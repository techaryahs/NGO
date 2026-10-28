# Financial-integrity production deployment preparation

**Recommendation: NO-GO for production execution now.** The Edit Patient payload
incompatibility is fixed and its request-level regression passes. Production
identity, recoverable backup/restore evidence, migration approval and
coordinated desktop-client readiness also remain unverified.
No production connection, migration, data correction, Git staging, commit, push
or deployment was performed. The compatibility fix and its regressions are local.

All commands below are instructions for the authorized operator after the gates
are satisfied. They were not run against production. They match the checked-in
Compose configuration; the actual VPS checkout path, Compose overrides/project
name and public HTTPS URL are not recorded in that configuration. Run inside the
existing VPS checkout, using its existing authorized settings and Compose flags.
Never substitute a guessed host, local database or different Compose project.
Keep the same Bash session through the VPS sections so its approved configuration
and backup/release variables are retained.

## Resolved code finding: Edit Patient client/server compatibility

`lib/screens/patients/widgets/edit_patient_dialog.dart` previously sent
`billingAmountOverride: null` unconditionally, and again on placement changes.
The PostgreSQL form now omits it entirely; the legacy RTDB reset is retained.
The backend generic patient PUT protection remains unchanged and rejects
explicit derived financial fields even when null.

The real form-to-HTTP regression in `test/postgres_real_workflows_e2e_test.dart`
saves an ordinary diagnosis/address edit using Firebase test-token authentication
and the actual API with disposable PostgreSQL 16. It checks HTTP 200, all 12
protected financial keys absent from the request, saved edit fields, and unchanged
financial columns and receipts. The complete E2E file passes (28 tests).
`backend/tests/settlement.integration.test.ts` adds 24 rejection cases: each of the
12 protected fields with null and a non-null value, with no profile/ledger changes.
Malformed `stayBillingUpdates: null` is rejected by shared validation with 400;
a well-formed object and the other protected fields reach the 409 financial guard.
No production patient or authentication configuration is used by these tests.

The 48-file manifest includes this fix. It remains a **candidate scope**, not
approval to commit, merge, migrate or deploy before the operational gates below.

## 1. Verified release scope

`docs/financial-integrity-release-files.txt` lists exactly **48 files**: all 41
currently modified tracked financial/attendance source and regression-test files,
migration 010, three new regression-test files, the existing shared-fix document,
this runbook and the manifest. Test fixture/mocking adjustments are included
because they are necessary for the verified suite and unchanged billing rules.

Leave these existing untracked groups out of this release commit, untouched:

- `.gravitas/sessions/financial-root-causes-20261028/` — local process metadata.
- `audit/client-billing-20261022/` — generated synthetic benchmark artifacts.
- `audit/production-export-20261028/` — production-derived pseudonymous reports,
  correction proposals, analysis scripts and local verification evidence. Keep
  them in the restricted audit archive; pseudonymization is not permission to
  publish financial records. References to those paths in the financial documents
  identify the locally retained/private audit evidence, not application assets.
- `backend/scripts/audit-payment-allocations.ts`, `export-financial-data.py`,
  `export-financial-data.md`, `production-financial-schema.json`,
  `backend/tests/test_financial_export.py`, and
  `backend/tests/test_financial_export_postgres.py` — the separate export/audit
  tooling workstream. Preserve it for a separately reviewed tooling commit.
- `docs/financial-reconciliation-plan.md` — its export-tool instructions and
  historical reconciliation process belong with that separate tooling workstream;
  leaving it untouched avoids releasing references to tools omitted here.

No credentials, `.env` files, exports, schema dump, private pseudonym keys/maps,
database backups, logs, generated bundles or `backend/dist` belong in this commit.
Do not use `git add .`, `git add -A`, reset, clean or stash unrelated work.

## 2. Verification evidence

The table below records the previous full release-review baseline. Its log hashes
were checked against
`audit/production-export-20261028/implementation-verification.json`. That baseline
predates the compatibility fix; it is not evidence for the new request regression.
Current rerun results are recorded separately below.

