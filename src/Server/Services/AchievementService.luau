--!strict

-- One-time milestones across every major Forge feature, each granting a
-- small Forge Tokens reward exactly once, plus a Roblox badge once its ID is
-- configured. The point isn't the reward itself (small by design, see
-- docs/PRICING.md) — it's giving players a reason to try equip, fit
-- presets, publishing, listing, liking, Avatar Lab try-on, and rewarded ads
-- instead of only ever using whichever path they found first. Definitions
-- live in the shared Achievements module; call sites elsewhere just call
-- Unlock/CheckCount with an id from that list.

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage:WaitForChild("Achievements"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local AchievementService = {}
AchievementService.__index = AchievementService

local BY_ID: { [string]: Achievements.AchievementDefinition } = {}
local NON_COMPLETIONIST_IDS: { string } = {}
for _, definition in Achievements.List do
	BY_ID[definition.id] = definition
	if definition.id ~= Achievements.CompletionistId then
		table.insert(NON_COMPLETIONIST_IDS, definition.id)
	end
end

-- None of these tokens are backed by ad revenue or a Robux payment (unlike a
-- rewarded-ad watch or a direct Forge Tokens purchase), so their combined
-- total must stay inside the budget the token markup already earns Forge —
-- see Config.Achievements.NonEarningTokenBudget for the derivation. This is
-- the same fail-closed-at-startup pattern CommerceService uses for product
-- ID conflicts: a misconfigured economy should never silently go live.
local function validateTokenBudget()
	local total = 0
	for _, definition in Achievements.List do
		total += definition.tokens
	end
	local budget = Config.Achievements.NonEarningTokenBudget
	if total > budget then
		error(
			string.format(
				"Achievements.luau grants %d total tokens across all achievements, over the "
					.. "Config.Achievements.NonEarningTokenBudget cap of %d. Lower some achievement "
					.. "token values or raise the budget deliberately (see its comment).",
				total,
				budget
			)
		)
	end
end

function AchievementService.new(profileService: any, push: (Player, string, any) -> (), analyticsService: any)
	validateTokenBudget()
	return setmetatable({
		profiles = profileService,
		push = push,
		analytics = analyticsService,
	}, AchievementService)
end

-- Grants achievementId's token reward (and Roblox badge, once its ID is
-- configured) the first time this is called for a given player; every later
-- call for the same id is a harmless no-op, so call sites never need their
-- own "have they already got this" check.
function AchievementService:Unlock(player: Player, achievementId: string)
	local definition = BY_ID[achievementId]
	if not definition then
		warn(string.format("[AchievementService] Unknown achievement id: %s", tostring(achievementId)))
		return
	end
	local unlocked = false
	local mutateSuccess = self.profiles:Mutate(player, function(profile)
		if not profile.achievements[achievementId] then
			profile.achievements[achievementId] = os.time()
			profile.tokens = (profile.tokens or 0) + definition.tokens
			unlocked = true
		end
	end)
	if not mutateSuccess or not unlocked then
		return
	end
	self.profiles:Save(player)
	local profile = self.profiles:Get(player)
	if not profile or player.Parent == nil then
		return
	end
	self.push(player, Network.PushEvents.Profile, { tokens = profile.tokens, achievements = profile.achievements })
	self.push(player, Network.PushEvents.Toast, {
		tone = "success",
		message = string.format("Achievement unlocked: %s (+%d tokens)", definition.name, definition.tokens),
	})
	self.analytics:Custom(player, "AchievementUnlocked", definition.tokens, { achievement = achievementId })

	local badgeId = Config.Achievements.BadgeIds[achievementId]
	if type(badgeId) == "number" and badgeId > 0 then
		task.spawn(function()
			local success, problem = pcall(function()
				BadgeService:AwardBadgeAsync(player.UserId, badgeId)
			end)
			if not success then
				warn(
					string.format(
						"[AchievementService] AwardBadgeAsync failed for %s: %s",
						achievementId,
						tostring(problem)
					)
				)
			end
		end)
	end

	if achievementId ~= Achievements.CompletionistId then
		local allDone = true
		for _, otherId in NON_COMPLETIONIST_IDS do
			if not profile.achievements[otherId] then
				allDone = false
				break
			end
		end
		if allDone then
			self:Unlock(player, Achievements.CompletionistId)
		end
	end
end

-- For milestones defined by a running count crossing a threshold (five
-- creations, a seven-day streak) rather than a single discrete event.
function AchievementService:CheckCount(player: Player, achievementId: string, count: number, threshold: number)
	if count >= threshold then
		self:Unlock(player, achievementId)
	end
end

return AchievementService
