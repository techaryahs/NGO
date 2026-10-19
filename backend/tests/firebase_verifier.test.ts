import { generateKeyPairSync } from 'node:crypto';
import jwt from 'jsonwebtoken';
import { describe, expect, it, vi } from 'vitest';
import { createFirebaseTokenVerifier } from '../src/middleware/auth.js';

const project = 'ngo-key-rotation-test';
const first = generateKeyPairSync('rsa', { modulusLength: 2048 });
const second = generateKeyPairSync('rsa', { modulusLength: 2048 });
const publicPem = (keys: typeof first) => keys.publicKey.export({ type: 'spki', format: 'pem' }).toString();
const keyResponse = (keys: Record<string, string>, seconds = 3600) => new Response(JSON.stringify(keys), {
  status: 200, headers: { 'cache-control': `public, max-age=${seconds}` },
});
const token = (kid = 'first', keys = first, extra: Record<string, unknown> = {}) => {
  const seconds = Math.floor(Date.now() / 1000);
  return jwt.sign({ sub: 'synthetic-uid', aud: project, iss: `https://securetoken.google.com/${project}`,
    exp: seconds + 7200, iat: seconds, auth_time: seconds, ...extra }, keys.privateKey,
    { algorithm: 'RS256', keyid: kid });
};

describe('Trusted Firebase public key cache and rotation', () => {
  it('caches Google keys for their max-age and coalesces concurrent fetches', async () => {
    const fetchKeys = vi.fn<typeof fetch>().mockImplementation(async () => keyResponse({ first: publicPem(first) }));
    const verify = createFirebaseTokenVerifier({ projectId: () => project, fetchKeys });
    const responses = await Promise.all([verify(token()), verify(token()), verify(token())]);
    expect(responses.map(response => response.uid)).toEqual(['synthetic-uid', 'synthetic-uid', 'synthetic-uid']);
    await verify(token());
    expect(fetchKeys).toHaveBeenCalledTimes(1);
    expect(fetchKeys).toHaveBeenCalledWith('https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com', expect.objectContaining({ signal: expect.any(AbortSignal) }));
  });

  it('refreshes on a new kid before expiry and verifies a rotated signing key', async () => {
    const fetchKeys = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(keyResponse({ first: publicPem(first) }))
      .mockResolvedValueOnce(keyResponse({ second: publicPem(second) }));
    const verify = createFirebaseTokenVerifier({ projectId: () => project, fetchKeys });
    await verify(token());
    expect((await verify(token('second', second))).uid).toBe('synthetic-uid');
    expect(fetchKeys).toHaveBeenCalledTimes(2);
  });

  it('refreshes expired cache entries using the response max-age', async () => {
    let now = Date.now();
    const fetchKeys = vi.fn<typeof fetch>().mockImplementation(async () => keyResponse({ first: publicPem(first) }, 30));
    const verify = createFirebaseTokenVerifier({ projectId: () => project, fetchKeys, now: () => now });
    await verify(token());
    now += 31000;
    await verify(token());
    expect(fetchKeys).toHaveBeenCalledTimes(2);
  });

  it('rejects unknown kids and bounds repeated refreshes', async () => {
    const fetchKeys = vi.fn<typeof fetch>().mockImplementation(async () => keyResponse({ first: publicPem(first) }));
    const verify = createFirebaseTokenVerifier({ projectId: () => project, fetchKeys });
    await verify(token());
    await expect(verify(token('unknown', second))).rejects.toThrow('Unknown Firebase signing key');
    await expect(verify(token('other-unknown', second))).rejects.toThrow('Unknown Firebase signing key');
    expect(fetchKeys).toHaveBeenCalledTimes(2);
  });

  it('does not follow JWT-controlled jku/x5u key URLs', async () => {
    const seconds = Math.floor(Date.now() / 1000);
    const attackToken = jwt.sign({ sub: 'synthetic-uid', aud: project, iss: `https://securetoken.google.com/${project}`,
      iat: seconds, auth_time: seconds, exp: seconds + 3600 }, second.privateKey, {
      algorithm: 'RS256', header: { alg: 'RS256', kid: 'first', jku: 'https://attacker.invalid/jwks', x5u: 'https://attacker.invalid/cert' },
    });
    const fetchKeys = vi.fn<typeof fetch>().mockResolvedValue(keyResponse({ first: publicPem(first) }));
    const verify = createFirebaseTokenVerifier({ projectId: () => project, fetchKeys });
    await expect(verify(attackToken)).rejects.toThrow('invalid signature');
    expect(fetchKeys.mock.calls[0][0]).toBe('https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com');
  });

  it('rejects algorithm confusion without fetching any certificates', async () => {
    const attackToken = jwt.sign({ sub: 'synthetic-uid' }, 'not-a-secret', { algorithm: 'HS256', keyid: 'first' });
    const fetchKeys = vi.fn<typeof fetch>();
    const verify = createFirebaseTokenVerifier({ projectId: () => project, fetchKeys });
    await expect(verify(attackToken)).rejects.toThrow('Invalid Firebase token');
    expect(fetchKeys).not.toHaveBeenCalled();
  });

  it('fails closed on key source errors and recovers on the next successful request', async () => {
    const fetchKeys = vi.fn<typeof fetch>()
      .mockRejectedValueOnce(new Error('Network unavailable'))
      .mockResolvedValueOnce(keyResponse({ first: publicPem(first) }));
    const verify = createFirebaseTokenVerifier({ projectId: () => project, fetchKeys });
    await expect(verify(token())).rejects.toThrow('temporarily unavailable');
    await expect(verify(token())).resolves.toMatchObject({ uid: 'synthetic-uid' });
  });

  it.each([
    () => new Response('upstream failure', { status: 503 }),
    () => new Response('{"first":123}', { status: 200 }),
    () => new Response('{}', { status: 200 }),
  ])('fails closed on an invalid trusted key response', async response => {
    const fetchKeys = vi.fn<typeof fetch>().mockResolvedValue(response());
    const verify = createFirebaseTokenVerifier({ projectId: () => project, fetchKeys });
    await expect(verify(token())).rejects.toThrow('temporarily unavailable');
  });
});
