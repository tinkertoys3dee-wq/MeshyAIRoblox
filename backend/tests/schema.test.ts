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

  it("rejects unsupported accessory types", () => {
    expect(createJobSchema.safeParse({ ...base, kind: "TEXT_TO_3D", accessoryType: "Weapon" }).success).toBe(false);
  });
});