| Check | Observed result |
|---|---|
| Backend full PostgreSQL matrix | **412 passed**: 201 ordinary tests and 211 integration tests; no opt-in suite omitted |
| Integration breakdown | workflows 47; modules 41; importer 27; payment accuracy 40; scalability 4; settlement 47; database authorization 3; migrations 1; persistence/restart 1 |
| Full Flutter suite | **541 passed**, including the isolated real PostgreSQL end-to-end suite |
| Flutter analysis | No issues found |
| TypeScript | Build passed; also compiled successfully in the production Docker build |
| Local production Docker build | Passed: `docker build --tag ngo-financial-integrity-review:20261028 --file backend/Dockerfile backend` |
| Docker runtime artifact check | Node v22.23.3, non-root UID 1000, compiled payment route, migration 010 and production migration dependency present |
| Compose syntax | Passed using an explicit temporary dummy env file; no production configuration/connection used |
| Historical dry run | Repeated output identical; zero executed corrections |

The local image ID observed was
`sha256:edbbf9ace62f67a4d4840202f270581673074095bb9a9361e744cf8a7603b5b4`.
The VPS build may have a different image ID; record its actual immutable ID.
This compatibility follow-up changes the form and adds request/injection tests;
it does not change billing, server validation, migrations or deployment commands.
Existing README cutover warnings predate the current implementation; use the
actual code/configuration and this specific release procedure for this review.

Compatibility-fix verification rerun (2026-10-28), after the code/test changes:

| Check | Observed result |
|---|---|
| Full backend matrix, `npm --prefix backend run test:postgres` | **436 passed**: 201 ordinary plus 235 integration tests; all opt-in suites executed |
| Integration breakdown | workflows 47; modules 41; importer 27; payment accuracy 40; scalability 4; settlement **71**; database authorization 3; migrations 1; persistence/restart 1 |
| Targeted Flutter real-API E2E file | **28 passed**, including the actual Edit Patient form save |
| Full Flutter suite, `flutter test --no-pub --reporter expanded` | **542 passed**, including the same real-form request regression |
| TypeScript, `npm --prefix backend run build` | Passed |
| Flutter analysis, `flutter analyze --no-pub` | No issues found |

Current backend/E2E/Flutter/build/analysis outputs are retained locally in ignored
`edit-patient-backend.log`, `edit-patient-e2e.log`, `edit-patient-flutter.log`,
`edit-patient-build.log` and `edit-patient-analyze.log`.
These logs contain only local test evidence and do
not belong in the release commit. The previous Docker build, Compose validation
and historical dry run above were not rerun for this frontend-only source change.

If code changes after this review, rerun the applicable checks. A complete local
rerun uses the following, **sequentially**: the backend runner and Flutter E2E
suite both own disposable PostgreSQL port 55439 and must not run simultaneously.

```powershell
npm --prefix backend run build
npm --prefix backend run test:postgres
flutter test --no-pub
flutter analyze --no-pub
git diff --check
```

## 3. Migration 010 is a required release dependency

The supplied Desktop PostgreSQL 16.15 schema has the payments/stays schema and
`pgmigrations`, but no `payment_change_history` table, associated sequence/index,
`preserve_payment_change` function/trigger or `immutable_payment_history`
function/trigger. The completed export records migrations 001–009. The current
live state has not been re-queried in this preparation.

Migration 010 adds those objects without rewriting existing receipts, allocation
fields, charges or balances. Its payment trigger captures future INSERT/UPDATE/
DELETE old/new rows with operator/reason; the history trigger rejects ordinary
UPDATE/DELETE. This is application/database trigger protection, not protection
against a database administrator disabling triggers. It does not reconstruct
past events. The application role needs the new table/sequence privileges;
the checked-in Compose uses the same configured role for migration and runtime.
If production separates those roles, explicit reviewed grants are required.

Runtime dependency is precise:

- `backend/src/routes/payments.ts` directly selects `payment_change_history` for
  `GET /api/payments/:id/history`; without 010 this request fails.
- Payment POST/PUT/PATCH/DELETE set transaction-local operator/reason settings.
  Without the migration's trigger those writes can succeed **without the new
  audit trail**. Starting the process or passing `/ready` is therefore insufficient.
