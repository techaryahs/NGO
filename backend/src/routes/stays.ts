import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import { getClient, query } from '../db/index.js';
import { authenticate } from '../middleware/auth.js';
import { randomUUID } from 'node:crypto';
import { httpError } from '../validation.js';
import { refreshRoomOccupancy } from '../db/occupancy.js';
import { z } from 'zod';
import { approvedPricing, newStayIdentity, persistBilling, projectBilling, quoteStayExtension, stayCycle } from '../services/billing.js';
import { finalizeDischarge } from '../services/discharge.js';

export interface RawStayRow {
  id: string;
  patient_id: string;
  patient_name: string;
  patient_snapshot: any;
  room_id: string;
  room_number: string;
  room_type: string;
  cycle_id: string | null;
  admission_date: Date | string;
  duration_days: number;
  expected_discharge_date: Date | string;
  completed_at: Date | string | null;
  expiry_date: Date | string;
  total_extended_days: number;
  attendant_count: number;
  attendant_labels: any;
  daily_rate: string | number | null;
  daily_rate_is_manual: boolean;
  long_stay_daily_rate: string | number | null;
  cost_override: string | number | null;
  billing_summary: any;
  total_cost: string | number;
  base_cost: string | number;
  extra_attendant_cost: string | number;
  paid_amount: string | number | null;
  pending_amount: string | number | null;
  extensions: any;
  status: string;
  bed_number: number | null;
  bed_id: string | null;
  bed_label: string | null;
  notes: string | null;
  created_by: string;
  created_at: Date | string;
  updated_at: Date | string;
}

function toEpochMs(d: Date | string | number | null | undefined): number | null {
  if (d == null) return null;
  if (typeof d === 'number') return d;
  const parsed = new Date(d).getTime();
  return isNaN(parsed) ? null : parsed;
}

export function formatStay(row: RawStayRow) {
  return {
    id: row.id,
    patientId: row.patient_id,
    patientName: row.patient_name,
    patientSnapshot: row.patient_snapshot || {},
    roomId: row.room_id,
    roomNumber: row.room_number,
    roomType: row.room_type,
    cycleId: row.cycle_id,
    admissionDate: toEpochMs(row.admission_date) ?? 0,
    durationDays: row.duration_days,
    expectedDischargeDate: toEpochMs(row.expected_discharge_date) ?? 0,
    completedAt: toEpochMs(row.completed_at),
    expiryDate: toEpochMs(row.expiry_date) ?? 0,
    totalExtendedDays: row.total_extended_days || 0,
    attendantCount: row.attendant_count || 0,
    attendantLabels: Array.isArray(row.attendant_labels) ? row.attendant_labels : [],
    dailyRate: row.daily_rate != null ? parseFloat(String(row.daily_rate)) : null,
    dailyRateIsManual: Boolean(row.daily_rate_is_manual),
    longStayDailyRate: row.long_stay_daily_rate != null ? parseFloat(String(row.long_stay_daily_rate)) : null,
    costOverride: row.cost_override != null ? parseFloat(String(row.cost_override)) : null,
    billingSummary: row.billing_summary || {},
    totalCost: parseFloat(String(row.total_cost || 0)),
    baseCost: parseFloat(String(row.base_cost || 0)),
    extraAttendantCost: parseFloat(String(row.extra_attendant_cost || 0)),
    paidAmount: row.paid_amount != null ? parseFloat(String(row.paid_amount)) : null,
    pendingAmount: row.pending_amount != null ? parseFloat(String(row.pending_amount)) : null,
    extensions: Array.isArray(row.extensions) ? row.extensions : [],
    status: row.status,
    bedNumber: row.bed_number,
    bedId: row.bed_id,
    bedLabel: row.bed_label,
    notes: row.notes,
    createdBy: row.created_by,
    createdAt: toEpochMs(row.created_at) ?? Date.now(),
    updatedAt: toEpochMs(row.updated_at) ?? Date.now(),
  };
}

