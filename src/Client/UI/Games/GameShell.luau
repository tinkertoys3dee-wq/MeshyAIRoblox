--!strict

-- Shared harness for the Arcade minigames. Builds the HUD (score + exit) and
-- the game-over screen (score, personal best, retry) once, so every game
-- module only has to implement its own play loop -- not this chrome three
-- times over. A game module's contract is a single function:
--
--   Game.Start(canvas: Frame, api: GameApi) -> () -> ()
--
-- api.setScore/api.gameOver drive this shell; the returned function is the
-- game's cleanup (disconnect every connection, destroy every instance it
-- created under canvas) and is always called before a retry or a switch to
-- a different game, never left for the caller to guess about.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)

local Colors = Theme.Colors

export type GameApi = {
	sounds: any,
	setScore: (score: number) -> (),
	gameOver: (score: number) -> (),
	-- True when the player enabled Settings > Reduce motion. Every game
	-- reads this before playing a decorative effect (screen shake, particle
	-- bursts, squash/stretch) -- never before moving the player/obstacles
	-- themselves, since that motion carries the actual gameplay information.
	reduceMotion: boolean,
}

export type GameModule = {
	Name: string,
	Key: string,
	Start: (canvas: Frame, api: GameApi) -> () -> (),
}

export type WeeklyStanding = { userId: number, name: string, score: number }
-- The requesting player's own placement -- `rank` is nil when they have a
-- score but it fell outside the fetched top standings (still worth showing
-- "you: N" even when you're not on the visible list).
export type PersonalStanding = { rank: number?, score: number }
export type WeeklyResult = { standings: { WeeklyStanding }, self: PersonalStanding? }

local GameShell = {}
GameShell.__index = GameShell

-- Small radial particle puff shared by all three games (gate passed, pipe
-- cleared, obstacle jumped) so the effect only has to be built once. A no-op
-- under reduceMotion -- it's pure decoration, never the game's only signal
-- that something happened (a sound and/or score update always accompanies
-- it), so skipping it costs nothing but flourish.
function GameShell.Burst(parent: Instance, position: UDim2, color: Color3, reduceMotion: boolean)
	if reduceMotion then
		return
	end
	for i = 1, 6 do
		local angle = (i / 6) * math.pi * 2 + math.random() * 0.4
		local distance = 22 + math.random() * 16
		local particle = Factory.New("Frame", {
			Name = "Particle",
			Size = UDim2.fromOffset(6, 6),
			Position = position,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 40,
			Parent = parent,
		})
		Factory.Corner(particle, 3)
		local targetPosition = position + UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance)
		local tween = TweenService:Create(
			particle,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = targetPosition, BackgroundTransparency = 1, Size = UDim2.fromOffset(2, 2) }
		)
		tween.Completed:Connect(function()
			particle:Destroy()
		end)
		tween:Play()
	end
end

