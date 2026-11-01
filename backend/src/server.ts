import { buildApp } from './app.js';
import { config } from './config/index.js';
import { closePool } from './db/index.js';
import { startAdmissionRepair } from './services/admission_repair.js';
import { startPhotoCleanup } from './services/photo_staging.js';

async function startServer(): Promise<void> {
  const app = buildApp();
  let stopRepair: (() => Promise<void>) | undefined;
  let stopCleanup: (() => Promise<void>) | undefined;
  app.addHook('onClose', async () => { await stopRepair?.(); await stopCleanup?.(); });

  const shutdown = async (signal: string) => {
    app.log.info({ signal }, 'Received shutdown signal, shutting down gracefully...');
    try {
      await app.close();
      await closePool();
      app.log.info('Application and database pool closed cleanly.');
      process.exit(0);
    } catch (err) {
      app.log.error(err, 'Error during graceful shutdown');
      process.exit(1);
    }
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));

  try {
    const address = await app.listen({
      port: config.PORT,
      host: config.HOST,
    });
    stopRepair = startAdmissionRepair(app.log);
    stopCleanup = startPhotoCleanup(app.log);
    app.log.info(
      { port: config.PORT, host: config.HOST, env: config.NODE_ENV },
      `NGO Backend API is listening at ${address}`
    );
  } catch (err) {
    app.log.error(err, 'Failed to start server');
    process.exit(1);
  }
}

startServer();
