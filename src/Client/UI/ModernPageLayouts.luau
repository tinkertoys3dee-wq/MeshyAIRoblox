--!strict

-- Approved SVG proportions around the existing live controls. This module
-- changes presentation only: callbacks, text inputs, thumbnails, viewports,
-- purchase disclosures and overflow content keep their original instances.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Factory = require(script.Parent.Factory)
local RedesignSkin = require(script.Parent.RedesignSkin)
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local success, uploaded = pcall(function()
	local module = ReplicatedStorage:FindFirstChild("ScreenAssets")
	return if module then require(module) else {}
end)
local Assets: { [string]: any } = if success and type(uploaded) == "table" then uploaded else {}
local Layouts = {}

local DECORATION = { Decal = true, Gloss = true, Shade = true, DropShadow = true,
	ForgeScreenArt = true, PopScale = true, InteractionOutline = true }

local function named(root: Instance, name: string): any
	for _, child in root:GetDescendants() do
		if child.Name == name then return child end
	end
	return nil
end

local function direct(root: Instance, className: string): { any }
	local result = {}
	for _, child in root:GetChildren() do
		if child:IsA(className) and not DECORATION[child.Name] then table.insert(result, child) end
	end
	return result
end

local function place(target: GuiObject, x: number, y: number, w: number, h: number)
	target.AnchorPoint = Vector2.zero
	target.Position = UDim2.fromOffset(x, y)
	target.Size = UDim2.fromOffset(w, h)
end

local function textSize(target: any, size: number)
	target.TextSize = size
	target:SetAttribute("ForgeSized", true)
	local label = target:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then label:SetAttribute("ForgeSized", true) end
end

function Layouts.Skin(target: GuiObject, key: string): boolean
	-- Opaque child artwork would paint over native editable text/model pixels.
	if target:IsA("TextBox") or target:IsA("ViewportFrame") or target:IsA("ImageLabel") then return false end
	local id = Assets[key]
	if Theme.IsHighContrast or type(id) ~= "number" or id <= 0 then return false end
	local existing = target:FindFirstChild("ForgeScreenArt")
	if existing then return existing:GetAttribute("ForgeAssetKey") == key end
	local caption = Factory.LiftLabel(target)
	if caption and target:GetAttribute("ForgeSized") then caption:SetAttribute("ForgeSized", true) end
	local padded = string.find(key, "Panel", 1, true) ~= nil or string.find(key, "Button", 1, true) ~= nil
		or string.match(key, "Idea%d+$") ~= nil
	local layer = target.ZIndex or 1
	local art = Factory.New("ImageLabel", {
		Name = "ForgeScreenArt", Image = "rbxassetid://" .. tostring(id), Active = false,
		Position = if padded then UDim2.fromOffset(-8, -8) else UDim2.new(),
		Size = if padded then UDim2.new(1, 16, 1, 20) else UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, BorderSizePixel = 0, ImageTransparency = 0,
		ScaleType = if padded then Enum.ScaleType.Stretch else Enum.ScaleType.Fit,
		ZIndex = layer, Parent = target,
	})
	art:SetAttribute("ForgeAssetKey", key)
	local function raise(child: Instance)
		if child ~= art and child:IsA("GuiObject") and not DECORATION[child.Name] then
			(child :: GuiObject).ZIndex = math.max((child :: GuiObject).ZIndex or 1, layer + 1)
		end
	end
	for _, child in target:GetChildren() do raise(child) end
	local added = target.ChildAdded:Connect(raise)
	local oldDecal = target:FindFirstChild("Decal")
	local border = target:FindFirstChildOfClass("UIStroke")
	local authoredAlpha = if oldDecal then 0 else target.BackgroundTransparency
	local authoredBorder = if border then border.Transparency else 0
	local function refresh()
		local loaded = art.IsLoaded == true and not Theme.IsHighContrast
		art.ImageTransparency = if Theme.IsHighContrast then 1 else 0
		if oldDecal then oldDecal.Visible = not loaded end
		target.BackgroundTransparency = if loaded or (oldDecal and oldDecal.IsLoaded == true) then 1 else authoredAlpha
		if border then border.Transparency = if loaded then 1 else authoredBorder end
		for _, name in { "Gloss", "Shade" } do
			local overlay = target:FindFirstChild(name)
			if overlay then overlay.Visible = not loaded end
		end
	end
	art:GetPropertyChangedSignal("IsLoaded"):Connect(refresh)
	if oldDecal then oldDecal:GetPropertyChangedSignal("IsLoaded"):Connect(refresh) end
	target.Destroying:Connect(function() added:Disconnect() end)
	refresh()
	return true
end

local function decoration(parent: Instance, key: string, x: number, y: number, w: number, h: number)
	local name = "Illustration" .. key
	if parent:FindFirstChild(name) then return end
	local holder = Factory.New("Frame", { Name = name, BackgroundTransparency = 1,
		BorderSizePixel = 0, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Parent = parent })
	if not Layouts.Skin(holder, key) then holder:Destroy() end
end

local function header(card: GuiObject)
	local banner = card:FindFirstChild("SectionBanner")
	if not banner then return end
	banner.AnchorPoint = Vector2.zero
	banner.Position = UDim2.fromOffset(28, 16)
	banner.Size = UDim2.new(1, -56, 0, 32)
	banner.BackgroundTransparency = 1
	banner.TextXAlignment = Enum.TextXAlignment.Left
	textSize(banner, 23)
	local decal = banner:FindFirstChild("Decal")
	if decal then decal.Visible = false end
	local border = banner:FindFirstChildOfClass("UIStroke")
	if border then border.Transparency = 1 end
end

local function padding(root: Instance, amount: number)
	local pad = root:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, amount), UDim.new(0, amount)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, amount), UDim.new(0, amount)
	end
end

local function scrollBody(card: GuiObject, name: string, nodes: { any }, oldTop: number)
	local scroll = card:FindFirstChild(name)
	if scroll then return scroll end
	scroll = Factory.New("ScrollingFrame", { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(24, 54), Size = UDim2.new(1, -48, 1, -72),
		ScrollBarThickness = 4, ScrollBarImageColor3 = Theme.Colors.Cyan,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = card })
	for _, child in nodes do
		child.Parent = scroll
		child.Position = UDim2.new(child.Position.X.Scale, math.max(0, child.Position.X.Offset - 16),
			child.Position.Y.Scale, child.Position.Y.Offset - oldTop)
		if child.Size.X.Scale == 1 then child.Size = UDim2.new(1, -8, child.Size.Y.Scale, child.Size.Y.Offset) end
	end
	return scroll
