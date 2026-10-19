import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import { getClient, query } from '../db/index.js';
import { authenticate, requireRoles } from '../middleware/auth.js';
import { httpError } from '../validation.js';
import { formatPayment } from './payments.js';
import { attendantId } from '../db/identifiers.js';
import { formatStay, insertStayWithClient, RawStayRow } from './stays.js';
import { refreshRoomOccupancy } from '../db/occupancy.js';
import { collectionPage, cursorDateSql, parseCollectionCursor } from '../pagination.js';
import { createHash } from 'node:crypto';

function registrationFingerprint(body: Record<string, any>): string {
  return createHash('sha256').update(JSON.stringify({
    fullName: String(body.fullName).trim(), dateOfBirth: toEpochMs(body.dateOfBirth),
    gender: body.gender, contactNumber: body.contactNumber,
    admissionDate: toEpochMs(body.admissionDate),
  })).digest('hex');
}

interface RawPatientRow {
  registration_fingerprint?: string | null;
  cursor_date?: string;
  version: number;
  id: string;
  full_name: string;
  search_key: string | null;
  date_of_birth: Date | string;
  age: number | null;
  gender: string;
  contact_number: string;
  emergency_contact: string;
  emergency_contact_name: string;
  medical_condition: string;
  allergies: string | null;
  blood_type: string | null;
  admission_date: Date | string;
  status: string;
  discharge_date: Date | string | null;
  exit_date: Date | string | null;
  room_id: string | null;
  room_number: string | null;
  floor: number | null;
  bed_ids: any;
  bed_labels: any;
  lobby: string | null;
  address: string | null;
  registration_number: string | null;
  registration_date: Date | string | null;
  pan_card_number: string | null;
  aadhaar_card_number: string | null;
  receipt_number: string | null;
  mode_of_payment: string | null;
  uti_number: string | null;
  payment_pending: boolean | null;
  payment_status: string | null;
  total_paid_amount: string | number;
  current_due_amount: string | number;
  refund_due_amount: string | number;
  total_refund_due_amount: string | number;
  total_refunded_amount: string | number;
  admission_balances: any;
  payment_due_date: Date | string | null;
  is_advance_period: boolean;
  advance_billed_amount: string | number;
  billing_amount_override: string | number | null;
  attendance_charges: string | number;
  total_present_days: number;
  total_absent_days: number;
  max_stay_days: number;
  extension_approved: boolean;
  extension_days: number;
  extension_reason: string | null;
  approved_by: string | null;
  approved_date: Date | string | null;
  photo_data_url: string | null;
  photo_ref: string | null;
  photo_file_name: string | null;
  notes: string | null;
  created_by: string;
  created_at: Date | string;
  updated_at: Date | string;
}

interface RawAttendantRow {
  id: string;
  patient_id: string;
  name: string;
  age: string | null;
  relation: string | null;
  aadhaar_number: string | null;
  mobile_number: string | null;
  is_emergency_contact: boolean;
  photo_ref: string | null;
  photo_data_url: string | null;
}

function toEpochMs(d: Date | string | number | null | undefined): number | null {
  if (d == null) return null;
  if (typeof d === 'number') return d;
  const parsed = new Date(d).getTime();
  return isNaN(parsed) ? null : parsed;
}

export function formatPatient(row: RawPatientRow, attendants: RawAttendantRow[] = [], payments: ReturnType<typeof formatPayment>[] = []) {
  return {
    id: row.id,
    version: row.version ?? 0,
    payments,
    fullName: row.full_name,
    searchKey: row.search_key || '',
    dateOfBirth: toEpochMs(row.date_of_birth) ?? 0,
    age: row.age ?? 0,
    gender: row.gender,
    contactNumber: row.contact_number,
    emergencyContact: row.emergency_contact,
    emergencyContactName: row.emergency_contact_name,
    medicalCondition: row.medical_condition,
    allergies: row.allergies,
    bloodType: row.blood_type,
    admissionDate: toEpochMs(row.admission_date) ?? 0,
    status: row.status,
    dischargeDate: toEpochMs(row.discharge_date),
    exitDate: toEpochMs(row.exit_date),
    roomId: row.room_id,
    roomNumber: row.room_number,
    floor: row.floor,
    bedIds: Array.isArray(row.bed_ids) ? row.bed_ids : [],
    bedLabels: Array.isArray(row.bed_labels) ? row.bed_labels : [],
    lobby: row.lobby,
    address: row.address,
    registrationNumber: row.registration_number,
    registrationDate: toEpochMs(row.registration_date),
    panCardNumber: row.pan_card_number,
    aadhaarCardNumber: row.aadhaar_card_number,
    receiptNumber: row.receipt_number,
    modeOfPayment: row.mode_of_payment,
    utiNumber: row.uti_number,
    paymentPending: Boolean(row.payment_pending),
    paymentStatus: row.payment_status || 'Paid',
    totalPaidAmount: parseFloat(String(row.total_paid_amount || 0)),
    currentDueAmount: parseFloat(String(row.current_due_amount || 0)),
    refundDueAmount: parseFloat(String(row.refund_due_amount || 0)),
    totalRefundDueAmount: parseFloat(String(row.total_refund_due_amount || 0)),
    totalRefundedAmount: parseFloat(String(row.total_refunded_amount || 0)),
    admissionBalances: typeof row.admission_balances === 'object' && row.admission_balances !== null ? row.admission_balances : {},
    paymentDueDate: toEpochMs(row.payment_due_date),
    isAdvancePeriod: Boolean(row.is_advance_period),
    advanceBilledAmount: parseFloat(String(row.advance_billed_amount || 0)),
    billingAmountOverride: row.billing_amount_override != null ? parseFloat(String(row.billing_amount_override)) : null,
    attendanceCharges: parseFloat(String(row.attendance_charges || 0)),
    totalPresentDays: row.total_present_days || 0,
    totalAbsentDays: row.total_absent_days || 0,
    maxStayDays: row.max_stay_days || 60,
    extensionApproved: Boolean(row.extension_approved),
    extensionDays: row.extension_days || 0,
    extensionReason: row.extension_reason,
    approvedBy: row.approved_by,
    approvedDate: toEpochMs(row.approved_date),
    photoDataUrl: row.photo_data_url,
    photoRef: row.photo_ref,
    photoFileName: row.photo_file_name,
    notes: row.notes,
    createdBy: row.created_by,
    createdAt: toEpochMs(row.created_at) ?? Date.now(),
    updatedAt: toEpochMs(row.updated_at) ?? Date.now(),
    attendants: attendants.map((att) => ({
      id: att.id,
      name: att.name,
      age: att.age,
      relation: att.relation,
      aadhaarNumber: att.aadhaar_number,
      mobileNumber: att.mobile_number,
      isEmergencyContact: Boolean(att.is_emergency_contact),
      photoRef: att.photo_ref,
      photoDataUrl: att.photo_data_url,
    })),
  };
}