- `backend/Dockerfile` runs
  `node dist/db/migrate.js up && exec node dist/server.js` on every normal start.
  **A plain `docker compose up` would apply pending migrations automatically.**
  Use a new-image one-off container with its entrypoint overridden for inspection;
  execute the reviewed migration explicitly before starting the API.
- The down section deliberately retains history (`SELECT 1`), and the migration
  runner refuses production down migrations. Rollback is not “run migrate down.”

## 4. Local commit/push instructions — NOT executed

Run only after verifying the candidate and reviewing the manifest. Current branch
is `main`, remote `origin` exists, and the index was empty at review time.
These commands create a release branch without discarding uncommitted work.

```powershell
if (@(git diff --cached --name-only).Count -ne 0) { throw 'Review existing staged work first' }
git switch -c codex/financial-integrity-release
if ($LASTEXITCODE -ne 0) { throw 'Branch creation failed; stop' }
git add --pathspec-from-file=docs/financial-integrity-release-files.txt
if ($LASTEXITCODE -ne 0) { throw 'Staging failed; stop' }
$expected = @(Get-Content docs/financial-integrity-release-files.txt | Sort-Object)
$actual = @(git diff --cached --name-only | Sort-Object)
if (Compare-Object $expected $actual) { throw 'Staged files differ from the release manifest' }
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Staged diff check failed' }
git diff --cached --stat
git diff --cached
# Review the complete staged patch before executing the next two commands.
git commit -m "Fix financial cycle identity and authoritative reconciliation"
if ($LASTEXITCODE -ne 0) { throw 'Commit failed; do not push' }
git push -u origin codex/financial-integrity-release
```

Have the release reviewed and merged into `main` through the existing process.
Record the **reviewed merged main commit SHA** for `RELEASE_SHA` below. It does
not exist yet; do not substitute the current uncommitted main SHA. The manifest
does not authorize inclusion of unrelated future changes.

## 5. VPS read-only preflight and build — NOT executed

Use Bash in the existing VPS repository. For a deployment with additional
Compose flags, put the **same existing flags** in `dc`; do not change project
name, env file, volumes or network during this financial release.

```bash
set -euo pipefail
dc() { docker compose "$@"; }
cd "$(git rev-parse --show-toplevel)"
test "$(git branch --show-current)" = main
test -z "$(git status --porcelain)"  # stop and preserve any VPS-local work
dc config --quiet                 # never print expanded config/secrets
dc ps

stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_dir="$HOME/ngo-deployment-backups/financial-$stamp"
umask 077
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
git rev-parse HEAD > "$backup_dir/previous-revision.txt"
old_image=$(docker inspect "$(dc ps -q backend)" --format '{{.Image}}')
rollback_image="ngo-backend:financial-rollback-$stamp"
docker image tag "$old_image" "$rollback_image"
printf '%s\n' "$rollback_image" > "$backup_dir/previous-image-tag.txt"

# Execute the configured driver's read-only query inside the running backend
# container; this uses the same driver/configuration code as the API, not a
# separately guessed connection URL. Only safe server identity is printed.
dc exec -T backend node --input-type=module -e '
import {pool} from "./dist/db/index.js";
const c=await pool.connect();
try { await c.query("BEGIN READ ONLY");
 const r=await c.query("SELECT current_database() AS db,current_user AS role,inet_server_addr()::text AS addr,inet_server_port() AS port,current_setting($1) AS version",["server_version"]);
 console.log(JSON.stringify(r.rows[0])); await c.query("ROLLBACK");
} finally { c.release(); await pool.end(); }
' > "$backup_dir/backend-db-identity.json"

dc exec -T postgres sh -eu -c 'exec psql -X -qAt -v ON_ERROR_STOP=1 -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT json_build_object('\''db'\'',current_database(),'\''role'\'',current_user,'\''addr'\'',inet_server_addr()::text,'\''port'\'',inet_server_port(),'\''version'\'',current_setting('\''server_version'\''));"' > "$backup_dir/postgres-identity.json"
python3 - "$backup_dir" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); api=json.loads((p/'backend-db-identity.json').read_text()); db=json.loads((p/'postgres-identity.json').read_text())
assert api==db, 'API driver and postgres service identity differ; stop'
assert db['db']=='ngo_db' and db['port']==5432 and db['version'].startswith('16.'), 'Unexpected production target; stop'
print('Configured API driver and postgres service identities match expected ngo_db / PostgreSQL 16')
PY
```

