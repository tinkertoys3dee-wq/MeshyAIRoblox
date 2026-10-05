--!strict

-- Live controls over individually extracted, text-free forge-ugc.svg artwork.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local HomeAssets = require(ReplicatedStorage:WaitForChild("HomeAssets"))
local Factory = require(script.Parent.Factory)
local Motion = require(script.Parent.Motion)
local HomeEffects = require(script.Parent.HomeEffects)

local HomeScreen = {}
local WHITE = Color3.fromRGB(248, 250, 255)
local MUTED = Color3.fromRGB(174, 188, 215)
local INK = Color3.fromRGB(15, 24, 44)
local BLUE = Color3.fromRGB(0, 202, 255)
local VIOLET = Color3.fromRGB(189, 75, 255)
local GOLD = Color3.fromRGB(255, 203, 66)

local function frame(parent: Instance, name: string, x: number, y: number, w: number, h: number): Frame
	return Factory.New("Frame", {
		Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1, BorderSizePixel = 0, Parent = parent,
	})
end

local function image(parent: Instance, key: string, x: number, y: number, w: number, h: number, z: number?): ImageLabel?
	local id = (HomeAssets :: any)[key] or 0
	if id <= 0 then return nil end
	return Factory.New("ImageLabel", {
		Name = key .. "Art", Image = "rbxassetid://" .. tostring(id),
		Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
		ScaleType = Enum.ScaleType.Stretch, ZIndex = z or 1, Parent = parent,
	})
end

local function label(parent: Instance, text: string, x: number, y: number, w: number, h: number,
	size: number, bold: boolean?, color: Color3?, centered: boolean?): TextLabel
	return Factory.New("TextLabel", {
		Name = "Caption", Text = text, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1, BorderSizePixel = 0, TextColor3 = color or WHITE,
		Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham,
		TextSize = size, TextWrapped = true, TextXAlignment = if centered then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 4, Parent = parent,
	})
end

local function button(app: any, parent: Instance, name: string, text: string,
	x: number, y: number, w: number, h: number, action: () -> ()): TextButton
	local control = Factory.New("TextButton", {
		Name = name, Text = text, TextTransparency = 1, BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		AutoButtonColor = false, BorderSizePixel = 0, Selectable = true, ZIndex = 3, Parent = parent,
	})
	app:_BindButton(control)
	control.Activated:Connect(action)
	return control
end

local function fallbackSurface(target: GuiObject, color: Color3, edge: Color3, radius: number)
	target.BackgroundTransparency = 0
	target.BackgroundColor3 = color
	Factory.Corner(target, radius)
	Factory.Stroke(target, edge, 0.25, 1.6)
end

local function coverFallback(target: GuiObject, art: ImageLabel?)
	if not art then return end
	local function update()
		if not art.IsLoaded then return end
		target.BackgroundTransparency = 1
		local stroke = target:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Transparency = 1 end
		local gradient = target:FindFirstChildOfClass("UIGradient")
		if gradient then gradient.Enabled = false end
	end
	art:GetPropertyChangedSignal("IsLoaded"):Connect(update)
	update()
end

local function closeModal(app: any)
	if app.homeModal then
		app.homeModal:Destroy()
		app.homeModal = nil
	end
end

local function modal(app: any, title: string): (Frame, ScrollingFrame)
	closeModal(app)
	local overlay = Factory.New("Frame", {
		Name = "HomeDetails", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.3, BorderSizePixel = 0, Active = true, ZIndex = 240, Parent = app.gui,
	})
	app.homeModal = overlay
	local panel = Factory.New("Frame", {
		Name = "DetailsPanel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.82), BackgroundColor3 = INK, BorderSizePixel = 0,
		ZIndex = 241, Parent = overlay,
	})
	Factory.New("UISizeConstraint", { MaxSize = Vector2.new(580, 560), Parent = panel })
	Factory.Corner(panel, 22)
	Factory.Stroke(panel, BLUE, 0.35, 1.5)
	local heading = label(panel, title, 20, 12, 450, 40, 23, true)
	heading.Size = UDim2.new(1, -84, 0, 40)
	heading.ZIndex = 243
	local close = button(app, panel, "CloseDetails", "Close", 0, 0, 44, 44, function() closeModal(app) end)
	close.Position = UDim2.new(1, -58, 0, 10)
	close.ZIndex = 243
	local cross = label(close, "×", 0, 0, 44, 44, 28, true, WHITE, true)
	cross.ZIndex = 244
	local body = Factory.New("ScrollingFrame", {
		Name = "DetailsScroll", Position = UDim2.fromOffset(20, 68), Size = UDim2.new(1, -40, 1, -88),
		BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5,
		ScrollBarImageColor3 = BLUE, ZIndex = 242, Parent = panel,
	})
	Factory.List(body, Enum.FillDirection.Vertical, 12)
	Motion.AutoFocus(close)
	local connection = UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
			closeModal(app)
		end
	end)
	overlay.Destroying:Connect(function() connection:Disconnect() end)
	return panel, body
