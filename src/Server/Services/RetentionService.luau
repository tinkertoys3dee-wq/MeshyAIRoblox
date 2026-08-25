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
	local winBackTokensGranted = 0
	local daysAway = 0
	self.profiles:Mutate(player, function(profile)
		if profile.daily.lastDay ~= day then
			changed = true
			-- lastDay == 0 means this player has never checked in before
			-- (ProfileService.defaultProfile's default) -- a brand new
			-- player is not "returning", so daysAway only gets computed once
			-- there is a real previous visit to measure the gap against.
			if profile.daily.lastDay > 0 then
				daysAway = day - profile.daily.lastDay
			end
			if profile.daily.lastDay == day - 1 then
				profile.daily.streak += 1
			else
				profile.daily.streak = 1
			end
			profile.daily.lastDay = day
			profile.daily.best = math.max(profile.daily.best, profile.daily.streak)
			tokensGranted = Config.Retention.DailyCheckInTokens
			-- bonusTokens, not tokens: this reward has no ad revenue or Robux
			-- payment behind it, so it may only ever buy the Priority Pass —
			-- see the matching comment on ProfileService.defaultProfile.
			profile.bonusTokens = (profile.bonusTokens or 0) + tokensGranted
			if profile.daily.streak % 3 == 0 then
				profile.retryCredits.PriorityPass = (profile.retryCredits.PriorityPass or 0) + 1
				rewardGranted = true
			end
			-- A gap resets the streak either way, but a player who was
			-- genuinely at risk of not returning (not just someone who
			-- missed yesterday) gets an extra, distinctly-messaged welcome
			-- on top of the normal daily reward above.
			if daysAway >= Config.Retention.WinBackGapDays then
				winBackTokensGranted = Config.Retention.WinBackBonusTokens
				profile.bonusTokens = (profile.bonusTokens or 0) + winBackTokensGranted
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
		winBackTokensGranted = winBackTokensGranted,
		daysAway = daysAway,
	})
	self.achievements:CheckCount(player, "STREAK_SEVEN", profile.daily.streak, 7)
	local brief = {
		streak = profile.daily.streak,
		best = profile.daily.best,
		rewardGranted = rewardGranted,
		tokensGranted = tokensGranted,
		winBackTokensGranted = winBackTokensGranted,
		daysAway = daysAway,
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
