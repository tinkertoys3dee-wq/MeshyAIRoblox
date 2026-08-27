import { describe, expect, it } from "vitest";
import {
  accessoryIsolationGuidance,
  composeMeshyPrompt,
  composeTextToImagePrompt,
  detailGuidance,
  styleGuidance,
} from "../src/guidance.js";

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

  it("keeps Meshy prompts within limit even with the longest isolation guidance", () => {
    const prompt = composeMeshyPrompt("x".repeat(500), "REALISTIC", "INTRICATE", "HairAccessory");
    expect(prompt.length).toBeLessThanOrEqual(600);
  });

  it("defines every user-facing extreme without provider-only magic values", () => {
    expect(styleGuidance("LOW_POLY")).toContain("low-poly");
    expect(detailGuidance("CLEAN")).toContain("minimal ornament");
  });

  // Regression test: a short prompt like "cool anime hair" with no isolation
  // guidance was completed by Meshy into a whole anime character wearing
  // that hair, instead of an isolated hair accessory mesh.
  it("steers every generation toward one isolated accessory, never a whole character", () => {
    const prompt = composeMeshyPrompt("cool anime hair", "ANIME", "BALANCED", "HairAccessory");
    expect(prompt).toContain("hair accessory (hair only)");
    expect(prompt).toContain("no head, face, body, full character, mannequin, or other body part");
  });

  // The isolation instruction leads the prompt rather than only trailing it:
  // Meshy's shape-defining `prompt` field is what a long, buried instruction
  // is easiest to lose track of, and it's also the first thing the model
  // reads. It's repeated briefly at the end too, for reinforcement.
  it("puts the isolation instruction before the player's own words, and repeats it at the end", () => {
    const prompt = composeMeshyPrompt("cool anime hair", "ANIME", "BALANCED", "HairAccessory");
    const isolationIndex = prompt.indexOf("A single isolated 3D asset");
    const descriptionIndex = prompt.indexOf("cool anime hair");
    expect(isolationIndex).toBe(0);
    expect(descriptionIndex).toBeGreaterThan(isolationIndex);
    expect(prompt).toMatch(/Reminder: isolated .* only, nothing else\.$/);
  });

  it("describes every accessory type distinctly", () => {
    expect(accessoryIsolationGuidance("Hat")).toContain("a hat");
    expect(accessoryIsolationGuidance("FaceAccessory")).toContain("glasses or a mask");
    expect(accessoryIsolationGuidance("BackAccessory")).toContain("wings");
  });

  it("falls back to a generic accessory description when the type is missing", () => {
    expect(accessoryIsolationGuidance(undefined)).toContain("a single wearable accessory");
  });

  it("builds a text-to-image prompt with style/detail guidance and the player's description", () => {
    const prompt = composeTextToImagePrompt("a neon city skyline at dusk", "ANIME", "INTRICATE");
    expect(prompt).toContain("anime-inspired");
    expect(prompt).toContain("rich perceived surface detail");
    expect(prompt).toContain("a neon city skyline at dusk");
    expect(prompt).not.toContain("isolated 3D asset");
    expect(prompt).not.toContain("reference image");
  });
});
