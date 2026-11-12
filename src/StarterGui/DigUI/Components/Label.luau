--!strict
-- Explorer: StarterGui/DigUI/Components/Label (ModuleScript)
-- Nunito only: SemiBold for body, ExtraBold for numbers and titles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Config.UITheme)

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
	display: boolean?, -- ExtraBold
	align: Enum.TextXAlignment?,
	valign: Enum.TextYAlignment?,
	wrap: boolean?,
	autoHeight: boolean?,
	layoutOrder: number?,
	truncate: boolean?,
}

function Label.new(props: Props): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = props.name or "Label"
	label.Text = props.text
	label.Size = props.size or UDim2.fromScale(1, 0)
	label.Position = props.position or UDim2.new()
	label.AnchorPoint = props.anchor or Vector2.zero
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = if props.display then UITheme.Font.Display else UITheme.Font.Body
	label.TextSize = props.textSize or UITheme.TextSize.Body
	label.TextColor3 = props.color or UITheme.Colors.Text
	label.TextXAlignment = props.align or Enum.TextXAlignment.Left
	label.TextYAlignment = props.valign or Enum.TextYAlignment.Center
	label.TextWrapped = props.wrap == true
	label.LayoutOrder = props.layoutOrder or 0
	if props.truncate then
		label.TextTruncate = Enum.TextTruncate.AtEnd
	end
	if props.autoHeight then
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.TextWrapped = true
	end
	label.Parent = props.parent
	return label
end

return Label
