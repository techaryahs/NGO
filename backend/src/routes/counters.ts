import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import { query } from '../db/index.js';
import { authenticate } from '../middleware/auth.js';
import { z } from 'zod';

const nameSchema = z.string().min(1).max(64).regex(/^[A-Za-z0-9_-]+$/);
const maxSafeValue = Number.MAX_SAFE_INTEGER;

interface RawCounterRow {
  counter_name: string;
  current_value: string | number;
  updated_at: Date | string;
}

export async function counterRoutes(fastify: FastifyInstance, _opts: FastifyPluginOptions): Promise<void> {
  fastify.addHook('preHandler', authenticate);

  // ── GET /api/counters/:name ─────────────────────────────────────────────────
  fastify.get('/counters/:name', async (request, reply) => {
    const { name } = request.params as { name: string };
    if (!nameSchema.safeParse(name).success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid counter name' });
    const res = await query<RawCounterRow>(
      'SELECT * FROM system_counters WHERE counter_name = $1',
      [name]
    );

    if (res.rows.length === 0) {
      return reply.send({ counterName: name, currentValue: 0 });
    }

    const val = parseInt(String(res.rows[0].current_value), 10);
    if (!Number.isSafeInteger(val)) return reply.status(409).send({ error: 'Conflict', message: 'Counter exceeds the supported range' });
    return reply.send({ counterName: name, currentValue: isNaN(val) ? 0 : val });
  });

  // ── POST /api/counters/:name/next ───────────────────────────────────────────
  fastify.post('/counters/:name/next', async (request, reply) => {
    const { name } = request.params as { name: string };
    if (!nameSchema.safeParse(name).success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid counter name' });

    const res = await query<RawCounterRow>(
      `WITH seed AS (
         SELECT CASE WHEN $1 = 'registrationNumber' THEN
           GREATEST(0, (SELECT COALESCE(MAX(registration_number::numeric), 0)
             FROM patients WHERE registration_number ~ '^[0-9]+$'))
           ELSE 0 END AS value
       )
       INSERT INTO system_counters (counter_name, current_value, updated_at)
       SELECT $1, value + 1, CURRENT_TIMESTAMP FROM seed WHERE value < $2
       ON CONFLICT (counter_name) DO UPDATE
       SET current_value = GREATEST(system_counters.current_value, EXCLUDED.current_value - 1) + 1,
           updated_at = CURRENT_TIMESTAMP
       WHERE GREATEST(system_counters.current_value, EXCLUDED.current_value - 1) < $2
       RETURNING *`,
      [name, maxSafeValue]
    );

    if (res.rows.length === 0) return reply.status(409).send({ error: 'Conflict', message: 'Counter exceeds the supported range' });

    const nextVal = parseInt(String(res.rows[0].current_value), 10);
    return reply.status(200).send({
      counterName: name,
      nextValue: nextVal,
      allocatedValue: nextVal,
      formatted: String(nextVal),
    });
  });

  // ── PUT /api/counters/:name ─────────────────────────────────────────────────
  fastify.put('/counters/:name', async (request, reply) => {
    const { name } = request.params as { name: string };
    const parsed = z.object({ value: z.number().int().min(0).max(maxSafeValue) }).safeParse(request.body);
    if (!nameSchema.safeParse(name).success || !parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'A nonnegative safe integer counter value is required' });
    const targetVal = parsed.data.value;

    const res = await query<RawCounterRow>(
      `INSERT INTO system_counters (counter_name, current_value, updated_at)
       VALUES ($1, $2, CURRENT_TIMESTAMP)
       ON CONFLICT (counter_name) DO UPDATE
       SET current_value = $2,
           updated_at = CURRENT_TIMESTAMP
       RETURNING *`,
      [name, targetVal]
    );

    const val = parseInt(String(res.rows[0].current_value), 10);
    return reply.send({ counterName: name, currentValue: val });
  });
}
