import { createApp } from './app.js';
import { connectDb, disconnectDb } from './config/db.js';
import { env } from './config/env.js';
import { logger } from './config/logger.js';

async function main() {
  await connectDb();

  const app = createApp();
  const server = app.listen(env.PORT, () => {
    logger.info(`AKD Care API listening on http://localhost:${env.PORT}/api/v1`);
  });

  // The evening appointment digest is intentionally NOT started: the app no
  // longer exposes an appointment feature, so a nightly "tomorrow's schedule"
  // push — including the empty "no appointments" one — is just noise.

  // Finish in-flight clinical writes before dying.
  const shutdown = async (signal) => {
    logger.info({ signal }, 'shutting down');
    server.close(async () => {
      await disconnectDb();
      process.exit(0);
    });
    setTimeout(() => {
      logger.error('forced shutdown after timeout');
      process.exit(1);
    }, 10_000).unref();
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  process.on('unhandledRejection', (reason) => {
    logger.error({ reason }, 'unhandled promise rejection');
  });
  process.on('uncaughtException', (err) => {
    logger.fatal({ err }, 'uncaught exception');
    process.exit(1);
  });
}

main().catch((err) => {
  logger.fatal({ err }, 'failed to start server');
  process.exit(1);
});
