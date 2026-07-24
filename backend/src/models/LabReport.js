import mongoose from 'mongoose';

const labReportSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    title: { type: String, required: true, trim: true, maxlength: 200 },
    labName: { type: String, trim: true, maxlength: 160 },
    testedOn: { type: Date, required: true, index: true },

    files: [{ type: mongoose.Schema.Types.ObjectId, ref: 'MediaAsset' }],

    // Structured values the patient (or the extraction model) pulled out, so
    // key markers can be trended without re-reading the PDF.
    values: [
      {
        code: { type: String, trim: true, maxlength: 60 }, // 'HBA1C', 'CREAT', 'LDL'
        label: { type: String, trim: true, maxlength: 160 },
        value: { type: Number },
        textValue: { type: String, trim: true, maxlength: 120 },
        unit: { type: String, trim: true, maxlength: 40 },
        refLow: Number,
        refHigh: Number,
        flag: { type: String, enum: ['low', 'normal', 'high', 'critical'] },
      },
    ],

    aiSummary: { type: String, maxlength: 4000 },
    reviewedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    reviewedAt: Date,
  },
  { timestamps: true },
);

labReportSchema.index({ patient: 1, testedOn: -1 });

export const LabReport = mongoose.model('LabReport', labReportSchema);
