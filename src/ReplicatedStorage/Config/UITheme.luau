--!strict
-- Explorer: ReplicatedStorage/Config/UITheme (ModuleScript)
-- The one palette, the one font family (two weights), the one radius.
-- Anything visual that is not in here is a bug.

local UITheme = {}

UITheme.Colors = {
	Panel = Color3.fromHex("23272E"),
	PanelOutline = Color3.fromHex("3B424D"), -- 2px lighter outline on every panel
	PanelInset = Color3.fromHex("1B1E24"), -- bars and wells inside panels
	Amber = Color3.fromHex("F2B33D"), -- rewards, cash, winners
	Teal = Color3.fromHex("3FB6A8"), -- positive actions, progress, confirm
	Text = Color3.fromHex("F1EFE8"),
	TextDim = Color3.fromHex("A3A7AE"),
	TextOnAccent = Color3.fromHex("1B1E24"),
	Muted = Color3.fromHex("5A616C"), -- disabled buttons
	Warn = Color3.fromHex("C9655C"), -- "can't afford", lost ore; used sparingly
}

UITheme.Font = {
	Body = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
	Display = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal),
}

UITheme.Radius = 10 -- px, everywhere
UITheme.Stroke = 2 -- px, everywhere
UITheme.Padding = 10 -- px, inside panels
UITheme.Gap = 8 -- px, between siblings
UITheme.TapMin = 48 -- px, minimum tap target on touch

-- Text sizes are px at 1x; the UIScale component multiplies for phones.
UITheme.TextSize = {
	Small = 14,
	Body = 18,
	Title = 24,
	Display = 40,
	Hero = 64,
}

UITheme.Easing = {
	-- Pops and rewards overshoot; everything else settles with Quad/Sine.
	Pop = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Settle = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Slide = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	SlideOut = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Count = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Bar = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
	Flash = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
}

return UITheme
