import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import { randomUUID } from 'node:crypto';
import { getClient, query } from '../db/index.js';
import type { PoolClient } from 'pg';
import { authenticate, requireRoles } from '../middleware/auth.js';
import { z } from 'zod';

const id = z.string().min(1).max(64).regex(/^[A-Za-z0-9_-]+$/);
const optionalId = id.nullable().optional();
const name = z.string().trim().min(1).max(255);
const nonnegative = z.number().finite().nonnegative();
// Reject extra precision instead of allowing PostgreSQL to silently round an
// incoming ledger value; pass decimal strings unchanged to NUMERIC columns.
const money = z.union([
  z.string().regex(/^(?:0|[1-9]\d{0,9})(?:\.\d{1,2})?$/),
  z.number().finite().nonnegative().max(9999999999.99).refine((value) => Math.abs(value * 100 - Math.round(value * 100)) < 0.00001),
]);
const date = z.union([z.number().finite(), z.string().min(1)]).refine((value) => {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return false;
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}/.test(value)) {
    const day = new Date(`${value.slice(0, 10)}T00:00:00Z`);
    return !Number.isNaN(day.getTime()) && day.toISOString().slice(0, 10) === value.slice(0, 10);
  }
  return true;
});
const common = { id: id.optional() };
const optionalText = (max: number) => z.string().max(max).nullable().optional();
const paymentDetailsSchema = z.object({
  paymentMethod: z.string().min(1).max(32), paymentStatus: z.enum(['Paid', 'Pending', 'Partial']),
  paymentDate: date.nullable().optional(), chequeDate: date.nullable().optional(),
  paymentReferenceNumber: optionalText(128), bankName: optionalText(128), transactionId: optionalText(128),
  cashVoucherNumber: optionalText(128), receivedBy: optionalText(255), chequeNumber: optionalText(128),
  chequeClearanceStatus: optionalText(32), proofUrl: optionalText(512),
}).strict();
const vendorFields = ['gstNumber', 'notes'] as const;
const purchaseFields = ['paymentDetails'] as const;
const expenseFields = ['subcategory', 'itemName', 'vendorId', 'quantity', 'unit', 'unitPrice', 'paymentDetails'] as const;
const sponsorshipFields = ['sponsorPrefix', 'sponsorMobile', 'referencePrefix', 'referenceName', 'referenceMobile', 'occasion', 'honoreeName', 'paymentStatus', 'transactionRef', 'bookingStatus'] as const;
const salaryFields = ['role', 'paymentDetails'] as const;
const inventorySchema = z.object({ ...common, name, category: z.string().min(1).max(64).optional(), unit: z.string().min(1).max(32).optional(), minStockLevel: nonnegative.optional(), currentStock: nonnegative.optional() });
const vendorSchema = z.object({ ...common, name, contactPerson: z.string().max(255).optional(), phone: z.string().max(32).optional(), email: z.union([z.literal(''), z.string().email().max(255)]).optional(), address: z.string().optional(), category: z.string().min(1).max(64).optional(), gstNumber: z.string().max(64).optional(), notes: z.string().max(10000).optional() });
const purchaseSchema = z.object({ ...common, vendorId: optionalId, vendorName: name, itemId: optionalId, itemName: name, quantity: z.number().finite().positive(), unit: z.string().min(1).max(32).optional(), unitPrice: money, totalAmount: money, purchaseDate: date.optional(), invoiceNumber: z.string().max(64).optional(), notes: z.string().optional(), paymentDetails: paymentDetailsSchema.optional() });
const expenseSchema = z.object({ ...common, category: z.string().min(1).max(64).optional(), amount: money, paymentMethod: z.string().min(1).max(32).optional(), paidTo: z.string().max(255).optional(), expenseDate: date.optional(), description: z.string().optional(), receiptUrl: z.string().max(512).optional(), subcategory: optionalText(64), itemName: optionalText(255), vendorId: optionalId, quantity: nonnegative.nullable().optional(), unit: optionalText(32), unitPrice: money.nullable().optional(), paymentDetails: paymentDetailsSchema.optional() });
const sponsorshipSchema = z.object({ ...common, sponsorName: name, patientId: optionalId, patientName: name.nullable().optional(), amount: money, sponsorshipDate: date.optional(), paymentMethod: z.string().min(1).max(32).optional(), notes: z.string().optional(), sponsorPrefix: z.string().max(32).optional(), sponsorMobile: z.string().max(32).optional(), referencePrefix: z.string().max(32).optional(), referenceName: z.string().max(255).optional(), referenceMobile: z.string().max(32).optional(), occasion: z.string().max(128).optional(), honoreeName: optionalText(255), paymentStatus: z.enum(['Paid', 'Pending', 'Partial']).optional(), transactionRef: z.string().max(128).optional(), bookingStatus: z.enum(['Booked', 'Confirmed', 'Completed', 'Cancelled']).optional() });
const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const salarySchema = z.object({ ...common, staffId: z.string().min(1).max(128).nullable().optional(), employeeName: name, role: z.string().min(1).max(64), salaryMonth: z.string().refine(value => new RegExp(`^(${months.join('|')}) [1-9][0-9]{3}$`).test(value)), grossSalary: money, deductions: money, netSalary: money.optional(), paymentDetails: paymentDetailsSchema });

