import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import { z } from 'zod';
import { query } from '../db/index.js';
import { authenticate } from '../middleware/auth.js';

interface RawUserRow {
  id: string;
  email: string;
  name: string;
  phone: string | null;
  role: string;
  created_at: Date | string;
  updated_at: Date | string;
}

const updateUserSchema = z.object({
  name: z.string().trim().min(1).max(255).optional(),
  email: z.string().trim().email().max(255).optional(),
  phone: z.string().trim().max(32).nullable().optional(),
  role: z.enum(['admin', 'staff', 'volunteer']).optional(),
}).passthrough();

export async function userRoutes(fastify: FastifyInstance, _opts: FastifyPluginOptions): Promise<void> {
  fastify.addHook('preHandler', authenticate);

  // ── GET /api/users/:id ──────────────────────────────────────────────────────
  fastify.get('/users/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const currentUser = request.user!;

    // Volunteers can only view their own user profile
    if (currentUser.role === 'volunteer' && currentUser.id !== id) {
      return reply.status(403).send({ statusCode: 403, error: 'Forbidden', message: 'Insufficient permissions' });
    }

    const res = await query<RawUserRow>(
      'SELECT id, email, name, phone, role, created_at, updated_at FROM users WHERE id = $1',
      [id]
    );

    if (res.rows.length === 0) {
      return reply.status(404).send({ error: 'NotFound', message: `User '${id}' not found` });
    }

    const r = res.rows[0];
    return reply.send({
      id: r.id,
      uid: r.id,
      email: r.email,
      name: r.name,
      phone: r.phone,
      role: r.role,
      createdAt: new Date(r.created_at).getTime(),
    });
  });

  // ── GET /api/users ──────────────────────────────────────────────────────────
  fastify.get('/users', async (_request, reply) => {
    const res = await query<RawUserRow>(
      'SELECT id, email, name, phone, role, created_at, updated_at FROM users'
    );

    const result: Record<string, any> = {};
    for (const r of res.rows) {
      result[r.id] = {
        id: r.id,
        uid: r.id,
        email: r.email,
        name: r.name,
        phone: r.phone,
        role: r.role,
        createdAt: new Date(r.created_at).getTime(),
      };
    }
    return reply.send(result);
  });

  // ── PUT /api/users/:id ──────────────────────────────────────────────────────
  fastify.put('/users/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const parsed = updateUserSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        statusCode: 400,
        error: 'BadRequest',
        message: `Invalid user data: ${parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ')}`,
      });
    }

    const currentUser = request.user!;
    const body = parsed.data;

    // Authorization checks:
    // 1. Non-admin users cannot edit any account other than their own.
    if (currentUser.role !== 'admin' && currentUser.id !== id) {
      return reply.status(403).send({
        statusCode: 403,
        error: 'Forbidden',
        message: 'Cannot modify another user account',
      });
    }

    // 2. Non-admin users cannot change their own role or escalate privileges.
    if (currentUser.role !== 'admin' && body.role !== undefined && body.role !== currentUser.role) {
      return reply.status(403).send({
        statusCode: 403,
        error: 'Forbidden',
        message: 'Insufficient permissions to change role',
      });
    }

    const email = body.email || `${id}@example.com`;
    const name = body.name || 'User';
    const phone = body.phone ?? null;
    const canChangeRole = currentUser.role === 'admin' && Boolean(body.role);
    const assignedRole = canChangeRole && body.role ? body.role : (currentUser.role !== 'admin' ? currentUser.role : 'volunteer');

    const res = await query<RawUserRow>(
      `INSERT INTO users (id, email, name, phone, role, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       ON CONFLICT (id) DO UPDATE
       SET email = COALESCE(EXCLUDED.email, users.email),
           name = COALESCE(EXCLUDED.name, users.name),
           phone = EXCLUDED.phone,
           role = CASE WHEN $6 THEN EXCLUDED.role ELSE users.role END,
           updated_at = CURRENT_TIMESTAMP
       RETURNING *`,
      [id, email, name, phone, assignedRole, canChangeRole]
    );

    const r = res.rows[0];
    return reply.send({
      id: r.id,
      uid: r.id,
      email: r.email,
      name: r.name,
      phone: r.phone,
      role: r.role,
      createdAt: new Date(r.created_at).getTime(),
    });
  });
}
