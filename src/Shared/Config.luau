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
		ImagePreviewMedium = { Id = 0, SuggestedPrice = 49 },
		ImagePreviewHigh = { Id = 0, SuggestedPrice = 129 },
		ImageConversion = { Id = 3709322228, SuggestedPrice = 159 },
		PriorityPass = { Id = 3709322304, SuggestedPrice = 29 },
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
	},

	Studio = {
		AllowMockPurchases = true,
		AllowMockBackend = true,
	},
})
