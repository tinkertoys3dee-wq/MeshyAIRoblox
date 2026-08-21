--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local CommerceService = {}
CommerceService.__index = CommerceService

export type PostCommit = () -> ()
export type GrantHandler = (Player, { [string]: any }, string) -> PostCommit?

local function validateProductConfiguration()
	local ownersById = {} :: { [number]: string }
	for productKey, product in Config.Products do
		local productId = product.Id
		if type(productId) ~= "number" or productId < 0 or productId % 1 ~= 0 then
			error(string.format("Config.Products.%s.Id must be a non-negative integer", productKey))
		end
		if productId > 0 then
			local existingOwner = ownersById[productId]
			if existingOwner then
				error(
					string.format(
						"Developer product ID %d is assigned to both %s and %s",
						productId,
						existingOwner,
						productKey
					)
				)
			end
			ownersById[productId] = productKey
		end
	end
end

function CommerceService.new(profileService: any, playerStateService: any, analyticsService: any)
	validateProductConfiguration()
	local self = setmetatable({
		profiles = profileService,
		playerStates = playerStateService,
		handlers = {} :: { [string]: GrantHandler },
		analytics = analyticsService,
		priceCache = nil :: { [string]: number }?,
		priceCacheAt = 0,
	}, CommerceService)

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return self:_ProcessReceipt(receiptInfo)
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
		if isPurchased then
			return
		end
		local player = Players:GetPlayerByUserId(userId)
		local productKey = self:_ProductKey(productId)
		if not player or not productKey then
			return
		end
		local removed = false
		self.profiles:Mutate(player, function(profile)
			for intentId, intent in profile.pendingIntents do
				if intent.productKey == productKey then
					profile.pendingIntents[intentId] = nil
					removed = true
				end
			end
		end)
		if removed then
			self.profiles:Save(player)
		end
	end)
	return self
end

function CommerceService:Register(productKey: string, handler: GrantHandler)
	self.handlers[productKey] = handler
end

function CommerceService:GetPrices(): { [string]: number }
	if self.priceCache and os.clock() - self.priceCacheAt < 300 then
		return table.clone(self.priceCache)
	end
	local result = {}
	for productKey, product in Config.Products do
		local price = product.SuggestedPrice
		if product.Id > 0 then
			local success, info = pcall(function()
				return MarketplaceService:GetProductInfoAsync(product.Id, Enum.InfoType.Product)
			end)
			if success and type(info.PriceInRobux) == "number" then
				price = info.PriceInRobux
			end
		end
		result[productKey] = price
	end
	self.priceCache = result
	self.priceCacheAt = os.clock()
	return table.clone(result)
end

