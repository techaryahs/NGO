'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const billing = require('../lib/billing');
const billingUpdate = require('../lib/billing-update');
const ledger = require('../lib/ledger');
const { FakeDatabase } = require('./helpers/fake-db');

function ist(y, m, d, h = 0, min = 0) {
  return Date.UTC(y, m - 1, d, h, min) - (5 * 60 + 30) * 60000;
}

const ADMISSION = ist(2026, 8, 1, 10, 0);
const EXIT = ist(2026, 8, 8, 9, 0);

function seedDatabase() {
  const attendance = {};
  for (let d = billing.dayStartMs(ADMISSION); d < billing.dayStartMs(EXIT); d = billing.addDaysToDayStart(d, 1)) {
    attendance[billing.dateKey(d)] = {
      p1: {
        patientId: 'p1',
        patientName: 'Komal',
        status: 'Present',
        source: 'automatic_registration_period',
        date: billing.dateKey(d),
      },
    };
  }
  // Out-of-range records must not influence the calculation.
  attendance['2026-07-30'] = { p1: { patientId: 'p1', status: 'Present' } };
  attendance['2026-08-20'] = { p1: { patientId: 'p1', status: 'Present' } };

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
        billingAmountOverride: null,
        totalPaidAmount: 0,
        payments: [],
        attendants: [],
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
        cycleId: null,
        patientSnapshot: {},
        dailyRate: 200, // generated legacy rate -> must migrate to null
        dailyRateIsManual: false,
        costOverride: null,
      },
    },
    admin_settings: {
      pricing: {
        generalRoomBedPrice: 150, // legacy fallback -> must migrate to 200
        privateRoomBasePrice: 700,
        privateRoomIncludedAttendants: 1,
        privateRoomExtraAttendantFee: 200,
      },
    },
    attendance: { daily: attendance },
    attendant_attendance: { daily: {} },
    paymentLinks: {},
    payments: {},
    paymentHistory: {},
    razorpayEvents: {},
  });
}

test('buildBillingUpdates recomputes billing and migrates legacy rates', async () => {
  const db = seedDatabase();
  const { updates } = await billingUpdate.buildBillingUpdates(db, 'p1');
  assert.equal(updates['patients/p1/advanceBilledAmount'], 1400);
  assert.equal(updates['patients/p1/paymentPending'], true);
  assert.equal(updates['patients/p1/paymentStatus'], 'Unpaid');
  assert.equal(updates['patients/p1/totalPresentDays'], 7);
  assert.equal(updates['patients/p1/totalAbsentDays'], 0);
  assert.equal(updates['stays/s1/dailyRate'], null);
  assert.equal(updates['admin_settings/pricing/generalRoomBedPrice'], 200);
  assert.equal(updates['stays/s1/totalCost'], 1400);
  assert.equal(updates['stays/s1/billableDays'], 7);
  assert.ok(updates['stays/s1/patientSnapshot']);
  assert.equal(updates['stays/s1/patientSnapshot'].registrationNumber, undefined);
  const balances = updates['patients/p1/admissionBalances'];
  assert.ok(balances[String(ADMISSION)]);
  assert.equal(balances[String(ADMISSION)].total, 1400);
  assert.equal(balances[String(ADMISSION)].due, 1400);
});

test('buildBillingUpdates throws for a missing patient', async () => {
  const db = seedDatabase();
  await assert.rejects(
    () => billingUpdate.buildBillingUpdates(db, 'missing'),
    /not found/,
  );
});

test('applyRazorpayPayment records the payment exactly once and settles billing', async () => {
  const db = seedDatabase();
  db.data.paymentLinks['plink_1'] = {
    id: 'plink_1',
    patientId: 'p1',
    amountPaise: 50000,
    status: 'created',
  };
  const payment = {
    id: 'pay_TEST123',
    amountPaise: 50000,
    method: 'upi',
    capturedAtMs: ist(2026, 8, 2, 10, 0),
    linkId: 'plink_1',
    eventId: 'payment_link.paid:pay_TEST123',
    verifiedBy: 'webhook',
  };

  const first = await ledger.applyRazorpayPayment(db, {
    patientId: 'p1',
    payment,
  });
  assert.equal(first.applied, true);
  assert.equal(first.id, 'razorpay_pay_TEST123');

  const record = db.data.payments['razorpay_pay_TEST123'];
  assert.equal(record.amount, 500);
  assert.equal(record.status, 'paid');
  assert.equal(record.source, 'razorpay');
  assert.equal(record.verifiedBy, 'webhook');
  assert.equal(record.transactionId, 'pay_TEST123');
  assert.equal(record.patientId, 'p1');

  assert.equal(db.data.patients.p1.payments.length, 1);
  assert.equal(db.data.paymentLinks['plink_1'].status, 'paid');
  assert.equal(db.data.razorpayEvents['payment_link.paid:pay_TEST123'].paymentId, 'pay_TEST123');

  // Billing: 1400 total, 500 paid -> due 900.
  assert.equal(db.data.patients.p1.totalPaidAmount, 500);
  assert.equal(db.data.patients.p1.currentDueAmount, 900);
  assert.equal(db.data.patients.p1.paymentStatus, 'Partially Paid');

  // Idempotency: a duplicate webhook must not double-record.
  const second = await ledger.applyRazorpayPayment(db, {
    patientId: 'p1',
    payment: { ...payment, eventId: 'payment_link.paid:pay_TEST123:duplicate' },
  });
  assert.equal(second.applied, false);
  assert.equal(db.data.patients.p1.payments.length, 1);
  assert.equal(db.data.payments['razorpay_pay_TEST123'].amount, 500);
});

test('applyRazorpayPayment rejects an unknown patient', async () => {
  const db = seedDatabase();
  await assert.rejects(
    () =>
      ledger.applyRazorpayPayment(db, {
        patientId: 'missing',
        payment: {
          id: 'pay_TEST123',
          amountPaise: 100,
          method: 'upi',
          capturedAtMs: Date.now(),
          linkId: 'plink_1',
          eventId: 'e1',
          verifiedBy: 'webhook',
        },
      }),
    /not found/,
  );
});

test('concurrent manual payment and webhook both survive (transaction merge)', async () => {
  const db = seedDatabase();
  // Simulate a manual payment appended by the client before the webhook.
  db.data.patients.p1.payments = [
    { id: 'manual1', amount: 200, type: 'payment', method: 'cash', date: ADMISSION },
  ];
  db.data.paymentLinks['plink_1'] = {
    id: 'plink_1',
    patientId: 'p1',
    amountPaise: 30000,
    status: 'created',
  };
  await ledger.applyRazorpayPayment(db, {
    patientId: 'p1',
    payment: {
      id: 'pay_TEST456',
      amountPaise: 30000,
      method: 'card',
      capturedAtMs: ist(2026, 8, 3, 10, 0),
      linkId: 'plink_1',
      eventId: 'payment_link.paid:pay_TEST456',
      verifiedBy: 'webhook',
    },
  });
  const ids = db.data.patients.p1.payments.map((p) => p.id);
  assert.deepEqual(ids.sort(), ['manual1', 'pay_TEST456'].sort());
  assert.equal(db.data.patients.p1.currentDueAmount, 900); // 1400 - 200 - 300
});
