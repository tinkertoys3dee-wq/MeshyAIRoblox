--!strict

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local CommunityService = {}
CommunityService.__index = CommunityService

local INDEX_KEY = "public_v1"
local MAX_PUBLIC_ITEMS = 250
local CACHE_SECONDS = 12

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

local function score(entry: { [string]: any }): number
	local ageHours = math.max(0, (os.time() - (entry.updatedAt or os.time())) / 3600)
	local engagement = (entry.likes or 0) * 5 + (entry.favorites or 0) * 8 + (entry.views or 0) * 0.35
	return (engagement + 2) / ((ageHours + 2) ^ 0.55)
end

local function publicItem(
	item: { [string]: any },
	ownerName: string,
	viewerProfile: { [string]: any }
): { [string]: any }
	return {
		id = item.id,
		ownerUserId = item.ownerUserId,
		ownerName = ownerName,
		name = item.name,
		method = item.method,
		stylePreset = item.stylePreset or "AUTO",
		detailLevel = item.detailLevel or "BALANCED",
		createdAt = item.createdAt,
		updatedAt = item.updatedAt,
		modelAssetId = item.modelAssetId,
		thumbnailAssetId = item.thumbnailAssetId,
		fit = deepCopy(item.fit),
		isListed = item.isListed == true,
		listingPriceRobux = item.listingPriceRobux,
		likes = item.likes or 0,
		favorites = item.favorites or 0,
		views = item.views or 0,
		viewerLiked = viewerProfile.likedItems[item.id] == true,
		viewerFavorited = viewerProfile.favoriteItems[item.id] == true,
	}
end

function CommunityService.new(
	profileService: any,
	playerStateService: any,
	push: (Player, string, any) -> (),
	analyticsService: any
)
	local self = setmetatable({
		profiles = profileService,
		playerStates = playerStateService,
		push = push,
		analytics = analyticsService,
		indexStore = DataStoreService:GetDataStore(Config.DataStores.ItemIndex),
		claimStore = DataStoreService:GetDataStore(Config.DataStores.ReceiptClaims),
		indexCache = nil :: { [string]: any }?,
		indexCacheAt = 0,
		nameCache = {} :: { [number]: string },
	}, CommunityService)

	MarketplaceService:BindReceiptHandler(Enum.ReceiptType.RobuxTransferSender, function(receiptInfo)
		return self:_ProcessSenderReceipt(receiptInfo)
	end)
	MarketplaceService:BindReceiptHandler(Enum.ReceiptType.RobuxTransferReceiver, function(_receiptInfo)
		return Enum.ReceiptDecision.Processed
	end)
	return self
end

function CommunityService:_ReadIndex(): { [string]: any }
	if self.indexCache and os.clock() - self.indexCacheAt < CACHE_SECONDS then
		return deepCopy(self.indexCache)
	end
	local success, result = pcall(function()
		return self.indexStore:GetAsync(INDEX_KEY)
	end)
	local index = if success and type(result) == "table" then result else { entries = {}, updatedAt = os.time() }
	if type(index.entries) ~= "table" then
		index.entries = {}
	end
	self.indexCache = index
	self.indexCacheAt = os.clock()
	return deepCopy(index)
end

function CommunityService:_UpdateIndex(item: { [string]: any }, visible: boolean): boolean
	local success, problem = pcall(function()
		self.indexStore:UpdateAsync(INDEX_KEY, function(stored)
			local index = if type(stored) == "table" then stored else { entries = {} }
			if type(index.entries) ~= "table" then
				index.entries = {}
			end
			if visible then
				local old = index.entries[item.id] or {}
				index.entries[item.id] = {
					itemId = item.id,
					ownerUserId = item.ownerUserId,
					updatedAt = os.time(),
					likes = item.likes or old.likes or 0,
					favorites = item.favorites or old.favorites or 0,
					views = item.views or old.views or 0,
				}
				local entries = {}
				for _, entry in index.entries do
					table.insert(entries, entry)
				end
				if #entries > MAX_PUBLIC_ITEMS then
					table.sort(entries, function(left, right)
						return score(left) > score(right)
					end)
					for position = MAX_PUBLIC_ITEMS + 1, #entries do
						index.entries[entries[position].itemId] = nil
					end
				end
			else
				index.entries[item.id] = nil
			end
			index.updatedAt = os.time()
			return index
		end)
	end)
	if not success then
		warn(string.format("[CommunityService] Public index update failed: %s", tostring(problem)))
		return false
	end
	self.indexCache = nil
	return true
end

