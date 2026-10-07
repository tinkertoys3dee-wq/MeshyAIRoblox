--!strict

-- Crisp native popup surfaces. Icons are the original hand-authored SVG
-- exports; labels and interaction states remain editable Roblox controls.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local HomeAssets = require(ReplicatedStorage:WaitForChild("HomeAssets"))
local Factory = require(script.Parent.Factory)
local Motion = require(script.Parent.Motion)
local GuiService = game:GetService("GuiService")

local PopupStyle = {}
local Colors = Theme.Colors

function PopupStyle.SafeArea(overlay: GuiObject): Frame
	local success, inset = pcall(function() return GuiService:GetGuiInset() end)
	local top = if success and inset then math.max(0, inset.Y) else 0
	return Factory.New("Frame", { Name = "PopupSafeArea", Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top), BackgroundTransparency = 1, BorderSizePixel = 0,
		Active = false, ZIndex = overlay.ZIndex, Parent = overlay })
end

local function own(instance: Instance): any
	instance:SetAttribute("ForgePopupPart", true)
	return instance
end

local function clearParts(target: GuiObject)
	for _, child in target:GetChildren() do
		if child:GetAttribute("ForgePopupPart") then
			child:Destroy()
		end
	end
end

local function corners(target: Instance, radius: number)
	local corner = target:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, radius)
	else
		own(Factory.Corner(target, radius))
	end
end

local function border(target: GuiObject, color: Color3, transparency: number): UIStroke
	local stroke = target:FindFirstChildOfClass("UIStroke")
	if not stroke or stroke.Name == "InteractionOutline" then
		stroke = own(Factory.Stroke(target, color, transparency, 1))
	end
	stroke.Name = "PopupBorder"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = if Theme.IsHighContrast then 1.5 else 1
	return stroke
end

local function gradient(target: GuiObject, top: Color3, bottom: Color3)
	local previous = target:FindFirstChildOfClass("UIGradient")
	if previous then previous:Destroy() end
	local result = own(Factory.Gradient(target, { top, bottom }, 90))
	result.Enabled = not Theme.IsHighContrast
	return result
end

local function icon(parent: GuiObject, key: string, position: UDim2, size: UDim2, z: number): ImageLabel?
	local id = (HomeAssets :: any)[key]
	if type(id) ~= "number" or id <= 0 then return nil end
	return own(Factory.New("ImageLabel", {
		Name = "PopupIcon", Image = "rbxassetid://" .. tostring(id),
		Position = position, Size = size, BackgroundTransparency = 1,
		BorderSizePixel = 0, Active = false, ScaleType = Enum.ScaleType.Fit,
		ZIndex = z, Parent = parent,
	}))
end

local function frame(parent: GuiObject, name: string, properties: { [string]: any }): Frame
	properties.Name = name
	properties.Parent = parent
	properties.BorderSizePixel = 0
	properties.Active = false
	return own(Factory.New("Frame", properties))
end

local HEADER_ICONS = {
	["Forge Tokens"] = "TokenIcon", ["Daily Missions"] = "MissionsIcon",
	["Daily Rewards"] = "RewardsIcon", ["UGC Item Codes"] = "CodesIcon",
	["Premium"] = "PremiumIcon", ["More Tools"] = "SettingsButton",
	["More tools"] = "SettingsButton", ["Tutorial"] = "TutorialIcon",
}

