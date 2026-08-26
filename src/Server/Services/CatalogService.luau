--!strict

local AvatarEditorService = game:GetService("AvatarEditorService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

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
}

function CatalogService.new(profileService: any, playerStateService: any, analyticsService: any)
	return setmetatable({
		profiles = profileService,
		playerStates = playerStateService,
		analytics = analyticsService,
	}, CatalogService)
end

function CatalogService:TryOn(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" or type(payload.assetId) ~= "number" or payload.assetId <= 0 then
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
	local success, problem = pcall(function()
		local description = humanoid:GetAppliedDescription()
		local accessories = description:GetAccessories(true)
		table.insert(accessories, {
			AssetId = assetId,
			AccessoryType = AvatarEditorService:GetAccessoryType(avatarAssetType),
			Order = #accessories + 1,
		})
		description:SetAccessories(accessories, true)
		humanoid:ApplyDescriptionAsync(description)
	end)
	if not success then
		warn(string.format("[CatalogService] Catalog try-on failed: %s", tostring(problem)))
		return false, "TRY_ON_FAILED"
	end
	self.profiles:Mutate(player, function(profile)
		profile.stats.catalogTryOns = (profile.stats.catalogTryOns or 0) + 1
	end)
	self.analytics:Custom(player, "CatalogItemTried", 1, { assetType = payload.avatarAssetType })
	return true, {}
end

function CatalogService:Untry(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" or type(payload.assetId) ~= "number" or payload.assetId <= 0 then
		return false, "INVALID_REQUEST"
	end
	local assetId = math.floor(payload.assetId)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "CHARACTER_UNAVAILABLE"
	end
	local success, problem = pcall(function()
		local description = humanoid:GetAppliedDescription()
		local accessories = description:GetAccessories(true)
		local filtered = {}
		for _, accessory in accessories do
			if accessory.AssetId ~= assetId then
				table.insert(filtered, accessory)
			end
		end
		description:SetAccessories(filtered, true)
		humanoid:ApplyDescriptionAsync(description)
	end)
	if not success then
		warn(string.format("[CatalogService] Catalog un-equip failed: %s", tostring(problem)))
		return false, "UNEQUIP_FAILED"
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
	humanoid:ApplyDescriptionAsync(description)
	return true, {}
end

return CatalogService
