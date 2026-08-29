--!strict

-- Meteor Rush: a five-lane survival sprint. Move with A/D, arrows,
-- controller, swipe, tap a lane, or the on-screen buttons. Meteors end the
-- run, energy cores build an increasingly valuable collection combo, and a
-- rare shield absorbs one collision. Speed and wave density rise through
-- CRUISE, RUSH, and HYPER phases so every run has a clear escalation arc.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors

local LANE_COUNT = 5
local PLAYFIELD_MARGIN = 34
local SHIP_SIZE = 34
local BASE_FALL_SPEED = 190
local MAX_FALL_SPEED = 440
local SPEED_PER_SECOND = 5.4
local BASE_WAVE_INTERVAL = 0.96
local MIN_WAVE_INTERVAL = 0.46
local WAVE_INTERVAL_STEP = 0.011
local DISTANCE_SCORE_PER_SECOND = 7
local CORE_BASE_SCORE = 7
local CORE_COMBO_BONUS = 2
local CORE_MAX_COMBO_BONUS = 12
local SHIELD_SCORE = 12
local DEFLECT_SCORE = 18
local NEAR_MISS_SCORE = 2
local SWIPE_MIN_DISTANCE = 18

type FallingObject = {
	frame: Frame,
	kind: string,
	lane: number,
	y: number,
	size: number,
	rotationSpeed: number,
	passedShip: boolean,
}

type Star = { frame: Frame, x: number, y: number, speed: number }

local Game = {} :: GameShell.GameModule
Game.Name = "Meteor Rush"
Game.Key = "MeteorRush"

local function shuffledLanes(): { number }
	local lanes = { 1, 2, 3, 4, 5 }
	for index = #lanes, 2, -1 do
		local swapIndex = math.random(1, index)
		lanes[index], lanes[swapIndex] = lanes[swapIndex], lanes[index]
	end
	return lanes
