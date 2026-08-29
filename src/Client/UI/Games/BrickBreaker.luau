--!strict

-- Brick Breaker: classic Breakout. Drag (mouse/touch) or hold Left/Right
-- (or A/D) to steer the paddle along the bottom; the ball bounces on its
-- own with no gravity, and only ever needs the paddle to keep it off the
-- floor. Score is bricks broken, one point each; clearing every brick spawns
-- a fresh wave with a small speed bump rather than ending the run, the same
-- "keeps getting harder without a separate difficulty tier" trick
-- DinoRunner/NeonSnake/BlockStacker already use, just applied per-wave
-- instead of continuously.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors

local PADDLE_WIDTH = 74
local PADDLE_HEIGHT = 12
local PADDLE_BOTTOM_MARGIN = 22
local PADDLE_KEY_SPEED = 480 -- px/sec while holding Left/Right or A/D
local PADDLE_FOLLOW_RATE = 18 -- how quickly the paddle catches up to a drag target
local BALL_SIZE = 14
local BALL_BASE_SPEED = 250
local BALL_SPEED_PER_WAVE = 22
local BALL_MAX_SPEED = 470
local PADDLE_STEER_INFLUENCE = 0.85 -- how much hit offset from paddle center bends the bounce
local BRICK_COLUMNS = 6
local BRICK_ROWS = 4
local BRICK_HEIGHT = 20
local BRICK_GAP = 6
local BRICK_SIDE_MARGIN = 10
local BRICK_TOP_MARGIN = 54
local COMBO_WINDOW = 1.6 -- seconds between broken bricks before the streak resets

type Brick = { frame: Frame, x: number, y: number, width: number, height: number }

