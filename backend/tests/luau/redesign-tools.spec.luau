-- Imported art surrounds real data and callbacks; this fixture makes no
-- Roblox image, catalog, account, purchase or network calls.
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end
local function equal(actual, expected, message)
	check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function find(parent, name)
	local value = parent:FindFirstChild(name, true)
	assert(value, "Missing native node: " .. name)
	return value
end
local function count(parent, name)
	local total = 0
	for _, value in parent:GetDescendants() do if value.Name == name then total += 1 end end
	return total
end
local function separated(first, second, gap, message)
	local ax, ay = first.Position.X.Offset, first.Position.Y.Offset
	local bx, by = second.Position.X.Offset, second.Position.Y.Offset
	check(ax + first.Size.X.Offset + gap <= bx or bx + second.Size.X.Offset + gap <= ax
		or ay + first.Size.Y.Offset + gap <= by or by + second.Size.Y.Offset + gap <= ay, message)
end
local function iconLane(button, asset)
	local icon = find(button, "V2Decoration" .. asset)
	local label = find(button, "Label")
	check(icon.Position.X.Offset + icon.Size.X.Offset <= label.Position.X.Offset,
		asset .. " reserves a separate native caption lane")
	check(label.Position.X.Offset + label.Size.X.Offset <= button.Size.X.Offset,
		asset .. " keeps its native caption inside the button")
end
local function visibleAncestors(target, message)
	local current = target
	while current do
		if current:IsA("GuiObject") then check(current.Visible ~= false, message .. ": " .. current.Name) end
		current = current.Parent
	end
end
fixtures.RedesignAssets = setmetatable({}, { __index = function() return 100 end })
fixtures.RedesignMetrics = { screens = {} }
cache.RedesignAssets, cache.RedesignMetrics = nil, nil
services.ContentProvider = services.ContentProvider or { PreloadAsync = function() end }
fixtures.HomeScreen = { ShowTools = function(app) app.toolsShown = (app.toolsShown or 0) + 1 end }
cache.HomeScreen = nil
-- Model Roblox defaults absent from the minimal shared engine double.
local originalNew = Instance.new
Instance.new = function(class)
	local instance = originalNew(class)
	instance.ZIndex = 1
	instance.IsLoaded = false
	return instance
end
methods.CaptureFocus = function(self) self.focusCaptured = true end
local Factory = require("Factory")
local Tools = require("RedesignToolsLayouts")
local function node(parent, class, name, x, y, w, h)
	return Factory.New(class, { Name = name, Parent = parent,
		Position = UDim2.fromOffset(x or 0, y or 0), Size = UDim2.fromOffset(w or 0, h or 0),
	})
end
local function text(parent, name, value, x, y)
	local label = node(parent, "TextLabel", name, x, y, 300, 24)
	label.Text = value
	return label
end
local function action(parent, name, value, callback, x, y)
	local button = Factory.ImageButton(parent, value, UDim2.fromOffset(150, 42), UDim2.fromOffset(x or 0, y or 0))
	button.Name = name
	button.Activated:Connect(callback)
	return button
end
local function app(page)
	local instance = { content = node(nil, "Frame", "Content", 0, 0, 1672, 941), activePage = page,
		compact = false, pageConnections = {}, scrollPositions = {},
		state = { profile = { settings = { simpleMode = true }, graphicOrder = {}, equippedItemIds = {} } },
		_BindButton = function() end,
		_Toast = function(self, kind, message) self.lastToast = message end,
		_RenderActivePage = function(self) self.renderCount = (self.renderCount or 0) + 1 end,
		_OpenPage = function(self, name) self.lastOpenedPage = name end,
	}
	text(instance.content, "PageTitle", page, 0, 0)
	text(instance.content, "PageSubtitle", "Original description", 0, 50)
	return instance
end

local catalogApp = app("Avatar Lab")
catalogApp.catalogType = "Hat"
catalogApp.catalogWorkspace = { tab = "BROWSE" }
catalogApp.catalogResults = { { Id = 42 }, { Id = 84 }, { Id = 126 }, { Id = 168 } }
local workspace = node(catalogApp.content, "ScrollingFrame", "AvatarLabWorkspace")
local stack = node(workspace, "Frame", "Stack")
Factory.List(stack, Enum.FillDirection.Vertical, 12)
local tabs = node(stack, "ScrollingFrame", "CatalogTabs")
Factory.List(tabs, Enum.FillDirection.Horizontal, 8)
action(tabs, "Browse", "Find items", function() end)
action(tabs, "Look", "My avatar", function() catalogApp.catalogWorkspace.tab = "LOOK" end)
local searchRow = node(stack, "Frame", "CatalogSearchRow")
local query = node(searchRow, "TextBox", "RealQuery")
query.Text = "actual catalog query"
local searched = 0
local searchButton = action(searchRow, "SearchCatalog", "Search", function() searched += 1 end)
local categories = node(stack, "ScrollingFrame", "CatalogCategories")
Factory.List(categories, Enum.FillDirection.Horizontal, 8)
for index, name in { "Hair", "Hats", "Face", "Shirts", "Pants", "Jackets", "Back" } do
	action(categories, "Category" .. name, name, function() end).LayoutOrder = index
