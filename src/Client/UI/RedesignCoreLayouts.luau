--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Factory = require(script.Parent.Factory)
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local Skin = require(script.Parent.RedesignSkin)
local Layouts = {}
local place, sized, direct = Skin.Place, Skin.Sized, Skin.Direct

local function move(child: any, parent: Instance, x: number, y: number, w: number, h: number, size: number?)
	child.Parent = parent
	place(child, x, y, w, h)
	if size then sized(child, size) end
end

local function card(parent: Instance, slug: string, asset: string, x: number, y: number, w: number, h: number): Frame
	local result = Factory.ImageCard(parent, UDim2.fromOffset(w, h), UDim2.fromOffset(x, y), "V2" .. asset)
	Skin.Skin(result, slug, asset)
	return result
end

local function header(app: any, title: string, subtitle: string, x: number, y: number, w: number, size: number)
	local heading = app.content:FindFirstChild("PageTitle")
	local description = app.content:FindFirstChild("PageSubtitle")
	if heading then heading.Text = title; place(heading, x, y, w, size+10); sized(heading, size) end
	if description then description.Text = subtitle; place(description, x+6, y+size+7, w+200, 36); sized(description, 27) end
end

local function zeroPadding(root: Instance)
	local padding = root:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingLeft, padding.PaddingRight = UDim.new(), UDim.new()
		padding.PaddingTop, padding.PaddingBottom = UDim.new(), UDim.new()
	end
end

local function create(app: any): boolean
	if app.customUGCGuideRequested then return false end
	local page = Skin.Named(app.content, "CreateScroll")
	local prompt = Skin.Named(app.content, "CustomUGCPrompt")
	local generate = Skin.Named(app.content, "CreatePersonalUGCButton")
	local ideas = Skin.Named(app.content, "IdeaSuggestions")
	if not page or not prompt or not generate or not ideas then return false end
	local oldCard = prompt.Parent
	local counter, advanced, help, safety
	for _, child in app.content:GetDescendants() do
		if child:IsA("TextButton") then
			if child.Text == "MORE CREATION OPTIONS" then advanced = child end
			if child.Text == "HOW IT WORKS" then help = child end
		elseif child:IsA("TextLabel") and child.Parent == oldCard then
			if string.match(child.Text, "^%d+ / %d+$") then counter = child end
			if child.Name == "CreateSafetyNote" or string.find(child.Text, "One custom 3D accessory", 1, true)
				or string.find(child.Text, "Your retry credit will be used", 1, true) then safety = child end
		end
	end
	header(app, "Create UGC", "Describe it. Wear it.", 118, 233, 600, 66)
	local panel = card(app.content, "create", "CreatePromptPanel", 65, 351, 823, 537)
	Skin.Label(panel, "Tell us your idea", 25, 12, 750, 45, 34)
	move(prompt, panel, 23, 61, 777, 111, 24)
	prompt.BackgroundColor3 = Color3.fromRGB(21, 62, 114)
	prompt.PlaceholderText = "A crystal crown with glowing blue gems..."
	if counter then move(counter, panel, 663, 178, 137, 27, 21) end
	Skin.Label(panel, "Need an idea? Tap one.", 25, 187, 750, 36, 25)
	move(ideas, panel, 23, 230, 777, 157)
	zeroPadding(ideas)
	ideas.ScrollBarThickness = 3
	local list = ideas:FindFirstChildOfClass("UIListLayout")
	if list then list.Padding = UDim.new(0, 13) end
	local keys = { "Dragon", "Crown", "Katana", "Hat", "Fairy" }
	local captions = { "Dragon Wings", "Crystal Crown", "Neon Katana", "Steampunk Hat", "Fairy Wings" }
	for index, chip in direct(ideas, "TextButton") do
		chip.Size = UDim2.fromOffset(145, 153)
		chip.Text = captions[index] or chip.Text
		sized(chip, 17)
		Skin.Skin(chip, "create", "CreateIdea" .. keys[index] .. "Surface")
		local art = Skin.Decoration(chip, "create", "CreateIdea" .. keys[index] .. "Art", 7, 8, 131, 107)
		if art then
			for _, image in direct(chip, "ImageLabel") do image.Visible = false end
		end
		local label = Factory.LiftLabel(chip)
		if label then place(label, 5, 116, 135, 30); label.TextXAlignment = Enum.TextXAlignment.Center end
	end
	move(generate, panel, 18, 407, 787, 90, 34)
	Skin.Skin(generate, "create", "CreateMakeItemSurface")
	if safety then
		move(safety, panel, 25, 499, 750, 34, 14)
		safety.TextXAlignment = Enum.TextXAlignment.Center
	else
		Skin.Label(panel, "Confirm the price in Roblox before paying.", 25, 502, 750, 30, 18, Theme.Colors.TextMuted).TextXAlignment = Enum.TextXAlignment.Center
	end
	local preview = card(app.content, "create", "CreatePreviewPanel", 901, 238, 716, 651)
	Skin.Label(preview, "Your next creation", 25, 12, 380, 53, 39)
	local simple = Factory.ImagePill(preview, "Simple", Theme.Colors.Cyan, 135)
	place(simple, 419, 18, 135, 50); sized(simple, 24)
	Skin.Skin(simple, "create", "CreateSimpleSurface")
	if advanced then
		move(advanced, preview, 558, 18, 140, 50, 22)
		advanced.Text = "Advanced"
	end
	local activity = Skin.Named(page, "Activity")
	if activity and activity.Visible then
		-- Real job rows retain their follow-up actions and queue updates.
		local body = Factory.New("ScrollingFrame", { Name = "V2CreationActivity", Position = UDim2.fromOffset(20, 85),
			Size = UDim2.fromOffset(676, 505), BackgroundTransparency = 1, BorderSizePixel = 0,
			AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarThickness = 5, Parent = preview })
		activity.Parent = body; activity.Position = UDim2.new(); activity.Size = UDim2.new(1, -8, 0, activity.Size.Y.Offset)
	else
		Skin.Decoration(preview, "create", "CreateHeroV2", 1, 72, 714, 576)
		local note = card(preview, "create", "CreatePreviewNote", 148, 487, 423, 87)
		Skin.Label(note, "AI creates it.\nYou make it yours.", 120, 6, 292, 74, 23)
		Skin.Decoration(note, "create", "CreateNoteSparkle", 53, 24, 40, 40)
	end
	if help then
		move(help, preview, 257, 597, 194, 39, 21)
		help.Text = "How it works  ›"
	end
	-- Original callbacks still reference these containers; retain them hidden.
	page.Visible = false
	return true
