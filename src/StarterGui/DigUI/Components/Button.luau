--!strict
-- Explorer: StarterGui/DigUI/Components/Button (ModuleScript)
-- Chunky simulator button: gradient face with a shine strip and ink outline
-- sitting on a darker 3D lip. Presses sink the face into the lip, hovers grow,
-- clicks pop. 48 px minimum tap target.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Config.UITheme)
local Base = require(script.Parent.Base)
local Icon = require(script.Parent.Icon)

local Button = {}

export type Kind = string -- a UITheme swatch name, or legacy "primary" | "amber" | "secondary" | "ghost"

export type Props = {
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	kind: Kind?,
	icon: string?, -- Icon name
	iconSize: number?,
	stack: boolean?, -- icon above the text (menu tiles)
	textSize: number?,
	body: boolean?, -- Fredoka instead of Luckiest Guy
	layoutOrder: number?,
	name: string?,
	onClick: (() -> ())?,
	sfx: ((name: string) -> ())?,
	minSize: Vector2?,
	zIndex: number?,
}

export type Handle = {
	instance: TextButton,
	face: Frame,
	label: TextLabel,
	setEnabled: (enabled: boolean) -> (),
	setText: (text: string) -> (),
	setKind: (kind: Kind) -> (),
	setOnClick: (fn: () -> ()) -> (),
	setBadge: (text: string?) -> (),
	setIcon: (name: string) -> (),
	isEnabled: () -> boolean,
}

local LEGACY: { [string]: string } = {
	primary = "green",
	amber = "gold",
	secondary = "grey",
	ghost = "grey",
}

local PRESS = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function swatchFor(kind: Kind): UITheme.Swatch
	return UITheme.swatch(LEGACY[kind] or kind)
end

function Button.new(props: Props): Handle
	local kind: Kind = props.kind or "blue"
	local enabled = true
	local onClick = props.onClick
	local lipPx = UITheme.Lip
	local z = props.zIndex or 1

	local button = Instance.new("TextButton")
	button.Name = props.name or "Button"
	button.Size = props.size
	button.Position = props.position or UDim2.new()
	button.AnchorPoint = props.anchor or Vector2.zero
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.LayoutOrder = props.layoutOrder or 0
	button.ZIndex = z
	Base.sizeConstraint(button, props.minSize or Vector2.new(UITheme.TapMin, UITheme.TapMin))

	local lip = Base.fill(button, "Lip", Color3.new(1, 1, 1), UDim2.fromScale(1, 1))
	lip.ZIndex = z
	Base.corner(lip)
	local lipStroke = Base.stroke(lip)

	local face = Base.fill(button, "Face", Color3.new(1, 1, 1), UDim2.new(1, 0, 1, -lipPx))
	face.ZIndex = z + 1
	Base.corner(face)
	Base.stroke(face)
	local gradient = Base.gradient(face, Color3.new(1, 1, 1), Color3.new(1, 1, 1))

	local shine = Base.fill(face, "Shine", Color3.new(1, 1, 1), UDim2.new(1, -10, 0.4, 0), UDim2.fromOffset(5, 3))
	shine.BackgroundTransparency = 0.7
	shine.ZIndex = z + 1
	Base.corner(shine, UITheme.Radius - 5)

	local textSize = props.textSize or UITheme.TextSize.Body
	local content = Base.frame(face, "Content", UDim2.fromScale(1, 1))
	content.ZIndex = z + 2
	local layout = Base.list(
		content,
		if props.stack then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
		if props.stack then 0 else 6,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	layout.Parent = content

	local iconFrame: Frame? = nil
	if props.icon then
		local px = props.iconSize or math.floor(textSize * 1.45)
		iconFrame = Icon.new({ parent = content, name = props.icon, size = UDim2.fromOffset(px, px), layoutOrder = 1, zIndex = z + 2 })
	end

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.FontFace = if props.body then UITheme.Font.Body else UITheme.Font.Display
	label.TextSize = textSize
	label.Text = props.text
	label.TextColor3 = UITheme.Colors.White
	label.LayoutOrder = 2
	label.ZIndex = z + 2
	label.Visible = props.text ~= ""
	if props.stack then
		label.Size = UDim2.new(1, -4, 0, textSize + 2)
		label.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = textSize
		limit.Parent = label
	else
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.new(0, 0, 1, 0)
	end
	Base.textStroke(label)
	label.Parent = content

	local badge = Base.fill(button, "Badge", UITheme.Colors.Red, UDim2.fromOffset(24, 24), UDim2.new(1, 4, 0, -6), Vector2.new(1, 0))
	badge.ZIndex = z + 4
	badge.Visible = false
	Base.round(badge)
	Base.stroke(badge, UITheme.Colors.Ink, 2)
	local badgeText = Instance.new("TextLabel")
	badgeText.BackgroundTransparency = 1
	badgeText.Size = UDim2.fromScale(1, 1)
	badgeText.FontFace = UITheme.Font.Display
	badgeText.TextSize = 15
	badgeText.TextColor3 = UITheme.Colors.White
	badgeText.ZIndex = z + 5
	badgeText.Parent = badge

	local scale = Instance.new("UIScale")
	scale.Parent = button

	local function paint()
		local swatch = if enabled then swatchFor(kind) else UITheme.swatch("grey")
		gradient.Color = ColorSequence.new(swatch.top, swatch.bottom)
		lip.BackgroundColor3 = swatch.edge
		lipStroke.Color = UITheme.Colors.Ink
		label.TextColor3 = if enabled then UITheme.Colors.White else Color3.fromHex("F4F6FA")
		shine.BackgroundTransparency = if enabled then 0.7 else 0.85
	end
	paint()

	local up = UDim2.new(0, 0, 0, 0)
	local down = UDim2.new(0, 0, 0, math.floor(lipPx * 0.7))
	local function press(isDown: boolean)
		TweenService:Create(face, PRESS, { Position = if isDown and enabled then down else up }):Play()
	end

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			press(true)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			press(false)
		end
	end)
	button.Activated:Connect(function()
		if not enabled then
			if props.sfx then
				props.sfx("ButtonDenied")
			end
			scale.Scale = 0.97
			TweenService:Create(scale, UITheme.Easing.Settle, { Scale = 1 }):Play()
			return
		end
		scale.Scale = 0.9
		TweenService:Create(scale, UITheme.Easing.Pop, { Scale = 1 }):Play()
		if props.sfx then
			props.sfx("ButtonTap")
		end
		if onClick then
			onClick()
		end
	end)
	button.MouseEnter:Connect(function()
		if enabled then
			TweenService:Create(scale, UITheme.Easing.Settle, { Scale = 1.05 }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		press(false)
		TweenService:Create(scale, UITheme.Easing.Settle, { Scale = 1 }):Play()
	end)

	button.Parent = props.parent

	return {
		instance = button,
		face = face,
		label = label,
		setEnabled = function(value: boolean)
			if enabled == value then
				return
			end
			enabled = value
			paint()
		end,
		setText = function(text: string)
			label.Text = text
			label.Visible = text ~= ""
		end,
		setKind = function(newKind: Kind)
			if kind == newKind then
				return
			end
			kind = newKind
			paint()
		end,
		setOnClick = function(fn: () -> ())
			onClick = fn
		end,
		setBadge = function(text: string?)
			badge.Visible = text ~= nil and text ~= ""
			badgeText.Text = text or ""
		end,
		setIcon = function(name: string)
			local frame = iconFrame
			if frame then
				Icon.set(frame, name)
			end
		end,
		isEnabled = function()
			return enabled
		end,
	}
end

return Button
