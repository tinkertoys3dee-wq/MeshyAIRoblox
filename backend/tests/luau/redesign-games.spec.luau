-- Functional layout checks use real Factory/Skin modules with local image IDs.
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function equal(actual, expected, message) check(actual == expected, message) end
local function find(parent, name)
	for _, child in parent:GetDescendants() do if child.Name == name then return child end end
	error("Missing " .. name)
end
fixtures.HomeAssets = { Backdrop = 11, LogoMark = 12 }
fixtures.ScreenAssets = {}
fixtures.RedesignAssets = setmetatable({}, { __index = function() return 100 end })
fixtures.RedesignMetrics = { screens = {} }
fixtures.Config.Arcade = { Games = table.create(11, {}), WeeklyRewards = {150,83,33}, DailyChallengeBonusTokens = 5 }
fixtures.Config.Runway = { WeeklyPlacementXP = {600,350,200} }
fixtures.DailyChallenge = {}
-- Roblox GuiObjects default to ZIndex 1; the shared old double omits it.
local newInstance = Instance.new
Instance.new = function(class)
	local instance = newInstance(class)
	instance.ZIndex = 1
	return instance
end
local Factory = require("Factory")
local Layouts = require("RedesignGamesLayouts")
local clicked, closed = 0, 0
local app = { compact = false, activePage = "Play", content = Factory.New("Frame"),
	state = { profile = { settings = {}, tokens = 15, bonusTokens = 8, retryCredits = { PriorityPass = 2 } } },
	_BindButton = function() end,
	_OpenPage = function(self, page) self.opened = page end,
	_SetStudioOpen = function(self, value) self.studioOpen = value end,
	_BuyPriorityPass = function(self) self.buyPass = true end,
	_Invoke = function() end,
}
local function label(parent, name, value)
	return Factory.Label(parent, value or name, UDim2.fromOffset(140, 28), { Name = name })
end
local function button(parent, name)
	local result = Factory.ImageButton(parent, name, UDim2.fromOffset(100, 40))
	result.Name = name
	result.Activated:Connect(function() clicked += 1 end)
	return result
end
local page = Factory.New("ScrollingFrame", { Name = "PlayScroll", Parent = app.content })
local stack = Factory.New("Frame", { Parent = page })
for index=1,3 do
	local card = Factory.ImageCard(stack, UDim2.fromOffset(500,116))
	card.LayoutOrder = index
	label(card, "Title", "Destination").Position = UDim2.fromOffset(18,16)
	label(card, "Description", "Real description").Position = UDim2.fromOffset(18,48)
	button(card, "Open")
end
check(Layouts.Apply(app), "Desktop Games consumes the new layout")
local cards = {}
for _, card in stack:GetChildren() do if card:IsA("Frame") then table.insert(cards, card) end end
equal(cards[1].Position.X.Offset, 68, "Arcade uses measured x")
equal(cards[3].Position.X.Offset, 1118, "Lounge uses measured x")
equal(cards[1].Size.Y.Offset, 545, "Destination cards keep their full illustrated height")
find(cards[1], "Open").Activated:Fire()
equal(clicked, 1, "Artwork preserves destination activation")
app.compact = true
check(not Layouts.Apply(app), "Phone Games keeps its existing scrolling layout")
app.compact = false

local overlay = Factory.New("Frame", { AbsoluteSize = Vector2.new(1200,800) })
local modal = Factory.ImageCard(overlay, UDim2.fromOffset(900,700), nil, "ArcadeModal")
modal.ZIndex = 211
Factory.New("UISizeConstraint", {MinSize = Vector2.new(300,420), MaxSize = Vector2.new(1672,941), Parent = modal})
label(modal, "OldTitle", "ARCADE")
label(modal, "ArcadeTitle", "11 free games")
button(modal, "CloseButton")
Factory.New("Frame", {Name="RewardBanner", Parent=modal})
Factory.New("Frame", {Name="HeaderRule", Parent=modal})
local hub = Factory.New("ScrollingFrame", {Name="HubView", Parent=modal})
for _, name in {"GameView","LeaderboardView","TransitionOverlay"} do Factory.New("Frame", {Name=name, Parent=modal}) end
local keys = {"FlappyBird","DinoRunner","ColorSwitch","NeonSnake","BlockStacker","BrickBreaker","ReflexTap","PrismMerge","MeteorRush","SkyHopper","EchoMatch","Leaderboard"}
for index,key in keys do
	local card = Factory.New("TextButton", {Name=key.."Tile", Position=UDim2.fromOffset((index-1)%2*250,math.floor((index-1)/2)*180), Parent=hub})
	label(card,"GameTitle",key); label(card,"GameDescription","Description")
	if key ~= "Leaderboard" then label(card,"BestScore","—") end
	Factory.New("Frame", {Name="IconBadge",Parent=card})
	Factory.New("Frame", {Name="ChallengeChip",Parent=card})
	button(card,"PlayPill")