export async function insertStayWithClient(client: Awaited<ReturnType<typeof getClient>>, rawBody: Record<string, any>, userId: string): Promise<RawStayRow> {
  const body = { ...rawBody };
  const stayId = body.id || `s_${randomUUID()}`;
  const admissionDate = body.admissionDate != null ? new Date(body.admissionDate) : new Date();
  const durationDays = body.durationDays != null ? parseInt(body.durationDays, 10) : 1;
  const expectedDischargeDate = body.expectedDischargeDate != null
    ? new Date(body.expectedDischargeDate)
    : new Date(admissionDate.getTime() + durationDays * 86400000);
  const expiryDate = body.expiryDate != null ? new Date(body.expiryDate) : expectedDischargeDate;

  // Lifecycle mutations use patient -> room -> stay -> bed lock order.
  const patient = (await client.query('SELECT * FROM patients WHERE id=$1 FOR UPDATE', [body.patientId])).rows[0];
  if (!patient) throw httpError(409, 'Patient does not exist');

  const isLobbyPlacement = body.roomType === 'lobby' || String(body.roomId || '').startsWith('lobby:');
  if (isLobbyPlacement) {
    const lobbyName = body.roomNumber || String(body.roomId).replace(/^lobby:/, '') || 'Lobby';
    await client.query(
      `INSERT INTO rooms (id, room_number, room_identifier, floor, room_type, status, max_attendants, current_attendants, total_beds, occupied_beds, version)
       VALUES ($1, $2, $2, 0, 'lobby', 'available', 5, 0, 0, 0, 1)
       ON CONFLICT (id) DO NOTHING`,
      [body.roomId, lobbyName]
    );
  }

  const room = (await client.query('SELECT * FROM rooms WHERE id=$1 FOR UPDATE', [body.roomId])).rows[0];
  if (!room) throw httpError(409, 'Room does not exist');
  if (body.id) {
    const existingStay = (await client.query<RawStayRow>('SELECT * FROM stays WHERE id=$1 FOR UPDATE', [body.id])).rows[0];
    if (existingStay) {
      if (
        existingStay.patient_id === body.patientId &&
        existingStay.room_id === body.roomId &&
        (existingStay.bed_id || null) === (body.bedId || null) &&
        (body.cycleId == null || String(existingStay.cycle_id) === String(body.cycleId)) &&
        (body.admissionDate == null || new Date(existingStay.admission_date).getTime() === admissionDate.getTime())
      ) {
        return existingStay;
      }
      throw httpError(409, 'Stay ID already exists with a different assignment');
    }
  }

  const active = !body.status || body.status === 'active';
  if (active && patient.status === 'discharged') throw httpError(409, 'Create a new admission through the rejoin workflow');
  if (active && (await client.query("SELECT id FROM stays WHERE patient_id=$1 AND status='active' AND room_id<>$2", [body.patientId, body.roomId])).rowCount) throw httpError(409, 'Complete the current room placement before moving rooms');
  if (active && ['maintenance','cleaning','unavailable'].includes(room.status)) throw httpError(409, 'Room is unavailable');
  if (active && (room.room_type === 'private' || room.room_type === 'lobby') && (await client.query("SELECT id FROM stays WHERE room_id=$1 AND status='active' AND patient_id<>$2", [body.roomId, body.patientId])).rowCount) {
    throw httpError(409, room.room_type === 'lobby' ? 'Lobby slot is occupied' : 'Private room is occupied');
  }
  if (active && !body.bedId && (await client.query('SELECT id FROM room_beds WHERE room_id=$1', [body.roomId])).rowCount) throw httpError(400, 'bedId is required for rooms with beds');
  if (body.bedId) {
    const bed = (await client.query('SELECT * FROM room_beds WHERE id=$1 AND room_id=$2 FOR UPDATE', [body.bedId, body.roomId])).rows[0];
    if (!bed || (active && (bed.current_stay_id || bed.status !== 'available'))) throw httpError(409, 'Bed is unavailable or does not belong to this room');
    body.bedLabel = bed.bed_label;
  }
  body.patientName = patient.full_name;
  body.roomNumber = room.room_number;
  body.roomType = room.room_type;
  const attendants = (await client.query('SELECT id,name,relation FROM patient_attendants WHERE patient_id=$1 ORDER BY id', [body.patientId])).rows;
  // Carry association dates across room transfers within this admission.
  const priorStays = active ? (await client.query('SELECT patient_snapshot FROM stays WHERE patient_id=$1 AND cycle_id=$2 ORDER BY admission_date DESC,id',
    [body.patientId, String(new Date(patient.admission_date).getTime())])).rows : [];
  const priorRoster = priorStays.flatMap(s => s.patient_snapshot?.attendants ?? []);
  const roster = attendants.map(person => ({ ...priorRoster.find(p => p.id === person.id), ...person }));
  const identity = newStayIdentity(patient, body);
  body.patientSnapshot = { ...body.patientSnapshot, admissionDate: identity.snapshotAdmission,
    attendants: active ? roster : body.patientSnapshot?.attendants ?? attendants };
  body.cycleId = identity.cycleId;
  if (active) body.billingSummary = { ...body.billingSummary, pricing: approvedPricing({}) };
  const res = await client.query<RawStayRow>(
    `INSERT INTO stays (
      id, patient_id, patient_name, patient_snapshot, room_id, room_number,
      room_type, cycle_id, admission_date, duration_days, expected_discharge_date,
      completed_at, expiry_date, total_extended_days, attendant_count, attendant_labels,
      daily_rate, daily_rate_is_manual, long_stay_daily_rate, cost_override,
      billing_summary, total_cost, base_cost, extra_attendant_cost, paid_amount,
      pending_amount, extensions, status, bed_number, bed_id, bed_label,
      notes, created_by, created_at, updated_at
    ) VALUES (
      $1, $2, $3, $4, $5, $6,
      $7, $8, $9, $10, $11,
      $12, $13, $14, $15, $16,
      $17, $18, $19, $20,
      $21, $22, $23, $24, $25,
      $26, $27, $28, $29, $30, $31,
      $32, $33, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    ) RETURNING *`,
    [
      stayId,
      body.patientId,
      body.patientName || 'Patient',
      JSON.stringify(body.patientSnapshot || {}),
      body.roomId,
      body.roomNumber || 'Room',
      body.roomType || 'general',
      body.cycleId || null,
      admissionDate,
      durationDays,
      expectedDischargeDate,
      body.completedAt != null ? new Date(body.completedAt) : null,
      expiryDate,
      body.totalExtendedDays != null ? parseInt(body.totalExtendedDays, 10) : 0,
      body.attendantCount != null ? parseInt(body.attendantCount, 10) : 0,
      JSON.stringify(body.attendantLabels || []),
      body.dailyRate != null ? body.dailyRate : null,
      Boolean(body.dailyRateIsManual),
      body.longStayDailyRate != null ? body.longStayDailyRate : null,
      body.costOverride != null ? body.costOverride : null,
      JSON.stringify(body.billingSummary || {}),
      body.totalCost || 0,
      body.baseCost || 0,
      body.extraAttendantCost || 0,
      body.paidAmount != null ? body.paidAmount : null,
      body.pendingAmount != null ? body.pendingAmount : null,
      JSON.stringify(body.extensions || []),
      body.status || 'active',
      body.bedNumber != null ? parseInt(body.bedNumber, 10) : null,
      body.bedId || null,
      body.bedLabel || null,
      body.notes || null,
      userId,
    ]
  );

  if (active) {
    if (room.room_type === 'lobby') {
      await client.query(
        "UPDATE patients SET status='active',lobby=$2,room_id=NULL,room_number=NULL,floor=NULL,bed_ids='[]',bed_labels='[]',discharge_date=NULL,version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=$1",
        [body.patientId, room.room_number]
      );
    } else {
      if (body.bedId) await client.query("UPDATE room_beds SET status='occupied',current_patient_id=$2,current_stay_id=$3,updated_at=CURRENT_TIMESTAMP WHERE id=$1", [body.bedId, body.patientId, stayId]);
      const placements = (await client.query("SELECT bed_id,bed_label FROM stays WHERE patient_id=$1 AND status='active' AND bed_id IS NOT NULL ORDER BY created_at,id", [body.patientId])).rows;
      await client.query("UPDATE patients SET status='active',lobby=NULL,room_id=$2,room_number=$3,floor=$4,bed_ids=$5,bed_labels=$6,discharge_date=NULL,version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=$1", [body.patientId, body.roomId, room.room_number, room.floor, JSON.stringify(placements.map((row: any) => row.bed_id)), JSON.stringify(placements.map((row: any) => row.bed_label))]);
    }
    await refreshRoomOccupancy(client, body.roomId);
  }
  return res.rows[0];
}

