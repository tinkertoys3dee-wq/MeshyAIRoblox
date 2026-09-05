local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end
local function equal(actual, expected, message)
	check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local Motion, Factory = require("Motion"), require("Factory")
equal(
	Factory.New("TextButton", { Selectable = false }).Selectable,
	false,
	"Motion preserves deliberately non-selectable controls"
)
local parent = Instance.new("Frame")
local button = Factory.Button(parent, "Try on", UDim2.fromOffset(120, 44))
local border = button:FindFirstChildOfClass("UIStroke")
local size, position = button.Size, button.Position
local childCount = #button:GetChildren()
Motion.Bind(button)
button.MouseEnter:Fire()
check(button:GetAttribute("ForgeMotionBound"), "All factory buttons receive interaction feedback")
equal(button:FindFirstChildOfClass("UIStroke"), border, "Interaction outline must not replace the authored border")
equal(#button:GetChildren(), childCount + 1, "Binding twice must not add duplicate visuals")
equal(button.Size, size, "Hover never enlarges a layout-owned button")
equal(button.Position, position, "Hover never moves a layout-owned button")
local mirrored = button:FindFirstChild("Label")
button.TextSize, button.TextWrapped = 10, false
button.Text = "Studio"
equal(mirrored.Text, "Studio", "Lifted labels track text")
equal(mirrored.TextSize, 10, "Lifted labels track responsive font size")
equal(mirrored.TextWrapped, false, "Lifted labels track wrapping")
local padding = Factory.Padding(button, 12, 4)
equal(mirrored.Position.X.Offset, 12, "Late padding insets lifted text")
padding.PaddingLeft = UDim.new(0, 42)
equal(mirrored.Position.X.Offset, 42, "Changing navigation icon gutter updates text")
equal(mirrored.Size.X.Offset, -54, "Text reserves both gutters")
equal(
	Factory.Label(parent, "Very long text", UDim2.fromOffset(30, 20)).TextTruncate,
	Enum.TextTruncate.AtEnd,
	"Fixed labels truncate safely"
)
equal(
	Factory.Label(parent, "Wrapped text", UDim2.fromOffset(30, 20), { Wrapped = true }).TextTruncate,
	Enum.TextTruncate.AtEnd,
	"Fixed wrapped text also stays bounded"
)
equal(
	Factory.Label(parent, "Notice", UDim2.fromOffset(30, 0), { Wrapped = true, AutomaticSize = Enum.AutomaticSize.Y }).TextTruncate,
	Enum.TextTruncate.None,
	"Auto-height notices retain full copy"
)
local before = tweenCount
Motion.Configure(function()
	return true
end)
Motion.Tween(button, 1, { TextSize = 18 })
equal(tweenCount, before, "Reduced motion skips TweenService")
equal(mirrored.TextSize, 18, "Reduced motion still applies final state")
for _, viewport in { Vector2.new(320, 568), Vector2.new(844, 390), Vector2.new(768, 1024), Vector2.new(1920, 1080) } do
	local modalSize = Vector2.new(560, 702)
	local scale = Motion.FitScale(modalSize, viewport, 1.4)
	check(modalSize.X * scale <= viewport.X - 24 + 0.01, "Modal fits width")
	check(modalSize.Y * scale <= viewport.Y - 24 + 0.01, "Modal fits height")
end
local overlay = Instance.new("Frame")
overlay.Parent = parent
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(560, 702)
panel.Parent = overlay
local fitted = Motion.FitPanel(panel)
overlay.AbsoluteSize = Vector2.new(844, 390)
check(fitted.Scale * 702 <= 366.01, "Modal refits when the device rotates")
local resizeSignal = overlay:GetPropertyChangedSignal("AbsoluteSize")
local oldScale = fitted.Scale
local completed = 0
Motion.Close(overlay, panel, function()
	completed += 1
end)
Motion.Close(overlay, panel, function()
	completed += 1
end)
equal(completed, 1, "Double-close completes once")
equal(overlay.Parent, nil, "Reduced-motion close destroys immediately")
overlay.AbsoluteSize = Vector2.new(100, 100)
equal(fitted.Scale, oldScale, "Resize listener disconnects when modal is destroyed")

local Notice = require("NotificationService")
local host = Instance.new("Frame")
host.Parent = parent
local notices = Notice.new(host, { Play = function() end })
for index = 1, 5 do
	notices:Show("info", "Message " .. index)
end
equal(#notices.entries, 3, "Notification stack stays bounded")
equal(notices.entries[1].key, "info:Message 3", "Oldest notification is retired")
notices:Show("info", "Message 5")
equal(#notices.entries, 3, "Duplicate messages reuse one notice")
local frame = notices.entries[3].frame
frame:FindFirstChild("Button").Activated:Fire()
equal(#notices.entries, 2, "Notifications are individually dismissible")
services.Workspace.CurrentCamera.ViewportSize = Vector2.new(844, 390)
notices:Show("error", "One actionable error")
equal(#notices.entries, 1, "Short landscape screens show one notice at a time")
table.clear(spawned)
table.clear(delayed)

local AvatarLab = require("AvatarLab")
local StudioTransition = require("StudioTransition")
local studio = setmetatable({
	shell = Instance.new("Frame"),
	uiScaleInstance = Instance.new("UIScale"),
	fittedUiScale = 1.2,
	launcher = {},
	runwayLauncher = {},
	arcadeLauncher = {},
	afkLauncher = {},
	sounds = { Play = function() end },
	state = { profile = { settings = { reduceMotion = false }, onboarding = { completed = false } } },
	_LayoutAvatarPreviewPanel = function() end,
}, { __index = StudioTransition })
Motion.Configure(function()
	return false
end)
studio:_SetStudioOpen(false)
studio:_SetStudioOpen(false)
equal(#delayed, 1, "Repeated close schedules just one completion")
table.remove(delayed, 1)()
equal(studio.shell.Visible, false, "Double-clicking close cannot strand a visible studio")
studio:_SetStudioOpen(true)
studio:_SetStudioOpen(false)
studio:_SetStudioOpen(true)
table.remove(delayed, 1)()
equal(studio.shell.Visible, true, "A stale close never hides a reopened studio")
equal(studio.uiScaleInstance.Scale, 1.2, "Reopening preserves the fitted accessibility scale")
local app = {
	activePage = "Avatar Lab",
	catalogAccess = true,
	catalogType = "Hat",
	catalogSortType = "Relevance",
	catalogCreatorName = "",
	catalogMinPrice = "",
	catalogMaxPrice = "",
	scrollPositions = {},
	notices = {},
	renders = 0,
	_RenderActivePage = function(self)
		self.renders += 1
	end,
	_Toast = function(self, tone, message)
		table.insert(self.notices, message)
	end,
	_Track = function() end,
}
local function pages(id)
	return {
		IsFinished = false,
		GetCurrentPage = function()
			return { { Id = id, Name = "Item" } }
		end,
		AdvanceToNextPageAsync = function(self)
			self.GetCurrentPage = function()
				return { { Id = id }, { Id = id + 1 } }
			end
		end,
	}
end
services.AvatarEditorService.SearchCatalogAsync = function(_, params)
	return pages(if params.SearchKeyword == "old" then 1 else 2)
end
AvatarLab.Search(app, "old")
AvatarLab.Search(app, "new")
runSpawn(2)
runSpawn(1)
equal(app.catalogResults[1].Id, 2, "Late search responses never replace a newer query")
equal(app.catalogResults[1].forgeCategory, "Hat", "Cards retain the category they were fetched under")
AvatarLab.LoadMore(app)
AvatarLab.LoadMore(app)
equal(#spawned, 1, "Repeated load-more clicks queue one page")
runSpawn()
equal(#app.catalogResults, 2, "Pagination deduplicates asset IDs")
local oldResults = app.catalogResults
app.catalogWorkspace.pages.AdvanceToNextPageAsync = function()
	error("network")
end
AvatarLab.LoadMore(app)
runSpawn()
equal(app.catalogResults, oldResults, "Pagination failure preserves visible results")
equal(app.catalogWorkspace.loadingMore, false, "Pagination failure allows retry")
AvatarLab.LoadMore(app)
AvatarLab.Search(app, "new")
runSpawn(2)
runSpawn(1)
equal(#app.catalogResults, 1, "Old pagination cannot append to a new search")
services.AvatarEditorService.SearchCatalogAsync = function()
	return {
		GetCurrentPage = function()
			error("page read failed")
		end,
	}
end
AvatarLab.Search(app, "broken")
runSpawn()
equal(app.catalogSearching, false, "Even GetCurrentPage failures clear loading state")
check(app.catalogError ~= nil, "Search failure produces a retryable explanation")
app.catalogAccess = false
AvatarLab.Search(app, "no consent")
equal(#spawned, 0, "No search or automatic consent prompt without access")
app.catalogAccess = true
app.catalogMinPrice = "100"
app.catalogMaxPrice = "50"
AvatarLab.Search(app, "bad budget")
equal(#spawned, 0, "Invalid price range is rejected locally")

local AvatarLook, CatalogService = require("AvatarLook"), require("CatalogService")
local description = Instance.new("HumanoidDescription")
description.Shirt = 100
description.HeadColor = Color3.new(0.1, 0.2, 0.3)
description:SetAccessories({ { AssetId = 200, AccessoryType = Enum.AccessoryType.Hat, IsLayered = false } })
local snapshot = AvatarLook.Capture(description)
equal(snapshot.accessories[1].AccessoryType, "Hat", "Snapshots store enum names, not Instances")
snapshot.properties.UntrustedProperty = 1000
local restored = AvatarLook.Description(snapshot)
equal(restored.Shirt, 100, "Snapshots restore classic clothes")
equal(restored.HeadColor.G, 0.2, "Snapshots preserve colors")
equal(restored:GetAccessories(true)[1].AssetId, 200, "Snapshots preserve accessories")
equal(restored.UntrustedProperty, nil, "Only allowlisted properties are restored")
local function cloneDescription(value)
	return AvatarLook.Description(AvatarLook.Capture(value))
end
local humanoid = { description = cloneDescription(description), fail = false, applies = 0, incrementalApplies = 0 }
function humanoid:GetAppliedDescription()
	return cloneDescription(self.description)
end
function humanoid:ApplyDescriptionAsync(value)
	self.incrementalApplies += 1
	if self.fail then
		error("Roblox apply failed")
	end
	self.description = cloneDescription(value)
	self.applies += 1
end
function humanoid:ApplyDescriptionResetAsync(value)
	if self.fail then
		error("Roblox apply failed")
	end
	self.description = cloneDescription(value)
	self.applies += 1
end
local character = {
	FindFirstChildOfClass = function(_, kind)
		return if kind == "Humanoid" then humanoid else nil
	end,
	GetChildren = function()
		return {}
	end,
}
local player = { Character = character, UserId = 7 }
local profile = { stats = {}, equippedItemIds = {}, outfits = {}, outfitOrder = {}, items = {} }
local profiles = { saves = true, serial = 0 }
function profiles:Get()
	return profile
end
function profiles:Mutate(_, callback)
	callback(profile)
	return true
end
function profiles:Save()
	return self.saves
end
function profiles:GenerateId()
	self.serial += 1
	return "outfit" .. self.serial
end
local analytics = { Custom = function() end }
local catalog = CatalogService.new(profiles, {}, analytics)
local assetTypes = { [101] = 11, [201] = 8, [301] = 67, [401] = 12, [501] = "8" }
local avatarAssetTypes = { [101] = "Shirt", [201] = "Hat", [301] = "JacketAccessory", [401] = "Pants" }
services.AvatarEditorService.GetItemDetailsAsync = function(_, id)
	if id == 501 then
		error("Avatar catalog temporarily throttled")
	end
	return { Id = id, ItemType = "Asset", AssetType = avatarAssetTypes[id] or "Hat", Name = "Catalog item " .. id }
end
services.MarketplaceService.GetProductInfoAsync = function(_, id)
	return { AssetTypeId = assetTypes[id] or 8, Name = "Catalog item " .. id }
end
check(not catalog:TryOn(player, { assetId = 1 / 0, avatarAssetType = "Hat" }), "Non-finite IDs are rejected")
check(not catalog:TryOn(player, { assetId = 101, avatarAssetType = "Hat" }), "Server checks actual asset type")
check(catalog:TryOn(player, { assetId = 101, avatarAssetType = "Shirt" }), "Classic shirt can be tried on")
equal(humanoid.description.Shirt, 101, "Classic shirt sets its description property")
equal(#humanoid.description:GetAccessories(true), 1, "Classic clothes are not appended as accessories")
local applies = humanoid.applies
check(catalog:TryOn(player, { assetId = 101, avatarAssetType = "Shirt" }), "Already worn try-on succeeds as no-op")
equal(humanoid.applies, applies, "Already worn item does not reapply avatar")
equal(profile.stats.catalogTryOns, 1, "No-op does not inflate try-on count")
check(catalog:TryOn(player, { assetId = 301, avatarAssetType = "JacketAccessory" }), "Layered jacket can be tried on")
equal(humanoid.description:GetAccessories(true)[2].IsLayered, true, "Layered category retains layering")
check(
	catalog:TryOn(player, { assetId = 501, avatarAssetType = "Hat" }),
	"Marketplace metadata fallback keeps try-on available"
)
check(catalog:History(player, false), "Undo succeeds")
equal(#humanoid.description:GetAccessories(true), 2, "Undo removes the most recent marketplace fallback item")
check(catalog:History(player, true), "Redo succeeds")
equal(#humanoid.description:GetAccessories(true), 3, "Redo restores the marketplace fallback item")
humanoid.fail = true
local historyCount = #catalog.history[player].undo
check(not catalog:History(player, false), "Failed avatar apply is reported")
equal(#catalog.history[player].undo, historyCount, "Failed undo retains the history entry")
humanoid.fail = false
check(catalog:Untry(player, { assetId = 101 }), "Classic shirt can be removed")
equal(humanoid.description.Shirt, 0, "Remove clears classic property")
check(catalog:History(player, false), "Removing clothes is undoable")
equal(humanoid.description.Shirt, 101, "Undo restores removed clothes")
check(catalog:TryOn(player, { assetId = 401, avatarAssetType = "Pants" }), "New edit after undo succeeds")
equal(#catalog.history[player].redo, 0, "New edit clears redo branch")
for index = 1, 25 do
	catalog:_Remember(player, AvatarLook.Capture(humanoid.description))
end
equal(#catalog.history[player].undo, 20, "History memory stays bounded")
local ok, worn = catalog:GetEquippedAccessories(player)
check(ok, "Worn list loads")
check(#worn.accessories >= 3, "Worn list includes classic clothes and accessories")
player.Character = { FindFirstChildOfClass = character.FindFirstChildOfClass }
check(not catalog:History(player, false), "Respawn invalidates old-character history")
player.Character = character
catalog:Remove(player)
equal(catalog.history[player], nil, "Leaving clears history")

local ItemService = require("ItemService")
local items = setmetatable({ profiles = profiles }, ItemService)
local saved, data = items:SaveOutfit(player, { name = "Catalog only" })
check(saved, "Catalog-only outfits save without owned Forge pieces")
equal(#data.outfit.itemIds, 0, "Catalog-only outfit does not grant Forge items")
equal(data.outfit.avatarLook.properties.Shirt, 101, "Outfit captures applied appearance on server")
local outfitId = data.outfit.id
humanoid.description.Shirt = 500
check(items:EquipOutfit(player, { outfitId = outfitId }), "Catalog-only outfit can be restored")
equal(humanoid.description.Shirt, 101, "Saved outfit restores classic clothes")
profiles.saves = false
local existing = #profile.outfitOrder
check(not items:SaveOutfit(player, { name = "Failure" }), "Save failure is not reported as success")
equal(#profile.outfitOrder, existing, "Failed save rolls back to avoid duplicate outfits on retry")
profiles.saves = true
profile.outfits.legacy = { itemIds = { "owned" }, name = "Legacy" }
profile.equippedItemIds = { "owned" }
humanoid.description.Shirt = 999
check(items:EquipOutfit(player, { outfitId = "legacy" }), "Legacy Forge-only outfits still work")
equal(humanoid.description.Shirt, 999, "Legacy outfit does not replace catalog appearance")
equal(humanoid.incrementalApplies, 0, "Catalog and outfit changes never use unsafe incremental avatar apply")

-- Construct each real Avatar Lab view using the UI doubles. This catches
-- missing client state/wiring; visual layout remains a Studio release gate.
services.Players.LocalPlayer = player
app.content = Instance.new("Frame")
app.uiScaleInstance = Instance.new("UIScale")
app.pageConnections = {}
app.state = { profile = profile, policy = { commerceAllowed = true } }
app.triedOnAssetIds, app.triedOnAssetInfo = {}, {}
app.avatarAccessoriesLoaded = true
app.catalogResults = { { Id = 201, Name = "Long catalog item name", Price = 50, forgeCategory = "Hat" } }
app.catalogQuery, app.catalogError, app.catalogMinPrice, app.catalogMaxPrice = "", nil, "", ""
app._PageHeader = function() end
app._TrackScroll = function() end
app._BindButton = function() end
app._WatchImageLoad = function() end
app._RefreshAvatarAccessories = function() end
app._TextBox = function(_, container, placeholder, size, position)
	return Factory.New("TextBox", { Size = size, Position = position, Parent = container })
end
local invoked = {}
app._Invoke = function(_, action, payload)
	table.insert(invoked, { action = action, payload = payload })
	return true, {}
end
for _, tab in { "BROWSE", "LOOK", "SAVED", "FORGE" } do
	app.catalogWorkspace.tab = tab
	AvatarLab.Render(app)
	check(#app.content:GetChildren() > 0, "Avatar Lab " .. tab .. " view constructs")
	for _, child in app.content:GetChildren() do
		child:Destroy()
	end
end
app.catalogWorkspace.tab = "BROWSE"
AvatarLab.Render(app)
local tryButton, saveButton
for _, control in app.content:GetDescendants() do
	if control:IsA("TextButton") then
		if control.Text == "Try on · free" then
			tryButton = control
		end
		if control.Text == "Save" then
			saveButton = control
		end
	end
end
check(tryButton ~= nil and saveButton ~= nil, "Catalog cards expose try and bookmark controls")
tryButton.Activated:Fire()
runSpawn()
equal(invoked[1].action, "TryCatalogAsset", "Try-on invokes only the catalog edit action")
equal(invoked[1].payload.avatarAssetType, "Hat", "Try-on uses the card's captured category")
saveButton.Activated:Fire()
equal(#invoked, 1, "Bookmarking neither purchases nor generates anything")
check(app.catalogWorkspace.favorites[201] ~= nil, "Bookmark is available in this visit")
app.compact = true
app.catalogWorkspace.previewIntroduced = nil
tryButton.Activated:Fire()
runSpawn()
equal(app.catalogWorkspace.tab, "LOOK", "First mobile try-on opens its visible result")
app.catalogWorkspace.tab = "BROWSE"
tryButton.Activated:Fire()
runSpawn()
equal(app.catalogWorkspace.tab, "BROWSE", "Subsequent try-ons do not keep changing tabs")
app.catalogWorkspace.previewIntroduced = nil
tryButton.Activated:Fire()
app.activePage = "Create"
runSpawn()
equal(app.catalogWorkspace.tab, "BROWSE", "Late try-on never hijacks navigation away from styling")
app.activePage = "Avatar Lab"
for _, child in app.content:GetChildren() do
	child:Destroy()
end
app.catalogAccess = false
AvatarLab.Render(app)
local enable, searchControls = nil, 0
for _, control in app.content:GetDescendants() do
	if control:IsA("TextButton") and control.Text == "Enable catalog · free" then
		enable = control
	end
	if control:IsA("TextBox") then
		searchControls += 1
	end
end
check(enable ~= nil, "First-use catalog access has a clear action")
equal(enable.Parent.LayoutOrder, 2, "Permission action appears directly after the heading")
equal(searchControls, 0, "Unusable search/filter controls are not placed before consent")

local WindowFocus = require("WindowFocus")
local focus = { gui = Instance.new("ScreenGui"), shell = { Visible = true }, studioOpen = true, activePage = "Create" }
check(WindowFocus.CanCelebrate(focus), "Unobstructed creator page can celebrate")
local toastHost = Factory.New("Frame", { Name = "Toasts", ZIndex = 500, Parent = focus.gui })
check(WindowFocus.CanCelebrate(focus), "Non-blocking notices do not count as windows")
local arcade = Factory.New("Frame", { Name = "ArcadeOverlay", ZIndex = 210, Parent = focus.gui })
check(not WindowFocus.CanCelebrate(focus), "Automatic completion cannot cover an active game")
arcade:Destroy()
focus.activePage = "Avatar Lab"
check(not WindowFocus.CanCelebrate(focus), "Automatic completion does not interrupt styling")
focus.activePage = "Create"
focus.shell.Visible = false
check(not WindowFocus.CanCelebrate(focus), "A closed editor is not reopened by a completion")
focus.shell.Visible = true
Factory.New("Frame", { Name = "CreationComplete", ZIndex = 300, Parent = focus.gui })
check(not WindowFocus.CanCelebrate(focus), "A second completion never covers the first")
return checks