end
local filters = node(stack, "ScrollingFrame", "CatalogFilterRow")
local filterCount = 0
local filter = action(filters, "Filter", "More filters", function() filterCount += 1 end)
local grid = node(stack, "Frame", "CatalogItemsGrid")
node(grid, "UIGridLayout", "Grid").CellSize = UDim2.fromOffset(180, 326)
local tried = 0
local firstThumb = nil
for index = 1, 4 do
	local card = Factory.ImageCard(grid, UDim2.fromOffset(180, 326), nil, "StyleItem")
	card.LayoutOrder = index
	local image = node(card, "ImageLabel", "CatalogItemThumbnail")
	image.Image = "rbxthumb://type=Asset&id=" .. tostring(index * 42) .. "&w=420&h=420"
	if index == 1 then firstThumb = image end
	text(card, "CatalogItemTitle", "Actual catalog item " .. index)
	text(card, "CatalogItemPrice", "R$ 173 to own · free to try")
	action(card, "CatalogTryOn", "Try on · free", function() tried += 1 end)
	action(card, "CatalogBookmark", "Save", function() end)
	action(card, "CatalogBuy", "Buy / view in Roblox", function() end)
end
equal(Tools.Apply(catalogApp), true, "Simple catalog is imported")
equal(query.Text, "actual catalog query", "Search query survives imported geometry")
equal(query.BackgroundTransparency, 0, "Loading input artwork retains readable native field fill")
local searchArt = find(searchRow, "V2DecorationCatalogSearchFieldArt"):FindFirstChild("RedesignArt")
searchArt.IsLoaded = true
equal(query.BackgroundTransparency, 1, "Loaded input artwork replaces only native fill")
searchArt.IsLoaded = false
equal(query.BackgroundTransparency, 0, "Unloaded input artwork restores native fill")
searchButton.Activated:Fire(); equal(searched, 1, "Catalog search callback survives reparenting")
filter.Activated:Fire(); equal(filterCount, 1, "More filters remains active after joining category strip")
equal(filter.Parent, categories, "More filters stays beside categories")
equal(firstThumb.Image, "rbxthumb://type=Asset&id=42&w=420&h=420", "Real item thumbnail is never replaced by sample art")
find(grid, "CatalogTryOn").Activated:Fire(); equal(tried, 1, "Free try-on retains its existing callback")
equal(find(grid, "CatalogItemPrice").Text, "R$ 173 to own · free to try", "Ownership price stays live and separate from free try-on")
equal(grid:FindFirstChildOfClass("UIGridLayout").CellSize.Y.Offset, 404, "Catalog rows retain complete action area")
check(grid.AutomaticSize == Enum.AutomaticSize.Y, "Additional catalog results extend the scroll canvas")
equal(tabs.Parent, stack, "Native Browse/Look tabs stay in their workspace and preserve callbacks")
check(not tabs.Visible, "Normal catalog gives the measured body to catalog results")
find(catalogApp.content, "OpenAvatarGraphics").Activated:Fire()
equal(catalogApp.lastOpenedPage, "Avatar Graphics", "Cross-page secondary navigation opens Avatar Graphics")
separated(find(grid, "CatalogItemPrice"), find(grid, "CatalogBuy"), 4, "Price and Roblox purchase link have distinct readable rows")
separated(find(grid, "CatalogBuy"), find(grid, "CatalogTryOn"), 4, "Ownership link never reaches into free try-on button")
iconLane(find(grid, "CatalogTryOn"), "CatalogCard1TryOnIcon")
Tools.Apply(catalogApp)
check(filter.Size.X.Offset >= 140, "Repeated catalog layout keeps the full More filters action width")
equal(count(grid, "V2DecorationCatalogCard1TryOnIcon"), 2, "Repeated catalog layout adds one icon per actual card only")
equal(query.Text, "actual catalog query", "Repeated catalog layout preserves player input")

local preview = Factory.ImageCard(nil, UDim2.fromOffset(465, 516), nil, "AvatarPreviewPanel")
preview.Visible = true
catalogApp.avatarPreviewPanel = preview
catalogApp.avatarPreviewViewport = node(preview, "ViewportFrame", "PreviewViewport")
local resetCount = 0
action(catalogApp.avatarPreviewViewport, "ResetCamera", "↺", function() resetCount += 1 end)
text(preview, "PreviewTitle", "YOUR AVATAR")
text(preview, "PreviewWornHeading", "WORN NOW")
node(preview, "Frame", "Divider")
catalogApp.avatarPreviewList = node(preview, "ScrollingFrame", "TriedOnList")
Factory.List(catalogApp.avatarPreviewList, Enum.FillDirection.Vertical, 8)
catalogApp.avatarPreviewEmptyLabel = text(catalogApp.avatarPreviewList, "Empty", "Nothing equipped")
local worn = node(catalogApp.avatarPreviewList, "Frame", "TriedOnItemRow")
node(worn, "ImageLabel", "RealWornImage").Image = "rbxthumb://type=Asset&id=321&w=150&h=150"
text(worn, "WornName", "Player's real crown", 52, 6)
text(worn, "WornSource", "CATALOG", 52, 29)
local removed = 0
action(worn, "RemoveWorn", "Remove", function() removed += 1 end)
equal(Tools.ApplyPreview(catalogApp), true, "Live avatar uses the imported measured stage")
equal(Tools.ApplyPreview(catalogApp), true, "Repeated avatar syncing is safe")
equal(count(preview, "SaveNewLook"), 1, "Syncing never duplicates save-look control")
equal(count(preview, "V2DecorationWornItemsPanelArt"), 1, "Syncing never duplicates artwork")
find(preview, "PreviewWornHeading").Visible = false
catalogApp.avatarPreviewList.Visible = false
catalogApp.avatarPreviewList.CanvasPosition = Vector2.new(0, 300)
Tools.ApplyPreview(catalogApp)
check(find(preview, "PreviewWornHeading").Visible and catalogApp.avatarPreviewList.Visible,
	"Persistent preview restores native wearing heading and list visibility")
equal(find(preview, "PreviewWornHeading").Text, "Wearing (1)", "Preview wearing count comes from actual live rows")
equal(catalogApp.avatarPreviewList.CanvasPosition.Y, 0, "Short wearing list resets stale canvas offset from another screen")
check(catalogApp.avatarPreviewList.ZIndex > find(preview, "V2DecorationWornItemsPanelArt").ZIndex,
	"Live wearing list renders above pane artwork")
