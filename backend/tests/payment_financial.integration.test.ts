import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../src/app.js';
import { config } from '../src/config/index.js';
import { pool, query } from '../src/db/index.js';
import { runMigrations } from '../src/db/migrate.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

const enabled = process.env.RUN_PAYMENT_ACCURACY_INTEGRATION === '1';
const cycle = String(Date.parse('2026-01-01T00:00:00Z'));
const oldCycle = String(Date.parse('2025-01-01T00:00:00Z'));
describe.skipIf(!enabled)('isolated PostgreSQL payment financial accuracy', () => {
  const app = buildApp({ logger: false });
  let verified = false;
  const send = (method: any, url: string, payload?: any) => app.inject({ method, url: `/api${url}`, payload, headers: { authorization: `Bearer ${signedTestToken()}` } });
  const getPatient = async () => (await send('GET', '/patients/p1')).json();
  const record = (id: string, amount: string, extra: Record<string, any> = {}) => send('POST', '/payments', { id, patientId: 'p1', amount, cycleId: cycle, date: '2026-01-02', ...extra });
  const balance = (total: number, paid: number, refunded = 0) => ({ total, paid, refunded, netPaid: paid - refunded, due: Math.max(0, total - paid + refunded), refundDue: Math.max(0, paid - refunded - total), status: paid - refunded > total ? 'Payment Exceeded' : paid - refunded === total ? 'Paid' : paid - refunded > 0 ? 'Partially Paid' : 'Unpaid' });
  async function seed(extra: Record<string, any> = {}) {
    const response = await send('POST', '/patients', { id: 'p1', fullName: 'Synthetic payment accuracy', dateOfBirth: '1990-01-01', gender: 'Other', contactNumber: '000', emergencyContact: '000', emergencyContactName: 'Synthetic', medicalCondition: 'Synthetic', admissionDate: '2026-01-01T00:00:00Z', currentDueAmount: '10.00', advanceBilledAmount: String((extra.admissionBalances as any)?.[cycle]?.total ?? (extra.currentDueAmount != null ? Number(extra.currentDueAmount) + Number(extra.totalPaidAmount ?? 0) - Number(extra.refundDueAmount ?? 0) : 10)), ...extra });
    expect(response.statusCode).toBe(201);
    // Financial fixtures must contain real receipts, not only saved summaries.
    const balances = extra.admissionBalances ?? { [cycle]: balance(Number(extra.advanceBilledAmount ?? 10), Number(extra.totalPaidAmount ?? 0)) };
    for (const [id, saved] of Object.entries(balances) as [string, any][]) {
      if (saved.paid) await query("INSERT INTO payments(id,patient_id,cycle_id,amount,payment_date) VALUES($1,'p1',$2,$3,'2026-01-02')", [`fixture_paid_${id}`, id, saved.paid]);
      if (saved.refunded) await query("INSERT INTO payments(id,patient_id,cycle_id,type,amount,payment_date) VALUES($1,'p1',$2,'refund',$3,'2026-01-02')", [`fixture_refund_${id}`, id, -saved.refunded]);
    }
    return response.json();
  }
  async function excess() {
    return seed({ totalPaidAmount: 120, currentDueAmount: 0, refundDueAmount: 20, totalRefundDueAmount: 20, admissionBalances: { [cycle]: balance(100, 120) } });
  }
  beforeAll(async () => {
    const target = new URL(config.getEffectiveDatabaseUrl());
    if (process.env.NODE_ENV !== 'test' || target.hostname !== '127.0.0.1' || target.port !== '55439' || target.pathname !== '/ngo_audit_payment_accuracy' || decodeURIComponent(target.username) !== 'ngo_audit' || config.POSTGRES_DB !== 'ngo_audit_payment_accuracy' || config.POSTGRES_HOST !== '127.0.0.1' || config.POSTGRES_PORT !== 55439 || config.POSTGRES_USER !== 'ngo_audit') throw new Error('Refusing writes outside exact disposable payment accuracy database');
    const identity = (await query("SELECT current_database() AS db,current_user AS username,inet_server_port() AS port,current_setting('server_version_num')::int AS version")).rows[0];
    expect(identity).toMatchObject({ db: 'ngo_audit_payment_accuracy', username: 'ngo_audit', port: 55439 });
    expect(identity.version).toBeGreaterThanOrEqual(160000); expect(identity.version).toBeLessThan(170000);
    verified = true;
    await runMigrations();
    installTestFirebaseKeys();
    await app.ready();
  }, 60000);
  beforeEach(async () => {
    if (!verified) throw new Error('Disposable database was not verified');
    await query('TRUNCATE users,rooms,patients,payments CASCADE');
    await query("INSERT INTO users(id,email,name,role) VALUES('test-uid-admin','payment@ngo.test','Synthetic Admin','admin')");
  });
  afterAll(async () => { vi.restoreAllMocks(); await app.close(); await pool.end(); });

  it('records exact decimal receipts and updates due, status and version', async () => {
    const before = await seed();
    expect((await record('penny', '0.10')).statusCode).toBe(201);
    expect((await record('two-pennies', '0.20')).statusCode).toBe(201);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 0.3, currentDueAmount: 9.7, paymentStatus: 'Partially Paid', paymentPending: true, version: before.version + 2 });
    expect((await query("SELECT sum(amount)::text AS amount FROM payments")).rows[0].amount).toBe('0.30');
  });
  it('collects partial and remaining balances through the application path and persists both history and ledger', async () => {
    await seed();
    const partial = { collectOutstanding: true, method: 'ONLINE', transactionId: 'OUTSTANDING-PARTIAL', receiptNumber: 'partial receipt' };
    const remaining = { collectOutstanding: true, method: 'ONLINE', transactionId: 'OUTSTANDING-REMAINING', receiptNumber: 'remaining receipt' };
    expect((await record('collect-partial', '3.00', partial)).statusCode).toBe(201);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 3, currentDueAmount: 7 });
    expect((await record('collect-remaining', '7.00', remaining)).statusCode).toBe(201);
    const reloaded = await getPatient();
    expect(reloaded).toMatchObject({ totalPaidAmount: 10, currentDueAmount: 0, paymentPending: false, paymentStatus: 'Paid' });
    expect(reloaded.payments).toHaveLength(2);
    expect(reloaded.payments).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: 'collect-remaining', amount: 7, cycleId: cycle, method: 'ONLINE', transactionId: remaining.transactionId, receiptNumber: remaining.receiptNumber, date: Date.parse('2026-01-02') }),
    ]));
    expect((await send('GET', '/payments?patientId=p1')).json()).toHaveLength(2);
    expect((await record('collect-remaining', '7.00', remaining)).statusCode).toBe(200);
    expect((await query("SELECT COUNT(*)::int AS count FROM payments")).rows[0].count).toBe(2);
    expect((await record('collect-excess', '0.01', { collectOutstanding: true })).statusCode).toBe(409);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 10, currentDueAmount: 0 });
  });
  it('serializes competing outstanding collections and rejects stale excessive amounts without writing', async () => {
    await seed();
    await record('already-paid', '3.00');
    const responses = await Promise.all([
      record('collect-race-a', '7.00', { collectOutstanding: true }),
      record('collect-race-b', '7.00', { collectOutstanding: true }),
    ]);
    expect(responses.map(r => r.statusCode).sort()).toEqual([201, 409]);
    expect((await query("SELECT COUNT(*)::int AS count FROM payments")).rows[0].count).toBe(2);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 10, currentDueAmount: 0 });
  });
  it('accepts payment identifiers up to the migrated 128 character contract and rejects invalid collection flags', async () => {
    await seed();
    const longId = `upi_${'a'.repeat(100)}`;
    expect((await record(longId, '1.00', { collectOutstanding: true })).statusCode).toBe(201);
    expect((await send('GET', `/payments/${longId}`)).json()).toMatchObject({ id: longId, amount: 1 });
    expect((await record('bad-flag', '1.00', { collectOutstanding: 'true' })).statusCode).toBe(400);
    expect((await record('bad-refund-collection', '-1.00', { type: 'refund', collectOutstanding: true })).statusCode).toBe(400);
  });
  it('PATCH amount changes patient totals and invalidates old snapshots', async () => {
    await seed(); await record('edit', '3.00');
    const before = await getPatient();
    expect((await send('PATCH', '/payments/edit', { amount: '1.00' })).statusCode).toBe(200);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 1, currentDueAmount: 9, version: before.version + 1 });
    expect((await send('PUT', '/patients/p1', { totalPaidAmount: before.totalPaidAmount, expectedVersion: before.version })).statusCode).toBe(409);
  });
  it('DELETE reverses a receipt and invalidates old snapshots', async () => {
    await seed(); await record('remove', '3.00'); const before = await getPatient();
    expect((await send('DELETE', '/payments/remove')).statusCode).toBe(200);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 0, currentDueAmount: 10, version: before.version + 1 });
    expect((await send('PUT', '/patients/p1', { currentDueAmount: before.currentDueAmount, expectedVersion: before.version })).statusCode).toBe(409);
    expect((await send('DELETE', '/payments/remove')).statusCode).toBe(404);
  });
  it('preserves financial receipt metadata on details-only edits and bumps version once', async () => {
    await seed(); await record('metadata', '3.00', { totalAmount: '10.00', paidAmount: '3.00', pendingAmount: '7.00' });
    const before = await getPatient();
    const updated = await send('PATCH', '/payments/metadata', { notes: 'corrected receipt', transactionId: 'REF-1' });
    expect(updated.statusCode).toBe(200);
    expect(updated.json()).toMatchObject({ totalAmount: 10, paidAmount: 3, pendingAmount: 7, transactionId: 'REF-1' });
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 3, currentDueAmount: 7, version: before.version + 1 });
  });
  it('identical and empty PATCH requests preserve version and timestamps', async () => {
    await seed(); await record('noop', '3.00'); const before = await getPatient();
    const row = (await query("SELECT updated_at FROM payments WHERE id='noop'")).rows[0];
    expect((await send('PATCH', '/payments/noop', {})).statusCode).toBe(200);
    expect((await send('PUT', '/payments/noop', { amount: '3', patientId: 'p1', type: 'payment', date: '2026-01-02' })).statusCode).toBe(200);
    expect((await getPatient()).version).toBe(before.version);
    expect((await query("SELECT updated_at FROM payments WHERE id='noop'")).rows[0]).toEqual(row);
  });
  it('records negative refunds using existing excess and updates all affected balances', async () => {
    const before = await excess();
    const response = await record('refund', '-10.00', { type: 'refund' });
    expect(response.statusCode).toBe(201); expect(response.json()).toMatchObject({ type: 'refund', amount: -10 });
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 110, currentDueAmount: 0, refundDueAmount: 10, totalRefundDueAmount: 10, totalRefundedAmount: 10, version: before.version + 1, admissionBalances: { [cycle]: { paid: 120, refunded: 10, netPaid: 110, refundDue: 10 } } });
  });
  it('identical concurrent refund retries return one canonical ledger record', async () => {
    const before = await excess();
    const responses = await Promise.all([record('retry', '-20.00', { type: 'refund' }), record('retry', '-20.00', { type: 'refund' })]);
    expect(responses.map(x => x.statusCode).sort()).toEqual([200, 201]);
    expect(responses[0].json()).toEqual(responses[1].json());
    expect((await record('retry', '-20.00', { type: 'refund' })).statusCode).toBe(200);
    expect((await record('retry', '-19.00', { type: 'refund' })).statusCode).toBe(409);
    expect((await query("SELECT count(*)::int AS count FROM payments WHERE id NOT LIKE 'fixture_%'")).rows[0].count).toBe(1);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 100, totalRefundedAmount: 20, refundDueAmount: 0, version: before.version + 1 });
  });
  it('serializes concurrent distinct refunds so combined amount cannot exceed excess', async () => {
    await excess();
    const responses = await Promise.all([record('r1', '-15.00', { type: 'refund' }), record('r2', '-15.00', { type: 'refund' })]);
    expect(responses.map(x => x.statusCode).sort()).toEqual([201, 409]);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 105, totalRefundedAmount: 15, refundDueAmount: 5 });
  });
  it('rejects refunds without current cycle excess or a known historical balance', async () => {
    await seed();
    expect((await record('no-excess', '-1.00', { type: 'refund' })).statusCode).toBe(409);
    expect((await record('unknown-cycle', '-1.00', { type: 'refund', cycleId: oldCycle })).statusCode).toBe(409);
    expect((await query("SELECT count(*)::int AS count FROM payments WHERE id NOT LIKE 'fixture_%'")).rows[0].count).toBe(0);
  });
  it('refund edits and deletion reverse refunded totals and preserve billed charges', async () => {
    await excess(); await record('refund-edit', '-10.00', { type: 'refund' });
    expect((await send('PATCH', '/payments/refund-edit', { amount: '-5.00' })).statusCode).toBe(200);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 115, totalRefundedAmount: 5, refundDueAmount: 15 });
    expect((await send('PATCH', '/payments/refund-edit', { amount: '-20.00' })).statusCode).toBe(200);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 100, totalRefundedAmount: 20, refundDueAmount: 0 });
    expect((await send('PATCH', '/payments/refund-edit', { amount: '-20.01' })).statusCode).toBe(409);
    expect((await send('DELETE', '/payments/refund-edit')).statusCode).toBe(200);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 120, totalRefundedAmount: 0, refundDueAmount: 20, totalRefundDueAmount: 20 });
  });
  it('historical refunds update their cycle and aggregates without restating current admission', async () => {
    await seed({ totalPaidAmount: 7, currentDueAmount: 3, totalRefundDueAmount: 20, admissionBalances: { [cycle]: balance(10, 7), [oldCycle]: { ...balance(100, 120), segmentCharges: { retained: 100 } } } });
    expect((await record('historical-refund', '-10.00', { type: 'refund', cycleId: oldCycle })).statusCode).toBe(201);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 7, currentDueAmount: 3, refundDueAmount: 0, totalRefundDueAmount: 10, totalRefundedAmount: 10, admissionBalances: { [oldCycle]: { total: 100, paid: 120, refunded: 10, refundDue: 10, segmentCharges: { retained: 100 } } } });
  });
  it('moving a receipt between known cycles applies both deltas without global restatement', async () => {
    await seed({ admissionBalances: { [cycle]: balance(10, 0), [oldCycle]: balance(20, 0) } });
    await record('move', '3.00');
    expect((await send('PATCH', '/payments/move', { cycleId: oldCycle })).statusCode).toBe(200);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 0, currentDueAmount: 10, admissionBalances: { [oldCycle]: { paid: 3, due: 17 }, [cycle]: { paid: 0, due: 10 } } });
    expect((await send('DELETE', '/payments/move')).statusCode).toBe(200);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 0, currentDueAmount: 10, admissionBalances: { [oldCycle]: { paid: 0, due: 20 } } });
  });
  it('legacy receipts without cycle ids use current admission dates and retain correct mutation deltas', async () => {
    await seed();
    expect((await record('legacy-current', '3.00', { cycleId: null })).statusCode).toBe(201);
    expect((await send('PATCH', '/payments/legacy-current', { amount: '2.00' })).statusCode).toBe(200);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 2, currentDueAmount: 8 });
    expect((await send('DELETE', '/payments/legacy-current')).statusCode).toBe(200);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 0, currentDueAmount: 10 });
  });
  it('legacy historical receipts follow explicit stay boundaries without spending current admission credit', async () => {
    await seed({ totalPaidAmount: 7, currentDueAmount: 3, totalRefundDueAmount: 20, admissionBalances: { [cycle]: balance(10, 7), [oldCycle]: balance(100, 120) } });
    await query("INSERT INTO rooms(id,room_number,room_type) VALUES('legacy-room','Legacy','general')");
    await query(`INSERT INTO stays(id,patient_id,patient_name,room_id,room_number,room_type,cycle_id,admission_date,duration_days,expected_discharge_date,expiry_date,completed_at,cost_override,status,created_by)
      VALUES('legacy-stay','p1','Synthetic','legacy-room','Legacy','general',$1,'2025-01-01',2,'2025-01-03','2025-01-03','2025-01-03',100,'completed','test-uid-admin')`, [oldCycle]);
    expect((await record('legacy-old-refund', '-10.00', { type: 'refund', cycleId: null, date: '2025-01-02' })).statusCode).toBe(201);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 7, currentDueAmount: 3, totalRefundedAmount: 10, totalRefundDueAmount: 10, admissionBalances: { [oldCycle]: { paid: 120, refunded: 10, refundDue: 10 } } });
  });
  it('prevents removing already refunded receipt money below zero net paid', async () => {
    await seed({ currentDueAmount: 0 }); await record('credit', '10.00'); await record('returned', '-8.00', { type: 'refund' });
    expect((await send('DELETE', '/payments/credit')).statusCode).toBe(409);
    expect((await send('PATCH', '/payments/credit', { amount: '7.99' })).statusCode).toBe(409);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 2, totalRefundedAmount: 8, refundDueAmount: 2 });
  });
  it('clears due on overpayment and restores original due when it is removed', async () => {
    await seed(); await record('overpaid', '15.00');
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 15, currentDueAmount: 0, refundDueAmount: 5, totalRefundDueAmount: 5, paymentStatus: 'Payment Exceeded', paymentPending: false });
    await send('DELETE', '/payments/overpaid');
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 0, currentDueAmount: 10, refundDueAmount: 0, totalRefundDueAmount: 0, paymentStatus: 'Unpaid' });
  });
  it.each([
    { amount: '1.001' }, { amount: '0' }, { amount: '-1', type: 'payment' }, { amount: '1', type: 'refund' }, { amount: '1', type: 'other' }, { amount: 'NaN' }, { amount: '1e2' }, { amount: '1', date: '2026-02-30' }, { amount: '1', date: '2026-02-30T10:00:00Z' }, { amount: '1', date: '2026-99-99' }, { amount: '1', date: 'invalid' },
  ])('rejects invalid create payload %j before writing', async invalid => {
    await seed(); expect((await record('invalid', invalid.amount, invalid)).statusCode).toBe(400);
    expect((await query("SELECT count(*)::int AS count FROM payments WHERE id NOT LIKE 'fixture_%'")).rows[0].count).toBe(0);
  });
  it('requires stable retry keys, preserves ownership and rejects type/sign flips and malformed edit dates', async () => {
    await seed();
    expect((await send('POST', '/payments', { patientId: 'p1', amount: '1' })).statusCode).toBe(400);
    await record('immutable', '1.00');
    for (const payload of [{ patientId: 'p2' }, { id: 'changed' }, { type: 'refund', amount: '-1.00' }, { amount: '-1' }, { amount: '1.001' }, { date: '2026-02-30' }, { date: 'invalid' }]) expect((await send('PATCH', '/payments/immutable', payload)).statusCode).toBe(400);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 1, currentDueAmount: 9 });
  });
  it('unique transaction references reject conflicting edits and retries atomically', async () => {
    await seed(); await record('tx1', '1.00', { transactionId: 'UNIQUE' }); await record('tx2', '2.00');
    const before = await getPatient();
    expect((await send('PATCH', '/payments/tx2', { amount: '5.00', transactionId: 'UNIQUE' })).statusCode).toBe(409);
    expect((await record('retry-by-tx', '1.00', { transactionId: 'UNIQUE' })).statusCode).toBe(200);
    expect((await record('other', '3.00', { transactionId: 'UNIQUE' })).statusCode).toBe(409);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 3, currentDueAmount: 7, version: before.version });
  });
  it('preserves imported split-reference identities on metadata and amount edits', async () => {
    await seed();
    await query("INSERT INTO payments(id,patient_id,cycle_id,amount,payment_date,transaction_id,source) VALUES('legacy-a','p1',$1,1,'2026-01-02','SHARED','firebase'),('legacy-b','p1',$1,2,'2026-01-02','SHARED','firebase')", [cycle]);
    expect((await send('PATCH', '/payments/legacy-a', { notes: 'corrected legacy receipt' })).statusCode).toBe(200);
    expect((await send('PATCH', '/payments/legacy-a', { transactionId: 'SHARED', amount: '1.50' })).statusCode).toBe(200);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 3.5, currentDueAmount: 6.5 });
    expect((await query("SELECT COUNT(*)::int AS count FROM payments WHERE transaction_id='SHARED'")).rows[0].count).toBe(2);
  });
  it.each(['PATCH', 'DELETE'])('%s failure rolls back the ledger and patient version together', async method => {
    await seed(); await record('rollback', '3.00'); const before = await getPatient();
    await query("CREATE FUNCTION payment_accuracy_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic failure'; END $$; CREATE TRIGGER payment_accuracy_fail BEFORE UPDATE ON patients FOR EACH ROW EXECUTE FUNCTION payment_accuracy_fail()");
    try {
      expect((await send(method, '/payments/rollback', method === 'PATCH' ? { amount: '1.00' } : undefined)).statusCode).toBe(500);
      expect((await send('GET', '/payments/rollback')).json().amount).toBe(3);
      expect(await getPatient()).toMatchObject({ totalPaidAmount: 3, currentDueAmount: 7, version: before.version });
    } finally { await query('DROP TRIGGER payment_accuracy_fail ON patients; DROP FUNCTION payment_accuracy_fail()'); }
  });
  it('POST failure rolls back both the newly inserted ledger and financial changes', async () => {
    const before = await seed();
    await query("CREATE FUNCTION payment_accuracy_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic failure'; END $$; CREATE TRIGGER payment_accuracy_fail BEFORE UPDATE ON patients FOR EACH ROW EXECUTE FUNCTION payment_accuracy_fail()");
    try {
      expect((await record('rollback-create', '3.00')).statusCode).toBe(500);
      expect((await query("SELECT count(*)::int AS count FROM payments WHERE id NOT LIKE 'fixture_%'")).rows[0].count).toBe(0);
      expect(await getPatient()).toMatchObject({ totalPaidAmount: 0, currentDueAmount: 10, version: before.version });
    } finally { await query('DROP TRIGGER payment_accuracy_fail ON patients; DROP FUNCTION payment_accuracy_fail()'); }
  });
  it('concurrent create, edit and delete serialize on the same patient without losing financial deltas', async () => {
    const before = await seed(); await record('edit-concurrent', '2.00'); await record('delete-concurrent', '1.00');
    const responses = await Promise.all([send('PATCH', '/payments/edit-concurrent', { amount: '3.00' }), send('DELETE', '/payments/delete-concurrent'), record('create-concurrent', '0.10')]);
    expect(responses.map(x => x.statusCode)).toEqual([200, 200, 201]);
    expect(await getPatient()).toMatchObject({ totalPaidAmount: 3.1, currentDueAmount: 6.9, version: before.version + 5 });
  });
  it.each(['PATCH', 'DELETE'])('%s rejects a receipt recreated under another patient while its original owner is locked', async method => {
    await seed(); await record('recreated', '1.00');
    const other = await send('POST', '/patients', { id: 'p2', fullName: 'Synthetic second patient', dateOfBirth: '1990-01-01', gender: 'Other', contactNumber: '000', emergencyContact: '000', emergencyContactName: 'Synthetic', medicalCondition: 'Synthetic', admissionDate: '2026-01-01', totalPaidAmount: 2, currentDueAmount: 8 });
    expect(other.statusCode).toBe(201);
    const blocker = await pool.connect();
    let open = false;
    let pending: ReturnType<typeof send> | undefined;
    try {
      await blocker.query('BEGIN'); open = true;
      await blocker.query("SELECT id FROM patients WHERE id='p1' FOR UPDATE");
      const blockerPid = (await blocker.query('SELECT pg_backend_pid() AS pid')).rows[0].pid;
      // Start the real HTTP handler, then prove its owner lookup completed by
      // observing it blocked on the original patient's lock before replacement.
      pending = send(method, '/payments/recreated', method === 'PATCH' ? { amount: '5.00' } : undefined).then(response => response);
      let waiting = false;
      const deadline = Date.now() + 5000;
      while (Date.now() < deadline) {
        waiting = (await query("SELECT count(*)::int AS count FROM pg_stat_activity WHERE $1 = ANY(pg_blocking_pids(pid)) AND query LIKE 'SELECT * FROM patients WHERE id=$1 FOR UPDATE'", [blockerPid])).rows[0].count > 0;
        if (waiting) break;
        await new Promise(resolve => setTimeout(resolve, 10));
      }
      expect(waiting).toBe(true);
      await blocker.query("DELETE FROM payments WHERE id='recreated'");
      await blocker.query("UPDATE patients SET total_paid_amount=0,current_due_amount=10,version=version+1 WHERE id='p1'");
      await blocker.query("INSERT INTO payments(id,patient_id,cycle_id,amount,payment_date) VALUES('recreated','p2',$1,2,'2026-01-02')", [cycle]);
      await blocker.query('COMMIT'); open = false;
      expect((await pending).statusCode).toBe(409);
      expect((await query("SELECT patient_id,amount FROM payments WHERE id='recreated'")).rows[0]).toEqual({ patient_id: 'p2', amount: '2.00' });
      expect(await getPatient()).toMatchObject({ totalPaidAmount: 0, currentDueAmount: 10 });
      expect((await send('GET', '/patients/p2')).json()).toMatchObject({ totalPaidAmount: 2, currentDueAmount: 8 });
    } finally {
      if (open) await blocker.query('ROLLBACK');
      blocker.release();
      if (pending) await pending;
    }
  }, 10000);
});
