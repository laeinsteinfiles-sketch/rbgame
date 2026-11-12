--!strict
-- Explorer: ReplicatedStorage/Shared/Models/PetModels (ModuleScript)
-- Seven pets built from rounded primitives with big readable eyes. Each pet
-- returns animation groups (wings, tails, claws, legs) with a pivot so the
-- client can flap and wag them cheaply. Local frame: faces -Z, walkers stand
-- on y = 0, flyers are centred on y = 0.

local GameConfig = require(script.Parent.Parent.Parent.Config.GameConfig)
local Kit = require(script.Parent.ModelKit)

local PetModels = {}

export type Group = { name: string, pivot: CFrame, parts: { BasePart }, offsets: { CFrame } }
export type Rig = {
	model: Model,
	root: BasePart,
	groups: { [string]: Group },
	flyer: boolean,
	height: number,
}

local INK = "1D1F24"

type Builder = {
	m: Model,
	groups: { [string]: Group },
}

local function group(b: Builder, name: string, pivot: CFrame): Group
	local g: Group = { name = name, pivot = pivot, parts = {}, offsets = {} }
	b.groups[name] = g
	return g
end

local function add(g: Group, parts: BasePart | { BasePart })
	if typeof(parts) == "table" then
		for _, p in parts do
			table.insert(g.parts, p)
		end
	else
		table.insert(g.parts, parts)
	end
end

-- Glossy eye: dark ball plus a neon catch-light toward the viewer.
local function eye(m: Model, pos: Vector3, d: number, iris: string?)
	if iris then
		Kit.ball(m, d * 1.45, CFrame.new(pos + Vector3.new(0, 0, 0.02)), "F4EFE4", { shadow = false })
		Kit.ball(m, d * 1.05, CFrame.new(pos + Vector3.new(0, 0, -d * 0.18)), iris, { shadow = false })
	end
	Kit.ball(m, d, CFrame.new(pos + Vector3.new(0, 0, if iris then -d * 0.32 else 0)), INK, { shadow = false })
	Kit.ball(m, d * 0.36, CFrame.new(pos + Vector3.new(d * 0.16, d * 0.2, -d * (if iris then 0.68 else 0.4))), "FFFFFF", {
		material = Enum.Material.Neon,
		shadow = false,
	})
end

