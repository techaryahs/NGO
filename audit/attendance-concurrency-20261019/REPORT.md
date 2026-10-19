# NGO attendance initialization and concurrency audit

19 October 2026. Local implementation and automated verification are complete. Manual Windows UI retesting is pending.

## Boundaries and local state

No VPS deployment, production import, Firebase Authentication change, Docker volume reset, or historical financial recalculation was performed. Existing unrelated working-tree edits were preserved.

Tests used a separate PostgreSQL **16.12** cluster at **127.0.0.1:55439**, data directory `%TEMP%\ngo-audit-pg16-attendance-20261019`. Its dedicated databases were `ngo_audit_workflows`, `ngo_flutter_e2e`, `ngo_audit_payment_accuracy`, and `ngo_audit_migrations`. Database identity guards run before test migrations/resets. The temporary cluster was stopped after verification; its data directory remains available for reruns.

The normal local backend container was rebuilt and replaced. The existing Docker PostgreSQL **16.15** container/volume was retained. Additive migration `008_registration_identity` adds a registration fingerprint column; it performs no attendance or financial reconciliation. The backend is healthy and `/ready` reports the database connected.

Before/after counts **and full-row hashes** match for all three checked tables: attendance **13**, payments **1**, stays **1**. Evidence: `local-before.txt`, `local-after.txt`, `local-inventory.sql`, `local-ready.json`, `docker-build-final.log`, `docker-update-final.log`.

## Phase 1: Attendance initialization

### Original behavior

`PatientService.addPatient` called `initialAdmissionAttendance`, which expanded `PricingHelper.attendancePeriod` into inclusive date keys. October 19-31 therefore generated **13 Present patient records**, plus equivalent attendant records, tagged `automatic_registration_period`. The atomic registration payload sent these in `initialAttendance`; Fastify inserted them with the patient, attendants, stays, and bed allocation. The alternate Flutter path created the patient and then sent separate attendance bulk writes.

Additional producers were the RTDB date-edit branch of `updatePatient` and `getDischargeReadiness` calling `syncAutomaticPatientAttendance` (including PostgreSQL). Merely checking discharge readiness could manufacture marks. No additional automatic generator was found in Fastify stays/extensions, the monthly grid, or the profile calendar.

Attendance is stored by kind, date, and patient ID with database uniqueness. The monthly screen reads `AttendanceService.loadMonth`; its editor defaults missing keys to Unmarked. The profile reads the same API daily map. SQLite caches successful snapshots/acknowledged writes. PaymentService uses stored marks for confirmed attendance summaries and billing inputs. Generated rows were consequently indistinguishable from real saved presence to these readers.

### Changed paths

| Path | Change |
|---|---|
| `lib/services/patient_service.dart` | Registration always uses the atomic PostgreSQL endpoint and sends no attendance. Removed date-edit and discharge-readiness automatic sync calls. Legacy initial/sync/clear helper entry points are harmless no-ops: they neither create nor delete marks. |
| `backend/src/routes/patients.ts` | Removed registration attendance insertion. Legacy `initialAttendance` payloads are accepted for compatibility and ignored. Patient/attendants/stays/bed allocation remain transactional. |
| `lib/utils/pricing_helper.dart` | Documents that inclusive date ranges represent eligibility and estimates, never actual presence. |
| `lib/screens/attendance/attendance_service.dart` | Shared patient-ID projection and summary count only stored Present/Absent. Missing monthly cells retain Unmarked behavior. |
| `lib/screens/patients/patient_profile_screen.dart` | Uses that projection and authoritative date keys. Summary skips Unmarked/unknown values instead of counting them Absent. |
| `lib/services/room_service_stays.dart`, `backend/src/routes/stays.ts` | Extensions create no attendance; concurrent extensions are now atomic. |
| `lib/services/payment_service.dart` | Actual counts remain based on stored marks; patient/stay billing restatement is now one version-checked transaction. |
| `lib/services/backend_api_service.dart` | No generated registration attendance; stale range/read handling corrected. |
| Tests and migrations | Updated obsolete auto-Present expectations; added regressions. No attendance cleanup migration was introduced. |

Registration, admission, planned exit, and extension dates remain **Unmarked until attendance is explicitly saved**. Retrying registration never overwrites manual marks. No new status system was added.

**Billing distinction:** the established planned/physical-stay estimate remains separate from actual attendance. Unmarked stays may retain an advance estimate, but this does not create confirmed presence or increase Present totals. Attendance-only `StayBilling.calculate(onlyPresent: true)` yields zero days for the unmarked planned stay and one billable day after saving one Present and one Absent. Existing estimate/checkout rules and historical payments were preserved. Old tagged rows remain stored and countable until explicitly reconciled; they were not silently hidden or reclassified.

