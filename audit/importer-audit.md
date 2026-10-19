# Firebase importer audit — 16 October 2026

The importer was inspected independently. Its original single mocked test did not establish PostgreSQL compatibility, data reconciliation, or safe reruns. The corrected importer has **30 executed tests: 9 mocked orchestration tests and 21 PostgreSQL integration tests**, all successful in the latest run. Production cutover remains blocked by observed source inconsistencies and unsupported export modules described below.

## Isolation and evidence

Only the synthetic fixture in `backend/tests/fixtures/importer-fixture.ts` was imported. No production/source snapshot was imported into PostgreSQL or changed. The existing sensitive export was inspected locally using aggregate counts and field/type sets; no identities, patient values, financial totals, photos, or source records were copied into fixtures or this report.

Before migration or mutation, a real connection reported:

```text
current_database: ngo_audit_importer
inet_server_addr: 127.0.0.1/32
inet_server_port: 55439
version: PostgreSQL 16.12, compiled by Visual C++ build 1944, 64-bit
```

The integration suite requires `RUN_IMPORTER_DB_TESTS=1`, `NODE_ENV=test`, database **exactly** `ngo_audit_importer`, host `127.0.0.1`, port `55439`, and a PostgreSQL 16 runtime, and verifies the live database identity before any truncate. Test cleanup affects only this disposable database. Other test databases are not used by this suite.

Executed in the backend directory:

```powershell
$env:NODE_ENV='test'
$env:POSTGRES_HOST='127.0.0.1'
$env:POSTGRES_PORT='55439'
$env:POSTGRES_USER='ngo_audit'
$env:POSTGRES_DB='ngo_audit_importer'
# Local-only test authentication was configured; no production credentials used.
npm run migrate:up
$env:RUN_IMPORTER_DB_TESTS='1'
npm test -- tests/importer.test.ts tests/importer.integration.test.ts
npm run build
```

