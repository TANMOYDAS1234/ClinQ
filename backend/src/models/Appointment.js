import mongoose from 'mongoose';

export const APPOINTMENT_STATUS = Object.freeze([
  'requested',
  'confirmed',
  'checked_in',
  'in_consultation',
  'completed',
  'cancelled',
  'no_show',
]);

const appointmentSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },

    // The location this appointment is booked at. Required for an in-clinic
    // visit (its slot came from the clinic's schedule); absent for teleconsult.
    clinic: { type: mongoose.Schema.Types.ObjectId, ref: 'Clinic', index: true },

    mode: { type: String, enum: ['in_clinic', 'teleconsult'], default: 'in_clinic' },
    scheduledFor: { type: Date, required: true, index: true },
    durationMinutes: { type: Number, default: 15, min: 5, max: 120 },

    status: { type: String, enum: APPOINTMENT_STATUS, default: 'requested', index: true },
    reason: { type: String, maxlength: 600 },

    // Queue management: assigned when the patient checks in, so walk-ins and
    // booked patients share one ordering.
    queueNumber: { type: Number },
    queueDate: { type: String, index: true }, // 'YYYY-MM-DD' in clinic-local time
    calledAt: Date,

    teleconsult: {
      roomId: String,
      joinUrl: String,
      patientJoinedAt: Date,
      doctorJoinedAt: Date,
    },

    consultationNotes: { type: String, maxlength: 8000 },
    prescription: { type: mongoose.Schema.Types.ObjectId, ref: 'Prescription' },

    rescheduledFrom: { type: mongoose.Schema.Types.ObjectId, ref: 'Appointment' },
    cancelledBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    cancellationReason: { type: String, maxlength: 500 },

    // Set when triage escalates a chat into a priority slot request.
    createdFromAlert: { type: mongoose.Schema.Types.ObjectId, ref: 'ClinicalAlert' },
    isPriority: { type: Boolean, default: false, index: true },
  },
  { timestamps: true },
);

appointmentSchema.index({ doctor: 1, scheduledFor: 1 });
appointmentSchema.index({ patient: 1, scheduledFor: -1 });
appointmentSchema.index({ queueDate: 1, queueNumber: 1 });

export const Appointment = mongoose.model('Appointment', appointmentSchema);
