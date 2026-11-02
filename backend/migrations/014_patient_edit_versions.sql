-- Up Migration
ALTER TABLE patients ADD COLUMN edit_version integer NOT NULL DEFAULT 0;
UPDATE patients SET edit_version = version;

-- Down Migration
ALTER TABLE patients DROP COLUMN edit_version;
