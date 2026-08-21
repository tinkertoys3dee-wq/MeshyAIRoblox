import type { AppConfig } from "../config.js";
import { PipelineError } from "../types.js";

type AssetType = "Model" | "Image";
type Operation = {
  path?: string;
  done?: boolean;
  error?: { message?: string };
  response?: { assetId?: string | number };
};

export class RobloxAssetClient {
  readonly #config: AppConfig["roblox"];
  readonly #creator: { groupId: string } | { userId: string };

  constructor(config: AppConfig) {
    this.#config = config.roblox;
    this.#creator =
      config.roblox.creatorType === "group"
        ? { groupId: String(config.roblox.creatorId) }
        : { userId: String(config.roblox.creatorId) };
  }

  async uploadModel(data: Buffer, jobId: string): Promise<number> {
    return this.#upload("Model", data, "model/gltf-binary", `forge-${jobId}.glb`, jobId);
  }

  async uploadImage(data: Buffer, jobId: string, purpose: string): Promise<number> {
    return this.#upload("Image", data, "image/png", `forge-${purpose}-${jobId}.png`, jobId);
  }

  async #upload(
    assetType: AssetType,
    data: Buffer,
    mimeType: string,
    fileName: string,
    jobId: string,
  ): Promise<number> {
    const form = new FormData();
    form.append(
      "request",
      JSON.stringify({
        assetType,
        displayName: `Forge UGC ${assetType} ${jobId.slice(0, 8)}`,
        description: "Generated and validated by the Forge UGC experience.",
        creationContext: { creator: this.#creator },
      }),
    );
    form.append("fileContent", new Blob([new Uint8Array(data)], { type: mimeType }), fileName);

    const response = await this.#fetch("https://apis.roblox.com/assets/v1/assets", {
      method: "POST",
      headers: { "x-api-key": this.#config.apiKey },
      body: form,
    });
    const operation = (await response.json()) as Operation;
    if (!operation.path) throw new PipelineError("ROBLOX_UPLOAD_BAD_RESPONSE", "Roblox returned no operation path", true);
    return this.#pollOperation(operation.path);
  }

  async #pollOperation(path: string): Promise<number> {
    const deadline = Date.now() + this.#config.assetTimeoutMs;
    const url = `https://apis.roblox.com/assets/v1/${path.replace(/^\//, "")}`;
    while (Date.now() < deadline) {
      const response = await this.#fetch(url, { headers: { "x-api-key": this.#config.apiKey } });
      const operation = (await response.json()) as Operation;
      if (operation.done) {
        if (operation.error) {
          throw new PipelineError(
            "ROBLOX_UPLOAD_FAILED",
            operation.error.message ?? "Roblox rejected the asset upload",
            false,
          );
        }
        const assetId = Number(operation.response?.assetId);
        if (!Number.isSafeInteger(assetId) || assetId <= 0) {
          throw new PipelineError("ROBLOX_UPLOAD_BAD_RESPONSE", "Roblox operation returned no asset ID", true);
        }
        return assetId;
      }
      await delay(2000);
    }
    throw new PipelineError("ROBLOX_UPLOAD_TIMEOUT", "Roblox asset processing timed out", true);
  }

  async #fetch(url: string, init: RequestInit): Promise<Response> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 45_000);
    try {
      const response = await fetch(url, { ...init, signal: controller.signal });
      if (!response.ok) {
        const body = (await response.text()).slice(0, 500);
        const retryable = response.status === 408 || response.status === 429 || response.status >= 500;
        throw new PipelineError("ROBLOX_HTTP_ERROR", `Roblox returned ${response.status}: ${body}`, retryable);
      }
      return response;
    } catch (error) {
      if (error instanceof PipelineError) throw error;
      throw new PipelineError("ROBLOX_NETWORK_ERROR", error instanceof Error ? error.message : "Roblox request failed", true);
    } finally {
      clearTimeout(timer);
    }
  }
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
