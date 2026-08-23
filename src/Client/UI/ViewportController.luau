--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local AccessoryFit = require(ReplicatedStorage:WaitForChild("AccessoryFit"))

local ViewportController = {}
ViewportController.__index = ViewportController

local nextControllerId = 0

local DEFAULT_FOCUS = Vector3.new(0, 1.15, 0)

local function prepareInstance(instance: Instance)
	if instance:IsA("LuaSourceContainer") then
		instance:Destroy()
	elseif instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
		instance.CanTouch = false
	end
end

local function prepare(root: Instance)
	prepareInstance(root)
	for _, descendant in root:GetDescendants() do
		prepareInstance(descendant)
	end
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

function ViewportController.new(viewport: ViewportFrame)
	nextControllerId += 1
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
		zoomActionName = `ForgeViewportZoom_{nextControllerId}`,
		scrollFrame = viewport:FindFirstAncestorWhichIsA("ScrollingFrame") :: ScrollingFrame?,
		scrollRestore = nil :: boolean?,
		connections = {} :: { RBXScriptConnection },
		destroyed = false,
	}, ViewportController)
	self:_UpdateCamera()

	local function connect(signal: RBXScriptSignal, callback: (...any) -> ())
		table.insert(self.connections, signal:Connect(callback))
	end
	local function setPageScrollLocked(locked: boolean)
		local scrollFrame = self.scrollFrame
		if not scrollFrame or not scrollFrame.Parent then
			return
		end
		if locked and self.scrollRestore == nil then
			self.scrollRestore = scrollFrame.ScrollingEnabled
			scrollFrame.ScrollingEnabled = false
		elseif not locked and self.scrollRestore ~= nil then
			scrollFrame.ScrollingEnabled = self.scrollRestore
			self.scrollRestore = nil
		end
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
	ContextActionService:BindActionAtPriority(
		self.zoomActionName,
		function(_actionName: string, inputState: Enum.UserInputState, input: InputObject)
			local point = Vector2.new(input.Position.X, input.Position.Y)
			if
				self.destroyed
				or input.UserInputType ~= Enum.UserInputType.MouseWheel
				or not pointInsideVisibleBounds(viewport, point)
			then
				return Enum.ContextActionResult.Pass
			end
			setPageScrollLocked(true)
			if inputState == Enum.UserInputState.Change then
				self.distance = math.clamp(self.distance - input.Position.Z * 0.85, 4.25, 14)
				self:_UpdateCamera()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 1,
		Enum.UserInputType.MouseWheel
	)
	connect(UserInputService.InputChanged, function(input: InputObject)
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
		local player = Players.LocalPlayer
		local success, avatar = pcall(function()
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				return Players:CreateHumanoidModelFromDescriptionAsync(
					humanoid:GetAppliedDescription(),
					humanoid.RigType
				)
			end
			return Players:CreateHumanoidModelFromUserIdAsync(player.UserId)
		end)
		if success and avatar then
			if not self.destroyed and viewport.Parent then
				prepare(avatar)
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
	prepare(handle)
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
	ContextActionService:UnbindAction(self.zoomActionName)
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
