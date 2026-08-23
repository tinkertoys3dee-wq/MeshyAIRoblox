# Canonical product specification

This file is the durable source of truth for future Forge UGC updates. A change should preserve these rules unless the creator explicitly replaces one.

## Core experience

- Public servers support about 15 players and all gameplay systems must remain multiplayer-safe.
- Creation has three paths:
  - Direct: filtered text → Meshy Smart Topology textured 3D.
  - Art-directed: filtered text → paid reference image → player approval → paid image-to-3D conversion. A reroll is another paid reference and never destroys the prior result. The reference image itself has three purchasable quality tiers (`Low`, `Medium`, `High`), each a separate developer product priced to its own OpenAI provider cost; see `docs/PRICING.md`.
  - Upload Reference: a permanent 249 R$ game pass unlocks player-owned Roblox Image/Decal references. The reference is free to submit after unlock; an approved reference uses the normal paid image-to-3D conversion.
- Every path exposes an allowlisted visual-style preset (`Auto`, `Anime`, `Realistic`, `Stylized`, `Low poly`, or `Fantasy`) and detail density (`Clean`, `Balanced`, or `Intricate`). These settings guide both shape and texture without relaxing topology limits.
- Meshy targets 3,600 triangle faces. Accepted output has one watertight textured mesh/primitive, usable UVs, fewer than 4,000 triangles and vertices, embedded textures no larger than 2048×2048, and a final file below the Roblox upload cap.
- Players fit each owned item against an avatar reference with position, rotation, and per-axis scale, then save, equip, and unequip that fit in the experience. Unequip is server-authoritative and independent of equipping a different item, so multiple owned items may be equipped or removed one at a time.
- A player may save the position/rotation/scale currently being dialed in as a named fit preset (up to 20 per player) and reapply it later — including while actively customizing a different item's fit, since presets are stored independently of any single item's in-progress draft.
- An owner can use Roblox's `AvatarCreationService` and the matching Avatar Creation Token to prompt creation of a platform-wide wearable. This prompt can carry a separate Roblox token price and is never silently charged.

## Ownership and marketplace

- Each original belongs to its creator. The creator controls private/public visibility and whether it is listed.
- Publishing a listing does not require Roblox Plus.
- Every public item can be viewed and tried on for free, even when it is not listed and even when the viewer does not have Plus.
- Buying requires both an active owner listing and a Roblox Plus subscriber buyer.
- Payment uses `PromptRobuxTransferAsync`; the buyer receives a copy only after a matching sender receipt confirms the stored transfer request and amount.
- A purchased copy is `PERSONAL_COPY`: the buyer may fit, equip, and publish it as their own wearable, but can never list, resell, transfer, or use it as a source listing inside Forge.
- Listings are restricted to Roblox's current transfer range of 10–500 R$. The seller receives 90% and the experience receives 10% according to the current platform program.
- Public discovery ranks recent engagement from views, likes, and favorites by default. Players may switch to newest, lowest listed price, or most-liked, and may search by item name or by creator display name. The owner profile remains authoritative for ownership and visibility; the atomically updated public index is authoritative for the current listing flag and price so buyers in another server do not see stale sale state.
- A cross-server Top Creators leaderboard ranks players by total likes received across every published/listed item, backed by an `OrderedDataStore` (`Config.DataStores.LikesLeaderboard`) kept in step every time a like is toggled. It is a ranking signal, not a source of truth — item-level like counts on the owner's own profile remain authoritative.

## Safety, privacy, and authority

- The server filters all player generation text with Roblox `TextService` before it can reach Railway or an AI provider. Filtering fails closed.
- Provider moderation is a second gate for filtered text before purchase and for generated visual output before display/upload. Meshy moderation remains enabled as an additional layer.
- A custom reference must be a Roblox Image or Decal owned by the player or the configured creator group and must finish Roblox moderation before Forge can resolve it. Forge verifies ownership, type, moderation availability, format, dimensions, and fixed Roblox CDN provenance, but deliberately does not pay to re-run OpenAI vision moderation on an already Roblox-approved upload. Arbitrary URLs and raw client image bytes are never accepted.
- `PolicyService.IsContentSharingAllowed` disables public sharing, listings, reactions, and other-player generated-item try-on. Private creation stays available.
- Custom-image submission additionally requires `IsContentSharingAllowed`; it fails closed when the policy lookup, pass lookup, asset metadata, ownership, Roblox moderation state, or image validation is unavailable.
- Commerce, subscription, and paid-trading policy flags are enforced server-side.
- Provider keys and the Open Cloud key exist only in Railway variables. The Roblox experience authenticates with a Creator Hub secret; no secret belongs in Git or client-visible Luau.
- Client values are requests, never authority. The server rechecks price, ownership, listing state, transforms, policy, rate limits, and receipt identity.
- Player item metadata, generation records, fits, licenses, settings, and receipt state live under that player's individual DataStore key. Shared DataStores contain only the minimum discovery index and receipt idempotency record. Large GLB/PNG artifacts use Roblox assets or temporary durable backend pipeline storage because DataStores cannot hold those files.

## Retention and monetization principles

