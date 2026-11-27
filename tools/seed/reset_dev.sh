#!/bin/bash
# Empties every branch table of the school DB (keeps directory.* and Flyway history) and loads the dev seed again.
#   tools/seed/reset_dev.sh   (runs psql as the postgres OS user; set PSQL to override)
set -euo pipefail
cd "$(dirname "$0")/../.."
PSQL=${PSQL:-"sudo -u postgres psql -q -v ON_ERROR_STOP=1 -d school_app_db"}
$PSQL <<'SQL'
DO $$
DECLARE t TEXT;
BEGIN
  SELECT string_agg(format('%I.%I', schemaname, tablename), ', ') INTO t FROM pg_tables
   WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'directory', 'api')
     AND NOT (schemaname = 'platform' AND tablename = 'flyway_schema_history');
  EXECUTE 'TRUNCATE ' || t || ' RESTART IDENTITY CASCADE';
END $$;
SQL
$PSQL -f tools/seed/dev_seed.sql
echo "dev seed reloaded"
