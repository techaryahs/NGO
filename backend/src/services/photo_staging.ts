import { query } from '../db/index.js';

export interface PendingPhotoRow {
  photo_ref: string;
  patient_id: string;
  kind: string;
  content_type: string;
  data: string;
  version: number | string;
  created_at: Date | string;
}

export interface PhotoLogger {
  info: (data: any, msg?: string) => void;
  error?: (data: any, msg?: string) => void;
}

/**
 * Move any pending_photos rows for patientId into patient_photos and delete the staged rows.
 * Must be executed inside the same transaction as patient creation.
 * Returns the count of adopted photos. No-op if there are no staged rows.
 */
export async function adoptPendingPhotos(
  client: { query: (text: string, params?: any[]) => Promise<any> },
  patientId: string
): Promise<number> {
  const moveRes = await client.query(
    `INSERT INTO patient_photos (photo_ref, patient_id, photo_type, content_type, data, version, updated_at)
     SELECT photo_ref, patient_id, kind, content_type, data, version, CURRENT_TIMESTAMP
     FROM pending_photos
     WHERE patient_id = $1
     ON CONFLICT (photo_ref) DO UPDATE
     SET data = EXCLUDED.data,
         content_type = EXCLUDED.content_type,
         version = EXCLUDED.version,
         updated_at = CURRENT_TIMESTAMP
     RETURNING photo_ref`,
    [patientId]
  );
  if (moveRes.rowCount && moveRes.rowCount > 0) {
    await client.query('DELETE FROM pending_photos WHERE patient_id = $1', [patientId]);
  }
  return moveRes.rowCount ?? 0;
}

/**
 * Delete staged photos older than 24 hours (blob + row).
 * Emits one log line per sweep with the count deleted.
 */
export async function cleanupPendingPhotos(log?: PhotoLogger): Promise<number> {
  const result = await query(
    `DELETE FROM pending_photos WHERE created_at < NOW() - INTERVAL '24 hours' RETURNING photo_ref`
  );
  const deletedCount = result.rowCount ?? 0;
  if (log?.info) {
    log.info({ event: 'pending_photos_cleanup', deletedCount }, `Pending photos cleanup completed: ${deletedCount} deleted`);
  } else {
    console.log(`[PendingPhotos] Cleanup completed: ${deletedCount} deleted`);
  }
  return deletedCount;
}

/**
 * Start hourly cleanup timer and run once immediately on startup.
 */
export function startPhotoCleanup(log?: PhotoLogger): () => Promise<void> {
  let running: Promise<unknown> | undefined;
  const run = () => {
    if (!running) {
      running = cleanupPendingPhotos(log)
        .catch(err => {
          if (log?.error) {
            log.error({ event: 'pending_photos_cleanup_failed', err }, 'Pending photos cleanup failed');
          } else {
            console.error('Pending photos cleanup failed', err);
          }
        })
        .finally(() => { running = undefined; });
    }
    return running;
  };
  const timer = setInterval(() => { void run(); }, 60 * 60 * 1000);
  timer.unref();
  void run();
  return async () => {
    clearInterval(timer);
    await running;
  };
}
