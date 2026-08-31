--!strict

-- Public, non-secret configuration. API keys and the Roblox-to-backend share
-- secret belong in Railway variables / Creator Hub secrets, never here.
return table.freeze({
	Brand = {
		Name = "FORGE UGC",
		Tagline = "Imagine it. Fit it. Wear it.",
	},

	Backend = {
		BaseUrl = "https://meshyairoblox-production.up.railway.app", -- Example: https://forge-ugc-production.up.railway.app
		SecretName = "FORGE_BACKEND_SECRET",
	},

	Group = {
		Id = 15575113, -- Your Roblox group ID
		GenerationSpeedMultiplier = 0.90,
		ExtraQueueSlots = 1,
	},

	Generation = {
		BaseQueueSlots = 1,
		PromptMinLength = 6,
		PromptMaxLength = 500,
		StylePresets = {
			{ Id = "AUTO", Label = "Auto" },
			{ Id = "ANIME", Label = "Anime" },
			{ Id = "REALISTIC", Label = "Realistic" },
			{ Id = "STYLIZED", Label = "Stylized" },
			{ Id = "LOW_POLY", Label = "Low poly" },
			{ Id = "FANTASY", Label = "Fantasy" },
		},
		DetailLevels = {
			{ Id = "CLEAN", Label = "Clean" },
			{ Id = "BALANCED", Label = "Balanced" },
			{ Id = "INTRICATE", Label = "Intricate" },
		},
		-- Purchasable reference-image quality tiers. Each maps 1:1 onto an
		-- OpenAI gpt-image quality parameter (see backend/src/pricing.ts) and a
		-- distinct developer product below, since Roblox developer products
		-- cannot carry a dynamic price per purchase.
		ImageQualityTiers = {
			{ Id = "LOW", Label = "Low", ProductKey = "ImagePreviewLow", OpenAIQuality = "low" },
			{ Id = "MEDIUM", Label = "Medium", ProductKey = "ImagePreviewMedium", OpenAIQuality = "medium" },
			{ Id = "HIGH", Label = "High", ProductKey = "ImagePreviewHigh", OpenAIQuality = "high" },
		},
		-- Which render of the player's own current Roblox avatar seeds an
		-- AVATAR_TO_3D generation. `ThumbType` is the matching rbxthumb://
		-- content type this game's client uses for its own live preview.
		-- `Endpoint` is purely reference documentation for the external
		-- backend, which is the one that must resolve a real fetchable
		-- image URL -- from `GET https://thumbnails.roblox.com/v1/users/
		-- {Endpoint}?userIds={playerUserId}` -- since Roblox's HttpService
		-- is blocked from reaching Roblox-owned domains, so the Roblox
		-- server can never make that call itself (confirmed live: "HttpService
		-- is not allowed to access that Roblox resource"). The two fields
		-- are deliberately kept next to each other since they must always
		-- refer to the same render.
		AvatarViews = {
			{ Id = "HEADSHOT", Label = "Headshot", ThumbType = "AvatarHeadShot", Endpoint = "avatar-headshot" },
			{ Id = "BUST", Label = "Bust", ThumbType = "AvatarBust", Endpoint = "avatar-bust" },
			{ Id = "FULL_BODY", Label = "Full body", ThumbType = "Avatar", Endpoint = "avatar" },
		},
		TargetTriangles = 3600,
		HardTriangleLimit = 3999,
		HardVertexLimit = 3999,
		TextureResolution = 2048,
		StatusPollSeconds = 4,
		IntentLifetimeSeconds = 15 * 60,
		-- A completed model isn't handed to the player the moment the
		-- pipeline finishes; it clears a standard queue first, randomized
		-- within this range each time so it doesn't read as a fixed
		-- timer. This is what Products.PriorityPass and its free grants
		-- (RetentionService's streak reward, AdRewardService-funded
		-- retries) actually buy relief from -- see
		-- PriorityModelQueueSeconds below. Only applies to the two
		-- methods that produce a model (TEXT_TO_3D, IMAGE_TO_3D); the
		-- reference-image step is unaffected.
		ModelQueueSeconds = { Minimum = 130, Maximum = 220 },
		-- Group members and anyone who has spent a Priority Pass on this
		-- generation (GenerationService._Prepare's `priority` flag) clear
		-- the same queue in this much shorter range instead of skipping
		-- it outright -- a real, felt improvement rather than an instant
		-- finish, which would look exploitable and undercut why anyone
		-- would buy it again next time.
		PriorityModelQueueSeconds = { Minimum = 20, Maximum = 45 },
	},

	-- Shared by the fitting UI and the authoritative server validator so the
	-- controls can never advertise a transform that SaveFit later rejects.
	Fitting = {
		Position = { Minimum = -10, Maximum = 10, Step = 0.05 },
		Rotation = { Minimum = -360, Maximum = 360, Step = 5 },
		Scale = { Minimum = 0.1, Maximum = 8, Step = 0.05 },
	},

	Products = {
		DirectGeneration = { Id = 3709322103, SuggestedPrice = 159 },
		-- Tiered reference-image pricing. Low keeps the original product ID and
		-- price; Medium/High are new products awaiting Creator Hub IDs (0 = not
		-- configured yet, same convention as every other placeholder below).
		ImagePreviewLow = { Id = 3709322158, SuggestedPrice = 29 },
		ImagePreviewMedium = { Id = 3709537948, SuggestedPrice = 49 },
		ImagePreviewHigh = { Id = 3709538054, SuggestedPrice = 129 },
		ImageConversion = { Id = 3709322228, SuggestedPrice = 159 },
		-- Same Meshy image → Smart Topology model operation and provider
		-- cost as ImageConversion above -- only the image source differs
		-- (the player's own Roblox avatar render, resolved to a real
		-- fetchable URL by the backend from the avatarView and
		-- playerUserId GenerationService sends it, instead of an
		-- uploaded/generated reference) -- so it's priced identically.
		AvatarConversion = { Id = 3709863858, SuggestedPrice = 159 },
		PriorityPass = { Id = 3709322304, SuggestedPrice = 29 },
		-- Dedicated 70-token Robux pack. Keep this separate from the developer
		-- product wrapped by rewarded video below: a completed ad remains worth
		-- exactly one token, while this deliberately stronger 10-Robux offer
		-- gives paying players a useful amount at once. Create this repeatable
		-- developer product in Creator Hub and replace 0 with its ID.
		TokenPack70 = { Id = 3710290071, SuggestedPrice = 10 },
		-- Rewarded-video wrapper product. Roblox recommends an ad reward worth
		-- 3-10 Robux and its official flow wraps a normal developer product, so
		-- this stays a separate one-token product rather than overloading the
		-- 70-token store pack above.
		AdRewardTokens = { Id = 3709706813, SuggestedPrice = 3 },
	},

	Passes = {
		-- Permanent access to player- or creator-group-owned Image/Decal references.
		CustomImageUpload = { Id = 1955130723, SuggestedPrice = 249 },
	},

	-- Forge Tokens: an ad-earned (or directly Robux-purchased) alternative to
	-- Robux. Split across two profile fields that must never be merged — see
	-- ProfileService.defaultProfile — because they carry different real-money
	-- guarantees: profile.tokens (this section) is backed by an actual ad
	-- view or Robux payment and may fund generation products; profile.
	-- bonusTokens (free grants — achievements, daily check-in, invites,
	-- group join) has no revenue behind it and may only ever buy the
	-- near-zero-cost Priority Pass. See
	-- CommerceService:BeginIntentWithTokens for the enforcement.
	--
	-- Roblox does not expose live per-view ad revenue to a running
	-- experience (only a 1-day-delayed Analytics dashboard), so this section
	-- originally shipped on a guess: "1 token == 1 Robux of value, matching
	-- AdRewardTokens.SuggestedPrice," and let tokens fund every purchasable
	-- product at that rate. Measured Analytics > Rewarded Video data puts one
	-- completed ad at only ~0.12-0.44 Robux of real revenue — 18x-66x less
	-- than that guess — while a generation product costs real OpenAI/Meshy
	-- provider money per use regardless of how it's paid for (as much as
	-- $0.30, see docs/PRICING.md). At the old rate, a 159 Robux generation
	-- (needing ceil(159 * 1.2) = 191 tokens, ~24 ad watches under the old
	-- 8-tokens-per-ad grant) could be funded with ad revenue worth only
	-- ~2.9-10.6 Robux: a guaranteed loss on every such redemption.
	--
	-- Generation products are priced steeply enough to close that gap
	-- outright rather than merely narrow it: WorstCaseAdRevenuePerAd anchors
	-- the token price to the *worst* measured ad, not the average, so Forge
	-- stays ahead even in the least profitable case. See docs/PRICING.md
	-- "Forge Tokens" for the full derivation.
	Ads = {
		-- The AdRewardTokens product grants this same benefit whether acquired
		-- from a completed rewarded video or bought directly from its Roblox
		-- product page. The in-game Robux store instead sells TokenPack70.
		TokenGrantPerAd = 1,
		TokenPackGrant = 70,
		-- The conservative floor of the measured ~0.12-0.44 Robux-per-ad
		-- range (see the note above) — deliberately the *worst* case, not the
		-- average, so generation-token pricing stays safe even on the least
		-- profitable ads. Revisit this only when new measured data justifies
		-- moving the floor, never to make token pricing more generous on
		-- optimism alone.
		WorstCaseAdRevenuePerAd = 0.12,
		-- Buying Priority Pass with tokens costs ceil(robuxPrice * this)
		-- tokens instead of Robux, so the token path is deliberately worth
		-- more to Forge than the matching Robux price, not merely equal to
		-- it. Generation products use this same markup but divided by
		-- WorstCaseAdRevenuePerAd instead of applied directly — see
		-- CommerceService.tokenPriceFor — since their real provider cost
		-- means a friendly 1.2x markup on face value alone is nowhere near
		-- enough to stay safe.
		TokenPurchaseMarkup = 1.2,
		-- Deliberately no daily cap on rewarded-ad requests: every completed
		-- ad is real, positive revenue for Forge at even the worst measured
		-- rate (WorstCaseAdRevenuePerAd above), so there's no financial
		-- reason to ever stop a player from watching more. AdRewardService
		-- still tracks a per-UTC-day watch count (profile.adWatch), but only
		-- as a "watched N today" stat, never to gate the button.
	},

	Retention = {
		-- Seven-day repeating login calendar. Missing a UTC day resets the
		-- streak and therefore returns the next claim to day 1. These are free
		-- bonusTokens (Priority-Pass eligible, never provider-cost generation
		-- spend), which keeps the generous day-7 payoff economically bounded.
		DailyStreakTokens = { 3, 6, 10, 20, 40, 50, 70 },
		-- A lapsed player's streak already resets to 1 on any gap (see
		-- RetentionService:CheckIn), but that alone doesn't distinguish
		-- "away one day" from "away a month" -- the second player is the one
		-- actually at risk of not coming back, and is worth a specifically
		-- warmer welcome. A gap of at least this many UTC days on top of the
		-- normal DailyStreakTokens reward grants WinBackBonusTokens once.
		WinBackGapDays = 3,
		-- Free (bonusTokens, no revenue behind it, same as every other
		-- retention grant) top-up for a returning lapsed player. Kept modest
		-- and one-shot per return -- this is a welcome, not a subsidy.
		WinBackBonusTokens = 6,
		-- Three short daily objectives, each touching a different part of
		-- the app in one sitting (see RetentionService:MarkQuest) rather
		-- than rewarding just one of them -- session depth, not just
		-- session count, is the point. bonusTokens, same Priority-Pass-only
		-- restriction as every other grant in this table.
		Quests = {
			{ key = "TRY_STYLE", label = "Try any avatar accessory", icon = "◇", tokens = 3 },
			{ key = "RUNWAY", label = "Finish a Forge Runway round", icon = "◆", tokens = 3 },
			{ key = "ARCADE", label = "Post a score in the Arcade", icon = "🎮", tokens = 3 },
		},
		-- Extra one-shot bonus for clearing all Quests the same UTC day, on
		-- top of the per-quest tokens above.
		QuestClearBonusTokens = 6,
		-- Escalating bonus on top of the every-3rd-day Priority Pass credit,
		-- keyed by streak day. Deliberately lands on 7/14/30 -- the exact
		-- D7/D30 windows Roblox's own retention analytics (and, by
		-- extension, discovery/recommendation weighting) are most sensitive
		-- to, so these are the days most worth making feel like a genuine
		-- occasion rather than another routine check-in. bonusTokens, same
		-- restriction as every other grant here (Priority Pass only).
		StreakMilestones = {
			[7] = { tokens = 0, priorityPasses = 1 },
			[14] = { tokens = 0, priorityPasses = 1 },
			[30] = { tokens = 0, priorityPasses = 2 },
		},
		-- Once a streak passes the highest configured milestone, that same
		-- tier repeats every this-many days instead of the table needing an
		-- entry for every future day forever.
		StreakMilestoneRepeatDay = 30,
		-- A free first-session route through the systems that make Forge feel
		-- like a game. Only OPEN_STUDIO is client-reported; every later step is
		-- completed from a successful server action (try-on, runway lock-in,
		-- round completion). Rewards are bonusTokens, so they can accelerate a
		-- queue but can never pay OpenAI/Meshy provider cost.
		FirstLookJourney = {
			{ key = "OPEN_STUDIO", label = "Open your creator studio", icon = "✦" },
			{ key = "TRY_STYLE", label = "Try any accessory", icon = "◇" },
			{ key = "JOIN_RUNWAY", label = "Lock in a runway look", icon = "◆" },
			{ key = "COMPLETE_RUNWAY", label = "Finish a style round", icon = "★" },
		},
		FirstLookStepTokens = 2,
		FirstLookCompletionTokens = 12,
		FirstLookCompletionXP = 100,
	},

	-- A populated server-wide style round lasts exactly six minutes. A solo
	-- server skips the meaningless ballot phase rather than padding time;
	-- otherwise two rounds form the 10-15 minute session target through active
	-- styling, avatar viewing, voting, and results. Routine rewards are XP or
	-- bonusTokens, never provider-backed tokens.
	Runway = {
		Themes = {
			"Cyber royalty",
			"Soft cloud fantasy",
			"Retro arcade hero",
			"Deep-sea explorer",
			"Celestial streetwear",
			"Nature reclaimed",
			"Villain entrance",
			"Candy-colored chaos",
			"Ancient future",
			"Prismatic festival",
		},
		IntermissionSeconds = 30,
		StylingSeconds = 210,
		VotingSeconds = 90,
		ResultsSeconds = 30,
		MinimumEntrantsForPlacement = 2,
		ParticipationXP = 25,
		VoteXP = 5,
		PlacementXP = { 100, 60, 40 },
		DailyFirstRoundBonusTokens = 5,
		-- Completing a second ready look on the same UTC day turns a single
		-- round into a visible, finite encore objective. These are free
		-- bonusTokens, so the reward can accelerate a queue but can never pay
		-- OpenAI or Meshy provider cost.
		DailyEncoreRounds = 2,
		DailyEncoreBonusTokens = 10,
		DailyEncoreXP = 50,
		WeeklyPlacementXP = { 600, 350, 200 },
		LeaderboardSize = 10,
	},

	CreatorProgression = {
		ModelCompletionXP = 75,
		GraphicCompletionXP = 35,
		FirstPublishXP = 50,
	},

	AFK = {
		-- Server-authoritative lounge reward. Free AFK earnings stay in the
		-- bonusTokens pool, so they can buy queue acceleration without exposing
		-- OpenAI/Meshy spend. A daily cap prevents unattended farms from growing
		-- without bound while still making a normal lounge session feel active.
		IntervalSeconds = 180,
		TokensPerInterval = 1,
		DailyTokenCap = 140,
	},

	Commerce = {
		-- One-time bonusTokens welcome the first time CommerceService ever
		-- processes a real Robux receipt for this player (see
		-- CommerceService:_ProcessReceipt). Same bonusTokens pool and
		-- Priority-Pass-only restriction as every other free grant in this
		-- file -- a real purchase happening doesn't license a separate free
		-- grant into the revenue-backed `tokens` pool. The point is making a
		-- second purchase feel like an easy yes, not subsidizing the first.
		FirstPurchaseBonusTokens = 10,
	},

	-- Each achievement in src/Shared/Achievements.luau also awards a Roblox
	-- badge on unlock (BadgeService:AwardBadgeAsync). Create one Badge asset
	-- per id below in Creator Hub and paste its numeric ID in; 0 means "not
	-- configured yet" (AchievementService silently skips awarding until then,
	-- same convention as every other placeholder ID in this file) — token
	-- rewards still work without a badge ID. Keys must match
	-- Achievements.luau's `id` fields exactly, including "COMPLETIONIST", the
	-- bonus achievement AchievementService grants automatically once every
	-- other achievement is unlocked.
	Achievements = {
		BadgeIds = {
			FIRST_CREATION = 1988483841053665,
			FIVE_CREATIONS = 1247423063402341,
			FIRST_EQUIP = 4167969644689488,
			FIRST_FIT_PRESET = 2277407725453843,
			FIRST_PUBLISH = 3504089854919994,
			FIRST_LISTING = 99594973192757,
			FIRST_LIKE_GIVEN = 3461971222499396,
			FIRST_TRY_ON = 181312400705376,
			FIRST_AD_WATCHED = 88267055892597,
			FIRST_MARKETPLACE_PURCHASE = 537031408819152,
			STREAK_SEVEN = 1187463061094437,
			FIRST_INVITE_SENT = 950632947701447,
			GROUP_JOINED = 1311980823175385,
			COMPLETIONIST = 22321998004466,
		},
		-- Soft cap on the combined token value of every achievement plus the
		-- completionist bonus (AchievementService errors at startup if
		-- Achievements.luau's totals exceed this — see that file for the
		-- current sum). None of these tokens are backed by ad revenue or a
		-- Robux payment, unlike a rewarded-ad watch or a direct Forge Tokens
		-- purchase.
		--
		-- This budget is no longer what keeps that safe to hand out for free.
		-- It used to be sized against a basket of every purchasable product,
		-- on the theory that the 20% token markup's "extra" tokens covered
		-- the free ones — a real-money guarantee that only held if tokens
		-- were worth what that basket assumed, which measured ad revenue
		-- (~0.12-0.44 Robux per ad, see Ads above) showed was never true.
		-- Achievement tokens land in profile.bonusTokens, not profile.tokens
		-- (see ProfileService.defaultProfile), which can only ever buy the
		-- near-zero-marginal-cost Priority Pass (see
		-- CommerceService:BeginIntentWithTokens) — never a generation
		-- product, no matter this number — so handing them out for free
		-- costs Forge no real provider spend regardless of its size. 110 is
		-- kept as a game-balance ceiling — stopping the achievement pool from
		-- trivializing Priority Pass access, not a revenue calculation — so
		-- raising an achievement's reward still needs this reviewed, just
		-- for pacing rather than solvency.
		NonEarningTokenBudget = 110,
	},

	-- Client-side arcade minigames (Flappy Bird, Dino Runner, Color Switch,
	-- Neon Snake, Block Stacker, Brick Breaker, Reflex Tap, Prism Merge,
	-- Meteor Rush) — purely for session time and fun, not part of the Forge
	-- Tokens economy. Their
	-- scores are simulated entirely on the client with no server authority
	-- over gameplay, unlike everything else with a token reward in this
	-- file, so ArcadeService:SubmitScore treats every submission as
	-- unverified input: sanity-clamped, never trusted as truth the way a
	-- purchase receipt or an ad-completion callback is.
	Arcade = {
		Games = {
			"FlappyBird",
			"DinoRunner",
			"ColorSwitch",
			"NeonSnake",
			"BlockStacker",
			"BrickBreaker",
			"ReflexTap",
			"PrismMerge",
			"MeteorRush",
			"SkyHopper",
			"EchoMatch",
		},
		-- Weekly reward for each game's top 3 players by that game's best
		-- score of the week. Index = placement: [1] = 1st, [2] = 2nd,
		-- [3] = 3rd. Unlike every other free grant in this file, ArcadeService
		-- credits these to `tokens`, not `bonusTokens` — fully spendable,
		-- generations included. That's a deliberate, bounded exception to the
		-- "only gain money" guarantee (approved for the engagement value):
		-- worst case is 266/game * #Games (11) = 2926 tokens/week, worth
		-- roughly 2.4 generations (~$0.73) at the pricing in
		-- Config.Generation. See ArcadeService's module header and
		-- docs/PRICING.md for the full reasoning; raising these numbers
		-- meaningfully needs that math re-checked, not just a game-balance
		-- judgment call. (Originally lowered 30% from 360/200/80 to
		-- 252/140/56, lowered another 30% to 176/98/39, then lowered another
		-- 15% to the whole-token values below -- the total ceiling still
		-- ticked up slightly versus the 176/98/39 era despite the per-game
		-- cut, purely from SkyHopper/EchoMatch adding two more games to
		-- multiply against. Keep this comment's math in sync with
		-- WeeklyRewards and Games if either changes again.)
		WeeklyRewards = { 150, 83, 33 },
		-- Sanity ceiling against an obviously spoofed score reaching the
		-- leaderboard store. Can't stop a determined cheater on a
		-- client-simulated game, only bound the damage one can do.
		MaxSubmittableScore = 100000,
		-- One-time-per-game-per-day bonus for clearing that day's Daily
		-- Challenge target (see Shared/DailyChallenge.luau). Unlike
		-- WeeklyRewards above, this is a normal bonusTokens grant --
		-- Priority-Pass-only, same restriction as every other free grant in
		-- this file, not the fully-spendable `tokens` exception WeeklyRewards
		-- carries. (Lowered 20% from an original 8 to 6, then another 15% to
		-- the value below.)
		DailyChallengeBonusTokens = 5,
	},

	Marketplace = {
		MinimumTransferRobux = 10,
		MaximumTransferRobux = 500,
		SellerShare = 0.90,
		PageSize = 24,
		TransferIntentLifetimeSeconds = 30 * 60,
		-- Fixed tip amounts a viewer can send a creator straight from a
		-- Discover item/graphic, no listing required. A fixed allowlist
		-- (checked server-side, never trusting a client-supplied amount)
		-- keeps this on the same MarketplaceService:PromptRobuxTransferAsync
		-- primitive SetListing-backed purchases already use, just without a
		-- listing or a copy grant behind it. All four sit inside
		-- Minimum/MaximumTransferRobux above.
		TipTiers = { 10, 25, 50, 100 },
		-- Bounds for the owner-set title/description shown on a Discover
		-- item/graphic and its detail overlay. Both fields are optional
		-- (an owner can clear either), unlike a generation prompt.
		TitleMaxLength = 40,
		DescriptionMaxLength = 240,
	},

	DataStores = {
		Player = "ForgeUGC_Player_v1",
		ItemIndex = "ForgeUGC_ItemIndex_v1",
		GraphicIndex = "ForgeUGC_GraphicIndex_v1",
		ReceiptClaims = "ForgeUGC_ReceiptClaims_v1",
		LikesLeaderboard = "ForgeUGC_LikesLeaderboard_v1",
		-- Single-key store: which week's arcade payout has already been
		-- processed. Per-game-per-week score stores are named
		-- programmatically by ArcadeService (they need a fresh key every
		-- week, so a fixed list here wouldn't fit the pattern the other
		-- stores use).
		ArcadeMeta = "ForgeUGC_ArcadeMeta_v1",
		RunwayMeta = "ForgeUGC_RunwayMeta_v1",
	},

	Leaderboard = {
		TopCount = 10,
	},

	Studio = {
		AllowMockPurchases = true,
		AllowMockBackend = true,
	},
})
