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
fixtures.Theme.Colors.Text = Color3.new(1,1,1)
fixtures.Theme.Colors.Ink = Color3.new(0.04,0.05,0.09)
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
equal(find(cards[1], "Open").TextColor3, fixtures.Theme.Colors.Text, "Arcade action uses a bright caption on its cyan surface")
equal(find(cards[2], "Open").TextColor3, fixtures.Theme.Colors.Text, "Runway action uses a bright caption on its purple surface")
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
for _, name in {"GameView","LeaderboardView","ViewTransition"} do Factory.New("Frame", {Name=name, Parent=modal}) end
local keys = {"FlappyBird","DinoRunner","ColorSwitch","NeonSnake","BlockStacker","BrickBreaker","ReflexTap","PrismMerge","MeteorRush","SkyHopper","EchoMatch","Leaderboard"}
for index,key in keys do
	local card = Factory.New("TextButton", {Name=key.."Tile", Position=UDim2.fromOffset((index-1)%2*250,math.floor((index-1)/2)*180), Parent=hub})
	label(card,"GameTitle",key); label(card,"GameDescription","Description")
	if key ~= "Leaderboard" then label(card,"BestScore","—") end
	Factory.New("Frame", {Name="IconBadge",Parent=card})
	local challenge = Factory.New("Frame", {Name="ChallengeChip",Parent=card})
	label(challenge, "Target", "Target: 30")
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
equal(find(modal,"ModalNavHome").TextColor3,fixtures.Theme.Colors.Text,"Inactive Arcade navigation has a white caption on navy")
equal(find(modal,"ModalMyItems").TextColor3,fixtures.Theme.Colors.Text,"Modal My Items does not inherit dark gold-card text")
equal(find(modal,"ModalNavHome"):FindFirstChildOfClass("UIStroke").Transparency,1,"Inactive navigation does not retain a gold button outline")
equal(find(find(hub,"FlappyBirdTile"),"PlayPill").TextColor3,fixtures.Theme.Colors.Text,"Cyan play surfaces get a white caption")
equal(find(find(hub,"ColorSwitchTile"),"PlayPill").TextColor3,fixtures.Theme.Colors.Text,"Purple play surfaces get a white caption")
equal(find(find(hub,"NeonSnakeTile"),"PlayPill").TextColor3,fixtures.Theme.Colors.Ink,"Gold play surfaces keep contrasting dark captions")
local arcadeHero = find(modal,"ArcadeHeroPanelArt")
find(arcadeHero,"RedesignArt").IsLoaded = true
check(find(modal,"OldTitle").ZIndex > find(arcadeHero,"RedesignArt").ZIndex,"Loaded hero artwork stays beneath the Arcade title")
check(find(modal,"ArcadeTitle").ZIndex > find(arcadeHero,"RedesignArt").ZIndex,"Loaded hero artwork stays beneath the Arcade subtitle")
local transition = find(modal,"ViewTransition")
check(transition.Position.Y.Offset >= find(modal,"ArcadeTitle").Position.Y.Offset+find(modal,"ArcadeTitle").Size.Y.Offset,"Real Arcade transition starts below the heading")
equal(transition.Position.Y.Offset,find(modal,"GameView").Position.Y.Offset,"Transition and game cover the same content area")
check(transition.Position.Y.Offset+transition.Size.Y.Offset<=900,"Transition stays inside the shell")
equal(find(find(hub,"FlappyBirdTile"),"Target").TextSize,18,"Daily targets remain legible at the fitted desktop scale")
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
	button(row,"ViewLook"); button(row,"VoteOrLeave").Active = true
end
local hero=Factory.ImageCard(right,UDim2.fromOffset(601,535),nil,"RoundHero")
label(hero,"SectionBanner","Your Look"); label(hero,"LookInstruction","Lock before the timer")
label(hero,"CreatorXp","320 XP"); label(hero,"CreatorLevel","LEVEL 2")
label(hero,"CreatorTitle","Forge Apprentice"); label(hero,"RunwayStats","0 rounds · 0 wins · 0 votes cast")
label(hero,"DailyEncore","DAILY ENCORE 0/2 ROUNDS · +5 TOKENS · +20 XP")
label(hero,"EquippedLookName","Nothing equipped yet"); label(hero,"EquippedLookHelp","Change it in My Studio before you lock.")
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
label(extra,"JourneyTitle","YOUR FIRST MAKEOVER"); label(extra,"JourneyCount","0 / 4")
label(extra,"JourneyHelp","Free path · each step +2 bonus tokens · finish +12 and +100 Creator XP")
for index=1,4 do
	local step=Factory.New("Frame",{Name="JourneyStep",Parent=extra})
	label(step,"JourneyStepIcon","◆"); label(step,"JourneyStepName","Step "..index); label(step,"JourneyStepReward","+2")
