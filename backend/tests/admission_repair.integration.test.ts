import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import * as db from '../src/db/index.js';
import { runMigrations } from '../src/db/migrate.js';
import { repairAdmissions } from '../src/services/admission_repair.js';

describe.skipIf(process.env.RUN_PG_INTEGRATION !== '1')('PostgreSQL admission repair cycle mismatch', () => {
  const older = Date.parse('2026-09-01');
  const target = Date.parse('2026-10-01');
  const wrong = Date.parse('2026-11-02');
  const log = () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() });
  const counters = (logger: ReturnType<typeof log>) => logger.info.mock.calls
    .map(([data]) => data).find(data => data.event === 'admission_repair_summary').cycleMismatch;

  beforeAll(async () => {
    if (process.env.NODE_ENV !== 'test' || process.env.POSTGRES_HOST !== '127.0.0.1' ||
        process.env.POSTGRES_PORT !== '55439' || process.env.POSTGRES_DB !== 'ngo_audit_workflows') {
      throw new Error('Refusing non-disposable repair database');
    }
    const identity = (await db.query("SELECT current_database() AS db,inet_server_port() AS port,current_setting('server_version_num')::int AS version")).rows[0];
    expect(identity).toMatchObject({ db: 'ngo_audit_workflows', port: 55439 });
    expect(identity.version).toBeGreaterThanOrEqual(160000);
    expect(identity.version).toBeLessThan(170000);
    await runMigrations();
  }, 30000);
  beforeEach(async () => {
    await db.query('TRUNCATE patients,rooms,users,payment_change_history,billing_corrections CASCADE');
    await db.query("INSERT INTO rooms(id,room_number,room_type) VALUES('repair-room','R','general')");
  });
  afterAll(async () => { vi.restoreAllMocks(); await db.pool.end(); });

  async function addStay(id: string, admission: number, cycle: string | null, snapshot: any = {}) {
    await db.query(`INSERT INTO stays(id,patient_id,patient_name,room_id,room_number,room_type,
      admission_date,duration_days,expected_discharge_date,expiry_date,cycle_id,status,created_by,
      patient_snapshot,billing_summary,total_cost)
      VALUES($1,'repair-patient','Synthetic','repair-room','R','general',$2,7,$2,$2,$3,'completed','test',
        $4::jsonb,$5::jsonb,100)`, [id, new Date(admission), cycle,
      JSON.stringify({ admissionDate: Number(cycle), billingSummary: { admissionId: cycle, cycleId: cycle, total: 100 }, retained: true, ...snapshot }),
      JSON.stringify({ admissionId: cycle, cycleId: cycle, amount: 100 })]);
  }
  async function fixture(status = 'discharged') {
    await db.query(`INSERT INTO patients(id,full_name,date_of_birth,gender,contact_number,emergency_contact,
      emergency_contact_name,medical_condition,admission_date,registration_date,status,discharge_date,created_by,admission_balances)
      VALUES('repair-patient','Synthetic','1990-01-01','Other','0','0','Synthetic','Synthetic',$1,$2,$3,'2026-09-09','test',$4::jsonb)`,
    [new Date(target), new Date(status === 'active' ? target : older), status, JSON.stringify({
      [older]: { cycleId: String(older), total: 25 },
      [wrong]: { cycleId: String(wrong), total: 100, segmentCharges: { anchor: 100 } },
    })]);
    await addStay('older', older, String(older));
    await addStay('anchor', wrong, String(wrong));
  }
  async function state() {
    const result: Record<string, any[]> = {};
    for (const table of ['patients', 'stays', 'payments', 'billing_corrections', 'payment_change_history']) {
      const owner = table === 'patients' ? 'id' : 'patient_id';
      result[table] = (await db.query(`SELECT * FROM ${table} WHERE ${owner}='repair-patient' ORDER BY id`)).rows;
    }
    return result;
  }
  async function assertConverged(before: Awaited<ReturnType<typeof state>>) {
    const after = await state();
    expect(after.patients[0]).toMatchObject({ admission_date: new Date(target),
      registration_date: before.patients[0].registration_date, discharge_date: before.patients[0].discharge_date,
      status: before.patients[0].status, admission_balances: {
        [older]: { cycleId: String(older), total: 25 },
        [target]: { cycleId: String(target), total: 100, segmentCharges: { anchor: 100 } },
      } });
    expect(after.patients[0].admission_balances).not.toHaveProperty(String(wrong));
    expect(after.stays.find(s => s.id === 'anchor')).toMatchObject({ admission_date: new Date(target), cycle_id: String(target),
      patient_snapshot: { admissionDate: target, retained: true, billingSummary: { admissionId: String(target), cycleId: String(target), total: 100 } },
      billing_summary: { admissionId: String(target), cycleId: String(target), amount: 100 }, total_cost: '100.00' });
    expect(after.stays.find(s => s.id === 'older')).toEqual(before.stays.find(s => s.id === 'older'));
    return after;
  }

  it.each(['discharged', 'active', 'Paid'])('converges the production anchor mismatch for status %s', async status => {
    await fixture(status);
    const before = await state(), logger = log();
    expect(await repairAdmissions(logger)).toEqual({ repaired: 1, skipped: 0, failed: 0 });
    await assertConverged(before);
    expect(logger.info).toHaveBeenCalledWith(expect.objectContaining({ event: 'admission_repaired', class: 'cycle_mismatch',
      patientId: 'repair-patient', fromCycle: String(wrong), toCycle: String(target) }), 'Admission repaired');
    expect(counters(logger)).toEqual({ repaired: 1, skipped: 0, failed: 0 });
    if (status === 'discharged') console.log('CLASS_2_FIXTURE_COUNTERS', JSON.stringify(counters(logger)));
  });
  it('converges after the patient has already been discharged again', async () => {
    await fixture();
    await db.query("UPDATE patients SET discharge_date='2026-11-09' WHERE id='repair-patient'");
    const before = await state();
    expect(await repairAdmissions(log())).toEqual({ repaired: 1, skipped: 0, failed: 0 });
    await assertConverged(before);
  });
  it.each(['transfer', 'registration differs', 'fresh rejoin', 'latest created_at tie-break'])('leaves %s untouched', async shape => {
    await fixture();
    if (shape === 'transfer') {
      await db.query('UPDATE stays SET admission_date=$1,cycle_id=$2 WHERE id=\'anchor\'', [new Date(target), String(target)]);
      await addStay('latest-segment', wrong, String(target));
    } else if (shape === 'registration differs') {
      await db.query('UPDATE stays SET admission_date=$1,cycle_id=$2 WHERE id=\'anchor\'', [new Date(target), String(target)]);
      await db.query("UPDATE patients SET registration_date='2026-11-01',status='active' WHERE id='repair-patient'");
    } else if (shape === 'fresh rejoin') {
      await db.query('UPDATE patients SET admission_date=$1,registration_date=$1,status=\'active\',discharge_date=NULL WHERE id=\'repair-patient\'', [new Date(wrong)]);
    } else {
      await db.query('UPDATE patients SET admission_date=$1 WHERE id=\'repair-patient\'', [new Date(wrong)]);
      await addStay('latest-anchor', wrong, String(wrong));
      await db.query("UPDATE stays SET created_at=CASE WHEN id='latest-anchor' THEN '2026-11-03'::timestamptz ELSE '2026-11-02'::timestamptz END WHERE id IN ('anchor','latest-anchor')");
    }
    const before = await state(), logger = log();
    expect(await repairAdmissions(logger)).toEqual({ repaired: 0, skipped: 0, failed: 0 });
    expect(await state()).toEqual(before);
    expect(counters(logger)).toEqual({ repaired: 0, skipped: 0, failed: 0 });
  });
  it.each(['immutable_billing_corrections', 'target stay', 'target balance', 'target payment', 'unresolved stay', 'unresolved payment'])('skips %s atomically and logs the class', async reason => {
    await fixture();
    if (reason === 'immutable_billing_corrections') await db.query(`INSERT INTO billing_corrections(patient_id,cycle_id,stay_id,billable_date,amount,reason,operator_uid)
      VALUES('repair-patient',$1,'anchor','2026-11-02',100,'Synthetic correction','test')`, [String(wrong)]);
    if (reason === 'target stay') await addStay('target', target, String(target));
    if (reason === 'target balance') await db.query('UPDATE patients SET admission_balances=admission_balances || $1::jsonb WHERE id=\'repair-patient\'', [JSON.stringify({ [target]: { cycleId: String(target) } })]);
    if (reason === 'target payment' || reason === 'unresolved payment') await db.query("INSERT INTO payments(id,patient_id,cycle_id,amount,payment_date) VALUES('ambiguous','repair-patient',$1,100,'2026-11-02')", [reason === 'target payment' ? String(target) : null]);
    if (reason === 'unresolved stay') await addStay('unresolved', Date.parse('2026-09-15'), null, { admissionDate: null });
    const before = await state(), logger = log();
    expect(await repairAdmissions(logger)).toEqual({ repaired: 0, skipped: 1, failed: 0 });
    expect(await state()).toEqual(before);
    expect(logger.warn).toHaveBeenCalledTimes(1);
    expect(logger.warn).toHaveBeenCalledWith(expect.objectContaining({ class: 'cycle_mismatch',
      patientId: 'repair-patient', fromCycle: String(wrong), toCycle: String(target),
      reason: reason.startsWith('target') ? 'target_cycle_exists' : reason.startsWith('unresolved') ? 'unresolved_cycle_identity' : reason }), 'Admission repair skipped');
    expect(counters(logger)).toEqual({ repaired: 0, skipped: 1, failed: 0 });
  });
  it('moves only wrong-cycle payments and anchor dates, preserving older-cycle records', async () => {
    await fixture();
    const segmentDate = Date.parse('2026-11-01');
    await addStay('segment', segmentDate, String(wrong));
    await db.query("INSERT INTO payments(id,patient_id,cycle_id,amount,payment_date,type) VALUES('wrong-payment','repair-patient',$1,100,'2026-11-02','payment'),('older-payment','repair-patient',$2,25,'2026-09-01','payment'),('wrong-refund','repair-patient',$1,-10,'2026-11-02','refund')", [String(wrong), String(older)]);
    const before = await state();
    expect(await repairAdmissions(log())).toEqual({ repaired: 1, skipped: 0, failed: 0 });
    const after = await assertConverged(before);
    expect(after.stays.find(s => s.id === 'segment')).toMatchObject({ admission_date: new Date(segmentDate), cycle_id: String(target), patient_snapshot: { admissionDate: target } });
    expect(after.payments.find(p => p.id === 'older-payment')).toEqual(before.payments.find(p => p.id === 'older-payment'));
    for (const id of ['wrong-payment', 'wrong-refund']) {
      expect(after.payments.find(p => p.id === id)).toEqual({ ...before.payments.find(p => p.id === id), cycle_id: String(target) });
      expect(after.payment_change_history.filter(h => h.payment_id === id && h.operation === 'UPDATE')).toEqual([
        expect.objectContaining({ reason: 'Admission date repaired from registration date', previous_record: expect.objectContaining({ cycle_id: String(wrong) }), resulting_record: expect.objectContaining({ cycle_id: String(target) }) }),
      ]);
    }
  });
  it('is idempotent on the second run', async () => {
    await fixture();
    expect(await repairAdmissions(log())).toEqual({ repaired: 1, skipped: 0, failed: 0 });
    const before = await state(), logger = log();
    expect(await repairAdmissions(logger)).toEqual({ repaired: 0, skipped: 0, failed: 0 });
    expect(await state()).toEqual(before);
    expect(counters(logger)).toEqual({ repaired: 0, skipped: 0, failed: 0 });
    console.log('CLASS_2_SECOND_RUN_COUNTERS', JSON.stringify(counters(logger)));
  });
  it('repairs the newest anchor despite a later transfer, preserving the transfer admission date', async () => {
    await fixture();
    const segmentDate = Date.parse('2026-11-03');
    await addStay('later-transfer', segmentDate, String(wrong));
    const before = await state(), logger = log();
    expect(await repairAdmissions(logger)).toEqual({ repaired: 1, skipped: 0, failed: 0 });
    const after = await assertConverged(before);
    expect(after.stays.find(s => s.id === 'later-transfer')).toEqual({
      ...before.stays.find(s => s.id === 'later-transfer'), cycle_id: String(target),
      patient_snapshot: { admissionDate: target, retained: true,
        billingSummary: { admissionId: String(target), cycleId: String(target), total: 100 } },
      billing_summary: { admissionId: String(target), cycleId: String(target), amount: 100 },
      updated_at: expect.any(Date),
    });
    expect(counters(logger)).toEqual({ repaired: 1, skipped: 0, failed: 0 });
    const second = log();
    expect(await repairAdmissions(second)).toEqual({ repaired: 0, skipped: 0, failed: 0 });
    expect(await state()).toEqual(after);
    expect(counters(second)).toEqual({ repaired: 0, skipped: 0, failed: 0 });
  });
  it('leaves older mismatching episodes untouched when the newest anchor is coherent', async () => {
    await fixture();
    await db.query('UPDATE stays SET admission_date=$1,cycle_id=$2 WHERE id=\'anchor\'', [new Date(target), String(target)]);
    const before = await state(), logger = log();
    expect(before.stays.find(s => s.id === 'older').cycle_id).not.toBe(String(target));
    expect(await repairAdmissions(logger)).toEqual({ repaired: 0, skipped: 0, failed: 0 });
    expect(await state()).toEqual(before);
    expect(counters(logger)).toEqual({ repaired: 0, skipped: 0, failed: 0 });
  });
  it('rechecks the target collision after class 1 commits its new patient admission', async () => {
    await fixture('active');
    await db.query("UPDATE patients SET registration_date='2026-09-15T00:00:00Z' WHERE id='repair-patient'");
    await db.query("UPDATE stays SET status='active',admission_date='2026-10-01T00:00:00Z',cycle_id=$1 WHERE id='older'", [String(target)]);
    const logger = log();
    expect(await repairAdmissions(logger)).toEqual({ repaired: 1, skipped: 1, failed: 0 });
    const finalCycle = String(Date.parse('2026-09-15'));
    expect((await db.query("SELECT cycle_id FROM stays WHERE id='older'")).rows[0].cycle_id).toBe(finalCycle);
    expect((await db.query("SELECT cycle_id FROM stays WHERE id='anchor'")).rows[0].cycle_id).toBe(String(wrong));
    expect(logger.warn).toHaveBeenCalledWith(expect.objectContaining({ class: 'cycle_mismatch',
      fromCycle: String(wrong), toCycle: finalCycle, reason: 'target_cycle_exists' }), 'Admission repair skipped');
    expect(counters(logger)).toEqual({ repaired: 0, skipped: 1, failed: 0 });
  });
  it('rechecks the latest anchor after candidate selection inside the transaction', async () => {
    await fixture();
    const original = db.getClient;
    const connect = vi.spyOn(db, 'getClient').mockImplementationOnce(async () => {
      await db.query('UPDATE stays SET admission_date=$1,cycle_id=$2 WHERE id=\'anchor\'', [new Date(target), String(target)]);
      return original();
    });
    try {
      const logger = log();
      expect(await repairAdmissions(logger)).toEqual({ repaired: 0, skipped: 0, failed: 0 });
      expect(counters(logger)).toEqual({ repaired: 0, skipped: 0, failed: 0 });
      expect((await db.query("SELECT admission_date FROM stays WHERE id='anchor'")).rows[0].admission_date).toEqual(new Date(target));
    } finally { connect.mockRestore(); }
  });
});
