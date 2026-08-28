--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local CommerceService = {}
CommerceService.__index = CommerceService

local PASS_CACHE_SECONDS = 60

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

local function validatePassConfiguration()
	local ownersById = {} :: { [number]: string }
	for passKey, pass in Config.Passes do
		local passId = pass.Id
		if type(passId) ~= "number" or passId < 0 or passId % 1 ~= 0 then
			error(string.format("Config.Passes.%s.Id must be a non-negative integer", passKey))
		end
		if passId > 0 then
			local existingOwner = ownersById[passId]
			if existingOwner then
				error(string.format("Game pass ID %d is assigned to both %s and %s", passId, existingOwner, passKey))
			end
			ownersById[passId] = passKey
		end
	end
end

function CommerceService.new(
	profileService: any,
	playerStateService: any,
	analyticsService: any,
	push: (Player, string, any) -> ()
)
	validateProductConfiguration()
	validatePassConfiguration()
	local self = setmetatable({
		profiles = profileService,
		playerStates = playerStateService,
		handlers = {} :: { [string]: GrantHandler },
		analytics = analyticsService,
		push = push,
		priceCache = nil :: { [string]: number }?,
		priceCacheAt = 0,
		passCache = {} :: { [number]: { [string]: { owned: boolean, checkedAt: number } } },
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
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased or player.Parent ~= Players then
			return
		end
		local passKey = self:_PassKey(passId)
		if not passKey then
			return
		end
		self:_CachePass(player, passKey, true)
		local prices = self:GetPrices()
		self.analytics:Economy(player, prices[passKey] or 0, "GamePass_" .. passKey)
		self.analytics:Custom(player, "GamePassPurchased", 1, { pass = passKey })
		self.push(player, Network.PushEvents.Entitlements, self:GetEntitlements(player))
		self.push(player, Network.PushEvents.Toast, {
			tone = "ready",
			message = "Custom image upload is permanently unlocked.",
		})
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
	for passKey, pass in Config.Passes do
		local price = pass.SuggestedPrice
		if pass.Id > 0 then
			local success, info = pcall(function()
				return MarketplaceService:GetProductInfoAsync(pass.Id, Enum.InfoType.GamePass)
			end)
			if success and type(info.PriceInRobux) == "number" then
				price = info.PriceInRobux
			end
		end
		result[passKey] = price
	end
	self.priceCache = result
	self.priceCacheAt = os.clock()
	return table.clone(result)
end

function CommerceService:_PassKey(passId: number): string?
	for passKey, pass in Config.Passes do
		if pass.Id == passId then
			return passKey
		end
	end
	return nil
end

function CommerceService:_CachePass(player: Player, passKey: string, owned: boolean)
	local userCache = self.passCache[player.UserId]
	if not userCache then
		userCache = {}
		self.passCache[player.UserId] = userCache
	end
	userCache[passKey] = { owned = owned, checkedAt = os.clock() }
end

function CommerceService:OwnsPass(player: Player, passKey: string, forceRefresh: boolean?): (boolean, boolean | string)
	local pass = Config.Passes[passKey]
	if not pass then
		return false, "UNKNOWN_GAME_PASS"
	end
	local userCache = self.passCache[player.UserId]
	local cached = userCache and userCache[passKey]
	if cached and (cached.owned or (not forceRefresh and os.clock() - cached.checkedAt < PASS_CACHE_SECONDS)) then
		return true, cached.owned
	end
	if pass.Id <= 0 then
		if RunService:IsStudio() and Config.Studio.AllowMockPurchases then
			return true, cached ~= nil and cached.owned == true
		end
		return false, "GAME_PASS_ID_NOT_CONFIGURED"
	end
	local success, owned = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
	end)
	if not success then
		warn(string.format("[CommerceService] Game pass lookup failed for %d: %s", player.UserId, tostring(owned)))
		return false, "GAME_PASS_LOOKUP_FAILED"
	end
	self:_CachePass(player, passKey, owned == true)
	return true, owned == true
end

function CommerceService:GetEntitlements(player: Player): { [string]: boolean }
	local success, owned = self:OwnsPass(player, "CustomImageUpload", false)
	return { customImageUpload = success and owned == true }
end

function CommerceService:PromptPass(player: Player, passKey: string): (boolean, any)
	local pass = Config.Passes[passKey]
	if not pass then
		return false, "UNKNOWN_GAME_PASS"
	end
	if not self.playerStates:Get(player).commerceAllowed then
		return false, "COMMERCE_NOT_ALLOWED"
	end
	local lookupSuccess, owned = self:OwnsPass(player, passKey, true)
	if lookupSuccess and owned == true then
		return true, { alreadyOwned = true }
	end
	if pass.Id <= 0 then
		if RunService:IsStudio() and Config.Studio.AllowMockPurchases then
			self:_CachePass(player, passKey, true)
			self.push(player, Network.PushEvents.Entitlements, self:GetEntitlements(player))
			return true, { mocked = true }
		end
		return false, "GAME_PASS_ID_NOT_CONFIGURED"
	end
	if not lookupSuccess and owned ~= "GAME_PASS_LOOKUP_FAILED" then
		return false, owned
	end
	local promptSuccess, problem = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	end)
	if not promptSuccess then
		warn(string.format("[CommerceService] Game pass prompt failed: %s", tostring(problem)))
		return false, "GAME_PASS_PROMPT_FAILED"
	end
	return true, { prompted = true }
