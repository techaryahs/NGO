# Client billing implementation — 22 October 2026

**Implementation and local validation passed.** The working tree is ready for review;
nothing was committed or deployed. Real historical exposure remains unknown.

## Scope and preservation

Starting branch: `main`; starting HEAD: `0596354a855740f93a93043b2073a2877317ce40`.
The security baseline `129cfe74ae5a5f551c89d71fef0e4efe2f0bf3f8` is an ancestor.
Token verification, authoritative account roles, CORS, secure credential requirements
and user endpoints were not changed. New APIs use the existing staff/admin authentication hook.
No commit, push, merge, deployment, VPS access or production-data operation was performed.

Pre-existing installer script changes, the existing installer executable, and
macOS/Windows generated plugin files were outside implementation scope. They
remain in the working tree. The Windows application build is a validation step;
the installer is not rebuilt.

## Root causes and corrections

| Regression / inconsistency | Root cause | Result |
|---|---|---|
| General multi-bed estimate disagreed with invoice | Flutter multiplied person pricing by occupied beds | One patient charge; independent Present attendant charges. Bed allocation remains independent. |
| New admissions could use legacy tariff settings | Mutable global monetary settings overrode client-approved amounts | New service/projection boundaries normalize General/Lobby 200, Private 700, extra Private attendant 200 and one included attendant; long-stay rates are 250/900/300. Explicit manual and stored per-stay pricing overrides remain supported. |
| Private included allowance could differ | Calculation read a legacy configurable allowance | Exactly one attendant included; settings UI reflects fixed allowance. |
| Absent Private patient lost reserved base | Entire day was skipped before category selection when nobody was Present | Private room base remains billable even when patient and attendants are Absent. |
| Attendant attendance omitted or collapsed | Backend read individual payloads while API stores nested maps; Flutter used names as keys | Nested/individual legacy shapes supported; stable IDs used throughout; unique legacy-name fallback only. Ambiguous legacy records remain Pending and retained. |
| Pending attendance looked definitive | Missing patient marks treated as billable without explicit provisional metadata; discharge checked only patient marks | Estimates expose Pending/provisional metadata. Patient and required attendant marks are independently validated before finalization. Unknown historical Pending marks also block finalization. |
| Long-stay/extension day inconsistencies | Original and extended durations could be counted twice; effective expiry added an extension to an already extended date | Original duration remains separate; expected discharge already includes extensions. Quotes use marginal projections and shared admission-wide billable-day count. Existing request-ID extension protection retained. |
| Checkout time and tier ignored | Discharge substituted planned dates for actual checkout; inclusive calendar billing had no itemized late adjustment | Actual discharge timestamp is separate; General/Lobby after 09:00 Kolkata uses checkout day's tier and explicitly Present people; exactly 09:00 has no adjustment. Day 60 uses 200, day 61 uses 250. Private retains inclusive base without a new extra surcharge. |
| Settlement preview changed during payment/refund | Receipt processing recalculated without checkout context | Draft checkout timestamp is retained in current admission summary and reused by financial reads and receipt transactions. Transfers/extensions clear it for a fresh projection. |
| Completion bypassed final checks | Last-stay PUT could discharge outside the settlement workflow | Shared finalization transaction validates attendance, ledger settlement and exact bed ownership before completing/releasing placement. Generic lifecycle edits and stay-based rejoin bypasses are rejected. |
| Transfer date selected wrong category | Highest-priced segment owned overlap date, even on downgrade | Destination segment owns the transfer date once; admission threshold continues. |
| Successful transfer left stale money | Placement transaction completed before a separate Flutter recalculation | Projection and stay/patient balances persist in the transfer transaction; redundant Flutter recalculation removed. Retry does not mutate patient version. |
| Rejoin could partially activate a patient | Separate patient/room/stay writes with invented/default planned boundary | Dedicated transactional request creates the cycle, placement/stay and provisional projection. Explicit confirmed/unconfirmed planned exit and immutable request fingerprint make retries safe. |
| Historical invoices could be restated | Recalculation allowed finalized totals to be repriced; legacy invoices sometimes lacked saved admission balances | Closed admission totals are frozen, including legacy stored stay totals. Existing receipts and finalized stay records are not backfilled. New pricing snapshots protect later calculations from setting changes. |

