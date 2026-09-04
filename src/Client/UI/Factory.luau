--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Colors = Theme.Colors
local UIAssets = require(ReplicatedStorage:WaitForChild("UIAssets"))

local Factory = {}

-- design/manifest.json's sliceCenter for each sliced decal, mirrored here
-- since Luau can't read that JSON file at runtime.
local SLICE_CENTER = {
	PanelFrame = Rect.new(78, 78, 162, 162),
	-- Buttons, pills and the banner are all the concept art's notched
	-- hexagon, so all four are 3-sliced rather than 9-sliced: the centre
	-- band spans the source's full height, leaving only the flat middle to
	-- stretch and the two angled end caps untouched. Keep in sync with
	-- export_ui_assets.py's BTN_*/PILL_*/BANNER_* values.
	ButtonPrimary = Rect.new(42, 0, 198, 120),
	ButtonDefault = Rect.new(42, 0, 198, 120),
	ButtonDanger = Rect.new(42, 0, 198, 120),
	PillFrame = Rect.new(34, 0, 166, 100),
	SectionBanner = Rect.new(48, 0, 192, 120),
}

-- A slice border draws at its source size unless scaled down. For the panel
-- that mattered because its 78px gold filigree reached ~40px into the card
-- and swallowed the left edge of every section title sitting at x=16. For
-- the hexagons it matters because each is drawn well above the size it
-- renders at, to keep its diagonals crisp: without this a 42px cap would
-- eat a third of a short button, instead of landing on the art's own
-- proportion of about 0.7 of the shape's half-height.
local SLICE_SCALE = {
	PanelFrame = 0.6,
	ButtonPrimary = 0.35,
	ButtonDefault = 0.35,
	ButtonDanger = 0.35,
	PillFrame = 0.28,
	SectionBanner = 0.25,
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
	-- Every caller asks for a font by Enum (Theme.Fonts.*), but the display
	-- serif only exists at one weight there and the art sets it bold. Upgrade
	-- it to the weighted FontFace centrally, so no call site has to know --
	-- FontFace overrides Font, so this is the only place the two can differ.
	if
		Theme.DisplayFace
		and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
		and (instance :: any).Font == Theme.Fonts.Display
	then
		(instance :: any).FontFace = Theme.DisplayFace
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
		-- The art sets every button label in its display serif, next to the
		-- sans it keeps for descriptions and for the pill metadata below.
		Font = Theme.Fonts.Display,
		TextSize = 14,
		TextWrapped = true,
		-- A label that outgrows its button -- a long item name, a localised
		-- price, a serif that sets wider than the sans this was sized for --
		-- otherwise wraps to a second line and has its bottom half sliced off
		-- by the button's own height. Truncation applies to the last visible
		-- line, so it degrades to an ellipsis instead.
		TextTruncate = Enum.TextTruncate.AtEnd,
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
		-- Pills neither wrap nor scale, so an over-long caption used to run
		-- straight out through both ends of the capsule.
		TextTruncate = Enum.TextTruncate.AtEnd,
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

-- Roblox has no dashed UIStroke, and the art dashes a ring in two places --
-- the backdrop's arcane circles and a locked achievement's rim. Draws the
-- dashes around the inside edge of whatever it is parented to, in scale, so
-- the caller does not have to know the ring's pixel size.
function Factory.DashedRing(
	parent: Instance,
	dashes: number,
	dashLength: number,
	color: Color3,
	transparency: number,
	thickness: number
)
	for index = 1, dashes do
		local degrees = (index - 1) / dashes * 360
		local radians = math.rad(degrees)
		Factory.New("Frame", {
			Name = string.format("Dash%d", index),
			AnchorPoint = Vector2.new(0.5, 0.5),
			-- Half of 1.0 in scale is the parent's own edge.
			Position = UDim2.fromScale(0.5 + math.cos(radians) / 2, 0.5 + math.sin(radians) / 2),
			Size = UDim2.fromOffset(dashLength, thickness),
			-- Tangent, so each dash lies along the ring.
			Rotation = degrees + 90,
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			Parent = parent,
		})
	end
end

-- The backdrop every one of the eight mockups is drawn over: a set of
-- concentric arcane rings with tick marks at the compass points, sitting
-- far behind the content at low opacity. It is the single thing that makes
-- the app read as a forge circle rather than a dark dashboard.
--
-- Sized off the container's HEIGHT through a square aspect constraint, so
-- it stays a circle rather than stretching into an ellipse as the window
-- gets wider, and every ring and tick is placed in scale rather than
-- pixels -- their real radius is not known until the layout resolves.
--
-- Roblox cannot dash a UIStroke, so the two dashed rings in the art are
-- built from small rotated segments the way Factory.RadialRing builds its
-- arc. They never move or update; this runs once.
local ARCANE_RINGS = {
	-- radius as a fraction of the circle's own half-size, then how it draws
	{ radius = 1.0, dashes = 0, thickness = 1.4, transparency = 0.85 },
	{ radius = 0.95, dashes = 54, thickness = 1.6, transparency = 0.86 },
	{ radius = 0.82, dashes = 26, thickness = 2.2, transparency = 0.84 },
	{ radius = 0.66, dashes = 0, thickness = 1, transparency = 0.88 },
}

function Factory.ArcaneCircle(parent: Instance, heightScale: number?): Frame
	local circle = Factory.New("Frame", {
		Name = "ArcaneCircle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- The art centres it left of middle and slightly low, so the rings
		-- read behind the content rather than haloing it.
		Position = UDim2.fromScale(0.38, 0.52),
		Size = UDim2.new(0, 0, heightScale or 0.9, 0),
		BackgroundTransparency = 1,
		ZIndex = 0,
		Parent = parent,
	})
	Factory.New("UIAspectRatioConstraint", {
		AspectRatio = 1,
		DominantAxis = Enum.DominantAxis.Height,
		Parent = circle,
	})

	for index, ring in ARCANE_RINGS do
		if ring.dashes == 0 then
			local outline = Factory.New("Frame", {
				Name = string.format("Ring%d", index),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(ring.radius, ring.radius),
				BackgroundTransparency = 1,
				ZIndex = 0,
				Parent = circle,
			})
			Factory.New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = outline })
			Factory.Stroke(outline, Colors.Cyan, ring.transparency, ring.thickness)
		else
			for dash = 1, ring.dashes do
				local degrees = (dash - 1) / ring.dashes * 360
				local radians = math.rad(degrees)
				-- Scale, not pixels: half the ring's fractional radius is how
				-- far from the centre a 0..1 scale position has to move.
				Factory.New("Frame", {
					Name = string.format("Ring%dDash%d", index, dash),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(
						0.5 + math.cos(radians) * ring.radius / 2,
						0.5 + math.sin(radians) * ring.radius / 2
					),
					Size = UDim2.fromOffset(if ring.dashes > 40 then 3 else 12, ring.thickness),
					-- Tangent to the circle, so the dashes lie along it
					-- rather than pointing out from the centre.
					Rotation = degrees + 90,
					BackgroundColor3 = Colors.Cyan,
					BackgroundTransparency = ring.transparency,
					BorderSizePixel = 0,
					ZIndex = 0,
					Parent = circle,
				})
			end
		end
	end

	-- Gold ticks at the four compass points and the four diagonals, just
	-- outside the widest ring.
	for index = 0, 7 do
		local degrees = index * 45
		local radians = math.rad(degrees)
		Factory.New("Frame", {
			Name = string.format("Tick%d", index),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.cos(radians) * 0.52, 0.5 + math.sin(radians) * 0.52),
			Size = UDim2.fromOffset(14, 1.6),
			-- Radial here, not tangent: these point out of the circle.
			Rotation = degrees,
			BackgroundColor3 = Colors.Gold,
			BackgroundTransparency = 0.78,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = circle,
		})
	end
	return circle
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
			-- FontFace, not Font: the display serif is set as a weighted
			-- face, and Font reads back as Unknown once it is, so mirroring
			-- the enum would silently drop every button label to the
			-- default face.
			FontFace = textHolder.FontFace,
			TextSize = textHolder.TextSize,
			TextWrapped = textHolder.TextWrapped,
			TextTruncate = textHolder.TextTruncate,
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

	-- Factory.Button/Pill draw their own rounded Gloss and Shade overlays,
	-- which fit a capsule and hang out past the corners of the hexagon the
	-- art actually uses. The hexagon art carries its own top highlight, so
	-- retire the code-drawn pair whenever a decal takes over. Cards keep
	-- theirs: a panel really is a rounded rectangle.
	if target:IsA("TextButton") or target:IsA("TextLabel") then
		for _, overlay in { "Gloss", "Shade" } do
			local child = target:FindFirstChild(overlay)
			if child and child:IsA("GuiObject") then
				child.Visible = false
			end
		end
	end

	local decal = Factory.New("ImageLabel", {
		Name = "Decal",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = `rbxassetid://{assetId}`,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = SLICE_CENTER[assetKey],
		SliceScale = SLICE_SCALE[assetKey] or 1,
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

-- The concept art titles every panel with a small notched banner tab
-- straddling the card's own top edge -- "CREATE MODE", "COLLECTION * 6",
-- "YOUR LOOK" -- rather than a pill or label tucked inside the top-left
-- corner. It straddles that edge in the concept art's own proportion (12px
-- of a 30px tab above the card, 18px below), so callers need to leave the
-- card's first ~22px clear and ~12px of daylight above it.
--
-- Falls back to a plain rounded tab when SectionBanner's id is still 0,
-- like every other image-backed helper here.
function Factory.SectionBanner(card: GuiObject, text: string, width: number?): TextLabel
	local caption = string.upper(text)
	local banner = Factory.New("TextLabel", {
		Name = "SectionBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.fromOffset(width or math.clamp(#caption * 9 + 60, 120, 340), 30),
		BackgroundColor3 = Color3.fromRGB(46, 27, 84),
		BorderSizePixel = 0,
		Text = caption,
		TextColor3 = Colors.Gold,
		Font = Theme.Fonts.Black,
		TextSize = 12,
		-- The width above clamps at 340, so a caption longer than that has
		-- nowhere left to grow into.
		TextTruncate = Enum.TextTruncate.AtEnd,
		-- Above the card's own PanelFrame decal (ZIndex 0) and its Gloss, so
		-- the tab reads as sitting on top of the frame the way it does in
		-- the concept art.
		ZIndex = 6,
		Parent = card,
	}) :: TextLabel
	if not attachDecal(banner, "SectionBanner") then
		Factory.Corner(banner, 8)
		Factory.Stroke(banner, Colors.Gold, 0.25, 1.4)
	end
	return banner
end

-- A SectionBanner deliberately overhangs 12px above the card it titles. That
-- is fine mid-stack, where the gap between cards absorbs it, but the FIRST
-- card in a stack has nothing above it except the scrolling region's own
-- edge -- and every one of those clips, so the tab's top edge gets sliced
-- off. Give the stack the headroom rather than the card: the overhang is a
-- property of the layout, and the card should not have to know whether it
-- happens to be first.
function Factory.BannerHeadroom(stack: Instance): UIPadding
	return Factory.New("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		Parent = stack,
	})
