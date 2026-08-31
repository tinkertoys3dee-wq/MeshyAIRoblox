--!strict

-- Echo Match: a Simon-says pattern memory game. The board plays a growing
-- sequence of lit pads; the player repeats it back in order. Clearing a
-- round appends one more step and speeds the playback up slightly, so a long
-- run is really a test of how much sequence you can hold in your head at
-- once, not reflexes. Every pad response also has to beat a per-step timer
-- that shrinks with round number -- hesitating is its own failure mode,
-- distinct from tapping the wrong pad, so a strong run can still end two
-- ways. One wrong tap or one timeout ends the run, same "no second life"
-- rule the rest of the roster uses.
--
-- Score is every correct tap (with a speed-combo bonus for fast repeats)
-- plus an escalating clear bonus each time a full round is completed, so a
-- run that dies mid-round on a long sequence still banked real points along
-- the way rather than only paying out on a clean finish.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Parent.Factory)
local GameShell = require(script.Parent.GameShell)

local Colors = Theme.Colors

local PAD_COUNT = 4
-- Color carries the primary signal; the glyph is redundant so a colorblind
-- player can track the sequence purely by shape, the same convention
-- ColorSwitch established for its rings.
local PAD_COLOR = { Colors.Violet, Colors.Cyan, Colors.Mint, Colors.Rose }
local PAD_GLYPH = { "▲", "●", "■", "★" }
local PAD_KEY = { Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.A, Enum.KeyCode.D }
local PAD_DIM_TRANSPARENCY = 0.6
local PAD_LIT_TRANSPARENCY = 0.05

local BASE_FLASH_DURATION = 0.52
local MIN_FLASH_DURATION = 0.26
local FLASH_DURATION_STEP = 0.014 -- shaved off per round
local BASE_FLASH_GAP = 0.2
local MIN_FLASH_GAP = 0.1
local FLASH_GAP_STEP = 0.006
local INTRO_PAUSE = 0.6
local ROUND_CLEAR_PAUSE = 0.85
local WRONG_TAP_REVEAL_PAUSE = 0.55

local BASE_STEP_TIME = 2.3 -- seconds the player has to land each tap once their turn starts
local MIN_STEP_TIME = 1.05
local STEP_TIME_DECAY_PER_ROUND = 0.045

local COMBO_WINDOW = 1.05 -- seconds between correct taps before the speed-combo resets
local COMBO_MAX_BONUS = 6
local ROUND_CLEAR_BONUS_PER_ROUND = 3
local CONFETTI_EVERY_ROUNDS = 5 -- a bigger celebration on every 5th cleared round

type Pad = {
	button: TextButton,
	glyph: TextLabel,
}

local Game = {} :: GameShell.GameModule
Game.Name = "Echo Match"
Game.Key = "EchoMatch"

