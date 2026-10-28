import { describe, expect, it } from 'vitest';
import { dailyChargeCents, extensionCostCents } from '../src/services/billing.js';
import { projectBilling as projectBillingEngine, quoteStayExtension } from '../src/services/billing.js';
import type pg from 'pg';

const pricing = {
  generalRoomBedPrice: 200,
  privateRoomBasePrice: 700,
  privateRoomIncludedAttendants: 1,
  privateRoomExtraAttendantFee: 200,
};

describe('historical long-stay pricing', () => {
  it('charges General extension days at ₹250 after day 60', () => {
    expect(extensionCostCents('general', 0, 10, pricing, 60)).toBe(250000);
    expect(extensionCostCents('lobby', 0, 10, pricing, 60)).toBe(250000);
    expect(extensionCostCents('general', 1, 10, pricing, 60)).toBe(500000);
  });

  it('changes rate exactly at the 60-to-61 billable-day boundary', () => {
    expect(extensionCostCents('general', 0, 2, pricing, 59)).toBe(45000);
  });

  it('preserves a stored per-stay long-stay override for extension days', () => {
    expect(extensionCostCents('general', 0, 1, pricing, 60, 30000)).toBe(30000);
  });

  it('keeps the first 60 General days at ₹200', () => {
    expect(extensionCostCents('general', 0, 60, pricing, 0)).toBe(1200000);
    expect(extensionCostCents('general', 0, 70, pricing, 0)).toBe(1450000);
    expect(extensionCostCents('general', 0, 10, pricing, 0)).toBe(200000);
    expect(extensionCostCents('general', 0, 10, { ...pricing, generalRoomBedPrice: 150 }, 0)).toBe(200000);
  });

  it('uses the historical Private long-stay surcharge and attendant rule', () => {
    expect(dailyChargeCents('private', 2, pricing, true)).toBe(120000);
    expect(extensionCostCents('private', 2, 1, pricing, 60)).toBe(120000);
  });
});

// These rate fixtures describe the planned booking, independent of the test run date.
const projectBilling: typeof projectBillingEngine = (client, patient, options = {}) =>
  projectBillingEngine(client, patient, { asOf: patient.exit_date ? new Date(patient.exit_date).getTime() : undefined, ...options });

const at = (day: number, hour = 3, minute = 31) => new Date(Date.UTC(2026, 0, day, hour, minute)).toISOString();
const cycle = String(Date.parse(at(1)));
function fixture(options: { days?: number; type?: string; absent?: number; records?: any[]; stays?: any[]; receipts?: any[]; manual?: string; longRate?: string } = {}) {
  const patient = { id: 'synthetic', status: 'active', admission_date: at(1), registration_date: at(1), exit_date: at(options.days ?? 70), attendants: [] };
  const stays = options.stays ?? [{ id: 'stay', patient_id: patient.id, status: 'active', room_type: options.type ?? 'general',
    admission_date: at(1), created_at: at(1), updated_at: at(1), expected_discharge_date: at(71),
    duration_days: 60, total_extended_days: 10, cycle_id: cycle,
    daily_rate_is_manual: options.manual != null, daily_rate: options.manual, long_stay_daily_rate: options.longRate }];
  const records = options.records ?? Array.from({ length: options.absent ?? 0 }, (_, i) => ({ kind: 'attendance', day: at(i + 1).slice(0, 10), payload: { status: 'Absent' } }));
  const client = { query: async (sql: string) => {
    if (sql.startsWith('SELECT * FROM stays')) return { rows: stays };
    if (sql.includes('FROM attendance_records')) return { rows: records };
    if (sql.includes('FROM payments')) return { rows: options.receipts ?? [] };
    if (sql.includes('FROM system_settings')) return { rows: Object.entries(pricing).map(([settings_key, settings_value]) => ({ settings_key, settings_value })) };
    throw new Error(`Unexpected query: ${sql}`);
  } } as unknown as pg.PoolClient;
  return { client, patient, stay: stays[0] };
}
const projection = (options: Parameters<typeof fixture>[0] = {}) => {
  const { client, patient } = fixture(options);
  return projectBilling(client, patient);
};