function formDetails(body: Record<string, unknown>, fields: readonly string[], userId: string, creating = false): Record<string, unknown> {
  const details = Object.fromEntries(fields.filter(field => body[field] !== undefined).map(field => [field, body[field]]));
  return { ...details, ...(creating ? { createdBy: userId, createdAt: Date.now() } : {}), updatedBy: userId, updatedAt: Date.now() };
}

function presentErp(row: Record<string, any>): Record<string, any> {
  const { details, ...columns } = row;
  const result = { ...(details ?? {}), ...columns };
  if (row.created_by != null) result.createdBy = row.created_by;
  if (row.updated_by != null) result.updatedBy = row.updated_by;
  if (row.created_at != null) result.createdAt = new Date(row.created_at).getTime();
  if (row.updated_at != null) result.updatedAt = new Date(row.updated_at).getTime();
  if (row.base_salary !== undefined) {
    result.employeeName = row.staff_name;
    result.staffId = row.staff_id;
    result.salaryMonth = `${months[row.month - 1]} ${row.year}`;
    result.grossSalary = row.base_salary;
    result.netSalary = row.net_salary;
  }
  return result;
}

function salaryAmounts(gross: string | number, deductions: string | number, suppliedNet?: string | number): string {
  const cents = (value: string | number) => BigInt(Math.round(Number(value) * 100));
  const net = cents(gross) - cents(deductions);
  if (net < 0n || suppliedNet !== undefined && cents(suppliedNet) !== net) throw Object.assign(new Error('Net salary must equal gross salary minus deductions and be nonnegative'), { statusCode: 400 });
  return `${net / 100n}.${(net % 100n).toString().padStart(2, '0')}`;
}

