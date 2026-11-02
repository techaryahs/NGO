import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { pool, query } from '../src/db/index.js';
import { runMigrations } from '../src/db/migrate.js';
import { eligibleAttendant } from '../src/services/attendant_roster.js';
import { dayKey } from '../src/services/billing.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

describe.skipIf(process.env.RUN_PG_INTEGRATION !== '1')('episode attendant start dates on live PostgreSQL', () => {
  const app = buildApp({ logger: false });
  const today = dayKey(Date.now());
  const relative = (days: number) => new Date(Date.parse(`${today}T00:00:00Z`) + days * 86400000).toISOString().slice(0, 10);
  const admission = relative(-6);
  const person = { id: 'episode-helper', name: 'Synthetic helper', relation: 'Family' };
  const send = (method: any, url: string, payload?: any) => app.inject({ method, url: `/api${url}`,
    headers: { authorization: `Bearer ${signedTestToken()}` }, payload });
  const roster = async (stay = 'episode-stay') => (await query('SELECT patient_snapshot FROM stays WHERE id=$1', [stay])).rows[0].patient_snapshot.attendants;
  const patient = (attendants: any[] = [person], date = admission) => ({ id: 'episode-p', fullName: 'Synthetic Episode',
    dateOfBirth: '1990-01-01', gender: 'Other', contactNumber: '000', emergencyContact: '000',
    emergencyContactName: 'Synthetic', medicalCondition: 'Synthetic', admissionDate: date, registrationDate: date, attendants });
  const stay = (date = admission) => ({ id: 'episode-stay', roomId: 'lobby:2D Episode', roomNumber: '2D Episode',
    roomType: 'lobby', durationDays: 7, admissionDate: date });
  async function create(attendants: any[] = [person], date = admission, route = '/patients/register') {
    const result = await send('POST', route, { ...patient(attendants, date), stays: [stay(date)] });
    expect(result.statusCode, result.body).toBe(201);
    return result;
  }
  async function mark(date: string, attendant = person) {
    const result = await send('POST', '/attendance', { patientId: 'episode-p', date, kind: 'attendant_attendance',
      payload: { [attendant.id]: { attendantId: attendant.id, attendantName: attendant.name, status: 'Present' } } });
    expect(result.statusCode, result.body).toBe(200);
  }
  beforeAll(async () => {
    if (process.env.NODE_ENV !== 'test' || process.env.POSTGRES_HOST !== '127.0.0.1' ||
        process.env.POSTGRES_PORT !== '55439' || process.env.POSTGRES_DB !== 'ngo_audit_workflows') {
      throw new Error('Refusing non-disposable attendant database');
    }
    const identity = (await query("SELECT current_database() AS db,inet_server_port() AS port,current_setting('server_version_num')::int AS version")).rows[0];
    expect(identity).toMatchObject({ db: 'ngo_audit_workflows', port: 55439 });
    expect(identity.version).toBeGreaterThanOrEqual(160000);
    expect(identity.version).toBeLessThan(170000);
    await runMigrations();
  }, 30000);
  beforeEach(async () => {
    installTestFirebaseKeys();
    await query('TRUNCATE users,rooms,patients CASCADE');
    await query("INSERT INTO users(id,email,name,role) VALUES('test-uid-admin','admin@ngo.test','Synthetic Admin','admin')");
  });
  afterAll(async () => { await app.close(); await pool.end(); });
  it.each(['/patients', '/patients/register'])('A1 backdated create via %s anchors to registration and admits day-1 marks', async route => {
    await create([person], admission, route);
    const saved = (await roster())[0];
    expect(saved.startDate).toBe(admission);
    expect(eligibleAttendant(saved, admission)).toBe(true);
    await mark(admission);
  });
  it('A2 same-day create anchors to today and admission', async () => {
    await create([person], today);
    expect((await roster())[0].startDate).toBe(today);
  });
  it('A3 PUT-add without a date anchors to the backdated episode (Ashish)', async () => {
    await create([]);
    const result = await send('PUT', '/patients/episode-p', { attendants: [person] });
    expect(result.statusCode, result.body).toBe(200);
    expect((await roster())[0].startDate).toBe(admission);
    await mark(admission);
  });
  it('A4 deliberate date is stored and before-admission dates return 400', async () => {
    await create([]);
    const sent = relative(-3);
    const valid = await send('PUT', '/patients/episode-p', { attendants: [{ ...person, startDate: sent }] });
    expect(valid.statusCode, valid.body).toBe(200);
    expect((await roster())[0].startDate).toBe(sent);
    const before = await roster();
    const invalid = await send('PUT', '/patients/episode-p', { attendants: [{ id: 'new-helper', name: 'Before admission', startDate: relative(-7) }] });
    expect(invalid.statusCode, invalid.body).toBe(400);
    expect(await roster()).toEqual(before);
  });
  it('A4 discharged historical stay honours an in-bounds date and rejects after-discharge dates', async () => {
    await create();
    const checkout = relative(-1);
    await query("UPDATE stays SET status='completed',completed_at=$1 WHERE patient_id='episode-p'", [checkout]);
    await query("UPDATE patients SET status='discharged',discharge_date=$1 WHERE id='episode-p'", [checkout]);
    // A newly presented historical attendant is not grandfathered by the old snapshot.
    await query("UPDATE stays SET patient_snapshot=jsonb_set(patient_snapshot,'{attendants}','[]') WHERE patient_id='episode-p'");
    const row = (await query("SELECT * FROM patients WHERE id='episode-p'")).rows[0];
    const payload = { ...stay(), patientId: 'episode-p', status: 'completed', completedAt: checkout,
      cycleId: String(new Date(row.admission_date).getTime()), patientSnapshot: { attendants: [{ ...person, startDate: relative(-3) }] } };
    const valid = await send('POST', '/stays', { ...payload, id: 'historical-valid' });
    expect(valid.statusCode, valid.body).toBe(201);
    expect((await roster('historical-valid'))[0].startDate).toBe(relative(-3));
    // A different identity is new and must satisfy the discharge bound.
    const invalid = await send('POST', '/stays', { ...payload, id: 'historical-invalid',
      patientSnapshot: { attendants: [{ id: 'other-helper', name: 'Late', startDate: relative(1) }] } });
    expect(invalid.statusCode, invalid.body).toBe(400);
    expect((await query("SELECT id FROM stays WHERE id='historical-invalid'")).rows).toHaveLength(0);
  });
  it.each([relative(-4), undefined])('A5 name/photo edits preserve stored startDate %s byte-identically', async startDate => {
    await create();
    const original = [{ ...person, ...(startDate ? { startDate } : {}) }];
    await query("UPDATE stays SET patient_snapshot=jsonb_set(patient_snapshot,'{attendants}',$1::jsonb) WHERE id='episode-stay'", [JSON.stringify(original)]);
    const result = await send('PUT', '/patients/episode-p', { attendants: [{ ...person, name: 'Corrected helper', photoRef: 'synthetic/photo' }] });
    expect(result.statusCode, result.body).toBe(200);
    const saved = (await roster())[0];
    expect(saved.name).toBe('Corrected helper');
    expect(saved.photoRef).toBe('synthetic/photo');
    expect(Object.hasOwn(saved, 'startDate')).toBe(Object.hasOwn(original[0], 'startDate'));
    expect(JSON.stringify(saved.startDate)).toBe(JSON.stringify(original[0].startDate));
  });
  it('A6 rejoin anchors carried attendants to the new episode admission', async () => {
    await create();
    await query("UPDATE stays SET patient_snapshot=jsonb_set(patient_snapshot,'{attendants}',$1::jsonb),status='completed',completed_at=$2 WHERE id='episode-stay'",
      [JSON.stringify([{ ...person, startDate: admission }]), relative(-4)]);
    await query("UPDATE patients SET status='discharged',discharge_date=$1 WHERE id='episode-p'", [relative(-4)]);
    const newAdmission = relative(-2);
    const result = await send('POST', '/patients/episode-p/rejoin', { requestId: 'episode-rejoin',
      registrationDate: newAdmission, roomId: 'lobby:2D Rejoin', roomNumber: '2D Rejoin', roomType: 'lobby', exitDate: null, exitDateUnconfirmed: true });
    expect(result.statusCode, result.body).toBe(201);
    expect((await roster('episode-rejoin'))[0].startDate).toBe(newAdmission);
    expect((await roster())[0].startDate).toBe(admission);
  });
  it.each([relative(-4), undefined])('A7 transfer preserves the original startDate %s, never the segment date', async startDate => {
    await create();
    const original = [{ ...person, ...(startDate ? { startDate } : {}) }];
    await query("UPDATE stays SET patient_snapshot=jsonb_set(patient_snapshot,'{attendants}',$1::jsonb) WHERE id='episode-stay'", [JSON.stringify(original)]);
    const result = await send('POST', '/patients/episode-p/transfer', { requestId: 'episode-transfer', expectedStayIds: ['episode-stay'],
      roomId: 'lobby:2D Transfer', roomNumber: '2D Transfer', roomType: 'lobby', shiftedAt: relative(-1) });
    expect(result.statusCode, result.body).toBe(200);
    expect(await roster('episode-transfer')).toEqual(original);
  });
  it('A8 PUT-add with an entry-day echo anchors to episode admission', async () => {
    await create([]);
    const result = await send('PUT', '/patients/episode-p', { attendants: [{ ...person, startDate: today }] });
    expect(result.statusCode, result.body).toBe(200);
    expect((await roster())[0].startDate).toBe(admission);
  });
  it('A9 PUT-add honours a deliberate admission-plus-three date byte-identically', async () => {
    await create([]);
    const chosen = relative(-3);
    const result = await send('PUT', '/patients/episode-p', { attendants: [{ ...person, startDate: chosen }] });
    expect(result.statusCode, result.body).toBe(200);
    expect((await roster())[0].startDate).toBe(chosen);
    const tooEarly = await send('POST', '/attendance', { patientId: 'episode-p', date: admission, kind: 'attendant_attendance',
      payload: { [person.id]: { attendantId: person.id, status: 'Present' } } });
    expect(tooEarly.statusCode, tooEarly.body).toBe(400);
    await mark(chosen);
  });
  it.each(['/patients', '/patients/register'])('A10 backdated create via %s normalizes an entry-day payload echo', async route => {
    await create([{ ...person, startDate: today }], admission, route);
    expect((await roster())[0].startDate).toBe(admission);
  });
  it('standalone continuing stay explicitly preserves dates from the previous snapshot', async () => {
    await create();
    const chosen = relative(-4);
    await query("UPDATE stays SET patient_snapshot=jsonb_set(patient_snapshot,'{attendants}',$1::jsonb),status='completed',completed_at=$2 WHERE id='episode-stay'",
      [JSON.stringify([{ ...person, startDate: chosen }]), relative(-1)]);
    const result = await send('POST', '/stays', { ...stay(relative(-1)), id: 'continuing-stay', patientId: 'episode-p' });
    expect(result.statusCode, result.body).toBe(201);
    expect((await roster('continuing-stay'))[0].startDate).toBe(chosen);
  });
  it('PUT uses the episode admission just written by a registration-date change', async () => {
    await create([]);
    const changedAdmission = relative(-7);
    const result = await send('PUT', '/patients/episode-p', { registrationDate: changedAdmission, attendants: [person] });
    expect(result.statusCode, result.body).toBe(200);
    expect((await roster())[0].startDate).toBe(changedAdmission);
  });
  it('stay mint uses the registration-derived patient admission after correcting a stale row', async () => {
    const created = await send('POST', '/patients', patient());
    expect(created.statusCode, created.body).toBe(201);
    await query("UPDATE patients SET admission_date=$1 WHERE id='episode-p'", [today]);
    const result = await send('POST', '/stays', { ...stay(today), patientId: 'episode-p' });
    expect(result.statusCode, result.body).toBe(201);
    expect((await roster())[0].startDate).toBe(admission);
    expect(dayKey((await query("SELECT admission_date FROM patients WHERE id='episode-p'")).rows[0].admission_date)).toBe(admission);
  });
});
