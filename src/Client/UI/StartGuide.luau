--!strict

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Factory)
local GamesHub = require(script.Parent.GamesHub)

local StartGuide = {}

function StartGuide.Show(app: any)
	if not app.state or (app.tutorialOverlay and app.tutorialOverlay.Parent) then
		return
	end
	local overlay = Factory.New("Frame", {
		Name = "HowToPlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 350,
		Parent = app.gui,
	})
	app.tutorialOverlay = overlay
	local modal = Factory.ImageCard(overlay, UDim2.new(0.94, 0, 0.92, 0), UDim2.fromScale(0.5, 0.5), "StartGuide")
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.ZIndex = 351
	Factory.New("UISizeConstraint", { MaxSize = Vector2.new(510, 600), Parent = modal })
	-- Reflow and scroll on phones instead of shrinking text to unreadable
	-- sizes. Every path and Skip remains reachable in landscape too.
	local scroll = Factory.New("ScrollingFrame", {
		Size = UDim2.new(1, -40, 1, -40),
		Position = UDim2.fromOffset(20, 20),
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
	Factory.List(content, Enum.FillDirection.Vertical, 12)
	local function text(value: string, height: number, order: number, large: boolean?)
		local item = Factory.Label(content, value, UDim2.new(1, 0, 0, height), {
			TextSize = if large then 23 else 14,
			Wrapped = true,
			Font = if large then Theme.Fonts.Black else Theme.Fonts.Regular,
			AutomaticSize = Enum.AutomaticSize.Y,
			AlignX = Enum.TextXAlignment.Center,
			ZIndex = 353,
		})
		item.LayoutOrder = order
	end
	text("YOUR LOOK. YOUR CREATION.", 42, 1, true)
	text("Create a custom item, style an avatar, or play. Pick what you came for.", 44, 2)
	text(
		"1  Describe an item and confirm the price.\n2  Fit the finished item in My Studio.\n3  Wear it here. Publishing is a separate Roblox step.",
		76,
		3
	)
	local busy = false
	local controls = {}
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
			app.state.profile.tutorialVersion = Config.Tutorial.Version
			app.state.profile.onboarding.completed = true
			app:_CloseModal(overlay, modal, function()
				app.tutorialOverlay = nil
				if destination == "ARCADE" then
					app:_SetStudioOpen(false)
					GamesHub.Show(app)
				else
					app:_SetStudioOpen(true)
					app.scrollPositions.Create = Vector2.zero
					app:_OpenPage(destination)
				end
			end)
		end)
	end
	for index, route in
		{
			{ "MAKE MY OWN ITEM", "MAKE_OWN", "Create", "primary" },
			{ "STYLE MY AVATAR · FREE TO TRY", "START_FREE", "Avatar Lab", "mint" },
			{ "PLAY THE ARCADE", "SKIP", "ARCADE", "default" },
		}
	do
		local control = Factory.ImageButton(content, route[1], UDim2.new(1, 0, 0, 46), nil, route[4])
		control.TextSize = 13
		control.LayoutOrder = 3 + index
		control.ZIndex = 353
		control.Activated:Connect(function()
			choose(route[2], route[3])
		end)
		table.insert(controls, control)
	end
	text(
		string.format(
			"Custom generation starts at R$ %d. No free first generation. Roblox asks before charging; catalog try-ons are free, ownership is separate.",
			app.state.prices.DirectGeneration
		),
		62,
		7
	)
	local skip = Factory.Button(content, "Skip guide", UDim2.new(1, 0, 0, 34))
	skip.LayoutOrder = 8
	skip.ZIndex = 353
	skip.Activated:Connect(function()
		choose("SKIP", "Create")
	end)
	table.insert(controls, skip)
	if not app.visualTutorialShown then
		app.visualTutorialShown = true
		app:_Track({ event = "VisualTutorialShown" })
	end
	app:_AnimateModalIn(overlay, modal)
	GuiService.SelectedObject = controls[1]
end

return StartGuide
