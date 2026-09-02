--!strict

-- The Arcade: a separate entry point from Forge Studio (see App:_BuildChrome's
-- "🎮 Arcade" launcher) that opens a small selection of client-only minigames
-- for session fun, plus the weekly top-3 token payout described in
-- Config.Arcade. Built and destroyed fresh each time it's opened, the same
-- way App:_ShowLeaderboard already works, rather than kept as persistent
-- chrome -- there's nothing here that needs to survive being closed.
--
-- Three views share the same footprint below the header and are swapped by
-- visibility: the tile picker (hubView), a running game (gameView), and the
-- standalone leaderboard (leaderboardView) -- added because the in-game
-- standings panel only ever shows while you're mid-run, which isn't useful
-- for just checking where you stand. The leaderboard tab works without
-- starting a game at all.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local DailyChallenge = require(ReplicatedStorage:WaitForChild("DailyChallenge"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local Factory = require(script.Parent.Factory)
local GameShell = require(script.Parent.Games.GameShell)
local FlappyBird = require(script.Parent.Games.FlappyBird)
local DinoRunner = require(script.Parent.Games.DinoRunner)
local ColorSwitch = require(script.Parent.Games.ColorSwitch)
local NeonSnake = require(script.Parent.Games.NeonSnake)
local BlockStacker = require(script.Parent.Games.BlockStacker)
local BrickBreaker = require(script.Parent.Games.BrickBreaker)
local ReflexTap = require(script.Parent.Games.ReflexTap)
local PrismMerge = require(script.Parent.Games.PrismMerge)
local MeteorRush = require(script.Parent.Games.MeteorRush)
local SkyHopper = require(script.Parent.Games.SkyHopper)
local EchoMatch = require(script.Parent.Games.EchoMatch)

local Colors = Theme.Colors

local function lighten(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + amount, 0, 1))
end

local function darken(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v - amount, 0, 1))
end

local GAMES = {
	{
		game = FlappyBird,
		color = Colors.Cyan,
		icon = "🐦",
		blurb = "Flap through the gap.",
	},
	{
		game = DinoRunner,
		color = Colors.Mint,
		icon = "🦖",
		blurb = "Jump the cacti.",
	},
	{
		game = ColorSwitch,
		color = Colors.Rose,
		icon = "🎨",
		blurb = "Bounce through the right color.",
	},
	{
		game = NeonSnake,
		color = Colors.Violet,
		icon = "🐍",
		blurb = "Grow without biting yourself.",
	},
	{
		game = BlockStacker,
		color = Colors.Danger,
		icon = "🧱",
		blurb = "Stack it straight, don't miss.",
	},
	{
		game = BrickBreaker,
		color = Color3.fromRGB(255, 149, 66),
		icon = "🏓",
		blurb = "Steer the paddle, clear the bricks.",
	},
	{
		game = ReflexTap,
		color = Color3.fromRGB(45, 205, 196),
		icon = "🎯",
		blurb = "Tap the lit tile before it's gone.",
	},
	{
		game = PrismMerge,
		color = Color3.fromRGB(116, 92, 255),
		icon = "🔷",
		blurb = "Merge prisms and chase huge chains.",
	},
	{
		game = MeteorRush,
		color = Color3.fromRGB(44, 196, 255),
		icon = "🚀",
		blurb = "Dodge meteors, collect cores, go hyper.",
	},
	{
		game = SkyHopper,
		color = Color3.fromRGB(120, 200, 255),
		icon = "☁️",
		blurb = "Bounce ever higher, don't fall behind.",
	},
	{
		game = EchoMatch,
		color = Colors.Gold,
		icon = "🔔",
		blurb = "Watch the pattern, echo it back.",
	},
}

