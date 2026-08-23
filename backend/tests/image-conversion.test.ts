import { describe, expect, it, vi } from "vitest";
import { resolveApprovedReferenceImage } from "../src/pipeline.js";
import type { Job } from "../src/types.js";

const sourceId = "11111111-1111-4111-8111-111111111111";

function makeJob(overrides: Partial<Job> = {}): Job {
  return {
    id: "22222222-2222-4222-8222-222222222222",
    requestId: "conversion_request_12345",
    playerUserId: 123,
    kind: "IMAGE_TO_3D",
    status: "QUEUED",
    stage: "Waiting for a worker",
    progress: 0,
    filteredPrompt: "A polished silver crown",
    accessoryType: "Hat",
    stylePreset: "AUTO",
    detailLevel: "BALANCED",
    sourceJobId: sourceId,
    priority: false,
    context: { universeId: 1, placeId: 2, gameJobId: "server" },
    output: {},
    createdAt: new Date("2026-01-01T00:00:00Z"),
    updatedAt: new Date("2026-01-01T00:00:00Z"),
    ...overrides,
  };
}

describe("resolveApprovedReferenceImage", () => {
  it("uses the IMAGE_READY source artifact without downloading it again", async () => {
    const image = Buffer.from("approved-reference");
    const source = makeJob({
      id: sourceId,
      requestId: "preview_request_12345",
      kind: "IMAGE_PREVIEW",
      status: "IMAGE_READY",
      imageArtifact: image,
    });
    const repository = { get: vi.fn(async () => source) };
    const references = { downloadImage: vi.fn(async () => Buffer.from("fallback")) };

    await expect(resolveApprovedReferenceImage(makeJob(), repository, references)).resolves.toEqual({
      image,
      recoveredFromRoblox: false,
    });
    expect(references.downloadImage).not.toHaveBeenCalled();
  });

  it("recovers an approved preview from Roblox when the source job expired", async () => {
    const image = Buffer.from("roblox-recovery");
    const repository = { get: vi.fn(async () => undefined) };
    const references = { downloadImage: vi.fn(async () => image) };

    await expect(
      resolveApprovedReferenceImage(makeJob({ sourceImageAssetId: 987654321 }), repository, references),
    ).resolves.toEqual({ image, recoveredFromRoblox: true });
    expect(references.downloadImage).toHaveBeenCalledWith(987654321);
  });

  it("never uses the fallback to bypass source ownership", async () => {
    const source = makeJob({
      id: sourceId,
      requestId: "other_preview_12345",
      playerUserId: 456,
      kind: "IMAGE_PREVIEW",
      status: "IMAGE_READY",
    });
    const repository = { get: vi.fn(async () => source) };
    const references = { downloadImage: vi.fn(async () => Buffer.from("fallback")) };

    await expect(
      resolveApprovedReferenceImage(makeJob({ sourceImageAssetId: 987654321 }), repository, references),
    ).rejects.toMatchObject({ code: "INVALID_SOURCE", retryable: false });
    expect(references.downloadImage).not.toHaveBeenCalled();
  });
});
