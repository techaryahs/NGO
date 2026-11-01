import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { buildApp } from '../src/app.js';
import * as dbModule from '../src/db/index.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

describe('Admission Date Alignment & Fallback Specification', () => {
  let app: ReturnType<typeof buildApp>;

  let patientsMap: Map<string, any>;
  let staysMap: Map<string, any>;
  let roomsMap: Map<string, any>;
  let roomBedsMap: Map<string, any>;

  beforeEach(() => {
    vi.restoreAllMocks();
    installTestFirebaseKeys();
    app = buildApp({ logger: false });

    patientsMap = new Map();
    staysMap = new Map();
    roomsMap = new Map();
    roomBedsMap = new Map();

    // Seed default room and bed
    roomsMap.set('room_101', {
      id: 'room_101',
      room_number: '101',
      room_identifier: '101',
      floor: 1,
      room_type: 'general',
      status: 'available',
      max_attendants: 2,
      current_attendants: 0,
      total_beds: 2,
      occupied_beds: 0,
      version: 1,
    });

    roomBedsMap.set('bed_101_1', {
      id: 'bed_101_1',
      room_id: 'room_101',
      bed_label: 'B1',
      bed_number: 1,
      status: 'available',
      current_patient_id: null,
      current_stay_id: null,
      last_cleaned: null,
    });

    const mockQuery = vi.fn(async (sql: string, params: unknown[] = []) => {
      const trimmed = sql.trim();

      if (/^(BEGIN|COMMIT|ROLLBACK)$/i.test(trimmed)) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('pg_advisory_xact_lock')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('FROM users')) {
        return {
          rows: [{ id: 'admin-1', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1,
        };
      }
      if (trimmed.includes('FROM system_settings')) {
        return {
          rows: [
            { settings_key: 'general_bed_daily_rate', settings_value: '50' },
            { settings_key: 'private_room_daily_rate', settings_value: '300' },
          ],
          rowCount: 2,
        };
      }
      if (trimmed.includes('system_counters')) {
        return { rows: [{ current_value: '1001' }], rowCount: 1 };
      }
      if (trimmed.includes('SELECT id FROM patients WHERE LOWER(registration_number)')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('FROM stays s') && trimmed.includes('WHERE s.patient_id = $1') && trimmed.includes("s.status = 'active'")) {
        const pId = params[0] as string;
        const activeStays = Array.from(staysMap.values()).filter(s => s.patient_id === pId && s.status === 'active');
        return { rows: activeStays, rowCount: activeStays.length };
      }
      if (trimmed.includes('SELECT id FROM stays WHERE patient_id=$1 AND status=\'active\'')) {
        const pId = params[0] as string;
        const active = Array.from(staysMap.values()).filter(s => s.patient_id === pId && s.status === 'active');
        return { rows: active.map(s => ({ id: s.id })), rowCount: active.length };
      }
      if (trimmed.includes('SELECT id FROM stays WHERE room_id=$1 AND status=\'active\'')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('SELECT id FROM room_beds WHERE room_id=$1')) {
        const rId = params[0] as string;
        const beds = Array.from(roomBedsMap.values()).filter(b => b.room_id === rId);
        return { rows: beds.map(b => ({ id: b.id })), rowCount: beds.length };
      }
      if (trimmed.includes('SELECT * FROM room_beds WHERE id=$1 AND room_id=$2 FOR UPDATE')) {
        const bedId = params[0] as string;
        const bed = roomBedsMap.get(bedId);
        return { rows: bed ? [bed] : [], rowCount: bed ? 1 : 0 };
      }
      if (trimmed.includes('UPDATE room_beds SET')) {
        return { rows: [], rowCount: 1 };
      }
      if (trimmed.includes('SELECT id FROM rooms WHERE id=ANY')) {
        return { rows: [{ id: 'room_101' }], rowCount: 1 };
      }
      if (trimmed.includes('SELECT * FROM rooms WHERE id=$1 FOR UPDATE')) {
        const rId = params[0] as string;
        const room = roomsMap.get(rId);
        return { rows: room ? [room] : [], rowCount: room ? 1 : 0 };
      }
      if (trimmed.includes('SELECT id,name,relation FROM patient_attendants WHERE patient_id=$1')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('SELECT * FROM patient_attendants WHERE patient_id=$1')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('SELECT patient_snapshot FROM stays WHERE patient_id=$1 AND cycle_id=$2')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('SELECT * FROM stays WHERE patient_id = ANY') || trimmed.includes('SELECT * FROM stays WHERE patient_id=$1')) {
        const pId = params[0];
        const pIds = Array.isArray(pId) ? pId : [pId];
        const matching = Array.from(staysMap.values()).filter(s => pIds.includes(s.patient_id));
        return { rows: matching, rowCount: matching.length };
      }
      if (trimmed.includes('SELECT * FROM payments WHERE patient_id')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('SELECT * FROM billing_corrections WHERE patient_id')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('attendance_records WHERE patient_id')) {
        return { rows: [], rowCount: 0 };
      }
      if (trimmed.includes('INSERT INTO patients')) {
        const row: any = {
          id: params[0],
          full_name: params[1],
          search_key: params[2],
          date_of_birth: params[3],
          age: params[4],
          gender: params[5],
          contact_number: params[6],
          emergency_contact: params[7],
          emergency_contact_name: params[8],
          medical_condition: params[9],
          allergies: params[10],
          blood_type: params[11],
          admission_date: params[12],
          status: params[13],
          discharge_date: params[14],
          exit_date: params[15],
          room_id: params[16],
          room_number: params[17],
          floor: params[18],
          bed_ids: typeof params[19] === 'string' ? JSON.parse(params[19]) : params[19],
          bed_labels: typeof params[20] === 'string' ? JSON.parse(params[20]) : params[20],
          lobby: params[21],
          address: params[22],
          registration_number: params[23],
          registration_date: params[24],
          total_paid_amount: params[32] || 0,
          current_due_amount: params[33] || 0,
          refund_due_amount: params[34] || 0,
          total_refund_due_amount: params[35] || 0,
          total_refunded_amount: params[36] || 0,
          admission_balances: typeof params[37] === 'string' ? JSON.parse(params[37] || '{}') : params[37],
          payment_due_date: params[38],
          is_advance_period: params[39],
          advance_billed_amount: params[40] || 0,
          billing_amount_override: params[41],
          attendance_charges: params[42] || 0,
          total_present_days: params[43] || 0,
          total_absent_days: params[44] || 0,
          max_stay_days: params[45] || 60,
          created_by: params[55],
          created_at: new Date(),
          updated_at: new Date(),
          version: 1,
        };
        patientsMap.set(row.id, row);
        return { rows: [row], rowCount: 1 };
      }
      if (trimmed.includes('UPDATE patients SET registration_fingerprint=$2 WHERE id=$1')) {
        const p = patientsMap.get(params[0] as string);
        if (p) p.registration_fingerprint = params[1];
        return { rows: [], rowCount: 1 };
      }
      if (trimmed.includes('UPDATE patients SET') && trimmed.includes('WHERE id=$1')) {
        const p = patientsMap.get(params[0] as string);
        if (p) {
          // If update for rejoin:
          if (trimmed.includes("admission_date=$2,status='active'")) {
            p.admission_date = params[1];
            p.status = 'active';
            p.discharge_date = null;
            p.exit_date = params[2];
          }
        }
        return { rows: p ? [p] : [], rowCount: p ? 1 : 0 };
      }
      if (trimmed.includes('SELECT * FROM patients WHERE id = $1 FOR UPDATE') || trimmed.includes('SELECT * FROM patients WHERE id=$1 FOR UPDATE')) {
        const p = patientsMap.get(params[0] as string);
        return { rows: p ? [p] : [], rowCount: p ? 1 : 0 };
      }
      if (trimmed.includes('SELECT * FROM patients WHERE id = $1') || trimmed.includes('SELECT * FROM patients WHERE id=$1')) {
        const p = patientsMap.get(params[0] as string);
        return { rows: p ? [p] : [], rowCount: p ? 1 : 0 };
      }
      if (trimmed.includes('INSERT INTO stays')) {
        const stayRow: any = {
          id: params[0],
          patient_id: params[1],
          patient_name: params[2],
          patient_snapshot: typeof params[3] === 'string' ? JSON.parse(params[3]) : params[3],
          room_id: params[4],
          room_number: params[5],
          room_type: params[6],
          cycle_id: params[7],
          admission_date: params[8],
          duration_days: params[9],
          expected_discharge_date: params[10],
          completed_at: params[11],
          expiry_date: params[12],
          total_extended_days: params[13],
          attendant_count: params[14],
          attendant_labels: typeof params[15] === 'string' ? JSON.parse(params[15]) : params[15],
          daily_rate: params[16],
          daily_rate_is_manual: params[17],
          long_stay_daily_rate: params[18],
          cost_override: params[19],
          billing_summary: typeof params[20] === 'string' ? JSON.parse(params[20]) : params[20],
          total_cost: params[21],
          base_cost: params[22],
          extra_attendant_cost: params[23],
          paid_amount: params[24],
          pending_amount: params[25],
          extensions: typeof params[26] === 'string' ? JSON.parse(params[26]) : params[26],
          status: params[27],
          bed_number: params[28],
          bed_id: params[29],
          bed_label: params[30],
          notes: params[31],
          created_by: params[32],
          created_at: new Date(),
          updated_at: new Date(),
        };
        staysMap.set(stayRow.id, stayRow);
        return { rows: [stayRow], rowCount: 1 };
      }
      if (trimmed.includes('UPDATE rooms SET')) {
        return { rows: [], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    vi.spyOn(dbModule, 'getClient').mockResolvedValue({
      query: mockQuery,
      release: vi.fn(),
    } as any);

    vi.spyOn(dbModule, 'query').mockImplementation(mockQuery as any);
  });

  afterEach(async () => {
    await app.close();
    vi.restoreAllMocks();
  });

  const authHeader = { authorization: `Bearer ${signedTestToken('admin-1')}` };

  // TEST 1
  it('1. POST /patients with registrationDate 3 days in the past and no admissionDate → 201; patients.admission_date equals registration instant; stay admission_date and stay.cycle_id follow it', async () => {
    const threeDaysAgoMs = Date.now() - 3 * 86400000;
    const registrationDateIso = new Date(threeDaysAgoMs).toISOString();

    const res = await app.inject({
      method: 'POST',
      url: '/api/patients',
      headers: authHeader,
      payload: {
        fullName: 'Backdated Patient',
        dateOfBirth: '1990-01-01',
        gender: 'male',
        contactNumber: '9999999999',
        emergencyContact: '8888888888',
        emergencyContactName: 'Contact',
        medicalCondition: 'Condition',
        registrationDate: registrationDateIso,
        stays: [
          {
            roomId: 'room_101',
            roomNumber: '101',
            roomType: 'general',
            bedId: 'bed_101_1',
            durationDays: 7,
          },
        ],
      },
    });

    expect(res.statusCode).toBe(201);
    const body = JSON.parse(res.body);

    // Patient admissionDate equals registration instant
    const patientRow = Array.from(patientsMap.values())[0];
    expect(patientRow).toBeDefined();
    expect(new Date(patientRow.admission_date).getTime()).toBe(new Date(registrationDateIso).getTime());
    expect(body.admissionDate).toBe(new Date(registrationDateIso).getTime());

    // Stay admission_date and cycle_id follow registrationDate
    const stayRow = Array.from(staysMap.values())[0];
    expect(stayRow).toBeDefined();
    expect(new Date(stayRow.admission_date).getTime()).toBe(new Date(registrationDateIso).getTime());
    expect(stayRow.cycle_id).toBe(String(new Date(registrationDateIso).getTime()));
  });

  // TEST 2
  it('2. POST /patients with BOTH registrationDate (past) and admissionDate (now) → admission follows registrationDate everywhere (patient + stay + cycle)', async () => {
    const pastDateMs = Date.now() - 5 * 86400000;
    const registrationDateIso = new Date(pastDateMs).toISOString();
    const admissionDateNowIso = new Date().toISOString();

    const res = await app.inject({
      method: 'POST',
      url: '/api/patients',
      headers: authHeader,
      payload: {
        fullName: 'Dual Date Patient',
        dateOfBirth: '1985-06-15',
        gender: 'female',
        contactNumber: '9999999999',
        emergencyContact: '8888888888',
        emergencyContactName: 'Contact',
        medicalCondition: 'Condition',
        registrationDate: registrationDateIso,
        admissionDate: admissionDateNowIso,
        stays: [
          {
            roomId: 'room_101',
            roomNumber: '101',
            roomType: 'general',
            bedId: 'bed_101_1',
            admissionDate: admissionDateNowIso, // stay item carrying admissionDate (now)
            durationDays: 5,
          },
        ],
      },
    });

    expect(res.statusCode).toBe(201);

    // Patient admission follows registrationDate, NOT admissionDate (now)
    const patientRow = Array.from(patientsMap.values())[0];
    expect(new Date(patientRow.admission_date).getTime()).toBe(new Date(registrationDateIso).getTime());

    // Stay admission and cycle follow registrationDate everywhere
    const stayRow = Array.from(staysMap.values())[0];
    expect(stayRow).toBeDefined();
    expect(new Date(stayRow.admission_date).getTime()).toBe(new Date(registrationDateIso).getTime());
    expect(stayRow.cycle_id).toBe(String(new Date(registrationDateIso).getTime()));
  });

  // TEST 3
  it('3. POST /patients with neither date → admission is approximately now (previous behaviour preserved)', async () => {
    const beforeCall = Date.now();

    const res = await app.inject({
      method: 'POST',
      url: '/api/patients',
      headers: authHeader,
      payload: {
        fullName: 'Undated Patient',
        dateOfBirth: '2000-01-01',
        gender: 'other',
        contactNumber: '9999999999',
        emergencyContact: '8888888888',
        emergencyContactName: 'Contact',
        medicalCondition: 'Condition',
      },
    });

    const afterCall = Date.now();
    expect(res.statusCode).toBe(201);
    const body = JSON.parse(res.body);

    const patientRow = Array.from(patientsMap.values())[0];
    expect(patientRow).toBeDefined();
    const admissionEpoch = new Date(patientRow.admission_date).getTime();
    expect(admissionEpoch).toBeGreaterThanOrEqual(beforeCall - 1000);
    expect(admissionEpoch).toBeLessThanOrEqual(afterCall + 1000);
    expect(body.admissionDate).toBe(admissionEpoch);
  });

  // TEST 4
  it('4. POST /patients with exitDate before the chosen registrationDate → 400', async () => {
    const regDate = new Date('2026-10-25T10:00:00.000Z');
    const exitDateBefore = new Date('2026-10-20T10:00:00.000Z');

    const res = await app.inject({
      method: 'POST',
      url: '/api/patients',
      headers: authHeader,
      payload: {
        fullName: 'Invalid Exit Patient',
        dateOfBirth: '1992-03-10',
        gender: 'male',
        contactNumber: '9999999999',
        emergencyContact: '8888888888',
        emergencyContactName: 'Contact',
        medicalCondition: 'Condition',
        registrationDate: regDate.toISOString(),
        exitDate: exitDateBefore.toISOString(),
      },
    });

    expect(res.statusCode).toBe(400);
    const body = JSON.parse(res.body);
    expect(body.message).toBe('Planned exit cannot precede admission');
  });

  // TEST 5
  it('5. POST /stays without admissionDate for an existing patient → the stay admission_date equals patient stored admission_date, not now', async () => {
    const storedAdmissionDate = new Date('2026-10-15T08:30:00.000Z');
    const existingPatient = {
      id: 'patient_existing_1',
      full_name: 'Existing Stored Patient',
      admission_date: storedAdmissionDate,
      status: 'active',
      registration_number: 'REG-555',
    };
    patientsMap.set(existingPatient.id, existingPatient);

    const res = await app.inject({
      method: 'POST',
      url: '/api/stays',
      headers: authHeader,
      payload: {
        patientId: 'patient_existing_1',
        roomId: 'room_101',
        roomNumber: '101',
        roomType: 'general',
        bedId: 'bed_101_1',
        durationDays: 7,
      },
    });

    expect(res.statusCode).toBe(201);
    const body = JSON.parse(res.body);

    const stayRow = Array.from(staysMap.values())[0];
    expect(stayRow).toBeDefined();
    expect(new Date(stayRow.admission_date).getTime()).toBe(storedAdmissionDate.getTime());
    expect(body.admissionDate).toBe(storedAdmissionDate.getTime());
  });

  // TEST 6
  it('6. Rejoin with an explicit admissionDate behaves exactly as before (regression)', async () => {
    const oldAdmission = new Date('2026-10-01T00:00:00.000Z');
    const oldDischarge = new Date('2026-10-10T00:00:00.000Z');
    const dischargedPatient = {
      id: 'patient_discharged_1',
      full_name: 'Discharged Patient',
      admission_date: oldAdmission,
      discharge_date: oldDischarge,
      status: 'discharged',
      registration_number: 'REG-999',
    };
    patientsMap.set(dischargedPatient.id, dischargedPatient);

    const explicitRejoinAdmission = new Date('2026-10-20T10:00:00.000Z');

    const res = await app.inject({
      method: 'POST',
      url: `/api/patients/${dischargedPatient.id}/rejoin`,
      headers: authHeader,
      payload: {
        requestId: 'stay_rejoin_1',
        admissionDate: explicitRejoinAdmission.toISOString(),
        roomId: 'room_101',
        roomNumber: '101',
        roomType: 'general',
        bedId: 'bed_101_1',
        exitDate: null,
        exitDateUnconfirmed: true,
      },
    });

    expect(res.statusCode).toBe(201);

    const stayRow = Array.from(staysMap.values())[0];
    expect(stayRow).toBeDefined();
    expect(new Date(stayRow.admission_date).getTime()).toBe(explicitRejoinAdmission.getTime());
    expect(stayRow.cycle_id).toBe(String(explicitRejoinAdmission.getTime()));
  });

  // Additional check: POST /patients/register (atomic endpoint) behaves identically
  it('7. POST /patients/register with registrationDate in the past and stay item admissionDate → forced to registrationDate', async () => {
    const threeDaysAgoMs = Date.now() - 3 * 86400000;
    const registrationDateIso = new Date(threeDaysAgoMs).toISOString();

    const res = await app.inject({
      method: 'POST',
      url: '/api/patients/register',
      headers: authHeader,
      payload: {
        fullName: 'Atomic Registration Patient',
        dateOfBirth: '1991-02-02',
        gender: 'female',
        contactNumber: '9999999999',
        emergencyContact: '8888888888',
        emergencyContactName: 'Contact',
        medicalCondition: 'Condition',
        registrationDate: registrationDateIso,
        stays: [
          {
            roomId: 'room_101',
            roomNumber: '101',
            roomType: 'general',
            bedId: 'bed_101_1',
            admissionDate: new Date().toISOString(), // should be overridden by chosen registrationDate
            durationDays: 7,
          },
        ],
      },
    });

    expect(res.statusCode).toBe(201);
    const body = JSON.parse(res.body);

    const patientRow = Array.from(patientsMap.values())[0];
    expect(patientRow).toBeDefined();
    expect(new Date(patientRow.admission_date).getTime()).toBe(new Date(registrationDateIso).getTime());
    expect(body.admissionDate).toBe(new Date(registrationDateIso).getTime());

    const stayRow = Array.from(staysMap.values())[0];
    expect(stayRow).toBeDefined();
    expect(new Date(stayRow.admission_date).getTime()).toBe(new Date(registrationDateIso).getTime());
    expect(stayRow.cycle_id).toBe(String(new Date(registrationDateIso).getTime()));
  });

  it('8. POST /patients/register with exitDate before chosen registrationDate → 400', async () => {
    const regDate = new Date('2026-10-25T10:00:00.000Z');
    const exitDateBefore = new Date('2026-10-20T10:00:00.000Z');

    const res = await app.inject({
      method: 'POST',
      url: '/api/patients/register',
      headers: authHeader,
      payload: {
        fullName: 'Invalid Atomic Exit Patient',
        dateOfBirth: '1992-03-10',
        gender: 'male',
        contactNumber: '9999999999',
        emergencyContact: '8888888888',
        emergencyContactName: 'Contact',
        medicalCondition: 'Condition',
        registrationDate: regDate.toISOString(),
        exitDate: exitDateBefore.toISOString(),
      },
    });

    expect(res.statusCode).toBe(400);
    const body = JSON.parse(res.body);
    expect(body.message).toBe('Planned exit cannot precede admission');
  });
});
