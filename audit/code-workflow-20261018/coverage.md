# Code workflow accuracy audit — 18 October 2026

Scope: code-driven tests only. No computer-use skill, desktop interaction, existing application database reset, production/VPS access, or real payment was used by this worker.

Gravitas policy record: `{"planning":"compact","context_depth":"dependency","verification_depth":"impact","delegation":"delegated-worker","reason_codes":["broad-workflow-inventory","isolated-integration","shared-repository"]}`.

Decision: extend `backend/tests/modules.integration.test.ts` with existing-record ERP edit/delete regressions. Evidence: the application service exposes edit/delete methods and API routes exist, while prior tests only requested missing IDs. These new cases exercise authorization, persistent partial updates, zeros, validation rollback, and deletion. Risk: low; only tests and this audit are edited, and all writes target the guarded synthetic module database.

Follow-up decision, authorized by parent: remove the `updated_at` assignment from the sponsorship update SQL in `backend/src/routes/erp.ts`. The new existing-record test returned 500, and PostgreSQL reported that column does not exist; both schema source and executed schema contain only `created_at`. This changes one SQL assignment without introducing a migration. Final verification follows below.

Replan, authorized by parent: fix PostgreSQL purchase stock accounting in the same ERP route file and `lib/services/inventory_expense_service.dart`. Purchase creation, edit, item move/detachment and deletion now adjust stock in the same transaction as the purchase record. A transaction advisory lock serializes the purchase identity; existing purchase rows and affected inventory rows are locked, with item IDs ordered to avoid opposite-move deadlocks. Stock never falls below zero, matching the prior client rule. PostgreSQL client methods return after the acknowledged server write, avoiding a second stock adjustment; the RTDB path is unchanged. Add targeted inventory GET and executable transaction/concurrency/failure tests. No historical stock recalculation, migration or existing database reset is performed.

Second replan, authorized by parent: complete existing ERP form persistence and salary writes. Actual Flutter model maps contain vendor GST/notes, purchase and expense payment details, expense item metadata, payroll role/month/payment metadata, and sponsorship booking fields that the API previously dropped. Add migration `007_erp_form_details.sql` with bounded JSONB metadata columns, persist only explicitly validated form fields, retain authoritative database financial/identity fields, and add admin-only salary mutations using the existing gross-minus-deductions rule. Add reproductions before implementation, then execute targeted API and independent Flutter model/service roundtrip tests. No backup/profile placeholder implementation, production deployment, historical backfill or global restatement is included.

## Isolation and reproducibility

- PostgreSQL 16 container: `ngo-desktop-qa-pg16-20261018`, published only at `127.0.0.1:55439`, synthetic `ngo_audit` user with test-only trust authentication. Existing application containers and volumes are untouched.
- Workflow suite exclusively uses `ngo_audit_workflows`; module suite uses `ngo_audit_modules`; auth/importer/migration suites each use their exact `ngo_audit_auth`, `ngo_audit_importer`, and `ngo_audit_migrations` guards.
- Every integration command explicitly sets `NODE_ENV=test`, `POSTGRES_HOST=127.0.0.1`, `POSTGRES_PORT=55439`, database/user fields, and `DATABASE_URL=postgres://ngo_audit:unused@127.0.0.1:55439/<dedicated-database>`. No `.env` credentials or target are inherited by these connections.
- Modules require database-side loopback identity. An ephemeral `node:22-alpine` container shares the PostgreSQL container network namespace, copies only backend package manifests/source/tests/migrations from a read-only bind mount, installs its own Linux dependencies, and runs the suite at `127.0.0.1:55439`. Existing guards were not weakened. The image's default command is overridden; no application server is started.
- Backend units disable every integration opt-in and use a deliberately nonexistent synthetic database URL. `POSTGRES_PORT=5432` is retained only because the existing config unit asserts that default; the explicit URL still points at the isolated port 55439.

## Observed results

