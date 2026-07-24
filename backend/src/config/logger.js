import pino from 'pino';
import { env, isProd } from './env.js';

/**
 * Patient data must never land in logs. `redact` covers the fields most likely
 * to carry PHI if an object is logged wholesale by mistake.
 */
export const logger = pino({
  level: isProd ? 'info' : 'debug',
  redact: {
    paths: [
      'req.headers.authorization',
      'req.body.password',
      'req.body.currentPassword',
      'req.body.newPassword',
      'req.body.message',
      'password',
      'passwordHash',
      'refreshTokenHash',
      '*.password',
      '*.passwordHash',
    ],
    censor: '[redacted]',
  },
  transport: isProd
    ? undefined
    : {
        target: 'pino-pretty',
        options: { colorize: true, translateTime: 'HH:MM:ss', ignore: 'pid,hostname' },
      },
});

logger.info(
  { env: env.NODE_ENV, chatModel: env.GEMINI_CHAT_MODEL },
  'logger initialised',
);