end

-- The concept art's gold ON/OFF switch: a capsule with a gold knob that
-- sits on the side the state is on, and the state's word on the other.
-- Every one of Settings' real boolean options is drawn this way there
-- instead of as another full-width button.
local SWITCH_KNOB = 24

-- Moves a Factory.Switch to a state without rebuilding it, for a caller
-- that flips one optimistically and may have to roll it back (the sound
-- toggle, which reverts if the server rejects the change).
function Factory.SetSwitch(switch: GuiObject, on: boolean)
	switch.BackgroundColor3 = if on then Colors.Mint else Color3.fromRGB(42, 27, 76)
	local label = switch:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = if on then "ON" else "OFF"
		label.TextColor3 = if on then Colors.Ink else Colors.TextMuted
		label.Position = if on then UDim2.fromOffset(6, 0) else UDim2.fromOffset(SWITCH_KNOB + 6, 0)
	end
	local knob = switch:FindFirstChild("Knob")
	if knob and knob:IsA("Frame") then
		knob.Position = if on then UDim2.new(1, -(SWITCH_KNOB + 4), 0.5, 0) else UDim2.new(0, 4, 0.5, 0)
	end
end

function Factory.Switch(parent: Instance, on: boolean, position: UDim2?, width: number?): TextButton
	local switch = Factory.New("TextButton", {
		Name = "Switch",
		Size = UDim2.fromOffset(width or 92, 32),
		Position = position or UDim2.new(),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		-- The visible caption is a child label below, so the knob can never
		-- be hidden underneath a TextButton's own native text.
		Text = "",
		Parent = parent,
	})
	Factory.Corner(switch, 99)
	Factory.Stroke(switch, Colors.Gold, 0.25, 1.4)
	Factory.Label(switch, "", UDim2.new(1, -(SWITCH_KNOB + 12), 1, 0), {
		AlignX = Enum.TextXAlignment.Center,
		-- ON/OFF is metadata beside a control, which the art keeps in sans.
		Font = Theme.Fonts.Bold,
		TextSize = 11,
	})
	local dot = Factory.New("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(SWITCH_KNOB, SWITCH_KNOB),
		BackgroundColor3 = Colors.Gold,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = switch,
	})
	Factory.Corner(dot, SWITCH_KNOB / 2)
	Factory.Gradient(dot, { Color3.fromRGB(255, 243, 196), Colors.Gold }, 90)
	Factory.Stroke(dot, Color3.fromRGB(255, 243, 196), 0.35, 1)
	Factory.SetSwitch(switch, on)
	return switch
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
	decal.SliceScale = SLICE_SCALE[assetKey] or 1
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

