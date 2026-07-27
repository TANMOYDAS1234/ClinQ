import { readFileSync } from 'node:fs';
import admin from 'firebase-admin';

import { env } from './env.js';
import { logger } from './logger.js';

/**
 * Firebase Admin, initialised lazily and at most once.
 *
 * Returns null when no credentials are configured rather than throwing, so a
 * development machine — or a deployment where push is not wanted yet — runs
 * every notification caller unchanged and simply logs instead of sending.
 *
 * The service-account key is read from a path, never from the repo. That key
 * can push to every device registered to the project, so it belongs on the
 * server's filesystem with the rest of the secrets.
 */
let messaging;
let attempted = false;

export function getMessaging() {
  if (attempted) return messaging;
  attempted = true;

  const path = env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!path) {
    logger.warn('GOOGLE_APPLICATION_CREDENTIALS not set — notifications will be logged, not sent');
    return null;
  }

  try {
    const credential = JSON.parse(readFileSync(path, 'utf8'));
    const app = admin.initializeApp({ credential: admin.credential.cert(credential) });
    messaging = app.messaging();
    logger.info({ projectId: credential.project_id }, 'firebase messaging ready');
    return messaging;
  } catch (err) {
    // Deliberately not fatal: a clinic should keep taking appointments and
    // answering patients even if push is misconfigured.
    logger.error({ err, path }, 'could not initialise firebase; notifications will be logged only');
    return null;
  }
}