describe('attendance-aware financial projection', () => {
  it('preserves ₹12,000 for 60 calendar days and adds only ₹2,500 for ten more', async () => {
    expect((await projection({ days: 60 })).balances[cycle].total).toBe(12000);
    expect((await projection()).balances[cycle].total).toBe(14500);
  });

  it('uses billable days rather than recorded extension duration at the threshold', async () => {
    expect((await projection({ absent: 10 })).balances[cycle].total).toBe(12000);
    expect((await projection({ days: 71, absent: 10 })).balances[cycle].total).toBe(12250);
    // The simple helper remains usable only when its caller has a billable count.
    expect(extensionCostCents('general', 0, 10, pricing, 60)).toBe(250000);
  });

  it('keeps Lobby and Private category rates and changing attendant marks', async () => {
    expect((await projection({ type: 'lobby' })).balances[cycle].total).toBe(14500);
    const records = Array.from({ length: 10 }, (_, i) => ['A', 'B'].map(attendantName => ({
      kind: 'attendant_attendance', day: at(i + 61).slice(0, 10), payload: { attendantName, status: 'Present' },
    }))).flat();
    expect((await projection({ type: 'private', records })).balances[cycle].total).toBe(60 * 700 + 10 * 1200);
    expect((await projection({ type: 'general', records })).balances[cycle].total).toBe(12000 + 10 * 750);
    expect((await projection({ type: 'lobby', records })).balances[cycle].total).toBe(12000 + 10 * 750);
  });

  it('retains manual paise rates and a separate stored long-stay override', async () => {
    expect((await projection({ days: 61, manual: '123.45', longRate: '300.00' })).balances[cycle].total).toBe(7707);
  });

  it('counts a transfer boundary once and keeps the admission-wide tier', async () => {
    const stays = [
      { id: 'general', status: 'completed', room_type: 'general', admission_date: at(1), completed_at: at(61), cycle_id: cycle },
      { id: 'private', status: 'active', room_type: 'private', admission_date: at(61), cycle_id: cycle },
    ];
    const result = await projection({ stays });
    expect(result.balances[cycle].total).toBe(12000 + 10 * 900);
    expect(result.balances[cycle].segmentDays).toEqual({ general: 60, private: 10 });
  });

  it('reconciles actual receipts and refunds without adding approval estimates twice', async () => {
    const receipts = [
      { amount: '15000.00', cycle_id: cycle, payment_date: at(2) },
      { amount: '-500.00', cycle_id: cycle, payment_date: at(70) },
    ];
    expect((await projection({ receipts })).balances[cycle]).toMatchObject({ total: 14500, paid: 15000, refunded: 500, netPaid: 14500, due: 0, refundDue: 0, status: 'Paid' });
  });
});

describe('approval quotes share the final invoice engine', () => {
  it.each(['general', 'lobby'])('%s quotes ten additional days at ₹250 only after 60 billable days', async type => {
    const f = fixture({ days: 60, type });
    expect(await quoteStayExtension(f.client, f.patient, f.stay, 10)).toMatchObject({ additionalCost: 2500, priorBillableDays: 60 });
  });
  it('ten absent days defer the higher rate and do not reprice earlier days', async () => {
    const f = fixture({ days: 60, absent: 10 });
    expect(await quoteStayExtension(f.client, f.patient, f.stay, 10)).toMatchObject({ additionalCost: 2000, priorBillableDays: 50 });
    expect(await quoteStayExtension(f.client, f.patient, f.stay, 11)).toMatchObject({ additionalCost: 2250 });
  });
  it('uses only present attendants, Private rates and stored overrides', async () => {
    const records = Array.from({ length: 10 }, (_, i) => ['A', 'B'].map(attendantName => ({ kind: 'attendant_attendance', day: at(i + 61).slice(0, 10), payload: { attendantName, status: 'Present' } }))).flat();
    const privateStay = fixture({ days: 60, type: 'private', records });
    expect((await quoteStayExtension(privateStay.client, privateStay.patient, privateStay.stay, 10)).additionalCost).toBe(12000);
    const manual = fixture({ days: 60, manual: '123.45', longRate: '300.00' });
    expect((await quoteStayExtension(manual.client, manual.patient, manual.stay, 1)).additionalCost).toBe(300);
  });
  it('does not charge overdue days twice when an open admission already bills them', async () => {
    const f = fixture();
    const patient = { ...f.patient, exit_date: null };
    expect((await quoteStayExtension(f.client, patient, { ...f.stay, expected_discharge_date: at(3) }, 1)).additionalCost).toBe(0);
  });
  it('rejects zero-length and closed-stay approvals', async () => {
    const f = fixture({ days: 60 });
    await expect(quoteStayExtension(f.client, f.patient, f.stay, 0)).rejects.toThrow('Invalid stay extension');
    await expect(quoteStayExtension(f.client, f.patient, { ...f.stay, status: 'completed' }, 1)).rejects.toThrow('active admission');
  });
});
