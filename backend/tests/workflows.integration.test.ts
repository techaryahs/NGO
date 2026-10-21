import { beforeAll, afterAll, beforeEach, describe, it, expect, vi } from 'vitest';
import * as dbModule from '../src/db/index.js';
import { buildApp } from '../src/app.js';
import { pool, query } from '../src/db/index.js';
import { runMigrations } from '../src/db/migrate.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';
import { readFile } from 'node:fs/promises';

const enabled = process.env.RUN_PG_INTEGRATION === '1';
describe.skipIf(!enabled)('real PostgreSQL API workflows', () => {
  const app = buildApp({ logger: false });
  const headers = () => ({ authorization: `Bearer ${signedTestToken()}` });
  const send = async (method: any, url: string, payload?: any) => app.inject({ method, url: `/api${url}`, headers: headers(), payload });
  const patient = (id = 'p1') => ({ id, fullName: `Synthetic ${id}`, dateOfBirth: '1990-01-01', gender: 'Other', contactNumber: '000', emergencyContact: '000', emergencyContactName: 'Synthetic', medicalCondition: 'Synthetic', admissionDate: '2026-01-01', registrationNumber: id, allergies: 'retain', address: 'synthetic address', attendants: [{ name: 'Synthetic helper', age: '32' }], currentDueAmount: '10.00', advanceBilledAmount: '10.00' });
  const room = (id = 'r1') => ({ id, roomNumber: id, roomType: 'general', beds: [{ id: `${id}b1`, bedLabel: '1' }, { id: `${id}b2`, bedLabel: '2' }] });
  const stay = (id = 's1', patientId = 'p1', roomId = 'r1') => ({ id, patientId, roomId, bedId: `${roomId}b1`, durationDays: 2, admissionDate: '2026-01-01' });
  beforeAll(async () => {
    if (process.env.POSTGRES_HOST !== '127.0.0.1' || process.env.POSTGRES_DB !== 'ngo_audit_workflows' || process.env.POSTGRES_PORT !== '55439' || process.env.NODE_ENV !== 'test') throw new Error('Refusing non-disposable test database');
    const identity = (await query('SELECT current_database() AS db, inet_server_port() AS port, current_setting(\'server_version_num\')::int AS version')).rows[0];
    expect(identity).toMatchObject({ db: 'ngo_audit_workflows', port: 55439 });
    expect(identity.version).toBeGreaterThanOrEqual(160000); expect(identity.version).toBeLessThan(170000);
    await runMigrations();
  }, 30000);
  beforeEach(async () => {
    installTestFirebaseKeys();
    // Allowed only after the exact disposable connection assertion above.
    await query('TRUNCATE users, rooms, room_beds, patients, stays, patient_attendants, payments, attendance_records, patient_photos, sponsorships CASCADE');
    await query("INSERT INTO users(id,email,name,role) VALUES('test-uid-admin','admin@ngo.test','Synthetic Admin','admin')");
  });
  afterAll(async () => { await app.close(); await pool.end(); });

  it('planned October admission and extension never initialize attendance, including legacy registration payloads', async () => {
    await send('POST', '/rooms', room());
    const registration = { ...patient('oct19'), fullName: 'Same synthetic name',
      admissionDate: '2026-10-19', registrationDate: '2026-10-19', exitDate: '2026-10-31',
      stays: [{ ...stay('octstay', 'oct19'), admissionDate: '2026-10-19', durationDays: 13 }],
      initialAttendance: Array.from({ length: 13 }, (_, i) => ({ date: `2026-10-${19 + i}`,
        payload: { status: 'Present', source: 'automatic_registration_period' } })),
    };
    expect((await send('POST', '/patients/register', registration)).statusCode).toBe(201);
    expect((await query('SELECT * FROM attendance_records')).rows).toEqual([]);
    for (const [date, status] of [['2026-10-19', 'Present'], ['2026-10-20', 'Absent']]) {
      expect((await send('POST', '/attendance', { patientId: 'oct19', date, payload: { date, status, source: 'manual' } })).statusCode).toBe(200);
    }
    expect((await send('POST', '/patients/register', registration)).statusCode).toBe(200);
    expect((await send('POST', '/patients/register', { ...patient('octother'), fullName: registration.fullName,
      admissionDate: registration.admissionDate, exitDate: registration.exitDate })).statusCode).toBe(201);
    expect((await send('PUT', '/stays/octstay', { durationDays: 20, expectedDischargeDate: '2026-11-07', expiryDate: '2026-11-07' })).statusCode).toBe(200);
    expect((await send('PUT', '/patients/oct19', { exitDate: '2026-11-07' })).statusCode).toBe(200);
    const records = (await query('SELECT patient_id,attendance_date::text AS day,payload FROM attendance_records ORDER BY attendance_date')).rows;
    expect(records).toHaveLength(2);
    expect(records.map(r => [r.patient_id, r.day, r.payload.status])).toEqual([
      ['oct19', '2026-10-19', 'Present'], ['oct19', '2026-10-20', 'Absent'],
    ]);
    expect((await send('GET', '/attendance?kind=attendance&patientId=octother&format=map')).json()).toEqual({});
  });

  it('attendance invalidates a billing snapshot so old totals cannot overwrite a newer mark', async () => {
    await send('POST', '/patients', patient());
    const snapshot = (await send('GET', '/patients/p1')).json();
    await send('POST', '/attendance', { patientId: 'p1', date: '2026-01-01', payload: { status: 'Absent' } });
    expect((await send('PUT', '/patients/p1', { expectedVersion: snapshot.version,
      totalPaidAmount: 0, currentDueAmount: 10, totalPresentDays: 1 })).statusCode).toBe(409);
    const latest = (await send('GET', '/patients/p1')).json();
    const failed = await send('POST', '/attendance/bulk', { date: '2026-01-02', records: {
      p1: { status: 'Present' }, missing: { status: 'Present' },
    }});
    expect(failed.statusCode).toBe(409);
    expect((await send('GET', '/patients/p1')).json().version).toBe(latest.version);
    expect((await query("SELECT * FROM attendance_records WHERE attendance_date='2026-01-02'")).rows).toEqual([]);
  });

  it('stay changes invalidate financial snapshots and failed updates roll back the version', async () => {
    await send('POST', '/rooms', room()); await send('POST', '/patients', patient());
    await send('POST', '/stays', stay());
    const snapshot = (await send('GET', '/patients/p1')).json();
    expect((await send('PUT', '/stays/s1', { durationDays: 5 })).statusCode).toBe(200);
    expect((await send('PUT', '/patients/p1', { expectedVersion: snapshot.version, currentDueAmount: 1 })).statusCode).toBe(409);
  });

  it('registration retry cannot associate a different patient identity with an existing ID', async () => {
    const registration = { ...patient(), stays: [] };
    expect((await send('POST', '/patients/register', registration)).statusCode).toBe(201);
    expect((await send('POST', '/patients/register', { ...registration, fullName: 'Different synthetic person', dateOfBirth: '1980-01-01' })).statusCode).toBe(409);
  });

  it('patient deletion and concurrent admission use a consistent lock order without deadlock', async () => {
    await send('POST', '/rooms', room()); await send('POST', '/patients', patient());
    await send('POST', '/stays', stay());
    let unlock!: () => void;
    let locked!: () => void;
    const paused = new Promise<void>(resolve => { unlock = resolve; });
    const patientLocked = new Promise<void>(resolve => { locked = resolve; });
    const originalGetClient = dbModule.getClient;
    let requests = 0;
    let admissionPid = 0;
    const spy = vi.spyOn(dbModule, 'getClient').mockImplementation(async () => {
      const client = await originalGetClient();
      const request = ++requests;
      if (request === 2) admissionPid = (client as any).processID;
      return new Proxy(client, { get(target, prop) {
        if (prop === 'query') return async (...args: any[]) => {
          const result = await (target.query as any)(...args);
          if (request === 1 && String(args[0]).includes('SELECT id FROM patients WHERE id = $1 FOR UPDATE')) {
            locked(); await paused;
          }
          return result;
        };
        const value = (target as any)[prop];
        return typeof value === 'function' ? value.bind(target) : value;
      }});
    });
    try {
      const deletion = send('DELETE', '/patients/p1');
      await patientLocked;
      const admission = send('POST', '/stays', { ...stay('new-admission'), bedId: 'r1b2' });
      await vi.waitFor(async () => {
        expect(admissionPid).not.toBe(0);
        const row = (await query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1', [admissionPid])).rows[0];
        expect(row.wait_event_type).toBe('Lock');
      }, { timeout: 3000, interval: 10 });
      unlock();
      const results = await Promise.all([deletion, admission]);
      expect(results.map(r => r.statusCode)).toEqual([200, 409]);
      expect((await query('SELECT * FROM stays')).rows).toEqual([]);
      expect((await query("SELECT * FROM room_beds WHERE status='occupied'")).rows).toEqual([]);
    } finally { unlock(); spy.mockRestore(); }
  });

  it('atomic billing rejects another patient stay and rolls back the entire calculation', async () => {
    await send('POST', '/rooms', room());
    await send('POST', '/patients', patient()); await send('POST', '/patients', patient('p2'));
    await send('POST', '/stays', stay('s2', 'p2'));
    const before = (await send('GET', '/patients/p1')).json();
    const stayBefore = (await send('GET', '/stays/s2')).json();
    const result = await send('PUT', '/patients/p1', { expectedVersion: before.version,
      currentDueAmount: 0, stayBillingUpdates: { s2: { totalCost: 999 } } });
    expect(result.statusCode).toBe(409);
    expect((await send('GET', '/patients/p1')).json()).toEqual(before);
    expect((await send('GET', '/stays/s2')).json()).toEqual(stayBefore);
  });

  it('stay extension increments and patient metadata commit together with retry and rollback safety', async () => {
    await send('POST', '/rooms', room()); await send('POST', '/patients', patient());
    await send('POST', '/stays', stay());
    const extension = { additionalDays: 3, extensionRequestId: 'synthetic-extension', reason: 'Synthetic' };
    expect((await send('PUT', '/stays/s1', extension)).statusCode).toBe(200);
    const before = (await send('GET', '/stays/s1')).json();
    const patientBefore = (await send('GET', '/patients/p1')).json();
    expect(before).toMatchObject({ durationDays: 2, totalExtendedDays: 3 });
    expect(patientBefore.extensionDays).toBe(3);
    expect((await send('PUT', '/stays/s1', extension)).json()).toEqual(before);
    expect((await send('PUT', '/stays/s1', { ...extension, additionalDays: 4 })).statusCode).toBe(409);
    await query("CREATE FUNCTION race_fail_extension() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic failure'; END $$; CREATE TRIGGER race_fail_extension BEFORE UPDATE ON stays FOR EACH ROW EXECUTE FUNCTION race_fail_extension()");
    try {
      expect((await send('PUT', '/stays/s1', { ...extension, extensionRequestId: 'failed-extension' })).statusCode).toBe(500);
      expect((await send('GET', '/stays/s1')).json()).toEqual(before);
      expect((await send('GET', '/patients/p1')).json()).toEqual(patientBefore);
    } finally { await query('DROP TRIGGER race_fail_extension ON stays; DROP FUNCTION race_fail_extension()'); }
    expect((await query('SELECT * FROM attendance_records')).rows).toEqual([]);
  });

  it('quotes and stores only the projected attendance-based extension charge, with protected reads', async () => {
    const at = (day: number) => new Date(Date.UTC(2026, 0, day)).toISOString();
    await send('POST', '/rooms', room());
    await send('POST', '/patients', { ...patient(), exitDate: at(60) });
    await send('POST', '/stays', { ...stay(), durationDays: 60, expectedDischargeDate: at(61) });
    for (let day = 1; day <= 10; day++) {
      expect((await send('POST', '/attendance', { patientId: 'p1', date: at(day).slice(0, 10), payload: { status: 'Absent' } })).statusCode).toBe(200);
    }
    const url = '/stays/extension-quote?stayId=s1&additionalDays=10';
    expect((await app.inject({ method: 'GET', url: `/api${url}` })).statusCode).toBe(401);
    expect((await app.inject({ method: 'GET', url: `/api${url}`, headers: { authorization: `Bearer ${signedTestToken('test-uid-volunteer')}` } })).statusCode).toBe(403);
    const before = (await query("SELECT * FROM stays WHERE id='s1'")).rows[0];
    expect((await send('GET', url)).json()).toMatchObject({ additionalCost: 2000, priorBillableDays: 50, pricingBasis: 'projected_billable_attendance' });
    expect((await query("SELECT * FROM stays WHERE id='s1'")).rows[0]).toEqual(before);
    const request = { additionalDays: 10, extensionRequestId: 'attendance-quote', reason: 'Approved' };
    const response = await send('PUT', '/stays/s1', request);
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ durationDays: 60, totalExtendedDays: 10, totalCost: 12000,
      extensions: [expect.objectContaining({ additionalCost: 2000, priorBillableDays: 50 })] });
    expect((await send('GET', '/patients/p1')).json()).toMatchObject({ advanceBilledAmount: 12000, currentDueAmount: 12000, exitDate: Date.parse(at(70)) });
    expect((await send('PUT', '/stays/s1', request)).json()).toEqual(response.json());
  });

  it('concurrent bulk attendant edits preserve independent people and reject no manual marks', async () => {
    await send('POST', '/patients', patient()); await send('POST', '/patients', patient('p2'));
    const responses = await Promise.all([
      send('POST', '/attendance/bulk', { date: '2026-01-01', kind: 'attendant_attendance', records: { p1: { A: { status: 'Present' } }, p2: { A: { status: 'Absent' } } } }),
      send('POST', '/attendance/bulk', { date: '2026-01-01', kind: 'attendant_attendance', records: { p2: { B: { status: 'Present' } }, p1: { B: { status: 'Absent' } } } }),
    ]);
    expect(responses.map(r => r.statusCode)).toEqual([200, 200]);
    expect((await send('GET', '/attendance?kind=attendant_attendance&date=2026-01-01&format=map')).json()).toEqual({
      p1: { A: { status: 'Present' }, B: { status: 'Absent' } },
      p2: { A: { status: 'Absent' }, B: { status: 'Present' } },
    });
  });

  it('concurrent transfer and discharge cannot leave a discharged patient with an active stay', async () => {
    await send('POST', '/rooms', room()); await send('POST', '/rooms', room('r2'));
    await send('POST', '/patients', patient()); await send('POST', '/stays', stay());
    const transfer = { requestId: 'race-transfer', expectedStayIds: ['s1'], roomId: 'r2',
      roomNumber: 'r2', roomType: 'general', bedId: 'r2b1', shiftedAt: '2026-01-02' };
    const results = await Promise.all([
      send('POST', '/patients/p1/transfer', transfer),
      send('PUT', '/stays/s1', { status: 'completed', completedAt: '2026-01-02' }),
    ]);
    expect([200, 409]).toContain(results[0].statusCode);
    expect(results[1].statusCode).toBe(200);
    const active = (await query("SELECT * FROM stays WHERE patient_id='p1' AND status='active'")).rows;
    const savedPatient = (await send('GET', '/patients/p1')).json();
    expect(savedPatient.status).toBe(active.length ? 'active' : 'discharged');
    expect((await query("SELECT * FROM room_beds WHERE current_patient_id='p1'")).rows).toHaveLength(active.length);
    if (results[0].statusCode === 200) {
      const before = (await send('GET', '/patients/p1')).json();
      expect((await send('POST', '/patients/p1/transfer', transfer)).statusCode).toBe(200);
      expect((await send('GET', '/patients/p1')).json()).toEqual(before);
    }
    expect((await query('SELECT * FROM attendance_records')).rows).toEqual([]);
  });

  it('fresh migration creates all 17 domain tables, is rerunnable and records status', async () => {
    await runMigrations();
    expect((await query("SELECT tablename FROM pg_tables WHERE schemaname='public'")).rows).toHaveLength(18);
    expect((await query('SELECT name FROM pgmigrations ORDER BY id')).rows.map(x => x.name)).toContain('001_initial_schema');
    // Compare the expected initial catalog with the executed database, including
    // every original column/index/FK, rather than accepting table counts alone.
    const ddl = await readFile(new URL('../migrations/001_initial_schema.sql', import.meta.url), 'utf8');
    const columns = (await query("SELECT table_name,column_name FROM information_schema.columns WHERE table_schema='public'")).rows;
    const expectedTables = [...ddl.matchAll(/CREATE TABLE IF NOT EXISTS (\w+) \(([\s\S]*?)\n\);/g)];
    expect(expectedTables).toHaveLength(17);
    for (const [, table, definition] of expectedTables) {
      const expected = [...definition.matchAll(/^\s+([a-z_]\w*)\s+(?:VARCHAR|INTEGER|TEXT|TIMESTAMPTZ|DATE|BOOLEAN|JSONB|NUMERIC|DOUBLE|BIGINT)/gm)].map(match => match[1]);
      const actual = columns.filter(column => column.table_name === table).map(column => column.column_name);
      expect(actual).toEqual(expect.arrayContaining(expected));
    }
    const indexes = (await query("SELECT indexname FROM pg_indexes WHERE schemaname='public'")).rows.map(row => row.indexname);
    expect(indexes).toEqual(expect.arrayContaining([...ddl.matchAll(/CREATE INDEX IF NOT EXISTS (\w+)/g)].map(match => match[1])));
    const constraints = (await query("SELECT conname FROM pg_constraint WHERE connamespace='public'::regnamespace AND contype='f'")).rows.map(row => row.conname);
    for (const [, table, definition] of expectedTables) {
      for (const match of definition.matchAll(/^\s+(\w+).*?REFERENCES\s+(\w+)\(/gm)) expect(constraints).toContain(`${table}_${match[1]}_fkey`);
    }
  });
  it('creates and updates rooms, adds beds, rejects duplicate labels and cross-room bed mutation', async () => {
    expect((await send('POST', '/rooms', room())).statusCode).toBe(201);
    expect((await send('POST', '/rooms/r1/beds', { id: 'extra', bedLabel: '3' })).statusCode).toBe(201);
    expect((await send('POST', '/rooms/r1/beds', { id: 'duplicate', bedLabel: '3' })).statusCode).toBe(409);
    expect((await send('PUT', '/rooms/r1/beds/extra', { bedLabel: 'four', status: 'maintenance' })).statusCode).toBe(200);
    expect((await send('PUT', '/rooms/missing/beds/extra', { status: 'available' })).statusCode).toBe(404);
    const current = (await send('GET', '/rooms/r1')).json();
    expect(current.totalBeds).toBe(3); expect(current.beds.find((b: any) => b.id === 'extra').bedLabel).toBe('four');
  });
  it('only one concurrent update with the same room version succeeds', async () => {
    const created = (await send('POST', '/rooms', room())).json();
    const results = await Promise.all([send('PUT', '/rooms/r1', { expectedVersion: created.version, notes: 'a' }), send('PUT', '/rooms/r1', { expectedVersion: created.version, notes: 'b' })]);
    expect(results.map(x => x.statusCode).sort()).toEqual([200, 409]);
  });
  it('patient partial updates preserve fields and attendants; searches, pagination and duplicate registration work', async () => {
    expect((await send('POST', '/patients', patient())).statusCode).toBe(201);
    const updated = await send('PUT', '/patients/p1', { fullName: 'Updated Synthetic' });
    expect(updated.json()).toMatchObject({ fullName: 'Updated Synthetic', allergies: 'retain', address: 'synthetic address', attendants: [{ name: 'Synthetic helper' }] });
    expect((await send('GET', '/patients?search=Updated&limit=1&offset=0')).json()).toHaveLength(1);
    expect((await send('GET', '/patients?limit=-1')).statusCode).toBe(400);
    expect((await send('POST', '/patients', { ...patient('p2'), registrationNumber: 'p1' })).statusCode).toBe(409);
    expect((await query('SELECT count(*)::int AS count FROM patient_attendants')).rows[0].count).toBe(1);
  });
  it('rejects missing patient fields and invalid dates without inserting anything', async () => {
    expect((await send('POST', '/patients', {})).statusCode).toBe(400);
    expect((await send('POST', '/patients', { ...patient(), dateOfBirth: 'bad' })).statusCode).toBe(400);
    expect((await query('SELECT count(*)::int AS count FROM patients')).rows[0].count).toBe(0);
  });
  it('supports maximum-length patient identifiers and safe repeated registration requests', async () => {
    const id = 'p'.repeat(64);
    expect((await send('POST', '/patients', patient(id))).statusCode).toBe(201);
    expect((await send('POST', '/patients', patient(id))).statusCode).toBe(409);
    const profile = (await send('GET', `/patients/${id}`)).json();
    expect(profile.attendants).toHaveLength(1); expect(profile.attendants[0].id.length).toBeLessThanOrEqual(64);
    expect((await query('SELECT count(*)::int AS count FROM patients')).rows[0].count).toBe(1);
  });
  it('preserves epoch-zero birth and admission dates without substituting defaults', async () => {
    const response = await send('POST', '/patients', { ...patient(), dateOfBirth: 0, admissionDate: 0 });
    expect(response.statusCode).toBe(201); expect(response.json()).toMatchObject({ dateOfBirth: 0, admissionDate: 0 });
  });
  it('admission and discharge synchronize patient, stay, bed and room; repeat discharge is safe', async () => {
    await send('POST', '/rooms', room()); await send('POST', '/patients', patient());
    expect((await send('POST', '/stays', stay())).statusCode).toBe(201);
    expect((await send('GET', '/rooms/r1')).json()).toMatchObject({ occupiedBeds: 1, status: 'partially_occupied', beds: [{ currentPatientId: 'p1', currentStayId: 's1', status: 'occupied' }, {}] });
    expect((await send('GET', '/patients/p1')).json()).toMatchObject({ roomId: 'r1', bedIds: ['r1b1'] });
    expect((await send('PUT', '/stays/s1', { durationDays: 3, notes: 'extension' })).json()).toMatchObject({ bedId: 'r1b1', durationDays: 3 });
    expect((await send('PUT', '/stays/s1', { status: 'completed', completedAt: '2026-01-04' })).statusCode).toBe(200);
    const bed = (await query("SELECT * FROM room_beds WHERE id='r1b1'")).rows[0];
    expect(bed).toMatchObject({ status: 'available', current_patient_id: null, current_stay_id: null });
    expect((await send('GET', '/rooms/r1')).json()).toMatchObject({ occupiedBeds: 0, status: 'available' });
    expect((await send('GET', '/patients/p1')).json()).toMatchObject({ status: 'discharged', roomId: null, bedIds: [] });
    expect((await send('GET', '/stays/s1')).json()).toMatchObject({ status: 'completed', bedId: 'r1b1' });
    expect((await send('PUT', '/stays/s1', { status: 'completed' })).statusCode).toBe(200);
  });
  it('concurrent admissions cannot claim the same bed', async () => {
    await send('POST', '/rooms', room()); await send('POST', '/patients', patient()); await send('POST', '/patients', patient('p2'));
    const results = await Promise.all([send('POST', '/stays', stay()), send('POST', '/stays', stay('s2', 'p2'))]);
    expect(results.map(x => x.statusCode).sort()).toEqual([201, 409]);
    expect((await query('SELECT count(*)::int AS count FROM stays')).rows[0].count).toBe(1);
  });
  it('supports existing multi-bed admissions and discharges the patient only after the final placement ends', async () => {
    await send('POST', '/rooms', room()); await send('POST', '/patients', patient());
    expect((await send('POST', '/stays', stay())).statusCode).toBe(201);
    expect((await send('POST', '/stays', { ...stay('s2'), bedId: 'r1b2' })).statusCode).toBe(201);
    expect((await send('GET', '/patients/p1')).json()).toMatchObject({ bedIds: ['r1b1', 'r1b2'], status: 'active' });
    expect((await send('GET', '/rooms/r1')).json()).toMatchObject({ occupiedBeds: 2, status: 'occupied' });
    await send('PUT', '/stays/s1', { status: 'completed' });
    expect((await send('GET', '/patients/p1')).json()).toMatchObject({ bedIds: ['r1b2'], status: 'active', roomId: 'r1' });
    expect((await send('GET', '/rooms/r1')).json()).toMatchObject({ occupiedBeds: 1, status: 'partially_occupied' });
    await send('PUT', '/stays/s2', { status: 'completed' });
    expect((await send('GET', '/patients/p1')).json()).toMatchObject({ bedIds: [], status: 'discharged', roomId: null });
    expect((await send('GET', '/rooms/r1')).json()).toMatchObject({ occupiedBeds: 0, status: 'available' });
  });
  it('active assignments cannot be detached through patient or room updates; stay rate updates persist', async () => {
    await send('POST', '/rooms', room()); await send('POST', '/patients', patient()); await send('POST', '/stays', stay());
    expect((await send('PUT', '/patients/p1', { roomId: null, bedIds: [] })).statusCode).toBe(409);
    expect((await send('PUT', '/patients/p1', { status: 'discharged' })).statusCode).toBe(409);
    expect((await send('PUT', '/rooms/r1', { beds: [{ id: 'rogue', bedLabel: 'bad', status: 'occupied', currentPatientId: 'p1' }] })).statusCode).toBe(409);
    expect((await send('PUT', '/rooms/r1/beds/r1b1', { status: 'available' })).statusCode).toBe(409);
    const response = await send('PUT', '/stays/s1', { longStayDailyRate: '12.34' });
    expect(response.json().longStayDailyRate).toBe(12.34);
    expect((await query("SELECT long_stay_daily_rate FROM stays WHERE id='s1'")).rows[0].long_stay_daily_rate).toBe('12.34');
  });
  it('stale full patient snapshots cannot overwrite a newer payment balance', async () => {
    await send('POST', '/patients', patient());
    const old = (await send('GET', '/patients/p1')).json();
    await send('POST', '/payments', { id: 'version-payment', patientId: 'p1', amount: '1.00' });
    expect((await send('PUT', '/patients/p1', old)).statusCode).toBe(409);
    expect((await send('PUT', '/patients/p1', { totalPaidAmount: '0.00' })).statusCode).toBe(409);
    const current = (await send('GET', '/patients/p1')).json();
    expect(current).toMatchObject({ totalPaidAmount: 1, currentDueAmount: 9, payments: [{ id: 'version-payment' }] });
  });
  it('invalid admission rolls back stay and assignment; discharge failure rolls back all related writes', async () => {
    await send('POST', '/rooms', room()); await send('POST', '/patients', patient());
    expect((await send('POST', '/stays', { ...stay(), bedId: 'missing' })).statusCode).toBe(409);
    expect((await query('SELECT count(*)::int AS count FROM stays')).rows[0].count).toBe(0);
    await send('POST', '/stays', stay());
    await query("CREATE FUNCTION audit_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic failure'; END $$; CREATE TRIGGER audit_fail BEFORE UPDATE ON patients FOR EACH ROW EXECUTE FUNCTION audit_fail()");
    try {
      expect((await send('PUT', '/stays/s1', { status: 'completed' })).statusCode).toBe(500);
      expect((await query("SELECT status FROM stays WHERE id='s1'")).rows[0].status).toBe('active');
      expect((await query("SELECT current_stay_id FROM room_beds WHERE id='r1b1'")).rows[0].current_stay_id).toBe('s1');
    } finally { await query('DROP TRIGGER audit_fail ON patients; DROP FUNCTION audit_fail()'); }
  });
  it('authorized admin deletion removes the patient and dependent financial records atomically', async () => {
    await send('POST', '/patients', patient()); await send('POST', '/payments', { id: 'pay1', patientId: 'p1', amount: '1.00' });
    expect((await send('DELETE', '/patients/p1')).statusCode).toBe(200);
    expect((await query('SELECT count(*)::int AS count FROM payments')).rows[0].count).toBe(0);
  });
  it('concurrent duplicate payments and retry apply balances exactly once, conflicting reuse is rejected', async () => {
    await send('POST', '/patients', patient());
    const payload = { patientId: 'p1', amount: '0.10', transactionId: 'synthetic-tx', method: 'cash' };
    const results = await Promise.all([send('POST', '/payments', payload), send('POST', '/payments', payload)]);
    expect(results.map(x => x.statusCode).sort()).toEqual([200, 201]);
    expect((await send('POST', '/payments', payload)).statusCode).toBe(200);
    expect((await send('POST', '/payments', { ...payload, amount: '0.20' })).statusCode).toBe(409);
    expect((await query('SELECT count(*)::int AS count FROM payments')).rows[0].count).toBe(1);
    expect((await query("SELECT total_paid_amount,current_due_amount FROM patients WHERE id='p1'")).rows[0]).toEqual({ total_paid_amount: '0.10', current_due_amount: '9.90' });
  });
  it('payment requires a stable retry key, rejects invalid amounts and over-refunds, rolls back balances on failure', async () => {
    await send('POST', '/patients', patient());
    for (const payload of [{ amount: '1' }, { id: 'bad', amount: '1.001' }, { id: 'negative-payment', amount: '-1', type: 'payment' }]) expect((await send('POST', '/payments', { patientId: 'p1', ...payload })).statusCode).toBe(400);
    expect((await send('POST', '/payments', { patientId: 'p1', id: 'refund', amount: '-1', type: 'refund' })).statusCode).toBe(409);
    await query("CREATE FUNCTION audit_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic failure'; END $$; CREATE TRIGGER audit_fail BEFORE UPDATE ON patients FOR EACH ROW EXECUTE FUNCTION audit_fail()");
    try { expect((await send('POST', '/payments', { id: 'pay1', patientId: 'p1', amount: '1.00' })).statusCode).toBe(500); expect((await query('SELECT count(*)::int AS count FROM payments')).rows[0].count).toBe(0); }
    finally { await query('DROP TRIGGER audit_fail ON patients; DROP FUNCTION audit_fail()'); }
  });
  it('concurrent distinct decimal payments add exactly in PostgreSQL', async () => {
    await send('POST', '/patients', patient());
    const results = await Promise.all([send('POST', '/payments', { id: 'cents1', patientId: 'p1', amount: '0.10' }), send('POST', '/payments', { id: 'cents2', patientId: 'p1', amount: '0.20' })]);
    expect(results.map(r => r.statusCode)).toEqual([201, 201]);
    expect((await query("SELECT total_paid_amount,current_due_amount FROM patients WHERE id='p1'")).rows[0]).toEqual({ total_paid_amount: '0.30', current_due_amount: '9.70' });
    expect((await query("SELECT sum(amount)::text AS total FROM payments WHERE patient_id='p1'")).rows[0].total).toBe('0.30');
  });
  it('lost database connection is replaced and a saturated pool times out without leaks', async () => {
    const victim = await pool.connect(); victim.on('error', () => {}); const pid = (await victim.query('SELECT pg_backend_pid() AS pid')).rows[0].pid;
    await query('SELECT pg_terminate_backend($1)', [pid]); victim.release(true);
    expect((await query('SELECT 1 AS ok')).rows[0].ok).toBe(1);
    const pg = await import('pg'); const small = new pg.default.Pool({ connectionString: undefined, host: '127.0.0.1', port: 55439, database: 'ngo_audit_workflows', user: 'ngo_audit', password: process.env.POSTGRES_PASSWORD, max: 1, connectionTimeoutMillis: 100 });
    const held = await small.connect(); await expect(small.connect()).rejects.toThrow(/timeout/); held.release(); expect((await small.query('SELECT 1 AS ok')).rows[0].ok).toBe(1); await small.end();
  });
  it('supports atomic multi-bed batch admission with rollback on conflict, room deletion guards, and attendant attendance JSONB merge', async () => {
    await send('POST', '/rooms', room('r_batch'));
    await send('POST', '/patients', patient('p_batch'));
    const conflictBatch = await send('POST', '/stays/batch', {
      stays: [
        { id: 'sb1', patientId: 'p_batch', roomId: 'r_batch', bedId: 'r_batchb1', durationDays: 3, admissionDate: '2026-01-01' },
        { id: 'sb2', patientId: 'p_batch', roomId: 'r_batch', bedId: 'r_batchb1', durationDays: 3, admissionDate: '2026-01-01' },
      ],
    });
    expect(conflictBatch.statusCode).toBe(409);
    expect((await query('SELECT count(*)::int AS count FROM stays')).rows[0].count).toBe(0);
    expect((await query("SELECT status FROM room_beds WHERE id='r_batchb1'")).rows[0].status).toBe('available');

    const okBatch = await send('POST', '/stays/batch', {
      stays: [
        { id: 'sb1', patientId: 'p_batch', roomId: 'r_batch', bedId: 'r_batchb1', durationDays: 3, admissionDate: '2026-01-01', attendantCount: 1 },
        { id: 'sb2', patientId: 'p_batch', roomId: 'r_batch', bedId: 'r_batchb2', durationDays: 3, admissionDate: '2026-01-01', attendantCount: 0 },
      ],
    });
    expect(okBatch.statusCode).toBe(201);
    expect(okBatch.json().stays).toHaveLength(2);
    expect((await send('GET', '/patients/p_batch')).json().bedIds.sort()).toEqual(['r_batchb1', 'r_batchb2']);
    expect((await send('DELETE', '/rooms/r_batch')).statusCode).toBe(409);

    await send('POST', '/rooms', room('r_empty'));
    expect((await send('DELETE', '/rooms/r_empty')).statusCode).toBe(200);

    await send('POST', '/attendance/bulk', {
      kind: 'attendant_attendance',
      date: '2026-01-01',
      records: { p_batch: { att_1: { status: 'Present', name: 'Helper 1' } } },
    });
    await send('POST', '/attendance/bulk', {
      kind: 'attendant_attendance',
      date: '2026-01-01',
      records: { p_batch: { att_2: { status: 'Absent', name: 'Helper 2' } } },
    });
    const attRow = (await query("SELECT payload FROM attendance_records WHERE kind='attendant_attendance' AND attendance_date='2026-01-01' AND patient_id='p_batch'")).rows[0];
    expect(attRow.payload).toMatchObject({
      att_1: { status: 'Present', name: 'Helper 1' },
      att_2: { status: 'Absent', name: 'Helper 2' },
    });
  });

  it('returns authoritative registration state on an identical retry without duplicating or resetting financial records', async () => {
    await send('POST', '/rooms', room());
    const registration = {
      ...patient(),
      stays: [stay()],
      initialAttendance: [{ date: '2026-01-01', kind: 'attendance', payload: { status: 'Present' } }],
    };
    expect((await send('POST', '/patients/register', registration)).statusCode).toBe(201);
    expect((await send('POST', '/payments', { id: 'registration-payment', patientId: 'p1', amount: '1.00' })).statusCode).toBe(201);
    const before = (await send('GET', '/patients/p1')).json();

    const retry = await send('POST', '/patients/register', registration);
    expect(retry.statusCode).toBe(200);
    expect(retry.json()).toMatchObject({ ...before, idempotentRetry: true, stayIds: ['s1'] });
    expect((await send('GET', '/patients/p1')).json()).toEqual(before);
    for (const table of ['patients', 'patient_attendants', 'stays', 'attendance_records', 'payments']) {
      expect((await query(`SELECT count(*)::int AS count FROM ${table}`)).rows[0].count).toBe(table === 'attendance_records' ? 0 : 1);
    }
  });

  it.each([
    ['bed', { bedId: 'r1b2' }],
    ['stay ID', { id: 'different-stay' }],
    ['room', { roomId: 'r_other', bedId: 'r_otherb1' }],
    ['admission date', { admissionDate: '2026-01-02' }],
    ['duration', { durationDays: 3 }],
  ])('rejects a same-count registration retry with a different %s before changing patient or financial history', async (_field, changedStay) => {
    await send('POST', '/rooms', room());
    await send('POST', '/rooms', room('r_other'));
    const registration = {
      ...patient(),
      stays: [stay()],
      initialAttendance: [{ date: '2026-01-01', kind: 'attendance', payload: { status: 'Present' } }],
    };
    expect((await send('POST', '/patients/register', registration)).statusCode).toBe(201);
    await send('POST', '/payments', { id: 'preserved-payment', patientId: 'p1', amount: '1.00' });
    const before = (await send('GET', '/patients/p1')).json();
    const staysBefore = (await query('SELECT * FROM stays ORDER BY id')).rows;
    const bedsBefore = (await query('SELECT * FROM room_beds ORDER BY id')).rows;
    const attendanceBefore = (await query('SELECT * FROM attendance_records ORDER BY id')).rows;

    const retry = await send('POST', '/patients/register', {
      ...registration,
      fullName: 'Must not replace the patient',
      currentDueAmount: '999.00',
      totalPaidAmount: '0.00',
      attendants: [{ name: 'Must not replace the attendant' }],
      stays: [{ ...stay(), ...changedStay }],
    });
    expect(retry.statusCode).toBe(409);
    expect(retry.json().message).toMatch(/different.*registration|registration.*different/i);
    expect((await send('GET', '/patients/p1')).json()).toEqual(before);
    expect((await query('SELECT * FROM stays ORDER BY id')).rows).toEqual(staysBefore);
    expect((await query('SELECT * FROM room_beds ORDER BY id')).rows).toEqual(bedsBefore);
    expect((await query('SELECT * FROM attendance_records ORDER BY id')).rows).toEqual(attendanceBefore);
    expect((await query('SELECT count(*)::int AS count FROM payments')).rows[0].count).toBe(1);
  });

  it('rejects an added-stay retry instead of replacing existing patient fields or attendants', async () => {
    await send('POST', '/rooms', room());
    const registration = { ...patient(), stays: [stay()] };
    expect((await send('POST', '/patients/register', registration)).statusCode).toBe(201);
    await send('POST', '/payments', { id: 'preserved-payment', patientId: 'p1', amount: '1.00' });
    const before = (await send('GET', '/patients/p1')).json();

    const retry = await send('POST', '/patients/register', {
      ...registration,
      fullName: 'Must not replace the patient',
      totalPaidAmount: '0.00',
      currentDueAmount: '999.00',
      attendants: [{ name: 'Must not replace the attendant' }],
      stays: [stay(), { ...stay('s2'), bedId: 'r1b2' }],
    });
    expect(retry.statusCode).toBe(409);
    expect((await send('GET', '/patients/p1')).json()).toEqual(before);
    expect((await query('SELECT count(*)::int AS count FROM stays')).rows[0].count).toBe(1);
    expect((await query("SELECT status,current_stay_id FROM room_beds WHERE id='r1b2'")).rows[0]).toEqual({ status: 'available', current_stay_id: null });
  });

  it('serializes simultaneous identical patient registrations, creating one complete admission', async () => {
    await send('POST', '/rooms', room());
    const registration = {
      ...patient(),
      stays: [stay()],
      initialAttendance: [{ date: '2026-01-01', kind: 'attendance', payload: { status: 'Present' } }],
    };
    const responses = await Promise.all([
      send('POST', '/patients/register', registration),
      send('POST', '/patients/register', registration),
    ]);
    expect(responses.map(response => response.statusCode).sort()).toEqual([200, 201]);
    for (const response of responses) expect(response.json()).toMatchObject({ id: 'p1', bedIds: ['r1b1'], stayIds: ['s1'], attendants: [{ name: 'Synthetic helper' }] });
    for (const table of ['patients', 'patient_attendants', 'stays', 'attendance_records']) {
      expect((await query(`SELECT count(*)::int AS count FROM ${table}`)).rows[0].count).toBe(table === 'attendance_records' ? 0 : 1);
    }
    expect((await query("SELECT current_patient_id,current_stay_id FROM room_beds WHERE id='r1b1'")).rows[0]).toEqual({ current_patient_id: 'p1', current_stay_id: 's1' });
    expect((await query("SELECT occupied_beds FROM rooms WHERE id='r1'")).rows[0].occupied_beds).toBe(1);
  });

  it('rejects one simultaneous same-patient registration with a different bed without overwriting the winner', async () => {
    await send('POST', '/rooms', room());
    const responses = await Promise.all([
      send('POST', '/patients/register', { ...patient(), fullName: 'First synthetic claimant', currentDueAmount: '11.00', stays: [stay()] }),
      send('POST', '/patients/register', { ...patient(), fullName: 'Second synthetic claimant', currentDueAmount: '22.00', stays: [{ ...stay('s2'), bedId: 'r1b2' }] }),
    ]);
    expect(responses.map(response => response.statusCode).sort()).toEqual([201, 409]);
    const winner = responses.find(response => response.statusCode === 201)!.json();
    const current = (await send('GET', '/patients/p1')).json();
    expect(current).toMatchObject({ fullName: winner.fullName, currentDueAmount: winner.currentDueAmount, bedIds: winner.bedIds, version: winner.version });
    expect((await query('SELECT count(*)::int AS count FROM stays')).rows[0].count).toBe(1);
    expect((await query('SELECT count(*)::int AS count FROM patient_attendants')).rows[0].count).toBe(1);
    expect((await query("SELECT occupied_beds FROM rooms WHERE id='r1'")).rows[0].occupied_beds).toBe(1);
    const available = (await query("SELECT id FROM room_beds WHERE status='available'")).rows;
    expect(available).toHaveLength(1);
    expect(available[0].id).not.toBe(winner.bedIds[0]);
  });

  it('preserves no-stay registration retry behavior without rewriting the patient', async () => {
    const registration = { ...patient(), stays: [] };
    const created = await send('POST', '/patients/register', registration);
    expect(created.statusCode).toBe(201);
    const retry = await send('POST', '/patients/register', registration);
    expect(retry.statusCode).toBe(200);
    expect(retry.json()).toMatchObject({ idempotentRetry: true, stays: [], patient: created.json().patient });
    expect((await query('SELECT count(*)::int AS count FROM patients')).rows[0].count).toBe(1);
    expect((await query('SELECT count(*)::int AS count FROM patient_attendants')).rows[0].count).toBe(1);
  });

  it('rolls back a registration when its second bed is occupied, preserving the other patient and assignment', async () => {
    await send('POST', '/rooms', room());
    await send('POST', '/patients', patient('other-patient'));
    expect((await send('POST', '/stays', { ...stay('other-stay', 'other-patient'), bedId: 'r1b2' })).statusCode).toBe(201);
    const otherPatientBefore = (await send('GET', '/patients/other-patient')).json();
    const otherStayBefore = (await query("SELECT * FROM stays WHERE id='other-stay'")).rows[0];
    const occupiedBedBefore = (await query("SELECT * FROM room_beds WHERE id='r1b2'")).rows[0];

    const rejected = await send('POST', '/patients/register', {
      ...patient(),
      stays: [stay(), { ...stay('s2'), bedId: 'r1b2' }],
      initialAttendance: [{ date: '2026-01-01', kind: 'attendance', payload: { status: 'Present' } }],
    });
    expect(rejected.statusCode).toBe(409);
    for (const [table, key] of [['patients', 'id'], ['patient_attendants', 'patient_id'], ['stays', 'patient_id'], ['attendance_records', 'patient_id']]) {
      expect((await query(`SELECT count(*)::int AS count FROM ${table} WHERE ${key}=$1`, ['p1'])).rows[0].count).toBe(0);
    }
    expect((await query("SELECT status,current_patient_id,current_stay_id FROM room_beds WHERE id='r1b1'")).rows[0]).toEqual({ status: 'available', current_patient_id: null, current_stay_id: null });
    expect((await query("SELECT * FROM room_beds WHERE id='r1b2'")).rows[0]).toEqual(occupiedBedBefore);
    expect((await query("SELECT * FROM stays WHERE id='other-stay'")).rows[0]).toEqual(otherStayBefore);
    expect((await send('GET', '/patients/other-patient')).json()).toEqual(otherPatientBefore);
    expect((await query("SELECT occupied_beds FROM rooms WHERE id='r1'")).rows[0].occupied_beds).toBe(1);
  });

  it('accepts 71-character composite stay IDs in /stays/batch and completes atomic single-bed, multi-bed, and lobby registrations with rollback and retry safety', async () => {
    // 1. Reproduce exact 71-char deterministic stay ID from live desktop failure
    const longRoomId = 'r_1792316250516360';
    const longBed1 = 'r_1792316250516360_1/2';
    const longBed2 = 'r_1792316250516360_2/2';
    await send('POST', '/rooms', {
      id: longRoomId,
      roomNumber: '1A',
      roomType: 'general',
      floor: 1,
      beds: [
        { id: longBed1, bedLabel: '1/2' },
        { id: longBed2, bedLabel: '2/2' },
      ],
    });

    const longPatientId = 'p_1792317035249089_7491219db8037bcf66f1cc8b';
    const longStayId = `stay_${longPatientId}_${longBed1}`;
    expect(longStayId.length).toBe(71);

    // 2. Test atomic rollback: if bed 2 does not exist or is unavailable, patient + stays + attendants must NOT be persisted
    const rollbackRes = await send('POST', '/patients/register', {
      ...patient(longPatientId),
      attendants: [{ name: 'Attendant Rollback' }],
      stays: [
        { id: longStayId, roomId: longRoomId, bedId: longBed1, durationDays: 7, admissionDate: '2026-01-01' },
        { id: `stay_${longPatientId}_missing_bed`, roomId: longRoomId, bedId: 'non_existent_bed', durationDays: 7, admissionDate: '2026-01-01' },
      ],
      initialAttendance: [
        { date: '2026-01-01', kind: 'attendance', payload: { status: 'present' } },
      ],
    });
    expect(rollbackRes.statusCode).toBe(409);
    expect((await query('SELECT count(*)::int AS count FROM patients WHERE id = $1', [longPatientId])).rows[0].count).toBe(0);
    expect((await query('SELECT count(*)::int AS count FROM stays WHERE patient_id = $1', [longPatientId])).rows[0].count).toBe(0);
    expect((await query('SELECT count(*)::int AS count FROM patient_attendants WHERE patient_id = $1', [longPatientId])).rows[0].count).toBe(0);
    expect((await query('SELECT count(*)::int AS count FROM attendance_records WHERE patient_id = $1', [longPatientId])).rows[0].count).toBe(0);
    expect((await query('SELECT occupied_beds FROM rooms WHERE id = $1', [longRoomId])).rows[0].occupied_beds).toBe(0);
    expect((await query('SELECT status, current_stay_id FROM room_beds WHERE id = $1', [longBed1])).rows[0]).toEqual({
      status: 'available',
      current_stay_id: null,
    });

    // 3. Test atomic single-bed registration with 71-character stay ID + initial attendance
    const singleRegRes = await send('POST', '/patients/register', {
      ...patient(longPatientId),
      registrationNumber: null,
      attendants: [{ name: 'Primary Attendant', relation: 'Spouse' }],
      stays: [
        {
          id: longStayId,
          roomId: longRoomId,
          bedId: longBed1,
          durationDays: 7,
          admissionDate: '2026-01-01',
          attendantCount: 1,
          totalCost: 350,
          baseCost: 350,
        },
      ],
      initialAttendance: [
        { date: '2026-01-01', kind: 'attendance', payload: { status: 'present', isAdvance: true } },
        { date: '2026-01-01', kind: 'attendant_attendance', payload: { 'Primary Attendant': { status: 'Present', isAdvance: true } } },
      ],
    });
    expect(singleRegRes.statusCode).toBe(201);
    const singleRegBody = singleRegRes.json();
    expect(singleRegBody.id).toBe(longPatientId);
    expect(singleRegBody.registrationNumber).toBeTruthy();
    expect(singleRegBody.bedIds).toEqual([longBed1]);
    expect(singleRegBody.stays).toHaveLength(1);
    expect(singleRegBody.stays[0].id).toBe(longStayId);

    // 4. Test idempotent retry of the same registration request
    const retryRegRes = await send('POST', '/patients/register', {
      ...patient(longPatientId),
      registrationNumber: null,
      attendants: [{ name: 'Primary Attendant', relation: 'Spouse' }],
      stays: [
        {
          id: longStayId,
          roomId: longRoomId,
          bedId: longBed1,
          durationDays: 7,
          admissionDate: '2026-01-01',
        },
      ],
    });
    expect(retryRegRes.statusCode).toBe(200);
    expect(retryRegRes.json().idempotentRetry).toBe(true);
    expect((await query('SELECT count(*)::int AS count FROM patients WHERE id = $1', [longPatientId])).rows[0].count).toBe(1);
    expect((await query('SELECT count(*)::int AS count FROM stays WHERE patient_id = $1', [longPatientId])).rows[0].count).toBe(1);

    // 5. Test atomic multi-bed registration in a new room
    await send('POST', '/rooms', room('r_multi'));
    const multiPatientId = 'p_1792318000000000_multibedtest000000000000';
    const multiRegRes = await send('POST', '/patients/register', {
      ...patient(multiPatientId),
      registrationNumber: 'REG-MULTI-1',
      attendants: [{ name: 'Att 1' }, { name: 'Att 2' }],
      stays: [
        { id: `stay_${multiPatientId}_r_multib1`, roomId: 'r_multi', bedId: 'r_multib1', durationDays: 5, admissionDate: '2026-01-01', attendantCount: 2 },
        { id: `stay_${multiPatientId}_r_multib2`, roomId: 'r_multi', bedId: 'r_multib2', durationDays: 5, admissionDate: '2026-01-01', attendantCount: 0 },
      ],
    });
    expect(multiRegRes.statusCode).toBe(201);
    expect(multiRegRes.json().bedIds.sort()).toEqual(['r_multib1', 'r_multib2']);
    expect((await query("SELECT occupied_beds FROM rooms WHERE id = 'r_multi'")).rows[0].occupied_beds).toBe(2);

    // 6. Test lobby registration & virtual room filtering
    const lobbyPatientId = 'p_1792319000000000_lobbytest000000000000000';
    const lobbyStayId = `stay_${lobbyPatientId}_lobby_Main_Lobby`;
    const lobbyRegRes = await send('POST', '/patients/register', {
      ...patient(lobbyPatientId),
      registrationNumber: 'REG-LOBBY-1',
      stays: [
        {
          id: lobbyStayId,
          roomId: 'lobby:Main Lobby',
          roomNumber: 'Main Lobby',
          roomType: 'lobby',
          durationDays: 3,
          admissionDate: '2026-01-01',
        },
      ],
    });
    expect(lobbyRegRes.statusCode).toBe(201);
    expect(lobbyRegRes.json().lobby).toBe('Main Lobby');
    // Virtual lobby room must not appear in standard GET /api/rooms
    const standardRooms = (await send('GET', '/rooms')).json() as Array<{ id: string }>;
    expect(standardRooms.some(r => r.id.startsWith('lobby:'))).toBe(false);

    // 7. Test attendance startDate/endDate range filter and payment PATCH/DELETE
    await send('POST', '/attendance/bulk', {
      date: '2026-01-01',
      kind: 'attendance',
      records: { [longPatientId]: { status: 'Present', date: '2026-01-01' } },
    });
    await send('POST', '/attendance/bulk', {
      date: '2026-01-05',
      kind: 'attendance',
      records: { [longPatientId]: { status: 'Present', date: '2026-01-05' } },
    });
    const rangeRes = await send('GET', '/attendance?kind=attendance&startDate=2026-01-01&endDate=2026-01-02&format=map');
    expect(rangeRes.statusCode).toBe(200);
    expect(Object.keys(rangeRes.json())).toEqual(['2026-01-01']);

    const payRes = await send('POST', '/payments', {
      id: 'pay_test_edit',
      patientId: longPatientId,
      amount: 200,
      method: 'Cash',
    });
    expect(payRes.statusCode).toBe(201);
    const patchPayRes = await send('PATCH', '/payments/pay_test_edit', {
      amount: 250,
      receiptNumber: 'REC-250',
    });
    expect(patchPayRes.statusCode).toBe(200);
    expect(patchPayRes.json().amount).toBe(250);
    expect(patchPayRes.json().receiptNumber).toBe('REC-250');

    const delPayRes = await send('DELETE', '/payments/pay_test_edit');
    expect(delPayRes.statusCode).toBe(200);
    expect((await send('GET', '/payments/pay_test_edit')).statusCode).toBe(404);
  });

  it('measures before/after workflow latency against real PostgreSQL 16', async () => {
    const nowMs = () => performance.now();
    await send('POST', '/rooms', {
      id: 'r_bench',
      roomNumber: 'B101',
      roomType: 'general',
      floor: 1,
      beds: [
        { id: 'r_bench_b1', bedLabel: '1/2' },
        { id: 'r_bench_b2', bedLabel: '2/2' },
      ],
    });

    // Seed 30 days of historical attendance records across 10 patients to measure full scan vs bounded date range
    for (let d = 1; d <= 30; d++) {
      const dayStr = `2026-01-${String(d).padStart(2, '0')}`;
      const records: Record<string, any> = {};
      for (let p = 1; p <= 10; p++) {
        records[`p_hist_${p}`] = { status: 'Present', date: dayStr, source: 'automatic_registration_period' };
      }
      await send('POST', '/attendance/bulk', { date: dayStr, kind: 'attendance', records });
    }

    // 1. Before vs After Registration (5-day stay)
    const tRegBefore0 = nowMs();
    await send('POST', '/patients', { ...patient('p_bench_before'), registrationNumber: '9001' });
    await send('POST', '/stays/batch', {
      stays: [{ id: 'stay_p_bench_before_r_bench_b1', patientId: 'p_bench_before', roomId: 'r_bench', bedId: 'r_bench_b1', durationDays: 5, admissionDate: '2026-02-01' }],
    });
    for (let d = 1; d <= 5; d++) {
      const dayStr = `2026-02-${String(d).padStart(2, '0')}`;
      await send('POST', '/attendance/bulk', {
        date: dayStr,
        kind: 'attendance',
        records: { p_bench_before: { status: 'Present', date: dayStr, source: 'automatic_registration_period', cycleId: 'c1' } },
      });
    }
    const regBeforeMs = nowMs() - tRegBefore0;

    const tRegAfter0 = nowMs();
    const initialAttendance = [];
    for (let d = 1; d <= 5; d++) {
      const dayStr = `2026-02-${String(d).padStart(2, '0')}`;
      initialAttendance.push({
        date: dayStr,
        kind: 'attendance',
        payload: { status: 'Present', date: dayStr, source: 'automatic_registration_period', cycleId: 'c2' },
      });
    }
    const afterRegRes = await send('POST', '/patients/register', {
      ...patient('p_bench_after'),
      registrationNumber: '9002',
      stays: [{ id: 'stay_p_bench_after_r_bench_b2', roomId: 'r_bench', bedId: 'r_bench_b2', durationDays: 5, admissionDate: '2026-02-01' }],
      initialAttendance,
    });
    const regAfterMs = nowMs() - tRegAfter0;
    expect(afterRegRes.statusCode).toBe(201);

    // 2. Patient List & Room Retrieval
    const tPatients0 = nowMs();
    const patientsRes = await send('GET', '/patients?format=map');
    const patientsGetMs = nowMs() - tPatients0;
    expect(patientsRes.statusCode).toBe(200);

    const tRooms0 = nowMs();
    const roomsRes = await send('GET', '/rooms?format=map');
    const roomsGetMs = nowMs() - tRooms0;
    expect(roomsRes.statusCode).toBe(200);

    // 3. Before vs After Attendance Retrieval & Sync (5-day window out of 35 total days)
    const tAttBefore0 = nowMs();
    await send('GET', '/attendance?kind=attendance&format=map');
    for (let d = 1; d <= 5; d++) {
      const dayStr = `2026-02-${String(d).padStart(2, '0')}`;
      await send('POST', '/attendance/bulk', {
        date: dayStr,
        kind: 'attendance',
        records: { p_bench_after: { status: 'Present', date: dayStr, source: 'automatic_registration_period', cycleId: 'c2' } },
      });
    }
    const attBeforeMs = nowMs() - tAttBefore0;

    const tAttAfter0 = nowMs();
    const boundedAttRes = await send('GET', '/attendance?kind=attendance&startDate=2026-02-01&endDate=2026-02-05&format=map');
    const attAfterMs = nowMs() - tAttAfter0;
    expect(boundedAttRes.statusCode).toBe(200);

    // 4. Payment Recording & Balance Refresh
    const tPay0 = nowMs();
    await send('POST', '/payments', {
      id: 'pay_bench_1',
      patientId: 'p_bench_after',
      amount: 1000,
      method: 'Cash',
    });
    await send('PATCH', '/patients/p_bench_after', {
      totalPaidAmount: 1000,
      currentDueAmount: 0,
      paymentPending: false,
      paymentStatus: 'Paid',
    });
    const payMs = nowMs() - tPay0;

    // 5. Before vs After Discharge
    const tDisBefore0 = nowMs();
    await send('GET', '/stays?format=map');
    for (let d = 1; d <= 5; d++) {
      const dayStr = `2026-02-${String(d).padStart(2, '0')}`;
      await send('POST', '/attendance/bulk', {
        date: dayStr,
        kind: 'attendance',
        records: { p_bench_before: { status: 'Present', date: dayStr, source: 'automatic_registration_period', cycleId: 'c1' } },
      });
    }
    await send('PUT', '/stays/stay_p_bench_before_r_bench_b1', { status: 'completed', completedAt: '2026-02-05T10:00:00.000Z' });
    await send('PATCH', '/patients/p_bench_before', { status: 'discharged', dischargeDate: '2026-02-05T10:00:00.000Z' });
    await send('PATCH', '/patients/p_bench_before', { status: 'discharged', dischargeDate: '2026-02-05T10:00:00.000Z' });
    const disBeforeMs = nowMs() - tDisBefore0;

    const tDisAfter0 = nowMs();
    await send('GET', '/stays?patientId=p_bench_after&format=map');
    await send('GET', '/attendance?kind=attendance&startDate=2026-02-01&endDate=2026-02-05&format=map');
    await send('PUT', '/stays/stay_p_bench_after_r_bench_b2', { status: 'completed', completedAt: '2026-02-05T10:00:00.000Z' });
    await send('PATCH', '/patients/p_bench_after', { status: 'discharged', dischargeDate: '2026-02-05T10:00:00.000Z' });
    const disAfterMs = nowMs() - tDisAfter0;

    console.log(JSON.stringify({
      benchmark: 'PG16_FASTIFY_WORKFLOWS_MS',
      regBeforeMs: Number(regBeforeMs.toFixed(2)),
      regAfterMs: Number(regAfterMs.toFixed(2)),
      patientsGetMs: Number(patientsGetMs.toFixed(2)),
      roomsGetMs: Number(roomsGetMs.toFixed(2)),
      attBeforeMs: Number(attBeforeMs.toFixed(2)),
      attAfterMs: Number(attAfterMs.toFixed(2)),
      payMs: Number(payMs.toFixed(2)),
      disBeforeMs: Number(disBeforeMs.toFixed(2)),
      disAfterMs: Number(disAfterMs.toFixed(2)),
    }));
  });
});


