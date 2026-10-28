# Financial identity and allocation correction — 28 October 2026

This continuation uses the completed production export findings. It does not
re-audit production, access credentials/SSH/private pseudonym material, deploy,
or correct historical data. Existing unrelated working-tree changes are retained.

## Root causes and shared behavior

1. **Conflicting stay identity could be created.** The stay writer stamped the
   current admission into `patient_snapshot.admissionDate` but accepted a different
   caller `cycleId`. The importer independently filled a missing cycle from the
   placement date. Billing preferred the explicit value, so the 5157 pattern
   produced two charge groups while a receipt retained their shared snapshot ID.
   The export establishes that disagreement; it cannot identify the original
   writer or prove either frozen accommodation charge invalid.

   `billing.newStayIdentity` now defines online placement identity from the locked
   admission. Stay insertion rejects contradictory explicit/snapshot/summary
   identifiers and stamps a consistent pair. Transfers and rejoins use that
   writer. Imports retain existing explicit/snapshot associations and do not
   manufacture identities from placement dates. Historical read resolution uses
   explicit ID, snapshot ID, then unique saved `segmentCharges` ownership. Missing
   or conflicting identities are reported, preserving the original source rows.
   Snapshot conflicts are never silently aliased or merged.

2. **Historical receipt inference was unstable.** Even the remaining single-cycle
   fallback could change on a later rejoin and could not detect deleted or
   incompletely imported admissions. `receiptCycle` now leaves recorded untagged
   receipts unallocated. The only automatic single-cycle choice is a *new online
   request*, under the patient lock, persisted once. Imports preserve source
   `cycleId`/`receiptCycle`, including conflicts for review, without date inference.

   This intentionally changes the treatment of 67 legacy receipts / 165,600.00:
   they remain in account totals but do not establish a confirmed cycle balance
   merely because only one cycle is known. Reliable original allocation evidence
   or a complete, independently verified admission history is needed for review;
   agreement with a saved aggregate alone is insufficient. Fully allocated
   accounts retain their established calculation behavior.

3. **Account money and current-cycle money were conflated.** The importer still
   updated current paid fields using all patient receipts, independently of the
   shared resolver. Reconciliation imports now project/persist with the same
   billing service as online financial mutations. Every signed `payments.amount`
   contributes once to account paid/refunded/net values. Only established
   ownership contributes to a cycle; embedded histories are not extra receipts.
   Frozen invoice totals remain the charge source.

4. **Frontend derivation could contradict the backend.** The profile still assigned
   untagged payments by date, and aggregate collection displays could exclude
   unallocated/historical money. The profile now reads authoritative cycle and
   account totals, the payment dashboard sums account net receipts, unresolved
   collection actions are disabled, provisional amounts are qualified, and the
   existing refund suppression respects reconciliation state. Cache round-trip
   tests retain the server metadata. Original history remains available.

5. **Receipt reference matching was too permissive.** Reconciliation import could
   silently absorb another source ID merely because its reference and amount
   matched. Matching now prioritizes exact/truncated identity, checks transaction
   patient/amount/date/type, and reports distinct-ID reference matches as conflicts.
   Contradictory cycle associations in copies of the same receipt are rejected.
   These changes do not deduplicate the export's ten reference-candidate groups.

## Financial boundaries

`projectBilling` returns `reconciliation.required`, `unallocatedReceipts` with
reasons and original IDs/cycles/amounts, `unallocatedNet`, `accountPaid`,
`accountRefunded`, `cycleIdentityIssues` and `chargeIssues`. Patient DTO metadata
also contains account net paid. All cycle balances carry reconciliation state.
Missing invoice evidence cannot certify an overpayment as refundable; in
particular the stored 800.00 inconsistency remains an unverified candidate.

The existing whole-receipt model is retained. No wallet, partial-allocation
subsystem, alias table, rate/cutoff change or new financial schema is needed for
these corrections. The existing local migration 010 preserves payment changes
with operator/reason and old/new rows; it is not present in the exported live
schema and is not claimed deployed. Its history does not reconstruct old events.

