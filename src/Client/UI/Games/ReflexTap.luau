--!strict

-- Reflex Tap: one tile in a grid lights up at a time -- tap it before its
-- countdown bar runs out. Tapping any other tile, or letting the countdown
-- expire, ends the run; a hit tapped early in its window (fast reaction)
-- builds a streak the same way FlappyBird/ColorSwitch's near-miss streaks
-- do. The window shrinks with score for the same "keeps getting harder
-- without a separate difficulty tier" reason DinoRunner's speed ramp and
-- NeonSnake's tick interval do.
--
-- Unlike every physics-driven game in this Arcade, there's nothing here to
-- simulate every frame -- each tile is a real TextButton and input is just
-- "which button fired Activated", the same primitive GameShell's own HUD
-- buttons use. A Heartbeat connection still exists, but only to drive the
-- countdown bar's visual width; the actual timeout is a cancellable
-- task.delay (the `myRound` token pattern every other game already uses for
-- a scheduled callback that a later event might need to invalidate).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors
local HOT_COLOR = Color3.fromRGB(45, 205, 196)
local HOT_GLOW_COLOR = Color3.fromRGB(120, 235, 225)

local GRID_COLUMNS = 4
local GRID_ROWS = 3
local GRID_GAP = 10
local GRID_TOP_MARGIN = 46
local GRID_SIDE_MARGIN = 14
local GRID_BOTTOM_MARGIN = 14
local BASE_WINDOW = 1.05 -- seconds to react at score 0
local MIN_WINDOW = 0.42
local WINDOW_STEP_PER_SCORE = 0.018
local QUICK_REACTION_FRACTION = 0.4 -- tapped within this fraction of the window counts as "quick"
local NEXT_TILE_DELAY = 0.18 -- breather between one hit and the next tile lighting up
local STREAK_FLASH_EVERY = 5

type Tile = { button: TextButton, bar: Frame, glow: Frame }

