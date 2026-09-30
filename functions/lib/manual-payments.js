'use strict';

const billing = require('./billing');
const billingUpdate = require('./billing-update');
const crypto = require('crypto');

/**
 * Server-authoritative manual payment/refund recording.
 *
 * Used by the client because database rules reject all client-side payment
 * writes. Amounts are
 * validated server-side; refunds are bounded by the computed refundable
 * excess.
 */

async function recordManualPayment(db, { patientId, payment, refund = false, nowMs = null }) {
  const now = nowMs === null ? Date.now() : nowMs;
  const patientSnap = await db.ref(`patients/${patientId}`).once('value');
  const patient = patientSnap.val();
  if (!patient || typeof patient !== 'object') {
    throw new Error(`Patient ${patientId} not found.`);
  }

  const amount = Number(payment.amount);
  if (!Number.isFinite(amount) || amount === 0) {
    throw new Error('Enter a positive payment amount.');
  }
  const isRefund = refund || String(payment.type || '') === 'refund' || amount < 0;
  const signedAmount = isRefund ? -Math.abs(amount) : Math.abs(amount);

  if (payment.id == null) throw new Error('Payment request id is required for safe retries.');
  const requestId = String(payment.id);
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(requestId)) {
    throw new Error('Invalid payment request id.');
  }
  const id = `manual_${crypto.createHash('sha256').update(`${patientId}:${requestId}`).digest('hex')}`;
  const existing = (await db.ref(`payments/${id}`).once('value')).val();
  if (existing) {
    if (existing.patientId !== patientId || existing.amount !== signedAmount ||
        existing.type !== (isRefund ? 'refund' : 'payment')) {
      throw new Error('Payment request id was already used for different details.');
    }
    return { applied: false, id };
  }
  const patientPayments = Array.isArray(patient.payments) ? patient.payments :
    patient.payments && typeof patient.payments === 'object' ? Object.values(patient.payments) : [];
  const alreadyInPatient = patientPayments.some((row) => row && row.id === id);
  if (isRefund && !alreadyInPatient) {
    const computed = await billingUpdate.buildBillingUpdates(db, patientId);
    const cycleId = String(payment.cycleId || billing.currentCycle(patient));
    const balance = computed.balances.find((b) => b.id === cycleId);
    const refundDue = balance ? balance.refundDue : 0;
    if (Math.abs(signedAmount) > refundDue + 0.005) {
      throw new Error('Refund exceeds the remaining excess payment.');
    }
  }
  const record = {
    id,
    patientId,
    patientName: String(patient.fullName || ''),
    type: isRefund ? 'refund' : 'payment',
    amount: signedAmount,
    totalAmount: Math.abs(signedAmount),
    paidAmount: Math.abs(signedAmount),
    pendingAmount: 0,
    paymentStatus: 'Paid',
    method: String(payment.method || 'cash'),
    date: Number(payment.date) || now,
    receiptNumber: payment.receiptNumber || null,
    checkNumber: payment.checkNumber || null,
    bankName: payment.bankName || null,
    transactionId: payment.transactionId || null,
    cycleId: String(payment.cycleId || billing.currentCycle(patient)),
    notes: payment.notes || null,
    source: 'manual',
    status: 'paid',
    verifiedBy: 'server',
    timestamp: now,
    createdAt: now,
  };

  await db
    .ref(`patients/${patientId}/payments`)
    .transaction((current) => {
      const list = Array.isArray(current) ? current :
        current && typeof current === 'object' ? Object.values(current) : [];
      if (list.some((p) => p && p.id === id)) return;
      list.push(record);
      return list;
    }, undefined, false);

  const updates = (await billingUpdate.buildBillingUpdates(db, patientId)).updates;
  Object.assign(updates, {
    [`payments/${id}`]: record,
    [`paymentHistory/${id}`]: record,
  });
  await db.ref().update(updates);
  return { applied: true, id };
}

/** Admin-only correction of a manually entered payment. A void retains the
 * ledger and history record, while removing its financial effect. */
async function amendManualPayment(db, { patientId, paymentId, embeddedPaymentId = null,
  changes = null, voidPayment = false, uid, nowMs = null }) {
  if (!/^[A-Za-z0-9_-]+$/.test(patientId) || !/^[A-Za-z0-9_-]+$/.test(paymentId)) {
    throw new Error('Invalid payment reference.');
  }
  const original = (await db.ref(`payments/${paymentId}`).once('value')).val();
  if (!original || original.patientId !== patientId) throw new Error('Payment not found.');
  if (original.source === 'razorpay' || original.status === 'void' ||
      String(original.method || '').toLowerCase().includes('online') ||
      String(original.transactionId || '').startsWith('pay_')) {
    throw new Error('Only active manual payments can be corrected.');
  }
  const isRefund = original.type === 'refund' || Number(original.amount) < 0;
  const now = nowMs === null ? Date.now() : nowMs;
  const next = { ...original };
  if (!voidPayment) {
    if (!changes || typeof changes !== 'object' || Array.isArray(changes)) {
      throw new Error('Payment changes are required.');
    }
    if (changes.amount !== undefined) {
      const value = Number(changes.amount);
      if (!Number.isFinite(value) || value <= 0) throw new Error('Invalid payment amount.');
      next.amount = isRefund ? -value : value;
      next.totalAmount = value;
      next.paidAmount = value;
    }
    if (changes.date !== undefined) {
      if (!Number.isSafeInteger(changes.date) || changes.date <= 0) {
        throw new Error('Invalid payment date.');
      }
      next.date = changes.date;
    }
    for (const field of ['transactionId', 'receiptNumber', 'cycleId']) {
      if (changes[field] !== undefined) {
        if (typeof changes[field] !== 'string' || changes[field].length > 128) {
          throw new Error(`Invalid ${field}.`);
        }
        next[field] = changes[field].trim();
      }
    }
  }
  if (isRefund && !voidPayment && -next.amount > -Number(original.amount)) {
    const before = await billingUpdate.buildBillingUpdates(db, patientId);
    const balance = before.balances.find((row) => row.id === next.cycleId);
    if (-next.amount > -Number(original.amount) + (balance ? balance.refundDue : 0) + 0.005) {
      throw new Error('Refund exceeds the remaining excess payment.');
    }
  }
  let found = false;
  await db.ref(`patients/${patientId}/payments`).transaction((current) => {
    const list = Array.isArray(current) ? [...current] :
      current && typeof current === 'object' ? Object.values(current) : [];
    const index = list.findIndex((row) => row &&
      (row.id === original.id || row.id === paymentId ||
        (embeddedPaymentId && row.id === embeddedPaymentId)));
    if (index < 0) return;
    found = true;
    if (voidPayment) list.splice(index, 1);
    else list[index] = next;
    return list;
  }, undefined, false);
  if (!found && !voidPayment) throw new Error('Patient payment mirror is missing.');
  const updates = (await billingUpdate.buildBillingUpdates(db, patientId)).updates;
  const ledgerRecord = voidPayment
    ? { ...original, status: 'void', voidedAt: now, voidedBy: uid }
    : { ...next, amendedAt: now, amendedBy: uid };
  updates[`payments/${paymentId}`] = ledgerRecord;
  updates[`paymentHistory/${paymentId}`] = ledgerRecord;
  await db.ref().update(updates);
  return { id: paymentId, status: voidPayment ? 'void' : 'paid' };
}

module.exports = { recordManualPayment, amendManualPayment };