function PopupStyle.Panel(panel: GuiObject, title: string, options: { [string]: any }?)
	options = options or {}
	clearParts(panel)
	local z = panel.ZIndex
	panel.BackgroundTransparency = 0
	-- UIGradient multiplies the base color; white preserves the authored
	-- navy stops rather than multiplying two dark colors into near-black.
	panel.BackgroundColor3 = if Theme.IsHighContrast then Colors.Panel else Color3.new(1, 1, 1)
	panel.BorderSizePixel = 0
	corners(panel, 24)
	border(panel, if Theme.IsHighContrast then Colors.Line else Color3.fromRGB(112, 144, 184), if Theme.IsHighContrast then 0.12 else 0.56)
	gradient(panel, Color3.fromRGB(29, 44, 71), Color3.fromRGB(14, 23, 41))
	local shadow = frame(panel, "PopupShadow", {
		Position = UDim2.new(0, 12, 1, 3), Size = UDim2.new(1, -24, 0, 7),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.6,
		ZIndex = z - 1, Visible = not Theme.IsHighContrast,
	})
	corners(shadow, 4)
	local accent = frame(panel, "PopupTopAccent", {
		Position = UDim2.fromOffset(26, 0), Size = UDim2.fromOffset(56, 2),
		BackgroundColor3 = options.accent or Colors.Cyan, ZIndex = z + 1,
	})
	corners(accent, 1)
	frame(panel, "PopupHeaderRule", {
		Position = UDim2.fromOffset(22, 70), Size = UDim2.new(1, -44, 0, 1),
		BackgroundColor3 = Colors.Line, BackgroundTransparency = if Theme.IsHighContrast then 0.35 else 0.72,
		ZIndex = z + 1,
	})
	local iconKey = options.icon or HEADER_ICONS[title]
	local headingIcon = if iconKey then icon(panel, iconKey, UDim2.fromOffset(22, 18), UDim2.fromOffset(34, 34), z + 2) else nil
	for _, child in panel:GetChildren() do
		if child:IsA("TextLabel") and child.Text == title then
			child.Position = UDim2.fromOffset(if headingIcon then 68 else 22, 14)
			child.Size = UDim2.new(1, if headingIcon then -132 else -86, 0, 42)
			child.TextColor3 = Colors.Text
			child.Font = Theme.Fonts.Bold
			child.TextSize = 23
			child.TextXAlignment = Enum.TextXAlignment.Left
			child.TextTruncate = Enum.TextTruncate.AtEnd
			child.TextWrapped = false
			child.ZIndex = z + 3
		end
	end
end

local function palette(kind: string): (Color3, Color3, Color3, Color3)
	if Theme.IsHighContrast then
		return Colors.PanelRaised, Colors.PanelRaised, Colors.Text, Colors.Line
	elseif kind == "primary" then
		return Color3.fromRGB(31, 131, 223), Color3.fromRGB(14, 88, 169), Colors.Text, Color3.fromRGB(92, 193, 255)
	elseif kind == "gold" then
		return Color3.fromRGB(255, 215, 105), Color3.fromRGB(226, 172, 50), Colors.Ink, Color3.fromRGB(255, 229, 148)
	elseif kind == "violet" then
		return Color3.fromRGB(127, 76, 205), Color3.fromRGB(82, 45, 143), Colors.Text, Color3.fromRGB(177, 135, 242)
	end
	return Color3.fromRGB(38, 55, 81), Color3.fromRGB(27, 41, 63), Colors.Text, Color3.fromRGB(107, 139, 181)
end

