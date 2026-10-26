import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { runFirebaseImport } from '../src/importer/index.js';
import * as dbModule from '../src/db/index.js';
import { importerFixture } from './fixtures/importer-fixture.js';

describe('Firebase importer orchestration (mocked PostgreSQL)', () => {
  let directory: string;
  let fixture: Record<string, any>;
  let client: { query: ReturnType<typeof vi.fn>; release: ReturnType<typeof vi.fn> };
  const writeFixture = () => {
    const filePath = path.join(directory, 'synthetic.json');
    fs.writeFileSync(filePath, JSON.stringify(fixture));
    return filePath;
  };
  beforeEach(() => {
    directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ngo-import-test-'));
    fixture = importerFixture();
    client = {
      query: vi.fn().mockImplementation(async (sql: string) => {
        if (sql.includes('SUM(amount)')) return { rows: [{ total: '0.30' }], rowCount: 1 };
        if (sql.includes('SUM(total_paid_amount)')) return { rows: [{ paid: '0.30', due: '9.70' }], rowCount: 1 };
        return { rows: [{ is_inserted: true }], rowCount: 1 };
      }), release: vi.fn(),
    };
    vi.spyOn(dbModule, 'getClient').mockResolvedValue(client as any);
  });
  afterEach(() => {
    vi.restoreAllMocks();
    fs.rmSync(directory, { recursive: true, force: true });
  });
  it('defaults to dry run, with exact source totals and canonical payment deduplication', async () => {
    const stats = await runFirebaseImport({ filePath: writeFixture(), onProgress: () => {} });
    expect(client.query).toHaveBeenCalledWith('BEGIN');
    expect(client.query).toHaveBeenCalledWith('ROLLBACK');
    expect(client.query).not.toHaveBeenCalledWith('COMMIT');
    expect(stats.committed).toBe(false);
    expect(stats.payments).toMatchObject({ processed: 2, imported: 2, failed: 0, deduplicated: 1 });
    expect(stats.attendance.imported).toBe(2);
    expect(stats.financials).toMatchObject({ sourceTotalPayments: 0.3, sourceTotalPatientPaid: 0.3, sourceTotalPatientDue: 9.7 });
  });
  it('rolls back and releases the connection on a fatal setup failure without logging payloads', async () => {
    client.query.mockRejectedValueOnce(new Error('connection failed'));
    await expect(runFirebaseImport({ filePath: writeFixture(), onProgress: () => {} })).rejects.toThrow('connection failed');
    expect(client.query).toHaveBeenCalledWith('ROLLBACK');
    expect(client.release).toHaveBeenCalledTimes(1);
  });
  it('rejects malformed roots before connecting', async () => {
    fs.writeFileSync(path.join(directory, 'invalid.json'), '[]');
    await expect(runFirebaseImport({ filePath: path.join(directory, 'invalid.json'), onProgress: () => {} })).rejects.toThrow('Export root');
    expect(dbModule.getClient).not.toHaveBeenCalled();
  });
  it('recovers a row SQL failure using a savepoint and redacts database detail', async () => {
    client.query.mockImplementation(async (sql: string) => {
      if (sql.includes('INSERT INTO patients')) throw Object.assign(new Error('sensitive patient payload'), { code: '23505' });
      return { rows: [{ is_inserted: true }], rowCount: 1 };
    });
    const stats = await runFirebaseImport({ filePath: writeFixture(), dryRun: false, onProgress: () => {} });
    expect(client.query).toHaveBeenCalledWith('ROLLBACK TO SAVEPOINT import_record');
    expect(stats.patients.failed).toBe(1);
    expect(stats.stays.missingPatientRefs).toBe(1);
    expect(stats.payments.missingPatientRefs).toBe(2);
    expect(stats.warnings.join(' ')).not.toContain('sensitive');
  });
  it.each(['12oops', 'NaN', 'Infinity', '0.001', '10000000000.00'])('rejects invalid money %s rather than truncating or rounding it', async (amount) => {
    fixture.payments = { invalid: { id: 'invalid', patientId: 'audit_patient', date: 1767261600000, amount } };
    fixture.paymentHistory = {};
    const stats = await runFirebaseImport({ filePath: writeFixture(), onProgress: () => {} });
    expect(stats.payments).toMatchObject({ processed: 1, failed: 1, imported: 0 });
  });

  describe('Reconciliation mode (reconcile: true)', () => {
    let pgPatients: Map<string, any>;
    let pgStays: Map<string, any>;
    let pgPayments: Map<string, any>;
    let pgAttendance: Set<string>;
    let pgPhotos: Set<string>;

    beforeEach(() => {
      pgPatients = new Map([
        [
          'p_existing_5132',
          {
            id: 'p_existing_5132',
            full_name: 'Taraknath Pal',
            registration_number: '5132',
            admission_date: new Date(1787196600000),
            registration_date: new Date(1787196600000),
            updated_at: new Date(),
            total_paid_amount: '1000.00',
            current_due_amount: '0.00',
            advance_billed_amount: '1000.00',
            attendance_charges: '0.00',
            admission_balances: {},
          },
        ],
      ]);

      pgStays = new Map([
        [
          'stay_existing_5132',
          {
            id: 'stay_existing_5132',
            patient_id: 'p_existing_5132',
            room_id: 'audit_room',
            bed_id: 'audit_bed',
            admission_date: new Date(1787196600000),
            status: 'active',
          },
        ],
      ]);

      pgPayments = new Map([
        // 1. Existing payment with 64-char truncated ID and UTR
        [
          'upi_truncated64_________________________________________________',
          {
            id: 'upi_truncated64_________________________________________________',
            patient_id: 'p_existing_5132',
            cycle_id: '1787196600000',
            amount: '1000.00',
            method: 'UPI',
            transaction_id: 'UTR_EXISTING_64',
            receipt_number: '6900',
          },
        ],
        // 2. PG-only live payment that is absent from RTDB export
        [
          'upi_pg_only_live_payment',
          {
            id: 'upi_pg_only_live_payment',
            patient_id: 'p_existing_5132',
            cycle_id: '1787196600000',
            amount: '18800.00',
            method: 'UPI',
            transaction_id: 'UTR_PG_ONLY_999',
            receipt_number: '7100',
          },
        ],
      ]);

      pgAttendance = new Set();
      pgPhotos = new Set();

      client.query.mockImplementation(async (sql: string, params: any[] = []) => {
        if (sql.includes('SELECT id, registration_number, admission_date, updated_at FROM patients')) {
          return { rows: Array.from(pgPatients.values()), rowCount: pgPatients.size };
        }
        if (sql.includes('INSERT INTO patients (')) {
          const id = params[0];
          const isInserted = !pgPatients.has(id);
          pgPatients.set(id, {
            id,
            full_name: params[1],
            registration_number: params[23],
            admission_date: params[12],
            registration_date: params[24] || params[12],
            updated_at: new Date(),
            total_paid_amount: String(params[32] ?? '0'),
            current_due_amount: String(params[33] ?? '0'),
            advance_billed_amount: String(params[40] ?? '0'),
            attendance_charges: String(params[42] ?? '0'),
            admission_balances: JSON.parse(params[37] || '{}'),
          });
          return { rows: [{ is_inserted: isInserted }], rowCount: 1 };
        }
        if (sql.includes('SELECT id, status FROM stays WHERE id = $1')) {
          const row = pgStays.get(params[0]);
          return { rows: row ? [row] : [], rowCount: row ? 1 : 0 };
        }
        if (sql.includes('INSERT INTO stays (')) {
          const id = params[0];
          const isInserted = !pgStays.has(id);
          pgStays.set(id, {
            id,
            patient_id: params[1],
            room_id: params[3],
            bed_id: params[7],
            admission_date: params[9],
            status: params[16],
          });
          return { rows: [{ is_inserted: isInserted }], rowCount: 1 };
        }
        if (sql.includes('SELECT * FROM payments') && sql.includes('LIMIT 1')) {
          const [payId, prefix64, patientId, trimmedTx, trimmedReceipt] = params;
          for (const row of pgPayments.values()) {
            if (
              row.id === payId ||
              (row.id === prefix64 && row.patient_id === patientId) ||
              (trimmedTx && row.patient_id === patientId && row.transaction_id === trimmedTx) ||
              (trimmedReceipt && row.patient_id === patientId && row.receipt_number === trimmedReceipt)
            ) {
              return { rows: [row], rowCount: 1 };
            }
          }
          return { rows: [], rowCount: 0 };
        }
        if (sql.includes('SELECT id, admission_date, registration_date FROM patients WHERE id = $1')) {
          const row = pgPatients.get(params[0]);
          return { rows: row ? [row] : [], rowCount: row ? 1 : 0 };
        }
        if (sql.includes('SELECT * FROM stays WHERE patient_id = $1 ORDER BY admission_date ASC')) {
          const rows = Array.from(pgStays.values()).filter((s) => s.patient_id === params[0]);
          return { rows, rowCount: rows.length };
        }
        if (sql.includes('INSERT INTO payments (') && sql.includes('ON CONFLICT (id) DO NOTHING')) {
          const id = params[0];
          if (pgPayments.has(id)) {
            return { rows: [], rowCount: 0 };
          }
          pgPayments.set(id, {
            id,
            patient_id: params[1],
            cycle_id: params[2],
            type: params[3],
            amount: String(params[4]),
            method: params[9],
            payment_date: params[10],
            receipt_number: params[11],
            transaction_id: params[14],
          });
          return { rows: [{ id }], rowCount: 1 };
        }
        if (sql.includes('SELECT COALESCE(SUM(amount), 0) AS total_paid FROM payments WHERE patient_id = $1')) {
          const pid = params[0];
          let sum = 0;
          for (const p of pgPayments.values()) {
            if (p.patient_id === pid) sum += Number(p.amount);
          }
          return { rows: [{ total_paid: sum.toFixed(2) }], rowCount: 1 };
        }
        if (sql.includes('SELECT advance_billed_amount, attendance_charges, admission_balances FROM patients WHERE id = $1')) {
          const row = pgPatients.get(params[0]);
          return { rows: row ? [row] : [], rowCount: row ? 1 : 0 };
        }
        if (sql.includes('SELECT id FROM attendance_records')) {
          const rows = Array.from(pgAttendance).map((id) => ({ id }));
          return { rows, rowCount: rows.length };
        }
        if (sql.includes('INSERT INTO attendance_records (')) {
          const key = params[0];
          const isInserted = !pgAttendance.has(key);
          pgAttendance.add(key);
          return { rows: [{ is_inserted: isInserted }], rowCount: 1 };
        }
        if (sql.includes('INSERT INTO patient_photos') && sql.includes('ON CONFLICT (photo_path) DO NOTHING')) {
          const key = params[0];
          if (pgPhotos.has(key)) return { rows: [], rowCount: 0 };
          pgPhotos.add(key);
          return { rows: [{ photo_path: key }], rowCount: 1 };
        }
        if (sql.includes('SUM(amount)')) {
          let sum = 0;
          for (const p of pgPayments.values()) sum += Number(p.amount);
          return { rows: [{ total: sum.toFixed(2) }], rowCount: 1 };
        }
        if (sql.includes('SUM(total_paid_amount)')) {
          return { rows: [{ paid: '11000.00', due: '0.00' }], rowCount: 1 };
        }
        return { rows: [{ is_inserted: true }], rowCount: 1 };
      });
    });

    it('1. imports a missing patient without duplicating or overwriting existing patients', async () => {
      fixture.patients = {
        p_existing_5132: {
          fullName: 'Older Export Name That Should Not Overwrite PG',
          gender: 'Male',
          dateOfBirth: '1970-01-01',
          contactNumber: '9999999999',
          emergencyContact: '9999999999',
          emergencyContactName: 'Kin',
          medicalCondition: 'Checkup',
          admissionDate: 1787196600000,
          registrationNumber: '5132',
          totalPaidAmount: '1000.00',
          currentDueAmount: '0.00',
        },
        p_missing_5254: {
          fullName: 'Annu Singh',
          gender: 'Female',
          dateOfBirth: '1992-05-10',
          contactNumber: '9876543210',
          emergencyContact: '9876543211',
          emergencyContactName: 'Relative',
          medicalCondition: 'Treatment',
          admissionDate: 1792392191048,
          registrationNumber: '5254',
          roomId: 'audit_room',
          totalPaidAmount: '0.00',
          currentDueAmount: '0.00',
        },
      };
      fixture.stays = {};
      fixture.payments = {};
      fixture.paymentHistory = {};
      fixture.attendance = {};
      fixture.attendant_attendance = {};

      const stats = await runFirebaseImport({
        filePath: writeFixture(),
        dryRun: false,
        reconcile: true,
        onProgress: () => {},
      });

      expect(stats.reconciliation).toBeDefined();
      expect(stats.reconciliation!.patients).toMatchObject({
        source: 2,
        matched: 1,
        imported: 1,
        conflicting: 0,
      });
      // Existing patient preserved in PG without overwrite
      expect(pgPatients.get('p_existing_5132')?.full_name).toBe('Taraknath Pal');
      // Missing patient imported into PG
      expect(pgPatients.get('p_missing_5254')?.full_name).toBe('Annu Singh');
      expect(pgPatients.get('p_missing_5254')?.registration_number).toBe('5254');
      expect(pgPatients.size).toBe(2);
    });

    it('2 & 4. imports a missing 68-char advance payment once, matches 64-char truncated/UTR payments, and maps cycleId from receiptCycle', async () => {
      const missingUpiId = 'upi_78872293db2bf1ea37273e07deb48e11a2950085cf84010e367fcd5af0fbf996';
      const truncatedSourceId = 'upi_truncated64_________________________________________________abcd';

      fixture.patients = {
        p_existing_5132: {
          fullName: 'Taraknath Pal',
          gender: 'Male',
          dateOfBirth: '1970-01-01',
          contactNumber: '9999999999',
          emergencyContact: '9999999999',
          emergencyContactName: 'Kin',
          medicalCondition: 'Checkup',
          admissionDate: 1787196600000,
          registrationNumber: '5132',
        },
      };
      fixture.stays = {};
      fixture.payments = {
        [missingUpiId]: {
          id: missingUpiId,
          patientId: 'p_existing_5132',
          amount: '10000.00',
          date: 1787197000000,
          method: 'UPI',
          type: 'Advance Payment',
          transactionId: '449581259384',
          receiptNumber: '6966',
          receiptCycle: 1787196600000,
        },
        [truncatedSourceId]: {
          id: truncatedSourceId,
          patientId: 'p_existing_5132',
          amount: '1000.00',
          date: 1787196800000,
          method: 'UPI',
          transactionId: 'UTR_EXISTING_64',
          receiptNumber: '6900',
        },
      };
      fixture.paymentHistory = {};
      fixture.attendance = {};
      fixture.attendant_attendance = {};

      const stats = await runFirebaseImport({
        filePath: writeFixture(),
        dryRun: false,
        reconcile: true,
        onProgress: () => {},
      });

      expect(stats.reconciliation!.payments).toMatchObject({
        source: 2,
        matched: 1,
        imported: 1,
        conflicting: 0,
        unresolved: 0,
      });

      const importedPay = pgPayments.get(missingUpiId);
      expect(importedPay).toBeDefined();
      expect(importedPay.patient_id).toBe('p_existing_5132');
      expect(importedPay.cycle_id).toBe('1787196600000');
      expect(importedPay.amount).toBe('10000.00');
      expect(importedPay.transaction_id).toBe('449581259384');
      expect(importedPay.receipt_number).toBe('6966');
      // PG-only payment is also preserved untouched
      expect(pgPayments.has('upi_pg_only_live_payment')).toBe(true);
      expect(pgPayments.size).toBe(3);
    });

    it('3. preserves an existing PostgreSQL payment when an RTDB record has conflicting values', async () => {
      fixture.patients = {
        p_existing_5132: {
          fullName: 'Taraknath Pal',
          gender: 'Male',
          dateOfBirth: '1970-01-01',
          contactNumber: '9999999999',
          emergencyContact: '9999999999',
          emergencyContactName: 'Kin',
          medicalCondition: 'Checkup',
          admissionDate: 1787196600000,
          registrationNumber: '5132',
        },
      };
      fixture.stays = {};
      fixture.payments = {
        upi_pg_only_live_payment: {
          id: 'upi_pg_only_live_payment',
          patientId: 'p_existing_5132',
          amount: '500.00', // Conflicts with PG's 18800.00
          date: 1787197000000,
          method: 'UPI',
          transactionId: 'UTR_PG_ONLY_999',
        },
      };
      fixture.paymentHistory = {};
      fixture.attendance = {};
      fixture.attendant_attendance = {};

      const stats = await runFirebaseImport({
        filePath: writeFixture(),
        dryRun: false,
        reconcile: true,
        onProgress: () => {},
      });

      expect(stats.reconciliation!.payments.conflicting).toBe(1);
      expect(stats.reconciliation!.payments.imported).toBe(0);
      // PG record still has its original amount 18800.00
      expect(pgPayments.get('upi_pg_only_live_payment')?.amount).toBe('18800.00');
    });

    it('5. reports ambiguous, conflicting, or unmatched orphan records without importing them', async () => {
      fixture.patients = {
        // Duplicate registration number conflict against p_existing_5132 (Reg 5132)
        p_conflicting_reg: {
          fullName: 'Duplicate Reg Patient',
          gender: 'Male',
          dateOfBirth: '1980-01-01',
          contactNumber: '9111111111',
          emergencyContact: '9111111111',
          emergencyContactName: 'Kin',
          medicalCondition: 'Flu',
          admissionDate: 1790000000000,
          registrationNumber: '5132',
        },
        // Incomplete patient stub missing required fullName
        p_incomplete_stub: {
          gender: 'Female',
          registrationNumber: '9999',
        },
      };
      fixture.stays = {
        stay_orphan: {
          id: 'stay_orphan',
          patientId: 'non_existent_patient_id',
          roomId: 'audit_room',
          bedId: 'audit_bed',
          admissionDate: 1790000000000,
          durationDays: 3,
        },
      };
      fixture.payments = {
        pay_orphan: {
          id: 'pay_orphan',
          patientId: 'non_existent_patient_id',
          amount: '2500.00',
          date: 1790000000000,
          method: 'UPI',
        },
      };
      fixture.paymentHistory = {};
      fixture.attendance = {};
      fixture.attendant_attendance = {};

      const stats = await runFirebaseImport({
        filePath: writeFixture(),
        dryRun: false,
        reconcile: true,
        onProgress: () => {},
      });

      expect(stats.reconciliation!.patients.conflicting).toBe(2);
      expect(stats.reconciliation!.patients.imported).toBe(0);
      expect(stats.reconciliation!.stays.unresolved).toBe(1);
      expect(stats.reconciliation!.stays.imported).toBe(0);
      expect(stats.reconciliation!.payments.unresolved).toBe(1);
      expect(stats.reconciliation!.payments.imported).toBe(0);
      expect(pgPatients.has('p_conflicting_reg')).toBe(false);
      expect(pgPatients.has('p_incomplete_stub')).toBe(false);
      expect(pgPayments.has('pay_orphan')).toBe(false);
    });

    it('6. running the importer twice in reconcile mode is idempotent and creates zero additional records', async () => {
      const missingUpiId = 'upi_78872293db2bf1ea37273e07deb48e11a2950085cf84010e367fcd5af0fbf996';
      fixture.patients = {
        p_existing_5132: {
          fullName: 'Taraknath Pal',
          gender: 'Male',
          dateOfBirth: '1970-01-01',
          contactNumber: '9999999999',
          emergencyContact: '9999999999',
          emergencyContactName: 'Kin',
          medicalCondition: 'Checkup',
          admissionDate: 1787196600000,
          registrationNumber: '5132',
        },
        p_missing_5254: {
          fullName: 'Annu Singh',
          gender: 'Female',
          dateOfBirth: '1992-05-10',
          contactNumber: '9876543210',
          emergencyContact: '9876543211',
          emergencyContactName: 'Relative',
          medicalCondition: 'Treatment',
          admissionDate: 1792392191048,
          registrationNumber: '5254',
          roomId: 'audit_room',
        },
      };
      fixture.stays = {
        stay_new_5254: {
          id: 'stay_new_5254',
          patientId: 'p_missing_5254',
          roomId: 'audit_room',
          bedId: 'audit_bed',
          patientName: 'Annu Singh',
          admissionDate: 1792392191048,
          durationDays: 5,
          status: 'active',
        },
      };
      fixture.payments = {
        [missingUpiId]: {
          id: missingUpiId,
          patientId: 'p_existing_5132',
          amount: '10000.00',
          date: 1787197000000,
          method: 'UPI',
          transactionId: '449581259384',
          receiptNumber: '6966',
          receiptCycle: 1787196600000,
        },
      };
      fixture.paymentHistory = {};
      fixture.attendance = {
        daily: {
          '2026-10-20': {
            p_missing_5254: { status: 'Present', date: '2026-10-20' },
          },
        },
      };
      fixture.attendant_attendance = {};

      const filePath = writeFixture();

      // First run imports the missing patient, stay, payment, and attendance
      const run1 = await runFirebaseImport({
        filePath,
        dryRun: false,
        reconcile: true,
        onProgress: () => {},
      });
      expect(run1.reconciliation!.patients.imported).toBe(1);
      expect(run1.reconciliation!.stays.imported).toBe(1);
      expect(run1.reconciliation!.payments.imported).toBe(1);
      expect(run1.reconciliation!.attendance.imported).toBe(1);

      // Second run against the updated PG state imports 0 records across all collections
      const run2 = await runFirebaseImport({
        filePath,
        dryRun: false,
        reconcile: true,
        onProgress: () => {},
      });
      expect(run2.reconciliation!.patients).toMatchObject({ matched: 2, imported: 0 });
      expect(run2.reconciliation!.stays).toMatchObject({ matched: 1, imported: 0 });
      expect(run2.reconciliation!.payments).toMatchObject({ matched: 1, imported: 0 });
      expect(run2.reconciliation!.attendance).toMatchObject({ matched: 1, imported: 0 });
      expect(pgPatients.size).toBe(2);
      expect(pgStays.size).toBe(2);
      expect(pgPayments.size).toBe(3);
    });
  });
});
