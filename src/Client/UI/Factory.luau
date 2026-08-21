--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Colors = Theme.Colors

local Factory = {}

function Factory.New(className: string, properties: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	if properties then
		local parent = properties.Parent
		for property, value in properties do
			if property ~= "Parent" then
				(instance :: any)[property] = value
			end
		end
		if parent then
			instance.Parent = parent
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	return instance
end

function Factory.Corner(parent: Instance, radius: number?): UICorner
	return Factory.New("UICorner", {
		CornerRadius = UDim.new(0, radius or Theme.Corner),
		Parent = parent,
	})
end

function Factory.Stroke(parent: Instance, color: Color3?, transparency: number?, thickness: number?): UIStroke
	return Factory.New("UIStroke", {
		Color = color or Colors.Line,
		Transparency = transparency or Theme.StrokeTransparency,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Factory.Gradient(parent: Instance, colors: { Color3 }, rotation: number?): UIGradient
	local keypoints = {}
	for index, color in colors do
		local alpha = if #colors == 1 then 0 else (index - 1) / (#colors - 1)
		table.insert(keypoints, ColorSequenceKeypoint.new(alpha, color))
	end
	return Factory.New("UIGradient", {
		Color = ColorSequence.new(keypoints),
		Rotation = rotation or 0,
		Parent = parent,
	})
end

function Factory.Padding(parent: Instance, horizontal: number, vertical: number?): UIPadding
	local y = vertical or horizontal
	return Factory.New("UIPadding", {
		PaddingLeft = UDim.new(0, horizontal),
		PaddingRight = UDim.new(0, horizontal),
		PaddingTop = UDim.new(0, y),
		PaddingBottom = UDim.new(0, y),
		Parent = parent,
	})
end

function Factory.Label(parent: Instance, text: string, size: UDim2, options: { [string]: any }?): TextLabel
	options = options or {}
	return Factory.New("TextLabel", {
		Name = options.Name or "Label",
		Size = size,
		Position = options.Position or UDim2.new(),
		AnchorPoint = options.AnchorPoint or Vector2.zero,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = options.Color or Colors.Text,
		TextTransparency = options.Transparency or 0,
		Font = options.Font or Theme.Fonts.Regular,
		TextSize = options.TextSize or 15,
		TextXAlignment = options.AlignX or Enum.TextXAlignment.Left,
		TextYAlignment = options.AlignY or Enum.TextYAlignment.Center,
		TextWrapped = options.Wrapped == true,
		RichText = options.RichText == true,
		TextTruncate = options.Truncate or Enum.TextTruncate.None,
		ZIndex = options.ZIndex or 1,
		Parent = parent,
	})
end

function Factory.Card(parent: Instance, size: UDim2, position: UDim2?, name: string?): Frame
	local card = Factory.New("Frame", {
		Name = name or "Card",
		Size = size,
		Position = position or UDim2.new(),
		BackgroundColor3 = Colors.PanelRaised,
		BorderSizePixel = 0,
		Parent = parent,
	})
	Factory.Corner(card)
	Factory.Stroke(card)
	Factory.Gradient(card, {
		Color3.fromRGB(35, 42, 76),
		Color3.fromRGB(20, 26, 50),
	}, 115)
	local gloss = Factory.New("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -2, 0, 46),
		Position = UDim2.fromOffset(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.94,
		BorderSizePixel = 0,
		Parent = card,
	})
	Factory.Corner(gloss, Theme.Corner - 1)
	return card
end

function Factory.Button(parent: Instance, text: string, size: UDim2, position: UDim2?, kind: string?): TextButton
	local background = Colors.PanelSoft
	local foreground = Colors.Text
	if kind == "primary" then
		background = Colors.Violet
	elseif kind == "mint" then
		background = Colors.Mint
		foreground = Colors.Ink
	elseif kind == "danger" then
		background = Colors.Danger
	end
	local button = Factory.New("TextButton", {
		Name = "Button",
		Size = size,
		Position = position or UDim2.new(),
		BackgroundColor3 = background,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = text,
		TextColor3 = foreground,
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextWrapped = true,
		Parent = parent,
	})
	Factory.Corner(button, Theme.SmallCorner)
	Factory.Stroke(button, if kind == "primary" then Colors.Cyan else Colors.Line, 0.55)
	if kind == "primary" then
		Factory.Gradient(button, { Colors.Violet, Color3.fromRGB(91, 94, 255), Colors.Cyan }, 12)
	end
	return button
end

function Factory.Pill(parent: Instance, text: string, color: Color3?, width: number?): TextLabel
	local pill = Factory.New("TextLabel", {
		Name = "Pill",
		Size = UDim2.fromOffset(width or math.max(72, #text * 7 + 24), 27),
		BackgroundColor3 = color or Colors.PanelSoft,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Text = string.upper(text),
		TextColor3 = Colors.Text,
		Font = Theme.Fonts.Bold,
		TextSize = 10,
		Parent = parent,
	})
	Factory.Corner(pill, 99)
	Factory.Stroke(pill, color or Colors.Line, 0.5)
	return pill
end

function Factory.List(parent: Instance, direction: Enum.FillDirection, gap: number): UIListLayout
	return Factory.New("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

return Factory
