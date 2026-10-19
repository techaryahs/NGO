import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import { query } from '../db/index.js';
import { authenticate, requireRoles } from '../middleware/auth.js';
import { z } from 'zod';

interface RawPhotoRow {
  photo_ref: string;
  patient_id: string;
  photo_type: string;
  content_type: string;
  data: string;
  version: number | string;
  updated_at: Date | string;
}

export async function photoRoutes(fastify: FastifyInstance, _opts: FastifyPluginOptions): Promise<void> {
  fastify.addHook('preHandler', authenticate);
  fastify.addHook('preHandler', requireRoles(['admin', 'staff']));

  const validPhotoRef = /^patientPhotos\/[A-Za-z0-9_-]{1,64}\/(patient|attendants\/[A-Za-z0-9_-]{1,64})$/;

  // ── GET /api/photos/* ───────────────────────────────────────────────────────
  fastify.get('/photos/*', async (request, reply) => {
    const rawRef = (request.params as any)['*'] as string;
    const photoRef = rawRef.startsWith('patientPhotos/') ? rawRef : `patientPhotos/${rawRef}`;
    if (!validPhotoRef.test(photoRef)) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid photo reference' });

    const res = await query<RawPhotoRow>(
      'SELECT * FROM patient_photos WHERE photo_ref = $1',
      [photoRef]
    );

    if (res.rows.length === 0) {
      return reply.status(404).send({ error: 'NotFound', message: `Photo '${photoRef}' not found` });
    }

    const row = res.rows[0];
    return reply.send({
      photoRef: row.photo_ref,
      patientId: row.patient_id,
      photoType: row.photo_type,
      contentType: row.content_type,
      data: row.data,
      version: Number(row.version),
      updatedAt: new Date(row.updated_at).getTime(),
    });
  });

  // ── PUT /api/photos/* ───────────────────────────────────────────────────────
  fastify.put('/photos/*', async (request, reply) => {
    const rawRef = (request.params as any)['*'] as string;
    const photoRef = rawRef.startsWith('patientPhotos/') ? rawRef : `patientPhotos/${rawRef}`;
    const parsed = z.object({
      data: z.string().min(1).max(409600).regex(/^(?:data:image\/(?:png|jpeg);base64,)?(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/),
      contentType: z.enum(['image/jpeg', 'image/png']).optional(),
      version: z.number().int().positive().max(Number.MAX_SAFE_INTEGER).default(1),
      patientId: z.string().optional(),
    }).safeParse(request.body);
    if (!validPhotoRef.test(photoRef) || !parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid photo reference, base64 data or metadata' });
    const body = parsed.data;

    // Infer patientId and photoType from path (e.g. patientPhotos/p_123/patient or patientPhotos/p_123/attendants/att_1)
    const segments = photoRef.split('/');
    const inferredPatientId = segments[1];
    if (body.patientId !== undefined && body.patientId !== inferredPatientId) return reply.status(400).send({ error: 'BadRequest', message: 'Patient ID must match the photo reference' });
    const inferredType = segments.includes('attendants') ? 'attendant' : 'patient';
    const contentType = body.contentType || (body.data.startsWith('data:image/png') ? 'image/png' : 'image/jpeg');
    const version = body.version;

    const res = await query<RawPhotoRow>(
      `INSERT INTO patient_photos (photo_ref, patient_id, photo_type, content_type, data, version, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP)
       ON CONFLICT (photo_ref) DO UPDATE
       SET data = EXCLUDED.data,
           content_type = EXCLUDED.content_type,
           version = EXCLUDED.version,
           updated_at = CURRENT_TIMESTAMP
       WHERE EXCLUDED.version > patient_photos.version
         OR (EXCLUDED.version = patient_photos.version AND EXCLUDED.data = patient_photos.data
           AND EXCLUDED.content_type = patient_photos.content_type)
       RETURNING *`,
      [photoRef, inferredPatientId, inferredType, contentType, body.data, version]
    );

    if (res.rows.length === 0) return reply.status(409).send({ error: 'Conflict', message: 'Photo has a newer or conflicting version' });
    const row = res.rows[0];
    return reply.send({
      photoRef: row.photo_ref,
      patientId: row.patient_id,
      photoType: row.photo_type,
      contentType: row.content_type,
      version: Number(row.version),
      updatedAt: new Date(row.updated_at).getTime(),
    });
  });

  // ── DELETE /api/photos/* ────────────────────────────────────────────────────
  fastify.delete('/photos/*', { preHandler: requireRoles(['admin', 'staff']) }, async (request, reply) => {
    const rawRef = (request.params as any)['*'] as string;
    const photoRef = rawRef.startsWith('patientPhotos/') ? rawRef : `patientPhotos/${rawRef}`;
    if (!validPhotoRef.test(photoRef)) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid photo reference' });

    await query('DELETE FROM patient_photos WHERE photo_ref = $1', [photoRef]);
    return reply.status(200).send({ success: true });
  });
}
