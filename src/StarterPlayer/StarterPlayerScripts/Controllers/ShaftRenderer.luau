--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/ShaftRenderer (ModuleScript)
-- Renders only this player's shaft, only around the player, only from pools.
-- The whole 1050 m column is never instantiated: a window of blocks below the
-- player plus three wall chunks is all that exists at any time.
--
-- Walls are a ring of chunky rock voxels per 4-stud slice, banded into strata
-- and studded with roots, pebbles, ore, crystals, lava, timber and lanterns.
-- None of that collides: the only collidable wall geometry is four hidden
-- slabs per chunk whose inner faces sit exactly 4 studs from the centre, so
-- nothing can catch a falling character. Visuals derive from (seed, slice)
-- alone, so a chunk rebuilds identically whenever it is reacquired.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Hash = require(ReplicatedStorage.Shared.Hash)
local Layers = require(ReplicatedStorage.Shared.Layers)
local OreGen = require(ReplicatedStorage.Shared.OreGen)
local Types = require(ReplicatedStorage.Shared.Types)

local ShaftRenderer = {}

local G = GameConfig.Geometry
local H = G.BlockHeight
local HALF = G.BlockSize / 2
local WALL = 4 -- rock behind each shaft face
local POKE_MIN, POKE_MAX = 0.06, 0.5 -- voxel faces protrude this far (never coplanar with the slabs)
local SURFACE_DROP = 0.12 -- the top slice stops short of Y=0 so it never z-fights the island
local BLEND = 4 -- metres of mixed rock either side of a layer boundary
local DECO_BLOCKS = 2 -- only the top two blocks can ever be seen
local CRACKS = 6
local CHUNK_LIGHTS = 6
local TAU = 2 * math.pi
local M = Enum.Material
local BLOCK, BALL, CYLINDER = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> world Y
local ALONG = CFrame.Angles(0, math.pi / 2, 0) -- after lookAt: cylinder axis X -> look direction

local SALT_SHADE = 53
local SALT_BAND = 101
local SALT_SLICE = 103
local SALT_MIX = 107
local SALT_DECO = 109
local SALT_CHUNK = 113
local SALT_CRACK = 127

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local IRON = Color3.fromHex("2F3038")
local LANTERN_GLOW = Color3.fromHex("FFC56B")
local LANTERN_LIGHT = Color3.fromHex("FFB65C")
local ROOT_COLOR = Color3.fromHex("5E3B20")
local WORM_COLOR = Color3.fromHex("FF8FAE")
local BONE_COLOR = Color3.fromHex("F2EAD6")
local STEM_COLOR = Color3.fromHex("E9DEFF")
local GOLD = Color3.fromHex("FFC93C")
local RELIC_GEM = Color3.fromHex("3FE0FF")
local LAVA = Color3.fromHex("FF7A1A")
local LAVA_ROCK = Color3.fromHex("5A2440")
local SEAL_ROCK = Color3.fromHex("2B1810")
local SEAL_RING = Color3.fromHex("D9A441")

local SPARKLE_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.3, 0.45),
	NumberSequenceKeypoint.new(1, 0),
})
local FADE = NumberSequence.new(0.1, 1)
local EMBER_SIZE = NumberSequence.new(0.4, 0)

type Bag = { parts: { Part }, lights: { PointLight }, meshes: { SpecialMesh }, emitters: { ParticleEmitter } }
type Budget = { lights: number }

type BlockView = {
	part: Part,
	textures: { Texture },
	index: number,
	color: Color3,
	bag: Bag,
	decorated: boolean,
}

type WallChunk = { slabs: { Part }, bag: Bag, chunk: number }

type Face = { n: Vector3, t: Vector3, span: number, alongX: boolean }

type Odds = { nugget: number, pebble: number, crystal: number, lava: number, mushroom: number }

type Palette = {
	bands: { string },
	mats: { string },
	pebble: string,
	wood: string?,
	crystal: string?,
	crystalCore: string?,
	lava: string?,
	mushroom: string?,
	roots: boolean?,
	worms: boolean?,
	fossils: boolean?,
	odds: Odds,
}

type Style = {
	layer: Types.LayerDef,
	material: Enum.Material,
	variant: string,
	ground: Color3,
	bands: { Color3 },
	bandMats: { Enum.Material },
	pebble: Color3,
	wood: Color3?,
	crystal: Color3?,
	crystalCore: Color3?,
	lava: Color3?,
	mushroom: Color3?,
	roots: boolean,
	worms: boolean,
	fossils: boolean,
	odds: Odds,
}

-- Extra strata and decor per layer id, on top of the layer's own
-- wallColor (dominant band) and accentColor (rare bright band).
local PALETTES: { [string]: Palette } = {
	topsoil = {
		bands = { "95522B", "62351C", "B8743A", "CC9358", "7A5638" },
		mats = { "Ground", "Ground", "Sandstone", "Sand", "Pebble" },
		pebble = "A69584",
		wood = "A36B3A",
		roots = true,
		worms = true,
		fossils = true,
		odds = { nugget = 0.07, pebble = 0.1, crystal = 0, lava = 0, mushroom = 0 },
	},
	bedrock = {
		bands = { "5F7397", "3D4A63", "8397BA", "4A5E86", "6C7C9C" },
		mats = { "Slate", "Slate", "Limestone", "Rock", "Slate" },
		pebble = "A0AABD",
		wood = "7C5130",
		crystal = "35E2FF",
		crystalCore = "C4FCFF",
		fossils = true,
		odds = { nugget = 0.07, pebble = 0.05, crystal = 0.08, lava = 0, mushroom = 0 },
	},
	hollows = {
		bands = { "4D2F80", "2B1A4C", "6A3389", "211538", "3D2A5C" },
		mats = { "Basalt", "Basalt", "Rock", "Slate", "CrackedLava" },
		pebble = "7D6AA6",
		crystal = "B45CFF",
		crystalCore = "F2CCFF",
		lava = "FF7A1A",
		mushroom = "4DFFD8",
		odds = { nugget = 0.05, pebble = 0.03, crystal = 0.1, lava = 0.06, mushroom = 0.04 },
	},
}

local DEFAULT_ODDS: Odds = { nugget = 0.06, pebble = 0.06, crystal = 0, lava = 0, mushroom = 0 }

local function material(name: string, fallback: Enum.Material): Enum.Material
	local found = (Enum.Material :: any)[name]
	return if found then found else fallback
end

local function optColor(value: string?): Color3?
	return if value then Color3.fromHex(value) else nil
end

