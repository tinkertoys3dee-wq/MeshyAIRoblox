--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local ProfileService = {}
ProfileService.__index = ProfileService

local SAVE_INTERVAL = 45
local MAX_ATTEMPTS = 4

local function keyFor(userId: number): string
	return `u_{userId}`
end

local function defaultProfile(userId: number): { [string]: any }
	local now = os.time()
	return {
		schemaVersion = 2,
		userId = userId,
		items = {},
		itemOrder = {},
		generations = {},
		generationOrder = {},
		graphics = {},
		graphicOrder = {},
		likedItems = {},
		favoriteItems = {},
		pendingIntents = {},
		pendingTransfers = {},
		processedReceipts = {},
		grantedIntents = {},
		retryCredits = {},
		equippedItemIds = {},
		fitPresets = {},
		fitPresetOrder = {},
		outfits = {},
		outfitOrder = {},
		-- Two separate Forge Tokens pools, deliberately never merged into one
		-- balance: `tokens` is backed by real money (a rewarded ad or a
		-- direct Robux purchase of AdRewardTokens) and may fund generation
		-- products at their steep, revenue-safe token price; `bonusTokens`
		-- (achievements, daily check-in, invites, group join) has no revenue
		-- behind it at all and may only ever buy the near-zero-cost Priority
		-- Pass — see CommerceService:BeginIntentWithTokens. Keeping them
		-- apart is what makes "tokens can safely buy generations" and "free
		-- tokens are safe to hand out" both true at once; a single shared
		-- balance would let a free token silently fund a real-cost purchase.
		tokens = 0,
		bonusTokens = 0,
		adWatch = { day = 0, count = 0 },
		achievements = {},
		settings = { soundsEnabled = true, reduceMotion = false, highContrast = false, uiScale = 1 },
		stats = {
			sessions = 0,
			generationsStarted = 0,
			generationsCompleted = 0,
			imagesRegenerated = 0,
			customImagesSubmitted = 0,
			itemsPublished = 0,
			marketplacePurchases = 0,
			catalogTryOns = 0,
			likesReceived = 0,
		},
		daily = {
			lastDay = 0,
			streak = 0,
			best = 0,
			questsDay = 0,
			questsDone = {},
			challengesDay = 0,
			challengesDone = {},
		},
		onboarding = { completed = false, step = 1 },
		createdAt = now,
		updatedAt = now,
	}
end

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, nested in value :: any do
		(result :: any)[deepCopy(key)] = deepCopy(nested)
	end
	return result :: T
end

local function reconcile(target: { [string]: any }, template: { [string]: any })
	for key, value in template do
		if target[key] == nil then
			target[key] = deepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" then
			reconcile(target[key], value)
		end
	end
end

local function retry<T>(operation: () -> T): (boolean, T | string)
	local lastError = "Unknown DataStore error"
	for attempt = 1, MAX_ATTEMPTS do
		local success, result = pcall(operation)
		if success then
			return true, result
		end
		lastError = tostring(result)
		if attempt < MAX_ATTEMPTS then
			task.wait(0.5 * (2 ^ (attempt - 1)))
		end
	end
	return false, lastError
end

function ProfileService.new()
	local self = setmetatable({
		store = DataStoreService:GetDataStore(Config.DataStores.Player),
		profiles = {} :: { [Player]: { [string]: any } },
		dirty = {} :: { [Player]: boolean },
		closing = false,
	}, ProfileService)

	task.spawn(function()
		while not self.closing do
			task.wait(SAVE_INTERVAL)
			for player in self.dirty do
				if player.Parent == Players then
					self:Save(player)
				end
			end
		end
	end)

	return self
end