function CommunityService:_AdjustIndex(itemId: string, field: string, delta: number)
	local success, problem = pcall(function()
		self.indexStore:UpdateAsync(INDEX_KEY, function(stored)
			local index = if type(stored) == "table" then stored else { entries = {} }
			local entry = index.entries and index.entries[itemId]
			if entry then
				entry[field] = math.max(0, (entry[field] or 0) + delta)
				entry.updatedAt = os.time()
			end
			index.updatedAt = os.time()
			return index
		end)
	end)
	if not success then
		warn(string.format("[CommunityService] Engagement index update failed: %s", tostring(problem)))
	end
	self.indexCache = nil
end

function CommunityService:_OwnerName(userId: number): string
	if self.nameCache[userId] then
		return self.nameCache[userId]
	end
	local success, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if success then result else "Creator"
	self.nameCache[userId] = name
	return name
end

function CommunityService:_ResolvePublic(itemId: string): ({ [string]: any }?, string?)
	local index = self:_ReadIndex()
	local reference = index.entries[itemId]
	if not reference then
		return nil, nil
	end
	local ownerProfile = self.profiles:ReadUser(reference.ownerUserId)
	local item = ownerProfile and ownerProfile.items[itemId]
	if not item or item.visibility ~= "PUBLIC" then
		return nil, nil
	end
	item.likes = reference.likes or item.likes or 0
	item.favorites = reference.favorites or item.favorites or 0
	item.views = reference.views or item.views or 0
	return item, self:_OwnerName(reference.ownerUserId)
end

function CommunityService:GetMarketplace(player: Player, payload: any): (boolean, any)
	if not self.playerStates:Get(player).contentSharingAllowed then
		return false, "CONTENT_SHARING_DISABLED"
	end
	local viewerProfile = self.profiles:Get(player)
	if not viewerProfile then
		return false, "PROFILE_UNAVAILABLE"
	end
	local query = ""
	if type(payload) == "table" and type(payload.query) == "string" then
		query = string.lower(string.sub(payload.query, 1, 60))
	end
	local references = {}
	for _, entry in self:_ReadIndex().entries do
		table.insert(references, entry)
	end
	table.sort(references, function(left, right)
		return score(left) > score(right)
	end)

	local items = {}
	for _, reference in references do
		if #items >= Config.Marketplace.PageSize then
			break
		end
		local item, ownerName = self:_ResolvePublic(reference.itemId)
		if item and (query == "" or string.find(string.lower(item.name), query, 1, true)) then
			table.insert(items, publicItem(item, ownerName or "Creator", viewerProfile))
		end
	end
	return true, { items = items, refreshedAt = os.time() }
end

