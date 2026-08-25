--!strict

-- Color Switch: a vertical climber modeled on the mobile game of the same
-- name. The ball only ever moves along a single vertical line (its X is
-- fixed at canvas center) -- tapping gives it an upward bounce, gravity
-- pulls it back down the instant you stop tapping, and if you never retap it
-- falls indefinitely until it hits the bottom of the canvas (a loss, same as
-- FlappyBird's ground).
--
-- Rings scroll down from the top like FlappyBird's pipes. Each is a
-- spinning 4-color wheel; a small non-rotating badge on every ring always
-- shows which of the 4 colors currently counts as "safe" -- reading the spin
-- itself is flavor, not a requirement, since the badge is the actual signal
-- and stays legible at a glance regardless of spin speed or eyesight.
-- Passing a ring while the ball's own color matches the badge scores a
-- point; a mismatch ends the run. Colored orbs drift down the same line and
-- change the ball's current color on contact -- the only way to prepare for
-- an upcoming ring that doesn't already match.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors
local PALETTE_COLORS = { Colors.Rose, Colors.Gold, Colors.Cyan, Colors.Mint }
-- Paired index-for-index with PALETTE_COLORS so every color carries a
-- non-color signal too -- the ball's glyph and every ring's facing badge
-- both show shape, not just hue.
local PALETTE_SHAPES = { "●", "▲", "■", "★" }
local PALETTE_COUNT = #PALETTE_COLORS

local GRAVITY = 1000
local BOUNCE_VELOCITY = -380
local BALL_SIZE = 24
local RING_SIZE = 84
local RING_SPEED_BASE = 150
local RING_SPEED_PER_SCORE = 5
local RING_SPEED_MAX = 300
local RING_INTERVAL_BASE = 1.8
local RING_INTERVAL_MIN = 1.0
local RING_SPIN_MIN = 70 -- deg/sec
local RING_SPIN_MAX = 160
local ORB_SIZE = 22
local ORB_SPEED = 150
local ORB_INTERVAL_MIN = 2.4
local ORB_INTERVAL_MAX = 4.2
local TRAIL_INTERVAL = 0.045

type Ring = {
	backing: Frame,
	spinner: Frame,
	badgeFill: Frame,
	badgeGlyph: TextLabel,
	quadrantColors: { number },
	rotation: number,
	spinSpeed: number,
	y: number,
	checked: boolean,
}
type Orb = { frame: Frame, colorIndex: number, y: number, collected: boolean }

local Game = {} :: GameShell.GameModule
Game.Name = "Color Switch"
Game.Key = "ColorSwitch"

local function shuffledIndices(): { number }
	local pool = {}
	for i = 1, PALETTE_COUNT do
		pool[i] = i
	end
	for i = PALETTE_COUNT, 2, -1 do
		local j = math.random(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	return pool
end

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local score = 0
	local ballColorIndex = math.random(1, PALETTE_COUNT)
	local velocityY = 0
	local rings: { Ring } = {}
	local orbs: { Orb } = {}
	local timeSinceRing = 0
	local nextRingInterval = RING_INTERVAL_BASE
	local timeSinceOrb = 0
	local nextOrbInterval = ORB_INTERVAL_MIN + math.random() * (ORB_INTERVAL_MAX - ORB_INTERVAL_MIN)
	local trailTimer = 0

	local function width(): number
		local w = math.floor(canvas.AbsoluteSize.X)
		return if w > 40 then w else 480
	end
	local function height(): number
		local h = math.floor(canvas.AbsoluteSize.Y)
		return if h > 40 then h else 320
	end
	local function centerX(): number
		return width() / 2
	end

	local sky = Factory.New("Frame", {
		Name = "Sky",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = canvas,
	})
	Factory.Gradient(sky, { Colors.PanelSoft, Colors.Panel }, 90)
	-- A faint centerline -- the ball never leaves it, so it doubles as a
	-- flight-path guide the same way a runway centerline would.
	Factory.New("Frame", {
		Name = "Centerline",
		Size = UDim2.new(0, 2, 1, 0),
		Position = UDim2.fromOffset(centerX() - 1, 0),
		BackgroundColor3 = Colors.Line,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = canvas,
	})

	local ball = Factory.New("Frame", {
		Name = "Ball",
		Size = UDim2.fromOffset(BALL_SIZE, BALL_SIZE),
		BackgroundColor3 = PALETTE_COLORS[ballColorIndex],
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = canvas,
	})
	Factory.Corner(ball, BALL_SIZE / 2)
	Factory.Stroke(ball, Colors.Ink, 0.2, 2)
	local ballScale = Factory.New("UIScale", { Scale = 1, Parent = ball })
	local ballGlyph = Factory.Label(ball, PALETTE_SHAPES[ballColorIndex], UDim2.fromScale(1, 1), {
		Color = Colors.Ink,
		TextSize = 13,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
		ZIndex = 7,
	})
	local ballY = height() * 0.5
	ball.Position = UDim2.fromOffset(centerX() - BALL_SIZE / 2, ballY)

	local function setBallColor(colorIndex: number)
		ballColorIndex = colorIndex
		ball.BackgroundColor3 = PALETTE_COLORS[colorIndex]
		ballGlyph.Text = PALETTE_SHAPES[colorIndex]
		if not api.reduceMotion then
			ballScale.Scale = 1.35
			TweenService
				:Create(ballScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end
	end

	local function bounce()
		if not running then
			return
		end
		velocityY = BOUNCE_VELOCITY
		api.sounds:Play("Press")
		if not api.reduceMotion then
			ballScale.Scale = 0.75
			TweenService
				:Create(ballScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
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
			bounce()
		end
	end)
	local tapConn = canvas.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			bounce()
		end
	end)

	local function spawnRing()
		local backing = Factory.New("Frame", {
			Name = "Ring",
			Size = UDim2.fromOffset(RING_SIZE, RING_SIZE),
			Position = UDim2.fromOffset(centerX() - RING_SIZE / 2, -RING_SIZE),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = canvas,
		})
		Factory.Corner(backing, RING_SIZE / 2)
		Factory.Stroke(backing, Colors.Line, 0.5, 1.5)

		local spinner = Factory.New("Frame", {
			Name = "Spinner",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = backing,
		})
		local quadrantColors = shuffledIndices()
		local petalSize = (RING_SIZE - 12) / 2
		local petalOffsets = {
			{ 3, 3 },
			{ RING_SIZE / 2 + 1, 3 },
			{ 3, RING_SIZE / 2 + 1 },
			{ RING_SIZE / 2 + 1, RING_SIZE / 2 + 1 },
		}
		for i, offset in petalOffsets do
			local petal = Factory.New("Frame", {
				Name = "Petal",
				Size = UDim2.fromOffset(petalSize, petalSize),
				Position = UDim2.fromOffset(offset[1], offset[2]),
				BackgroundColor3 = PALETTE_COLORS[quadrantColors[i]],
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = spinner,
			})
			Factory.Corner(petal, 8)
		end

		local rotation = math.random(0, 359)
		spinner.Rotation = rotation
		local spinSpeed = (RING_SPIN_MIN + math.random() * (RING_SPIN_MAX - RING_SPIN_MIN))
			* (if math.random() < 0.5 then -1 else 1)

		local badgeFill = Factory.New("Frame", {
			Name = "Badge",
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.fromOffset(RING_SIZE - 12, -8),
			BackgroundColor3 = Colors.Ink,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = backing,
		})
		Factory.Corner(badgeFill, 14)
		Factory.Stroke(badgeFill, Colors.Ink, 0.3, 2)
		local badgeGlyph = Factory.Label(badgeFill, "", UDim2.fromScale(1, 1), {
			Color = Colors.Ink,
			Font = Theme.Fonts.Bold,
			TextSize = 13,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 5,
		})

		table.insert(rings, {
			backing = backing,
			spinner = spinner,
			badgeFill = badgeFill,
			badgeGlyph = badgeGlyph,
			quadrantColors = quadrantColors,
			rotation = rotation,
			spinSpeed = spinSpeed,
			y = -RING_SIZE,
			checked = false,
		})
	end

	local function spawnOrb()
		local colorIndex = math.random(1, PALETTE_COUNT)
		while colorIndex == ballColorIndex do
			colorIndex = math.random(1, PALETTE_COUNT)
		end
		local frame = Factory.New("Frame", {
			Name = "Orb",
			Size = UDim2.fromOffset(ORB_SIZE, ORB_SIZE),
			Position = UDim2.fromOffset(centerX() - ORB_SIZE / 2, -ORB_SIZE),
			BackgroundColor3 = PALETTE_COLORS[colorIndex],
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = canvas,
		})
		Factory.Corner(frame, ORB_SIZE / 2)
		Factory.Stroke(frame, Colors.Ink, 0.2, 2)
		Factory.Label(frame, PALETTE_SHAPES[colorIndex], UDim2.fromScale(1, 1), {
			Color = Colors.Ink,
			TextSize = 11,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 5,
		})
		table.insert(orbs, { frame = frame, colorIndex = colorIndex, y = -ORB_SIZE, collected = false })
	end

	-- A ring within this many pixels of the top already claimed the spawn
	-- slot this tick -- skipped so an orb never spawns stacked on top of a
	-- ring the instant both timers land together.
	local function orbSlotFree(): boolean
		for _, ring in rings do
			if math.abs(ring.y + RING_SIZE) < RING_SIZE + 40 then
				return false
			end
		end
		return true
	end

	local function endGame()
		if not running then
			return
		end
		running = false
		GameShell.Shake(canvas, api.reduceMotion)
		GameShell.Burst(
			canvas,
			ball.Position + UDim2.fromOffset(BALL_SIZE / 2, BALL_SIZE / 2),
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
		ballY += velocityY * dt
		if ballY < 0 then
			ballY = 0
			velocityY = 0
		end
		if ballY > height() - BALL_SIZE then
			ball.Position = UDim2.fromOffset(centerX() - BALL_SIZE / 2, height() - BALL_SIZE)
			endGame()
			return
		end
		ball.Position = UDim2.fromOffset(centerX() - BALL_SIZE / 2, ballY)

		if not api.reduceMotion then
			trailTimer += dt
			if trailTimer >= TRAIL_INTERVAL then
				trailTimer = 0
				local dot = Factory.New("Frame", {
					Name = "Trail",
					Size = UDim2.fromOffset(BALL_SIZE * 0.6, BALL_SIZE * 0.6),
					Position = ball.Position + UDim2.fromOffset(BALL_SIZE * 0.2, BALL_SIZE * 0.2),
					BackgroundColor3 = PALETTE_COLORS[ballColorIndex],
					BackgroundTransparency = 0.5,
					BorderSizePixel = 0,
					ZIndex = 4,
					Parent = canvas,
				})
				Factory.Corner(dot, BALL_SIZE * 0.3)
				local tween = TweenService:Create(
					dot,
					TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ BackgroundTransparency = 1, Size = UDim2.fromOffset(4, 4) }
				)
				tween.Completed:Connect(function()
					dot:Destroy()
				end)
				tween:Play()
			end
		end

		local speed = math.min(RING_SPEED_MAX, RING_SPEED_BASE + score * RING_SPEED_PER_SCORE)
		timeSinceRing += dt
		if timeSinceRing >= nextRingInterval then
			timeSinceRing = 0
			nextRingInterval = math.max(RING_INTERVAL_MIN, RING_INTERVAL_BASE - score * 0.03)
			spawnRing()
		end
		timeSinceOrb += dt
		if timeSinceOrb >= nextOrbInterval then
			timeSinceOrb = 0
			nextOrbInterval = ORB_INTERVAL_MIN + math.random() * (ORB_INTERVAL_MAX - ORB_INTERVAL_MIN)
			if orbSlotFree() then
				spawnOrb()
			end
		end

		local ballTop, ballBottom = ballY, ballY + BALL_SIZE

		for i = #rings, 1, -1 do
			local ring = rings[i]
			ring.y += speed * dt
			ring.rotation = (ring.rotation + ring.spinSpeed * dt) % 360
			ring.backing.Position = UDim2.fromOffset(centerX() - RING_SIZE / 2, ring.y)
			ring.spinner.Rotation = ring.rotation

			local facingQuadrant = math.floor(ring.rotation / 90) + 1
			local facingColorIndex = ring.quadrantColors[facingQuadrant]
			ring.badgeFill.BackgroundColor3 = PALETTE_COLORS[facingColorIndex]
			ring.badgeGlyph.Text = PALETTE_SHAPES[facingColorIndex]

			if not ring.checked and ring.y + RING_SIZE >= ballTop and ring.y <= ballBottom then
				ring.checked = true
				if facingColorIndex ~= ballColorIndex then
					endGame()
					return
				end
				score += 1
				api.setScore(score)
				api.sounds:Play("Like")
				GameShell.Burst(
					canvas,
					ball.Position + UDim2.fromOffset(BALL_SIZE / 2, BALL_SIZE / 2),
					PALETTE_COLORS[ballColorIndex],
					api.reduceMotion
				)
			end

			if ring.y > height() then
				ring.backing:Destroy()
				table.remove(rings, i)
			end
		end

		for i = #orbs, 1, -1 do
			local orb = orbs[i]
			orb.y += ORB_SPEED * dt
			orb.frame.Position = UDim2.fromOffset(centerX() - ORB_SIZE / 2, orb.y)

			if not orb.collected and orb.y + ORB_SIZE >= ballTop and orb.y <= ballBottom then
				orb.collected = true
				local orbPosition = orb.frame.Position
				local orbColorIndex = orb.colorIndex
				setBallColor(orbColorIndex)
				api.sounds:Play("Hover")
				GameShell.Burst(
					canvas,
					orbPosition + UDim2.fromOffset(ORB_SIZE / 2, ORB_SIZE / 2),
					PALETTE_COLORS[orbColorIndex],
					api.reduceMotion
				)
				orb.frame:Destroy()
				table.remove(orbs, i)
				continue
			end

			if orb.y > height() then
				orb.frame:Destroy()
				table.remove(orbs, i)
			end
		end
	end)

	return function()
		running = false
		heartbeatConn:Disconnect()
		inputConn:Disconnect()
		tapConn:Disconnect()
		ball:Destroy()
		sky:Destroy()
		for _, ring in rings do
			ring.backing:Destroy()
		end
		table.clear(rings)
		for _, orb in orbs do
			orb.frame:Destroy()
		end
		table.clear(orbs)
	end
end

return Game
