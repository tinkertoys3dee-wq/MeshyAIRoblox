local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end
local Factory = require("Factory")
local HomeScreen = require("HomeScreen")
fixtures.Config.Retention.Quests = {
	{ key = "TRY_STYLE", label = "Try an accessory", tokens = 3 },
	{ key = "RUNWAY", label = "Finish a Runway round", tokens = 3 },
	{ key = "ARCADE", label = "Post a score", tokens = 3 },
}
fixtures.Config.Retention.QuestClearBonusTokens = 6
fixtures.Config.Retention.DailyStreakTokens = { 3, 6, 10, 20, 40, 50, 70 }
local app = {
	content = Instance.new("Frame"), gui = Instance.new("ScreenGui"), uiScaleInstance = Instance.new("UIScale"),
	pageConnections = {}, triedOnAssetIds = {},
	state = { profile = { tokens = 15, bonusTokens = 8, retryCredits = { PriorityPass = 2 } },
		questState = { questsDone = {} }, dailyBrief = { streak = 4, rewardDay = 4, nextDailyTokens = 40 } },
	_BindButton = function() end, _TrackScroll = function() end, _Track = function() end,
	_OpenPage = function(self, page) self.openedPage = page end,
	_SetStudioOpen = function(self, open) self.studioOpen = open end,
	_ShowVisualTutorial = function(self) self.tutorialOpened = true end,
	_ShowPlus = function(self) self.plusOpened = true end,
	_BuyPriorityPass = function(self) self.passOpened = true end,
	_OpenAfkLounge = function(self) self.afkOpened = true end,
	_Invoke = function(self, action, payload) self.invokedAction = action; self.invokedPayload = payload; return true end,
}
local function find(name)
	for _, child in app.content:GetDescendants() do if child.Name == name then return child end end
	error("Missing control: " .. name)
end
HomeScreen.Render(app)
check(app.homeBalanceLabels.tokens.Text == "23", "Home shows the real combined token balance")
check(app.homeBalanceLabels.passes.Text == "2", "Home shows actual available Priority Passes")
check(find("CreateCard").Position.Y.Offset == 266, "A new Home visit starts the staggered card entrance")
local function allButtonsPop()
	for _, child in app.content:GetDescendants() do
		if child:IsA("GuiButton") and not child:GetAttribute("ForgePopBound") then return false end
	end
	return true
end
check(allButtonsPop(), "Every desktop Home control opts into button pops")
for _, item in { { "CreateAction", "Create" }, { "MarketAction", "Discover" }, { "GamesAction", "Play" }, { "HomeLibrary", "My Studio" }, { "HomeSettings", "Settings" } } do
	find(item[1]).Activated:Fire()
	check(app.openedPage == item[2], item[1] .. " opens its real destination")
end
find("TutorialShortcut").Activated:Fire()
check(app.tutorialOpened, "Tutorial shortcut opens existing help")
find("PremiumShortcut").Activated:Fire()
check(app.plusOpened, "Premium uses the existing Roblox Plus flow")
find("CloseHome").Activated:Fire()
check(app.studioOpen == false, "Home can return to the game world")
find("PriorityPasses").Activated:Fire()
check(app.passOpened, "Ticket control uses the existing Priority Pass purchase flow")
find("ForgeTokens").Activated:Fire()
local wallet = app.homeModal
check(wallet:FindFirstChild("SpendableBalance", true):FindFirstChild("StatValue").Text == "15", "Wallet card preserves actual spendable tokens")
check(wallet:FindFirstChild("BonusBalance", true):FindFirstChild("StatValue").Text == "8", "Wallet card preserves actual bonus tokens separately")
local walletActions = {}
for _, child in wallet:GetDescendants() do if child.Name == "DetailAction" then walletActions[child.Text] = child end end
for _, text in { "Open Token Lounge", "Buy Tokens", "Get a Priority Pass" } do
	local action = walletActions[text]
	check(action and action.Selectable and action.Size.Y.Offset >= 58, "Wallet action retains a readable native hit target: " .. text)
	local caption = action:FindFirstChild("Caption")
	check(caption.Position.X.Offset >= 60 and caption.ZIndex > action.ZIndex, "Wallet caption clears its icon and surface: " .. text)
