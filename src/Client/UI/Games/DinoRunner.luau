--!strict

-- Dino Runner: tap/click/space to jump over cacti scrolling in from the
-- right at ground level. Score is distance survived (classic Chrome-dino
-- scoring, not an obstacle counter), and speed ramps with it so the game
-- keeps getting harder without needing separate difficulty tiers.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors

local GRAVITY = 2200
local JUMP_VELOCITY = -760
local DINO_SIZE = 30
local DINO_X = 56
local GROUND_MARGIN = 24
local BASE_SPEED = 260
local SPEED_PER_SCORE = 0.6
local MAX_SPEED = 640
local SCORE_PER_SECOND = 10
-- In hundredths of a second so math.random (integers only) can pick between
-- them directly -- computing these from float seconds risks a value like
-- 1.6 * 100 landing on 159.999999... and erroring math.random on a
-- non-integer argument.
local MIN_OBSTACLE_GAP_CENTIS = 90
local MAX_OBSTACLE_GAP_CENTIS = 160

type Obstacle = { frame: Frame, x: number, width: number, height: number }

local Game = {} :: GameShell.GameModule
Game.Name = "Dino Runner"
Game.Key = "DinoRunner"

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local dinoY = 0
	local velocityY = 0
	local onGround = true
	local elapsed = 0
	local score = 0
	local displayedScore = -1
	local obstacles: { Obstacle } = {}
	local timeSinceObstacle = 0
	local nextObstacleGap = MIN_OBSTACLE_GAP_CENTIS / 100

	-- Floored: AbsoluteSize can be fractional (UI scaling), and math.random
	-- errors on a non-integer argument -- spawnObstacle's width() feeds it.
	local function groundY(): number
		local h = math.floor(canvas.AbsoluteSize.Y)
		if h <= 40 then
			h = 260
		end
		return h - GROUND_MARGIN
	end
	local function width(): number
		local w = math.floor(canvas.AbsoluteSize.X)
		return if w > 40 then w else 520
	end

	Factory.New("Frame", {
		Name = "Ground",
		Size = UDim2.new(1, 0, 0, 2),
		Position = UDim2.fromOffset(0, groundY() + DINO_SIZE),
		BackgroundColor3 = Colors.Line,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = canvas,
	})

	local dino = Factory.New("Frame", {
		Name = "Dino",
		Size = UDim2.fromOffset(DINO_SIZE, DINO_SIZE),
		Position = UDim2.fromOffset(DINO_X, groundY()),
		BackgroundColor3 = Colors.Mint,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = canvas,
	})
	Factory.Corner(dino, 6)
	Factory.Stroke(dino, Colors.Ink, 0.3, 1.5)
	dinoY = groundY()

	local function jump()
		if not running or not onGround then
			return
		end
		velocityY = JUMP_VELOCITY
		onGround = false
		api.sounds:Play("Press")
	end

	local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.Space
			or input.KeyCode == Enum.KeyCode.Up
		then
			jump()
		end
	end)
	local tapConn = canvas.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			jump()
		end
	end)

	local function currentSpeed(): number
		return math.min(MAX_SPEED, BASE_SPEED + score * SPEED_PER_SCORE)
	end

	local function spawnObstacle()
		local h = math.random(24, 42)
		local w = math.random(16, 26)
		local frame = Factory.New("Frame", {
			Name = "Cactus",
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = Colors.Rose,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = canvas,
		})
		Factory.Corner(frame, 4)
		local x = width() + w
		table.insert(obstacles, { frame = frame, x = x, width = w, height = h })
	end

	local function endGame()
		if not running then
			return
		end
		running = false
		api.gameOver(score)
	end

	local heartbeatConn: RBXScriptConnection
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		dt = math.min(dt, 1 / 20)
		elapsed += dt
		score = math.floor(elapsed * SCORE_PER_SECOND)
		if score ~= displayedScore then
			displayedScore = score
			api.setScore(score)
		end

		local ground = groundY()
		velocityY += GRAVITY * dt
		dinoY += velocityY * dt
		if dinoY >= ground then
			dinoY = ground
			velocityY = 0
			onGround = true
		end
		dino.Position = UDim2.fromOffset(DINO_X, dinoY)

		local speed = currentSpeed()
		timeSinceObstacle += dt
		if timeSinceObstacle >= nextObstacleGap then
			timeSinceObstacle = 0
			nextObstacleGap = math.random(MIN_OBSTACLE_GAP_CENTIS, MAX_OBSTACLE_GAP_CENTIS) / 100
			spawnObstacle()
		end

		local dinoLeft, dinoRight = DINO_X, DINO_X + DINO_SIZE
		local dinoTop, dinoBottom = dinoY, dinoY + DINO_SIZE

		for i = #obstacles, 1, -1 do
			local obstacle = obstacles[i]
			obstacle.x -= speed * dt
			local obstacleTop = ground + DINO_SIZE - obstacle.height
			obstacle.frame.Position = UDim2.fromOffset(obstacle.x, obstacleTop)

			if obstacle.x + obstacle.width < 0 then
				obstacle.frame:Destroy()
				table.remove(obstacles, i)
				continue
			end

			local obLeft, obRight = obstacle.x, obstacle.x + obstacle.width
			local obTop, obBottom = obstacleTop, obstacleTop + obstacle.height
			if dinoRight > obLeft and dinoLeft < obRight and dinoBottom > obTop and dinoTop < obBottom then
				endGame()
				return
			end
		end
	end)

	return function()
		running = false
		heartbeatConn:Disconnect()
		inputConn:Disconnect()
		tapConn:Disconnect()
		dino:Destroy()
		for _, obstacle in obstacles do
			obstacle.frame:Destroy()
		end
		table.clear(obstacles)
	end
end

return Game
