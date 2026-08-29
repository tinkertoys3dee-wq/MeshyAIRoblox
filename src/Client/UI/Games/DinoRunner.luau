--!strict

-- Dino Runner: tap/click/space to jump over cacti scrolling in from the
-- right at ground level. Score is distance survived (classic Chrome-dino
-- scoring, not an obstacle counter) plus whatever coin bonuses were
-- collected along the way, and speed ramps with distance so the game keeps
-- getting harder without needing separate difficulty tiers.
--
-- On top of the base jump, three things raise the ceiling on how exciting a
-- run can get without changing what a "run" fundamentally is:
--   - A second, mid-air jump (a real double jump, not just a taller single
--     one) for extra control over tricky obstacle timing.
--   - Ducking (hold Down/S) -- a shorter, ground-only crouch that clears a
--     pterodactyl's flight band the same way jumping over it does. Jumping
--     always still works too (a pterodactyl never requires a duck), so
--     touch/mouse players -- who have no duck input -- are never blocked,
--     just missing the extra option keyboard players get.
--   - Floating coins (small bonus score) and a rarer shield coin (temporary
--     invincibility that lets the dino plow straight through the next
--     obstacle or two instead of dying to it).

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors
local SHIELD_COLOR = Colors.Gold

local GRAVITY = 2200
local JUMP_VELOCITY = -760
local DOUBLE_JUMP_VELOCITY = -620
local MAX_JUMPS = 2
local DUCK_SCALE = 0.55 -- fraction of DINO_SIZE the dino's height shrinks to while ducking
local DINO_SIZE = 30
local DINO_X = 56
local GROUND_MARGIN = 24
local BASE_SPEED = 300
local SPEED_PER_SCORE = 0.75
local MAX_SPEED = 760
local SCORE_PER_SECOND = 10
local TICK_COUNT = 8
local TICK_SPACING = 70
-- In hundredths of a second so math.random (integers only) can pick between
-- them directly -- computing these from float seconds risks a value like
-- 1.6 * 100 landing on 159.999999... and erroring math.random on a
-- non-integer argument.
local MIN_OBSTACLE_GAP_CENTIS = 90
local MAX_OBSTACLE_GAP_CENTIS = 160
local MIN_COIN_GAP_CENTIS = 150
local MAX_COIN_GAP_CENTIS = 270
local FLYING_UNLOCK_SCORE = 8 -- pterodactyls only start appearing once the run has some legs
local FLYING_CHANCE = 0.32 -- of obstacles spawned once unlocked
local FLY_BOTTOM_HEIGHT = 22 -- how far above the ground surface a pterodactyl's belly sits
local FLY_HEIGHT = 16
local COIN_SIZE = 12
local COIN_BONUS = 3
local SHIELD_BONUS = 5
local SHIELD_CHANCE = 0.22 -- of coin spawns
local SHIELD_DURATION = 4
local DAY_CYCLE_SECONDS = 45 -- full day-to-night-to-day loop
local STAR_COUNT = 10
local DUST_INTERVAL = 0.08 -- continuous foot-dust cadence while grounded
local SKY_NIGHT_TOP = Color3.fromRGB(21, 24, 48)
local SKY_NIGHT_BOTTOM = Color3.fromRGB(8, 9, 20)
local SUN_DAY_COLOR = Colors.Gold
local MOON_NIGHT_COLOR = Color3.fromRGB(214, 222, 240)

type Obstacle = { frame: Frame, x: number, width: number, height: number, flying: boolean, deflected: boolean }
type Coin = { frame: Frame, x: number, y: number, shield: boolean }

