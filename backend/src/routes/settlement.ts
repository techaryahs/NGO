import type { FastifyInstance } from 'fastify';
import { getClient } from '../db/index.js';
import { authenticate } from '../middleware/auth.js';
import { httpError } from '../validation.js';
import { formatPatient } from './patients.js';
import { formatPayment } from './payments.js';
import { formatStay } from './stays.js';
import { projectBilling, persistBilling, dayKey, stayCycle } from '../services/billing.js';
import { refreshRoomOccupancy } from '../db/occupancy.js';
export async function settlementRoutes(app: FastifyInstance) {
    app.addHook('preHandler', authenticate);
    const snapshot = async (client: any, projection: any) => ({
        patient: formatPatient(projection.patient, (await client.query('SELECT * FROM patient_attendants WHERE patient_id=$1', [projection.patient.id])).rows, projection.receipts.map(formatPayment)),
        stays: projection.stays.map(formatStay),
    });
    const perform = async (request: any, reply: any, mode: 'read' | 'recalculate' | 'discharge') => {
        const client = await getClient();
        try {
            await client.query('BEGIN');
            // All attendance, receipt and stay writes use this same per-patient lock.
            const patient = (await client.query('SELECT * FROM patients WHERE id=$1 FOR UPDATE', [request.params.id])).rows[0];
            if (!patient)
                throw httpError(404, 'Patient not found');
            let projection = await projectBilling(client, patient, { finalize: mode === 'recalculate' });
            if (mode === 'discharge' && patient.status !== 'discharged') {
                const cycle = String(new Date(patient.admission_date).getTime());
                const segments = projection.stays.filter(s => stayCycle(s, patient) === cycle && s.status === 'active');
                if (!patient.exit_date)
                    throw httpError(409, 'Set the planned exit date before discharging this patient');
                const exit = new Date(Math.min(new Date(patient.exit_date).getTime(), ...segments.map(s => new Date(s.expected_discharge_date).getTime())));
                // Calculate the final completed-stay invoice before any bed is released.
                const rooms = [...new Set(segments.map(s => s.room_id))].sort();
                for (const room of rooms)
                    await client.query('SELECT id FROM rooms WHERE id=$1 FOR UPDATE', [room]);
                for (const stay of segments.filter(s => s.bed_id)) {
                    const bed = (await client.query('SELECT current_patient_id,current_stay_id FROM room_beds WHERE id=$1 FOR UPDATE', [stay.bed_id])).rows[0];
                    if (!bed || bed.current_patient_id !== patient.id || bed.current_stay_id !== stay.id)
                        throw httpError(409, 'Bed assignment changed; reconcile the placement before discharge');
                }
                // These updates are rolled back if attendance or settlement validation fails.
                for (const s of segments)
                    await client.query("UPDATE stays SET status='completed',completed_at=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1", [s.id, exit]);
                const finalPatient = { ...patient, status: 'discharged', exit_date: exit, discharge_date: exit };
                projection = await projectBilling(client, finalPatient, { finalize: true });
                const start = dayKey(patient.registration_date ?? patient.admission_date);
                const end = dayKey(exit);
                // Every included calendar day, including checkout, needs an explicit mark.
                let missing = 0;
                for (let d = start; d <= end; d = new Date(Date.parse(d + 'T00:00:00Z') + 86400000).toISOString().slice(0, 10))
                    if (!['Present', 'Absent'].includes(projection.attendance.get(d) ?? ''))
                        missing++;
                if (missing)
                    throw httpError(409, `Mark ${missing} patient attendance day(s) before discharge`);
                const balance = projection.balances[cycle];
                if (balance.due > 0 || balance.refundDue > 0)
                    throw httpError(409, `Final settlement requires payment ${balance.due.toFixed(2)} and refund ${balance.refundDue.toFixed(2)}`);
                await client.query("UPDATE patients SET status='discharged',exit_date=$2,discharge_date=$2,room_id=NULL,room_number=NULL,bed_ids='[]'::jsonb,bed_labels='[]'::jsonb WHERE id=$1", [patient.id, exit]);
                projection.patient = (await client.query('SELECT * FROM patients WHERE id=$1', [patient.id])).rows[0];
                for (const s of segments)
                    await client.query("UPDATE room_beds SET status='available',current_patient_id=NULL,current_stay_id=NULL,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND current_patient_id=$2 AND current_stay_id=$3", [s.bed_id, patient.id, s.id]);
                for (const room of rooms)
                    await refreshRoomOccupancy(client, room);
            }
            if (mode !== 'read' && !(mode === 'discharge' && patient.status === 'discharged'))
                await persistBilling(client, projection);
            const result = await snapshot(client, projection);
            await client.query('COMMIT');
            return reply.send(result);
        }
        catch (error) {
            await client.query('ROLLBACK');
            throw error;
        }
        finally {
            client.release();
        }
    };
    app.get('/patients/:id/financials', (r, p) => perform(r, p, 'read'));
    app.post('/patients/:id/recalculate-billing', (r, p) => perform(r, p, 'recalculate'));
    app.post('/patients/:id/discharge', (r, p) => perform(r, p, 'discharge'));
}
