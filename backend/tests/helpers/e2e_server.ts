import { generateKeyPairSync } from 'node:crypto';
import jwt from 'jsonwebtoken';
import { buildApp } from '../../src/app.js';
import { config } from '../../src/config/index.js';
import { pool, query } from '../../src/db/index.js';
import { runMigrations } from '../../src/db/migrate.js';

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const TEST_FIREBASE_PROJECT = 'ngo-audit-test';
const TEST_FIREBASE_KID = 'audit-key';
const TEST_FIREBASE_PUBLIC_KEY = publicKey.export({ type: 'spki', format: 'pem' }).toString();

config.FIREBASE_PROJECT_ID = TEST_FIREBASE_PROJECT;
const originalFetch = globalThis.fetch;
globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
  const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
  if (url.includes('securetoken@system.gserviceaccount.com')) {
    return new Response(
      JSON.stringify({ [TEST_FIREBASE_KID]: TEST_FIREBASE_PUBLIC_KEY }),
      { status: 200, headers: { 'cache-control': 'public, max-age=3600', 'content-type': 'application/json' } },
    );
  }
  return originalFetch(input, init);
};

function createToken(uid: string, extraClaims: Record<string, unknown> = {}) {
  const now = Math.floor(Date.now() / 1000);
  const payload: Record<string, unknown> = {
    sub: uid,
    user_id: uid,
    aud: TEST_FIREBASE_PROJECT,
    iss: `https://securetoken.google.com/${TEST_FIREBASE_PROJECT}`,
    iat: now - 10,
    auth_time: now - 10,
    exp: now + 3600,
    email: `${uid}@ngo.test`,
    email_verified: true,
    ...extraClaims,
  };
  return jwt.sign(payload, privateKey, { algorithm: 'RS256', keyid: TEST_FIREBASE_KID });
}

async function seedUsers() {
  await query(
    `INSERT INTO users(id, email, name, role) VALUES
      ('test-uid-admin', 'admin@ngo.test', 'Test Admin', 'admin'),
      ('test-uid-staff', 'staff@ngo.test', 'Test Staff', 'staff'),
      ('test-uid-volunteer', 'volunteer@ngo.test', 'Test Volunteer', 'volunteer')
     ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role`,
  );
}

async function resetDatabase() {
  await query(
    `TRUNCATE users, rooms, room_beds, patients, stays, patient_attendants,
              payments, attendance_records, patient_photos, sponsorships,
              system_counters, system_settings, purchases, expense_entries,
              salaries, inventory_items, vendors
     CASCADE`,
  );
  await seedUsers();
}

async function main() {
  if (
    process.env.POSTGRES_HOST !== '127.0.0.1' ||
    process.env.POSTGRES_PORT !== '55439' ||
    process.env.POSTGRES_DB !== 'ngo_flutter_e2e'
  ) {
    throw new Error('Refusing to start E2E test server on non-disposable database');
  }

  await runMigrations('up');
  await resetDatabase();

  const app = buildApp({ logger: false });
  let simulateDbOutage = false;

  app.addHook('onRequest', async (request, reply) => {
    if (simulateDbOutage && request.url.startsWith('/api/')) {
      return reply.status(503).send({
        statusCode: 503,
        error: 'Service Unavailable',
        message: 'Simulated database outage for E2E failure testing',
      });
    }
  });

  app.get('/__test__/token', async (request) => {
    const q = request.query as Record<string, string | undefined>;
    const role = q.role ?? 'admin';
    if (role === 'expired') {
      const past = Math.floor(Date.now() / 1000) - 7200;
      const token = createToken('test-uid-admin', { iat: past, auth_time: past, exp: past + 1800 });
      return { token };
    }
    if (role === 'unregistered') {
      return { token: createToken('test-uid-unregistered') };
    }
    const uid =
      role === 'staff'
        ? 'test-uid-staff'
        : role === 'volunteer'
          ? 'test-uid-volunteer'
          : 'test-uid-admin';
    return { token: createToken(uid) };
  });

  app.post('/__test__/reset', async () => {
    simulateDbOutage = false;
    await resetDatabase();
    return { ok: true };
  });

  app.post('/__test__/db-outage', async (request) => {
    const body = (request.body ?? {}) as { outage?: boolean };
    simulateDbOutage = Boolean(body.outage);
    return { outage: simulateDbOutage };
  });

  app.post('/__test__/sql', async (request) => {
    const body = request.body as { sql: string; params?: unknown[] };
    const result = await query(body.sql, body.params ?? []);
    return { rows: result.rows, rowCount: result.rowCount };
  });

  const requestedPort = Number(process.env.E2E_PORT ?? 0);
  const address = await app.listen({ host: '127.0.0.1', port: requestedPort });
  console.log(`E2E_SERVER_READY:${address}`);

  const shutdown = async () => {
    try {
      await app.close();
      await pool.end();
    } finally {
      process.exit(0);
    }
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  console.error('E2E_SERVER_ERROR:', err);
  process.exit(1);
});
