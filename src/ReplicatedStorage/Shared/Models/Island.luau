--!strict
-- Explorer: ReplicatedStorage/Shared/Models/Island (ModuleScript)
-- One player's floating island: layered cliff with hanging rock spikes, the
-- shaft collar and mine headframe, trading post (sell), workshop (upgrades),
-- name board and a little set dressing. Built at the origin facing -Z (the
-- hub), then pivoted onto the ring by the server.

local GameConfig = require(script.Parent.Parent.Parent.Config.GameConfig)
local Palette = require(script.Parent.Parent.Parent.Config.Palette)
local DrillModels = require(script.Parent.DrillModels)
local Kit = require(script.Parent.ModelKit)
local Props = require(script.Parent.Props)

local Island = {}

export type Built = {
	model: Model,
	sellPad: BasePart,
	workshopPad: BasePart,
	cap: Model,
	nameLabel: TextLabel,
	depthLabel: TextLabel,
	wheel: BasePart,
}

local W = GameConfig.World
local HOLE = GameConfig.Geometry.BlockSize / 2 + 0.5 -- hidden behind the owner's 2-stud shaft walls

local function cliff(m: Model)
	Props.slab(m, W.IslandHalf, 7, HOLE, -1.2, 0, Palette.grass, { material = Enum.Material.Grass, collide = true })
	Props.slab(m, W.IslandHalf - 0.6, 7, HOLE, -4.5, -1.2, Palette.dirt, { material = Enum.Material.Ground, collide = true })
	Props.slab(m, W.IslandHalf - 3.5, 6.5, HOLE, -9, -4.5, Palette.rock, { material = Enum.Material.Rock })
	Props.slab(m, W.IslandHalf - 8, 5.5, HOLE, -14, -9, Palette.rockDark, { material = Enum.Material.Slate })
	Props.slab(m, W.IslandHalf - 13, 3.5, HOLE, -19, -14, Kit.shade(Palette.rockDark, -0.15), { material = Enum.Material.Basalt })
	-- Hanging spikes around the core pillar give the island its silhouette.
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2 + 0.4
		local radius = 9 + Kit.jitter(i, 1) * 4
		local top = Vector3.new(math.cos(a) * radius, -12 - Kit.jitter(i, 2) * 3, math.sin(a) * radius)
		Props.spike(m, top, 3 + Kit.jitter(i, 3) * 1.5, 7 + Kit.jitter(i, 4) * 7, if i % 2 == 0 then Palette.rockDark else Palette.rock, Enum.Material.Slate)
	end
	-- The core pillar others see under every island: the shaft as rock.
	local depth, top = 70, -19
	for _, s in { -1, 1 } do
		Kit.block(m, Vector3.new(15.5, depth, 1.5), CFrame.new(0, top - depth / 2, s * 7.25), Palette.rockDark, { material = Enum.Material.Slate })
		Kit.block(m, Vector3.new(1.5, depth, 13), CFrame.new(s * 7.25, top - depth / 2, 0), Palette.rockDark, { material = Enum.Material.Slate })
	end
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		Props.spike(m, Vector3.new(math.cos(a) * 8.5, top - 18 - i * 9, math.sin(a) * 8.5), 2.4, 9, Palette.rock, Enum.Material.Rock)
	end
end

local function collar(m: Model): Model
	local stone: Kit.Opts = { material = Enum.Material.Cobblestone, collide = true }
	local outer, h = HOLE + 2, 0.5
	Kit.block(m, Vector3.new(outer * 2, h, 2), CFrame.new(0, h / 2, -(HOLE + 1)), Palette.stone, stone)
	Kit.block(m, Vector3.new(outer * 2, h, 2), CFrame.new(0, h / 2, HOLE + 1), Palette.stone, stone)
	Kit.block(m, Vector3.new(2, h, HOLE * 2), CFrame.new(-(HOLE + 1), h / 2, 0), Palette.stone, stone)
	Kit.block(m, Vector3.new(2, h, HOLE * 2), CFrame.new(HOLE + 1, h / 2, 0), Palette.stone, stone)

	-- Closed hatch strangers see; the owner's client hides it locally.
	local cap = Kit.model("ShaftCap", m)
	Kit.block(cap, Vector3.new(HOLE * 2, 1, HOLE * 2), CFrame.new(0, -0.5, 0), Palette.plank, {
		material = Enum.Material.WoodPlanks,
		collide = true,
		name = "Collider",
	})
	for i = -1, 1 do
		Kit.block(cap, Vector3.new(HOLE * 2, 0.12, 0.5), CFrame.new(0, 0.04, i * 2.6), Palette.metalDark, { material = Enum.Material.Metal })
	end
	return cap
