-- Up Migration
ALTER TABLE billing_corrections ADD COLUMN IF NOT EXISTS reverted_at TIMESTAMPTZ;
ALTER TABLE billing_corrections ADD COLUMN IF NOT EXISTS reverted_by TEXT;
ALTER TABLE billing_corrections ADD COLUMN IF NOT EXISTS revert_reason TEXT;
ALTER TABLE billing_corrections DROP CONSTRAINT IF EXISTS billing_corrections_patient_id_cycle_id_billable_date_key;
CREATE UNIQUE INDEX IF NOT EXISTS ux_active_billing_correction_date
  ON billing_corrections(patient_id, cycle_id, billable_date) WHERE reverted_at IS NULL;
CREATE OR REPLACE FUNCTION immutable_billing_correction() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' OR OLD.reverted_at IS NOT NULL OR NEW.reverted_at IS NULL
    OR NEW.reverted_by IS NULL OR length(trim(NEW.reverted_by)) = 0
    OR NEW.revert_reason IS NULL OR length(trim(NEW.revert_reason)) NOT BETWEEN 1 AND 500
    OR (to_jsonb(NEW) - ARRAY['reverted_at','reverted_by','revert_reason']) IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['reverted_at','reverted_by','revert_reason']) THEN
    RAISE EXCEPTION 'Billing correction history permits only an audited reversal';
  END IF;
  RETURN NEW;
END $$;
-- Down Migration
-- Preserve financial history and reversals on rollback.
SELECT 1;
