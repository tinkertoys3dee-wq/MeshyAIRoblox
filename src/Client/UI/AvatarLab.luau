--!strict

local AvatarEditorService = game:GetService("AvatarEditorService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Factory)
local ViewportController = require(script.Parent.ViewportController)
local RunwayHub = require(script.Parent.RunwayHub)

local AvatarLab = {}
local C = Theme.Colors
local CATEGORIES = {
	{ "Hat", "Hats" },
	{ "HairAccessory", "Hair" },
	{ "FaceAccessory", "Face extras" },
	{ "Shirt", "Classic shirts" },
	{ "Pants", "Classic pants" },
	{ "TShirt", "T-shirts" },
	{ "JacketAccessory", "Jackets" },
	{ "SweaterAccessory", "Sweaters" },
	{ "ShirtAccessory", "Layered tops" },
	{ "PantsAccessory", "Layered pants" },
	{ "Face", "Faces" },
	{ "NeckAccessory", "Neck" },
	{ "ShoulderAccessory", "Shoulders" },
	{ "FrontAccessory", "Front" },
	{ "BackAccessory", "Back" },
	{ "WaistAccessory", "Waist" },
}
local SPARKS = {
	{ "Cyber", "cyber", "A sleek cyan cyber visor with a single solid frame", "FaceAccessory" },
	{ "Fantasy", "fantasy", "A violet crystal crown with a chunky connected silhouette", "Hat" },
	{ "Soft pastel", "pastel", "A pastel butterfly backpack with rounded connected wings", "BackAccessory" },
	{ "Streetwear", "streetwear", "A glossy black crossbody bag with a silver star buckle", "FrontAccessory" },
}

local function state(app: any): any
	if not app.catalogWorkspace then
		app.catalogWorkspace = {
			tab = "BROWSE",
			request = 0,
			pages = nil,
			loadingMore = false,
			favorites = {},
			favoriteOrder = {},
			filters = false,
			outfitName = "",
			busy = false,
			spark = 1,
		}
	end
	return app.catalogWorkspace
end

local function render(app: any)
	if app.activePage == "Avatar Lab" then
		app:_RenderActivePage()
	end
end

local function normalize(items: { any }, category: string): { any }
	local result = {}
	for _, item in items do
		local id = tonumber(item.Id or item.AssetId)
		if id and id > 0 then
			local copy = table.clone(item)
			copy.Id = id
			copy.forgeCategory = category
			table.insert(result, copy)
		end
	end
	return result
end

function AvatarLab.Search(app: any, query: string)
	local lab = state(app)
	lab.request += 1
	local request = lab.request
	app.catalogQuery = query
	app.catalogError = nil
	app.catalogResults = nil
	lab.pages = nil
	lab.loadingMore = false
	app.scrollPositions.AvatarLabWorkspace = Vector2.zero
	if app.catalogAccess ~= true then
		app.catalogSearching = false
		render(app)
		return
	end
	local minPrice, maxPrice = tonumber(app.catalogMinPrice), tonumber(app.catalogMaxPrice)
	if minPrice and maxPrice and minPrice > maxPrice then
		app.catalogSearching = false
		app.catalogResults = {}
		app.catalogError = "Minimum price must be lower than maximum price. Change the filters and search again."
		render(app)
		return
	end
	local category, sort = app.catalogType, app.catalogSortType
	local creator = string.sub(app.catalogCreatorName or "", 1, 50)
	app.catalogSearching = true
	task.spawn(function()
		local ok, pages, firstPage = pcall(function()
			local params = CatalogSearchParams.new()
			params.SearchKeyword = string.sub(query, 1, 60)
			params.AssetTypes = { Enum.AvatarAssetType[category] }
			params.SortType = Enum.CatalogSortType[sort]
			params.IncludeOffSale = false
			params.Limit = 30
			if creator ~= "" then
				params.CreatorName = creator
			end
			if minPrice then
				params.MinPrice = math.clamp(math.floor(minPrice), 0, 2147483647)
			end
			if maxPrice then
				params.MaxPrice = math.clamp(math.floor(maxPrice), 0, 2147483647)
			end
			local found = AvatarEditorService:SearchCatalogAsync(params)
			return found, found:GetCurrentPage()
		end)
		if request ~= lab.request then
			return
		end -- a newer query owns this view
		app.catalogSearching = false
		if ok then
			lab.pages = pages
			app.catalogResults = normalize(firstPage, category)
			app:_Track({
				event = "CatalogSearch",
				fields = {
					assetType = category,
					sortType = sort,
					resultCount = #app.catalogResults,
					hasCreatorFilter = creator ~= "",
					hasPriceFilter = minPrice ~= nil or maxPrice ~= nil,
				},
			})
		else
			app.catalogResults = {}
			app.catalogError = "Roblox couldn't load these results. Your look is safe. Try Search again."
			app:_Toast("error", app.catalogError)
		end
		render(app)
	end)
	render(app)
end

function AvatarLab.LoadMore(app: any)
	local lab = state(app)
	local pages, request, category = lab.pages, lab.request, app.catalogType
	if lab.loadingMore or not pages or pages.IsFinished or #(app.catalogResults or {}) >= 180 then
		return
	end
	lab.loadingMore = true
	render(app)
	task.spawn(function()
		local ok, nextPage = pcall(function()
			pages:AdvanceToNextPageAsync()
			return pages:GetCurrentPage()
		end)
		if request ~= lab.request then
			return
		end
		lab.loadingMore = false
		if ok then
			local seen = {}
			for _, item in app.catalogResults or {} do
				seen[item.Id] = true
			end
			for _, item in normalize(nextPage, category) do
				if not seen[item.Id] then
					table.insert(app.catalogResults, item)
					seen[item.Id] = true
				end
			end
		else
			app:_Toast(
				"error",
				"The next page didn't load. Tap Load more to retry; your current results are still here."
			)
		end
		render(app)
	end)
end

local function changed(app: any)
	app.communityTryOnItem = nil
	app.avatarAccessoriesDirty = true
	app.avatarAccessoriesRevision = (app.avatarAccessoriesRevision or 0) + 1
	app.avatarPreviewDirty = true
	app:_RefreshAvatarAccessories()
	render(app)
end

local function mutate(app: any, action: string, payload: any, message: string)
	local lab = state(app)
	if lab.busy then
		app:_Toast("info", "Your last change is still applying.")
		return
	end
	lab.busy = true
	local startedTab = lab.tab
	app:_Toast("info", "Updating your look…")
	task.spawn(function()
		local ok, result = app:_Invoke(action, payload)
		lab.busy = false
		if ok then
			if result.equippedItemIds then
				app.state.profile.equippedItemIds = result.equippedItemIds
			end
			if
				action == Network.Actions.EquipItem
				and not table.find(app.state.profile.equippedItemIds, payload.itemId)
			then
				table.insert(app.state.profile.equippedItemIds, payload.itemId)
			end
			if action == Network.Actions.UnequipItem then
				local index = table.find(app.state.profile.equippedItemIds, payload.itemId)
				if index then
					table.remove(app.state.profile.equippedItemIds, index)
				end
			end
			local firstPreview = action == Network.Actions.TryCatalogAsset and not lab.previewIntroduced
			if firstPreview and app.compact and app.activePage == "Avatar Lab" and lab.tab == startedTab then
				lab.tab = "LOOK"
				app.scrollPositions.AvatarLabWorkspace = Vector2.zero
				message = "Item applied! Drag to see your look, then use Browse to add more. Nothing was purchased."
			end
			if firstPreview then
				lab.previewIntroduced = true
			end
			app:_Toast("success", message)
			changed(app)
		else
			render(app)
		end
	end)
end

local function label(parent: Instance, text: string, height: number, bold: boolean?): TextLabel
	return Factory.Label(parent, text, UDim2.new(1, 0, 0, height), {
		TextSize = if bold then 16 else 13,
		Font = if bold then Theme.Fonts.Bold else Theme.Fonts.Regular,
		Wrapped = true,
		AlignY = Enum.TextYAlignment.Top,
	})
end

local function row(parent: Instance, order: number, height: number?): ScrollingFrame
	local frame = Factory.New("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, height or 44),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		LayoutOrder = order,
		Parent = parent,
	})
	Factory.List(frame, Enum.FillDirection.Horizontal, 8)
	return frame
