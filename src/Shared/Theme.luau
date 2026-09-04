--!strict

-- The concept art's own surface ramp, read straight off its panelGlass
-- gradient (#33205E / #241645 / #1A1035) and its lettering (#EBDCFF over
-- #CDBBEE). The app had been slate/navy against art that is unmistakably
-- purple -- and since the PanelFrame decal carries the art's purple, every
-- code-drawn frame inside a card was reading a different colour from the
-- card around it.
--
-- Darker panels under the same lettering means every pairing gained
-- contrast rather than losing it: muted text on the softest panel goes
-- 4.77 to 6.15, and borders clear the 3.0 non-text threshold for the first
-- time (2.29 to 3.05). Accent hues are untouched.
local DEFAULT_COLORS = {
	Ink = Color3.fromRGB(26, 16, 53),
	Panel = Color3.fromRGB(36, 22, 69),
	PanelRaised = Color3.fromRGB(51, 32, 94),
	PanelSoft = Color3.fromRGB(68, 48, 120),
	Line = Color3.fromRGB(126, 108, 168),
	Text = Color3.fromRGB(243, 236, 255),
	TextMuted = Color3.fromRGB(205, 187, 238),
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
	Ink = Color3.fromRGB(4, 2, 12),
	Panel = Color3.fromRGB(10, 6, 20),
	PanelRaised = Color3.fromRGB(18, 12, 34),
	PanelSoft = Color3.fromRGB(30, 22, 52),
	Line = Color3.fromRGB(176, 160, 214),
	Text = Color3.fromRGB(255, 255, 255),
	TextMuted = Color3.fromRGB(226, 216, 244),
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
