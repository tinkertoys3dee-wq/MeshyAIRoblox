--!strict

-- Score tracking and weekly top-3 token payouts for the client-side arcade
-- minigames (Flappy Bird, Dino Runner, Color Switch). See Config.Arcade for
-- the reward amounts.
--
-- Unlike every other free grant (achievements, daily check-in, win-back —
-- see ProfileService.defaultProfile), these are credited straight to
-- `tokens`, the same fully-spendable pool ad rewards and Robux purchases
-- fund, not the spend-restricted `bonusTokens` pool. That's a deliberate,
-- bounded cost, not an oversight: max payout is 800 tokens/game * 3 games =
-- 2400 tokens/week worst case (every rank won by a different player, every
-- week), worth roughly 2 generations or ~$0.60 at the token pricing in
-- Config.Generation. Accepted as an engagement investment, same category as
-- the free tokens for watching an ad -- not something to "fix" back to
-- bonusTokens without checking with the studio owner first.
--
-- Every game's actual play loop runs entirely on the client (see
-- src/Client/UI/Games/) with no server authority over gameplay -- these are
-- session-time minigames, not a purchasable product, so that tradeoff is
-- fine for the games themselves. It is NOT fine for what happens with a
-- submitted score, since real tokens are now on the other end of it: every
-- score is treated as unverified client input here (sanity-clamped, only
-- ever improves a player's own stored best, never trusted as ground truth
-- the way a Roblox purchase receipt or AdService completion callback is).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local ArcadeService = {}
ArcadeService.__index = ArcadeService

local WEEK_SECONDS = 7 * 24 * 60 * 60
local SCORE_STORE_PREFIX = "FUGC_Arcade_"
local PAYOUT_CHECK_INTERVAL_SECONDS = 30 * 60
local DISPLAY_TOP_COUNT = 10

local GAMES: { [string]: boolean } = {}
for _, name in Config.Arcade.Games do
	GAMES[name] = true
end

local function currentWeek(): number
	return math.floor(os.time() / WEEK_SECONDS)
end

local function scoreStoreName(gameKey: string, week: number): string
	return SCORE_STORE_PREFIX .. gameKey .. "_wk" .. tostring(week)
end

function ArcadeService.new(
	profileService: any,
	playerStateService: any,
	push: (Player, string, any) -> (),
	analyticsService: any
)
	local self = setmetatable({
		profiles = profileService,
		playerStates = playerStateService,
		push = push,
		analytics = analyticsService,
		metaStore = DataStoreService:GetDataStore(Config.DataStores.ArcadeMeta),
		nameCache = {} :: { [number]: string },
	}, ArcadeService)

	task.spawn(function()
		self:_CheckWeeklyPayout()
	end)
	task.spawn(function()
		while true do
			task.wait(PAYOUT_CHECK_INTERVAL_SECONDS)
			self:_CheckWeeklyPayout()
		end
	end)

	return self
end

function ArcadeService:_NameFor(userId: number): string
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

-- Records `score` as this player's best for `gameKey` this week, if it beats
-- whatever they already have stored. Never rejects a submission outright
-- (a low or repeat score is simply not written) except for malformed input,
-- so a well-behaved client never sees an error from an honest low score.
function ArcadeService:SubmitScore(player: Player, gameKey: any, score: any): (boolean, any)
	if type(gameKey) ~= "string" or not GAMES[gameKey] then
		return false, "UNKNOWN_GAME"
	end
	if type(score) ~= "number" or score ~= score or score < 0 then
		return false, "INVALID_SCORE"
	end
	local clamped = math.min(math.floor(score), Config.Arcade.MaxSubmittableScore)
	local week = currentWeek()
	local store = DataStoreService:GetOrderedDataStore(scoreStoreName(gameKey, week))
	local key = tostring(player.UserId)

	local newBest = clamped
	local success = pcall(function()
		local existing = store:GetAsync(key)
		local existingScore = if type(existing) == "number" then existing else -1
		if clamped > existingScore then
			store:SetAsync(key, clamped)
		else
			newBest = existingScore
		end
	end)
	if not success then
		return false, "SCORE_STORE_UNAVAILABLE"
	end

	self.analytics:Custom(player, "ArcadeScoreSubmitted", clamped, { game = gameKey })
	return true, { best = newBest }
end

