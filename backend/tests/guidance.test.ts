import { describe, expect, it } from "vitest";
import { composeAvatarMeshyPrompt, composeMeshyPrompt, detailGuidance, styleGuidance } from "../src/guidance.js";

describe("generation guidance", () => {
  it("adds deterministic style and detail guidance", () => {
    const prompt = composeMeshyPrompt("A moon crown", "ANIME", "INTRICATE");
    expect(prompt).toContain("anime-inspired");
    expect(prompt).toContain("rich perceived surface detail");
  });

  it("keeps Meshy prompts within its texture prompt limit", () => {
    const prompt = composeMeshyPrompt("x".repeat(500), "REALISTIC", "BALANCED");
    expect(prompt.length).toBeLessThanOrEqual(600);
  });

  it("defines every user-facing extreme without provider-only magic values", () => {
    expect(styleGuidance("LOW_POLY")).toContain("low-poly");
    expect(detailGuidance("CLEAN")).toContain("minimal ornament");
  });

  it("tells Meshy to isolate a single accessory from the avatar photo, not the whole figure", () => {
    const prompt = composeAvatarMeshyPrompt("Hat", "Match my avatar's style", "AUTO", "BALANCED");
    expect(prompt).toContain("a hat");
    expect(prompt).toContain("not a full body, head, or character");
    expect(prompt).toContain("Match my avatar's style");
  });

  it("names each accessory type distinctly in the avatar framing instruction", () => {
    expect(composeAvatarMeshyPrompt("BackAccessory", "x", "AUTO", "BALANCED")).toContain("backpack or cape");
    expect(composeAvatarMeshyPrompt("WaistAccessory", "x", "AUTO", "BALANCED")).toContain("belt");
  });

  it("keeps avatar-framed Meshy prompts within the texture prompt limit too", () => {
    const prompt = composeAvatarMeshyPrompt("Hat", "x".repeat(500), "REALISTIC", "BALANCED");
    expect(prompt.length).toBeLessThanOrEqual(600);
  });
});
