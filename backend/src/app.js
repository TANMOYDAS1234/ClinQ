import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import compression from 'compression';
import morgan from 'morgan';
import rateLimit from 'express-rate-limit';

import routes from './routes/index.js';
import { errorHandler, notFoundHandler } from './middleware/errors.js';
import { logger } from './config/logger.js';
import { isProd } from './config/env.js';

export function createApp() {
  const app = express();

  // Behind a reverse proxy in production; needed for correct req.ip in
  // rate limiting and audit logs.
  app.set('trust proxy', 1);

  app.use(
    helmet({
      // The prescription print view is served as inline-styled HTML.
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          styleSrc: ["'self'", "'unsafe-inline'"],
          scriptSrc: ["'self'", "'unsafe-inline'"],
          imgSrc: ["'self'", 'data:'],
        },
      },
      crossOriginResourcePolicy: { policy: 'cross-origin' },
    }),
  );

  app.use(
    cors({
      origin: isProd ? (process.env.ALLOWED_ORIGINS?.split(',') ?? false) : true,
      credentials: true,
    }),
  );

  app.use(compression());
  app.use(express.json({ limit: '1mb' }));
  app.use(express.urlencoded({ extended: true, limit: '1mb' }));

  app.use(
    morgan(isProd ? 'combined' : 'dev', {
      stream: { write: (msg) => logger.info(msg.trim()) },
      // Health checks would otherwise dominate the logs.
      skip: (req) => req.path === '/api/v1/health',
    }),
  );

  // Broad backstop; per-route limiters handle the sensitive paths.
  app.use(
    rateLimit({
      windowMs: 60 * 1000,
      limit: 300,
      standardHeaders: 'draft-7',
      legacyHeaders: false,
      skip: (req) => req.path === '/api/v1/health',
    }),
  );

  app.use('/api/v1', routes);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
