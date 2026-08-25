--!strict

-- Flappy Bird: tap/click/space to flap upward against constant gravity,
-- thread the gap between a scrolling pair of pipes. Pipe position data lives
-- in a plain Lua table (`pipes`), not re-read back from each Frame's
-- Position/AbsoluteSize every tick -- reading GUI layout back out the same
-- frame it was written is one round trip more than this needs, and ties
-- collision math to whatever the engine's layout pass has settled on rather
-- than to numbers this module already knows are correct.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors

local GRAVITY = 900
local FLAP_VELOCITY = -320
local PIPE_SPEED = 190
local PIPE_GAP = 165
local PIPE_WIDTH = 58
local PIPE_INTERVAL = 1.5
local BIRD_SIZE = 26
local BIRD_X = 74
local CLOUD_COUNT = 5
local CLOUD_PARALLAX_SPEED = 26 -- px/sec, well under PIPE_SPEED for depth
local PIPE_LIGHT_COLOR = Color3.fromRGB(140, 255, 205)
local PIPE_DARK_COLOR = Color3.fromRGB(48, 196, 143)

type Pipe = { top: Frame, bottom: Frame, x: number, gapY: number, scored: boolean }

local Game = {} :: GameShell.GameModule
Game.Name = "Flappy Bird"
Game.Key = "FlappyBird"

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local birdY = 140
	local velocityY = 0
	local score = 0
	local pipes: { Pipe } = {}
	local timeSincePipe = PIPE_INTERVAL -- spawn the first pipe immediately

	-- A soft sky gradient plus a handful of slow-drifting "clouds" well
	-- behind the pipes (ZIndex 1-2, pipes are 3) -- pure background texture,
	-- parallax-scrolled at a fraction of PIPE_SPEED for depth. Frozen in
	-- place (no per-frame scroll) under reduceMotion; they still render, just
	-- as a static backdrop rather than an animated one.
	local sky = Factory.New("Frame", {
		Name = "Sky",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = canvas,
	})
	Factory.Gradient(sky, { Colors.PanelSoft, Colors.Panel }, 90)
	local clouds: { { instance: Frame, x: number, y: number } } = {}
	for i = 1, CLOUD_COUNT do
		local cloudSize = 30 + math.random() * 40
		local instance = Factory.New("Frame", {
			Name = "Cloud",
			Size = UDim2.fromOffset(cloudSize, cloudSize * 0.5),
			BackgroundColor3 = Colors.Text,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = canvas,
		})
		Factory.Corner(instance, cloudSize)
		local x = math.random(0, 520)
		local y = 20 + math.random() * 180
		instance.Position = UDim2.fromOffset(x, y)
		table.insert(clouds, { instance = instance, x = x, y = y })
	end

	local bird = Factory.New("Frame", {
		Name = "Bird",
		Size = UDim2.fromOffset(BIRD_SIZE, BIRD_SIZE),
		Position = UDim2.fromOffset(BIRD_X, birdY),
		BackgroundColor3 = Colors.Gold,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = canvas,
	})
	Factory.Corner(bird, BIRD_SIZE / 2)
	Factory.Stroke(bird, Colors.Ink, 0.3, 1.5)
	-- Flap squash/stretch handle: purely cosmetic scale pulse, so it's the
	-- part of "flap" that reduceMotion turns off -- the bird's actual
	-- position/velocity (the gameplay-relevant motion) is untouched either
	-- way. Children below (wing/eye/beak) inherit the bird's own Rotation
	-- and this UIScale automatically -- Roblox rotates/scales a GuiObject's
	-- whole visual subtree as a unit, not just itself.
	local birdScale = Factory.New("UIScale", { Scale = 1, Parent = bird })
	local wing = Factory.New("Frame", {
		Name = "Wing",
		Size = UDim2.fromOffset(BIRD_SIZE * 0.5, BIRD_SIZE * 0.32),
		Position = UDim2.fromOffset(BIRD_SIZE * 0.1, BIRD_SIZE * 0.4),
		BackgroundColor3 = Color3.fromRGB(214, 158, 40),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = bird,
	})
	Factory.Corner(wing, 6)
	local eye = Factory.New("Frame", {
		Name = "Eye",
		Size = UDim2.fromOffset(BIRD_SIZE * 0.32, BIRD_SIZE * 0.32),
		Position = UDim2.fromOffset(BIRD_SIZE * 0.52, BIRD_SIZE * 0.06),
		BackgroundColor3 = Colors.Text,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = bird,
	})
	Factory.Corner(eye, BIRD_SIZE * 0.16)
	Factory.New("Frame", {
		Name = "Pupil",
		Size = UDim2.fromOffset(BIRD_SIZE * 0.14, BIRD_SIZE * 0.14),
		Position = UDim2.fromOffset(BIRD_SIZE * 0.7, BIRD_SIZE * 0.14),
		BackgroundColor3 = Colors.Ink,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = bird,
	})
	local beak = Factory.New("Frame", {
		Name = "Beak",
		Size = UDim2.fromOffset(BIRD_SIZE * 0.34, BIRD_SIZE * 0.2),
		Position = UDim2.fromOffset(BIRD_SIZE * 0.86, BIRD_SIZE * 0.36),
		BackgroundColor3 = Color3.fromRGB(255, 138, 61),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = bird,
	})
	Factory.Corner(beak, 3)

	-- Floored: AbsoluteSize can be fractional (UI scaling), and math.random
	-- errors on a non-integer argument -- every caller below feeds these
	-- straight into math.random bounds.
	local function height(): number
		local h = math.floor(canvas.AbsoluteSize.Y)
		return if h > 40 then h else 320
	end
	local function width(): number
		local w = math.floor(canvas.AbsoluteSize.X)
		return if w > 40 then w else 520
	end

	local function flap()
		if not running then
			return
		end
		velocityY = FLAP_VELOCITY
		api.sounds:Play("Press")
		if not api.reduceMotion then
			birdScale.Scale = 0.7
			TweenService
				:Create(birdScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
			wing.Rotation = -35
			TweenService
				:Create(wing, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 0 })
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
		then
			flap()
		end
	end)
	-- The canvas itself is also tappable, since a touch player's finger is
	-- rarely still holding a keyboard.
	local tapConn = canvas.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			flap()
		end
	end)

	local function spawnPipe()
		local h = height()
		local gapY = math.random(70, math.max(71, h - 70))
		local x = width() + PIPE_WIDTH
		local bottomY = gapY + PIPE_GAP / 2

		local top = Factory.New("Frame", {
			Name = "PipeTop",
			Size = UDim2.fromOffset(PIPE_WIDTH, math.max(0, gapY - PIPE_GAP / 2)),
			Position = UDim2.fromOffset(x, 0),
			BackgroundColor3 = Colors.Mint,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = canvas,
		})
		Factory.Gradient(top, { PIPE_LIGHT_COLOR, PIPE_DARK_COLOR }, 0)
		-- Caps are children of their pipe, not tracked separately -- they
		-- inherit its Position every frame for free and get destroyed
		-- automatically along with it, the same trick the bird's wing/eye/
		-- beak use off its own Frame.
		local topCap = Factory.New("Frame", {
			Name = "Cap",
			Size = UDim2.new(1, 12, 0, 16),
			Position = UDim2.new(0, -6, 1, -16),
			BackgroundColor3 = PIPE_DARK_COLOR,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = top,
		})
		Factory.Corner(topCap, 4)
		Factory.Stroke(topCap, Colors.Ink, 0.6, 1)
		local bottom = Factory.New("Frame", {
			Name = "PipeBottom",
			Size = UDim2.fromOffset(PIPE_WIDTH, math.max(0, h - bottomY)),
			Position = UDim2.fromOffset(x, bottomY),
			BackgroundColor3 = Colors.Mint,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = canvas,
		})
		Factory.Gradient(bottom, { PIPE_LIGHT_COLOR, PIPE_DARK_COLOR }, 0)
		local bottomCap = Factory.New("Frame", {
			Name = "Cap",
			Size = UDim2.new(1, 12, 0, 16),
			Position = UDim2.new(0, -6, 0, 0),
			BackgroundColor3 = PIPE_DARK_COLOR,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = bottom,
		})
		Factory.Corner(bottomCap, 4)
		Factory.Stroke(bottomCap, Colors.Ink, 0.6, 1)
		table.insert(pipes, { top = top, bottom = bottom, x = x, gapY = gapY, scored = false })
	end

	local function endGame()
		if not running then
			return
		end
		running = false
		GameShell.Shake(canvas, api.reduceMotion)
		GameShell.Burst(
			canvas,
			bird.Position + UDim2.fromOffset(BIRD_SIZE / 2, BIRD_SIZE / 2),
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

		velocityY += GRAVITY * dt
		birdY += velocityY * dt
		if birdY < 0 then
			birdY = 0
			velocityY = 0
		end
		if birdY > height() - BIRD_SIZE then
			bird.Position = UDim2.fromOffset(BIRD_X, height() - BIRD_SIZE)
			endGame()
			return
		end
		bird.Position = UDim2.fromOffset(BIRD_X, birdY)
		-- Tilt is a direct readout of the bird's own existing vertical
		-- velocity, not an independent animation, so it stays on even under
		-- reduceMotion the same way the bird's position itself does.
		bird.Rotation = math.clamp(velocityY * 0.08, -30, 75)

		if not api.reduceMotion then
			for _, cloud in clouds do
				cloud.x -= CLOUD_PARALLAX_SPEED * dt
				if cloud.x < -60 then
					cloud.x = width() + 20
				end
				cloud.instance.Position = UDim2.fromOffset(cloud.x, cloud.y)
			end
		end

		timeSincePipe += dt
		if timeSincePipe >= PIPE_INTERVAL then
			timeSincePipe = 0
			spawnPipe()
		end

		local birdTop, birdBottom = birdY, birdY + BIRD_SIZE
		local birdLeft, birdRight = BIRD_X, BIRD_X + BIRD_SIZE

		for i = #pipes, 1, -1 do
			local pipe = pipes[i]
			pipe.x -= PIPE_SPEED * dt
			pipe.top.Position = UDim2.fromOffset(pipe.x, 0)
			pipe.bottom.Position = UDim2.fromOffset(pipe.x, pipe.gapY + PIPE_GAP / 2)

			if pipe.x + PIPE_WIDTH < 0 then
				pipe.top:Destroy()
				pipe.bottom:Destroy()
				table.remove(pipes, i)
				continue
			end

			local pipeLeft, pipeRight = pipe.x, pipe.x + PIPE_WIDTH
			if birdRight > pipeLeft and birdLeft < pipeRight then
				local gapTop = pipe.gapY - PIPE_GAP / 2
				local gapBottom = pipe.gapY + PIPE_GAP / 2
				if birdTop < gapTop or birdBottom > gapBottom then
					endGame()
					return
				end
			elseif not pipe.scored and pipeRight < birdLeft then
				pipe.scored = true
				score += 1
				api.setScore(score)
				api.sounds:Play("Like")
				GameShell.Burst(
					canvas,
					bird.Position + UDim2.fromOffset(BIRD_SIZE / 2, BIRD_SIZE / 2),
					Colors.Mint,
					api.reduceMotion
				)
			end
		end
	end)

	return function()
		running = false
		heartbeatConn:Disconnect()
		inputConn:Disconnect()
		tapConn:Disconnect()
		bird:Destroy()
		sky:Destroy()
		for _, cloud in clouds do
			cloud.instance:Destroy()
		end
		for _, pipe in pipes do
			pipe.top:Destroy()
			pipe.bottom:Destroy()
		end
		table.clear(pipes)
	end
end

return Game
