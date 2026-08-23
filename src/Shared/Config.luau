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
		-- changing this price or Ads.TokenGrantPerPurchase.
		AdRewardTokens = { Id = 0, SuggestedPrice = 8 },
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

	-- Forge Tokens: an ad-earned alternative to Robux for the same purchasable
	-- products (see docs/PRICING.md). Roblox does not expose live per-view ad
	-- revenue to a running experience (only a 1-day-delayed Analytics
	-- dashboard), so this whole section is a creator-tuned estimate, not a
	-- measured value — revisit it against Monetization > Ads > Analytics >
	-- Rewarded Video after launch.
	Ads = {
		-- Tokens granted both when a player buys AdRewardTokens directly with
		-- Robux and when they complete a rewarded video ad for it (Roblox
		-- requires both paths grant the identical benefit). 1 token == 1 Robux
		-- of value at that baseline, matching AdRewardTokens.SuggestedPrice.
		TokenGrantPerPurchase = 8,
		-- Buying any other product with tokens costs ceil(robuxPrice * this)
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
			COMPLETIONIST = 0,
		},
		-- Hard cap on the combined token value of every achievement plus the
		-- completionist bonus (AchievementService errors at startup if
		-- Achievements.luau's totals exceed this — see that file for the
		-- current sum). None of these tokens are backed by ad revenue or a
		-- Robux payment, unlike a rewarded-ad watch or a direct Forge Tokens
		-- purchase, so their total must stay inside the margin the 20% token
		-- markup already earns Forge, not stack on top of it.
		--
		-- Budget derivation: if a player funded one purchase of every
		-- purchasable product (DirectGeneration 159 + ImagePreviewLow 29 +
		-- ImagePreviewMedium 49 + ImagePreviewHigh 129 + ImageConversion 159 +
		-- PriorityPass 29 = 554 R$) entirely with ad-earned tokens, Forge
		-- earns (Ads.TokenPurchaseMarkup - 1) * 554 ≈ 111 tokens' worth of
		-- margin from that one pass. This budget spends well under that
		-- (currently ~86 of 110), so the one-time achievement pool never
		-- outruns what a single engaged, ad-watching player's markup alone
		-- already covers — before counting any of their other ad activity or
		-- direct Robux spend. Recompute 110 if product prices or the markup
		-- change materially.
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
