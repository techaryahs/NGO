'use strict';

/**
 * Server-side port of the Flutter application's billing engine
 * (lib/utils/stay_billing.dart and lib/utils/pricing_helper.dart).
 *
 * The clinic's client machines record dates in local time (IST). To keep the
 * server calculation byte-for-byte compatible with the client, all calendar
 * date keys are derived in the Asia/Kolkata timezone. IST has no DST, so day
 * arithmetic uses fixed 24-hour steps from the IST midnight timestamp.
 */

const IST_TIMEZONE = 'Asia/Kolkata';
const ADVANCE_DAYS = 7;
const CHECKOUT_HOUR = 9;

// ---------------------------------------------------------------------------
// Time helpers
// ---------------------------------------------------------------------------

/** Split a millisecond timestamp into IST calendar parts. */
function istParts(ms) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: IST_TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).formatToParts(new Date(ms));
  const map = {};
  for (const part of parts) {
    if (part.type !== 'literal') map[part.type] = part.value;
  }
  return {
    year: Number(map.year),
    month: Number(map.month),
    day: Number(map.day),
    hour: Number(map.hour) % 24,
    minute: Number(map.minute),
    second: Number(map.second),
  };
}

/** 'YYYY-MM-DD' calendar key for a timestamp, in IST. */
function dateKey(ms) {
  const p = istParts(ms);
  const pad = (n) => String(n).padStart(2, '0');
  return `${p.year}-${pad(p.month)}-${pad(p.day)}`;
}

/** IST midnight of the given timestamp, expressed as a UTC epoch-ms value. */
function dayStartMs(ms) {
  const p = istParts(ms);
  return Date.UTC(p.year, p.month - 1, p.day);
}

/** Add `days` calendar days to an IST-midnight UTC timestamp. */
function addDaysToDayStart(dayStart, days) {
  return dayStart + days * 86400000;
}

/** Timestamp (ms) parsed from any numeric RTDB representation. */
function toMs(value, fallback) {
  if (value === null || value === undefined) return fallback;
  const n = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(n) ? n : fallback;
}

// ---------------------------------------------------------------------------
// Pricing (port of PricingHelper)
// ---------------------------------------------------------------------------

