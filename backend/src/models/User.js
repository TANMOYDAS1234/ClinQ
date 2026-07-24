import mongoose from 'mongoose';
import bcrypt from 'bcryptjs';

export const ROLES = Object.freeze({
  PATIENT: 'patient',
  DOCTOR: 'doctor',
  STAFF: 'staff',
});

export const LANGUAGES = Object.freeze(['en', 'bn', 'hi']);

const userSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true, maxlength: 120 },
    phone: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      // Stored E.164-ish; the app normalises to +91XXXXXXXXXX before sending.
      match: [/^\+?[1-9]\d{7,14}$/, 'invalid phone number'],
    },
    email: {
      type: String,
      lowercase: true,
      trim: true,
      sparse: true,
      unique: true,
      match: [/^\S+@\S+\.\S+$/, 'invalid email'],
    },
    passwordHash: { type: String, required: true, select: false },
    role: { type: String, enum: Object.values(ROLES), default: ROLES.PATIENT, index: true },
    language: { type: String, enum: LANGUAGES, default: 'en' },

    dateOfBirth: Date,
    gender: { type: String, enum: ['male', 'female', 'other', 'undisclosed'], default: 'undisclosed' },

    // Push delivery targets for reminders and escalations.
    deviceTokens: [{ type: String }],

    isActive: { type: Boolean, default: true },
    lastLoginAt: Date,

    // Consent is a compliance requirement, not a UI checkbox we can forget.
    consent: {
      termsAcceptedAt: Date,
      dataProcessingAcceptedAt: Date,
      aiDisclaimerAcceptedAt: Date,
    },
  },
  { timestamps: true },
);

userSchema.methods.setPassword = async function setPassword(plain) {
  this.passwordHash = await bcrypt.hash(plain, 12);
};

userSchema.methods.verifyPassword = function verifyPassword(plain) {
  return bcrypt.compare(plain, this.passwordHash);
};

userSchema.methods.toPublic = function toPublic() {
  return {
    id: this._id.toString(),
    name: this.name,
    phone: this.phone,
    email: this.email ?? null,
    role: this.role,
    language: this.language,
    dateOfBirth: this.dateOfBirth ?? null,
    gender: this.gender,
    createdAt: this.createdAt,
  };
};

export const User = mongoose.model('User', userSchema);
