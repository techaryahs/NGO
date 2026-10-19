import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { buildApp } from '../src/app.js';
import * as dbModule from '../src/db/index.js';

describe('Health and Readiness Endpoints', () => {
  let app: ReturnType<typeof buildApp>;

  beforeEach(() => {
    vi.restoreAllMocks();
    app = buildApp();
  });

  afterEach(async () => { await app.close(); });

  it('GET /health should return 200 with service status and uptime', async () => {
    const response = await app.inject({
      method: 'GET',
      url: '/health',
    });

    expect(response.statusCode).toBe(200);
    const body = JSON.parse(response.body);
    expect(body.status).toBe('healthy');
    expect(body.service).toBe('ngo-backend');
    expect(body.version).toBe('1.0.0');
    expect(typeof body.uptimeSeconds).toBe('number');
    expect(body.timestamp).toBeDefined();
  });

  it('GET /api/health should also return 200 for reverse-proxy compatibility', async () => {
    const response = await app.inject({
      method: 'GET',
      url: '/api/health',
    });

    expect(response.statusCode).toBe(200);
    const body = JSON.parse(response.body);
    expect(body.status).toBe('healthy');
  });

  it('GET /ready should return 200 when database connection is healthy', async () => {
    vi.spyOn(dbModule, 'checkDatabaseConnection').mockResolvedValue({
      healthy: true,
      latencyMs: 3,
      timestamp: new Date().toISOString(),
    });

    const response = await app.inject({
      method: 'GET',
      url: '/ready',
    });

    expect(response.statusCode).toBe(200);
    const body = JSON.parse(response.body);
    expect(body.status).toBe('ready');
    expect(body.database).toBe('connected');
    expect(body.latencyMs).toBe(3);
  });

  it('GET /ready should return 503 when database is disconnected or unreachable', async () => {
    vi.spyOn(dbModule, 'checkDatabaseConnection').mockResolvedValue({
      healthy: false,
      latencyMs: 50,
      error: 'Connection refused at 5432',
      timestamp: new Date().toISOString(),
    });

    const response = await app.inject({
      method: 'GET',
      url: '/ready',
    });

    expect(response.statusCode).toBe(503);
    const body = JSON.parse(response.body);
    expect(body.status).toBe('not_ready');
    expect(body.database).toBe('disconnected');
    expect(body.error).toBe('Database unavailable');
    expect(response.body).not.toContain('Connection refused');
  });

  it('GET / should return root application metadata', async () => {
    const response = await app.inject({
      method: 'GET',
      url: '/',
    });

    expect(response.statusCode).toBe(200);
    const body = JSON.parse(response.body);
    expect(body.name).toBe('NGO Management System API');
    expect(body.status).toBe('active');
  });
});
