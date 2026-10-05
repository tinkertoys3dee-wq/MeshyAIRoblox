--!strict

-- Measured v2 surfaces surround the existing catalog, image, and settings
-- controls. Player content and the original callbacks stay native.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Factory)
local Skin = require(script.Parent.RedesignSkin)

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
	if existing and existing:IsA("TextLabel") then return existing end
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

local function scroll(parent: Instance, name: string, x: number, y: number, w: number, h: number): ScrollingFrame
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("ScrollingFrame") then return existing end
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
	if not field or not surface or field:GetAttribute("ForgeV2FieldBound") then return end
	local art = surface:FindFirstChild("RedesignArt")
	if not art or not art:IsA("ImageLabel") then return end
	field:SetAttribute("ForgeV2FieldBound", true)
	local nativeAlpha = field.BackgroundTransparency
	local function refresh()
		field.BackgroundTransparency = if art.IsLoaded and not Theme.IsHighContrast then 1 else nativeAlpha
	end
	local changed = art:GetPropertyChangedSignal("IsLoaded"):Connect(refresh)
	field.Destroying:Connect(function() changed:Disconnect() end)
	refresh()
end

local function panelHeader(card: GuiObject, x: number, y: number, w: number, size: number)
	local banner = card:FindFirstChild("SectionBanner")
	if banner and banner:IsA("TextLabel") then
		place(banner, x, y, w, size + 8)
		plainText(banner)
		banner.TextXAlignment = Enum.TextXAlignment.Left
		sizeText(banner, size)
	end
end

local function pageHeader(app: any, titleText: string, subtitleText: string, x: number, y: number, w: number, size: number)
	local title, subtitle = named(app.content, "PageTitle"), named(app.content, "PageSubtitle")
	if title then
		title.Text = titleText
		place(title, x, y, w, size + 12)
		sizeText(title, size)
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
	place(title, 14, 211, 285, 31); sizeText(title, 22)
	place(price, 14, 246, 285, 45); sizeText(price, 17)
	local buy = named(card, "CatalogBuy")
	place(buy, 154, 267, 145, 26); sizeText(buy, 14)
	if price and buy then place(price, 14, 246, 285, 24); sizeText(price, 14) end
	local try, bookmark = named(card, "CatalogTryOn"), named(card, "CatalogBookmark")
	place(try, 12, 295, 287, 44); sizeText(try, 20)
	if try then Skin.Skin(try, "avatar-lab", prefix .. "TryOnArt") end
	place(bookmark, 12, 349, 287, 43); sizeText(bookmark, 18)
	if bookmark then Skin.Skin(bookmark, "avatar-lab", prefix .. "BookmarkArt") end
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
	local tabs = named(page, "CatalogTabs")
	if tabs then
		tabs.Parent = app.content
		place(tabs, 578, 243, 1030, 66)
		tabs.ScrollingDirection = Enum.ScrollingDirection.X
		tabs.ScrollBarThickness = 3
		local buttons = direct(tabs, "TextButton")
		local width = if #buttons > 3 then 196 else 298
		for _, button in buttons do
			button.Size = UDim2.fromOffset(width, 60)
			sizeText(button, 22)
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
		or (app.state.makeoverState and app.state.makeoverState.active == true) then
		for _, label in direct(stack, "TextLabel") do sizeText(label, 18) end
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
		local widths = { 98, 101, 98, 108, 106, 120, 99 }
		local types = { "HairAccessory", "Hat", "FaceAccessory", "Shirt", "Pants", "JacketAccessory", "BackAccessory" }
		for index, button in direct(categories, "TextButton") do
			button.LayoutOrder = index
			button.Size = UDim2.fromOffset(widths[index] or 100, 49)
			sizeText(button, 16)
			Skin.Skin(button, "avatar-lab", assets[index] or "CategoryHairArt")
			selection(button, app.catalogType == types[index])
		end
		if filters then
			for _, button in direct(filters, "TextButton") do
				button.Parent = categories; button.LayoutOrder = 20
				button.Size = UDim2.fromOffset(163, 49); sizeText(button, 16)
				Skin.Skin(button, "avatar-lab", "CategoryMorefiltersArt")
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
	panel.ClipsDescendants = true
	Skin.Skin(panel, "avatar-lab", "AvatarStageArt")
	local freeTryOn = panel:FindFirstChild("V2FreeTryOn")
	if freeTryOn and freeTryOn:IsA("GuiObject") then freeTryOn.Visible = false end
	local title = named(panel, "PreviewTitle")
	place(title, 18, 18, 290, 35); sizeText(title, 25)
	local viewport = app.avatarPreviewViewport
	place(viewport, 15, 69, 258, 427)
	viewport.BackgroundTransparency = 1
	local reset = named(panel, "ResetCamera")
	if reset then
		reset.Parent = panel
		place(reset, 336, 13, 207, 47); sizeText(reset, 20)
		reset.Text = "Reset camera"
		Skin.Skin(reset, "avatar-lab", "ResetAvatarCameraArt")
	end
	local divider = named(panel, "Divider")
	if divider then divider.Visible = false end
	ornament(panel, "avatar-lab", "WornItemsPanelArt", 284, 73, 263, 476)
	local heading = named(panel, "PreviewWornHeading")
	place(heading, 298, 85, 240, 30); sizeText(heading, 23)
	local list = app.avatarPreviewList
	place(list, 298, 124, 240, 335)
	local padding = list:FindFirstChildOfClass("UIPadding")
	if padding then padding.PaddingRight = UDim.new(0, 3) end
	sizeText(app.avatarPreviewEmptyLabel, 17)
	for _, row in direct(list, "Frame") do
		if row.Name ~= "TriedOnItemRow" then continue end
		row.Size = UDim2.new(1, 0, 0, 61)
		Skin.Skin(row, "avatar-lab", "WornRow1Art")
		local image = direct(row, "ImageLabel")[1]
		place(image, 4, 5, 52, 51)
		if image then image.BackgroundTransparency = 1 end
		for _, label in direct(row, "TextLabel") do
			local source = label.Position.Y.Offset >= 25
			place(label, 61, if source then 34 else 7, 139, if source then 18 else 27)
			sizeText(label, if source then 11 else 15)
		end
		local remove = direct(row, "TextButton")[1]
		if remove then
			place(remove, 200, 12, 33, 35)
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
		Skin.Skin(save, "avatar-lab", "SaveNewLookArt")
	end
	local save = panel:FindFirstChild("SaveNewLook")
	if save and save:IsA("GuiObject") then save.Visible = true end
	local drag = caption(panel, "AvatarDragHint", "Drag to rotate", 49, 507, 176, 37, 16)
	drag.Visible = true
	drag.TextColor3 = C.TextMuted
	return true
