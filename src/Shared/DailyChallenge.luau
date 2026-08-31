--!strict

-- Today's target score for each Arcade game, computed as a pure function of
-- (gameKey, UTC day) so it needs no DataStore or server round-trip -- the
-- client (to display it on a tile) and ArcadeService (to grant the bonus)
-- each compute the exact same number independently and always agree.

local DailyChallenge = {}

-- A rough "good but achievable in one sitting" score for each game, given
-- their own scoring scales (see each Games/*.luau module): FlappyBird and
-- ColorSwitch score one point per obstacle/ring cleared, DinoRunner scores
-- ~10/second survived, NeonSnake scores one point per food eaten,
-- BlockStacker scores one point per block successfully landed on the tower,
-- BrickBreaker scores one point per brick broken (a wave is 24 bricks),
-- ReflexTap scores one point per correctly-tapped tile before its window
-- expires, PrismMerge adds the value of every combined prism, MeteorRush
-- scores distance plus pickups, deflections, and near misses, SkyHopper
-- scores world height climbed (÷6) plus coins, and EchoMatch scores every
-- correct tap (plus a speed-combo bonus) plus an escalating per-round clear
-- bonus, so clearing a handful of rounds outpaces ReflexTap-style per-tap
-- scoring quickly.
local BASE_TARGETS: { [string]: number } = {
	FlappyBird = 8,
	DinoRunner = 260,
	ColorSwitch = 10,
	NeonSnake = 12,
	BlockStacker = 14,
	BrickBreaker = 20,
	ReflexTap = 14,
	PrismMerge = 512,
	MeteorRush = 220,
	SkyHopper = 200,
	EchoMatch = 40,
}

-- Deterministic pseudo-randomness with no storage: folds the day number and
-- the game's own name into a 0-40 spread, then scales the base target by
-- 0.80-1.20x so the target visibly moves day to day without ever needing to
-- be written down anywhere.
function DailyChallenge.GetTarget(gameKey: string, day: number): number?
	local base = BASE_TARGETS[gameKey]
	if not base then
		return nil
	end
	local seed = (day * 37 + string.byte(gameKey, 1)) % 41
	local variance = 0.8 + seed / 100
	return math.max(1, math.floor(base * variance))
end

return DailyChallenge
