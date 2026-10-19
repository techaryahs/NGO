-- Review-only rehearsal for the one local synthetic patient observed on 2026-10-19.
-- This script intentionally ROLLS BACK. No payment, bill or balance is updated.
-- Export the 13 rows first. Close/reopen the corrected desktop app after an
-- explicitly approved cleanup so successful API range reads clear cached rows.
BEGIN;
DO $$
BEGIN
  IF current_database() <> 'ngo_db' THEN RAISE EXCEPTION 'Wrong local database'; END IF;
  IF NOT EXISTS (SELECT 1 FROM patients WHERE id='p_1792387833687528_306da8e79f748ffbc7e4006d' AND full_name='test')
    THEN RAISE EXCEPTION 'Synthetic patient identity changed; review again'; END IF;
END $$;
SELECT id FROM patients WHERE id='p_1792387833687528_306da8e79f748ffbc7e4006d' FOR UPDATE;
SELECT id,kind,attendance_date,payload FROM attendance_records
WHERE patient_id='p_1792387833687528_306da8e79f748ffbc7e4006d' ORDER BY kind,attendance_date;
DELETE FROM attendance_records
WHERE patient_id='p_1792387833687528_306da8e79f748ffbc7e4006d'
  AND kind='attendance'
  AND attendance_date BETWEEN DATE '2026-10-19' AND DATE '2026-10-31'
  AND payload->>'source'='automatic_registration_period'
  AND payload->>'status'='Present'
RETURNING id,attendance_date,payload;
-- Invalidate calculations begun before the explicitly reconciled marks.
UPDATE patients SET version=version+1,updated_at=CURRENT_TIMESTAMP
WHERE id='p_1792387833687528_306da8e79f748ffbc7e4006d';
ROLLBACK;
-- Replace ROLLBACK with COMMIT only after reviewing the exported rows and
-- explicitly approving this patient-specific synthetic cleanup. Financial
-- reconciliation is a separate review; this script never recalculates balances.
