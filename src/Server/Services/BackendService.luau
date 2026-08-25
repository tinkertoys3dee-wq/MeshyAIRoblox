--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local BackendService = {}
BackendService.__index = BackendService

local MAX_ATTEMPTS = 3

function BackendService.new()
	return setmetatable({}, BackendService)
end

function BackendService:IsConfigured(): boolean
	return Config.Backend.BaseUrl ~= ""
end

function BackendService:CreateJob(player: Player, payload: { [string]: any }): (boolean, { [string]: any } | string)
	payload.playerUserId = player.UserId
	payload.context = {
		universeId = game.GameId,
		placeId = game.PlaceId,
		gameJobId = game.JobId,
	}
	return self:_Request(player, "POST", "/v1/jobs", payload)
end

function BackendService:ModeratePrompt(player: Player, filteredPrompt: string): (boolean, { [string]: any } | string)
	return self:_Request(player, "POST", "/v1/moderate", {
		playerUserId = player.UserId,
		filteredPrompt = filteredPrompt,
	})
end

function BackendService:GetJob(player: Player, backendJobId: string): (boolean, { [string]: any } | string)
	return self:_Request(player, "GET", `/v1/jobs/{HttpService:UrlEncode(backendJobId)}`, nil)
end

function BackendService:_Request(
	player: Player,
	method: string,
	path: string,
	body: { [string]: any }?
): (boolean, { [string]: any } | string)
	if not self:IsConfigured() then
		return false, "BACKEND_NOT_CONFIGURED"
	end

	-- HttpService:GetSecret can fail transiently in Studio -- most often
	-- right at the start of a fresh test session, before Studio's bridge
	-- to Creator Hub secrets has finished warming up -- even though the
	-- secret is genuinely configured and every other call in the same
	-- session succeeds moments later. A single failed attempt here isn't
	-- proof the secret is actually missing, so this retries with the same
	-- backoff shape as the HTTP request loop below before giving up.
	local secretSuccess, secret = false, nil :: any
	for attempt = 1, MAX_ATTEMPTS do
		secretSuccess, secret = pcall(function()
			return HttpService:GetSecret(Config.Backend.SecretName)
		end)
		if secretSuccess then
			break
		end
		if attempt < MAX_ATTEMPTS then
			task.wait(0.35 * (2 ^ (attempt - 1)))
		end
	end
	if not secretSuccess then
		warn(`[BackendService] Creator Hub secret unavailable after {MAX_ATTEMPTS} attempts: {secret}`)
		return false, "BACKEND_SECRET_UNAVAILABLE"
	end

	local request = {
		Url = string.gsub(Config.Backend.BaseUrl, "/+$", "") .. path,
		Method = method,
		Headers = {
			["content-type"] = "application/json",
			["x-forge-secret"] = secret,
			["x-roblox-user-id"] = tostring(player.UserId),
		},
	}
	if body then
		request.Body = HttpService:JSONEncode(body)
	end

	for attempt = 1, MAX_ATTEMPTS do
		local success, response = pcall(function()
			return HttpService:RequestAsync(request)
		end)
		if success then
			if response.Success then
				local decodeSuccess, decoded = pcall(function()
					return HttpService:JSONDecode(response.Body)
				end)
				if not decodeSuccess or type(decoded) ~= "table" then
					return false, "BACKEND_BAD_RESPONSE"
				end
				return true, decoded
			end

			local statusCode = tonumber(response.StatusCode) or 0
			local retryable = statusCode == 408 or statusCode == 429 or statusCode >= 500
			warn(`[BackendService] Backend returned {statusCode}: {response.Body}`)
			if not retryable or attempt == MAX_ATTEMPTS then
				local decodeSuccess, decoded = pcall(function()
					return HttpService:JSONDecode(response.Body)
				end)
				local errorCode = if decodeSuccess and type(decoded) == "table" then decoded.error else nil
				if type(errorCode) == "string" and #errorCode <= 64 and string.match(errorCode, "^[A-Z0-9_]+$") then
					return false, errorCode
				end
				return false, `BACKEND_HTTP_{statusCode}`
			end
		else
			warn(`[BackendService] HTTP request failed: {response}`)
			if attempt == MAX_ATTEMPTS then
				return false, "BACKEND_UNAVAILABLE"
			end
		end
		task.wait(0.35 * (2 ^ (attempt - 1)))
	end
	return false, "BACKEND_UNAVAILABLE"
end

return BackendService
