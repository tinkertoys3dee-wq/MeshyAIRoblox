# Architecture

## Trust boundaries

```mermaid
flowchart TD
    C[Roblox client] -->|typed remote requests| S[Roblox server]
    S -->|TextService + PolicyService| F[Filtered, permitted request]
    S -->|pass + Image/Decal ownership| I[Roblox-moderated reference ID]
    F -->|Creator Hub secret| R[Railway API]
    I -->|numeric ID only| R
    R -->|fixed thumbnail endpoint| T[Roblox image CDN]
    R --> M[Meshy API]
    R --> O[OpenAI Images API]
    R -->|group API key| A[Roblox Open Cloud Assets]
    A --> S
    S --> D[(Player DataStore key)]
```

The client is never trusted with prices, pass ownership, image ownership, fit bounds, product IDs, provider URLs, secrets, or receipt state. Railway never accepts a player-supplied identity directly; it accepts the Roblox server's authenticated user ID and request ID. Custom-image jobs accept a numeric Roblox asset ID only; the backend never fetches a player-supplied URL.

## Generation state machine

```mermaid
stateDiagram-v2
    [*] --> QUOTED
    [*] --> ENTITLED: owned upload pass
    ENTITLED --> IMAGE_MODERATION: owned Roblox Image/Decal ID
    IMAGE_MODERATION --> IMAGE_READY: Roblox moderation + validation pass
    QUOTED --> PAID: developer product receipt
    PAID --> QUEUED
    QUEUED --> GENERATING_IMAGE: image-assisted
    QUEUED --> GENERATING_MESH: direct
    GENERATING_IMAGE --> IMAGE_READY
    IMAGE_READY --> GENERATING_MESH: approved conversion
    GENERATING_MESH --> TEXTURING: text path
    GENERATING_MESH --> VALIDATING: image path
    TEXTURING --> VALIDATING
    VALIDATING --> UPLOADING
    UPLOADING --> SUCCEEDED
    VALIDATING --> FAILED
    UPLOADING --> FAILED
```

The live backend and its second-stage text moderation must respond successfully before a developer-product prompt can open. Provider, validation, upload, and infrastructure failures after payment grant an in-game retry credit for the same operation. A post-payment content rejection is also recovered as a credit because the prompt already passed preflight. Retry credits are not Robux and cannot be transferred.

Custom-image submission has no per-submission developer product. The Roblox server rechecks the permanent game pass, content-sharing policy, asset type, and creator ownership. Railway resolves the already moderated asset through Roblox's fixed thumbnail API, restricts downloads to HTTPS Roblox CDN hosts, and validates/normalizes the still image. It does not purchase a redundant OpenAI vision check for that Roblox-approved upload. Only an `IMAGE_READY` artifact can become the source of the separately paid image-to-3D conversion.

Style and detail choices are strict enums, not free-form instructions. Railway expands them into trusted prompt guidance for OpenAI reference generation and Meshy geometry/texture prompts. Meshy's deprecated `art_style` parameter is deliberately not used.

Developer-product intent data is saved before Roblox is prompted. Receipt grants use deterministic generation IDs, write the durable benefit and receipt marker to the player's profile before acknowledging Roblox, and submit the same backend request ID on every retry. Plus transfers likewise persist a source snapshot and transfer request ID before a sender receipt can grant a deterministic personal copy.

## Persistence

`ForgeUGC_Player_v1` stores one document per user key (`u_<userId>`):

- original and purchased item records;
- generation jobs and preview state;
- style/detail selections and custom Roblox reference IDs;
- fit transforms and equipped item IDs;
- liked/favorited item references;
- pending generation purchases and Plus transfers;
- processed developer-product receipt IDs;
- settings, onboarding, streak, and analytics counters.

`ForgeUGC_ItemIndex_v1` contains only public item IDs, owner IDs, current listing state/price, engagement counters, and ranking timestamps. Trending scores and cross-server listing availability are calculated from that index; the owner profile remains canonical for ownership, licensing, visibility, and the source model. This small shared index is necessary because Roblox DataStores cannot enumerate every player key for marketplace discovery.

The raw GLB/PNG bytes are never placed in a DataStore. Roblox DataStores are metadata stores with strict value-size limits. Final files become Roblox assets; temporary provider artifacts live only long enough for Railway to validate and upload them.

## Roblox asset lifecycle

1. Railway downloads the provider result immediately because Meshy URLs expire.
2. The GLB is normalized before upload: compatible Smart Topology parts are flattened and joined, then the result must contain exactly one mesh/primitive/node, watertight manifold geometry with usable UVs, fewer than 4,000 triangles and vertices, finite coordinates, no rig or animation data, an embedded base-color texture normalized to PNG at no more than 2048×2048, and a final file below the configured upload cap.
3. Generated references, embedded textures, and thumbnails pass provider visual moderation before display or upload. Player-supplied references rely on completed Roblox moderation plus Forge ownership/type/CDN/image validation.
4. Railway uploads the GLB as a group-owned Model using the Open Cloud Assets API.
5. The Roblox server loads the owned model with `AssetService:LoadAssetAsync()` for private fitting and in-game equip.
6. Final platform-wide creation uses `AvatarCreationService:PromptCreateAvatarAssetAsync()` and an Avatar Creation Token matching the selected accessory type.

## Marketplace license model

- `ORIGINAL` — may be made public, listed, fitted, equipped, or sent through avatar creation by its owner.
- `PERSONAL_COPY` — may be independently fitted, equipped, and sent through avatar creation by its buyer; may never be listed, transferred, or used as a source listing.

Trying on a public item is free and does not require Plus or an active listing. Buying requires an active listing and a Roblox Plus transfer between 10 and 500 Robux. The buyer receives the copy only after the sender receipt is processed.

## Analytics boundary

Only server-authored events and three tightly allowlisted client events reach `AnalyticsService`. Fields are enumerated or numeric, capped in count and length, and never contain prompts, item names, catalog queries, or provider responses. See `docs/ANALYTICS.md` for the launch scorecard and decision cadence.