-- Nudges `frame` away from its current position and eases it back -- used
-- for crash/collision feedback. A no-op under reduceMotion since a sudden
-- shake is exactly the kind of motion that setting exists to suppress, and
-- the games always pair it with a sound and the game-over screen anyway.
function GameShell.Shake(frame: Frame, reduceMotion: boolean)
	if reduceMotion then
		return
	end
	local restingPosition = frame.Position
	frame.Position = restingPosition + UDim2.fromOffset(math.random(-7, 7), math.random(-5, 5))
	TweenService:Create(
		frame,
		TweenInfo.new(0.3, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{ Position = restingPosition }
	):Play()
end

-- `onGameEnd` fires once per finished game (fire-and-forget score submission
-- — the shell doesn't wait on it or block the game-over screen for it).
-- `fetchWeeklyTop` backs the "🏆 This week" panel; both are supplied by
-- GamesHub, which is the layer that actually knows about Network/_Invoke, so
-- this module stays free of any direct server-communication concern.
function GameShell.new(
	parent: Instance,
	sounds: any,
	onExit: () -> (),
	onGameEnd: (gameKey: string, score: number) -> (),
	fetchWeeklyTop: (gameKey: string) -> WeeklyResult?,
	reduceMotion: boolean?
)
	local self = setmetatable({
		sounds = sounds,
		onExit = onExit,
		onGameEnd = onGameEnd,
		fetchWeeklyTop = fetchWeeklyTop,
		reduceMotion = reduceMotion == true,
		stopGame = nil :: (() -> ())?,
		currentGame = nil :: GameModule?,
		bestScores = {} :: { [string]: number },
		standingsCache = {} :: { [string]: WeeklyResult },
	}, GameShell)

	local root = Factory.New("Frame", {
		Name = "GameShellRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	self.root = root

	local hud = Factory.New("Frame", {
		Name = "HUD",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = root,
	})
	Factory.Corner(hud, 14)
	Factory.New("Frame", {
		Name = "Divider",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, 0),
		Size = UDim2.new(1, -20, 0, 1),
		BackgroundColor3 = Colors.Line,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		Parent = hud,
	})
	-- The right-side cluster (score, trophy, exit) reserves a fixed 230px
	-- from the HUD's right edge; gameTitle's own width stops 8px short of
	-- that so the two can never formally overlap regardless of text length.
	self.gameTitle = Factory.Label(hud, "", UDim2.new(1, -230, 1, 0), {
		Position = UDim2.fromOffset(14, 0),
		Font = Theme.Fonts.Black,
		TextSize = 16,
		AlignY = Enum.TextYAlignment.Center,
	})
	local scoreBadge = Factory.New("Frame", {
		Name = "ScoreBadge",
		Size = UDim2.fromOffset(96, 26),
		Position = UDim2.new(1, -222, 0, 7),
		BackgroundColor3 = Colors.Gold,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Parent = hud,
	})
	Factory.Corner(scoreBadge, 13)
	self.scoreLabel = Factory.Label(scoreBadge, "0", UDim2.new(1, -14, 1, 0), {
		Position = UDim2.fromOffset(14, 0),
		Font = Theme.Fonts.Black,
		TextSize = 14,
		Color = Colors.Gold,
		AlignX = Enum.TextXAlignment.Right,
		AlignY = Enum.TextYAlignment.Center,
	})
	Factory.Label(scoreBadge, "◆", UDim2.fromOffset(20, 26), {
		Position = UDim2.fromOffset(-2, 0),
		TextSize = 11,
		Color = Colors.Gold,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
	})
	local trophyShadow = Factory.New("Frame", {
		Name = "TrophyShadow",
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(1, -118, 0, 7),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Parent = hud,
	})
	Factory.Corner(trophyShadow, 15)
	local trophyButton = Factory.New("TextButton", {
		Name = "TrophyButton",
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(1, -118, 0, 5),
		BackgroundColor3 = Colors.Gold,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "🏆",
		TextSize = 15,
		Parent = hud,
	})
	Factory.Corner(trophyButton, 15)
	Factory.Stroke(trophyButton, Colors.Ink, 0.4, 1.5)
	Factory.Gradient(trophyButton, { Color3.fromRGB(255, 224, 140), Color3.fromRGB(214, 158, 40) }, 120)
	sounds:Bind(trophyButton)
	trophyButton.Activated:Connect(function()
		self:_ToggleWeeklyStandings()
	end)

	local exitShadow = Factory.New("Frame", {
		Name = "ExitShadow",
		Size = UDim2.fromOffset(70, 30),
		Position = UDim2.new(1, -80, 0, 7),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Parent = hud,
	})
	Factory.Corner(exitShadow, Theme.SmallCorner)
	local exitButton = Factory.New("TextButton", {
		Name = "ExitButton",
		Size = UDim2.fromOffset(70, 30),
		Position = UDim2.new(1, -80, 0, 5),
		BackgroundColor3 = Colors.Danger,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "Exit",
		TextColor3 = Colors.Text,
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		Parent = hud,
	})
	Factory.Corner(exitButton, Theme.SmallCorner)
	Factory.Stroke(exitButton, Colors.Ink, 0.4, 1.5)
	Factory.Gradient(exitButton, { Color3.fromRGB(255, 140, 150), Colors.Danger }, 120)
	exitButton.TextXAlignment = Enum.TextXAlignment.Right
	Factory.New("UIPadding", { PaddingRight = UDim.new(0, 10), Parent = exitButton })
	local exitIcon = Factory.New("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.fromOffset(5, 5),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = exitButton,
	})
	Factory.Corner(exitIcon, 7)
	Factory.Label(exitIcon, "✕", UDim2.fromScale(1, 1), {
		Color = Colors.Text,
		Font = Theme.Fonts.Black,
		TextSize = 11,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
		ZIndex = 3,
	})
	sounds:Bind(exitButton)
	exitButton.Activated:Connect(function()
		self:Stop()
		onExit()
	end)

	local canvas = Factory.New("Frame", {
		Name = "Canvas",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.1,
		ClipsDescendants = true,
		-- Every game taps/clicks directly on this frame for input (mobile
		-- has no spacebar); Active makes that input reliably fire.
		Active = true,
		Parent = root,
	})
	Factory.Corner(canvas, 14)
	Factory.Stroke(canvas, Colors.Line, 0.4, 1.5)
	self.canvas = canvas

	local overlay = Factory.New("Frame", {
		Name = "GameOverOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.35,
		Visible = false,
		ZIndex = 30,
		Parent = canvas,
	})
	-- The actual game-over content lives on a centered card rather than
	-- floating directly on the dim backdrop -- reads as a proper modal
	-- instead of text pasted over the last frame of gameplay.
	local card = Factory.Card(overlay, UDim2.fromOffset(252, 244), UDim2.fromScale(0.5, 0.45), "GameOverCard")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.ZIndex = 31
	local badge = Factory.New("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		BackgroundColor3 = Colors.Rose,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 32,
		Parent = card,
	})
	Factory.Corner(badge, 16)
	Factory.Label(badge, "💥", UDim2.fromScale(1, 1), {
		TextSize = 22,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
		ZIndex = 33,
	})
	local titleLabel = Factory.Label(card, "GAME OVER", UDim2.new(1, -20, 0, 26), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Font = Theme.Fonts.Black,
		TextSize = 20,
		Color = Colors.Rose,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 32,
	})
	local titleScale = Factory.New("UIScale", { Scale = 1, Parent = titleLabel })
	local finalScoreLabel = Factory.Label(card, "", UDim2.new(1, -20, 0, 26), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Font = Theme.Fonts.Black,
		TextSize = 18,
		Color = Colors.Gold,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 32,
	})
	local bestLabel = Factory.Label(card, "", UDim2.new(1, -20, 0, 18), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 126),
		Font = Theme.Fonts.Medium,
		TextSize = 11,
		Color = Colors.TextMuted,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 32,
	})
	local retryShadow = Factory.New("Frame", {
		Name = "RetryShadow",
		Size = UDim2.fromOffset(200, 42),
		Position = UDim2.new(0.5, -100, 0, 159),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 31,
		Parent = card,
	})
	Factory.Corner(retryShadow, Theme.SmallCorner)
	local retryButton =
		Factory.Button(card, "Play Again", UDim2.fromOffset(200, 42), UDim2.new(0.5, -100, 0, 156), "mint")
	retryButton.ZIndex = 32
	retryButton.TextXAlignment = Enum.TextXAlignment.Right
	Factory.Gradient(retryButton, { Color3.fromRGB(150, 255, 210), Colors.Mint }, 90)
	local retryIcon = Factory.New("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(8, 7),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 33,
		Parent = retryButton,
	})
	Factory.Corner(retryIcon, 9)
	Factory.Label(retryIcon, "↻", UDim2.fromScale(1, 1), {
		Color = Colors.Ink,
		Font = Theme.Fonts.Black,
		TextSize = 16,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
		ZIndex = 34,
	})
	Factory.New("UIPadding", { PaddingRight = UDim.new(0, 20), Parent = retryButton })
	sounds:Bind(retryButton)

	local hubButton =
		Factory.Button(card, "Back to Arcade", UDim2.fromOffset(200, 34), UDim2.new(0.5, -100, 0, 202), nil)
	hubButton.ZIndex = 32
	hubButton.TextXAlignment = Enum.TextXAlignment.Right
	local hubIcon = Factory.New("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.fromOffset(8, 6),
		BackgroundColor3 = Colors.Rose,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		ZIndex = 33,
		Parent = hubButton,
	})
	Factory.Corner(hubIcon, 7)
	Factory.Label(hubIcon, "🎮", UDim2.fromScale(1, 1), {
		TextSize = 12,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
		ZIndex = 34,
	})
	Factory.New("UIPadding", { PaddingRight = UDim.new(0, 16), Parent = hubButton })
	sounds:Bind(hubButton)
	hubButton.Activated:Connect(function()
		self:Stop()
		onExit()
	end)

	local standingsPanel = Factory.New("Frame", {
		Name = "WeeklyStandings",
		Size = UDim2.fromOffset(232, 258),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		BackgroundColor3 = Colors.PanelRaised,
		BackgroundTransparency = 0.03,
		Visible = false,
		ZIndex = 25,
		Parent = canvas,
	})
	Factory.Corner(standingsPanel, 14)
	Factory.Stroke(standingsPanel, Colors.Gold, 0.4)
	Factory.Gradient(standingsPanel, {
		Color3.fromRGB(64, 72, 104),
		Color3.fromRGB(46, 52, 80),
	}, 115)
	Factory.Label(standingsPanel, "🏆  THIS WEEK · TOP 10", UDim2.new(1, -20, 0, 22), {
		Position = UDim2.fromOffset(10, 8),
		Font = Theme.Fonts.Bold,
		TextSize = 11,
		Color = Colors.Gold,
		ZIndex = 26,
	})
	Factory.New("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(10, 30),
		Size = UDim2.new(1, -20, 0, 1),
		BackgroundColor3 = Colors.Gold,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		ZIndex = 26,
		Parent = standingsPanel,
	})
	-- A ScrollingFrame rather than a plain Frame -- 10 rows don't reliably
	-- fit the panel's height, so the list scrolls instead of the panel
	-- growing to swallow the canvas.
	local standingsList = Factory.New("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(10, 38),
		Size = UDim2.new(1, -20, 0, 154),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.Gold,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 26,
		Parent = standingsPanel,
	})
	Factory.List(standingsList, Enum.FillDirection.Vertical, 6)
	Factory.New("Frame", {
		Name = "FooterDivider",
		Position = UDim2.fromOffset(10, 198),
		Size = UDim2.new(1, -20, 0, 1),
		BackgroundColor3 = Colors.Gold,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		ZIndex = 26,
		Parent = standingsPanel,
	})
	-- Pinned below the scrollable list -- "where do I stand" should never
	-- require scrolling to find, especially when the honest answer is
	-- "not in the top 10 yet".
	local selfStandingLabel = Factory.Label(standingsPanel, "", UDim2.new(1, -20, 0, 40), {
		Position = UDim2.fromOffset(10, 208),
		Color = Colors.TextMuted,
		Font = Theme.Fonts.Medium,
		TextSize = 11,
		Wrapped = true,
		ZIndex = 26,
	})
	self.standingsPanel = standingsPanel
	self.standingsList = standingsList
	self.selfStandingLabel = selfStandingLabel

	self.overlay = overlay
	self.finalScoreLabel = finalScoreLabel
	self.bestLabel = bestLabel
	self.titleScale = titleScale

	-- Always restarts whatever `currentGame` is currently set to, so no
	-- individual game needs to know how retry works.
	retryButton.Activated:Connect(function()
		if self.currentGame then
			self:Run(self.currentGame)
		end
	end)

	return self
