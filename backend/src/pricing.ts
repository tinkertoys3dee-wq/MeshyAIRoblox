export const STANDARD_DEVEX_USD_PER_ROBUX = 0.0038;
export const STANDARD_PRODUCT_CREATOR_SHARE = 0.7;

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
