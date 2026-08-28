# Creator setup checklist

No secret should be pasted into chat or committed to this repository.

## Argon and the existing place

`default.project.json` deliberately keeps unknown DataModel instances and does not map `Workspace` or `Lighting`. Server-priority Argon syncs may update Forge code, but must preserve the creator-built map and every place lighting setting. Do not add runtime world construction or lighting overrides to this repository.

## Roblox Creator Hub

1. Set the experience's maximum player count to **15**.
2. Enable HTTP requests and Studio API access for the experience.
3. Add a Creator Hub secret named `FORGE_BACKEND_SECRET`; use the same cryptographically random value of at least 32 characters for Railway's `ROBLOX_SHARED_SECRET`.
4. Create developer products at the suggested prices and enter their IDs in `src/Shared/Config.luau` (`Config.Products`):
   - Direct Text → 3D: 159 R$ (`DirectGeneration`)
   - Reference Image — Low quality: 29 R$ (`ImagePreviewLow`; already configured)
   - Reference Image — Medium quality: 49 R$ (`ImagePreviewMedium`)
   - Reference Image — High quality: 129 R$ (`ImagePreviewHigh`)
   - Image → 3D Conversion: 159 R$ (`ImageConversion`)
   - Avatar → 3D Conversion: 159 R$ (`AvatarConversion`)
   - Priority Queue Pass: 29 R$ (`PriorityPass`)
   - 70 Forge Tokens: 10 R$ (`TokenPack70`; `Id` is still `0`)
   - Rewarded-ad token unit: 3 R$ (`AdRewardTokens`, Roblox's allowed floor) — see step 4a before changing this one.

   The medium/high reference-image prices are estimates pending measured OpenAI cost per tier; see `docs/PRICING.md` before treating them as final.
4a. Forge Tokens are the Robux alternative earned from Rewarded Video Ads. This needs two things beyond the usual product ID:
   - The experience must first meet Roblox's [rewarded-ad eligibility bar](https://create.roblox.com/docs/production/promotion/rewarded-video-ads#eligibility-requirements): public and unrestricted, a completed Maturity & Compliance questionnaire (see step 11), an ID-verified account with two-step verification, and roughly 2,000+ unique monthly visitors.
   - Register `AdRewardTokens` as a Rewarded Video Ad reward in Creator Hub. `AdService:CreateAdRewardFromDevProductId` resolves it at runtime. Roblox requires the wrapped reward product to stay worth 3–10 Robux and forbids rewarding Robux directly; it grants `Config.Ads.TokenGrantPerAd` (one token). The normal 10-Robux store button uses the separate `TokenPack70` product and grants `Config.Ads.TokenPackGrant` (70 tokens).
5. Create a **Custom Image Upload** game pass for **249 R$**, enable it for sale, and enter its ID in `Config.Passes.CustomImageUpload.Id`. This is permanent access; it is not a developer product.
6. Enter the Roblox group ID in `Config.Group.Id` to enable 10% faster queue polling, one extra queued job, and group-owned custom reference images.
7. Create Avatar Creation Tokens for each accessory type you will permit. Keep active token IDs out of Git: in Studio, create a `Folder` named `ForgeUGCSecrets` under `ServerStorage`, then add a `StringValue` named `AvatarCreationToken_BackAccessory` (or the matching accessory type) and put the token ID in its `Value`. Repeat for each enabled type. The project uses `$keepUnknowns`, so Argon sync preserves this private server-only folder.
8. Keep the group or token owner ID-verified with Roblox Premium so in-experience avatar creation remains available.
9. Leave `Workspace.SandboxedInstanceMode` set to `Default`. `AssetRead`, `Players`, `PlatformAvatarEditing`, and `LoadUnownedAsset` are experimental **script sandbox** labels shown in the API reference, not Creator Hub experience switches. The current Forge scripts are intentionally not sandboxed; Avatar Lab requests inventory access from each player at runtime.
10. Enable API access for the Open Cloud key used by Railway:
   - Assets API read/write for the experience's group creator.
   - Restrict the key by IP if Railway provides a stable egress IP.
11. Complete the experience's Maturity & Compliance questionnaire, disclose paid item trading and player-supplied image references, and confirm that the experience enforces `IsPaidItemTradingAllowed` and `IsContentSharingAllowed` per player.
12. Create one Badge asset per achievement in Creator Hub (Create → Badges) and paste each numeric badge ID into the matching key of `Config.Achievements.BadgeIds` in `src/Shared/Config.luau` — the achievement id, name, and description text live in `src/Shared/Achievements.luau`, not the badge asset itself, so the badge's own Creator Hub title/description can be whatever you like. Token rewards work immediately without this step; a badge ID left at `0` just means `AchievementService` skips awarding that badge until you fill it in. Don't change any achievement's `tokens` value without checking it against `Config.Achievements.NonEarningTokenBudget` — the server refuses to start if the total goes over budget (see that constant's comment for why).
13. `assets/icons/` has a ready-made circular icon for every badge, developer product, and game pass (512×512 PNG, transparent corners, matching the in-game palette) — upload the matching file when you create/configure each one in Creator Hub. `assets/icons/README.md` maps every filename to its `Config.luau` key.

