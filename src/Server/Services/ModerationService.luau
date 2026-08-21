--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local ModerationService = {}

function ModerationService.FilterPrompt(player: Player, rawPrompt: any): (boolean, string, string?)
	if type(rawPrompt) ~= "string" then
		return false, "", "PROMPT_REQUIRED"
	end
	local normalized = string.gsub(rawPrompt, "[%c]", " ")
	normalized = string.gsub(normalized, "%s+", " ")
	normalized = string.gsub(normalized, "^%s+", "")
	normalized = string.gsub(normalized, "%s+$", "")
	if #normalized < Config.Generation.PromptMinLength then
		return false, "", "PROMPT_TOO_SHORT"
	end
	if #normalized > Config.Generation.PromptMaxLength then
		return false, "", "PROMPT_TOO_LONG"
	end

	local success, filtered = pcall(function()
		local result = TextService:FilterStringAsync(normalized, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not success or type(filtered) ~= "string" then
		warn(`[ModerationService] Text filtering failed for {player.UserId}: {filtered}`)
		return false, "", "FILTER_UNAVAILABLE"
	end

	local meaningful = string.gsub(filtered, "[%s%p]", "")
	local lengthSuccess, characterCount = pcall(utf8.len, meaningful)
	if not lengthSuccess or (characterCount or 0) < 3 or string.find(filtered, "#", 1, true) then
		return false, "", "PROMPT_BLOCKED"
	end
	return true, filtered, nil
end

return ModerationService
