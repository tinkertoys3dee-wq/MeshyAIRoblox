--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Factory)
local Motion = require(script.Parent.Motion)

local StartGuide = {}

-- The first screen is a choice, not a lesson. Players learn each tool after
-- choosing it; making an eight-year-old read the entire product manual before
-- they can act was exactly the problem this guide is meant to solve.
function StartGuide.Show(app: any)
	if not app.state or (app.tutorialOverlay and app.tutorialOverlay.Parent) then
		return
	end
	local overlay = Factory.New("Frame", {
		Name = "ChooseStart",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 350,
		Parent = app.gui,
	})
	app.tutorialOverlay = overlay
	local modal = Factory.ImageCard(overlay, UDim2.new(0.94, 0, 0.78, 0), UDim2.fromScale(0.5, 0.5), "StartGuide")
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.ZIndex = 351
	Factory.New("UISizeConstraint", { MaxSize = Vector2.new(520, 460), Parent = modal })
	local scroll = Factory.New("ScrollingFrame", {
		Size = UDim2.new(1, -36, 1, -36),
		Position = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 352,
		Parent = modal,
	})
	local content = Factory.New("Frame", {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 352,
		Parent = scroll,
	})
	Factory.List(content, Enum.FillDirection.Vertical, 10)
	local title = Factory.Label(content, "WHAT DO YOU WANT TO DO?", UDim2.new(1, 0, 0, 34), {
		Font = Theme.Fonts.Black,
		TextSize = 23,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 353,
	})
	title.LayoutOrder = 1
	local subtitle = Factory.Label(content, "Pick one. You can change your mind anytime.", UDim2.new(1, 0, 0, 24), {
		Color = Theme.Colors.TextMuted,
		TextSize = 13,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 353,
	})
	subtitle.LayoutOrder = 2

	local busy = false
	local controls = {} :: { TextButton }
	local function choose(choice: string, destination: string)
		if busy then
			return
		end
		busy = true
		for _, control in controls do
			control.Active = false
		end
		task.spawn(function()
			local ok = app:_Invoke(Network.Actions.CompleteTutorial, { choice = choice })
			if not ok then
				busy = false
				for _, control in controls do
					control.Active = true
				end
				return
			end
			app.makeoverGuideRequested = choice == "START_FREE"
			app.customUGCGuideRequested = false
			if choice == "MAKE_OWN" then
				app.customUGCGuideDismissed = true
			end
			if choice == "START_FREE" then
				local previous = app.state.makeoverState or {}
				local sprintOk, sprint = app:_Invoke(Network.Actions.StartStyleSprint, {
					restart = previous.completed == true or previous.dailyCompleted == true,
				})
				if sprintOk then
					app.state.makeoverState = sprint
				end
			end
			app.state.profile.tutorialVersion = Config.Tutorial.Version
			app.state.profile.onboarding.completed = true
			app:_CloseModal(overlay, modal, function()
				app.tutorialOverlay = nil
				app:_SetStudioOpen(true)
				app.scrollPositions[if destination == "Avatar Lab" then "AvatarLabWorkspace" else destination] =
					Vector2.zero
				app:_OpenPage(destination)
				app:_Toast(
					"info",
					if choice == "START_FREE"
						then "Try any catalog item for free. Nothing is bought unless you choose Buy."
						else if choice == "MAKE_OWN"
							then "Type one idea. Roblox shows the price before anything starts."
							else "Pick a game—your creations can keep building while you play."
				)
			end)
		end)
	end

	local options = {
		{
			choice = "START_FREE",
			destination = "Avatar Lab",
			title = "STYLE MY AVATAR · FREE",
			body = "Try catalog clothes and accessories on your own avatar.",
			kind = "primary",
		},
		{
			choice = "MAKE_OWN",
			destination = "Create",
			title = "MAKE MY OWN ITEM",
			body = string.format(
				"Describe it, see the R$ %d price, then AI builds it.",
				app.state.prices.DirectGeneration
			),
			kind = "mint",
		},
		{
			choice = "SKIP",
			destination = "Play",
			title = "PLAY GAMES · FREE",
			body = "Arcade games, Runway battles, and the AFK token lounge.",
			kind = nil,
		},
	}
	for index, option in options do
		local compact = app.compact == true
		local card = Factory.ImageCard(content, UDim2.new(1, 0, 0, if compact then 128 else 88), nil, "StartChoice")
		card.LayoutOrder = 2 + index
		card.ZIndex = 353
		Factory.Label(card, option.body, UDim2.new(1, if compact then -32 else -190, 0, if compact then 44 else 68), {
			Position = UDim2.fromOffset(16, 10),
			Color = Theme.Colors.TextMuted,
			TextSize = 12,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 354,
		})
		local control = Factory.ImageButton(
			card,
			option.title,
			if compact then UDim2.new(1, -32, 0, 42) else UDim2.fromOffset(166, 48),
			if compact then UDim2.fromOffset(16, 74) else UDim2.new(1, -180, 0.5, -24),
			option.kind
		)
		control.TextSize = 11
		control.ZIndex = 354
		app:_BindButton(control)
		control.Activated:Connect(function()
			choose(option.choice, option.destination)
		end)
		table.insert(controls, control)
	end
	if not app.visualTutorialShown then
		app.visualTutorialShown = true
		app:_Track({ event = "VisualTutorialShown" })
	end
	app:_AnimateModalIn(overlay, modal)
	Motion.AutoFocus(controls[1])
end

return StartGuide
