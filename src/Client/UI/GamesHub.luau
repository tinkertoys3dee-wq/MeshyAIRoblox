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

local function lighten(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + amount, 0, 1))
end

local function darken(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v - amount, 0, 1))
end

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
		blurb = "Bounce through the right color.",
		wide = { size = UDim2.fromOffset(216, 120), position = UDim2.fromOffset(280, 292) },
	},
}

local GamesHub = {}

-- `app` needs: .gui, .sounds, .compact, .state, :_Invoke(action, payload), :_BindButton(button).
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
	-- A console-style accent strip along the very top edge -- a small frame
	-- detail that reads as "this modal has a top", the same idea a game
	-- cabinet's marquee light gives it.
	local topAccent = Factory.New("Frame", {
		Name = "TopAccent",
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Colors.Rose,
		BorderSizePixel = 0,
		ZIndex = 212,
		Parent = modal,
	})
	Factory.Gradient(topAccent, { Colors.Rose, Colors.Gold, Colors.Cyan, Colors.Mint }, 0)

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

	-- A soft, static (non-animated -- cheap and reduceMotion-safe by
	-- construction) glow behind the header for depth, the same trick the
	-- app's own background layer uses elsewhere.
	local glow = Factory.New("Frame", {
		Name = "HeaderGlow",
		Size = UDim2.fromOffset(360, 200),
		Position = UDim2.fromOffset(-60, -90),
		BackgroundColor3 = Colors.Rose,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		ZIndex = 211,
		Parent = modal,
	})
	Factory.Corner(glow, 120)

	local headerIcon = Factory.New("Frame", {
		Name = "HeaderIcon",
		Size = UDim2.fromOffset(52, 52),
		Position = UDim2.fromOffset(16, 14),
		BackgroundColor3 = Colors.Rose,
		BorderSizePixel = 0,
		ZIndex = 213,
		Parent = modal,
	})
	Factory.Corner(headerIcon, 16)
	Factory.Gradient(headerIcon, { lighten(Colors.Rose, 0.08), darken(Colors.Rose, 0.12) }, 120)
	Factory.Stroke(headerIcon, Colors.Ink, 0.5, 1.5)
	Factory.Label(headerIcon, "🕹️", UDim2.fromScale(1, 1), {
		TextSize = 26,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
		ZIndex = 214,
	})

	Factory.Label(modal, "ARCADE", UDim2.new(1, -220, 0, 24), {
		Position = UDim2.fromOffset(78, 12),
		Font = Theme.Fonts.Black,
		TextSize = 22,
		Color = Colors.Text,
		AlignX = Enum.TextXAlignment.Left,
		Truncate = Enum.TextTruncate.AtEnd,
		ZIndex = 213,
	})
	Factory.Label(modal, "Three games, one weekly leaderboard.", UDim2.new(1, -220, 0, 18), {
		Position = UDim2.fromOffset(78, 38),
		Font = Theme.Fonts.Medium,
		TextSize = 12,
		Color = Colors.TextMuted,
		AlignX = Enum.TextXAlignment.Left,
		Truncate = Enum.TextTruncate.AtEnd,
		ZIndex = 213,
	})

	local rewardBanner = Factory.New("Frame", {
		Name = "RewardBanner",
		Size = UDim2.new(1, -32, 0, 30),
		Position = UDim2.fromOffset(16, 74),
		BackgroundColor3 = Colors.Gold,
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		ZIndex = 212,
		Parent = modal,
	})
	Factory.Corner(rewardBanner, 10)
	Factory.Stroke(rewardBanner, Colors.Gold, 0.65, 1)
	Factory.Label(
		rewardBanner,
		"🏆  Top 3 each game get a weekly Forge Token bonus — 1st +450 · 2nd +250 · 3rd +100",
		UDim2.new(1, -20, 1, 0),
		{
			Position = UDim2.fromOffset(10, 0),
			Color = Colors.Gold,
			Font = Theme.Fonts.Medium,
			TextSize = 11,
			Truncate = Enum.TextTruncate.AtEnd,
			ZIndex = 213,
		}
	)

	local closeButton = Factory.New("TextButton", {
		Name = "CloseButton",
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(1, -50, 0, 14),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "×",
		TextColor3 = Colors.Text,
		Font = Theme.Fonts.Black,
		TextSize = 20,
		ZIndex = 214,
		Parent = modal,
	})
	Factory.Corner(closeButton, 17)
	Factory.Stroke(closeButton, Colors.Line, 0.5, 1.5)
	app:_BindButton(closeButton)

	-- The hub view (tile picker) and the game view (GameShell) share the
	-- same footprint and are swapped by visibility rather than both existing
	-- on screen -- picking a game replaces the picker, Exit brings it back.
	local hubView = Factory.New("Frame", {
		Name = "HubView",
		Position = UDim2.fromOffset(12, 116),
		Size = UDim2.new(1, -24, 1, -128),
		BackgroundTransparency = 1,
		ZIndex = 212,
		Parent = modal,
	})
	local gameView = Factory.New("Frame", {
		Name = "GameView",
		Position = UDim2.fromOffset(12, 116),
		Size = UDim2.new(1, -24, 1, -128),
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

	local function fetchWeeklyTop(gameKey: string): GameShell.WeeklyResult?
		local success, result = app:_Invoke(Network.Actions.GetArcadeLeaderboard, { game = gameKey })
		if success and type(result) == "table" and type(result.standings) == "table" then
			return { standings = result.standings, self = result.self }
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
		local tileHeight = size.Y.Offset

		-- A soft drop shadow: a darker duplicate sat behind and slightly
		-- offset from the tile itself, the cheapest way to fake elevation
		-- with plain Frames.
		local shadow = Factory.New("Frame", {
			Name = "Shadow",
			Size = size,
			Position = position + UDim2.fromOffset(0, 5),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			ZIndex = 212,
			Parent = hubView,
		})
		Factory.Corner(shadow, 18)

		local button = Factory.New("TextButton", {
			Name = tile.game.Key,
			Size = size,
			Position = position,
			BackgroundColor3 = tile.color,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ClipsDescendants = true,
			ZIndex = 213,
			Parent = hubView,
		})
		Factory.Corner(button, 18)
		Factory.Stroke(button, Colors.Ink, 0.45, 1.5)
		Factory.Gradient(button, { lighten(tile.color, 0.1), darken(tile.color, 0.16) }, 130)
		local gloss = Factory.New("Frame", {
			Name = "Gloss",
			Size = UDim2.new(1, -2, 0, math.min(30, tileHeight * 0.3)),
			Position = UDim2.fromOffset(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.85,
			BorderSizePixel = 0,
			ZIndex = 214,
			Parent = button,
		})
		Factory.Corner(gloss, 17)
		local tileScale = Factory.New("UIScale", { Scale = 1, Parent = button })

		local iconBadge = Factory.New("Frame", {
			Name = "IconBadge",
			Size = UDim2.fromOffset(38, 38),
			Position = UDim2.fromOffset(12, 10),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 215,
			Parent = button,
		})
		Factory.Corner(iconBadge, 12)
		Factory.Label(iconBadge, tile.icon, UDim2.fromScale(1, 1), {
			TextSize = 20,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 216,
		})

		-- A bottom scrim so the title/blurb stay legible in light text no
		-- matter how bright the tile's own accent color is, the same trick a
		-- media/game-store card uses over a busy thumbnail.
		local scrimHeight = math.max(40, tileHeight * 0.42)
		local scrim = Factory.New("Frame", {
			Name = "Scrim",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, scrimHeight),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 215,
			Parent = button,
		})
		Factory.New("UIGradient", {
			Color = ColorSequence.new(Colors.Ink),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0.22),
			}),
			Rotation = 90,
			Parent = scrim,
		})

		Factory.Label(scrim, tile.game.Name, UDim2.new(1, -50, 0, 20), {
			Position = UDim2.fromOffset(14, scrimHeight - 36),
			Font = Theme.Fonts.Black,
			TextSize = 15,
			Color = Colors.Text,
			AlignX = Enum.TextXAlignment.Left,
			Truncate = Enum.TextTruncate.AtEnd,
			ZIndex = 216,
		})
		Factory.Label(scrim, tile.blurb, UDim2.new(1, -50, 0, 16), {
			Position = UDim2.fromOffset(14, scrimHeight - 17),
			Font = Theme.Fonts.Medium,
			TextSize = 10,
			Color = Colors.TextMuted,
			AlignX = Enum.TextXAlignment.Left,
			Truncate = Enum.TextTruncate.AtEnd,
			ZIndex = 216,
		})
		Factory.Label(scrim, "▶", UDim2.fromOffset(22, 22), {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -10, 1, -8),
			TextSize = 13,
			Color = Colors.Text,
			Transparency = 0.35,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 216,
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
