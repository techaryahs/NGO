import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { buildApp } from '../src/app.js';
import * as dbModule from '../src/db/index.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

describe('Attendance Identity Isolation & Same-Name Patient Verification', () => {
  let app: ReturnType<typeof buildApp>;

  beforeEach(() => {
    vi.restoreAllMocks();
    installTestFirebaseKeys();
    app = buildApp({ logger: false });
  });

  afterEach(async () => {
    await app.close();
    vi.restoreAllMocks();
  });

  it('GET /api/attendance with format=map returns records strictly partitioned by patient_id, never name', async () => {
    const mockRows = [
      {
        id: 'attendance/2026-10-15/patient_A',
        kind: 'attendance',
        attendance_date: '2026-10-15',
        patient_id: 'patient_A',
        payload: { status: 'Absent', source: 'manual', patientName: 'test', patientId: 'patient_A' },
        created_at: new Date(),
        updated_at: new Date(),
      },
      {
        id: 'attendance/2026-10-15/patient_B',
        kind: 'attendance',
        attendance_date: '2026-10-15',
        patient_id: 'patient_B',
        payload: { status: 'Present', source: 'automatic_registration_period', patientName: 'test', patientId: 'patient_B' },
        created_at: new Date(),
        updated_at: new Date(),
      },
    ];

    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string, params?: unknown[]) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'test-admin', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1, command: 'SELECT', oid: 0, fields: [],
        };
      }
      if (sql.includes('FROM attendance_records')) {
        if (params && params.includes('patient_A')) {
          return {
            rows: mockRows.filter(r => r.patient_id === 'patient_A'),
            rowCount: 1, command: 'SELECT', oid: 0, fields: [],
          };
        }
        if (params && params.includes('patient_B')) {
          return {
            rows: mockRows.filter(r => r.patient_id === 'patient_B'),
            rowCount: 1, command: 'SELECT', oid: 0, fields: [],
          };
        }
        return {
          rows: mockRows,
          rowCount: mockRows.length, command: 'SELECT', oid: 0, fields: [],
        };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    // 1. Query for entire month without patientId filter: map should have day -> patientId keys
    const resAll = await app.inject({
      method: 'GET',
      url: '/api/attendance?startDate=2026-10-01&endDate=2026-10-31&format=map',
      headers: { authorization: `Bearer ${signedTestToken()}` },
    });
    expect(resAll.statusCode).toBe(200);
    const bodyAll = JSON.parse(resAll.body);
    expect(bodyAll['2026-10-15']).toBeDefined();
    expect(bodyAll['2026-10-15']['patient_A'].status).toBe('Absent');
    expect(bodyAll['2026-10-15']['patient_B'].status).toBe('Present');

    // 2. Query filtered by patient_A: must never include patient_B even though both have patientName='test'
    const resA = await app.inject({
      method: 'GET',
      url: '/api/attendance?startDate=2026-10-01&endDate=2026-10-31&format=map&patientId=patient_A',
      headers: { authorization: `Bearer ${signedTestToken()}` },
    });
    expect(resA.statusCode).toBe(200);
    const bodyA = JSON.parse(resA.body);
    expect(bodyA['2026-10-15']['patient_A']).toBeDefined();
    expect(bodyA['2026-10-15']['patient_B']).toBeUndefined();

    // 3. Query filtered by patient_B: must never include patient_A
    const resB = await app.inject({
      method: 'GET',
      url: '/api/attendance?startDate=2026-10-01&endDate=2026-10-31&format=map&patientId=patient_B',
      headers: { authorization: `Bearer ${signedTestToken()}` },
    });
    expect(resB.statusCode).toBe(200);
    const bodyB = JSON.parse(resB.body);
    expect(bodyB['2026-10-15']['patient_B']).toBeDefined();
    expect(bodyB['2026-10-15']['patient_A']).toBeUndefined();
  });

  it('POST /api/attendance constructs record ID using kind/date/patientId and isolates upserts', async () => {
    let capturedId = '';
    let capturedPatientId = '';
    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string, params?: unknown[]) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'test-admin', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1, command: 'SELECT', oid: 0, fields: [],
        };
      }
      if (sql.includes('INSERT INTO attendance_records')) {
        capturedId = params![0] as string;
        capturedPatientId = params![3] as string;
        return {
          rows: [{
            id: capturedId,
            kind: 'attendance',
            attendance_date: '2026-10-19',
            patient_id: capturedPatientId,
            payload: { status: 'Present', patientName: 'test' },
          }],
          rowCount: 1, command: 'INSERT', oid: 0, fields: [],
        };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    vi.spyOn(dbModule, 'getClient').mockResolvedValue({
      query: async (sql: string, params?: unknown[]) => sql.includes('SELECT id FROM patients')
        ? { rows: [{ id: 'patient_B' }], rowCount: 1 }
        : dbModule.query(sql, params),
      release: vi.fn(),
    } as any);

    const res = await app.inject({
      method: 'POST',
      url: '/api/attendance',
      headers: { authorization: `Bearer ${signedTestToken()}` },
      payload: {
        date: '2026-10-19',
        kind: 'attendance',
        patientId: 'patient_B',
        payload: {
          patientId: 'patient_B',
          patientName: 'test',
          status: 'Present',
          source: 'manual',
        },
      },
    });

    expect(res.statusCode).toBe(200);
    expect(capturedId).toBe('attendance/2026-10-19/patient_B');
    expect(capturedPatientId).toBe('patient_B');
  });
});
