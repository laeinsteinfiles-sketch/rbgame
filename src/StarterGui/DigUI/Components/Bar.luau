--!strict
-- Explorer: StarterGui/DigUI/Components/Bar (ModuleScript)
-- Progress bar: inset track, accent fill, optional centred label.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Config.UITheme)
local Base = require(script.Parent.Base)

local Bar = {}

export type Props = {
	parent: Instance,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	name: string?,
	label: boolean?,
	layoutOrder: number?,
	textSize: number?,
}

export type Handle = {
	instance: Frame,
	setFraction: (fraction: number, animate: boolean?) -> (),
	setLabel: (text: string) -> (),
	setColor: (color: Color3) -> (),
}

function Bar.new(props: Props): Handle
	local track = Instance.new("Frame")
	track.Name = props.name or "Bar"
	track.Size = props.size
	track.Position = props.position or UDim2.new()
	track.AnchorPoint = props.anchor or Vector2.zero
	track.BackgroundColor3 = UITheme.Colors.PanelInset
	track.BorderSizePixel = 0
	track.LayoutOrder = props.layoutOrder or 0
	track.ClipsDescendants = true
	Base.corner(track)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = props.color or UITheme.Colors.Teal
	fill.BorderSizePixel = 0
	Base.corner(fill)
	fill.Parent = track

	local label: TextLabel? = nil
	if props.label then
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.FontFace = UITheme.Font.Display
		text.TextSize = props.textSize or UITheme.TextSize.Small
		text.TextColor3 = UITheme.Colors.Text
		text.TextStrokeTransparency = 0.7
		text.TextStrokeColor3 = UITheme.Colors.PanelInset
		text.Text = ""
		text.Parent = track
		label = text
	end

	track.Parent = props.parent

	return {
		instance = track,
		setFraction = function(fraction: number, animate: boolean?)
			local target = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			if animate == false then
				fill.Size = target
			else
				TweenService:Create(fill, UITheme.Easing.Bar, { Size = target }):Play()
			end
		end,
		setLabel = function(text: string)
			if label then
				label.Text = text
			end
		end,
		setColor = function(color: Color3)
			fill.BackgroundColor3 = color
		end,
	}
end

return Bar
