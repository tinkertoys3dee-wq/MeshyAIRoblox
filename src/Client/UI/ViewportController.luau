--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local AccessoryFit = require(ReplicatedStorage:WaitForChild("AccessoryFit"))

local ViewportController = {}
ViewportController.__index = ViewportController

local DEFAULT_FOCUS = Vector3.new(0, 1.15, 0)
local MIN_CAMERA_DISTANCE = 4.25
local MAX_CAMERA_DISTANCE = 14

local function stripUnsafe(instance: Instance)
	if instance:IsA("LuaSourceContainer") then
		instance:Destroy()
	end
end

local function prepareAvatar(root: Model)
	stripUnsafe(root)
	for _, descendant in root:GetDescendants() do
		stripUnsafe(descendant)
		if descendant:IsA("BasePart") then
			-- Multiple anchored parts split a welded character into independent
			-- assemblies. Anchor only the root so Motor6Ds and AccessoryWelds keep
			-- every pre-existing hat/back accessory in its real worn position.
			descendant.Anchored = descendant.Name == "HumanoidRootPart"
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
end

local function prepareStandalonePart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

local function cloneCurrentCharacter(player: Player): Model?
	local character = player.Character
	if not character then
		return nil
	end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local success, clone = pcall(function()
		return character:Clone()
	end)
	character.Archivable = wasArchivable
	if success and clone and clone:IsA("Model") then
		return clone
	end
	return nil
end

local function clampFocus(focus: Vector3): Vector3
	return Vector3.new(math.clamp(focus.X, -6, 6), math.clamp(focus.Y, -4, 7), math.clamp(focus.Z, -6, 6))
end

local function pointInsideVisibleBounds(gui: GuiObject, point: Vector2): boolean
	if not gui.Visible then
		return false
	end
	local minimum = gui.AbsolutePosition
	local maximum = minimum + gui.AbsoluteSize
	local ancestor = gui.Parent
	while ancestor do
		if ancestor:IsA("GuiObject") then
			if not ancestor.Visible then
				return false
			end
			if ancestor.ClipsDescendants then
				local ancestorMinimum = ancestor.AbsolutePosition
				local ancestorMaximum = ancestorMinimum + ancestor.AbsoluteSize
				minimum = Vector2.new(math.max(minimum.X, ancestorMinimum.X), math.max(minimum.Y, ancestorMinimum.Y))
				maximum = Vector2.new(math.min(maximum.X, ancestorMaximum.X), math.min(maximum.Y, ancestorMaximum.Y))
			end
		end
		ancestor = ancestor.Parent
	end
	return point.X >= minimum.X and point.X <= maximum.X and point.Y >= minimum.Y and point.Y <= maximum.Y
end

