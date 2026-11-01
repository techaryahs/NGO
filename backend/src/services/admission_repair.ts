import { getClient, query } from '../db/index.js';
import { stayCycle } from './billing.js';

type RepairLogger = {
  info: (data: any, message: string) => void;
  warn: (data: any, message: string) => void;
  error: (data: any, message: string) => void;
};

/** Repair identities only: never recalculate charges or change transfer dates. */
export async function repairAdmissions(log: RepairLogger) {
  const summary = { repaired: 0, skipped: 0, failed: 0 };
  let candidates: { id: string }[];
  try {
    candidates = (await query<{ id: string }>("SELECT id FROM patients WHERE status='active' AND admission_date > registration_date ORDER BY id")).rows;
  } catch (err) {
    summary.failed++;
    log.error({ event: 'admission_repair_failed', err }, 'Admission repair run failed');
    log.info({ event: 'admission_repair_summary', ...summary }, 'Admission repair run complete');
    return summary;
  }
  for (const { id } of candidates) {
    let client: Awaited<ReturnType<typeof getClient>>;
    try { client = await getClient(); }
    catch (err) {
      summary.failed++;
      log.error({ event: 'admission_repair_failed', patientId: id, err }, 'Admission repair failed');
      continue;
    }
    try {
      await client.query('BEGIN');
      const patient = (await client.query("SELECT * FROM patients WHERE id=$1 FOR UPDATE", [id])).rows[0];
      if (!patient || patient.status !== 'active' || !patient.registration_date ||
          new Date(patient.admission_date) <= new Date(patient.registration_date)) {
        await client.query('ROLLBACK');
        continue;
      }
      const oldAdmission = new Date(patient.admission_date).getTime();
      const registration = new Date(patient.registration_date);
      const newAdmission = registration.getTime();
      const oldCycle = String(oldAdmission), newCycle = String(newAdmission);
      const stays = (await client.query('SELECT * FROM stays WHERE patient_id=$1 ORDER BY admission_date,id FOR UPDATE', [id])).rows;
      const cycleStays = stays.filter(s => stayCycle(s, patient) === oldCycle);
      const anchor = cycleStays.find(s => s.completed_at == null && s.status === 'active');
      const payments = (await client.query('SELECT * FROM payments WHERE patient_id=$1 FOR UPDATE', [id])).rows;
      const corrections = (await client.query('SELECT id FROM billing_corrections WHERE patient_id=$1 AND cycle_id=$2', [id, oldCycle])).rowCount;
      const reason = !anchor || new Date(anchor.admission_date) <= registration ? 'anchor_not_after_registration'
        : stays.some(s => stayCycle(s, patient) === newCycle) || Object.hasOwn(patient.admission_balances ?? {}, newCycle) || payments.some(p => p.cycle_id === newCycle) ? 'target_cycle_exists'
        : corrections ? 'immutable_billing_corrections'
        : stays.some(s => stayCycle(s, patient).startsWith('unresolved-stay:')) || payments.some(p => p.cycle_id == null) ? 'unresolved_cycle_identity'
        : undefined;
      if (reason) {
        await client.query('ROLLBACK');
        summary.skipped++;
        log.warn({ event: 'admission_repair_skipped', patientId: id, reason }, 'Admission repair skipped');
        continue;
      }
      for (const stay of cycleStays) {
        const snapshot = { ...stay.patient_snapshot, admissionDate: newAdmission };
        if (snapshot.billingSummary) snapshot.billingSummary = { ...snapshot.billingSummary, admissionId: newCycle,
          ...(Object.hasOwn(snapshot.billingSummary, 'cycleId') ? { cycleId: newCycle } : {}) };
        const billing = { ...stay.billing_summary, admissionId: newCycle, cycleId: newCycle };
        await client.query(`UPDATE stays SET admission_date=CASE WHEN admission_date=$2 THEN $3 ELSE admission_date END,
          cycle_id=$4,patient_snapshot=$5::jsonb,billing_summary=$6::jsonb,updated_at=CURRENT_TIMESTAMP WHERE id=$1`,
        [stay.id, patient.admission_date, registration, newCycle, JSON.stringify(snapshot), JSON.stringify(billing)]);
      }
      // Explicit receipt owners move with their cycle, including refunds.
      await client.query("SET LOCAL app.payment_reason='Admission date repaired from registration date'");
      await client.query('UPDATE payments SET cycle_id=$3 WHERE patient_id=$1 AND cycle_id=$2', [id, oldCycle, newCycle]);
      const balances = { ...patient.admission_balances };
      if (Object.hasOwn(balances, oldCycle)) {
        balances[newCycle] = { ...balances[oldCycle], cycleId: newCycle };
        delete balances[oldCycle];
      }
      await client.query('UPDATE patients SET admission_date=$2,admission_balances=$3::jsonb,version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=$1',
        [id, registration, JSON.stringify(balances)]);
      await client.query('COMMIT');
      summary.repaired++;
      log.info({ event: 'admission_repaired', patientId: id, registrationDate: registration.toISOString(), oldAdmission, newAdmission }, 'Admission repaired');
    } catch (error) {
      await client.query('ROLLBACK');
      summary.failed++;
      log.error({ event: 'admission_repair_failed', patientId: id, err: error }, 'Admission repair failed');
    } finally { client.release(); }
  }
  log.info({ event: 'admission_repair_summary', ...summary }, 'Admission repair run complete');
  return summary;
}

export function startAdmissionRepair(log: RepairLogger) {
  let running: Promise<unknown> | undefined;
  const run = () => {
    if (!running) running = repairAdmissions(log)
      .catch(err => log.error({ event: 'admission_repair_failed', err }, 'Admission repair run failed'))
      .finally(() => { running = undefined; });
    return running;
  };
  const timer = setInterval(() => { void run(); }, 60 * 60 * 1000);
  timer.unref();
  log.info({ event: 'admission_repair_registered', intervalMs: 3600000, runOnStartup: true }, 'Admission repair job registered');
  void run();
  return async () => { clearInterval(timer); await running; };
}