end

local function paragraph(parent: Instance, text: string, height: number?): TextLabel
	local result = label(parent, text, 0, 0, 1, height or 68, 15, false, MUTED)
	result.Size = UDim2.new(1, -8, 0, height or 68)
	result.TextYAlignment = Enum.TextYAlignment.Top
	result.ZIndex = 243
	return result
end

local function modalAction(app: any, parent: Instance, text: string, action: () -> ()): TextButton
	local control = button(app, parent, "DetailAction", text, 0, 0, 1, 48, action)
	control.Size = UDim2.new(1, -8, 0, 48)
	control.ZIndex = 243
	fallbackSurface(control, Color3.fromRGB(7, 77, 141), BLUE, 13)
	local caption = label(control, text, 10, 0, 1, 48, 16, true, WHITE, true)
	caption.Size = UDim2.new(1, -20, 1, 0)
	caption.ZIndex = 244
	return control
end

local function showMissions(app: any)
	local _, body = modal(app, "Daily Missions")
	paragraph(body, "Complete these activities to earn bonus tokens. Rewards are added automatically.", 48)
	local done = (app.state.questState and app.state.questState.questsDone) or {}
	for _, quest in Config.Retention.Quests do
		local destination = if quest.key == "TRY_STYLE" then "Avatar Lab" else "Play"
		modalAction(app, body, (if done[quest.key] then "✓ " else "") .. quest.label .. "  ·  +" .. quest.tokens, function()
			closeModal(app)
			app:_OpenPage(destination)
		end)
	end
	paragraph(body, string.format("Finish all three for +%d extra bonus tokens. Bonus tokens can fund Priority Passes.", Config.Retention.QuestClearBonusTokens), 60)
end

local function showRewards(app: any)
	local _, body = modal(app, "Daily Rewards")
	local brief = app.state.dailyBrief or {}
	paragraph(body, string.format("Your streak: %d day%s. Daily rewards are credited when you join.", brief.streak or 0,
		if brief.streak == 1 then "" else "s"), 48)
	for index, reward in Config.Retention.DailyStreakTokens do
		local current = brief.rewardDay == index
		local row = paragraph(body, string.format("%sDay %d  ·  +%d bonus tokens", if current then "✓ " else "", index, reward), 26)
		row.TextColor3 = if current then GOLD else MUTED
	end
	paragraph(body, string.format("Next check-in: +%d bonus tokens. Bonus tokens can fund Priority Passes.", brief.nextDailyTokens or 0), 48)
	modalAction(app, body, "View Missions", function() showMissions(app) end)
end

local function showWallet(app: any)
	local _, body = modal(app, "Forge Tokens")
	local profile = app.state.profile
	paragraph(body, string.format("%d spendable tokens\n%d bonus tokens for Priority Passes", profile.tokens or 0, profile.bonusTokens or 0), 56)
	paragraph(body, "Earn tokens in the AFK Lounge. Roblox shows the price before any purchase.", 52)
	modalAction(app, body, "Open Token Lounge", function()
		closeModal(app)
		app:_SetStudioOpen(false)
		task.spawn(function() app:_OpenAfkLounge() end)
	end)
	modalAction(app, body, "Buy Tokens", function()
		task.spawn(function() app:_Invoke(Network.Actions.BuyTokens, {}) end)
	end)
	modalAction(app, body, "Get a Priority Pass", function() closeModal(app); app:_BuyPriorityPass() end)
end

