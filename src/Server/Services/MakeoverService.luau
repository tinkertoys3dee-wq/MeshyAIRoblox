--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local MakeoverService = {}
MakeoverService.__index = MakeoverService

local function today(): number
	return math.floor(os.time() / 86400)
end

local function themeForDay(day: number): (string, number)
	local themes = Config.StyleSprint.DailyThemes
	local index = (day % #themes) + 1
	return themes[index], index
end

local function countKeys(values: { [any]: boolean }): number
	local total = 0
	for _ in values do
		total += 1
	end
	return total
end

function MakeoverService.new(
	profileService: any,
	analyticsService: any,
	retentionService: any,
	progressionService: any,
	push: (Player, string, any) -> ()
)
	return setmetatable({
		profiles = profileService,
		analytics = analyticsService,
		retention = retentionService,
		progression = progressionService,
		push = push,
		sessions = {} :: { [Player]: { [string]: any } },
	}, MakeoverService)
end

function MakeoverService:_Ensure(player: Player): { [string]: any }
	local current = self.sessions[player]
	local day = today()
	if current and current.day == day then
		return current
	end
	local theme, themeIndex = themeForDay(day)
	current = {
		day = day,
		startedAt = os.time(),
		theme = theme,
		themeIndex = themeIndex,
		assetIds = {} :: { [string]: boolean },
		categories = {} :: { [string]: boolean },
		starterApplied = false,
		personalized = false,
		completed = false,
		score = 0,
	}
	self.sessions[player] = current
	self.analytics:BeginFunnel(player, "makeover", "Style Sprint opened", { theme = themeIndex })
	self.analytics:Custom(player, "StyleSprintStarted", 1, { theme = themeIndex })
	return current
end

function MakeoverService:GetState(player: Player): { [string]: any }
	local profile = self.profiles:Get(player)
	local saved = profile and profile.makeover or {}
	local current = self.sessions[player]
	local day = today()
	if current and current.day ~= day then
		self.sessions[player] = nil
		current = nil
	end
	local theme, themeIndex = themeForDay(day)
	if not current then
		return {
			active = false,
			theme = theme,
			themeIndex = themeIndex,
			durationSeconds = Config.StyleSprint.DurationSeconds,
			remainingSeconds = Config.StyleSprint.DurationSeconds,
			starterApplied = false,
			personalized = false,
			completed = false,
			categoryCount = 0,
			itemCount = 0,
			bestScore = saved.bestScore or 0,
			dailyCompleted = saved.dailyDay == day and saved.dailyCompleted == true,
			completedCount = saved.completedCount or 0,
		}
	end
	return {
		active = not current.completed,
		theme = current.theme,
		themeIndex = current.themeIndex,
		durationSeconds = Config.StyleSprint.DurationSeconds,
		remainingSeconds = math.max(0, Config.StyleSprint.DurationSeconds - (os.time() - current.startedAt)),
		starterApplied = current.starterApplied,
		personalized = current.personalized,
		completed = current.completed,
		categoryCount = countKeys(current.categories),
		itemCount = countKeys(current.assetIds),
		score = current.score,
		breakdown = current.breakdown,
		bestScore = math.max(saved.bestScore or 0, current.score or 0),
		dailyCompleted = saved.dailyDay == day and saved.dailyCompleted == true,
		completedCount = saved.completedCount or 0,
	}
end

function MakeoverService:_Push(player: Player, extra: any?)
	if player.Parent ~= Players then
		return
	end
	local payload: { [string]: any } = { state = self:GetState(player) }
	if type(extra) == "table" then
		for key, value in extra do
			payload[key] = value
		end
	end
	self.push(player, Network.PushEvents.Makeover, payload)
end

function MakeoverService:Start(player: Player, restart: boolean?): (boolean, { [string]: any })
	if restart and self.sessions[player] and self.sessions[player].completed then
		self.sessions[player] = nil
	end
	self:_Ensure(player)
	local state = self:GetState(player)
	self:_Push(player)
	return true, state
end

function MakeoverService:RecordStarterLook(player: Player, lookKey: string, assets: { any })
	local session = self:_Ensure(player)
	local added = 0
	for _, asset in assets do
		local id = math.floor(tonumber(asset.assetId) or 0)
		local assetType = if type(asset.assetType) == "string" then asset.assetType else "Accessory"
		if id > 0 then
			local key = tostring(id)
			if not session.assetIds[key] then
				session.assetIds[key] = true
				added += 1
			end
			session.categories[assetType] = true
		end
	end
	if added <= 0 then
		return
	end
	session.starterApplied = true
	session.lookKey = lookKey
	self.retention:MarkJourney(player, "TRY_STYLE")
	self.analytics:Funnel(player, "makeover", 2, "Starter look applied", {
		look = string.sub(lookKey, 1, 16),
		itemCount = added,
	})
	self.analytics:Custom(player, "StarterLookApplied", added, { look = string.sub(lookKey, 1, 16) })
	self:_Push(player, { justCompleted = "TRY_STYLE" })
end

-- Single-item changes from catalog, community, or the player's own Forge
-- inventory share one progression rule: the first successful change can be
-- the starting look; a later distinct change is the personalization step.
function MakeoverService:RecordChange(player: Player, assetKey: string, assetType: string, source: string)
	local session = self:_Ensure(player)
	local safeKey = string.sub(assetKey, 1, 64)
	if safeKey == "" or session.assetIds[safeKey] then
		return
	end
	session.assetIds[safeKey] = true
	session.categories[string.sub(assetType, 1, 32)] = true
	if not session.starterApplied then
		session.starterApplied = true
		self.retention:MarkJourney(player, "TRY_STYLE")
		self.analytics:Funnel(player, "makeover", 2, "First item applied", { source = source })
		self:_Push(player, { justCompleted = "TRY_STYLE" })
		return
	end
	if not session.personalized then
		session.personalized = true
		self.retention:MarkJourney(player, "PERSONALIZE")
		self.analytics:Funnel(player, "makeover", 3, "Look personalized", { source = source })
		self.analytics:Custom(player, "MakeoverPersonalized", 1, { source = source })
		self:_Push(player, { justCompleted = "PERSONALIZE" })
	else
		self:_Push(player)
	end
end

function MakeoverService:Complete(player: Player): { [string]: any }
	local session = self.sessions[player]
	if not session then
		return { state = self:GetState(player), inactive = true }
	end
	if not session.starterApplied or not session.personalized then
		self.analytics:Custom(player, "MakeoverSavedBeforePersonalize", 1, {
			hasStarter = session ~= nil and session.starterApplied == true,
		})
		local state = self:GetState(player)
		return { state = state, needsPersonalize = not (session and session.personalized) }
	end
	if session.completed then
		return { state = self:GetState(player), score = session.score, alreadyCompleted = true }
	end

	local elapsed = math.max(0, os.time() - session.startedAt)
	local categoryCount = countKeys(session.categories)
	local breakdown = {
		completion = 45,
		variety = math.min(3, categoryCount) * 10,
		personalization = 15,
		themeHarmony = if session.lookKey then 5 else 0,
		speed = if elapsed <= Config.StyleSprint.DurationSeconds then 5 else 0,
	}
	local score = breakdown.completion
		+ breakdown.variety
		+ breakdown.personalization
		+ breakdown.themeHarmony
		+ breakdown.speed
	score = math.clamp(score, 0, 100)
	local day = today()
	local xpGranted = 0
	local mutated = self.profiles:Mutate(player, function(profile)
		local makeover = profile.makeover
		makeover.bestScore = math.max(makeover.bestScore or 0, score)
		makeover.completedCount = (makeover.completedCount or 0) + 1
		if makeover.dailyDay ~= day or makeover.dailyCompleted ~= true then
			makeover.dailyDay = day
			makeover.dailyCompleted = true
			xpGranted = Config.StyleSprint.DailyCompletionXP
		end
	end)
	if not mutated then
		return { state = self:GetState(player), error = "PROFILE_NOT_READY" }
	end
	session.completed = true
	session.score = score
	session.breakdown = breakdown
	self.retention:MarkJourney(player, "SAVE_LOOK")
	if xpGranted > 0 then
		self.progression:Grant(player, xpGranted, "DAILY_STYLE_SPRINT")
	else
		self.profiles:Save(player)
	end
	self.analytics:Funnel(player, "makeover", 4, "Outfit saved", {
		score = score,
		under90Seconds = elapsed <= Config.StyleSprint.DurationSeconds,
	})
	self.analytics:Custom(player, "StyleSprintCompleted", score, {
		categories = categoryCount,
		under90Seconds = elapsed <= Config.StyleSprint.DurationSeconds,
	})
	local state = self:GetState(player)
	self:_Push(player, { justCompleted = "SAVE_LOOK", score = score, xpGranted = xpGranted })
	self.push(player, Network.PushEvents.Toast, {
		tone = "success",
		message = string.format(
			"Style Sprint complete: %d/100%s. Your next move: photo, Runway, or Forge a missing piece.",
			score,
			if xpGranted > 0 then string.format(" · +%d Creator XP", xpGranted) else ""
		),
	})
	return { state = state, score = score, breakdown = breakdown, xpGranted = xpGranted }
end

function MakeoverService:Remove(player: Player)
	self.sessions[player] = nil
end

return MakeoverService
