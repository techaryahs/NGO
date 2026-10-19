# Independent backend, PostgreSQL, importer and Flutter audit

**16 October 2026 — production cutover is not approved.**

The implemented backend's tested workflows now retain consistent database state through admission, payment, attendance and discharge, including concurrent requests and injected failures. The application as a whole is not ready to migrate: Flutter domain adapters are missing, ERP and migration coverage is incomplete, the available source snapshot is inconsistent, and dependency advisories remain. No production cutover was performed.

## Evidence boundaries and isolation

The initial `git status --short`, `git diff --stat` and relevant source/diffs were inspected before editing. This checkout already contained substantial uncommitted migration and Flutter work; those edits were preserved. Existing installer/UI/Firebase changes were not reset. Nothing was committed.

Reviewed package manifests/lockfile, all backend routes, auth/config/pool/runner/importer, schema and tests, Dockerfile/Compose/environment/ignore files, Flutter config/locator/HTTP/Firebase/auth/domain services, models, Drift/PersistentCache, existing tests and available export/report structure. Prior reports' success claims were not accepted as test evidence.

- **No Computer Use, GUI automation, screenshots, screen recording or manual application navigation.** Existing headless Flutter widget tests are automated tests, not a Windows application runtime test.
- Docker CLI exists, but `docker version` and `docker ps` could not reach `dockerDesktopLinuxEngine`. No existing containers or volumes were changed.
- PostgreSQL 16 binaries were available. A new cluster was initialized under the OS temp directory `ngo-audit-pg16-20261016`, owned by the current OS user, bound only to `127.0.0.1:55439`. Runtime reported **PostgreSQL 16.12**. The separately installed PostgreSQL Windows service was not modified.
- Dedicated databases: `ngo_audit_workflows`, `ngo_audit_modules`, `ngo_audit_importer`, `ngo_audit_migrations`, `ngo_audit_auth`. Suites require explicit opt-in, local address/port, exact database name and real PostgreSQL-major assertions before mutations. Migration rollback and schema reset occurred only in the dedicated migrations database. No production database was dropped or truncated.
- All imported fixtures, requests, identities, photos and payments were synthetic. Existing sensitive snapshots were inspected locally for aggregate structure/counts only; no source records, identities, financial totals or photos were copied into tests or reports.
- The temporary cluster was stopped after verification; its synthetic files remain in the temp directory for review. The existing PostgreSQL Windows service remained running.
- API/database tests use Fastify injection and real PostgreSQL, with actual SQL assertions. Authentication uses real ephemeral RSA signatures and server-side users/roles; Google's certificate HTTP response is mocked. No live Firebase authentication/service call was tested.

## Final execution results