### Mandatory regression results

`test/postgres_real_workflows_e2e_test.dart` includes **October 19 planned registration stays Unmarked through retries, extension and disk cache reopen**. It uses real HTTP Fastify routes, PostgreSQL, production Flutter services and file-backed SQLite.

| Required scenario | Observed result |
|---|---|
| Register October 19, exit October 31, with attendant/stay/bed | Patient and related records saved; attendance table empty. |
| Monthly and profile data before marking | All 13 monthly cells resolve to Unmarked; profile projection empty; confirmed total 0. |
| October 19 Present, October 20 Absent | Exactly those two patient/date rows; summary 1 Present, 1 Absent, total 2, 50%. |
| Same name, different patient ID | Second patient inherits no attendance. |
| Retry registration | No generated or overwritten attendance. |
| Extend into November | Newly added dates remain Unmarked. |
| Close/reopen services and actual SQLite file | Saved marks persist on disk; future marks remain absent after fresh API reads. |
| Attendance-only billing | Zero days before marks; one Present day afterward. |

A backend regression submitted the legacy 13-day automatic payload: before the fix it failed with 13 inserted rows; afterward it passes with none. Phase 1 finished with **33/33 PostgreSQL workflow tests** and **98/98 targeted Flutter tests**, before Phase 2 began.

**UI limitation:** these tests verify actual database/service behavior, shared profile projection, and monthly cell data. Existing widget tests exercise grid editing. They do not establish that the actual Windows profile/calendar workflow was clicked successfully. Native desktop interaction is disabled in this session. Manual desktop testing remains required.

### Existing records and reconciliation

Read-only inspection identified exactly **13** tagged patient records for local synthetic patient `p_1792387833687528_306da8e79f748ffbc7e4006d`, name `test`, October 19-31. No manual attendance rows were present at inspection. Those records, its payment, and its stay were preserved. This existing patient will continue showing the saved 13 marks until a specifically approved reconciliation occurs.

`reconcile-synthetic-review.sql` is a review-only transaction ending in **ROLLBACK**. It targets only that exact patient, date window, kind, automatic source and Present status; it returns candidate rows for review and never recalculates balances. It was written, **not executed**. Export/review the rows before approving a commit. Alternatively, retest with a fresh synthetic patient ID without changing the old patient's history.

For potentially real history: inventory the exact source tag (including individual nested attendant objects), corroborate patient/cycle/date/registration evidence, export originals, preserve manual/untagged/uncertain records, and obtain explicit approval for targeted changes. Do not infer automatic generation from dates alone. Re-read API ranges/reopen the corrected app to reconcile SQLite afterward. Any historic financial restatement requires a separate review.

## Phase 2: Confirmed concurrency and reliability defects

Each defect below has a failing reproducer observed before correction or an existing real integration regression that failed in this session.

| Defect / reproduction | Root cause | Fix | Verification |
|---|---|---|---|
| Reuse registration ID with different patient identity: old endpoint returned 200 | `/patients/register` compared stays but not original identity | Persist original identity fingerprint and reject mismatched reuse; preserve canonical retries | `registration retry cannot associate a different patient identity...`: corrected 409, PASS |
| Delete paused after patient lock while admission locks room then waits for patient: old responses `[200,500]` | Inconsistent lock ordering across admission, deletion, stay lifecycle | Patient, sorted rooms, then stays/beds; sorted batch locks | Real transactions and `pg_stat_activity` lock observation: corrected `[200,409]`, no orphan stays/beds, PASS |
| Save attendance or change stay, then submit old financial snapshot: old PUT accepted | These writes did not invalidate billing's patient version | Lock affected patients and bump versions in the same transaction | Attendance/stay stale billing tests reject 409; failed bulk write rolls back marks and version, PASS |
| Two extensions read the same state: 2-day stay plus 2 and 3 days became 5 instead of 7 | Flutter wrote absolute totals; patient metadata was a separate request | Increment operation with retry ID; update stay and patient metadata transactionally | Real Flutter/PG before 5, after 7; retry, conflicting reuse and injected rollback tests, PASS |
| Inject failure in stay billing UPDATE: patient totals remained changed | `_applyBillingUpdatesToPostgres` wrote patient and stays in separate requests | Version-checked `stayBillingUpdates` in one patient transaction; patient ownership validation | Real trigger failure now rolls back entire calculation; successful retry and cross-patient rejection, PASS |
| Release older attendance range after newer range; release old patient GET after deletion | Guards prevented some cache writes but not stale returned values; read ordering absent | Sequence checks for overlapping ranges/equivalent reads, fresh retries and acknowledged deletion handling | Controlled completers: corrected fresh range/absent patient for caller and cache, PASS |
| Dispose scheduler while a pass awaits an earlier pass: old implementation started a second pass | Waiting callback was no longer in the cancellable timer map | Scheduler generation checked after waiting | `disposing a scheduler cancels a pass already waiting...`: old 2 calls, corrected 1, PASS |
| Concurrent identical refund retries returned different patient-name metadata | New response enriched patient name; reuse response omitted it | Canonical enrichment on both paths | Existing financial response-equality regression; one ledger row, PASS |
| Destination becomes occupied during room shift: original patient became discharged | Dialog closed source stays before acquiring destination | Atomic `/patients/:id/transfer`, expected source IDs, ordered locks, rollback and fingerprinted retries; PostgreSQL dialog uses it | Real Flutter conflict preserves full original placement; success/retry and concurrent transfer/discharge invariant test, PASS |

