--!strict

-- The v2 paintings are split into text-free surfaces and illustrations.
-- Gameplay, live scores, voting and avatar cameras remain native controls.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Factory = require(script.Parent.Factory)
local Skin = require(script.Parent.RedesignSkin)
local Motion = require(script.Parent.Motion)
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local HomeAssets = require(ReplicatedStorage:WaitForChild("HomeAssets"))
local DailyChallenge = require(ReplicatedStorage:WaitForChild("DailyChallenge"))
local Layouts = {}

local function balance(value: number): string
	if value >= 1000000 then return string.format("%.1fM", value/1000000) end
	if value >= 10000 then return string.format("%.1fK", value/1000) end
	return tostring(math.floor(value))
end

local function named(root: Instance, name: string): any
	for _, child in root:GetDescendants() do if child.Name == name then return child end end
	return nil
end

local function children(root: Instance, className: string): { any }
	local list = {}
	for _, child in root:GetChildren() do
		if child:IsA(className) and child.Name ~= "ForgeScreenArt" and child.Name ~= "RedesignArt" then
			table.insert(list, child)
		end
	end
	return list
end

local function removeLayout(parent: Instance)
	for _, node in parent:GetChildren() do
		if node:IsA("UIListLayout") or node:IsA("UIPadding") then node:Destroy() end
	end
end

local function text(parent: Instance, name: string, value: string, x: number, y: number,
	w: number, h: number, size: number, color: Color3?, centered: boolean?): TextLabel
	local label = Factory.Label(parent, value, UDim2.fromOffset(w, h), {
		Name = name, Position = UDim2.fromOffset(x, y), TextSize = size,
		Font = Theme.Fonts.Bold, Color = color or Theme.Colors.Text,
		AlignX = if centered then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
		Truncate = Enum.TextTruncate.AtEnd, ZIndex = (parent :: any).ZIndex + 2,
	})
	Skin.Sized(label, size)
	return label
end

local function surface(parent: Instance, slug: string, asset: string, x: number, y: number, w: number, h: number): Frame
	local panel = Factory.New("Frame", {
		Name = asset, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = Theme.Colors.PanelRaised, BorderSizePixel = 0,
		ZIndex = (parent :: any).ZIndex + 1, Parent = parent,
	})
	Factory.Corner(panel, 20)
	Factory.Stroke(panel, Theme.Colors.Gold, 0.4, 1.5)
	Skin.Skin(panel, slug, asset)
	return panel
end

local function control(app: any, parent: Instance, slug: string, name: string, asset: string,
	caption: string, x: number, y: number, w: number, h: number, size: number, action: () -> ()): TextButton
	local button = Factory.ImageButton(parent, caption, UDim2.fromOffset(w, h), UDim2.fromOffset(x, y), "mint")
	button.Name = name
	button.ZIndex = (parent :: any).ZIndex + 2
	button.TextColor3 = Theme.Colors.Text
	Skin.Sized(button, size)
	Skin.Skin(button, slug, asset)
	app:_BindButton(button)
	button.Activated:Connect(action)
	return button
end

local function captionIcon(button: TextButton, slug: string, asset: string, width: number)
	local icon = Skin.Decoration(button, slug, asset, 22, 14, 39, 39)
	if icon then
		local caption = Factory.LiftLabel(button)
		if caption then Skin.Place(caption, 66, 0, width-78, button.Size.Y.Offset) end
	end
end

local function nativeEllipse(parent: Instance, name: string, x: number, y: number, w: number, h: number,
	color: Color3, alpha: number, layer: number)
	local holder = Factory.New("Frame", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = layer, Active = false, Parent = parent })
	-- Flat native spans make a light ring beneath the real avatar. There is
	-- no painted example avatar, fake scenery or extra Roblox asset upload.
	for top = 0, h-1, 2 do
		local stripHeight = math.min(2, h-top)
		local normalizedY = (top+stripHeight/2-h/2)/(h/2)
		local span = w*math.sqrt(math.max(0, 1-normalizedY*normalizedY))
		Factory.New("Frame", { Position = UDim2.fromOffset((w-span)/2, top), Size = UDim2.fromOffset(span, stripHeight),
			BackgroundColor3 = color, BackgroundTransparency = alpha, BorderSizePixel = 0,
			ZIndex = layer, Active = false, Parent = holder })
	end
	return holder
end

