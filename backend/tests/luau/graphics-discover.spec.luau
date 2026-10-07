-- Exercise App's actual public graphic renderer before applying its skin.
-- Data and callback assertions use doubles; no shared-content writes occur.
fixtures.RedesignAssets = setmetatable({}, { __index = function() return 100 end })
fixtures.RedesignMetrics = { screens = {} }
local Factory = require("Factory")
local Layouts = require("ModernPageLayouts")
local NativeDiscover = require("NativeGraphicsDiscoverRenderer")
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function count(root, name)
	local n = 0
	for _, node in root:GetDescendants() do if node.Name == name then n += 1 end end
	return n
end
for _, compact in { false, true } do
for _, simple in { true, false } do
	local app = setmetatable({ content = Factory.New("Frame"), activePage = "Avatar Graphics", compact = compact,
		graphicsTab = "DISCOVER", graphicsMarketplaceSearchBy = "PROMPT", graphicsMarketplaceSortBy = "TRENDING",
		graphicsMarketplaceQuery = "Actual query", gridColumns = 3,
		state = { profile = { settings = { simpleMode = simple } }, policy = { contentSharingAllowed = true } },
		graphicsMarketplaceItems = { { id = "actual-graphic", previewAssetId = 12345, title = "Actual shared artwork",
			ownerName = "ActualCreator", ownerUserId = 3, likes = 42, favorites = 7, viewerLiked = false,
			viewerFavorited = false, isListed = true, listingPriceRobux = 173 } },
		sounds = { Bind = function() end, Play = function() end },
	}, { __index = NativeDiscover })
	app.content.Size = UDim2.fromOffset(640, if compact then 224 else 645)
	if compact then
		app.gridColumns = 2
		for index = 2, 5 do
			local graphic = table.clone(app.graphicsMarketplaceItems[1]); graphic.id = "actual-graphic-" .. tostring(index)
			table.insert(app.graphicsMarketplaceItems, graphic)
		end
	end
	function app:_TextBox(parent, placeholder, size, position)
		return Factory.New("TextBox", { Parent = parent, PlaceholderText = placeholder, Size = size, Position = position })
	end
	function app:_GlowField() end
	function app:_BindButton() end
	function app:_TrackScroll() end
	function app:_RefreshGraphicsMarketplace(query) self.refreshedQuery = query end
	function app:_ShowContentDetail(value) self.openedDetail = value end
	function app:_Invoke(action, value) self.lastAction, self.lastActionValue = action, value; return true end
	Factory.Label(app.content, "Avatar Graphics", UDim2.fromOffset(600, 48)).Name = "PageTitle"
	Factory.Label(app.content, "Original subtitle", UDim2.fromOffset(600, 32)).Name = "PageSubtitle"
	local tabs = Factory.New("Frame", { Parent = app.content })
	Factory.List(tabs, Enum.FillDirection.Horizontal, 8)
	Factory.ImageButton(tabs, "Create", UDim2.fromOffset(120, 34))
	Factory.ImageButton(tabs, "Discover", UDim2.fromOffset(120, 34))
	app:_RenderGraphicsDiscoverBody()
	Layouts.Apply(app)
	local card = app.content:FindFirstChild("CommunityGraphic", true)
	local preview
	for _, child in card:GetChildren() do
		if child:IsA("ImageLabel") and child.Image == "rbxassetid://12345" then preview = child end
	end
	check(preview and preview.ScaleType == Enum.ScaleType.Fit, "Actual public image keeps its source and full aspect ratio")
	if compact then
		local page = app.content:FindFirstChild("GraphicsDiscoverScroll")
		check(page and page.Size.Y.Scale == 1 and page.AutomaticCanvasSize == Enum.AutomaticSize.Y,
			"Short compact viewports retain one full-height outer scroller")
		local gallery = card.Parent
		check(gallery.Parent == page and gallery.Size.Y.Offset > 1000, "Every compact gallery row has reachable positive height")
		check(not gallery.ScrollingEnabled, "Compact gallery scroll belongs to the outer page")
		check(preview.ZIndex > card:FindFirstChild("RedesignArt").ZIndex, "Compact real artwork renders above its surface")
	else
		check(preview.ZIndex > card:FindFirstChild("V2DecorationGraphicsSourceThumbnailArt").ZIndex,
			"Real artwork stays in front of the decorative well")
	end
	check(card:FindFirstChild("GraphicsDiscoverTitle").Text == "Actual shared artwork", "Actual title remains intact")
	check(card:FindFirstChild("GraphicsDiscoverCreator").Text == "by @ActualCreator", "Real creator attribution stays intact")
	card:FindFirstChild("ExpandHit").Activated:Fire()
	check(app.openedDetail.id == "actual-graphic" and app.openedDetail.imageId == 12345,
		"Detail callback retains the actual graphic identity")
	local like, favorite = card:FindFirstChild("GraphicsDiscoverLike"), card:FindFirstChild("GraphicsDiscoverFavorite")
	like.Activated:Fire(); runSpawn()
	check(app.lastAction == "ToggleGraphicLike" and app.lastActionValue.graphicId == "actual-graphic",
		"Native like callback survives the layout")
	favorite.Activated:Fire(); runSpawn()
	check(app.lastAction == "ToggleGraphicFavorite", "Native favorite callback survives the layout")
	if not simple then
		check(card:FindFirstChild("GraphicsDiscoverPrice").Text == "R$ 173", "Advanced card preserves the current Robux price")
		check(card:FindFirstChild("GraphicsDiscoverBuy").Active, "Advanced purchase entry remains available")
	end
	Layouts.Apply(app)
	if compact then
		check(count(app.content, "GraphicsDiscoverScroll") == 1 and count(app.content, "CommunityGraphic") == 5,
			"Repeated compact layout preserves all native cards in one scroll")
	else
		check(count(card, "V2DecorationGraphicsSourceThumbnailArt") == 1 and count(card, "GraphicsDiscoverViewHint") == 1,
			"Repeated layout adds no duplicate decoration or captions")
	end
end
end
return checks
