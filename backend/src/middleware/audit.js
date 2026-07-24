import { AuditLog } from '../models/AuditLog.js';
import { logger } from '../config/logger.js';

/**
 * Records access to patient data. Fire-and-forget: an audit write must never
 * fail a clinical request, but a failure to write must be loud in the logs.
 */
export function audit(action, resource) {
  return (req, res, next) => {
    res.on('finish', () => {
      if (res.statusCode >= 400) return;
      AuditLog.create({
        actor: req.user?._id,
        actorRole: req.user?.role,
        action,
        resource,
        resourceId: req.auditResourceId,
        subjectPatient: req.patientId ?? req.user?._id,
        ip: req.ip,
        userAgent: req.get('user-agent')?.slice(0, 300),
        meta: { method: req.method, path: req.route?.path ?? req.originalUrl, status: res.statusCode },
      }).catch((err) => logger.error({ err }, 'audit write failed'));
    });
    next();
  };
}
