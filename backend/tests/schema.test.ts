import { describe, expect, it } from "vitest";
import { createJobSchema } from "../src/types.js";

const base = {
  requestId: "request_123456789",
  playerUserId: 123,
  filteredPrompt: "A polished silver crown",
  accessoryType: "Hat",
  priority: false,
  context: { universeId: 1, placeId: 2, gameJobId: "server" },
};

describe("createJobSchema", () => {
  it("requires a source image job for image conversion", () => {
    expect(createJobSchema.safeParse({ ...base, kind: "IMAGE_TO_3D" }).success).toBe(false);
  });

  it("accepts filtered text-to-3D requests", () => {
    expect(createJobSchema.safeParse({ ...base, kind: "TEXT_TO_3D" }).success).toBe(true);
  });

  it("accepts a custom Roblox image only for the upload job kind", () => {
    const upload = createJobSchema.safeParse({
      ...base,
      kind: "IMAGE_UPLOAD",
      sourceImageAssetId: 1234567890,
      stylePreset: "REALISTIC",
      detailLevel: "INTRICATE",
    });
    expect(upload.success).toBe(true);
    expect(createJobSchema.safeParse({ ...base, kind: "TEXT_TO_3D", sourceImageAssetId: 123 }).success).toBe(false);
  });

  it("rejects unrecognized style and detail controls", () => {
    expect(createJobSchema.safeParse({ ...base, kind: "TEXT_TO_3D", stylePreset: "PHOTOCOPY" }).success).toBe(false);
    expect(createJobSchema.safeParse({ ...base, kind: "TEXT_TO_3D", detailLevel: "UNLIMITED" }).success).toBe(false);
  });

  it("rejects unsupported accessory types", () => {
    expect(createJobSchema.safeParse({ ...base, kind: "TEXT_TO_3D", accessoryType: "Weapon" }).success).toBe(false);
  });
});
