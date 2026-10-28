import { describe, expect, it } from 'vitest';
import { projectBilling, receiptCycle, stayCycle, newStayIdentity } from '../src/services/billing.js';

describe('unallocated payment reconciliation', () => {
  const legacyStart = new Date('2026-08-01T04:00:00Z');
  const legacyCycle = String(legacyStart.getTime());
  async function legacyProjection(overrides: any = {}, receiptOverrides: any = {}) {
    const patient = { id: 'imported', status: 'discharged', admission_date: legacyStart,
      admission_balances: { [legacyCycle]: { total: 300, paid: 600, refunded: 50, netPaid: 550,
        due: 0, refundDue: 250, finalized: true } }, ...overrides };
    const receipts = [
      { id: 'cash', cycle_id: null, source: 'firebase_export', method: 'Cash', amount: '200.00', ...receiptOverrides },
      { id: 'qr', cycle_id: null, source: 'firebase_export', method: 'Online (QR Code)', amount: '400.00' },
      { id: 'returned', cycle_id: legacyCycle, source: 'manual', amount: '-50.00' },
    ];
    const source = { stays: [], records: [], roster: [], pricing: {}, receipts };
    const original = JSON.stringify({ patient, source });
    const result = await projectBilling({} as any, patient, { source });
    expect(JSON.stringify({ patient, source })).toBe(original);
    return result;
  }
  it('retains a ledger-supported closed Firebase invoice without allocating or duplicating legacy receipts', async () => {
    const result = await legacyProjection();
    expect(result.reconciliation).toMatchObject({ required: false, allocationRequired: true,
      legacyInvoiceSupported: true, unallocatedNet: 600, accountPaid: 600, accountRefunded: 50 });
    expect(result.balances[legacyCycle]).toMatchObject({ total: 300, paid: 600, refunded: 50,
      netPaid: 550, refundDue: 250, reconciliationRequired: false });
    expect(result.patient.total_refund_due_amount).toBe('250.00');
    expect(result.receipts.map(r => r.method)).toEqual(['Cash', 'Online (QR Code)', undefined]);
    expect(result.receipts[0].cycle_id).toBeNull();
    expect(receiptCycle(result.receipts[0], result.patient, [])).toBeNull();
  });
  it.each([
    ['manual receipt', {}, { source: 'manual' }],
    ['unknown explicit cycle', {}, { cycle_id: 'unknown' }],
    ['active admission', { status: 'active' }, {}],
    ['multiple cycles', { admission_balances: { [legacyCycle]: { total: 300, paid: 600, refunded: 50, netPaid: 550, due: 0, refundDue: 250 }, old: { total: 100 } } }, {}],
    ['inconsistent invoice', { admission_balances: { [legacyCycle]: { total: 300, paid: 700, refunded: 50, netPaid: 650, due: 0, refundDue: 350 } } }, {}],
    ['provisional invoice', { admission_balances: { [legacyCycle]: { total: 300, paid: 600, refunded: 50, netPaid: 550, due: 0, refundDue: 250, provisional: true } } }, {}],
    ['missing invoice', { admission_balances: {} }, {}],
  ])('keeps reconciliation for %s', async (_name, patient, receipt) => {
    const result = await legacyProjection(patient, receipt);
    expect(result.reconciliation.required).toBe(true);
    expect(result.reconciliation.legacyInvoiceSupported).toBeFalsy();
  });
  it('uses the same conservative allocation for projections, mutations and imports', () => {
    const patient = { admission_date: new Date('2026-10-01T00:00:00Z') };
    const old = { cycle_id: 'old', status: 'completed' };
    expect(receiptCycle({ payment_date: patient.admission_date }, patient, [old])).toBeNull();
    expect(receiptCycle({ cycle_id: 'verified', payment_date: patient.admission_date }, patient, [old])).toBe('verified');
    expect(receiptCycle({}, patient, [])).toBeNull();
    expect(receiptCycle({}, patient, [], 'new')).toBe(String(patient.admission_date.getTime()));
  });
  it('retains orphan and ambiguous receipts once without authorizing their allocation', async () => {
    const start = new Date('2026-10-01T04:00:00Z');
    const cycle = String(start.getTime());
    const historical = String(new Date('2026-09-10T04:00:00Z').getTime());
    const patient = { id: 'fixture', status: 'active', admission_date: start, exit_date: start, attendants: [], admission_balances: { [historical]: { total: 800, finalized: true } } };
    const stays = [
      { id: 'current', cycle_id: cycle, status: 'active', admission_date: start, room_type: 'general', patient_snapshot: { attendants: [] } },
      { id: 'old', cycle_id: historical, status: 'completed', admission_date: new Date('2026-09-01T04:00:00Z'), completed_at: new Date('2026-09-08T04:00:00Z'), room_type: 'general', total_cost: '800.00' },
    ];
    const receipts = [
      { id: 'matched', cycle_id: cycle, amount: '400.00', payment_date: start },
      { id: 'orphan', cycle_id: 'unknown', amount: '1200.00', payment_date: start },
      { id: 'ambiguous', cycle_id: null, amount: '4400.00', payment_date: new Date('2026-09-04T04:00:00Z') },
    ];
    const result = await projectBilling({} as any, patient, { source: { stays, records: [], receipts, pricing: {}, roster: [] }, checkoutAt: start });
    expect(result.reconciliation).toMatchObject({ required: true, unallocatedNet: 5600, accountPaid: 6000, accountRefunded: 0 });
    expect(result.reconciliation.unallocatedReceipts.map(r => r.id)).toEqual(['orphan', 'ambiguous']);
    expect(result.balances[cycle]).toMatchObject({ paid: 400, reconciliationRequired: true });
    expect(result.balances[historical]).toMatchObject({ total: 800, paid: 0, reconciliationRequired: true });
  });
  it('preserves the 5157 structural conflict, both frozen charges and the shared-snapshot receipt', async () => {
    const admission = new Date('2026-10-11T11:09:35.040Z');
    const patient = { id: 'structural-fixture', status: 'discharged', admission_date: admission,
      admission_balances: { explicitA: { total: 1200, finalized: true }, explicitB: { total: 1200, finalized: true } } };
    const stays = ['A', 'B'].map(suffix => ({ id: `stay${suffix}`, patient_id: patient.id, room_id: 'same-room', bed_id: `bed${suffix}`,
      cycle_id: `explicit${suffix}`, patient_snapshot: { admissionDate: 'shared-snapshot' }, status: 'completed',
      admission_date: new Date('2026-09-20T04:00:00Z'), completed_at: new Date('2026-09-23T04:00:00Z'), total_cost: '1200.00' }));
    const receipts = [{ id: 'receipt', cycle_id: 'shared-snapshot', amount: '1200.00' }];
    const source = { stays, receipts, records: [], pricing: {}, roster: [] };
    const original = JSON.stringify(source);
    const result = await projectBilling({} as any, patient, { source });
    expect(result.reconciliation).toMatchObject({ required: true, accountPaid: 1200, unallocatedNet: 1200 });
    expect(result.reconciliation.cycleIdentityIssues).toHaveLength(2);
    expect(result.balances.explicitA).toMatchObject({ total: 1200, paid: 0, reconciliationRequired: true });
    expect(result.balances.explicitB).toMatchObject({ total: 1200, paid: 0, reconciliationRequired: true });
    expect(result.balances['shared-snapshot']).toBeUndefined();
    expect(JSON.stringify(source)).toBe(original);
    expect(result.stays).toEqual(stays);
  });
  it('does not prove legacy ownership from one remaining cycle or a saved aggregate', async () => {
    const start = new Date('2026-10-01T04:00:00Z');
    const cycle = String(start.getTime());
    const patient = { id: 'legacy', status: 'discharged', admission_date: start,
      admission_balances: { [cycle]: { total: 100, paid: 200, finalized: true } } };
    const result = await projectBilling({} as any, patient, { source: { stays: [], records: [], roster: [], pricing: {},
      receipts: [{ id: 'legacy', cycle_id: null, amount: '200.00', payment_date: start }] } });
    expect(result.reconciliation).toMatchObject({ required: true, accountPaid: 200, unallocatedNet: 200 });
    expect(result.balances[cycle]).toMatchObject({ total: 100, paid: 0, refundDue: 0 });
  });
  it('resolves missing stay identity only from a unique saved segment owner', () => {
    const patient = { admission_date: new Date(), admission_balances: { established: { segmentCharges: { segment: 1200 } } } };
    const stay = { id: 'segment', created_at: new Date(), admission_date: patient.admission_date };
    expect(stayCycle(stay, patient)).toBe('established');
    expect(stayCycle(stay, { ...patient, admission_balances: {} })).toBe('unresolved-stay:segment');
    expect(stayCycle(stay, { ...patient, admission_balances: { ...patient.admission_balances, other: { segmentCharges: { segment: 1200 } } } })).toBe('unresolved-stay:segment');
  });
  it('stamps admission identity for placements and rejects conflicting explicit or snapshot cycles', () => {
    const patient = { admission_date: new Date('2026-10-01T04:00:00Z') };
    const cycle = String(patient.admission_date.getTime());
    expect(newStayIdentity(patient, { admissionDate: new Date('2026-10-10T04:00:00Z') })).toEqual({ cycleId: cycle, snapshotAdmission: Number(cycle) });
    expect(() => newStayIdentity(patient, { cycleId: 'placement-time' })).toThrow(/cycle conflicts/);
    expect(() => newStayIdentity(patient, { cycleId: cycle, patientSnapshot: { admissionDate: 'stale-snapshot' } })).toThrow(/cycle conflicts/);
    expect(() => newStayIdentity(patient, { status: 'completed' })).toThrow(/cycle conflicts/);
    expect(() => newStayIdentity(patient, { billingSummary: { admissionId: 'stale' } })).toThrow(/cycle conflicts/);
  });
  it('does not certify the stored-field 800 credit without invoice evidence', async () => {
    const start = new Date('2026-10-01T04:00:00Z');
    const cycle = String(start.getTime());
    const patient = { id: 'missing-invoice', admission_date: start, status: 'discharged', advance_billed_amount: '3200.00',
      attendance_charges: '0.00', total_paid_amount: '4000.00', refund_due_amount: '0.00' };
    const result = await projectBilling({} as any, patient, { source: { stays: [], records: [], pricing: {}, roster: [],
      receipts: [{ id: 'receipt', cycle_id: cycle, amount: '4000.00' }] } });
    expect(result.reconciliation).toMatchObject({ required: true, accountPaid: 4000, unallocatedNet: 0,
      chargeIssues: [{ reason: 'missing_invoice_evidence' }] });
    expect(result.balances[cycle]).toMatchObject({ total: 3200, refundDue: 800, reconciliationRequired: true });
  });
});
