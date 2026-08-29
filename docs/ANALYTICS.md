# Analytics and growth instrumentation

Analytics are implemented as a privacy-conscious product feedback loop, not as a guarantee of Roblox discovery placement. The server logs Roblox onboarding, funnel, economy, and custom events; the client may send only an allowlisted event name with enumerated fields. AI prompts, item names, free-form searches, secrets, and other personally identifying text are never sent as analytics fields

## Launch scorecard

Review these by new/returning player, device class, creation method, group membership, and Plus status where Roblox dashboards permit it:

| Goal | Primary metrics | Diagnostic events |
|---|---|---|
| Activation / play-through | onboarding completion; First Look step and round completion; first creation attempt | onboarding funnel, `FirstLookStepCompleted`, `FirstLookJourneyCompleted`, `creator_journey` funnel, generation funnel |
| Reliability | paid-to-ready completion; median generation duration; retry rate; completion/failure rate per reference-image quality tier | `GenerationCompleted`, `GenerationFailed` (both carry `productKey`, e.g. `ImagePreviewLow`/`Medium`/`High`) |
| Retention | D1/D7 retention; sessions per user; median session length; streak return rate | `ForgeSessionStarted`, `ForgeSessionEnded`, `DailyStudioCheckIn` |
| Creation demand | direct/guided mix; image approval-to-conversion; generations per creator | generation funnel method field and profile counters |
| Upload feature | pass prompt-to-purchase; unlock-to-first-upload; moderation success; upload-to-conversion | `CustomImagePassPrompted`, `GamePassPurchased`, `customImagesSubmitted`, reference funnel |
| Avatar engagement | catalog try-ons per session; generated-item fits; publishes | `CatalogSearch`, `CatalogItemTried`, `AccessoryFitSaved`, publish counters |
| Fit preset adoption | save-to-reuse rate; presets saved per player; deletion rate | `FitPresetSaved`, `FitPresetApplied`, `FitPresetDeleted` |
| Catalog search quality | filter adoption (sort/creator/price); zero-result rate by filter combination | `CatalogSearch` (`sortType`, `hasCreatorFilter`, `hasPriceFilter`, `resultCount`) |
| Accessibility adoption | high-contrast/reduce-motion/UI-scale opt-in rate; page reach including Settings | `SettingsChanged`, `AppOpenedTab` (`page = "Settings"`) |
| Forge Tokens / ad engagement | rewarded-ad completion rate; 70-token pack conversion; tokens earned vs. spent; token-vs-Robux purchase mix | `AdRewardGranted`, `TokenPackGranted`, `TokenPurchase` (`product`), economy events for `AdRewardTokens`/`TokenPack70` |
| AFK / login retention | lounge entries and duration; passive tokens per session/day; seven-day reward-day return rate | `AfkLoungeEntered`, `AfkLoungeLeft`, `AfkTokensGranted`, `DailyStudioCheckIn` (`tokensGranted`) |
| Social playtime | runway open-to-join, join-to-ready, and ready-to-complete rates; votes per round; rounds per session; friend-invite use from runway | `RunwayOpened`, `runway` funnel, `RunwayLookLocked`, `RunwayVoteCast`, `RunwayRoundCompleted`, `GameInviteSent` |
| Progression / D1-D7 return | Creator levels reached; XP source mix; daily first-round claims; weekly repeat participation | `CreatorXPGranted` (`reason`), `CreatorLevelReached`, `RunwayRoundCompleted`, `RunwayWeeklyRewardClaimed` |
| Feature reach / virality | achievement completion rate per milestone; daily-bonus claim rate; invite-sent rate | `AchievementUnlocked` (`achievement`), `DailyStudioCheckIn` (`tokensGranted`), `GameInviteSent` |
| Community health | discovery visits; try-on rate; likes/favorites per view; leaderboard engagement | marketplace funnel, reaction and view counters, `CommunityLikeToggled` |
| Monetization | payer conversion; ARPDAU; revenue per completed model; priority-pass attach rate | economy events by SKU plus completion events |
| Marketplace liquidity | listed originals; try-on-to-transfer rate; transfer completion | marketplace funnel steps 1–4 |

## Funnels

- Generation: creation attempt → method/prompt submitted → paid job queued → model ready to fit.
- Reference: AI-image attempt → prompt submitted → paid image job queued → reference ready; or custom-image submission → visual moderation queued → reference ready.
- Marketplace: Discover opened → community item tried → Plus transfer prompted → personal copy granted.
- Onboarding: entered Forge → chose a starting path → First Look introduced → ready to style.
- First Look: studio opened → accessory tried → runway look locked → style round completed.
- Runway: runway entered → look locked → vote cast (when another entrant exists) → style round completed. A solo round legitimately skips the optional vote step.

## Operating cadence

During beta, inspect reliability and purchase reconciliation daily, cohorts weekly, and price/cost margin after every provider or Roblox pricing change. Prioritize fixes in this order: paid job loss, moderation/policy violations, completion rate, activation, retention, then monetization experiments. Run one material UX or price experiment at a time so the result is interpretable.

The First Look journey, Forge Runway, Creator levels, weekly spotlight, daily free quest trio, daily theme, three-day priority reward, group queue benefit, free community try-on, and Roblox catalog lab are intended to create useful return reasons and longer customization sessions. Treat each as a hypothesis: keep it only if cohort data improves without degrading generation completion, player trust, or safety. The first release question is whether First Look completion lifts qualified play-through and six-minute retention; the second is whether one completed runway round predicts D1/D7 return. Do not increase rewards or add purchase friction until those two cohort cuts are understood.