end

local function headframe(m: Model): BasePart
	local wood: Kit.Opts = { material = Enum.Material.Wood }
	local base, top, height = 5.6, 1.9, 15
	local legs = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local a = Vector3.new(sx * base, 0.5, sz * base)
			local b = Vector3.new(sx * top, height, sz * top)
			Kit.beam(m, a, b, 0.8, Palette.woodDark, wood)
			table.insert(legs, { a = a, b = b })
		end
	end
	local function legAt(i: number, t: number): Vector3
		return legs[i].a:Lerp(legs[i].b, t)
	end
	-- Ring braces at two heights plus one X-brace on the hub-facing side.
	local order = { 1, 2, 4, 3 }
	for _, t in { 0.38, 0.72 } do
		for k = 1, 4 do
			local i, j = order[k], order[k % 4 + 1]
			Kit.beam(m, legAt(i, t), legAt(j, t), 0.5, Palette.wood, wood)
		end
	end
	Kit.beam(m, legAt(1, 0.05), legAt(3, 0.38), 0.4, Palette.wood, wood)
	Kit.beam(m, legAt(3, 0.05), legAt(1, 0.38), 0.4, Palette.wood, wood)
	Kit.block(m, Vector3.new(5.2, 0.5, 5.2), CFrame.new(0, height + 0.2, 0), Palette.plank, { material = Enum.Material.WoodPlanks })
	for _, x in { -0.75, 0.75 } do
		Kit.block(m, Vector3.new(0.4, 2.1, 0.4), CFrame.new(x, height + 1.45, 0), Palette.metalDark, { material = Enum.Material.Metal })
	end
	-- Pulley wheel; its parts carry "Wheel" so the client can spin it during rides.
	local wheelCf = CFrame.new(0, height + 2.6, 0)
	local hub = Kit.cylX(m, 1.3, 0.7, wheelCf, Palette.metalDark, { material = Enum.Material.Metal, name = "WheelHub" })
	hub:SetAttribute("Wheel", true)
	local rim = Kit.ring(m, 1.75, 14, 0.35, 0.3, wheelCf * CFrame.Angles(0, 0, math.pi / 2), Palette.metal, { material = Enum.Material.Metal })
	for _, p in rim do
		p:SetAttribute("Wheel", true)
	end
	for k = 0, 3 do
		local spoke = Kit.block(m, Vector3.new(0.18, 3.4, 0.18), wheelCf * CFrame.Angles(k * math.pi / 4, 0, 0), Palette.metal, { material = Enum.Material.Metal })
		spoke:SetAttribute("Wheel", true)
	end
	Kit.cylY(m, height + 2.6 - 6.5, 0.12, CFrame.new(0, (height + 2.6 + 6.5) / 2 - 0.9, -1.75), Palette.rope, { material = Enum.Material.Fabric })
	Kit.cylY(m, 0.9, 1.1, CFrame.new(0, 5.6, -1.75), Palette.metalDark, { material = Enum.Material.Metal })
	Kit.cylY(m, 0.12, 1.16, CFrame.new(0, 6.02, -1.75), Palette.metal, { material = Enum.Material.Metal })
	Props.lantern(m, CFrame.new(legAt(2, 0.6) + Vector3.new(-0.7, -0.9, 0)))
	return hub
end

