--!strict
-- Explorer: StarterGui/DigUI/Components/Panel (ModuleScript)
-- Dark slate panel with the 2px lighter outline. Uses the 9-slice sprite once
-- AssetIds.UI.PanelSlice is sourced; until then a rounded Frame with the
-- same colours, so layouts are identical either way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Base = require(script.Parent.Base)

local Panel = {}

export type Props = {
	parent: Instance,
	name: string?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	padding: number?,
	inset: boolean?, -- darker well for bars/lists inside another panel
	layoutOrder: number?,
}

function Panel.new(props: Props): GuiObject
	local color = if props.inset then UITheme.Colors.PanelInset else UITheme.Colors.Panel
	local panel: GuiObject
	if AssetIds.isSet(AssetIds.UI.PanelSlice) and not props.inset then
		local image = Instance.new("ImageLabel")
		image.Image = AssetIds.image(AssetIds.UI.PanelSlice)
		image.ScaleType = Enum.ScaleType.Slice
		image.SliceCenter = AssetIds.UI.PanelSliceCenter
		image.ImageColor3 = color
		image.BackgroundTransparency = 1
		panel = image
	else
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = color
		Base.corner(frame)
		if not props.inset then
			Base.stroke(frame)
		end
		panel = frame
	end
	panel.Name = props.name or "Panel"
	panel.Size = props.size
	panel.Position = props.position or UDim2.new()
	panel.AnchorPoint = props.anchor or Vector2.zero
	panel.BorderSizePixel = 0
	panel.LayoutOrder = props.layoutOrder or 0
	if props.padding ~= 0 then
		Base.padding(panel, props.padding)
	end
	panel.Parent = props.parent
	return panel
end

return Panel
