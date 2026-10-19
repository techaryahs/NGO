import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../src/app.js';
import { config } from '../src/config/index.js';
import { pool, query } from '../src/db/index.js';
import { runMigrations } from '../src/db/migrate.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

describe.runIf(process.env.RUN_AUTH_PG_INTEGRATION === '1')('Firebase UID boundaries against disposable PostgreSQL', () => {
  const app = buildApp({ logger: false });
  const uid = 'a'.repeat(128);
  const send = (method: 'GET' | 'POST', url: string, payload?: Record<string, unknown>, identity = uid) => app.inject({
    method, url: `/api${url}`, headers: { authorization: `Bearer ${signedTestToken(identity, { email: `auth-${identity.length}@ngo.test` })}` }, payload,
  });
  beforeAll(async () => {
    const target = new URL(config.getEffectiveDatabaseUrl());
    if (process.env.NODE_ENV !== 'test' || target.hostname !== '127.0.0.1' || target.port !== '55439' || target.pathname !== '/ngo_audit_auth') throw new Error('Refusing non-disposable authentication test database');
    const db = (await query("SELECT current_database() AS db, inet_server_port() AS port, current_setting('server_version_num')::int AS version")).rows[0];
    expect(db).toMatchObject({ db: 'ngo_audit_auth', port: 55439 });
    expect(db.version).toBeGreaterThanOrEqual(160000); expect(db.version).toBeLessThan(170000);
    await runMigrations('up');
    installTestFirebaseKeys();
    // Reruns touch only this suite's known synthetic identities after safety guards.
    await query("UPDATE room_beds SET current_patient_id=NULL,current_stay_id=NULL,status='available' WHERE id='auth_uid_bed'");
    await query("DELETE FROM stays WHERE id='auth_uid_stay'");
    await query("DELETE FROM patients WHERE id='auth_uid_patient'");
    await query("DELETE FROM rooms WHERE id='auth_uid_room'");
    await query("DELETE FROM inventory_items WHERE id='auth_uid_inventory'");
    await query('DELETE FROM users WHERE id=ANY($1)', [['a'.repeat(65), uid]]);
  }, 30000);
  afterAll(async () => { await app.close(); await pool.end(); vi.restoreAllMocks(); });

  it('provisions valid 65-character and 128-character Firebase UIDs without truncation', async () => {
    for (const length of [65, 128]) {
      const identity = 'a'.repeat(length);
      const response = await send('GET', '/erp/inventory', undefined, identity);
      expect(response.statusCode).toBe(200);
      const row = (await query('SELECT id,role FROM users WHERE id=$1', [identity])).rows[0];
      expect(row).toEqual({ id: identity, role: 'volunteer' });
    }
  });

  it('retains a 128-character authenticated creator across patient, stay, and inventory writes', async () => {
    await query("UPDATE users SET role='staff' WHERE id=$1", [uid]);
    expect((await send('POST', '/patients', {
      id: 'auth_uid_patient', fullName: 'Synthetic UID audit', dateOfBirth: '1990-01-01', gender: 'Other',
      contactNumber: '000', emergencyContact: '000', emergencyContactName: 'Synthetic', medicalCondition: 'Synthetic', admissionDate: '2026-01-01',
    })).statusCode).toBe(201);
    expect((await send('POST', '/rooms', { id: 'auth_uid_room', roomNumber: 'auth_uid_room', roomType: 'general', beds: [{ id: 'auth_uid_bed', bedLabel: '1' }] })).statusCode).toBe(201);
    expect((await send('POST', '/stays', { id: 'auth_uid_stay', patientId: 'auth_uid_patient', roomId: 'auth_uid_room', bedId: 'auth_uid_bed' })).statusCode).toBe(201);
    expect((await send('POST', '/erp/inventory', { id: 'auth_uid_inventory', name: 'Synthetic UID inventory' })).statusCode).toBe(201);
    expect((await query("SELECT created_by FROM patients WHERE id='auth_uid_patient'")).rows[0].created_by).toBe(uid);
    expect((await query("SELECT created_by FROM stays WHERE id='auth_uid_stay'")).rows[0].created_by).toBe(uid);
    expect((await query("SELECT created_by,updated_by FROM inventory_items WHERE id='auth_uid_inventory'")).rows[0]).toEqual({ created_by: uid, updated_by: uid });
  });

  it('matches the supported Firebase UID length for every user/creator/updater column', async () => {
    const columns = (await query(`SELECT table_name,column_name,character_maximum_length AS width FROM information_schema.columns
      WHERE table_schema='public' AND ((table_name='users' AND column_name='id') OR column_name IN ('created_by','updated_by'))`)).rows;
    expect(columns).toHaveLength(7);
    for (const column of columns) expect(column.width, `${column.table_name}.${column.column_name}`).toBeGreaterThanOrEqual(128);
    expect((await send('GET', '/erp/inventory', undefined, 'a'.repeat(129))).statusCode).toBe(401);
  });
});
