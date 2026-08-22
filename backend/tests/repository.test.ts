import { describe, expect, it } from "vitest";
import { MemoryJobRepository } from "../src/repository.js";

const input = {
  requestId: "request_123456789",
  playerUserId: 123,
  kind: "TEXT_TO_3D" as const,
  filteredPrompt: "A polished silver crown",
  accessoryType: "Hat" as const,
  stylePreset: "ANIME" as const,
  detailLevel: "INTRICATE" as const,
  priority: false,
  context: { universeId: 1, placeId: 2, gameJobId: "server" },
};

describe("MemoryJobRepository", () => {
  it("is idempotent by Roblox request ID", async () => {
    const repository = new MemoryJobRepository();
    const first = await repository.create(input);
    const second = await repository.create(input);
    expect(second.id).toBe(first.id);
  });

  it("does not expose mutable stored state", async () => {
    const repository = new MemoryJobRepository();
    const created = await repository.create(input);
    created.output.modelAssetId = 99;
    expect((await repository.get(created.id))?.output.modelAssetId).toBeUndefined();
  });

  it("persists immutable art-direction parameters", async () => {
    const repository = new MemoryJobRepository();
    const created = await repository.create(input);
    expect(created).toMatchObject({ stylePreset: "ANIME", detailLevel: "INTRICATE" });
  });
});
