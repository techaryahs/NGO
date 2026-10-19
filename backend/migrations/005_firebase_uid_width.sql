-- Up Migration
-- Firebase Authentication UIDs may contain up to 128 characters. Preserve the
-- complete verified identifier both on the account and on audit/creator fields.
ALTER TABLE users ALTER COLUMN id TYPE VARCHAR(128);
ALTER TABLE patients ALTER COLUMN created_by TYPE VARCHAR(128);
ALTER TABLE stays ALTER COLUMN created_by TYPE VARCHAR(128);
ALTER TABLE inventory_items ALTER COLUMN created_by TYPE VARCHAR(128);
ALTER TABLE inventory_items ALTER COLUMN updated_by TYPE VARCHAR(128);
ALTER TABLE purchases ALTER COLUMN created_by TYPE VARCHAR(128);
ALTER TABLE expense_entries ALTER COLUMN created_by TYPE VARCHAR(128);

-- Down Migration
-- Deliberately retain widened columns: narrowing would reject or truncate valid
-- Firebase identities and their historical audit trail after a successful import.
SELECT 1;
