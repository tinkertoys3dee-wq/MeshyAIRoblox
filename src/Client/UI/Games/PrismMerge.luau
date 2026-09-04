--!strict

-- Prism Merge: slide every prism on a 4x4 board with swipe, keyboard,
-- controller, or the on-screen direction buttons. Equal prisms combine once
-- per move; every merge adds the resulting value to the score. Consecutive
-- scoring moves build a visible chain, while the board's increasing color
-- intensity gives a long run a clear visual arc without adding a separate
-- difficulty selector.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors

local GRID_SIZE = 4
local CELL_COUNT = GRID_SIZE * GRID_SIZE
local BOARD_GAP = 7
local BOARD_PADDING = 9
local SWIPE_MIN_DISTANCE = 18
local INPUT_LOCK_SECONDS = 0.1

type MergeResult = { value: number, merged: boolean }

local Game = {} :: GameShell.GameModule
Game.Name = "Prism Merge"
Game.Key = "PrismMerge"

local PRISM_COLORS: { [number]: Color3 } = {
	[2] = Color3.fromRGB(104, 96, 178),
	[4] = Color3.fromRGB(76, 148, 199),
	[8] = Color3.fromRGB(52, 202, 220),
	[16] = Color3.fromRGB(70, 229, 170),
	[32] = Color3.fromRGB(167, 224, 83),
	[64] = Color3.fromRGB(255, 196, 82),
	[128] = Color3.fromRGB(255, 143, 75),
	[256] = Color3.fromRGB(255, 91, 151),
	[512] = Color3.fromRGB(198, 92, 255),
	[1024] = Color3.fromRGB(135, 94, 255),
	[2048] = Color3.fromRGB(255, 228, 132),
}

local function lighten(color: Color3, amount: number): Color3
	local hue, saturation, value = color:ToHSV()
	return Color3.fromHSV(hue, saturation, math.clamp(value + amount, 0, 1))
end

local function darken(color: Color3, amount: number): Color3
	local hue, saturation, value = color:ToHSV()
	return Color3.fromHSV(hue, saturation, math.clamp(value - amount, 0, 1))
end

local function prismColor(value: number): Color3
	local configured = PRISM_COLORS[value]
	if configured then
		return configured
	end
	local exponent = math.floor(math.log(value) / math.log(2))
	return Color3.fromHSV((0.74 + exponent * 0.073) % 1, 0.64, 1)
