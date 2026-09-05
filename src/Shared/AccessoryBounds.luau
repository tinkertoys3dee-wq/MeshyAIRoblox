--!strict

-- Official Rthro Normal rigid-accessory mesh limits, measured in studs in
-- attachment orientation. Roblox validates the complete occupied envelope
-- around the attachment, not only the mesh's X/Y/Z span. Hair, Back, and
-- Waist also have explicitly asymmetric envelopes in the official table.
-- Forge publishes generated rigid accessories as ProportionsNormal.
-- https://create.roblox.com/docs/avatar/rigid-accessories/specifications
local AccessoryBounds = {}

export type Envelope = {
	minimum: Vector3,
	maximum: Vector3,
}

export type FittedBounds = {
	center: Vector3,
	size: Vector3,
	minimum: Vector3,
	maximum: Vector3,
}

export type Violation = {
	axis: string,
	side: string,
	direction: string,
	amount: number,
}

export type Clearance = {
	axis: string,
	side: string,
	direction: string,
	amount: number,
}

-- Keep every face slightly inside the documented platform envelope. The
-- publish path measures the newly created EditableMesh-backed Handle again,
-- but this inset also absorbs float serialization and platform rounding.
AccessoryBounds.SafetyInset = 0.02

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

local function symmetric(size: Vector3): Envelope
	local half = size / 2
	return { minimum = -half, maximum = half }
end

local NORMAL_ENVELOPES: { [string]: Envelope } = {
	Hat = symmetric(NORMAL_MAXIMUMS.Hat),
	HairAccessory = {
		minimum = Vector3.new(-1.87 / 2, -1.875, -0.9375),
		maximum = Vector3.new(1.87 / 2, 1.25, 1.25),
	},
	FaceAccessory = symmetric(NORMAL_MAXIMUMS.FaceAccessory),
	NeckAccessory = symmetric(NORMAL_MAXIMUMS.NeckAccessory),
	ShoulderAccessory = symmetric(NORMAL_MAXIMUMS.ShoulderAccessory),
	FrontAccessory = symmetric(NORMAL_MAXIMUMS.FrontAccessory),
	BackAccessory = {
		minimum = Vector3.new(-9.86 / 2, -8.59 / 2, -1.623),
		maximum = Vector3.new(9.86 / 2, 8.59 / 2, 3.246),
	},
	WaistAccessory = {
		minimum = Vector3.new(-3.94 / 2, -2.457, -7.57 / 2),
		maximum = Vector3.new(3.94 / 2, 1.842, 7.57 / 2),
	},
}

local function validVectorRecord(value: any): boolean
	return type(value) == "table"
		and type(value.x) == "number"
		and type(value.y) == "number"
		and type(value.z) == "number"
end

local function vectorRecord(value: any, fallback: Vector3): Vector3
	if not validVectorRecord(value) then
		return fallback
	end
	return Vector3.new(value.x, value.y, value.z)
end

function AccessoryBounds.GetMaximum(accessoryType: any): Vector3?
	if type(accessoryType) ~= "string" then
		return nil
	end
	return NORMAL_MAXIMUMS[accessoryType]
end

function AccessoryBounds.GetEnvelope(accessoryType: any, safe: boolean?): Envelope?
	if type(accessoryType) ~= "string" then
		return nil
	end
	local official = NORMAL_ENVELOPES[accessoryType]
	if not official then
		return nil
	end
	if safe ~= true then
		return { minimum = official.minimum, maximum = official.maximum }
	end
	local inset = Vector3.new(AccessoryBounds.SafetyInset, AccessoryBounds.SafetyInset, AccessoryBounds.SafetyInset)
	return {
		minimum = official.minimum + inset,
		maximum = official.maximum - inset,
	}
end