end

local function button(
	app: any,
	parent: Instance,
	text: string,
	width: number,
	action: () -> (),
	primary: boolean?
): TextButton
	local control =
		Factory.ImageButton(parent, text, UDim2.fromOffset(width, 42), nil, if primary then "primary" else nil)
	control.TextSize = 13
	app:_BindButton(control)
	control.Activated:Connect(function()
		if control.Active then
			action()
		end
	end)
	return control
end

local function design(app: any)
	local spark = SPARKS[state(app).spark]
	app.draftPrompt = spark[3]
	app.selectedAccessoryType = spark[4]
	app.selectedMethod = "TEXT_TO_3D"
	app.scrollPositions.Create = Vector2.zero
	app:_OpenPage("Create")
	app:_Toast("info", "An idea is ready to edit. Custom generation is paid; nothing starts until you confirm.")
end

local function lookPanel(app: any, stack: Frame)
	local lab = state(app)
	local preview = Factory.New("ViewportFrame", {
		Name = "LookPreview",
		Size = UDim2.new(1, 0, 0, 260),
		BackgroundColor3 = C.Ink,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = stack,
	})
	Factory.Corner(preview, 14)
	app.activeViewport = ViewportController.new(preview)
	label(stack, "Drag to rotate. Trying items is free; owning them is separate.", 42).LayoutOrder = 2
	local actions = row(stack, 3)
	button(app, actions, "Undo", 92, function()
		mutate(app, Network.Actions.UndoAvatar, {}, "Last catalog change undone.")
	end)
	button(app, actions, "Redo", 92, function()
		mutate(app, Network.Actions.RedoAvatar, {}, "Catalog change restored.")
	end)
	button(app, actions, "Reset catalog", 138, function()
		mutate(
			app,
			Network.Actions.ResetAvatar,
			{},
			"Catalog reset to your saved Roblox avatar. Custom UGCs stay equipped; undo is available."
		)
	end)
	button(app, actions, "Save to Roblox", 150, function()
		local humanoid = Players.LocalPlayer.Character
			and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			app:_Toast("error", "Wait for your character to load.")
			return
		end
		local ok = pcall(function()
			AvatarEditorService:PromptSaveAvatar(humanoid:GetAppliedDescription(), humanoid.RigType)
		end)
		app:_Toast(
			if ok then "info" else "error",
			if ok
				then "Confirm in Roblox. Only owned catalog items can be saved; unpublished Forge models stay in this game."
				else "Roblox couldn't open the save prompt."
		)
	end)
	local saveRow = Factory.New(
		"Frame",
		{ Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, LayoutOrder = 4, Parent = stack }
	)
	local name = app:_TextBox(saveRow, "Name this mixed outfit", UDim2.new(1, -134, 0, 42), UDim2.new(), false)
	name.Text = lab.outfitName
	name:GetPropertyChangedSignal("Text"):Connect(function()
		lab.outfitName = name.Text
	end)
	local save = button(app, saveRow, "Save in Forge", 126, function()
		if lab.saving then
			return
		end
		lab.saving = true
		task.spawn(function()
			local ok, data = app:_Invoke(Network.Actions.SaveOutfit, { name = lab.outfitName })
			lab.saving = false
			if ok and data.outfit then
				app.state.profile.outfits[data.outfit.id] = data.outfit
				table.insert(app.state.profile.outfitOrder, 1, data.outfit.id)
				app:_Toast(
					"success",
					"Mixed outfit saved in Forge: catalog clothes, accessories and your equipped custom UGCs."
				)
				render(app)
			end
		end)
	end, true)
	save.Position = UDim2.new(1, -126, 0, 0)
	label(stack, "WORN NOW", 24, true).LayoutOrder = 5
	local worn = Factory.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 6,
		Parent = stack,
	})
	Factory.List(worn, Enum.FillDirection.Vertical, 8)
	if app.avatarAccessoriesError then
		label(worn, "The worn-item list didn't load. Your avatar is unchanged.", 46)
		button(app, worn, "Retry worn list", 150, function()
			app.avatarAccessoriesRetryAt = 0
			app:_RefreshAvatarAccessories()
		end)
	end
	if app.avatarAccessoriesDirty or not app.avatarAccessoriesLoaded then
		app:_RefreshAvatarAccessories()
	end
	local count = 0
	for assetId, info in app.triedOnAssetInfo do
		count += 1
		local line = Factory.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = worn })
		Factory.Label(line, info.name, UDim2.new(1, -100, 1, 0), { TextSize = 13, Truncate = Enum.TextTruncate.AtEnd })
		local remove = button(app, line, "Remove", 92, function()
			mutate(app, Network.Actions.UntryCatalogAsset, { assetId = assetId }, "Item removed. Undo is available.")
		end)
		remove.Position = UDim2.new(1, -92, 0, 0)
	end
	if count == 0 then
		label(
			worn,
			if app.avatarAccessoriesLoading
				then "Reading your worn items…"
				else "Try a catalog item to start your look.",
			40
		)
	end
	label(stack, "SAVED MIXED OUTFITS", 24, true).LayoutOrder = 7
	local looks = Factory.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 8,
		Parent = stack,
	})
	Factory.List(looks, Enum.FillDirection.Vertical, 10)
	if #(app.state.profile.outfitOrder or {}) == 0 then
		label(
			looks,
			"Your first mixed outfit belongs here. Try a few items, name your look, then tap Save in Forge.",
			64
		)
	end
	for _, id in app.state.profile.outfitOrder or {} do
		local outfit = app.state.profile.outfits[id]
		if outfit then
			local line =
				Factory.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 84), Parent = looks })
			label(line, outfit.name, 26, true)
			local wear = button(app, line, "Wear outfit", 126, function()
				mutate(
					app,
					Network.Actions.EquipOutfit,
					{ outfitId = id },
					"Saved look applied. Any unavailable custom pieces were skipped."
				)
			end, true)
			wear.Position = UDim2.fromOffset(0, 34)
			local confirming, deleting = false, false
			local remove: TextButton
			remove = button(app, line, "Delete saved", 126, function()
				if deleting then
					return
				end
				if not confirming then
					confirming = true
					remove.Text = "Confirm delete"
					app:_Toast("info", "Tap Confirm delete to remove this saved outfit. Your owned items will stay.")
					task.delay(5, function()
						if remove.Parent and not deleting then
							confirming = false
							remove.Text = "Delete saved"
						end
					end)
					return
				end
				deleting = true
				task.spawn(function()
					local ok = app:_Invoke(Network.Actions.DeleteOutfit, { outfitId = id })
					deleting = false
					if ok then
						app.state.profile.outfits[id] = nil
						local index = table.find(app.state.profile.outfitOrder, id)
						if index then
							table.remove(app.state.profile.outfitOrder, index)
						end
						app:_Toast("success", "Saved outfit removed. The items you own are unchanged.")
						render(app)
					end
				end)
			end)
			remove.Position = UDim2.fromOffset(134, 34)
		end
	end