| Check | Final observed result | Evidence type |
|---|---|---|
| Baseline `npm test` | 15 tests successful; database calls mocked | Baseline unit/Fastify tests |
| Final `npm test -- --reporter=dot` | **70 passed, 71 skipped, 0 failed** | Mocked/unit suite; PostgreSQL suites deliberately opt-in |
| `workflows.integration.test.ts` | **18 passed, 0 failed** | Real API/PostgreSQL workflows and catalog assertions |
| `modules.integration.test.ts` | **27 passed, 0 failed** | Real API/PostgreSQL module workflows |
| `importer.integration.test.ts` | **21 passed, 0 failed** | Real importer/PostgreSQL transactions |
| `auth_database.integration.test.ts` | **3 passed, 0 failed** | Signed Firebase-shaped tokens, real users and creator persistence |
| `migrations.integration.test.ts` | **1 passed, 0 failed** | Real fresh install, initialized upgrade, status, full disposable rollback/reapply |
| `persistence.integration.test.ts` | **1 passed, 0 failed** | Actual PostgreSQL outage, restart, safe readiness, persistence and pool recovery |
| Total distinct backend tests executed across final runs | **141 successful: 70 mocked/unit + 71 real PostgreSQL** | Not a claim that opt-in suites ran during plain `npm test` |
| `npm run build` | Exit 0; `tsc` completed | TypeScript source build; no configured lint script |
| `npm ls --depth=0` | Exit 0; installed direct dependencies resolved | Existing dependencies; no new framework installed |
| Compiled `node dist/db/migrate.js status` and `up` | All five applied; pending/unexpected empty; repeated up had no migrations | Production-format Node entry point against disposable PostgreSQL |
| Root `docker compose --env-file .env.example config --quiet` | Exit 0 | Compose syntax/interpolation only |
| Docker build/start/container restart | **Not executed: daemon unavailable** | Environmental limitation |
| `npm audit --omit=dev --json` | **4 high findings** | Dependency audit; remains unresolved |
| Baseline `flutter test --no-pub --reporter expanded` | 258 completed successfully | Existing headless Flutter tests |
| Final same Flutter command | **305 completed successfully, 0 failures** | 258 existing + 47 added client/config/cache regressions |
| Changed-files `dart analyze` | No issues; exit 0 | Static analysis |
| `flutter analyze --no-pub` | **Exit 1: 0 errors, 56 warnings, 255 infos** | Full project analysis is not clean |
| `git diff --check` | Exit 0 | Tracked patch whitespace; existing LF/CRLF notices only |

Final database suites were rerun after the last relevant source changes. The workflow catalog assertions and multi-bed compatibility checks were expanded and all 18 cases rerun afterward. Flutter final evidence follows its last Dart mutation. Detailed test-development failures and corrective reruns are documented in the component reports.

The first real workflow run had **9 failures / 3 successes**, while the module baseline had **15 failures / 8 successes**. Signed-token security regressions failed before verification was corrected; long Firebase UID regressions failed **3/3** before migration 005. Epoch-zero patient dates were separately demonstrated to become fabricated dates before correction. A final comparison with Flutter's room-service parts exposed two mistakes in the audit's first lifecycle correction: it prohibited existing multi-bed admissions and labeled partially occupied rooms occupied. Two failing regressions were added, then the implementation was aligned with the existing rules and all 18 workflow tests rerun successfully. The initial restart harness timed out because synchronous Windows process control blocked socket events; changing the test to asynchronous hidden child processes produced the final successful restart run. An initial catalog assertion incorrectly expected six new indexes instead of the actual five; the corrected assertion now verifies the concrete index names/catalog. These harness failures are not counted as successful verification.

## Database and migration results

`001_initial_schema.sql` was actually executed on a fresh PostgreSQL database by the existing `node-pg-migrate` runner. Its `-- Up Migration` / `-- Down Migration` format works. Runtime assertions compare **every original table, column, explicit index and foreign-key name** from the DDL with PostgreSQL's catalog. There are 17 domain tables plus `pgmigrations`. Monetary columns retain `NUMERIC(12,2)`; SQL assertions establish `0.10 + 0.20 = 0.30` and exact resulting balances.

The initialized upgrade test applies only 001, inserts synthetic historical data, then applies the upgrades and verifies the existing payment remains `0.10`. It checks restrictive history FKs, unique indexes and monetary precision. Status distinguishes applied/pending/unexpected migration names. Repeated `up` is a no-op. The library warns that numeric prefixes `001`–`005` are not timestamps; it nevertheless discovers, orders, executes and records those SQL files. Files were not renamed or silently marked applied.

| Upgrade | Correction |
|---|---|
| 002 integrity hardening | Patient stays, attendance, payments and attendants restrict patient deletion; stay bed history restricts bed deletion; bed labels, active-bed use, attendance identity and patient transaction IDs gain uniqueness; assignment/room FKs added; photo versions widened to BIGINT. |
| 003 preservation/retries | Inline attendant photos gain a destination; payment request fingerprints distinguish identical retries from conflicting reuse or imported history. |
| 004 patient write versions | Patient responses expose `version`; payment/admission/discharge/profile writes advance it. Financial profile updates require a current version, preventing stale snapshots from erasing newer payments. |
| 005 Firebase UID width | Users and all six creator/updater columns retain up to 128-character Firebase UIDs; 65/128-character identities tested against PostgreSQL. |

