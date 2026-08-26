--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AccessoryFit = require(ReplicatedStorage:WaitForChild("AccessoryFit"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local ModerationService = require(script.Parent.ModerationService)

local GenerationService = {}
GenerationService.__index = GenerationService

local TERMINAL = {
	SUCCEEDED = true,
	FAILED = true,
	IMAGE_READY = true,
}

local ACCESSORY_TYPES = {
	Hat = true,
	HairAccessory = true,
	FaceAccessory = true,
	NeckAccessory = true,
	ShoulderAccessory = true,
	FrontAccessory = true,
	BackAccessory = true,
	WaistAccessory = true,
}

local STYLE_PRESETS = {}
for _, option in Config.Generation.StylePresets do
	STYLE_PRESETS[option.Id] = true
end

local DETAIL_LEVELS = {}
for _, option in Config.Generation.DetailLevels do
	DETAIL_LEVELS[option.Id] = true
end

local IMAGE_QUALITY_TIERS: { [string]: { ProductKey: string, OpenAIQuality: string } } = {}
for _, tier in Config.Generation.ImageQualityTiers do
	IMAGE_QUALITY_TIERS[tier.Id] = { ProductKey = tier.ProductKey, OpenAIQuality = tier.OpenAIQuality }
end

local AVATAR_VIEWS: { [string]: boolean } = {}
for _, view in Config.Generation.AvatarViews do
	AVATAR_VIEWS[view.Id] = true
end

-- Unlike every other generation method, AVATAR_TO_3D already has a fixed,
-- concrete source image (the player's own avatar) plus an explicit
-- accessoryType, so a prompt is optional guidance rather than the only
-- description of what to build. FilterPrompt still requires *some* real
-- text (Config.Generation.PromptMinLength), so a blank/whitespace-only
-- prompt substitutes this fixed, always-safe default instead of blocking
-- generation over missing text.
local AVATAR_DEFAULT_PROMPT = "Match the style, colors, and details of my current Roblox avatar."

-- Same rationale as AVATAR_DEFAULT_PROMPT above: AVATAR_GRAPHIC always has a
-- fixed source (the player's own avatar render), so a scene/theme prompt is
-- optional creative direction rather than the only description of the image.
local AVATAR_GRAPHIC_DEFAULT_PROMPT = "A striking portrait celebrating my current Roblox avatar."

local IMAGE_ASSET_TYPES = {
	[1] = true, -- Image
	[13] = true, -- Decal
}

local GENERATION_FAILURE_LABELS = {
	PROVIDER_DOWNLOAD_FAILED = "Meshy finished, but its model file could not be downloaded",
	INVALID_GLB = "Meshy returned an unreadable model file",
	MESH_JOIN_FAILED = "The generated model parts could not be combined",
	MULTI_MESH = "The generated model could not be reduced to one accessory mesh",
	MULTI_PRIMITIVE = "The generated materials could not be reduced to one accessory mesh",
	MULTI_MESH_NODE = "The generated scene could not be reduced to one accessory mesh",
	TRIANGLE_LIMIT = "The repaired model exceeded the triangle limit",
	VERTEX_LIMIT = "The repaired model exceeded the vertex limit",
	MISSING_UV = "The generated model did not contain usable texture coordinates",
	MISSING_TEXTURE = "The generated model did not contain a usable color texture",
	OUTPUT_CONTENT_REJECTED = "The generated visual did not pass the output safety check",
	ROBLOX_UPLOAD_FAILED = "Roblox could not accept the validated model upload",
}

local function generationFailureText(errorCode: string): string
	local label = GENERATION_FAILURE_LABELS[errorCode] or "Generation stopped before a usable item was produced"
	return string.format("%s (%s)", label, errorCode)
end

local function productKeyFor(method: string): string
	if method == "IMAGE_PREVIEW" then
		return "ImagePreviewLow"
	elseif method == "IMAGE_TO_3D" then
		return "ImageConversion"
	elseif method == "IMAGE_UPLOAD" then
		return "CustomImageUpload"
	elseif method == "AVATAR_TO_3D" then
		return "AvatarConversion"
	elseif method == "AVATAR_GRAPHIC" then
		return "ImagePreviewLow"
	end
	return "DirectGeneration"
end

local function readGuidance(payload: { [string]: any }): (boolean, string, string)
	local stylePreset = if type(payload.stylePreset) == "string" then payload.stylePreset else "AUTO"
	local detailLevel = if type(payload.detailLevel) == "string" then payload.detailLevel else "BALANCED"
	if not STYLE_PRESETS[stylePreset] then
		return false, "INVALID_STYLE_PRESET", ""
	end
	if not DETAIL_LEVELS[detailLevel] then
		return false, "INVALID_DETAIL_LEVEL", ""
	end
	return true, stylePreset, detailLevel
end

local function deterministicId(prefix: string, source: string): string
	return prefix .. "_" .. string.sub(string.gsub(source, "%W", ""), 1, 54)
end

local function defaultFit(accessoryType: string): { [string]: any }
	return {
		position = { x = 0, y = 0, z = 0 },
		rotation = { x = 0, y = 0, z = 0 },
		scale = { x = 1, y = 1, z = 1 },
		accessoryType = accessoryType,
	}
end

local MODEL_PRODUCING_METHODS = {
	TEXT_TO_3D = true,
	IMAGE_TO_3D = true,
	AVATAR_TO_3D = true,
}

-- See Config.Generation.ModelQueueSeconds for why this exists. Returns nil
-- for methods that don't produce a model (IMAGE_PREVIEW/IMAGE_UPLOAD reach
-- their terminal IMAGE_READY status through a different _Poll branch that
-- never consults this).
local function computeMinReadyAt(now: number, method: string, priority: boolean): number?
	if not MODEL_PRODUCING_METHODS[method] then
		return nil
	end
	local range = if priority then Config.Generation.PriorityModelQueueSeconds else Config.Generation.ModelQueueSeconds
	return now + math.random(range.Minimum, range.Maximum)
end

-- Cosmetic-only stage text shown once the pipeline has actually finished but
-- this generation hasn't cleared its queue time yet (see computeMinReadyAt).
-- Progress climbs from wherever the real backend progress last was up to 99
-- -- never backward, and never 100 until the item is actually handed over --
-- so the bar keeps moving forward instead of stalling or visibly rewinding.
local FINISHING_STAGE_TEXTS = {
	"Finishing touches",
	"Polishing the details",
	"Preparing your item",
	"Almost ready",
}

local function finishingStageFor(startedAt: number, readyAt: number, startProgress: number): (string, number)
	local total = math.max(1, readyAt - startedAt)
	local elapsed = math.clamp(os.time() - startedAt, 0, total)
	local span = math.max(1, 99 - startProgress)
	local progress = math.clamp(startProgress + math.floor((elapsed / total) * span), startProgress, 99)
	local stageIndex = 1 + (math.floor(elapsed / 18) % #FINISHING_STAGE_TEXTS)
	return FINISHING_STAGE_TEXTS[stageIndex], progress
end

function GenerationService.new(
	profileService: any,
	playerStateService: any,
	backendService: any,
	commerceService: any,
	push: (Player, string, any) -> (),
	analyticsService: any,
	achievementService: any,
	itemService: any
)
	local self = setmetatable({
		profiles = profileService,
		playerStates = playerStateService,
		backend = backendService,
		commerce = commerceService,
		analytics = analyticsService,
		achievements = achievementService,
		items = itemService,
		push = push,
		polling = {} :: { [string]: boolean },
		launching = {} :: { [string]: boolean },
	}, GenerationService)

	commerceService:Register("DirectGeneration", function(player, payload, intentId)
		return self:_Grant(player, "DirectGeneration", payload, intentId)
	end)
	for _, tier in IMAGE_QUALITY_TIERS do
		commerceService:Register(tier.ProductKey, function(player, payload, intentId)
			return self:_Grant(player, tier.ProductKey, payload, intentId)
		end)
	end
	commerceService:Register("ImageConversion", function(player, payload, intentId)
		return self:_Grant(player, "ImageConversion", payload, intentId)
	end)
	commerceService:Register("AvatarConversion", function(player, payload, intentId)
		return self:_Grant(player, "AvatarConversion", payload, intentId)
	end)
	commerceService:Register("PriorityPass", function(player, _payload, intentId)
		local granted = false
		local mutateSuccess = self.profiles:Mutate(player, function(profile)
			if not profile.grantedIntents[intentId] then
				profile.grantedIntents[intentId] = { kind = "PRIORITY_PASS", grantedAt = os.time() }
				profile.retryCredits.PriorityPass = (profile.retryCredits.PriorityPass or 0) + 1
				granted = true
			end
		end)
		if not mutateSuccess then
			error("PROFILE_MUTATION_FAILED")
		end
		if granted then
			return function()
				local profile = self.profiles:Get(player)
				if not profile or player.Parent == nil then
					return
				end
				self.push(player, Network.PushEvents.Profile, { retryCredits = profile.retryCredits })
				self.push(
					player,
					Network.PushEvents.Toast,
					{ tone = "success", message = "Priority pass added to your account." }
				)
			end
		end
		return nil
	end)
	return self
end

function GenerationService:Create(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" then
		return false, "INVALID_REQUEST"
	end
	local kind = payload.kind
	if kind ~= "TEXT_TO_3D" and kind ~= "IMAGE_PREVIEW" then
		return false, "INVALID_METHOD"
	end
	local accessoryType = payload.accessoryType
	if type(accessoryType) ~= "string" or not ACCESSORY_TYPES[accessoryType] then
		return false, "INVALID_ACCESSORY_TYPE"
	end
	local guidanceSuccess, stylePreset, detailLevel = readGuidance(payload)
	if not guidanceSuccess then
		return false, stylePreset
	end

	local imageQualityTier = nil :: string?
	if kind == "IMAGE_PREVIEW" then
		local requestedTier = if type(payload.imageQuality) == "string" then payload.imageQuality else "LOW"
		if not IMAGE_QUALITY_TIERS[requestedTier] then
			return false, "INVALID_IMAGE_QUALITY"
		end
		imageQualityTier = requestedTier
	end

	local filterSuccess, filteredPrompt, filterError = ModerationService.FilterPrompt(player, payload.prompt)
	if not filterSuccess then
		return false, filterError
	end
	local studioMock = RunService:IsStudio() and Config.Studio.AllowMockBackend and not self.backend:IsConfigured()
	if not studioMock then
		local moderationSuccess, moderationResult = self.backend:ModeratePrompt(player, filteredPrompt)
		if not moderationSuccess then
			return false, moderationResult
		end
	end
	if not self:_HasQueueSpace(player) then
		return false, "QUEUE_FULL"
	end

	local productKey = if kind == "TEXT_TO_3D"
		then "DirectGeneration"
		else IMAGE_QUALITY_TIERS[imageQualityTier :: string].ProductKey
	local intentPayload = {
		kind = kind,
		filteredPrompt = filteredPrompt,
		accessoryType = accessoryType,
		stylePreset = stylePreset,
		detailLevel = detailLevel,
		imageQuality = imageQualityTier,
		usePriority = payload.usePriority == true,
		-- Forge Tokens may fund generation, but only from profile.tokens (the
		-- real-money-backed pool: a rewarded ad or a direct Robux purchase),
		-- and only at a steep enough price that even the worst measured ad
		-- (~0.12 Robux) still leaves Forge ahead of the real provider cost —
		-- see CommerceService.tokenPriceFor and docs/PRICING.md "Forge
		-- Tokens". profile.bonusTokens (free grants) can never reach this
		-- path regardless of what the client sends here.
		paymentMethod = if payload.paymentMethod == "TOKENS" then "TOKENS" else "ROBUX",
	}
	return self:_UseCreditOrPrompt(player, productKey, intentPayload)
end

function GenerationService:CreateUploadedImage(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" then
		return false, "INVALID_REQUEST"
	end
	local passLookupSuccess, ownsPass = self.commerce:OwnsPass(player, "CustomImageUpload", true)
	if not passLookupSuccess then
		return false, ownsPass
	end
	if ownsPass ~= true then
		return false, "CUSTOM_IMAGE_PASS_REQUIRED"
	end
	if not self.playerStates:Get(player).contentSharingAllowed then
		return false, "CONTENT_SHARING_DISABLED"
	end

	local accessoryType = payload.accessoryType
	if type(accessoryType) ~= "string" or not ACCESSORY_TYPES[accessoryType] then
		return false, "INVALID_ACCESSORY_TYPE"
	end
	local guidanceSuccess, stylePreset, detailLevel = readGuidance(payload)
	if not guidanceSuccess then
		return false, stylePreset
	end
	local sourceImageAssetId = tonumber(payload.sourceImageAssetId)
	if
		not sourceImageAssetId
		or sourceImageAssetId <= 0
		or sourceImageAssetId % 1 ~= 0
		or sourceImageAssetId > 9_007_199_254_740_991
	then
		return false, "INVALID_IMAGE_ASSET_ID"
	end

	local filterSuccess, filteredPrompt, filterError = ModerationService.FilterPrompt(player, payload.prompt)
	if not filterSuccess then
		return false, filterError
	end
	local studioMock = RunService:IsStudio() and Config.Studio.AllowMockBackend and not self.backend:IsConfigured()
	if not studioMock then
		local metadataSuccess, metadata = pcall(function()
			return MarketplaceService:GetProductInfoAsync(sourceImageAssetId, Enum.InfoType.Asset)
		end)
		if not metadataSuccess or type(metadata) ~= "table" then
			return false, "IMAGE_ASSET_UNAVAILABLE"
		end
		if not IMAGE_ASSET_TYPES[tonumber(metadata.AssetTypeId)] then
			return false, "IMAGE_ASSET_TYPE_REQUIRED"
		end
		local creator = metadata.Creator
		local creatorId = if type(creator) == "table" then tonumber(creator.CreatorTargetId or creator.Id) else nil
		local creatorType = if type(creator) == "table" then tostring(creator.CreatorType or "") else ""
		creatorType = string.lower(string.gsub(creatorType, "^Enum%.CreatorType%.", ""))
		local ownedByPlayer = creatorType == "user" and creatorId == player.UserId
		local ownedByGroup = creatorType == "group" and Config.Group.Id > 0 and creatorId == Config.Group.Id
		if not ownedByPlayer and not ownedByGroup then
			return false, "IMAGE_NOT_OWNED"
		end
		local moderationSuccess, moderationResult = self.backend:ModeratePrompt(player, filteredPrompt)
		if not moderationSuccess then
			return false, moderationResult
		end
	end
	if not self:_HasQueueSpace(player) then
		return false, "QUEUE_FULL"
	end
	if not self.backend:IsConfigured() and not studioMock then
		return false, "BACKEND_NOT_CONFIGURED"
	end

	local intentId = self.profiles:GenerateId("upload")
	local postCommit = self:_Prepare(player, "CustomImageUpload", {
		kind = "IMAGE_UPLOAD",
		filteredPrompt = filteredPrompt,
		accessoryType = accessoryType,
		stylePreset = stylePreset,
		detailLevel = detailLevel,
		sourceImageAssetId = sourceImageAssetId,
		usePriority = payload.usePriority == true,
	}, intentId)
	if type(postCommit) ~= "function" then
		return false, "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		return false, "SAVE_FAILED"
	end
	task.spawn(postCommit)
	return true, {
		generationId = deterministicId("gen", intentId),
		uploadAccepted = true,
	}
end

-- Same wizard as Create()/CreateUploadedImage() (prompt, accessory type,
-- style preset, detail level, pricing/payment) except the source image is
-- the player's own current Roblox avatar render instead of an
-- upload/AI-generated reference -- no custom-image pass required, since
-- there's nothing to upload. Unlike an early version of this feature, the
-- Roblox server does NOT resolve a real fetchable avatar image URL itself:
-- HttpService is blocked from reaching Roblox-owned domains (confirmed live
-- -- "HttpService is not allowed to access that Roblox resource" against
-- thumbnails.roblox.com), so only `avatarView` is sent to the backend,
-- which resolves the actual thumbnail URL itself from the `playerUserId`
-- BackendService already stamps on every job (see BackendService:CreateJob).
function GenerationService:CreateFromAvatar(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" then
		return false, "INVALID_REQUEST"
	end
	local accessoryType = payload.accessoryType
	if type(accessoryType) ~= "string" or not ACCESSORY_TYPES[accessoryType] then
		return false, "INVALID_ACCESSORY_TYPE"
	end
	local guidanceSuccess, stylePreset, detailLevel = readGuidance(payload)
	if not guidanceSuccess then
		return false, stylePreset
	end
	local avatarView = payload.avatarView
	if type(avatarView) ~= "string" or not AVATAR_VIEWS[avatarView] then
		return false, "INVALID_AVATAR_VIEW"
	end
	if not self.playerStates:Get(player).contentSharingAllowed then
		return false, "CONTENT_SHARING_DISABLED"
	end

	local rawPrompt = if type(payload.prompt) == "string" then payload.prompt else ""
	local hasPrompt = #string.gsub(rawPrompt, "%s", "") > 0
	local filterSuccess, filteredPrompt, filterError =
		ModerationService.FilterPrompt(player, if hasPrompt then rawPrompt else AVATAR_DEFAULT_PROMPT)
	if not filterSuccess then
		return false, filterError
	end
	local studioMock = RunService:IsStudio() and Config.Studio.AllowMockBackend and not self.backend:IsConfigured()
	if not studioMock then
		local moderationSuccess, moderationResult = self.backend:ModeratePrompt(player, filteredPrompt)
		if not moderationSuccess then
			return false, moderationResult
		end
	end
	if not self:_HasQueueSpace(player) then
		return false, "QUEUE_FULL"
	end
	if not self.backend:IsConfigured() and not studioMock then
		return false, "BACKEND_NOT_CONFIGURED"
	end

	return self:_UseCreditOrPrompt(player, "AvatarConversion", {
		kind = "AVATAR_TO_3D",
		filteredPrompt = filteredPrompt,
		accessoryType = accessoryType,
		stylePreset = stylePreset,
		detailLevel = detailLevel,
		avatarView = avatarView,
		usePriority = payload.usePriority == true,
		-- See the matching comment in Create() above.
		paymentMethod = if payload.paymentMethod == "TOKENS" then "TOKENS" else "ROBUX",
	})
end

-- Unlike CreateFromAvatar above, this never produces an accessory or a 3D
-- model at all -- it's a standalone stylized image of the player's own
-- avatar, priced and paid for through the same purchasable image-quality
-- tiers as the IMAGE_PREVIEW reference-image step (Config.Generation.
-- ImageQualityTiers), since both are a single OpenAI image call with no
-- Meshy pipeline cost behind them.
function GenerationService:CreateAvatarGraphic(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" then
		return false, "INVALID_REQUEST"
	end
	local guidanceSuccess, stylePreset, _detailLevel = readGuidance(payload)
	if not guidanceSuccess then
		return false, stylePreset
	end
	local avatarView = payload.avatarView
	if type(avatarView) ~= "string" or not AVATAR_VIEWS[avatarView] then
		return false, "INVALID_AVATAR_VIEW"
	end
	local requestedTier = if type(payload.imageQuality) == "string" then payload.imageQuality else "LOW"
	if not IMAGE_QUALITY_TIERS[requestedTier] then
		return false, "INVALID_IMAGE_QUALITY"
	end
	if not self.playerStates:Get(player).contentSharingAllowed then
		return false, "CONTENT_SHARING_DISABLED"
	end

	local rawPrompt = if type(payload.prompt) == "string" then payload.prompt else ""
	local hasPrompt = #string.gsub(rawPrompt, "%s", "") > 0
	local filterSuccess, filteredPrompt, filterError =
		ModerationService.FilterPrompt(player, if hasPrompt then rawPrompt else AVATAR_GRAPHIC_DEFAULT_PROMPT)
	if not filterSuccess then
		return false, filterError
	end
	local studioMock = RunService:IsStudio() and Config.Studio.AllowMockBackend and not self.backend:IsConfigured()
	if not studioMock then
		local moderationSuccess, moderationResult = self.backend:ModeratePrompt(player, filteredPrompt)
		if not moderationSuccess then
			return false, moderationResult
		end
	end
	if not self:_HasQueueSpace(player) then
		return false, "QUEUE_FULL"
	end
	if not self.backend:IsConfigured() and not studioMock then
		return false, "BACKEND_NOT_CONFIGURED"
	end

	local productKey = IMAGE_QUALITY_TIERS[requestedTier].ProductKey
	return self:_UseCreditOrPrompt(player, productKey, {
		kind = "AVATAR_GRAPHIC",
		filteredPrompt = filteredPrompt,
		stylePreset = stylePreset,
		detailLevel = "BALANCED",
		avatarView = avatarView,
		imageQuality = requestedTier,
		usePriority = false,
		-- See the matching comment in Create() above.
		paymentMethod = if payload.paymentMethod == "TOKENS" then "TOKENS" else "ROBUX",
	})
end

function GenerationService:ConvertImage(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" or type(payload.generationId) ~= "string" then
		return false, "INVALID_REQUEST"
	end
	if not self:_HasQueueSpace(player) then
		return false, "QUEUE_FULL"
	end
	if not self.backend:IsConfigured() and not (RunService:IsStudio() and Config.Studio.AllowMockBackend) then
		return false, "BACKEND_NOT_CONFIGURED"
	end
	local profile = self.profiles:Get(player)
	local source = profile and profile.generations[payload.generationId]
	if not source or source.stage ~= "IMAGE_READY" or not source.backendJobId then
		return false, "IMAGE_NOT_READY"
	end
	local sourceImageAssetId = tonumber(source.previewAssetId)
	if
		not (RunService:IsStudio() and Config.Studio.AllowMockBackend)
		and (not sourceImageAssetId or sourceImageAssetId <= 0 or sourceImageAssetId % 1 ~= 0)
	then
		return false, "IMAGE_NOT_READY"
	end
	return self:_UseCreditOrPrompt(player, "ImageConversion", {
		kind = "IMAGE_TO_3D",
		filteredPrompt = source.filteredPrompt,
		accessoryType = source.accessoryType,
		stylePreset = source.stylePreset or "AUTO",
		detailLevel = source.detailLevel or "BALANCED",
		sourceGenerationId = source.id,
		sourceBackendJobId = source.backendJobId,
		sourceImageAssetId = if sourceImageAssetId and sourceImageAssetId > 0 then sourceImageAssetId else nil,
		usePriority = payload.usePriority == true,
		-- See the matching comment in Create() above.
		paymentMethod = if payload.paymentMethod == "TOKENS" then "TOKENS" else "ROBUX",
	})
end

function GenerationService:_UseCreditOrPrompt(
	player: Player,
	productKey: string,
	payload: { [string]: any }
): (boolean, any)
	local usedCredit = false
	self.profiles:Mutate(player, function(profile)
		local credits = profile.retryCredits[productKey] or 0
		if credits > 0 then
			profile.retryCredits[productKey] = credits - 1
			usedCredit = true
		end
	end)
	if usedCredit then
		local intentId = self.profiles:GenerateId("credit")
		local grantSuccess, postCommit = pcall(function()
			return self:_Grant(player, productKey, payload, intentId)
		end)
		if not grantSuccess or type(postCommit) ~= "function" then
			self.profiles:Mutate(player, function(profile)
				profile.retryCredits[productKey] = (profile.retryCredits[productKey] or 0) + 1
			end)
			return false, "GRANT_FAILED"
		end
		if not self.profiles:Save(player) then
			return false, "SAVE_FAILED"
		end
		task.spawn(postCommit)
		return true, { usedRetryCredit = true, intentId = intentId }
	end
	if payload.paymentMethod == "TOKENS" then
		return self.commerce:BeginIntentWithTokens(player, productKey, payload)
	end
	return self.commerce:BeginIntent(player, productKey, payload)
end

function GenerationService:_Grant(
	player: Player,
	productKey: string,
	payload: { [string]: any },
	intentId: string
): (() -> ())?
	local profile = self.profiles:Get(player)
	if not profile then
		return nil
	end
	local existingGrant = profile.grantedIntents[intentId]
	if type(existingGrant) == "table" then
		if type(existingGrant.generationId) == "string" then
			return function()
				self:_Launch(player, existingGrant.generationId)
			end
		end
		return nil
	end

	if payload.recoveryCredit then
		local granted = false
		local mutateSuccess = self.profiles:Mutate(player, function(mutableProfile)
			if not mutableProfile.grantedIntents[intentId] then
				mutableProfile.grantedIntents[intentId] = {
					kind = "RECOVERY_CREDIT",
					productKey = productKey,
					grantedAt = os.time(),
				}
				mutableProfile.retryCredits[productKey] = (mutableProfile.retryCredits[productKey] or 0) + 1
				granted = true
			end
		end)
		if not mutateSuccess then
			error("PROFILE_MUTATION_FAILED")
		end
		if granted then
			return function()
				local currentProfile = self.profiles:Get(player)
				if not currentProfile or player.Parent == nil then
					return
				end
				self.push(player, Network.PushEvents.Profile, { retryCredits = currentProfile.retryCredits })
				self.push(player, Network.PushEvents.Toast, {
					tone = "success",
					message = "Your purchase was recovered as a generation credit.",
				})
			end
		end
		return nil
	end
	return self:_Prepare(player, productKey, payload, intentId)
end

function GenerationService:_Prepare(
	player: Player,
	productKey: string,
	payload: { [string]: any },
	intentId: string
): (() -> ())?
	local profile = self.profiles:Get(player)
	if not profile then
		return nil
	end
	local generationId = deterministicId("gen", intentId)
	if profile.generations[generationId] then
		return function()
			self:_Launch(player, generationId)
		end
	end
	if not self:_HasQueueSpace(player) then
		local mutateSuccess = self.profiles:Mutate(player, function(mutableProfile)
			if not mutableProfile.grantedIntents[intentId] then
				mutableProfile.grantedIntents[intentId] = {
					kind = "QUEUE_RECOVERY_CREDIT",
					productKey = productKey,
					grantedAt = os.time(),
				}
				mutableProfile.retryCredits[productKey] = (mutableProfile.retryCredits[productKey] or 0) + 1
			end
		end)
		if not mutateSuccess then
			error("PROFILE_MUTATION_FAILED")
		end
		return function()
			local currentProfile = self.profiles:Get(player)
			if not currentProfile or player.Parent == nil then
				return
			end
			self.push(player, Network.PushEvents.Profile, { retryCredits = currentProfile.retryCredits })
			self.push(player, Network.PushEvents.Toast, {
				tone = "success",
				message = "Your queue filled up, so the purchase became a retry credit.",
			})
		end
	end

	local now = os.time()
	-- Time-to-first-wow: a brand new player's first model rides the same
	-- fast queue lane as a group member or Priority Pass, until they've
	-- actually received one completed model -- not just made their first
	-- attempt, since a common first session is a reference-image step
	-- before ever converting one. Roblox's own new-player retention
	-- weighting (and, by extension, discovery/recommendation) is most
	-- sensitive to exactly this window, so it's worth the same fast lane a
	-- paying/group player gets, free, without touching pricing at all.
	local isFirstModel = MODEL_PRODUCING_METHODS[payload.kind] == true
		and (profile.stats.generationsCompleted or 0) == 0
	local priority = self.playerStates:Get(player).groupMember or isFirstModel
	if payload.usePriority == true and not priority then
		self.profiles:Mutate(player, function(profile)
			local passes = profile.retryCredits.PriorityPass or 0
			if passes > 0 then
				profile.retryCredits.PriorityPass = passes - 1
				priority = true
			end
		end)
	end

	local mutateSuccess = self.profiles:Mutate(player, function(profile)
		if profile.generations[generationId] then
			return
		end
		profile.generations[generationId] = {
			id = generationId,
			method = payload.kind,
			productKey = productKey,
			priority = priority,
			stage = "QUEUED",
			stageText = "Joining the generation queue",
			progress = 0,
			filteredPrompt = payload.filteredPrompt,
			accessoryType = payload.accessoryType,
			stylePreset = payload.stylePreset or "AUTO",
			detailLevel = payload.detailLevel or "BALANCED",
			imageQuality = payload.imageQuality,
			sourceImageAssetId = payload.sourceImageAssetId,
			avatarView = payload.avatarView,
			createdAt = now,
			updatedAt = now,
			purchaseIntentId = intentId,
			sourceBackendJobId = payload.sourceBackendJobId,
			minReadyAt = computeMinReadyAt(now, payload.kind, priority),
			isFirstModelBoost = isFirstModel,
		}
		table.insert(profile.generationOrder, 1, generationId)
		profile.stats.generationsStarted += 1
		if payload.kind == "IMAGE_UPLOAD" then
			profile.stats.customImagesSubmitted = (profile.stats.customImagesSubmitted or 0) + 1
		end
		profile.grantedIntents[intentId] = {
			kind = "GENERATION",
			generationId = generationId,
			productKey = productKey,
			grantedAt = now,
		}
	end)
	if not mutateSuccess then
		error("PROFILE_MUTATION_FAILED")
	end
	return function()
		self:_Launch(player, generationId)
	end
end

function GenerationService:_Launch(player: Player, generationId: string)
	if player.Parent == nil or self.launching[generationId] then
		return
	end
	local profile = self.profiles:Get(player)
	local generation = profile and profile.generations[generationId]
	if not generation or TERMINAL[generation.stage] then
		return
	end
	local productKey = generation.productKey or productKeyFor(generation.method)
	if generation.backendJobId then
		self:_Poll(player, generationId, generation.backendJobId, productKey)
		return
	end
	self.launching[generationId] = true
	self.push(player, Network.PushEvents.Profile, { retryCredits = profile.retryCredits })
	self.push(player, Network.PushEvents.Generation, { generationId = generationId, stage = "QUEUED", progress = 0 })
	if generation.isFirstModelBoost then
		self.push(player, Network.PushEvents.Toast, {
			tone = "success",
			message = "🚀 Your first model is fast-tracked -- it'll be ready sooner than usual!",
		})
	end
	local funnel = if generation.method == "IMAGE_PREVIEW" or generation.method == "IMAGE_UPLOAD"
		then "reference"
		else "generation"
	self.analytics:Funnel(player, funnel, 3, "Job queued", { method = generation.method })

	if not self.backend:IsConfigured() and RunService:IsStudio() and Config.Studio.AllowMockBackend then
		self.launching[generationId] = nil
		self:_RunStudioMock(player, generationId, generation.method)
		return
	end

	local requestPayload = {
		requestId = generationId,
		kind = generation.method,
		filteredPrompt = generation.filteredPrompt,
		accessoryType = generation.accessoryType,
		stylePreset = generation.stylePreset or "AUTO",
		detailLevel = generation.detailLevel or "BALANCED",
		priority = generation.priority == true,
	}
	if generation.sourceBackendJobId then
		requestPayload.sourceJobId = generation.sourceBackendJobId
	end
	if generation.sourceImageAssetId then
		requestPayload.sourceImageAssetId = generation.sourceImageAssetId
	end
	if generation.avatarView then
		-- The backend, not the Roblox server, resolves this into a real
		-- fetchable thumbnail URL -- see BackendService:CreateJob and the
		-- comment above CreateFromAvatar for why.
		requestPayload.avatarView = generation.avatarView
	end
	if
		(generation.method == "IMAGE_PREVIEW" or generation.method == "AVATAR_GRAPHIC")
		and type(generation.imageQuality) == "string"
	then
		local tier = IMAGE_QUALITY_TIERS[generation.imageQuality]
		requestPayload.imageQuality = if tier then tier.OpenAIQuality else "low"
	end
	local success, response = self.backend:CreateJob(player, requestPayload)
	if not success then
		self.launching[generationId] = nil
		self:_Fail(player, generationId, tostring(response), true, productKey)
		return
	end
	local job = response.job
	if type(job) ~= "table" or type(job.id) ~= "string" then
		self.launching[generationId] = nil
		self:_Fail(player, generationId, "BACKEND_BAD_RESPONSE", true, productKey)
		return
	end
	self.profiles:Mutate(player, function(profile)
		local mutableGeneration = profile.generations[generationId]
		if mutableGeneration then
			mutableGeneration.backendJobId = job.id
			mutableGeneration.updatedAt = os.time()
		end
	end)
	self.launching[generationId] = nil
	self:_Poll(player, generationId, job.id, productKey)
end

function GenerationService:_Poll(player: Player, generationId: string, backendJobId: string, productKey: string)
	if self.polling[generationId] then
		return
	end
	self.polling[generationId] = true
	task.spawn(function()
		-- Mutates + pushes one generation-progress update. Kept as a single
		-- path so every caller below (real backend stages, the immediate
		-- "SUCCEEDED and ready" case, and the paced FINISHING case) produces
		-- exactly one push per poll cycle -- never two competing ones in the
		-- same tick, which would otherwise flash the bar to 100% and back
		-- down every ~4 seconds while a generation waits out its queue time.
		local function pushGenerationUpdate(stage: string, stageText: string, progress: number)
			self.profiles:Mutate(player, function(profile)
				local generation = profile.generations[generationId]
				if generation then
					generation.stage = stage
					generation.stageText = stageText
					generation.progress = progress
					generation.updatedAt = os.time()
				end
			end)
			self.push(player, Network.PushEvents.Generation, {
				generationId = generationId,
				stage = stage,
				stageText = stageText,
				progress = progress,
			})
		end

		while self.polling[generationId] and player.Parent do
			local success, response = self.backend:GetJob(player, backendJobId)
			if success and type(response.job) == "table" then
				local job = response.job
				-- SUCCEEDED is deliberately not pushed here: the branch below
				-- owns that push, either as a real completion or as a paced
				-- FINISHING update, so there's exactly one push for it.
				if job.status ~= "SUCCEEDED" then
					pushGenerationUpdate(job.status, job.stage, job.progress)
				end

				if job.status == "IMAGE_READY" then
					self.polling[generationId] = nil
					local output = if type(job.output) == "table" then job.output else {}
					if
						not RunService:IsStudio()
						and (type(output.previewAssetId) ~= "number" or output.previewAssetId <= 0)
					then
						self:_Fail(player, generationId, "BACKEND_PREVIEW_MISSING", true, productKey)
						return
					end
					self.profiles:Mutate(player, function(profile)
						local generation = profile.generations[generationId]
						if generation then
							generation.previewAssetId = output.previewAssetId
						end
					end)
					self.profiles:Save(player)
					self.push(player, Network.PushEvents.Generation, {
						generationId = generationId,
						previewAssetId = output.previewAssetId,
					})
					self.push(player, Network.PushEvents.Toast, {
						tone = "ready",
						message = "Your reference image is ready to review.",
					})
					self.analytics:Funnel(player, "reference", 4, "Reference image ready", {})
					return
				elseif job.status == "SUCCEEDED" then
					local output = if type(job.output) == "table" then job.output else {}
					local currentProfile = self.profiles:Get(player)
					local currentGeneration = currentProfile and currentProfile.generations[generationId]
					if currentGeneration and currentGeneration.method == "AVATAR_GRAPHIC" then
						-- Never produces a model, so it skips the modelAssetId
						-- check and the model queue-time gate entirely (see
						-- computeMinReadyAt: AVATAR_GRAPHIC isn't in
						-- MODEL_PRODUCING_METHODS) and hands the graphic over
						-- the moment the backend reports it ready.
						if
							not RunService:IsStudio()
							and (type(output.previewAssetId) ~= "number" or output.previewAssetId <= 0)
						then
							self.polling[generationId] = nil
							self:_Fail(player, generationId, "BACKEND_GRAPHIC_MISSING", true, productKey)
							return
						end
						self.polling[generationId] = nil
						pushGenerationUpdate(job.status, job.stage, job.progress)
						self:_CompleteGraphic(player, generationId, output)
						return
					end
					if
						not RunService:IsStudio()
						and (type(output.modelAssetId) ~= "number" or output.modelAssetId <= 0)
					then
						self.polling[generationId] = nil
						self:_Fail(player, generationId, "BACKEND_MODEL_MISSING", true, productKey)
						return
					end
					local minReadyAt = currentGeneration and currentGeneration.minReadyAt
					if type(minReadyAt) ~= "number" or os.time() >= minReadyAt then
						self.polling[generationId] = nil
						pushGenerationUpdate(job.status, job.stage, job.progress)
						self:_CompleteModel(player, generationId, output)
						return
					end
					-- The pipeline is done, but this generation hasn't cleared
					-- its queue time yet (see Config.Generation.ModelQueueSeconds).
					-- Keep this same poll loop alive -- backend:GetJob on an
					-- already-finished job is cheap and idempotent -- and pace a
					-- plausible finishing stage instead of handing the item over
					-- early.
					local finishingStartedAt = currentGeneration.finishingStartedAt
					local finishingStartProgress = currentGeneration.finishingStartProgress
					if type(finishingStartedAt) ~= "number" or type(finishingStartProgress) ~= "number" then
						finishingStartedAt = os.time()
						-- Seeded from the last real backend progress value
						-- (still sitting in the profile since the SUCCEEDED
						-- branch above deliberately skips the generic push),
						-- capped with a little headroom so there's always
						-- room to visibly keep climbing.
						finishingStartProgress = math.clamp(math.floor(currentGeneration.progress or 90), 0, 97)
					end
					local stageText, progress =
						finishingStageFor(finishingStartedAt, minReadyAt, finishingStartProgress)
					self.profiles:Mutate(player, function(profile)
						local generation = profile.generations[generationId]
						if generation then
							generation.stage = "FINISHING"
							generation.stageText = stageText
							generation.progress = progress
							generation.finishingStartedAt = finishingStartedAt
							generation.finishingStartProgress = finishingStartProgress
							generation.updatedAt = os.time()
						end
					end)
					self.push(player, Network.PushEvents.Generation, {
						generationId = generationId,
						stage = "FINISHING",
						stageText = stageText,
						progress = progress,
					})
				elseif job.status == "FAILED" then
					self.polling[generationId] = nil
					local errorCode = if job.error then job.error.code else "GENERATION_FAILED"
					local retryable = if job.error then job.error.retryable == true else false
					self:_Fail(player, generationId, errorCode, retryable, productKey)
					return
				end
			end
			task.wait(Config.Generation.StatusPollSeconds * self.playerStates:Get(player).queueSpeedMultiplier)
		end
		self.polling[generationId] = nil
	end)
end

-- Meshy's exported mesh origin is inconsistent between generations (see
-- AccessoryFit.ComputeDefaultPosition), so the all-zero defaultFit() alone
-- reads as a randomly offset item the first time it's previewed. Loading the
-- model once here, right when it's known to exist, lets the item start out
-- correctly seated instead of requiring every player to manually re-center
-- every generation. This never blocks item creation: any failure (asset not
-- yet propagated, no MeshPart found, placeholder id 0 in Studio) just falls
-- back to the previous all-zero position, same as before this existed.
function GenerationService:_ComputeInitialFit(accessoryType: string, modelAssetId: any): { [string]: any }
	local fit = defaultFit(accessoryType)
	if type(modelAssetId) ~= "number" or modelAssetId <= 0 then
		return fit
	end
	local ok, result = pcall(function()
		local loaded, modelOrProblem = self.items:LoadModelForInspection(modelAssetId)
		if not loaded then
			return nil
		end
		local model = modelOrProblem :: Model
		local mesh = model:FindFirstChildWhichIsA("MeshPart", true)
		local position = if mesh then AccessoryFit.ComputeDefaultPosition(mesh, accessoryType) else nil
		model:Destroy()
		return position
	end)
	if ok and result then
		fit.position = result
	end
	return fit
end

function GenerationService:_CompleteModel(player: Player, generationId: string, output: { [string]: any })
	local profile = self.profiles:Get(player)
	local existingGeneration = profile and profile.generations[generationId]
	if not existingGeneration then
		return
	end
	local itemId = existingGeneration.itemId or deterministicId("item", generationId)
	-- Only compute this when it will actually be used: _CompleteModel is
	-- re-entrant-safe (see the profile.items[itemId] check below), and a
	-- repeat call for an already-created item has no use for another mesh
	-- load.
	local initialFit = if not (profile and profile.items[itemId])
		then self:_ComputeInitialFit(existingGeneration.accessoryType, output.modelAssetId)
		else nil
	local created = false
	self.profiles:Mutate(player, function(profile)
		local generation = profile.generations[generationId]
		if not generation then
			return
		end
		if profile.items[itemId] then
			generation.stage = "SUCCEEDED"
			generation.stageText = "Ready to fit"
			generation.progress = 100
			generation.itemId = itemId
			generation.updatedAt = os.time()
			return
		end
		local now = os.time()
		profile.items[itemId] = {
			id = itemId,
			ownerUserId = player.UserId,
			originalOwnerUserId = player.UserId,
			license = "ORIGINAL",
			canList = true,
			canPublish = true,
			name = string.sub(generation.filteredPrompt, 1, 48),
			filteredPrompt = generation.filteredPrompt,
			method = if generation.method == "TEXT_TO_3D"
				then "TEXT_TO_3D"
				elseif generation.method == "AVATAR_TO_3D" then "AVATAR_TO_3D"
				else "IMAGE_TO_3D",
			stylePreset = generation.stylePreset or "AUTO",
			detailLevel = generation.detailLevel or "BALANCED",
			status = "READY",
			createdAt = now,
			updatedAt = now,
			backendJobId = generation.backendJobId,
			modelAssetId = output.modelAssetId,
			thumbnailAssetId = output.thumbnailAssetId,
			fit = initialFit,
			visibility = "PRIVATE",
			isListed = false,
			likes = 0,
			favorites = 0,
			views = 0,
		}
		created = true
		table.insert(profile.itemOrder, 1, itemId)
		generation.stage = "SUCCEEDED"
		generation.stageText = "Ready to fit"
		generation.progress = 100
		generation.itemId = itemId
		generation.updatedAt = now
		profile.stats.generationsCompleted += 1
	end)
	self.profiles:Save(player)
	self.push(player, Network.PushEvents.Item, { itemId = itemId, item = self.profiles:Get(player).items[itemId] })
	if created then
		self.push(player, Network.PushEvents.Toast, { tone = "ready", message = "Your model is ready to fit." })
		self.analytics:Funnel(player, "generation", 4, "Model ready to fit", {
			method = self.profiles:Get(player).generations[generationId].method,
		})
		self.analytics:Custom(player, "GenerationCompleted", 1, {
			durationSeconds = math.max(0, os.time() - existingGeneration.createdAt),
			productKey = existingGeneration.productKey,
			method = existingGeneration.method,
		})
		self.achievements:Unlock(player, "FIRST_CREATION")
		local completedCount = self.profiles:Get(player).stats.generationsCompleted
		self.achievements:CheckCount(player, "FIVE_CREATIONS", completedCount, 5)
	end
end

-- Same re-entrant-safe shape as _CompleteModel above, but stores into
-- PlayerProfile.graphics instead of .items: an avatar graphic has no fit,
-- license, or publishing concept, so an ItemRecord would carry a pile of
-- meaningless fields for it.
function GenerationService:_CompleteGraphic(player: Player, generationId: string, output: { [string]: any })
	local profile = self.profiles:Get(player)
	local existingGeneration = profile and profile.generations[generationId]
	if not existingGeneration then
		return
	end
	local graphicId = existingGeneration.graphicId or deterministicId("graphic", generationId)
	local created = false
	self.profiles:Mutate(player, function(profile)
		local generation = profile.generations[generationId]
		if not generation then
			return
		end
		if profile.graphics[graphicId] then
			generation.stage = "SUCCEEDED"
			generation.stageText = "Your avatar graphic is ready"
			generation.progress = 100
			generation.graphicId = graphicId
			generation.updatedAt = os.time()
			return
		end
		local now = os.time()
		profile.graphics[graphicId] = {
			id = graphicId,
			ownerUserId = player.UserId,
			filteredPrompt = generation.filteredPrompt,
			stylePreset = generation.stylePreset or "AUTO",
			avatarView = generation.avatarView or "BUST",
			previewAssetId = output.previewAssetId,
			backendJobId = generation.backendJobId or "",
			createdAt = now,
			updatedAt = now,
		}
		created = true
		table.insert(profile.graphicOrder, 1, graphicId)
		generation.stage = "SUCCEEDED"
		generation.stageText = "Your avatar graphic is ready"
		generation.progress = 100
		generation.graphicId = graphicId
		generation.updatedAt = now
		profile.stats.generationsCompleted += 1
	end)
	self.profiles:Save(player)
	self.push(
		player,
		Network.PushEvents.Graphic,
		{ graphicId = graphicId, graphic = self.profiles:Get(player).graphics[graphicId] }
	)
	if created then
		self.push(player, Network.PushEvents.Toast, { tone = "ready", message = "Your avatar graphic is ready." })
		self.analytics:Funnel(player, "generation", 4, "Avatar graphic ready", {
			method = self.profiles:Get(player).generations[generationId].method,
		})
		self.analytics:Custom(player, "GenerationCompleted", 1, {
			durationSeconds = math.max(0, os.time() - existingGeneration.createdAt),
			productKey = existingGeneration.productKey,
			method = existingGeneration.method,
		})
		self.achievements:Unlock(player, "FIRST_CREATION")
		local completedCount = self.profiles:Get(player).stats.generationsCompleted
		self.achievements:CheckCount(player, "FIVE_CREATIONS", completedCount, 5)
	end
end

function GenerationService:_Fail(
	player: Player,
	generationId: string,
	errorCode: string,
	retryable: boolean,
	productKey: string
)
	local firstFailure = false
	self.profiles:Mutate(player, function(profile)
		local generation = profile.generations[generationId]
		if generation and not generation.failureHandled then
			generation.failureHandled = true
			generation.stage = "FAILED"
			generation.stageText = generationFailureText(errorCode)
			generation.errorCode = errorCode
			generation.updatedAt = os.time()
			firstFailure = true
		end
	end)
	if not firstFailure then
		return
	end
	if productKey == "CustomImageUpload" then
		self.push(player, Network.PushEvents.Toast, {
			tone = "error",
			message = "That image could not pass reference validation. You can try another image at no charge.",
		})
	else
		self:_RefundCredit(player, productKey, generationFailureText(errorCode) .. ". A retry credit was added.")
	end
	self.profiles:Save(player)
	self.analytics:Custom(player, "GenerationFailed", 1, {
		code = errorCode,
		retryable = retryable,
		creditGranted = productKey ~= "CustomImageUpload",
		productKey = productKey,
	})
end

function GenerationService:_RefundCredit(player: Player, productKey: string, message: string)
	self.profiles:Mutate(player, function(profile)
		profile.retryCredits[productKey] = (profile.retryCredits[productKey] or 0) + 1
	end)
	local profile = self.profiles:Get(player)
	if profile and player.Parent then
		self.push(player, Network.PushEvents.Profile, { retryCredits = profile.retryCredits })
		self.push(player, Network.PushEvents.Toast, { tone = "success", message = message })
	end
end

function GenerationService:_RunStudioMock(player: Player, generationId: string, kind: string)
	task.spawn(function()
		task.wait(1.25)
		local profile = self.profiles:Get(player)
		if not profile or not profile.generations[generationId] or player.Parent == nil then
			return
		end
		if kind == "IMAGE_PREVIEW" or kind == "IMAGE_UPLOAD" then
			self.profiles:Mutate(player, function(profile)
				local generation = profile.generations[generationId]
				generation.stage = "IMAGE_READY"
				generation.stageText = "Studio mock reference ready"
				generation.progress = 100
				generation.previewAssetId = generation.sourceImageAssetId or 0
				generation.backendJobId = `00000000-0000-0000-0000-{string.sub(generationId, -12)}`
			end)
			self.push(
				player,
				Network.PushEvents.Generation,
				{ generationId = generationId, stage = "IMAGE_READY", progress = 100 }
			)
		elseif kind == "AVATAR_GRAPHIC" then
			self:_CompleteGraphic(player, generationId, { previewAssetId = 0 })
		else
			self:_CompleteModel(player, generationId, { modelAssetId = 0, thumbnailAssetId = 0 })
		end
	end)
end

function GenerationService:_HasQueueSpace(player: Player): boolean
	local profile = self.profiles:Get(player)
	if not profile then
		return false
	end
	local active = 0
	for _, generation in profile.generations do
		if not TERMINAL[generation.stage] then
			active += 1
		end
	end
	return active < self.playerStates:Get(player).queueSlots
end

function GenerationService:Get(player: Player, generationId: string): (boolean, any)
	local profile = self.profiles:Get(player)
	local generation = profile and profile.generations[generationId]
	if not generation then
		return false, "NOT_FOUND"
	end
	return true, generation
end

function GenerationService:Resume(player: Player)
	local profile = self.profiles:Get(player)
	if not profile then
		return
	end
	for generationId, generation in profile.generations do
		if not TERMINAL[generation.stage] then
			if generation.backendJobId then
				self:_Poll(
					player,
					generationId,
					generation.backendJobId,
					generation.productKey or productKeyFor(generation.method)
				)
			else
				task.spawn(function()
					self:_Launch(player, generationId)
				end)
			end
		end
	end
end

function GenerationService:DeleteGraphic(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" or type(payload.graphicId) ~= "string" then
		return false, "INVALID_REQUEST"
	end
	local graphicId = payload.graphicId
	local removed = false
	self.profiles:Mutate(player, function(profile)
		if not profile.graphics[graphicId] then
			return
		end
		profile.graphics[graphicId] = nil
		for index, id in profile.graphicOrder do
			if id == graphicId then
				table.remove(profile.graphicOrder, index)
				break
			end
		end
		removed = true
	end)
	if not removed then
		return false, "NOT_FOUND"
	end
	self.profiles:Save(player)
	return true, {}
end

return GenerationService