local function showCodes(app: any)
	local _, body = modal(app, "UGC Item Codes")
	paragraph(body, "Enter a Roblox catalog item ID to try it on for free. Choose its category below. Your saved creations are in My Items.", 72)
	local entry = Factory.New("TextBox", {
		Name = "CatalogItemId", Size = UDim2.new(1, -8, 0, 48), Text = "", PlaceholderText = "Roblox catalog item ID",
		ClearTextOnFocus = false, BackgroundColor3 = Color3.fromRGB(27, 40, 65), BorderSizePixel = 0,
		TextColor3 = WHITE, PlaceholderColor3 = MUTED, Font = Enum.Font.Gotham, TextSize = 18, ZIndex = 243, Parent = body,
	})
	Factory.Corner(entry, 12)
	local categories = { "Hat", "HairAccessory", "FaceAccessory", "NeckAccessory", "ShoulderAccessory", "FrontAccessory", "BackAccessory", "WaistAccessory", "Shirt", "Pants", "TShirt", "Face" }
	local categoryIndex = 1
	local category = modalAction(app, body, "Category: Hat  ›", function() end)
	category.Activated:Connect(function()
		categoryIndex = categoryIndex % #categories + 1
		local caption = category:FindFirstChild("Caption") :: TextLabel
		caption.Text = "Category: " .. categories[categoryIndex] .. "  ›"
	end)
	local busy = false
	local tryButton: TextButton
	tryButton = modalAction(app, body, "Try Item · Free", function()
		if busy then return end
		local id = tonumber(entry.Text)
		if not id or id <= 0 or id % 1 ~= 0 or not string.match(entry.Text, "^%d+$") then
			app:_Toast("info", "Enter the numeric ID from the item's Roblox catalog link.")
			return
		end
		busy = true
		tryButton.Active = false
		local chosenCategory = categories[categoryIndex]
		task.spawn(function()
			local ok = app:_Invoke(Network.Actions.TryCatalogAsset, { assetId = id, avatarAssetType = chosenCategory })
			busy = false
			if ok then
				app.triedOnAssetIds[id] = true
				app.avatarPreviewDirty = true
				app.avatarAccessoriesDirty = true
				closeModal(app)
				app:_OpenPage("Avatar Lab")
			elseif tryButton.Parent then tryButton.Active = true end
		end)
	end)
	modalAction(app, body, "Open My Items", function() closeModal(app); app:_OpenPage("My Studio") end)
	modalAction(app, body, "Browse Avatar Styles", function() closeModal(app); app:_OpenPage("Avatar Lab") end)
end

local function logo(parent: Instance, x: number, y: number, scale: number)
	local holder = frame(parent, "ForgeWordmark", x, y, 320, 228)
	Factory.New("UIScale", { Scale = scale, Parent = holder })
	image(holder, "LogoMark", 0, 0, 320, 228)
	local forge = label(holder, "FORGE", 20, 78, 255, 78, 70, true, WHITE, true)
	forge.Font = Enum.Font.GothamBlack
	forge.Rotation = -5
	forge.TextStrokeColor3 = Color3.fromRGB(2, 9, 24)
	forge.TextStrokeTransparency = 0.12
	local ugc = label(holder, "UGC", 49, 145, 205, 75, 74, true, BLUE, true)
	ugc.Font = Enum.Font.GothamBlack
	ugc.Rotation = -5
	ugc.TextStrokeColor3 = Color3.fromRGB(2, 9, 24)
	ugc.TextStrokeTransparency = 0.12
	ugc.TextColor3 = WHITE
	Factory.Gradient(ugc, { Color3.fromRGB(0, 245, 255), Color3.fromRGB(0, 104, 232) }, 90)
end

local function resource(app: any, parent: Instance, name: string, key: string, x: number, y: number, w: number, h: number, small: boolean, action: () -> ()): TextLabel
	local pill = button(app, parent, name, name, x, y, w, h, action)
	fallbackSurface(pill, INK, Color3.fromRGB(53, 72, 101), if small then 14 else 22)
	local background = image(pill, "ResourcePill", -10, -10, w + 20, h + 24)
	if background then
		background.ScaleType = Enum.ScaleType.Slice
		background.SliceCenter = Rect.new(84, 64, 354, 112)
		background.SliceScale = if small then 0.35 else 0.5
	end
	coverFallback(pill, background)
	image(pill, key, if small then -2 else -1, -3, if small then 48 else 67, h + 4, 2)
	local value = label(pill, "0", if small then 42 else 65, 0, w - (if small then 71 else 111), h, if small then 19 else 29, true)
	image(pill, "PlusButton", w - (if small then 36 else 64), if small then 1 else -1, if small then 42 else 66, h + 2, 2)
	if (HomeAssets :: any).PlusButton == 0 then
		label(pill, "+", w - 37, 0, 30, h, if small then 24 else 30, true, BLUE, true)
	end
	return value
