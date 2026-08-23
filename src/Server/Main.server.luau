--!strict
--fs
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Network"))
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
local WorldService = require(script.Parent.Services.WorldService)

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

local pushRemote = remoteFolder:FindFirstChild(Network.PushName) :: RemoteEvent?
if not pushRemote then
	pushRemote = Instance.new("RemoteEvent")
	pushRemote.Name = Network.PushName
	pushRemote.Parent = remoteFolder
end

local function push(player: Player, eventName: string, payload: any)
	if player.Parent == Players then
		(pushRemote :: RemoteEvent):FireClient(player, eventName, payload)
	end
end

local profiles = ProfileService.new()
local playerStates = PlayerStateService.new()
local analytics = AnalyticsService.new()
local retention = RetentionService.new(profiles, analytics)
local backend = BackendService.new()
local commerce = CommerceService.new(profiles, playerStates, analytics, push)
local items = ItemService.new(profiles, playerStates, push)
local generations = GenerationService.new(profiles, playerStates, backend, commerce, push, analytics)
local community = CommunityService.new(profiles, playerStates, push, analytics)
local catalog = CatalogService.new(profiles, playerStates, analytics)
local remoteLimiter = RateLimiter.new(50, 10)
local reactionLimiter = RateLimiter.new(8, 10)
local loaded = {} :: { [Player]: boolean }
local loading = {} :: { [Player]: boolean }
local characterConnections = {} :: { [Player]: RBXScriptConnection }

WorldService.Build()

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
	[Network.Actions.BuyPriorityPass] = function(player)
		return commerce:BeginIntent(player, "PriorityPass", {})
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
	[Network.Actions.EquipItem] = function(player, payload)
		if type(payload) ~= "table" or type(payload.itemId) ~= "string" then
			return false, "INVALID_REQUEST"
		end
		local success, result = items:Equip(player, payload.itemId)
		if success then
			analytics:Custom(player, "GeneratedItemEquipped", 1, {})
		end
		return success, result
	end,
	[Network.Actions.PublishItem] = function(player, payload)
		if type(payload) ~= "table" or type(payload.itemId) ~= "string" then
			return false, "INVALID_REQUEST"
		end
		local success, result = items:Publish(player, payload.itemId)
		if success then
			analytics:Custom(player, "GeneratedItemPublished", 1, {
				alreadyPublished = type(result) == "table" and result.alreadyPublished == true,
			})
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
		return catalog:TryOn(player, payload)
	end,
	[Network.Actions.ResetAvatar] = function(player)
		return catalog:Reset(player)
	end,
	[Network.Actions.UpdateSettings] = function(player, payload)
		if type(payload) ~= "table" or type(payload.soundsEnabled) ~= "boolean" then
			return false, "INVALID_REQUEST"
		end
		local success, problem = profiles:Mutate(player, function(profile)
			profile.settings.soundsEnabled = payload.soundsEnabled
		end)
		if not success then
			return false, problem
		end
		if not profiles:Save(player) then
			return false, "SAVE_FAILED"
		end
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
}

local typedRequestRemote = requestRemote :: RemoteFunction
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
