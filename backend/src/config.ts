import { z } from "zod";

const booleanString = z.enum(["true", "false"]);
const falseByDefault = booleanString.default("false").transform((value) => value === "true");
const trueByDefault = booleanString.default("true").transform((value) => value === "true");

const schema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  HOST: z.string().default("0.0.0.0"),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  LOG_LEVEL: z.string().default("info"),
  DATABASE_URL: z.string().optional().or(z.literal("")),
  DATABASE_SSL: trueByDefault,
  MESHY_API_KEY: z.string().optional().or(z.literal("")),
  MESHY_BASE_URL: z.string().url().default("https://api.meshy.ai"),
  MESHY_POLL_INTERVAL_MS: z.coerce.number().int().min(500).default(5000),
  MESHY_TASK_TIMEOUT_MS: z.coerce.number().int().min(30_000).default(900_000),
  OPENAI_API_KEY: z.string().optional().or(z.literal("")),
  OPENAI_IMAGE_MODEL: z.string().default("gpt-image-2"),
  OPENAI_IMAGE_QUALITY: z.enum(["low", "medium", "high", "auto"]).default("low"),
  ROBLOX_OPEN_CLOUD_API_KEY: z.string().optional().or(z.literal("")),
  ROBLOX_CREATOR_TYPE: z.enum(["group", "user"]).default("group"),
  ROBLOX_CREATOR_ID: z.coerce.number().int().positive().optional(),
  ROBLOX_SHARED_SECRET: z.string().optional().or(z.literal("")),
  ROBLOX_ASSET_TIMEOUT_MS: z.coerce.number().int().min(30_000).default(180_000),
  TARGET_TRIANGLES: z.coerce.number().int().min(100).max(3999).default(3600),
  MAX_TRIANGLES: z.coerce.number().int().min(100).max(3999).default(3999),
  MAX_VERTICES: z.coerce.number().int().min(100).max(3999).default(3999),
  MAX_TEXTURE_SIZE: z.coerce.number().int().min(64).max(2048).default(2048),
  MAX_MODEL_BYTES: z.coerce.number().int().min(1_000_000).max(20_000_000).default(19_500_000),
  MAX_CONCURRENT_JOBS: z.coerce.number().int().min(1).max(32).default(4),
  MOCK_PROVIDERS: falseByDefault,
});

export type AppConfig = {
  nodeEnv: "development" | "test" | "production";
  host: string;
  port: number;
  logLevel: string;
  databaseUrl?: string;
  databaseSsl: boolean;
  meshy: {
    apiKey: string;
    baseUrl: string;
    pollIntervalMs: number;
    timeoutMs: number;
  };
  openai: {
    apiKey: string;
    imageModel: string;
    imageQuality: "low" | "medium" | "high" | "auto";
  };
  roblox: {
    apiKey: string;
    creatorType: "group" | "user";
    creatorId: number;
    sharedSecret: string;
    assetTimeoutMs: number;
  };
  limits: {
    targetTriangles: number;
    maxTriangles: number;
    maxVertices: number;
    maxTextureSize: number;
    maxModelBytes: number;
    maxConcurrentJobs: number;
  };
  mockProviders: boolean;
};

export function loadConfig(source: NodeJS.ProcessEnv = process.env): AppConfig {
  const parsed = schema.parse(source);
  const production = parsed.NODE_ENV === "production";

  const alwaysRequiredInProduction = {
    ROBLOX_SHARED_SECRET: parsed.ROBLOX_SHARED_SECRET,
    DATABASE_URL: parsed.DATABASE_URL,
  };

  const liveProviderRequirements = {
    MESHY_API_KEY: parsed.MESHY_API_KEY,
    OPENAI_API_KEY: parsed.OPENAI_API_KEY,
    ROBLOX_OPEN_CLOUD_API_KEY: parsed.ROBLOX_OPEN_CLOUD_API_KEY,
    ROBLOX_CREATOR_ID: parsed.ROBLOX_CREATOR_ID,
  };

  if (production) {
    if (parsed.MOCK_PROVIDERS) {
      throw new Error("MOCK_PROVIDERS cannot be enabled in production");
    }
    const required = { ...alwaysRequiredInProduction, ...liveProviderRequirements };
    const missing = Object.entries(required)
      .filter(([, value]) => value === undefined || value === "")
      .map(([name]) => name);
    if (missing.length > 0) {
      throw new Error(`Missing production configuration: ${missing.join(", ")}`);
    }
    if ((parsed.ROBLOX_SHARED_SECRET ?? "").length < 32) {
      throw new Error("ROBLOX_SHARED_SECRET must contain at least 32 characters in production");
    }
  }

  if (parsed.TARGET_TRIANGLES > parsed.MAX_TRIANGLES) {
    throw new Error("TARGET_TRIANGLES must be less than or equal to MAX_TRIANGLES");
  }

  const databaseUrl = parsed.DATABASE_URL || undefined;
  return {
    nodeEnv: parsed.NODE_ENV,
    host: parsed.HOST,
    port: parsed.PORT,
    logLevel: parsed.LOG_LEVEL,
    ...(databaseUrl ? { databaseUrl } : {}),
    databaseSsl: parsed.DATABASE_SSL,
    meshy: {
      apiKey: parsed.MESHY_API_KEY ?? "",
      baseUrl: parsed.MESHY_BASE_URL.replace(/\/$/, ""),
      pollIntervalMs: parsed.MESHY_POLL_INTERVAL_MS,
      timeoutMs: parsed.MESHY_TASK_TIMEOUT_MS,
    },
    openai: {
      apiKey: parsed.OPENAI_API_KEY ?? "",
      imageModel: parsed.OPENAI_IMAGE_MODEL,
      imageQuality: parsed.OPENAI_IMAGE_QUALITY,
    },
    roblox: {
      apiKey: parsed.ROBLOX_OPEN_CLOUD_API_KEY ?? "",
      creatorType: parsed.ROBLOX_CREATOR_TYPE,
      creatorId: parsed.ROBLOX_CREATOR_ID ?? 1,
      sharedSecret: parsed.ROBLOX_SHARED_SECRET ?? "development-secret-change-me",
      assetTimeoutMs: parsed.ROBLOX_ASSET_TIMEOUT_MS,
    },
    limits: {
      targetTriangles: parsed.TARGET_TRIANGLES,
      maxTriangles: parsed.MAX_TRIANGLES,
      maxVertices: parsed.MAX_VERTICES,
      maxTextureSize: parsed.MAX_TEXTURE_SIZE,
      maxModelBytes: parsed.MAX_MODEL_BYTES,
      maxConcurrentJobs: parsed.MAX_CONCURRENT_JOBS,
    },
    mockProviders: parsed.MOCK_PROVIDERS,
  };
}
