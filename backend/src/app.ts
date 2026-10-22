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

export function buildApp(opts: FastifyServerOptions = {}): FastifyInstance {
  const app = Fastify({
    // Stay and payment IDs are VARCHAR(128); Fastify's default of 100
    // otherwise makes valid persisted receipts unreachable by ID.
    maxParamLength: 128,
    logger: {
      level: config.LOG_LEVEL,
    },
    ...opts,
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
    allowedHeaders: ['Authorization', 'Content-Type', 'Accept', 'Origin', 'X-Requested-With'],
    exposedHeaders: ['x-pagination-mode', 'x-next-cursor'],
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
  app.setErrorHandler((error, _request, reply) => {
    app.log.error({ err: error, code: (error as Error & { code?: string }).code, statusCode: error.statusCode, message: error.message }, 'Request failed');
    const code = (error as Error & { code?: string }).code || '';
    const statusCode = error.statusCode || (['23505', '23503'].includes(code) ? 409 : /^(22|23502|23514)/.test(code) ? 400 : 500);
    return reply.status(statusCode).send({
      statusCode,
      error: statusCode >= 500 ? 'InternalServerError' : statusCode === 409 ? 'Conflict' : 'BadRequest',
      message: statusCode >= 500 ? 'An unexpected error occurred' : code ? 'The request conflicts with database constraints or contains invalid data' : error.message,
    });
  });

  return app;
}
