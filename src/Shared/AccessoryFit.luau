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
	local candidate = avatar:FindFirstChild(AccessoryFit.GetAttachmentName(accessoryType), true)
	if candidate and candidate:IsA("Attachment") then
		return candidate
	end
	return nil
end

return table.freeze(AccessoryFit)
