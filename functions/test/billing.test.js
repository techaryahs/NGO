'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const billing = require('../lib/billing');

// ---------------------------------------------------------------------------
// Time helpers — IST timestamps expressed as UTC epoch-ms.
// ---------------------------------------------------------------------------

/** IST date-time -> UTC ms (IST is UTC+5:30, no DST). */
function ist(y, m, d, h = 0, min = 0) {
  return Date.UTC(y, m - 1, d, h, min) - (5 * 60 + 30) * 60000;
}

const PRICING = {
  privateRoomBasePrice: 700,
  privateRoomIncludedAttendants: 1,
  privateRoomExtraAttendantFee: 200,
  privateRoomMaxAttendants: 5,
  generalRoomBedPrice: 200,
  generalRoomIncludedAttendants: 1,
  generalRoomMaxAttendants: 2,
};

function patient(overrides = {}) {
  return {
    id: 'p1',
    fullName: 'Test Patient',
    status: 'active',
    admissionDate: ist(2026, 8, 1, 10, 0),
    registrationDate: ist(2026, 8, 1, 10, 0),
    exitDate: ist(2026, 8, 8, 9, 0),
    advanceBilledAmount: 0,
    attendanceCharges: 0,
    billingAmountOverride: null,
    totalPaidAmount: 0,
    payments: [],
    ...overrides,
  };
}

function stay(id, overrides = {}) {
  return {
    id,
    patientId: 'p1',
    status: 'active',
    roomType: 'general',
    admissionDate: ist(2026, 8, 1, 10, 0),
    expectedDischargeDate: ist(2026, 8, 8, 9, 0),
    createdAt: ist(2026, 8, 1, 10, 0),
    updatedAt: ist(2026, 8, 1, 10, 0),
    completedAt: null,
    cycleId: null,
    patientSnapshot: {},
    dailyRate: null,
    dailyRateIsManual: false,
    costOverride: null,
    longStayDailyRate: null,
    ...overrides,
  };
}

/** Patient 'Present' for every date in [startMs, endMs) in IST days. */
function presentRange(startMs, endMs) {
  const result = {};
  const start = billing.dayStartMs(startMs);
  const end = billing.dayStartMs(endMs);
  for (let d = start; d < end; d = billing.addDaysToDayStart(d, 1)) {
    result[billing.dateKey(d)] = 'Present';
  }
  return result;
}

test('documented example: 7 billable days, full attendance -> ₹2800', () => {
  const p = patient();
  const s = stay('s1');
  const attendance = presentRange(ist(2026, 8, 1), ist(2026, 8, 8));
  const attendantAttendance = {};
  for (const [key] of Object.entries(attendance)) {
    attendantAttendance[key] = { Attendant1: 'Present' };
  }
  const balances = billing.calculateBalances({
    patient: p,
    stays: [s],
    pricing: PRICING,
    attendance,
    attendantAttendance,
  });
  assert.equal(balances.length, 1);
  assert.equal(balances[0].total, 2800);
  assert.equal(balances[0].due, 2800);
});

test('documented example: attendant present 3 days, paid 1500 -> due 500', () => {
  const p = patient({
    payments: [{ id: 'pay1', amount: 1500, date: ist(2026, 8, 1, 10, 0), cycleId: null }],
  });
  const s = stay('s1');
  const attendance = presentRange(ist(2026, 8, 1), ist(2026, 8, 8));
  const attendantAttendance = {};
  let count = 0;
  for (const [key] of Object.entries(attendance)) {
    if (count++ < 3) attendantAttendance[key] = { Attendant1: 'Present' };
  }
  const balances = billing.calculateBalances({
    patient: p,
    stays: [s],
    pricing: PRICING,
    attendance,
    attendantAttendance,
  });
  assert.equal(balances[0].total, 2000);
  assert.equal(balances[0].netPaid, 1500);
  assert.equal(balances[0].due, 500);
  assert.equal(balances[0].refundDue, 0);
  assert.equal(balances[0].status, 'Partially Paid');
});

