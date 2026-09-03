--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Colors = Theme.Colors
local UIAssets = require(ReplicatedStorage:WaitForChild("UIAssets"))

local Factory = {}

-- design/manifest.json's sliceCenter for each 9-sliced decal, mirrored here
-- since Luau can't read that JSON file at runtime. Keep in sync if
-- design/export_ui_assets.py's PANEL_SLICE/BTN_SLICE/PILL_SLICE ever change.
local SLICE_CENTER = {
	PanelFrame = Rect.new(78, 78, 162, 162),
	ButtonPrimary = Rect.new(30, 30, 90, 90),
	ButtonDefault = Rect.new(30, 30, 90, 90),
	ButtonDanger = Rect.new(30, 30, 90, 90),
	PillFrame = Rect.new(22, 22, 58, 58),
}

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

-- ============================================================================
-- Decal-backed chrome
--
-- Each function below is a thin wrapper around its plain code-drawn
-- counterpart above (Card/Button/Pill): it builds the exact same instance
-- first, then -- only if design/upload_ui_assets.py (or apply_asset_ids.py)
-- has actually put a nonzero id in UIAssets for that piece -- swaps the flat
-- BackgroundColor3/Gradient fill for a 9-sliced decal from design/assets/,
-- inserted at ZIndex 0 so it stays behind the existing Gloss/Shade/
-- DropShadow overlays and text exactly as the flat fill did. Everything
-- interactive (the TextButton/TextLabel itself, its Activated event, text)
-- is completely unchanged -- only the art *behind* it differs. With every
-- id still 0 (the checked-in default), these behave identically to calling
-- Card/Button/Pill directly.
-- ============================================================================

local function attachDecal(target: GuiObject, assetKey: string): boolean
	local assetId = (UIAssets :: any)[assetKey]
	if type(assetId) ~= "number" or assetId == 0 then
		return false
	end
	target.BackgroundTransparency = 1

	-- A TextButton/TextLabel's own native Text always renders BELOW every
	-- child it has, no matter what ZIndex the child is given -- ZIndex only
	-- orders children against each other, never against the parent's own
	-- text/background paint. Left alone, the decal (a child) would always
	-- hide the button/pill's own label. Keep the native Text property as
	-- the live value callers all over App.luau keep reading and writing
	-- after creation (nav labels, idea-chip icons, ...) -- just hide its
	-- own rendering and mirror it into a real child that can sit above the
	-- decal.
	if target:IsA("TextButton") or target:IsA("TextLabel") then
		local textHolder = target :: TextButton | TextLabel
		local label = Factory.New("TextLabel", {
			Name = "Label",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = textHolder.Text,
			TextColor3 = textHolder.TextColor3,
			Font = textHolder.Font,
			TextSize = textHolder.TextSize,
			TextWrapped = textHolder.TextWrapped,
			TextXAlignment = textHolder.TextXAlignment,
			TextYAlignment = textHolder.TextYAlignment,
			ZIndex = 5,
			Parent = target,
		}) :: TextLabel
		textHolder.TextTransparency = 1
		textHolder:GetPropertyChangedSignal("Text"):Connect(function()
			label.Text = textHolder.Text
		end)
		textHolder:GetPropertyChangedSignal("TextColor3"):Connect(function()
			label.TextColor3 = textHolder.TextColor3
		end)

		-- UIPadding only insets its own object's native text (and any
		-- UIListLayout/UIGridLayout children) -- never an unrelated sibling
		-- child like `label`, which otherwise stays flush edge-to-edge and
		-- can crowd into an icon a caller placed at a fixed offset (the nav
		-- rows). Mirror any UIPadding onto the label too, whether it was
		-- added before this ran or (as with the nav rows) after.
		local function applyPadding(padding: UIPadding)
			local left, right = padding.PaddingLeft, padding.PaddingRight
			local top, bottom = padding.PaddingTop, padding.PaddingBottom
			label.Position = UDim2.new(left.Scale, left.Offset, top.Scale, top.Offset)
			label.Size = UDim2.new(
				1 - left.Scale - right.Scale,
				-(left.Offset + right.Offset),
				1 - top.Scale - bottom.Scale,
				-(top.Offset + bottom.Offset)
			)
		end
		local existingPadding = target:FindFirstChildOfClass("UIPadding")
		if existingPadding then
			applyPadding(existingPadding)
		end
		target.ChildAdded:Connect(function(child: Instance)
			if child:IsA("UIPadding") then
				applyPadding(child)
			end
		end)
	end

	local decal = Factory.New("ImageLabel", {
		Name = "Decal",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = `rbxassetid://{assetId}`,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = SLICE_CENTER[assetKey],
		ZIndex = 0,
		Parent = target,
	})
	decal:SetAttribute("ForgeDecal", true)
	return decal ~= nil
end

function Factory.ImageCard(parent: Instance, size: UDim2, position: UDim2?, name: string?): Frame
	local card = Factory.Card(parent, size, position, name)
	attachDecal(card, "PanelFrame")
	return card
end

function Factory.ImageButton(parent: Instance, text: string, size: UDim2, position: UDim2?, kind: string?): TextButton
	local button = Factory.Button(parent, text, size, position, kind)
	local assetKey = if kind == "primary" or kind == "mint"
		then "ButtonPrimary"
		elseif kind == "danger" then "ButtonDanger"
		else "ButtonDefault"
	attachDecal(button, assetKey)
	return button