end

local function graphicsCard(app: any, card: GuiObject, index: number)
	local slot = (index - 1) % 2 + 1
	local prefix = "GraphicGalleryCard" .. tostring(slot)
	Skin.Skin(card, "avatar-graphics", prefix .. "Art")
	local image = direct(card, "ImageLabel")[1]
	place(image, 3, 7, 288, 378)
	if image then image.ScaleType = Enum.ScaleType.Fit end
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
	if delete then Skin.Skin(delete, "avatar-graphics", prefix .. "DeleteArt") end
	if link then
		local canCopy = link.TextEditable
		place(link, 13, 457, 174, 51)
		link.Visible = false
		link.ZIndex = card.ZIndex + 8
		link.TextSize = 10
		link:SetAttribute("ForgeSized", true)
		local copy = Factory.ImageButton(card, if canCopy then "Copy link" else "Link unavailable", UDim2.fromOffset(174, 51), UDim2.fromOffset(13, 457))
		copy.Name = "CopyGraphicLink"
		copy.Active = canCopy
		sizeText(copy, 17)
		Skin.Skin(copy, "avatar-graphics", prefix .. "CopyLinkArt")
		app:_BindButton(copy)
		copy.Activated:Connect(function()
			if not canCopy then return end
			link.Visible = true
			link:CaptureFocus()
			link.CursorPosition = 1
			link.SelectionStart = #link.Text + 1
			app:_Toast("info", "Full-resolution link selected. Copy it, then open it in your browser to save the image.")
		end)
		link.FocusLost:Connect(function() link.Visible = false end)
	end
end

