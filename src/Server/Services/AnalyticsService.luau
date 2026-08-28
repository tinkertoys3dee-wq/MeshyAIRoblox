--!strict

local Players = game:GetService("Players")
local RobloxAnalytics = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")

local AnalyticsService = {}
AnalyticsService.__index = AnalyticsService

-- One funnel step per whole minute of session playtime, 1-15: how many
-- players are still around after 1 minute, 2 minutes, ... 15 minutes. Read
-- as a retention/drop-off curve on the dashboard, distinct from
-- ForgeSessionEnded's single final duration.
local PLAYTIME_FUNNEL_MINUTES = 15

local CLIENT_EVENTS = {
	AppOpenedTab = true,
	OnboardingStep = true,
	CatalogSearch = true,
	FitPresetApplied = true,
}

-- "Settings" was missing here for a while: every Settings-page visit was
-- silently rejected by TrackClient below (INVALID_ANALYTICS_FIELDS) and
-- never reached Roblox analytics at all.
local PAGE_VALUES = { Create = true, ["My Studio"] = true, Discover = true, ["Avatar Lab"] = true, Settings = true }
local CATALOG_SORT_VALUES = {
	Relevance = true,
	Bestselling = true,
	MostFavorited = true,
	PriceLowToHigh = true,
	PriceHighToLow = true,
	RecentlyCreated = true,
}
local ASSET_TYPE_VALUES = {
	Hat = true,
	HairAccessory = true,
	FaceAccessory = true,
	NeckAccessory = true,
	ShoulderAccessory = true,
	FrontAccessory = true,
	BackAccessory = true,
	WaistAccessory = true,
}
local ONBOARDING_STEP_NAMES = {
	[1] = "Entered Forge",
	[2] = "Understood creation paths",
	[3] = "Understood fitting and marketplace",
	[4] = "Ready to create",
}

local function safeCall(callback: () -> ())
	local success, problem = pcall(callback)
	if not success then
		warn(string.format("[AnalyticsService] Roblox analytics call failed: %s", tostring(problem)))
	end
end

local function safeFields(raw: any): { [string]: string | number | boolean }
	local fields = {}
	if type(raw) ~= "table" then
		return fields
	end
	local count = 0
	for key, value in raw do
		if count >= 5 then
			break
		end
		if type(key) == "string" and #key <= 32 then
			if type(value) == "string" then
				fields[key] = string.sub(value, 1, 64)
				count += 1
			elseif type(value) == "number" or type(value) == "boolean" then
				fields[key] = value
				count += 1
			end
		end
	end
	return fields
end

function AnalyticsService.new()
	return setmetatable({
		sessions = {} :: { [Player]: { [string]: any } },
	}, AnalyticsService)
end

function AnalyticsService:PlayerJoined(player: Player, returning: boolean)
	self.sessions[player] = {
		onboarding = HttpService:GenerateGUID(false),
		generation = HttpService:GenerateGUID(false),
		reference = HttpService:GenerateGUID(false),
		marketplace = HttpService:GenerateGUID(false),
		playtime = HttpService:GenerateGUID(false),
		startedAt = os.time(),
	}
	safeCall(function()
		RobloxAnalytics:LogCustomEvent(player, "ForgeSessionStarted", 1, {
			returningPlayer = returning,
		})
	end)
	if not returning then
		self:Onboarding(player, 1, "Entered Forge")
	end
	self:_TrackPlaytimeFunnel(player)
end

