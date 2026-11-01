import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { buildApp } from '../src/app.js';
import * as dbModule from '../src/db/index.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';
import { adoptPendingPhotos, cleanupPendingPhotos, startPhotoCleanup } from '../src/services/photo_staging.js';

describe('Photo Staging & Adoption Suite', () => {
  let app: ReturnType<typeof buildApp>;

  // In-memory simulation tables
  let patientsTable: Map<string, any>;
  let patientPhotosTable: Map<string, any>;
  let pendingPhotosTable: Map<string, any>;

  beforeEach(() => {
    vi.restoreAllMocks();
    installTestFirebaseKeys();

    patientsTable = new Map();
    patientPhotosTable = new Map();
    pendingPhotosTable = new Map();

    const mockQuery = vi.fn(async (sql: string, params: unknown[] = []) => {
      const trimmed = sql.trim();

      if (/^(BEGIN|COMMIT|ROLLBACK)/i.test(trimmed)) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('pg_advisory_xact_lock')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('FROM users')) {
        return {
          rows: [{ id: 'admin-1', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1,
        };
      }
      if (trimmed.includes('FROM system_settings')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('system_counters')) {
        return { rows: [{ current_value: '1001' }], rowCount: 1 };
      }

      // Check if patient exists: SELECT 1 FROM patients WHERE id = $1
      if (/^SELECT\s+1\s+FROM\s+patients\s+WHERE\s+id\s*=\s*\$1/i.test(trimmed)) {
        const id = params[0] as string;
        const exists = patientsTable.has(id);
        return { rows: exists ? [{ '?column?': 1 }] : [], rowCount: exists ? 1 : 0 };
      }

      // SELECT * FROM patients WHERE id = $1
      if (/^SELECT\s+\*\s+FROM\s+patients\s+WHERE\s+id\s*=\s*\$1/i.test(trimmed)) {
        const id = params[0] as string;
        const row = patientsTable.get(id);
        return { rows: row ? [row] : [], rowCount: row ? 1 : 0 };
      }

      // INSERT INTO pending_photos ...
      if (trimmed.includes('INSERT INTO pending_photos')) {
        const [photoRef, patientId, kind, contentType, data, version] = params as [string, string, string, string, string, number];
        const row = {
          photo_ref: photoRef,
          patient_id: patientId,
          kind,
          photo_type: kind,
          content_type: contentType,
          data,
          version,
          created_at: new Date(),
          updated_at: new Date(),
        };
        pendingPhotosTable.set(photoRef, row);
        return { rows: [row], rowCount: 1 };
      }

      // INSERT INTO patient_photos ...
      if (trimmed.includes('INSERT INTO patient_photos') && !trimmed.includes('SELECT photo_ref')) {
        const [photoRef, patientId, photoType, contentType, data, version] = params as [string, string, string, string, string, number];
        const row = {
          photo_ref: photoRef,
          patient_id: patientId,
          photo_type: photoType,
          content_type: contentType,
          data,
          version,
          updated_at: new Date(),
        };
        patientPhotosTable.set(photoRef, row);
        return { rows: [row], rowCount: 1 };
      }

      // INSERT INTO patient_photos ... SELECT ... FROM pending_photos WHERE patient_id = $1 (Adoption SQL)
      if (trimmed.includes('INSERT INTO patient_photos') && trimmed.includes('SELECT photo_ref') && trimmed.includes('FROM pending_photos')) {
        const patientId = params[0] as string;
        const adopted: any[] = [];
        for (const [ref, row] of pendingPhotosTable.entries()) {
          if (row.patient_id === patientId) {
            const ppRow = {
              photo_ref: row.photo_ref,
              patient_id: row.patient_id,
              photo_type: row.kind,
              content_type: row.content_type,
              data: row.data,
              version: row.version,
              updated_at: new Date(),
            };
            patientPhotosTable.set(ref, ppRow);
            adopted.push(ppRow);
          }
        }
        return { rows: adopted, rowCount: adopted.length };
      }

      // DELETE FROM pending_photos WHERE patient_id = $1
      if (/^DELETE\s+FROM\s+pending_photos\s+WHERE\s+patient_id\s*=\s*\$1/i.test(trimmed)) {
        const patientId = params[0] as string;
        let deleted = 0;
        for (const [ref, row] of [...pendingPhotosTable.entries()]) {
          if (row.patient_id === patientId) {
            pendingPhotosTable.delete(ref);
            deleted++;
          }
        }
        return { rows: [], rowCount: deleted };
      }

      // DELETE FROM pending_photos WHERE created_at < NOW() - INTERVAL '24 hours'
      if (trimmed.includes('DELETE FROM pending_photos WHERE created_at < NOW() - INTERVAL \'24 hours\'')) {
        let deleted = 0;
        const now = Date.now();
        const cutoff = now - 24 * 60 * 60 * 1000;
        for (const [ref, row] of [...pendingPhotosTable.entries()]) {
          const createdAt = new Date(row.created_at).getTime();
          if (createdAt < cutoff) {
            pendingPhotosTable.delete(ref);
            deleted++;
          }
        }
        return { rows: [], rowCount: deleted };
      }

      // SELECT * FROM pending_photos WHERE patient_id = $1
      if (trimmed.includes('FROM pending_photos WHERE patient_id = $1')) {
        const patientId = params[0] as string;
        const rows = [...pendingPhotosTable.values()].filter(r => r.patient_id === patientId);
        return { rows, rowCount: rows.length };
      }

      // SELECT * FROM patient_photos WHERE photo_ref = $1
      if (trimmed.startsWith('SELECT') && trimmed.includes('FROM patient_photos WHERE photo_ref = $1')) {
        const ref = params[0] as string;
        const row = patientPhotosTable.get(ref);
        return { rows: row ? [row] : [], rowCount: row ? 1 : 0 };
      }

      if (trimmed.startsWith('SELECT') && trimmed.includes('FROM pending_photos WHERE photo_ref = $1')) {
        const row = pendingPhotosTable.get(params[0] as string);
        return { rows: row ? [{ ...row, photo_type: row.kind, updated_at: row.created_at }] : [], rowCount: row ? 1 : 0 };
      }

      if (trimmed.includes('DELETE FROM pending_photos WHERE photo_ref = $1')) {
        const existed = pendingPhotosTable.delete(params[0] as string);
        return { rows: [], rowCount: existed ? 1 : 0 };
      }

      // DELETE FROM patient_photos WHERE photo_ref = $1
      if (trimmed.includes('DELETE FROM patient_photos WHERE photo_ref = $1')) {
        const ref = params[0] as string;
        const existed = patientPhotosTable.delete(ref);
        return { rows: [], rowCount: existed ? 1 : 0 };
      }

      // INSERT INTO patients ...
      if (trimmed.includes('INSERT INTO patients')) {
        const patientId = params[0] as string;
        const row = { id: patientId, full_name: params[1], status: 'active', admission_date: new Date(), registration_date: new Date(), admission_balances: {}, payment_status: 'Paid', total_paid_amount: 0, current_due_amount: 0, version: 1 };
        patientsTable.set(patientId, row);
        return { rows: [row], rowCount: 1 };
      }

      // Stays / Attendants / Attendance queries during registration
      if (trimmed.includes('INSERT INTO patient_attendants')) {
        return { rows: [{ id: params[0], patient_id: params[1], name: params[2] }], rowCount: 1 };
      }
      if (trimmed.includes('SELECT id FROM rooms')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('FROM patient_attendants')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('FROM payments')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('FROM stays')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('UPDATE patients SET registration_fingerprint')) {
        return { rows: [], rowCount: 1 };
      }

      return { rows: [], rowCount: 0 };
    });

    vi.spyOn(dbModule, 'query').mockImplementation(mockQuery as any);
    vi.spyOn(dbModule, 'getClient').mockResolvedValue({
      query: mockQuery,
      release: vi.fn(),
    } as any);

    app = buildApp({ logger: false });
  });

  afterEach(async () => {
    await app.close();
    vi.restoreAllMocks();
  });

  const authHeaders = () => ({
    authorization: `Bearer ${signedTestToken('admin-1')}`,
  });

  // (a) PUT photo, unknown patient → success, no patient_photos row, one staged row
  it('(a) PUT photo, unknown patient -> success, no patient_photos row, one staged row', async () => {
    const unknownId = 'p_unknown_1';
    const res = await app.inject({
      method: 'PUT',
      url: `/api/photos/patientPhotos/${unknownId}/patient`,
      headers: authHeaders(),
      payload: {
        data: 'aGVsbG8=',
        contentType: 'image/jpeg',
        version: 1,
      },
    });

    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body).toMatchObject({
      photoRef: `patientPhotos/${unknownId}/patient`,
      patientId: unknownId,
      photoType: 'patient',
      contentType: 'image/jpeg',
      version: 1,
    });
    expect(body.updatedAt).toBeTypeOf('number');

    // No row in patient_photos
    expect(patientPhotosTable.has(`patientPhotos/${unknownId}/patient`)).toBe(false);
    // Exactly one staged row in pending_photos
    expect(pendingPhotosTable.size).toBe(1);
    const staged = pendingPhotosTable.get(`patientPhotos/${unknownId}/patient`);
    expect(staged).toBeDefined();
    expect(staged.patient_id).toBe(unknownId);
    expect(staged.kind).toBe('patient');
    expect(staged.data).toBe('aGVsbG8=');
  });

  // (b) register that id → photo in patient_photos, staged row gone, GET serves it
  it('(b) register that id -> photo in patient_photos, staged row gone, GET serves it', async () => {
    const patientId = 'p_adopt_1';
    // Stage photo before patient exists
    await app.inject({
      method: 'PUT',
      url: `/api/photos/patientPhotos/${patientId}/patient`,
      headers: authHeaders(),
      payload: { data: 'aGVsbG8=', version: 1 },
    });
    expect(pendingPhotosTable.size).toBe(1);

    // Register patient
    const regRes = await app.inject({
      method: 'POST',
      url: '/api/patients/register',
      headers: authHeaders(),
      payload: {
        id: patientId,
        fullName: 'Test Adopted Patient',
        registrationDate: '2026-01-01',
        dateOfBirth: '1995-01-01',
        gender: 'Female',
        contactNumber: '1234567890',
        emergencyContact: '0987654321',
        emergencyContactName: 'Emergency',
        medicalCondition: 'Healthy',
      },
    });
    expect(regRes.statusCode).toBe(201);

    // Photo now in patient_photos
    expect(patientPhotosTable.has(`patientPhotos/${patientId}/patient`)).toBe(true);
    const inDb = patientPhotosTable.get(`patientPhotos/${patientId}/patient`);
    expect(inDb.data).toBe('aGVsbG8=');
    expect(inDb.photo_type).toBe('patient');

    // Staged row gone
    expect(pendingPhotosTable.has(`patientPhotos/${patientId}/patient`)).toBe(false);
    expect(pendingPhotosTable.size).toBe(0);

    // GET serves it
    const getRes = await app.inject({
      method: 'GET',
      url: `/api/photos/patientPhotos/${patientId}/patient`,
      headers: authHeaders(),
    });
    expect(getRes.statusCode).toBe(200);
    const getBody = JSON.parse(getRes.body);
    expect(getBody).toMatchObject({
      photoRef: `patientPhotos/${patientId}/patient`,
      patientId,
      photoType: 'patient',
      data: 'aGVsbG8=',
    });
  });

  // (c) PUT for an existing patient → unchanged, nothing staged
  it('(c) PUT for an existing patient -> unchanged, nothing staged', async () => {
    const existingId = 'p_existing_1';
    patientsTable.set(existingId, { id: existingId, full_name: 'Existing Patient' });

    const res = await app.inject({
      method: 'PUT',
      url: `/api/photos/patientPhotos/${existingId}/patient`,
      headers: authHeaders(),
      payload: { data: 'ZXhpc3Rpbmc=', version: 2 },
    });

    expect(res.statusCode).toBe(200);
    // Direct in patient_photos
    expect(patientPhotosTable.has(`patientPhotos/${existingId}/patient`)).toBe(true);
    expect(patientPhotosTable.get(`patientPhotos/${existingId}/patient`).data).toBe('ZXhpc3Rpbmc=');
    // Nothing staged in pending_photos
    expect(pendingPhotosTable.size).toBe(0);
  });

  // (d) attendant-kind staged photo adopted identically
  it('(d) attendant-kind staged photo adopted identically', async () => {
    const patientId = 'p_attendant_1';
    // Stage attendant photo before patient exists
    const putRes = await app.inject({
      method: 'PUT',
      url: `/api/photos/patientPhotos/${patientId}/attendants/att_1`,
      headers: authHeaders(),
      payload: { data: 'YXR0ZW5kYW50MQ==', version: 1 },
    });
    expect(putRes.statusCode).toBe(200);
    expect(JSON.parse(putRes.body)).toMatchObject({
      photoRef: `patientPhotos/${patientId}/attendants/att_1`,
      patientId,
      photoType: 'attendant',
    });

    // Verify staged row has kind = 'attendant'
    expect(pendingPhotosTable.has(`patientPhotos/${patientId}/attendants/att_1`)).toBe(true);
    expect(pendingPhotosTable.get(`patientPhotos/${patientId}/attendants/att_1`).kind).toBe('attendant');

    // Create patient via POST /patients
    const createRes = await app.inject({
      method: 'POST',
      url: '/api/patients',
      headers: authHeaders(),
      payload: {
        id: patientId,
        fullName: 'Attendant Parent Patient',
        registrationDate: '2026-01-01',
        dateOfBirth: '1990-01-01',
        gender: 'Male',
        contactNumber: '1234567890',
        emergencyContact: '0987654321',
        emergencyContactName: 'Emergency',
        medicalCondition: 'Healthy',
      },
    });
    expect(createRes.statusCode).toBe(201);

    // Staged row adopted into patient_photos with photo_type = 'attendant'
    expect(patientPhotosTable.has(`patientPhotos/${patientId}/attendants/att_1`)).toBe(true);
    const adopted = patientPhotosTable.get(`patientPhotos/${patientId}/attendants/att_1`);
    expect(adopted.photo_type).toBe('attendant');
    expect(adopted.data).toBe('YXR0ZW5kYW50MQ==');

    // Staged row deleted
    expect(pendingPhotosTable.has(`patientPhotos/${patientId}/attendants/att_1`)).toBe(false);

    // GET serves it
    const getRes = await app.inject({
      method: 'GET',
      url: `/api/photos/patientPhotos/${patientId}/attendants/att_1`,
      headers: authHeaders(),
    });
    expect(getRes.statusCode).toBe(200);
    expect(JSON.parse(getRes.body)).toMatchObject({
      photoRef: `patientPhotos/${patientId}/attendants/att_1`,
      patientId,
      photoType: 'attendant',
      data: 'YXR0ZW5kYW50MQ==',
    });
  });

  // (e) cleanup deletes staged items older than 24 h, keeps newer
  it('(e) cleanup deletes staged items older than 24 h, keeps newer', async () => {
    const now = Date.now();
    // 25 hours old
    pendingPhotosTable.set('patientPhotos/p_old/patient', {
      photo_ref: 'patientPhotos/p_old/patient',
      patientId: 'p_old',
      kind: 'patient',
      content_type: 'image/jpeg',
      data: 'b2xk',
      version: 1,
      created_at: new Date(now - 25 * 60 * 60 * 1000),
    });
    // 1 hour old
    pendingPhotosTable.set('patientPhotos/p_new/patient', {
      photo_ref: 'patientPhotos/p_new/patient',
      patientId: 'p_new',
      kind: 'patient',
      content_type: 'image/jpeg',
      data: 'bmV3',
      version: 1,
      created_at: new Date(now - 1 * 60 * 60 * 1000),
    });

    const logger = { info: vi.fn(), error: vi.fn() };
    const deleted = await cleanupPendingPhotos(logger);
    expect(deleted).toBe(1);
    expect(logger.info).toHaveBeenCalledWith(
      { event: 'pending_photos_cleanup', deletedCount: 1 },
      'Pending photos cleanup completed: 1 deleted'
    );

    // Old is gone, new remains
    expect(pendingPhotosTable.has('patientPhotos/p_old/patient')).toBe(false);
    expect(pendingPhotosTable.has('patientPhotos/p_new/patient')).toBe(true);
  });

  // (f) a second identical PUT replaces the staged copy (still one row)
  it('(f) a second identical PUT replaces the staged copy (still one row)', async () => {
    const patientId = 'p_retry_1';
    const url = `/api/photos/patientPhotos/${patientId}/patient`;

    const put1 = await app.inject({
      method: 'PUT',
      url,
      headers: authHeaders(),
      payload: { data: 'Zmlyc3Q=', contentType: 'image/jpeg', version: 1 },
    });
    expect(put1.statusCode).toBe(200);
    expect(pendingPhotosTable.size).toBe(1);
    expect(pendingPhotosTable.get(url.slice('/api/photos/'.length)).data).toBe('Zmlyc3Q=');

    // Second identical PUT with updated data (admin retrying Save)
    const put2 = await app.inject({
      method: 'PUT',
      url,
      headers: authHeaders(),
      payload: { data: 'c2Vjb25k', contentType: 'image/jpeg', version: 1 },
    });
    expect(put2.statusCode).toBe(200);

    // Still exactly one row in pending_photos, data replaced
    expect(pendingPhotosTable.size).toBe(1);
    expect(pendingPhotosTable.get(url.slice('/api/photos/'.length)).data).toBe('c2Vjb25k');
  });

  it.each(['patient', 'attendants/att_1'])('reads back staged %s photos before patient creation with identical data', async path => {
    const patientId = 'p_verify_staged';
    const photoRef = `patientPhotos/${patientId}/${path}`;
    const url = `/api/photos/${photoRef}`;
    const data = 'data:image/png;base64,AAECA/8=';
    const put = await app.inject({ method: 'PUT', url, headers: authHeaders(), payload: { data, contentType: 'image/png', version: 17 } });
    expect(put.statusCode).toBe(200);
    const staged = pendingPhotosTable.get(photoRef);
    const get = await app.inject({ method: 'GET', url, headers: authHeaders() });
    expect(get.statusCode).toBe(200);
    expect(get.json()).toEqual({ photoRef, patientId, photoType: path === 'patient' ? 'patient' : 'attendant',
      contentType: 'image/png', data, version: 17, updatedAt: new Date(staged.created_at).getTime() });
    expect(patientsTable.has(patientId)).toBe(false);
    expect(patientPhotosTable.has(photoRef)).toBe(false);
  });

  it.each(['patient', 'attendants/att_1'])('deletes a staged %s photo so later creation adopts nothing', async path => {
    const patientId = 'p_deleted_staged';
    const photoRef = `patientPhotos/${patientId}/${path}`;
    const url = `/api/photos/${photoRef}`;
    expect((await app.inject({ method: 'PUT', url, headers: authHeaders(), payload: { data: 'aGVsbG8=' } })).statusCode).toBe(200);
    const removed = await app.inject({ method: 'DELETE', url, headers: authHeaders() });
    expect(removed.statusCode).toBe(200);
    expect(removed.json()).toEqual({ success: true });
    expect(pendingPhotosTable.has(photoRef)).toBe(false);
    expect((await app.inject({ method: 'GET', url, headers: authHeaders() })).statusCode).toBe(404);
    const created = await app.inject({ method: 'POST', url: '/api/patients', headers: authHeaders(), payload: {
      id: patientId, fullName: 'Deleted Attachment', registrationDate: '2026-01-01', dateOfBirth: '1990-01-01', gender: 'Other',
      contactNumber: '000', emergencyContact: '000', emergencyContactName: 'Synthetic', medicalCondition: 'Synthetic',
    } });
    expect(created.statusCode).toBe(201);
    expect(patientPhotosTable.has(photoRef)).toBe(false);
    expect((await app.inject({ method: 'GET', url, headers: authHeaders() })).statusCode).toBe(404);
  });

  // Never-uploaded references retain their GET/DELETE behavior.
  it('preserves GET/DELETE photo behavior for nonexistent patients (GET 404, DELETE 200)', async () => {
    const nonExistent = 'p_ghost_1';
    const getRes = await app.inject({
      method: 'GET',
      url: `/api/photos/patientPhotos/${nonExistent}/patient`,
      headers: authHeaders(),
    });
    expect(getRes.statusCode).toBe(404);

    const delRes = await app.inject({
      method: 'DELETE',
      url: `/api/photos/patientPhotos/${nonExistent}/patient`,
      headers: authHeaders(),
    });
    expect(delRes.statusCode).toBe(200);
  });

  // startPhotoCleanup timer and startup run
  it('registers startup run and timer in startPhotoCleanup, stopping on shutdown', async () => {
    vi.useFakeTimers();
    const logger = { info: vi.fn(), error: vi.fn() };
    const querySpy = vi.spyOn(dbModule, 'query').mockResolvedValue({ rows: [], rowCount: 0 } as any);

    const stop = startPhotoCleanup(logger);
    await vi.advanceTimersByTimeAsync(0);
    expect(querySpy).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(3600000);
    expect(querySpy).toHaveBeenCalledTimes(2);

    await stop();
    await vi.advanceTimersByTimeAsync(3600000);
    expect(querySpy).toHaveBeenCalledTimes(2);
    vi.useRealTimers();
  });
});