end

function Factory.ImagePill(parent: Instance, text: string, color: Color3?, width: number?): TextLabel
	local pill = Factory.Pill(parent, text, color, width)
	attachDecal(pill, "PillFrame")
	return pill
end

-- Swaps a Factory.ImageCard/ImageButton/ImagePill's live decal to a
-- different asset key -- e.g. toggling a nav button between "ButtonDefault"
-- and "ButtonPrimary" for an inactive/active state, the decal equivalent of
-- what used to be a plain BackgroundColor3 change before attachDecal made
-- that invisible (a decal-covered target's own background is fully
-- transparent, so recoloring it no longer shows). No-op, keeping whatever
-- image is already showing, if that asset key's id is still 0 or the
-- target never had a decal attached in the first place.
function Factory.SwapDecal(target: Instance, assetKey: string): boolean
	local decal = target:FindFirstChild("Decal")
	if not decal or not decal:IsA("ImageLabel") then
		return false
	end
	local assetId = (UIAssets :: any)[assetKey]
	if type(assetId) ~= "number" or assetId == 0 then
		return false
	end
	decal.Image = `rbxassetid://{assetId}`
	local sliceCenter = SLICE_CENTER[assetKey]
	if sliceCenter then
		decal.SliceCenter = sliceCenter
	end
	return true
end

-- Small square medallion icon (nav row, brand mark, ...). Returns nil when
-- that asset hasn't been uploaded yet, so a call site can keep its existing
-- code-drawn icon visible as a fallback instead of showing a blank square --
-- see App.luau's nav-row loop for the pattern (build the icon, only hide the
-- unicode-symbol label if this returns non-nil).
function Factory.Icon(parent: Instance, assetKey: string, size: UDim2, position: UDim2?): ImageLabel?
	local assetId = (UIAssets :: any)[assetKey]
	if type(assetId) ~= "number" or assetId == 0 then
		return nil
	end
	return Factory.New("ImageLabel", {
		Name = assetKey,
		Size = size,
		Position = position or UDim2.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = `rbxassetid://{assetId}`,
		ScaleType = Enum.ScaleType.Fit,
		Parent = parent,
	}) :: ImageLabel
end

-- A circular 0-100% progress ring (e.g. the Creator Rank crest) from a
-- single full-circle image -- Roblox has no native way to draw a partial
-- arc, so this reveals a slice of the image via two rotating clip-masked
-- frames instead of needing one image per possible progress value.
--
-- Geometry (verified against 0%, 50%, 100%): a fixed right-half viewport
-- (ClipsDescendants) holds an oversized square mask pinned at its own
-- left-edge midpoint, which sits exactly on the ring's center; rotating
-- that mask clockwise sweeps its covered range from [12 o'clock, 6
-- o'clock] down to empty as it turns 0->180 degrees, so intersecting it
-- against the viewport's fixed half yields a *shrinking* covered wedge
-- from 12 o'clock down to the current angle -- i.e. a growing reveal from
-- 12 o'clock clockwise. A mirrored left-half viewport/mask (pinned at its
-- right edge) does the same for the 6-to-12 o'clock half, active only past
-- 50%. trackColor should match whatever the ring sits on (its own parent's
-- background, or a dedicated track circle behind it), since the masks are
-- opaque frames of that color covering the not-yet-filled arc.
--
-- Returns an updater to call with the current 0-1 progress fraction, or
-- nil if the asset hasn't been uploaded yet (same fallback contract as
-- every other Factory image helper).
function Factory.RadialRing(
	parent: Instance,
	assetKey: string,
	size: UDim2,
	position: UDim2?,
	trackColor: Color3
): ((number) -> ())?
	local assetId = (UIAssets :: any)[assetKey]
	if type(assetId) ~= "number" or assetId == 0 then
		return nil
	end
	local container = Factory.New("Frame", {
		Name = "RadialRing",
		Size = size,
		Position = position or UDim2.new(),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Factory.New("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = `rbxassetid://{assetId}`,
		ZIndex = 1,
		Parent = container,
	})
	local function buildMask(pivotX: number, viewportX: number): Frame
		local viewport = Factory.New("Frame", {
			Size = UDim2.fromScale(0.5, 1),
			Position = UDim2.fromScale(viewportX, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = 2,
			Parent = container,
		}) :: Frame
		return Factory.New("Frame", {
			AnchorPoint = Vector2.new(pivotX, 0.5),
			Position = UDim2.new(pivotX, 0, 0.5, 0),
			-- Oversized (2x the viewport in each axis) so its far corners
			-- clear the ring's radius at every rotation, no gaps at the
			-- edge of the swept wedge.
			Size = UDim2.fromScale(2, 2),
			BackgroundColor3 = trackColor,
			BorderSizePixel = 0,
			Parent = viewport,
		}) :: Frame
	end
	local maskRight = buildMask(0, 0.5)
	local maskLeft = buildMask(1, 0)
	return function(progress: number)
		local degrees = math.clamp(progress, 0, 1) * 360
		maskRight.Rotation = math.clamp(degrees, 0, 180)
		maskLeft.Rotation = math.clamp(degrees - 180, 0, 180)
	end
end

return Factory
