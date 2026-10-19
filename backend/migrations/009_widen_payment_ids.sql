-- Up Migration
-- Client-generated UPI payment IDs (e.g. `upi_<sha256>`) can reach 68+ characters.
-- Widen payment identifier column to VARCHAR(128) to match client identifiers.
ALTER TABLE payments ALTER COLUMN id TYPE VARCHAR(128);

-- Historical records include legitimate split payments sharing a single bank reference
-- as well as multiple payments with placeholder 'MANUAL_ONLINE' transaction IDs.
-- Replace strict unique constraint with a non-unique index to preserve ledger integrity.
DROP INDEX IF EXISTS ux_payment_transaction;
CREATE INDEX IF NOT EXISTS ix_payments_patient_transaction ON payments(patient_id, transaction_id);

-- Down Migration
-- Retain widened column and index to avoid rejecting or truncating imported payment identifiers.
SELECT 1;
