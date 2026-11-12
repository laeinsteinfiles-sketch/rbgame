--!strict
-- Explorer: ReplicatedStorage/Config/UITheme (ModuleScript)
-- The "plate" look of the top dig games (Dig to Earth's CORE!, Mining
-- Simulator 2): charcoal panels with thick near-black outlines, saturated
-- glossy plates with a darker 3D lip, white Fredoka One text with a heavy
-- black stroke, Luckiest Guy only for big banners. Colours and fonts live
-- only here.

local UITheme = {}

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

export type Swatch = { top: Color3, bottom: Color3, edge: Color3 }

UITheme.Colors = {
	Ink = hex("0C0C0C"), -- every outline and text stroke
	White = hex("FFFFFF"),
	Text = hex("FFFFFF"), -- always drawn with an Ink stroke
	TextDark = hex("1E1E24"), -- text on light plates (rare)
	TextDim = hex("B4B4C2"),
	PanelTop = hex("303036"),
	PanelBottom = hex("222226"),
	Card = hex("3A3A42"),
	CardBottom = hex("2F2F36"),
	Shade = hex("1A1A1E"), -- HUD pill backing
	Gold = hex("FFD93B"),
	Objective = hex("FFEB0C"),
	Green = hex("9BE40F"),
	Blue = hex("3CB4FC"),
	Periwinkle = hex("9EA0FA"),
	Purple = hex("8B6FE8"),
	Red = hex("FA5470"),
	Orange = hex("FF9A2E"),
	Cyan = hex("4FD8FF"),
	Pink = hex("F2527A"),

	-- Legacy names kept for world-space code (signs, floating text).
	Amber = hex("FFD93B"),
	Teal = hex("9BE40F"),
	Warn = hex("FA5470"),
	Panel = hex("242424"),
	PanelOutline = hex("0C0C0C"),
	PanelInset = hex("0C0C0C"),
	TextOnAccent = hex("0C0C0C"),
	Muted = hex("6E6E78"),
}

-- Plate gradients: top -> bottom face, plus the darker 3D lip.
UITheme.Swatches = {
	green = { top = hex("C6F75C"), bottom = hex("6FB80A"), edge = hex("477A05") },
	blue = { top = hex("82D3FF"), bottom = hex("2F9CF0"), edge = hex("1B66AD") },
	periwinkle = { top = hex("C8C9FF"), bottom = hex("8789F0"), edge = hex("5758BF") },
	red = { top = hex("FF8FA0"), bottom = hex("F0425F"), edge = hex("A6233F") },
	gold = { top = hex("FFE866"), bottom = hex("F5B400"), edge = hex("A87800") },
	orange = { top = hex("FFC766"), bottom = hex("FF841F"), edge = hex("B85200") },
	purple = { top = hex("A993FF"), bottom = hex("6C54CC"), edge = hex("44338C") },
	pink = { top = hex("FF96B5"), bottom = hex("F2527A"), edge = hex("A32E4E") },
	cyan = { top = hex("94F3FF"), bottom = hex("1FB8E6"), edge = hex("0E78A0") },
	grey = { top = hex("85858F"), bottom = hex("5A5A63"), edge = hex("38383E") },
	dark = { top = hex("4C4C55"), bottom = hex("2E2E34"), edge = hex("141417") },
} :: { [string]: Swatch }

-- Ore rarity 1..5 (GameConfig.Ores[].rarity) and pet tiers share one ramp.
UITheme.Rarity = {
	{ name = "Common", color = hex("C9CDD6"), swatch = "grey" },
	{ name = "Uncommon", color = hex("9BE40F"), swatch = "green" },
	{ name = "Rare", color = hex("3CB4FC"), swatch = "blue" },
	{ name = "Epic", color = hex("A993FF"), swatch = "purple" },
	{ name = "Legendary", color = hex("FFD93B"), swatch = "gold" },
	{ name = "Mythic", color = hex("FF6FB5"), swatch = "pink" },
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
	Display = Font.fromEnum(Enum.Font.FredokaOne),
	Banner = Font.fromEnum(Enum.Font.LuckiestGuy), -- countdown, rarity banners
}

UITheme.Radius = 14 -- px, plates and panels
UITheme.Stroke = 4 -- px, ink outline on panels
UITheme.ButtonStroke = 3.5 -- px, ink outline on plates
UITheme.TextStrokeRatio = 0.12 -- text outline as a fraction of text size
UITheme.TextStroke = 2.5 -- px, minimum text outline
UITheme.Lip = 5 -- px, height of the darker 3D lip under plates
UITheme.Padding = 12
UITheme.Gap = 10
UITheme.TapMin = 48

-- Text sizes are design px; the root UIScale multiplies for the screen.
UITheme.TextSize = {
	Small = 15,
	Body = 19,
	Title = 28,
	Display = 42,
	Hero = 96,
}

UITheme.Easing = {
	Pop = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Settle = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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

--- Outline thickness for text of a given size (about 12%, never thinner than 2.5).
function UITheme.textStroke(textSize: number): number
	return math.max(UITheme.TextStroke, math.floor(textSize * UITheme.TextStrokeRatio + 0.5))
end

return UITheme