end

local function itemGrid(app: any, stack: Frame, results: { any }, forge: boolean?)
	local lab = state(app)
	local grid = Factory.New("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 20,
		Parent = stack,
	})
	local layout = Factory.New(
		"UIGridLayout",
		{ CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid }
	)
	local function resize()
		local width = math.max(1, grid.AbsoluteSize.X / (app.uiScaleInstance.Scale or 1))
		local columns = math.max(1, math.floor((width + 12) / 190))
		layout.CellSize = UDim2.new(1 / columns, -12 * (columns - 1) / columns, 0, 326)
	end
	resize()
	table.insert(app.pageConnections, grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize))
	for index, item in results do
		local id = item.Id
		local modelThumbnail =
			string.format("rbxthumb://type=Asset&id=%d&w=420&h=420", if forge then item.modelAssetId or 0 else id)
		local uploadedThumbnail = if forge then tonumber(item.thumbnailAssetId) else nil
		local card = Factory.ImageCard(grid, UDim2.fromScale(1, 1), nil, "StyleItem")
		card.LayoutOrder = index
		local image = Factory.New("ImageLabel", {
			Size = UDim2.new(1, -24, 0, 152),
			Position = UDim2.fromOffset(12, 12),
			BackgroundColor3 = C.Ink,
			BorderSizePixel = 0,
			ScaleType = Enum.ScaleType.Fit,
			Image = if uploadedThumbnail and uploadedThumbnail > 0
				then "rbxassetid://" .. uploadedThumbnail
				else modelThumbnail,
			Parent = card,
		})
		Factory.Corner(image, 10)
		local hint = Factory.Label(
			image,
			"Loading preview…",
			UDim2.fromScale(1, 1),
			{ TextSize = 12, AlignX = Enum.TextXAlignment.Center }
		)
		app:_WatchImageLoad(image, hint, modelThumbnail)
		Factory.Label(
			card,
			item.Name or item.name or "Item",
			UDim2.new(1, -24, 0, 24),
			{ Position = UDim2.fromOffset(12, 170), TextSize = 14, Font = Theme.Fonts.Bold }
		)
		local price = tonumber(item.Price or item.LowestPrice)
		Factory.Label(
			card,
			if forge
				then "Your custom Forge creation"
				elseif price == 0 then "Free to own · free to try"
				elseif price then string.format("R$ %d to own · free to try", price)
				else "Free to try · check price in Roblox",
			UDim2.new(1, -24, 0, 32),
			{ Position = UDim2.fromOffset(12, 198), TextSize = 11, Wrapped = true, Color = C.TextMuted }
		)
		local customWorn = forge and table.find(app.state.profile.equippedItemIds, item.id) ~= nil
		local try = Factory.ImageButton(
			card,
			if forge
				then (if customWorn then "Remove custom item" else "Wear custom item")
				elseif app.triedOnAssetIds[id] then "Remove"
				else "Try on · free",
			UDim2.new(1, -24, 0, 42),
			UDim2.fromOffset(12, 236),
			"primary"
		)
		try.Active = not lab.busy
		try.Activated:Connect(function()
			if forge then
				mutate(
					app,
					if customWorn then Network.Actions.UnequipItem else Network.Actions.EquipItem,
					{ itemId = item.id },
					if customWorn
						then "Custom item removed from your look."
						else "Custom item added to your catalog look."
				)
				return
			end
			local removing = app.triedOnAssetIds[id] == true
			mutate(
				app,
				if removing then Network.Actions.UntryCatalogAsset else Network.Actions.TryCatalogAsset,
				{ assetId = id, avatarAssetType = item.forgeCategory },
				if removing
					then "Item removed. Undo is available."
					else "Item applied! Open My look to preview or save."
			)
		end)
		if not forge then
			local star = Factory.ImageButton(
				card,
				if lab.favorites[id] then "Saved" else "Save",
				UDim2.fromOffset(66, 34),
				UDim2.new(1, -78, 0, 20)
			)
			star.Activated:Connect(function()
				if lab.favorites[id] then
					lab.favorites[id] = nil
					local position = table.find(lab.favoriteOrder, id)
					if position then
						table.remove(lab.favoriteOrder, position)
					end
				else
					if #lab.favoriteOrder >= 60 then
						app:_Toast("info", "Your visit collection holds 60 items. Remove one to save another.")
						return
					end
					lab.favorites[id] = item
					table.insert(lab.favoriteOrder, id)
				end
				render(app)
			end)
			local buy = Factory.New("TextButton", {
				BackgroundTransparency = 1,
				Text = "Buy / view in Roblox",
				TextColor3 = C.Cyan,
				TextSize = 12,
				Font = Theme.Fonts.Bold,
				Size = UDim2.new(1, -24, 0, 36),
				Position = UDim2.fromOffset(12, 282),
				Parent = card,
			})
			buy.Activated:Connect(function()
				if not app.state.policy.commerceAllowed then
					app:_Toast("info", "Purchases are unavailable for this account. You can still try items.")
					return
				end
				local ok = pcall(function()
					MarketplaceService:PromptPurchase(Players.LocalPlayer, id)
				end)
				app:_Toast(
					if ok then "info" else "error",
					if ok
						then "Check the item and final price in Roblox. Cancel if you don't want to buy."
						else "Roblox couldn't open this item. Try again later."
				)
			end)
		end
	end
