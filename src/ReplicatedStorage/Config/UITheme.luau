--!strict
-- Explorer: ReplicatedStorage/Config/UITheme (ModuleScript)
-- Cartoon-simulator look used by every screen and world-space label: chunky
-- rounded fonts with a dark ink outline, bright gradient buttons with a 3D
-- lip, light panels with a thick ink border. Colours and fonts live only here.

local UITheme = {}

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

export type Swatch = { top: Color3, bottom: Color3, edge: Color3 }
export type SwatchName = "green" | "gold" | "blue" | "purple" | "red" | "orange" | "pink" | "cyan" | "grey" | "dark"

UITheme.Colors = {
	Ink = hex("1A1F36"), -- every outline and text stroke
	White = hex("FFFFFF"),
	Text = hex("FFFFFF"), -- HUD text, always drawn with an Ink stroke
	TextDark = hex("26324F"), -- text on light panels and cards
	TextDim = hex("7A86A6"),
	PanelTop = hex("FFFFFF"),
	PanelBottom = hex("D9E6FF"),
	Card = hex("F2F6FF"),
	CardEdge = hex("B9C8EA"),
	Shade = hex("101428"), -- translucent backing behind HUD pills
	Gold = hex("FFC93C"),
	Green = hex("4CD964"),
	Blue = hex("39A0FF"),
	Purple = hex("A55CFF"),
	Red = hex("FF4D5E"),
	Orange = hex("FF9A2E"),
	Cyan = hex("3FE0FF"),
	Pink = hex("FF6FD8"),

	-- Legacy names kept for world-space code (signs, floating text).
	Amber = hex("FFC93C"),
	Teal = hex("4CD964"),
	Warn = hex("FF4D5E"),
	Panel = hex("26324F"),
	PanelOutline = hex("1A1F36"),
	PanelInset = hex("1A1F36"),
	TextOnAccent = hex("1A1F36"),
	Muted = hex("9AA3B5"),
}

-- Button / bar / header gradients: top -> bottom face, plus the darker lip.
UITheme.Swatches = {
	green = { top = hex("8CF58C"), bottom = hex("2DBE4A"), edge = hex("1B8434") },
	gold = { top = hex("FFE66E"), bottom = hex("FFAE1F"), edge = hex("C27400") },
	blue = { top = hex("74CBFF"), bottom = hex("2B83EF"), edge = hex("1A57AC") },
	purple = { top = hex("CB94FF"), bottom = hex("8743F2"), edge = hex("5A28AE") },
	red = { top = hex("FF8790"), bottom = hex("EE2E40"), edge = hex("A21B29") },
	orange = { top = hex("FFC766"), bottom = hex("FF861F"), edge = hex("BF5600") },
	pink = { top = hex("FF9BE6"), bottom = hex("F04FB8"), edge = hex("A82C7E") },
	cyan = { top = hex("8CF1FF"), bottom = hex("1FB8E6"), edge = hex("0F7FA6") },
	grey = { top = hex("E9EDF4"), bottom = hex("B5BED0"), edge = hex("848EA3") },
	dark = { top = hex("4B5679"), bottom = hex("2C3554"), edge = hex("161B30") },
} :: { [string]: Swatch }

-- Ore rarity 1..5 (GameConfig.Ores[].rarity) and pet tiers share one ramp.
UITheme.Rarity = {
	{ name = "Common", color = hex("B8C2D6"), swatch = "grey" },
	{ name = "Uncommon", color = hex("6BE07B"), swatch = "green" },
	{ name = "Rare", color = hex("4FB3FF"), swatch = "blue" },
	{ name = "Epic", color = hex("B66BFF"), swatch = "purple" },
	{ name = "Legendary", color = hex("FFC93C"), swatch = "gold" },
} :: { { name: string, color: Color3, swatch: string } }

UITheme.PetTier = {
	common = 1,
	uncommon = 2,
	rare = 3,
	epic = 4,
	legendary = 5,
} :: { [string]: number }

UITheme.Font = {
	Body = Font.fromEnum(Enum.Font.FredokaOne),
	Display = Font.fromEnum(Enum.Font.LuckiestGuy),
}

UITheme.Radius = 14 -- px, panels and buttons
UITheme.Stroke = 3 -- px, ink outline on panels and buttons
UITheme.TextStroke = 2 -- px, ink outline on text
UITheme.Lip = 5 -- px, height of the darker 3D lip under buttons
UITheme.Padding = 12
UITheme.Gap = 10
UITheme.TapMin = 48

-- Text sizes are px at 1x; the root UIScale multiplies for small screens.
UITheme.TextSize = {
	Small = 15,
	Body = 19,
	Title = 28,
	Display = 42,
	Hero = 96,
}

UITheme.Easing = {
	Pop = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Settle = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Slide = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	SlideOut = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Count = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Bar = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Flash = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
}

function UITheme.swatch(name: string?): Swatch
	return UITheme.Swatches[name or "blue"] or UITheme.Swatches.blue
end

function UITheme.rarity(rarity: number): { name: string, color: Color3, swatch: string }
	return UITheme.Rarity[math.clamp(math.floor(rarity), 1, #UITheme.Rarity)]
end

--- Vertical two-stop gradient as a ColorSequence (top -> bottom with Rotation 90).
function UITheme.sequence(top: Color3, bottom: Color3): ColorSequence
	return ColorSequence.new(top, bottom)
end

return UITheme
