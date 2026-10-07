--!strict

-- SVG chrome around live, scrollable editor pages. No sample item/picture is
-- used as a player's content; native renderers keep their existing callbacks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Factory = require(script.Parent.Factory)
local HomeScreen = require(script.Parent.HomeScreen)
local HomeAssets = require(ReplicatedStorage:WaitForChild("HomeAssets"))
local HomeEffects = require(script.Parent.HomeEffects)
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local RedesignToolsLayouts = require(script.Parent.RedesignToolsLayouts)
local RedesignSkin = require(script.Parent.RedesignSkin)

local ModernChrome = {}
local SURFACES = { Discover = "Purple", ["Avatar Graphics"] = "Purple", Play = "Gold" }

local function layout(app: any)
	local root, canvas = app.editorRoot, app.editorCanvas
	if not root or not root.Parent then return end
	local scale = math.max(.01, app.uiScaleInstance.Scale)
	local width, height = root.AbsoluteSize.X / scale, root.AbsoluteSize.Y / scale
	if width <= 0 or height <= 0 then return end
	local mobile = app.compact == true
	local shade = root:FindFirstChild("CompactBackdropShade")
	if shade then shade.Visible = mobile and not Theme.IsHighContrast end
	if app.editorMobile ~= mobile or (mobile and math.abs((app.editorWidth or 0)-width) > 1) then
		app.editorMobile, app.editorWidth = mobile, width
		for _, child in app.editorHeader:GetChildren() do child:Destroy() end
		HomeScreen.Chrome(app, app.editorHeader, mobile, width)
	end
	if mobile then
		app.editorScale.Scale = 1
		canvas.AnchorPoint = Vector2.zero
		canvas.Position = UDim2.fromOffset(0, 0)
		canvas.Size = UDim2.fromScale(1, 1)
		if app.content.Parent == canvas then
			local headerHeight = if width >= 520 then 168 else 200
			app.content.Position = UDim2.fromOffset(0, headerHeight)
			app.content.Size = UDim2.new(1, 0, 1, -headerHeight - 12)
		end
	else
		canvas.AnchorPoint = Vector2.new(.5, .5)
		canvas.Position = UDim2.fromScale(.5, .5)
		canvas.Size = UDim2.fromOffset(1672, 941)
		app.editorScale.Scale = math.min(width/1672, height/941)
		if app.content.Parent == canvas then
			local hasPreview = app.activePage == "Avatar Lab" or app.activePage == "Discover"
			app.content.Position = if app.redesignLayoutActive then UDim2.new() else UDim2.fromOffset(46, 238)
			app.content.Size = if app.redesignLayoutActive then UDim2.fromOffset(1672, 941) else UDim2.fromOffset(if hasPreview then 1087 else 1586, 645)
		end
	end
end

local function ensure(app: any)
	if app.editorRoot and app.editorRoot.Parent then return end
	local root = Factory.New("Frame", { Name = "ForgeEditor", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Ink, BorderSizePixel = 0, Parent = app.shell })
	app.editorRoot = root
	if HomeAssets.Backdrop > 0 and not Theme.IsHighContrast then
		Factory.New("ImageLabel", { Name = "CityBackdrop", Image = "rbxassetid://" .. tostring(HomeAssets.Backdrop),
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop,
			ZIndex = 0, Parent = root })
	end
	Factory.New("Frame", { Name = "CompactBackdropShade", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Ink, BackgroundTransparency = 0.28, BorderSizePixel = 0,
		Active = false, Visible = false, ZIndex = 0, Parent = root })
	app.editorCanvas = Factory.New("Frame", { Name = "EditorCanvas", Size = UDim2.fromOffset(1672, 941),
		BackgroundTransparency = 1, BorderSizePixel = 0, Parent = root })
	app.editorScale = Factory.New("UIScale", { Scale = 1, Parent = app.editorCanvas })
	app.editorHeader = Factory.New("Frame", { Name = "EditorHeader", Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, BorderSizePixel = 0, Parent = app.editorCanvas })
	local connections = {
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() layout(app) end),
		app.uiScaleInstance:GetPropertyChangedSignal("Scale"):Connect(function() layout(app) end),
	}
	root.Destroying:Connect(function()
		for _, connection in connections do connection:Disconnect() end
	end)
	app.editorMobile = nil
end

