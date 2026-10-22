# Read-only historical findings — 22 October 2026

No VPS, production database or real patient export was accessed. No approved
anonymized production snapshot was supplied. Real historical affected-record
counts remain unknown. The local working directory contains exports, but this
audit intentionally does not treat those as approved anonymized snapshots.

The findings below are code-history evidence, not claims about deployment dates
or the contents of production records.

| Evidence | Confirmed historical behavior / exposure |
|---|---|
| `918225c09c80b1666ce9c6456dbc64f0f5190921` | Flutter `PricingHelper.calculateDailyCharge` multiplied General patient-and-attendant pricing by `bedsCount`. Private used one base, not two patients, and a configurable included-attendant allowance. |
| `918225c09c80b1666ce9c6456dbc64f0f5190921` | `StayBilling` counted admission-wide billable days, added General ₹50/person and Private ₹200 base plus ₹100/extra attendant after day 60, and chose the highest-priced segment on a transfer date. The generic duration helper used a >09:00 cutoff for all categories; it did not establish an independent itemized Private surcharge. |
| `e012e95552068c4caf55a801c78f29ebc5f34a86` | Extension handling incremented both `durationDays` and `totalExtendedDays` and appended flat-rate extension costs. Code adding the two duration fields could count an extension twice. |
| Starting HEAD `0596354a855740f93a93043b2073a2877317ce40` | The previous extension fix already preserves original duration and calculates marginal invoice projections. This implementation must preserve it. |
| Starting HEAD | PostgreSQL discharge picked the planned exit / expected stay date and saved it as `discharge_date`; actual checkout time was not transmitted reliably. Inclusive day billing ignored the confirmed General late checkout adjustment. Historical `discharge_date = exit_date` is only a review candidate because real actual/planned equality can be valid. |
| Starting HEAD | Backend attendant billing parsed individual `attendantName/status` payloads while the API and Flutter editor store a nested day/patient map. The mismatch could omit applicable attendants. Name-based map keys also collapse duplicate names. |
| Starting HEAD | Unmarked patient attendance was charged provisionally without an explicit pending state; discharge checked patient marks but not the required attendant roster. An entirely absent Private patient and attendant day could be skipped before charging the reserved base. |
| Starting HEAD | Transfer placement was atomic, but invoice recalculation occurred separately in Flutter. A failed subsequent request could leave stored summaries stale. Rejoin consisted of separate placement, admission and stay writes. |
| `129cfe74ae5a5f551c89d71fef0e4efe2f0bf3f8` | Security baseline dated 21 October 2026, 13:18:46 Asia/Kolkata. Token verification, database-authoritative permissions, strict CORS and financial validation must remain in place. No legacy implementation was restored wholesale. |

Existing schema already has `patients.discharge_date TIMESTAMPTZ`, planned
`patients.exit_date`, `stays.completed_at`, `stays.billing_summary JSONB`,
`patients.admission_balances JSONB` and stable `patient_attendants.id`.
These support actual checkout, itemized adjustments and identity-based records
without destructive historical backfills.

`historical-billing-exposure.sql` adds aggregate-only read-only checks for the
confirmed risk areas. `historical-extension-audit.sql` from the previous audit
continues to cover extension-ledger mismatches. Candidate counts need review
against approved snapshots and receipts; they must never trigger automatic
invoice changes. Disposable regression fixtures validate schema/query behavior
and preserved financial history, but cannot measure production exposure.

Validation performed in this session: the focused PostgreSQL Flutter E2E suite
passed **23 tests, 0 failed, 0 skipped**. Both historical audit SELECTs executed
successfully against its newly provisioned disposable PostgreSQL 16 schema. The
new query returned zero for each of its eight aggregate columns because that
test runs before any synthetic patient is inserted. The prior extension query
also returned zero in all six columns on the same empty test database. These
zeros establish executable schema compatibility; they say nothing about actual
historical exposure. The settlement integration fixtures additionally compare
old stays, frozen cycle balances and receipts before/after confirmed and unknown
rejoin retries, and preserve those records unchanged.

Evidence: `postgres-e2e.txt` is the final successful run. The initial E2E run had
21 passes and two failures from old test fixtures that assumed name-keyed
attendance or completed a stay before marking/settling attendance; it is kept
as `postgres-e2e-initial.txt`. The corrected final run requires stable IDs and
settles attendance before finalization. No skipped or failed test is counted as
passed. `backend-client-rules.txt` records the focused 31-test pure billing suite
passing with zero failures/skips, including ambiguous legacy attendance,
unknown historical Pending records, canonical new tariffs and preserved stored
per-stay pricing.