end

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local inputLocked = false
	local score = 0
	local chain = 0
	local board: { number } = table.create(CELL_COUNT, 0)
	local swipeStart: Vector2? = nil

	local function widthPx(): number
		local width = math.floor(canvas.AbsoluteSize.X)
		return if width > 80 then width else 504
	end

	local function heightPx(): number
		local height = math.floor(canvas.AbsoluteSize.Y)
		return if height > 100 then height else 300
	end

	local root = Factory.New("Frame", {
		Name = "PrismMergeRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 22, 46),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
		ZIndex = 1,
		Parent = canvas,
	})
	Factory.Gradient(root, {
		Color3.fromRGB(42, 32, 82),
		Color3.fromRGB(18, 23, 49),
		Color3.fromRGB(13, 34, 55),
	}, 125)

	local leftGlow = Factory.Blob(root, 250, UDim2.fromOffset(-100, -70), Colors.Violet, 0.84)
	leftGlow.ZIndex = 1
	local rightGlow = Factory.Blob(root, 210, UDim2.new(1, -90, 1, -130), Colors.Cyan, 0.9)
	rightGlow.ZIndex = 1

	-- Faceted background marks keep the empty parts of the canvas visually
	-- tied to the prism theme. Static even with motion enabled, so they remain
	-- accessibility-safe decoration.
	for index = 1, 9 do
		local facet = Factory.New("Frame", {
			Name = "Facet",
			Size = UDim2.fromOffset(12 + index % 3 * 7, 12 + index % 3 * 7),
			Position = UDim2.new((index * 0.173) % 0.94, 0, (index * 0.287) % 0.9, 0),
			Rotation = 45,
			BackgroundColor3 = if index % 2 == 0 then Colors.Cyan else Colors.Violet,
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = root,
		})
		Factory.Corner(facet, 4)
	end

	local instruction = Factory.Label(root, "SWIPE · WASD · ARROWS", UDim2.new(1, -24, 0, 22), {
		Position = UDim2.fromOffset(12, 8),
		AlignX = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Bold,
		TextSize = 10,
		Color = Colors.TextMuted,
		ZIndex = 4,
	})
	Factory.New("UIStroke", { Color = Colors.Ink, Thickness = 1, Transparency = 0.5, Parent = instruction })

	local chainLabel = Factory.Label(root, "", UDim2.fromOffset(190, 28), {
		Name = "ChainLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 25),
		AlignX = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Black,
		TextSize = 15,
		Color = Colors.Gold,
		Transparency = 1,
		ZIndex = 15,
	})
	Factory.New("UIStroke", { Color = Colors.Ink, Thickness = 2, Transparency = 0.35, Parent = chainLabel })

	local availableBoardHeight = math.max(170, heightPx() - 92)
	local boardSize = math.max(170, math.min(widthPx() - 34, availableBoardHeight, 340))
	local boardX = math.floor((widthPx() - boardSize) / 2)
	local boardY = 43 + math.floor((availableBoardHeight - boardSize) / 2)
	local cellSize = math.floor((boardSize - BOARD_PADDING * 2 - BOARD_GAP * (GRID_SIZE - 1)) / GRID_SIZE)
	boardSize = cellSize * GRID_SIZE + BOARD_GAP * (GRID_SIZE - 1) + BOARD_PADDING * 2
	boardX = math.floor((widthPx() - boardSize) / 2)

	local boardShadow = Factory.New("Frame", {
		Name = "BoardShadow",
		Size = UDim2.fromOffset(boardSize + 8, boardSize + 8),
		Position = UDim2.fromOffset(boardX - 4, boardY + 5),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.38,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = root,
	})
	Factory.Corner(boardShadow, 19)

	local boardFrame = Factory.New("Frame", {
		Name = "Board",
		Size = UDim2.fromOffset(boardSize, boardSize),
		Position = UDim2.fromOffset(boardX, boardY),
		BackgroundColor3 = Color3.fromRGB(31, 35, 67),
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = root,
	})
	Factory.Corner(boardFrame, 17)
	Factory.Stroke(boardFrame, Colors.Violet, 0.4, 2)
	Factory.Gradient(boardFrame, { Color3.fromRGB(51, 32, 94), Color3.fromRGB(26, 16, 53) }, 125)

	local function cellPosition(index: number): UDim2
		local zeroIndex = index - 1
		local column = zeroIndex % GRID_SIZE
		local row = math.floor(zeroIndex / GRID_SIZE)
		return UDim2.fromOffset(
			BOARD_PADDING + column * (cellSize + BOARD_GAP),
			BOARD_PADDING + row * (cellSize + BOARD_GAP)
		)
	end

	for index = 1, CELL_COUNT do
		local slot = Factory.New("Frame", {
			Name = "Slot",
			Size = UDim2.fromOffset(cellSize, cellSize),
			Position = cellPosition(index),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.47,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = boardFrame,
		})
		Factory.Corner(slot, math.max(7, math.floor(cellSize * 0.14)))
		Factory.Stroke(slot, Colors.Line, 0.82, 1)
	end

	local tileLayer = Factory.New("Frame", {
		Name = "Tiles",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = boardFrame,
	})

	local highestPill = Factory.ImagePill(root, "HIGHEST · 2", Colors.Cyan, 104)
	highestPill.Name = "HighestPill"
	highestPill.Position = UDim2.fromOffset(10, 8)
	highestPill.ZIndex = 6
	local highestLabel = highestPill :: TextLabel

	local flashOverlay = Factory.New("Frame", {
		Name = "FlashOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Gold,
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
		TweenService:Create(flashOverlay, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
	end

	local chainToken = 0
	local function showChain(mergeCount: number, gained: number)
		chainToken += 1
		local thisToken = chainToken
		if mergeCount >= 2 then
			chainLabel.Text = string.format("CASCADE x%d  ·  +%d", mergeCount, gained)
		elseif chain >= 2 then
			chainLabel.Text = string.format("%dx CHAIN  ·  +%d", chain, gained)
		else
			chainLabel.Text = string.format("MERGE  +%d", gained)
		end
		chainLabel.TextTransparency = 0
		if not api.reduceMotion then
			local scale = Factory.New("UIScale", { Scale = 1.32, Parent = chainLabel })
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
			task.delay(0.6, function()
				if scale.Parent then
					scale:Destroy()
				end
			end)
		end
		task.delay(1.15, function()
			if thisToken == chainToken and chainLabel.Parent then
				if api.reduceMotion then
					chainLabel.TextTransparency = 1
				else
					TweenService:Create(chainLabel, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
				end
			end
		end)
	end

	local function renderBoard(spawnedIndex: number?, mergedTargets: { number }?)
		for _, child in tileLayer:GetChildren() do
			child:Destroy()
		end
		local mergedLookup: { [number]: boolean } = {}
		for _, target in mergedTargets or {} do
			mergedLookup[target] = true
		end
		local highest = 2
		for index, value in board do
			if value <= 0 then
				continue
			end
			highest = math.max(highest, value)
			local position = cellPosition(index)
			local color = prismColor(value)
			local shadow = Factory.New("Frame", {
				Name = "TileShadow",
				Size = UDim2.fromOffset(cellSize, cellSize),
				Position = position + UDim2.fromOffset(0, 3),
				BackgroundColor3 = Colors.Ink,
				BackgroundTransparency = 0.42,
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = tileLayer,
			})
			Factory.Corner(shadow, math.max(7, math.floor(cellSize * 0.14)))
			local tile = Factory.New("Frame", {
				Name = "Prism",
				Size = UDim2.fromOffset(cellSize, cellSize),
				Position = position,
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = 6,
				Parent = tileLayer,
			})
			Factory.Corner(tile, math.max(7, math.floor(cellSize * 0.14)))
			Factory.Stroke(tile, lighten(color, 0.22), 0.18, 1.5)
			Factory.Gradient(tile, { lighten(color, 0.15), color, darken(color, 0.16) }, 135)
			local gloss = Factory.New("Frame", {
				Name = "FacetGloss",
				Size = UDim2.new(1, -4, 0.42, 0),
				Position = UDim2.fromOffset(2, 2),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.82,
				BorderSizePixel = 0,
				ZIndex = 7,
				Parent = tile,
			})
			Factory.Corner(gloss, math.max(6, math.floor(cellSize * 0.12)))
			Factory.Label(tile, "◆", UDim2.fromOffset(16, 16), {
				Position = UDim2.fromOffset(5, 4),
				Color = Color3.new(1, 1, 1),
				Transparency = 0.36,
				TextSize = math.max(8, math.floor(cellSize * 0.15)),
				ZIndex = 8,
			})
			local valueText = tostring(value)
			Factory.Label(tile, valueText, UDim2.fromScale(1, 1), {
				AlignX = Enum.TextXAlignment.Center,
				AlignY = Enum.TextYAlignment.Center,
				Font = Theme.Fonts.Black,
				TextSize = math.max(12, math.floor(cellSize * (if #valueText >= 5 then 0.25 else 0.31))),
				Color = if value >= 64 then Colors.Ink else Colors.Text,
				ZIndex = 8,
			})

			if not api.reduceMotion and (index == spawnedIndex or mergedLookup[index]) then
				local scale = Factory.New("UIScale", {
					Scale = if mergedLookup[index] then 1.25 else 0.2,
					Parent = tile,
				})
				TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				}):Play()
			end
		end
		highestLabel.Text = string.format("HIGHEST · %d", highest)
	end

	local function emptyCells(): { number }
		local empty: { number } = {}
		for index, value in board do
			if value == 0 then
				table.insert(empty, index)
			end
		end
		return empty
	end

	local function spawnPrism(): number?
		local empty = emptyCells()
		if #empty == 0 then
			return nil
		end
		local index = empty[math.random(1, #empty)]
		board[index] = if math.random() < 0.9 then 2 else 4
		return index
	end

	local function lineIndices(direction: string, line: number): { number }
		local indices: { number } = {}
		for step = 1, GRID_SIZE do
			local row: number
			local column: number
			if direction == "LEFT" then
				row, column = line, step
			elseif direction == "RIGHT" then
				row, column = line, GRID_SIZE - step + 1
			elseif direction == "UP" then
				row, column = step, line
			else
				row, column = GRID_SIZE - step + 1, line
			end
			table.insert(indices, (row - 1) * GRID_SIZE + column)
		end
		return indices
	end

	local function slide(direction: string): ({ number }, { number }, number, boolean)
		local nextBoard: { number } = table.create(CELL_COUNT, 0)
		local mergedTargets: { number } = {}
		local gained = 0
		for line = 1, GRID_SIZE do
			local indices = lineIndices(direction, line)
			local values: { number } = {}
			for _, index in indices do
				if board[index] > 0 then
					table.insert(values, board[index])
				end
			end
			local output: { MergeResult } = {}
			local cursor = 1
			while cursor <= #values do
				if cursor < #values and values[cursor] == values[cursor + 1] then
					local mergedValue = values[cursor] * 2
					table.insert(output, { value = mergedValue, merged = true })
					gained += mergedValue
					cursor += 2
				else
					table.insert(output, { value = values[cursor], merged = false })
					cursor += 1
				end
			end
			for outputIndex, result in output do
				local targetIndex = indices[outputIndex]
				nextBoard[targetIndex] = result.value
				if result.merged then
					table.insert(mergedTargets, targetIndex)
				end
			end
		end

		local changed = false
		for index = 1, CELL_COUNT do
			if nextBoard[index] ~= board[index] then
				changed = true
				break
			end
		end
		return nextBoard, mergedTargets, gained, changed
	end

	local function hasMove(): boolean
		if #emptyCells() > 0 then
			return true
		end
		for row = 1, GRID_SIZE do
			for column = 1, GRID_SIZE do
				local index = (row - 1) * GRID_SIZE + column
				if column < GRID_SIZE and board[index] == board[index + 1] then
					return true
				end
				if row < GRID_SIZE and board[index] == board[index + GRID_SIZE] then
					return true
				end
			end
		end
		return false
	end

	local function endGame()
		if not running then
			return
		end
		running = false
		GameShell.Shake(canvas, api.reduceMotion)
		GameShell.Burst(root, UDim2.fromOffset(widthPx() / 2, heightPx() / 2), Colors.Danger, api.reduceMotion)
		api.gameOver(score)
	end

	local function move(direction: string)
		if not running or inputLocked then
			return
		end
		local nextBoard, mergedTargets, gained, changed = slide(direction)
		if not changed then
			api.sounds:Play("Press")
			GameShell.Shake(boardFrame, api.reduceMotion, 0.08)
			return
		end

		inputLocked = true
		board = nextBoard
		local spawnedIndex = spawnPrism()
		if gained > 0 then
			chain += 1
			score += gained
			api.setScore(score)
			api.sounds:Play(if #mergedTargets >= 2 then "Success" else "Like")
			showChain(#mergedTargets, gained)
			for _, index in mergedTargets do
				local zeroIndex = index - 1
				local column = zeroIndex % GRID_SIZE
				local row = math.floor(zeroIndex / GRID_SIZE)
				GameShell.Burst(
					root,
					UDim2.fromOffset(
						boardX + BOARD_PADDING + column * (cellSize + BOARD_GAP) + cellSize / 2,
						boardY + BOARD_PADDING + row * (cellSize + BOARD_GAP) + cellSize / 2
					),
					prismColor(board[index]),
					api.reduceMotion
				)
			end
			if chain % 4 == 0 or #mergedTargets >= 3 then
				flash(Colors.Gold, 0.78)
				GameShell.Shake(canvas, api.reduceMotion, 0.35)
			end
		else
			chain = 0
			api.sounds:Play("Press")
		end
		renderBoard(spawnedIndex, mergedTargets)

		task.delay(INPUT_LOCK_SECONDS, function()
			if root.Parent and running then
				inputLocked = false
				if not hasMove() then
					task.delay(0.28, endGame)
				end
			end
		end)
	end

	local function directionButton(text: string, xOffset: number, direction: string): TextButton
		local button = Factory.New("TextButton", {
			Name = direction .. "Button",
			Size = UDim2.fromOffset(36, 28),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, xOffset, 1, -7),
			BackgroundColor3 = Colors.PanelSoft,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = text,
			TextColor3 = Colors.Text,
			Font = Theme.Fonts.Black,
			TextSize = 15,
			ZIndex = 10,
			Parent = root,
		})
		Factory.Corner(button, 9)
		Factory.Stroke(button, Colors.Cyan, 0.55, 1)
		api.sounds:Bind(button)
		button.Activated:Connect(function()
			move(direction)
		end)
		return button
	end

	directionButton("←", -63, "LEFT")
	directionButton("↑", -21, "UP")
	directionButton("↓", 21, "DOWN")
	directionButton("→", 63, "RIGHT")

	local inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not running then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Left or key == Enum.KeyCode.A or key == Enum.KeyCode.DPadLeft then
			move("LEFT")
		elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.D or key == Enum.KeyCode.DPadRight then
			move("RIGHT")
		elseif key == Enum.KeyCode.Up or key == Enum.KeyCode.W or key == Enum.KeyCode.DPadUp then
			move("UP")
		elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S or key == Enum.KeyCode.DPadDown then
			move("DOWN")
		end
	end)

	local pointerBegan = canvas.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
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
		local delta = Vector2.new(input.Position.X, input.Position.Y) - start
		if delta.Magnitude < SWIPE_MIN_DISTANCE then
			return
		end
		if math.abs(delta.X) > math.abs(delta.Y) then
			move(if delta.X > 0 then "RIGHT" else "LEFT")
		else
			move(if delta.Y > 0 then "DOWN" else "UP")
		end
	end)

	spawnPrism()
	spawnPrism()
	renderBoard(nil, nil)

	return function()
		running = false
		inputConnection:Disconnect()
		pointerBegan:Disconnect()
		pointerEnded:Disconnect()
		root:Destroy()
	end
end

return Game
