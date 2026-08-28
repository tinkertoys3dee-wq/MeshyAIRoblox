# Pricing model

Prices are centralized in `src/Shared/Config.luau`; the UI must retrieve live developer-product prices from Roblox before showing a Robux amount.

## Current baseline

The cost model uses the standard DevEx rate of **$0.0038 per Earned Robux** and Roblox's normal **70% creator share** for developer products. It deliberately does not assume the higher U.S. 18+ rate.

| Operation | Estimated provider cost | Suggested product price | Net at standard DevEx | Contribution margin before hosting |
|---|---:|---:|---:|---:|
| Isolated reference image, low quality | $0.006 | 29 R$ | $0.077 | 92% |
| Isolated reference image, medium quality | $0.023 | 49 R$ | $0.130 | 82% |
| Isolated reference image, high quality | $0.091 | 129 R$ | $0.343 | 73% |
| Text → textured Smart Topology model | $0.300 | 159 R$ | $0.423 | 29% |
| Approved image → textured Smart Topology model | $0.300 | 159 R$ | $0.423 | 29% |
| Player avatar → textured Smart Topology model | $0.300 | 159 R$ | $0.423 | 29% |
| Priority queue pass | negligible variable cost | 29 R$ | $0.077 | n/a |
| Custom Image Upload game pass | moderation/hosting over account lifetime | 249 R$ one time | $0.662 | usage-dependent |

The guided path's default is the **low** reference tier: **29 R$** for the reviewable reference image and **159 R$** after approval for conversion, or **188 R$ total**. At the estimates above it nets about **$0.500** against **$0.306** of provider cost, a 39% contribution margin before hosting. Low-quality reference generation is intentionally used as the default disposable-reference price point; Meshy, rather than the reference image itself, produces the final player-facing texture.

### Reference image quality tiers

`Config.Generation.ImageQualityTiers` in `src/Shared/Config.luau` exposes three purchasable tiers — `LOW`, `MEDIUM`, `HIGH` — each backed by its own developer product (`ImagePreviewLow`/`ImagePreviewMedium`/`ImagePreviewHigh`) because a single Roblox product cannot carry more than one price. Each tier maps directly onto the matching OpenAI `quality` request value (`low`/`medium`/`high`), so no separate cost model is needed per style/detail combination — quality alone drives provider cost.

The medium/high provider-cost estimates above are scaled off the existing low-tier baseline using OpenAI's published low→medium (~3.8×) and low→high (~15×) cost ratios; they are **planning estimates, not measured billing data**. All three product IDs are currently configured. `backend/src/pricing.ts` exports `IMAGE_QUALITY_PROVIDER_COST_USD` as the single source of truth for these per-tier cost estimates — update it there first, then recompute the suggested prices above whenever real OpenAI spend is measured per tier.

### Avatar-sourced generation

`Config.Products.AvatarConversion` (159 R$) is the same Meshy image → Smart Topology model operation and provider cost as `ImageConversion` above — only the source image differs. Instead of an uploaded asset or an OpenAI-generated reference, the Roblox server sends the backend only the player's chosen `avatarView` (headshot/bust/full body) on `POST /v1/jobs`, alongside the `playerUserId` `BackendService:CreateJob` already stamps on every job; the **backend**, not the Roblox server, resolves those into a real fetchable image URL from Roblox's public Thumbnails web API (`https://thumbnails.roblox.com/v1/users/{avatar-headshot|avatar-bust|avatar}?userIds={playerUserId}`) before handing it to Meshy. This split exists because Roblox's `HttpService` is blocked from reaching Roblox-owned domains at the platform level — confirmed live ("HttpService is not allowed to access that Roblox resource") when an earlier version of this feature tried to resolve the URL from the Roblox server itself — so only a backend running outside Roblox's sandbox can make that call. The client-side live preview in the wizard is unaffected by any of this: it uses the `rbxthumb://` content reference directly (see `avatarThumbnail()` in `App.luau`), which the Roblox engine resolves locally with no HTTP call at all. Because the operation and cost are identical to `ImageConversion`, it is priced the same and added to `GENERATION_TOKEN_PRODUCTS` so Forge Token payment prices against the same worst-case-ad formula as every other model-producing product (see "Forge Tokens" below) rather than the much cheaper non-generation markup.

