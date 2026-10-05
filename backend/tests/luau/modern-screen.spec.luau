-- Exercise native controls beneath the imported SVG surfaces. Asset IDs are
-- local fixture values; this suite never fetches images or invokes Roblox.
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end
local function equal(actual, expected, message)
	check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, message)
	check(math.abs(actual - expected) < .00001, message)
end
local function find(parent, name)
	for _, node in parent:GetDescendants() do if node.Name == name then return node end end
	error("Missing native control: " .. name)
end
local function count(parent, name)
	local total = 0
	for _, node in parent:GetDescendants() do if node.Name == name then total += 1 end end
	return total
end
local function bounds(node, root)
	if node == root then return 0, 0, 600, root.Size.Y.Offset end
	local x, y, width, height = bounds(node.Parent, root)
	local ownWidth = node.Size.X.Scale * width + node.Size.X.Offset
	local ownHeight = node.Size.Y.Scale * height + node.Size.Y.Offset
	return x + node.Position.X.Scale * width + node.Position.X.Offset - node.AnchorPoint.X * ownWidth,
		y + node.Position.Y.Scale * height + node.Position.Y.Offset - node.AnchorPoint.Y * ownHeight,
		ownWidth, ownHeight
end
local function noOverlap(first, second, root, message)
	local ax, ay, aw, ah = bounds(first, root)
	local bx, by, bw, bh = bounds(second, root)
	check(ax + aw <= bx or bx + bw <= ax or ay + ah <= by or by + bh <= ay, message)
end

fixtures.ScreenAssets = {
	PanelBlue = 101, PanelPurple = 102, PanelGold = 103,
	ButtonBlue = 201, ButtonPurple = 202, ButtonGold = 203,
	ButtonQuiet = 204, ButtonDanger = 205, SectionHeader = 301,
}
-- Remove the imported chrome textures to verify readable code-drawn fallbacks.
fixtures.HomeAssets = table.clone(require("HomeAssets"))
cache.HomeAssets = nil
for key, value in fixtures.HomeAssets do if type(value) == "number" then fixtures.HomeAssets[key] = 0 end end
fixtures.Theme.Colors.Cyan = Color3.fromRGB(0, 202, 255)
fixtures.Theme.Colors.Violet = Color3.fromRGB(191, 103, 255)
fixtures.Theme.Colors.Gold = Color3.fromRGB(255, 208, 78)
fixtures.Theme.Colors.Ink = Color3.fromRGB(15, 24, 44)
fixtures.Theme.Colors.Text = Color3.fromRGB(246, 250, 255)
fixtures.Theme.Colors.PanelSoft = Color3.fromRGB(20, 34, 59)
local Factory = require("Factory")
local ModernChrome = require("ModernChrome")
local HomeScreen = require("HomeScreen")
local Motion = require("Motion")

local host = Factory.New("Frame")
host:SetAttribute("ForgeSurface", "Purple")
local card = Factory.ImageCard(host, UDim2.fromOffset(350, 200), nil, "NativeCollection")
local decal = card:FindFirstChild("Decal")
equal(decal:GetAttribute("ForgeAssetKey"), "PanelPurple", "Cards inherit their page's surface")
equal(decal.Image, "rbxassetid://102", "The imported panel uses its configured Roblox asset")
equal(card.BackgroundTransparency, 0, "Loading artwork retains a native panel background")
check(card:FindFirstChildOfClass("UIStroke").Transparency < 1, "Loading artwork retains the native outline")
local authoredBorder = card:FindFirstChildOfClass("UIStroke").Transparency
decal.IsLoaded = true
equal(card.BackgroundTransparency, 1, "Loaded artwork replaces only the native panel fill")
equal(card:FindFirstChildOfClass("UIStroke").Transparency, 1, "Loaded artwork hides the native duplicate outline")
check(not card:FindFirstChild("Gloss").Visible, "Loaded artwork hides the native duplicate reflection")
decal.IsLoaded = false
equal(card.BackgroundTransparency, 0, "An unloaded texture restores its native fill")
equal(card:FindFirstChildOfClass("UIStroke").Transparency, authoredBorder, "An unloaded texture restores its authored border")
check(card:FindFirstChild("Gloss").Visible, "An unloaded texture restores its native reflection")

local clicked = 0
local action = Factory.ImageButton(card, "Try on", UDim2.fromOffset(120, 42), nil, "primary")
action.Activated:Connect(function() clicked += 1 end)
equal(action:FindFirstChild("Decal"):GetAttribute("ForgeAssetKey"), "ButtonPurple", "Primary buttons inherit the panel surface")
action:FindFirstChild("Decal").IsLoaded = true
action.Activated:Fire()
equal(clicked, 1, "Imported button artwork preserves native activation callbacks")
action.Text = "Remove"
equal(action:FindFirstChild("Label").Text, "Remove", "Native state changes update the visible button caption")
check(action:FindFirstChild("Label").ZIndex > action:FindFirstChild("Decal").ZIndex, "Native button text stays above imported artwork")
action.AbsoluteSize = Vector2.new(40, 28)
check(action:FindFirstChild("Decal").SliceScale <= 28/62, "Small reset/remove controls retain a stretchable sliced centre")
check(Factory.SwapDecal(action, "ButtonDefault"), "Existing deselection callbacks accept their legacy asset key")
equal(action:FindFirstChild("Decal"):GetAttribute("ForgeAssetKey"), "ButtonQuiet", "Deselection uses the quiet modern button art")
check(Factory.SwapDecal(action, "ButtonPrimary"), "Existing selection callbacks accept their legacy asset key")
equal(action:FindFirstChild("Decal"):GetAttribute("ForgeAssetKey"), "ButtonPurple", "Selection restores the page's primary art")
fixtures.ScreenAssets.ButtonPurple = 0
check(not Factory.SwapDecal(action, "ButtonPrimary"), "Unavailable selection art reports a native fallback")
equal(action:FindFirstChild("Decal").Image, "", "Unavailable replacement art clears the stale texture")
equal(action.BackgroundTransparency, 0, "Unavailable selection art keeps its control visible")
fixtures.ScreenAssets.ButtonPurple = 202
fixtures.ScreenAssets.PanelBlue = 0
local missingHost = Factory.New("Frame")
local missingBlue = Factory.ImageCard(missingHost, UDim2.fromOffset(350, 200))
check(not missingBlue:FindFirstChild("Decal") and missingBlue.BackgroundTransparency == 0, "A missing panel ID keeps its native readable fallback")
fixtures.ScreenAssets.PanelBlue = 101

for _, item in {{"GraphicComposer", "Purple"}, {"Collection", "Purple"}, {"ArcadeModal", "Gold"}, {"RunwayModal", "Purple"}} do
	local special = Factory.ImageCard(missingHost, UDim2.fromOffset(350, 200), nil, item[1])
	equal(special:GetAttribute("ForgeSurface"), item[2], item[1] .. " keeps its screen's intended color")
end
fixtures.Theme.IsHighContrast = true
local contrast = Factory.ImageCard(host, UDim2.fromOffset(350, 200))
check(not contrast:FindFirstChild("Decal"), "High contrast uses the native accessible panel colors")
check(contrast:FindFirstChildOfClass("UIStroke").Transparency <= .08, "High contrast keeps the strong native outline")
fixtures.Theme.IsHighContrast = false
fixtures.HomeAssets.LogoMark = 401
equal(Factory.Icon(host, "Logo", UDim2.fromOffset(64, 64)).Image, "rbxassetid://401", "Legacy brand callers use the supplied Home logo art")
check(Factory.Icon(host, "CornerOrnament", UDim2.fromOffset(64, 64)) == nil, "Retired ornaments cannot reintroduce the old theme")
fixtures.HomeAssets.LogoMark = 0

local app = {
	gui = Factory.New("ScreenGui"), shell = Factory.New("Frame"), nav = Factory.New("Frame"),
	backgroundLayer = Factory.New("Frame"), content = Factory.New("Frame"),
	uiScaleInstance = Factory.New("UIScale", {Scale = 1}), activePage = "Create", compact = false, studioOpen = true,
	state = {profile = {tokens = 15, bonusTokens = 8, retryCredits = {PriorityPass = 2}, settings = {}}},
	_BindButton = function() end,
	_OpenPage = function(self, page) self.openedPage = page end,
	_SetStudioOpen = function(self, open) self.studioOpen = open end,
	_ShowVisualTutorial = function(self) self.tutorialOpened = true end,
	_BuyPriorityPass = function(self) self.passOpened = true end,
}
app.shell.Parent = app.gui
app.nav.Parent = app.shell
app.navButtons = {}
for _, page in {"Home", "Create", "Discover", "Play", "Avatar Lab", "My Studio", "Settings"} do
	app.navButtons[page] = Factory.New("TextButton", {Parent = app.nav})
