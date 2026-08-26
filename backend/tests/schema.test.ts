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

  it("accepts an approved Roblox preview as an image-conversion recovery source", () => {
    const conversion = createJobSchema.safeParse({
      ...base,
      kind: "IMAGE_TO_3D",
      sourceJobId: "11111111-1111-4111-8111-111111111111",
      sourceImageAssetId: 1234567890,
    });
    expect(conversion.success).toBe(true);
  });

  it("rejects unrecognized style and detail controls", () => {
    expect(createJobSchema.safeParse({ ...base, kind: "TEXT_TO_3D", stylePreset: "PHOTOCOPY" }).success).toBe(false);
    expect(createJobSchema.safeParse({ ...base, kind: "TEXT_TO_3D", detailLevel: "UNLIMITED" }).success).toBe(false);
  });

  it("rejects unsupported accessory types", () => {
    expect(createJobSchema.safeParse({ ...base, kind: "TEXT_TO_3D", accessoryType: "Weapon" }).success).toBe(false);
  });

  it("accepts an avatar view only for AVATAR_TO_3D", () => {
    expect(createJobSchema.safeParse({ ...base, kind: "AVATAR_TO_3D", avatarView: "HEADSHOT" }).success).toBe(true);
    expect(createJobSchema.safeParse({ ...base, kind: "AVATAR_TO_3D", avatarView: "BUST" }).success).toBe(true);
    expect(createJobSchema.safeParse({ ...base, kind: "AVATAR_TO_3D", avatarView: "FULL_BODY" }).success).toBe(true);
    expect(createJobSchema.safeParse({ ...base, kind: "AVATAR_TO_3D" }).success).toBe(false);
    expect(createJobSchema.safeParse({ ...base, kind: "TEXT_TO_3D", avatarView: "HEADSHOT" }).success).toBe(false);
    expect(createJobSchema.safeParse({ ...base, kind: "AVATAR_TO_3D", avatarView: "PROFILE" }).success).toBe(false);
  });

  it("accepts an image quality tier only for IMAGE_PREVIEW or AVATAR_GRAPHIC", () => {
    expect(createJobSchema.safeParse({ ...base, kind: "IMAGE_PREVIEW", imageQuality: "medium" }).success).toBe(true);
    expect(createJobSchema.safeParse({ ...base, kind: "IMAGE_PREVIEW", imageQuality: "high" }).success).toBe(true);
    expect(createJobSchema.safeParse({ ...base, kind: "TEXT_TO_3D", imageQuality: "high" }).success).toBe(false);
    expect(
      createJobSchema.safeParse({ ...base, kind: "IMAGE_PREVIEW", imageQuality: "ultra" }).success,
    ).toBe(false);
    const graphic = { ...base, accessoryType: undefined, kind: "AVATAR_GRAPHIC", avatarView: "BUST" };
    expect(createJobSchema.safeParse({ ...graphic, imageQuality: "high" }).success).toBe(true);
  });

  it("requires an avatar view for AVATAR_GRAPHIC and forbids an accessory type", () => {
    const graphic = { ...base, accessoryType: undefined, kind: "AVATAR_GRAPHIC" };
    expect(createJobSchema.safeParse(graphic).success).toBe(false);
    expect(createJobSchema.safeParse({ ...graphic, avatarView: "FULL_BODY" }).success).toBe(true);
    expect(createJobSchema.safeParse({ ...graphic, avatarView: "FULL_BODY", accessoryType: "Hat" }).success).toBe(
      false,
    );
  });
});
