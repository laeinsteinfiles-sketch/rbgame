--!strict
-- Explorer: ReplicatedStorage/Shared/Models/DrillModels (ModuleScript)
-- One drill per tier, each with its own silhouette so players can read a
-- rival's progress from across the map. Local frame: the T-handle ("Grip",
-- PrimaryPart) sits at the origin along X, the drill hangs straight down and
-- the bit tip ends at y = -Length. Front is -Z.
--
-- Parts tagged Skin="body" take the skin colour/material, Skin="trim" the
-- skin accent; the default skin keeps each tier's own colours.

local GameConfig = require(script.Parent.Parent.Parent.Config.GameConfig)
local Kit = require(script.Parent.ModelKit)

local DrillModels = {}

DrillModels.Length = 3.3

local INK = "1D1F24"
local METAL_DARK = "43474E"
local METAL = "6C7178"
local METAL_LIGHT = "AEB4BC"

type Build = (m: Model) -> ()

local function handle(m: Model, bar: string, wrap: string): Part
	local grip = Kit.cylX(m, 2.3, 0.36, CFrame.new(), bar, { name = "Grip", material = Enum.Material.SmoothPlastic })
	for _, x in { -0.9, 0.9 } do
		Kit.cylX(m, 0.5, 0.44, CFrame.new(x, 0, 0), wrap)
	end
	for _, x in { -0.55, 0.55 } do
		Kit.block(m, Vector3.new(0.22, 0.72, 0.22), CFrame.new(x, -0.36, 0), METAL_DARK)
	end
	return grip
end

local function chuck(m: Model, y: number, d: number)
	Kit.cylY(m, 0.34, d, CFrame.new(0, y, 0), METAL_DARK, { material = Enum.Material.Metal })
	Kit.cylY(m, 0.08, d + 0.08, CFrame.new(0, y - 0.13, 0), INK)
end

-- Stepped cone: reads as a drill point from any angle at phone size.
local function cone(m: Model, top: number, length: number, d0: number, steps: number, c: string, opts: Kit.Opts?)
	local h = length / steps
	for s = 0, steps - 1 do
		local d = d0 * (1 - s / steps) + 0.05
		Kit.cylY(m, h + 0.01, d, CFrame.new(0, top - h * (s + 0.5), 0), c, opts)
	end
end