Also verify the actual HTTPS API's authenticated read-only financial response
against corresponding database receipt totals. A driver query in the container
plus `/health` alone does not prove the reverse proxy routes to that container or
that an old mounted configuration has not diverged. Stop on an identity/version/
routing mismatch. Do not print tokens or patient response bodies in deployment logs.

After the approved release is merged, pull and build while the existing API is
still running. Building an image does not start it or run migrations.

```bash
RELEASE_SHA='<reviewed merged main commit SHA>'
test "$RELEASE_SHA" != '<reviewed merged main commit SHA>'
git pull --ff-only origin main
test "$(git rev-parse HEAD)" = "$RELEASE_SHA"
dc config --quiet
dc build backend
dc run --rm --no-deps -T --entrypoint node backend dist/db/migrate.js status > "$backup_dir/migrations-before.json"
python3 - "$backup_dir/migrations-before.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); assert s['unexpected']==[]; assert s['pending']==['010_payment_change_history'], s
print('Only the reviewed migration 010 is pending')
PY
```

If 010 is already applied, stop to verify who applied it and its exact object
definitions/privileges; do not rerun/drop it merely to match this example. If any
other migration is pending or unexpected, stop for a separate review.

## 6. Mandatory full backup and isolated restore test — NOT executed

**A full recoverable PostgreSQL backup and a successful restore test are required
before migration or replacement of the backend.** A schema-only file and the
pseudonymous financial export are not recoverable production backups.

Schedule maintenance, close all client sessions and quiesce all other writers,
including importers/admin jobs. Stop only the backend; keep PostgreSQL running.
Preserve the existing server env/secrets, Compose overrides, proxy/TLS and storage
configuration in the existing encrypted recovery system, outside Git. Protect
the full database and global-role dump as sensitive data. The global dump can
contain password hashes; do not display or commit it.

```bash
dc stop backend
dc exec -T postgres sh -eu -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' > "$backup_dir/ngo_db.full.dump"
dc exec -T postgres sh -eu -c 'exec pg_dumpall -U "$POSTGRES_USER" --globals-only' > "$backup_dir/globals.sql"
test -s "$backup_dir/ngo_db.full.dump"
test -s "$backup_dir/globals.sql"
sha256sum "$backup_dir/ngo_db.full.dump" "$backup_dir/globals.sql" > "$backup_dir/SHA256SUMS"
sha256sum -c "$backup_dir/SHA256SUMS"
dc exec -T postgres pg_restore --list < "$backup_dir/ngo_db.full.dump" > "$backup_dir/restore-list.txt"
```

The restore-list check is only an archive integrity check, **not a restore test**.
Restore into a fresh isolated container with no production volumes, ports or
network. These commands use the same immutable PostgreSQL image as production
but an independently created container/anonymous volume. They never target the
production database. Check the unique bootstrap role is absent from the global
dump before running this example.

