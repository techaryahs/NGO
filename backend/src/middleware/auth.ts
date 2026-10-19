import { FastifyReply, FastifyRequest } from 'fastify';
import jwt from 'jsonwebtoken';
import { query } from '../db/index.js';
import { config } from '../config/index.js';

export interface AuthenticatedUser {
  id: string;
  email: string;
  name: string;
  role: 'admin' | 'staff' | 'volunteer';
}

declare module 'fastify' {
  interface FastifyRequest { user?: AuthenticatedUser; }
}

const GOOGLE_CERTIFICATES_URL = 'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';
class VerificationUnavailable extends Error {}

/** A fixed trusted key source; JWT jku/x5u headers can never select the source. */
export function createFirebaseTokenVerifier(options: {
  projectId: () => string | undefined;
  fetchKeys?: typeof fetch;
  now?: () => number;
}) {
  let certificates: Record<string, string> = {};
  let expiresAt = 0;
  let pending: Promise<void> | undefined;
  let lastUnknownKidRefresh = 0;
  const now = options.now ?? Date.now;

  const refresh = async () => {
    if (!pending) pending = (async () => {
      try {
        const response = await (options.fetchKeys ?? globalThis.fetch)(GOOGLE_CERTIFICATES_URL, { signal: AbortSignal.timeout(5000) });
        if (!response.ok) throw new Error('Key source unavailable');
        const body: unknown = await response.json();
        if (!body || typeof body !== 'object' || Array.isArray(body) || !Object.keys(body).length
          || !Object.values(body).every(value => typeof value === 'string' && value.includes('-----BEGIN '))) {
          throw new Error('Invalid key source response');
        }
        certificates = body as Record<string, string>;
        const maxAge = Number(response.headers.get('cache-control')?.match(/(?:^|[,\s])max-age=(\d+)/i)?.[1] ?? 300);
        expiresAt = now() + Math.min(maxAge, 86400) * 1000;
      } catch { throw new VerificationUnavailable('Firebase token verification is temporarily unavailable'); }
    })().finally(() => { pending = undefined; });
    await pending;
  };

  return async (token: string): Promise<{ uid: string; email?: string; name?: string }> => {
    const projectId = options.projectId();
    if (!projectId) throw new VerificationUnavailable('Firebase project is not configured');
    const decoded = jwt.decode(token, { complete: true });
    if (!decoded || decoded.header.alg !== 'RS256' || typeof decoded.header.kid !== 'string'
      || !decoded.header.kid.length || decoded.header.kid.length > 256) throw new Error('Invalid Firebase token');
    const kid = decoded.header.kid;
    const hadFreshKeys = now() < expiresAt;
    if (!hadFreshKeys) await refresh();
    // A new kid can appear before cache expiry during normal Google rotation.
    // Bound refreshes for unknown kids to avoid untrusted tokens flooding Google.
    if (!Object.hasOwn(certificates, kid) && hadFreshKeys && now() - lastUnknownKidRefresh >= 30000) {
      lastUnknownKidRefresh = now();
      await refresh();
    }
    if (!Object.hasOwn(certificates, kid)) throw new Error('Unknown Firebase signing key');

    const payload = jwt.verify(token, certificates[kid], {
      algorithms: ['RS256'], audience: projectId,
      issuer: `https://securetoken.google.com/${projectId}`,
      clockTimestamp: Math.floor(now() / 1000),
    });
    const seconds = Math.floor(now() / 1000);
    if (typeof payload === 'string' || payload.aud !== projectId || typeof payload.sub !== 'string' || !payload.sub.length || payload.sub.length > 128
      || typeof payload.exp !== 'number' || !Number.isFinite(payload.exp)
      || typeof payload.iat !== 'number' || !Number.isFinite(payload.iat) || payload.iat > seconds
      || typeof payload.auth_time !== 'number' || !Number.isFinite(payload.auth_time) || payload.auth_time > seconds
      || (payload.user_id !== undefined && payload.user_id !== payload.sub)) throw new Error('Invalid Firebase claims');
    return { uid: payload.sub, email: typeof payload.email === 'string' ? payload.email : undefined,
      name: typeof payload.name === 'string' ? payload.name : undefined };
  };
}

const verifyFirebaseToken = createFirebaseTokenVerifier({ projectId: () => config.FIREBASE_PROJECT_ID });

function allowedRoles(request: FastifyRequest): AuthenticatedUser['role'][] {
  // Preserve the access policy in database.rules.json during backend migration.
  const path = request.routeOptions.url ?? request.url.split('?')[0];
  const isRead = request.method === 'GET' || request.method === 'HEAD';
  if (path.startsWith('/api/erp/')) {
    if (path.startsWith('/api/erp/salaries') && !isRead) return ['admin'];
    return isRead ? ['admin', 'staff', 'volunteer'] : ['admin', 'staff'];
  }
  if (path.startsWith('/api/settings/') && !isRead) return ['admin'];
  return ['admin', 'staff'];
}

export async function authenticate(request: FastifyRequest, reply: FastifyReply): Promise<void> {
  const match = request.headers.authorization?.match(/^Bearer\s+(\S+)$/i);
  if (!match) return reply.status(401).send({ statusCode: 401, error: 'Unauthorized', message: 'Missing or invalid Authorization header. Expected Bearer token.' });
  let identity: { uid: string; email?: string; name?: string };
  try { identity = await verifyFirebaseToken(match[1]); }
  catch (error) {
    const unavailable = error instanceof VerificationUnavailable;
    return reply.status(unavailable ? 503 : 401).send({ statusCode: unavailable ? 503 : 401,
      error: unavailable ? 'ServiceUnavailable' : 'Unauthorized',
      message: unavailable ? 'Authentication service unavailable' : 'Invalid or expired Firebase ID token' });
  }
  try {
    // Only the verified Firebase UID can select an account. Email cannot link accounts.
    const userRes = await query<AuthenticatedUser>('SELECT id, email, name, role FROM users WHERE id = $1', [identity.uid]);
    let user = userRes.rows[0];
    if (!user) {
      const provisioned = await query<AuthenticatedUser>(
        `INSERT INTO users (id, email, name, role) VALUES ($1, $2, $3, 'volunteer')
         ON CONFLICT (id) DO UPDATE SET updated_at = CURRENT_TIMESTAMP RETURNING id, email, name, role`,
        [identity.uid, identity.email ?? `${identity.uid}@unknown.firebase`, identity.name ?? 'NGO Staff / Volunteer'],
      );
      user = provisioned.rows[0];
    }
    if (!user || !['admin', 'staff', 'volunteer'].includes(user.role)) throw new Error('Invalid authoritative account');
    request.user = user;
  } catch {
    return reply.status(503).send({ statusCode: 503, error: 'ServiceUnavailable', message: 'Authentication service unavailable' });
  }
  if (!allowedRoles(request).includes(request.user.role)) {
    return reply.status(403).send({ statusCode: 403, error: 'Forbidden', message: 'Insufficient permissions' });
  }
}

export function requireRoles(roles: AuthenticatedUser['role'][]) {
  return async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    if (!request.user) return reply.status(401).send({ statusCode: 401, error: 'Unauthorized', message: 'Authentication required' });
    if (!roles.includes(request.user.role)) return reply.status(403).send({ statusCode: 403, error: 'Forbidden', message: 'Insufficient permissions' });
  };
}
