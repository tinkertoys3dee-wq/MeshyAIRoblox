--!strict
--fs
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

-- Publish the transport before loading feature services. If a service ever
-- fails during development, clients receive a bounded network error instead
-- of waiting forever for a folder that was never created.
local remoteFolder = ReplicatedStorage:FindFirstChild(Network.FolderName)
if not remoteFolder then
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = Network.FolderName
	remoteFolder.Parent = ReplicatedStorage
end

local requestRemote = remoteFolder:FindFirstChild(Network.RequestName) :: RemoteFunction?
if not requestRemote then
	requestRemote = Instance.new("RemoteFunction")
	requestRemote.Name = Network.RequestName
	requestRemote.Parent = remoteFolder
end
local typedRequestRemote = requestRemote :: RemoteFunction
typedRequestRemote.OnServerInvoke = function()
	return { ok = false, error = "SERVER_STARTING" }
end

local pushRemote = remoteFolder:FindFirstChild(Network.PushName) :: RemoteEvent?
if not pushRemote then
	pushRemote = Instance.new("RemoteEvent")
	pushRemote.Name = Network.PushName
	pushRemote.Parent = remoteFolder
end

local RateLimiter = require(script.Parent.Util.RateLimiter)
local ProfileService = require(script.Parent.Services.ProfileService)
local PlayerStateService = require(script.Parent.Services.PlayerStateService)
local BackendService = require(script.Parent.Services.BackendService)
local CommerceService = require(script.Parent.Services.CommerceService)
local GenerationService = require(script.Parent.Services.GenerationService)
local ItemService = require(script.Parent.Services.ItemService)
local CommunityService = require(script.Parent.Services.CommunityService)
local CatalogService = require(script.Parent.Services.CatalogService)
local AnalyticsService = require(script.Parent.Services.AnalyticsService)
local RetentionService = require(script.Parent.Services.RetentionService)
local AdRewardService = require(script.Parent.Services.AdRewardService)
local AchievementService = require(script.Parent.Services.AchievementService)
local LeaderboardService = require(script.Parent.Services.LeaderboardService)
local ArcadeService = require(script.Parent.Services.ArcadeService)
local LeaderstatsService = require(script.Parent.Services.LeaderstatsService)
local AfkRewardService = require(script.Parent.Services.AfkRewardService)
local ProgressionService = require(script.Parent.Services.ProgressionService)
local RunwayService = require(script.Parent.Services.RunwayService)

local function push(player: Player, eventName: string, payload: any)
	if player.Parent == Players then
		(pushRemote :: RemoteEvent):FireClient(player, eventName, payload)
	end
end

local profiles = ProfileService.new()
local playerStates = PlayerStateService.new()
local analytics = AnalyticsService.new()
local achievements = AchievementService.new(profiles, push, analytics)
local progression = ProgressionService.new(profiles, push, analytics)
local retention = RetentionService.new(profiles, analytics, achievements, push, progression)
local backend = BackendService.new()
local commerce = CommerceService.new(profiles, playerStates, analytics, push)
local adRewards = AdRewardService.new(profiles, playerStates, commerce, push, analytics, achievements)
local items = ItemService.new(profiles, playerStates, push)
local generations =
	GenerationService.new(profiles, playerStates, backend, commerce, push, analytics, achievements, items, progression)
local leaderboard = LeaderboardService.new()
local arcade = ArcadeService.new(profiles, playerStates, push, analytics)
local afkRewards = AfkRewardService.new(profiles, push, analytics)
local runway = RunwayService.new(profiles, push, analytics, retention, progression)
local community = CommunityService.new(profiles, playerStates, push, analytics, achievements, leaderboard)
local catalog = CatalogService.new(profiles, playerStates, analytics)
local leaderstats = LeaderstatsService.new()
-- Refreshes every online player's leaderstats after ANY profile.stats
-- change (generation completed, marketplace purchase, tip, ...) via
-- ProfileService's single Mutate choke point, instead of every stat-writing
-- call site remembering to trigger one itself.
profiles:OnMutate(function(player, profile)
	leaderstats:Refresh(player, profile)
end)
local remoteLimiter = RateLimiter.new(50, 10)
local reactionLimiter = RateLimiter.new(8, 10)
local loaded = {} :: { [Player]: boolean }
local loading = {} :: { [Player]: boolean }
local characterConnections = {} :: { [Player]: RBXScriptConnection }