function numOr(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function intOr(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

function calculateDailyCharge(isPrivate, attendantsCount, pricing = {}) {
  const rate = (key, fallback) => numOr(pricing[key], fallback);
  const count = (key, fallback) => intOr(pricing[key], fallback);
  if (isPrivate) {
    const base = rate('privateRoomBasePrice', 700);
    const included = count('privateRoomIncludedAttendants', 1);
    const extraFee = rate('privateRoomExtraAttendantFee', 200);
    return (
      base +
      (attendantsCount > included
        ? (attendantsCount - included) * extraFee
        : 0)
    );
  }
  return (1 + attendantsCount) * rate('generalRoomBedPrice', 200);
}

// ---------------------------------------------------------------------------
// Cycle helpers (port of StayBilling)
// ---------------------------------------------------------------------------

function currentCycle(patient) {
  return String(toMs(patient.admissionDate, 0));
}

function cycleFor(stay, patient) {
  if (stay.cycleId !== null && stay.cycleId !== undefined) {
    return String(stay.cycleId);
  }
  const snapshot = stay.patientSnapshot || {};
  const saved = snapshot.admissionDate;
  if (saved !== null && saved !== undefined) return String(saved);
  const admissionMs = toMs(patient.admissionDate, 0);
  const createdAtMs = toMs(stay.createdAt, 0);
  const registrationMs = toMs(
    patient.registrationDate !== null && patient.registrationDate !== undefined
      ? patient.registrationDate
      : admissionMs,
    admissionMs,
  );
  if (
    !(createdAtMs < admissionMs - 60000) ||
    toMs(stay.admissionDate, 0) === registrationMs
  ) {
    return currentCycle(patient);
  }
  return String(toMs(stay.admissionDate, 0));
}

function paymentCycle(payment, patient, stays) {
  if (payment.cycleId !== null && payment.cycleId !== undefined) {
    return String(payment.cycleId);
  }
  const boundaries = new Set([currentCycle(patient)]);
  for (const stay of stays) {
    const value = Number(cycleFor(stay, patient));
    if (Number.isFinite(value)) boundaries.add(String(value));
  }
  const sorted = Array.from(boundaries)
    .map(Number)
    .sort((a, b) => a - b);
  const paymentDayStart = dayStartMs(toMs(payment.date, 0));
  const before = sorted.filter((value) => dayStartMs(value) <= paymentDayStart);
  if (before.length === 0) return `before-${sorted[0]}`;
  return String(before[before.length - 1]);
}

// ---------------------------------------------------------------------------
// Balance calculation (port of StayBilling.calculate)
// ---------------------------------------------------------------------------

/**
 * @param {object} patient raw RTDB patient map
 * @param {Array<object>} stays stay maps (with `id`)
 * @param {object} pricing pricing map
 * @param {object} attendance { dateKey: status } for the patient
 * @param {object} attendantAttendance { dateKey: { attendantName: status } }
 * @param {number|null} nowMs optional override for "today"
 * @returns {Array<object>} admission balances (one per admission cycle)
 */
function calculateBalances({
  patient,
  stays,
  pricing,
  attendance = {},
  attendantAttendance = {},
  nowMs = null,
}) {
  const now = nowMs === null ? Date.now() : nowMs;
  const groups = new Map();
  for (const stay of stays.filter((s) => s.status !== 'cancelled')) {
    const key = cycleFor(stay, patient);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(stay);
  }
  if (!groups.has(currentCycle(patient))) groups.set(currentCycle(patient), []);

  const result = [];
  for (const [groupKey, groupStays] of groups.entries()) {
    const segments = groupStays
      .slice()
      .sort((a, b) => toMs(a.admissionDate, 0) - toMs(b.admissionDate, 0));
    const charges = {};
    const days = {};
    for (const s of segments) {
      charges[s.id] = 0;
      days[s.id] = 0;
    }
    const isCurrent = groupKey === currentCycle(patient);
    const active =
      isCurrent && String(patient.status || '').toLowerCase() !== 'discharged';

    let total = 0;
    if (segments.length > 0) {
      const start = dayStartMs(toMs(segments[0].admissionDate, 0));
      let endMs;
      if (active) {
        if (patient.exitDate !== null && patient.exitDate !== undefined) {
          endMs = toMs(patient.exitDate, now);
        } else {
          const estimateEnd = addDaysToDayStart(start, ADVANCE_DAYS);
          const segmentEnds = segments
            .filter((segment) => segment.status === 'active')
            .map((segment) => toMs(segment.expectedDischargeDate, 0))
            .filter((value) => value > 0);
          endMs = segmentEnds.reduce(
            (latest, value) => (value > latest ? value : latest),
            estimateEnd,
          );
        }
      } else {
        endMs = segments.reduce((latest, s) => {
          const value = toMs(
            s.completedAt !== null && s.completedAt !== undefined
              ? s.completedAt
              : s.updatedAt,
            0,
          );
          return value > latest ? value : latest;
        }, 0);
      }

      let exclusiveEnd = dayStartMs(endMs);
      const endParts = istParts(endMs);
      if (
        endParts.hour > CHECKOUT_HOUR ||
        (endParts.hour === CHECKOUT_HOUR && endParts.minute > 0)
      ) {
        exclusiveEnd = addDaysToDayStart(exclusiveEnd, 1);
      }
      if (exclusiveEnd <= start) exclusiveEnd = addDaysToDayStart(start, 1);

      let hasPresentAttendance = false;
      for (let d = start; d < exclusiveEnd; d = addDaysToDayStart(d, 1)) {
        if (attendance[dateKey(d)] === 'Present') {
          hasPresentAttendance = true;
          break;
        }
      }

      let billableDays = 0;
      for (let d = start; d < exclusiveEnd; d = addDaysToDayStart(d, 1)) {
        const key = dateKey(d);
        const status = attendance[key];
        if (status === 'Absent' || (hasPresentAttendance && status !== 'Present')) {
          continue;
        }
        const candidates = segments.filter((s) => {
          if (dayStartMs(toMs(s.admissionDate, 0)) > d) return false;
          if (s.status === 'active' && active) return true;
          const checkoutMs = toMs(
            s.completedAt !== null && s.completedAt !== undefined
              ? s.completedAt
              : s.updatedAt,
            0,
          );
          let checkoutEnd = dayStartMs(checkoutMs);
          const checkoutParts = istParts(checkoutMs);
          if (
            checkoutParts.hour > CHECKOUT_HOUR ||
            (checkoutParts.hour === CHECKOUT_HOUR && checkoutParts.minute > 0)
          ) {
            checkoutEnd = addDaysToDayStart(checkoutEnd, 1);
          }
          return (
            d < checkoutEnd ||
            (d === dayStartMs(toMs(s.admissionDate, 0)) &&
              checkoutMs > toMs(s.admissionDate, 0))
          );
        });
        if (candidates.length === 0) continue;
        billableDays++;

        const daily = attendantAttendance[key] || {};
        const attendantsPresent = Object.values(daily).filter(
          (v) => v === 'Present',
        ).length;

        const rateFor = (segment) => {
          const base =
            segment.dailyRateIsManual === true &&
            segment.dailyRate !== null &&
            segment.dailyRate !== undefined
              ? numOr(segment.dailyRate, 0)
              : calculateDailyCharge(
                  segment.roomType === 'private',
                  attendantsPresent,
                  pricing,
                );
          const extra =
            segment.roomType === 'private'
              ? 200 +
                Math.max(
                  0,
                  attendantsPresent - intOr(pricing['privateRoomIncludedAttendants'], 1),
                ) *
                  100
              : (1 + attendantsPresent) * 50;
          const rate =
            billableDays <= 60
              ? base
              : segment.longStayDailyRate !== null &&
                  segment.longStayDailyRate !== undefined
                ? numOr(segment.longStayDailyRate, base + extra)
                : base + extra;
          return rate;
        };

        candidates.sort((a, b) => {
          const rateOrder = rateFor(b) - rateFor(a);
          if (rateOrder !== 0) return rateOrder;
          return toMs(b.admissionDate, 0) - toMs(a.admissionDate, 0);
        });
        const segment = candidates[0];
        charges[segment.id] += rateFor(segment);
        days[segment.id] += 1;
      }

      for (const segment of segments) {
        if (segment.costOverride !== null && segment.costOverride !== undefined) {
          charges[segment.id] = numOr(segment.costOverride, 0);
        }
      }
    }

    total = Object.values(charges).reduce((a, b) => a + b, 0);
    if (segments.length === 0) {
      total = numOr(patient.advanceBilledAmount, 0) + numOr(patient.attendanceCharges, 0);
    }
    if (
      isCurrent &&
      segments.length === 0 &&
      patient.billingAmountOverride !== null &&
      patient.billingAmountOverride !== undefined
    ) {
      total = numOr(patient.billingAmountOverride, 0);
    }

    let paid = 0;
    let refunded = 0;
    const payments = patient.payments || null;
    if (payments !== null) {
      for (const payment of payments) {
        if (paymentCycle(payment, patient, segments) !== groupKey) continue;
        if (numOr(payment.amount, 0) < 0) {
          refunded -= numOr(payment.amount, 0);
        } else {
          paid += numOr(payment.amount, 0);
        }
      }
    }
    if (payments === null && isCurrent) {
      paid = numOr(patient.totalPaidAmount, 0);
    }

    result.push(balanceOf(groupKey, segments, charges, days, total, paid, refunded));
  }
  return result;
}

function balanceOf(id, stays, charges, days, total, paid, refunded) {
  const netPaid = paid - refunded;
  const due = Math.max(0, total - netPaid);
  const refundDue = Math.max(0, netPaid - total);
  const status =
    refundDue > 0.005
      ? 'Payment Exceeded'
      : due <= 0.005
        ? 'Paid'
        : netPaid > 0
          ? 'Partially Paid'
          : 'Unpaid';
  return {
    id,
    stays,
    charges,
    days,
    total,
    paid,
    refunded,
    netPaid,
    due,
    refundDue,
    status,
    toMap() {
      return {
        cycleId: id,
        total,
        paid,
        refunded,
        netPaid,
        due,
        refundDue,
        status,
        segmentCharges: charges,
        segmentDays: days,
      };
    },
  };
}

module.exports = {
  IST_TIMEZONE,
  ADVANCE_DAYS,
  CHECKOUT_HOUR,
  istParts,
  dateKey,
  dayStartMs,
  addDaysToDayStart,
  toMs,
  numOr,
  intOr,
  calculateDailyCharge,
  currentCycle,
  cycleFor,
  paymentCycle,
  calculateBalances,
};
