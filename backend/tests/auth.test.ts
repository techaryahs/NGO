import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { generateKeyPairSync } from 'node:crypto';
import jwt from 'jsonwebtoken';
import { buildApp } from '../src/app.js';
import * as db from '../src/db/index.js';
import { config } from '../src/config/index.js';
import { installTestFirebaseKeys, signedTestToken, TEST_FIREBASE_KID } from './helpers/auth.js';

const result = (rows: Record<string, unknown>[] = []) => ({ rows, rowCount: rows.length, command: 'SELECT', oid: 0, fields: [] });

describe('Firebase authentication and authoritative authorization', () => {
  let app: ReturnType<typeof buildApp>;
  let role = 'staff';
  beforeEach(() => {
    vi.restoreAllMocks();
    role = 'staff';
    installTestFirebaseKeys();
    vi.spyOn(db, 'query').mockImplementation(async (sql: string) => {
      if (sql.includes('FROM users')) return result([{ id: 'test-uid-staff', email: 'staff@ngo.test', name: 'Staff', role }]);
      return result();
    });
    app = buildApp({ logger: false });
  });
  afterEach(async () => { await app.close(); vi.restoreAllMocks(); });

  const auth = (token = signedTestToken('test-uid-staff')) => ({ authorization: `Bearer ${token}` });

  it('accepts a signed Firebase token and queries by authoritative UID only', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/patients', headers: auth() });
    expect(res.statusCode).toBe(200);
    expect(db.query).toHaveBeenCalledWith(expect.stringMatching(/WHERE id = \$1\s*$/), ['test-uid-staff']);
  });

  it.each(['garbage', 'test-token-admin', 'eyJhbGciOiJub25lIn0.eyJzdWIiOiJhZG1pbiJ9.'])('rejects malformed or unsigned tokens: %s', async token => {
    const res = await app.inject({ method: 'GET', url: '/api/patients', headers: auth(token) });
    expect(res.statusCode).toBe(401);
    expect(db.query).not.toHaveBeenCalled();
    expect(res.json().message).toBe('Invalid or expired Firebase ID token');
  });

  it.each([
    { exp: Math.floor(Date.now() / 1000) - 10 },
    { aud: 'other-project' },
    { aud: ['ngo-audit-test', 'other-project'] },
    { iss: 'https://attacker.example' },
    { sub: '' },
    { sub: 'x'.repeat(129) },
    { user_id: 'other-uid' },
    { auth_time: Math.floor(Date.now() / 1000) + 3600 },
    { iat: Math.floor(Date.now() / 1000) + 3600 },
    { exp: undefined },
    { auth_time: undefined },
  ])('rejects invalid required claims: %j', async claims => {
    const res = await app.inject({ method: 'GET', url: '/api/patients', headers: auth(signedTestToken('test-uid-staff', claims)) });
    expect(res.statusCode).toBe(401);
    expect(db.query).not.toHaveBeenCalled();
  });

  it('rejects a validly shaped token signed by an untrusted key with a trusted kid', async () => {
    const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
    const payload = jwt.decode(signedTestToken('test-uid-staff')) as jwt.JwtPayload;
    const token = jwt.sign(payload, privateKey, { algorithm: 'RS256', keyid: TEST_FIREBASE_KID });
    const res = await app.inject({ method: 'GET', url: '/api/patients', headers: auth(token) });
    expect(res.statusCode).toBe(401);
    expect(db.query).not.toHaveBeenCalled();
  });

  it('ignores token/body role escalation and denies volunteer access to clinical data', async () => {
    role = 'volunteer';
    const res = await app.inject({ method: 'PUT', url: '/api/patients/synthetic-patient', headers: auth(signedTestToken('test-uid-staff', { role: 'admin' })), payload: { role: 'admin', userId: 'admin' } });
    expect(res.statusCode).toBe(403);
    expect(vi.mocked(db.query).mock.calls).toHaveLength(1);
  });

  it.each(['patients', 'rooms', 'stays', 'attendance', 'payments', 'photos/patientPhotos/p/patient', 'settings/general', 'counters/registrationNumber'])('denies volunteer reads from /api/%s', async path => {
    role = 'volunteer';
    const res = await app.inject({ method: 'GET', url: `/api/${path}`, headers: auth() });
    expect(res.statusCode).toBe(403);
  });

  it('allows staff settings reads but denies settings writes', async () => {
    const read = await app.inject({ method: 'GET', url: '/api/settings/general', headers: auth() });
    const write = await app.inject({ method: 'PUT', url: '/api/settings/general/fees', headers: auth(), payload: { fee: 1 } });
    expect(read.statusCode).toBe(200);
    expect(write.statusCode).toBe(403);
  });

  it('allows admin settings writes', async () => {
    role = 'admin';
    vi.mocked(db.query).mockImplementation(async sql => sql.includes('FROM users') ? result([{ id: 'test-uid-staff', email: 'admin@ngo.test', name: 'Admin', role }]) : result([{ settings_value: { fee: 1 } }]));
    const res = await app.inject({ method: 'PUT', url: '/api/settings/general/fees', headers: auth(), payload: { fee: 1 } });
    expect(res.statusCode).toBe(200);
  });

  it('denies staff patient deletion even with an admin token claim', async () => {
    const res = await app.inject({ method: 'DELETE', url: '/api/patients/synthetic-patient', headers: auth(signedTestToken('test-uid-staff', { role: 'admin' })) });
    expect(res.statusCode).toBe(403);
    expect(vi.mocked(db.query).mock.calls).toHaveLength(1);
  });

  it('never links an unknown UID to an existing account by email', async () => {
    vi.mocked(db.query).mockImplementation(async sql => {
      if (sql.startsWith('SELECT')) return result();
      return result([{ id: 'test-uid-staff', email: 'existing-admin@ngo.test', name: 'New account', role: 'volunteer' }]);
    });
    const res = await app.inject({ method: 'GET', url: '/api/patients', headers: auth(signedTestToken('test-uid-staff', { email: 'existing-admin@ngo.test', role: 'admin' })) });
    expect(res.statusCode).toBe(403);
    expect(db.query).toHaveBeenCalledWith('SELECT id, email, name, role FROM users WHERE id = $1', ['test-uid-staff']);
    const insertion = vi.mocked(db.query).mock.calls.find(call => call[0].includes('INSERT INTO users'));
    expect(insertion?.[0]).toContain("'volunteer'");
  });

  it('allows volunteer ERP reads but denies ERP writes', async () => {
    role = 'volunteer';
    const read = await app.inject({ method: 'GET', url: '/api/erp/inventory', headers: auth() });
    const write = await app.inject({ method: 'POST', url: '/api/erp/inventory', headers: auth(), payload: { name: 'Synthetic' } });
    expect(read.statusCode).toBe(200);
    expect(write.statusCode).toBe(403);
  });

  it('returns a safe service error for a failed authoritative role lookup', async () => {
    vi.mocked(db.query).mockRejectedValue(new Error('password=DO_NOT_LEAK host=private-db'));
    const res = await app.inject({ method: 'GET', url: '/api/patients', headers: auth() });
    expect(res.statusCode).toBe(503);
    expect(res.body).not.toContain('DO_NOT_LEAK');
    expect(res.body).not.toContain('private-db');
  });

  it('fails closed when the Firebase project is not configured', async () => {
    const configuredProject = config.FIREBASE_PROJECT_ID;
    config.FIREBASE_PROJECT_ID = undefined;
    try {
      const res = await app.inject({ method: 'GET', url: '/api/patients', headers: auth() });
      expect(res.statusCode).toBe(503);
      expect(db.query).not.toHaveBeenCalled();
    } finally { config.FIREBASE_PROJECT_ID = configuredProject; }
  });
});