function PopupStyle.Action(control: GuiButton, caption: string, options: { [string]: any }?)
	options = options or {}
	clearParts(control)
	local kind = options.kind or "secondary"
	local top, bottom, ink, edge = palette(kind)
	local z = control.ZIndex
	control.BackgroundTransparency = 0
	control.BackgroundColor3 = if Theme.IsHighContrast then Colors.PanelRaised else Color3.new(1, 1, 1)
	control.BorderSizePixel = 0
	if control:IsA("TextButton") then
		control.Text = caption
		control.TextTransparency = 1
	end
	corners(control, 14)
	border(control, edge, if Theme.IsHighContrast then 0 else (if kind == "secondary" then 0.53 else 0.32))
	gradient(control, top, bottom)
	local shadow = frame(control, "PopupActionShadow", {
		Position = UDim2.new(0, 6, 1, 1), Size = UDim2.new(1, -12, 0, 3),
		BackgroundColor3 = Color3.fromRGB(2, 9, 22), BackgroundTransparency = 0.45,
		ZIndex = z - 1, Visible = not Theme.IsHighContrast,
	})
	corners(shadow, 2)
	local wash = frame(control, "PopupInteractionWash", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1, ZIndex = z + 1,
	})
	corners(wash, 14)
	local hasIcon = options.icon and (HomeAssets :: any)[options.icon] ~= nil
	if hasIcon then
		local medallion = frame(control, "PopupIconWell", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0),
			Size = UDim2.fromOffset(40, 40), BackgroundColor3 = if kind == "gold" and not Theme.IsHighContrast then Colors.Ink else Color3.new(1, 1, 1),
			BackgroundTransparency = 0.88, ZIndex = z + 2,
		})
		corners(medallion, 11)
		icon(medallion, options.icon, UDim2.fromOffset(6, 6), UDim2.fromOffset(28, 28), z + 3)
	end
	local left = if hasIcon then 66 else 18
	local arrowWidth = if options.chevron == false then 18 else 48
	local text = control:FindFirstChild("Caption")
	if not text or not text:IsA("TextLabel") then
		text = Factory.New("TextLabel", { Name = "Caption", Parent = control })
	end
	local title = text :: TextLabel
	-- Retain the native button's original semantic text, while the rendered
	-- caption uses the separate chevron lane instead of a duplicate arrow.
	title.Text = if options.chevron == false then caption else (string.gsub(caption, "%s*›%s*$", ""))
	title.BackgroundTransparency = 1
	title.BorderSizePixel = 0
	title.Position = if options.detail then UDim2.new(0, left, 0.5, -23) else UDim2.new(0, left, 0, 0)
	title.Size = if options.detail then UDim2.new(1, -left - arrowWidth, 0, 26) else UDim2.new(1, -left - arrowWidth, 1, 0)
	title.TextColor3 = ink
	title.Font = Theme.Fonts.Bold
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = z + 3
	if options.detail then
		own(Factory.Label(control, options.detail, UDim2.new(1, -left - arrowWidth, 0, 20), {
			Name = "ActionDetail", Position = UDim2.new(0, left, 0.5, 3), Font = Theme.Fonts.Regular,
			TextSize = 13, Color = if Theme.IsHighContrast then Colors.TextMuted elseif kind == "gold" then Color3.fromRGB(76, 53, 14) else Color3.fromRGB(206, 223, 246),
			ZIndex = z + 3, Truncate = Enum.TextTruncate.AtEnd,
		}))
	end
	if options.chevron ~= false then
		own(Factory.Label(control, "›", UDim2.fromOffset(26, 36), {
			Name = "ActionChevron", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, -1),
			Font = Theme.Fonts.Regular, TextSize = 29, Color = ink, AlignX = Enum.TextXAlignment.Center,
			ZIndex = z + 3,
		}))
	end
	Motion.Bind(control)
	if control:GetAttribute("ForgePopupHoverBound") then return end
	control:SetAttribute("ForgePopupHoverBound", true)
	local hovered, selected, pressed = false, false, false
	local tween: Tween? = nil
	local connections = {}
	local function update()
		local liveWash = control:FindFirstChild("PopupInteractionWash")
		if not liveWash then return end
		if tween then tween:Cancel() end
		tween = Motion.Tween(liveWash, 0.1, {
			BackgroundTransparency = if not control.Active then 1 elseif pressed then 0.86 elseif hovered or selected then 0.94 else 1,
		})
	end
	table.insert(connections, control.MouseEnter:Connect(function() hovered = true; update() end))
	table.insert(connections, control.MouseLeave:Connect(function() hovered = false; pressed = false; update() end))
	table.insert(connections, control.SelectionGained:Connect(function() selected = true; update() end))
	table.insert(connections, control.SelectionLost:Connect(function() selected = false; pressed = false; update() end))
	table.insert(connections, control.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Return then
			pressed = true
			update()
		end
	end))
	table.insert(connections, control.InputEnded:Connect(function() pressed = false; update() end))
	table.insert(connections, control:GetPropertyChangedSignal("Active"):Connect(update))
	control.Destroying:Connect(function()
		if tween then tween:Cancel() end
		for _, connection in connections do connection:Disconnect() end
	end)
end

return PopupStyle
