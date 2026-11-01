import { getClient, query } from '../db/index.js';
import { stayCycle } from './billing.js';

type RepairLogger = {
  info: (data: any, message: string) => void;
  warn: (data: any, message: string) => void;
  error: (data: any, message: string) => void;
};

function substantiveBalance(balance: any): boolean {
  // Preserve malformed entries rather than treating uncertain history as empty.
  if (!balance || typeof balance !== 'object' || Array.isArray(balance)) return true;
  return ['total', 'paid', 'netPaid', 'refunded', 'due', 'refundDue'].some(key => Number(balance[key] ?? 0) !== 0) ||
    balance.finalized === true ||
    ['segmentDays', 'segmentCharges', 'pendingAttendance'].some(key => Object.keys(balance[key] ?? {}).length > 0) ||
    balance.checkoutAt != null || balance.checkoutAdjustment != null;
}

export type AdmissionConvergenceResult =
  | { outcome: 'converged'; fromCycle: string; toCycle: string; replacedEmptyTargetBalance: boolean }
  | { outcome: 'already-coherent' }
  | { outcome: 'skipped'; reason: string; fromCycle: string; toCycle: string;
      target?: { stay: boolean; payments: number; balance: boolean; amount: unknown } };

/** Caller owns the transaction. Lock order: patient, stays, payments. */
export async function convergeAdmissionCycle(
  client: Awaited<ReturnType<typeof getClient>>, patientId: string, log: RepairLogger,
): Promise<AdmissionConvergenceResult> {
  const patient = (await client.query('SELECT * FROM patients WHERE id=$1 FOR UPDATE', [patientId])).rows[0];
  if (!patient) return { outcome: 'already-coherent' };
  const stays = (await client.query('SELECT * FROM stays WHERE patient_id=$1 ORDER BY admission_date,id FOR UPDATE', [patientId])).rows;
  const latest = (await client.query(`SELECT admission_date,cycle_id FROM stays WHERE patient_id=$1
    AND cycle_id=trunc(extract(epoch FROM admission_date)*1000)::bigint::text
    ORDER BY admission_date DESC,created_at DESC,id DESC LIMIT 1 FOR UPDATE`, [patientId])).rows[0];
  const newAdmission = new Date(patient.admission_date).getTime();
  const toCycle = String(newAdmission);
  if (!latest || latest.cycle_id === toCycle) return { outcome: 'already-coherent' };
  const fromCycle = latest.cycle_id as string;
  const oldAdmission = new Date(latest.admission_date).getTime();
  const cycleStays = stays.filter(s => stayCycle(s, patient) === fromCycle);
  const payments = (await client.query('SELECT * FROM payments WHERE patient_id=$1 FOR UPDATE', [patientId])).rows;
  const corrections = (await client.query('SELECT id FROM billing_corrections WHERE patient_id=$1 AND cycle_id=$2', [patientId, fromCycle])).rowCount;
  const hasTargetBalance = Object.hasOwn(patient.admission_balances ?? {}, toCycle);
  const substantiveTargetBalance = hasTargetBalance && substantiveBalance(patient.admission_balances[toCycle]);
  const target = { stay: stays.some(s => stayCycle(s, patient) === toCycle),
    payments: payments.filter(p => p.cycle_id === toCycle).length, balance: substantiveTargetBalance,
    amount: patient.admission_balances?.[toCycle]?.total ?? 0 };
  const reason = patient.admission_balances?.[fromCycle]?.finalized === true ? 'source_cycle_finalized'
    : target.stay || target.payments || target.balance ? 'target_cycle_exists'
    : corrections ? 'immutable_billing_corrections'
    : stays.some(s => stayCycle(s, patient).startsWith('unresolved-stay:')) || payments.some(p => p.cycle_id == null) ? 'unresolved_cycle_identity'
    : undefined;
  if (reason) {
    log.warn({ event: 'admission_repair_skipped', patientId, class: 'cycle_mismatch', fromCycle, toCycle, reason }, 'Admission repair skipped');
    return { outcome: 'skipped', reason, fromCycle, toCycle, ...(reason === 'target_cycle_exists' ? { target } : {}) };
  }
  for (const stay of cycleStays) {
    const snapshot = { ...stay.patient_snapshot, admissionDate: newAdmission };
    if (snapshot.billingSummary) snapshot.billingSummary = { ...snapshot.billingSummary, admissionId: toCycle,
      ...(Object.hasOwn(snapshot.billingSummary, 'cycleId') ? { cycleId: toCycle } : {}) };
    const billing = { ...stay.billing_summary, admissionId: toCycle, cycleId: toCycle };
    await client.query(`UPDATE stays SET admission_date=CASE WHEN admission_date=$2 THEN $3 ELSE admission_date END,
      cycle_id=$4,patient_snapshot=$5::jsonb,billing_summary=$6::jsonb,updated_at=CURRENT_TIMESTAMP WHERE id=$1`,
    [stay.id, new Date(oldAdmission), patient.admission_date, toCycle, JSON.stringify(snapshot), JSON.stringify(billing)]);
  }
  await client.query("SET LOCAL app.payment_reason='Admission date repaired from registration date'");
  await client.query('UPDATE payments SET cycle_id=$3 WHERE patient_id=$1 AND cycle_id=$2', [patientId, fromCycle, toCycle]);
  const balances = { ...patient.admission_balances };
  const replacedEmptyTargetBalance = hasTargetBalance && !substantiveTargetBalance && Object.hasOwn(balances, fromCycle);
  if (Object.hasOwn(balances, fromCycle)) {
    balances[toCycle] = { ...balances[fromCycle], cycleId: toCycle };
    delete balances[fromCycle];
  }
  await client.query('UPDATE patients SET admission_date=$2,admission_balances=$3::jsonb,version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=$1',
    [patientId, patient.admission_date, JSON.stringify(balances)]);
  log.info({ event: 'admission_repaired', patientId, class: 'cycle_mismatch',
    ...(replacedEmptyTargetBalance ? { replacedEmptyTargetBalance: true } : {}), fromCycle, toCycle, oldAdmission, newAdmission }, 'Admission repaired');
  return { outcome: 'converged', fromCycle, toCycle, replacedEmptyTargetBalance };
}

