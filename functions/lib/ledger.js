'use strict';

const billing = require('./billing');
const billingUpdate = require('./billing-update');

/**
 * Idempotent, server-authoritative payment ledger writer.
 *
 * /payments is the canonical ledger. /paymentHistory and
 * /patients/$patientId/payments are derived mirrors updated in the same
 * atomic multi-path write. Duplicate webhooks, re-polled verification calls
 * and repeated event delivery all converge to the same database state.
 */

function razorpayLedgerKey(paymentId) {
  // Razorpay ids are alphanumeric with underscores and are safe RTDB keys.
  return `razorpay_${paymentId}`;
}

/**
 * Records a verified Razorpay payment and recalculates the patient billing.
 *
 * @param {import('firebase-admin').database.Database} db
 * @param {object} params
 * @param {string} params.patientId
 * @param {object} params.payment
 *   { id, amountPaise, method, capturedAtMs, linkId, eventId, verifiedBy }
 * @returns {Promise<{applied: boolean, id: string}>}
 */
async function applyRazorpayPayment(db, { patientId, payment }) {
  const ledgerId = razorpayLedgerKey(payment.id);

  // Idempotency check: a verified payment is never applied twice.
  const existingSnap = await db.ref(`payments/${ledgerId}`).once('value');
  const existing = existingSnap.val();
  if (
    existing &&
    typeof existing === 'object' &&
    existing.status === 'paid' &&
    existing.source === 'razorpay'
  ) {
    if (existing.patientId !== patientId || existing.transactionId !== payment.id) {
      throw new Error('Razorpay payment id is already linked to another record.');
    }
    return { applied: false, id: ledgerId };
  }

  const patientSnap = await db
    .ref(`patients/${patientId}`)
    .once('value');
  const patient = patientSnap.val();
  if (!patient || typeof patient !== 'object') {
    throw new Error(`Patient ${patientId} not found.`);
  }

  const amountRs = Math.round(Number(payment.amountPaise)) / 100;
  if (!Number.isInteger(Number(payment.amountPaise)) || amountRs <= 0) {
    throw new Error('Invalid captured payment amount.');
  }
  const capturedAtMs = Number(payment.capturedAtMs) || Date.now();
  const now = Date.now();

  const record = {
    id: payment.id,
    patientId,
    patientName: String(patient.fullName || ''),
    type: 'payment',
    amount: amountRs,
    totalAmount: amountRs,
    paidAmount: amountRs,
    pendingAmount: 0,
    paymentStatus: 'Paid',
    method: 'online (razorpay)',
    date: capturedAtMs,
    receiptNumber: `RZP-${payment.id}`,
    transactionId: payment.id,
    cycleId: billing.currentCycle(patient),
    notes: `Razorpay payment link ${payment.linkId || ''}`.trim(),
    source: 'razorpay',
    status: 'paid',
    verifiedBy: payment.verifiedBy || 'webhook',
    eventId: payment.eventId || null,
    timestamp: now,
    createdAt: now,
  };

  // Append to the derived patient mirror inside a transaction so concurrent
  // webhooks and manual payments cannot lose each other's updates.
  await db
    .ref(`patients/${patientId}/payments`)
    .transaction((current) => {
      const list = Array.isArray(current) ? current :
        current && typeof current === 'object' ? Object.values(current) : [];
      if (list.some((p) => p && p.id === payment.id)) return;
      list.push(record);
      return list;
    }, undefined, false);

  // Recompute billing with the payment included, then commit ledger records,
  // mirrors, link status and the event guard in one atomic update.
  const { updates } = await billingUpdate.buildBillingUpdates(db, patientId);
  Object.assign(updates, {
    [`payments/${ledgerId}`]: record,
    [`paymentHistory/${ledgerId}`]: record,
    [`paymentLinks/${payment.linkId}/status`]: 'paid',
    [`paymentLinks/${payment.linkId}/paymentId`]: payment.id,
    [`paymentLinks/${payment.linkId}/updatedAt`]: now,
    [`razorpayEvents/${payment.eventId}`]: { processedAt: now, paymentId: payment.id },
  });
  await db.ref().update(updates);
  return { applied: true, id: ledgerId };
}

module.exports = { applyRazorpayPayment, razorpayLedgerKey };
