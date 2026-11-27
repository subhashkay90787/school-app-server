-- Helpers for the screen queries in src/main/resources/views/*.sql (core.data.Views). Repeatable migration:
-- every object is CREATE OR REPLACE, so edits here are re-applied by Flyway when the file changes.
-- All SECURITY INVOKER and STABLE: they run as the API role, so row-level security applies inside them too.

CREATE SCHEMA IF NOT EXISTS api;

-- Display name of a section ("5-A"; section names are unique per academic year)
CREATE OR REPLACE FUNCTION api.section_label(p_class_section_id BIGINT) RETURNS TEXT
    LANGUAGE sql STABLE AS $$
    SELECT cs.section_name FROM academics.class_section cs WHERE cs.class_section_id = p_class_section_id
$$;

CREATE OR REPLACE FUNCTION api.user_name(p_user_id BIGINT) RETURNS TEXT
    LANGUAGE sql STABLE AS $$
    SELECT btrim(u.first_name || ' ' || coalesce(u.last_name, '')) FROM directory.app_user u WHERE u.user_id = p_user_id
$$;

-- PersonRef for a user (staff, parent)
CREATE OR REPLACE FUNCTION api.person(p_user_id BIGINT, p_label TEXT DEFAULT NULL) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN p_user_id IS NULL THEN NULL ELSE jsonb_strip_nulls(jsonb_build_object(
        'userId', p_user_id, 'name', coalesce(api.user_name(p_user_id), 'User ' || p_user_id), 'label', p_label)) END
$$;

-- PersonRef for a student (label = class section unless given)
CREATE OR REPLACE FUNCTION api.student_ref(p_student_id BIGINT, p_label TEXT DEFAULT NULL) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'studentId', s.student_id, 'userId', s.student_user_id,
        'name', btrim(s.first_name || ' ' || coalesce(s.last_name, '')), 'photoUrl', s.photo_url,
        'label', coalesce(p_label, api.section_label(s.class_section_id))))
    FROM academics.student s WHERE s.student_id = p_student_id
$$;

-- Where a hosteller is right now: SICK_BAY / ON_OUTING (OVERDUE -> MISSING) / IN_HOSTEL; NULL for day scholars
CREATE OR REPLACE FUNCTION api.hostel_status(p_student_id BIGINT) RETURNS TEXT
    LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN NOT EXISTS (SELECT 1 FROM hostel.allocation a WHERE a.student_id = p_student_id AND a.status = 'ACTIVE') THEN NULL
        WHEN EXISTS (SELECT 1 FROM wellbeing.infirmary_visit v WHERE v.person_kind = 'STUDENT' AND v.person_id = p_student_id
                     AND v.disposition = 'SICK_BAY' AND v.discharged_at IS NULL) THEN 'SICK_BAY'
        WHEN EXISTS (SELECT 1 FROM hostel.outing_request o WHERE o.student_id = p_student_id AND o.status = 'OVERDUE') THEN 'MISSING'
        WHEN EXISTS (SELECT 1 FROM hostel.outing_request o WHERE o.student_id = p_student_id AND o.status = 'OUT'
                     AND o.outing_type IN ('HOME_LEAVE', 'VACATION', 'WEEKEND_HOME')) THEN 'ON_LEAVE'
        WHEN EXISTS (SELECT 1 FROM hostel.outing_request o WHERE o.student_id = p_student_id AND o.status = 'OUT') THEN 'ON_OUTING'
        ELSE 'IN_HOSTEL' END
$$;

-- Today's attendance word for a student: ABSENT / LATE / PRESENT / ON_LEAVE ... or NULL when not taken yet
CREATE OR REPLACE FUNCTION api.attendance_today(p_student_id BIGINT, p_date DATE DEFAULT current_date) RETURNS TEXT
    LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT d.status FROM operations.daily_presence d WHERE d.person_kind = 'STUDENT' AND d.person_id = p_student_id
           AND d.presence_date = p_date ORDER BY d.presence_id DESC LIMIT 1),
        (SELECT CASE WHEN bool_or(a.class_section_period_id IS NULL) THEN 'ABSENT' ELSE 'PARTIAL' END
           FROM operations.student_absence a WHERE a.student_id = p_student_id AND a.date = p_date HAVING count(*) > 0))
$$;

-- ChildSummary card for parent / assistant screens
CREATE OR REPLACE FUNCTION api.child_summary(p_student_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM academics.student WHERE student_id = p_student_id),
         st AS (SELECT api.hostel_status(p_student_id) AS hostel, api.attendance_today(p_student_id) AS att,
                       (SELECT coalesce(sum(f.remaining_due), 0) FROM finance.fee f WHERE f.student_id = p_student_id
                          AND f.status IN ('DUE', 'PART_PAID') AND f.due_date < current_date) AS overdue)
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'studentId', s.student_id, 'name', btrim(s.first_name || ' ' || coalesce(s.last_name, '')),
        'photoUrl', s.photo_url, 'classSection', api.section_label(s.class_section_id),
        'branchName', (SELECT ds.branch_name FROM directory.school ds WHERE ds.school_id = s.school_id),
        'schoolId', s.school_id, 'residency', s.residency_type,
        'statusDot', CASE WHEN st.hostel = 'MISSING' THEN 'RED'
                          WHEN st.att IN ('ABSENT', 'PARTIAL') OR st.hostel = 'SICK_BAY' OR st.overdue > 0 THEN 'AMBER'
                          ELSE 'GREEN' END,
        'statusText', CASE WHEN st.hostel = 'MISSING' THEN 'Not back from outing'
                           WHEN st.hostel = 'SICK_BAY' THEN 'In sick bay'
                           WHEN st.hostel IN ('ON_OUTING', 'ON_LEAVE') THEN 'Out on pass'
                           WHEN st.att = 'ABSENT' THEN 'Absent today'
                           WHEN st.att = 'PARTIAL' THEN 'Missed some periods today'
                           WHEN st.att = 'LATE' THEN 'Late today'
                           WHEN st.overdue > 0 THEN 'Fees overdue'
                           WHEN st.hostel = 'IN_HOSTEL' THEN 'In hostel'
                           WHEN st.att IS NOT NULL THEN 'In school'
                           ELSE 'All well' END))
    FROM s, st
$$;

-- Home card; NULL (dropped from the feed) when a count is given and it is zero
CREATE OR REPLACE FUNCTION api.card(p_id TEXT, p_section TEXT, p_kind TEXT, p_title TEXT, p_subtitle TEXT,
                                    p_count BIGINT, p_severity TEXT, p_deep_link TEXT,
                                    p_due_at TIMESTAMPTZ DEFAULT NULL, p_payload JSONB DEFAULT NULL) RETURNS JSONB
    LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_count IS NOT NULL AND p_count = 0 THEN NULL ELSE jsonb_strip_nulls(jsonb_build_object(
        'id', p_id, 'section', p_section, 'kind', p_kind, 'title', p_title, 'subtitle', p_subtitle, 'count', p_count,
        'severity', p_severity, 'dueAt', p_due_at, 'deepLink', p_deep_link, 'payload', p_payload)) END
$$;

-- HomeFeed: cards in section order (Critical -> Needs you -> Now -> Today -> Feed), empty ones dropped
CREATE OR REPLACE FUNCTION api.feed(p_role TEXT, VARIADIC p_cards JSONB[]) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    WITH c AS (SELECT card, ord FROM unnest(p_cards) WITH ORDINALITY AS u(card, ord) WHERE card IS NOT NULL)
    SELECT jsonb_build_object(
        'generatedAt', now(), 'role', p_role,
        'cards', coalesce((SELECT jsonb_agg(card ORDER BY array_position(
            ARRAY['CRITICAL', 'NEEDS_YOU', 'NOW', 'TODAY', 'FEED'], card ->> 'section'), ord) FROM c), '[]'::jsonb),
        'allCaughtUp', NOT EXISTS (SELECT 1 FROM c WHERE card ->> 'section' IN ('CRITICAL', 'NEEDS_YOU')))
$$;

-- Children of the calling parent in the current branch(es)
CREATE OR REPLACE FUNCTION api.my_children() RETURNS SETOF BIGINT
    LANGUAGE sql STABLE AS $$
    SELECT sp.student_id FROM academics.student_parent sp WHERE sp.user_id = platform.current_user_id()
$$;

-- Student record of the calling student
CREATE OR REPLACE FUNCTION api.my_student() RETURNS BIGINT
    LANGUAGE sql STABLE AS $$
    SELECT s.student_id FROM academics.student s WHERE s.student_user_id = platform.current_user_id()
    ORDER BY s.student_id DESC LIMIT 1
$$;

-- Sections the calling teacher class-teaches or teaches in (timetable or offering)
CREATE OR REPLACE FUNCTION api.my_sections() RETURNS SETOF BIGINT
    LANGUAGE sql STABLE AS $$
    SELECT cs.class_section_id FROM academics.class_section cs WHERE cs.teacher_user_id = platform.current_user_id()
    UNION
    SELECT csp.class_section_id FROM academics.timetable tt
      JOIN academics.class_section_period csp ON csp.class_section_period_id = tt.class_section_period_id
      JOIN academics.staff_subject ss ON ss.staff_subject_id = tt.staff_subject_id
     WHERE ss.user_id = platform.current_user_id()
    UNION
    SELECT co.class_section_id FROM academics.course_offering co
      JOIN academics.staff_subject ss ON ss.staff_subject_id = co.staff_subject_id
     WHERE ss.user_id = platform.current_user_id() AND co.class_section_id IS NOT NULL
$$;

-- Hostels the calling hostel staff member is assigned to today
CREATE OR REPLACE FUNCTION api.my_hostels() RETURNS SETOF BIGINT
    LANGUAGE sql STABLE AS $$
    SELECT DISTINCT sa.hostel_id FROM hostel.staff_assignment sa
     WHERE sa.user_id = platform.current_user_id() AND sa.from_date <= current_date
       AND (sa.to_date IS NULL OR sa.to_date >= current_date)
$$;

-- Today's weekday code as used by timetable / menus (MON..SUN)
CREATE OR REPLACE FUNCTION api.dow(p_date DATE) RETURNS TEXT
    LANGUAGE sql IMMUTABLE AS $$
    SELECT (ARRAY['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'])[extract(isodow FROM p_date)::int]
$$;

-- "09:00-09:45" style period_time -> start / end
CREATE OR REPLACE FUNCTION api.period_start(p_period_time TEXT) RETURNS TIME
    LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_period_time ~ '^\d{1,2}:\d{2}' THEN substring(p_period_time FROM '^(\d{1,2}:\d{2})')::time END
$$;
CREATE OR REPLACE FUNCTION api.period_end(p_period_time TEXT) RETURNS TIME
    LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_period_time ~ '\d{1,2}:\d{2}\s*$' THEN substring(p_period_time FROM '(\d{1,2}:\d{2})\s*$')::time END
$$;

-- Row as API JSON: snake_case keys -> camelCase (top level), e.g. api.camel(to_jsonb(h)) for an embedded entity
CREATE OR REPLACE FUNCTION api.camel(p JSONB) RETURNS JSONB
    LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p IS NULL OR jsonb_typeof(p) <> 'object' THEN p ELSE coalesce((
        SELECT jsonb_object_agg(
                 (SELECT string_agg(CASE WHEN i = 1 THEN w ELSE initcap(w) END, '' ORDER BY i)
                    FROM unnest(string_to_array(k, '_')) WITH ORDINALITY AS t(w, i)), v)
          FROM jsonb_each(p) AS e(k, v)), '{}'::jsonb) END
$$;

-- Page envelope {items, page, size, total} from an ordered JSON array (page/size as given by the API, text)
CREATE OR REPLACE FUNCTION api.page(p_all JSONB, p_page TEXT, p_size TEXT) RETURNS JSONB
    LANGUAGE sql IMMUTABLE AS $$
    WITH a AS (SELECT coalesce(p_all, '[]'::jsonb) AS arr,
                      greatest(coalesce(p_page::int, 0), 0) AS pg,
                      least(greatest(coalesce(p_size::int, 50), 1), 200) AS sz)
    SELECT jsonb_build_object(
        'items', coalesce((SELECT jsonb_agg(e ORDER BY o) FROM jsonb_array_elements(a.arr) WITH ORDINALITY AS x(e, o)
                            WHERE o > a.pg * a.sz AND o <= (a.pg + 1) * a.sz), '[]'::jsonb),
        'page', a.pg, 'size', a.sz, 'total', jsonb_array_length(a.arr))
    FROM a
$$;

-- Duties of the calling user right now (navigation overlays, UX v2): class teacher, subject teacher,
-- invigilation and escort assignments, hostel warden duties, hostel night roster
CREATE OR REPLACE FUNCTION api.my_duties() RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT coalesce(jsonb_agg(d ORDER BY d ->> 'kind', d ->> 'label'), '[]'::jsonb) FROM (
        SELECT jsonb_build_object('kind', 'CLASS_TEACHER', 'refId', cs.class_section_id, 'label', 'Class teacher ' || cs.section_name) AS d
          FROM academics.class_section cs JOIN academics.academic_year y ON y.academic_year_id = cs.academic_year_id AND y.is_current
         WHERE cs.teacher_user_id = platform.current_user_id()
        UNION ALL
        SELECT jsonb_build_object('kind', 'SUBJECT_TEACHER', 'refId', ss.staff_subject_id, 'label', sub.subject_name)
          FROM academics.staff_subject ss JOIN academics.subject sub ON sub.subject_id = ss.subject_id
         WHERE ss.user_id = platform.current_user_id()
        UNION ALL
        SELECT jsonb_strip_nulls(jsonb_build_object('kind', 'INVIGILATOR', 'refId', e.exam_id, 'label', 'Invigilation: ' || e.exam_name,
               'from', (e.exam_date + coalesce(e.start_time, time '00:00'))::timestamptz,
               'to', (e.exam_date + coalesce(e.start_time, time '00:00'))::timestamptz + make_interval(mins => coalesce(e.duration_minutes, 60))))
          FROM assessment.exams e
         WHERE e.exam_date >= current_date AND (e.invigilated_by_user_id = platform.current_user_id()
               OR EXISTS (SELECT 1 FROM assessment.invigilation_duty i WHERE i.exam_id = e.exam_id AND i.user_id = platform.current_user_id()))
        UNION ALL
        SELECT jsonb_strip_nulls(jsonb_build_object('kind', 'ESCORT', 'refId', g.group_id, 'label', 'Escort: ' || g.title,
               'from', g.campus_departure_at, 'to', g.carrier_departure_at))
          FROM hostel.outing_group g
         WHERE g.escort_user_id = platform.current_user_id() AND g.status IN ('PLANNED', 'DEPARTED')
        UNION ALL
        SELECT jsonb_build_object('kind', sa.duty, 'refId', sa.assignment_id, 'label', initcap(replace(sa.duty, '_', ' ')) || ', ' || h.name)
          FROM hostel.staff_assignment sa JOIN hostel.hostel h ON h.hostel_id = sa.hostel_id
         WHERE sa.user_id = platform.current_user_id() AND sa.from_date <= current_date AND (sa.to_date IS NULL OR sa.to_date >= current_date)
           AND sa.duty IN ('BLOCK_WARDEN', 'FLOOR_WARDEN', 'ROOM_WARDEN', 'ASSISTANT_WARDEN')
        UNION ALL
        SELECT jsonb_build_object('kind', 'NIGHT_WARDEN', 'refId', r.roster_entry_id, 'label', 'Night duty ' || p.code,
               'from', (r.duty_date + sh.start_time)::timestamptz,
               'to', (r.duty_date + sh.end_time + CASE WHEN sh.crosses_midnight THEN interval '1 day' ELSE interval '0' END)::timestamptz)
          FROM hr.roster_entry r JOIN hr.post p ON p.post_id = r.post_id JOIN hr.shift sh ON sh.shift_id = r.shift_id
         WHERE r.user_id = platform.current_user_id() AND r.duty_date = current_date AND p.post_type = 'HOSTEL_NIGHT'
           AND r.status IN ('PLANNED', 'ON_DUTY')
    ) x(d)
$$;

GRANT USAGE ON SCHEMA api TO schoolcrm_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO schoolcrm_app;