-- Top `DISPLAY_TOP_COUNT` for `gameKey` this week, for the in-hub "this
-- week" standings -- plus the requesting player's own rank/score, so the
-- panel can show "where do I stand" even when that's outside the visible
-- list. `self` is nil only when the player has no score at all this week;
-- otherwise it always carries a score, with `rank` set only when they
-- placed within the fetched page (a second, targeted read covers everyone
-- else, since GetSortedAsync has no cheap "rank of this key" query).
function ArcadeService:GetWeeklyTop(player: Player, gameKey: any): (boolean, any)
	if type(gameKey) ~= "string" or not GAMES[gameKey] then
		return false, "UNKNOWN_GAME"
	end
	local store = DataStoreService:GetOrderedDataStore(scoreStoreName(gameKey, currentWeek()))
	local success, pages = pcall(function()
		return store:GetSortedAsync(false, DISPLAY_TOP_COUNT)
	end)
	if not success then
		return true, { standings = {}, self = nil }
	end
	local standings = {}
	local selfStanding = nil
	for rank, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(standings, { userId = userId, name = self:_NameFor(userId), score = entry.value })
			if userId == player.UserId then
				selfStanding = { rank = rank, score = entry.value }
			end
		end
	end
	if not selfStanding then
		local ownSuccess, ownScore = pcall(function()
			return store:GetAsync(tostring(player.UserId))
		end)
		if ownSuccess and type(ownScore) == "number" then
			selfStanding = { rank = nil, score = ownScore }
		end
	end
	return true, { standings = standings, self = selfStanding }
end

-- Atomically claims responsibility for paying out `week` so that, across
-- however many concurrent server instances are running, only one of them
-- actually grants the rewards -- every other instance's UpdateAsync callback
-- sees the already-bumped value and backs off.
function ArcadeService:_ClaimPayoutWeek(week: number): boolean
	local claimed = false
	local success = pcall(function()
		self.metaStore:UpdateAsync("lastPayoutWeek", function(stored)
			local storedWeek = if type(stored) == "number" then stored else 0
			if storedWeek < week then
				claimed = true
				return week
			end
			claimed = false
			return stored
		end)
	end)
	return success and claimed
end

function ArcadeService:_ProcessWeek(week: number)
	for _, gameKey in Config.Arcade.Games do
		local store = DataStoreService:GetOrderedDataStore(scoreStoreName(gameKey, week))
		local success, pages = pcall(function()
			return store:GetSortedAsync(false, 3)
		end)
		if not success then
			warn(`[ArcadeService] Could not read {gameKey} standings for week {week}: {tostring(pages)}`)
			continue
		end
		for rank, entry in pages:GetCurrentPage() do
			local userId = tonumber(entry.key)
			local reward = Config.Arcade.WeeklyRewards[rank]
			if not userId or not reward then
				continue
			end
			local granted = self.profiles:MutateUser(userId, function(profile)
				-- tokens, not bonusTokens: see the module header for why
				-- this one specific grant is fully spendable.
				profile.tokens = (profile.tokens or 0) + reward
			end)
			if not granted then
				warn(`[ArcadeService] Could not grant week {week} {gameKey} rank {rank} reward to {userId}`)
				continue
			end
			local onlinePlayer = Players:GetPlayerByUserId(userId)
			if onlinePlayer and onlinePlayer.Parent == Players then
				local profile = self.profiles:Get(onlinePlayer)
				if profile then
					self.push(onlinePlayer, Network.PushEvents.Profile, { tokens = profile.tokens })
				end
				self.push(onlinePlayer, Network.PushEvents.Toast, {
					tone = "success",
					message = string.format(
						"Arcade weekly reward: #%d in %s earned you +%d Forge Tokens!",
						rank,
						gameKey,
						reward
					),
				})
			end
		end
	end
end

-- Checked once at startup and periodically thereafter (see
-- PAYOUT_CHECK_INTERVAL_SECONDS): Roblox servers are per-session, not one
-- long-lived process, so "a new server started" is the reliable signal a
-- week boundary might have passed, not a scheduled job. The first-ever check
-- (lastPayoutWeek has never been set) only establishes a baseline instead of
-- paying out a partial or nonexistent week -- there's nothing to pay yet on
-- a brand new deployment.
function ArcadeService:_CheckWeeklyPayout()
	local completedWeek = currentWeek() - 1
	local success, stored = pcall(function()
		return self.metaStore:GetAsync("lastPayoutWeek")
	end)
	if not success then
		return
	end

	if stored == nil then
		pcall(function()
			self.metaStore:UpdateAsync("lastPayoutWeek", function(current)
				if current == nil then
					return completedWeek
				end
				return current
			end)
		end)
		return
	end

	local lastPayoutWeek = if type(stored) == "number" then stored else completedWeek
	if lastPayoutWeek >= completedWeek then
		return
	end

	-- Processes every completed week since the last payout, in order, in
	-- case a long gap (no server running across more than one boundary)
	-- left more than one week unpaid.
	for week = lastPayoutWeek + 1, completedWeek do
		if self:_ClaimPayoutWeek(week) then
			self:_ProcessWeek(week)
		end
	end
end

return ArcadeService