local function initializePlayer(player: Player)
	if loaded[player] then
		return
	end
	while loading[player] and player.Parent == Players do
		task.wait()
	end
	if loaded[player] or player.Parent ~= Players then
		return
	end
	loading[player] = true
	-- playerStates:Initialize touches only Config/PolicyService/GroupService,
	-- never the profile, so it doesn't need to wait for the DataStore load
	-- below -- running it alongside instead of after overlaps two real
	-- network round trips on every single new join instead of stacking them.
	local playerStateDone = false
	task.spawn(function()
		playerStates:Initialize(player)
		playerStateDone = true
	end)
	local success = profiles:Load(player)
	while not playerStateDone do
		task.wait()
	end
	if not success or player.Parent ~= Players then
		loading[player] = nil
		return
	end
	local profile = profiles:Get(player)
	leaderstats:Init(player, profile)
	loaded[player] = true
	loading[player] = nil
	if not characterConnections[player] then
		characterConnections[player] = player.CharacterAdded:Connect(function()
			task.delay(0.75, function()
				if loaded[player] and player.Parent == Players then
					items:RestoreEquipped(player)
				end
			end)
		end)
	end
	if player.Character then
		task.defer(function()
			items:RestoreEquipped(player)
		end)
	end
	analytics:PlayerJoined(player, profile.stats.sessions > 1)
	analytics:Custom(player, "ForgeEligibilitySnapshot", 1, {
		groupMember = playerStates:Get(player).groupMember,
		plusSubscriber = playerStates:Get(player).plusSubscriber,
		contentSharingAllowed = playerStates:Get(player).contentSharingAllowed,
		commerceAllowed = playerStates:Get(player).commerceAllowed,
	})
	if playerStates:Get(player).groupMember then
		achievements:Unlock(player, "GROUP_JOINED")
	end
	retention:CheckIn(player)
	progression:AnnouncePending(player)
	generations:Resume(player)
end

local function bootstrap(player: Player): (boolean, any)
	if not loaded[player] then
		initializePlayer(player)
	end
	local profile = profiles:PublicSnapshot(player)
	if not profile then
		return false, "PROFILE_UNAVAILABLE"
	end
	-- A snapshot, not the live profile (see ProfileService:PublicSnapshot),
	-- so this never touches what's actually saved: only what this one
	-- Bootstrap response claims. Lets a Studio playtester re-see the
	-- first-timer flow (App.luau's Bootstrap handler opens straight to
	-- Create whenever stats.generationsCompleted is 0) every run, without a
	-- fresh account or hand-editing their real profile.
	if RunService:IsStudio() and Config.Studio.AlwaysShowFirstTimerFlow then
		profile.onboarding = { completed = false, step = 1 }
		profile.tutorialVersion = 0
		profile.stats.generationsCompleted = 0
		profile.settings.simpleMode = true
	end
	local state = playerStates:Get(player)
	return true,
		{
			profile = profile,
			policy = {
				contentSharingAllowed = state.contentSharingAllowed,
				commerceAllowed = state.commerceAllowed,
				subscriptionAllowed = state.subscriptionAllowed,
				paidTradingAllowed = state.paidTradingAllowed,
			},
			benefits = {
				groupMember = state.groupMember,
				queueSlots = state.queueSlots,
				speedMultiplier = state.queueSpeedMultiplier,
				plusSubscriber = state.plusSubscriber,
				customImageUpload = commerce:GetEntitlements(player).customImageUpload == true,
			},
			prices = commerce:GetPrices(),
			dailyBrief = retention:GetBrief(player),
			questState = retention:GetQuestState(player),
			journeyState = retention:GetJourneyState(player),
			creatorProgress = progression:GetSnapshot(player),
			runwayState = runway:GetState(player),
		}
end