end

local function play(app: any)
	local page = named(app.content, "PlayScroll")
	if not page then return end
	place(page, 31, 99, 1530, 516); padding(page, 0)
	local stack = direct(page, "Frame")[1]
	if not stack then return end
	stack.AutomaticSize = Enum.AutomaticSize.None
	stack.Size = UDim2.fromOffset(1530, 516)
	local list = stack:FindFirstChildOfClass("UIListLayout")
	if list then list.FillDirection = Enum.FillDirection.Horizontal; list.Padding = UDim.new(0, 21) end
	local cards = direct(stack, "Frame")
	table.sort(cards, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	for index, card in cards do
		card.Size = UDim2.fromOffset(496, 516)
		Layouts.Skin(card, "GamesChoice" .. index .. "Panel")
		local labels = direct(card, "TextLabel")
		table.sort(labels, function(a, b) return a.Position.Y.Offset < b.Position.Y.Offset end)
		if labels[1] then place(labels[1], 28, 27, 440, 42); textSize(labels[1], 29) end
		if labels[2] then
			place(labels[2], 28, 362, 440, 72); textSize(labels[2], 20)
			labels[2].TextWrapped = true
		end
		decoration(card, "GamesChoice" .. index .. "Artwork", 26, 108, 444, 226)
		local action = direct(card, "TextButton")[1]
		if action then
			place(action, 28, 432, 440, 58); textSize(action, 24)
			action.Text = ({ "Open Arcade  ›", "Open Runway  ›", "Enter Lounge  ›" })[index] or action.Text
			Layouts.Skin(action, "GamesChoice" .. index .. "OpenButton")
		end
	end
end

local function studio(app: any, simple: boolean)
	local collection, inspector = named(app.content, "Collection"), named(app.content, "Inspector")
	if not collection or not inspector then return end
	local top = if simple then 99 else 199
	local height = 615 - top
	place(collection, 31, top, 523, height); header(collection)
	place(inspector, 578, top, 983, height)
	Layouts.Skin(collection, "ItemsCollectionPanel"); Layouts.Skin(inspector, "ItemsInspectorPanel")
	local scroll = direct(collection, "ScrollingFrame")[1]
	if scroll then
		scroll.Position = UDim2.fromOffset(24, 63); scroll.Size = UDim2.new(1, -48, 1, -85); padding(scroll, 0)
		for _, row in scroll:GetDescendants() do
			if row:IsA("TextButton") and row.Text == "" and row.Size.Y.Offset == 82 then
				row.Size = UDim2.new(1, 0, 0, 78)
				for _, label in direct(row, "TextLabel") do
					if label.Position.X.Scale == 0 and label.Position.X.Offset >= 86 then
						textSize(label, if label.Position.Y.Offset < 35 then 19 else 14)
					end
				end
			end
		end
	end
	local preview, viewport
	for _, frame in direct(inspector, "Frame") do
		local candidate = frame:FindFirstChildOfClass("ViewportFrame")
		if candidate then preview, viewport = frame, candidate; break end
	end
	if not preview then return end
	preview.Position = UDim2.fromOffset(12, 14)
	preview.Size = UDim2.new(1, -24, 0, if simple then 340 else 248)
	viewport.Position = UDim2.fromOffset(16, 100)
	viewport.Size = UDim2.new(1, -32, 0, if simple then 242 else 142)
	viewport.BackgroundColor3 = Theme.Colors.Ink
	local title = direct(preview, "TextLabel")[1]
	if title then textSize(title, 27) end
	local bodyScroll = direct(inspector, "ScrollingFrame")[1]
	if bodyScroll then
		local y = if simple then 364 else 274
		bodyScroll.Position = UDim2.fromOffset(6, y); bodyScroll.Size = UDim2.new(1, -12, 1, -y - 12)
		if simple then
			local body = direct(bodyScroll, "Frame")[1]
			if body then
				body.Size = UDim2.new(1, -8, 0, 154)
				for _, child in direct(body, "GuiObject") do
					if child:IsA("TextButton") then
						if string.find(child.Text, "Advanced Mode", 1, true) then
							child.Parent = app.content; place(child, 760, 619, 790, 26); textSize(child, 16)
						else
							child.Position = UDim2.new(child.Position.X.Scale, child.Position.X.Offset, 0, 62)
							textSize(child, 20)
						end
					elseif child:IsA("TextLabel") then
						child.Position = UDim2.fromOffset(16, 113); textSize(child, 13)
					elseif child:IsA("Frame") and child.Position.Y.Offset == 8 then
						child.Position = UDim2.fromOffset(16, 0); child.Size = UDim2.new(1, -32, 0, 52)
					end
				end
			end
		end
	end
end

local function marketplace(app: any, simple: boolean)
	local content = app.content
	local title = content:FindFirstChild("PageTitle")
	if title then title.Text = "Market" end
	local grid
	for _, child in direct(content, "ScrollingFrame") do
		if child:FindFirstChildOfClass("UIGridLayout") then grid = child; break end
	end
	for _, tools in direct(content, "Frame") do
		local field = tools:FindFirstChildOfClass("TextBox")
		if field and tools.Position.Y.Offset >= 90 then
			local oldY = tools.Position.Y.Offset
			place(tools, 31, if oldY > 96 then oldY else 99, 1041, 54)
			field.Size = UDim2.new(1, if simple then -183 else -328, 0, 54); textSize(field, 20)
			for _, button in direct(tools, "TextButton") do
				if button.Text == "Search" then
					place(button, if simple then 874 else 729, 0, 167, 54); textSize(button, 21)
				elseif not simple then place(button, 911, 0, 130, 54) end
			end
		end
	end
	if not grid then return end
	local hasGuide = named(content, "FirstLookGuide") ~= nil
	if simple and not hasGuide then
		place(grid, 31, 207, 1041, 408)
		for _, button in direct(content, "TextButton") do
			if string.find(button.Text, "Advanced Mode", 1, true) then place(button, 31, 619, 1041, 26); textSize(button, 16) end
		end
	end
	padding(grid, 0)
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	layout.CellSize = UDim2.new(1/3, -14, 0, 408); layout.CellPadding = UDim2.fromOffset(21, 20)
	for _, card in direct(grid, "Frame") do
		if card.Name ~= "CommunityItem" then continue end
		Layouts.Skin(card, "MarketCard1Panel")
		local image = direct(card, "ImageLabel")[1]
		if image then place(image, 16, 16, 301, 186) end
		for _, label in direct(card, "TextLabel") do
			if label.Position.Y.Offset == 194 then
				place(label, 16, 213, 301, 29); textSize(label, 21)
			elseif label.Position.Y.Offset == 221 then
				place(label, 16, 245, 301, 24); textSize(label, 16)
			end
		end
		local expand = card:FindFirstChild("ExpandHit")
		if expand then expand.Size = UDim2.new(1, 0, 0, 278) end
		for _, button in direct(card, "TextButton") do
			if button.Name == "ExpandHit" then continue end
			if button.Position.Y.Offset == 250 then
				button.Position = UDim2.new(button.Position.X.Scale, if simple then 16 else button.Position.X.Offset, 0, 282)
				button.Size = UDim2.new(if simple then 1 else button.Size.X.Scale, if simple then -32 else button.Size.X.Offset, 0, 49)
				textSize(button, 20)
			elseif button.Position.Y.Offset == 298 then
				button.Position = UDim2.new(button.Position.X.Scale, button.Position.X.Offset, 0, 345)
				button.Size = UDim2.new(button.Size.X.Scale, button.Size.X.Offset, 0, 42); textSize(button, 18)
			end
		end
	end
end

local function threeColumns(grid: GuiObject, height: number)
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	if not layout then return end
	local function apply()
		if math.abs(layout.CellSize.X.Scale - 1/3) > .0001 or layout.CellSize.X.Offset ~= -14
			or layout.CellSize.Y.Offset ~= height then
			layout.CellSize = UDim2.new(1/3, -14, 0, height)
		end
		layout.CellPadding = UDim2.fromOffset(21, 20)
	end
	apply()
	if grid:GetAttribute("ForgeGridBound") then return end
	grid:SetAttribute("ForgeGridBound", true)
	local resized = layout:GetPropertyChangedSignal("CellSize"):Connect(apply)
	grid.Destroying:Connect(function() resized:Disconnect() end)
end

local function catalog(app: any, simple: boolean)
	local page = named(app.content, "AvatarLabWorkspace")
	if not page then return end
	place(page, 31, 99, 1041, 516); padding(page, 0)
	local stack = direct(page, "Frame")[1]
	if not stack then return end
	stack.Size = UDim2.new(1, -6, 0, 0)
	local subtitle = app.content:FindFirstChild("PageSubtitle")
	local guided = subtitle and string.find(subtitle.Text, "Follow the gold glow", 1, true) ~= nil
	local lab = app.catalogWorkspace or {}
	if simple and not guided then
		for _, row in direct(stack, "ScrollingFrame") do
			if row.LayoutOrder == -10 and app.editorHeader then
				row.Parent = app.editorHeader; place(row, 1142, 263, 465, 50)
				for _, button in direct(row, "TextButton") do
					button.Size = UDim2.fromOffset(if string.find(button.Text, "More", 1, true) then 82 else 140, 44)
					textSize(button, 18)
				end
			elseif row.LayoutOrder == -8 and app.editorHeader and lab.showChallenge ~= true then
				row.Parent = app.editorHeader; place(row, 80, 866, 1038, 30)
				for _, button in direct(row, "TextButton") do
					button.Size = UDim2.fromOffset(395, 28); textSize(button, 16)
				end
			end
		end
		local categories = named(stack, "CatalogCategories")
		if categories then
			local categoryButtons = direct(categories, "TextButton")
			for index, button in categoryButtons do
				button.LayoutOrder = index; button.Size = UDim2.fromOffset(110, 42); textSize(button, 17)
			end
			for _, row in direct(stack, "ScrollingFrame") do
				if row.LayoutOrder == 3 then
					for _, button in direct(row, "TextButton") do
						button.Parent = categories; button.LayoutOrder = 20; button.Size = UDim2.fromOffset(160, 42); textSize(button, 17)
					end
					row.Visible = false
				end
			end
		end
	end
	for _, row in direct(stack, "Frame") do
		local field = row:FindFirstChildOfClass("TextBox")
		if field and row.LayoutOrder == 1 then
			row.Size = UDim2.new(1, 0, 0, 54); field.Size = UDim2.new(1, -183, 0, 54); textSize(field, 20)
			local search = direct(row, "TextButton")[1]
			if search then
				search.Position = UDim2.new(1, -167, 0, 0); search.Size = UDim2.fromOffset(167, 54); textSize(search, 21)
			end
		end
	end
	for _, label in direct(stack, "TextLabel") do
		if label.LayoutOrder == 10 then label.Size = UDim2.new(1, 0, 0, 28); textSize(label, 16) end
	end
	if guided then return end
	for _, frame in direct(stack, "Frame") do
		if frame:FindFirstChildOfClass("UIGridLayout") then
			threeColumns(frame, 344)
			for _, card in direct(frame, "Frame") do
				if card.Name ~= "StyleItem" then continue end
				Layouts.Skin(card, "AvatarLabCard1Panel")
				local image = direct(card, "ImageLabel")[1]
				if image then image.Position = UDim2.fromOffset(16, 16); image.Size = UDim2.new(1, -32, 0, 147) end
				for _, label in direct(card, "TextLabel") do
					if label.Position.Y.Offset == 170 then
						label.Position = UDim2.fromOffset(16, 176); textSize(label, 21)
					elseif label.Position.Y.Offset == 198 then
						label.Position = UDim2.fromOffset(16, 207); label.Size = UDim2.new(1, -32, 0, 36); textSize(label, 15)
					end
				end
				for _, button in direct(card, "TextButton") do
					if button.Position.Y.Offset == 236 then
						button.Position = UDim2.fromOffset(16, 250); button.Size = UDim2.new(1, -32, 0, 48); textSize(button, 20)
					elseif button.Position.Y.Offset == 282 then
						button.Position = UDim2.fromOffset(16, 305); button.Size = UDim2.new(1, -32, 0, 30); textSize(button, 15)
					end
				end
			end
		end
	end
end

local function compactGraphicsDiscover(app: any, simple: boolean)
	local content = app.content
	local page = content:FindFirstChild("GraphicsDiscoverScroll")
	if not page then
		local children = direct(content, "GuiObject")
		page = Factory.New("ScrollingFrame", {
			Name = "GraphicsDiscoverScroll", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0),
			BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ZIndex = 3,
			ScrollBarImageColor3 = Theme.Colors.Violet, AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y, Parent = content,
		})
		for _, child in children do
			if child.Name == "FlourishDivider" then child.Visible = false else child.Parent = page end
		end
	end
	local title, subtitle = page:FindFirstChild("PageTitle"), page:FindFirstChild("PageSubtitle")
	if title then
		title.Position = UDim2.fromOffset(16, 8); title.Size = UDim2.new(1, -112, 0, 42)
		textSize(title, 27); title.TextTruncate = Enum.TextTruncate.AtEnd
	end
	if subtitle then
		subtitle.Text = "Explore creator art. Tap a poster to open it."
		subtitle.Position = UDim2.fromOffset(16, 58); subtitle.Size = UDim2.new(1, -32, 0, 42)
		textSize(subtitle, 16); subtitle.TextWrapped = true
	end
	local grid
	for _, child in direct(page, "ScrollingFrame") do
		if child:FindFirstChildOfClass("UIGridLayout") then grid = child; break end
	end
	for _, row in direct(page, "Frame") do
		local buttons = direct(row, "TextButton")
		if #buttons == 2 and buttons[1].Text == "Create" then
			row.Position = UDim2.fromOffset(16, 112); row.Size = UDim2.new(1, -32, 0, 48)
			for _, button in buttons do button.Size = UDim2.new(.5, -4, 0, 46); textSize(button, 18) end
		elseif row:FindFirstChildOfClass("TextBox") then
			row.Position = UDim2.fromOffset(16, 176); row.Size = UDim2.new(1, -32, 0, 106)
			local field = row:FindFirstChildOfClass("TextBox")
			field.Size = UDim2.new(1, 0, 0, 48); textSize(field, 18)
			for _, button in buttons do
				if button.Text == "Search" then
					button.Position = UDim2.fromOffset(0, 58); button.Size = UDim2.new(1, 0, 0, 46); textSize(button, 19)
				end
			end
		elseif not row:GetAttribute("ForgeV2Decoration") then
			row.Position = UDim2.fromOffset(16, 176); row.Size = UDim2.new(1, -32, 0, 220)
			for _, label in direct(row, "TextLabel") do textSize(label, if label.Position.Y.Offset < 60 then 22 else 17) end
		end
	end
	local filters = page:FindFirstChild("GraphicsMarketplaceFilters")
	if filters then
		filters.Position = UDim2.fromOffset(16, 294); filters.Size = UDim2.new(1, -32, 0, 54)
		for _, chip in direct(filters, "TextButton") do
			chip.Size = UDim2.fromOffset(if string.find(chip.Text, "Simple", 1, true) then 169 else 129, 46); textSize(chip, 17)
		end
	end
	for _, button in direct(page, "TextButton") do
		if string.find(button.Text, "Advanced Mode", 1, true) then
			button.Position = UDim2.fromOffset(16, 294); button.Size = UDim2.new(1, -32, 0, 60)
			textSize(button, 17); button.TextWrapped = true
		elseif button.Text == "HOME" then
			button.Position = UDim2.new(1, -88, 0, 8); button.Size = UDim2.fromOffset(72, 40); textSize(button, 16)
		end
	end
	for _, label in direct(page, "TextLabel") do
		if string.find(label.Text, "Loading trending", 1, true) then
			label.Position = UDim2.fromOffset(16, 372); label.Size = UDim2.new(1, -32, 0, 72); textSize(label, 21)
		end
	end
	if not grid then return end
	local columns = math.clamp(app.gridColumns or 1, 1, 2)
	local cards = direct(grid, "Frame")
	local rows = math.max(1, math.ceil(#cards / columns))
	local cardHeight = if simple then 344 else 398
	grid.Position = UDim2.fromOffset(16, 372); grid.Size = UDim2.new(1, -32, 0, rows * (cardHeight + 16))
	grid.AutomaticCanvasSize = Enum.AutomaticSize.None; grid.CanvasSize = UDim2.new()
	grid.ScrollingEnabled = false; grid.ScrollBarThickness = 0; padding(grid, 0)
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	local function cellSize()
		layout.CellSize = UDim2.new(1 / columns, -16 * (columns - 1) / columns, 0, cardHeight)
		layout.CellPadding = UDim2.fromOffset(16, 16)
	end
	cellSize()
	if not grid:GetAttribute("ForgeCompactDiscoverGridBound") then
		grid:SetAttribute("ForgeCompactDiscoverGridBound", true)
		local resized = layout:GetPropertyChangedSignal("CellSize"):Connect(function()
			if layout.CellSize.X.Scale ~= 1 / columns or layout.CellSize.X.Offset ~= -16 * (columns - 1) / columns
				or layout.CellSize.Y.Offset ~= cardHeight then cellSize() end
		end)
		grid.Destroying:Connect(function() resized:Disconnect() end)
	end
	for _, card in cards do
		if card.Name ~= "CommunityGraphic" then continue end
		card.ZIndex = 4; RedesignSkin.Skin(card, "avatar-graphics", "GraphicsFormArt")
		local image = direct(card, "ImageLabel")[1]
		if image then image.Position = UDim2.fromOffset(12, 12); image.Size = UDim2.new(1, -24, 0, 180); image.ScaleType = Enum.ScaleType.Fit; image.ZIndex = 7 end
		for _, label in direct(card, "TextLabel") do
			local creator = string.sub(label.Text, 1, 4) == "by @"
			local price = string.sub(label.Text, 1, 3) == "R$ "
			label.Name = if creator then "GraphicsDiscoverCreator" elseif price then "GraphicsDiscoverPrice" else "GraphicsDiscoverTitle"
			label.Position = UDim2.fromOffset(12, if creator then 255 elseif price then 24 else 202)
			label.Size = if price then UDim2.fromOffset(100, 29) else UDim2.new(1, -24, 0, if creator then 26 else 48)
			textSize(label, if creator then 16 elseif price then 17 else 20); label.ZIndex = 7
			if price then local caption = Factory.LiftLabel(label); if caption then caption.ZIndex = 8 end end
		end
		local expand = card:FindFirstChild("ExpandHit")
		if expand then expand.Size = UDim2.new(1, 0, 0, 284); expand.ZIndex = 8 end
		for _, button in direct(card, "TextButton") do
			if button.Name == "ExpandHit" then continue end
			local buy = button.Text == "Buy copy" or button.Text == "Not for sale"
			if buy then
				button.Name = "GraphicsDiscoverBuy"
				button.Position = UDim2.fromOffset(12, 289); button.Size = UDim2.new(1, -24, 0, 44); textSize(button, 18)
			else
				local favorite = button.Position.X.Scale == .5
				button.Name = if favorite then "GraphicsDiscoverFavorite" else "GraphicsDiscoverLike"
				button.Position = UDim2.new(if favorite then .5 else 0, if favorite then 6 else 12, 0, if simple then 289 else 345)
				button.Size = UDim2.new(.5, -18, 0, 44); textSize(button, 18)
				for _, glyph in direct(button, "TextLabel") do
					if glyph.Name ~= "Label" then place(glyph, 8, 0, 24, 44); textSize(glyph, 23); glyph.ZIndex = 11 end
				end
			end
			button.ZIndex = 9
			local caption = Factory.LiftLabel(button)
			if caption then caption.ZIndex = 10 end
		end
	end
	for _, label in direct(grid, "TextLabel") do label.Size = UDim2.new(1, -16, 0, 180); textSize(label, 21) end
end

local function graphicsDiscover(app: any, simple: boolean)
	local content = app.content
	local title, subtitle = content:FindFirstChild("PageTitle"), content:FindFirstChild("PageSubtitle")
	if title then
		place(title, 96, 4, 1000, 54); textSize(title, 40); title.Font = Theme.Fonts.Black
	end
	if subtitle then
		subtitle.Text = "Explore pictures shared by creators. Open a poster to see the full artwork."
		place(subtitle, 31, 63, 1180, 29); textSize(subtitle, 19)
	end
	RedesignSkin.Decoration(content, "avatar-graphics", "GraphicsTitleSparkle1", 35, 7, 49, 49)
	local grid
	for _, child in direct(content, "ScrollingFrame") do
		if child:FindFirstChildOfClass("UIGridLayout") then grid = child; break end
	end
	for _, row in direct(content, "Frame") do
		local buttons = direct(row, "TextButton")
		if #buttons == 2 and buttons[1].Text == "Create" then
			place(row, 1194, 10, 367, 54)
			for index, button in buttons do
				button.Size = UDim2.fromOffset(179, 54); textSize(button, 22)
				button.Font = Theme.Fonts.Bold; button.ZIndex = 5
				if index == 2 then RedesignSkin.Skin(button, "avatar-graphics", "GraphicsCreateTabArt") end
				local caption = Factory.LiftLabel(button)
				if caption then
					place(caption, 49, 0, 122, 54); caption.TextXAlignment = Enum.TextXAlignment.Left; caption.ZIndex = 7
				end
				RedesignSkin.Decoration(button, "avatar-graphics", if index == 1 then "GraphicsCreateTabIcon" else "GraphicsDiscoverTabIcon", 14, 12, 30, 30)
			end
		elseif row:FindFirstChildOfClass("TextBox") then
			place(row, 31, 105, 1530, 54)
			local field = row:FindFirstChildOfClass("TextBox")
			field.Size = UDim2.new(1, -183, 0, 54); textSize(field, 22)
			for _, button in buttons do
				if button.Text == "Search" then
					place(button, 1363, 0, 167, 54); textSize(button, 22)
				end
			end
		end
	end
	local filters = content:FindFirstChild("GraphicsMarketplaceFilters")
	if filters then
		place(filters, 31, 170, 1530, 46)
		for _, chip in direct(filters, "TextButton") do
			chip.Size = UDim2.fromOffset(if string.find(chip.Text, "Simple", 1, true) then 183 else 142, 42)
			textSize(chip, 18)
		end
	end
	for _, button in direct(content, "TextButton") do
		if string.find(button.Text, "Advanced Mode", 1, true) then
			place(button, 853, 172, 708, 37); textSize(button, 18)
		end
	end
	if not grid then
		for _, label in direct(content, "TextLabel") do
			if string.find(label.Text, "Loading trending", 1, true) then
				place(label, 31, 230, 1530, 72); textSize(label, 24)
			end
		end
		return
	end
	if simple and not content:FindFirstChild("GraphicsDiscoverHeading") then
		local heading = Factory.Label(content, "CREATOR GALLERY", UDim2.fromOffset(730, 34), {
			Name = "GraphicsDiscoverHeading", Position = UDim2.fromOffset(31, 174),
			Font = Theme.Fonts.Bold, TextSize = 22, Color = Theme.Colors.Gold,
		})
		heading.Name = "GraphicsDiscoverHeading"; heading:SetAttribute("ForgeSized", true)
	end
	local gridTop = if simple then 222 else 230
	place(grid, 31, gridTop, 1530, 629 - gridTop); padding(grid, 0)
	grid.ScrollBarThickness = 6; grid.ScrollBarImageColor3 = Theme.Colors.Violet
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	local function columns()
		layout.CellSize = UDim2.new(.5, -12, 0, 362)
		layout.CellPadding = UDim2.fromOffset(24, 20)
	end
	columns()
	if not grid:GetAttribute("ForgeGraphicsDiscoverGridBound") then
		grid:SetAttribute("ForgeGraphicsDiscoverGridBound", true)
		local resized = layout:GetPropertyChangedSignal("CellSize"):Connect(function()
			if layout.CellSize.X.Scale ~= .5 or layout.CellSize.X.Offset ~= -12 or layout.CellSize.Y.Offset ~= 362 then columns() end
		end)
		grid.Destroying:Connect(function() resized:Disconnect() end)
	end
	for _, card in direct(grid, "Frame") do
		if card.Name ~= "CommunityGraphic" then continue end
		card.ZIndex = 4
		RedesignSkin.Skin(card, "avatar-graphics", "GraphicsFormArt")
		RedesignSkin.Decoration(card, "avatar-graphics", "GraphicsSourceThumbnailArt", 14, 14, 334, 334)
		local image = direct(card, "ImageLabel")[1]
		if image then
			place(image, 22, 22, 318, 318)
			image.ScaleType = Enum.ScaleType.Fit; image.BackgroundTransparency = 1; image.ZIndex = 7
		end
		for _, label in direct(card, "TextLabel") do
			if label.Name == "GraphicsDiscoverViewHint" then continue end
			local creator = label.Name == "GraphicsDiscoverCreator" or string.sub(label.Text, 1, 4) == "by @"
			local price = label.Name == "GraphicsDiscoverPrice" or string.sub(label.Text, 1, 3) == "R$ "
			label.Name = if creator then "GraphicsDiscoverCreator" elseif price then "GraphicsDiscoverPrice" else "GraphicsDiscoverTitle"
			label.Position = UDim2.fromOffset(372, if creator then 112 elseif price then 159 else 23)
			label.Size = if price then UDim2.fromOffset(145, 32) else UDim2.new(1, -395, 0, if creator then 29 else 76)
			textSize(label, if creator then 20 elseif price then 18 else 26)
			label.Font = if creator then Theme.Fonts.Medium else Theme.Fonts.Bold
			label.TextWrapped = not creator and not price; label.ZIndex = 7
		end
		local expand = card:FindFirstChild("ExpandHit")
		if expand then expand.Size = UDim2.fromScale(1, 1); expand.ZIndex = 8 end
		if not card:FindFirstChild("GraphicsDiscoverViewHint") then
			local hint = Factory.Label(card, "OPEN ARTWORK  ↗", UDim2.new(1, -395, 0, 30), {
				Position = UDim2.fromOffset(372, if simple then 184 else 234), Font = Theme.Fonts.Bold,
				TextSize = 19, Color = Theme.Colors.Cyan, ZIndex = 7,
			})
			hint.Name = "GraphicsDiscoverViewHint"; hint:SetAttribute("ForgeSized", true)
		end
		for _, button in direct(card, "TextButton") do
			if button.Name == "ExpandHit" then continue end
			local buy = button.Name == "GraphicsDiscoverBuy" or button.Text == "Buy copy" or button.Text == "Not for sale"
			if buy then
				button.Name = "GraphicsDiscoverBuy"; button.Position = UDim2.fromOffset(372, 192)
				button.Size = UDim2.new(1, -395, 0, 40); textSize(button, 20)
			else
				local favorite = button.Name == "GraphicsDiscoverFavorite" or button.Position.X.Scale == .5
				button.Name = if favorite then "GraphicsDiscoverFavorite" else "GraphicsDiscoverLike"
				button.Position = UDim2.new(.5, if favorite then 184 else -2, 0, 289)
				button.Size = UDim2.new(.25, -29, 0, 48); textSize(button, 21)
				for _, glyph in direct(button, "TextLabel") do
					if glyph.Name ~= "Label" then place(glyph, 12, 0, 30, 48); textSize(glyph, 26); glyph.ZIndex = 11 end
				end
			end
			button.ZIndex = 9
			local caption = Factory.LiftLabel(button)
			if caption then caption.ZIndex = 10 end
		end
	end
	for _, label in direct(grid, "TextLabel") do
		label.Size = UDim2.fromOffset(742, 180); textSize(label, 24)
	end
end

local function graphics(app: any, simple: boolean)
	if app.graphicsTab == "DISCOVER" then graphicsDiscover(app, simple); return end
	local page = named(app.content, "AvatarGraphicsScroll")
	local composer = named(app.content, "GraphicComposer")
	local gallery = named(app.content, "GraphicsGallery")
	if not page or not composer or not gallery then return end
	place(page, 31, 99, 1530, 516); padding(page, 0)
	local left, right = composer.Parent, gallery.Parent
	local columns = left.Parent
	columns.Size = UDim2.new(1, 0, 0, 0)
	local list = columns:FindFirstChildOfClass("UIListLayout")
	if list then list.Padding = UDim.new(0, 25) end
	left.Size = UDim2.new(0, 976, 0, 0); right.Size = UDim2.new(0, 529, 0, 0)
	padding(right, 0)
	for _, tabs in direct(app.content, "Frame") do
		local buttons = direct(tabs, "TextButton")
		if #buttons == 2 and buttons[1].Text == "Create" and app.editorHeader then
			tabs.Parent = app.editorHeader; place(tabs, 1271, 263, 336, 50)
			for _, button in buttons do button.Size = UDim2.fromOffset(164, 50); textSize(button, 20) end
		end
	end
	Layouts.Skin(composer, "GraphicsComposerPanel")
	if simple and not composer:GetAttribute("ForgeComposerPlaced") then
		composer:SetAttribute("ForgeComposerPlaced", true)
		local oldHeight = composer.Size.Y.Offset
		local factor = 516 / math.max(1, oldHeight)
		composer.Size = UDim2.new(1, 0, 0, 516)
		for _, child in direct(composer, "GuiObject") do
			if child.Position.X.Scale == 0 and child.Position.X.Offset == 16 then
				child.Position = UDim2.new(0, 28, child.Position.Y.Scale, math.floor(child.Position.Y.Offset * factor))
			elseif child.Position.Y.Scale == 0 then
				child.Position = UDim2.new(child.Position.X.Scale, child.Position.X.Offset, 0, math.floor(child.Position.Y.Offset * factor))
			end
			if child.Size.X.Scale == 1 and child.Size.X.Offset == -32 then
				child.Size = UDim2.new(1, -56, child.Size.Y.Scale, math.floor(child.Size.Y.Offset * factor))
			elseif child.Size.Y.Scale == 0 then
				child.Size = UDim2.new(child.Size.X.Scale, child.Size.X.Offset, 0, math.floor(child.Size.Y.Offset * factor))
			end
			if child:IsA("TextBox") then textSize(child, 20)
			elseif child:IsA("TextButton") then textSize(child, 21) end
		end
	end
	local activity = named(app.content, "GraphicActivity")
	if activity then
		Layouts.Skin(activity, "GraphicsActivityPanel"); header(activity)
		activity.Size = UDim2.new(1, 0, 0, math.max(144, activity.Size.Y.Offset))
	end
	Layouts.Skin(gallery, "GraphicsGalleryPanel"); header(gallery)
	if simple then
		gallery.Size = UDim2.new(1, 0, 0, if activity then 337 else 516)
		local grids = direct(gallery, "Frame")
		for _, grid in grids do
			if grid:FindFirstChildOfClass("UIGridLayout") and grid.Parent == gallery then
				scrollBody(gallery, "LiveGraphicsGallery", { grid }, grid.Position.Y.Offset)
			end
		end
	end
end

local function settings(app: any)
	local page = named(app.content, "SettingsScroll")
	local mode = named(app.content, "CreateMode")
	local accessibility = named(app.content, "Accessibility")
	local loadout = named(app.content, "Loadout")
	local achievements = named(app.content, "Achievements")
	if not page or not mode or not accessibility or not loadout or not achievements then return end
	place(page, 31, 99, 1530, 516); padding(page, 0)
	local left, right = mode.Parent, loadout.Parent
	left.Size = UDim2.new(0, 753, 0, 0); right.Size = UDim2.new(0, 755, 0, 0)
	padding(left, 0); padding(right, 0)
	for _, stack in { left, right } do
		local list = stack:FindFirstChildOfClass("UIListLayout")
		if list then list.Padding = UDim.new(0, 22) end
	end
	Layouts.Skin(mode, "SettingsCreateModePanel"); header(mode)
	mode.Size = UDim2.new(1, 0, 0, 143)
	for _, label in direct(mode, "TextLabel") do
		if label.Name == "SectionBanner" then continue end
		if label.Position.Y.Offset == 32 then label.Visible = false
		elseif label.Position.Y.Offset == 60 then
			label.Position = UDim2.fromOffset(28, 50); label.Size = UDim2.new(1, -56, 0, 38); textSize(label, 16)
		end
	end
	for _, button in direct(mode, "TextButton") do
		button.Position = UDim2.new(button.Position.X.Scale, button.Position.X.Offset, 0, 94)
		button.Size = UDim2.new(button.Size.X.Scale, button.Size.X.Offset, 0, 36); textSize(button, 18)
	end
	Layouts.Skin(accessibility, "SettingsAccessibilityPanel"); header(accessibility)
	-- All help text remains reachable; the overflow is an ordinary scroller.
	accessibility.Size = UDim2.new(1, 0, 0, 235)
	if not accessibility:FindFirstChild("AccessibilityControls") then
		local nodes = direct(accessibility, "GuiObject")
		local controls = {}
		for _, node in nodes do if node.Name ~= "SectionBanner" then table.insert(controls, node) end end
		scrollBody(accessibility, "AccessibilityControls", controls, 36)
	end
	local audio = named(app.content, "Audio")
	if audio then
		audio.Size = UDim2.new(1, 0, 0, 98); Layouts.Skin(audio, "SettingsAudioPanel"); header(audio)
		for _, label in direct(audio, "TextLabel") do
			if label.Name == "SectionBanner" then continue end
			if label.Text == "Sound effects" then
				label.Position = UDim2.fromOffset(28, 50); label.Size = UDim2.new(1, -168, 0, 22); textSize(label, 18)
			else
				label.Position = UDim2.fromOffset(28, 76); label.Size = UDim2.new(1, -168, 0, 18); textSize(label, 13)
			end
		end
	end
	loadout.Size = UDim2.new(1, 0, 0, 143); Layouts.Skin(loadout, "SettingsEquippedPanel"); header(loadout)
	if not loadout:FindFirstChild("EquippedItems") then
		local nodes = {}
		for _, node in direct(loadout, "GuiObject") do if node.Name ~= "SectionBanner" then table.insert(nodes, node) end end
		scrollBody(loadout, "EquippedItems", nodes, 38)
	end
	achievements.Size = UDim2.new(1, 0, 0, 235)
	Layouts.Skin(achievements, "SettingsAchievementsPanel"); header(achievements)
	for _, grid in direct(achievements, "Frame") do
		if grid:FindFirstChildOfClass("UIGridLayout") then scrollBody(achievements, "EveryAchievement", { grid }, grid.Position.Y.Offset) end
	end
	local invite, group = named(app.content, "InviteFriends"), named(app.content, "CreatorGroup")
	if invite and group and not right:FindFirstChild("CommunityActions") then
		local community = Factory.ImageCard(right, UDim2.new(1, 0, 0, 98), nil, "CommunityActions")
		community.LayoutOrder = 7; Layouts.Skin(community, "SettingsCommunityPanel")
		local title = Factory.Label(community, "Create with friends", UDim2.new(1, -340, 0, 30), {
			Position = UDim2.fromOffset(28, 14), Font = Theme.Fonts.Bold, TextSize = 22 })
		title:SetAttribute("ForgeSized", true)
		local description = direct(invite, "TextLabel")[2]
		if description then
			description.Parent = community; description.Position = UDim2.fromOffset(28, 48)
			description.Size = UDim2.new(1, -350, 0, 40); textSize(description, 15)
		end
		local inviteButton, groupButton = direct(invite, "TextButton")[1], direct(group, "TextButton")[1]
		if inviteButton then
			inviteButton.Parent = community; inviteButton.Position = UDim2.new(1, -311, 0, 12)
			inviteButton.Size = UDim2.fromOffset(283, 33); textSize(inviteButton, 17)
		end
		if groupButton then
			groupButton.Parent = community; groupButton.Position = UDim2.new(1, -311, 0, 53)
			groupButton.Size = UDim2.fromOffset(283, 33); textSize(groupButton, 17)
		end
		invite.Visible = false
		-- The full group benefits remain below the first three settings panels.
		for _, label in direct(group, "TextLabel") do
			if label.Name ~= "SectionBanner" then label.Size = UDim2.new(1, -32, label.Size.Y.Scale, label.Size.Y.Offset) end
		end
	end
end

function Layouts.Apply(app: any)
	if not app.content or app.activePage == "Home" or app.activePage == "Create" then return end
	local profileSettings = app.state and app.state.profile and app.state.profile.settings or {}
	local simple = profileSettings.simpleMode ~= false
	if app.compact then
		if app.activePage == "Avatar Graphics" and app.graphicsTab == "DISCOVER" then compactGraphicsDiscover(app, simple) end
		return
	end
	if app.activePage == "Play" then play(app)
	elseif app.activePage == "My Studio" then studio(app, simple)
	elseif app.activePage == "Discover" then marketplace(app, simple)
	elseif app.activePage == "Avatar Lab" then catalog(app, simple)
	elseif app.activePage == "Avatar Graphics" then graphics(app, simple)
	elseif app.activePage == "Settings" then settings(app)
	end
end

function Layouts.Modal(app: any, modal: GuiObject, kind: string)
	-- Modal renderers call this after creating their live contents.
	if kind == "Arcade" then
		local hub = named(modal, "HubView")
		if not hub then return end
		local tiles = direct(hub, "TextButton")
		table.sort(tiles, function(a, b)
			return if a.Position.Y.Offset == b.Position.Y.Offset then a.Position.X.Offset < b.Position.X.Offset
				else a.Position.Y.Offset < b.Position.Y.Offset
		end)
		for index, tile in tiles do
			if tile:GetAttribute("ForgeArcadePlaced") then continue end
			tile:SetAttribute("ForgeArcadePlaced", true)
			Layouts.Skin(tile, "ArcadeGame" .. index .. "Panel")
			local icon = tile:FindFirstChild("IconBadge")
			if icon then
				Layouts.Skin(icon, "ArcadeGame" .. index .. "Icon")
				local glyph = icon:FindFirstChildOfClass("TextLabel")
				local art = icon:FindFirstChild("ForgeScreenArt")
				if glyph and art then
					local function refreshIcon() glyph.Visible = art.IsLoaded ~= true end
					art:GetPropertyChangedSignal("IsLoaded"):Connect(refreshIcon); refreshIcon()
				end
			end
			local playButton = tile:FindFirstChild("PlayPill")
			if playButton then
				playButton.TextColor3 = Theme.Colors.Text
				Layouts.Skin(playButton, "ArcadeGame" .. index .. "PlayButton")
			end
		end
		if not app.compact then
			local constraint = modal:FindFirstChildOfClass("UISizeConstraint")
			if constraint then constraint.MaxSize = Vector2.new(1672, 941) end
			for _, child in direct(hub, "Frame") do
				if child.Name == "Glow" or child.Name == "Shadow" or child.Name == "FarShadow" then child.Visible = false end
			end
			local camera = game:GetService("Workspace").CurrentCamera
			local columns = if camera and camera.ViewportSize.X >= 1200 then 4 else 3
			for index, tile in tiles do
				local column, row = (index-1) % columns, math.floor((index-1)/columns)
				tile.Size = UDim2.new(1/columns, -12, 0, 139)
				tile.Position = UDim2.new(column/columns, 0, 0, 12 + row * 155)
				local title, description = tile:FindFirstChild("GameTitle"), tile:FindFirstChild("GameDescription")
				if title then title.Size = UDim2.new(1, -104, 0, 27); textSize(title, 20) end
				if description then description.Size = UDim2.new(1, -104, 0, 34); textSize(description, 14) end
				local action = tile:FindFirstChild("PlayPill")
				if action then action.Position = UDim2.new(.52, 0, 1, -48); action.Size = UDim2.new(.48, -14, 0, 36); textSize(action, 16) end
				local challenge = tile:FindFirstChild("ChallengeChip")
				if challenge then challenge.Position = UDim2.new(1, -12, 0, 73); challenge.Size = UDim2.fromOffset(102, 16) end
				for _, label in direct(tile, "TextLabel") do
					if label.Name ~= "GameTitle" and label.Name ~= "GameDescription" and label.Position.Y.Offset >= 100 then
						local score = label.Size.Y.Offset >= 20
						label.Position = UDim2.fromOffset(16, if score then 105 else 89)
						label.Size = UDim2.new(.5, -24, 0, if score then 28 else 16); textSize(label, if score then 23 else 11)
					end
				end
			end
		end
	elseif kind == "Runway" then
		local lineup, hero, weekly = named(modal, "Participants"), named(modal, "RoundHero"), named(modal, "WeeklyStandings")
		for _, info in { { lineup, "RunwayLineupPanel" }, { hero, "RunwayYourLookPanel" }, { weekly, "RunwayWeeklyPanel" } } do
			if info[1] then Layouts.Skin(info[1], info[2]) end
		end
		if app.compact or not lineup or not hero or not weekly then return end
		local left, middle = lineup.Parent, hero.Parent
		if left == middle then return end
		header(lineup); header(hero); header(weekly)
		local columns = left.Parent
		local third = columns:FindFirstChild("WeeklyColumn")
		if not third then
			third = Factory.New("Frame", { Name = "WeeklyColumn", BackgroundTransparency = 1,
				Size = UDim2.new(.2667, -15, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = columns })
			Factory.List(third, Enum.FillDirection.Vertical, 22)
		end
		weekly.Parent = third
		left.Size, middle.Size = UDim2.new(.366, -15, 0, 0), UDim2.new(.3673, -15, 0, 0)
		padding(left, 0); padding(middle, 0)
		local list = columns:FindFirstChildOfClass("UIListLayout")
		if list then list.Padding = UDim.new(0, 22) end
		local constraint = modal:FindFirstChildOfClass("UISizeConstraint")
		if constraint then constraint.MaxSize = Vector2.new(1672, 941) end
		lineup.Size = UDim2.new(1, 0, 0, 516)
		if not lineup:FindFirstChild("LiveRunwayLineup") then
			local rows = {}
			for _, child in direct(lineup, "GuiObject") do if child.Name ~= "SectionBanner" then table.insert(rows, child) end end
			scrollBody(lineup, "LiveRunwayLineup", rows, 40)
		end
		hero.Size = UDim2.new(1, 0, 0, 516)
		for _, label in direct(hero, "TextLabel") do
			if label.Position.Y.Scale == 0 and (label.Position.Y.Offset == 30 or label.Position.Y.Offset == 34) then
				label.Position = UDim2.new(label.Position.X.Scale, label.Position.X.Offset, 0, 54)
			end
		end
		local viewport = hero:FindFirstChild("SelectedLook")
		if viewport then
			viewport.Position = UDim2.fromOffset(16, 104); viewport.Size = UDim2.new(1, -32, 0, 222)
			viewport.BackgroundColor3 = Theme.Colors.Ink
		end
		if not hero:FindFirstChild("LookActions") then
			local nodes = {}
			for _, child in direct(hero, "GuiObject") do
				if child.Position.Y.Scale == 0 and child.Position.Y.Offset >= 354 then table.insert(nodes, child) end
			end
			local scroll = scrollBody(hero, "LookActions", nodes, 354)
			scroll.Position = UDim2.fromOffset(16, 340); scroll.Size = UDim2.new(1, -32, 0, 160)
		end
		weekly.Size = UDim2.new(1, 0, 0, 516)
		if not weekly:GetAttribute("ForgeWeeklyBodyPlaced") then
			weekly:SetAttribute("ForgeWeeklyBodyPlaced", true)
			for _, child in direct(weekly, "GuiObject") do
				if child.Position.Y.Scale ~= 0 or child.Name == "SectionBanner" then continue end
				local y = child.Position.Y.Offset
				if y == 36 then
					child.Position = UDim2.new(child.Position.X.Scale, child.Position.X.Offset, 0, 54)
					if child:IsA("TextLabel") then
						child.Size = UDim2.new(1, -140, 0, 30); child.TextWrapped = true
					end
				elseif y == 53 then
					child.Position = UDim2.new(child.Position.X.Scale, child.Position.X.Offset, 0, 90)
					child.Size = UDim2.new(child.Size.X.Scale, child.Size.X.Offset, 0, 18)
				elseif y >= 69 then
					-- Includes each row's rank circle and selected-player highlight.
					child.Position = UDim2.new(child.Position.X.Scale, child.Position.X.Offset, 0, y + 50)
				end
			end
		end
	end
end

return Layouts