New assignment FKs use `NOT VALID` to avoid pretending existing historical data has been reconciled. They enforce new writes, but legacy constraint validation remains required before cutover. New unique indexes can deliberately fail an upgrade on conflicting existing records; the migration does not delete or silently merge historical data to make an index succeed.

Rollback requires `NODE_ENV=test`, an explicit `ALLOW_DISPOSABLE_DB_ROLLBACK=1`, loopback URL and an `ngo_audit_*` database. All five migrations were reversed and reapplied only in the disposable migrations database. Down migrations retain widened UID/photo types to avoid narrowing valid values. This is a tested development rollback, not a proposed production rollback strategy.

Pool configuration now honors `DATABASE_URL` consistently with migrations. DATE values preserve calendar-date semantics rather than shifting to the previous date in IST. Idle-pool/global errors omit raw PostgreSQL objects, client connection parameters and record details. Connection replacement and saturated-pool timeout/reuse were executed. An actual server stop returned a generic 503 from readiness; restart restored readiness through the same pool and retained a committed marker. **Container-volume persistence was not runtime-tested**; the private network and named data volume were inspected statically.

## API endpoint and workflow coverage matrix

All domain paths below have prefix `/api`. “Real” means Fastify injection plus PostgreSQL assertions. All implemented domain operations require verified identity and server-side role lookup.

