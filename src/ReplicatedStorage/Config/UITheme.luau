--!strict
-- Explorer: ReplicatedStorage/Config/UITheme (ModuleScript)
-- The UI's single source of style: chunky toy-like panels with thick ink
-- outlines, glossy 3D buttons with a lip, one font family (Nunito) in two
-- weights, one corner radius. Anything visual not defined here is a bug.

local UITheme = {}

local hex = Color3.fromHex

UITheme.Colors = {
	Ink = hex("15171C"), -- every outline and text stroke
	Panel = hex("2A2F38"),
	PanelTop = hex("343B47"),
	PanelBottom = hex("22262D"),
	PanelInset = hex("181B21"),
	Rim = hex("FFFFFF"), -- inner highlight line, used at high transparency
	Text = hex("FFF7E8"),
	TextDim = hex("B9B2A4"),
	Amber = hex("F2B33D"), -- rewards, cash, winners
	Teal = hex("3FB6A8"), -- positive actions, progress, gems
	Coral = hex("E8644E"), -- close, can't afford, pack full
	Muted = hex("5A616C"),
	Track = hex("101216"),
}

export type ButtonStyle = { top: Color3, bottom: Color3, lip: Color3, text: Color3 }

-- Glossy faces: light top, deep bottom, darker lip underneath for depth.
UITheme.Buttons = {
	amber = { top = hex("FFD873"), bottom = hex("EE9E22"), lip = hex("A2620E"), text = hex("FFF7E8") },
	teal = { top = hex("6FE0CF"), bottom = hex("2FA294"), lip = hex("1C665D"), text = hex("FFF7E8") },
	coral = { top = hex("FF937A"), bottom = hex("DB4D39"), lip = hex("8C2A1D"), text = hex("FFF7E8") },
	slate = { top = hex("5E6878"), bottom = hex("3D4451"), lip = hex("222730"), text = hex("FFF7E8") },
	disabled = { top = hex("5B5F66"), bottom = hex("474A50"), lip = hex("2A2C30"), text = hex("A7A39A") },
} :: { [string]: ButtonStyle }

UITheme.Font = {
	Body = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal),
	Display = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Heavy, Enum.FontStyle.Normal),
}

UITheme.Radius = 12 -- px, everywhere
UITheme.Stroke = 3 -- px ink outline on panels and buttons
UITheme.TextStroke = 2.5 -- px ink outline on text
UITheme.Lip = 5 -- px depth of a button's 3D lip
UITheme.Padding = 12
UITheme.Gap = 8
UITheme.TapMin = 48 -- px, minimum tap target on touch

-- Reference layout is a landscape phone; App scales it for bigger screens.
UITheme.Reference = Vector2.new(844, 390)

UITheme.TextSize = {
	Small = 14,
	Body = 17,
	Button = 19,
	Title = 26,
	Number = 30,
	Display = 40,
	Hero = 72,
}

UITheme.Easing = {
	-- Pops and rewards overshoot; everything else settles with Quad/Sine.
	Pop = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	BigPop = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0),
	Settle = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Press = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Slide = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	SlideOut = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Count = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Bar = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
	Flash = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
	Shine = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
	Stripes = TweenInfo.new(1.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
}

return UITheme
