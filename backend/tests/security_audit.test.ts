import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../src/app.js';
import * as db from '../src/db/index.js';
import { config } from '../src/config/index.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

const mockResult = (rows: Record<string, unknown>[] = []) => ({
  rows,
  rowCount: rows.length,
  command: 'SELECT',
  oid: 0,
  fields: [],
});

describe('Security Audit — CORS, Authentication, Authorization and Error Exposure', () => {
  let app: ReturnType<typeof buildApp>;
  let currentUserRole: 'admin' | 'staff' | 'volunteer' = 'staff';
  let currentUserId = 'user-staff-123';
  const originalCorsOrigins = config.CORS_ORIGINS;

  beforeEach(() => {
    vi.restoreAllMocks();
    vi.spyOn(db, 'getClient').mockResolvedValue({
      query: async (sql: string, params?: unknown[]) => /^(BEGIN|COMMIT|ROLLBACK)/.test(sql)
        ? { rows: [], rowCount: 0 } : db.query(sql, params),
      release: vi.fn(),
    } as any);
    currentUserRole = 'staff';
    currentUserId = 'user-staff-123';
    installTestFirebaseKeys();

    // Set an explicit allowlist for CORS tests
    config.CORS_ORIGINS = ['https://trusted.ngo-portal.org', 'http://localhost:3000'];

    vi.spyOn(db, 'query').mockImplementation(async (sql: string, params?: unknown[]) => {
      // Mock user lookup for authentication hook
      if (sql.includes('SELECT id, email, name, role FROM users WHERE id = $1')) {
        const uid = (params?.[0] as string) || currentUserId;
        return mockResult([{
          id: uid,
          email: `${uid}@ngo.test`,
          name: 'Test User',
          role: currentUserRole,
        }]);
      }
      if (sql.includes('FROM users WHERE id = $1')) {
        const uid = params?.[0] as string;
        return mockResult([{
          id: uid,
          email: `${uid}@ngo.test`,
          name: 'Target User',
          phone: '+919876543210',
          role: uid === 'admin-user' ? 'admin' : uid === 'staff-user' ? 'staff' : 'volunteer',
          created_at: new Date('2026-01-01T00:00:00Z'),
          updated_at: new Date('2026-01-01T00:00:00Z'),
        }]);
      }
      if (sql.includes('FROM users')) {
        return mockResult([
          { id: 'u1', email: 'u1@ngo.test', name: 'User 1', phone: null, role: 'volunteer', created_at: new Date(), updated_at: new Date() },
          { id: 'u2', email: 'u2@ngo.test', name: 'User 2', phone: null, role: 'staff', created_at: new Date(), updated_at: new Date() },
        ]);
      }
      if (sql.includes('INSERT INTO users')) {
        return mockResult([{
          id: params?.[0] as string,
          email: params?.[1] as string,
          name: params?.[2] as string,
          phone: params?.[3] as string | null,
          role: params?.[4] as string,
          created_at: new Date(),
          updated_at: new Date(),
        }]);
      }
      if (sql.includes('FROM patients')) {
        return mockResult([]);
      }
      return mockResult();
    });

    app = buildApp({ logger: false });
  });

  afterEach(async () => {
    config.CORS_ORIGINS = originalCorsOrigins;
    await app.close();
    vi.restoreAllMocks();
  });

  const authHeader = (uid = currentUserId, token?: string) => ({
    authorization: `Bearer ${token || signedTestToken(uid)}`,
  });

  it('requires an administrator for a billing correction', async () => {
    for (const role of ['staff', 'volunteer'] as const) {
      currentUserRole = role;
      const response = await app.inject({ method: 'POST', url: '/api/patients/p1/billing-corrections',
        headers: authHeader(), payload: { reason: 'Billing correction', dates: [{ day: '2026-10-01', stayId: 's1', amount: 200 }] } });
      expect(response.statusCode).toBe(403);
    }
    currentUserRole = 'admin';
    const response = await app.inject({ method: 'POST', url: '/api/patients/p1/billing-corrections',
      headers: authHeader(), payload: { reason: 'Billing correction', dates: [{ day: '2026-10-01', stayId: 's1', amount: 200 }] } });
    expect(response.statusCode).toBe(404); // Authorization passed; synthetic patient is absent.
  });

  // ── 1. Unauthenticated and Invalid Token Requests ──────────────────────────
  describe('1. API Route Authentication', () => {
    it('rejects requests without Authorization header with 401 Unauthorized', async () => {
      const res = await app.inject({
        method: 'GET',
        url: '/api/patients',
      });
      expect(res.statusCode).toBe(401);
      const json = res.json();
      expect(json.error).toBe('Unauthorized');
      expect(json.message).toContain('Missing or invalid Authorization header');
    });

    it('rejects requests with malformed Bearer token with 401 Unauthorized', async () => {
      const res = await app.inject({
        method: 'GET',
        url: '/api/patients',
        headers: { authorization: 'Bearer not-a-valid-jwt-token' },
      });
      expect(res.statusCode).toBe(401);
      const json = res.json();
      expect(json.error).toBe('Unauthorized');
      expect(json.message).toBe('Invalid or expired Firebase ID token');
    });

    it('rejects expired Firebase token with 401 Unauthorized', async () => {
      const expiredToken = signedTestToken(currentUserId, {
        exp: Math.floor(Date.now() / 1000) - 300,
      });
      const res = await app.inject({
        method: 'GET',
        url: '/api/patients',
        headers: authHeader(currentUserId, expiredToken),
      });
      expect(res.statusCode).toBe(401);
      expect(res.json().message).toBe('Invalid or expired Firebase ID token');
    });

    it('rejects requests with non-Bearer authorization scheme', async () => {
      const res = await app.inject({
        method: 'GET',
        url: '/api/patients',
        headers: { authorization: 'Basic dXNlcjpwYXNz' },
      });
      expect(res.statusCode).toBe(401);
    });
  });

  // ── 2. CORS and Client Exposure ────────────────────────────────────
  describe('2. CORS Configuration', () => {
    it('allows native Flutter Windows desktop requests with no Origin header', async () => {
      const res = await app.inject({
        method: 'GET',
        url: '/api/patients',
        headers: authHeader(),
      });
      expect(res.statusCode).toBe(200);
      // Native desktop requests receive no Access-Control-Allow-Origin header
      expect(res.headers['access-control-allow-origin']).toBeUndefined();
    });

    it('handles OPTIONS preflight for explicitly approved browser origin', async () => {
      const res = await app.inject({
        method: 'OPTIONS',
        url: '/api/patients',
        headers: {
          origin: 'https://trusted.ngo-portal.org',
          'access-control-request-method': 'GET',
          'access-control-request-headers': 'authorization,content-type',
        },
      });
      expect(res.statusCode).toBe(204);
      expect(res.headers['access-control-allow-origin']).toBe('https://trusted.ngo-portal.org');
      expect(res.headers['access-control-allow-credentials']).toBe('true');
      expect(String(res.headers['access-control-allow-methods'])).toContain('GET');
      expect(String(res.headers['access-control-allow-headers']).toLowerCase()).toContain('authorization');
    });

    it('rejects browser preflight for unapproved origin by omitting CORS headers', async () => {
      const res = await app.inject({
        method: 'OPTIONS',
        url: '/api/patients',
        headers: {
          origin: 'https://attacker.evil.com',
          'access-control-request-method': 'GET',
        },
      });
      expect(res.headers['access-control-allow-origin']).toBeUndefined();
    });

    it('attaches CORS header for approved browser origin on GET request', async () => {
      const res = await app.inject({
        method: 'GET',
        url: '/api/patients',
        headers: {
          ...authHeader(),
          origin: 'https://trusted.ngo-portal.org',
        },
      });
      expect(res.statusCode).toBe(200);
      expect(res.headers['access-control-allow-origin']).toBe('https://trusted.ngo-portal.org');
      expect(res.headers['access-control-allow-credentials']).toBe('true');
    });

    it('omits CORS header for unapproved browser origin on GET request', async () => {
      const res = await app.inject({
        method: 'GET',
        url: '/api/patients',
        headers: {
          ...authHeader(),
          origin: 'https://attacker.evil.com',
        },
      });
      expect(res.headers['access-control-allow-origin']).toBeUndefined();
    });

    it('does not treat the Origin header as authentication or identity', async () => {
      // Sending a trusted origin without token must still be rejected with 401
      const res = await app.inject({
        method: 'GET',
        url: '/api/patients',
        headers: {
          origin: 'https://trusted.ngo-portal.org',
        },
      });
      expect(res.statusCode).toBe(401);
    });

    it('never uses wildcard * as a substitute for approved origins when configured', async () => {
      // Even if CORS_ORIGINS was originally set to ['*'], the verifier removes it
      config.CORS_ORIGINS = [];
      const res = await app.inject({
        method: 'OPTIONS',
        url: '/api/patients',
        headers: {
          origin: 'https://random-site.com',
          'access-control-request-method': 'GET',
        },
      });
      expect(res.headers['access-control-allow-origin']).toBeUndefined();
    });
  });

  // ── 3. Authorization and Privilege Escalation Protections ──────────────────
  describe('3. Role Authorization and Privilege Escalation', () => {
    it('allows volunteer to read their own user profile', async () => {
      currentUserRole = 'volunteer';
      currentUserId = 'volunteer-456';

      const res = await app.inject({
        method: 'GET',
        url: '/api/users/volunteer-456',
        headers: authHeader('volunteer-456'),
      });

      expect(res.statusCode).toBe(200);
      expect(res.json().id).toBe('volunteer-456');
    });

    it('denies volunteer from reading another user profile with 403 Forbidden', async () => {
      currentUserRole = 'volunteer';
      currentUserId = 'volunteer-456';

      const res = await app.inject({
        method: 'GET',
        url: '/api/users/other-user-789',
        headers: authHeader('volunteer-456'),
      });

      expect(res.statusCode).toBe(403);
      expect(res.json().error).toBe('Forbidden');
      expect(res.json().message).toBe('Insufficient permissions');
    });

    it('denies volunteer from listing all users with 403 Forbidden', async () => {
      currentUserRole = 'volunteer';
      currentUserId = 'volunteer-456';

      const res = await app.inject({
        method: 'GET',
        url: '/api/users',
        headers: authHeader('volunteer-456'),
      });

      expect(res.statusCode).toBe(403);
      expect(res.json().error).toBe('Forbidden');
    });

    it('allows staff to list all users', async () => {
      currentUserRole = 'staff';
      currentUserId = 'staff-123';

      const res = await app.inject({
        method: 'GET',
        url: '/api/users',
        headers: authHeader('staff-123'),
      });

      expect(res.statusCode).toBe(200);
      expect(typeof res.json()).toBe('object');
    });

    it('denies staff from modifying another user profile with 403 Forbidden', async () => {
      currentUserRole = 'staff';
      currentUserId = 'staff-123';

      const res = await app.inject({
        method: 'PUT',
        url: '/api/users/another-user-999',
        headers: authHeader('staff-123'),
        payload: {
          name: 'Hacked Name',
        },
      });

      expect(res.statusCode).toBe(403);
      expect(res.json().error).toBe('Forbidden');
      expect(res.json().message).toBe('Cannot modify another user account');
    });

    it('denies staff from escalating their own role to admin with 403 Forbidden', async () => {
      currentUserRole = 'staff';
      currentUserId = 'staff-123';

      const res = await app.inject({
        method: 'PUT',
        url: '/api/users/staff-123',
        headers: authHeader('staff-123'),
        payload: {
          role: 'admin',
        },
      });

      expect(res.statusCode).toBe(403);
      expect(res.json().error).toBe('Forbidden');
      expect(res.json().message).toBe('Insufficient permissions to change role');
    });

    it('allows admin to update another user and assign a role', async () => {
      currentUserRole = 'admin';
      currentUserId = 'admin-001';

      const res = await app.inject({
        method: 'PUT',
        url: '/api/users/user-to-promote',
        headers: authHeader('admin-001'),
        payload: {
          name: 'Promoted User',
          role: 'staff',
        },
      });

      expect(res.statusCode).toBe(200);
      expect(res.json().role).toBe('staff');
    });

    it('rejects invalid role assignment with 400 Bad Request', async () => {
      currentUserRole = 'admin';
      currentUserId = 'admin-001';

      const res = await app.inject({
        method: 'PUT',
        url: '/api/users/user-test',
        headers: authHeader('admin-001'),
        payload: {
          role: 'super_admin_invalid',
        },
      });

      expect(res.statusCode).toBe(400);
      expect(res.json().error).toBe('BadRequest');
    });
  });

  // ── 4. Error Handling and Secret Masking ────────────────────────────────────
  describe('4. Error Handling and Information Disclosure', () => {
    it('masks 500 error messages and never exposes stack traces or db credentials', async () => {
      vi.spyOn(db, 'query').mockImplementation(async (sql: string) => {
        if (sql.includes('SELECT id, email, name, role FROM users')) {
          return mockResult([{ id: currentUserId, email: 'admin@ngo.test', name: 'Admin', role: 'admin' }]);
        }
        throw new Error('FATAL: password authentication failed for user "ngo_user" at 10.0.0.1:5432');
      });

      const res = await app.inject({
        method: 'GET',
        url: '/api/patients',
        headers: authHeader(),
      });

      expect(res.statusCode).toBe(500);
      const json = res.json();
      expect(json.error).toBe('InternalServerError');
      expect(json.message).toBe('An unexpected error occurred');
      expect(res.body).not.toContain('password');
      expect(res.body).not.toContain('ngo_user');
      expect(res.body).not.toContain('10.0.0.1');
      expect(res.body).not.toContain('FATAL');
    });

    it('masks PostgreSQL constraint error details from leaking internal database columns', async () => {
      vi.spyOn(db, 'query').mockImplementation(async (sql: string) => {
        if (sql.includes('SELECT id, email, name, role FROM users')) {
          return mockResult([{ id: currentUserId, email: 'admin@ngo.test', name: 'Admin', role: 'admin' }]);
        }
        const err = Object.assign(new Error('Key (id)=(p_dup) already exists in table "patients"'), { code: '23505' });
        throw err;
      });

      const res = await app.inject({
        method: 'GET',
        url: '/api/patients',
        headers: authHeader(),
      });

      expect(res.statusCode).toBe(409);
      const json = res.json();
      expect(json.error).toBe('Conflict');
      expect(json.message).toBe('The request conflicts with database constraints or contains invalid data');
      expect(res.body).not.toContain('Key (id)=(p_dup)');
    });

    it('health and readiness endpoints return minimal operational status without secrets', async () => {
      vi.spyOn(db, 'checkDatabaseConnection').mockResolvedValue({
        healthy: true,
        latencyMs: 1.5,
        timestamp: new Date().toISOString(),
      });

      const healthRes = await app.inject({ method: 'GET', url: '/health' });
      expect(healthRes.statusCode).toBe(200);
      const healthJson = healthRes.json();
      expect(healthJson.status).toBe('healthy');
      expect(healthJson.service).toBe('ngo-backend');
      expect(Object.keys(healthJson)).toEqual(['status', 'service', 'version', 'uptimeSeconds', 'timestamp']);

      const readyRes = await app.inject({ method: 'GET', url: '/ready' });
      expect(readyRes.statusCode).toBe(200);
      const readyJson = readyRes.json();
      expect(readyJson.status).toBe('ready');
      expect(readyJson.database).toBe('connected');
      expect(Object.keys(readyJson)).toEqual(['status', 'database', 'latencyMs', 'timestamp']);
    });
  });
});
