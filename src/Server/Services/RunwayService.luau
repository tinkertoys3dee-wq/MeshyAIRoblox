--!strict

-- Server-synchronized social style rounds. The service never creates or
-- edits Workspace instances: it observes the avatars players already wear
-- and publishes round state for the client UI. This preserves the owner's
-- map and global Lighting while still giving every server a shared loop.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local RunwayService = {}
RunwayService.__index = RunwayService

local WEEK_SECONDS = 7 * 24 * 60 * 60
local SCORE_STORE_PREFIX = "FUGC_Runway_wk"
local PAYOUT_CHECK_INTERVAL_SECONDS = 30 * 60

local function currentWeek(): number
	return math.floor(os.time() / WEEK_SECONDS)
end

local function scoreStore(week: number): OrderedDataStore
	return DataStoreService:GetOrderedDataStore(SCORE_STORE_PREFIX .. tostring(week))
end

function RunwayService.new(
	profileService: any,
	push: (Player, string, any) -> (),
	analyticsService: any,
	retentionService: any,
	progressionService: any
)
	local self = setmetatable({
		profiles = profileService,
		push = push,
		analytics = analyticsService,
		retention = retentionService,
		progression = progressionService,
		metaStore = DataStoreService:GetDataStore(Config.DataStores.RunwayMeta),
		phase = "INTERMISSION",
		roundId = "",
		theme = "",
		endsAt = 0,
		entries = {} :: { [number]: { [string]: any } },
		votesBy = {} :: { [number]: number },
		results = {} :: { { [string]: any } },
		nameCache = {} :: { [number]: string },
		closing = false,
	}, RunwayService)

	self:_StartIntermission()
	task.spawn(function()
		while not self.closing do
			task.wait(1)
			if os.time() >= self.endsAt then
				self:_AdvancePhase()
			end
		end
	end)
	task.spawn(function()
		self:_CheckWeeklyPayout()
		while not self.closing do
			task.wait(PAYOUT_CHECK_INTERVAL_SECONDS)
			self:_CheckWeeklyPayout()
		end
	end)
	return self
end

