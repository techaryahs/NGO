'use strict';

/**
 * Authentication and role helpers for the trusted backend.
 *
 * Roles are read from the RTDB `users/$uid/role` record. The database rules
 * enforce that users cannot modify their own role after account creation, so
 * the backend can rely on this value as server-side role state.
 */

const ALLOWED_PAYMENT_ROLES = new Set(['admin', 'staff']);

/**
 * Verifies a Firebase ID token and returns the uid.
 * @param {import('firebase-admin').app.App} adminApp
 * @param {string|null|undefined} idToken
 * @returns {Promise<string>}
 */
async function requireUser(adminApp, idToken) {
  if (!idToken || typeof idToken !== 'string') {
    const error = new Error('Authentication required.');
    error.code = 'unauthenticated';
    throw error;
  }
  let decoded;
  try {
    decoded = await adminApp.auth().verifyIdToken(idToken);
  } catch (err) {
    const error = new Error('Invalid or expired credentials.');
    error.code = 'unauthenticated';
    throw error;
  }
  return decoded.uid;
}

/**
 * Returns the user's role from RTDB (defaults to 'volunteer' when unset).
 */
async function getRole(adminApp, uid) {
  const snap = await adminApp.database().ref(`users/${uid}/role`).once('value');
  const role = snap.val();
  return typeof role === 'string' && role.length > 0 ? role : 'volunteer';
}

/**
 * Verifies the token and requires one of the given roles.
 * @returns {Promise<{uid: string, role: string}>}
 */
async function requireRole(adminApp, idToken, allowedRoles) {
  const uid = await requireUser(adminApp, idToken);
  const role = await getRole(adminApp, uid);
  const allowed = new Set(allowedRoles);
  if (!allowed.has(role)) {
    const error = new Error('You are not authorized to perform this action.');
    error.code = 'permission-denied';
    throw error;
  }
  return { uid, role };
}

/** Verifies the token and requires a role allowed to handle payments. */
async function requirePaymentRole(adminApp, idToken) {
  return requireRole(adminApp, idToken, Array.from(ALLOWED_PAYMENT_ROLES));
}

module.exports = { requireUser, getRole, requireRole, requirePaymentRole };
