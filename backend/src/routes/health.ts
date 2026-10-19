import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import { checkDatabaseConnection } from '../db/index.js';

export async function healthRoutes(fastify: FastifyInstance, _opts: FastifyPluginOptions): Promise<void> {
  // Liveness probe — indicates process is running and event loop is responsive
  fastify.get('/health', async (_request, reply) => {
    return reply.status(200).send({
      status: 'healthy',
      service: 'ngo-backend',
      version: '1.0.0',
      uptimeSeconds: Math.floor(process.uptime()),
      timestamp: new Date().toISOString(),
    });
  });

  // Readiness probe — indicates application is ready to accept client traffic (DB is reachable)
  fastify.get('/ready', async (_request, reply) => {
    const dbStatus = await checkDatabaseConnection();

    if (!dbStatus.healthy) {
      return reply.status(503).send({
        status: 'not_ready',
        database: 'disconnected',
        error: 'Database unavailable',
        latencyMs: dbStatus.latencyMs,
        timestamp: dbStatus.timestamp,
      });
    }

    return reply.status(200).send({
      status: 'ready',
      database: 'connected',
      latencyMs: dbStatus.latencyMs,
      timestamp: dbStatus.timestamp,
    });
  });
}