`migrate:up` actually executed `001_initial_schema.sql` on the fresh disposable database and subsequently executed `002_integrity_hardening.sql` against that initialized database. The final integration run's setup then applied migrations `003_preserve_photos_and_payment_retries`, `004_patient_write_versions`, and `005_firebase_uid_width` to the initialized database before testing. The runner emitted `Can't determine timestamp for 001` through `005` notices for numeric filenames, discovered and executed the SQL files, and recorded their names. Importer tests were then executed with all five migrations installed. Migration implementation, rollback, container persistence, and broader schema testing are covered by the parent audit, not asserted here from SQL inspection alone.

Latest run:

```text
tests/importer.test.ts                 9 tests
tests/importer.integration.test.ts    21 tests
Test Files 2 passed (2)
Tests      30 passed (30)
Start at   16:23:11
Duration   6.16s
npm run build -> tsc, exit 0
```

The no-argument CLI was also executed with `npm run import:firebase`. It refused the operation before acquiring a database connection, printed that an explicit export path is required and imports default to dry-run, and intentionally exited 1. This is a tested safety refusal, not a failed import of a fixture. The `--apply` CLI branch was inspected; the import implementation's explicit `dryRun:false` behavior was exercised by real integration tests.

## Confirmed defects and targeted corrections

| Defect / root cause | Correction | Regression evidence |
|---|---|---|
| SQL errors were caught inside one transaction without rolling back to a savepoint; later queries could execute in PostgreSQL's aborted transaction state. | Per-record savepoints recover the transaction so all rejections can be reported. Any rejection causes a final rollback of the entire import. | Real duplicate registration and invalid foreign key tests; later valid writes and reconciliation execute, then no imported records remain. |
| A patient ID was treated as valid before its insert/attendants succeeded. | Add it to the valid-reference set only after the patient and attendants finish successfully. | A failed duplicate registration is not accepted by its dependent stay; no dangling rows are retained. |
| Nested attendance was read as `attendance/date/patient`; actual exports use `attendance/daily/date/patient`. | Handle both nested `daily` and direct date branches for patients and attendants. | Real payload/date/patient assertions for both kinds, plus direct-branch regression. |
| Payment deduplication used only Firebase map keys; actual copied records retain an original `id` under a different key. Embedded patient ledgers were discarded. | Canonicalize using embedded payment `id`, merge both ledger branches and embedded patient payments, infer a missing embedded patient relationship from its parent, and reject conflicting duplicate identities. | Two copied keys produce one payment; an embedded-only refund is preserved; conflicting identities roll back. |
| Rerunning an import silently overwrote historical payment amounts/status. | Insert immutable ledger entries; compare all imported financial/identity fields on a conflict. Identical rows are counted as `unchanged`; changed historical entries are rejected. | Two imports leave complete payment rows and timestamps unchanged. Changed historical amount is rejected and retains the original database value. |
| `parseFloat` truncated malformed monetary text, converted invalid amounts to zero, and permitted silent NUMERIC rounding. | Parse full decimal strings, reject nonfinite/invalid/out-of-range or more-than-two-decimal values, send exact decimal strings to PostgreSQL, sum source totals in integer cents. | Mocked malformed values and real `0.10 + 0.20 = 0.30` SQL sums; refund stores exact `-0.05`. |
| Invalid dates were replaced with now; missing DOB was fabricated as 2000-01-01; missing room used a hard-coded real identifier. | Reject invalid/provided dates and missing required dates/text; require the source room relationship; preserve valid epoch and ISO timestamp values. | Invalid calendar dates, missing DOB/name, missing room FK, and valid timezone-offset timestamps. |
| Bed pointers were inserted before their foreign-key parents, incompatible with integrity migration 002. | Stage pointers as NULL, then validate and attach them after stays and patients exist. Invalid/completed/mismatched assigned stays abort the whole import. | Real occupied-bed pointer success; completed-stay occupancy rejection and full rollback. |
| Reused bed IDs in different rooms updated a bed in the original room while claiming success for the second room. | Require the existing bed's room to match on conflict and reject zero-row conflicting upserts. | Real duplicate cross-room identity test, no rooms retained after failure. |
| Legacy attendant `photoDataUrl` was omitted. | Populate the new `patient_attendants.photo_data_url` column from migration 003. | Exact synthetic photo payload queried from PostgreSQL; parent owns schema/API serializer updates. |
| Pricing was stored under one `config` key, yielding an extra JSON nesting level through the existing settings API. | Store each pricing field as its own settings key. | SQL reconstruction returns the original flat pricing object; coordinated with settings-route audit. |
| Upserts updated only a few room/patient/stay columns and silently retained stale source fields on a corrected rerun. | Update the existing mapped non-ledger columns from the explicit source snapshot. No billing calculations were introduced. | Before correction, real test failed because contact remained empty and allergies NULL. After correction, profile, room limits/notes and stay duration/extensions match the corrected source. |
| Financial reconciliation summed the entire target database, including unrelated payments. | Scope sums to source patient and canonical ledger identities. | Preexisting unrelated payment remains present but excluded from import reconciliation totals. |
| CLI defaulted to a sensitive source snapshot and committed when `--dry-run` was omitted. | Explicit export path required; API and CLI default to dry-run; `--apply` required for a CLI commit. Any warning aborts the whole import; CLI exits 2 for rejected data. | Default API rollback tested; no-argument CLI refusal executed; explicit commit and rollback paths tested against PostgreSQL. |
| Error warnings contained PostgreSQL exception text, which can include full records. | Report only safe SQLSTATE codes or a generic invalid/conflicting-record message. CLI fatal output excludes raw errors. | Mocked exception containing a sensitive payload does not expose it in warnings. |
| Attendant IDs concatenated a full patient ID and index, overflowing the schema for a valid 64-character patient ID. | Use the shared deterministic attendant-ID helper; preserve existing short IDs and hash only IDs that exceed the limit. | Real maximum-length patient import and repeat import preserve the same 64-character attendant identity. |

Success counters describe **attempted transaction writes** when `committed=false`. The CLI labels the totals as transaction totals and explicitly says no imported writes were retained. This prevents preview reconciliation from being mistaken for committed database state.

## Executed importer coverage

| Behavior | Evidence type and result |
|---|---|
| Rooms, map/array beds, patients, map/array attendants, stays | Real PostgreSQL inserts and relationship queries; covered |
| Missing optional fields | Sparse synthetic patients/stays import with nullable/default optional values; covered |
| Nested patient/attendant attendance and direct dates | Exact stored JSON and kinds; covered |
| Payment branch/embedded deduplication | Exact ledger counts, amounts, identities and timestamps; covered |
| Repeat import | Same ledger unchanged; no duplicate stay/attendance/attendant rows; covered |
| Changed historical payment | Rejected; original retained; covered |
| Corrected non-ledger rerun | Source profile, room and stay values reflected; covered |
| Invalid date/money, missing patient/room, duplicate registration | Rejections counted and entire import rolled back; covered |
| Failure inside nested patient/attendant write | Patient and earlier attendant inserts rolled back; covered |
| Fatal identity import error and retry | Entire initial transaction rolled back; corrected rerun commits; covered |
| Receipt/transaction duplicates | Same patient transaction identity rejected by real unique index; receipt number uniqueness is not assumed; covered for transaction ID |
| Counters and flat pricing settings | Exact stored values; covered |
| Dry run | Constraints and preview sums execute, then patients/payments/settings absent; covered |
| Unsupported export branches | Nonempty photos/ERP branches force a reported full rollback; covered |
| Dedicated photo-store import, other admin categories, inventory/vendors/purchases/expenses/salaries/sponsorships import | **Not implemented.** Nonempty unsupported branches prevent a commit; no complete-module migration claim. |

## Observed source inconsistencies — aggregate inspection only

Inspected the available directory `migration_reports/global_billing_restatement_20261005_181013_411811`, including source snapshot structure and the top-level structure/status booleans in prior validation/verification reports. Those reports concern earlier billing changes; their booleans were not accepted as evidence for this importer or PostgreSQL migration.

The source snapshot contains:

- 116 patients; 182 stays (165 completed, 17 active); 9 rooms and 47 beds (13 occupied, 34 available).
- 205 top-level payment entries and 180 payment-history entries, with 169 overlapping Firebase keys. Amount-bearing rows across the two branches total 296 but resolve to 188 canonical payment IDs. There are 81 `payments` entries whose Firebase key differs from their embedded ID.
- 187 embedded patient-payment entries, of which 186 have a canonical ledger match and 1 is embedded-only. Including embedded records gives 483 amount-bearing rows and 189 canonical IDs. Seven canonical IDs conflict on imported metadata: 6 transaction IDs and 1 cycle ID. Amount/patient comparisons for shared amount-bearing identities agreed in this aggregate inspection; conflicting metadata must still be reviewed.
- 17 `payments` and 72 `paymentHistory` entries lack amount and patient identity. They are incomplete stubs containing only date and/or transaction ID; they must not become invented zero-value payments.
- 39 stays reference a patient missing from the exported patients branch; 51 reference a missing room. Counts overlap and must not be added as distinct records.
- 1,460 patient-attendance records under 117 dates; 106 reference patients missing from the export. 1,204 attendant-attendance records under 99 dates; none reference a missing patient in this branch.
- Two occupied-bed patient references are missing from the patients branch. One current-stay pointer refers to a non-active stay and one current-stay relationship has a mismatched bed. These are source defects; the importer does not invent corrections or silently free these beds.
- 28 attendants have embedded `photoDataUrl`; the new mapping preserves it. Photo reference targets are not present as a dedicated photo-store branch in this snapshot, so referenced binary photo completeness cannot be established from it.
- 115 patients have a four-digit numeric registration number; one lacks a registration number. The snapshot contains no registration counter. The backend must seed/allocate safely relative to existing registrations; the parent route audit owns this check.

These counts are **not** a runtime import/reconciliation result for sensitive production data. The source was deliberately never imported during this audit. Its existing inconsistencies require explicit review and a complete, consistent export before production migration can be approved.

## Remaining limits and review requirements

1. The importer supports its explicit core collections only. Dedicated photo-store and ERP exports, settings/security categories beyond pricing, and unknown nonempty branches are blocked instead of silently ignored. Their migration is still required if they contain production data.
2. The original migration source is a historical billing snapshot with missing referenced records and conflicting identities. A clean production reconciliation has not been executed or claimed.
3. The importer performs snapshot upserts for non-ledger records. It is an offline migration tool, not conflict-aware ongoing synchronization with post-export production edits. Do not apply a stale snapshot to an actively changing PostgreSQL deployment.
4. Per-record SQLSTATE failures and counts are reported safely, but fatal setup/user/counter/settings SQL errors throw and roll back rather than returning a complete record-level rejection report.
5. Database financial values are exact NUMERIC decimals, and source sums use integer cents. Public `ImportStats.financials` retains the existing numeric reporting interface; it is not an arbitrary-precision serialized ledger.
6. No GUI, screenshots, live Firebase calls, production database mutations, live importer execution, or production cutover were performed.

VERDICT: PASS — the executed synthetic importer regression suite and TypeScript build completed successfully.

Production-source migration readiness remains blocked by the explicit source and coverage limitations above.
