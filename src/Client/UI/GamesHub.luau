--!strict

-- The Arcade: a separate entry point from Forge Studio (see App:_BuildChrome's
-- "🎮 Arcade" launcher) that opens a small selection of client-only minigames
-- for session fun, plus the weekly top-3 token payout described in
-- Config.Arcade. Built and destroyed fresh each time it's opened, the same
-- way App:_ShowLeaderboard already works, rather than kept as persistent
-- chrome -- there's nothing here that needs to survive being closed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local Factory = require(script.Parent.Factory)
local GameShell = require(script.Parent.Games.GameShell)
local FlappyBird = require(script.Parent.Games.FlappyBird)
local DinoRunner = require(script.Parent.Games.DinoRunner)
local ColorSwitch = require(script.Parent.Games.ColorSwitch)

local Colors = Theme.Colors

-- Each tile deliberately isn't a uniform grid cell -- different sizes and a
-- hand-placed offset per tile is what makes this read as an arcade cabinet
-- lineup rather than a settings list. `wide` positions/sizes apply above the
-- compact breakpoint; compact always stacks full-width instead, since
-- overlapping absolute offsets on a narrow phone screen would just collide.
local TILES = {
	{
		game = FlappyBird,
		color = Colors.Cyan,
		icon = "🐦",
		blurb = "Flap through the gap.",
		wide = { size = UDim2.fromOffset(240, 132), position = UDim2.fromOffset(8, 14) },
	},
	{
		game = DinoRunner,
		color = Colors.Mint,
		icon = "🦖",
		blurb = "Jump the cacti.",
		wide = { size = UDim2.fromOffset(196, 108), position = UDim2.fromOffset(84, 168) },
	},
	{
		game = ColorSwitch,
		color = Colors.Rose,
		icon = "🎨",
		blurb = "Match your color.",
		wide = { size = UDim2.fromOffset(216, 120), position = UDim2.fromOffset(280, 292) },
	},
}

local GamesHub = {}

