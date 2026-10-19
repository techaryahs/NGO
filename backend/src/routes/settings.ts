import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import { getClient, query } from '../db/index.js';
import { authenticate, requireRoles } from '../middleware/auth.js';
import { z } from 'zod';

const settingName = z.string().min(1).max(64).regex(/^[A-Za-z0-9_-]+$/);

interface RawSettingRow {
  category: string;
  settings_key: string;
  settings_value: any;
  updated_at: Date | string;
}

export async function settingsRoutes(fastify: FastifyInstance, _opts: FastifyPluginOptions): Promise<void> {
  fastify.addHook('preHandler', authenticate);
  fastify.addHook('preHandler', requireRoles(['admin', 'staff']));

  // ── GET /api/settings/:category ─────────────────────────────────────────────
  fastify.get('/settings/:category', async (request, reply) => {
    const { category } = request.params as { category: string };
    if (!settingName.safeParse(category).success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid settings category' });
    const res = await query<RawSettingRow>(
      'SELECT * FROM system_settings WHERE category = $1',
      [category]
    );

    const result: Record<string, any> = {};
    for (const r of res.rows) {
      result[r.settings_key] = r.settings_value;
    }

    return reply.send(result);
  });

  // ── GET /api/settings/:category/:key ────────────────────────────────────────
  fastify.get('/settings/:category/:key', async (request, reply) => {
    const { category, key } = request.params as { category: string; key: string };
    if (!settingName.safeParse(category).success || !settingName.safeParse(key).success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid settings path' });
    const res = await query<RawSettingRow>(
      'SELECT * FROM system_settings WHERE category = $1 AND settings_key = $2',
      [category, key]
    );

    if (res.rows.length === 0) {
      return reply.send({});
    }

    return reply.send(res.rows[0].settings_value);
  });

  // ── PUT /api/settings/:category/:key ────────────────────────────────────────
  fastify.put('/settings/:category/:key', { preHandler: requireRoles(['admin']) }, async (request, reply) => {
    const { category, key } = request.params as { category: string; key: string };
    if (!settingName.safeParse(category).success || !settingName.safeParse(key).success || request.body === undefined) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid settings path or value' });
    const value = request.body;

    const res = await query<RawSettingRow>(
      `INSERT INTO system_settings (category, settings_key, settings_value, updated_at)
       VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
       ON CONFLICT (category, settings_key) DO UPDATE
       SET settings_value = EXCLUDED.settings_value,
           updated_at = CURRENT_TIMESTAMP
       RETURNING *`,
      [category, key, JSON.stringify(value)]
    );

    return reply.send(res.rows[0].settings_value);
  });

  // RTDB pricing/security callers patch a category's children. Persist every
  // supplied key together and preserve keys omitted by that partial write.
  fastify.put('/settings/:category', { preHandler: requireRoles(['admin']) }, async (request, reply) => {
    const { category } = request.params as { category: string };
    const parsed = z.record(settingName, z.unknown()).safeParse(request.body);
    if (!settingName.safeParse(category).success || !parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'A settings object with valid keys is required' });
    const client = await getClient();
    try {
      await client.query('BEGIN');
      for (const [key, value] of Object.entries(parsed.data)) {
        await client.query(`INSERT INTO system_settings(category, settings_key, settings_value, updated_at)
          VALUES($1,$2,$3,CURRENT_TIMESTAMP) ON CONFLICT(category,settings_key)
          DO UPDATE SET settings_value=EXCLUDED.settings_value, updated_at=CURRENT_TIMESTAMP`, [category, key, JSON.stringify(value)]);
      }
      const result = await client.query<RawSettingRow>('SELECT * FROM system_settings WHERE category=$1', [category]);
      await client.query('COMMIT');
      return reply.send(Object.fromEntries(result.rows.map((row) => [row.settings_key, row.settings_value])));
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  });
}