### Avatar Graphics (standalone images)

The Avatar Graphics section (`App:_RenderAvatarGraphics`, backend job kind `AVATAR_GRAPHIC`) never produces a mesh or accessory at all — it turns the player's avatar render into a single stylized image via one OpenAI `images.edit` call and stops there. Because the provider cost is a single image call with no Meshy pipeline behind it, it reuses the exact same purchasable tiers and developer products as the reference-image step above (`ImagePreviewLow`/`Medium`/`High`) rather than introducing a fourth set of Creator Hub products to maintain. `GenerationService:CreateAvatarGraphic` picks the product key straight from `Config.Generation.ImageQualityTiers`, so this pricing model needs no dedicated row in `Config.Products` and moves automatically if the reference-image tiers above are ever repriced.

The **249 R$ Custom Image Upload pass** is a permanent premium entitlement. Upload moderation and previewing are included after purchase, but every approved image still uses the normal **159 R$ Image → 3D Conversion** product. This prevents unlimited Meshy cost exposure while giving the pass durable value. At the baseline conversion assumptions, the pass nets about **$0.662** before lifetime moderation and hosting expense; review its attach rate, upload frequency, and support burden before changing the price.

Calculations use:

```text
net_usd = robux_price × 0.70 × 0.0038
price_for_cost_markup = ceil((provider_cost + hosting_reserve) × (1 + markup) / (0.70 × 0.0038))
price_for_contribution_margin = ceil((provider_cost + hosting_reserve) / ((1 - margin) × 0.70 × 0.0038))
```

At the current Meshy API schedule, Smart Topology T2 is 5 credits for geometry plus 10 credits for a 2K texture. A Pro plan advertised at $20 per 1,000 credits makes 15 credits approximately $0.30. These inputs must be reviewed whenever Meshy, OpenAI, Roblox revenue share, or DevEx pricing changes.

“30% markup on cost” and “30% contribution margin” are different targets. In the user's $0.30 example, 159 R$ creates about $0.123 gross contribution: a 41% cost markup or 29% contribution margin before hosting. With a hypothetical $0.02 per-job hosting reserve, those become roughly 32% and 24%. The configured price therefore clears the requested +30% cost markup with that reserve, but should not be described as a 30% contribution margin.

Railway expense and failed-generation retries are usage-dependent. Before launch, replace every estimate with one week of measured cost per completed job, then adjust prices to maintain the chosen margin. Keep the UI driven by Roblox's live localized product information so Roblox Plus discounts display correctly while creator earnings remain based on the base price. If Railway already defines `OPENAI_IMAGE_QUALITY`, change it to `low`; the application default cannot override an explicit environment variable.

## Player-to-player sales

Plus transfers accept 10–500 R$ per transaction. Roblox sends 90% to the listed item's owner and 10% to the experience. A listing price is the gross amount the buyer approves; the UI must show both values. Transfer Robux received by a player are not DevEx eligible, while the experience's 10% share is eligible.

## Forge Tokens (rewarded-ad currency)

Forge Tokens split across **two profile fields that are never merged**, because they carry different real-money guarantees:

- `profile.tokens` — backed by an actual rewarded ad view, a direct purchase of the one-token `AdRewardTokens` reward product, or the 70-token `TokenPack70` store product. May fund a generation product (Direct Forge, every reference-image quality tier, Image → 3D Conversion, Avatar → 3D Conversion) or the Priority Pass.
- `profile.bonusTokens` — free grants with no revenue behind them: achievements, the seven-day login calendar, AFK lounge time, invites, and group join. May **only ever** buy the Priority Pass.