end

local function studio(app: any): boolean
	local profile = app.state.profile
	local collection, inspector = Skin.Named(app.content, "Collection"), Skin.Named(app.content, "Inspector")
	if not collection or not inspector then
		if #profile.itemOrder > 0 then return false end
		for _, child in direct(app.content, "GuiObject") do child.Visible = false end
		local emptyCollection = card(app.content, "my-items", "MyItemsCollection", 65, 233, 561, 655)
		Skin.Label(emptyCollection, "My Items", 23, 8, 490, 62, 52)
		Skin.Label(emptyCollection, "Your creations, ready to wear.", 25, 67, 500, 36, 25)
		Skin.Label(emptyCollection, "Your collection starts with an idea.", 35, 220, 490, 90, 30)
		local new = Factory.ImageButton(emptyCollection, "Create your first accessory", UDim2.fromOffset(471, 76), UDim2.fromOffset(45, 348), "primary")
		sized(new, 27); Skin.Skin(new, "my-items", "MyItemsCreateNewSurface")
		app:_BindButton(new); new.Activated:Connect(function() app:_OpenPage("Create") end)
		local emptyPreview = card(app.content, "my-items", "MyItemsPreviewPanel", 648, 233, 967, 655)
		Skin.Label(emptyPreview, "Your next creation", 35, 15, 897, 64, 48)
		Skin.Label(emptyPreview, "Create an accessory, then inspect, equip, and publish it here.", 80, 250, 807, 100, 33).TextXAlignment = Enum.TextXAlignment.Center
		return true
	end
	local title, subtitle = app.content:FindFirstChild("PageTitle"), app.content:FindFirstChild("PageSubtitle")
	if title then title.Visible = false end
	if subtitle then subtitle.Visible = false end
	place(collection, 65, 233, 561, 655)
	place(inspector, 648, 233, 967, 655)
	Skin.Skin(collection, "my-items", "MyItemsCollection")
	Skin.Skin(inspector, "my-items", "MyItemsPreviewPanel")
	local banner = collection:FindFirstChild("SectionBanner")
	if banner then banner.Visible = false end
	Skin.Label(collection, "My Items", 23, 8, 350, 62, 52)
	Skin.Label(collection, "Your creations, ready to wear.", 25, 67, 420, 36, 25)
	Skin.Label(collection, tostring(#profile.itemOrder) .. " items", 444, 67, 97, 35, 23).TextXAlignment = Enum.TextXAlignment.Right
	local new = Factory.ImageButton(collection, "Create new", UDim2.fromOffset(167, 53), UDim2.fromOffset(381, 12), "primary")
	sized(new, 22); Skin.Skin(new, "my-items", "MyItemsCreateNewSurface")
	app:_BindButton(new); new.Activated:Connect(function() app:_OpenPage("Create") end)
	local scroll = direct(collection, "ScrollingFrame")[1]
	if scroll then
		place(scroll, 12, 113, 535, 529); zeroPadding(scroll)
		local stack = direct(scroll, "Frame")[1]
		if stack then
			stack.Size = UDim2.new(1, -6, 0, 0)
			local list = stack:FindFirstChildOfClass("UIListLayout")
			if list then list.Padding = UDim.new(0, 12) end
			for _, row in direct(stack, "TextButton") do
				row.Size = UDim2.new(1, 0, 0, 127)
				local item = profile.items[profile.itemOrder[row.LayoutOrder]]
				Skin.Skin(row, "my-items", if item and item.id == app.selectedItemId then "MyItemsRowCrownSurface" else "MyItemsRowDragonSurface")
				local image = direct(row, "ImageLabel")[1]
				if image then place(image, 8, 8, 157, 110) end
				for _, label in direct(row, "TextLabel") do
					if label.Position.X.Offset >= 86 then
						local isTitle = label.Position.Y.Offset < 35
						place(label, 185, if isTitle then 15 else 61, 305, if isTitle then 38 else 50)
						sized(label, if isTitle then 29 else 20)
						if isTitle and item then label.Text = item.title or item.name end
					elseif label.Text == "›" then place(label, 491, 42, 26, 40) end
				end
			end
		end
	end
	local preview, viewport
	for _, frame in direct(inspector, "Frame") do
		local candidate = frame:FindFirstChildOfClass("ViewportFrame")
		if candidate then preview, viewport = frame, candidate; break end
	end
	if not viewport then return true end
	place(preview, 2, 2, 963, 399)
	local item = profile.items[app.selectedItemId]
	for index, label in direct(preview, "TextLabel") do
		if index == 1 then
			place(label, 30, 10, 350, 63); sized(label, 45); label.Text = item.title or item.name
			label.TextTruncate = Enum.TextTruncate.AtEnd
		else label.Visible = false end
	end
	place(viewport, 0, 72, 962, 327)
	viewport.BackgroundColor3 = Color3.fromRGB(4, 35, 74)
	local reset = viewport:FindFirstChild("ResetCamera")
	if reset then
		move(reset, inspector, 744, 291, 204, 54, 21); reset.Text = "Reset camera"
		Skin.Skin(reset, "my-items", "MyItemsResetCameraSurface")
	end
	local bodyScroll = direct(inspector, "ScrollingFrame")[1]
	local body = if bodyScroll then direct(bodyScroll, "Frame")[1] else nil
	if body then
		local readiness = direct(body, "Frame")[1]
		if readiness then
			move(readiness, inspector, 404, 23, 210, 43)
			for _, label in direct(readiness, "TextLabel") do
				if label.Position.Y.Offset <= 20 then
					place(label, 32, 0, 174, 43); sized(label, 15); label.TextTruncate = Enum.TextTruncate.AtEnd
				else move(label, viewport, 24, 278, 710, 44, 17) end
			end
		end
		for _, action in direct(body, "TextButton") do
			if string.find(action.Text, "Advanced Mode", 1, true) then
				move(action, inspector, 42, 589, 335, 52, 21); action.Text = "›  Advanced options"
			elseif string.find(action.Text, "Publish", 1, true) then
				move(action, inspector, 475, 486, 467, 81, 30)
				Skin.Skin(action, "my-items", "MyItemsPublishSurface")
			else
				move(action, inspector, 24, 486, 435, 81, 37)
				Skin.Skin(action, "my-items", "MyItemsEquipSurface")
			end
		end
		for _, label in direct(body, "TextLabel") do
			move(label, inspector, 449, 590, 477, 47, 15)
		end
	end
	if bodyScroll then bodyScroll.Visible = false end
	Skin.Label(inspector, "Item Name", 39, 396, 220, 24, 20, Theme.Colors.TextMuted)
	local nameBox = app:_TextBox(inspector, "Item name", UDim2.fromOffset(687, 52), UDim2.fromOffset(37, 420), false)
	nameBox.Name = "V2ItemName"; nameBox.Text = item.title or item.name; sized(nameBox, 24)
	local save = Factory.ImageButton(inspector, "Save name", UDim2.fromOffset(184, 62), UDim2.fromOffset(747, 402), "primary")
	sized(save, 24); Skin.Skin(save, "my-items", "MyItemsSaveNameSurface"); app:_BindButton(save)
	local editable = item.license ~= "PERSONAL_COPY"
	nameBox.TextEditable, save.Active = editable, editable
	if not editable then save.Text = "Personal copy" end
	save.Activated:Connect(function()
		if not editable then return end
		save.Active = false; save.Text = "Saving…"
		task.spawn(function()
			local ok, data = app:_Invoke(Network.Actions.SetItemDetails, { itemId = item.id, title = nameBox.Text })
			if ok then app.state.profile.items[item.id] = data.item; app:_Toast("success", "Name saved."); app:_RenderActivePage()
			elseif save.Parent then save.Active = true; save.Text = "Save name" end
		end)
	end)
	return true
end

local function market(app: any): boolean
	if Skin.Named(app.content, "FirstLookGuide") or not app.state.policy.contentSharingAllowed then return false end
	local content = app.content
	header(app, "Community Market", "Find a look. Try it on.", 75, 234, 510, 48)
	local grid
	for _, child in direct(content, "ScrollingFrame") do
		if child:FindFirstChildOfClass("UIGridLayout") then grid = child; break end
	end
	for _, tools in direct(content, "Frame") do
		local field = tools:FindFirstChildOfClass("TextBox")
		if field then
			place(tools, 592, 245, 520, 67)
			place(field, 0, 0, 386, 67); sized(field, 21); field.PlaceholderText = "Search community creations..."
			for _, button in direct(tools, "TextButton") do
				if button.Text == "Search" then place(button, 394, 2, 126, 65); sized(button, 25); Skin.Skin(button, "market", "MarketSearchSurface") end
			end
		end
	end
	for _, control in direct(content, "TextButton") do
		if string.find(control.Text, "Advanced Mode", 1, true) then
			place(control, 825, 313, 286, 23); control.Text = "Advanced filters  ›"; sized(control, 16)
		end
	end
	if not grid then
		for _, label in direct(content, "TextLabel") do
			if label.Name ~= "PageTitle" and label.Name ~= "PageSubtitle" then place(label, 70, 370, 1035, 70); sized(label, 23) end
		end
		return true
	end
	place(grid, 65, 337, 1057, 535); zeroPadding(grid)
	local gridLayout = grid:FindFirstChildOfClass("UIGridLayout")
	local function columns()
		gridLayout.CellSize = UDim2.new(1/3, -12, 0, 534)
		gridLayout.CellPadding = UDim2.fromOffset(18, 20)
	end
	columns()
	if not grid:GetAttribute("V2GridBound") then
		grid:SetAttribute("V2GridBound", true)
		local changing = false
		local connection = gridLayout:GetPropertyChangedSignal("CellSize"):Connect(function()
			if changing then return end; changing = true; columns(); changing = false
		end)
		grid.Destroying:Connect(function() connection:Disconnect() end)
	end
	for _, card_ in direct(grid, "Frame") do
		if card_.Name ~= "CommunityItem" then continue end
		Skin.Skin(card_, "market", "MarketCardCrown")
		local image = direct(card_, "ImageLabel")[1]
		if image then place(image, 16, 110, 308, 252) end
		for _, label in direct(card_, "TextLabel") do
			if label.Position.Y.Offset == 194 then place(label, 27, 10, 290, 53); sized(label, 31); label.TextXAlignment = Enum.TextXAlignment.Left
			elseif label.Position.Y.Offset == 221 then place(label, 27, 66, 290, 32); sized(label, 20); label.TextXAlignment = Enum.TextXAlignment.Left end
		end
		local expand = card_:FindFirstChild("ExpandHit")
		if expand then expand.Size = UDim2.new(1, 0, 0, 362) end
		for _, control in direct(card_, "TextButton") do
			if control.Name == "ExpandHit" then continue end
			if control.Position.Y.Offset == 250 then
				place(control, 15, 369, 314, 65); sized(control, 27); Skin.Skin(control, "market", "MarketTryCrownSurface")
			elseif control.Position.Y.Offset == 298 then
				local right = control.Position.X.Scale > 0
				place(control, if right then 186 else 15, 451, 152, 64); sized(control, 22)
				Skin.Skin(control, "market", if right then "MarketFavoriteCrownSurface" else "MarketLikeCrownSurface")
				for _, glyph in direct(control, "TextLabel") do
					if glyph.Name ~= "Label" then place(glyph, 12, 0, 28, 64); sized(glyph, 29) end
				end
			end
		end
	end
	return true
end

function Layouts.Apply(app: any): boolean
	if app.compact or app.state.profile.settings.simpleMode == false then return false end
	if app.activePage == "Create" then return create(app)
	elseif app.activePage == "My Studio" then return studio(app)
	elseif app.activePage == "Discover" then return market(app) end
	return false
end

return Layouts
