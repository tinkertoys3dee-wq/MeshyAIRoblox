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
	-- Vertical scrollbars draw inside their ScrollingFrame by default, which
	-- lets cards and text sit underneath the thumb. Reserve that strip for
	-- every vertical/bidirectional scrolling region; horizontal chip rows are
	-- intentionally excluded because they have no visible vertical bar.
	if
		instance:IsA("ScrollingFrame")
		and instance.ScrollingDirection ~= Enum.ScrollingDirection.X
		and (not properties or properties.VerticalScrollBarInset == nil)
	then
		instance.VerticalScrollBarInset = Enum.ScrollBarInset.Always
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

function Factory.ScalePadding(parent: Instance, horizontal: number, vertical: number?): UIPadding
	local y = vertical or horizontal
	local rightOffset = if parent:IsA("ScrollingFrame")
			and parent.ScrollingDirection ~= Enum.ScrollingDirection.X
		then 12
		else 0
	return Factory.New("UIPadding", {
		PaddingLeft = UDim.new(horizontal, 0),
		PaddingRight = UDim.new(horizontal, rightOffset),
		PaddingTop = UDim.new(y, 0),
		PaddingBottom = UDim.new(y, 0),
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
		-- Deliberately NOT ClipsDescendants: Roblox clips to the object's
		-- axis-aligned rectangle, not its UICorner shape, so a clipped card
		-- shows a visible square notch cut into its own rounded corners
		-- wherever a child's opaque background reaches into that curve.
		Parent = parent,
	})
	Factory.Corner(card)
	Factory.Stroke(card)
	-- The gradient's own colors render the card's visible surface (a
	-- UIGradient paints over BackgroundColor3), so the mid-tone target lives
	-- here, not just in Colors.PanelRaised.
	Factory.Gradient(card, {
		Color3.fromRGB(64, 72, 104),
		Color3.fromRGB(46, 52, 80),
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
	-- A soft ground shadow cast just below the card -- a child (not a
	-- sibling) so it can't become a phantom cell in a caller's
	-- UIGridLayout/UIListLayout, the way an extra sibling Frame would.
	-- Fades via transparency rather than sitting at one flat value, so it
	-- reads as a soft falloff instead of a hard second rectangle.
	local dropShadow = Factory.New("Frame", {
		Name = "DropShadow",
		Position = UDim2.new(0, 6, 1, 0),
		Size = UDim2.new(1, -12, 0, 10),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = card,
	})
	Factory.New("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
		Parent = dropShadow,
	})
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
	-- A soft top highlight and bottom shade -- alpha-blended white/black
	-- overlays rather than a second UIGradient, so a button whose caller
	-- reassigns BackgroundColor3 later (the Settings sound toggle, selected
	-- quality chips, ...) still shows its real color instead of whatever a
	-- gradient was baked with at creation time. Every kind gets this, not
	-- just primary, so flat fills read as raised pills too.
	local glossRadius = math.max(Theme.SmallCorner - 1, 0)
	local gloss = Factory.New("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -2, 0.45, 0),
		Position = UDim2.fromOffset(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Parent = button,
	})
	Factory.Corner(gloss, glossRadius)
	local shade = Factory.New("Frame", {
		Name = "Shade",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(1, -2, 0.4, 0),
		Position = UDim2.new(0, 1, 1, -1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		Parent = button,
	})
	Factory.Corner(shade, glossRadius)
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
	-- The same top-highlight overlay Button uses, so pills read with a touch
	-- of the same glassy depth instead of sitting perfectly flat.
	local gloss = Factory.New("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -2, 0.5, 0),
		Position = UDim2.fromOffset(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Parent = pill,
	})
	Factory.Corner(gloss, 99)
	return pill
end

-- A soft, oversized, mostly-transparent circle used purely as a background
-- accent. Roblox frames can't blur, so a large low-opacity circle sitting
-- behind normal content is the cheapest way to add the same sense of depth a
-- blurred color blob gives a page, without hurting text contrast in front of
-- it. Callers should parent it first (or set a low ZIndex) so it renders
-- behind everything else.
function Factory.Blob(parent: Instance, diameter: number, position: UDim2, color: Color3, transparency: number?): Frame
	local blob = Factory.New("Frame", {
		Name = "Blob",
		Size = UDim2.fromOffset(diameter, diameter),
		Position = position,
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0.9,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = parent,
	})
	Factory.Corner(blob, diameter / 2)
	return blob
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