## Player image upload flow

Roblox does not currently expose a general-purpose runtime picker that gives an experience an arbitrary local PNG/JPG for use by an external generation pipeline. `AvatarCreationService:PromptSelectAvatarGenerationImageAsync()` is limited to Roblox's sensitive Photo-to-Avatar flow: it returns a temporary file identifier for Roblox's avatar-generation methods, not image bytes, a URL, or an uploaded Image/Decal asset that Forge can send to Meshy. Players therefore upload a PNG/JPG through Roblox Creator Hub as an **Image** or **Decal**, wait for Roblox moderation, and paste the numeric asset ID into Forge.

The asset must be owned by the player's Roblox account or by the group configured in `Config.Group.Id`. Forge rejects arbitrary URLs, non-image asset types, other creators' assets, pending/blocked thumbnails, malformed images, and accounts for which `IsContentSharingAllowed` is false. Railway downloads only through Roblox's fixed thumbnail endpoint and approved HTTPS CDN hosts. Because the asset has already completed Roblox moderation, Forge does not spend OpenAI vision credits rechecking the same upload; generated references and Meshy-produced textures/thumbnails still receive provider-side visual moderation.

## Railway variables

Copy every field from `backend/.env.example` into the Railway service. Required production values are:

- `MESHY_API_KEY`
- `OPENAI_API_KEY`
- `ROBLOX_OPEN_CLOUD_API_KEY`
- `ROBLOX_CREATOR_ID` (the group ID)
- `ROBLOX_CREATOR_TYPE=group`
- `ROBLOX_SHARED_SECRET`
- `DATABASE_URL` (attach Railway PostgreSQL)

Set `OPENAI_IMAGE_MODEL=gpt-image-2` and `OPENAI_IMAGE_QUALITY=low`. If Railway already has `OPENAI_IMAGE_QUALITY=medium`, change or remove that explicit value so the cheaper reference-image default takes effect.

Create a Railway service from this repository with `backend/` as its root directory. Use `npm run build` as the build command, `npm run start` as the start command, and `/health` as the health-check path. A production boot deliberately fails if PostgreSQL, the Roblox shared secret, or any live provider credential is absent.

Finally, put the Railway HTTPS origin in `Config.Backend.BaseUrl`. Do not include a trailing slash.

## Studio smoke test

With an ID still set to `0`, Studio uses the project's mock purchase behavior for that product. The Custom Image Upload pass can be mock-unlocked for that Studio session; use any positive numeric image ID while the mock backend is active. Verify onboarding, all creation paths and quality tiers, fitting-control state, preserved avatar accessories, equip/unequip from Studio and both avatar side panels, immediate graphic deletion, the completion celebration, the seven-day login calendar, the AFK lounge, fit presets/outfits, listing/search/sort controls, accessibility settings, and reconnect persistence before enabling live products. Placeholder asset IDs do not render a mesh; test the full viewport/equip/publish path with a privately owned test model or the live backend. Never put a provider key or Avatar Creation Token in a replicated Luau file.

Rewarded ads cannot be exercised end to end in Studio: `AdService:GetAdAvailabilityNowAsync`/`ShowRewardedVideoAdAsync` need a live, ads-eligible experience. The separate `TokenPack70` purchase and token-spending flow can be tested with Studio mock purchases once its ID is configured. Verify the complete ad loop once live, including that each ad requires a fresh player click, unavailable/closed ads grant nothing, and a completed ad credits exactly one token through the receipt handler.
