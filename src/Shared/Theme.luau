--!strict

return table.freeze({
	Colors = table.freeze({
		Ink = Color3.fromRGB(8, 11, 23),
		Panel = Color3.fromRGB(17, 22, 42),
		PanelRaised = Color3.fromRGB(27, 34, 61),
		PanelSoft = Color3.fromRGB(36, 43, 74),
		Line = Color3.fromRGB(72, 83, 128),
		Text = Color3.fromRGB(247, 249, 255),
		TextMuted = Color3.fromRGB(168, 178, 207),
		Violet = Color3.fromRGB(135, 94, 255),
		Cyan = Color3.fromRGB(55, 220, 255),
		Mint = Color3.fromRGB(76, 239, 175),
		Rose = Color3.fromRGB(255, 91, 151),
		Gold = Color3.fromRGB(255, 196, 82),
		Danger = Color3.fromRGB(255, 91, 106),
	}),
	Corner = 16,
	SmallCorner = 10,
	StrokeTransparency = 0.45,
	Fonts = table.freeze({
		Regular = Enum.Font.Gotham,
		Medium = Enum.Font.GothamMedium,
		Bold = Enum.Font.GothamBold,
		Black = Enum.Font.GothamBlack,
	}),
})
