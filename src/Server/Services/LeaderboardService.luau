--!strict

-- A thin wrapper around an OrderedDataStore ranking players by likes their
-- published/listed creations have received from other players. Existing
-- per-item like counts already live on the owner's own profile (not
-- queryable in bulk across every player), so this keeps a parallel,
-- purpose-built ranked index the same way ItemIndex does for marketplace
-- discovery.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local LeaderboardService = {}
LeaderboardService.__index = LeaderboardService

function LeaderboardService.new()
	return setmetatable({
		store = DataStoreService:GetOrderedDataStore(Config.DataStores.LikesLeaderboard),
		nameCache = {} :: { [number]: string },
	}, LeaderboardService)
end

-- Fire-and-forget: the leaderboard is a nice-to-have ranking, not a source
-- of truth, so a transient DataStore failure here must never block or fail
-- the like/unlike action that triggered it.
function LeaderboardService:SetScore(userId: number, score: number)
	if score < 0 then
		return
	end
	task.spawn(function()
		local success, problem = pcall(function()
			self.store:SetAsync(tostring(userId), score)
		end)
		if not success then
			warn(string.format("[LeaderboardService] SetAsync failed for %d: %s", userId, tostring(problem)))
		end
	end)
end

function LeaderboardService:_NameFor(userId: number): string
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
	local resolved = if success and type(name) == "string" and name ~= "" then name else "Creator"
	self.nameCache[userId] = resolved
	return resolved
end

function LeaderboardService:GetTop(): { { userId: number, name: string, likes: number } }
	local success, pages = pcall(function()
		return self.store:GetSortedAsync(false, Config.Leaderboard.TopCount)
	end)
	if not success then
		warn(string.format("[LeaderboardService] GetSortedAsync failed: %s", tostring(pages)))
		return {}
	end
	local page = pages:GetCurrentPage()
	local results = {}
	for _, entry in page do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(results, {
				userId = userId,
				name = self:_NameFor(userId),
				likes = entry.value,
			})
		end
	end
	return results
end

return LeaderboardService
