--!strict
-- Explorer: StarterGui/DigUI/Components/Panel (ModuleScript)
-- Panel styles: "light" (white-to-sky gradient with an ink border, modals and
-- sheets), "card" (flat light card inside panels), "dark" (translucent HUD
-- pill over the 3D world). Uses the 9-slice sprite if AssetIds.UI.PanelSlice
-- is ever sourced; layouts are identical either way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Base = require(script.Parent.Base)

local Panel = {}

export type Style = "light" | "card" | "dark"

export type Props = {
	parent: Instance,
	name: string?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	padding: number?,
	inset: boolean?, -- legacy alias for style = "card"
	style: Style?,
	tint: Color3?, -- card accent: tints the card gradient and border
	layoutOrder: number?,
	zIndex: number?,
}

function Panel.new(props: Props): Frame
	local style: Style = props.style or (if props.inset then "card" else "light")
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.Name = props.name or "Panel"
	frame.Size = props.size
	frame.Position = props.position or UDim2.new()
	frame.AnchorPoint = props.anchor or Vector2.zero
	frame.LayoutOrder = props.layoutOrder or 0
	frame.ZIndex = props.zIndex or 1

	if style == "light" then
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		Base.gradient(frame, UITheme.Colors.PanelTop, UITheme.Colors.PanelBottom)
		Base.corner(frame)
		Base.stroke(frame)
		if AssetIds.isSet(AssetIds.UI.PanelSlice) then
			local image = Instance.new("ImageLabel")
			image.Name = "Slice"
			image.Size = UDim2.fromScale(1, 1)
			image.BackgroundTransparency = 1
			image.Image = AssetIds.image(AssetIds.UI.PanelSlice)
			image.ScaleType = Enum.ScaleType.Slice
			image.SliceCenter = AssetIds.UI.PanelSliceCenter
			image.ZIndex = frame.ZIndex
			image.Parent = frame
		end
	elseif style == "card" then
		local tint = props.tint
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		if tint then
			local h, s, _ = tint:ToHSV()
			Base.gradient(frame, Color3.fromHSV(h, s * 0.12, 1), Color3.fromHSV(h, s * 0.3, 0.98))
			Base.stroke(frame, tint, 2.5)
		else
			Base.gradient(frame, Color3.new(1, 1, 1), UITheme.Colors.Card)
			Base.stroke(frame, UITheme.Colors.CardEdge, 2)
		end
		Base.corner(frame, 12)
	else
		frame.BackgroundColor3 = UITheme.Colors.Shade
		frame.BackgroundTransparency = 0.3
		Base.corner(frame)
		Base.stroke(frame, UITheme.Colors.Ink, 2.5)
	end

	if props.padding ~= 0 then
		Base.padding(frame, props.padding)
	end
	frame.Parent = props.parent
	return frame
end

return Panel