local Game = {} :: GameShell.GameModule
Game.Name = "Brick Breaker"
Game.Key = "BrickBreaker"

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local score = 0
	local wave = 1
	local comboCount = 0
	local lastBreakTime = 0

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
	local function paddleY(): number
		return heightPx() - PADDLE_BOTTOM_MARGIN - PADDLE_HEIGHT
	end
	paddle.Position = UDim2.fromOffset(paddleX, paddleY())

	local ball = Factory.New("Frame", {
		Name = "Ball",
		Size = UDim2.fromOffset(BALL_SIZE, BALL_SIZE),
		BackgroundColor3 = Colors.Text,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = canvas,
	})
	Factory.Corner(ball, BALL_SIZE / 2)
	Factory.Stroke(ball, Colors.Ink, 0.3, 1.5)
	local ballScale = Factory.New("UIScale", { Scale = 1, Parent = ball })

	local function resetBall(): (number, number, number, number)
		local x = widthPx() / 2 - BALL_SIZE / 2
		local y = paddleY() - BALL_SIZE - 2
		local launchAngle = math.rad(math.random(-50, 50))
		local speed = math.min(BALL_MAX_SPEED, BALL_BASE_SPEED + (wave - 1) * BALL_SPEED_PER_WAVE)
		local vx = math.sin(launchAngle) * speed
		local vy = -math.cos(launchAngle) * speed
		return x, y, vx, vy
	end
	local ballX, ballY, ballVX, ballVY = resetBall()
	ball.Position = UDim2.fromOffset(ballX, ballY)

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
		return math.clamp(x, 0, math.max(0, widthPx() - PADDLE_WIDTH))
	end

	local inputConn = UserInputService.InputChanged:Connect(function(input: InputObject)
		if not running or not dragTargetX then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragTargetX = input.Position.X - canvas.AbsolutePosition.X - PADDLE_WIDTH / 2
		end
	end)
	local dragBeganConn = canvas.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragTargetX = input.Position.X - canvas.AbsolutePosition.X - PADDLE_WIDTH / 2
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
		end
		paddle.Position = UDim2.fromOffset(paddleX, paddleY())

		ballX += ballVX * dt
		ballY += ballVY * dt

		local w, h = widthPx(), heightPx()
		if ballX <= 0 then
			ballX = 0
			ballVX = math.abs(ballVX)
		elseif ballX + BALL_SIZE >= w then
			ballX = w - BALL_SIZE
			ballVX = -math.abs(ballVX)
		end
		if ballY <= 0 then
			ballY = 0
			ballVY = math.abs(ballVY)
		end

		-- Paddle bounce: only checked while the ball is moving downward into
		-- it (an upward-moving ball already past the paddle shouldn't bounce
		-- off its own far edge on the way back down through the same rows).
		local pTop = paddleY()
		if
			ballVY > 0
			and ballY + BALL_SIZE >= pTop
			and ballY + BALL_SIZE <= pTop + PADDLE_HEIGHT + math.abs(ballVY) * dt
			and ballX + BALL_SIZE > paddleX
			and ballX < paddleX + PADDLE_WIDTH
		then
			ballY = pTop - BALL_SIZE
			local hitOffset = ((ballX + BALL_SIZE / 2) - (paddleX + PADDLE_WIDTH / 2)) / (PADDLE_WIDTH / 2)
			hitOffset = math.clamp(hitOffset, -1, 1)
			local speed = math.sqrt(ballVX * ballVX + ballVY * ballVY)
			local angle = hitOffset * PADDLE_STEER_INFLUENCE * (math.pi / 2.4)
			ballVX = math.sin(angle) * speed
			ballVY = -math.cos(angle) * speed
			api.sounds:Play("Press")
			if not api.reduceMotion then
				ballScale.Scale = 0.7
				TweenService
					:Create(
						ballScale,
						TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{ Scale = 1 }
					)
					:Play()
			end
		end

		if ballY > h then
			ball.Position = UDim2.fromOffset(ballX, h)
			endGame()
			return
		end
		ball.Position = UDim2.fromOffset(ballX, ballY)

		local ballLeft, ballRight = ballX, ballX + BALL_SIZE
		local ballTop, ballBottom = ballY, ballY + BALL_SIZE
		for i = #bricks, 1, -1 do
			local brick = bricks[i]
			if
				ballRight > brick.x
				and ballLeft < brick.x + brick.width
				and ballBottom > brick.y
				and ballTop < brick.y + brick.height
			then
				-- Reflect off whichever axis the ball was closer to entering
				-- from -- a simple center-distance heuristic, not full swept
				-- collision, but enough that a brick clipped from the side
				-- doesn't look like it bounced straight down.
				local brickCenterX = brick.x + brick.width / 2
				local brickCenterY = brick.y + brick.height / 2
				local ballCenterX = ballLeft + BALL_SIZE / 2
				local ballCenterY = ballTop + BALL_SIZE / 2
				local dx = (ballCenterX - brickCenterX) / brick.width
				local dy = (ballCenterY - brickCenterY) / brick.height
				if math.abs(dx) > math.abs(dy) then
					ballVX = -ballVX
				else
					ballVY = -ballVY
				end

				brick.frame:Destroy()
				table.remove(bricks, i)
				score += 1
				api.setScore(score)
				api.sounds:Play("Like")
				GameShell.Burst(
					canvas,
					UDim2.fromOffset(brickCenterX, brickCenterY),
					brick.frame.BackgroundColor3,
					api.reduceMotion
				)

				local now = os.clock()
				comboCount = if now - lastBreakTime <= COMBO_WINDOW then comboCount + 1 else 1
				lastBreakTime = now
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
				break
			end
		end

		if #bricks == 0 then
			wave += 1
			waveLabel.Text = string.format("WAVE %d", wave)
			flashScreen(Colors.Mint, 0.7)
			api.sounds:Play("Success")
			spawnWave()
			ballX, ballY, ballVX, ballVY = resetBall()
			ball.Position = UDim2.fromOffset(ballX, ballY)
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
		waveLabel:Destroy()
		paddle:Destroy()
		ball:Destroy()
		clearBricks()
	end
end

return Game