| Endpoints | Database operations | Executed evidence and support limits |
|---|---|---|
| GET `/rooms`, GET `/rooms/:id` | Rooms SELECT plus nested bed SELECT | Real list/detail and final occupancy retrieval. Floor/type filtering inspected; not every combination tested. |
| POST `/rooms`, PUT `/rooms/:id` | Transactional room/bed insert or update; version lock; occupancy refresh | Real creation/update, rollback, two concurrent writes with the same expectedVersion, duplicate/cross-room bed rejection. |
| **POST `/rooms/:id/beds`**, PUT `/rooms/:id/beds/:bedId` | Room lock, bed insert/update, occupancy/version refresh in one transaction | Missing create-bed operation added and tested. Label/status changes, missing room/bed, duplicate labels and assignment guards tested. GET/delete individual bed and room delete are absent. |
| GET `/patients`, GET `/patients/:id` | Patient/attendant/payment SELECT; filters/pagination | Real search, paging, detail, field/attendant/inline-photo/ledger preservation, max-length identifier. Not every legacy field combination has an independent test. |
| POST `/patients` | Transactional patient/attendant insert | Real required-field/date validation, duplicate ID/registration rollback, repeated request rejection without duplication, server creator, epoch-zero preservation. Registration allocation remains a separate endpoint. |
| PUT `/patients/:id` | Row lock, partial profile update, optional attendant replacement, version advance | Omitted optional fields preserved; DOB/admission fields supported; active assignment bypass denied; stale financial snapshot denied. Financial changes require `expectedVersion` or current returned `version`. This is not a billing-restatement engine. |
| DELETE `/patients/:id` | Admin DELETE subject to restrictive history FKs | Real financial-history deletion rejection; clinical/financial history is retained. Archival endpoint is absent. |
| GET `/stays`, GET `/stays/:id` | Stay SELECT with filters | Real patient/stay final lifecycle retrieval; filter combinations inspected. No delete endpoint. |
| POST `/stays` | Lock room/patient/bed; insert stay; update assignment/patient/room atomically | Real complete admission sequence, competing same-bed admissions, invalid reference rollback, authoritative room/patient fields. Existing multi-bed admissions within a room remain supported, with all current bed IDs retained. Complete current placement before a room move. |
| PUT `/stays/:id` | Transactional stay update; optional completion releases bed, updates patient, recomputes room occupancy | **Mandatory discharge verified**: completed stay retained, bed available with NULL pointers, patient discharged with cleared current placement after the final active stay, room occupancy zero. A remaining bed keeps the patient active and room partially occupied. Repeated completion safe; injected patient-update error rolls back stay/bed/room changes. Duration/long-stay-rate updates tested. No separate discharge route; complete a stay using `status: completed`. |
| GET/POST `/attendance`, POST `/attendance/bulk` | Filtered SELECT; identity upsert; transactional bulk | Real patient/attendant date storage, updates/retries, history maps retaining dates, invalid dates/IDs, successful bulk and rollback of earlier items when a later item fails. Attendant subkeys remain JSON, not attendant FKs. |
| GET `/payments`, GET `/payments/:id`, POST `/payments` | Payment SELECT; patient lock; immutable retry check; payment insert + balance update transaction | Real histories, concurrent duplicates, simulated retry, conflicting key reuse, two distinct concurrent decimal payments, exact balance math, injected failure rollback. Stable `id` or `transactionId` required. Receipt numbers are indexed, not assumed globally unique. Refund/adjust/amend/delete APIs are **not implemented**; unsupported refund submissions are rejected rather than applying payment arithmetic. |
| GET/PUT `/counters/:name`, POST `/counters/:name/next` | SELECT, validated upsert, atomic bounded allocation seeded above numeric registrations | Real two concurrent registration allocations (1043/1044 over imported 1042), ordinary counters, invalid/unsafe input and exhaustion. Lost allocation response may leave a gap; `/next` does not deduplicate retries. |
| GET/PUT `/settings/:category`, GET/PUT `/settings/:category/:key` | JSONB SELECT/upsert; category merge transaction | Real false/zero persistence, admin write policy and category merge. Category PUT added. Root settings, delete and full ordinary/admin namespace parity absent. |
| GET/PUT `/photos/*` | Photo SELECT; conditional atomic versioned upsert | Real patient/attendant retrieval, microsecond BIGINT versions, identical retry, stale conflict, path/body mismatch, missing patient and malformed payloads. No delete API; actual image decoding not tested. |
| GET/POST `/erp/inventory` | Inventory SELECT/INSERT | Real create/list, stock values, duplicate/input/role checks. Stock movement workflow absent. |
| GET/POST `/erp/vendors` | Vendor SELECT/INSERT | Real contact/empty optional email, required-name and role checks. Model metadata parity incomplete. |
| GET/POST `/erp/purchases` | Purchase SELECT/INSERT with vendor/item FKs | Real references, decimal values and invalid-reference no-write assertions. Purchase creation does not atomically move stock. |
| GET/POST `/erp/expenses` | Expense SELECT/INSERT | Real exact amount, invalid money/precision and authorization checks. Flutter expense shape differs. |
| GET `/erp/salaries` | Salary SELECT | Real synthetic stored salary retrieval. Salary creation is absent. |
| GET/POST `/erp/sponsorships` | Sponsorship SELECT/INSERT with optional patient FK | Real references, decimals, invalid date/reference and roles. |
| GET/PUT/DELETE `/erp/:module/:id`, POST `/erp/salaries` | No route | Real tests confirm 404. Full ERP CRUD is not claimed. |
| `/users` and user/role management | No route | Static absence; middleware auto-provisions only volunteer records. No client profile/admin user-management API exists. |
| GET `/`, `/health`, `/api/health`, `/ready`, `/api/ready` | Liveness metadata; readiness `SELECT 1` | Existing probes and real `/ready` outage/recovery tested. `/api/ready` is an inspected shared-plugin alias, not separately exercised. |

## Authentication and security

The previous middleware accepted fabricated JWTs because it used `jwt.decode` without cryptographic verification and could select an account by email. It also enabled test tokens outside production and lacked most resource role checks. Those defects were corrected.

