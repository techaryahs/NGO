# Post-admission attendee, billing and collection repair

## Confirmed causes and trace

**Missing attendance row.** Edit Details called `PatientService.updatePatient`, which sent `PUT /api/patients/:id` and correctly saved `patient_attendants`. The subsequent `updateStayAttendantCount` sent `patientSnapshot/attendants`, a Firebase multipath key, through the PostgreSQL stay API. That route updated counts/labels but did not apply this key. `MonthlyAttendanceData.rows` deliberately preferred the admission snapshot, including an empty snapshot, over today's patient roster. The profile therefore showed an attendee while Monthly Attendance did not. Backend billing also preferred the snapshot but retained unknown historical attendance marks, permitting billing and visible rows to disagree.

The patient edit now upserts stable identities and updates active current-admission snapshots, occupancy and the authoritative bill within one locked transaction. New associations have a validated `startDate` in the existing JSON snapshot. The dialog defaults to actual arrival today and allows selecting the actual valid arrival date. Existing association dates survive edits/retries; no attendance is initialized. Removed attendees remain in admission history with an end date. Room transfers carry association metadata forward; a new admission starts its own snapshot. Closed admission snapshots and finalized invoices are not reconciled automatically.

**Payment false success.** Both dashboard Pay Now and profile Pay Remaining call `showPatientPaymentDialog`, then `PaymentService.recordPayment`. Before this repair, an existing receipt with the same UPI reference and amount made the service return its original ID immediately. The dialog interpreted that as a new successful collection; no POST or new ledger transaction occurred. This reproduces the unchanged history/paid/due symptom when the old reference is reused. `payment-reference-before.txt` records the regression failing against that old branch: it emitted `original` instead of rejecting the attempted additional collection. A receipt committed elsewhere could also leave the watched ledger stale when this early-return branch ran.

Outstanding collection now distinguishes the same payment attempt from reuse of an older receipt, including a partial payment on the same invoice and legacy receipts without bill metadata. A reused old reference displays an explicit failure. A response-lost retry of the same attempt retains its timestamp and financial snapshot, refreshes the persisted receipt and does not create a duplicate. New receipts require a server-confirmed transaction ID before success.

**Other confirmed payment contract defects.** Migration 009 already widened receipt IDs to 128 characters while request validation still allowed 64. Fastify's default route parameter limit of 100 also made some valid long IDs unreachable after persistence. Validation and routing now support the existing 128-character schema. Regression tests exercise POST and GET of a long receipt ID.

**Outstanding integrity.** The shared collection action sends optional `collectOutstanding: true`. After idempotency checks, the backend validates the requested collection against a fresh authoritative balance under the patient row lock. Receipt insertion, billing persistence and COMMIT remain in the established transaction. Existing advance/overpayment, edit, refund and authorization workflows remain covered. Failed and concurrent excessive collections cannot create ledger rows. Recalculating a bill never creates a payment.

The exact failure on the deployed VPS is **not established**: no deployed code, request logs, bank references or production records were accessed. A distinct-reference additional payment already followed the transactional commit path in the checked-out code. The confirmed local failure paths above are repaired; they are not proof that a particular reference or backend version caused the screenshots.

## Billing preservation

No tariff constants or threshold formulas were changed. Backend and Flutter billing exclude attendee marks before association and retain independent patient/attendee treatment. Pending/Absent attendees add no attendee charge. The existing patient projection, actual Present threshold, reserved Private base, transfer-day ownership, checkout cutoff, rejoin and finalized-invoice rules remain in place.

Dynamic stay `base_cost` and `extra_attendant_cost` now come from the same authoritative daily tariff calculation as `total_cost`. General patient/attendee charges are separate; Private's included attendee remains in its base. Explicit aggregate overrides do not receive an invented split. No parallel balance or pricing service was added.

## Changed files

