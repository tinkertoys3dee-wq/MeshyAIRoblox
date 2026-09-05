-- Minimal deterministic Roblox doubles. No network calls, purchases or
-- DataStore access. Only properties/APIs needed by these tests are modeled.
local modules, cache, fixtures = {}, {}, {}
local function require(name)
	if cache[name] then
		return cache[name]
	end
	if fixtures[name] then
		return fixtures[name]
	end
	assert(modules[name], "Missing module double: " .. tostring(name))
	cache[name] = modules[name]()
	return cache[name]
end
local script = { Parent = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
}) }
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			local link = { Connected = true }
			function link:Disconnect()
				self.Connected = false
			end
			table.insert(callbacks, { callback = callback, link = link })
			return link
		end,
		Fire = function(_, ...)
			for _, item in table.clone(callbacks) do
				if item.link.Connected then
					item.callback(...)
				end
			end
		end,
	}
end
local Enum = setmetatable({}, {
	__index = function(enums, category)
		local group = setmetatable({}, {
			__index = function(values, name)
				local entry = setmetatable({ Name = name, Value = 0 }, {
					__tostring = function()
						return "Enum." .. category .. "." .. name
					end,
				})
				rawset(values, name, entry)
				return entry
			end,
		})
		rawset(enums, category, group)
		return group
	end,
})
for name, value in
	{
		Hat = 8,
		HairAccessory = 41,
		FaceAccessory = 42,
		Shirt = 11,
		Pants = 12,
		TShirt = 2,
		Face = 18,
		JacketAccessory = 67,
		ShirtAccessory = 65,
		PantsAccessory = 66,
		SweaterAccessory = 68,
	}
do
	Enum.AvatarAssetType[name].Value = value
end
local Color3 = {
	new = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
}
function Color3.fromRGB(r, g, b)
	return Color3.new(r / 255, g / 255, b / 255)
end
local Vector2 = {
	new = function(x, y)
		return { X = x, Y = y }
	end,
}
Vector2.zero = Vector2.new(0, 0)
local Vector3 = {
	new = function(x, y, z)
		return { X = x, Y = y, Z = z }
	end,
}
Vector3.zero = Vector3.new(0, 0, 0)
local UDim = {
	new = function(scale, offset)
		return { Scale = scale or 0, Offset = offset or 0 }
	end,
}
local UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, {
		__add = function(a, b)
			return UDim2.new(
				a.X.Scale + b.X.Scale,
				a.X.Offset + b.X.Offset,
				a.Y.Scale + b.Y.Scale,
				a.Y.Offset + b.Y.Offset
			)
		end,
	})
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end
local Rect = {
	new = function(...)
		return { ... }
	end,
}
local NumberSequence = {
	new = function(...)
		return { ... }
	end,
}
local NumberSequenceKeypoint = {
	new = function(...)
		return { ... }
	end,
}
local ColorSequence, ColorSequenceKeypoint = NumberSequence, NumberSequenceKeypoint
local TweenInfo = {
	new = function(...)
		return { ... }
	end,
}
local CatalogSearchParams = {
	new = function()
		return {}
	end,
}
local spawned, delayed = {}, {}
local task = {
	spawn = function(callback)
		table.insert(spawned, callback)
	end,
	defer = function(callback)
		table.insert(spawned, callback)
	end,
	delay = function(_, callback)
		table.insert(delayed, callback)
	end,
	wait = function()
		error("Tests must explicitly advance the scheduler")
	end,
}
local function runSpawn(index)
	local callback = table.remove(spawned, index or 1)
	assert(callback)
	callback()
end
local function warn(...) end
local eventNames = {
	ChildAdded = true,
	Destroying = true,
	DescendantAdded = true,
	MouseEnter = true,
	MouseLeave = true,
	SelectionGained = true,
	SelectionLost = true,
	InputBegan = true,
	InputEnded = true,
	Activated = true,
	FocusLost = true,
}
local methods = {}
function methods:IsA(kind)
	if kind == self.ClassName or kind == "Instance" then
		return true
	end
	if kind == "GuiButton" then
		return self.ClassName == "TextButton" or self.ClassName == "ImageButton"
	end
	if kind == "GuiObject" then
		return not string.match(self.ClassName, "^UI") and self.ClassName ~= "HumanoidDescription"
	end
	return false
end
function methods:GetAttribute(key)
	return self._attributes[key]
end
function methods:SetAttribute(key, value)
	self._attributes[key] = value
end
function methods:GetPropertyChangedSignal(key)
	if not self._signals[key] then
		self._signals[key] = signal()
	end
	return self._signals[key]
end
function methods:GetChildren()
	return table.clone(self._children)
end
function methods:GetDescendants()
	local result = {}
	for _, child in self._children do
		table.insert(result, child)
		for _, descendant in child:GetDescendants() do
			table.insert(result, descendant)
		end
	end
	return result