local styles: { Style } = {}
local anyVariant = false
for i, layer in GameConfig.Layers do
	local palette = PALETTES[layer.id]
	local base = material(layer.material, M.Slate)
	local bands = { Color3.fromHex(layer.wallColor) }
	local mats = { base }
	if palette then
		for j, value in palette.bands do
			table.insert(bands, Color3.fromHex(value))
			table.insert(mats, material(palette.mats[j] or layer.material, base))
		end
	end
	table.insert(bands, Color3.fromHex(layer.accentColor))
	table.insert(mats, base)
	local slots = (AssetIds.Textures :: { [string]: any })[layer.id]
	local variant = if slots and typeof(slots.MaterialVariant) == "string" then slots.MaterialVariant else ""
	anyVariant = anyVariant or variant ~= ""
	styles[i] = {
		layer = layer,
		material = base,
		variant = variant,
		ground = Color3.fromHex(layer.groundColor),
		bands = bands,
		bandMats = mats,
		pebble = Color3.fromHex(if palette then palette.pebble else layer.accentColor),
		wood = optColor(palette and palette.wood),
		crystal = optColor(palette and palette.crystal),
		crystalCore = optColor(palette and (palette.crystalCore or palette.crystal)),
		lava = optColor(palette and palette.lava),
		mushroom = optColor(palette and palette.mushroom),
		roots = palette ~= nil and palette.roots == true,
		worms = palette ~= nil and palette.worms == true,
		fossils = palette ~= nil and palette.fossils == true,
		odds = if palette then palette.odds else DEFAULT_ODDS,
	}
end

local FACES: { Face } = {
	-- N/S faces run through the corners; E/W faces sit between them.
	{ n = Vector3.new(0, 0, -1), t = Vector3.new(1, 0, 0), span = HALF + WALL, alongX = true },
	{ n = Vector3.new(0, 0, 1), t = Vector3.new(-1, 0, 0), span = HALF + WALL, alongX = true },
	{ n = Vector3.new(-1, 0, 0), t = Vector3.new(0, 0, 1), span = HALF, alongX = false },
	{ n = Vector3.new(1, 0, 0), t = Vector3.new(0, 0, -1), span = HALF, alongX = false },
}
local SIDES = { -1, 1 }

local folder = Instance.new("Folder")
folder.Name = "LocalShaft"
folder.Parent = Workspace

local center: Vector3 = Vector3.zero
local centerKnown = false
local seed = 0
local depth = 0

local freeBlocks: { BlockView } = {}
local blockByIndex: { [number]: BlockView } = {}
local freeWalls: { WallChunk } = {}
local wallByChunk: { [number]: WallChunk } = {}
local rollCache: { [number]: Types.BlockRoll } = {}

local partPool: { Part } = {}
local lightPool: { PointLight } = {}
local meshPool: { SpecialMesh } = {}
local emitterPool: { ParticleEmitter } = {}

function ShaftRenderer.blockCFrame(index: number): CFrame
	return CFrame.new(center + Vector3.new(0, G.SurfaceY - (index - 1) * H - H / 2, 0))
end

function ShaftRenderer.rollAt(index: number): Types.BlockRoll
	local cached = rollCache[index]
	if not cached then
		cached = OreGen.roll(seed, index)
		rollCache[index] = cached
	end
	return cached
end

-- Geometry helpers ----------------------------------------------------------------

--- World Y of the top of slice k (slice k is the rock beside block k + 1).
local function topY(k: number): number
	return center.Y + G.SurfaceY - k * H
end

--- A point `inset` studs in front of a shaft face (the plane HALF from the centre).
local function facePoint(face: Face, along: number, y: number, inset: number): Vector3
	return Vector3.new(center.X, y, center.Z) + face.n * (HALF - inset) + face.t * along
end

-- Pools ---------------------------------------------------------------------------

local function newBag(): Bag
	return { parts = {}, lights = {}, meshes = {}, emitters = {} }
end

local function newDecorPart(): Part
	local part = Instance.new("Part")
	part.Name = "Decor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function newSphereMesh(): SpecialMesh
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	return mesh
end

--- A pooled, non-collidable decor part, fully reconfigured on every use.
local function piece(bag: Bag, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, mat: Enum.Material): Part
	local part = table.remove(partPool) or newDecorPart()
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = mat
	part.Transparency = 0
	part.Reflectance = 0
	if anyVariant then
		part.MaterialVariant = ""
	end
	part.Parent = folder
	table.insert(bag.parts, part)
	return part
end

--- Ellipsoid look for a block-shaped piece.
local function round(bag: Bag, part: Part)
	local mesh = table.remove(meshPool) or newSphereMesh()
	mesh.Parent = part
	table.insert(bag.meshes, mesh)
end

local function glow(bag: Bag, parent: BasePart, color: Color3, brightness: number, range: number)
	local light = table.remove(lightPool) or Instance.new("PointLight")
	light.Shadows = false
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Parent = parent
	table.insert(bag.lights, light)
end

local function emitter(bag: Bag, parent: BasePart, ember: boolean, color: Color3, rate: number)
	local e = table.remove(emitterPool) or Instance.new("ParticleEmitter")
	if ember then
		e.Texture = AssetIds.Particles.Ember
		e.Lifetime = NumberRange.new(0.8, 1.6)
		e.Speed = NumberRange.new(1.5, 3.5)
		e.SpreadAngle = Vector2.new(30, 30)
		e.Acceleration = Vector3.new(0, 3, 0)
		e.Size = EMBER_SIZE
	else
		e.Texture = AssetIds.Particles.Sparkle
		e.Lifetime = NumberRange.new(0.6, 1.2)
		e.Speed = NumberRange.new(0.4, 1.4)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.zero
		e.Size = SPARKLE_SIZE
	end
	e.EmissionDirection = Enum.NormalId.Top
	e.Transparency = FADE
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = rate
	e.Enabled = true
	e.Parent = parent
	table.insert(bag.emitters, e)
end

local function releaseBag(bag: Bag)
	-- Children first, so a recycled part never carries a stale light or mesh.
	for _, light in bag.lights do
		light.Parent = nil
		table.insert(lightPool, light)
	end
	for _, mesh in bag.meshes do
		mesh.Parent = nil
		table.insert(meshPool, mesh)
	end
	for _, e in bag.emitters do
		e.Enabled = false
		e:Clear()
		e.Parent = nil
		table.insert(emitterPool, e)
	end
	for _, part in bag.parts do
		part.Parent = nil
		table.insert(partPool, part)
	end
	table.clear(bag.lights)
	table.clear(bag.meshes)
	table.clear(bag.emitters)
	table.clear(bag.parts)
end

-- Strata --------------------------------------------------------------------------

local function tone(color: Color3, rng: Random, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(
		(h + rng:NextNumber(-0.012, 0.012)) % 1,
		math.clamp(s + rng:NextNumber(-amount, amount) * 0.5, 0, 1),
		math.clamp(v + rng:NextNumber(-amount, amount), 0, 1)
	)
end

local function shade(color: Color3, index: number): Color3
	-- ±5% value jitter so a column of identical blocks still reads as rock.
	local t = (Hash.unit(seed, index, SALT_SHADE) - 0.5) * 0.1
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + t, 0, 1))
end