end

local function navigation(app: any, parent: Instance, x: number, y: number, width: number, height: number, mobile: boolean)
	local bar = frame(parent, "HomeNavigation", x, y, width, height)
	fallbackSurface(bar, INK, Color3.fromRGB(47, 65, 95), 18)
	local backdrop = image(bar, "NavBar", -10, -10, width + 20, height + 21)
	if backdrop then backdrop.ScaleType = Enum.ScaleType.Slice; backdrop.SliceCenter = Rect.new(80, 60, 1930, 136); backdrop.SliceScale = 0.5 end
	coverFallback(bar, backdrop)
	app.homeNavButtons = {}
	for index, data in {
		{ "Home", "NavHome", "Home", "⌂" }, { "Create", "NavCreate", "Create", "◇" },
		{ "Market", "NavMarket", "Discover", "♧" }, { "Games", "NavGames", "Play", "🎮" },
	} do
		local w = width / 4
		local control = button(app, bar, "HomeNav" .. data[1], data[1], (index - 1) * w, 0, w, height, function() app:_OpenPage(data[3]) end)
		control.SelectionOrder = index
		app.homeNavButtons[data[3]] = control
		local active = (app.activePage or "Home") == data[3]
		if active then
			fallbackSurface(control, Color3.fromRGB(0, 113, 241), BLUE, 17)
			local selected = image(control, "NavActive", -12, -12, w + 24, height + 27, 1)
			if selected then selected.ScaleType = Enum.ScaleType.Slice; selected.SliceCenter = Rect.new(80, 70, 456, 134); selected.SliceScale = 0.5 end
			coverFallback(control, selected)
		end
		local iconSize = if mobile then 28 else 56
		local iconX = if mobile then (w - iconSize) / 2 else 43
		if not image(control, data[2], iconX, if mobile then 0 else 9, iconSize, iconSize, 2) then
			label(control, data[4], iconX, 0, iconSize, if mobile then 28 else height, if mobile then 19 else 28, true, WHITE, true)
		end
		label(control, data[1], if mobile then 0 else 111, if mobile then 27 else 0,
			if mobile then w else w - 120, if mobile then 23 else height,
			if mobile then 12 else 28, true, if active then WHITE else MUTED, mobile)
	end
end

function HomeScreen.ShowTools(app: any)
	local _, body = modal(app, "More tools")
	for _, tool in {
		{ "Style My Avatar", "Avatar Lab" }, { "Avatar Graphics", "Avatar Graphics" },
		{ "My Items", "My Studio" }, { "Games & Runway", "Play" }, { "Settings", "Settings" },
	} do
		modalAction(app, body, tool[1] .. "  ›", function()
			closeModal(app)
			app:_OpenPage(tool[2])
		end)
	end
	modalAction(app, body, "Tutorial  ›", function() closeModal(app); app:_ShowVisualTutorial() end)
end

