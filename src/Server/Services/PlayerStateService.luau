--!strict

local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local PlayerStateService = {}
PlayerStateService.__index = PlayerStateService

function PlayerStateService.new()
	return setmetatable({ states = {} :: { [Player]: { [string]: any } } }, PlayerStateService)
end

function PlayerStateService:Initialize(player: Player): { [string]: any }
	local policySuccess, policy = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if not policySuccess then
		warn(`[PlayerStateService] Policy lookup failed for {player.UserId}: {policy}`)
		policy = {}
	end

	local groupMember = false
	if Config.Group.Id > 0 then
		local groupSuccess, result = pcall(function()
			return player:IsInGroupAsync(Config.Group.Id)
		end)
		groupMember = groupSuccess and result == true
	end

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
	player:SetAttribute("ForgeGroupMember", groupMember)
	player:SetAttribute("ForgeQueueSlots", state.queueSlots)
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

function PlayerStateService:Remove(player: Player)
	self.states[player] = nil
end

return PlayerStateService