end
app.content.Parent = app.shell
local topbar = Factory.New("Frame", {Name = "Topbar", Parent = app.shell})
Factory.New("UIGradient", {Parent = app.shell})
Factory.New("UIStroke", {Parent = app.shell})
ModernChrome.Apply(app)
check(not topbar.Visible and not app.nav.Visible and not app.backgroundLayer.Visible, "Every editor page replaces the legacy header, sidebar and scenery")
check(app.editorRoot.Visible and app.content.Parent == app.editorCanvas, "Native page controls live inside the modern canvas")
equal(app.editorCanvas.Size.X.Offset, 1672, "Desktop layout uses the SVG's logical width")
equal(app.editorCanvas.Size.Y.Offset, 941, "Desktop layout uses the SVG's logical height")
app.editorRoot.AbsoluteSize = Vector2.new(1672, 941)
near(app.editorScale.Scale, 1, "A full-size viewport displays the SVG at its authored scale")
app.uiScaleInstance.Scale = 2
near(app.editorScale.Scale, .5, "Editor scaling accounts for the enclosing user interface scale")
app.uiScaleInstance.Scale = 1
equal(app.homeBalanceLabels.tokens.Text, "23", "Every editor header shows the live combined token balance")
equal(app.homeBalanceLabels.passes.Text, "2", "Every editor header shows live Priority Pass inventory")
app.state.profile.tokens = 1000000
app.state.profile.retryCredits.PriorityPass = 8
HomeScreen.Refresh(app)
equal(app.homeBalanceLabels.tokens.Text, "1.0M", "Balance refreshes stay readable inside imported chrome")
equal(app.homeBalanceLabels.passes.Text, "8", "Balance refreshes update pass inventory without rebuilding controls")
for _, item in {{"Home", "Home"}, {"Create", "Create"}, {"Discover", "Discover"}, {"Play", "Play"}} do
	app.activePage = item[1]
	ModernChrome.Apply(app)
	if item[1] ~= "Home" then
		local selected = app.homeNavButtons[item[1]]
		check(selected and selected.BackgroundTransparency == 0, item[1] .. " receives a visible active navigation state without images")
	end
end
for _, item in {{"HomeNavHome", "Home"}, {"HomeNavCreate", "Create"}, {"HomeNavMarket", "Discover"}, {"HomeNavGames", "Play"}, {"EditorLibrary", "My Studio"}, {"EditorSettings", "Settings"}} do
	find(app.editorHeader, item[1]).Activated:Fire()
	equal(app.openedPage, item[2], item[1] .. " retains its real destination")
end
find(app.editorHeader, "CloseEditor").Activated:Fire()
check(app.studioOpen == false, "Editor close returns to the game world")
app.studioOpen = true
find(app.editorHeader, "PriorityPasses").Activated:Fire()
check(app.passOpened, "Editor pass balance preserves the existing purchase action")
check(app.editorHeader:FindFirstChild("EditorMoreTools", true) == nil, "Desktop v2 chrome leaves room for page-specific tabs")
HomeScreen.ShowTools(app)
check(app.homeModal and app.homeModal.Parent, "Page-specific tools retain the native tools menu")
for _, item in {{"Style My Avatar  ›", "Avatar Lab"}, {"Avatar Graphics  ›", "Avatar Graphics"}, {"My Items  ›", "My Studio"}, {"Games & Runway  ›", "Play"}, {"Settings  ›", "Settings"}} do
	-- Opening a destination closes the menu, so rebuild it for each action.
	HomeScreen.ShowTools(app)
	local destination
	for _, node in app.homeModal:GetDescendants() do
		if node:IsA("TextButton") and node.Text == item[1] then
			destination = node
			break
		end
	end
	check(destination ~= nil, "More tools retains the " .. item[2] .. " destination")
	destination.Activated:Fire()
	equal(app.openedPage, item[2], "More tools reaches " .. item[2])
	check(app.homeModal == nil, "More tools closes after a destination is chosen")
end
HomeScreen.ShowTools(app)
local tutorial
for _, node in app.homeModal:GetDescendants() do
	if node:IsA("TextButton") and node.Text == "Tutorial  ›" then tutorial = node end
end
check(tutorial ~= nil, "More tools retains the existing tutorial")
tutorial.Activated:Fire()
check(app.tutorialOpened and app.homeModal == nil, "More tools opens the existing tutorial and closes its menu")
equal(count(app.shell, "ForgeEditor"), 1, "Changing pages reuses one editor canvas")
local NavigationFocus = require("NavigationFocus")
for _, page in {"Create", "Discover", "Play", "Avatar Lab", "My Studio", "Settings", "Avatar Graphics"} do
	app.activePage = page
	ModernChrome.Apply(app)
	for _, key in {Enum.KeyCode.Tab, Enum.KeyCode.ButtonY} do
		services.GuiService.SelectedObject = nil
		NavigationFocus._TestNavigationInput(app, {KeyCode = key}, false)
		equal(services.GuiService.SelectedObject, app.homeNavButtons[page] or app.homeNavButtons.Home, page .. " keyboard/gamepad focus uses visible modern navigation")
	end
end
services.GuiService.SelectedObject = nil
NavigationFocus._TestNavigationInput(app, {KeyCode = Enum.KeyCode.Tab}, true)
check(services.GuiService.SelectedObject == nil, "Processed input does not steal navigation focus")
app.shell.Visible = false
NavigationFocus._TestNavigationInput(app, {KeyCode = Enum.KeyCode.Tab}, false)
check(services.GuiService.SelectedObject == nil, "Hidden studio does not capture navigation focus")
app.shell.Visible = true
local tabActions = 0
local nativeTab = Factory.New("TextButton", {Name = "LiveEditorTab", Parent = app.editorHeader,
	Text = "My avatar", Size = UDim2.fromOffset(140, 44)})
nativeTab.Activated:Connect(function() tabActions += 1 end)
local headerBefore = app.editorHeader
ModernChrome.Apply(app)
equal(nativeTab.Parent, headerBefore, "Applying the same page retains its relocated live tabs")
app.editorRoot.AbsoluteSize = Vector2.new(1600, 900)
app.uiScaleInstance.Scale = 1.2
equal(nativeTab.Parent, headerBefore, "Desktop resizing and interface scaling preserve live header tabs")
nativeTab.Activated:Fire()
equal(tabActions, 1, "Tabs retain their callbacks after responsive layout changes")
app.uiScaleInstance.Scale = 1
app.homeNavButtons = nil
ModernChrome.Apply(app)
check(nativeTab.Parent == nil and app.homeNavButtons ~= nil, "A full page rerender replaces previous native header tabs")

app.avatarPreviewPanel = Factory.New("Frame", {Name = "SharedAvatar", Parent = app.gui})
app.avatarPreviewViewport = Factory.New("ViewportFrame", {Parent = app.avatarPreviewPanel})
app.avatarPreviewList = Factory.New("ScrollingFrame", {Parent = app.avatarPreviewPanel})
app.avatarPreviewEmptyLabel = Factory.New("TextLabel", {Parent = app.avatarPreviewList})
for _, page in {"Avatar Lab", "Discover"} do
	app.activePage = page
	ModernChrome.Apply(app)
	check(ModernChrome.LayoutPreview(app), page .. " handles its existing shared avatar panel")
	check(app.avatarPreviewPanel.Visible and app.avatarPreviewPanel.Parent == app.editorCanvas, page .. " embeds the live avatar inside the screen")
	equal(app.content.Size.X.Offset, 1087, page .. " reserves exactly one interior avatar column")
	equal(app.avatarPreviewPanel.Position.X.Offset, 1142, "Avatar preview matches the SVG column")
	equal(app.shell.Size.X.Scale, .9, "An integrated preview does not shrink the shell for a second outside rail")
end
app.activePage = "Settings"
ModernChrome.Apply(app)
ModernChrome.LayoutPreview(app)
check(not app.avatarPreviewPanel.Visible, "Unrelated pages hide the shared avatar preview")
equal(app.content.Size.X.Offset, 1586, "Unrelated pages reclaim the full editor body")
app.activePage = "My Studio"
ModernChrome.Apply(app)
check(find(app.editorHeader, "EditorLibrary").BackgroundTransparency == 0, "My Items gets its own active native state")

