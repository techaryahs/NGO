# Manual production financial export — read only

Primary schema: the complete `ngo_schema.sql` supplied on 28 October 2026,
29,540 bytes, SHA-256
`475841e91cde8c841c22e2484d936dfda1c3ff110d1b9bb5c553d93acab1ccba`.
The dump identifies PostgreSQL/pg_dump **16.15**. It contains structure only;
it does not establish the host, database name, deployed code revision, applied
migration rows, actual receipt allocations, or historical transaction contents.

## Schema comparison

The dump has 18 tables: the 17 original domain tables plus `pgmigrations`.
The financial structure matches the relevant changes in local migrations
001–009: patient version/registration fingerprint; retry fingerprints on
payments; 128-character payment/stay IDs; widened creator IDs; nullable salary
staff references; ERP `details` columns. This is a structural comparison, not
proof that those migration names were executed on the VPS.

The local, uncommitted **010_payment_change_history.sql** differs from this dump:
its `payment_change_history` table, sequence, functions and audit triggers do not
exist in the supplied production structure. The export does not reference them
and must not be preceded by deploying that migration.

Important production facts:

- `payments.amount` is NUMERIC(12,2); patient/stay money is also NUMERIC(12,2).
  Amounts are exported as exact decimal strings, without float arithmetic.
- `payments.id` and `stays.id` are VARCHAR(128); patient IDs are VARCHAR(64).
- `payments.cycle_id` and `stays.cycle_id` are nullable VARCHAR(64), with no
  cycle foreign key or separate admissions/allocation table.
- `ix_payments_patient_transaction` is **non-unique**. Neither transaction
  references nor receipt numbers establish uniqueness by themselves.
- There is no separate refund, reversal, credit, partial-allocation or payment
  change-history table. Signed payment amounts and stored `type` are retained.
  No reversal linkage can be invented from this schema.
- Relational financial timestamps are TIMESTAMPTZ and are rendered in UTC.
  `pgmigrations.run_on` is TIMESTAMP WITHOUT TIME ZONE. JSON timestamps may be
  naive strings or epoch values; they are preserved without inventing a timezone.
- `admission_balances`, `billing_summary`, `patient_snapshot`, `extensions` and
  attendance payloads are JSONB. Their internal keys are not specified by the
  schema. Only known financial/association fields are exported. Unknown fields
  and arbitrary notes require authorized on-server review if relevant.
- Several bed/stay foreign keys are `NOT VALID`. The summary independently
  checks exported relationships rather than assuming they have been validated.

## Files to copy to the VPS

Copy these two files together into the existing repository's `backend/scripts/`:

1. `export-financial-data.py`
2. `production-financial-schema.json`

Python 3.8+ and an existing authorized `psql` invocation are required. No pip,
Node packages, application server, migration, `.env` access or SSH code is used.
Run from the repository root in the VPS shell you already use. The script never
reads `.env`; libpq/psql uses the connection/authentication context you provide.

```sh
umask 077
python3 backend/scripts/export-financial-data.py \
  --output-dir "$HOME/ngo-financial-export-20261028"
```

This exact command uses `psql` from PATH and its already authorized libpq context
(for example an existing PGSERVICE/PGHOST/PGDATABASE/PGUSER and password file).
It uses `-w`, so it fails instead of prompting for or logging a password. Never
put passwords or a connection URL in the command. No host, role or database is
guessed. If desired, add `--expected-database YOUR_VERIFIED_DATABASE_NAME` as an
explicit identity guard.

If your authorized psql invocation is inside Docker, replace only the psql
invocation using the same container/service/role/database you already verified:

```sh
python3 backend/scripts/export-financial-data.py \
  --output-dir "$HOME/ngo-financial-export-20261028" \
  --psql-command 'docker compose exec -T YOUR_EXISTING_SERVICE psql -U YOUR_AUTHORIZED_ROLE -d YOUR_VERIFIED_DATABASE'
```

The `YOUR_...` values are placeholders; this document does not establish their
production values. Run that variant from your existing Compose directory.
`--psql-command` is split into arguments, never evaluated as a shell command.
SQL is supplied over stdin; no server files are read or written.

The exporter now adds `-i` to **Docker exec** and `-T --interactive=true` to
**Docker Compose exec**, so SQL on stdin reaches psql without TTY framing. A
`docker exec ... psql -c ...` diagnostic works without `-i`, but the original
export invocation without `-i` discarded SQL stdin and returned empty stdout
with exit code 0. That caused `json.loads` to fail before manifest decoding.
Do not use Docker `-t`/`-it`; the exporter rejects that transport.

Parser errors now identify `psql stdout JSON`, `psql result shape`,
`schema manifest JSON`, or `schema manifest shape`. They include no database
output excerpts, JSON values, credentials or patient details. The schema manifest
is decoded explicitly as UTF-8 (with optional BOM); psql stdout uses UTF-8.

### Backend/database identity evidence

The checked-in Compose file assigns the backend `POSTGRES_HOST=postgres` and
`POSTGRES_PORT=5432`. Both services use the same `${POSTGRES_DB:-ngo_db}`
substitution. The backend pool in `src/db/index.ts` uses those settings;
`DATABASE_URL`, if present at runtime, can override them. Compose does not pass
that override, and the Dockerfile does not copy a `.env` into the image.
This establishes the configuration intent, not which containers/code are
currently deployed on the VPS.