local function modalCanvas(app: any, modal: GuiObject, slug: string)
	if modal:GetAttribute("V2ModalCanvas") then return end
	modal:SetAttribute("V2ModalCanvas", true)
	modal.Size = UDim2.fromOffset(1672, 941)
	local constraint = modal:FindFirstChildOfClass("UISizeConstraint")
	if constraint then constraint.MinSize = Vector2.zero; constraint.MaxSize = Vector2.new(1672, 941) end
	for _, name in { "Decal", "Gloss", "Shade", "TopAccent", "HeaderGlow", "AmbientLayer" } do
		local child = modal:FindFirstChild(name)
		if child and child:IsA("GuiObject") then child.Visible = false end
	end
	modal.BackgroundColor3 = Theme.Colors.Ink
	local backdrop = Factory.New("ImageLabel", {
		Name = "V2ModalBackdrop", Position = UDim2.new(), Size = UDim2.fromScale(1, 1),
		Image = "rbxassetid://" .. tostring(HomeAssets.Backdrop), BackgroundTransparency = 1,
		Active = false, ZIndex = modal.ZIndex, Parent = modal,
	})
	backdrop.Visible = not Theme.IsHighContrast
	surface(modal, slug, "MainShellArt", 45, 111, 1592, 789)
	local mark = Factory.New("ImageLabel", {
		Name = "ModalForgeLogo", Position = UDim2.fromOffset(77, 34), Size = UDim2.fromOffset(320, 228),
		BackgroundTransparency = 1, Image = "rbxassetid://" .. tostring(HomeAssets.LogoMark),
		ZIndex = modal.ZIndex + 2, Parent = modal,
	})
	mark.Visible = not Theme.IsHighContrast
	text(modal, "ForgeWord", "FORGE", 101, 82, 274, 80, 70, nil, true).Rotation = -5
	text(modal, "UGCWord", "UGC", 136, 145, 206, 76, 74, Theme.Colors.Cyan, true).Rotation = -5
	Motion.FitPanel(modal, function()
		return if app.state then tonumber(app.state.profile.settings.uiScale) or 1 else 1
	end)
end

local function modalHeader(app: any, modal: GuiObject, slug: string, close: GuiButton, closeModal: () -> ())
	if modal:FindFirstChild("ModalPrimaryNavigation") then return end
	local function openPage(page: string)
		closeModal()
		app:_SetStudioOpen(true)
		app:_OpenPage(page)
	end
	local nav = surface(modal, slug, "NavigationArt", 382, 137, 856, 74)
	nav.Name = "ModalPrimaryNavigation"
	for index, pair in { { "Home", "Home" }, { "Create", "Create" }, { "Market", "Discover" }, { "Games", "Play" } } do
		local x = ({ 382, 590, 814, 1019 })[index]
		local button = control(app, modal, slug, "ModalNav" .. pair[1], if index == 4 then "NavGamesArt" else "",
			pair[1], x, 139, if index == 4 then 218 else 208, 66, 27, function() openPage(pair[2]) end)
		captionIcon(button, slug, "Nav" .. pair[1] .. "Icon", if index == 4 then 218 else 208)
		if index ~= 4 then
			button.BackgroundTransparency = 1
			for _, name in { "Decal", "Gloss", "Shade" } do local child = button:FindFirstChild(name); if child then child.Visible = false end end
			local border = button:FindFirstChildOfClass("UIStroke")
			if border then border.Transparency = 1 end
		end
	end
	local items = control(app, modal, slug, "ModalMyItems", "MyItemsArt", "My Items", 1276, 139, 247, 67, 26,
		function() openPage("My Studio") end)
	captionIcon(items, slug, "MyItemsBag", 247)
	close.Parent = modal
	Skin.Place(close, 1544, 139, 69, 67); Skin.Sized(close, 32); Skin.Skin(close, slug, "CloseArt")
	close.ZIndex = modal.ZIndex + 4
	control(app, modal, slug, "ModalSettings", "HeaderSettingsArt", "⚙", 1572, 30, 65, 64, 34,
		function() openPage("Settings") end)
	local profile = app.state and app.state.profile or {}
	local tokens = (profile.tokens or 0) + (profile.bonusTokens or 0)
	local passes = (profile.retryCredits or {}).PriorityPass or 0
	surface(modal, slug, "TokenBalanceArt", 1144, 30, 199, 62)
	surface(modal, slug, "PassBalanceArt", 1359, 30, 193, 62)
	Skin.Decoration(modal, slug, "HeaderToken", 1154, 35, 47, 47)
	Skin.Decoration(modal, slug, "HeaderPass", 1370, 37, 44, 43)
	local tokenLabel = text(modal, "ModalTokenBalance", balance(tokens), 1204, 40, 85, 42, 30)
	local passLabel = text(modal, "ModalPassBalance", balance(passes), 1416, 40, 75, 42, 30)
	control(app, modal, slug, "ModalBuyTokens", "TokenBalancePlusArt", "+", 1289, 40, 44, 42, 30,
		function() task.spawn(function() app:_Invoke(Network.Actions.BuyTokens, {}) end) end)
	control(app, modal, slug, "ModalBuyPass", "PassBalancePlusArt", "+", 1498, 40, 44, 42, 30,
		function() app:_BuyPriorityPass() end)
	-- Do not overwrite Home's balance references while a modal is open.
	-- Follow the pushed profile locally; this never polls Roblox services.
	task.spawn(function()
		while modal.Parent do
			local current = app.state and app.state.profile or {}
			tokenLabel.Text = balance((current.tokens or 0) + (current.bonusTokens or 0))
			passLabel.Text = balance((current.retryCredits or {}).PriorityPass or 0)
			task.wait(0.5)
		end
	end)
end

