import dotenv from 'dotenv';
import path from 'path';
import { z } from 'zod';

// Load .env from backend root or repository root if present
dotenv.config();
dotenv.config({ path: path.resolve(process.cwd(), '../.env') });

export const configSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  HOST: z.string().default('0.0.0.0'),
  PORT: z.coerce.number().int().positive().default(8080),
  LOG_LEVEL: z.string().default('info'),

  // Database settings
  POSTGRES_HOST: z.string().default('localhost'),
  POSTGRES_PORT: z.coerce.number().int().positive().default(5432),
  POSTGRES_DB: z.string().default('ngo_db'),
  POSTGRES_USER: z.string().default('ngo_user'),
  POSTGRES_PASSWORD: z.string().default('ngo_password'),
  DATABASE_URL: z.string().url().refine(value => /^postgres(?:ql)?:\/\//.test(value), 'Use a PostgreSQL URL').optional(),

  // Connection Pool settings
  DB_POOL_MAX: z.coerce.number().int().positive().default(20),
  DB_POOL_MIN: z.coerce.number().int().nonnegative().default(2),
  DB_POOL_IDLE_TIMEOUT_MS: z.coerce.number().int().positive().default(30000),
  DB_POOL_CONNECTION_TIMEOUT_MS: z.coerce.number().int().positive().default(5000),

  // Security & Authentication
  // Firebase project ID is public configuration, never a service-account secret.
  FIREBASE_PROJECT_ID: z.string().trim().regex(/^[a-z0-9][a-z0-9-]{4,62}$/).optional(),

  // CORS Origins: Environment-based allowlist of approved browser origins.
  // Wildcard origins are rejected to prevent insecure credential exposure.
  CORS_ORIGINS: z
    .string()
    .default('')
    .transform((val) => {
      try {
        const parsed = JSON.parse(val);
        if (Array.isArray(parsed)) {
          return parsed.map((s) => String(s).trim()).filter((s) => s.length > 0 && s !== '*');
        }
      } catch {
        // Fall back to comma-separated splitting
      }
      return val
        .split(',')
        .map((s) => s.trim())
        .filter((s) => s.length > 0 && s !== '*');
    }),
}).superRefine((env, context) => {
  if (env.NODE_ENV === 'production' && !env.FIREBASE_PROJECT_ID) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['FIREBASE_PROJECT_ID'], message: 'FIREBASE_PROJECT_ID is required in production' });
  }
  if (env.NODE_ENV === 'production' && !env.DATABASE_URL
    && ['ngo_password', 'NGO@2026', 'password', 'replace_with_secure_password_in_production', ''].includes(env.POSTGRES_PASSWORD)) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['POSTGRES_PASSWORD'], message: 'Configure a non-default production database password' });
  }
  if (env.DB_POOL_MIN > env.DB_POOL_MAX) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['DB_POOL_MIN'], message: 'DB_POOL_MIN cannot exceed DB_POOL_MAX' });
  }
});

export type Config = z.infer<typeof configSchema> & {
  getEffectiveDatabaseUrl: () => string;
};

const parsedEnv = configSchema.parse(process.env);

export const config: Config = {
  ...parsedEnv,
  getEffectiveDatabaseUrl: () => {
    if (parsedEnv.DATABASE_URL) {
      return parsedEnv.DATABASE_URL;
    }
    const encodedUser = encodeURIComponent(parsedEnv.POSTGRES_USER);
    const encodedPass = encodeURIComponent(parsedEnv.POSTGRES_PASSWORD);
    return `postgres://${encodedUser}:${encodedPass}@${parsedEnv.POSTGRES_HOST}:${parsedEnv.POSTGRES_PORT}/${parsedEnv.POSTGRES_DB}`;
  },
};
