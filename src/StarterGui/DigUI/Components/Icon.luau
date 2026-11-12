--!strict
-- Explorer: StarterGui/DigUI/Components/Icon (ModuleScript)
-- Icons by name. An uploaded image in AssetIds.Icons wins; otherwise coins,
-- gems and ores are drawn from frames (crisp at any size) and everything
-- else uses a colour emoji glyph, so no icon is ever an empty box.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Base = require(script.Parent.Base)

local Icon = {}

local GLYPHS: { [string]: string } = {
	Depth = "⛏️",
	Drill = "⛏️",
	Backpack = "🎒",
	Shop = "🛒",
	Book = "📖",
	Quest = "📜",
	Trophy = "🏆",
	Settings = "⚙️",
	Close = "✖️",
	Sell = "💰",
	Up = "⬆️",
	Down = "⬇️",
	Mega = "⚡",
	Egg = "🥚",
	Relic = "🏺",
	Timer = "⏱️",
	Pet = "🐾",
	Skin = "🎨",
	Crown = "👑",
	Star = "⭐",
	Fire = "🔥",
	Lock = "🔒",
	Check = "✅",
	Gift = "🎁",
	Sparkles = "✨",
	Rocket = "🚀",
	Elevator = "🛗",
	Sound = "🔊",
	Music = "🎵",
	Shake = "📳",
	Robot = "🤖",
	Flag = "🏁",
	Medal1 = "🥇",
	Medal2 = "🥈",
	Medal3 = "🥉",
	Info = "💡",
	Warning = "⚠️",
	Core = "🌋",
	Pickaxe = "⛏️",
	Muscle = "💪",
}

-- Pets have no matching asset; the closest emoji stands in on cards.
local PET_GLYPHS: { [string]: string } = {
	mole = "🐹",
	beetle = "🐞",
	gecko = "🦎",
	bat = "🦇",
	crab = "🦀",
	owl = "🦉",
	salamander = "🐲",
}

export type Props = {
	parent: Instance,
	name: string, -- icon name ("Cash", "Gem", "Ore:ruby", "Pet:owl", any GLYPHS key)
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
}

local oreColor: { [string]: Color3 } = {}
for _, ore in GameConfig.Ores do
	oreColor[ore.id] = Color3.fromHex(ore.color)
end

local function container(props: Props): Frame
	local frame = Base.frame(props.parent, "Icon", props.size or UDim2.fromOffset(28, 28), props.position, props.anchor)
	frame.LayoutOrder = props.layoutOrder or 0
	frame.ZIndex = props.zIndex or 1
	Base.aspect(frame, 1)
	return frame
end

local function shine(parent: GuiObject, zIndex: number)
	local spot = Base.fill(parent, "Shine", Color3.new(1, 1, 1), UDim2.fromScale(0.28, 0.28), UDim2.fromScale(0.28, 0.22))
	spot.BackgroundTransparency = 0.25
	spot.ZIndex = zIndex + 1
	Base.round(spot)
end

--- Gold coin with an embossed "$".
local function drawCoin(frame: Frame)
	local z = frame.ZIndex
	local coin = Base.fill(frame, "Coin", Color3.new(1, 1, 1), UDim2.fromScale(0.9, 0.9), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	coin.ZIndex = z
	Base.round(coin)
	Base.gradient(coin, Color3.fromHex("FFE97A"), Color3.fromHex("F5A515"))
	Base.stroke(coin, UITheme.Colors.Ink, 2)
	local inner = Base.frame(coin, "Rim", UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	inner.ZIndex = z + 1
	Base.round(inner)
	Base.stroke(inner, Color3.fromHex("D88A0B"), 1.5)
	local mark = Instance.new("TextLabel")
	mark.Name = "Mark"
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromScale(1, 1)
	mark.FontFace = UITheme.Font.Display
	mark.Text = "$"
	mark.TextScaled = true
	mark.TextColor3 = Color3.fromHex("C97A06")
	mark.ZIndex = z + 2
	mark.Parent = inner
end

--- Faceted gem: a rotated square with a two-tone gradient and a highlight.
local function drawGem(frame: Frame, top: Color3, bottom: Color3)
	local z = frame.ZIndex
	local gem = Base.fill(frame, "Gem", Color3.new(1, 1, 1), UDim2.fromScale(0.66, 0.66), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	gem.Rotation = 45
	gem.ZIndex = z
	Base.corner(gem, 4)
	Base.gradient(gem, top, bottom, 45)
	Base.stroke(gem, UITheme.Colors.Ink, 2)
	shine(gem, z)
end

local function glyph(frame: Frame, text: string)
	local label = Instance.new("TextLabel")
	label.Name = "Glyph"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = UITheme.Font.Body
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.ZIndex = frame.ZIndex
	label.Parent = frame
end

local function imageId(name: string): number
	local icons = AssetIds.Icons :: { [string]: any }
	local oreId = string.match(name, "^Ore:(.+)$")
	if oreId then
		local id = (icons.Ore :: { [string]: number })[oreId]
		return if typeof(id) == "number" then id else 0
	end
	local id = icons[name]
	return if typeof(id) == "number" then id else 0
end

function Icon.new(props: Props): Frame
	local frame = container(props)
	Icon.set(frame, props.name)
	return frame
end

--- Redraws an icon container in place (used when a card changes its icon).
function Icon.set(frame: Frame, name: string)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local id = imageId(name)
	if AssetIds.isSet(id) then
		local image = Instance.new("ImageLabel")
		image.Name = "Image"
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = AssetIds.image(id)
		image.ZIndex = frame.ZIndex
		image.Parent = frame
		return
	end
	if name == "Cash" or name == "Coin" then
		drawCoin(frame)
		return
	end
	if name == "Gem" then
		drawGem(frame, Color3.fromHex("8FF3FF"), Color3.fromHex("8A4DFF"))
		return
	end
	local oreId = string.match(name, "^Ore:(.+)$")
	if oreId then
		local color = oreColor[oreId] or Color3.new(1, 1, 1)
		local h, s, v = color:ToHSV()
		drawGem(frame, Color3.fromHSV(h, s * 0.7, math.min(1, v + 0.35)), color)
		return
	end
	local petId = string.match(name, "^Pet:(.+)$")
	if petId then
		glyph(frame, PET_GLYPHS[petId] or GLYPHS.Pet)
		return
	end
	glyph(frame, GLYPHS[name] or GLYPHS.Star)
end

function Icon.glyph(name: string): string
	return GLYPHS[name] or ""
end

return Icon
