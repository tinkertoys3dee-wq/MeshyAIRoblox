--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Colors = Theme.Colors
local UIAssets = require(ReplicatedStorage:WaitForChild("UIAssets"))
local Motion = require(script.Parent.Motion)

local function optionalAssets(name: string): { [string]: any }
	local success, assets = pcall(function()
		local module = ReplicatedStorage:FindFirstChild(name)
		return if module then require(module) else {}
	end)
	return if success and type(assets) == "table" then assets else {}
end

local ScreenAssets = optionalAssets("ScreenAssets")
local HomeAssets = optionalAssets("HomeAssets")

local Factory = {}

-- Shared screen artwork is exported at 240px wide, without outside padding.
-- Panels are 240x240; rounded controls are 240x64. Keep these source-pixel
-- centres synchronized with design/export_screen_assets.py.
local SLICE_CENTER = {
	PanelBlue = Rect.new(30, 30, 210, 210),
	PanelPurple = Rect.new(30, 30, 210, 210),
	PanelGold = Rect.new(30, 30, 210, 210),
	ButtonBlue = Rect.new(30, 30, 210, 34),
	ButtonPurple = Rect.new(30, 30, 210, 34),
	ButtonGold = Rect.new(30, 30, 210, 34),
	ButtonQuiet = Rect.new(30, 30, 210, 34),
	ButtonDanger = Rect.new(30, 30, 210, 34),
	SearchField = Rect.new(30, 30, 210, 34),
	SectionHeader = Rect.new(30, 30, 210, 34),
}

local SURFACE_NAMES = {
	GraphicComposer = "Purple",
	GraphicActivity = "Purple",
	CommunityItem = "Purple",
	CommunityGraphic = "Purple",
	Collection = "Purple",
	StarterLook = "Purple",
	StyleSprint = "Purple",
	Gallery = "Gold",
	GraphicGallery = "Gold",
	GraphicsGallery = "Gold",
	GraphicItem = "Gold",
	TokensCard = "Gold",
	DailyBrief = "Gold",
	DailyQuests = "Gold",
	PlayChoice = "Gold",
	Arcade = "Gold",
	ArcadeModal = "Gold",
	GameOverCard = "Gold",
	Runway = "Purple",
	RunwayModal = "Purple",
}

local function surfaceOf(target: Instance?): string
	local current = target
	while current do
		local surface = current:GetAttribute("ForgeSurface")
		if type(surface) == "string" then
			return surface
		end
		current = current.Parent
	end
	return "Blue"
end

local function accent(surface: string): Color3
	return if surface == "Purple" then Colors.Violet elseif surface == "Gold" then Colors.Gold else Colors.Cyan
end

local function panelStops(surface: string): { Color3 }
	if Theme.IsHighContrast then
		return { Colors.PanelRaised, Colors.Panel }
	elseif surface == "Purple" then
		return { Color3.fromRGB(66, 42, 100), Color3.fromRGB(28, 23, 52) }
	elseif surface == "Gold" then
		return { Color3.fromRGB(66, 55, 32), Color3.fromRGB(30, 27, 24) }
	end
	return { Color3.fromRGB(34, 57, 96), Color3.fromRGB(16, 28, 50) }
end

local function buttonStops(surface: string): { Color3 }
	if surface == "Purple" then
		return { Color3.fromRGB(159, 75, 246), Color3.fromRGB(93, 38, 177) }
	elseif surface == "Gold" then
		return { Color3.fromRGB(244, 198, 76), Color3.fromRGB(192, 133, 28) }
	end
	return { Color3.fromRGB(15, 153, 239), Color3.fromRGB(5, 84, 173) }
end

local function bindSliceScale(decal: ImageLabel, target: GuiObject)
	local function apply()
		local isPanel = string.sub(decal:GetAttribute("ForgeAssetKey") or "", 1, 5) == "Panel"
		local size = target.AbsoluteSize
		local desired = if isPanel then 0.65 else math.min(1, size.Y / 64)
		-- Tiny reset/remove controls must still have a stretchable centre.
		decal.SliceScale = math.max(0.1, math.min(desired, size.X / 62, size.Y / 62))
	end
	apply()
	local resized = target:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	target.Destroying:Connect(function()
		resized:Disconnect()
	end)