check(find(worn, "WornName").ZIndex > find(worn, "RedesignArt").ZIndex,
	"Actual worn-item caption renders above its row artwork")
iconLane(find(preview, "ResetCamera"), "ResetAvatarCameraIcon")
iconLane(find(preview, "SaveNewLook"), "SaveNewLookIcon")
check(find(preview, "PreviewTitle").TextSize >= 32, "Avatar stage retains the strong readable source heading")
local Theme = require("Theme")
Theme.IsHighContrast = true
Tools.ApplyPreview(catalogApp)
check(not find(preview, "V2DecorationSaveNewLookIcon").Visible, "High contrast hides decorative save icon while retaining the native button")
Theme.IsHighContrast = false
Tools.ApplyPreview(catalogApp)
check(find(preview, "V2DecorationSaveNewLookIcon").Visible, "Returning from high contrast restores existing approved icon")
equal(count(preview, "SaveNewLook"), 1, "Accessibility changes never duplicate the persistent action")
find(preview, "SaveNewLook").Visible = false
find(preview, "V2DecorationWornItemsPanelArt").Visible = false
find(preview, "AvatarDragHint").Visible = false
local marketBadge = text(preview, "V2FreeTryOn", "FREE TRY-ON")
find(preview, "ResetCamera").Text = "Market camera\nReset"
Tools.ApplyPreview(catalogApp)
check(find(preview, "SaveNewLook").Visible and find(preview, "AvatarDragHint").Visible,
	"Returning from Market restores Avatar Lab's persistent actions")
check(find(preview, "V2DecorationWornItemsPanelArt").Visible and not marketBadge.Visible,
	"Returning from Market restores lab decoration and hides market-only badge")
equal(find(preview, "ResetCamera").Text, "Reset camera", "Returning from Market restores reset caption")
find(preview, "ResetCamera").Activated:Fire(); equal(resetCount, 1, "Reset keeps live camera callback")
find(preview, "RemoveWorn").Activated:Fire(); equal(removed, 1, "Worn removal retains native callback")
find(preview, "SaveNewLook").Activated:Fire()
equal(catalogApp.catalogWorkspace.tab, "LOOK", "Save new look opens existing named outfit/save flow")
equal(catalogApp.renderCount, 1, "Opening save flow renders native page")

