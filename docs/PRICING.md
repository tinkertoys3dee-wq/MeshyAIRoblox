# Pricing model

Prices are centralized in `src/Shared/Config.luau`; the UI must retrieve live developer-product prices from Roblox before showing a Robux amount.

## Current baseline

The cost model uses the standard DevEx rate of **$0.0038 per Earned Robux** and Roblox's normal **70% creator share** for developer products. It deliberately does not assume the higher U.S. 18+ rate.

| Operation | Estimated provider cost | Suggested product price | Net at standard DevEx | Contribution margin before hosting |
|---|---:|---:|---:|---:|
| Isolated reference image, GPT Image 2 medium | $0.053 | 29 R$ | $0.077 | 31% |
| Text → textured Smart Topology model | $0.300 | 159 R$ | $0.423 | 29% |
| Approved image → textured Smart Topology model | $0.300 | 159 R$ | $0.423 | 29% |
| Priority queue pass | negligible variable cost | 29 R$ | $0.077 | n/a |

The guided path is two explicit purchases: **29 R$** for the reviewable reference image and **159 R$** after approval for conversion, or **188 R$ total**. At the estimates above it nets about **$0.500** against **$0.353** of provider cost, a 29% contribution margin before hosting.

Calculations use:

```text
net_usd = robux_price × 0.70 × 0.0038
price_for_cost_markup = ceil((provider_cost + hosting_reserve) × (1 + markup) / (0.70 × 0.0038))
price_for_contribution_margin = ceil((provider_cost + hosting_reserve) / ((1 - margin) × 0.70 × 0.0038))
```

At the current Meshy API schedule, Smart Topology T2 is 5 credits for geometry plus 10 credits for a 2K texture. A Pro plan advertised at $20 per 1,000 credits makes 15 credits approximately $0.30. These inputs must be reviewed whenever Meshy, OpenAI, Roblox revenue share, or DevEx pricing changes.

“30% markup on cost” and “30% contribution margin” are different targets. In the user's $0.30 example, 159 R$ creates about $0.123 gross contribution: a 41% cost markup or 29% contribution margin before hosting. With a hypothetical $0.02 per-job hosting reserve, those become roughly 32% and 24%. The configured price therefore clears the requested +30% cost markup with that reserve, but should not be described as a 30% contribution margin.

Railway expense and failed-generation retries are usage-dependent. Before launch, replace every estimate with one week of measured cost per completed job, then adjust prices to maintain the chosen margin. Keep the UI driven by Roblox's live localized product information so Roblox Plus discounts display correctly while creator earnings remain based on the base price.

## Player-to-player sales

Plus transfers accept 10–500 R$ per transaction. Roblox sends 90% to the listed item's owner and 10% to the experience. A listing price is the gross amount the buyer approves; the UI must show both values. Transfer Robux received by a player are not DevEx eligible, while the experience's 10% share is eligible.
