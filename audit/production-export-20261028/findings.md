# Actual production export analysis — 28 October 2026

This is offline analysis of the two exact Desktop files. No credentials, keys,
identity maps, APIs, SSH connections or databases were accessed. No application
code, schema, historical charge or transaction was changed during this task.

## Provenance and completeness

Both JSON files were parsed completely with decimal-safe arithmetic. The data
file SHA-256 is `c8a4ff557208290163614404bda7b76c27f3f6d3d64cb148de780203ece4edc1`.
The summary SHA-256 is `d3cbedbbc10af54d8bcac3a8a74dfbb5d333c2f901add57b24c1d5aee9f03d77`.
The canonical records hash exactly matches the embedded hash
`4d2fcff75a88073b793126140d3ae7019370c9c79d47e7826e09f1a4f43a43ac`.
Recomputed counts, account/grand totals and every reproducible issue list match
the supplied summary. Raw-ID prefix analysis cannot be independently repeated
without original IDs; the supplied prefix-candidate list is empty.

Export metadata reports PostgreSQL 16.15, database `ngo_db`, a repeatable-read,
read-only transaction captured at **2026-10-28 12:23:43.972809 IST**. The null
server address/port is consistent with a Unix socket; the file itself does not
prove the running API's database or application revision.

Examined: **153 patients, 201 stays, 289 payments, 4,048 attendance rows, 171
attendant records, 17 rooms, 47 beds, one sponsorship, eight pricing settings and
nine migration rows**. There are **171 saved admission balances** and **176
known cycle groups**, including five current groups without a saved balance.
The distinction explains the earlier count of 176 returned API balances.

No duplicated table IDs or exported broken foreign-key relationships were found.
All 171 saved balance due/refund formulas and segment-charge sums agree with
their own saved inputs. This does not establish that the saved invoice is right.

## Financial accounting, without assigning unknown receipts

| Measure | Amount |
|---|---:|
| Positive receipt amounts | ₹909,950.00 |
| One recorded negative refund | ₹400.00 |
| Net payments | **₹909,550.00** |
| Net receipts explicitly matched to known cycle groups | ₹720,350.00 |
| 79 receipts with no cycle IDs | ₹188,000.00 |
| One explicit cycle absent from authoritative groups | ₹1,200.00 |
| Strict export unresolved total | **₹189,200.00** |

The three categories of net receipt amounts sum exactly to the ledger net. Every
one of the 289 records is included once. These are recorded transaction amounts,
not independent bank verification or certified losses/refunds.

The missing-cycle receipts split into **67 records/₹165,600 across single-known-
cycle accounts**, and **12 records/₹22,400 across eight multi-cycle accounts**.
The current local resolver implicitly allocates the former; its simulated
unallocated amount is therefore **₹23,600**, including the ₹1,200 unmatched
explicit receipt. That simulation does not authorize historical reassignment.

**120 receipts have `paid_amount != amount`.** Summing `paid_amount` would give
₹1,914,650, versus the actual signed `amount` sum ₹909,550. This demonstrates why
transaction `amount` must remain authoritative: `paid_amount` often represents
cumulative payment state. It does not establish that current billing code is
making that mistake; inspected billing uses `amount`.

## All 59 saved-cycle and 55 current-cycle flags

Every flag is classified individually in **flag-classification.csv**, with full
patient/cycle pseudonyms, saved values, explicit-only totals and local-resolver
totals.

- **50/59 saved-cycle flags** are explained exactly by single-known-cycle legacy
  receipts. The saved totals exceed explicit-only totals by ₹151,000 in aggregate;
  the local resolver includes those receipts. These are comparator differences,
  not established missing money.
- **9/59 saved-cycle flags** concern the eight multi-cycle patients below. The
  aggregate ₹22,400 difference is precisely their untagged payments. Saved cycle
  assignment is unproven; no alternative is selected.
