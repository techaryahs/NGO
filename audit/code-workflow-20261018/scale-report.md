# Synthetic API scalability verification — 2026-10-18

Only the disposable PostgreSQL 16 database `ngo_audit_scale` at `127.0.0.1:55439` was created/seeded. Guards check the exact URL, user, test environment, live database identity and server major version before schema or data writes. No existing application database, external Firebase account, desktop automation or VPS was used.

## Verified dataset and correctness

| Stage | Patients | Attendants | Payments | Stays | Attendance records |
| --- | ---: | ---: | ---: | ---: | ---: |
| Small | 1,000 | 1,000 | 5,000 | 2,000 | 30,000 |
| Large | 10,000 | 10,000 | 50,000 | 20,000 | 300,000 |

Checks assert unique complete patient/payment traversal, five correctly associated payments and one attendant per patient, exact integer-cent totals (500,000 cents across the large dataset), day/month attendance counts and filtering, full stay counts, and 20 concurrent successful patient requests. Fixtures use synthetic identifiers and no photos.

The original Flutter collection requests received only the default 500 patient/payment rows. Backend collection GET routes now provide stable date/id keyset continuation via `x-next-cursor` and `x-pagination-mode: cursor`; the client aggregation change is owned by the parallel frontend task. Existing limit/offset callers retain their response shape and behavior. Additional live regressions cover more than 500 equal timestamps, deletion of the last returned row between pages, exact PostgreSQL microseconds, malformed/wrong-resource cursors, and final/empty pages.

## Measurements and focused changes

| Large dataset measurement | Baseline | After focused change |
| --- | ---: | ---: |
| Patient page of 5,000, median of 3 | 3,923.39 ms | 1,425.88 ms |
| Patient page payload | 15,275,020 bytes | 15,275,020 bytes |
| All 10,000 patients, cursor pages of 500 | unavailable | 20 requests / 30,677,900 bytes / 3,329.74 ms |
| 20 concurrent patient pages of 500, p95 | 1,827.52 ms | 1,871.64 ms |
| 20 concurrent patient pages of 500, throughput | 10.36 requests/s | 10.30 requests/s |
| Native attendance month SQL, same-data EXPLAIN pair | 262.864 ms | 141.600 ms |
| Attendance month SQL temporary read blocks | 6,802 | 0 |

Patient serialization previously filtered the entire selected payment set for every patient. It now groups payments once, preserving every association and payment order. The measured large-page median decreased while payload and query count stayed constant (four database queries including authentication per populated patient request). Timings were collected during other local verification workloads; they describe these runs and are not production SLOs or an isolated performance study.

Attendance originally ordered the selected `attendance_date::text` output alias. Qualifying `attendance_records.attendance_date` preserves the date string output while ordering the native DATE column. The 300,000-row plan changed from a parallel external merge sort to an index scan using the existing kind/date/patient index. A patient-filtered month used the existing `ix_attendance_patient_id`, returned exactly 30 rows in 0.136 ms SQL execution time and 26.53 ms API time; no additional index migration was justified by this evidence.

## Remaining measured limits

- Full 20,000-stay responses contain 15,851,153 bytes. Full month attendance responses contain 27,234,091 bytes; the final optimized query/API check still took 2,900.23 ms end to end through in-process injection.
- Full patient refreshes remain approximately 30.7 MB at this synthetic size. Existing shared streams poll every ten seconds while subscribed. Inference: repeatedly loading a complete collection retains a substantial bandwidth, parsing and cache-writing cost even with bounded requests and correct pagination.
- Patient substring search uses `%term%` across name, search key and registration number. Its observed 10,000-patient plan scans 9,999 nonmatching rows; ordinary B-tree indexes do not remove this scan. No extension or index was added for the observed roughly 20–45 ms request range.
- Node RSS at the end of the large stage was 728,158,208 bytes baseline and 762,519,552 bytes after. These are end samples, not peak measurements or a memory improvement claim.
- WAN/TLS transfer, Flutter rendering of this dataset, photos, sustained load, many simultaneous full collection clients, and production VPS capacity were not measured. Cursor traversal is not a database snapshot: new records inserted ahead of a traversal boundary appear on a subsequent refresh.

## Evidence

- `scale-baseline.json`: original 1k/10k results, plans and payload/query counts. Baseline run: 2/2 tests passed in 87.46 seconds.
- `scale-optimized.json` and `scale-optimized-tests.log`: 1k/10k post-change measurements plus cursor regressions. Run: 3/3 tests passed in 180.56 seconds.
- `scale-attendance.json` and `scale-attendance-tests.log`: 300k attendance before/after plans, native date ordering and patient filtering. Targeted run after the attendance change: 1 passed, 3 deliberately filtered out; 37.62 seconds.
- `scale-typecheck.log`: `tsc --noEmit` exit 0 after the final production change. Existing domain route tests also passed 5/5 after cursor changes.

Reproduce from `backend` with the exact guarded database environment, `RUN_SCALE_INTEGRATION=1`, `SCALE_PHASE=review`, and `vitest run tests/scalability.integration.test.ts --maxWorkers=1 --minWorkers=1`. Normal test runs skip this opt-in suite. The suite remains destructive only within the explicitly guarded synthetic database.

VERDICT: PASS
