import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { buildApp } from '../src/app.js';
import * as dbModule from '../src/db/index.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

describe('Admin Patient Deletion Suite', () => {
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

  // 1. Non-administrators cannot delete a patient
  it('rejects deletion with 403 Forbidden for staff account', async () => {
    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'staff-user', email: 'staff@ngo.test', name: 'Staff', role: 'staff' }],
          rowCount: 1, command: 'SELECT', oid: 0, fields: [],
        };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/patients/p_victim',
      headers: { authorization: `Bearer ${signedTestToken('staff-user')}` },
    });

    expect(res.statusCode).toBe(403);
    const body = JSON.parse(res.body);
    expect(body.error).toBe('Forbidden');
    expect(body.message).toBe('Insufficient permissions');
  });

  it('rejects deletion with 403 Forbidden for volunteer account', async () => {
    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'vol-user', email: 'vol@ngo.test', name: 'Volunteer', role: 'volunteer' }],
          rowCount: 1, command: 'SELECT', oid: 0, fields: [],
        };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/patients/p_victim',
      headers: { authorization: `Bearer ${signedTestToken('vol-user')}` },
    });

    expect(res.statusCode).toBe(403);
    const body = JSON.parse(res.body);
    expect(body.error).toBe('Forbidden');
  });

  it('rejects unauthenticated deletion with 401 Unauthorized', async () => {
    const res = await app.inject({
      method: 'DELETE',
      url: '/api/patients/p_victim',
    });

    expect(res.statusCode).toBe(401);
  });

  // 2. Returns 404 if patient not found
  it('returns 404 NotFound when deleting a non-existent patient', async () => {
    let rolledBack = false;
    const mockClient = {
      query: vi.fn(async (sql: string) => {
        if (sql === 'BEGIN') return { rows: [], rowCount: 0 };
        if (sql === 'ROLLBACK') {
          rolledBack = true;
          return { rows: [], rowCount: 0 };
        }
        if (sql.includes('SELECT id FROM patients WHERE id = $1 FOR UPDATE')) {
          return { rows: [], rowCount: 0 }; // Not found
        }
        return { rows: [], rowCount: 0 };
      }),
      release: vi.fn(),
    };

    vi.spyOn(dbModule, 'getClient').mockResolvedValue(mockClient as any);
    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'admin-user', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1, command: 'SELECT', oid: 0, fields: [],
        };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/patients/p_nonexistent',
      headers: { authorization: `Bearer ${signedTestToken('admin-user')}` },
    });

    expect(res.statusCode).toBe(404);
    expect(rolledBack).toBe(true);
    expect(mockClient.release).toHaveBeenCalled();
  });

  // 3. Admin can delete a patient with no related history
  it('successfully deletes a patient with no related history in a transaction', async () => {
    const executedQueries: string[] = [];
    let committed = false;

    const mockClient = {
      query: vi.fn(async (sql: string, params?: unknown[]) => {
        executedQueries.push(sql);
        if (sql === 'BEGIN') return { rows: [], rowCount: 0 };
        if (sql === 'COMMIT') {
          committed = true;
          return { rows: [], rowCount: 0 };
        }
        if (sql.includes('SELECT id FROM patients WHERE id = $1 FOR UPDATE')) {
          return { rows: [{ id: 'p_simple' }], rowCount: 1 };
        }
        if (sql.includes('SELECT DISTINCT room_id FROM')) {
          return { rows: [], rowCount: 0 };
        }
        if (sql.includes('DELETE FROM patients WHERE id = $1 RETURNING id')) {
          return { rows: [{ id: 'p_simple' }], rowCount: 1 };
        }
        return { rows: [], rowCount: 0 };
      }),
      release: vi.fn(),
    };

    vi.spyOn(dbModule, 'getClient').mockResolvedValue(mockClient as any);
    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'admin-user', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1, command: 'SELECT', oid: 0, fields: [],
        };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/patients/p_simple',
      headers: { authorization: `Bearer ${signedTestToken('admin-user')}` },
    });

    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toEqual({ success: true, deletedId: 'p_simple' });
    expect(committed).toBe(true);
    expect(mockClient.release).toHaveBeenCalled();
  });

  // 4. Admin deletes a patient with stays, attendance, payments, attendants, photos, and bed assignments
  it('deletes patient and all exclusively dependent records and releases bed in a single transaction', async () => {
    const executedQueries: string[] = [];
    const queryParams: unknown[][] = [];
    let committed = false;

    const mockClient = {
      query: vi.fn(async (sql: string, params?: unknown[]) => {
        executedQueries.push(sql);
        if (params) queryParams.push(params);

        if (sql === 'BEGIN') return { rows: [], rowCount: 0 };
        if (sql === 'COMMIT') {
          committed = true;
          return { rows: [], rowCount: 0 };
        }
        if (sql.includes('SELECT id FROM patients WHERE id = $1 FOR UPDATE')) {
          return { rows: [{ id: 'p_full' }], rowCount: 1 };
        }
        if (sql.includes('SELECT DISTINCT room_id FROM')) {
          return { rows: [{ room_id: 'room_101' }], rowCount: 1 };
        }
        if (sql.includes('UPDATE room_beds')) {
          return { rows: [], rowCount: 1 };
        }
        if (sql.includes('UPDATE sponsorships')) {
          return { rows: [], rowCount: 0 };
        }
        if (sql.includes('DELETE FROM attendance_records WHERE patient_id = $1')) {
          return { rows: [], rowCount: 12 };
        }
        if (sql.includes('DELETE FROM patient_attendants WHERE patient_id = $1')) {
          return { rows: [], rowCount: 1 };
        }
        if (sql.includes('DELETE FROM payments WHERE patient_id = $1')) {
          return { rows: [], rowCount: 3 };
        }
        if (sql.includes('DELETE FROM patient_photos WHERE patient_id = $1')) {
          return { rows: [], rowCount: 1 };
        }
        if (sql.includes('DELETE FROM stays WHERE patient_id = $1')) {
          return { rows: [], rowCount: 1 };
        }
        if (sql.includes('DELETE FROM patients WHERE id = $1 RETURNING id')) {
          return { rows: [{ id: 'p_full' }], rowCount: 1 };
        }
        if (sql.includes('UPDATE rooms SET')) {
          // refreshRoomOccupancy query
          return { rows: [], rowCount: 1 };
        }
        return { rows: [], rowCount: 0 };
      }),
      release: vi.fn(),
    };

    vi.spyOn(dbModule, 'getClient').mockResolvedValue(mockClient as any);
    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'admin-user', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1, command: 'SELECT', oid: 0, fields: [],
        };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/patients/p_full',
      headers: { authorization: `Bearer ${signedTestToken('admin-user')}` },
    });

    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toEqual({ success: true, deletedId: 'p_full' });
    expect(committed).toBe(true);

    // Verify correct execution order:
    // 1. BEGIN
    expect(executedQueries[0]).toBe('BEGIN');
    // 2. Lock patient
    expect(executedQueries[1]).toContain('FOR UPDATE');
    // 3. Find affected rooms
    expect(executedQueries[2]).toContain('SELECT DISTINCT room_id FROM');
    expect(executedQueries[3]).toContain('SELECT id FROM rooms');
    expect(executedQueries[3]).toContain('FOR UPDATE');
    // 4. Clear bed assignments
    expect(executedQueries[4]).toContain('UPDATE room_beds');
    expect(executedQueries[4]).toContain("status = 'available'");
    // 5. Clear sponsorships
    expect(executedQueries[5]).toContain('UPDATE sponsorships SET patient_id = NULL');
    // 6. Delete attendance
    expect(executedQueries[6]).toContain('DELETE FROM attendance_records WHERE patient_id = $1');
    // 7. Delete attendants
    expect(executedQueries[7]).toContain('DELETE FROM patient_attendants WHERE patient_id = $1');
    // 8. Delete payments
    expect(executedQueries[8]).toContain('DELETE FROM payments WHERE patient_id = $1');
    // 9. Delete photos
    expect(executedQueries[9]).toContain('DELETE FROM patient_photos WHERE patient_id = $1');
    // 10. Delete stays
    expect(executedQueries[10]).toContain('DELETE FROM stays WHERE patient_id = $1');
    // 11. Delete patient
    expect(executedQueries[11]).toContain('DELETE FROM patients WHERE id = $1 RETURNING id');
    // 12. Refresh occupancy for room_101
    expect(executedQueries[12]).toContain('UPDATE rooms SET');
    // 13. COMMIT
    expect(executedQueries[13]).toBe('COMMIT');

    // All patient-bound deletes must use the target patient id 'p_full'
    for (const params of queryParams) {
      if (params.length === 1 && typeof params[0] === 'string') {
        expect(['p_full', 'room_101']).toContain(params[0]);
      }
    }
  });

  // 5. Simulated transaction failure rolls back cleanly
  it('rolls back the transaction and releases client when any dependent query fails', async () => {
    let rolledBack = false;

    const mockClient = {
      query: vi.fn(async (sql: string) => {
        if (sql === 'BEGIN') return { rows: [], rowCount: 0 };
        if (sql === 'ROLLBACK') {
          rolledBack = true;
          return { rows: [], rowCount: 0 };
        }
        if (sql.includes('SELECT id FROM patients WHERE id = $1 FOR UPDATE')) {
          return { rows: [{ id: 'p_fail' }], rowCount: 1 };
        }
        if (sql.includes('SELECT DISTINCT room_id FROM')) {
          return { rows: [{ room_id: 'room_101' }], rowCount: 1 };
        }
        if (sql.includes('UPDATE room_beds')) {
          throw new Error('Simulated database deadlock / constraint failure');
        }
        return { rows: [], rowCount: 0 };
      }),
      release: vi.fn(),
    };

    vi.spyOn(dbModule, 'getClient').mockResolvedValue(mockClient as any);
    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'admin-user', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1, command: 'SELECT', oid: 0, fields: [],
        };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/patients/p_fail',
      headers: { authorization: `Bearer ${signedTestToken('admin-user')}` },
    });

    expect(res.statusCode).toBe(500);
    expect(rolledBack).toBe(true);
    expect(mockClient.release).toHaveBeenCalled();
  });
});
