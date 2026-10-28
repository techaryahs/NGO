import type pg from 'pg';
import { httpError } from '../validation.js';
import { eligibleAttendant } from './attendant_roster.js';
// Checkout date is included only after 09:00 in the organisation's timezone.
// The same date boundary applies to every accommodation category.
const calendar = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' });
export const dayKey = (v: any) => calendar.format(new Date(v));
export const nextDay = (v: string, n = 1) => new Date(Date.parse(v + 'T00:00:00Z') + n * 86400000).toISOString().slice(0, 10);
const localClock = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kolkata', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
export const afterCheckoutCutoff = (value: any) => localClock.format(new Date(value)) > '09:00';
export const checkoutEnd = (value: any) => afterCheckoutCutoff(value) ? nextDay(dayKey(value)) : dayKey(value);
export const usesLongStayTier = (priorPatientPresentDays: number) => priorPatientPresentDays >= 60;
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
// Client-approved tariff for new estimates. A saved per-stay pricing snapshot
// or explicit manual override remains separate from mutable legacy settings.
export const approvedPricing = (settings: Record<string, any>) => ({ ...settings,
    generalRoomBedPrice: 200, privateRoomBasePrice: 700,
    privateRoomIncludedAttendants: 1, privateRoomExtraAttendantFee: 200 });
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
    const included = 1;
    return isPrivate
        ? rate('privateRoomBasePrice', 700) + Math.max(0, attendantsCount - included) * rate('privateRoomExtraAttendantFee', 200)
        : ((patientBillable ? 1 : 0) + attendantsCount) * rate('generalRoomBedPrice', 200);
}
export function dailyChargeCents(roomType: string, attendantsCount: number, pricing: Record<string, any>, patientBillable = true, baseRateCents?: number): number {
    const base = baseRateCents ?? baseDailyChargeCents(roomType, attendantsCount, pricing, patientBillable);
    const isPrivate = roomType === 'private';
    const included = 1;
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
    // A saved segment owner is evidence; placement/creation dates are not an
    // admission identity (transfers and imported stays can share those dates).
    const owners = Object.entries<any>(patient.admission_balances ?? {})
        .filter(([, balance]) => Object.hasOwn(balance.segmentCharges ?? {}, stay.id))
        .map(([id]) => id);
    return owners.length === 1 ? owners[0] : `unresolved-stay:${stay.id}`;
}
export function cycleIdentityIssues(patient: any, stays: any[]) {
    return stays.filter(s => s.status !== 'cancelled').flatMap(s => {
        const cycle = stayCycle(s, patient);
        const snapshot = s.patient_snapshot?.admissionDate;
        const summary = s.billing_summary?.admissionId;
        const savedOwners = Object.entries<any>(patient.admission_balances ?? {})
            .filter(([, balance]) => Object.hasOwn(balance.segmentCharges ?? {}, s.id)).map(([id]) => id);
        return cycle.startsWith('unresolved-stay:') ||
            snapshot != null && String(snapshot) !== cycle ||
            summary != null && String(summary) !== cycle ||
            savedOwners.length > 0 && (savedOwners.length !== 1 || savedOwners[0] !== cycle)
            ? [{ stayId: s.id, cycleId: s.cycle_id ?? null, snapshotCycleId: snapshot == null ? null : String(snapshot),
                summaryCycleId: summary == null ? null : String(summary), savedCycleIds: savedOwners,
                reason: cycle.startsWith('unresolved-stay:') ? 'missing_stay_cycle' : 'conflicting_stay_cycles' }]
            : [];
    });
}
/** New online placements belong to the locked admission, never the bed/date. */
export function newStayIdentity(patient: any, body: any) {
    const current = String(new Date(patient.admission_date).getTime());
    const active = !body.status || body.status === 'active';
    const cycle = active ? current : body.cycleId ?? body.patientSnapshot?.admissionDate;
    if (cycle == null || (body.cycleId != null && String(body.cycleId) !== String(cycle)) ||
        (body.patientSnapshot?.admissionDate != null && String(body.patientSnapshot.admissionDate) !== String(cycle)) ||
        (body.billingSummary?.admissionId != null && String(body.billingSummary.admissionId) !== String(cycle)))
        throw httpError(409, 'Stay cycle conflicts with the admission identity; reconcile the original admission evidence');
    return { cycleId: String(cycle), snapshotAdmission: /^\d+$/.test(String(cycle)) && Number.isSafeInteger(Number(cycle)) ? Number(cycle) : String(cycle) };
}
export function receiptCycle(row: any, patient: any, stays: any[], context: 'recorded' | 'new' = 'recorded'): string | null {
    if (row.cycle_id)
        return String(row.cycle_id);
    // One *remaining* cycle cannot prove a historical receipt's ownership:
    // previous admissions may have been deleted or incompletely imported.
    // Only a new online request can establish and persist a single-cycle choice.
    if (context !== 'new' || cycleIdentityIssues(patient, stays).length) return null;
    const cycles = new Set([String(new Date(patient.admission_date).getTime()), ...stays.filter(s => s.status !== 'cancelled').map(s => stayCycle(s, patient)), ...Object.keys(patient.admission_balances ?? {})]);
    return cycles.size === 1 ? [...cycles][0] : null;
}
/** Caller holds this patient's row lock. Read-only until persistBilling is called.
 * Charges retain stay overrides, per-admission transfer/multi-bed day ownership,
 * recorded attendants and the existing 60-day rates. Receipts are never inferred
 * from patient summaries. All calculations use integer paise from NUMERIC text.
 */
