--!strict
-- Explorer: StarterGui/DigUI/Components/Base (ModuleScript)
-- The few primitives every component shares. One radius, one stroke, one
-- padding; nobody sets these numbers anywhere else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local UITheme = require(ReplicatedStorage.Config.UITheme)

local Base = {}

-- Type-only references: the UI receives the live controller instances from
-- PlayerScripts at runtime (see App), never requires these copies.
export type ClientState = typeof(require(StarterPlayer.StarterPlayerScripts.Controllers.ClientState))
export type DigController = typeof(require(StarterPlayer.StarterPlayerScripts.Controllers.DigController))
export type Juice = typeof(require(StarterPlayer.StarterPlayerScripts.Controllers.Juice))
export type LayerFX = typeof(require(StarterPlayer.StarterPlayerScripts.Controllers.LayerFX))
export type SFX = typeof(require(StarterPlayer.StarterPlayerScripts.Controllers.SFX))

export type Context = {
	gui: ScreenGui,
	hud: Frame,
	modals: Frame,
	overlay: Frame,
	state: ClientState,
	dig: DigController,
	juice: Juice,
	fx: LayerFX,
	sfx: SFX,
	isTouch: boolean,
}

function Base.corner(instance: GuiObject): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UITheme.Radius)
	corner.Parent = instance
	return corner
end

function Base.stroke(instance: GuiObject, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = UITheme.Stroke
	stroke.Color = color or UITheme.Colors.PanelOutline
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

function Base.padding(instance: GuiObject, px: number?): UIPadding
	local p = px or UITheme.Padding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, p)
	padding.PaddingBottom = UDim.new(0, p)
	padding.PaddingLeft = UDim.new(0, p)
	padding.PaddingRight = UDim.new(0, p)
	padding.Parent = instance
	return padding
end

function Base.sizeConstraint(instance: GuiObject, min: Vector2?, max: Vector2?): UISizeConstraint
	local constraint = Instance.new("UISizeConstraint")
	if min then
		constraint.MinSize = min
	end
	if max then
		constraint.MaxSize = max
	end
	constraint.Parent = instance
	return constraint
end

function Base.aspect(instance: GuiObject, ratio: number): UIAspectRatioConstraint
	local constraint = Instance.new("UIAspectRatioConstraint")
	constraint.AspectRatio = ratio
	constraint.AspectType = Enum.AspectType.ScaleWithParentSize
	constraint.DominantAxis = Enum.DominantAxis.Width
	constraint.Parent = instance
	return constraint
end

function Base.list(parent: GuiObject, direction: Enum.FillDirection, gap: number?, align: Enum.HorizontalAlignment?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, gap or UITheme.Gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = align or Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = parent
	return layout
end

function Base.grid(parent: GuiObject, cell: UDim2, gap: number?): UIGridLayout
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = cell
	layout.CellPadding = UDim2.fromOffset(gap or UITheme.Gap, gap or UITheme.Gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

function Base.frame(parent: Instance, name: string, size: UDim2, position: UDim2?, anchor: Vector2?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position or UDim2.new()
	frame.AnchorPoint = anchor or Vector2.zero
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

return Base