-- The same uploaded, text-free Home chrome surrounds every editor page.
function HomeScreen.Chrome(app: any, canvas: Instance, mobile: boolean, width: number)
	local function tools(x: number, y: number, w: number)
		local control = button(app, canvas, "EditorMoreTools", "More tools", x, y, w, 32, function() HomeScreen.ShowTools(app) end)
		label(control, "More tools  ›", 0, 0, w, 32, 16, true, BLUE, true)
	end
	if mobile then
		logo(canvas, 0, 0, math.min(0.43, (width - 184) / 320))
		app.homeBalanceLabels = {
			tokens = resource(app, canvas, "ForgeTokens", "TokenIcon", width-184, 10, 128, 44, true, function() showWallet(app) end),
			passes = resource(app, canvas, "PriorityPasses", "TicketIcon", width-184, 62, 128, 44, true, function() app:_BuyPriorityPass() end),
		}
		navigation(app, canvas, 8, 124, width-16, 52, true)
		local library = button(app, canvas, "EditorLibrary", "My Items", 8, 179, (width-24)/2, 36, function() app:_OpenPage("My Studio") end)
		label(library, "My Items  ›", 0, 0, (width-24)/2, 36, 16, true, WHITE, true)
		tools(width/2, 181, (width-24)/2)
	else
		local dashboard = frame(canvas, "EditorDashboardFallback", 46, 112, 1590, 786)
		fallbackSurface(dashboard, Color3.fromRGB(19, 28, 49), Color3.fromRGB(58, 76, 108), 37)
		coverFallback(dashboard, image(canvas, "Dashboard", 18, 84, 1634, 838))
		logo(canvas, 68, 0, 1)
		navigation(app, canvas, 385, 136, 984, 77, false)
		app.homeBalanceLabels = {
			tokens = resource(app, canvas, "ForgeTokens", "TokenIcon", 1145, 29, 199, 64, false, function() showWallet(app) end),
			passes = resource(app, canvas, "PriorityPasses", "TicketIcon", 1359, 29, 191, 64, false, function() app:_BuyPriorityPass() end),
		}
		local library = button(app, canvas, "EditorLibrary", "My Items", 1399, 144, 154, 62, function() app:_OpenPage("My Studio") end)
		if app.activePage == "My Studio" then
			fallbackSurface(library, Color3.fromRGB(0, 113, 241), BLUE, 17)
		end
		label(library, "My Items", 0, 0, 154, 62, 21, true, if app.activePage == "My Studio" then WHITE else MUTED, true)
		tools(1399, 215, 154)
	end
	local settingsX, settingsY, size = if mobile then width-50 else 1573, if mobile then 10 else 29, if mobile then 44 else 64
	local settings = button(app, canvas, "EditorSettings", "Settings", settingsX, settingsY, size, size, function() app:_OpenPage("Settings") end)
	if not image(settings, "SettingsButton", -8, -8, size+16, size+20) then label(settings, "⚙", 0, 0, size, size, 28, true, WHITE, true) end
	local close = button(app, canvas, "CloseEditor", "Back to world", if mobile then width-50 else 1562,
		if mobile then 62 else 143, if mobile then 44 else 56, if mobile then 44 else 56, function() app:_SetStudioOpen(false) end)
	label(close, "×", 0, 0, if mobile then 44 else 56, if mobile then 44 else 56, 30, true, MUTED, true)
	for _, child in canvas:GetDescendants() do
		if child:IsA("GuiButton") then HomeEffects.Button(child :: GuiButton, BLUE) end
	end
	HomeScreen.Refresh(app)
end

local function feature(app: any, parent: Instance, data: any, x: number, y: number, w: number, h: number, mobile: boolean, entranceDelay: number?)
	local card = frame(parent, data.key .. "Card", x, y, w, h)
	fallbackSurface(card, data.color, data.edge, 26)
	Factory.Gradient(card, { data.color, data.dark }, 105)
	local panel = image(card, data.key .. "Panel", -12, -12, w + 24, h + 24)
	if panel and mobile then
		panel.ScaleType = Enum.ScaleType.Slice
		panel.SliceCenter = if data.key == "Create" then Rect.new(90, 90, 968, 938)
			elseif data.key == "Market" then Rect.new(90, 90, 966, 938) else Rect.new(90, 90, 902, 938)
		panel.SliceScale = 0.5
	end
	coverFallback(card, panel)
	local art = image(card, data.key .. "Art", 0, 0, w, h, 2)
	if art and mobile then art.ScaleType = Enum.ScaleType.Fit end
	if not art then label(card, data.symbol, w * 0.3, h * 0.43, w * 0.5, h * 0.3, 72, true, data.edge, true) end
	local inset = if mobile then 22 else 39
	label(card, data.title, inset, if mobile then 16 else 13, w - inset * 2, if mobile then 46 else 68, if mobile then 29 else 48, true)
	local description = label(card, data.body, inset, if mobile then 65 else 84, w - inset * 2,
		if mobile then 76 else 94, if mobile then 17 else 24)
	description.TextYAlignment = Enum.TextYAlignment.Top
	local bw = w - 46
	local bh = if mobile then 54 else 77
	local action = button(app, card, data.key .. "Action", data.actionLabel, 23, h - bh - 17, bw, bh, function()
		app:_Track({ event = "HomeChoice", fields = { choice = data.key } })
		app:_OpenPage(data.page)
	end)
	fallbackSurface(action, data.edge, data.edge, 22)
	local background = image(action, data.key .. "Button", -10, -10, bw + 20, bh + 25)
	if background and mobile then
		background.ScaleType = Enum.ScaleType.Slice
		background.SliceCenter = if data.key == "Games" then Rect.new(90, 80, 802, 124) else Rect.new(90, 80, 868, 124)
		background.SliceScale = 0.38
	end
	coverFallback(action, background)
	local caption = label(action, data.actionLabel .. "  ›", 12, 0, bw - 24, bh, if mobile then 21 else 28, true, WHITE, true)
	caption.TextStrokeColor3 = Color3.fromRGB(3, 18, 46)
	caption.TextStrokeTransparency = 0.55
	HomeEffects.Button(action, data.edge)
	HomeEffects.Card(card, action, data.edge, entranceDelay)