type BillingSource = { stays: any[]; records: any[]; receipts: any[]; pricing: Record<string, any>; roster?: any[] };
export async function projectBilling(client: pg.PoolClient, patient: any, options: {
    finalize?: boolean;
    // Read-only hypothetical stay dates for an approval quote.
    stayEndDates?: Record<string, Date>;
    source?: BillingSource;
    asOf?: number;
    checkoutAt?: Date;
    ignoreCheckout?: boolean;
    // Explicit refund mutations retain the legacy settlement quote context.
    // Ordinary active booking reads must never adopt an uncommitted preview.
    useSavedCheckout?: boolean;
} = {}) {
    const currentCycle = String(new Date(patient.admission_date).getTime());
    const savedCheckout = patient.admission_balances?.[currentCycle]?.checkoutAt;
    if (!options.checkoutAt && options.useSavedCheckout && !options.ignoreCheckout && patient.status !== 'discharged' && savedCheckout != null) options = { ...options, checkoutAt: new Date(savedCheckout) };
    const sourceStays = options.source?.stays ?? (await client.query("SELECT * FROM stays WHERE patient_id=$1 ORDER BY admission_date,id", [patient.id])).rows;
    const stays = sourceStays.map(s =>
        options.stayEndDates?.[s.id] ? { ...s, expected_discharge_date: options.stayEndDates[s.id] } : s);
    const records = options.source?.records ?? (await client.query("SELECT kind,attendance_date::text AS day,payload FROM attendance_records WHERE patient_id=$1", [patient.id])).rows;
    const receipts = options.source?.receipts ?? (await client.query('SELECT * FROM payments WHERE patient_id=$1 ORDER BY payment_date,id', [patient.id])).rows;
    const pricing = approvedPricing(options.source?.pricing ?? Object.fromEntries((await client.query("SELECT settings_key,settings_value FROM system_settings WHERE category='pricing'")).rows.map(r => [r.settings_key, r.settings_value])));
    const roster = options.source?.roster ?? patient.attendants ?? (await client.query('SELECT id,name FROM patient_attendants WHERE patient_id=$1 ORDER BY id', [patient.id])).rows;
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
            // API stores one day/patient row containing an ID-keyed map. Older
            // imports also contain individual name-keyed records. Keep both.
            if (r.payload.attendantName || r.payload.attendantId)
                marks.set(String(r.payload.attendantId ?? r.payload.attendantName), r.payload.status);
            else for (const [key, value] of Object.entries(r.payload ?? {})) {
                if (value && typeof value === 'object') {
                    const mark = value as any;
                    marks.set(String(mark.attendantId ?? key), mark.status);
                }
            }
            attendants.set(r.day, marks);
        }
    }
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
    const allocatedCycle = (r: any) => receiptCycle(r, patient, stays);
    const identityIssues = cycleIdentityIssues(patient, stays);
    const chargeIssues = !stays.some(s => s.status !== 'cancelled') &&
        !Object.values<any>(patient.admission_balances ?? {}).some(b => b.total != null) && patient.billing_amount_override == null
        ? [{ cycleId: currentCycle, reason: 'missing_invoice_evidence' }] : [];
    const unallocated = receipts.filter(r => { const cycle = allocatedCycle(r); return cycle == null || !groups.has(cycle); });
    const reconciliation = {
        required: unallocated.length > 0 || identityIssues.length > 0 || chargeIssues.length > 0,
        cycleIdentityIssues: identityIssues,
        chargeIssues,
        unallocatedReceipts: unallocated.map(r => ({ id: r.id, cycleId: r.cycle_id ?? null, amount: money(r.amount) / 100,
            reason: r.cycle_id == null ? 'unestablished_cycle' : 'unknown_cycle' })),
        unallocatedNet: unallocated.reduce((sum, r) => sum + money(r.amount), 0) / 100,
        accountPaid: receipts.reduce((sum, r) => sum + Math.max(0, money(r.amount)), 0) / 100,
        accountRefunded: receipts.reduce((sum, r) => sum + Math.max(0, -money(r.amount)), 0) / 100,
    };
    const balances: Record<string, any> = {};
    for (const [cycleId, segments] of groups) {
        const active = cycleId === currentCycle && patient.status.toLowerCase() !== 'discharged';
        const stored = patient.admission_balances?.[cycleId];
        // Legacy finalized stays can predate admission_balances. Their stored
        // invoice totals are history, not a request to price them again today.
        const legacyFinal = segments.length && segments.every(s => s.status === 'completed') && (cycleId !== currentCycle || patient.status === 'discharged' && !options.checkoutAt);
        const saved = stored ?? (legacyFinal ? { total: segments.reduce((sum, s) => sum + money(s.total_cost), 0) / 100,
            segmentCharges: Object.fromEntries(segments.map(s => [s.id, money(s.total_cost) / 100])),
            segmentDays: Object.fromEntries(segments.map(s => [s.id, Number(s.billing_summary?.days ?? 0)])), finalized: true } : undefined);
        const frozen = saved?.total != null && (cycleId !== currentCycle || saved.finalized === true || patient.status === 'discharged' && (!options.finalize || !options.checkoutAt));
        const charges: Record<string, number> = Object.fromEntries(segments.map(s => [s.id, 0]));
        const patientCharges: Record<string, number> = Object.fromEntries(segments.map(s => [s.id, 0]));
        const attendantCharges: Record<string, number> = Object.fromEntries(segments.map(s => [s.id, 0]));
        const unsplit = new Set(segments.filter(s => s.daily_rate_is_manual || s.cost_override != null || s.long_stay_daily_rate != null).map(s => s.id));
        const days: Record<string, number> = Object.fromEntries(segments.map(s => [s.id, 0]));
        const pendingAttendance: { day: string; kind: string; attendantId?: string }[] = [];
        let checkoutAdjustment: any = frozen ? saved.checkoutAdjustment : null;
        let actualPatientPresentDays = 0, projectedPatientPresentDays = 0;
        if (!frozen && options.checkoutAt && cycleId === currentCycle)
            checkoutAdjustment = { day: dayKey(options.checkoutAt), included: afterCheckoutCutoff(options.checkoutAt), includedInTotal: true, amount: 0, checkoutAt: options.checkoutAt.getTime() };
        if (segments.length && !frozen) {
            const start = dayKey(segments[0].admission_date);
            let end: any, isActualCheckout = false;
            if (options.checkoutAt && cycleId === currentCycle) { end = options.checkoutAt; isActualCheckout = true; }
            else if (active) {
                end = patient.exit_date;
                if (!end) {
                    // An open admission retains its seven-day advance, extending for
                    // elapsed days, stay extensions and genuinely recorded attendance.
                    const candidates = [nextDay(start, 6) + 'T03:30:00Z', dayKey(options.asOf ?? Date.now()) + 'T03:30:00Z', ...segments.filter(s => s.status === 'active').map(s => (s.expected_discharge_date ? dayKey(new Date(new Date(s.expected_discharge_date).getTime() - 86400000)) : nextDay(start, 6)) + 'T03:30:00Z'), ...[...attendance.keys(), ...attendants.keys()].map(d => d + 'T03:30:00Z')];
                    end = new Date(Math.max(...candidates.map(d => new Date(d).getTime())));
                }
            }
            else
            { end = patient.discharge_date ?? new Date(Math.max(...segments.map(s => new Date(s.completed_at ?? s.updated_at).getTime()))); isActualCheckout = true; }
            const checkoutDay = patient.exit_date ? dayKey(patient.exit_date) : null;
            const hasCheckoutAttendance = Boolean(
                checkoutDay && (attendance.has(checkoutDay) || attendants.has(checkoutDay))
            );
            let exclusive = isActualCheckout
                ? checkoutEnd(end)
                : patient.exit_date
                    ? ((afterCheckoutCutoff(end) || hasCheckoutAttendance) ? nextDay(dayKey(end)) : dayKey(end))
                    : nextDay(dayKey(end));
            if (exclusive <= start) exclusive = nextDay(start);
            let billableDays = 0;
            for (let d = start; d < exclusive; d = nextDay(d)) {
                const candidates = segments.filter(s => {
                    if (dayKey(s.admission_date) > d)
                        return false;
                    if ((active || options.checkoutAt) && s.status === 'active')
                        return true;
                    const checkout = s.completed_at ?? s.updated_at;
                    return d < checkoutEnd(checkout);
                });
                if (!candidates.length)
                    continue;
                const patientState = attendance.get(d) ?? 'Pending';
                if (!['Present', 'Absent'].includes(patientState)) pendingAttendance.push({ day: d, kind: 'attendance' });
                const patientBillable = patientState === 'Present' || (!options.finalize && patientState !== 'Absent');
                const patientPresentDaysBefore = options.finalize ? actualPatientPresentDays : projectedPatientPresentDays;
                const longStay = usesLongStayTier(patientPresentDaysBefore);
                if (patientState === 'Present') actualPatientPresentDays++;
                // A projection can assume unresolved patient dates are Present,
                // but never changes their attendance or actual threshold count.
                if (patientBillable) projectedPatientPresentDays++;
                const marks = attendants.get(d) ?? new Map<string, string>();
                const resolveAttendants = (stay: any) => {
                const unresolved: typeof pendingAttendance = [];
                const snapshotRoster = stay.patient_snapshot?.attendants;
                const people: any[] = (Array.isArray(snapshotRoster) ? snapshotRoster : cycleId === currentCycle ? roster : []).map((person: any) => {
                    const matches = roster.filter((a: any) => a.name === person.name);
                    return person.id == null && matches.length === 1 ? { ...person, id: matches[0].id } : person;
                });
                const safeName = (name: string) => name.replace(/[.#$\[\]/]/g, '_');
                const known = new Set<string>();
                let attendantCount = 0;
                for (const person of people) {
                    const key = String(person.id ?? person.name);
                    known.add(key);
                    const uniqueName = people.filter(p => p.name === person.name).length === 1;
                    const legacy = uniqueName ? marks.get(person.name) ?? marks.get(safeName(person.name ?? '')) : undefined;
                    const mark = (person.id != null || uniqueName ? marks.get(key) : undefined) ?? legacy ?? 'Pending';
                    known.add(person.name); known.add(safeName(person.name ?? ''));
                    if (!eligibleAttendant(person, d)) continue;
                    if (mark === 'Present') attendantCount++;
                    if (!['Present', 'Absent'].includes(mark)) unresolved.push({ day: d, kind: 'attendant_attendance', attendantId: key });
                }
                // Retain historical attendants no longer in the current roster.
                for (const [key, mark] of marks) if (!known.has(key)) {
                    const associated = segments.flatMap(s => s.patient_snapshot?.attendants ?? []).filter((p: any) => p.id === key);
                    if (associated.length && !associated.some((p: any) => eligibleAttendant(p, d))) continue;
                    if (mark === 'Present') attendantCount++;
                    else if (mark !== 'Absent') unresolved.push({ day: d, kind: 'attendant_attendance', attendantId: key });
                }
                return { attendantCount, unresolved };
                };
                const resolved = new Map(candidates.map(s => [s.id, resolveAttendants(s)]));
                const cost = (s: any, attendantCount = resolved.get(s.id)!.attendantCount) => {
                    if (s.room_type !== 'private' && !patientBillable && !attendantCount) return 0;
                    const stayPricing = s.billing_summary?.pricing ?? pricing;
                    const base = s.daily_rate_is_manual && s.daily_rate != null ? money(s.daily_rate) : baseDailyChargeCents(s.room_type, attendantCount, stayPricing, patientBillable);
                    return !longStay ? base : s.long_stay_daily_rate != null ? money(s.long_stay_daily_rate) : dailyChargeCents(s.room_type, attendantCount, stayPricing, patientBillable, base);
                };
                // An explicit transfer establishes destination ownership from
                // its effective date. Ambiguous legacy overlaps use the higher
                // applicable daily amount once, independently of occupied beds.
                const explicit = candidates.filter(s =>
                    s.patient_snapshot?.transferFingerprint ||
                    s.notes === 'Room transfer' ||
                    s.notes?.toLowerCase().startsWith('shifted from') ||
                    candidates.some(other => other.id !== s.id && other.completed_at && new Date(other.completed_at).getTime() === new Date(s.admission_date).getTime())
                );
                const owners = explicit.length ? explicit : candidates;
                owners.sort((a, b) => (explicit.length ? new Date(b.admission_date).getTime() - new Date(a.admission_date).getTime() : cost(b) - cost(a)) || new Date(b.admission_date).getTime() - new Date(a.admission_date).getTime() || String(a.id).localeCompare(String(b.id)));
                const chosen = owners[0];
                const { attendantCount, unresolved } = resolved.get(chosen.id)!;
                pendingAttendance.push(...unresolved);
                const privateRoom = chosen.room_type === 'private';
                const billable = privateRoom || patientBillable || attendantCount > 0;
                if (!billable) continue;
                billableDays++;
                charges[chosen.id] += cost(chosen);
                // Split the very same daily tariff, including Private's included
                // attendant. Explicit aggregate overrides have no invented split.
                if (!unsplit.has(chosen.id)) {
                    const patientCost = cost(chosen, 0);
                    patientCharges[chosen.id] += patientCost;
                    attendantCharges[chosen.id] += cost(chosen) - patientCost;
                }
                days[chosen.id]++;
                if (options.checkoutAt && cycleId === currentCycle && d === dayKey(options.checkoutAt)) {
                    const stayPricing = chosen.billing_summary?.pricing ?? pricing;
                    const base = baseDailyChargeCents(chosen.room_type, 0, stayPricing, patientBillable);
                    const patientAmount = longStay ? dailyChargeCents(chosen.room_type, 0, stayPricing, patientBillable, base) : base;
                    const custom = chosen.daily_rate_is_manual || (longStay && chosen.long_stay_daily_rate != null);
                    checkoutAdjustment = { ...checkoutAdjustment, stayId: chosen.id, billableDay: billableDays, patientPresentDaysBefore,
                        amount: chosen.cost_override == null ? cost(chosen) / 100 : 0, includedByOverride: chosen.cost_override != null,
                        patientAmount: custom ? null : patientAmount / 100, attendantAmount: custom ? null : (cost(chosen) - patientAmount) / 100, category: chosen.room_type };
                }
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
        for (const r of receipts.filter(r => allocatedCycle(r) === cycleId)) {
            const amount = money(r.amount);
            if (amount < 0)
                refunded -= amount;
            else
                paid += amount;
        }
        const net = paid - refunded, due = Math.max(0, billed - net), excess = Math.max(0, net - billed);
        balances[cycleId] = { ...(frozen ? saved : {}), cycleId, total: billed / 100, paid: paid / 100, refunded: refunded / 100, netPaid: net / 100, due: due / 100, refundDue: excess / 100, status: status(net, due, excess), segmentCharges: segments.length ? Object.fromEntries(Object.entries(charges).map(([k, v]) => [k, v / 100])) : (patient.admission_balances?.[cycleId]?.segmentCharges ?? {}), segmentDays: segments.length ? days : (patient.admission_balances?.[cycleId]?.segmentDays ?? {}), ...(!frozen ? { finalized: options.finalize === true && cycleId === currentCycle, provisional: pendingAttendance.length > 0 || active && !patient.exit_date && !options.checkoutAt, pendingAttendance, actualPatientPresentDays, projectedPatientPresentDays, pricingBasis: options.finalize ? 'actual_patient_present' : 'projected_patient_present', checkoutAdjustment, checkoutAt: cycleId === currentCycle && options.checkoutAt ? options.checkoutAt.getTime() : null, plannedExitConfirmed: patient.exit_date != null } : {}) };
        balances[cycleId].reconciliationRequired = reconciliation.required;
        if (!frozen) {
            balances[cycleId].segmentPatientCharges = Object.fromEntries(Object.entries(patientCharges).filter(([id]) => !unsplit.has(id)).map(([id, amount]) => [id, amount / 100]));
            balances[cycleId].segmentAttendantCharges = Object.fromEntries(Object.entries(attendantCharges).filter(([id]) => !unsplit.has(id)).map(([id, amount]) => [id, amount / 100]));
        }
    }
    const current = balances[currentCycle];
    const rangeStart = dayKey(patient.admission_date), rangeEnd = dayKey(options.checkoutAt ?? (patient.status === 'discharged' ? patient.discharge_date ?? patient.exit_date ?? Date.now() : patient.exit_date ?? Date.now()));
    const marks = [...attendance].filter(([d]) => d >= rangeStart && d <= rangeEnd).map(([, s]) => s);
    const fields = { advance_billed_amount: decimal(money(current.total)), attendance_charges: '0.00', billing_amount_override: stays.length ? null : patient.billing_amount_override, total_paid_amount: decimal(money(current.netPaid)), current_due_amount: decimal(money(current.due)), refund_due_amount: decimal(money(current.refundDue)), total_refund_due_amount: decimal(Object.values(balances).reduce((sum, b) => sum + money(b.refundDue), 0)), total_refunded_amount: decimal(Object.values(balances).reduce((sum, b) => sum + money(b.refunded), 0)), payment_pending: current.due > 0, payment_status: current.status, admission_balances: balances, total_present_days: marks.filter(s => s === 'Present').length, total_absent_days: marks.filter(s => s === 'Absent').length };
    const conflictedStays = new Set(identityIssues.map(issue => issue.stayId));
    const computedStays = stays.map(s => { const b = balances[stayCycle(s, patient)]; return b && !conflictedStays.has(s.id) && s.status !== 'cancelled' && !(b.finalized && !options.finalize) && stayCycle(s, patient) === currentCycle ? { ...s, total_cost: decimal(money(b.segmentCharges[s.id] ?? 0)), billing_summary: { ...s.billing_summary, pricing: s.billing_summary?.pricing ?? pricing, days: b.segmentDays[s.id] ?? 0, amount: b.segmentCharges[s.id] ?? 0, admissionId: b.cycleId, provisional: b.provisional, checkoutAdjustment: b.checkoutAdjustment?.stayId == null || b.checkoutAdjustment.stayId === s.id ? b.checkoutAdjustment : null, pendingAttendance: b.pendingAttendance }, cycle_id: b.cycleId, daily_rate: s.daily_rate_is_manual ? s.daily_rate : null } : s; });
    for (const s of computedStays) {
        const b = balances[stayCycle(s, patient)];
        if (!conflictedStays.has(s.id) && s.status !== 'cancelled' && stayCycle(s, patient) === currentCycle && !(b.finalized && !options.finalize) && b.segmentPatientCharges?.[s.id] != null) {
            s.base_cost = decimal(money(b.segmentPatientCharges[s.id]));
            s.extra_attendant_cost = decimal(money(b.segmentAttendantCharges[s.id]));
        }
    }
    return { patient: { ...patient, ...fields, financial_reconciliation: { ...reconciliation, accountNetPaid: reconciliation.accountPaid - reconciliation.accountRefunded, provisional: current.provisional === true } }, fields, stays: computedStays, receipts, balances, reconciliation, attendance, repriceClosed: options.finalize === true,
        source: { stays: sourceStays, records, receipts, pricing, roster } };
}

/** Marginal charge for the added period, using the final invoice engine. */
export async function quoteStayExtension(client: pg.PoolClient, patient: any, stay: any, additionalDays: number) {
    if (!Number.isInteger(additionalDays) || additionalDays < 1 || additionalDays > 3650)
        throw httpError(400, 'Invalid stay extension');
    const cycle = String(new Date(patient.admission_date).getTime());
    if (stay.status !== 'active' || patient.status === 'discharged' || stayCycle(stay, patient) !== cycle)
        throw httpError(409, 'Only the current active admission can be extended');
    const from = patient.exit_date ? nextDay(dayKey(patient.exit_date)) : dayKey(stay.expected_discharge_date);
    const through = nextDay(from, additionalDays);
    const asOf = Date.now();
    const beforeProjection = await projectBilling(client, patient, { asOf, ignoreCheckout: true });
    if (beforeProjection.reconciliation.cycleIdentityIssues.length)
        throw httpError(409, 'Reconcile admission identities before pricing a stay extension');
    const before = beforeProjection.balances[cycle];
    const afterPatient = { ...patient, exit_date: patient.exit_date ? new Date(new Date(patient.exit_date).getTime() + additionalDays * 86400000) : null };
    const after = (await projectBilling(client, afterPatient, { asOf, ignoreCheckout: true, source: beforeProjection.source, stayEndDates: {
        [stay.id]: new Date(new Date(stay.expected_discharge_date).getTime() + additionalDays * 86400000),
    } })).balances[cycle];
    const cost = money(after.total) - money(before.total);
    if (cost < 0) throw httpError(409, 'Extension quote would reduce existing charges');
    return { additionalDays, additionalCost: cost / 100, from, throughExclusive: through,
        priorBillableDays: before.projectedPatientPresentDays,
        actualPatientPresentDays: before.actualPatientPresentDays,
        pricingBasis: 'projected_billable_attendance' };
}

export async function persistBilling(client: pg.PoolClient, projection: Awaited<ReturnType<typeof projectBilling>>) {
    const keys = Object.keys(projection.fields);
    const values = Object.values(projection.fields).map(v => typeof v === 'object' && v !== null ? JSON.stringify(v) : v);
    const updated = (await client.query(`UPDATE patients SET ${keys.map((k, i) => `${k}=$${i + 2}`).join(',')},version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=$1 RETURNING *`, [projection.patient.id, ...values])).rows[0];
    const unresolvedStays = new Set(projection.reconciliation.cycleIdentityIssues.map(issue => issue.stayId));
    for (const s of projection.stays.filter(s => !unresolvedStays.has(s.id) && s.status !== 'cancelled' && (projection.patient.status !== 'discharged' || projection.repriceClosed) && stayCycle(s, projection.patient) === String(new Date(projection.patient.admission_date).getTime())))
        await client.query('UPDATE stays SET total_cost=$2,billing_summary=$3::jsonb,cycle_id=$4,daily_rate=$5,base_cost=COALESCE($6,base_cost),extra_attendant_cost=COALESCE($7,extra_attendant_cost),updated_at=CURRENT_TIMESTAMP WHERE id=$1', [s.id, s.total_cost, JSON.stringify(s.billing_summary), s.cycle_id, s.daily_rate, s.base_cost, s.extra_attendant_cost]);
    projection.patient = { ...updated, financial_reconciliation: projection.patient.financial_reconciliation };
    return projection;
}
