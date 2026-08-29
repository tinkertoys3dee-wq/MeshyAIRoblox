--!strict

-- Neon Snake: classic grid snake with a swipe/arrow-key/WASD direction
-- input. Score is food eaten (one point each), and the tick interval
-- shortens as the snake grows so the game keeps getting harder without a
-- separate difficulty tier, the same trick DinoRunner uses with its speed
-- ramp.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors

local CELL = 23 -- bumped up from 18 -- fewer, bigger cells so the arena reads as a tighter, more dangerous space instead of a sprawling grid
local MAX_COLS = 18
local MAX_ROWS = 11
local INITIAL_LENGTH = 3
local BASE_MOVE_INTERVAL = 0.16
local MIN_MOVE_INTERVAL = 0.078
local INTERVAL_STEP_PER_FOOD = 0.006
local SWIPE_MIN_DISTANCE = 16
local HEAD_COLOR = Colors.Cyan
local BODY_COLOR = Colors.Violet
local TAIL_COLOR = Color3.fromRGB(94, 66, 190) -- a touch darker than BODY_COLOR
local COMBO_WINDOW = 3 -- seconds between food pickups before the streak resets

-- Obstacle blocks: static hazards that start appearing once a run has some
-- legs, permanent for the rest of that run -- real stakes beyond "don't hit
-- yourself/the wall", the same "the map fights back eventually" trick
-- DinoRunner's pterodactyls add on top of its base jump.
local OBSTACLE_UNLOCK_SCORE = 5
local OBSTACLE_CHANCE = 0.4 -- per food eaten, once unlocked
local MAX_OBSTACLES = 6
local OBSTACLE_MIN_HEAD_DISTANCE = 3 -- cells -- never spawn right next to the current head

-- Bonus food: a time-limited, higher-value pickup that shows up periodically
-- alongside the routine gold food -- worth chasing down fast rather than
-- always being the safest, slowest path to the next point.
local BONUS_FOOD_EVERY = 4 -- one bonus food offered every this-many regular foods eaten
local BONUS_FOOD_SCORE = 3
local BONUS_FOOD_LIFETIME = 4.5
local BONUS_FOOD_COLOR = Color3.fromRGB(255, 92, 168)

type Point = { x: number, y: number }
type Direction = { x: number, y: number }
type Obstacle = { frame: Frame, point: Point }
type BonusFood = { frame: Frame, point: Point, token: number }