local graphicsApp = app("Avatar Graphics")
graphicsApp.graphicsTab, graphicsApp.graphicMode, graphicsApp.selectedAvatarView = "CREATE", "AVATAR", "BUST"
graphicsApp.state.profile.graphicOrder = { "actual-graphic" }
local page = node(graphicsApp.content, "ScrollingFrame", "AvatarGraphicsScroll")
local columns = node(page, "Frame", "Columns")
local composer = Factory.ImageCard(columns, UDim2.fromOffset(900, 460), nil, "GraphicComposer")
local gallery = Factory.ImageCard(columns, UDim2.fromOffset(500, 350), nil, "GraphicsGallery")
Factory.SectionBanner(gallery, "Your Graphics")
local nativeTabs = node(graphicsApp.content, "Frame", "Tabs")
action(nativeTabs, "CreateTab", "Create", function() end)
action(nativeTabs, "DiscoverTab", "Discover", function() end)
text(composer, "Source", "SOURCE")
local source = node(composer, "Frame", "SourceRow")
action(source, "MyAvatar", "From My Avatar", function() end)
action(source, "FromText", "Text Prompt", function() end)
local prompt = node(composer, "TextBox", "RealPrompt")
prompt.Text = "Player's actual art prompt"
local promptCounter = text(composer, "PromptCounter", "23 / 500", 700, 200)
local generated = 0
local generate = action(composer, "Generate", "Create · R$ 37", function() generated += 1 end)
action(composer, "Advanced", "Advanced Mode: style & quality ✦", function() end)
node(composer, "ImageLabel", "AvatarThumbnail").Image = "rbxthumb://type=AvatarBust&id=123&w=150&h=150"
local images = node(gallery, "Frame", "GalleryGrid")
node(images, "UIGridLayout", "Grid").CellSize = UDim2.fromOffset(200, 310)
local imageCard = Factory.ImageCard(images, UDim2.fromOffset(200, 310), nil, "GraphicItem")
imageCard.LayoutOrder = 1
local art = node(imageCard, "ImageLabel", "RealArt")
art.Image = "rbxassetid://987654"
text(imageCard, "GraphicTitle", "Actual generation", 10, 148)
text(imageCard, "GraphicKind", "Bust", 10, 178)
text(imageCard, "LinkDescription", "Full resolution", 10, 200)
local link = node(imageCard, "TextBox", "RealURL", 10, 213)
link.Text = "https://example.invalid/v1/graphics/actual-graphic/image"; link.TextEditable = true
local deleted = 0
local delete = action(imageCard, "DeleteGraphic", "Delete", function() deleted += 1 end)
equal(Tools.Apply(graphicsApp), true, "Simple graphic composer imports")
equal(prompt.Text, "Player's actual art prompt", "Art prompt remains live")
equal(generate.Text, "Create · R$ 37", "Cost never becomes the image's sample price")
generate.Activated:Fire(); equal(generated, 1, "Generation preserves original commerce callback")
equal(art.Image, "rbxassetid://987654", "Owned art preview stays real")
find(imageCard, "CopyGraphicLink").Activated:Fire()
check(link.Visible and link.focusCaptured, "Copy link focuses original selectable URL")
equal(link.SelectionStart, #link.Text + 1, "Copy link selects whole original URL")
equal(link.Text, "https://example.invalid/v1/graphics/actual-graphic/image", "Full-resolution URL stays real")
link.FocusLost:Fire(); check(not link.Visible, "Copy mode closes on focus loss")
delete.Activated:Fire(); equal(deleted, 1, "Gallery delete retains original callback")
check(find(gallery, "LiveGraphicsGallery").ScrollBarThickness > 0, "All owned graphics remain reachable by scrolling")
check(find(graphicsApp.content, "GraphicsIdleActivity") ~= nil, "Idle activity shows honest empty status")
separated(prompt, promptCounter, 0, "Graphic character count is outside the typed input")
separated(promptCounter, find(composer, "Advanced"), 2, "Graphic character count has room before advanced control")
local graphicCount = find(gallery, "GraphicCount")
check(graphicCount.Position.Y.Offset + graphicCount.Size.Y.Offset < find(gallery, "LiveGraphicsGallery").Position.Y.Offset,
	"Gallery count remains in its header and never covers owned poster artwork")
iconLane(find(imageCard, "CopyGraphicLink"), "GraphicGalleryCard1CopyLinkIcon")
iconLane(delete, "GraphicGalleryCard1DeleteIcon")
Tools.Apply(graphicsApp)
equal(count(imageCard, "CopyGraphicLink"), 1, "Repeated gallery layout never duplicates the link control")
equal(count(graphicsApp.content, "GraphicsIdleActivity"), 1, "Repeated graphic layout never layers duplicate idle panels")
equal(graphicCount.Position.Y.Offset, 20, "Generated header decoration is excluded from empty-message placement")
graphicsApp.state.profile.graphicOrder = { "actual-graphic", "second-actual-graphic" }
Tools.Apply(graphicsApp)
equal(graphicCount.Text, "2 items", "Reused header caption updates from real collection count")

local emptyGraphics = app("Avatar Graphics")
emptyGraphics.graphicMode = "TEXT"
node(emptyGraphics.content, "ScrollingFrame", "AvatarGraphicsScroll")
local emptyComposer = Factory.ImageCard(emptyGraphics.content, UDim2.fromOffset(900, 460), nil, "GraphicComposer")
local emptyGallery = Factory.ImageCard(emptyGraphics.content, UDim2.fromOffset(500, 350), nil, "GraphicsGallery")
Factory.SectionBanner(emptyGallery, "Your Graphics")
local realEmpty = text(emptyGallery, "ActualEmptyCollection", "No graphics saved yet.")
Tools.Apply(emptyGraphics); Tools.Apply(emptyGraphics)
equal(realEmpty.Text, "No graphics saved yet.", "Rich empty gallery preserves honest collection status")
equal(count(emptyGallery, "GraphicItem"), 0, "Empty gallery never adds fake generated posters")
equal(count(emptyGallery, "EmptyGalleryHelp"), 1, "Repeated empty layout keeps one readable instruction")
equal(find(emptyGallery, "GraphicCount").Text, "0 items", "Decorated empty gallery keeps the real zero count")

local settingsApp = app("Settings")
local settingsPage = node(settingsApp.content, "ScrollingFrame", "SettingsScroll")
local settingsStack = node(settingsPage, "Frame", "SettingsStack")
local mode = Factory.ImageCard(settingsStack, UDim2.fromOffset(760, 168), nil, "CreateMode")
Factory.SectionBanner(mode, "Create Mode")
text(mode, "CurrentMode", "Simple Mode", 16, 32)
text(mode, "Description", "Original editing mode help", 16, 60)
local simpleClicked, advancedClicked = 0, 0
local simpleButton = action(mode, "SimpleChoice", "Simple Mode · ON", function() simpleClicked += 1 end)
local advancedButton = action(mode, "AdvancedChoice", "Advanced Mode", function() advancedClicked += 1 end)
local access = Factory.ImageCard(settingsStack, UDim2.fromOffset(760, 276), nil, "Accessibility")
Factory.SectionBanner(access, "Accessibility")
text(access, "ReduceMotionLabel", "Reduce motion", 16, 36)
text(access, "MotionDescription", "Turns off animated effects", 16, 58)
text(access, "ContrastLabel", "High contrast", 16, 96)
text(access, "ContrastDescription", "Darker panels and brighter text", 16, 118)
text(access, "InterfaceLabel", "Interface size", 16, 156)
text(access, "ScaleValue", "115%", 16, 180)
local keyboard = text(access, "KeyboardHelp", "Tab and gamepad navigation help", 16, 208)
local reduced, contrasted = 0, 0
local reduceSwitch = Factory.Switch(access, true, UDim2.fromOffset(650, 46))
reduceSwitch.Activated:Connect(function() reduced += 1 end)
local contrastSwitch = Factory.Switch(access, false, UDim2.fromOffset(650, 106))
contrastSwitch.Activated:Connect(function() contrasted += 1 end)
local slider = node(access, "TextButton", "RealScaleSlider", 200, 162, 300, 16)
local fill = node(slider, "Frame", "LiveScaleFill")
fill.Size = UDim2.fromScale(.35, 1)
local knob = node(slider, "Frame", "LiveScaleKnob")
knob.Position = UDim2.fromScale(.35, .5)
local pointerChanges = 0
slider.InputBegan:Connect(function() pointerChanges += 1 end)
local audio = Factory.ImageCard(settingsStack, UDim2.fromOffset(760, 104), nil, "Audio")
Factory.SectionBanner(audio, "Audio")
text(audio, "AudioLabel", "Sound effects", 16, 38)
text(audio, "AudioDescription", "Taps, forge chimes and reward stings.", 16, 60)
local sounded = 0
local soundSwitch = Factory.Switch(audio, false, UDim2.fromOffset(650, 48))
soundSwitch.Activated:Connect(function() sounded += 1 end)
local loadout = Factory.ImageCard(settingsStack, UDim2.fromOffset(760, 200), nil, "Loadout")
Factory.SectionBanner(loadout, "Equipped Now · 1")
local equippedRow = node(loadout, "Frame", "OwnedEquippedRow")
local equippedThumb = node(equippedRow, "ImageLabel", "ActualEquippedThumbnail")
equippedThumb.Image = "rbxassetid://246810"
text(equippedRow, "EquippedName", "My real wing", 58, 8)
text(equippedRow, "EquippedType", "BackAccessory", 58, 30)
local unequipped = 0
local unequip = action(equippedRow, "Unequip", "Remove", function() unequipped += 1 end)
local achievements = Factory.ImageCard(settingsStack, UDim2.fromOffset(760, 700), nil, "Achievements")
Factory.SectionBanner(achievements, "Achievements · 1/14")
local achievementGrid = node(achievements, "Frame", "ActualAchievements")
node(achievementGrid, "UIGridLayout", "Grid").CellSize = UDim2.fromOffset(160, 138)
for index = 1, 14 do
	local tile = node(achievementGrid, "Frame", "AchievementTile")
	tile.LayoutOrder = index
	local badge = node(tile, "Frame", "RealBadge")
	text(badge, "Glyph", if index == 1 then "✦" else "🔒")
	text(tile, "ActualMilestone", "Milestone " .. index, 0, 60)
	text(tile, "ActualRequirement", "Actual requirement and reward", 3, 78)
end
local invite = Factory.ImageCard(settingsStack, UDim2.fromOffset(760, 104), nil, "InviteFriends")
Factory.SectionBanner(invite, "Grow the Studio")
text(invite, "InviteHelp", "Real one-time invite benefit", 16, 38)
local invited = 0
local inviteButton = action(invite, "Invite", "Invite a friend", function() invited += 1 end)
local group = Factory.ImageCard(settingsStack, UDim2.fromOffset(760, 124), nil, "CreatorGroup")
Factory.SectionBanner(group, "Real Creator Group")
text(group, "MembershipStatus", "Member benefits active ✓", 16, 34)
text(group, "GroupBenefits", "Actual speed and queue slot benefits", 16, 64)
local groupButton = action(group, "GroupJoin", "Joined ✓", function() error("Member button should remain inactive") end)
groupButton.Active = false
equal(Tools.Apply(settingsApp), true, "Settings imports all six measured cards")
simpleButton.Activated:Fire(); advancedButton.Activated:Fire()
equal(simpleClicked, 1, "Simple Mode retains original update-setting callback")
equal(advancedClicked, 1, "Advanced Mode retains original update-setting callback")
reduceSwitch.Activated:Fire(); contrastSwitch.Activated:Fire(); soundSwitch.Activated:Fire()
equal(reduced, 1, "Reduce-motion callback survives import")
equal(contrasted, 1, "High-contrast callback survives import")
equal(sounded, 1, "Sound callback survives import")
equal(contrastSwitch:FindFirstChild("Knob").Position.X.Offset, 4, "Imported layout never bakes ON art over an OFF switch")
equal(fill.Size.X.Scale, .35, "Slider keeps live fill value")
equal(knob.Position.X.Scale, .35, "Slider keeps live knob value")
slider.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Unknown })
equal(pointerChanges, 1, "Slider pointer callback survives reparenting")
check(keyboard:IsDescendantOf(find(access, "AccessibilityControls")), "Complete keyboard help remains inside reachable scroller")
equal(equippedThumb.Image, "rbxassetid://246810", "Equipped thumbnail remains owned content")
unequip.Activated:Fire(); equal(unequipped, 1, "Unequip retains native server-action callback")
equal(count(achievementGrid, "AchievementTile"), 14, "Full actual achievement set is preserved")
local firstBadge = find(achievementGrid, "RealBadge")
check(not find(firstBadge, "Glyph").Visible and firstBadge:FindFirstChild("V2DecorationSettingsFirstSparkArt") ~= nil,
	"Genuinely earned achievement uses approved artwork instead of a missing glyph")