local handlers: { [string]: (Player, any) -> (boolean, any) } = {
	[Network.Actions.Bootstrap] = function(player)
		return bootstrap(player)
	end,
	[Network.Actions.CreateGeneration] = function(player, payload)
		local funnel = if type(payload) == "table" and payload.kind == "IMAGE_PREVIEW"
			then "reference"
			else "generation"
		analytics:BeginFunnel(player, funnel, "Creation attempt started", {
			method = if type(payload) == "table" then payload.kind else "unknown",
		})
		analytics:Funnel(player, funnel, 2, "Method and prompt submitted", {
			method = if type(payload) == "table" then payload.kind else "unknown",
		})
		local success, result = generations:Create(player, payload)
		return success, result
	end,
	[Network.Actions.CreateUploadedImage] = function(player, payload)
		analytics:BeginFunnel(player, "reference", "Custom image submitted", {
			method = "IMAGE_UPLOAD",
		})
		analytics:Funnel(player, "reference", 2, "Custom image sent to moderation", {
			method = "IMAGE_UPLOAD",
		})
		local success, result = generations:CreateUploadedImage(player, payload)
		return success, result
	end,
	[Network.Actions.CreateFromAvatar] = function(player, payload)
		analytics:BeginFunnel(player, "generation", "Avatar-sourced creation started", {
			method = "AVATAR_TO_3D",
		})
		analytics:Funnel(player, "generation", 2, "Avatar view and prompt submitted", {
			method = "AVATAR_TO_3D",
		})
		local success, result = generations:CreateFromAvatar(player, payload)
		return success, result
	end,
	[Network.Actions.CreateAvatarGraphic] = function(player, payload)
		analytics:BeginFunnel(player, "generation", "Avatar graphic creation started", {
			method = "AVATAR_GRAPHIC",
		})
		analytics:Funnel(player, "generation", 2, "Avatar view and prompt submitted", {
			method = "AVATAR_GRAPHIC",
		})
		local success, result = generations:CreateAvatarGraphic(player, payload)
		return success, result
	end,
	[Network.Actions.CreateTextImage] = function(player, payload)
		analytics:BeginFunnel(player, "generation", "Text-to-image creation started", {
			method = "TEXT_TO_IMAGE",
		})
		analytics:Funnel(player, "generation", 2, "Prompt submitted", {
			method = "TEXT_TO_IMAGE",
		})
		local success, result = generations:CreateTextImage(player, payload)
		return success, result
	end,
	[Network.Actions.DeleteGraphic] = function(player, payload)
		return generations:DeleteGraphic(player, payload)
	end,
	[Network.Actions.ConvertImage] = function(player, payload)
		analytics:BeginFunnel(player, "generation", "Approved conversion started", { method = "IMAGE_TO_3D" })
		analytics:Funnel(player, "generation", 2, "Reference image approved", { method = "IMAGE_TO_3D" })
		local success, result = generations:ConvertImage(player, payload)
		return success, result
	end,
	[Network.Actions.PromptCustomImagePass] = function(player)
		analytics:Custom(player, "CustomImagePassPrompted", 1, {})
		return commerce:PromptPass(player, "CustomImageUpload")
	end,
	[Network.Actions.BuyPriorityPass] = function(player, payload)
		if type(payload) == "table" and payload.paymentMethod == "TOKENS" then
			return commerce:BeginIntentWithTokens(player, "PriorityPass", {})
		end
		return commerce:BeginIntent(player, "PriorityPass", {})
	end,
	[Network.Actions.RequestRewardedAd] = function(player)
		return adRewards:RequestAd(player)
	end,
	-- Roblox's SocialService.GameInvitePromptClosed only reports the local
	-- player sent invites to at least one recipient, never whether anyone
	-- accepted — there is no accepted-invite signal in the public API. The
	-- reward is therefore for taking the (real, Roblox-verified-by-its-own-
	-- native-UI) action of sending an invite, not for a friend joining.
	[Network.Actions.ReportInviteSent] = function(player, payload)
		local recipientCount = type(payload) == "table" and tonumber(payload.recipientCount) or nil
		if not recipientCount or recipientCount < 1 then
			return false, "INVALID_REQUEST"
		end
		achievements:Unlock(player, "FIRST_INVITE_SENT")
		analytics:Custom(player, "GameInviteSent", math.min(math.floor(recipientCount), 20), {})
		return true, {}
	end,
	[Network.Actions.ReportJourneyAction] = function(player, payload)
		local action = type(payload) == "table" and payload.action or nil
		if action ~= "OPEN_STUDIO" then
			return false, "INVALID_REQUEST"
		end
		local profile = profiles:Get(player)
		if not profile or profile.onboarding.completed ~= true then
			return false, "ONBOARDING_REQUIRED"
		end
		return retention:MarkJourney(player, action)
	end,
	-- Roblox requires a rewarded-ad reward product to also be normally
	-- purchasable with Robux (see AdRewardService), so this is both a real
	-- purchase path and the way to test token spending in Studio without a
	-- live ad.
	[Network.Actions.BuyTokens] = function(player)
		return commerce:BeginIntent(player, "TokenPack70", {})
	end,
	[Network.Actions.EnterAfkLounge] = function(player)
		return afkRewards:Enter(player)
	end,
	[Network.Actions.LeaveAfkLounge] = function(player)
		return afkRewards:Leave(player)
	end,
	[Network.Actions.GetGeneration] = function(player, payload)
		if type(payload) ~= "table" or type(payload.generationId) ~= "string" then
			return false, "INVALID_REQUEST"
		end
		return generations:Get(player, payload.generationId)
	end,
	[Network.Actions.SaveFit] = function(player, payload)
		local success, result = items:SaveFit(player, payload)
		if success then
			analytics:Custom(player, "AccessoryFitSaved", 1, {})
		end
		return success, result
	end,
	[Network.Actions.ResetFitToSuggested] = function(player, payload)
		local itemId = type(payload) == "table" and payload.itemId or nil
		local success, result = items:ResetFitToSuggested(player, itemId)
		if success then
			analytics:Custom(player, "AccessoryFitResetToSuggested", 1, {})
		end
		return success, result
	end,
	[Network.Actions.SaveFitPreset] = function(player, payload)
		local success, result = items:SaveFitPreset(player, payload)
		if success then
			analytics:Custom(player, "FitPresetSaved", 1, {})
			achievements:Unlock(player, "FIRST_FIT_PRESET")
		end
		return success, result
	end,
	[Network.Actions.DeleteFitPreset] = function(player, payload)
		if type(payload) ~= "table" or type(payload.presetId) ~= "string" then
			return false, "INVALID_REQUEST"
		end
		local success, result = items:DeleteFitPreset(player, payload.presetId)
		if success then
			analytics:Custom(player, "FitPresetDeleted", 1, {})
		end
		return success, result
	end,
	[Network.Actions.SaveOutfit] = function(player, payload)
		local success, result = items:SaveOutfit(player, payload)
		if success then
			analytics:Custom(player, "OutfitSaved", 1, {})
		end
		return success, result
	end,
	[Network.Actions.EquipOutfit] = function(player, payload)
		if runway:IsLookFrozen(player) then
			return false, "RUNWAY_LOOK_LOCKED"
		end
		local success, result = items:EquipOutfit(player, payload)
		if success then
			analytics:Custom(player, "OutfitEquipped", 1, {})
		end
		return success, result
	end,
	[Network.Actions.DeleteOutfit] = function(player, payload)
		return items:DeleteOutfit(player, payload)
	end,
	[Network.Actions.EquipItem] = function(player, payload)
		if runway:IsLookFrozen(player) then
			return false, "RUNWAY_LOOK_LOCKED"
		end
		if type(payload) ~= "table" or type(payload.itemId) ~= "string" then
			return false, "INVALID_REQUEST"
		end
		local success, result = items:Equip(player, payload.itemId)
		if success then
			analytics:Custom(player, "GeneratedItemEquipped", 1, {})
			achievements:Unlock(player, "FIRST_EQUIP")
			retention:MarkJourney(player, "TRY_STYLE")
			retention:MarkQuest(player, "TRY_STYLE")
		end
		return success, result
	end,
	[Network.Actions.UnequipItem] = function(player, payload)
		if runway:IsLookFrozen(player) then
			return false, "RUNWAY_LOOK_LOCKED"
		end
		if type(payload) ~= "table" or type(payload.itemId) ~= "string" then
			return false, "INVALID_REQUEST"
		end
		local success, result = items:Unequip(player, payload.itemId)
		if success then
			analytics:Custom(player, "GeneratedItemUnequipped", 1, {})
		end
		return success, result
	end,
	[Network.Actions.PublishItem] = function(player, payload)
		if type(payload) ~= "table" or type(payload.itemId) ~= "string" then
			return false, "INVALID_REQUEST"
		end
		local success, result = items:Publish(player, payload.itemId)
		if success then
			local alreadyPublished = type(result) == "table" and result.alreadyPublished == true
			analytics:Custom(player, "GeneratedItemPublished", 1, { alreadyPublished = alreadyPublished })
			if not alreadyPublished then
				progression:Grant(player, Config.CreatorProgression.FirstPublishXP, "FIRST_PUBLISH")
				achievements:Unlock(player, "FIRST_PUBLISH")
			end
		end
		return success, result
	end,
	[Network.Actions.SetVisibility] = function(player, payload)
		return community:SetVisibility(player, payload)
	end,
	[Network.Actions.SetListing] = function(player, payload)
		return community:SetListing(player, payload)
	end,
	[Network.Actions.SetItemDetails] = function(player, payload)
		return community:SetItemDetails(player, payload)
	end,
	[Network.Actions.GetMarketplace] = function(player, payload)
		local success, result = community:GetMarketplace(player, payload)
		if success then
			local resultCount = if type(result) == "table" and type(result.items) == "table" then #result.items else 0
			local requestedSort = if type(payload) == "table" then payload.sortBy else nil
			local sortBy = if requestedSort == "NEWEST"
					or requestedSort == "PRICE_LOW"
					or requestedSort == "MOST_LIKED"
				then requestedSort
				else "TRENDING"
			analytics:Custom(player, "CommunityMarketplaceLoaded", resultCount, {
				resultCount = resultCount,
				hasResults = resultCount > 0,
				searchBy = if type(payload) == "table" and payload.searchBy == "CREATOR" then "CREATOR" else "NAME",
				sortBy = sortBy,
			})
		end
		return success, result
	end,
	[Network.Actions.GetLeaderboard] = function(player)
		return community:GetLeaderboard(player)
	end,
	[Network.Actions.ToggleLike] = function(player, payload)
		if not reactionLimiter:consume(player.UserId) then
			return false, "RATE_LIMITED"
		end
		return community:ToggleLike(player, payload)
	end,
	[Network.Actions.ToggleFavorite] = function(player, payload)
		if not reactionLimiter:consume(player.UserId) then
			return false, "RATE_LIMITED"
		end
		return community:ToggleFavorite(player, payload)
	end,
	[Network.Actions.BeginMarketplacePurchase] = function(player, payload)
		return community:BeginPurchase(player, payload)
	end,
	[Network.Actions.SetGraphicVisibility] = function(player, payload)
		return community:SetGraphicVisibility(player, payload)
	end,
	[Network.Actions.SetGraphicListing] = function(player, payload)
		return community:SetGraphicListing(player, payload)
	end,
	[Network.Actions.SetGraphicDetails] = function(player, payload)
		return community:SetGraphicDetails(player, payload)
	end,
	[Network.Actions.GetGraphicsMarketplace] = function(player, payload)
		return community:GetGraphicsMarketplace(player, payload)
	end,
	[Network.Actions.ToggleGraphicLike] = function(player, payload)
		if not reactionLimiter:consume(player.UserId) then
			return false, "RATE_LIMITED"
		end
		return community:ToggleGraphicLike(player, payload)
	end,
	[Network.Actions.ToggleGraphicFavorite] = function(player, payload)
		if not reactionLimiter:consume(player.UserId) then
			return false, "RATE_LIMITED"
		end
		return community:ToggleGraphicFavorite(player, payload)
	end,
	[Network.Actions.BeginGraphicPurchase] = function(player, payload)
		return community:BeginGraphicPurchase(player, payload)
	end,
	[Network.Actions.BeginTip] = function(player, payload)
		return community:BeginTip(player, payload)
	end,
	[Network.Actions.RequestPrivateModel] = function(player, payload)
		if type(payload) ~= "table" or type(payload.itemId) ~= "string" then
			return false, "INVALID_REQUEST"
		end
		local item = community:ResolveAccessibleItem(player, payload.itemId)
		if not item then
			return false, "ITEM_NOT_FOUND"
		end
		return items:RequestPrivateModel(player, item)
	end,
	[Network.Actions.TryOnCommunityItem] = function(player, payload)
		if runway:IsLookFrozen(player) then
			return false, "RUNWAY_LOOK_LOCKED"
		end
		if type(payload) ~= "table" or type(payload.itemId) ~= "string" then
			return false, "INVALID_REQUEST"
		end
		local entryPoint = if payload.entryPoint == "FIRST_LOOK" then "FIRST_LOOK" else "GRID"
		analytics:Custom(player, "CommunityTryOnAttempted", 1, { entryPoint = entryPoint })
		local item = community:ResolveAccessibleItem(player, payload.itemId)
		if not item then
			analytics:Custom(player, "CommunityTryOnFailed", 1, {
				entryPoint = entryPoint,
				failure = "ITEM_NOT_FOUND",
			})
			return false, "ITEM_NOT_FOUND"
		end
		local success, result = items:TryOn(player, item)
		if success then
			-- This funnel step means the model actually reached the avatar, not
			-- merely that the player pressed the button. That distinction is
			-- essential when diagnosing public-index versus asset-load failures.
			analytics:Funnel(player, "marketplace", 2, "Community item worn", { entryPoint = entryPoint })
			analytics:Custom(player, "CommunityTryOnSucceeded", 1, { entryPoint = entryPoint })
			achievements:Unlock(player, "FIRST_TRY_ON")
			retention:MarkJourney(player, "TRY_STYLE")
			retention:MarkQuest(player, "TRY_STYLE")
		else
			local failure = if type(result) == "string" and string.match(result, "^[A-Z0-9_]+$")
				then string.sub(result, 1, 32)
				else "TRY_ON_FAILED"
			analytics:Custom(player, "CommunityTryOnFailed", 1, {
				entryPoint = entryPoint,
				failure = failure,
			})
		end
		return success, result
	end,
	[Network.Actions.ClearCommunityTryOn] = function(player)
		if runway:IsLookFrozen(player) then
			return false, "RUNWAY_LOOK_LOCKED"
		end
		return items:ClearCommunityTryOn(player)
	end,
	[Network.Actions.PromptPlus] = function(player)
		return community:PromptPlus(player)
	end,
	[Network.Actions.TryCatalogAsset] = function(player, payload)
		if runway:IsLookFrozen(player) then
			return false, "RUNWAY_LOOK_LOCKED"
		end
		local success, result = catalog:TryOn(player, payload)
		if success then
			achievements:Unlock(player, "FIRST_TRY_ON")
			retention:MarkJourney(player, "TRY_STYLE")
			retention:MarkQuest(player, "TRY_STYLE")
			task.defer(function()
				items:RestoreEquipped(player)
			end)
		end
		return success, result
	end,
	[Network.Actions.UntryCatalogAsset] = function(player, payload)
		if runway:IsLookFrozen(player) then
			return false, "RUNWAY_LOOK_LOCKED"
		end
		local success, result = catalog:Untry(player, payload)
		if success then
			task.defer(function()
				items:RestoreEquipped(player)
			end)
		end
		return success, result
	end,
	[Network.Actions.GetEquippedAvatarAccessories] = function(player)
		return catalog:GetEquippedAccessories(player)
	end,
	[Network.Actions.ResetAvatar] = function(player)
		if runway:IsLookFrozen(player) then
			return false, "RUNWAY_LOOK_LOCKED"
		end
		local success, result = catalog:Reset(player)
		if success then
			task.defer(function()
				items:RestoreEquipped(player)
			end)
		end
		return success, result
	end,
	[Network.Actions.UpdateSettings] = function(player, payload)
		if type(payload) ~= "table" then
			return false, "INVALID_REQUEST"
		end
		local updates: { [string]: any } = {}
		if payload.soundsEnabled ~= nil then
			if type(payload.soundsEnabled) ~= "boolean" then
				return false, "INVALID_REQUEST"
			end
			updates.soundsEnabled = payload.soundsEnabled
		end
		if payload.reduceMotion ~= nil then
			if type(payload.reduceMotion) ~= "boolean" then
				return false, "INVALID_REQUEST"
			end
			updates.reduceMotion = payload.reduceMotion
		end
		if payload.highContrast ~= nil then
			if type(payload.highContrast) ~= "boolean" then
				return false, "INVALID_REQUEST"
			end
			updates.highContrast = payload.highContrast
		end
		if payload.uiScale ~= nil then
			local scale = tonumber(payload.uiScale)
			if not scale or scale < 0.8 or scale > 1.4 then
				return false, "INVALID_REQUEST"
			end
			updates.uiScale = scale
		end
		if payload.simpleMode ~= nil then
			if type(payload.simpleMode) ~= "boolean" then
				return false, "INVALID_REQUEST"
			end
			updates.simpleMode = payload.simpleMode
		end
		if next(updates) == nil then
			return false, "INVALID_REQUEST"
		end
		local success, problem = profiles:Mutate(player, function(profile)
			for key, value in updates do
				profile.settings[key] = value
			end
		end)
		if not success then
			return false, problem
		end
		if not profiles:Save(player) then
			return false, "SAVE_FAILED"
		end
		-- Booleans/numbers only (the exact values a toggle or slider can take),
		-- never free text, so this is safe under the no-prompt-text rule while
		-- still surfacing accessibility-feature adoption.
		analytics:Custom(player, "SettingsChanged", 1, updates)
		return true, { settings = profiles:Get(player).settings }
	end,
	[Network.Actions.CompleteOnboarding] = function(player)
		local existingProfile = profiles:Get(player)
		if
			existingProfile
			and existingProfile.onboarding.completed == true
			and (existingProfile.onboarding.step or 1) >= 2
		then
			return true, {}
		end
		local previousStep = 1
		local mutateSuccess, mutateProblem = profiles:Mutate(player, function(profile)
			previousStep = math.clamp(math.floor(profile.onboarding.step or 1), 1, 4)
			profile.onboarding.completed = true
			profile.onboarding.step = math.max(previousStep, 2)
		end)
		if not mutateSuccess then
			return false, mutateProblem or "PROFILE_UNAVAILABLE"
		end
		if not profiles:Save(player) then
			return false, "SAVE_FAILED"
		end
		-- Choosing a path is the only action this request proves. Opening the
		-- guided First Look and successfully wearing its free item advance
		-- steps 3 and 4 from RetentionService, so analytics reflects behavior
		-- instead of auto-completing the funnel from one modal click.
		if previousStep < 2 then
			analytics:Onboarding(player, 2, "Chose a starting path")
		end
		return true, {}
	end,
	[Network.Actions.CompleteTutorial] = function(player, payload)
		local choice = type(payload) == "table" and payload.choice or nil
		if choice ~= "START_FREE" and choice ~= "MAKE_OWN" and choice ~= "SKIP" then
			return false, "INVALID_REQUEST"
		end
		local existingProfile = profiles:Get(player)
		if not existingProfile then
			return false, "PROFILE_UNAVAILABLE"
		end
		local tutorialVersion = Config.Tutorial.Version
		local existingVersion = math.max(0, math.floor(tonumber(existingProfile.tutorialVersion) or 0))
		if existingVersion >= tutorialVersion then
			return true, { tutorialVersion = existingVersion }
		end
		local previousOnboardingStep = 1
		local previousOnboardingCompleted = false
		local mutateSuccess, mutateProblem = profiles:Mutate(player, function(profile)
			previousOnboardingStep = math.clamp(math.floor(profile.onboarding.step or 1), 1, 4)
			previousOnboardingCompleted = profile.onboarding.completed == true
			profile.tutorialVersion = tutorialVersion
			-- Every exit lands in a usable studio path, including Skip. Marking
			-- onboarding complete is also what permits the free First Look's
			-- OPEN_STUDIO journey action on the next client call.
			profile.onboarding.completed = true
			profile.onboarding.step = math.max(previousOnboardingStep, 2)
		end)
		if not mutateSuccess then
			return false, mutateProblem or "PROFILE_UNAVAILABLE"
		end
		if not profiles:Save(player) then
			-- Keep a transient DataStore failure from making the retry look
			-- complete only in this server's memory. The next tap must retry the
			-- durable save, not silently dismiss a tutorial that will reappear.
			profiles:Mutate(player, function(profile)
				profile.tutorialVersion = existingVersion
				profile.onboarding.completed = previousOnboardingCompleted
				profile.onboarding.step = previousOnboardingStep
			end)
			return false, "SAVE_FAILED"
		end
		analytics:Custom(player, "VisualTutorialCompleted", 1, {
			choice = choice,
			version = tutorialVersion,
		})
		if previousOnboardingStep < 2 then
			analytics:Onboarding(player, 2, "Chose a starting path")
		end
		return true, { tutorialVersion = tutorialVersion }
	end,
	[Network.Actions.Track] = function(player, payload)
		return analytics:TrackClient(player, payload)
	end,
	[Network.Actions.SubmitArcadeScore] = function(player, payload)
		if type(payload) ~= "table" then
			return false, "INVALID_REQUEST"
		end
		local success, result = arcade:SubmitScore(player, payload.game, payload.score)
		if success then
			retention:MarkQuest(player, "ARCADE")
		end
		return success, result
	end,
	[Network.Actions.GetArcadeLeaderboard] = function(player, payload)
		if type(payload) ~= "table" then
			return false, "INVALID_REQUEST"
		end
		return arcade:GetWeeklyTop(player, payload.game)
	end,
	[Network.Actions.GetFriendArcadeLeaderboard] = function(player, payload)
		if type(payload) ~= "table" then
			return false, "INVALID_REQUEST"
		end
		return arcade:GetFriendStandings(player, payload.game)
	end,
	[Network.Actions.GetRunwayState] = function(player)
		return true, runway:GetState(player)
	end,
	[Network.Actions.JoinRunway] = function(player)
		return runway:Join(player)
	end,
	[Network.Actions.LeaveRunway] = function(player)
		return runway:Leave(player)
	end,
	[Network.Actions.ReadyRunwayLook] = function(player)
		return runway:Ready(player)
	end,
	[Network.Actions.VoteRunway] = function(player, payload)
		local targetUserId = type(payload) == "table" and payload.targetUserId or nil
		return runway:Vote(player, targetUserId)
	end,
	[Network.Actions.GetRunwayLeaderboard] = function(player)
		return runway:GetLeaderboard(player)
	end,
}

