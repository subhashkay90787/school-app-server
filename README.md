# school-app-server

SchoolCRM app server: the school-side API behind the Flutter app (Android, iOS, web). One image serves a
single self-hosted school or the hosted multi-tenant deployment; every row is scoped by the `school_id`
issued by **school-auth**. Without a school-auth access token it serves nothing.

## Layout

```
src/main/resources/openapi/        API contracts (generated, see below)
  <actor>.yaml                     one spec per actor; base path /api/v1/<actor>
  school-app-api.yaml              all actors in one file (docs, Dart client)
  role-routes.json                 /api/v1/<actor> -> base roles allowed
src/main/resources/db/migration/   Flyway: V1 schemas + directory cache (hand-written), V2-V4 generated from ER v5
src/main/java/com/school/app/
  core/                            platform-core: security (JWKS), tenant, access, RLS transactions, directory, nav
  role/<actor>/                    one package per actor: <Actor>Controller implements the generated <Actor>Api
  domain/<area>/                   domain services shared by role modules (calendar is the first)
tools/
  er_v5_school.dsl                 ER v5 school tables, one line per column (source for SQL and schemas)
  er2sql.py                        -> V2 tables, V3 foreign keys, V4 RLS / grants / ledger rules
  openapi/                         gen_openapi.py, actors.py (endpoints), views.py (screen models), spec.py
```

### Actor modules (UX v2)

| Package | Base role(s) | Ops | Package | Base role(s) | Ops |
|---|---|---|---|---|---|
| `common` | any | 40 | `chiefwarden` | CHIEF_WARDEN | 28 |
| `admin` | ADMIN | 17 | `warden` | WARDEN | 21 |
| `principal` | PRINCIPAL | 24 | `matron` | MATRON | 11 |
| `schooladmin` | SCHOOL_ADMIN (SYS_ADMIN alias) | 70 | `nurse` | NURSE | 12 |
| `accountant` | ACCOUNTANT | 34 | `messmanager` | MESS_MANAGER | 14 |
| `hrmanager` | HR_MANAGER | 30 | `security` | SECURITY | 24 |
| `admissionofficer` | ADMISSION_OFFICER | 22 | `securitysupervisor` | SECURITY_SUPERVISOR | 17 |
| `receptionist` | RECEPTIONIST | 15 | `staff` | STAFF | 10 |
| `teacher` | TEACHER | 39 | `storekeeper` | STORE_KEEPER | 30 |
| `parent` | PARENT | 34 | `transportmanager` | TRANSPORT_MANAGER (phase 2) | 19 |
| `student` | STUDENT (adults only) | 22 | `driver` | DRIVER (phase 2) | 10 |
| `assistant` | any, GET only (school-mcp) | 11 | | | **554** |

Custom roles have no package: school-auth puts their base role in the token's `base_roles`, so a
"Lab Assistant" based on TEACHER uses `/api/v1/teacher`, limited by its own permissions.

## How a request is checked

1. **Token** — RS256 JWT from school-auth, validated against its JWKS (`AUTH_ISSUER_URL`). Service tokens
   (client_credentials) are refused: `USER_TOKEN_REQUIRED`.
2. **Branch** — `X-School-Id` is required (except `/api/v1/common/me`) and must be in the token's
   `school_access`: `SCHOOL_REQUIRED` / `NOT_IN_SCHOOL`. The branch and user are upserted into the
   directory cache from the verified claims (at most every 5 min).
3. **Role module** — `/api/v1/<actor>/**` needs one of that actor's base roles: `WRONG_ROLE`.
4. **Feature + permission** — each operation's `@Access(feature, anyOf)` (from `x-access` in the spec):
   `FEATURE_OFF` / `MISSING_PERMISSION`.
5. **Rows** — every transaction starts with `SET LOCAL app.school_ids / app.user_id / app.org_ids`
   (`TenantAwareTransactionManager`); row-level security on all 210 tenant tables does the rest. Data scope
   inside a branch (own class, own rooms, own children) belongs in the domain services.

Unimplemented operations answer **501**. Implemented so far: `GET /common/me`, `GET /common/me/navigation`,
`GET /common/calendar`.

## Adding or changing an endpoint

1. Edit `tools/openapi/actors.py` (and `views.py` for a new screen model), then
   `python3 tools/openapi/gen_openapi.py`. Entity bodies come from `tools/er_v5_school.dsl`.
2. `mvn generate-sources` regenerates `com.school.app.role.<actor>.api.<Actor>Api`.
3. Override the method in `<Actor>Controller`, calling a service in `com.school.app.domain.<area>`.
   Role modules call domains only, never another role module.

## Database

- `directory.school` / `directory.app_user` hold auth ids only; written through
  `directory.upsert_*_from_token` (SECURITY DEFINER) and the nightly refresh (`DIRECTORY_SYNC_*`, calls
  school-auth `/internal/v1/...`). Roles, features and permissions are never stored here.
- Every tenant table has `school_id` and `UNIQUE (school_id, pk)`; all references to tenant rows are
  composite `(school_id, x_id)` so a row can never point into another branch.
- Append-only ledgers (custody events, wallet, payment allocations, punches, consent records, stock ledger,
  gate movements, patrol scans, flow log, audit log), one current academic year, one active bed per
  student/bed, four-eyes checks on presence corrections and leave.
- The app connects as `schoolcrm_api` (member of `schoolcrm_app`); Flyway runs as the owner. Using the owner
  for traffic would skip RLS.
- After a migration is applied anywhere, don't regenerate it: write a new `V<n>__*.sql` by hand.

## Run

Local (Postgres 16, school-auth on :8080):

```
createdb school_app_db
psql -c "CREATE ROLE schoolcrm_app NOLOGIN" -c "CREATE ROLE schoolcrm_api LOGIN PASSWORD 'api' IN ROLE schoolcrm_app"
mvn spring-boot:run     # :8081, Swagger UI at /swagger-ui.html (one group per actor)
```

Docker: `cp .env.example .env`, set the passwords and `AUTH_ISSUER_URL`, then `docker compose up -d`.
Postgres data lives in `PG_DATA_DIR`; the `backup` service writes nightly `pg_dump`s (14 daily, 8 weekly) to
`BACKUP_DIR`.

## Not built yet

- Domain services behind the 551 stub operations; business-rule triggers from Schema v5 beyond those in V4
  (custody release rules, outing ban, payment allocation, stock posting, no-dues clearance).
- Consent gate (`CONSENT_REQUIRED`), idempotency store for `Idempotency-Key`, outbox delivery
  (WhatsApp / email / push), news media storage adapters (Drive / Dropbox).
- NOT NULL beyond keys and required ER columns; review per table when implementing its domain.