end

local function quickLink(app: any, parent: Instance, data: any, x: number, y: number, w: number, h: number, mobile: boolean): TextButton
	local control = button(app, parent, data.key .. "Shortcut", data.title, x, y, w, h, data.action)
	fallbackSurface(control, INK, Color3.fromRGB(42, 76, 110), 21)
	local background = image(control, "QuickLink", -10, -10, w + 20, h + 20)
	if background then background.ScaleType = Enum.ScaleType.Slice; background.SliceCenter = Rect.new(80, 70, 544, 186); background.SliceScale = 0.5 end
	coverFallback(control, background)
	local iconSize = if mobile then 52 else 95
	if not image(control, data.key .. "Icon", if mobile then 4 else 10, if mobile then 10 else 8, iconSize, iconSize, 2) then
		label(control, data.symbol, 8, 8, iconSize, iconSize, if mobile then 24 else 40, true, BLUE, true)
	end
	local inset = if mobile then 58 else 118
	label(control, data.title, inset, if mobile then 14 else 18, w - inset - 8, 28, if mobile then 13 else 20, true, Color3.fromRGB(221, 246, 255))
	local subtitle = label(control, data.subtitle, inset, if mobile then 46 else 48, w - inset - 10, 48, if mobile then 12 else 18, false, MUTED)
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	return control
end

function HomeScreen.Refresh(app: any)
	local values = app.homeBalanceLabels
	if not values or not app.state then return end
	local profile = app.state.profile
	local function compactNumber(value: number): string
		if value >= 1000000 then return string.format("%.1fM", value / 1000000) end
		if value >= 1000 then return string.format("%.1fK", value / 1000) end
		return tostring(value)
	end
	if values.tokens.Parent then values.tokens.Text = compactNumber((profile.tokens or 0) + (profile.bonusTokens or 0)) end
	if values.passes.Parent then values.passes.Text = compactNumber((profile.retryCredits or {}).PriorityPass or 0) end
end

