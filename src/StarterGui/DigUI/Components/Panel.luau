--!strict
-- Explorer: StarterGui/DigUI/Components/Panel (ModuleScript)
-- Panel styles: "window" (charcoal with a thick ink border, menus and
-- sheets), "card" (lighter charcoal plate inside a window, or a saturated
-- rarity plate when tinted), "dark" (translucent HUD pill over the world).
-- Uses the 9-slice sprite if AssetIds.UI.PanelSlice is ever sourced.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Base = require(script.Parent.Base)

local Panel = {}

export type Style = "window" | "light" | "card" | "dark"

export type Props = {
	parent: Instance,
	name: string?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	padding: number?,
	inset: boolean?, -- legacy alias for style = "card"
	style: Style?,
	tint: Color3?, -- card only: a saturated plate in this colour
	layoutOrder: number?,
	zIndex: number?,
}

function Panel.new(props: Props): Frame
	local style: Style = props.style or (if props.inset then "card" else "window")
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.Name = props.name or "Panel"
	frame.Size = props.size
	frame.Position = props.position or UDim2.new()
	frame.AnchorPoint = props.anchor or Vector2.zero
	frame.LayoutOrder = props.layoutOrder or 0
	frame.ZIndex = props.zIndex or 1
	frame.BackgroundColor3 = Color3.new(1, 1, 1)

	if style == "window" or style == "light" then
		Base.gradient(frame, UITheme.Colors.PanelTop, UITheme.Colors.PanelBottom)
		Base.corner(frame, 18)
		Base.stroke(frame, UITheme.Colors.Ink, UITheme.Stroke)
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
		if tint then
			local h, s, v = tint:ToHSV()
			Base.gradient(frame, Color3.fromHSV(h, s * 0.75, math.min(1, v + 0.18)), Color3.fromHSV(h, math.min(1, s * 1.05), v * 0.82))
		else
			Base.gradient(frame, UITheme.Colors.Card, UITheme.Colors.CardBottom)
		end
		Base.corner(frame, 12)
		Base.stroke(frame, UITheme.Colors.Ink, 3)
	else
		frame.BackgroundColor3 = UITheme.Colors.Shade
		frame.BackgroundTransparency = 0.2
		Base.corner(frame)
		Base.stroke(frame, UITheme.Colors.Ink, 3)
	end

	if props.padding ~= 0 then
		Base.padding(frame, props.padding)
	end
	frame.Parent = props.parent
	return frame
end

return Panel
