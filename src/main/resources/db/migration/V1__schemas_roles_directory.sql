-- =============================================================================
-- school-app-server V1 — schemas, the application role, and the thin directory cache.
--
-- The auth server (school-auth) is the only registry of branches (school_id) and users (user_id). This
-- database never generates either: directory.school / directory.app_user hold the auth-issued ids so that
-- school tables can reference them, and are written only from verified token claims (upsert functions
-- below, called by platform-core) or the nightly refresh from the auth server's internal API.
-- Roles, features and permissions are NOT cached here; they are read from the token on every request.
-- =============================================================================

-- Application role: the app server connects as a LOGIN member of this role (see docker/postgres/init),
-- never as the migration owner, so row-level security applies.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'schoolcrm_app') THEN
        CREATE ROLE schoolcrm_app NOLOGIN;
    END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS directory;
CREATE SCHEMA IF NOT EXISTS platform;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS academics;
CREATE SCHEMA IF NOT EXISTS operations;
CREATE SCHEMA IF NOT EXISTS assessment;
CREATE SCHEMA IF NOT EXISTS learning;
CREATE SCHEMA IF NOT EXISTS communication;
CREATE SCHEMA IF NOT EXISTS finance;
CREATE SCHEMA IF NOT EXISTS admissions;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS accounts;
CREATE SCHEMA IF NOT EXISTS library;
CREATE SCHEMA IF NOT EXISTS calendar;
CREATE SCHEMA IF NOT EXISTS hostel;
CREATE SCHEMA IF NOT EXISTS custody;
CREATE SCHEMA IF NOT EXISTS frontoffice;
CREATE SCHEMA IF NOT EXISTS hr;
CREATE SCHEMA IF NOT EXISTS security;
CREATE SCHEMA IF NOT EXISTS transport;
CREATE SCHEMA IF NOT EXISTS facility;
CREATE SCHEMA IF NOT EXISTS wellbeing;
CREATE SCHEMA IF NOT EXISTS discipline;
CREATE SCHEMA IF NOT EXISTS records;
CREATE SCHEMA IF NOT EXISTS compliance;
CREATE SCHEMA IF NOT EXISTS alumni;
CREATE SCHEMA IF NOT EXISTS placement;
CREATE SCHEMA IF NOT EXISTS store;

-- ---------------------------------------------------------------------------
-- Request context (set with SET LOCAL by platform-core in every transaction)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION platform.current_school_ids() RETURNS BIGINT[]
LANGUAGE sql STABLE AS $$
    SELECT coalesce(string_to_array(nullif(current_setting('app.school_ids', TRUE), ''), ',')::BIGINT[], '{}'::BIGINT[]);
$$;

CREATE OR REPLACE FUNCTION platform.current_org_ids() RETURNS BIGINT[]
LANGUAGE sql STABLE AS $$
    SELECT coalesce(string_to_array(nullif(current_setting('app.org_ids', TRUE), ''), ',')::BIGINT[], '{}'::BIGINT[]);
$$;

CREATE OR REPLACE FUNCTION platform.current_user_id() RETURNS BIGINT
LANGUAGE sql STABLE AS $$
    SELECT nullif(current_setting('app.user_id', TRUE), '')::BIGINT;
$$;

CREATE OR REPLACE FUNCTION platform.rls_bypass() RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT coalesce(current_setting('app.rls_bypass', TRUE), '') = 'on';
$$;