local Game = {} :: GameShell.GameModule
Game.Name = "Reflex Tap"
Game.Key = "ReflexTap"

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local score = 0
	local streak = 0
	local round = 0 -- bumped on every new hot tile / game end, invalidates stale scheduled callbacks
	local hotIndex: number? = nil
	local hotStartedAt = 0
	local hotWindow = BASE_WINDOW

	local function widthPx(): number
		local w = math.floor(canvas.AbsoluteSize.X)
		return if w > 40 then w else 480
	end
	local function heightPx(): number
		local h = math.floor(canvas.AbsoluteSize.Y)
		return if h > 40 then h else 300
	end

	local backdrop = Factory.New("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = canvas,
	})
	Factory.Gradient(backdrop, { Colors.Panel, Colors.Ink }, 90)

	local flashOverlay = Factory.New("Frame", {
		Name = "FlashOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = HOT_COLOR,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 45,
		Parent = canvas,
	})
	local function flashScreen(color: Color3, peakTransparency: number)
		if api.reduceMotion then
			return
		end
		flashOverlay.BackgroundColor3 = color
		flashOverlay.BackgroundTransparency = peakTransparency
		TweenService:Create(flashOverlay, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
	end

	local streakLabel = Factory.Label(canvas, "", UDim2.fromOffset(160, 24), {
		Name = "StreakLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Color = Colors.Gold,
		Font = Theme.Fonts.Black,
		TextSize = 16,
		AlignX = Enum.TextXAlignment.Center,
		Transparency = 1,
		ZIndex = 46,
	})
	Factory.New("UIStroke", { Color = Colors.Ink, Thickness = 2, Transparency = 0.4, Parent = streakLabel })

	local w, h = widthPx(), heightPx()
	local gridWidth = w - GRID_SIDE_MARGIN * 2
	local gridHeight = h - GRID_TOP_MARGIN - GRID_BOTTOM_MARGIN
	local tileWidth = (gridWidth - GRID_GAP * (GRID_COLUMNS - 1)) / GRID_COLUMNS
	local tileHeight = (gridHeight - GRID_GAP * (GRID_ROWS - 1)) / GRID_ROWS
	-- Square-ish tiles read better than however the canvas's own aspect
	-- ratio happens to stretch them -- clamp to the smaller dimension and
	-- re-center the whole grid in the leftover room.
	local tileSize = math.max(18, math.min(tileWidth, tileHeight))
	local usedWidth = tileSize * GRID_COLUMNS + GRID_GAP * (GRID_COLUMNS - 1)
	local usedHeight = tileSize * GRID_ROWS + GRID_GAP * (GRID_ROWS - 1)
	local originX = GRID_SIDE_MARGIN + (gridWidth - usedWidth) / 2
	local originY = GRID_TOP_MARGIN + (gridHeight - usedHeight) / 2

	local tiles: { Tile } = {}
	for index = 0, GRID_COLUMNS * GRID_ROWS - 1 do
		local col = index % GRID_COLUMNS
		local row = math.floor(index / GRID_COLUMNS)
		local x = originX + col * (tileSize + GRID_GAP)
		local y = originY + row * (tileSize + GRID_GAP)
		local button = Factory.New("TextButton", {
			Name = "Tile",
			Size = UDim2.fromOffset(tileSize, tileSize),
			Position = UDim2.fromOffset(x, y),
			BackgroundColor3 = Colors.PanelSoft,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 4,
			Parent = canvas,
		})
		Factory.Corner(button, 10)
		Factory.Stroke(button, Colors.Line, 0.55, 1.5)
		local glow = Factory.New("Frame", {
			Name = "Glow",
			Size = UDim2.new(1, -2, 1, -2),
			Position = UDim2.fromOffset(1, 1),
			BackgroundColor3 = HOT_GLOW_COLOR,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = button,
		})
		Factory.Corner(glow, 9)
		-- Countdown bar: a thin strip pinned to the tile's bottom edge that
		-- shrinks from full width to nothing over the reaction window --
		-- built once per tile and reused every time it goes hot, rather than
		-- created/destroyed each round.
		local bar = Factory.New("Frame", {
			Name = "Bar",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 3, 1, -3),
			Size = UDim2.new(1, -6, 0, 4),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = button,
		})
		Factory.Corner(bar, 2)
		table.insert(tiles, { button = button, bar = bar, glow = glow })
	end

	local function setTileHot(tile: Tile, hot: boolean)
		tile.button.BackgroundColor3 = if hot then HOT_COLOR else Colors.PanelSoft
		tile.glow.BackgroundTransparency = if hot then 0.55 else 1
		tile.bar.BackgroundTransparency = if hot then 0.15 else 1
		tile.bar.BackgroundColor3 = Colors.Ink
	end

	local function endGame()
		if not running then
			return
		end
		running = false
		round += 1
		if hotIndex then
			setTileHot(tiles[hotIndex], false)
		end
		GameShell.Shake(canvas, api.reduceMotion)
		local failedTile = if hotIndex then tiles[hotIndex] else tiles[1]
		GameShell.Burst(
			canvas,
			failedTile.button.Position + UDim2.fromOffset(tileSize / 2, tileSize / 2),
			Colors.Danger,
			api.reduceMotion
		)
		api.gameOver(score)
	end

	local function registerStreak(quick: boolean)
		if quick then
			streak += 1
		else
			streak = 0
		end
		if streak >= 2 then
			streakLabel.Text = string.format("%dx QUICK", streak)
			streakLabel.TextColor3 = if streak >= STREAK_FLASH_EVERY then Colors.Gold else Colors.Mint
			streakLabel.TextTransparency = 0
			if not api.reduceMotion then
				local pop = Factory.New("UIScale", { Scale = 1.3, Parent = streakLabel })
				TweenService
					:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
					:Play()
			end
			local fadeRound = round
			task.delay(1.4, function()
				if fadeRound == round and streakLabel.Parent then
					if api.reduceMotion then
						streakLabel.TextTransparency = 1
					else
						TweenService:Create(streakLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
					end
				end
			end)
		else
			streakLabel.TextTransparency = 1
		end
		if streak > 0 and streak % STREAK_FLASH_EVERY == 0 then
			flashScreen(Colors.Gold, 0.75)
			api.sounds:Play("Success")
		end
	end

	local function lightNextTile()
		if not running then
			return
		end
		local nextIndex = math.random(1, #tiles)
		if #tiles > 1 then
			while nextIndex == hotIndex do
				nextIndex = math.random(1, #tiles)
			end
		end
		hotIndex = nextIndex
		hotWindow = math.max(MIN_WINDOW, BASE_WINDOW - score * WINDOW_STEP_PER_SCORE)
		hotStartedAt = os.clock()
		setTileHot(tiles[nextIndex], true)
		local myRound = round
		task.delay(hotWindow, function()
			if myRound == round and running and hotIndex == nextIndex then
				endGame()
			end
		end)
	end

	local function onTileTapped(index: number)
		if not running then
			return
		end
		if index ~= hotIndex then
			endGame()
			return
		end
		local reactionTime = os.clock() - hotStartedAt
		local tile = tiles[index]
		setTileHot(tile, false)
		hotIndex = nil
		round += 1

		score += 1
		api.setScore(score)
		api.sounds:Play("Like")
		GameShell.Burst(
			canvas,
			tile.button.Position + UDim2.fromOffset(tileSize / 2, tileSize / 2),
			HOT_COLOR,
			api.reduceMotion
		)
		if not api.reduceMotion then
			local pop = Factory.New("UIScale", { Scale = 0.82, Parent = tile.button })
			TweenService
				:Create(pop, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end
		registerStreak(reactionTime <= hotWindow * QUICK_REACTION_FRACTION)

		local myRound = round
		task.delay(NEXT_TILE_DELAY, function()
			if myRound == round and running then
				lightNextTile()
			end
		end)
	end

	local tileConnections: { RBXScriptConnection } = {}
	for index, tile in tiles do
		table.insert(
			tileConnections,
			tile.button.Activated:Connect(function()
				onTileTapped(index)
			end)
		)
	end

	-- Purely visual: shrinks the hot tile's countdown bar toward zero width
	-- over hotWindow. The actual timeout is the task.delay in
	-- lightNextTile/onTileTapped above, not this -- a paused/dropped frame
	-- here only makes the bar look slightly off, never desyncs the real
	-- countdown a player is scored against.
	local heartbeatConn = RunService.Heartbeat:Connect(function()
		if not running or not hotIndex then
			return
		end
		local tile = tiles[hotIndex :: number]
		local remaining = math.clamp(1 - (os.clock() - hotStartedAt) / hotWindow, 0, 1)
		tile.bar.Size = UDim2.new(remaining, -6 * remaining, 0, 4)
	end)

	lightNextTile()

	return function()
		running = false
		round += 1
		heartbeatConn:Disconnect()
		for _, connection in tileConnections do
			connection:Disconnect()
		end
		backdrop:Destroy()
		flashOverlay:Destroy()
		streakLabel:Destroy()
		for _, tile in tiles do
			tile.button:Destroy()
		end
		table.clear(tiles)
	end
end

return Game