function ModernChrome.Apply(app: any)
	local home = app.activePage == "Home"
	local topbar = app.shell:FindFirstChild("Topbar")
	if topbar then topbar.Visible = false end
	app.nav.Visible = false
	if app.backgroundLayer then app.backgroundLayer.Visible = false end
	local gradient = app.shell:FindFirstChildOfClass("UIGradient")
	if gradient then gradient.Enabled = false end
	local stroke = app.shell:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Transparency = 1 end
	app.shell.BackgroundTransparency = 1
	if home then
		if app.editorRoot then app.editorRoot.Visible = false end
		app.content.Parent = app.shell
		app.content.Position = UDim2.fromOffset(0, 0)
		app.content.Size = UDim2.fromScale(1, 1)
	else
		ensure(app)
		app.editorRoot.Visible = true
		app.content.Parent = app.editorCanvas
		app.content.ZIndex = 3
		app.content:SetAttribute("ForgeSurface", SURFACES[app.activePage] or "Blue")
		-- Rebuild during a page render, while retaining live tab controls that
		-- were moved into the header during ordinary desktop resizing.
		if app.editorPage ~= app.activePage or not app.homeNavButtons then
			app.editorMobile = nil
			app.editorPage = app.activePage
		end
		layout(app)
		task.defer(function() layout(app) end)
	end
end

