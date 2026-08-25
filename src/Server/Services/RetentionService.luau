--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local THEMES = {
	"Celestial streetwear",
	"Bio-luminescent garden",
	"Retro arcade relic",
	"Soft cloud fantasy",
	"Deep-sea explorer",
	"Prismatic festival",
	"Ancient tech artifact",
}

-- The next streak day (7, 14, 30, then every StreakMilestoneRepeatDay after
-- that) that a check-in will trigger a StreakMilestones bonus -- shared by
-- CheckIn's brief and GetBrief so the streak-calendar UI can always show how
-- far away the next milestone is, not just whether one just fired.
local function nextMilestoneDay(streak: number): number
	if streak < 7 then
		return 7
	elseif streak < 14 then
		return 14
	elseif streak < 30 then
		return 30
	end
	local repeatDay = Config.Retention.StreakMilestoneRepeatDay
	return (math.floor(streak / repeatDay) + 1) * repeatDay
end

local QUEST_BY_KEY = {} :: { [string]: { key: string, label: string, icon: string, tokens: number } }
for _, quest in Config.Retention.Quests do
	QUEST_BY_KEY[quest.key] = quest
end

local RetentionService = {}
RetentionService.__index = RetentionService

function RetentionService.new(
	profileService: any,
	analyticsService: any,
	achievementService: any,
	push: (Player, string, any) -> ()
)
	return setmetatable({
		profiles = profileService,
		analytics = analyticsService,
		achievements = achievementService,
		push = push,
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
	local milestoneReward = nil :: { day: number, tokens: number, priorityPasses: number }?
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
			local milestone = Config.Retention.StreakMilestones[profile.daily.streak]
			if
				not milestone
				and profile.daily.streak > Config.Retention.StreakMilestoneRepeatDay
				and profile.daily.streak % Config.Retention.StreakMilestoneRepeatDay == 0
			then
				milestone = Config.Retention.StreakMilestones[Config.Retention.StreakMilestoneRepeatDay]
			end
			if milestone then
				profile.bonusTokens = (profile.bonusTokens or 0) + milestone.tokens
				profile.retryCredits.PriorityPass = (profile.retryCredits.PriorityPass or 0) + milestone.priorityPasses
				milestoneReward =
					{ day = profile.daily.streak, tokens = milestone.tokens, priorityPasses = milestone.priorityPasses }
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
		milestoneDay = if milestoneReward then milestoneReward.day else nil,
	})
	if milestoneReward then
		self.analytics:Custom(player, "StreakMilestoneReached", milestoneReward.day, {
			tokens = milestoneReward.tokens,
			priorityPasses = milestoneReward.priorityPasses,
		})
	end
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
		milestoneReward = milestoneReward,
		nextMilestoneDay = nextMilestoneDay(profile.daily.streak),
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
		nextMilestoneDay = nextMilestoneDay(profile.daily.streak),
	}
end

-- `profile.daily.questsDone` belongs to whatever UTC day `questsDay`
-- records -- once that's stale (a new day started since the player last
-- completed one), the map reads as empty without needing an explicit reset
-- write of its own (MarkQuest performs the real reset, the first time it's
-- actually needed).
local function questsDoneForToday(profile: { [string]: any }, day: number): { [string]: boolean }
	if profile.daily.questsDay == day then
		return profile.daily.questsDone
	end
	return {}
end

-- Marks `questKey` complete for today, the first time this is called for it
-- -- every later call the same day is a harmless no-op (mirrors
-- AchievementService:Unlock's own "call sites never need their own check"
-- contract). Call sites are the server's own verified success branches for
-- each underlying action (a generation queued, a fit saved, a score
-- submitted), never something the client can trigger by itself.
function RetentionService:MarkQuest(player: Player, questKey: string)
	local quest = QUEST_BY_KEY[questKey]
	if not quest then
		warn(string.format("[RetentionService] Unknown quest key: %s", tostring(questKey)))
		return
	end
	local day = math.floor(os.time() / 86400)
	local justCompleted = false
	local clearBonusGranted = 0
	local mutateSuccess = self.profiles:Mutate(player, function(profile)
		if profile.daily.questsDay ~= day then
			profile.daily.questsDay = day
			profile.daily.questsDone = {}
		end
		if profile.daily.questsDone[questKey] then
			return
		end
		profile.daily.questsDone[questKey] = true
		profile.bonusTokens = (profile.bonusTokens or 0) + quest.tokens
		justCompleted = true
		local allDone = true
		for _, definition in Config.Retention.Quests do
			if not profile.daily.questsDone[definition.key] then
				allDone = false
				break
			end
		end
		if allDone then
			clearBonusGranted = Config.Retention.QuestClearBonusTokens
			profile.bonusTokens = (profile.bonusTokens or 0) + clearBonusGranted
		end
	end)
	if not mutateSuccess or not justCompleted then
		return
	end
	self.profiles:Save(player)
	local profile = self.profiles:Get(player)
	if not profile or player.Parent == nil then
		return
	end
	self.analytics:Custom(player, "DailyQuestCompleted", quest.tokens, {
		quest = questKey,
		clearBonus = clearBonusGranted > 0,
	})
	self.push(player, Network.PushEvents.Profile, { tokens = profile.tokens, bonusTokens = profile.bonusTokens })
	self.push(player, Network.PushEvents.Quests, {
		questsDone = questsDoneForToday(profile, day),
		justCompleted = questKey,
		clearBonusGranted = clearBonusGranted,
	})
	local message = if clearBonusGranted > 0
		then string.format(
			"Quest cleared: %s (+%d) · All 3 done today! +%d bonus",
			quest.label,
			quest.tokens,
			clearBonusGranted
		)
		else string.format("Quest cleared: %s (+%d tokens)", quest.label, quest.tokens)
	self.push(player, Network.PushEvents.Toast, { tone = "success", message = message })
end

function RetentionService:GetQuestState(player: Player): { [string]: any }
	local day = math.floor(os.time() / 86400)
	local profile = self.profiles:Get(player)
	if not profile then
		return { questsDone = {} }
	end
	return { questsDone = questsDoneForToday(profile, day) }
end

function RetentionService:Remove(player: Player)
	self.briefs[player] = nil
end

return RetentionService
