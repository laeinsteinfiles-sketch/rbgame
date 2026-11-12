--!strict
-- Explorer: ReplicatedStorage/Shared/Models/OreModels (ModuleScript)
-- What sits on top of a block: ore clusters (chunks, nuggets or crystals),
-- mutations, relics, treasure chests and blast charges. All built around
-- the origin = a point on the block's top face; parts sink partly below
-- y = 0 so they read as embedded, not placed.

local GameConfig = require(script.Parent.Parent.Parent.Config.GameConfig)
local AssetIds = require(script.Parent.Parent.Parent.Config.AssetIds)
local Kit = require(script.Parent.ModelKit)

local OreModels = {}

local oreById: { [string]: typeof(GameConfig.Ores[1]) } = {}
for _, ore in GameConfig.Ores do
	oreById[ore.id] = ore
end
local mutationById: { [string]: typeof(GameConfig.Mutations[1]) } = {}
for _, mutation in GameConfig.Mutations do
	mutationById[mutation.id] = mutation
end

local function r(seed: number, i: number): number
	return Kit.jitter(seed % 9973, i)
end

local function sparkle(parent: BasePart, c: Color3, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = AssetIds.Particles.Sparkle
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(0.6, 1.6)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Color = ColorSequence.new(c)
	emitter.LightEmission = 1
	emitter.Parent = parent
end

local function embers(parent: BasePart)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = AssetIds.Particles.Ember
	emitter.Rate = 8
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(1.5, 3)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	emitter.Color = ColorSequence.new(Color3.fromHex("FF8A3D"), Color3.fromHex("FF3D1F"))
	emitter.LightEmission = 1
	emitter.Parent = parent
end

local SHAPES = {
	chunk = function(m: Model, c: Color3, material: Enum.Material, seed: number): BasePart
		local biggest: BasePart? = nil
		for i = 1, 4 do
			local size = 0.55 + r(seed, i) * 0.55
			local x, z = (r(seed, i + 10) - 0.5) * 1.6, (r(seed, i + 20) - 0.5) * 1.6
			local p = Kit.block(m, Vector3.new(size, size * 0.8, size * 1.1), CFrame.new(x, size * 0.12, z) * CFrame.Angles(r(seed, i + 30) * 1.2, r(seed, i + 40) * 3, r(seed, i + 50) * 0.8), Kit.shade(c, (r(seed, i + 60) - 0.5) * 0.25), {
				material = material,
			})
			biggest = biggest or p
		end
		return biggest :: BasePart
	end,
	nugget = function(m: Model, c: Color3, material: Enum.Material, seed: number): BasePart
		local biggest: BasePart? = nil
		for i = 1, 5 do
			local d = if i == 1 then 0.95 else 0.4 + r(seed, i) * 0.4
			local x, z = (r(seed, i + 10) - 0.5) * 1.5, (r(seed, i + 20) - 0.5) * 1.5
			local p = Kit.ball(m, d, CFrame.new(x, d * 0.15, z), Kit.shade(c, (r(seed, i + 60) - 0.5) * 0.2), { material = material })
			biggest = biggest or p
		end
		-- Veins: flat streaks across the rock so ore reads even at a glance.
		for i = 1, 2 do
			local a = r(seed, i + 70) * math.pi
			Kit.block(m, Vector3.new(1.8, 0.06, 0.14), CFrame.new(0, 0.01, (i - 1.5) * 0.6) * CFrame.Angles(0, a, 0), Kit.shade(c, -0.25), {
				material = material,
				shadow = false,
			})
		end
		return biggest :: BasePart
	end,
	crystal = function(m: Model, c: Color3, material: Enum.Material, seed: number): BasePart
		Kit.block(m, Vector3.new(1.2, 0.5, 1.1), CFrame.new(0, 0.05, 0) * CFrame.Angles(0, r(seed, 1) * 3, 0.1), "3A3540", {
			material = Enum.Material.Slate,
		})
		local biggest: BasePart? = nil
		for i = 1, 5 do
			local h = if i == 1 then 1.5 else 0.6 + r(seed, i) * 0.6
			local w = if i == 1 then 0.5 else 0.3 + r(seed, i + 5) * 0.15
			local a = (i - 1) / 5 * math.pi * 2 + r(seed, i + 9)
			local tilt = if i == 1 then 0.08 else 0.35 + r(seed, i + 13) * 0.3
			local base = CFrame.new(math.cos(a) * (if i == 1 then 0 else 0.35), 0, math.sin(a) * (if i == 1 then 0 else 0.35))
				* CFrame.Angles(0, -a, 0)
				* CFrame.Angles(0, 0, tilt)
				* CFrame.Angles(0, math.pi / 4, 0)
			local parts = Kit.crystal(m, w, h, w * 0.9, base, c, { material = material, transparency = 0.08 })
			biggest = biggest or parts[1]
		end
		return biggest :: BasePart
	end,
}

--- Ore cluster for (oreId, mutationId); `seed` varies the arrangement.
function OreModels.cluster(oreId: string, mutationId: string?, seed: number): Model
	local ore = oreById[oreId] or GameConfig.Ores[1]
	local mutation = mutationById[mutationId or "none"] or GameConfig.Mutations[1]
	local m = Kit.model(ore.name)
	local c = Color3.fromHex(ore.color)
	local material = (Enum.Material :: any)[ore.material] or Enum.Material.SmoothPlastic
	if mutation.id == "flawless" then
		c = Kit.shade(c, 0.22)
	elseif mutation.id == "ancient" then
		c = c:Lerp(Color3.fromHex("F2B33D"), 0.35)
	elseif mutation.id == "molten" then
		c = c:Lerp(Color3.fromHex("FF6A2A"), 0.6)
		material = Enum.Material.Neon
	end
	local main = SHAPES[ore.shape](m, c, material, seed)
	if ore.shape == "crystal" then
		Kit.light(main, c, 0.9, 7)
	end
	if mutation.id == "flawless" then
		sparkle(main, Kit.shade(c, 0.5), 4)
		Kit.light(main, Kit.shade(c, 0.4), 0.8, 6)
	elseif mutation.id == "ancient" then
		Kit.ring(m, 0.62, 10, 0.08, 0.1, CFrame.new(0, 0.3, 0), "F2B33D", { material = Enum.Material.Neon, shadow = false })
		Kit.light(main, "F2B33D", 1.2, 8)
		sparkle(main, Color3.fromHex("FFE2A8"), 3)
	elseif mutation.id == "molten" then
		embers(main)
		Kit.light(main, "FF6A2A", 2, 10)
	end
	m.PrimaryPart = main
	return m
end

--- Ancient tablet with glowing glyph lines.
function OreModels.relic(seed: number): Model
	local m = Kit.model("Relic")
	for i = 1, 3 do
		Kit.block(m, Vector3.new(0.5, 0.35, 0.45), CFrame.new((i - 2) * 0.55, 0.05, 0.45) * CFrame.Angles(0, r(seed, i) * 2, 0.2), "6E6A62", {
			material = Enum.Material.Slate,
		})
	end
	local tablet = Kit.block(m, Vector3.new(1.1, 1.5, 0.28), CFrame.new(0, 0.6, 0) * CFrame.Angles(-0.25, 0, 0.06), "8C877E", {
		material = Enum.Material.Slate,
	})
	for i = 1, 3 do
		Kit.block(m, Vector3.new(0.6 - i * 0.1, 0.08, 0.04), tablet.CFrame * CFrame.new(0, 0.45 - i * 0.28, -0.15), "F2B33D", {
			material = Enum.Material.Neon,
			shadow = false,
		})
	end
	Kit.light(tablet, "F2B33D", 1.4, 8)
	sparkle(tablet, Color3.fromHex("FFE2A8"), 3)
	m.PrimaryPart = tablet
	return m
end

--- Treasure chest; the lid parts carry the "Lid" attribute and hinge at the back.
function OreModels.chest(): Model
	local m = Kit.model("Chest")
	local wood, band, gold = "8A6545", "4A4E55", "F2C14E"
	local base = Kit.block(m, Vector3.new(1.8, 0.9, 1.2), CFrame.new(0, 0.45, 0), wood, { material = Enum.Material.WoodPlanks })
	for _, x in { -0.6, 0.6 } do
		Kit.block(m, Vector3.new(0.16, 0.94, 1.24), CFrame.new(x, 0.45, 0), band, { material = Enum.Material.Metal })
	end
	local lidParts = {
		Kit.cylX(m, 1.8, 1.2, CFrame.new(0, 0.9, 0), wood, { material = Enum.Material.WoodPlanks }),
		Kit.cylX(m, 0.16, 1.24, CFrame.new(-0.6, 0.9, 0), band, { material = Enum.Material.Metal }),
		Kit.cylX(m, 0.16, 1.24, CFrame.new(0.6, 0.9, 0), band, { material = Enum.Material.Metal }),
		Kit.block(m, Vector3.new(0.32, 0.36, 0.12), CFrame.new(0, 0.86, -0.62), gold, { material = Enum.Material.Metal }),
	}
	for _, p in lidParts do
		p:SetAttribute("Lid", true)
	end
	local glow = Kit.block(m, Vector3.new(1.5, 0.08, 0.9), CFrame.new(0, 0.92, 0), gold, { material = Enum.Material.Neon, shadow = false, name = "Glow" })
	Kit.light(glow, gold, 1.5, 9)
	sparkle(glow, Color3.fromHex("FFE9A8"), 5)
	m.PrimaryPart = base
	return m
end

--- Blast charge: three sticks, a strap, a fuse and a blinking spark ("Blink").
function OreModels.charge(): Model
	local m = Kit.model("Charge")
	local red, strap = "C8452F", "3A2E24"
	local main: BasePart? = nil
	for i, x in { -0.3, 0, 0.3 } do
		local p = Kit.cylY(m, 1.2, 0.36, CFrame.new(x, 0.6, if i == 2 then -0.2 else 0.08), red)
		Kit.cylY(m, 0.08, 0.37, CFrame.new(x, 1.18, if i == 2 then -0.2 else 0.08), "E9DCC4")
		main = main or p
	end
	Kit.block(m, Vector3.new(1.05, 0.2, 0.75), CFrame.new(0, 0.55, -0.04), strap)
	local fuseTop = Vector3.new(0.15, 1.65, -0.35)
	Kit.beam(m, Vector3.new(0, 1.2, -0.2), fuseTop, 0.07, "2B2B2B")
	local blink = Kit.ball(m, 0.22, CFrame.new(fuseTop), "FFC46B", { material = Enum.Material.Neon, name = "Blink", shadow = false })
	Kit.light(blink, "FF8A3D", 1.5, 8)
	sparkle(blink, Color3.fromHex("FFC46B"), 6)
	m.PrimaryPart = main
	return m
end

--- Cluster on a little rock plinth, for collection-book thumbnails.
function OreModels.preview(oreId: string, mutationId: string?): Model
	local m = OreModels.cluster(oreId, mutationId, 7)
	Kit.cylY(m, 0.5, 2.6, CFrame.new(0, -0.25, 0), "4A4652", { material = Enum.Material.Slate, name = "Plinth" })
	return m
end

return OreModels
