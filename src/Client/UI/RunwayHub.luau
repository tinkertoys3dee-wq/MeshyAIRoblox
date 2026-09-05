--!strict

-- A map-preserving social style loop. This module owns UI only: the server
-- synchronizes phases/votes/rewards, while ViewportController clones the
-- avatars players are already wearing into isolated WorldModels. Nothing in
-- Workspace or global Lighting is created, moved, or recolored here.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Factory)
local Motion = require(script.Parent.Motion)
local ViewportController = require(script.Parent.ViewportController)

local Colors = Theme.Colors
local localPlayer = Players.LocalPlayer

local RunwayHub = {}

local PHASE_COPY = {
	INTERMISSION = {
		label = "NEXT ROUND",
		instruction = "Join now, then build a look for the new theme.",
		color = Colors.Gold,
	},
	STYLING = {
		label = "STYLE",
		instruction = "Use Avatar Lab, Discover, or your Forge items—then lock in your look.",
		color = Colors.Cyan,
	},
	VOTING = {
		label = "VOTE",
		instruction = "Inspect every locked look and cast one vote. You cannot vote for yourself.",
		color = Colors.Rose,
	},
	RESULTS = {
		label = "RESULTS",
		instruction = "The spotlight is on. Creator XP and daily rewards have been granted.",
		color = Colors.Mint,
	},
}

-- Each phase's full length, for the header ring's drain fraction. Same
-- constants the server runs the round on, so the ring can only disagree
-- with the clock beside it if these ever diverge from Config.
local PHASE_SECONDS = {
	INTERMISSION = Config.Runway.IntermissionSeconds,
	STYLING = Config.Runway.StylingSeconds,
	VOTING = Config.Runway.VotingSeconds,
	RESULTS = Config.Runway.ResultsSeconds,
}

local function formatClock(seconds: number): string
	local safe = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(safe / 60), safe % 60)
end

