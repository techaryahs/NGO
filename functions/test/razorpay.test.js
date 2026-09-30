'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const razorpay = require('../lib/razorpay');

const SECRET = 'test_webhook_secret';

function sign(body) {
  return crypto.createHmac('sha256', SECRET).update(body, 'utf8').digest('hex');
}

test('valid webhook signature is accepted', () => {
  const body = JSON.stringify({ event: 'payment_link.paid' });
  assert.doesNotThrow(() =>
    razorpay.verifyWebhookSignature(body, sign(body), SECRET),
  );
});

test('tampered webhook body is rejected', () => {
  const body = JSON.stringify({ event: 'payment_link.paid', payload: { amount: 100 } });
  const tampered = JSON.stringify({ event: 'payment_link.paid', payload: { amount: 1 } });
  assert.throws(() => razorpay.verifyWebhookSignature(tampered, sign(body), SECRET), /Invalid/);
});

test('missing signature is rejected', () => {
  assert.throws(
    () => razorpay.verifyWebhookSignature('{}', null, SECRET),
    /signature/i,
  );
});

test('missing secret is rejected', () => {
  assert.throws(
    () => razorpay.verifyWebhookSignature('{}', sign('{}'), ''),
    /secret/i,
  );
});

test('createPaymentLink validates its amount', async () => {
  await assert.rejects(
    () =>
      razorpay.createPaymentLink({
        amountPaise: 0,
        description: 'x',
        customerName: 'n',
        customerContact: '9999999999',
      }),
    /positive integer/,
  );
  await assert.rejects(
    () =>
      razorpay.createPaymentLink({
        amountPaise: -5,
        description: 'x',
        customerName: 'n',
        customerContact: '9999999999',
      }),
    /positive integer/,
  );
});
