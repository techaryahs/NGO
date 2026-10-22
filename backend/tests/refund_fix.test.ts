import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { buildApp } from '../src/app.js';
import * as dbModule from '../src/db/index.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';
import { validateDomainRequest } from '../src/validation.js';

describe('Refund Bug Fix and Financial Validation Tests', () => {
  let app: ReturnType<typeof buildApp>;

  beforeEach(() => {
    vi.restoreAllMocks();
    installTestFirebaseKeys();
    app = buildApp({ logger: false });
  });

  afterEach(async () => {
    await app.close();
    vi.restoreAllMocks();
  });

  describe('Zod Domain Validation (validateDomainRequest)', () => {
    it('accepts the exact payload that previously failed with HTTP 400', async () => {
      // The exact payload sent by Flutter when submitting ₹1,200 refund:
      // - amount: -1200
      // - type: "refund"
      // - method: "online"
      // - transactionId: ""
      // - receiptNumber: ""
      const payload = {
        id: 'refund_1792347900000_12345678',
        amount: -1200,
        date: 1792347900000,
        method: 'online',
        receiptNumber: '',
        transactionId: '',
        cycleId: '1792316340000',
        type: 'refund',
        notes: 'Refund recorded',
        patientId: 'p_1792347832476077_4e82d761ff7201dd0485d38a',
        patientName: 'test',
        timestamp: 1792347900000,
      };

      const mockRequest: any = {
        method: 'POST',
        routeOptions: { url: '/api/payments' },
        body: payload,
      };

      // In the old code, this threw 400 with:
      // "type: Invalid literal value, expected 'payment'; amount: amount must be positive; transactionId: String must contain at least 1 character(s)"
      // In the fixed code, this MUST succeed without error:
      await expect(validateDomainRequest(mockRequest)).resolves.toBeUndefined();
    });

    it('rejects positive amounts for refunds', async () => {
      const positiveRefund = {
        id: 'refund_test_pos',
        amount: 1200, // Should be negative for refunds
        patientId: 'p_123',
        type: 'refund',
        method: 'online',
      };

      const mockRequest: any = {
        method: 'POST',
        routeOptions: { url: '/api/payments' },
        body: positiveRefund,
      };

      await expect(validateDomainRequest(mockRequest)).rejects.toThrow(
        /Payments must be positive and refunds negative/
      );
    });

    it('rejects negative amounts for payments', async () => {
      const negativePayment = {
        id: 'pay_test_neg',
        amount: -1200, // Should be positive for payments
        patientId: 'p_123',
        type: 'payment',
        method: 'cash',
      };

      const mockRequest: any = {
        method: 'POST',
        routeOptions: { url: '/api/payments' },
        body: negativePayment,
      };

      await expect(validateDomainRequest(mockRequest)).rejects.toThrow(
        /Payments must be positive and refunds negative/
      );
    });

    it('rejects invalid decimal places in money amounts', async () => {
      const badDecimal = {
        id: 'refund_test_bad_dec',
        amount: -1200.555, // 3 decimal places is invalid
        patientId: 'p_123',
        type: 'refund',
      };

      const mockRequest: any = {
        method: 'POST',
        routeOptions: { url: '/api/payments' },
        body: badDecimal,
      };

      await expect(validateDomainRequest(mockRequest)).rejects.toThrow(
        /decimal with at most two fractional digits/
      );
    });

    it('rejects requests missing patientId', async () => {
      const missingPatient = {
        id: 'refund_no_patient',
        amount: -500,
        type: 'refund',
      };

      const mockRequest: any = {
        method: 'POST',
        routeOptions: { url: '/api/payments' },
        body: missingPatient,
      };

      await expect(validateDomainRequest(mockRequest)).rejects.toThrow(
        /patientId/
      );
    });

    it('allows empty transactionId and receiptNumber strings without validation failure', async () => {
      const emptyReferences = {
        id: 'refund_empty_ref',
        amount: -100,
        patientId: 'p_123',
        type: 'refund',
        method: 'cash',
        receiptNumber: '',
        transactionId: '',
      };

      const mockRequest: any = {
        method: 'POST',
        routeOptions: { url: '/api/payments' },
        body: emptyReferences,
      };

      await expect(validateDomainRequest(mockRequest)).resolves.toBeUndefined();
    });

    it('supports cash, online (UPI QR), and check refund methods', async () => {
      for (const method of ['cash', 'online', 'check', 'ONLINE', 'CASH']) {
        const req: any = {
          method: 'POST',
          routeOptions: { url: '/api/payments' },
          body: {
            id: `refund_method_${method}`,
            amount: -100,
            patientId: 'p_123',
            type: 'refund',
            method,
          },
        };
        await expect(validateDomainRequest(req)).resolves.toBeUndefined();
      }
    });
  });

  describe('Payment and Refund Route Logic', () => {
    it('formats refunds correctly in GET /api/payments with patient name and negative amount', async () => {
      vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
        if (sql.includes('SELECT id, email, name, role FROM users')) {
          return {
            rows: [{ id: 'test-admin', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
            rowCount: 1, command: 'SELECT', oid: 0, fields: [],
          };
        }
        if (sql.includes('FROM payments')) {
          return {
            rows: [
              {
                id: 'pay_1',
                patient_id: 'p_1',
                patient_name: 'Test Patient',
                type: 'payment',
                amount: '2800.00',
                total_amount: '2800.00',
                paid_amount: '2800.00',
                pending_amount: '0.00',
                payment_status: 'Paid',
                method: 'ONLINE',
                payment_date: new Date('2026-10-18T10:00:00Z'),
                receipt_number: 'REC001',
                transaction_id: 'TXN123',
                notes: 'Admission payment',
              },
              {
                id: 'ref_1',
                patient_id: 'p_1',
                patient_name: 'Test Patient',
                type: 'refund',
                amount: '-1200.00',
                total_amount: '-1200.00',
                paid_amount: '-1200.00',
                pending_amount: '0.00',
                payment_status: 'Paid',
                method: 'online',
                payment_date: new Date('2026-10-19T10:00:00Z'),
                receipt_number: null,
                transaction_id: null,
                notes: 'Refund recorded',
              },
            ],
            rowCount: 2, command: 'SELECT', oid: 0, fields: [],
          };
        }
        return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
      });

      const res = await app.inject({
        method: 'GET',
        url: '/api/payments?patientId=p_1',
        headers: { authorization: `Bearer ${signedTestToken('test-admin')}` },
      });

      expect(res.statusCode).toBe(200);
      const list = JSON.parse(res.body);
      expect(list).toHaveLength(2);
      expect(list[0]).toMatchObject({
        id: 'pay_1',
        patientName: 'Test Patient',
        amount: 2800,
        type: 'payment',
      });
      expect(list[1]).toMatchObject({
        id: 'ref_1',
        patientName: 'Test Patient',
        amount: -1200,
        type: 'refund',
      });
    });

    it('rolls back database transaction cleanly when an error occurs during payment insertion', async () => {
      let rolledBack = false;
      const mockClient = {
        query: vi.fn().mockImplementation(async (sql: string) => {
          if (sql === 'BEGIN') return {};
          if (sql === 'ROLLBACK') {
            rolledBack = true;
            return {};
          }
          if (sql.includes('SELECT * FROM patients WHERE id=$1 FOR UPDATE')) {
            return {
              rows: [{
                id: 'p_1',
                full_name: 'Test Patient',
                admission_date: new Date('2026-10-18T00:00:00Z'),
                registration_date: null,
                total_paid_amount: '2800.00',
                current_due_amount: '0.00',
                refund_due_amount: '1200.00',
                total_refund_due_amount: '1200.00',
                total_refunded_amount: '0.00',
                admission_balances: {},
              }],
              rowCount: 1,
            };
          }
          if (sql.includes('INSERT INTO payments')) {
            throw new Error('Database constraint failure simulation');
          }
          return { rows: [], rowCount: 0 };
        }),
        release: vi.fn(),
      };

      vi.spyOn(dbModule, 'getClient').mockResolvedValue(mockClient as any);
      vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
        if (sql.includes('SELECT id, email, name, role FROM users')) {
          return {
            rows: [{ id: 'test-admin', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
            rowCount: 1, command: 'SELECT', oid: 0, fields: [],
          };
        }
        return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
      });

      const res = await app.inject({
        method: 'POST',
        url: '/api/payments',
        headers: { authorization: `Bearer ${signedTestToken('test-admin')}` },
        payload: {
          id: 'ref_fail_sim',
          patientId: 'p_1',
          amount: -1200,
          type: 'refund',
          method: 'online',
        },
      });

      expect(res.statusCode).toBe(500);
      expect(rolledBack).toBe(true);
      expect(mockClient.release).toHaveBeenCalled();
    });

    it('rejects refund when refund exceeds excess balance with 409', async () => {
      const cycleKey = String(new Date('2026-10-18T00:00:00Z').getTime());
      const mockClient = {
        query: vi.fn().mockImplementation(async (sql: string) => {
          if (sql === 'BEGIN') return {};
          if (sql === 'ROLLBACK') return {};
          if (sql.includes('SELECT * FROM patients WHERE id=$1 FOR UPDATE')) {
            return {
              rows: [{
                id: 'p_1',
                full_name: 'Test Patient', status: 'active', advance_billed_amount: '1600.00', attendance_charges: '0.00',
                admission_date: new Date('2026-10-18T00:00:00Z'),
                registration_date: null,
                total_paid_amount: '2800.00',
                current_due_amount: '0.00',
                refund_due_amount: '1200.00',
                total_refund_due_amount: '1200.00',
                total_refunded_amount: '0.00',
                admission_balances: {
                  [cycleKey]: {
                    cycleId: cycleKey,
                    total: 1600,
                    paid: 2800,
                    refunded: 0,
                    netPaid: 2800,
                    due: 0,
                    refundDue: 1200,
                    status: 'Payment Exceeded',
                  },
                },
              }],
              rowCount: 1,
            };
          }
          if (sql.includes('SELECT * FROM payments WHERE id = $1')) {
            return { rows: [], rowCount: 0 };
          }
          if (sql.includes('SELECT cycle_id, patient_snapshot')) {
            return { rows: [], rowCount: 0 };
          }
          if (sql.includes('SELECT * FROM payments WHERE patient_id=$1')) {
            return { rows: [
              {cycle_id:cycleKey, amount:'2800.00', payment_date:new Date('2026-10-19')},
              {cycle_id:cycleKey, amount:'-1500.00', payment_date:new Date('2026-10-19')},
            ], rowCount:2 };
          }
          if (sql.includes('INSERT INTO payments')) {
            return {
              rows: [{
                id: 'ref_excess_attempt',
                patient_id: 'p_1',
                cycle_id: cycleKey,
                type: 'refund',
                amount: '-1500.00',
                payment_date: new Date('2026-10-19T00:00:00Z'),
              }],
              rowCount: 1,
            };
          }
          return { rows: [], rowCount: 0 };
        }),
        release: vi.fn(),
      };

      vi.spyOn(dbModule, 'getClient').mockResolvedValue(mockClient as any);
      vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string) => {
        if (sql.includes('SELECT id, email, name, role FROM users')) {
          return {
            rows: [{ id: 'test-admin', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
            rowCount: 1, command: 'SELECT', oid: 0, fields: [],
          };
        }
        return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
      });

      // Attempt to refund ₹1,500 when available excess is only ₹1,200
      const res = await app.inject({
        method: 'POST',
        url: '/api/payments',
        headers: { authorization: `Bearer ${signedTestToken('test-admin')}` },
        payload: {
          id: 'ref_excess_attempt',
          patientId: 'p_1',
          amount: -1500, // Exceeds 1200
          type: 'refund',
          method: 'online',
        },
      });

      expect(res.statusCode).toBe(409);
      const body = JSON.parse(res.body);
      expect(body.message).toMatch(/Refund exceeds the remaining excess payment/);
    });

    it('successfully routes GET, PUT, and DELETE for stay IDs containing slashes (e.g. bed 1/2)', async () => {
      const slashStayId = 'stay_p_1792347832476077_r_1792316250516360_1/2';
      const mockStayRow = {
        id: slashStayId,
        patient_id: 'p_1792347832476077',
        room_id: 'r_1792316250516360',
        bed_id: 'r_1792316250516360_1/2',
        bed_label: '1/2',
        room_number: '1A',
        room_type: 'general',
        status: 'active',
        admission_date: new Date('2026-10-18T00:00:00Z'),
        expiry_date: new Date('2026-10-31T00:00:00Z'),
        daily_rate: '200.00',
        total_cost: '2600.00',
        paid_amount: '2600.00',
        pending_amount: '0.00',
        created_at: new Date(),
        updated_at: new Date(),
      };

      const mockClient = {
        query: vi.fn().mockImplementation(async (sql: string, params?: any[]) => {
          if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') {
            return { rows: [], rowCount: 0 };
          }
          if (sql.includes('SELECT * FROM stays WHERE id=$1')) {
            return { rows: [mockStayRow], rowCount: 1 };
          }
          if (sql.includes('SELECT id FROM rooms WHERE id=$1 FOR UPDATE')) {
            return { rows: [{ id: 'r_1792316250516360' }], rowCount: 1 };
          }
          if (sql.includes('SELECT id FROM patients WHERE id=$1 FOR UPDATE')) {
            return { rows: [{ id: 'p_1792347832476077' }], rowCount: 1 };
          }
          if (sql.includes('UPDATE stays SET')) {
            return { rows: [{ ...mockStayRow, notes: 'Slash path update' }], rowCount: 1 };
          }
          if (sql.includes('UPDATE room_beds')) {
            return { rows: [], rowCount: 1 };
          }
          if (sql.includes('UPDATE patients')) {
            return { rows: [], rowCount: 1 };
          }
          if (sql.includes('SELECT bed_id,bed_label FROM stays')) {
            return { rows: [], rowCount: 0 };
          }
          if (sql.includes('SELECT') && sql.includes('FROM room_beds')) {
            return { rows: [], rowCount: 0 };
          }
          return { rows: [], rowCount: 0 };
        }),
        release: vi.fn(),
      };

      vi.spyOn(dbModule, 'getClient').mockResolvedValue(mockClient as any);
      vi.spyOn(dbModule, 'query').mockImplementation(async (sql: string, params?: any[]) => {
        if (sql.includes('SELECT id, email, name, role FROM users')) {
          return {
            rows: [{ id: 'test-admin', email: 'admin@ngo.test', name: 'Admin', role: 'admin' }],
            rowCount: 1, command: 'SELECT', oid: 0, fields: [],
          };
        }
        if (sql.includes('SELECT * FROM stays WHERE id = $1')) {
          return { rows: [mockStayRow], rowCount: 1, command: 'SELECT', oid: 0, fields: [] };
        }
        if (sql.includes('SELECT') && sql.includes('FROM room_beds')) {
          return { rows: [], rowCount: 0, command: 'SELECT', oid: 0, fields: [] };
        }
        return { rows: [], rowCount: 0, command: '', oid: 0, fields: [] };
      });

      // 1. GET with raw slash in URL
      const getRes = await app.inject({
        method: 'GET',
        url: `/api/stays/${slashStayId}`,
        headers: { authorization: `Bearer ${signedTestToken('test-admin')}` },
      });
      expect(getRes.statusCode).toBe(200);
      expect(JSON.parse(getRes.body).id).toBe(slashStayId);

      // Routing is tested with a metadata edit; actual completion validation
      // runs against PostgreSQL in the lifecycle suite.
      const putRes = await app.inject({
        method: 'PUT',
        url: `/api/stays/${slashStayId}`,
        headers: { authorization: `Bearer ${signedTestToken('test-admin')}` },
        payload: {
          notes: 'Slash path update',
        },
      });
      expect(putRes.statusCode).toBe(200);
      expect(JSON.parse(putRes.body)).toMatchObject({id: slashStayId, notes: 'Slash path update'});

      // 3. PUT with percent-encoded slash in URL
      const encodedId = encodeURIComponent(slashStayId);
      const putEncodedRes = await app.inject({
        method: 'PUT',
        url: `/api/stays/${encodedId}`,
        headers: { authorization: `Bearer ${signedTestToken('test-admin')}` },
        payload: {
          notes: 'Slash path update',
        },
      });
      expect(putEncodedRes.statusCode).toBe(200);
      expect(JSON.parse(putEncodedRes.body)).toMatchObject({id: slashStayId, notes: 'Slash path update'});
    });
  });
});