local function padAt(m: Model, at: CFrame, c: string, name: string): BasePart
	local pad = Kit.cylY(m, 0.3, 6.4, at * CFrame.new(0, 0.15, 0), c, { name = name, collide = true })
	Kit.cylY(m, 0.32, 4.6, at * CFrame.new(0, 0.16, 0), Kit.shade(c, -0.18), { shadow = false })
	Kit.cylY(m, 0.34, 1.4, at * CFrame.new(0, 0.17, 0), Kit.shade(c, 0.3), { material = Enum.Material.Neon, shadow = false })
	-- Chevrons pointing at the counter; the client scrolls their glow.
	for k = 0, 2 do
		local chevron = Kit.ridge(m, 0.5, 0.06, 0.9, at * CFrame.new(0, 0.32, -1.6 + k * 1.1) * CFrame.Angles(math.pi / 2, 0, 0), Kit.shade(c, 0.45), {
			material = Enum.Material.Neon,
			shadow = false,
		})
		for _, p in chevron do
			p:SetAttribute("Chevron", k)
		end
	end
	return pad
end

local function tradingPost(m: Model, at: CFrame): BasePart
	Props.stall(m, at, Palette.canvas, Palette.canvasStripe)
	Kit.block(m, Vector3.new(7, 2.3, 1.3), at * CFrame.new(0, 1.55, -1.9), Palette.wood, { material = Enum.Material.WoodPlanks, collide = true })
	Kit.block(m, Vector3.new(7.4, 0.3, 1.7), at * CFrame.new(0, 2.85, -1.9), Palette.woodDark, { material = Enum.Material.Wood, collide = true })
	-- Scale and a coin pile on the counter: the only saturated thing here is money.
	Kit.block(m, Vector3.new(0.8, 0.15, 0.5), at * CFrame.new(2.3, 3.08, -1.9), Palette.metalDark)
	Kit.block(m, Vector3.new(0.12, 1, 0.12), at * CFrame.new(2.3, 3.6, -1.9), Palette.metalDark)
	Kit.cylX(m, 1.5, 0.1, at * CFrame.new(2.3, 4.1, -1.9), Palette.metal)
	for _, x in { 1.6, 3.0 } do
		Kit.cylY(m, 0.06, 0.62, at * CFrame.new(x, 3.6, -1.9), Palette.gold, { material = Enum.Material.Metal })
		Kit.beam(m, (at * CFrame.new(x, 4.1, -1.9)).Position, (at * CFrame.new(x, 3.63, -1.9)).Position, 0.04, Palette.metalDark)
	end
	for i = 0, 4 do
		Kit.cylY(m, 0.1, 0.5, at * CFrame.new(-2 + (i % 2) * 0.12, 3.05 + i * 0.1, -1.95), Palette.gold, { material = Enum.Material.Metal })
	end
	Kit.cylY(m, 0.1, 0.5, at * CFrame.new(-1.4, 3.05, -1.6), Palette.gold, { material = Enum.Material.Metal })
	-- Shelf of sorted ore crates on the back wall.
	Kit.block(m, Vector3.new(7.6, 0.2, 0.9), at * CFrame.new(0, 4.3, 2.4), Palette.woodDark)
	for i, oreColor in { "E07A3F", "A9ACB6", "FFC53D" } do
		local x = -2.6 + (i - 1) * 2.6
		Props.crate(m, at * CFrame.new(x, 4.4, 2.35), 1.1)
		for k = 0, 2 do
			Kit.ball(m, 0.42, at * CFrame.new(x - 0.25 + k * 0.25, 5.55 + (k % 2) * 0.12, 2.3), oreColor, { material = Enum.Material.Metal, shadow = false })
		end
	end
	local board = Kit.block(m, Vector3.new(6.2, 1.5, 0.3), at * CFrame.new(0, 8.4, -3.3), Palette.woodDark, { material = Enum.Material.Wood })
	Props.signText(board, { { text = "TRADING POST", color = Palette.amber, weight = 1 } })
	for _, x in { -2.2, 2.2 } do
		Kit.block(m, Vector3.new(0.18, 1.2, 0.18), at * CFrame.new(x, 7.6, -3.3), Palette.metalDark)
	end
	Props.barrel(m, at * CFrame.new(5.3, 0, -1.5))
	Props.barrel(m, at * CFrame.new(5.5, 0, 0.6))
	return padAt(m, at * CFrame.new(0, 0, -6), Palette.amber, "SellPad")