end

function GameShell:SetScore(score: number)
	self.scoreLabel.Text = tostring(score)
end

function GameShell:_GameOver(score: number)
	local gameModule = self.currentGame
	local name = gameModule and gameModule.Name or ""
	local best = math.max(self.bestScores[name] or 0, score)
	self.bestScores[name] = best
	self.finalScoreLabel.Text = string.format("Score: %d", score)
	self.bestLabel.Text = string.format("Best this session: %d", best)
	self.overlay.Visible = true
	self.sounds:Play("Error")
	if self.reduceMotion then
		self.overlay.BackgroundTransparency = 0.15
		self.titleScale.Scale = 1
	else
		-- A quick fade-in-and-punch on the "GAME OVER" title -- purely
		-- decorative feedback, so it's the first thing skipped under Reduce
		-- motion (set to its final resting state above instead).
		self.overlay.BackgroundTransparency = 1
		self.titleScale.Scale = 0.4
		TweenService:Create(
			self.overlay,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0.15 }
		):Play()
		TweenService
			:Create(
				self.titleScale,
				TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }
			)
			:Play()
	end
	if gameModule then
		-- Fire-and-forget: a network hiccup here should never interrupt the
		-- game-over screen the player is already looking at.
		self.onGameEnd(gameModule.Key, score)
	end
