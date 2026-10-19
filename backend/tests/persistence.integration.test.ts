import { afterAll, beforeAll, describe, it, expect } from 'vitest';
import { spawn } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { buildApp } from '../src/app.js';
import { query, pool } from '../src/db/index.js';
import { config } from '../src/config/index.js';

describe.skipIf(process.env.RUN_PG_RESTART !== '1')('disposable PostgreSQL outage, recovery and persistence', () => {
  const app = buildApp({ logger: false });
  let stopped = false;
  let dataDir: string;
  let binary: string;
  // Async process control lets pg consume disconnect events while PostgreSQL
  // stops; inherited pipe handles must not keep a Windows child process open.
  const control = (action: 'stop' | 'start') => new Promise<void>((resolve, reject) => {
    const child = spawn(binary, ['-D', dataDir, '-w', ...(action === 'stop' ? ['-m', 'fast'] : ['-l', path.join(dataDir, 'server.log'), '-o', '-p 55439 -h 127.0.0.1']), action], { timeout: 20000, stdio: 'ignore', windowsHide: true });
    child.on('error', reject); child.on('exit', code => code === 0 ? resolve() : reject(new Error(`Disposable pg_ctl ${action} exited ${code}`)));
  });
  beforeAll(async () => {
    const target = new URL(config.getEffectiveDatabaseUrl());
    if (config.NODE_ENV !== 'test' || target.hostname !== '127.0.0.1' || target.port !== '55439' || target.pathname !== '/ngo_audit_workflows' || !process.env.AUDIT_PG_DATA_DIR || !process.env.AUDIT_PG_CTL) throw new Error('Explicit disposable cluster configuration required');
    dataDir = realpathSync(process.env.AUDIT_PG_DATA_DIR); binary = realpathSync(process.env.AUDIT_PG_CTL);
    if (!dataDir.startsWith(realpathSync(tmpdir()) + path.sep) || !path.basename(dataDir).startsWith('ngo-audit-pg16-')) throw new Error('Refusing to control a non-audit cluster');
    const identity = (await query("SELECT current_database() AS db,current_setting('data_directory') AS directory,current_setting('server_version_num')::int AS version")).rows[0];
    expect(identity.db).toBe('ngo_audit_workflows'); expect(realpathSync(identity.directory)).toBe(dataDir);
    expect(identity.version).toBeGreaterThanOrEqual(160000); expect(identity.version).toBeLessThan(170000);
  });
  afterAll(async () => { if (stopped) await control('start'); await app.close(); await pool.end(); });
  it('returns safe503 during outage, recovers with the same pool and retains committed records after restart', async () => {
    await query("INSERT INTO system_counters(counter_name,current_value) VALUES('audit_restart_marker',12345) ON CONFLICT(counter_name) DO UPDATE SET current_value=12345");
    expect((await app.inject('/ready')).statusCode).toBe(200);
    await control('stop'); stopped = true;
    const unavailable = await app.inject('/ready');
    expect(unavailable.statusCode).toBe(503); expect(unavailable.body).not.toMatch(/127\.0\.0\.1|55439|ECONNREFUSED|ngo_audit/);
    await control('start'); stopped = false;
    expect((await app.inject('/ready')).statusCode).toBe(200);
    expect((await query("SELECT current_value FROM system_counters WHERE counter_name='audit_restart_marker'")).rows[0].current_value).toBe('12345');
    await query("DELETE FROM system_counters WHERE counter_name='audit_restart_marker'");
  }, 45000);
});
