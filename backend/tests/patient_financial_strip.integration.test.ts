import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { readFile } from 'node:fs/promises';
import { buildApp } from '../src/app.js';
import { pool, query } from '../src/db/index.js';
import { runMigrations } from '../src/db/migrate.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

describe.skipIf(process.env.RUN_PG_INTEGRATION !== '1')('patient financial strip on live PostgreSQL', () => {
  const app = buildApp({ logger: false });
  const patientId = 'strip-p';
  const stayId = `s_${'f'.repeat(63)}`;
  const person = { id: 'original-helper', name: 'Synthetic helper', relation: 'Family' };
  const send = (method: any, url: string, payload?: any) => app.inject({ method, url: `/api${url}`,
    headers: { authorization: `Bearer ${signedTestToken()}` }, payload });
  const bogus = () => ({ totalPaidAmount: 999999, currentDueAmount: 888888, refundDueAmount: 777777,
    totalRefundDueAmount: 666666, totalRefundedAmount: 555555, admissionBalances: { fabricated: { total: 444444, paid: 333333 } },
    advanceBilledAmount: 222222, attendanceCharges: 111111, billingAmountOverride: null,
    totalPresentDays: 999, totalAbsentDays: 888 });
  const row = async () => (await query('SELECT * FROM patients WHERE id=$1', [patientId])).rows[0];
  const financial = async () => (await query(`SELECT json_build_object(
    'total_paid_amount',total_paid_amount,'current_due_amount',current_due_amount,'refund_due_amount',refund_due_amount,
    'total_refund_due_amount',total_refund_due_amount,'total_refunded_amount',total_refunded_amount,
    'admission_balances',admission_balances,'advance_billed_amount',advance_billed_amount,'attendance_charges',attendance_charges,
    'billing_amount_override',billing_amount_override,'total_present_days',total_present_days,'total_absent_days',total_absent_days)::text AS data
    FROM patients WHERE id=$1`, [patientId])).rows[0].data;
  const stayState = async () => (await query('SELECT row_to_json(s)::text AS data FROM stays s WHERE id=$1', [stayId])).rows[0].data;
  const identity = async () => (await query(`SELECT p.status,p.admission_date::text,p.registration_date::text,p.discharge_date::text,
    s.cycle_id FROM patients p JOIN stays s ON s.patient_id=p.id WHERE p.id=$1 AND s.id=$2`, [patientId, stayId])).rows[0];
  beforeAll(async () => {
    if (process.env.NODE_ENV !== 'test' || process.env.POSTGRES_HOST !== '127.0.0.1' ||
        process.env.POSTGRES_PORT !== '55439' || process.env.POSTGRES_DB !== 'ngo_audit_workflows') {
      throw new Error('Refusing non-disposable financial-strip database');
    }
    const identity = (await query("SELECT current_database() AS db,inet_server_port() AS port,current_setting('server_version_num')::int AS version")).rows[0];
    expect(identity).toMatchObject({ db: 'ngo_audit_workflows', port: 55439 });
    expect(identity.version).toBeGreaterThanOrEqual(160000);
    expect(identity.version).toBeLessThan(170000);
    await runMigrations();
  }, 30000);
  beforeEach(async () => {
    installTestFirebaseKeys();
    await query('TRUNCATE users,rooms,patients,pending_photos CASCADE');
    await query("INSERT INTO users(id,email,name,role) VALUES('test-uid-admin','admin@ngo.test','Synthetic Admin','admin')");
    const created = await send('POST', '/patients/register', { id: patientId, fullName: 'Synthetic Strip',
      dateOfBirth: '1990-01-01', gender: 'Other', contactNumber: '000', emergencyContact: '000',
      emergencyContactName: 'Synthetic', medicalCondition: 'Synthetic', admissionDate: '2026-10-01', registrationDate: '2026-10-01',
      attendants: [person], stays: [{ id: stayId, roomId: 'lobby:2D Strip', roomNumber: '2D Strip', roomType: 'lobby',
        durationDays: 7, admissionDate: '2026-10-01' }] });
    expect(created.statusCode, created.body).toBe(201);
  });
  afterAll(async () => { await app.close(); await pool.end(); });
  it('F2 Ashok: discharged editor accepts the real id-less attendant serializer without duplication', async () => {
    await query("UPDATE stays SET status='completed',completed_at='2026-10-03',patient_snapshot=jsonb_set(patient_snapshot,'{attendants}',$2::jsonb) WHERE id=$1", [stayId, JSON.stringify([person])]);
    await query("UPDATE patients SET status='discharged',discharge_date='2026-10-03',exit_date='2026-10-03',room_id=NULL,room_number=NULL,floor=NULL,lobby=NULL,bed_ids='[]',bed_labels='[]' WHERE id=$1", [patientId]);
    const before = await identity();
    const snapshotCount = (JSON.parse(await stayState()).patient_snapshot.attendants as any[]).length;
    const loaded = await row();
    const ref = `patientPhotos/${patientId}/attendants/stay_${stayId}_0`;
    const photo = await send('PUT', `/photos/${ref}`, { data: 'data:image/png;base64,AAECA/8=', contentType: 'image/png' });
    expect(photo.statusCode, photo.body).toBe(200);
    const stay = await send('PUT', `/stays/${stayId}`, { notes: 'Ashok maintenance' });
    expect(stay.statusCode, stay.body).toBe(200);
    const beforeFinancial = await financial();
    // Exactly the Flutter _StayAttendant.toMap shape: no id/startDate/endDate.
    const attendant = { name: person.name, relation: person.relation, age: '32', aadhaarNumber: '',
      photoRef: ref, mobileNumber: '1234567890', isEmergencyContact: false };
    expect(Object.keys(attendant).sort()).toEqual(['name', 'relation', 'age', 'aadhaarNumber', 'photoRef', 'mobileNumber', 'isEmergencyContact'].sort());
    const edited = await send('PUT', `/patients/${patientId}`, { ...bogus(), expectedVersion: loaded.version, attendants: [attendant] });
    console.log('F2_IDLESS_RESULT', JSON.stringify({ status: edited.statusCode, message: edited.json().message ?? null }));
    expect(edited.statusCode, edited.body).toBe(200);
    const people = (await query('SELECT * FROM patient_attendants WHERE patient_id=$1', [patientId])).rows;
    expect(people).toHaveLength(1);
    expect(people[0]).toMatchObject({ name: person.name, mobile_number: '1234567890', photo_ref: ref });
    expect((await query('SELECT count(*)::int AS count FROM patient_attendants WHERE patient_id=$1 AND name=$2', [patientId, person.name])).rows[0].count).toBe(1);
    const saved = JSON.parse(await stayState()).patient_snapshot.attendants;
    expect(saved).toHaveLength(snapshotCount);
    expect(Object.hasOwn(saved[0], 'startDate')).toBe(false);
    expect(await identity()).toEqual(before);
    expect(await financial()).toBe(beforeFinancial);
  });
  it('F1 active editor financials are ignored byte-identically to a control PUT', async () => {
    const initial = await financial();
    const control = await send('PUT', `/patients/${patientId}`, { contactNumber: '1111111111' });
    expect(control.statusCode, control.body).toBe(200);
    const controlFinancial = await financial();
    expect(controlFinancial).toBe(initial);
    const edited = await send('PUT', `/patients/${patientId}`, { ...bogus(), contactNumber: '1111111111' });
    expect(edited.statusCode, edited.body).toBe(200);
    expect((await row()).contact_number).toBe('1111111111');
    expect(await financial()).toBe(controlFinancial);
  });
  it('F3 edit-dialog shape without financial keys retains successful behavior', async () => {
    const initial = await financial();
    const edited = await send('PUT', `/patients/${patientId}`, { fullName: 'Edited Strip', contactNumber: '2222222222',
      notes: 'Edit dialog', address: 'Synthetic address', photoDataUrl: null, photoRef: null });
    expect(edited.statusCode, edited.body).toBe(200);
    expect((await row()).full_name).toBe('Edited Strip');
    expect(await financial()).toBe(initial);
  });
  it('F4 financial-only PUT has no financial effect and increments edit_version', async () => {
    const before = await row();
    const initial = await financial();
    const edited = await send('PUT', `/patients/${patientId}`, { ...bogus(), stayBillingUpdates: {} });
    expect(edited.statusCode, edited.body).toBe(200);
    expect(await financial()).toBe(initial);
    expect((await row()).edit_version).toBe(before.edit_version + 1);
  });
  it('F5 stayBillingUpdates are ignored and no client stay-billing reader remains', async () => {
    const before = await stayState();
    const initial = await financial();
    const edited = await send('PUT', `/patients/${patientId}`, { stayBillingUpdates: { [stayId]: {
      totalCost: 999999, cycleId: '1700000000000', dailyRate: 9999, billableDays: 999,
      billingSummary: { fabricated: true }, completedAt: '2026-10-02' } } });
    expect(edited.statusCode, edited.body).toBe(200);
    expect(await stayState()).toBe(before);
    expect(await financial()).toBe(initial);
    const source = await readFile(new URL('../src/routes/patients.ts', import.meta.url), 'utf8');
    expect(source).not.toMatch(/\(request\.body as any\)\.stayBillingUpdates/);
    expect(source).not.toContain('Billing stay no longer belongs to this patient');
  });
  it.each(['delete-admission', 'Excel-import'])('F6 %s shape applies non-financial edits and ignores financials', async flow => {
    const initial = await financial();
    const payload = flow === 'delete-admission' ? { ...bogus(), fullName: 'After admission deletion' }
      : { advanceBilledAmount: 999999, status: 'active', fullName: 'Imported name' };
    const edited = await send('PUT', `/patients/${patientId}`, payload);
    expect(edited.statusCode, edited.body).toBe(200);
    expect((await row()).full_name).toBe(payload.fullName);
    expect(await financial()).toBe(initial);
  });
});