-- Fires the "playtime" funnel's 15 minute-by-minute steps for this player's
-- session, one per elapsed minute, stopping early the moment they leave (the
-- session table is nil'd out by Remove below) so a player who leaves after 4
-- minutes only ever registers steps 1-4, never the later ones.
function AnalyticsService:_TrackPlaytimeFunnel(player: Player)
	task.spawn(function()
		for minute = 1, PLAYTIME_FUNNEL_MINUTES do
			task.wait(60)
			if player.Parent ~= Players or not self.sessions[player] then
				return
			end
			self:Funnel(
				player,
				"playtime",
				minute,
				string.format("%d minute%s played", minute, if minute == 1 then "" else "s")
			)
		end
	end)
end

function AnalyticsService:Onboarding(player: Player, step: number, stepName: string)
	safeCall(function()
		RobloxAnalytics:LogOnboardingFunnelStepEvent(player, step, stepName, {})
	end)
end

function AnalyticsService:Funnel(player: Player, funnel: string, step: number, stepName: string, fields: any?)
	local sessions = self.sessions[player]
	local sessionId = sessions and sessions[funnel]
	if not sessionId then
		sessionId = HttpService:GenerateGUID(false)
		if sessions then
			sessions[funnel] = sessionId
		end
	end
	safeCall(function()
		RobloxAnalytics:LogFunnelStepEvent(player, "Forge_" .. funnel, sessionId, step, stepName, safeFields(fields))
	end)
end

function AnalyticsService:BeginFunnel(player: Player, funnel: string, stepName: string, fields: any?)
	local sessions = self.sessions[player]
	if sessions then
		sessions[funnel] = HttpService:GenerateGUID(false)
	end
	self:Funnel(player, funnel, 1, stepName, fields)
end

function AnalyticsService:Custom(player: Player, eventName: string, value: number?, fields: any?)
	safeCall(function()
		RobloxAnalytics:LogCustomEvent(player, eventName, value or 1, safeFields(fields))
	end)
end

function AnalyticsService:Economy(player: Player, amount: number, sku: string)
	safeCall(function()
		RobloxAnalytics:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Sink,
			"Robux",
			amount,
			0,
			Enum.AnalyticsEconomyTransactionType.IAP.Name,
			sku,
			{}
		)
	end)
end

function AnalyticsService:TrackClient(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" or type(payload.event) ~= "string" or not CLIENT_EVENTS[payload.event] then
		return false, "INVALID_ANALYTICS_EVENT"
	end
	local fields = {}
	if payload.event == "AppOpenedTab" then
		local page = type(payload.fields) == "table" and payload.fields.page or nil
		if type(page) ~= "string" or not PAGE_VALUES[page] then
			return false, "INVALID_ANALYTICS_FIELDS"
		end
		fields.page = page
		if page == "Discover" then
			self:BeginFunnel(player, "marketplace", "Discover opened", {})
		end
	elseif payload.event == "CatalogSearch" then
		local assetType = type(payload.fields) == "table" and payload.fields.assetType or nil
		if type(assetType) ~= "string" or not ASSET_TYPE_VALUES[assetType] then
			return false, "INVALID_ANALYTICS_FIELDS"
		end
		fields.assetType = assetType
		fields.resultCount = math.clamp(math.floor(tonumber(payload.fields.resultCount) or 0), 0, 100)
		-- Enum choice and presence flags only, never the entered creator name
		-- or price text, to respect the no-catalog-query-text analytics rule.
		local sortType = payload.fields.sortType
		if type(sortType) == "string" and CATALOG_SORT_VALUES[sortType] then
			fields.sortType = sortType
		end
		fields.hasCreatorFilter = payload.fields.hasCreatorFilter == true
		fields.hasPriceFilter = payload.fields.hasPriceFilter == true
	end
	self:Custom(player, payload.event, 1, fields)
	if payload.event == "OnboardingStep" then
		local step = math.clamp(math.floor(tonumber(payload.step) or 1), 1, 4)
		self:Onboarding(player, step, ONBOARDING_STEP_NAMES[step])
	end
	return true, {}
end

function AnalyticsService:Remove(player: Player)
	local session = self.sessions[player]
	if session then
		self:Custom(player, "ForgeSessionEnded", math.max(0, os.time() - (session.startedAt or os.time())), {})
	end
	self.sessions[player] = nil
end

return AnalyticsService