function CommunityService:SetVisibility(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" or type(payload.itemId) ~= "string" or type(payload.isPublic) ~= "boolean" then
		return false, "INVALID_REQUEST"
	end
	if payload.isPublic and not self.playerStates:Get(player).contentSharingAllowed then
		return false, "CONTENT_SHARING_DISABLED"
	end
	local profile = self.profiles:Get(player)
	local item = profile and profile.items[payload.itemId]
	if not item or item.ownerUserId ~= player.UserId or item.license ~= "ORIGINAL" then
		return false, "ITEM_NOT_SHAREABLE"
	end
	local mutateSuccess, mutateProblem = self.profiles:Mutate(player, function(mutableProfile)
		local mutableItem = mutableProfile.items[payload.itemId]
		mutableItem.visibility = if payload.isPublic then "PUBLIC" else "PRIVATE"
		if not payload.isPublic then
			mutableItem.isListed = false
			mutableItem.listingPriceRobux = nil
		end
		mutableItem.updatedAt = os.time()
	end)
	if not mutateSuccess then
		return false, mutateProblem or "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		return false, "SAVE_FAILED"
	end
	item = self.profiles:Get(player).items[payload.itemId]
	if not self:_UpdateIndex(item, payload.isPublic) then
		return false, "MARKETPLACE_UNAVAILABLE"
	end
	self.analytics:Custom(player, "CommunityVisibilityChanged", 1, { isPublic = payload.isPublic })
	return true, { item = item }
end

function CommunityService:SetListing(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" or type(payload.itemId) ~= "string" or type(payload.isListed) ~= "boolean" then
		return false, "INVALID_REQUEST"
	end
	local state = self.playerStates:Get(player)
	if not state.contentSharingAllowed or not state.paidTradingAllowed then
		return false, "COMMERCE_NOT_ALLOWED"
	end
	local profile = self.profiles:Get(player)
	local item = profile and profile.items[payload.itemId]
	if not item or item.ownerUserId ~= player.UserId or not item.canList or item.license ~= "ORIGINAL" then
		return false, "ITEM_NOT_LISTABLE"
	end
	local price = math.floor(tonumber(payload.priceRobux) or 0)
	if
		payload.isListed
		and (price < Config.Marketplace.MinimumTransferRobux or price > Config.Marketplace.MaximumTransferRobux)
	then
		return false, "PRICE_OUT_OF_RANGE"
	end
	local mutateSuccess, mutateProblem = self.profiles:Mutate(player, function(mutableProfile)
		local mutableItem = mutableProfile.items[payload.itemId]
		mutableItem.isListed = payload.isListed
		mutableItem.listingPriceRobux = if payload.isListed then price else nil
		if payload.isListed then
			mutableItem.visibility = "PUBLIC"
		end
		mutableItem.updatedAt = os.time()
	end)
	if not mutateSuccess then
		return false, mutateProblem or "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		return false, "SAVE_FAILED"
	end
	item = self.profiles:Get(player).items[payload.itemId]
	if not self:_UpdateIndex(item, item.visibility == "PUBLIC") then
		return false, "MARKETPLACE_UNAVAILABLE"
	end
	self.analytics:Custom(player, "MarketplaceListingChanged", 1, {
		isListed = payload.isListed,
		price = if payload.isListed then price else 0,
	})
	return true, { item = item }
end

function CommunityService:_ToggleReaction(
	player: Player,
	itemId: string,
	profileField: string,
	countField: string
): (boolean, any)
	if not self.playerStates:Get(player).contentSharingAllowed then
		return false, "CONTENT_SHARING_DISABLED"
	end
	local item = self:_ResolvePublic(itemId)
	if not item then
		return false, "ITEM_NOT_FOUND"
	end
	local enabled = false
	local mutateSuccess, mutateProblem = self.profiles:Mutate(player, function(profile)
		enabled = profile[profileField][itemId] ~= true
		profile[profileField][itemId] = if enabled then true else nil
	end)
	if not mutateSuccess then
		return false, mutateProblem or "PROFILE_UNAVAILABLE"
	end
	local delta = if enabled then 1 else -1
	self:_AdjustIndex(itemId, countField, delta)
	self.profiles:MutateUser(item.ownerUserId, function(ownerProfile)
		local ownerItem = ownerProfile.items[itemId]
		if ownerItem then
			ownerItem[countField] = math.max(0, (ownerItem[countField] or 0) + delta)
		end
	end)
	self.analytics:Custom(
		player,
		if countField == "likes" then "CommunityLikeToggled" else "CommunityFavoriteToggled",
		1,
		{
			enabled = enabled,
		}
	)
	return true, { enabled = enabled }
end

function CommunityService:ToggleLike(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" or type(payload.itemId) ~= "string" then
		return false, "INVALID_REQUEST"
	end
	return self:_ToggleReaction(player, payload.itemId, "likedItems", "likes")
end

function CommunityService:ToggleFavorite(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" or type(payload.itemId) ~= "string" then
		return false, "INVALID_REQUEST"
	end
	return self:_ToggleReaction(player, payload.itemId, "favoriteItems", "favorites")
end

function CommunityService:ResolveAccessibleItem(player: Player, itemId: string): ({ [string]: any }?, string?)
	local profile = self.profiles:Get(player)
	local own = profile and profile.items[itemId]
	if own then
		return own, player.Name
	end
	if not self.playerStates:Get(player).contentSharingAllowed then
		return nil, nil
	end
	local item, ownerName = self:_ResolvePublic(itemId)
	if item then
		self:_AdjustIndex(itemId, "views", 1)
		self.profiles:MutateUser(item.ownerUserId, function(ownerProfile)
			local ownerItem = ownerProfile.items[itemId]
			if ownerItem then
				ownerItem.views = (ownerItem.views or 0) + 1
			end
		end)
	end
	return item, ownerName
end

function CommunityService:BeginPurchase(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" or type(payload.itemId) ~= "string" then
		return false, "INVALID_REQUEST"
	end
	local state = self.playerStates:Get(player)
	local studioMock = RunService:IsStudio() and Config.Studio.AllowMockPurchases
	if not state.plusSubscriber and not studioMock then
		return false, "PLUS_REQUIRED"
	end
	if not state.contentSharingAllowed or not state.paidTradingAllowed then
		return false, "COMMERCE_NOT_ALLOWED"
	end
	local item = self:_ResolvePublic(payload.itemId)
	if not item or not item.isListed or item.ownerUserId == player.UserId then
		return false, "LISTING_UNAVAILABLE"
	end
	local amount = math.floor(tonumber(item.listingPriceRobux) or 0)
	if amount < Config.Marketplace.MinimumTransferRobux or amount > Config.Marketplace.MaximumTransferRobux then
		return false, "PRICE_OUT_OF_RANGE"
	end
	local now = os.time()
	local alreadyPending = false
	local cleanupSuccess, cleanupProblem = self.profiles:Mutate(player, function(profile)
		for transferId, pending in profile.pendingTransfers do
			local createdAt = if type(pending) == "table" then tonumber(pending.createdAt) or 0 else 0
			if
				type(pending) ~= "table"
				or (
					pending.status == "PROMPTING"
					and createdAt + Config.Marketplace.TransferIntentLifetimeSeconds < now
				)
			then
				profile.pendingTransfers[transferId] = nil
			else
				alreadyPending = true
			end
		end
	end)
	if not cleanupSuccess then
		return false, cleanupProblem or "PROFILE_UNAVAILABLE"
	end
	if alreadyPending then
		return false, "TRANSFER_ALREADY_PENDING"
	end
	local snapshot = deepCopy(item)
	local preliminaryId = self.profiles:GenerateId("transfer")
	local mutateSuccess, mutateProblem = self.profiles:Mutate(player, function(profile)
		profile.pendingTransfers[preliminaryId] = {
			transferRequestId = preliminaryId,
			status = "PROMPTING",
			itemId = item.id,
			sellerUserId = item.ownerUserId,
			amount = amount,
			sourceItem = snapshot,
			createdAt = now,
		}
	end)
	if not mutateSuccess then
		return false, mutateProblem or "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		self.profiles:Mutate(player, function(profile)
			profile.pendingTransfers[preliminaryId] = nil
		end)
		return false, "SAVE_FAILED"
	end

	if studioMock then
		local granted, result = self:_GrantCopy(player, preliminaryId)
		return granted, if granted then { mocked = true, item = result } else result
	end

	local success, transferId = pcall(function()
		return MarketplaceService:PromptRobuxTransferAsync(player, item.ownerUserId, amount)
	end)
	if not success or type(transferId) ~= "string" then
		self.profiles:Mutate(player, function(profile)
			profile.pendingTransfers[preliminaryId] = nil
		end)
		self.profiles:Save(player)
		return false, "TRANSFER_PROMPT_FAILED"
	end
	local recoverySaved, recoveryProblem = pcall(function()
		self.claimStore:UpdateAsync(transferId, function(stored)
			if type(stored) == "table" and stored.state == "PROCESSED" then
				return stored
			end
			return {
				state = "PENDING",
				buyerUserId = player.UserId,
				preliminaryId = preliminaryId,
				createdAt = now,
			}
		end)
	end)
	if not recoverySaved then
		warn(string.format("[CommunityService] Transfer recovery marker failed: %s", tostring(recoveryProblem)))
	end
	self.profiles:Mutate(player, function(profile)
		local pending = profile.pendingTransfers[preliminaryId]
		if pending then
			profile.pendingTransfers[preliminaryId] = nil
			pending.transferRequestId = transferId
			pending.status = "AWAITING_RECEIPT"
			profile.pendingTransfers[transferId] = pending
		end
	end)
	if not self.profiles:Save(player) then
		warn(string.format("[CommunityService] Transfer %s is awaiting a persistence retry", transferId))
	end
	self.analytics:Funnel(player, "marketplace", 3, "Transfer prompted", { price = amount })
	return true, { transferRequestId = transferId, prompted = true }
end

function CommunityService:_GrantCopy(player: Player, transferId: string): (boolean, any)
	local profile = self.profiles:Get(player)
	local pending = profile and profile.pendingTransfers[transferId]
	if not pending then
		return false, "TRANSFER_NOT_FOUND"
	end
	local receiptKey = "transfer:" .. transferId
	local copyId = "copy_" .. string.sub(string.gsub(transferId, "%W", ""), 1, 54)
	if profile.processedReceipts[receiptKey] then
		return true, profile.items[copyId]
	end
	local source = pending.sourceItem
	if type(source) ~= "table" then
		return false, "SOURCE_ITEM_UNAVAILABLE"
	end
	self.profiles:Mutate(player, function(mutableProfile)
		if not mutableProfile.items[copyId] then
			local now = os.time()
			mutableProfile.items[copyId] = {
				id = copyId,
				ownerUserId = player.UserId,
				originalOwnerUserId = source.originalOwnerUserId or source.ownerUserId,
				sourceItemId = source.id,
				license = "PERSONAL_COPY",
				canList = false,
				canPublish = true,
				name = source.name,
				filteredPrompt = source.filteredPrompt,
				method = source.method,
				stylePreset = source.stylePreset or "AUTO",
				detailLevel = source.detailLevel or "BALANCED",
				status = "READY",
				createdAt = now,
				updatedAt = now,
				modelAssetId = source.modelAssetId,
				thumbnailAssetId = source.thumbnailAssetId,
				fit = deepCopy(source.fit),
				visibility = "PRIVATE",
				isListed = false,
				likes = 0,
				favorites = 0,
				views = 0,
			}
			table.insert(mutableProfile.itemOrder, 1, copyId)
			mutableProfile.stats.marketplacePurchases += 1
		end
		mutableProfile.processedReceipts[receiptKey] = os.time()
		mutableProfile.pendingTransfers[transferId] = nil
	end)
	if not self.profiles:Save(player) then
		return false, "SAVE_FAILED"
	end
	pcall(function()
		self.claimStore:UpdateAsync(transferId, function()
			return {
				state = "PROCESSED",
				buyerUserId = player.UserId,
				itemId = copyId,
				processedAt = os.time(),
			}
		end)
	end)
	local copy = self.profiles:Get(player).items[copyId]
	self.push(player, Network.PushEvents.Item, { itemId = copyId, item = copy })
	self.push(player, Network.PushEvents.Transfer, { status = "COMPLETED", itemId = copyId })
	self.push(player, Network.PushEvents.Toast, {
		tone = "ready",
		message = "Purchase verified. Your personal, non-resellable copy is ready to fit.",
	})
	self.analytics:Funnel(player, "marketplace", 4, "Personal copy granted", { price = pending.amount })
	return true, copy
end

function CommunityService:_ProcessSenderReceipt(receiptInfo: { [string]: any }): Enum.ReceiptDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player or not self.profiles:Get(player) then
		return Enum.ReceiptDecision.NotProcessedYet
	end
	local transferId = tostring(receiptInfo.TransferRequestId)
	local profile = self.profiles:Get(player)
	local pending = profile.pendingTransfers[transferId]
	if not pending then
		local markerSuccess, marker = pcall(function()
			return self.claimStore:GetAsync(transferId)
		end)
		if markerSuccess and type(marker) == "table" and marker.buyerUserId == player.UserId then
			if marker.state == "PROCESSED" then
				return Enum.ReceiptDecision.Processed
			end
			local preliminaryId = marker.preliminaryId
			if type(preliminaryId) == "string" then
				self.profiles:Mutate(player, function(mutableProfile)
					local recovered = mutableProfile.pendingTransfers[preliminaryId]
					if recovered then
						mutableProfile.pendingTransfers[preliminaryId] = nil
						recovered.transferRequestId = transferId
						recovered.status = "AWAITING_RECEIPT"
						mutableProfile.pendingTransfers[transferId] = recovered
					end
				end)
				pending = self.profiles:Get(player).pendingTransfers[transferId]
			end
		end
	end
	if not pending then
		local processed = profile.processedReceipts["transfer:" .. transferId]
		if processed and self.profiles:Save(player) then
			return Enum.ReceiptDecision.Processed
		end
		return Enum.ReceiptDecision.NotProcessedYet
	end
	local spent = tonumber(receiptInfo.CurrencySpent)
	if not spent or math.floor(spent) ~= pending.amount then
		warn(string.format("[CommunityService] Transfer %s amount did not match the stored listing", transferId))
		return Enum.ReceiptDecision.NotProcessedYet
	end
	local success = self:_GrantCopy(player, transferId)
	return if success then Enum.ReceiptDecision.Processed else Enum.ReceiptDecision.NotProcessedYet
end

function CommunityService:PromptPlus(player: Player): (boolean, any)
	if player.HasRobloxSubscription then
		return true, { alreadySubscribed = true }
	end
	if not self.playerStates:Get(player).subscriptionAllowed then
		return false, "SUBSCRIPTION_NOT_ALLOWED"
	end
	local success, problem = pcall(function()
		MarketplaceService:PromptRobloxSubscriptionPurchase(player)
	end)
	if not success then
		warn(string.format("[CommunityService] Plus prompt failed: %s", tostring(problem)))
		return false, "SUBSCRIPTION_PROMPT_FAILED"
	end
	return true, { prompted = true }
end

return CommunityService
