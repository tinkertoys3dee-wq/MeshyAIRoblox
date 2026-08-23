--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local THEMES = {
	"Celestial streetwear",
	"Bio-luminescent garden",
	"Retro arcade relic",
	"Soft cloud fantasy",
	"Deep-sea explorer",
	"Prismatic festival",
	"Ancient tech artifact",
}

local RetentionService = {}
RetentionService.__index = RetentionService

function RetentionService.new(profileService: any, analyticsService: any, achievementService: any)
	return setmetatable({
		profiles = profileService,
		analytics = analyticsService,
		achievements = achievementService,
		briefs = {} :: { [Player]: { [string]: any } },
	}, RetentionService)
end

function RetentionService:CheckIn(player: Player): { [string]: any }
	local day = math.floor(os.time() / 86400)
	local rewardGranted = false
	local changed = false
	local tokensGranted = 0
	self.profiles:Mutate(player, function(profile)
		if profile.daily.lastDay ~= day then
			changed = true
			if profile.daily.lastDay == day - 1 then
				profile.daily.streak += 1
			else
				profile.daily.streak = 1
			end
			profile.daily.lastDay = day
			profile.daily.best = math.max(profile.daily.best, profile.daily.streak)
			tokensGranted = Config.Retention.DailyCheckInTokens
			profile.tokens = (profile.tokens or 0) + tokensGranted
			if profile.daily.streak % 3 == 0 then
				profile.retryCredits.PriorityPass = (profile.retryCredits.PriorityPass or 0) + 1
				rewardGranted = true
			end
		end
	end)
	if changed then
		self.profiles:Save(player)
	end
	local profile = self.profiles:Get(player)
	self.analytics:Custom(player, "DailyStudioCheckIn", profile.daily.streak, {
		reward = rewardGranted,
		tokensGranted = tokensGranted,
	})
	self.achievements:CheckCount(player, "STREAK_SEVEN", profile.daily.streak, 7)
	local brief = {
		streak = profile.daily.streak,
		best = profile.daily.best,
		rewardGranted = rewardGranted,
		tokensGranted = tokensGranted,
		theme = THEMES[(day % #THEMES) + 1],
		nextRewardIn = 3 - (profile.daily.streak % 3),
	}
	self.briefs[player] = brief
	return brief
end

function RetentionService:GetBrief(player: Player): { [string]: any }
	if self.briefs[player] then
		return self.briefs[player]
	end
	local day = math.floor(os.time() / 86400)
	local profile = self.profiles:Get(player)
	return {
		streak = profile.daily.streak,
		best = profile.daily.best,
		theme = THEMES[(day % #THEMES) + 1],
		nextRewardIn = 3 - (profile.daily.streak % 3),
	}
end

function RetentionService:Remove(player: Player)
	self.briefs[player] = nil
end

return RetentionService