export async function patientRoutes(fastify: FastifyInstance, _opts: FastifyPluginOptions): Promise<void> {
  fastify.addHook('preHandler', authenticate);

  // ── GET /api/patients ───────────────────────────────────────────────────────
  fastify.get('/patients', async (request, reply) => {
    const q = request.query as {
      status?: string;
      roomId?: string;
      floor?: string;
      search?: string;
      limit?: string;
      offset?: string;
      cursor?: string;
      format?: 'map' | 'array';
    };

    const conditions: string[] = [];
    const params: unknown[] = [];
    let idx = 1;

    if (q.status) {
      conditions.push(`p.status = $${idx++}`);
      params.push(q.status);
    }
    if (q.roomId) {
      conditions.push(`p.room_id = $${idx++}`);
      params.push(q.roomId);
    }
    if (q.floor) {
      conditions.push(`p.floor = $${idx++}`);
      params.push(parseInt(q.floor, 10));
    }
    if (q.search) {
      conditions.push(`(p.full_name ILIKE $${idx} OR p.search_key ILIKE $${idx} OR p.registration_number ILIKE $${idx})`);
      params.push(`%${q.search}%`);
      idx++;
    }

    const limit = q.limit ? parseInt(q.limit, 10) : 500;
    const offset = q.offset ? parseInt(q.offset, 10) : 0;
    const cursor = parseCollectionCursor(q.cursor, 'patients', offset);
    if (cursor) {
      conditions.push(`(p.admission_date, p.id) < ($${idx++}::timestamptz, $${idx++}::varchar)`);
      params.push(cursor.date, cursor.id);
    }
    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const patientSql = `
      SELECT p.*, ${cursorDateSql('p.admission_date')}
      FROM patients p
      ${whereClause}
      ORDER BY p.admission_date DESC, p.id DESC
      LIMIT ${limit + 1} OFFSET ${offset}
    `;

    const patientsRes = await query<RawPatientRow>(patientSql, params);
    const patients = collectionPage(reply, patientsRes.rows, limit, 'patients');
    if (patients.length === 0) {
      return reply.send(q.format === 'map' ? {} : []);
    }

    const patientIds = patients.map((p) => p.id);
    const attendantsRes = await query<RawAttendantRow>(
      `SELECT * FROM patient_attendants WHERE patient_id = ANY($1)`,
      [patientIds]
    );
    const paymentsRes = await query('SELECT * FROM payments WHERE patient_id = ANY($1) ORDER BY payment_date DESC', [patientIds]);

    const attendantsByPatient = new Map<string, RawAttendantRow[]>();
    for (const att of attendantsRes.rows) {
      const list = attendantsByPatient.get(att.patient_id) || [];
      list.push(att);
      attendantsByPatient.set(att.patient_id, list);
    }

    const paymentsByPatient = new Map<string, ReturnType<typeof formatPayment>[]>();
    for (const payment of paymentsRes.rows) {
      const list = paymentsByPatient.get(payment.patient_id) || [];
      list.push(formatPayment(payment as any));
      paymentsByPatient.set(payment.patient_id, list);
    }

    const formattedList = patients.map((row) =>
      formatPatient(row, attendantsByPatient.get(row.id) || [], paymentsByPatient.get(row.id) || [])
    );

    if (q.format === 'map') {
      const mapResult: Record<string, ReturnType<typeof formatPatient>> = {};
      for (const item of formattedList) {
        mapResult[item.id] = item;
      }
      return reply.send(mapResult);
    }

    return reply.send(formattedList);
  });

  // ── GET /api/patients/:id ───────────────────────────────────────────────────
  fastify.get('/patients/:id', async (request, reply) => {
    const { id } = request.params as { id: string };

    const patientRes = await query<RawPatientRow>('SELECT * FROM patients WHERE id = $1', [id]);
    if (patientRes.rows.length === 0) {
      return reply.status(404).send({ error: 'NotFound', message: `Patient '${id}' not found` });
    }

    const attendantsRes = await query<RawAttendantRow>(
      'SELECT * FROM patient_attendants WHERE patient_id = $1',
      [id]
    );

    const paymentsRes = await query('SELECT * FROM payments WHERE patient_id=$1 ORDER BY payment_date DESC', [id]);
    return reply.send(formatPatient(patientRes.rows[0], attendantsRes.rows, paymentsRes.rows.map(payment => formatPayment(payment as any))));
  });

  // ── POST /api/patients ──────────────────────────────────────────────────────
  fastify.post('/patients', async (request, reply) => {
    const body = request.body as Record<string, any>;
    const patientId = body.id || `p_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    const user = request.user!;
    if (Array.isArray(body.payments) && body.payments.length) throw httpError(400, 'Record payments using the payments endpoint');

    const client = await getClient();
    try {
      await client.query('BEGIN');

      const insertPatientSql = `
        INSERT INTO patients (
          id, full_name, search_key, date_of_birth, age, gender,
          contact_number, emergency_contact, emergency_contact_name, medical_condition,
          allergies, blood_type, admission_date, status, discharge_date, exit_date,
          room_id, room_number, floor, bed_ids, bed_labels, lobby, address,
          registration_number, registration_date, pan_card_number, aadhaar_card_number,
          receipt_number, mode_of_payment, uti_number, payment_pending, payment_status,
          total_paid_amount, current_due_amount, refund_due_amount, total_refund_due_amount,
          total_refunded_amount, admission_balances, payment_due_date, is_advance_period,
          advance_billed_amount, billing_amount_override, attendance_charges, total_present_days,
          total_absent_days, max_stay_days, extension_approved, extension_days,
          extension_reason, approved_by, approved_date, photo_data_url, photo_ref,
          photo_file_name, notes, created_by, created_at, updated_at
        ) VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
          $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
          $21, $22, $23, $24, $25, $26, $27, $28, $29, $30,
          $31, $32, $33, $34, $35, $36, $37, $38, $39, $40,
          $41, $42, $43, $44, $45, $46, $47, $48, $49, $50,
          $51, $52, $53, $54, $55, $56, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        ) RETURNING *;
      `;

      const dob = new Date(body.dateOfBirth);
      const admissionDate = new Date(body.admissionDate);

      const patientValues = [
        patientId,
        body.fullName || 'Unnamed Patient',
        body.searchKey || (body.fullName ? String(body.fullName).toLowerCase() : null),
        dob,
        body.age != null ? parseInt(body.age, 10) : null,
        body.gender || 'Unknown',
        body.contactNumber || '',
        body.emergencyContact || '',
        body.emergencyContactName || '',
        body.medicalCondition || 'None stated',
        body.allergies || null,
        body.bloodType || null,
        admissionDate,
        body.status || 'active',
        body.dischargeDate != null ? new Date(body.dischargeDate) : null,
        body.exitDate != null ? new Date(body.exitDate) : null,
        body.roomId || null,
        body.roomNumber || null,
        body.floor != null ? parseInt(body.floor, 10) : null,
        JSON.stringify(body.bedIds || []),
        JSON.stringify(body.bedLabels || []),
        body.lobby || null,
        body.address || null,
        body.registrationNumber || null,
        body.registrationDate != null ? new Date(body.registrationDate) : null,
        body.panCardNumber || null,
        body.aadhaarCardNumber || null,
        body.receiptNumber || null,
        body.modeOfPayment || null,
        body.utiNumber || null,
        body.paymentPending != null ? Boolean(body.paymentPending) : false,
        body.paymentStatus || 'Paid',
        body.totalPaidAmount || 0,
        body.currentDueAmount || 0,
        body.refundDueAmount || 0,
        body.totalRefundDueAmount || 0,
        body.totalRefundedAmount || 0,
        JSON.stringify(body.admissionBalances || {}),
        body.paymentDueDate != null ? new Date(body.paymentDueDate) : null,
        body.isAdvancePeriod != null ? Boolean(body.isAdvancePeriod) : true,
        body.advanceBilledAmount || 0,
        body.billingAmountOverride != null ? body.billingAmountOverride : null,
        body.attendanceCharges || 0,
        body.totalPresentDays || 0,
        body.totalAbsentDays || 0,
        body.maxStayDays || 60,
        body.extensionApproved != null ? Boolean(body.extensionApproved) : false,
        body.extensionDays || 0,
        body.extensionReason || null,
        body.approvedBy || null,
        body.approvedDate != null ? new Date(body.approvedDate) : null,
        body.photoDataUrl || null,
        body.photoRef || null,
        body.photoFileName || null,
        body.notes || null,
        user.id,
      ];

      const insertedPatient = await client.query<RawPatientRow>(insertPatientSql, patientValues);

      // Insert attendants if provided
      const attendants: RawAttendantRow[] = [];
      if (Array.isArray(body.attendants)) {
        for (let i = 0; i < body.attendants.length; i++) {
          const att = body.attendants[i];
          const attId = attendantId(patientId, i);
          const attRes = await client.query<RawAttendantRow>(
            `INSERT INTO patient_attendants (
              id, patient_id, name, age, relation, aadhaar_number,
              mobile_number, is_emergency_contact, photo_ref, photo_data_url
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *`,
            [
              attId,
              patientId,
              att.name || 'Unnamed Attendant',
              att.age ? String(att.age) : null,
              att.relation || null,
              att.aadhaarNumber || null,
              att.mobileNumber || null,
              Boolean(att.isEmergencyContact),
              att.photoRef || null,
              att.photoDataUrl || null,
            ]
          );
          attendants.push(attRes.rows[0]);
        }
      }

      await client.query('COMMIT');
      return reply.status(201).send(formatPatient(insertedPatient.rows[0], attendants));
    } catch (err: unknown) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  });

  // ── POST /api/patients/register ─────────────────────────────────────────────
  // Atomic registration endpoint: inserts patient + attendants + initial
  // stays + bed allocations inside a single PostgreSQL
  // transaction. Handles retries idempotently without creating duplicate records.
  fastify.post('/patients/register', async (request, reply) => {
    const body = request.body as Record<string, any>;
    const patientId = body.id || `p_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    const user = request.user!;
    if (Array.isArray(body.payments) && body.payments.length) throw httpError(400, 'Record payments using the payments endpoint');

    const requestedStays: Record<string, any>[] = Array.isArray(body.stays) ? body.stays : [];
    const client = await getClient();
    try {
      await client.query('BEGIN');
      // A row lock cannot serialize two initial requests when the patient row
      // does not exist yet. Keep the same patient ID exclusive until commit.
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`patient-registration:${patientId}`]);

      const existingPatientRes = await client.query<RawPatientRow>(
        'SELECT * FROM patients WHERE id = $1 FOR UPDATE',
        [patientId]
      );
      const existingStaysRes = await client.query<RawStayRow>(
        "SELECT * FROM stays WHERE patient_id = $1 AND status = 'active' ORDER BY created_at, id FOR UPDATE",
        [patientId]
      );

      if (existingPatientRes.rows.length > 0) {
        const existing = existingPatientRes.rows[0];
        const fingerprint = existing.registration_fingerprint ?? registrationFingerprint(formatPatient(existing));
        if (registrationFingerprint(body) !== fingerprint) throw httpError(409, 'Patient ID already belongs to a different registration identity');
        // Compare the requested assignments as a multiset, consuming each
        // persisted stay once. Equal counts alone can hide a different bed or
        // stay, and a retry must never become an update of the patient's data.
        const unmatchedStays = [...existingStaysRes.rows];
        const matchesRegistration = requestedStays.length === unmatchedStays.length && requestedStays.every(requested => {
          const index = unmatchedStays.findIndex(existing =>
            (!requested.id || requested.id === existing.id) &&
            requested.roomId === existing.room_id &&
            (requested.bedId || null) === (existing.bed_id || null) &&
            (requested.admissionDate == null || toEpochMs(requested.admissionDate) === toEpochMs(existing.admission_date)) &&
            (requested.durationDays == null || requested.durationDays === existing.duration_days) &&
            (requested.cycleId == null || requested.cycleId === existing.cycle_id) &&
            (requested.status == null || requested.status === existing.status)
          );
          if (index < 0) return false;
          unmatchedStays.splice(index, 1);
          return true;
        });
        if (!matchesRegistration) throw httpError(409, 'Patient ID already exists with a different registration. Update admissions through the stay lifecycle.');

        const attRes = await client.query<RawAttendantRow>(
          'SELECT * FROM patient_attendants WHERE patient_id = $1',
          [patientId]
        );
        const paymentsRes = await client.query(
          'SELECT * FROM payments WHERE patient_id = $1 ORDER BY payment_date DESC',
          [patientId]
        );
        await client.query('COMMIT');
        const formattedPatient = formatPatient(
          existingPatientRes.rows[0],
          attRes.rows,
          paymentsRes.rows.map(p => formatPayment(p as any))
        );
        const formattedStays = existingStaysRes.rows.map(formatStay);
        return reply.status(200).send({
          ...formattedPatient,
          patient: formattedPatient,
          stays: formattedStays,
          stayIds: formattedStays.map(s => s.id),
          idempotentRetry: true,
        });
      }

      // Resolve or allocate registration number inside the transaction
      let regNumber: string | null = body.registrationNumber ? String(body.registrationNumber).trim() : null;
      if (regNumber) {
        const dupReg = await client.query(
          'SELECT id FROM patients WHERE LOWER(registration_number) = LOWER($1) AND id <> $2',
          [regNumber, patientId]
        );
        if (dupReg.rowCount) {
          throw httpError(409, `Registration number "${regNumber}" is already assigned to another patient.`);
        }
      } else if (existingPatientRes.rows[0]?.registration_number) {
        regNumber = existingPatientRes.rows[0].registration_number;
      } else {
        const counterRes = await client.query<{ current_value: string }>(
          `WITH max_reg AS (
             SELECT COALESCE(MAX(CASE WHEN registration_number ~ '^[0-9]+$' THEN registration_number::bigint ELSE 0 END), 0) AS max_val
             FROM patients
           )
           INSERT INTO system_counters (counter_name, current_value, updated_at)
           SELECT 'registrationNumber', GREATEST(1, max_val + 1), CURRENT_TIMESTAMP FROM max_reg
           ON CONFLICT (counter_name) DO UPDATE SET
             current_value = GREATEST(system_counters.current_value, (SELECT max_val FROM max_reg)) + 1,
             updated_at = CURRENT_TIMESTAMP
           RETURNING current_value`
        );
        regNumber = String(counterRes.rows[0].current_value);
      }

      const dob = new Date(body.dateOfBirth);
      const admissionDate = new Date(body.admissionDate);
      const hasStaysToCreate = requestedStays.length > 0;

      // When stays are provided, room/bed placement will be set authoritatively by insertStayWithClient.
      const initialRoomId = hasStaysToCreate ? null : (body.roomId || null);
      const initialRoomNumber = hasStaysToCreate ? null : (body.roomNumber || null);
      const initialFloor = hasStaysToCreate ? null : (body.floor != null ? parseInt(body.floor, 10) : null);
      const initialBedIds = hasStaysToCreate ? [] : (body.bedIds || []);
      const initialBedLabels = hasStaysToCreate ? [] : (body.bedLabels || []);
      const initialLobby = hasStaysToCreate ? null : (body.lobby || null);

      const insertPatientSql = `
        INSERT INTO patients (
          id, full_name, search_key, date_of_birth, age, gender,
          contact_number, emergency_contact, emergency_contact_name, medical_condition,
          allergies, blood_type, admission_date, status, discharge_date, exit_date,
          room_id, room_number, floor, bed_ids, bed_labels, lobby, address,
          registration_number, registration_date, pan_card_number, aadhaar_card_number,
          receipt_number, mode_of_payment, uti_number, payment_pending, payment_status,
          total_paid_amount, current_due_amount, refund_due_amount, total_refund_due_amount,
          total_refunded_amount, admission_balances, payment_due_date, is_advance_period,
          advance_billed_amount, billing_amount_override, attendance_charges, total_present_days,
          total_absent_days, max_stay_days, extension_approved, extension_days,
          extension_reason, approved_by, approved_date, photo_data_url, photo_ref,
          photo_file_name, notes, created_by, created_at, updated_at
        ) VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
          $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
          $21, $22, $23, $24, $25, $26, $27, $28, $29, $30,
          $31, $32, $33, $34, $35, $36, $37, $38, $39, $40,
          $41, $42, $43, $44, $45, $46, $47, $48, $49, $50,
          $51, $52, $53, $54, $55, $56, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        ) RETURNING *;
      `;

      const patientValues = [
        patientId,
        body.fullName || 'Unnamed Patient',
        body.searchKey || (body.fullName ? String(body.fullName).toLowerCase() : null),
        dob,
        body.age != null ? parseInt(body.age, 10) : null,
        body.gender || 'Unknown',
        body.contactNumber || '',
        body.emergencyContact || '',
        body.emergencyContactName || '',
        body.medicalCondition || 'None stated',
        body.allergies || null,
        body.bloodType || null,
        admissionDate,
        body.status || 'active',
        body.dischargeDate != null ? new Date(body.dischargeDate) : null,
        body.exitDate != null ? new Date(body.exitDate) : null,
        initialRoomId,
        initialRoomNumber,
        initialFloor,
        JSON.stringify(initialBedIds),
        JSON.stringify(initialBedLabels),
        initialLobby,
        body.address || null,
        regNumber,
        body.registrationDate != null ? new Date(body.registrationDate) : admissionDate,
        body.panCardNumber || null,
        body.aadhaarCardNumber || null,
        body.receiptNumber || null,
        body.modeOfPayment || null,
        body.utiNumber || null,
        body.paymentPending != null ? Boolean(body.paymentPending) : false,
        body.paymentStatus || 'Paid',
        body.totalPaidAmount || 0,
        body.currentDueAmount || 0,
        body.refundDueAmount || 0,
        body.totalRefundDueAmount || 0,
        body.totalRefundedAmount || 0,
        JSON.stringify(body.admissionBalances || {}),
        body.paymentDueDate != null ? new Date(body.paymentDueDate) : null,
        body.isAdvancePeriod != null ? Boolean(body.isAdvancePeriod) : true,
        body.advanceBilledAmount || 0,
        body.billingAmountOverride != null ? body.billingAmountOverride : null,
        body.attendanceCharges || 0,
        body.totalPresentDays || 0,
        body.totalAbsentDays || 0,
        body.maxStayDays || 60,
        body.extensionApproved != null ? Boolean(body.extensionApproved) : false,
        body.extensionDays || 0,
        body.extensionReason || null,
        body.approvedBy || null,
        body.approvedDate != null ? new Date(body.approvedDate) : null,
        body.photoDataUrl || null,
        body.photoRef || null,
        body.photoFileName || null,
        body.notes || null,
        user.id,
      ];

      await client.query<RawPatientRow>(insertPatientSql, patientValues);

      // Insert attendants only for this new registration in the same transaction.
      const attendants: RawAttendantRow[] = [];
      if (Array.isArray(body.attendants)) {
        for (let i = 0; i < body.attendants.length; i++) {
          const att = body.attendants[i];
          const attId = attendantId(patientId, i);
          const attRes = await client.query<RawAttendantRow>(
            `INSERT INTO patient_attendants (
              id, patient_id, name, age, relation, aadhaar_number,
              mobile_number, is_emergency_contact, photo_ref, photo_data_url
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *`,
            [
              attId,
              patientId,
              att.name || 'Unnamed Attendant',
              att.age ? String(att.age) : null,
              att.relation || null,
              att.aadhaarNumber || null,
              att.mobileNumber || null,
              Boolean(att.isEmergencyContact),
              att.photoRef || null,
              att.photoDataUrl || null,
            ]
          );
          attendants.push(attRes.rows[0]);
        }
      }

      await client.query('UPDATE patients SET registration_fingerprint=$2 WHERE id=$1', [patientId, registrationFingerprint(body)]);
      await client.query('SELECT id FROM rooms WHERE id=ANY($1::varchar[]) ORDER BY id FOR UPDATE', [requestedStays.map(s => s.roomId)]);
      // Create stays & allocate beds atomically in the same transaction
      const createdStayRows: RawStayRow[] = [];
      for (const stayItem of requestedStays) {
        const stayRow = await insertStayWithClient(
          client,
          { ...stayItem, patientId },
          user.id
        );
        createdStayRows.push(stayRow);
      }

      // Legacy clients may still send initialAttendance. Deliberately ignore it:
      // registration and planned stay dates are never actual attendance.

      const finalPatientRes = await client.query<RawPatientRow>(
        'SELECT * FROM patients WHERE id = $1',
        [patientId]
      );

      await client.query('COMMIT');
      const formattedPatient = formatPatient(finalPatientRes.rows[0], attendants);
      const formattedStays = createdStayRows.map(formatStay);
      return reply.status(201).send({
        ...formattedPatient,
        patient: formattedPatient,
        stays: formattedStays,
        stayIds: formattedStays.map(s => s.id),
      });
    } catch (err: unknown) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  });

  // A transfer is one admission mutation: destination conflicts roll back the
  // old stay closures, bed release and patient placement together.
  fastify.post('/patients/:id/transfer', async (request, reply) => {
    const { id } = request.params as { id: string };
    const body = request.body as Record<string, any>;
    const fingerprint = createHash('sha256').update(JSON.stringify([
      id, [...body.expectedStayIds].sort(), body.roomId, body.bedId ?? null,
      toEpochMs(body.shiftedAt), toEpochMs(body.exitDate),
    ])).digest('hex');
    const client = await getClient();
    try {
      await client.query('BEGIN');
      const patient = (await client.query<RawPatientRow>('SELECT * FROM patients WHERE id=$1 FOR UPDATE', [id])).rows[0];
      if (!patient) throw httpError(409, 'Patient no longer exists');
      const previous = (await client.query<RawStayRow>('SELECT * FROM stays WHERE id=$1', [body.requestId])).rows[0];
      if (previous && (previous.patient_id !== id || previous.patient_snapshot?.transferFingerprint !== fingerprint)) {
        throw httpError(409, 'Transfer request ID already used differently');
      }
      if (!previous) {
        const active = (await client.query<RawStayRow>("SELECT * FROM stays WHERE patient_id=$1 AND status='active' ORDER BY id", [id])).rows;
        if (patient.status === 'discharged' || JSON.stringify(active.map(s => s.id)) !== JSON.stringify([...body.expectedStayIds].sort())) {
          throw httpError(409, 'Patient placement changed; refresh before transferring');
        }
        const roomIds = [...new Set([...active.map(s => s.room_id), body.roomId])].sort();
        await client.query('SELECT id FROM rooms WHERE id=ANY($1::varchar[]) ORDER BY id FOR UPDATE', [roomIds]);
        await client.query("UPDATE stays SET status='completed',completed_at=$2,updated_at=CURRENT_TIMESTAMP WHERE patient_id=$1 AND status='active'", [id, new Date(body.shiftedAt)]);
        await client.query("UPDATE room_beds SET status='available',current_patient_id=NULL,current_stay_id=NULL,updated_at=CURRENT_TIMESTAMP WHERE current_stay_id=ANY($1::varchar[])", [body.expectedStayIds]);
        const attendants = (await client.query<RawAttendantRow>('SELECT * FROM patient_attendants WHERE patient_id=$1 ORDER BY id', [id])).rows;
        await insertStayWithClient(client, {
          id: body.requestId, patientId: id, roomId: body.roomId, roomType: body.roomType,
          roomNumber: body.roomNumber, bedId: body.bedId, admissionDate: body.shiftedAt,
          durationDays: 7, cycleId: String(toEpochMs(patient.admission_date)),
          attendantCount: attendants.length,
          attendantLabels: attendants.map(a => a.relation ? `${a.name} (${a.relation})` : a.name),
          patientSnapshot: { transferFingerprint: fingerprint, registrationNumber: patient.registration_number,
            admissionDate: toEpochMs(patient.admission_date), photoRef: patient.photo_ref,
            attendants: attendants.map(a => ({ name: a.name, relation: a.relation })) },
          notes: 'Room transfer',
        }, request.user!.id);
        await client.query('UPDATE patients SET exit_date=$2,billing_amount_override=NULL WHERE id=$1', [id, body.exitDate == null ? null : new Date(body.exitDate)]);
        for (const roomId of roomIds) await refreshRoomOccupancy(client, roomId);
      }
      const finalPatient = (await client.query<RawPatientRow>('SELECT * FROM patients WHERE id=$1', [id])).rows[0];
      const attendants = (await client.query<RawAttendantRow>('SELECT * FROM patient_attendants WHERE patient_id=$1', [id])).rows;
      const payments = (await client.query('SELECT * FROM payments WHERE patient_id=$1 ORDER BY payment_date DESC', [id])).rows;
      const stays = (await client.query<RawStayRow>('SELECT * FROM stays WHERE patient_id=$1 ORDER BY id', [id])).rows;
      await client.query('COMMIT');
      return reply.send({ patient: formatPatient(finalPatient, attendants, payments.map(p => formatPayment(p as any))), stays: stays.map(formatStay) });
    } catch (err) { await client.query('ROLLBACK'); throw err; }
    finally { client.release(); }
  });

  // ── PUT /api/patients/:id ───────────────────────────────────────────────────
  fastify.put('/patients/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    let body = request.body as Record<string, any>;

    const client = await getClient();
    try {
      await client.query('BEGIN');

      const existing = await client.query<RawPatientRow>('SELECT * FROM patients WHERE id = $1 FOR UPDATE', [id]);
      if (existing.rows.length === 0) {
        await client.query('ROLLBACK');
        return reply.status(404).send({ error: 'NotFound', message: `Patient '${id}' not found` });
      }

      const expectedVersion = body.expectedVersion ?? body.version;
      if (expectedVersion != null && expectedVersion !== existing.rows[0].version) throw httpError(409, 'Patient version mismatch');
      const financialFields = ['totalPaidAmount', 'currentDueAmount', 'refundDueAmount', 'totalRefundDueAmount', 'totalRefundedAmount', 'admissionBalances', 'stayBillingUpdates'];
      if (financialFields.some(key => Object.hasOwn(body, key)) && expectedVersion == null) throw httpError(409, 'Financial updates require expectedVersion from the current patient record');
      const activeStays = await client.query("SELECT id FROM stays WHERE patient_id=$1 AND status='active'", [id]);
      const before = formatPatient(existing.rows[0]);
      if (activeStays.rowCount && ['roomId', 'roomNumber', 'floor', 'bedIds', 'bedLabels'].some(key => Object.hasOwn(body, key) && JSON.stringify(body[key]) !== JSON.stringify(before[key as keyof typeof before]))) throw httpError(409, 'Change active assignments through the stay lifecycle');
      if (body.status === 'discharged' && activeStays.rowCount) {
        throw httpError(409, 'Complete active stays before discharging the patient');
      }
      // PUT historically acts as a partial update. Preserve omitted optional fields.
      body = { ...formatPatient(existing.rows[0]), ...body };
      if ((request.body as Record<string, unknown>).fullName && !Object.hasOwn(request.body as object, 'searchKey')) body.searchKey = String(body.fullName).toLowerCase();

      const updateSql = `
        UPDATE patients SET
          full_name = COALESCE($2, full_name),
          search_key = COALESCE($3, search_key),
          age = COALESCE($4, age),
          gender = COALESCE($5, gender),
          contact_number = COALESCE($6, contact_number),
          emergency_contact = COALESCE($7, emergency_contact),
          emergency_contact_name = COALESCE($8, emergency_contact_name),
          medical_condition = COALESCE($9, medical_condition),
          allergies = $10,
          blood_type = $11,
          status = COALESCE($12, status),
          discharge_date = $13,
          exit_date = $14,
          room_id = $15,
          room_number = $16,
          floor = $17,
          bed_ids = COALESCE($18, bed_ids),
          bed_labels = COALESCE($19, bed_labels),
          lobby = $20,
          address = $21,
          registration_number = COALESCE($22, registration_number),
          registration_date = $23,
          pan_card_number = $24,
          aadhaar_card_number = $25,
          receipt_number = $26,
          mode_of_payment = $27,
          uti_number = $28,
          payment_pending = COALESCE($29, payment_pending),
          payment_status = COALESCE($30, payment_status),
          total_paid_amount = COALESCE($31, total_paid_amount),
          current_due_amount = COALESCE($32, current_due_amount),
          refund_due_amount = COALESCE($33, refund_due_amount),
          total_refund_due_amount = COALESCE($34, total_refund_due_amount),
          total_refunded_amount = COALESCE($35, total_refunded_amount),
          admission_balances = COALESCE($36, admission_balances),
          payment_due_date = $37,
          is_advance_period = COALESCE($38, is_advance_period),
          advance_billed_amount = COALESCE($39, advance_billed_amount),
          billing_amount_override = $40,
          attendance_charges = COALESCE($41, attendance_charges),
          total_present_days = COALESCE($42, total_present_days),
          total_absent_days = COALESCE($43, total_absent_days),
          max_stay_days = COALESCE($44, max_stay_days),
          extension_approved = COALESCE($45, extension_approved),
          extension_days = COALESCE($46, extension_days),
          extension_reason = $47,
          approved_by = $48,
          approved_date = $49,
          photo_data_url = $50,
          photo_ref = $51,
          photo_file_name = $52,
          notes = $53,
          date_of_birth = COALESCE($54, date_of_birth),
          admission_date = COALESCE($55, admission_date),
          version = version + 1,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = $1
        RETURNING *;
      `;

      const updateValues = [
        id,
        body.fullName || null,
        body.searchKey || (body.fullName ? String(body.fullName).toLowerCase() : null),
        body.age != null ? parseInt(body.age, 10) : null,
        body.gender || null,
        body.contactNumber || null,
        body.emergencyContact || null,
        body.emergencyContactName || null,
        body.medicalCondition || null,
        body.allergies || null,
        body.bloodType || null,
        body.status || null,
        body.dischargeDate != null ? new Date(body.dischargeDate) : null,
        body.exitDate != null ? new Date(body.exitDate) : null,
        body.roomId || null,
        body.roomNumber || null,
        body.floor != null ? parseInt(body.floor, 10) : null,
        body.bedIds ? JSON.stringify(body.bedIds) : null,
        body.bedLabels ? JSON.stringify(body.bedLabels) : null,
        body.lobby || null,
        body.address || null,
        body.registrationNumber || null,
        body.registrationDate != null ? new Date(body.registrationDate) : null,
        body.panCardNumber || null,
        body.aadhaarCardNumber || null,
        body.receiptNumber || null,
        body.modeOfPayment || null,
        body.utiNumber || null,
        body.paymentPending != null ? Boolean(body.paymentPending) : null,
        body.paymentStatus || null,
        body.totalPaidAmount != null ? body.totalPaidAmount : null,
        body.currentDueAmount != null ? body.currentDueAmount : null,
        body.refundDueAmount != null ? body.refundDueAmount : null,
        body.totalRefundDueAmount != null ? body.totalRefundDueAmount : null,
        body.totalRefundedAmount != null ? body.totalRefundedAmount : null,
        body.admissionBalances ? JSON.stringify(body.admissionBalances) : null,
        body.paymentDueDate != null ? new Date(body.paymentDueDate) : null,
        body.isAdvancePeriod != null ? Boolean(body.isAdvancePeriod) : null,
        body.advanceBilledAmount != null ? body.advanceBilledAmount : null,
        body.billingAmountOverride != null ? body.billingAmountOverride : null,
        body.attendanceCharges != null ? body.attendanceCharges : null,
        body.totalPresentDays != null ? parseInt(body.totalPresentDays, 10) : null,
        body.totalAbsentDays != null ? parseInt(body.totalAbsentDays, 10) : null,
        body.maxStayDays != null ? parseInt(body.maxStayDays, 10) : null,
        body.extensionApproved != null ? Boolean(body.extensionApproved) : null,
        body.extensionDays != null ? parseInt(body.extensionDays, 10) : null,
        body.extensionReason || null,
        body.approvedBy || null,
        body.approvedDate != null ? new Date(body.approvedDate) : null,
        body.photoDataUrl || null,
        body.photoRef || null,
        body.photoFileName || null,
        body.notes || null,
        body.dateOfBirth != null ? new Date(body.dateOfBirth) : null,
        body.admissionDate != null ? new Date(body.admissionDate) : null,
      ];

      const updatedPatient = await client.query<RawPatientRow>(updateSql, updateValues);

      // If attendants are provided, replace them
      let attendants: RawAttendantRow[] = [];
      if (Array.isArray((request.body as Record<string, unknown>).attendants)) {
        await client.query('DELETE FROM patient_attendants WHERE patient_id = $1', [id]);
        for (let i = 0; i < body.attendants.length; i++) {
          const att = body.attendants[i];
          const attId = attendantId(id, i);
          const attRes = await client.query<RawAttendantRow>(
            `INSERT INTO patient_attendants (
              id, patient_id, name, age, relation, aadhaar_number,
              mobile_number, is_emergency_contact, photo_ref, photo_data_url
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *`,
            [
              attId,
              id,
              att.name || 'Unnamed Attendant',
              att.age ? String(att.age) : null,
              att.relation || null,
              att.aadhaarNumber || null,
              att.mobileNumber || null,
              Boolean(att.isEmergencyContact),
              att.photoRef || null,
              att.photoDataUrl || null,
            ]
          );
          attendants.push(attRes.rows[0]);
        }
      } else {
        const attRes = await client.query<RawAttendantRow>(
          'SELECT * FROM patient_attendants WHERE patient_id = $1',
          [id]
        );
        attendants = attRes.rows;
      }

      // Commit the calculated patient balance and its stay summaries together.
      // The patient lock/version also serializes attendance, payments and stays.
      for (const [stayId, values] of Object.entries((request.body as any).stayBillingUpdates ?? {}).sort(([a], [b]) => a.localeCompare(b))) {
        const delta = values as Record<string, any>;
        const updated = await client.query(
          `UPDATE stays SET total_cost=COALESCE($3,total_cost), cycle_id=COALESCE($4,cycle_id),
           daily_rate=CASE WHEN $5 THEN $6 ELSE daily_rate END,
           billing_summary=COALESCE($7,billing_summary),
           completed_at=COALESCE($8,completed_at),updated_at=CURRENT_TIMESTAMP
           WHERE id=$1 AND patient_id=$2 RETURNING id`,
          [stayId, id, delta.totalCost ?? null, delta.cycleId ?? null,
            Object.hasOwn(delta, 'dailyRate'), delta.dailyRate ?? null,
            delta.billingSummary == null ? null : JSON.stringify(delta.billingSummary),
            delta.completedAt == null ? null : new Date(delta.completedAt)],
        );
        if (!updated.rowCount) throw httpError(409, 'Billing stay no longer belongs to this patient');
      }
      const payments = await client.query('SELECT * FROM payments WHERE patient_id=$1 ORDER BY payment_date DESC', [id]);
      await client.query('COMMIT');
      return reply.send(formatPatient(updatedPatient.rows[0], attendants, payments.rows.map(payment => formatPayment(payment as any))));
    } catch (err: unknown) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  });

  // ── DELETE /api/patients/:id ────────────────────────────────────────────────
  fastify.delete(
    '/patients/:id',
    { preHandler: [requireRoles(['admin'])] },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      const client = await getClient();
      try {
        await client.query('BEGIN');

        // 1. Verify patient exists with row-level lock
        const check = await client.query('SELECT id FROM patients WHERE id = $1 FOR UPDATE', [id]);
        if (check.rows.length === 0) {
          await client.query('ROLLBACK');
          return reply.status(404).send({ error: 'NotFound', message: `Patient '${id}' not found` });
        }

        // 2. Identify all affected rooms
        const affectedRooms = await client.query<{ room_id: string }>(
          `SELECT DISTINCT room_id FROM (
             SELECT room_id FROM patients WHERE id = $1 AND room_id IS NOT NULL
             UNION
             SELECT room_id FROM stays WHERE patient_id = $1 AND room_id IS NOT NULL
             UNION
             SELECT room_id FROM room_beds WHERE (current_patient_id = $1 OR current_stay_id IN (SELECT id FROM stays WHERE patient_id = $1)) AND room_id IS NOT NULL
           ) r`,
          [id]
        );

        await client.query('SELECT id FROM rooms WHERE id=ANY($1::varchar[]) ORDER BY id FOR UPDATE', [affectedRooms.rows.map(r => r.room_id)]);
        // 3. Clear bed assignments for this patient and all their stays
        await client.query(
          `UPDATE room_beds
           SET status = 'available',
               current_patient_id = NULL,
               current_stay_id = NULL,
               updated_at = CURRENT_TIMESTAMP
           WHERE current_patient_id = $1
              OR current_stay_id IN (SELECT id FROM stays WHERE patient_id = $1)`,
          [id]
        );

        // 4. Detach patient from any sponsorships
        await client.query(
          'UPDATE sponsorships SET patient_id = NULL WHERE patient_id = $1',
          [id]
        );

        // 5. Delete dependent records exclusively belonging to this patient
        await client.query('DELETE FROM attendance_records WHERE patient_id = $1', [id]);
        await client.query('DELETE FROM patient_attendants WHERE patient_id = $1', [id]);
        await client.query('DELETE FROM payments WHERE patient_id = $1', [id]);
        await client.query('DELETE FROM patient_photos WHERE patient_id = $1', [id]);
        await client.query('DELETE FROM stays WHERE patient_id = $1', [id]);

        // 6. Delete the patient record
        const res = await client.query('DELETE FROM patients WHERE id = $1 RETURNING id', [id]);
        if (res.rows.length === 0) {
          await client.query('ROLLBACK');
          return reply.status(404).send({ error: 'NotFound', message: `Patient '${id}' not found` });
        }

        // 7. Refresh occupancy for all affected rooms
        for (const r of affectedRooms.rows) {
          if (r.room_id) await refreshRoomOccupancy(client, r.room_id);
        }

        await client.query('COMMIT');
        return reply.send({ success: true, deletedId: id });
      } catch (err) {
        await client.query('ROLLBACK');
        throw err;
      } finally {
        client.release();
      }
    }
  );
}
