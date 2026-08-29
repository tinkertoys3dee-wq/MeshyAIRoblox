--!strict

-- Brick Breaker: classic Breakout, with power-ups. Drag (mouse/touch) or
-- hold Left/Right (or A/D) to steer the paddle along the bottom; the ball
-- bounces on its own with no gravity, and only ever needs the paddle to
-- keep it off the floor. Score is bricks broken (doubled while Score x2 is
-- active), one point each; clearing every brick spawns a fresh wave with a
-- small speed bump rather than ending the run, the same "keeps getting
-- harder without a separate difficulty tier" trick DinoRunner/NeonSnake/
-- BlockStacker already use, just applied per-wave instead of continuously.
--
-- Every brick has a chance to drop a falling power-up when broken; catching
-- one with the paddle applies it:
--   MULTI    -- splits the ball that triggered it into three, fanned out at
--               different angles (capped at MAX_BALLS total in play)
--   WIDE     -- the paddle grows for a few seconds
--   FIRE     -- every ball currently in play stops bouncing off bricks and
--               just plows straight through them for a few seconds
--   SCOREX2  -- brick score is doubled for a few seconds
-- The run only ends once every ball currently in play has fallen past the
-- paddle, not the first one -- MULTI is a real second (and third) chance,
-- not just extra fireworks.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors
local FIRE_COLOR = Color3.fromRGB(255, 122, 61)

local PADDLE_WIDTH = 74
local PADDLE_HEIGHT = 12
local PADDLE_BOTTOM_MARGIN = 22
local PADDLE_KEY_SPEED = 560 -- px/sec while holding Left/Right or A/D
local PADDLE_FOLLOW_RATE = 24 -- how quickly the paddle catches up to a drag target
local PADDLE_STEER_INFLUENCE = 0.85 -- how much hit offset from paddle center bends the bounce
local BALL_SIZE = 14
local BALL_BASE_SPEED = 340
local BALL_SPEED_PER_WAVE = 28
local BALL_MAX_SPEED = 640
local BALL_TRAIL_INTERVAL = 0.035
local BRICK_COLUMNS = 6
local BRICK_ROWS = 4
local BRICK_HEIGHT = 20
local BRICK_GAP = 6
local BRICK_SIDE_MARGIN = 10
local BRICK_TOP_MARGIN = 54
local COMBO_WINDOW = 1.6 -- seconds between broken bricks before the streak resets

local MAX_BALLS = 6
local POWERUP_DROP_CHANCE = 0.18
local POWERUP_SIZE = 22
local POWERUP_FALL_SPEED = 150
local WIDE_BONUS = 42
local WIDE_DURATION = 10
local FIRE_DURATION = 7
local SCOREX2_DURATION = 9

type PowerupKind = "MULTI" | "WIDE" | "FIRE" | "SCOREX2"
local POWERUP_KINDS: { PowerupKind } = { "MULTI", "WIDE", "FIRE", "SCOREX2" }
local POWERUP_COLOR: { [PowerupKind]: Color3 } = {
	MULTI = Colors.Cyan,
	WIDE = Colors.Mint,
	FIRE = FIRE_COLOR,
	SCOREX2 = Colors.Gold,
}
local POWERUP_ICON: { [PowerupKind]: string } = {
	MULTI = "⚡",
	WIDE = "↔",
	FIRE = "🔥",
	SCOREX2 = "★",
}
local POWERUP_LABEL: { [PowerupKind]: string } = {
	MULTI = "MULTI-BALL",
	WIDE = "WIDE PADDLE",
	FIRE = "FIREBALL",
	SCOREX2 = "SCORE x2",
}

type Brick = { frame: Frame, x: number, y: number, width: number, height: number }
type Ball = { frame: Frame, scale: any, x: number, y: number, vx: number, vy: number, trailTimer: number }
type FallingPowerup = { frame: Frame, x: number, y: number, kind: PowerupKind }