```bash
db_image=$(docker inspect "$(dc ps -q postgres)" --format '{{.Image}}')
restore_container="ngo-restore-test-$stamp"
restore_role="restore_validator_$(date +%s)"
if grep -Fq "CREATE ROLE $restore_role;" "$backup_dir/globals.sql"; then exit 1; fi
openssl rand -hex 32 > "$backup_dir/restore-password"
docker run -d --name "$restore_container" --network none \
  -e POSTGRES_USER="$restore_role" -e POSTGRES_DB=postgres \
  -e POSTGRES_PASSWORD_FILE=/run/secrets/restore-password \
  --mount "type=bind,src=$backup_dir/restore-password,dst=/run/secrets/restore-password,readonly" \
  "$db_image" > "$backup_dir/restore-container-id.txt"
for attempt in $(seq 1 60); do
  if docker exec "$restore_container" pg_isready -q -U "$restore_role" -d postgres; then break; fi
  sleep 1
done
docker exec "$restore_container" pg_isready -q -U "$restore_role" -d postgres
docker exec -i "$restore_container" psql -X -v ON_ERROR_STOP=1 -U "$restore_role" -d postgres < "$backup_dir/globals.sql" > "$backup_dir/restore-globals.log" 2>&1
docker exec -i "$restore_container" pg_restore --exit-on-error --create -U "$restore_role" -d postgres < "$backup_dir/ngo_db.full.dump" > "$backup_dir/restore-data.log" 2>&1

counts_sql="SELECT json_build_object('patients',(SELECT count(*) FROM patients),'stays',(SELECT count(*) FROM stays),'payments',(SELECT count(*) FROM payments),'attendance',(SELECT count(*) FROM attendance_records),'receipts',(SELECT coalesce(sum(amount) FILTER (WHERE amount>0),0)::text FROM payments),'refunds',(SELECT coalesce(-sum(amount) FILTER (WHERE amount<0),0)::text FROM payments),'net',(SELECT coalesce(sum(amount),0)::text FROM payments));"
dc exec -T -e AUDIT_COUNTS_SQL="$counts_sql" postgres sh -eu -c 'exec psql -X -qAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$AUDIT_COUNTS_SQL"' > "$backup_dir/production-counts.json"
docker exec "$restore_container" psql -X -qAt -v ON_ERROR_STOP=1 -U "$restore_role" -d ngo_db -c "$counts_sql" > "$backup_dir/restored-counts.json"
cmp "$backup_dir/production-counts.json" "$backup_dir/restored-counts.json"
sha256sum -c "$backup_dir/SHA256SUMS"
```

Retain successful restore logs, compare restored schema/migration state, ownership,
constraints and all relevant table counts, verify recovery access, and retain an
encrypted off-VPS copy of the backup/configuration. Do not copy a running raw
PostgreSQL data directory as a backup substitute. Record operator/time and the
verified backup hash. Stop on any restore or comparison error. Once evidence is
retained, remove **only** the uniquely named disposable restore container/volume:

```bash
case "$restore_container" in ngo-restore-test-*) ;; *) exit 1 ;; esac
docker rm -fv "$restore_container"
```

## 7. Explicit operator-approved migration and backend start — NOT executed

**Checkpoint:** execute this section only after production identity, maintenance,
full backup/restore, reviewed release SHA, pending-migration review and coordinated
client/operator readiness are all confirmed. These commands intentionally change
the production schema; they are provided for the operator, not executed here.
No historical financial correction/import/audit apply command is part of deployment.

```bash
dc run --rm --no-deps -T -e PGOPTIONS='-c lock_timeout=5s -c statement_timeout=60s' \
  --entrypoint node backend dist/db/migrate.js up
dc run --rm --no-deps -T --entrypoint node backend dist/db/migrate.js status > "$backup_dir/migrations-after.json"
python3 - "$backup_dir/migrations-after.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); assert s['unexpected']==[] and s['pending']==[]
assert '010_payment_change_history' in s['applied']
print('Migration 010 applied; no pending or unexpected migrations')
PY
dc exec -T postgres sh -eu -c 'exec psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT to_regclass('\''public.payment_change_history'\''); SELECT tgname,tgenabled FROM pg_trigger WHERE NOT tgisinternal AND tgname IN ('\''preserve_payment_change'\'','\''immutable_payment_history'\'') ORDER BY tgname;"'

# Startup still invokes the image migration check, which must now be a no-op.
dc up -d --no-deps --no-build backend
new_image=$(docker inspect "$(dc ps -q backend)" --format '{{.Image}}')
printf '%s\n' "$RELEASE_SHA" "$new_image" > "$backup_dir/deployed-revision-image.txt"
dc ps
```

Do not restart/recreate PostgreSQL or change its volume, network or credentials.
Never run `docker compose down -v`. If a migration fails, leave maintenance in
place and investigate; do not repeatedly restart the new container to retry DDL.

## 8. Post-deployment checks — authenticated GETs only

