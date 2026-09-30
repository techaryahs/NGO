'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const billing = require('../lib/billing');
const manualPayments = require('../lib/manual-payments');
const { FakeDatabase } = require('./helpers/fake-db');

function ist(y, m, d, h = 0, min = 0) {
  return Date.UTC(y, m - 1, d, h, min) - (5 * 60 + 30) * 60000;
}

const ADMISSION = ist(2026, 8, 1, 10, 0);
const EXIT = ist(2026, 8, 8, 9, 0);

function seed() {
  const attendance = {};
  for (let d = billing.dayStartMs(ADMISSION); d < billing.dayStartMs(EXIT); d = billing.addDaysToDayStart(d, 1)) {
    attendance[billing.dateKey(d)] = {
      p1: { patientId: 'p1', status: 'Present', source: 'automatic_registration_period' },
    };
  }
  return new FakeDatabase({
    patients: {
      p1: {
        id: 'p1',
        fullName: 'Komal',
        status: 'active',
        admissionDate: ADMISSION,
        registrationDate: ADMISSION,
        exitDate: EXIT,
        advanceBilledAmount: 1400,
        attendanceCharges: 0,
        totalPaidAmount: 0,
        payments: [],
      },
    },
    stays: {
      s1: {
        id: 's1',
        patientId: 'p1',
        status: 'active',
        roomType: 'general',
        admissionDate: ADMISSION,
        expectedDischargeDate: EXIT,
        createdAt: ADMISSION,
        updatedAt: ADMISSION,
        patientSnapshot: {},
      },
    },
    admin_settings: { pricing: { generalRoomBedPrice: 200, privateRoomBasePrice: 700 } },
    attendance: { daily: attendance },
    attendant_attendance: { daily: {} },
    payments: {},
    paymentHistory: {},
  });
}

test('manual payment is recorded in the canonical ledger and mirrors', async () => {
  const db = seed();
  const result = await manualPayments.recordManualPayment(db, {
    patientId: 'p1',
    payment: { id: 'payment_001', amount: 500, method: 'Cash', date: ist(2026, 8, 2, 10, 0) },
  });
  assert.equal(result.applied, true);
  assert.ok(result.id.startsWith('manual_'));

  const record = db.data.payments[result.id];
  assert.equal(record.amount, 500);
  assert.equal(record.source, 'manual');
  assert.equal(record.verifiedBy, 'server');
  assert.equal(record.type, 'payment');
  assert.equal(record.patientId, 'p1');

  assert.equal(db.data.paymentHistory[result.id].amount, 500);
  assert.equal(db.data.patients.p1.payments.length, 1);
  // Billing: 1400 total, 500 paid -> due 900.
  assert.equal(db.data.patients.p1.currentDueAmount, 900);
});

test('zero and non-finite manual amounts are rejected', async () => {
  const db = seed();
  await assert.rejects(
    () => manualPayments.recordManualPayment(db, { patientId: 'p1', payment: { amount: 0 } }),
    /positive/,
  );
  await assert.rejects(
    () => manualPayments.recordManualPayment(db, { patientId: 'p1', payment: { amount: 'abc' } }),
    /positive/,
  );
});

test('refund is bounded by the server-computed refundable excess', async () => {
  const db = seed();
  await manualPayments.recordManualPayment(db, {
    patientId: 'p1',
    payment: { id: 'payment_002', amount: 2000, method: 'Cash', date: ist(2026, 8, 2, 10, 0) },
  });
  // 2000 paid vs 1400 bill -> 600 refundable.
  const refund = await manualPayments.recordManualPayment(db, {
    patientId: 'p1',
    payment: { id: 'refund_001', amount: 600, method: 'Cash', date: ist(2026, 8, 3, 10, 0), type: 'refund' },
    refund: true,
  });
  const record = db.data.payments[refund.id];
  assert.equal(record.amount, -600);
  assert.equal(record.type, 'refund');

  await assert.rejects(
    () =>
      manualPayments.recordManualPayment(db, {
        patientId: 'p1',
        payment: { id: 'refund_002', amount: 100, method: 'Cash', date: ist(2026, 8, 4, 10, 0), type: 'refund' },
        refund: true,
      }),
    /Refund exceeds/,
  );
});

test('manual retry uses one ledger id and does not double count', async () => {
  const db = seed();
  const request = { patientId: 'p1', payment: {
    id: 'payment_retry', amount: 500, method: 'Cash', date: ADMISSION,
  } };
  const first = await manualPayments.recordManualPayment(db, request);
  const second = await manualPayments.recordManualPayment(db, request);
  assert.equal(first.id, second.id);
  assert.equal(second.applied, false);
  assert.equal(db.data.patients.p1.payments.length, 1);
  assert.equal(db.data.patients.p1.currentDueAmount, 900);
});

test('admin correction and void update billing while retaining audit history', async () => {
  const db = seed();
  const { id } = await manualPayments.recordManualPayment(db, {
    patientId: 'p1', payment: { id: 'payment_edit', amount: 500, method: 'Cash', date: ADMISSION },
  });
  await manualPayments.amendManualPayment(db, {
    patientId: 'p1', paymentId: id, changes: { amount: 700, transactionId: 'BANK-1' }, uid: 'admin-1',
  });
  assert.equal(db.data.patients.p1.currentDueAmount, 700);
  assert.equal(db.data.paymentHistory[id].amount, 700);
  assert.equal(db.data.paymentHistory[id].amendedBy, 'admin-1');
  await manualPayments.amendManualPayment(db, {
    patientId: 'p1', paymentId: id, voidPayment: true, uid: 'admin-1',
  });
  assert.equal(db.data.patients.p1.currentDueAmount, 1400);
  assert.equal(db.data.patients.p1.payments.length, 0);
  assert.equal(db.data.payments[id].status, 'void');
  assert.equal(db.data.paymentHistory[id].voidedBy, 'admin-1');
});

test('captured online ledger entries cannot be amended as manual payments', async () => {
  const db = seed();
  db.data.payments.razorpay_pay123 = {
    id: 'pay123', patientId: 'p1', amount: 500, source: 'razorpay', status: 'paid',
  };
  await assert.rejects(() => manualPayments.amendManualPayment(db, {
    patientId: 'p1', paymentId: 'razorpay_pay123', changes: { amount: 1000 }, uid: 'admin-1',
  }), /Only active manual/);
});
