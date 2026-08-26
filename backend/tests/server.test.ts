import { afterEach, describe, expect, it } from "vitest";
import { loadConfig } from "../src/config.js";
import { MemoryJobRepository } from "../src/repository.js";
import { buildServer } from "../src/server.js";

describe("backend HTTP boundary", () => {
  const apps: Awaited<ReturnType<typeof buildServer>>[] = [];

  afterEach(async () => {
    await Promise.all(apps.splice(0).map((app) => app.close()));
  });

  it("boots in mock mode and runs an authenticated job", async () => {
    const config = loadConfig({
      NODE_ENV: "test",
      MOCK_PROVIDERS: "true",
      ROBLOX_SHARED_SECRET: "test-shared-secret",
      LOG_LEVEL: "silent",
    });
    const repository = new MemoryJobRepository();
    await repository.initialize();
    const app = await buildServer(config, repository);
    apps.push(app);

    const health = await app.inject({ method: "GET", url: "/health" });
    expect(health.statusCode).toBe(200);
    expect(health.json()).toMatchObject({ ok: true, providers: "mock" });

    const body = {
      requestId: "smoke_request_12345",
      playerUserId: 12345,
      kind: "TEXT_TO_3D",
      filteredPrompt: "a polished violet crystal crown",
      accessoryType: "Hat",
      priority: false,
      context: { universeId: 0, placeId: 0, gameJobId: "test-job" },
    };
    const unauthorized = await app.inject({ method: "POST", url: "/v1/jobs", payload: body });
    expect(unauthorized.statusCode).toBe(401);

    const moderation = await app.inject({
      method: "POST",
      url: "/v1/moderate",
      headers: {
        "x-forge-secret": "test-shared-secret",
        "x-roblox-user-id": "12345",
      },
      payload: { playerUserId: 12345, filteredPrompt: body.filteredPrompt },
    });
    expect(moderation.statusCode).toBe(200);
    expect(moderation.json()).toEqual({ safe: true });

    const created = await app.inject({
      method: "POST",
      url: "/v1/jobs",
      headers: {
        "x-forge-secret": "test-shared-secret",
        "x-roblox-user-id": "12345",
      },
      payload: body,
    });
    expect(created.statusCode).toBe(202);
    const createdJob = created.json().job;
    const id = createdJob.id as string;
    expect(createdJob).not.toHaveProperty("filteredPrompt");
    expect(createdJob).not.toHaveProperty("playerUserId");
    expect(createdJob).not.toHaveProperty("context");

    const repeated = await app.inject({
      method: "POST",
      url: "/v1/jobs",
      headers: {
        "x-forge-secret": "test-shared-secret",
        "x-roblox-user-id": "12345",
      },
      payload: body,
    });
    expect(repeated.statusCode).toBe(200);
    expect(repeated.json()).toMatchObject({ idempotent: true, job: { id } });

    const conflict = await app.inject({
      method: "POST",
      url: "/v1/jobs",
      headers: {
        "x-forge-secret": "test-shared-secret",
        "x-roblox-user-id": "12345",
      },
      payload: { ...body, filteredPrompt: "a different filtered prompt" },
    });
    expect(conflict.statusCode).toBe(409);

    await new Promise((resolve) => setTimeout(resolve, 80));
    const completed = await app.inject({
      method: "GET",
      url: "/v1/jobs/" + id,
      headers: {
        "x-forge-secret": "test-shared-secret",
        "x-roblox-user-id": "12345",
      },
    });
    expect(completed.statusCode).toBe(200);
    expect(completed.json().job).toMatchObject({
      status: "SUCCEEDED",
      output: { modelAssetId: 0, triangles: 3600, vertices: 2400 },
    });

    const uploaded = await app.inject({
      method: "POST",
      url: "/v1/jobs",
      headers: {
        "x-forge-secret": "test-shared-secret",
        "x-roblox-user-id": "12345",
      },
      payload: {
        ...body,
        requestId: "upload_request_12345",
        kind: "IMAGE_UPLOAD",
        sourceImageAssetId: 987654321,
        stylePreset: "STYLIZED",
        detailLevel: "CLEAN",
      },
    });
    expect(uploaded.statusCode).toBe(202);
    const uploadId = uploaded.json().job.id as string;
    await new Promise((resolve) => setTimeout(resolve, 80));
    const uploadedReady = await app.inject({
      method: "GET",
      url: "/v1/jobs/" + uploadId,
      headers: {
        "x-forge-secret": "test-shared-secret",
        "x-roblox-user-id": "12345",
      },
    });
    expect(uploadedReady.json().job).toMatchObject({
      status: "IMAGE_READY",
      stylePreset: "STYLIZED",
      detailLevel: "CLEAN",
      output: { previewAssetId: 987654321 },
    });

    const preview = await app.inject({
      method: "POST",
      url: "/v1/jobs",
      headers: {
        "x-forge-secret": "test-shared-secret",
        "x-roblox-user-id": "12345",
      },
      payload: {
        ...body,
        requestId: "preview_request_12345",
        kind: "IMAGE_PREVIEW",
        imageQuality: "high",
      },
    });
    expect(preview.statusCode).toBe(202);
    expect(preview.json().job).toMatchObject({ kind: "IMAGE_PREVIEW", imageQuality: "high" });

    const invalidTier = await app.inject({
      method: "POST",
      url: "/v1/jobs",
      headers: {
        "x-forge-secret": "test-shared-secret",
        "x-roblox-user-id": "12345",
      },
      payload: { ...body, requestId: "bad_tier_request_12345", imageQuality: "high" },
    });
    expect(invalidTier.statusCode).toBe(400);

    const { accessoryType: _unused, ...bodyWithoutAccessory } = body;
    const graphic = await app.inject({
      method: "POST",
      url: "/v1/jobs",
      headers: {
        "x-forge-secret": "test-shared-secret",
        "x-roblox-user-id": "12345",
      },
      payload: {
        ...bodyWithoutAccessory,
        requestId: "graphic_request_12345",
        kind: "AVATAR_GRAPHIC",
        avatarView: "BUST",
        filteredPrompt: "a heroic fantasy portrait with golden light",
      },
    });
    expect(graphic.statusCode).toBe(202);
    expect(graphic.json().job).not.toHaveProperty("accessoryType");
    const graphicId = graphic.json().job.id as string;
    await new Promise((resolve) => setTimeout(resolve, 80));
    const graphicReady = await app.inject({
      method: "GET",
      url: "/v1/jobs/" + graphicId,
      headers: {
        "x-forge-secret": "test-shared-secret",
        "x-roblox-user-id": "12345",
      },
    });
    expect(graphicReady.json().job).toMatchObject({
      status: "SUCCEEDED",
      output: { previewAssetId: 0 },
    });

    // The shareable image link needs no auth headers at all -- it's opened
    // from the player's own browser, outside Roblox entirely.
    const image = await app.inject({ method: "GET", url: `/v1/graphics/${graphicId}/image` });
    expect(image.statusCode).toBe(200);
    expect(image.headers["content-type"]).toBe("image/png");
    expect(image.rawPayload.length).toBeGreaterThan(0);

    // A job that isn't a succeeded AVATAR_GRAPHIC (the earlier TEXT_TO_3D
    // job from this same test) must never be served through this route.
    const wrongKind = await app.inject({ method: "GET", url: `/v1/graphics/${id}/image` });
    expect(wrongKind.statusCode).toBe(404);

    const missing = await app.inject({ method: "GET", url: "/v1/graphics/does-not-exist/image" });
    expect(missing.statusCode).toBe(404);
  });
});
