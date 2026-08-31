--!strict

-- Sky Hopper: an endless vertical bouncer. The hopper bounces automatically
-- off every platform it lands on -- there's no jump input -- so the whole
-- skill is steering left/right (arrows/A-D, drag, or a lane tap) to land on
-- the next platform up before gravity pulls it back down past the bottom of
-- the screen. Wrapping off one side of the canvas reappears on the other,
-- the same convention the mobile games this genre is modeled on use.
--
-- Height climbed is the score, using the same "ceiling" world-shift trick
-- ColorSwitch's vertical climb already established: the hopper never
-- actually rises past a fixed line near the top of the canvas -- once its
-- physics would carry it there, the excess becomes a downward shift applied
-- to every platform/hazard/pickup instead, and that shift is what's summed
-- into the score. Four platform kinds keep a long run from feeling like the
-- same single obstacle repeated: NORMAL (safe), MOVING (slides side to
-- side), BREAKABLE (bounces once, then crumbles away), and SPRING (a much
-- bigger bounce). Floating spike hazards start appearing once a run has some
-- height and must be steered around rather than landed on. Coins build a
-- combo streak the same way DinoRunner/NeonSnake's do; a rarer Shield orb
-- absorbs one hazard hit, and a Jetpack orb grants a few seconds of
-- collision-free auto-ascent with its own particle trail.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors
local SHIELD_COLOR = Colors.Text
local JETPACK_COLOR = Colors.Gold

local GRAVITY = 1500
local BOUNCE_VELOCITY = -640
local SPRING_BOUNCE_VELOCITY = -1060
local JETPACK_VELOCITY = -820 -- constant while active, replacing gravity integration entirely
local JETPACK_DURATION = 3.5
local HOPPER_SIZE = 28
local MOVE_SPEED = 380 -- px/sec while holding a steering key
local DRAG_FOLLOW_RATE = 26 -- how quickly the hopper eases toward a touch/mouse drag target
local CEILING_FRACTION = 0.36
local SCORE_PER_WORLD_UNIT = 6 -- world px climbed per score point

local PLATFORM_HEIGHT = 14
local PLATFORM_WIDTH_BASE = 62
local PLATFORM_WIDTH_MIN = 40
local PLATFORM_WIDTH_SHRINK_PER_SCORE = 0.05
local PLATFORM_SPACING_BASE = 74
local PLATFORM_SPACING_MAX = 118
local PLATFORM_SPACING_PER_SCORE = 0.12
local MOVING_SPEED_BASE = 60
local MOVING_SPEED_MAX = 150
local MOVING_SPEED_PER_SCORE = 0.25
local SPRING_CHANCE = 0.08
local BREAKABLE_CHANCE = 0.18
local MOVING_CHANCE = 0.22
local HAZARD_UNLOCK_SCORE = 25 -- score before spike hazards start rolling instead of a platform
local HAZARD_CHANCE = 0.14 -- of a row, once unlocked, replacing what would've been a platform

local COLLECTIBLE_SPACING_MIN = 90
local COLLECTIBLE_SPACING_MAX = 170
local COIN_SIZE = 14
local COIN_SCORE = 2
local COIN_COMBO_WINDOW = 2.4
local COIN_COMBO_MAX_BONUS = 5
local SPECIAL_PICKUP_CHANCE = 0.24 -- of a collectible spawn, split evenly between Shield/Jetpack
local SHIELD_MAX_CHARGES = 2
local PICKUP_SIZE = 20

local CLOUD_COUNT = 5
local CLOUD_PARALLAX_SPEED = 18

type PlatformKind = "NORMAL" | "MOVING" | "BREAKABLE" | "SPRING"
type Platform = {
	frame: Frame,
	x: number,
	y: number,
	width: number,
	kind: PlatformKind,
	vx: number,
	used: boolean, -- BREAKABLE only: already bounced once, mid-crumble, no longer collidable
}
type Hazard = { frame: Frame, x: number, y: number, size: number }
type PickupKind = "COIN" | "SHIELD" | "JETPACK"
type Pickup = { frame: Frame, x: number, y: number, kind: PickupKind, collected: boolean }
type Cloud = { instance: Frame, x: number, y: number }