Other audited workflows:

- Registration lock/unique registration numbers, identical and conflicting retries, second-bed failure rollback, multi-bed/lobby admission and counter concurrency tests pass. Counter preview gaps were not treated as duplicate-patient corruption.
- Active-bed uniqueness and row locks prevent double placement. Room occupancy, another patient's bed, repeated completion and stale direct assignment requests are tested.
- Stay completion updates patient/bed/room in its transaction. Generic patient updates cannot detach active stays. The actual sequential transfer defect is corrected above.
- Attendance preserves patient/date identity and existing last committed write behavior for the same cell. Concurrent bulk edits preserve independent patient/attendant keys; sorted locks avoid opposite-order batches. No global lock was added.
- Payment/refund tests cover duplicate receipts, concurrent distinct decimal payments, combined over-refund rejection, edits/deletions, stale snapshots, failure rollback and historical admission credit isolation. No further lost-balance defect was demonstrated beyond the billing/version defects above.
- Patient deletion remains admin-only and transactional. Account switch/logout, disposal, failed-write cache integrity, canonical pagination/partial snapshots, shared streams and unrelated acknowledgements are covered. Unsupported theoretical risks were not reported as confirmed defects.

No Redis, broker, global serialization, new attendance statuses, or authorization relaxation was introduced.

## Final verification

| Check | Actual result | Evidence |
|---|---|---|
| Full Flutter suite | **418 passed, 0 failed**, including 17 real HTTP/PostgreSQL service workflow tests | `flutter-full-final.log` |
| Backend unit invocation | **90 passed, 0 failed**, 147 opt-in integration cases skipped | `backend-unit-results.json`, `backend-unit-counts.log`; Gravitas-owned validator PASS in session evidence ledger |
| PostgreSQL API/concurrency workflows | **41 passed, 0 failed** | `backend-workflows-final.log` |
| PostgreSQL financial integration | **35 passed, 0 failed** | `payments-postgres-final.log` |
| PostgreSQL migration upgrade/rollback/reapply | **1 passed, 0 failed** | `migrations-postgres-final.log` |
| Backend TypeScript build | PASS | `backend-build-final.log`; local Docker build also compiles TypeScript |
| Windows debug build | PASS | `windows-build-final.log` |
| Focused Dart analysis | No errors; adding transfer dialog reports its 4 unchanged Radio API deprecation infos | `dart-scoped-final.log` |
| Repository-wide Dart analysis | **0 errors, 53 warnings, 228 infos (281 findings)**; not clean | `dart-full-final.log` |
| Local backend | Healthy, database connected; migration 008 applied | Docker logs and `local-ready.json` |
| Existing local history | Attendance/payment/stay counts and complete-row hashes unchanged | `local-before.txt`, `local-after.txt` |
| Native Windows UI interaction | **Not exercised; manual retest pending** | No desktop UI pass claimed |

The initial broad Flutter run exposed a read-scope retry problem and an outdated pagination mock; the corrected final full suite passes. Filtered requests remain independent. Unit mocks were updated for transactional attendance and ordered room locks. A stale test expecting admin deletion to be blocked was aligned with the existing authorized cascade-deletion implementation; application deletion authorization/policy was not weakened.

## Manual desktop retest

1. Close the previously running app. Launch `build/windows/x64/runner/Debug/ngo.exe` from its build directory with the accompanying updated Dart assets. The installer was not rebuilt.
2. Register a fresh synthetic patient for October 19-31. Before marking, check both monthly and profile calendars: Unmarked, zero confirmed attendance.
3. Save October 19 Present and October 20 Absent, reload, extend into November, and register the same name under a different ID. Confirm 1/1/2/50%, future Unmarked, and identity isolation.
4. Review the targeted SQL proposal separately if the old synthetic patient's stored 13 marks should be removed. Its payment/history remains preserved.

Stop here pending manual desktop retesting. No VPS deployment or production import was performed.

VERDICT: PASS
