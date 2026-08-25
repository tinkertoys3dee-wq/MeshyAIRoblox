--!strict

-- Fetches a real, externally-fetchable HTTPS image URL for a player's
-- current Roblox avatar render, for AVATAR_TO_3D generations to hand to
-- Forge's own backend (which in turn feeds it to Meshy the same way it
-- already handles an uploaded/generated reference image's URL).
--
-- Deliberately does NOT use `Players:GetUserThumbnailAsync`: that call only
-- ever returns an opaque `rbxthumb://` Content reference the Roblox ENGINE
-- resolves internally when rendering an ImageLabel on-screen -- exactly
-- right for the client-side live preview (see App.luau), but never a real
-- URL an external HTTP service could download. Roblox's own public
-- Thumbnails web API is the documented way to get one server-side, and this
-- game already talks to an external host over HttpService for every
-- generation (see BackendService) -- calling a second one needs no new
-- permission.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local AvatarThumbnailService = {}
AvatarThumbnailService.__index = AvatarThumbnailService

local MAX_ATTEMPTS = 4
-- A brand new/never-rendered avatar combination can briefly come back
-- "Pending" rather than "Completed" -- worth one short retry loop of its
-- own, distinct from the HTTP-failure retry below, since it's not an error,
-- just not ready yet.
local PENDING_RETRY_SECONDS = 0.6

local ENDPOINT_BY_VIEW: { [string]: string } = {}
for _, view in Config.Generation.AvatarViews do
	ENDPOINT_BY_VIEW[view.Id] = view.Endpoint
end

function AvatarThumbnailService.new()
	return setmetatable({}, AvatarThumbnailService)
end

-- Returns (true, imageUrl) on success, or (false, errorCode). `avatarView`
-- must be one of Config.Generation.AvatarViews' Id values.
function AvatarThumbnailService:GetImageUrl(userId: number, avatarView: string): (boolean, string)
	local endpoint = ENDPOINT_BY_VIEW[avatarView]
	if not endpoint or type(userId) ~= "number" or userId <= 0 then
		return false, "INVALID_AVATAR_VIEW"
	end

	local url = string.format(
		"%s/%s?userIds=%d&size=%s&format=Png&isCircular=false",
		Config.AvatarThumbnails.BaseUrl,
		endpoint,
		userId,
		Config.AvatarThumbnails.Size
	)

	for attempt = 1, MAX_ATTEMPTS do
		local success, response = pcall(function()
			return HttpService:RequestAsync({ Url = url, Method = "GET" })
		end)
		if success and response.Success then
			local decodeSuccess, decoded = pcall(function()
				return HttpService:JSONDecode(response.Body)
			end)
			local entry = if decodeSuccess
					and type(decoded) == "table"
					and type(decoded.data) == "table"
				then decoded.data[1]
				else nil
			if type(entry) ~= "table" then
				return false, "THUMBNAIL_BAD_RESPONSE"
			end
			if entry.state == "Completed" and type(entry.imageUrl) == "string" and entry.imageUrl ~= "" then
				return true, entry.imageUrl
			end
			if entry.state == "Pending" and attempt < MAX_ATTEMPTS then
				task.wait(PENDING_RETRY_SECONDS)
				continue
			end
			warn(`[AvatarThumbnailService] Thumbnail state for {userId}/{avatarView}: {tostring(entry.state)}`)
			return false, "THUMBNAIL_UNAVAILABLE"
		end

		local statusCode = if success then tonumber(response.StatusCode) or 0 else 0
		local retryable = not success or statusCode == 408 or statusCode == 429 or statusCode >= 500
		if not retryable or attempt == MAX_ATTEMPTS then
			warn(`[AvatarThumbnailService] Request failed for {userId}/{avatarView}: {tostring(response)}`)
			return false, "THUMBNAIL_UNAVAILABLE"
		end
		task.wait(0.35 * (2 ^ (attempt - 1)))
	end
	return false, "THUMBNAIL_UNAVAILABLE"
end

return AvatarThumbnailService
