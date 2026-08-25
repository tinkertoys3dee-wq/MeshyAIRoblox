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
	fetchWeeklyTop: (gameKey: string) -> { WeeklyStanding }?,
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
		standingsCache = {} :: { [string]: { WeeklyStanding } },
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
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Parent = root,
	})
	self.gameTitle = Factory.Label(hud, "", UDim2.new(1, -214, 1, 0), {
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		AlignY = Enum.TextYAlignment.Center,
	})
	self.scoreLabel = Factory.Label(hud, "Score: 0", UDim2.fromOffset(90, 34), {
		Position = UDim2.new(1, -206, 0, 0),
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		Color = Colors.Gold,
		AlignX = Enum.TextXAlignment.Right,
		AlignY = Enum.TextYAlignment.Center,
	})
	local trophyButton = Factory.Button(hud, "🏆", UDim2.fromOffset(34, 30), UDim2.new(1, -108, 0, 2), nil)
	sounds:Bind(trophyButton)
	trophyButton.Activated:Connect(function()
		self:_ToggleWeeklyStandings()
	end)
	local exitButton = Factory.Button(hud, "✕ Exit", UDim2.fromOffset(70, 30), UDim2.new(1, -70, 0, 2), nil)
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
	Factory.Stroke(canvas, Colors.Line, 0.55)
	self.canvas = canvas

	local overlay = Factory.New("Frame", {
		Name = "GameOverOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.15,
		Visible = false,
		ZIndex = 30,
		Parent = canvas,
	})
	local titleLabel = Factory.Label(overlay, "GAME OVER", UDim2.new(1, -40, 0, 34), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.28, 0),
		Font = Theme.Fonts.Black,
		TextSize = 24,
		Color = Colors.Rose,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 31,
	})
	local titleScale = Factory.New("UIScale", { Scale = 1, Parent = titleLabel })
	local finalScoreLabel = Factory.Label(overlay, "", UDim2.new(1, -40, 0, 24), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.28, 40),
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 31,
	})
	local bestLabel = Factory.Label(overlay, "", UDim2.new(1, -40, 0, 20), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.28, 66),
		Font = Theme.Fonts.Medium,
		TextSize = 12,
		Color = Colors.TextMuted,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 31,
	})
	local retryButton =
		Factory.Button(overlay, "↻ Play again", UDim2.fromOffset(160, 42), UDim2.new(0.5, -80, 0.28, 104), "mint")
	retryButton.ZIndex = 31
	sounds:Bind(retryButton)
	local hubButton =
		Factory.Button(overlay, "Back to Arcade", UDim2.fromOffset(160, 36), UDim2.new(0.5, -80, 0.28, 154), nil)
	hubButton.ZIndex = 31
	sounds:Bind(hubButton)
	hubButton.Activated:Connect(function()
		self:Stop()
		onExit()
	end)

	local standingsPanel = Factory.New("Frame", {
		Name = "WeeklyStandings",
		Size = UDim2.fromOffset(230, 190),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 25,
		Parent = canvas,
	})
	Factory.Corner(standingsPanel, 12)
	Factory.Stroke(standingsPanel, Colors.Gold, 0.4)
	Factory.Label(standingsPanel, "THIS WEEK · TOP 3", UDim2.new(1, -20, 0, 22), {
		Position = UDim2.fromOffset(10, 8),
		Font = Theme.Fonts.Bold,
		TextSize = 11,
		Color = Colors.Gold,
		ZIndex = 26,
	})
	local standingsList = Factory.New("Frame", {
		Position = UDim2.fromOffset(10, 34),
		Size = UDim2.new(1, -20, 1, -44),
		BackgroundTransparency = 1,
		ZIndex = 26,
		Parent = standingsPanel,
	})
	Factory.List(standingsList, Enum.FillDirection.Vertical, 6)
	self.standingsPanel = standingsPanel
	self.standingsList = standingsList

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
	self.scoreLabel.Text = string.format("Score: %d", score)
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
	task.spawn(function()
		local standings: { WeeklyStanding } = self.fetchWeeklyTop(gameModule.Key) or {}
		self.standingsCache[gameModule.Key] = standings
		if self.currentGame == gameModule and panel.Visible then
			self:_RenderStandings(standings)
		end
	end)
end

function GameShell:_RenderStandings(standings: { WeeklyStanding })
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
		return
	end
	local medals = { "🥇", "🥈", "🥉" }
	for rank, entry in standings do
		local row = Factory.New("Frame", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			LayoutOrder = rank,
			ZIndex = 26,
			Parent = self.standingsList,
		})
		Factory.Label(row, medals[rank] or string.format("#%d", rank), UDim2.fromOffset(24, 22), {
			TextSize = 13,
			ZIndex = 26,
		})
		Factory.Label(row, string.format("@%s", entry.name), UDim2.new(1, -80, 1, 0), {
			Position = UDim2.fromOffset(26, 0),
			TextSize = 11,
			Truncate = Enum.TextTruncate.AtEnd,
			ZIndex = 26,
		})
		Factory.Label(row, tostring(entry.score), UDim2.fromOffset(48, 22), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			AlignX = Enum.TextXAlignment.Right,
			Font = Theme.Fonts.Bold,
			Color = Colors.Gold,
			TextSize = 12,
			ZIndex = 26,
		})
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
