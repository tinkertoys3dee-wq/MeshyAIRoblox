--!strict

-- Color Switch: a vertical climber modeled on the mobile game of the same
-- name. The ball only ever moves along a single vertical line (its X is
-- fixed at canvas center) -- tapping gives it an upward bounce, gravity
-- pulls it back down the instant you stop tapping, and if you never retap it
-- falls indefinitely until it hits the bottom of the canvas (a loss, same as
-- FlappyBird's ground).
--
-- Rings do NOT scroll on their own -- in the real game they only rotate in
-- place, and the world only moves when the player actually climbs. Modeled
-- here as a "ceiling": once the ball's physics would carry it above
-- `ceiling()`, the excess is converted into a world shift instead (the ball
-- gets pinned at the ceiling, every ring/orb moves down by that same
-- amount) -- so a ring sits dead still, spinning, for as long as the ball
-- is below the ceiling or simply falling, exactly like the idle/start
-- screen of the real game where nothing scrolls until you tap.
--
-- Each ring is a spinning 4-color wheel with a genuinely empty hollow
-- center (no readout, no glyph -- just a hole), matching the real game: the
-- ball must pass through whichever of the 4 colored sections is currently
-- facing its approach side (the bottom, since the ball rises into the ring
-- from below), judged by eye off the actual spin, not a separate indicator.
-- Which section currently faces the ball is read directly off Roblox's own
-- rendered layout (AbsolutePosition/AbsoluteSize of the actual spinning
-- pieces) rather than computed by hand from the rotation angle -- deriving
-- "which of 4 squares rotated by R degrees is now at the bottom" via
-- trigonometry is exactly the kind of math that's easy to get subtly wrong
-- with no way to see the result, so instead this just asks the engine where
-- it actually put things. Passing a ring while the ball's own color matches
-- scores a point; a mismatch ends the run. Colored orbs drift down the same
-- line and change the ball's current color on contact -- the only way to
-- prepare for an upcoming ring that doesn't already match.

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
-- non-color signal too -- the ball, every orb, and every ring petal all
-- show shape, not just hue.
local PALETTE_SHAPES = { "●", "▲", "■", "★" }
local PALETTE_COUNT = #PALETTE_COLORS

local GRAVITY = 1150
local BOUNCE_VELOCITY = -430
local BALL_SIZE = 24
local RING_SIZE = 84
local RING_HUB_SIZE = 40
local RING_SPACING_BASE = 230 -- world px climbed between ring spawns
local RING_SPACING_MIN = 130
local RING_SPACING_PER_SCORE = 4
local RING_SPIN_MIN = 90 -- deg/sec
local RING_SPIN_MAX = 190
local ORB_SIZE = 22
local ORB_SPACING_MIN = 320 -- world px climbed between orb spawns
local ORB_SPACING_MAX = 520
local TRAIL_INTERVAL = 0.045
local CEILING_FRACTION = 0.32 -- how far down the canvas the ball is pinned
local NEAR_MISS_SEAM_DEGREES = 10 -- how close to a petal boundary counts as a close call
local STREAK_WINDOW = 3.5 -- seconds between clean passes before the streak resets

-- Special (non-color) orbs: SHIELD stacks up to SHIELD_MAX_CHARGES free
-- passes through a wrong-colored ring instead of ending the run, and
-- MULTIPLIER doubles ring score for a few seconds. Both drift down the same
-- line as a normal color orb and share its collection code path, just
-- carrying a different `kind` -- see spawnOrb/the orb-collision loop below.
local SPECIAL_ORB_CHANCE = 0.22 -- of orb spawns, split evenly between the two kinds
local SHIELD_COLOR = Colors.Text
local SHIELD_MAX_CHARGES = 2
local MULTIPLIER_COLOR = Colors.Gold
local MULTIPLIER_DURATION = 8

type Ring = {
	backing: Frame,
	spinner: Frame,
	petals: { Frame },
	quadrantColors: { number },
	rotation: number,
	spinSpeed: number,
	y: number,
	checked: boolean,
}
type OrbKind = "COLOR" | "SHIELD" | "MULTIPLIER"
type Orb = { frame: Frame, colorIndex: number?, kind: OrbKind, y: number, collected: boolean }

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
	local distanceSinceRing = 0
	local distanceSinceOrb = 0
	local nextOrbSpacing = ORB_SPACING_MIN + math.random() * (ORB_SPACING_MAX - ORB_SPACING_MIN)
	local trailTimer = 0
	local streakCount = 0
	local lastPassTime = 0
	local shieldCharges = 0
	local scoreMultiplierUntil = 0
	local lastStatusText = ""

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
	-- A soft pulsing ring shown only while a shield charge is banked, and a
	-- small floating badge only while the score multiplier is active -- both
	-- children of the ball so they track its position/scale for free.
	local shieldRing = Factory.New("Frame", {
		Name = "ShieldRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.55, 1.55),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = ball,
	})
	Factory.Corner(shieldRing, 99)
	local shieldRingStroke =
		Factory.New("UIStroke", { Color = SHIELD_COLOR, Thickness = 2.5, Transparency = 0.2, Parent = shieldRing })
	local multiplierBadge = Factory.Label(ball, "×2", UDim2.fromOffset(30, 16), {
		Name = "MultiplierBadge",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -6),
		Color = MULTIPLIER_COLOR,
		Font = Theme.Fonts.Black,
		TextSize = 13,
		Visible = false,
		ZIndex = 8,
	})
	Factory.New("UIStroke", { Color = Colors.Ink, Thickness = 1.5, Transparency = 0.4, Parent = multiplierBadge })
	local ballY = height() * 0.55
	ball.Position = UDim2.fromOffset(centerX() - BALL_SIZE / 2, ballY)

	-- Full-canvas tint for the near-miss "close call" cue, mirroring the
	-- same trick used in FlappyBird/DinoRunner -- sits above every ring/orb
	-- so a quick flash reads as a screen-wide reaction.
	local flashOverlay = Factory.New("Frame", {
		Name = "FlashOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Cyan,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 45,
		Parent = canvas,
	})
	-- Streak readout: hidden until two clean ring passes land within
	-- STREAK_WINDOW of each other, then tracks the run until it lapses.
	local streakLabel = Factory.Label(canvas, "", UDim2.fromOffset(160, 28), {
		Name = "StreakLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Color = Colors.Gold,
		Font = Theme.Fonts.Black,
		TextSize = 20,
		AlignX = Enum.TextXAlignment.Center,
		Transparency = 1,
		ZIndex = 46,
	})
	Factory.New("UIStroke", {
		Color = Colors.Ink,
		Thickness = 2,
		Transparency = 0.4,
		Parent = streakLabel,
	})
	local statusLabel = Factory.Label(canvas, "", UDim2.fromOffset(200, 16), {
		Name = "StatusLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 44),
		Color = SHIELD_COLOR,
		Font = Theme.Fonts.Bold,
		TextSize = 11,
		AlignX = Enum.TextXAlignment.Center,
		Transparency = 1,
		ZIndex = 46,
	})

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

	-- Fires when a clean pass happened close to the seam between two petals
	-- -- a beat later or earlier and the wrong color would have been facing
	-- the ball, so it reads as a genuine close call rather than a routine
	-- pass.
	local function triggerNearMiss()
		flashScreen(Colors.Cyan, 0.82)
		GameShell.Burst(
			canvas,
			ball.Position + UDim2.fromOffset(BALL_SIZE / 2, BALL_SIZE / 2),
			Colors.Cyan,
			api.reduceMotion
		)
	end

	local streakFadeToken = 0
	local function registerStreak()
		local now = os.clock()
		streakCount = if now - lastPassTime <= STREAK_WINDOW then streakCount + 1 else 1
		lastPassTime = now

		streakFadeToken += 1
		local myToken = streakFadeToken
		if streakCount >= 2 then
			streakLabel.Text = string.format("%dx STREAK", streakCount)
			streakLabel.TextColor3 = if streakCount >= 5 then Colors.Gold else Colors.Mint
			streakLabel.TextTransparency = 0
			if not api.reduceMotion then
				local pop = Factory.New("UIScale", { Scale = 1.3, Parent = streakLabel })
				TweenService
					:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
					:Play()
			end
			task.delay(STREAK_WINDOW, function()
				if myToken == streakFadeToken and streakLabel.Parent then
					if api.reduceMotion then
						streakLabel.TextTransparency = 1
					else
						TweenService:Create(streakLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
					end
				end
			end)
		end

		if streakCount > 0 and streakCount % 5 == 0 then
			flashScreen(Colors.Gold, 0.75)
			api.sounds:Play("Success")
		end
	end

	-- `initialY` lets the very first ring spawn already visible near the
	-- ceiling (matching the real game's idle screen) instead of starting
	-- off-canvas and waiting for a climb that hasn't happened yet.
	local function spawnRing(initialY: number?)
		local y = initialY or -RING_SIZE
		local backing = Factory.New("Frame", {
			Name = "Ring",
			Size = UDim2.fromOffset(RING_SIZE, RING_SIZE),
			Position = UDim2.fromOffset(centerX() - RING_SIZE / 2, y),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = canvas,
		})
		-- Rectangular clipping (Roblox clips to the object's own bounds, not
		-- its rounded corners) still keeps the spinning petals from
		-- overflowing past the ring at 45-degree-ish angles, when a square
		-- petal's rotated corner would otherwise reach further from center
		-- than the ring's own radius.
		backing.ClipsDescendants = true
		Factory.Corner(backing, RING_SIZE / 2)
		Factory.Stroke(backing, Colors.Line, 0.5, 1.5)

		-- AnchorPoint (0.5, 0.5) is load-bearing: Roblox rotates a GuiObject
		-- around its AnchorPoint, which defaults to the top-left corner. Left
		-- at the default, the petals swing in a wide arc around that corner
		-- instead of spinning in place around the ring's own center -- which
		-- is exactly why the ring looked stuck/broken before this fix.
		local spinner = Factory.New("Frame", {
			Name = "Spinner",
			Size = UDim2.fromScale(1, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = backing,
		})
		local quadrantColors = shuffledIndices()
		local petalMargin = 7
		local petalGap = 5
		local petalSize = (RING_SIZE - petalMargin * 2 - petalGap) / 2
		local petalOffsets = {
			{ petalMargin, petalMargin },
			{ petalMargin + petalSize + petalGap, petalMargin },
			{ petalMargin, petalMargin + petalSize + petalGap },
			{ petalMargin + petalSize + petalGap, petalMargin + petalSize + petalGap },
		}
		local petals = {}
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
			-- Colorblind redundancy now that the center is genuinely empty
			-- (no separate readout there): each petal carries its own shape
			-- glyph, same as the ball and orbs. It spins with the petal, but
			-- a glance still reads it -- shape, not orientation, is the
			-- signal.
			Factory.Label(petal, PALETTE_SHAPES[quadrantColors[i]], UDim2.fromScale(1, 1), {
				Color = Colors.Ink,
				TextSize = 12,
				AlignX = Enum.TextXAlignment.Center,
				AlignY = Enum.TextYAlignment.Center,
				ZIndex = 3,
			})
			petals[i] = petal
		end

		local rotation = math.random(0, 359)
		spinner.Rotation = rotation
		local spinSpeed = (RING_SPIN_MIN + math.random() * (RING_SPIN_MAX - RING_SPIN_MIN))
			* (if math.random() < 0.5 then -1 else 1)

		-- A plain, non-rotating hollow hole punched through the middle of
		-- the spinning petals -- genuinely empty (no color, no readout),
		-- matching the real game: the ball reads whichever petal is
		-- actually facing it, not a separate indicator.
		local hub = Factory.New("Frame", {
			Name = "Hub",
			Size = UDim2.fromOffset(RING_HUB_SIZE, RING_HUB_SIZE),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = backing,
		})
		Factory.Corner(hub, RING_HUB_SIZE / 2)

		table.insert(rings, {
			backing = backing,
			spinner = spinner,
			petals = petals,
			quadrantColors = quadrantColors,
			rotation = rotation,
			spinSpeed = spinSpeed,
			y = y,
			checked = false,
		})
	end

	local function spawnOrb()
		local roll = math.random()
		local kind: OrbKind = if roll < SPECIAL_ORB_CHANCE * 0.5
			then "SHIELD"
			elseif roll < SPECIAL_ORB_CHANCE then "MULTIPLIER"
			else "COLOR"
		local colorIndex: number? = nil
		local color: Color3
		local glyph: string
		if kind == "COLOR" then
			local picked = math.random(1, PALETTE_COUNT)
			while picked == ballColorIndex do
				picked = math.random(1, PALETTE_COUNT)
			end
			colorIndex = picked
			color = PALETTE_COLORS[picked]
			glyph = PALETTE_SHAPES[picked]
		elseif kind == "SHIELD" then
			color = SHIELD_COLOR
			glyph = "🛡"
		else
			color = MULTIPLIER_COLOR
			glyph = "×2"
		end
		local frame = Factory.New("Frame", {
			Name = "Orb",
			Size = UDim2.fromOffset(ORB_SIZE, ORB_SIZE),
			Position = UDim2.fromOffset(centerX() - ORB_SIZE / 2, -ORB_SIZE),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = canvas,
		})
		Factory.Corner(frame, ORB_SIZE / 2)
		Factory.Stroke(frame, Colors.Ink, 0.2, 2)
		Factory.Label(frame, glyph, UDim2.fromScale(1, 1), {
			Color = Colors.Ink,
			TextSize = if kind == "COLOR" then 11 else 9,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 5,
		})
		-- A soft pulsing glow ring around the orb -- purely decorative, so
		-- it's skipped under reduceMotion.
		if not api.reduceMotion then
			local glow = Factory.New("Frame", {
				Name = "Glow",
				Size = UDim2.fromOffset(ORB_SIZE, ORB_SIZE),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = color,
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = frame,
			})
			Factory.Corner(glow, ORB_SIZE / 2)
			local glowTween = TweenService:Create(
				glow,
				TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Size = UDim2.fromOffset(ORB_SIZE * 1.6, ORB_SIZE * 1.6), BackgroundTransparency = 1 }
			)
			glowTween:Play()
		end
		table.insert(orbs, { frame = frame, colorIndex = colorIndex, kind = kind, y = -ORB_SIZE, collected = false })
	end

	-- A ring within this many pixels of the top already claimed the spawn
	-- slot this tick -- skipped so an orb never spawns stacked on top of a
	-- ring the instant both counters cross their threshold together.
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

	-- The very first ring is already on screen and spinning before any
	-- input, same as the real game's idle/start state.
	spawnRing(ceiling() - RING_SIZE * 0.65)

	local heartbeatConn: RBXScriptConnection
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		dt = math.min(dt, 1 / 20)

		local now = os.clock()
		local multiplierActive = now < scoreMultiplierUntil
		shieldRing.Visible = shieldCharges > 0
		if shieldCharges > 0 then
			shieldRingStroke.Transparency = 0.5 + 0.35 * math.sin(now * 8)
		end
		multiplierBadge.Visible = multiplierActive
		local statusParts = {}
		if shieldCharges > 0 then
			table.insert(statusParts, string.format("🛡 SHIELD ×%d", shieldCharges))
		end
		if multiplierActive then
			table.insert(statusParts, "×2 SCORE")
		end
		local statusText = table.concat(statusParts, "   ")
		if statusText ~= lastStatusText then
			statusLabel.Text = statusText
			statusLabel.TextTransparency = if statusText == "" then 1 else 0
			lastStatusText = statusText
		end

		velocityY += GRAVITY * dt
		ballY += velocityY * dt

		-- The ball never actually rises past the ceiling -- any climb past
		-- it is converted into a world shift instead, applied to every ring
		-- and orb below. Purely falling (or sitting below the ceiling)
		-- produces zero shift, so nothing moves but the ball itself, which
		-- is exactly the "gates only rotate, they don't scroll" behavior of
		-- the real game.
		local ceilingY = ceiling()
		local shift = 0
		if ballY < ceilingY then
			shift = ceilingY - ballY
			ballY = ceilingY
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

		if shift > 0 then
			distanceSinceRing += shift
			distanceSinceOrb += shift
			local ringSpacing = math.max(RING_SPACING_MIN, RING_SPACING_BASE - score * RING_SPACING_PER_SCORE)
			if distanceSinceRing >= ringSpacing then
				distanceSinceRing -= ringSpacing
				spawnRing()
			end
			if distanceSinceOrb >= nextOrbSpacing then
				distanceSinceOrb = 0
				nextOrbSpacing = ORB_SPACING_MIN + math.random() * (ORB_SPACING_MAX - ORB_SPACING_MIN)
				if orbSlotFree() then
					spawnOrb()
				end
			end
		end

		local ballTop, ballBottom = ballY, ballY + BALL_SIZE

		for i = #rings, 1, -1 do
			local ring = rings[i]
			ring.y += shift
			-- Rotation always advances, shift or not -- this is the part of
			-- the ring that's never supposed to stop.
			ring.rotation = (ring.rotation + ring.spinSpeed * dt) % 360
			ring.backing.Position = UDim2.fromOffset(centerX() - RING_SIZE / 2, ring.y)
			ring.spinner.Rotation = ring.rotation

			-- Whichever petal Roblox actually rendered lowest (largest
			-- AbsolutePosition.Y) is the one currently facing the ball's
			-- approach side -- read straight from the engine's own layout
			-- rather than re-derived from the rotation angle by hand.
			local facingIndex = 1
			local lowestY = -math.huge
			for petalIndex, petal in ring.petals do
				local petalCenterY = petal.AbsolutePosition.Y + petal.AbsoluteSize.Y / 2
				if petalCenterY > lowestY then
					lowestY = petalCenterY
					facingIndex = petalIndex
				end
			end
			local facingColorIndex = ring.quadrantColors[facingIndex]

			if not ring.checked and ring.y + RING_SIZE >= ballTop and ring.y <= ballBottom then
				ring.checked = true
				local mismatched = facingColorIndex ~= ballColorIndex
				if mismatched then
					if shieldCharges > 0 then
						-- A banked shield absorbs one wrong-color pass --
						-- still scores (this counts as a save, not a free
						-- pass), just skips the near-miss check below since
						-- there's nothing "close" about actually missing.
						shieldCharges -= 1
						flashScreen(SHIELD_COLOR, 0.7)
						GameShell.Ring(
							canvas,
							UDim2.fromOffset(centerX(), ring.y + RING_SIZE / 2),
							SHIELD_COLOR,
							api.reduceMotion,
							RING_SIZE * 0.85
						)
						api.sounds:Play("Success")
					else
						endGame()
						return
					end
				end
				local scoreMultiplier = if os.clock() < scoreMultiplierUntil then 2 else 1
				score += scoreMultiplier
				api.setScore(score)
				api.sounds:Play("Like")
				GameShell.Burst(
					canvas,
					ball.Position + UDim2.fromOffset(BALL_SIZE / 2, BALL_SIZE / 2),
					PALETTE_COLORS[ballColorIndex],
					api.reduceMotion
				)
				GameShell.Ring(
					canvas,
					UDim2.fromOffset(centerX(), ring.y + RING_SIZE / 2),
					PALETTE_COLORS[ballColorIndex],
					api.reduceMotion,
					RING_SIZE * 0.7
				)
				registerStreak()
				if not mismatched then
					-- How close the current rotation is to a petal boundary:
					-- a beat later or earlier at this spin speed and a
					-- different (likely wrong) color would have been facing
					-- the ball.
					local seamOffset = ring.rotation % 90
					local seamDistance = math.min(seamOffset, 90 - seamOffset)
					if seamDistance <= NEAR_MISS_SEAM_DEGREES then
						triggerNearMiss()
					end
				end
			end

			if ring.y > height() then
				ring.backing:Destroy()
				table.remove(rings, i)
			end
		end

		for i = #orbs, 1, -1 do
			local orb = orbs[i]
			orb.y += shift
			orb.frame.Position = UDim2.fromOffset(centerX() - ORB_SIZE / 2, orb.y)

			if not orb.collected and orb.y + ORB_SIZE >= ballTop and orb.y <= ballBottom then
				orb.collected = true
				local orbPosition = orb.frame.Position
				local effectColor: Color3
				if orb.kind == "COLOR" then
					local orbColorIndex = orb.colorIndex :: number
					setBallColor(orbColorIndex)
					api.sounds:Play("Hover")
					effectColor = PALETTE_COLORS[orbColorIndex]
				elseif orb.kind == "SHIELD" then
					shieldCharges = math.min(SHIELD_MAX_CHARGES, shieldCharges + 1)
					api.sounds:Play("Success")
					effectColor = SHIELD_COLOR
				else
					scoreMultiplierUntil = math.max(scoreMultiplierUntil, os.clock()) + MULTIPLIER_DURATION
					api.sounds:Play("Success")
					effectColor = MULTIPLIER_COLOR
				end
				GameShell.Burst(
					canvas,
					orbPosition + UDim2.fromOffset(ORB_SIZE / 2, ORB_SIZE / 2),
					effectColor,
					api.reduceMotion
				)
				GameShell.Ring(
					canvas,
					orbPosition + UDim2.fromOffset(ORB_SIZE / 2, ORB_SIZE / 2),
					effectColor,
					api.reduceMotion,
					10
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
		flashOverlay:Destroy()
		streakLabel:Destroy()
		statusLabel:Destroy()
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