```bash
host_port=$(dc port backend 8080 | head -n 1 | awk -F: '{print $NF}')
curl --fail-with-body --silent --show-error "http://127.0.0.1:$host_port/health"
curl --fail-with-body --silent --show-error "http://127.0.0.1:$host_port/ready"
dc exec -T backend node dist/db/migrate.js status
```

Verify both configured public HTTPS health/readiness URLs too. `/health` reports
the static application version `1.0.0`, not a Git commit; `/ready` only tests
database connectivity. Neither proves migration 010, target identity or financial
correctness. Verify those separately and correlate the running image with the
recorded reviewed commit/build.

Using the existing authorized authentication flow, privately inspect GET
`/api/patients`, `/api/patients/:id`, `/api/payments?patientId=:id`,
`/api/patients/:id/financials`, and `/api/payments/:id/history` for actual records.
Follow pagination. Compare signed receipts, account net, explicit cycle totals,
unallocated amounts, frozen totals and reconciliation flags with read-only SQL.
For pre-migration receipts, an empty history is expected; 010 does not backfill it.
An unauthenticated financial GET must remain 401. Do not log patient bodies or
tokens, and do not submit payments/refunds/discharge/attendance to smoke-test live
patients. Mutation guards/concurrency were tested only with isolated fixtures.

Verify the approved desktop client shows provisional amounts, suppresses
unverified actionable refunds, and retains the original receipt history. Review
application errors/readiness without printing container env or raw secrets.
Keep maintenance until identity/schema/GET checks and client readiness pass.

There will be intentional operational changes: all 79 untagged receipts plus the
unmatched explicit receipt in the exported snapshot remain visible but unresolved
under the strict resolver. Export net 189,200.00 is not a loss/refund entitlement.
Affected cycle-specific collections/refunds/discharge may block until separately
authorized reconciliation. Positive safe advances remain supported. Obtain an
operator review plan for this cohort before reopening financial workflows.
5157/5219/the 800.00 conflict, other flagged history and 5251's unexplained
screenshot difference are not repaired by deployment or migration 010.

## 9. Rollback/recovery

Retain the previous immutable image tag and full recoverable backup. Do not run
production `migrate down`, delete `pgmigrations` entries, remove audit history or
restore an old database over subsequent receipts. Migration 010's additive
structures/history should normally remain during an application rollback.
If rollback is required, keep financial actions in maintenance, select the
recorded old image through a separately reviewed Compose image override with
`--no-build`, and verify schema/API compatibility before restarting it. The old
backend lacks the new guards, so resuming old financial operations is not a safe
automatic rollback. A disaster restore needs a separate approved recovery/replay
plan for any writes since the backup. No rollback is executed in this preparation.

## 10. Separate Windows desktop release

The 13 modified `lib/` files in the manifest contain model/cache propagation,
authoritative paid/account totals, provisional/refund UI, collection/discharge
guards, attendant summary identity resolution and overdue attendance ranges.
Every one requires rebuilding/distributing the desktop application; rebuilding
the backend container does not update installed Windows binaries.
The Edit Patient payload fix above is included in that source and requires the
same separate desktop rebuild; a backend-only deployment cannot update it.

`AppConfig.usePostgresBackend` is already always true. Do not add a dart-define
feature flag: this application loads configuration from its bundled `.env`.
`pubspec.yaml` bundles that file, so use only approved public client settings
(HTTPS `BACKEND_API_URL`, environment and Firebase client authentication settings),
never the VPS/server env file, database credentials, private keys or backend
secrets. The actual client configuration contents were not read/verified here.
Preserve each workstation's existing cache/data. Ship a distinct approved build
name/number using the project's release process; the next version has not been
assigned in this preparation.

From the approved Windows release checkout/configuration:

```powershell
flutter pub get
flutter analyze
flutter test
# After assigning the approved release version/build and client configuration:
flutter build windows --release
```

Distribute the complete `build/windows/x64/runner/Release/` bundle (or the
existing signed installer), not only the executable. Verify fresh login,
authoritative cache refresh and financial UI on a controlled test environment
before distribution. No Windows release build/signing/installation was performed
by this deployment preparation. Older clients may show stale interpretations
even though server guards reject unsafe mutations; the rollout must be coordinated.
