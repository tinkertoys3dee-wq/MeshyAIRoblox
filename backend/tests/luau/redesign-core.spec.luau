local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function equal(actual, expected, message) check(actual == expected, message .. ": " .. tostring(actual)) end
local function find(parent, name)
	for _, child in parent:GetDescendants() do if child.Name == name then return child end end
	error("Missing " .. name)
end
fixtures.ScreenAssets = {}
fixtures.HomeAssets = {}
fixtures.RedesignAssets = setmetatable({}, { __index = function() return 100 end })
fixtures.RedesignMetrics = { screens = {} }
local Factory = require("Factory")
local Skin = require("RedesignSkin")
local Layouts = require("RedesignCoreLayouts")
local clicked = 0
local function button(parent, name, value, y)
	local result = Factory.ImageButton(parent, value or name, UDim2.fromOffset(150,40), UDim2.fromOffset(16,y or 0))
	result.Name = name
	result.Activated:Connect(function() clicked += 1 end)
	return result
end
local function label(parent, name, value, x, y)
	return Factory.Label(parent, value or name, UDim2.fromOffset(250,32), {Name=name,Position=UDim2.fromOffset(x or 0,y or 0)})
end
local function appFor(page)
	local app = {content = Factory.New("Frame"),activePage=page,compact=false,
		state={profile={settings={simpleMode=true},items={},itemOrder={}},policy={contentSharingAllowed=true}},
		_BindButton=function() end,_OpenPage=function(self,p) self.opened=p end,
		_TextBox=function(self,parent,placeholder,size,position)
			return Factory.New("TextBox",{Parent=parent,PlaceholderText=placeholder,Size=size,Position=position})
		end,
		_Invoke=function(self,action,payload) self.invoked=action; self.payload=payload; return false end,
		_Toast=function() end,_RenderActivePage=function(self) self.rendered=true end,
	}
	label(app.content,"PageTitle","Existing heading"); label(app.content,"PageSubtitle","Existing subtitle")
	return app
end

