--!strict

local AssetService = game:GetService("AssetService")
local AvatarCreationService = game:GetService("AvatarCreationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local ItemService = {}
ItemService.__index = ItemService

local ATTACHMENTS = {
	Hat = "HatAttachment",
	HairAccessory = "HairAttachment",
	FaceAccessory = "FaceFrontAttachment",
	NeckAccessory = "NeckAttachment",
	ShoulderAccessory = "RightShoulderAttachment",
	FrontAccessory = "BodyFrontAttachment",
	BackAccessory = "BodyBackAttachment",
	WaistAccessory = "WaistFrontAttachment",
}

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

function ItemService.new(profileService: any, playerStateService: any, push: (Player, string, any) -> ())
	return setmetatable({
		profiles = profileService,
		playerStates = playerStateService,
		push = push,
		assetCache = {} :: { [number]: Model },
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

function ItemService:RequestPrivateModel(player: Player, item: { [string]: any }): (boolean, any)
	if type(item.modelAssetId) ~= "number" or item.modelAssetId <= 0 then
		return false, "MODEL_UNAVAILABLE"
	end
	local success, modelOrError = self:_LoadModel(item.modelAssetId)
	if not success then
		return false, modelOrError
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
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
	local model = (modelOrError :: Model):Clone()
	model.Name = item.id
	stripUnsafe(model)
	model.Parent = cache
	return true, { cacheName = item.id }
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
	local tokenId = Config.AvatarCreationTokens[accessoryType]
	local avatarAssetType = AVATAR_ASSET_ENUMS[accessoryType]
	if type(tokenId) ~= "string" or tokenId == "" or not avatarAssetType then
		return false, "CREATION_TOKEN_NOT_CONFIGURED"
	end
	local success, accessoryOrError = self:_CreateAccessory(item, true)
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
			warn(string.format("[ItemService] UGC validation failed: %s", tostring(validationMessage)))
			accessory:Destroy()
			return false, "UGC_VALIDATION_FAILED"
		end
	end

	local promptSuccess, result, resultMessage = pcall(function()
		return AvatarCreationService:PromptCreateAvatarAssetAsync(tokenId, player, accessory, avatarAssetType)
	end)
	if not promptSuccess then
		accessory:Destroy()
		warn(`[ItemService] Avatar creation prompt failed: {result}`)
		return false, "AVATAR_CREATION_UNAVAILABLE"
	end
	if result ~= Enum.PromptCreateAssetResult.Success then
		accessory:Destroy()
		warn(string.format("[ItemService] Avatar creation was not completed: %s", tostring(resultMessage)))
		return false, "AVATAR_CREATION_REJECTED"
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

function ItemService:_LoadModel(assetId: number): (boolean, Model | string)
	local cached = self.assetCache[assetId]
	if cached then
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
			self.assetCache[assetId] = model
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

function ItemService:_CreateAccessory(item: { [string]: any }, editable: boolean): (boolean, Accessory | string)
	local callSuccess, creationSuccess, accessoryOrProblem = pcall(function()
		return self:_BuildAccessory(item, editable)
	end)
	if not callSuccess then
		warn(`[ItemService] Accessory preparation crashed for {item.id}: {creationSuccess}`)
		return false, "ACCESSORY_PREPARATION_FAILED"
	end
	return creationSuccess, accessoryOrProblem
end

function ItemService:_BuildAccessory(item: { [string]: any }, editable: boolean): (boolean, Accessory | string)
	local success, modelOrError = self:_LoadModel(item.modelAssetId)
	if not success then
		return false, modelOrError
	end
	local model = modelOrError :: Model
	local source = model:FindFirstChildWhichIsA("MeshPart", true)
	if not source then
		model:Destroy()
		return false, "MESH_NOT_FOUND"
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
			local textureUri = source.TextureID
			local oldSurface = source:FindFirstChildWhichIsA("SurfaceAppearance")
			if oldSurface and oldSurface.ColorMap ~= "" then
				textureUri = oldSurface.ColorMap
			end
			if textureUri ~= "" then
				local editableImage = AssetService:CreateEditableImageAsync(Content.fromUri(textureUri))
				if editableImage then
					local surface = AssetService:CreateSurfaceAppearanceAsync({
						ColorMap = Content.fromObject(editableImage),
					})
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
	handle.Massless = true
	handle.Material = Enum.Material.Plastic
	handle.Transparency = 0
	handle.Color = Color3.new(1, 1, 1)
	local scale = item.fit.scale
	handle.Size = Vector3.new(handle.Size.X * scale.x, handle.Size.Y * scale.y, handle.Size.Z * scale.z)
	for _, child in handle:GetChildren() do
		if not child:IsA("SurfaceAppearance") then
			child:Destroy()
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = ATTACHMENTS[item.fit.accessoryType] or "HatAttachment"
	local position = item.fit.position
	local rotation = item.fit.rotation
	local desiredOffset = CFrame.new(position.x, position.y, position.z)
		* CFrame.Angles(math.rad(rotation.x), math.rad(rotation.y), math.rad(rotation.z))
	attachment.CFrame = desiredOffset:Inverse()
	attachment.Parent = handle

	local accessory = Instance.new("Accessory")
	accessory.Name = item.name
	accessory.AccessoryType = ACCESSORY_ENUMS[item.fit.accessoryType] or Enum.AccessoryType.Hat
	handle.Parent = accessory
	return true, accessory
end

return ItemService
