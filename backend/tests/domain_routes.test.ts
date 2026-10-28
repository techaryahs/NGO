import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { buildApp } from '../src/app.js';
import * as dbModule from '../src/db/index.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

describe('Domain Routes and Authentication', () => {
  let app: ReturnType<typeof buildApp>;

  beforeEach(() => {
    vi.restoreAllMocks();
    vi.spyOn(dbModule, 'getClient').mockResolvedValue({
      query: async (sql: string, params?: unknown[]) => /^(BEGIN|COMMIT|ROLLBACK)/.test(sql)
        ? { rows: [], rowCount: 0 } : dbModule.query(sql, params),
      release: vi.fn(),
    } as any);
    installTestFirebaseKeys();
    app = buildApp();
  });

  afterEach(async () => { await app.close(); vi.restoreAllMocks(); });

  it('rejects unauthenticated requests to protected endpoints with 401', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/patients',
    });
    expect(res.statusCode).toBe(401);
    const body = JSON.parse(res.body);
    expect(body.error).toBe('Unauthorized');
  });

  it('authenticates a signed Firebase token and allows access', async () => {
    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string, _params?: unknown[]) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'test-uid-admin', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('FROM patients')) {
        return {
          rows: [],
          rowCount: 0,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'GET',
      url: '/api/patients',
      headers: {
        authorization: `Bearer ${signedTestToken('test-uid-admin')}`,
      },
    });

    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toEqual([]);
  });

  it('denies delete patient if user role is volunteer with 403', async () => {
    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'test-uid-volunteer', email: 'volunteer@ngo.test', name: 'Volunteer', role: 'volunteer' }],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/patients/p_123',
      headers: {
        authorization: `Bearer ${signedTestToken('test-uid-volunteer')}`,
      },
    });

    expect(res.statusCode).toBe(403);
    const body = JSON.parse(res.body);
    expect(body.error).toBe('Forbidden');
  });

  it('POST /api/counters/registrationNumber/next increments sequence atomically', async () => {
    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string, params?: unknown[]) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'test-uid-staff', email: 'staff@ngo.test', name: 'Staff', role: 'staff' }],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('system_counters')) {
        return {
          rows: [{ counter_name: params?.[0] || 'registrationNumber', current_value: 1042 }],
          rowCount: 1,
          command: 'INSERT',
          oid: 0,
          fields: [],
        };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'POST',
      url: '/api/counters/registrationNumber/next',
      headers: {
        authorization: `Bearer ${signedTestToken('test-uid-staff')}`,
      },
    });

    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.counterName).toBe('registrationNumber');
    expect(body.nextValue).toBe(1042);
    expect(body.formatted).toBe('1042');
  });

  it('GET /api/rooms returns list of rooms with nested beds', async () => {
    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'test-uid-staff', email: 'staff@ngo.test', name: 'Staff', role: 'staff' }],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('FROM rooms')) {
        return {
          rows: [
            {
              id: 'r_1A',
              room_number: '1A',
              room_identifier: '1A',
              floor: 1,
              room_type: 'private',
              status: 'available',
              max_attendants: 5,
              current_attendants: 0,
              has_custom_attendant_limit: false,
              total_beds: 1,
              occupied_beds: 0,
              expected_vacancy_date: null,
              version: 1,
              notes: null,
              created_at: new Date('2026-01-01'),
              updated_at: new Date('2026-01-01'),
            },
          ],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('FROM room_beds')) {
        return {
          rows: [
            {
              id: 'r_1A_bed1',
              room_id: 'r_1A',
              bed_label: '1',
              status: 'available',
              current_patient_id: null,
              current_stay_id: null,
              last_cleaned: null,
            },
          ],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'GET',
      url: '/api/rooms',
      headers: {
        authorization: `Bearer ${signedTestToken('test-uid-staff')}`,
      },
    });

    expect(res.statusCode).toBe(200);
    const rooms = JSON.parse(res.body);
    expect(rooms.length).toBe(1);
    expect(rooms[0].roomNumber).toBe('1A');
    expect(rooms[0].beds.length).toBe(1);
    expect(rooms[0].beds[0].bedLabel).toBe('1');
  });
});
