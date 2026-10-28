-- Up Migration
-- Preserve complete receipt history, including legacy voids. No existing
-- receipt or financial total is changed by this migration.
CREATE TABLE IF NOT EXISTS payment_change_history (
  id BIGSERIAL PRIMARY KEY,
  payment_id VARCHAR(128) NOT NULL,
  patient_id VARCHAR(64) NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
  previous_record JSONB,
  resulting_record JSONB,
  operator_uid TEXT NOT NULL,
  reason TEXT NOT NULL,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_payment_change_history_payment ON payment_change_history(payment_id,id);
CREATE OR REPLACE FUNCTION preserve_payment_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO payment_change_history(payment_id,patient_id,operation,previous_record,resulting_record,operator_uid,reason)
  VALUES(COALESCE(NEW.id,OLD.id),COALESCE(NEW.patient_id,OLD.patient_id),TG_OP,
    CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
    CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END,
    COALESCE(NULLIF(current_setting('app.operator_uid',true),''),current_user),
    COALESCE(NULLIF(current_setting('app.payment_reason',true),''),'database operation'));
  RETURN COALESCE(NEW,OLD);
END $$;
DROP TRIGGER IF EXISTS preserve_payment_change ON payments;
CREATE TRIGGER preserve_payment_change AFTER INSERT OR UPDATE OR DELETE ON payments
FOR EACH ROW EXECUTE FUNCTION preserve_payment_change();
CREATE OR REPLACE FUNCTION immutable_payment_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Payment change history is append-only'; END $$;
DROP TRIGGER IF EXISTS immutable_payment_history ON payment_change_history;
CREATE TRIGGER immutable_payment_history BEFORE UPDATE OR DELETE ON payment_change_history
FOR EACH ROW EXECUTE FUNCTION immutable_payment_history();

-- Down Migration
-- Deliberately retain recovery history on rollback. The audit data must be
-- exported and explicitly archived before an operator ever removes it.
SELECT 1;
