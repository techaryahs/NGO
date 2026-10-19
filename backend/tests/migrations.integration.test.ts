import { beforeAll, afterAll, describe, it, expect } from 'vitest';
import { runner } from 'node-pg-migrate';
import { fileURLToPath } from 'node:url';
import { query, pool } from '../src/db/index.js';
import { config } from '../src/config/index.js';
import { migrationStatus, runMigrations } from '../src/db/migrate.js';

describe.skipIf(process.env.RUN_PG_MIGRATIONS !== '1')('disposable PostgreSQL migration upgrade/rollback', () => {
  beforeAll(async () => {
    const target = new URL(config.getEffectiveDatabaseUrl());
    if (target.hostname !== '127.0.0.1' || target.port !== '55439' || target.pathname !== '/ngo_audit_migrations' || config.NODE_ENV !== 'test') throw new Error('Refusing non-disposable migration target');
    const identity = (await query("SELECT current_database() AS name, current_setting('server_version_num')::int AS version")).rows[0];
    expect(identity.name).toBe('ngo_audit_migrations'); expect(identity.version).toBeGreaterThanOrEqual(160000); expect(identity.version).toBeLessThan(170000);
    // Only this exact freshly-created audit database may be reset for reruns.
    await query('DROP SCHEMA public CASCADE; CREATE SCHEMA public');
  });
  afterAll(async () => { await pool.end(); });
  it('reports pending, applies existing SQL format, upgrades initialized data, verifies constraints and guarded rollback', async () => {
    expect((await migrationStatus()).pending.length).toBeGreaterThanOrEqual(4);
    await runner({ databaseUrl: config.getEffectiveDatabaseUrl(), dir: fileURLToPath(new URL('../migrations', import.meta.url)), direction: 'up', count: 1, migrationsTable: 'pgmigrations', verbose: false });
    expect((await migrationStatus()).applied).toEqual(['001_initial_schema']);
    await query("INSERT INTO patients(id,full_name,date_of_birth,gender,contact_number,emergency_contact,emergency_contact_name,medical_condition,admission_date,created_by) VALUES('upgrade-p','Synthetic','1990-01-01','Other','','','','Synthetic','2026-01-01','synthetic')");
    await query("INSERT INTO payments(id,patient_id,amount,payment_date) VALUES('upgrade-pay','upgrade-p',0.10,'2026-01-01')");
    await runMigrations();
    expect(await migrationStatus()).toMatchObject({ pending: [], unexpected: [] });
    expect((await query("SELECT amount FROM payments WHERE id='upgrade-pay'")).rows[0].amount).toBe('0.10');
    const constraints = (await query("SELECT conname,confdeltype FROM pg_constraint WHERE conname IN ('payments_patient_id_fkey','stays_patient_id_fkey','attendance_records_patient_id_fkey','patient_attendants_patient_id_fkey')")).rows;
    expect(constraints).toHaveLength(4); expect(constraints.every(row => row.confdeltype === 'r')).toBe(true);
    const precision = (await query("SELECT numeric_precision,numeric_scale FROM information_schema.columns WHERE table_name='payments' AND column_name='amount'")).rows[0];
    expect(precision).toEqual({ numeric_precision: 12, numeric_scale: 2 });
    expect((await query("SELECT indexname FROM pg_indexes WHERE indexname LIKE 'ux_%'")).rows).toHaveLength(5);
    await expect(query("DELETE FROM patients WHERE id='upgrade-p'")).rejects.toMatchObject({ code: '23503' });
    delete process.env.ALLOW_DISPOSABLE_DB_ROLLBACK;
    await expect(runMigrations('down')).rejects.toThrow(/explicitly enabled disposable/);
    process.env.ALLOW_DISPOSABLE_DB_ROLLBACK = '1';
    await runMigrations('down');
    expect((await migrationStatus()).pending.length).toBeGreaterThan(0);
    for (let i = 0; i < 10 && (await migrationStatus()).applied.length; i++) await runMigrations('down');
    expect((await migrationStatus()).applied).toEqual([]);
    expect((await query("SELECT tablename FROM pg_tables WHERE schemaname='public'")).rows.map(row => row.tablename)).toEqual(['pgmigrations']);
    await runMigrations();
    expect((await migrationStatus()).pending).toEqual([]);
    delete process.env.ALLOW_DISPOSABLE_DB_ROLLBACK;
  }, 30000);
});
