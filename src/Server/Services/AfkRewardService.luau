--!strict

-- Server-authoritative rewards for the opt-in AFK Token Lounge. The client
-- can ask to enter or leave, but never supplies elapsed time or a reward
-- amount. Free lounge earnings use bonusTokens, keeping them useful for
-- Priority Passes without exposing paid OpenAI/Meshy generation spend.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

type Session = {
	startedAt: number,
	nextRewardAt: number,
	earned: number,
}

local AfkRewardService = {}
AfkRewardService.__index = AfkRewardService

local function currentDay(): number
	return math.floor(os.time() / 86400)
end

function AfkRewardService.new(profileService: any, push: (Player, string, any) -> (), analyticsService: any)
	return setmetatable({
		profiles = profileService,
		push = push,
		analytics = analyticsService,
		sessions = {} :: { [Player]: Session },
	}, AfkRewardService)
end

function AfkRewardService:_Snapshot(player: Player, session: Session): { [string]: any }
	local profile = self.profiles:Get(player)
	local afk = profile and profile.afk or { day = currentDay(), earned = 0 }
	local earnedToday = if afk.day == currentDay() then afk.earned else 0
	return {
		active = self.sessions[player] == session,
		sessionEarned = session.earned,
		dailyEarned = earnedToday,
		dailyCap = Config.AFK.DailyTokenCap,
		intervalSeconds = Config.AFK.IntervalSeconds,
		nextRewardAt = session.nextRewardAt,
		tokens = if profile then profile.tokens else 0,
		bonusTokens = if profile then profile.bonusTokens else 0,
	}
end

function AfkRewardService:_Run(player: Player, session: Session)
	task.spawn(function()
		while self.sessions[player] == session and player.Parent do
			task.wait(1)
			if self.sessions[player] ~= session or player.Parent == nil then
				break
			end
			local now = os.time()
			if now < session.nextRewardAt then
				continue
			end

			local elapsedIntervals = math.floor((now - session.nextRewardAt) / Config.AFK.IntervalSeconds) + 1
			session.nextRewardAt += elapsedIntervals * Config.AFK.IntervalSeconds
			local granted = 0
			local mutateSuccess = self.profiles:Mutate(player, function(profile)
				local day = currentDay()
				if profile.afk.day ~= day then
					profile.afk = { day = day, earned = 0 }
				end
				local remaining = math.max(0, Config.AFK.DailyTokenCap - profile.afk.earned)
				granted = math.min(remaining, elapsedIntervals * Config.AFK.TokensPerInterval)
				if granted > 0 then
					profile.afk.earned += granted
					profile.bonusTokens = (profile.bonusTokens or 0) + granted
				end
			end)
			if not mutateSuccess or granted <= 0 then
				continue
			end

			session.earned += granted
			self.profiles:Save(player)
			local snapshot = self:_Snapshot(player, session)
			self.push(player, Network.PushEvents.Profile, {
				bonusTokens = snapshot.bonusTokens,
				afk = {
					day = currentDay(),
					earned = snapshot.dailyEarned,
				},
			})
			self.push(player, Network.PushEvents.Afk, snapshot)
			self.analytics:Custom(player, "AfkTokensGranted", granted, {
				dailyEarned = snapshot.dailyEarned,
				sessionEarned = session.earned,
			})
		end
	end)
end

function AfkRewardService:Enter(player: Player): (boolean, any)
	local profile = self.profiles:Get(player)
	if not profile then
		return false, "PROFILE_UNAVAILABLE"
	end
	local existing = self.sessions[player]
	if existing then
		return true, self:_Snapshot(player, existing)
	end

	local resetDaily = false
	local mutateSuccess = self.profiles:Mutate(player, function(mutableProfile)
		local day = currentDay()
		if mutableProfile.afk.day ~= day then
			mutableProfile.afk = { day = day, earned = 0 }
			resetDaily = true
		end
	end)
	if not mutateSuccess then
		return false, "PROFILE_UNAVAILABLE"
	end
	if resetDaily then
		self.profiles:Save(player)
	end

	local session = {
		startedAt = os.time(),
		nextRewardAt = os.time() + Config.AFK.IntervalSeconds,
		earned = 0,
	}
	self.sessions[player] = session
	self.analytics:Custom(player, "AfkLoungeEntered", 1, {})
	self:_Run(player, session)
	return true, self:_Snapshot(player, session)
end

function AfkRewardService:Leave(player: Player): (boolean, any)
	local session = self.sessions[player]
	if not session then
		return true, { active = false, sessionEarned = 0 }
	end
	self.sessions[player] = nil
	self.analytics:Custom(player, "AfkLoungeLeft", math.max(0, os.time() - session.startedAt), {
		sessionEarned = session.earned,
	})
	local snapshot = self:_Snapshot(player, session)
	snapshot.active = false
	return true, snapshot
end

function AfkRewardService:Remove(player: Player)
	self.sessions[player] = nil
end

return AfkRewardService
