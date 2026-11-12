--!strict
-- Explorer: StarterGui/DigUI/Components/Button (ModuleScript)
-- Chunky button, 48px minimum tap target, one radius, tap punch + sound.
-- Kinds: primary (teal), amber (reward), secondary (inset), ghost (outline).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Base = require(script.Parent.Base)
local Icon = require(script.Parent.Icon)

local Button = {}

export type Kind = "primary" | "amber" | "secondary" | "ghost"

export type Props = {
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	kind: Kind?,
	icon: number?,
	textSize: number?,
	layoutOrder: number?,
	name: string?,
	onClick: (() -> ())?,
	sfx: ((name: string) -> ())?,
	minSize: Vector2?,
}

export type Handle = {
	instance: TextButton,
	setEnabled: (enabled: boolean) -> (),
	setText: (text: string) -> (),
	setKind: (kind: Kind) -> (),
	setOnClick: (fn: () -> ()) -> (),
}

local function colorsFor(kind: Kind): (Color3, Color3, Color3)
	if kind == "primary" then
		return UITheme.Colors.Teal, UITheme.Colors.TextOnAccent, UITheme.Colors.Teal
	elseif kind == "amber" then
		return UITheme.Colors.Amber, UITheme.Colors.TextOnAccent, UITheme.Colors.Amber
	elseif kind == "ghost" then
		return UITheme.Colors.Panel, UITheme.Colors.Text, UITheme.Colors.PanelOutline
	end
	return UITheme.Colors.PanelInset, UITheme.Colors.Text, UITheme.Colors.PanelOutline
end

function Button.new(props: Props): Handle
	local kind: Kind = props.kind or "secondary"
	local enabled = true
	local onClick = props.onClick

	local button = Instance.new("TextButton")
	button.Name = props.name or "Button"
	button.Size = props.size
	button.Position = props.position or UDim2.new()
	button.AnchorPoint = props.anchor or Vector2.zero
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = ""
	button.LayoutOrder = props.layoutOrder or 0
	Base.corner(button)
	local stroke = Base.stroke(button)
	Base.sizeConstraint(button, props.minSize or Vector2.new(UITheme.TapMin, UITheme.TapMin))

	local hasIcon = props.icon ~= nil and AssetIds.isSet(props.icon :: number)
	if hasIcon then
		Icon.new({
			parent = button,
			id = props.icon :: number,
			size = UDim2.new(0, 24, 0, 24),
			position = UDim2.new(0, 12, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
		})
	end

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = if hasIcon then UDim2.new(1, -44, 1, 0) else UDim2.fromScale(1, 1)
	label.Position = if hasIcon then UDim2.fromOffset(40, 0) else UDim2.new()
	label.FontFace = UITheme.Font.Display
	label.TextSize = props.textSize or UITheme.TextSize.Body
	label.Text = props.text
	label.TextXAlignment = if hasIcon then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = button

	local scale = Instance.new("UIScale")
	scale.Parent = button

	local function paint()
		local bg, fg, outline = colorsFor(kind)
		if not enabled then
			bg, fg, outline = UITheme.Colors.Muted, UITheme.Colors.TextDim, UITheme.Colors.Muted
		end
		button.BackgroundColor3 = bg
		label.TextColor3 = fg
		stroke.Color = outline
		local icon = button:FindFirstChild("Icon")
		if icon and icon:IsA("ImageLabel") then
			icon.ImageColor3 = fg
		end
	end
	paint()

	button.Activated:Connect(function()
		if not enabled then
			if props.sfx then
				props.sfx("ButtonDenied")
			end
			return
		end
		scale.Scale = 0.94
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
			TweenService:Create(scale, UITheme.Easing.Settle, { Scale = 1.03 }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, UITheme.Easing.Settle, { Scale = 1 }):Play()
	end)

	button.Parent = props.parent

	return {
		instance = button,
		setEnabled = function(value: boolean)
			if enabled == value then
				return
			end
			enabled = value
			paint()
		end,
		setText = function(text: string)
			label.Text = text
		end,
		setKind = function(newKind: Kind)
			kind = newKind
			paint()
		end,
		setOnClick = function(fn: () -> ())
			onClick = fn
		end,
	}
end

return Button