function ViewportController.new(viewport: ViewportFrame, excludedForgeItemId: string?, sourcePlayer: Player?)
	local world = Instance.new("WorldModel")
	world.Name = "ForgePreviewWorld"
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Active = true
	viewport.Ambient = Color3.fromRGB(246, 247, 255)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-0.8, -0.45, -0.55).Unit
	viewport.ImageColor3 = Color3.new(1, 1, 1)
	viewport.ImageTransparency = 0
	local self = setmetatable({
		viewport = viewport,
		world = world,
		camera = camera,
		accessory = nil :: Model?,
		handle = nil :: MeshPart?,
		baseHandleSize = Vector3.zero,
		avatar = nil :: Model?,
		currentFit = nil :: { [string]: any }?,
		focus = DEFAULT_FOCUS,
		yaw = 0,
		pitch = -4,
		distance = 9.25,
		dragMode = nil :: string?,
		dragButton = nil :: Enum.UserInputType?,
		dragTouch = nil :: InputObject?,
		lastPointer = Vector2.zero,
		scrollFrame = viewport:FindFirstAncestorWhichIsA("ScrollingFrame") :: ScrollingFrame?,
		scrollRestore = nil :: boolean?,
		connections = {} :: { RBXScriptConnection },
		destroyed = false,
	}, ViewportController)
	self:_UpdateCamera()

	local function connect(signal: RBXScriptSignal, callback: (...any) -> ())
		table.insert(self.connections, signal:Connect(callback))
	end
	-- ScrollingFrame's own wheel-scroll response is a built-in engine
	-- behavior, not a bindable ContextActionService action, so sinking the
	-- MouseWheel input alone cannot reliably stop it from also scrolling the
	-- page underneath the viewport. Disabling ScrollingEnabled is the real
	-- lever; pinning CanvasPosition while locked is a second guard in case a
	-- wheel tick is still processed by the engine in the same input step
	-- that our lock takes effect.
	local scrollLocked = false
	local pinnedCanvasPosition = Vector2.zero
	local function setPageScrollLocked(locked: boolean)
		local scrollFrame = self.scrollFrame
		if not scrollFrame or not scrollFrame.Parent then
			return
		end
		if locked and not scrollLocked then
			scrollLocked = true
			pinnedCanvasPosition = scrollFrame.CanvasPosition
			if self.scrollRestore == nil then
				self.scrollRestore = scrollFrame.ScrollingEnabled
			end
			scrollFrame.ScrollingEnabled = false
		elseif not locked and scrollLocked then
			scrollLocked = false
			if self.scrollRestore ~= nil then
				scrollFrame.ScrollingEnabled = self.scrollRestore
				self.scrollRestore = nil
			end
		end
	end
	if self.scrollFrame then
		connect(self.scrollFrame:GetPropertyChangedSignal("CanvasPosition"), function()
			local scrollFrame = self.scrollFrame
			if scrollLocked and scrollFrame and scrollFrame.CanvasPosition ~= pinnedCanvasPosition then
				scrollFrame.CanvasPosition = pinnedCanvasPosition
			end
		end)
	end

	connect(viewport.MouseEnter, function()
		setPageScrollLocked(true)
	end)
	connect(viewport.MouseLeave, function()
		setPageScrollLocked(false)
	end)
	connect(viewport.InputBegan, function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local shiftDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			self.dragMode = if input.UserInputType == Enum.UserInputType.MouseButton2
					or input.UserInputType == Enum.UserInputType.MouseButton3
					or shiftDown
				then "PAN"
				else "ORBIT"
			self.dragButton = input.UserInputType
			self.dragTouch = if input.UserInputType == Enum.UserInputType.Touch then input else nil
			self.lastPointer = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	connect(viewport.InputEnded, function(input: InputObject)
		if input.UserInputType == self.dragButton or input == self.dragTouch then
			self.dragMode = nil
			self.dragButton = nil
			self.dragTouch = nil
		end
	end)
	-- Zoom deliberately reads the raw UserInputService signal instead of a
	-- ContextActionService-bound action: ContextActionService actions can be
	-- sunk by another, higher-priority bound action (Roblox's own default
	-- camera controller binds MouseWheel too) before ours ever runs, which
	-- left zoom silently doing nothing. UserInputService.InputChanged always
	-- fires for every input regardless of what else is bound or focused.
	connect(UserInputService.InputChanged, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local point = Vector2.new(input.Position.X, input.Position.Y)
			if not self.destroyed and pointInsideVisibleBounds(viewport, point) then
				setPageScrollLocked(true)
				self.distance =
					math.clamp(self.distance - input.Position.Z * 0.85, MIN_CAMERA_DISTANCE, MAX_CAMERA_DISTANCE)
				self:_UpdateCamera()
			end
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local point = Vector2.new(input.Position.X, input.Position.Y)
			setPageScrollLocked(pointInsideVisibleBounds(viewport, point))
		end
		if not self.dragMode then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= self.dragTouch then
			return
		end
		local pointer = Vector2.new(input.Position.X, input.Position.Y)
		local delta = pointer - self.lastPointer
		self.lastPointer = pointer
		if self.dragMode == "PAN" then
			local viewportHeight = math.max(viewport.AbsoluteSize.Y, 1)
			local studsPerPixel = 2 * self.distance * math.tan(math.rad(self.camera.FieldOfView * 0.5)) / viewportHeight
			local movement = -self.camera.CFrame.RightVector * delta.X * studsPerPixel
				+ self.camera.CFrame.UpVector * delta.Y * studsPerPixel
			self.focus = clampFocus(self.focus + movement)
		else
			self.yaw -= delta.X * 0.42
			self.pitch = math.clamp(self.pitch - delta.Y * 0.32, -58, 58)
		end
		self:_UpdateCamera()
	end)
	connect(UserInputService.InputEnded, function(input: InputObject)
		if input.UserInputType == self.dragButton or input == self.dragTouch then
			self.dragMode = nil
			self.dragButton = nil
			self.dragTouch = nil
		end
	end)

	task.spawn(function()
		local previewPlayer = sourcePlayer or Players.LocalPlayer
		local success, avatar = pcall(function()
			local current = cloneCurrentCharacter(previewPlayer)
			if current then
				return current
			end
			local character = previewPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				return Players:CreateHumanoidModelFromDescriptionAsync(
					humanoid:GetAppliedDescription(),
					humanoid.RigType
				)
			end
			return Players:CreateHumanoidModelFromUserIdAsync(previewPlayer.UserId)
		end)
		if success and avatar then
			if not self.destroyed and viewport.Parent then
				-- The fitting handle is rendered separately so its draft transform
				-- can move live. If this exact Forge item is already worn, remove its
				-- cloned runtime copy first or the viewport would show two of it.
				if excludedForgeItemId then
					for _, child in avatar:GetChildren() do
						if child:IsA("Accessory") and child:GetAttribute("ForgeItemId") == excludedForgeItemId then
							child:Destroy()
						end
					end
				end
				prepareAvatar(avatar)
				avatar.Name = "AvatarReference"
				avatar:PivotTo(CFrame.new())
				avatar.Parent = world
				self.avatar = avatar
				if self.currentFit then
					self:ApplyFit(self.currentFit)
				end
			else
				avatar:Destroy()
			end
		end
	end)
	return self
end

function ViewportController:_UpdateCamera()
	if self.destroyed or not self.camera.Parent then
		return
	end
	local rotation = CFrame.Angles(math.rad(self.pitch), math.rad(self.yaw), 0)
	local offset = rotation:VectorToWorldSpace(Vector3.new(0, 0, -self.distance))
	self.camera.CFrame = CFrame.lookAt(self.focus + offset, self.focus)
end

function ViewportController:ResetCamera()
	self.focus = DEFAULT_FOCUS
	self.yaw = 0
	self.pitch = -4
	self.distance = 9.25
	self:_UpdateCamera()
end

function ViewportController:SetAccessory(source: Model, fit: { [string]: any })
	if self.accessory then
		self.accessory:Destroy()
	end
	self.accessory = nil
	self.handle = nil
	local sourceHandle = source:FindFirstChildWhichIsA("MeshPart", true)
	if not sourceHandle then
		return
	end
	local previewModel = Instance.new("Model")
	previewModel.Name = "ForgeAccessory"
	local handle = sourceHandle:Clone()
	for _, child in handle:GetChildren() do
		if not child:IsA("SurfaceAppearance") then
			child:Destroy()
		end
	end
	handle.Name = "Handle"
	prepareStandalonePart(handle)
	-- Match the runtime accessory's untinted appearance; imported MeshParts often
	-- retain Roblox's gray default Color even when their texture is full-color.
	handle.Material = Enum.Material.Plastic
	handle.Transparency = 0
	handle.Color = Color3.new(1, 1, 1)
	handle.Parent = previewModel
	previewModel.Parent = self.world
	self.accessory = previewModel
	self.handle = handle
	self.baseHandleSize = handle.Size
	self:ApplyFit(fit)
end

function ViewportController:ApplyFit(fit: { [string]: any })
	self.currentFit = fit
	local handle = self.handle
	local avatar = self.avatar
	if not handle or not avatar then
		return
	end
	local scale = fit.scale
	handle.Size =
		Vector3.new(self.baseHandleSize.X * scale.x, self.baseHandleSize.Y * scale.y, self.baseHandleSize.Z * scale.z)
	local avatarAttachment = AccessoryFit.FindAvatarAttachment(avatar, fit.accessoryType)
	if avatarAttachment then
		-- This is the same equation Humanoid:AddAccessory resolves when the
		-- Handle attachment is AccessoryFit.GetOffsetCFrame(fit):Inverse().
		handle.CFrame = avatarAttachment.WorldCFrame * AccessoryFit.GetOffsetCFrame(fit)
	end
end

function ViewportController:Destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.scrollFrame and self.scrollFrame.Parent and self.scrollRestore ~= nil then
		self.scrollFrame.ScrollingEnabled = self.scrollRestore
		self.scrollRestore = nil
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.world.Parent then
		self.world:Destroy()
	end
	self.accessory = nil
	self.handle = nil
	self.avatar = nil
	if self.camera.Parent then
		self.camera:Destroy()
	end
end

return ViewportController
