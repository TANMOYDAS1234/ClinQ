import mongoose from 'mongoose';

/**
 * A test report the patient uploaded against a lab test the doctor advised
 * (Prescription.labTestsAdvised). The photo/PDF is a MediaAsset served from
 * /uploads/:id/raw.
 */
const labResultSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    testName: { type: String, required: true, trim: true, maxlength: 200 },
    note: { type: String, trim: true, maxlength: 1000 },
    photo: { type: mongoose.Schema.Types.ObjectId, ref: 'MediaAsset' },
  },
  { timestamps: true },
);

labResultSchema.index({ patient: 1, createdAt: -1 });

export const LabResult = mongoose.model('LabResult', labResultSchema);