local Game = {} :: GameShell.GameModule
Game.Name = "Dino Runner"
Game.Key = "DinoRunner"

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local dinoY = 0
	local velocityY = 0
	local onGround = true
	local jumpsUsed = 0
	local wasDucking = false
	local elapsed = 0
	local distanceScore = 0
	local bonusScore = 0
	local score = 0
	local displayedScore = -1
	local obstacles: { Obstacle } = {}
	local coins: { Coin } = {}
	local timeSinceObstacle = 0
	local nextObstacleGap = MIN_OBSTACLE_GAP_CENTIS / 100
	local timeSinceCoin = 0
	local nextCoinGap = MIN_COIN_GAP_CENTIS / 100
	local timeSinceDust = 0
	local shieldUntil = 0
	local lastStatusText = ""

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

	local statusLabel = Factory.Label(canvas, "", UDim2.fromOffset(200, 18), {
		Name = "StatusLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Color = SHIELD_COLOR,
		Font = Theme.Fonts.Bold,
		TextSize = 11,
		AlignX = Enum.TextXAlignment.Center,
		Transparency = 1,
		ZIndex = 8,
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
	-- Squash/stretch handle: cosmetic scale pulse on takeoff/landing, gated
	-- under reduceMotion the same way FlappyBird's flap-squash is -- the
	-- dino's actual jump arc (the gameplay motion) is unaffected either way.
	-- Also doubles as the duck crouch's shrink (see applyPose below) --
	-- ducking and the jump-squash tween never run at the same time (jump()
	-- always clears ducking first), so the two never fight over this one
	-- UIScale. Children below (tail/legs/eye) inherit this scale and the
	-- dino's own Rotation automatically.
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
	-- A soft pulsing gold aura shown only while the shield is active --
	-- child of dino so it tracks its position/scale for free, same trick the
	-- shell's own decorations use elsewhere.
	local shieldAura = Factory.New("Frame", {
		Name = "ShieldAura",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.6, 1.6),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
		Parent = dino,
	})
	Factory.Corner(shieldAura, 99)
	local shieldStroke =
		Factory.New("UIStroke", { Color = SHIELD_COLOR, Thickness = 2.5, Transparency = 0.2, Parent = shieldAura })
	dinoY = groundY()

	local function jump()
		if not running or jumpsUsed >= MAX_JUMPS then
			return
		end
		jumpsUsed += 1
		velocityY = if jumpsUsed == 1 then JUMP_VELOCITY else DOUBLE_JUMP_VELOCITY
		onGround = false
		api.sounds:Play("Press")
		GameShell.Burst(
			canvas,
			dino.Position + UDim2.fromOffset(DINO_SIZE / 2, DINO_SIZE),
			Colors.Line,
			api.reduceMotion
		)
		if jumpsUsed == 2 then
			-- A distinct flourish for the double jump specifically -- it's
			-- the more skillful, less automatic of the two, so it earns a
			-- bigger cue than the routine first jump gets.
			GameShell.Ring(
				canvas,
				dino.Position + UDim2.fromOffset(DINO_SIZE / 2, DINO_SIZE / 2),
				Colors.Cyan,
				api.reduceMotion,
				8
			)
		end
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
		return math.min(MAX_SPEED, BASE_SPEED + distanceScore * SPEED_PER_SCORE)
	end

	local function spawnObstacle()
		local flying = distanceScore >= FLYING_UNLOCK_SCORE and math.random() < FLYING_CHANCE
		local h = if flying then FLY_HEIGHT else math.random(24, 42)
		local w = if flying then math.random(24, 30) else math.random(16, 26)
		local frame = Factory.New("Frame", {
			Name = if flying then "Pterodactyl" else "Cactus",
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = if flying then Colors.Violet else Colors.Rose,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = canvas,
		})
		Factory.Corner(frame, if flying then 8 else 4)
		if flying then
			-- A pair of angled wing shapes read as "flying thing", distinct
			-- silhouette from the ground cacti below.
			for _, side in { -1, 1 } do
				local wing = Factory.New("Frame", {
					Name = "Wing",
					Size = UDim2.fromOffset(w * 0.55, h * 0.35),
					Position = UDim2.new(0.5, side > 0 and 0 or -w * 0.55, 0.5, -h * 0.15),
					Rotation = side * 18,
					BackgroundColor3 = Color3.fromRGB(168, 130, 255),
					BorderSizePixel = 0,
					ZIndex = 4,
					Parent = frame,
				})
				Factory.Corner(wing, 4)
			end
			if not api.reduceMotion then
				local flap = Factory.New("UIScale", { Scale = 1, Parent = frame })
				TweenService:Create(
					flap,
					TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Scale = 1.12 }
				):Play()
			end
		else
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
		end
		local x = width() + w
		table.insert(obstacles, { frame = frame, x = x, width = w, height = h, flying = flying, deflected = false })
	end

	local function spawnCoin()
		local shield = math.random() < SHIELD_CHANCE
		local y = groundY() - math.random(40, 95)
		local frame = Factory.New("Frame", {
			Name = if shield then "ShieldCoin" else "Coin",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(COIN_SIZE, COIN_SIZE),
			Position = UDim2.fromOffset(width() + COIN_SIZE, y),
			BackgroundColor3 = if shield then SHIELD_COLOR else Colors.Gold,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = canvas,
		})
		Factory.Corner(frame, COIN_SIZE / 2)
		Factory.Stroke(frame, Colors.Ink, 0.3, 1.5)
		Factory.Label(frame, if shield then "🛡" else "◆", UDim2.fromScale(1, 1), {
			TextSize = if shield then 9 else 8,
			Color = Colors.Ink,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 5,
		})
		if not api.reduceMotion then
			local bob = Factory.New("UIScale", { Scale = 1, Parent = frame })
			TweenService:Create(
				bob,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.2 }
			):Play()
		end
		table.insert(coins, { frame = frame, x = width() + COIN_SIZE, y = y, shield = shield })
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
		distanceScore = math.floor(elapsed * SCORE_PER_SECOND)
		score = distanceScore + bonusScore
		if score ~= displayedScore then
			displayedScore = score
			api.setScore(score)
		end

		if not api.reduceMotion then
			updateDayNightCycle(elapsed)
		end

		local now = os.clock()
		local shielded = now < shieldUntil
		shieldAura.Visible = shielded
		if shielded then
			local pulse = 0.5 + 0.35 * math.sin(now * 8)
			shieldStroke.Transparency = pulse
		end
		local statusText = if shielded then "🛡 SHIELD" else ""
		if statusText ~= lastStatusText then
			statusLabel.Text = statusText
			statusLabel.TextTransparency = if statusText == "" then 1 else 0
			lastStatusText = statusText
		end

		local ground = groundY()
		local wasAirborne = not onGround
		velocityY += GRAVITY * dt
		dinoY += velocityY * dt
		if dinoY >= ground then
			dinoY = ground
			velocityY = 0
			onGround = true
			jumpsUsed = 0
			if wasAirborne then
				GameShell.Burst(
					canvas,
					dino.Position + UDim2.fromOffset(DINO_SIZE / 2, DINO_SIZE),
					Colors.Line,
					api.reduceMotion
				)
				GameShell.Ring(
					canvas,
					dino.Position + UDim2.fromOffset(DINO_SIZE / 2, DINO_SIZE),
					Colors.Line,
					api.reduceMotion,
					10
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

		-- Ducking only applies grounded -- holding it mid-air is a no-op
		-- until landing re-derives it fresh, so a jump always fully clears
		-- (and a landing while still holding Down re-enters it naturally).
		local duckKeyHeld = UserInputService:IsKeyDown(Enum.KeyCode.Down) or UserInputService:IsKeyDown(Enum.KeyCode.S)
		local ducking = duckKeyHeld and onGround and jumpsUsed == 0
		if ducking then
			dinoScale.Scale = DUCK_SCALE
		elseif wasDucking then
			if api.reduceMotion then
				dinoScale.Scale = 1
			else
				TweenService
					:Create(
						dinoScale,
						TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Scale = 1 }
					)
					:Play()
			end
		end
		wasDucking = ducking

		-- Render position and the hitbox used below both derive from the
		-- same values -- ducking (only possible while grounded, so dinoY
		-- already equals `ground` when it applies) shrinks height only, feet
		-- staying planted on the ground; airborne always just follows the
		-- real physics position, never the ground line. Single source of
		-- truth for both what's drawn and what a pterodactyl actually has to
		-- clear.
		local dinoHitHeight = if ducking then DINO_SIZE * DUCK_SCALE else DINO_SIZE
		local dinoHitTop = if ducking then (ground + DINO_SIZE - dinoHitHeight) else dinoY
		dino.Position = UDim2.fromOffset(DINO_X, dinoHitTop)

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

		timeSinceCoin += dt
		if timeSinceCoin >= nextCoinGap then
			timeSinceCoin = 0
			nextCoinGap = math.random(MIN_COIN_GAP_CENTIS, MAX_COIN_GAP_CENTIS) / 100
			spawnCoin()
		end

		for _, tick in groundTicks do
			tick.x -= speed * dt
			if tick.x < -20 then
				tick.x += TICK_COUNT * TICK_SPACING
			end
			tick.instance.Position = UDim2.fromOffset(tick.x, ground + DINO_SIZE)
		end

		local dinoLeft, dinoRight = DINO_X, DINO_X + DINO_SIZE
		local dinoTop, dinoBottom = dinoHitTop, dinoHitTop + dinoHitHeight

		for i = #obstacles, 1, -1 do
			local obstacle = obstacles[i]
			obstacle.x -= speed * dt
			local obstacleTop = if obstacle.flying
				then ground + DINO_SIZE - FLY_BOTTOM_HEIGHT - obstacle.height
				else ground + DINO_SIZE - obstacle.height
			obstacle.frame.Position = UDim2.fromOffset(obstacle.x, obstacleTop)

			if obstacle.x + obstacle.width < 0 then
				obstacle.frame:Destroy()
				table.remove(obstacles, i)
				continue
			end

			local obLeft, obRight = obstacle.x, obstacle.x + obstacle.width
			local obTop, obBottom = obstacleTop, obstacleTop + obstacle.height
			if dinoRight > obLeft and dinoLeft < obRight and dinoBottom > obTop and dinoTop < obBottom then
				if shielded then
					if not obstacle.deflected then
						obstacle.deflected = true
						GameShell.Burst(
							canvas,
							UDim2.fromOffset(obLeft + obstacle.width / 2, obTop + obstacle.height / 2),
							SHIELD_COLOR,
							api.reduceMotion
						)
						obstacle.frame:Destroy()
						table.remove(obstacles, i)
					end
				else
					endGame()
					return
				end
			end
		end

		for i = #coins, 1, -1 do
			local coin = coins[i]
			coin.x -= speed * dt
			coin.frame.Position = UDim2.fromOffset(coin.x, coin.y)

			if coin.x + COIN_SIZE < 0 then
				coin.frame:Destroy()
				table.remove(coins, i)
				continue
			end

			if
				dinoRight > coin.x
				and dinoLeft < coin.x + COIN_SIZE
				and dinoBottom > coin.y
				and dinoTop < coin.y + COIN_SIZE
			then
				local coinPosition = coin.frame.Position
				local isShield = coin.shield
				coin.frame:Destroy()
				table.remove(coins, i)
				bonusScore += if isShield then SHIELD_BONUS else COIN_BONUS
				if isShield then
					shieldUntil = math.max(shieldUntil, now) + SHIELD_DURATION
				end
				api.sounds:Play(if isShield then "Success" else "Hover")
				local color = if isShield then SHIELD_COLOR else Colors.Gold
				GameShell.Burst(
					canvas,
					coinPosition + UDim2.fromOffset(COIN_SIZE / 2, COIN_SIZE / 2),
					color,
					api.reduceMotion
				)
				GameShell.Ring(
					canvas,
					coinPosition + UDim2.fromOffset(COIN_SIZE / 2, COIN_SIZE / 2),
					color,
					api.reduceMotion,
					10
				)
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
		statusLabel:Destroy()
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
		for _, coin in coins do
			coin.frame:Destroy()
		end
		table.clear(coins)
	end
end

return Game