end

local function workshop(m: Model, at: CFrame): BasePart
	Props.stall(m, at, Palette.woodDark, Palette.wood)
	-- Teal trim along the awning edge: upgrades are the teal action.
	Kit.block(m, Vector3.new(9, 0.3, 0.3), at * CFrame.new(0, 6.45, -3.75), Palette.teal, { shadow = false })
	-- Anvil
	local anvil = at * CFrame.new(-1.8, 0.4, -1.2)
	Kit.block(m, Vector3.new(1.3, 0.8, 1), anvil * CFrame.new(0, 0.4, 0), Palette.rockDark, { material = Enum.Material.Slate, collide = true })
	Kit.block(m, Vector3.new(0.7, 0.6, 0.6), anvil * CFrame.new(0, 1.1, 0), Palette.metalDark, { material = Enum.Material.Metal })
	Kit.block(m, Vector3.new(2, 0.55, 0.85), anvil * CFrame.new(0.1, 1.65, 0), Palette.metalDark, { material = Enum.Material.Metal })
	Kit.wedge(m, Vector3.new(0.85, 0.55, 0.9), anvil * CFrame.new(-1.33, 1.65, 0) * CFrame.Angles(0, -math.pi / 2, 0), Palette.metalDark, {
		material = Enum.Material.Metal,
	})
	Kit.block(m, Vector3.new(0.9, 0.12, 0.2), anvil * CFrame.new(0.3, 2.0, 0.1) * CFrame.Angles(0, 0.4, 0), Palette.metal)
	-- Workbench with a grinding wheel.
	Kit.block(m, Vector3.new(4.2, 0.35, 1.5), at * CFrame.new(2, 2.4, 1.9), Palette.woodDark, { material = Enum.Material.Wood, collide = true })
	for _, x in { 0.2, 3.8 } do
		Kit.block(m, Vector3.new(0.3, 2.2, 1.3), at * CFrame.new(x, 1.3, 1.9), Palette.wood, { material = Enum.Material.Wood })
	end
	Kit.cylX(m, 0.3, 1.3, at * CFrame.new(3, 3.3, 1.9), Palette.stone, { material = Enum.Material.Slate })
	Kit.block(m, Vector3.new(0.5, 0.6, 0.4), at * CFrame.new(3, 2.85, 1.9), Palette.metalDark)
	-- Drill rack: real models of the next tiers, a teaser of what cash buys.
	Kit.block(m, Vector3.new(7, 0.25, 0.3), at * CFrame.new(0, 6.05, 2.55), Palette.metalDark, { material = Enum.Material.Metal })
	for i, tier in { 3, 4, 5 } do
		local drill = DrillModels.build(tier)
		drill:PivotTo(at * CFrame.new(-2.4 + (i - 1) * 2.4, 5.7, 2.35))
		drill.Parent = m
	end
	local board = Kit.block(m, Vector3.new(5.4, 1.5, 0.3), at * CFrame.new(0, 8.4, -3.3), Palette.woodDark, { material = Enum.Material.Wood })
	Props.signText(board, { { text = "UPGRADES", color = Palette.teal, weight = 1 } })
	for _, x in { -2, 2 } do
		Kit.block(m, Vector3.new(0.18, 1.2, 0.18), at * CFrame.new(x, 7.6, -3.3), Palette.metalDark)
	end
	Props.crate(m, at * CFrame.new(-5.4, 0, -0.8), 1.6)
	Props.crate(m, at * CFrame.new(-5.3, 1.6, -0.7), 1.1)
	return padAt(m, at * CFrame.new(0, 0, -6), Palette.teal, "WorkshopPad")
end

