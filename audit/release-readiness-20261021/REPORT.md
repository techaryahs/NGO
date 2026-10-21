# NGO release readiness — 21 October 2026

## 1. Verdict and executive summary

**RELEASE BLOCKED — engineering checks pass; the historical-record audit still needs an approved snapshot or explicit approval to defer that risk.**

The Windows release candidate bundle builds successfully. Final verification is **293 backend tests passed, 0 failed, 0 skipped; 443 Flutter tests passed, 0 failed, 0 skipped; analyzer 0 findings; TypeScript build passed; diff check passed; Windows release build passed**. Focused runs are subsets of these totals, not additional unique tests.

All 160 formerly skipped PostgreSQL tests executed. Three additional database regression cases bring the final integration total to 163. The ordinary backend tests total 130.

The business-rule discrepancy is resolved according to your explicit selection: **approval quotes use projected billable attendance days**. Flutter obtains the server quote; extension approval recalculates it under the patient lock, stores its basis and amount, extends planned dates, and persists the current invoice in the same transaction. Finalized historical balances and receipt records are not backfilled.

No production snapshot was supplied or accessed. The number of real historical records affected by the old duration bug is **unknown**, not zero. A SELECT-only aggregate audit procedure is provided and its query was validated against the actual disposable schema.

## 2. Original blockers and root causes

| Blocker | Root cause | Correction |
|---|---|---|
| 160 skipped backend tests | PostgreSQL suites intentionally require separate opt-in flags, exact database names, loopback port 55439, and PostgreSQL 16. The normal command did not provision those dependencies. | Added `npm run test:postgres`: create a unique temporary cluster, generate test credentials, verify its directory/version, create exact test databases, execute every suite, stop and delete only that cluster. Occupied-port reuse is rejected before database creation. |
| Flutter PostgreSQL E2E unavailable | Test expected an already initialized, machine-specific temporary cluster and hardcoded binary path; it did not run initdb or create its database. Captured Windows pg_ctl pipes also caused a startup hang. | Discover binaries from explicit overrides/PATH/standard installation directories; create an owned temporary cluster; initialize and create the database; verify server directory/version; bounded pg_ctl startup; inherit lifecycle stdio; run the API directly through Node and clean up owned processes/directories. |
| Analyzer exit 1 / 281 findings | 53 warnings and 228 infos: deprecated APIs, unused/dead code and imports, nullable fallbacks on nonnullable fields, async context lifetime checks, and lint violations. | Focused code/API corrections plus mechanical fixes and formatting. No lint rules disabled and no repository areas excluded. |
| Integration failures exposed after enabling tests | Payment edits could acquire another receipt's reference; invalid bed assignments were silently skipped; rollback tried to drop an index already removed by migration 009; some assertions predated newer intentional behavior. | Narrow API conflict guard, strict importer assignment failure accounting, tolerant index rollback, and evidence-backed test corrections. |
| Extension quote/final invoice discrepancy | Quote used recorded duration and attendant count; final invoice used billable attendance days and per-day attendant marks. | Reuse the final invoice engine for the marginal before/after projection. The dialog fails closed on quote failure and rejects stale quote responses. |

Migration **009_widen_payment_ids.sql** explicitly permits imported split receipts and placeholder `MANUAL_ONLINE` references. A preliminary importer restriction was removed during review because it contradicted that intentional compatibility rule. Final tests verify both import preservation and editing existing shared-reference receipts.

## 3. Historical evidence and reconstructed pricing

| Evidence | Date (Asia/Kolkata) | Relevance |
|---|---|---|
| `918225c09c80b1666ce9c6456dbc64f0f5190921` | 2026-09-08 10:07:20 | Historical StayBilling counted billable days and applied long-stay surcharges; StayModel combined original duration and extension days. |
| `dd96d8284e01913258f92e28e6c1157509ca4b7c` | 2026-09-30 18:15:02 | Deleted legacy billing implementation/tests retain evidence for the 60 × ₹200 + ₹250 boundary behavior. |
| `59fa330c7a1fb3d38c890a39645e8aee213231a5` | 2026-10-05 15:10:48 | Calendar billing/planned-exit tests document the newer PostgreSQL date policy. |
| `e012e95552068c4caf55a801c78f29ebc5f34a86` | 2026-10-19 16:08:48 | Backend extension incremented both duration fields; migration 009 deliberately retained legitimate shared bank references. |
| `129cfe74ae5a5f551c89d71fef0e4efe2f0bf3f8` | 2026-10-21 13:18:46 | Current HEAD/security baseline; authentication, authorization, token-verification, strict CORS and credential-validation behavior preserved. |