local lockedBadge = achievementGrid:GetChildren()[3]:FindFirstChild("RealBadge")
check(lockedBadge and find(lockedBadge, "Glyph").Visible and not lockedBadge:FindFirstChild("V2DecorationSettingsFirstSparkArt"),
	"Locked achievement remains locked and receives no earned artwork")
check(achievementGrid:IsDescendantOf(find(achievements, "EveryAchievement")), "Every actual milestone remains reachable")
inviteButton.Activated:Fire(); equal(invited, 1, "Invite retains native Roblox prompt callback")
equal(groupButton.Active, false, "Membership keeps group action disabled")
check(find(settingsApp.content, "GroupBenefits"):IsDescendantOf(find(settingsApp.content, "CommunityBenefits")), "Full group benefit explanation remains reachable")
check(not settingsPage.Visible and mode.Parent == settingsApp.content, "Only emptied original settings wrapper is hidden")
separated(simpleButton, advancedButton, 12, "Creation-mode controls keep clear space between their artwork")
iconLane(simpleButton, "SimpleModeCube")
iconLane(advancedButton, "AdvancedModeGear")
iconLane(unequip, "RemoveTrashIcon")
Tools.Apply(settingsApp)
equal(count(settingsApp.content, "CommunityActions"), 1, "Repeated Settings application never layers duplicate community panels")
equal(count(equippedRow.Parent, "UIListLayout"), 1, "Repeated Settings layout keeps one equipped-item layout")
equal(contrastSwitch:FindFirstChild("Knob").Position.X.Offset, 4, "Repeated Settings polish preserves the actual OFF switch state")

