import type pg from 'pg';
import { httpError } from '../validation.js';
// Calendar-day billing includes admission and checkout regardless of clock
// time, in the organisation's local calendar (independent of container UTC).
const calendar = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' });
export const dayKey = (v: any) => calendar.format(new Date(v));
const nextDay = (v: string, n = 1) => new Date(Date.parse(v + 'T00:00:00Z') + n * 86400000).toISOString().slice(0, 10);
const checkoutEnd = (v: any) => nextDay(dayKey(v));
export function money(value: unknown): number {
    const text = String(value ?? 0);
    const match = /^(-?)(\d+)(?:\.(\d{1,2}))?$/.exec(text);
    if (!match)
        throw httpError(409, 'Invalid stored decimal amount');
    const cents = (match[1] === '-' ? -1 : 1) * (Number(match[2]) * 100 + Number((match[3] ?? '').padEnd(2, '0')));
    if (!Number.isSafeInteger(cents))
        throw httpError(409, 'Financial amount exceeds supported precision');
    return cents;
}
export const decimal = (v: number) => (v / 100).toFixed(2);
const status = (net: number, due: number, excess: number) => excess > 0 ? 'Payment Exceeded' : due === 0 ? 'Paid' : net > 0 ? 'Partially Paid' : 'Unpaid';
export function baseDailyChargeCents(roomType: string, attendantsCount: number, pricing: Record<string, any>, patientBillable = true): number {
    const rate = (key: string, fallback: number) => {
        // ₹150 was the legacy built-in General/Lobby fallback. Keep the
        // extension endpoint aligned with projectBilling and the Flutter
        // pricing migration when it encounters an un-migrated setting.
        const value = key === 'generalRoomBedPrice' && Number(pricing[key]) === 150
            ? 200
            : pricing[key] ?? fallback;
        return money(value);
    };
    const isPrivate = roomType === 'private';
    const included = Number(pricing.privateRoomIncludedAttendants ?? 1);
    return isPrivate
        ? rate('privateRoomBasePrice', 700) + Math.max(0, attendantsCount - included) * rate('privateRoomExtraAttendantFee', 200)
        : ((patientBillable ? 1 : 0) + attendantsCount) * rate('generalRoomBedPrice', 200);
}
export function dailyChargeCents(roomType: string, attendantsCount: number, pricing: Record<string, any>, patientBillable = true, baseRateCents?: number): number {
    const base = baseRateCents ?? baseDailyChargeCents(roomType, attendantsCount, pricing, patientBillable);
    const isPrivate = roomType === 'private';
    const included = Number(pricing.privateRoomIncludedAttendants ?? 1);
    if (isPrivate)
        return base + 20000 + Math.min(100, Math.max(0, attendantsCount - included)) * 10000;
    return base + ((patientBillable ? 1 : 0) + attendantsCount) * 5000;
}
export function extensionCostCents(roomType: string, attendantsCount: number, additionalDays: number, pricing: Record<string, any>, priorBillableDays = 0, longStayRateCents?: number): number {
    let total = 0;
    const base = baseDailyChargeCents(roomType, attendantsCount, pricing, true);
    for (let offset = 1; offset <= additionalDays; offset++) {
        total += priorBillableDays + offset <= 60
            ? base
            : longStayRateCents ?? dailyChargeCents(roomType, attendantsCount, pricing, true, base);
    }
    return total;
}
export function stayCycle(stay: any, patient: any): string {
    if (stay.cycle_id != null)
        return String(stay.cycle_id);
    if (stay.patient_snapshot?.admissionDate != null)
        return String(stay.patient_snapshot.admissionDate);
    const admission = new Date(patient.admission_date).getTime();
    return String(new Date(stay.created_at).getTime() >= admission - 60000 || new Date(stay.admission_date).getTime() === new Date(patient.registration_date ?? patient.admission_date).getTime() ? admission : new Date(stay.admission_date).getTime());
}
export function receiptCycle(row: any, patient: any, stays: any[]): string {
    if (row.cycle_id)
        return row.cycle_id;
    const boundaries = [...new Set([String(new Date(patient.admission_date).getTime()), ...stays.map(s => stayCycle(s, patient))])].map(Number).filter(Number.isFinite).sort((a, b) => a - b);
    return String(boundaries.filter(n => dayKey(n) <= dayKey(row.payment_date)).at(-1) ?? `before-${boundaries[0]}`);
}
/** Caller holds this patient's row lock. Read-only until persistBilling is called.
 * Charges retain stay overrides, per-admission transfer/multi-bed day ownership,
 * recorded attendants and the existing 60-day rates. Receipts are never inferred
 * from patient summaries. All calculations use integer paise from NUMERIC text.
 */
