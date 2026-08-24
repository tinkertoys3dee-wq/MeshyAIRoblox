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
| Priority queue pass | negligible variable cost | 29 R$ | $0.077 | n/a |
| Custom Image Upload game pass | moderation/hosting over account lifetime | 249 R$ one time | $0.662 | usage-dependent |

The guided path's default is the **low** reference tier: **29 R$** for the reviewable reference image and **159 R$** after approval for conversion, or **188 R$ total**. At the estimates above it nets about **$0.500** against **$0.306** of provider cost, a 39% contribution margin before hosting. Low-quality reference generation is intentionally used as the default disposable-reference price point; Meshy, rather than the reference image itself, produces the final player-facing texture.

### Reference image quality tiers

`Config.Generation.ImageQualityTiers` in `src/Shared/Config.luau` exposes three purchasable tiers — `LOW`, `MEDIUM`, `HIGH` — each backed by its own developer product (`ImagePreviewLow`/`ImagePreviewMedium`/`ImagePreviewHigh`) because a single Roblox product cannot carry more than one price. Each tier maps directly onto the matching OpenAI `quality` request value (`low`/`medium`/`high`), so no separate cost model is needed per style/detail combination — quality alone drives provider cost.

The medium/high provider-cost estimates above are scaled off the existing low-tier baseline using OpenAI's published low→medium (~3.8×) and low→high (~15×) cost ratios; they are **planning estimates, not measured billing data**. `ImagePreviewLow` reuses the original product ID and 29 R$ price; `ImagePreviewMedium` and `ImagePreviewHigh` are new products with `Id = 0` (safe-configuration placeholders, same convention as every other unconfigured ID in this file) until their Creator Hub developer products are created and their IDs are filled in. `backend/src/pricing.ts` exports `IMAGE_QUALITY_PROVIDER_COST_USD` as the single source of truth for these per-tier cost estimates — update it there first, then recompute the suggested prices above, whenever real OpenAI spend is measured per tier.

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

Forge Tokens are an alternative to Robux **only for the Priority Pass**. They used to also pay for Direct Forge, every reference-image quality tier, and Image → 3D Conversion; that was a real money-losing bug, not an aggressive design choice, and the section below explains why it was removed rather than merely re-priced. Never for the permanent Custom Image Upload game pass either, which Roblox's rewarded-video-ad system cannot back (only developer products qualify). Players choose Robux or Tokens for the Priority Pass specifically; the server, not the client, decides the price and grants the benefit either way, and `CommerceService:BeginIntentWithTokens` hard-rejects any other product key regardless of what a client sends.

Roblox's Rewarded Video Ads feature (`AdService`) does not let a developer reward Robux directly, does not expose live per-view ad revenue to a running experience (only a 1-day-delayed Analytics dashboard), and requires the reward to be **an existing developer product worth 3–10 Robux** that is also normally purchasable — see [Roblox's rewarded video ad documentation](https://create.roblox.com/docs/production/promotion/rewarded-video-ads) before changing any of this. `Config.Products.AdRewardTokens` (3 R$, Roblox's allowed floor) is that product; `AdRewardService` registers one grant handler for it that runs whether a player buys it directly with Robux or completes a rewarded ad for it, and both paths must keep granting the same `Config.Ads.TokenGrantPerPurchase` (3 tokens) — 1 token equal to 1 Robux of that product's own price.

**Why the scope was cut, not just the price.** This system originally shipped on a guess — "1 token == 1 Robux of value" — because Roblox does not expose live ad revenue to a running server. Measured Analytics > Rewarded Video data puts one completed ad at only **~0.12–0.44 Robux** of real revenue, 18×–66× less than that guess. Under the old numbers (8 tokens/ad, `AdRewardTokens` at 8 R$), a player could fund a 159 R$ generation — `ceil(159 × 1.2) = 191` tokens, ~24 ad watches — using ad revenue worth only ~2.9–10.6 Robux, while that generation burns real OpenAI/Meshy provider cost (up to $0.30, see the pricing table above) regardless of how it was paid for. That is a guaranteed loss on every such redemption. No token count fixes it: a currency worth fractions of a Robux per unit earned cannot safely be spent against a cost measured in tens of cents, at any markup. Priority Pass is the one purchasable product with negligible variable cost, so it is the only one Forge Tokens — from *any* source: ads, achievements, daily check-in, invites, group join — may ever buy.

Spending tokens on the pass still deliberately costs more than its matching Robux price: `Config.Ads.TokenPurchaseMarkup` (1.2×) means the 29 R$ pass costs `ceil(29 × 1.2) = 35` tokens, ~12 completed rewarded ads at the default grant size. Because the pass's variable cost is negligible, every one of those ad views is close to pure incremental revenue for Forge — there is no realistic amount of grinding that turns this into a loss, unlike the removed generation path. Re-derive `TokenGrantPerPurchase` and `TokenPurchaseMarkup` if real eCPM data moves meaningfully from the ~0.12–0.44 Robux figure above, the same way `IMAGE_QUALITY_PROVIDER_COST_USD` gets revisited against measured OpenAI spend — but do not restore token payment for any product with real provider cost without re-deriving this whole section from scratch.

`Config.Ads.MaxAdWatchesPerDay` (20) bounds both grind and repeated `AdService:ShowRewardedVideoAdAsync` server calls per player per UTC day; it is a request cap, not a completion guarantee, so a skipped or unfilled ad still counts against it — acceptable given Roblox reports rewarded-video completion rates above 90%.

### Non-earning token budget (achievements)

`src/Shared/Achievements.luau`'s milestones — including the automatic `COMPLETIONIST` bonus for unlocking every other one — each grant Forge Tokens with no matching ad revenue or Robux payment behind them, unlike a rewarded ad or a direct Forge Tokens purchase. `Config.Achievements.NonEarningTokenBudget` (110) caps their combined total, but it is no longer what keeps that safe to hand out for free: that used to rest on a basket of every purchasable product and the same "1 token ≈ 1 Robux" assumption the section above shows measured ad revenue never supported. Since achievement tokens, like every other Forge Token, can now only buy the near-zero-marginal-cost Priority Pass, the budget is a game-balance ceiling — stopping the achievement pool from trivializing Priority Pass access — not a revenue calculation. `AchievementService` still sums every achievement's `tokens` at startup and refuses to boot if that total exceeds the budget, so raising an achievement's reward still needs this reviewed, just for pacing rather than solvency.
