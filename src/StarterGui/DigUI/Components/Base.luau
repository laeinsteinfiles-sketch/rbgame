--!strict
-- Explorer: StarterGui/DigUI/Components/Base (ModuleScript)
-- Shared primitives for every component: corners, ink outlines, gradients,
-- layouts and the responsive root. Nobody sets these numbers anywhere else.

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
export type Music = typeof(require(StarterPlayer.StarterPlayerScripts.Controllers.Music))

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
	music: Music,
	isTouch: boolean,
}

-- Layouts are authored for a 1280x720 screen and scaled to fit; this floor
-- keeps text readable on a 667x375 phone (the HUD fits in 889x500 units).
local DESIGN_HEIGHT = 720
local MIN_SCALE = 0.75
local MAX_SCALE = 1.35

function Base.corner(instance: GuiObject, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or UITheme.Radius)
	corner.Parent = instance
	return corner
end

function Base.round(instance: GuiObject): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = instance
	return corner
end

--- Ink outline around a frame's border.
function Base.stroke(instance: GuiObject, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or UITheme.Stroke
	stroke.Color = color or UITheme.Colors.Ink
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = instance
	return stroke
end

--- Ink outline around text glyphs (the cartoon look).
function Base.textStroke(label: TextLabel | TextButton, thickness: number?, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or UITheme.TextStroke
	stroke.Color = color or UITheme.Colors.Ink
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return stroke
end

--- Top-to-bottom gradient; the object's own colour should be white.
function Base.gradient(instance: GuiObject, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = rotation or 90
	gradient.Parent = instance
	return gradient
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

function Base.list(parent: GuiObject, direction: Enum.FillDirection, gap: number?, align: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, gap or UITheme.Gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = align or Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = valign or Enum.VerticalAlignment.Top
	layout.Parent = parent
	return layout
end

function Base.grid(parent: GuiObject, cell: UDim2, gap: number?): UIGridLayout
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = cell
	layout.CellPadding = UDim2.fromOffset(gap or UITheme.Gap, gap or UITheme.Gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
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

--- Solid rounded frame in one colour (white + gradient for two-tone fills).
function Base.fill(parent: Instance, name: string, color: Color3, size: UDim2, position: UDim2?, anchor: Vector2?): Frame
	local frame = Base.frame(parent, name, size, position, anchor)
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = color
	return frame
end

--- Full-screen layer whose children are laid out in design units. The frame
--- is sized 1/scale of the screen and scaled back up by a UIScale, so
--- offsets written for 1280x720 shrink or grow with the real viewport.
function Base.responsiveRoot(gui: ScreenGui, name: string): Frame
	local root = Base.frame(gui, name, UDim2.fromScale(1, 1))
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local function update()
		local height = gui.AbsoluteSize.Y
		if height <= 0 then
			return
		end
		local s = math.clamp(height / DESIGN_HEIGHT, MIN_SCALE, MAX_SCALE)
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
	return root
end

--- Avatar headshot content id; works without any uploaded asset.
function Base.headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

return Base