local advanced = app("Avatar Lab")
advanced.state.profile.settings.simpleMode = false
local originalPage = node(advanced.content, "ScrollingFrame", "AvatarLabWorkspace", 3, 4, 10, 20)
equal(Tools.Apply(advanced), false, "Advanced catalog keeps complete native fallback")
equal(originalPage.Position.X.Offset, 3, "Fallback returns before changing geometry")
graphicsApp.graphicsTab = "DISCOVER"
equal(Tools.Apply(graphicsApp), false, "Public graphics discovery keeps complete native commerce flow")
catalogApp.compact = true
equal(Tools.Apply(catalogApp), false, "Compact tools retain responsive layout")
equal(Tools.ApplyPreview(catalogApp), false, "Compact tools never force desktop avatar stage")

local compactSettings = app("Settings")
compactSettings.compact = true
local compactPage = node(compactSettings.content, "ScrollingFrame", "SettingsScroll")
local compactStack = node(compactPage, "Frame", "OriginalSettingsStack")
Factory.List(compactStack, Enum.FillDirection.Vertical, 22)
local compactMode = Factory.ImageCard(compactStack, UDim2.new(1, 0, 0, 168), nil, "CreateMode")
Factory.SectionBanner(compactMode, "Create Mode")
text(compactMode, "Current", "Simple Mode", 16, 32)
text(compactMode, "Help", "Full original mode help", 16, 60)
local changedMode = 0
local compactSimple = action(compactMode, "Simple", "Simple ✓", function() end)
local compactAdvanced = action(compactMode, "Advanced", "Advanced", function() changedMode += 1 end)
local compactAccess = Factory.ImageCard(compactStack, UDim2.new(1, 0, 0, 292), nil, "Accessibility")
Factory.SectionBanner(compactAccess, "Accessibility")
local motionTitle = text(compactAccess, "MotionTitle", "Reduce motion", 16, 36)
local motionHelp = text(compactAccess, "MotionHelp", "Turns off pulses, drifting embers and sweeps.", 16, 58)
local contrastTitle = text(compactAccess, "ContrastTitle", "High contrast", 16, 96)
text(compactAccess, "ContrastHelp", "Darker panels, brighter text and borders.", 16, 118)
text(compactAccess, "ScaleTitle", "Interface size", 16, 156)
text(compactAccess, "ScaleReadout", "105%", 16, 180)
local compactKeyboard = text(compactAccess, "KeyboardHelp", "Complete keyboard and gamepad instructions stay readable.", 16, 208)
local compactMotion = Factory.Switch(compactAccess, true, UDim2.fromOffset(400, 46))
local compactContrast = Factory.Switch(compactAccess, false, UDim2.fromOffset(400, 106))
local compactScale = node(compactAccess, "TextButton", "ActualScaleSlider", 200, 162, 300, 16)
compactScale.Text = ""
local compactFill = node(compactScale, "Frame", "Fill"); compactFill.Size = UDim2.fromScale(.42, 1)
local compactKnob = node(compactScale, "Frame", "Knob"); compactKnob.Position = UDim2.fromScale(.42, .5)
local compactSound = Factory.ImageCard(compactStack, UDim2.new(1, 0, 0, 104), nil, "Audio")
Factory.SectionBanner(compactSound, "Audio")
text(compactSound, "SoundTitle", "Sound effects", 16, 38)
text(compactSound, "SoundHelp", "Actual sound description", 16, 60)
Factory.Switch(compactSound, false, UDim2.fromOffset(400, 48))
fixtures.RedesignMetrics.screens.settings = { CreationModePanelArt = {
	assetKey = "V2_Settings_CreationModePanelArt", rect = { x = 0, y = 0, w = 769, h = 208 },
	sourceRect = { x = 0, y = 0, w = 769, h = 208 },
} }
equal(Tools.Compact(compactSettings), true, "Compact Settings receives approved styling")
equal(compactMode.Parent, compactStack, "Compact styling keeps original single-column scrolling flow")
equal(compactStack:FindFirstChildOfClass("UIListLayout").FillDirection, Enum.FillDirection.Vertical,
	"Compact styling never changes scrolling stack into desktop columns")
equal(find(compactMode, "RedesignArt").ScaleType, Enum.ScaleType.Slice, "Compact panel corners are sliced instead of stretched with long scroll cards")
equal(find(compactMode, "RedesignArt").SliceScale, .5, "Compact sliced borders account for approved 2x image exports")
equal(compactSimple.Size.Y.Offset, 48, "Compact creation modes retain comfortable touch targets")
check(compactMode.Size.Y.Offset <= 168 and compactSimple.Position.Y.Offset + compactSimple.Size.Y.Offset <= 160,
	"Compact mode card fits its first-screen controls without obsolete headroom")
check(find(compactMode, "Help").TextSize >= 16 and find(compactMode, "Help"):GetAttribute("ForgeSized"),
	"Compact descriptions keep explicit readable font sizes")
check(motionHelp.Position.Y.Offset >= compactMotion.Position.Y.Offset + compactMotion.Size.Y.Offset,
	"Compact motion description sits below its switch without crossing the label")
check(contrastTitle.Position.Y.Offset >= motionHelp.Position.Y.Offset + motionHelp.Size.Y.Offset,
	"Compact switch rows have independent text regions")
equal(find(compactAccess, "ScaleReadout").Text, "105%", "Compact Settings retains real interface-scale readout")
equal(compactFill.Size.X.Scale, .42, "Compact styling retains actual slider fill value")
equal(compactKnob.Position.X.Scale, .42, "Compact styling retains actual slider knob value")
check(compactKeyboard.Size.Y.Offset >= 100, "Full keyboard help has readable wrapping space")
compactAdvanced.Activated:Fire(); equal(changedMode, 1, "Compact mode styling retains original setting callback")
Tools.Compact(compactSettings)
equal(count(compactMode, "V2DecorationSimpleModeCube"), 1, "Repeated compact styling does not duplicate approved icons")
equal(compactContrast:FindFirstChild("Knob").Position.X.Offset, 4, "Compact styling retains actual OFF state")

