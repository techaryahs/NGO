import { generateKeyPairSync } from 'node:crypto';
import jwt from 'jsonwebtoken';
import { vi } from 'vitest';
import { config } from '../../src/config/index.js';

// Generated only in memory. These keys and identities have no production use.
const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
export const TEST_FIREBASE_PROJECT = 'ngo-audit-test';
export const TEST_FIREBASE_KID = 'audit-key';
export const TEST_FIREBASE_PUBLIC_KEY = publicKey.export({ type: 'spki', format: 'pem' }).toString();

export function installTestFirebaseKeys() {
  config.FIREBASE_PROJECT_ID = TEST_FIREBASE_PROJECT;
  return vi.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response(
    JSON.stringify({ [TEST_FIREBASE_KID]: TEST_FIREBASE_PUBLIC_KEY }),
    { status: 200, headers: { 'cache-control': 'public, max-age=3600' } },
  ));
}

export function signedTestToken(uid = 'test-uid-admin', claims: Record<string, unknown> = {}) {
  const now = Math.floor(Date.now() / 1000);
  const payload: Record<string, unknown> = {
    sub: uid, user_id: uid, aud: TEST_FIREBASE_PROJECT,
    iss: `https://securetoken.google.com/${TEST_FIREBASE_PROJECT}`,
    iat: now, auth_time: now, exp: now + 3600,
    email: `${uid}@ngo.test`, email_verified: true, ...claims,
  };
  for (const key of Object.keys(payload)) if (payload[key] === undefined) delete payload[key];
  return jwt.sign(payload, privateKey, { algorithm: 'RS256', keyid: TEST_FIREBASE_KID });
}