-- The concept art puts each entrant's own avatar beside their name in the
-- lineup. Resolved by the engine locally (see App.luau's avatarThumbnail
-- for why an rbxthumb:// URI, not a fetched URL) -- avatar thumbnail types
-- only accept one of a fixed discrete size set, of which 150 is the
-- smallest that stays sharp at this row's 44px.
local function avatarBust(userId: number): string
	return string.format("rbxthumb://type=AvatarBust&id=%d&w=150&h=150", userId)
end

local function formatNumber(value: number): string
	local text = tostring(math.floor(value))
	while true do
		local replaced, count = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		text = replaced
		if count == 0 then
			return text
		end
	end
end

local function setLaunchersVisible(app: any, visible: boolean)
	for _, field in { "launcher", "runwayLauncher", "arcadeLauncher", "afkLauncher" } do
		local launcher = app[field]
		if launcher and launcher.Parent then
			launcher.Visible = visible
		end
	end
end

local function entryFor(state: { [string]: any }, userId: number): { [string]: any }?
	for _, entry in state.entries or {} do
		if entry.userId == userId then
			return entry
		end
	end
	return nil
end

local function resultFor(state: { [string]: any }, userId: number): { [string]: any }?
	for _, result in state.results or {} do
		if result.userId == userId then
			return result
		end
	end
	return nil
end

local function stateRevision(state: { [string]: any }): string
	local parts = {
		tostring(state.roundId),
		tostring(state.phase),
		tostring(state.joined),
		tostring(state.ready),
		tostring(state.votedFor),
		tostring(state.creatorProgress and state.creatorProgress.xp or 0),
		tostring(state.journeyState and state.journeyState.doneCount or 0),
		tostring(state.dailyProgress and state.dailyProgress.rounds or 0),
		tostring(state.dailyProgress and state.dailyProgress.encoreCompleted or false),
	}
	for _, entry in state.entries or {} do
		table.insert(
			parts,
			string.format("%s:%s:%s", tostring(entry.userId), tostring(entry.ready), tostring(entry.votes))
		)
	end
	return table.concat(parts, "|")
end

-- `app` needs the same small surface as GamesHub plus the runway state/push
-- bridge installed in App:_ConnectPush.
function RunwayHub.Show(app: any)
	if app.runwayOverlay and app.runwayOverlay.Parent then
		return
	end

	local state = app.runwayState or (app.state and app.state.runwayState)
	if not state then
		local success, result = app:_Invoke(Network.Actions.GetRunwayState, {})
		if not success then
			return
		end
		state = result
	end
	app.runwayState = state
	app:_Track({ event = "RunwayOpened" })
	setLaunchersVisible(app, false)

	local reduceMotion = app.state and app.state.profile.settings.reduceMotion == true
	local overlay = Factory.New("Frame", {
		Name = "RunwayOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(7, 7, 18),
		BackgroundTransparency = if reduceMotion then 0.12 else 1,
		BorderSizePixel = 0,
		ZIndex = 230,
		Parent = app.gui,
	})
	app.runwayOverlay = overlay

	local restingPosition = UDim2.fromScale(0.5, 0.5)
	local modal = Factory.ImageCard(
		overlay,
		UDim2.new(0.94, 0, 0.9, 0),
		if reduceMotion then restingPosition else restingPosition + UDim2.fromOffset(0, 20),
		"RunwayModal"
	)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.ZIndex = 231
	modal.ClipsDescendants = true
	Factory.New("UISizeConstraint", {
		MinSize = Vector2.new(320, 440),
		MaxSize = Vector2.new(940, 760),
		Parent = modal,
	})
	local uiScale = Motion.FitPanel(modal, function()
		return if app.state then tonumber(app.state.profile.settings.uiScale) or 1 else 1
	end)
	app.runwayUiScale = uiScale

	local accent = Factory.New("Frame", {
		Name = "TopAccent",
		Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = Colors.Rose,
		BorderSizePixel = 0,
		ZIndex = 232,
		Parent = modal,
	})
	Factory.Gradient(accent, { Colors.Rose, Colors.Gold, Colors.Cyan, Colors.Violet }, 0)

	local header = Factory.New("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.new(1, 0, 0, 92),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 232,
		Parent = modal,
	})
	-- A round, gold-rimmed medallion, as the concept art draws every hub's
	-- title mark -- not a rounded square.
	local titleBadge = Factory.New("Frame", {
		Size = UDim2.fromOffset(52, 52),
		Position = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Colors.Rose,
		BorderSizePixel = 0,
		ZIndex = 233,
		Parent = header,
	})
	Factory.Corner(titleBadge, 26)
	Factory.Gradient(titleBadge, { Colors.Rose, Colors.Violet }, 135)
	Factory.Stroke(titleBadge, Colors.Gold, 0.15, 2)
	Factory.Label(titleBadge, "◆", UDim2.fromScale(1, 1), {
		Font = Theme.Fonts.Black,
		TextSize = 25,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
		ZIndex = 234,
	})
	Factory.Label(header, "FORGE RUNWAY", UDim2.new(1, -260, 0, 26), {
		Position = UDim2.fromOffset(80, 13),
		Font = Theme.Fonts.Black,
		TextSize = 22,
		Truncate = Enum.TextTruncate.AtEnd,
		ZIndex = 233,
	})
	-- The art frames the theme rather than just naming it.
	local function themeLine(current: { [string]: any }): string
		return string.format("Tonight's theme · %s", current.theme or "Style challenge")
	end
	local themeLabel = Factory.Label(header, themeLine(state), UDim2.new(1, -260, 0, 22), {
		Position = UDim2.fromOffset(80, 39),
		Font = Theme.Fonts.Medium,
		TextSize = 13,
		Color = Colors.TextMuted,
		Truncate = Enum.TextTruncate.AtEnd,
		ZIndex = 233,
	})
	local phaseLabel = Factory.Label(header, "", UDim2.fromOffset(98, 20), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -146, 0, 36),
		Font = Theme.Fonts.Bold,
		TextSize = 11,
		AlignX = Enum.TextXAlignment.Right,
		ZIndex = 233,
	})
	-- The concept art wraps the clock in a gold ring that drains as the
	-- phase runs down. Every phase length is a client-side constant
	-- (Config.Runway), so the fraction remaining is derivable here without
	-- the server sending one. The ring's own colour stays gold across all
	-- four phases, as the art draws it; the clock inside takes the phase
	-- colour.
	local timerRing = Factory.New("Frame", {
		Name = "TimerRing",
		Size = UDim2.fromOffset(68, 68),
		Position = UDim2.new(1, -136, 0, 12),
		BackgroundTransparency = 1,
		ZIndex = 233,
		Parent = header,
	})
	local setTimerRing = Factory.RadialRing(timerRing, 68, 5, Colors.Gold, Color3.fromRGB(48, 33, 78))
	local timerLabel = Factory.Label(timerRing, "", UDim2.new(1, -14, 0, 22), {
		Position = UDim2.fromOffset(7, 18),
		Font = Theme.Fonts.Black,
		TextSize = 18,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 234,
	})
	Factory.Label(timerRing, "LEFT", UDim2.new(1, -14, 0, 12), {
		Position = UDim2.fromOffset(7, 38),
		Font = Theme.Fonts.Bold,
		TextSize = 9,
		Color = Colors.TextMuted,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 234,
	})
	local close = Factory.ImageButton(header, "×", UDim2.fromOffset(38, 38), UDim2.new(1, -52, 0, 17), nil)
	close.TextSize = 21
	close.ZIndex = 234
	-- Round, with the art's gold rim: the decal behind it keeps its own
	-- shape, so this is the fallback's outline and the hit area either way.
	local closeCorner = close:FindFirstChildOfClass("UICorner")
	if closeCorner then
		closeCorner.CornerRadius = UDim.new(0.5, 0)
	end
	app:_BindButton(close)
	-- The single centred flourish the art hangs under every hub header.
	local headerFlourish =
		Factory.Icon(header, "FlourishDivider", UDim2.fromOffset(120, 16), UDim2.new(0.5, -60, 1, -18))
	if headerFlourish then
		headerFlourish.ZIndex = 233
	end

	local body = Factory.New("ScrollingFrame", {
		Name = "RunwayContent",
		Position = UDim2.fromOffset(12, 106),
		Size = UDim2.new(1, -24, 1, -118),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Colors.Rose,
		ZIndex = 232,
		Parent = modal,
	})
	Factory.ScalePadding(body, 0.008, 0.008)
	local stack = Factory.New("Frame", {
		Name = "Stack",
		Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 232,
		Parent = body,
	})
	Factory.List(stack, Enum.FillDirection.Vertical, 12)

	local selectedUserId = localPlayer.UserId
	local openingWinner = state.phase == "RESULTS" and state.results and state.results[1]
	if openingWinner and openingWinner.placement == 1 then
		selectedUserId = openingWinner.userId
	end
	local viewportController: any = nil
	local leaderboard = nil :: { [string]: any }?
	local rendering = false
	local closed = false
	local inputConnection: RBXScriptConnection? = nil

	local function closeHub()
		if closed then
			return
		end
		closed = true
		if inputConnection then
			inputConnection:Disconnect()
			inputConnection = nil
		end
		if viewportController then
			viewportController:Destroy()
			viewportController = nil
		end
		app.runwayRefresh = nil
		app.runwayUiScale = nil
		app.runwayOverlay = nil
		app.sounds:Play("PanelClose")
		app:_CloseModal(overlay, modal)
		setLaunchersVisible(app, not app.shell.Visible and app.afkOverlay == nil)
	end

	close.Activated:Connect(closeHub)
	inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or closed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			closeHub()
		end
	end)

	local function invokeAndApply(action: string, payload: any?)
		task.spawn(function()
			local success, result = app:_Invoke(action, payload or {})
			if success and type(result) == "table" and result.phase then
				state = result
				app.runwayState = result
				if app.runwayRefresh then
					app.runwayRefresh(result)
				end
			end
		end)
	end

	local function openAvatarLab()
		closeHub()
		app:_SetStudioOpen(true)
		app:_OpenPage("Avatar Lab")
	end
	local function openCreate()
		closeHub()
		app:_SetStudioOpen(true)
		app:_OpenPage("Create")
	end

	local function fetchLeaderboard(refresh: (() -> ())?)
		task.spawn(function()
			local success, result = app:_Invoke(Network.Actions.GetRunwayLeaderboard, {})
			if success and type(result) == "table" then
				leaderboard = result
				if refresh and not closed then
					refresh()
				end
			end
		end)
	end

	local render: () -> ()
	render = function()
		if closed or rendering then
			return
		end
		rendering = true
		local selectedObject = GuiService.SelectedObject
		local restoreFocus = selectedObject ~= nil and selectedObject:IsDescendantOf(stack)
		if viewportController then
			viewportController:Destroy()
			viewportController = nil
		end
		for _, child in stack:GetChildren() do
			child:Destroy()
		end
		-- 22, not 12: every panel below is titled by a banner tab that
		-- overhangs 12px above the card it sits on.
		Factory.List(stack, Enum.FillDirection.Vertical, 22)

		local camera = Workspace.CurrentCamera
		local viewportWidth = camera and camera.ViewportSize.X or 1200
		local compact = viewportWidth < 760
		-- The concept art runs the lineup down a wide left column with the
		-- selected look and the weekly spotlight stacked beside it. Two
		-- columns need real width -- the modal caps at 940 -- so below 900
		-- this stays the single stack it has always been.
		local twoColumn = viewportWidth >= 900
		local columns = if twoColumn
			then Factory.New("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ZIndex = 232,
				Parent = stack,
			})
			else nil
		local leftColumn = stack
		local rightColumn = stack
		if columns then
			Factory.List(columns, Enum.FillDirection.Horizontal, 14)
			leftColumn = Factory.New("Frame", {
				Size = UDim2.new(0.56, -7, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ZIndex = 232,
				Parent = columns,
			})
			Factory.List(leftColumn, Enum.FillDirection.Vertical, 22)
			Factory.BannerHeadroom(leftColumn)
			rightColumn = Factory.New("Frame", {
				Size = UDim2.new(0.44, -7, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ZIndex = 232,
				Parent = columns,
			})
			Factory.List(rightColumn, Enum.FillDirection.Vertical, 22)
			Factory.BannerHeadroom(rightColumn)
		else
			-- Single column: the banner-titled hero is the stack's own first
			-- child, so the headroom belongs there instead.
			Factory.BannerHeadroom(stack)
		end

		local phase = PHASE_COPY[state.phase] or PHASE_COPY.INTERMISSION
		-- The hero's stacked layout (viewport above its details, rather than
		-- side by side) is what fits a narrow phone AND what fits the ~44%
		-- right column above.
		local heroNarrow = compact or twoColumn
		-- 610 before the look summary above pushed the action row down 38px;
		-- the wide layout has that much slack already and keeps its height.
		local heroHeight = if heroNarrow then 648 else 396
		local hero = Factory.ImageCard(rightColumn, UDim2.new(1, 0, 0, heroHeight), nil, "RoundHero")
		hero.LayoutOrder = 1
		local selectedIsSelf = selectedUserId == localPlayer.UserId
		local selectedName = (entryFor(state, selectedUserId) or {}).name
		Factory.SectionBanner(hero, if selectedIsSelf then "Your Look" else tostring(selectedName or "Their Look"))
		local phasePill = Factory.ImagePill(hero, phase.label, phase.color, 116)
		phasePill.Position = UDim2.fromOffset(16, 34)
		Factory.Label(hero, phase.instruction, UDim2.new(1, -160, 0, 38), {
			Position = UDim2.fromOffset(144, 30),
			Color = Colors.TextMuted,
			TextSize = 12,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Top,
		})

		local preview = Factory.New("ViewportFrame", {
			Name = "SelectedLook",
			Position = if heroNarrow then UDim2.fromOffset(16, 82) else UDim2.fromOffset(16, 80),
			Size = if heroNarrow then UDim2.new(1, -32, 0, 260) else UDim2.new(0.5, -24, 1, -98),
			BackgroundColor3 = Color3.fromRGB(58, 40, 104),
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = hero,
		})
		Factory.Corner(preview, 16)
		Factory.Stroke(preview, phase.color, 0.35, 1.5)
		local selectedPlayer = Players:GetPlayerByUserId(selectedUserId) or localPlayer
		viewportController = ViewportController.new(preview, nil, selectedPlayer)
		local selectedEntry = entryFor(state, selectedUserId)
		Factory.Label(
			preview,
			selectedEntry and selectedEntry.name or selectedPlayer.DisplayName,
			UDim2.new(1, -54, 0, 26),
			{
				Position = UDim2.fromOffset(12, 10),
				Font = Theme.Fonts.Bold,
				TextSize = 12,
				ZIndex = 5,
			}
		)
		local resetCamera = Factory.ImageButton(preview, "↺", UDim2.fromOffset(32, 28), UDim2.new(1, -42, 0, 8), nil)
		resetCamera.ZIndex = 5
		app:_BindButton(resetCamera)
		resetCamera.Activated:Connect(function()
			if viewportController then
				viewportController:ResetCamera()
			end
		end)

		local detailScale = if heroNarrow then 0 else 0.5
		local detailOffset = if heroNarrow then 16 else 8
		local detailY = if heroNarrow then 354 else 82
		local detailWidth = if heroNarrow then UDim2.new(1, -32, 0, 0) else UDim2.new(0.5, -24, 0, 0)
		local progress = state.creatorProgress or (app.state and app.state.creatorProgress) or {}
		Factory.Label(
			hero,
			string.format("LEVEL %d", progress.level or 1),
			UDim2.new(detailWidth.X.Scale, detailWidth.X.Offset, 0, 18),
			{
				Position = UDim2.new(detailScale, detailOffset, 0, detailY),
				Font = Theme.Fonts.Bold,
				TextSize = 11,
				Color = Colors.Gold,
			}
		)
		Factory.Label(
			hero,
			progress.title or "Forge Apprentice",
			UDim2.new(detailWidth.X.Scale, detailWidth.X.Offset, 0, 30),
			{
				Position = UDim2.new(detailScale, detailOffset, 0, detailY + 20),
				Font = Theme.Fonts.Black,
				TextSize = 20,
				Truncate = Enum.TextTruncate.AtEnd,
			}
		)
		local xpTrack = Factory.New("Frame", {
			Position = UDim2.new(detailScale, detailOffset, 0, detailY + 56),
			Size = UDim2.new(detailWidth.X.Scale, detailWidth.X.Offset, 0, 10),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.32,
			BorderSizePixel = 0,
			Parent = hero,
		})
		Factory.Corner(xpTrack, 5)
		local xpFill = Factory.New("Frame", {
			Size = UDim2.new(math.clamp(progress.levelProgress or 0, 0, 1), 0, 1, 0),
			BackgroundColor3 = Colors.Gold,
			BorderSizePixel = 0,
			Parent = xpTrack,
		})
		Factory.Corner(xpFill, 5)
		Factory.Gradient(xpFill, { Colors.Rose, Colors.Gold }, 0)
		Factory.Label(
			hero,
			string.format("%s XP", formatNumber(progress.xp or 0)),
			UDim2.new(detailWidth.X.Scale, detailWidth.X.Offset, 0, 18),
			{
				Position = UDim2.new(detailScale, detailOffset, 0, detailY + 70),
				Color = Colors.TextMuted,
				TextSize = 10,
			}
		)

		local statsY = detailY + 96
		Factory.Label(
			hero,
			string.format(
				"%d rounds  ·  %d wins  ·  %d votes cast",
				progress.runwayEntries or 0,
				progress.runwayWins or 0,
				progress.runwayVotes or 0
			),
			UDim2.new(detailWidth.X.Scale, detailWidth.X.Offset, 0, 20),
			{
				Position = UDim2.new(detailScale, detailOffset, 0, statsY),
				Color = Colors.TextMuted,
				TextSize = 11,
				Truncate = Enum.TextTruncate.AtEnd,
			}
		)

		local dailyProgress = state.dailyProgress or {}
		local encoreComplete = dailyProgress.encoreCompleted == true
		local encoreRounds = math.min(dailyProgress.rounds or 0, dailyProgress.target or 2)
		local encoreTarget = dailyProgress.target or 2
		Factory.Label(
			hero,
			if encoreComplete
				then string.format(
					"DAILY ENCORE COMPLETE  ✓  +%d TOKENS · +%d XP",
					dailyProgress.bonusTokens or 0,
					dailyProgress.xp or 0
				)
				else string.format(
					"DAILY ENCORE  %d/%d ROUNDS  ·  +%d TOKENS · +%d XP",
					encoreRounds,
					encoreTarget,
					dailyProgress.bonusTokens or 0,
					dailyProgress.xp or 0
				),
			UDim2.new(detailWidth.X.Scale, detailWidth.X.Offset, 0, 20),
			{
				Position = UDim2.new(detailScale, detailOffset, 0, statsY + 20),
				Color = if encoreComplete then Colors.Mint else Colors.Gold,
				Font = Theme.Fonts.Bold,
				TextSize = 10,
				Truncate = Enum.TextTruncate.AtEnd,
			}
		)

		-- The art's YOUR LOOK panel names what you are about to lock in --
		-- the item and what else is on with it -- and points at where to
		-- change it. Read off the profile's own equipped list, so it needs
		-- nothing from the runway state, and only shown for your own entry:
		-- selecting somebody else's look means the panel is describing
		-- theirs, and their loadout is not something this client knows.
		local lookY = statsY + 40
		if selectedIsSelf then
			local profileNow = app.state and app.state.profile
			local equipped = profileNow and profileNow.equippedItemIds or {}
			local names = {}
			for _, itemId in equipped do
				local item = profileNow and profileNow.items[itemId]
				if item then
					table.insert(names, item.name)
				end
			end
			Factory.Label(
				hero,
				if #names == 0 then "Nothing equipped yet" else names[1],
				UDim2.new(detailWidth.X.Scale, detailWidth.X.Offset, 0, 20),
				{
					Position = UDim2.new(detailScale, detailOffset, 0, lookY),
					Font = Theme.Fonts.Black,
					TextSize = 15,
					Truncate = Enum.TextTruncate.AtEnd,
				}
			)
			Factory.Label(
				hero,
				if #names > 1
					then string.format("+ %d more on your avatar", #names - 1)
					else "Change it in My Studio before you lock.",
				UDim2.new(detailWidth.X.Scale, detailWidth.X.Offset, 0, 18),
				{
					Position = UDim2.new(detailScale, detailOffset, 0, lookY + 20),
					Color = Colors.TextMuted,
					TextSize = 11,
					Truncate = Enum.TextTruncate.AtEnd,
				}
			)
		end

		local actionY = statsY + 92
		local primaryText = "Watch the runway"
		local primaryAction: (() -> ())? = nil
		if state.phase == "INTERMISSION" then
			if state.joined then
				primaryText = "Joined next round ✓"
			else
				primaryText = "Join next round"
				primaryAction = function()
					invokeAndApply(Network.Actions.JoinRunway, {})
				end
			end
		elseif state.phase == "STYLING" then
			if not state.joined then
				primaryText = "Join this round"
				primaryAction = function()
					invokeAndApply(Network.Actions.JoinRunway, {})
				end
			elseif not state.ready then
				primaryText = "Lock in my look"
				primaryAction = function()
					invokeAndApply(Network.Actions.ReadyRunwayLook, {})
				end
			else
				primaryText = "Look locked ✓"
			end
		elseif state.phase == "VOTING" then
			primaryText = if state.votedFor then "Vote cast ✓" else "Choose a look below"
		else
			local winner = state.results and state.results[1]
			primaryText = if winner and winner.placement == 1
				then "Winner: " .. winner.name
				else "Round complete · next theme soon"
		end
		local primary = Factory.ImageButton(
			hero,
			primaryText,
			UDim2.new(detailWidth.X.Scale, detailWidth.X.Offset, 0, 42),
			UDim2.new(detailScale, detailOffset, 0, actionY),
			if primaryAction then "primary" else nil
		)
		primary.Active = primaryAction ~= nil
		app:_BindButton(primary)
		if primaryAction then
			primary.Activated:Connect(primaryAction)
		end

		local lab = Factory.ImageButton(
			hero,
			if state.phase == "RESULTS" then "Forge next look" else "Open Avatar Lab",
			UDim2.new(detailWidth.X.Scale / 2, detailWidth.X.Offset / 2 - 4, 0, 36),
			UDim2.new(detailScale, detailOffset, 0, actionY + 50),
			"mint"
		)
		app:_BindButton(lab)
		lab.Activated:Connect(if state.phase == "RESULTS" then openCreate else openAvatarLab)
		local invite = Factory.ImageButton(
			hero,
			"Invite friend",
			UDim2.new(detailWidth.X.Scale / 2, detailWidth.X.Offset / 2 - 4, 0, 36),
			UDim2.new(
				detailScale + detailWidth.X.Scale / 2,
				detailOffset + detailWidth.X.Offset / 2 + 4,
				0,
				actionY + 50
			),
			nil
		)
		app:_BindButton(invite)
		invite.Activated:Connect(function()
			app:_PromptFriendInvite()
		end)

		local activeJobs = 0
		local profile = app.state and app.state.profile
		for _, generation in (profile and profile.generations or {}) do
			if
				generation.stage ~= "SUCCEEDED"
				and generation.stage ~= "FAILED"
				and generation.stage ~= "IMAGE_READY"
			then
				activeJobs += 1
			end
		end
		if activeJobs > 0 then
			local activity = Factory.ImageCard(leftColumn, UDim2.new(1, 0, 0, 60), nil, "RunwayForgeActivity")
			activity.LayoutOrder = 1
			Factory.Label(
				activity,
				string.format(
					"⚒  %d creation%s still forging in the background",
					activeJobs,
					if activeJobs == 1 then " is" else "s are"
				),
				UDim2.new(1, -142, 0, 22),
				{
					Position = UDim2.fromOffset(16, 9),
					Font = Theme.Fonts.Bold,
					Color = Colors.Cyan,
					TextSize = 11,
					Truncate = Enum.TextTruncate.AtEnd,
				}
			)
			Factory.Label(
				activity,
				"Keep styling—we'll celebrate as soon as it is ready.",
				UDim2.new(1, -142, 0, 18),
				{
					Position = UDim2.fromOffset(16, 31),
					Color = Colors.TextMuted,
					TextSize = 10,
					Truncate = Enum.TextTruncate.AtEnd,
				}
			)
			local viewActivity = Factory.ImageButton(
				activity,
				"View activity",
				UDim2.fromOffset(132, 32),
				UDim2.new(1, -148, 0, 14),
				nil
			)
			app:_BindButton(viewActivity)
			viewActivity.Activated:Connect(function()
				closeHub()
				app:_SetStudioOpen(true)
				app:_OpenPage("Create")
			end)
		end

		-- First-look journey -------------------------------------------------
		local journey = state.journeyState or (app.state and app.state.journeyState) or { done = {} }
		local journeyComplete = journey.completed == true
		local journeyHeight = 84 + #Config.Retention.FirstLookJourney * 34
		local journeyCard = Factory.ImageCard(leftColumn, UDim2.new(1, 0, 0, journeyHeight), nil, "FirstLookJourney")
		journeyCard.LayoutOrder = 2
		Factory.Label(
			journeyCard,
			if journeyComplete then "FIRST LOOK COMPLETE" else "YOUR FIRST LOOK",
			UDim2.new(1, -126, 0, 20),
			{
				Position = UDim2.fromOffset(16, 13),
				Font = Theme.Fonts.Bold,
				TextSize = 12,
				Color = if journeyComplete then Colors.Mint else Colors.Cyan,
			}
		)
		Factory.Label(
			journeyCard,
			string.format("%d / %d", journey.doneCount or 0, journey.total or #Config.Retention.FirstLookJourney),
			UDim2.fromOffset(90, 20),
			{
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 13),
				Font = Theme.Fonts.Black,
				Color = if journeyComplete then Colors.Mint else Colors.TextMuted,
				AlignX = Enum.TextXAlignment.Right,
				TextSize = 12,
			}
		)
		Factory.Label(
			journeyCard,
			"Free path · each step +2 bonus tokens · finish +12 and +100 Creator XP",
			UDim2.new(1, -32, 0, 26),
			{ Position = UDim2.fromOffset(16, 37), Color = Colors.TextMuted, TextSize = 10, Wrapped = true }
		)
		local journeyY = 70
		for _, definition in Config.Retention.FirstLookJourney do
			local done = journey.done and journey.done[definition.key] == true
			local row = Factory.New("Frame", {
				Position = UDim2.fromOffset(16, journeyY),
				Size = UDim2.new(1, -32, 0, 27),
				BackgroundColor3 = if done then Colors.Mint else Colors.Ink,
				BackgroundTransparency = if done then 0.85 else 0.3,
				BorderSizePixel = 0,
				Parent = journeyCard,
			})
			Factory.Corner(row, 8)
			Factory.Label(row, if done then "✓" else definition.icon, UDim2.fromOffset(32, 27), {
				Font = Theme.Fonts.Bold,
				Color = if done then Colors.Mint else Colors.Text,
				AlignX = Enum.TextXAlignment.Center,
				TextSize = 12,
			})
			Factory.Label(row, definition.label, UDim2.new(1, -90, 1, 0), {
				Position = UDim2.fromOffset(34, 0),
				Color = if done then Colors.Text else Colors.TextMuted,
				TextSize = 11,
				Truncate = Enum.TextTruncate.AtEnd,
			})
			Factory.Label(row, if done then "DONE" else "+2", UDim2.fromOffset(44, 27), {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 0),
				Color = if done then Colors.Mint else Colors.Gold,
				Font = Theme.Fonts.Bold,
				AlignX = Enum.TextXAlignment.Right,
				TextSize = 10,
			})
			journeyY += 34
		end

		-- Participants and voting -------------------------------------------
		local entries = state.entries or {}
		-- Taller rows than the old 40: the concept art shows each entrant's
		-- own avatar beside their name, which needs the height to read.
		local participantHeight = 48 + math.max(1, #entries) * 64
		local participants = Factory.ImageCard(leftColumn, UDim2.new(1, 0, 0, participantHeight), nil, "Participants")
		participants.LayoutOrder = 3
		Factory.SectionBanner(participants, string.format("Runway Lineup · %d joined", #entries))
		if #entries == 0 then
			Factory.Label(participants, "Be the first player under the spotlight.", UDim2.new(1, -32, 0, 34), {
				Position = UDim2.fromOffset(16, 48),
				Color = Colors.TextMuted,
				AlignX = Enum.TextXAlignment.Center,
				TextSize = 12,
			})
		else
			for index, entry in entries do
				local row = Factory.New("TextButton", {
					Name = "LookRow",
					Position = UDim2.fromOffset(16, 40 + (index - 1) * 64),
					Size = UDim2.new(1, -32, 0, 56),
					BackgroundColor3 = if selectedUserId == entry.userId then Colors.Violet else Colors.Ink,
					BackgroundTransparency = if selectedUserId == entry.userId then 0.35 else 0.24,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Text = "",
					Parent = participants,
				})
				Factory.Corner(row, 10)
				Factory.Stroke(row, if selectedUserId == entry.userId then Colors.Gold else Colors.Line, 0.5)
				app:_BindButton(row)
				local face = Factory.New("ImageLabel", {
					Size = UDim2.fromOffset(44, 44),
					Position = UDim2.fromOffset(6, 6),
					BackgroundColor3 = Colors.Panel,
					BorderSizePixel = 0,
					Image = avatarBust(entry.userId),
					ScaleType = Enum.ScaleType.Crop,
					Parent = row,
				})
				Factory.Corner(face, 9)
				Factory.Stroke(face, Colors.Gold, 0.45)
				local voteWidth = if compact then 84 else 150
				Factory.Label(row, entry.name, UDim2.new(1, -(voteWidth + 76), 0, 24), {
					Position = UDim2.fromOffset(58, 7),
					Font = Theme.Fonts.Bold,
					TextSize = 13,
					Truncate = Enum.TextTruncate.AtEnd,
				})
				local statusText = if entry.ready then "LOOK LOCKED" else "STYLING"
				if state.phase == "RESULTS" and entry.votes ~= nil then
					local result = resultFor(state, entry.userId)
					statusText = if result and result.placement
						then string.format("#%d · %dV", result.placement, entry.votes)
						else string.format("%d VOTE%s", entry.votes, if entry.votes == 1 then "" else "S")
				end
				Factory.Label(row, statusText, UDim2.new(1, -(voteWidth + 76), 0, 18), {
					Position = UDim2.fromOffset(58, 31),
					Font = Theme.Fonts.Bold,
					Color = if entry.ready then Colors.Mint else Colors.TextMuted,
					TextSize = 10,
					Truncate = Enum.TextTruncate.AtEnd,
				})
				local canVote = state.phase == "VOTING"
					and state.votedFor == nil
					and entry.ready == true
					and entry.userId ~= localPlayer.UserId
				local canLeave = entry.userId == localPlayer.UserId
					and (state.phase == "INTERMISSION" or state.phase == "STYLING")
				-- votedFor can be the -1 "spent ballot" sentinel (the entrant
				-- this player voted for already left the round) rather than
				-- nil or a real userId -- that never equals any entry.userId,
				-- so without this every remaining row fell through to "Vote"
				-- and looked actionable even though canVote below is already
				-- correctly false for all of them.
				local voteLabel = if canLeave
					then "Leave"
					elseif state.votedFor == entry.userId then "✓"
					elseif state.votedFor ~= nil then "Voted"
					else "Vote"
				-- The concept art writes the entrant's vote count into the
				-- button itself ("Vote * 24") rather than repeating it as a
				-- separate figure.
				local vote = Factory.ImageButton(
					row,
					if voteLabel == "Vote"
							and entry.votes
							and not compact
						then string.format("♥ Vote · %d", entry.votes)
						else voteLabel,
					UDim2.fromOffset(voteWidth, 40),
					UDim2.new(1, -(voteWidth + 12), 0, 8),
					if canLeave then "danger" elseif canVote then "mint" else nil
				)
				vote.Active = canVote or canLeave
				vote.ZIndex = 4
				app:_BindButton(vote)
				if canLeave then
					vote.Activated:Connect(function()
						invokeAndApply(Network.Actions.LeaveRunway, {})
					end)
				elseif canVote then
					vote.Activated:Connect(function()
						invokeAndApply(Network.Actions.VoteRunway, { targetUserId = entry.userId })
					end)
				end
				row.Activated:Connect(function()
					selectedUserId = entry.userId
					render()
				end)
			end
		end

		-- Weekly standings ---------------------------------------------------
		-- Five rows, as the art lists them -- 246 only had room for three.
		local standings = Factory.ImageCard(rightColumn, UDim2.new(1, 0, 0, 336), nil, "WeeklyStandings")
		standings.LayoutOrder = 2
		Factory.SectionBanner(standings, "Weekly Spotlight")
		Factory.Label(standings, "Points from rounds, votes cast/received, and placements", UDim2.new(1, -32, 0, 16), {
			Position = UDim2.fromOffset(16, 36),
			AlignX = Enum.TextXAlignment.Center,
			Color = Colors.TextMuted,
			TextSize = 10,
		})
		Factory.Label(
			standings,
			string.format(
				"Weekly XP: #1 +%d · #2 +%d · #3 +%d",
				Config.Runway.WeeklyPlacementXP[1],
				Config.Runway.WeeklyPlacementXP[2],
				Config.Runway.WeeklyPlacementXP[3]
			),
			UDim2.new(1, -32, 0, 14),
			{
				Position = UDim2.fromOffset(16, 53),
				AlignX = Enum.TextXAlignment.Center,
				Color = Colors.Gold,
				TextSize = 9,
			}
		)
		-- Below the banner tab now, not level with it: a centred tab leaves
		-- no clear right-hand corner to sit in.
		local refresh =
			Factory.ImageButton(standings, "Refresh", UDim2.fromOffset(78, 28), UDim2.new(1, -94, 0, 36), nil)
		app:_BindButton(refresh)
		refresh.Activated:Connect(function()
			leaderboard = nil
			fetchLeaderboard(render)
			render()
		end)
		if not leaderboard then
			Factory.Label(standings, "Loading this week's creators…", UDim2.new(1, -32, 0, 80), {
				Position = UDim2.fromOffset(16, 86),
				Color = Colors.TextMuted,
				AlignX = Enum.TextXAlignment.Center,
				TextSize = 12,
			})
		else
			local rows = leaderboard.standings or {}
			if #rows == 0 then
				Factory.Label(standings, "No weekly points yet. Lock in the first look.", UDim2.new(1, -32, 0, 80), {
					Position = UDim2.fromOffset(16, 86),
					Color = Colors.TextMuted,
					AlignX = Enum.TextXAlignment.Center,
					TextSize = 12,
				})
			else
				for index = 1, math.min(5, #rows) do
					local entry = rows[index]
					local y = 72 + (index - 1) * 46
					local isSelf = entry.userId == localPlayer.UserId
					local color = if index == 1
						then Colors.Gold
						elseif index == 2 then Colors.Cyan
						elseif index == 3 then Colors.Rose
						else Colors.TextMuted
					-- The art seats each placement in a filled circle, and
					-- lights the viewer's own row so they can find themselves
					-- in the list without reading every name.
					if isSelf then
						local highlight = Factory.New("Frame", {
							Position = UDim2.fromOffset(10, y - 3),
							Size = UDim2.new(1, -20, 0, 44),
							BackgroundColor3 = Colors.Violet,
							BackgroundTransparency = 0.7,
							BorderSizePixel = 0,
							Parent = standings,
						})
						Factory.Corner(highlight, 10)
						Factory.Stroke(highlight, Colors.Gold, 0.5)
					end
					local seat = Factory.New("Frame", {
						Position = UDim2.fromOffset(18, y + 5),
						Size = UDim2.fromOffset(28, 28),
						BackgroundColor3 = color,
						BorderSizePixel = 0,
						ZIndex = 2,
						Parent = standings,
					})
					Factory.Corner(seat, 14)
					Factory.Label(seat, tostring(index), UDim2.fromScale(1, 1), {
						AlignX = Enum.TextXAlignment.Center,
						AlignY = Enum.TextYAlignment.Center,
						Font = Theme.Fonts.Black,
						TextSize = 13,
						Color = Colors.Ink,
						ZIndex = 3,
					})
					Factory.Label(standings, if isSelf then "You" else entry.name, UDim2.new(1, -170, 0, 38), {
						Position = UDim2.fromOffset(56, y),
						Font = Theme.Fonts.Bold,
						TextSize = 12,
						Truncate = Enum.TextTruncate.AtEnd,
						ZIndex = 2,
					})
					Factory.Label(
						standings,
						string.format("%s pts", formatNumber(entry.score or 0)),
						UDim2.fromOffset(90, 38),
						{
							AnchorPoint = Vector2.new(1, 0),
							Position = UDim2.new(1, -16, 0, y),
							AlignX = Enum.TextXAlignment.Right,
							Color = color,
							Font = Theme.Fonts.Bold,
							TextSize = 11,
							ZIndex = 2,
						}
					)
				end
			end
			local own = leaderboard.self
			Factory.Label(
				standings,
				if own
					then string.format(
						"YOUR WEEK · %s%s",
						formatNumber(own.score or 0) .. " PTS",
						if own.rank then " · #" .. tostring(own.rank) else ""
					)
					else "FINISH A ROUND TO JOIN THE SPOTLIGHT",
				UDim2.new(1, -32, 0, 18),
				{
					Position = UDim2.fromOffset(16, 301),
					Color = if own then Colors.Cyan else Colors.TextMuted,
					Font = Theme.Fonts.Bold,
					TextSize = 9,
					AlignX = Enum.TextXAlignment.Center,
				}
			)
		end
		if restoreFocus and close.Parent then
			GuiService.SelectedObject = close
		end
		rendering = false
	end

	app.runwayRefresh = function(newState: { [string]: any })
		if closed then
			return
		end
		local previousPhase = state.phase
		state = newState
		app.runwayState = newState
		if previousPhase ~= "RESULTS" and newState.phase == "RESULTS" then
			local winner = newState.results and newState.results[1]
			if winner and winner.placement == 1 then
				selectedUserId = winner.userId
			end
			app.sounds:Play("Success")
		end
		if not entryFor(state, selectedUserId) and selectedUserId ~= localPlayer.UserId then
			selectedUserId = localPlayer.UserId
		end
		themeLabel.Text = themeLine(state)
		render()
	end

	local function updateHeader()
		if closed then
			return
		end
		local phase = PHASE_COPY[state.phase] or PHASE_COPY.INTERMISSION
		phaseLabel.Text = phase.label
		phaseLabel.TextColor3 = phase.color
		timerLabel.TextColor3 = phase.color
		local remaining = math.max(0, (state.endsAt or os.time()) - os.time())
		timerLabel.Text = formatClock(remaining)
		setTimerRing(remaining / math.max(1, PHASE_SECONDS[state.phase] or Config.Runway.StylingSeconds))
	end

	if not reduceMotion then
		TweenService:Create(overlay, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			BackgroundTransparency = 0.12,
		}):Play()
		TweenService:Create(modal, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = restingPosition,
		}):Play()
	end
	app.sounds:Play("PanelOpen")
	render()
	updateHeader()
	fetchLeaderboard(render)
	task.spawn(function()
		local lastRefresh = os.clock()
		while not closed and overlay.Parent do
			task.wait(0.5)
			updateHeader()
			-- Pushes are the primary update path; this low-frequency fetch heals a
			-- missed event after a network hiccup without polling every second.
			if os.clock() - lastRefresh >= 15 then
				lastRefresh = os.clock()
				local success, result = app:_Invoke(Network.Actions.GetRunwayState, {})
				if success and type(result) == "table" and result.roundId then
					if stateRevision(result) ~= stateRevision(state) then
						app.runwayRefresh(result)
					else
						-- Keep timing authoritative without rebuilding the 3D viewport
						-- when the healing poll found no visible state change.
						state.endsAt = result.endsAt
						state.serverTime = result.serverTime
					end
				end
			end
		end
	end)
	GuiService.SelectedObject = close
end

return RunwayHub