-- baseCenter/baseSize describe the mesh geometry in Handle-local coordinates.
-- The fit moves the Handle origin relative to the avatar attachment, so the
-- center must be scaled, rotated, and translated too. This is the part the old
-- span-only check missed: an unchanged span can still cross one face after a
-- position adjustment, and rotations change the attachment-oriented AABB.
function AccessoryBounds.GetFittedBounds(
	baseCenter: Vector3,
	baseSize: Vector3,
	fit: { [string]: any }
): FittedBounds
	local scale = vectorRecord(fit.scale, Vector3.new(1, 1, 1))
	local rotation = vectorRecord(fit.rotation, Vector3.new())
	local position = vectorRecord(fit.position, Vector3.new())
	local scaledSize = Vector3.new(
		math.abs(baseSize.X * scale.X),
		math.abs(baseSize.Y * scale.Y),
		math.abs(baseSize.Z * scale.Z)
	)
	local scaledCenter = Vector3.new(
		baseCenter.X * scale.X,
		baseCenter.Y * scale.Y,
		baseCenter.Z * scale.Z
	)
	local orientation = CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	local offset = CFrame.new(position) * orientation
	local xAxis = orientation.XVector
	local yAxis = orientation.YVector
	local zAxis = orientation.ZVector
	local size = Vector3.new(
		math.abs(xAxis.X) * scaledSize.X + math.abs(yAxis.X) * scaledSize.Y + math.abs(zAxis.X) * scaledSize.Z,
		math.abs(xAxis.Y) * scaledSize.X + math.abs(yAxis.Y) * scaledSize.Y + math.abs(zAxis.Y) * scaledSize.Z,
		math.abs(xAxis.Z) * scaledSize.X + math.abs(yAxis.Z) * scaledSize.Y + math.abs(zAxis.Z) * scaledSize.Z
	)
	local center = offset:PointToWorldSpace(scaledCenter)
	local half = size / 2
	return {
		center = center,
		size = size,
		minimum = center - half,
		maximum = center + half,
	}
end

-- Compatibility helper for callers that need only the rotated span. Position
-- does not alter a span, so a centered geometry record is sufficient here.
function AccessoryBounds.GetFittedSize(baseSize: Vector3, fit: { [string]: any }): Vector3
	return AccessoryBounds.GetFittedBounds(Vector3.new(), baseSize, fit).size
end

function AccessoryBounds.GetViolations(
	minimum: Vector3,
	maximum: Vector3,
	allowedMinimum: Vector3,
	allowedMaximum: Vector3
): { Violation }
	local violations: { Violation } = {}
	local epsilon = 0.0005
	local function minimumViolation(axis: string, direction: string, actual: number, allowed: number)
		if actual < allowed - epsilon then
			table.insert(violations, {
				axis = axis,
				side = "MINIMUM",
				direction = direction,
				amount = allowed - actual,
			})
		end
	end
	local function maximumViolation(axis: string, direction: string, actual: number, allowed: number)
		if actual > allowed + epsilon then
			table.insert(violations, {
				axis = axis,
				side = "MAXIMUM",
				direction = direction,
				amount = actual - allowed,
			})
		end
	end

	minimumViolation("X", "left", minimum.X, allowedMinimum.X)
	maximumViolation("X", "right", maximum.X, allowedMaximum.X)
	minimumViolation("Y", "below", minimum.Y, allowedMinimum.Y)
	maximumViolation("Y", "above", maximum.Y, allowedMaximum.Y)
	-- Roblox's attachment-local front direction is -Z; behind is +Z.
	minimumViolation("Z", "front", minimum.Z, allowedMinimum.Z)
	maximumViolation("Z", "behind", maximum.Z, allowedMaximum.Z)
	return violations
end

function AccessoryBounds.GetExceededAxes(violations: { Violation }): { string }
	local axes: { string } = {}
	for _, violation in violations do
		if not table.find(axes, violation.axis) then
			table.insert(axes, violation.axis)
		end
	end
	return axes
end

function AccessoryBounds.GetClosestBoundary(
	minimum: Vector3,
	maximum: Vector3,
	allowedMinimum: Vector3,
	allowedMaximum: Vector3
): Clearance
	local candidates: { Clearance } = {
		{ axis = "X", side = "MINIMUM", direction = "left", amount = minimum.X - allowedMinimum.X },
		{ axis = "X", side = "MAXIMUM", direction = "right", amount = allowedMaximum.X - maximum.X },
		{ axis = "Y", side = "MINIMUM", direction = "below", amount = minimum.Y - allowedMinimum.Y },
		{ axis = "Y", side = "MAXIMUM", direction = "above", amount = allowedMaximum.Y - maximum.Y },
		{ axis = "Z", side = "MINIMUM", direction = "front", amount = minimum.Z - allowedMinimum.Z },
		{ axis = "Z", side = "MAXIMUM", direction = "behind", amount = allowedMaximum.Z - maximum.Z },
	}
	local closest = candidates[1] :: Clearance
	for index = 2, #candidates do
		local candidate = candidates[index] :: Clearance
		if candidate.amount < closest.amount then
			closest = candidate
		end
	end
	return closest
end

function AccessoryBounds.ExceededAxes(size: Vector3, maximum: Vector3): { string }
	local axes: { string } = {}
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
