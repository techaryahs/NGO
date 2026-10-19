# Attendance, counters, settings, photos and ERP audit

Executed 16 October 2026. Automated source inspection, Fastify injection and real PostgreSQL assertions only; no GUI or production operations.

## Runtime evidence

The module suite verifies its target **before migration or mutation**: connection URL hostname `127.0.0.1`/`localhost`, port `55439`, exact database `ngo_audit_modules`, actual server address loopback, actual database name and `server_version_num` in `[160000,170000)`. The root audit created a fresh disposable PostgreSQL 16.12 cluster. Test identities and records are synthetic. Rerun cleanup deletes only the suite's `mod_audit_` records after those guards; it never truncates a table. No production connection is used.

Commands, run in `backend/` using PowerShell:

```powershell
$env:NODE_ENV='test'
$env:AUDIT_DATABASE_TESTS='1'
$env:POSTGRES_HOST='127.0.0.1'
$env:POSTGRES_PORT='55439'
$env:POSTGRES_DB='ngo_audit_modules'
$env:POSTGRES_USER='ngo_audit'
$env:POSTGRES_PASSWORD='audit-local-only' # Disposable synthetic cluster only.
$env:LOG_LEVEL='silent'
npx vitest run tests/modules.integration.test.ts --no-file-parallelism
npm run build
```

- First executable baseline after correcting the test guard's inet formatting: **15 failed, 8 passed, 23 total**. The earlier guard attempt safely stopped before data writes because PostgreSQL's `inet::text` included `/32`; the test now uses `host(inet_server_addr())`.
- Intermediate run: **2 failed, 22 passed**. One failure was an overbroad test assertion rejecting the safe generic word “constraints”; the other exposed the test helper's handling of scalar HTTP payloads. The helper now explicitly JSON encodes `false` and `0` with the JSON content type. These test issues were corrected.
- Final run after source/test changes: **27 passed, 0 failed**, one integration test file, duration 4.67 seconds. This is a real PostgreSQL API/database suite; only Firebase signing keys are supplied by a mocked trusted-key HTTP response and ephemeral RSA test signer.
- Final `npm run build`: exit 0, TypeScript compilation completed.
- Migration runner executed the initial schema, then upgrades 002, 003 and 004 as they were added; an earlier rerun reported `No migrations to run!`. The migration library emitted `Can't determine timestamp for 001/002/003/004` warnings for numeric filenames, but the migrations completed. Full migration/persistence results belong to the consolidated audit.

## Endpoint coverage matrix

All paths below have `/api` prefix. Authentication and role lookups use the real `users` table. The role policy follows `database.rules.json`: sensitive module reads/writes require staff/admin; administrative setting writes require admin; ERP reads allow any authenticated role and ERP writes require staff/admin.

| Endpoint | Database operations | Executed coverage / limitation |
|---|---|---|
| GET `/attendance` | Filter/date/order SELECT of `attendance_records` | Patient/date/kind filters, array and map output, all dates preserved in history map, correct calendar date in Windows timezone, invalid filter 400, unauthorized 401, volunteer 403. |
| POST `/attendance` | Upsert one kind/date/patient record | Create, update, repeated request, distinct patient/attendant kinds and resulting stored payload, invalid dates/kinds/missing fields 400, missing patient 409. |
| POST `/attendance/bulk` | BEGIN, upsert every record, COMMIT/ROLLBACK | Successful/repeated bulk and actual row count; later invalid patient rolls back an earlier update, retaining the old stored payload. No SQL/constraint identifiers leak in response. |
| GET `/counters/:name` | SELECT `system_counters` | Read allocated value and staff/admin access. |
| POST `/counters/:name/next` | Atomic INSERT/ON CONFLICT with numeric patient-registration seed | Two simultaneous ordinary allocations return 1/2; two simultaneous registration allocations after imported registration 1042 return 1043/1044; stored value and unchanged patient registration asserted. Safe-integer exhaustion returns 409 without increment. |
| PUT `/counters/:name` | Validated upsert | Nonnegative safe integers accepted; negatives, fractions, invalid strings, unsafe integers rejected; volunteer denied. |
| GET `/settings/:category` | SELECT all key/value rows | Reconstructed category, scalar false/zero, category merge result and role denial. |
| GET `/settings/:category/:key` | SELECT one key | Reads stored false correctly; missing key returns an empty object under the existing API contract. |
| PUT `/settings/:category/:key` | Upsert JSONB key | Admin write, staff denial, false/zero preserved in DB and response. |
| PUT `/settings/:category` | Transactional upsert of supplied children | Added for existing pricing/security category writes; supplied keys merge while omitted keys remain. Whole body validated before the transaction. |
| GET `/photos/*` | SELECT `patient_photos` | Patient and attendant retrieval with patient relationship, 404, invalid path/role denial, precise numeric version. |
| PUT `/photos/*` | Conditional atomic versioned upsert | Dart microsecond version succeeds with upgraded BIGINT column; repeated identical writes succeed; stale writes return 409 and retain newer bytes; malformed paths/base64/types/versions and patient path/body mismatch rejected; missing patient FK conflicts. |
| GET/POST `/erp/inventory` | SELECT/INSERT `inventory_items` | List/create, real stock/minimum values, server-authoritative creator despite forged request creator, missing-name 400, duplicate-ID 409, volunteer read/write policy. |
| GET/POST `/erp/vendors` | SELECT/INSERT `vendors` | List/create, stored contact, missing-name 400, volunteer write denial. |
| GET/POST `/erp/purchases` | SELECT/INSERT `purchases` | Persisted vendor/item relationships, exact 0.10/0.30 decimals; invalid item rejects without stored purchase; list contains actual record; invalid quantity rejected. |
| GET/POST `/erp/expenses` | SELECT/INSERT `expense_entries` | Actual stored/listed 12.34; NaN and 0.001 rejected instead of rounding/500; role denial. |
| GET `/erp/salaries` | SELECT `salaries` | Seeded synthetic salary retrieved, including net_salary 100.20 and staff/month/year; no salary API write exists. |
| GET/POST `/erp/sponsorships` | SELECT/INSERT `sponsorships` | Actual patient relationship and 30.10 precision in DB/list; invalid date 400, missing patient 409, role denial. |
| GET/PUT/DELETE `/erp/:module/:id` | No route | Explicit tests confirm 404 for all six ERP modules. No individual read/update/delete capability is claimed. |
| POST `/erp/salaries` | No route | Explicit 404 test. |