The backend original-duration and extension-request protections were already in
starting HEAD and were retained. The Flutter effective-expiry calculation still
added extension days to an already extended expected date; that regression is corrected here.

## Files changed

[files-changed.csv](files-changed.csv) is the complete path inventory, including
separate classifications for preserved user changes and evidence artifacts.
Implementation is limited to billing/lifecycle callers, their tests and one
offline serialization compatibility correction:

- Backend: `src/services/billing.ts`, new `src/services/discharge.ts`,
  `src/routes/patients.ts`, `src/routes/settlement.ts`, `src/routes/stays.ts`,
  and `src/validation.ts` (all under `backend/`).
- Backend tests: new `client_billing_rules.test.ts`, `billing_pricing.test.ts`,
  `settlement.integration.test.ts`, `workflows.integration.test.ts`,
  `refund_fix.test.ts` and `scalability.integration.test.ts`.
  The scalability test now writes its evidence in this task's audit directory
  rather than overwriting an older audit's artifacts.
- Flutter utilities/models: `lib/utils/pricing_helper.dart`,
  `lib/utils/stay_billing.dart`, `lib/models/patient_model.dart`,
  `lib/models/stay_model.dart`.
- Flutter services: `backend_api_service.dart`, `patient_service.dart`,
  `payment_service.dart`, `room_service_pricing.dart`, `room_service_stays.dart`
  under `lib/services/`.
- Flutter screens: attendance editor/service; patient list/profile;
  Add/Edit/Details/Shift patient dialogs and stay-history card; financial dialog;
  Create Stay and pricing settings dialogs. Exact paths are in the CSV.
- Flutter tests: new `test/client_billing_rules_test.dart`, admission pricing,
  attendance/payment, calendar alignment/settlement, domain PostgreSQL service,
  planned-exit attendance, real PostgreSQL E2E, stay billing and offline planner
  regression fixtures.
- `tool/global_billing_restatement.dart`: filter live Pending/checkout metadata
  out of its existing financial-only write allowlist. The allowlist was not
  broadened, and the tool was not executed against any real dataset. Tests use
  in-memory synthetic maps.
- This audit directory and `.gravitas/sessions/client-billing-20261022/`:
  implementation contract, validation records, historical analysis and logs.

## Schema and API compatibility

**No migration or backfill is required.** Existing `patients.discharge_date`
and `stays.completed_at` hold actual checkout; `patients.exit_date` stays planned.
Existing JSONB admission balances and billing summaries hold pricing snapshots,
Pending/provisional metadata, tentative/final `checkoutAt`, and one itemized
`checkoutAdjustment` with its owner stay, category, applicable billable day and amount.
The existing `patient_attendants.id` supports identity-based payloads without deleting legacy attendance.

`POST /patients/:id/discharge` accepts `checkoutAt` in epoch milliseconds.
An omitted timestamp uses the server's actual current time. It no longer means
"use the planned date". An already discharged admission returns its frozen snapshot.
`GET /patients/:id/financials?checkoutAt=...` previews an actual checkout.
`POST /patients/:id/recalculate-billing` can save that draft for settlement.

`POST /patients/:id/rejoin` requires a stable `requestId`, new `admissionDate`,
`exitDate` plus `exitDateUnconfirmed`, and a valid room/bed or Lobby placement.
Unknown exit remains null, with a provisional ongoing estimate. Confirmed exit
must not precede admission. Previous identity, registration, stays, attendance,
receipts and admission balances are retained. Reusing a request ID differently
returns a conflict; failed placement rolls back the entire new cycle.

Legacy clients completing the last stay must now satisfy the same attendance
and settlement checks as the authoritative discharge endpoint. A missing current
stay needs placement reconciliation before discharge. Legacy RTDB workflows remain
separate writes; no RTDB atomicity is claimed.

## Validation

All commands below completed after their relevant final implementation changes.
Commands run from the repository root unless the working directory says `backend`.

