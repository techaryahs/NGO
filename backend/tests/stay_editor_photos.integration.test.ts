import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { pool, query } from '../src/db/index.js';
import { runMigrations } from '../src/db/migrate.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

describe.skipIf(process.env.RUN_PG_INTEGRATION !== '1')('stay editor photo and patient saves on live PostgreSQL', () => {
  const app = buildApp({ logger: false });
  const patientId = 'editor-p';
  const stayId = `s_${'a'.repeat(63)}`;
  const stayKey = `stay_${stayId}_0`;
  const person = { id: 'editor-attendant', name: 'Synthetic helper', relation: 'Family' };
  const photo = { data: 'data:image/png;base64,AAECA/8=', contentType: 'image/png', version: 1 };
  const send = (method: any, url: string, payload?: any) => app.inject({ method, url: `/api${url}`,
    headers: { authorization: `Bearer ${signedTestToken()}` }, payload });
  const photoUrl = (key: string, id = patientId) => `/photos/patientPhotos/${id}/${key}`;
  const patient = (id = patientId) => ({ id, fullName: 'Synthetic Editor', dateOfBirth: '1990-01-01',
    gender: 'Other', contactNumber: '000', emergencyContact: '000', emergencyContactName: 'Synthetic',
    medicalCondition: 'Synthetic', admissionDate: '2026-10-01', registrationDate: '2026-10-01', attendants: [person] });
  async function create(withStay = false) {
    const result = await send('POST', '/patients/register', { ...patient(), ...(withStay ? { stays: [{
      id: stayId, roomId: 'lobby:2D Editor', roomNumber: '2D Editor', roomType: 'lobby', durationDays: 7,
      admissionDate: '2026-10-01' }] } : {}) });
    expect(result.statusCode, result.body).toBe(201);
  }
  const editPayload = (snapshot: Record<string, any>) => Object.fromEntries(Object.entries(snapshot).filter(([key]) =>
    !['totalPaidAmount', 'currentDueAmount', 'refundDueAmount', 'totalRefundDueAmount', 'totalRefundedAmount',
      'admissionBalances', 'stayBillingUpdates', 'advanceBilledAmount', 'attendanceCharges', 'billingAmountOverride',
      'totalPresentDays', 'totalAbsentDays'].includes(key)));
  beforeAll(async () => {
    if (process.env.NODE_ENV !== 'test' || process.env.POSTGRES_HOST !== '127.0.0.1' ||
        process.env.POSTGRES_PORT !== '55439' || process.env.POSTGRES_DB !== 'ngo_audit_workflows') {
      throw new Error('Refusing non-disposable stay-editor database');
    }
    const identity = (await query("SELECT current_database() AS db,inet_server_port() AS port,current_setting('server_version_num')::int AS version")).rows[0];
    expect(identity).toMatchObject({ db: 'ngo_audit_workflows', port: 55439 });
    expect(identity.version).toBeGreaterThanOrEqual(160000);
    expect(identity.version).toBeLessThan(170000);
    await runMigrations();
    expect(stayKey).toHaveLength(72);
  }, 30000);
  beforeEach(async () => {
    installTestFirebaseKeys();
    await query('TRUNCATE users,rooms,patients,pending_photos CASCADE');
    await query("INSERT INTO users(id,email,name,role) VALUES('test-uid-admin','admin@ngo.test','Synthetic Admin','admin')");
  });
  afterAll(async () => { await app.close(); await pool.end(); });
  it('P1 production-shaped 72-character attendant photo key supports PUT, GET and DELETE', async () => {
    await create();
    const url = photoUrl(`attendants/${stayKey}`);
    const put = await send('PUT', url, photo);
    expect(put.statusCode, put.body).toBe(200);
    const get = await send('GET', url);
    expect(get.statusCode, get.body).toBe(200);
    expect(get.json()).toMatchObject({ ...photo, photoType: 'attendant', patientId });
    expect((await send('DELETE', url)).statusCode).toBe(200);
    expect((await send('GET', url)).statusCode).toBe(404);
    expect((await query('SELECT photo_ref FROM patient_photos')).rows).toHaveLength(0);
  });
  it.each(['attendants/0', 'patient'])('P2 unchanged %s PUT/GET succeeds', async key => {
    await create();
    const put = await send('PUT', photoUrl(key), photo);
    expect(put.statusCode, put.body).toBe(200);
    const get = await send('GET', photoUrl(key));
    expect(get.statusCode, get.body).toBe(200);
    expect(get.json().data).toBe(photo.data);
  });
  it.each([`attendants/${'a'.repeat(161)}`, 'attendants/bad.name'])('P3 invalid key %s is rejected by every handler', async key => {
    for (const method of ['PUT', 'GET', 'DELETE']) {
      const response = await send(method, photoUrl(key), method === 'PUT' ? photo : undefined);
      expect(response.statusCode, response.body).toBe(400);
    }
    expect((await query('SELECT photo_ref FROM patient_photos UNION ALL SELECT photo_ref FROM pending_photos')).rows).toHaveLength(0);
  });
  it('patient-id cap and literal patient branch remain unchanged', async () => {
    for (const url of [photoUrl('patient', 'p'.repeat(65)), photoUrl('patientx')]) {
      for (const method of ['PUT', 'GET', 'DELETE']) {
        const response = await send(method, url, method === 'PUT' ? photo : undefined);
        expect(response.statusCode, response.body).toBe(400);
      }
    }
  });
  it('the exact new attendant cap fits the unchanged database full-ref limit', async () => {
    const id = 'p'.repeat(64);
    const ref = `patientPhotos/${id}/attendants/${'a'.repeat(160)}`;
    expect(ref).toHaveLength(250);
    const put = await send('PUT', `/photos/${ref}`, photo);
    expect(put.statusCode, put.body).toBe(200);
    expect((await send('GET', `/photos/${ref}`)).statusCode).toBe(200);
    expect((await send('DELETE', `/photos/${ref}`)).statusCode).toBe(200);
  });
  it.each(['patient', 'attendants/0', `attendants/${stayKey}`])('P4 staging and adoption work end to end for %s', async key => {
    const url = photoUrl(key);
    const ref = `patientPhotos/${patientId}/${key}`;
    const put = await send('PUT', url, photo);
    expect(put.statusCode, put.body).toBe(200);
    expect((await send('GET', url)).json().data).toBe(photo.data);
    expect((await query('SELECT photo_ref FROM pending_photos WHERE photo_ref=$1', [ref])).rows).toHaveLength(1);
    await create();
    expect((await query('SELECT photo_ref FROM pending_photos WHERE photo_ref=$1', [ref])).rows).toHaveLength(0);
    expect((await query('SELECT photo_ref FROM patient_photos WHERE photo_ref=$1', [ref])).rows).toHaveLength(1);
    const get = await send('GET', url);
    expect(get.statusCode, get.body).toBe(200);
    expect(get.json().data).toBe(photo.data);
    expect((await send('DELETE', url)).statusCode).toBe(200);
    expect((await send('GET', url)).statusCode).toBe(404);
  });
  async function identity() {
    return (await query(`SELECT p.status,p.admission_date::text,p.discharge_date::text,s.cycle_id
      FROM patients p JOIN stays s ON s.patient_id=p.id WHERE p.id=$1 AND s.id=$2`, [patientId, stayId])).rows[0];
  }
  async function editorSequence(discharged: boolean) {
    await create(true);
    if (discharged) {
      await query("UPDATE stays SET status='completed',completed_at='2026-10-03',patient_snapshot=jsonb_set(patient_snapshot,'{attendants}',$2::jsonb) WHERE id=$1", [stayId, JSON.stringify([person])]);
      await query("UPDATE patients SET status='discharged',discharge_date='2026-10-03',exit_date='2026-10-03',room_id=NULL,room_number=NULL,floor=NULL,lobby=NULL,bed_ids='[]',bed_labels='[]' WHERE id=$1", [patientId]);
    }
    const before = await identity();
    const get = await send('GET', `/patients/${patientId}`);
    expect(get.statusCode, get.body).toBe(200);
    const snapshot = get.json();
    if (!discharged) expect(snapshot.floor).toBe(2);
    const ref = `patientPhotos/${patientId}/attendants/${stayKey}`;
    const putPhoto = await send('PUT', `/photos/${ref}`, photo);
    // Continue the full sequence even if the old photo cap rejects the first step,
    // so pre-batch runs also demonstrate the independent stale-version blockade.
    const putStay = await send('PUT', `/stays/${stayId}`, { notes: 'Stay editor maintenance' });
    const afterStay = (await query('SELECT version FROM patients WHERE id=$1', [patientId])).rows[0];
    expect(afterStay.version).toBeGreaterThan(snapshot.version);
    const attendants = snapshot.attendants.map((att: any) => ({ ...att, photoRef: ref,
      ...(discharged ? { mobileNumber: '1234567890' } : {}) }));
    const putPatient = await send('PUT', `/patients/${patientId}`, { ...editPayload(snapshot), attendants });
    const outcomes = { photo: putPhoto.statusCode, stay: putStay.statusCode, patient: putPatient.statusCode,
      patientMessage: putPatient.json().message ?? null };
    console.log(discharged ? 'S2_EDITOR_SEQUENCE' : 'S1_EDITOR_SEQUENCE', JSON.stringify(outcomes));
    expect(outcomes).toEqual({ photo: 200, stay: 200, patient: 200, patientMessage: null });
    expect((await send('GET', `/photos/${ref}`)).json().data).toBe(photo.data);
    expect(await identity()).toEqual(before);
    if (discharged) {
      expect(putPatient.json().attendants[0].mobileNumber).toBe('1234567890');
      const saved = (await query('SELECT patient_snapshot FROM stays WHERE id=$1', [stayId])).rows[0].patient_snapshot.attendants[0];
      expect(Object.hasOwn(saved, 'startDate')).toBe(false);
    }
  }
  it('S1 active stay-editor sequence accepts a long photo key and its own stale legacy version', async () => {
    await editorSequence(false);
  });
  it('S2 discharged stay-editor sequence preserves dates, status, cycle and undated snapshot attendant', async () => {
    await editorSequence(true);
  });
});
