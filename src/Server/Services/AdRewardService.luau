--!strict

-- Forge Tokens are a Robux alternative earned by watching a Roblox
-- Rewarded Video ad. See docs/PRICING.md for the economics and
-- docs/ARCHITECTURE.md for how this ties into CommerceService's existing
-- developer-product receipt pipeline.
--
-- Roblox's AdService splits this across two contexts (verified against
-- Roblox's own class reference, not guessed): AdService:GetAdAvailabilityNowAsync
-- may only be called from a Client-context script, while
-- AdService:CreateAdRewardFromDevProductId and AdService:ShowRewardedVideoAdAsync
-- may only be called from a Server-context script. The client therefore checks
-- availability itself before ever asking the server to show an ad; this
-- service does the privileged, server-only half. Confirm this split still
-- holds during live Studio/device testing before enabling the real product ID.

local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local AdRewardService = {}
AdRewardService.__index = AdRewardService

local function currentDay(): number
	return math.floor(os.time() / 86400)
end

function AdRewardService.new(
	profileService: any,
	playerStateService: any,
	commerceService: any,
	push: (Player, string, any) -> (),
	analyticsService: any
)
	local self = setmetatable({
		profiles = profileService,
		playerStates = playerStateService,
		commerce = commerceService,
		push = push,
		analytics = analyticsService,
	}, AdRewardService)

	-- Roblox requires the ad reward to be a developer product that is also
	-- normally purchasable with Robux; buying it directly and completing a
	-- rewarded ad for it must grant the identical benefit, so both paths are
	-- registered through this one handler.
	commerceService:Register("AdRewardTokens", function(player: Player, _payload: any, intentId: string)
		local granted = false
		local mutateSuccess = self.profiles:Mutate(player, function(profile)
			if not profile.grantedIntents[intentId] then
				profile.grantedIntents[intentId] = { kind = "AD_REWARD_TOKENS", grantedAt = os.time() }
				profile.tokens = (profile.tokens or 0) + Config.Ads.TokenGrantPerPurchase
				granted = true
			end
		end)
		if not mutateSuccess then
			error("PROFILE_MUTATION_FAILED")
		end
		if not granted then
			return nil
		end
		return function()
			local profile = self.profiles:Get(player)
			if not profile or player.Parent == nil then
				return
			end
			self.push(player, Network.PushEvents.Profile, { tokens = profile.tokens })
			self.push(player, Network.PushEvents.Toast, {
				tone = "success",
				message = string.format("+%d Forge Tokens", Config.Ads.TokenGrantPerPurchase),
			})
			self.analytics:Custom(player, "AdRewardGranted", Config.Ads.TokenGrantPerPurchase, {})
		end
	end)

	return self
end

-- Returns how many rewarded-ad requests this player has left today without
-- mutating anything, for the client to show ("14/20 today") and to disable
-- the button once exhausted.
function AdRewardService:WatchesRemainingToday(player: Player): number
	local profile = self.profiles:Get(player)
	if not profile then
		return 0
	end
	local watch = profile.adWatch or { day = 0, count = 0 }
	local count = if watch.day == currentDay() then watch.count else 0
	return math.max(0, Config.Ads.MaxAdWatchesPerDay - count)
end

function AdRewardService:RequestAd(player: Player): (boolean, any)
	if not self.playerStates:Get(player).commerceAllowed then
		return false, "COMMERCE_NOT_ALLOWED"
	end
	local product = Config.Products.AdRewardTokens
	if type(product.Id) ~= "number" or product.Id <= 0 then
		return false, "PRODUCT_ID_NOT_CONFIGURED"
	end
	local today = currentDay()
	local mutateSuccess, limitReached = pcall(function()
		local reached = false
		local ok = self.profiles:Mutate(player, function(profile)
			local watch = profile.adWatch or { day = 0, count = 0 }
			local count = if watch.day == today then watch.count else 0
			if count >= Config.Ads.MaxAdWatchesPerDay then
				reached = true
				return
			end
			profile.adWatch = { day = today, count = count + 1 }
		end)
		if not ok then
			error("PROFILE_MUTATION_FAILED")
		end
		return reached
	end)
	if not mutateSuccess then
		return false, "PROFILE_UNAVAILABLE"
	end
	if limitReached then
		return false, "AD_WATCH_LIMIT_REACHED"
	end
	self.profiles:Save(player)

	local rewardSuccess, rewardOrProblem = pcall(function()
		return AdService:CreateAdRewardFromDevProductId(product.Id)
	end)
	if not rewardSuccess then
		warn(string.format("[AdRewardService] Could not create ad reward: %s", tostring(rewardOrProblem)))
		return false, "AD_UNAVAILABLE"
	end

	local showSuccess, showResult = pcall(function()
		return AdService:ShowRewardedVideoAdAsync(player, rewardOrProblem)
	end)
	if not showSuccess then
		warn(string.format("[AdRewardService] Could not show rewarded ad: %s", tostring(showResult)))
		return false, "AD_UNAVAILABLE"
	end
	if showResult ~= Enum.ShowAdResult.ShowCompleted then
		-- Roblox's own guidance: don't grant off this result, only use it for
		-- user-facing failure messaging. AdNotReady/AdAlreadyShowing/
		-- ShowInterrupted/InternalError/InsufficientMemory all land here.
		return false, "AD_NOT_COMPLETED"
	end

	-- The actual token grant is asynchronous: Roblox fires the same
	-- MarketplaceService.ProcessReceipt callback CommerceService already
	-- installs once the player finishes watching, exactly like a paid
	-- developer product purchase (receipt.ProductPurchaseChannel is
	-- Enum.ProductPurchaseChannel.AdReward for these). ShowCompleted here only
	-- confirms playback finished, not that the grant has landed yet.
	return true, { watchesRemainingToday = self:WatchesRemainingToday(player) }
end

return AdRewardService