end
Layouts.Modal(app,modal,"Arcade",function() closed += 1 end)
equal(modal.Size.X.Offset,1672,"Arcade uses logical desktop width")
equal(find(hub,"NeonSnakeTile").Position.X.Offset,1170,"Four cards fit across the first row")
equal(find(hub,"LeaderboardTile").Position.Y.Offset,347,"Twelve destinations fit three rows")
check(find(hub,"LeaderboardTile").Position.Y.Offset+find(hub,"LeaderboardTile").Size.Y.Offset <= hub.Size.Y.Offset,"Last Arcade tile stays inside the visible canvas")
find(hub,"FlappyBirdTile"):FindFirstChild("PlayPill").Activated:Fire()
equal(clicked,2,"Visible Play controls retain gameplay callbacks")
equal(find(hub,"FlappyBirdTile"):FindFirstChild("BestScore").Text,"Best: —","Best stays unknown until real data arrives")
check(string.find(find(modal,"DailyReward").Text,"5",1,true)~=nil,"Daily reward comes from Config")
hub.Visible = false
check(not find(modal,"DailyChallengePanelArt").Visible,"Daily challenge hides while a game is running")
find(modal,"ModalNavHome").Activated:Fire()
equal(closed,1,"Header navigation closes through the owner callback")
equal(app.opened,"Home","Header navigation reaches the real Home page")

local runway = Factory.ImageCard(overlay,UDim2.fromOffset(1000,760),nil,"RunwayModal")
runway.ZIndex = 231
local header=Factory.New("Frame",{Name="Header",Parent=runway})
label(header,"RunwayTitle","FORGE RUNWAY"); label(header,"RunwayTheme","Cyber Royalty"); label(header,"RunwayPhase","STYLE")
local timer=Factory.New("Frame",{Name="TimerRing",Parent=header}); label(timer,"RunwayClock","01:24")
button(header,"CloseButton")
local body=Factory.New("ScrollingFrame",{Name="RunwayContent",Parent=runway})
local runStack=Factory.New("Frame",{Name="Stack",Parent=body})
local columns=Factory.New("Frame",{Parent=runStack})
local left=Factory.New("Frame",{Parent=columns}); local right=Factory.New("Frame",{Parent=columns})
local lineup=Factory.ImageCard(left,UDim2.fromOffset(501,534),nil,"Participants")
label(lineup,"SectionBanner","Lineup")
for index=1,6 do
	local row=Factory.New("TextButton",{Name="LookRow",Parent=lineup}); row:SetAttribute("RunwayEntryIndex",index)
	Factory.New("ImageLabel",{Name="EntryAvatar",Image="LIVE_AVATAR",Parent=row})
	label(row,"EntryName","Actual player"); label(row,"EntryStatus","Styling")
	button(row,"ViewLook"); button(row,"VoteOrLeave")
end
local hero=Factory.ImageCard(right,UDim2.fromOffset(601,535),nil,"RoundHero")
label(hero,"SectionBanner","Your Look"); label(hero,"LookInstruction","Lock before the timer")
label(hero,"CreatorXp","320 XP"); label(hero,"CreatorLevel","LEVEL 2")
Factory.New("Frame",{Name="CreatorXpTrack",Parent=hero})
local preview=Factory.New("ViewportFrame",{Name="SelectedLook",Parent=hero}); button(preview,"ResetCamera")
button(hero,"OpenAvatarLab"); button(hero,"LockLook"); button(hero,"InviteRunwayFriends")
local weekly=Factory.ImageCard(right,UDim2.fromOffset(426,535),nil,"WeeklyStandings")
label(weekly,"SectionBanner","Weekly standings"); button(weekly,"RefreshWeekly")
for index=1,5 do
	local row=Factory.New("Frame",{Name="WeeklyRow",Parent=weekly}); row:SetAttribute("WeeklyEntryIndex",index)
	Factory.New("Frame",{Name="WeeklyRank",Parent=row})
	Factory.New("ImageLabel",{Name="WeeklyAvatar",Image="LIVE_FACE",Parent=row})
	label(row,"WeeklyName","Player"); label(row,"WeeklyScore","1,500 pts")
end
local extra=Factory.ImageCard(left,UDim2.fromOffset(500,280),nil,"FirstLookJourney")
Layouts.Modal(app,runway,"Runway",function() closed += 1 end)
equal(find(runway,"SelectedLook"),preview,"Runway preserves the live ViewportFrame instance")
equal(preview.Parent,hero,"The live avatar remains inside its hero panel")
equal(find(runway,"ResetCamera").Parent,hero,"Camera reset remains accessible beside the live avatar")
find(runway,"ResetCamera").Activated:Fire()
equal(clicked,3,"Camera reset retains its original callback")
equal(hero.Position.X.Offset,577,"Hero uses measured middle column")
equal(weekly.Position.X.Offset,1194,"Weekly standings use measured right column")
local live=find(lineup,"LiveRunwayLineup")
equal(#live:GetChildren(),6,"Every server entrant stays reachable beyond four visible rows")
equal(find(live,"EntryAvatar").Image,"LIVE_AVATAR","Sample artwork never replaces live entrant portraits")
equal(extra.Parent,runStack,"First-look journey remains accessible below the primary panels")
check(extra.Position.Y.Offset>=553,"Journey stays below the measured primary panels")
check(string.find(find(weekly,"WeeklyXpRewards").Text,"600",1,true)~=nil,"Weekly XP uses real server Config")
check(runStack.Size.Y.Offset>540,"Overflow content retains scrolling reach")
equal(find(runway,"ModalTokenBalance").Text,"23","Modal balances use the pushed profile")
equal(find(runway,"ModalPassBalance").Text,"2","Pass inventory stays native and live")
return checks
