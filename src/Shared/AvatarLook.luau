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

-- Roblox's Humanoid:ApplyDescription(Reset)Async can leave Humanoid.HipHeight
-- at 0 after applying a description -- most reliably on a character's first
-- apply in a session, or when the description being applied doesn't actually
-- change body scale (see devforum.roblox.com/t/4200195 -- Roblox has reopened
-- this one after an earlier attempted fix, and it is still reproducible as of
-- this writing). A HipHeight of 0 doesn't move or resize the character by
-- itself, but the default Animate script's walk/run/jump animations are
-- authored assuming the humanoid's real hip height, so the character visibly
-- slides/glides across the ground the moment it drops to 0. Every Forge look
-- change goes through this path (Forge accessories are welded outside
-- HumanoidDescription entirely, so Catalog/Outfit edits always use the
-- reset-safe apply -- see CatalogService and ItemService:EquipOutfit), so
-- this is what actually shows up in-game as a new item "breaking"
-- animations, even though nothing about the accessory or its fit math is at
-- fault. 0 is never a legitimate result for a rig that had a positive
-- HipHeight a moment earlier, so treat that transition as the engine bug
-- firing and restore the prior value. A rig that was already at 0 (R6, or no
-- real body loaded yet) is left alone, and a genuine change to a new nonzero
-- HipHeight (a real body-scale change) is never overwritten.
function AvatarLook.ApplyDescriptionSafely(humanoid: Humanoid, description: HumanoidDescription, reset: boolean?)
	local hipHeightBefore = humanoid.HipHeight
	if reset then
		humanoid:ApplyDescriptionResetAsync(description)
	else
		humanoid:ApplyDescriptionAsync(description)
	end
	if type(hipHeightBefore) == "number" and hipHeightBefore > 0 and humanoid.HipHeight == 0 then
		humanoid.HipHeight = hipHeightBefore
	end
end

return AvatarLook
