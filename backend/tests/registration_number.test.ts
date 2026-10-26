import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { buildApp } from '../src/app.js';
import * as dbModule from '../src/db/index.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

describe('Editable Registration Number Endpoints', () => {
  let app: ReturnType<typeof buildApp>;

  beforeEach(() => {
    vi.restoreAllMocks();
    installTestFirebaseKeys();
    app = buildApp();
  });

  afterEach(async () => {
    await app.close();
    vi.restoreAllMocks();
  });

  const setupAuth = () => {
    vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
      if (sql.includes('SELECT id, email, name, role FROM users')) {
        return {
          rows: [{ id: 'admin-1', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
          rowCount: 1, command: 'SELECT', oid: 0, fields: [],
        };
      }
      return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
    });
  };

  it('POST /api/patients rejects duplicate registration numbers with clear 409 error', async () => {
    setupAuth();

    const mockClient = {
      query: vi.fn(async (sql: string, params?: unknown[]) => {
        if (sql === 'BEGIN' || sql === 'ROLLBACK') return { rows: [], rowCount: 0 };
        if (sql.includes('SELECT id FROM patients WHERE LOWER(registration_number) = LOWER($1)')) {
          // Simulate existing patient with registration number 'REG-100'
          return { rows: [{ id: 'existing_p1' }], rowCount: 1 };
        }
        return { rows: [], rowCount: 0 };
      }),
      release: vi.fn(),
    };
    vi.spyOn(dbModule, 'getClient').mockResolvedValue(mockClient as any);

    const res = await app.inject({
      method: 'POST',
      url: '/api/patients',
      headers: { authorization: `Bearer ${signedTestToken('admin-1')}` },
      payload: {
        id: 'new_patient_1',
        fullName: 'Test Patient',
        dateOfBirth: '1995-05-15',
        gender: 'female',
        contactNumber: '9876543210',
        emergencyContact: '9876543211',
        emergencyContactName: 'Relative',
        medicalCondition: 'General Checkup',
        admissionDate: '2026-10-26',
        registrationNumber: 'reg-100', // duplicate (case-insensitive)
      },
    });

    expect(res.statusCode).toBe(409);
    const body = JSON.parse(res.body);
    expect(body.message).toBe('Registration number "reg-100" is already assigned to another patient.');
    expect(mockClient.release).toHaveBeenCalled();
  });

  it('POST /api/patients allows custom registration number and saves it', async () => {
    setupAuth();

    let savedRegNumber: string | null = null;
    const mockClient = {
      query: vi.fn(async (sql: string, params?: unknown[]) => {
        if (sql === 'BEGIN' || sql === 'COMMIT') return { rows: [], rowCount: 0 };
        if (sql.includes('SELECT id FROM patients WHERE LOWER(registration_number) = LOWER($1)')) {
          return { rows: [], rowCount: 0 }; // no duplicate
        }
        if (sql.includes('INSERT INTO patients')) {
          savedRegNumber = (params as any[])[23]; // $24 index in 0-based is 23
          return {
            rows: [{
              id: 'new_patient_2',
              full_name: 'Custom Reg Patient',
              registration_number: savedRegNumber,
              admission_date: new Date('2026-10-26'),
              date_of_birth: new Date('1990-01-01'),
              status: 'active',
              total_paid_amount: '0',
              current_due_amount: '0',
              refund_due_amount: '0',
              total_refund_due_amount: '0',
              total_refunded_amount: '0',
              version: 1,
            }],
            rowCount: 1,
          };
        }
        return { rows: [], rowCount: 0 };
      }),
      release: vi.fn(),
    };
    vi.spyOn(dbModule, 'getClient').mockResolvedValue(mockClient as any);

    const res = await app.inject({
      method: 'POST',
      url: '/api/patients',
      headers: { authorization: `Bearer ${signedTestToken('admin-1')}` },
      payload: {
        id: 'new_patient_2',
        fullName: 'Custom Reg Patient',
        dateOfBirth: '1990-01-01',
        gender: 'male',
        contactNumber: '9876543210',
        emergencyContact: '9876543211',
        emergencyContactName: 'Relative',
        medicalCondition: 'Observation',
        admissionDate: '2026-10-26',
        registrationNumber: 'CUSTOM-777',
      },
    });

    expect(res.statusCode).toBe(201);
    const body = JSON.parse(res.body);
    expect(body.registrationNumber).toBe('CUSTOM-777');
    expect(savedRegNumber).toBe('CUSTOM-777');
  });

  it('PUT /api/patients/:id updates registration number without changing patient id', async () => {
    setupAuth();

    let updatedRegNumber: string | null = null;
    const existingPatient = {
      id: 'patient_existing_1',
      full_name: 'Existing Patient',
      registration_number: '5200',
      admission_date: new Date('2026-10-01'),
      date_of_birth: new Date('1985-05-05'),
      status: 'active',
      total_paid_amount: '0',
      current_due_amount: '0',
      refund_due_amount: '0',
      total_refund_due_amount: '0',
      total_refunded_amount: '0',
      version: 1,
    };

    const mockClient = {
      query: vi.fn(async (sql: string, params?: unknown[]) => {
        if (sql === 'BEGIN' || sql === 'COMMIT') return { rows: [], rowCount: 0 };
        if (sql.includes('SELECT * FROM patients WHERE id = $1 FOR UPDATE')) {
          return { rows: [existingPatient], rowCount: 1 };
        }
        if (sql.includes("SELECT id,room_id FROM stays WHERE patient_id=$1 AND status='active'")) {
          return { rows: [], rowCount: 0 };
        }
        if (sql.includes('SELECT id FROM patients WHERE LOWER(registration_number) = LOWER($1) AND id <> $2')) {
          return { rows: [], rowCount: 0 }; // no duplicate
        }
        if (sql.includes('UPDATE patients SET')) {
          updatedRegNumber = (params as any[])[21]; // $22 is index 21
          return {
            rows: [{ ...existingPatient, registration_number: updatedRegNumber, version: 2 }],
            rowCount: 1,
          };
        }
        return { rows: [], rowCount: 0 };
      }),
      release: vi.fn(),
    };
    vi.spyOn(dbModule, 'getClient').mockResolvedValue(mockClient as any);

    const res = await app.inject({
      method: 'PUT',
      url: '/api/patients/patient_existing_1',
      headers: { authorization: `Bearer ${signedTestToken('admin-1')}` },
      payload: {
        registrationNumber: '5299-A',
      },
    });

    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.id).toBe('patient_existing_1');
    expect(body.registrationNumber).toBe('5299-A');
    expect(updatedRegNumber).toBe('5299-A');
  });

  it('PUT /api/patients/:id rejects duplicate registration number with 409', async () => {
    setupAuth();

    const existingPatient = {
      id: 'patient_existing_1',
      full_name: 'Existing Patient',
      registration_number: '5200',
      admission_date: new Date('2026-10-01'),
      date_of_birth: new Date('1985-05-05'),
      status: 'active',
      total_paid_amount: '0',
      current_due_amount: '0',
      refund_due_amount: '0',
      total_refund_due_amount: '0',
      total_refunded_amount: '0',
      version: 1,
    };

    const mockClient = {
      query: vi.fn(async (sql: string, params?: unknown[]) => {
        if (sql === 'BEGIN' || sql === 'ROLLBACK') return { rows: [], rowCount: 0 };
        if (sql.includes('SELECT * FROM patients WHERE id = $1 FOR UPDATE')) {
          return { rows: [existingPatient], rowCount: 1 };
        }
        if (sql.includes("SELECT id,room_id FROM stays WHERE patient_id=$1 AND status='active'")) {
          return { rows: [], rowCount: 0 };
        }
        if (sql.includes('SELECT id FROM patients WHERE LOWER(registration_number) = LOWER($1) AND id <> $2')) {
          return { rows: [{ id: 'another_patient' }], rowCount: 1 }; // duplicate exists!
        }
        return { rows: [], rowCount: 0 };
      }),
      release: vi.fn(),
    };
    vi.spyOn(dbModule, 'getClient').mockResolvedValue(mockClient as any);

    const res = await app.inject({
      method: 'PUT',
      url: '/api/patients/patient_existing_1',
      headers: { authorization: `Bearer ${signedTestToken('admin-1')}` },
      payload: {
        registrationNumber: '5201',
      },
    });

    expect(res.statusCode).toBe(409);
    const body = JSON.parse(res.body);
    expect(body.message).toBe('Registration number "5201" is already assigned to another patient.');
  });
});