function Layouts.Apply(app: any): boolean
	if not app.content or app.compact or app.activePage ~= "Play" then return false end
	local page = named(app.content, "PlayScroll")
	if not page then return false end
	Skin.Place(page, 0, 0, 1672, 941); removeLayout(page)
	page.ScrollBarThickness = 0; page.AutomaticCanvasSize = Enum.AutomaticSize.None; page.CanvasSize = UDim2.new()
	local stack = children(page, "Frame")[1]
	if not stack then return false end
	removeLayout(stack); stack.AutomaticSize = Enum.AutomaticSize.None
	Skin.Place(stack, 0, 0, 1672, 941)
	local cards = children(stack, "Frame")
	table.sort(cards, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	for index, card in cards do
		local x, w = ({ 68, 595, 1118 })[index], ({ 510, 504, 497 })[index]
		if not x then continue end
		Skin.Place(card, x, 339, w, 545)
		Skin.Skin(card, "games", "GamesDestination" .. index .. "Art")
		local labels = children(card, "TextLabel")
		table.sort(labels, function(a, b) return a.Position.Y.Offset < b.Position.Y.Offset end)
		if labels[1] then
			Skin.Place(labels[1], 119, 10, w-136, 73); Skin.Sized(labels[1], ({ 56, 44, 47 })[index])
			labels[1].Font = Theme.Fonts.Black
			labels[1].Text = ({ "Arcade", "Forge Runway", "AFK Lounge" })[index]
			labels[1].TextXAlignment = Enum.TextXAlignment.Center
		end
		Skin.Decoration(card, "games", "GamesDestination" .. index .. "Icon", 35, 16, 76, 76)
		if labels[2] then
			Skin.Place(labels[2], 20, 82, w-40, 42); Skin.Sized(labels[2], 24)
			labels[2].Font = Theme.Fonts.Bold
			labels[2].TextColor3 = Theme.Colors.Text
			labels[2].Text = ({ string.format("%d mini-games. Chase a new best.", #Config.Arcade.Games),
				"Style a look. Walk the runway.", "Relax in the lounge. Earn tokens." })[index]
			labels[2].TextXAlignment = Enum.TextXAlignment.Center
		end
		Skin.Decoration(card, "games", ({ "GamesArcadeSceneArt", "GamesRunwaySceneArt", "GamesLoungeSceneArt" })[index], 4, 115, w-7, 337)
		local action = children(card, "TextButton")[1]
		if action then
			Skin.Place(action, 20, 455, w-40, 75); Skin.Sized(action, 31)
			action.Text = ({ "Open Arcade  ›", "Open Runway  ›", "Enter Lounge  ›" })[index]
			-- The old gold destination card authored a dark foreground. The
			-- new cyan and purple actions need their own bright captions.
			action.TextColor3 = if index == 3 then Theme.Colors.Ink else Theme.Colors.Text
			Skin.Skin(action, "games", "GamesDestination" .. index .. "OpenArt")
		end
	end
	text(page, "GamesHeading", "Play & Earn", 80, 229, 585, 77, 76).Font = Theme.Fonts.Black
	Skin.Decoration(page, "games", "GamesHeadingSparkle1", 621, 240, 49, 49)
	Skin.Decoration(page, "games", "GamesHeadingSparkle2", 605, 275, 29, 29)
	text(page, "GamesSubtitle", "Take a break. Find your next challenge.", 124, 302, 650, 36, 28)
	local badge = surface(page, "games", "GamesFreeToPlayBadgeArt", 686, 261, 218, 47)
	Skin.Decoration(badge, "games", "GamesFreeToPlayBadgeIcon", 13, 8, 31, 31)
	text(badge, "FreeBadgeCaption", "Free to play", 45, 0, 164, 47, 23, nil, true)
	return true
end

local function arcade(app: any, modal: GuiObject, closeModal: () -> ())
	local hub = named(modal, "HubView")
	if not hub then return end
	local tiles = children(hub, "TextButton")
	table.sort(tiles, function(a, b)
		return if a.Position.Y.Offset == b.Position.Y.Offset then a.Position.X.Offset < b.Position.X.Offset
			else a.Position.Y.Offset < b.Position.Y.Offset
	end)
	if app.compact then
		for index, tile in tiles do
			local key = string.gsub(tile.Name, "Tile$", "")
			Skin.Skin(tile, "arcade", "ArcadeTile" .. key .. "Art")
		end
		return
	end
	modalCanvas(app, modal, "arcade")
	modalHeader(app, modal, "arcade", named(modal, "CloseButton"), closeModal)
	for _, name in { "HeaderIcon", "HeaderFlourish" } do
		local old = named(modal, name); if old then old.Visible = false end
	end
	local title = nil
	for _, label in children(modal, "TextLabel") do if label.Text == "ARCADE" then title = label end end
	if title then
		Skin.Place(title, 241, 234, 452, 82); Skin.Sized(title, 78); title.Text = "Arcade"
		title.Font = Theme.Fonts.Black
		-- The loaded hero painting is created later than these native labels.
		-- Keep its surface below the title rather than relying on sibling order.
		title.ZIndex = modal.ZIndex + 5
	end
	local subtitle = named(modal, "ArcadeTitle")
	if subtitle then
		Skin.Place(subtitle, 241, 319, 452, 39); Skin.Sized(subtitle, 25)
		subtitle.ZIndex = modal.ZIndex + 5
	end
	local hero = surface(modal, "arcade", "ArcadeHeroPanelArt", 65, 229, 642, 140)
	hero.ZIndex = modal.ZIndex + 2
	Skin.Decoration(hero, "arcade", "ArcadeController", 8, 9, 163, 117)
	Skin.Decoration(hero, "arcade", "ArcadeCrown", 443, 6, 70, 62)
	local reward = named(modal, "RewardBanner")
	reward.ZIndex = modal.ZIndex + 2
	Skin.Place(reward, 722, 229, 487, 140); Skin.Skin(reward, "arcade", "WeeklyPrizePanelArt")
	for _, child in children(reward, "GuiObject") do child.Visible = false end
	Skin.Decoration(reward, "arcade", "ArcadeTrophy", 11, 14, 89, 112)
	text(reward, "WeeklyCaption", "Weekly top 3", 111, 10, 349, 34, 28)
	for index, amount in Config.Arcade.WeeklyRewards do
		local x = 109 + (index-1)*126
		Skin.Decoration(reward, "arcade", "WeeklyMedal" .. index, x-2, 54, 44, 53)
		Skin.Decoration(reward, "arcade", "ArcadeCoins" .. index, x+26, 95, 70, 34)
		text(reward, "Prize" .. index, tostring(amount), x+48, 53, 76, 42, 24, Theme.Colors.Gold)
	end
	local daily = surface(modal, "arcade", "DailyChallengePanelArt", 1224, 229, 388, 140)
	Skin.Decoration(daily, "arcade", "ArcadeCalendar", 16, 11, 88, 87)
	text(daily, "DailyTitle", "Daily challenges", 111, 12, 264, 34, 24)
	text(daily, "DailyInstruction", "Beat today's target", 111, 49, 264, 30, 20)
	text(daily, "DailyReward", "+" .. tostring(Config.Arcade.DailyChallengeBonusTokens) .. " bonus tokens / game", 111, 77, 270, 27, 17, Theme.Colors.Gold)
	text(daily, "DailyPerGame", "Each target is shown on its card", 16, 110, 358, 23, 15, Theme.Colors.TextMuted)
	local function hubVisibility() hero.Visible = hub.Visible; daily.Visible = hub.Visible end
	hub:GetPropertyChangedSignal("Visible"):Connect(hubVisibility); hubVisibility()
	local rule = named(modal, "HeaderRule"); if rule then Skin.Place(rule, 65, 377, 1547, 1) end
	Skin.Place(hub, 64, 382, 1548, 506)
	hub.ZIndex = modal.ZIndex + 3
	hub.AutomaticCanvasSize = Enum.AutomaticSize.None; hub.CanvasSize = UDim2.new(); hub.ScrollBarThickness = 0
	for _, child in children(hub, "Frame") do child.Visible = false end
	for index, tile in tiles do
		local column, row = (index-1)%4, math.floor((index-1)/4)
		local x, y = ({ 0, 392, 782, 1170 })[column+1], ({ 0, 176, 347 })[row+1]
		local width, height = ({ 378, 376, 375, 378 })[column+1], ({ 162, 158, 159 })[row+1]
		Skin.Place(tile, x, y, width, height)
		local key = string.gsub(tile.Name, "Tile$", "")
		Skin.Skin(tile, "arcade", "ArcadeTile" .. key .. "Art")
		local badge = tile:FindFirstChild("IconBadge"); if badge then badge.Visible = false end
		local inner = tile:FindFirstChild("InnerRule"); if inner then inner.Visible = false end
		local shine = tile:FindFirstChild("ShineMask"); if shine then shine.Visible = false end
		Skin.Decoration(tile, "arcade", "Arcade" .. key, 2, 2, 181, height-5)
		local titleLabel = tile:FindFirstChild("GameTitle")
		if titleLabel then Skin.Place(titleLabel, 196, 10, width-206, 42); Skin.Sized(titleLabel, 26) end
		local description = tile:FindFirstChild("GameDescription")
		if description then
			description.Visible = key == "Leaderboard"
			Skin.Place(description, 190, 43, width-204, 48); Skin.Sized(description, 17)
		end
		for _, label in children(tile, "TextLabel") do
			if label.Name ~= "GameTitle" and label.Name ~= "GameDescription" and label.Name ~= "BestScore" then label.Visible = false end
		end
		local best = tile:FindFirstChild("BestScore")
		if best then
			best:SetAttribute("BestPrefix", true)
			if not string.find(best.Text, "Best:", 1, true) then best.Text = "Best: " .. best.Text end
			Skin.Place(best, 196, 50, width-206, 32); Skin.Sized(best, 22)
		end
		local challenge = tile:FindFirstChild("ChallengeChip")
		if challenge then
			Skin.Place(challenge, 7, height-26, 174, 22)
			challenge.AnchorPoint = Vector2.zero
			for _, label in children(challenge, "TextLabel") do Skin.Sized(label, 18) end
		end
		local play = tile:FindFirstChild("PlayPill")
		if play then
			Skin.Place(play, 193, 92, width-207, if key == "Leaderboard" then 52 else 58)
			Skin.Sized(play, if key == "Leaderboard" then 20 else 27)
			play.Text = if key == "Leaderboard" then "View rankings" else "Play"
			play.TextColor3 = if key == "NeonSnake" or key == "BrickBreaker" or key == "EchoMatch"
				then Theme.Colors.Ink else Theme.Colors.Text
			Skin.Skin(play, "arcade", if key == "Leaderboard" then "OpenLeaderboardsArt" else "Play" .. key .. "Art")
		end
	end
	for _, name in { "GameView", "LeaderboardView", "ViewTransition" } do
		local view = named(modal, name)
		if view then
			-- All view changes stay beneath the shared title and navigation.
			Skin.Place(view, 65, 377, 1547, 511)
			view.ZIndex = if name == "ViewTransition" then modal.ZIndex+8 else modal.ZIndex+3
		end
	end
end

local function runway(app: any, modal: GuiObject, closeModal: () -> ())
	local lineup, hero, weekly = named(modal, "Participants"), named(modal, "RoundHero"), named(modal, "WeeklyStandings")
	if not lineup or not hero or not weekly then return end
	if app.compact then
		Skin.Skin(lineup, "runway", "LineupPanelArt"); Skin.Skin(hero, "runway", "AvatarPreviewPanelArt")
		Skin.Skin(weekly, "runway", "WeeklyStandingsPanelArt")
		return
	end
	modalCanvas(app, modal, "runway")
	modalHeader(app, modal, "runway", named(modal, "CloseButton"), closeModal)
	local header = named(modal, "Header")
	header.ZIndex = modal.ZIndex + 3
	Skin.Place(header, 0, 218, 1672, 119); header.BackgroundTransparency = 1
	for _, child in children(header, "Frame") do
		if child.Name ~= "TimerRing" and child.Name ~= "CurrentThemeBannerArt"
			and string.sub(child.Name, 1, 12) ~= "V2Decoration" then child.Visible = false end
	end
	for _, child in children(header, "ImageLabel") do child.Visible = false end
	Skin.Decoration(header, "runway", "RunwayTitleCrown", 61, 7, 108, 110)
	local title = named(header, "RunwayTitle")
	Skin.Place(title, 171, 16, 495, 80); Skin.Sized(title, 60); title.Text = "Forge Runway"
	local theme = named(header, "RunwayTheme")
	Skin.Place(theme, 824, 58, 335, 50); Skin.Sized(theme, 34)
	theme.Text = string.gsub(theme.Text, "Tonight's theme · ", "")
	local themePanel = header:FindFirstChild("CurrentThemeBannerArt")
		or surface(header, "runway", "CurrentThemeBannerArt", 744, 6, 421, 109)
	theme.Parent = themePanel; Skin.Place(theme, 110, 49, 299, 50); theme.ZIndex = themePanel.ZIndex+2
	Skin.Decoration(themePanel, "runway", "RunwayThemeCrown", 18, 24, 78, 80)
	if not themePanel:FindFirstChild("CurrentThemeCaption") then text(themePanel, "CurrentThemeCaption", "Current Theme", 110, 7, 298, 30, 21) end
	Skin.Decoration(header, "runway", "RunwayThemeLeftCrystals", 670, 8, 124, 112)
	Skin.Decoration(header, "runway", "RunwayThemeRightCrystals", 1152, 6, 82, 112)
	Skin.Decoration(header, "runway", "RunwayTimerCrystals", 1538, 6, 82, 112)
	local phase = named(header, "RunwayPhase")
	Skin.Place(phase, 1280, 16, 256, 40); Skin.Sized(phase, 21)
	phase.TextXAlignment = Enum.TextXAlignment.Center
	Skin.Skin(phase, "runway", "RunwayPhaseIndicatorArt")
	Skin.Decoration(phase, "runway", "PhaseHanger", 12, 5, 34, 29)
	local phaseCaption = Factory.LiftLabel(phase)
	if phaseCaption then Skin.Place(phaseCaption, 48, 0, 197, 40) end
	local timer = named(header, "TimerRing")
	Skin.Place(timer, 1335, 61, 201, 50)
	for _, child in children(timer, "GuiObject") do child.Visible = child.Name == "RunwayClock" end
	local clock = named(timer, "RunwayClock")
	Skin.Decoration(timer, "runway", "CountdownClock", 5, 1, 45, 48)
	Skin.Place(clock, 54, 0, 147, 50); Skin.Sized(clock, 39)
	if not header:FindFirstChild("RunwaySubheading") then text(header, "RunwaySubheading", "Style it. Lock it. Own the stage.", 184, 84, 540, 32, 27) end
	local body = named(modal, "RunwayContent")
	body.ZIndex = modal.ZIndex + 3
	Skin.Place(body, 0, 348, 1672, 540); removeLayout(body)
	body.ScrollBarThickness = 5
	local stack = named(body, "Stack"); removeLayout(stack)
	stack.AutomaticSize = Enum.AutomaticSize.None
	local extraCards = {}
	for _, node in stack:GetDescendants() do
		if node.Name == "FirstLookJourney" or node.Name == "RunwayForgeActivity" then table.insert(extraCards, node) end
	end
	lineup.Parent = stack; hero.Parent = stack; weekly.Parent = stack
	Skin.Place(lineup, 61, 0, 501, 534); Skin.Skin(lineup, "runway", "LineupPanelArt")
	Skin.Place(hero, 577, 0, 601, 535); Skin.Skin(hero, "runway", "AvatarPreviewPanelArt")
	Skin.Place(weekly, 1194, 0, 426, 535); Skin.Skin(weekly, "runway", "WeeklyStandingsPanelArt")
	local extraY = 553
	for _, card in extraCards do
		card.Parent = stack
		if card.Name == "FirstLookJourney" then
			local steps = {}
			for _, row in children(card, "Frame") do if row.Name == "JourneyStep" then table.insert(steps, row) end end
			if #steps > 0 then
				Skin.Place(card, 61, extraY, 501, 117+#steps*58)
				local heading, count, help = named(card, "JourneyTitle"), named(card, "JourneyCount"), named(card, "JourneyHelp")
				Skin.Place(heading, 21, 14, 353, 35); Skin.Sized(heading, 26)
				Skin.Place(count, 378, 14, 102, 35); Skin.Sized(count, 26)
				Skin.Place(help, 21, 53, 459, 56); Skin.Sized(help, 20)
				for index, row in steps do
					Skin.Place(row, 17, 111+(index-1)*58, 467, 49)
					local icon, caption, prize = named(row, "JourneyStepIcon"), named(row, "JourneyStepName"), named(row, "JourneyStepReward")
					Skin.Place(icon, 6, 0, 43, 49); Skin.Sized(icon, 26)
					Skin.Place(caption, 53, 0, 337, 49); Skin.Sized(caption, 22)
					Skin.Place(prize, 392, 0, 65, 49); Skin.Sized(prize, 20)
				end
			else Skin.Place(card, 61, extraY, 501, card.Size.Y.Offset) end
		elseif card.Name == "RunwayForgeActivity" then
			Skin.Place(card, 61, extraY, 501, 119)
			local heading, help, action = named(card, "ForgeActivityTitle"), named(card, "ForgeActivityHelp"), named(card, "ViewForgeActivity")
			if heading then Skin.Place(heading, 21, 12, 298, 44); Skin.Sized(heading, 22); heading.TextWrapped = true end
			if help then Skin.Place(help, 21, 60, 298, 48); Skin.Sized(help, 20); help.TextWrapped = true end
			if action then Skin.Place(action, 334, 30, 148, 64); Skin.Sized(action, 21); action.TextWrapped = true end
		else Skin.Place(card, 61, extraY, 501, card.Size.Y.Offset) end
		extraY += card.Size.Y.Offset + 18
	end
	Skin.Place(stack, 0, 0, 1672, math.max(540, extraY))
	for _, child in children(stack, "Frame") do
		if child ~= lineup and child ~= hero and child ~= weekly and not table.find(extraCards, child) then child:Destroy() end
	end
	for _, panel in { lineup, hero, weekly } do
		local banner = panel:FindFirstChild("SectionBanner")
		if banner then
			Skin.Place(banner, 20, 10, panel.Size.X.Offset-40, 44); Skin.Sized(banner, 31)
			banner.BackgroundTransparency = 1
			banner.TextColor3 = Theme.Colors.Text
			local decal = banner:FindFirstChild("Decal"); if decal then decal.Visible = false end
			local border = banner:FindFirstChildOfClass("UIStroke"); if border then border.Transparency = 1 end
			for _, name in { "Gloss", "Shade" } do local overlay = banner:FindFirstChild(name); if overlay then overlay.Visible = false end end
		end
	end
	local emptyLineup = lineup:FindFirstChild("RunwayLineupEmpty")
	if emptyLineup then
		local crown = Skin.Decoration(lineup, "runway", "RunwayTitleCrown", 188, 83, 125, 127)
		if crown and crown:FindFirstChild("RedesignArt") then Factory.Corner(crown.RedesignArt, 22) end
		Skin.Place(emptyLineup, 30, 220, 441, 77); Skin.Sized(emptyLineup, 30)
		emptyLineup.Text = "The spotlight is waiting"
		emptyLineup.TextColor3 = Theme.Colors.Text
		emptyLineup.Font = Theme.Fonts.Black; emptyLineup.TextWrapped = true
		emptyLineup.ZIndex = lineup.ZIndex+3
		local hint = text(lineup, "RunwayLineupEmptyHelp", "Join the round, style your avatar, then lock in your look.", 39, 304, 423, 84, 23, Theme.Colors.TextMuted, true)
		hint.TextWrapped = true; hint.TextTruncate = Enum.TextTruncate.None
		text(lineup, "RunwayLineupEmptyNote", "Live players appear here when they join.", 36, 433, 429, 57, 20, Theme.Colors.Cyan, true).TextWrapped = true
	end
	-- Entrants overflow inside their panel; all server entries stay reachable.
	local entries = children(lineup, "TextButton")
	local scroll = Factory.New("ScrollingFrame", {
		Name = "LiveRunwayLineup", Position = UDim2.fromOffset(7, 64), Size = UDim2.fromOffset(486, 439),
		BackgroundTransparency = 1, BorderSizePixel = 0, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ScrollBarThickness = 4, ZIndex = lineup.ZIndex+2, Parent = lineup,
	})
	for _, row in entries do
		local index = row:GetAttribute("RunwayEntryIndex") or 1
		row.Parent = scroll; Skin.Place(row, 0, (index-1)*110, 486, 103)
		Skin.Skin(row, "runway", "EntrantRow" .. tostring((index-1)%4+1) .. "Art")
		if row:GetAttribute("RunwaySelected") then
			local outline = Factory.Stroke(row, Theme.Colors.Gold, 0, 3)
			outline.Name = "SelectedLookOutline"
		end
		local face, name, status = row:FindFirstChild("EntryAvatar"), row:FindFirstChild("EntryName"), row:FindFirstChild("EntryStatus")
		if face then Skin.Place(face, 61, 8, 81, 86) end
		if name then Skin.Place(name, 163, 15, 144, 31); Skin.Sized(name, 24) end
		if status then Skin.Place(status, 164, 52, 143, 29); Skin.Sized(status, 20) end
		local view = row:FindFirstChild("ViewLook")
		if view then
			view.Visible = true; Skin.Place(view, 315, 24, 161, 59); Skin.Sized(view, 20)
			Skin.Skin(view, "runway", "ViewLookPlayer" .. tostring((index-1)%4+1) .. "Art")
		end
		local vote = row:FindFirstChild("VoteOrLeave")
		if vote then
			vote.Visible = vote.Active == true or vote.Text == "✓" or vote.Text == "Voted"
			-- Voting and viewing share a clear action column. A short vote
			-- button underneath the player's status was too small after fit.
			Skin.Place(vote, 315, 55, 161, 41); Skin.Sized(vote, 20)
			if vote.Visible and view then Skin.Place(view, 315, 7, 161, 43); Skin.Sized(view, 20) end
		end
	end
	local preview = named(hero, "SelectedLook")
	Skin.Place(preview, 12, 55, 577, 300)
	preview.BackgroundTransparency = 1
	local stage = Factory.New("Frame", { Name = "V2RunwayAvatarStage", Position = UDim2.fromOffset(12, 55),
		Size = UDim2.fromOffset(577, 300), BackgroundColor3 = if Theme.IsHighContrast then Theme.Colors.Ink else Color3.new(1,1,1),
		BorderSizePixel = 0, ClipsDescendants = true, Active = false, ZIndex = hero.ZIndex+1, Parent = hero })
	Factory.Corner(stage, 16)
	if not Theme.IsHighContrast then
		Factory.Gradient(stage, { Color3.fromRGB(17, 14, 45), Color3.fromRGB(27, 30, 76), Color3.fromRGB(14, 62, 109) }, 90)
		nativeEllipse(stage, "HologramHalo", 4, 205, 569, 90, Color3.fromRGB(24, 162, 247), 0.85, stage.ZIndex)
		nativeEllipse(stage, "HologramRim", 87, 239, 403, 51, Color3.fromRGB(57, 211, 255), 0.12, stage.ZIndex)
		nativeEllipse(stage, "HologramCentre", 106, 245, 365, 33, Color3.fromRGB(13, 51, 107), 0.04, stage.ZIndex)
	end
	preview.ZIndex = stage.ZIndex+1
	local previewName = preview:FindFirstChild("SelectedLookName")
	if previewName then Skin.Place(previewName, 16, 11, 363, 35); Skin.Sized(previewName, 23); previewName.ZIndex = preview.ZIndex+2 end
	local heroBanner = hero:FindFirstChild("SectionBanner")
	if heroBanner then Skin.Place(heroBanner, 20, 10, 391, 44) end
	local rotateHint = surface(hero, "runway", "DragInstructionArt", 436, 7, 155, 46)
	Skin.Decoration(rotateHint, "runway", "RotateMouseIcon", 10, 8, 24, 28)
	text(rotateHint, "RunwayRotateCaption", "Drag to rotate", 39, 2, 109, 42, 18, Theme.Colors.Text, true).TextWrapped = true
	local reset = named(preview, "ResetCamera")
	reset.Parent = hero; Skin.Place(reset, 440, 91, 149, 44); Skin.Sized(reset, 16)
	reset.Text = "Reset camera"; Skin.Skin(reset, "runway", "ResetCameraArt")
	reset.ZIndex = hero.ZIndex+4
	local phasePill = hero:FindFirstChild("LookPhase"); if phasePill then phasePill.Visible = false end
	local instruction = hero:FindFirstChild("LookInstruction")
	if instruction then Skin.Place(instruction, 14, 495, 573, 36); Skin.Sized(instruction, 16) end
	local xp = hero:FindFirstChild("CreatorXp")
	if xp then Skin.Place(xp, 344, 369, 208, 31); Skin.Sized(xp, 21); xp.TextXAlignment = Enum.TextXAlignment.Right; xp.ZIndex = hero.ZIndex+3 end
	local level = hero:FindFirstChild("CreatorLevel")
	if level then Skin.Place(level, 26, 369, 300, 31); Skin.Sized(level, 21); level.ZIndex = hero.ZIndex+3 end
	Skin.Decoration(hero, "runway", "CreatorXpStripArt", 16, 368, 569, 39)
	Skin.Decoration(hero, "runway", "CreatorXpCrown", 552, 369, 30, 29)
	local track = hero:FindFirstChild("CreatorXpTrack")
	if track then
		Skin.Place(track, 24, 406, 552, 7); track.ZIndex = hero.ZIndex+3
		for _, fill in children(track, "Frame") do fill.ZIndex = track.ZIndex+1 end
	end
	-- Profile details get their own middle-column card directly below the
	-- avatar. Long journey cards in the left column no longer push these
	-- labels into an unrelated blank area far down the scroll.
	local summary: Frame? = nil
	for _, spec in { { "CreatorTitle", 51, 34, 26 }, { "RunwayStats", 89, 34, 22 },
		{ "DailyEncore", 126, 51, 21 }, { "EquippedLookName", 182, 34, 24 }, { "EquippedLookHelp", 218, 45, 20 } } do
		local node = hero:FindFirstChild(spec[1])
		if node then
			if not summary then
				summary = surface(stack, "runway", "AvatarPreviewPanelArt", 577, 553, 601, 278)
				summary.Name = "CreatorSummaryPanel"
				text(summary, "CreatorSummaryHeading", "Your Creator Progress", 24, 9, 553, 37, 28, Theme.Colors.Gold)
			end
			node.Parent = summary
			Skin.Place(node, 24, spec[2], 553, spec[3]); Skin.Sized(node, spec[4])
			node.ZIndex = summary.ZIndex+3; node.TextWrapped = true; node.TextTruncate = Enum.TextTruncate.None
		end
	end
	if summary then extraY = math.max(extraY, 849) end
	Skin.Place(stack, 0, 0, 1672, math.max(540, extraY))
	for _, spec in { { "OpenAvatarLab", "OpenAvatarLabArt", 8, 420, 151, 73, 17 },
		{ "LockLook", "LockInLookArt", 171, 416, 260, 71, 26 },
		{ "InviteRunwayFriends", "InviteRunwayFriendsArt", 443, 420, 151, 73, 17 } } do
		local button = hero:FindFirstChild(spec[1])
		if button then Skin.Place(button, spec[3], spec[4], spec[5], spec[6]); Skin.Sized(button, spec[7]); Skin.Skin(button, "runway", spec[2]) end
	end
	local refresh = weekly:FindFirstChild("RefreshWeekly")
	Skin.Place(refresh, 284, 10, 132, 42); Skin.Sized(refresh, 19); Skin.Skin(refresh, "runway", "RefreshWeeklyArt")
	local weeklyBanner = weekly:FindFirstChild("SectionBanner")
	if weeklyBanner then
		Skin.Place(weeklyBanner, 17, 10, 253, 44); Skin.Sized(weeklyBanner, 27)
		weeklyBanner.Text = "Weekly Spotlight"
	end
	for _, label in children(weekly, "TextLabel") do
		if label.Name ~= "SectionBanner" then
			local y = label.Position.Y.Offset
			if label.Name == "WeeklyPointsHelp" or label.Name == "WeeklyRewardsHelp" or y == 36 or y == 53 then label.Visible = false
			elseif label.Name == "WeeklyOwnSummary" or y == 301 then Skin.Place(label, 12, 377, 402, 24); Skin.Sized(label, 18)
			elseif label.Name == "RunwayWeeklyEmpty" or label.Name == "RunwayWeeklyLoading" then
				Skin.Place(label, 25, 192, 376, 83); Skin.Sized(label, 27)
				label.TextWrapped = true; label.TextTruncate = Enum.TextTruncate.None
				label.TextColor3 = Theme.Colors.Text; label.ZIndex = weekly.ZIndex+3
			else Skin.Place(label, 16, 76, 394, 88); Skin.Sized(label, 20) end
		end
	end
	if weekly:FindFirstChild("RunwayWeeklyEmpty") or weekly:FindFirstChild("RunwayWeeklyLoading") then
		local crown = Skin.Decoration(weekly, "runway", "RunwayTitleCrown", 161, 74, 104, 106)
		if crown and crown:FindFirstChild("RedesignArt") then Factory.Corner(crown.RedesignArt, 20) end
		local help = text(weekly, "WeeklyEmptyHelp", "Finish rounds and cast votes to earn real weekly points.", 28, 281, 370, 73, 22, Theme.Colors.TextMuted, true)
		help.TextWrapped = true; help.TextTruncate = Enum.TextTruncate.None
	end
	for _, row in children(weekly, "Frame") do
		if row.Name ~= "WeeklyRow" then continue end
		local index = row:GetAttribute("WeeklyEntryIndex") or 1
		Skin.Place(row, 8, 63+(index-1)*65.5, 408, 59)
		Skin.Skin(row, "runway", "WeeklyRow" .. index .. "Art")
		local rank = row:FindFirstChild("WeeklyRank"); Skin.Place(rank, 14, 10, 36, 39)
		local avatar = row:FindFirstChild("WeeklyAvatar"); avatar.Visible = true; Skin.Place(avatar, 70, 3, 60, 55)
		local name = row:FindFirstChild("WeeklyName"); Skin.Place(name, 148, 9, 155, 40); Skin.Sized(name, 20)
		local score = row:FindFirstChild("WeeklyScore"); Skin.Place(score, 310, 9, 87, 40); Skin.Sized(score, 20)
	end
	local rewards = surface(weekly, "runway", "WeeklyCreatorXpPanelArt", 6, 398, 415, 129)
	Skin.Decoration(rewards, "runway", "RunwayWeeklyRewardArt", 7, 4, 166, 121)
	text(rewards, "WeeklyXpTitle", "Weekly Creator XP", 172, 12, 237, 36, 24)
	text(rewards, "WeeklyXpRewards", string.format("1st +%d · 2nd +%d · 3rd +%d", table.unpack(Config.Runway.WeeklyPlacementXP)),
		172, 50, 237, 45, 19, Theme.Colors.Gold).TextWrapped = true
	text(rewards, "WeeklyXpHelp", "Weekly spotlight rewards", 172, 97, 237, 27, 18, Theme.Colors.TextMuted)
end

function Layouts.Modal(app: any, modal: GuiObject, kind: string, closeModal: () -> ())
	if kind == "Arcade" then arcade(app, modal, closeModal)
	elseif kind == "Runway" then runway(app, modal, closeModal) end
end

return Layouts
