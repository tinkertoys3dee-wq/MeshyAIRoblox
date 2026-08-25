import { z } from "zod";

export const jobKindSchema = z.enum(["TEXT_TO_3D", "IMAGE_PREVIEW", "IMAGE_UPLOAD", "IMAGE_TO_3D", "AVATAR_TO_3D"]);
export type JobKind = z.infer<typeof jobKindSchema>;

export const avatarViewSchema = z.enum(["HEADSHOT", "BUST", "FULL_BODY"]);
export type AvatarView = z.infer<typeof avatarViewSchema>;

export const stylePresetSchema = z.enum(["AUTO", "ANIME", "REALISTIC", "STYLIZED", "LOW_POLY", "FANTASY"]);
export type StylePreset = z.infer<typeof stylePresetSchema>;

export const detailLevelSchema = z.enum(["CLEAN", "BALANCED", "INTRICATE"]);
export type DetailLevel = z.infer<typeof detailLevelSchema>;

// Mirrors OpenAI's own gpt-image quality tiers, so a purchased tier maps
// directly onto the provider parameter with no translation layer.
export const imageQualitySchema = z.enum(["low", "medium", "high"]);
export type ImageQuality = z.infer<typeof imageQualitySchema>;

export const accessoryTypeSchema = z.enum([
  "Hat",
  "HairAccessory",
  "FaceAccessory",
  "NeckAccessory",
  "ShoulderAccessory",
  "FrontAccessory",
  "BackAccessory",
  "WaistAccessory",
]);
export type AccessoryType = z.infer<typeof accessoryTypeSchema>;

export const createJobSchema = z
  .object({
    requestId: z.string().min(12).max(80).regex(/^[a-zA-Z0-9_-]+$/),
    playerUserId: z.number().int().positive(),
    kind: jobKindSchema,
    filteredPrompt: z.string().trim().min(6).max(500),
    accessoryType: accessoryTypeSchema,
    stylePreset: stylePresetSchema.default("AUTO"),
    detailLevel: detailLevelSchema.default("BALANCED"),
    imageQuality: imageQualitySchema.optional(),
    sourceJobId: z.string().uuid().optional(),
    sourceImageAssetId: z.number().int().positive().max(Number.MAX_SAFE_INTEGER).optional(),
    avatarView: avatarViewSchema.optional(),
    priority: z.boolean().default(false),
    context: z
      .object({
        universeId: z.number().int().nonnegative(),
        placeId: z.number().int().nonnegative(),
        gameJobId: z.string().max(128),
      })
      .strict(),
  })
  .strict()
  .superRefine((value, context) => {
    if (value.kind === "IMAGE_TO_3D" && !value.sourceJobId) {
      context.addIssue({ code: "custom", path: ["sourceJobId"], message: "sourceJobId is required" });
    }
    if (value.kind !== "IMAGE_TO_3D" && value.sourceJobId) {
      context.addIssue({ code: "custom", path: ["sourceJobId"], message: "sourceJobId is only valid for IMAGE_TO_3D" });
    }
    if (value.kind === "IMAGE_UPLOAD" && !value.sourceImageAssetId) {
      context.addIssue({ code: "custom", path: ["sourceImageAssetId"], message: "sourceImageAssetId is required" });
    }
    if (value.kind !== "IMAGE_UPLOAD" && value.kind !== "IMAGE_TO_3D" && value.sourceImageAssetId) {
      context.addIssue({
        code: "custom",
        path: ["sourceImageAssetId"],
        message: "sourceImageAssetId is only valid for IMAGE_UPLOAD or IMAGE_TO_3D",
      });
    }
    if (value.kind !== "IMAGE_PREVIEW" && value.imageQuality) {
      context.addIssue({
        code: "custom",
        path: ["imageQuality"],
        message: "imageQuality is only valid for IMAGE_PREVIEW",
      });
    }
    if (value.kind === "AVATAR_TO_3D" && !value.avatarView) {
      context.addIssue({ code: "custom", path: ["avatarView"], message: "avatarView is required" });
    }
    if (value.kind !== "AVATAR_TO_3D" && value.avatarView) {
      context.addIssue({ code: "custom", path: ["avatarView"], message: "avatarView is only valid for AVATAR_TO_3D" });
    }
  });

