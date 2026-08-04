import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config();

/**
 * Fail fast on misconfiguration. A healthcare service silently starting with a
 * missing JWT secret or no AI key is worse than not starting at all.
 */
const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().default(4000),

  MONGODB_URI: z.string().min(1, 'MONGODB_URI is required'),

  JWT_ACCESS_SECRET: z.string().min(16, 'JWT_ACCESS_SECRET must be >= 16 chars'),
  JWT_REFRESH_SECRET: z.string().min(16, 'JWT_REFRESH_SECRET must be >= 16 chars'),
  ACCESS_TOKEN_TTL: z.string().default('30m'),
  REFRESH_TOKEN_TTL: z.string().default('60d'),

  GEMINI_API_KEY: z.string().min(1, 'GEMINI_API_KEY is required'),
  GEMINI_CHAT_MODEL: z.string().default('gemini-2.5-flash'),
  GEMINI_VISION_MODEL: z.string().default('gemini-2.5-flash'),
  GEMINI_EMBED_MODEL: z.string().default('text-embedding-004'),

  // Absolute path to the Firebase service-account JSON. Optional: without it
  // notifications are logged rather than sent, so a development machine needs
  // no credentials. Never the key itself — that file can push to every device
  // registered to the project and belongs on the server, not in config.
  GOOGLE_APPLICATION_CREDENTIALS: z.string().optional(),

  // Atlas Vector Search is used when available; otherwise the RAG layer falls
  // back to in-process cosine similarity (fine for a single-clinic corpus).
  USE_ATLAS_VECTOR_SEARCH: z
    .enum(['true', 'false'])
    .default('false')
    .transform((v) => v === 'true'),
  VECTOR_INDEX_NAME: z.string().default('knowledge_vector_index'),

  UPLOAD_DIR: z.string().default('uploads'),
  MAX_UPLOAD_MB: z.coerce.number().default(12),

  CLINIC_NAME: z.string().default('Dr. Amit Kumar Dey Clinic'),
  CLINIC_EMERGENCY_PHONE: z.string().default('+91-0000000000'),
  DOCTOR_DISPLAY_NAME: z.string().default('Dr. Amit Kumar Dey'),

  // Anyone who registers with this exact code becomes a dietician instead of a
  // patient. Change it per clinic; keep it private (shared only with dieticians
  // the doctor is onboarding).
  DIETICIAN_INVITE_CODE: z.string().min(4).default('CLINQ-DIET-2026'),

  // Clinic wall-clock timezone. All appointment slot times are computed in this
  // zone, so the schedule is correct no matter what timezone the server runs in
  // (a VPS is often UTC). India is a single zone.
  CLINIC_TZ: z.string().default('Asia/Kolkata'),
});

const parsed = schema.safeParse(process.env);

if (!parsed.success) {
  const issues = parsed.error.issues
    .map((i) => `  - ${i.path.join('.')}: ${i.message}`)
    .join('\n');
  console.error(`\nInvalid environment configuration:\n${issues}\n`);
  console.error('Copy .env.example to .env and fill in the values.\n');
  process.exit(1);
}

export const env = parsed.data;
export const isProd = env.NODE_ENV === 'production';
