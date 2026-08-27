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

local CELL = 18
local INITIAL_LENGTH = 3
local BASE_MOVE_INTERVAL = 0.16
local MIN_MOVE_INTERVAL = 0.078
local INTERVAL_STEP_PER_FOOD = 0.006
local SWIPE_MIN_DISTANCE = 16
local HEAD_COLOR = Colors.Cyan
local BODY_COLOR = Colors.Violet
local TAIL_COLOR = Color3.fromRGB(94, 66, 190) -- a touch darker than BODY_COLOR

type Point = { x: number, y: number }
type Direction = { x: number, y: number }

local Game = {} :: GameShell.GameModule
Game.Name = "Neon Snake"
Game.Key = "NeonSnake"

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local score = 0

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

	local cols = math.max(12, math.floor(widthPx() / CELL))
	local rows = math.max(10, math.floor(heightPx() / CELL))
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

	local function placeFood()
		local attempt = randomCell()
		local tries = 0
		while occupies(attempt, segments, false) and tries < 200 do
			attempt = randomCell()
			tries += 1
		end
		food = attempt
		foodFrame.Position = toPixel(food) + UDim2.fromOffset(CELL / 2, CELL / 2)
	end
	placeFood()

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
		local eating = newHead.x == food.x and newHead.y == food.y
		if occupies(newHead, segments, not eating) then
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
			GameShell.Burst(canvas, foodFrame.Position, Colors.Gold, api.reduceMotion)
			-- The new tail's frame gets the dedicated tail shade -- otherwise
			-- a snake that only ever grows would never show one.
			segmentFrames[#segmentFrames].BackgroundColor3 = TAIL_COLOR
			placeFood()
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
		eyeLeft:Destroy()
		eyeRight:Destroy()
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
