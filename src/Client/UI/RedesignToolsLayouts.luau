--!strict

-- Measured v2 surfaces surround the existing catalog, image, and settings
-- controls. Player content and the original callbacks stay native.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Factory)
local Skin = require(script.Parent.RedesignSkin)
local Motion = require(script.Parent.Motion)

local Layouts = {}
local C = Theme.Colors

local function named(root: Instance, name: string): any
	if root.Name == name then return root end
	return root:FindFirstChild(name, true)
end

local function direct(root: Instance, className: string): { any }
	local result = {}
	for _, child in root:GetChildren() do
		if child:IsA(className) and not child:GetAttribute("ForgeV2Decoration")
			and child.Name ~= "Decal" and child.Name ~= "ForgeScreenArt"
			and child.Name ~= "ForgeRedesignArt" and child.Name ~= "ForgeV2Art"
			and child.Name ~= "RedesignArt" and child.Name ~= "Gloss" and child.Name ~= "Shade"
			and child.Name ~= "DropShadow" then
			table.insert(result, child)
		end
	end
	return result
end

local function place(target: any, x: number, y: number, w: number, h: number)
	if not target then return end
	target.AutomaticSize = Enum.AutomaticSize.None
	target.AnchorPoint = Vector2.zero
	Skin.Place(target, x, y, w, h)
end

local function sizeText(target: any, size: number)
	if not target then return end
	target.TextSize = size
	target:SetAttribute("ForgeSized", true)
	local caption = target:FindFirstChild("Label")
	if caption and caption:IsA("TextLabel") then
		caption.TextSize = size
		caption:SetAttribute("ForgeSized", true)
	end
end

local function displayText(target: any, size: number)
	if not target then return end
	sizeText(target, size)
	target.Font = Theme.Fonts.Black
	target.TextStrokeColor3 = C.Ink
	target.TextStrokeTransparency = if Theme.IsHighContrast then 1 else 0.55
	local label = target:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Font = Theme.Fonts.Black
		label.TextStrokeColor3 = C.Ink
		label.TextStrokeTransparency = target.TextStrokeTransparency
	end
end

local function removeLayout(root: Instance)
	for _, child in root:GetChildren() do
		if child:IsA("UIListLayout") or child:IsA("UIPadding") then child:Destroy() end
	end
end

local function plainText(target: any)
	if not target then return end
	target.BackgroundTransparency = 1
	local decal = target:FindFirstChild("Decal")
	if decal and decal:IsA("GuiObject") then decal.Visible = false end
	for _, child in target:GetChildren() do
		if child:IsA("UIStroke") then child.Transparency = 1 end
	end
end

local function selection(target: GuiObject, selected: boolean, color: Color3?)
	local mark = target:FindFirstChild("V2SelectionMark")
	if not mark then
		mark = Factory.Stroke(target, color or C.Cyan, 1, 2)
		mark.Name = "V2SelectionMark"
	end
	local strokeMark = mark :: UIStroke
	strokeMark.Color = color or C.Cyan
	strokeMark.Transparency = if selected then 0.02 else 1
	local art = target:FindFirstChild("RedesignArt")
	if art and art:IsA("ImageLabel") then
		art.ImageColor3 = if selected then Color3.new(1, 1, 1) else Color3.fromRGB(148, 164, 190)
	end
end

local function caption(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, size: number): TextLabel
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("TextLabel") then
		existing.Text = text
		place(existing, x, y, w, h)
		sizeText(existing, size)
		existing:SetAttribute("ForgeV2Decoration", true)
		return existing
	end
	local label = Factory.Label(parent, text, UDim2.fromOffset(w, h), {
		Name = name, Position = UDim2.fromOffset(x, y), TextSize = size,
		Font = Theme.Fonts.Bold, Wrapped = true, Color = C.Text,
	})
	label:SetAttribute("ForgeSized", true)
	label:SetAttribute("ForgeV2Decoration", true)
	return label
end

local function ornament(parent: Instance, slug: string, asset: string, x: number, y: number, w: number, h: number)
	local existing = parent:FindFirstChild("V2Decoration" .. asset)
	if existing and existing:IsA("GuiObject") then
		place(existing, x, y, w, h)
		existing.Visible = not Theme.IsHighContrast
		return existing
	end
	local object = Skin.Decoration(parent, slug, asset, x, y, w, h)
	if object then
		object:SetAttribute("ForgeV2Decoration", true)
		object.ZIndex = if parent:IsA("GuiObject") then (parent :: GuiObject).ZIndex else 1
		for _, child in object:GetDescendants() do
			if child:IsA("GuiObject") then child.ZIndex = object.ZIndex end
		end
	end
	return object
end

-- Approved icon crops are separate from the button surface. Reserve a text
-- lane for them so adding detail never paints over a live caption.
local function buttonIcon(target: any, slug: string, asset: string, x: number, y: number, w: number, h: number, inset: number?)
	if not target then return end
	local icon = ornament(target, slug, asset, x, y, w, h)
	if not icon then return end
	icon.ZIndex = target.ZIndex + 2
	for _, child in icon:GetDescendants() do
		if child:IsA("GuiObject") then child.ZIndex = icon.ZIndex end
	end
	for _, old in direct(target, "ImageLabel") do old.Visible = Theme.IsHighContrast end
	local label = Factory.LiftLabel(target)
	if label then
		label.ZIndex = math.max(label.ZIndex, target.ZIndex + 3)
		if inset then
			label.Position = UDim2.fromOffset(inset, 0)
			label.Size = UDim2.new(1, -inset - 8, 1, 0)
		end
	end
end

local function verticalList(holder: Instance, gap: number)
	local layout = holder:FindFirstChildOfClass("UIListLayout")
	if not layout then layout = Factory.List(holder, Enum.FillDirection.Vertical, gap) end
	layout.Padding = UDim.new(0, gap)
end

