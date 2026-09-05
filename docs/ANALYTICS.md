# Analytics and growth instrumentation

Analytics are implemented as a privacy-conscious product feedback loop, not as a guarantee of Roblox discovery placement. The server logs Roblox onboarding, funnel, economy, and custom events; the client may send only an allowlisted event name with enumerated fields. AI prompts, item names, free-form searches, secrets, and other personally identifying text are never sent as analytics fields

## Launch scorecard

Review these by new/returning player, device class, creation method, group membership, and Plus status where Roblox dashboards permit it:

| Goal | Primary metrics | Diagnostic events |
|---|---|---|
| Activation / play-through | tutorial view-to-choice; starter looks shown; apply click/request/success/visible; personalization; outfit save; next action; first creation attempt | `VisualTutorialShown`, `VisualTutorialCompleted` (`choice`), onboarding funnel, `FirstLookGuide`, `MakeoverAction`, `StarterLookApplied`, `StyleSprintStarted`/`Completed`, `FirstLookStepCompleted`, `FirstLookJourneyCompleted`, `makeover` and `creator_journey` funnels, generation funnel |
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
| Social playtime | runway open-to-join, join-to-ready, ready-to-complete, and first-to-second-round rates; votes per round; rounds per session; friend-invite use from runway | `RunwayOpened`, `runway` funnel, `RunwayLookLocked`, `RunwayVoteCast`, `RunwayRoundCompleted`, `RunwayEncoreCompleted`, `GameInviteSent` |
| Progression / D1-D7 return | Creator levels reached; XP source mix; daily first-round and two-round Encore claims; weekly repeat participation | `CreatorXPGranted` (`reason`), `CreatorLevelReached`, `RunwayRoundCompleted`, `RunwayEncoreCompleted`, `RunwayWeeklyRewardClaimed` |
| Feature reach / virality | achievement completion rate per milestone; daily-bonus claim rate; invite-sent rate | `AchievementUnlocked` (`achievement`), `DailyStudioCheckIn` (`tokensGranted`), `GameInviteSent` |
| Community health | discovery visits; marketplace inventory availability; try-on attempt-to-success rate; likes/favorites per view; leaderboard engagement | marketplace funnel, `CommunityMarketplaceLoaded`, `CommunityTryOnAttempted`/`Succeeded`/`Failed`, reaction and view counters, `CommunityLikeToggled` |
| Monetization | offer reach; generate-click rate; native-prompt open/accept/cancel; payer conversion; ARPDAU; revenue per completed model; priority-pass attach rate | `GenerationOfferShown`, generation funnel, `ProductPromptOpened`, `ProductPromptClosed` (`purchased`), `ProductPurchaseCompleted`, economy events by SKU plus completion events |
| Marketplace liquidity | listed originals; try-on-to-transfer rate; transfer completion | marketplace funnel steps 1–4 |

## Funnels

- Generation: creation attempt → method/prompt submitted → paid job queued → model ready to fit.
- Reference: AI-image attempt → prompt submitted → paid image job queued → reference ready; or custom-image submission → visual moderation queued → reference ready.
- Marketplace: Discover opened → community item successfully worn → Plus transfer prompted → personal copy granted. A button press is not step two unless the model actually attaches to the avatar.
- Onboarding: entered Forge → chose a starting path → opened the free First Look → successfully wore a free look. These milestones are server-authored from real actions; choosing the initial path no longer auto-emits steps three and four.
- First-session tutorial: `VisualTutorialShown` → `VisualTutorialCompleted`, split by the enumerated `START_FREE`, `MAKE_OWN`, or `SKIP` choice. The one-screen tutorial is versioned, so the completion event fires once per materially new tutorial version, including for existing accounts.
- Generation checkout diagnosis: `GenerationOfferShown` means the price was actually visible after onboarding, the generation funnel means the player pressed the create button and submitted valid fields, `ProductPromptOpened` means Roblox's native prompt opened, `ProductPromptClosed.purchased` separates accept from cancel, and `ProductPurchaseCompleted` proves the receipt was granted. Do not treat a Create-page render hidden behind the tutorial as an offer impression.
- First makeover: studio opened → starter look applied → one distinct item changed → outfit saved. `MakeoverAction` separately distinguishes looks displayed, apply clicked, request started, server success, avatar visibly updated, failures, and the chosen next action.
- Runway: runway entered → look locked → vote cast (when another entrant exists) → style round completed. A solo round legitimately skips the optional vote step.
- Daily Encore: first completed round → second completed round → 10 bonus-token and 50-XP reward. Compare its completion rate, session length, and next-day return against otherwise similar first-round completers.

## Operating cadence

During beta, inspect reliability and purchase reconciliation daily, cohorts weekly, and price/cost margin after every provider or Roblox pricing change. Prioritize fixes in this order: paid job loss, moderation/policy violations, completion rate, activation, retention, then monetization experiments. Run one material UX or price experiment at a time so the result is interpretable. Before changing a price, first distinguish low offer reach, low create-button intent, native-prompt cancellation, and receipt failure with the events above; those four causes require different fixes.

The makeover journey, daily Style Sprint, Forge Runway, two-round Daily Encore, Creator levels, weekly spotlight, daily free quest trio, group queue benefit, free community try-on, and Roblox catalog lab are hypotheses, not permanent complexity. The first release questions are whether starter-look visible-update reaches 65% of makeover opens and whether minute-two survival reaches 70%; then measure personalization, save, and next-action conversion. Split `REQUEST_FAILED` by its bounded failure code so catalog/API faults are not misread as weak creative intent. Runway, avatar art, and contextual custom-UGC creation appear only after a satisfying saved look. Do not increase rewards or add purchase pressure until these cohort cuts are understood.