function ProfileService:Load(player: Player): (boolean, string?)
	if self.profiles[player] then
		return true
	end

	local success, stored = retry(function()
		return self.store:GetAsync(keyFor(player.UserId))
	end)
	if not success then
		warn(`[ProfileService] Load failed for {player.UserId}: {stored}`)
		if not RunService:IsStudio() then
			return false, "PROFILE_LOAD_FAILED"
		end
		stored = nil
	end

	local profile = if type(stored) == "table" then stored :: { [string]: any } else defaultProfile(player.UserId)
	reconcile(profile, defaultProfile(player.UserId))
	-- The single "ImagePreview" reference-image product split into three
	-- quality tiers ("ImagePreviewLow/Medium/High"). Low kept the original
	-- product ID and price, so fold forward any unspent credit a player
	-- already earned under the retired key rather than stranding it.
	if profile.retryCredits and profile.retryCredits.ImagePreview then
		profile.retryCredits.ImagePreviewLow = (profile.retryCredits.ImagePreviewLow or 0)
			+ profile.retryCredits.ImagePreview
		profile.retryCredits.ImagePreview = nil
	end
	profile.schemaVersion = 2
	profile.userId = player.UserId
	profile.updatedAt = os.time()
	profile.stats.sessions += 1
	self.profiles[player] = profile
	self.dirty[player] = true
	return true
end

function ProfileService:Get(player: Player): { [string]: any }?
	return self.profiles[player]
end

function ProfileService:Mutate(player: Player, mutator: ({ [string]: any }) -> ()): (boolean, string?)
	local profile = self.profiles[player]
	if not profile then
		return false, "PROFILE_NOT_LOADED"
	end
	local success, problem = pcall(mutator, profile)
	if not success then
		warn(`[ProfileService] Mutation failed for {player.UserId}: {problem}`)
		return false, "PROFILE_MUTATION_FAILED"
	end
	profile.updatedAt = os.time()
	self.dirty[player] = true
	return true
end

function ProfileService:Save(player: Player): boolean
	local profile = self.profiles[player]
	if not profile then
		return true
	end
	profile.updatedAt = os.time()
	local snapshot = deepCopy(profile)
	local success, result = retry(function()
		return self.store:UpdateAsync(keyFor(player.UserId), function()
			return snapshot
		end)
	end)
	if success then
		self.dirty[player] = nil
		return true
	end
	warn(`[ProfileService] Save failed for {player.UserId}: {result}`)
	if RunService:IsStudio() then
		-- Studio often runs with API Services disabled. Keep mock-purchase testing
		-- functional while making production servers fail closed on persistence.
		self.dirty[player] = nil
		return true
	end
	return false
end

function ProfileService:ReadUser(userId: number): { [string]: any }?
	for player, profile in self.profiles do
		if player.UserId == userId then
			return deepCopy(profile)
		end
	end
	local success, result = retry(function()
		return self.store:GetAsync(keyFor(userId))
	end)
	if success and type(result) == "table" then
		local profile = result :: { [string]: any }
		reconcile(profile, defaultProfile(userId))
		profile.schemaVersion = 2
		return profile
	end
	return nil
end

function ProfileService:MutateUser(userId: number, mutator: ({ [string]: any }) -> ()): boolean
	for player in self.profiles do
		if player.UserId == userId then
			local success = self:Mutate(player, mutator)
			return success
		end
	end

	local success, result = retry(function()
		return self.store:UpdateAsync(keyFor(userId), function(stored)
			local profile = if type(stored) == "table" then stored else defaultProfile(userId)
			reconcile(profile, defaultProfile(userId))
			profile.schemaVersion = 2
			mutator(profile)
			profile.updatedAt = os.time()
			return profile
		end)
	end)
	if not success then
		warn(`[ProfileService] Offline mutation failed for {userId}: {result}`)
	end
	return success
end

function ProfileService:PublicSnapshot(player: Player): { [string]: any }?
	local profile = self.profiles[player]
	if not profile then
		return nil
	end
	local snapshot = deepCopy(profile)
	snapshot.pendingIntents = nil
	snapshot.pendingTransfers = nil
	snapshot.processedReceipts = nil
	snapshot.grantedIntents = nil
	return snapshot
end

function ProfileService:Remove(player: Player)
	self:Save(player)
	self.profiles[player] = nil
	self.dirty[player] = nil
end

function ProfileService:Close()
	self.closing = true
	for player in self.profiles do
		self:Save(player)
	end
end

function ProfileService:GenerateId(prefix: string): string
	return `{prefix}_{string.gsub(HttpService:GenerateGUID(false), "-", "")}`
end

return ProfileService
