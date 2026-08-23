import type { AppConfig } from "../config.js";
import { PipelineError } from "../types.js";

type MeshyTask = {
  id: string;
  status: "PENDING" | "IN_PROGRESS" | "SUCCEEDED" | "FAILED" | "CANCELED";
  progress?: number;
  model_urls?: { glb?: string };
  thumbnail_url?: string;
  alpha_thumbnail_url?: string;
  task_error?: { message?: string };
};

export class MeshyClient {
  readonly #config: AppConfig["meshy"];
  readonly #targetTriangles: number;

  constructor(config: AppConfig) {
    this.#config = config.meshy;
    this.#targetTriangles = config.limits.targetTriangles;
  }

  async createTextPreview(filteredPrompt: string): Promise<string> {
    return this.#create("/openapi/v2/text-to-3d", {
      mode: "preview",
      prompt: filteredPrompt,
      model_type: "smart-topology",
      ai_model: "meshy-t2",
      topology: "triangle",
      target_polycount: this.#targetTriangles,
      moderation: true,
      target_formats: ["glb"],
      alpha_thumbnail: true,
      auto_size: false,
    });
  }

  async createTextRefine(previewTaskId: string, filteredPrompt: string): Promise<string> {
    return this.#create("/openapi/v2/text-to-3d", {
      mode: "refine",
      preview_task_id: previewTaskId,
      texture_prompt: filteredPrompt,
      enable_pbr: false,
      texture_resolution: "2k",
      moderation: true,
      target_formats: ["glb"],
      alpha_thumbnail: true,
      auto_size: false,
    });
  }

  async createImageTo3D(image: Buffer, mimeType: "image/png" | "image/jpeg", filteredPrompt: string): Promise<string> {
    const imageUrl = `data:${mimeType};base64,${image.toString("base64")}`;
    return this.#create("/openapi/v1/image-to-3d", {
      image_url: imageUrl,
      model_type: "smart-topology",
      ai_model: "meshy-t2",
      target_polycount: this.#targetTriangles,
      should_texture: true,
      enable_pbr: false,
      texture_resolution: "2k",
      texture_prompt: filteredPrompt,
      moderation: true,
      target_formats: ["glb"],
      alpha_thumbnail: true,
      auto_size: false,
    });
  }

  async pollTextTask(taskId: string, onProgress: (progress: number) => Promise<void>): Promise<MeshyTask> {
    return this.#poll(`/openapi/v2/text-to-3d/${encodeURIComponent(taskId)}`, onProgress);
  }

  async pollImageTask(taskId: string, onProgress: (progress: number) => Promise<void>): Promise<MeshyTask> {
    return this.#poll(`/openapi/v1/image-to-3d/${encodeURIComponent(taskId)}`, onProgress);
  }

  async download(url: string): Promise<Buffer> {
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        const response = await fetchWithTimeout(url, {}, 120_000);
        if (!response.ok) {
          const retryable = response.status === 408 || response.status === 429 || response.status >= 500;
          throw new PipelineError(
            "PROVIDER_DOWNLOAD_FAILED",
            `Meshy artifact download returned ${response.status}`,
            retryable,
          );
        }
        return Buffer.from(await response.arrayBuffer());
      } catch (error) {
        const downloadError =
          error instanceof PipelineError
            ? error
            : new PipelineError(
                "PROVIDER_DOWNLOAD_FAILED",
                error instanceof Error ? error.message : "Meshy artifact download failed",
                true,
              );
        if (!downloadError.retryable || attempt === 3) throw downloadError;
        await delay(500 * attempt);
      }
    }
    throw new PipelineError("PROVIDER_DOWNLOAD_FAILED", "Meshy artifact download failed", true);
  }

  async #create(path: string, body: Record<string, unknown>): Promise<string> {
    const response = await this.#request(path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    const payload = (await response.json()) as { result?: string; message?: string };
    if (!payload.result) {
      throw new PipelineError("PROVIDER_BAD_RESPONSE", payload.message ?? "Meshy did not return a task ID", true);
    }
    return payload.result;
  }

  async #poll(path: string, onProgress: (progress: number) => Promise<void>): Promise<MeshyTask> {
    const deadline = Date.now() + this.#config.timeoutMs;
    let previousProgress = -1;
    let consecutiveRequestFailures = 0;

    while (Date.now() < deadline) {
      let task: MeshyTask;
      try {
        const response = await this.#request(path, { method: "GET" });
        task = (await response.json()) as MeshyTask;
        consecutiveRequestFailures = 0;
      } catch (error) {
        const requestError =
          error instanceof PipelineError
            ? error
            : new PipelineError(
                "PROVIDER_BAD_RESPONSE",
                error instanceof Error ? error.message : "Meshy returned an unreadable task response",
                true,
              );
        if (!requestError.retryable) throw requestError;
        consecutiveRequestFailures += 1;
        if (consecutiveRequestFailures >= 4) throw requestError;
        await delay(Math.min(this.#config.pollIntervalMs, 500 * 2 ** (consecutiveRequestFailures - 1)));
        continue;
      }
      const progress = Math.max(0, Math.min(100, Math.floor(task.progress ?? 0)));
      if (progress !== previousProgress) {
        previousProgress = progress;
        await onProgress(progress);
      }

      if (task.status === "SUCCEEDED") return task;
      if (task.status === "FAILED" || task.status === "CANCELED") {
        throw new PipelineError(
          "MESHY_TASK_FAILED",
          task.task_error?.message ?? `Meshy task ended with ${task.status}`,
          false,
        );
      }
      await delay(this.#config.pollIntervalMs);
    }

    throw new PipelineError("MESHY_TIMEOUT", "Meshy generation exceeded the configured timeout", true);
  }

  async #request(path: string, init: RequestInit): Promise<Response> {
    const response = await fetchWithTimeout(
      `${this.#config.baseUrl}${path}`,
      {
        ...init,
        headers: {
          authorization: `Bearer ${this.#config.apiKey}`,
          ...init.headers,
        },
      },
      30_000,
    );
    if (!response.ok) {
      const body = (await response.text()).slice(0, 500);
      const retryable = response.status === 408 || response.status === 429 || response.status >= 500;
      throw new PipelineError("MESHY_HTTP_ERROR", `Meshy returned ${response.status}: ${body}`, retryable);
    }
    return response;
  }
}

async function fetchWithTimeout(url: string, init: RequestInit, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } catch (error) {
    throw new PipelineError("PROVIDER_NETWORK_ERROR", error instanceof Error ? error.message : "Provider request failed", true);
  } finally {
    clearTimeout(timer);
  }
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