| Command / check | Passed | Failed | Skipped | Evidence |
|---|---:|---:|---:|---|
| `npm run test:postgres` (`backend`) | 344 | 0 | 0 | [backend-tests.txt](backend-tests.txt) |
| Focused `npm test -- --reporter=dot tests/client_billing_rules.test.ts` (`backend`) | 31 | 0 | 0 | [backend-client-rules.txt](backend-client-rules.txt) |
| Affected Flutter suite, 13 files | 163 | 0 | 0 | [flutter-affected.txt](flutter-affected.txt) |
| `flutter test --no-pub test/global_billing_restatement_test.dart test/calendar_day_settlement_test.dart --reporter expanded` | 22 | 0 | 0 | [flutter-compatibility.txt](flutter-compatibility.txt) |
| `flutter test --no-pub test/postgres_real_workflows_e2e_test.dart --reporter expanded` | 23 | 0 | 0 | [postgres-e2e.txt](postgres-e2e.txt) |
| `flutter test --no-pub --reporter expanded` | 477 | 0 | 0 | [flutter-tests.txt](flutter-tests.txt) |
| `npm run build` (`backend`) | exit 0 | 0 | 0 | [typescript-build.txt](typescript-build.txt) |
| `flutter analyze --no-pub` | exit 0; no issues | 0 | 0 | [flutter-analyze.txt](flutter-analyze.txt) |
| `git diff --check` | exit 0 | 0 | 0 | [diff-check.txt](diff-check.txt) |
| `flutter build windows --release` | exit 0 | 0 | 0 | [windows-build.txt](windows-build.txt) |

The backend matrix executed every opt-in PostgreSQL suite in owned temporary
PostgreSQL 16 clusters at loopback port 55439. It rejects existing services and
stops/removes only its own cluster. Breakdown:

| Backend suite | Passed | Failed | Skipped |
|---|---:|---:|---:|
| Ordinary tests (including billing, validation and security) | 161 | 0 | 0 |
| Workflows | 42 | 0 | 0 |
| Modules | 41 | 0 | 0 |
| Importer | 22 | 0 | 0 |
| Payment financial accuracy | 36 | 0 | 0 |
| Scalability | 4 | 0 | 0 |
| Settlement / checkout / transfer / rejoin | 33 | 0 | 0 |
| PostgreSQL authentication | 3 | 0 | 0 |
| Migrations | 1 | 0 | 0 |
| Outage / restart persistence | 1 | 0 | 0 |

Windows Release output: `build/windows/x64/runner/Release/ngo.exe`.
The Windows compilation stage completed in 78.3 seconds. No installer was rebuilt.

Evidence files are stored in this directory. Focused suite counts overlap full
suite counts and must not be added to them as unique tests. Expected negative
test 401/403/409/503 responses and synthetic outage logs do not mean those tests failed.

Earlier runs failed while identifying obsolete fixture assumptions and the
offline summary serialization mismatch. Their fixes were verified by the final
runs above; failures were not reclassified as passes. Initial E2E and full Flutter
outputs are retained as `postgres-e2e-initial.txt` and `flutter-tests-initial.txt`.

## Read-only historical audit and limitations

See [historical findings](HISTORICAL-FINDINGS.md) and
[aggregate audit query](historical-billing-exposure.sql).
Code-history evidence confirms the duration, payload, checkout and stale-summary
risks. The aggregate query is validated against the actual disposable schema.
No approved anonymized production snapshot was supplied or read. Real affected
record counts and deployment dates remain unknown; no invoices were repaired.

Past configurable rates that were never saved in an active admission's legacy
segments cannot be reconstructed reliably from current settings. Existing stored
pricing snapshots/manual overrides are retained, and finalized stored totals are
frozen; no retrospective rate history is invented. Ambiguous name-only attendant
history is preserved and requires explicit identity review rather than guessing.

Private's historical generic physical checkout helper is not evidence for a new
separate surcharge on top of inclusive PostgreSQL billing. The implementation
therefore preserves Private's inclusive category tariff and introduces no such
surcharge. General/Lobby's confirmed adjustment is separate and tier-aware.

Legacy RTDB continues to use its historical physical checkout/date policy and
separate lifecycle writes. The PostgreSQL path is authoritative for atomic
checkout settlement, projection persistence and rejoin. No RTDB atomicity or
automatic migration to the PostgreSQL calendar policy is claimed.

VERDICT: PASS — implementation and required local validation; production historical exposure unverified.