- Group members receive one extra concurrent queue slot, priority scheduling, and the configured 10% status-polling boost.
- A priority pass is an optional transparent convenience product, not a requirement to complete a paid job.
- Custom Image Upload is a permanent premium game pass, not a consumable. Its 249 R$ price pays for durable art-direction access; each resulting 3D conversion remains separately and transparently priced.
- Daily creative briefs and a three-day streak reward provide return reasons without random paid rewards or loss aversion.
- Forge Tokens are an alternative to Robux for every Direct Forge/reference-image/conversion/Priority Pass purchase, earned by watching a Roblox Rewarded Video ad (or bought directly, since Roblox requires the ad reward to also be a normal purchase). Paying with tokens always costs 20% more than the Robux price (`Config.Ads.TokenPurchaseMarkup`), and a player can switch between Robux and Tokens per purchase; the Custom Image Upload pass is Robux-only because Roblox's ad-reward system only supports developer products. See `docs/PRICING.md` "Forge Tokens".
- A daily check-in bonus, a one-time achievement for every major feature (creating, equipping, saving a fit preset, publishing, listing, liking, Avatar Lab try-on, watching an ad, a marketplace purchase, a 7-day streak, sending a friend invite), and a cross-server Top Creators leaderboard all reinforce the token economy and give players concrete reasons to return daily and explore every part of the studio, not just optimize a single loop.
- The Avatar Lab supports Roblox catalog search — filterable by sort order (relevance, bestselling, most favorited, price, newest), creator name, and price range, on top of the existing accessory-type filter — free try-on, platform purchase prompts, avatar saving, and reset.
- Pricing uses the standard, lowest DevEx rate assumption. Provider cost, completion rate, retry liability, Railway cost, and live Roblox revenue must be remeasured before any price change.
- Analytics never include prompt text, generated names, catalog queries, secrets, or provider response bodies. Use the scorecard in `docs/ANALYTICS.md` to improve reliability and player value before optimizing spend.

## Presentation

- UI should remain glossy, vibrant, layered, responsive, and straightforward—not a collection of flat default frames.
- Effects should be polished and restrained; excessive confetti or sparkle noise is out of scope.
- Every sound ID remains creator-owned. `src/Shared/SoundIds.luau` is the only place to enter them, with directions in `docs/SOUND_SETUP.md`.
- Accessibility is a durable requirement, not a one-time pass: a dedicated Settings page exposes interface scale (a single `UIScale` covering text and touch targets together), a high-contrast palette toggle, and a reduce-motion toggle that a player's saved profile settings apply the next time they open the studio. Status is never color-only — toasts and equipped-state indicators pair color with a glyph. Every interactive control remains keyboard/gamepad `Selectable`, and Tab or a gamepad's Y button hands focus to the nav rail.
- The default palette is mid-tone, not near-black: panels read as slate/navy rather than pure dark mode, while the separate high-contrast toggle still goes to the darker, wider-contrast extremes appropriate for that accessibility mode. Rounded-corner containers (`Factory.Card` and similar) deliberately do not set `ClipsDescendants` — Roblox clips to the object's rectangle, not its `UICorner` shape, so that property cuts a visible square notch into a rounded corner instead of fixing overflow; keep content inside a card's bounds by sizing/positioning it correctly instead.

## Delivery workflow

- Argon synchronizes `default.project.json` with server priority; repository source is authoritative and routine edits are not made in Studio.
- The Railway service deploys the `backend/` directory from this same repository.
- Work is committed and pushed directly to `main`; do not create feature branches or ask the creator to merge a pull request. Before pushing, incorporate any upstream `main` changes without discarding unrelated work.

## Checkpoint status

Implemented in the current checkpoint: all three creation flows with tiered reference-image quality, permanent custom-image entitlement checks, player/group image ownership validation, generated-output visual moderation, style/detail guidance, receipt-safe developer products, Forge Tokens as a rewarded-ad-earned alternative to Robux for every purchase except the Custom Image Upload pass, Railway provider pipeline, GLB validation, fitting/equip/unequip/publish services with named fit presets, individual player profiles, Plus-transfer copies, discovery/reactions/trending-newest-price-likes sorting, name/creator search, an Avatar Lab catalog search with sort/creator/price filters, policy gates, group/streak benefits, a Settings page (interface scale, high contrast, reduce motion, sound, equipped-loadout management), keyboard/gamepad navigation entry point, a mid-tone responsive UI, sound hooks, and analytics instrumentation.

Creator-owned activation still required: group ID, developer product IDs (including the Forge Tokens `AdRewardTokens` product, which must also be registered as a Rewarded Video Ad reward in the Roblox Creator Hub ad monetization dashboard once the experience meets Roblox's rewarded-ad eligibility bar), Custom Image Upload game pass ID, Avatar Creation Token IDs and prices, sound asset IDs and permissions, Railway/PostgreSQL deployment, Creator Hub/Open Cloud secrets, maximum player setting, and live Studio/device testing — rewarded ads specifically cannot be exercised in Studio and need a live, eligible experience to verify end to end.

Post-beta scaling priorities: profile session locking, a paginated cross-server discovery index, report/block/takedown tooling, operational cost dashboards, provider queue telemetry, and controlled UX experiments. These are launch-hardening tasks, not permission to weaken any rule above.
