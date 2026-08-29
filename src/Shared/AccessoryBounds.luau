--!strict

-- Official Rthro Normal rigid-accessory mesh limits, measured in studs in
-- attachment orientation. Forge publishes its generated rigid accessories as
-- ProportionsNormal so the in-game measurements and Roblox's validator use the
-- same scale family.
-- https://create.roblox.com/docs/avatar/rigid-accessories/specifications
local AccessoryBounds = {}

local NORMAL_MAXIMUMS: { [string]: Vector3 } = {
	Hat = Vector3.new(1.87, 2.5, 1.87),
	HairAccessory = Vector3.new(1.87, 3.12, 2.18),
	FaceAccessory = Vector3.new(1.87, 1.25, 1.25),
	NeckAccessory = Vector3.new(2.95, 3.68, 2.16),
	-- Forge uses RightShoulderAttachment; Roblox publishes a separate, smaller
	-- bound for shoulder-attached items than for NeckAttachment items.
	ShoulderAccessory = Vector3.new(2.67, 4.4, 3.09),
	FrontAccessory = Vector3.new(2.95, 3.68, 3.24),
	BackAccessory = Vector3.new(9.86, 8.59, 4.87),
	WaistAccessory = Vector3.new(3.94, 4.29, 7.57),
}

local function validVectorRecord(value: any): boolean
	return type(value) == "table"
		and type(value.x) == "number"
		and type(value.y) == "number"
		and type(value.z) == "number"
end

function AccessoryBounds.GetMaximum(accessoryType: any): Vector3?
	if type(accessoryType) ~= "string" then
		return nil
	end
	return NORMAL_MAXIMUMS[accessoryType]
end

-- MeshPart.Size is axis-aligned in the part's own coordinates. Roblox measures
-- rigid accessories in attachment orientation, so rotation can make the
-- occupied X/Y/Z span larger than the unrotated MeshPart.Size. This converts
-- the scaled box into that attachment-oriented span.
function AccessoryBounds.GetFittedSize(baseSize: Vector3, fit: { [string]: any }): Vector3
	local scale = fit.scale
	local rotation = fit.rotation
	if not validVectorRecord(scale) or not validVectorRecord(rotation) then
		return baseSize
	end

	local scaled =
		Vector3.new(math.abs(baseSize.X * scale.x), math.abs(baseSize.Y * scale.y), math.abs(baseSize.Z * scale.z))
	local orientation = CFrame.Angles(math.rad(rotation.x), math.rad(rotation.y), math.rad(rotation.z))
	local xAxis = orientation.XVector
	local yAxis = orientation.YVector
	local zAxis = orientation.ZVector
	return Vector3.new(
		math.abs(xAxis.X) * scaled.X + math.abs(yAxis.X) * scaled.Y + math.abs(zAxis.X) * scaled.Z,
		math.abs(xAxis.Y) * scaled.X + math.abs(yAxis.Y) * scaled.Y + math.abs(zAxis.Y) * scaled.Z,
		math.abs(xAxis.Z) * scaled.X + math.abs(yAxis.Z) * scaled.Y + math.abs(zAxis.Z) * scaled.Z
	)
end

function AccessoryBounds.ExceededAxes(size: Vector3, maximum: Vector3): { string }
	local axes = {}
	if size.X > maximum.X + 0.001 then
		table.insert(axes, "X")
	end
	if size.Y > maximum.Y + 0.001 then
		table.insert(axes, "Y")
	end
	if size.Z > maximum.Z + 0.001 then
		table.insert(axes, "Z")
	end
	return axes
end

return table.freeze(AccessoryBounds)