/** Repair identities only: never recalculate charges or change transfer dates. */
export async function repairAdmissions(log: RepairLogger) {
  const summary = { repaired: 0, skipped: 0, failed: 0 };
  const cycleMismatch = { repaired: 0, skipped: 0, failed: 0 };
  let candidates: { id: string }[];
  try {
    candidates = (await query<{ id: string }>(`SELECT p.id FROM patients p
      LEFT JOIN LATERAL (SELECT admission_date,cycle_id FROM stays WHERE patient_id=p.id
        AND cycle_id=trunc(extract(epoch FROM admission_date)*1000)::bigint::text
        ORDER BY admission_date DESC,created_at DESC,id DESC LIMIT 1) latest ON true
      WHERE (p.status='active' AND p.admission_date > p.registration_date)
        OR (latest.cycle_id=trunc(extract(epoch FROM latest.admission_date)*1000)::bigint::text
          AND latest.cycle_id<>trunc(extract(epoch FROM p.admission_date)*1000)::bigint::text)
      ORDER BY p.id`)).rows;
  } catch (err) {
    summary.failed++;
    log.error({ event: 'admission_repair_failed', err }, 'Admission repair run failed');
    log.info({ event: 'admission_repair_summary', ...summary, cycleMismatch }, 'Admission repair run complete');
    return summary;
  }
  // Each class locks and reads afresh; class 2 observes class 1's committed result.
  for (const { id, mismatch } of candidates.flatMap(({ id }) => [
    { id, mismatch: false }, { id, mismatch: true },
  ])) {
    const context = mismatch ? { class: 'cycle_mismatch' } : {};
    let client: Awaited<ReturnType<typeof getClient>>;
    try { client = await getClient(); }
    catch (err) {
      summary.failed++;
      if (mismatch) cycleMismatch.failed++;
      log.error({ event: 'admission_repair_failed', patientId: id, ...context, err }, 'Admission repair failed');
      continue;
    }
    try {
      await client.query('BEGIN');
      if (mismatch) {
        const messages: (() => void)[] = [];
        const result = await convergeAdmissionCycle(client, id, {
          info: (data, message) => { messages.push(() => log.info(data, message)); },
          warn: (data, message) => { messages.push(() => log.warn(data, message)); },
          error: (data, message) => { messages.push(() => log.error(data, message)); },
        });
        if (result.outcome === 'converged') {
          await client.query('COMMIT');
          summary.repaired++;
          cycleMismatch.repaired++;
        } else {
          await client.query('ROLLBACK');
          if (result.outcome === 'skipped') { summary.skipped++; cycleMismatch.skipped++; }
        }
        for (const emit of messages) emit();
        continue;
      }
      const patient = (await client.query("SELECT * FROM patients WHERE id=$1 FOR UPDATE", [id])).rows[0];
      if (!patient || !mismatch && (patient.status !== 'active' || !patient.registration_date ||
          new Date(patient.admission_date) <= new Date(patient.registration_date))) {
        await client.query('ROLLBACK');
        continue;
      }
      const stays = (await client.query('SELECT * FROM stays WHERE patient_id=$1 ORDER BY admission_date,id FOR UPDATE', [id])).rows;
      const latest = mismatch ? (await client.query(`SELECT admission_date,cycle_id FROM stays WHERE patient_id=$1
        AND cycle_id=trunc(extract(epoch FROM admission_date)*1000)::bigint::text
        ORDER BY admission_date DESC,created_at DESC,id DESC LIMIT 1 FOR UPDATE`, [id])).rows[0] : undefined;
      if (mismatch && (!latest || latest.cycle_id !== String(new Date(latest.admission_date).getTime()) ||
          latest.cycle_id === String(new Date(patient.admission_date).getTime()))) {
        await client.query('ROLLBACK');
        continue;
      }
      const oldAdmission = new Date(mismatch ? latest!.admission_date : patient.admission_date).getTime();
      const registration = new Date(mismatch ? patient.admission_date : patient.registration_date);
      const newAdmission = registration.getTime();
      const oldCycle = String(oldAdmission), newCycle = String(newAdmission);
      const cycleStays = stays.filter(s => stayCycle(s, patient) === oldCycle);
      const anchor = cycleStays.find(s => s.completed_at == null && s.status === 'active');
      const payments = (await client.query('SELECT * FROM payments WHERE patient_id=$1 FOR UPDATE', [id])).rows;
      const corrections = (await client.query('SELECT id FROM billing_corrections WHERE patient_id=$1 AND cycle_id=$2', [id, oldCycle])).rowCount;
      const hasTargetBalance = Object.hasOwn(patient.admission_balances ?? {}, newCycle);
      const substantiveTargetBalance = hasTargetBalance && substantiveBalance(patient.admission_balances[newCycle]);
      const reason = !mismatch && (!anchor || new Date(anchor.admission_date) <= registration) ? 'anchor_not_after_registration'
        : stays.some(s => stayCycle(s, patient) === newCycle) || substantiveTargetBalance || payments.some(p => p.cycle_id === newCycle) ? 'target_cycle_exists'
        : corrections ? 'immutable_billing_corrections'
        : stays.some(s => stayCycle(s, patient).startsWith('unresolved-stay:')) || payments.some(p => p.cycle_id == null) ? 'unresolved_cycle_identity'
        : undefined;
      if (reason) {
        await client.query('ROLLBACK');
        summary.skipped++;
        if (mismatch) cycleMismatch.skipped++;
        log.warn({ event: 'admission_repair_skipped', patientId: id, ...context,
          ...(mismatch ? { fromCycle: oldCycle, toCycle: newCycle } : {}), reason }, 'Admission repair skipped');
        continue;
      }
      for (const stay of cycleStays) {
        const snapshot = { ...stay.patient_snapshot, admissionDate: newAdmission };
        if (snapshot.billingSummary) snapshot.billingSummary = { ...snapshot.billingSummary, admissionId: newCycle,
          ...(Object.hasOwn(snapshot.billingSummary, 'cycleId') ? { cycleId: newCycle } : {}) };
        const billing = { ...stay.billing_summary, admissionId: newCycle, cycleId: newCycle };
        await client.query(`UPDATE stays SET admission_date=CASE WHEN admission_date=$2 THEN $3 ELSE admission_date END,
          cycle_id=$4,patient_snapshot=$5::jsonb,billing_summary=$6::jsonb,updated_at=CURRENT_TIMESTAMP WHERE id=$1`,
        [stay.id, new Date(oldAdmission), registration, newCycle, JSON.stringify(snapshot), JSON.stringify(billing)]);
      }
      // Explicit receipt owners move with their cycle, including refunds.
      await client.query("SET LOCAL app.payment_reason='Admission date repaired from registration date'");
      await client.query('UPDATE payments SET cycle_id=$3 WHERE patient_id=$1 AND cycle_id=$2', [id, oldCycle, newCycle]);
      const balances = { ...patient.admission_balances };
      const replacedEmptyTargetBalance = hasTargetBalance && !substantiveTargetBalance && Object.hasOwn(balances, oldCycle);
      if (Object.hasOwn(balances, oldCycle)) {
        balances[newCycle] = { ...balances[oldCycle], cycleId: newCycle };
        delete balances[oldCycle];
      }
      await client.query('UPDATE patients SET admission_date=$2,admission_balances=$3::jsonb,version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=$1',
        [id, registration, JSON.stringify(balances)]);
      await client.query('COMMIT');
      summary.repaired++;
      if (mismatch) cycleMismatch.repaired++;
      log.info({ event: 'admission_repaired', patientId: id, ...context,
        ...(replacedEmptyTargetBalance ? { replacedEmptyTargetBalance: true } : {}),
        ...(mismatch ? { fromCycle: oldCycle, toCycle: newCycle } : { registrationDate: registration.toISOString() }),
        oldAdmission, newAdmission }, 'Admission repaired');
    } catch (error) {
      await client.query('ROLLBACK');
      summary.failed++;
      if (mismatch) cycleMismatch.failed++;
      log.error({ event: 'admission_repair_failed', patientId: id, ...context, err: error }, 'Admission repair failed');
    } finally { client.release(); }
  }
  log.info({ event: 'admission_repair_summary', ...summary, cycleMismatch }, 'Admission repair run complete');
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
