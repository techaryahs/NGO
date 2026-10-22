import { describe, expect, it } from 'vitest';
import type pg from 'pg';
import { afterCheckoutCutoff, baseDailyChargeCents, dailyChargeCents, projectBilling } from '../src/services/billing.js';

const at = (day: number, hour = 3, minute = 30) => new Date(Date.UTC(2026, 0, day, hour, minute));
const cycle = String(at(1, 0).getTime());
function fixture(options: { days?: number; category?: string; patientStatus?: string; people?: any[]; attendantStates?: string[]; patientStates?: string[]; beds?: number; saved?: any; pricing?: Record<string, any> } = {}) {
  const count = options.days ?? 1;
  const people = options.people ?? [];
  const patient = { id: 'synthetic', admission_date: at(1, 0), registration_date: at(1, 0), status: options.patientStatus ?? 'active',
    exit_date: at(count), discharge_date: at(count), attendants: people, admission_balances: options.saved ? { [cycle]: options.saved } : {} };
  const stays = Array.from({ length: options.beds ?? 1 }, (_, index) => ({ id: `s${index}`, patient_id: patient.id, status: 'active',
    admission_date: at(1, 0), created_at: at(1, 0), updated_at: at(1, 0), expected_discharge_date: at(count),
    duration_days: count, total_extended_days: 0, cycle_id: cycle, room_type: options.category ?? 'general',
    patient_snapshot: { attendants: people }, total_cost: '0.00' }));
  const records = Array.from({ length: count }, (_, index) => [
    { kind: 'attendance', day: at(index + 1).toISOString().slice(0, 10), payload: { status: options.patientStates?.[index] ?? 'Present' } },
    { kind: 'attendant_attendance', day: at(index + 1).toISOString().slice(0, 10), payload: Object.fromEntries(people.map((person, i) =>
      [person.id, { attendantId: person.id, attendantName: person.name, status: options.attendantStates?.[i] ?? 'Present' }])) },
  ]).flat();
  const source = { stays, records, receipts: [], roster: people, pricing: { generalRoomBedPrice: 200, privateRoomBasePrice: 700,
    privateRoomExtraAttendantFee: 200, privateRoomIncludedAttendants: 1, ...options.pricing } };
  const client = { query: async () => { throw new Error('Pure fixture must not query external data'); } } as unknown as pg.PoolClient;
  return { patient, source, client };
}
async function calculate(options: Parameters<typeof fixture>[0], checkoutAt?: Date) {
  const f = fixture(options);
  return projectBilling(f.client, f.patient, { source: f.source, checkoutAt });
}