- **55/55 patient/current-cycle flags** are explained exactly by the local
  single-known-cycle rule, totaling ₹165,600. No unexplained residual remains in
  this comparison. A single apparent cycle is weaker evidence than a verified
  persisted allocation, especially before a later rejoin.
- The **six account-versus-saved-cycle flags** are one ₹1,200 omission and five
  patients with entirely absent saved admission-balance maps, whose recorded net
  receipts total ₹14,600. An absent map is not proof that payments disappeared:
  patient/legacy invoice fields exist. One of those five also has the separate
  ₹800 cached arithmetic conflict described below.

## Eight accounts requiring cycle-allocation review

The registration column below is only a unique prior-audit admission fingerprint
match. Registration identifiers in the export are HMAC tokens. They were not
decoded or independently mapped. The five specifically requested cases each
match one exported admission timestamp and the previously observed financial
structure; no private key or identity map was accessed or requested.

| Patient pseudonym | Prior fingerprint | Missing-cycle amount | Explicit unmatched amount |
|---|---|---:|---:|
| patient_6b5574d907873b2f94bf79a3dbb64af87bee44b6c2bfe2a36c926ac9563b625f | — | ₹3,200 | ₹0 |
| patient_c2cb34ba3220ab03fa66bf4bd050182daab11c776ed55556131c9100c0073719 | 5219 | ₹6,800 | ₹0 |
| patient_6bed0cf4b879eb7a4b279054f41a2c8256168278684887f93bdac0a578c4d529 | 5157 | ₹1,200 | ₹1,200 |
| patient_85ee49249c90517e5b89193955f8e1f8a043b62a5b89652583f80d1ffc83dbb3 | — | ₹3,000 | ₹0 |
| patient_721cd8e7917ac0443a891cd808a339989ee06e0d36e1c18176648e139acd45f1 | — | ₹2,200 | ₹0 |
| patient_38f2e5d77cc42fbd21ef29ac3eff111914f43fae5e2728faaecd3829ab41a4bf | — | ₹4,800 | ₹0 |
| patient_77b05d52531656ec282d450d3b6b54f76846120b4d423fe84603c7c3be87e774 | — | ₹400 | ₹0 |
| patient_93c6bd482ad429e3b2bc8932a1f3b55fe8ce6e6ffd012394439daec6edff3f5b | — | ₹800 | ₹0 |

Receipt pseudonyms for every account are listed in patients.csv and analysis.json;
all nine affected saved cycle IDs are in flag-classification.csv. None of this
₹23,600 is a demonstrated loss or authorized refund.

## Confirmed recorded inconsistencies and requested cases

### 5157 fingerprint: omission and contradictory stay identities

Five receipts total ₹5,400; saved cycles total ₹4,200 of net payments. Receipt
`payment_17729e4432c4adfb9e98944ee6e127de0a3f0894ffe16970a5651a3e1223d749`
is ₹1,200 and points to
`cycle_a39b18e310626e3bd27da2702f78179dca6c714f12d65c85d6c6c1df4f12c153`.
That ID is absent from current/stay-explicit/saved cycle groups, but it **matches
the snapshot cycle in both** of these stays:

- `stay_5cafe1bf4229ac5fe654d587c1d242a7830ed4c1e808f9dde887578a5ed8a158`
- `stay_e3225f134082d99807b78d93f147cbf09d59104c2375d7c1ddedd59dc1c8abe5`

The two stays have the same patient, room and interval (20–23 September), different
beds and explicit cycle IDs, and ₹1,200 charges each. This is stronger evidence
of cycle-identity drift than simply calling the receipt cycle invalid. It raises
a possible duplicate accommodation-charge issue, but different beds can be
legitimate: do not erase one charge or redirect the receipt without the original
admission/placement evidence. Frozen charges remain untouched.