Tests exercise real RS256 signature verification using ephemeral trusted test keys: valid claims, malformed/unsigned/wrong-signature tokens, unsupported algorithms, expiry, missing/future claim times, issuer/audience/project mismatch, key IDs, rotation/cache/refresh failure/recovery, UID consistency and boundaries. The key source is fixed to Google's Firebase certificate endpoint; token-controlled key URLs are ignored. DB user roles govern access; body/token role claims cannot escalate privileges, and a matching email cannot select another UID's account. Clinical access requires staff/admin, administrative setting writes require admin, ERP policies follow the existing Firebase rules. Valid-token database/key-source failure returns safe 503; invalid authentication returns 401; forbidden roles return 403.

Database values are parameterized. Query shape identifiers are fixed/allowlisted; pagination is validated before interpolation. Responses and logs avoid raw SQL/credentials/record payloads. Production config requires explicit Firebase project and non-placeholder database credentials. Compose publishes only the API port, not PostgreSQL. Docker startup now runs compiled pending migrations before the server; build context excludes dependencies, environment files and logs. This deployment behavior is source/compiled-command verification, not a completed Docker deployment test.

`npm audit --omit=dev` identified four high findings through Fastify/find-my-way and node-pg-migrate/glob. Major dependency upgrades and their regression checks remain cutover work; findings were not hidden by an untested upgrade. Live Google certificate retrieval, token revocation policy, real Firebase account sign-in, external TLS and load/socket timeout testing were not exercised.

## Importer results and source reconciliation

There are **9 mocked + 21 real PostgreSQL importer tests**, included in the counts above. The valid fixture stores one room/bed/patient/attendant/stay, two attendance kinds and two unique payments. Duplicate branch copies produce two ledger rows, not three. SQL sum is exactly `0.30`; fixture patient paid/due remain `0.30`/`9.70`. Repeat import leaves complete historical payment rows/timestamps unchanged. A separate embedded legacy refund is preserved as `-0.05`; this does not imply the API implements refunds.

Confirmed corrections include row savepoints, final whole-import rollback on any rejection/unsupported nonempty branch, valid-reference accounting, nested `daily` attendance, canonical payment ID deduplication across payments/history/embedded patient arrays, immutable existing payment checks, strict dates/decimals, scoped integer-cent reconciliation, deferred bed references, inline attendant photos, bounded deterministic attendant IDs, pricing key shape and complete mapped non-ledger snapshot upserts. Default API/CLI import is dry-run; CLI requires an explicit file and `--apply` for commit. No-argument CLI refusal was executed. Counts when `committed=false` describe preview writes and are labeled accordingly. Failed rows are counted with redacted reasons; fatal setup errors roll everything back.

Existing `migration_reports/global_billing_restatement_20261005_181013_411811` was inspected only for aggregate source structure:

- 116 patients, 182 stays, 9 rooms and 47 beds.
- 39 stays reference absent patients; 51 reference absent rooms (overlapping counts).
- 1,460 patient-attendance records, 106 with absent patients; 1,204 attendant-attendance records.
- 205 payments + 180 payment-history entries; **89 incomplete stubs** lack amount/patient identity. Amount-bearing records plus 187 embedded entries yield 189 canonical payment IDs. Seven canonical IDs conflict on transaction/cycle metadata.
- Two occupied-bed patient references are absent; one bed points at a non-active stay and one stay pointer disagrees with its bed.
- 28 attendants have inline photos. Dedicated referenced photo binaries are not present in this snapshot; photo completeness cannot be established.
- 115 numeric registration numbers and no counter; allocator bootstrap was tested.

These are observed inconsistencies, not invented corrections or production import results. The source snapshot was **never imported** during the audit. Dedicated photo-store, ERP and additional administrative settings import are incomplete; unsupported nonempty branches now prevent a silent partial commit. A complete reviewed export and production financial reconciliation remain required.

