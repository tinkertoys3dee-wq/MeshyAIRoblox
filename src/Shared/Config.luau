--!strict

-- Public, non-secret configuration. API keys and the Roblox-to-backend shared
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
		AdRewardTokens = { Id = 0, SuggestedPrice = 3 },
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

	-- Forge Tokens: an ad-earned alternative to Robux, but ONLY for the
	-- Priority Pass — see the CommerceService:BeginIntentWithTokens whitelist
	-- before assuming this covers anything else. It used to cover Direct
	-- Forge, every reference-image tier, and Image → 3D Conversion too; that
	-- was a real money-losing bug, not just an aggressive design choice, and
	-- is why it no longer does (see below).
	--
	-- Roblox does not expose live per-view ad revenue to a running
	-- experience (only a 1-day-delayed Analytics dashboard), so this section
	-- originally shipped on a guess: "1 token == 1 Robux of value, matching
	-- AdRewardTokens.SuggestedPrice." Measured Analytics > Rewarded Video
	-- data puts one completed ad at only ~0.12-0.44 Robux of real revenue —
	-- 18x-66x less than that guess. Under the old 8-tokens-per-ad grant, a
	-- player could fund a 159 Robux generation (needing ceil(159 * 1.2) =
	-- 191 tokens, ~24 ad watches) using ad revenue worth only ~2.9-10.6
	-- Robux, while the generation itself burns real OpenAI/Meshy provider
	-- cost regardless of how it was paid for (as much as $0.30 — see
	-- docs/PRICING.md). That is a guaranteed loss on every such redemption,
	-- not a break-even trade, so token payment for every real-provider-cost
	-- product was removed rather than merely re-priced: no token count fixes
	-- a currency worth fractions of a Robux being spent against a cost
	-- measured in tens of cents. Priority Pass is the one purchasable item
	-- with negligible variable cost, so it is the only one tokens may ever
	-- buy, regardless of source (ad, achievement, daily check-in, invite,
	-- group join).
	Ads = {
		-- Tokens granted both when a player buys AdRewardTokens directly with
		-- Robux and when they complete a rewarded video ad for it (Roblox
		-- requires both paths grant the identical benefit). Kept at
		-- 1 token == 1 Robux of AdRewardTokens.SuggestedPrice, just at that
		-- product's new, much lower floor price — see the note above for why
		-- the token grant itself was never the real fix.
		TokenGrantPerPurchase = 3,
		-- Buying Priority Pass with tokens costs ceil(robuxPrice * this)
		-- tokens instead of Robux, so the token path is deliberately worth
		-- more to Forge than the matching Robux price, not merely equal to it.
		TokenPurchaseMarkup = 1.2,
		-- Anti-grind / anti-abuse cap on rewarded-ad requests per player per
		-- UTC day. Resets at UTC midnight.
		MaxAdWatchesPerDay = 20,
	},

	Retention = {
		-- Granted every day RetentionService:CheckIn sees a new UTC day,
		-- independent of the existing every-3rd-day Priority Pass reward.
		DailyCheckInTokens = 2,
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
			FIRST_CREATION = 0,
			FIVE_CREATIONS = 0,
			FIRST_EQUIP = 0,
			FIRST_FIT_PRESET = 0,
			FIRST_PUBLISH = 0,
			FIRST_LISTING = 0,
			FIRST_LIKE_GIVEN = 0,
			FIRST_TRY_ON = 0,
			FIRST_AD_WATCHED = 0,
			FIRST_MARKETPLACE_PURCHASE = 0,
			STREAK_SEVEN = 0,
			FIRST_INVITE_SENT = 0,
			GROUP_JOINED = 0,
			COMPLETIONIST = 0,
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
		-- Achievement tokens, like every other Forge Token, can now only buy
		-- the near-zero-marginal-cost Priority Pass (see
		-- CommerceService:BeginIntentWithTokens), so handing them out for
		-- free costs Forge no real provider spend regardless of this number.
		-- 110 is kept as a game-balance ceiling — stopping the achievement
		-- pool from trivializing Priority Pass access, not a revenue
		-- calculation — so raising an achievement's reward still needs this
		-- reviewed, just for pacing rather than solvency.
		NonEarningTokenBudget = 110,
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
	},

	Leaderboard = {
		TopCount = 10,
	},

	Studio = {
		AllowMockPurchases = true,
		AllowMockBackend = true,
	},
})
