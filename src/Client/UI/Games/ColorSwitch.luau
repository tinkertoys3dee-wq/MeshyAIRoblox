--!strict

-- Color Switch: the ball's color cycles automatically through 4 palette
-- colors. Gates scroll down from the top, each split into 4 lane-segments
-- coloured as a shuffled permutation of the same 4 colors -- so exactly one
-- lane is ever safe on any given gate. Move the ball into whichever lane
-- matches its CURRENT color before the gate reaches it; keyboard (A/D or
-- arrows) and tap-left/tap-right both move one lane at a time.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors
local LANE_COLORS = { Colors.Rose, Colors.Gold, Colors.Cyan, Colors.Mint }
local LANE_COUNT = #LANE_COLORS

local BALL_SIZE = 22
local BALL_Y_FRACTION = 0.82 -- how far down the canvas the ball sits
local BALL_LERP_SPEED = 10 -- lanes/second, i.e. how snappy the slide feels
local GATE_HEIGHT = 16
local GATE_SPEED_BASE = 130
local GATE_SPEED_PER_SCORE = 6
local GATE_SPEED_MAX = 340
local GATE_INTERVAL_BASE = 1.7
local GATE_INTERVAL_MIN = 0.95
local COLOR_CYCLE_SECONDS = 1.7

type Gate = { frame: Frame, segments: { Frame }, laneColors: { Color3 }, y: number, checked: boolean }

local Game = {} :: GameShell.GameModule
Game.Name = "Color Switch"
Game.Key = "ColorSwitch"

local function shuffledColors(): { Color3 }
	local pool = table.clone(LANE_COLORS)
	for i = LANE_COUNT, 2, -1 do
		local j = math.random(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	return pool
end

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local score = 0
	local laneIndex = math.floor(LANE_COUNT / 2)
	local ballColorIndex = 1
	local colorTimer = 0
	local gates: { Gate } = {}
	local timeSinceGate = 0
	local nextGateInterval = GATE_INTERVAL_BASE

	local function width(): number
		local w = math.floor(canvas.AbsoluteSize.X)
		return if w > 40 then w else 480
	end
	local function height(): number
		local h = math.floor(canvas.AbsoluteSize.Y)
		return if h > 40 then h else 320
	end
	local function laneWidth(): number
		return width() / LANE_COUNT
	end
	local function laneCenterX(lane: number): number
		return laneWidth() * (lane - 0.5)
	end
	local function ballY(): number
		return height() * BALL_Y_FRACTION
	end

	local trackLines = {}
	for lane = 1, LANE_COUNT - 1 do
		local line = Factory.New("Frame", {
			Name = "Lane",
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = Colors.Line,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = canvas,
		})
		table.insert(trackLines, line)
	end

	local ball = Factory.New("Frame", {
		Name = "Ball",
		Size = UDim2.fromOffset(BALL_SIZE, BALL_SIZE),
		BackgroundColor3 = LANE_COLORS[ballColorIndex],
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = canvas,
	})
	Factory.Corner(ball, BALL_SIZE / 2)
	Factory.Stroke(ball, Colors.Ink, 0.2, 2)
	local ballX = laneCenterX(laneIndex) - BALL_SIZE / 2
	ball.Position = UDim2.fromOffset(ballX, ballY() - BALL_SIZE / 2)

	local function moveLane(delta: number)
		if not running then
			return
		end
		laneIndex = math.clamp(laneIndex + delta, 1, LANE_COUNT)
		api.sounds:Play("Hover")
	end

	local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not running then
			return
		end
		if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
			moveLane(-1)
		elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
			moveLane(1)
		end
	end)
	-- Tap-left/tap-right halves of the canvas for touch and mouse, since
	-- there is no arrow key on a phone.
	local tapConn = canvas.InputBegan:Connect(function(input)
		if not running then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local position = input.Position
		local canvasX = canvas.AbsolutePosition.X
		local relativeX = position.X - canvasX
		if relativeX < width() / 2 then
			moveLane(-1)
		else
			moveLane(1)
		end
	end)

	local function spawnGate()
		local laneColors = shuffledColors()
		local gateFrame = Factory.New("Frame", {
			Name = "Gate",
			Size = UDim2.fromOffset(width(), GATE_HEIGHT),
			Position = UDim2.fromOffset(0, -GATE_HEIGHT),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = canvas,
		})
		local segments = {}
		local lw = laneWidth()
		for lane = 1, LANE_COUNT do
			local segment = Factory.New("Frame", {
				Name = "Segment",
				Size = UDim2.fromOffset(lw - 3, GATE_HEIGHT),
				Position = UDim2.fromOffset((lane - 1) * lw, 0),
				BackgroundColor3 = laneColors[lane],
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = gateFrame,
			})
			Factory.Corner(segment, 3)
			table.insert(segments, segment)
		end
		table.insert(
			gates,
			{ frame = gateFrame, segments = segments, laneColors = laneColors, y = -GATE_HEIGHT, checked = false }
		)
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

		colorTimer += dt
		if colorTimer >= COLOR_CYCLE_SECONDS then
			colorTimer -= COLOR_CYCLE_SECONDS
			ballColorIndex = (ballColorIndex % LANE_COUNT) + 1
			ball.BackgroundColor3 = LANE_COLORS[ballColorIndex]
		end

		local targetX = laneCenterX(laneIndex) - BALL_SIZE / 2
		ballX += (targetX - ballX) * math.min(1, BALL_LERP_SPEED * dt)
		ball.Position = UDim2.fromOffset(ballX, ballY() - BALL_SIZE / 2)

		local lw = laneWidth()
		for lane, line in trackLines do
			line.Position = UDim2.fromOffset(lw * lane, 0)
		end

		local speed = math.min(GATE_SPEED_MAX, GATE_SPEED_BASE + score * GATE_SPEED_PER_SCORE)
		timeSinceGate += dt
		if timeSinceGate >= nextGateInterval then
			timeSinceGate = 0
			nextGateInterval = math.max(GATE_INTERVAL_MIN, GATE_INTERVAL_BASE - score * 0.03)
			spawnGate()
		end

		local by = ballY()
		for i = #gates, 1, -1 do
			local gate = gates[i]
			gate.y += speed * dt
			gate.frame.Position = UDim2.fromOffset(0, gate.y)

			if not gate.checked and gate.y + GATE_HEIGHT >= by - BALL_SIZE / 2 then
				gate.checked = true
				local safeColor = gate.laneColors[laneIndex]
				if safeColor ~= LANE_COLORS[ballColorIndex] then
					endGame()
					return
				end
				score += 1
				api.setScore(score)
				api.sounds:Play("Like")
			end

			if gate.y > height() then
				gate.frame:Destroy()
				table.remove(gates, i)
			end
		end
	end)

	return function()
		running = false
		heartbeatConn:Disconnect()
		inputConn:Disconnect()
		tapConn:Disconnect()
		ball:Destroy()
		for _, line in trackLines do
			line:Destroy()
		end
		for _, gate in gates do
			gate.frame:Destroy()
		end
		table.clear(gates)
	end
end

return Game
