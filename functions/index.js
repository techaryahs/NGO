'use strict';

const functions = require('firebase-functions');
const admin = require('firebase-admin');

const auth = require('./lib/auth');
const razorpay = require('./lib/razorpay');
const billingUpdate = require('./lib/billing-update');
const ledger = require('./lib/ledger');
const manualPayments = require('./lib/manual-payments');

admin.initializeApp();

/** Writes a JSON response. */
function json(res, statusCode, payload) {
  res.status(statusCode);
  res.json(payload);
}

function errorResponse(res, err) {
  const statusCode =
    err && err.code === 'unauthenticated'
      ? 401
      : err && err.code === 'permission-denied'
        ? 403
        : 400;
  functions.logger.error(err);
  json(res, statusCode, { ok: false, error: String(err.message || err) });
}

/** Shared CORS headers (the desktop client has no browser origin). */
function allowCors(res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
}

/**
 * POST /createPaymentLink
 * Body: { idToken, patientId, amountInPaise?, description? }
 * Creates a Razorpay payment link. The amount is validated against the
 * server-computed balance — the client can never choose an arbitrary amount.
 */
exports.createPaymentLink = functions.https.onRequest(async (req, res) => {
  allowCors(res);
  if (req.method === 'OPTIONS') return json(res, 204, {});
  if (req.method !== 'POST') {
    return json(res, 405, { ok: false, error: 'Method not allowed' });
  }
  try {
    const body = req.body || {};
    const { uid } = await auth.requirePaymentRole(admin, body.idToken);
    const patientId = String(body.patientId || '');
    if (!/^[A-Za-z0-9_-]+$/.test(patientId)) throw new Error('Invalid patientId.');

    const patientSnap = await admin
      .database()
      .ref(`patients/${patientId}`)
      .once('value');
    const patient = patientSnap.val();
    if (!patient || typeof patient !== 'object') {
      throw new Error('Patient not found.');
    }
    if (String(patient.status || '').toLowerCase() === 'discharged') {
      throw new Error('Discharged patients cannot create payment links.');
    }

    const computed = await billingUpdate.buildBillingUpdates(
      admin.database(),
      patientId,
    );
    const due = computed.current ? computed.current.due : 0;
    const duePaise = Math.round(due * 100);
    if (duePaise <= 0) {
      throw new Error('Nothing is due for this patient.');
    }
    const requested = body.amountInPaise;
    let amountPaise = duePaise;
    if (requested !== undefined && requested !== null) {
      const value = Number(requested);
      if (!Number.isInteger(value) || value <= 0) {
        throw new Error('Invalid amount.');
      }
      if (value > duePaise) {
        throw new Error(
          `Amount exceeds the outstanding balance (₹${due.toFixed(2)}).`,
        );
      }
      amountPaise = value;
    }

    const link = await razorpay.createPaymentLink({
      amountPaise,
      description: body.description || `Payment — ${patient.fullName || patientId}`,
      customerName: patient.fullName || '',
      customerContact: String(patient.contactNumber || ''),
      notes: { patientId, app: 'ngo-management-system' },
    });

    const now = Date.now();
    await admin.database().ref(`paymentLinks/${link.id}`).set({
      id: link.id,
      patientId,
      amountPaise,
      status: 'created',
      createdBy: uid,
      createdAt: now,
      updatedAt: now,
    });
    return json(res, 200, {
      ok: true,
      linkId: link.id,
      url: link.shortUrl,
      amountPaise,
    });
  } catch (err) {
    return errorResponse(res, err);
  }
});

/**
 * POST /checkPaymentLink
 * Body: { idToken, linkId }
 * Server-side status check used by the client polling loop. When the link is
 * paid, the payment is recorded in the ledger idempotently and the patient's
 * billing is recalculated on the server.
 */
