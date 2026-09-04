--!strict

-- A mid-tone palette: dark enough to stay easy on the eyes for a long
-- creation session, light enough that panels read as slate/navy rather than
-- near-black. Accent hues are untouched; only the neutral surface ramp moved.
local DEFAULT_COLORS = {
	Ink = Color3.fromRGB(24, 27, 44),
	Panel = Color3.fromRGB(44, 50, 78),
	PanelRaised = Color3.fromRGB(60, 67, 98),
	PanelSoft = Color3.fromRGB(74, 82, 114),
	Line = Color3.fromRGB(112, 122, 160),
	Text = Color3.fromRGB(247, 249, 255),
	TextMuted = Color3.fromRGB(196, 204, 226),
	Violet = Color3.fromRGB(135, 94, 255),
	Cyan = Color3.fromRGB(55, 220, 255),
	Mint = Color3.fromRGB(76, 239, 175),
	Rose = Color3.fromRGB(255, 91, 151),
	Gold = Color3.fromRGB(255, 196, 82),
	Danger = Color3.fromRGB(255, 91, 106),
}

-- A brighter, higher-contrast palette for the optional accessibility toggle.
-- Backgrounds go darker and near-black, borders and muted text go lighter,
-- so every WCAG-relevant pairing (text-on-panel, line-on-panel) widens.
local HIGH_CONTRAST_COLORS = {
	Ink = Color3.fromRGB(2, 3, 8),
	Panel = Color3.fromRGB(8, 9, 16),
	PanelRaised = Color3.fromRGB(17, 18, 28),
	PanelSoft = Color3.fromRGB(28, 29, 42),
	Line = Color3.fromRGB(160, 170, 210),
	Text = Color3.fromRGB(255, 255, 255),
	TextMuted = Color3.fromRGB(216, 220, 236),
	Violet = Color3.fromRGB(184, 152, 255),
	Cyan = Color3.fromRGB(130, 238, 255),
	Mint = Color3.fromRGB(140, 255, 210),
	Rose = Color3.fromRGB(255, 150, 190),
	Gold = Color3.fromRGB(255, 219, 130),
	Danger = Color3.fromRGB(255, 150, 160),
}

-- Mutable and shared by reference: every module that captures
-- `Theme.Colors` at require-time (Factory, App, ...) holds the same table,
-- so toggling high contrast here is visible everywhere without those
-- modules re-requiring anything. Already-rendered GuiObjects still hold the
-- color values they were created with, so the client rebuilds its chrome
-- and re-renders the active page after calling SetHighContrast.
local Colors = table.clone(DEFAULT_COLORS)

local Theme = {
	Colors = Colors,
	IsHighContrast = false,
	Corner = 16,
	SmallCorner = 10,
	StrokeTransparency = 0.45,
	-- The concept art runs two type registers, and only two. A classical
	-- serif carries every NAMEPLATE -- page titles, panel captions, item and
	-- setting names, button labels, big figures -- and a plain sans carries
	-- everything EXPLANATORY: descriptions, helper prose, and the small caps
	-- metadata beside a control ("LEVEL", "YOUR BEST", "ON"/"OFF").
	--
	-- The art is set in Cinzel, which Roblox does not ship. Merriweather is
	-- the closest face Roblox does have that survives this app's real size
	-- range: the captions run as small as 9px, where Garamond's and Bodoni's
	-- thin strokes break up on screen.
	Fonts = table.freeze({
		Regular = Enum.Font.Gotham,
		Medium = Enum.Font.GothamMedium,
		Bold = Enum.Font.GothamBold,
		Display = Enum.Font.Merriweather,
		-- The older name for the same register. Every existing call site
		-- reaching for "Black" is already a nameplate -- a page title, a card
		-- name, a score -- exactly where the art sets its serif, so they all
		-- keep working unchanged.
		Black = Enum.Font.Merriweather,
	}),
	-- Enum.Font exposes Merriweather at one (regular) weight; the art sets
	-- its serif at 700 throughout. A FontFace carries a weight and overrides
	-- the Font property, so Factory applies this to anything asking for the
	-- display face. Built through pcall because a family path Roblox has
	-- since moved would otherwise throw at require time and take the whole
	-- client's UI down with it -- without the face, text simply renders at
	-- Merriweather's regular weight.
	DisplayFace = (function(): Font?
		local success, face = pcall(function()
			return Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
		end)
		return if success then face else nil
	end)(),
}

function Theme.SetHighContrast(enabled: boolean)
	local source = if enabled then HIGH_CONTRAST_COLORS else DEFAULT_COLORS
	for key, value in source do
		Colors[key] = value
	end
	Theme.IsHighContrast = enabled
end

return Theme
