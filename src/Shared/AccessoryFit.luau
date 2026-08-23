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
