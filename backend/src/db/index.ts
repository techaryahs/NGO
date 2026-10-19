import pg from 'pg';
import { config } from '../config/index.js';

const { Pool } = pg;
// DATE is a calendar date, not local midnight (which shifts a day when serialized in IST).
pg.types.setTypeParser(1082, (value: string) => value);

export const pool = new Pool({
  connectionString: config.DATABASE_URL,
  host: config.POSTGRES_HOST,
  port: config.POSTGRES_PORT,
  database: config.POSTGRES_DB,
  user: config.POSTGRES_USER,
  password: config.POSTGRES_PASSWORD,
  max: config.DB_POOL_MAX,
  min: config.DB_POOL_MIN,
  idleTimeoutMillis: config.DB_POOL_IDLE_TIMEOUT_MS,
  connectionTimeoutMillis: config.DB_POOL_CONNECTION_TIMEOUT_MS,
});

// Avoid crashing unhandled on idle client errors
pool.on('error', (err) => {
  // pg errors can carry an attached Client, including connection parameters.
  console.error('Unexpected error on idle PostgreSQL client pool', { code: (err as Error & { code?: string }).code });
});

export interface HealthCheckResult {
  healthy: boolean;
  latencyMs?: number;
  error?: string;
  timestamp: string;
}

/**
 * Executes a fast `SELECT 1` query to verify database connectivity.
 */
export async function checkDatabaseConnection(): Promise<HealthCheckResult> {
  const start = Date.now();
  try {
    const client = await pool.connect();
    try {
      await client.query('SELECT 1');
      const latencyMs = Date.now() - start;
      return {
        healthy: true,
        latencyMs,
        timestamp: new Date().toISOString(),
      };
    } finally {
      client.release();
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      healthy: false,
      latencyMs: Date.now() - start,
      error: message,
      timestamp: new Date().toISOString(),
    };
  }
}

/**
 * Execute a parameterized SQL query on the pool.
 */
export async function query<T extends pg.QueryResultRow = pg.QueryResultRow>(
  text: string,
  params?: unknown[]
): Promise<pg.QueryResult<T>> {
  return pool.query<T>(text, params);
}

/**
 * Acquire a dedicated client for multi-statement transactions.
 */
export async function getClient(): Promise<pg.PoolClient> {
  return pool.connect();
}

/**
 * Gracefully close the connection pool during application shutdown.
 */
export async function closePool(): Promise<void> {
  try {
    await pool.end();
  } catch (err) {
    console.error('Error closing database connection pool:', err);
  }
}
