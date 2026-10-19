import { FastifyInstance, FastifyPluginOptions } from 'fastify';
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

export async function userRoutes(fastify: FastifyInstance, _opts: FastifyPluginOptions): Promise<void> {
  fastify.addHook('preHandler', authenticate);

  // ── GET /api/users/:id ──────────────────────────────────────────────────────
  fastify.get('/users/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
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
    const body = (request.body || {}) as any;
    const email = body.email || `${id}@example.com`;
    const name = body.name || 'User';
    const phone = body.phone || null;
    const role = body.role || 'volunteer';

    const res = await query<RawUserRow>(
      `INSERT INTO users (id, email, name, phone, role, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       ON CONFLICT (id) DO UPDATE
       SET email = EXCLUDED.email,
           name = EXCLUDED.name,
           phone = EXCLUDED.phone,
           role = EXCLUDED.role,
           updated_at = CURRENT_TIMESTAMP
       RETURNING *`,
      [id, email, name, phone, role]
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
