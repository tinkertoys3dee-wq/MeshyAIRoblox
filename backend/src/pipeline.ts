import sharp from "sharp";
import type { AppConfig } from "./config.js";
import { composeMeshyPrompt } from "./guidance.js";
import { ImageProvider } from "./providers/openai-image.js";
import { MeshyClient } from "./providers/meshy.js";
import { RobloxAssetClient } from "./providers/roblox-assets.js";
import { RobloxReferenceClient } from "./providers/roblox-reference.js";
import type { JobRepository } from "./repository.js";
import { PipelineError, type Job, type JobOutput } from "./types.js";
import { validateAndNormalizeGlb } from "./validation/gltf.js";

type Logger = {
  info(object: unknown, message?: string): void;
  error(object: unknown, message?: string): void;
};

export class JobRunner {
  readonly #config: AppConfig;
  readonly #repository: JobRepository;
  readonly #logger: Logger;
  readonly #meshy: MeshyClient;
  readonly #images: ImageProvider;
  readonly #roblox: RobloxAssetClient;
  readonly #robloxReferences: RobloxReferenceClient;
  readonly #pending: string[] = [];
  readonly #active = new Set<string>();
  #closed = false;

  constructor(config: AppConfig, repository: JobRepository, logger: Logger) {
    this.#config = config;
    this.#repository = repository;
    this.#logger = logger;
    this.#meshy = new MeshyClient(config);
    this.#images = new ImageProvider(config);
    this.#roblox = new RobloxAssetClient(config);
    this.#robloxReferences = new RobloxReferenceClient();
  }

  async recover(): Promise<void> {
    const jobs = await this.#repository.listRecoverable();
    for (const job of jobs) this.enqueue(job.id, job.priority);
  }

