--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local ModerationService = {}

local function normalize(rawText: string): string
	local normalized = string.gsub(rawText, "[%c]", " ")
	normalized = string.gsub(normalized, "%s+", " ")
	normalized = string.gsub(normalized, "^%s+", "")
	normalized = string.gsub(normalized, "%s+$", "")
	return normalized
end

-- Runs Roblox's own text filter over already-length-checked, already-trimmed
-- text, then rejects a result that filtered down to nothing meaningful (fewer
-- than 3 non-space/punctuation characters left, or a leftover "#" mask
-- character) rather than storing/broadcasting that residue.
local function runFilter(player: Player, normalized: string, blockedCode: string): (boolean, string, string?)
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
		return false, "", blockedCode
	end
	return true, filtered, nil
end

function ModerationService.FilterPrompt(player: Player, rawPrompt: any): (boolean, string, string?)
	if type(rawPrompt) ~= "string" then
		return false, "", "PROMPT_REQUIRED"
	end
	local normalized = normalize(rawPrompt)
	if #normalized < Config.Generation.PromptMinLength then
		return false, "", "PROMPT_TOO_SHORT"
	end
	if #normalized > Config.Generation.PromptMaxLength then
		return false, "", "PROMPT_TOO_LONG"
	end
	return runFilter(player, normalized, "PROMPT_BLOCKED")
end

-- Optional, length-bounded free text such as an item/graphic title or
-- description. Unlike FilterPrompt above, an empty (or all-whitespace)
-- result is valid -- the owner is clearing the field, not submitting
-- nothing -- so it returns success with a nil filtered value rather than an
-- error.
function ModerationService.FilterOptionalText(
	player: Player,
	rawText: any,
	maxLength: number
): (boolean, string?, string?)
	if rawText == nil then
		return true, nil, nil
	end
	if type(rawText) ~= "string" then
		return false, nil, "TEXT_INVALID"
	end
	local normalized = normalize(rawText)
	if normalized == "" then
		return true, nil, nil
	end
	if #normalized > maxLength then
		return false, nil, "TEXT_TOO_LONG"
	end
	return runFilter(player, normalized, "TEXT_BLOCKED")
end

return ModerationService
