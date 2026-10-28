import type { FastifyInstance } from 'fastify';
import { getClient } from '../db/index.js';
import { authenticate } from '../middleware/auth.js';
import { httpError } from '../validation.js';
import { formatPatient } from './patients.js';
import { formatPayment } from './payments.js';
import { formatStay } from './stays.js';
import { projectBilling, persistBilling } from '../services/billing.js';
import { finalizeDischarge } from '../services/discharge.js';
import { z } from 'zod';
export async function settlementRoutes(app: FastifyInstance) {
    app.addHook('preHandler', authenticate);
    const snapshot = async (client: any, projection: any) => ({
        patient: formatPatient(projection.patient, (await client.query('SELECT * FROM patient_attendants WHERE patient_id=$1', [projection.patient.id])).rows, projection.receipts.map(formatPayment)),
        stays: projection.stays.map(formatStay),
        reconciliation: projection.reconciliation,
    });
    const perform = async (request: any, reply: any, mode: 'read' | 'recalculate' | 'discharge') => {
        const client = await getClient();
        try {
            await client.query('BEGIN');
            // All attendance, receipt and stay writes use this same per-patient lock.
            const patient = (await client.query('SELECT * FROM patients WHERE id=$1 FOR UPDATE', [request.params.id])).rows[0];
            if (!patient)
                throw httpError(404, 'Patient not found');
            const input = z.object({ checkoutAt: z.coerce.number().finite().refine(v => Number.isFinite(new Date(v).getTime()), 'Invalid checkout time').optional() }).safeParse(mode === 'read' ? request.query : request.body ?? {});
            if (!input.success) throw httpError(400, 'Invalid checkout time');
            const checkout = patient.status !== 'discharged' && (input.data.checkoutAt != null || mode === 'discharge')
                ? new Date(input.data.checkoutAt ?? Date.now()) : undefined;
            if (checkout && checkout < new Date(patient.admission_date)) throw httpError(400, 'Checkout cannot precede admission');
            let projection = await projectBilling(client, patient, { checkoutAt: checkout });
            if (mode === 'discharge' && patient.status !== 'discharged')
                projection = await finalizeDischarge(client, patient, checkout!);
            else if (mode === 'recalculate' && patient.status !== 'discharged')
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
