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
		PriorityPass = { Id = 3709322304, SuggestedPrice = 29 },
		-- The Forge Tokens pack: a normal Robux-purchasable product AND the
		-- product Roblox's rewarded-video-ad reward is created from
		-- (AdService:CreateAdRewardFromDevProductId). Roblox requires an ad
		-- reward to be "a developer product which would normally be available
		-- to purchase with Robux" worth 3-10 Robux, and forbids rewarding
		-- Robux directly — see docs/PRICING.md "Forge Tokens" section before
		-- changing this price or Ads.TokenGrantPerPurchase. Priced at Roblox's
		-- allowed floor: a completed rewarded ad measures at only ~0.12-0.44
		-- Robux of real revenue (see Ads.TokenGrantPerPurchase below), nowhere
		-- close to what an 8 Robux anchor implied, so there is no case for
		-- pricing this above the minimum.
		AdRewardTokens = { Id = 3709706813, SuggestedPrice = 3 },
	},

	Passes = {
		-- Permanent access to player- or creator-group-owned Image/Decal references.
		CustomImageUpload = { Id = 1955130723, SuggestedPrice = 249 },
	},

	AvatarCreationTokens = {
		Hat = "",
		HairAccessory = "",
		FaceAccessory = "",
		NeckAccessory = "",
		ShoulderAccessory = "",
		FrontAccessory = "",
		BackAccessory = "3e34e666-3680-419a-9a11-46b38a8664c3",
		WaistAccessory = "",
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
		-- Tokens granted both when a player buys AdRewardTokens directly with
		-- Robux and when they complete a rewarded video ad for it (Roblox
		-- requires both paths grant the identical benefit). 1 token per ad —
		-- see WorstCaseAdRevenuePerAd below for why this needs to be a small,
		-- clean unit rather than a larger batch: each token stands in for one
		-- ad's worth of real revenue, and CommerceService's generation-token
		-- price is derived directly from that equivalence.
		TokenGrantPerPurchase = 1,
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
		-- Granted every day RetentionService:CheckIn sees a new UTC day,
		-- independent of the existing every-3rd-day Priority Pass reward.
		DailyCheckInTokens = 2,
		-- A lapsed player's streak already resets to 1 on any gap (see
		-- RetentionService:CheckIn), but that alone doesn't distinguish
		-- "away one day" from "away a month" -- the second player is the one
		-- actually at risk of not coming back, and is worth a specifically
		-- warmer welcome. A gap of at least this many UTC days on top of the
		-- normal DailyCheckInTokens reward grants WinBackBonusTokens once.
		WinBackGapDays = 3,
		-- Free (bonusTokens, no revenue behind it, same as every other
		-- retention grant) top-up for a returning lapsed player. Kept modest
		-- and one-shot per return -- this is a welcome, not a subsidy.
		WinBackBonusTokens = 6,
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

	-- Client-side arcade minigames (Flappy Bird, Dino Runner, Color Switch) —
	-- purely for session time and fun, not part of the Forge Tokens economy.
	-- Their scores are simulated entirely on the client with no server
	-- authority over gameplay, unlike everything else with a token reward in
	-- this file, so ArcadeService:SubmitScore treats every submission as
	-- unverified input: sanity-clamped, never trusted as truth the way a
	-- purchase receipt or an ad-completion callback is.
	Arcade = {
		Games = { "FlappyBird", "DinoRunner", "ColorSwitch" },
		-- Weekly reward for each game's top 3 players by that game's best
		-- score of the week. Index = placement: [1] = 1st, [2] = 2nd,
		-- [3] = 3rd. Unlike every other free grant in this file, ArcadeService
		-- credits these to `tokens`, not `bonusTokens` — fully spendable,
		-- generations included. That's a deliberate, bounded exception to the
		-- "only gain money" guarantee (approved for the engagement value):
		-- worst case is 800/game * #Games = 2400 tokens/week, worth ~2
		-- generations (~$0.60) at the pricing in Config.Generation. See
		-- ArcadeService's module header and docs/PRICING.md for the full
		-- reasoning; raising these numbers meaningfully needs that math
		-- re-checked, not just a game-balance judgment call.
		WeeklyRewards = { 450, 250, 100 },
		-- Sanity ceiling against an obviously spoofed score reaching the
		-- leaderboard store. Can't stop a determined cheater on a
		-- client-simulated game, only bound the damage one can do.
		MaxSubmittableScore = 100000,
	},

	Marketplace = {
		MinimumTransferRobux = 10,
		MaximumTransferRobux = 500,
		SellerShare = 0.90,
		PageSize = 24,
		TransferIntentLifetimeSeconds = 30 * 60,
	},

	DataStores = {
		Player = "ForgeUGC_Player_v1",
		ItemIndex = "ForgeUGC_ItemIndex_v1",
		ReceiptClaims = "ForgeUGC_ReceiptClaims_v1",
		LikesLeaderboard = "ForgeUGC_LikesLeaderboard_v1",
		-- Single-key store: which week's arcade payout has already been
		-- processed. Per-game-per-week score stores are named
		-- programmatically by ArcadeService (they need a fresh key every
		-- week, so a fixed list here wouldn't fit the pattern the other
		-- stores use).
		ArcadeMeta = "ForgeUGC_ArcadeMeta_v1",
	},

	Leaderboard = {
		TopCount = 10,
	},

	Studio = {
		AllowMockPurchases = true,
		AllowMockBackend = true,
	},
})
