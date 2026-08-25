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

-- `wide` positions/sizes are a verified-fit 2x2 grid within the hub view's
-- fixed 536x392 content box (see the width/height derivation in the Show
-- function below) -- NOT hand-waved offsets, since the last layout
-- overflowed the visible area once the header grew and nobody re-checked
-- the numbers. `wide` applies above the compact breakpoint; compact always
-- stacks full-width instead.
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
}

local TILE_SIZE = UDim2.fromOffset(248, 172)
local COMPACT_TILE_SIZE = UDim2.new(1, 0, 0, 84)
local TILE_POSITIONS = {
	UDim2.fromOffset(12, 12),
	UDim2.fromOffset(270, 12),
	UDim2.fromOffset(12, 194),
	UDim2.fromOffset(270, 194), -- reserved for the Leaderboard tile
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
	-- MaxSize width matches the compact breakpoint (App.luau: width < 760 is
	-- compact) so `useWide` below and this modal's actual rendered width
	-- agree: whenever tiles render in wide mode, the screen is already wide
	-- enough that this 560 cap -- not the screen -- is what's actually
	-- limiting the modal, so its width is reliably exactly 560px, not just
	-- "usually about that". The tile grid below is sized against that fixed
	-- number, not a guess.
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

	-- Three views share the same footprint below the header and are swapped
	-- by visibility rather than all existing on screen at once.
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
	local leaderboardView = Factory.New("Frame", {
		Name = "LeaderboardView",
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
		leaderboardView.Visible = false
		if shell then
			shell:Stop()
		end
	end

	local function playGame(gameModule: GameShell.GameModule)
		hubView.Visible = false
		leaderboardView.Visible = false
		gameView.Visible = true
		if not shell then
			shell = GameShell.new(gameView, app.sounds, showHub, submitScore, fetchWeeklyTop, reduceMotion)
		end
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

	local leaderboardTabs = Factory.New("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(80, 3),
		Size = UDim2.new(1, -80, 0, 28),
		BackgroundTransparency = 1,
		ZIndex = 213,
		Parent = leaderboardView,
	})

	local standingsHost = Factory.New("Frame", {
		Name = "StandingsHost",
		Position = UDim2.fromOffset(0, 43),
		Size = UDim2.new(1, 0, 1, -43),
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
	local tabButtons: { [string]: TextButton } = {}

	local function setActiveTab(gameKey: string)
		for key, tab in tabButtons do
			local active = key == gameKey
			tab.BackgroundTransparency = if active then 0.15 else 0.65
			tab.BackgroundColor3 = if active then Colors.Gold else Colors.PanelSoft
			tab.TextColor3 = if active then Colors.Ink else Colors.Text
		end
	end

	local function renderLeaderboardStandings(result: GameShell.WeeklyResult)
		for _, child in standingsList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local standings = result.standings
		if #standings == 0 then
			Factory.Label(
				standingsList,
				"No scores yet this week — be the first to set one!",
				UDim2.new(1, 0, 0, 40),
				{
					Color = Colors.TextMuted,
					TextSize = 12,
					Wrapped = true,
					ZIndex = 214,
				}
			)
		end
		local medals = { "🥇", "🥈", "🥉" }
		local localUserId = Players.LocalPlayer and Players.LocalPlayer.UserId
		for rank, entry in standings do
			local isSelf = entry.userId == localUserId
			local row = Factory.New("Frame", {
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundColor3 = Colors.Gold,
				BackgroundTransparency = if isSelf then 0.85 else 1,
				LayoutOrder = rank,
				ZIndex = 214,
				Parent = standingsList,
			})
			if isSelf then
				Factory.Corner(row, 8)
			end
			Factory.Label(row, medals[rank] or string.format("#%d", rank), UDim2.fromOffset(32, 30), {
				Position = UDim2.fromOffset(4, 0),
				TextSize = 15,
				ZIndex = 214,
			})
			Factory.Label(row, if isSelf then "You" else string.format("@%s", entry.name), UDim2.new(1, -110, 1, 0), {
				Position = UDim2.fromOffset(40, 0),
				Font = if isSelf then Theme.Fonts.Bold else Theme.Fonts.Regular,
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
		local cached = standingsCache[gameKey]
		if cached then
			renderLeaderboardStandings(cached)
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
			local result = fetchWeeklyTop(gameKey) or { standings = {}, self = nil }
			standingsCache[gameKey] = result
			if selectedGameKey == gameKey and leaderboardView.Visible then
				renderLeaderboardStandings(result)
			end
		end)
	end

	do
		local tabCount = #GAMES
		for i, tile in GAMES do
			local tab = Factory.New("TextButton", {
				Name = tile.game.Key .. "Tab",
				Size = UDim2.new(1 / tabCount, if i == 1 or i == tabCount then -6 else -8, 1, 0),
				Position = UDim2.new((i - 1) / tabCount, if i == 1 then 0 else 4, 0, 0),
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

	local function showLeaderboardTab()
		hubView.Visible = false
		gameView.Visible = false
		leaderboardView.Visible = true
		if shell then
			shell:Stop()
		end
		loadLeaderboard(selectedGameKey)
	end

	-- ===== Tile picker =====

	local function buildTile(
		size: UDim2,
		position: UDim2,
		color: Color3,
		icon: string,
		title: string,
		blurb: string,
		onActivated: () -> ()
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
		local tileScale = Factory.New("UIScale", { Scale = 1, Parent = button })

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
				UDim2.fromOffset(0, (index - 1) * 92),
				tile.color,
				tile.icon,
				tile.game.Name,
				tile.blurb,
				function()
					playGame(tile.game)
				end
			)
		end
		buildTile(
			COMPACT_TILE_SIZE,
			UDim2.fromOffset(0, #GAMES * 92),
			Colors.Gold,
			"🏆",
			"Leaderboard",
			"See where you rank.",
			showLeaderboardTab
		)
	else
		for index, tile in GAMES do
			buildTile(TILE_SIZE, TILE_POSITIONS[index], tile.color, tile.icon, tile.game.Name, tile.blurb, function()
				playGame(tile.game)
			end)
		end
		buildTile(
			TILE_SIZE,
			TILE_POSITIONS[4],
			Colors.Gold,
			"🏆",
			"Leaderboard",
			"See where you rank.",
			showLeaderboardTab
		)
	end
end

return GamesHub