end

function CommerceService:Remove(player: Player)
	self.passCache[player.UserId] = nil
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

-- Which pool a token-funded product draws from, and at what price, is a
-- direct consequence of what backs each pool:
--
-- profile.tokens is real-money-backed (a rewarded ad or a direct Robux
-- purchase of AdRewardTokens); profile.bonusTokens (achievements, daily
-- check-in, invites, group join) has no revenue behind it at all. A
-- completed rewarded ad measures at only ~0.12-0.44 Robux of real revenue —
-- see docs/PRICING.md "Forge Tokens" for the full derivation, including why
-- an earlier version of this system priced tokens against an ~8 Robux
-- assumption that was never true. Priority Pass has negligible variable
-- cost, so both pools may buy it, at the same friendly markup Robux
-- purchases get discounted against. Every generation product costs real
-- provider money per use regardless of who pays (as little as $0.006, as
-- much as $0.30), so it may draw ONLY from profile.tokens, and only at a
-- price steep enough that even the worst measured ad — 0.12 Robux — still
-- leaves Forge ahead: ceil(robuxPrice * markup / worstCaseAdRevenue) tokens,
-- which for the 159 Robux Direct Forge generation is 1590 tokens (with
-- TokenGrantPerAd at 1 token per ad, 1590 completed ad watches).
-- bonusTokens can never reach this branch: no free grant, no matter how
-- large, is allowed to fund a real-cost product.
local GENERATION_TOKEN_PRODUCTS = {
	DirectGeneration = true,
	ImagePreviewLow = true,
	ImagePreviewMedium = true,
	ImagePreviewHigh = true,
	ImageConversion = true,
	AvatarConversion = true,
}

local function tokenPriceFor(productKey: string, robuxPrice: number): number
	if GENERATION_TOKEN_PRODUCTS[productKey] then
		return math.ceil(robuxPrice * Config.Ads.TokenPurchaseMarkup / Config.Ads.WorstCaseAdRevenuePerAd)
	end
	return math.ceil(robuxPrice * Config.Ads.TokenPurchaseMarkup)
end