function CommerceService:BeginIntent(
	player: Player,
	productKey: string,
	payload: { [string]: any }
): (boolean, { [string]: any } | string)
	local product = Config.Products[productKey]
	local handler = self.handlers[productKey]
	if not product or not handler then
		return false, "UNKNOWN_PRODUCT"
	end
	if not self.playerStates:Get(player).commerceAllowed then
		return false, "COMMERCE_NOT_ALLOWED"
	end

	local now = os.time()
	local alreadyPending = false
	local cleanupSuccess = self.profiles:Mutate(player, function(profile)
		for pendingId, pending in profile.pendingIntents do
			local expiresAt = if type(pending) == "table" then tonumber(pending.expiresAt) or 0 else 0
			if expiresAt < now then
				profile.pendingIntents[pendingId] = nil
			elseif pending.productKey == productKey then
				alreadyPending = true
			end
		end
	end)
	if not cleanupSuccess then
		return false, "PROFILE_UNAVAILABLE"
	end
	if alreadyPending then
		return false, "PURCHASE_ALREADY_PENDING"
	end

	local intentId = self.profiles:GenerateId("intent")
	local mutateSuccess = self.profiles:Mutate(player, function(profile)
		profile.pendingIntents[intentId] = {
			id = intentId,
			productKey = productKey,
			payload = payload,
			createdAt = now,
			expiresAt = now + Config.Generation.IntentLifetimeSeconds,
		}
	end)
	if not mutateSuccess then
		return false, "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		self.profiles:Mutate(player, function(profile)
			profile.pendingIntents[intentId] = nil
		end)
		return false, "SAVE_FAILED"
	end

	if product.Id <= 0 then
		if RunService:IsStudio() and Config.Studio.AllowMockPurchases then
			local grantSuccess, postCommit = pcall(handler, player, payload, intentId)
			if not grantSuccess then
				warn(string.format("[CommerceService] Mock grant failed: %s", tostring(postCommit)))
				return false, "GRANT_FAILED"
			end
			self.profiles:Mutate(player, function(profile)
				profile.pendingIntents[intentId] = nil
			end)
			if not self.profiles:Save(player) then
				return false, "SAVE_FAILED"
			end
			if type(postCommit) == "function" then
				task.spawn(postCommit)
			end
			return true, { intentId = intentId, mocked = true }
		end
		self.profiles:Mutate(player, function(profile)
			profile.pendingIntents[intentId] = nil
		end)
		return false, "PRODUCT_ID_NOT_CONFIGURED"
	end

	local promptSuccess, promptProblem = pcall(function()
		MarketplaceService:PromptProductPurchase(player, product.Id)
	end)
	if not promptSuccess then
		warn(string.format("[CommerceService] Purchase prompt failed: %s", tostring(promptProblem)))
		self.profiles:Mutate(player, function(profile)
			profile.pendingIntents[intentId] = nil
		end)
		self.profiles:Save(player)
		return false, "PURCHASE_PROMPT_FAILED"
	end
	return true, { intentId = intentId, prompted = true }
end

function CommerceService:_ProductKey(productId: number): string?
	for productKey, product in Config.Products do
		if product.Id == productId then
			return productKey
		end
	end
	return nil
end

function CommerceService:_ProcessReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = self.profiles:Get(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local productKey = self:_ProductKey(receiptInfo.ProductId)
	local handler = if productKey then self.handlers[productKey] else nil
	if not productKey or not handler then
		warn(string.format("[CommerceService] Unknown developer product %s", tostring(receiptInfo.ProductId)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)
	if profile.processedReceipts[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local chosenIntent: { [string]: any }? = nil
	local chosenIntentId: string? = nil
	local oldest = math.huge
	for intentId, intent in profile.pendingIntents do
		if type(intent) == "table" then
			local createdAt = tonumber(intent.createdAt)
			local expiresAt = tonumber(intent.expiresAt)
			if
				intent.productKey == productKey
				and createdAt
				and expiresAt
				and expiresAt >= os.time()
				and createdAt < oldest
			then
				oldest = createdAt
				chosenIntent = intent
				chosenIntentId = intentId
			end
		end
	end

	local payload = if chosenIntent and type(chosenIntent.payload) == "table"
		then chosenIntent.payload
		else { recoveryCredit = true }
	local intentId = chosenIntentId or ("receipt_" .. purchaseId)
	local grantSuccess, postCommit = pcall(handler, player, payload, intentId)
	if not grantSuccess then
		warn(string.format("[CommerceService] Grant failed for %s: %s", purchaseId, tostring(postCommit)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local mutationSuccess = self.profiles:Mutate(player, function(mutableProfile)
		if chosenIntentId then
			mutableProfile.pendingIntents[chosenIntentId] = nil
		end
		mutableProfile.processedReceipts[purchaseId] = os.time()
	end)
	if not mutationSuccess or not self.profiles:Save(player) then
		self.profiles:Mutate(player, function(mutableProfile)
			mutableProfile.processedReceipts[purchaseId] = nil
			if chosenIntentId and chosenIntent then
				mutableProfile.pendingIntents[chosenIntentId] = chosenIntent
			end
		end)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if type(postCommit) == "function" then
		task.spawn(postCommit)
	end
	self.analytics:Economy(player, tonumber(receiptInfo.CurrencySpent) or 0, productKey)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return CommerceService