local create=appFor("Create")
local page=Factory.New("ScrollingFrame",{Name="CreateScroll",Parent=create.content})
local oldCard=Factory.ImageCard(page,UDim2.fromOffset(600,400))
local prompt=Factory.New("TextBox",{Name="CustomUGCPrompt",Text="My own idea",Parent=oldCard})
local counter=label(oldCard,"CharacterCounter","11 / 300")
prompt:GetPropertyChangedSignal("Text"):Connect(function() counter.Text=tostring(#prompt.Text).." / 300" end)
local ideas=Factory.New("ScrollingFrame",{Name="IdeaSuggestions",Parent=oldCard})
Factory.List(ideas,Enum.FillDirection.Horizontal,8)
for index=1,5 do button(ideas,"Idea"..index,"Original idea") end
local generate=button(oldCard,"CreatePersonalUGCButton","Make my item · R$199")
local more=button(page,"MoreCreationOptions","MORE CREATION OPTIONS")
local help=button(page,"Help","HOW IT WORKS")
check(Layouts.Apply(create),"Simple Create uses the new screen")
equal(prompt.Text,"My own idea","The editable prompt never changes during import")
equal(prompt.ClassName,"TextBox","The prompt stays a native text input")
prompt.Text="A real updated idea"
equal(counter.Text,"19 / 300","The existing character counter follows the moved field")
equal(generate.Text,"Make my item · R$199","Generation retains its configured price disclosure")
generate.Activated:Fire(); more.Activated:Fire(); help.Activated:Fire(); find(create.content,"Idea3").Activated:Fire()
equal(clicked,4,"Generation, advanced, help, and idea callbacks remain attached")
equal(prompt.Parent.Name,"V2CreatePromptPanel","The live prompt moves into its measured panel")
equal(generate.Parent.Position.X.Offset,65,"The creation panel uses measured geometry")
check(not page.Visible,"Original containers remain alive for callbacks without duplicating the old screen")
create.compact=true
local before=prompt.Parent
check(not Layouts.Apply(create),"Phone Create retains its native responsive fallback")
equal(prompt.Parent,before,"Fallback checks do not mutate the live input")
create.compact=false; create.state.profile.settings.simpleMode=false
check(not Layouts.Apply(create),"Advanced Create retains all original controls")

local running=appFor("Create")
local runningPage=Factory.New("ScrollingFrame",{Name="CreateScroll",Parent=running.content})
local runningCard=Factory.ImageCard(runningPage,UDim2.fromOffset(600,400))
Factory.New("TextBox",{Name="CustomUGCPrompt",Text="A pending creation",Parent=runningCard})
Factory.New("ScrollingFrame",{Name="IdeaSuggestions",Parent=runningCard})
button(runningCard,"CreatePersonalUGCButton","Make my item · R$199")
local activity=Factory.New("Frame",{Name="Activity",Size=UDim2.fromOffset(600,200),Visible=true,Parent=runningPage})
local stage=label(activity,"RealStage","TEXTURING")
local progress=label(activity,"RealProgress","64%")
button(activity,"InspectPending","Inspect pending item")
check(Layouts.Apply(running),"An active creation uses the redesigned frame")
equal(activity.Parent.Name,"V2CreationActivity","Actual activity moves into reachable preview overflow")
equal(activity.Visible,true,"A running job remains visible after its old parent is hidden")
equal(find(running.content,"RealStage"),stage,"The original live generation-stage label survives")
equal(progress.Text,"64%","Generation progress remains actual server data")
local beforeActivity=clicked
find(running.content,"InspectPending").Activated:Fire()
equal(clicked,beforeActivity+1,"An active job retains its inspect callback")
stage.Text="SUCCEEDED"; equal(find(running.content,"RealStage").Text,"SUCCEEDED","Existing completion updates reach the moved activity")

local function makeStudio(personalCopy)
	local app=appFor("My Studio")
	app.state.profile.items={itemA={id="itemA",name="Actual wings"},itemB={id="itemB",title="Live crown title",name="Live crown",license=if personalCopy then "PERSONAL_COPY" else nil}}
	app.state.profile.itemOrder={"itemA","itemB"}; app.selectedItemId="itemB"
	local collection=Factory.ImageCard(app.content,UDim2.fromOffset(300,500),nil,"Collection")
	label(collection,"SectionBanner","Collection")
	local scroll=Factory.New("ScrollingFrame",{Parent=collection,ScrollBarThickness=5})
	local stack=Factory.New("Frame",{Parent=scroll}); Factory.List(stack,Enum.FillDirection.Vertical,8)
	local rows={}
	for index=1,2 do
		local row=Factory.New("TextButton",{Name="LiveRow"..index,LayoutOrder=index,Parent=stack}); rows[index]=row
		row.Activated:Connect(function() clicked+=1 end)
		Factory.New("ImageLabel",{Name="LiveThumb",Image="rbxthumb://actual-item-"..index,Parent=row})
		label(row,"ItemTitle","Old title",100,12); label(row,"ItemState","Actual ready state",100,45)
	end
	local inspector=Factory.ImageCard(app.content,UDim2.fromOffset(600,500),nil,"Inspector")
	local preview=Factory.New("Frame",{Parent=inspector})
	label(preview,"SelectedItemHeading","Original selected title")
	local viewport=Factory.New("ViewportFrame",{Name="ActualSelectedModel",Parent=preview})
	button(viewport,"ResetCamera","↺")
	local bodyScroll=Factory.New("ScrollingFrame",{Parent=inspector,ScrollBarThickness=4})
	local body=Factory.New("Frame",{Parent=bodyScroll})
	local readiness=Factory.New("Frame",{Name="Readiness",Parent=body})
	label(readiness,"ActualReadiness","Ready to wear",16,12)
	label(readiness,"ActualReadinessHelp","This is your actual readiness explanation",16,42)
	button(body,"Equip","Equip in game",50); button(body,"Publish","Publish to Roblox",100)
	button(body,"Advanced","Advanced Mode options",150)
	return app,rows,viewport
end
local studio,rows,viewport=makeStudio(false)
local countBefore=clicked
check(Layouts.Apply(studio),"My Items uses the new measured screen")
equal(viewport.Parent.Position.X.Offset,2,"The selected preview remains in its native container")
equal(find(studio.content,"ActualSelectedModel"),viewport,"The live selected model instance survives")
equal(find(rows[2],"LiveThumb").Image,"rbxthumb://actual-item-2","Sample design artwork never replaces real collection thumbnails")
equal(find(rows[2],"ItemTitle").Text,"Live crown title","Collection labels show actual selected-item data")
equal(find(studio.content,"V2ItemName").Text,"Live crown title","The rename field starts from the actual selected item")
equal(find(studio.content,"ActualReadiness").Text,"Ready to wear","Selected-item readiness stays live")
equal(find(studio.content,"ActualReadinessHelp").Text,"This is your actual readiness explanation","Readiness help survives relocation")
equal(find(studio.content,"ActualReadinessHelp").Parent,viewport,"Readiness details remain visible beside the live selected model")
local selectedHeading=find(studio.content,"SelectedItemHeading")
local readiness=find(studio.content,"Readiness")
check(selectedHeading.Position.X.Offset+selectedHeading.Size.X.Offset+selectedHeading.Parent.Position.X.Offset <= readiness.Position.X.Offset,
	"Long live item titles remain clear of the readiness badge")
rows[2].Activated:Fire(); find(studio.content,"Equip").Activated:Fire(); find(studio.content,"Publish").Activated:Fire(); find(studio.content,"Advanced").Activated:Fire(); find(studio.content,"ResetCamera").Activated:Fire()
equal(clicked,countBefore+5,"Collection, equip, publish, advanced, and reset callbacks remain functional")
local createNew
local save
for _,node in studio.content:GetDescendants() do
	if node:IsA("TextButton") and node.Text=="Create new" then createNew=node end
	if node:IsA("TextButton") and node.Text=="Save name" then save=node end
end
createNew.Activated:Fire(); equal(studio.opened,"Create","Create new opens the existing creation route")
find(studio.content,"V2ItemName").Text="My renamed crown"
save.Activated:Fire(); runSpawn()
equal(studio.invoked,"SetItemDetails","Save name uses the existing server action")
equal(studio.payload.itemId,"itemB","Rename sends the actual selected item ID")
equal(studio.payload.title,"My renamed crown","Rename sends editable native field text")
check(save.Active,"A failed server rename restores the action")
local personal=makeStudio(true)
check(Layouts.Apply(personal),"Personal copies retain their new presentation")
check(not find(personal.content,"V2ItemName").TextEditable,"Personal-copy licensing still blocks edits")
for _,node in personal.content:GetDescendants() do
	if node:IsA("TextButton") and node.Text=="Personal copy" then check(not node.Active,"Personal-copy save is disabled") end
end

local market=appFor("Discover")
local tools=Factory.New("Frame",{Parent=market.content})
local searchField=Factory.New("TextBox",{Text="A user search",Parent=tools})
button(tools,"Search","Search")
local grid=Factory.New("ScrollingFrame",{Name="RealCommunityResults",ScrollBarThickness=4,Parent=market.content})
local layout=Factory.New("UIGridLayout",{Parent=grid})
local result=Factory.ImageCard(grid,UDim2.fromOffset(248,344),nil,"CommunityItem")
local thumb=Factory.New("ImageLabel",{Image="rbxthumb://real-creator-item",Parent=result})
local title=label(result,"Title","An actual creator's item",16,194)
button(result,"TryOn","Try on",250)
button(result,"Like","♥ 17",298)
local favorite=button(result,"Favorite","Saved ★",298); favorite.Position=UDim2.new(.5,2,0,298)
local previous=clicked
check(Layouts.Apply(market),"Allowed community results use the new Market screen")
equal(searchField.Text,"A user search","The native search query survives")
equal(thumb.Image,"rbxthumb://real-creator-item","The live community thumbnail survives")
equal(title.Text,"An actual creator's item","Actual creator labels survive")
equal(favorite.Text,"Saved ★","Favorite state remains native instead of using sample artwork")
find(market.content,"Search").Activated:Fire(); find(result,"TryOn").Activated:Fire(); find(result,"Like").Activated:Fire(); favorite.Activated:Fire()
equal(clicked,previous+4,"Search, try-on, like, and favorite keep original callbacks")
equal(grid.ScrollBarThickness,4,"Result overflow stays reachable")
layout.CellSize=UDim2.new(.5,-12,0,200)
equal(layout.CellSize.X.Scale,1/3,"The measured three-column grid survives responsive callbacks")
market.state.policy.contentSharingAllowed=false
local fieldParent=searchField.Parent
check(not Layouts.Apply(market),"Restricted content-sharing policy retains its native explanation")
equal(searchField.Parent,fieldParent,"Policy fallback does not mutate controls")

local pending=Factory.New("Frame",{BackgroundTransparency=.7,ZIndex=3})
Factory.Stroke(pending,fixtures.Theme.Colors.Cyan,.12)
local native=Factory.New("ViewportFrame",{Parent=pending,ZIndex=1})
check(Skin.Skin(pending,"my-items","MyItemsPreviewPanel"),"Text-free panel art can surround a native viewport")
local art=pending:FindFirstChild("RedesignArt")
equal(pending.BackgroundTransparency,.7,"Pending images retain their native authored fill")
check(native.ZIndex>art.ZIndex,"Live viewport pixels stay above pending artwork")
art.IsLoaded=true; equal(pending.BackgroundTransparency,1,"Loaded artwork replaces only its native background")
art.IsLoaded=false; equal(pending.BackgroundTransparency,.7,"Unavailable artwork restores the original fill")
local count=#pending:GetChildren()
Skin.Skin(pending,"my-items","MyItemsPreviewPanel")
equal(#pending:GetChildren(),count,"Repeated skinning does not duplicate artwork")
local caption=Factory.ImageButton(pending,"Live caption",UDim2.fromOffset(200,50))
Skin.Skin(caption,"market","MarketTryCrownSurface")
Skin.Skin(caption,"market","MarketFavoriteCrownSurface")
local replacement=caption:FindFirstChild("RedesignArt")
check(caption:FindFirstChild("Label").ZIndex>replacement.ZIndex,"Replacing a skin keeps its native caption above new artwork")
fixtures.Theme.IsHighContrast=true
check(not Skin.Skin(Factory.New("Frame"),"market","MarketCardCrown"),"High contrast retains readable native surfaces")
fixtures.Theme.IsHighContrast=false
for _,class in {"TextBox","ImageLabel","ViewportFrame"} do
	local live=Factory.New(class)
	check(not Skin.Skin(live,"my-items","MyItemsPreviewPanel"),"Artwork never covers a live "..class)
end
return checks
