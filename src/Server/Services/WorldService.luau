--!strict

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local WorldService = {}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
)
	local object = Instance.new("Part")
	object.Name = name
	object.Size = size
	object.CFrame = cframe
	object.Color = color
	object.Material = material
	object.Anchored = true
	object.CanCollide = true
	object.TopSurface = Enum.SurfaceType.Smooth
	object.BottomSurface = Enum.SurfaceType.Smooth
	object.Parent = parent
	return object
end

function WorldService.Build()
	if Workspace:FindFirstChild("ForgeStudio") then
		return
	end
	Lighting.Brightness = 2.2
	Lighting.ClockTime = 18.4
	Lighting.Ambient = Color3.fromRGB(54, 60, 90)
	Lighting.OutdoorAmbient = Color3.fromRGB(34, 42, 70)
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 1

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.22
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(160, 178, 255)
	atmosphere.Decay = Color3.fromRGB(68, 44, 110)
	atmosphere.Glare = 0.08
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting

	local studio = Instance.new("Model")
	studio.Name = "ForgeStudio"
	studio.Parent = Workspace
	part(
		studio,
		"Floor",
		Vector3.new(180, 2, 180),
		CFrame.new(0, -1, 0),
		Color3.fromRGB(14, 18, 34),
		Enum.Material.Slate
	)
	part(
		studio,
		"CenterStage",
		Vector3.new(30, 1, 30),
		CFrame.new(0, 0.5, 0),
		Color3.fromRGB(42, 36, 78),
		Enum.Material.SmoothPlastic
	)
	for index = 1, 12 do
		local angle = math.rad((index - 1) * 30)
		local radius = if index % 2 == 0 then 65 else 48
		local position = Vector3.new(math.cos(angle) * radius, 3, math.sin(angle) * radius)
		local pillar = part(
			studio,
			"GlowPillar",
			Vector3.new(2, 7 + (index % 3) * 2, 2),
			CFrame.new(position),
			if index % 2 == 0 then Color3.fromRGB(65, 219, 255) else Color3.fromRGB(142, 86, 255),
			Enum.Material.Neon
		)
		pillar.CanCollide = false
	end
	for index = 1, 6 do
		local angle = math.rad((index - 1) * 60)
		local position = Vector3.new(math.cos(angle) * 29, 1.5, math.sin(angle) * 29)
		part(
			studio,
			"ShowcasePlinth",
			Vector3.new(8, 3, 8),
			CFrame.new(position),
			Color3.fromRGB(29, 36, 65),
			Enum.Material.Marble
		)
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ForgeSpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 1.5, 22)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Transparency = 0.25
	spawn.Material = Enum.Material.ForceField
	spawn.Color = Color3.fromRGB(108, 98, 255)
	spawn.Neutral = true
	spawn.Parent = studio
end

return WorldService