local BUILDS: { [string]: (b: Builder, def: typeof(GameConfig.Pets[1])) -> () } = {
	mole = function(b, def)
		local m, fur, belly, pink, claw = b.m, def.color, "A68E74", "E89AA6", "EFE3CC"
		Kit.ball(m, 1.7, CFrame.new(0, 0.85, 0.2), fur)
		Kit.ball(m, 1.45, CFrame.new(0, 0.8, 0.68), fur)
		Kit.ball(m, 1.2, CFrame.new(0, 0.66, -0.22), belly)
		Kit.ball(m, 1.15, CFrame.new(0, 1.02, -0.52), fur)
		Kit.ball(m, 0.66, CFrame.new(0, 0.88, -1.06), belly)
		Kit.ball(m, 0.36, CFrame.new(0, 0.92, -1.38), pink)
		eye(m, Vector3.new(-0.27, 1.2, -0.98), 0.17)
		eye(m, Vector3.new(0.27, 1.2, -0.98), 0.17)
		for _, side in { -1, 1 } do
			local g = group(b, if side < 0 then "clawL" else "clawR", CFrame.new(side * 0.6, 0.45, -0.5))
			add(g, Kit.block(m, Vector3.new(0.6, 0.16, 0.55), CFrame.new(side * 0.72, 0.3, -0.78) * CFrame.Angles(0, side * 0.35, side * 0.3), claw))
			for k = -1, 1 do
				add(g, Kit.ball(m, 0.16, CFrame.new(side * 0.74 + k * 0.17, 0.28, -1.07), "FFF8EC"))
			end
			Kit.ball(m, 0.42, CFrame.new(side * 0.5, 0.2, 0.9), claw)
		end
		local tail = group(b, "tail", CFrame.new(0, 0.95, 1.35))
		add(tail, Kit.cylZ(m, 0.45, 0.16, CFrame.new(0, 1.05, 1.5) * CFrame.Angles(0.6, 0, 0), pink))
	end,

	beetle = function(b, def)
		local m, shell, under, leg = b.m, def.color, "3E463F", "2C302C"
		Kit.ball(m, 1.65, CFrame.new(0, 0.62, 0.15), shell)
		Kit.cylY(m, 0.22, 1.55, CFrame.new(0, 0.32, 0.15), under)
		Kit.block(m, Vector3.new(0.07, 0.6, 1.5), CFrame.new(0, 1.2, 0.2), Kit.shade(shell, -0.45))
		Kit.ball(m, 0.42, CFrame.new(-0.32, 1.22, -0.05), Kit.shade(shell, 0.35), { shadow = false })
		Kit.ball(m, 0.82, CFrame.new(0, 0.55, -0.72), under)
		Kit.cylZ(m, 0.55, 0.16, CFrame.new(0, 0.86, -1.05) * CFrame.Angles(-0.7, 0, 0), "C9B98F")
		eye(m, Vector3.new(-0.22, 0.7, -1.06), 0.18)
		eye(m, Vector3.new(0.22, 0.7, -1.06), 0.18)
		for _, side in { -1, 1 } do
			local antenna = Kit.cylZ(m, 0.6, 0.06, CFrame.new(side * 0.2, 0.95, -0.95) * CFrame.Angles(-0.9, side * 0.4, 0), leg)
			Kit.ball(m, 0.14, CFrame.new(antenna.Position + (antenna.CFrame.RightVector * 0.3)), leg)
			local g = group(b, if side < 0 then "legsL" else "legsR", CFrame.new(side * 0.7, 0.35, 0))
			for _, z in { -0.4, 0.1, 0.55 } do
				add(g, Kit.block(m, Vector3.new(0.5, 0.12, 0.12), CFrame.new(side * 0.85, 0.22, z) * CFrame.Angles(0, 0, side * -0.5), leg))
			end
		end
	end,

	gecko = function(b, def)
		local m, skin, belly, spot = b.m, def.color, "B4BEC5", "5F6C78"
		Kit.ball(m, 0.95, CFrame.new(0, 0.55, 0), skin)
		Kit.ball(m, 0.85, CFrame.new(0, 0.52, 0.48), skin)
		Kit.ball(m, 0.7, CFrame.new(0, 0.42, -0.05), belly)
		Kit.ball(m, 0.9, CFrame.new(0, 0.66, -0.62), skin)
		Kit.ball(m, 0.6, CFrame.new(0, 0.58, -0.98), skin)
		for i, p in { Vector3.new(-0.2, 0.98, 0.05), Vector3.new(0.18, 0.95, 0.4), Vector3.new(0.05, 0.98, -0.25) } do
			Kit.ball(m, 0.18 + i * 0.02, CFrame.new(p), spot)
		end
		eye(m, Vector3.new(-0.3, 0.92, -0.72), 0.2, "E9D27A")
		eye(m, Vector3.new(0.3, 0.92, -0.72), 0.2, "E9D27A")
		for _, side in { -1, 1 } do
			for _, z in { -0.35, 0.55 } do
				Kit.block(m, Vector3.new(0.4, 0.14, 0.16), CFrame.new(side * 0.5, 0.25, z) * CFrame.Angles(0, 0, side * -0.4), skin)
				Kit.ball(m, 0.24, CFrame.new(side * 0.7, 0.12, z - 0.05), belly)
			end
		end
		local tail = group(b, "tail", CFrame.new(0, 0.5, 0.85))
		local prev = Vector3.new(0, 0.5, 0.85)
		for i = 1, 4 do
			local nextPoint = Vector3.new(math.sin(i * 0.5) * 0.25, 0.48 - i * 0.05, 0.85 + i * 0.32)
			add(tail, Kit.beam(m, prev, nextPoint, 0.42 - i * 0.07, skin))
			prev = nextPoint
		end
	end,

	bat = function(b, def)
		local m, fur, wing, inner = b.m, def.color, "45404F", "C9A0A8"
		Kit.ball(m, 1.15, CFrame.new(0, 0, 0.05), fur)
		Kit.ball(m, 0.95, CFrame.new(0, 0.42, -0.32), fur)
		for _, side in { -1, 1 } do
			Kit.wedge(m, Vector3.new(0.14, 0.62, 0.38), CFrame.new(side * 0.28, 0.95, -0.3) * CFrame.Angles(0, 0, side * -0.25), fur)
			Kit.wedge(m, Vector3.new(0.06, 0.4, 0.22), CFrame.new(side * 0.28, 0.9, -0.38) * CFrame.Angles(0, 0, side * -0.25), inner)
			local g = group(b, if side < 0 then "wingL" else "wingR", CFrame.new(side * 0.45, 0.12, 0))
			-- Two fanned wedges per wing: membrane with a scalloped trailing edge.
			add(g, Kit.wedge(m, Vector3.new(0.06, 0.9, 1.25), CFrame.new(side * 0.98, 0.18, 0.02) * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.Angles(0, 0, 0), wing))
			add(g, Kit.wedge(m, Vector3.new(0.06, 0.6, 0.8), CFrame.new(side * 1.5, 0.06, 0.18) * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.Angles(0.35, 0, 0), wing))
			add(g, Kit.cylX(m, 1.3, 0.1, CFrame.new(side * 1.05, 0.62, 0), Kit.shade(wing, -0.3)))
		end
		eye(m, Vector3.new(-0.2, 0.52, -0.74), 0.17)
		eye(m, Vector3.new(0.2, 0.52, -0.74), 0.17)
		for _, side in { -1, 1 } do
			Kit.wedge(m, Vector3.new(0.06, 0.16, 0.06), CFrame.new(side * 0.1, 0.18, -0.76) * CFrame.Angles(math.pi, 0, 0), "FFFFFF")
			Kit.ball(m, 0.2, CFrame.new(side * 0.2, -0.55, 0.1), INK)
		end
	end,

	crab = function(b, def)
		local m, shell, under, claw = b.m, def.color, "E8B07E", "D8823F"
		Kit.cylY(m, 0.5, 1.7, CFrame.new(0, 0.5, 0), under)
		Kit.ball(m, 1.5, CFrame.new(0, 0.62, 0.05), shell)
		Kit.ball(m, 0.36, CFrame.new(-0.3, 1.18, -0.05), Kit.shade(shell, 0.35), { shadow = false })
		for _, side in { -1, 1 } do
			Kit.cylY(m, 0.5, 0.1, CFrame.new(side * 0.28, 1.25, -0.5), shell)
			eye(m, Vector3.new(side * 0.28, 1.55, -0.5), 0.22, "F4EFE4")
			local g = group(b, if side < 0 then "clawL" else "clawR", CFrame.new(side * 0.75, 0.6, -0.45))
			add(g, Kit.beam(m, Vector3.new(side * 0.75, 0.6, -0.45), Vector3.new(side * 1.05, 0.75, -0.95), 0.24, claw))
			add(g, Kit.ball(m, 0.62, CFrame.new(side * 1.08, 0.8, -1.12), claw))
			add(g, Kit.wedge(m, Vector3.new(0.3, 0.28, 0.5), CFrame.new(side * 1.12, 0.98, -1.42) * CFrame.Angles(math.pi, 0, 0), Kit.shade(claw, 0.15)))
			add(g, Kit.wedge(m, Vector3.new(0.3, 0.22, 0.46), CFrame.new(side * 1.12, 0.68, -1.4), Kit.shade(claw, 0.15)))
			local legs = group(b, if side < 0 then "legsL" else "legsR", CFrame.new(side * 0.7, 0.45, 0.2))
			for _, z in { -0.05, 0.3, 0.62 } do
				add(legs, Kit.beam(m, Vector3.new(side * 0.7, 0.5, z), Vector3.new(side * 1.25, 0.05, z + 0.1), 0.13, shell))
			end
		end
	end,

	owl = function(b, def)
		local m, feather, belly, amber = b.m, def.color, "A9A4C0", "F2B33D"
		Kit.ball(m, 1.55, CFrame.new(0, -0.05, 0), feather)
		Kit.ball(m, 1.1, CFrame.new(0, -0.2, -0.32), belly)
		Kit.ball(m, 1.3, CFrame.new(0, 0.68, -0.04), feather)
		for _, side in { -1, 1 } do
			Kit.cylZ(m, 0.12, 0.78, CFrame.new(side * 0.26, 0.72, -0.6), Kit.shade(belly, 0.25), { shadow = false })
			eye(m, Vector3.new(side * 0.26, 0.74, -0.62), 0.2, amber)
			Kit.wedge(m, Vector3.new(0.16, 0.5, 0.36), CFrame.new(side * 0.42, 1.36, -0.05) * CFrame.Angles(0, 0, side * -0.3), Kit.shade(feather, -0.25))
			local g = group(b, if side < 0 then "wingL" else "wingR", CFrame.new(side * 0.62, 0.15, 0.05))
			add(g, Kit.ball(m, 0.85, CFrame.new(side * 0.78, -0.05, 0.1), Kit.shade(feather, -0.12)))
			add(g, Kit.ball(m, 0.6, CFrame.new(side * 0.9, -0.42, 0.2), Kit.shade(feather, -0.2)))
			Kit.ball(m, 0.24, CFrame.new(side * 0.25, -0.8, -0.2), amber)
		end
		Kit.wedge(m, Vector3.new(0.18, 0.26, 0.2), CFrame.new(0, 0.5, -0.7) * CFrame.Angles(math.pi, 0, 0), amber)
	end,

	salamander = function(b, def)
		local m, skin, belly, glow = b.m, def.color, "F2C46B", "FF6A2A"
		Kit.ball(m, 1.0, CFrame.new(0, 0.52, -0.1), skin)
		Kit.ball(m, 0.92, CFrame.new(0, 0.5, 0.45), skin)
		Kit.ball(m, 0.72, CFrame.new(0, 0.4, 0.1), belly)
		Kit.ball(m, 0.92, CFrame.new(0, 0.62, -0.72), skin)
		Kit.ball(m, 0.62, CFrame.new(0, 0.55, -1.1), skin)
		eye(m, Vector3.new(-0.3, 0.86, -0.85), 0.19, "FFE2A8")
		eye(m, Vector3.new(0.3, 0.86, -0.85), 0.19, "FFE2A8")
		for i, z in { -0.55, -0.15, 0.25, 0.6 } do
			Kit.wedge(m, Vector3.new(0.08, 0.32 - i * 0.03, 0.32), CFrame.new(0, 1.0 - i * 0.03, z), belly)
			Kit.ball(m, 0.2, CFrame.new((i % 2 - 0.5) * 0.5, 0.92, z + 0.05), glow, { material = Enum.Material.Neon, shadow = false })
		end
		for _, side in { -1, 1 } do
			for _, z in { -0.45, 0.55 } do
				Kit.block(m, Vector3.new(0.42, 0.16, 0.18), CFrame.new(side * 0.52, 0.24, z) * CFrame.Angles(0, 0, side * -0.4), skin)
				Kit.ball(m, 0.26, CFrame.new(side * 0.74, 0.12, z - 0.06), belly)
			end
		end
		local tail = group(b, "tail", CFrame.new(0, 0.5, 0.85))
		local prev = Vector3.new(0, 0.5, 0.85)
		for i = 1, 4 do
			local nextPoint = Vector3.new(math.sin(i * 0.6) * 0.3, 0.5 - i * 0.04, 0.85 + i * 0.34)
			add(tail, Kit.beam(m, prev, nextPoint, 0.44 - i * 0.07, skin))
			prev = nextPoint
		end
		local flame = Kit.ball(m, 0.3, CFrame.new(prev), glow, { material = Enum.Material.Neon, shadow = false })
		add(tail, flame)
		Kit.light(flame, glow, 1.2, 7)
	end,
}