end
walletActions["Buy Tokens"].Activated:Fire()
runSpawn(#spawned)
check(app.invokedAction == "BuyTokens", "Wallet purchase keeps its original native server action in the offline fixture")
walletActions["Get a Priority Pass"].Activated:Fire()
check(app.passOpened and app.homeModal == nil, "Priority action retains existing purchase handler and closes the wallet")
find("MissionsShortcut").Activated:Fire()
check(app.homeModal and app.homeModal.Parent, "Missions opens a functional modal")
app.homeModal:Destroy()
app.homeModal = nil
find("CodesShortcut").Activated:Fire()
local codeField
for _, child in app.homeModal:GetDescendants() do if child.Name == "CatalogItemId" then codeField = child end end
check(codeField and codeField:IsA("TextBox"), "Item code entry remains a native editable control")
local category
for _, child in app.homeModal:GetDescendants() do if child:IsA("TextButton") and child.Text == "Category: Hat  ›" then category = child end end
category.Activated:Fire()
check(category:FindFirstChild("Caption").Text == "Category: HairAccessory", "Restyled category selector updates its native caption")
check(category:FindFirstChild("ActionChevron") ~= nil, "Category selector keeps one separate arrow lane")
app.homeModal:Destroy()
app.homeModal = nil
local root = find("ForgeHome")
root.AbsoluteSize = Vector2.new(390, 700)
check(find("HomeScroll").ScrollBarThickness > 0, "Phone layout exposes a visible scrolling region")
check(find("CreateAction").Size.Y.Offset >= 44, "Phone primary action remains touch sized")
check(app.homeNavButtons.Home.Visible and app.homeNavButtons.Home.Selectable, "Keyboard focus targets visible Home navigation")
check(allButtonsPop(), "Every rebuilt phone Home control retains button pops")
app.state.profile.tokens = 1000000
HomeScreen.Refresh(app)
check(app.homeBalanceLabels.tokens.Text == "1.0M", "Large balances stay inside the currency pill")
for _, connection in app.pageConnections do connection:Disconnect() end
table.clear(app.pageConnections)
root:Destroy()
HomeScreen.Render(app)
check(find("CreateCard").Position.Y.Offset == 244, "Profile refreshes do not replay the entrance")
for _, connection in app.pageConnections do connection:Disconnect() end
table.clear(app.pageConnections)
find("ForgeHome"):Destroy()
app.animateNextPage = true
HomeScreen.Render(app)
check(find("CreateCard").Position.Y.Offset == 266, "Returning from another page replays the entrance")

local Chrome = require("HomeChrome")
local chrome = setmetatable({ shell = Factory.New("Frame"), nav = Factory.New("Frame"),
	backgroundLayer = Factory.New("Frame"), content = Factory.New("Frame"), activePage = "Home", compact = false,
	uiScaleInstance = app.uiScaleInstance, gui = app.gui, state = app.state,
	_BindButton = app._BindButton, _OpenPage = app._OpenPage, _SetStudioOpen = app._SetStudioOpen }, { __index = Chrome })
local topbar = Factory.New("Frame", { Name = "Topbar", Parent = chrome.shell })
chrome:_ApplyHomeChrome()
check(not topbar.Visible and not chrome.nav.Visible, "Home replaces the old header and sidebar")
check(chrome.content.Size.X.Scale == 1 and chrome.content.Position.X.Scale == 0, "Home uses the full shell")
chrome.activePage = "Create"
chrome:_ApplyHomeChrome()
check(not topbar.Visible and not chrome.nav.Visible and chrome.editorRoot.Visible, "Leaving Home uses the shared modern editor navigation")
check(chrome.content.Parent == chrome.editorCanvas and chrome.content.Size.X.Offset == 1586, "Editor pages use the shared logical SVG canvas")
chrome.compact = true
chrome:_ApplyHomeChrome()
local compactHeaderHeight = if chrome.editorRoot.AbsoluteSize.X >= 520 then 168 else 200
check(chrome.content.Position.Y.Offset == compactHeaderHeight and chrome.content.Size.Y.Offset == -compactHeaderHeight - 12, "Mobile editor pages leave room for the shorter compact modern header")
return checks
