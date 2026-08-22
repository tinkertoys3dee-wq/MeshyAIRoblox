import type { DetailLevel, StylePreset } from "./types.js";

const STYLE_GUIDANCE: Record<StylePreset, string> = {
  AUTO: "a cohesive premium game-asset style chosen to suit the object",
  ANIME: "anime-inspired proportions, crisp cel-shaded color blocking, and bold readable shapes",
  REALISTIC: "realistic proportions, physically plausible materials, and refined natural surface definition",
  STYLIZED: "polished stylized game-asset forms, an expressive silhouette, and a handcrafted finish",
  LOW_POLY: "intentional low-poly faceting, simplified connected geometry, and graphic color blocks",
  FANTASY: "ornate fantasy design language, magical materials, and a dramatic but wearable silhouette",
};

const DETAIL_GUIDANCE: Record<DetailLevel, string> = {
  CLEAN: "Use clean broad forms with minimal ornament and an exceptionally clear silhouette",
  BALANCED: "Balance readable primary forms with selective secondary detail",
  INTRICATE:
    "Create rich perceived surface detail through texture and broad relief while keeping the geometry connected and efficient",
};

export function styleGuidance(stylePreset: StylePreset): string {
  return STYLE_GUIDANCE[stylePreset];
}

export function detailGuidance(detailLevel: DetailLevel): string {
  return DETAIL_GUIDANCE[detailLevel];
}

export function composeMeshyPrompt(
  filteredPrompt: string,
  stylePreset: StylePreset,
  detailLevel: DetailLevel,
): string {
  const suffix = ` Style direction: ${styleGuidance(stylePreset)}. Detail direction: ${detailGuidance(detailLevel)}.`;
  const maximumLength = 600;
  const description = filteredPrompt.slice(0, Math.max(1, maximumLength - suffix.length)).trimEnd();
  return `${description}${suffix}`;
}