async function purchaseTransaction<T>(purchaseId: string, operation: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await getClient();
  try {
    await client.query('BEGIN');
    // Establish one lock order for retries and edits before taking item locks.
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`erp-purchase:${purchaseId}`]);
    const result = await operation(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function lockPurchaseItems(client: PoolClient, itemIds: (string | null | undefined)[]): Promise<void> {
  const ids = [...new Set(itemIds.filter((value): value is string => Boolean(value)))].sort();
  if (ids.length === 0) return;
  const locked = await client.query('SELECT id FROM inventory_items WHERE id = ANY($1::text[]) ORDER BY id FOR UPDATE', [ids]);
  if (locked.rowCount !== ids.length) throw Object.assign(new Error('Referenced inventory item not found'), { statusCode: 409 });
}

async function adjustPurchaseStock(client: PoolClient, itemId: string | null, delta: number, userId: string): Promise<void> {
  if (!itemId || delta === 0) return;
  await client.query(`UPDATE inventory_items SET current_stock = GREATEST(0, current_stock + $2::double precision),
    updated_by = $3, updated_at = CURRENT_TIMESTAMP WHERE id = $1`, [itemId, delta, userId]);
}

export async function erpRoutes(fastify: FastifyInstance, _opts: FastifyPluginOptions): Promise<void> {
  fastify.addHook('preHandler', authenticate);
  fastify.addHook('preHandler', async (request, reply) => {
    if (request.method !== 'GET') return requireRoles(request.routeOptions.url?.startsWith('/api/erp/salaries') ? ['admin'] : ['admin', 'staff'])(request, reply);
  });
  fastify.addHook('preSerialization', async (_request, _reply, payload) => {
    if (Array.isArray(payload)) return payload.map(row => row && typeof row === 'object' && 'id' in row ? presentErp(row) : row);
    return payload && typeof payload === 'object' && 'id' in payload ? presentErp(payload) : payload;
  });

  // ── Inventory ──────────────────────────────────────────────────────────────
  fastify.get('/erp/inventory', async (_req, reply) => {
    const res = await query('SELECT * FROM inventory_items ORDER BY name ASC');
    return reply.send(res.rows);
  });

  fastify.get('/erp/inventory/:id', async (req, reply) => {
    const { id: itemId } = req.params as { id: string };
    const res = await query('SELECT * FROM inventory_items WHERE id = $1', [itemId]);
    if (res.rows.length === 0) return reply.status(404).send({ error: 'NotFound', message: 'Inventory item not found' });
    return reply.send(res.rows[0]);
  });

  fastify.post('/erp/inventory', async (req, reply) => {
    const parsed = inventorySchema.safeParse(req.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid inventory record' });
    const body = parsed.data;
    const id = body.id || `inv_${randomUUID()}`;
    const user = req.user!;
    const res = await query(
      `INSERT INTO inventory_items (id, name, category, unit, min_stock_level, current_stock, created_by, updated_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $7) RETURNING *`,
      [id, body.name, body.category || 'General', body.unit || 'pcs', body.minStockLevel || 0, body.currentStock || 0, user.id]
    );
    return reply.status(201).send(res.rows[0]);
  });

  fastify.put('/erp/inventory/:id', async (req, reply) => {
    const { id: itemId } = req.params as { id: string };
    const existing = await query('SELECT * FROM inventory_items WHERE id = $1', [itemId]);
    if (existing.rows.length === 0) return reply.status(404).send({ error: 'NotFound', message: 'Inventory item not found' });
    const parsed = inventorySchema.partial().safeParse(req.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid inventory update' });
    const body = parsed.data;
    const user = req.user!;
    const res = await query(
      `UPDATE inventory_items SET
         name = COALESCE($2, name),
         category = COALESCE($3, category),
         unit = COALESCE($4, unit),
         min_stock_level = COALESCE($5, min_stock_level),
         current_stock = COALESCE($6, current_stock),
         updated_by = $7,
         updated_at = CURRENT_TIMESTAMP
       WHERE id = $1 RETURNING *`,
      [itemId, body.name ?? null, body.category ?? null, body.unit ?? null, body.minStockLevel ?? null, body.currentStock ?? null, user.id]
    );
    return reply.send(res.rows[0]);
  });

  fastify.delete('/erp/inventory/:id', async (req, reply) => {
    const { id: itemId } = req.params as { id: string };
    const res = await query('DELETE FROM inventory_items WHERE id = $1 RETURNING id', [itemId]);
    if (res.rows.length === 0) return reply.status(404).send({ error: 'NotFound', message: 'Inventory item not found' });
    return reply.send({ success: true, deletedId: itemId });
  });

  // ── Vendors ────────────────────────────────────────────────────────────────
  fastify.get('/erp/vendors', async (_req, reply) => {
    const res = await query('SELECT * FROM vendors ORDER BY name ASC');
    return reply.send(res.rows);
  });

  fastify.post('/erp/vendors', async (req, reply) => {
    const parsed = vendorSchema.safeParse(req.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid vendor record' });
    const body = parsed.data;
    const id = body.id || `ven_${randomUUID()}`;
    const res = await query(
      `INSERT INTO vendors (id, name, contact_person, phone, email, address, category, details)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb) RETURNING *`,
      [id, body.name, body.contactPerson || null, body.phone || null, body.email || null, body.address || null, body.category || 'General', formDetails(body, vendorFields, req.user!.id, true)]
    );
    return reply.status(201).send(res.rows[0]);
  });

  fastify.put('/erp/vendors/:id', async (req, reply) => {
    const { id: vendorId } = req.params as { id: string };
    const existing = await query('SELECT * FROM vendors WHERE id = $1', [vendorId]);
    if (existing.rows.length === 0) return reply.status(404).send({ error: 'NotFound', message: 'Vendor not found' });
    const parsed = vendorSchema.partial().safeParse(req.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid vendor update' });
    const body = parsed.data;
    const res = await query(
      `UPDATE vendors SET
         name = COALESCE($2, name),
         contact_person = COALESCE($3, contact_person),
         phone = COALESCE($4, phone),
         email = COALESCE($5, email),
         address = COALESCE($6, address),
         category = COALESCE($7, category),
         details = details || $8::jsonb,
         updated_at = CURRENT_TIMESTAMP
       WHERE id = $1 RETURNING *`,
      [vendorId, body.name ?? null, body.contactPerson ?? null, body.phone ?? null, body.email ?? null, body.address ?? null, body.category ?? null, formDetails(body, vendorFields, req.user!.id)]
    );
    return reply.send(res.rows[0]);
  });

  fastify.delete('/erp/vendors/:id', async (req, reply) => {
    const { id: vendorId } = req.params as { id: string };
    const res = await query('DELETE FROM vendors WHERE id = $1 RETURNING id', [vendorId]);
    if (res.rows.length === 0) return reply.status(404).send({ error: 'NotFound', message: 'Vendor not found' });
    return reply.send({ success: true, deletedId: vendorId });
  });

  // ── Purchases ──────────────────────────────────────────────────────────────
  fastify.get('/erp/purchases', async (_req, reply) => {
    const res = await query('SELECT * FROM purchases ORDER BY purchase_date DESC');
    return reply.send(res.rows);
  });

  fastify.post('/erp/purchases', async (req, reply) => {
    const parsed = purchaseSchema.safeParse(req.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid purchase record' });
    const body = parsed.data;
    const id = body.id || `pur_${randomUUID()}`;
    const user = req.user!;
    const record = await purchaseTransaction(id, async (client) => {
      await lockPurchaseItems(client, [body.itemId]);
      const res = await client.query(
      `INSERT INTO purchases (id, vendor_id, vendor_name, item_id, item_name, quantity, unit, unit_price, total_amount, purchase_date, invoice_number, notes, created_by, details)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14::jsonb) RETURNING *`,
      [
        id,
        body.vendorId || null,
        body.vendorName || 'Vendor',
        body.itemId || null,
        body.itemName || 'Item',
        body.quantity || 1,
        body.unit || 'pcs',
        body.unitPrice || 0,
        body.totalAmount || 0,
        body.purchaseDate !== undefined ? new Date(body.purchaseDate) : new Date(),
        body.invoiceNumber || null,
        body.notes || null,
        user.id,
        formDetails(body, purchaseFields, user.id, true),
      ]
      );
      await adjustPurchaseStock(client, body.itemId ?? null, body.quantity, user.id);
      return res.rows[0];
    });
    return reply.status(201).send(record);
  });

  fastify.put('/erp/purchases/:id', async (req, reply) => {
    const { id: purchaseId } = req.params as { id: string };
    const parsed = purchaseSchema.partial().safeParse(req.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid purchase update' });
    const body = parsed.data;
    const record = await purchaseTransaction(purchaseId, async (client) => {
      const existing = await client.query('SELECT * FROM purchases WHERE id = $1 FOR UPDATE', [purchaseId]);
      const previous = existing.rows[0];
      if (!previous) return null;
      const itemId = body.itemId === undefined ? previous.item_id : body.itemId;
      const quantity = body.quantity ?? previous.quantity;
      await lockPurchaseItems(client, [previous.item_id, itemId]);
      const res = await client.query(
      `UPDATE purchases SET
         vendor_id = $2,
         vendor_name = COALESCE($3, vendor_name),
         item_id = $4,
         item_name = COALESCE($5, item_name),
         quantity = COALESCE($6, quantity),
         unit = COALESCE($7, unit),
         unit_price = COALESCE($8, unit_price),
         total_amount = COALESCE($9, total_amount),
         purchase_date = COALESCE($10, purchase_date),
         invoice_number = COALESCE($11, invoice_number),
         notes = COALESCE($12, notes),
         details = details || $13::jsonb
       WHERE id = $1 RETURNING *`,
      [
        purchaseId,
        body.vendorId === undefined ? previous.vendor_id : body.vendorId,
        body.vendorName ?? null,
        itemId,
        body.itemName ?? null,
        body.quantity ?? null,
        body.unit ?? null,
        body.unitPrice ?? null,
        body.totalAmount ?? null,
        body.purchaseDate !== undefined ? new Date(body.purchaseDate) : null,
        body.invoiceNumber ?? null,
        body.notes ?? null,
        formDetails(body, purchaseFields, req.user!.id),
      ]
      );
      if (previous.item_id === itemId) {
        await adjustPurchaseStock(client, itemId, quantity - previous.quantity, req.user!.id);
      } else {
        await adjustPurchaseStock(client, previous.item_id, -previous.quantity, req.user!.id);
        await adjustPurchaseStock(client, itemId, quantity, req.user!.id);
      }
      return res.rows[0];
    });
    if (!record) return reply.status(404).send({ error: 'NotFound', message: 'Purchase not found' });
    return reply.send(record);
  });

  fastify.delete('/erp/purchases/:id', async (req, reply) => {
    const { id: purchaseId } = req.params as { id: string };
    const removed = await purchaseTransaction(purchaseId, async (client) => {
      const existing = await client.query('SELECT * FROM purchases WHERE id = $1 FOR UPDATE', [purchaseId]);
      const previous = existing.rows[0];
      if (!previous) return false;
      await lockPurchaseItems(client, [previous.item_id]);
      await client.query('DELETE FROM purchases WHERE id = $1', [purchaseId]);
      await adjustPurchaseStock(client, previous.item_id, -previous.quantity, req.user!.id);
      return true;
    });
    if (!removed) return reply.status(404).send({ error: 'NotFound', message: 'Purchase not found' });
    return reply.send({ success: true, deletedId: purchaseId });
  });

  // ── Expenses ───────────────────────────────────────────────────────────────
  fastify.get('/erp/expenses', async (_req, reply) => {
    const res = await query('SELECT * FROM expense_entries ORDER BY expense_date DESC');
    return reply.send(res.rows);
  });

  fastify.post('/erp/expenses', async (req, reply) => {
    const parsed = expenseSchema.safeParse(req.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid expense record' });
    const body = parsed.data;
    const id = body.id || `exp_${randomUUID()}`;
    const user = req.user!;
    const res = await query(
      `INSERT INTO expense_entries (id, category, amount, payment_method, paid_to, expense_date, description, receipt_url, created_by, details)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb) RETURNING *`,
      [
        id,
        body.category || 'General',
        body.amount || 0,
        body.paymentMethod ?? body.paymentDetails?.paymentMethod ?? 'cash',
        body.paidTo || '',
        body.expenseDate !== undefined ? new Date(body.expenseDate) : new Date(),
        body.description || null,
        body.receiptUrl || null,
        user.id,
        formDetails(body, expenseFields, user.id, true),
      ]
    );
    return reply.status(201).send(res.rows[0]);
  });

  fastify.put('/erp/expenses/:id', async (req, reply) => {
    const { id: expenseId } = req.params as { id: string };
    const existing = await query('SELECT * FROM expense_entries WHERE id = $1', [expenseId]);
    if (existing.rows.length === 0) return reply.status(404).send({ error: 'NotFound', message: 'Expense not found' });
    const parsed = expenseSchema.partial().safeParse(req.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid expense update' });
    const body = parsed.data;
    const res = await query(
      `UPDATE expense_entries SET
         category = COALESCE($2, category),
         amount = COALESCE($3, amount),
         payment_method = COALESCE($4, payment_method),
         paid_to = COALESCE($5, paid_to),
         expense_date = COALESCE($6, expense_date),
         description = COALESCE($7, description),
         receipt_url = COALESCE($8, receipt_url),
         details = details || $9::jsonb
       WHERE id = $1 RETURNING *`,
      [
        expenseId,
        body.category ?? null,
        body.amount ?? null,
        body.paymentMethod ?? body.paymentDetails?.paymentMethod ?? null,
        body.paidTo ?? null,
        body.expenseDate !== undefined ? new Date(body.expenseDate) : null,
        body.description ?? null,
        body.receiptUrl ?? null,
        formDetails(body, expenseFields, req.user!.id),
      ]
    );
    return reply.send(res.rows[0]);
  });

  fastify.delete('/erp/expenses/:id', async (req, reply) => {
    const { id: expenseId } = req.params as { id: string };
    const res = await query('DELETE FROM expense_entries WHERE id = $1 RETURNING id', [expenseId]);
    if (res.rows.length === 0) return reply.status(404).send({ error: 'NotFound', message: 'Expense not found' });
    return reply.send({ success: true, deletedId: expenseId });
  });

  // ── Salaries ───────────────────────────────────────────────────────────────
  fastify.get('/erp/salaries', async (_req, reply) => {
    const res = await query('SELECT * FROM salaries ORDER BY year DESC, month DESC');
    return reply.send(res.rows);
  });

  fastify.post('/erp/salaries', async (req, reply) => {
    const parsed = salarySchema.safeParse(req.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid salary record' });
    const body = parsed.data;
    const salaryId = body.id ?? `sal_${randomUUID()}`;
    const [monthName, year] = body.salaryMonth.split(' ');
    const net = salaryAmounts(body.grossSalary, body.deductions, body.netSalary);
    const payment = body.paymentDetails;
    const res = await query(`INSERT INTO salaries (id,staff_id,staff_name,month,year,base_salary,deductions,net_salary,payment_date,payment_method,status,details)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb) RETURNING *`,
    [salaryId, body.staffId ?? null, body.employeeName, months.indexOf(monthName) + 1, Number(year), body.grossSalary,
      body.deductions, net, payment.paymentDate == null ? null : new Date(payment.paymentDate), payment.paymentMethod,
      payment.paymentStatus, formDetails(body, salaryFields, req.user!.id, true)]);
    return reply.status(201).send(res.rows[0]);
  });

  fastify.put('/erp/salaries/:id', async (req, reply) => {
    const { id: salaryId } = req.params as { id: string };
    const parsed = salarySchema.partial().safeParse(req.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid salary update' });
    const body = parsed.data;
    const record = await purchaseTransaction(`salary:${salaryId}`, async (client) => {
      const previous = (await client.query('SELECT * FROM salaries WHERE id=$1 FOR UPDATE', [salaryId])).rows[0];
      if (!previous) return null;
      const gross = body.grossSalary ?? previous.base_salary;
      const deductions = body.deductions ?? previous.deductions;
      const financialEdit = body.grossSalary !== undefined || body.deductions !== undefined || body.netSalary !== undefined;
      const net = financialEdit ? salaryAmounts(gross, deductions, body.netSalary) : previous.net_salary;
      const [monthName, year] = (body.salaryMonth ?? `${months[previous.month - 1]} ${previous.year}`).split(' ');
      const payment = body.paymentDetails;
      const result = await client.query(`UPDATE salaries SET staff_id=$2,staff_name=$3,month=$4,year=$5,base_salary=$6,
        deductions=$7,net_salary=$8,payment_date=$9,payment_method=$10,status=$11,details=details || $12::jsonb
        WHERE id=$1 RETURNING *`,
      [salaryId, body.staffId === undefined ? previous.staff_id : body.staffId, body.employeeName ?? previous.staff_name,
        months.indexOf(monthName) + 1, Number(year), gross, deductions, net,
        payment === undefined ? previous.payment_date : payment.paymentDate == null ? null : new Date(payment.paymentDate),
        payment?.paymentMethod ?? previous.payment_method, payment?.paymentStatus ?? previous.status,
        formDetails(body, salaryFields, req.user!.id)]);
      return result.rows[0];
    });
    if (!record) return reply.status(404).send({ error: 'NotFound', message: 'Salary not found' });
    return reply.send(record);
  });

  fastify.delete('/erp/salaries/:id', async (req, reply) => {
    const { id: salaryId } = req.params as { id: string };
    const deleted = await query('DELETE FROM salaries WHERE id=$1 RETURNING id', [salaryId]);
    if (!deleted.rowCount) return reply.status(404).send({ error: 'NotFound', message: 'Salary not found' });
    return reply.send({ success: true, deletedId: salaryId });
  });

  // ── Sponsorships ───────────────────────────────────────────────────────────
  fastify.get('/erp/sponsorships', async (_req, reply) => {
    const res = await query('SELECT * FROM sponsorships ORDER BY sponsorship_date DESC');
    return reply.send(res.rows);
  });

  fastify.post('/erp/sponsorships', async (req, reply) => {
    const parsed = sponsorshipSchema.safeParse(req.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid sponsorship record' });
    const body = parsed.data;
    const id = body.id || `sp_${randomUUID()}`;
    const res = await query(
      `INSERT INTO sponsorships (id, sponsor_name, patient_id, patient_name, amount, sponsorship_date, payment_method, notes, details)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb) RETURNING *`,
      [
        id,
        body.sponsorName || 'Sponsor',
        body.patientId || null,
        body.patientName || null,
        body.amount || 0,
        body.sponsorshipDate !== undefined ? new Date(body.sponsorshipDate) : new Date(),
        body.paymentMethod || 'bank_transfer',
        body.notes || null,
        formDetails(body, sponsorshipFields, req.user!.id, true),
      ]
    );
    return reply.status(201).send(res.rows[0]);
  });

  fastify.put('/erp/sponsorships/:id', async (req, reply) => {
    const { id: sponsorshipId } = req.params as { id: string };
    const existing = await query('SELECT * FROM sponsorships WHERE id = $1', [sponsorshipId]);
    if (existing.rows.length === 0) return reply.status(404).send({ error: 'NotFound', message: 'Sponsorship not found' });
    const parsed = sponsorshipSchema.partial().safeParse(req.body);
    if (!parsed.success) return reply.status(400).send({ error: 'BadRequest', message: 'Invalid sponsorship update' });
    const body = parsed.data;
    const res = await query(
      `UPDATE sponsorships SET
         sponsor_name = COALESCE($2, sponsor_name),
         patient_id = COALESCE($3, patient_id),
         patient_name = COALESCE($4, patient_name),
         amount = COALESCE($5, amount),
         sponsorship_date = COALESCE($6, sponsorship_date),
         payment_method = COALESCE($7, payment_method),
         notes = COALESCE($8, notes),
         details = details || $9::jsonb
       WHERE id = $1 RETURNING *`,
      [
        sponsorshipId,
        body.sponsorName ?? null,
        body.patientId ?? null,
        body.patientName ?? null,
        body.amount ?? null,
        body.sponsorshipDate !== undefined ? new Date(body.sponsorshipDate) : null,
        body.paymentMethod ?? null,
        body.notes ?? null,
        formDetails(body, sponsorshipFields, req.user!.id),
      ]
    );
    return reply.send(res.rows[0]);
  });

  fastify.delete('/erp/sponsorships/:id', async (req, reply) => {
    const { id: sponsorshipId } = req.params as { id: string };
    const res = await query('DELETE FROM sponsorships WHERE id = $1 RETURNING id', [sponsorshipId]);
    if (res.rows.length === 0) return reply.status(404).send({ error: 'NotFound', message: 'Sponsorship not found' });
    return reply.send({ success: true, deletedId: sponsorshipId });
  });
}
