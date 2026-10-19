import { FastifyReply } from 'fastify';
import { httpError } from './validation.js';

type Collection = 'patients' | 'payments';
interface Cursor { collection: Collection; date: string; id: string; version: 1 }

/** Keep PostgreSQL microseconds: JavaScript Date would lose page boundaries. */
export const cursorDateSql = (column: 'p.admission_date' | 'payment_date' | 'p.payment_date') =>
  `to_char(${column} AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS cursor_date`;

export function parseCollectionCursor(value: unknown, collection: Collection, offset = 0): Cursor | undefined {
  if (value === undefined) return undefined;
  const invalid = () => httpError(400, 'Invalid collection cursor');
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,1024}$/.test(value) || offset > 0) throw invalid();
  try {
    const decoded: unknown = JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
    if (!decoded || typeof decoded !== 'object') throw invalid();
    const cursor = decoded as Cursor;
    if (cursor.version !== 1 || cursor.collection !== collection || typeof cursor.id !== 'string'
      || cursor.id.length < 1 || cursor.id.length > 64 || typeof cursor.date !== 'string'
      || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/.test(cursor.date)) throw invalid();
    // Reject impossible dates/times before the SQL timestamptz cast. Compare
    // millisecond precision only here; retain all six digits in the SQL value.
    const normalized = `${cursor.date.slice(0,23)}Z`;
    const date = new Date(normalized);
    if (!Number.isFinite(date.getTime()) || date.toISOString() !== normalized) throw invalid();
    return cursor;
  } catch { throw invalid(); }
}

/** Fetch limit+1 rows; expose only the requested page with a typed continuation. */
export function collectionPage<T extends { id: string; cursor_date?: string }>(
  reply: FastifyReply, rows: T[], limit: number, collection: Collection,
): T[] {
  reply.header('x-pagination-mode', 'cursor');
  reply.header('access-control-expose-headers', 'x-pagination-mode, x-next-cursor');
  if (rows.length > limit) {
    const last = rows[limit-1];
    if (!last.cursor_date) throw new Error('Missing database cursor timestamp');
    const cursor: Cursor = { version: 1, collection, date: last.cursor_date, id: last.id };
    reply.header('x-next-cursor', Buffer.from(JSON.stringify(cursor)).toString('base64url'));
  }
  return rows.slice(0,limit);
}
