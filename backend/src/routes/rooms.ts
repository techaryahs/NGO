import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import { getClient, query } from '../db/index.js';
import { authenticate } from '../middleware/auth.js';
import { randomUUID } from 'node:crypto';
import { httpError } from '../validation.js';
import { refreshRoomOccupancy } from '../db/occupancy.js';

interface RawRoomRow {
  id: string;
  room_number: string;
  room_identifier: string | null;
  floor: number;
  room_type: string;
  status: string;
  max_attendants: number;
  current_attendants: number;
  has_custom_attendant_limit: boolean;
  total_beds: number;
  occupied_beds: number;
  expected_vacancy_date: Date | string | null;
  version: number;
  notes: string | null;
  created_at: Date | string;
  updated_at: Date | string;
}

interface RawBedRow {
  id: string;
  room_id: string;
  bed_label: string;
  status: string;
  current_patient_id: string | null;
  current_stay_id: string | null;
  last_cleaned: Date | string | null;
}

function toEpochMs(d: Date | string | number | null | undefined): number | null {
  if (d == null) return null;
  if (typeof d === 'number') return d;
  const parsed = new Date(d).getTime();
  return isNaN(parsed) ? null : parsed;
}

function formatRoom(room: RawRoomRow, beds: RawBedRow[] = []) {
  return {
    id: room.id,
    roomNumber: room.room_number,
    roomIdentifier: room.room_identifier || room.room_number,
    floor: room.floor,
    roomType: room.room_type,
    status: room.status,
    maxAttendants: room.max_attendants,
    currentAttendants: room.current_attendants,
    hasCustomAttendantLimit: Boolean(room.has_custom_attendant_limit),
    totalBeds: room.total_beds,
    occupiedBeds: room.occupied_beds,
    expectedVacancyDate: toEpochMs(room.expected_vacancy_date),
    version: room.version || 0,
    notes: room.notes,
    createdAt: toEpochMs(room.created_at) ?? Date.now(),
    updatedAt: toEpochMs(room.updated_at) ?? Date.now(),
    beds: beds.map((b) => ({
      id: b.id,
      bedNumber: b.bed_label,
      bedLabel: b.bed_label,
      status: b.status,
      currentPatientId: b.current_patient_id,
      currentStayId: b.current_stay_id,
      lastCleaned: toEpochMs(b.last_cleaned),
    })),
  };
}