-- `app` needs: .gui, .sounds, .compact, :_Invoke(action, payload), :_BindButton(button).
function GamesHub.Show(app: any)
	local reduceMotion = app.state ~= nil and app.state.profile.settings.reduceMotion == true

	local overlay = Factory.New("Frame", {
		Name = "ArcadeOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = if reduceMotion then 0.2 else 1,
		BorderSizePixel = 0,
		ZIndex = 210,
		Parent = app.gui,
	})

	local restingModalPosition = UDim2.fromScale(0.5, 0.5)
	local modal = Factory.Card(
		overlay,
		UDim2.new(1, -32, 0, 520),
		if reduceMotion then restingModalPosition else restingModalPosition + UDim2.fromOffset(0, 18),
		"ArcadeModal"
	)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.ZIndex = 211
	modal.ClipsDescendants = true
	Factory.New("UISizeConstraint", {
		MaxSize = Vector2.new(560, 520),
		Parent = modal,
	})

	-- A quick fade-and-rise entrance -- skipped under reduceMotion, where
	-- both the overlay and modal are simply created at their final resting
	-- state above instead of animated into it.
	if not reduceMotion then
		TweenService:Create(overlay, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.2,
		}):Play()
		TweenService:Create(modal, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = restingModalPosition,
		}):Play()
	end

	-- This modal is parented to app.gui, a sibling of the scaled `shell` (not
	-- inside it), so it does NOT inherit App's own UIScale automatically --
	-- without this it would stay stuck at 1x for players who picked a larger
	-- UI scale for readability. Registered on `app` so the Settings page's
	-- scale chips can keep it live while the Arcade is open; cleared below
	-- when the modal closes.
	local uiScale = Factory.New("UIScale", {
		Scale = if app.state then tonumber(app.state.profile.settings.uiScale) or 1 else 1,
		Parent = modal,
	})
	app.arcadeUiScale = uiScale

	Factory.Pill(modal, "ARCADE", Colors.Rose, 100).Position = UDim2.fromOffset(16, 16)
	Factory.Label(
		modal,
		"Top 3 each game get a Forge Token bonus every week — 1st +450, 2nd +250, 3rd +100.",
		UDim2.new(1, -140, 0, 34),
		{
			Position = UDim2.fromOffset(16, 46),
			Color = Colors.TextMuted,
			TextSize = 11,
			Wrapped = true,
			ZIndex = 212,
		}
	)
	local closeButton = Factory.Button(modal, "×", UDim2.fromOffset(34, 34), UDim2.new(1, -50, 0, 14), nil)
	closeButton.ZIndex = 213
	app:_BindButton(closeButton)

	-- The hub view (tile picker) and the game view (GameShell) share the
	-- same footprint and are swapped by visibility rather than both existing
	-- on screen -- picking a game replaces the picker, Exit brings it back.
	local hubView = Factory.New("Frame", {
		Name = "HubView",
		Position = UDim2.fromOffset(12, 92),
		Size = UDim2.new(1, -24, 1, -104),
		BackgroundTransparency = 1,
		ZIndex = 212,
		Parent = modal,
	})
	local gameView = Factory.New("Frame", {
		Name = "GameView",
		Position = UDim2.fromOffset(12, 92),
		Size = UDim2.new(1, -24, 1, -104),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 212,
		Parent = modal,
	})

	local function submitScore(gameKey: string, score: number)
		task.spawn(function()
			app:_Invoke(Network.Actions.SubmitArcadeScore, { game = gameKey, score = score })
		end)
	end

	local function fetchWeeklyTop(gameKey: string): { GameShell.WeeklyStanding }?
		local success, result = app:_Invoke(Network.Actions.GetArcadeLeaderboard, { game = gameKey })
		if success and type(result) == "table" and type(result.standings) == "table" then
			return result.standings
		end
		return nil
	end

	local shell: any = nil

	local function showHub()
		hubView.Visible = true
		gameView.Visible = false
		if shell then
			shell:Stop()
		end
	end

	local function playGame(gameModule: GameShell.GameModule)
		if not shell then
			shell = GameShell.new(gameView, app.sounds, showHub, submitScore, fetchWeeklyTop, reduceMotion)
		end
		hubView.Visible = false
		gameView.Visible = true
		shell:Run(gameModule)
	end

	closeButton.Activated:Connect(function()
		app.sounds:Play("PanelClose")
		if shell then
			shell:Destroy()
		end
		app.arcadeUiScale = nil
		overlay:Destroy()
	end)

	for index, tile in TILES do
		local useWide = not app.compact
		local size = if useWide then tile.wide.size else UDim2.new(1, 0, 0, 84)
		local position = if useWide then tile.wide.position else UDim2.fromOffset(0, (index - 1) * 92)

		local button = Factory.New("TextButton", {
			Name = tile.game.Key,
			Size = size,
			Position = position,
			BackgroundColor3 = tile.color,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 213,
			Parent = hubView,
		})
		Factory.Corner(button, 18)
		Factory.Stroke(button, Colors.Ink, 0.5, 1.5)
		local tileScale = Factory.New("UIScale", { Scale = 1, Parent = button })
		Factory.Label(button, tile.icon, UDim2.fromOffset(40, 40), {
			Position = UDim2.fromOffset(14, 12),
			TextSize = 28,
			AlignX = Enum.TextXAlignment.Left,
			ZIndex = 214,
		})
		Factory.Label(button, tile.game.Name, UDim2.new(1, -28, 0, 24), {
			Position = UDim2.fromOffset(14, 54),
			Font = Theme.Fonts.Black,
			TextSize = 16,
			Color = Colors.Ink,
			AlignX = Enum.TextXAlignment.Left,
			ZIndex = 214,
		})
		Factory.Label(button, tile.blurb, UDim2.new(1, -28, 0, 18), {
			Position = UDim2.fromOffset(14, 78),
			Font = Theme.Fonts.Medium,
			TextSize = 11,
			Color = Colors.Ink,
			TextTransparency = 0.25,
			AlignX = Enum.TextXAlignment.Left,
			ZIndex = 214,
		})
		app.sounds:Bind(button)
		button.Selectable = true
		button.Activated:Connect(function()
			if not reduceMotion then
				tileScale.Scale = 0.92
				TweenService
					:Create(
						tileScale,
						TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Scale = 1 }
					)
					:Play()
			end
			playGame(tile.game)
		end)
	end
end

return GamesHub
