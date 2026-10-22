import { settlementRoutes } from './routes/settlement.js';
import Fastify, { FastifyInstance, FastifyServerOptions } from 'fastify';
import cors from '@fastify/cors';
import { config } from './config/index.js';
import { healthRoutes } from './routes/health.js';
import { patientRoutes } from './routes/patients.js';
import { roomRoutes } from './routes/rooms.js';
import { stayRoutes } from './routes/stays.js';
import { attendanceRoutes } from './routes/attendance.js';
import { paymentRoutes } from './routes/payments.js';
import { counterRoutes } from './routes/counters.js';
import { settingsRoutes } from './routes/settings.js';
import { photoRoutes } from './routes/photos.js';
import { erpRoutes } from './routes/erp.js';
import { userRoutes } from './routes/users.js';
import { validateDomainRequest } from './validation.js';
import { randomUUID } from 'node:crypto';

export function buildApp(opts: FastifyServerOptions = {}): FastifyInstance {
  const app = Fastify({
    requestIdHeader: false,
    genReqId: request => {
      const supplied = request.headers['x-request-id'];
      return typeof supplied === 'string' && /^payreq_[A-Za-z0-9_-]{1,80}$/.test(supplied) ? supplied : randomUUID();
    },
    // Stay and payment IDs are VARCHAR(128); Fastify's default of 100
    // otherwise makes valid persisted receipts unreachable by ID.
    maxParamLength: 128,
    logger: {
      level: config.LOG_LEVEL,
    },
    ...opts,
  });

  const isPaymentSubmission = (request: { method: string; url: string }) => request.method === 'POST' && request.url.split('?')[0] === '/api/payments';
  app.addHook('onSend', async (request, reply, payload) => {
    if (isPaymentSubmission(request)) reply.header('x-request-id', request.id);
    return payload;
  });
  app.addHook('onResponse', async (request, reply) => {
    if (isPaymentSubmission(request)) request.log.info({ requestId: request.id, statusCode: reply.statusCode, category: 'payment_submission' }, 'Payment request completed');
  });

  // Enable CORS with strict origin validation
  app.addHook('preValidation', validateDomainRequest);
  app.register(cors, {
    origin: (origin, cb) => {
      // 1. Allow native desktop (Flutter Windows), mobile, curl and server requests with no Origin header.
      // Note: Origin is a browser security mechanism, NOT an authentication mechanism.
      if (!origin) {
        return cb(null, true);
      }

      // 2. Browser requests: Allow ONLY explicitly approved origins from environment configuration.
      // Wildcard '*' is strictly prohibited as an origin substitute.
      if (config.CORS_ORIGINS.length > 0 && config.CORS_ORIGINS.includes(origin)) {
        return cb(null, true);
      }

      // 3. Disallow unapproved browser origins (omits Access-Control-Allow-Origin).
      return cb(null, false);
    },
    methods: ['GET', 'HEAD', 'PUT', 'PATCH', 'POST', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type', 'Accept', 'Origin', 'X-Requested-With', 'X-Request-Id'],
    exposedHeaders: ['x-pagination-mode', 'x-next-cursor', 'x-request-id'],
    credentials: true,
    maxAge: 86400,
  });

  // Register health & readiness routes at root level
  app.register(healthRoutes);

  // Mount API domain routes under /api
  app.register(healthRoutes, { prefix: '/api' });
  app.register(patientRoutes, { prefix: '/api' });
  app.register(roomRoutes, { prefix: '/api' });
  app.register(stayRoutes, { prefix: '/api' });
  app.register(attendanceRoutes, { prefix: '/api' });
  app.register(paymentRoutes, { prefix: '/api' });
  app.register(settlementRoutes, { prefix: '/api' });
  app.register(counterRoutes, { prefix: '/api' });
  app.register(settingsRoutes, { prefix: '/api' });
  app.register(photoRoutes, { prefix: '/api' });
  app.register(erpRoutes, { prefix: '/api' });
  app.register(userRoutes, { prefix: '/api' });

  // Root welcome / status route
  app.get('/', async (_request, reply) => {
    return reply.status(200).send({
      name: 'NGO Management System API',
      status: 'active',
      version: '1.0.0',
      docs: '/health',
    });
  });

  // Global error handler
  app.setErrorHandler((error, request, reply) => {
    const code = (error as Error & { code?: string }).code || '';
    const statusCode = error.statusCode || (['23505', '23503'].includes(code) ? 409 : /^(22|23502|23514)/.test(code) ? 400 : 500);
    if (isPaymentSubmission(request)) {
      request.log.error({ requestId: request.id, statusCode, category: statusCode >= 500 ? 'payment_server_error' : statusCode === 409 ? 'payment_conflict' : 'payment_validation' }, 'Payment request failed');
    } else {
      app.log.error({ err: error, code, statusCode, message: error.message }, 'Request failed');
    }
    return reply.status(statusCode).send({
      statusCode,
      ...(isPaymentSubmission(request) ? { requestId: request.id } : {}),
      error: statusCode >= 500 ? 'InternalServerError' : statusCode === 409 ? 'Conflict' : 'BadRequest',
      message: statusCode >= 500 ? 'An unexpected error occurred' : code ? 'The request conflicts with database constraints or contains invalid data' : error.message,
    });
  });

  return app;
}
