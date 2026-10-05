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
fixtures.RedesignAssets = setmetatable({}, { __index = function() return 100 end })
fixtures.RedesignMetrics = { screens = {} }
cache.RedesignAssets, cache.RedesignMetrics = nil, nil
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
equal(tabs.Parent, catalogApp.content, "Native tab actions remain outside the catalog scroller")

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
check(achievementGrid:IsDescendantOf(find(achievements, "EveryAchievement")), "Every actual milestone remains reachable")
inviteButton.Activated:Fire(); equal(invited, 1, "Invite retains native Roblox prompt callback")
equal(groupButton.Active, false, "Membership keeps group action disabled")
check(find(settingsApp.content, "GroupBenefits"):IsDescendantOf(find(settingsApp.content, "CommunityBenefits")), "Full group benefit explanation remains reachable")
check(not settingsPage.Visible and mode.Parent == settingsApp.content, "Only emptied original settings wrapper is hidden")

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

return checks
