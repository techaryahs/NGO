# Flutter integration audit — 16 October 2026

## Finding

The Flutter application is **not ready for PostgreSQL cutover**. Before this audit, `USE_POSTGRES_BACKEND` was defined but never used to select a transport. `ServiceLocator` constructed an unused `BackendApiService`; patient, room, payment, settings, registration, ERP, photo and profile services still received `FirebaseRTDBRestService`. Merely setting the flag could therefore appear to enable migration while continuing to write Firebase.

Initialization now rejects an explicitly enabled PostgreSQL flag with an actionable `StateError`. Disabled mode retains the existing Firebase service graph. No environment file or live flag was changed. Implementing the full adapter would require replacing RTDB queries, ETags and atomic root updates across multiple domains; that work has deliberately not been disguised as a small HTTP client fix.

## Method and evidence boundaries

- Inspected the initial Git status and diff before edits. Existing changes were preserved.
- Inspected AppConfig, BackendApiService, ServiceLocator, Firebase REST/auth, domain services and models, Drift schema, PersistentCache, attendance paths, existing tests, and backend route implementations.
- Used headless `flutter test`, HTTP `MockClient`, synthetic identities, and isolated `NativeDatabase.memory()` SQLite databases. Existing Flutter widget tests run through the automated test harness; the Windows application was never opened.
- No Computer Use, GUI automation, screenshots, screen recording, live Firebase requests, or production database requests were used.
- These tests establish client behavior and real SQLite behavior. They do **not** establish a live Flutter-to-Fastify-to-PostgreSQL workflow or Windows application runtime behavior. See the consolidated backend audit for actual PostgreSQL and API/database execution evidence.

## Corrections

| Confirmed issue | Root cause | Correction and regression coverage |
| --- | --- | --- |
| Flag silently left all domain writes on Firebase | No transport selection consumed `usePostgresBackend` | Fail closed before service creation when enabled; test disabled Firebase registration and disposal. Backend-ready indicator no longer claims readiness in disabled mode. |
| Blank API URL produced invalid requests | Getter default applied only to missing values | Blank/missing URL uses documented localhost default; configured URL remains intact. |
| 400/401/403/409 masked by cached data | GET caught every failure and returned cache | Only connection errors, timeouts and HTTP 5xx permit cache fallback; malformed JSON and non-404 4xx propagate. Four status-specific regressions. |
| Failed/missing auth token led to anonymous requests/cache fallback | Header builder swallowed token-provider errors | Propagate provider failure; configured provider returning no token produces HTTP 401 exception before HTTP. Tests also check Bearer injection. |
| Error responses could expose server details | Exception/log included complete response body | Typed `BackendApiException` preserves HTTP status while omitting body; sensitive-marker regression. |
| Stale deleted/null values remained cached | 404 returned early, null body skipped cache update; DELETE 404 skipped eviction | Reconcile acknowledged 404/null reads and idempotent DELETE 404 with SQLite. |
| Writes cached submitted fields instead of server result | PUT/PATCH applied request maps | Cache authoritative returned representation. Empty success invalidates record; failed writes leave cache intact. |
| Creation could invent an ID | Fallback returned request ID or literal `generated_id` | Require nonempty server ID; cache authoritative created record. Retrying after simulated lost response retains caller's submitted ID. This does not itself establish server idempotency. |
| Responses crossed account partitions | Cache partition selected only after HTTP completed | Capture account generation before token/HTTP work, reject stale reads, prevent old-account writes populating the next account. |
| Older read replaced newer acknowledged write | No request/mutation generation check | Cache reconciliation uses mutation generation and existing transactional snapshot guard. |
| Delayed cache stream emission followed fresh server data | Hydration and polling raced without ordering | Suppress late hydration after a newer poll response. |
| Polls overlapped or survived disposal | Async polls had no pending/disposed guard | One poll at a time, cancel/close on last listener, prevent pending async polls starting HTTP after dispose; make dispose idempotent. |
| Attendance path treated `daily` as date | Mapper assumed `attendance/date/patient`, actual callers use `attendance/daily/date/patient` | Correct query date/patient extraction, root `daily` envelope and targeted patient/attendant response projection. Four regressions were observed failing before correction. |
| Targeted attendance cache returned entire day's data | `_readAttendance` always returned date map | Traverse patient/attendant suffix for targeted reads while preserving other patients. Date-level behavior unchanged. |

Two redundant null comparisons in the existing cache freshness guard were removed; `_asInt` already returns non-null `int`. Its comparison behavior is unchanged.