## Flutter evaluation

The feature flag was unused by the domain service graph. Constructing `BackendApiService` did not connect patients, stays, payments, registration, users/photos/settings or ERP to PostgreSQL. Service initialization now explicitly rejects enabled PostgreSQL mode before misleading writes occur. Disabled mode retains Firebase. No live flag/environment was enabled.

47 new tests demonstrate/fix cache fallback masking 4xx/authentication errors, token/header failures, unsafe error bodies, deleted/null records, caching submitted rather than server-authoritative data, failed-write cache mutation, invented IDs, account partition races, late cache hydration, stale reads overwriting newer writes, overlapping/disposed polls, actual `attendance/daily/...` mapping and targeted patient/attendant SQLite reads. Tests use mocked HTTP and isolated real in-memory Drift/SQLite.

Changed-file `dart analyze` found no issues. Full Flutter tests completed 305/305 successfully. Full `flutter analyze` executed with no errors but 311 warnings/info findings elsewhere; it is not reported as clean. No Windows application runtime or live Flutter/API/PostgreSQL integration was performed.

Remaining adapter contracts include Firebase queries/streams, ETag CAS, atomic multi-path updates, payment/refund contracts, pagination before canonical cache replacement, patient versions, ordinary/admin settings namespace, photos, profile CRUD and ERP camelCase/maps/epoch dates versus SQL rows. Each backend stay mutation is atomic; there is no bulk-admission/completion endpoint making an entire multi-bed group one transaction. That contract needs explicit treatment in the adapter. **Existing Firebase discharge still marks the patient discharged and suppresses placement cleanup failures**; that source-inspection finding can still leave a bed occupied. The corrected atomic backend operation does not repair this legacy path until the adapter actually calls it.

## Changed files and regression ownership

| Defect group | Principal changed files | Regression files |
|---|---|---|
| Verified identity, roles, UID width, config, deployment | `backend/src/middleware/auth.ts`, `src/config/index.ts`, migrations 005, `Dockerfile`, `.dockerignore`, Compose, `.env.example`, deployment docs | `auth.test.ts`, `firebase_verifier.test.ts`, `auth_database.integration.test.ts`, config/domain/health tests |
| Transactional admission/discharge, bed create/edit, partial profiles, retry-safe balances | `backend/src/routes/{rooms,patients,stays,payments}.ts`, `src/validation.ts`, `src/db/{occupancy,identifiers,index,migrate}.ts`, migrations 002–004 | `workflows.integration.test.ts`, `migrations.integration.test.ts`, `persistence.integration.test.ts` |
| Attendance/settings/counters/photos/ERP correctness | `backend/src/routes/{attendance,settings,counters,photos,erp}.ts` | `modules.integration.test.ts` |
| Safe complete core import and financial history | `backend/src/importer/{index,cli}.ts`, synthetic fixture | `importer.test.ts`, `importer.integration.test.ts` |
| Flutter HTTP/cache/feature flag | `lib/config/app_config.dart`, `lib/services/{backend_api_service,service_locator}.dart`, `lib/cache/persistent_cache.dart` | `test/backend_api_regression_test.dart`, `test/backend_config_test.dart`; existing suites rerun |

See the detailed [security](security-audit.md), [module](modules-audit.md), [importer](importer-audit.md) and [Flutter](flutter-audit.md) reports for root causes, test cases and narrower limits. The consolidated results here supersede intermediate counts in those reports.

## Reproducing the executed checks

Existing dependencies were used. No database test may be aimed at production. A separately initialized PostgreSQL 16 audit cluster and the exact disposable database names are prerequisites; guards intentionally reject normal development/production targets.

Cluster setup executed with the installed PostgreSQL 16 `initdb.exe`, `pg_ctl.exe`, `createdb.exe`, using `--auth=trust --encoding=UTF8 --locale=C`, temp data directory and `-p 55439 -h 127.0.0.1`. Trust authentication applies only to this temporary loopback test instance. Test passwords are synthetic.

