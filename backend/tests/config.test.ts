import { describe, it, expect } from 'vitest';
import { config, configSchema } from '../src/config/index.js';

describe('Configuration Module', () => {
  it('should load default port and host', () => {
    expect(config.PORT).toBeGreaterThan(0);
    expect(typeof config.HOST).toBe('string');
  });

  it('should have valid database connection properties', () => {
    expect(config.POSTGRES_DB).toBeDefined();
    expect(config.POSTGRES_USER).toBeDefined();
    expect(config.POSTGRES_HOST).toBeDefined();
    expect(config.POSTGRES_PORT).toBe(5432);
  });

  it('should generate an effective database URL string', () => {
    const url = config.getEffectiveDatabaseUrl();
    expect(url).toMatch(/^postgres:\/\/.+:.+@.+:\d+\/.+$/);
  });

  it('should have reasonable pool settings', () => {
    expect(config.DB_POOL_MAX).toBeGreaterThanOrEqual(1);
    expect(config.DB_POOL_MIN).toBeGreaterThanOrEqual(0);
    expect(config.DB_POOL_IDLE_TIMEOUT_MS).toBeGreaterThan(0);
  });

  it('requires a Firebase project in production', () => {
    const result = configSchema.safeParse({ NODE_ENV: 'production', POSTGRES_PASSWORD: 'synthetic-only-password' });
    expect(result.success).toBe(false);
    if (!result.success) expect(result.error.issues.some(issue => issue.path[0] === 'FIREBASE_PROJECT_ID')).toBe(true);
  });

  it('rejects default or template production database passwords', () => {
    for (const password of [undefined, 'ngo_password', 'replace_with_secure_password_in_production']) {
      const result = configSchema.safeParse({ NODE_ENV: 'production', FIREBASE_PROJECT_ID: 'ngo-test-project', POSTGRES_PASSWORD: password });
      expect(result.success).toBe(false);
    }
  });

  it('accepts explicit production project and database credentials', () => {
    expect(configSchema.safeParse({ NODE_ENV: 'production', FIREBASE_PROJECT_ID: 'ngo-test-project', POSTGRES_PASSWORD: 'synthetic-only-password' }).success).toBe(true);
  });

  it('rejects a pool minimum larger than its maximum', () => {
    expect(configSchema.safeParse({ DB_POOL_MIN: 10, DB_POOL_MAX: 2 }).success).toBe(false);
  });

  it('accepts PostgreSQL DATABASE_URL and rejects other connection protocols', () => {
    expect(configSchema.safeParse({ DATABASE_URL: 'postgresql://test:test@127.0.0.1:5432/ngo_audit_test' }).success).toBe(true);
    expect(configSchema.safeParse({ DATABASE_URL: 'https://example.invalid/database' }).success).toBe(false);
  });
});