function Game.Start(canvas: Frame, api: GameShell.GameApi): () -> ()
	local running = true
	local score = 0
	local round = 1
	local sequence: { number } = {}
	local playerIndex = 1
	local acceptingInput = false
	local combo = 0
	local lastTapTime = 0
	local stepDeadline = 0
	local showTimerBar = false
	local runToken = 0 -- bumped on cleanup so a stray delayed coroutine can't act after teardown

	local function width(): number
		local w = math.floor(canvas.AbsoluteSize.X)
		return if w > 40 then w else 504
	end
	local function height(): number
		local h = math.floor(canvas.AbsoluteSize.Y)
		return if h > 40 then h else 270
	end

	local function flashDuration(): number
		return math.max(MIN_FLASH_DURATION, BASE_FLASH_DURATION - (round - 1) * FLASH_DURATION_STEP)
	end
	local function flashGap(): number
		return math.max(MIN_FLASH_GAP, BASE_FLASH_GAP - (round - 1) * FLASH_GAP_STEP)
	end
	local function stepTime(): number
		return math.max(MIN_STEP_TIME, BASE_STEP_TIME - (round - 1) * STEP_TIME_DECAY_PER_ROUND)
	end

	local backdrop = Factory.New("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = canvas,
	})
	Factory.Gradient(backdrop, { Colors.Panel, Colors.Ink }, 90)

	local boardSize = math.clamp(math.floor(math.min(width(), height()) * 0.68), 150, 232)
	local padGap = 12
	local padSize = math.floor((boardSize - padGap) / 2)
	local boardOriginX = math.floor((width() - boardSize) / 2)
	local topAreaHeight = 36
	local timerAreaHeight = 26
	local contentHeight = topAreaHeight + boardSize + timerAreaHeight
	local boardOriginY = topAreaHeight + math.max(0, math.floor((height() - contentHeight) / 2))

	local glowBlob = Factory.Blob(canvas, boardSize * 1.15, UDim2.new(), Colors.Violet, 0.9)
	glowBlob.AnchorPoint = Vector2.new(0.5, 0.5)
	glowBlob.Position = UDim2.fromOffset(boardOriginX + boardSize / 2, boardOriginY + boardSize / 2)

	local statusLabel = Factory.Label(canvas, "Get ready...", UDim2.new(1, -20, 0, 22), {
		Name = "StatusLabel",
		Position = UDim2.fromOffset(10, 6),
		Color = Colors.TextMuted,
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 10,
	})

	local roundPill = Factory.New("Frame", {
		Name = "RoundPill",
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.fromOffset(72, 22),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 11,
		Parent = canvas,
	})
	Factory.Corner(roundPill, 11)
	local roundLabel = Factory.Label(roundPill, "Round 1", UDim2.fromScale(1, 1), {
		Color = Colors.Gold,
		Font = Theme.Fonts.Black,
		TextSize = 12,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
	})

	local comboLabel = Factory.Label(canvas, "", UDim2.fromOffset(150, 24), {
		Name = "ComboLabel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Color = Colors.Gold,
		Font = Theme.Fonts.Black,
		TextSize = 14,
		AlignX = Enum.TextXAlignment.Right,
		TextTransparency = 1,
		ZIndex = 11,
	})
	Factory.New("UIStroke", { Color = Colors.Ink, Thickness = 1.5, Transparency = 0.5, Parent = comboLabel })

	local board = Factory.New("Frame", {
		Name = "Board",
		Position = UDim2.fromOffset(boardOriginX, boardOriginY),
		Size = UDim2.fromOffset(boardSize, boardSize),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = canvas,
	})
	Factory.Corner(board, 18)
	Factory.Stroke(board, Colors.Line, 0.5, 1.5)

	local padPositions = {
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(padSize + padGap, 0),
		UDim2.fromOffset(0, padSize + padGap),
		UDim2.fromOffset(padSize + padGap, padSize + padGap),
	}

	local pads: { Pad } = {}
	for i = 1, PAD_COUNT do
		local button = Factory.New("TextButton", {
			Name = "Pad" .. i,
			Position = padPositions[i],
			Size = UDim2.fromOffset(padSize, padSize),
			BackgroundColor3 = PAD_COLOR[i],
			BackgroundTransparency = PAD_DIM_TRANSPARENCY,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 4,
			Parent = board,
		})
		Factory.Corner(button, 14)
		Factory.Stroke(button, Colors.Ink, 0.35, 1.5)
		local glyph = Factory.Label(button, PAD_GLYPH[i], UDim2.fromScale(1, 1), {
			Color = Colors.Ink,
			TextSize = math.floor(padSize * 0.34),
			TextTransparency = 0.1,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 5,
		})
		pads[i] = { button = button, glyph = glyph }
	end

	local timerTrack = Factory.New("Frame", {
		Name = "TimerTrack",
		Position = UDim2.fromOffset(boardOriginX, boardOriginY + boardSize + 12),
		Size = UDim2.fromOffset(boardSize, 8),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = canvas,
	})
	Factory.Corner(timerTrack, 4)
	local timerFill = Factory.New("Frame", {
		Name = "TimerFill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Mint,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = timerTrack,
	})
	Factory.Corner(timerFill, 4)

	local function timerColor(fraction: number): Color3
		if fraction > 0.5 then
			return Colors.Mint:Lerp(Colors.Gold, (1 - fraction) * 2)
		end
		return Colors.Gold:Lerp(Colors.Danger, 1 - fraction * 2)
	end

	local comboFadeToken = 0
	local function showComboLabel(comboCount: number)
		comboFadeToken += 1
		local myToken = comboFadeToken
		if comboCount < 2 then
			return
		end
		comboLabel.Text = string.format("%dx SPEED", comboCount)
		comboLabel.TextTransparency = 0
		if not api.reduceMotion then
			local pop = Factory.New("UIScale", { Scale = 1.3, Parent = comboLabel })
			TweenService
				:Create(pop, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end
		task.delay(COMBO_WINDOW, function()
			if myToken == comboFadeToken and comboLabel.Parent then
				if api.reduceMotion then
					comboLabel.TextTransparency = 1
				else
					TweenService:Create(comboLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
				end
			end
		end)
	end

	local function showScorePopup(index: number, amount: number)
		if api.reduceMotion then
			return
		end
		local popup = Factory.Label(canvas, "+" .. amount, UDim2.fromOffset(70, 20), {
			Name = "ScorePopup",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(
				boardOriginX + padPositions[index].X.Offset + padSize / 2,
				boardOriginY + padPositions[index].Y.Offset
			),
			Color = Colors.Text,
			Font = Theme.Fonts.Black,
			TextSize = 15,
			AlignX = Enum.TextXAlignment.Center,
			ZIndex = 20,
		})
		Factory.New("UIStroke", { Color = Colors.Ink, Thickness = 1.5, Transparency = 0.5, Parent = popup })
		local tween = TweenService:Create(popup, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = popup.Position - UDim2.fromOffset(0, 24),
			TextTransparency = 1,
		})
		tween.Completed:Connect(function()
			popup:Destroy()
		end)
		tween:Play()
	end

	local function litPad(index: number, lit: boolean, colorOverride: Color3?)
		local pad = pads[index]
		pad.button.BackgroundColor3 = colorOverride or PAD_COLOR[index]
		pad.button.BackgroundTransparency = if lit then PAD_LIT_TRANSPARENCY else PAD_DIM_TRANSPARENCY
		if lit and not api.reduceMotion then
			local scaleUp = Factory.New("UIScale", { Scale = 1, Parent = pad.button })
			TweenService:Create(scaleUp, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Scale = 1.06,
			}):Play()
		end
	end

	local heartbeatConn: RBXScriptConnection
	heartbeatConn = RunService.Heartbeat:Connect(function()
		if not running then
			return
		end
		if showTimerBar then
			local remaining = stepDeadline - os.clock()
			local fraction = math.clamp(remaining / stepTime(), 0, 1)
			timerFill.Size = UDim2.fromScale(fraction, 1)
			timerFill.BackgroundColor3 = timerColor(fraction)
			if remaining <= 0 then
				showTimerBar = false
				acceptingInput = false
				statusLabel.Text = "Too slow!"
				GameShell.Shake(canvas, api.reduceMotion)
				api.sounds:Play("Error")
				running = false
				heartbeatConn:Disconnect()
				api.gameOver(score)
			end
		end
	end)

	local function endGame()
		if not running then
			return
		end
		running = false
		acceptingInput = false
		showTimerBar = false
		heartbeatConn:Disconnect()
		api.gameOver(score)
	end

	local function beginPlayerTurn()
		local myToken = runToken
		playerIndex = 1
		acceptingInput = true
		stepDeadline = os.clock() + stepTime()
		showTimerBar = true
		timerTrack.Visible = true
		roundLabel.Text = "Round " .. round
		statusLabel.Text = string.format("Your turn -- %d/%d", 0, #sequence)
		if myToken ~= runToken then
			return
		end
	end

	local function playSequence()
		local myToken = runToken
		acceptingInput = false
		showTimerBar = false
		timerTrack.Visible = false
		statusLabel.Text = "Watch..."
		roundLabel.Text = "Round " .. round
		task.wait(INTRO_PAUSE)
		if not running or myToken ~= runToken then
			return
		end
		for _, padIndex in ipairs(sequence) do
			if not running or myToken ~= runToken then
				return
			end
			litPad(padIndex, true)
			task.wait(flashDuration())
			if not running or myToken ~= runToken then
				return
			end
			litPad(padIndex, false)
			task.wait(flashGap())
		end
		if not running or myToken ~= runToken then
			return
		end
		beginPlayerTurn()
	end

	local function handleWrongTap(index: number)
		acceptingInput = false
		showTimerBar = false
		litPad(sequence[playerIndex], true, Colors.Danger)
		statusLabel.Text = "Not quite!"
		GameShell.Shake(canvas, api.reduceMotion)
		api.sounds:Play("Error")
		task.wait(WRONG_TAP_REVEAL_PAUSE)
		litPad(sequence[playerIndex], false)
		endGame()
	end

	local function celebrateRoundClear()
		acceptingInput = false
		showTimerBar = false
		timerTrack.Visible = false
		local clearBonus = ROUND_CLEAR_BONUS_PER_ROUND * round
		score += clearBonus
		api.setScore(score)
		statusLabel.Text = "Round cleared! +" .. clearBonus
		api.sounds:Play("Success")
		for i = 1, PAD_COUNT do
			GameShell.Ring(
				board,
				UDim2.fromOffset(padPositions[i].X.Offset + padSize / 2, padPositions[i].Y.Offset + padSize / 2),
				PAD_COLOR[i],
				api.reduceMotion,
				padSize * 0.6
			)
		end
		if round % CONFETTI_EVERY_ROUNDS == 0 then
			GameShell.Confetti(canvas, width(), 0, api.reduceMotion)
		end
		round += 1
		table.insert(sequence, math.random(1, PAD_COUNT))
		task.wait(ROUND_CLEAR_PAUSE)
		if not running then
			return
		end
		task.spawn(playSequence)
	end

	local function handleTap(index: number)
		if not running or not acceptingInput then
			return
		end
		if index ~= sequence[playerIndex] then
			handleWrongTap(index)
			return
		end

		local now = os.clock()
		combo = if now - lastTapTime <= COMBO_WINDOW then combo + 1 else 1
		lastTapTime = now
		local bonus = math.min(combo - 1, COMBO_MAX_BONUS)
		local gained = 1 + bonus
		score += gained
		api.setScore(score)
		showScorePopup(index, gained)
		showComboLabel(combo)

		litPad(index, true)
		GameShell.Burst(
			board,
			UDim2.fromOffset(padPositions[index].X.Offset + padSize / 2, padPositions[index].Y.Offset + padSize / 2),
			PAD_COLOR[index],
			api.reduceMotion
		)
		api.sounds:Play("Press")
		task.delay(0.14, function()
			if pads[index].button.Parent then
				litPad(index, false)
			end
		end)

		playerIndex += 1
		if playerIndex > #sequence then
			celebrateRoundClear()
		else
			stepDeadline = os.clock() + stepTime()
			statusLabel.Text = string.format("Your turn -- %d/%d", playerIndex - 1, #sequence)
		end
	end

	local padConns: { RBXScriptConnection } = {}
	for i, pad in pads do
		local conn = pad.button.Activated:Connect(function()
			handleTap(i)
		end)
		table.insert(padConns, conn)
	end

	local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not running or not acceptingInput then
			return
		end
		for i, key in PAD_KEY do
			if input.KeyCode == key then
				handleTap(i)
				return
			end
		end
	end)

	table.insert(sequence, math.random(1, PAD_COUNT))
	task.spawn(playSequence)

	return function()
		running = false
		runToken += 1
		heartbeatConn:Disconnect()
		inputConn:Disconnect()
		for _, conn in padConns do
			conn:Disconnect()
		end
		backdrop:Destroy()
		glowBlob:Destroy()
		statusLabel:Destroy()
		roundPill:Destroy()
		comboLabel:Destroy()
		board:Destroy()
		timerTrack:Destroy()
	end
end

return Game
