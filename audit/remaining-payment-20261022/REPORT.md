# Partial payment followed by remaining collection

Baseline: HEAD and the user-specified deployed commit both resolve to `b2beb0828f70e5ecc46897b2d534e0b4386394e7`. No VPS or production database access was performed.

## Confirmed cause

The exact `Bad state: This reference is already recorded with a different amount` string came from `PaymentService._recordPayment` in Flutter. The service reads the fresh patient, finds the existing receipt by normalized UPI reference, and rejects a different amount **before** calling `BackendApiService.createPayment`. Therefore there is no payment POST for this rejection. That duplicate protection is correct: an earlier ₹1,400 transfer's UTR cannot represent a new ₹2,400 transfer.

I did **not** find a previous-reference prefill in this commit. The shared dialog already allocated nonstatic empty reference/receipt controllers and disposed them. Its four production callers (patient profile, Payments dashboard, patient list and Add Patient) pass amounts/patient information, not UTRs. `patient_financial_dialog.dart` reads financial history and handles refunds; it does not prefill or launch this collection dialog. The reference's actual source in the reported running UI is not established. It would be inaccurate to claim a controller/cache prefill defect was reproduced.

The confirmed UX gaps were an unactionable `Bad state` error, absent phase/request diagnostics and a dialog amount based on potentially stale caller totals. The fix addresses those gaps and explicitly tests clean initialization/reopening rather than weakening duplicate protection.

## Changes

| File | Purpose |
|---|---|
| `lib/screens/patients/widgets/payment_dialog.dart` | Give each invocation its own stable widget identity; explicitly empty reference/receipt controllers; disable their platform autofill, autocorrect and suggestions; read the authoritative invoice before displaying a collectible QR; load its current cycle/total/paid/due; block collection when that read fails and allow retry; refresh after a definitive 409. Keep retry metadata intact after ambiguous transport/server failures. |
| `lib/services/payment_service.dart` | Add `collectionBalance` backed by the existing billing projection. Use an actionable reference exception without the `Bad state` prefix. Add safe validation/submission/acknowledgement/failure diagnostics with random request IDs, categories and HTTP status. Retain existing same-attempt recognition and ledger refresh. |
| `lib/services/backend_api_service.dart` | Forward the request ID with payment POST, report response status safely and carry the server response ID on HTTP errors. |
| `backend/src/app.ts` | Validate/propagate correlation IDs, return/expose `x-request-id`, log payment response status/category, and avoid printing payment exception/database detail that could contain references. |
| `backend/src/routes/payments.ts` | Make conflicting receipt/reference reuse actionable. Fingerprint comparisons, patient locking, outstanding validation, INSERT, billing persistence, COMMIT and rollback are unchanged. |
| `test/post_admission_payment_test.dart` | Add the exact ₹3,800/₹1,400/₹2,400 shared-dialog scenario, blank/reopened controls, actionable rejection then distinct successful UTR, safe diagnostics, current balance and failed-balance retry tests. Preserve lost-acknowledgement and same-attempt retry tests. |
| `test/attendance_payment_implementation_test.dart` | Supply an authoritative-balance stub to its existing QR/invalid-reference widget test; actual payment assertions remain. |
| `test/postgres_real_workflows_e2e_test.dart` | Add a 19-day General-bed invoice through real Flutter services, HTTP and PostgreSQL: ₹1,400 then ₹2,400, old UTR rejection, idempotent retry, ledger SQL checks and consistent watched dashboard/profile balances. |
| `backend/tests/payment_financial.integration.test.ts` | Add exact-amount real-database partial/remaining receipts, rejected old-reference reuse, request-ID correlation, history/ledger and zero balance. Existing concurrent collection and rollback tests execute too. |
| `backend/tests/payment_diagnostics.test.ts` | Assert correlated safe server logs and responses without UTR, token, credentials or raw database error text. |

No billing, room pricing, attendance, financial-history migration or stored production data was changed. Pre-existing installer/platform changes were retained. No commit/push/deployment was performed.

## Request trace and diagnostics

All four production entry points use the shared dialog → `PaymentService.recordPayment` → fresh patient/duplicate validation → authenticated `POST /api/payments` → patient row lock → fingerprint idempotency → authoritative outstanding validation → receipt INSERT and billing persistence → COMMIT → acknowledged cache/history refresh.

The dialog now gets its current collection amount from `GET /api/patients/:id/financials` through `billingUpdates`, the repository's existing invoice service. That read creates no transaction and does not copy an earlier UTR into an input.

Example diagnostic categories contain no amount, patient identity, UTR or receipt details:

```
[Payment] requestId=payreq_<random-id> phase=validating
[Payment] requestId=payreq_<random-id> phase=failed category=reference_reuse status=none
```

This is a client rejection with no POST. A real submission has `phase=submitting endpoint=POST:/api/payments`, then `phase=response status=<HTTP status>`. The VPS logs the same request ID with response status and a payment error category. `phase=acknowledged` follows server acknowledgement or verified recognition of the same already-committed attempt. A timeout is not proof that the receipt failed to commit; retry the same attempt rather than recording another transfer.

## Verification

Actual command outputs are retained alongside this report:

| Command | Evidence |
|---|---|
| `npm --prefix backend run build` | `backend-build.txt` |
| `npm --prefix backend test -- --reporter=dot --exclude=**/*.integration.test.ts` | `backend-unit.txt`: 180 passed |
| `npm --prefix backend run test:postgres` | `postgres-matrix.txt`: 180 ordinary plus 192 database integration tests passed; all nine opt-in suites ran |
| `flutter test --no-pub --concurrency=1 --reporter expanded` | `flutter-all.txt`: 508 passed, including real database workflows |
| `flutter analyze --no-pub` | `flutter-analyze.txt`: no issues found |
| `flutter build windows --release --no-pub` | `flutter-build.txt`: passed; `build/windows/x64/runner/Release/ngo.exe` |

Database tests run only on the infrastructure's verified temporary local PostgreSQL 16 clusters. Backend and Flutter suites that own the fixed PostgreSQL test port were run sequentially. No production records are used to satisfy tests. Early test failures were test-harness API/fake-async issues and lint findings; they were corrected and rerun.

## Safe deployment

1. Review this patch and the test evidence. Retain the current application/backend release and the usual database backup.
2. Build the backend with the established production configuration (`npm ci`, `npm run build` in `backend/`) and restart the VPS's existing backend service/container using the normal release process. No migration or new environment variable is required.
3. Preserve `X-Request-Id` and `x-request-id` through any reverse proxy. The new backend CORS configuration permits/exposes these headers. Deploy the backend before a browser client that sends the new header.
4. Rebuild/distribute the Flutter application using its existing production API configuration. `flutter build windows --release --no-pub` was executed locally; installer packaging/distribution was not performed.
5. On staging, verify empty new/reopened UTR/receipt inputs, current outstanding amount, actionable duplicate rejection, a distinct valid transfer reference and refreshed history/ledger/balances. Do not reuse or alter a real past receipt to test the release.

The backend's payment persistence and outstanding/concurrency rules have not been relaxed. There is no automatic reconciliation, refund or historical payment correction in this patch.
