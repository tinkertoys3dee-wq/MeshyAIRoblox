--!strict

-- Dino Runner: tap/click/space to jump over cacti scrolling in from the
-- right at ground level. Score is distance survived (classic Chrome-dino
-- scoring, not an obstacle counter), and speed ramps with it so the game
-- keeps getting harder without needing separate difficulty tiers.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
local TICK_COUNT = 8
local TICK_SPACING = 70
-- In hundredths of a second so math.random (integers only) can pick between
-- them directly -- computing these from float seconds risks a value like
-- 1.6 * 100 landing on 159.999999... and erroring math.random on a
-- non-integer argument.
local MIN_OBSTACLE_GAP_CENTIS = 90
local MAX_OBSTACLE_GAP_CENTIS = 160
local DAY_CYCLE_SECONDS = 45 -- full day-to-night-to-day loop
local STAR_COUNT = 10
local DUST_INTERVAL = 0.08 -- continuous foot-dust cadence while grounded
local SKY_NIGHT_TOP = Color3.fromRGB(21, 24, 48)
local SKY_NIGHT_BOTTOM = Color3.fromRGB(8, 9, 20)
local SUN_DAY_COLOR = Colors.Gold
local MOON_NIGHT_COLOR = Color3.fromRGB(214, 222, 240)

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
	local timeSinceDust = 0

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

	local sky = Factory.New("Frame", {
		Name = "Sky",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = canvas,
	})
	local skyDayTop, skyDayBottom = Colors.PanelSoft, Colors.Panel
	local skyGradient = Factory.Gradient(sky, { skyDayTop, skyDayBottom }, 90)
	-- Sun by day, moon by night -- same Frame, its color/position just tween
	-- across the cycle rather than swapping instances.
	local sun = Factory.New("Frame", {
		Name = "Sun",
		Size = UDim2.fromOffset(46, 46),
		Position = UDim2.new(1, -70, 0, 18),
		BackgroundColor3 = Colors.Gold,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = canvas,
	})
	Factory.Corner(sun, 23)

	-- Starfield: fully transparent by day, fades in as the sky darkens.
	-- Purely decorative background texture, so it's frozen invisible under
	-- reduceMotion rather than driven by the per-frame cycle update below.
	local stars: { { instance: Frame, twinklePhase: number } } = {}
	if not api.reduceMotion then
		for _ = 1, STAR_COUNT do
			local star = Factory.New("Frame", {
				Name = "Star",
				Size = UDim2.fromOffset(2, 2),
				Position = UDim2.fromOffset(math.random(10, 500), math.random(8, 140)),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 1,
				Parent = canvas,
			})
			Factory.Corner(star, 1)
			table.insert(stars, { instance = star, twinklePhase = math.random() * math.pi * 2 })
		end
	end

	-- A proper band with its own gradient reads as ground/dirt; the old
	-- 2px hairline was barely there.
	local groundBand = Factory.New("Frame", {
		Name = "Ground",
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.fromOffset(0, groundY() + DINO_SIZE),
		BackgroundColor3 = Colors.PanelSoft,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = canvas,
	})
	Factory.Gradient(groundBand, { Colors.PanelSoft, Colors.Ink }, 90)

	-- Short scrolling tick marks along the ground reinforce how fast the
	-- game is currently moving -- decorative (the obstacles alone already
	-- carry the real gameplay speed), so skipped entirely under reduceMotion
	-- rather than left scrolling in the background.
	local groundTicks: { { instance: Frame, x: number } } = {}
	if not api.reduceMotion then
		for i = 1, TICK_COUNT do
			local x = (i - 1) * TICK_SPACING
			local tick = Factory.New("Frame", {
				Name = "GroundTick",
				Size = UDim2.fromOffset(18, 2),
				Position = UDim2.fromOffset(x, groundY() + DINO_SIZE),
				BackgroundColor3 = Colors.Line,
				BackgroundTransparency = 0.65,
				BorderSizePixel = 0,
				ZIndex = 2,
				Parent = canvas,
			})
			table.insert(groundTicks, { instance = tick, x = x })
		end
	end

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
	-- Squash/stretch handle: cosmetic scale pulse on takeoff/landing, gated
	-- under reduceMotion the same way FlappyBird's flap-squash is -- the
	-- dino's actual jump arc (the gameplay motion) is unaffected either way.
	-- Children below (tail/legs/eye) inherit this scale automatically.
	local dinoScale = Factory.New("UIScale", { Scale = 1, Parent = dino })
	Factory.New("Frame", {
		Name = "Tail",
		Size = UDim2.fromOffset(DINO_SIZE * 0.3, DINO_SIZE * 0.22),
		Position = UDim2.fromOffset(-DINO_SIZE * 0.2, DINO_SIZE * 0.5),
		BackgroundColor3 = Colors.Mint,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = dino,
	})
	for _, fraction in { 0.14, 0.6 } do
		Factory.New("Frame", {
			Name = "Leg",
			Size = UDim2.fromOffset(DINO_SIZE * 0.22, DINO_SIZE * 0.26),
			Position = UDim2.new(0, DINO_SIZE * fraction, 1, -DINO_SIZE * 0.05),
			BackgroundColor3 = Color3.fromRGB(46, 189, 138),
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = dino,
		})
	end
	local eye = Factory.New("Frame", {
		Name = "Eye",
		Size = UDim2.fromOffset(DINO_SIZE * 0.28, DINO_SIZE * 0.28),
		Position = UDim2.fromOffset(DINO_SIZE * 0.56, DINO_SIZE * 0.04),
		BackgroundColor3 = Colors.Text,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = dino,
	})
	Factory.Corner(eye, DINO_SIZE * 0.14)
	Factory.New("Frame", {
		Name = "Pupil",
		Size = UDim2.fromOffset(DINO_SIZE * 0.12, DINO_SIZE * 0.12),
		Position = UDim2.fromOffset(DINO_SIZE * 0.72, DINO_SIZE * 0.1),
		BackgroundColor3 = Colors.Ink,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = dino,
	})
	dinoY = groundY()

	local function jump()
		if not running or not onGround then
			return
		end
		velocityY = JUMP_VELOCITY
		onGround = false
		api.sounds:Play("Press")
		GameShell.Burst(
			canvas,
			dino.Position + UDim2.fromOffset(DINO_SIZE / 2, DINO_SIZE),
			Colors.Line,
			api.reduceMotion
		)
		if not api.reduceMotion then
			dinoScale.Scale = 1
			TweenService
				:Create(
					dinoScale,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Scale = 1.25 }
				)
				:Play()
		end
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
		-- A couple of thin ribs read as cactus texture instead of a plain
		-- block; children of `frame` so they scroll and get destroyed with
		-- it for free, same trick as the pipe caps and dino's own details.
		for _, fraction in { 0.3, 0.7 } do
			Factory.New("Frame", {
				Name = "Rib",
				Size = UDim2.new(0, 1, 1, -4),
				Position = UDim2.new(fraction, 0, 0, 2),
				BackgroundColor3 = Colors.Ink,
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = frame,
			})
		end
		-- An arm on a random side about half the time, for silhouette
		-- variety between cacti.
		if math.random() < 0.5 then
			local armWidth = math.max(6, w * 0.45)
			local armHeight = math.max(8, h * 0.32)
			local onRight = math.random() < 0.5
			local arm = Factory.New("Frame", {
				Name = "Arm",
				Size = UDim2.fromOffset(armWidth, armHeight),
				Position = if onRight
					then UDim2.fromOffset(w - 2, h * 0.25)
					else UDim2.fromOffset(-armWidth + 2, h * 0.25),
				BackgroundColor3 = Colors.Rose,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = frame,
			})
			Factory.Corner(arm, 3)
		end
		local x = width() + w
		table.insert(obstacles, { frame = frame, x = x, width = w, height = h })
	end

	-- Light continuous foot-dust while grounded and moving, distinct from the
	-- one-shot Burst on takeoff/landing -- each puff kicks up and back, then
	-- fades, so a faint trail is always visible behind a running dino instead
	-- of only flashing at the two jump transitions.
	local function spawnDustPuff(speed: number)
		local size = 3 + math.random() * 3
		local puff = Factory.New("Frame", {
			Name = "Dust",
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromOffset(DINO_X + math.random(-2, 6), groundY() + DINO_SIZE - math.random(0, 3)),
			BackgroundColor3 = Colors.Line,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = canvas,
		})
		Factory.Corner(puff, size / 2)
		local drift = speed * 0.16 + math.random(4, 14)
		local rise = math.random(4, 10)
		TweenService
			:Create(puff, TweenInfo.new(0.32 + math.random() * 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = puff.Position - UDim2.fromOffset(drift, rise),
				Size = UDim2.fromOffset(size * 1.7, size * 1.7),
				BackgroundTransparency = 1,
			})
			:Play()
		task.delay(0.5, function()
			puff:Destroy()
		end)
	end

	-- Sky/sun/star readout for the current point in the day-night loop --
	-- purely cosmetic background texture (same category as the parallax
	-- ground ticks), so it's skipped every frame under reduceMotion and the
	-- sky simply stays at its initial daylight look.
	local function updateDayNightCycle(elapsedSeconds: number)
		local dayPhase = (math.cos(elapsedSeconds / DAY_CYCLE_SECONDS * math.pi * 2) + 1) / 2
		local nightAmount = 1 - dayPhase
		skyGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, skyDayTop:Lerp(SKY_NIGHT_TOP, nightAmount)),
			ColorSequenceKeypoint.new(1, skyDayBottom:Lerp(SKY_NIGHT_BOTTOM, nightAmount)),
		})
		sun.BackgroundColor3 = SUN_DAY_COLOR:Lerp(MOON_NIGHT_COLOR, nightAmount)
		sun.BackgroundTransparency = 0.55 - nightAmount * 0.2
		for _, star in stars do
			local twinkle = 0.15 * math.sin(elapsedSeconds * 2.4 + star.twinklePhase)
			star.instance.BackgroundTransparency = math.clamp(1 - nightAmount * 0.85 + twinkle, 0, 1)
		end
	end

	local function endGame()
		if not running then
			return
		end
		running = false
		GameShell.Shake(canvas, api.reduceMotion)
		GameShell.Burst(
			canvas,
			dino.Position + UDim2.fromOffset(DINO_SIZE / 2, DINO_SIZE / 2),
			Colors.Danger,
			api.reduceMotion
		)
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

		if not api.reduceMotion then
			updateDayNightCycle(elapsed)
		end

		local ground = groundY()
		local wasAirborne = not onGround
		velocityY += GRAVITY * dt
		dinoY += velocityY * dt
		if dinoY >= ground then
			dinoY = ground
			velocityY = 0
			onGround = true
			if wasAirborne then
				GameShell.Burst(
					canvas,
					dino.Position + UDim2.fromOffset(DINO_SIZE / 2, DINO_SIZE),
					Colors.Line,
					api.reduceMotion
				)
				if not api.reduceMotion then
					dinoScale.Scale = 0.8
					TweenService:Create(
						dinoScale,
						TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Scale = 1 }
					):Play()
				end
			end
		end
		dino.Position = UDim2.fromOffset(DINO_X, dinoY)

		local speed = currentSpeed()

		if onGround and not api.reduceMotion then
			timeSinceDust += dt
			if timeSinceDust >= DUST_INTERVAL then
				timeSinceDust = 0
				spawnDustPuff(speed)
			end
		else
			timeSinceDust = 0
		end

		timeSinceObstacle += dt
		if timeSinceObstacle >= nextObstacleGap then
			timeSinceObstacle = 0
			nextObstacleGap = math.random(MIN_OBSTACLE_GAP_CENTIS, MAX_OBSTACLE_GAP_CENTIS) / 100
			spawnObstacle()
		end

		for _, tick in groundTicks do
			tick.x -= speed * dt
			if tick.x < -20 then
				tick.x += TICK_COUNT * TICK_SPACING
			end
			tick.instance.Position = UDim2.fromOffset(tick.x, ground + DINO_SIZE)
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
		sky:Destroy()
		sun:Destroy()
		groundBand:Destroy()
		for _, tick in groundTicks do
			tick.instance:Destroy()
		end
		for _, star in stars do
			star.instance:Destroy()
		end
		for _, obstacle in obstacles do
			obstacle.frame:Destroy()
		end
		table.clear(obstacles)
	end
end

return Game