The current code prefers explicit stay cycle IDs over snapshot IDs. This creates
two charge groups while the receipt retains their shared snapshot identity.
The old projection only iterated group IDs and omitted that receipt. The current
uncommitted projection exposes it in reconciliation instead. Code changes have
not repaired the underlying records.

### 5219 fingerprint: unproven cycle ownership, not a proven refund

Patient `patient_c2cb34ba3220ab03fa66bf4bd050182daab11c776ed55556131c9100c0073719`
has five payments totaling ₹9,200. Three lack cycle IDs, totaling **₹6,800**;
the previously discussed ₹4,400 is a subset. Saved historical cycles attribute
₹4,400 and ₹2,400 to different groups; the current explicit cycle has ₹2,400.
The stored ₹2,200 refund candidate depends on those unproven historical
allocations. Two unassigned receipts also repeat a transaction reference but
have different amounts/timestamps, so the export does not prove duplication.

### 5149 fingerprint: single-cycle legacy receipt and lifecycle conflict

Patient `patient_f6ad499cfd306a24392e64bf960f78489d82c3a89abe461cc4493631d6bd9df4`
has receipts ₹2,400 without a cycle plus ₹5,400 explicitly associated. The saved
single-cycle net ₹7,800 agrees with the local resolver. This is **not** another
explicit-cycle omission. The patient is labeled discharged while its stay is
active. Allocation evidence remains weaker than an explicit receipt association;
physical occupancy/departure cannot be corrected from financial fields.

The second discharged patient with an active stay is
`patient_2030fdffe6709eff91a1fb55b3e850037f3d6ad618bffe67cbae2eb85f91470a`.

### 5255 fingerprint: conflicting attendance representations

Patient `patient_245b79d617576bb618c4eee92781768ea262fcf9317958a7281ab5b47ef973f9`
has one explicitly matched ₹800 payment. Five attendance rows contain overlapping
legacy/ID representations: Present versus Unmarked on 23 October, Present versus
Absent on 24–27 October. These are all five overlapping-mark candidates in the
export. Billing's ID precedence and a raw-name summary can produce different
counts. Correct effective counts for 21–27 October are 2 Present, 4 Absent,
1 Unmarked. The snapshot invoice ₹1,000/paid ₹800/due ₹200 uses the planned
boundary and is provisional. This is a summary/representation defect, not proof
of an incorrect payment or refund.

### 5251 fingerprint: booking snapshot is not the late-checkout preview

Patient `patient_943e7420171add3148b1bf8fbc47c2dbb867ed0d253ff3258b92de0e783dc69b`
has two matched payments, ₹2,800 and ₹400. Its saved invoice is ₹3,200 for eight
patient/attendant Present dates (16–23 October), with `checkoutAt=null`. Marks
for both kinds on 24–28 October are Unmarked. There is **no saved 09:59 or 10:18
checkout response/history** in the export. The prior ₹4,200/₹5,200 screenshot
difference remains unproven. The active stored rate and unresolved marks are
compatible with a provisional ₹4,200 late-checkout projection (13 patient days
at ₹200 plus 8 attendant days at ₹200), but this is a code-based projection,
not a final bill or evidence of the earlier screenshot's inputs.

### Additional cached arithmetic conflict: ₹800

Patient `patient_2b827ab65a747a2007abf1f11fa55510bb0ab781fbbdaf8f7aa86ec2d84cfbb6`
has ₹4,000 ledger receipts, stored current paid ₹4,000, stored billed ₹3,200,
no override/attendance surcharge, due ₹0 and refund ₹0. Those saved fields
contradict their own settlement formula by **₹800**. No stay or saved admission
balance supplies independent invoice evidence, and the receipt belongs to a
placeholder-reference candidate group. Therefore this confirms inconsistent
cached fields, **not an ₹800 entitlement**.

## Other candidate groups

