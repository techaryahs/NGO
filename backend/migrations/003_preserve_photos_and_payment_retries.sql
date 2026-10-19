-- Up Migration
ALTER TABLE patient_attendants ADD COLUMN IF NOT EXISTS photo_data_url TEXT;
-- Imported payments intentionally have no retry fingerprint: API retries must
-- never silently overwrite or reapply an imported financial transaction.
ALTER TABLE payments ADD COLUMN IF NOT EXISTS request_fingerprint TEXT;

-- Down Migration
ALTER TABLE payments DROP COLUMN request_fingerprint;
ALTER TABLE patient_attendants DROP COLUMN photo_data_url;
