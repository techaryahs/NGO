-- Run only on an explicitly approved, anonymized snapshot/test copy with a
-- SELECT-only role. Do not run this file against the VPS. It returns counts,
-- never patient identities, names, contact details, or payment details.
-- e012e955 (2026-10-19 16:08:48 +05:30) introduced:
--   duration_days := duration_days + additionalDays
--   total_extended_days := total_extended_days + additionalDays
-- Corrected local formula preserves duration_days and increments only the
-- extension field. Actual deployment/bug-window timestamps are not available.
-- Candidate counts are heuristics: edited dates and inclusive-duration records
-- require comparison with an earlier snapshot and extension request history.

BEGIN READ ONLY;

SELECT current_database() AS snapshot_database,
       current_setting('transaction_read_only') AS read_only;

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'stays'
  AND column_name IN ('admission_date', 'duration_days',
      'expected_discharge_date', 'expiry_date', 'total_extended_days',
      'extensions', 'created_at', 'updated_at')
ORDER BY ordinal_position;

-- AUDIT_COUNTS_BEGIN
WITH candidates AS (
  SELECT duration_days, total_extended_days,
         (expected_discharge_date AT TIME ZONE 'Asia/Kolkata')::date
           - (admission_date AT TIME ZONE 'Asia/Kolkata')::date AS calendar_span,
         COALESCE((SELECT SUM((entry->>'additionalDays')::bigint)
           FROM jsonb_array_elements(CASE WHEN jsonb_typeof(extensions) = 'array'
             THEN extensions ELSE '[]'::jsonb END) entry
           WHERE entry->>'additionalDays' ~ '^[0-9]{1,9}$'), 0) AS entry_days
  FROM stays
)
SELECT COUNT(*)::int AS stays_examined,
       COUNT(*) FILTER (WHERE total_extended_days > 0)::int AS extended_stays,
       COUNT(*) FILTER (WHERE total_extended_days > 0
         AND duration_days = calendar_span)::int AS possible_double_count,
       COUNT(*) FILTER (WHERE total_extended_days > 0
         AND duration_days + total_extended_days = calendar_span)::int AS consistent_separate_duration,
       COUNT(*) FILTER (WHERE total_extended_days > 0
         AND duration_days <> calendar_span
         AND duration_days + total_extended_days <> calendar_span)::int AS date_formula_requires_review,
       COUNT(*) FILTER (WHERE total_extended_days <> entry_days)::int AS extension_ledger_mismatch
FROM candidates;
-- AUDIT_COUNTS_END

ROLLBACK;