type BillingSource = { stays: any[]; records: any[]; receipts: any[]; pricing: Record<string, any> };
export async function projectBilling(client: pg.PoolClient, patient: any, options: {
    finalize?: boolean;
    // Read-only hypothetical stay dates for an approval quote.
    stayEndDates?: Record<string, Date>;
    source?: BillingSource;
    asOf?: number;
} = {}) {
    const sourceStays = options.source?.stays ?? (await client.query("SELECT * FROM stays WHERE patient_id=$1 ORDER BY admission_date,id", [patient.id])).rows;
    const stays = sourceStays.map(s =>
        options.stayEndDates?.[s.id] ? { ...s, expected_discharge_date: options.stayEndDates[s.id] } : s);
    const records = options.source?.records ?? (await client.query("SELECT kind,attendance_date::text AS day,payload FROM attendance_records WHERE patient_id=$1", [patient.id])).rows;
    const receipts = options.source?.receipts ?? (await client.query('SELECT * FROM payments WHERE patient_id=$1 ORDER BY payment_date,id', [patient.id])).rows;
    const pricing = { ...(options.source?.pricing ?? Object.fromEntries((await client.query("SELECT settings_key,settings_value FROM system_settings WHERE category='pricing'")).rows.map(r => [r.settings_key, r.settings_value]))) };
    const rate = (key: string, fallback: number) => money(pricing[key] ?? fallback);
    // Same legacy default-price migration as PaymentService (a configured 150 was
    // the old default, not a manual stay rate).
    if (Number(pricing.generalRoomBedPrice) === 150)
        pricing.generalRoomBedPrice = 200;
    const attendance = new Map<string, string>();
    const attendants = new Map<string, Map<string, string>>();
    for (const r of records) {
        if (r.kind === 'attendance')
            attendance.set(r.day, r.payload.status);
        else if (r.kind === 'attendant_attendance') {
            const marks = attendants.get(r.day) ?? new Map<string, string>();
            // Payloads use one attendant record per row, keyed by name in Flutter.
            if (r.payload.attendantName)
                marks.set(r.payload.attendantName, r.payload.status);
            attendants.set(r.day, marks);
        }
    }
    const currentCycle = String(new Date(patient.admission_date).getTime());
    const groups = new Map<string, any[]>();
    for (const s of stays.filter(s => s.status !== 'cancelled')) {
        const id = stayCycle(s, patient);
        groups.set(id, [...(groups.get(id) ?? []), s]);
    }
    if (!groups.has(currentCycle))
        groups.set(currentCycle, []);
    // Legacy admissions may have a saved explicit invoice but no stay segments.
    // Preserve those charges; only the ledger supplies their payments/refunds.
    for (const id of Object.keys(patient.admission_balances ?? {}))
        if (!groups.has(id))
            groups.set(id, []);
    const balances: Record<string, any> = {};
    for (const [cycleId, segments] of groups) {
        const active = cycleId === currentCycle && patient.status.toLowerCase() !== 'discharged';
        const saved = patient.admission_balances?.[cycleId];
        const frozen = saved?.total != null && (cycleId !== currentCycle || (patient.status === 'discharged' && !options.finalize));
        const charges: Record<string, number> = Object.fromEntries(segments.map(s => [s.id, 0]));
        const days: Record<string, number> = Object.fromEntries(segments.map(s => [s.id, 0]));
        if (segments.length && !frozen) {
            const start = dayKey(segments[0].admission_date);
            let end: any;
            if (active) {
                end = patient.exit_date;
                if (!end) {
                    // An open admission retains its seven-day advance, extending for
                    // elapsed days, stay extensions and genuinely recorded attendance.
                    const candidates = [nextDay(start, 6) + 'T03:30:00Z', dayKey(options.asOf ?? Date.now()) + 'T03:30:00Z', ...segments.filter(s => s.status === 'active').map(s => nextDay(dayKey(s.expected_discharge_date), -1) + 'T03:30:00Z'), ...[...attendance.keys(), ...attendants.keys()].map(d => d + 'T03:30:00Z')];
                    end = new Date(Math.max(...candidates.map(d => new Date(d).getTime())));
                }
            }
            else
                end = new Date(Math.max(...segments.map(s => new Date(s.completed_at ?? s.updated_at).getTime())));
            let exclusive = checkoutEnd(end);
            if (exclusive <= start)
                exclusive = nextDay(start);
            let billableDays = 0;
            for (let d = start; d < exclusive; d = nextDay(d)) {
                const patientBillable = attendance.get(d) !== 'Absent';
                const attendantCount = [...(attendants.get(d)?.values() ?? [])].filter(s => s === 'Present').length;
                if (!patientBillable && !attendantCount)
                    continue;
                const candidates = segments.filter(s => {
                    if (dayKey(s.admission_date) > d)
                        return false;
                    if (active && s.status === 'active')
                        return true;
                    const checkout = s.completed_at ?? s.updated_at;
                    return d < checkoutEnd(checkout) || (d === dayKey(s.admission_date) && new Date(checkout) > new Date(s.admission_date));
                });
                if (!candidates.length)
                    continue;
                billableDays++;
                const cost = (s: any) => {
                    const base = s.daily_rate_is_manual && s.daily_rate != null ? money(s.daily_rate) : baseDailyChargeCents(s.room_type, attendantCount, pricing, patientBillable);
                    return billableDays <= 60 ? base : s.long_stay_daily_rate != null ? money(s.long_stay_daily_rate) : dailyChargeCents(s.room_type, attendantCount, pricing, patientBillable, base);
                };
                candidates.sort((a, b) => cost(b) - cost(a) || new Date(b.admission_date).getTime() - new Date(a.admission_date).getTime());
                const chosen = candidates[0];
                charges[chosen.id] += cost(chosen);
                days[chosen.id]++;
            }
            for (const s of segments)
                if (s.cost_override != null)
                    charges[s.id] = money(s.cost_override);
        }
        if (frozen)
            for (const s of segments) {
                charges[s.id] = money(saved.segmentCharges?.[s.id] ?? s.total_cost);
                days[s.id] = Number(saved.segmentDays?.[s.id] ?? s.billing_summary?.days ?? 0);
            }
        let billed = Object.values(charges).reduce((a, b) => a + b, 0);
        if (frozen)
            billed = money(saved.total);
        else if (!segments.length && cycleId !== currentCycle)
            billed = money(patient.admission_balances?.[cycleId]?.total ?? 0);
        else if (!segments.length)
            billed = patient.billing_amount_override != null ? money(patient.billing_amount_override) : money(patient.advance_billed_amount) + money(patient.attendance_charges);
        // Parse exact NUMERIC values returned by pg; do not sum IEEE decimal money.
        let paid = 0, refunded = 0;
        for (const r of receipts.filter(r => receiptCycle(r, patient, stays) === cycleId)) {
            const amount = money(r.amount);
            if (amount < 0)
                refunded -= amount;
            else
                paid += amount;
        }
        const net = paid - refunded, due = Math.max(0, billed - net), excess = Math.max(0, net - billed);
        balances[cycleId] = { cycleId, total: billed / 100, paid: paid / 100, refunded: refunded / 100, netPaid: net / 100, due: due / 100, refundDue: excess / 100, status: status(net, due, excess), segmentCharges: segments.length ? Object.fromEntries(Object.entries(charges).map(([k, v]) => [k, v / 100])) : (patient.admission_balances?.[cycleId]?.segmentCharges ?? {}), segmentDays: segments.length ? days : (patient.admission_balances?.[cycleId]?.segmentDays ?? {}) };
    }
    const current = balances[currentCycle];
    const rangeStart = dayKey(patient.registration_date ?? patient.admission_date), rangeEnd = dayKey(patient.status === 'discharged' ? patient.discharge_date ?? patient.exit_date ?? Date.now() : patient.exit_date ?? Date.now());
    const marks = [...attendance].filter(([d]) => d >= rangeStart && d <= rangeEnd).map(([, s]) => s);
    const fields = { advance_billed_amount: decimal(money(current.total)), attendance_charges: '0.00', billing_amount_override: stays.length ? null : patient.billing_amount_override, total_paid_amount: decimal(money(current.netPaid)), current_due_amount: decimal(money(current.due)), refund_due_amount: decimal(money(current.refundDue)), total_refund_due_amount: decimal(Object.values(balances).reduce((sum, b) => sum + money(b.refundDue), 0)), total_refunded_amount: decimal(Object.values(balances).reduce((sum, b) => sum + money(b.refunded), 0)), payment_pending: current.due > 0, payment_status: current.status, admission_balances: balances, total_present_days: marks.filter(s => s === 'Present').length, total_absent_days: marks.filter(s => s === 'Absent').length };
    const computedStays = stays.map(s => { const b = balances[stayCycle(s, patient)]; return b && s.status !== 'cancelled' ? { ...s, total_cost: decimal(money(b.segmentCharges[s.id] ?? 0)), billing_summary: { ...s.billing_summary, days: b.segmentDays[s.id] ?? 0, amount: b.segmentCharges[s.id] ?? 0, admissionId: b.cycleId }, cycle_id: b.cycleId, daily_rate: s.daily_rate_is_manual ? s.daily_rate : null } : s; });
    return { patient: { ...patient, ...fields }, fields, stays: computedStays, receipts, balances, attendance, repriceClosed: options.finalize === true,
        source: { stays: sourceStays, records, receipts, pricing } };
}

