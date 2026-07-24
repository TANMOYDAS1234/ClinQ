import { Router } from 'express';
import mongoose from 'mongoose';

import authRoutes from './auth.js';
import chatRoutes from './chat.js';
import trackingRoutes from './tracking.js';
import medicationRoutes from './medications.js';
import careRoutes from './care.js';
import appointmentRoutes from './appointments.js';
import prescriptionRoutes from './prescriptions.js';
import dashboardRoutes from './dashboard.js';
import doctorRoutes from './doctor.js';
import uploadRoutes from './uploads.js';

const router = Router();

router.get('/health', (req, res) => {
  const states = ['disconnected', 'connected', 'connecting', 'disconnecting'];
  res.json({
    status: 'ok',
    db: states[mongoose.connection.readyState] ?? 'unknown',
    uptime: Math.round(process.uptime()),
    version: '1.0.0',
  });
});

router.use('/auth', authRoutes);
router.use('/chat', chatRoutes);
router.use('/appointments', appointmentRoutes);
router.use('/doctor', doctorRoutes);
router.use('/uploads', uploadRoutes);

// Patient-scoped clinical data. `:patientId` is 'me' for patients, or a real
// id for clinicians — resolvePatientScope enforces which is allowed.
router.use('/patients/:patientId', trackingRoutes);
router.use('/patients/:patientId/medications', medicationRoutes);
router.use('/patients/:patientId', careRoutes);
router.use('/patients/:patientId/prescriptions', prescriptionRoutes);
router.use('/patients/:patientId/dashboard', dashboardRoutes);

export default router;
