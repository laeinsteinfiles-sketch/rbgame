--!strict
-- Explorer: StarterGui/DigUI/Components/Label (ModuleScript)
-- Fredoka One for body text, Luckiest Guy for titles and numbers. Light text
-- gets the ink outline automatically so it reads over any background.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Config.UITheme)
local Base = require(script.Parent.Base)

local Label = {}

export type Props = {
	parent: Instance,
	text: string,
	name: string?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?,
	color: Color3?,
	display: boolean?, -- heavier use: titles and numbers (same family, set in caps by callers)
	banner: boolean?, -- Luckiest Guy, for big moments only
	align: Enum.TextXAlignment?,
	valign: Enum.TextYAlignment?,
	wrap: boolean?,
	autoHeight: boolean?,
	layoutOrder: number?,
	truncate: boolean?,
	stroke: number?, -- outline px; default: on for light text, off for dark text
	scaled: boolean?, -- TextScaled, capped at textSize
	rich: boolean?,
	zIndex: number?,
}

local function isLight(color: Color3): boolean
	return 0.299 * color.R + 0.587 * color.G + 0.114 * color.B > 0.55
end

function Label.new(props: Props): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = props.name or "Label"
	label.Text = props.text
	label.Size = props.size or UDim2.fromScale(1, 0)
	label.Position = props.position or UDim2.new()
	label.AnchorPoint = props.anchor or Vector2.zero
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = if props.banner then UITheme.Font.Banner elseif props.display then UITheme.Font.Display else UITheme.Font.Body
	local size = props.textSize or UITheme.TextSize.Body
	label.TextSize = size
	local color = props.color or UITheme.Colors.Text
	label.TextColor3 = color
	label.TextXAlignment = props.align or Enum.TextXAlignment.Left
	label.TextYAlignment = props.valign or Enum.TextYAlignment.Center
	label.TextWrapped = props.wrap == true
	label.RichText = props.rich == true
	label.LayoutOrder = props.layoutOrder or 0
	label.ZIndex = props.zIndex or 1
	if props.truncate then
		label.TextTruncate = Enum.TextTruncate.AtEnd
	end
	if props.autoHeight then
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.TextWrapped = true
	end
	if props.scaled then
		label.TextScaled = true
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = size
		constraint.MinTextSize = math.min(size, 9)
		constraint.Parent = label
	end
	local strokePx = props.stroke
	if strokePx == nil then
		strokePx = if isLight(color) then UITheme.textStroke(size) else 0
	end
	if strokePx > 0 then
		Base.textStroke(label, strokePx)
	end
	label.Parent = props.parent
	return label
end

--- Re-colours a label and keeps the automatic outline rule consistent.
function Label.setColor(label: TextLabel, color: Color3)
	label.TextColor3 = color
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Enabled = isLight(color)
	end
end

return Label
