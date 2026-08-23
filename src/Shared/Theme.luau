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
	Fonts = table.freeze({
		Regular = Enum.Font.Gotham,
		Medium = Enum.Font.GothamMedium,
		Bold = Enum.Font.GothamBold,
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