test('Komal case: 9 billable days, 6 attendant days, paid 800 -> due 2200', () => {
  const p = patient({
    admissionDate: ist(2026, 8, 1, 15, 34),
    registrationDate: ist(2026, 8, 1, 15, 34),
    exitDate: ist(2026, 8, 10, 9, 0),
    billingAmountOverride: 3600, // legacy override must not win once stays exist
    payments: [{ id: 'pay1', amount: 800, date: ist(2026, 8, 1, 15, 0), cycleId: null }],
  });
  const s = stay('s1', {
    admissionDate: ist(2026, 8, 1, 15, 34),
    expectedDischargeDate: ist(2026, 8, 10, 9, 0),
  });
  const attendance = presentRange(ist(2026, 8, 1), ist(2026, 8, 10));
  const attendantAttendance = {};
  let count = 0;
  for (const [key] of Object.entries(attendance)) {
    if (count++ < 6) attendantAttendance[key] = { Attendant1: 'Present' };
  }
  const balances = billing.calculateBalances({
    patient: p,
    stays: [s],
    pricing: PRICING,
    attendance,
    attendantAttendance,
  });
  assert.equal(balances[0].total, 3000);
  assert.equal(balances[0].due, 2200);
});

test('patient absent days reduce the charge', () => {
  const p = patient();
  const s = stay('s1');
  const attendance = presentRange(ist(2026, 8, 1), ist(2026, 8, 8));
  attendance['2026-08-05'] = 'Absent';
  attendance['2026-08-06'] = 'Absent';
  const balances = billing.calculateBalances({
    patient: p,
    stays: [s],
    pricing: PRICING,
    attendance,
  });
  assert.equal(balances[0].total, 1000); // 5 patient days x 200
});

test('exit before 9:00 AM does not add another billed day; after 9:00 does', () => {
  const before = patient({ exitDate: ist(2026, 8, 8, 8, 59) });
  const s1 = stay('s1', { expectedDischargeDate: ist(2026, 8, 8, 8, 59) });
  const b1 = billing.calculateBalances({
    patient: before,
    stays: [s1],
    pricing: PRICING,
    attendance: presentRange(ist(2026, 8, 1), ist(2026, 8, 8)),
  });
  assert.equal(b1[0].total, 1400); // 7 days

  const after = patient({ exitDate: ist(2026, 8, 8, 10, 0) });
  const s2 = stay('s2', { expectedDischargeDate: ist(2026, 8, 8, 10, 0) });
  const b2 = billing.calculateBalances({
    patient: after,
    stays: [s2],
    pricing: PRICING,
    attendance: presentRange(ist(2026, 8, 1), ist(2026, 8, 9)),
  });
  assert.equal(b2[0].total, 1600); // 8 days
});

test('transfer date is charged once to the segment covering it', () => {
  const p = patient({
    exitDate: ist(2026, 8, 10, 9, 0),
    status: 'active',
  });
  const room1 = stay('room1', {
    roomType: 'general',
    admissionDate: ist(2026, 8, 1, 10, 0),
    completedAt: ist(2026, 8, 5, 9, 0),
    status: 'completed',
  });
  const room2 = stay('room2', {
    roomType: 'general',
    admissionDate: ist(2026, 8, 5, 9, 0),
    expectedDischargeDate: ist(2026, 8, 10, 9, 0),
    status: 'active',
  });
  const balances = billing.calculateBalances({
    patient: p,
    stays: [room1, room2],
    pricing: PRICING,
    attendance: presentRange(ist(2026, 8, 1), ist(2026, 8, 10)),
  });
  assert.equal(balances[0].total, 1800);
  assert.equal(balances[0].charges.room1, 800); // Aug 1-4
  assert.equal(balances[0].charges.room2, 1000); // Aug 5-9
});

test('overlapping transfer date uses the higher room rate', () => {
  const p = patient({ exitDate: ist(2026, 8, 10, 9, 0) });
  const privateRoom = stay('private', {
    roomType: 'private',
    admissionDate: ist(2026, 8, 1, 10, 0),
    completedAt: ist(2026, 8, 5, 14, 0), // checkout after 9AM -> Aug 5 still candidate
    status: 'completed',
  });
  const generalRoom = stay('general', {
    roomType: 'general',
    admissionDate: ist(2026, 8, 5, 10, 0),
    expectedDischargeDate: ist(2026, 8, 10, 9, 0),
    status: 'active',
  });
  const balances = billing.calculateBalances({
    patient: p,
    stays: [privateRoom, generalRoom],
    pricing: PRICING,
    attendance: presentRange(ist(2026, 8, 1), ist(2026, 8, 10)),
  });
  // Aug 5 is covered by both segments; the private rate (700) must win.
  assert.equal(balances[0].charges.private, 4 * 700 + 700);
  assert.equal(balances[0].charges.general, 4 * 200);
  assert.equal(balances[0].total, 3500 + 800);
});