-- ---------------------------------------------------------------------------
-- Directory cache (auth ids; never generated here)
-- ---------------------------------------------------------------------------
CREATE TABLE directory.school (
    school_id             BIGINT PRIMARY KEY,                 -- auth school_id
    organization_id       BIGINT       NOT NULL,              -- auth organization id; no FK (other database)
    school_code           TEXT         NOT NULL UNIQUE,
    school_name           TEXT         NOT NULL,
    branch_code           TEXT         NOT NULL,
    branch_name           TEXT         NOT NULL,
    institution_type_code TEXT         NOT NULL
        CHECK (institution_type_code IN ('SCHOOL', 'COLLEGE', 'UNIVERSITY', 'INSTITUTE', 'TUITION_CENTRE')),
    terminology           JSONB        NOT NULL DEFAULT '{}'::jsonb,
    timezone              TEXT         NOT NULL DEFAULT 'Asia/Kolkata',
    status                TEXT         NOT NULL CHECK (status IN ('ONBOARDING', 'ACTIVE', 'SUSPENDED', 'INACTIVE')),
    last_seen_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    refreshed_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE directory.app_user (
    user_id        BIGINT PRIMARY KEY,                        -- auth user_id
    first_name     TEXT        NOT NULL,
    last_name      TEXT        NOT NULL DEFAULT '',
    phone_number   TEXT,
    email          TEXT,
    user_category  TEXT        NOT NULL CHECK (user_category IN ('STAFF', 'NON_STAFF', 'PARENT', 'STUDENT')),
    is_active_flag BOOLEAN     NOT NULL DEFAULT TRUE,
    last_seen_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    refreshed_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Cursor of the nightly refresh per branch
CREATE TABLE directory.sync_state (
    school_id       BIGINT PRIMARY KEY REFERENCES directory.school (school_id),
    last_synced_at  TIMESTAMPTZ,
    last_status     TEXT CHECK (last_status IN ('OK', 'FAILED')),
    last_error      TEXT,
    users_refreshed INTEGER
);

-- Writes go through these functions only. SECURITY DEFINER: they run as the owner, the app role can't
-- touch the tables directly. Called with verified JWT claims; last_seen_at is written at most every 5 min.
CREATE OR REPLACE FUNCTION directory.upsert_school_from_token(
    p_school_id BIGINT, p_organization_id BIGINT, p_school_code TEXT, p_school_name TEXT, p_branch_code TEXT,
    p_branch_name TEXT, p_institution_type_code TEXT, p_terminology JSONB, p_timezone TEXT, p_status TEXT)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = directory, pg_temp AS $$
BEGIN
    INSERT INTO directory.school AS s (school_id, organization_id, school_code, school_name, branch_code, branch_name,
                                       institution_type_code, terminology, timezone, status)
    VALUES (p_school_id, p_organization_id, p_school_code, p_school_name, p_branch_code, p_branch_name,
            p_institution_type_code, coalesce(p_terminology, '{}'::jsonb), coalesce(p_timezone, 'Asia/Kolkata'), p_status)
    ON CONFLICT (school_id) DO UPDATE
    SET organization_id = EXCLUDED.organization_id, school_code = EXCLUDED.school_code,
        school_name = EXCLUDED.school_name, branch_code = EXCLUDED.branch_code, branch_name = EXCLUDED.branch_name,
        institution_type_code = EXCLUDED.institution_type_code, terminology = EXCLUDED.terminology,
        timezone = EXCLUDED.timezone, status = EXCLUDED.status,
        last_seen_at = CASE WHEN s.last_seen_at < now() - INTERVAL '5 minutes' THEN now() ELSE s.last_seen_at END
    WHERE (s.school_code, s.school_name, s.branch_code, s.branch_name, s.institution_type_code, s.terminology,
           s.timezone, s.status, s.organization_id)
          IS DISTINCT FROM (EXCLUDED.school_code, EXCLUDED.school_name, EXCLUDED.branch_code, EXCLUDED.branch_name,
                            EXCLUDED.institution_type_code, EXCLUDED.terminology, EXCLUDED.timezone, EXCLUDED.status,
                            EXCLUDED.organization_id)
       OR s.last_seen_at < now() - INTERVAL '5 minutes';
END $$;

CREATE OR REPLACE FUNCTION directory.upsert_user_from_token(
    p_user_id BIGINT, p_first_name TEXT, p_last_name TEXT, p_phone_number TEXT, p_email TEXT,
    p_user_category TEXT, p_is_active BOOLEAN)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = directory, pg_temp AS $$
BEGIN
    INSERT INTO directory.app_user AS u (user_id, first_name, last_name, phone_number, email, user_category, is_active_flag)
    VALUES (p_user_id, p_first_name, coalesce(p_last_name, ''), p_phone_number, p_email, p_user_category, coalesce(p_is_active, TRUE))
    ON CONFLICT (user_id) DO UPDATE
    SET first_name = EXCLUDED.first_name, last_name = EXCLUDED.last_name, phone_number = EXCLUDED.phone_number,
        email = EXCLUDED.email, user_category = EXCLUDED.user_category, is_active_flag = EXCLUDED.is_active_flag,
        last_seen_at = CASE WHEN u.last_seen_at < now() - INTERVAL '5 minutes' THEN now() ELSE u.last_seen_at END
    WHERE (u.first_name, u.last_name, u.phone_number, u.email, u.user_category, u.is_active_flag)
          IS DISTINCT FROM (EXCLUDED.first_name, EXCLUDED.last_name, EXCLUDED.phone_number, EXCLUDED.email,
                            EXCLUDED.user_category, EXCLUDED.is_active_flag)
       OR u.last_seen_at < now() - INTERVAL '5 minutes';
END $$;

-- Nightly refresh (users who haven't signed in): same rules, without touching last_seen_at
CREATE OR REPLACE FUNCTION directory.refresh_user(
    p_user_id BIGINT, p_first_name TEXT, p_last_name TEXT, p_phone_number TEXT, p_email TEXT,
    p_user_category TEXT, p_is_active BOOLEAN)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = directory, pg_temp AS $$
    INSERT INTO directory.app_user (user_id, first_name, last_name, phone_number, email, user_category, is_active_flag)
    VALUES (p_user_id, p_first_name, coalesce(p_last_name, ''), p_phone_number, p_email, p_user_category, coalesce(p_is_active, TRUE))
    ON CONFLICT (user_id) DO UPDATE
    SET first_name = EXCLUDED.first_name, last_name = EXCLUDED.last_name, phone_number = EXCLUDED.phone_number,
        email = EXCLUDED.email, user_category = EXCLUDED.user_category, is_active_flag = EXCLUDED.is_active_flag,
        refreshed_at = now();
$$;

REVOKE ALL ON FUNCTION directory.upsert_school_from_token(BIGINT, BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION directory.upsert_user_from_token(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION directory.refresh_user(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION directory.upsert_school_from_token(BIGINT, BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT, TEXT) TO schoolcrm_app;
GRANT EXECUTE ON FUNCTION directory.upsert_user_from_token(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO schoolcrm_app;
GRANT EXECUTE ON FUNCTION directory.refresh_user(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO schoolcrm_app;

GRANT USAGE ON SCHEMA directory, platform TO schoolcrm_app;
GRANT SELECT ON directory.school, directory.app_user TO schoolcrm_app;
GRANT SELECT, INSERT, UPDATE ON directory.sync_state TO schoolcrm_app;
GRANT EXECUTE ON FUNCTION platform.current_school_ids(), platform.current_org_ids(), platform.current_user_id(),
    platform.rls_bypass() TO schoolcrm_app;
