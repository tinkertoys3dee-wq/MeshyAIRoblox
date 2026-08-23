import { afterEach, describe, expect, it, vi } from "vitest";
import { loadConfig } from "../src/config.js";
import { MeshyClient } from "../src/providers/meshy.js";

describe("MeshyClient", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("survives a transient polling failure without restarting a paid task", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response("temporarily unavailable", { status: 503 }))
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ id: "task-1", status: "SUCCEEDED", progress: 100, model_urls: {} }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    vi.stubGlobal("fetch", fetchMock);
    const client = new MeshyClient(
      loadConfig({
        NODE_ENV: "test",
        MESHY_API_KEY: "test-key",
        MESHY_POLL_INTERVAL_MS: "500",
        MESHY_TASK_TIMEOUT_MS: "30000",
      }),
    );

    await expect(client.pollImageTask("task-1", async () => {})).resolves.toMatchObject({
      status: "SUCCEEDED",
      progress: 100,
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
