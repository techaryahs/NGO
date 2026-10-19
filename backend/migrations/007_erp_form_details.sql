-- Up Migration
-- Preserve validated fields used by the existing Flutter ERP forms without
-- changing financial columns or rewriting historical records.
ALTER TABLE vendors ADD COLUMN IF NOT EXISTS details JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS details JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE expense_entries ADD COLUMN IF NOT EXISTS details JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE salaries ADD COLUMN IF NOT EXISTS details JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE sponsorships ADD COLUMN IF NOT EXISTS details JSONB NOT NULL DEFAULT '{}'::jsonb;
-- The salary form records an employee name without requiring an application
-- account. Preserve supplied identities, and represent no association as NULL.
ALTER TABLE salaries ALTER COLUMN staff_id DROP NOT NULL;
ALTER TABLE salaries ALTER COLUMN staff_id TYPE VARCHAR(128);

-- Down Migration
-- Retain metadata and optional account relationships to avoid losing form data.
SELECT 1;
