import mongoose from 'mongoose';
import { TIME_RE, DATE_RE } from '../utils/clinicTime.js';

const timeValidator = { validator: (v) => TIME_RE.test(v), message: 'time must be HH:mm (24h)' };

/**
 * One recurring window in the weekly schedule — e.g. Monday 10:00–14:00. A day
 * can have several (a morning and an evening sitting), so this is a flat list
 * keyed by dayOfWeek rather than one entry per day.
 */
const weeklyHoursSchema = new mongoose.Schema(
  {
    dayOfWeek: { type: Number, min: 0, max: 6, required: true }, // 0 = Sunday
    start: { type: String, required: true, validate: timeValidator },
    end: { type: String, required: true, validate: timeValidator },
  },
  { _id: false },
);

const windowSchema = new mongoose.Schema(
  {
    start: { type: String, required: true, validate: timeValidator },
    end: { type: String, required: true, validate: timeValidator },
  },
  { _id: false },
);

/**
 * A date-specific exception to the weekly pattern: a holiday closure
 * (`isClosed`) or special one-off hours (`windows`). Overrides win over the
 * weekly schedule for that date.
 */
const overrideSchema = new mongoose.Schema(
  {
    date: { type: String, required: true, match: DATE_RE }, // 'YYYY-MM-DD'
    isClosed: { type: Boolean, default: false },
    windows: { type: [windowSchema], default: [] },
    note: { type: String, maxlength: 200 },
  },
  { _id: false },
);

/**
 * A physical location where the doctor holds consultations, together with the
 * schedule of when they are available there. Doctor and staff manage these; the
 * slot engine ([services/scheduling.js]) turns the schedule into bookable
 * times, and patients book against it.
 */
const clinicSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true, maxlength: 160 },
    addressLine: { type: String, trim: true, maxlength: 400 },
    city: { type: String, trim: true, maxlength: 120 },
    phone: { type: String, trim: true, maxlength: 40 },
    // Optional map link (Google Maps, etc.) so a patient can find the place.
    mapUrl: { type: String, trim: true, maxlength: 600 },

    // The doctor whose availability this schedule represents. Single-doctor
    // today; the ref keeps a multi-doctor build open.
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', index: true },

    slotMinutes: { type: Number, default: 15, min: 5, max: 120 },
    weeklyHours: { type: [weeklyHoursSchema], default: [] },
    overrides: { type: [overrideSchema], default: [] },

    // Soft-disable rather than delete, so past appointments keep their clinic.
    isActive: { type: Boolean, default: true, index: true },
    sortIndex: { type: Number, default: 0 },
  },
  { timestamps: true },
);

clinicSchema.methods.toPublic = function toPublic() {
  return {
    id: this._id,
    name: this.name,
    addressLine: this.addressLine ?? null,
    city: this.city ?? null,
    phone: this.phone ?? null,
    mapUrl: this.mapUrl ?? null,
    slotMinutes: this.slotMinutes,
    weeklyHours: (this.weeklyHours ?? [])
      .map((w) => ({ dayOfWeek: w.dayOfWeek, start: w.start, end: w.end }))
      .sort((a, b) => a.dayOfWeek - b.dayOfWeek || a.start.localeCompare(b.start)),
    overrides: (this.overrides ?? []).map((o) => ({
      date: o.date,
      isClosed: o.isClosed,
      windows: (o.windows ?? []).map((w) => ({ start: w.start, end: w.end })),
      note: o.note ?? null,
    })),
    isActive: this.isActive,
    sortIndex: this.sortIndex,
    createdAt: this.createdAt,
  };
};

/** Lightweight shape for embedding on an appointment. */
clinicSchema.methods.toBrief = function toBrief() {
  return {
    id: this._id,
    name: this.name,
    addressLine: this.addressLine ?? null,
    city: this.city ?? null,
    phone: this.phone ?? null,
  };
};

export const Clinic = mongoose.model('Clinic', clinicSchema);