local function scroll(parent: Instance, name: string, x: number, y: number, w: number, h: number): ScrollingFrame
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("ScrollingFrame") then
		place(existing, x, y, w, h)
		return existing
	end
	local holder = Factory.New("ScrollingFrame", {
		Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.Cyan, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
	return holder
end

local function fieldArtwork(field: TextBox?, surface: GuiObject?)
	if not field or not surface then return end
	if field:GetAttribute("ForgeV2FieldAlpha") == nil then field:SetAttribute("ForgeV2FieldAlpha", field.BackgroundTransparency) end
	local nativeAlpha = field:GetAttribute("ForgeV2FieldAlpha")
	if Theme.IsHighContrast then field.BackgroundTransparency = nativeAlpha; return end
	if field:GetAttribute("ForgeV2FieldBound") then return end
	local art = surface:FindFirstChild("RedesignArt")
	if not art or not art:IsA("ImageLabel") then return end
	field:SetAttribute("ForgeV2FieldBound", true)
	local function refresh()
		field.BackgroundTransparency = if art.IsLoaded and not Theme.IsHighContrast then 1 else nativeAlpha
	end
	local changed = art:GetPropertyChangedSignal("IsLoaded"):Connect(refresh)
	field.Destroying:Connect(function() changed:Disconnect() end)
	art.Destroying:Connect(function()
		changed:Disconnect()
		field:SetAttribute("ForgeV2FieldBound", nil)
		if field.Parent then field.BackgroundTransparency = nativeAlpha end
	end)
	refresh()
end

local function panelHeader(card: GuiObject, x: number, y: number, w: number, size: number)
	local banner = card:FindFirstChild("SectionBanner")
	if banner and banner:IsA("TextLabel") then
		place(banner, x, y, w, size + 8)
		plainText(banner)
		banner.TextColor3 = C.Text
		banner.TextXAlignment = Enum.TextXAlignment.Left
		displayText(banner, size)
	end
end

local function pageHeader(app: any, titleText: string, subtitleText: string, x: number, y: number, w: number, size: number)
	local title, subtitle = named(app.content, "PageTitle"), named(app.content, "PageSubtitle")
	if title then
		title.Text = titleText
		place(title, x, y, w, size + 12)
		displayText(title, size)
		title.ZIndex = 7
	end
	if subtitle then
		subtitle.Text = subtitleText
		place(subtitle, x + 2, y + size + 9, w + 70, 30)
		sizeText(subtitle, if size >= 55 then 24 else 21)
		subtitle.ZIndex = 7
	end
end

local function fixedGrid(app: any, grid: GuiObject, columns: number, height: number, gap: number)
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	if not layout then return end
	local function apply()
		local desired = UDim2.new(1 / columns, -gap * (columns - 1) / columns, 0, height)
		if math.abs(layout.CellSize.X.Scale - desired.X.Scale) > 0.00001
			or math.abs(layout.CellSize.X.Offset - desired.X.Offset) > 0.00001
			or layout.CellSize.Y.Scale ~= 0 or layout.CellSize.Y.Offset ~= height then
			layout.CellSize = desired
		end
		layout.CellPadding = UDim2.fromOffset(gap, gap)
	end
	apply()
	if grid:GetAttribute("ForgeV2GridBound") then return end
	grid:SetAttribute("ForgeV2GridBound", true)
	-- The catalog's original resize callback remains installed. Reassert its
	-- desktop columns whenever it recalculates them; compact renders are new.
	table.insert(app.pageConnections, layout:GetPropertyChangedSignal("CellSize"):Connect(apply))
end

local function catalogCard(card: GuiObject, index: number)
	local slot = (index - 1) % 3 + 1
	local prefix = "CatalogCard" .. tostring(slot)
	Skin.Skin(card, "avatar-lab", prefix .. "Art")
	local image = named(card, "CatalogItemThumbnail")
	if image then
		place(image, 8, 8, 297, 194)
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Fit
	end
	local title, price = named(card, "CatalogItemTitle"), named(card, "CatalogItemPrice")
	place(title, 14, 211, 285, 31); displayText(title, 22)
	place(price, 14, 245, 285, 22); sizeText(price, 15)
	local buy = named(card, "CatalogBuy")
	place(buy, 14, 271, 285, 20); sizeText(buy, 14)
	if buy then buy.TextXAlignment = Enum.TextXAlignment.Right end
	local try, bookmark = named(card, "CatalogTryOn"), named(card, "CatalogBookmark")
	place(try, 12, 295, 287, 44); sizeText(try, 20)
	if try then
		Skin.Skin(try, "avatar-lab", prefix .. "TryOnArt")
		buttonIcon(try, "avatar-lab", prefix .. "TryOnIcon", 18, 7, 30, 30, 53)
	end
	place(bookmark, 12, 349, 287, 43); sizeText(bookmark, 18)
	if bookmark then
		Skin.Skin(bookmark, "avatar-lab", prefix .. "BookmarkArt")
		buttonIcon(bookmark, "avatar-lab", prefix .. "BookmarkIcon", 18, 8, 27, 27, 53)
	end
end

local function labNavigation(app: any)
	local nav = app.content:FindFirstChild("AvatarLabSecondaryNavigation")
	if not nav then
		nav = Factory.New("Frame", { Name = "AvatarLabSecondaryNavigation", BackgroundTransparency = 1,
			BorderSizePixel = 0, ZIndex = 7, Parent = app.content })
		nav:SetAttribute("ForgeV2Decoration", true)
		for index, entry in { { "Avatar Lab", "Avatar Lab", "LabWorkspaceTabIcon" },
			{ "Avatar Graphics", "Avatar Graphics", "LabGraphicsTabIcon" }, { "More tools", "TOOLS", "LabMoreToolsIcon" } } do
			local button = Factory.ImageButton(nav, entry[1], UDim2.fromOffset(330, 60), UDim2.fromOffset((index - 1) * 344, 3))
			button.Name = if index == 1 then "OpenAvatarLab" elseif index == 2 then "OpenAvatarGraphics" else "OpenLabTools"
			button.ZIndex = 8; sizeText(button, 22)
			Skin.Skin(button, "avatar-lab", "LabWorkspaceTabArt")
			buttonIcon(button, "avatar-lab", entry[3], 17, 14, 32, 32, 57)
			selection(button, index == 1)
			app:_BindButton(button)
			button.Activated:Connect(function()
				if entry[2] == "TOOLS" then
					if app.catalogWorkspace then
						app.catalogWorkspace.moreTabs = true
						app.catalogWorkspace.guideDismissed = true
						app.makeoverGuideRequested = false
						app:_RenderActivePage()
					end
					require(script.Parent.HomeScreen).ShowTools(app)
				else app:_OpenPage(entry[2]) end
			end)
		end
	end
	place(nav, 578, 243, 1030, 66)
	nav.Visible = true
	Skin.Skin(nav, "avatar-lab", "LabSecondaryNavArt")
end

local function guidedTypography(app: any, stack: Instance)
	for _, node in stack:GetDescendants() do
		if node:IsA("TextLabel") and not node:GetAttribute("ForgeV2Decoration") then sizeText(node, math.max(16, node.TextSize or 16)) end
	end
	local looks = named(stack, "StarterLooks")
	if not looks then return end
	looks.Size = UDim2.new(1, 0, 0, 296)
	for _, card in direct(looks, "Frame") do
		if card.Name ~= "StarterLook" then continue end
		card.Size = UDim2.fromOffset(276, 278)
		for _, label in direct(card, "TextLabel") do
			local role = label:GetAttribute("ForgeStarterTextRole")
			if not role then
				role = if label.Position.Y.Offset == 10 then "Title" elseif label.Position.Y.Offset == 35 then "Description" else "Availability"
				label:SetAttribute("ForgeStarterTextRole", role)
			end
			if role == "Title" then place(label, 12, 10, 252, 29); displayText(label, 20)
			elseif role == "Description" then
				place(label, 12, 44, 252, 58); sizeText(label, 16); label.TextWrapped = true
			else place(label, 12, 111, 252, 74); sizeText(label, 16) end
		end
		for index, image in direct(card, "ImageLabel") do place(image, 14 + (index - 1) * 85, 111, 74, 74) end
		local target = named(card, "GuideTargetLabel")
		if target then
			place(target, 12, 192, 252, 28)
			if not target:GetAttribute("ForgeStarterPulseBound") then
				target:SetAttribute("ForgeStarterPulseBound", true)
				local pulse = Motion.Pulse(target, 0.48, { Position = UDim2.fromOffset(12, 196) })
				if pulse then target.Destroying:Connect(function() pulse:Cancel() end) end
			end
		end
		local wear = direct(card, "TextButton")[1]
		place(wear, 12, 226, 252, 44); sizeText(wear, 17)
	end
end

local function catalog(app: any)
	local page = named(app.content, "AvatarLabWorkspace")
	if not page then return end
	pageHeader(app, "Avatar Lab", "Build a look that feels like you.", 188, 235, 350, 55)
	ornament(app.content, "avatar-lab", "LabTitleIcon", 79, 242, 79, 79)
	ornament(app.content, "avatar-lab", "CatalogWorkspaceArt", 63, 330, 990, 555)
	place(page, 63, 330, 990, 555)
	page.ZIndex = app.content.ZIndex + 1
	removeLayout(page)
	local stack = direct(page, "Frame")[1]
	if not stack then return end
	stack.Size = UDim2.new(1, -8, 0, 0)
	local lab = app.catalogWorkspace or {}
	labNavigation(app)
	local tabs = named(page, "CatalogTabs")
	if tabs then
		-- These are Browse/Look/Bookmarks controls, not cross-page navigation.
		-- Keep their real callbacks in the workspace; the header row above is
		-- present even during guided stages, where the native tabs do not exist.
		tabs.Visible = lab.moreTabs == true or lab.tab ~= "BROWSE"
		tabs.Size = UDim2.new(1, 0, 0, 55)
		tabs.ScrollingDirection = Enum.ScrollingDirection.X
		tabs.ScrollBarThickness = 3
		local buttons = direct(tabs, "TextButton")
		local width = if #buttons > 3 then 180 else 220
		for _, button in buttons do
			button.Size = UDim2.fromOffset(width, 48)
			sizeText(button, 18)
			Skin.Skin(button, "avatar-lab", "LabWorkspaceTabArt")
			local selected = (button.Text == "Find items" and lab.tab == "BROWSE")
				or (button.Text == "My avatar" and lab.tab == "LOOK")
				or (button.Text == "Bookmarks" and lab.tab == "SAVED")
				or (button.Text == "My custom items" and lab.tab == "FORGE")
			selection(button, selected)
		end
	end
	-- Guided/onboarding, current-look, bookmarks, and advanced filters keep
	-- their complete original scrolling flow inside the imported workspace.
	local normalBrowse = lab.tab == "BROWSE" and named(stack, "CatalogSearchRow") ~= nil
	local simple = app.state.profile.settings.simpleMode ~= false
	if not normalBrowse or not simple or lab.filters == true or lab.showChallenge == true
		or (tabs and tabs.Visible)
		or (app.state.makeoverState and app.state.makeoverState.active == true) then
		for _, label in direct(stack, "TextLabel") do sizeText(label, 18) end
		guidedTypography(app, stack)
		return
	end
	local searchRow, categories, filters = named(stack, "CatalogSearchRow"), named(stack, "CatalogCategories"), named(stack, "CatalogFilterRow")
	removeLayout(stack)
	place(searchRow, 15, 11, 970, 53)
	local search, searchButton = direct(searchRow, "TextBox")[1], direct(searchRow, "TextButton")[1]
	place(search, 0, 0, 775, 53); sizeText(search, 22)
	local searchSurface = ornament(searchRow, "avatar-lab", "CatalogSearchFieldArt", 0, 0, 775, 53)
	fieldArtwork(search, searchSurface)
	if search then search.ZIndex = searchRow.ZIndex + 1 end
	place(searchButton, 790, 0, 180, 54); sizeText(searchButton, 21)
	if searchButton then Skin.Skin(searchButton, "avatar-lab", "CatalogSearchArt") end
	if categories then
		place(categories, 15, 79, 970, 57)
		local categoryLayout = categories:FindFirstChildOfClass("UIListLayout")
		if categoryLayout then categoryLayout.Padding = UDim.new(0, 11) end
		local assets = { "CategoryHairArt", "CategoryHatsArt", "CategoryFaceArt", "CategoryShirtsArt", "CategoryPantsArt", "CategoryJacketsArt", "CategoryBackArt" }
		local icons = { "CategoryHairIcon", "CategoryHatsIcon", "CategoryFaceIcon", "CategoryShirtsIcon", "CategoryPantsIcon", "CategoryJacketsIcon", "CategoryBackIcon" }
		local widths = { 98, 101, 98, 108, 106, 120, 99 }
		local types = { "HairAccessory", "Hat", "FaceAccessory", "Shirt", "Pants", "JacketAccessory", "BackAccessory" }
		for index, button in direct(categories, "TextButton") do
			if button:GetAttribute("ForgeCatalogFilter") then continue end
			button.LayoutOrder = index
			button.Size = UDim2.fromOffset(widths[index] or 100, 49)
			sizeText(button, 16)
			Skin.Skin(button, "avatar-lab", assets[index] or "CategoryHairArt")
			buttonIcon(button, "avatar-lab", icons[index] or "CategoryHairIcon", 7, 12, 25, 25, 34)
			selection(button, app.catalogType == types[index])
		end
		if filters then
			for _, button in direct(filters, "TextButton") do
				button:SetAttribute("ForgeCatalogFilter", true)
				button.Parent = categories; button.LayoutOrder = 20
				button.Size = UDim2.fromOffset(163, 49); sizeText(button, 16)
				Skin.Skin(button, "avatar-lab", "CategoryMorefiltersArt")
				buttonIcon(button, "avatar-lab", "CategoryMorefiltersIcon", 9, 12, 25, 25, 38)
			end
			filters.Visible = false; filters.Size = UDim2.new()
		end
	end
	local grid = named(stack, "CatalogItemsGrid")
	if grid then
		grid.Position = UDim2.fromOffset(15, 148)
		grid.Size = UDim2.fromOffset(970, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		fixedGrid(app, grid, 3, 404, 18)
		for _, card in direct(grid, "Frame") do
			if card.Name == "StyleItem" then catalogCard(card, card.LayoutOrder) end
		end
	end
	local bottom = 148 + math.ceil(#(app.catalogResults or {}) / 3) * 422
	for _, node in direct(stack, "GuiObject") do
		if node == searchRow or node == categories or node == filters or node == grid then continue end
		if node:IsA("TextLabel") and node.LayoutOrder == 10 then
			place(node, 15, bottom, 970, 24); sizeText(node, 15); bottom += 32
		elseif node.Visible then
			place(node, 15, bottom, 970, math.max(40, node.Size.Y.Offset))
			bottom += node.Size.Y.Offset + 12
		end
	end
end

function Layouts.ApplyPreview(app: any): boolean
	if app.compact or app.activePage ~= "Avatar Lab" or not app.avatarPreviewPanel then return false end
	local panel = app.avatarPreviewPanel
	if not panel.Visible then return false end
	place(panel, 1061, 331, 557, 555)
	panel.ZIndex = 5
	panel.ClipsDescendants = true
	Skin.Skin(panel, "avatar-lab", "AvatarStageArt")
	local freeTryOn = panel:FindFirstChild("V2FreeTryOn")
	if freeTryOn and freeTryOn:IsA("GuiObject") then freeTryOn.Visible = false end
	local title = named(panel, "PreviewTitle")
	place(title, 18, 13, 305, 45); displayText(title, 34)
	local viewport = app.avatarPreviewViewport
	place(viewport, 15, 69, 258, 427)
	viewport.BackgroundTransparency = 1
	local reset = named(panel, "ResetCamera")
	if reset then
		reset.Parent = panel
		place(reset, 336, 13, 207, 47); sizeText(reset, 20)
		reset.Text = "Reset camera"
		Skin.Skin(reset, "avatar-lab", "ResetAvatarCameraArt")
		buttonIcon(reset, "avatar-lab", "ResetAvatarCameraIcon", 10, 10, 27, 27, 40)
	end
	local divider = named(panel, "Divider")
	if divider then divider.Visible = false end
	local wornSurface = ornament(panel, "avatar-lab", "WornItemsPanelArt", 284, 73, 263, 476)
	if wornSurface then
		wornSurface.ZIndex = panel.ZIndex + 1
		for _, child in wornSurface:GetDescendants() do if child:IsA("GuiObject") then child.ZIndex = wornSurface.ZIndex end end
	end
	local heading = named(panel, "PreviewWornHeading")
	place(heading, 298, 85, 240, 30); displayText(heading, 23)
	local list = app.avatarPreviewList
	local returning = list.Position.X.Offset ~= 298
	place(list, 298, 124, 240, 335)
	list.Visible = true
	list.BackgroundTransparency = 1
	list.ZIndex = panel.ZIndex + 3
	list.ScrollBarThickness = 4
	local rows = direct(list, "Frame")
	if returning or #rows <= 4 then list.CanvasPosition = Vector2.zero end
	if heading then
		heading.Visible = true
		heading.ZIndex = panel.ZIndex + 3
		heading.Text = "Wearing (" .. tostring(#rows) .. ")"
		heading.TextColor3 = C.Text
	end
	local padding = list:FindFirstChildOfClass("UIPadding")
	if padding then padding.PaddingRight = UDim.new(0, 3) end
	sizeText(app.avatarPreviewEmptyLabel, 17)
	for _, row in rows do
		if row.Name ~= "TriedOnItemRow" then continue end
		row.Visible = true
		row.ZIndex = list.ZIndex + 1
		row.Size = UDim2.new(1, -3, 0, 74)
		Skin.Skin(row, "avatar-lab", "WornRow1Art")
		local image = direct(row, "ImageLabel")[1]
		place(image, 4, 11, 52, 51)
		if image then image.BackgroundTransparency = 1; image.ZIndex = row.ZIndex + 2 end
		for _, label in direct(row, "TextLabel") do
			local source = label.Position.Y.Offset >= 25
			place(label, 61, if source then 40 else 7, 136, if source then 23 else 29)
			sizeText(label, 16)
			label.ZIndex = row.ZIndex + 3
		end
		local remove = direct(row, "TextButton")[1]
		if remove then
			place(remove, 200, 19, 33, 35)
			-- Keep the native removal callback and its busy caption.
			if remove.Text == "Remove" then remove.Text = "×" end
			sizeText(remove, 20)
			Skin.Skin(remove, "avatar-lab", "RemoveWorn1Art")
		end
	end
	if not panel:FindFirstChild("SaveNewLook") then
		local save = Factory.ImageButton(panel, "Save new look", UDim2.fromOffset(241, 66), UDim2.fromOffset(299, 474), "primary")
		save.Name = "SaveNewLook"; sizeText(save, 22)
		app:_BindButton(save)
		save.Activated:Connect(function()
			if app.activePage ~= "Avatar Lab" or not app.catalogWorkspace then return end
			app.catalogWorkspace.tab = "LOOK"
			app.scrollPositions.AvatarLabWorkspace = Vector2.zero
			app:_RenderActivePage()
		end)
	end
	local save = panel:FindFirstChild("SaveNewLook")
	if save and save:IsA("GuiObject") then
		save.Visible = true
		place(save, 299, 474, 241, 66)
		Skin.Skin(save, "avatar-lab", "SaveNewLookArt")
		buttonIcon(save, "avatar-lab", "SaveNewLookIcon", 14, 18, 29, 29, 48)
	end
	local drag = caption(panel, "AvatarDragHint", "Drag to rotate", 49, 507, 176, 37, 16)
	drag.Visible = true
	drag.TextColor3 = C.TextMuted
	return true
end

local function graphicsCard(app: any, card: GuiObject, index: number)
	local slot = (index - 1) % 2 + 1
	local prefix = "GraphicGalleryCard" .. tostring(slot)
	Skin.Skin(card, "avatar-graphics", prefix .. "Art")
	ornament(card, "avatar-graphics", prefix .. "PreviewFrameArt", 3, 7, 288, 378)
	local image = direct(card, "ImageLabel")[1]
	place(image, 3, 7, 288, 378)
	if image then
		image.ScaleType = Enum.ScaleType.Fit
		image.ZIndex = card.ZIndex + 3
	end
	local link = direct(card, "TextBox")[1]
	for _, label in direct(card, "TextLabel") do
		if label.Position.Y.Offset == 148 then
			place(label, 13, 388, 270, 39); sizeText(label, 18)
		elseif label.Position.Y.Offset == 178 then
			place(label, 13, 425, 270, 23); sizeText(label, 16)
		elseif label.Position.Y.Offset == 200 then
			-- The link is selected by a real control below instead of a long
			-- permanent URL consuming the poster's content area.
			label.Visible = false
		end
	end
	local delete = direct(card, "TextButton")[1]
	place(delete, 197, 457, 87, 51); sizeText(delete, 15)
	if delete then
		Skin.Skin(delete, "avatar-graphics", prefix .. "DeleteArt")
		buttonIcon(delete, "avatar-graphics", prefix .. "DeleteIcon", 7, 17, 18, 18, 27)
	end
	if link then
		local canCopy = link.TextEditable
		place(link, 13, 457, 174, 51)
		link.Visible = false
		link.ZIndex = card.ZIndex + 8
		link.TextSize = 10
		link:SetAttribute("ForgeSized", true)
		local copy = card:FindFirstChild("CopyGraphicLink")
		if not copy then
			copy = Factory.ImageButton(card, if canCopy then "Copy link" else "Link unavailable", UDim2.fromOffset(174, 51), UDim2.fromOffset(13, 457))
			copy.Name = "CopyGraphicLink"
			app:_BindButton(copy)
			copy.Activated:Connect(function()
				if not link.TextEditable then return end
				link.Visible = true
				link:CaptureFocus()
				link.CursorPosition = 1
				link.SelectionStart = #link.Text + 1
				app:_Toast("info", "Full-resolution link selected. Copy it, then open it in your browser to save the image.")
			end)
			link.FocusLost:Connect(function() link.Visible = false end)
		end
		copy.Text = if canCopy then "Copy link" else "No link"
		copy.Active = canCopy
		sizeText(copy, 17)
		Skin.Skin(copy, "avatar-graphics", prefix .. "CopyLinkArt")
		buttonIcon(copy, "avatar-graphics", prefix .. "CopyLinkIcon", 11, 14, 25, 25, 40)
	end
end

local function graphicsActivity(app: any, activity: GuiObject)
	activity.Parent = app.content
	place(activity, 77, 775, 889, 116)
	Skin.Skin(activity, "avatar-graphics", "GraphicsActivityArt")
	ornament(activity, "avatar-graphics", "GraphicsActivityClock", 16, 4, 25, 25)
	panelHeader(activity, 54, 0, 650, 24)
	local rows = direct(activity, "Frame")
	local holder = scroll(activity, "LiveGraphicsJobs", 54, 36, 819, 79)
	verticalList(holder, 7)
	for _, row in rows do
		row.Parent = holder
		row.Size = UDim2.new(1, -3, 0, 79)
		Skin.Skin(row, "avatar-graphics", "GraphicsJobRowArt")
		for _, label in direct(row, "TextLabel") do
			local oldY = label.Position.Y.Offset
			if label.AnchorPoint.X == 1 then
				place(label, 735, 52, 70, 24); sizeText(label, 17)
			elseif oldY == 4 then
				place(label, 104, 4, 680, 28); sizeText(label, 20)
			else
				place(label, 104, 35, 680, 21); sizeText(label, 13)
			end
		end
		for _, part in direct(row, "Frame") do
			if part.Position.Y.Offset == 39 then
				place(part, 104, 62, 620, 14)
			elseif part.Position.X.Offset == 7 then
				place(part, 5, 5, 82, 68)
			end
		end
	end
end

local function graphics(app: any)
	local page = named(app.content, "AvatarGraphicsScroll")
	local composer, gallery = named(app.content, "GraphicComposer"), named(app.content, "GraphicsGallery")
	if not page or not composer or not gallery then return end
	local activity = named(app.content, "GraphicActivity")
	local tabs = nil
	for _, frame in direct(app.content, "Frame") do
		local buttons = direct(frame, "TextButton")
		if #buttons == 2 and buttons[1].Text == "Create" then tabs = frame; break end
	end
	composer.Parent = app.content; gallery.Parent = app.content
	composer.Visible = true; gallery.Visible = true
	composer.ZIndex = app.content.ZIndex + 1
	gallery.ZIndex = app.content.ZIndex + 1
	page.Visible = false
	place(composer, 61, 229, 918, 666)
	place(gallery, 995, 229, 624, 666)
	Skin.Skin(composer, "avatar-graphics", "GraphicsComposerArt")
	Skin.Skin(gallery, "avatar-graphics", "GraphicsGalleryArt")
	pageHeader(app, "Avatar Graphics", "Turn your look into something shareable.", 149, 243, 430, 53)
	local titleSparkle = ornament(app.content, "avatar-graphics", "GraphicsTitleSparkle1", 80, 250, 51, 51)
	local formSurface = ornament(composer, "avatar-graphics", "GraphicsFormArt", 16, 115, 887, 429)
	if tabs then
		place(tabs, 611, 250, 355, 63); removeLayout(tabs)
		tabs.ZIndex = 5
		for index, button in direct(tabs, "TextButton") do
			place(button, if index == 1 then 1 else 185, 3, if index == 1 then 174 else 170, 58)
			sizeText(button, if index == 1 then 23 else 20)
			Skin.Skin(button, "avatar-graphics", "GraphicsCreateTabArt")
			buttonIcon(button, "avatar-graphics", if index == 1 then "GraphicsCreateTabIcon" else "GraphicsDiscoverTabIcon", 13, 16, 27, 27, 44)
			selection(button, index == 1)
		end
	end
	local textMode = app.graphicMode == "TEXT"
	local sourceRow = nil
	for _, frame in direct(composer, "Frame") do
		if #direct(frame, "TextButton") == 2 then sourceRow = frame; break end
	end
	if sourceRow then
		place(sourceRow, 301, 124, 589, 46)
		sourceRow.Visible = true
		sourceRow.ZIndex = composer.ZIndex + 3
		local buttons = direct(sourceRow, "TextButton")
		for index, button in buttons do
			place(button, if index == 1 then 0 else 292, 0, if index == 1 then 281 else 297, 46)
			sizeText(button, if index == 1 then 20 else 18)
			Skin.Skin(button, "avatar-graphics", if index == 1 then "GraphicsMyAvatarSourceArt" else "GraphicsTextSourceArt")
			buttonIcon(button, "avatar-graphics", if index == 1 then "GraphicsMyAvatarSourceIcon" else "GraphicsTextSourceIcon", 16, 7, 32, 32, 53)
			local selected = (index == 1 and not textMode) or (index == 2 and textMode)
			selection(button, selected)
			button:SetAttribute("ForgeSelected", selected)
			button.TextColor3 = if selected then C.Text else C.TextMuted
			local mark, art = button:FindFirstChild("V2SelectionMark"), button:FindFirstChild("RedesignArt")
			if mark then mark.Thickness = if selected then 3.5 else 2 end
			if art then art.ImageColor3 = if selected then Color3.fromRGB(134, 230, 255) else Color3.fromRGB(90, 112, 138) end
		end
	end
	local prompt = direct(composer, "TextBox")[1]
	place(prompt, if textMode then 30 else 300, if textMode then 210 else 317, if textMode then 855 else 592, if textMode then 171 else 72); sizeText(prompt, 20)
	if prompt then
		prompt.Visible = true
		prompt.ZIndex = composer.ZIndex + 4
	end
	local promptSurface = ornament(composer, "avatar-graphics", "GraphicsPromptFieldArt", if textMode then 30 else 300, if textMode then 210 else 317, if textMode then 855 else 592, if textMode then 171 else 72)
	fieldArtwork(prompt, promptSurface)
	for _, image in direct(composer, "ImageLabel") do
		if string.find(image.Image, "rbxthumb://", 1, true) then
			place(image, 29, 176, 253, 210)
			image.ScaleType = Enum.ScaleType.Fit
			image.BackgroundTransparency = 1
			image.ImageTransparency = 0
			image.Visible = true
			image.ZIndex = composer.ZIndex + 4
		end
	end
	if not textMode then ornament(composer, "avatar-graphics", "GraphicsSourceThumbnailArt", 29, 176, 253, 210) end
	for _, label in direct(composer, "TextLabel") do
		local text = label.Text
		if text == "SOURCE" then
			label.Text = "Choose a source"; place(label, 76, 124, 220, 33); sizeText(label, 21)
		elseif string.find(text, "CHOOSE YOUR AVATAR VIEW", 1, true) then
			label.Text = "Choose a view"; place(label, 349, 177, 510, 31); sizeText(label, 20)
		elseif string.find(text, "DESCRIBE", 1, true) then
			place(label, if textMode then 40 else 349, if textMode then 176 else 279, if textMode then 835 else 530, 30); sizeText(label, if textMode then 21 else 18)
		elseif string.match(text, "^%d+ / %d+") then
			place(label, 750, 389, 128, 20); sizeText(label, 15)
			label.TextXAlignment = Enum.TextXAlignment.Right
		elseif string.find(text, "provider moderation", 1, true) then
			place(label, 30, 510, 855, 34); sizeText(label, 16)
		elseif string.find(text, "Fetched automatically", 1, true) then
			label.Text = "Your current Roblox avatar.\nDefault style and quality."
			place(label, 29, 392, 253, 44); sizeText(label, 16)
		elseif string.find(text, "Style and quality", 1, true) then
			label.Visible = false
			label:SetAttribute("ForgeV2Suppressed", true)
		end
	end
	local views = named(composer, "GraphicsChoiceOptions")
	if views then
		place(views, 301, 219, 589, 46)
		views.Visible = true
		views.ZIndex = composer.ZIndex + 3
		removeLayout(views)
		local assets = { "GraphicsHeadshotViewArt", "GraphicsBustViewArt", "GraphicsFullBodyViewArt" }
		local icons = { "GraphicsHeadshotViewIcon", "GraphicsBustViewIcon", "GraphicsFullBodyViewIcon" }
		local ids = { "HEADSHOT", "BUST", "FULL_BODY" }
		for index, button in direct(views, "TextButton") do
			place(button, (index - 1) * 200, 0, if index == 1 then 190 else 188, 46)
			sizeText(button, 20); Skin.Skin(button, "avatar-graphics", assets[index] or assets[1])
			buttonIcon(button, "avatar-graphics", icons[index] or icons[1], 10, 9, 28, 28, 42)
			selection(button, app.selectedAvatarView == ids[index])
		end
	end
	for _, button in direct(composer, "TextButton") do
		if string.find(button.Text, "Advanced Mode", 1, true) then
			place(button, 301, 413, 591, 29); sizeText(button, 17)
			Skin.Skin(button, "avatar-graphics", "GraphicsAdvancedOptionsArt")
			buttonIcon(button, "avatar-graphics", "GraphicsAdvancedOptionsIcon", 11, 4, 21, 21, 38)
		elseif string.find(button.Text, "Create", 1, true) then
			place(button, 26, 449, 868, 56); sizeText(button, 25)
			Skin.Skin(button, "avatar-graphics", "GraphicsGenerateArt")
			buttonIcon(button, "avatar-graphics", "GraphicsGenerateIcon", 27, 12, 32, 32)
		end
	end
	panelHeader(gallery, 89, 8, 330, 43)
	local count = caption(gallery, "GraphicCount", string.format("%d items", #(app.state.profile.graphicOrder or {})), 444, 20, 165, 36, 21)
	count.TextXAlignment = Enum.TextXAlignment.Right
	ornament(gallery, "avatar-graphics", "GraphicsGalleryIcon", 28, 19, 42, 42)
	local holder = scroll(gallery, "LiveGraphicsGallery", 12, 90, 600, 546)
	for _, frame in direct(gallery, "Frame") do
		if frame:FindFirstChildOfClass("UIGridLayout") then
			frame.Parent = holder
			frame.Position = UDim2.fromOffset(0, 0)
			frame.Size = UDim2.new(1, -4, 0, math.ceil(#(app.state.profile.graphicOrder or {}) / 2) * 536)
			fixedGrid(app, frame, 2, 526, 10)
			for _, card in direct(frame, "Frame") do
				if card.Name == "GraphicItem" then graphicsCard(app, card, card.LayoutOrder) end
			end
		end
	end
	local empty = #(app.state.profile.graphicOrder or {}) == 0
	for _, label in direct(gallery, "TextLabel") do
		if label.Name == "SectionBanner" then continue end
		place(label, 42, if empty then 257 else 100, 540, 80)
		displayText(label, 25)
		label.TextXAlignment = Enum.TextXAlignment.Center
	end
	if empty then
		ornament(gallery, "avatar-graphics", "GraphicsTitleSparkle2", 256, 139, 110, 96)
		local help = caption(gallery, "EmptyGalleryHelp", "Choose a source and create a graphic. Your saved images appear here.", 44, 342, 536, 76, 21)
		help.TextColor3 = C.TextMuted
		help.TextXAlignment = Enum.TextXAlignment.Center
	end
	if activity then
		activity.ZIndex = composer.ZIndex + 4
		graphicsActivity(app, activity)
	else
		local idle = app.content:FindFirstChild("GraphicsIdleActivity")
		if not idle then idle = Factory.New("Frame", { Name = "GraphicsIdleActivity", BackgroundTransparency = 1, Parent = app.content }) end
		place(idle, 77, 775, 889, 116)
		idle.ZIndex = composer.ZIndex + 4
		Skin.Skin(idle, "avatar-graphics", "GraphicsActivityArt")
		ornament(idle, "avatar-graphics", "GraphicsActivityClock", 16, 5, 25, 25)
		displayText(caption(idle, "IdleHeading", "In progress", 54, 0, 760, 36, 24), 24)
		caption(idle, "IdleDescription", "No images generating. Your new graphics will appear in the gallery.", 54, 42, 780, 50, 20)
		for _, child in direct(idle, "GuiObject") do child.ZIndex = idle.ZIndex + 1 end
	end
	-- Loaded form/thumbnail crops are opaque surfaces. Reparenting out of the
	-- original scroll only preserves the controls if their own layer also
	-- clears those new surfaces; otherwise the entire live form is covered.
	if formSurface then
		formSurface.ZIndex = composer.ZIndex + 1
		for _, child in formSurface:GetDescendants() do if child:IsA("GuiObject") then child.ZIndex = formSurface.ZIndex end end
	end
	if titleSparkle then
		titleSparkle.ZIndex = composer.ZIndex + 4
		for _, child in titleSparkle:GetDescendants() do if child:IsA("GuiObject") then child.ZIndex = titleSparkle.ZIndex end end
	end
	local thumbnailWell = composer:FindFirstChild("V2DecorationGraphicsSourceThumbnailArt")
	if thumbnailWell and thumbnailWell:IsA("GuiObject") then
		thumbnailWell.ZIndex = composer.ZIndex + 2
		for _, child in thumbnailWell:GetDescendants() do if child:IsA("GuiObject") then child.ZIndex = thumbnailWell.ZIndex end end
	end
	for _, control in direct(composer, "GuiObject") do
		control.Visible = control:GetAttribute("ForgeV2Suppressed") ~= true
		control.ZIndex = math.max(control.ZIndex, composer.ZIndex + 3)
		if control:IsA("TextLabel") or control:IsA("TextButton") then
			local label = control:FindFirstChild("Label")
			control.TextTransparency = if label then 1 else 0
			if label and label:IsA("TextLabel") then label.Visible = true; label.TextTransparency = 0 end
		end
	end
end

local function achievementArtwork(tile: Instance, medallion: any)
	if not medallion then return end
	local glyph = direct(medallion, "TextLabel")[1]
	if not glyph then return end
	local earned = glyph:GetAttribute("ForgeActualAchievementEarned")
	if earned == nil then
		earned = glyph.Text == "✦"
		glyph:SetAttribute("ForgeActualAchievementEarned", earned)
	end
	if not earned then return end
	local title = direct(tile, "TextLabel")[1]
	local asset = if title and string.find(title.Text, "Friend", 1, true) then "SettingsInviteArt"
		elseif title and string.find(title.Text, "Collector", 1, true) then "SettingsCollectorArt"
		elseif title and string.find(title.Text, "Prolific", 1, true) then "SettingsProlificArt" else "SettingsFirstSparkArt"
	local size = medallion.Size.X.Offset
	local icon = ornament(medallion, "settings", asset, 0, 0, size, size)
	if icon and not Theme.IsHighContrast then
		icon.ZIndex = medallion.ZIndex + 1
		for _, child in icon:GetDescendants() do if child:IsA("GuiObject") then child.ZIndex = icon.ZIndex end end
		glyph.Visible = false
	else
		glyph.Text = "Earned"
		sizeText(glyph, 12)
		glyph.Visible = true
	end
end

local function settings(app: any)
	local page = named(app.content, "SettingsScroll")
	local mode, accessibility, audio = named(app.content, "CreateMode"), named(app.content, "Accessibility"), named(app.content, "Audio")
	local loadout, achievements = named(app.content, "Loadout"), named(app.content, "Achievements")
	local invite, group = named(app.content, "InviteFriends"), named(app.content, "CreatorGroup")
	if not page or not mode or not accessibility or not audio or not loadout or not achievements then return end
	pageHeader(app, "Settings", "Make Forge feel right for you.", 82, 227, 850, 62)
	for _, card in { mode, accessibility, audio, loadout, achievements } do card.Parent = app.content end
	page.Visible = false
	place(mode, 65, 330, 769, 208); Skin.Skin(mode, "settings", "CreationModePanelArt")
	place(accessibility, 848, 328, 768, 210); Skin.Skin(accessibility, "settings", "AccessibilityPanelArt")
	place(audio, 65, 550, 769, 160); Skin.Skin(audio, "settings", "AudioPanelArt")
	place(loadout, 848, 550, 768, 160); Skin.Skin(loadout, "settings", "EquippedItemsPanelArt")
	place(achievements, 65, 722, 769, 193); Skin.Skin(achievements, "settings", "AchievementsPanelArt")
	panelHeader(mode, 256, 10, 491, 32)
	panelHeader(accessibility, 235, 7, 509, 32)
	panelHeader(audio, 257, 10, 490, 31)
	panelHeader(loadout, 269, 10, 480, 31)
	panelHeader(achievements, 222, 3, 525, 29)
	ornament(mode, "settings", "SettingsCreationArt", 7, 8, 230, 194)
	ornament(accessibility, "settings", "SettingsAccessibilityArt", 7, 9, 216, 194)
	ornament(audio, "settings", "SettingsAudioArt", 9, 10, 225, 140)
	ornament(achievements, "settings", "SettingsTrophyArt", 11, 16, 192, 162)
	for _, label in direct(mode, "TextLabel") do
		if label.Name == "SectionBanner" then continue end
		if label.Position.Y.Offset == 32 then
			label.Visible = false
		else
			label.Text = "Start with a prompt and a few ideas. Advanced adds every method, style, fit and sharing option."
			place(label, 257, 52, 490, 53); sizeText(label, 18)
		end
	end
	local simpleMode = app.state.profile.settings.simpleMode ~= false
	for index, button in direct(mode, "TextButton") do
		place(button, if index == 1 then 257 else 501, 113, if index == 1 then 230 else 246, 71)
		button.Text = if index == 1 then "Simple" else "Advanced"
		displayText(button, 24)
		Skin.Skin(button, "settings", if index == 1 then "SimpleModeArt" else "AdvancedModeArt")
		buttonIcon(button, "settings", if index == 1 then "SimpleModeCube" else "AdvancedModeGear", 15, 20, 31, 31, 53)
		selection(button, (index == 1 and simpleMode) or (index == 2 and not simpleMode))
	end
	local controls = scroll(accessibility, "AccessibilityControls", 233, 76, 515, 128)
	local switches = direct(accessibility, "TextButton")
	for _, label in direct(accessibility, "TextLabel") do
		if label.Name == "SectionBanner" then continue end
		local oldY = label.Position.Y.Offset
		label.Parent = controls
		if oldY == 36 or oldY == 96 then
			place(label, 18, if oldY == 36 then 0 else 44, 388, 25); sizeText(label, 21)
		elseif oldY == 58 or oldY == 118 then
			place(label, 18, if oldY == 58 then 23 else 67, 388, 18); sizeText(label, 12)
		elseif oldY == 156 then
			label.Text = "UI scale"; place(label, 12, 91, 106, 28); sizeText(label, 20)
		elseif oldY == 180 then
			place(label, 438, 91, 72, 28); sizeText(label, 20)
		else
			-- Keyboard help stays available below the three main options.
			place(label, 12, 130, 493, 95); sizeText(label, 16)
		end
	end
	for _, button in switches do
		local oldY = button.Position.Y.Offset
		button.Parent = controls
		if button.Name == "Switch" then
			place(button, 423, if oldY < 80 then 5 else 49, 74, 35)
			sizeText(button, 12)
		else
			-- Preserve the live slider's alpha, knob and pointer callbacks.
			place(button, 110, 102, 323, 14)
			local parts = direct(button, "Frame")
			local fill, knob = parts[1], parts[2]
			if fill then fill.BackgroundColor3 = C.Cyan end
			if knob then
				knob.Size = UDim2.fromOffset(29, 29)
				knob.BackgroundColor3 = C.Text
				local gradient = knob:FindFirstChildOfClass("UIGradient")
				if gradient then gradient:Destroy() end
			end
		end
	end
	for _, label in direct(audio, "TextLabel") do
		if label.Name == "SectionBanner" then continue end
		if label.Text == "Sound effects" then
			place(label, 275, 93, 365, 29); sizeText(label, 22)
		else
			place(label, 257, 48, 490, 36); sizeText(label, 20)
		end
	end
	local sound = direct(audio, "TextButton")[1]
	place(sound, 654, 89, 74, 35); sizeText(sound, 12)
	local equippedRows = direct(loadout, "Frame")
	local equipped = scroll(loadout, "EquippedItems", 10, 54, 746, 96)
	verticalList(equipped, 8)
	for _, row in equippedRows do
		row.Parent = equipped
		row.Size = UDim2.new(1, -4, 0, 100)
		row.BackgroundTransparency = 1
		local image = direct(row, "ImageLabel")[1]
		place(image, 0, 0, 244, 96)
		if image then image.ScaleType = Enum.ScaleType.Fit; image.BackgroundTransparency = 1 end
		for _, label in direct(row, "TextLabel") do
			local detail = label.Position.Y.Offset >= 25
			place(label, 269, if detail then 73 else 37, 247, if detail then 22 else 36)
			sizeText(label, if detail then 14 else 24)
		end
		local remove = direct(row, "TextButton")[1]
		place(remove, 521, 34, 224, 59); sizeText(remove, 24)
		if remove then
			Skin.Skin(remove, "settings", "RemoveEquippedArt")
			buttonIcon(remove, "settings", "RemoveTrashIcon", 15, 16, 27, 27, 47)
		end
	end
	for _, label in direct(loadout, "TextLabel") do
		if label.Name == "SectionBanner" then continue end
		label.Parent = equipped; place(label, 245, 10, 480, 70)
		sizeText(label, 20)
	end
	local allAchievements = scroll(achievements, "EveryAchievement", 221, 54, 528, 128)
	for _, grid in direct(achievements, "Frame") do
		local layout = grid:FindFirstChildOfClass("UIGridLayout")
		if not layout then continue end
		grid.Parent = allAchievements
		grid.Position = UDim2.fromOffset(0, 0)
		grid.Size = UDim2.new(1, -4, 0, math.ceil(#direct(grid, "Frame") / 4) * 172)
		fixedGrid(app, grid, 4, 164, 8)
		for _, tile in direct(grid, "Frame") do
			local medallion = direct(tile, "Frame")[1]
			if medallion then
				medallion.Size = UDim2.fromOffset(76, 76)
				for _, glyph in direct(medallion, "TextLabel") do sizeText(glyph, 28) end
				achievementArtwork(tile, medallion)
			end
			for _, label in direct(tile, "TextLabel") do
				if label.Position.Y.Offset == 60 then
					place(label, 0, 80, 125, 33); sizeText(label, 14); label.TextWrapped = true
				else
					place(label, 3, 114, 119, 48); sizeText(label, 10)
				end
			end
		end
	end
	if invite and group then
		local community = app.content:FindFirstChild("CommunityActions")
		if not community then community = Factory.ImageCard(app.content, UDim2.fromOffset(768, 193), UDim2.fromOffset(848, 722), "CommunityActions") end
		Skin.Skin(community, "settings", "CommunityPanelArt")
		ornament(community, "settings", "SettingsCommunityArt", 9, 16, 213, 162)
		displayText(caption(community, "CommunityTitle", "Community", 241, 8, 513, 40, 31), 31)
		local details = scroll(community, "CommunityBenefits", 241, 51, 513, 34)
		local cursor = 0
		for _, original in { invite, group } do
			for _, label in direct(original, "TextLabel") do
				if label.Name == "SectionBanner" then continue end
				label.Parent = details
				place(label, 0, cursor, 507, 50); sizeText(label, 17)
				cursor += 54
			end
		end
		local inviteButton, groupButton = direct(invite, "TextButton")[1], direct(group, "TextButton")[1]
		if inviteButton then
			inviteButton.Parent = community; place(inviteButton, 241, 92, 239, 85)
			sizeText(inviteButton, 23); Skin.Skin(inviteButton, "settings", "InviteFriendsArt")
			buttonIcon(inviteButton, "settings", "InvitePeople", 12, 28, 29, 29, 45)
		end
		if groupButton then
			groupButton.Parent = community; place(groupButton, 495, 92, 259, 85)
			sizeText(groupButton, 22); Skin.Skin(groupButton, "settings", "JoinCreatorGroupArt")
			buttonIcon(groupButton, "settings", "JoinPeople", 12, 28, 29, 29, 45)
		end
		invite.Visible = false; group.Visible = false
	end
end

local function relative(target: any, x: number, y: number, right: number, h: number)
	if not target then return end
	target.AutomaticSize = Enum.AutomaticSize.None
	target.AnchorPoint = Vector2.zero
	target.Position = UDim2.fromOffset(x, y)
	target.Size = UDim2.new(1, -x - right, 0, h)
end

local function compactSurface(target: any, slug: string, asset: string)
	if not target then return end
	Skin.Skin(target, slug, asset)
	local art, metric = target:FindFirstChild("RedesignArt"), Skin.Metric(slug, asset)
	if not art or not art:IsA("ImageLabel") or not metric then return end
	local rect = metric.rect
	if not rect then return end
	local w, h = rect.w or rect[3], rect.h or rect[4]
	if not w or not h or w < 64 or h < 64 then return end
	-- Compact cards can be several scroll pages tall. Slice their approved
	-- border instead of stretching its corners and glow with the content.
	local edge = math.min(30, math.floor(math.min(w, h) / 3))
	-- export_runtime_assets.py renders crops below 1000px at 2x. Roblox
	-- SliceCenter uses image pixels, while the layout metrics use SVG units.
	local rasterScale = if math.max(w, h) < 1000 then 2 else 1
	art.ScaleType = Enum.ScaleType.Slice
	art.SliceCenter = Rect.new(edge * rasterScale, edge * rasterScale, (w - edge) * rasterScale, (h - edge) * rasterScale)
	art.SliceScale = 1 / rasterScale
end

local function compactHeader(card: any, slug: string, asset: string?)
	if not card then return end
	local x = if asset then 88 else 16
	local banner = card:FindFirstChild("SectionBanner")
	if banner then
		relative(banner, x, 12, 16, 36)
		plainText(banner)
		banner.TextColor3 = C.Text
		banner.TextXAlignment = Enum.TextXAlignment.Left
		displayText(banner, 24)
	end
	if asset then ornament(card, slug, asset, 12, 4, 65, 58) end
end

local function compactText(root: Instance)
	for _, target in root:GetDescendants() do
		if target:GetAttribute("ForgeV2Decoration") then continue end
		if target:IsA("TextLabel") or target:IsA("TextBox") or target:IsA("TextButton") then
			if target:IsA("TextButton") and target.Text == "" then continue end
			sizeText(target, math.max(16, target.TextSize or 16))
			if target.Size.Y.Scale == 0 and target.Size.Y.Offset > 0 and target.Size.Y.Offset < 22 then
				target.Size = UDim2.new(target.Size.X.Scale, target.Size.X.Offset, 0, 22)
			end
		end
	end
end

local function compactPage(app: any, page: any, subtitleText: string?)
	local title, subtitle = named(app.content, "PageTitle"), named(app.content, "PageSubtitle")
	relative(title, 12, 4, 12, 40)
	displayText(title, 30)
	relative(subtitle, 14, 45, 14, 30)
	sizeText(subtitle, 16)
	if subtitle and subtitleText then subtitle.Text = subtitleText end
	if page then
		page.Position = UDim2.new(0.02, 0, 0, 82)
		page.Size = UDim2.new(0.96, 0, 1, -96)
		page.ScrollBarThickness = 6
	end
end

local function compactSettings(app: any): boolean
	local page = named(app.content, "SettingsScroll")
	if not page then return false end
	compactPage(app, page, "Your controls, preferences, and collection.")
	compactText(page)
	local mode, access, audio = named(page, "CreateMode"), named(page, "Accessibility"), named(page, "Audio")
	local loadout, achievements = named(page, "Loadout"), named(page, "Achievements")
	local invite, group = named(page, "InviteFriends"), named(page, "CreatorGroup")
	local panels = {
		{ mode, "CreationModePanelArt", "SettingsCreationArt" },
		{ access, "AccessibilityPanelArt", "SettingsAccessibilityArt" },
		{ audio, "AudioPanelArt", "SettingsAudioArt" },
		{ loadout, "EquippedItemsPanelArt" },
		{ achievements, "AchievementsPanelArt", "SettingsTrophyArt" },
		{ invite, "CommunityPanelArt", "SettingsCommunityArt" },
		{ group, "CommunityPanelArt", "SettingsCommunityArt" },
	}
	for _, panel in panels do
		if panel[1] then
			compactSurface(panel[1], "settings", panel[2])
			compactHeader(panel[1], "settings", panel[3])
		end
	end
	if mode then
		mode.Size = UDim2.new(1, 0, 0, 168)
		local headroom = mode.Parent:FindFirstChildOfClass("UIPadding")
		if headroom then headroom.PaddingTop = UDim.new(0, 0) end
		for _, label in direct(mode, "TextLabel") do
			if label.Name == "SectionBanner" then continue end
			if label.Position.Y.Offset == 32 then label.Visible = false; continue end
			label.Text = "Simple keeps the essentials. Advanced unlocks extra options."
			relative(label, 16, 62, 16, 44); sizeText(label, 16)
			label.TextWrapped = true; label.TextTruncate = Enum.TextTruncate.None
		end
		local simple = app.state.profile.settings.simpleMode ~= false
		for index, button in direct(mode, "TextButton") do
			button.Position = if index == 1 then UDim2.fromOffset(16, 112) else UDim2.new(0.5, 6, 0, 112)
			button.Size = UDim2.new(0.5, -22, 0, 48)
			button.Text = if index == 1 then "Simple" else "Advanced"
			displayText(button, 20)
			compactSurface(button, "settings", if index == 1 then "SimpleModeArt" else "AdvancedModeArt")
			buttonIcon(button, "settings", if index == 1 then "SimpleModeCube" else "AdvancedModeGear", 12, 11, 25, 25, 41)
			selection(button, (index == 1 and simple) or (index == 2 and not simple))
		end
	end
	if access then
		access.Size = UDim2.new(1, 0, 0, 520)
		for _, label in direct(access, "TextLabel") do
			if label.Name == "SectionBanner" then continue end
			local role = label:GetAttribute("ForgeCompactAccessRole")
			if not role then
				local y = label.Position.Y.Offset
				role = if y == 36 then "MotionTitle" elseif y == 58 then "MotionHelp"
					elseif y == 96 then "ContrastTitle" elseif y == 118 then "ContrastHelp"
					elseif y == 156 then "ScaleTitle" elseif y == 180 then "ScaleValue" else "KeyboardHelp"
				label:SetAttribute("ForgeCompactAccessRole", role)
			end
			if role == "MotionTitle" or role == "ContrastTitle" then
				relative(label, 16, if role == "MotionTitle" then 68 else 180, 122, 27); sizeText(label, 19)
			elseif role == "MotionHelp" or role == "ContrastHelp" then
				relative(label, 16, if role == "MotionHelp" then 118 else 230, 16, 42); sizeText(label, 16)
				label.TextWrapped = true
			elseif role == "ScaleTitle" then
				relative(label, 16, 298, 120, 29); sizeText(label, 19)
			elseif role == "ScaleValue" then
				label.Position = UDim2.new(1, -104, 0, 298); label.Size = UDim2.fromOffset(88, 29)
				sizeText(label, 18); label.TextXAlignment = Enum.TextXAlignment.Right
			else
				relative(label, 16, 375, 16, 132); sizeText(label, 16)
				label.TextWrapped = true; label.TextTruncate = Enum.TextTruncate.None
			end
		end
		for _, button in direct(access, "TextButton") do
			if button.Name == "Switch" then
				local contrast = button.Position.Y.Offset >= 100
				button.Position = UDim2.new(1, -96, 0, if contrast then 184 else 72)
				button.Size = UDim2.fromOffset(80, 40)
			else
				button.Position = UDim2.fromOffset(16, 336); button.Size = UDim2.new(1, -32, 0, 16)
			end
		end
	end
	if audio then
		audio.Size = UDim2.new(1, 0, 0, 174)
		for _, label in direct(audio, "TextLabel") do
			if label.Name == "SectionBanner" then continue end
			relative(label, 16, if label.Text == "Sound effects" then 77 else 110, 122, if label.Text == "Sound effects" then 27 else 46)
			sizeText(label, if label.Text == "Sound effects" then 20 else 16)
			label.TextWrapped = true
		end
		local button = direct(audio, "TextButton")[1]
		if button then button.Position = UDim2.new(1, -96, 0, 77); button.Size = UDim2.fromOffset(80, 40) end
	end
	for index, card in { invite, group } do
		if not card then continue end
		card.Size = UDim2.new(1, 0, 0, if index == 1 then 194 else 226)
		local labels = direct(card, "TextLabel")
		local body = 0
		for _, label in labels do
			if label.Name == "SectionBanner" then continue end
			body += 1
			relative(label, 16, if index == 1 then 64 elseif body == 1 then 64 else 98, 16, if index == 2 and body == 1 then 29 else 62)
			sizeText(label, if index == 2 and body == 1 then 19 else 16); label.TextWrapped = true
		end
		local button = direct(card, "TextButton")[1]
		if button then
			relative(button, 16, if index == 1 then 132 else 168, 16, 46); sizeText(button, 19)
			compactSurface(button, "settings", if index == 1 then "InviteFriendsArt" else "JoinCreatorGroupArt")
			buttonIcon(button, "settings", if index == 1 then "InvitePeople" else "JoinPeople", 14, 10, 26, 26, 46)
		end
	end
	if loadout then
		local rows = direct(loadout, "Frame")
		loadout.Size = UDim2.new(1, 0, 0, 62 + math.max(1, #rows) * 100 + 12)
		for index, row in rows do
			relative(row, 12, 62 + (index - 1) * 100, 12, 90)
			local image = direct(row, "ImageLabel")[1]
			place(image, 8, 14, 62, 62)
			for _, label in direct(row, "TextLabel") do
				local detail = label.Position.Y.Offset >= 25
				relative(label, 82, if detail then 46 else 13, 144, 28); sizeText(label, if detail then 16 else 18)
			end
			local remove = direct(row, "TextButton")[1]
			if remove then
				remove.Position = UDim2.new(1, -134, 0, 23); remove.Size = UDim2.fromOffset(126, 44); sizeText(remove, 18)
				compactSurface(remove, "settings", "RemoveEquippedArt")
				buttonIcon(remove, "settings", "RemoveTrashIcon", 8, 13, 18, 18, 30)
			end
		end
		for _, label in direct(loadout, "TextLabel") do
			if label.Name ~= "SectionBanner" then relative(label, 16, 62, 16, 84); sizeText(label, 17) end
		end
	end
	if achievements then
		for _, grid in direct(achievements, "Frame") do
			local layout = grid:FindFirstChildOfClass("UIGridLayout")
			if not layout then continue end
			local rows = math.ceil(#direct(grid, "Frame") / 2)
			relative(grid, 16, 66, 16, rows * 222)
			layout.CellSize = UDim2.new(0.5, -4, 0, 214); layout.CellPadding = UDim2.fromOffset(8, 8)
			achievements.Size = UDim2.new(1, 0, 0, 82 + rows * 222)
			for _, tile in direct(grid, "Frame") do
				achievementArtwork(tile, direct(tile, "Frame")[1])
				for _, label in direct(tile, "TextLabel") do
					local role = label:GetAttribute("ForgeCompactAchievementRole")
					if not role then role = if label.Position.Y.Offset == 60 then "Name" else "Requirement"; label:SetAttribute("ForgeCompactAchievementRole", role) end
					relative(label, 3, if role == "Name" then 70 else 116, 3, if role == "Name" then 40 else 86)
					sizeText(label, 16); label.TextWrapped = true; label.TextTruncate = Enum.TextTruncate.None
				end
			end
		end
	end
	return true
end

local function compactField(field: any, slug: string, asset: string)
	if not field then return end
	local name = "V2CompactField" .. field.Name
	local surface = field.Parent:FindFirstChild(name)
	if not surface then
		surface = Factory.New("Frame", { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = field.Parent })
		surface:SetAttribute("ForgeV2Decoration", true)
	end
	surface.Position, surface.Size = field.Position, field.Size
	surface.ZIndex = math.max(1, field.ZIndex - 1)
	compactSurface(surface, slug, asset)
	field.ZIndex = surface.ZIndex + 1
	fieldArtwork(field, surface)
end

local function compactCatalog(app: any): boolean
	local page = named(app.content, "AvatarLabWorkspace")
	if not page then return false end
	compactPage(app, page)
	compactText(page)
	for _, button in page:GetDescendants() do
		if button:IsA("TextButton") and button.Text ~= "" and not button:GetAttribute("ForgeV2Decoration")
			and button.Size.Y.Scale == 0 and button.Size.Y.Offset < 44 then
			button.Size = UDim2.new(button.Size.X.Scale, button.Size.X.Offset, 0, 44)
			local parent = button.Parent
			local layout = parent and parent:FindFirstChildOfClass("UIListLayout")
			if parent and parent:IsA("GuiObject") and layout and layout.FillDirection == Enum.FillDirection.Horizontal
				and parent.Size.Y.Scale == 0 then parent.Size = UDim2.new(parent.Size.X.Scale, parent.Size.X.Offset, 0, math.max(49, parent.Size.Y.Offset)) end
		end
	end
	local preview = named(page, "LookPreview")
	if preview then
		local stage = preview.Parent:FindFirstChild("V2CompactLookStage")
		if preview.Parent.Name == "V2CompactLookStage" then stage = preview.Parent end
		if not stage then
			stage = Factory.New("Frame", {
				Name = "V2CompactLookStage", Size = preview.Size, LayoutOrder = preview.LayoutOrder,
				BackgroundColor3 = C.PanelRaised, BorderSizePixel = 0, Parent = preview.Parent,
			})
			stage:SetAttribute("ForgeV2Decoration", true)
			preview.Parent = stage
		end
		compactSurface(stage, "avatar-lab", "AvatarStageArt")
		local heading = caption(stage, "CompactLookHeading", "Your avatar", 16, 8, 260, 28, 21)
		relative(heading, 16, 8, 16, 28)
		displayText(heading, 21)
		preview.Position = UDim2.fromOffset(12, 42); preview.Size = UDim2.new(1, -24, 1, -54)
		preview.BackgroundTransparency = if Theme.IsHighContrast then 0 else 1
		preview.ZIndex = stage.ZIndex + 2
	end
	local tabs = named(page, "CatalogTabs")
	if tabs then
		tabs.Size = UDim2.new(1, 0, 0, 49)
		for _, button in direct(tabs, "TextButton") do
			button.Size = UDim2.fromOffset(156, 44); sizeText(button, 17)
			compactSurface(button, "avatar-lab", "LabWorkspaceTabArt")
			buttonIcon(button, "avatar-lab", if button.Text == "More tools" then "LabMoreToolsIcon" else "LabWorkspaceTabIcon", 10, 10, 24, 24, 40)
		end
	end
	local searchRow = named(page, "CatalogSearchRow")
	if searchRow then
		searchRow.Size = UDim2.new(1, 0, 0, 48)
		local field, button = direct(searchRow, "TextBox")[1], direct(searchRow, "TextButton")[1]
		if field then field.Size = UDim2.new(1, -112, 0, 44); sizeText(field, 17); compactField(field, "avatar-lab", "CatalogSearchFieldArt") end
		if button then button.Size = UDim2.fromOffset(100, 44); sizeText(button, 18); compactSurface(button, "avatar-lab", "CatalogSearchArt") end
	end
	local categories = named(page, "CatalogCategories")
	if categories then
		categories.Size = UDim2.new(1, 0, 0, 49)
		local assets = { "CategoryHair", "CategoryHats", "CategoryFace", "CategoryShirts", "CategoryPants", "CategoryJackets", "CategoryBack" }
		for index, button in direct(categories, "TextButton") do
			if button:GetAttribute("ForgeCatalogFilter") then continue end
			button.Size = UDim2.fromOffset(if index == 6 then 118 else 105, 44); sizeText(button, 16)
			local asset = assets[index]
			if asset then compactSurface(button, "avatar-lab", asset .. "Art"); buttonIcon(button, "avatar-lab", asset .. "Icon", 7, 10, 24, 24, 34) end
		end
	end
	local lab = app.catalogWorkspace or {}
	local grid = named(page, "CatalogItemsGrid")
	if grid and lab.tab == "BROWSE" and not lab.showChallenge
		and not (app.state.makeoverState and app.state.makeoverState.active) then
		local columns = math.clamp(app.gridColumns or 2, 1, 2)
		fixedGrid(app, grid, columns, 338, 12)
		for index, card in direct(grid, "Frame") do
			if card.Name ~= "StyleItem" or named(card, "GuideTargetLabel") then continue end
			local prefix = "CatalogCard" .. tostring((index - 1) % 3 + 1)
			compactSurface(card, "avatar-lab", prefix .. "Art")
			local image = named(card, "CatalogItemThumbnail")
			relative(image, 8, 8, 8, 146)
			if image then image.BackgroundTransparency = 1; image.ScaleType = Enum.ScaleType.Fit end
			local title, price = named(card, "CatalogItemTitle"), named(card, "CatalogItemPrice")
			relative(title, 12, 162, 12, 28); displayText(title, 18)
			relative(price, 12, 195, 12, 42); sizeText(price, 16)
			local try, bookmark, buy = named(card, "CatalogTryOn"), named(card, "CatalogBookmark"), named(card, "CatalogBuy")
			relative(try, 12, 244, 12, 44); sizeText(try, 18)
			if try then compactSurface(try, "avatar-lab", prefix .. "TryOnArt"); buttonIcon(try, "avatar-lab", prefix .. "TryOnIcon", 12, 10, 24, 24, 41) end
			if bookmark then
				bookmark.Position = UDim2.new(1, -92, 0, 16); bookmark.Size = UDim2.fromOffset(80, 44); sizeText(bookmark, 16)
				compactSurface(bookmark, "avatar-lab", prefix .. "BookmarkArt"); buttonIcon(bookmark, "avatar-lab", prefix .. "BookmarkIcon", 6, 14, 16, 16, 25)
			end
			relative(buy, 12, 296, 12, 28); sizeText(buy, 16)
			if buy then buy.Text = "View in Roblox" end
		end
	end
	return true
end

local function compactGraphicCard(app: any, card: any, index: number)
	local prefix = "GraphicGalleryCard" .. tostring((index - 1) % 2 + 1)
	compactSurface(card, "avatar-graphics", prefix .. "Art")
	local image, link = direct(card, "ImageLabel")[1], direct(card, "TextBox")[1]
	relative(image, 10, 10, 10, 140)
	if image then image.ScaleType = Enum.ScaleType.Fit end
	for _, label in direct(card, "TextLabel") do
		local role = label:GetAttribute("ForgeCompactGraphicRole")
		if not role then role = if label.Position.Y.Offset == 148 then "Title" elseif label.Position.Y.Offset == 178 then "Kind" else "Link"; label:SetAttribute("ForgeCompactGraphicRole", role) end
		if role == "Link" then label.Visible = false
		else relative(label, 10, if role == "Title" then 160 else 204, 10, if role == "Title" then 38 else 24); sizeText(label, 16) end
	end
	local delete = direct(card, "TextButton")[1]
	if delete then
		delete.Position = UDim2.new(0.63, 4, 0, 244); delete.Size = UDim2.new(0.37, -14, 0, 48); sizeText(delete, 16)
		compactSurface(delete, "avatar-graphics", prefix .. "DeleteArt"); buttonIcon(delete, "avatar-graphics", prefix .. "DeleteIcon", 6, 15, 18, 18, 26)
	end
	if link then
		relative(link, 10, 244, 10, 48); link.Visible = false; link.ZIndex = card.ZIndex + 8
		local copy = card:FindFirstChild("CopyGraphicLink")
		if not copy then
			copy = Factory.ImageButton(card, "Copy link", UDim2.new(), UDim2.new())
			copy.Name = "CopyGraphicLink"; app:_BindButton(copy)
			copy.Activated:Connect(function()
				if not link.TextEditable then return end
				link.Visible = true; link:CaptureFocus(); link.CursorPosition = 1; link.SelectionStart = #link.Text + 1
				app:_Toast("info", "Full-resolution link selected. Copy it, then open it in your browser to save the image.")
			end)
			link.FocusLost:Connect(function() link.Visible = false end)
		end
		copy.Text = if link.TextEditable then "Copy link" else "No link"; copy.Active = link.TextEditable
		copy.Position = UDim2.fromOffset(10, 244); copy.Size = UDim2.new(0.63, -14, 0, 48); sizeText(copy, 16)
		compactSurface(copy, "avatar-graphics", prefix .. "CopyLinkArt"); buttonIcon(copy, "avatar-graphics", prefix .. "CopyLinkIcon", 8, 14, 20, 20, 34)
	end
end

local function compactGraphics(app: any): boolean
	local page = named(app.content, "AvatarGraphicsScroll")
	if not page then return false end
	compactPage(app, page, "Turn a prompt or your avatar into a picture you can keep.")
	page.Position = UDim2.new(0.02, 0, 0, 142); page.Size = UDim2.new(0.96, 0, 1, -156)
	compactText(page)
	for _, frame in direct(app.content, "Frame") do
		local buttons = direct(frame, "TextButton")
		if #buttons == 2 and buttons[1].Text == "Create" then
			frame.Position = UDim2.new(0.02, 0, 0, 82); frame.Size = UDim2.new(0.96, 0, 0, 49)
			for index, button in buttons do
				button.Size = UDim2.fromOffset(156, 44); sizeText(button, 18)
				compactSurface(button, "avatar-graphics", "GraphicsCreateTabArt")
				buttonIcon(button, "avatar-graphics", if index == 1 then "GraphicsCreateTabIcon" else "GraphicsDiscoverTabIcon", 11, 10, 24, 24, 40)
			end
		end
	end
	local composer, gallery = named(page, "GraphicComposer"), named(page, "GraphicsGallery")
	compactSurface(composer, "avatar-graphics", "GraphicsComposerArt")
	compactSurface(gallery, "avatar-graphics", "GraphicsGalleryArt")
	compactHeader(gallery, "avatar-graphics", "GraphicsGalleryIcon")
	local simple = app.state.profile.settings.simpleMode ~= false
	if composer and simple then
		local textMode = app.graphicMode == "TEXT"
		local promptY = if textMode then 146 else 344
		composer.Size = UDim2.new(1, 0, 0, promptY + 312)
		local sourceRow = nil
		for _, frame in direct(composer, "Frame") do if #direct(frame, "TextButton") == 2 then sourceRow = frame; break end end
		if sourceRow then
			relative(sourceRow, 16, 52, 16, 44)
			for index, button in direct(sourceRow, "TextButton") do
				button.Position = if index == 1 then UDim2.new() else UDim2.new(0.5, 5, 0, 0); button.Size = UDim2.new(0.5, -5, 1, 0)
				button.Text = if index == 1 then "My avatar" else "Text prompt"; sizeText(button, 18)
				compactSurface(button, "avatar-graphics", if index == 1 then "GraphicsMyAvatarSourceArt" else "GraphicsTextSourceArt")
				buttonIcon(button, "avatar-graphics", if index == 1 then "GraphicsMyAvatarSourceIcon" else "GraphicsTextSourceIcon", 9, 10, 24, 24, 38)
			end
		end
		local views = named(composer, "GraphicsChoiceOptions")
		if views then
			relative(views, 16, 143, 16, 49)
			local assets = { "GraphicsHeadshotView", "GraphicsBustView", "GraphicsFullBodyView" }
			for index, button in direct(views, "TextButton") do
				button.Size = UDim2.fromOffset(146, 44); sizeText(button, 18)
				compactSurface(button, "avatar-graphics", (assets[index] or assets[1]) .. "Art")
				buttonIcon(button, "avatar-graphics", (assets[index] or assets[1]) .. "Icon", 8, 10, 24, 24, 37)
			end
		end
		for _, image in direct(composer, "ImageLabel") do
			if string.find(image.Image, "rbxthumb://", 1, true) then place(image, 16, 207, 76, 76); image.ScaleType = Enum.ScaleType.Fit end
		end
		for _, label in direct(composer, "TextLabel") do
			local value = label.Text
			if value == "SOURCE" or value == "Choose a source" then label.Text = "Choose a source"; relative(label, 16, 16, 16, 28); displayText(label, 21)
			elseif string.find(value, "CHOOSE YOUR AVATAR VIEW", 1, true) then relative(label, 16, 110, 16, 27); sizeText(label, 19)
			elseif string.find(value, "DESCRIBE", 1, true) then relative(label, 16, promptY - 34, 16, 28); sizeText(label, 19)
			elseif string.match(value, "^%d+ / %d+") then relative(label, 16, promptY + 108, 16, 22); sizeText(label, 16); label.TextXAlignment = Enum.TextXAlignment.Right
			elseif string.find(value, "Fetched automatically", 1, true) then relative(label, 104, 208, 16, 72); sizeText(label, 16)
			elseif string.find(value, "Style and quality", 1, true) then relative(label, 16, 287, 16, 27); sizeText(label, 16)
			elseif string.find(value, "provider moderation", 1, true) then relative(label, 16, promptY + 254, 16, 48); sizeText(label, 16) end
		end
		local prompt = direct(composer, "TextBox")[1]
		relative(prompt, 16, promptY, 16, 100); sizeText(prompt, 18); compactField(prompt, "avatar-graphics", "GraphicsPromptFieldArt")
		for _, button in direct(composer, "TextButton") do
			if string.find(button.Text, "Advanced Mode", 1, true) then
				relative(button, 16, promptY + 140, 16, 42); sizeText(button, 17); compactSurface(button, "avatar-graphics", "GraphicsAdvancedOptionsArt")
			elseif string.find(button.Text, "Create", 1, true) then
				relative(button, 16, promptY + 194, 16, 48); sizeText(button, 20); compactSurface(button, "avatar-graphics", "GraphicsGenerateArt")
				buttonIcon(button, "avatar-graphics", "GraphicsGenerateIcon", 14, 10, 28, 28, 48)
			end
		end
	end
	if gallery and simple then
		for _, grid in direct(gallery, "Frame") do
			if not grid:FindFirstChildOfClass("UIGridLayout") then continue end
			local columns = math.clamp(app.gridColumns or 2, 1, 2)
			local rows = math.ceil(#direct(grid, "Frame") / columns)
			relative(grid, 12, 62, 12, rows * 322); fixedGrid(app, grid, columns, 310, 12)
			gallery.Size = UDim2.new(1, 0, 0, 74 + rows * 322)
			for index, card in direct(grid, "Frame") do if card.Name == "GraphicItem" then compactGraphicCard(app, card, index) end end
		end
		for _, label in direct(gallery, "TextLabel") do
			if label.Name ~= "SectionBanner" then relative(label, 16, 62, 16, 78); sizeText(label, 18); gallery.Size = UDim2.new(1, 0, 0, 156) end
		end
	end
	local activity = named(page, "GraphicActivity")
	if activity then compactSurface(activity, "avatar-graphics", "GraphicsActivityArt"); compactHeader(activity, "avatar-graphics") end
	return true
end

function Layouts.Compact(app: any): boolean
	if not app.content or not app.compact then return false end
	if app.activePage == "Settings" then return compactSettings(app)
	elseif app.activePage == "Avatar Lab" then return compactCatalog(app)
	elseif app.activePage == "Avatar Graphics" then return compactGraphics(app) end
	return false
end

function Layouts.Apply(app: any): boolean
	if not app.content or app.compact then return false end
	local simple = app.state and app.state.profile and app.state.profile.settings.simpleMode ~= false
	if app.activePage == "Avatar Lab" then
		if not simple or not named(app.content, "AvatarLabWorkspace") then return false end
		catalog(app)
		return true
	elseif app.activePage == "Avatar Graphics" then
		if not simple or app.graphicsTab == "DISCOVER" or not named(app.content, "GraphicComposer") then return false end
		graphics(app)
		return true
	elseif app.activePage == "Settings" then
		if not named(app.content, "SettingsScroll") then return false end
		settings(app)
		return true
	end
	return false
end

return Layouts
