--!strict

local Players = game:GetService("Players")

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
	camera.FieldOfView = 32
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 2.4, -9.5), Vector3.new(0, 1.1, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Ambient = Color3.fromRGB(145, 155, 210)
	viewport.LightColor = Color3.fromRGB(255, 245, 235)
	viewport.LightDirection = Vector3.new(-1, -0.8, -0.5)
	local self = setmetatable({
		viewport = viewport,
		world = world,
		camera = camera,
		accessory = nil :: Model?,
	}, ViewportController)
	task.spawn(function()
		local player = Players.LocalPlayer
		local success, avatar = pcall(function()
			return Players:CreateHumanoidModelFromUserIdAsync(player.UserId)
		end)
		if success and avatar and viewport.Parent then
			prepare(avatar)
			avatar.Name = "AvatarReference"
			avatar:PivotTo(CFrame.new())
			avatar.Parent = world
		end
	end)
	return self
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

return ViewportController