end
function methods:FindFirstChild(name)
	for _, child in self._children do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function methods:FindFirstChildOfClass(class)
	for _, child in self._children do
		if child.ClassName == class then
			return child
		end
	end
	return nil
end
function methods:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self.Destroying:Fire()
	for _, child in self:GetChildren() do
		child:Destroy()
	end
	self.Parent = nil
	for _, event in self._signals do -- disconnected by engine destruction in Roblox
		-- Individual external subscriptions are asserted separately by tests.
	end
end
function methods:GetAccessories()
	return table.clone(self._accessories or {})
end
function methods:SetAccessories(accessories)
	self._accessories = table.clone(accessories)
end
local Instance = {}
function Instance.new(class)
	local object = {
		_props = {
			ClassName = class,
			Name = class,
			Active = true,
			Visible = true,
			Size = UDim2.new(),
			Position = UDim2.new(),
			AbsoluteSize = Vector2.new(1000, 800),
			BackgroundTransparency = 0,
			TextTransparency = 0,
			Text = "",
			TextSize = 14,
			Scale = 1,
			TextTruncate = Enum.TextTruncate.None,
			TextWrapped = false,
			PaddingLeft = UDim.new(),
			PaddingRight = UDim.new(),
			PaddingTop = UDim.new(),
			PaddingBottom = UDim.new(),
			MinSize = Vector2.zero,
			MaxSize = Vector2.new(math.huge, math.huge),
		},
		_children = {},
		_signals = {},
		_attributes = {},
	}
	setmetatable(object, {
		__index = function(self, key)
			if methods[key] then
				return methods[key]
			end
			if eventNames[key] then
				return self:GetPropertyChangedSignal("event:" .. key)
			end
			return self._props[key]
		end,
		__newindex = function(self, key, value)
			if string.sub(key, 1, 1) == "_" then
				rawset(self, key, value)
				return
			end
			local previous = self._props[key]
			self._props[key] = value
			if key == "Parent" and previous ~= value then
				if previous then
					local index = table.find(previous._children, self)
					if index then
						table.remove(previous._children, index)
					end
				end
				if value then
					table.insert(value._children, self)
					value.ChildAdded:Fire(self)
				end
			end
			if previous ~= value and self._signals[key] then
				self._signals[key]:Fire()
			end
		end,
	})
	if class == "HumanoidDescription" then
		for _, name in
			{
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
				"ClimbAnimation",
				"FallAnimation",
				"IdleAnimation",
				"JumpAnimation",
				"RunAnimation",
				"SwimAnimation",
				"WalkAnimation",
			}
		do
			object[name] = 0
		end
		for _, name in { "BodyTypeScale", "DepthScale", "HeadScale", "HeightScale", "ProportionScale", "WidthScale" } do
			object[name] = 1
		end
		for _, name in { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" } do
			object[name] = Color3.new(1, 1, 1)
		end
	end
	return object
end
local tweenCount = 0
local services = {
	Workspace = { CurrentCamera = { ViewportSize = Vector2.new(1200, 900) } },
	ReplicatedStorage = {
		WaitForChild = function(_, name)
			return name
		end,
	},
	TweenService = {
		Create = function(_, object, info, properties)
			tweenCount += 1
			return {
				Play = function()
					for key, value in properties do
						object[key] = value
					end
				end,
				Cancel = function() end,
			}
		end,
	},
	AvatarEditorService = {
		GetAccessoryType = function(_, assetType)
			return Enum.AccessoryType[assetType.Name:gsub("Accessory", "")]
		end,
	},
	GroupService = {},
	MarketplaceService = {},
	Players = {},
	PolicyService = {},
	AssetService = {},
	AvatarCreationService = {},
	RunService = {},
	ServerStorage = {},
}
local game = {
	GetService = function(_, name)
		assert(services[name], name)
		return services[name]
	end,
}
fixtures.Theme = {
	Colors = setmetatable({}, {
		__index = function()
			return Color3.new(0.5, 0.5, 0.5)
		end,
	}),
	Fonts = {
		Display = Enum.Font.Gotham,
		Regular = Enum.Font.Arial,
		Bold = Enum.Font.ArialBold,
		Black = Enum.Font.ArialBold,
	},
	Corner = 16,
	SmallCorner = 10,
	StrokeTransparency = 0.45,
}
fixtures.UIAssets = {}
fixtures.Network = { Actions = setmetatable({}, {
	__index = function(_, name)
		return name
	end,
}) }
fixtures.Config = {
	Generation = { BaseQueueSlots = 1 },
	Group = {
		Id = 15575113,
		Name = "Mundane Studios",
		ExtraQueueSlots = 1,
		GenerationSpeedMultiplier = 0.9,
	},
}
fixtures.AccessoryBounds, fixtures.AccessoryFit = {}, {}
fixtures.ViewportController = {
	new = function()
		return {}
	end,
}
fixtures.RunwayHub = {}