local function nameBoard(m: Model): (TextLabel, TextLabel)
	local at = CFrame.new(0, 0, W.IslandHalf - 5) * CFrame.Angles(0, 0, 0)
	for _, x in { -5.2, 5.2 } do
		Kit.block(m, Vector3.new(0.6, 5.6, 0.6), at * CFrame.new(x, 2.8, 0.2), Palette.woodDark, { material = Enum.Material.Wood, collide = true })
	end
	local board = Kit.block(m, Vector3.new(11.4, 3.2, 0.4), at * CFrame.new(0, 4.2, 0), Palette.woodDark, { material = Enum.Material.Wood })
	Kit.block(m, Vector3.new(11.8, 0.3, 0.6), at * CFrame.new(0, 5.9, 0), Palette.wood, { material = Enum.Material.Wood })
	local labels = Props.signText(board, {
		{ text = "", color = Palette.cream, weight = 0.6 },
		{ text = "", color = Palette.amber, weight = 0.4 },
	})
	return labels[1], labels[2]
end

local function dressing(m: Model)
	local half = W.IslandHalf
	Props.pine(m, CFrame.new(-half + 6, 0, half - 9), 1.15)
	Props.roundTree(m, CFrame.new(half - 6, 0, half - 8), 1)
	Props.pine(m, CFrame.new(-half + 4.5, 0, -2), 0.8)
	Props.rocks(m, CFrame.new(half - 4, 0, 4), 1.2, 3)
	Props.rocks(m, CFrame.new(-half + 5, 0, -half + 9), 1, 7)
	Props.rocks(m, CFrame.new(7, 0, half - 4), 0.8, 11)
	Props.lanternPost(m, CFrame.new(-7, 0, 9) * CFrame.Angles(0, math.pi * 0.75, 0))
	Props.lanternPost(m, CFrame.new(8, 0, 9) * CFrame.Angles(0, math.pi * 1.25, 0))
	-- Grass tufts break up the flat top.
	for i = 0, 9 do
		local a = Kit.jitter(i, 21) * math.pi * 2
		local radius = 9 + Kit.jitter(i, 22) * 11
		local p = Vector3.new(math.cos(a) * radius, 0.25, math.sin(a) * radius)
		if math.abs(p.Z) < 18 and math.abs(p.X) < 18 then
			Kit.ridge(m, 0.6, 0.6, 0.8, CFrame.new(p) * CFrame.Angles(0, a, 0), Palette.grassLight, { material = Enum.Material.Grass, shadow = false })
		end
	end
	-- Invisible rails stop players walking off the edge.
	for _, def in {
		{ Vector3.new(half * 2, 10, 1), Vector3.new(0, 5, -half) },
		{ Vector3.new(half * 2, 10, 1), Vector3.new(0, 5, half) },
		{ Vector3.new(1, 10, half * 2), Vector3.new(-half, 5, 0) },
		{ Vector3.new(1, 10, half * 2), Vector3.new(half, 5, 0) },
	} do
		Kit.block(m, def[1], CFrame.new(def[2]), Palette.ink, { transparency = 1, collide = true, shadow = false, name = "Rail" })
	end
end

--- Builds island `index` at the origin; the caller pivots it into place.
function Island.build(index: number): Built
	local m = Kit.model(`Plot{index}`)
	cliff(m)
	local cap = collar(m)
	local wheel = headframe(m)
	local function stallFrame(x: number, z: number): CFrame
		local pos = Vector3.new(x, 0, z)
		return CFrame.lookAt(pos, Vector3.new(0, 0, 0))
	end
	local sellPad = tradingPost(m, stallFrame(W.TradingPost.x, W.TradingPost.z))
	local workshopPad = workshop(m, stallFrame(W.Workshop.x, W.Workshop.z))
	local nameLabel, depthLabel = nameBoard(m)
	dressing(m)
	m.WorldPivot = CFrame.new()
	return {
		model = m,
		sellPad = sellPad,
		workshopPad = workshopPad,
		cap = cap,
		nameLabel = nameLabel,
		depthLabel = depthLabel,
		wheel = wheel,
	}
end

return Island