| Run | Result | Log |
|---|---|---|
| Backend unit baseline | 70 passed, 85 integration cases skipped; 6 files passed, 6 skipped; 9.97 s | `backend-unit.log` |
| PostgreSQL API workflows | 32/32 passed; 12.36 s | `backend-workflows.log` |
| PostgreSQL API workflows after ERP and payment changes | 32/32 passed; 9.70 s; signed refund without excess now correctly asserts 409 | `backend-workflows-final.log` |
| PostgreSQL modules baseline | 27/27 passed; 2.06 s | `backend-modules.log` |
| PostgreSQL modules extended, before fix | 31 passed, 1 failed; sponsorship edit returned 500 because SQL referenced absent `sponsorships.updated_at`; 3.30 s | `backend-modules-extended.log` |
| PostgreSQL modules after sponsorship fix, concurrent load | 24 passed, 8 failed: seven existing 5-second timeouts and a dependent missing-attendance assertion; sponsorship CRUD passed. This run is retained as failed evidence. | `backend-modules-final.log` |
| PostgreSQL modules final, after both fixes | 35/35 passed; 2.80 s; explicit 30-second case timeout | `backend-modules-stock-final.log` |
| PostgreSQL authoritative UID boundaries | 3/3 passed; 2.87 s | `backend-auth-postgres.log` |
| PostgreSQL importer/reconciliation | 21/21 passed; 12.80 s | `backend-importer-postgres.log` |
| PostgreSQL upgrade and rollback | 1/1 passed; 8.86 s | `backend-migrations-postgres.log` |
| Backend TypeScript build before SQL fix | Passed (`tsc`, exit 0) | `backend-build.log` |
| Backend TypeScript build after both fixes | Passed (`tsc`, exit 0) | `backend-build-stock-final.log` |
| Safe Flutter existing test suite | 367 passed, no failures; 25 files; 2 min 5 s; real PostgreSQL E2E file excluded | `flutter-safe-suite.log` |
| Flutter purchase stock ownership regressions | 3/3 passed after final client change | `flutter-inventory-purchase.log` |
| Backend final unit regression | 70 passed, 130 explicit integration skips; 6 files passed, 8 skipped; 7.69 s | `backend-unit-final.log` |

The workflow suite intentionally terminates one idle database backend to test pool recovery, which logs PostgreSQL `57P01`; its case passed. Migration timestamp warnings are emitted by the existing numbered SQL naming convention; all migration assertions passed. These observations are not desktop measurements.

## Workflow coverage matrix

Flutter evidence below comes from the 367-case safe suite (real application services with MockClient/local HTTP, in-memory fixtures or SQLite as defined by each test), plus three new purchase regressions after the client change. The parent separately owns `postgres_real_workflows_e2e_test.dart`, which connects Flutter services to real Fastify/PostgreSQL. Mock-based tests are not described here as real database execution.

