--!strict

-- Shared native surfaces match the approved SVG screens. The uploaded
-- artwork supplies their detail; these colors keep fields, live viewports,
-- loading states and accessibility mode in the same palette.
local DEFAULT_COLORS = {
	Ink = Color3.fromRGB(11, 19, 35),
	Panel = Color3.fromRGB(17, 29, 51),
	PanelRaised = Color3.fromRGB(29, 48, 79),
	PanelSoft = Color3.fromRGB(38, 61, 95),
	Line = Color3.fromRGB(79, 111, 154),
	Text = Color3.fromRGB(246, 250, 255),
	TextMuted = Color3.fromRGB(176, 190, 217),
	Violet = Color3.fromRGB(191, 103, 255),
	Cyan = Color3.fromRGB(0, 202, 255),
	Mint = Color3.fromRGB(73, 228, 182),
	Rose = Color3.fromRGB(255, 112, 186),
	Gold = Color3.fromRGB(255, 208, 78),
	Danger = Color3.fromRGB(255, 101, 119),
}

-- A brighter, higher-contrast palette for the optional accessibility toggle.
-- Backgrounds go darker and near-black, borders and muted text go lighter,
-- so every WCAG-relevant pairing (text-on-panel, line-on-panel) widens.
local HIGH_CONTRAST_COLORS = {
	Ink = Color3.fromRGB(3, 7, 14),
	Panel = Color3.fromRGB(7, 14, 25),
	PanelRaised = Color3.fromRGB(12, 23, 39),
	PanelSoft = Color3.fromRGB(19, 34, 54),
	Line = Color3.fromRGB(178, 211, 247),
	Text = Color3.fromRGB(255, 255, 255),
	TextMuted = Color3.fromRGB(223, 234, 250),
	Violet = Color3.fromRGB(216, 173, 255),
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
	Corner = 20,
	SmallCorner = 16,
	StrokeTransparency = 0.32,
	-- Native text stays editable and uses the same clean sans register as
	-- the SVGs. Existing Display/Black callers retain their stronger weight.
	Fonts = table.freeze({
		Regular = Enum.Font.Gotham,
		Medium = Enum.Font.GothamMedium,
		Bold = Enum.Font.GothamBold,
		Display = Enum.Font.GothamBold,
		Black = Enum.Font.GothamBlack,
	}),
}

function Theme.SetHighContrast(enabled: boolean)
	local source = if enabled then HIGH_CONTRAST_COLORS else DEFAULT_COLORS
	for key, value in source do
		Colors[key] = value
	end
	Theme.IsHighContrast = enabled
end

return Theme
