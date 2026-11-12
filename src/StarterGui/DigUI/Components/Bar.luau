--!strict
-- Explorer: StarterGui/DigUI/Components/Bar (ModuleScript)
-- Chunky progress bar: dark rounded track with an ink outline, glossy
-- gradient fill, centred outlined label.

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
	color: Color3?, -- legacy single colour
	swatch: string?, -- UITheme swatch name (preferred)
	name: string?,
	label: boolean?,
	layoutOrder: number?,
	textSize: number?,
	zIndex: number?,
}

export type Handle = {
	instance: Frame,
	fill: Frame,
	setFraction: (fraction: number, animate: boolean?) -> (),
	setLabel: (text: string) -> (),
	setColor: (color: Color3) -> (),
	setSwatch: (name: string) -> (),
}

function Bar.new(props: Props): Handle
	local z = props.zIndex or 1
	local track = Instance.new("Frame")
	track.Name = props.name or "Bar"
	track.Size = props.size
	track.Position = props.position or UDim2.new()
	track.AnchorPoint = props.anchor or Vector2.zero
	track.BackgroundColor3 = Color3.fromHex("2B3352")
	track.BorderSizePixel = 0
	track.LayoutOrder = props.layoutOrder or 0
	track.ZIndex = z
	Base.round(track)
	Base.stroke(track, UITheme.Colors.Ink, 2.5)

	local fill = Base.fill(track, "Fill", Color3.new(1, 1, 1), UDim2.fromScale(0, 1))
	fill.ZIndex = z + 1
	Base.round(fill)
	local gradient = Base.gradient(fill, Color3.new(1, 1, 1), Color3.new(1, 1, 1))
	local shine = Base.fill(fill, "Shine", Color3.new(1, 1, 1), UDim2.new(1, -6, 0.38, 0), UDim2.new(0, 3, 0, 2))
	shine.BackgroundTransparency = 0.6
	shine.ZIndex = z + 1
	Base.round(shine)

	local label: TextLabel? = nil
	if props.label then
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.FontFace = UITheme.Font.Display
		text.TextSize = props.textSize or UITheme.TextSize.Small
		text.TextColor3 = UITheme.Colors.White
		text.ZIndex = z + 2
		text.Text = ""
		Base.textStroke(text)
		text.Parent = track
		label = text
	end

	local function setSwatch(name: string)
		local swatch = UITheme.swatch(name)
		gradient.Color = ColorSequence.new(swatch.top, swatch.bottom)
	end
	local function setColor(color: Color3)
		local h, s, v = color:ToHSV()
		gradient.Color = ColorSequence.new(Color3.fromHSV(h, s * 0.75, math.min(1, v + 0.2)), color)
	end
	if props.swatch then
		setSwatch(props.swatch)
	else
		setColor(props.color or UITheme.Colors.Green)
	end

	track.Parent = props.parent

	return {
		instance = track,
		fill = fill,
		setFraction = function(fraction: number, animate: boolean?)
			local f = math.clamp(fraction, 0, 1)
			local target = UDim2.fromScale(f, 1)
			fill.Visible = f > 0.001
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
		setColor = setColor,
		setSwatch = setSwatch,
	}
end

return Bar