The 20 duplicate flags are **10 groups reported twice**, once for exact reference
and once for normalized reference. They comprise six transaction-reference
groups and four receipt-number groups. One transaction group is a recognized
placeholder shared by 13 receipts across eight patients. One strongest candidate
has two ₹1,000 receipts with the same patient, amount, timestamp and reference;
all other groups differ in amount/date/patient. None is a duplicate table ID,
and none proves money was collected twice. analysis.json includes every group,
every receipt ID, amount/date and placeholder classification.

Of 36 missing explicit/snapshot stay-cycle IDs, **35 have exactly one saved
segment-charge owner cycle**; the remaining completed stay has no saved balance.
For all 36, evaluation of the existing code takes the current-cycle fallback;
for the 35 with saved evidence it agrees. Missing metadata does not itself prove
misallocation. The created-at fallback should still be replaced with established
cycle identity for future writes; it is not authorization for a historical write.

## Comparison with the current working tree and implementation priorities

1. **P0: cycle identity and review.** Preserve the same shared receipt resolver
   across projection, importer and mutation paths. Continue exposing every
   unmatched receipt at account level. Add tests based on the 5157 structural
   pattern (two explicit stay cycles sharing a different snapshot cycle), not
   just a synthetic orphan string. Do not fix this by assigning to the nearest
   stay, by matching a timestamp, or by rewriting frozen charges. Resolve the
   authoritative admission identity from external evidence first.
2. **P0: mutation/UI consistency.** The local payment route distinguishes
   collection/refund from positive advances, rejects unresolved collection and
   refund, and the settlement/discharge transaction rolls back on failure.
   Account-level totals and original receipts must remain visible. Tests must
   prove that ambiguous historical receipts, not stale displayed excess, govern
   safety. Deployment is not proven by this export, which has only migrations
   001–009, not the local 010 audit structures.
3. **P1: remove contradictory derivation.** The local resolver includes missing
   receipts when exactly one cycle is known; the exporter intentionally requires
   explicit evidence. Label these two semantics separately. Keep new receipt
   associations persisted once established so a future rejoin cannot change
   old implicit interpretation. Correct the export-summary wording/comparator
   to avoid presenting the 55/50 explained differences as verified errors.
   Always sum signed `amount`, not cumulative `paid_amount` or nested histories.
4. **P1: cached versus frozen data.** Rebuild only derived paid/due/refund fields
   from established allocations; preserve frozen invoice totals. In the one
   ₹800 case, verify original charge evidence before treating the calculated
   difference as a refund. Empty saved maps need explicit legacy handling,
   not an assumption that every receipt was omitted.
5. **P1: lifecycle/attendance.** Reconcile the two status conflicts with actual
   occupancy/departure evidence. Keep attendance ID precedence consistent with
   summaries, retaining both source representations for history. Pending marks
   and provisional booking snapshots cannot certify final settlements.
6. **P2: duplicate review and provenance.** Use original bank/receipt evidence
   for the 10 candidate groups. Do not merge placeholder-reference groups.
   The local audit-history migration cannot reconstruct past edits or the
   5251 screenshot state. Any later correction needs backup, reason/operator,
   before/after values, idempotency and tested recovery.

No new large implementation is started. Existing application tests were inspected
for coverage, not used as proof of production correctness. The analysis is
repeatable with `python audit/production-export-20261028/analyze.py` against the
same two Desktop paths; it asserts input consistency before generating reports.

## Complete patient results

The mutually exclusive record-consistency classifications are **5 patients with
confirmed recorded inconsistencies**, **24 other patients needing review**, and
**124 whose compared recorded totals agree but whose final charges are not
independently certified**: 5 + 24 + 124 = 153. Cases overlap internally (for
example 5157 has both ambiguous receipts and conflicting stay identities), but
no patient is counted twice in these three categories.

See patient-report.md (153 rows), patients.csv (153 rows, receipt/stay/cycle IDs),
cycles.csv (176 cycle groups), flag-classification.csv (114 original flags), and
analysis.json (complete classifications and evidence). These do not mark the
entire system or every patient bill as financially correct.
