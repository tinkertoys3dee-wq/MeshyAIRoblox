import { describe, expect, it } from "vitest";
import { loadConfig } from "../src/config.js";

describe("loadConfig", () => {
  it("loads safe development defaults", () => {
    const config = loadConfig({ NODE_ENV: "test", MOCK_PROVIDERS: "true" });
    expect(config.limits.targetTriangles).toBe(3600);
    expect(config.limits.maxTriangles).toBe(3999);
    expect(config.limits.maxVertices).toBe(3999);
    expect(config.openai.imageModel).toBe("gpt-image-2");
    expect(config.openai.imageQuality).toBe("low");
    expect(config.mockProviders).toBe(true);
  });

  it("rejects missing production secrets", () => {
    expect(() => loadConfig({ NODE_ENV: "production", MOCK_PROVIDERS: "false" })).toThrow(
      /Missing production configuration/,
    );
  });

  it("forbids provider mocks in production", () => {
    expect(() => loadConfig({ NODE_ENV: "production", MOCK_PROVIDERS: "true" })).toThrow(/MOCK_PROVIDERS/);
  });

  it("requires a strong production request secret", () => {
    expect(() =>
      loadConfig({
        NODE_ENV: "production",
        MOCK_PROVIDERS: "false",
        ROBLOX_SHARED_SECRET: "short",
        DATABASE_URL: "postgres://example.test/forge",
        MESHY_API_KEY: "meshy-test",
        OPENAI_API_KEY: "openai-test",
        ROBLOX_OPEN_CLOUD_API_KEY: "roblox-test",
        ROBLOX_CREATOR_ID: "123",
      }),
    ).toThrow(/at least 32/);
  });

  it("rejects a target above the hard triangle limit", () => {
    expect(() =>
      loadConfig({ NODE_ENV: "test", MOCK_PROVIDERS: "true", TARGET_TRIANGLES: "4000", MAX_TRIANGLES: "3000" }),
    ).toThrow(/TARGET_TRIANGLES/);
  });
});