end

function AvatarLab.Render(app: any)
	local lab = state(app)
	app:_PageHeader("Avatar Lab", "Try it free. Make it yours. Mix catalog fashion with your custom Forge UGCs.", true)
	local page = Factory.New("ScrollingFrame", {
		Name = "AvatarLabWorkspace",
		Size = UDim2.new(0.96, 0, 1, -106),
		Position = UDim2.new(0.02, 0, 0, 94),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = app.content,
	})
	app:_TrackScroll(page, "AvatarLabWorkspace")
	Factory.Padding(page, 12, 12)
	local stack = Factory.New("Frame", {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = page,
	})
	Factory.List(stack, Enum.FillDirection.Vertical, 12)
	local tabs = row(stack, -10)
	for _, tab in
		{
			{ "BROWSE", "Browse" },
			{ "LOOK", "My look" },
			{ "SAVED", "Saved this visit" },
			{ "FORGE", "My custom UGCs" },
		}
	do
		button(app, tabs, tab[2], if #tab[2] > 9 then 148 else 100, function()
			lab.tab = tab[1]
			app.scrollPositions.AvatarLabWorkspace = Vector2.zero
			render(app)
		end, lab.tab == tab[1])
	end
	if lab.tab == "LOOK" then
		lookPanel(app, stack)
		return
	end
	if lab.tab == "FORGE" then
		label(stack, "Your own designs + catalog fashion, in one saved outfit.", 40, true).LayoutOrder = 1
		local actions = row(stack, 2)
		button(app, actions, "Design a missing piece", 206, function()
			design(app)
		end, true)
		button(app, actions, "Show it on Runway", 190, function()
			RunwayHub.Show(app)
		end)
		local records = {}
		for _, id in app.state.profile.itemOrder or {} do
			local item = app.state.profile.items[id]
			if item then
				table.insert(records, item)
			end
		end
		if #records == 0 then
			label(
				stack,
				"No custom items yet. Design one, confirm its price, then fit it in My Studio. Catalog try-ons never spend generation credits.",
				72
			).LayoutOrder =
				3
		end
		itemGrid(app, stack, records, true)
		return
	end
	if lab.tab == "SAVED" then
		label(
			stack,
			"Bookmarks last for this visit. Wear your favorites, then save the complete outfit in My look to keep it.",
			58
		).LayoutOrder =
			1
		local records = {}
		for _, id in lab.favoriteOrder do
			table.insert(records, lab.favorites[id])
		end
		if #records == 0 then
			label(stack, "Tap Save on any catalog card to collect ideas here.", 46).LayoutOrder = 2
		end
		itemGrid(app, stack, records)
		return
	end
	-- Permission is the first available action, not a button below several
	-- screens of filters that cannot do anything until access is granted.
	if app.catalogAccess ~= true then
		label(stack, "READY TO TRY YOUR FIRST LOOK?", 46, true).LayoutOrder = 1
		local access = row(stack, 2)
		local enable = button(
			app,
			access,
			if app.catalogAccessPrompting then "Waiting for Roblox…" else "Enable catalog · free",
			230,
			function()
				app:_RequestCatalogAccess()
				render(app)
			end,
			true
		)
		enable.Active = not app.catalogAccessPrompting
		label(
			stack,
			app.catalogError
				or "Roblox asks for permission once this visit. Enabling the catalog doesn't buy an item or start a custom generation.",
			78
		).LayoutOrder =
			3
		local preview = row(stack, 4)
		button(app, preview, "See my current avatar", 220, function()
			lab.tab = "LOOK"
			app.scrollPositions.AvatarLabWorkspace = Vector2.zero
			render(app)
		end)
		label(
			stack,
			"After enabling: choose an item → tap Try on → see it on your avatar. Owning an item is a separate Roblox purchase.",
			78
		).LayoutOrder =
			5
		return
	end
	local searchRow = Factory.New(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 1, Parent = stack }
	)
	local search =
		app:_TextBox(searchRow, "Search hair, clothes, accessories…", UDim2.new(1, -104, 0, 42), UDim2.new(), false)
	search.Text = app.catalogQuery
	search:GetPropertyChangedSignal("Text"):Connect(function()
		app.catalogQuery = search.Text
	end)
	local searchButton = button(app, searchRow, "Search", 96, function()
		AvatarLab.Search(app, search.Text)
	end, true)
	searchButton.Position = UDim2.new(1, -96, 0, 0)
	search.FocusLost:Connect(function(enter)
		if enter then
			AvatarLab.Search(app, search.Text)
		end
	end)
	local categories = row(stack, 2)
	for _, category in CATEGORIES do
		button(app, categories, category[2], math.max(100, #category[2] * 8 + 26), function()
			app.catalogType = category[1]
			AvatarLab.Search(app, app.catalogQuery)
		end, app.catalogType == category[1])
	end
	local filters = row(stack, 3)
	button(app, filters, if lab.filters then "Hide filters" else "Price & sort", 138, function()
		lab.filters = not lab.filters
		render(app)
	end)
	button(app, filters, if lab.sparkOpen then "Hide Style Sparks" else "Style Sparks", 164, function()
		lab.sparkOpen = not lab.sparkOpen
		render(app)
	end)
	if lab.sparkOpen then
		local sparks = row(stack, 4)
		for index, spark in SPARKS do
			button(app, sparks, spark[1], 120, function()
				lab.spark = index
				AvatarLab.Search(app, spark[2])
			end, lab.spark == index)
		end
		label(stack, "Pick a theme to find catalog pieces, then design a missing piece yourself.", 46).LayoutOrder = 5
		local designRow = row(stack, 6)
		button(app, designRow, "Design a matching UGC", 208, function()
			design(app)
		end)
	end
	if lab.filters then
		local sorting = row(stack, 7)
		for _, option in
			{
				{ "Relevance", "Relevant" },
				{ "Bestselling", "Popular" },
				{ "RecentlyCreated", "Newest" },
				{ "PriceLowToHigh", "Price: low first" },
				{ "PriceHighToLow", "Price: high first" },
				{ "MostFavorited", "Most saved" },
			}
		do
			button(app, sorting, option[2], 144, function()
				app.catalogSortType = option[1]
				AvatarLab.Search(app, app.catalogQuery)
			end, app.catalogSortType == option[1])
		end
		local budget = row(stack, 8)
		for _, amount in { -1, 0, 50, 100, 250 } do
			button(
				app,
				budget,
				if amount == -1 then "Any price" elseif amount == 0 then "Free to own" else "Up to R$ " .. amount,
				136,
				function()
					app.catalogMinPrice = ""
					app.catalogMaxPrice = if amount < 0 then "" else tostring(amount)
					AvatarLab.Search(app, app.catalogQuery)
				end,
				app.catalogMaxPrice == (if amount < 0 then "" else tostring(amount))
			)
		end
		local creator = app:_TextBox(stack, "Creator name (optional)", UDim2.new(1, 0, 0, 42), UDim2.new(), false)
		creator.LayoutOrder = 9
		creator.Text = app.catalogCreatorName
		creator:GetPropertyChangedSignal("Text"):Connect(function()
			app.catalogCreatorName = creator.Text
		end)
		creator.FocusLost:Connect(function(enter)
			if enter then
				AvatarLab.Search(app, app.catalogQuery)
			end
		end)
	end
	if app.catalogResults == nil and not app.catalogSearching then
		task.defer(function()
			if app.activePage == "Avatar Lab" then
				AvatarLab.Search(app, app.catalogQuery)
			end
		end)
	end
	label(
		stack,
		if app.catalogSearching
			then "Searching Roblox…"
			elseif app.catalogError then app.catalogError
			else string.format(
				"%d items loaded · all free to try · prices are for ownership",
				#(app.catalogResults or {})
			),
		46
	).LayoutOrder =
		10
	itemGrid(app, stack, app.catalogResults or {})
	if app.catalogResults and #app.catalogResults == 0 and not app.catalogSearching and not app.catalogError then
		label(stack, "No matches. Try another category, a shorter search, or Any price.", 60).LayoutOrder = 21
	end
	if #(app.catalogResults or {}) >= 180 then
		label(
			stack,
			"180 items loaded. Refine your search or category to find more without slowing down your device.",
			58
		).LayoutOrder =
			22
	elseif lab.pages and not lab.pages.IsFinished then
		local more = row(stack, 22)
		local control = button(app, more, if lab.loadingMore then "Loading…" else "Load more items", 200, function()
			AvatarLab.LoadMore(app)
		end, true)
		control.Active = not lab.loadingMore
	end
end

return AvatarLab