function ModernChrome.LayoutPreview(app: any): boolean
	if not app.editorRoot then return false end
	local wanted = app.editorRoot.Visible and not app.compact and app.shell.Visible
		and app.studioOpen ~= false and (app.activePage == "Avatar Lab" or app.activePage == "Discover")
	local panel = app.avatarPreviewPanel
	if not panel then return false end
	-- The SVG includes this pane in the canvas; do not reserve a second external rail.
	local size = UDim2.new(.9, 0, .88, 0)
	if app.shell.Size ~= size then app.shell.Size = size end
	local position = UDim2.fromScale(.5, .5)
	if app.shell.Position ~= position then app.shell.Position = position end
	panel.Visible = wanted
	if not wanted then return true end
	panel.Parent = app.editorCanvas
	if app.redesignLayoutActive then
		if app.activePage == "Avatar Lab" then
			if RedesignToolsLayouts.ApplyPreview(app) then layout(app); return true end
		end
		if app.activePage == "Discover" then
			for _, name in { "SaveNewLook", "AvatarDragHint", "V2DecorationWornItemsPanelArt" } do
				local child = panel:FindFirstChild(name)
				if child then child.Visible = false end
			end
			RedesignSkin.Place(panel, 1139, 236, 484, 644)
			panel.ZIndex = 3
			RedesignSkin.Skin(panel, "market", "MarketAvatarPanel")
			local title = panel:FindFirstChild("PreviewTitle")
			if title then title.Text = "Your Avatar"; RedesignSkin.Place(title, 24, 10, 250, 53); RedesignSkin.Sized(title, 36) end
			if not panel:FindFirstChild("V2FreeTryOn") then
				local badge = Factory.ImagePill(panel, "Free Try-On", Theme.Colors.Mint, 170)
				badge.Name = "V2FreeTryOn"; RedesignSkin.Place(badge, 300, 13, 170, 49); RedesignSkin.Sized(badge, 21)
				RedesignSkin.Skin(badge, "market", "MarketFreeTryOnSurface")
			end
			panel.V2FreeTryOn.Visible = true
			local viewport = app.avatarPreviewViewport
			RedesignSkin.Place(viewport, 3, 68, 479, 407)
			viewport.BackgroundColor3 = Color3.fromRGB(5, 46, 85)
			local reset = panel:FindFirstChild("ResetCamera", true)
			if reset then
				reset.Parent = panel; reset.Text = "Reset\nCamera"; RedesignSkin.Place(reset, 381, 106, 94, 124)
				RedesignSkin.Sized(reset, 18); RedesignSkin.Skin(reset, "market", "MarketResetCameraSurface")
				local caption = Factory.LiftLabel(reset)
				if caption then RedesignSkin.Place(caption, 4, 55, 86, 61); caption.TextXAlignment = Enum.TextXAlignment.Center end
				RedesignSkin.Decoration(reset, "market", "MarketResetIconArtwork", 25, 14, 43, 43)
			end
			local divider = panel:FindFirstChild("Divider")
			if divider then divider.Visible = false end
			local worn = panel:FindFirstChild("PreviewWornHeading")
			if worn then RedesignSkin.Place(worn, 23, 482, 420, 39); RedesignSkin.Sized(worn, 27) end
			RedesignSkin.Place(app.avatarPreviewList, 18, 527, 450, 104)
			local list = app.avatarPreviewList:FindFirstChildOfClass("UIListLayout")
			if list then list.Padding = UDim.new(0, 8) end
			for _, row in app.avatarPreviewList:GetChildren() do
				if row.Name ~= "TriedOnItemRow" then continue end
				row.Size = UDim2.new(1, -10, 0, 101)
				RedesignSkin.Skin(row, "market", "MarketWearingItem")
				local image = row:FindFirstChildOfClass("ImageLabel")
				if image then RedesignSkin.Place(image, 9, 9, 95, 84) end
				for _, label in RedesignSkin.Direct(row, "TextLabel") do
					local isTitle = label.Position.Y.Offset < 25
					RedesignSkin.Place(label, 122, if isTitle then 17 else 53, 252, 32); RedesignSkin.Sized(label, if isTitle then 24 else 18)
				end
				local remove = row:FindFirstChildOfClass("TextButton")
				if remove then remove.Text = "×"; RedesignSkin.Place(remove, 373, 21, 63, 61); RedesignSkin.Sized(remove, 35); RedesignSkin.Skin(remove, "market", "MarketRemoveSurface") end
			end
			if worn then worn.Text = "Wearing (" .. tostring(#RedesignSkin.Direct(app.avatarPreviewList, "Frame")) .. ")" end
			app.avatarPreviewEmptyLabel.TextSize = 19
			layout(app)
			return true
		end
	end
	RedesignSkin.Reset(panel)
	for _, name in { "SaveNewLook", "AvatarDragHint", "V2DecorationWornItemsPanelArt", "V2FreeTryOn" } do
		local child = panel:FindFirstChild(name)
		if child then child.Visible = false end
	end
	panel.Position = UDim2.fromOffset(1142, 337)
	panel.Size = UDim2.fromOffset(465, 516)
	panel.ZIndex = 3
	panel.BackgroundColor3 = Theme.Colors.Panel
	local title = panel:FindFirstChild("PreviewTitle")
	if title then title.Position = UDim2.fromOffset(32, 21); title.Size = UDim2.new(1, -64, 0, 34); title.TextSize = 26 end
	local viewport = app.avatarPreviewViewport
	viewport.Position = UDim2.fromOffset(26, 95)
	viewport.Size = UDim2.new(1, -52, 0, 242)
	viewport.BackgroundColor3 = Theme.Colors.Ink
	local reset = panel:FindFirstChild("ResetCamera", true)
	if reset then RedesignSkin.Reset(reset); reset.Parent = viewport; reset.Text = "↺"; RedesignSkin.Place(reset, 379, 8, 32, 28); RedesignSkin.Sized(reset, 15) end
	local free = panel:FindFirstChild("V2FreeTryOn")
	if free then free.Visible = false end
	local divider = panel:FindFirstChild("Divider")
	if divider then divider.Position = UDim2.fromOffset(32, 392); divider.Size = UDim2.new(1, -64, 0, 1) end
	local worn = panel:FindFirstChild("PreviewWornHeading")
	if worn then worn.Position = UDim2.fromOffset(32, 355); worn.Size = UDim2.new(1, -64, 0, 32); worn.TextSize = 21 end
	app.avatarPreviewList.Position = UDim2.fromOffset(26, 405)
	app.avatarPreviewList.Size = UDim2.new(1, -52, 0, 96)
	app.avatarPreviewEmptyLabel.TextSize = 17
	layout(app)
	return true
end

function ModernChrome.Finish(app: any)
	if app.activePage == "Home" then return end
	for _, child in app.content:GetDescendants() do
		if not app.compact and (child:IsA("TextLabel") or child:IsA("TextBox") or child:IsA("TextButton"))
			and not child:GetAttribute("ForgeSized") then
			child.TextSize = math.min(32, math.floor(child.TextSize * 1.25 + .5))
			child:SetAttribute("ForgeSized", true)
			-- Lifted captions follow the native control's font through its signal.
			-- Mark them too so traversal does not enlarge the same caption twice.
			local caption = child:FindFirstChild("Label")
			if caption and caption:IsA("TextLabel") then caption:SetAttribute("ForgeSized", true) end
		end
		if child:IsA("GuiButton") and child.Name ~= "ExpandHit" and child.Parent
			and not child.Parent:FindFirstChildOfClass("UIListLayout")
			and not child.Parent:FindFirstChildOfClass("UIGridLayout") then
			HomeEffects.Button(child, Theme.Colors.Cyan)
		end
	end
end

return ModernChrome
