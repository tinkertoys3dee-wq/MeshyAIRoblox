--!strict

local AvatarEditorService = game:GetService("AvatarEditorService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarLook = require(ReplicatedStorage:WaitForChild("AvatarLook"))

local CatalogService = {}
CatalogService.__index = CatalogService

local TYPES = {
	Hat = Enum.AvatarAssetType.Hat,
	HairAccessory = Enum.AvatarAssetType.HairAccessory,
	FaceAccessory = Enum.AvatarAssetType.FaceAccessory,
	NeckAccessory = Enum.AvatarAssetType.NeckAccessory,
	ShoulderAccessory = Enum.AvatarAssetType.ShoulderAccessory,
	FrontAccessory = Enum.AvatarAssetType.FrontAccessory,
	BackAccessory = Enum.AvatarAssetType.BackAccessory,
	WaistAccessory = Enum.AvatarAssetType.WaistAccessory,
	Shirt = Enum.AvatarAssetType.Shirt,
	Pants = Enum.AvatarAssetType.Pants,
	TShirt = Enum.AvatarAssetType.TShirt,
	Face = Enum.AvatarAssetType.Face,
	JacketAccessory = Enum.AvatarAssetType.JacketAccessory,
	SweaterAccessory = Enum.AvatarAssetType.SweaterAccessory,
	ShirtAccessory = Enum.AvatarAssetType.ShirtAccessory,
	PantsAccessory = Enum.AvatarAssetType.PantsAccessory,
}
local CLASSIC = { Shirt = "Shirt", Pants = "Pants", TShirt = "GraphicTShirt", Face = "Face" }

function CatalogService.new(profileService: any, playerStateService: any, analyticsService: any)
	return setmetatable({
		profiles = profileService,
		playerStates = playerStateService,
		analytics = analyticsService,
		assetNameCache = {} :: { [number]: string },
		history = {} :: { [Player]: any },
	}, CatalogService)
end

function CatalogService:_Remember(player: Player, snapshot: any)
	local history = self.history[player]
	if not history or history.character ~= player.Character then
		history = { character = player.Character, undo = {}, redo = {} }
		self.history[player] = history
	end
	table.insert(history.undo, snapshot)
	if #history.undo > 20 then
		table.remove(history.undo, 1)
	end
	table.clear(history.redo)
end

function CatalogService:History(player: Player, redo: boolean): (boolean, any)
	local history = self.history[player]
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "CHARACTER_UNAVAILABLE"
	end
	if not history or history.character ~= player.Character then
		return false, "AVATAR_HISTORY_EMPTY"
	end
	local source = if redo then history.redo else history.undo
	local destination = if redo then history.undo else history.redo
	if #source == 0 then
		return false, "AVATAR_HISTORY_EMPTY"
	end
	local success, current = pcall(function()
		local before = AvatarLook.Read(humanoid)
		local description = AvatarLook.Description(source[#source])
		local applied, problem = pcall(function()
			humanoid:ApplyDescriptionAsync(description)
		end)
		description:Destroy()
		if not applied then
			error(problem)
		end
		return before
	end)
	if not success then
		return false, "TRY_ON_FAILED"
	end
	if history.character ~= player.Character then
		return false, "CHARACTER_UNAVAILABLE"
	end
	table.remove(source)
	table.insert(destination, current)
	return true, { undoCount = #history.undo, redoCount = #history.redo }
end

function CatalogService:Remove(player: Player)
	self.history[player] = nil
end

function CatalogService:GetEquippedAccessories(player: Player): (boolean, any)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "CHARACTER_UNAVAILABLE"
	end
	local descriptionSuccess, accessoriesOrProblem = pcall(function()
		local description = humanoid:GetAppliedDescription()
		local accessories = description:GetAccessories(true)
		for typeName, property in CLASSIC do
			local assetId = (description :: any)[property]
			if assetId > 0 then
				table.insert(accessories, { AssetId = assetId, typeName = typeName })
			end
		end
		description:Destroy()
		return accessories
	end)
	if not descriptionSuccess or type(accessoriesOrProblem) ~= "table" then
		warn(string.format("[CatalogService] Could not read equipped accessories: %s", tostring(accessoriesOrProblem)))
		return false, "AVATAR_UNAVAILABLE"
	end

	local result = {}
	local seen = {} :: { [number]: boolean }
	for _, accessory in accessoriesOrProblem do
		local assetId = math.floor(tonumber(accessory.AssetId) or 0)
		if assetId > 0 and not seen[assetId] then
			seen[assetId] = true
			local name = self.assetNameCache[assetId]
			if not name then
				local infoSuccess, info = pcall(function()
					return MarketplaceService:GetProductInfoAsync(assetId, Enum.InfoType.Asset)
				end)
				name = if infoSuccess
						and type(info) == "table"
						and type(info.Name) == "string"
					then info.Name
					else string.format("Avatar accessory %d", assetId)
				self.assetNameCache[assetId] = name
			end
			local assetType = accessory.typeName or tostring(accessory.AccessoryType or "Accessory")
			assetType = string.gsub(assetType, "Enum%.AccessoryType%.", "")
			table.insert(result, { assetId = assetId, name = name, assetType = assetType })
		end
	end
	return true, { accessories = result }
end

function CatalogService:TryOn(player: Player, payload: any): (boolean, any)
	if
		type(payload) ~= "table"
		or type(payload.assetId) ~= "number"
		or payload.assetId <= 0
		or payload.assetId % 1 ~= 0
	then
		return false, "INVALID_REQUEST"
	end
	local avatarAssetType = if type(payload.avatarAssetType) == "string" then TYPES[payload.avatarAssetType] else nil
	if not avatarAssetType then
		return false, "INVALID_ASSET_TYPE"
	end
	local assetId = math.floor(payload.assetId)
	local infoSuccess, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(assetId, Enum.InfoType.Asset)
	end)
	if not infoSuccess or type(info) ~= "table" or info.AssetTypeId ~= avatarAssetType.Value then
		return false, "CATALOG_ITEM_UNAVAILABLE"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "CHARACTER_UNAVAILABLE"
	end
	local before = nil
	local description: any = nil
	local success, appliedOrProblem = pcall(function(): boolean
		description = humanoid:GetAppliedDescription()
		before = AvatarLook.Capture(description)
		local classicProperty = CLASSIC[payload.avatarAssetType]
		if classicProperty then
			if (description :: any)[classicProperty] == assetId then
				return false
			end
			(description :: any)[classicProperty] = assetId
			humanoid:ApplyDescriptionAsync(description)
			return true
		end
		local accessories = description:GetAccessories(true)
		for _, accessory in accessories do
			if accessory.AssetId == assetId then
				return false
			end
		end
		table.insert(accessories, {
			AssetId = assetId,
			AccessoryType = AvatarEditorService:GetAccessoryType(avatarAssetType),
			Order = #accessories + 1,
			IsLayered = avatarAssetType.Value >= 64,
		})
		description:SetAccessories(accessories, true)
		humanoid:ApplyDescriptionAsync(description)
		return true
	end)
	if description then
		description:Destroy()
	end
	if not success then
		warn(string.format("[CatalogService] Catalog try-on failed: %s", tostring(appliedOrProblem)))
		return false, "TRY_ON_FAILED"
	end
	if character ~= player.Character then
		return false, "CHARACTER_UNAVAILABLE"
	end
	-- Already-worn assets (e.g. the client hasn't caught up to a HumanoidDescription
	-- applied in a previous session) short-circuit above without changing anything --
	-- don't count that no-op as a real try-on in stats/analytics.
	if appliedOrProblem then
		self:_Remember(player, before)
		self.profiles:Mutate(player, function(profile)
			profile.stats.catalogTryOns = (profile.stats.catalogTryOns or 0) + 1
		end)
		self.analytics:Custom(player, "CatalogItemTried", 1, { assetType = payload.avatarAssetType })
	end
	return true, {}
end

function CatalogService:Untry(player: Player, payload: any): (boolean, any)
	if
		type(payload) ~= "table"
		or type(payload.assetId) ~= "number"
		or payload.assetId <= 0
		or payload.assetId % 1 ~= 0
	then
		return false, "INVALID_REQUEST"
	end
	local assetId = math.floor(payload.assetId)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "CHARACTER_UNAVAILABLE"
	end
	local before = nil
	local description: any = nil
	local success, problem = pcall(function()
		description = humanoid:GetAppliedDescription()
		before = AvatarLook.Capture(description)
		local removed = false
		for _, property in CLASSIC do
			if (description :: any)[property] == assetId then
				(description :: any)[property] = 0
				removed = true
			end
		end
		local accessories = description:GetAccessories(true)
		local filtered = {}
		for _, accessory in accessories do
			if accessory.AssetId ~= assetId then
				table.insert(filtered, accessory)
			else
				removed = true
			end
		end
		if not removed then
			return false
		end
		description:SetAccessories(filtered, true)
		humanoid:ApplyDescriptionAsync(description)
		return true
	end)
	if description then
		description:Destroy()
	end
	if not success then
		warn(string.format("[CatalogService] Catalog un-equip failed: %s", tostring(problem)))
		return false, "UNEQUIP_FAILED"
	end
	if character ~= player.Character then
		return false, "CHARACTER_UNAVAILABLE"
	end
	if problem then
		self:_Remember(player, before)
	end
	return true, {}
end

function CatalogService:Reset(player: Player): (boolean, any)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "CHARACTER_UNAVAILABLE"
	end
	local success, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
	end)
	if not success then
		return false, "AVATAR_UNAVAILABLE"
	end
	if character ~= player.Character then
		description:Destroy()
		return false, "CHARACTER_UNAVAILABLE"
	end
	local before = nil
	local applied = pcall(function()
		before = AvatarLook.Read(humanoid)
		humanoid:ApplyDescriptionAsync(description)
	end)
	description:Destroy()
	if not applied then
		return false, "TRY_ON_FAILED"
	end
	if character ~= player.Character then
		return false, "CHARACTER_UNAVAILABLE"
	end
	self:_Remember(player, before)
	return true, {}
end

return CatalogService
