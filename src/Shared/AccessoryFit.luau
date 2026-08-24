--!strict

-- The fitting preview and the server-built Accessory must use the exact same
-- attachment names and CFrame math. Keeping this in ReplicatedStorage prevents
-- a visually correct preview from shifting when Humanoid:AddAccessory welds it.
local AccessoryFit = {}

local ATTACHMENT_NAMES: { [string]: string } = {
	Hat = "HatAttachment",
	HairAccessory = "HairAttachment",
	FaceAccessory = "FaceFrontAttachment",
	NeckAccessory = "NeckAttachment",
	ShoulderAccessory = "RightShoulderAttachment",
	FrontAccessory = "BodyFrontAttachment",
	BackAccessory = "BodyBackAttachment",
	WaistAccessory = "WaistFrontAttachment",
}

function AccessoryFit.GetAttachmentName(accessoryType: any): string
	if type(accessoryType) == "string" then
		return ATTACHMENT_NAMES[accessoryType] or ATTACHMENT_NAMES.Hat
	end
	return ATTACHMENT_NAMES.Hat
end

function AccessoryFit.GetOffsetCFrame(fit: { [string]: any }): CFrame
	local position = fit.position
	local rotation = fit.rotation
	return CFrame.new(position.x, position.y, position.z)
		* CFrame.Angles(math.rad(rotation.x), math.rad(rotation.y), math.rad(rotation.z))
end

function AccessoryFit.GetHandleAttachmentCFrame(fit: { [string]: any }): CFrame
	return AccessoryFit.GetOffsetCFrame(fit):Inverse()
end

-- Head-worn types are seated bottom-first: the mesh's bounding-box floor is
-- placed on the attachment (so a hat/hair mesh sits ON the head instead of
-- straddling it, and a hat isn't half-sunk into the skull the way centering
-- its bounding box would leave it). Body-worn types use the full bounding-box
-- center instead, since there's no equivalent "resting surface" for a
-- shoulder, back, or waist accessory -- it should simply be centered on its
-- attachment.
local SEATED_TYPES: { [string]: boolean } = {
	Hat = true,
	HairAccessory = true,
	FaceAccessory = true,
}

-- Meshy's generated meshes place their own local origin (a MeshPart's
-- CFrame position, i.e. what fit.position = (0,0,0) pins to the avatar
-- attachment) wherever its export happened to land -- sometimes the
-- geometric center, sometimes a corner, inconsistently between generations.
-- GetOffsetCFrame has no way to know that, so an off-center mesh origin
-- reads as a wildly, randomly offset item the moment it's equipped or
-- previewed, even though the fit math itself is correct. This computes the
-- position that instead seats a sensible geometric anchor of the mesh --
-- see SEATED_TYPES above -- at the attachment, independent of wherever the
-- mesh's authored origin actually sits, so a freshly generated item starts
-- out looking properly placed instead of at (0,0,0).
--
-- `handle` is inspected, never mutated: bounding-box math runs on a
-- throwaway clone at an identity CFrame (Model:GetBoundingBox() is the
-- verified-official way to get a Model's true geometric extents, aligned
-- with its pivot -- there is no equivalent BasePart-level method), so this
-- is safe to call on a live, in-use MeshPart.
function AccessoryFit.ComputeDefaultPosition(handle: BasePart, accessoryType: any): { x: number, y: number, z: number }
	local clone = handle:Clone()
	clone.CFrame = CFrame.new()
	local tempModel = Instance.new("Model")
	clone.Parent = tempModel
	tempModel.PrimaryPart = clone

	local ok, centerCFrame, size = pcall(function()
		return tempModel:GetBoundingBox()
	end)
	tempModel:Destroy()

	if not ok then
		return { x = 0, y = 0, z = 0 }
	end

	local center = (centerCFrame :: CFrame).Position
	local anchor: Vector3
	if SEATED_TYPES[accessoryType] then
		anchor = Vector3.new(center.X, center.Y - (size :: Vector3).Y / 2, center.Z)
	else
		anchor = center
	end
	-- fit.position offsets the Handle's local origin away from the
	-- attachment (see GetOffsetCFrame above); to land the anchor point ON
	-- the attachment instead, the origin must move by the anchor's
	-- negation.
	return { x = -anchor.X, y = -anchor.Y, z = -anchor.Z }
end

function AccessoryFit.FindAvatarAttachment(avatar: Instance, accessoryType: any): Attachment?
	local name = AccessoryFit.GetAttachmentName(accessoryType)
	-- Deliberately not a recursive FindFirstChild(name, true): every worn
	-- Accessory's Handle carries its own attachment with this exact same
	-- name (that is how Humanoid:AddAccessory matches and welds it), so a
	-- recursive search can return a currently-equipped accessory's
	-- attachment instead of the body's, placing the fitted item at that
	-- unrelated accessory's position. Only the body parts parented
	-- directly under the avatar model can carry the real attachment.
	for _, part in avatar:GetChildren() do
		if part:IsA("BasePart") then
			local candidate = part:FindFirstChild(name)
			if candidate and candidate:IsA("Attachment") then
				return candidate
			end
		end
	end
	return nil
end

return table.freeze(AccessoryFit)
