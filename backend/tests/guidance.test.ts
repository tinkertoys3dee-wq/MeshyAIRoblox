import { describe, expect, it } from "vitest";
import { accessoryIsolationGuidance, composeMeshyPrompt, detailGuidance, styleGuidance } from "../src/guidance.js";

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

  it("describes every accessory type distinctly", () => {
    expect(accessoryIsolationGuidance("Hat")).toContain("a hat");
    expect(accessoryIsolationGuidance("FaceAccessory")).toContain("glasses or a mask");
    expect(accessoryIsolationGuidance("BackAccessory")).toContain("wings");
  });

  it("falls back to a generic accessory description when the type is missing", () => {
    expect(accessoryIsolationGuidance(undefined)).toContain("a single wearable accessory");
  });
});