describe('approved client billing rules', () => {
  it('post-admission attendee charges and Pending requirements start at association, including imported early marks', async () => {
    const people = [{ id: 'late-person', name: 'Late arrival', startDate: '2026-01-06' }];
    const f = fixture({ days: 10, people });
    const first = await projectBilling(f.client, f.patient, { source: f.source });
    expect(first.balances[cycle].total).toBe(3000);
    expect(first.stays[0]).toMatchObject({ base_cost: '2000.00', extra_attendant_cost: '1000.00', total_cost: '3000.00' });
    f.source.records.find(r => r.kind === 'attendant_attendance' && r.day === '2026-01-06')!.payload[people[0].id].status = 'Absent';
    f.source.records.find(r => r.kind === 'attendant_attendance' && r.day === '2026-01-07')!.payload[people[0].id].status = 'Pending';
    const next = await projectBilling(f.client, f.patient, { source: f.source });
    expect(next.balances[cycle].total).toBe(2600);
    expect(next.stays[0]).toMatchObject({ base_cost: '2000.00', extra_attendant_cost: '600.00' });
    expect(next.balances[cycle].pendingAttendance).toEqual([{ day: '2026-01-07', kind: 'attendant_attendance', attendantId: people[0].id }]);
  });
  it('a later transfer snapshot cannot make an imported early attendant mark billable in the old room', async () => {
    const f = fixture({ days: 10, people: [{ id: 'late-person', name: 'Late arrival', startDate: '2026-01-06' }] });
    const original = f.source.stays[0];
    const previous = { ...original, id: 'previous', status: 'completed', completed_at: at(5), patient_snapshot: { attendants: [] } };
    f.source.stays = [previous, { ...original, admission_date: at(5) }];
    expect((await projectBilling(f.client, f.patient, { source: f.source })).balances[cycle].total).toBe(3000);
  });
  it.each([['general', 60, 12000], ['general', 70, 14500], ['lobby', 70, 14500], ['private', 60, 42000], ['private', 70, 51000]])(
    '%s %i applicable days cost ₹%i', async (category, days, total) => {
      expect((await calculate({ category: String(category), days: Number(days) })).balances[cycle].total).toBe(total);
    });
  it('General patient and one Present attendant cost ₹400 initially and ₹500 after day 60', async () => {
    const people = [{ id: 'one', name: 'One' }];
    expect((await calculate({ days: 1, people })).balances[cycle].total).toBe(400);
    expect((await calculate({ days: 61, people })).balances[cycle].total).toBe(24500);
  });
  it.each([['Absent', 'Present', 200], ['Present', 'Absent', 200], ['Absent', 'Absent', 0]])(
    'independently evaluates patient %s and helper %s', async (patientState, attendantState, expected) => {
      expect((await calculate({ people: [{ id: 'one', name: 'One' }], patientStates: [String(patientState)], attendantStates: [String(attendantState)] })).balances[cycle].total).toBe(expected);
    });
  it('Private has exactly one included attendant even when a legacy setting says zero or two', async () => {
    for (const included of [0, 2]) {
      expect(baseDailyChargeCents('private', 2, { privateRoomIncludedAttendants: included })).toBe(90000);
      expect(dailyChargeCents('private', 2, { privateRoomIncludedAttendants: included })).toBe(120000);
    }
  });
  it('Private included attendant remains in the base line and only additional attendance is separate', async () => {
    const one = await calculate({ days: 10, category: 'private', people: [{id:'included',name:'Included'}] });
    expect(one.stays[0]).toMatchObject({ base_cost:'7000.00',extra_attendant_cost:'0.00',total_cost:'7000.00' });
    const two = await calculate({ days: 10, category: 'private', people: [{id:'included',name:'Included'},{id:'extra',name:'Extra'}] });
    expect(two.stays[0]).toMatchObject({ base_cost:'7000.00',extra_attendant_cost:'2000.00',total_cost:'9000.00' });
  });
  it('new admissions use approved tariffs despite conflicting legacy global settings', async () => {
    const pricing = { generalRoomBedPrice: 350, privateRoomBasePrice: 1100, privateRoomExtraAttendantFee: 450, privateRoomIncludedAttendants: 2 };
    const people = [{ id: 'a', name: 'A' }, { id: 'b', name: 'B' }];
    expect((await calculate({ pricing, people })).balances[cycle].total).toBe(600);
    expect((await calculate({ category: 'private', pricing, people })).balances[cycle].total).toBe(900);
  });
  it('Private absent patient retains reserved base and only Present additional attendants are charged', async () => {
    const people = [{ id: 'a', name: 'A' }, { id: 'b', name: 'B' }, { id: 'c', name: 'C' }];
    expect((await calculate({ category: 'private', patientStates: ['Absent'], people, attendantStates: ['Present', 'Present', 'Absent'] })).balances[cycle].total).toBe(900);
    const absent = Array.from({ length: 61 }, () => 'Absent');
    expect((await calculate({ days: 61, category: 'private', patientStates: absent, people, attendantStates: ['Present', 'Present', 'Absent'] })).balances[cycle].total).toBe(54900);
    expect((await calculate({ days: 61, category: 'private', patientStates: absent })).balances[cycle].total).toBe(42700);
  });
  it('65 attendant-only General days do not advance the patient Present threshold', async () => {
    const patientStates = Array.from({ length: 65 }, () => 'Absent');
    const result = await calculate({ days: 65, people: [{ id: 'helper', name: 'Helper' }], patientStates });
    expect(result.balances[cycle].total).toBe(13000);
  });
  it('Private absence before 60 actual Present days retains the initial room tier', async () => {
    const patientStates = [...Array.from({ length: 20 }, () => 'Absent'), ...Array.from({ length: 60 }, () => 'Present')];
    expect((await calculate({ days: 80, category: 'private', patientStates })).balances[cycle].total).toBe(56000);
    patientStates.push('Present');
    expect((await calculate({ days: 81, category: 'private', patientStates })).balances[cycle].total).toBe(56900);
  });
  it('an ID-keyed same-name roster is not collapsed into one attendant', async () => {
    const people = [{ id: 'a', name: 'Same' }, { id: 'b', name: 'Same' }];
    expect((await calculate({ people })).balances[cycle].total).toBe(600);
    expect((await calculate({ people, attendantStates: ['Present', 'Absent'] })).balances[cycle].total).toBe(400);
  });
  it('legacy unique-name attendance remains billable without discarding stored records', async () => {
    const f = fixture({ people: [{ id: 'stable', name: 'Old Name' }] });
    f.source.records[1].payload = { attendantName: 'Old Name', status: 'Present' } as any;
    expect((await projectBilling(f.client, f.patient, { source: f.source })).balances[cycle].total).toBe(400);
    expect(f.source.records[1].payload).toEqual({ attendantName: 'Old Name', status: 'Present' });
  });
  it('an ambiguous legacy same-name mark cannot become Present for both snapshot attendants', async () => {
    const f = fixture({ people: [{ id: 'a', name: 'Same' }, { id: 'b', name: 'Same' }] });
    (f.source.stays[0].patient_snapshot as any).attendants = [{ name: 'Same' }, { name: 'Same' }];
    f.source.records[1].payload = { Same: { attendantName: 'Same', status: 'Present' } } as any;
    const result = await projectBilling(f.client, f.patient, { source: f.source });
    expect(result.balances[cycle].total).toBe(200);
    expect(result.balances[cycle].pendingAttendance.filter((entry: any) => entry.kind === 'attendant_attendance')).toHaveLength(2);
    expect(result.balances[cycle].provisional).toBe(true);
    expect(f.source.records[1].payload).toEqual({ Same: { attendantName: 'Same', status: 'Present' } });
  });
  it('unmarked and explicit Pending records stay provisional and are listed for finalization', async () => {
    const f = fixture({ people: [{ id: 'a', name: 'A' }] });
    f.source.records = [];
    const result = await projectBilling(f.client, f.patient, { source: f.source });
    expect(result.attendance.has('2026-01-01')).toBe(false);
    expect(result.balances[cycle]).toMatchObject({ provisional: true, pendingAttendance: [
      { day: '2026-01-01', kind: 'attendance' }, { day: '2026-01-01', kind: 'attendant_attendance', attendantId: 'a' },
    ] });
    expect((await calculate({ patientStates: ['Pending'] })).balances[cycle].provisional).toBe(true);
  });
  it('an explicitly Pending historical attendant outside the current roster still blocks finalization', async () => {
    const f = fixture();
    f.source.records[1].payload = { departed: { attendantId: 'departed', attendantName: 'Historical helper', status: 'Pending' } } as any;
    const result = await projectBilling(f.client, f.patient, { source: f.source });
    expect(result.balances[cycle].total).toBe(200);
    expect(result.balances[cycle]).toMatchObject({ provisional: true, pendingAttendance: [
      { day: '2026-01-01', kind: 'attendant_attendance', attendantId: 'departed' },
    ] });
  });
  it('General multi-bed occupancy never multiplies patient pricing', async () => {
    const result = await calculate({ days: 70, beds: 3 });
    expect(result.balances[cycle].total).toBe(14500);
    expect(Object.values(result.balances[cycle].segmentDays).reduce((sum: number, value: any) => sum + value, 0)).toBe(70);
  });
  it.each([[7, 3, 29, 1200, 0], [7, 3, 30, 1200, 0], [7, 3, 31, 1400, 200], [60, 3, 31, 12000, 200], [61, 3, 31, 12250, 250], [65, 3, 31, 13250, 250]])(
    'checkout day %i at %i:%i UTC counts the date once at the applicable tier', async (days, hour, minute, expected, adjustment) => {
      const result = await calculate({ days }, at(days, hour, minute));
      expect(result.balances[cycle].total).toBe(expected);
      expect(result.balances[cycle].checkoutAdjustment?.amount ?? 0).toBe(adjustment);
      expect(result.balances[cycle].checkoutAdjustment?.includedInTotal).toBe(true);
      expect(result.balances[cycle].checkoutAdjustment?.included).toBe(minute > 30);
    });
  it('checkout at precisely 9 AM is free of adjustment, 9:01 AM passes the cutoff', () => {
    expect(afterCheckoutCutoff(at(7, 3, 30))).toBe(false);
    expect(afterCheckoutCutoff(at(7, 3, 31))).toBe(true);
    expect(afterCheckoutCutoff(at(7, 3, 29))).toBe(false);
  });
  it.each(['general', 'lobby', 'private'])('%s excludes checkout at or before09:00 IST and includes it once after09:00', async category => {
    const daily = category === 'private' ? 700 : 200;
    for (const minute of [29, 30, 31]) {
      const result = await calculate({ days: 7, category }, at(7, 3, minute));
      expect(result.balances[cycle].total).toBe((minute > 30 ? 7 : 6) * daily);
      expect(result.balances[cycle].checkoutAdjustment).toMatchObject({ amount: minute > 30 ? daily : 0, included: minute > 30, includedInTotal: true });
      expect(Object.values(result.balances[cycle].segmentDays).reduce((sum: number, value: any) => sum + value, 0)).toBe(minute > 30 ? 7 : 6);
    }
  });
  it('checkout date includes Present attendants only at the applicable tier without an added surcharge', async () => {
    const people = [{ id: 'a', name: 'A' }, { id: 'b', name: 'B' }];
    const result = await calculate({ days: 61, people, attendantStates: ['Present', 'Absent'] }, at(61, 3, 31));
    expect(result.balances[cycle].total).toBe(24500);
    expect(result.balances[cycle].checkoutAdjustment).toMatchObject({ amount: 500, patientAmount: 250, attendantAmount: 250, patientPresentDaysBefore: 60, includedInTotal: true, included: true });
  });
  it('an absent checkout patient adds no charge while the independently Present helper uses ₹250', async () => {
    const patientStates = Array.from({ length: 61 }, (_, index) => index === 60 ? 'Absent' : 'Present');
    const result = await calculate({ days: 61, people: [{ id: 'a', name: 'A' }], patientStates }, at(61, 3, 31));
    expect(result.balances[cycle].total).toBe(24250);
    expect(result.balances[cycle].checkoutAdjustment).toMatchObject({ amount: 250, patientAmount: 0, attendantAmount: 250, patientPresentDaysBefore: 60 });
  });
  it('Private checkout after 9 AM includes its applicable room rate once', async () => {
    const result = await calculate({ days: 61, category: 'private' }, at(61, 3, 31));
    expect(result.balances[cycle].total).toBe(42900);
    expect(result.balances[cycle].checkoutAdjustment).toMatchObject({ amount: 900, included: true, includedInTotal: true });
  });
  it('a Private-to-General downgrade charges the destination date once and keeps the admission-wide threshold', async () => {
    const f = fixture({ days: 70 });
    f.source.stays = [
      { ...f.source.stays[0], id: 'old-private', room_type: 'private', status: 'completed', completed_at: at(61, 3, 31) },
      { ...f.source.stays[0], id: 'new-general', room_type: 'general', admission_date: at(61), notes: 'Room transfer' },
    ];
    const result = await projectBilling(f.client, f.patient, { source: f.source });
    expect(result.balances[cycle]).toMatchObject({ total: 44500, segmentDays: { 'old-private': 60, 'new-general': 10 } });
  });
  it('an ambiguous historical overlap without transfer evidence uses the higher room rate once', async () => {
    const f = fixture({ days: 70 });
    f.source.stays = [
      { ...f.source.stays[0], id: 'old-private', room_type: 'private', status: 'completed', completed_at: at(61, 3, 31) },
      { ...f.source.stays[0], id: 'new-general', room_type: 'general', admission_date: at(61) },
    ];
    const result = await projectBilling(f.client, f.patient, { source: f.source });
    expect(result.balances[cycle]).toMatchObject({ total: 45150, segmentDays: { 'old-private': 61, 'new-general': 9 } });
  });
  it('saved per-stay pricing prevents a settings change from repricing the completed period', async () => {
    const f = fixture({ days: 61 });
    (f.source.stays[0] as any).billing_summary = { pricing: { generalRoomBedPrice: 200 } };
    f.source.pricing.generalRoomBedPrice = 999;
    expect((await projectBilling(f.client, f.patient, { source: f.source })).balances[cycle].total).toBe(12250);
  });
  it('frozen financial history is unchanged by current settings or recalculation', async () => {
    const saved = { total: 1234, segmentCharges: { s0: 1234 }, segmentDays: { s0: 7 }, checkoutAdjustment: { amount: 34 }, provisional: false };
    const f = fixture({ days: 7, patientStatus: 'discharged', saved, pricing: { generalRoomBedPrice: 999 } });
    const result = await projectBilling(f.client, f.patient, { source: f.source, finalize: true });
    expect(result.balances[cycle]).toMatchObject(saved);
    expect(saved.total).toBe(1234);
  });
  it('a finalized legacy stay without saved admission balances preserves its stored invoice', async () => {
    const f = fixture({ days: 7, patientStatus: 'discharged', pricing: { generalRoomBedPrice: 999 } });
    f.source.stays[0].status = 'completed';
    f.source.stays[0].total_cost = '1234.00';
    (f.source.stays[0] as any).completed_at = at(7);
    const result = await projectBilling(f.client, f.patient, { source: f.source, finalize: true });
    expect(result.balances[cycle]).toMatchObject({ total: 1234, finalized: true, segmentCharges: { s0: 1234 } });
    expect(result.stays[0].total_cost).toBe('1234.00');
  });
});
