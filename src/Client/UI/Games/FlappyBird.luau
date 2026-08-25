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
		local bottom = Factory.New("Frame", {
			Name = "PipeBottom",
			Size = UDim2.fromOffset(PIPE_WIDTH, math.max(0, h - bottomY)),
			Position = UDim2.fromOffset(x, bottomY),
			BackgroundColor3 = Colors.Mint,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = canvas,
		})
		table.insert(pipes, { top = top, bottom = bottom, x = x, gapY = gapY, scored = false })
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
			end
		end
	end)

	return function()
		running = false
		heartbeatConn:Disconnect()
		inputConn:Disconnect()
		tapConn:Disconnect()
		bird:Destroy()
		for _, pipe in pipes do
			pipe.top:Destroy()
			pipe.bottom:Destroy()
		end
		table.clear(pipes)
	end
end

return Game