-- The concept art flanks each page's centred "Switch to ... Mode" link with
-- one small gold flourish on either side of it. Positions both against the
-- parent's horizontal centre, so they stay paired with a link that is itself
-- centred however wide the page gets. No-op (like Factory.Icon) while
-- FlourishDivider's id is still 0.
function Factory.FlourishFlank(parent: Instance, centreY: number, halfGap: number, width: number?, height: number?)
	local w = width or 20
	local h = height or 14
	for _, side in { -1, 1 } do
		local flourish = Factory.Icon(
			parent,
			"FlourishDivider",
			UDim2.fromOffset(w, h),
			UDim2.new(0.5, if side < 0 then -halfGap - w else halfGap, 0, centreY - h // 2)
		)
		if flourish then
			flourish.ZIndex = 2
		end
	end
end

-- A circular 0-100% progress ring (the Creator Rank crest), built from
-- many small segment frames laid around a circle.
--
-- Roblox can't draw a partial-arc stroke, and the usual trick for this --
-- revealing one full-circle image through rotating clip-masks -- is
-- unusable here: ClipsDescendants does NOT clip a *rotated* descendant.
-- That was confirmed in-engine rather than assumed; the masks rendered
-- clear across the sidebar and out past the app window, and adding
-- ClipsDescendants on unrotated ancestors above them changed nothing.
-- Rotation on its own renders correctly though, so this rotates many
-- tiny segments into place and just recolours them -- no clipping, no
-- image, and nothing that depends on the engine quirk above.
--
-- Returns an updater to call with the current 0-1 progress fraction.
function Factory.RadialRing(
	parent: Instance,
	diameter: number,
	thickness: number,
	fillColor: Color3,
	trackColor: Color3,
	segments: number?
): (number) -> ()
	local count = segments or 60
	local radius = (diameter - thickness) / 2
	-- One segment's own width is the arc it has to span, plus a little
	-- overlap so neighbours meet as a continuous band rather than a
	-- dashed one.
	local segmentWidth = math.max(3, math.ceil(2 * math.pi * radius / count) + 2)
	local arc: { Frame } = {}
	for index = 1, count do
		-- -90 puts the first segment at 12 o'clock and runs them
		-- clockwise; +90 on Rotation turns each one tangent to the
		-- circle, so they form a ring rather than radial spokes.
		local degrees = (index - 1) / count * 360 - 90
		local radians = math.rad(degrees)
		arc[index] = Factory.New("Frame", {
			Name = string.format("Segment%d", index),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(radians) * radius, 0.5, math.sin(radians) * radius),
			Size = UDim2.fromOffset(segmentWidth, thickness),
			Rotation = degrees + 90,
			BackgroundColor3 = trackColor,
			BorderSizePixel = 0,
			Parent = parent,
		})
	end
	return function(progress: number)
		local filled = math.floor(math.clamp(progress, 0, 1) * count + 0.5)
		for index, segment in arc do
			segment.BackgroundColor3 = if index <= filled then fillColor else trackColor
		end
	end
end

return Factory