local compactGraphics = app("Avatar Graphics")
compactGraphics.compact, compactGraphics.graphicMode, compactGraphics.gridColumns = true, "TEXT", 2
compactGraphics.state.profile.graphicOrder = { "real-graphic" }
local compactGraphicsPage = node(compactGraphics.content, "ScrollingFrame", "AvatarGraphicsScroll")
local compactGraphicsStack = node(compactGraphicsPage, "Frame", "GraphicsStack")
Factory.List(compactGraphicsStack, Enum.FillDirection.Vertical, 14)
local compactComposer = Factory.ImageCard(compactGraphicsStack, UDim2.new(1, 0, 0, 460), nil, "GraphicComposer")
text(compactComposer, "Source", "SOURCE")
local compactSources = node(compactComposer, "Frame", "SourceChoices")
action(compactSources, "Avatar", "My avatar", function() end)
action(compactSources, "Text", "Text prompt", function() end)
text(compactComposer, "Describe", "DESCRIBE YOUR GRAPHIC")
local compactCounter = text(compactComposer, "Counter", "20 / 500")
local compactPrompt = node(compactComposer, "TextBox", "ActualPrompt")
compactPrompt.Text = "Actual player input"
local compactPurchased = 0
local compactGenerate = action(compactComposer, "Generate", "Create · R$ 37", function() compactPurchased += 1 end)
local compactAdvancedArt = action(compactComposer, "Advanced", "Advanced Mode: style & quality", function() end)
local compactGallery = Factory.ImageCard(compactGraphicsStack, UDim2.new(1, 0, 0, 360), nil, "GraphicsGallery")
Factory.SectionBanner(compactGallery, "Your Graphics")
local compactGalleryGrid = node(compactGallery, "Frame", "Grid")
node(compactGalleryGrid, "UIGridLayout", "GridLayout").CellSize = UDim2.fromOffset(200, 310)
local compactOwnedCard = Factory.ImageCard(compactGalleryGrid, UDim2.fromScale(1, 1), nil, "GraphicItem")
local compactOwnedImage = node(compactOwnedCard, "ImageLabel", "ActualGraphic"); compactOwnedImage.Image = "rbxassetid://987654"
text(compactOwnedCard, "RealTitle", "Actual saved graphic", 10, 148)
text(compactOwnedCard, "RealKind", "Text prompt", 10, 178)
text(compactOwnedCard, "LinkHint", "Full resolution", 10, 200)
local compactURL = node(compactOwnedCard, "TextBox", "ActualLink")
compactURL.Text = "https://example.invalid/actual-full-image"; compactURL.TextEditable = true
action(compactOwnedCard, "Delete", "Delete", function() end)
equal(Tools.Compact(compactGraphics), true, "Compact graphics receives approved responsive surfaces")
equal(compactComposer.Parent, compactGraphicsStack, "Compact graphics keeps complete original scrolling composer flow")
equal(compactGenerate.Text, "Create · R$ 37", "Compact graphics never bakes sample generation price")
equal(compactPrompt.Text, "Actual player input", "Compact graphics preserves typed prompt")
separated(compactPrompt, compactCounter, 6, "Compact graphics counter sits outside its input")
separated(compactCounter, compactAdvancedArt, 6, "Compact graphic counter has separate space from advanced options")
separated(compactAdvancedArt, compactGenerate, 8, "Compact graphics checkout never overlaps advanced options")
equal(compactOwnedImage.Image, "rbxassetid://987654", "Compact gallery preserves actual saved artwork")
find(compactOwnedCard, "CopyGraphicLink").Activated:Fire()
check(compactURL.Visible and compactURL.focusCaptured, "Compact Copy link selects the real original URL")
compactGenerate.Activated:Fire(); equal(compactPurchased, 1, "Compact checkout keeps original purchase callback")
Tools.Compact(compactGraphics)
equal(count(compactOwnedCard, "CopyGraphicLink"), 1, "Repeated compact graphics layout does not duplicate native link action")
Theme.IsHighContrast = true
Tools.Compact(compactGraphics)
equal(compactPrompt.BackgroundTransparency, 0, "Compact high contrast restores readable native input fill")
Theme.IsHighContrast = false
Tools.Compact(compactGraphics)
check(find(compactPrompt.Parent, "V2CompactFieldActualPrompt"):FindFirstChild("RedesignArt") ~= nil,
	"Returning from high contrast restores approved compact field surface")

local compactLab = app("Avatar Lab")
compactLab.compact, compactLab.gridColumns = true, 2
compactLab.catalogWorkspace = { tab = "BROWSE" }
local compactLabPage = node(compactLab.content, "ScrollingFrame", "AvatarLabWorkspace")
local compactLabStack = node(compactLabPage, "Frame", "CatalogStack")
Factory.List(compactLabStack, Enum.FillDirection.Vertical, 12)
local compactSearch = node(compactLabStack, "Frame", "CatalogSearchRow")
local compactQuery = node(compactSearch, "TextBox", "ActualCatalogSearch"); compactQuery.Text = "Real query"
action(compactSearch, "Search", "Search", function() end)
local compactCatalogGrid = node(compactLabStack, "Frame", "CatalogItemsGrid")
node(compactCatalogGrid, "UIGridLayout", "Grid").CellSize = UDim2.fromOffset(180, 326)
local compactCatalogCard = Factory.ImageCard(compactCatalogGrid, UDim2.fromScale(1, 1), nil, "StyleItem")
local compactCatalogImage = node(compactCatalogCard, "ImageLabel", "CatalogItemThumbnail")
compactCatalogImage.Image = "rbxthumb://type=Asset&id=42&w=420&h=420"
text(compactCatalogCard, "CatalogItemTitle", "Actual catalog crown")
text(compactCatalogCard, "CatalogItemPrice", "R$ 173 to own · free to try")
local compactTried = 0
local compactTry = action(compactCatalogCard, "CatalogTryOn", "Try on · free", function() compactTried += 1 end)
action(compactCatalogCard, "CatalogBookmark", "Save", function() end)
action(compactCatalogCard, "CatalogBuy", "Buy / view in Roblox", function() end)
equal(Tools.Compact(compactLab), true, "Compact catalog receives imported readable styling")
equal(compactQuery.Text, "Real query", "Compact catalog preserves actual search input")
equal(compactCatalogImage.Image, "rbxthumb://type=Asset&id=42&w=420&h=420", "Compact catalog never substitutes example thumbnails")
equal(find(compactCatalogCard, "CatalogItemPrice").Text, "R$ 173 to own · free to try", "Compact catalog keeps real ownership price separate from free preview")
compactTry.Activated:Fire(); equal(compactTried, 1, "Compact catalog keeps native free-try-on callback")
check(compactTry.Size.Y.Offset >= 44, "Compact catalog retains comfortable try-on hit target")