-- Pays for a product with Forge Tokens (earned by watching rewarded ads —
-- see AdRewardService — or granted for free, see ProfileService.
-- defaultProfile) instead of prompting a Robux purchase. Mirrors BeginIntent's
-- studio-mock-purchase shape: mutate first, call the same registered grant
-- handler every Robux/receipt path uses, then only commit the side effect
-- once the mutation is durably saved.
function CommerceService:BeginIntentWithTokens(
	player: Player,
	productKey: string,
	payload: { [string]: any }
): (boolean, any)
	local usesGenerationPricing = GENERATION_TOKEN_PRODUCTS[productKey] == true
	if not usesGenerationPricing and productKey ~= "PriorityPass" then
		return false, "TOKENS_NOT_ACCEPTED"
	end
	local handler = self.handlers[productKey]
	if not handler then
		return false, "UNKNOWN_PRODUCT"
	end
	if not self.playerStates:Get(player).commerceAllowed then
		return false, "COMMERCE_NOT_ALLOWED"
	end
	local robuxPrice = self:GetPrices()[productKey]
	if type(robuxPrice) ~= "number" or robuxPrice <= 0 then
		return false, "UNKNOWN_PRODUCT"
	end
	local tokenPrice = tokenPriceFor(productKey, robuxPrice)
	local profile = self.profiles:Get(player)
	if not profile then
		return false, "PROFILE_UNAVAILABLE"
	end
	-- Generation products spend only the real-money-backed pool. Priority
	-- Pass is safe from either, so it spends the free pool first — saving
	-- ad-backed tokens for the one thing only they may buy.
	local fromBonus, fromTokens
	if usesGenerationPricing then
		if (profile.tokens or 0) < tokenPrice then
			return false, "INSUFFICIENT_AD_TOKENS"
		end
		fromBonus, fromTokens = 0, tokenPrice
	else
		local bonus = math.min(profile.bonusTokens or 0, tokenPrice)
		local remainder = tokenPrice - bonus
		if remainder > (profile.tokens or 0) then
			return false, "INSUFFICIENT_TOKENS"
		end
		fromBonus, fromTokens = bonus, remainder
	end

	local intentId = self.profiles:GenerateId("tokenpurchase")
	local mutateSuccess = self.profiles:Mutate(player, function(mutableProfile)
		mutableProfile.bonusTokens -= fromBonus
		mutableProfile.tokens -= fromTokens
	end)
	if not mutateSuccess then
		return false, "PROFILE_UNAVAILABLE"
	end
	local grantSuccess, postCommit = pcall(handler, player, payload, intentId)
	if not grantSuccess then
		warn(string.format("[CommerceService] Token-funded grant failed for %s: %s", productKey, tostring(postCommit)))
		self.profiles:Mutate(player, function(mutableProfile)
			mutableProfile.bonusTokens += fromBonus
			mutableProfile.tokens += fromTokens
		end)
		return false, "GRANT_FAILED"
	end
	if not self.profiles:Save(player) then
		return false, "SAVE_FAILED"
	end
	if type(postCommit) == "function" then
		task.spawn(postCommit)
	end
	self.analytics:Custom(player, "TokenPurchase", tokenPrice, { product = productKey })
	local savedProfile = self.profiles:Get(player)
	return true,
		{
			intentId = intentId,
			tokensSpent = tokenPrice,
			tokens = savedProfile.tokens,
			bonusTokens = savedProfile.bonusTokens,
		}
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
	-- Captured before this receipt's own processedReceipts entry is written
	-- below, so it reflects whether this is genuinely the player's first-ever
	-- completed Robux purchase in this experience, not just this product.
	local isFirstPurchase = next(profile.processedReceipts) == nil
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
		if isFirstPurchase then
			mutableProfile.bonusTokens = (mutableProfile.bonusTokens or 0) + Config.Commerce.FirstPurchaseBonusTokens
		end
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
	if isFirstPurchase then
		local updatedProfile = self.profiles:Get(player)
		if updatedProfile then
			self.push(player, Network.PushEvents.Profile, { bonusTokens = updatedProfile.bonusTokens })
			self.push(player, Network.PushEvents.Toast, {
				tone = "success",
				message = string.format(
					"Thanks for your first purchase! +%d bonus tokens on the house.",
					Config.Commerce.FirstPurchaseBonusTokens
				),
			})
		end
		self.analytics:Custom(player, "FirstPurchaseBonusGranted", Config.Commerce.FirstPurchaseBonusTokens, {
			productKey = productKey,
		})
	end
	self.analytics:Economy(player, tonumber(receiptInfo.CurrencySpent) or 0, productKey)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return CommerceService
