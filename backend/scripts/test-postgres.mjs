// Full local test matrix. Never accepts a database URL or an existing cluster.
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { tmpdir } from 'node:os';
import path from 'node:path';
import net from 'node:net';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const backend = fileURLToPath(new URL('../', import.meta.url));
const suites = [
  ['workflows', 'RUN_PG_INTEGRATION'],
  ['modules', 'AUDIT_DATABASE_TESTS'],
  ['importer', 'RUN_IMPORTER_DB_TESTS'],
  ['payment_financial', 'RUN_PAYMENT_ACCURACY_INTEGRATION', 'payment_accuracy'],
  ['scalability', 'RUN_SCALE_INTEGRATION', 'scale'],
  ['settlement', 'RUN_SETTLEMENT_TESTS'],
  ['auth_database', 'RUN_AUTH_PG_INTEGRATION', 'auth'],
  ['migrations', 'RUN_PG_MIGRATIONS'],
  ['persistence', 'RUN_PG_RESTART', 'workflows'],
];
const baseEnv = { ...process.env, NODE_ENV: 'test' };
for (const [, flag] of suites) delete baseEnv[flag];
const executable = name => {
  const suffix = process.platform === 'win32' ? '.exe' : '';
  const configured = process.env.AUDIT_PG_BIN_DIR;
  const candidates = configured ? [path.join(configured, name + suffix)] : [
    ...(process.platform === 'win32' ? [path.join(process.env.ProgramFiles || 'C:\\Program Files', 'PostgreSQL', '16', 'bin', name + suffix)] : []),
    ...(process.env.PATH || '').split(path.delimiter).map(dir => path.join(dir, name + suffix)),
  ];
  const found = candidates.find(candidate => existsSync(candidate));
  if (!found) throw new Error(`PostgreSQL 16 ${name} missing; set AUDIT_PG_BIN_DIR to its bin directory`);
  return realpathSync(found);
};
const pgCtl = executable('pg_ctl');
const initdb = executable('initdb');
const run = (binary, args, env = baseEnv) => {
  const result = spawnSync(binary, args, { cwd: backend, env, stdio: 'inherit', windowsHide: true });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${path.basename(binary)} failed (exit ${result.status})`);
};
const version = spawnSync(pgCtl, ['--version'], { encoding: 'utf8', windowsHide: true });
if (version.status !== 0 || !/PostgreSQL\) 16\./.test(version.stdout)) throw new Error('PostgreSQL 16 is required');
// Fail before initdb/tests if the fixed port belongs to any other service.
await new Promise((resolve, reject) => {
  const server = net.createServer();
  server.once('error', () => reject(new Error('Port 55439 is occupied; refusing to reuse an existing database')));
  server.listen(55439, '127.0.0.1', () => server.close(resolve));
});
const root = mkdtempSync(path.join(tmpdir(), 'ngo-audit-pg16-release-'));
const dataDir = path.join(root, 'ngo-audit-pg16-cluster');
const password = randomBytes(24).toString('hex');
const passwordFile = path.join(root, 'password');
writeFileSync(passwordFile, password, { mode: 0o600 });
let started = false;
try {
  run(initdb, ['-D', dataDir, '-U', 'ngo_audit', '--pwfile', passwordFile,
    '--auth-local=trust', '--auth-host=scram-sha-256', '--encoding=UTF8', '--locale=C']);
  rmSync(passwordFile);
  run(pgCtl, ['-D', dataDir, '-l', path.join(root, 'server.log'), '-o', '-p 55439 -h 127.0.0.1', '-w', '-t', '30', 'start']);
  started = true;
  const connection = { host: '127.0.0.1', port: 55439, user: 'ngo_audit', password };
  const admin = new pg.Client({ ...connection, database: 'postgres' });
  await admin.connect();
  try {
    const identity = (await admin.query("SELECT current_setting('data_directory') AS directory,current_setting('server_version_num')::int AS version")).rows[0];
    if (realpathSync(identity.directory) !== realpathSync(dataDir) || identity.version < 160000 || identity.version >= 170000) throw new Error('Disposable cluster identity mismatch');
    for (const name of new Set(suites.map(([name, , db]) => `ngo_audit_${db || name}`))) {
      if (!/^ngo_audit_[a-z_]+$/.test(name)) throw new Error('Invalid test database name');
      await admin.query(`CREATE DATABASE ${name}`);
    }
  } finally { await admin.end(); }
  const environment = database => ({ ...baseEnv, POSTGRES_HOST: '127.0.0.1', POSTGRES_PORT: '55439',
    POSTGRES_DB: database, POSTGRES_USER: 'ngo_audit', POSTGRES_PASSWORD: password,
    DATABASE_URL: `postgres://ngo_audit:${password}@127.0.0.1:55439/${database}`,
    AUDIT_PG_DATA_DIR: dataDir, AUDIT_PG_CTL: pgCtl, SCALE_PHASE: 'release',
  });
  const vitest = path.join(backend, 'node_modules', 'vitest', 'vitest.mjs');
  const tests = readFileSync(path.join(backend, 'package.json'), 'utf8');
  if (!tests.includes('vitest run')) throw new Error('Unexpected project test convention');
  // Run every ordinary test, then every opt-in file in its exact dedicated DB.
  run(process.execPath, [vitest, 'run', '--reporter=dot', '--exclude=**/*.integration.test.ts'], environment('ngo_audit_workflows'));
  for (const [name, flag, db] of suites) {
    console.log(`\nDISPOSABLE_SUITE ${name}`);
    run(process.execPath, [vitest, 'run', '--reporter=dot', `tests/${name}.integration.test.ts`],
      { ...environment(`ngo_audit_${db || name}`), [flag]: '1' });
  }
  console.log('DISPOSABLE_MATRIX_COMPLETE: all suites executed; no opt-in files skipped');
} finally {
  if (started) run(pgCtl, ['-D', dataDir, '-w', '-t', '30', '-m', 'fast', 'stop']);
  const resolved = realpathSync(root);
  if (path.dirname(resolved) !== realpathSync(tmpdir()) || !path.basename(resolved).startsWith('ngo-audit-pg16-release-')) throw new Error('Unsafe cleanup target');
  rmSync(resolved, { recursive: true });
}