exports.checkPaymentLink = functions.https.onRequest(async (req, res) => {
  allowCors(res);
  if (req.method === 'OPTIONS') return json(res, 204, {});
  if (req.method !== 'POST') {
    return json(res, 405, { ok: false, error: 'Method not allowed' });
  }
  try {
    const body = req.body || {};
    await auth.requirePaymentRole(admin, body.idToken);
    const linkId = String(body.linkId || '');
    if (!/^plink_[A-Za-z0-9]+$/.test(linkId)) throw new Error('Invalid linkId.');

    const linkSnap = await admin
      .database()
      .ref(`paymentLinks/${linkId}`)
      .once('value');
    const link = linkSnap.val();
    if (!link || typeof link !== 'object') {
      throw new Error('Payment link not found.');
    }
    if (link.status === 'paid' && link.paymentId) {
      const recorded = (await admin.database()
        .ref(`payments/${ledger.razorpayLedgerKey(link.paymentId)}`)
        .once('value')).val();
      if (recorded && recorded.source === 'razorpay' && recorded.status === 'paid') {
        return json(res, 200, {
          ok: true,
          status: 'paid',
          paymentId: link.paymentId,
          method: recorded.method,
          paidAt: recorded.date,
          amountPaid: Math.round(Number(recorded.amount) * 100),
        });
      }
    }

    const status = await razorpay.getPaymentLinkStatus(linkId);
    if (status.status === 'paid' && status.payment && status.payment.paymentId) {
      const paid = status.payment;
      const verified = await razorpay.getPayment(paid.paymentId);
      if (verified.status !== 'captured' ||
          Number(verified.amount) !== Number(link.amountPaise) ||
          Number(paid.amountPaid) !== Number(link.amountPaise)) {
        throw new Error('Captured payment amount does not match the payment link.');
      }
      await ledger.applyRazorpayPayment(admin.database(), {
        patientId: link.patientId,
        payment: {
          id: paid.paymentId,
          amountPaise: verified.amount,
          method: verified.method,
          capturedAtMs: verified.capturedAt || paid.paidAt || Date.now(),
          linkId,
          eventId: `check:${paid.paymentId}`,
          verifiedBy: 'server_check',
        },
      });
      return json(res, 200, {
        ok: true,
        status: 'paid',
        paymentId: paid.paymentId,
        method: paid.method,
        paidAt: paid.paidAt,
        amountPaid: paid.amountPaid,
      });
    }
    return json(res, 200, {
      ok: true,
      status: status.status === 'paid' ? 'pending_reconciliation' : status.status,
    });
  } catch (err) {
    return errorResponse(res, err);
  }
});

/**
 * POST /razorpayWebhook
 * Public endpoint. Every mutation requires a valid X-Razorpay-Signature
 * (HMAC-SHA256 of the raw body with the webhook secret). Updates are
 * idempotent per event and per Razorpay payment id.
 */
exports.razorpayWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    return json(res, 405, { ok: false, error: 'Method not allowed' });
  }
  const rawBody = req.rawBody;
  if (!Buffer.isBuffer(rawBody)) {
    return json(res, 400, { ok: false, error: 'Raw webhook body required.' });
  }
  const signature =
    req.get('x-razorpay-signature') || req.get('X-Razorpay-Signature');
  try {
    razorpay.verifyWebhookSignature(
      rawBody,
      signature,
      process.env.RAZORPAY_WEBHOOK_SECRET || '',
    );
  } catch (err) {
    functions.logger.warn(`Webhook signature rejected: ${err.message}`);
    return json(res, 400, { ok: false, error: 'Invalid signature.' });
  }

  let event;
  try {
    event = JSON.parse(rawBody);
  } catch (err) {
    return json(res, 400, { ok: false, error: 'Invalid webhook body.' });
  }

  const eventType = String(event.event || '');
  if (eventType !== 'payment_link.paid') {
    // Acknowledge unrelated events so Razorpay does not retry them.
    return json(res, 200, { ok: true, ignored: true, event: eventType });
  }

  try {
    const payload = event.payload || {};
    const payment =
      payload.payment && payload.payment.entity ? payload.payment.entity : null;
    if (!payment || !payment.id) {
      throw new Error('Paid webhook has no payment entity.');
    }

    const linkId =
      (payload.payment_link &&
        payload.payment_link.entity &&
        payload.payment_link.entity.id) ||
      (payment.notes && payment.notes.payment_link_id) ||
      null;
    if (!linkId || !/^plink_[A-Za-z0-9]+$/.test(linkId)) {
      throw new Error('Webhook payment has no payment link reference.');
    }
    const linkSnap = await admin
      .database()
      .ref(`paymentLinks/${linkId}`)
      .once('value');
    const link = linkSnap.val();
    if (!link || typeof link !== 'object') {
      throw new Error(`Unknown payment link ${linkId}.`);
    }
    const expectedAmountPaise = Number(link.amountPaise);
    const paidAmountPaise = Number(payment.amount);
    if (!Number.isInteger(paidAmountPaise) || paidAmountPaise <= 0) {
      throw new Error('Invalid webhook amount.');
    }
    if (paidAmountPaise !== expectedAmountPaise) {
      throw new Error(
        `Webhook amount ${paidAmountPaise} does not match link amount ${expectedAmountPaise}.`,
      );
    }
    const status = String(payment.status || '');
    if (status !== 'captured') {
      return json(res, 200, { ok: true, ignored: true, reason: `status-${status}` });
    }
    const verified = await razorpay.getPayment(String(payment.id));
    if (verified.status !== 'captured' || Number(verified.amount) !== paidAmountPaise) {
      throw new Error('Razorpay API did not confirm the captured payment.');
    }

    await ledger.applyRazorpayPayment(admin.database(), {
      patientId: link.patientId,
      payment: {
        id: String(payment.id),
        amountPaise: paidAmountPaise,
        method: verified.method,
        capturedAtMs: verified.capturedAt || Date.now(),
        linkId,
        eventId: `${eventType}:${payment.id}`,
        verifiedBy: 'webhook',
      },
    });
    return json(res, 200, { ok: true, applied: true });
  } catch (err) {
    functions.logger.error(`Webhook processing failed: ${err.message}`);
    return json(res, 400, { ok: false, error: String(err.message || err) });
  }
});