These are code-history dates, **not verified production deployment dates**.

| Category | First 60 billable days | After the 60th billable day | Attendants |
|---|---|---|---|
| General | ₹200 per billable person/day | Base + ₹50 per billable person/day; patient alone ₹250 | No included attendant; only present attendant marks are charged. |
| Lobby | Same verified General pricing path | Same verified General long-stay path | Same attendance-based per-person charges. |
| Private | ₹700 room base/day | Base + ₹200/day | One included; each extra present attendant adds configured ₹200 base fee and ₹100 long-stay surcharge. |

Base rates/included allowance use existing pricing settings. Historical ₹150 General default normalization remains. Manual stay daily rates and stored per-stay long-stay overrides remain effective. Rates above describe verified defaults, not invented room-specific tariffs.

The new approval quote is the **difference between two projections of the current admission**, using one coherent set of stay, attendance, receipt and rate data and one calculation time. It includes room transfers, manual overrides and actual attendant marks. It does not append a separate ledger charge. If overdue days are already included in an open admission's bill, extending metadata over those days does not charge them again.

Verified examples:

- 60 General billable days = ₹12,000; ten more = ₹2,500; total ₹14,500.
- 60 recorded days with ten absent days = 50 billable days. Ten additional projected days quote ₹2,000; the resulting 60-day invoice is ₹12,000.
- One more day after that crosses the threshold at ₹250.
- Private: 60 days at ₹700 plus ten long-stay days with two present attendants = ₹42,000 + ₹12,000.
- A manual ₹123.45 rate for 60 days followed by a stored ₹300 long-stay override gives ₹7,707 for 61 days.

PostgreSQL retains its established inclusive calendar-date billing. Legacy RTDB/offline billing retains its historical checkout policy; its quote now delegates to that same legacy invoice calculation. This task does not silently migrate old calendar rules.

## 4. Files changed

[files-changed.csv](files-changed.csv) lists each changed/preserved path and its purpose. Main behavioral changes:

- `backend/scripts/test-postgres.mjs`, `backend/package.json`: reproducible isolated backend matrix with generated SCRAM credentials, exact target guards and scoped cleanup.
- `test/postgres_real_workflows_e2e_test.dart`: self-provisioned PostgreSQL lifecycle; read-only audit query validation; cross-layer quote/storage/final-invoice regression.
- `backend/src/services/billing.ts`, `backend/src/routes/stays.ts`: shared quote/invoice projection; immutable extension retry identity; original duration preserved; planned exit and current invoice updated atomically.
- `lib/screens/rooms/widgets/extend_stay_dialog.dart`, `lib/services/room_service_stays.dart`, `lib/services/payment_service.dart`: authoritative quote retrieval, no stale/offline monetary fallback, loading/error handling, legacy invoice-based quoting.
- `backend/src/routes/payments.ts`: reject newly colliding references while preserving edits to imported shared-reference receipts.
- `backend/src/importer/index.ts`: invalid occupied-bed assignments cause strict import failure and rollback.
- `backend/migrations/002_integrity_hardening.sql`: only the down path changes to `DROP INDEX IF EXISTS`; no new migration or up-schema change.
- Backend regression tests and Flutter billing/quote tests cover these changes.
- Analyzer fixes span the existing UI/services/tests. They replace deprecated color/form/radio/web APIs, remove unreferenced private code, fix mounted checks and remove unreachable null fallbacks. Large line counts in several tabs are formatter output; no UI redesign was performed.
- `pubspec.yaml`/`pubspec.lock`: declare already locked `web 1.1.1` and `fake_async 1.3.3` directly; no dependency versions upgraded.

Pre-existing installer changes, existing installer executable and platform plugin registrant changes were preserved. No installer was rebuilt. The prior billing restoration remains in the working tree.

## 5. Exact validation commands and final results

Commands ran in the repository root unless the working directory says `backend`.

