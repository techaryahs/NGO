import { projectBilling, persistBilling, receiptCycle, stayCycle, money as cents, decimal } from '../services/billing.js';
import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import { getClient, query } from '../db/index.js';
import { authenticate } from '../middleware/auth.js';
import { createHash, randomUUID } from 'node:crypto';
import { httpError } from '../validation.js';
import { collectionPage, cursorDateSql, parseCollectionCursor } from '../pagination.js';

interface RawPaymentRow {
  cursor_date?: string;
  id: string;
  patient_id: string;
  cycle_id: string | null;
  type: string;
  amount: string | number;
  total_amount: string | number;
  paid_amount: string | number;
  pending_amount: string | number;
  payment_status: string;
  method: string;
  payment_date: Date | string;
  receipt_number: string | null;
  check_number: string | null;
  bank_name: string | null;
  transaction_id: string | null;
  source: string;
  notes: string | null;
  created_at: Date | string;
  updated_at: Date | string;
  request_fingerprint?: string | null;
}

function toEpochMs(d: Date | string | number | null | undefined): number {
  if (d == null) return Date.now();
  if (typeof d === 'number') return d;
  const parsed = new Date(d).getTime();
  return isNaN(parsed) ? Date.now() : parsed;
}

export function formatPayment(row: RawPaymentRow) {
  return {
    id: row.id,
    patientId: row.patient_id,
    patientName: (row as any).patient_name ?? (row as any).patientName ?? null,
    cycleId: row.cycle_id,
    type: row.type || 'payment',
    amount: parseFloat(String(row.amount)),
    totalAmount: parseFloat(String(row.total_amount || row.amount)),
    paidAmount: parseFloat(String(row.paid_amount || row.amount)),
    pendingAmount: parseFloat(String(row.pending_amount || 0)),
    paymentStatus: row.payment_status || 'Paid',
    method: row.method || 'cash',
    date: toEpochMs(row.payment_date),
    receiptNumber: row.receipt_number,
    checkNumber: row.check_number,
    bankName: row.bank_name,
    transactionId: row.transaction_id,
    notes: row.notes,
  };
}

type PaymentClient = Awaited<ReturnType<typeof getClient>>;
type LockedPatient = {
  id: string; admission_date: Date | string; registration_date: Date | string | null;
  total_paid_amount: string; current_due_amount: string; refund_due_amount: string;
  total_refund_due_amount: string; total_refunded_amount: string;
  admission_balances: Record<string, Record<string, any>>;
};

async function applyPaymentDelta(client: PaymentClient, patient: LockedPatient, before: RawPaymentRow | null, after: RawPaymentRow | null, checkoutAt?: Date) {
  // The ledger mutation and this read occur under the same patient row lock.
  // A saved patient/admission summary never authorizes a refund.
  // Only an explicit refund mutation uses a previously requested settlement
  // quote. Collections and ordinary reads use the active booking period.
  const projection = await projectBilling(client, patient, {
    checkoutAt,
    useSavedCheckout: Number(before?.amount) < 0 || Number(after?.amount) < 0,
  });
  if ((projection.reconciliation.required || projection.reconciliation.allocationRequired) && (Number(before?.amount) < 0 || Number(after?.amount) < 0))
    throw httpError(409, 'Reconcile receipt allocations, admission identities and invoice evidence before issuing or changing a refund');
  const changes = new Map<string, { paid: number; refunded: number }>();
  for (const [row, direction] of [[before, -1], [after, 1]] as const) {
    if (!row) continue;
    const cycle = receiptCycle(row, patient, projection.stays);
    if (direction === -1 && (cycle == null || !projection.balances[cycle])) continue;
    if (cycle == null && Number(row.amount) > 0) continue;
    if (cycle == null) throw httpError(409, 'Payment allocation requires an explicit admission cycle');
    const change = changes.get(cycle) ?? { paid: 0, refunded: 0 };
    const amount = cents(row.amount);
    if (amount < 0) change.refunded -= amount * direction;
    else change.paid += amount * direction;
    changes.set(cycle, change);
  }
  for (const [cycle, change] of changes) {
    const balance = projection.balances[cycle];
    if (!balance) throw httpError(409, 'Payment does not belong to a known admission');
    const net = cents(balance.netPaid), billed = cents(balance.total);
    const previousNet = net - change.paid + change.refunded;
    if (change.refunded > 0 && change.refunded > Math.max(0, previousNet - billed) + change.paid) {
      throw httpError(409, 'Refund exceeds the remaining excess payment');
    }
    if (net < 0) throw httpError(409, 'Payment change would make financial balances negative');
  }
  await persistBilling(client, projection);
  return projection.balances;
}