| Path | Authoritative validation / verification |
|---|---|
| Payment POST and idempotent retries | Patient lock, persisted new allocation, fingerprints/reference protection, account and cycle projection in transaction |
| Cycle-specific collection | Reconciliation guard and current due recalculated under the same lock; concurrent over-collection rejected |
| Refund POST/PUT/PATCH | Reconciliation, provisional/attendance, remaining excess and nonnegative-net checks; rejected insert/edit rolled back |
| Receipt allocation correction | Administrator plus supporting reason; known-cycle checks; original/new history and no duplicate history on exact retry |
| Payment PUT/PATCH/DELETE | Common delta projection and lock order; receipt ownership race and trigger-failure rollback tests retained |
| Settlement preview/recalculate | Shared projection; GET is read-only; supplied checkout distinct from booking; frozen charges preserved |
| Patient discharge and last-stay completion | Shared finalizer validates reconciliation/attendance/settlement; failed bed release or stale-state check rolls back closure and balances |
| Generic patient PUT | Rejects injected derived financial fields and direct lifecycle/admission changes |
| Stay create/batch/register/transfer/rejoin | Common admission identity writer, atomic placement/financial state, idempotency and concurrent placement tests |
| Extension quote/approval | Shared attendance-based marginal pricing; identity conflict rejects unsafe quote; retry/rollback and cutoff tests |
| Import reconciliation | Shared invoice/allocation engine; original receipt identity protected; no account-wide sum written into current-cycle paid |

Physical occupancy and final financial settlement continue to follow the
existing discharge workflow. The code does not fabricate attendance/departure
or silently resolve the two historical occupancy/status conflicts. Existing
administrator deletion workflows remain explicit destructive actions, not a
historical reconciliation mechanism; this phase never invokes them against live
data. Tests use isolated fixture databases, including their deletion/rollback
cases. Local append-only receipt history preserves originals for supported edits.

## Historical proposals

See `audit/production-export-20261028/historical-dry-run.md` and its JSON for every
patient/receipt/cycle, evidence, before/after figures and review requirements.
The report reuses the completed analysis and verifies its source snapshot hash.
Repeating it is byte-identical. It proposes 35 unique saved-owner metadata
completions, no receipt reassignment, no charge correction and no refund.

All 153 patients, 201 stays, 289 receipts and 176 known groups appear. Ledger net
before/after is 909,550.00; 80 unestablished associations total 189,200.00 under
the strict rule. This is neither a proven loss nor a refund amount. 5157, 5219,
the 800.00 conflict, duplicate candidates and lifecycle conflicts still need
original evidence. 5255 uses the preserved ID-first summary correction. Neither
5251 screenshot response exists in the export; no charge change is justified.

## Verification

| Check | Observed result |
|---|---|
| Full backend matrix | 412 passed: 201 ordinary tests and 211 PostgreSQL integration tests; all nine opt-in suites executed |
| Settlement / payment accuracy / importer | 47 / 40 / 27 passed, respectively, within that matrix |
| Full Flutter suite | 541 passed, including the real disposable PostgreSQL end-to-end workflows |
| TypeScript build | `tsc` succeeded, exit 0 |
| Flutter static analysis | No issues found, exit 0 |
| Final diff whitespace check | Passed; Git's CRLF conversion notices are informational |
| Historical dry-run repeatability | Identical JSON/Markdown hashes on a repeated run; no database connection |

There are no remaining failures in these executed suites. The three originally
reported charge/extension failures were fixture boundary errors: UTC midnight
is 05:30 IST and cannot represent an inclusive after-cutoff final date. Fixtures
now supply an after-cutoff planned time where they expect that date included.
The end-to-end fixtures had the same mistake at exactly 09:00. Actual checkout
assertions still cover 08:59, 09:00 and 09:01 with the established tariffs and
60-day tiers. No cutoff/rate implementation was changed to make tests pass.
Open-admission tests now independently pin billing time and verify elapsed days,
and mutation fixtures supply frozen invoice evidence instead of trusting caches.

Actual command outcomes are recorded after the final runs in
`audit/production-export-20261028/implementation-verification.json`.
No passing test certifies bank receipts, historical allocation intent, deployed
revision or all frozen invoices. Release still requires the separately approved
backup/migration/review process; production data has not been fixed by local code.