local PLATFORM_COLOR: { [PlatformKind]: Color3 } = {
	NORMAL = Colors.Mint,
	MOVING = Colors.Cyan,
	BREAKABLE = Colors.Rose,
	SPRING = Colors.Gold,
}
local PLATFORM_GLYPH: { [PlatformKind]: string } = {
	NORMAL = "",
	MOVING = "↔",
	BREAKABLE = "⚡",
	SPRING = "⇧",
}

local Game = {} :: GameShell.GameModule
Game.Name = "Sky Hopper"
Game.Key = "SkyHopper"

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local heightScore = 0
	local coinScore = 0
	local score = 0
	local displayedScore = -1
	local worldClimbed = 0
	local velocityY = 0
	local hopperX = 0
	local hopperY = 0
	local platforms: { Platform } = {}
	local hazards: { Hazard } = {}
	local pickups: { Pickup } = {}
	local distanceSincePlatform = 0
	local nextPlatformSpacing = PLATFORM_SPACING_BASE
	local distanceSinceCollectible = 0
	local nextCollectibleSpacing = COLLECTIBLE_SPACING_MIN
	local shieldCharges = 0
	local jetpackUntil = 0
	local comboCount = 0
	local lastCoinTime = 0
	local lastStatusText = ""
	local dragTargetX: number? = nil

	local function width(): number
		local w = math.floor(canvas.AbsoluteSize.X)
		return if w > 40 then w else 480
	end
	local function height(): number
		local h = math.floor(canvas.AbsoluteSize.Y)
		return if h > 40 then h else 320
	end
	local function ceiling(): number
		return height() * CEILING_FRACTION
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

	-- Slow-drifting decoration well behind everything else -- purely a depth
	-- cue, same trick FlappyBird's own clouds use, so it's frozen in place
	-- (no per-frame scroll) rather than skipped outright under reduceMotion.
	local clouds: { Cloud } = {}
	for _ = 1, CLOUD_COUNT do
		local cloudSize = 26 + math.random() * 34
		local instance = Factory.New("Frame", {
			Name = "Cloud",
			Size = UDim2.fromOffset(cloudSize, cloudSize * 0.5),
			BackgroundColor3 = Colors.Text,
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = canvas,
		})
		Factory.Corner(instance, cloudSize)
		local x = math.random(0, 480)
		local y = math.random(10, 300)
		instance.Position = UDim2.fromOffset(x, y)
		table.insert(clouds, { instance = instance, x = x, y = y })
	end

	local flashOverlay = Factory.New("Frame", {
		Name = "FlashOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Gold,
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

	local comboLabel = Factory.Label(canvas, "", UDim2.fromOffset(160, 26), {
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
	local statusLabel = Factory.Label(canvas, "", UDim2.fromOffset(220, 18), {
		Name = "StatusLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 34),
		Color = SHIELD_COLOR,
		Font = Theme.Fonts.Bold,
		TextSize = 11,
		AlignX = Enum.TextXAlignment.Center,
		Transparency = 1,
		ZIndex = 46,
	})

	local hopper = Factory.New("Frame", {
		Name = "Hopper",
		Size = UDim2.fromOffset(HOPPER_SIZE, HOPPER_SIZE),
		BackgroundColor3 = Colors.Mint,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = canvas,
	})
	Factory.Corner(hopper, HOPPER_SIZE / 2)
	Factory.Stroke(hopper, Colors.Ink, 0.25, 1.5)
	local hopperScale = Factory.New("UIScale", { Scale = 1, Parent = hopper })
	for _, side in { -1, 1 } do
		local ear = Factory.New("Frame", {
			Name = "Ear",
			Size = UDim2.fromOffset(HOPPER_SIZE * 0.22, HOPPER_SIZE * 0.32),
			Position = UDim2.new(0.5, side * HOPPER_SIZE * 0.28 - HOPPER_SIZE * 0.11, 0, -HOPPER_SIZE * 0.22),
			Rotation = side * -12,
			BackgroundColor3 = Colors.Mint,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = hopper,
		})
		Factory.Corner(ear, HOPPER_SIZE * 0.1)
	end
	local eye = Factory.New("Frame", {
		Name = "Eye",
		Size = UDim2.fromOffset(HOPPER_SIZE * 0.26, HOPPER_SIZE * 0.26),
		Position = UDim2.fromOffset(HOPPER_SIZE * 0.58, HOPPER_SIZE * 0.32),
		BackgroundColor3 = Colors.Text,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = hopper,
	})
	Factory.Corner(eye, HOPPER_SIZE * 0.13)
	Factory.New("Frame", {
		Name = "Pupil",
		Size = UDim2.fromOffset(HOPPER_SIZE * 0.1, HOPPER_SIZE * 0.1),
		Position = UDim2.fromOffset(HOPPER_SIZE * 0.72, HOPPER_SIZE * 0.36),
		BackgroundColor3 = Colors.Ink,
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = hopper,
	})
	local shieldAura = Factory.New("Frame", {
		Name = "ShieldAura",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.6, 1.6),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
		Parent = hopper,
	})
	Factory.Corner(shieldAura, 99)
	local shieldStroke =
		Factory.New("UIStroke", { Color = SHIELD_COLOR, Thickness = 2.5, Transparency = 0.2, Parent = shieldAura })

	hopperX = width() / 2 - HOPPER_SIZE / 2
	hopperY = ceiling()
	hopper.Position = UDim2.fromOffset(hopperX, hopperY)

	local function currentSpacing(): number
		return math.min(PLATFORM_SPACING_MAX, PLATFORM_SPACING_BASE + heightScore * PLATFORM_SPACING_PER_SCORE)
	end
	local function currentPlatformWidth(): number
		return math.max(PLATFORM_WIDTH_MIN, PLATFORM_WIDTH_BASE - heightScore * PLATFORM_WIDTH_SHRINK_PER_SCORE)
	end
	local function currentMovingSpeed(): number
		return math.min(MOVING_SPEED_MAX, MOVING_SPEED_BASE + heightScore * MOVING_SPEED_PER_SCORE)
	end

	local function pickPlatformKind(): PlatformKind
		local roll = math.random()
		if roll < SPRING_CHANCE then
			return "SPRING"
		elseif roll < SPRING_CHANCE + BREAKABLE_CHANCE then
			return "BREAKABLE"
		elseif roll < SPRING_CHANCE + BREAKABLE_CHANCE + MOVING_CHANCE then
			return "MOVING"
		end
		return "NORMAL"
	end

	local function spawnPlatform(initialY: number?)
		local platformWidth = currentPlatformWidth()
		local kind = pickPlatformKind()
		local x = math.random(4, math.max(5, math.floor(width() - platformWidth - 4)))
		local y = initialY or -PLATFORM_HEIGHT
		local frame = Factory.New("Frame", {
			Name = "Platform",
			Size = UDim2.fromOffset(platformWidth, PLATFORM_HEIGHT),
			Position = UDim2.fromOffset(x, y),
			BackgroundColor3 = PLATFORM_COLOR[kind],
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = canvas,
		})
		Factory.Corner(frame, 6)
		Factory.Stroke(frame, Colors.Ink, 0.35, 1.5)
		Factory.Gradient(frame, { Color3.new(1, 1, 1), PLATFORM_COLOR[kind] }, 90)
		if kind == "BREAKABLE" then
			-- A couple of crack ribs read as "fragile" before it's ever
			-- touched, not just after -- the same "signal the hazard before
			-- the player commits to it" idea BrickBreaker's laser-tinted
			-- paddle stroke uses.
			for _, fraction in { 0.35, 0.65 } do
				Factory.New("Frame", {
					Name = "Crack",
					Size = UDim2.new(0, 1.5, 1, -4),
					Position = UDim2.new(fraction, 0, 0, 2),
					Rotation = 18,
					BackgroundColor3 = Colors.Ink,
					BackgroundTransparency = 0.35,
					BorderSizePixel = 0,
					ZIndex = 5,
					Parent = frame,
				})
			end
		end
		if PLATFORM_GLYPH[kind] ~= "" then
			Factory.Label(frame, PLATFORM_GLYPH[kind], UDim2.fromScale(1, 1), {
				TextSize = 11,
				Color = Colors.Ink,
				AlignX = Enum.TextXAlignment.Center,
				AlignY = Enum.TextYAlignment.Center,
				ZIndex = 6,
			})
		end
		local vx = if kind == "MOVING" then currentMovingSpeed() * (if math.random() < 0.5 then -1 else 1) else 0
		table.insert(
			platforms,
			{ frame = frame, x = x, y = y, width = platformWidth, kind = kind, vx = vx, used = false }
		)
	end

	local function spawnHazard(y: number)
		local size = 22 + math.random(0, 10)
		local x = math.random(4, math.max(5, math.floor(width() - size - 4)))
		local frame = Factory.New("Frame", {
			Name = "Hazard",
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromOffset(x, y),
			BackgroundColor3 = Colors.Danger,
			BackgroundTransparency = 0.15,
			Rotation = 45,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = canvas,
		})
		Factory.Stroke(frame, Colors.Ink, 0.3, 1.5)
		Factory.Label(frame, "▲", UDim2.fromScale(1, 1), {
			Rotation = -45,
			TextSize = 12,
			Color = Colors.Text,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 6,
		})
		if not api.reduceMotion then
			TweenService:Create(
				frame,
				TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Rotation = 65 }
			):Play()
		end
		table.insert(hazards, { frame = frame, x = x, y = y, size = size })
	end

	-- One row per spacing tick: either a landing opportunity or, once height
	-- unlocks it, a chance of a hazard to dodge instead -- never both, so a
	-- row is always readable as one clear choice.
	local function spawnRow()
		if heightScore >= HAZARD_UNLOCK_SCORE and math.random() < HAZARD_CHANCE then
			spawnHazard(-30)
		else
			spawnPlatform()
		end
	end

	local function spawnCollectible()
		local roll = math.random()
		local kind: PickupKind = if roll < SPECIAL_PICKUP_CHANCE * 0.5
			then "SHIELD"
			elseif roll < SPECIAL_PICKUP_CHANCE then "JETPACK"
			else "COIN"
		local size = if kind == "COIN" then COIN_SIZE else PICKUP_SIZE
		local x = math.random(math.floor(size), math.max(math.floor(size) + 1, math.floor(width() - size)))
		local color = if kind == "COIN" then Colors.Gold elseif kind == "SHIELD" then SHIELD_COLOR else JETPACK_COLOR
		local glyph = if kind == "COIN" then "◆" elseif kind == "SHIELD" then "🛡" else "🚀"
		local frame = Factory.New("Frame", {
			Name = "Collectible",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromOffset(x, -size),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = canvas,
		})
		Factory.Corner(frame, size / 2)
		Factory.Stroke(frame, Colors.Ink, 0.25, 1.5)
		Factory.Label(frame, glyph, UDim2.fromScale(1, 1), {
			TextSize = if kind == "COIN" then 9 else 11,
			Color = Colors.Ink,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 6,
		})
		if not api.reduceMotion then
			local pulse = Factory.New("UIScale", { Scale = 1, Parent = frame })
			TweenService:Create(
				pulse,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.22 }
			):Play()
		end
		table.insert(pickups, { frame = frame, x = x, y = -size, kind = kind, collected = false })
	end

	-- Seed a handful of rows above the hopper's starting platform so the
	-- very first frame already has somewhere to bounce toward, the same
	-- reason ColorSwitch's very first ring spawns pre-placed instead of
	-- waiting for a climb that hasn't happened yet.
	local startPlatform = Factory.New("Frame", {
		Name = "Platform",
		Size = UDim2.fromOffset(currentPlatformWidth(), PLATFORM_HEIGHT),
		Position = UDim2.fromOffset(0, 0),
		BackgroundColor3 = PLATFORM_COLOR.NORMAL,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = canvas,
	})
	Factory.Corner(startPlatform, 6)
	Factory.Stroke(startPlatform, Colors.Ink, 0.35, 1.5)
	Factory.Gradient(startPlatform, { Color3.new(1, 1, 1), PLATFORM_COLOR.NORMAL }, 90)
	local startWidth = currentPlatformWidth()
	local startX = hopperX + HOPPER_SIZE / 2 - startWidth / 2
	local startY = ceiling() + HOPPER_SIZE + 6
	startPlatform.Position = UDim2.fromOffset(startX, startY)
	table.insert(platforms, {
		frame = startPlatform,
		x = startX,
		y = startY,
		width = startWidth,
		kind = "NORMAL" :: PlatformKind,
		vx = 0,
		used = false,
	})
	for i = 1, 4 do
		spawnPlatform(startY - i * PLATFORM_SPACING_BASE)
	end

	local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragTargetX = input.Position.X - canvas.AbsolutePosition.X - HOPPER_SIZE / 2
		end
	end)
	local dragChangedConn = UserInputService.InputChanged:Connect(function(input)
		if not dragTargetX then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragTargetX = input.Position.X - canvas.AbsolutePosition.X - HOPPER_SIZE / 2
		end
	end)
	local dragEndedConn = UserInputService.InputEnded:Connect(function(input)
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
			hopper.Position + UDim2.fromOffset(HOPPER_SIZE / 2, HOPPER_SIZE / 2),
			Colors.Danger,
			api.reduceMotion
		)
		api.gameOver(score)
	end

	local comboFadeToken = 0
	local function showComboPopup(position: UDim2, combo: number)
		if not api.reduceMotion then
			local popupText = if combo >= 2 then string.format("+%d  x%d", COIN_SCORE, combo) else "+" .. COIN_SCORE
			local popup = Factory.Label(canvas, popupText, UDim2.fromOffset(90, 20), {
				Name = "ScorePopup",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = position,
				Color = if combo >= 5 then Colors.Gold else Colors.Mint,
				Font = Theme.Fonts.Black,
				TextSize = 14,
				AlignX = Enum.TextXAlignment.Center,
				ZIndex = 47,
			})
			Factory.New("UIStroke", { Color = Colors.Ink, Thickness = 1.5, Transparency = 0.5, Parent = popup })
			local tween =
				TweenService:Create(popup, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = position - UDim2.fromOffset(0, 24),
					TextTransparency = 1,
				})
			tween.Completed:Connect(function()
				popup:Destroy()
			end)
			tween:Play()
		end
		comboFadeToken += 1
		local myToken = comboFadeToken
		if combo >= 2 then
			comboLabel.Text = string.format("%dx STREAK", combo)
			comboLabel.TextTransparency = 0
			if not api.reduceMotion then
				local pop = Factory.New("UIScale", { Scale = 1.3, Parent = comboLabel })
				TweenService
					:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
					:Play()
			end
			task.delay(COIN_COMBO_WINDOW, function()
				if myToken == comboFadeToken and comboLabel.Parent then
					if api.reduceMotion then
						comboLabel.TextTransparency = 1
					else
						TweenService:Create(comboLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
					end
				end
			end)
		end
		if combo > 0 and combo % 5 == 0 then
			flashScreen(Colors.Gold, 0.75)
			api.sounds:Play("Success")
			GameShell.Shake(canvas, api.reduceMotion, 0.55)
		end
	end

	local heartbeatConn: RBXScriptConnection
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		dt = math.min(dt, 1 / 20)
		local now = os.clock()
		local w, h = width(), height()

		local jetpacking = now < jetpackUntil
		shieldAura.Visible = shieldCharges > 0
		if shieldCharges > 0 then
			shieldStroke.Transparency = 0.5 + 0.35 * math.sin(now * 8)
		end
		local statusParts = {}
		if shieldCharges > 0 then
			table.insert(statusParts, string.format("🛡 SHIELD ×%d", shieldCharges))
		end
		if jetpacking then
			table.insert(statusParts, "🚀 JETPACK")
		end
		local statusText = table.concat(statusParts, "   ")
		if statusText ~= lastStatusText then
			statusLabel.Text = statusText
			statusLabel.TextTransparency = if statusText == "" then 1 else 0
			lastStatusText = statusText
		end

		if not api.reduceMotion then
			for _, cloud in clouds do
				cloud.x -= CLOUD_PARALLAX_SPEED * dt
				if cloud.x < -60 then
					cloud.x = w + 20
				end
				cloud.instance.Position = UDim2.fromOffset(cloud.x, cloud.y)
			end
		end

		-- Steering: keyboard hold wins whenever pressed, otherwise ease
		-- toward the last drag/tap position -- same precedence BrickBreaker's
		-- paddle already uses. Off either edge wraps to the opposite side
		-- rather than clamping, the expected feel for this genre.
		local left = UserInputService:IsKeyDown(Enum.KeyCode.Left) or UserInputService:IsKeyDown(Enum.KeyCode.A)
		local right = UserInputService:IsKeyDown(Enum.KeyCode.Right) or UserInputService:IsKeyDown(Enum.KeyCode.D)
		if left and not right then
			hopperX -= MOVE_SPEED * dt
		elseif right and not left then
			hopperX += MOVE_SPEED * dt
		elseif dragTargetX then
			local alpha = math.clamp(DRAG_FOLLOW_RATE * dt, 0, 1)
			hopperX += (dragTargetX - hopperX) * alpha
		end
		if hopperX < -HOPPER_SIZE then
			hopperX = w
		elseif hopperX > w then
			hopperX = -HOPPER_SIZE
		end

		if jetpacking then
			velocityY = JETPACK_VELOCITY
		else
			velocityY += GRAVITY * dt
		end
		hopperY += velocityY * dt

		local ceilingY = ceiling()
		local shift = 0
		if hopperY < ceilingY then
			shift = ceilingY - hopperY
			hopperY = ceilingY
		end
		if shift > 0 then
			worldClimbed += shift
			heightScore = math.floor(worldClimbed / SCORE_PER_WORLD_UNIT)
			score = heightScore + coinScore
			if score ~= displayedScore then
				displayedScore = score
				api.setScore(score)
			end
		end

		if hopperY > h then
			hopper.Position = UDim2.fromOffset(hopperX, h)
			endGame()
			return
		end
		hopper.Position = UDim2.fromOffset(hopperX, hopperY)

		if not api.reduceMotion then
			-- Squash while descending, stretch tall right after a bounce --
			-- a continuous readout of velocityY (the real gameplay motion),
			-- not an independent animation, so it stays on even under
			-- reduceMotion the same way the position itself does... except
			-- this part IS purely decorative polish on top of that real
			-- motion, so it's what actually gets skipped.
			local stretch = math.clamp(velocityY / 900, -0.35, 0.5)
			hopperScale.Scale = 1 + math.abs(stretch) * 0.25
			hopper.Rotation = math.clamp(hopperX >= w / 2 and 0 or 0, 0, 0)
		end

		if jetpacking and not api.reduceMotion then
			local trail = Factory.New("Frame", {
				Name = "JetpackTrail",
				Size = UDim2.fromOffset(6, 6),
				Position = hopper.Position + UDim2.fromOffset(HOPPER_SIZE / 2 + math.random(-4, 4), HOPPER_SIZE),
				BackgroundColor3 = JETPACK_COLOR,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = canvas,
			})
			Factory.Corner(trail, 3)
			local trailTween =
				TweenService:Create(trail, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = trail.Position + UDim2.fromOffset(0, 18),
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(2, 2),
				})
			trailTween.Completed:Connect(function()
				trail:Destroy()
			end)
			trailTween:Play()
		end

		distanceSincePlatform += shift
		if distanceSincePlatform >= nextPlatformSpacing then
			distanceSincePlatform -= nextPlatformSpacing
			nextPlatformSpacing = currentSpacing()
			spawnRow()
		end
		distanceSinceCollectible += shift
		if distanceSinceCollectible >= nextCollectibleSpacing then
			distanceSinceCollectible = 0
			nextCollectibleSpacing = COLLECTIBLE_SPACING_MIN
				+ math.random() * (COLLECTIBLE_SPACING_MAX - COLLECTIBLE_SPACING_MIN)
			spawnCollectible()
		end

		local hopperLeft, hopperRight = hopperX, hopperX + HOPPER_SIZE
		local hopperTop, hopperBottom = hopperY, hopperY + HOPPER_SIZE

		for i = #platforms, 1, -1 do
			local platform = platforms[i]
			platform.y += shift
			if platform.kind == "MOVING" and not platform.used then
				platform.x += platform.vx * dt
				if platform.x <= 0 then
					platform.x = 0
					platform.vx = math.abs(platform.vx)
				elseif platform.x + platform.width >= w then
					platform.x = w - platform.width
					platform.vx = -math.abs(platform.vx)
				end
			end
			platform.frame.Position = UDim2.fromOffset(platform.x, platform.y)

			if platform.y > h then
				platform.frame:Destroy()
				table.remove(platforms, i)
				continue
			end

			if
				not platform.used
				and velocityY > 0
				and not jetpacking
				and hopperBottom >= platform.y
				and hopperBottom <= platform.y + PLATFORM_HEIGHT + math.abs(velocityY) * dt
				and hopperRight > platform.x
				and hopperLeft < platform.x + platform.width
			then
				hopperY = platform.y - HOPPER_SIZE
				local bounceColor = PLATFORM_COLOR[platform.kind]
				if platform.kind == "SPRING" then
					velocityY = SPRING_BOUNCE_VELOCITY
					api.sounds:Play("Success")
					GameShell.Ring(
						canvas,
						UDim2.fromOffset(platform.x + platform.width / 2, platform.y),
						bounceColor,
						api.reduceMotion,
						14
					)
					GameShell.Shake(canvas, api.reduceMotion, 0.3)
				else
					velocityY = BOUNCE_VELOCITY
					api.sounds:Play("Press")
					GameShell.Burst(
						canvas,
						UDim2.fromOffset(platform.x + platform.width / 2, platform.y),
						bounceColor,
						api.reduceMotion
					)
				end
				if platform.kind == "BREAKABLE" then
					platform.used = true
					if api.reduceMotion then
						platform.frame:Destroy()
						table.remove(platforms, i)
					else
						local crumble = TweenService:Create(
							platform.frame,
							TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
							{
								Position = platform.frame.Position + UDim2.fromOffset(0, 40),
								Rotation = math.random(-30, 30),
								BackgroundTransparency = 1,
							}
						)
						crumble.Completed:Connect(function()
							platform.frame:Destroy()
						end)
						crumble:Play()
						table.remove(platforms, i)
					end
				end
			end
		end

		for i = #hazards, 1, -1 do
			local hazard = hazards[i]
			hazard.y += shift
			hazard.frame.Position = UDim2.fromOffset(hazard.x, hazard.y)
			if hazard.y > h then
				hazard.frame:Destroy()
				table.remove(hazards, i)
				continue
			end
			if
				not jetpacking
				and hopperRight > hazard.x
				and hopperLeft < hazard.x + hazard.size
				and hopperBottom > hazard.y
				and hopperTop < hazard.y + hazard.size
			then
				if shieldCharges > 0 then
					shieldCharges -= 1
					api.sounds:Play("Success")
					GameShell.Burst(
						canvas,
						UDim2.fromOffset(hazard.x + hazard.size / 2, hazard.y + hazard.size / 2),
						SHIELD_COLOR,
						api.reduceMotion
					)
					GameShell.Shake(canvas, api.reduceMotion, 0.45)
					hazard.frame:Destroy()
					table.remove(hazards, i)
				else
					endGame()
					return
				end
			end
		end

		for i = #pickups, 1, -1 do
			local pickup = pickups[i]
			pickup.y += shift
			pickup.frame.Position = UDim2.fromOffset(pickup.x, pickup.y)
			local pickupSize = if pickup.kind == "COIN" then COIN_SIZE else PICKUP_SIZE
			if pickup.y > h then
				pickup.frame:Destroy()
				table.remove(pickups, i)
				continue
			end
			if
				not pickup.collected
				and hopperRight > pickup.x - pickupSize / 2
				and hopperLeft < pickup.x + pickupSize / 2
				and hopperBottom > pickup.y - pickupSize / 2
				and hopperTop < pickup.y + pickupSize / 2
			then
				pickup.collected = true
				local pickupPosition = pickup.frame.Position
				if pickup.kind == "COIN" then
					comboCount = if now - lastCoinTime <= COIN_COMBO_WINDOW then comboCount + 1 else 1
					lastCoinTime = now
					local bonus = COIN_SCORE + math.min(comboCount - 1, COIN_COMBO_MAX_BONUS)
					coinScore += bonus
					score = heightScore + coinScore
					api.setScore(score)
					displayedScore = score
					api.sounds:Play("Like")
					GameShell.Burst(canvas, pickupPosition, Colors.Gold, api.reduceMotion)
					showComboPopup(pickupPosition, comboCount)
				elseif pickup.kind == "SHIELD" then
					shieldCharges = math.min(SHIELD_MAX_CHARGES, shieldCharges + 1)
					api.sounds:Play("Success")
					GameShell.Burst(canvas, pickupPosition, SHIELD_COLOR, api.reduceMotion)
					GameShell.Ring(canvas, pickupPosition, SHIELD_COLOR, api.reduceMotion, 12)
				else
					jetpackUntil = math.max(jetpackUntil, now) + JETPACK_DURATION
					api.sounds:Play("Success")
					GameShell.Burst(canvas, pickupPosition, JETPACK_COLOR, api.reduceMotion)
					GameShell.Ring(canvas, pickupPosition, JETPACK_COLOR, api.reduceMotion, 14)
				end
				pickup.frame:Destroy()
				table.remove(pickups, i)
			end
		end
	end)

	return function()
		running = false
		heartbeatConn:Disconnect()
		inputConn:Disconnect()
		dragChangedConn:Disconnect()
		dragEndedConn:Disconnect()
		sky:Destroy()
		flashOverlay:Destroy()
		comboLabel:Destroy()
		statusLabel:Destroy()
		hopper:Destroy()
		for _, cloud in clouds do
			cloud.instance:Destroy()
		end
		for _, platform in platforms do
			platform.frame:Destroy()
		end
		table.clear(platforms)
		for _, hazard in hazards do
			hazard.frame:Destroy()
		end
		table.clear(hazards)
		for _, pickup in pickups do
			pickup.frame:Destroy()
		end
		table.clear(pickups)
	end
end

return Game
