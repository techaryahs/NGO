import { FastifyRequest } from 'fastify';
import { z } from 'zod';

export function httpError(statusCode: number, message: string): Error & { statusCode: number } {
  return Object.assign(new Error(message), { statusCode });
}
const id = z.string().min(1).max(64);
const stayId = z.string().min(1).max(128);
const text = z.string().min(1).max(255);
const integer = z.number().int().nonnegative();
const date = z.union([z.string().min(1), z.number().finite()]).refine(value => {
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) return false;
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) return parsed.toISOString().slice(0, 10) === value;
  return true;
}, 'Invalid date');
const money = z.union([z.number().finite(), z.string()]).refine(value => /^\d{1,10}(\.\d{1,2})?$/.test(String(value)), 'Use a nonnegative decimal with at most two fractional digits');
const stayBillingUpdates = z.record(stayId, z.object({
  dailyRate: money.nullable().optional(), totalCost: money.optional(),
  cycleId: id.optional(), completedAt: date.optional(), billableDays: integer.optional(),
  billingSummary: z.record(z.unknown()).optional(),
}).strict());
const bed = z.object({ id: id.nullable().optional(), bedLabel: text.nullable().optional(), bedNumber: z.union([text, integer]).nullable().optional(), status: z.enum(['available', 'occupied', 'maintenance', 'cleaning', 'reserved']).nullable().optional(), currentPatientId: id.nullable().optional(), currentStayId: stayId.nullable().optional(), lastCleaned: date.nullable().optional() }).passthrough();
const room = z.object({ id: id.nullable().optional(), roomNumber: text, roomType: text, floor: integer.nullable().optional(), maxAttendants: integer.nullable().optional(), currentAttendants: integer.nullable().optional(), totalBeds: integer.nullable().optional(), occupiedBeds: integer.nullable().optional(), version: integer.nullable().optional(), expectedVersion: integer.nullable().optional(), beds: z.array(bed).nullable().optional(), expectedVacancyDate: date.nullable().optional() }).passthrough();
const patient = z.object({ id: id.nullable().optional(), fullName: text, dateOfBirth: date, gender: text, contactNumber: z.string(), emergencyContact: z.string(), emergencyContactName: z.string(), medicalCondition: z.string(), admissionDate: date, registrationNumber: id.nullable().optional(), attendants: z.array(z.object({ name: text }).passthrough()).nullable().optional(), bedIds: z.array(id).nullable().optional(), bedLabels: z.array(z.string()).nullable().optional() }).passthrough();
const stay = z.object({ id: stayId.nullable().optional(), patientId: id, roomId: id, bedId: id.nullable().optional(), durationDays: z.number().int().positive().nullable().optional(), admissionDate: date.nullable().optional(), expectedDischargeDate: date.nullable().optional(), expiryDate: date.nullable().optional(), completedAt: date.nullable().optional(), status: z.enum(['active', 'completed', 'cancelled']).nullable().optional() }).passthrough();
const registerStay = stay.partial({ patientId: true });
const registerAttendanceItem = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  kind: z.enum(['attendance', 'attendant_attendance']).default('attendance'),
  payload: z.record(z.unknown()).default({}),
});
const registerPatient = patient.extend({
  stays: z.array(registerStay).optional(),
  initialAttendance: z.array(registerAttendanceItem).optional(),
}).passthrough();
const transferPatient = z.object({
  requestId: stayId, expectedStayIds: z.array(stayId).min(1), roomId: id,
  roomNumber: text, roomType: text, bedId: id.nullable().optional(),
  shiftedAt: date, exitDate: date.nullable().optional(),
});
const signedPaymentMoney = z.union([z.number().finite(), z.string()]).refine(value => /^-?\d{1,10}(\.\d{1,2})?$/.test(String(value)), 'Use a decimal with at most two fractional digits');
const paymentDate = date.refine(value => {
  if (typeof value !== 'string') return true;
  const calendarDate = value.match(/^(\d{4}-\d{2}-\d{2})(?:T|$)/)?.[1];
  if (!calendarDate) return true;
  const parsed = new Date(`${calendarDate}T00:00:00Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === calendarDate;
}, 'Invalid calendar date');
const paymentFields = z.object({
  id: id.nullable().optional(), patientId: id, cycleId: id.nullable().optional(),
  transactionId: z.string().max(128).nullable().optional(), amount: signedPaymentMoney,
  totalAmount: signedPaymentMoney.nullable().optional(), paidAmount: signedPaymentMoney.nullable().optional(), pendingAmount: signedPaymentMoney.nullable().optional(),
  type: z.enum(['payment', 'refund']).nullable().optional(), date: paymentDate.nullable().optional(),
  method: z.string().min(1).max(32).optional(), receiptNumber: z.string().max(64).nullable().optional(),
  checkNumber: z.string().max(64).nullable().optional(), bankName: z.string().max(128).nullable().optional(),
  paymentStatus: z.string().min(1).max(32).optional(), source: z.string().min(1).max(32).optional(), notes: z.string().nullable().optional(),
}).passthrough();
const payment = paymentFields.refine(x => Boolean(x.id || x.transactionId?.trim()), 'A stable id or transactionId is required for safe retries')
  .refine(x => x.type === 'refund' ? Number(x.amount) < 0 : Number(x.amount) > 0, 'Payments must be positive and refunds negative');

/** Validate inputs without stripping legacy model fields. */
export async function validateDomainRequest(request: FastifyRequest): Promise<void> {
  const path = request.routeOptions.url ?? '';
  const writing = ['POST', 'PUT', 'PATCH'].includes(request.method);
  let schema: z.ZodTypeAny | undefined;
  if (writing) {
    if (path === '/api/rooms') schema = room;
    else if (path === '/api/rooms/:id') schema = room.partial();
    else if (path === '/api/rooms/:id/beds' || path === '/api/rooms/:id/beds/:bedId') schema = bed;
    else if (path === '/api/patients') schema = patient;
    else if (path === '/api/patients/register') schema = registerPatient;
    else if (path === '/api/patients/:id/transfer') schema = transferPatient;
    else if (path === '/api/patients/:id') schema = patient.partial();
    else if (path === '/api/stays') schema = stay;
    else if (path === '/api/stays/batch') schema = z.object({ stays: z.array(stay).min(1) });
    else if (path === '/api/stays/:id') schema = stay.partial();
    else if (path === '/api/payments') schema = payment;
    else if (path === '/api/payments/:id') schema = paymentFields.partial();
  }
  if (schema) {
    const parsed = schema.safeParse(request.body);
    if (!parsed.success) throw httpError(400, `Invalid request: ${parsed.error.issues.map(i => `${i.path.join('.')}: ${i.message}`).join('; ')}`);
    // Validate additional shared date/money fields even in partial updates.
    const body = request.body as Record<string, unknown>;
    if (body.stayBillingUpdates !== undefined &&
      (path !== '/api/patients/:id' || !stayBillingUpdates.safeParse(body.stayBillingUpdates).success)) {
      throw httpError(400, 'Invalid stay billing updates');
    }
    for (const key of ['expectedVersion', 'version']) if (body[key] != null && !integer.safeParse(body[key]).success) throw httpError(400, `Invalid ${key}`);
    for (const [key, value] of Object.entries(body)) {
      if (value == null) continue;
      if ((key.endsWith('Date') || key === 'approvedDate') && !date.safeParse(value).success) throw httpError(400, `Invalid ${key}`);
      const fieldMoney = path.startsWith('/api/payments') && key === 'paidAmount' ? signedPaymentMoney : money;
      if (/^(totalPaidAmount|currentDueAmount|refundDueAmount|totalRefundDueAmount|totalRefundedAmount|advanceBilledAmount|billingAmountOverride|attendanceCharges|dailyRate|longStayDailyRate|costOverride|totalCost|baseCost|extraAttendantCost|paidAmount|pendingAmount)$/.test(key) && !fieldMoney.safeParse(value).success) throw httpError(400, `Invalid ${key}`);
    }
  }
  if (request.method === 'GET' && ['/api/patients', '/api/payments'].includes(path)) {
    const result = z.object({ limit: z.coerce.number().int().min(1).max(5000).optional(), offset: z.coerce.number().int().nonnegative().optional(), floor: z.coerce.number().int().optional() }).passthrough().safeParse(request.query);
    if (!result.success) throw httpError(400, 'Invalid pagination or floor');
  }
}