export async function roomRoutes(fastify: FastifyInstance, _opts: FastifyPluginOptions): Promise<void> {
  fastify.addHook('preHandler', authenticate);

  // ── GET /api/rooms ──────────────────────────────────────────────────────────
  fastify.get('/rooms', async (request, reply) => {
    const q = request.query as { floor?: string; roomType?: string; format?: 'map' | 'array' };

    const conditions: string[] = [];
    const params: unknown[] = [];
    let idx = 1;

    if (q.floor) {
      conditions.push(`floor = $${idx++}`);
      params.push(parseInt(q.floor, 10));
    }
    if (q.roomType) {
      conditions.push(`room_type = $${idx++}`);
      params.push(q.roomType);
    } else {
      conditions.push(`room_type <> 'lobby'`);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
    const roomsRes = await query<RawRoomRow>(`SELECT * FROM rooms ${whereClause} ORDER BY floor ASC, room_number ASC`, params);

    const bedsRes = await query<RawBedRow>('SELECT * FROM room_beds ORDER BY bed_label ASC');
    const bedsByRoom = new Map<string, RawBedRow[]>();
    for (const bed of bedsRes.rows) {
      const list = bedsByRoom.get(bed.room_id) || [];
      list.push(bed);
      bedsByRoom.set(bed.room_id, list);
    }

    const formattedRooms = roomsRes.rows.map((r) => formatRoom(r, bedsByRoom.get(r.id) || []));

    if (q.format === 'map') {
      const mapRes: Record<string, ReturnType<typeof formatRoom>> = {};
      for (const r of formattedRooms) {
        mapRes[r.id] = r;
      }
      return reply.send(mapRes);
    }

    return reply.send(formattedRooms);
  });

  // ── GET /api/rooms/:id ──────────────────────────────────────────────────────
  fastify.get('/rooms/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const roomRes = await query<RawRoomRow>('SELECT * FROM rooms WHERE id = $1', [id]);
    if (roomRes.rows.length === 0) {
      return reply.status(404).send({ error: 'NotFound', message: `Room '${id}' not found` });
    }

    const bedsRes = await query<RawBedRow>('SELECT * FROM room_beds WHERE room_id = $1 ORDER BY bed_label ASC', [id]);
    return reply.send(formatRoom(roomRes.rows[0], bedsRes.rows));
  });

  // ── POST /api/rooms ─────────────────────────────────────────────────────────
  fastify.post('/rooms', async (request, reply) => {
    const body = request.body as Record<string, any>;
    const roomId = body.id || `r_${randomUUID()}`;

    const client = await getClient();
    try {
      await client.query('BEGIN');

      const roomRes = await client.query<RawRoomRow>(
        `INSERT INTO rooms (
          id, room_number, room_identifier, floor, room_type, status,
          max_attendants, current_attendants, has_custom_attendant_limit,
          total_beds, occupied_beds, expected_vacancy_date, version, notes
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
        RETURNING *`,
        [
          roomId,
          body.roomNumber || 'Room',
          body.roomIdentifier || body.roomNumber || 'Room',
          body.floor != null ? parseInt(body.floor, 10) : 1,
          body.roomType || 'general',
          body.status || 'available',
          body.maxAttendants != null ? parseInt(body.maxAttendants, 10) : 5,
          body.currentAttendants != null ? parseInt(body.currentAttendants, 10) : 0,
          Boolean(body.hasCustomAttendantLimit),
          Array.isArray(body.beds) ? body.beds.length : 0,
          0,
          body.expectedVacancyDate != null ? new Date(body.expectedVacancyDate) : null,
          body.version != null ? parseInt(body.version, 10) : 1,
          body.notes || null,
        ]
      );

      const insertedBeds: RawBedRow[] = [];
      if (Array.isArray(body.beds)) {
        for (let i = 0; i < body.beds.length; i++) {
          const b = body.beds[i];
          if (b.currentPatientId || b.currentStayId || b.status === 'occupied') throw httpError(409, 'Assign beds through the stay lifecycle');
          const bedId = b.id || `${roomId}_bed_${i + 1}`;
          const bedRes = await client.query<RawBedRow>(
            `INSERT INTO room_beds (id, room_id, bed_label, status, current_patient_id, current_stay_id, last_cleaned)
             VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
            [
              bedId,
              roomId,
              b.bedLabel || b.bedNumber || String(i + 1),
              b.status || 'available',
              b.currentPatientId || null,
              b.currentStayId || null,
              b.lastCleaned != null ? new Date(b.lastCleaned) : null,
            ]
          );
          insertedBeds.push(bedRes.rows[0]);
        }
      }

      await client.query('COMMIT');
      return reply.status(201).send(formatRoom(roomRes.rows[0], insertedBeds));
    } catch (err: unknown) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  });

  // ── PUT /api/rooms/:id ──────────────────────────────────────────────────────
  fastify.put('/rooms/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    let body = request.body as Record<string, any>;

    const client = await getClient();
    try {
      await client.query('BEGIN');

      const existing = await client.query<RawRoomRow>('SELECT * FROM rooms WHERE id = $1 FOR UPDATE', [id]);
      if (existing.rows.length === 0) {
        await client.query('ROLLBACK');
        return reply.status(404).send({ error: 'NotFound', message: `Room '${id}' not found` });
      }

      // Concurrency check if expectedVersion is provided
      if (body.expectedVersion != null && existing.rows[0].version !== body.expectedVersion) {
        await client.query('ROLLBACK');
        return reply.status(409).send({
          error: 'Conflict',
          message: `Room version mismatch. Current: ${existing.rows[0].version}, expected: ${body.expectedVersion}`,
        });
      }
      body = { ...formatRoom(existing.rows[0]), ...body };

      const updateSql = `
        UPDATE rooms SET
          room_number = COALESCE($2, room_number),
          room_identifier = COALESCE($3, room_identifier),
          floor = COALESCE($4, floor),
          room_type = COALESCE($5, room_type),
          status = COALESCE($6, status),
          max_attendants = COALESCE($7, max_attendants),
          current_attendants = COALESCE($8, current_attendants),
          has_custom_attendant_limit = COALESCE($9, has_custom_attendant_limit),
          total_beds = COALESCE($10, total_beds),
          occupied_beds = COALESCE($11, occupied_beds),
          expected_vacancy_date = $12,
          version = version + 1,
          notes = $13,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = $1
        RETURNING *
      `;

      const updated = await client.query<RawRoomRow>(updateSql, [
        id,
        body.roomNumber || null,
        body.roomIdentifier || null,
        body.floor != null ? parseInt(body.floor, 10) : null,
        body.roomType || null,
        body.status || null,
        body.maxAttendants != null ? parseInt(body.maxAttendants, 10) : null,
        body.currentAttendants != null ? parseInt(body.currentAttendants, 10) : null,
        body.hasCustomAttendantLimit != null ? Boolean(body.hasCustomAttendantLimit) : null,
        body.totalBeds != null ? parseInt(body.totalBeds, 10) : null,
        body.occupiedBeds != null ? parseInt(body.occupiedBeds, 10) : null,
        body.expectedVacancyDate != null ? new Date(body.expectedVacancyDate) : null,
        body.notes || null,
      ]);

      // If beds array provided, upsert beds
      if (Array.isArray(body.beds)) {
        for (const b of body.beds) {
          if (!b.id) continue;
          const previous = (await client.query<RawBedRow>('SELECT * FROM room_beds WHERE id=$1', [b.id])).rows[0];
          if (previous && previous.room_id !== id) throw httpError(409, 'Bed belongs to a different room');
          if ((b.currentPatientId != null && b.currentPatientId !== previous?.current_patient_id) || (b.currentStayId != null && b.currentStayId !== previous?.current_stay_id) || (b.status === 'occupied' && !previous?.current_stay_id)) throw httpError(409, 'Assign beds through the stay lifecycle');
          const upserted = await client.query(
            `INSERT INTO room_beds (id, room_id, bed_label, status, current_patient_id, current_stay_id, last_cleaned)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (id) DO UPDATE SET
               bed_label = EXCLUDED.bed_label,
               status = CASE WHEN room_beds.current_stay_id IS NOT NULL THEN room_beds.status ELSE EXCLUDED.status END,
               last_cleaned = EXCLUDED.last_cleaned,
               updated_at = CURRENT_TIMESTAMP
             WHERE room_beds.room_id = EXCLUDED.room_id RETURNING id`,
            [
              b.id,
              id,
              b.bedLabel || b.bedNumber || 'Bed',
              b.status || 'available',
              b.currentPatientId || null,
              b.currentStayId || null,
              b.lastCleaned != null ? new Date(b.lastCleaned) : previous?.last_cleaned ?? null,
            ]
          );
          if (!upserted.rowCount) throw httpError(409, 'Bed belongs to a different room');
        }
      }

      const allBeds = await client.query<RawBedRow>(
        'SELECT * FROM room_beds WHERE room_id = $1 ORDER BY bed_label ASC',
        [id]
      );
      await refreshRoomOccupancy(client, id);
      const finalRoom = await client.query<RawRoomRow>('SELECT * FROM rooms WHERE id=$1', [id]);

      await client.query('COMMIT');
      return reply.send(formatRoom(finalRoom.rows[0], allBeds.rows));
    } catch (err: unknown) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  });

  // ── PUT /api/rooms/:id/beds/:bedId ──────────────────────────────────────────
  fastify.post('/rooms/:id/beds', async (request, reply) => {
    const { id } = request.params as { id: string };
    const body = request.body as Record<string, any>;
    if (!body.bedLabel && !body.bedNumber) throw httpError(400, 'bedLabel is required');
    if (body.currentPatientId || body.currentStayId || body.status === 'occupied') throw httpError(409, 'Assign beds through the stay lifecycle');
    const client = await getClient();
    try {
      await client.query('BEGIN');
      const room = await client.query('SELECT id FROM rooms WHERE id=$1 FOR UPDATE', [id]);
      if (!room.rowCount) throw httpError(404, 'Room not found');
      const bed = await client.query<RawBedRow>(`INSERT INTO room_beds(id,room_id,bed_label,status) VALUES($1,$2,$3,$4) RETURNING *`, [body.id || `b_${randomUUID()}`, id, body.bedLabel || String(body.bedNumber), body.status || 'available']);
      await refreshRoomOccupancy(client, id);
      await client.query('COMMIT');
      return reply.status(201).send(formatRoom({} as RawRoomRow, bed.rows).beds[0]);
    } catch (err) { await client.query('ROLLBACK'); throw err; }
    finally { client.release(); }
  });

  fastify.put('/rooms/:id/beds/:bedId', async (request, reply) => {
    const { id, bedId } = request.params as { id: string; bedId: string };
    let body = request.body as Record<string, any>;
    const client = await getClient();
    try {
      await client.query('BEGIN');
      await client.query('SELECT id FROM rooms WHERE id=$1 FOR UPDATE', [id]);
      const current = await client.query<RawBedRow>('SELECT * FROM room_beds WHERE id=$1 AND room_id=$2 FOR UPDATE', [bedId, id]);
      if (!current.rowCount) throw httpError(404, 'Bed not found in room');
      const old = current.rows[0];
      if ((body.currentPatientId !== undefined && body.currentPatientId !== old.current_patient_id) || (body.currentStayId !== undefined && body.currentStayId !== old.current_stay_id) || (old.current_stay_id && body.status && body.status !== 'occupied') || (!old.current_stay_id && body.status === 'occupied')) throw httpError(409, 'Change assignments through the stay lifecycle');
      body = { currentPatientId: old.current_patient_id, currentStayId: old.current_stay_id, ...body };

    const res = await client.query<RawBedRow>(
      `UPDATE room_beds SET
         status = COALESCE($3, status),
         current_patient_id = $4,
         current_stay_id = $5,
         last_cleaned = COALESCE($6, last_cleaned),
         bed_label = COALESCE($7, bed_label),
         updated_at = CURRENT_TIMESTAMP
       WHERE id = $1 AND room_id = $2
       RETURNING *`,
      [
        bedId,
        id,
        body.status || null,
        body.currentPatientId !== undefined ? body.currentPatientId : null,
        body.currentStayId !== undefined ? body.currentStayId : null,
        body.lastCleaned != null ? new Date(body.lastCleaned) : null,
        body.bedLabel || body.bedNumber || null,
      ]
    );

    if (res.rows.length === 0) {
      return reply.status(404).send({ error: 'NotFound', message: `Bed '${bedId}' not found in room '${id}'` });
    }

    // Bump room version
    await refreshRoomOccupancy(client, id);
    await client.query('COMMIT');

    const bed = res.rows[0];
    return reply.send({
      id: bed.id,
      bedLabel: bed.bed_label,
      status: bed.status,
      currentPatientId: bed.current_patient_id,
      currentStayId: bed.current_stay_id,
      lastCleaned: toEpochMs(bed.last_cleaned),
    });
    } catch (err) { await client.query('ROLLBACK'); throw err; }
    finally { client.release(); }
  });

  // ── DELETE /api/rooms/:id ───────────────────────────────────────────────────
  fastify.delete('/rooms/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const client = await getClient();
    try {
      await client.query('BEGIN');
      const roomRes = await client.query<RawRoomRow>('SELECT * FROM rooms WHERE id = $1 FOR UPDATE', [id]);
      if (roomRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return reply.status(404).send({ error: 'NotFound', message: `Room '${id}' not found` });
      }
      const occupiedBeds = await client.query("SELECT id FROM room_beds WHERE room_id = $1 AND status = 'occupied'", [id]);
      if (occupiedBeds.rowCount) {
        throw httpError(409, 'Cannot delete room while one or more beds are occupied');
      }
      const activeStays = await client.query("SELECT id FROM stays WHERE room_id = $1 AND status = 'active'", [id]);
      if (activeStays.rowCount) {
        throw httpError(409, 'Cannot delete room with active stays');
      }
      await client.query('DELETE FROM room_beds WHERE room_id = $1', [id]);
      await client.query('DELETE FROM rooms WHERE id = $1', [id]);
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
