--!strict

-- DataStore-safe snapshots, captured from the server's applied description.
-- No URLs, Instances, or client-supplied properties are ever deserialized.
local AvatarLook = {}
local NUMBERS = {
	"Shirt",
	"Pants",
	"GraphicTShirt",
	"Face",
	"Head",
	"Torso",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
	"BodyTypeScale",
	"DepthScale",
	"HeadScale",
	"HeightScale",
	"ProportionScale",
	"WidthScale",
	"ClimbAnimation",
	"FallAnimation",
	"IdleAnimation",
	"JumpAnimation",
	"RunAnimation",
	"SwimAnimation",
	"WalkAnimation",
}
local COLORS = { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }

function AvatarLook.Capture(description: HumanoidDescription): { [string]: any }
	local snapshot: { [string]: any } = { properties = {}, colors = {}, accessories = {} }
	for _, key in NUMBERS do
		snapshot.properties[key] = (description :: any)[key]
	end
	for _, key in COLORS do
		local color = (description :: any)[key] :: Color3
		snapshot.colors[key] = { color.R, color.G, color.B }
	end
	for _, accessory in description:GetAccessories(true) do
		table.insert(snapshot.accessories, {
			AssetId = accessory.AssetId,
			AccessoryType = accessory.AccessoryType.Name,
			IsLayered = accessory.IsLayered,
			Order = accessory.Order,
			Puffiness = accessory.Puffiness,
		})
	end
	return snapshot
end

function AvatarLook.Read(humanoid: Humanoid): { [string]: any }
	local description = humanoid:GetAppliedDescription()
	local ok, snapshot = pcall(AvatarLook.Capture, description)
	description:Destroy()
	if not ok then
		error(snapshot)
	end
	return snapshot
end

function AvatarLook.Description(snapshot: { [string]: any }): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	for _, key in NUMBERS do
		local value = snapshot.properties[key]
		if type(value) == "number" and value == value and math.abs(value) < math.huge then
			(description :: any)[key] = value
		end
	end
	for _, key in COLORS do
		local color = snapshot.colors[key]
		if type(color) == "table" and #color == 3 then
			(description :: any)[key] = Color3.new(color[1], color[2], color[3])
		end
	end
	local accessories = {}
	for _, accessory in snapshot.accessories do
		local copy = table.clone(accessory)
		copy.AccessoryType = Enum.AccessoryType[accessory.AccessoryType]
		table.insert(accessories, copy)
	end
	description:SetAccessories(accessories, true)
	return description
end

return AvatarLook
