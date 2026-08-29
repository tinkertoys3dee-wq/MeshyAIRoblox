--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatorProgression = require(ReplicatedStorage:WaitForChild("CreatorProgression"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local ProgressionService = {}
ProgressionService.__index = ProgressionService

function ProgressionService.new(profileService: any, push: (Player, string, any) -> (), analyticsService: any)
	return setmetatable({
		profiles = profileService,
		push = push,
		analytics = analyticsService,
	}, ProgressionService)
end

function ProgressionService:GetSnapshot(player: Player): { [string]: any }
	local profile = self.profiles:Get(player)
	local creator = profile and profile.creator or { xp = 0, level = 1 }
	local snapshot = CreatorProgression.Snapshot(creator.xp or 0)
	snapshot.runwayEntries = creator.runwayEntries or 0
	snapshot.runwayWins = creator.runwayWins or 0
	snapshot.runwayVotes = creator.runwayVotes or 0
	return snapshot
end

function ProgressionService:_Push(player: Player)
	local profile = self.profiles:Get(player)
	if not profile or player.Parent ~= Players then
		return
	end
	self.push(player, Network.PushEvents.CreatorProgress, {
		creator = profile.creator,
		progress = self:GetSnapshot(player),
	})
end

function ProgressionService:Grant(player: Player, amount: number, reason: string, persist: boolean?): { [string]: any }?
	local safeAmount = math.clamp(math.floor(amount), 0, 10000)
	if safeAmount <= 0 then
		return self:GetSnapshot(player)
	end
	local priorLevel = 1
	local newLevel = 1
	local priorTitle = CreatorProgression.TitleForLevel(1)
	local success = self.profiles:Mutate(player, function(profile)
		priorLevel = CreatorProgression.LevelFromXP(profile.creator.xp or 0)
		priorTitle = CreatorProgression.TitleForLevel(priorLevel)
		profile.creator.xp = math.max(0, math.floor(profile.creator.xp or 0)) + safeAmount
		newLevel = CreatorProgression.LevelFromXP(profile.creator.xp)
		profile.creator.level = newLevel
	end)
	if not success then
		return nil
	end
	-- XP is durable by default. High-level operations that already make one
	-- guaranteed save after this call (the runway result path) can opt out to
	-- avoid a burst of redundant DataStore writes.
	if persist ~= false and not self.profiles:Save(player) then
		return nil
	end
	self.analytics:Custom(player, "CreatorXPGranted", safeAmount, {
		reason = string.sub(reason, 1, 32),
		level = newLevel,
	})
	self:_Push(player)
	if newLevel > priorLevel then
		local title = CreatorProgression.TitleForLevel(newLevel)
		self.push(player, Network.PushEvents.Toast, {
			tone = "success",
			message = if title ~= priorTitle
				then string.format("Creator Level %d: %s unlocked", newLevel, title)
				else string.format("Creator Level %d reached", newLevel),
		})
		self.analytics:Custom(player, "CreatorLevelReached", newLevel, { title = title })
	end
	return self:GetSnapshot(player)
end

function ProgressionService:GrantWeekly(userId: number, amount: number, week: number, rank: number): boolean
	local safeAmount = math.clamp(math.floor(amount), 0, 10000)
	local newlyGranted = false
	local granted = self.profiles:MutateUser(userId, function(profile)
		if (profile.runway.weeklyPaidWeek or 0) >= week then
			return
		end
		profile.runway.weeklyPaidWeek = week
		profile.creator.xp = math.max(0, math.floor(profile.creator.xp or 0)) + safeAmount
		profile.creator.level = CreatorProgression.LevelFromXP(profile.creator.xp)
		profile.runway.weeklyPlacements = (profile.runway.weeklyPlacements or 0) + 1
		profile.runway.weeklyReward = {
			week = week,
			rank = rank,
			xp = safeAmount,
			announced = false,
		}
		newlyGranted = true
	end)
	if not granted then
		return false
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		-- MutateUser uses the in-memory profile for an online player. Persist
		-- before the cross-server payout marker advances so a server shutdown
		-- cannot lose a reward that the weekly job considers finished.
		if not self.profiles:Save(player) then
			return false
		end
		if newlyGranted then
			self:_Push(player)
			self:AnnouncePending(player)
		end
	end
	return true
end

function ProgressionService:AnnouncePending(player: Player)
	local profile = self.profiles:Get(player)
	local reward = profile and profile.runway and profile.runway.weeklyReward
	if not reward or reward.week <= 0 or reward.announced == true then
		return
	end
	local snapshot = {
		week = reward.week,
		rank = reward.rank,
		xp = reward.xp,
	}
	self.profiles:Mutate(player, function(current)
		current.runway.weeklyReward.announced = true
	end)
	self.push(player, Network.PushEvents.Toast, {
		tone = "success",
		message = string.format("Weekly Runway #%d: +%d Creator XP", snapshot.rank, snapshot.xp),
	})
	self.analytics:Custom(player, "RunwayWeeklyRewardClaimed", snapshot.xp, {
		rank = snapshot.rank,
		week = snapshot.week,
	})
end

return ProgressionService