Files changed by this subtask: `lib/config/app_config.dart`, `lib/services/backend_api_service.dart`, `lib/services/service_locator.dart`, `lib/cache/persistent_cache.dart`, `test/backend_api_regression_test.dart`, `test/backend_config_test.dart`, and this report. The service, config and locator files already contained migration work before the audit; the changes above build on those files.

## Flutter/API contract coverage matrix

All rows remain blocked from PostgreSQL use by the explicit initialization guard. “Mocked” means endpoint/path/HTTP/client/cache contracts were executed against mocked responses, not against Fastify or PostgreSQL.

| Module | Client/API behavior inspected or mocked | Remaining integration gap |
| --- | --- | --- |
| Patients | Mocked GET collection `format=map`, GET entity, POST ID handling, PUT partial update, failures, cache and account races | PatientService creates via RTDB entity PUT and uses root atomic patches; API creates via POST. Generic helper silently collapses deeper patient field paths to entity URL. No production adapter/pagination integration. |
| Rooms/beds | Mocked GET collection/entity; inspected room model accepts array/map beds | Room creation, bed CAS and reservation services require RTDB queries/ETags/root patches. Generic bed GET maps to a server write-only path and can misinterpret 404 as absent. Versioned backend methods need explicit adaptation. |
| Stays/admission/discharge | Mocked stay GET collection/entity; inspected snapshots, extensions, billing fields and lifecycle service | Current admission/completion operations use multiple RTDB requests/root patches. No adapter to server-authoritative atomic lifecycle operations. |
| Attendance | Mocked patient and attendant date reads, root date envelope, individual patient projection; actual SQLite date/patient assertions | Client bulk writes are flattened RTDB root PATCH, whereas API uses POST `/attendance` or `/attendance/bulk`. Bounded query helpers are absent from BackendApiService. Aggregate/root attendance cache hydration is not implemented. |
| Payments/refunds | Mocked payment/history read mapping, caller retry with stable submitted ID, actual SQLite acknowledgement checks; inspected PaymentModel and PaymentService | PaymentService uses RTDB atomic multi-path financial writes. Legacy PaymentBackendClient instead targets `recordManualPayment`, `recalculateBilling`, `amendManualPayment` with token in body; those are a different trusted-payment backend contract, not this Fastify API. No working adapter to new payment POST/refund semantics. |
| Profiles/users/roles | Inspected AuthService/Firebase auth and profile registration | Auth profile operations still target RTDB users. A generic `/users/...` URL mapping does not establish backend support. Server roles must remain authoritative. |
| Settings | Mocked `/settings/:category` and `/settings/:category/:key` reads for admin_settings | SettingsService also uses RTDB root settings and category patches. Root settings, nested fields and key/category write semantics still need complete adaptation. Backend added category PUT merge separately during this audit. |
| Registration counters | Mocked counter GET URL; inspected currentValue unwrap and Firebase allocator | Allocator uses Firebase ETag CAS/bootstrap/stream; no adapter for server POST `/counters/:name/next`, persistent retry identity or counter reset authorization. |
| Patient/attendant photos | Mocked `/photos/...` GET mapping; inspected existing dedicated-photo tests and metadata-only cache | PhotoRtdbService still depends on RTDB writes/readback/delete. API photo shape/storage lifecycle must be adapted explicitly; generic successful PUT response can contain metadata without image data. |
| Inventory | Inspected API and InventoryExpenseService | Flutter expects RTDB map/camelCase at `inventory_items`; backend uses `/erp/inventory` and SQL row arrays/snake_case. Missing transport and model conversion, plus full CRUD parity. |
| Vendors | Inspected model and service | Flutter uses mobileNumber/gstNumber/notes/audit fields; backend SQL uses phone/category and a smaller schema. Transport, field preservation and CRUD parity unresolved. |
| Purchases | Inspected model and service | Flutter expects nested paymentDetails, audit timestamps and map collection; backend raw SQL array contract differs. Transport/model preservation unresolved. |
| Expenses | Inspected model and service | Flutter uses totalAmount, nested paymentDetails, subcategory/vendor/item/quantity fields; backend uses amount/payment_method and narrower representation. No production adapter. |
| Salaries | Inspected model/service and API | Flutter write/update/delete semantics are not implemented by backend salary GET-only operation; no adapter. |
| Sponsorships | Inspected service/model and API | Flutter expects map/camelCase and full update/delete; backend ERP transport/response shape and operation coverage differ. |

## Unresolved integrity and security findings