To verify the backend's own configured pool manually, run from your existing
Compose directory (no credentials are printed):

```sh
docker compose exec -T backend node --input-type=module <<'NODE'
import { pool } from './dist/db/index.js';
const client = await pool.connect();
try {
  await client.query('BEGIN READ ONLY');
  const { rows } = await client.query("SELECT current_database() AS database, current_user AS database_user, inet_server_addr() AS server_address, inet_server_port() AS server_port, current_setting('server_version') AS server_version");
  console.log(JSON.stringify({ configuredHost: pool.options.host, ...rows[0] }));
  await client.query('ROLLBACK');
} finally { client.release(); await pool.end(); }
NODE
```

Compare that result with the PostgreSQL-container diagnostic and export metadata.
The agent has not run this against the VPS.

## Database safety and completeness

The script supplies `psql -X -q -A -t -v ON_ERROR_STOP=1 -w` and runs:

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL statement_timeout='120s';
SET LOCAL lock_timeout='5s';
SET LOCAL row_security=on;
-- One SELECT assembles schema metadata and all required financial rows.
ROLLBACK;
```

It creates no database objects and issues no INSERT, UPDATE, DELETE, import,
allocation, migration or discharge statements. A role with write permissions
still executes the export in a read-only transaction. It refuses a visible
table-inventory difference, mismatched required column types/lengths/precision,
RLS on relevant tables, wrong explicit database name, missing SELECT permissions,
or failed statement. There is no pagination or LIMIT on financial rows.

Required SELECT access covers patients, stays, payments, attendance_records,
patient_attendants, rooms, room_beds, sponsorships, pgmigrations and pricing
settings. It does not select any row from users, photos, expenses, payroll,
vendors or inventory. Catalog/schema metadata is read for structural validation.

psql stderr is deliberately suppressed in reports because errors can echo row
values. If access fails, inspect your established connection/permissions locally;
do not send connection strings or raw authentication output.

## Output files and privacy

Retrieve these two files for review:

- **financial-data.json** — pseudonymous linked records, exact amounts and
  timestamps, saved/frozen charge fields, association snapshots, attendance marks,
  pricing snapshots, allowed extension metadata, schema/constraint metadata and
  actual database identity/version. Bank/check/receipt references and retry
  fingerprints are HMAC tokens, preserving exact and normalized equality.
- **financial-summary.json** — counts, account receipts/refunds/net, unmatched
  explicit cycles, all missing cycle IDs, duplicate-reference candidates,
  payment-ID prefix candidates, missing relationships, active/discharged status
  conflicts, overlapping attendant marks, and saved-balance discrepancies.

Keep these private files on the VPS; do not include them in a shared bundle:

- **pseudonym.key.private** — random HMAC key. Reuse it for repeat exports to
  compare the same identities. It is not a database credential.
- **identity-map.private.json** — maps pseudonyms back to original table IDs,
  registration identifiers and cycle identifiers, enabling authorized record
  lookup without putting those identifiers in the shared dataset. It contains
  no intentionally selected patient/attendant names, bank references or photos.

Files use mode 600 and the output directory mode 700 on POSIX. Existing directories
or keys with broader access are rejected. Protect Windows output with equivalent
user-only ACLs if running there.

Patient names, contact details, birth dates, medical details, addresses, photos,
authentication rows, free-text notes, operator identities and credentials are
excluded. Attendant names are tokenized in memory solely to preserve legacy
name/ID comparisons, then discarded. JSON is allowlisted; an omitted-field count
is included for balances. Do not assume schema-less unknown JSON fields contain
no additional financial evidence.

## Repeatability and interpretation

Re-run with the same directory (or `--key-file` pointing to the existing key).
Output files are replaced atomically; source data is never changed. Identical
database contents plus the same key give the same `records_sha256`; capture-time
and server metadata can differ. `financial-summary.json` is deterministic for
the same records. No real export, record count or finding is asserted by this
document before you run it.

All missing receipt cycle IDs remain unresolved, even with one apparent cycle.
No date proximity or raw timestamp is used to choose a cycle. Explicit cycles
are compared with current, saved-balance and retained stay/snapshot cycle IDs.
Missing stay cycle metadata is reported without generating a replacement cycle.
Saved charge totals are preserved; the summary does not recompute bills using
current rates. An allocation or arithmetic discrepancy is a review candidate,
not a proposed SQL correction, confirmed loss or refund entitlement. Repeated
bank references can be legitimate split payments or placeholders.

Sponsorship rows are retained separately and are not automatically applied as
patient payment credits, because the schema has no authoritative linkage saying
they settle a particular invoice. Refund/reversal type-versus-sign conflicts are
flagged; original amounts are not changed or netted away.

This is a diagnostic export, **not a recoverable PostgreSQL backup**. It does not
authorize historical corrections or deployment. Review the returned metadata and
data first. Database identity verification, backup validation and evidence-backed
corrections remain separate later steps.

## Verification performed locally

The generated SQL was executed against an empty, disposable local PostgreSQL 16
instance created from the supplied schema (no patient data inserted). Schema
validation and export succeeded. Unit fixtures cover money precision, privacy,
stable joins, repeat output, ambiguous cycles, duplicate candidates, attendant
conflicts and schema mismatch rejection. No VPS connection or production export
was performed by the agent.