export type CreateJobInput = z.infer<typeof createJobSchema>;

export const moderatePromptSchema = z
  .object({
    playerUserId: z.number().int().positive(),
    filteredPrompt: z.string().trim().min(6).max(500),
  })
  .strict();

export const jobStatuses = [
  "QUEUED",
  "MODERATING",
  "GENERATING_IMAGE",
  "IMAGE_READY",
  "GENERATING_MESH",
  "TEXTURING",
  "VALIDATING",
  "UPLOADING",
  "SUCCEEDED",
  "FAILED",
] as const;
export type JobStatus = (typeof jobStatuses)[number];

export type JobOutput = {
  previewAssetId?: number;
  modelAssetId?: number;
  thumbnailAssetId?: number;
  meshyPreviewTaskId?: string;
  meshyFinalTaskId?: string;
  triangles?: number;
  vertices?: number;
  textureWidth?: number;
  textureHeight?: number;
};

export type JobError = {
  code: string;
  message: string;
  retryable: boolean;
};

export type Job = {
  id: string;
  requestId: string;
  playerUserId: number;
  kind: JobKind;
  status: JobStatus;
  stage: string;
  progress: number;
  filteredPrompt: string;
  accessoryType: AccessoryType;
  stylePreset: StylePreset;
  detailLevel: DetailLevel;
  imageQuality?: ImageQuality;
  sourceJobId?: string;
  sourceImageAssetId?: number;
  avatarView?: AvatarView;
  priority: boolean;
  context: CreateJobInput["context"];
  output: JobOutput;
  error?: JobError;
  imageArtifact?: Buffer;
  createdAt: Date;
  updatedAt: Date;
};

export type JobPatch = Partial<
  Pick<Job, "status" | "stage" | "progress" | "output" | "error" | "imageArtifact" | "updatedAt">
>;

export function publicJob(job: Job) {
  return {
    id: job.id,
    requestId: job.requestId,
    kind: job.kind,
    status: job.status,
    stage: job.stage,
    progress: job.progress,
    accessoryType: job.accessoryType,
    stylePreset: job.stylePreset,
    detailLevel: job.detailLevel,
    ...(job.imageQuality ? { imageQuality: job.imageQuality } : {}),
    priority: job.priority,
    ...(job.sourceJobId ? { sourceJobId: job.sourceJobId } : {}),
    output: {
      ...(typeof job.output.previewAssetId === "number" ? { previewAssetId: job.output.previewAssetId } : {}),
      ...(typeof job.output.modelAssetId === "number" ? { modelAssetId: job.output.modelAssetId } : {}),
      ...(typeof job.output.thumbnailAssetId === "number" ? { thumbnailAssetId: job.output.thumbnailAssetId } : {}),
      ...(typeof job.output.triangles === "number" ? { triangles: job.output.triangles } : {}),
      ...(typeof job.output.vertices === "number" ? { vertices: job.output.vertices } : {}),
      ...(typeof job.output.textureWidth === "number" ? { textureWidth: job.output.textureWidth } : {}),
      ...(typeof job.output.textureHeight === "number" ? { textureHeight: job.output.textureHeight } : {}),
    },
    ...(job.error ? { error: { code: job.error.code, retryable: job.error.retryable } } : {}),
    createdAt: job.createdAt,
    updatedAt: job.updatedAt,
  };
}

export class PipelineError extends Error {
  readonly code: string;
  readonly retryable: boolean;

  constructor(code: string, message: string, retryable = false) {
    super(message);
    this.name = "PipelineError";
    this.code = code;
    this.retryable = retryable;
  }
}
