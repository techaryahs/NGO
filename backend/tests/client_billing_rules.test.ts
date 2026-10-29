import { describe, expect, it } from 'vitest';
import type pg from 'pg';
import { afterCheckoutCutoff, baseDailyChargeCents, dailyChargeCents, projectBilling as projectBillingEngine, quoteStayExtension } from '../src/services/billing.js';

// These rate fixtures describe the planned booking, independent of the test run date.
const projectBilling: typeof projectBillingEngine = (client, patient, options = {}) =>
  projectBillingEngine(client, patient, { asOf: patient.exit_date ? new Date(patient.exit_date).getTime() : undefined, ...options });

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
  it('excludes selected date charges without altering receipt allocation or attendance and preserves refunds', async () => {
    const f = fixture({ days: 4 });
    f.source.records.splice(-2); // No attendance on the planned 9 AM exit day.
    f.source.receipts.push({ id: 'paid', cycle_id: cycle, amount: '600.00' } as never);
    const correction = (day: string) => ({ cycle_id: cycle, stay_id: 's0', billable_day: day });
    const before = await projectBilling(f.client, f.patient, { source: f.source });
    expect(before.balances[cycle]).toMatchObject({ total: 600, netPaid: 600, due: 0, refundDue: 0 });
    const one = await projectBilling(f.client, f.patient, { source: { ...f.source, corrections: [correction('2026-01-01')] } });
    expect(one.balances[cycle]).toMatchObject({ total: 400, netPaid: 600, due: 0, refundDue: 200, actualPatientPresentDays: 3 });
    const two = await projectBilling(f.client, f.patient, { source: { ...f.source, corrections: [correction('2026-01-01'), correction('2026-01-02')] }, includeDayCharges: true });
    expect(two.balances[cycle]).toMatchObject({ total: 200, netPaid: 600, due: 0, refundDue: 400, actualPatientPresentDays: 3 });
    expect(two.balances[cycle].dayCharges.filter((d: any) => d.excluded)).toHaveLength(2);
    const final = await projectBilling(f.client, { ...f.patient, status: 'discharged' }, { source: { ...f.source, corrections: [correction('2026-01-01'), correction('2026-01-02')] }, finalize: true, checkoutAt: at(4) });
    expect(final.balances[cycle]).toMatchObject({ total: 200, netPaid: 600, refundDue: 400 });
  });

  it('quotes October 23 to 28 as five additional patient-and-attendant days, without rebilling the advance', async () => {
    const f = fixture({ days: 13, people: [{ id: 'helper', name: 'Helper' }] });
    const start = new Date('2026-10-16T07:30:00Z');
    const current = String(start.getTime());
    f.patient.admission_date = start;
    f.patient.exit_date = new Date('2026-10-23T14:30:00Z');
    Object.assign(f.source.stays[0], { admission_date: start, cycle_id: current,
      expected_discharge_date: new Date('2026-10-24T03:30:00Z') });
    f.source.records.forEach((r, i) => { r.day = `2026-10-${16 + Math.floor(i / 2)}`; });
    (f.source.receipts as any[]).push({ id: 'advance', cycle_id: current, amount: '3200.00' });
    const query = async (sql: string) => ({ rows: sql.includes('FROM stays') ? f.source.stays :
      sql.includes('FROM attendance_records') ? f.source.records : sql.includes('FROM payments') ? f.source.receipts :
      sql.includes('FROM patient_attendants') ? f.source.roster : [] });
    const before = await projectBilling({ query } as any, f.patient);
    expect(before.balances[current]).toMatchObject({ total: 3200, paid: 3200, due: 0 });
    expect(await quoteStayExtension({ query } as any, f.patient, f.source.stays[0], 5)).toMatchObject({ additionalCost: 2000 });
    const overdueAt = Date.parse('2026-10-28T11:44:00Z');
    const overdue = await projectBillingEngine(f.client, f.patient, { source: f.source, asOf: overdueAt });
    expect(overdue.balances[current]).toMatchObject({ total: 3200, netPaid: 3200, due: 0, refundDue: 0 });
    (f.source.receipts as any[]).push({ id: 'collection', cycle_id: current, amount: '2000.00' });
    const withStalePreview = { ...f.patient, admission_balances: { [current]: { checkoutAt: start.getTime() } } };
    const collected = await projectBillingEngine(f.client, withStalePreview, { source: f.source, asOf: overdueAt, useSavedCheckout: true });
    expect(collected.balances[current]).toMatchObject({ total: 3200, netPaid: 5200, due: 0, refundDue: 2000 });
    (f.source.receipts as any[]).pop();
    const checkoutAt = new Date('2026-10-28T11:44:00Z');
    const preview = await projectBilling(f.client, f.patient, { source: f.source, checkoutAt });
    expect(preview.balances[current]).toMatchObject({ total: 5200, netPaid: 3200, due: 2000,
      checkoutAdjustment: { includedInTotal: true, amount: 400 } });
    (f.source.receipts as any[]).push({ id: 'extension', cycle_id: current, amount: '2000.00' });
    const paidPreview = await projectBilling(f.client, f.patient, { source: f.source, checkoutAt });
    expect(paidPreview.balances[current]).toMatchObject({ total: 5200, netPaid: 5200, due: 0 });
    (f.source.receipts as any[]).pop();
    const extended = { ...f.patient, exit_date: new Date('2026-10-28T14:30:00Z') };
    const full = await projectBilling({ query } as any, extended);
    expect(full.balances[current]).toMatchObject({ total: 5200, paid: 3200, due: 2000 });
    const shorter = await projectBilling({ query } as any, { ...extended, exit_date: new Date('2026-10-27T14:30:00Z') });
    expect(shorter.balances[current].total).toBe(4800);
  });
  it('late October checkout requires both kinds through the actual date, not just the planned exit', async () => {
    const person = { id: 'helper', name: 'Helper' };
    const f = fixture({ days: 8, people: [person] });
    const start = new Date('2026-10-16T06:00:00Z');
    const current = String(start.getTime());
    f.patient.admission_date = start;
    f.patient.registration_date = start;
    f.patient.exit_date = new Date('2026-10-23T14:30:00Z');
    Object.assign(f.source.stays[0], { admission_date: start, cycle_id: current });
    f.source.records.forEach((r, index) => { r.day = `2026-10-${16 + Math.floor(index / 2)}`; });
    const checkoutAt = new Date('2026-10-28T04:29:00Z');
    const result = await projectBilling(f.client, f.patient, { source: f.source, checkoutAt });
    const missing = result.balances[current].pendingAttendance;
    expect(missing.filter((r: any) => r.kind === 'attendance').map((r: any) => r.day)).toEqual(['2026-10-24', '2026-10-25', '2026-10-26', '2026-10-27', '2026-10-28']);
    expect(missing.filter((r: any) => r.kind === 'attendant_attendance')).toHaveLength(5);
    for (let day = 24; day <= 28; day++) {
      f.source.records.push({ kind: 'attendance', day: `2026-10-${day}`, payload: { status: 'Absent' } });
      f.source.records.push({ kind: 'attendant_attendance', day: `2026-10-${day}`, payload: { helper: { attendantId: 'helper', attendantName: 'Helper', status: 'Present' } } });
    }
    expect((await projectBilling(f.client, f.patient, { source: f.source, checkoutAt })).balances[current].pendingAttendance).toEqual([]);
  });
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
    expect((await calculate({ days: 61, category: 'private', patientStates: absent })).balances[cycle].total).toBe(0);
  });
  it('65 attendant-only General days do not advance the patient Present threshold', async () => {
    const patientStates = Array.from({ length: 65 }, () => 'Absent');
    const result = await calculate({ days: 65, people: [{ id: 'helper', name: 'Helper' }], patientStates });
    expect(result.balances[cycle].total).toBe(13000);
  });
  it('Private absence before 60 actual Present days retains the initial room tier', async () => {
    const patientStates = [...Array.from({ length: 20 }, () => 'Absent'), ...Array.from({ length: 60 }, () => 'Present')];
    expect((await calculate({ days: 80, category: 'private', patientStates })).balances[cycle].total).toBe(42000);
    patientStates.push('Present');
    expect((await calculate({ days: 81, category: 'private', patientStates })).balances[cycle].total).toBe(42900);
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
    expect(result.balances[cycle].provisional).toBe(false);
    expect(f.source.records[1].payload).toEqual({ Same: { attendantName: 'Same', status: 'Present' } });
  });
  it('unmarked and explicit Pending records stay provisional and are listed for finalization', async () => {
    const f = fixture({ people: [{ id: 'a', name: 'A' }] });
    f.source.records = [];
    const result = await projectBilling(f.client, f.patient, { source: f.source });
    expect(result.attendance.has('2026-01-01')).toBe(false);
    expect(result.balances[cycle]).toMatchObject({ provisional: false, pendingAttendance: [
      { day: '2026-01-01', kind: 'attendance' }, { day: '2026-01-01', kind: 'attendant_attendance', attendantId: 'a' },
    ] });
    expect((await calculate({ patientStates: ['Pending'] })).balances[cycle].provisional).toBe(false);
    expect((await calculate({ patientStates: ['Pending'] })).balances[cycle].total).toBe(0);
  });
  it('an explicitly Pending historical attendant outside the current roster still blocks finalization', async () => {
    const f = fixture();
    f.source.records[1].payload = { departed: { attendantId: 'departed', attendantName: 'Historical helper', status: 'Pending' } } as any;
    const result = await projectBilling(f.client, f.patient, { source: f.source });
    expect(result.balances[cycle].total).toBe(200);
    expect(result.balances[cycle]).toMatchObject({ provisional: false, pendingAttendance: [
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

  describe('9:00 AM cutoff and advance payment / extension settlement consistency', () => {
    it('planned exit at or before 9:00 AM bills 8 days (₹1,600) for general bed', async () => {
      // Jan 1 admission, planned exit Jan 9 at 09:00 IST (03:30 UTC) -> 8 billable days (Jan 1..8)
      const patient = {
        id: 'p_8days',
        admission_date: at(1, 0, 0),
        registration_date: at(1, 0, 0),
        status: 'active',
        exit_date: at(9, 3, 30), // 09:00 IST
        attendants: [],
      };
      const stays = [{
        id: 's0',
        patient_id: patient.id,
        status: 'active',
        admission_date: at(1, 0, 0),
        created_at: at(1, 0, 0),
        updated_at: at(9, 3, 30),
        expected_discharge_date: at(9, 3, 30),
        cycle_id: cycle,
        room_type: 'general',
      }];
      const records = Array.from({ length: 11 }, (_, i) => ({
        kind: 'attendance',
        day: at(i + 1, 0, 0).toISOString().slice(0, 10),
        payload: { status: 'Present' },
      }));
      const source = {
        stays,
        records,
        receipts: [],
        roster: [],
        pricing: { generalRoomBedPrice: 200 },
      };
      const client = {} as unknown as pg.PoolClient;
      const result = await projectBilling(client, patient as any, { source: source as any });
      expect(result.balances[cycle].total).toBe(1600);
      expect(result.balances[cycle].segmentDays['s0']).toBe(8);
    });

    it('planned exit after 9:00 AM bills 9 days (₹1,800) for general bed', async () => {
      // Jan 1 admission, planned exit Jan 9 at 09:01 IST (03:31 UTC) -> 9 billable days (Jan 1..9)
      const patient = {
        id: 'p_9days',
        admission_date: at(1, 0, 0),
        registration_date: at(1, 0, 0),
        status: 'active',
        exit_date: at(9, 3, 31), // 09:01 IST
        attendants: [],
      };
      const stays = [{
        id: 's0',
        patient_id: patient.id,
        status: 'active',
        admission_date: at(1, 0, 0),
        created_at: at(1, 0, 0),
        updated_at: at(9, 3, 31),
        expected_discharge_date: at(9, 3, 31),
        cycle_id: cycle,
        room_type: 'general',
      }];
      const records = Array.from({ length: 11 }, (_, i) => ({
        kind: 'attendance',
        day: at(i + 1, 0, 0).toISOString().slice(0, 10),
        payload: { status: 'Present' },
      }));
      const source = {
        stays,
        records,
        receipts: [],
        roster: [],
        pricing: { generalRoomBedPrice: 200 },
      };
      const client = {} as unknown as pg.PoolClient;
      const result = await projectBilling(client, patient as any, { source: source as any });
      expect(result.balances[cycle].total).toBe(1800);
      expect(result.balances[cycle].segmentDays['s0']).toBe(9);
    });

    it('stay extended after ₹1,600 advance payment collects only remaining ₹400 difference', async () => {
      // Patient paid ₹1,600 advance for 8 days, then extended stay to Jan 11 at 09:00 AM (10 days -> ₹2,000)
      const patient = {
        id: 'p_extension',
        admission_date: at(1, 0, 0),
        registration_date: at(1, 0, 0),
        status: 'active',
        exit_date: at(11, 3, 30), // 09:00 IST -> Jan 1..10 (10 days)
        attendants: [],
      };
      const stays = [{
        id: 's0',
        patient_id: patient.id,
        status: 'active',
        admission_date: at(1, 0, 0),
        created_at: at(1, 0, 0),
        updated_at: at(11, 3, 30),
        expected_discharge_date: at(11, 3, 30),
        cycle_id: cycle,
        room_type: 'general',
      }];
      const records = Array.from({ length: 10 }, (_, i) => ({
        kind: 'attendance',
        day: at(i + 1).toISOString().slice(0, 10),
        payload: { status: 'Present' },
      }));
      const source = {
        stays,
        records,
        receipts: [{
          id: 'pay_1',
          patient_id: patient.id,
          amount: '1600.00',
          payment_date: at(1, 1, 0),
          cycle_id: cycle,
        }],
        roster: [],
        pricing: { generalRoomBedPrice: 200 },
      };
      const client = {} as unknown as pg.PoolClient;
      const result = await projectBilling(client, patient as any, { source: source as any });
      expect(result.balances[cycle].total).toBe(2000);
      expect(result.balances[cycle].paid).toBe(1600);
      expect(result.balances[cycle].due).toBe(400);
      expect(result.balances[cycle].refundDue).toBe(0);
    });

    it('calculates refund due when patient overpaid in advance', async () => {
      // Patient paid ₹1,800 advance, actual checkout at 09:00 AM on Jan 9 (8 days -> ₹1,600)
      const patient = {
        id: 'p_refund',
        admission_date: at(1, 0),
        registration_date: at(1, 0),
        status: 'discharged',
        exit_date: at(9, 3, 30),
        discharge_date: at(9, 3, 30),
        attendants: [],
      };
      const stays = [{
        id: 's0',
        patient_id: patient.id,
        status: 'completed',
        admission_date: at(1, 0),
        created_at: at(1, 0),
        updated_at: at(9, 3, 30),
        completed_at: at(9, 3, 30),
        cycle_id: cycle,
        room_type: 'general',
      }];
      const records = Array.from({ length: 8 }, (_, i) => ({
        kind: 'attendance',
        day: at(i + 1).toISOString().slice(0, 10),
        payload: { status: 'Present' },
      }));
      const source = {
        stays,
        records,
        receipts: [{
          id: 'pay_1',
          patient_id: patient.id,
          amount: '1800.00',
          payment_date: at(1, 1, 0),
          cycle_id: cycle,
        }],
        roster: [],
        pricing: { generalRoomBedPrice: 200 },
      };
      const client = {} as unknown as pg.PoolClient;
      const result = await projectBilling(client, patient as any, { source: source as any, finalize: true, checkoutAt: at(9, 3, 30) });
      expect(result.balances[cycle].total).toBe(1600);
      expect(result.balances[cycle].paid).toBe(1800);
      expect(result.balances[cycle].due).toBe(0);
      expect(result.balances[cycle].refundDue).toBe(200);
    });
  });

  describe('Rule 7 Acceptance Tests', () => {
    it('Case 1: Patient admitted 21 Oct, patient+attendant present 21-22 Oct in general room, no marks after 22 Oct, no planned exit: on 29 Oct total is exactly ₹800 final', async () => {
      const admission = new Date('2026-10-21T06:00:00+05:30');
      const cycleId = String(admission.getTime());
      const helper = { id: 'att_1', name: 'Helper' };
      const patient = {
        id: 'p_case1',
        admission_date: admission,
        registration_date: admission,
        status: 'active',
        exit_date: null,
        attendants: [helper],
      };
      const stays = [{
        id: 's_case1',
        patient_id: patient.id,
        status: 'active',
        admission_date: admission,
        created_at: admission,
        updated_at: admission,
        cycle_id: cycleId,
        room_type: 'general',
        patient_snapshot: { attendants: [helper] },
      }];
      // Only 21 and 22 Oct have attendance marked Present for both
      const records = [
        { kind: 'attendance', day: '2026-10-21', payload: { status: 'Present' } },
        { kind: 'attendant_attendance', day: '2026-10-21', payload: { [helper.id]: { attendantId: helper.id, attendantName: helper.name, status: 'Present' } } },
        { kind: 'attendance', day: '2026-10-22', payload: { status: 'Present' } },
        { kind: 'attendant_attendance', day: '2026-10-22', payload: { [helper.id]: { attendantId: helper.id, attendantName: helper.name, status: 'Present' } } },
      ];
      const source = {
        stays,
        records,
        receipts: [],
        roster: [helper],
        pricing: { generalRoomBedPrice: 200 },
      };
      const client = {} as unknown as pg.PoolClient;
      // Viewed on 29 Oct
      const asOf = Date.parse('2026-10-29T15:00:00+05:30');
      const result = await projectBillingEngine(client, patient as any, { source: source as any, asOf });
      const balance = result.balances[cycleId];

      expect(balance.total).toBe(800); // 2 days * (200 + 200) = 800
      expect(balance.provisional).toBe(false);
      expect(balance.pricingBasis).toBe('actual_patient_present');
      expect(result.patient.advance_billed_amount).toBe('800.00');
      expect(result.patient.financial_reconciliation.provisional).toBe(false);
      expect(result.stays[0].billing_summary.provisional).toBe(false);
    });

    it('Case 2: Same patient: discharge with admin-chosen exit 23 Oct succeeds despite pending marks; final total ₹800', async () => {
      const admission = new Date('2026-10-21T06:00:00+05:30');
      const cycleId = String(admission.getTime());
      const helper = { id: 'att_1', name: 'Helper' };
      const patient = {
        id: 'p_case2',
        admission_date: admission,
        registration_date: admission,
        status: 'active',
        exit_date: null,
        attendants: [helper],
      };
      const stays = [{
        id: 's_case2',
        patient_id: patient.id,
        status: 'active',
        room_id: 'r1',
        bed_id: 'b1',
        admission_date: admission,
        created_at: admission,
        updated_at: admission,
        cycle_id: cycleId,
        room_type: 'general',
        patient_snapshot: { attendants: [helper] },
      }];
      // Marked only on 21 and 22 Oct. Days 23..29 are unmarked (pending)
      const records = [
        { kind: 'attendance', day: '2026-10-21', payload: { status: 'Present' } },
        { kind: 'attendant_attendance', day: '2026-10-21', payload: { [helper.id]: { attendantId: helper.id, attendantName: helper.name, status: 'Present' } } },
        { kind: 'attendance', day: '2026-10-22', payload: { status: 'Present' } },
        { kind: 'attendant_attendance', day: '2026-10-22', payload: { [helper.id]: { attendantId: helper.id, attendantName: helper.name, status: 'Present' } } },
      ];
      const source = {
        stays,
        records,
        receipts: [],
        roster: [helper],
        pricing: { generalRoomBedPrice: 200 },
      };

      // Admin chooses checkout at 09:00 AM on 23 Oct (excludes 23 Oct checkout day per 09:00 cutoff)
      const checkoutAt = new Date('2026-10-23T09:00:00+05:30');
      const result = await projectBillingEngine({} as any, { ...patient, status: 'discharged', discharge_date: checkoutAt }, { source: source as any, finalize: true, checkoutAt });
      const balance = result.balances[cycleId];

      expect(balance.total).toBe(800);
      expect(balance.provisional).toBe(false);
      expect(balance.due).toBe(800);
      expect(balance.refundDue).toBe(0);
    });

    it('Case 3: Patient with planned exit 25 Oct, still ACTIVE on 29 Oct, attendance marked 21-28 Oct: only marked attendance up to 25 Oct billed (₹2,000); 26-28 Oct are ₹0; stay remains Active', async () => {
      const admission = new Date('2026-10-21T06:00:00+05:30');
      const cycleId = String(admission.getTime());
      const helper = { id: 'att_1', name: 'Helper' };
      const plannedExit = new Date('2026-10-25T23:59:59+05:30'); // Date-only planned exit: end of day
      const patient = {
        id: 'p_case3',
        admission_date: admission,
        registration_date: admission,
        status: 'active',
        exit_date: plannedExit,
        attendants: [helper],
      };
      const stays = [{
        id: 's_case3',
        patient_id: patient.id,
        status: 'active',
        admission_date: admission,
        created_at: admission,
        updated_at: admission,
        cycle_id: cycleId,
        room_type: 'general',
        patient_snapshot: { attendants: [helper] },
      }];
      // Attendance marked Present for patient AND attendant on all 8 days: 21 to 28 Oct
      const records: any[] = [];
      for (let day = 21; day <= 28; day++) {
        records.push({ kind: 'attendance', day: `2026-10-${day}`, payload: { status: 'Present' } });
        records.push({ kind: 'attendant_attendance', day: `2026-10-${day}`, payload: { [helper.id]: { attendantId: helper.id, attendantName: helper.name, status: 'Present' } } });
      }
      const source = {
        stays,
        records,
        receipts: [],
        roster: [helper],
        pricing: { generalRoomBedPrice: 200 },
      };
      // Viewed on 29 Oct
      const asOf = Date.parse('2026-10-29T15:00:00+05:30');
      const result = await projectBillingEngine({} as any, patient as any, { source: source as any, asOf });
      const balance = result.balances[cycleId];

      // Only 21, 22, 23, 24, 25 Oct are billed: 5 days * ₹400 = ₹2,000. 26-28 Oct charges are ₹0.
      expect(balance.total).toBe(2000);
      expect(result.patient.status).toBe('active');
      expect(result.stays[0].status).toBe('active');
    });

    it('Case 4: Same patient: planned exit extended 25 Oct -> 30 Oct -> attendance on 26-30 Oct charges normally again (total ₹4,000)', async () => {
      const admission = new Date('2026-10-21T06:00:00+05:30');
      const cycleId = String(admission.getTime());
      const helper = { id: 'att_1', name: 'Helper' };
      // Extended planned exit to 30 Oct end of day
      const extendedExit = new Date('2026-10-30T23:59:59+05:30');
      const patient = {
        id: 'p_case4',
        admission_date: admission,
        registration_date: admission,
        status: 'active',
        exit_date: extendedExit,
        attendants: [helper],
      };
      const stays = [{
        id: 's_case4',
        patient_id: patient.id,
        status: 'active',
        admission_date: admission,
        created_at: admission,
        updated_at: admission,
        cycle_id: cycleId,
        room_type: 'general',
        patient_snapshot: { attendants: [helper] },
      }];
      // Attendance marked Present for patient AND attendant on all 10 days: 21 to 30 Oct
      const records: any[] = [];
      for (let day = 21; day <= 30; day++) {
        records.push({ kind: 'attendance', day: `2026-10-${day}`, payload: { status: 'Present' } });
        records.push({ kind: 'attendant_attendance', day: `2026-10-${day}`, payload: { [helper.id]: { attendantId: helper.id, attendantName: helper.name, status: 'Present' } } });
      }
      const source = {
        stays,
        records,
        receipts: [],
        roster: [helper],
        pricing: { generalRoomBedPrice: 200 },
      };
      const asOf = Date.parse('2026-10-31T10:00:00+05:30');
      const result = await projectBillingEngine({} as any, patient as any, { source: source as any, asOf });
      const balance = result.balances[cycleId];

      // 10 days * ₹400 = ₹4,000
      expect(balance.total).toBe(4000);
      expect(result.patient.status).toBe('active');
    });

    it('Case 5: Patient who paid more than the truncated final total: pending = 0, excess shows as unallocated/credit', async () => {
      const admission = new Date('2026-10-21T06:00:00+05:30');
      const cycleId = String(admission.getTime());
      const patient = {
        id: 'p_case5',
        admission_date: admission,
        registration_date: admission,
        status: 'active',
        exit_date: new Date('2026-10-25T23:59:59+05:30'),
        attendants: [],
      };
      const stays = [{
        id: 's_case5',
        patient_id: patient.id,
        status: 'active',
        admission_date: admission,
        created_at: admission,
        updated_at: admission,
        cycle_id: cycleId,
        room_type: 'general',
      }];
      // 4 days present (21..24 Oct) @ 200 = 800
      const records = [21, 22, 23, 24].map(day => ({
        kind: 'attendance',
        day: `2026-10-${day}`,
        payload: { status: 'Present' },
      }));
      // Advance payment was 2,000
      const receipts = [{
        id: 'rec_1',
        patient_id: patient.id,
        cycle_id: cycleId,
        amount: '2000.00',
        payment_date: admission,
      }];
      const source = {
        stays,
        records,
        receipts,
        roster: [],
        pricing: { generalRoomBedPrice: 200 },
      };
      const result = await projectBillingEngine({} as any, patient as any, { source: source as any });
      const balance = result.balances[cycleId];

      expect(balance.total).toBe(800);
      expect(balance.paid).toBe(2000);
      expect(balance.due).toBe(0); // pending never goes negative
      expect(balance.refundDue).toBe(1200); // excess exposed as credit
      expect(balance.status).toBe('Payment Exceeded');
      expect(result.patient.payment_pending).toBe(false);
      expect(result.patient.refund_due_amount).toBe('1200.00');
    });
  });
});