--- Strata band (index into style.bands) for slice k: 2 m bands, base rock dominant.
local function bandOf(style: Style, k: number): number
	local u = Hash.unit(seed, k // 2, SALT_BAND)
	if u < 0.42 then
		return 1
	end
	return 2 + math.floor((u - 0.42) / 0.58 * (#style.bands - 1))
end

--- Style for slice k. Within BLEND metres of a boundary some rock belongs to
--- the neighbouring layer, so the change dithers instead of snapping.
local function styleAt(k: number, u: number): Style
	local li = Layers.indexAt(k)
	local start = Layers.get(li).startDepth
	local finish = Layers.endDepth(li)
	if li < #styles and k >= finish - BLEND then
		if u < (k - finish + BLEND + 0.5) / (2 * BLEND) then
			return styles[li + 1]
		end
	elseif li > 1 and k < start + BLEND then
		if u < 0.5 - (k - start + 0.5) / (2 * BLEND) then
			return styles[li - 1]
		end
	end
	return styles[li]
end

local function pickOre(layer: Types.LayerDef, u: number): Types.OreDef?
	local total = 0
	for _, entry in layer.ores do
		if entry.id ~= "" then
			total += entry.weight
		end
	end
	local target = u * total
	for _, entry in layer.ores do
		if entry.id ~= "" then
			target -= entry.weight
			if target < 0 then
				return Economy.oreById[entry.id]
			end
		end
	end
	return nil
end

-- Wall decor ----------------------------------------------------------------------

local function addPebble(bag: Bag, rng: Random, style: Style, face: Face, along: number, y: number, poke: number)
	local size = rng:NextNumber(0.5, 0.95)
	piece(bag, BALL, Vector3.one * size, CFrame.new(facePoint(face, along, y, poke + size * 0.1)), tone(style.pebble, rng, 0.08), M.Slate)
end

local function addNugget(bag: Bag, rng: Random, style: Style, face: Face, along: number, y: number, poke: number, budget: Budget)
	local ore = pickOre(style.layer, rng:NextNumber())
	if not ore then
		return
	end
	local color = Color3.fromHex(ore.color)
	local mat = material(ore.material, M.Slate)
	local count = if rng:NextNumber() < 0.5 then 1 else 2
	local first: Part? = nil
	for i = 1, count do
		local size = rng:NextNumber(0.55, 0.95) * (if i == 1 then 1 else 0.7)
		local offset = if i == 1 then Vector3.zero else face.t * rng:NextNumber(-0.7, 0.7) + Vector3.new(0, rng:NextNumber(-0.5, 0.5), 0)
		local cframe = CFrame.new(facePoint(face, along, y, poke + size * 0.15) + offset)
			* CFrame.Angles(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), rng:NextNumber(0, TAU))
		local part = piece(bag, BLOCK, Vector3.one * size, cframe, color, mat)
		if mat == M.Metal then
			part.Reflectance = 0.15
		end
		first = first or part
	end
	local lit = rng:NextNumber()
	if first and ore.rarity >= 3 and lit < 0.5 and budget.lights > 0 then
		budget.lights -= 1
		glow(bag, first, color, 0.9, 7)
	end
end

local function addCrystals(bag: Bag, rng: Random, style: Style, face: Face, along: number, y: number, poke: number, scale: number, budget: Budget)
	local crystal = style.crystal or WHITE
	local core = style.crystalCore or crystal
	local base = facePoint(face, along, y, poke - 0.15)
	local count = if rng:NextNumber() < 0.45 then 2 else 3
	local first: Part? = nil
	for i = 1, count do
		local len = rng:NextNumber(1.1, 1.9) * scale * (if i == 1 then 1.25 else 0.85)
		local width = rng:NextNumber(0.3, 0.46) * scale
		local dir = (-face.n + Vector3.new(0, rng:NextNumber(-0.45, 0.9), 0) + face.t * rng:NextNumber(-0.7, 0.7)).Unit
		-- lookAt points -Z along dir; the X turn stands the crystal's Y axis on it.
		local cframe = CFrame.lookAt(base, base + dir) * CFrame.Angles(-math.pi / 2, rng:NextNumber(0, 1.5), 0) * CFrame.new(0, len * 0.4, 0)
		local part = piece(bag, BLOCK, Vector3.new(width, len, width), cframe, if i == 1 then core else crystal, if i == 1 then M.Neon else M.Glass)
		if i ~= 1 then
			part.Transparency = 0.12
			part.Reflectance = 0.25
		end
		first = first or part
	end
	local lit = rng:NextNumber()
	if first and lit < 0.6 and budget.lights > 0 then
		budget.lights -= 1
		glow(bag, first, crystal, 1.2 * scale, 9)
	end
end

local function addLava(
	bag: Bag,
	rng: Random,
	style: Style,
	face: Face,
	along: number,
	y: number,
	poke: number,
	va: number,
	vb: number,
	yBot: number,
	yTop: number,
	budget: Budget
)
	local lava = style.lava or LAVA
	local count = if rng:NextNumber() < 0.5 then 2 else 3
	local dirSign = if rng:NextNumber() < 0.5 then -1 else 1
	local t0, y0 = along, y
	local first: Part? = nil
	for i = 1, count do
		-- A zigzag kept inside this voxel's face so it never floats over a neighbour.
		local angle = rng:NextNumber(0.25, 0.95) * (if i % 2 == 0 then -1 else 1)
		local len = rng:NextNumber(0.9, 1.6)
		local t1 = math.clamp(t0 + math.cos(angle) * len * dirSign, va + 0.15, vb - 0.15)
		local y1 = math.clamp(y0 + math.sin(angle) * len, yBot + 0.25, yTop - 0.25)
		local a = facePoint(face, t0, y0, poke + 0.04)
		local b = facePoint(face, t1, y1, poke + 0.04)
		local span = b - a
		local length = span.Magnitude
		if length > 0.2 then
			local size = Vector3.new(length + 0.12, 0.14, rng:NextNumber(0.18, 0.28))
			local part = piece(bag, BLOCK, size, CFrame.fromMatrix((a + b) / 2, span.Unit, face.n), lava, M.Neon)
			first = first or part
		end
		t0, y0 = t1, y1
	end
	local lit = rng:NextNumber()
	if first and lit < 0.5 and budget.lights > 0 then
		budget.lights -= 1
		glow(bag, first, lava, 1.3, 8)
	end
end

local function addRoot(bag: Bag, rng: Random, face: Face, along: number, yTop: number, poke: number)
	local start = facePoint(face, along, yTop - rng:NextNumber(0.3, 1.2), poke - 0.25)
	local color = tone(ROOT_COLOR, rng, 0.06)
	local width = rng:NextNumber(0.28, 0.42)
	local d1 = (-face.n * 0.75 + Vector3.new(0, -0.65, 0) + face.t * rng:NextNumber(-0.35, 0.35)).Unit
	local l1 = rng:NextNumber(1.2, 2)
	piece(bag, CYLINDER, Vector3.new(l1, width, width), CFrame.lookAt(start, start + d1) * ALONG * CFrame.new(l1 / 2, 0, 0), color, M.Wood)
	local joint = start + d1 * (l1 - 0.1)
	local d2 = (-face.n * 0.2 + Vector3.new(0, -1, 0) + face.t * rng:NextNumber(-0.5, 0.5)).Unit
	local l2 = rng:NextNumber(0.9, 1.5)
	local w2 = width * 0.62
	piece(bag, CYLINDER, Vector3.new(l2, w2, w2), CFrame.lookAt(joint, joint + d2) * ALONG * CFrame.new(l2 / 2, 0, 0), color, M.Wood)
end

local function addMushrooms(bag: Bag, rng: Random, style: Style, face: Face, along: number, y: number, poke: number, budget: Budget)
	local glowColor = style.mushroom or LAVA
	local count = if rng:NextNumber() < 0.5 then 1 else 2
	local first: Part? = nil
	for i = 1, count do
		local s = rng:NextNumber(0.7, 1.1) * (if i == 1 then 1 else 0.7)
		local at = along + (if i == 1 then 0 else rng:NextNumber(-0.8, 0.8))
		local ay = y + (if i == 1 then 0 else rng:NextNumber(-0.5, 0.4))
		local stem = 0.55 * s
		local stemCFrame = CFrame.fromMatrix(facePoint(face, at, ay, poke + stem / 2 - 0.05), face.n, Vector3.yAxis)
		piece(bag, CYLINDER, Vector3.new(stem, 0.18 * s, 0.18 * s), stemCFrame, STEM_COLOR, M.SmoothPlastic)
		local cap = piece(bag, BLOCK, Vector3.new(0.95 * s, 0.42 * s, 0.95 * s), CFrame.new(facePoint(face, at, ay + 0.12 * s, poke + stem)), glowColor, M.Neon)
		round(bag, cap)
		first = first or cap
	end
	local lit = rng:NextNumber()
	if first and lit < 0.35 and budget.lights > 0 then
		budget.lights -= 1
		glow(bag, first, glowColor, 0.8, 6)
	end
end

local function addWorm(bag: Bag, rng: Random, face: Face, along: number, y: number, poke: number)
	local dir = if rng:NextNumber() < 0.5 then -1 else 1
	local pos = facePoint(face, along, y, poke + 0.02)
	for i = 1, 3 do
		piece(bag, BALL, Vector3.one * (0.38 - i * 0.03), CFrame.new(pos), WORM_COLOR, M.SmoothPlastic)
		pos += -face.n * (0.2 - i * 0.04) + Vector3.new(0, 0.18, 0) + face.t * (0.24 * dir)
	end
end

local function addFossil(bag: Bag, rng: Random, face: Face, along: number, y: number, poke: number)
	local angle = rng:NextNumber(-0.7, 0.7)
	local axis = face.t * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)
	local mid = facePoint(face, along, y, poke - 0.02)
	piece(bag, CYLINDER, Vector3.new(1.2, 0.22, 0.22), CFrame.fromMatrix(mid, axis, face.n), BONE_COLOR, M.SmoothPlastic)
	for _, side in SIDES do
		piece(bag, BALL, Vector3.one * 0.36, CFrame.new(mid + axis * (0.6 * side)), BONE_COLOR, M.SmoothPlastic)
	end
end

--- One roll per visible voxel face; most voxels stay bare.
local function decorate(
	bag: Bag,
	rng: Random,
	style: Style,
	face: Face,
	k: number,
	va: number,
	vb: number,
	yBot: number,
	yTop: number,
	poke: number,
	nearCore: number,
	budget: Budget
)
	local roll = rng:NextNumber()
	local along = rng:NextNumber(va + 0.35, vb - 0.35)
	local y = rng:NextNumber(yBot + 0.8, yTop - 0.8)
	local odds = style.odds
	local c = if style.roots then math.max(0, 0.16 - k * 0.003) else 0
	if roll < c then
		addRoot(bag, rng, face, along, yTop, poke)
		return
	end
	c += odds.pebble
	if roll < c then
		addPebble(bag, rng, style, face, along, y, poke)
		return
	end
	c += odds.nugget
	if roll < c then
		addNugget(bag, rng, style, face, along, y, poke, budget)
		return
	end
	if style.crystal then
		-- Crystals grow bigger and more common the deeper the layer goes.
		local through = math.clamp((k - style.layer.startDepth) / 300, 0, 1)
		c += odds.crystal + nearCore * 0.03
		if roll < c then
			addCrystals(bag, rng, style, face, along, y, poke, 0.9 + through * 0.4, budget)
			return
		end
	end
	if style.lava then
		c += odds.lava + nearCore * 0.15
		if roll < c then
			addLava(bag, rng, style, face, along, y, poke, va, vb, yBot, yTop, budget)
			return
		end
	end
	if style.mushroom then
		c += odds.mushroom
		if roll < c then
			addMushrooms(bag, rng, style, face, along, y, poke, budget)
			return
		end
	end
	if style.worms and k < 60 then
		c += 0.012
		if roll < c then
			addWorm(bag, rng, face, along, y, poke)
			return
		end
	end
	if style.fossils then
		c += 0.007
		if roll < c then
			addFossil(bag, rng, face, along, y, poke)
		end
	end
end

-- Walls ---------------------------------------------------------------------------

local function buildSlice(bag: Bag, k: number, budget: Budget)
	local rng = Random.new(Hash.u32(seed, k, SALT_SLICE))
	local yTop = topY(k) - (if k == 0 then SURFACE_DROP else 0)
	local yBot = topY(k + 1)
	local yMid = (yTop + yBot) / 2
	local height = yTop - yBot
	local nearCore = math.clamp((k - (GameConfig.CoreDepth - 100)) / 100, 0, 1)
	for _, face in FACES do
		-- 2 or 3 rocks per face, split at different points every slice.
		local cut1, cut2
		if rng:NextNumber() < 0.55 then
			cut1, cut2 = rng:NextNumber(-2.2, 2.2), face.span
		else
			cut1, cut2 = rng:NextNumber(-2.8, -0.7), rng:NextNumber(0.7, 2.8)
		end
		local a = -face.span
		for seg = 1, 3 do
			local b = if seg == 1 then cut1 elseif seg == 2 then cut2 else face.span
			if b > a then
				local style = styleAt(k, rng:NextNumber())
				local band = bandOf(style, k)
				local color = tone(style.bands[band], rng, 0.07)
				local mat = style.bandMats[band]
				local odd = rng:NextNumber()
				if style.lava and odd < 0.05 + nearCore * 0.2 then
					mat = M.CrackedLava
					color = tone(LAVA_ROCK, rng, 0.05)
				elseif odd > 0.94 then
					mat = M.Rock -- a stray boulder in the strata
					color = tone(style.bands[1]:Lerp(style.pebble, 0.5), rng, 0.05)
				end
				local poke = rng:NextNumber(POKE_MIN, POKE_MAX)
				local thick = WALL + poke
				local size = if face.alongX then Vector3.new(b - a, height, thick) else Vector3.new(thick, height, b - a)
				local pos = Vector3.new(center.X, yMid, center.Z) + face.n * (HALF - poke + thick / 2) + face.t * ((a + b) / 2)
				local voxel = piece(bag, BLOCK, size, CFrame.new(pos), color, mat)
				if anyVariant and mat == style.material then
					voxel.MaterialVariant = style.variant
				end
				local va, vb = math.max(a, -HALF + 0.5), math.min(b, HALF - 0.5)
				if vb - va >= 1 then
					decorate(bag, rng, style, face, k, va, vb, yBot, yTop, poke, nearCore, budget)
				end
				a = b
			end
		end
	end
end

local function addTimber(bag: Bag, rng: Random, k0: number, wood: Color3)
	local top = topY(k0) - 0.3
	for _, face in FACES do
		-- E/W beams sit slightly lower so the corner overlaps never share a face.
		local size = if face.alongX then Vector3.new(G.BlockSize, 0.9, 0.9) else Vector3.new(0.9, 0.86, G.BlockSize)
		local y = if face.alongX then top - 0.45 else top - 0.51
		piece(bag, BLOCK, size, CFrame.new(Vector3.new(center.X, y, center.Z) + face.n * (HALF - 0.45)), tone(wood, rng, 0.05), M.WoodPlanks)
	end
	local postColor = tone(wood, rng, 0.04):Lerp(BLACK, 0.15)
	for _, sx in SIDES do
		for _, sz in SIDES do
			local pos = Vector3.new(center.X + sx * (HALF - 0.5), top - 3.6, center.Z + sz * (HALF - 0.5))
			piece(bag, BLOCK, Vector3.new(0.8, 7.1, 0.8), CFrame.new(pos), postColor, M.Wood)
		end
	end
end

local function addLantern(bag: Bag, rng: Random, k0: number, timber: boolean)
	local face = FACES[1 + math.floor(rng:NextNumber() * 4)]
	local along = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(1.6, 2.4)
	local inset = if timber then 0.9 else 1.05
	local hook = topY(k0) - (if timber then 1.2 else 0.9)
	if not timber then
		-- Iron arm out of the rock where there is no beam to hang from.
		local size = if face.alongX then Vector3.new(0.22, 0.22, 1.25) else Vector3.new(1.25, 0.22, 0.22)
		piece(bag, BLOCK, size, CFrame.new(facePoint(face, along, hook + 0.1, 0.5)), IRON, M.Metal)
	end
	local chain = 0.7
	piece(bag, CYLINDER, Vector3.new(chain, 0.12, 0.12), CFrame.new(facePoint(face, along, hook - chain / 2, inset)) * UPRIGHT, IRON, M.Metal)
	local capY = hook - chain - 0.11
	piece(bag, BLOCK, Vector3.new(0.78, 0.22, 0.78), CFrame.new(facePoint(face, along, capY, inset)), IRON, M.Metal)
	local glassY = capY - 0.53
	local glass = piece(bag, BLOCK, Vector3.new(0.58, 0.84, 0.58), CFrame.new(facePoint(face, along, glassY, inset)), LANTERN_GLOW, M.Neon)
	piece(bag, BLOCK, Vector3.new(0.78, 0.2, 0.78), CFrame.new(facePoint(face, along, glassY - 0.52, inset)), IRON, M.Metal)
	glow(bag, glass, LANTERN_LIGHT, 1.6, 16)
end

local function newSlab(): Part
	local part = Instance.new("Part")
	part.Name = "WallSlab"
	part.Anchored = true
	part.CanTouch = false
	part.CastShadow = true -- keeps sunlight from reaching deep into the shaft
	part.Material = M.Slate
	part.Color = Color3.fromHex("2A2420")
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function newWallChunk(): WallChunk
	return { slabs = { newSlab(), newSlab(), newSlab(), newSlab() }, bag = newBag(), chunk = -1 }
end

local function acquireWalls(chunk: number)
	local wall = table.remove(freeWalls) or newWallChunk()
	wall.chunk = chunk
	local blocks = G.WallChunkBlocks
	local k0 = chunk * blocks
	local top = topY(k0) - (if chunk == 0 then SURFACE_DROP else 0)
	local bottom = topY(k0 + blocks)
	local height = top - bottom
	local midY = (top + bottom) / 2
	-- Collidable slabs with inner faces exactly HALF from the centre, hidden
	-- behind the voxels (which always protrude at least POKE_MIN past them).
	local slabDefs = {
		{ Vector3.new(G.BlockSize + 4, height, 2), Vector3.new(0, 0, -(HALF + 1)) },
		{ Vector3.new(G.BlockSize + 4, height, 2), Vector3.new(0, 0, HALF + 1) },
		{ Vector3.new(2, height, G.BlockSize), Vector3.new(-(HALF + 1), 0, 0) },
		{ Vector3.new(2, height, G.BlockSize), Vector3.new(HALF + 1, 0, 0) },
	}
	for i, slab in wall.slabs do
		slab.Size = slabDefs[i][1]
		slab.CFrame = CFrame.new(Vector3.new(center.X, midY, center.Z) + slabDefs[i][2])
		slab.Parent = folder
	end

	local rng = Random.new(Hash.u32(seed, chunk, SALT_CHUNK))
	local style = styles[Layers.indexAt(k0)]
	local budget: Budget = { lights = CHUNK_LIGHTS }
	if style.wood then
		addTimber(wall.bag, rng, k0, style.wood)
	end
	if chunk % 2 == 0 then
		addLantern(wall.bag, rng, k0, style.wood ~= nil)
		budget.lights -= 1
	end
	for k = k0, k0 + blocks - 1 do
		buildSlice(wall.bag, k, budget)
	end
	wallByChunk[chunk] = wall
end

local function releaseWalls(chunk: number)
	local wall = wallByChunk[chunk]
	if wall then
		for _, slab in wall.slabs do
			slab.Parent = nil
		end
		releaseBag(wall.bag)
		wallByChunk[chunk] = nil
		table.insert(freeWalls, wall)
	end
end

-- Blocks --------------------------------------------------------------------------

local function newBlock(): BlockView
	local part = Instance.new("Part")
	part.Name = "Block"
	part.Anchored = true
	part.Size = Vector3.new(G.BlockSize, H, G.BlockSize)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	local textures = {}
	for _, face in { Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		local texture = Instance.new("Texture")
		texture.Face = face
		texture.StudsPerTileU = 4
		texture.StudsPerTileV = 4
		texture.Texture = ""
		texture.Parent = part
		table.insert(textures, texture)
	end
	return { part = part, textures = textures, index = 0, color = WHITE, bag = newBag(), decorated = false }
end

local function applySurface(view: BlockView, style: Style?, color: Color3)
	local part = view.part
	part.Material = if style then style.material else M.Basalt
	part.Color = color
	if anyVariant then
		part.MaterialVariant = if style then style.variant else ""
	end
	local slots = if style then (AssetIds.Textures :: { [string]: any })[style.layer.id] else nil
	for i, texture in view.textures do
		local id = if slots then (if i == 1 then slots.Top else slots.Side) else 0
		texture.Texture = AssetIds.image(if typeof(id) == "number" then id else 0)
		texture.Color3 = color
	end
end

local function oreCluster(bag: Bag, rng: Random, base: Vector3, roll: Types.BlockRoll)
	local ore = Economy.oreById[roll.oreId or ""]
	if not ore then
		return
	end
	local mutation = Economy.mutationById[roll.mutationId or "none"]
	local mutationId = if mutation then mutation.id else "none"
	local color = Color3.fromHex(ore.color)
	local mat = material(ore.material, M.Slate)
	local gem = ore.material == "Glass"
	if mutation and mutationId ~= "none" then
		color = color:Lerp(Color3.fromHex(mutation.color), 0.45)
		mat = if mutationId == "flawless" then M.Glass elseif mutationId == "molten" then M.Neon else mat
	end
	local cx, cz = rng:NextNumber(-1.1, 1.1), rng:NextNumber(-1.1, 1.1)
	local count = 3 + math.floor(rng:NextNumber() * 3)
	local first: Part? = nil
	for i = 1, count do
		local angle = (i - 1) / count * TAU + rng:NextNumber(-0.4, 0.4)
		local radius = if i == 1 then 0 else rng:NextNumber(0.75, 1.5)
		local x = math.clamp(cx + math.cos(angle) * radius, -2.8, 2.8)
		local z = math.clamp(cz + math.sin(angle) * radius, -2.8, 2.8)
		local at = base + Vector3.new(x, 0, z)
		local part: Part
		if gem then
			-- Crystal prisms leaning out from the cluster centre.
			local len = if i == 1 then rng:NextNumber(1.9, 2.4) else rng:NextNumber(1.1, 1.7)
			local tilt = if i == 1 then rng:NextNumber(0, 0.15) else rng:NextNumber(0.25, 0.55)
			local cframe = CFrame.new(at)
				* CFrame.Angles(0, math.pi / 2 - angle, 0)
				* CFrame.Angles(tilt, 0, 0)
				* CFrame.new(0, len * 0.32, 0)
				* CFrame.Angles(0, rng:NextNumber(0, 1.5), 0)
			local partMat = if mutationId ~= "none" then mat elseif i == 1 then M.Neon else M.Glass
			part = piece(bag, BLOCK, Vector3.new(len * 0.42, len, len * 0.42), cframe, color, partMat)
			if partMat == M.Glass then
				part.Transparency = 0.1
				part.Reflectance = 0.3
			end
		else
			-- Chunky nuggets, half buried at random angles.
			local size = if i == 1 then rng:NextNumber(1.25, 1.65) else rng:NextNumber(0.7, 1.15)
			local cframe = CFrame.new(at + Vector3.new(0, size * 0.18, 0))
				* CFrame.Angles(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), rng:NextNumber(0, TAU))
			part = piece(bag, BLOCK, Vector3.one * size, cframe, color, mat)
			if mat == M.Metal then
				part.Reflectance = 0.18
			end
		end
		first = first or part
	end
	-- Flecks across the whole face so the block reads as ore at a glance.
	for _ = 1, 5 do
		local size = rng:NextNumber(0.4, 0.75)
		local cframe = CFrame.new(base + Vector3.new(rng:NextNumber(-3.2, 3.2), 0.03, rng:NextNumber(-3.2, 3.2)))
			* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		piece(bag, BLOCK, Vector3.new(size, 0.08, size * rng:NextNumber(0.6, 1)), cframe, color, mat)
	end
	if first then
		local rare = ore.rarity >= 3
		if rare or mutationId ~= "none" then
			local brightness = if mutationId == "molten" then 2.6 elseif rare then 1.6 else 1
			glow(bag, first, color, brightness, 11)
			emitter(bag, first, false, color:Lerp(WHITE, 0.4), if rare then 5 else 3)
		end
		if mutationId == "molten" then
			emitter(bag, first, true, LAVA, 8)
		end
	end
end

--- A half-buried golden chalice with a glowing gem.
local function relicDecor(bag: Bag, rng: Random, base: Vector3)
	local x, z = rng:NextNumber(-1.4, 1.4), rng:NextNumber(-1.4, 1.4)
	local root = CFrame.new(base + Vector3.new(x, 0, z)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0) * CFrame.Angles(rng:NextNumber(0.12, 0.3), 0, 0)
	local foot = piece(bag, CYLINDER, Vector3.new(0.3, 1.7, 1.7), root * CFrame.new(0, 0.1, 0) * UPRIGHT, GOLD, M.Metal)
	piece(bag, CYLINDER, Vector3.new(0.7, 0.5, 0.5), root * CFrame.new(0, 0.55, 0) * UPRIGHT, GOLD, M.Metal)
	local cup = piece(bag, BLOCK, Vector3.new(1.7, 1.25, 1.7), root * CFrame.new(0, 1.4, 0), GOLD, M.Metal)
	round(bag, cup)
	piece(bag, CYLINDER, Vector3.new(0.22, 1.75, 1.75), root * CFrame.new(0, 2, 0) * UPRIGHT, GOLD:Lerp(WHITE, 0.25), M.Metal)
	piece(bag, BALL, Vector3.one * 0.5, root * CFrame.new(0, 1.4, -0.82), RELIC_GEM, M.Neon)
	foot.Reflectance = 0.25
	cup.Reflectance = 0.25
	glow(bag, cup, GOLD, 2.2, 12)
	emitter(bag, cup, false, GOLD, 6)
end

--- The last block: a gold-ringed seal with lava glowing through its cracks.
local function sealDecor(bag: Bag, rng: Random, base: Vector3)
	local at = CFrame.new(base)
	local ring = piece(bag, CYLINDER, Vector3.new(0.2, 6.8, 6.8), at * CFrame.new(0, 0.1, 0) * UPRIGHT, SEAL_RING, M.Metal)
	ring.Reflectance = 0.2
	piece(bag, CYLINDER, Vector3.new(0.26, 5.7, 5.7), at * CFrame.new(0, 0.13, 0) * UPRIGHT, Color3.fromHex("24120C"), M.Basalt)
	local glyph = piece(bag, CYLINDER, Vector3.new(0.32, 2.3, 2.3), at * CFrame.new(0, 0.16, 0) * UPRIGHT, LAVA, M.Neon)
	for i = 1, 6 do
		local angle = (i - 1) / 6 * TAU + rng:NextNumber(-0.25, 0.25)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local cframe = CFrame.fromMatrix(base + Vector3.new(0, 0.27, 0) + dir * 2, dir, Vector3.yAxis)
		piece(bag, BLOCK, Vector3.new(1.7, 0.1, rng:NextNumber(0.16, 0.26)), cframe, LAVA, M.Neon)
	end
	for i = 1, 4 do
		local angle = (i - 0.5) / 4 * TAU + rng:NextNumber(-0.2, 0.2)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		piece(bag, BLOCK, Vector3.new(1.3, 0.08, 0.2), CFrame.fromMatrix(base + Vector3.new(0, 0.03, 0) + dir * 4, dir, Vector3.yAxis), LAVA, M.Neon)
	end
	glow(bag, glyph, LAVA, 3, 18)
	emitter(bag, glyph, true, LAVA, 10)
end

local function plainDecor(bag: Bag, rng: Random, base: Vector3, style: Style)
	for _ = 1, math.floor(rng:NextNumber() * 3) do
		local size = rng:NextNumber(0.4, 0.7)
		local pos = base + Vector3.new(rng:NextNumber(-3, 3), size * 0.1, rng:NextNumber(-3, 3))
		piece(bag, BALL, Vector3.one * size, CFrame.new(pos), tone(style.pebble, rng, 0.08), M.Slate)
	end
end

local function decorateBlock(view: BlockView)
	view.decorated = true
	local index = view.index
	local base = ShaftRenderer.blockCFrame(index).Position + Vector3.new(0, H / 2, 0)
	local rng = Random.new(Hash.u32(seed, index, SALT_DECO))
	if index >= GameConfig.CoreDepth then
		sealDecor(view.bag, rng, base)
		return
	end
	local roll = ShaftRenderer.rollAt(index)
	if roll.oreId then
		oreCluster(view.bag, rng, base, roll)
	end
	if roll.relic then
		relicDecor(view.bag, rng, base)
	end
	if not roll.oreId and not roll.relic then
		plainDecor(view.bag, rng, base, styleAt(index - 1, Hash.unit(seed, index, SALT_MIX)))
	end
end

local function acquireBlock(index: number): BlockView
	local view = table.remove(freeBlocks) or newBlock()
	view.index = index
	if index >= GameConfig.CoreDepth then
		view.color = SEAL_ROCK
		applySurface(view, nil, SEAL_ROCK)
	else
		-- Top faces share the strata of the walls beside them.
		local k = index - 1
		local style = styleAt(k, Hash.unit(seed, index, SALT_MIX))
		view.color = shade(style.ground:Lerp(style.bands[bandOf(style, k)], 0.3), index)
		applySurface(view, style, view.color)
	end
	view.part.CFrame = ShaftRenderer.blockCFrame(index)
	view.part.Parent = folder
	blockByIndex[index] = view
	return view
end

local function releaseBlock(index: number)
	local view = blockByIndex[index]
	if view then
		if view.decorated then
			view.decorated = false
			releaseBag(view.bag)
		end
		view.part.Parent = nil
		blockByIndex[index] = nil
		table.insert(freeBlocks, view)
	end
end

-- Dig cracks ----------------------------------------------------------------------

local crackParts: { Part } = {}
for _ = 1, CRACKS do
	table.insert(crackParts, newDecorPart())
end
local crackIndex = 0 -- block the current crack layout belongs to
local cracksShown = 0

local function hideCracks()
	crackIndex = 0
	cracksShown = 0
	for _, part in crackParts do
		part.Parent = nil
	end
end

local function layoutCracks(index: number)
	crackIndex = index
	local view = blockByIndex[index]
	local base = ShaftRenderer.blockCFrame(index).Position + Vector3.new(0, H / 2 + 0.04, 0)
	local rng = Random.new(Hash.u32(seed, index, SALT_CRACK))
	local style = styleAt(index - 1, Hash.unit(seed, index, SALT_MIX))
	local hot = index >= GameConfig.CoreDepth or style.lava ~= nil
	local color = if hot then LAVA else (if view then view.color else style.ground):Lerp(BLACK, 0.7)
	local origin = base + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	local spin = rng:NextNumber(0, TAU)
	for i, part in crackParts do
		local angle = spin + (i - 1) / CRACKS * TAU + rng:NextNumber(-0.3, 0.3)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local len = rng:NextNumber(1.5, 2.6)
		local mid = origin + dir * (0.3 + len / 2)
		mid = Vector3.new(math.clamp(mid.X, base.X - 3.2, base.X + 3.2), mid.Y, math.clamp(mid.Z, base.Z - 3.2, base.Z + 3.2))
		part.Shape = BLOCK
		part.Size = Vector3.new(len, 0.1, rng:NextNumber(0.14, 0.22))
		part.CFrame = CFrame.fromMatrix(mid, dir, Vector3.yAxis)
		part.Color = color
		part.Material = if hot then M.Neon else M.SmoothPlastic
	end
end

--- Cracks spread across the block being dug as `progress` goes 0 -> 1.
function ShaftRenderer.setDigProgress(progress: number)
	local index = depth + 1
	local want = 0
	if progress > 0.06 and blockByIndex[index] then
		want = math.min(CRACKS, 1 + math.floor(progress * CRACKS))
	end
	if want > 0 and crackIndex ~= index then
		layoutCracks(index)
	end
	if want == cracksShown then
		return
	end
	cracksShown = want
	for i, part in crackParts do
		part.Parent = if i <= want then folder else nil
	end
end

-- Core ----------------------------------------------------------------------------

local coreModel: Model? = nil
local coreSpark: Part? = nil
local coreLight: PointLight? = nil
local corePulse: RBXScriptConnection? = nil

local function corePart(name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, mat: Enum.Material, parent: Instance): Part
	local part = newDecorPart()
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = mat
	part.Parent = parent
	return part
end

local function ensureCore(): Model
	if coreModel then
		return coreModel
	end
	local model = Instance.new("Model")
	model.Name = "Core"
	local floorCFrame = ShaftRenderer.blockCFrame(GameConfig.CoreDepth + 1)
	-- The only collidable core part: a glass floor over the molten heart.
	local floor = Instance.new("Part")
	floor.Name = "CoreFloor"
	floor.Anchored = true
	floor.Size = Vector3.new(G.BlockSize, H, G.BlockSize)
	floor.CFrame = floorCFrame
	floor.Material = M.Glass
	floor.Color = Color3.fromHex("FFB061")
	floor.Transparency = 0.35
	floor.Reflectance = 0.1
	floor.CastShadow = false
	floor.TopSurface = Enum.SurfaceType.Smooth
	floor.BottomSurface = Enum.SurfaceType.Smooth
	floor.Parent = model

	local heartCFrame = floorCFrame * CFrame.new(0, -H / 2 - 3, 0)
	local shell = corePart("CoreShell", BALL, Vector3.one * 6.8, heartCFrame, Color3.fromHex("FFD27A"), M.Glass, model)
	shell.Transparency = 0.55
	local heart = corePart("CoreHeart", BALL, Vector3.one * 5.6, heartCFrame, Color3.fromHex("FF7A1A"), M.Neon, model)
	local spark = corePart("CoreSpark", BALL, Vector3.one * 3.4, heartCFrame, Color3.fromHex("FFF3B0"), M.Neon, model)
	corePart("CoreLava", BLOCK, Vector3.new(G.BlockSize, 0.6, G.BlockSize), floorCFrame * CFrame.new(0, -H / 2 - 7, 0), Color3.fromHex("FF5A12"), M.Neon, model)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("FF8A3D")
	light.Brightness = 4
	light.Range = 40
	light.Shadows = false
	light.Parent = heart

	local embers = Instance.new("ParticleEmitter")
	embers.Texture = AssetIds.Particles.Ember
	embers.Rate = 18
	embers.Lifetime = NumberRange.new(1.2, 2.2)
	embers.Speed = NumberRange.new(3, 6)
	embers.SpreadAngle = Vector2.new(20, 20)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Acceleration = Vector3.new(0, 2, 0)
	embers.Size = NumberSequence.new(0.5, 0)
	embers.Transparency = FADE
	embers.Color = ColorSequence.new(Color3.fromHex("FFE38A"), Color3.fromHex("FF5A12"))
	embers.LightEmission = 1
	embers.Parent = floor

	-- Light pillars rising out of the core (and through the seal above it).
	for i = 1, 3 do
		local angle = i * TAU / 3
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(math.cos(angle) * 1.8, H / 2, math.sin(angle) * 1.8)
		a0.Parent = floor
		local a1 = Instance.new("Attachment")
		a1.Position = a0.Position + Vector3.new(0, 18, 0)
		a1.Parent = floor
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = 2.2
		beam.Width1 = 0.4
		beam.FaceCamera = true
		beam.Segments = 1
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(Color3.fromHex("FF8A3D"), Color3.fromHex("FFE38A"))
		beam.Transparency = NumberSequence.new(0.45, 1)
		beam.Parent = floor
	end

	coreModel = model
	coreSpark = spark
	coreLight = light
	return model
end

local function setCoreVisible(visible: boolean)
	if visible then
		ensureCore().Parent = folder
		if not corePulse then
			corePulse = RunService.Heartbeat:Connect(function()
				local pulse = 0.5 + 0.5 * math.sin(os.clock() * 2.6)
				if coreSpark then
					coreSpark.Size = Vector3.one * (3.1 + pulse * 0.7)
				end
				if coreLight then
					coreLight.Brightness = 3.4 + pulse * 1.8
				end
			end)
		end
	else
		if coreModel then
			coreModel.Parent = nil
		end
		if corePulse then
			corePulse:Disconnect()
			corePulse = nil
		end
	end
end

-- Window --------------------------------------------------------------------------

local function refresh()
	if not centerKnown then
		return -- nothing to render until the plot is assigned
	end
	hideCracks()
	local lo = depth + 1
	local hi = math.min(depth + G.VisibleBlocksBelow, GameConfig.CoreDepth)
	for index in blockByIndex do
		if index < lo or index > hi then
			releaseBlock(index)
		end
	end
	for index = lo, hi do
		local view = blockByIndex[index] or acquireBlock(index)
		local visible = index < lo + DECO_BLOCKS
		if visible and not view.decorated then
			decorateBlock(view)
		elseif not visible and view.decorated then
			view.decorated = false
			releaseBag(view.bag)
		end
	end

	local chunk = depth // G.WallChunkBlocks
	local lastChunk = GameConfig.CoreDepth // G.WallChunkBlocks
	local cLo = math.max(0, chunk - G.WallChunksAround)
	local cHi = math.min(lastChunk, chunk + G.WallChunksAround)
	for c in wallByChunk do
		if c < cLo or c > cHi then
			releaseWalls(c)
		end
	end
	for c = cLo, cHi do
		if not wallByChunk[c] then
			acquireWalls(c)
		end
	end

	setCoreVisible(hi >= GameConfig.CoreDepth - 2)
end

local function releaseAll()
	for index in blockByIndex do
		releaseBlock(index)
	end
	for c in wallByChunk do
		releaseWalls(c)
	end
end

function ShaftRenderer.depth(): number
	return depth
end

function ShaftRenderer.setDepth(newDepth: number)
	if newDepth ~= depth then
		depth = newDepth
		refresh()
	end
end

--- Prediction: hide the block being dug right now.
function ShaftRenderer.removeBlock(index: number)
	if index == depth + 1 then
		ShaftRenderer.setDepth(index)
	end
end

function ShaftRenderer.reset(newSeed: number, newDepth: number)
	seed = newSeed
	table.clear(rollCache)
	releaseAll()
	depth = newDepth
	refresh()
end

function ShaftRenderer.setCenter(newCenter: Vector3)
	center = newCenter
	centerKnown = true
	releaseAll()
	setCoreVisible(false)
	if coreModel then
		coreModel:Destroy()
		coreModel = nil
		coreSpark = nil
		coreLight = nil
	end
	refresh()
end

--- The server's cap keeps strangers out; locally it must not block the owner.
function ShaftRenderer.hideCap(plot: Model)
	local cap = plot:FindFirstChild("ShaftCap")
	if cap and cap:IsA("BasePart") then
		cap.Transparency = 1
		cap.CanCollide = false
	end
end

function ShaftRenderer.init()
	for _ = 1, G.VisibleBlocksBelow + 2 do
		table.insert(freeBlocks, newBlock())
	end
	for _ = 1, G.WallChunksAround * 2 + 1 do
		table.insert(freeWalls, newWallChunk())
	end
end

return ShaftRenderer