async function lockPayment(client: PaymentClient, id: string): Promise<{ patient: LockedPatient; payment: RawPaymentRow } | null> {
  const owner = await client.query<{ patient_id: string }>('SELECT patient_id FROM payments WHERE id=$1', [id]);
  if (!owner.rowCount) return null;
  // Match POST's patient-then-payment order; locking the receipt first can
  // deadlock with patient-wide billing writes and concurrent payment edits.
  const patient = await client.query<LockedPatient>('SELECT * FROM patients WHERE id=$1 FOR UPDATE', [owner.rows[0].patient_id]);
  const payment = await client.query<RawPaymentRow>('SELECT * FROM payments WHERE id=$1 FOR UPDATE', [id]);
  if (!payment.rowCount) return null;
  if (!patient.rowCount) throw httpError(409, 'Patient not found');
  if (payment.rows[0].patient_id !== patient.rows[0].id) throw httpError(409, 'Payment was replaced while being changed; retry with its current owner');
  return { patient: patient.rows[0], payment: payment.rows[0] };
}

export async function paymentRoutes(fastify: FastifyInstance, _opts: FastifyPluginOptions): Promise<void> {
  fastify.addHook('preHandler', authenticate);

  fastify.get('/payments/:id/history', async (request, reply) => {
    const { id } = request.params as { id: string };
    return reply.send((await query('SELECT * FROM payment_change_history WHERE payment_id=$1 ORDER BY id', [id])).rows);
  });

  // ── GET /api/payments ───────────────────────────────────────────────────────
  fastify.get('/payments', async (request, reply) => {
    const q = request.query as {
      patientId?: string;
      limit?: string;
      offset?: string;
      cursor?: string;
      format?: 'map' | 'array';
    };

    const conditions: string[] = [];
    const params: unknown[] = [];
    let idx = 1;

    if (q.patientId) {
      conditions.push(`p.patient_id = $${idx++}`);
      params.push(q.patientId);
    }

    const limit = q.limit ? parseInt(q.limit, 10) : 500;
    const offset = q.offset ? parseInt(q.offset, 10) : 0;
    const cursor = parseCollectionCursor(q.cursor, 'payments', offset);
    if (cursor) {
      conditions.push(`(p.payment_date, p.id) < ($${idx++}::timestamptz, $${idx++}::varchar)`);
      params.push(cursor.date, cursor.id);
    }
    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const res = await query<RawPaymentRow>(
      `SELECT p.*, pt.full_name AS patient_name, ${cursorDateSql('p.payment_date')}
       FROM payments p
       LEFT JOIN patients pt ON p.patient_id = pt.id
       ${whereClause}
       ORDER BY p.payment_date DESC, p.id DESC
       LIMIT ${limit + 1} OFFSET ${offset}`,
      params
    );

    const formattedList = collectionPage(reply, res.rows, limit, 'payments').map(formatPayment);

    if (q.format === 'map') {
      const mapRes: Record<string, ReturnType<typeof formatPayment>> = {};
      for (const item of formattedList) {
        mapRes[item.id] = item;
      }
      return reply.send(mapRes);
    }

    return reply.send(formattedList);
  });

  // ── GET /api/payments/:id ───────────────────────────────────────────────────
  fastify.get('/payments/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const res = await query<RawPaymentRow>(
      `SELECT p.*, pt.full_name AS patient_name
       FROM payments p
       LEFT JOIN patients pt ON p.patient_id = pt.id
       WHERE p.id = $1`,
      [id]
    );
    if (res.rows.length === 0) {
      return reply.status(404).send({ error: 'NotFound', message: `Payment '${id}' not found` });
    }
    return reply.send(formatPayment(res.rows[0]));
  });

  // ── POST /api/payments ──────────────────────────────────────────────────────
  fastify.post('/payments', async (request, reply) => {
    const body = request.body as Record<string, any>;
    const paymentId = body.id || `pay_${randomUUID()}`;
    const patientId = body.patientId;
    const amount = String(body.amount);
    const checkoutAt = body.checkoutAt == null ? undefined : new Date(body.checkoutAt);
    if (checkoutAt && (!Number.isFinite(checkoutAt.getTime()) || (body.type !== 'refund' && body.collectOutstanding !== true))) {
      throw httpError(400, 'Checkout context requires a refund or outstanding collection');
    }
    const decimal = (value: unknown) => Number(value).toFixed(2);
    const trimmedTx = typeof body.transactionId === 'string' && body.transactionId.trim().length > 0
      ? body.transactionId.trim()
      : null;
    const trimmedReceipt = typeof body.receiptNumber === 'string' && body.receiptNumber.trim().length > 0
      ? body.receiptNumber.trim()
      : null;
    const fingerprint = createHash('sha256').update(JSON.stringify({
      patientId, amount: decimal(amount), cycleId: body.cycleId || null, type: body.type || 'payment',
      totalAmount: decimal(body.totalAmount ?? amount), paidAmount: decimal(body.paidAmount ?? amount), pendingAmount: decimal(body.pendingAmount ?? 0),
      paymentStatus: body.paymentStatus || 'Paid', method: body.method || 'cash', date: body.date != null ? new Date(body.date).getTime() : null,
      ...(body.collectOutstanding === true ? { collectOutstanding: true } : {}),
      ...(checkoutAt ? { checkoutAt: checkoutAt.getTime() } : {}),
      receiptNumber: trimmedReceipt, checkNumber: body.checkNumber || null, bankName: body.bankName || null,
      transactionId: trimmedTx, source: body.source || 'manual', notes: body.notes || null,
    })).digest('hex');
    const reuse = (existing: RawPaymentRow, patientName: string) => {
      if (existing.request_fingerprint !== fingerprint) throw httpError(409, 'This reference or payment ID is already recorded for another payment. Enter the new transfer\'s UTR / UPI reference.');
      return formatPayment({ ...existing, patient_name: patientName } as RawPaymentRow);
    };

    if (!patientId) {
      return reply.status(400).send({ error: 'BadRequest', message: 'patientId is required' });
    }

    const client = await getClient();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('app.operator_uid',$1,true),set_config('app.payment_reason',$2,true)", [request.user!.id, String((request.body as any)?.reason ?? request.method + ' payment')]);
      // Serialize a patient's balance changes and duplicate transaction checks.
      const patient = await client.query<LockedPatient>('SELECT * FROM patients WHERE id=$1 FOR UPDATE', [patientId]);
      if (!patient.rowCount) throw httpError(409, 'Patient not found');

      // Idempotency check: If an explicit paymentId or transactionId already exists, return existing
      if (body.id) {
        const existing = await client.query<RawPaymentRow>('SELECT * FROM payments WHERE id = $1', [body.id]);
        if (existing.rows.length > 0) {
          const response = { ...reuse(existing.rows[0], (patient.rows[0] as any).full_name), resultingBalances: (await projectBilling(client, patient.rows[0])).balances };
          await client.query('COMMIT');
          return reply.status(200).send(response);
        }
      }

      if (trimmedTx) {
        const existingTx = await client.query<RawPaymentRow>(
          'SELECT * FROM payments WHERE patient_id = $1 AND transaction_id = $2',
          [patientId, trimmedTx]
        );
        if (existingTx.rows.length > 0) {
          const response = { ...reuse(existingTx.rows[0], (patient.rows[0] as any).full_name), resultingBalances: (await projectBilling(client, patient.rows[0])).balances };
          await client.query('COMMIT');
          return reply.status(200).send(response);
        }
      }

      // Pay Now/Pay Remaining collects only the currently owed balance. Other
      // established receipt workflows may intentionally record an advance.
      // Check after idempotency so replaying a committed payment still succeeds
      // when that payment has already reduced the outstanding amount to zero.
      if (checkoutAt && body.type === 'refund') {
        const current = patient.rows[0] as any;
        if (current.status === 'discharged' || body.cycleId !== String(new Date(current.admission_date).getTime()))
          throw httpError(409, 'Checkout refund must belong to the active admission');
        if (checkoutAt < new Date(current.admission_date)) throw httpError(400, 'Checkout cannot precede admission');
        const placements = (await client.query("SELECT admission_date FROM stays WHERE patient_id=$1 AND status='active'", [patientId])).rows;
        if (!placements.length || placements.some(s => checkoutAt < new Date(s.admission_date)))
          throw httpError(409, 'Reconcile the current placement before recording a checkout refund');
      }
      if (body.collectOutstanding === true) {
        if ((body.type || 'payment') !== 'payment') throw httpError(400, 'Outstanding collection must be a payment');
        if (checkoutAt && (checkoutAt.getTime() > Date.now() || body.cycleId !== String(new Date(patient.rows[0].admission_date).getTime())))
          throw httpError(409, 'Collection must belong to the active admission and cannot use a future checkout');
        const projection = await projectBilling(client, patient.rows[0]);
        const cycle = receiptCycle({ cycle_id: body.cycleId }, patient.rows[0], projection.stays, 'new');
        if (cycle == null) throw httpError(409, 'Select the admission cycle before collecting payment');
        if (checkoutAt && (!['active', 'paid'].includes(String((patient.rows[0] as any).status).toLowerCase()) ||
            !projection.stays.some(s => s.status === 'active' && stayCycle(s, patient.rows[0]) === cycle)))
          throw httpError(409, 'Verify the active admission and placement before collecting an extension balance');
        const balance = projection.balances[cycle];
        // The quote and the current server-time projection must both authorize
        // the amount; a stale quote cannot authorize extra collection.
        const quoted = checkoutAt ? await projectBilling(client, patient.rows[0], { checkoutAt }) : projection;
        const quotedBalance = quoted.balances[cycle];
        if (quotedBalance?.reconciliationRequired) throw httpError(409, 'Reconcile receipt allocations, admission identities and invoice evidence for this admission before collecting an outstanding balance');
        if (!quotedBalance || cents(amount) > cents(quotedBalance.due)) throw httpError(409, 'Payment exceeds the quoted outstanding balance. Refresh the bill before collecting payment.');
        if (balance?.reconciliationRequired) throw httpError(409, 'Reconcile receipt allocations, admission identities and invoice evidence for this admission before collecting an outstanding balance');
        if (!balance || cents(amount) > cents(balance.due)) throw httpError(409, 'Payment exceeds the current outstanding balance. Refresh the bill before collecting payment.');
      }

      const paymentDate = body.date != null ? new Date(body.date) : new Date();
      // Establish a whole-receipt association once at creation. A later rejoin
      // must not turn an already established single-cycle receipt ambiguous.
      const allocationProjection = await projectBilling(client, patient.rows[0]);
      const allocatedCycle = receiptCycle({ cycle_id: body.cycleId }, patient.rows[0], allocationProjection.stays, 'new');
      if (allocatedCycle != null && !allocationProjection.balances[allocatedCycle])
        throw httpError(409, 'Payment does not belong to a known admission');

      const insertRes = await client.query<RawPaymentRow>(
        `INSERT INTO payments (
          id, patient_id, cycle_id, type, amount, total_amount, paid_amount,
          pending_amount, payment_status, method, payment_date, receipt_number,
          check_number, bank_name, transaction_id, source, notes, request_fingerprint, created_at, updated_at
        ) VALUES (
          $1, $2, $3, $4, $5, $6, $7,
          $8, $9, $10, $11, $12,
          $13, $14, $15, $16, $17, $18, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        ) RETURNING *`,
        [
          paymentId,
          patientId,
          allocatedCycle,
          body.type || 'payment',
          amount,
          body.totalAmount ?? amount,
          body.paidAmount ?? amount,
          body.pendingAmount ?? 0,
          body.paymentStatus || 'Paid',
          body.method || 'cash',
          paymentDate,
          trimmedReceipt,
          body.checkNumber || null,
          body.bankName || null,
          trimmedTx,
          body.source || 'manual',
          body.notes || null,
          fingerprint,
        ]
      );

      const balances = await applyPaymentDelta(client, patient.rows[0], null, insertRes.rows[0], body.type === 'refund' ? checkoutAt : undefined);

      await client.query('COMMIT');
      const rowToFormat = {
        ...insertRes.rows[0],
        patient_name: (patient.rows[0] as any).full_name,
      };
      return reply.status(201).send({ ...formatPayment(rowToFormat), resultingBalances: balances });
    } catch (err: unknown) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  });

  // ── PUT/PATCH /api/payments/:id ─────────────────────────────────────────────
  const updatePaymentHandler = async (request: any, reply: any) => {
    const { id } = request.params as { id: string };
    const body = (request.body as Record<string, any>) || {};
    const client = await getClient();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('app.operator_uid',$1,true),set_config('app.payment_reason',$2,true)", [request.user!.id, String((request.body as any)?.reason ?? request.method + ' payment')]);
      const locked = await lockPayment(client, id);
      if (!locked) {
        await client.query('ROLLBACK');
        return reply.status(404).send({ error: 'NotFound', message: `Payment '${id}' not found` });
      }
      const existing = locked.payment;
      if (Object.hasOwn(body, 'cycleId') && body.cycleId !== existing.cycle_id && request.user!.role !== 'admin')
        throw httpError(403, 'Admission allocation corrections require an administrator');
      if (Object.hasOwn(body, 'cycleId') && body.cycleId !== existing.cycle_id &&
          (typeof body.reason !== 'string' || body.reason.trim().length < 10))
        throw httpError(409, 'Allocation correction requires a reason describing the supporting evidence');
      if (('patientId' in body && body.patientId !== existing.patient_id) || ('id' in body && body.id !== id)) throw httpError(400, 'Payment id and patientId are immutable');
      if ('type' in body && body.type !== existing.type) throw httpError(400, 'Payment type is immutable');
      const amount = body.amount != null ? cents(body.amount) : cents(existing.amount);
      if (amount === 0 || (existing.type === 'refund' ? amount >= 0 : amount <= 0)) throw httpError(400, 'Payments must be positive and refunds negative');
      const nextTransactionId = 'transactionId' in body
        ? typeof body.transactionId === 'string' && body.transactionId.trim().length > 0
          ? body.transactionId.trim()
          : null
        : existing.transaction_id;
      // Migration 009 permits historical split receipts sharing a reference.
      // Preserve those identities on ordinary edits; reject a newly assigned
      // reference that would collide with another ledger entry.
      if (nextTransactionId != null && nextTransactionId !== existing.transaction_id) {
        const conflict = await client.query(
          'SELECT id FROM payments WHERE patient_id=$1 AND transaction_id=$2 AND id<>$3 LIMIT 1',
          [existing.patient_id, nextTransactionId, id],
        );
        if (conflict.rowCount) throw httpError(409, 'Transaction reference already belongs to another payment for this patient');
      }
      const fields: [string, string, 'money' | 'date' | 'text'][] = [
        ['cycleId', 'cycle_id', 'text'], ['amount', 'amount', 'money'], ['totalAmount', 'total_amount', 'money'],
        ['paidAmount', 'paid_amount', 'money'], ['pendingAmount', 'pending_amount', 'money'], ['paymentStatus', 'payment_status', 'text'],
        ['method', 'method', 'text'], ['date', 'payment_date', 'date'], ['receiptNumber', 'receipt_number', 'text'],
        ['checkNumber', 'check_number', 'text'], ['bankName', 'bank_name', 'text'], ['transactionId', 'transaction_id', 'text'],
        ['source', 'source', 'text'], ['notes', 'notes', 'text'],
      ];
      const assignments: string[] = [];
      const values: unknown[] = [id];
      for (const [key, column, kind] of fields) {
        if (!(key in body) || (kind === 'money' && body[key] == null)) continue;
        const previous = (existing as any)[column];
        const value = kind === 'money'
          ? decimal(cents(body[key]))
          : kind === 'date'
            ? new Date(body[key])
            : key === 'transactionId' && typeof body[key] === 'string'
              ? body[key].trim() || null
              : body[key] === '' && ['receiptNumber', 'checkNumber', 'bankName'].includes(key)
                ? null
                : body[key];
        const same = kind === 'money' ? cents(value) === cents(previous) : kind === 'date' ? new Date(value as Date).getTime() === new Date(previous).getTime() : value === previous;
        if (same) continue;
        values.push(value); assignments.push(`${column}=$${values.length}`);
      }
      if (!assignments.length) {
        await client.query('COMMIT');
        return reply.send(formatPayment(existing));
      }
      const updated = await client.query<RawPaymentRow>(`UPDATE payments SET ${assignments.join(',')},updated_at=CURRENT_TIMESTAMP WHERE id=$1 RETURNING *`, values);
      await applyPaymentDelta(client, locked.patient, existing, updated.rows[0]);
      await client.query('COMMIT');
      return reply.send(formatPayment(updated.rows[0]));
    } catch (err: unknown) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  };
  fastify.put('/payments/:id', updatePaymentHandler);
  fastify.patch('/payments/:id', updatePaymentHandler);

  // ── DELETE /api/payments/:id ────────────────────────────────────────────────
  fastify.delete('/payments/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const client = await getClient();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('app.operator_uid',$1,true),set_config('app.payment_reason',$2,true)", [request.user!.id, String((request.body as any)?.reason ?? request.method + ' payment')]);
      const locked = await lockPayment(client, id);
      if (!locked) {
        await client.query('ROLLBACK');
        return reply.status(404).send({ error: 'NotFound', message: `Payment '${id}' not found` });
      }
      await client.query('DELETE FROM payments WHERE id=$1', [id]);
      await applyPaymentDelta(client, locked.patient, locked.payment, null);
      await client.query('COMMIT');
      return reply.send({ success: true, id });
    } catch (err: unknown) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  });
}
