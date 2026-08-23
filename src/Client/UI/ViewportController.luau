--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local ViewportController = {}
ViewportController.__index = ViewportController

local PREVIEW_ANCHORS = {
	Hat = Vector3.new(0, 3.25, 0),
	HairAccessory = Vector3.new(0, 3.05, 0.05),
	FaceAccessory = Vector3.new(0, 2.55, -0.5),
	NeckAccessory = Vector3.new(0, 1.85, 0),
	ShoulderAccessory = Vector3.new(0.9, 1.75, 0),
	FrontAccessory = Vector3.new(0, 1.05, -0.48),
	BackAccessory = Vector3.new(0, 1.1, 0.48),
	WaistAccessory = Vector3.new(0, 0.05, 0),
}

local function prepare(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
end

function ViewportController.new(viewport: ViewportFrame)
	local world = Instance.new("WorldModel")
	world.Name = "ForgePreviewWorld"
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Active = true
	viewport.Ambient = Color3.fromRGB(218, 224, 255)
	viewport.LightColor = Color3.fromRGB(255, 249, 235)
	viewport.LightDirection = Vector3.new(-0.8, -0.65, -0.4)
	local self = setmetatable({
		viewport = viewport,
		world = world,
		camera = camera,
		accessory = nil :: Model?,
		focus = Vector3.new(0, 1.15, 0),
		yaw = 0,
		pitch = -4,
		distance = 9.25,
		dragging = false,
		dragTouch = nil :: InputObject?,
		lastPointer = Vector2.zero,
		connections = {} :: { RBXScriptConnection },
		destroyed = false,
	}, ViewportController)
	self:_UpdateCamera()

	local function connect(signal: RBXScriptSignal, callback: (...any) -> ())
		table.insert(self.connections, signal:Connect(callback))
	end

	connect(viewport.InputBegan, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self.dragging = true
			self.dragTouch = if input.UserInputType == Enum.UserInputType.Touch then input else nil
			self.lastPointer = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	connect(viewport.InputEnded, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input == self.dragTouch then
			self.dragging = false
			self.dragTouch = nil
		end
	end)
	connect(viewport.InputChanged, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			self.distance = math.clamp(self.distance - input.Position.Z * 0.85, 4.25, 14)
			self:_UpdateCamera()
		end
	end)
	connect(UserInputService.InputChanged, function(input: InputObject)
		if not self.dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= self.dragTouch then
			return
		end
		local pointer = Vector2.new(input.Position.X, input.Position.Y)
		local delta = pointer - self.lastPointer
		self.lastPointer = pointer
		self.yaw -= delta.X * 0.42
		self.pitch = math.clamp(self.pitch - delta.Y * 0.32, -58, 58)
		self:_UpdateCamera()
	end)
	connect(UserInputService.InputEnded, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input == self.dragTouch then
			self.dragging = false
			self.dragTouch = nil
		end
	end)

	task.spawn(function()
		local player = Players.LocalPlayer
		local success, avatar = pcall(function()
			return Players:CreateHumanoidModelFromUserIdAsync(player.UserId)
		end)
		if success and avatar then
			if not self.destroyed and viewport.Parent then
				prepare(avatar)
				avatar.Name = "AvatarReference"
				avatar:PivotTo(CFrame.new())
				avatar.Parent = world
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
	self.yaw = 0
	self.pitch = -4
	self.distance = 9.25
	self:_UpdateCamera()
end

function ViewportController:SetAccessory(source: Model, fit: { [string]: any })
	if self.accessory then
		self.accessory:Destroy()
	end
	local clone = source:Clone()
	prepare(clone)
	clone.Name = "ForgeAccessory"
	clone.Parent = self.world
	self.accessory = clone
	self:ApplyFit(fit)
end

function ViewportController:ApplyFit(fit: { [string]: any })
	if not self.accessory then
		return
	end
	local position = fit.position
	local rotation = fit.rotation
	local scale = fit.scale
	local anchor = PREVIEW_ANCHORS[fit.accessoryType] or PREVIEW_ANCHORS.Hat
	self.accessory:PivotTo(
		CFrame.new(anchor + Vector3.new(position.x, position.y, position.z))
			* CFrame.Angles(math.rad(rotation.x), math.rad(rotation.y), math.rad(rotation.z))
	)
	for _, descendant in self.accessory:GetDescendants() do
		if descendant:IsA("BasePart") then
			local baseSize = descendant:GetAttribute("ForgeBaseSize")
			if typeof(baseSize) ~= "Vector3" then
				baseSize = descendant.Size
				descendant:SetAttribute("ForgeBaseSize", baseSize)
			end
			descendant.Size = Vector3.new(baseSize.X * scale.x, baseSize.Y * scale.y, baseSize.Z * scale.z)
		end
	end
end

function ViewportController:Destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.world.Parent then
		self.world:Destroy()
	end
	if self.camera.Parent then
		self.camera:Destroy()
	end
end

return ViewportController