  enqueue(jobId: string, priority = false): void {
    if (this.#closed || this.#active.has(jobId) || this.#pending.includes(jobId)) return;
    if (priority) this.#pending.unshift(jobId);
    else this.#pending.push(jobId);
    this.#drain();
  }

  close(): void {
    this.#closed = true;
  }

  #drain(): void {
    while (
      !this.#closed &&
      this.#active.size < this.#config.limits.maxConcurrentJobs &&
      this.#pending.length > 0
    ) {
      const jobId = this.#pending.shift();
      if (!jobId) break;
      this.#active.add(jobId);
      void this.#run(jobId).finally(() => {
        this.#active.delete(jobId);
        this.#drain();
      });
    }
  }

  async #run(jobId: string): Promise<void> {
    const job = await this.#repository.get(jobId);
    if (!job || ["SUCCEEDED", "FAILED", "IMAGE_READY"].includes(job.status)) return;
    this.#logger.info({ jobId, kind: job.kind, userId: job.playerUserId }, "Starting generation job");

    try {
      if (this.#config.mockProviders) {
        await this.#runMock(job);
      } else {
        await this.#set(job.id, "MODERATING", "Running provider safety checks", 2);
        await this.#images.assertSafe(job.filteredPrompt);
        if (job.kind === "IMAGE_PREVIEW") await this.#runImagePreview(job);
        else if (job.kind === "IMAGE_UPLOAD") await this.#runImageUpload(job);
        else if (job.kind === "TEXT_TO_3D") await this.#runTextTo3D(job);
        else await this.#runImageTo3D(job);
      }
      this.#logger.info({ jobId }, "Generation job completed");
    } catch (error) {
      const pipelineError =
        error instanceof PipelineError
          ? error
          : new PipelineError("INTERNAL_ERROR", "An unexpected backend error interrupted generation", true);
      this.#logger.error({ jobId, error }, "Generation job failed");
      await this.#repository.update(job.id, {
        status: "FAILED",
        stage: "Generation failed",
        error: {
          code: pipelineError.code,
          message: pipelineError.message.slice(0, 500),
          retryable: pipelineError.retryable,
        },
      });
    }
  }

  async #runImagePreview(job: Job): Promise<void> {
    let image = job.imageArtifact;
    if (!image) {
      await this.#set(job.id, "GENERATING_IMAGE", "Creating isolated accessory reference", 10);
      image = await this.#images.generateAccessoryReference(
        job.filteredPrompt,
        job.id,
        job.stylePreset,
        job.detailLevel,
      );
      image = await sharp(image).resize(1024, 1024, { fit: "cover" }).png({ compressionLevel: 9 }).toBuffer();
      await this.#images.assertImageSafe(image);
      await this.#repository.update(job.id, { imageArtifact: image, progress: 70, stage: "Reference image ready" });
    }

    const current = await this.#requiredJob(job.id);
    let previewAssetId = current.output.previewAssetId;
    if (!previewAssetId) {
      await this.#set(job.id, "UPLOADING", "Preparing private Roblox preview", 80);
      previewAssetId = await this.#roblox.uploadImage(image, job.id, "reference");
      await this.#mergeOutput(job.id, { previewAssetId });
    }

    await this.#repository.update(job.id, {
      status: "IMAGE_READY",
      stage: "Approve or regenerate your reference",
      progress: 100,
      output: { ...(await this.#requiredJob(job.id)).output, previewAssetId },
      imageArtifact: image,
    });
  }

  async #runImageUpload(job: Job): Promise<void> {
    if (!job.sourceImageAssetId) {
      throw new PipelineError("MISSING_IMAGE_ASSET", "The custom reference has no Roblox image asset", false);
    }
    let image = job.imageArtifact;
    if (!image) {
      await this.#set(job.id, "MODERATING", "Downloading the Roblox-moderated reference", 12);
      image = await this.#robloxReferences.downloadImage(job.sourceImageAssetId);
      await this.#set(job.id, "MODERATING", "Running visual safety checks", 58);
      await this.#images.assertImageSafe(image);
      await this.#repository.update(job.id, {
        imageArtifact: image,
        progress: 84,
        stage: "Custom reference approved",
      });
    }

    await this.#repository.update(job.id, {
      status: "IMAGE_READY",
      stage: "Approve your uploaded reference",
      progress: 100,
      output: { ...(await this.#requiredJob(job.id)).output, previewAssetId: job.sourceImageAssetId },
      imageArtifact: image,
    });
  }

  async #runTextTo3D(job: Job): Promise<void> {
    const guidedPrompt = composeMeshyPrompt(job.filteredPrompt, job.stylePreset, job.detailLevel);
    let current = await this.#requiredJob(job.id);
    let previewTaskId = current.output.meshyPreviewTaskId;
    if (!previewTaskId) {
      await this.#set(job.id, "GENERATING_MESH", "Building Smart Topology geometry", 8);
      previewTaskId = await this.#meshy.createTextPreview(guidedPrompt);
      await this.#mergeOutput(job.id, { meshyPreviewTaskId: previewTaskId });
    }

    await this.#meshy.pollTextTask(previewTaskId, async (providerProgress) => {
      await this.#set(job.id, "GENERATING_MESH", "Building Smart Topology geometry", 8 + Math.floor(providerProgress * 0.34));
    });

    current = await this.#requiredJob(job.id);
    let finalTaskId = current.output.meshyFinalTaskId;
    if (!finalTaskId) {
      await this.#set(job.id, "TEXTURING", "Applying a Roblox-sized 2K texture", 45);
      finalTaskId = await this.#meshy.createTextRefine(previewTaskId, guidedPrompt);
      await this.#mergeOutput(job.id, { meshyFinalTaskId: finalTaskId });
    }

    const finalTask = await this.#meshy.pollTextTask(finalTaskId, async (providerProgress) => {
      await this.#set(job.id, "TEXTURING", "Applying a Roblox-sized 2K texture", 45 + Math.floor(providerProgress * 0.28));
    });
    await this.#finishModel(job, finalTask.model_urls?.glb, finalTask.thumbnail_url);
  }

  async #runImageTo3D(job: Job): Promise<void> {
    if (!job.sourceJobId) throw new PipelineError("MISSING_SOURCE", "Image conversion has no source job", false);
    const source = await this.#repository.get(job.sourceJobId);
    if (!source || source.playerUserId !== job.playerUserId || source.status !== "IMAGE_READY" || !source.imageArtifact) {
      throw new PipelineError("INVALID_SOURCE", "The approved reference image is unavailable", false);
    }

    await this.#images.assertImageSafe(source.imageArtifact);
    const guidedPrompt = composeMeshyPrompt(job.filteredPrompt, job.stylePreset, job.detailLevel);

    const current = await this.#requiredJob(job.id);
    let finalTaskId = current.output.meshyFinalTaskId;
    if (!finalTaskId) {
      await this.#set(job.id, "GENERATING_MESH", "Turning the approved image into Smart Topology", 8);
      finalTaskId = await this.#meshy.createImageTo3D(source.imageArtifact, "image/png", guidedPrompt);
      await this.#mergeOutput(job.id, { meshyFinalTaskId: finalTaskId });
    }

    const finalTask = await this.#meshy.pollImageTask(finalTaskId, async (providerProgress) => {
      await this.#set(
        job.id,
        "GENERATING_MESH",
        "Turning the approved image into Smart Topology",
        8 + Math.floor(providerProgress * 0.65),
      );
    });
    await this.#finishModel(job, finalTask.model_urls?.glb, finalTask.thumbnail_url);
  }

  async #finishModel(job: Job, modelUrl: string | undefined, thumbnailUrl: string | undefined): Promise<void> {
    if (!modelUrl) throw new PipelineError("MISSING_MODEL", "Meshy returned no GLB model", true);
    await this.#set(job.id, "VALIDATING", "Checking triangles, vertices, mesh count, and textures", 76);
    const rawGlb = await this.#meshy.download(modelUrl);
    const validated = await validateAndNormalizeGlb(rawGlb, this.#config);
    for (const texture of validated.textures) await this.#images.assertImageSafe(texture);
    await this.#mergeOutput(job.id, {
      triangles: validated.triangles,
      vertices: validated.vertices,
      textureWidth: validated.textureWidth,
      textureHeight: validated.textureHeight,
    });

    let preparedThumbnail: Buffer | undefined;
    if (thumbnailUrl) {
      const thumbnail = await this.#meshy.download(thumbnailUrl);
      preparedThumbnail = await sharp(thumbnail)
        .resize(512, 512, { fit: "cover" })
        .png({ compressionLevel: 9 })
        .toBuffer();
      await this.#images.assertImageSafe(preparedThumbnail);
    }

    await this.#set(job.id, "UPLOADING", "Uploading the validated model to Roblox", 88);
    const current = await this.#requiredJob(job.id);
    let modelAssetId = current.output.modelAssetId;
    if (!modelAssetId) {
      modelAssetId = await this.#roblox.uploadModel(validated.glb, job.id);
      await this.#mergeOutput(job.id, { modelAssetId });
    }

    let thumbnailAssetId = (await this.#requiredJob(job.id)).output.thumbnailAssetId;
    if (!thumbnailAssetId && preparedThumbnail) {
      thumbnailAssetId = await this.#roblox.uploadImage(preparedThumbnail, job.id, "thumbnail");
      await this.#mergeOutput(job.id, { thumbnailAssetId });
    }

    const output = (await this.#requiredJob(job.id)).output;
    await this.#repository.update(job.id, {
      status: "SUCCEEDED",
      stage: "Ready to fit",
      progress: 100,
      output: { ...output, modelAssetId, ...(thumbnailAssetId ? { thumbnailAssetId } : {}) },
    });
  }

  async #runMock(job: Job): Promise<void> {
    await delay(40);
    if (job.kind === "IMAGE_PREVIEW" || job.kind === "IMAGE_UPLOAD") {
      const image = Buffer.from(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFhQGAWvBFPQAAAABJRU5ErkJggg==",
        "base64",
      );
      await this.#repository.update(job.id, {
        status: "IMAGE_READY",
        stage: "Mock reference ready",
        progress: 100,
        output: { previewAssetId: job.sourceImageAssetId ?? 0 },
        imageArtifact: image,
      });
      return;
    }
    await this.#repository.update(job.id, {
      status: "SUCCEEDED",
      stage: "Mock model ready",
      progress: 100,
      output: { modelAssetId: 0, thumbnailAssetId: 0, triangles: 3600, vertices: 2400 },
    });
  }

  async #set(jobId: string, status: Job["status"], stage: string, progress: number): Promise<void> {
    await this.#repository.update(jobId, { status, stage, progress: Math.max(0, Math.min(100, progress)) });
  }

  async #mergeOutput(jobId: string, patch: JobOutput): Promise<void> {
    const current = await this.#requiredJob(jobId);
    await this.#repository.update(jobId, { output: { ...current.output, ...patch } });
  }

  async #requiredJob(jobId: string): Promise<Job> {
    const job = await this.#repository.get(jobId);
    if (!job) throw new PipelineError("JOB_LOST", "Generation job no longer exists", true);
    return job;
  }
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