app.compact = true
app.editorRoot.AbsoluteSize = Vector2.new(390, 700)
ModernChrome.Apply(app)
equal(app.editorScale.Scale, 1, "Phone layout preserves native control scale")
equal(app.editorCanvas.Size.X.Scale, 1, "Phone canvas fills available width")
equal(app.content.Position.Y.Offset, 218, "Phone body clears the compact header")
equal(app.content.Size.Y.Offset, -230, "Phone body retains an accessible scrolling viewport")
check(find(app.editorHeader, "HomeNavigation").Size.X.Offset <= 390, "Phone navigation fits the viewport")
check(find(app.editorHeader, "CloseEditor").Size.X.Offset >= 44, "Phone close control remains touch sized")
find(app.editorHeader, "EditorMoreTools").Activated:Fire()
check(app.homeModal and app.homeModal.Parent, "Phone chrome retains its original tools menu")
app.activePage = "Avatar Lab"
ModernChrome.Apply(app)
ModernChrome.LayoutPreview(app)
check(not app.avatarPreviewPanel.Visible, "Phones avoid a duplicated narrow external avatar rail")
app.editorRoot.AbsoluteSize = Vector2.new(430, 700)
equal(find(app.editorHeader, "HomeNavigation").Size.X.Offset, 414, "Resizing phones rebuilds navigation to the available width")
app.activePage = "Home"
ModernChrome.Apply(app)
check(not app.editorRoot.Visible and app.content.Parent == app.shell, "Returning Home restores its full independent screen")
equal(app.content.Size.X.Scale, 1, "Home retains full shell width")

app.compact = false
app.activePage = "Create"
ModernChrome.Apply(app)
local control = Factory.New("TextButton", {Parent = app.content, Text = "Create", TextSize = 20, Size = UDim2.fromOffset(140, 48)})
local decorated = Factory.ImageButton(app.content, "Try on", UDim2.fromOffset(140, 48), nil, "primary")
decorated.TextSize = 20
ModernChrome.Finish(app)
equal(control.TextSize, 25, "Desktop content receives readable text sizing")
equal(decorated.TextSize, 25, "Skinned controls receive readable text sizing")
equal(decorated:FindFirstChild("Label").TextSize, 25, "Lifted captions are scaled once with their native control")
ModernChrome.Finish(app)
equal(control.TextSize, 25, "Repeated finish passes preserve authored text sizing")
check(control:GetAttribute("ForgePopBound"), "Native editor actions receive the same pop interaction as Home")
Motion.Configure(function() return true end)
local before = tweenCount
control.MouseEnter:Fire()
control.Activated:Fire()
while #delayed > 0 do table.remove(delayed, 1)() end
equal(tweenCount, before, "Reduce Motion disables editor button tweens")
equal(control:FindFirstChild("PopScale").Scale, 1, "Reduce Motion preserves editor button size")

for key, id in { GamesChoice1Panel = 501, GamesChoice2Panel = 502, GamesChoice3Panel = 503,
	GamesChoice1Artwork = 511, GamesChoice2Artwork = 512, GamesChoice3Artwork = 513,
	GamesChoice1OpenButton = 521, GamesChoice2OpenButton = 522, GamesChoice3OpenButton = 523,
	ItemsCollectionPanel = 601, ItemsInspectorPanel = 602, MarketCard1Panel = 701,
	RunwayLineupPanel = 801, RunwayYourLookPanel = 802, RunwayWeeklyPanel = 803,
	CreatePromptPanel = 901, CreateGenerateButton = 902, CreatePreviewPanel = 903 } do
	fixtures.ScreenAssets[key] = id
end
for index = 1, 12 do
	fixtures.ScreenAssets["ArcadeGame" .. index .. "Panel"] = 1000 + index
	fixtures.ScreenAssets["ArcadeGame" .. index .. "Icon"] = 1100 + index
	fixtures.ScreenAssets["ArcadeGame" .. index .. "PlayButton"] = 1200 + index