local function auger(m: Model, top: number, length: number, shaftD: number, flight: number, turns: number, c: string)
	local opts: Kit.Opts = { material = Enum.Material.Metal, tag = "trim" }
	local coneLength = 0.3
	local spiral = length - coneLength
	Kit.cylY(m, spiral, shaftD, CFrame.new(0, top - spiral / 2, 0), c, opts)
	local count = math.floor(turns * 7)
	for i = 0, count - 1 do
		local t = i / count
		local y = top - 0.08 - t * (spiral - 0.12)
		local angle = t * turns * math.pi * 2
		Kit.block(
			m,
			Vector3.new(flight, 0.07, 0.3),
			CFrame.new(0, y, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(shaftD / 2 + flight / 2 - 0.02, 0, 0) * CFrame.Angles(0.42, 0, 0),
			c,
			opts
		)
	end
	cone(m, top - spiral, coneLength, shaftD + flight * 0.9, 3, c, opts)
end

local function tip(m: Model): Attachment
	local anchor = Kit.block(m, Vector3.new(0.1, 0.1, 0.1), CFrame.new(0, -DrillModels.Length, 0), INK, { name = "Tip", transparency = 1, shadow = false })
	local attachment = Instance.new("Attachment")
	attachment.Name = "TipAttachment"
	attachment.Parent = anchor
	return attachment
end

local BUILDS: { Build } = {
	-- 1 Hand Drill: wood and rusty iron, a crank on the side.
	function(m)
		handle(m, "8A6545", "5E4330")
		local body: Kit.Opts = { tag = "body", material = Enum.Material.Metal }
		Kit.block(m, Vector3.new(1, 1.15, 0.9), CFrame.new(0, -1.25, 0), "7A7470", body)
		Kit.block(m, Vector3.new(1.06, 0.18, 0.96), CFrame.new(0, -0.98, 0), "5A4A3E", { tag = "trim" })
		Kit.cylX(m, 0.14, 0.66, CFrame.new(0.58, -1.3, 0), METAL_DARK)
		Kit.block(m, Vector3.new(0.1, 0.1, 0.5), CFrame.new(0.68, -1.3, -0.22), METAL_DARK)
		Kit.ball(m, 0.2, CFrame.new(0.7, -1.3, -0.48), "8A6545")
		chuck(m, -1.98, 0.5)
		cone(m, -2.15, 1.15, 0.32, 4, "9A9DA3", { material = Enum.Material.Metal, tag = "trim" })
	end,
	-- 2 Copper Bit: round steel housing with rivets, bright copper point.
	function(m)
		handle(m, "5E4330", "33363C")
		Kit.cylY(m, 1.25, 1.05, CFrame.new(0, -1.25, 0), "7E848C", { tag = "body", material = Enum.Material.Metal })
		Kit.cylY(m, 0.16, 1.14, CFrame.new(0, -0.66, 0), METAL_DARK)
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			for _, y in { -0.82, -1.68 } do
				Kit.ball(m, 0.13, CFrame.new(math.cos(a) * 0.52, y, math.sin(a) * 0.52), METAL_LIGHT)
			end
		end
		chuck(m, -2, 0.52)
		cone(m, -2.17, 1.13, 0.44, 5, "E07A3F", { material = Enum.Material.Metal, tag = "trim" })
	end,
	-- 3 Iron Bit: boxy motor with vents and a real auger flight.
	function(m)
		handle(m, "33363C", "1F2125")
		Kit.block(m, Vector3.new(1.15, 1.25, 1), CFrame.new(0, -1.25, 0), "5E646C", { tag = "body", material = Enum.Material.Metal })
		for k = 0, 2 do
			Kit.block(m, Vector3.new(0.72, 0.08, 0.04), CFrame.new(0, -1.02 - k * 0.2, -0.52), INK)
		end
		for _, side in { -1, 1 } do
			Kit.cylX(m, 0.26, 0.7, CFrame.new(side * 0.62, -1.3, 0.05), METAL_DARK)
		end
		chuck(m, -2.05, 0.55)
		auger(m, -2.22, 1.08, 0.16, 0.2, 2.5, "A9ACB6")
	end,
	-- 4 Steel Auger: industrial, hazard band, exhaust stack.
	function(m)
		handle(m, "1F2125", "E8B931")
		Kit.block(m, Vector3.new(1.3, 1.3, 1.1), CFrame.new(0, -1.25, 0), "4C535C", { tag = "body", material = Enum.Material.Metal })
		Kit.block(m, Vector3.new(1.34, 0.24, 1.14), CFrame.new(0, -0.78, 0), "E8B931")
		for k = -2, 2 do
			for _, z in { -0.575, 0.575 } do
				Kit.block(m, Vector3.new(0.1, 0.34, 0.02), CFrame.new(k * 0.26, -0.78, z) * CFrame.Angles(0, 0, math.rad(40)), INK)
			end
		end
		Kit.cylY(m, 0.95, 0.22, CFrame.new(0.42, -0.62, 0.62), METAL_DARK)
		Kit.cylY(m, 0.12, 0.3, CFrame.new(0.42, -0.12, 0.62), INK)
		chuck(m, -2.06, 0.64)
		auger(m, -2.24, 1.06, 0.2, 0.25, 3, "C9CED6")
	end,
	-- 5 Tungsten Auger: dark, twin pressure tanks, amber status light.
	function(m)
		handle(m, "1F2125", "3A3E45")
		Kit.block(m, Vector3.new(1.2, 1.4, 1.1), CFrame.new(0, -1.25, 0), "3A3E45", { tag = "body", material = Enum.Material.Metal })
		for _, side in { -1, 1 } do
			Kit.cylY(m, 1.1, 0.5, CFrame.new(side * 0.8, -1.25, 0.08), "2B2E33", { tag = "body", material = Enum.Material.Metal })
			Kit.cylY(m, 0.08, 0.54, CFrame.new(side * 0.8, -0.95, 0.08), METAL_LIGHT)
			Kit.cylY(m, 0.08, 0.54, CFrame.new(side * 0.8, -1.55, 0.08), METAL_LIGHT)
		end
		Kit.block(m, Vector3.new(0.22, 0.22, 0.05), CFrame.new(0.3, -0.85, -0.57), "F2B33D", { material = Enum.Material.Neon })
		Kit.block(m, Vector3.new(0.5, 0.06, 0.05), CFrame.new(-0.2, -0.85, -0.57), INK)
		chuck(m, -2.08, 0.66)
		auger(m, -2.26, 1.04, 0.2, 0.27, 3, "5B6068")
	end,
	-- 6 Diamond Core: white ceramic, teal light rings, ring of diamond teeth.
	function(m)
		handle(m, "2B2E33", "3FB6A8")
		Kit.cylY(m, 1.3, 1.25, CFrame.new(0, -1.3, 0), "D9DEE5", { tag = "body" })
		Kit.ball(m, 1.12, CFrame.new(0, -0.78, 0), "D9DEE5", { tag = "body" })
		for _, y in { -0.95, -1.7 } do
			Kit.cylY(m, 0.07, 1.29, CFrame.new(0, y, 0), "3FB6A8", { material = Enum.Material.Neon, tag = "trim" })
		end
		chuck(m, -2.08, 0.72)
		Kit.cylY(m, 0.92, 0.64, CFrame.new(0, -2.68, 0), METAL_LIGHT, { material = Enum.Material.Metal })
		Kit.cylY(m, 0.94, 0.42, CFrame.new(0, -2.69, 0), INK)
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			Kit.crystal(m, 0.13, 0.12, 0.16, CFrame.new(math.cos(a) * 0.26, -3.12, math.sin(a) * 0.26) * CFrame.Angles(math.pi, a, 0), "DDF4FF", {
				material = Enum.Material.Glass,
				transparency = 0.1,
			})
		end
	end,
	-- 7 Plasma Bore: open coil column, three prongs around a plasma lance.
	function(m)
		handle(m, "1F2125", "FF8A3D")
		Kit.cylY(m, 1.45, 0.72, CFrame.new(0, -1.3, 0), "2B2E34", { tag = "body", material = Enum.Material.Metal })
		for _, y in { -0.82, -1.27, -1.72 } do
			Kit.cylY(m, 0.14, 1.28, CFrame.new(0, y, 0), "FF8A3D", { material = Enum.Material.Neon, tag = "trim" })
		end
		for i = 0, 3 do
			local a = i / 4 * math.pi * 2 + math.pi / 4
			Kit.ball(m, 0.36, CFrame.new(math.cos(a) * 0.72, -1.05, math.sin(a) * 0.72), METAL)
			Kit.block(m, Vector3.new(0.06, 1.2, 0.34), CFrame.new(math.cos(a) * 0.5, -1.3, math.sin(a) * 0.5) * CFrame.Angles(0, -a, 0), METAL_DARK)
		end
		chuck(m, -2.12, 0.72)
		for i = 0, 2 do
			local a = i / 3 * math.pi * 2
			local top = Vector3.new(math.cos(a) * 0.3, -2.3, math.sin(a) * 0.3)
			local bottom = Vector3.new(math.cos(a) * 0.12, -3.2, math.sin(a) * 0.12)
			Kit.beam(m, top, bottom, 0.12, METAL_LIGHT, { material = Enum.Material.Metal })
		end
		Kit.cylY(m, 0.95, 0.2, CFrame.new(0, -2.75, 0), "FFB15E", { material = Enum.Material.Neon })
		local core = Kit.ball(m, 0.4, CFrame.new(0, -3.22, 0), "FFE2A8", { material = Enum.Material.Neon })
		Kit.light(core, "FF9B4A", 2, 9)
	end,
}

local skinById: { [string]: typeof(GameConfig.Skins[1]) } = {}
for _, skin in GameConfig.Skins do
	skinById[skin.id] = skin
end

function DrillModels.applySkin(model: Model, skinId: string)
	local skin = skinById[skinId]
	if not skin or skin.id == "default" then
		return
	end
	local material = (Enum.Material :: any)[skin.material] or Enum.Material.Metal
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("Skin")
			if role == "body" then
				d.Color = Color3.fromHex(skin.color)
				d.Material = material
			elseif role == "trim" and d.Material ~= Enum.Material.Neon then
				d.Color = Color3.fromHex(skin.bitColor)
			end
		end
	end
end

--- Builds tier 1..7 at the origin (anchored). Callers weld or move it.
function DrillModels.build(tier: number, skinId: string?): Model
	local index = math.clamp(tier, 1, #BUILDS)
	local m = Kit.model(`Drill{index}`)
	BUILDS[index](m)
	tip(m)
	m.PrimaryPart = m:FindFirstChild("Grip") :: BasePart
	DrillModels.applySkin(m, skinId or "default")
	return m
end

return DrillModels