local Game = {} :: GameShell.GameModule
Game.Name = "Neon Snake"
Game.Key = "NeonSnake"

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local score = 0
	local comboCount = 0
	local lastEatTime = 0
	local obstacles: { Obstacle } = {}
	local regularFoodCount = 0
	local bonusFood: BonusFood? = nil
	local bonusFoodTokenCounter = 0

	-- Floored + defaulted the same way DinoRunner's width()/groundY() are:
	-- AbsoluteSize can be fractional or briefly zero before layout settles,
	-- and math.random errors on a non-integer/zero-range argument.
	local function widthPx(): number
		local w = math.floor(canvas.AbsoluteSize.X)
		return if w > 40 then w else 504
	end
	local function heightPx(): number
		local h = math.floor(canvas.AbsoluteSize.Y)
		return if h > 40 then h else 270
	end

	local cols = math.clamp(math.floor(widthPx() / CELL), 10, MAX_COLS)
	local rows = math.clamp(math.floor(heightPx() / CELL), 8, MAX_ROWS)
	local boardWidth = cols * CELL
	local boardHeight = rows * CELL
	local originX = math.floor((widthPx() - boardWidth) / 2)
	local originY = math.floor((heightPx() - boardHeight) / 2)

	local function toPixel(point: Point): UDim2
		return UDim2.fromOffset(originX + point.x * CELL, originY + point.y * CELL)
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

	-- A single soft glow centered behind the arena, the same "spotlight
	-- behind the panel" depth trick GamesHub's tiles and App's own page
	-- backgrounds use -- purely ambient, so it's a no-op decoration under
	-- reduceMotion rather than gated (it never moves, so there's nothing to
	-- suppress).
	local glowBlob = Factory.Blob(canvas, math.max(boardWidth, boardHeight) * 0.85, UDim2.new(), Colors.Violet, 0.88)
	glowBlob.AnchorPoint = Vector2.new(0.5, 0.5)
	glowBlob.Position = UDim2.fromOffset(originX + boardWidth / 2, originY + boardHeight / 2)

	local arena = Factory.New("Frame", {
		Name = "Arena",
		Position = UDim2.fromOffset(originX - 4, originY - 4),
		Size = UDim2.fromOffset(boardWidth + 8, boardHeight + 8),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = canvas,
	})
	Factory.Corner(arena, 10)
	local arenaStroke = Factory.Stroke(arena, Colors.Violet, 0.55, 1.5)
	-- A slow neon-buzz pulse on the border transparency -- purely cosmetic,
	-- so it's the first thing skipped under reduceMotion.
	if not api.reduceMotion then
		TweenService:Create(
			arenaStroke,
			TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.15 }
		):Play()
	end

	-- A sparse, faint tile grid within the arena -- purely a texture cue for
	-- "this is a grid game", drawn as widely spaced dots rather than a full
	-- line-per-cell mesh so the instance count stays small on a big board.
	if not api.reduceMotion then
		for gx = 0, cols, 3 do
			for gy = 0, rows, 3 do
				local dot = Factory.New("Frame", {
					Name = "GridDot",
					Size = UDim2.fromOffset(2, 2),
					Position = UDim2.fromOffset(originX + gx * CELL, originY + gy * CELL),
					BackgroundColor3 = Colors.Line,
					BackgroundTransparency = 0.75,
					BorderSizePixel = 0,
					ZIndex = 1,
					Parent = canvas,
				})
				Factory.Corner(dot, 1)
			end
		end
	end

	local function randomCell(): Point
		return { x = math.random(0, cols - 1), y = math.random(0, rows - 1) }
	end

	local startX = math.floor(cols / 2)
	local startY = math.floor(rows / 2)
	local segments: { Point } = {}
	local segmentFrames: { Frame } = {}
	for i = 0, INITIAL_LENGTH - 1 do
		local point = { x = startX - i, y = startY }
		table.insert(segments, point)
		local frame = Factory.New("Frame", {
			Name = "Segment",
			Size = UDim2.fromOffset(CELL - 3, CELL - 3),
			Position = toPixel(point),
			BackgroundColor3 = if i == 0 then HEAD_COLOR elseif i == INITIAL_LENGTH - 1 then TAIL_COLOR else BODY_COLOR,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = canvas,
		})
		Factory.Corner(frame, 5)
		table.insert(segmentFrames, frame)
	end

	-- A soft glow trailing just behind the head -- pure decoration (the head
	-- segment itself already carries the real position), so it's the first
	-- thing skipped under reduceMotion.
	local headGlow: Frame? = nil
	if not api.reduceMotion then
		headGlow = Factory.New("Frame", {
			Name = "HeadGlow",
			Size = UDim2.fromOffset(CELL + 10, CELL + 10),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = HEAD_COLOR,
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = canvas,
		})
		Factory.Corner(headGlow, 12)
	end

	local eyeLeft = Factory.New("Frame", {
		Name = "EyeLeft",
		Size = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Colors.Ink,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = canvas,
	})
	Factory.Corner(eyeLeft, 2)
	local eyeRight = Factory.New("Frame", {
		Name = "EyeRight",
		Size = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Colors.Ink,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = canvas,
	})
	Factory.Corner(eyeRight, 2)

	local direction: Direction = { x = 1, y = 0 }
	local pendingDirection: Direction = { x = 1, y = 0 }

	local function occupies(point: Point, list: { Point }, skipLast: boolean): boolean
		local limit = if skipLast then #list - 1 else #list
		for i = 1, limit do
			local segment = list[i]
			if segment.x == point.x and segment.y == point.y then
				return true
			end
		end
		return false
	end

	local food: Point = { x = 0, y = 0 }
	local foodFrame = Factory.New("Frame", {
		Name = "Food",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(CELL - 5, CELL - 5),
		BackgroundColor3 = Colors.Gold,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = canvas,
	})
	Factory.Corner(foodFrame, 99)
	Factory.Stroke(foodFrame, Colors.Ink, 0.35, 1.5)
	local foodPulse = Factory.New("UIScale", { Scale = 1, Parent = foodFrame })

	-- Shared "is this cell already spoken for" check used by every random
	-- placement below (food, bonus food, obstacles) -- one place to keep in
	-- sync with everything currently on the board.
	local function cellBlocked(point: Point): boolean
		if occupies(point, segments, false) then
			return true
		end
		if point.x == food.x and point.y == food.y then
			return true
		end
		if bonusFood and point.x == bonusFood.point.x and point.y == bonusFood.point.y then
			return true
		end
		for _, obstacle in obstacles do
			if obstacle.point.x == point.x and obstacle.point.y == point.y then
				return true
			end
		end
		return false
	end

	-- Full-canvas tint for streak milestones, same trick FlappyBird/ColorSwitch
	-- use for their own near-miss/combo flashes.
	local flashOverlay = Factory.New("Frame", {
		Name = "FlashOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Gold,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 45,
		Parent = canvas,
	})
	local comboLabel = Factory.Label(canvas, "", UDim2.fromOffset(160, 28), {
		Name = "ComboLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Color = Colors.Gold,
		Font = Theme.Fonts.Black,
		TextSize = 18,
		AlignX = Enum.TextXAlignment.Center,
		Transparency = 1,
		ZIndex = 46,
	})
	Factory.New("UIStroke", { Color = Colors.Ink, Thickness = 2, Transparency = 0.4, Parent = comboLabel })

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

	local comboFadeToken = 0
	local function showScorePopup(position: UDim2, combo: number, amount: number?, popupColor: Color3?)
		local gained = amount or 1
		if not api.reduceMotion then
			local popupText = if combo >= 2
				then string.format("+%d  x%d", gained, combo)
				else string.format("+%d", gained)
			local popup = Factory.Label(canvas, popupText, UDim2.fromOffset(90, 20), {
				Name = "ScorePopup",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = position,
				Color = popupColor or (if combo >= 5 then Colors.Gold else Colors.Mint),
				Font = Theme.Fonts.Black,
				TextSize = 15,
				AlignX = Enum.TextXAlignment.Center,
				ZIndex = 47,
			})
			Factory.New("UIStroke", { Color = Colors.Ink, Thickness = 1.5, Transparency = 0.5, Parent = popup })
			local tween =
				TweenService:Create(popup, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = position - UDim2.fromOffset(0, 26),
					TextTransparency = 1,
				})
			tween.Completed:Connect(function()
				popup:Destroy()
			end)
			tween:Play()
		end

		comboFadeToken += 1
		local myToken = comboFadeToken
		if combo >= 2 then
			comboLabel.Text = string.format("%dx STREAK", combo)
			comboLabel.TextTransparency = 0
			if not api.reduceMotion then
				local pop = Factory.New("UIScale", { Scale = 1.3, Parent = comboLabel })
				TweenService
					:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
					:Play()
			end
			task.delay(COMBO_WINDOW, function()
				if myToken == comboFadeToken and comboLabel.Parent then
					if api.reduceMotion then
						comboLabel.TextTransparency = 1
					else
						TweenService:Create(comboLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
					end
				end
			end)
		end

		if combo > 0 and combo % 5 == 0 then
			flashScreen(Colors.Gold, 0.75)
			api.sounds:Play("Success")
			GameShell.Shake(canvas, api.reduceMotion, 0.55)
		end
	end

	local function placeFood()
		local attempt = randomCell()
		local tries = 0
		while cellBlocked(attempt) and tries < 200 do
			attempt = randomCell()
			tries += 1
		end
		food = attempt
		foodFrame.Position = toPixel(food) + UDim2.fromOffset(CELL / 2, CELL / 2)
	end
	placeFood()

	-- Obstacle blocks: a plain hazard-striped tile, permanent once placed.
	local function spawnObstacle()
		if #obstacles >= MAX_OBSTACLES then
			return
		end
		local head = segments[1]
		local attempt = randomCell()
		local tries = 0
		while
			(
				cellBlocked(attempt)
				or math.abs(attempt.x - head.x) + math.abs(attempt.y - head.y) < OBSTACLE_MIN_HEAD_DISTANCE
			) and tries < 200
		do
			attempt = randomCell()
			tries += 1
		end
		if tries >= 200 then
			-- Board's too crowded to place one fairly right now -- skip this
			-- roll rather than force a cell that might be unfair or missing.
			return
		end
		local frame = Factory.New("Frame", {
			Name = "Obstacle",
			Size = UDim2.fromOffset(CELL - 3, CELL - 3),
			Position = toPixel(attempt),
			BackgroundColor3 = Colors.Danger,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = canvas,
		})
		Factory.Corner(frame, 4)
		Factory.Stroke(frame, Color3.fromRGB(255, 200, 120), 0.35, 1.5)
		-- A couple of diagonal hazard ribs -- reads as "caution", distinct
		-- silhouette from every food/snake tile on the board.
		for _, fraction in { 0.25, 0.65 } do
			Factory.New("Frame", {
				Name = "HazardStripe",
				Size = UDim2.new(0, (CELL - 3) * 1.4, 0, 3),
				Position = UDim2.new(fraction, 0, 0, (CELL - 3) * fraction),
				Rotation = 45,
				BackgroundColor3 = Color3.fromRGB(255, 200, 120),
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = frame,
			})
		end
		if not api.reduceMotion then
			GameShell.Burst(canvas, frame.Position + UDim2.fromOffset(CELL / 2, CELL / 2), Colors.Danger, false)
		end
		table.insert(obstacles, { frame = frame, point = attempt })
	end

	-- Bonus food: distinct color/glyph, a shrinking countdown ring, and a
	-- timeout that despawns it if it's not caught in time.
	local function spawnBonusFood()
		local attempt = randomCell()
		local tries = 0
		while cellBlocked(attempt) and tries < 200 do
			attempt = randomCell()
			tries += 1
		end
		if tries >= 200 then
			return
		end
		bonusFoodTokenCounter += 1
		local myToken = bonusFoodTokenCounter
		local frame = Factory.New("Frame", {
			Name = "BonusFood",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(CELL - 4, CELL - 4),
			Position = toPixel(attempt) + UDim2.fromOffset(CELL / 2, CELL / 2),
			BackgroundColor3 = BONUS_FOOD_COLOR,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = canvas,
		})
		Factory.Corner(frame, 6)
		Factory.Stroke(frame, Colors.Ink, 0.3, 1.5)
		Factory.Label(frame, "★", UDim2.fromScale(1, 1), {
			TextSize = 11,
			Color = Colors.Ink,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 6,
		})
		-- The ring's own stroke transparency ticks from opaque to fully faded
		-- over the food's lifetime -- a countdown a player reads at a glance
		-- without needing a number.
		local ring = Factory.New("Frame", {
			Name = "BonusRing",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.7, 1.7),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Parent = frame,
		})
		Factory.Corner(ring, 99)
		local ringStroke = Factory.New("UIStroke", { Color = BONUS_FOOD_COLOR, Thickness = 2.5, Parent = ring })
		if not api.reduceMotion then
			local pulse = Factory.New("UIScale", { Scale = 1, Parent = frame })
			TweenService:Create(
				pulse,
				TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.22 }
			):Play()
			TweenService:Create(ringStroke, TweenInfo.new(BONUS_FOOD_LIFETIME, Enum.EasingStyle.Linear), {
				Transparency = 1,
			}):Play()
		end
		bonusFood = { frame = frame, point = attempt, token = myToken }
		task.delay(BONUS_FOOD_LIFETIME, function()
			if bonusFood and bonusFood.token == myToken then
				bonusFood.frame:Destroy()
				bonusFood = nil
			end
		end)
	end

	local function updateEyes()
		local head = segments[1]
		local basePosition = toPixel(head)
		local offsetX = if direction.x ~= 0 then (if direction.x > 0 then CELL - 6 else 2) else CELL / 2 - 1.5
		local offsetY = if direction.y ~= 0 then (if direction.y > 0 then CELL - 6 else 2) else CELL / 2 - 1.5
		local spread = 5
		if direction.x ~= 0 then
			eyeLeft.Position = basePosition + UDim2.fromOffset(offsetX, CELL / 2 - spread)
			eyeRight.Position = basePosition + UDim2.fromOffset(offsetX, CELL / 2 + spread - 3)
		else
			eyeLeft.Position = basePosition + UDim2.fromOffset(CELL / 2 - spread, offsetY)
			eyeRight.Position = basePosition + UDim2.fromOffset(CELL / 2 + spread - 3, offsetY)
		end
		if headGlow then
			headGlow.Position = basePosition + UDim2.fromOffset(CELL / 2, CELL / 2)
		end
	end
	updateEyes()

	local function trySetDirection(nextDirection: Direction)
		-- Rejecting an immediate 180-degree reversal (into the segment right
		-- behind the head) here, rather than only at tick time, means a
		-- same-tick double-input can't sneak a reversal through either.
		if nextDirection.x == -direction.x and nextDirection.y == -direction.y then
			return
		end
		pendingDirection = nextDirection
	end

	local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.W then
			trySetDirection({ x = 0, y = -1 })
		elseif input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.S then
			trySetDirection({ x = 0, y = 1 })
		elseif input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then
			trySetDirection({ x = -1, y = 0 })
		elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then
			trySetDirection({ x = 1, y = 0 })
		end
	end)

	-- Swipe steering for touch/mouse: a plain tap (below the distance
	-- threshold) is deliberately a no-op rather than a direction guess, so an
	-- imprecise tap never sends the snake somewhere the player didn't intend.
	local swipeStart: Vector2? = nil
	local swipeBeganConn = canvas.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			swipeStart = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	local swipeEndedConn = canvas.InputEnded:Connect(function(input)
		if not swipeStart then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - swipeStart
		swipeStart = nil
		if delta.Magnitude < SWIPE_MIN_DISTANCE then
			return
		end
		if math.abs(delta.X) > math.abs(delta.Y) then
			trySetDirection({ x = if delta.X > 0 then 1 else -1, y = 0 })
		else
			trySetDirection({ x = 0, y = if delta.Y > 0 then 1 else -1 })
		end
	end)

	local function endGame()
		if not running then
			return
		end
		running = false
		GameShell.Shake(canvas, api.reduceMotion)
		GameShell.Burst(
			canvas,
			toPixel(segments[1]) + UDim2.fromOffset(CELL / 2, CELL / 2),
			Colors.Danger,
			api.reduceMotion
		)
		api.gameOver(score)
	end

	local elapsedSinceMove = 0
	local heartbeatConn: RBXScriptConnection
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		dt = math.min(dt, 1 / 20)

		if not api.reduceMotion then
			local pulse = 1 + 0.12 * math.sin(os.clock() * 6)
			foodPulse.Scale = pulse
		end

		local moveInterval = math.max(MIN_MOVE_INTERVAL, BASE_MOVE_INTERVAL - score * INTERVAL_STEP_PER_FOOD)
		elapsedSinceMove += dt
		if elapsedSinceMove < moveInterval then
			return
		end
		elapsedSinceMove = 0

		direction = pendingDirection
		local head = segments[1]
		local newHead: Point = { x = head.x + direction.x, y = head.y + direction.y }

		if newHead.x < 0 or newHead.x >= cols or newHead.y < 0 or newHead.y >= rows then
			endGame()
			return
		end
		for _, obstacle in obstacles do
			if obstacle.point.x == newHead.x and obstacle.point.y == newHead.y then
				endGame()
				return
			end
		end
		local eating = newHead.x == food.x and newHead.y == food.y
		local eatingBonus = bonusFood ~= nil and newHead.x == bonusFood.point.x and newHead.y == bonusFood.point.y
		local growing = eating or eatingBonus
		if occupies(newHead, segments, not growing) then
			endGame()
			return
		end

		-- The previous head becomes a body segment now that a new head is
		-- about to take its place -- recolor rather than recreate, since the
		-- frame's grid position (and thus its own Position) doesn't change.
		segmentFrames[1].BackgroundColor3 = BODY_COLOR
		table.insert(segments, 1, newHead)
		local newHeadFrame = Factory.New("Frame", {
			Name = "Segment",
			Size = UDim2.fromOffset(CELL - 3, CELL - 3),
			Position = toPixel(newHead),
			BackgroundColor3 = HEAD_COLOR,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = canvas,
		})
		Factory.Corner(newHeadFrame, 5)
		table.insert(segmentFrames, 1, newHeadFrame)

		if eating then
			score += 1
			api.setScore(score)
			api.sounds:Play("Success")
			local eatenFoodPosition = foodFrame.Position
			GameShell.Burst(canvas, eatenFoodPosition, Colors.Gold, api.reduceMotion)
			GameShell.Ring(canvas, eatenFoodPosition, Colors.Gold, api.reduceMotion, CELL)
			GameShell.Shake(canvas, api.reduceMotion, 0.15)
			local now = os.clock()
			comboCount = if now - lastEatTime <= COMBO_WINDOW then comboCount + 1 else 1
			lastEatTime = now
			showScorePopup(eatenFoodPosition, comboCount)
			-- The new tail's frame gets the dedicated tail shade -- otherwise
			-- a snake that only ever grows would never show one.
			segmentFrames[#segmentFrames].BackgroundColor3 = TAIL_COLOR
			placeFood()

			regularFoodCount += 1
			if score >= OBSTACLE_UNLOCK_SCORE and math.random() < OBSTACLE_CHANCE then
				spawnObstacle()
			end
			if not bonusFood and regularFoodCount % BONUS_FOOD_EVERY == 0 then
				spawnBonusFood()
			end
		elseif eatingBonus then
			local activeBonusFood = bonusFood :: BonusFood
			score += BONUS_FOOD_SCORE
			api.setScore(score)
			api.sounds:Play("Success")
			local bonusPosition = activeBonusFood.frame.Position
			GameShell.Burst(canvas, bonusPosition, BONUS_FOOD_COLOR, api.reduceMotion)
			GameShell.Ring(canvas, bonusPosition, BONUS_FOOD_COLOR, api.reduceMotion, CELL * 1.4)
			GameShell.Shake(canvas, api.reduceMotion, 0.35)
			local now = os.clock()
			comboCount = if now - lastEatTime <= COMBO_WINDOW then comboCount + 1 else 1
			lastEatTime = now
			showScorePopup(bonusPosition, comboCount, BONUS_FOOD_SCORE, BONUS_FOOD_COLOR)
			segmentFrames[#segmentFrames].BackgroundColor3 = TAIL_COLOR
			activeBonusFood.frame:Destroy()
			bonusFood = nil
		else
			local removedPoint = table.remove(segments)
			local removedFrame = table.remove(segmentFrames)
			if removedPoint and removedFrame then
				removedFrame:Destroy()
			end
			if #segmentFrames > 0 then
				segmentFrames[#segmentFrames].BackgroundColor3 = TAIL_COLOR
			end
		end

		updateEyes()
	end)

	return function()
		running = false
		heartbeatConn:Disconnect()
		inputConn:Disconnect()
		swipeBeganConn:Disconnect()
		swipeEndedConn:Disconnect()
		backdrop:Destroy()
		glowBlob:Destroy()
		arena:Destroy()
		foodFrame:Destroy()
		flashOverlay:Destroy()
		comboLabel:Destroy()
		eyeLeft:Destroy()
		eyeRight:Destroy()
		for _, obstacle in obstacles do
			obstacle.frame:Destroy()
		end
		table.clear(obstacles)
		if bonusFood then
			bonusFood.frame:Destroy()
			bonusFood = nil
		end
		if headGlow then
			headGlow:Destroy()
		end
		for _, frame in segmentFrames do
			frame:Destroy()
		end
		table.clear(segments)
		table.clear(segmentFrames)
		for _, child in canvas:GetChildren() do
			if child.Name == "GridDot" then
				child:Destroy()
			end
		end
	end
end

return Game