end

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local elapsed = 0
	local bonusScore = 0
	local score = 0
	local displayedScore = -1
	local coreCombo = 0
	local shipLane = math.ceil(LANE_COUNT / 2)
	local shielded = false
	local timeSinceWave = BASE_WAVE_INTERVAL * 0.55
	local objects: { FallingObject } = {}
	local stars: { Star } = {}
	local swipeStart: Vector2? = nil
	local shipTween: Tween? = nil

	local function widthPx(): number
		local width = math.floor(canvas.AbsoluteSize.X)
		return if width > 100 then width else 504
	end

	local function heightPx(): number
		local height = math.floor(canvas.AbsoluteSize.Y)
		return if height > 100 then height else 300
	end

	local function laneWidth(): number
		return math.max(34, (widthPx() - PLAYFIELD_MARGIN * 2) / LANE_COUNT)
	end

	local function laneX(lane: number): number
		return PLAYFIELD_MARGIN + (lane - 0.5) * laneWidth()
	end

	local function shipY(): number
		return heightPx() - 48
	end

	local root = Factory.New("Frame", {
		Name = "MeteorRushRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(7, 11, 30),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
		ZIndex = 1,
		Parent = canvas,
	})
	Factory.Gradient(root, {
		Color3.fromRGB(27, 17, 62),
		Color3.fromRGB(10, 21, 52),
		Color3.fromRGB(5, 10, 25),
	}, 155)

	local nebulaLeft = Factory.Blob(root, 300, UDim2.fromOffset(-150, -85), Colors.Violet, 0.82)
	nebulaLeft.ZIndex = 1
	local nebulaRight = Factory.Blob(root, 250, UDim2.new(1, -105, 0.55, 0), Colors.Cyan, 0.91)
	nebulaRight.ZIndex = 1

	-- A distant planet and rings provide a recognizable silhouette behind the
	-- playfield without competing with lane hazards in the foreground.
	local planet = Factory.New("Frame", {
		Name = "Planet",
		Size = UDim2.fromOffset(76, 76),
		Position = UDim2.new(1, -104, 0, 30),
		BackgroundColor3 = Color3.fromRGB(111, 77, 189),
		BackgroundTransparency = 0.34,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = root,
	})
	Factory.Corner(planet, 38)
	Factory.Gradient(planet, { Color3.fromRGB(189, 117, 225), Color3.fromRGB(60, 55, 143) }, 135)
	local planetRing = Factory.New("Frame", {
		Name = "PlanetRing",
		Size = UDim2.fromOffset(112, 10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Rotation = -16,
		BackgroundColor3 = Colors.Cyan,
		BackgroundTransparency = 0.58,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = planet,
	})
	Factory.Corner(planetRing, 5)

	for lane = 1, LANE_COUNT - 1 do
		Factory.New("Frame", {
			Name = "LaneGuide",
			Size = UDim2.new(0, 1, 1, -24),
			Position = UDim2.fromOffset(PLAYFIELD_MARGIN + lane * laneWidth(), 12),
			BackgroundColor3 = Colors.Cyan,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = root,
		})
	end

	local starCount = if api.reduceMotion then 14 else 24
	for index = 1, starCount do
		local size = if index % 7 == 0 then 3 else 2
		local x = math.random(8, math.max(9, widthPx() - 8))
		local y = math.random(4, math.max(5, heightPx() - 4))
		local star = Factory.New("Frame", {
			Name = "Star",
			Size = UDim2.fromOffset(size, if api.reduceMotion then size else size * (1 + index % 3)),
			Position = UDim2.fromOffset(x, y),
			BackgroundColor3 = if index % 5 == 0 then Colors.Cyan else Color3.new(1, 1, 1),
			BackgroundTransparency = 0.35 + (index % 4) * 0.12,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = root,
		})
		Factory.Corner(star, 2)
		table.insert(stars, { frame = star, x = x, y = y, speed = 28 + (index % 6) * 12 })
	end

	local stageLabel = Factory.Label(root, "CRUISE", UDim2.fromOffset(136, 24), {
		Name = "StageLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		AlignX = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Black,
		TextSize = 13,
		Color = Colors.Cyan,
		ZIndex = 14,
	})
	Factory.New("UIStroke", { Color = Colors.Ink, Thickness = 2, Transparency = 0.35, Parent = stageLabel })

	local comboLabel = Factory.Label(root, "", UDim2.fromOffset(160, 22), {
		Name = "ComboLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 31),
		AlignX = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Black,
		TextSize = 13,
		Color = Colors.Gold,
		Transparency = 1,
		ZIndex = 14,
	})
	Factory.New("UIStroke", { Color = Colors.Ink, Thickness = 2, Transparency = 0.35, Parent = comboLabel })

	local controlHint = Factory.Label(root, "A / D  ·  SWIPE OR TAP A LANE", UDim2.new(1, -28, 0, 18), {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -8),
		AlignX = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Bold,
		TextSize = 9,
		Color = Colors.TextMuted,
		Transparency = 0.15,
		ZIndex = 5,
	})

	local flashOverlay = Factory.New("Frame", {
		Name = "FlashOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Cyan,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 24,
		Parent = root,
	})

	local function flash(color: Color3, transparency: number)
		if api.reduceMotion then
			return
		end
		flashOverlay.BackgroundColor3 = color
		flashOverlay.BackgroundTransparency = transparency
		TweenService:Create(flashOverlay, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
	end

	local shipGroup = Factory.New("Frame", {
		Name = "ShipGroup",
		Size = UDim2.fromOffset(50, 52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(laneX(shipLane), shipY()),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = root,
	})
	local shipGlow = Factory.New("Frame", {
		Name = "ShipGlow",
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Colors.Cyan,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		ZIndex = 9,
		Parent = shipGroup,
	})
	Factory.Corner(shipGlow, 24)
	local shieldRing = Factory.New("Frame", {
		Name = "ShieldRing",
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 12,
		Parent = shipGroup,
	})
	Factory.Corner(shieldRing, 24)
	local shieldStroke = Factory.Stroke(shieldRing, Colors.Gold, 0.12, 3)

	local ship = Factory.New("Frame", {
		Name = "Ship",
		Size = UDim2.fromOffset(SHIP_SIZE, 26),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		BackgroundColor3 = Colors.Cyan,
		BorderSizePixel = 0,
		ZIndex = 11,
		Parent = shipGroup,
	})
	Factory.Corner(ship, 8)
	Factory.Stroke(ship, Color3.fromRGB(197, 251, 255), 0.15, 1.5)
	Factory.Gradient(ship, { Color3.fromRGB(196, 250, 255), Colors.Cyan, Color3.fromRGB(45, 121, 214) }, 120)
	local nose = Factory.New("Frame", {
		Name = "Nose",
		Size = UDim2.fromOffset(19, 19),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, -2),
		Rotation = 45,
		BackgroundColor3 = Color3.fromRGB(170, 246, 255),
		BorderSizePixel = 0,
		ZIndex = 11,
		Parent = ship,
	})
	Factory.Corner(nose, 5)
	local cockpit = Factory.New("Frame", {
		Name = "Cockpit",
		Size = UDim2.fromOffset(10, 12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		BackgroundColor3 = Colors.Violet,
		BorderSizePixel = 0,
		ZIndex = 13,
		Parent = ship,
	})
	Factory.Corner(cockpit, 5)
	for _, side in { -1, 1 } do
		local wing = Factory.New("Frame", {
			Name = "Wing",
			Size = UDim2.fromOffset(13, 9),
			Position = UDim2.new(if side < 0 then 0 else 1, if side < 0 then -8 else -5, 1, -8),
			Rotation = side * 18,
			BackgroundColor3 = Color3.fromRGB(70, 142, 230),
			BorderSizePixel = 0,
			ZIndex = 10,
			Parent = ship,
		})
		Factory.Corner(wing, 4)
	end
	local thruster = Factory.New("Frame", {
		Name = "Thruster",
		Size = UDim2.fromOffset(10, 15),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -1),
		BackgroundColor3 = Colors.Gold,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = ship,
	})
	Factory.Corner(thruster, 5)
	if not api.reduceMotion then
		TweenService:Create(
			thruster,
			TweenInfo.new(0.14, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Size = UDim2.fromOffset(7, 23), BackgroundTransparency = 0.34 }
		):Play()
		TweenService:Create(
			shipGlow,
			TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Size = UDim2.fromOffset(58, 58), BackgroundTransparency = 0.82 }
		):Play()
		TweenService:Create(
			shieldStroke,
			TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.5 }
		):Play()
	end

	local function showPopup(text: string, color: Color3, position: UDim2)
		if api.reduceMotion then
			return
		end
		local popup = Factory.Label(root, text, UDim2.fromOffset(130, 22), {
			Name = "ScorePopup",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = position,
			AlignX = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Black,
			TextSize = 14,
			Color = color,
			ZIndex = 18,
		})
		Factory.New("UIStroke", { Color = Colors.Ink, Thickness = 2, Transparency = 0.35, Parent = popup })
		local tween = TweenService:Create(popup, TweenInfo.new(0.58, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = position - UDim2.fromOffset(0, 34),
			TextTransparency = 1,
		})
		tween.Completed:Connect(function()
			if popup.Parent then
				popup:Destroy()
			end
		end)
		tween:Play()
	end

	local function setShipLane(nextLane: number)
		if not running then
			return
		end
		nextLane = math.clamp(nextLane, 1, LANE_COUNT)
		if nextLane == shipLane then
			return
		end
		shipLane = nextLane
		api.sounds:Play("Press")
		if shipTween then
			shipTween:Cancel()
		end
		local target = UDim2.fromOffset(laneX(shipLane), shipY())
		if api.reduceMotion then
			shipGroup.Position = target
		else
			shipTween = TweenService:Create(
				shipGroup,
				TweenInfo.new(0.13, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = target }
			)
			shipTween:Play()
		end
	end

	local function spawnMeteor(lane: number)
		local size = math.random(32, 44)
		local frame = Factory.New("Frame", {
			Name = "Meteor",
			Size = UDim2.fromOffset(size, size),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(laneX(lane), -size),
			Rotation = math.random(0, 359),
			BackgroundColor3 = Color3.fromRGB(224, 91, 70),
			BorderSizePixel = 0,
			ZIndex = 8,
			Parent = root,
		})
		Factory.Corner(frame, math.floor(size * 0.43))
		Factory.Stroke(frame, Color3.fromRGB(255, 183, 85), 0.28, 2)
		Factory.Gradient(frame, {
			Color3.fromRGB(255, 172, 82),
			Color3.fromRGB(205, 76, 72),
			Color3.fromRGB(91, 45, 68),
		}, 135)
		for craterIndex = 1, 3 do
			local craterSize = math.max(4, math.floor(size * (0.1 + craterIndex * 0.025)))
			local crater = Factory.New("Frame", {
				Name = "Crater",
				Size = UDim2.fromOffset(craterSize, craterSize),
				Position = UDim2.new(0.14 + craterIndex * 0.18, 0, 0.16 + (craterIndex % 2) * 0.34, 0),
				BackgroundColor3 = Color3.fromRGB(92, 46, 67),
				BackgroundTransparency = 0.18,
				BorderSizePixel = 0,
				ZIndex = 9,
				Parent = frame,
			})
			Factory.Corner(crater, craterSize / 2)
		end
		table.insert(objects, {
			frame = frame,
			kind = "METEOR",
			lane = lane,
			y = -size,
			size = size,
			rotationSpeed = math.random(-115, 115),
			passedShip = false,
		})
	end

	local function spawnPickup(lane: number, kind: string)
		local isShield = kind == "SHIELD"
		local size = if isShield then 27 else 22
		local color = if isShield then Colors.Gold else Colors.Cyan
		local frame = Factory.New("Frame", {
			Name = if isShield then "Shield" else "Core",
			Size = UDim2.fromOffset(size, size),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(laneX(lane), -size),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 9,
			Parent = root,
		})
		Factory.Corner(frame, if isShield then 8 else size / 2)
		Factory.Stroke(frame, Color3.new(1, 1, 1), 0.2, 2)
		Factory.Gradient(frame, { Color3.new(1, 1, 1), color, if isShield then Colors.Rose else Colors.Violet }, 135)
		Factory.Label(frame, if isShield then "◇" else "◆", UDim2.fromScale(1, 1), {
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			Font = Theme.Fonts.Black,
			TextSize = if isShield then 17 else 12,
			Color = Colors.Ink,
			ZIndex = 10,
		})
		if not api.reduceMotion then
			local scale = Factory.New("UIScale", { Scale = 1, Parent = frame })
			TweenService:Create(
				scale,
				TweenInfo.new(0.42, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.2 }
			):Play()
		end
		table.insert(objects, {
			frame = frame,
			kind = kind,
			lane = lane,
			y = -size,
			size = size,
			rotationSpeed = if isShield then 55 else -70,
			passedShip = false,
		})
	end

	local function spawnWave()
		local lanes = shuffledLanes()
		local meteorCount: number
		if elapsed < 10 then
			meteorCount = 1
		elseif elapsed < 26 then
			meteorCount = math.random(1, 2)
		else
			meteorCount = math.random(2, 3)
		end
		for index = 1, meteorCount do
			spawnMeteor(lanes[index])
		end

		local safeCount = LANE_COUNT - meteorCount
		if safeCount > 0 and math.random() < 0.8 then
			local pickupLane = lanes[meteorCount + math.random(1, safeCount)]
			local offerShield = not shielded and elapsed >= 7 and math.random() < 0.1
			spawnPickup(pickupLane, if offerShield then "SHIELD" else "CORE")
		end
	end

	local function endGame()
		if not running then
			return
		end
		running = false
		GameShell.Shake(canvas, api.reduceMotion)
		GameShell.Burst(root, shipGroup.Position, Colors.Danger, api.reduceMotion)
		flash(Colors.Danger, 0.68)
		api.gameOver(score)
	end

	local function collectCore(object: FallingObject)
		coreCombo += 1
		local amount = CORE_BASE_SCORE + math.min(CORE_MAX_COMBO_BONUS, (coreCombo - 1) * CORE_COMBO_BONUS)
		bonusScore += amount
		api.sounds:Play(if coreCombo % 5 == 0 then "Success" else "Like")
		GameShell.Burst(root, object.frame.Position, Colors.Cyan, api.reduceMotion)
		GameShell.Ring(root, object.frame.Position, Colors.Cyan, api.reduceMotion, 20)
		showPopup(string.format("+%d  ·  x%d CORE", amount, coreCombo), Colors.Cyan, object.frame.Position)
		comboLabel.Text = string.format("ENERGY CHAIN x%d", coreCombo)
		comboLabel.TextTransparency = 0
		if coreCombo % 5 == 0 then
			flash(Colors.Cyan, 0.78)
			GameShell.Shake(canvas, api.reduceMotion, 0.35)
		end
	end

	local function collectShield(object: FallingObject)
		shielded = true
		shieldRing.Visible = true
		bonusScore += SHIELD_SCORE
		api.sounds:Play("Success")
		GameShell.Burst(root, object.frame.Position, Colors.Gold, api.reduceMotion)
		GameShell.Ring(root, shipGroup.Position, Colors.Gold, api.reduceMotion, 30)
		showPopup("SHIELD READY  +12", Colors.Gold, object.frame.Position)
		flash(Colors.Gold, 0.82)
	end

	local function deflectMeteor(object: FallingObject)
		shielded = false
		shieldRing.Visible = false
		bonusScore += DEFLECT_SCORE
		api.sounds:Play("Success")
		GameShell.Burst(root, object.frame.Position, Colors.Gold, api.reduceMotion)
		GameShell.Ring(root, shipGroup.Position, Colors.Gold, api.reduceMotion, 34)
		showPopup("DEFLECTED  +18", Colors.Gold, object.frame.Position)
		flash(Colors.Gold, 0.7)
		GameShell.Shake(canvas, api.reduceMotion, 0.5)
	end

	local leftButton = Factory.New("TextButton", {
		Name = "MoveLeft",
		Size = UDim2.fromOffset(44, 38),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 9, 1, -7),
		BackgroundColor3 = Colors.PanelSoft,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "◀",
		TextColor3 = Colors.Text,
		Font = Theme.Fonts.Black,
		TextSize = 16,
		ZIndex = 13,
		Parent = root,
	})
	Factory.Corner(leftButton, 12)
	Factory.Stroke(leftButton, Colors.Cyan, 0.55, 1)
	api.sounds:Bind(leftButton)
	leftButton.Activated:Connect(function()
		setShipLane(shipLane - 1)
	end)
	local rightButton = Factory.New("TextButton", {
		Name = "MoveRight",
		Size = UDim2.fromOffset(44, 38),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -9, 1, -7),
		BackgroundColor3 = Colors.PanelSoft,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "▶",
		TextColor3 = Colors.Text,
		Font = Theme.Fonts.Black,
		TextSize = 16,
		ZIndex = 13,
		Parent = root,
	})
	Factory.Corner(rightButton, 12)
	Factory.Stroke(rightButton, Colors.Cyan, 0.55, 1)
	api.sounds:Bind(rightButton)
	rightButton.Activated:Connect(function()
		setShipLane(shipLane + 1)
	end)

	local inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not running then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Left or key == Enum.KeyCode.A or key == Enum.KeyCode.DPadLeft then
			setShipLane(shipLane - 1)
		elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.D or key == Enum.KeyCode.DPadRight then
			setShipLane(shipLane + 1)
		end
	end)

	local pointerBegan = canvas.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			local localX = input.Position.X - canvas.AbsolutePosition.X
			local localY = input.Position.Y - canvas.AbsolutePosition.Y
			-- The visible arrow buttons already handle their own Activated
			-- event. Do not reinterpret the same short press as a tap on lane
			-- one/five when Gui input also reaches the canvas underneath.
			if localY >= heightPx() - 54 and (localX <= 62 or localX >= widthPx() - 62) then
				swipeStart = nil
				return
			end
			swipeStart = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	local pointerEnded = canvas.InputEnded:Connect(function(input)
		if
			input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1
		then
			return
		end
		local start = swipeStart
		swipeStart = nil
		if not start then
			return
		end
		local finish = Vector2.new(input.Position.X, input.Position.Y)
		local delta = finish - start
		if math.abs(delta.X) >= SWIPE_MIN_DISTANCE and math.abs(delta.X) > math.abs(delta.Y) then
			setShipLane(shipLane + if delta.X > 0 then 1 else -1)
			return
		end
		local localX = finish.X - canvas.AbsolutePosition.X
		local tappedLane = math.clamp(math.floor((localX - PLAYFIELD_MARGIN) / laneWidth()) + 1, 1, LANE_COUNT)
		setShipLane(tappedLane)
	end)

	local currentStage = "CRUISE"
	local heartbeatConnection: RBXScriptConnection
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		dt = math.min(dt, 1 / 20)
		elapsed += dt

		local stage = if elapsed < 12 then "CRUISE" elseif elapsed < 28 then "RUSH" else "HYPER"
		if stage ~= currentStage then
			currentStage = stage
			stageLabel.Text = stage
			stageLabel.TextColor3 = if stage == "RUSH"
				then Colors.Gold
				else if stage == "HYPER" then Colors.Rose else Colors.Cyan
			api.sounds:Play("Success")
			flash(stageLabel.TextColor3, 0.8)
			GameShell.Ring(root, UDim2.fromOffset(widthPx() / 2, 22), stageLabel.TextColor3, api.reduceMotion, 30)
		end

		local fallSpeed = math.min(MAX_FALL_SPEED, BASE_FALL_SPEED + elapsed * SPEED_PER_SECOND)
		local waveInterval = math.max(MIN_WAVE_INTERVAL, BASE_WAVE_INTERVAL - elapsed * WAVE_INTERVAL_STEP)
		timeSinceWave += dt
		if timeSinceWave >= waveInterval then
			timeSinceWave -= waveInterval
			spawnWave()
		end

		if not api.reduceMotion then
			for _, star in stars do
				star.y += (star.speed + fallSpeed * 0.12) * dt
				if star.y > heightPx() + 8 then
					star.y = -8
					star.x = math.random(8, math.max(9, widthPx() - 8))
				end
				star.frame.Position = UDim2.fromOffset(star.x, star.y)
			end
		end

		for index = #objects, 1, -1 do
			local object = objects[index]
			object.y += fallSpeed * dt
			object.frame.Position = UDim2.fromOffset(laneX(object.lane), object.y)
			if not api.reduceMotion then
				object.frame.Rotation += object.rotationSpeed * dt
			end

			local inCollisionBand = math.abs(object.y - shipY()) <= (object.size + SHIP_SIZE) * 0.43
			if inCollisionBand and object.lane == shipLane then
				if object.kind == "METEOR" then
					if shielded then
						deflectMeteor(object)
						object.frame:Destroy()
						table.remove(objects, index)
					else
						endGame()
						return
					end
				elseif object.kind == "CORE" then
					collectCore(object)
					object.frame:Destroy()
					table.remove(objects, index)
				else
					collectShield(object)
					object.frame:Destroy()
					table.remove(objects, index)
				end
			elseif not object.passedShip and object.y > shipY() + object.size * 0.55 then
				object.passedShip = true
				if object.kind == "METEOR" and math.abs(object.lane - shipLane) == 1 then
					bonusScore += NEAR_MISS_SCORE
					showPopup("NEAR MISS  +2", Colors.Mint, UDim2.fromOffset(laneX(object.lane), shipY()))
				elseif object.kind == "CORE" then
					coreCombo = 0
					comboLabel.TextTransparency = 1
				end
			end

			if object.y > heightPx() + object.size then
				object.frame:Destroy()
				table.remove(objects, index)
			end
		end

		score = math.floor(elapsed * DISTANCE_SCORE_PER_SECOND) + bonusScore
		if score ~= displayedScore then
			displayedScore = score
			api.setScore(score)
		end
	end)

	return function()
		running = false
		heartbeatConnection:Disconnect()
		inputConnection:Disconnect()
		pointerBegan:Disconnect()
		pointerEnded:Disconnect()
		if shipTween then
			shipTween:Cancel()
		end
		table.clear(objects)
		table.clear(stars)
		root:Destroy()
	end
end

return Game