1. **Existing Firebase discharge can still report success while a bed remains occupied.** `PatientService.dischargePatient` marks the patient discharged first and catches all stay lookup/completion failures. `RoomService.completeStay` separately performs bed CAS and stay update. A network/CAS failure can leave these records inconsistent. This is a source-inspection finding; this audit did not alter those legacy business rules or claim to have proved live Firebase discharge atomicity. Backend lifecycle tests and fixes cannot repair this Flutter path while it still uses Firebase. Cutover requires the domain adapter to use the atomic backend operation.
2. Backend patient collection defaults to a bounded page; BackendApiService only requests the first collection response, while PersistentCache can mark a patients snapshot canonical/complete. A future adapter must exhaust pagination before replacing the complete collection or merge individual pages without deleting older cached patients.
3. Existing domain financial calculations use Dart `double`; no claim of end-to-end decimal arithmetic follows from SQLite/client tests. The database/API financial tests must establish server precision; client display/serialization policies still need final contract review.
4. Legacy FirebaseAuthRestService persists ID/refresh tokens in SharedPreferences. Existing signup diagnostics print email/UID. These were inspected and not changed or supplied with real identities during this audit. OS-protected token storage and diagnostic minimization remain hardening work.
5. The generic backend helper is a partial compatibility helper. Its API surface does not implement Firebase query streams, atomic root PATCH, conditional ETags, registration allocation, complete ERP mappings, or complete photo lifecycle. The fail-closed flag is essential until those contracts are implemented and tested.

## Execution record

Commands ran from `C:\Users\sahil\OneDrive\Desktop\NGO`; existing dependencies only, no new testing framework installed.

| Actual command | Observed result | Evidence type |
| --- | --- | --- |
| `flutter test --no-pub --reporter expanded` before audit edits | 258 tests completed successfully | Existing headless Flutter unit/widget/service/cache suite |
| `flutter test --no-pub --reporter expanded test/backend_api_regression_test.dart` before initial client fixes | 4 successful, 18 failed | Demonstrated client/cache/auth/race defects |
| Same initial 22-regression command after fixes | 22 completed successfully | Mocked HTTP plus isolated real SQLite |
| `flutter test --no-pub --reporter expanded test/backend_api_service_test.dart test/backend_api_regression_test.dart test/backend_config_test.dart` | Intermediate test authoring compile error (`testLoad` removed in installed dotenv 6); corrected to local dependency's `loadFromString`. Subsequent run: 32 completed successfully | Transparent test-development failure and correction |
| `flutter test --no-pub --reporter expanded` before attendance/disposal additions | 300 completed successfully | Existing suite plus first 42 added tests |
| `flutter test --no-pub --reporter expanded test/backend_api_regression_test.dart --name attendance` before attendance fixes | 4 failed | Actual path/query/envelope regression evidence |
| `flutter test --no-pub --reporter expanded test/backend_api_regression_test.dart test/backend_config_test.dart test/persistent_cache_test.dart test/attendance_payment_implementation_test.dart` after attendance fixes | 83 completed successfully | Mocked API paths plus actual SQLite and existing attendance regression suite |
| `flutter test --no-pub --reporter expanded` with new disposal case before disposal fix | 304 successful, 1 failed | Pending poll issued HTTP after dispose |
| `flutter test --no-pub --reporter expanded test/backend_api_regression_test.dart --name dispose` after guard | 1 completed successfully | Disposal regression |
| Final `flutter test --no-pub --reporter expanded` | **305 completed successfully, 0 failures; exit 0; 40 seconds reported by runner** | Full regression: 258 original tests + 47 new tests (43 client/cache cases and 4 config/locator cases) |
| `dart analyze lib/config/app_config.dart lib/services/backend_api_service.dart lib/services/service_locator.dart lib/cache/persistent_cache.dart test/backend_api_regression_test.dart test/backend_config_test.dart` | **No issues found; exit 0** | Changed Dart static analysis |
| `flutter analyze --no-pub` | **Executed; exit 1: 0 errors, 56 warnings, 255 informational findings, total 311; 26.6 seconds. No diagnostics in the six edited/new Dart files.** | Full-project static analysis remains non-clean because of issues elsewhere; do not describe this check as passed |

Final verification above ran after the last Dart/test code change. Temporary command output is kept in the operating-system temp directory (`ngo-flutter-baseline.log`, `ngo-flutter-regression-before.log`, `ngo-flutter-attendance-before.log`, `ngo-flutter-final.log`, `ngo-dart-analyze-final.log`, `ngo-flutter-analyze-final.log`). These are test-only outputs; no patient/export records were copied to fixtures or committed logs.

VERDICT: FAIL -- PostgreSQL cutover is blocked by the missing Flutter domain adapters and endpoint/model parity. The corrected client/cache regressions and full headless test suite completed successfully; this does not establish a working migrated application.