| Command | Working directory | Final result |
|---|---|---|
| `npm run test:postgres` | backend | Exit 0; 293 passed, 0 failed, 0 skipped. |
| `npm run build` | backend | Exit 0; TypeScript compilation passed after the final backend changes. |
| `npm test -- --reporter=dot tests/billing_pricing.test.ts` | backend | Exit 0; 17 passed. Also included in the final full backend matrix. |
| `flutter test --no-pub test/stay_billing_test.dart test/extend_stay_quote_test.dart --reporter expanded` | root | Exit 0; 34 passed (31 stay-billing + 3 quote-widget tests). |
| `flutter test --no-pub test/postgres_real_workflows_e2e_test.dart --reporter expanded` | root | Exit 0; 19 passed, 0 failed, 0 skipped. |
| `flutter test --no-pub --reporter expanded` | root | Exit 0; 443 passed, 0 failed, 0 skipped, including PostgreSQL E2E. |
| `flutter analyze --no-pub` | root | Exit 0; No issues found, after final source changes. |
| `git diff --check` | root | Exit 0. Git emitted CRLF-conversion notices for existing files, not whitespace errors. |
| `flutter build windows --release` | root | Exit 0; Windows Release bundle built successfully after final source changes, 52.9 seconds build stage. |
| Occupied-port negative test | backend | A listener created solely for the test occupied 55439; runner exited 1 with its expected refusal, before creating a database. The negative-test harness exited 0. |

The backend runner executes the existing project test convention through `node node_modules/vitest/vitest.mjs run --reporter=dot`. Its ordinary-test phase uses `--exclude=**/*.integration.test.ts`; **every excluded integration file is then explicitly executed** with its own exact database and opt-in flag:

| Suite/file stem | Flag = 1 | Database | Passed / failed / skipped |
|---|---|---|---|
| Ordinary test files | none | isolated workflows connection | 130 / 0 / 0 |
| workflows | RUN_PG_INTEGRATION | ngo_audit_workflows | 42 / 0 / 0 |
| modules | AUDIT_DATABASE_TESTS | ngo_audit_modules | 41 / 0 / 0 |
| importer | RUN_IMPORTER_DB_TESTS | ngo_audit_importer | 22 / 0 / 0 |
| payment_financial | RUN_PAYMENT_ACCURACY_INTEGRATION | ngo_audit_payment_accuracy | 36 / 0 / 0 |
| scalability | RUN_SCALE_INTEGRATION | ngo_audit_scale | 4 / 0 / 0 |
| settlement | RUN_SETTLEMENT_TESTS | ngo_audit_settlement | 13 / 0 / 0 |
| auth_database | RUN_AUTH_PG_INTEGRATION | ngo_audit_auth | 3 / 0 / 0 |
| migrations | RUN_PG_MIGRATIONS | ngo_audit_migrations | 1 / 0 / 0 |
| persistence | RUN_PG_RESTART | ngo_audit_workflows | 1 / 0 / 0 |

All database connections use `NODE_ENV=test`, `127.0.0.1:55439`, `ngo_audit`, and only the temporary cluster's generated password/explicit DATABASE_URL. Migrations run inside the guarded suite setup. The persistence suite additionally receives the owned cluster directory and pg_ctl path.

Security coverage includes 32 auth tests, 22 security-audit tests, ten Firebase verifier tests, ten config tests and three real-PostgreSQL Firebase UID boundary tests. The new quote endpoint is also tested for anonymous 401 and volunteer 403.

There is no separate `integration_test/` directory in this repository. The supported real PostgreSQL Flutter integration suite resides under `test/` and ran both independently and in the full suite.

Intermediate failures were investigated and corrected: the config test assumed port 5432 despite an explicit test-port override; stale duration/index/importer assertions conflicted with intentional newer behavior; new widget tests exposed an ambiguous finder and a quote-label overflow. Final runs above include their corrections. No failed or skipped final test is counted as passed.

Full evidence: [backend-tests.txt](backend-tests.txt), [flutter-tests.txt](flutter-tests.txt), [postgres-e2e.txt](postgres-e2e.txt), [billing-tests.txt](billing-tests.txt), [analyzer-after.txt](analyzer-after.txt), [windows-build.txt](windows-build.txt).

## 6. Analyzer before and after

Before: **281 findings: 0 errors, 53 warnings, 228 infos; exit 1**. [analyzer-before.csv](analyzer-before.csv) preserves all findings, sorted by severity, rule, file and line, with original messages/columns.

Major rule counts were 118 deprecated-member uses, 69 missing flow-control braces, 17 prints, 13 unused elements, 12 unused private parameters, ten dead-code findings, nine dead null-aware expressions and five async-context findings. Remaining rules are fully enumerated in the CSV.

After: **0 errors, 0 warnings, 0 infos; exit 0**. The final command actually returned `No issues found!`.

## 7. Read-only historical-data audit

Actual schema inspection in disposable PostgreSQL verified `duration_days INTEGER`, `total_extended_days INTEGER`, `extensions JSONB`, and the existing timestamp fields. The supplied query operates on those actual column names.

