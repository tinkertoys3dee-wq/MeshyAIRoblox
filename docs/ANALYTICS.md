# Analytics and growth instrumentation

Analytics are implemented as a privacy-conscious product feedback loop, not as a guarantee of Roblox discovery placement. The server logs Roblox onboarding, funnel, economy, and custom events; the client may send only an allowlisted event name with enumerated fields. AI prompts, item names, free-form searches, secrets, and other personally identifying text are never sent as analytics fields

## Launch scorecard

Review these by new/returning player, device class, creation method, group membership, and Plus status where Roblox dashboards permit it:

| Goal | Primary metrics | Diagnostic events |
|---|---|---|
| Activation | onboarding completion; first creation attempt; first fit saved | `OnboardingStep`, generation funnel steps 1–4, `AccessoryFitSaved` |
| Reliability | paid-to-ready completion; median generation duration; retry rate; completion/failure rate per reference-image quality tier | `GenerationCompleted`, `GenerationFailed` (both carry `productKey`, e.g. `ImagePreviewLow`/`Medium`/`High`) |
| Retention | D1/D7 retention; sessions per user; median session length; streak return rate | `ForgeSessionStarted`, `ForgeSessionEnded`, `DailyStudioCheckIn` |
| Creation demand | direct/guided mix; image approval-to-conversion; generations per creator | generation funnel method field and profile counters |
| Upload feature | pass prompt-to-purchase; unlock-to-first-upload; moderation success; upload-to-conversion | `CustomImagePassPrompted`, `GamePassPurchased`, `customImagesSubmitted`, reference funnel |
| Avatar engagement | catalog try-ons per session; generated-item fits; publishes | `CatalogSearch`, `CatalogItemTried`, `AccessoryFitSaved`, publish counters |
| Fit preset adoption | save-to-reuse rate; presets saved per player; deletion rate | `FitPresetSaved`, `FitPresetApplied`, `FitPresetDeleted` |
| Catalog search quality | filter adoption (sort/creator/price); zero-result rate by filter combination | `CatalogSearch` (`sortType`, `hasCreatorFilter`, `hasPriceFilter`, `resultCount`) |
| Accessibility adoption | high-contrast/reduce-motion/UI-scale opt-in rate; page reach including Settings | `SettingsChanged`, `AppOpenedTab` (`page = "Settings"`) |
| Community health | discovery visits; try-on rate; likes/favorites per view | marketplace funnel, reaction and view counters |
| Monetization | payer conversion; ARPDAU; revenue per completed model; priority-pass attach rate | economy events by SKU plus completion events |
| Marketplace liquidity | listed originals; try-on-to-transfer rate; transfer completion | marketplace funnel steps 1–4 |

## Funnels

- Generation: creation attempt → method/prompt submitted → paid job queued → model ready to fit.
- Reference: AI-image attempt → prompt submitted → paid image job queued → reference ready; or custom-image submission → visual moderation queued → reference ready.
- Marketplace: Discover opened → community item tried → Plus transfer prompted → personal copy granted.
- Onboarding: entered Forge → understood the paths → understood fitting/marketplace → ready to create.

## Operating cadence

During beta, inspect reliability and purchase reconciliation daily, cohorts weekly, and price/cost margin after every provider or Roblox pricing change. Prioritize fixes in this order: paid job loss, moderation/policy violations, completion rate, activation, retention, then monetization experiments. Run one material UX or price experiment at a time so the result is interpretable.

The daily theme, three-day priority reward, group queue benefit, free community try-on, and Roblox catalog lab are intended to create useful return reasons and longer customization sessions. Treat each as a hypothesis: keep it only if cohort data improves without degrading generation completion, player trust, or safety.
