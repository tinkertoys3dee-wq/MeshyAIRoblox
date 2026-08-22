import { afterEach, describe, expect, it, vi } from "vitest";
import { RobloxReferenceClient } from "../src/providers/roblox-reference.js";

describe("RobloxReferenceClient", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("rejects a thumbnail URL outside Roblox's CDN before downloading it", async () => {
    const fetchMock = vi.fn(async () =>
      new Response(
        JSON.stringify({
          data: [{ targetId: 123, state: "Completed", imageUrl: "https://example.com/not-roblox.png" }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(new RobloxReferenceClient().downloadImage(123)).rejects.toMatchObject({
      code: "ROBLOX_IMAGE_URL_REJECTED",
      retryable: false,
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("never follows a CDN redirect", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            data: [{ targetId: 123, state: "Completed", imageUrl: "https://tr.rbxcdn.com/safe-image.png" }],
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(new Response("unavailable", { status: 503 }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(new RobloxReferenceClient().downloadImage(123)).rejects.toMatchObject({
      code: "ROBLOX_IMAGE_DOWNLOAD_FAILED",
    });
    expect(fetchMock.mock.calls[1]?.[1]).toMatchObject({ redirect: "error" });
  });
});
