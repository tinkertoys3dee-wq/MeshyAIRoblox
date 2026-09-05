--!strict

local AssetService = game:GetService("AssetService")
local AvatarCreationService = game:GetService("AvatarCreationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local AccessoryBounds = require(ReplicatedStorage:WaitForChild("AccessoryBounds"))
local AccessoryFit = require(ReplicatedStorage:WaitForChild("AccessoryFit"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local AvatarLook = require(ReplicatedStorage:WaitForChild("AvatarLook"))

local ItemService = {}
ItemService.__index = ItemService

local ACCESSORY_ENUMS = {
	Hat = Enum.AccessoryType.Hat,
	HairAccessory = Enum.AccessoryType.Hair,
	FaceAccessory = Enum.AccessoryType.Face,
	NeckAccessory = Enum.AccessoryType.Neck,
	ShoulderAccessory = Enum.AccessoryType.Shoulder,
	FrontAccessory = Enum.AccessoryType.Front,
	BackAccessory = Enum.AccessoryType.Back,
	WaistAccessory = Enum.AccessoryType.Waist,
}

local AVATAR_ASSET_ENUMS = {
	Hat = Enum.AvatarAssetType.Hat,
	HairAccessory = Enum.AvatarAssetType.HairAccessory,
	FaceAccessory = Enum.AvatarAssetType.FaceAccessory,
	NeckAccessory = Enum.AvatarAssetType.NeckAccessory,
	ShoulderAccessory = Enum.AvatarAssetType.ShoulderAccessory,
	FrontAccessory = Enum.AvatarAssetType.FrontAccessory,
	BackAccessory = Enum.AvatarAssetType.BackAccessory,
	WaistAccessory = Enum.AvatarAssetType.WaistAccessory,
}

-- AvatarCreationService validates these values exactly for a rigid accessory
-- produced by CreateMeshPartAsync. Runtime accessories can remain massless,
-- but the instance passed to the creation prompt must retain upload-safe data.
local AVATAR_CREATION_HANDLE_COLOR = Color3.fromRGB(163, 162, 165)
local ASSET_CACHE_SECONDS = 45

-- Avatar Creation Tokens authorize paid publishing and should never be
-- replicated to every client through Config. Studio owners keep them in an
-- unsynced ServerStorage folder, which default.project.json preserves via
-- $keepUnknowns. Attributes and StringValues are both supported for easy
-- Creator Studio setup.
local function getCreationToken(accessoryType: string): string?
	local secrets = ServerStorage:FindFirstChild("ForgeUGCSecrets")
	if not secrets then
		return nil
	end
	local valueName = `AvatarCreationToken_{accessoryType}`
	local attribute = secrets:GetAttribute(valueName)
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end
	local value = secrets:FindFirstChild(valueName)
	if value and value:IsA("StringValue") and value.Value ~= "" then
		return value.Value
	end
	return nil
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function sanitizeVector(record: any, minimum: number, maximum: number): { x: number, y: number, z: number }?
	if type(record) ~= "table" or not finite(record.x) or not finite(record.y) or not finite(record.z) then
		return nil
	end
	return {
		x = math.clamp(record.x, minimum, maximum),
		y = math.clamp(record.y, minimum, maximum),
		z = math.clamp(record.z, minimum, maximum),
	}
end

local function stripUnsafe(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
end

local function vectorData(value: Vector3): { x: number, y: number, z: number }
	return { x = value.X, y = value.Y, z = value.Z }
end

local function textureContent(mesh: MeshPart): any?
	if mesh.TextureID ~= "" then
		return Content.fromUri(mesh.TextureID)
	end
	local surface = mesh:FindFirstChildWhichIsA("SurfaceAppearance")
	if not surface then
		return nil
	end
	if surface.ColorMap ~= "" then
		return Content.fromUri(surface.ColorMap)
	end
	-- Newer imports can populate the Content-typed property without mirroring
	-- it back into the legacy ContentId string immediately.
	local success, content = pcall(function()
		return surface.ColorMapContent
	end)
	if not success then
		return nil
	end
	local sourceSuccess, sourceType = pcall(function()
		return content.SourceType
	end)
	if not sourceSuccess or sourceType == Enum.ContentSourceType.None then
		return nil
	end
	return content
end

local function hasTextureReference(mesh: MeshPart): boolean
	return textureContent(mesh) ~= nil
end

local function itemDiagnostics(item: { [string]: any }, source: MeshPart): { [string]: any }
	local fittedSize = AccessoryBounds.GetFittedSize(source.Size, item.fit)
	local maximumSize = AccessoryBounds.GetMaximum(item.fit.accessoryType)
	local exceededAxes = if maximumSize then AccessoryBounds.ExceededAxes(fittedSize, maximumSize) else {}
	local textureReady = hasTextureReference(source)
	return {
		baseSize = vectorData(source.Size),
		fittedSize = vectorData(fittedSize),
		maximumSize = if maximumSize then vectorData(maximumSize) else nil,
		exceededAxes = exceededAxes,
		tooLarge = #exceededAxes > 0,
		textureStatus = if textureReady then "READY" else "PROCESSING",
		textureExpected = true,
		triangles = item.triangles,
		vertices = item.vertices,
		textureWidth = item.textureWidth,
		textureHeight = item.textureHeight,
	}
end

local function formatSize(value: { [string]: any }): string
	return string.format("%.2f × %.2f × %.2f", value.x, value.y, value.z)
end

local function boundsProblem(item: { [string]: any }, diagnostics: { [string]: any }): { [string]: any }
	local axes = table.concat(diagnostics.exceededAxes, ", ")
	return {
		code = "UGC_BOUNDS_TOO_LARGE",
		details = {
			diagnostics = diagnostics,
			userMessage = string.format(
				"This %s is %s studs after fit; Roblox's limit is %s. Reduce the %s scale in Fitting.",
				tostring(item.fit.accessoryType),
				formatSize(diagnostics.fittedSize),
				formatSize(diagnostics.maximumSize),
				axes
			),
		},
	}
end

local function sanitizePlatformMessage(value: any): string
	local message = string.gsub(tostring(value or ""), "[%c]", " ")
	message = string.gsub(message, "%s+", " ")
	return string.sub(message, 1, 240)
end

local function classifyValidationProblem(value: any): string
	local message = string.lower(tostring(value or ""))
	if
		string.find(message, "too large", 1, true)
		or string.find(message, "larger than", 1, true)
		or string.find(message, "bounding", 1, true)
		or string.find(message, "bounds", 1, true)
		or string.find(message, "dimension", 1, true)
		or string.find(message, "scale down", 1, true)
	then
		return "UGC_BOUNDS_TOO_LARGE"
	end
	if
		string.find(message, "moderation", 1, true)
		or string.find(message, "pending", 1, true)
		or string.find(message, "processing", 1, true)
		or string.find(message, "not yet available", 1, true)
	then
		return "UGC_MODERATION_PENDING"
	end
	if
		string.find(message, "texture", 1, true)
		or string.find(message, "color map", 1, true)
		or string.find(message, "colormap", 1, true)
	then
		return "MODEL_TEXTURE_PROCESSING"
	end
	return "UGC_VALIDATION_FAILED"
end

local function validationProblem(value: any): { [string]: any }
	local code = classifyValidationProblem(value)
	local platformMessage = sanitizePlatformMessage(value)
	local fallback = if code == "UGC_BOUNDS_TOO_LARGE"
		then "Roblox says this wearable is outside its size bounds. Check the measured X/Y/Z limits in Fitting."
		elseif
			code == "UGC_MODERATION_PENDING"
		then "Roblox is still processing or moderating this model or texture. Your item is saved; retry publishing later."
		elseif
			code == "MODEL_TEXTURE_PROCESSING"
		then "Roblox has not released this model's texture yet. Your item is saved; retry after the texture appears in Fitting."
		else "Roblox validation rejected this wearable. Adjust the fit and review the validation detail below."
	return {
		code = code,
		details = {
			userMessage = if platformMessage ~= "" then fallback .. " Roblox: " .. platformMessage else fallback,
		},
	}
end

function ItemService.new(profileService: any, playerStateService: any, push: (Player, string, any) -> ())
	return setmetatable({
		profiles = profileService,
		playerStates = playerStateService,
		push = push,
		assetCache = {} :: { [number]: Model },
		assetCacheLoadedAt = {} :: { [number]: number },
	}, ItemService)
end

function ItemService:SaveFit(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" or type(payload.itemId) ~= "string" or type(payload.fit) ~= "table" then
		return false, "INVALID_REQUEST"
	end
	local position =
		sanitizeVector(payload.fit.position, Config.Fitting.Position.Minimum, Config.Fitting.Position.Maximum)
	local rotation =
		sanitizeVector(payload.fit.rotation, Config.Fitting.Rotation.Minimum, Config.Fitting.Rotation.Maximum)
	local scale = sanitizeVector(payload.fit.scale, Config.Fitting.Scale.Minimum, Config.Fitting.Scale.Maximum)
	if not position or not rotation or not scale then
		return false, "INVALID_TRANSFORM"
	end
	local profile = self.profiles:Get(player)
	local item = profile and profile.items[payload.itemId]
	if not item then
		return false, "ITEM_NOT_FOUND"
	end
	local mutateSuccess, mutateProblem = self.profiles:Mutate(player, function(mutableProfile)
		local mutableItem = mutableProfile.items[payload.itemId]
		mutableItem.fit = {
			position = position,
			rotation = rotation,
			scale = scale,
			accessoryType = mutableItem.fit.accessoryType,
		}
		mutableItem.updatedAt = os.time()
	end)
	if not mutateSuccess then
		return false, mutateProblem or "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		return false, "SAVE_FAILED"
	end
	self.push(player, Network.PushEvents.Toast, { tone = "success", message = "Fit saved." })
	return true, { item = self.profiles:Get(player).items[payload.itemId] }
end

-- The bounding-box-derived default position (see AccessoryFit.ComputeDefaultPosition)
-- only ever runs once, automatically, at generation-completion time
-- (GenerationService:_ComputeInitialFit). Any item that already existed
-- before that fix shipped is stuck with the old all-zero position forever
-- unless something re-runs the same computation for it later -- this is
-- that "later": on-demand, from the fitting UI, against the item's real
-- mesh right now, not a guess about what it should have gotten originally.
function ItemService:ResetFitToSuggested(player: Player, itemId: any): (boolean, any)
	if type(itemId) ~= "string" then
		return false, "INVALID_REQUEST"
	end
	local profile = self.profiles:Get(player)
	local item = profile and profile.items[itemId]
	if not item then
		return false, "ITEM_NOT_FOUND"
	end
	local accessoryType = item.fit.accessoryType
	local suggested = { x = 0, y = 0, z = 0 }
	if type(item.modelAssetId) == "number" and item.modelAssetId > 0 then
		local loaded, modelOrProblem = self:_LoadModel(item.modelAssetId)
		if loaded then
			local model = modelOrProblem :: Model
			local mesh = model:FindFirstChildWhichIsA("MeshPart", true)
			if mesh then
				local ok, position = pcall(AccessoryFit.ComputeDefaultPosition, mesh, accessoryType)
				if ok and position then
					suggested = position
				end
			end
			model:Destroy()
		end
	end
	local mutateSuccess, mutateProblem = self.profiles:Mutate(player, function(mutableProfile)
		local mutableItem = mutableProfile.items[itemId]
		mutableItem.fit = {
			position = suggested,
			rotation = { x = 0, y = 0, z = 0 },
			scale = { x = 1, y = 1, z = 1 },
			accessoryType = accessoryType,
		}
		mutableItem.updatedAt = os.time()
	end)
	if not mutateSuccess then
		return false, mutateProblem or "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		return false, "SAVE_FAILED"
	end
	self.push(player, Network.PushEvents.Toast, { tone = "success", message = "Fit reset to the suggested position." })
	return true, { item = self.profiles:Get(player).items[itemId] }
end

local MAX_FIT_PRESETS = 20
local MAX_PRESET_NAME_LENGTH = 24
local MAX_OUTFITS = 12
local MAX_OUTFIT_NAME_LENGTH = 24

-- Fit presets are purely a personal convenience: saved names are never shown
-- to another player, so (unlike an item name or listing) they do not need
-- TextService filtering, only length/shape sanitizing.
function ItemService:SaveFitPreset(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" or type(payload.fit) ~= "table" then
		return false, "INVALID_REQUEST"
	end
	local accessoryType = payload.accessoryType
	if type(accessoryType) ~= "string" or not ACCESSORY_ENUMS[accessoryType] then
		return false, "INVALID_ASSET_TYPE"
	end
	local position =
		sanitizeVector(payload.fit.position, Config.Fitting.Position.Minimum, Config.Fitting.Position.Maximum)
	local rotation =
		sanitizeVector(payload.fit.rotation, Config.Fitting.Rotation.Minimum, Config.Fitting.Rotation.Maximum)
	local scale = sanitizeVector(payload.fit.scale, Config.Fitting.Scale.Minimum, Config.Fitting.Scale.Maximum)
	if not position or not rotation or not scale then
		return false, "INVALID_TRANSFORM"
	end
	local rawName = if type(payload.name) == "string" then payload.name else ""
	local name = string.match(rawName, "^%s*(.-)%s*$") or ""
	if name == "" then
		name = "Untitled fit"
	elseif #name > MAX_PRESET_NAME_LENGTH then
		name = string.sub(name, 1, MAX_PRESET_NAME_LENGTH)
	end
	local profile = self.profiles:Get(player)
	if not profile then
		return false, "PROFILE_UNAVAILABLE"
	end
	if #profile.fitPresetOrder >= MAX_FIT_PRESETS then
		return false, "FIT_PRESET_LIMIT_REACHED"
	end
	local id = self.profiles:GenerateId("preset")
	local record = {
		id = id,
		name = name,
		accessoryType = accessoryType,
		fit = { position = position, rotation = rotation, scale = scale, accessoryType = accessoryType },
		createdAt = os.time(),
	}
	local mutateSuccess, mutateProblem = self.profiles:Mutate(player, function(mutableProfile)
		mutableProfile.fitPresets[id] = record
		table.insert(mutableProfile.fitPresetOrder, id)
	end)
	if not mutateSuccess then
		return false, mutateProblem or "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		return false, "SAVE_FAILED"
	end
	return true, { preset = record }
end

function ItemService:DeleteFitPreset(player: Player, presetId: any): (boolean, any)
	if type(presetId) ~= "string" then
		return false, "INVALID_REQUEST"
	end
	local profile = self.profiles:Get(player)
	if not profile or not profile.fitPresets[presetId] then
		return false, "FIT_PRESET_NOT_FOUND"
	end
	local mutateSuccess, mutateProblem = self.profiles:Mutate(player, function(mutableProfile)
		mutableProfile.fitPresets[presetId] = nil
		local index = table.find(mutableProfile.fitPresetOrder, presetId)
		if index then
			table.remove(mutableProfile.fitPresetOrder, index)
		end
	end)
	if not mutateSuccess then
		return false, mutateProblem or "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		return false, "SAVE_FAILED"
	end
	return true, { deleted = true }
end

function ItemService:Equip(player: Player, itemId: string): (boolean, any)
	local profile = self.profiles:Get(player)
	local item = profile and profile.items[itemId]
	if not item or type(item.modelAssetId) ~= "number" or item.modelAssetId <= 0 then
		return false, "MODEL_UNAVAILABLE"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "CHARACTER_UNAVAILABLE"
	end
	local success, accessoryOrError = self:_CreateAccessory(item, false)
	if not success then
		return false, accessoryOrError
	end
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") and child:GetAttribute("ForgeItemId") == itemId then
			child:Destroy()
		end
	end
	local accessory = accessoryOrError :: Accessory
	accessory:SetAttribute("ForgeItemId", itemId)
	local addSuccess, addProblem = pcall(function()
		humanoid:AddAccessory(accessory)
	end)
	if not addSuccess then
		accessory:Destroy()
		warn(`[ItemService] Could not equip {itemId}: {addProblem}`)
		return false, "EQUIP_FAILED"
	end
	local mutateSuccess, mutateProblem = self.profiles:Mutate(player, function(mutableProfile)
		if not table.find(mutableProfile.equippedItemIds, itemId) then
			table.insert(mutableProfile.equippedItemIds, itemId)
		end
	end)
	if not mutateSuccess then
		accessory:Destroy()
		return false, mutateProblem or "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		return false, "SAVE_FAILED"
	end
	return true, { equipped = true }
end

function ItemService:Unequip(player: Player, itemId: string): (boolean, any)
	local profile = self.profiles:Get(player)
	if not profile or not profile.items[itemId] then
		return false, "ITEM_NOT_FOUND"
	end
	if not table.find(profile.equippedItemIds, itemId) then
		return false, "ITEM_NOT_EQUIPPED"
	end
	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Accessory") and child:GetAttribute("ForgeItemId") == itemId then
				child:Destroy()
			end
		end
	end
	local mutateSuccess, mutateProblem = self.profiles:Mutate(player, function(mutableProfile)
		local index = table.find(mutableProfile.equippedItemIds, itemId)
		if index then
			table.remove(mutableProfile.equippedItemIds, index)
		end
	end)
	if not mutateSuccess then
		return false, mutateProblem or "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		return false, "SAVE_FAILED"
	end
	return true, { unequipped = true }
end

-- An outfit snapshots the server-applied catalog appearance plus owned
-- Forge item IDs. Each Forge item keeps its own saved fit. Legacy outfits
-- without avatarLook still restore their custom item selection as before.
function ItemService:SaveOutfit(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" then
		return false, "INVALID_REQUEST"
	end
	local rawName = if type(payload.name) == "string" then payload.name else ""
	local name = string.match(rawName, "^%s*(.-)%s*$") or ""
	if name == "" then
		name = "Untitled outfit"
	elseif #name > MAX_OUTFIT_NAME_LENGTH then
		name = string.sub(name, 1, MAX_OUTFIT_NAME_LENGTH)
	end
	local profile = self.profiles:Get(player)
	if not profile then
		return false, "PROFILE_UNAVAILABLE"
	end
	local equippedItemIds = profile.equippedItemIds or {}
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "CHARACTER_UNAVAILABLE"
	end
	local captured, avatarLook = pcall(function()
		return AvatarLook.Read(humanoid)
	end)
	if not captured then
		return false, "AVATAR_UNAVAILABLE"
	end
	if #(profile.outfitOrder or {}) >= MAX_OUTFITS then
		return false, "OUTFIT_LIMIT_REACHED"
	end
	local id = self.profiles:GenerateId("outfit")
	local record = {
		id = id,
		name = name,
		itemIds = table.clone(equippedItemIds),
		avatarLook = avatarLook,
		createdAt = os.time(),
		updatedAt = os.time(),
	}
	local mutateSuccess, mutateProblem = self.profiles:Mutate(player, function(mutableProfile)
		mutableProfile.outfits[id] = record
		table.insert(mutableProfile.outfitOrder, 1, id)
	end)
	if not mutateSuccess then
		return false, mutateProblem or "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		self.profiles:Mutate(player, function(mutableProfile)
			mutableProfile.outfits[id] = nil
			local index = table.find(mutableProfile.outfitOrder, id)
			if index then
				table.remove(mutableProfile.outfitOrder, index)
			end
		end)
		return false, "SAVE_FAILED"
	end
	return true, { outfit = record }
end

function ItemService:DeleteOutfit(player: Player, payload: any): (boolean, any)
	local outfitId = if type(payload) == "table" then payload.outfitId else payload
	if type(outfitId) ~= "string" then
		return false, "INVALID_REQUEST"
	end
	local profile = self.profiles:Get(player)
	if not profile or not profile.outfits[outfitId] then
		return false, "OUTFIT_NOT_FOUND"
	end
	local mutateSuccess, mutateProblem = self.profiles:Mutate(player, function(mutableProfile)
		mutableProfile.outfits[outfitId] = nil
		local index = table.find(mutableProfile.outfitOrder, outfitId)
		if index then
			table.remove(mutableProfile.outfitOrder, index)
		end
	end)
	if not mutateSuccess then
		return false, mutateProblem or "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		return false, "SAVE_FAILED"
	end
	return true, { deleted = true }
end

-- Re-equipping an outfit reproduces exactly the look it was saved with:
-- anything currently worn that the outfit doesn't include gets unequipped
-- first, rather than layering the outfit's items on top of whatever else
-- happens to be equipped right now. Best-effort on the outfit's own items --
-- one since-deleted or since-unpublished item does not block the rest.
function ItemService:EquipOutfit(player: Player, payload: any): (boolean, any)
	if type(payload) ~= "table" or type(payload.outfitId) ~= "string" then
		return false, "INVALID_REQUEST"
	end
	local profile = self.profiles:Get(player)
	local outfit = profile and profile.outfits[payload.outfitId]
	if not outfit then
		return false, "OUTFIT_NOT_FOUND"
	end
	local character = player.Character
	if not character or not character:FindFirstChildOfClass("Humanoid") then
		return false, "CHARACTER_UNAVAILABLE"
	end
	if outfit.avatarLook then
		local applied = pcall(function()
			local description = AvatarLook.Description(outfit.avatarLook)
			local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
			local ok, problem = pcall(function()
				humanoid:ApplyDescriptionAsync(description)
			end)
			description:Destroy()
			if not ok then
				error(problem)
			end
		end)
		if not applied then
			return false, "TRY_ON_FAILED"
		end
	end
	if character ~= player.Character then
		return false, "CHARACTER_UNAVAILABLE"
	end
	local target: { [string]: boolean } = {}
	for _, itemId in outfit.itemIds do
		target[itemId] = true
	end
	for _, itemId in table.clone(profile.equippedItemIds or {}) do
		if outfit.avatarLook or not target[itemId] then
			self:Unequip(player, itemId)
		end
	end
	local equippedCount = 0
	local skipped = 0
	for _, itemId in outfit.itemIds do
		local currentProfile = self.profiles:Get(player)
		local alreadyEquipped = not outfit.avatarLook
			and currentProfile ~= nil
			and table.find(currentProfile.equippedItemIds, itemId) ~= nil
		if alreadyEquipped then
			equippedCount += 1
		else
			local success = self:Equip(player, itemId)
			if success then
				equippedCount += 1
			else
				skipped += 1
			end
		end
	end
	if equippedCount == 0 and not outfit.avatarLook then
		return false, "OUTFIT_ITEMS_UNAVAILABLE"
	end
	local currentProfile = self.profiles:Get(player)
	if not currentProfile then
		return false, "PROFILE_UNAVAILABLE"
	end
	return true,
		{
			equippedCount = equippedCount,
			skipped = skipped,
			equippedItemIds = table.clone(currentProfile.equippedItemIds),
		}
end

function ItemService:RestoreEquipped(player: Player)
	local profile = self.profiles:Get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not profile or not humanoid then
		return
	end
	for _, itemId in profile.equippedItemIds do
		local item = profile.items[itemId]
		if item and type(item.modelAssetId) == "number" and item.modelAssetId > 0 then
			local alreadyEquipped = false
			for _, child in character:GetChildren() do
				if child:IsA("Accessory") and child:GetAttribute("ForgeItemId") == itemId then
					alreadyEquipped = true
					break
				end
			end
			if not alreadyEquipped then
				local success, accessoryOrError = self:_CreateAccessory(item, false)
				if success then
					local accessory = accessoryOrError :: Accessory
					accessory:SetAttribute("ForgeItemId", itemId)
					local addSuccess, addProblem = pcall(function()
						humanoid:AddAccessory(accessory)
					end)
					if not addSuccess then
						accessory:Destroy()
						warn(`[ItemService] Could not restore {itemId}: {addProblem}`)
					end
				end
			end
		end
	end
end

function ItemService:TryOn(player: Player, item: { [string]: any }): (boolean, any)
	if not self.playerStates:Get(player).contentSharingAllowed then
		return false, "CONTENT_SHARING_DISABLED"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "CHARACTER_UNAVAILABLE"
	end
	local success, accessoryOrError = self:_CreateAccessory(item, false)
	if not success then
		return false, accessoryOrError
	end
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") and child:GetAttribute("ForgeCommunityTryOn") then
			child:Destroy()
		end
	end
	local accessory = accessoryOrError :: Accessory
	accessory:SetAttribute("ForgeCommunityTryOn", true)
	accessory:SetAttribute("ForgeItemId", item.id)
	local addSuccess, addProblem = pcall(function()
		humanoid:AddAccessory(accessory)
	end)
	if not addSuccess then
		accessory:Destroy()
		warn(`[ItemService] Community try-on failed for {item.id}: {addProblem}`)
		return false, "TRY_ON_FAILED"
	end
	return true, { triedOn = true }
end

function ItemService:ClearCommunityTryOn(player: Player): (boolean, any)
	local character = player.Character
	if not character then
		return false, "CHARACTER_UNAVAILABLE"
	end
	local removed = false
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") and child:GetAttribute("ForgeCommunityTryOn") then
			child:Destroy()
			removed = true
		end
	end
	return true, { removed = removed }
end

function ItemService:RequestPrivateModel(player: Player, item: { [string]: any }): (boolean, any)
	if type(item.modelAssetId) ~= "number" or item.modelAssetId <= 0 then
		return false, "MODEL_UNAVAILABLE"
	end
	-- Always ask Roblox for a fresh copy here. A model upload can become
	-- loadable before its embedded texture is released by moderation/CDN; an
	-- indefinite server cache would otherwise keep handing every fitting view
	-- that first gray copy even after Roblox finished processing it.
	local success, modelOrError = self:_LoadModel(item.modelAssetId, true)
	if not success then
		return false, modelOrError
	end
	local sourceModel = modelOrError :: Model
	local source = sourceModel:FindFirstChildWhichIsA("MeshPart", true)
	if not source then
		sourceModel:Destroy()
		return false, "MESH_NOT_FOUND"
	end
	local diagnostics = itemDiagnostics(item, source)
	if diagnostics.textureStatus ~= "READY" then
		self:_InvalidateModel(item.modelAssetId)
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		sourceModel:Destroy()
		return false, "PLAYER_GUI_UNAVAILABLE"
	end
	local cache = playerGui:FindFirstChild("ForgeAssetCache")
	if not cache then
		cache = Instance.new("Folder")
		cache.Name = "ForgeAssetCache"
		cache.Parent = playerGui
	end
	local existing = cache:FindFirstChild(item.id)
	if existing then
		existing:Destroy()
	end
	local model = sourceModel:Clone()
	sourceModel:Destroy()
	model.Name = item.id
	stripUnsafe(model)
	model.Parent = cache
	return true, { cacheName = item.id, diagnostics = diagnostics }
end

function ItemService:Publish(player: Player, itemId: string): (boolean, any)
	if not self.playerStates:Get(player).contentSharingAllowed then
		return false, "CONTENT_SHARING_DISABLED"
	end
	local profile = self.profiles:Get(player)
	local item = profile and profile.items[itemId]
	if not item or item.ownerUserId ~= player.UserId or not item.canPublish then
		return false, "ITEM_NOT_PUBLISHABLE"
	end
	if type(item.publishedAssetId) == "number" and item.publishedAssetId > 0 then
		return true, { assetId = item.publishedAssetId, alreadyPublished = true }
	end
	local accessoryType = item.fit.accessoryType
	local tokenId = getCreationToken(accessoryType)
	local avatarAssetType = AVATAR_ASSET_ENUMS[accessoryType]
	if type(tokenId) ~= "string" or tokenId == "" or not avatarAssetType then
		return false, "CREATION_TOKEN_NOT_CONFIGURED"
	end
	local success, accessoryOrError = self:_CreateAccessory(item, true, true)
	if not success then
		return false, accessoryOrError
	end
	local accessory = accessoryOrError :: Accessory

	-- Roblox exposes ValidateUGCAccessoryAsync only in Studio. The live creation
	-- prompt runs platform validation itself, so never call the Studio-only API
	-- on production servers.
	if RunService:IsStudio() then
		local validationSuccess, isValid, validationMessage = pcall(function()
			return AvatarCreationService:ValidateUGCAccessoryAsync(player, accessory, ACCESSORY_ENUMS[accessoryType])
		end)
		if not validationSuccess or not isValid then
			local validationProblemMessage = if validationSuccess then validationMessage else isValid
			warn(string.format("[ItemService] UGC validation failed: %s", tostring(validationProblemMessage)))
			accessory:Destroy()
			return false, validationProblem(validationProblemMessage)
		end
	end

	local promptSuccess, result, resultMessage = pcall(function()
		return AvatarCreationService:PromptCreateAvatarAssetAsync(tokenId, player, accessory, avatarAssetType)
	end)
	if not promptSuccess then
		accessory:Destroy()
		warn(`[ItemService] Avatar creation prompt failed: {result}`)
		local classified = validationProblem(result)
		if classified.code ~= "UGC_VALIDATION_FAILED" then
			return false, classified
		end
		return false, "AVATAR_CREATION_UNAVAILABLE"
	end
	if result ~= Enum.PromptCreateAssetResult.Success then
		accessory:Destroy()
		warn(string.format("[ItemService] Avatar creation was not completed: %s", tostring(resultMessage)))
		if string.find(string.lower(tostring(result)), "cancel", 1, true) then
			return false, "AVATAR_CREATION_CANCELLED"
		end
		return false, validationProblem(resultMessage)
	end
	accessory:Destroy()
	local assetId = tonumber(resultMessage)
	if not assetId or assetId <= 0 then
		warn(string.format("[ItemService] Avatar creation returned an invalid asset id: %s", tostring(resultMessage)))
		return false, "AVATAR_CREATION_BAD_RESPONSE"
	end
	local mutateSuccess, mutateProblem = self.profiles:Mutate(player, function(mutableProfile)
		mutableProfile.items[itemId].publishedAssetId = assetId
		mutableProfile.items[itemId].updatedAt = os.time()
		mutableProfile.stats.itemsPublished += 1
	end)
	if not mutateSuccess then
		return false, mutateProblem or "PROFILE_UNAVAILABLE"
	end
	if not self.profiles:Save(player) then
		warn(string.format("[ItemService] Published asset %s is awaiting a profile save retry", tostring(assetId)))
	end
	return true, { assetId = assetId }
end

function ItemService:_InvalidateModel(assetId: number)
	local cached = self.assetCache[assetId]
	if cached then
		cached:Destroy()
	end
	self.assetCache[assetId] = nil
	self.assetCacheLoadedAt[assetId] = nil
end

function ItemService:_LoadModel(assetId: number, forceRefresh: boolean?): (boolean, Model | string)
	local cached = self.assetCache[assetId]
	local loadedAt = self.assetCacheLoadedAt[assetId] or 0
	if cached and not forceRefresh and os.clock() - loadedAt < ASSET_CACHE_SECONDS then
		return true, cached:Clone()
	end
	local lastProblem: any = "No model returned"
	for attempt = 1, 4 do
		local success, loaded = pcall(function()
			return AssetService:LoadAssetAsync(assetId)
		end)
		if success and typeof(loaded) == "Instance" and loaded:IsA("Model") then
			local model = loaded :: Model
			stripUnsafe(model)
			model.Parent = nil
			self:_InvalidateModel(assetId)
			self.assetCache[assetId] = model
			self.assetCacheLoadedAt[assetId] = os.clock()
			return true, model:Clone()
		end
		lastProblem = loaded
		if attempt < 4 then
			-- Open Cloud uploads can be acknowledged before the asset is available
			-- to live servers. A short bounded retry keeps the first fit/equip click
			-- from failing during that propagation window.
			task.wait(attempt)
		end
	end
	warn(`[ItemService] Could not load asset {assetId} after retries: {lastProblem}`)
	return false, "ASSET_STILL_PROCESSING"
end

-- Exposed for GenerationService: it needs a freshly generated model's real
-- mesh geometry once, at generation-completion time, to seat the item's
-- default fit (see AccessoryFit.ComputeDefaultPosition). Reusing this loader
-- means that lookup shares the same asset cache and Open Cloud propagation
-- retry as every other model load instead of duplicating that logic.
function ItemService:LoadModelForInspection(assetId: number): (boolean, Model | string)
	return self:_LoadModel(assetId)
end

function ItemService:_CreateAccessory(
	item: { [string]: any },
	editable: boolean,
	forceRefresh: boolean?
): (boolean, any)
	local callSuccess, creationSuccess, accessoryOrProblem = pcall(function()
		return self:_BuildAccessory(item, editable, forceRefresh)
	end)
	if not callSuccess then
		warn(`[ItemService] Accessory preparation crashed for {item.id}: {creationSuccess}`)
		return false, "ACCESSORY_PREPARATION_FAILED"
	end
	return creationSuccess, accessoryOrProblem
end

function ItemService:_BuildAccessory(item: { [string]: any }, editable: boolean, forceRefresh: boolean?): (boolean, any)
	local success, modelOrError = self:_LoadModel(item.modelAssetId, forceRefresh)
	if not success then
		return false, modelOrError
	end
	local model = modelOrError :: Model
	local source = model:FindFirstChildWhichIsA("MeshPart", true)
	if not source then
		model:Destroy()
		return false, "MESH_NOT_FOUND"
	end
	local diagnostics = itemDiagnostics(item, source)
	if editable and diagnostics.tooLarge then
		model:Destroy()
		return false, boundsProblem(item, diagnostics)
	end
	if editable and diagnostics.textureStatus ~= "READY" then
		model:Destroy()
		self:_InvalidateModel(item.modelAssetId)
		return false,
			{
				code = "MODEL_TEXTURE_PROCESSING",
				details = {
					diagnostics = diagnostics,
					userMessage = "Roblox has not released this model's generated texture yet. Your item is saved; retry after the texture appears in Fitting.",
				},
			}
	end

	local handle: MeshPart
	if editable then
		local editSuccess, editableHandle = pcall(function()
			local editableMesh = AssetService:CreateEditableMeshAsync(Content.fromUri(source.MeshId))
			if not editableMesh then
				error("EditableMesh memory budget exceeded")
			end
			local created = AssetService:CreateMeshPartAsync(Content.fromObject(editableMesh), {
				CollisionFidelity = Enum.CollisionFidelity.Hull,
			})
			local sourceTexture = textureContent(source)
			if sourceTexture then
				local editableImage = AssetService:CreateEditableImageAsync(sourceTexture)
				if editableImage then
					local surface = AssetService:CreateSurfaceAppearanceAsync({
						ColorMap = Content.fromObject(editableImage),
					})
					surface.AlphaMode = Enum.AlphaMode.Overlay
					surface.Parent = created
				end
			end
			return created
		end)
		if not editSuccess then
			model:Destroy()
			warn(`[ItemService] Editable asset preparation failed: {editableHandle}`)
			return false, "EDITABLE_ASSET_FAILED"
		end
		handle = editableHandle
	else
		handle = source:Clone()
	end
	model:Destroy()

	handle.Name = "Handle"
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = not editable
	handle.Material = Enum.Material.Plastic
	handle.Transparency = 0
	handle.Color = if editable then AVATAR_CREATION_HANDLE_COLOR else Color3.new(1, 1, 1)
	local scale = item.fit.scale
	handle.Size = Vector3.new(handle.Size.X * scale.x, handle.Size.Y * scale.y, handle.Size.Z * scale.z)
	for _, child in handle:GetChildren() do
		if not child:IsA("SurfaceAppearance") then
			child:Destroy()
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = AccessoryFit.GetAttachmentName(item.fit.accessoryType)
	attachment.CFrame = AccessoryFit.GetHandleAttachmentCFrame(item.fit)
	attachment.Parent = handle
	local scaleType = Instance.new("StringValue")
	scaleType.Name = "AvatarPartScaleType"
	scaleType.Value = "ProportionsNormal"
	scaleType.Parent = handle

	local accessory = Instance.new("Accessory")
	accessory.Name = item.name
	accessory.AccessoryType = ACCESSORY_ENUMS[item.fit.accessoryType] or Enum.AccessoryType.Hat
	handle.Parent = accessory
	return true, accessory
end

return ItemService