local compactLook = app("Avatar Lab")
compactLook.compact = true; compactLook.catalogWorkspace = { tab = "LOOK" }
local compactLookPage = node(compactLook.content, "ScrollingFrame", "AvatarLabWorkspace")
local compactLookStack = node(compactLookPage, "Frame", "LookStack")
Factory.List(compactLookStack, Enum.FillDirection.Vertical, 12)
local realViewport = node(compactLookStack, "ViewportFrame", "LookPreview", 0, 0, 700, 260)
realViewport.LayoutOrder = 1
local actualCamera = node(realViewport, "Camera", "ActualPlayerCamera")
realViewport.CurrentCamera = actualCamera
equal(Tools.Compact(compactLook), true, "Compact look preview receives approved stage styling")
equal(realViewport.CurrentCamera, actualCamera, "Compact preview keeps original live camera")
equal(actualCamera.Parent, realViewport, "Compact preview keeps original player viewport contents")
equal(realViewport.Parent.Parent, compactLookStack, "Compact preview remains inside the same native scrolling stack")
Tools.Compact(compactLook)
equal(count(compactLookPage, "V2CompactLookStage"), 1, "Repeated compact preview styling never duplicates its stage")

local guidedLab = app("Avatar Lab")
guidedLab.catalogWorkspace = { tab = "BROWSE" }
guidedLab.makeoverGuideRequested = true
guidedLab.state.makeoverState = { active = true, completed = false }
local guidedPage = node(guidedLab.content, "ScrollingFrame", "AvatarLabWorkspace")
local guidedStack = node(guidedPage, "Frame", "GuideStack")
Factory.List(guidedStack, Enum.FillDirection.Vertical, 12)
local guideCard = Factory.ImageCard(guidedStack, UDim2.new(1, 0, 0, 224), nil, "GuidedMakeoverCard")
local guideBody = text(guideCard, "GuideBody", "Real guided instructions remain here.", 16, 65)
guideBody.TextSize = 12
local starter = node(guidedStack, "ScrollingFrame", "StarterLooks")
Factory.List(starter, Enum.FillDirection.Horizontal, 12)
local starterCard = Factory.ImageCard(starter, UDim2.fromOffset(218, 230), nil, "StarterLook")
text(starterCard, "Title", "Actual starter look", 12, 10)
local realTagline = text(starterCard, "Tagline", "Live catalog pieces for a real style.", 12, 35); realTagline.TextSize = 10
local starterImage = node(starterCard, "ImageLabel", "ActualStarterThumbnail", 12, 76, 58, 58)
starterImage.Image = "rbxthumb://type=Asset&id=42&w=150&h=150"
local woreStarter = 0
local wearStarter = action(starterCard, "WearStarter", "Wear today's pick", function() woreStarter += 1 end, 12, 174)
equal(Tools.Apply(guidedLab), true, "Guided Avatar Lab retains imported layout")
local guidedNav = find(guidedLab.content, "AvatarLabSecondaryNavigation")
equal(guidedNav.Parent, guidedLab.content, "Secondary navigation belongs to page content rather than disposable chrome")
find(guidedNav, "OpenAvatarGraphics").Activated:Fire()
equal(guidedLab.lastOpenedPage, "Avatar Graphics", "Guided stage still offers direct Avatar Graphics navigation")
check(guideBody.TextSize >= 16 and realTagline.TextSize >= 16, "Guided and starter descriptions use readable native fonts")
check(realTagline.Position.Y.Offset + realTagline.Size.Y.Offset < starterImage.Position.Y.Offset,
	"Larger starter description has its own region above actual thumbnails")
equal(starterImage.Image, "rbxthumb://type=Asset&id=42&w=150&h=150", "Guide polish preserves real starter thumbnail")
wearStarter.Activated:Fire(); equal(woreStarter, 1, "Guide polish preserves actual starter-look callback")
local disposableHeader = node(guidedLab.content.Parent, "Frame", "TemporaryEditorHeader")
disposableHeader:Destroy()
equal(guidedNav.Parent, guidedLab.content, "Chrome rebuild cannot destroy page-owned secondary navigation")
find(guidedNav, "OpenLabTools").Activated:Fire()
equal(guidedLab.toolsShown, 1, "More tools invokes existing native tools menu")
check(guidedLab.catalogWorkspace.moreTabs and guidedLab.catalogWorkspace.guideDismissed,
	"More tools also reveals complete native Avatar Lab workspace tabs")
equal(guidedLab.state.makeoverState.active, true, "Revealing tools keeps actual makeover progress")
Tools.Apply(guidedLab)
equal(count(guidedLab.content, "AvatarLabSecondaryNavigation"), 1, "Repeated guide layout keeps one navigation row")


return checks
