'use strict';

/**
 * Server-side Razorpay client. These functions run ONLY inside the trusted
 * backend. The key secret must never be present in the Flutter client.
 */

const crypto = require('crypto');

const BASE_URL = 'https://api.razorpay.com/v1';

function config() {
  const keyId = process.env.RAZORPAY_KEY_ID || '';
  const keySecret = process.env.RAZORPAY_KEY_SECRET || '';
  if (!keyId || !keySecret) {
    throw new Error(
      'Razorpay is not configured on this backend. Set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET.',
    );
  }
  return { keyId, keySecret };
}

function authHeaders() {
  const { keyId, keySecret } = config();
  return {
    Authorization: `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString('base64')}`,
    'Content-Type': 'application/json',
  };
}

/**
 * Creates a payment link.
 * @param {object} params { amountPaise, description, customerName, customerContact, notes }
 * @returns {Promise<{id: string, shortUrl: string, amountPaise: number}>}
 */
async function createPaymentLink({
  amountPaise,
  description,
  customerName,
  customerContact,
  notes = {},
}) {
  if (!Number.isInteger(amountPaise) || amountPaise <= 0) {
    throw new Error('Payment link amount must be a positive integer (paise).');
  }
  const body = {
    amount: amountPaise,
    currency: 'INR',
    description: String(description || '').slice(0, 250),
    customer: {
      name: String(customerName || '').slice(0, 100),
      contact: String(customerContact || ''),
    },
    notify: { sms: true },
    reminder_enable: false,
    accept_partial: false,
    notes: { ...notes },
  };
  const response = await fetch(`${BASE_URL}/payment_links/`, {
    method: 'POST',
    headers: authHeaders(),
    body: JSON.stringify(body),
  });
  const data = await response.json();
  if (response.status !== 200 && response.status !== 201) {
    throw new Error(
      (data && data.error && data.error.description) ||
        `Razorpay create link failed (${response.status})`,
    );
  }
  if (!data.id || !data.short_url) {
    throw new Error('Razorpay returned an unexpected link response.');
  }
  return { id: data.id, shortUrl: data.short_url, amountPaise: data.amount };
}

/**
 * Fetches the authoritative state of a payment link and, when paid, the
 * payment details. Used by the client-polling verification endpoint.
 */
async function getPaymentLinkStatus(linkId) {
  const response = await fetch(`${BASE_URL}/payment_links/${linkId}`, {
    method: 'GET',
    headers: authHeaders(),
  });
  if (response.status !== 200) {
    throw new Error(`Razorpay link lookup failed (${response.status})`);
  }
  const data = await response.json();
  const status = String(data.status || 'created');
  const payments = Array.isArray(data.payments) ? data.payments : [];
  let payment = null;
  if (payments.length > 0) {
    const last = payments[payments.length - 1];
    if (last.status === 'captured' && last.plink_id === linkId) payment = {
      paymentId: last.payment_id || null,
      method: last.method || null,
      amountPaid: last.amount || null,
      paidAt:
        last.created_at !== undefined && last.created_at !== null
          ? last.created_at * 1000
          : null,
    };
  }
  return { linkId, status, payment };
}

/**
 * Fetches a single payment's details. Used to validate webhook payloads
 * against the Razorpay API rather than trusting the webhook body.
 */
async function getPayment(paymentId) {
  const response = await fetch(`${BASE_URL}/payments/${paymentId}`, {
    method: 'GET',
    headers: authHeaders(),
  });
  if (response.status !== 200) {
    throw new Error(`Razorpay payment lookup failed (${response.status})`);
  }
  const data = await response.json();
  return {
    id: data.id,
    status: data.status,
    amount: data.amount,
    method: data.method,
    capturedAt: data.captured_at ? data.captured_at * 1000 : null,
    notes: data.notes || {},
  };
}

/**
 * Verifies the X-Razorpay-Signature header (HMAC-SHA256 of the raw body).
 * Throws when the signature is missing or invalid.
 */
function verifyWebhookSignature(rawBody, signatureHeader, secret) {
  if (!secret) {
    throw new Error(
      'Razorpay webhook secret is not configured. Set RAZORPAY_WEBHOOK_SECRET.',
    );
  }
  if (!signatureHeader) {
    throw new Error('Missing X-Razorpay-Signature header.');
  }
  const expected = crypto
    .createHmac('sha256', secret)
    .update(rawBody, 'utf8')
    .digest('hex');
  const signatureOk = crypto.timingSafeEqual(
    Buffer.from(expected, 'utf8'),
    Buffer.from(String(signatureHeader), 'utf8'),
  );
  if (!signatureOk) {
    throw new Error('Invalid Razorpay webhook signature.');
  }
}

module.exports = {
  createPaymentLink,
  getPaymentLinkStatus,
  getPayment,
  verifyWebhookSignature,
};