local TILE_SIZE = UDim2.fromOffset(248, 172)
local COMPACT_TILE_SIZE = UDim2.new(1, 0, 0, 84)
local COMPACT_TILE_HEIGHT = 92
-- Wide-mode tiles (#GAMES games + 1 Leaderboard tile) lay out into a fixed
-- 2-column grid computed from TILE_SIZE, rather than a hand-typed list of
-- offsets -- the previous hand-typed version overflowed the visible area
-- once the header grew and nobody re-checked the numbers; a computed grid
-- can't drift out of sync with GAMES's length the same way. `wide` applies
-- above the compact breakpoint; compact always stacks full-width instead
-- (see COMPACT_TILE_HEIGHT above).
local TILE_GRID_ORIGIN = Vector2.new(12, 12)
local TILE_GRID_GAP = 10
local TILE_GRID_COLUMNS = 2

local function wideTilePosition(index: number): UDim2
	local column = (index - 1) % TILE_GRID_COLUMNS
	local row = math.floor((index - 1) / TILE_GRID_COLUMNS)
	return UDim2.fromOffset(
		TILE_GRID_ORIGIN.X + column * (TILE_SIZE.X.Offset + TILE_GRID_GAP),
		TILE_GRID_ORIGIN.Y + row * (TILE_SIZE.Y.Offset + TILE_GRID_GAP)
	)
end

local GamesHub = {}

-- `app` needs: .gui, .sounds, .compact, .state, :_Invoke(action, payload),
-- :_Track(payload), :_BindButton(button).
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

	-- Height (702) is a target, not a hard requirement any more: hubView's
	-- content box is modal height - 128 (see hubView's Size below), and the
	-- wide-mode tile grid (12 tiles now: #GAMES games + 1 Leaderboard tile,
	-- computed by wideTilePosition above) is 6 rows -- 6*TILE_SIZE.Y +
	-- 5*TILE_GRID_GAP + a 26px bottom margin = 1104, taller than the 574 a
	-- 3-row grid needed when this number was first picked. Rather than
	-- rechase this comment's math every time Config.Arcade.Games grows,
	-- hubView is a genuine ScrollingFrame (see below): 702 (the MaxSize
	-- clamp below, and what any normal desktop window actually renders at)
	-- just no longer needs to be tall enough to fit every row at once, and
	-- neither does a shorter viewport once the modal's own scale-based
	-- height (not the old fixed `0, 702` offset, which simply rendered past
	-- the top/bottom of any shorter viewport with nothing to stop it)
	-- shrinks to fit it.
	local restingModalPosition = UDim2.fromScale(0.5, 0.5)
	local modal = Factory.ImageCard(
		overlay,
		UDim2.new(1, -32, 0.94, -16),
		if reduceMotion then restingModalPosition else restingModalPosition + UDim2.fromOffset(0, 18),
		"ArcadeModal"
	)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.ZIndex = 211
	modal.ClipsDescendants = true
	-- MaxSize width matches the compact breakpoint (App.luau: width < 760 is
	-- compact) so `useWide` below and this modal's actual rendered width
	-- agree: whenever tiles render in wide mode, the screen is already wide
	-- enough that this 560 cap -- not the screen -- is what's actually
	-- limiting the modal, so its width is reliably exactly 560px, not just
	-- "usually about that". The tile grid below is sized against that fixed
	-- number, not a guess. MinSize keeps the modal from shrinking past a
	-- usable floor on a genuinely tiny viewport -- GameShell's own game-over
	-- card needs at least this much canvas height to avoid clipping (see its
	-- own comment), and hubView's scrolling picks up whatever room is left.
	Factory.New("UISizeConstraint", {
		MinSize = Vector2.new(300, 420),
		MaxSize = Vector2.new(560, 702),
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

	-- A handful of faint drifting motes across the whole modal -- ambient
	-- texture, not a focal effect, echoing the same idea as the app's own
	-- ember system elsewhere. Individual looping tweens rather than a
	-- Heartbeat connection: they harmlessly stop doing anything the moment
	-- their particle is destroyed with the rest of the modal, no manual
	-- disconnect required on close.
	if not reduceMotion then
		local ambientLayer = Factory.New("Frame", {
			Name = "AmbientLayer",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 211,
			Parent = modal,
		})
		for _ = 1, 7 do
			local size = 3 + math.random() * 4
			local particle = Factory.New("Frame", {
				Name = "Mote",
				Size = UDim2.fromOffset(size, size),
				Position = UDim2.new(math.random(), 0, math.random(), 0),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.78 + math.random() * 0.15,
				BorderSizePixel = 0,
				ZIndex = 211,
				Parent = ambientLayer,
			})
			Factory.Corner(particle, size / 2)
			local driftX = math.random(-16, 16)
			local driftY = 18 + math.random() * 24
			TweenService:Create(
				particle,
				TweenInfo.new(
					3 + math.random() * 2.5,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut,
					-1,
					true,
					math.random() * 2.5
				),
				{ Position = particle.Position + UDim2.fromOffset(driftX, -driftY) }
			):Play()
		end
	end

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
	Factory.Label(modal, string.format("%d games, one weekly leaderboard.", #GAMES), UDim2.new(1, -220, 0, 18), {
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
	local rewards = Config.Arcade.WeeklyRewards
	Factory.Label(
		rewardBanner,
		string.format(
			"🏆  Top 3 each game get a weekly Forge Token bonus — 1st +%d · 2nd +%d · 3rd +%d",
			rewards[1],
			rewards[2],
			rewards[3]
		),
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

	-- Three views share the same footprint below the header and are swapped
	-- by visibility rather than all existing on screen at once. A
	-- ScrollingFrame (not a plain Frame) so the tile grid below -- laid out
	-- via fixed absolute offsets, not a UIListLayout -- scrolls into reach
	-- instead of silently overflowing past modal's ClipsDescendants whenever
	-- there isn't the full 574px of room the wide-mode grid was designed for
	-- (a short viewport, or the modal's own MinSize clamp above).
	local hubView = Factory.New("ScrollingFrame", {
		Name = "HubView",
		Position = UDim2.fromOffset(12, 116),
		Size = UDim2.new(1, -24, 1, -128),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.Rose,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 212,
		Parent = modal,
	})
	-- Starts 38px higher than hubView (reclaiming the reward banner's row,
	-- which showHub/playGame/showLeaderboardTab below hide outside the
	-- picker) so an actual game or the standings list gets more room than
	-- the tile picker needs to spend on a banner that's only relevant while
	-- choosing what to play.
	local gameView = Factory.New("Frame", {
		Name = "GameView",
		Position = UDim2.fromOffset(12, 78),
		Size = UDim2.new(1, -24, 1, -90),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 212,
		Parent = modal,
	})
	local leaderboardView = Factory.New("Frame", {
		Name = "LeaderboardView",
		Position = UDim2.fromOffset(12, 78),
		Size = UDim2.new(1, -24, 1, -90),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 212,
		Parent = modal,
	})

	-- A brief dip-to-dark covering just the content area (not the header,
	-- which stays interactive throughout) whenever the picker/game/
	-- leaderboard views swap -- cheaper and more robust than trying to
	-- cross-fade dozens of individual descendants across three very
	-- different view layouts. Sized to the taller of the two footprints
	-- (gameView/leaderboardView's, which start higher than hubView's) so it
	-- fully covers whichever view is swapping in or out.
	local transitionOverlay = Factory.New("Frame", {
		Name = "ViewTransition",
		Position = UDim2.fromOffset(12, 78),
		Size = UDim2.new(1, -24, 1, -90),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 218,
		Parent = modal,
	})
	local switchingView = false
	-- `applyVisibility` does the actual Visible swap (plus whatever other
	-- setup that view's switch-in function needs); wrapping it here just
	-- adds the fade around that swap.
	local function switchView(applyVisibility: () -> ())
		if reduceMotion then
			applyVisibility()
			return
		end
		if switchingView then
			applyVisibility()
			return
		end
		switchingView = true
		TweenService:Create(transitionOverlay, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0,
		}):Play()
		task.delay(0.12, function()
			if not transitionOverlay.Parent then
				return
			end
			applyVisibility()
			TweenService
				:Create(transitionOverlay, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					BackgroundTransparency = 1,
				})
				:Play()
			task.delay(0.18, function()
				switchingView = false
			end)
		end)
	end

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

	-- "Beat your friends" standings -- same shape as fetchWeeklyTop so
	-- renderLeaderboardStandings needs no scope-specific branching of its
	-- own, just a different data source and a different empty-state message.
	local function fetchFriendTop(gameKey: string): GameShell.WeeklyResult?
		local success, result = app:_Invoke(Network.Actions.GetFriendArcadeLeaderboard, { game = gameKey })
		if success and type(result) == "table" and type(result.standings) == "table" then
			return { standings = result.standings, self = result.self }
		end
		return nil
	end

	local shell: any = nil

	local function showHub()
		switchView(function()
			hubView.Visible = true
			gameView.Visible = false
			leaderboardView.Visible = false
			-- Only relevant while picking what to play; hiding it elsewhere
			-- gives gameView/leaderboardView the extra row they're sized for.
			rewardBanner.Visible = true
			if shell then
				shell:Stop()
			end
		end)
	end

	local function playGame(gameModule: GameShell.GameModule)
		switchView(function()
			hubView.Visible = false
			leaderboardView.Visible = false
			gameView.Visible = true
			rewardBanner.Visible = false
			if not shell then
				shell = GameShell.new(gameView, app.sounds, showHub, submitScore, fetchWeeklyTop, reduceMotion)
			end
			app:_Track({ event = "ArcadeGameStarted", fields = { game = gameModule.Key } })
			shell:Run(gameModule)
		end)
	end

	closeButton.Activated:Connect(function()
		app.sounds:Play("PanelClose")
		if shell then
			shell:Destroy()
		end
		app.arcadeUiScale = nil
		overlay:Destroy()
	end)

	-- ===== Leaderboard tab =====
	-- A back button plus a per-game tab row up top; standings for whichever
	-- tab is selected fill the rest, cached per game-key so switching tabs
	-- back and forth doesn't re-hit the network every time.

	local leaderboardBackShadow = Factory.New("Frame", {
		Name = "BackShadow",
		Size = UDim2.fromOffset(70, 28),
		Position = UDim2.fromOffset(0, 5),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = 212,
		Parent = leaderboardView,
	})
	Factory.Corner(leaderboardBackShadow, Theme.SmallCorner)
	local leaderboardBack = Factory.New("TextButton", {
		Name = "BackButton",
		Size = UDim2.fromOffset(70, 28),
		Position = UDim2.fromOffset(0, 3),
		BackgroundColor3 = Colors.PanelSoft,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "← Back",
		TextColor3 = Colors.Text,
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		ZIndex = 213,
		Parent = leaderboardView,
	})
	Factory.Corner(leaderboardBack, Theme.SmallCorner)
	Factory.Stroke(leaderboardBack, Colors.Line, 0.55)
	Factory.Gradient(leaderboardBack, {
		Color3.fromRGB(74, 82, 114),
		Color3.fromRGB(52, 58, 84),
	}, 120)
	app.sounds:Bind(leaderboardBack)
	leaderboardBack.Activated:Connect(showHub)

	-- Fixed-width chips inside a horizontal scroller stay readable as the
	-- Arcade grows. Squeezing every game into one scale-divided row made long
	-- names unreadable once the eighth and ninth games were added.
	local leaderboardTabs = Factory.New("ScrollingFrame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(80, 3),
		Size = UDim2.new(1, -80, 0, 28),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		ZIndex = 213,
		Parent = leaderboardView,
	})
	Factory.List(leaderboardTabs, Enum.FillDirection.Horizontal, 6)

	-- Global vs. Friends scope toggle -- a segmented control, same visual
	-- language as the game tabs below it (active = filled Cyan, inactive =
	-- dim outline), so the two rows read as one coherent header rather than
	-- two unrelated controls stacked on top of each other.
	local scopeToggle = Factory.New("Frame", {
		Name = "ScopeToggle",
		Position = UDim2.fromOffset(0, 37),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 213,
		Parent = leaderboardView,
	})
	Factory.Corner(scopeToggle, Theme.SmallCorner)
	Factory.Stroke(scopeToggle, Colors.Line, 0.6)

	local standingsHost = Factory.New("Frame", {
		Name = "StandingsHost",
		Position = UDim2.fromOffset(0, 71),
		Size = UDim2.new(1, 0, 1, -71),
		BackgroundColor3 = Colors.PanelRaised,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ZIndex = 212,
		Parent = leaderboardView,
	})
	Factory.Corner(standingsHost, 14)
	Factory.Stroke(standingsHost, Colors.Gold, 0.5)
	Factory.Gradient(standingsHost, {
		Color3.fromRGB(64, 72, 104),
		Color3.fromRGB(46, 52, 80),
	}, 115)

	local standingsList = Factory.New("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.new(1, -28, 1, -66),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Colors.Gold,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 213,
		Parent = standingsHost,
	})
	Factory.List(standingsList, Enum.FillDirection.Vertical, 8)
	Factory.New("Frame", {
		Name = "FooterDivider",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -44),
		Size = UDim2.new(1, -28, 0, 1),
		BackgroundColor3 = Colors.Gold,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		ZIndex = 213,
		Parent = standingsHost,
	})
	local selfStandingLabel = Factory.Label(standingsHost, "", UDim2.new(1, -28, 0, 36), {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -8),
		Color = Colors.TextMuted,
		Font = Theme.Fonts.Medium,
		TextSize = 12,
		Wrapped = true,
		ZIndex = 213,
	})

	local standingsCache: { [string]: GameShell.WeeklyResult } = {}
	local selectedGameKey = GAMES[1].game.Key
	local leaderboardScope: string = "global"
	local tabButtons: { [string]: TextButton } = {}
	local scopeButtons: { [string]: TextButton } = {}

	local function setActiveScope(scope: string)
		for key, button in scopeButtons do
			local active = key == scope
			button.BackgroundColor3 = if active then Colors.Cyan else Colors.PanelSoft
			button.BackgroundTransparency = if active then 0.1 else 0.7
			button.TextColor3 = if active then Colors.Ink else Colors.Text
		end
	end

	for i, entry in { { key = "global", label = "🌐 Global" }, { key = "friends", label = "👥 Friends" } } do
		local button = Factory.New("TextButton", {
			Name = entry.key .. "Scope",
			Position = UDim2.new((i - 1) / 2, if i == 1 then 3 else 2, 0, 3),
			Size = UDim2.new(0.5, if i == 1 then -5 else -5, 1, -6),
			BackgroundColor3 = Colors.PanelSoft,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = entry.label,
			TextColor3 = Colors.Text,
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			ZIndex = 214,
			Parent = scopeToggle,
		})
		Factory.Corner(button, Theme.SmallCorner - 2)
		app.sounds:Bind(button)
		scopeButtons[entry.key] = button
	end

	local function setActiveTab(gameKey: string)
		for key, tab in tabButtons do
			local active = key == gameKey
			tab.BackgroundTransparency = if active then 0.15 else 0.65
			tab.BackgroundColor3 = if active then Colors.Gold else Colors.PanelSoft
			tab.TextColor3 = if active then Colors.Ink else Colors.Text
		end
	end

	-- Same native prompt + eligibility check App.luau's own invite card uses;
	-- the reward itself is granted by App's existing
	-- SocialService.GameInvitePromptClosed listener, which fires regardless
	-- of which UI opened the prompt, so nothing extra needs wiring here.
	local function promptFriendInvite()
		local player = Players.LocalPlayer
		local checkSuccess, allowed = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if not checkSuccess or allowed ~= true then
			app:_Toast("error", "Invites aren't available for your account or platform right now.")
			return
		end
		local promptSuccess = pcall(function()
			SocialService:PromptGameInvite(player)
		end)
		if not promptSuccess then
			app:_Toast("error", "Roblox could not open the invite prompt.")
		end
	end

	local function renderLeaderboardStandings(result: GameShell.WeeklyResult, scope: string)
		for _, child in standingsList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local standings = result.standings
		if #standings == 0 then
			Factory.Label(
				standingsList,
				if scope == "friends"
					then "None of your friends have played this game yet."
					else "No scores yet this week — be the first to set one!",
				UDim2.new(1, 0, 0, 40),
				{
					Color = Colors.TextMuted,
					TextSize = 12,
					Wrapped = true,
					ZIndex = 214,
				}
			)
		end
		if scope == "friends" and #standings <= 1 then
			local inviteRow = Factory.New("Frame", {
				Size = UDim2.new(1, 0, 0, 44),
				LayoutOrder = 999,
				BackgroundTransparency = 1,
				Parent = standingsList,
			})
			Factory.Label(inviteRow, "Invite a friend to start a real rivalry.", UDim2.new(1, 0, 0, 18), {
				Color = Colors.TextMuted,
				TextSize = 11,
				AlignX = Enum.TextXAlignment.Center,
				ZIndex = 214,
			})
			local inviteButton = Factory.New("TextButton", {
				Size = UDim2.fromOffset(160, 22),
				Position = UDim2.new(0.5, -80, 0, 20),
				BackgroundColor3 = Colors.Mint,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "👥 Invite a friend",
				TextColor3 = Colors.Ink,
				Font = Theme.Fonts.Bold,
				TextSize = 11,
				ZIndex = 214,
				Parent = inviteRow,
			})
			Factory.Corner(inviteButton, 11)
			app.sounds:Bind(inviteButton)
			inviteButton.Activated:Connect(promptFriendInvite)
		end
		local medals = { "🥇", "🥈", "🥉" }
		local rankColors = { Colors.Gold, Color3.fromRGB(200, 208, 224), Color3.fromRGB(214, 158, 100) }
		local localUserId = Players.LocalPlayer and Players.LocalPlayer.UserId
		for rank, entry in standings do
			local isSelf = entry.userId == localUserId
			local rankColor = rankColors[rank]
			local rowColor = if isSelf then Colors.Gold elseif rankColor then rankColor else nil
			local finalTransparency = if isSelf then 0.85 elseif rankColor then 0.9 else 1
			local row = Factory.New("Frame", {
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundColor3 = rowColor or Colors.Gold,
				BackgroundTransparency = if reduceMotion then finalTransparency else 1,
				LayoutOrder = rank,
				ZIndex = 214,
				Parent = standingsList,
			})
			if rowColor then
				Factory.Corner(row, 8)
				if not isSelf then
					Factory.Stroke(row, rankColor, 0.75, 1)
				end
			end
			Factory.Label(row, medals[rank] or string.format("#%d", rank), UDim2.fromOffset(32, 30), {
				Position = UDim2.fromOffset(4, 0),
				TextSize = 15,
				ZIndex = 214,
			})
			Factory.Label(row, if isSelf then "You" else string.format("@%s", entry.name), UDim2.new(1, -110, 1, 0), {
				Position = UDim2.fromOffset(40, 0),
				Font = if isSelf or rankColor then Theme.Fonts.Bold else Theme.Fonts.Regular,
				TextSize = 13,
				Truncate = Enum.TextTruncate.AtEnd,
				ZIndex = 214,
			})
			Factory.Label(row, tostring(entry.score), UDim2.fromOffset(60, 30), {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -4, 0, 0),
				AlignX = Enum.TextXAlignment.Right,
				Font = Theme.Fonts.Black,
				Color = Colors.Gold,
				TextSize = 14,
				ZIndex = 214,
			})

			-- A quick staggered fade/rise so the list settles into place
			-- rather than popping in all at once -- skipped under
			-- reduceMotion (the row is already at its final transparency
			-- above in that case).
			if not reduceMotion then
				local rowScale = Factory.New("UIScale", { Scale = 0.94, Parent = row })
				task.delay(math.min(rank * 0.035, 0.35), function()
					if row.Parent then
						TweenService:Create(
							row,
							TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{ BackgroundTransparency = finalTransparency }
						):Play()
						TweenService:Create(
							rowScale,
							TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
							{ Scale = 1 }
						):Play()
					end
				end)
			end
		end
		local personal = result.self
		if not personal then
			selfStandingLabel.Text = "You haven't posted a score this week yet."
		elseif personal.rank then
			selfStandingLabel.Text = string.format("You're #%d this week with %d.", personal.rank, personal.score)
		else
			selfStandingLabel.Text =
				string.format("You're not in the top %d yet — your best is %d.", #standings, personal.score)
		end
	end

	local function loadLeaderboard(gameKey: string)
		selectedGameKey = gameKey
		setActiveTab(gameKey)
		setActiveScope(leaderboardScope)
		local scope = leaderboardScope
		local cacheKey = scope .. ":" .. gameKey
		local cached = standingsCache[cacheKey]
		if cached then
			renderLeaderboardStandings(cached, scope)
			return
		end
		for _, child in standingsList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		Factory.Label(standingsList, "Loading…", UDim2.new(1, 0, 0, 24), {
			Color = Colors.TextMuted,
			TextSize = 12,
			ZIndex = 214,
		})
		selfStandingLabel.Text = ""
		task.spawn(function()
			local result: GameShell.WeeklyResult
			if scope == "friends" then
				result = fetchFriendTop(gameKey) or { standings = {}, self = nil }
			else
				result = fetchWeeklyTop(gameKey) or { standings = {}, self = nil }
			end
			standingsCache[cacheKey] = result
			if selectedGameKey == gameKey and leaderboardScope == scope and leaderboardView.Visible then
				renderLeaderboardStandings(result, scope)
			end
		end)
	end

	for scope, button in scopeButtons do
		button.Activated:Connect(function()
			if leaderboardScope == scope then
				return
			end
			leaderboardScope = scope
			loadLeaderboard(selectedGameKey)
		end)
	end

	do
		for i, tile in GAMES do
			local tab = Factory.New("TextButton", {
				Name = tile.game.Key .. "Tab",
				Size = UDim2.fromOffset(104, 28),
				LayoutOrder = i,
				BackgroundColor3 = Colors.PanelSoft,
				BackgroundTransparency = 0.65,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = string.format("%s %s", tile.icon, tile.game.Name),
				TextColor3 = Colors.Text,
				Font = Theme.Fonts.Bold,
				TextSize = 11,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 213,
				Parent = leaderboardTabs,
			})
			Factory.Corner(tab, Theme.SmallCorner)
			Factory.Stroke(tab, Colors.Line, 0.6)
			-- A white overlay gradient rather than a colored one, since it
			-- needs to look right over both the active (Gold) and inactive
			-- (PanelSoft) fill setActiveTab swaps between.
			Factory.New("UIGradient", {
				Color = ColorSequence.new(Color3.new(1, 1, 1)),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.75),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 90,
				Parent = tab,
			})
			app.sounds:Bind(tab)
			tab.Activated:Connect(function()
				loadLeaderboard(tile.game.Key)
			end)
			tabButtons[tile.game.Key] = tab
		end
	end
	setActiveTab(selectedGameKey)
	setActiveScope(leaderboardScope)

	local function showLeaderboardTab()
		switchView(function()
			hubView.Visible = false
			gameView.Visible = false
			leaderboardView.Visible = true
			rewardBanner.Visible = false
			if shell then
				shell:Stop()
			end
			loadLeaderboard(selectedGameKey)
		end)
	end

	-- ===== Tile picker =====

	local function buildTile(
		size: UDim2,
		position: UDim2,
		color: Color3,
		icon: string,
		title: string,
		blurb: string,
		onActivated: () -> (),
		statsGameKey: string?
	)
		-- Compact (mobile-stacked) tiles are much shorter than wide-mode
		-- ones, so every internal metric below scales off the tile's own
		-- height instead of assuming the wide-mode numbers -- a fixed-size
		-- badge/scrim sized for a 172px-tall tile would swallow most of an
		-- 84px-tall one.
		local tileHeight = size.Y.Offset
		local roomy = tileHeight >= 150
		local badgeSize = if roomy then 48 else 30
		local badgeIconSize = if roomy then 24 else 15
		local scrimHeight = if roomy then 76 else 48

		-- A soft colored glow behind the tile, echoing its own accent color
		-- -- a "spotlight" sitting behind the shadow, the same depth trick
		-- the header's own glow uses.
		local glow = Factory.New("Frame", {
			Name = "Glow",
			Size = size + UDim2.fromOffset(70, 70),
			Position = position - UDim2.fromOffset(35, 35),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.86,
			BorderSizePixel = 0,
			ZIndex = 211,
			Parent = hubView,
		})
		Factory.Corner(glow, 34)

		-- Two shadow layers at different offsets/softness read as more
		-- elevation than one flat one.
		local farShadow = Factory.New("Frame", {
			Name = "FarShadow",
			Size = size + UDim2.fromOffset(6, 6),
			Position = position + UDim2.fromOffset(-3, 9),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			ZIndex = 211,
			Parent = hubView,
		})
		Factory.Corner(farShadow, 22)
		local shadow = Factory.New("Frame", {
			Name = "Shadow",
			Size = size,
			Position = position + UDim2.fromOffset(0, 5),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			ZIndex = 212,
			Parent = hubView,
		})
		Factory.Corner(shadow, 20)

		local button = Factory.New("TextButton", {
			Size = size,
			Position = position,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ClipsDescendants = true,
			ZIndex = 213,
			Parent = hubView,
		})
		Factory.Corner(button, 20)
		Factory.Stroke(button, Colors.Ink, 0.4, 2)
		Factory.Gradient(button, { lighten(color, 0.1), darken(color, 0.18) }, 130)
		local gloss = Factory.New("Frame", {
			Name = "Gloss",
			Size = UDim2.new(1, -2, 0, math.min(44, tileHeight * 0.35)),
			Position = UDim2.fromOffset(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.86,
			BorderSizePixel = 0,
			ZIndex = 214,
			Parent = button,
		})
		Factory.Corner(gloss, 19)

		-- A diagonal light streak that sweeps across on a loop, paused
		-- between passes -- purely decorative, so it's the first thing off
		-- under reduceMotion. Rotated GuiObjects do not reliably respect an
		-- ordinary Frame's clipping rectangle in Roblox. Rendering the shine
		-- through a CanvasGroup gives it an off-screen texture to mask first,
		-- then the group's matching UICorner clips that texture cleanly to the
		-- tile instead of letting the white strip flash outside the card.
		if not reduceMotion then
			local shineMask = Factory.New("CanvasGroup", {
				Name = "ShineMask",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				ZIndex = 214,
				Parent = button,
			})
			Factory.Corner(shineMask, 20)
			local shine = Factory.New("Frame", {
				Name = "Shine",
				Size = UDim2.fromOffset(34, tileHeight * 1.6),
				Position = UDim2.new(0, -60, 0, -tileHeight * 0.3),
				Rotation = 22,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.78,
				BorderSizePixel = 0,
				ZIndex = 214,
				Parent = shineMask,
			})
			TweenService:Create(
				shine,
				TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 2.6),
				{ Position = UDim2.new(1, 60, 0, -tileHeight * 0.3) }
			):Play()
		end

		local tileScale = Factory.New("UIScale", { Scale = 1, Parent = button })
		-- Desktop hover feedback: a light grow, distinct from (and gentler
		-- than) the click-punch below. Never fires on touch, which has no
		-- concept of hover -- fine, since the tap itself already answers
		-- "did something respond".
		button.MouseEnter:Connect(function()
			if not reduceMotion then
				TweenService:Create(
					tileScale,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Scale = 1.03 }
				):Play()
			end
		end)
		button.MouseLeave:Connect(function()
			TweenService
				:Create(tileScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end)

		local iconBadge = Factory.New("Frame", {
			Name = "IconBadge",
			Size = UDim2.fromOffset(badgeSize, badgeSize),
			Position = UDim2.fromOffset(if roomy then 14 else 10, if roomy then 14 else 8),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 215,
			Parent = button,
		})
		Factory.Corner(iconBadge, if roomy then 15 else 10)
		Factory.Stroke(iconBadge, Color3.new(1, 1, 1), 0.85, 1)
		Factory.Gradient(iconBadge, {
			Color3.fromRGB(56, 60, 82),
			Color3.fromRGB(30, 33, 50),
		}, 120)
		Factory.Label(iconBadge, icon, UDim2.fromScale(1, 1), {
			TextSize = badgeIconSize,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 216,
		})

		-- A real personal-best-this-week chip, not a fabricated stat --
		-- fetched lazily after the tile is already visible so it never
		-- blocks the picker screen from showing up, and only revealed once
		-- (if) an actual score comes back. Wide-mode tiles only: there's no
		-- clean spot for it on compact's much shorter ones.
		local statsChip: Frame? = nil
		local statsLabel: TextLabel? = nil
		if roomy and statsGameKey then
			statsChip = Factory.New("Frame", {
				Name = "StatsChip",
				Size = UDim2.fromOffset(108, 22),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 14),
				BackgroundColor3 = Colors.Ink,
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = 215,
				Parent = button,
			})
			Factory.Corner(statsChip, 11)
			Factory.Stroke(statsChip, Color3.new(1, 1, 1), 0.85, 1)
			statsLabel = Factory.Label(statsChip, "", UDim2.new(1, -16, 1, 0), {
				Position = UDim2.fromOffset(8, 0),
				Font = Theme.Fonts.Bold,
				TextSize = 10,
				Color = Colors.Text,
				AlignX = Enum.TextXAlignment.Center,
				AlignY = Enum.TextYAlignment.Center,
				Truncate = Enum.TextTruncate.AtEnd,
				ZIndex = 216,
			})
			task.spawn(function()
				local result = fetchWeeklyTop(statsGameKey)
				local chip, label = statsChip, statsLabel
				if result and result.self and chip and chip.Parent and label then
					label.Text = string.format("⚡ This week: %d", result.self.score)
					chip.Visible = true
				end
			end)

			-- Today's Daily Challenge target -- a pure local computation
			-- (see Shared/DailyChallenge.luau), so unlike the stats chip
			-- above it needs no round trip and is visible immediately.
			local challengeTarget = DailyChallenge.GetTarget(statsGameKey, math.floor(os.time() / 86400))
			if challengeTarget then
				local challengeChip = Factory.New("Frame", {
					Name = "ChallengeChip",
					Size = UDim2.fromOffset(108, 22),
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -10, 0, 40),
					BackgroundColor3 = Colors.Gold,
					BackgroundTransparency = 0.25,
					BorderSizePixel = 0,
					ZIndex = 215,
					Parent = button,
				})
				Factory.Corner(challengeChip, 11)
				Factory.Stroke(challengeChip, Colors.Gold, 0.4, 1)
				Factory.Label(
					challengeChip,
					string.format("🎯 Target: %d", challengeTarget),
					UDim2.new(1, -16, 1, 0),
					{
						Position = UDim2.fromOffset(8, 0),
						Font = Theme.Fonts.Bold,
						TextSize = 10,
						Color = Colors.Ink,
						AlignX = Enum.TextXAlignment.Center,
						AlignY = Enum.TextYAlignment.Center,
						Truncate = Enum.TextTruncate.AtEnd,
						ZIndex = 216,
					}
				)
			end
		end

		-- A bottom scrim so the title/blurb stay legible in light text no
		-- matter how bright the tile's own accent color is, the same trick a
		-- media/game-store card uses over a busy thumbnail.
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
				NumberSequenceKeypoint.new(1, 0.15),
			}),
			Rotation = 90,
			Parent = scrim,
		})

		Factory.Label(scrim, title, UDim2.new(1, -70, 0, 22), {
			Position = UDim2.fromOffset(16, scrimHeight - (if roomy then 46 else 32)),
			Font = Theme.Fonts.Black,
			TextSize = if roomy then 17 else 14,
			Color = Colors.Text,
			AlignX = Enum.TextXAlignment.Left,
			Truncate = Enum.TextTruncate.AtEnd,
			ZIndex = 216,
		})
		Factory.Label(scrim, blurb, UDim2.new(1, -70, 0, 30), {
			Position = UDim2.fromOffset(16, scrimHeight - (if roomy then 24 else 15)),
			Font = Theme.Fonts.Medium,
			TextSize = if roomy then 11 else 10,
			Color = Colors.TextMuted,
			Wrapped = true,
			AlignX = Enum.TextXAlignment.Left,
			Truncate = Enum.TextTruncate.AtEnd,
			ZIndex = 216,
		})
		-- The "▶ GO" affordance chip only fits comfortably on the taller
		-- wide-mode tiles -- skipped on compact's shorter ones rather than
		-- cramped in.
		if roomy then
			local playPill = Factory.New("Frame", {
				Name = "PlayPill",
				Size = UDim2.fromOffset(44, 22),
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -12, 1, -10),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				ZIndex = 216,
				Parent = scrim,
			})
			Factory.Corner(playPill, 11)
			Factory.Label(playPill, "▶ GO", UDim2.fromScale(1, 1), {
				Font = Theme.Fonts.Black,
				TextSize = 10,
				Color = darken(color, 0.25),
				AlignX = Enum.TextXAlignment.Center,
				AlignY = Enum.TextYAlignment.Center,
				ZIndex = 217,
			})
		end

		app.sounds:Bind(button)
		button.Selectable = true
		button.Activated:Connect(function()
			if not reduceMotion then
				tileScale.Scale = 0.94
				TweenService
					:Create(
						tileScale,
						TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Scale = 1 }
					)
					:Play()
			end
			onActivated()
		end)
	end

	if app.compact then
		for index, tile in GAMES do
			buildTile(
				COMPACT_TILE_SIZE,
				UDim2.fromOffset(0, (index - 1) * COMPACT_TILE_HEIGHT),
				tile.color,
				tile.icon,
				tile.game.Name,
				tile.blurb,
				function()
					playGame(tile.game)
				end,
				tile.game.Key
			)
		end
		buildTile(
			COMPACT_TILE_SIZE,
			UDim2.fromOffset(0, #GAMES * COMPACT_TILE_HEIGHT),
			Colors.Gold,
			"🏆",
			"Leaderboard",
			"See where you rank.",
			showLeaderboardTab
		)
	else
		for index, tile in GAMES do
			buildTile(TILE_SIZE, wideTilePosition(index), tile.color, tile.icon, tile.game.Name, tile.blurb, function()
				playGame(tile.game)
			end, tile.game.Key)
		end
		buildTile(
			TILE_SIZE,
			wideTilePosition(#GAMES + 1),
			Colors.Gold,
			"🏆",
			"Leaderboard",
			"See where you rank.",
			showLeaderboardTab
		)
	end
end

return GamesHub
