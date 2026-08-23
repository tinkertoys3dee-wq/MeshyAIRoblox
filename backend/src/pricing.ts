export const STANDARD_DEVEX_USD_PER_ROBUX = 0.0038;
export const STANDARD_PRODUCT_CREATOR_SHARE = 0.7;

// Estimated OpenAI gpt-image-2 cost per isolated 1024x1024 reference at each
// purchasable quality tier, scaled off the measured "low" baseline using
// OpenAI's published low/medium/high cost ratios (~1x / ~3.8x / ~15x). These
// are planning estimates, not billing data; replace with one week of
// measured Railway/OpenAI spend per tier before treating them as final.
export const IMAGE_QUALITY_PROVIDER_COST_USD: Readonly<Record<"low" | "medium" | "high", number>> = Object.freeze({
  low: 0.006,
  medium: 0.023,
  high: 0.091,
});

export function requiredRobuxPrice(
  providerCostUsd: number,
  targetCostMarkup: number,
  hostingReserveUsd = 0,
  creatorShare = STANDARD_PRODUCT_CREATOR_SHARE,
  devexUsdPerRobux = STANDARD_DEVEX_USD_PER_ROBUX,
): number {
  if (providerCostUsd < 0 || hostingReserveUsd < 0) throw new Error("Costs cannot be negative");
  if (targetCostMarkup < 0) throw new Error("Target cost markup cannot be negative");
  if (creatorShare <= 0 || creatorShare > 1 || devexUsdPerRobux <= 0) throw new Error("Invalid conversion inputs");
  return Math.ceil(((providerCostUsd + hostingReserveUsd) * (1 + targetCostMarkup)) / (creatorShare * devexUsdPerRobux));
}

export function netUsdFromProduct(robuxPrice: number): number {
  return robuxPrice * STANDARD_PRODUCT_CREATOR_SHARE * STANDARD_DEVEX_USD_PER_ROBUX;
}
