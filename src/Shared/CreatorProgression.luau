--!strict

-- Pure creator-level math shared by the server (authoritative XP grants)
-- and client (display only). XP is a zero-provider-cost progression track:
-- it unlocks status and presentation, never a paid AI generation.

local CreatorProgression = {}

CreatorProgression.MaximumLevel = 50

local TITLES = {
	{ level = 1, title = "Forge Apprentice" },
	{ level = 3, title = "Style Scout" },
	{ level = 5, title = "Accessory Maker" },
	{ level = 8, title = "Trendsetter" },
	{ level = 12, title = "Forge Artisan" },
	{ level = 20, title = "Master Forger" },
	{ level = 30, title = "Avatar Icon" },
	{ level = 40, title = "Runway Royalty" },
	{ level = 50, title = "Forge Legend" },
}

-- Cumulative XP required to enter `level`. Early levels arrive quickly
-- enough to reward a first session; later titles require repeat play.
function CreatorProgression.XPForLevel(level: number): number
	local clamped = math.clamp(math.floor(level), 1, CreatorProgression.MaximumLevel)
	if clamped <= 1 then
		return 0
	end
	return math.floor(75 * ((clamped - 1) ^ 1.55))
end

function CreatorProgression.LevelFromXP(xp: number): number
	local safeXP = math.max(0, math.floor(xp))
	local level = 1
	while level < CreatorProgression.MaximumLevel and safeXP >= CreatorProgression.XPForLevel(level + 1) do
		level += 1
	end
	return level
end

function CreatorProgression.TitleForLevel(level: number): string
	local title = TITLES[1].title
	for _, definition in TITLES do
		if level < definition.level then
			break
		end
		title = definition.title
	end
	return title
end

function CreatorProgression.Snapshot(xp: number): { [string]: any }
	local safeXP = math.max(0, math.floor(xp))
	local level = CreatorProgression.LevelFromXP(safeXP)
	local floorXP = CreatorProgression.XPForLevel(level)
	local ceilingXP = if level >= CreatorProgression.MaximumLevel
		then floorXP
		else CreatorProgression.XPForLevel(level + 1)
	local span = math.max(1, ceilingXP - floorXP)
	return {
		xp = safeXP,
		level = level,
		title = CreatorProgression.TitleForLevel(level),
		levelFloorXP = floorXP,
		nextLevelXP = ceilingXP,
		levelProgress = if level >= CreatorProgression.MaximumLevel
			then 1
			else math.clamp((safeXP - floorXP) / span, 0, 1),
	}
end

return table.freeze(CreatorProgression)