end

-- Lazily fetched and cached per game-key for as long as this shell instance
-- lives, so re-opening the panel on the same game doesn't re-hit the network
-- every time -- standings only meaningfully change across a whole play
-- session, not between two clicks a few seconds apart.
function GameShell:_ToggleWeeklyStandings()
	local panel = self.standingsPanel
	if panel.Visible then
		panel.Visible = false
		return
	end
	panel.Visible = true
	local gameModule = self.currentGame
	if not gameModule then
		return
	end
	local cached = self.standingsCache[gameModule.Key]
	if cached then
		self:_RenderStandings(cached)
		return
	end
	for _, child in self.standingsList:GetChildren() do
		child:Destroy()
	end
	Factory.Label(self.standingsList, "Loading…", UDim2.new(1, 0, 0, 20), {
		Color = Colors.TextMuted,
		TextSize = 11,
		ZIndex = 26,
	})
	self.selfStandingLabel.Text = ""
	task.spawn(function()
		local result: WeeklyResult = self.fetchWeeklyTop(gameModule.Key) or { standings = {}, self = nil }
		self.standingsCache[gameModule.Key] = result
		if self.currentGame == gameModule and panel.Visible then
			self:_RenderStandings(result)
		end
	end)
end

function GameShell:_RenderStandings(result: WeeklyResult)
	local standings = result.standings
	for _, child in self.standingsList:GetChildren() do
		child:Destroy()
	end
	if #standings == 0 then
		Factory.Label(self.standingsList, "No scores yet this week — be first!", UDim2.new(1, 0, 0, 34), {
			Color = Colors.TextMuted,
			TextSize = 11,
			Wrapped = true,
			ZIndex = 26,
		})
	end
	local medals = { "🥇", "🥈", "🥉" }
	local localUserId = Players.LocalPlayer and Players.LocalPlayer.UserId
	for rank, entry in standings do
		local isSelf = entry.userId == localUserId
		local row = Factory.New("Frame", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundColor3 = Colors.Gold,
			BackgroundTransparency = if isSelf then 0.85 else 1,
			LayoutOrder = rank,
			ZIndex = 26,
			Parent = self.standingsList,
		})
		if isSelf then
			Factory.Corner(row, 6)
		end
		Factory.Label(row, medals[rank] or string.format("#%d", rank), UDim2.fromOffset(24, 22), {
			Position = UDim2.fromOffset(2, 0),
			TextSize = 13,
			ZIndex = 26,
		})
		Factory.Label(row, if isSelf then "You" else string.format("@%s", entry.name), UDim2.new(1, -84, 1, 0), {
			Position = UDim2.fromOffset(28, 0),
			Font = if isSelf then Theme.Fonts.Bold else Theme.Fonts.Regular,
			TextSize = 11,
			Truncate = Enum.TextTruncate.AtEnd,
			ZIndex = 26,
		})
		Factory.Label(row, tostring(entry.score), UDim2.fromOffset(50, 22), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -2, 0, 0),
			AlignX = Enum.TextXAlignment.Right,
			Font = Theme.Fonts.Bold,
			Color = Colors.Gold,
			TextSize = 12,
			ZIndex = 26,
		})
	end

	local personal = result.self
	if not personal then
		self.selfStandingLabel.Text = "You haven't posted a score this week yet."
	elseif personal.rank then
		self.selfStandingLabel.Text = string.format("You're #%d this week with %d.", personal.rank, personal.score)
	else
		self.selfStandingLabel.Text =
			string.format("You're not in the top %d yet — your best is %d.", #standings, personal.score)
	end
end

-- Runs `gameModule`, stopping and cleaning up whatever was running first.
-- Safe to call again from the retry button to restart the same game.
function GameShell:Run(gameModule: GameModule)
	self:Stop()
	self.overlay.Visible = false
	self.standingsPanel.Visible = false
	self.currentGame = gameModule
	self.gameTitle.Text = gameModule.Name
	self:SetScore(0)
	self.stopGame = gameModule.Start(self.canvas, {
		sounds = self.sounds,
		reduceMotion = self.reduceMotion,
		setScore = function(score: number)
			self:SetScore(score)
		end,
		gameOver = function(score: number)
			local stop = self.stopGame
			if stop then
				stop()
				self.stopGame = nil
			end
			self:_GameOver(score)
		end,
	})
end

function GameShell:Stop()
	local stop = self.stopGame
	if stop then
		stop()
		self.stopGame = nil
	end
	self.overlay.Visible = false
end

function GameShell:Destroy()
	self:Stop()
	self.root:Destroy()
end

return GameShell
