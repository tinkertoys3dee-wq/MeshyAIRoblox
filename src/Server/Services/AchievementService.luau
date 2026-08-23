--!strict

-- One-time milestones across every major Forge feature, each granting a
-- small Forge Tokens reward exactly once. The point isn't the reward itself
-- (small by design, see docs/PRICING.md) — it's giving players a reason to
-- try equip, fit presets, publishing, listing, liking, Avatar Lab try-on,
-- and rewarded ads instead of only ever using whichever path they found
-- first. Definitions live here; call sites elsewhere just call Unlock/
-- CheckCount with an id from this list.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage:WaitForChild("Achievements"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local AchievementService = {}
AchievementService.__index = AchievementService

local BY_ID: { [string]: Achievements.AchievementDefinition } = {}
for _, definition in Achievements.List do
	BY_ID[definition.id] = definition
end

function AchievementService.new(profileService: any, push: (Player, string, any) -> (), analyticsService: any)
	return setmetatable({
		profiles = profileService,
		push = push,
		analytics = analyticsService,
	}, AchievementService)
end

-- Grants achievementId's token reward the first time this is called for a
-- given player; every later call for the same id is a harmless no-op, so
-- call sites never need their own "have they already got this" check.
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
end

-- For milestones defined by a running count crossing a threshold (five
-- creations, a seven-day streak) rather than a single discrete event.
function AchievementService:CheckCount(player: Player, achievementId: string, count: number, threshold: number)
	if count >= threshold then
		self:Unlock(player, achievementId)
	end
end

return AchievementService
