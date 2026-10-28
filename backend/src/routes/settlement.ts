import type { FastifyInstance } from 'fastify';
import { getClient } from '../db/index.js';
import { authenticate, requireRoles } from '../middleware/auth.js';
import { httpError } from '../validation.js';
import { formatPatient } from './patients.js';
import { formatPayment } from './payments.js';
import { formatStay } from './stays.js';
import { projectBilling, persistBilling, stayCycle } from '../services/billing.js';
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
            let projection = await projectBilling(client, patient, { checkoutAt: checkout, includeDayCharges: mode === 'read' });
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
    app.post('/patients/:id/billing-corrections', { preHandler: requireRoles(['admin']) }, async (request: any, reply) => {
        const input = z.object({ reason: z.string().trim().min(1).max(500),
            dates: z.array(z.object({ day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), stayId: z.string().min(1).max(128), amount: z.number().positive() })).min(1).max(3650),
        }).safeParse(request.body);
        if (!input.success || new Set(input.data?.dates.map(d => d.day)).size !== input.data?.dates.length)
            throw httpError(400, 'Select distinct billable dates and provide a reason');
        const client = await getClient();
        try {
            await client.query('BEGIN');
            const patient = (await client.query('SELECT * FROM patients WHERE id=$1 FOR UPDATE', [request.params.id])).rows[0];
            if (!patient) throw httpError(404, 'Patient not found');
            if (!['active', 'paid'].includes(String(patient.status).toLowerCase()))
                throw httpError(409, 'Billing corrections are only available for active admissions');
            const cycle = String(new Date(patient.admission_date).getTime());
            const before = await projectBilling(client, patient, { includeDayCharges: true });
            if (!before.stays.some(s => s.status === 'active' && stayCycle(s, patient) === cycle))
                throw httpError(409, 'Verify the active admission and placement before correcting charges');
            const balance = before.balances[cycle];
            if (!balance || balance.reconciliationRequired) throw httpError(409, 'Resolve this admission’s financial and identity review before correcting charges');
            const available = balance.dayCharges as { day: string; stayId: string; amount: number; excluded: boolean; eligible: boolean }[];
            if (!available) throw httpError(409, 'This admission does not have an editable daily bill');
            for (const selected of input.data.dates) {
                const row = available.find(d => d.day === selected.day && d.stayId === selected.stayId);
                if (!row || !row.eligible || row.excluded || Math.round(row.amount * 100) !== Math.round(selected.amount * 100))
                    throw httpError(409, 'A selected date is unavailable or its charge changed. Refresh the bill.');
            }
            for (const row of input.data.dates)
                await client.query('INSERT INTO billing_corrections(patient_id,cycle_id,stay_id,billable_date,amount,reason,operator_uid) VALUES($1,$2,$3,$4,$5,$6,$7)',
                    [patient.id, cycle, row.stayId, row.day, available.find(d => d.day === row.day)!.amount, input.data.reason, request.user.id]);
            const updated = await persistBilling(client, await projectBilling(client, patient));
            const result = await snapshot(client, updated);
            await client.query('COMMIT');
            return reply.status(201).send(result);
        } catch (error) { await client.query('ROLLBACK'); throw error; }
        finally { client.release(); }
    });
    app.get('/patients/:id/financials', (r, p) => perform(r, p, 'read'));
    app.post('/patients/:id/recalculate-billing', (r, p) => perform(r, p, 'recalculate'));
    app.post('/patients/:id/discharge', (r, p) => perform(r, p, 'discharge'));
}