local Game = {} :: GameShell.GameModule
Game.Name = "Brick Breaker"
Game.Key = "BrickBreaker"

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local score = 0
	local wave = 1
	local comboCount = 0
	local lastBreakTime = 0
	local fireUntil = 0
	local scoreX2Until = 0
	local wideUntil = 0
	local lastEffectsText = ""

	local function widthPx(): number
		local w = math.floor(canvas.AbsoluteSize.X)
		return if w > 40 then w else 520
	end
	local function heightPx(): number
		local h = math.floor(canvas.AbsoluteSize.Y)
		return if h > 40 then h else 320
	end

	local backdrop = Factory.New("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = canvas,
	})
	Factory.Gradient(backdrop, { Colors.PanelSoft, Colors.Panel }, 90)

	local flashOverlay = Factory.New("Frame", {
		Name = "FlashOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Cyan,
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

	local comboLabel = Factory.Label(canvas, "", UDim2.fromOffset(180, 26), {
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

	-- A one-line readout of whichever power-ups are currently live -- the
	-- paddle/ball's own look already changes (wider, orange), but a run with
	-- two or three effects stacked at once is otherwise hard to read from
	-- the play area alone.
	local statusLabel = Factory.Label(canvas, "", UDim2.fromOffset(260, 18), {
		Name = "StatusLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 32),
		Color = Colors.Text,
		Font = Theme.Fonts.Bold,
		TextSize = 11,
		AlignX = Enum.TextXAlignment.Center,
		Transparency = 1,
		ZIndex = 46,
	})

	local waveLabel = Factory.Label(canvas, "WAVE 1", UDim2.fromOffset(120, 22), {
		Name = "WaveLabel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Color = Colors.TextMuted,
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		AlignX = Enum.TextXAlignment.Right,
		ZIndex = 8,
	})

	-- A slow hue drift per wave (not per brick -- a whole wave reads as one
	-- coherent color) so a long run visibly keeps moving without needing a
	-- separate "level" indicator beyond the corner label above.
	local function brickColor(row: number): Color3
		local hue = (wave * 0.09 + row * 0.05) % 1
		return Color3.fromHSV(hue, 0.55, 0.92)
	end

	local bricks: { Brick } = {}
	local function clearBricks()
		for _, brick in bricks do
			brick.frame:Destroy()
		end
		table.clear(bricks)
	end

	local function spawnWave()
		clearBricks()
		local w = widthPx()
		local usableWidth = w - BRICK_SIDE_MARGIN * 2
		local brickWidth = (usableWidth - BRICK_GAP * (BRICK_COLUMNS - 1)) / BRICK_COLUMNS
		for row = 0, BRICK_ROWS - 1 do
			for col = 0, BRICK_COLUMNS - 1 do
				local x = BRICK_SIDE_MARGIN + col * (brickWidth + BRICK_GAP)
				local y = BRICK_TOP_MARGIN + row * (BRICK_HEIGHT + BRICK_GAP)
				local frame = Factory.New("Frame", {
					Name = "Brick",
					Size = UDim2.fromOffset(brickWidth, BRICK_HEIGHT),
					Position = UDim2.fromOffset(x, y),
					BackgroundColor3 = brickColor(row),
					BorderSizePixel = 0,
					ZIndex = 5,
					Parent = canvas,
				})
				Factory.Corner(frame, 5)
				Factory.Stroke(frame, Colors.Ink, 0.55, 1)
				table.insert(bricks, { frame = frame, x = x, y = y, width = brickWidth, height = BRICK_HEIGHT })
			end
		end
	end
	spawnWave()

	local paddle = Factory.New("Frame", {
		Name = "Paddle",
		Size = UDim2.fromOffset(PADDLE_WIDTH, PADDLE_HEIGHT),
		BackgroundColor3 = Colors.Mint,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = canvas,
	})
	Factory.Corner(paddle, PADDLE_HEIGHT / 2)
	Factory.Stroke(paddle, Colors.Ink, 0.3, 1.5)
	Factory.Gradient(paddle, { Color3.fromRGB(150, 255, 210), Colors.Mint }, 90)
	local paddleX = (widthPx() - PADDLE_WIDTH) / 2
	local paddleWidth = PADDLE_WIDTH
	local function paddleY(): number
		return heightPx() - PADDLE_BOTTOM_MARGIN - PADDLE_HEIGHT
	end
	paddle.Position = UDim2.fromOffset(paddleX, paddleY())

	local balls: { Ball } = {}
	local fallingPowerups: { FallingPowerup } = {}

	local function ballColor(): Color3
		return if os.clock() < fireUntil then FIRE_COLOR else Colors.Text
	end

	local function spawnBall(x: number, y: number, vx: number, vy: number)
		if #balls >= MAX_BALLS then
			return
		end
		local frame = Factory.New("Frame", {
			Name = "Ball",
			Size = UDim2.fromOffset(BALL_SIZE, BALL_SIZE),
			Position = UDim2.fromOffset(x, y),
			BackgroundColor3 = ballColor(),
			BorderSizePixel = 0,
			ZIndex = 7,
			Parent = canvas,
		})
		Factory.Corner(frame, BALL_SIZE / 2)
		Factory.Stroke(frame, Colors.Ink, 0.3, 1.5)
		local scale = Factory.New("UIScale", { Scale = 1, Parent = frame })
		table.insert(balls, { frame = frame, scale = scale, x = x, y = y, vx = vx, vy = vy, trailTimer = 0 })
	end

	local function currentBallSpeed(): number
		return math.min(BALL_MAX_SPEED, BALL_BASE_SPEED + (wave - 1) * BALL_SPEED_PER_WAVE)
	end

	local function launchFirstBall()
		local x = widthPx() / 2 - BALL_SIZE / 2
		local y = paddleY() - BALL_SIZE - 2
		local launchAngle = math.rad(math.random(-50, 50))
		local speed = currentBallSpeed()
		spawnBall(x, y, math.sin(launchAngle) * speed, -math.cos(launchAngle) * speed)
	end
	launchFirstBall()

	local function clearBalls()
		for _, ball in balls do
			ball.frame:Destroy()
		end
		table.clear(balls)
	end

	local function clearPowerups()
		for _, powerup in fallingPowerups do
			powerup.frame:Destroy()
		end
		table.clear(fallingPowerups)
	end

	-- Continuous paddle steering: a keyboard hold sets a direction every
	-- frame (checked live via IsKeyDown, not an edge-triggered press, since
	-- "move while held" is the whole control scheme here); a mouse/touch drag
	-- sets a target X instead, and the paddle eases toward whichever one was
	-- last active. Unlike every other game in this Arcade, there's no
	-- discrete tap/flap/drop action -- steering IS the entire input, which is
	-- the correct, expected control scheme for this genre, not a mechanic
	-- bolted on top of a simpler one.
	local dragTargetX: number? = nil
	local function clampPaddleX(x: number): number
		return math.clamp(x, 0, math.max(0, widthPx() - paddleWidth))
	end

	local inputConn = UserInputService.InputChanged:Connect(function(input: InputObject)
		if not running or not dragTargetX then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragTargetX = input.Position.X - canvas.AbsolutePosition.X - paddleWidth / 2
		end
	end)
	local dragBeganConn = canvas.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragTargetX = input.Position.X - canvas.AbsolutePosition.X - paddleWidth / 2
		end
	end)
	local dragEndedConn = UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragTargetX = nil
		end
	end)

	local function endGame()
		if not running then
			return
		end
		running = false
		GameShell.Shake(canvas, api.reduceMotion)
		GameShell.Burst(canvas, paddle.Position + UDim2.fromOffset(paddleWidth / 2, 0), Colors.Danger, api.reduceMotion)
		api.gameOver(score)
	end

	local function spawnFallingPowerup(x: number, y: number)
		local kind = POWERUP_KINDS[math.random(1, #POWERUP_KINDS)]
		local color = POWERUP_COLOR[kind]
		local frame = Factory.New("Frame", {
			Name = "Powerup",
			Size = UDim2.fromOffset(POWERUP_SIZE, POWERUP_SIZE),
			Position = UDim2.fromOffset(x - POWERUP_SIZE / 2, y - POWERUP_SIZE / 2),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = canvas,
		})
		Factory.Corner(frame, 8)
		Factory.Stroke(frame, Colors.Ink, 0.25, 1.5)
		Factory.Label(frame, POWERUP_ICON[kind], UDim2.fromScale(1, 1), {
			TextSize = 13,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 7,
		})
		if not api.reduceMotion then
			local pulse = Factory.New("UIScale", { Scale = 1, Parent = frame })
			TweenService:Create(
				pulse,
				TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.18 }
			):Play()
		end
		table.insert(
			fallingPowerups,
			{ frame = frame, x = x - POWERUP_SIZE / 2, y = y - POWERUP_SIZE / 2, kind = kind }
		)
	end

	local function applyPowerup(kind: PowerupKind, atX: number, atY: number)
		api.sounds:Play("Success")
		flashScreen(POWERUP_COLOR[kind], 0.8)
		GameShell.Ring(canvas, UDim2.fromOffset(atX, atY), POWERUP_COLOR[kind], api.reduceMotion, POWERUP_SIZE)
		if kind == "MULTI" then
			local source = balls[1]
			if source then
				local speed = math.sqrt(source.vx * source.vx + source.vy * source.vy)
				local baseAngle = math.atan2(source.vx, -source.vy)
				for _, spread in { -0.5, 0.5 } do
					local angle = baseAngle + spread
					spawnBall(source.x, source.y, math.sin(angle) * speed, -math.cos(angle) * speed)
				end
			end
		elseif kind == "WIDE" then
			wideUntil = os.clock() + WIDE_DURATION
		elseif kind == "FIRE" then
			fireUntil = os.clock() + FIRE_DURATION
		elseif kind == "SCOREX2" then
			scoreX2Until = os.clock() + SCOREX2_DURATION
		end
	end

	local heartbeatConn: RBXScriptConnection
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		dt = math.min(dt, 1 / 20)
		local w, h = widthPx(), heightPx()
		local now = os.clock()

		-- Active power-up readout, only rewritten when it actually changes.
		local parts = {}
		if now < fireUntil then
			table.insert(parts, POWERUP_ICON.FIRE .. " " .. POWERUP_LABEL.FIRE)
		end
		if now < scoreX2Until then
			table.insert(parts, POWERUP_ICON.SCOREX2 .. " " .. POWERUP_LABEL.SCOREX2)
		end
		if now < wideUntil then
			table.insert(parts, POWERUP_ICON.WIDE .. " " .. POWERUP_LABEL.WIDE)
		end
		local effectsText = table.concat(parts, "   ")
		if effectsText ~= lastEffectsText then
			statusLabel.Text = effectsText
			statusLabel.TextTransparency = if effectsText == "" then 1 else 0
			lastEffectsText = effectsText
		end

		paddleWidth = if now < wideUntil then PADDLE_WIDTH + WIDE_BONUS else PADDLE_WIDTH
		paddle.Size = UDim2.fromOffset(paddleWidth, PADDLE_HEIGHT)

		-- Paddle: keyboard hold wins whenever it's actually pressed (it's the
		-- more precise of the two for a player using both), otherwise ease
		-- toward the last drag position.
		local left = UserInputService:IsKeyDown(Enum.KeyCode.Left) or UserInputService:IsKeyDown(Enum.KeyCode.A)
		local right = UserInputService:IsKeyDown(Enum.KeyCode.Right) or UserInputService:IsKeyDown(Enum.KeyCode.D)
		if left and not right then
			paddleX = clampPaddleX(paddleX - PADDLE_KEY_SPEED * dt)
		elseif right and not left then
			paddleX = clampPaddleX(paddleX + PADDLE_KEY_SPEED * dt)
		elseif dragTargetX then
			local alpha = math.clamp(PADDLE_FOLLOW_RATE * dt, 0, 1)
			paddleX = clampPaddleX(paddleX + (clampPaddleX(dragTargetX) - paddleX) * alpha)
		else
			paddleX = clampPaddleX(paddleX)
		end
		paddle.Position = UDim2.fromOffset(paddleX, paddleY())

		local piercing = now < fireUntil
		local scoreMultiplier = if now < scoreX2Until then 2 else 1
		local tint = ballColor()
		local pTop = paddleY()

		for i = #balls, 1, -1 do
			local ball = balls[i]
			ball.frame.BackgroundColor3 = tint
			ball.x += ball.vx * dt
			ball.y += ball.vy * dt

			if ball.x <= 0 then
				ball.x = 0
				ball.vx = math.abs(ball.vx)
			elseif ball.x + BALL_SIZE >= w then
				ball.x = w - BALL_SIZE
				ball.vx = -math.abs(ball.vx)
			end
			if ball.y <= 0 then
				ball.y = 0
				ball.vy = math.abs(ball.vy)
			end

			-- Paddle bounce: only checked while the ball is moving downward
			-- into it (an upward-moving ball already past the paddle
			-- shouldn't bounce off its own far edge on the way back down
			-- through the same rows).
			if
				ball.vy > 0
				and ball.y + BALL_SIZE >= pTop
				and ball.y + BALL_SIZE <= pTop + PADDLE_HEIGHT + math.abs(ball.vy) * dt
				and ball.x + BALL_SIZE > paddleX
				and ball.x < paddleX + paddleWidth
			then
				ball.y = pTop - BALL_SIZE
				local hitOffset = ((ball.x + BALL_SIZE / 2) - (paddleX + paddleWidth / 2)) / (paddleWidth / 2)
				hitOffset = math.clamp(hitOffset, -1, 1)
				local speed = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
				local angle = hitOffset * PADDLE_STEER_INFLUENCE * (math.pi / 2.4)
				ball.vx = math.sin(angle) * speed
				ball.vy = -math.cos(angle) * speed
				api.sounds:Play("Press")
				if not api.reduceMotion then
					ball.scale.Scale = 0.7
					TweenService:Create(
						ball.scale,
						TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{ Scale = 1 }
					):Play()
				end
			end

			if ball.y > h then
				ball.frame:Destroy()
				table.remove(balls, i)
				continue
			end
			ball.frame.Position = UDim2.fromOffset(ball.x, ball.y)

			-- A brief fading trail dot behind the ball, echoing ColorSwitch's
			-- own climb trail -- purely decorative, so reduceMotion skips it
			-- outright rather than just not spawning as often.
			if not api.reduceMotion then
				ball.trailTimer += dt
				if ball.trailTimer >= BALL_TRAIL_INTERVAL then
					ball.trailTimer = 0
					local dot = Factory.New("Frame", {
						Name = "Trail",
						Size = UDim2.fromOffset(BALL_SIZE * 0.6, BALL_SIZE * 0.6),
						Position = UDim2.fromOffset(ball.x + BALL_SIZE * 0.2, ball.y + BALL_SIZE * 0.2),
						BackgroundColor3 = tint,
						BackgroundTransparency = 0.45,
						BorderSizePixel = 0,
						ZIndex = 6,
						Parent = canvas,
					})
					Factory.Corner(dot, BALL_SIZE * 0.3)
					local trailTween = TweenService:Create(
						dot,
						TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ BackgroundTransparency = 1, Size = UDim2.fromOffset(3, 3) }
					)
					trailTween.Completed:Connect(function()
						dot:Destroy()
					end)
					trailTween:Play()
				end
			end

			local ballLeft, ballRight = ball.x, ball.x + BALL_SIZE
			local ballTop, ballBottom = ball.y, ball.y + BALL_SIZE
			for j = #bricks, 1, -1 do
				local brick = bricks[j]
				if
					ballRight > brick.x
					and ballLeft < brick.x + brick.width
					and ballBottom > brick.y
					and ballTop < brick.y + brick.height
				then
					if not piercing then
						-- Reflect off whichever axis the ball was closer to
						-- entering from -- a simple center-distance
						-- heuristic, not full swept collision, but enough
						-- that a brick clipped from the side doesn't look
						-- like it bounced straight down.
						local brickCenterX = brick.x + brick.width / 2
						local brickCenterY = brick.y + brick.height / 2
						local ballCenterX = ballLeft + BALL_SIZE / 2
						local ballCenterY = ballTop + BALL_SIZE / 2
						local dx = (ballCenterX - brickCenterX) / brick.width
						local dy = (ballCenterY - brickCenterY) / brick.height
						if math.abs(dx) > math.abs(dy) then
							ball.vx = -ball.vx
						else
							ball.vy = -ball.vy
						end
					end

					local brickCenterX = brick.x + brick.width / 2
					local brickCenterY = brick.y + brick.height / 2
					local brickColorValue = brick.frame.BackgroundColor3
					brick.frame:Destroy()
					table.remove(bricks, j)
					score += scoreMultiplier
					api.setScore(score)
					api.sounds:Play("Like")
					GameShell.Burst(
						canvas,
						UDim2.fromOffset(brickCenterX, brickCenterY),
						brickColorValue,
						api.reduceMotion
					)
					if math.random() < POWERUP_DROP_CHANCE then
						spawnFallingPowerup(brickCenterX, brickCenterY)
					end

					local breakTime = os.clock()
					comboCount = if breakTime - lastBreakTime <= COMBO_WINDOW then comboCount + 1 else 1
					lastBreakTime = breakTime
					if comboCount >= 3 then
						comboLabel.Text = string.format("%dx COMBO", comboCount)
						comboLabel.TextTransparency = 0
						if not api.reduceMotion then
							local pop = Factory.New("UIScale", { Scale = 1.3, Parent = comboLabel })
							TweenService:Create(
								pop,
								TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
								{ Scale = 1 }
							):Play()
						end
						local fadeToken = comboCount
						task.delay(COMBO_WINDOW, function()
							if comboCount == fadeToken and comboLabel.Parent then
								if api.reduceMotion then
									comboLabel.TextTransparency = 1
								else
									TweenService:Create(comboLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
								end
							end
						end)
					end
					if comboCount > 0 and comboCount % 5 == 0 then
						flashScreen(Colors.Gold, 0.75)
						api.sounds:Play("Success")
					end

					if not piercing then
						break
					end
				end
			end
		end

		if #balls == 0 then
			endGame()
			return
		end

		for i = #fallingPowerups, 1, -1 do
			local powerup = fallingPowerups[i]
			powerup.y += POWERUP_FALL_SPEED * dt
			powerup.frame.Position = UDim2.fromOffset(powerup.x, powerup.y)
			if
				powerup.y + POWERUP_SIZE >= pTop
				and powerup.y <= pTop + PADDLE_HEIGHT
				and powerup.x + POWERUP_SIZE > paddleX
				and powerup.x < paddleX + paddleWidth
			then
				local kind = powerup.kind
				powerup.frame:Destroy()
				table.remove(fallingPowerups, i)
				applyPowerup(kind, powerup.x + POWERUP_SIZE / 2, pTop)
			elseif powerup.y > h then
				powerup.frame:Destroy()
				table.remove(fallingPowerups, i)
			end
		end

		if #bricks == 0 then
			wave += 1
			waveLabel.Text = string.format("WAVE %d", wave)
			flashScreen(Colors.Mint, 0.7)
			api.sounds:Play("Success")
			GameShell.Confetti(canvas, w, 0, api.reduceMotion)
			spawnWave()
			clearBalls()
			clearPowerups()
			launchFirstBall()
		end
	end)

	return function()
		running = false
		heartbeatConn:Disconnect()
		inputConn:Disconnect()
		dragBeganConn:Disconnect()
		dragEndedConn:Disconnect()
		backdrop:Destroy()
		flashOverlay:Destroy()
		comboLabel:Destroy()
		statusLabel:Destroy()
		waveLabel:Destroy()
		paddle:Destroy()
		clearBalls()
		clearPowerups()
		clearBricks()
	end
end

return Game