| File | Purpose |
|---|---|
| `backend/src/app.ts` | Route parameter length matches existing 128-character financial/stay IDs. |
| `backend/src/routes/patients.ts` | Atomic attendee upsert, ownership/duplicate/capacity checks, active admission association, occupancy and billing refresh; preserve creation history. |
| `backend/src/routes/stays.ts` | Preserve association metadata across transfers within one admission. |
| `backend/src/routes/attendance.ts` | Enforce association periods for ID and unambiguous legacy-name attendance, including admission/transfer history; preserve bulk merge semantics. |
| `backend/src/services/attendant_roster.ts` | Validate new association dates and retain established association metadata. |
| `backend/src/services/billing.ts` | Apply association boundaries to authoritative charges/Pending requirements; persist separate patient/attendee amounts from the existing tariff. |
| `backend/src/routes/payments.ts` | Validate outstanding collections against the authoritative locked balance before insertion, after safe retry recognition. |
| `backend/src/validation.ts` | Validate the additive collection flag and align payment IDs with migration 009. |
| `lib/screens/patients/widgets/edit_patient_dialog.dart` | Send actual new attendee arrival date; remove redundant PostgreSQL snapshot/count update after atomic patient edit. |
| `lib/screens/attendance/attendance_service.dart` | Bound actual attendee row intervals to persisted association dates. |
| `lib/services/patient_service.dart` | Publish changed stay snapshots after the committed edit so retained attendance screens rebuild. |
| `lib/utils/stay_billing.dart` | Match association eligibility in existing Flutter preview/legacy billing. |
| `lib/screens/patients/widgets/payment_dialog.dart` | Use outstanding-collection API mode and a stable attempt timestamp; retain existing server-error dialog behavior. |
| `lib/services/payment_service.dart` | Reject misleading reference reuse, require committed acknowledgement, refresh receipt/history on retry. |
| `backend/tests/attendant_roster.test.ts` | Arrival defaults/validation, identity/date stability, departure bounds and legacy metadata. |
| `backend/tests/client_billing_rules.test.ts` | Late arrival, Pending/Absent changes, imported early marks across transfers, patient/attendee split and included Private attendee. |
| `backend/tests/workflows.integration.test.ts` | Full actual API lifecycle for day-1/day-6 arrivals, partial/full/retried collections, ownership races, invalid edits, retained history and occupancy. |
| `backend/tests/payment_financial.integration.test.ts` | Real database collection, history/ledger, competing stale balances and long IDs. |
| `test/post_admission_attendance_test.dart` | Independent rows/marks, reload/save idempotency, arrival dates, months/filtering and Flutter billing parity. |
| `test/post_admission_attendance_screen_test.dart` | Actual attendance widget receives edited roster; search, room filter, save, month navigation and reloaded mark. |
| `test/post_admission_payment_test.dart` | Actual shared payment dialog/service success, rollback/error, lost acknowledgement, reference reuse, retry and watched history refresh. |
| `test/postgres_real_workflows_e2e_test.dart` | Flutter admission/edit/attendance/payment services through real HTTP/Fastify/PostgreSQL for both full and partial-period attendee arrival. |
| This audit directory and `.gravitas/sessions/post-admission-20261022/` | Verification records, deployment instructions and read-only reconciliation candidates. |

Pre-existing installer/platform/generated-file changes and earlier audit/session directories were retained. No commit, push, deployment or installer packaging was performed.

## Verification evidence

All commands below were actually executed. Logs are in this directory.

| Command | Result | Evidence |
|---|---|---|
| `npm run build` in `backend/` | Passed | `backend-build.txt` |
| `npm test -- --reporter=dot --exclude=**/*.integration.test.ts` | 179 passed | `backend-unit.txt` |
| `npm run test:postgres` | 179 ordinary + 191 PostgreSQL tests passed; all 9 opt-in database suites executed | `postgres-matrix.txt` |
| `flutter test --no-pub --concurrency=1 --reporter expanded` | 503 passed, including real PostgreSQL workflows | `flutter-all.txt` |
| `flutter test --no-pub test/postgres_real_workflows_e2e_test.dart --plain-name "post-admission Flutter lifecycle" --reporter expanded` | Both day-1 and day-6 scenarios passed against real PostgreSQL | `flutter-lifecycle.txt` |
| `flutter test --no-pub test/post_admission_attendance_screen_test.dart --reporter expanded` | Actual screen regression passed | `flutter-attendance-screen.txt` |
| `flutter analyze --no-pub` | No issues | `flutter-analyze.txt` |
| `flutter build windows --release --no-pub` | Passed; `build/windows/x64/runner/Release/ngo.exe` | `flutter-build.txt` |

The PostgreSQL matrix includes workflows (47), modules (41), importer (22), payment financial accuracy (39), scalability (4), settlement (33), auth (3), migrations (1) and restart/persistence (1). These are isolated local PostgreSQL 16 databases, not mocks and not the production database. The Flutter full suite also starts its own verified temporary PostgreSQL instance for real service-level HTTP workflows.

The baseline lifecycle asserts ₹2,000 initial patient bill/payment, a persisted post-admission attendee row, ten manually Present attendee dates, ₹4,000 bill/₹2,000 due, and then a distinct committed ₹2,000 receipt. Reloaded patient history and ledger each contain two receipts and zero due. The mid-stay variant has five eligible attendee days, a ₹3,000 bill, and a ₹1,000 additional receipt. No earlier attendee records are fabricated. Partial-payment, same-request retry, invalid amount, failed/rolled-back request, concurrent collection, edits, refunds, finalized records, long-stay, transfers, checkout and rejoin cases are exercised by the new and existing suites.

Initial verification failures were corrected rather than hidden: fixture room number/identifier constraints, a new test API signature, the long receipt-ID router limit, an analyzer warning, and an accidental concurrent use of the shared disposable PostgreSQL test port. Database-owning suites were subsequently run sequentially. No pricing rule was relaxed to pass a fixture.

## Release and existing records

See `DEPLOYMENT.md`. No new migration or configuration variable is required; check existing migration 009 status, deploy the backend first, and release a rebuilt Flutter client through the normal process. The locally built executable is verification evidence, not a VPS deployment or an installer release.

`reconciliation-review.sql` contains SELECT-only candidate reports and was not executed against production. Determine actual arrival dates and receipt evidence before any approved correction. Previous attendant PUTs deleted/reinserted rows, so creation timestamps are not reliable historical arrival proof. Preserve finalized invoices, prior payments, legitimate split receipts and refunds; no automatic financial reconciliation is included.
