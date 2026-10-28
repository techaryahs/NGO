-- Up Migration
CREATE TABLE IF NOT EXISTS billing_corrections (
  id BIGSERIAL PRIMARY KEY,
  patient_id VARCHAR(64) NOT NULL,
  cycle_id TEXT NOT NULL,
  stay_id VARCHAR(128) NOT NULL,
  billable_date DATE NOT NULL,
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  reason TEXT NOT NULL CHECK (length(trim(reason)) BETWEEN 1 AND 500),
  operator_uid TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(patient_id, cycle_id, billable_date)
);
CREATE INDEX IF NOT EXISTS ix_billing_corrections_patient ON billing_corrections(patient_id);
CREATE OR REPLACE FUNCTION immutable_billing_correction() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Billing correction history is append-only'; END $$;
DROP TRIGGER IF EXISTS immutable_billing_correction ON billing_corrections;
CREATE TRIGGER immutable_billing_correction BEFORE UPDATE OR DELETE ON billing_corrections
FOR EACH ROW EXECUTE FUNCTION immutable_billing_correction();
-- Down Migration
-- Financial correction history is retained for audit and recovery.
SELECT 1;