Actual backend commands, from `backend/` (each suite sets its own database and flag):

```powershell
$env:NODE_ENV='test'
$env:POSTGRES_HOST='127.0.0.1'
$env:POSTGRES_PORT='55439'
$env:POSTGRES_USER='ngo_audit'
$env:POSTGRES_PASSWORD='audit-local-only'
Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
npm test -- --reporter=dot
npm run build
npm ls --depth=0

$env:POSTGRES_DB='ngo_audit_workflows'; $env:RUN_PG_INTEGRATION='1'
npx vitest run tests/workflows.integration.test.ts --reporter=dot
$env:POSTGRES_DB='ngo_audit_modules'; $env:AUDIT_DATABASE_TESTS='1'
npx vitest run tests/modules.integration.test.ts --reporter=dot
$env:POSTGRES_DB='ngo_audit_importer'; $env:RUN_IMPORTER_DB_TESTS='1'
npx vitest run tests/importer.integration.test.ts --reporter=dot
$env:POSTGRES_DB='ngo_audit_auth'; $env:RUN_AUTH_PG_INTEGRATION='1'
npx vitest run tests/auth_database.integration.test.ts --reporter=dot
$env:POSTGRES_DB='ngo_audit_migrations'; $env:RUN_PG_MIGRATIONS='1'
npx vitest run tests/migrations.integration.test.ts --reporter=dot

# Run alone: this intentionally restarts the verified disposable cluster.
$env:POSTGRES_DB='ngo_audit_workflows'; $env:RUN_PG_RESTART='1'
$env:DB_POOL_CONNECTION_TIMEOUT_MS='200'
$env:AUDIT_PG_DATA_DIR=Join-Path $env:TEMP 'ngo-audit-pg16-20261016'
$env:AUDIT_PG_CTL='C:\Program Files\PostgreSQL\16\bin\pg_ctl.exe'
npx vitest run tests/persistence.integration.test.ts --reporter=dot
node dist/db/migrate.js status
node dist/db/migrate.js up
```

Other executed commands, from repository root:

```powershell
docker version
docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
docker compose --env-file .env.example config --quiet
flutter test --no-pub --reporter expanded
dart analyze lib/config/app_config.dart lib/services/backend_api_service.dart lib/services/service_locator.dart lib/cache/persistent_cache.dart test/backend_api_regression_test.dart test/backend_config_test.dart
flutter analyze --no-pub
git diff --check
```

`npm audit --omit=dev --json` ran from `backend/`. A first Compose command from that directory used the wrong relative env-file path and was corrected to the repository-root command above; only the corrected command validated configuration.

## Outstanding production review gates

1. Implement and test the actual Flutter domain adapters, including atomic lifecycle/payment operations, version preconditions and complete pagination/cache contracts. Preserve the fail-closed flag until then.
2. Complete required ERP CRUD, response/model/schema parity and atomic stock movement; complete users/settings/photos and importer branch coverage required by the real deployment.
3. Obtain a consistent complete export, review missing references/incomplete/conflicting ledger records, validate legacy assignment FKs and reconcile actual historical finances without inventing repairs. Do not apply a stale snapshot to a changing target database.
4. Resolve the four high dependency findings and rerun affected tests.
5. Execute Docker image build/start/initialized upgrade/ordinary container restart/volume persistence and staging sign-in/real client API tests with appropriate secrets and TLS. These were not replaced by Compose parsing or headless tests.
6. Review legacy Firebase discharge error suppression and existing token persistence/diagnostics. No assurance of atomic Firebase discharge or OS-protected token storage is made.

**Audit and targeted corrections are complete for review. The tested backend paths improved substantially; a safe production cutover has not been established.**

VERDICT: FAIL -- production cutover remains blocked by the enumerated integration, source-data, dependency and deployment gaps.
