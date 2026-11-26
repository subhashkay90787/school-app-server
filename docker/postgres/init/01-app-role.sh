#!/bin/sh
# Runs once, on an empty data directory. Creates the login role the app server uses: a member of
# schoolcrm_app, so row-level security applies (the Flyway owner bypasses RLS and must not serve traffic).
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'schoolcrm_app') THEN
        CREATE ROLE schoolcrm_app NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${APP_DB_USER}') THEN
        CREATE ROLE ${APP_DB_USER} LOGIN PASSWORD '${APP_DB_PASSWORD}' IN ROLE schoolcrm_app;
    END IF;
END
\$\$;
SQL
