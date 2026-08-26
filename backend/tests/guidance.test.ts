import { describe, expect, it } from "vitest";
import { composeMeshyPrompt, detailGuidance, styleGuidance } from "../src/guidance.js";

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
});
