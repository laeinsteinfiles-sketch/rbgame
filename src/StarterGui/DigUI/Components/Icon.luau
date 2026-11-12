--!strict
-- Explorer: StarterGui/DigUI/Components/Icon (ModuleScript)
-- Icon slot from the one icon set. Unset ids render as an invisible square
-- so layouts never shift when icons arrive.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local UITheme = require(ReplicatedStorage.Config.UITheme)

local Icon = {}

export type Props = {
	parent: Instance,
	id: number,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	layoutOrder: number?,
	name: string?,
}

function Icon.new(props: Props): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = props.name or "Icon"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Size = props.size or UDim2.fromOffset(24, 24)
	image.Position = props.position or UDim2.new()
	image.AnchorPoint = props.anchor or Vector2.zero
	image.ScaleType = Enum.ScaleType.Fit
	image.ImageColor3 = props.color or UITheme.Colors.Text
	image.LayoutOrder = props.layoutOrder or 0
	Icon.set(image, props.id)
	image.Parent = props.parent
	return image
end

function Icon.set(image: ImageLabel, id: number)
	local set = AssetIds.isSet(id)
	image.Image = AssetIds.image(id)
	image.ImageTransparency = if set then 0 else 1
end

return Icon
