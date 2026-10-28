import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { config } from '../src/config/index.js';
import { closePool, query } from '../src/db/index.js';
import { runMigrations } from '../src/db/migrate.js';
import { runFirebaseImport } from '../src/importer/index.js';
import { importerFixture } from './fixtures/importer-fixture.js';

const enabled = process.env.RUN_IMPORTER_DB_TESTS === '1';
describe.skipIf(!enabled)('Firebase importer with disposable PostgreSQL 16', () => {
  let directory: string;
  let fixture: Record<string, any>;
  let verifiedDisposable = false;
  async function run(dryRun = false, reconcile = false) {
    const filePath = path.join(directory, 'synthetic.json');
    fs.writeFileSync(filePath, JSON.stringify(fixture));
    return runFirebaseImport({ filePath, dryRun, reconcile, onProgress: () => {} });
  }
  beforeAll(async () => {
    // Refuse even a connection unless the explicitly opted-in target is isolated.
    expect(config.NODE_ENV).toBe('test');
    expect(config.POSTGRES_DB).toBe('ngo_audit_importer');
    expect(config.POSTGRES_HOST).toBe('127.0.0.1');
    expect(config.POSTGRES_PORT).toBe(55439);
    const target = (await query('SELECT current_database() AS db, inet_server_port() AS port, version() AS version')).rows[0];
    expect(target.db).toBe('ngo_audit_importer');
    expect(target.port).toBe(55439);
    expect(target.version).toMatch(/^PostgreSQL 16\./);
    await runMigrations();
    expect((await query("SELECT to_regclass('public.patients') IS NOT NULL AS migrated")).rows[0].migrated).toBe(true);
    verifiedDisposable = true;
  });
  beforeEach(async () => {
    if (!verifiedDisposable) throw new Error('Disposable database safety check did not complete');
    await query('TRUNCATE rooms, patients, users, system_counters, system_settings CASCADE');
    fixture = importerFixture();
    directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ngo-import-db-'));
  });
  afterEach(() => { if (directory) fs.rmSync(directory, { recursive: true, force: true }); });
  afterAll(async () => { await closePool(); });

  it('imports related rooms, beds, patients, attendants, stays, nested daily attendance, settings and precise payments', async () => {
    const stats = await run();
    expect(stats.committed).toBe(true);
    expect(stats.warnings).toEqual([]);
    expect(stats.rooms.imported).toBe(1);
    expect(stats.beds.imported).toBe(1);
    expect(stats.patients.imported).toBe(1);
    expect(stats.attendants.imported).toBe(1);
    expect(stats.stays.imported).toBe(1);
    expect(stats.attendance.imported).toBe(2);
    expect(stats.payments).toMatchObject({ processed: 2, imported: 2, failed: 0, deduplicated: 1 });
    expect(stats.financials).toEqual({ sourceTotalPayments: 0.3, dbTotalPayments: 0.3,
      sourceTotalPatientPaid: 0.3, dbTotalPatientPaid: 0.3, sourceTotalPatientDue: 9.7, dbTotalPatientDue: 9.7 });
    const stored = (await query(`SELECT p.full_name, p.total_paid_amount, p.current_due_amount,
      s.patient_id, s.room_id, s.bed_id, a.name AS attendant, a.photo_data_url FROM patients p JOIN stays s ON s.patient_id=p.id
      JOIN patient_attendants a ON a.patient_id=p.id`)).rows[0];
    expect(stored).toMatchObject({ full_name: 'Synthetic Patient', total_paid_amount: '0.30',
      current_due_amount: '9.70', patient_id: 'audit_patient', room_id: 'audit_room', bed_id: 'audit_bed', attendant: 'Synthetic Attendant',
      photo_data_url: 'data:image/png;base64,c3ludGhldGlj' });
    expect((await query('SELECT SUM(amount)::text AS amount, COUNT(*)::int AS count FROM payments')).rows[0]).toEqual({ amount: '0.30', count: 2 });
    expect((await query('SELECT kind,payload FROM attendance_records ORDER BY kind')).rows).toEqual([
      { kind: 'attendance', payload: { isPresent: true } },
      { kind: 'attendant_attendance', payload: { attendant_0: { isPresent: true } } },
    ]);
    const pricing = Object.fromEntries((await query("SELECT settings_key,settings_value FROM system_settings WHERE category='pricing'")).rows
      .map((row) => [row.settings_key, row.settings_value]));
    expect(pricing).toEqual({ generalRoom: 10 });
    expect((await query("SELECT current_value FROM system_counters WHERE counter_name='registrationNumber'")).rows[0].current_value).toBe('12');
  });
  it('reruns without duplicate ledger, stay or attendance records and never changes historical payment timestamps', async () => {
    await run();
    const before = (await query('SELECT * FROM payments ORDER BY id')).rows;
    const again = await run();
    expect(again.payments).toMatchObject({ imported: 0, updated: 0, unchanged: 2, failed: 0 });
    expect((await query('SELECT * FROM payments ORDER BY id')).rows).toEqual(before);
    expect((await query(`SELECT (SELECT COUNT(*)::int FROM stays) AS stays,
      (SELECT COUNT(*)::int FROM attendance_records) AS attendance,
      (SELECT COUNT(*)::int FROM patient_attendants) AS attendants`)).rows[0]).toEqual({ stays: 1, attendance: 2, attendants: 1 });
  });
  it('dry run executes constraints and reconciliation then leaves the database empty', async () => {
    const stats = await run(true);
    expect(stats.committed).toBe(false);
    expect(stats.financials.dbTotalPayments).toBe(0.3);
    expect((await query('SELECT COUNT(*)::int AS count FROM patients')).rows[0].count).toBe(0);
    expect((await query('SELECT COUNT(*)::int AS count FROM payments')).rows[0].count).toBe(0);
    expect((await query('SELECT COUNT(*)::int AS count FROM system_settings')).rows[0].count).toBe(0);
  });
  it('collects missing-reference and date failures then rolls back the whole import', async () => {
    fixture.stays.missing_patient = { ...fixture.stays.audit_stay, patientId: 'not_a_patient' };
    fixture.stays.missing_room = { ...fixture.stays.audit_stay, roomId: 'not_a_room' };
    fixture.attendance.daily['2026-02-30'] = { audit_patient: { isPresent: false } };
    fixture.attendance.daily['2026-01-01'].not_a_patient = { isPresent: true };
    fixture.payments.missing_patient = { ...fixture.payments.audit_pay_2, id: 'missing_patient', patientId: 'not_a_patient' };
    const stats = await run();
    expect(stats.stays).toMatchObject({ processed: 3, imported: 1, failed: 2, missingPatientRefs: 1 });
    expect(stats.attendance).toMatchObject({ processed: 4, imported: 2, failed: 2 });
    expect(stats.payments).toMatchObject({ processed: 3, imported: 2, failed: 1, missingPatientRefs: 1 });
    expect(stats.committed).toBe(false);
    expect((await query('SELECT COUNT(*)::int AS count FROM stays')).rows[0].count).toBe(0);
    expect((await query('SELECT COUNT(*)::int AS count FROM payments')).rows[0].count).toBe(0);
  });
  it('recovers from duplicate registration SQL failure and does not count the rejected patient as a valid reference', async () => {
    fixture.patients.duplicate_registration = { ...fixture.patients.audit_patient };
    fixture.stays.rejected_patient = { ...fixture.stays.audit_stay, patientId: 'duplicate_registration' };
    const stats = await run();
    expect(stats.patients).toMatchObject({ processed: 2, imported: 1, failed: 1 });
    expect(stats.stays).toMatchObject({ processed: 2, imported: 1, failed: 1 });
    expect(stats.payments.imported).toBe(2);
    expect(stats.warnings.join(' ')).toContain('23505');
    expect(stats.committed).toBe(false);
    expect((await query('SELECT COUNT(*)::int AS count FROM patients')).rows[0].count).toBe(0);
  });
  it('rolls back an entire patient and its attendants if a nested attendant fails', async () => {
    fixture.patients.audit_patient.attendants.push({ name: 'x'.repeat(256) });
    const stats = await run();
    expect(stats.patients).toMatchObject({ imported: 0, failed: 1 });
    expect(stats.attendants).toMatchObject({ processed: 2, imported: 0, failed: 2 });
    expect(stats.stays.missingPatientRefs).toBe(1);
    expect((await query('SELECT COUNT(*)::int AS count FROM patient_attendants')).rows[0].count).toBe(0);
    expect((await query('SELECT COUNT(*)::int AS count FROM patients')).rows[0].count).toBe(0);
  });
  it('rejects changed historical payment amounts instead of silently overwriting them', async () => {
    await run();
    fixture.payments.copied_key.amount = '1.10';
    fixture.paymentHistory.original_key.amount = '1.10';
    const stats = await run();
    expect(stats.payments).toMatchObject({ imported: 0, updated: 0, unchanged: 1, failed: 1 });
    expect((await query("SELECT amount FROM payments WHERE id='audit_pay_1'")).rows[0].amount).toBe('0.10');
  });
  it('rejects conflicting duplicate identities inside one export and incomplete legacy stubs', async () => {
    fixture.paymentHistory.original_key.amount = '1.00';
    fixture.payments.incomplete_stub = { transactionId: 'synthetic-stub' };
    const stats = await run();
    expect(stats.payments).toMatchObject({ processed: 3, imported: 1, failed: 2, deduplicated: 1 });
    expect(stats.committed).toBe(false);
    expect((await query('SELECT id FROM payments')).rows).toEqual([]);
  });
  it('rejects invalid patient financial values and dates without creating fabricated demographics', async () => {
    fixture.patients.bad_money = { ...fixture.patients.audit_patient, registrationNumber: 'OTHER', totalPaidAmount: '12abc' };
    fixture.patients.bad_date = { ...fixture.patients.audit_patient, registrationNumber: 'OTHER2', dateOfBirth: '1990-02-30' };
    fixture.patients.no_dob = { ...fixture.patients.audit_patient, registrationNumber: 'OTHER3', dateOfBirth: undefined };
    const stats = await run();
    expect(stats.patients).toMatchObject({ processed: 4, imported: 1, failed: 3 });
    expect(stats.committed).toBe(false);
    expect((await query('SELECT id FROM patients')).rows).toEqual([]);
  });
  it('scopes financial reconciliation to source identities rather than unrelated pre-existing records', async () => {
    await run();
    await query("INSERT INTO payments(id,patient_id,amount,payment_date) VALUES('unrelated_payment','audit_patient',999,NOW())");
    const stats = await run();
    expect(stats.financials.dbTotalPayments).toBe(0.3);
    expect((await query('SELECT SUM(amount)::text AS total FROM payments')).rows[0].total).toBe('999.30');
  });
  it('attaches occupied bed references only after their patient and active stay exist', async () => {
    Object.assign(fixture.rooms.audit_room.beds.audit_bed, { status: 'occupied',
      currentPatientId: 'audit_patient', currentStayId: 'audit_stay' });
    const stats = await run();
    expect(stats.warnings).toEqual([]);
    expect(stats.committed).toBe(true);
    expect((await query('SELECT current_patient_id,current_stay_id,status FROM room_beds')).rows[0]).toEqual({
      current_patient_id: 'audit_patient', current_stay_id: 'audit_stay', status: 'occupied',
    });
  });
  it('rolls back dangling or completed occupied-bed assignments rather than leaving an inconsistent occupancy', async () => {
    Object.assign(fixture.rooms.audit_room.beds.audit_bed, { status: 'occupied',
      currentPatientId: 'audit_patient', currentStayId: 'audit_stay' });
    fixture.stays.audit_stay.status = 'completed';
    const stats = await run();
    expect(stats.beds.assignmentFailures).toBe(1);
    expect(stats.committed).toBe(false);
    expect((await query('SELECT COUNT(*)::int AS count FROM room_beds')).rows[0].count).toBe(0);
  });
  it('preserves an embedded-only legacy refund and infers its parent patient relationship', async () => {
    fixture.patients.audit_patient.payments = [{ id: 'embedded_refund', amount: '-0.05',
      method: 'cash', date: '2026-01-01T23:00:00-05:00' }];
    const stats = await run();
    expect(stats.warnings).toEqual([]);
    expect(stats.committed).toBe(true);
    expect(stats.financials.sourceTotalPayments).toBe(0.25);
    expect((await query("SELECT patient_id,type,amount FROM payments WHERE id='embedded_refund'")).rows[0]).toEqual({
      patient_id: 'audit_patient', type: 'refund', amount: '-0.05',
    });
  });
  it('rejects a bed identity reused across rooms and rolls back both room imports', async () => {
    fixture.rooms.other_room = { roomNumber: 'T-102', roomType: 'general',
      beds: { audit_bed: { bedLabel: 'T-2' } } };
    const stats = await run();
    expect(stats.beds.failed).toBe(1);
    expect(stats.committed).toBe(false);
    expect((await query('SELECT COUNT(*)::int AS count FROM rooms')).rows[0].count).toBe(0);
  });
  it('does not silently commit a source with unsupported photos or ERP branches', async () => {
    fixture.unknown_erp = { synthetic_item: { name: 'Synthetic Item' } };
    fixture.patient_photos = { synthetic_photo: { data: 'synthetic' } };
    const stats = await run();
    expect(stats.warnings.filter((warning) => warning.includes('Unsupported nonempty export branch'))).toHaveLength(2);
    expect(stats.committed).toBe(false);
    expect((await query('SELECT COUNT(*)::int AS count FROM patients')).rows[0].count).toBe(0);
  });
  it('recovers after a fatal user-identity import error without retaining earlier writes', async () => {
    fixture.users.duplicate_email = { ...fixture.users.audit_author };
    await expect(run()).rejects.toMatchObject({ code: '23505' });
    expect((await query('SELECT COUNT(*)::int AS count FROM users')).rows[0].count).toBe(0);
    delete fixture.users.duplicate_email;
    expect((await run()).committed).toBe(true);
  });
  it('supports map attendants, array beds and direct date attendance branches', async () => {
    fixture.patients.audit_patient.attendants = { first: fixture.patients.audit_patient.attendants[0] };
    fixture.rooms.audit_room.beds = [{ id: 'audit_bed', bedLabel: 'T-1' }];
    fixture.attendance = fixture.attendance.daily;
    const stats = await run();
    expect(stats.warnings).toEqual([]);
    expect(stats.committed).toBe(true);
    expect(stats.beds.imported).toBe(1);
    expect(stats.attendants.imported).toBe(1);
    expect(stats.attendance.imported).toBe(2);
  });
  it('does not invent a patient name when a required legacy field is missing', async () => {
    delete fixture.patients.audit_patient.fullName;
    const stats = await run();
    expect(stats.patients.failed).toBe(1);
    expect(stats.committed).toBe(false);
    expect((await query('SELECT COUNT(*)::int AS count FROM patients')).rows[0].count).toBe(0);
  });
  it.each(['same_transaction', 'MANUAL_ONLINE'])('preserves distinct legacy split receipts sharing reference %s (migration 009)', async transactionId => {
    fixture.payments.copied_key.transactionId = transactionId;
    fixture.paymentHistory.original_key.transactionId = transactionId;
    fixture.payments.audit_pay_2.transactionId = transactionId;
    const stats = await run();
    expect(stats.payments.failed).toBe(0);
    expect(stats.committed).toBe(true);
    expect((await query('SELECT COUNT(*)::int AS count, SUM(amount)::text AS total FROM payments')).rows[0]).toEqual({ count: 2, total: '0.30' });
    expect((await run()).committed).toBe(true);
    expect((await query('SELECT COUNT(*)::int AS count FROM payments')).rows[0].count).toBe(2);
  });
  it('reimports corrected non-ledger source fields instead of silently retaining stale profile and stay values', async () => {
    await run();
    fixture.patients.audit_patient.contactNumber = '0000000000';
    fixture.patients.audit_patient.allergies = 'Synthetic allergy';
    fixture.rooms.audit_room.maxAttendants = 8;
    fixture.rooms.audit_room.notes = 'Synthetic source correction';
    fixture.stays.audit_stay.durationDays = 11;
    fixture.stays.audit_stay.extensions = [{ days: 1, reason: 'Synthetic correction' }];
    expect((await run()).committed).toBe(true);
    expect((await query('SELECT contact_number,allergies FROM patients')).rows[0]).toEqual({
      contact_number: '0000000000', allergies: 'Synthetic allergy',
    });
    expect((await query('SELECT max_attendants,notes FROM rooms')).rows[0]).toEqual({
      max_attendants: 8, notes: 'Synthetic source correction',
    });
    expect((await query('SELECT duration_days,extensions FROM stays')).rows[0]).toEqual({
      duration_days: 11, extensions: [{ days: 1, reason: 'Synthetic correction' }],
    });
  });
  it('imports a maximum-length patient identity with stable schema-compatible attendant IDs', async () => {
    const patientId = 'p'.repeat(64);
    fixture = JSON.parse(JSON.stringify(fixture).replaceAll('audit_patient', patientId));
    expect((await run()).committed).toBe(true);
    const attendants = (await query('SELECT id,patient_id FROM patient_attendants')).rows;
    expect(attendants).toHaveLength(1);
    expect(attendants[0].patient_id).toBe(patientId);
    expect(attendants[0].id).toHaveLength(64);
    expect((await run()).committed).toBe(true);
    expect((await query('SELECT id,patient_id FROM patient_attendants')).rows).toEqual(attendants);
  });
  it('does not manufacture imported stay or receipt cycles from placement timestamps', async () => {
    expect((await run()).committed).toBe(true);
    expect((await query('SELECT cycle_id FROM stays')).rows).toEqual([{ cycle_id: null }]);
    expect((await query('SELECT cycle_id FROM payments ORDER BY id')).rows).toEqual([{ cycle_id: null }, { cycle_id: null }]);
    const before = (await query('SELECT id,cycle_id,payment_date,amount FROM payments ORDER BY id')).rows;
    expect((await run()).committed).toBe(true);
    expect((await query('SELECT id,cycle_id,payment_date,amount FROM payments ORDER BY id')).rows).toEqual(before);
  });
  it('uses an imported snapshot cycle when explicit identity is absent and preserves source conflicts for review', async () => {
    fixture.stays.audit_stay.patientSnapshot = { admissionDate: 'original-admission' };
    expect((await run()).committed).toBe(true);
    expect((await query('SELECT cycle_id FROM stays')).rows[0].cycle_id).toBe('original-admission');
    fixture.stays.audit_stay.cycleId = 'conflicting-explicit';
    expect((await run()).committed).toBe(true);
    expect((await query('SELECT cycle_id,patient_snapshot,total_cost FROM stays')).rows[0]).toMatchObject({
      cycle_id: 'conflicting-explicit', patient_snapshot: { admissionDate: 'original-admission' }, total_cost: '10.00',
    });
  });
  it('reconciliation import does not put account-wide legacy receipts into the current frozen invoice', async () => {
    await run();
    const current = String(Date.parse('2026-01-01T10:00:00.000Z'));
    await query('UPDATE patients SET admission_balances=$1::jsonb WHERE id=$2', [JSON.stringify({
      [current]: { total: 10, finalized: true }, historical: { total: 20, finalized: true },
    }), 'audit_patient']);
    fixture.payments.new_historical = { id: 'new_historical', patientId: 'audit_patient', cycleId: 'historical', amount: '0.40', date: 1767261600000 };
    expect((await run(false, true)).committed).toBe(true);
    const patient = (await query('SELECT total_paid_amount,current_due_amount,admission_balances FROM patients')).rows[0];
    expect(patient).toMatchObject({ total_paid_amount: '0.00', current_due_amount: '10.00', admission_balances: {
      [current]: { total: 10, paid: 0, reconciliationRequired: true }, historical: { total: 20, paid: 0.4, due: 19.6 },
    } });
    expect((await query('SELECT sum(amount)::text AS net,count(*)::int AS count FROM payments')).rows[0]).toEqual({ net: '0.70', count: 3 });
    const before = (await query('SELECT id,cycle_id,amount,payment_date FROM payments ORDER BY id')).rows;
    expect((await run(false, true)).committed).toBe(true);
    expect((await query('SELECT id,cycle_id,amount,payment_date FROM payments ORDER BY id')).rows).toEqual(before);
    expect((await query('SELECT total_cost FROM stays')).rows[0].total_cost).toBe('10.00');
  });
  it('does not silently absorb distinct receipt IDs sharing a reference and amount in reconciliation mode', async () => {
    fixture.payments.copied_key.transactionId = 'SHARED-REFERENCE';
    fixture.paymentHistory.original_key.transactionId = 'SHARED-REFERENCE';
    await run();
    fixture.payments.other_source_id = { ...fixture.payments.copied_key, id: 'other_source_id' };
    const stats = await run(false, true);
    expect(stats.reconciliation?.payments.conflicting).toBe(1);
    expect(stats.payments.failed).toBe(1);
    expect((await query('SELECT sum(amount)::text AS net,count(*)::int AS count FROM payments')).rows[0]).toEqual({ net: '0.30', count: 2 });
  });
  it('preserves a source receiptCycle identity in normal imports and rejects contradictory legacy copies', async () => {
    fixture.payments.copied_key.receiptCycle = 'source-admission';
    fixture.paymentHistory.original_key.receiptCycle = 'source-admission';
    expect((await run()).committed).toBe(true);
    expect((await query("SELECT cycle_id FROM payments WHERE id='audit_pay_1'")).rows[0].cycle_id).toBe('source-admission');
    expect((await run()).committed).toBe(true);
    fixture.paymentHistory.original_key.cycleId = 'contradictory';
    const rejected = await run();
    expect(rejected.committed).toBe(false);
    expect(rejected.payments.failed).toBe(1);
    expect((await query("SELECT cycle_id,amount FROM payments WHERE id='audit_pay_1'")).rows[0]).toEqual({ cycle_id: 'source-admission', amount: '0.10' });
  });
});
