import fs from 'fs';
import { createHash } from 'node:crypto';
import { getClient } from '../db/index.js';
import { attendantId } from '../db/identifiers.js';
import { receiptCycle } from '../services/billing.js';

export interface ImportOptions {
  filePath: string;
  dryRun?: boolean;
  strict?: boolean;
  reconcile?: boolean;
  onProgress?: (message: string) => void;
}

export interface ReconciliationSummary {
  patients: { source: number; matched: number; imported: number; conflicting: number };
  stays: { source: number; matched: number; imported: number; unresolved: number };
  payments: { source: number; matched: number; imported: number; deduplicated: number; conflicting: number; unresolved: number };
  attendance: { source: number; matched: number; imported: number; unresolved: number };
  photos: { source: number; matched: number; imported: number };
}

export interface ImportStats {
  rooms: { processed: number; imported: number; updated: number; failed: number };
  beds: { processed: number; imported: number; updated: number; failed: number; assignmentFailures: number };
  patients: { processed: number; imported: number; updated: number; failed: number };
  attendants: { processed: number; imported: number; updated: number; failed: number };
  stays: { processed: number; imported: number; updated: number; failed: number; missingPatientRefs: number };
  attendance: { processed: number; imported: number; updated: number; failed: number; missingPatientRefs: number };
  payments: { processed: number; imported: number; updated: number; unchanged: number; failed: number; missingPatientRefs: number; deduplicated: number };
  photos: { processed: number; imported: number; updated: number; failed: number };
  expenses: { processed: number; imported: number; updated: number; failed: number };
  sponsorships: { processed: number; imported: number; updated: number; failed: number };
  settings: { processed: number; imported: number; updated: number; failed: number };
  financials: {
    sourceTotalPayments: number;
    dbTotalPayments: number;
    sourceTotalPatientPaid: number;
    dbTotalPatientPaid: number;
    sourceTotalPatientDue: number;
    dbTotalPatientDue: number;
  };
  reconciliation?: ReconciliationSummary;
  warnings: string[];
  durationMs: number;
  committed: boolean;
}

function parseDate(val: any): Date | null {
  if (val == null) return null;
  if (typeof val !== 'number' && typeof val !== 'string') throw new Error('Invalid date');
  if (typeof val === 'string' && !/^\d{4}-\d{2}-\d{2}(?:T.*)?$/.test(val)) throw new Error('Invalid date');
  const parsed = new Date(val);
  if (isNaN(parsed.getTime()) || (typeof val === 'string' && new Date(val.slice(0, 10)).toISOString().slice(0, 10) !== val.slice(0, 10))) {
    throw new Error('Invalid date');
  }
  return parsed;
}

function requiredDate(val: any): Date {
  const result = parseDate(val);
  if (!result) throw new Error('Missing required date');
  return result;
}

function requiredString(value: unknown, allowEmpty = true): string {
  if (typeof value !== 'string' || (!allowEmpty && !value.trim())) throw new Error('Missing required text field');
  return value;
}

function toEpochMs(d: any): number | null {
  if (d == null) return null;
  if (typeof d === 'number') return d;
  const parsed = new Date(d).getTime();
  return isNaN(parsed) ? null : parsed;
}

function registrationFingerprint(p: any): string {
  return createHash('sha256').update(JSON.stringify({
    fullName: String(p.fullName).trim(),
    dateOfBirth: toEpochMs(p.dateOfBirth),
    gender: p.gender,
    contactNumber: p.contactNumber,
    admissionDate: toEpochMs(p.admissionDate),
  })).digest('hex');
}

// Pass decimal strings to PostgreSQL; never truncate malformed values or let
// NUMERIC silently round historical ledger amounts during an import.
function parseDecimal(val: any, fallback = 0): string {
  const text = String(val ?? fallback);
  if (!/^-?\d+(?:\.\d{1,2})?$/.test(text)) throw new Error('Invalid monetary value');
  const negative = text.startsWith('-');
  const [whole, fraction = ''] = text.replace(/^-/, '').split('.');
  const cents = BigInt(whole) * 100n + BigInt(fraction.padEnd(2, '0'));
  if (cents > 999999999999n) throw new Error('Monetary value exceeds schema precision');
  return `${negative && cents !== 0n ? '-' : ''}${cents / 100n}.${String(cents % 100n).padStart(2, '0')}`;
}

function cents(value: string): bigint {
  return BigInt(value.replace('.', ''));
}

function safeError(err: unknown): string {
  const code = (err as { code?: string })?.code;
  // PostgreSQL error details may include full patient records. Keep logs redacted.
  return code && /^[A-Z0-9]{5}$/.test(code) ? `database error ${code}` : 'invalid or conflicting record';
}

