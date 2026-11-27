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
  core/data/                       CRUD engine (EntityStore, Crud, ScopeService) and screen queries (Views)
  role/<actor>/                    one package per actor: <Actor>Crud (generated) and <Actor>Controller
  domain/<area>/                   domain services shared by role modules (calendar is the first)
src/main/resources/views/<actor>.sql   one SQL statement per screen operation (see "How operations are served")
src/main/resources/schema/tables.json  table metadata for the CRUD engine (generated)
tools/
  er_v5_school.dsl                 ER v5 school tables, one line per column (source for SQL and schemas)
  er2sql.py                        -> V2 tables, V3 foreign keys, V4 RLS / grants / ledger rules
  openapi/                         gen_openapi.py, actors.py (endpoints), views.py (screen models), spec.py,
                                   gen_crud.py (<Actor>Crud classes), crud-report.md (which op is served how)
  seed/                            dev data (dev_seed.sql, auth_dev_users.sql, reset_dev.sh) and
                                   contract_test.py / viewq.py / call.py for checking against it
```

### Actor modules (UX v2)

| Package | Base role(s) | Ops | Package | Base role(s) | Ops |
|---|---|---|---|---|---|
| `common` | any | 44 | `chiefwarden` | CHIEF_WARDEN | 34 |
| `admin` | ADMIN | 21 | `warden` | WARDEN | 24 |
| `principal` | PRINCIPAL | 28 | `matron` | MATRON | 13 |
| `schooladmin` | SCHOOL_ADMIN (SYS_ADMIN alias) | 85 | `nurse` | NURSE | 14 |
| `accountant` | ACCOUNTANT | 43 | `messmanager` | MESS_MANAGER | 17 |
| `hrmanager` | HR_MANAGER | 38 | `security` | SECURITY | 25 |
| `admissionofficer` | ADMISSION_OFFICER | 24 | `securitysupervisor` | SECURITY_SUPERVISOR | 22 |
| `receptionist` | RECEPTIONIST | 20 | `staff` | STAFF | 13 |
| `teacher` | TEACHER | 47 | `storekeeper` | STORE_KEEPER | 37 |
| `parent` | PARENT | 40 | `transportmanager` | TRANSPORT_MANAGER (phase 2) | 24 |
| `student` | STUDENT (adults only) | 27 | `driver` | DRIVER (phase 2) | 12 |
| `assistant` | any, GET only (school-mcp) | 11 | | | **663** |

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

Unimplemented operations answer **501** (the flows: notifications, reminders, approval routing, payment
gateway, file storage, generators). See `tools/openapi/crud-report.md`.

## How operations are served

Of the 663 operations, 609 are served today:

| How | Ops | Where |
|---|---|---|
| **Generic CRUD** | 366 | `<Actor>Crud` (generated) → `core.data.Crud` → `EntityStore`. Operations whose request and response map onto one table: list / page / get / create / update (PUT = only the fields sent) / upsert / delete. |
| **Screen queries** | 243 | `src/main/resources/views/<actor>.sql`, run by `core.data.Views`: homes, dashboards, registers, marks sheets, outings, roll calls, gate, patrol ... and the writes with their own rules (submit register, save marks, counter payment, bookings, soft deletes). |
| **Java** | 3 | `CommonController`: me, navigation, calendar. |
| **501** | 54 | flows and files, built with the flow framework. |

- **Scope inside a branch** (`ScopeService`): parent = own children, student = own record, teacher = own
  sections / subjects / invigilation, warden / matron / chief warden = assigned hostels, driver = own trips,
  "my ..." operations = rows owned by the caller. Ids in the path, filters and bodies are checked first:
  outside the scope answers **404**, so another family's records are not even confirmed to exist.
- **Screen query format**: `-- name: <operationId>` (add `write` for changes), one statement returning the
  whole response as one JSON value. Parameters bind by name as text (`:studentId::bigint`); `:me`, `:school`
  and `:body` (request JSON) are always there. A write that must return the changed rows splits with
  `-- then` (first statement returns `result`, the second builds the response). Shared builders
  (`api.outing_view`, `api.family_dues`, `api.register_sheet`, `api.feed` / `api.card` for homes ...) are in
  the repeatable migrations `R__api_*.sql`.
- **Errors**: validation 400 (`VALIDATION` with field list), unknown reference / bad value 400, duplicate or
  still-in-use 409, rule triggers 409 (`RULE`), out of scope 404.
- Generated document numbers (certificate, expense voucher, application, requisition, PO, GRN) come from
  `EntityStore.GENERATED`; times are in the branch's time zone (set per transaction).
- Org-wide administrators read all their branches on `GET /admin/...?scope=ALL_BRANCHES` and
  `/admin/branches/comparison` (RLS widened for that GET only).

## Adding or changing an endpoint

1. Edit `tools/openapi/actors.py` (and `views.py` for a new screen model), then
   `python3 tools/openapi/gen_openapi.py`. Entity bodies come from `tools/er_v5_school.dsl`.
2. `mvn generate-sources` regenerates `com.school.app.role.<actor>.api.<Actor>Api`.
3. A screen or a write with its own rules: add a `-- name: <operationId>` block to `views/<actor>.sql`
   (try it with `python3 tools/seed/viewq.py <actor> <userId> <operationId> name=value ...`).
4. `python3 tools/openapi/gen_crud.py` regenerates the `<Actor>Crud` classes and `crud-report.md`.
5. A flow (notifications, approvals, payments): override the method in `<Actor>Controller` and call a
   service in `com.school.app.domain.<area>`. Role modules call domains only, never another role module.

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

Dev data and checks (school-auth on :8080 with OTP codes in its log):

```
psql -d school_platform_db -f tools/seed/auth_dev_users.sql   # one login per actor, branch 1
tools/seed/reset_dev.sh                                       # empty the school DB and load tools/seed/dev_seed.sql
python3 tools/seed/contract_test.py [--writes]                # every operation of every actor; fails on 5xx
python3 tools/seed/call.py parent GET /children               # one call as an actor's dev user
```

Docker: `cp .env.example .env`, set the passwords and `AUTH_ISSUER_URL`, then `docker compose up -d`.
Postgres data lives in `PG_DATA_DIR`; the `backup` service writes nightly `pg_dump`s (14 daily, 8 weekly) to
`BACKUP_DIR`.

## Not built yet

- The 54 flow / file operations (501): approvals routing (decide, submit expense / PO / payroll / audit),
  payment gateway (start / confirm / top-up), notifications delivery, receipts / payslips / report-card PDFs,
  uploads, imports, hall tickets / seating / fee demand generators, masked calls, offline batch sync.
- Business-rule triggers from Schema v5 beyond those in V4 (custody release rules, outing ban, no-dues clearance).
- Consent gate (`CONSENT_REQUIRED`), idempotency store for `Idempotency-Key`, outbox delivery
  (WhatsApp / email / push), news media storage adapters (Drive / Dropbox).
- NOT NULL beyond keys and required ER columns; review per table when implementing its domain.
