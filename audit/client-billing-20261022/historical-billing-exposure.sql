-- SELECT-only audit for a disposable database or explicitly approved anonymized
-- snapshot. Never run against the VPS or production. Aggregate candidates only;
-- a candidate is not proof of an incorrect historical bill. No record repair.
BEGIN READ ONLY;

SELECT current_database() AS database_name,
       current_setting('transaction_read_only') AS read_only;

-- CLIENT_BILLING_AUDIT_BEGIN
WITH duration_candidates AS (
  SELECT duration_days, total_extended_days,
    (expected_discharge_date AT TIME ZONE 'Asia/Kolkata')::date
      - (admission_date AT TIME ZONE 'Asia/Kolkata')::date AS calendar_span
  FROM stays
), duplicate_names AS (
  SELECT patient_id, name FROM patient_attendants
  GROUP BY patient_id, name HAVING COUNT(*) > 1
), finalized_segments AS (
  SELECT p.id, b.key AS cycle_id, b.value AS saved,
    COALESCE((SELECT SUM(s.total_cost) FROM stays s
      WHERE s.patient_id=p.id AND s.cycle_id=b.key AND s.status<>'cancelled'),0) AS stored_segments
  FROM patients p CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(p.admission_balances)='object'
    THEN p.admission_balances ELSE '{}'::jsonb END) b
  WHERE b.value->>'total' ~ '^[0-9]+([.][0-9]{1,2})?$'
    AND (p.status='discharged' OR b.key <> ((EXTRACT(EPOCH FROM p.admission_date)*1000)::bigint)::text)
)
SELECT (SELECT COUNT(*)::int FROM stays) AS stays_examined,
  (SELECT COUNT(*)::int FROM duration_candidates
    WHERE total_extended_days>0 AND duration_days=calendar_span) AS duration_double_count_candidates,
  (SELECT COUNT(*)::int FROM duplicate_names) AS duplicate_attendant_name_groups,
  (SELECT COUNT(*)::int FROM attendance_records WHERE kind='attendant_attendance'
    AND (payload ? 'attendantName' OR payload ? 'attendantId')) AS individual_attendant_payloads,
  (SELECT COUNT(*)::int FROM attendance_records WHERE kind='attendant_attendance'
    AND NOT (payload ? 'attendantName' OR payload ? 'attendantId')
    AND EXISTS(SELECT 1 FROM jsonb_each(CASE WHEN jsonb_typeof(payload)='object'
      THEN payload ELSE '{}'::jsonb END) e WHERE jsonb_typeof(e.value)='object')) AS nested_attendant_payloads,
  (SELECT COUNT(*)::int FROM patients WHERE status='discharged' AND discharge_date IS NULL) AS discharged_without_actual_timestamp,
  (SELECT COUNT(*)::int FROM patients WHERE status='discharged' AND discharge_date=exit_date) AS actual_equals_planned_candidates,
  (SELECT COUNT(*)::int FROM finalized_segments WHERE (saved->>'total')::numeric <> stored_segments) AS finalized_segment_summary_mismatch;
-- CLIENT_BILLING_AUDIT_END

ROLLBACK;