local function graphicsActivity(app: any, activity: GuiObject)
	activity.Parent = app.content
	place(activity, 77, 775, 889, 116)
	Skin.Skin(activity, "avatar-graphics", "GraphicsActivityArt")
	panelHeader(activity, 54, 0, 650, 24)
	local rows = direct(activity, "Frame")
	local holder = scroll(activity, "LiveGraphicsJobs", 54, 36, 819, 79)
	Factory.List(holder, Enum.FillDirection.Vertical, 7)
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
	page.Visible = false
	place(composer, 61, 229, 918, 666)
	place(gallery, 995, 229, 624, 666)
	Skin.Skin(composer, "avatar-graphics", "GraphicsComposerArt")
	Skin.Skin(gallery, "avatar-graphics", "GraphicsGalleryArt")
	pageHeader(app, "Avatar Graphics", "Turn your look into something shareable.", 149, 243, 430, 53)
	ornament(app.content, "avatar-graphics", "GraphicsTitleSparkle1", 80, 250, 51, 51)
	ornament(composer, "avatar-graphics", "GraphicsFormArt", 16, 115, 887, 429)
	if tabs then
		place(tabs, 611, 250, 355, 63); removeLayout(tabs)
		tabs.ZIndex = 5
		for index, button in direct(tabs, "TextButton") do
			place(button, if index == 1 then 1 else 185, 3, if index == 1 then 174 else 170, 58)
			sizeText(button, if index == 1 then 23 else 20)
			Skin.Skin(button, "avatar-graphics", "GraphicsCreateTabArt")
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
		local buttons = direct(sourceRow, "TextButton")
		for index, button in buttons do
			place(button, if index == 1 then 0 else 292, 0, if index == 1 then 281 else 297, 46)
			sizeText(button, if index == 1 then 20 else 18)
			Skin.Skin(button, "avatar-graphics", if index == 1 then "GraphicsMyAvatarSourceArt" else "GraphicsTextSourceArt")
			selection(button, (index == 1 and not textMode) or (index == 2 and textMode))
		end
	end
	local prompt = direct(composer, "TextBox")[1]
	place(prompt, 300, 317, 592, 72); sizeText(prompt, 20)
	if prompt then
		prompt.ZIndex = composer.ZIndex + 3
	end
	local promptSurface = ornament(composer, "avatar-graphics", "GraphicsPromptFieldArt", 300, 317, 592, 72)
	fieldArtwork(prompt, promptSurface)
	for _, image in direct(composer, "ImageLabel") do
		if string.find(image.Image, "rbxthumb://", 1, true) then
			place(image, 29, 176, 253, 259)
			image.ScaleType = Enum.ScaleType.Fit
			image.BackgroundTransparency = 1
		end
	end
	if not textMode then ornament(composer, "avatar-graphics", "GraphicsSourceThumbnailArt", 29, 176, 253, 259) end
	for _, label in direct(composer, "TextLabel") do
		local text = label.Text
		if text == "SOURCE" then
			label.Text = "Choose a source"; place(label, 76, 124, 220, 33); sizeText(label, 21)
		elseif string.find(text, "CHOOSE YOUR AVATAR VIEW", 1, true) then
			label.Text = "Choose a view"; place(label, 349, 177, 510, 31); sizeText(label, 20)
		elseif string.find(text, "DESCRIBE", 1, true) then
			place(label, 349, 279, 530, 30); sizeText(label, 18)
		elseif string.match(text, "^%d+ / %d+") then
			place(label, 750, 356, 128, 25); sizeText(label, 15)
		elseif string.find(text, "provider moderation", 1, true) then
			place(label, 30, 510, 855, 34); sizeText(label, 13)
		elseif string.find(text, "Fetched automatically", 1, true) then
			place(label, 29, 442, 253, 35); sizeText(label, 12)
		elseif string.find(text, "Style and quality", 1, true) then
			place(label, 29, 479, 253, 20); sizeText(label, 11)
		end
	end
	local views = named(composer, "GraphicsChoiceOptions")
	if views then
		place(views, 301, 219, 589, 46)
		removeLayout(views)
		local assets = { "GraphicsHeadshotViewArt", "GraphicsBustViewArt", "GraphicsFullBodyViewArt" }
		local ids = { "HEADSHOT", "BUST", "FULL_BODY" }
		for index, button in direct(views, "TextButton") do
			place(button, (index - 1) * 200, 0, if index == 1 then 190 else 188, 46)
			sizeText(button, 20); Skin.Skin(button, "avatar-graphics", assets[index] or assets[1])
			selection(button, app.selectedAvatarView == ids[index])
		end
	end
	for _, button in direct(composer, "TextButton") do
		if string.find(button.Text, "Advanced Mode", 1, true) then
			place(button, 301, 399, 591, 36); sizeText(button, 17)
			Skin.Skin(button, "avatar-graphics", "GraphicsAdvancedOptionsArt")
		elseif string.find(button.Text, "Create", 1, true) then
			place(button, 26, 449, 868, 56); sizeText(button, 25)
			Skin.Skin(button, "avatar-graphics", "GraphicsGenerateArt")
		end
	end
	panelHeader(gallery, 89, 13, 330, 39)
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
	for _, label in direct(gallery, "TextLabel") do
		if label.Name ~= "SectionBanner" then place(label, 20, 100, 580, 90); sizeText(label, 21) end
	end
	if activity then
		graphicsActivity(app, activity)
	else
		local idle = Factory.New("Frame", { Name = "GraphicsIdleActivity", BackgroundTransparency = 1, Parent = app.content })
		place(idle, 77, 775, 889, 116)
		Skin.Skin(idle, "avatar-graphics", "GraphicsActivityArt")
		caption(idle, "IdleHeading", "In progress", 54, 0, 760, 36, 24)
		caption(idle, "IdleDescription", "No images generating. Your new graphics will appear in the gallery.", 54, 42, 780, 50, 20)
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
		place(button, if index == 1 then 257 else 491, 113, if index == 1 then 240 else 258, 71)
		sizeText(button, 22)
		Skin.Skin(button, "settings", if index == 1 then "SimpleModeArt" else "AdvancedModeArt")
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
	Factory.List(equipped, Enum.FillDirection.Vertical, 8)
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
		if remove then Skin.Skin(remove, "settings", "RemoveEquippedArt") end
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
		local community = Factory.ImageCard(app.content, UDim2.fromOffset(768, 193), UDim2.fromOffset(848, 722), "CommunityActions")
		Skin.Skin(community, "settings", "CommunityPanelArt")
		ornament(community, "settings", "SettingsCommunityArt", 9, 16, 213, 162)
		caption(community, "CommunityTitle", "Community", 241, 8, 513, 40, 31)
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
		end
		if groupButton then
			groupButton.Parent = community; place(groupButton, 495, 92, 259, 85)
			sizeText(groupButton, 22); Skin.Skin(groupButton, "settings", "JoinCreatorGroupArt")
		end
		invite.Visible = false; group.Visible = false
	end
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