function RunwayService:_NameFor(userId: number): string
	local cached = self.nameCache[userId]
	if cached then
		return cached
	end
	local success, name = pcall(function()
		local player = Players:GetPlayerByUserId(userId)
		if player then
			return player.DisplayName
		end
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if success and type(name) == "string" and name ~= "" then name else "Player"
	self.nameCache[userId] = resolved
	return resolved
end

function RunwayService:_StartIntermission()
	local themes = Config.Runway.Themes
	local themeIndex = (math.floor(os.time() / 360) % #themes) + 1
	self.phase = "INTERMISSION"
	self.roundId = HttpService:GenerateGUID(false)
	self.theme = themes[themeIndex]
	self.endsAt = os.time() + Config.Runway.IntermissionSeconds
	self.entries = {}
	self.votesBy = {}
	self.results = {}
	self:_Broadcast()
end

function RunwayService:_StartStyling()
	self.phase = "STYLING"
	self.endsAt = os.time() + Config.Runway.StylingSeconds
	self:_Broadcast()
end

function RunwayService:_StartVoting()
	-- A disconnected avatar cannot be shown or voted on. Removing it here
	-- also prevents a player joining, locking a look, and immediately leaving
	-- to farm participation rewards later.
	for userId in self.entries do
		if not Players:GetPlayerByUserId(userId) then
			self.entries[userId] = nil
		end
	end
	local readyCount = 0
	for _, entry in self.entries do
		if entry.ready then
			readyCount += 1
		end
	end
	-- A solo server should still complete the player's journey and daily
	-- round, but there is nobody meaningful to vote for. Skip the empty
	-- 90-second ballot instead of making low-CCU players stare at a timer.
	if readyCount < Config.Runway.MinimumEntrantsForPlacement then
		self:_StartResults()
		return
	end
	self.phase = "VOTING"
	self.endsAt = os.time() + Config.Runway.VotingSeconds
	self:_Broadcast()
end

function RunwayService:_ReadyEntries(): { { [string]: any } }
	local ready = {}
	for _, entry in self.entries do
		if entry.ready == true then
			table.insert(ready, entry)
		end
	end
	table.sort(ready, function(a, b)
		if a.votes ~= b.votes then
			return a.votes > b.votes
		end
		-- Never reward rushing the styling phase. Equal vote totals use a
		-- server-authored per-round tie break instead of lock-in time.
		if a.tieBreak ~= b.tieBreak then
			return a.tieBreak < b.tieBreak
		end
		return a.userId < b.userId
	end)
	return ready
end

function RunwayService:_AddWeeklyPoints(userId: number, points: number)
	if points <= 0 then
		return
	end
	local week = currentWeek()
	task.spawn(function()
		local success, problem = pcall(function()
			scoreStore(week):IncrementAsync(tostring(userId), math.floor(points))
		end)
		if not success then
			warn(string.format("[RunwayService] Weekly score update failed for %d: %s", userId, tostring(problem)))
		end
	end)
end

function RunwayService:_FinishRound()
	local ready = self:_ReadyEntries()
	local totalVotes = 0
	for _, entry in ready do
		totalVotes += entry.votes
	end
	local placementValid = #ready >= Config.Runway.MinimumEntrantsForPlacement and totalVotes > 0
	self.results = {}

	for rank, entry in ready do
		local player = Players:GetPlayerByUserId(entry.userId)
		local placement = if placementValid and rank <= 3 then rank else nil
		local placementXP = if placement then Config.Runway.PlacementXP[placement] or 0 else 0
		local xp = Config.Runway.ParticipationXP + placementXP
		local dailyTokens = 0
		if player then
			local day = math.floor(os.time() / 86400)
			self.profiles:Mutate(player, function(profile)
				profile.creator.runwayEntries = (profile.creator.runwayEntries or 0) + 1
				if placement == 1 then
					profile.creator.runwayWins = (profile.creator.runwayWins or 0) + 1
				end
				if profile.runway.dailyDay ~= day then
					profile.runway.dailyDay = day
					profile.runway.dailyCompleted = false
				end
				if not profile.runway.dailyCompleted then
					profile.runway.dailyCompleted = true
					dailyTokens = Config.Runway.DailyFirstRoundBonusTokens
					profile.bonusTokens = (profile.bonusTokens or 0) + dailyTokens
				end
			end)
			self.progression:Grant(player, xp, if placement then "RUNWAY_PLACE" else "RUNWAY_COMPLETE", false)
			self.retention:MarkJourney(player, "COMPLETE_RUNWAY", false)
			self.retention:MarkQuest(player, "RUNWAY", false)
			-- All profile mutations above are synchronous and complete before a
			-- player can leave; persistence can run in parallel across entrants so
			-- a full server never stalls the synchronized results reveal.
			task.spawn(function()
				self.profiles:Save(player)
			end)
			local profile = self.profiles:Get(player)
			if dailyTokens > 0 and profile then
				self.push(player, Network.PushEvents.Profile, {
					bonusTokens = profile.bonusTokens,
					creator = profile.creator,
					runway = profile.runway,
				})
				self.push(player, Network.PushEvents.Toast, {
					tone = "success",
					message = string.format("Daily runway complete: +%d bonus tokens", dailyTokens),
				})
			end
			self.analytics:Funnel(player, "runway", 4, "Style round completed", {
				placement = placement or 0,
				votes = entry.votes,
			})
			self.analytics:Custom(player, "RunwayRoundCompleted", xp, {
				placement = placement or 0,
				votes = entry.votes,
				theme = self.theme,
			})
		end

		local weeklyPoints = 1
			+ entry.votes
			+ (if placement == 1 then 10 elseif placement == 2 then 6 elseif placement == 3 then 3 else 0)
		self:_AddWeeklyPoints(entry.userId, weeklyPoints)
		table.insert(self.results, {
			userId = entry.userId,
			name = entry.name,
			votes = entry.votes,
			placement = placement,
			xp = xp,
		})
	end
end

function RunwayService:_StartResults()
	self.phase = "RESULTS"
	self.endsAt = os.time() + Config.Runway.ResultsSeconds
	self:_FinishRound()
	self:_Broadcast()
end

function RunwayService:_AdvancePhase()
	if self.phase == "INTERMISSION" then
		self:_StartStyling()
	elseif self.phase == "STYLING" then
		self:_StartVoting()
	elseif self.phase == "VOTING" then
		self:_StartResults()
	else
		self:_StartIntermission()
	end
end

function RunwayService:GetState(player: Player): { [string]: any }
	local entries = {}
	for _, entry in self.entries do
		table.insert(entries, {
			userId = entry.userId,
			name = entry.name,
			ready = entry.ready == true,
			votes = if self.phase == "RESULTS" then entry.votes else nil,
		})
	end
	table.sort(entries, function(a, b)
		if a.ready ~= b.ready then
			return a.ready
		end
		return string.lower(a.name) < string.lower(b.name)
	end)
	local ownEntry = self.entries[player.UserId]
	return {
		roundId = self.roundId,
		phase = self.phase,
		theme = self.theme,
		endsAt = self.endsAt,
		serverTime = os.time(),
		entries = entries,
		results = self.results,
		joined = ownEntry ~= nil,
		ready = ownEntry ~= nil and ownEntry.ready == true,
		votedFor = self.votesBy[player.UserId],
		creatorProgress = self.progression:GetSnapshot(player),
		journeyState = self.retention:GetJourneyState(player),
	}
end

function RunwayService:_Broadcast()
	for _, player in Players:GetPlayers() do
		if self.profiles:Get(player) then
			self.push(player, Network.PushEvents.Runway, self:GetState(player))
		end
	end
end

function RunwayService:Join(player: Player): (boolean, any)
	if self.phase ~= "INTERMISSION" and self.phase ~= "STYLING" then
		return false, "RUNWAY_JOIN_CLOSED"
	end
	if self.entries[player.UserId] then
		return true, self:GetState(player)
	end
	self.entries[player.UserId] = {
		userId = player.UserId,
		name = player.DisplayName,
		joinedAt = os.time(),
		readyAt = 0,
		tieBreak = math.random(1, 1_000_000_000),
		ready = false,
		votes = 0,
	}
	self.analytics:BeginFunnel(player, "runway", "Runway entered", { phase = self.phase, theme = self.theme })
	self:_Broadcast()
	return true, self:GetState(player)
end

function RunwayService:Leave(player: Player): (boolean, any)
	if self.phase ~= "INTERMISSION" and self.phase ~= "STYLING" then
		return false, "RUNWAY_ROUND_ACTIVE"
	end
	self:Remove(player)
	return true, self:GetState(player)
end

function RunwayService:IsLookFrozen(player: Player): boolean
	local entry = self.entries[player.UserId]
	return entry ~= nil and entry.ready == true and (self.phase == "VOTING" or self.phase == "RESULTS")
end

function RunwayService:Ready(player: Player): (boolean, any)
	if self.phase ~= "STYLING" then
		return false, "RUNWAY_NOT_STYLING"
	end
	local entry = self.entries[player.UserId]
	if not entry then
		return false, "RUNWAY_NOT_JOINED"
	end
	if not entry.ready then
		entry.ready = true
		entry.readyAt = os.time()
		self.analytics:Funnel(player, "runway", 2, "Look locked in", { theme = self.theme })
		self.analytics:Custom(player, "RunwayLookLocked", 1, { theme = self.theme })
		self.retention:MarkJourney(player, "JOIN_RUNWAY")
	end
	self:_Broadcast()
	return true, self:GetState(player)
end

function RunwayService:Vote(player: Player, targetUserId: any): (boolean, any)
	if self.phase ~= "VOTING" then
		return false, "RUNWAY_NOT_VOTING"
	end
	local targetId = tonumber(targetUserId)
	if not targetId then
		return false, "INVALID_REQUEST"
	end
	targetId = math.floor(targetId)
	if targetId == player.UserId then
		return false, "RUNWAY_SELF_VOTE"
	end
	if self.votesBy[player.UserId] then
		return false, "RUNWAY_ALREADY_VOTED"
	end
	local entry = self.entries[targetId]
	if not entry or not entry.ready then
		return false, "RUNWAY_LOOK_UNAVAILABLE"
	end
	self.votesBy[player.UserId] = targetId
	entry.votes += 1
	self.profiles:Mutate(player, function(profile)
		profile.creator.runwayVotes = (profile.creator.runwayVotes or 0) + 1
	end)
	self.progression:Grant(player, Config.Runway.VoteXP, "RUNWAY_VOTE")
	self:_AddWeeklyPoints(player.UserId, 1)
	self.analytics:Funnel(player, "runway", 3, "Runway vote cast", { theme = self.theme })
	self.analytics:Custom(player, "RunwayVoteCast", 1, { theme = self.theme })
	-- Votes stay secret until RESULTS, so broadcasting every ballot would only
	-- rebuild every player's avatar viewport without revealing useful state.
	-- The invoking voter receives their updated `votedFor` in this response.
	return true, self:GetState(player)
end

function RunwayService:GetLeaderboard(player: Player): (boolean, any)
	local store = scoreStore(currentWeek())
	local success, pages = pcall(function()
		return store:GetSortedAsync(false, Config.Runway.LeaderboardSize)
	end)
	if not success then
		return true, { standings = {}, self = nil, week = currentWeek() }
	end
	local standings = {}
	local selfStanding = nil
	for rank, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId then
			local row = { rank = rank, userId = userId, name = self:_NameFor(userId), score = entry.value }
			table.insert(standings, row)
			if userId == player.UserId then
				selfStanding = row
			end
		end
	end
	if not selfStanding then
		local ownSuccess, ownScore = pcall(function()
			return store:GetAsync(tostring(player.UserId))
		end)
		if ownSuccess and type(ownScore) == "number" then
			selfStanding = { rank = nil, userId = player.UserId, name = player.DisplayName, score = ownScore }
		end
	end
	return true, { standings = standings, self = selfStanding, week = currentWeek() }
end

function RunwayService:_LastPayoutWeek(): number?
	local success, stored = pcall(function()
		return self.metaStore:GetAsync("lastPayoutWeek")
	end)
	if not success then
		return nil
	end
	return if type(stored) == "number" then stored else 0
end

function RunwayService:_MarkPayoutWeek(week: number): boolean
	return pcall(function()
		self.metaStore:UpdateAsync("lastPayoutWeek", function(stored)
			local storedWeek = if type(stored) == "number" then stored else 0
			return math.max(storedWeek, week)
		end)
	end)
end

function RunwayService:_ProcessWeek(week: number): boolean
	local success, pages = pcall(function()
		return scoreStore(week):GetSortedAsync(false, 3)
	end)
	if not success then
		warn(string.format("[RunwayService] Could not read standings for week %d", week))
		return false
	end
	local allGranted = true
	for rank, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		local reward = Config.Runway.WeeklyPlacementXP[rank]
		if userId and reward and not self.progression:GrantWeekly(userId, reward, week, rank) then
			allGranted = false
		end
	end
	return allGranted
end

function RunwayService:_CheckWeeklyPayout()
	local finishedWeek = currentWeek() - 1
	local lastPayoutWeek = self:_LastPayoutWeek()
	if finishedWeek < 0 or lastPayoutWeek == nil or lastPayoutWeek >= finishedWeek then
		return
	end
	-- Rewards are idempotent per profile (`weeklyPaidWeek`), so two servers
	-- may safely overlap here. The global marker advances only after every
	-- winner mutation succeeds; a partial outage is retried on the next pass.
	if self:_ProcessWeek(finishedWeek) and not self:_MarkPayoutWeek(finishedWeek) then
		warn(string.format("[RunwayService] Could not mark payout week %d complete", finishedWeek))
	end
end

function RunwayService:Remove(player: Player)
	local entry = self.entries[player.UserId]
	if not entry then
		return
	end
	self.entries[player.UserId] = nil
	local ownTarget = self.votesBy[player.UserId]
	if ownTarget and self.entries[ownTarget] then
		self.entries[ownTarget].votes = math.max(0, self.entries[ownTarget].votes - 1)
	end
	self.votesBy[player.UserId] = nil
	for voterId, targetId in self.votesBy do
		if targetId == player.UserId then
			-- The vote no longer counts, but the voter already spent their one
			-- ballot (and received its XP). -1 is a non-target sentinel that
			-- keeps the one-vote contract intact without pointing at a player.
			self.votesBy[voterId] = -1
		end
	end
	self:_Broadcast()
end

return RunwayService
