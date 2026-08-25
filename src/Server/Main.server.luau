--!strict
--fs
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function push(player: Player, eventName: string, payload: any)
	if player.Parent == Players then
		(pushRemote :: RemoteEvent):FireClient(player, eventName, payload)
	end
end

local profiles = ProfileService.new()
local playerStates = PlayerStateService.new()
local analytics = AnalyticsService.new()
local achievements = AchievementService.new(profiles, push, analytics)
local retention = RetentionService.new(profiles, analytics, achievements)
local backend = BackendService.new()
local commerce = CommerceService.new(profiles, playerStates, analytics, push)
local adRewards = AdRewardService.new(profiles, playerStates, commerce, push, analytics, achievements)
local items = ItemService.new(profiles, playerStates, push)
local generations =
	GenerationService.new(profiles, playerStates, backend, commerce, push, analytics, achievements, items)
local leaderboard = LeaderboardService.new()
local arcade = ArcadeService.new(profiles, playerStates, push, analytics)
local community = CommunityService.new(profiles, playerStates, push, analytics, achievements, leaderboard)
local catalog = CatalogService.new(profiles, playerStates, analytics)
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
	local success = profiles:Load(player)
	if not success or player.Parent ~= Players then
		loading[player] = nil
		return
	end
	local profile = profiles:Get(player)
	playerStates:Initialize(player)
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
	})
	if playerStates:Get(player).groupMember then
		achievements:Unlock(player, "GROUP_JOINED")
	end
	retention:CheckIn(player)
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
		return generations:Create(player, payload)
	end,
	[Network.Actions.CreateUploadedImage] = function(player, payload)
		analytics:BeginFunnel(player, "reference", "Custom image submitted", {
			method = "IMAGE_UPLOAD",
		})
		analytics:Funnel(player, "reference", 2, "Custom image sent to moderation", {
			method = "IMAGE_UPLOAD",
		})
		return generations:CreateUploadedImage(player, payload)
	end,
	[Network.Actions.ConvertImage] = function(player, payload)
		analytics:BeginFunnel(player, "generation", "Approved conversion started", { method = "IMAGE_TO_3D" })
		analytics:Funnel(player, "generation", 2, "Reference image approved", { method = "IMAGE_TO_3D" })
		return generations:ConvertImage(player, payload)
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
	-- Roblox requires a rewarded-ad reward product to also be normally
	-- purchasable with Robux (see AdRewardService), so this is both a real
	-- purchase path and the way to test token spending in Studio without a
	-- live ad.
	[Network.Actions.BuyTokens] = function(player)
		return commerce:BeginIntent(player, "AdRewardTokens", {})
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
	[Network.Actions.EquipItem] = function(player, payload)
		if type(payload) ~= "table" or type(payload.itemId) ~= "string" then
			return false, "INVALID_REQUEST"
		end
		local success, result = items:Equip(player, payload.itemId)
		if success then
			analytics:Custom(player, "GeneratedItemEquipped", 1, {})
			achievements:Unlock(player, "FIRST_EQUIP")
		end
		return success, result
	end,
	[Network.Actions.UnequipItem] = function(player, payload)
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
	[Network.Actions.GetMarketplace] = function(player, payload)
		return community:GetMarketplace(player, payload)
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
		if type(payload) ~= "table" or type(payload.itemId) ~= "string" then
			return false, "INVALID_REQUEST"
		end
		local item = community:ResolveAccessibleItem(player, payload.itemId)
		if not item then
			return false, "ITEM_NOT_FOUND"
		end
		analytics:Funnel(player, "marketplace", 2, "Community item tried", {})
		return items:TryOn(player, item)
	end,
	[Network.Actions.PromptPlus] = function(player)
		return community:PromptPlus(player)
	end,
	[Network.Actions.TryCatalogAsset] = function(player, payload)
		local success, result = catalog:TryOn(player, payload)
		if success then
			achievements:Unlock(player, "FIRST_TRY_ON")
		end
		return success, result
	end,
	[Network.Actions.ResetAvatar] = function(player)
		return catalog:Reset(player)
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
		local mutateSuccess, mutateProblem = profiles:Mutate(player, function(profile)
			profile.onboarding.completed = true
			profile.onboarding.step = 4
		end)
		if not mutateSuccess then
			return false, mutateProblem or "PROFILE_UNAVAILABLE"
		end
		if not profiles:Save(player) then
			return false, "SAVE_FAILED"
		end
		analytics:Onboarding(player, 4, "Ready to create")
		return true, {}
	end,
	[Network.Actions.Track] = function(player, payload)
		return analytics:TrackClient(player, payload)
	end,
	[Network.Actions.SubmitArcadeScore] = function(player, payload)
		if type(payload) ~= "table" then
			return false, "INVALID_REQUEST"
		end
		return arcade:SubmitScore(player, payload.game, payload.score)
	end,
	[Network.Actions.GetArcadeLeaderboard] = function(player, payload)
		if type(payload) ~= "table" then
			return false, "INVALID_REQUEST"
		end
		return arcade:GetWeeklyTop(payload.game)
	end,
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
	if ok and result == nil then
		warn(string.format("[Main] Remote %s returned success without response data for %d", action, player.UserId))
		result = {}
	end
	return if ok then { ok = true, data = result } else { ok = false, error = result }
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
	profiles:Remove(player)
end)

for _, player in Players:GetPlayers() do
	task.spawn(initializePlayer, player)
end

game:BindToClose(function()
	profiles:Close()
end)
