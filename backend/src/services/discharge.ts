import type pg from 'pg';
import { httpError } from '../validation.js';
import { refreshRoomOccupancy } from '../db/occupancy.js';
import { projectBilling, persistBilling, stayCycle } from './billing.js';

/** Caller owns the transaction and patient lock. All completion APIs share it. */
export async function finalizeDischarge(client: pg.PoolClient, patient: any, checkout: Date) {
  if (!Number.isFinite(checkout.getTime()) || checkout < new Date(patient.admission_date)) throw httpError(400, 'Invalid actual checkout time');
  const cycle = String(new Date(patient.admission_date).getTime());
  const allStays = (await client.query('SELECT * FROM stays WHERE patient_id=$1 ORDER BY id', [patient.id])).rows;
  const stays = allStays.filter(s => s.status === 'active');
  const segments = stays.filter(s => stayCycle(s, patient) === cycle);
  if (!segments.length) throw httpError(409, 'Create or reconcile the current stay before discharge');
  if (segments.length !== stays.length) throw httpError(409, 'Reconcile stays from a different admission before discharge');
  const rooms = [...new Set(segments.map(s => s.room_id))].sort();
  for (const room of rooms) await client.query('SELECT id FROM rooms WHERE id=$1 FOR UPDATE', [room]);
  for (const stay of segments.filter(s => s.bed_id)) {
    const bed = (await client.query('SELECT current_patient_id,current_stay_id FROM room_beds WHERE id=$1 FOR UPDATE', [stay.bed_id])).rows[0];
    if (!bed || bed.current_patient_id !== patient.id || bed.current_stay_id !== stay.id) throw httpError(409, 'Bed assignment changed; reconcile the placement before discharge');
  }
  for (const stay of segments) await client.query("UPDATE stays SET status='completed',admission_date=LEAST(admission_date,$2),completed_at=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1", [stay.id, checkout]);
  // Entry-time transfer artifacts must fit the admin's checkout without moving cycle identity.
  for (const stay of allStays.filter(s => s.status === 'completed' && stayCycle(s, patient) === cycle)) {
    await client.query(`UPDATE stays SET completed_at=LEAST(completed_at,$2),
      admission_date=LEAST(admission_date,LEAST(completed_at,$2)),updated_at=CURRENT_TIMESTAMP
      WHERE id=$1 AND (completed_at IS DISTINCT FROM LEAST(completed_at,$2)
        OR admission_date>LEAST(completed_at,$2))`, [stay.id, checkout]);
  }
  const projection = await projectBilling(client, { ...patient, status: 'discharged', discharge_date: checkout }, { finalize: true, checkoutAt: checkout });
  const balance = projection.balances[cycle];
  if (projection.reconciliation.required) throw httpError(409, 'Reconcile receipt allocations, admission identities and invoice evidence before discharge');
  await client.query("UPDATE patients SET status='discharged',discharge_date=$2,exit_date=$2,room_id=NULL,room_number=NULL,floor=NULL,lobby=NULL,bed_ids='[]'::jsonb,bed_labels='[]'::jsonb WHERE id=$1", [patient.id, checkout]);
  projection.patient = { ...(await client.query('SELECT * FROM patients WHERE id=$1', [patient.id])).rows[0], financial_reconciliation: projection.patient.financial_reconciliation };
  for (const stay of segments) await client.query("UPDATE room_beds SET status='available',current_patient_id=NULL,current_stay_id=NULL,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND current_patient_id=$2 AND current_stay_id=$3", [stay.bed_id, patient.id, stay.id]);
  for (const room of rooms) await refreshRoomOccupancy(client, room);
  return persistBilling(client, projection);
}
