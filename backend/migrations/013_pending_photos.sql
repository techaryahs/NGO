-- Up Migration
CREATE TABLE IF NOT EXISTS pending_photos (
    photo_ref VARCHAR(255) PRIMARY KEY,
    patient_id VARCHAR(64) NOT NULL,
    kind VARCHAR(32) NOT NULL,
    content_type VARCHAR(64) NOT NULL,
    data TEXT NOT NULL,
    version BIGINT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_pending_photos_patient_id ON pending_photos(patient_id);
CREATE INDEX IF NOT EXISTS ix_pending_photos_created_at ON pending_photos(created_at);

-- Down Migration
DROP TABLE IF EXISTS pending_photos CASCADE;