/**
 * POST /recordManualPayment
 * Body: { idToken, patientId, payment: { amount, method, date, ... }, refund? }
 * Server-authoritative manual payment/refund. Database rules always reject
 * direct client ledger writes.
 */
exports.recordManualPayment = functions.https.onRequest(async (req, res) => {
  allowCors(res);
  if (req.method === 'OPTIONS') return json(res, 204, {});
  if (req.method !== 'POST') {
    return json(res, 405, { ok: false, error: 'Method not allowed' });
  }
  try {
    const body = req.body || {};
    await auth.requirePaymentRole(admin, body.idToken);
    const patientId = String(body.patientId || '');
    if (!/^[A-Za-z0-9_-]+$/.test(patientId)) throw new Error('Invalid patientId.');
    const payment = body.payment;
    if (!payment || typeof payment !== 'object') {
      throw new Error('Missing payment details.');
    }
    const result = await manualPayments.recordManualPayment(admin.database(), {
      patientId,
      payment,
      refund: body.refund === true,
    });
    return json(res, 200, { ok: true, id: result.id });
  } catch (err) {
    return errorResponse(res, err);
  }
});

/** POST /amendManualPayment. Only an administrator may correct or void a
 * manually entered payment; captured Razorpay payments are immutable. */
exports.amendManualPayment = functions.https.onRequest(async (req, res) => {
  allowCors(res);
  if (req.method === 'OPTIONS') return json(res, 204, {});
  if (req.method !== 'POST') return json(res, 405, { ok: false, error: 'Method not allowed' });
  try {
    const body = req.body || {};
    const { uid } = await auth.requireRole(admin, body.idToken, ['admin']);
    const result = await manualPayments.amendManualPayment(admin.database(), {
      patientId: String(body.patientId || ''),
      paymentId: String(body.paymentId || ''),
      embeddedPaymentId: body.embeddedPaymentId == null ? null : String(body.embeddedPaymentId),
      changes: body.changes,
      voidPayment: body.voidPayment === true,
      uid,
    });
    return json(res, 200, { ok: true, ...result });
  } catch (err) {
    return errorResponse(res, err);
  }
});

/**
 * POST /recalculateBilling
 * Body: { idToken, patientId }
 * Server-side billing recalculation. The client uses this endpoint when the
 * backend is deployed.
 */
exports.recalculateBilling = functions.https.onRequest(async (req, res) => {
  allowCors(res);
  if (req.method === 'OPTIONS') return json(res, 204, {});
  if (req.method !== 'POST') {
    return json(res, 405, { ok: false, error: 'Method not allowed' });
  }
  try {
    const body = req.body || {};
    await auth.requirePaymentRole(admin, body.idToken);
    const patientId = String(body.patientId || '');
    if (!/^[A-Za-z0-9_-]+$/.test(patientId)) throw new Error('Invalid patientId.');
    const { updates } = await billingUpdate.buildBillingUpdates(
      admin.database(),
      patientId,
    );
    await admin.database().ref().update(updates);
    return json(res, 200, {
      ok: true,
      balances: updates[`patients/${patientId}/admissionBalances`],
      due: updates[`patients/${patientId}/currentDueAmount`],
    });
  } catch (err) {
    return errorResponse(res, err);
  }
});

// Attendance writes acknowledge immediately on the client. The durable queue
// keeps billing consistent even when that client closes before its short
// debounce timer fires. The worker coalesces all marks for one patient.
async function queueBilling(patientId) {
  if (!/^[A-Za-z0-9_-]+$/.test(patientId)) return;
  await admin.database().ref(`billingQueue/${patientId}`).set(Date.now());
}

exports.queuePatientAttendanceBilling = functions.database
  .ref('/attendance/daily/{date}/{patientId}')
  .onWrite(async (_change, context) => queueBilling(context.params.patientId));

exports.queueAttendantAttendanceBilling = functions.database
  .ref('/attendant_attendance/daily/{date}/{patientId}/{attendantId}')
  .onWrite(async (_change, context) => queueBilling(context.params.patientId));

exports.processBillingQueue = functions.runWith({ timeoutSeconds: 540 })
  .pubsub.schedule('every 1 minutes').onRun(async () => {
    const snapshot = await admin.database().ref('billingQueue')
      .orderByKey().limitToFirst(100).once('value');
    const queued = snapshot.val() || {};
    for (const [patientId, queuedAt] of Object.entries(queued)) {
      try {
        const { updates } = await billingUpdate.buildBillingUpdates(
          admin.database(), patientId,
        );
        await admin.database().ref().update(updates);
        await admin.database().ref(`billingQueue/${patientId}`)
          .transaction((current) => current === queuedAt ? null : undefined,
            undefined, false);
      } catch (err) {
        if (String(err.message || '').includes('not found')) {
          await admin.database().ref(`billingQueue/${patientId}`)
            .transaction((current) => current === queuedAt ? null : undefined,
              undefined, false);
          continue;
        }
        // Keep this patient queued for a later retry after transient errors.
        functions.logger.error(`Billing queue failed for ${patientId}: ${err.message}`);
      }
    }
    return null;
  });
