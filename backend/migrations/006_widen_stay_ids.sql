-- Up Migration
-- Deterministic stay IDs composed from client-generated patient IDs and bed/lobby
-- identifiers (e.g. `stay_<patientId>_<bedId>`) can reach 71+ characters.
-- Widen stay identifier columns to VARCHAR(128) to match the composite contract.
ALTER TABLE stays ALTER COLUMN id TYPE VARCHAR(128);
ALTER TABLE room_beds ALTER COLUMN current_stay_id TYPE VARCHAR(128);

-- Down Migration
-- Deliberately retain widened columns so active composite stay identifiers
-- are not truncated or rejected.
SELECT 1;