| Workflow | Observed code-based evidence | Limits / remaining validation |
|---|---|---|
| Auth and roles | Backend units cover signed token claims, malformed/unsigned tokens, authoritative UID role checks, and forbidden operations. Real PostgreSQL verifies 65/128-character UID provisioning and creator preservation. Module suite exercises staff/admin/volunteer boundaries. Flutter verifies restored-role/cache ordering and failed-role retry. | Real Firebase login, token refresh/revocation, email/password reset, logout and account UI are not exercised by signed test keys. |
| Rooms and beds | API suite covers create/edit, label conflicts, concurrent room versions, exclusive bed allocation, multi-bed admission, rollback and deletion guards. Flutter room selection, targeted stay reads, card rendering and inline editor pass. | Parent owns additional real database Flutter lifecycle execution. |
| Patient registration and attendants | API validates fields/dates, partial-update preservation, duplicate registrations, atomic patient/stay/bed creation, attendants, identical retries, conflicting retries, simultaneous registration and second-bed rollback. Flutter Add Patient pricing/idempotency/selection, counter sequencing and cache consistency pass. | Real desktop input devices and production identity login are not used. |
| Attendance | Modules verify patient/attendant separation, date validation, bulk transaction rollback, idempotent writes, range/map history; workflow suite verifies concurrent JSONB merge. Flutter calendar/grid, local edits and billing alignment pass. | Production data migration quality requires a separate real-data reconciliation. |
| Bills and totals | API verifies exact decimal payments and authoritative balance version conflicts. Flutter stay billing, calendar alignment, 9 AM checkout, planned exit, overrides and global restatement pass. | PDF/export rendering and printing are not exercised. |
| Cash and UPI payments, retries, refunds | API verifies duplicate retry applies balance once, conflicting retry rejects, concurrent decimal adds and failure rollback. Flutter refund ledgers, UPI URI/reference validation, submit locking and history calculations pass. Final workflow assertions distinguish malformed negative payments (400) from signed refund without excess (409). | Parent's financial worker owns additional real-PostgreSQL refund/edit/delete cases. No bank/provider settlement is performed or verified. |
| Discharge, rejoin and history | API synchronizes stay/patient/bed/room, handles repeat discharge and final multi-bed departure, preserves historical stay bed and blocks destructive deletion. Flutter historical access, later-admission preservation and refund attribution to the previous admission pass. | Parent owns additional real database Flutter lifecycle execution. |
| Settings | Modules verify category/key writes, role boundaries, false/zero preservation; registration counters are concurrent and safe-range guarded. Flutter settings transport mapping passes. | Manual Backup only writes a timestamp; no database dump occurs. Restore Database is a UI placeholder. Auto-backup stores a preference; scheduling is not demonstrated. Firebase password change is not tested against the real identity provider. |
| Profile | Read source: the user profile displays email and UID. | Profile role is hardcoded as `Super Admin`; Edit Profile displays a coming-soon message. Profile behavior has no runtime test in this worker's run. |
| Photos | Modules verify patient/attendant photo identity, microsecond version storage, stale-write rejection, metadata/reference validation. Flutter historical-photo identity, migration isolation, upload/download/delete and cache tests pass. | Camera/file-picker operation and rendered image quality are not exercised. |
| Inventory and vendors | Modules verify create/list, authoritative creator, duplicate/malformed rejection, persisted partial edits including zeros/empty phone, forbidden volunteer edits/deletes and existing-record deletion. Targeted inventory GET is tested. Flutter model mapping passes. | Rich vendor fields outside the API schema, such as GST/notes, are not proven to round-trip. |
| Purchases and expenses | Modules verify exact decimals, foreign-key rollback, precision rejection, partial edit/delete, atomic stock creation/delta/move/detach/deletion, ten concurrent increments, opposite item moves, simultaneous edits, injected failure rollback and zero clamp. Three Flutter tests verify one server write per purchase mutation, awaiting acknowledgement and error propagation. | Extra purchase/expense business fields absent from the API schema, including nested payment details and expense subcategory/item detail, are not proven to persist. Historical stock is not recalculated. |
| Salaries | Module suite inserts synthetic salary directly and verifies list read with exact stored amount. | Salary API has only collection GET. Flutter service exposes add/edit/delete which are not implemented server-side; baseline explicitly checks POST is 404. |
| Sponsorship | Modules verify create/list, patient relationship, invalid reference rejection and existing-record edit/delete after correcting the nonexistent SQL column. Flutter sponsor-name mapping passes. | API schema omits sponsor mobile, reference, occasion/honoree, booking/payment statuses and transaction reference used by the Flutter booking form. Full booking round-trip accuracy is not established; this audit does not add those fields. |
| Import and database maintenance | 21 importer cases cover deduplication, dry run, reconciliation and rollback. Migration suite verifies upgrade, constraints, rollback and reapplication. | Persistence restart suite requires a native disposable cluster and `pg_ctl`, and has not run in this Docker runtime. No shared PostgreSQL container restart was attempted. |

## Remaining limits

The 130 integration skips in the final unit command were intentional; PostgreSQL suites were run separately against their guarded databases. The native cluster restart case was not run. The parent owns additional Flutter-to-PostgreSQL, payment accuracy and scale results and records them separately. Passing tested scenarios does not establish that placeholders, missing API operations or omitted business fields are implemented.

VERDICT: PASS