export async function stayRoutes(fastify: FastifyInstance, _opts: FastifyPluginOptions): Promise<void> {
  fastify.addHook('preHandler', authenticate);

  // ── GET /api/stays ──────────────────────────────────────────────────────────
  fastify.get('/stays', async (request, reply) => {
    const q = request.query as {
      patientId?: string;
      roomId?: string;
      status?: string;
      format?: 'map' | 'array';
    };

    const conditions: string[] = [];
    const params: unknown[] = [];
    let idx = 1;

    if (q.patientId) {
      conditions.push(`patient_id = $${idx++}`);
      params.push(q.patientId);
    }
    if (q.roomId) {
      conditions.push(`room_id = $${idx++}`);
      params.push(q.roomId);
    }
    if (q.status) {
      conditions.push(`status = $${idx++}`);
      params.push(q.status);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
    const res = await query<RawStayRow>(
      `SELECT * FROM stays ${whereClause} ORDER BY admission_date DESC`,
      params
    );

    const formattedList = res.rows.map(formatStay);

    if (q.format === 'map') {
      const mapRes: Record<string, ReturnType<typeof formatStay>> = {};
      for (const item of formattedList) {
        mapRes[item.id] = item;
      }
      return reply.send(mapRes);
    }

    return reply.send(formattedList);
  });

  // Read-only quote. The existing authentication hook restricts this to staff
  // and admins. Repeatable read keeps both invoice projections consistent.
  fastify.get('/stays/extension-quote', async (request, reply) => {
    const input = z.object({ stayId: z.string().min(1).max(128), additionalDays: z.coerce.number().int().min(1).max(3650) }).safeParse(request.query);
    if (!input.success) throw httpError(400, 'Invalid stay extension quote');
    const client = await getClient();
    try {
      await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      const stay = (await client.query('SELECT * FROM stays WHERE id=$1', [input.data.stayId])).rows[0];
      if (!stay) throw httpError(404, 'Stay not found');
      const patient = (await client.query('SELECT * FROM patients WHERE id=$1', [stay.patient_id])).rows[0];
      const quote = await quoteStayExtension(client, patient, stay, input.data.additionalDays);
      await client.query('COMMIT');
      return reply.send(quote);
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  });

  // ── GET /api/stays/* ───────────────────────────────────────────────────────
  fastify.get('/stays/*', async (request, reply) => {
    const id = (request.params as any)['*'] || (request.params as any).id;
    const res = await query<RawStayRow>('SELECT * FROM stays WHERE id = $1', [id]);
    if (res.rows.length === 0) {
      return reply.status(404).send({ error: 'NotFound', message: `Stay '${id}' not found` });
    }
    return reply.send(formatStay(res.rows[0]));
  });

  // ── POST /api/stays ─────────────────────────────────────────────────────────
  fastify.post('/stays', async (request, reply) => {
    const body = request.body as Record<string, any>;
    const user = request.user!;
    const client = await getClient();
    try {
      await client.query('BEGIN');
      const created = await insertStayWithClient(client, body, user.id);
      const patient = (await client.query('SELECT * FROM patients WHERE id=$1', [created.patient_id])).rows[0];
      const projection = await persistBilling(client, await projectBilling(client, patient));
      await client.query('COMMIT');
      return reply.status(201).send(formatStay(projection.stays.find(s => s.id === created.id) ?? created));
    } catch (err: unknown) {
      await client.query('ROLLBACK');
      throw err;
    } finally { client.release(); }
  });

  // ── POST /api/stays/batch ───────────────────────────────────────────────────
  fastify.post('/stays/batch', async (request, reply) => {
    const body = request.body as { stays: Record<string, any>[] };
    const user = request.user!;
    const client = await getClient();
    try {
      await client.query('BEGIN');
      await client.query('SELECT id FROM patients WHERE id=ANY($1::varchar[]) ORDER BY id FOR UPDATE', [body.stays.map(s => s.patientId)]);
      await client.query('SELECT id FROM rooms WHERE id=ANY($1::varchar[]) ORDER BY id FOR UPDATE', [body.stays.map(s => s.roomId)]);
      const created: ReturnType<typeof formatStay>[] = [];
      for (const item of body.stays) {
        const row = await insertStayWithClient(client, item, user.id);
        created.push(formatStay(row));
      }
      for (const patientId of [...new Set(body.stays.map(s => s.patientId))]) {
        const patient = (await client.query('SELECT * FROM patients WHERE id=$1', [patientId])).rows[0];
        const projection = await persistBilling(client, await projectBilling(client, patient));
        for (let i = 0; i < created.length; i++) {
          const authoritative = projection.stays.find(s => s.id === created[i].id);
          if (authoritative) created[i] = formatStay(authoritative);
        }
      }
      await client.query('COMMIT');
      return reply.status(201).send({ stays: created, ids: created.map(s => s.id) });
    } catch (err: unknown) {
      await client.query('ROLLBACK');
      throw err;
    } finally { client.release(); }
  });

  // ── PUT /api/stays/* ───────────────────────────────────────────────────────
  fastify.put('/stays/*', async (request, reply) => {
    const id = (request.params as any)['*'] || (request.params as any).id;
    let body = request.body as Record<string, any>;
    const extending = body.additionalDays !== undefined;
    const client = await getClient();
    try {
    await client.query('BEGIN');
    const original = (await client.query<RawStayRow>('SELECT * FROM stays WHERE id=$1', [id])).rows[0];
    if (!original) throw httpError(404, 'Stay not found');
    const patient = (await client.query('SELECT * FROM patients WHERE id=$1 FOR UPDATE', [original.patient_id])).rows[0];
    await client.query('SELECT id FROM rooms WHERE id=$1 FOR UPDATE', [original.room_id]);
    const old = (await client.query<RawStayRow>('SELECT * FROM stays WHERE id=$1 FOR UPDATE', [id])).rows[0];
    if (!old) throw httpError(404, 'Stay not found');
    if (old.status === 'active' && body.status === 'completed' && !(await client.query("SELECT id FROM stays WHERE patient_id=$1 AND status='active' AND id<>$2", [old.patient_id, id])).rowCount) {
      const projection = await finalizeDischarge(client, patient, new Date(body.completedAt ?? Date.now()));
      await client.query('COMMIT');
      return reply.send(formatStay(projection.stays.find(s => s.id === id)!));
    }
    if (body.additionalDays !== undefined) {
      const extension = z.object({ additionalDays: z.number().int().min(1).max(3650),
        extensionRequestId: z.string().min(1).max(128), reason: z.string().max(2000).default('') }).safeParse(body);
      if (!extension.success) throw httpError(400, 'Invalid stay extension');
      const { additionalDays, extensionRequestId, reason } = extension.data;
      const entries = Array.isArray(old.extensions) ? old.extensions : [];
      const prior = entries.find(entry => entry.requestId === extensionRequestId);
      if (prior) {
        if (prior.additionalDays !== additionalDays || prior.reason !== reason) throw httpError(409, 'Extension request ID already used differently');
        await client.query('COMMIT');
        return reply.send(formatStay(old));
      }
      if (old.status !== 'active') throw httpError(409, 'Only active stays can be extended');
      const quote = await quoteStayExtension(client, patient, old, additionalDays);
      const cost = quote.additionalCost;
      body = { // duration_days remains the original admission period.
        durationDays: old.duration_days,
        totalExtendedDays: old.total_extended_days + additionalDays,
        expectedDischargeDate: new Date(old.expected_discharge_date).getTime() + additionalDays * 86400000,
        expiryDate: new Date(old.expiry_date).getTime() + additionalDays * 86400000,
        totalCost: Number(old.total_cost) + cost,
        extensions: [...entries, { ...quote, requestId: extensionRequestId, reason, extendedOn: Date.now() }],
      };
      await client.query("UPDATE patients SET extension_days=extension_days+$2,extension_approved=true,exit_date=exit_date+($2 * interval '1 day') WHERE id=$1", [old.patient_id, additionalDays]);
    }
    if ((body.bedId !== undefined && body.bedId !== old.bed_id) || (body.roomId && body.roomId !== old.room_id) || (body.patientId && body.patientId !== old.patient_id)) throw httpError(409, 'An existing stay assignment cannot be changed through this endpoint');
    if (old.status !== 'active' && body.status && body.status !== old.status) throw httpError(409, 'A completed or cancelled stay cannot be reopened');
    if (body.costOverride != null && (await client.query('SELECT 1 FROM billing_corrections WHERE patient_id=$1 AND cycle_id=$2 LIMIT 1',
      [old.patient_id, stayCycle(old, patient)])).rowCount)
      throw httpError(409, 'A fixed stay total cannot replace an admission with date corrections');

    body = { ...formatStay(old), ...body };
    if (body.status === 'completed' && body.completedAt == null) body.completedAt = Date.now();

    const res = await client.query<RawStayRow>(
      `UPDATE stays SET
        duration_days = COALESCE($2, duration_days),
        expected_discharge_date = COALESCE($3, expected_discharge_date),
        completed_at = $4,
        expiry_date = COALESCE($5, expiry_date),
        total_extended_days = COALESCE($6, total_extended_days),
        attendant_count = COALESCE($7, attendant_count),
        attendant_labels = COALESCE($8, attendant_labels),
        daily_rate = $9,
        daily_rate_is_manual = COALESCE($10, daily_rate_is_manual),
        cost_override = $11,
        billing_summary = COALESCE($12, billing_summary),
        total_cost = COALESCE($13, total_cost),
        base_cost = COALESCE($14, base_cost),
        extra_attendant_cost = COALESCE($15, extra_attendant_cost),
        paid_amount = $16,
        pending_amount = $17,
        extensions = COALESCE($18, extensions),
        status = COALESCE($19, status),
        bed_number = $20,
        bed_id = $21,
        bed_label = $22,
        notes = $23,
        long_stay_daily_rate = $24,
        updated_at = CURRENT_TIMESTAMP
      WHERE id = $1
      RETURNING *`,
      [
        id,
        body.durationDays != null ? parseInt(body.durationDays, 10) : null,
        body.expectedDischargeDate != null ? new Date(body.expectedDischargeDate) : null,
        body.completedAt != null ? new Date(body.completedAt) : null,
        body.expiryDate != null ? new Date(body.expiryDate) : null,
        body.totalExtendedDays != null ? parseInt(body.totalExtendedDays, 10) : null,
        body.attendantCount != null ? parseInt(body.attendantCount, 10) : null,
        body.attendantLabels ? JSON.stringify(body.attendantLabels) : null,
        body.dailyRate != null ? body.dailyRate : null,
        body.dailyRateIsManual != null ? Boolean(body.dailyRateIsManual) : null,
        body.costOverride != null ? body.costOverride : null,
        body.billingSummary ? JSON.stringify(body.billingSummary) : null,
        body.totalCost != null ? body.totalCost : null,
        body.baseCost != null ? body.baseCost : null,
        body.extraAttendantCost != null ? body.extraAttendantCost : null,
        body.paidAmount != null ? body.paidAmount : null,
        body.pendingAmount != null ? body.pendingAmount : null,
        body.extensions ? JSON.stringify(body.extensions) : null,
        body.status || null,
        body.bedNumber != null ? parseInt(body.bedNumber, 10) : null,
        body.bedId || null,
        body.bedLabel || null,
        body.notes || null,
        body.longStayDailyRate ?? null,
      ]
    );

    if (res.rows.length === 0) {
      await client.query('ROLLBACK');
      return reply.status(404).send({ error: 'NotFound', message: `Stay '${id}' not found` });
    }

    if (old.status === 'active' && body.status !== 'active') {
      await client.query("UPDATE room_beds SET status='available',current_patient_id=NULL,current_stay_id=NULL,updated_at=CURRENT_TIMESTAMP WHERE current_stay_id=$1", [id]);
      const others = await client.query("SELECT bed_id,bed_label FROM stays WHERE patient_id=$1 AND status='active' ORDER BY created_at,id", [old.patient_id]);
      if (!others.rowCount) await client.query(`UPDATE patients SET status=CASE WHEN $2='completed' THEN 'discharged' ELSE status END,
        discharge_date=CASE WHEN $2='completed' THEN $3 ELSE discharge_date END,
        lobby=NULL,room_id=NULL,room_number=NULL,floor=NULL,bed_ids='[]',bed_labels='[]',version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=$1`, [old.patient_id, body.status, new Date(body.completedAt ?? Date.now())]);
      else await client.query("UPDATE patients SET status='active',bed_ids=$2,bed_labels=$3,version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=$1", [old.patient_id, JSON.stringify(others.rows.filter(row => row.bed_id).map(row => row.bed_id)), JSON.stringify(others.rows.filter(row => row.bed_id).map(row => row.bed_label))]);
    }
    await client.query('UPDATE patients SET version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=$1', [old.patient_id]);
    await refreshRoomOccupancy(client, old.room_id);
    let responseStay = res.rows[0];
    if (extending) {
      const currentPatient = (await client.query('SELECT * FROM patients WHERE id=$1', [old.patient_id])).rows[0];
      const projection = await persistBilling(client, await projectBilling(client, currentPatient, { ignoreCheckout: true }));
      responseStay = projection.stays.find(stay => stay.id === id) ?? responseStay;
    }
    await client.query('COMMIT');

    return reply.send(formatStay(responseStay));
    } catch (err) { await client.query('ROLLBACK'); throw err; }
    finally { client.release(); }
  });

  // ── DELETE /api/stays/* ────────────────────────────────────────────────────
  fastify.delete('/stays/*', async (request, reply) => {
    const id = (request.params as any)['*'] || (request.params as any).id;
    const client = await getClient();
    try {
      await client.query('BEGIN');
      const original = (await client.query<RawStayRow>('SELECT * FROM stays WHERE id=$1', [id])).rows[0];
      if (!original) throw httpError(404, 'Stay not found');
      await client.query('SELECT id FROM patients WHERE id=$1 FOR UPDATE', [original.patient_id]);
      await client.query('SELECT id FROM rooms WHERE id=$1 FOR UPDATE', [original.room_id]);
      const existing = (await client.query<RawStayRow>('SELECT * FROM stays WHERE id=$1 FOR UPDATE', [id])).rows[0];
      if (!existing) {
        await client.query('ROLLBACK');
        return reply.status(404).send({ error: 'NotFound', message: `Stay '${id}' not found` });
      }
      await client.query("UPDATE room_beds SET status='available',current_patient_id=NULL,current_stay_id=NULL,updated_at=CURRENT_TIMESTAMP WHERE current_stay_id=$1", [id]);
      await client.query('DELETE FROM stays WHERE id=$1', [id]);
      if (existing.status === 'active') {
        const others = await client.query("SELECT bed_id,bed_label FROM stays WHERE patient_id=$1 AND status='active' ORDER BY created_at,id", [existing.patient_id]);
        if (!others.rowCount) {
          await client.query(
            "UPDATE patients SET lobby=NULL,room_id=NULL,room_number=NULL,floor=NULL,bed_ids='[]',bed_labels='[]',version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=$1",
            [existing.patient_id]
          );
        } else {
          await client.query(
            "UPDATE patients SET bed_ids=$2,bed_labels=$3,version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=$1",
            [
              existing.patient_id,
              JSON.stringify(others.rows.filter(row => row.bed_id).map(row => row.bed_id)),
              JSON.stringify(others.rows.filter(row => row.bed_id).map(row => row.bed_label)),
            ]
          );
        }
      }
      await refreshRoomOccupancy(client, existing.room_id);
      await client.query('COMMIT');
      return reply.send({ success: true, deletedId: id });
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  });
}