test('costOverride replaces the calculated segment charge', () => {
  const p = patient();
  const s = stay('s1', { costOverride: 2500 });
  const balances = billing.calculateBalances({
    patient: p,
    stays: [s],
    pricing: PRICING,
    attendance: presentRange(ist(2026, 8, 1), ist(2026, 8, 8)),
  });
  assert.equal(balances[0].total, 2500);
});

test('no stays: legacy advance amount and patient-level override', () => {
  const p1 = patient({ advanceBilledAmount: 1400, attendanceCharges: 0 });
  const b1 = billing.calculateBalances({ patient: p1, stays: [], pricing: PRICING });
  assert.equal(b1[0].total, 1400);

  const p2 = patient({
    advanceBilledAmount: 1400,
    billingAmountOverride: 3600,
  });
  const b2 = billing.calculateBalances({ patient: p2, stays: [], pricing: PRICING });
  assert.equal(b2[0].total, 3600);
});

test('long stay: after 60 days the higher daily rate applies', () => {
  const p = patient({
    exitDate: ist(2026, 10, 1, 9, 0),
  });
  const s = stay('s1', { expectedDischargeDate: ist(2026, 10, 1, 9, 0) });
  const balances = billing.calculateBalances({
    patient: p,
    stays: [s],
    pricing: PRICING,
    attendance: presentRange(ist(2026, 8, 1), ist(2026, 10, 1)),
  });
  // Aug has 31 days, Sep has 30: 61 billable days total.
  // Days 1-60 at 200; day 61 at 200 + 50 = 250.
  assert.equal(balances[0].total, 60 * 200 + 250);
});

test('refund reduces netPaid and creates refund due when overpaid', () => {
  const p = patient({
    payments: [
      { id: 'pay1', amount: 3000, date: ist(2026, 8, 1, 10, 0), cycleId: null },
      { id: 'refund1', amount: -600, date: ist(2026, 8, 3, 10, 0), cycleId: null },
    ],
  });
  const s = stay('s1');
  const balances = billing.calculateBalances({
    patient: p,
    stays: [s],
    pricing: PRICING,
    attendance: presentRange(ist(2026, 8, 1), ist(2026, 8, 8)),
  });
  assert.equal(balances[0].total, 1400);
  assert.equal(balances[0].paid, 3000);
  assert.equal(balances[0].refunded, 600);
  assert.equal(balances[0].netPaid, 2400);
  assert.equal(balances[0].refundDue, 1000);
  assert.equal(balances[0].status, 'Payment Exceeded');
});

test('same-day advance payment belongs to the admission cycle', () => {
  const p = patient({
    admissionDate: ist(2026, 9, 1, 15, 34),
    registrationDate: ist(2026, 9, 1, 15, 34),
    exitDate: ist(2026, 9, 8, 9, 0),
    payments: [
      // 10:48 AM same day, before the 3:34 PM registration time.
      { id: 'advance', amount: 500, date: ist(2026, 9, 1, 10, 48), cycleId: null },
    ],
  });
  const s = stay('s1', {
    admissionDate: ist(2026, 9, 1, 15, 34),
    expectedDischargeDate: ist(2026, 9, 8, 9, 0),
  });
  const balances = billing.calculateBalances({
    patient: p,
    stays: [s],
    pricing: PRICING,
    attendance: presentRange(ist(2026, 9, 1), ist(2026, 9, 8)),
  });
  assert.equal(balances.length, 1);
  assert.equal(balances[0].total, 1400);
  assert.equal(balances[0].paid, 500);
  assert.equal(balances[0].due, 900);
});

test('dailyRateIsManual stays are charged their stored rate', () => {
  const p = patient();
  const s = stay('s1', { dailyRate: 250, dailyRateIsManual: true });
  const balances = billing.calculateBalances({
    patient: p,
    stays: [s],
    pricing: PRICING,
    attendance: presentRange(ist(2026, 8, 1), ist(2026, 8, 8)),
  });
  assert.equal(balances[0].total, 7 * 250);
});
