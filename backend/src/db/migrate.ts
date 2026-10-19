import { runner } from 'node-pg-migrate';
import path from 'path';
import { fileURLToPath } from 'url';
import { config } from '../config/index.js';
import pg from 'pg';
import { readdir } from 'node:fs/promises';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const migrationDir = path.resolve(__dirname, '../../migrations');

export async function migrationStatus() {
  const client = new pg.Client({ connectionString: config.getEffectiveDatabaseUrl() });
  await client.connect();
  try {
    const exists = (await client.query("SELECT to_regclass('public.pgmigrations') AS name")).rows[0].name;
    const applied = exists ? (await client.query('SELECT name FROM pgmigrations ORDER BY id')).rows.map(row => row.name as string) : [];
    const available = (await readdir(migrationDir)).filter(name => name.endsWith('.sql')).sort().map(name => name.slice(0, -4));
    return { applied, pending: available.filter(name => !applied.includes(name)), unexpected: applied.filter(name => !available.includes(name)) };
  } finally { await client.end(); }
}

export async function runMigrations(direction: 'up' | 'down' = 'up'): Promise<void> {
  const databaseUrl = config.getEffectiveDatabaseUrl();
  const target = new URL(databaseUrl);
  if (direction === 'down' && (config.NODE_ENV !== 'test' || process.env.ALLOW_DISPOSABLE_DB_ROLLBACK !== '1' || !['127.0.0.1', 'localhost'].includes(target.hostname) || !/^\/ngo_audit_[a-z_]+$/.test(target.pathname))) throw new Error('Rollback requires an explicitly enabled disposable local ngo_audit_* test database');
  console.log(`Running migrations (${direction}) on ${target.hostname}:${target.port || '5432'}${target.pathname}...`);

  await runner({
    databaseUrl,
    dir: migrationDir,
    direction,
    migrationsTable: 'pgmigrations',
    verbose: false,
  });

  console.log(`Migrations (${direction}) completed successfully.`);
}

// If executed directly from command line (e.g. node dist/db/migrate.js up or tsx src/db/migrate.ts up)
if (process.argv[1] && (path.resolve(process.argv[1]) === __filename || __filename.endsWith(path.normalize(process.argv[1])))) {
  const direction = process.argv[2] || 'up';
  const action = direction === 'status' ? migrationStatus().then(status => { console.log(JSON.stringify(status)); }) : ['up', 'down'].includes(direction) ? runMigrations(direction as 'up' | 'down') : Promise.reject(new Error('Expected up, down or status'));
  action
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('Migration execution failed:', err);
      process.exit(1);
    });
}