The old formula in `e012e95` was:

```
durationDays = old.duration_days + additionalDays
totalExtendedDays = old.total_extended_days + additionalDays
```

Since the model also computes `totalDays = durationDays + totalExtendedDays`, the same approved days can be counted twice in duration metadata. The corrected formula preserves original duration and increments only the extension field. The revised financial quote/invoice path uses billable date segments rather than trusting either inflated duration count.

The query ran read-only against an explicitly disposable, empty test copy before fixtures. Result: **0 stays examined, 0 extended, 0 candidates**. This verifies schema/query execution; **it is not an audit of real historical NGO records**. Real potentially affected count remains **unknown**.

[historical-extension-audit.sql](historical-extension-audit.sql) returns only aggregates for extended stays, possible double-count candidates, consistent separate durations, date-formula discrepancies and extension-entry mismatches. Its transaction is read-only and ends in ROLLBACK.

Controlled follow-up procedure:

1. Identify and authorize an anonymized snapshot/test copy and its provenance. Obtain actual deployment timestamps for the bug window; commit dates alone cannot establish exposure.
2. Restore it into a dedicated isolated cluster through the approved data-owner workflow. Use a SELECT-only audit role and explicitly verify database/host/port. Do not point this audit at the VPS or production volume.
3. Run `psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p <approved-copy-port> -U <read-only-role> -d <approved-copy-name> -f audit/release-readiness-20261021/historical-extension-audit.sql`.
4. Treat candidates as heuristics. Authorized reviewers compare original duration, admission/expiry dates, extension entries/request IDs, earlier snapshots and finalized invoices. Manual edits and inclusive-date conventions can resemble the old formula.
5. Record aggregate findings and a separately approved remediation proposal. Do not UPDATE, DELETE or backfill financial records through this release task.

## 8. Windows release candidate

Build succeeded after all final source changes:

`C:\Users\sahil\OneDrive\Desktop\NGO\build\windows\x64\runner\Release\ngo.exe`

Use the **entire Release directory**, including DLLs and `data/`; ngo.exe alone is not the complete application.

The bundle was freshly built. Flutter's incremental build reused the unchanged native launcher (313,856 bytes; timestamp 13:26:33). The Dart AOT application `data/app.so` was freshly rebuilt at **15:12:15 +05:30** (11,731,888 bytes). This distinction prevents an old launcher timestamp being misreported as a freshly relinked native executable.

SHA-256:

- ngo.exe: `E7475EFB8EDA195DB266A4E523F461EB70E8A18F75DD933DAB69E144841FB4E8`
- data/app.so: `98E30E8DEF191D0657F8227F4AD310B0EBA570A8076496712A800DF7C5130098`

The app was not launched against production. The existing installer remains untouched. The new client needs the matching backend quote endpoint; an older deployed backend will cause the extension dialog to fail closed until a coordinated, separately approved rollout.

## 9. Database, compatibility and safety impact

No new migration is required. The only migration edit makes an existing rollback tolerate an intentionally absent index. All migrations, rollbacks, fixtures, SQL fault injection and restart tests occurred in owned disposable clusters.

No production records, historical receipts, server credentials, VPS processes or production volumes were accessed or changed. No backfill, seed against live data, deployment, commit, push, history rewrite or Docker cleanup was performed. Temporary synthetic clusters created by this task were stopped and removed; their data is regenerable from the tests.

The working branch remains `main` at `129cfe74ae5a5f551c89d71fef0e4efe2f0bf3f8`, with all changes uncommitted for review.

Expected negative-test HTTP failures, migration filename timestamp notices and Drift's debug multiple-database-instance warning remain visible in test logs; none is suppressed or reported as a passing assertion by itself. All final assertions passed. The E2E cache scenarios deliberately create separate cache instances and verify reopen/reconciliation behavior.

Gravitas guided interruption recovery, evidence tracking, scoped edits and full verification. The final release verdict remains blocked because the historical real-data risk has neither been measured on an approved snapshot nor explicitly accepted for deferral.

## 10. Remaining blocker and final status

**One unresolved release item:** approve/provide a safe historical snapshot for the aggregate audit, or explicitly approve deferring that data-integrity review. No unresolved pricing-policy choice remains after your attendance-based quote decision.

Engineering validation: passed. Windows candidate: prepared. Production historical-data assessment: unverified. Release authorization: **RELEASE BLOCKED**.

VERDICT: FAIL -- historical real-record exposure remains unverified and has not been explicitly approved for deferral.
