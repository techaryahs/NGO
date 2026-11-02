import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../src/app.js';
import { getClient, pool, query } from '../src/db/index.js';
import { runMigrations } from '../src/db/migrate.js';
import { derivePlacement } from '../src/routes/patients.js';
import { convergeAdmissionCycle, repairAdmissions } from '../src/services/admission_repair.js';
import { readFile } from 'node:fs/promises';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

describe.skipIf(process.env.RUN_PG_INTEGRATION !== '1')('placement edits on live PostgreSQL', () => {
  const app = buildApp({ logger: false });
  const send = (method: any, url: string, payload?: any) => app.inject({ method, url: `/api${url}`,
    headers: { authorization: `Bearer ${signedTestToken()}` }, payload });
  const stored = async () => (await query("SELECT * FROM patients WHERE id='placement-p'")).rows[0];
  const loaded = async () => {
    const response = await send('GET', '/patients/placement-p');
    expect(response.statusCode, response.body).toBe(200);
    return response.json();
  };
  // Echo every GET field accepted by the edit endpoint. Financial echoes are
  // deliberately forbidden by the existing financial guard, independently of placement.
  const editPayload = (snapshot: Record<string, any>) => Object.fromEntries(Object.entries(snapshot).filter(([key]) =>
    !['totalPaidAmount', 'currentDueAmount', 'refundDueAmount', 'totalRefundDueAmount', 'totalRefundedAmount',
      'admissionBalances', 'stayBillingUpdates', 'advanceBilledAmount', 'attendanceCharges', 'billingAmountOverride',
      'totalPresentDays', 'totalAbsentDays'].includes(key)));
  beforeAll(async () => {
    if (process.env.NODE_ENV !== 'test' || process.env.POSTGRES_HOST !== '127.0.0.1' ||
        process.env.POSTGRES_PORT !== '55439' || process.env.POSTGRES_DB !== 'ngo_audit_workflows') {
      throw new Error('Refusing non-disposable placement database');
    }
    const identity = (await query("SELECT current_database() AS db,inet_server_port() AS port,current_setting('server_version_num')::int AS version")).rows[0];
    expect(identity).toMatchObject({ db: 'ngo_audit_workflows', port: 55439 });
    expect(identity.version).toBeGreaterThanOrEqual(160000);
    expect(identity.version).toBeLessThan(170000);
    await runMigrations();
  }, 30000);
  beforeEach(async () => {
    installTestFirebaseKeys();
    await query('TRUNCATE users,rooms,patients CASCADE');
    await query("INSERT INTO users(id,email,name,role) VALUES('test-uid-admin','admin@ngo.test','Synthetic Admin','admin')");
    const created = await send('POST', '/patients', { id: 'placement-p', fullName: 'Synthetic Placement',
      dateOfBirth: '1990-01-01', gender: 'Other', contactNumber: '000', emergencyContact: '000',
      emergencyContactName: 'Synthetic', medicalCondition: 'Synthetic', registrationDate: '2026-10-01',
      admissionDate: '2026-10-01', attendants: [] });
    expect(created.statusCode, created.body).toBe(201);
  });
  afterAll(async () => { await app.close(); await pool.end(); });
  async function lobby(stale = true) {
    const created = await send('POST', '/stays', { id: 'placement-s', patientId: 'placement-p',
      roomId: 'lobby:2D Lobby 1', roomNumber: '2D Lobby 1', roomType: 'lobby', durationDays: 7,
      admissionDate: '2026-10-01' });
    expect(created.statusCode, created.body).toBe(201);
    if (stale) await query("UPDATE patients SET floor=NULL WHERE id='placement-p'");
  }
  async function room(id: string, floor = 1) {
    const created = await send('POST', '/rooms', { id, roomNumber: id, roomType: 'general', floor,
      beds: [{ id: `${id}-bed`, bedLabel: `${id} bed` }] });
    expect(created.statusCode, created.body).toBe(201);
  }
  async function roomPlacement() {
    await room('placement-room');
    const created = await send('POST', '/stays', { id: 'placement-s', patientId: 'placement-p',
      roomId: 'placement-room', bedId: 'placement-room-bed', durationDays: 7, admissionDate: '2026-10-01' });
    expect(created.statusCode, created.body).toBe(201);
  }
  async function coherent() {
    const row = await stored();
    const stays = (await query(`SELECT s.*,r.floor AS room_floor FROM stays s LEFT JOIN rooms r ON r.id=s.room_id
      WHERE s.patient_id='placement-p' AND s.status='active' ORDER BY s.created_at,s.id`)).rows;
    expect({ roomId: row.room_id, roomNumber: row.room_number, floor: row.floor, lobby: row.lobby,
      bedIds: row.bed_ids, bedLabels: row.bed_labels }).toEqual(derivePlacement(row, stays));
  }
  it('T1 incident: unrelated lobby edit heals the stale row copy', async () => {
    await lobby();
    const snapshot = await loaded();
    expect(snapshot.floor).toBe(2);
    expect((await stored()).floor).toBeNull();
    const edited = await send('PUT', '/patients/placement-p', { ...editPayload(snapshot), notes: 'T1' });
    expect(edited.statusCode, edited.body).toBe(200);
    expect((await stored()).floor).toBe(2);
    await coherent();
  });
  it('T2 guard: real floor and room changes return 409 with no writes (baseline guard)', async () => {
    await lobby();
    const payload = editPayload(await loaded());
    const before = await stored();
    const stays = (await query("SELECT * FROM stays WHERE patient_id='placement-p' ORDER BY id")).rows;
    for (const change of [{ floor: 1 }, { roomId: 'different-room' }]) {
      const result = await send('PUT', '/patients/placement-p', { ...payload, ...change });
      expect(result.statusCode, result.body).toBe(409);
      expect(result.json().message).toBe('Change active assignments through the stay lifecycle');
      expect(await stored()).toEqual(before);
      expect((await query("SELECT * FROM stays WHERE patient_id='placement-p' ORDER BY id")).rows).toEqual(stays);
    }
  });
  it('T3 room: unrelated edit heals stale beds from active stays', async () => {
    await roomPlacement();
    await query("UPDATE patients SET bed_ids='[\"stale-bed\"]',bed_labels='[\"stale label\"]' WHERE id='placement-p'");
    const result = await send('PUT', '/patients/placement-p', { ...editPayload(await loaded()), notes: 'T3' });
    expect(result.statusCode, result.body).toBe(200);
    await coherent();
  });
  it('T4 discharged: plain edit preserves placement (baseline behavior)', async () => {
    await query("UPDATE patients SET status='discharged',discharge_date='2026-10-02' WHERE id='placement-p'");
    const before = await stored();
    const result = await send('PUT', '/patients/placement-p', { notes: 'T4' });
    expect(result.statusCode, result.body).toBe(200);
    const after = await stored();
    for (const key of ['status', 'discharge_date', 'room_id', 'room_number', 'floor', 'lobby', 'bed_ids', 'bed_labels']) {
      expect(after[key]).toEqual(before[key]);
    }
    expect(after.notes).toBe('T4');
  });
  it('T5 mint: stay creation stores the derived lobby floor', async () => {
    await lobby(false);
    expect((await stored()).floor).toBe(2);
    await coherent();
  });
  it('T6a edit version: stale editVersion and expectedEditVersion return 409', async () => {
    const snapshot = await loaded();
    const result = await send('PUT', '/patients/placement-p', { editVersion: snapshot.editVersion, notes: 'first' });
    expect(result.statusCode, result.body).toBe(200);
    expect(result.json().editVersion).toBe(snapshot.editVersion + 1);
    const before = await stored();
    for (const version of [{ editVersion: snapshot.editVersion },
      { expectedEditVersion: snapshot.editVersion, editVersion: snapshot.editVersion + 1 }]) {
      const stale = await send('PUT', '/patients/placement-p', { ...version, notes: 'stale' });
      expect(stale.statusCode, stale.body).toBe(409);
      expect(stale.json().message).toBe('Patient version mismatch');
      expect(await stored()).toEqual(before);
    }
  });
  it('T6b edit version: attendance and billing persistence leave an open edit valid', async () => {
    await lobby(false);
    const snapshot = await loaded();
    const attendance = await send('POST', '/attendance', { patientId: 'placement-p', date: '2026-10-02',
      payload: { date: '2026-10-02', status: 'present', source: 'manual' } });
    expect(attendance.statusCode, attendance.body).toBe(200);
    const afterAttendance = await stored();
    expect(afterAttendance.version).toBeGreaterThan(snapshot.version);
    const billing = await send('POST', '/patients/placement-p/recalculate-billing', {});
    expect(billing.statusCode, billing.body).toBe(200);
    expect((await stored()).version).toBeGreaterThan(afterAttendance.version);
    expect((await stored()).edit_version).toBe(snapshot.editVersion);
    const edit = await send('PUT', '/patients/placement-p', { editVersion: snapshot.editVersion, notes: 'T6b' });
    expect(edit.statusCode, edit.body).toBe(200);
  });
  it.each(['convergence', 'class-1'] as const)('T6c edit version: admission %s invalidates an open edit', async repair => {
    await lobby(false);
    const snapshot = await loaded();
    if (repair === 'class-1') {
      await query("UPDATE patients SET registration_date='2026-09-30' WHERE id='placement-p'");
      expect(await repairAdmissions({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }))
        .toEqual({ repaired: 1, skipped: 0, failed: 0 });
    } else {
      await query("UPDATE patients SET admission_date='2026-10-02',registration_date='2026-10-02' WHERE id='placement-p'");
      const client = await getClient();
      try {
        await client.query('BEGIN');
        const result = await convergeAdmissionCycle(client, 'placement-p', { info: vi.fn(), warn: vi.fn(), error: vi.fn() });
        expect(result.outcome).toBe('converged');
        await client.query('COMMIT');
      } catch (error) { await client.query('ROLLBACK'); throw error; }
      finally { client.release(); }
    }
    const stale = await send('PUT', '/patients/placement-p', { editVersion: snapshot.editVersion, notes: 'stale' });
    expect(stale.statusCode, stale.body).toBe(409);
    expect(stale.json().message).toBe('Patient version mismatch');
    const fresh = await loaded();
    expect(fresh.editVersion).toBe(snapshot.editVersion + 1);
    const edited = await send('PUT', '/patients/placement-p', { editVersion: fresh.editVersion, notes: 'fresh' });
    expect(edited.statusCode, edited.body).toBe(200);
  });
  it('T6d edit version: only legacy stale version fields are ignored', async () => {
    await query("UPDATE patients SET version=100 WHERE id='placement-p'");
    const edited = await send('PUT', '/patients/placement-p', { expectedVersion: 1, version: 2, notes: 'legacy' });
    expect(edited.statusCode, edited.body).toBe(200);
    expect((await stored()).notes).toBe('legacy');
  });
  it('migration 014 backfills existing versions and defaults new edit versions to zero', async () => {
    const sql = (await readFile(new URL('../migrations/014_patient_edit_versions.sql', import.meta.url), 'utf8'))
      .split('-- Down Migration')[0];
    const client = await getClient();
    try {
      await client.query('BEGIN');
      // A transaction-local table shadows the real patient table for this DDL test.
      await client.query('CREATE TEMP TABLE patients(version integer NOT NULL) ON COMMIT DROP');
      await client.query('INSERT INTO patients(version) VALUES(0),(7),(29)');
      await client.query(sql);
      expect((await client.query('SELECT version,edit_version FROM patients ORDER BY version')).rows)
        .toEqual([{ version: 0, edit_version: 0 }, { version: 7, edit_version: 7 }, { version: 29, edit_version: 29 }]);
      expect((await client.query('INSERT INTO patients(version) VALUES(42) RETURNING edit_version')).rows[0].edit_version).toBe(0);
      await expect(client.query('INSERT INTO patients(version,edit_version) VALUES(43,NULL)')).rejects.toMatchObject({ code: '23502' });
    } finally { await client.query('ROLLBACK'); client.release(); }
  });
  it('T7 race: edit and room transfer serialize to a coherent placement', async () => {
    await roomPlacement();
    await room('transfer-room', 2);
    const snapshot = await loaded();
    const [edit, transfer] = await Promise.all([
      send('PUT', '/patients/placement-p', { ...editPayload(snapshot), notes: 'T7' }),
      send('POST', '/patients/placement-p/transfer', { requestId: 'placement-transfer', expectedStayIds: ['placement-s'],
        roomId: 'transfer-room', roomNumber: 'transfer-room', roomType: 'general', bedId: 'transfer-room-bed',
        shiftedAt: '2026-10-02' }),
    ]);
    expect(transfer.statusCode, transfer.body).toBe(200);
    expect([200, 409]).toContain(edit.statusCode);
    if (edit.statusCode === 409) expect(edit.json().message).toBe('Change active assignments through the stay lifecycle');
    else expect(edit.json().roomId).toBe('placement-room');
    expect((await loaded()).roomId).toBe('transfer-room');
    expect((await stored()).notes).toBe(edit.statusCode === 200 ? 'T7' : null);
    await coherent();
  });
});