## Confirmed defects corrected

1. **Attendance dates shifted backwards one day.** PostgreSQL DATE was parsed as local midnight then serialized with UTC `toISOString()`. The baseline returned `2026-10-01` for stored date `2026-10-02`. SELECT now requests `attendance_date::text`, retaining calendar-date semantics.
2. **Map history lost earlier dates.** Every row overwrote `map[patientId]`. History maps now group date then patient; date-filtered maps retain patient keys. Map requests default to patient attendance when kind is omitted, preventing attendant data from replacing patient attendance.
3. **Attendance validation and error leakage.** Missing/malformed input produced 500s or accepted noncanonical dates; bulk returned PostgreSQL error messages. Strict calendar date, kind, patient ID and object validation now reject malformed requests; rolled-back DB errors use the centrally sanitized handler.
4. **Counters accepted negative/unsafe/inexact values and ignored existing registrations.** Input now requires a nonnegative safe integer; allocation is bounded and atomically starts above existing numeric patient registration numbers. Alphanumeric registrations are intentionally excluded from this numeric sequence.
5. **Settings discarded false/zero and lacked the category write used by callers.** `body || {}` became an explicit undefined check. Category PUT validates all keys and transactionally merges supplied values. Administrative authorization is enforced.
6. **Photos accepted mismatched patient IDs and stale overwrites.** Path shape, patient ownership, bounded base64, content type and safe integer version are validated; an atomic SQL version predicate rejects stale/conflicting data and permits identical retries. The root upgrade changes the photo version column to BIGINT because Dart sends microseconds; responses convert this safe integer to a JSON number.
7. **ERP accepted malformed financial/input values and generated collision-prone millisecond IDs.** Required fields, references, date shapes, stock and two-decimal money values are validated; server-created IDs use built-in random UUIDs. Real FK/unique violations now receive centrally sanitized 409 responses. Creation still uses the verified server-side user ID.

Modified module files: `backend/src/routes/attendance.ts`, `counters.ts`, `settings.ts`, `photos.ts`, `erp.ts`; regression suite `backend/tests/modules.integration.test.ts`. Shared authentication, error handling, schema upgrades and importer fixes are owned by other audit work and covered in the consolidated report.

## Remaining cutover blockers and limits

- **ERP is incomplete and does not match Flutter model serialization.** Endpoints return raw snake_case rows/ISO dates/string NUMERICs, while Flutter reads camelCase maps and epoch dates. Existing Flutter services use `inventory_items`, `vendors`, `purchases`, `expense_entries`, `salaries`, `sponsorships`; the backend exposes `/erp/...`. Update/delete and individual reads are absent; salary creation is absent. No claim of full ERP client compatibility is made.
- Several real model fields have no schema/API destination: vendor `mobileNumber` differs from `phone`, and GST/notes/audit metadata are incomplete; purchase `paymentDetails` and update metadata are omitted; expense model uses `totalAmount` plus nested payment details and category/item/vendor fields rather than API `amount`; salary model uses employeeName/role/salaryMonth/grossSalary rather than staff_id/month/year/base_salary; sponsorship booking/reference/occasion/payment/transaction fields are omitted. Strict financial input now rejects the unsupported expense shape instead of silently storing zero. Other extra metadata remains a compatibility gap. These require a deliberate model/schema/API adapter, not speculative billing changes.
- Purchase insertion does not atomically adjust stock. Flutter's existing inventory service does this in separate calls. Stock reconciliation semantics were not changed; the backend should not be enabled for that workflow until an agreed atomic operation/adapter is implemented and tested.
- Photos validate encoded data and metadata, not actual image decoding. Attendant photo keys and attendant-attendance payload keys remain JSON/path labels tied to a patient; no attendant foreign key is claimed.
- Counter `/next` deliberately allocates a new number on every call. A lost response followed by retry can leave a harmless gap; this endpoint has no idempotency key. The allocator avoids duplicates, not gaps.
- Ordinary settings (`settings/...`) and admin settings (`admin_settings/...`) are separate Firebase branches, but the current backend has one category namespace. Root settings reads and administrative category parity remain adapter work. Importer per-key pricing correction is coordinated separately.
- No HTTP socket/load test, live Google-key network test, GUI test or production cutover was performed in this module audit. The successful tests demonstrate the implemented backend operations and database consistency, not complete Flutter runtime support.

VERDICT: PASS for the 27 executed module integration tests and TypeScript build. Production cutover remains blocked by the explicit unsupported workflows and model/API differences above.
