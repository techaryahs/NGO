import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { buildApp } from '../src/app.js';
import * as dbModule from '../src/db/index.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';
import { formatPatient, derivePlacement } from '../src/routes/patients.js';

describe('Patient Placement Derivation (Read Path)', () => {
  let app: ReturnType<typeof buildApp>;

  beforeEach(() => {
    vi.restoreAllMocks();
    vi.spyOn(dbModule, 'getClient').mockResolvedValue({
      query: async (sql: string, params?: unknown[]) =>
        /^(BEGIN|COMMIT|ROLLBACK)/.test(sql)
          ? { rows: [], rowCount: 0 }
          : dbModule.query(sql, params),
      release: vi.fn(),
    } as any);
    installTestFirebaseKeys();
    app = buildApp();
  });

  afterEach(async () => {
    await app.close();
    vi.restoreAllMocks();
  });

  // Base raw patient row representing a patient
  const baseRawPatient: any = {
    id: 'p_test_1',
    version: 1,
    full_name: 'Test Patient',
    search_key: 'test patient',
    date_of_birth: '1990-01-01',
    age: 34,
    gender: 'male',
    contact_number: '9876543210',
    emergency_contact: '9876543211',
    emergency_contact_name: 'Emergency Contact',
    medical_condition: 'Routine Care',
    allergies: null,
    blood_type: 'O+',
    admission_date: new Date('2026-10-01T10:00:00.000Z'),
    status: 'active',
    discharge_date: null,
    exit_date: null,
    room_id: null,
    room_number: null,
    floor: null,
    bed_ids: [],
    bed_labels: [],
    lobby: null,
    address: '123 Main St',
    registration_number: '1001',
    registration_date: new Date('2026-10-01T10:00:00.000Z'),
    pan_card_number: null,
    aadhaar_card_number: null,
    receipt_number: null,
    mode_of_payment: 'Cash',
    uti_number: null,
    payment_pending: false,
    payment_status: 'Paid',
    total_paid_amount: 0,
    current_due_amount: 0,
    refund_due_amount: 0,
    total_refund_due_amount: 0,
    total_refunded_amount: 0,
    admission_balances: {},
    payment_due_date: null,
    is_advance_period: true,
    advance_billed_amount: 0,
    billing_amount_override: null,
    attendance_charges: 0,
    total_present_days: 0,
    total_absent_days: 0,
    max_stay_days: 60,
    extension_approved: false,
    extension_days: 0,
    extension_reason: null,
    approved_by: null,
    approved_date: null,
    photo_data_url: null,
    photo_ref: null,
    photo_file_name: null,
    notes: null,
    created_by: 'system',
    created_at: new Date('2026-10-01T10:00:00.000Z'),
    updated_at: new Date('2026-10-01T10:00:00.000Z'),
  };

  it('Check 1 (unit): a rejoined lobby patient whose stored floor AND lobby are both NULL returns correct lobby and floor', () => {
    // Stored row has floor = null, lobby = null
    const storedRow = {
      ...baseRawPatient,
      status: 'active',
      floor: null,
      lobby: null,
      room_id: null,
      room_number: null,
      bed_ids: [],
      bed_labels: [],
    };

    const activeLobbyStay = {
      id: 's_lobby_1',
      room_id: 'lobby:1D Lobby 1',
      room_number: '1D Lobby 1',
      room_type: 'lobby',
      status: 'active',
    };

    const formatted = formatPatient(storedRow, [], [], [activeLobbyStay]);
    expect(formatted.lobby).toBe('1D Lobby 1');
    expect(formatted.floor).toBe(1);
    expect(formatted.roomId).toBeNull();
    expect(formatted.roomNumber).toBeNull();
    expect(formatted.bedIds).toEqual([]);
    expect(formatted.bedLabels).toEqual([]);

    // Test with Floor 2 lobby
    const activeLobby2Stay = {
      id: 's_lobby_2',
      room_id: 'lobby:2E Lobby 2',
      room_number: '2E Lobby 2',
      room_type: 'lobby',
      status: 'active',
    };
    const formatted2 = formatPatient(storedRow, [], [], [activeLobby2Stay]);
    expect(formatted2.lobby).toBe('2E Lobby 2');
    expect(formatted2.floor).toBe(2);
    expect(formatted2.roomId).toBeNull();
    expect(formatted2.roomNumber).toBeNull();
  });

  it('Check 2 (unit): an active room patient returns room/floor/beds matching their stay even if row copy is stale', () => {
    // Stale row copy in patients table
    const staleRow = {
      ...baseRawPatient,
      status: 'active',
      room_id: 'old_room_99',
      room_number: '99',
      floor: 9,
      bed_ids: ['old_bed_99'],
      bed_labels: ['Bed 99'],
      lobby: 'Old Lobby',
    };

    const activeRoomStay = {
      id: 's_room_1',
      room_id: 'room_101',
      room_number: '101',
      room_type: 'general',
      bed_id: 'b_101_1',
      bed_label: 'Bed A',
      status: 'active',
      room_floor: 1, // from rooms table join
    };

    const formatted = formatPatient(staleRow, [], [], [activeRoomStay]);
    expect(formatted.roomId).toBe('room_101');
    expect(formatted.roomNumber).toBe('101');
    expect(formatted.floor).toBe(1);
    expect(formatted.bedIds).toEqual(['b_101_1']);
    expect(formatted.bedLabels).toEqual(['Bed A']);
    expect(formatted.lobby).toBeNull();
  });

  it('Check 2b (unit): multi-bed active stays gather all bedIds and bedLabels in that room', () => {
    const staleRow = {
      ...baseRawPatient,
      status: 'active',
      room_id: 'old_room',
      bed_ids: ['stale_bed'],
      bed_labels: ['Stale Bed'],
    };

    const activeStays = [
      {
        id: 's_1',
        room_id: 'room_202',
        room_number: '202',
        bed_id: 'b_202_1',
        bed_label: 'Bed 202-A',
        status: 'active',
        room_floor: 2,
      },
      {
        id: 's_2',
        room_id: 'room_202',
        room_number: '202',
        bed_id: 'b_202_2',
        bed_label: 'Bed 202-B',
        status: 'active',
        room_floor: 2,
      },
    ];

    const formatted = formatPatient(staleRow, [], [], activeStays);
    expect(formatted.roomId).toBe('room_202');
    expect(formatted.roomNumber).toBe('202');
    expect(formatted.floor).toBe(2);
    expect(formatted.bedIds).toEqual(['b_202_1', 'b_202_2']);
    expect(formatted.bedLabels).toEqual(['Bed 202-A', 'Bed 202-B']);
    expect(formatted.lobby).toBeNull();
  });

  it('Check 3 (unit): a discharged patient payload is unchanged vs stored row (byte-identical)', () => {
    const dischargedRow = {
      ...baseRawPatient,
      status: 'discharged',
      discharge_date: new Date('2026-10-15T12:00:00.000Z'),
      room_id: null,
      room_number: null,
      floor: null,
      bed_ids: [],
      bed_labels: [],
      lobby: null,
    };

    // Stays list contains only completed stays
    const completedStays = [
      {
        id: 's_old',
        room_id: 'room_101',
        room_number: '101',
        bed_id: 'b_1',
        bed_label: 'Bed 1',
        status: 'completed',
        room_floor: 1,
      },
    ];

    const beforePayload = formatPatient(dischargedRow, []);
    const afterPayload = formatPatient(dischargedRow, [], [], completedStays);

    expect(afterPayload).toEqual(beforePayload);
    expect(JSON.stringify(afterPayload)).toBe(JSON.stringify(beforePayload));
  });

  it('Check 1 (route): GET /patients/:id returns correct lobby and floor for rejoined lobby patient with NULL stored fields', async () => {
    const testPatientId = 'p_lobby_test';
    const lobbyStoredPatient = {
      ...baseRawPatient,
      id: testPatientId,
      status: 'active',
      floor: null,
      lobby: null,
      room_id: null,
      room_number: null,
      bed_ids: [],
      bed_labels: [],
    };

    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string, params?: unknown[]) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'admin-user', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('FROM patients WHERE id = $1')) {
        return { rows: [lobbyStoredPatient], rowCount: 1, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM patient_attendants WHERE patient_id = $1')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM payments WHERE patient_id=$1')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM stays s') && sql.includes("s.status = 'active'")) {
        return {
          rows: [
            {
              id: 's_rejoin_lobby',
              room_id: 'lobby:1D Lobby 1',
              room_number: '1D Lobby 1',
              room_type: 'lobby',
              bed_id: null,
              bed_label: null,
              status: 'active',
              room_floor: 0,
            },
          ],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('FROM stays WHERE patient_id = $1')) {
        return {
          rows: [
            {
              id: 's_rejoin_lobby',
              patient_id: testPatientId,
              room_id: 'lobby:1D Lobby 1',
              room_number: '1D Lobby 1',
              room_type: 'lobby',
              status: 'active',
              admission_date: new Date('2026-10-01'),
              duration_days: 7,
              expected_discharge_date: new Date('2026-10-08'),
              expiry_date: new Date('2026-10-08'),
              total_cost: 0,
              base_cost: 0,
            },
          ],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('FROM attendance_records')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM system_settings')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM billing_corrections')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'GET',
      url: `/api/patients/${testPatientId}`,
      headers: {
        authorization: `Bearer ${signedTestToken('admin-user')}`,
      },
    });

    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.lobby).toBe('1D Lobby 1');
    expect(body.floor).toBe(1);
    expect(body.roomId).toBeNull();
    expect(body.roomNumber).toBeNull();
    expect(body.bedIds).toEqual([]);
    expect(body.bedLabels).toEqual([]);
  });

  it('Check 2 (route): GET /patients/:id returns room/floor/beds from active stay even if row copy is stale', async () => {
    const testPatientId = 'p_stale_room_patient';
    const staleStoredPatient = {
      ...baseRawPatient,
      id: testPatientId,
      status: 'active',
      room_id: 'old_room_99',
      room_number: '99',
      floor: 99,
      bed_ids: ['old_bed_99'],
      bed_labels: ['Old Bed 99'],
      lobby: 'Old Stale Lobby',
    };

    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string, params?: unknown[]) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'admin-user', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('FROM patients WHERE id = $1')) {
        return { rows: [staleStoredPatient], rowCount: 1, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM patient_attendants WHERE patient_id = $1')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM payments WHERE patient_id=$1')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM stays s') && sql.includes("s.status = 'active'")) {
        return {
          rows: [
            {
              id: 's_active_101',
              room_id: 'room_101',
              room_number: '101',
              room_type: 'general',
              bed_id: 'b_101_1',
              bed_label: 'Bed 101-A',
              status: 'active',
              room_floor: 1,
            },
          ],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('FROM stays WHERE patient_id = $1')) {
        return {
          rows: [
            {
              id: 's_active_101',
              patient_id: testPatientId,
              room_id: 'room_101',
              room_number: '101',
              room_type: 'general',
              status: 'active',
              admission_date: new Date('2026-10-01'),
              duration_days: 7,
              expected_discharge_date: new Date('2026-10-08'),
              expiry_date: new Date('2026-10-08'),
              total_cost: 0,
              base_cost: 0,
            },
          ],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('FROM attendance_records')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM system_settings')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM billing_corrections')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'GET',
      url: `/api/patients/${testPatientId}`,
      headers: {
        authorization: `Bearer ${signedTestToken('admin-user')}`,
      },
    });

    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.roomId).toBe('room_101');
    expect(body.roomNumber).toBe('101');
    expect(body.floor).toBe(1);
    expect(body.bedIds).toEqual(['b_101_1']);
    expect(body.bedLabels).toEqual(['Bed 101-A']);
    expect(body.lobby).toBeNull();
  });

  it('Check 3 (route): GET /patients/:id returns unchanged payload for discharged patient', async () => {
    const testPatientId = 'p_discharged_patient';
    const dischargedStoredPatient = {
      ...baseRawPatient,
      id: testPatientId,
      status: 'discharged',
      discharge_date: new Date('2026-10-15T12:00:00.000Z'),
      room_id: null,
      room_number: null,
      floor: null,
      bed_ids: [],
      bed_labels: [],
      lobby: null,
    };

    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'admin-user', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('FROM patients WHERE id = $1')) {
        return { rows: [dischargedStoredPatient], rowCount: 1, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM patient_attendants WHERE patient_id = $1')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM payments WHERE patient_id=$1')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM stays s') && sql.includes("s.status = 'active'")) {
        // Discharged patient has NO active stays
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM stays WHERE patient_id = $1')) {
        return {
          rows: [
            {
              id: 's_completed_1',
              patient_id: testPatientId,
              room_id: 'room_101',
              room_number: '101',
              room_type: 'general',
              status: 'completed',
              admission_date: new Date('2026-10-01'),
              duration_days: 7,
              expected_discharge_date: new Date('2026-10-08'),
              expiry_date: new Date('2026-10-08'),
              total_cost: 0,
              base_cost: 0,
            },
          ],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('FROM attendance_records')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM system_settings')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM billing_corrections')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'GET',
      url: `/api/patients/${testPatientId}`,
      headers: {
        authorization: `Bearer ${signedTestToken('admin-user')}`,
      },
    });

    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.roomId).toBeNull();
    expect(body.roomNumber).toBeNull();
    expect(body.floor).toBeNull();
    expect(body.bedIds).toEqual([]);
    expect(body.bedLabels).toEqual([]);
    expect(body.lobby).toBeNull();
    expect(body.status).toBe('discharged');
  });

  it('Check 4 (route): GET /patients list shows derived placement for lobby and room patients', async () => {
    const pLobby = {
      ...baseRawPatient,
      id: 'p_list_lobby',
      status: 'active',
      floor: null,
      lobby: null,
    };
    const pRoom = {
      ...baseRawPatient,
      id: 'p_list_room',
      status: 'active',
      floor: 99, // stale
      room_id: 'stale_room',
    };

    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'admin-user', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('FROM patients p')) {
        return { rows: [pLobby, pRoom], rowCount: 2, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM patient_attendants WHERE patient_id = ANY($1)')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM payments WHERE patient_id = ANY($1)')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM stays s') && sql.includes('LEFT JOIN rooms r')) {
        return {
          rows: [
            {
              id: 's_list_1',
              patient_id: 'p_list_lobby',
              room_id: 'lobby:1B Lobby 1',
              room_number: '1B Lobby 1',
              status: 'active',
              admission_date: new Date('2026-10-01'),
              duration_days: 7,
              expected_discharge_date: new Date('2026-10-08'),
              expiry_date: new Date('2026-10-08'),
              total_cost: 0,
              base_cost: 0,
              room_floor: 0,
              cycle_id: String(new Date(pLobby.admission_date).getTime()),
              updated_at: new Date('2026-10-01'),
            },
            {
              id: 's_list_2',
              patient_id: 'p_list_room',
              room_id: 'room_201',
              room_number: '201',
              bed_id: 'b_201_1',
              bed_label: 'Bed 201-1',
              status: 'active',
              admission_date: new Date('2026-10-01'),
              duration_days: 7,
              expected_discharge_date: new Date('2026-10-08'),
              expiry_date: new Date('2026-10-08'),
              total_cost: 0,
              base_cost: 0,
              room_floor: 2,
              cycle_id: String(new Date(pRoom.admission_date).getTime()),
              updated_at: new Date('2026-10-01'),
            },
          ],
          rowCount: 2,
          command: 'SELECT',
          oid: 0,
          fields: [],
        };
      }
      if (sql.includes('FROM attendance_records')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM system_settings')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      if (sql.includes('FROM billing_corrections')) {
        return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });

    const res = await app.inject({
      method: 'GET',
      url: '/api/patients',
      headers: {
        authorization: `Bearer ${signedTestToken('admin-user')}`,
      },
    });

    expect(res.statusCode).toBe(200);
    const list = JSON.parse(res.body);
    expect(list.length).toBe(2);

    const lobbyResult = list.find((p: any) => p.id === 'p_list_lobby');
    expect(lobbyResult.lobby).toBe('1B Lobby 1');
    expect(lobbyResult.floor).toBe(1);
    expect(lobbyResult.roomId).toBeNull();
    expect(lobbyResult.bedIds).toEqual([]);

    const roomResult = list.find((p: any) => p.id === 'p_list_room');
    expect(roomResult.roomId).toBe('room_201');
    expect(roomResult.roomNumber).toBe('201');
    expect(roomResult.floor).toBe(2);
    expect(roomResult.bedIds).toEqual(['b_201_1']);
    expect(roomResult.bedLabels).toEqual(['Bed 201-1']);
    expect(roomResult.lobby).toBeNull();
  });
});
