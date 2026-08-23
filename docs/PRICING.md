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