end

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
	-- Support an optional weighted family without changing caller APIs.
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
	if instance:IsA("GuiButton") then
		Motion.Bind(instance)
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
		TextTruncate = options.Truncate or (if options.AutomaticSize == Enum.AutomaticSize.Y
				or options.AutomaticSize == Enum.AutomaticSize.XY
			then Enum.TextTruncate.None
			else Enum.TextTruncate.AtEnd),
		AutomaticSize = options.AutomaticSize or Enum.AutomaticSize.None,
		ClipsDescendants = true,
		ZIndex = options.ZIndex or 1,
		Parent = parent,
	})
end

function Factory.Card(parent: Instance, size: UDim2, position: UDim2?, name: string?): Frame
	local surface = SURFACE_NAMES[name or ""] or surfaceOf(parent)
	local card = Factory.New("Frame", {
		Name = name or "Card",
		Size = size,
		Position = position or UDim2.new(),
		-- UIGradient multiplies the object's color; white preserves its stops.
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		-- Deliberately NOT ClipsDescendants: Roblox clips to the object's
		-- axis-aligned rectangle, not its UICorner shape, so a clipped card
		-- shows a visible square notch cut into its own rounded corners
		-- wherever a child's opaque background reaches into that curve.
		Parent = parent,
	})
	card:SetAttribute("ForgeSurface", surface)
	Factory.Corner(card)
	Factory.Stroke(card, accent(surface), if Theme.IsHighContrast then 0.08 else 0.25, 1.4)
	Factory.Gradient(card, panelStops(surface), 100)
	-- The art's panelSheen: white falling from 0.13 to nothing down the top
	-- of a panel, not a flat band that stops on a visible line. Sized in
	-- scale because the art scales it with the panel too (roughly a third of
	-- the tall sidebar, a fifth of a short content card), and carried by the
	-- gradient rather than BackgroundTransparency so the falloff is real.
	local gloss = Factory.New("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -2, 0.26, 0),
		Position = UDim2.fromOffset(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = card,
	})
	Factory.New("UISizeConstraint", { MaxSize = Vector2.new(math.huge, 120), Parent = gloss })
	Factory.New("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.87),
			NumberSequenceKeypoint.new(0.6, 0.98),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
		Parent = gloss,
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
	local surface = if kind == "gold" then "Gold"
		elseif kind == "purple" then "Purple"
		elseif kind == "blue" then "Blue"
		else surfaceOf(parent)
	local background = Colors.PanelSoft
	local foreground = Colors.Text
	local primary = kind == "primary" or kind == "mint" or kind == "blue" or kind == "purple" or kind == "gold"
	if primary then
		background = Color3.new(1, 1, 1)
		if surface == "Gold" then
			foreground = Colors.Ink
		end
	elseif kind == "danger" then
		background = Color3.fromRGB(113, 34, 59)
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
	button:SetAttribute("ForgeSurface", surface)
	Factory.Corner(button, Theme.SmallCorner)
	Factory.Stroke(
		button,
		if kind == "danger" then Colors.Danger elseif primary then accent(surface) else Colors.Line,
		if primary or kind == "danger" then 0.12 else 0.4,
		1.3
	)
	if primary then
		Factory.Gradient(button, buttonStops(surface), 90)
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
	Factory.LiftLabel(button)
	return button
end

function Factory.Pill(parent: Instance, text: string, color: Color3?, width: number?): TextLabel
	local pill = Factory.New("TextLabel", {
		Name = "Pill",
		Size = UDim2.fromOffset(width or math.max(72, #text * 7 + 24), 27),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Text = string.upper(text),
		TextColor3 = color or Colors.Text,
		Font = Theme.Fonts.Bold,
		TextSize = 10,
		-- Pills neither wrap nor scale, so an over-long caption used to run
		-- straight out through both ends of the capsule.
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = parent,
	})
	Factory.Corner(pill, 99)
	Factory.Stroke(pill, color or Colors.Line, if Theme.IsHighContrast then 0.1 else 0.28)
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
		-- Preserve the helper for older callers while retiring this decoration.
		Visible = false,
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

-- Text-free SVG artwork dresses the existing controls. Their text, enabled
-- state, selection, focus, callbacks and live contents remain native.

-- A TextButton/TextLabel's own native Text always renders BELOW every child
-- it has, no matter what ZIndex the child is given -- ZIndex only orders
-- children against each other, never against the parent's own text/background
-- paint. So anything a caller parents to a button -- a decal, but equally the
-- nav rows' opaque icon medallion -- draws straight over the start of its own
-- label.
--
-- This lifts the label out: the native Text property stays the live value
-- callers all over App.luau keep reading and writing after creation (nav
-- labels, idea-chip icons, ...), and only its rendering is hidden, mirrored
-- into a real child that can sit above everything else.
--
-- Safe to call twice on the same object -- the second call is a no-op, so a
-- caller that lifts a label itself can still be handed to attachDecal later.
function Factory.LiftLabel(target: GuiObject): TextLabel?
	if not (target:IsA("TextButton") or target:IsA("TextLabel")) then
		return nil
	end
	local existing = target:FindFirstChild("Label")
	if existing and existing:IsA("TextLabel") then
		return existing
	end
	local textHolder = target :: TextButton | TextLabel
	local label = Factory.New("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = textHolder.Text,
		TextColor3 = textHolder.TextColor3,
		-- Mirror the resolved face, including its weight.
		FontFace = textHolder.FontFace,
		TextSize = textHolder.TextSize,
		TextWrapped = textHolder.TextWrapped,
		TextTruncate = textHolder.TextTruncate,
		TextXAlignment = textHolder.TextXAlignment,
		TextYAlignment = textHolder.TextYAlignment,
		RichText = textHolder.RichText,
		ClipsDescendants = true,
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
	-- The nav rows re-align their text on every resize (left beside the icon
	-- when the rail is wide, centred when it collapses to icons only), and a
	-- lifted label that kept its creation-time alignment would sit where the
	-- old layout put it.
	textHolder:GetPropertyChangedSignal("TextXAlignment"):Connect(function()
		label.TextXAlignment = textHolder.TextXAlignment
	end)
	for _, property in { "FontFace", "TextSize", "TextWrapped", "TextTruncate", "TextYAlignment", "RichText" } do
		textHolder:GetPropertyChangedSignal(property):Connect(function()
			(label :: any)[property] = (textHolder :: any)[property]
		end)
	end

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
	local function bindPadding(padding: UIPadding)
		applyPadding(padding)
		for _, property in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
			padding:GetPropertyChangedSignal(property):Connect(function()
				applyPadding(padding)
			end)
		end
	end
	local existingPadding = target:FindFirstChildOfClass("UIPadding")
	if existingPadding then
		bindPadding(existingPadding)
	end
	target.ChildAdded:Connect(function(child: Instance)
		if child:IsA("UIPadding") then
			bindPadding(child)
		end
	end)
	return label
end

-- Pad only a lifted button/label caption. A UIPadding parented directly to a
-- GuiButton also offsets its decorative children, which used to push the
-- sidebar medallions and icons to the right whenever we reserved a text
-- gutter for them. Keeping the padding on the lifted label makes the icon
-- geometry independent from the caption geometry.
function Factory.LabelPadding(target: GuiObject, horizontal: number, vertical: number?): UIPadding
	local label = Factory.LiftLabel(target)
	return Factory.Padding(label or target, horizontal, vertical)
end

local function modernKey(target: Instance, assetKey: string): string
	if assetKey == "PanelFrame" then
		return "Panel" .. surfaceOf(target)
	elseif assetKey == "ButtonPrimary" then
		return "Button" .. surfaceOf(target)
	elseif assetKey == "ButtonDefault" or assetKey == "PillFrame" then
		return "ButtonQuiet"
	elseif assetKey == "SectionBanner" then
		return "SectionHeader"
	end
	return assetKey
end

local decalRefresh: { [Instance]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

local function attachDecal(target: GuiObject, requestedKey: string): boolean
	local assetKey = modernKey(target, requestedKey)
	local assetId = ScreenAssets[assetKey]
	if Theme.IsHighContrast or type(assetId) ~= "number" or assetId <= 0 then
		return false
	end
	Factory.LiftLabel(target)
	local decal = Factory.New("ImageLabel", {
		Name = "Decal",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = `rbxassetid://{assetId}`,
		ImageTransparency = 0,
		Active = false,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = SLICE_CENTER[assetKey],
		SliceScale = 0.65,
		ZIndex = 0,
		Parent = target,
	})
	decal:SetAttribute("ForgeDecal", true)
	decal:SetAttribute("ForgeAssetKey", assetKey)
	bindSliceScale(decal, target)

	local backgroundAlpha = target.BackgroundTransparency
	local border = target:FindFirstChildOfClass("UIStroke")
	local borderAlpha = if border then border.Transparency else 0
	local overlays: { GuiObject } = {}
	for _, name in { "Gloss", "Shade" } do
		local child = target:FindFirstChild(name)
		if child and child:IsA("GuiObject") then
			table.insert(overlays, child :: GuiObject)
		end
	end
	local function refresh()
		-- Loading or moderated textures retain a readable native surface.
		local loaded = decal.Image ~= "" and decal.IsLoaded == true and not Theme.IsHighContrast
		decal.ImageTransparency = if Theme.IsHighContrast then 1 else 0
		target.BackgroundTransparency = if loaded then 1 else backgroundAlpha
		if border then
			local fallbackAlpha = border:GetAttribute("ForgeFallbackTransparency") or borderAlpha
			border.Transparency = if loaded then 1 else fallbackAlpha
		end
		for _, overlay in overlays do
			overlay.Visible = not loaded
		end
	end
	decalRefresh[decal] = refresh
	decal:GetPropertyChangedSignal("IsLoaded"):Connect(refresh)
	refresh()
	return true
end

function Factory.ImageCard(parent: Instance, size: UDim2, position: UDim2?, name: string?): Frame
	local card = Factory.Card(parent, size, position, name)
	attachDecal(card, "PanelFrame")
	return card
end

function Factory.ImageButton(parent: Instance, text: string, size: UDim2, position: UDim2?, kind: string?): TextButton
	local button = Factory.Button(parent, text, size, position, kind)
	local assetKey = if kind == "primary" or kind == "mint" or kind == "blue" or kind == "purple" or kind == "gold"
		then "Button" .. surfaceOf(button)
		elseif kind == "danger" then "ButtonDanger"
		else "ButtonQuiet"
	attachDecal(button, assetKey)
	return button
end

function Factory.ImagePill(parent: Instance, text: string, color: Color3?, width: number?): TextLabel
	local pill = Factory.Pill(parent, text, color, width)
	attachDecal(pill, "PillFrame")
	return pill
end

-- Existing callers reserve space above their panel for a caption. Keep that
-- geometry while replacing its ornamental tab with a clean rounded header.
function Factory.SectionBanner(card: GuiObject, text: string, width: number?): TextLabel
	local caption = string.upper(text)
	local banner = Factory.New("TextLabel", {
		Name = "SectionBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.fromOffset(width or math.clamp(#caption * 9 + 60, 120, 340), 30),
		BackgroundColor3 = Colors.Panel,
		BorderSizePixel = 0,
		Text = caption,
		TextColor3 = accent(surfaceOf(card)),
		Font = Theme.Fonts.Black,
		TextSize = 12,
		-- The width above clamps at 340, so a caption longer than that has
		-- nowhere left to grow into.
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 6,
		Parent = card,
	}) :: TextLabel
	Factory.Corner(banner, 12)
	Factory.Stroke(banner, accent(surfaceOf(card)), 0.28, 1.2)
	attachDecal(banner, "SectionHeader")
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

-- Settings toggles keep their state word and knob in separate columns.
local SWITCH_KNOB = 24

-- Moves a Factory.Switch to a state without rebuilding it, for a caller
-- that flips one optimistically and may have to roll it back (the sound
-- toggle, which reverts if the server rejects the change).
function Factory.SetSwitch(switch: GuiObject, on: boolean)
	switch.BackgroundColor3 = if on then Colors.Cyan else Colors.PanelSoft
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
	Factory.Stroke(switch, Colors.Cyan, 0.25, 1.4)
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
		BackgroundColor3 = Colors.Text,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = switch,
	})
	Factory.Corner(dot, SWITCH_KNOB / 2)
	Factory.Stroke(dot, Colors.Cyan, 0.35, 1)
	Factory.SetSwitch(switch, on)
	return switch
end

-- Legacy key names remain accepted by selection/toggle callbacks. Update
-- their fallback too, so changing a selected state works during loading.
function Factory.SwapDecal(target: Instance, requestedKey: string): boolean
	if not target:IsA("GuiObject") then
		return false
	end
	local assetKey = modernKey(target, requestedKey)
	if target:IsA("TextButton") and string.sub(assetKey, 1, 6) == "Button" then
		local primary = assetKey == "ButtonBlue" or assetKey == "ButtonPurple" or assetKey == "ButtonGold"
		local surface = if assetKey == "ButtonPurple" then "Purple"
			elseif assetKey == "ButtonGold" then "Gold"
			elseif assetKey == "ButtonBlue" then "Blue"
			else surfaceOf(target)
		if primary then
			target:SetAttribute("ForgeSurface", surface)
		end
		local gradient = target:FindFirstChildOfClass("UIGradient")
		if primary then
			target.BackgroundColor3 = Color3.new(1, 1, 1)
			if not gradient then
				gradient = Factory.Gradient(target, buttonStops(surface), 90)
			else
				local stops = buttonStops(surface)
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, stops[1]),
					ColorSequenceKeypoint.new(1, stops[2]),
				})
			end
			gradient.Enabled = true
		else
			target.BackgroundColor3 = if assetKey == "ButtonDanger" then Color3.fromRGB(113, 34, 59) else Colors.PanelSoft
			if gradient then
				gradient.Enabled = false
			end
		end
		target.TextColor3 = if primary and surface == "Gold" then Colors.Ink else Colors.Text
		local border = target:FindFirstChildOfClass("UIStroke")
		if border then
			border.Color = if assetKey == "ButtonDanger" then Colors.Danger elseif primary then accent(surface) else Colors.Line
			local transparency = if primary or assetKey == "ButtonDanger" then 0.12 else 0.4
			border:SetAttribute("ForgeFallbackTransparency", transparency)
			border.Transparency = transparency
		end
	end
	local decal = target:FindFirstChild("Decal")
	if not decal or not decal:IsA("ImageLabel") then
		return attachDecal(target :: GuiObject, assetKey)
	end
	local assetId = ScreenAssets[assetKey]
	local ready = not Theme.IsHighContrast and type(assetId) == "number" and assetId > 0
	decal.ImageTransparency = 1
	decal.Image = if ready then `rbxassetid://{assetId}` else ""
	decal:SetAttribute("ForgeAssetKey", assetKey)
	local sliceCenter = SLICE_CENTER[assetKey]
	if sliceCenter then
		decal.SliceCenter = sliceCenter
	end
	local refresh = decalRefresh[decal]
	if refresh then
		refresh()
	end
	return ready
end

-- Small square medallion icon (nav row, brand mark, ...). Returns nil when
-- that asset hasn't been uploaded yet, so a call site can keep its existing
-- code-drawn icon visible as a fallback instead of showing a blank square --
-- see App.luau's nav-row loop for the pattern (build the icon, only hide the
-- unicode-symbol label if this returns non-nil).
function Factory.Icon(parent: Instance, assetKey: string, size: UDim2, position: UDim2?): ImageLabel?
	local modernIcons = {
		Logo = "LogoMark",
		NavCreate = "NavCreate",
		NavDiscover = "NavMarket",
		NavSettings = "SettingsButton",
	}
	local retired = {
		FlourishDivider = true,
		CornerOrnament = true,
		RivetStud = true,
		TopbarCurve = true,
		PriceCartouche = true,
		NavStudio = true,
		NavAvatarLab = true,
		NavAvatarArt = true,
	}
	if retired[assetKey] then
		return nil
	end
	local modernIcon = modernIcons[assetKey]
	local assetId = if modernIcon then HomeAssets[modernIcon] else (UIAssets :: any)[assetKey]
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
	-- Compatibility hook: the approved screens use a clean text link.
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
