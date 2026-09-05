--!strict

local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local PlayerStateService = {}
PlayerStateService.__index = PlayerStateService

local function applyGroupMembership(player: Player, state: { [string]: any }, groupMember: boolean)
	state.groupMember = groupMember
	state.queueSlots = Config.Generation.BaseQueueSlots + (if groupMember then Config.Group.ExtraQueueSlots else 0)
	state.queueSpeedMultiplier = if groupMember then Config.Group.GenerationSpeedMultiplier else 1
	player:SetAttribute("ForgeGroupMember", groupMember)
	player:SetAttribute("ForgeQueueSlots", state.queueSlots)
end

function PlayerStateService.new()
	return setmetatable({ states = {} :: { [Player]: { [string]: any } } }, PlayerStateService)
end

function PlayerStateService:Initialize(player: Player): { [string]: any }
	-- These two Roblox API calls don't depend on each other, but every new
	-- player used to wait through them one after the other on top of the
	-- profile DataStore load in initializePlayer -- three real network round
	-- trips stacked in sequence before any UI became usable, which is a
	-- plausible chunk of "leaves before the first minute". Running them
	-- concurrently overlaps the wait instead of stacking it.
	local policySuccess = false
	local policy: { [string]: any } = {}
	local policyDone = false
	task.spawn(function()
		local success, result = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		policySuccess = success
		if success and type(result) == "table" then
			policy = result
		elseif not success then
			warn(`[PlayerStateService] Policy lookup failed for {player.UserId}: {tostring(result)}`)
		end
		policyDone = true
	end)

	local groupSuccess, groupResult = false, false
	local groupDone = Config.Group.Id <= 0
	if not groupDone then
		task.spawn(function()
			groupSuccess, groupResult = pcall(function()
				return player:IsInGroupAsync(Config.Group.Id)
			end)
			groupDone = true
		end)
	end

	while not (policyDone and groupDone) do
		task.wait()
	end

	local groupMember = Config.Group.Id > 0 and groupSuccess and groupResult == true

	local studioFallback = RunService:IsStudio()
	local state = {
		contentSharingAllowed = if policySuccess then policy.IsContentSharingAllowed == true else studioFallback,
		commerceAllowed = if policySuccess then policy.IsEligibleToPurchaseCommerceProduct == true else studioFallback,
		subscriptionAllowed = if policySuccess then policy.IsEligibleToPurchaseSubscription == true else studioFallback,
		paidTradingAllowed = if policySuccess then policy.IsPaidItemTradingAllowed == true else studioFallback,
		groupMember = groupMember,
		queueSlots = Config.Generation.BaseQueueSlots + (if groupMember then Config.Group.ExtraQueueSlots else 0),
		queueSpeedMultiplier = if groupMember then Config.Group.GenerationSpeedMultiplier else 1,
		plusSubscriber = player.HasRobloxSubscription,
	}
	self.states[player] = state
	player:SetAttribute("ForgeContentSharingAllowed", state.contentSharingAllowed)
	applyGroupMembership(player, state, groupMember)
	return state
end

function PlayerStateService:Get(player: Player): { [string]: any }
	local state = self.states[player]
	if not state then
		state = self:Initialize(player)
	end
	state.plusSubscriber = player.HasRobloxSubscription
	return state
end

-- PromptJoinAsync runs on the client. Roblox clears its group-membership
-- cache when that native prompt joins a player, then this server-authoritative
-- refresh turns the benefits on without making the player leave and rejoin.
function PlayerStateService:RefreshGroupMembership(player: Player): (boolean, any)
	if Config.Group.Id <= 0 then
		return false, "GROUP_NOT_CONFIGURED"
	end
	local success, result = pcall(function()
		return player:IsInGroupAsync(Config.Group.Id)
	end)
	if not success then
		warn(`[PlayerStateService] Group refresh failed for {player.UserId}: {tostring(result)}`)
		return false, "GROUP_CHECK_FAILED"
	end
	local state = self.states[player]
	if not state then
		return false, "PLAYER_STATE_UNAVAILABLE"
	end
	local groupMember = result == true
	local newlyJoined = groupMember and state.groupMember ~= true
	applyGroupMembership(player, state, groupMember)
	return true,
		{
			groupMember = groupMember,
			newlyJoined = newlyJoined,
			queueSlots = state.queueSlots,
			speedMultiplier = state.queueSpeedMultiplier,
		}
end

function PlayerStateService:Remove(player: Player)
	self.states[player] = nil
end

return PlayerStateService