function HomeScreen.Render(app: any)
	app.homeBalanceLabels = nil
	-- Profile refreshes also rebuild this page; only animate a new visit.
	local animateEntry = app.animateNextPage == true or app.homeEntrancePlayed ~= true
	app.homeEntrancePlayed = true
	local builtOnce = false
	local root = frame(app.content, "ForgeHome", 0, 0, 1, 1)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = INK
	root.BackgroundTransparency = 0
	local background = image(root, "Backdrop", 0, 0, 1, 1, 0)
	if background then background.Size = UDim2.fromScale(1, 1); background.ScaleType = Enum.ScaleType.Crop end
	local canvas = frame(root, "HomeCanvas", 0, 0, 1672, 941)
	local canvasScale = Factory.New("UIScale", { Scale = 1, Parent = canvas })
	local previousMobile: boolean? = nil
	local features = {
		{ key = "Create", title = "Create UGC", body = "Turn your ideas into Roblox UGC\nwith AI. Generate, customize,\nand publish.", actionLabel = "Start Creating", page = "Create", symbol = "✦", color = Color3.fromRGB(0, 68, 131), dark = Color3.fromRGB(3, 39, 88), edge = BLUE, width = 505, x = 77 },
		{ key = "Market", title = "Shop UGC", body = "Explore and try on UGC made\nby the community.", actionLabel = "Browse Market", page = "Discover", symbol = "♛", color = Color3.fromRGB(85, 21, 147), dark = Color3.fromRGB(45, 9, 83), edge = VIOLET, width = 504, x = 606 },
		{ key = "Games", title = "Play & Earn", body = "Play fun mini-games to earn\ntokens, rewards, and more!", actionLabel = "Play Games", page = "Play", symbol = "🎮", color = Color3.fromRGB(168, 87, 8), dark = Color3.fromRGB(89, 38, 0), edge = GOLD, width = 472, x = 1135 },
	}
	local shortcuts = {
		{ key = "Tutorial", title = "Tutorial", subtitle = "Learn how to use\nForge UGC", symbol = "▣", x = 77, width = 292, action = function() app:_ShowVisualTutorial() end },
		{ key = "Missions", title = "Missions", subtitle = "Complete tasks\nfor rewards", symbol = "✓", x = 391, width = 289, action = function() showMissions(app) end },
		{ key = "Rewards", title = "Rewards", subtitle = "View daily rewards", symbol = "◇", x = 702, width = 295, action = function() showRewards(app) end },
		{ key = "Codes", title = "UGC Codes", subtitle = "Try a catalog\nitem by ID", symbol = "♧", x = 1018, width = 293, action = function() showCodes(app) end },
		{ key = "Premium", title = "Premium", subtitle = "View Roblox Plus\nbenefits", symbol = "★", x = 1332, width = 275, action = function() app:_ShowPlus() end },
	}
	local function build(mobile: boolean, width: number)
		for _, child in canvas:GetChildren() do if child ~= canvasScale then child:Destroy() end end
		app.homeBalanceLabels = nil
		local entrance = animateEntry and not builtOnce and not Motion.IsReduced()
		builtOnce = true
		if not mobile then
			canvas.Size = UDim2.fromOffset(1672, 941)
			canvas.AnchorPoint = Vector2.new(0.5, 0.5)
			canvas.Position = UDim2.fromScale(0.5, 0.5)
			local dashboard = frame(canvas, "DashboardFallback", 46, 112, 1590, 786)
			fallbackSurface(dashboard, Color3.fromRGB(19, 28, 49), Color3.fromRGB(58, 76, 108), 37)
			coverFallback(dashboard, image(canvas, "Dashboard", 18, 84, 1634, 838))
			logo(canvas, 68, 0, 1)
			navigation(app, canvas, 385, 136, 984, 77, false)
			app.homeBalanceLabels = {
				tokens = resource(app, canvas, "ForgeTokens", "TokenIcon", 1145, 29, 199, 64, false, function() showWallet(app) end),
				passes = resource(app, canvas, "PriorityPasses", "TicketIcon", 1359, 29, 191, 64, false, function() app:_BuyPriorityPass() end),
			}
			local settings = button(app, canvas, "HomeSettings", "Settings", 1573, 29, 64, 64, function() app:_OpenPage("Settings") end)
			if not image(settings, "SettingsButton", -10, -10, 84, 88) then label(settings, "⚙", 0, 0, 64, 64, 40, true, WHITE, true) end
			local library = button(app, canvas, "HomeLibrary", "My Items", 1410, 148, 126, 44, function() app:_OpenPage("My Studio") end)
			label(library, "My Items", 0, 0, 126, 44, 20, true, MUTED, true)
			local close = button(app, canvas, "CloseHome", "Back to world", 1562, 143, 56, 56, function() app:_SetStudioOpen(false) end)
			label(close, "×", 0, 0, 56, 56, 34, true, MUTED, true)
			local tools = button(app, canvas, "HomeMoreTools", "More tools", 77, 875, 164, 24, function() HomeScreen.ShowTools(app) end)
			label(tools, "More tools  ›", 0, 0, 164, 24, 16, true, BLUE)
			for index, data in features do
				feature(app, canvas, data, data.x, 244, data.width, 490, false, if entrance then (index - 1) * 0.07 else nil)
			end
			for index, data in shortcuts do
				local control = quickLink(app, canvas, data, data.x, 762, data.width, 108, false)
				HomeEffects.Button(control, if data.key == "Premium" then GOLD else BLUE)
				if entrance then HomeEffects.Rise(control, 0.16 + (index - 1) * 0.045, 14) end
			end
		else
			canvasScale.Scale = 1
			canvas.AnchorPoint = Vector2.zero
			canvas.Position = UDim2.fromOffset(0, 0)
			canvas.Size = UDim2.fromScale(1, 1)
			logo(canvas, 0, 0, math.min(0.43, (width - 184) / 320))
			app.homeBalanceLabels = {
				tokens = resource(app, canvas, "ForgeTokens", "TokenIcon", width - 184, 10, 128, 44, true, function() showWallet(app) end),
				passes = resource(app, canvas, "PriorityPasses", "TicketIcon", width - 184, 62, 128, 44, true, function() app:_BuyPriorityPass() end),
			}
			local settings = button(app, canvas, "HomeSettings", "Settings", width - 50, 10, 44, 44, function() app:_OpenPage("Settings") end)
			if not image(settings, "SettingsButton", -6, -6, 56, 58) then label(settings, "⚙", 0, 0, 44, 44, 27, true, WHITE, true) end
			local close = button(app, canvas, "CloseHome", "Back to world", width - 50, 62, 44, 44, function() app:_SetStudioOpen(false) end)
			label(close, "×", 0, 0, 44, 44, 28, true, WHITE, true)
			navigation(app, canvas, 8, 124, width - 16, 52, true)
			local scroll = Factory.New("ScrollingFrame", {
				Name = "HomeScroll", Position = UDim2.fromOffset(8, 190), Size = UDim2.new(1, -16, 1, -198),
				BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
				ScrollBarImageColor3 = BLUE, Parent = canvas,
			})
			app:_TrackScroll(scroll, "Home")
			local contentWidth = width - 36
			local cardHeight = math.max(350, contentWidth * 490 / 505)
			local y = 12
			for index, data in features do
				feature(app, scroll, data, 6, y, contentWidth, cardHeight, true, if entrance then (index - 1) * 0.07 else nil)
				y += cardHeight + 22
			end
			local half = (contentWidth - 12) / 2
			for index, data in shortcuts do
				local control = quickLink(app, scroll, data, 6 + (index - 1) % 2 * (half + 12), y + math.floor((index - 1) / 2) * 120, half, 108, true)
				HomeEffects.Button(control, if data.key == "Premium" then GOLD else BLUE)
				if entrance then HomeEffects.Rise(control, 0.16 + (index - 1) * 0.045, 14) end
			end
			local library = button(app, scroll, "HomeLibrary", "My Items", 6, y + 360, half, 48, function() app:_OpenPage("My Studio") end)
			fallbackSurface(library, INK, BLUE, 14)
			label(library, "My Items  ›", 8, 0, half - 16, 48, 17, true, WHITE, true)
			local tools = button(app, scroll, "HomeMoreTools", "More tools", half+18, y+360, half, 48, function() HomeScreen.ShowTools(app) end)
			fallbackSurface(tools, INK, BLUE, 14)
			label(tools, "More tools  ›", 8, 0, half-16, 48, 17, true, WHITE, true)
			HomeEffects.Button(library, BLUE)
			HomeEffects.Button(tools, BLUE)
			frame(scroll, "BottomSpacing", 0, y + 420, 1, 12)
		end
		for _, child in canvas:GetDescendants() do
			if child:IsA("GuiButton") then HomeEffects.Button(child :: GuiButton, BLUE) end
		end
		HomeScreen.Refresh(app)
	end
	local previousWidth = 0
	local function layout()
		if not root.Parent then return end
		local ancestorScale = app.uiScaleInstance.Scale
		local width = root.AbsoluteSize.X / math.max(0.01, ancestorScale)
		local height = root.AbsoluteSize.Y / math.max(0.01, ancestorScale)
		if width <= 0 or height <= 0 then return end
		local mobile = width < 760 or height < 420
		if mobile ~= previousMobile or (mobile and math.abs(width - previousWidth) > 1) then
			previousMobile, previousWidth = mobile, width
			build(mobile, width)
		end
		if not mobile then canvasScale.Scale = math.min(width / 1672, height / 941) end
	end
	table.insert(app.pageConnections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	table.insert(app.pageConnections, app.uiScaleInstance:GetPropertyChangedSignal("Scale"):Connect(layout))
	layout()
	task.defer(layout)
end

return HomeScreen
