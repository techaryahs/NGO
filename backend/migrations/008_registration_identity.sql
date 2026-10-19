-- Up Migration
-- Preserve the original identity even after profile fields are edited.
ALTER TABLE patients ADD COLUMN registration_fingerprint TEXT;

-- Down Migration
ALTER TABLE patients DROP COLUMN registration_fingerprint;