local petById: { [string]: typeof(GameConfig.Pets[1]) } = {}
for _, pet in GameConfig.Pets do
	petById[pet.id] = pet
end

local function scaleBuild(m: Model, s: number)
	if s == 1 then
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size *= s
			d.CFrame = CFrame.new(d.Position * s) * d.CFrame.Rotation
		elseif d:IsA("PointLight") then
			d.Range *= s
		end
	end
end

--- Builds a pet at `scale` (1 = Normal size) around the origin.
function PetModels.build(petId: string, scale: number?): Rig
	local def = petById[petId] or GameConfig.Pets[1]
	local s = scale or 1
	local m = Kit.model(def.name)
	local root = Kit.block(m, Vector3.new(0.2, 0.2, 0.2), CFrame.new(), INK, { name = "Root", transparency = 1, shadow = false })
	local b: Builder = { m = m, groups = {} }
	BUILDS[def.id](b, def)
	scaleBuild(m, s)
	for _, g in b.groups do
		g.pivot = CFrame.new(g.pivot.Position * s) * g.pivot.Rotation
		for i, part in g.parts do
			g.offsets[i] = g.pivot:Inverse() * part.CFrame
		end
	end
	m.PrimaryPart = root
	return {
		model = m,
		root = root,
		groups = b.groups,
		flyer = def.flyer,
		height = (if def.flyer then 1.6 else 1.4) * s,
	}
end

return PetModels
