-- Up Migration
-- An upgrade migration: never edit/replay 001 on initialized installations.
ALTER TABLE stays DROP CONSTRAINT stays_patient_id_fkey;
ALTER TABLE stays ADD CONSTRAINT stays_patient_id_fkey FOREIGN KEY(patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
ALTER TABLE stays DROP CONSTRAINT stays_bed_id_fkey;
ALTER TABLE stays ADD CONSTRAINT stays_bed_id_fkey FOREIGN KEY(bed_id) REFERENCES room_beds(id) ON DELETE RESTRICT;
ALTER TABLE payments DROP CONSTRAINT payments_patient_id_fkey;
ALTER TABLE payments ADD CONSTRAINT payments_patient_id_fkey FOREIGN KEY(patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
ALTER TABLE attendance_records DROP CONSTRAINT attendance_records_patient_id_fkey;
ALTER TABLE attendance_records ADD CONSTRAINT attendance_records_patient_id_fkey FOREIGN KEY(patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
ALTER TABLE patient_attendants DROP CONSTRAINT patient_attendants_patient_id_fkey;
ALTER TABLE patient_attendants ADD CONSTRAINT patient_attendants_patient_id_fkey FOREIGN KEY(patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
ALTER TABLE patient_photos ALTER COLUMN version TYPE BIGINT;
ALTER TABLE room_beds ADD CONSTRAINT room_beds_patient_fkey FOREIGN KEY(current_patient_id) REFERENCES patients(id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE room_beds ADD CONSTRAINT room_beds_stay_fkey FOREIGN KEY(current_stay_id) REFERENCES stays(id) ON DELETE RESTRICT NOT VALID;
CREATE UNIQUE INDEX ux_room_bed_label ON room_beds(room_id, bed_label);
CREATE UNIQUE INDEX ux_bed_room ON room_beds(id, room_id);
ALTER TABLE stays ADD CONSTRAINT stays_bed_room_fkey FOREIGN KEY(bed_id, room_id) REFERENCES room_beds(id, room_id) NOT VALID;
CREATE UNIQUE INDEX ux_stays_active_bed ON stays(bed_id) WHERE status = 'active' AND bed_id IS NOT NULL;
CREATE UNIQUE INDEX ux_attendance_identity ON attendance_records(kind, attendance_date, patient_id);
CREATE UNIQUE INDEX ux_payment_transaction ON payments(patient_id, transaction_id) WHERE transaction_id IS NOT NULL AND transaction_id <> '';

-- Down Migration
DROP INDEX IF EXISTS ux_payment_transaction;
DROP INDEX ux_attendance_identity;
DROP INDEX ux_stays_active_bed;
ALTER TABLE stays DROP CONSTRAINT stays_bed_room_fkey;
DROP INDEX ux_bed_room;
DROP INDEX ux_room_bed_label;
ALTER TABLE room_beds DROP CONSTRAINT room_beds_stay_fkey;
ALTER TABLE room_beds DROP CONSTRAINT room_beds_patient_fkey;
-- Keep BIGINT when reversing: narrowing can lose valid photo versions.
ALTER TABLE patient_attendants DROP CONSTRAINT patient_attendants_patient_id_fkey;
ALTER TABLE patient_attendants ADD CONSTRAINT patient_attendants_patient_id_fkey FOREIGN KEY(patient_id) REFERENCES patients(id) ON DELETE CASCADE;
ALTER TABLE attendance_records DROP CONSTRAINT attendance_records_patient_id_fkey;
ALTER TABLE attendance_records ADD CONSTRAINT attendance_records_patient_id_fkey FOREIGN KEY(patient_id) REFERENCES patients(id) ON DELETE CASCADE;
ALTER TABLE payments DROP CONSTRAINT payments_patient_id_fkey;
ALTER TABLE payments ADD CONSTRAINT payments_patient_id_fkey FOREIGN KEY(patient_id) REFERENCES patients(id) ON DELETE CASCADE;
ALTER TABLE stays DROP CONSTRAINT stays_patient_id_fkey;
ALTER TABLE stays ADD CONSTRAINT stays_patient_id_fkey FOREIGN KEY(patient_id) REFERENCES patients(id) ON DELETE CASCADE;
ALTER TABLE stays DROP CONSTRAINT stays_bed_id_fkey;
ALTER TABLE stays ADD CONSTRAINT stays_bed_id_fkey FOREIGN KEY(bed_id) REFERENCES room_beds(id) ON DELETE SET NULL;
