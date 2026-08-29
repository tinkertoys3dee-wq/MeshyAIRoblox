--!strict

-- Block Stacker: a block slides back and forth above the tower; tap/click/
-- space drops it. Perfect alignment (within a small tolerance) keeps the
-- full width and builds a combo; a partial landing trims the block down to
-- just the overlapping region and the trimmed-off pieces fall away as
-- debris. Missing entirely ends the run. Score is blocks successfully
-- landed, one point each, and the moving block speeds up with score the
-- same way DinoRunner's obstacle speed ramps with distance.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors

local ROW_HEIGHT = 26
local BLOCK_HEIGHT = 22
local TOP_Y = 64
local BASE_WIDTH_FRACTION = 0.62
local BASE_SPEED = 130
local SPEED_PER_BLOCK = 4
local MAX_SPEED = 360
local PERFECT_TOLERANCE = 5
-- Below this, an overlap is treated as a miss even though it's technically
-- nonzero -- a 1px sliver landing is not a satisfying "you made it".
local MIN_SURVIVABLE_WIDTH = 6
local COMBO_STREAK_WINDOW = 3 -- consecutive perfects before the combo label appears

type PlacedBlock = { frame: Frame, x: number, width: number }

local Game = {} :: GameShell.GameModule
Game.Name = "Block Stacker"
Game.Key = "BlockStacker"

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local score = 0
	local combo = 0

	local function widthPx(): number
		local w = math.floor(canvas.AbsoluteSize.X)
		return if w > 40 then w else 504
	end
	local function heightPx(): number
		local h = math.floor(canvas.AbsoluteSize.Y)
		return if h > 40 then h else 270
	end

	local canvasWidth = widthPx()
	local canvasHeight = heightPx()

	local backdrop = Factory.New("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = canvas,
	})
	Factory.Gradient(backdrop, { Colors.Ink, Colors.Panel }, 90)

	-- A soft glow behind the drop zone -- the same "spotlight" depth trick
	-- used throughout the Arcade -- so the row you're actually placing
	-- blocks into reads as the visual focus rather than just wherever the
	-- moving block happens to be.
	local dropGlow = Factory.Blob(canvas, 220, UDim2.new(), Colors.Gold, 0.92)
	dropGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	dropGlow.Position = UDim2.fromOffset(canvasWidth / 2, TOP_Y - ROW_HEIGHT / 2)

	-- A dark vignette at the bottom, where completed floors sink away as the
	-- tower rises -- reinforces "that part of the tower is behind you now"
	-- without needing any text to say so. Purely cosmetic, so it's skipped
	-- under reduceMotion like every other decoration here.
	if not api.reduceMotion then
		local vignette = Factory.New("Frame", {
			Name = "Vignette",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, math.floor(canvasHeight * 0.4)),
			BackgroundColor3 = Colors.Ink,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = canvas,
		})
		Factory.New("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0.35),
			}),
			Rotation = 90,
			Parent = vignette,
		})
	end

	-- A faint vertical guide beneath the drop zone -- purely a sight-line
	-- cue for lining the moving block up with the tower, so it's skipped
	-- under reduceMotion along with every other pure decoration here.
	if not api.reduceMotion then
		Factory.New("Frame", {
			Name = "DropGuide",
			Size = UDim2.new(0, 1, 0, ROW_HEIGHT * 2),
			Position = UDim2.fromOffset(0, TOP_Y - ROW_HEIGHT),
			BackgroundColor3 = Colors.Line,
			BackgroundTransparency = 0.85,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = canvas,
		})
	end

	local comboLabel = Factory.Label(canvas, "", UDim2.fromOffset(180, 26), {
		Name = "ComboLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		AlignX = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Black,
		TextSize = 15,
		Color = Colors.Gold,
		TextTransparency = 1,
		ZIndex = 8,
		Parent = canvas,
	})
	local comboFadeToken = 0

	-- A slow rainbow drift up the tower rather than one flat accent color --
	-- purely cosmetic (score/combo already carry the real information), and
	-- doubles as a free "how tall am I" readout since the hue never repeats
	-- within any one realistic run length.
	local function blockColor(height: number): Color3
		return Color3.fromHSV((height * 0.055) % 1, 0.55, 0.88)
	end

	local placed: { PlacedBlock } = {}
	local stackHeight = 0

	local baseWidth = math.floor(canvasWidth * BASE_WIDTH_FRACTION)
	local baseX = math.floor((canvasWidth - baseWidth) / 2)
	local baseFrame = Factory.New("Frame", {
		Name = "Block",
		Size = UDim2.fromOffset(baseWidth, BLOCK_HEIGHT),
		Position = UDim2.fromOffset(baseX, TOP_Y),
		BackgroundColor3 = blockColor(0),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = canvas,
	})
	Factory.Corner(baseFrame, 6)
	Factory.Stroke(baseFrame, Colors.Ink, 0.35, 1.5)
	table.insert(placed, { frame = baseFrame, x = baseX, width = baseWidth })

	local movingWidth = baseWidth
	local movingX = 0
	local movingDirection = 1
	local movingSpeed = BASE_SPEED
	local movingFrame: Frame? = nil

	local function spawnMovingBlock()
		local top = placed[#placed]
		movingWidth = top.width
		movingX = 0
		movingDirection = 1
		movingSpeed = math.min(MAX_SPEED, BASE_SPEED + score * SPEED_PER_BLOCK)
		local frame = Factory.New("Frame", {
			Name = "MovingBlock",
			Size = UDim2.fromOffset(movingWidth, BLOCK_HEIGHT),
			Position = UDim2.fromOffset(movingX, TOP_Y - ROW_HEIGHT),
			BackgroundColor3 = blockColor(stackHeight + 1),
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = canvas,
		})
		Factory.Corner(frame, 6)
		Factory.Stroke(frame, Colors.Ink, 0.35, 1.5)
		movingFrame = frame
	end
	spawnMovingBlock()

	local function spawnDebris(x: number, width: number)
		if api.reduceMotion or width < 2 then
			return
		end
		local debris = Factory.New("Frame", {
			Name = "Debris",
			Size = UDim2.fromOffset(width, BLOCK_HEIGHT),
			Position = UDim2.fromOffset(x, TOP_Y),
			BackgroundColor3 = blockColor(stackHeight + 1),
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = canvas,
		})
		Factory.Corner(debris, 4)
		local tween = TweenService:Create(debris, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = debris.Position + UDim2.fromOffset(math.random(-24, 24), 130 + math.random(0, 60)),
			Rotation = math.random(-45, 45),
			BackgroundTransparency = 1,
		})
		tween.Completed:Connect(function()
			debris:Destroy()
		end)
		tween:Play()
	end

	local function endGame()
		if not running then
			return
		end
		running = false
		local frame = movingFrame
		movingFrame = nil
		if frame then
			GameShell.Burst(
				canvas,
				frame.Position + UDim2.fromOffset(movingWidth / 2, BLOCK_HEIGHT / 2),
				Colors.Danger,
				api.reduceMotion
			)
			if api.reduceMotion then
				frame:Destroy()
			else
				local tween =
					TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
						Position = frame.Position + UDim2.fromOffset(0, 170),
						Rotation = math.random(-55, 55),
						BackgroundTransparency = 1,
					})
				tween.Completed:Connect(function()
					frame:Destroy()
				end)
				tween:Play()
			end
		end
		GameShell.Shake(canvas, api.reduceMotion)
		api.gameOver(score)
	end

	local function dropBlock()
		if not running or not movingFrame then
			return
		end
		local top = placed[#placed]
		local movingLeft = movingX
		local movingRight = movingX + movingWidth
		local topLeft = top.x
		local topRight = top.x + top.width
		local overlapLeft = math.max(movingLeft, topLeft)
		local overlapRight = math.min(movingRight, topRight)
		local overlapWidth = overlapRight - overlapLeft

		if overlapWidth < MIN_SURVIVABLE_WIDTH then
			endGame()
			return
		end

		local isPerfect = math.abs(overlapWidth - top.width) <= PERFECT_TOLERANCE
			and math.abs(overlapLeft - topLeft) <= PERFECT_TOLERANCE
		local finalWidth = if isPerfect then top.width else overlapWidth
		local finalX = if isPerfect then top.x else overlapLeft

		if not isPerfect then
			local leftDebrisWidth = overlapLeft - movingLeft
			local rightDebrisWidth = movingRight - overlapRight
			spawnDebris(movingLeft, leftDebrisWidth)
			spawnDebris(overlapRight, rightDebrisWidth)
		end

		if movingFrame then
			movingFrame:Destroy()
			movingFrame = nil
		end

		stackHeight += 1
		local landedFrame = Factory.New("Frame", {
			Name = "Block",
			Size = UDim2.fromOffset(finalWidth, BLOCK_HEIGHT),
			Position = UDim2.fromOffset(finalX, TOP_Y),
			BackgroundColor3 = blockColor(stackHeight),
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = canvas,
		})
		Factory.Corner(landedFrame, 6)
		Factory.Stroke(landedFrame, Colors.Ink, 0.35, 1.5)
		table.insert(placed, { frame = landedFrame, x = finalX, width = finalWidth })

		-- Shift every earlier block down by one row -- the camera "follows"
		-- the rising tower by keeping the current top pinned at TOP_Y and
		-- letting completed lower floors sink toward the bottom instead.
		for i = 1, #placed - 1 do
			local block = placed[i]
			block.frame.Position += UDim2.fromOffset(0, ROW_HEIGHT)
		end
		for i = #placed - 1, 1, -1 do
			if placed[i].frame.Position.Y.Offset > heightPx() + BLOCK_HEIGHT then
				placed[i].frame:Destroy()
				table.remove(placed, i)
			end
		end

		score += 1
		api.setScore(score)

		if isPerfect then
			combo += 1
			api.sounds:Play("Success")
			GameShell.Burst(
				canvas,
				UDim2.fromOffset(finalX + finalWidth / 2, TOP_Y + BLOCK_HEIGHT / 2),
				Colors.Gold,
				api.reduceMotion
			)
			GameShell.Ring(
				canvas,
				UDim2.fromOffset(finalX + finalWidth / 2, TOP_Y + BLOCK_HEIGHT / 2),
				Colors.Gold,
				api.reduceMotion,
				math.min(finalWidth, 60)
			)
			if not api.reduceMotion then
				landedFrame.BackgroundColor3 = Colors.Gold
				TweenService:Create(
					landedFrame,
					TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ BackgroundColor3 = blockColor(stackHeight) }
				):Play()
			end
			if combo >= COMBO_STREAK_WINDOW then
				comboLabel.Text = string.format("%dx PERFECT", combo)
				comboLabel.TextTransparency = 0
				comboFadeToken += 1
				local myToken = comboFadeToken
				if not api.reduceMotion then
					local pop = Factory.New("UIScale", { Scale = 1.3, Parent = comboLabel })
					TweenService
						:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
						:Play()
					task.delay(0.9, function()
						pop:Destroy()
					end)
				end
				task.delay(0.9, function()
					if myToken == comboFadeToken and comboLabel.Parent then
						if api.reduceMotion then
							comboLabel.TextTransparency = 1
						else
							TweenService:Create(comboLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
						end
					end
				end)
			end
		else
			combo = 0
			api.sounds:Play("Press")
		end

		spawnMovingBlock()
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
			dropBlock()
		end
	end)
	local tapConn = canvas.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dropBlock()
		end
	end)

	local heartbeatConn: RBXScriptConnection
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not running or not movingFrame then
			return
		end
		dt = math.min(dt, 1 / 20)
		movingX += movingSpeed * movingDirection * dt
		-- Live width, not the canvasWidth captured once at Game.Start -- a
		-- player resizing their window mid-run (unlike FlappyBird/DinoRunner/
		-- ColorSwitch, which all already re-read canvas.AbsoluteSize on every
		-- use) used to leave the moving block oscillating against bounds from
		-- whatever size the canvas happened to be when the game began.
		local maxX = math.max(0, widthPx() - movingWidth)
		if movingX <= 0 then
			movingX = 0
			movingDirection = 1
		elseif movingX >= maxX then
			movingX = maxX
			movingDirection = -1
		end
		movingFrame.Position = UDim2.fromOffset(movingX, TOP_Y - ROW_HEIGHT)
	end)

	return function()
		running = false
		heartbeatConn:Disconnect()
		inputConn:Disconnect()
		tapConn:Disconnect()
		backdrop:Destroy()
		dropGlow:Destroy()
		comboLabel:Destroy()
		if movingFrame then
			movingFrame:Destroy()
		end
		for _, block in placed do
			block.frame:Destroy()
		end
		table.clear(placed)
		for _, child in canvas:GetChildren() do
			if child.Name == "DropGuide" or child.Name == "Debris" or child.Name == "Vignette" then
				child:Destroy()
			end
		end
	end
end

return Game
