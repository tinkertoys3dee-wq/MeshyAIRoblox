import sharp from "sharp";
import { PipelineError, type AvatarView } from "../types.js";

const MAX_DOWNLOAD_BYTES = 8 * 1024 * 1024;
const MAX_INPUT_PIXELS = 16_777_216;

// Matches Config.Generation.AvatarViews' Endpoint values in the Roblox game
// (src/Shared/Config.luau) -- the two must stay in sync, since the Roblox
// server sends only the view id, and this backend is the one that resolves
// it into the actual Thumbnails API path.
const AVATAR_THUMBNAIL_ENDPOINT: Readonly<Record<AvatarView, string>> = Object.freeze({
  HEADSHOT: "avatar-headshot",
  BUST: "avatar-bust",
  FULL_BODY: "avatar",
});

type ThumbnailResponse = {
  data?: Array<{
    targetId?: number;
    state?: string;
    imageUrl?: string;
  }>;
};

export class RobloxReferenceClient {
  async downloadImage(assetId: number): Promise<Buffer> {
    const metadataUrl = new URL("https://thumbnails.roblox.com/v1/assets");
    metadataUrl.searchParams.set("assetIds", String(assetId));
    metadataUrl.searchParams.set("returnPolicy", "PlaceHolder");
    metadataUrl.searchParams.set("size", "420x420");
    metadataUrl.searchParams.set("format", "Png");
    metadataUrl.searchParams.set("isCircular", "false");
    return this.#resolveAndDownload(metadataUrl, assetId);
  }

  // The Roblox server cannot resolve this itself: HttpService is blocked
  // from reaching Roblox-owned domains (thumbnails.roblox.com included),
  // so it sends only the player's userId (already on every job, see
  // BackendService:CreateJob) and their chosen avatarView, and this
  // backend -- outside Roblox's sandbox -- does the lookup instead.
  async downloadAvatarImage(userId: number, avatarView: AvatarView): Promise<Buffer> {
    const endpoint = AVATAR_THUMBNAIL_ENDPOINT[avatarView];
    const metadataUrl = new URL(`https://thumbnails.roblox.com/v1/users/${endpoint}`);
    metadataUrl.searchParams.set("userIds", String(userId));
    metadataUrl.searchParams.set("size", "420x420");
    metadataUrl.searchParams.set("format", "Png");
    metadataUrl.searchParams.set("isCircular", "false");
    return this.#resolveAndDownload(metadataUrl, userId);
  }

  async #resolveAndDownload(metadataUrl: URL, targetId: number): Promise<Buffer> {
    const metadataResponse = await fetchWithTimeout(metadataUrl, { redirect: "error" }, 15_000);
    if (!metadataResponse.ok) {
      throw new PipelineError(
        "ROBLOX_IMAGE_UNAVAILABLE",
        `Roblox thumbnail lookup returned ${metadataResponse.status}`,
        metadataResponse.status === 429 || metadataResponse.status >= 500,
      );
    }
    const payload = (await metadataResponse.json()) as ThumbnailResponse;
    const thumbnail = payload.data?.find((entry) => entry.targetId === targetId) ?? payload.data?.[0];
    if (!thumbnail || thumbnail.state !== "Completed" || !thumbnail.imageUrl) {
      throw new PipelineError(
        "ROBLOX_IMAGE_NOT_READY",
        "The Roblox image is still pending, blocked, or unavailable",
        thumbnail?.state === "Pending" || thumbnail?.state === "InReview",
      );
    }

    const imageUrl = new URL(thumbnail.imageUrl);
    assertRobloxCdn(imageUrl);
    // Do not follow even a Roblox-hosted redirect: validating only after a
    // redirect would allow the first host to steer this server elsewhere.
    const imageResponse = await fetchWithTimeout(imageUrl, { redirect: "error" }, 30_000);
    if (!imageResponse.ok) {
      throw new PipelineError(
        "ROBLOX_IMAGE_DOWNLOAD_FAILED",
        `Roblox image download returned ${imageResponse.status}`,
        imageResponse.status === 429 || imageResponse.status >= 500,
      );
    }
    assertRobloxCdn(new URL(imageResponse.url));
    const declaredLength = Number(imageResponse.headers.get("content-length") ?? 0);
    if (declaredLength > MAX_DOWNLOAD_BYTES) {
      throw new PipelineError("REFERENCE_IMAGE_TOO_LARGE", "The reference image exceeded the size limit", false);
    }
    const raw = Buffer.from(await imageResponse.arrayBuffer());
    if (raw.length === 0 || raw.length > MAX_DOWNLOAD_BYTES) {
      throw new PipelineError("REFERENCE_IMAGE_TOO_LARGE", "The reference image was empty or too large", false);
    }

    try {
      const source = sharp(raw, { animated: false, failOn: "error", limitInputPixels: MAX_INPUT_PIXELS });
      const metadata = await source.metadata();
      if (!metadata.width || !metadata.height || metadata.width < 128 || metadata.height < 128) {
        throw new PipelineError(
          "REFERENCE_IMAGE_TOO_SMALL",
          "The reference image must be at least 128 pixels in both dimensions",
          false,
        );
      }
      return await source
        .rotate()
        .resize(1024, 1024, {
          fit: "contain",
          background: { r: 245, g: 246, b: 250, alpha: 1 },
        })
        .flatten({ background: { r: 245, g: 246, b: 250 } })
        .png({ compressionLevel: 9 })
        .toBuffer();
    } catch (error) {
      if (error instanceof PipelineError) throw error;
      throw new PipelineError("REFERENCE_IMAGE_INVALID", "The Roblox asset was not a valid still image", false);
    }
  }
}

function assertRobloxCdn(url: URL): void {
  const host = url.hostname.toLowerCase();
  if (url.protocol !== "https:" || (host !== "rbxcdn.com" && !host.endsWith(".rbxcdn.com"))) {
    throw new PipelineError("ROBLOX_IMAGE_URL_REJECTED", "Roblox returned an unexpected image host", false);
  }
}

async function fetchWithTimeout(url: URL, init: RequestInit, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } catch (error) {
    throw new PipelineError(
      "ROBLOX_IMAGE_NETWORK_ERROR",
      error instanceof Error ? error.message : "Roblox image request failed",
      true,
    );
  } finally {
    clearTimeout(timer);
  }
}
