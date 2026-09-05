--!strict

local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local GroupJoin = {}

local function refresh(app: any)
	app:_RefreshGroupTip()
	if app.activePage == "Settings" then
		app:_RenderActivePage()
	end
end

function GroupJoin.Prompt(app: any)
	if app.groupJoinPrompting then
		app:_Toast("info", "The Roblox group window is already opening.")
		return
	end
	if not app.state then
		app:_Toast("info", "Your creator profile is still loading.")
		return
	end
	if app.state.benefits.groupMember == true then
		app:_Toast(
			"success",
			string.format("You're already a %s member. Your group boost is active.", Config.Group.Name)
		)
		return
	end
	if Config.Group.Id <= 0 then
		app:_Toast("error", "The creator group has not been configured yet.")
		return
	end

	app.groupJoinPrompting = true
	app.groupJoinPending = false
	refresh(app)
	app:_Toast("info", string.format("Opening Roblox's secure %s join window…", Config.Group.Name))
	app:_Track({ event = "GroupJoinPrompt", fields = { action = "CLICK" } })

	task.spawn(function()
		local opened, status = pcall(function()
			return GroupService:PromptJoinAsync(Config.Group.Id)
		end)
		if not opened then
			app.groupJoinPrompting = false
			refresh(app)
			app:_Track({ event = "GroupJoinPrompt", fields = { action = "FAILED_TO_OPEN" } })
			app:_Toast(
				"error",
				"Roblox couldn't open the group window on this device. Try again in a published server."
			)
			return
		end

		if status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember then
			local verified, data = app:_Invoke(Network.Actions.RefreshGroupMembership, {})
			app.groupJoinPrompting = false
			if verified and type(data) == "table" and data.groupMember == true then
				app.groupJoinPending = false
				app.state.benefits.groupMember = true
				app.state.benefits.queueSlots = data.queueSlots
				app.state.benefits.speedMultiplier = data.speedMultiplier
				app:_RenderStatus()
				refresh(app)
				app.sounds:Play("Success")
				app:_Track({ event = "GroupJoinPrompt", fields = { action = "MEMBERSHIP_CONFIRMED" } })
				app:_Toast(
					"success",
					string.format("Welcome to %s! Your faster queue and extra slot are active now.", Config.Group.Name)
				)
				return
			end
			refresh(app)
			if verified then
				app:_Toast(
					"info",
					"Roblox accepted the join, but this server hasn't received it yet. Rejoin once to activate the boost."
				)
			end
			return
		end

		app.groupJoinPrompting = false
		if status == Enum.GroupMembershipStatus.JoinRequestPending then
			app.groupJoinPending = true
			refresh(app)
			app:_Track({ event = "GroupJoinPrompt", fields = { action = "REQUEST_PENDING" } })
			app:_Toast("info", "Join request sent. Tap Check membership here after the group approves it.")
		else
			refresh(app)
			app:_Track({ event = "GroupJoinPrompt", fields = { action = "CLOSED" } })
			app:_Toast("info", "The group window was closed. You can join whenever you're ready.")
		end
	end)
end

return GroupJoin
