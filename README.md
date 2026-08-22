# Forge UGC

Forge UGC is a Roblox experience for generating, fitting, trying on, publishing, and sharing AI-assisted avatar accessories. The repository contains both sides of the product:

- `src/` — the Roblox client/server project synchronized by Argon.
- `backend/` — a Railway-ready TypeScript service that keeps Meshy, OpenAI, and Roblox Open Cloud keys out of the experience.

The vertical slice supports three creation paths in the product specification:

1. **Text → 3D** — a filtered prompt is sent to Meshy Smart Topology, textured, checked against Roblox's rigid-accessory limits, and uploaded as a group-owned model.
2. **Text → image → 3D** — a filtered prompt creates an isolated reference image, the player can approve or regenerate it, and an approved image is converted to the same validated 3D pipeline.
3. **Player image → 3D** — a permanent game pass unlocks references uploaded as a player- or creator-group-owned Roblox Image/Decal. Roblox asset moderation, ownership/type checks, Forge visual moderation, and player approval all occur before the separately paid conversion.

All three paths include allowlisted style presets (`Auto`, `Anime`, `Realistic`, `Stylized`, `Low poly`, and `Fantasy`) plus `Clean`, `Balanced`, or `Intricate` detail guidance. These parameters affect generated references, Meshy geometry prompts, and texture prompts without changing the strict topology limits.

Generated item metadata, ownership, fit transforms, likes, favorites, purchase receipts, and non-resellable licenses are stored under the individual player's DataStore key. Shared stores contain only discovery indexes and idempotency records; they are not the source of truth for player content.

## Non-negotiable safety properties

- Raw player text never reaches an AI provider. The Roblox server first calls `TextService:FilterStringAsync()` and uses its broadcast-safe result.
- Filtered prompts receive a second provider-side safety check before any purchase prompt can open. Generated reference, texture, and thumbnail images are checked again before any visual asset is shown or uploaded.
- Custom references accept numeric Roblox Image/Decal IDs only, require player/group ownership and `IsContentSharingAllowed`, resolve through fixed Roblox hosts, and pass independent image moderation before Meshy receives any bytes.
- Public sharing, listings, likes, and other-player try-on are disabled when `PolicyService` reports `IsContentSharingAllowed == false`.
- Meshy and OpenAI keys are Railway environment variables. The Roblox-to-Railway credential is a Creator Hub secret returned by `HttpService:GetSecret()`.
- A generated rigid accessory targets 3,600 triangles and must remain strictly below 4,000 triangles and vertices. The backend requires one watertight textured mesh with UVs and normalizes its embedded texture to at most 2048×2048.
- A marketplace copy is granted only after a Roblox Plus transfer sender receipt matches a stored transfer request. Copies are permanently marked `PERSONAL_COPY` and cannot be listed again.
- The server, not the client, owns prices, transforms, item permissions, ownership checks, rate limits, and receipt decisions.

## Local setup

1. Install Node.js 22+.
2. Run `npm install --prefix backend`.
3. Copy `backend/.env.example` to `backend/.env` and fill it locally.
4. Run `npm run dev --prefix backend`.
5. In Studio, enable **Game Settings → Security → Allow HTTP Requests** and enable Studio API access while testing DataStores.
6. Synchronize `default.project.json` with Argon using server priority.

The game boots in a safe configuration mode until the IDs in `src/Shared/Config.luau` and the Creator Hub/Railway settings in [docs/SETUP.md](docs/SETUP.md) are completed.

## Commands

```bash
npm run check --prefix backend
npm test --prefix backend
npm run build --prefix backend
```

Start with the durable [product specification](docs/PRODUCT_SPEC.md), then see [architecture](docs/ARCHITECTURE.md), [analytics](docs/ANALYTICS.md), [pricing](docs/PRICING.md), and [sound setup](docs/SOUND_SETUP.md) for implementation decisions and the fields that still require creator-owned IDs.
