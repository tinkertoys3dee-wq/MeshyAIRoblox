import { timingSafeEqual } from "node:crypto";
import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import type { AppConfig } from "./config.js";
import { JobRunner } from "./pipeline.js";
import { ImageProvider } from "./providers/openai-image.js";
import type { JobRepository } from "./repository.js";
import {
  createJobSchema,
  moderatePromptSchema,
  PipelineError,
  publicJob,
  type CreateJobInput,
  type Job,
} from "./types.js";

export async function buildServer(config: AppConfig, repository: JobRepository): Promise<FastifyInstance> {
  const app = Fastify({
    logger: { level: config.logLevel },
    bodyLimit: 64 * 1024,
    requestTimeout: 30_000,
    trustProxy: true,
  });
  const runner = new JobRunner(config, repository, app.log);
  const moderator = new ImageProvider(config);
  const moderationWindows = new Map<number, number[]>();
  const jobWindows = new Map<number, number[]>();
  const uploadWindows = new Map<number, number[]>();
  const imageWindows = new Map<string, number[]>();

  app.get("/health", async () => ({
    ok: true,
    service: "forge-ugc-backend",
    version: "0.1.0",
    persistence: config.databaseUrl ? "postgres" : "memory",
    providers: config.mockProviders ? "mock" : "live",
  }));

  app.post("/v1/moderate", async (request, reply) => {
    if (!authenticate(request, config.roblox.sharedSecret)) return reply.code(401).send({ error: "UNAUTHORIZED" });
    const parsed = moderatePromptSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: "INVALID_REQUEST" });
    if (!identityMatches(request, parsed.data.playerUserId)) return reply.code(403).send({ error: "IDENTITY_MISMATCH" });
    if (!consumeRateLimit(moderationWindows, parsed.data.playerUserId, 20, 5 * 60_000)) {
      return reply.code(429).send({ error: "RATE_LIMITED" });
    }
    if (config.mockProviders) return { safe: true };
    try {
      await moderator.assertSafe(parsed.data.filteredPrompt);
      return { safe: true };
    } catch (error) {
      if (error instanceof PipelineError && error.code === "CONTENT_REJECTED") {
        return reply.code(422).send({ error: "CONTENT_REJECTED" });
      }
      request.log.error({ error, playerUserId: parsed.data.playerUserId }, "Prompt moderation failed");
      return reply.code(503).send({ error: "MODERATION_UNAVAILABLE" });
    }
  });

  app.post("/v1/jobs", async (request, reply) => {
    if (!authenticate(request, config.roblox.sharedSecret)) return reply.code(401).send({ error: "UNAUTHORIZED" });
    const parsed = createJobSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "INVALID_REQUEST", details: parsed.error.flatten() });
    }
    if (!identityMatches(request, parsed.data.playerUserId)) return reply.code(403).send({ error: "IDENTITY_MISMATCH" });
    const existing = await repository.getByRequestId(parsed.data.requestId);
    if (existing && !sameRequest(existing, parsed.data)) {
      return reply.code(409).send({ error: "IDEMPOTENCY_CONFLICT" });
    }
    if (
      !existing &&
      parsed.data.kind === "IMAGE_UPLOAD" &&
      !consumeRateLimit(uploadWindows, parsed.data.playerUserId, 6, 5 * 60_000)
    ) {
      return reply.code(429).send({ error: "RATE_LIMITED" });
    }
    if (!existing && !consumeRateLimit(jobWindows, parsed.data.playerUserId, 12, 5 * 60_000)) {
      return reply.code(429).send({ error: "RATE_LIMITED" });
    }
    const job = existing ?? (await repository.create(parsed.data));
    if (!sameRequest(job, parsed.data)) {
      return reply.code(409).send({ error: "IDEMPOTENCY_CONFLICT" });
    }
    runner.enqueue(job.id, job.priority);
    return reply.code(existing ? 200 : 202).send({ job: publicJob(job), idempotent: Boolean(existing) });
  });

  app.get<{ Params: { id: string } }>("/v1/jobs/:id", async (request, reply) => {
    if (!authenticate(request, config.roblox.sharedSecret)) return reply.code(401).send({ error: "UNAUTHORIZED" });
    const job = await repository.get(request.params.id);
    if (!job) return reply.code(404).send({ error: "NOT_FOUND" });
    if (!identityMatches(request, job.playerUserId)) return reply.code(403).send({ error: "IDENTITY_MISMATCH" });
    return { job: publicJob(job) };
  });

  // Deliberately unauthenticated: this is the shareable link a player opens
  // in their own browser (outside Roblox entirely) to view or save their
  // avatar graphic, so it can't require the Roblox-server-only shared
  // secret or a Roblox identity header. The job ID is an unguessable UUID,
  // same trust model as any other unlisted share link; only a SUCCEEDED
  // AVATAR_GRAPHIC job's own artifact is ever served, never an
  // in-progress reference image from another job kind.
  app.get<{ Params: { jobId: string } }>("/v1/graphics/:jobId/image", async (request, reply) => {
    if (!consumeRateLimit(imageWindows, request.ip, 60, 5 * 60_000)) {
      return reply.code(429).send({ error: "RATE_LIMITED" });
    }
    const job = await repository.get(request.params.jobId);
    if (!job || job.kind !== "AVATAR_GRAPHIC" || job.status !== "SUCCEEDED" || !job.imageArtifact) {
      return reply.code(404).send({ error: "NOT_FOUND" });
    }
    reply.header("Cache-Control", "public, max-age=31536000, immutable");
    return reply.type("image/png").send(job.imageArtifact);
  });

  app.addHook("onClose", async () => {
    runner.close();
  });

  await runner.recover();
  return app;
}

function authenticate(request: FastifyRequest, expectedSecret: string): boolean {
  const supplied = request.headers["x-forge-secret"];
  if (typeof supplied !== "string") return false;
  const left = Buffer.from(supplied);
  const right = Buffer.from(expectedSecret);
  return left.length === right.length && timingSafeEqual(left, right);
}

function identityMatches(request: FastifyRequest, userId: number): boolean {
  const supplied = request.headers["x-roblox-user-id"];
  return typeof supplied === "string" && Number(supplied) === userId;
}

function sameRequest(existing: Job, incoming: CreateJobInput): boolean {
  return (
    existing.requestId === incoming.requestId &&
    existing.playerUserId === incoming.playerUserId &&
    existing.kind === incoming.kind &&
    existing.filteredPrompt === incoming.filteredPrompt &&
    (existing.accessoryType ?? undefined) === (incoming.accessoryType ?? undefined) &&
    existing.stylePreset === incoming.stylePreset &&
    existing.detailLevel === incoming.detailLevel &&
    (existing.imageQuality ?? undefined) === (incoming.imageQuality ?? undefined) &&
    existing.sourceJobId === incoming.sourceJobId &&
    existing.sourceImageAssetId === incoming.sourceImageAssetId &&
    (existing.avatarView ?? undefined) === (incoming.avatarView ?? undefined)
  );
}

function consumeRateLimit<K>(windows: Map<K, number[]>, key: K, maximum: number, durationMs: number): boolean {
  const cutoff = Date.now() - durationMs;
  const timestamps = (windows.get(key) ?? []).filter((timestamp) => timestamp >= cutoff);
  if (timestamps.length >= maximum) {
    windows.set(key, timestamps);
    return false;
  }
  timestamps.push(Date.now());
  windows.set(key, timestamps);
  return true;
}