export async function runFirebaseImport(options: ImportOptions): Promise<ImportStats> {
  const startTime = Date.now();
  const log = options.onProgress || console.log;
  const reconcileMode = options.reconcile === true;

  log(`[Importer] Reading Firebase export from ${options.filePath}...`);
  if (!fs.existsSync(options.filePath)) {
    throw new Error(`Export file not found at path: ${options.filePath}`);
  }

  const rawJson = fs.readFileSync(options.filePath, 'utf8');
  const data = JSON.parse(rawJson);
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('Export root must be an object');

  const reconciliation: ReconciliationSummary = {
    patients: { source: 0, matched: 0, imported: 0, conflicting: 0 },
    stays: { source: 0, matched: 0, imported: 0, unresolved: 0 },
    payments: { source: 0, matched: 0, imported: 0, deduplicated: 0, conflicting: 0, unresolved: 0 },
    attendance: { source: 0, matched: 0, imported: 0, unresolved: 0 },
    photos: { source: 0, matched: 0, imported: 0 },
  };

  const stats: ImportStats = {
    rooms: { processed: 0, imported: 0, updated: 0, failed: 0 },
    beds: { processed: 0, imported: 0, updated: 0, failed: 0, assignmentFailures: 0 },
    patients: { processed: 0, imported: 0, updated: 0, failed: 0 },
    attendants: { processed: 0, imported: 0, updated: 0, failed: 0 },
    stays: { processed: 0, imported: 0, updated: 0, failed: 0, missingPatientRefs: 0 },
    attendance: { processed: 0, imported: 0, updated: 0, failed: 0, missingPatientRefs: 0 },
    payments: { processed: 0, imported: 0, updated: 0, unchanged: 0, failed: 0, missingPatientRefs: 0, deduplicated: 0 },
    photos: { processed: 0, imported: 0, updated: 0, failed: 0 },
    expenses: { processed: 0, imported: 0, updated: 0, failed: 0 },
    sponsorships: { processed: 0, imported: 0, updated: 0, failed: 0 },
    settings: { processed: 0, imported: 0, updated: 0, failed: 0 },
    financials: {
      sourceTotalPayments: 0,
      dbTotalPayments: 0,
      sourceTotalPatientPaid: 0,
      dbTotalPatientPaid: 0,
      sourceTotalPatientDue: 0,
      dbTotalPatientDue: 0,
    },
    ...(reconcileMode ? { reconciliation } : {}),
    warnings: [],
    durationMs: 0,
    committed: false,
  };
  let sourcePaidCents = 0n;
  let sourceDueCents = 0n;
  let sourcePaymentCents = 0n;
  const pendingBedAssignments: Array<{ id: string; patientId: string | null; stayId: string | null; roomId: string }> = [];
  const supportedBranches = new Set([
    'users', 'system_counters', 'rooms', 'patients', 'stays', 'attendance',
    'attendant_attendance', 'payments', 'paymentHistory', 'admin_settings/pricing',
    'admin_settings', 'settings', 'metadata', 'patientPhotos', 'expense_entries',
    'sponsorships', 'inventory_items', 'vendors', 'purchases', 'salaries', 'capturedAt',
  ]);
  for (const [branch, value] of Object.entries(data)) {
    if (!supportedBranches.has(branch) && value != null &&
        (typeof value !== 'object' || Object.keys(value).length > 0)) {
      stats.warnings.push('Unsupported nonempty export branch detected; no import was committed.');
    }
  }

  const client = await getClient();
  try {
    await client.query('BEGIN');
    // Each rejected row must release PostgreSQL's aborted transaction state.
    const beginRecord = () => client.query('SAVEPOINT import_record');
    const finishRecord = () => client.query('RELEASE SAVEPOINT import_record');
    const rejectRecord = async () => {
      await client.query('ROLLBACK TO SAVEPOINT import_record');
      await finishRecord();
    };

    // ─────────────────────────────────────────────────────────────────────────
    // Step 1: Users collection & Creator placeholders
    // ─────────────────────────────────────────────────────────────────────────
    log('[Importer] Step 1/11: Seeding required user identities...');
    const creatorUids = new Set<string>();

    if (data.users && typeof data.users === 'object') {
      for (const [uid, u] of Object.entries<any>(data.users)) {
        await client.query(
          `INSERT INTO users (id, email, name, phone, role, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           ON CONFLICT (id) DO UPDATE SET
             email = EXCLUDED.email,
             name = EXCLUDED.name,
             phone = EXCLUDED.phone,
             role = EXCLUDED.role,
             updated_at = EXCLUDED.updated_at`,
          [
            uid,
            u.email || `${uid}@firebase.import`,
            u.name || 'Imported User',
            u.phone || null,
            u.role || 'volunteer',
            parseDate(u.createdAt) || new Date(),
            parseDate(u.updatedAt) || new Date(),
          ]
        );
      }
    }

    // Collect creators from patients, stays, etc.
    const collectCreators = (branch: any) => {
      if (branch && typeof branch === 'object') {
        for (const item of Object.values<any>(branch)) {
          if (item && item.createdBy && typeof item.createdBy === 'string') {
            creatorUids.add(item.createdBy);
          }
        }
      }
    };
    collectCreators(data.patients);
    collectCreators(data.stays);
    collectCreators(data.expense_entries);
    collectCreators(data.sponsorships);
    collectCreators(data.purchases);
    collectCreators(data.inventory_items);

    for (const uid of creatorUids) {
      await client.query(
        `INSERT INTO users (id, email, name, role)
         VALUES ($1, $2, $3, 'volunteer')
         ON CONFLICT (id) DO NOTHING`,
        [uid, `${uid.replace(/[^a-zA-Z0-9]/g, '_')}@firebase.import`, `User (${uid.substring(0, 8)})`]
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Step 2: System Counters
    // ─────────────────────────────────────────────────────────────────────────
    log('[Importer] Step 2/11: Migrating system sequence counters...');
    const countersBranch = data.system_counters || data['system_counters'];
    if (countersBranch && typeof countersBranch === 'object') {
      for (const [counterName, rawVal] of Object.entries(countersBranch)) {
        let valNum: any = rawVal;
        if (typeof rawVal === 'object' && rawVal !== null) {
          valNum = (rawVal as any).current ?? (rawVal as any).value ?? (rawVal as any).count;
        }
        const val = String(valNum);
        if (!/^\d+$/.test(val) || BigInt(val) > 9223372036854775807n) throw new Error('Invalid sequence counter');
        await client.query(
          `INSERT INTO system_counters (counter_name, current_value, updated_at)
           VALUES ($1, $2, CURRENT_TIMESTAMP)
           ON CONFLICT (counter_name) DO UPDATE
           SET current_value = GREATEST(system_counters.current_value, EXCLUDED.current_value),
               updated_at = CURRENT_TIMESTAMP`,
          [counterName, val]
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Step 3: Rooms and Room Beds
    // ─────────────────────────────────────────────────────────────────────────
    log('[Importer] Step 3/11: Migrating rooms and beds...');

    // Pre-provision lobby rooms referenced by stays
    const lobbyRooms = new Map<string, string>();
    if (data.stays && typeof data.stays === 'object') {
      for (const s of Object.values<any>(data.stays)) {
        if (s && s.roomId && (String(s.roomId).startsWith('lobby:') || s.roomType === 'lobby')) {
          const name = s.roomNumber || String(s.roomId).replace(/^lobby:/, '') || 'Lobby';
          lobbyRooms.set(s.roomId, name);
        }
      }
    }
    for (const [lobbyId, lobbyName] of lobbyRooms.entries()) {
      stats.rooms.processed++;
      const floorMatch = lobbyName.match(/^\d+/);
      const floor = floorMatch ? parseInt(floorMatch[0], 10) : 1;
      const res = await client.query(
        `INSERT INTO rooms (
          id, room_number, room_identifier, floor, room_type, status,
          max_attendants, current_attendants, has_custom_attendant_limit,
          total_beds, occupied_beds, version, notes
        ) VALUES ($1, $2, $2, $3, 'lobby', 'available', 5, 0, false, 0, 0, 1, 'Auto-provisioned lobby')
        ON CONFLICT (id) DO UPDATE SET
          room_number = EXCLUDED.room_number,
          room_identifier = EXCLUDED.room_identifier
        RETURNING (xmax = 0) AS is_inserted`,
        [lobbyId, lobbyName, floor]
      );
      if (res.rows[0]?.is_inserted) stats.rooms.imported++;
      else stats.rooms.updated++;
    }

    const roomsBranch = data.rooms || {};
    for (const [roomId, r] of Object.entries<any>(roomsBranch)) {
      if (!r || typeof r !== 'object') continue;
      stats.rooms.processed++;

      await beginRecord();
      try {
        const roomRes = await client.query(
          `INSERT INTO rooms (
            id, room_number, room_identifier, floor, room_type, status,
            max_attendants, current_attendants, has_custom_attendant_limit,
            total_beds, occupied_beds, expected_vacancy_date, version, notes,
            created_at, updated_at
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
          ON CONFLICT (id) DO UPDATE SET
            room_number = EXCLUDED.room_number,
            room_identifier = EXCLUDED.room_identifier,
            floor = EXCLUDED.floor,
            room_type = EXCLUDED.room_type,
            status = EXCLUDED.status,
            max_attendants = EXCLUDED.max_attendants,
            current_attendants = EXCLUDED.current_attendants,
            has_custom_attendant_limit = EXCLUDED.has_custom_attendant_limit,
            total_beds = EXCLUDED.total_beds,
            occupied_beds = EXCLUDED.occupied_beds,
            expected_vacancy_date = EXCLUDED.expected_vacancy_date,
            version = EXCLUDED.version,
            notes = EXCLUDED.notes,
            updated_at = EXCLUDED.updated_at
          RETURNING (xmax = 0) AS is_inserted`,
          [
            roomId,
            r.roomNumber || r.roomIdentifier || 'Room',
            r.roomIdentifier || r.roomNumber || 'Room',
            r.floor != null ? parseInt(String(r.floor), 10) : 1,
            r.roomType || 'general',
            r.status || 'available',
            r.maxAttendants != null ? parseInt(String(r.maxAttendants), 10) : 5,
            r.currentAttendants != null ? parseInt(String(r.currentAttendants), 10) : 0,
            Boolean(r.hasCustomAttendantLimit),
            r.totalBeds != null ? parseInt(String(r.totalBeds), 10) : 0,
            r.occupiedBeds != null ? parseInt(String(r.occupiedBeds), 10) : 0,
            parseDate(r.expectedVacancyDate),
            r.version != null ? parseInt(String(r.version), 10) : 1,
            r.notes || null,
            parseDate(r.createdAt) || new Date(),
            parseDate(r.updatedAt) || new Date(),
          ]
        );

        if (roomRes.rows[0]?.is_inserted) {
          stats.rooms.imported++;
        } else {
          stats.rooms.updated++;
        }

        await finishRecord();
        // Migrate beds in this room (can be map or array in RTDB)
        if (r.beds) {
          const bedEntries: Array<[string, any]> = Array.isArray(r.beds)
            ? r.beds.map((b: any, idx: number): [string, any] => [b?.id || `${roomId}_${idx + 1}`, b])
            : Object.entries(r.beds);

          for (const [bedId, b] of bedEntries) {
            if (!b || typeof b !== 'object') continue;
            stats.beds.processed++;
            await beginRecord();
            try {
              const bedRes = await client.query(
                `INSERT INTO room_beds (id, room_id, bed_label, status, current_patient_id, current_stay_id, last_cleaned)
                 VALUES ($1, $2, $3, $4, $5, $6, $7)
                 ON CONFLICT (id) DO UPDATE SET
                   bed_label = EXCLUDED.bed_label,
                   status = EXCLUDED.status,
                   current_patient_id = EXCLUDED.current_patient_id,
                   current_stay_id = EXCLUDED.current_stay_id,
                   last_cleaned = EXCLUDED.last_cleaned,
                   updated_at = CURRENT_TIMESTAMP
                 WHERE room_beds.room_id = EXCLUDED.room_id
                 RETURNING (xmax = 0) AS is_inserted`,
                [
                  String(bedId),
                  roomId,
                  b.bedLabel || b.bedNumber || 'Bed',
                  b.status || 'available',
                  null, // Attach pointers after patients and stays exist (foreign keys).
                  null,
                  parseDate(b.lastCleaned),
                ]
              );

              if (!bedRes.rowCount) throw new Error('Bed identity belongs to a different room');
              if (bedRes.rows[0]?.is_inserted) {
                stats.beds.imported++;
              } else {
                stats.beds.updated++;
              }
              await finishRecord();
              if (b.currentPatientId || b.currentStayId) {
                pendingBedAssignments.push({
                  id: String(bedId),
                  patientId: b.currentPatientId || null,
                  stayId: b.currentStayId || null,
                  roomId,
                });
              }
            } catch (err: unknown) {
              await rejectRecord();
              stats.beds.failed++;
              stats.warnings.push(`Bed rejected: ${safeError(err)}.`);
            }
          }
        }
      } catch (err: unknown) {
        await rejectRecord();
        stats.rooms.failed++;
        stats.warnings.push(`Room rejected: ${safeError(err)}.`);
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Step 4: Patients & Attendants
    // ─────────────────────────────────────────────────────────────────────────
    log('[Importer] Step 4/11: Migrating patients and attendants...');
    const patientsBranch = data.patients || {};
    const validPatientIds = new Set<string>();
    const existingPgPatients = new Map<string, any>();
    const existingPgRegNumbers = new Map<string, string>();

    if (reconcileMode) {
      const existingRes = await client.query(
        'SELECT id, registration_number, admission_date, updated_at FROM patients'
      );
      for (const row of existingRes.rows || []) {
        if (row.id) {
          validPatientIds.add(row.id);
          existingPgPatients.set(row.id, row);
          if (row.registration_number) {
            existingPgRegNumbers.set(String(row.registration_number).trim().toLowerCase(), row.id);
          }
        }
      }
    }

    for (const [patientId, p] of Object.entries<any>(patientsBranch)) {
      if (!p || typeof p !== 'object') continue;
      stats.patients.processed++;
      reconciliation.patients.source++;

      if (reconcileMode && existingPgPatients.has(patientId)) {
        // Preserve existing PostgreSQL patient record without overwriting live modifications.
        const paid = parseDecimal(p.totalPaidAmount);
        const due = parseDecimal(p.currentDueAmount);
        sourcePaidCents += cents(paid);
        sourceDueCents += cents(due);
        validPatientIds.add(patientId);
        reconciliation.patients.matched++;
        continue;
      }

      if (reconcileMode && p.registrationNumber) {
        const regLower = String(p.registrationNumber).trim().toLowerCase();
        const ownerId = existingPgRegNumbers.get(regLower);
        if (ownerId && ownerId !== patientId) {
          stats.patients.failed++;
          reconciliation.patients.conflicting++;
          stats.warnings.push(`Patient rejected: registration number conflict with existing patient.`);
          continue;
        }
      }

      await beginRecord();
      const attendantStatsBefore = { ...stats.attendants };
      try {
        const paid = parseDecimal(p.totalPaidAmount);
        const due = parseDecimal(p.currentDueAmount);
        sourcePaidCents += cents(paid);
        sourceDueCents += cents(due);
        const creator = p.createdBy && creatorUids.has(p.createdBy) ? p.createdBy : 'system_importer';
        if (creator === 'system_importer') {
          await client.query(
            `INSERT INTO users (id, email, name, role) VALUES ('system_importer', 'importer@ngo.local', 'System Importer', 'admin') ON CONFLICT (id) DO NOTHING`
          );
        }

        const regFingerprint = registrationFingerprint(p);

        const patientRes = await client.query(
          `INSERT INTO patients (
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
            photo_file_name, notes, created_by, created_at, updated_at, registration_fingerprint
          ) VALUES (
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
            $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
            $21, $22, $23, $24, $25, $26, $27, $28, $29, $30,
            $31, $32, $33, $34, $35, $36, $37, $38, $39, $40,
            $41, $42, $43, $44, $45, $46, $47, $48, $49, $50,
            $51, $52, $53, $54, $55, $56, $57, $58, $59
          ) ON CONFLICT (id) DO UPDATE SET
            full_name = EXCLUDED.full_name,
            search_key = EXCLUDED.search_key,
            date_of_birth = EXCLUDED.date_of_birth,
            age = EXCLUDED.age,
            gender = EXCLUDED.gender,
            contact_number = EXCLUDED.contact_number,
            emergency_contact = EXCLUDED.emergency_contact,
            emergency_contact_name = EXCLUDED.emergency_contact_name,
            medical_condition = EXCLUDED.medical_condition,
            allergies = EXCLUDED.allergies,
            blood_type = EXCLUDED.blood_type,
            admission_date = EXCLUDED.admission_date,
            status = EXCLUDED.status,
            discharge_date = EXCLUDED.discharge_date,
            exit_date = EXCLUDED.exit_date,
            room_id = EXCLUDED.room_id,
            room_number = EXCLUDED.room_number,
            floor = EXCLUDED.floor,
            bed_ids = EXCLUDED.bed_ids,
            bed_labels = EXCLUDED.bed_labels,
            lobby = EXCLUDED.lobby,
            address = EXCLUDED.address,
            registration_number = EXCLUDED.registration_number,
            registration_date = EXCLUDED.registration_date,
            pan_card_number = EXCLUDED.pan_card_number,
            aadhaar_card_number = EXCLUDED.aadhaar_card_number,
            receipt_number = EXCLUDED.receipt_number,
            mode_of_payment = EXCLUDED.mode_of_payment,
            uti_number = EXCLUDED.uti_number,
            payment_pending = EXCLUDED.payment_pending,
            payment_status = EXCLUDED.payment_status,
            total_paid_amount = EXCLUDED.total_paid_amount,
            current_due_amount = EXCLUDED.current_due_amount,
            refund_due_amount = EXCLUDED.refund_due_amount,
            total_refund_due_amount = EXCLUDED.total_refund_due_amount,
            total_refunded_amount = EXCLUDED.total_refunded_amount,
            admission_balances = EXCLUDED.admission_balances,
            payment_due_date = EXCLUDED.payment_due_date,
            is_advance_period = EXCLUDED.is_advance_period,
            advance_billed_amount = EXCLUDED.advance_billed_amount,
            billing_amount_override = EXCLUDED.billing_amount_override,
            attendance_charges = EXCLUDED.attendance_charges,
            total_present_days = EXCLUDED.total_present_days,
            total_absent_days = EXCLUDED.total_absent_days,
            max_stay_days = EXCLUDED.max_stay_days,
            extension_approved = EXCLUDED.extension_approved,
            extension_days = EXCLUDED.extension_days,
            extension_reason = EXCLUDED.extension_reason,
            approved_by = EXCLUDED.approved_by,
            approved_date = EXCLUDED.approved_date,
            photo_data_url = EXCLUDED.photo_data_url,
            photo_ref = EXCLUDED.photo_ref,
            photo_file_name = EXCLUDED.photo_file_name,
            notes = EXCLUDED.notes,
            created_by = EXCLUDED.created_by,
            updated_at = EXCLUDED.updated_at,
            registration_fingerprint = EXCLUDED.registration_fingerprint
          RETURNING (xmax = 0) AS is_inserted`,
          [
            patientId,
            requiredString(p.fullName, false),
            p.searchKey || (p.fullName ? String(p.fullName).toLowerCase() : null),
            requiredDate(p.dateOfBirth),
            p.age != null ? parseInt(String(p.age), 10) : null,
            requiredString(p.gender, false),
            requiredString(p.contactNumber),
            requiredString(p.emergencyContact),
            requiredString(p.emergencyContactName),
            requiredString(p.medicalCondition),
            p.allergies || null,
            p.bloodType || null,
            requiredDate(p.admissionDate),
            p.status || 'active',
            parseDate(p.dischargeDate),
            parseDate(p.exitDate),
            p.roomId || null,
            p.roomNumber || null,
            p.floor != null ? parseInt(String(p.floor), 10) : null,
            JSON.stringify(p.bedIds || []),
            JSON.stringify(p.bedLabels || []),
            p.lobby || null,
            p.address || null,
            p.registrationNumber || null,
            parseDate(p.registrationDate),
            p.panCardNumber || null,
            p.aadhaarCardNumber || null,
            p.receiptNumber || null,
            p.modeOfPayment || null,
            p.utiNumber || null,
            Boolean(p.paymentPending),
            p.paymentStatus || 'Paid',
            paid,
            due,
            parseDecimal(p.refundDueAmount),
            parseDecimal(p.totalRefundDueAmount),
            parseDecimal(p.totalRefundedAmount),
            JSON.stringify(p.admissionBalances || {}),
            parseDate(p.paymentDueDate),
            p.isAdvancePeriod != null ? Boolean(p.isAdvancePeriod) : true,
            parseDecimal(p.advanceBilledAmount),
            p.billingAmountOverride != null ? parseDecimal(p.billingAmountOverride) : null,
            parseDecimal(p.attendanceCharges),
            p.totalPresentDays || 0,
            p.totalAbsentDays || 0,
            p.maxStayDays || 60,
            Boolean(p.extensionApproved),
            p.extensionDays || 0,
            p.extensionReason || null,
            p.approvedBy || null,
            parseDate(p.approvedDate),
            p.photoDataUrl || null,
            p.photoRef || null,
            p.photoFileName || null,
            p.notes || null,
            creator,
            parseDate(p.createdAt) || new Date(),
            parseDate(p.updatedAt) || new Date(),
            regFingerprint,
          ]
        );

        // Migrate attendants
        if (p.attendants) {
          const attendantList = Array.isArray(p.attendants) ? p.attendants : Object.values(p.attendants);
          await client.query('DELETE FROM patient_attendants WHERE patient_id = $1', [patientId]);

          for (let i = 0; i < attendantList.length; i++) {
            const att = attendantList[i];
            if (!att || typeof att !== 'object') continue;
            stats.attendants.processed++;

            await client.query(
              `INSERT INTO patient_attendants (
                id, patient_id, name, age, relation, aadhaar_number,
                mobile_number, is_emergency_contact, photo_ref, photo_data_url
              ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
              [
                attendantId(patientId, i),
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
            stats.attendants.imported++;
          }
        }
        await finishRecord();
        validPatientIds.add(patientId);
        if (p.registrationNumber) {
          existingPgRegNumbers.set(String(p.registrationNumber).trim().toLowerCase(), patientId);
        }
        if (patientRes.rows[0]?.is_inserted) {
          stats.patients.imported++;
          reconciliation.patients.imported++;
        } else {
          stats.patients.updated++;
          reconciliation.patients.matched++;
        }
      } catch (err: unknown) {
        await rejectRecord();
        const attemptedAttendants = stats.attendants.processed - attendantStatsBefore.processed;
        stats.attendants = {
          ...attendantStatsBefore,
          processed: attendantStatsBefore.processed + attemptedAttendants,
          failed: attendantStatsBefore.failed + attemptedAttendants,
        };
        stats.patients.failed++;
        reconciliation.patients.conflicting++;
        stats.warnings.push(`Patient rejected: ${safeError(err)}.`);
      }
    }

    // Ensure registrationNumber counter is synchronized with imported patients
    const maxRegRes = await client.query(
      `SELECT COALESCE(MAX(CASE WHEN registration_number ~ '^[0-9]+$' THEN registration_number::bigint ELSE 0 END), 0) AS max_val FROM patients`
    );
    const maxPatientReg = BigInt(maxRegRes.rows[0]?.max_val || 0);
    if (maxPatientReg > 0n) {
      await client.query(
        `INSERT INTO system_counters (counter_name, current_value, updated_at)
         VALUES ('registrationNumber', $1, CURRENT_TIMESTAMP)
         ON CONFLICT (counter_name) DO UPDATE
         SET current_value = GREATEST(system_counters.current_value, EXCLUDED.current_value),
             updated_at = CURRENT_TIMESTAMP`,
        [maxPatientReg.toString()]
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Step 5: Stays
    // ─────────────────────────────────────────────────────────────────────────
    log('[Importer] Step 5/11: Migrating admissions and stays...');
    const staysBranch = data.stays || {};
    const existingPgStays = new Set<string>();
    if (reconcileMode) {
      const existingStaysRes = await client.query('SELECT id FROM stays');
      for (const row of existingStaysRes.rows || []) {
        if (row.id) existingPgStays.add(row.id);
      }
    }

    for (const [stayId, s] of Object.entries<any>(staysBranch)) {
      if (!s || typeof s !== 'object') continue;
      stats.stays.processed++;
      reconciliation.stays.source++;

      if (!validPatientIds.has(s.patientId)) {
        stats.stays.missingPatientRefs++;
        stats.stays.failed++;
        reconciliation.stays.unresolved++;
        stats.warnings.push('Stay rejected: missing or rejected patient reference.');
        continue;
      }

      if (reconcileMode && existingPgStays.has(stayId)) {
        reconciliation.stays.matched++;
        continue;
      }

      await beginRecord();
      try {
        if (!s.roomId) throw new Error('Missing room reference');
        const creator = s.createdBy && creatorUids.has(s.createdBy) ? s.createdBy : 'system_importer';
        const admission = requiredDate(s.admissionDate);
        const duration = parseInt(String(s.durationDays || 1), 10);
        const expected = parseDate(s.expectedDischargeDate) || new Date(admission.getTime() + duration * 86400000);
        const expiry = parseDate(s.expiryDate) || expected;

        const stayRes = await client.query(
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
            $32, $33, $34, $35
          ) ON CONFLICT (id) DO UPDATE SET
            patient_id = EXCLUDED.patient_id,
            patient_name = EXCLUDED.patient_name,
            patient_snapshot = EXCLUDED.patient_snapshot,
            room_id = EXCLUDED.room_id,
            room_number = EXCLUDED.room_number,
            room_type = EXCLUDED.room_type,
            cycle_id = EXCLUDED.cycle_id,
            admission_date = EXCLUDED.admission_date,
            duration_days = EXCLUDED.duration_days,
            expected_discharge_date = EXCLUDED.expected_discharge_date,
            completed_at = EXCLUDED.completed_at,
            expiry_date = EXCLUDED.expiry_date,
            total_extended_days = EXCLUDED.total_extended_days,
            attendant_count = EXCLUDED.attendant_count,
            attendant_labels = EXCLUDED.attendant_labels,
            daily_rate = EXCLUDED.daily_rate,
            daily_rate_is_manual = EXCLUDED.daily_rate_is_manual,
            long_stay_daily_rate = EXCLUDED.long_stay_daily_rate,
            cost_override = EXCLUDED.cost_override,
            billing_summary = EXCLUDED.billing_summary,
            status = EXCLUDED.status,
            total_cost = EXCLUDED.total_cost,
            base_cost = EXCLUDED.base_cost,
            extra_attendant_cost = EXCLUDED.extra_attendant_cost,
            paid_amount = EXCLUDED.paid_amount,
            pending_amount = EXCLUDED.pending_amount,
            extensions = EXCLUDED.extensions,
            bed_number = EXCLUDED.bed_number,
            bed_id = EXCLUDED.bed_id,
            bed_label = EXCLUDED.bed_label,
            notes = EXCLUDED.notes,
            created_by = EXCLUDED.created_by,
            updated_at = EXCLUDED.updated_at
          RETURNING (xmax = 0) AS is_inserted`,
          [
            stayId,
            s.patientId,
            s.patientName || 'Patient',
            JSON.stringify(s.patientSnapshot || {}),
            s.roomId,
            s.roomNumber || 'Room',
            s.roomType || 'general',
            s.cycleId ? String(s.cycleId) : String(admission.getTime()),
            admission,
            duration,
            expected,
            parseDate(s.completedAt),
            expiry,
            parseInt(String(s.totalExtendedDays || 0), 10),
            parseInt(String(s.attendantCount || 0), 10),
            JSON.stringify(s.attendantLabels || []),
            s.dailyRate != null ? parseDecimal(s.dailyRate) : null,
            Boolean(s.dailyRateIsManual),
            s.longStayDailyRate != null ? parseDecimal(s.longStayDailyRate) : null,
            s.costOverride != null ? parseDecimal(s.costOverride) : null,
            JSON.stringify(s.billingSummary || {}),
            parseDecimal(s.totalCost),
            parseDecimal(s.baseCost),
            parseDecimal(s.extraAttendantCost),
            s.paidAmount != null ? parseDecimal(s.paidAmount) : null,
            s.pendingAmount != null ? parseDecimal(s.pendingAmount) : null,
            JSON.stringify(s.extensions || []),
            s.status || 'active',
            s.bedNumber != null ? parseInt(String(s.bedNumber), 10) : null,
            s.bedId || null,
            s.bedLabel || null,
            s.notes || null,
            creator,
            parseDate(s.createdAt) || new Date(),
            parseDate(s.updatedAt) || new Date(),
          ]
        );

        if (stayRes.rows[0]?.is_inserted) {
          stats.stays.imported++;
          reconciliation.stays.imported++;
        } else {
          stats.stays.updated++;
          reconciliation.stays.matched++;
        }
        await finishRecord();
      } catch (err: unknown) {
        await rejectRecord();
        stats.stays.failed++;
        reconciliation.stays.unresolved++;
        stats.warnings.push(`Stay rejected: ${safeError(err)}.`);
      }
    }

    for (const assignment of pendingBedAssignments) {
      await beginRecord();
      try {
        if (assignment.patientId && !validPatientIds.has(assignment.patientId)) {
          // Assigned patient deleted in source; leave bed available
          await finishRecord();
          continue;
        }
        if (assignment.stayId) {
          const stay = (await client.query('SELECT patient_id, room_id, bed_id, status FROM stays WHERE id = $1', [assignment.stayId])).rows[0];
          if (!stay || stay.status !== 'active' || stay.room_id !== assignment.roomId ||
              (stay.bed_id && stay.bed_id !== assignment.id) ||
              (assignment.patientId && stay.patient_id !== assignment.patientId)) {
            // A source assignment that cannot be proven active is a rejected
            // record, not a successful import with a silently cleared bed.
            stats.beds.assignmentFailures++;
            stats.warnings.push('Bed assignment rejected: dangling or completed stay reference.');
            await finishRecord();
            continue;
          }
        }
        await client.query('UPDATE room_beds SET current_patient_id=$2, current_stay_id=$3 WHERE id=$1',
          [assignment.id, assignment.patientId, assignment.stayId]);
        await finishRecord();
      } catch (err: unknown) {
        await rejectRecord();
        stats.beds.assignmentFailures++;
        stats.warnings.push(`Bed assignment rejected: ${safeError(err)}.`);
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Step 6: Attendance Records
    // ─────────────────────────────────────────────────────────────────────────
    log('[Importer] Step 6/11: Migrating daily attendance records...');
    const existingPgAttendance = new Set<string>();
    if (reconcileMode) {
      const existingAttRes = await client.query('SELECT id FROM attendance_records');
      for (const row of existingAttRes.rows || []) {
        if (row.id) existingPgAttendance.add(row.id);
      }
    }

    const importAttendanceBranch = async (branchName: string, kind: string) => {
      const root = data[branchName] || {};
      const branch = root.daily || root;
      for (const [dateStr, patientsMap] of Object.entries<any>(branch)) {
        if (!patientsMap || typeof patientsMap !== 'object') continue;
        for (const [patientId, payload] of Object.entries<any>(patientsMap)) {
          stats.attendance.processed++;
          reconciliation.attendance.source++;
          const recId = `${kind}/${dateStr}/${patientId}`;

          // Only insert if patient exists
          if (!validPatientIds.has(patientId)) {
            stats.attendance.missingPatientRefs++;
            stats.attendance.failed++;
            reconciliation.attendance.unresolved++;
            stats.warnings.push('Attendance rejected: missing or rejected patient reference.');
            continue;
          }

          if (reconcileMode && existingPgAttendance.has(recId)) {
            reconciliation.attendance.matched++;
            continue;
          }

          await beginRecord();
          try {
            if (!/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) throw new Error('Invalid attendance date');
            parseDate(dateStr);
            const attRes = await client.query(
              `INSERT INTO attendance_records (id, kind, attendance_date, patient_id, payload, created_at, updated_at)
               VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
               ON CONFLICT (id) DO UPDATE SET
                 payload = EXCLUDED.payload,
                 updated_at = CURRENT_TIMESTAMP
               RETURNING (xmax = 0) AS is_inserted`,
              [recId, kind, dateStr, patientId, JSON.stringify(payload || {})]
            );

            if (attRes.rows[0]?.is_inserted) {
              stats.attendance.imported++;
              reconciliation.attendance.imported++;
            } else {
              stats.attendance.updated++;
              reconciliation.attendance.matched++;
            }
            await finishRecord();
          } catch (err: unknown) {
            await rejectRecord();
            stats.attendance.failed++;
            reconciliation.attendance.unresolved++;
            stats.warnings.push(`Attendance rejected: ${safeError(err)}.`);
          }
        }
      }
    };

    await importAttendanceBranch('attendance', 'attendance');
    await importAttendanceBranch('attendant_attendance', 'attendant_attendance');

    // ─────────────────────────────────────────────────────────────────────────
    // Step 7: Payments & Payment History
    // ─────────────────────────────────────────────────────────────────────────
    log('[Importer] Step 7/11: Migrating payments and billing ledger...');
    const paymentsMap = new Map<string, any>();

    const paymentType = (p: any) => p.type || (cents(parseDecimal(p.amount)) < 0n ? 'refund' : 'payment');
    const paymentIdentity = (p: any) => JSON.stringify([
      p.patientId, p.cycleId || null, paymentType(p), parseDecimal(p.amount),
      parseDecimal(p.totalAmount ?? p.amount), parseDecimal(p.paidAmount ?? p.amount),
      parseDecimal(p.pendingAmount), p.paymentStatus || 'Paid', p.method || 'cash',
      parseDate(p.date ?? p.paymentDate)?.toISOString(), p.receiptNumber || null,
      p.checkNumber || null, p.bankName || null, p.transactionId || null,
    ]);
    const conflictingIds = new Set<string>();

    const embeddedPayments: Record<string, any> = {};
    for (const [patientId, patient] of Object.entries<any>(patientsBranch)) {
      const entries = patient?.payments;
      if (!entries || typeof entries !== 'object') continue;
      for (const [key, payment] of Object.entries<any>(entries)) {
        embeddedPayments[`${patientId}/${key}`] = payment && typeof payment === 'object'
          ? { ...payment, patientId: payment.patientId || patientId } : payment;
      }
    }

    for (const branch of [data.payments, data.paymentHistory, embeddedPayments]) {
      if (!branch || typeof branch !== 'object') continue;
      for (const [key, p] of Object.entries<any>(branch)) {
        if (!p || typeof p !== 'object') {
          stats.payments.processed++;
          stats.payments.failed++;
          reconciliation.payments.unresolved++;
          stats.warnings.push('Payment rejected: invalid record shape.');
          continue;
        }
        const id = typeof p.id === 'string' && p.id.length ? p.id : key;
        try {
          if (p.amount == null || !p.patientId || !(p.date ?? p.paymentDate)) throw new Error('Incomplete ledger record');
          parseDecimal(p.amount);
          const existing = paymentsMap.get(id);
          if (existing) {
            stats.payments.deduplicated++;
            reconciliation.payments.deduplicated++;
            const samePatient = existing.patientId === p.patientId;
            const sameAmount = cents(parseDecimal(existing.amount)) === cents(parseDecimal(p.amount));
            const d1 = parseDate(existing.date ?? existing.paymentDate)?.getTime();
            const d2 = parseDate(p.date ?? p.paymentDate)?.getTime();
            const sameDate = d1 != null && d1 === d2;
            if (samePatient && sameAmount && sameDate) {
              // Merge richer / updated fields
              if ((!existing.transactionId || existing.transactionId === 'MANUAL_ONLINE') && p.transactionId && p.transactionId !== 'MANUAL_ONLINE') {
                existing.transactionId = p.transactionId;
              }
              if (!existing.cycleId && p.cycleId) existing.cycleId = p.cycleId;
              if (!existing.receiptCycle && p.receiptCycle) existing.receiptCycle = p.receiptCycle;
              if (!existing.receiptNumber && p.receiptNumber) existing.receiptNumber = p.receiptNumber;
              if (!existing.checkNumber && p.checkNumber) existing.checkNumber = p.checkNumber;
              if (!existing.bankName && p.bankName) existing.bankName = p.bankName;
              if (!existing.type && p.type) existing.type = p.type;
              if (!existing.notes && p.notes) existing.notes = p.notes;
            } else {
              conflictingIds.add(id);
            }
          } else {
            paymentsMap.set(id, { ...p, id });
          }
        } catch {
          stats.payments.processed++;
          stats.payments.failed++;
          reconciliation.payments.unresolved++;
          stats.warnings.push('Payment rejected: incomplete or invalid ledger data.');
        }
      }
    }

    const patientsWithImportedPayments = new Set<string>();

    for (const [payId, p] of paymentsMap.entries()) {
      stats.payments.processed++;
      reconciliation.payments.source++;
      const amount = parseDecimal(p.amount);
      sourcePaymentCents += cents(amount);

      if (conflictingIds.has(payId)) {
        stats.payments.failed++;
        reconciliation.payments.conflicting++;
        stats.warnings.push('Payment rejected: conflicting duplicate ledger identity.');
        continue;
      }

      if (!validPatientIds.has(p.patientId)) {
        stats.payments.missingPatientRefs++;
        stats.payments.failed++;
        reconciliation.payments.unresolved++;
        stats.warnings.push('Payment rejected: missing or rejected patient reference.');
        continue;
      }

      await beginRecord();
      try {
        if (reconcileMode) {
          // Check for existing payment in PostgreSQL by exact ID, 64-char truncated ID, UTR, or receipt number
          const trimmedTx = typeof p.transactionId === 'string' && p.transactionId.trim().length > 0 && p.transactionId.trim() !== 'MANUAL_ONLINE' && p.transactionId.trim() !== 'same_transaction'
            ? p.transactionId.trim()
            : null;
          const trimmedReceipt = typeof p.receiptNumber === 'string' && p.receiptNumber.trim().length > 0
            ? p.receiptNumber.trim()
            : null;
          const prefix64 = payId.length > 64 ? payId.slice(0, 64) : payId;

          const existingMatchRes = await client.query(
            `SELECT * FROM payments
             WHERE id = $1
                OR (id = $2 AND patient_id = $3)
                OR ($4::varchar IS NOT NULL AND patient_id = $3 AND transaction_id = $4)
                OR ($5::varchar IS NOT NULL AND patient_id = $3 AND receipt_number = $5)
             LIMIT 1`,
            [payId, prefix64, p.patientId, trimmedTx, trimmedReceipt]
          );

          if (existingMatchRes.rows.length > 0) {
            const existingRow = existingMatchRes.rows[0];
            const existingAmount = parseDecimal(existingRow.amount);
            if (existingRow.patient_id !== p.patientId || cents(existingAmount) !== cents(amount)) {
              reconciliation.payments.conflicting++;
              throw new Error('Historical payment conflict');
            }
            stats.payments.unchanged++;
            reconciliation.payments.matched++;
            await finishRecord();
            continue;
          }

          // Infer cycleId from receiptCycle or patient's admission/stays when missing
          let resolvedCycleId: string | null = p.cycleId
            ? String(p.cycleId)
            : (p.receiptCycle ? String(p.receiptCycle) : null);
          if (!resolvedCycleId) {
            const patRowRes = await client.query('SELECT id, admission_date, registration_date FROM patients WHERE id = $1', [p.patientId]);
            const stayRowsRes = await client.query('SELECT * FROM stays WHERE patient_id = $1 ORDER BY admission_date ASC', [p.patientId]);
            if (patRowRes.rows.length > 0) {
              resolvedCycleId = receiptCycle(
                { cycle_id: null, payment_date: parseDate(p.date ?? p.paymentDate) || new Date() },
                patRowRes.rows[0],
                stayRowsRes.rows
              );
            }
          }

          const payRes = await client.query(
            `INSERT INTO payments (
              id, patient_id, cycle_id, type, amount, total_amount, paid_amount,
              pending_amount, payment_status, method, payment_date, receipt_number,
              check_number, bank_name, transaction_id, source, notes, created_at, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7,
              $8, $9, $10, $11, $12,
              $13, $14, $15, $16, $17, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            ) ON CONFLICT (id) DO NOTHING
            RETURNING id`,
            [
              payId,
              p.patientId,
              resolvedCycleId,
              paymentType(p),
              amount,
              p.totalAmount != null ? parseDecimal(p.totalAmount) : amount,
              p.paidAmount != null ? parseDecimal(p.paidAmount) : amount,
              p.pendingAmount != null ? parseDecimal(p.pendingAmount) : 0,
              p.paymentStatus || 'Paid',
              p.method || 'cash',
              parseDate(p.date ?? p.paymentDate),
              trimmedReceipt,
              p.checkNumber || null,
              p.bankName || null,
              typeof p.transactionId === 'string' && p.transactionId.trim().length > 0 ? p.transactionId.trim() : null,
              p.source || 'firebase_export',
              p.notes || null,
            ]
          );

          if (payRes.rowCount) {
            stats.payments.imported++;
            reconciliation.payments.imported++;
            patientsWithImportedPayments.add(p.patientId);
          } else {
            stats.payments.unchanged++;
            reconciliation.payments.matched++;
          }
          await finishRecord();
          continue;
        }

        const payRes = await client.query(
          `INSERT INTO payments (
            id, patient_id, cycle_id, type, amount, total_amount, paid_amount,
            pending_amount, payment_status, method, payment_date, receipt_number,
            check_number, bank_name, transaction_id, source, notes, created_at, updated_at
          ) VALUES (
            $1, $2, $3, $4, $5, $6, $7,
            $8, $9, $10, $11, $12,
            $13, $14, $15, $16, $17, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          ) ON CONFLICT (id) DO NOTHING
          RETURNING id`,
          [
            payId,
            p.patientId,
            p.cycleId || null,
            paymentType(p),
            amount,
            p.totalAmount != null ? parseDecimal(p.totalAmount) : amount,
            p.paidAmount != null ? parseDecimal(p.paidAmount) : amount,
            p.pendingAmount != null ? parseDecimal(p.pendingAmount) : 0,
            p.paymentStatus || 'Paid',
            p.method || 'cash',
            parseDate(p.date ?? p.paymentDate),
            p.receiptNumber || null,
            p.checkNumber || null,
            p.bankName || null,
            p.transactionId || null,
            p.source || 'firebase_export',
            p.notes || null,
          ]
        );

        if (payRes.rowCount) {
          stats.payments.imported++;
        } else {
          const existing = (await client.query('SELECT * FROM payments WHERE id = $1', [payId])).rows[0];
          if (!existing || paymentIdentity({
            patientId: existing.patient_id, cycleId: existing.cycle_id, type: existing.type,
            amount: existing.amount, totalAmount: existing.total_amount, paidAmount: existing.paid_amount,
            pendingAmount: existing.pending_amount, paymentStatus: existing.payment_status,
            method: existing.method, date: new Date(existing.payment_date).toISOString(),
            receiptNumber: existing.receipt_number, checkNumber: existing.check_number,
            bankName: existing.bank_name, transactionId: existing.transaction_id,
          }) !== paymentIdentity(p)) throw new Error('Historical payment conflict');
          stats.payments.unchanged++;
        }
        await finishRecord();
      } catch (err: unknown) {
        await rejectRecord();
        stats.payments.failed++;
        stats.warnings.push(`Payment rejected: ${safeError(err)}.`);
      }
    }

    if (reconcileMode && patientsWithImportedPayments.size > 0) {
      for (const pid of patientsWithImportedPayments) {
        const sumRes = await client.query(
          `SELECT COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0) AS paid,
                  COALESCE(SUM(amount), 0) AS net_paid
           FROM payments WHERE patient_id = $1`,
          [pid]
        );
        const netPaid = parseDecimal(sumRes.rows[0]?.net_paid ?? 0);
        await client.query(
          `UPDATE patients
           SET total_paid_amount = $2,
               current_due_amount = GREATEST(0, advance_billed_amount + attendance_charges - $2::numeric),
               payment_pending = (GREATEST(0, advance_billed_amount + attendance_charges - $2::numeric) > 0),
               payment_status = CASE
                 WHEN GREATEST(0, advance_billed_amount + attendance_charges - $2::numeric) <= 0 THEN 'Paid'
                 WHEN $2::numeric > 0 THEN 'Partially Paid'
                 ELSE 'Unpaid'
               END,
               updated_at = CURRENT_TIMESTAMP
           WHERE id = $1`,
          [pid, netPaid]
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Step 8: Patient & Attendant Photos
    // ─────────────────────────────────────────────────────────────────────────
    log('[Importer] Step 8/11: Migrating patient and attendant photos...');
    const photosBranch = data.patientPhotos || {};
    for (const [pid, obj] of Object.entries<any>(photosBranch)) {
      if (!obj || typeof obj !== 'object' || !validPatientIds.has(pid)) continue;

      if (obj.patient && typeof obj.patient === 'object' && obj.patient.data) {
        stats.photos.processed++;
        reconciliation.photos.source++;
        await beginRecord();
        try {
          const photoRef = `patientPhotos/${pid}/patient`;
          const res = await client.query(
            `INSERT INTO patient_photos (photo_ref, patient_id, photo_type, content_type, data, version, updated_at)
             VALUES ($1, $2, 'patient', $3, $4, $5, CURRENT_TIMESTAMP)
             ON CONFLICT (photo_ref) DO UPDATE SET
               data = EXCLUDED.data,
               content_type = EXCLUDED.content_type,
               version = EXCLUDED.version,
               updated_at = CURRENT_TIMESTAMP
             RETURNING (xmax = 0) AS is_inserted`,
            [
              photoRef,
              pid,
              obj.patient.contentType || (obj.patient.data.startsWith('data:image/png') ? 'image/png' : 'image/jpeg'),
              obj.patient.data,
              obj.patient.version != null ? BigInt(obj.patient.version) : 1n,
            ]
          );
          if (res.rows[0]?.is_inserted) {
            stats.photos.imported++;
            reconciliation.photos.imported++;
          } else {
            stats.photos.updated++;
            reconciliation.photos.matched++;
          }
          await finishRecord();
        } catch (err: unknown) {
          await rejectRecord();
          stats.photos.failed++;
          stats.warnings.push(`Photo rejected: ${safeError(err)}.`);
        }
      }

      if (obj.attendants && typeof obj.attendants === 'object') {
        for (const [attKey, attVal] of Object.entries<any>(obj.attendants)) {
          if (!attVal || typeof attVal !== 'object' || !attVal.data) continue;
          stats.photos.processed++;
          reconciliation.photos.source++;
          await beginRecord();
          try {
            const photoRef = `patientPhotos/${pid}/attendants/${attKey}`;
            const res = await client.query(
              `INSERT INTO patient_photos (photo_ref, patient_id, photo_type, content_type, data, version, updated_at)
               VALUES ($1, $2, 'attendant', $3, $4, $5, CURRENT_TIMESTAMP)
               ON CONFLICT (photo_ref) DO UPDATE SET
                 data = EXCLUDED.data,
                 content_type = EXCLUDED.content_type,
                 version = EXCLUDED.version,
                 updated_at = CURRENT_TIMESTAMP
               RETURNING (xmax = 0) AS is_inserted`,
              [
                photoRef,
                pid,
                attVal.contentType || (attVal.data.startsWith('data:image/png') ? 'image/png' : 'image/jpeg'),
                attVal.data,
                attVal.version != null ? BigInt(attVal.version) : 1n,
              ]
            );
            if (res.rows[0]?.is_inserted) {
              stats.photos.imported++;
              reconciliation.photos.imported++;
            } else {
              stats.photos.updated++;
              reconciliation.photos.matched++;
            }
            await finishRecord();
          } catch (err: unknown) {
            await rejectRecord();
            stats.photos.failed++;
            stats.warnings.push(`Attendant photo rejected: ${safeError(err)}.`);
          }
        }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Step 9: Expense Entries
    // ─────────────────────────────────────────────────────────────────────────
    log('[Importer] Step 9/11: Migrating expense entries...');
    const expenseBranch = data.expense_entries || {};
    for (const [expId, exp] of Object.entries<any>(expenseBranch)) {
      if (!exp || typeof exp !== 'object') continue;
      stats.expenses.processed++;
      await beginRecord();
      try {
        const creator = exp.createdBy && creatorUids.has(exp.createdBy) ? exp.createdBy : 'system_importer';
        const amount = parseDecimal(exp.totalAmount ?? exp.amount ?? 0);
        const paymentMethod = exp.paymentMethod || exp.paymentDetails?.paymentMethod || 'cash';
        const paidTo = exp.paidTo || exp.paymentDetails?.receivedBy || '';
        const expenseDate = parseDate(exp.expenseDate ?? exp.createdAt) || new Date();
        const details = {
          ...exp,
          ...(exp.details || {}),
        };
        const res = await client.query(
          `INSERT INTO expense_entries (id, category, amount, payment_method, paid_to, expense_date, description, receipt_url, created_by, created_at, details)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb)
           ON CONFLICT (id) DO UPDATE SET
             category = EXCLUDED.category,
             amount = EXCLUDED.amount,
             payment_method = EXCLUDED.payment_method,
             paid_to = EXCLUDED.paid_to,
             expense_date = EXCLUDED.expense_date,
             description = EXCLUDED.description,
             receipt_url = EXCLUDED.receipt_url,
             details = EXCLUDED.details
           RETURNING (xmax = 0) AS is_inserted`,
          [
            expId,
            exp.category || 'General',
            amount,
            paymentMethod,
            paidTo,
            expenseDate,
            exp.description || null,
            exp.receiptUrl || null,
            creator,
            parseDate(exp.createdAt) || expenseDate,
            JSON.stringify(details),
          ]
        );
        if (res.rows[0]?.is_inserted) stats.expenses.imported++;
        else stats.expenses.updated++;
        await finishRecord();
      } catch (err: unknown) {
        await rejectRecord();
        stats.expenses.failed++;
        stats.warnings.push(`Expense rejected: ${safeError(err)}.`);
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Step 10: Sponsorships
    // ─────────────────────────────────────────────────────────────────────────
    log('[Importer] Step 10/11: Migrating sponsorships...');
    const sponsorshipBranch = data.sponsorships || {};
    for (const [spId, sp] of Object.entries<any>(sponsorshipBranch)) {
      if (!sp || typeof sp !== 'object') continue;
      stats.sponsorships.processed++;
      await beginRecord();
      try {
        const amount = parseDecimal(sp.amount ?? 0);
        const spDate = parseDate(sp.sponsorshipDate ?? sp.createdAt) || new Date();
        const patientId = sp.patientId && validPatientIds.has(sp.patientId) ? sp.patientId : null;
        const details = {
          ...sp,
          ...(sp.details || {}),
        };
        const res = await client.query(
          `INSERT INTO sponsorships (id, sponsor_name, patient_id, patient_name, amount, sponsorship_date, payment_method, notes, created_at, details)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb)
           ON CONFLICT (id) DO UPDATE SET
             sponsor_name = EXCLUDED.sponsor_name,
             patient_id = EXCLUDED.patient_id,
             patient_name = EXCLUDED.patient_name,
             amount = EXCLUDED.amount,
             sponsorship_date = EXCLUDED.sponsorship_date,
             payment_method = EXCLUDED.payment_method,
             notes = EXCLUDED.notes,
             details = EXCLUDED.details
           RETURNING (xmax = 0) AS is_inserted`,
          [
            spId,
            sp.sponsorName || 'Sponsor',
            patientId,
            sp.patientName || null,
            amount,
            spDate,
            sp.paymentMethod || 'bank_transfer',
            sp.notes || null,
            parseDate(sp.createdAt) || spDate,
            JSON.stringify(details),
          ]
        );
        if (res.rows[0]?.is_inserted) stats.sponsorships.imported++;
        else stats.sponsorships.updated++;
        await finishRecord();
      } catch (err: unknown) {
        await rejectRecord();
        stats.sponsorships.failed++;
        stats.warnings.push(`Sponsorship rejected: ${safeError(err)}.`);
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Step 11: Settings (admin_settings/pricing and settings/*)
    // ─────────────────────────────────────────────────────────────────────────
    log('[Importer] Step 11/11: Migrating application settings...');
    const pricingDirect = data['admin_settings/pricing'];
    if (pricingDirect && typeof pricingDirect === 'object') {
      for (const [key, value] of Object.entries(pricingDirect)) {
        stats.settings.processed++;
        const result = await client.query(
          `INSERT INTO system_settings (category, settings_key, settings_value, updated_at)
           VALUES ('pricing', $1, $2, CURRENT_TIMESTAMP)
           ON CONFLICT (category, settings_key) DO UPDATE
           SET settings_value = EXCLUDED.settings_value, updated_at = CURRENT_TIMESTAMP
           RETURNING (xmax = 0) AS is_inserted`,
          [key, JSON.stringify(value)]
        );
        if (result.rows[0]?.is_inserted) stats.settings.imported++;
        else stats.settings.updated++;
      }
    }

    const adminSettings = data.admin_settings || {};
    if (adminSettings && typeof adminSettings === 'object') {
      for (const [cat, catObj] of Object.entries(adminSettings)) {
        if (catObj && typeof catObj === 'object') {
          for (const [key, value] of Object.entries(catObj as Record<string, any>)) {
            stats.settings.processed++;
            const result = await client.query(
              `INSERT INTO system_settings (category, settings_key, settings_value, updated_at)
               VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
               ON CONFLICT (category, settings_key) DO UPDATE
               SET settings_value = EXCLUDED.settings_value, updated_at = CURRENT_TIMESTAMP
               RETURNING (xmax = 0) AS is_inserted`,
              [cat, key, JSON.stringify(value)]
            );
            if (result.rows[0]?.is_inserted) stats.settings.imported++;
            else stats.settings.updated++;
          }
        }
      }
    }

    if (data.settings && typeof data.settings === 'object') {
      for (const [cat, catObj] of Object.entries(data.settings)) {
        if (catObj && typeof catObj === 'object') {
          for (const [key, value] of Object.entries(catObj as Record<string, any>)) {
            stats.settings.processed++;
            const result = await client.query(
              `INSERT INTO system_settings (category, settings_key, settings_value, updated_at)
               VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
               ON CONFLICT (category, settings_key) DO UPDATE
               SET settings_value = EXCLUDED.settings_value, updated_at = CURRENT_TIMESTAMP
               RETURNING (xmax = 0) AS is_inserted`,
              [cat, key, JSON.stringify(value)]
            );
            if (result.rows[0]?.is_inserted) stats.settings.imported++;
            else stats.settings.updated++;
          }
        }
      }
    }

    // Financial reconciliation queries from DB
    stats.financials.sourceTotalPayments = Number(sourcePaymentCents) / 100;
    stats.financials.sourceTotalPatientPaid = Number(sourcePaidCents) / 100;
    stats.financials.sourceTotalPatientDue = Number(sourceDueCents) / 100;
    const dbPaymentsSum = await client.query('SELECT COALESCE(SUM(amount), 0) AS total FROM payments WHERE id = ANY($1::varchar[])', [[...paymentsMap.keys()]]);
    stats.financials.dbTotalPayments = parseFloat(String(dbPaymentsSum.rows[0]?.total || 0));

    const dbPatientSums = await client.query(
      'SELECT COALESCE(SUM(total_paid_amount), 0) AS paid, COALESCE(SUM(current_due_amount), 0) AS due FROM patients WHERE id = ANY($1::varchar[])',
      [Object.keys(patientsBranch)]
    );
    stats.financials.dbTotalPatientPaid = parseFloat(String(dbPatientSums.rows[0]?.paid || 0));
    stats.financials.dbTotalPatientDue = parseFloat(String(dbPatientSums.rows[0]?.due || 0));

    const strictCheck = options.strict !== undefined ? options.strict : !reconcileMode;
    const shouldRollback = options.dryRun !== false || (strictCheck && stats.warnings.length > 0);
    if (shouldRollback) {
      log(stats.warnings.length > 0
        ? '[Importer] Rejected records detected: rolling back the entire import. Counts describe attempted writes.'
        : '[Importer] Dry-run mode enabled: rolling back transaction (no database modifications preserved).');
      await client.query('ROLLBACK');
    } else {
      await client.query('COMMIT');
      stats.committed = true;
      log('[Importer] Import committed. Review rejected records and reconciliation before cutover.');
    }
  } catch (err: unknown) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
    stats.durationMs = Date.now() - startTime;
  }

  return stats;
}
