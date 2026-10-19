import { buildApp } from './app.js';
import { config } from './config/index.js';
import { closePool } from './db/index.js';

async function startServer(): Promise<void> {
  const app = buildApp();

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