Neither pool ever pays for the permanent Custom Image Upload game pass, which Roblox's rewarded-video-ad system cannot back (only developer products qualify). Players choose Robux or Tokens; the server, not the client, decides the price, which pool a purchase draws from, and grants the benefit either way — `CommerceService:BeginIntentWithTokens` enforces all of this regardless of what a client sends, and rejects any product key that is neither a generation product nor the Priority Pass outright.

Roblox's Rewarded Video Ads feature (`AdService`) does not let a developer reward Robux directly, does not expose live per-view ad revenue to a running experience (only a delayed Analytics dashboard), and wraps an existing developer product — see [Roblox's rewarded video ad documentation](https://create.roblox.com/docs/production/promotion/rewarded-video-ads) before changing any of this. `Config.Products.AdRewardTokens` (3 R$) is the one-token reward unit; `Config.Products.TokenPack70` is a separate 10-Robux store offer that grants 70. Separate receipt handlers keep an ad completion at exactly `TokenGrantPerAd` while normal pack purchases receive `TokenPackGrant`.

**Why generation pricing changed rather than the feature being cut.** This system originally shipped on a guess — "1 token == 1 Robux of value" — because Roblox does not expose live ad revenue to a running server. Measured Analytics > Rewarded Video data puts one completed ad at only **~0.12–0.44 Robux** of real revenue, 18×–66× less than that guess. Under the old numbers (8 tokens/ad, `AdRewardTokens` at 8 R$), a player could fund a 159 R$ generation — `ceil(159 × 1.2) = 191` tokens, ~24 ad watches — using ad revenue worth only ~2.9–10.6 Robux, while that generation burns real OpenAI/Meshy provider cost (up to $0.30, see the pricing table above) regardless of how it was paid for. That is a guaranteed loss on every such redemption at that price. The fix is not to remove token payment for generations but to price it against the **worst** measured ad rather than an optimistic average, so it stays safe no matter which ad actually played:

```text
generation_token_price = ceil(robux_price × TokenPurchaseMarkup / WorstCaseAdRevenuePerAd)
```

With `TokenPurchaseMarkup` at 1.2× and `WorstCaseAdRevenuePerAd` at 0.12 (the low end of the measured range, deliberately — see `Config.Ads.WorstCaseAdRevenuePerAd`'s comment), this simplifies to `ceil(robux_price × 10)`. A 159 R$ Direct Forge generation costs **1,590 tokens** — 1,590 completed ad watches at the default 1-token grant — which at even the worst-case 0.12 Robux/ad nets Forge 190.8 Robux of real ad revenue. Converted at the standard DevEx rate this table already uses ($0.0038/Robux, applied directly since ad revenue is credited to the developer net rather than as a marketplace sale subject to the 70% creator-share split), that is about **$0.72** against the generation's roughly $0.30 provider cost — comfortably ahead, not a break-even trade. That margin is deliberate, matching the same "net Forge more than the equivalent Robux purchase, not merely break even" principle the original design intended, just calibrated against a real number instead of a guess. Crucially, this price can *only* be paid from `profile.tokens`: no amount of free `bonusTokens`, however large, is ever eligible, so a zero-revenue grant can never subsidize a real-cost purchase.

Priority Pass keeps the simpler, friendlier formula — `ceil(robux_price × TokenPurchaseMarkup)`, no division by `WorstCaseAdRevenuePerAd` — because its variable cost is negligible: the 29 R$ pass costs `ceil(29 × 1.2) = 35` tokens, ~35 ad watches (or fewer, since it draws from `bonusTokens` first). There is no realistic amount of grinding that turns a Priority Pass redemption into a loss, which is exactly why it accepts both pools while generations accept only one.

Re-derive `TokenGrantPerAd`, `TokenPurchaseMarkup`, and `WorstCaseAdRevenuePerAd` if real eCPM data moves meaningfully from the ~0.12–0.44 Robux figure above, the same way `IMAGE_QUALITY_PROVIDER_COST_USD` gets revisited against measured OpenAI spend — and if it does, move `WorstCaseAdRevenuePerAd` to the new *worst* case, not the new average. Review `TokenPackGrant` separately against the 10-Robux product's intended promotional value.

### Login calendar and AFK lounge

The seven-day repeating login calendar grants 3/6/10/20/40/50/70 `bonusTokens`; missing a UTC day resets it to day 1. The AFK lounge grants one `bonusToken` every three minutes, capped at 140 per UTC day. Both are server-authoritative and intentionally Priority-Pass-only, so unattended or retention rewards never subsidize OpenAI/Meshy provider cost. Rewarded ads shown from the lounge still credit normal `profile.tokens` at one per completed receipt. Roblox requires player activation for each ad, so the lounge auto-checks availability but never silently chains playback.

There is deliberately no daily cap on rewarded-ad requests (`AdRewardService:RequestAd`). Every completed ad is real, positive revenue at even the worst measured rate, so unlike a free grant there is no scenario where letting a player watch more of them costs Forge anything — the only limits are Roblox's own ad inventory and how long a player is willing to sit there. `profile.adWatch` still tracks a per-UTC-day watch count, but purely as a "watched N today" stat for the client; nothing gates on it. A player funding a 1,590-token generation entirely through ads is, from Forge's side, 1,590 ad impressions' worth of revenue landed instead of one 159 R$ purchase — a substitution, not a loss, however fast or slow they get there.

### Non-earning token budget (achievements)

`src/Shared/Achievements.luau`'s milestones — including the automatic `COMPLETIONIST` bonus for unlocking every other one — each grant `profile.bonusTokens`, never `profile.tokens`, with no ad revenue or Robux payment behind them. `Config.Achievements.NonEarningTokenBudget` (110) caps their combined total, but it is no longer what keeps that safe to hand out for free: that used to rest on a basket of every purchasable product and the same "1 token ≈ 1 Robux" assumption the section above shows measured ad revenue never supported. Since `bonusTokens` can only ever buy the near-zero-marginal-cost Priority Pass — never a generation product, regardless of this number — the budget is a game-balance ceiling, stopping the achievement pool from trivializing Priority Pass access, not a revenue calculation. `AchievementService` still sums every achievement's `tokens` at startup and refuses to boot if that total exceeds the budget, so raising an achievement's reward still needs this reviewed, just for pacing rather than solvency.

### Arcade weekly rewards

The Arcade (Flappy Bird, Dino Runner, Color Switch, Neon Snake, Block Stacker — see `src/Client/UI/Games/` and `src/Client/UI/GamesHub.luau`) is a client-only session-time feature, not part of the generation economy, but `Config.Arcade.WeeklyRewards` (360/200/80 tokens for 1st/2nd/3rd each game, every week — lowered 20% from an original 450/250/100) puts real free tokens on the other end of it. Unlike every other free grant in this file, these are credited to `profile.tokens` — the same fully-spendable pool ad rewards and Robux purchases fund, generations included — not the spend-restricted `bonusTokens` pool. That is a deliberate, studio-owner-approved exception to the "only ever gain money" rule everything else here follows, not an oversight: worst case is every rank in every game won by a different player every week, 3,200 tokens total, worth roughly 2.7 generations (~$0.80) at the pricing above. It's accepted as an engagement cost in the same category as ad-funded tokens, sized small enough to absorb even at the worst-case ceiling — not something `NonEarningTokenBudget` needs to account for (that budget is specifically achievement pacing, and achievement/daily-check-in/win-back grants are still `bonusTokens`-only).

`ArcadeService` on the server treats every submitted score as unverified client input — sanity-clamped to `Config.Arcade.MaxSubmittableScore`, only ever improving a player's own stored best for the week, never trusted as ground truth the way a purchase receipt or ad-completion callback is — because unlike everything else with a token reward in this file, these games run with no server authority over gameplay at all. Payouts are checked once at server startup and every 30 minutes thereafter (Roblox has no persistent cross-week process to schedule against), and use a DataStore compare-and-swap on `Config.DataStores.ArcadeMeta` so that whichever of the many concurrent server instances gets there first is the only one that actually grants a given week's rewards.
