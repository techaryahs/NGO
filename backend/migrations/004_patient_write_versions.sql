-- Up Migration
ALTER TABLE patients ADD COLUMN version INTEGER NOT NULL DEFAULT 0;

-- Down Migration
ALTER TABLE patients DROP COLUMN version;