-- These actions are consumed as structured purchase/generation results by
-- the client. Keep their success contract table-shaped even if a service
-- branch accidentally returns nil or another scalar. The action may already
-- have spent currency or opened a Roblox prompt, so the client must never
-- retry it merely to recover missing presentation metadata.
local structuredGenerationActions: { [string]: boolean } = {
	[Network.Actions.CreateGeneration] = true,
	[Network.Actions.CreateUploadedImage] = true,
	[Network.Actions.CreateFromAvatar] = true,
	[Network.Actions.CreateAvatarGraphic] = true,
	[Network.Actions.CreateTextImage] = true,
	[Network.Actions.ConvertImage] = true,
}

typedRequestRemote.OnServerInvoke = function(player: Player, action: any, payload: any)
	if not remoteLimiter:consume(player.UserId) then
		return { ok = false, error = "RATE_LIMITED" }
	end
	if type(action) ~= "string" or not handlers[action] then
		return { ok = false, error = "UNKNOWN_ACTION" }
	end
	if not loaded[player] and action ~= Network.Actions.Bootstrap then
		initializePlayer(player)
	end
	local success, ok, result = pcall(handlers[action], player, payload)
	if not success then
		warn(string.format("[Main] Remote %s failed for %d: %s", action, player.UserId, tostring(ok)))
		return { ok = false, error = "SERVER_ERROR" }
	end
	if ok and structuredGenerationActions[action] and type(result) ~= "table" then
		warn(
			string.format(
				"[Main] Generation remote %s returned success with %s response data for %d",
				action,
				typeof(result),
				player.UserId
			)
		)
		result = {}
	elseif ok and result == nil then
		warn(string.format("[Main] Remote %s returned success without response data for %d", action, player.UserId))
		result = {}
	end
	if ok then
		return { ok = true, data = result }
	end
	-- Most errors remain a plain code for backward compatibility. A service may
	-- additionally return safe, player-facing diagnostics (for example measured
	-- wearable bounds); keep the code in the same field while carrying those
	-- details alongside it.
	if type(result) == "table" then
		return {
			ok = false,
			error = if type(result.code) == "string" then result.code else "SERVER_ERROR",
			details = result.details,
		}
	end
	return { ok = false, error = result }
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(initializePlayer, player)
end)

Players.PlayerRemoving:Connect(function(player)
	loaded[player] = nil
	loading[player] = nil
	if characterConnections[player] then
		characterConnections[player]:Disconnect()
		characterConnections[player] = nil
	end
	remoteLimiter:remove(player.UserId)
	reactionLimiter:remove(player.UserId)
	analytics:Remove(player)
	retention:Remove(player)
	playerStates:Remove(player)
	commerce:Remove(player)
	afkRewards:Remove(player)
	runway:Remove(player)
	profiles:Remove(player)
end)

for _, player in Players:GetPlayers() do
	task.spawn(initializePlayer, player)
end

game:BindToClose(function()
	profiles:Close()
end)
