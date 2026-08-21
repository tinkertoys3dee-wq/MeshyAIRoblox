import { describe, expect, it } from "vitest";
import { netUsdFromProduct, requiredRobuxPrice } from "../src/pricing.js";

describe("pricing", () => {
  it("matches the standard DevEx break-even example", () => {
    expect(requiredRobuxPrice(0.3, 0)).toBe(113);
    expect(requiredRobuxPrice(0.3, 0.3)).toBe(147);
  });

  it("shows positive contribution at the configured direct price", () => {
    expect(netUsdFromProduct(159)).toBeCloseTo(0.42294, 5);
    expect(netUsdFromProduct(159)).toBeGreaterThan(0.3 * 1.3);
  });
});