end
Layouts.Modal(app,runway,"Runway",function() closed += 1 end)
equal(find(runway,"SelectedLook"),preview,"Runway preserves the live ViewportFrame instance")
equal(preview.Parent,hero,"The live avatar remains inside its hero panel")
local avatarStage=find(hero,"V2RunwayAvatarStage")
equal(preview.BackgroundTransparency,1,"Runway keeps the same live viewport transparent above its native stage")
check(preview.ZIndex>avatarStage.ZIndex,"The hologram stage sits behind the live avatar viewport")
check(not avatarStage.Active,"Decorative stage does not intercept avatar dragging")
equal(find(avatarStage,"HologramRim").ClassName,"Frame","Runway light ring is native geometry rather than a painted avatar")
equal(find(runway,"ResetCamera").Parent,hero,"Camera reset remains accessible beside the live avatar")
find(runway,"ResetCamera").Activated:Fire()
equal(clicked,3,"Camera reset retains its original callback")
equal(hero.Position.X.Offset,577,"Hero uses measured middle column")
equal(weekly.Position.X.Offset,1194,"Weekly standings use measured right column")
local live=find(lineup,"LiveRunwayLineup")
equal(#live:GetChildren(),6,"Every server entrant stays reachable beyond four visible rows")
equal(find(live,"EntryAvatar").Image,"LIVE_AVATAR","Sample artwork never replaces live entrant portraits")
check(find(live,"VoteOrLeave").Size.Y.Offset>=41,"Runway vote and leave targets stay usable after the desktop fit")
check(find(live,"VoteOrLeave").Position.Y.Offset>=find(live,"ViewLook").Position.Y.Offset+find(live,"ViewLook").Size.Y.Offset,"Vote and view actions do not overlap")
equal(extra.Parent,runStack,"First-look journey remains accessible below the primary panels")
check(extra.Position.Y.Offset>=553,"Journey stays below the measured primary panels")
check(string.find(find(weekly,"WeeklyXpRewards").Text,"600",1,true)~=nil,"Weekly XP uses real server Config")
check(find(weekly,"SectionBanner").Position.X.Offset+find(weekly,"SectionBanner").Size.X.Offset+12<=find(weekly,"RefreshWeekly").Position.X.Offset,"Weekly heading reserves space before Refresh")
check(find(weekly,"WeeklyXpRewards").TextSize>=18,"Placement XP stays legible after fitting the modal")
check(find(weekly,"WeeklyXpHelp").TextSize>=18,"Weekly XP footer stays legible after fitting the modal")
check(runStack.Size.Y.Offset>540,"Overflow content retains scrolling reach")
equal(find(runway,"ModalTokenBalance").Text,"23","Modal balances use the pushed profile")
equal(find(runway,"ModalPassBalance").Text,"2","Pass inventory stays native and live")
local summary = find(runway,"CreatorSummaryPanel")
equal(summary.Position.Y.Offset,553,"Creator metadata starts directly beneath the avatar beside the journey")
equal(find(runway,"CreatorTitle").Parent,summary,"Native Creator title stays inside its own summary card")
check(find(runway,"DailyEncore").TextWrapped,"Daily progress wraps inside its card")
equal(find(extra,"JourneyStepName").TextSize,22,"Journey steps stay readable at the fitted desktop scale")
check(find(hero,"CreatorXp").ZIndex > find(find(hero,"V2DecorationCreatorXpStripArt"),"RedesignArt").ZIndex,"XP artwork cannot cover live XP text")

-- Empty servers and a loading/empty weekly board are real states; they need
-- clear native copy rather than fake painted players or tiny legacy labels.
local empty = Factory.ImageCard(overlay,UDim2.fromOffset(1000,760),nil,"RunwayEmptyModal")
empty.ZIndex = 231
local emptyHeader = Factory.New("Frame",{Name="Header",Parent=empty})
label(emptyHeader,"RunwayTitle","FORGE RUNWAY"); label(emptyHeader,"RunwayTheme","Style challenge"); label(emptyHeader,"RunwayPhase","STYLE")
local emptyTimer=Factory.New("Frame",{Name="TimerRing",Parent=emptyHeader}); label(emptyTimer,"RunwayClock","01:24")
button(emptyHeader,"CloseButton")
local emptyBody=Factory.New("ScrollingFrame",{Name="RunwayContent",Parent=empty})
local emptyStack=Factory.New("Frame",{Name="Stack",Parent=emptyBody})
local emptyLineup=Factory.ImageCard(emptyStack,UDim2.fromOffset(501,534),nil,"Participants")
label(emptyLineup,"SectionBanner","Runway Lineup · 0 joined")
label(emptyLineup,"RunwayLineupEmpty","Be the first player under the spotlight.")
local emptyHero=Factory.ImageCard(emptyStack,UDim2.fromOffset(601,535),nil,"RoundHero")
label(emptyHero,"SectionBanner","Your Look"); label(emptyHero,"LookInstruction","Join next round")
local emptyPreview=Factory.New("ViewportFrame",{Name="SelectedLook",Parent=emptyHero}); button(emptyPreview,"ResetCamera")
button(emptyHero,"OpenAvatarLab"); button(emptyHero,"LockLook"); button(emptyHero,"InviteRunwayFriends")
local emptyWeekly=Factory.ImageCard(emptyStack,UDim2.fromOffset(426,535),nil,"WeeklyStandings")
label(emptyWeekly,"SectionBanner","Weekly Spotlight"); button(emptyWeekly,"RefreshWeekly")
label(emptyWeekly,"RunwayWeeklyEmpty","No weekly points yet. Lock in the first look.")
Layouts.Modal(app,empty,"Runway",function() closed += 1 end)
equal(find(empty,"RunwayLineupEmpty").TextSize,30,"Empty lineup no longer uses a six-pixel fitted label")
check(find(empty,"RunwayLineupEmpty").Position.Y.Offset>=200,"Empty lineup copy clears the panel heading and crown")
check(find(empty,"RunwayLineupEmptyHelp").TextWrapped,"Empty lineup instructions fit their native panel")
equal(find(empty,"RunwayWeeklyEmpty").TextSize,27,"Empty weekly board has readable text")
equal(#find(empty,"LiveRunwayLineup"):GetChildren(),0,"Empty lineup does not fabricate server players")
check(find(empty,"WeeklyEmptyHelp").Position.Y.Offset+find(empty,"WeeklyEmptyHelp").Size.Y.Offset<398,"Weekly empty copy clears the reward card")
return checks
