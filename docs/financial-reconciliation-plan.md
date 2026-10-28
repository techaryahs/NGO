# Financial reconciliation and release gates

The payments table is authoritative. Embedded payment histories are API views,
not additional receipts. Charges may be frozen in admission_balances; they must
not be reconstructed using today's tariff. Allocation currently applies to an
entire receipt; partial allocations are not supported by the existing model.

The current schema-export task proposes no production schema or data changes.
The local uncommitted migration 010 adds change-history structures, but these
are absent from the supplied VPS schema and are not used by the exporter.
Adding partial allocation or changing an established historical allocation needs
an append-only correction history (receipt ID, previous/new cycle, evidence,
authorized actor, timestamp, idempotency key), implemented and integration-tested
before any historical correction is authorized. Existing local mutation changes
are not evidence of deployment or successful production reconciliation.

## Schema-verified manual export (current step)

Use [the read-only export instructions](../backend/scripts/export-financial-data.md).
The primary reference is the supplied PostgreSQL 16.15 schema, not the local
migration directory. Copy `export-financial-data.py` and
`production-financial-schema.json` together. Run manually through the existing
authorized psql context; the agent must not connect to the VPS or read `.env`.
Retrieve only `financial-data.json` and `financial-summary.json`; retain the
identity map and pseudonym key privately. This export is not a database backup.

The older TypeScript offline audit below now recognizes this pseudonymous export
format. It does not reinterpret its tokens as timestamps. Its original raw-row
mode remains available for earlier private snapshots; the generated Python
summary is preferred for the schema-verified export because it deliberately
leaves every missing cycle ID unresolved.

## Offline dry run

Run `npx tsx scripts/audit-payment-allocations.ts snapshot.json` from backend.
The input uses database-shaped patient, stay and receipt rows. The command does
not connect to a database or write files. Repeated identical input produces
identical output. Duplicate receipt IDs fail instead of being silently counted.
Review unknown cycle IDs and ambiguous receipts against original transaction
evidence; date proximity does not establish ownership.

Before obtaining a production snapshot, verify the server/database identity and
take an independently recoverable backup. Retain that snapshot outside Git.
Use a read-only transaction for extraction. Do not apply this report as SQL.

Known review cases from prior API-only audits include registrations 5157, 5219,
5149 and the seven other accounts identified in the payment-cycle report.
Registration 5255 additionally has conflicting legacy/ID attendant marks.
Registration 5251's 4200/5200 screenshot difference remains unproven.

## Shared root-cause correction (28 October continuation)

The completed export findings are retained unchanged in
`audit/production-export-20261028/`. They describe the resolver at analysis time;
the implementation now deliberately stops inferring historical receipt ownership
even on a single-known-cycle account. A remaining cycle does not establish that
all previous admissions were retained. The 67 receipts / 165,600.00 are visible
at account level and await allocation evidence, rather than being silently
converted into established cycle allocations. This is uncertainty, not a loss.

New online receipts are different: under the patient lock an explicit known
cycle, or a single unambiguous admission choice, is persisted at creation. A
later rejoin cannot change that receipt's ownership. Positive unallocated
advances remain supported. Cycle-specific collections and refunds require
established allocations and supported charges. Original imported `cycleId` and
`receiptCycle` associations are retained; placement/payment dates are not used
to create historical identities.

New online placements stamp the locked admission into both the explicit cycle
and snapshot. Contradictory caller identifiers are rejected atomically. Legacy
stay reads use explicit identity, snapshot identity or a unique saved segment
owner; missing/conflicting evidence is returned in reconciliation metadata.
Neither shared snapshots nor coincident dates authorize merging two invoices.

All PostgreSQL financial projections use `projectBilling`; the importer
no longer writes account-wide receipt sums into current-cycle paid fields.
Flutter uses backend reconciliation metadata and does not replace it with
date-based payment allocation. Historical allocation changes through the payment
API require an administrator, supporting reason and append-only history.

## Historical dry run — no corrections executed

Run `python audit/production-export-20261028/prepare-corrections.py` from the
repository root, optionally followed by the financial-data.json path. The script
verifies the supplied snapshot hash and reads the existing analysis; it does not
connect to a database, load an identity map, generate executable SQL or apply
corrections. Repeated identical inputs produce byte-identical outputs:

- `audit/production-export-20261028/historical-dry-run.json`: every patient,
  receipt/cycle reference, original amount/date/reference, frozen balance,
  proposed metadata completion, before/after totals and review requirements.
- `audit/production-export-20261028/historical-dry-run.md`: all 153 patients and
  a review summary.

There are 35 metadata-only stay proposals backed by exactly one saved segment
owner; each preserves all charges and receipts with zero financial delta.
There are no proposed receipt reassignments. All 80 unestablished associations
(79 missing IDs and one unmatched explicit ID), net 189,200.00, await original
allocation/admission evidence. Ledger net stays 909,550.00. Saved-versus-strict
projection differences do not prove that the old saved allocation was wrong.

5157 retains both frozen 1,200.00 stay invoices and the original shared-snapshot
receipt. 5219's full untagged amount is 6,800.00, not just the earlier 4,400.00
subset. The 800.00 cached-field conflict needs invoice evidence. Duplicate
reference groups, both status conflicts and 5255's conflicting source marks
remain preserved. The 5251 screenshot difference remains unexplained.

## Release gates

See `docs/financial-root-cause-fix.md` for implementation and actual verification.
The supplied production schema includes migrations 001–009 only. Local migration
010 is required for receipt correction history; it has not been applied to
production. No new financial schema migration is added by this continuation.
Before any eventual migration or historical correction, verify target/version,
restore-test an independent backup, review original evidence privately, record
operator/reason/original/new state for both receipt and stay corrections, and
test transactional/idempotent recovery. A metadata-only proposal is not an
authorization or a tested production correction command. No deployment or
historical correction is performed in this phase.
