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
	analyticsService: any,
	achievementService: any
)
	local self = setmetatable({
		profiles = profileService,
		playerStates = playerStateService,
		commerce = commerceService,
		push = push,
		analytics = analyticsService,
		achievements = achievementService,
	}, AdRewardService)

	local function registerTokenGrant(productKey: string, amount: number, analyticsEvent: string)
		commerceService:Register(productKey, function(player: Player, _payload: any, intentId: string)
			local granted = false
			local mutateSuccess = self.profiles:Mutate(player, function(profile)
				if not profile.grantedIntents[intentId] then
					profile.grantedIntents[intentId] = {
						kind = "FORGE_TOKENS",
						productKey = productKey,
						amount = amount,
						grantedAt = os.time(),
					}
					profile.tokens = (profile.tokens or 0) + amount
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
					message = string.format("+%d Forge Token%s", amount, if amount == 1 then "" else "s"),
				})
				self.analytics:Custom(player, analyticsEvent, amount, { product = productKey })
			end
		end)
	end

	-- Rewarded ads stay 1:1 as requested. The 70-token Robux offer is a
	-- separate product so an ad-wrapped developer product does not silently
	-- change its benefit depending on where its receipt came from.
	registerTokenGrant("AdRewardTokens", Config.Ads.TokenGrantPerAd, "AdRewardGranted")
	registerTokenGrant("TokenPack70", Config.Ads.TokenPackGrant, "TokenPackGranted")

	return self
end

-- Returns how many rewarded ads this player has watched today, without
-- mutating anything -- purely a "nice, you've watched N today" stat for the
-- client. No cap backs this: every completed ad is real, positive ad
-- revenue for Forge (see Config.Ads.WorstCaseAdRevenuePerAd), so there is no
-- financial reason to ever stop a player from watching more.
function AdRewardService:WatchesToday(player: Player): number
	local profile = self.profiles:Get(player)
	if not profile then
		return 0
	end
	local watch = profile.adWatch or { day = 0, count = 0 }
	return if watch.day == currentDay() then watch.count else 0
end

function AdRewardService:RequestAd(player: Player): (boolean, any)
	if not self.playerStates:Get(player).commerceAllowed then
		return false, "COMMERCE_NOT_ALLOWED"
	end
	local product = Config.Products.AdRewardTokens
	if type(product.Id) ~= "number" or product.Id <= 0 then
		return false, "PRODUCT_ID_NOT_CONFIGURED"
	end
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
	if showResult == Enum.ShowAdResult.AdNotReady then
		-- Distinct from a genuinely interrupted/closed-early watch: this
		-- means Roblox had no ad ready to show at all, most often right
		-- after a previous watch used up the available inventory. Reusing
		-- AD_UNAVAILABLE here (the same code CreateAdRewardFromDevProductId
		-- failing above already returns) gives the player an accurate
		-- reason instead of the misleading "closed before it finished".
		return false, "AD_UNAVAILABLE"
	end
	if showResult ~= Enum.ShowAdResult.ShowCompleted then
		-- Roblox's own guidance: don't grant off this result, only use it for
		-- user-facing failure messaging. AdAlreadyShowing/ShowInterrupted/
		-- InternalError/InsufficientMemory all land here.
		return false, "AD_NOT_COMPLETED"
	end
	-- Unlocked here rather than in the shared AdRewardTokens grant handler:
	-- that handler also fires for a plain Robux purchase of the same
	-- product, which shouldn't count as "watched an ad". ShowCompleted is
	-- specific to this path.
	self.achievements:Unlock(player, "FIRST_AD_WATCHED")
	local today = currentDay()
	-- Count completed playback, not button presses or unavailable/interrupted
	-- attempts. This remains a display stat only and never gates another ad.
	local mutateSuccess = self.profiles:Mutate(player, function(profile)
		local watch = profile.adWatch or { day = 0, count = 0 }
		local count = if watch.day == today then watch.count else 0
		profile.adWatch = { day = today, count = count + 1 }
	end)
	if mutateSuccess then
		self.profiles:Save(player)
	else
		-- The player already completed the ad, and Roblox will still deliver
		-- its developer-product receipt. A temporary profile/display-counter
		-- failure must not turn that successful watch into a false error or
		-- encourage the player to watch again before the receipt arrives.
		warn(string.format("[AdRewardService] Could not update ad-watch display count for %d", player.UserId))
	end

	-- The actual token grant is asynchronous: Roblox fires the same
	-- MarketplaceService.ProcessReceipt callback CommerceService already
	-- installs once the player finishes watching, exactly like a paid
	-- developer product purchase (receipt.ProductPurchaseChannel is
	-- Enum.ProductPurchaseChannel.AdReward for these). ShowCompleted here only
	-- confirms playback finished, not that the grant has landed yet.
	return true, { watchesToday = self:WatchesToday(player) }
end

return AdRewardService