/** Marginal charge for the added period, using the final invoice engine. */
export async function quoteStayExtension(client: pg.PoolClient, patient: any, stay: any, additionalDays: number) {
    if (!Number.isInteger(additionalDays) || additionalDays < 1 || additionalDays > 3650)
        throw httpError(400, 'Invalid stay extension');
    const cycle = String(new Date(patient.admission_date).getTime());
    if (stay.status !== 'active' || patient.status === 'discharged' || stayCycle(stay, patient) !== cycle)
        throw httpError(409, 'Only the current active admission can be extended');
    const from = patient.exit_date ? checkoutEnd(patient.exit_date) : dayKey(stay.expected_discharge_date);
    const through = nextDay(from, additionalDays);
    const asOf = Date.now();
    const beforeProjection = await projectBilling(client, patient, { asOf });
    const before = beforeProjection.balances[cycle];
    const afterPatient = { ...patient, exit_date: patient.exit_date ? new Date(new Date(patient.exit_date).getTime() + additionalDays * 86400000) : null };
    const after = (await projectBilling(client, afterPatient, { asOf, source: beforeProjection.source, stayEndDates: {
        [stay.id]: new Date(new Date(stay.expected_discharge_date).getTime() + additionalDays * 86400000),
    } })).balances[cycle];
    const cost = money(after.total) - money(before.total);
    if (cost < 0) throw httpError(409, 'Extension quote would reduce existing charges');
    return { additionalDays, additionalCost: cost / 100, from, throughExclusive: through,
        priorBillableDays: Object.values(before.segmentDays as Record<string, number>).reduce((a, b) => a + b, 0),
        pricingBasis: 'projected_billable_attendance' };
}

export async function persistBilling(client: pg.PoolClient, projection: Awaited<ReturnType<typeof projectBilling>>) {
    const keys = Object.keys(projection.fields);
    const values = Object.values(projection.fields).map(v => typeof v === 'object' && v !== null ? JSON.stringify(v) : v);
    const updated = (await client.query(`UPDATE patients SET ${keys.map((k, i) => `${k}=$${i + 2}`).join(',')},version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=$1 RETURNING *`, [projection.patient.id, ...values])).rows[0];
    for (const s of projection.stays.filter(s => s.status !== 'cancelled' && (s.status === 'active' || projection.repriceClosed) && stayCycle(s, projection.patient) === String(new Date(projection.patient.admission_date).getTime())))
        await client.query('UPDATE stays SET total_cost=$2,billing_summary=$3::jsonb,cycle_id=$4,daily_rate=$5,updated_at=CURRENT_TIMESTAMP WHERE id=$1', [s.id, s.total_cost, JSON.stringify(s.billing_summary), s.cycle_id, s.daily_rate]);
    projection.patient = updated;
    return projection;
}
