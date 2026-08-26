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

// A short, plain description of what should be modeled -- deliberately never
// implying a wearer. Without this, a short prompt like "cool anime hair" has
// nothing telling Meshy to stop at the hair: left to its own defaults it
// reasonably completes that into a whole anime character wearing that hair,
// since "an isolated hair-only mesh" isn't the only plausible reading of the
// words alone. This is what composeMeshyPrompt appends to steer every
// generation back to a single standalone accessory.
const ACCESSORY_ISOLATION_DESCRIPTION: Record<AccessoryType, string> = {
  Hat: "a hat",
  HairAccessory: "a hair accessory (hair only)",
  FaceAccessory: "a face accessory such as glasses or a mask",
  NeckAccessory: "a neck accessory such as a necklace, collar, or scarf",
  ShoulderAccessory: "a shoulder accessory such as an epaulette or shoulder guard",
  FrontAccessory: "a front-torso accessory such as a badge or chest emblem",
  BackAccessory: "a back accessory such as wings, a backpack, or a cape",
  WaistAccessory: "a waist accessory such as a belt or sash",
};

export function accessoryIsolationGuidance(accessoryType?: AccessoryType): string {
  const description = accessoryType ? ACCESSORY_ISOLATION_DESCRIPTION[accessoryType] : "a single wearable accessory";
  return `Model ONLY ${description}, as one standalone object -- no head, face, body, full character, mannequin, or other body part.`;
}

export function styleGuidance(stylePreset: StylePreset): string {
  return STYLE_GUIDANCE[stylePreset];
}

export function detailGuidance(detailLevel: DetailLevel): string {
  return DETAIL_GUIDANCE[detailLevel];
}

export function composeAvatarGraphicPrompt(filteredPrompt: string, stylePreset: StylePreset): string {
  return [
    "Reimagine the person shown in the attached reference image as a striking piece of key art.",
    "Preserve their recognizable identity: hairstyle, outfit silhouette, and color palette from the reference.",
    "Compose it as a single polished portrait or scene, not a grid, collage, or multiple panels.",
    "Do not add any text, logos, watermarks, or UI elements anywhere in the image.",
    `Visual style: ${styleGuidance(stylePreset)}.`,
    `Scene or theme direction: <description>${filteredPrompt}</description>`,
  ].join("\n");
}

export function composeMeshyPrompt(
  filteredPrompt: string,
  stylePreset: StylePreset,
  detailLevel: DetailLevel,
  accessoryType?: AccessoryType,
): string {
  const suffix = ` Style direction: ${styleGuidance(stylePreset)}. Detail direction: ${detailGuidance(detailLevel)}. ${accessoryIsolationGuidance(accessoryType)}`;
  const maximumLength = 600;
  const description = filteredPrompt.slice(0, Math.max(1, maximumLength - suffix.length)).trimEnd();
  return `${description}${suffix}`;
}
