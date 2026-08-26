import type { AccessoryType, DetailLevel, StylePreset } from "./types.js";

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

const ACCESSORY_PROMPT_LABEL: Record<AccessoryType, string> = {
  Hat: "a hat",
  HairAccessory: "a hair accessory",
  FaceAccessory: "a face accessory such as glasses or a mask",
  NeckAccessory: "a neck accessory such as a necklace or scarf",
  ShoulderAccessory: "a shoulder-mounted accessory such as an epaulette or shoulder pad",
  FrontAccessory: "a chest-mounted front accessory",
  BackAccessory: "a back-mounted accessory such as a backpack or cape",
  WaistAccessory: "a waist accessory such as a belt",
};

// Every other image-sourced job kind (IMAGE_PREVIEW, IMAGE_UPLOAD,
// IMAGE_TO_3D) already hands Meshy an isolated photo of just the accessory
// itself, so filteredPrompt alone is enough context. AVATAR_TO_3D is
// different: its source image is a photo of the player's *whole* avatar,
// and accessoryType is otherwise never mentioned to Meshy at all (it's
// purely Roblox-side fit-region metadata for every other kind). Without an
// explicit instruction to extract a single standalone accessory, Meshy has
// no reason not to model the whole figure in the photo -- which then gets
// scaled and positioned as if it were a small accessory, producing a tiny,
// misshapen result.
export function composeAvatarMeshyPrompt(
  accessoryType: AccessoryType,
  filteredPrompt: string,
  stylePreset: StylePreset,
  detailLevel: DetailLevel,
): string {
  const framing = `Design ${ACCESSORY_PROMPT_LABEL[accessoryType]} as a single standalone wearable game accessory, not a full body, head, or character. Take creative inspiration only from the reference image's colors, materials, and visual style. ${filteredPrompt}`;
  return composeMeshyPrompt(framing, stylePreset, detailLevel);
}
