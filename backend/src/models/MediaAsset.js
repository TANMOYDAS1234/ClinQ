import mongoose from 'mongoose';

/**
 * Every uploaded file (foot photo, retinal report, lab PDF) is registered here.
 * Storing ownership on the asset lets one authorisation check guard all
 * downloads, instead of each module re-implementing access rules.
 */
const mediaAssetSchema = new mongoose.Schema(
  {
    owner: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    uploadedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },

    kind: {
      type: String,
      enum: ['foot_photo', 'retinal_report', 'lab_report', 'prescription_pdf', 'meal_photo', 'other'],
      required: true,
      index: true,
    },

    storageKey: { type: String, required: true }, // path relative to UPLOAD_DIR
    originalName: { type: String, maxlength: 260 },
    mimeType: { type: String, required: true },
    sizeBytes: { type: Number, required: true },
    width: Number,
    height: Number,

    // Soft-delete: clinical images are retained for the medical record even
    // after a patient hides them from their own timeline.
    deletedAt: Date,
  },
  { timestamps: true },
);

export const MediaAsset = mongoose.model('MediaAsset', mediaAssetSchema);
