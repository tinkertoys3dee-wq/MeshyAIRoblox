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
	local modal = Factory.ImageCard(overlay, UDim2.new(0.94, 0, 0.82, 0), UDim2.fromScale(0.5, 0.5), "StartGuide")
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.ZIndex = 351
	Factory.New("UISizeConstraint", { MaxSize = Vector2.new(510, 500), Parent = modal })
	-- Reflow and scroll on phones instead of shrinking text to unreadable
	-- sizes. Every starting path remains reachable in landscape too.
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
	text("YOUR FIRST LOOK, STEP BY STEP", 40, 1, true)
	text("We'll hide the extra tools and point to exactly one button at a time.", 38, 2)
	local path = Factory.New("Frame", {
		Name = "TutorialPath",
		Size = UDim2.new(1, 0, 0, 66),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		ZIndex = 353,
		Parent = content,
	})
	for index, caption in { "1\nPICK", "2\nCHANGE", "3\nSAVE" } do
		local node = Factory.New("Frame", {
			Size = UDim2.new(0.3, -4, 0, 58),
			Position = UDim2.new((index - 1) * 0.35, 0, 0, 0),
			BackgroundColor3 = if index == 1 then Theme.Colors.Gold else Theme.Colors.Panel,
			BackgroundTransparency = if index == 1 then 0.04 else 0.2,
			BorderSizePixel = 0,
			ZIndex = 353,
			Parent = path,
		})
		Factory.Corner(node, 10)
		Factory.Stroke(node, if index == 1 then Theme.Colors.Gold else Theme.Colors.Line, 0.2, 1.5)
		Factory.Label(node, caption, UDim2.fromScale(1, 1), {
			AlignX = Enum.TextXAlignment.Center,
			Wrapped = true,
			Font = Theme.Fonts.Black,
			TextSize = 11,
			Color = if index == 1 then Theme.Colors.Ink else Theme.Colors.Text,
			ZIndex = 354,
		})
		if index < 3 then
			Factory.Label(path, "→", UDim2.new(0.05, 0, 0, 58), {
				Position = UDim2.new(index * 0.35 - 0.05, 0, 0, 0),
				AlignX = Enum.TextXAlignment.Center,
				Font = Theme.Fonts.Black,
				TextSize = 18,
				Color = Theme.Colors.Gold,
				ZIndex = 354,
			})
		end
	end
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
			app.makeoverGuideRequested = choice == "START_FREE"
			if choice == "START_FREE" then
				local previous = app.state.makeoverState or {}
				local sprintOk, sprint = app:_Invoke(Network.Actions.StartStyleSprint, {
					restart = previous.completed == true or previous.dailyCompleted == true,
				})
				if sprintOk then
					app.state.makeoverState = sprint
				end
			end
			app:_Toast(
				"info",
				if choice == "START_FREE"
					then "Guided makeover ready—follow the gold arrow."
					else if choice == "MAKE_OWN" then "Opening the custom UGC creator." else "Opening the Arcade."
			)
			app.state.profile.tutorialVersion = Config.Tutorial.Version
			app.state.profile.onboarding.completed = true
			app:_CloseModal(overlay, modal, function()
				app.tutorialOverlay = nil
				if destination == "ARCADE" then
					app:_SetStudioOpen(false)
					GamesHub.Show(app)
				else
					app:_SetStudioOpen(true)
					app.scrollPositions[if destination == "Avatar Lab" then "AvatarLabWorkspace" else "Create"] =
						Vector2.zero
					app:_OpenPage(destination)
				end
			end)
		end)
	end
	local start = Factory.ImageButton(content, "START GUIDED MAKEOVER", UDim2.new(1, 0, 0, 50), nil, "primary")
	start.Name = "StartGuidedMakeover"
	start.TextSize = 14
	start.LayoutOrder = 4
	start.ZIndex = 353
	app:_BindButton(start)
	start.Activated:Connect(function()
		choose("START_FREE", "Avatar Lab")
	end)
	table.insert(controls, start)
	local alternatives = Factory.New("Frame", {
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		ZIndex = 353,
		Parent = content,
	})
	local custom = Factory.ImageButton(alternatives, "Custom UGC", UDim2.new(0.5, -5, 1, 0), nil, "mint")
	custom.TextSize = 11
	custom.ZIndex = 353
	app:_BindButton(custom)
	custom.Activated:Connect(function()
		choose("MAKE_OWN", "Create")
	end)
	table.insert(controls, custom)
	local arcade = Factory.ImageButton(alternatives, "Arcade", UDim2.new(0.5, -5, 1, 0), UDim2.new(0.5, 5, 0, 0))
	arcade.TextSize = 11
	arcade.ZIndex = 353
	app:_BindButton(arcade)
	arcade.Activated:Connect(function()
		choose("SKIP", "ARCADE")
	end)
	table.insert(controls, arcade)
	text(
		string.format(
			"Catalog makeover: free to preview. Custom AI generation starts at R$ %d; there is no free first generation.",
			app.state.prices.DirectGeneration
		),
		48,
		6
	)
	if not app.visualTutorialShown then
		app.visualTutorialShown = true
		app:_Track({ event = "VisualTutorialShown" })
	end
	app:_AnimateModalIn(overlay, modal)
	GuiService.SelectedObject = controls[1]
end

return StartGuide
