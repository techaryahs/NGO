import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import { getClient, query } from '../db/index.js';
import { authenticate } from '../middleware/auth.js';
import { z } from 'zod';
import { httpError } from '../validation.js';
import { eligibleAttendant } from '../services/attendant_roster.js';
import { dayKey } from '../services/billing.js';

async function validateAssociation(client: any, patientId: string, date: string, payload: Record<string, any>) {
  const stays = (await client.query("SELECT patient_snapshot,cycle_id,admission_date FROM stays WHERE patient_id=$1 AND status<>'cancelled' ORDER BY admission_date DESC,id", [patientId])).rows;
  const cycleStart = (stay: any) => dayKey(/^\d+$/.test(stay.cycle_id ?? '') ? Number(stay.cycle_id) : stay.patient_snapshot?.admissionDate ?? stay.admission_date);
  const cycles = [...new Set<string>(stays.map(cycleStart))].sort();
  const cycle = cycles.filter(start => start <= date).at(-1) ?? cycles[0];
  const people = [...new Map([...stays].reverse().filter((stay: any) => cycleStart(stay) === cycle)
    .flatMap((stay: any) => stay.patient_snapshot?.attendants ?? []).map((person: any) => [person.id ?? person.name, person])).values()] as any[];
  const marks = payload.attendantId || payload.attendantName
    ? [[payload.attendantId ?? payload.attendantName, payload]] : Object.entries(payload);
  for (const [key, value] of marks) {
    if (!value || typeof value !== 'object') continue;
    const identity = value.attendantId ?? key;
    const names = people.filter((p: any) => p.name === identity || p.name?.replace(/[.#$\[\]/]/g, '_') === identity);
    const person = people.find((p: any) => p.id === identity) ?? (names.length === 1 ? names[0] : undefined);
    if (person && !eligibleAttendant(person, date)) throw httpError(400, 'Attendance date is outside the attendant association period');
  }
}

const dateSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine((value) => {
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}, 'A valid calendar date is required');
const patientIdSchema = z.string().min(1).max(64).regex(/^[A-Za-z0-9_-]+$/);
const kindSchema = z.enum(['attendance', 'attendant_attendance']);
const attendanceSchema = z.object({
  date: dateSchema,
  kind: kindSchema.default('attendance'),
  patientId: patientIdSchema,
  payload: z.record(z.unknown()).default({}),
});

interface RawAttendanceRow {
  id: string;
  kind: string;
  attendance_date: Date | string;
  patient_id: string;
  payload: any;
  created_at: Date | string;
  updated_at: Date | string;
}

export async function attendanceRoutes(fastify: FastifyInstance, _opts: FastifyPluginOptions): Promise<void> {
  fastify.addHook('preHandler', authenticate);

  // ── GET /api/attendance ─────────────────────────────────────────────────────
  fastify.get('/attendance', async (request, reply) => {
    const parsed = z.object({
      date: dateSchema.optional(),
      startDate: dateSchema.optional(),
      endDate: dateSchema.optional(),
      kind: kindSchema.optional(),
      patientId: patientIdSchema.optional(),
      format: z.enum(['map', 'array']).optional(),
    }).safeParse(request.query);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid attendance filters' });
    const q = parsed.data;

    const conditions: string[] = [];
    const params: unknown[] = [];
    let idx = 1;

    if (q.date) {
      conditions.push(`attendance_date = $${idx++}`);
      params.push(q.date);
    }
    if (q.startDate) {
      conditions.push(`attendance_date >= $${idx++}`);
      params.push(q.startDate);
    }
    if (q.endDate) {
      conditions.push(`attendance_date <= $${idx++}`);
      params.push(q.endDate);
    }
    const kind = q.kind ?? (q.format === 'map' ? 'attendance' : undefined);
    if (kind) {
      conditions.push(`kind = $${idx++}`);
      params.push(kind);
    }
    if (q.patientId) {
      conditions.push(`patient_id = $${idx++}`);
      params.push(q.patientId);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
    const res = await query<RawAttendanceRow>(
      `SELECT id, kind, attendance_date::text AS attendance_date, patient_id, payload, created_at, updated_at
       FROM attendance_records ${whereClause} ORDER BY attendance_records.attendance_date DESC`,
      params
    );

    if (q.format === 'map') {
      const mapRes: Record<string, any> = {};
      for (const r of res.rows) {
        if (q.date) {
          mapRes[r.patient_id] = r.payload;
        } else {
          const day = typeof r.attendance_date === 'string' ? r.attendance_date : r.attendance_date.toISOString().slice(0, 10);
          mapRes[day] ??= {};
          mapRes[day][r.patient_id] = r.payload;
        }
      }
      return reply.send(mapRes);
    }

    return reply.send(
      res.rows.map((r) => ({
        id: r.id,
        kind: r.kind,
        date: typeof r.attendance_date === 'string' ? r.attendance_date : r.attendance_date.toISOString().split('T')[0],
        patientId: r.patient_id,
        payload: r.payload,
      }))
    );
  });

  // ── POST /api/attendance ────────────────────────────────────────────────────
  fastify.post('/attendance', async (request, reply) => {
    const parsed = attendanceSchema.safeParse(request.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid attendance record' });
    const body = parsed.data;
    const kind = body.kind;
    const recordId = `${kind}/${body.date}/${body.patientId}`;
    const client = await getClient();
    try {
    await client.query('BEGIN');
    const patient = await client.query('SELECT id FROM patients WHERE id=$1 FOR UPDATE', [body.patientId]);
    if (!patient.rowCount) throw httpError(409, 'Patient not found');
    if (kind === 'attendant_attendance') await validateAssociation(client, body.patientId, body.date, body.payload);
    const res = await client.query<RawAttendanceRow>(
      `INSERT INTO attendance_records (id, kind, attendance_date, patient_id, payload, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       ON CONFLICT (id) DO UPDATE SET
         payload = CASE WHEN attendance_records.kind = 'attendant_attendance' THEN attendance_records.payload || EXCLUDED.payload ELSE EXCLUDED.payload END,
         updated_at = CURRENT_TIMESTAMP
       RETURNING *`,
      [recordId, kind, body.date, body.patientId, JSON.stringify(body.payload || {})]
    );

    // Invalidate billing calculated from attendance read before this write.
    await client.query('UPDATE patients SET version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=$1', [body.patientId]);
    await client.query('COMMIT');
    return reply.status(200).send({
      id: res.rows[0].id,
      kind: res.rows[0].kind,
      date: body.date,
      patientId: res.rows[0].patient_id,
      payload: res.rows[0].payload,
    });
    } catch (err) { await client.query('ROLLBACK'); throw err; }
    finally { client.release(); }
  });

  // ── POST /api/attendance/bulk ───────────────────────────────────────────────
  fastify.post('/attendance/bulk', async (request, reply) => {
    const parsed = z.object({ date: dateSchema, kind: kindSchema.default('attendance'),
      records: z.record(patientIdSchema, z.record(z.unknown())) }).safeParse(request.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid bulk attendance records' });
    const body = parsed.data;
    const kind = body.kind;
    const client = await getClient();

    try {
      await client.query('BEGIN');
      const patientIds = Object.keys(body.records || {}).sort();
      const patients = await client.query('SELECT id FROM patients WHERE id=ANY($1::varchar[]) ORDER BY id FOR UPDATE', [patientIds]);
      if (patients.rowCount !== patientIds.length) throw httpError(409, 'Patient not found');

      for (const patientId of patientIds) {
        const payload = body.records[patientId];
        if (kind === 'attendant_attendance') await validateAssociation(client, patientId, body.date, payload);
        const recordId = `${kind}/${body.date}/${patientId}`;
        await client.query(
          `INSERT INTO attendance_records (id, kind, attendance_date, patient_id, payload, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
           ON CONFLICT (id) DO UPDATE SET
             payload = CASE WHEN attendance_records.kind = 'attendant_attendance' THEN attendance_records.payload || EXCLUDED.payload ELSE EXCLUDED.payload END,
             updated_at = CURRENT_TIMESTAMP`,
          [recordId, kind, body.date, patientId, JSON.stringify(payload)]
        );
      }

      await client.query('UPDATE patients SET version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=ANY($1::varchar[])', [patientIds]);
      await client.query('COMMIT');
      return reply.send({ success: true, count: patientIds.length, date: body.date, kind });
    } catch (err: unknown) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  });
}