end
local ModernPageLayouts = require("ModernPageLayouts")
local pending = Factory.New("Frame", {BackgroundTransparency = .7, ZIndex = 3})
Factory.Stroke(pending, fixtures.Theme.Colors.Cyan, .12)
local liveViewport = Factory.New("ViewportFrame", {Name = "LiveViewport", Parent = pending, ZIndex = 1})
check(ModernPageLayouts.Skin(pending, "RunwayYourLookPanel"), "Exact frame artwork can skin an existing native container")
local exactArt = pending:FindFirstChild("ForgeScreenArt")
equal(pending.BackgroundTransparency, .7, "Pending exact artwork preserves its authored native background")
equal(pending:FindFirstChildOfClass("UIStroke").Transparency, .12, "Pending exact artwork preserves its authored native outline")
check(liveViewport.ZIndex > exactArt.ZIndex, "Live avatar pixels stay above exact frame artwork")
local lateButton = Factory.New("TextButton", {Parent = pending, ZIndex = 1})
check(lateButton.ZIndex > exactArt.ZIndex, "Late native controls stay above imported artwork")
exactArt.IsLoaded = true
equal(pending.BackgroundTransparency, 1, "Loaded exact artwork replaces its native background")
exactArt.IsLoaded = false
equal(pending.BackgroundTransparency, .7, "Unloaded exact artwork restores its original native background")
local childrenBefore = #pending:GetChildren()
check(ModernPageLayouts.Skin(pending, "RunwayYourLookPanel"), "Repeated exact skinning retains the existing art")
equal(#pending:GetChildren(), childrenBefore, "Repeated exact skinning never adds duplicate artwork")
for _, class in {"TextBox", "ViewportFrame", "ImageLabel"} do
	local native = Factory.New(class, {Text = "a live value", Image = "rbxthumb://live", Parent = host})
	check(not ModernPageLayouts.Skin(native, "RunwayYourLookPanel"), "Exact artwork cannot paint over a live " .. class)
	check(not native:FindFirstChild("ForgeScreenArt"), class .. " keeps its native content without an opaque backplate")
end
local transparent = Factory.New("Frame", {BackgroundTransparency = 1})
check(ModernPageLayouts.Skin(transparent, "GamesChoice1Artwork"), "Decorative artwork can use its own transparent holder")
equal(transparent.BackgroundTransparency, 1, "Pending decorative artwork never creates an opaque empty rectangle")
fixtures.Theme.IsHighContrast = true
check(not ModernPageLayouts.Skin(Factory.New("Frame"), "RunwayYourLookPanel"), "High contrast skips exact frame artwork")
fixtures.Theme.IsHighContrast = false

local playEditor = {content = Factory.New("Frame"), activePage = "Play", compact = false,
	state = {profile = {settings = {simpleMode = true}}}}
local playPage = Factory.New("ScrollingFrame", {Name = "PlayScroll", Parent = playEditor.content})
local playStack = Factory.New("Frame", {Parent = playPage, AutomaticSize = Enum.AutomaticSize.Y})
local playList = Factory.List(playStack, Enum.FillDirection.Vertical, 14)
local nativeActions, launches = {}, {}
for index, title in {"Arcade", "Forge Runway", "AFK Token Lounge"} do
	local tile = Factory.ImageCard(playStack, UDim2.new(1, 0, 0, 116), nil, "PlayChoice")
	tile.LayoutOrder = index
	Factory.Label(tile, title, UDim2.new(1, -220, 0, 26), {Position = UDim2.fromOffset(18, 16)})
	Factory.Label(tile, "The live activity description", UDim2.new(1, -220, 0, 44), {Position = UDim2.fromOffset(18, 48)})
	local nativeAction = Factory.ImageButton(tile, "OPEN", UDim2.fromOffset(168, 44), nil, "primary")
	nativeAction.Activated:Connect(function() launches[index] = (launches[index] or 0)+1 end)
	table.insert(nativeActions, nativeAction)
end
ModernPageLayouts.Apply(playEditor)
equal(playList.FillDirection, Enum.FillDirection.Horizontal, "Desktop Games arranges its three existing choices side by side")
for index, action in nativeActions do
	equal(action.Parent.Size.X.Offset, 496, "Games keeps each choice inside its approved card width")
	equal(action.Parent.Size.Y.Offset, 516, "Games gives each native choice its approved card height")
	action.Activated:Fire()
	equal(launches[index], 1, "Games preserves the original activity callback exactly once")
	check(action.Parent:FindFirstChild("IllustrationGamesChoice" .. index .. "Artwork") ~= nil, "Games includes its individual decorative activity artwork")
end
local playPosition = playPage.Position
playEditor.compact = true
ModernPageLayouts.Apply(playEditor)
equal(playPage.Position, playPosition, "Phone Games keeps its native layout without desktop repositioning")

local studioEditor = {content = Factory.New("Frame"), activePage = "My Studio", compact = false,
	state = {profile = {settings = {simpleMode = true}}}}
local collection = Factory.ImageCard(studioEditor.content, UDim2.fromOffset(300, 500), nil, "Collection")
local inspector = Factory.ImageCard(studioEditor.content, UDim2.fromOffset(600, 500), nil, "Inspector")
local collectionScroll = Factory.New("ScrollingFrame", {Parent = collection})
local selectedRow = Factory.New("TextButton", {Text = "", Size = UDim2.new(1, 0, 0, 82), Parent = collectionScroll})
local selectedImage = Factory.New("ImageLabel", {Image = "rbxthumb://selected-item", Parent = selectedRow})
local selected = 0
selectedRow.Activated:Connect(function() selected += 1 end)
local nativePreview = Factory.New("Frame", {Parent = inspector})
local nativeModel = Factory.New("ViewportFrame", {Name = "LiveItemModel", Parent = nativePreview})
local itemControls = Factory.New("ScrollingFrame", {Parent = inspector, ScrollBarThickness = 4})
local nativeControls = Factory.New("Frame", {Parent = itemControls})
local equipped = 0
local equip = Factory.ImageButton(nativeControls, "Equip in game", UDim2.new(.5, -10, 0, 44), nil, "primary")
equip.Activated:Connect(function() equipped += 1 end)
ModernPageLayouts.Apply(studioEditor)
equal(collection.Size.X.Offset, 523, "My Items matches the approved collection column")
equal(inspector.Size.X.Offset, 983, "My Items matches the approved inspector column")
equal(nativeModel.Parent, nativePreview, "My Items retains its real selected item viewport")
equal(selectedImage.Image, "rbxthumb://selected-item", "My Items never substitutes the SVG's sample item for live content")
selectedRow.Activated:Fire(); equip.Activated:Fire()
equal(selected, 1, "My Items preserves live collection selection")
equal(equipped, 1, "My Items preserves the original equip callback")
equal(itemControls.ScrollBarThickness, 4, "My Items retains native overflow for inspector actions")

local marketEditor = {content = Factory.New("Frame"), activePage = "Discover", compact = false,
	state = {profile = {settings = {simpleMode = true}}}}
local searchBar = Factory.New("Frame", {Parent = marketEditor.content, Position = UDim2.fromOffset(20, 96)})
local searchField = Factory.New("TextBox", {Parent = searchBar, Text = "a real user query"})
local search = Factory.ImageButton(searchBar, "Search", UDim2.fromOffset(100, 40))
local grid = Factory.New("ScrollingFrame", {Parent = marketEditor.content, ScrollBarThickness = 4})
local gridLayout = Factory.New("UIGridLayout", {Parent = grid})
local marketCard = Factory.ImageCard(grid, UDim2.fromOffset(248, 344), nil, "CommunityItem")
local liveImage = Factory.New("ImageLabel", {Parent = marketCard, Image = "rbxthumb://real-community-item"})
local realTitle = Factory.Label(marketCard, "A real creator's item", UDim2.fromOffset(210, 26), {Position = UDim2.fromOffset(16, 194)})
local tryOn = Factory.ImageButton(marketCard, "Try on", UDim2.new(1, -32, 0, 42), UDim2.fromOffset(16, 250), "primary")
local tried = 0
tryOn.Activated:Connect(function() tried += 1 end)
ModernPageLayouts.Apply(marketEditor)
near(gridLayout.CellSize.X.Scale, 1/3, "Market retains its approved three-column grid")
equal(searchField.Text, "a real user query", "Market keeps the original native search text")
equal(liveImage.Image, "rbxthumb://real-community-item", "Market keeps live creator thumbnails")
equal(realTitle.Text, "A real creator's item", "Market keeps live creator item names")
tryOn.Activated:Fire()
equal(tried, 1, "Market preserves the original try-on callback")
check(not liveImage:FindFirstChild("ForgeScreenArt"), "Market artwork never covers the actual thumbnail pixels")
equal(grid.ScrollBarThickness, 4, "Market preserves its visible result overflow")

do
local arcadeModal = Factory.ImageCard(host, UDim2.fromOffset(800, 600), nil, "ArcadeModal")
Factory.New("UISizeConstraint", {MaxSize = Vector2.new(900, 700), Parent = arcadeModal})
local arcadeHub = Factory.New("Frame", {Name = "HubView", Parent = arcadeModal})
local arcadeTiles, arcadeLaunches = {}, {}
for index = 1, 12 do
	local tile = Factory.New("TextButton", {Name = "LiveGame" .. index, Parent = arcadeHub,
		Size = UDim2.fromOffset(240, 160), Position = UDim2.fromOffset((index-1)%4*250, math.floor((index-1)/4)*176)})
	local icon = Factory.New("Frame", {Name = "IconBadge", Parent = tile, BackgroundTransparency = .8})
	Factory.Label(icon, "Native game icon", UDim2.fromScale(1, 1))
	Factory.Label(tile, "Live game " .. index, UDim2.fromOffset(170, 22), {Name = "GameTitle"})
	Factory.Label(tile, "A real game description", UDim2.fromOffset(170, 30), {Name = "GameDescription"})
	Factory.Label(tile, tostring(index*17), UDim2.fromOffset(120, 26), {Name = "PersonalBest", Position = UDim2.fromOffset(16, 126)})
	local play = Factory.ImageButton(tile, "GO", UDim2.fromOffset(82, 36), nil, "primary")
	play.Name = "PlayPill"
	local function launch() arcadeLaunches[index] = (arcadeLaunches[index] or 0)+1 end
	tile.Activated:Connect(launch); play.Activated:Connect(launch)
	table.insert(arcadeTiles, tile)
end
ModernPageLayouts.Modal({compact = false}, arcadeModal, "Arcade")
equal(arcadeModal:FindFirstChildOfClass("UISizeConstraint").MaxSize.X, 1672, "Desktop Arcade uses the approved wide modal constraint")
for index, tile in arcadeTiles do
	check(tile:FindFirstChild("ForgeScreenArt") ~= nil, "Arcade skins each existing game tile individually")
	near(tile.Size.X.Scale, .25, "Desktop Arcade keeps four game columns")
	equal(tile:FindFirstChild("PersonalBest").Text, tostring(index*17), "Arcade preserves each real personal-best score")
	tile.Activated:Fire(); tile:FindFirstChild("PlayPill").Activated:Fire()
	equal(arcadeLaunches[index], 2, "Arcade keeps both original tile and play callbacks")
end
local icon = arcadeTiles[1]:FindFirstChild("IconBadge")
local glyph = icon:FindFirstChildOfClass("TextLabel")
check(glyph.Visible, "Arcade keeps the native icon visible while uploaded artwork is pending")
icon:FindFirstChild("ForgeScreenArt").IsLoaded = true
check(not glyph.Visible, "Loaded Arcade icon replaces its native fallback glyph")
icon:FindFirstChild("ForgeScreenArt").IsLoaded = false
check(glyph.Visible, "Unavailable Arcade icon restores the native fallback glyph")
local tileChildren = #arcadeTiles[1]:GetChildren()
ModernPageLayouts.Modal({compact = false}, arcadeModal, "Arcade")
equal(#arcadeTiles[1]:GetChildren(), tileChildren, "Repeated Arcade layout does not duplicate imported artwork")
local arcadeSize = arcadeTiles[1].Size
ModernPageLayouts.Modal({compact = true}, arcadeModal, "Arcade")
equal(arcadeTiles[1].Size, arcadeSize, "Compact Arcade leaves native tile dimensions unchanged")
end

do
local runwayModal = Factory.ImageCard(host, UDim2.fromOffset(800, 600), nil, "RunwayModal")
Factory.New("UISizeConstraint", {MaxSize = Vector2.new(900, 700), Parent = runwayModal})
local runwayColumns = Factory.New("Frame", {Name = "Columns", Parent = runwayModal})
Factory.List(runwayColumns, Enum.FillDirection.Horizontal, 14)
local runwayLeft = Factory.New("Frame", {Parent = runwayColumns})
local runwayMiddle = Factory.New("Frame", {Parent = runwayColumns})
local participants = Factory.ImageCard(runwayLeft, UDim2.fromOffset(300, 400), nil, "Participants")
local hero = Factory.ImageCard(runwayMiddle, UDim2.fromOffset(300, 400), nil, "RoundHero")
local weekly = Factory.ImageCard(runwayLeft, UDim2.fromOffset(300, 300), nil, "WeeklyStandings")
Factory.SectionBanner(participants, "Runway Lineup")
Factory.SectionBanner(hero, "Your Look")
Factory.SectionBanner(weekly, "Weekly Spotlight")
local phase = Factory.ImagePill(hero, "Styling", fixtures.Theme.Colors.Cyan, 116)
phase.Position = UDim2.fromOffset(16, 34)
local instruction = Factory.Label(hero, "Lock in your current avatar look", UDim2.new(1, -160, 0, 38), {Position = UDim2.fromOffset(144, 30)})
local weeklyDescription = Factory.Label(weekly, "Points from rounds, votes cast/received, and placements", UDim2.new(1, -32, 0, 16), {Position = UDim2.fromOffset(16, 36)})
local weeklyXP = Factory.Label(weekly, "Weekly XP: #1 +500 · #2 +300 · #3 +100", UDim2.new(1, -32, 0, 14), {Position = UDim2.fromOffset(16, 53)})
local refreshWeekly = Factory.ImageButton(weekly, "Refresh", UDim2.fromOffset(78, 28), UDim2.new(1, -94, 0, 36))
local refreshed = 0
refreshWeekly.Activated:Connect(function() refreshed += 1 end)
local weeklyRows = {}
for index = 1, 5 do
	weeklyRows[index] = Factory.Label(weekly, "Live creator " .. index, UDim2.new(1, -170, 0, 38), {Position = UDim2.fromOffset(56, 72 + (index-1)*46)})
end
local participant = Factory.ImageButton(participants, "A live participant", UDim2.new(1, -32, 0, 56), UDim2.fromOffset(16, 40))
local selectedParticipant = 0
participant.Activated:Connect(function() selectedParticipant += 1 end)
local lookViewport = Factory.New("ViewportFrame", {Name = "SelectedLook", Parent = hero,
	Position = UDim2.fromOffset(16, 82), Size = UDim2.new(1, -32, 0, 260)})
local lock = Factory.ImageButton(hero, "Lock in my look", UDim2.fromOffset(200, 44), UDim2.fromOffset(16, 366), "primary")
local locked = 0
lock.Activated:Connect(function() locked += 1 end)
ModernPageLayouts.Modal({compact = false}, runwayModal, "Runway")
check(find(runwayModal, "Participants"):FindFirstChild("ForgeScreenArt") ~= nil, "Runway modal uses its approved lineup art")
lock.Activated:Fire()
equal(locked, 1, "Runway modal artwork retains the original phase action callback")
equal(weekly.Parent.Name, "WeeklyColumn", "Runway moves its real weekly standings into the approved third column")
equal(lookViewport.Parent, hero, "Runway retains its actual selected-look viewport")
equal(lookViewport.Size.Y.Offset, 222, "Runway leaves room for its header, phase instructions, selected look, and live actions")
noOverlap(hero:FindFirstChild("SectionBanner"), phase, hero, "Runway title does not overlap its live phase pill")
noOverlap(hero:FindFirstChild("SectionBanner"), instruction, hero, "Runway title does not overlap its phase instruction")
noOverlap(phase, lookViewport, hero, "Runway phase pill stays above the selected-look viewport")
noOverlap(instruction, lookViewport, hero, "Runway instructions stay above the selected-look viewport")
noOverlap(lookViewport, lock.Parent, hero, "Runway viewport does not overlap its phase-action overflow")
noOverlap(participants:FindFirstChild("SectionBanner"), participant.Parent, participants, "Runway lineup starts below its readable title")
noOverlap(weekly:FindFirstChild("SectionBanner"), weeklyDescription, weekly, "Weekly title does not overlap its native description")
noOverlap(weekly:FindFirstChild("SectionBanner"), refreshWeekly, weekly, "Weekly title does not overlap the original Refresh button")
noOverlap(weeklyDescription, refreshWeekly, weekly, "Weekly description stays clear of the Refresh button")
noOverlap(weeklyXP, weeklyRows[1], weekly, "Weekly XP stays clear of the first live leaderboard row")
refreshWeekly.Activated:Fire()
equal(refreshed, 1, "Moving weekly content retains the original Refresh callback")
equal(weeklyRows[5].Text, "Live creator 5", "Weekly overflow retains every real creator row")
equal(lock.Parent.Name, "LookActions", "Runway keeps overflow phase actions reachable")
equal(lock.Parent.ScrollBarThickness, 4, "Runway exposes a visible scrollbar for native phase actions")
equal(participant.Parent.Name, "LiveRunwayLineup", "Runway preserves its existing participant list inside visible overflow")
participant.Activated:Fire()
equal(selectedParticipant, 1, "Runway keeps native participant selection working")
local weeklyParent = weekly.Parent
local weeklyXPPosition, weeklyRowPosition = weeklyXP.Position, weeklyRows[1].Position
ModernPageLayouts.Modal({compact = false}, runwayModal, "Runway")
equal(weekly.Parent, weeklyParent, "Repeated Runway updates reuse the existing standings column")
equal(count(runwayModal, "LookActions"), 1, "Repeated Runway updates do not duplicate phase-action containers")
equal(weeklyXP.Position, weeklyXPPosition, "Repeated Runway updates do not keep moving the live weekly XP")
equal(weeklyRows[1].Position, weeklyRowPosition, "Repeated Runway updates do not keep moving live weekly rows")
noOverlap(hero:FindFirstChild("SectionBanner"), instruction, hero, "Repeated Runway updates keep the header clear of phase instructions")
end

do
for _, compact in {false, true} do
	local nativeModal = Factory.New("Frame")
	local nativeStack = Factory.New("Frame", {Parent = nativeModal})
	local nativeLineup = Factory.ImageCard(nativeStack, UDim2.fromOffset(600, 400), nil, "Participants")
	local nativeHero = Factory.ImageCard(nativeStack, UDim2.fromOffset(600, 648), nil, "RoundHero")
	local nativeWeekly = Factory.ImageCard(nativeStack, UDim2.fromOffset(600, 336), nil, "WeeklyStandings")
	local nativeHeader = Factory.SectionBanner(nativeHero, "Your Look")
	local nativePhase = Factory.ImagePill(nativeHero, "Styling", fixtures.Theme.Colors.Cyan, 116)
	nativePhase.Position = UDim2.fromOffset(16, 34)
	local nativeInstruction = Factory.Label(nativeHero, "Lock in your current avatar look", UDim2.new(1, -160, 0, 38), {Position = UDim2.fromOffset(144, 30)})
	local nativeViewport = Factory.New("ViewportFrame", {Name = "SelectedLook", Parent = nativeHero,
		Position = UDim2.fromOffset(16, 82), Size = UDim2.new(1, -32, 0, 260)})
	ModernPageLayouts.Modal({compact = compact}, nativeModal, "Runway")
	equal(nativeHeader.Position.Y.Offset, 3, "Single-column Runway retains its native overhanging header")
	equal(nativePhase.Position.Y.Offset, 34, "Single-column Runway retains its native phase position")
	equal(nativeInstruction.Position.Y.Offset, 30, "Single-column Runway retains its native instruction position")
	equal(nativeViewport.Size.Y.Offset, 260, "Single-column Runway retains its native viewport height")
	equal(nativeWeekly.Parent, nativeStack, "Single-column Runway retains its native weekly stack")
end
end

local settingsEditor = {content = Factory.New("Frame"), activePage = "Settings", compact = false,
	state = {profile = {settings = {simpleMode = true, reduceMotion = false, highContrast = false, soundEnabled = true}}}}
local settingsPage = Factory.New("ScrollingFrame", {Name = "SettingsScroll", Parent = settingsEditor.content})
local settingsColumns = Factory.New("Frame", {Parent = settingsPage})
local settingsLeft = Factory.New("Frame", {Parent = settingsColumns})
local settingsRight = Factory.New("Frame", {Parent = settingsColumns})
Factory.List(settingsLeft, Enum.FillDirection.Vertical, 22)
Factory.List(settingsRight, Enum.FillDirection.Vertical, 22)
local createMode = Factory.ImageCard(settingsLeft, UDim2.new(1, 0, 0, 168), nil, "CreateMode")
Factory.SectionBanner(createMode, "Create Mode")
local simple = Factory.ImageButton(createMode, "Simple Mode · ON", UDim2.new(.5, -22, 0, 44), UDim2.fromOffset(16, 110))
local advanced = Factory.ImageButton(createMode, "Advanced Mode", UDim2.new(.5, -22, 0, 44), UDim2.new(.5, 6, 0, 110))
simple.Activated:Connect(function() settingsEditor.state.profile.settings.simpleMode = true end)
advanced.Activated:Connect(function() settingsEditor.state.profile.settings.simpleMode = false end)
local accessibility = Factory.ImageCard(settingsLeft, UDim2.new(1, 0, 0, 276), nil, "Accessibility")
Factory.SectionBanner(accessibility, "Accessibility")
local reduce = Factory.Switch(accessibility, false, UDim2.new(1, -108, 0, 46))
reduce.Activated:Connect(function() settingsEditor.state.profile.settings.reduceMotion = true; Factory.SetSwitch(reduce, true) end)
local contrastSwitch = Factory.Switch(accessibility, false, UDim2.new(1, -108, 0, 106))
contrastSwitch.Activated:Connect(function() settingsEditor.state.profile.settings.highContrast = true end)
local slider = Factory.New("TextButton", {Name = "ScaleTrack", Parent = accessibility, Position = UDim2.fromOffset(200, 162), Text = ""})
slider.InputBegan:Connect(function() settingsEditor.state.profile.settings.uiScale = 1.2 end)
local keyboardHelp = Factory.Label(accessibility, "Keyboard and gamepad navigation instructions", UDim2.new(1, -32, 0, 44), {Position = UDim2.fromOffset(16, 208)})
local audio = Factory.ImageCard(settingsLeft, UDim2.new(1, 0, 0, 104), nil, "Audio")
Factory.SectionBanner(audio, "Audio")
local sound = Factory.Switch(audio, true)
sound.Activated:Connect(function() settingsEditor.state.profile.settings.soundEnabled = false; Factory.SetSwitch(sound, false) end)
local inviteCard = Factory.ImageCard(settingsLeft, UDim2.new(1, 0, 0, 104), nil, "InviteFriends")
Factory.SectionBanner(inviteCard, "Grow the Studio")
Factory.Label(inviteCard, "Send a real Roblox invite", UDim2.fromOffset(200, 44))
local inviteAction = Factory.ImageButton(inviteCard, "Invite a friend", UDim2.fromOffset(190, 42))
local invited, joined = 0, 0
inviteAction.Activated:Connect(function() invited += 1 end)
local groupCard = Factory.ImageCard(settingsLeft, UDim2.new(1, 0, 0, 124), nil, "CreatorGroup")
Factory.SectionBanner(groupCard, "Creator community")
local benefits = Factory.Label(groupCard, "10% faster generation, +1 queue slot", UDim2.fromOffset(350, 44))
local groupAction = Factory.ImageButton(groupCard, "Join group", UDim2.fromOffset(188, 42))
groupAction.Activated:Connect(function() joined += 1 end)
local loadout = Factory.ImageCard(settingsRight, UDim2.new(1, 0, 0, 250), nil, "Loadout")
Factory.SectionBanner(loadout, "Equipped Now")
local equippedRow = Factory.New("Frame", {Name = "EquippedItem", Parent = loadout, Position = UDim2.fromOffset(16, 38), Size = UDim2.new(1, -32, 0, 56)})
local remove = Factory.ImageButton(equippedRow, "Remove", UDim2.fromOffset(104, 38))
local removed = 0
remove.Activated:Connect(function() removed += 1 end)
local achievements = Factory.ImageCard(settingsRight, UDim2.new(1, 0, 0, 480), nil, "Achievements")
Factory.SectionBanner(achievements, "Achievements · 4/14")
local achievementGrid = Factory.New("Frame", {Parent = achievements, Position = UDim2.fromOffset(16, 38), Size = UDim2.fromOffset(600, 600)})
Factory.New("UIGridLayout", {Parent = achievementGrid})
for index = 1, 14 do Factory.New("Frame", {Name = "Achievement" .. index, Parent = achievementGrid}) end
ModernPageLayouts.Apply(settingsEditor)
equal(createMode.Parent.Size.X.Offset, 753, "Settings uses the approved controls column")
equal(loadout.Parent.Size.X.Offset, 755, "Settings uses the approved equipped/achievement column")
advanced.Activated:Fire()
check(settingsEditor.state.profile.settings.simpleMode == false, "Settings keeps the Advanced Mode callback")
simple.Activated:Fire()
check(settingsEditor.state.profile.settings.simpleMode, "Settings keeps the Simple Mode callback")
reduce.Activated:Fire(); contrastSwitch.Activated:Fire(); slider.InputBegan:Fire({UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown})
check(settingsEditor.state.profile.settings.reduceMotion, "Settings keeps the Reduce Motion callback")
equal(reduce:FindFirstChild("Label").Text, "ON", "Relocated accessibility switches retain their native state captions")
check(settingsEditor.state.profile.settings.highContrast, "Settings keeps the High Contrast callback")
equal(settingsEditor.state.profile.settings.uiScale, 1.2, "Settings keeps native interface-size input")
sound.Activated:Fire()
check(not settingsEditor.state.profile.settings.soundEnabled, "Settings keeps the original audio toggle")
equal(sound:FindFirstChild("Label").Text, "OFF", "The audio switch retains its original native feedback")
equal(keyboardHelp.Parent.Name, "AccessibilityControls", "Settings retains all accessibility help in a visible overflow region")
equal(keyboardHelp.Parent.ScrollBarThickness, 4, "Settings accessibility overflow exposes its scrollbar")
equal(equippedRow.Parent.Name, "EquippedItems", "Settings preserves overflow for every equipped item")
remove.Activated:Fire()
equal(removed, 1, "Settings keeps the original equipped-item Remove callback")
equal(achievementGrid.Parent.Name, "EveryAchievement", "Settings retains the complete achievement grid in native overflow")
equal(#achievementGrid:GetChildren(), 15, "Settings preserves every achievement and its layout")
inviteAction.Activated:Fire(); groupAction.Activated:Fire()
equal(invited, 1, "Settings keeps the original Roblox friend-invite callback")
equal(joined, 1, "Settings keeps the original creator-group callback")
equal(inviteAction.Parent.Name, "CommunityActions", "Friend invitations remain visible in the community section")
equal(groupAction.Parent.Name, "CommunityActions", "Creator-group actions remain visible in the community section")
check(groupCard.Visible and benefits.Parent == groupCard, "Full creator-group benefits remain reachable below the compact community section")

local catalogEditor = {content = Factory.New("Frame"), editorHeader = Factory.New("Frame"), activePage = "Avatar Lab", compact = false,
	state = {profile = {settings = {simpleMode = true}}}, catalogWorkspace = {tab = "BROWSE", showChallenge = false}}
local catalogPage = Factory.New("ScrollingFrame", {Name = "AvatarLabWorkspace", Parent = catalogEditor.content, ScrollBarThickness = 5})
local catalogStack = Factory.New("Frame", {Parent = catalogPage})
local catalogTabs = Factory.New("ScrollingFrame", {Parent = catalogStack, LayoutOrder = -10, ScrollBarThickness = 4})
local myAvatar = Factory.ImageButton(catalogTabs, "My avatar", UDim2.fromOffset(140, 40))
myAvatar.Activated:Connect(function() catalogEditor.catalogWorkspace.tab = "LOOK" end)
local searchRow = Factory.New("Frame", {Parent = catalogStack, LayoutOrder = 1})
local catalogQuery = Factory.New("TextBox", {Parent = searchRow, Text = "a player's hat search"})
local catalogSearch = Factory.ImageButton(searchRow, "Search", UDim2.fromOffset(100, 40))
catalogSearch.Activated:Connect(function() catalogEditor.searchedQuery = catalogQuery.Text end)
local categories = Factory.New("ScrollingFrame", {Name = "CatalogCategories", Parent = catalogStack, LayoutOrder = 2, ScrollBarThickness = 5})
local hats = Factory.ImageButton(categories, "Hats", UDim2.fromOffset(80, 34))
hats.Activated:Connect(function() catalogEditor.selectedCategory = "Hat" end)
local filterRow = Factory.New("ScrollingFrame", {Parent = catalogStack, LayoutOrder = 3, ScrollBarThickness = 4})
local moreFilters = Factory.ImageButton(filterRow, "More filters", UDim2.fromOffset(120, 34))
moreFilters.Activated:Connect(function() catalogEditor.filtersOpen = true end)
local results = Factory.New("Frame", {Parent = catalogStack})
local resultsLayout = Factory.New("UIGridLayout", {Parent = results, CellSize = UDim2.new(.5, -5, 0, 326)})
local catalogCard = Factory.ImageCard(results, UDim2.fromOffset(300, 326), nil, "StyleItem")
local catalogImage = Factory.New("ImageLabel", {Parent = catalogCard, Image = "rbxthumb://actual-catalog-hat"})
local tryCatalog = Factory.ImageButton(catalogCard, "Try on · free", UDim2.new(1, -32, 0, 42), UDim2.fromOffset(16, 236))
local viewRoblox = Factory.ImageButton(catalogCard, "Buy / view in Roblox", UDim2.new(1, -32, 0, 36), UDim2.fromOffset(16, 282))
local bookmark = Factory.ImageButton(catalogImage, "Save", UDim2.fromOffset(60, 28))
local catalogTried, catalogViewed, bookmarked = 0, 0, 0
tryCatalog.Activated:Connect(function() catalogTried += 1 end)
viewRoblox.Activated:Connect(function() catalogViewed += 1 end)
bookmark.Activated:Connect(function() bookmarked += 1 end)
local loadMore = Factory.ImageButton(catalogStack, "Load more items", UDim2.fromOffset(200, 44))
local pagesLoaded = 0
loadMore.Activated:Connect(function() pagesLoaded += 1 end)
ModernPageLayouts.Apply(catalogEditor)
equal(catalogTabs.Parent, catalogEditor.editorHeader, "Avatar Lab preserves its original tab controls in the shared header")
myAvatar.Activated:Fire()
equal(catalogEditor.catalogWorkspace.tab, "LOOK", "Avatar Lab keeps its native My avatar action")
equal(catalogQuery.Text, "a player's hat search", "Avatar Lab keeps the player's native search query")
catalogSearch.Activated:Fire(); hats.Activated:Fire(); moreFilters.Activated:Fire()
equal(catalogEditor.searchedQuery, "a player's hat search", "Avatar Lab keeps the original search callback")
equal(catalogEditor.selectedCategory, "Hat", "Avatar Lab keeps native category selection")
check(catalogEditor.filtersOpen, "Relocated More filters retains its disclosure callback")
equal(moreFilters.Parent, categories, "Avatar Lab moves its original filter control into the category row")
check(categories.ScrollBarThickness > 0, "Avatar Lab preserves visible category overflow")
near(resultsLayout.CellSize.X.Scale, 1/3, "Avatar Lab uses the approved three-column catalog grid")
resultsLayout.CellSize = UDim2.new(.5, -5, 0, 326)
near(resultsLayout.CellSize.X.Scale, 1/3, "Native catalog resize listeners cannot overwrite the imported column layout")
equal(catalogImage.Image, "rbxthumb://actual-catalog-hat", "Avatar Lab keeps real catalog thumbnails")
tryCatalog.Activated:Fire(); viewRoblox.Activated:Fire(); bookmark.Activated:Fire(); loadMore.Activated:Fire()
equal(catalogTried, 1, "Avatar Lab keeps free try-on callbacks")
equal(catalogViewed, 1, "Avatar Lab keeps native Roblox item-view/purchase callbacks")
equal(bookmarked, 1, "Avatar Lab keeps native item bookmarking")
equal(pagesLoaded, 1, "Avatar Lab keeps native result pagination")

local graphicsEditor = {content = Factory.New("Frame"), editorHeader = Factory.New("Frame"), activePage = "Avatar Graphics", compact = false,
	state = {profile = {settings = {simpleMode = true}}}, graphicsTab = "CREATE"}
local graphicsPage = Factory.New("ScrollingFrame", {Name = "AvatarGraphicsScroll", Parent = graphicsEditor.content, ScrollBarThickness = 4})
local graphicsColumns = Factory.New("Frame", {Parent = graphicsPage})
Factory.List(graphicsColumns, Enum.FillDirection.Horizontal, 20)
local graphicsLeft = Factory.New("Frame", {Parent = graphicsColumns})
local graphicsRight = Factory.New("Frame", {Parent = graphicsColumns})
local composer = Factory.ImageCard(graphicsLeft, UDim2.new(1, 0, 0, 400), nil, "GraphicComposer")
local sourceRow = Factory.New("Frame", {Parent = composer, Position = UDim2.fromOffset(16, 32)})
local sourceAvatar = Factory.ImageButton(sourceRow, "From My Avatar", UDim2.fromOffset(200, 44))
sourceAvatar.Activated:Connect(function() graphicsEditor.graphicSource = "AVATAR" end)
local viewRow = Factory.New("Frame", {Parent = composer, Position = UDim2.fromOffset(16, 120)})
local fullBody = Factory.ImageButton(viewRow, "Full body", UDim2.fromOffset(120, 34))
fullBody.Activated:Connect(function() graphicsEditor.selectedAvatarView = "FULL_BODY" end)
local graphicsPrompt = Factory.New("TextBox", {Parent = composer, Text = "a player's actual art prompt",
	Position = UDim2.fromOffset(16, 180), Size = UDim2.new(1, -32, 0, 70)})
local graphicsGenerate = Factory.ImageButton(composer, "Create · R$ 19", UDim2.fromOffset(220, 42), UDim2.fromOffset(16, 350), "primary")
graphicsGenerate.Activated:Connect(function() graphicsEditor.checkoutPrompt = graphicsPrompt.Text end)
local gallery = Factory.ImageCard(graphicsRight, UDim2.new(1, 0, 0, 400), nil, "GraphicsGallery")
local galleryGrid = Factory.New("Frame", {Parent = gallery, Position = UDim2.fromOffset(16, 38), Size = UDim2.fromOffset(450, 700)})
Factory.New("UIGridLayout", {Parent = galleryGrid})
local ownedGraphic = Factory.New("Frame", {Parent = galleryGrid})
local ownedImage = Factory.New("ImageLabel", {Parent = ownedGraphic, Image = "rbxassetid://123456"})
local download = Factory.New("TextBox", {Parent = ownedGraphic, Text = "https://example.invalid/owned-full-resolution-image"})
local delete = Factory.ImageButton(ownedGraphic, "Delete", UDim2.fromOffset(100, 32))
local deleted = 0
delete.Activated:Connect(function() deleted += 1 end)
local graphicActivity = Factory.ImageCard(graphicsRight, UDim2.new(1, 0, 0, 144), nil, "GraphicActivity")
local graphicProgress = Factory.Label(graphicActivity, "72% · Painting your scene", UDim2.fromOffset(300, 24))
local graphicsTabs = Factory.New("Frame", {Parent = graphicsEditor.content})
local createTab = Factory.ImageButton(graphicsTabs, "Create", UDim2.fromOffset(100, 40))
local discoverTab = Factory.ImageButton(graphicsTabs, "Discover", UDim2.fromOffset(100, 40))
discoverTab.Activated:Connect(function() graphicsEditor.graphicsTab = "DISCOVER" end)
ModernPageLayouts.Apply(graphicsEditor)
equal(graphicsLeft.Size.X.Offset, 976, "Avatar Graphics uses the approved composer column")
equal(graphicsRight.Size.X.Offset, 529, "Avatar Graphics uses the approved gallery column")
equal(graphicsPrompt.Text, "a player's actual art prompt", "Avatar Graphics keeps the original editable prompt")
equal(graphicsGenerate.Text, "Create · R$ 19", "Avatar Graphics retains the live checkout price instead of the SVG example")
sourceAvatar.Activated:Fire(); fullBody.Activated:Fire(); graphicsGenerate.Activated:Fire()
equal(graphicsEditor.graphicSource, "AVATAR", "Avatar Graphics keeps native source selection")
equal(graphicsEditor.selectedAvatarView, "FULL_BODY", "Avatar Graphics keeps native avatar-view selection")
equal(graphicsEditor.checkoutPrompt, "a player's actual art prompt", "Avatar Graphics keeps the original checkout callback")
equal(ownedImage.Image, "rbxassetid://123456", "Avatar Graphics uses the player's actual generated picture")
equal(download.Text, "https://example.invalid/owned-full-resolution-image", "Avatar Graphics preserves the real editable download link")
equal(galleryGrid.Parent.Name, "LiveGraphicsGallery", "Avatar Graphics retains the complete gallery in native overflow")
equal(galleryGrid.Parent.ScrollBarThickness, 4, "Avatar Graphics gallery overflow exposes its scrollbar")
equal(graphicProgress.Text, "72% · Painting your scene", "Avatar Graphics retains live generation progress")
delete.Activated:Fire()
equal(deleted, 1, "Avatar Graphics retains the original delete callback")
equal(graphicsTabs.Parent, graphicsEditor.editorHeader, "Avatar Graphics keeps the original native tabs in the shared header")
discoverTab.Activated:Fire()
equal(graphicsEditor.graphicsTab, "DISCOVER", "Avatar Graphics keeps native Discover navigation")
local promptPosition = graphicsPrompt.Position
ModernPageLayouts.Apply(graphicsEditor)
equal(graphicsPrompt.Position, promptPosition, "Avatar Graphics Discover retains its existing public-art flow")

local ModernLayouts = require("ModernLayouts")
local function createFixture(withActivity, retry)
	local editor = {
		content = Factory.New("Frame"), activePage = "Create", compact = false,
		state = {profile = {settings = {simpleMode = true}}}, draftPrompt = "a crystal crown",
	}
	local page = Factory.New("ScrollingFrame", {Name = "CreateScroll", Parent = editor.content, ScrollBarThickness = 4})
	local stack = Factory.New("Frame", {Parent = page})
	local promptCard = Factory.ImageCard(stack, UDim2.new(1, 0, 0, 450))
	local prompt = Factory.New("TextBox", {Name = "CustomUGCPrompt", Text = editor.draftPrompt, Parent = promptCard})
	local counter = Factory.Label(promptCard, "15 / 500", UDim2.fromOffset(120, 20), {AnchorPoint = Vector2.new(1, 0)})
	prompt:GetPropertyChangedSignal("Text"):Connect(function()
		editor.draftPrompt = string.sub(prompt.Text, 1, 500)
		counter.Text = string.format("%d / 500", #prompt.Text)
	end)
	local safety = Factory.Label(promptCard,
		if retry then "Your retry credit will be used · No Robux charge" else "One custom 3D accessory · Roblox asks before charging R$ 199 · Nothing starts until you confirm",
		UDim2.new(1, -32, 0, 34))
	local ideas = Factory.New("ScrollingFrame", {Name = "IdeaSuggestions", Parent = promptCard,
		ScrollBarThickness = 3, ScrollingDirection = Enum.ScrollingDirection.X})
	Factory.List(ideas, Enum.FillDirection.Horizontal, 8)
	local chip = Factory.ImageButton(ideas, "Crystal Crown", UDim2.fromOffset(140, 34))
	chip.Activated:Connect(function() prompt.Text = "a golden crystal crown"; editor.selectedAccessoryType = "Hat" end)
	local generate = Factory.ImageButton(promptCard, if retry then "Use retry credit" else "Make My Item · R$ 199", UDim2.fromOffset(300, 48), nil, "primary")
	generate.Name = "CreatePersonalUGCButton"
	generate.Activated:Connect(function() editor.checkoutPrompt = editor.draftPrompt; editor.checkoutCount = (editor.checkoutCount or 0)+1 end)
	local methodRow = Factory.New("Frame", {Parent = stack})
	local advanced = Factory.ImageButton(methodRow, "MORE CREATION OPTIONS", UDim2.fromOffset(300, 34))
	advanced.Activated:Connect(function() editor.state.profile.settings.simpleMode = false end)
	local help = Factory.ImageButton(editor.content, "HOW IT WORKS", UDim2.fromOffset(100, 30))
	help.Activated:Connect(function() editor.customUGCGuideRequested = true end)
	local activity = Factory.ImageCard(stack, UDim2.new(1, 0, 0, 220), nil, "Activity")
	activity.Visible = withActivity
	local liveProgress = Factory.Label(activity, "64% · Building your model", UDim2.fromOffset(250, 24))
	return editor, {page = page, oldCard = promptCard, prompt = prompt, counter = counter, safety = safety,
		ideas = ideas, chip = chip, generate = generate, advanced = advanced, help = help, activity = activity, liveProgress = liveProgress}
end
local editor, live = createFixture(true, false)
ModernLayouts.Apply(editor)
local modernPanel = find(editor.content, "V2CreatePromptPanel")
equal(live.prompt.Parent, modernPanel, "Simple Create moves the existing editable prompt into the approved composition")
equal(live.prompt.Text, "a crystal crown", "Simple Create preserves an unfinished draft")
equal(live.counter.Parent, modernPanel, "Simple Create retains the original live character counter")
equal(live.generate.Parent, modernPanel, "Simple Create moves the original checkout button")
equal(live.generate.Text, "Make My Item · R$ 199", "Simple Create uses the live configured price instead of the SVG example")
check(live.generate.Active, "Simple Create keeps Roblox checkout available")
equal(live.safety.Parent, modernPanel, "Simple Create preserves the purchase confirmation note")
check(string.find(live.safety.Text, "Nothing starts until you confirm", 1, true) ~= nil, "Simple Create preserves its payment safety explanation")
check(not live.page.Visible and live.page.Parent == editor.content, "Original Create containers remain available to existing callbacks")
live.prompt.Text = "a blue crown"
equal(editor.draftPrompt, "a blue crown", "Repositioning the prompt preserves its native change listener")
equal(live.counter.Text, "12 / 500", "The relocated counter still follows typing")
live.chip.Activated:Fire()
equal(live.prompt.Text, "a golden crystal crown", "Relocated idea buttons still populate the original prompt")
equal(editor.selectedAccessoryType, "Hat", "Idea buttons retain their selected fit region")
equal(live.ideas.ScrollBarThickness, 3, "Idea overflow keeps its visible scrollbar")
live.generate.Activated:Fire()
equal(editor.checkoutPrompt, "a golden crystal crown", "The original checkout callback reads the edited draft")
equal(editor.checkoutCount, 1, "Imported presentation does not duplicate checkout callbacks")
equal(live.activity.Parent.Name, "V2CreationActivity", "Active generations stay reachable in the preview overflow")
equal(live.liveProgress.Parent, live.activity, "Active generation contents remain the original native controls")
equal(live.liveProgress.Text, "64% · Building your model", "Active generation progress retains its live value")
equal(find(editor.content, "V2CreatePreviewPanel").Size.Y.Offset, 651, "An active job uses the full measured preview panel")
live.advanced.Activated:Fire()
check(editor.state.profile.settings.simpleMode == false, "The relocated Advanced options button keeps its setting callback")
live.help.Activated:Fire()
check(editor.customUGCGuideRequested, "The relocated help button keeps its contextual guide callback")

local retryEditor, retryLive = createFixture(false, true)
ModernLayouts.Apply(retryEditor)
equal(retryLive.safety.Parent, find(retryEditor.content, "V2CreatePromptPanel"), "Retry-credit Create retains its no-charge explanation")
equal(retryLive.generate.Text, "Use retry credit", "Retry-credit Create keeps its real checkout label")
equal(find(retryEditor.content, "V2CreatePreviewPanel").Size.Y.Offset, 651, "Idle Create uses the full measured preview height")
for _, guard in {"compact", "advanced", "guide"} do
	local guarded, original = createFixture(false, false)
	if guard == "compact" then guarded.compact = true
	elseif guard == "advanced" then guarded.state.profile.settings.simpleMode = false
	else guarded.customUGCGuideRequested = true end
	ModernLayouts.Apply(guarded)
	check(original.page.Visible and original.prompt.Parent == original.oldCard, guard .. " Create retains its complete native flow")
	check(not guarded.content:FindFirstChild("V2CreatePromptPanel"), guard .. " Create does not receive a duplicate composition")
end

fixtures.ScreenAssets = nil
cache.Factory = nil
local withoutManifest = require("Factory")
local nativeOnly = withoutManifest.ImageCard(host, UDim2.fromOffset(350, 200))
check(not nativeOnly:FindFirstChild("Decal") and nativeOnly.BackgroundTransparency == 0, "A missing optional asset module never prevents native screens from rendering")
return checks
