--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/ShaftRenderer (ModuleScript)
-- Renders only this player's shaft, only around the player, mostly from
-- pools. The whole 1,100 m column never exists: a window of blocks below the
-- player and three wall chunks are all there is. Only the top blocks get ore
-- models, because the shaft camera can't see past the block underfoot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Palette = require(ReplicatedStorage.Config.Palette)
local Course = require(ReplicatedStorage.Shared.Course)
local Hash = require(ReplicatedStorage.Shared.Hash)
local Layers = require(ReplicatedStorage.Shared.Layers)
local Kit = require(ReplicatedStorage.Shared.Models.ModelKit)
local OreGen = require(ReplicatedStorage.Shared.OreGen)
local OreModels = require(ReplicatedStorage.Shared.Models.OreModels)
local Props = require(ReplicatedStorage.Shared.Models.Props)
local Types = require(ReplicatedStorage.Shared.Types)

local ShaftRenderer = {}

local G = GameConfig.Geometry
local H = G.BlockHeight
local HALF = G.BlockSize / 2
local SALT_SHADE = 53
local SALT_CRACK = 59
local CORE = GameConfig.CoreDepth

type BlockView = { part: Part, textures: { Texture }, index: number, base: Color3 }
type WallChunk = { parts: { Part }, decor: Model?, chunk: number }

local folder = Instance.new("Folder")
folder.Name = "LocalShaft"
folder.Parent = Workspace

local frame: CFrame? = nil
local courseSeed = 1
local lootSeed = 1
local depth = 0

local freeBlocks: { BlockView } = {}
local blockByIndex: { [number]: BlockView } = {}
local decoByIndex: { [number]: Model } = {}
local caveByIndex: { [number]: Model } = {}
local freeWalls: { WallChunk } = {}
local wallByChunk: { [number]: WallChunk } = {}
local rollCache: { [number]: Types.BlockRoll } = {}
local kindCache: { [number]: string } = {}
local coreModel: Model? = nil

local damageIndex = 0
local damageStage = 0
local cracks: { Part } = {}

local function material(name: string): Enum.Material
	local found = (Enum.Material :: any)[name]
	return if found then found else Enum.Material.Slate
end

--- Island-local CFrame -> world.
local function world(local_: CFrame): CFrame
	return (frame or CFrame.new()) * local_
end

function ShaftRenderer.blockCFrame(index: number): CFrame
	return world(CFrame.new(0, G.SurfaceY - (index - 1) * H - H / 2, 0))
end

--- Top centre of block `index`, where ore clusters and chests sit.
function ShaftRenderer.topCFrame(index: number): CFrame
	return world(CFrame.new(0, G.SurfaceY - (index - 1) * H, 0))
end

function ShaftRenderer.rollAt(index: number): Types.BlockRoll
	local cached = rollCache[index]
	if not cached then
		cached = OreGen.roll(lootSeed, index)
		rollCache[index] = cached
	end
	return cached
end

function ShaftRenderer.kindAt(index: number): string
	local cached = kindCache[index]
	if cached then
		return cached
	end
	local kind = Course.kind(courseSeed, index)
	kindCache[index] = kind
	return kind
end

function ShaftRenderer.seeds(): (number, number)
	return courseSeed, lootSeed
end

function ShaftRenderer.groundColor(index: number): Color3
	return Color3.fromHex(Layers.layerAt(index - 1).groundColor)
end

local function shade(color: Color3, index: number): Color3
	-- ±5% value jitter so a column of identical blocks still reads as rock.
	local t = (Hash.unit(lootSeed, index, SALT_SHADE) - 0.5) * 0.1
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + t, 0, 1))
end

local function applyLayerSurface(part: Part, textures: { Texture }?, layer: Types.LayerDef, color: Color3)
	part.Material = material(layer.material)
	part.Color = color
	local slots = (AssetIds.Textures :: { [string]: any })[layer.id]
	part.MaterialVariant = if slots and typeof(slots.MaterialVariant) == "string" then slots.MaterialVariant else ""
	if textures and slots then
		for i, texture in textures do
			local id = if i == 1 then slots.Top else slots.Side
			texture.Texture = AssetIds.image(if typeof(id) == "number" then id else 0)
			texture.Color3 = color
		end
	end
end

-- Blocks --------------------------------------------------------------------

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
		texture.Parent = part
		table.insert(textures, texture)
	end
	return { part = part, textures = textures, index = 0, base = Color3.new() }
end

local function acquireBlock(index: number)
	local view = table.remove(freeBlocks) or newBlock()
	view.index = index
	local layer = Layers.layerAt(index - 1)
	local kind = ShaftRenderer.kindAt(index)
	local color = shade(Color3.fromHex(layer.groundColor), index)
	if kind == "core" then
		color = Color3.fromHex("3A2A1E")
	elseif kind == "blast" then
		-- Scorched block: the charge on top is the real tell, this is the echo.
		color = color:Lerp(Color3.fromHex("5A2A22"), 0.45)
	end
	view.base = color
	applyLayerSurface(view.part, view.textures, layer, color)
	if kind == "core" then
		view.part.Material = Enum.Material.Basalt
	end
	view.part.CFrame = ShaftRenderer.blockCFrame(index)
	view.part.Parent = folder
	blockByIndex[index] = view
end

local function releaseBlock(index: number)
	local view = blockByIndex[index]
	if view then
		view.part.Parent = nil
		blockByIndex[index] = nil
		table.insert(freeBlocks, view)
	end
end

-- Decorations on the visible top blocks ----------------------------------------

local function buildDeco(index: number): Model?
	local kind = ShaftRenderer.kindAt(index)
	local roll = ShaftRenderer.rollAt(index)
	local top = ShaftRenderer.topCFrame(index)
	-- Corner placement keeps the middle clear for the character and drill.
	local corner = Hash.u32(lootSeed, index, 81) % 4
	local cx = if corner < 2 then -2.4 else 2.4
	local cz = if corner % 2 == 0 then -2.4 else 2.4
	local spin = CFrame.Angles(0, Hash.unit(lootSeed, index, 83) * math.pi * 2, 0)
	local model: Model? = nil
	if kind == "chest" then
		model = OreModels.chest()
	elseif kind == "blast" then
		model = OreModels.charge()
	elseif roll.relic then
		model = OreModels.relic(index)
	elseif roll.oreId then
		model = OreModels.cluster(roll.oreId, roll.mutationId, index)
	end
	if not model then
		return nil
	end
	local placed: Model = model
	placed.Name = `Deco{index}`
	placed:PivotTo(top * CFrame.new(cx, 0, cz) * spin)
	for _, d in placed:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	placed.Parent = folder
	return placed
end

function ShaftRenderer.decoFor(index: number): Model?
	return decoByIndex[index]
end

--- Detaches the deco model so an effect can animate it; the renderer
--- forgets it and the caller destroys it.
function ShaftRenderer.takeDeco(index: number): Model?
	local deco = decoByIndex[index]
	decoByIndex[index] = nil
	return deco
end

-- A pocket reads as a cave: hanging spikes and a couple of glowing caps.
local function buildCave(index: number): Model
	local m = Kit.model(`Cave{index}`)
	local top = ShaftRenderer.topCFrame(index)
	local wall = Color3.fromHex(Layers.layerAt(index - 1).wallColor)
	for k = 0, 1 do
		local a = Hash.unit(courseSeed, index, 91 + k) * math.pi * 2
		local p = top * CFrame.new(math.cos(a) * 2.6, 0, math.sin(a) * 2.6)
		Props.spike(m, p.Position, 0.9, 1.8 + k * 0.7, Kit.shade(wall, -0.15), Enum.Material.Slate)
	end
	local side = if Hash.u32(courseSeed, index, 97) % 2 == 0 then -1 else 1
	local cap = Kit.ellipsoid(m, Vector3.new(0.9, 0.35, 0.9), top * CFrame.new(side * (HALF - 0.4), -2.2, 1.2), "8FD3C7", {
		material = Enum.Material.Neon,
		shadow = false,
	})
	Kit.light(cap, "8FD3C7", 0.8, 9)
	Kit.cylY(m, 0.6, 0.2, top * CFrame.new(side * (HALF - 0.4), -2.6, 1.2), "C9C2B4")
	m.Parent = folder
	return m
end

-- Walls ------------------------------------------------------------------------

local function newWallChunk(): WallChunk
	local parts = {}
	for _ = 1, 4 do
		local part = Instance.new("Part")
		part.Name = "Wall"
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		-- Walls shade the shaft so lanterns and glowing ore carry the light.
		part.CastShadow = true
		table.insert(parts, part)
	end
	return { parts = parts, decor = nil, chunk = -1 }
end

local DECOR: { [string]: (m: Model, at: CFrame, height: number, chunk: number) -> () } = {
	topsoil = function(m, at, height, chunk)
		-- Timber mine supports: corner posts and two rings of beams.
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				Kit.block(m, Vector3.new(0.7, height, 0.7), at * CFrame.new(sx * (HALF - 0.35), 0, sz * (HALF - 0.35)), Palette.woodDark, {
					material = Enum.Material.Wood,
				})
			end
		end
		for _, y in { height * 0.25, -height * 0.25 } do
			for k = 0, 3 do
				local cf = at * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, y, -(HALF - 0.3))
				Kit.block(m, Vector3.new(G.BlockSize, 0.6, 0.6), cf, Palette.wood, { material = Enum.Material.Wood })
			end
		end
		local lantern = Props.lantern(m, at * CFrame.Angles(0, (chunk % 4) * math.pi / 2, 0) * CFrame.new(HALF - 0.9, height * 0.25 - 0.9, -(HALF - 0.9)))
		lantern.Name = "LanternGlow"
	end,
	bedrock = function(m, at, height, chunk)
		for k = 0, 3 do
			local cf = at * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, height * 0.2, -(HALF - 0.2))
			Kit.block(m, Vector3.new(G.BlockSize, 0.45, 0.35), cf, Palette.metalDark, { material = Enum.Material.Metal })
			for _, x in { -2.8, 2.8 } do
				Kit.cylZ(m, 0.2, 0.25, cf * CFrame.new(x, 0, 0.2), Palette.metalLight, { material = Enum.Material.Metal, shadow = false })
			end
		end
		local corner = at * CFrame.Angles(0, (chunk % 4) * math.pi / 2, 0) * CFrame.new(HALF - 0.45, 0, HALF - 0.45)
		Kit.cylY(m, height, 0.5, corner, Palette.metal, { material = Enum.Material.Metal })
		local lantern = Props.lantern(m, at * CFrame.Angles(0, (chunk % 4) * math.pi / 2, 0) * CFrame.new(-(HALF - 0.9), height * 0.2 - 0.9, -(HALF - 0.9)))
		lantern.Name = "LanternGlow"
		lantern.Color = Color3.fromHex("DDEBFF")
		local light = lantern:FindFirstChildOfClass("PointLight")
		if light then
			light.Color = Color3.fromHex("DDEBFF")
		end
	end,
	hollows = function(m, at, height, chunk)
		-- Pale crystal outcrops: the deep layer's own light source.
		for k = 0, 2 do
			local face = (chunk + k) % 4
			local y = (Hash.unit(chunk, k, 7) - 0.5) * height * 0.7
			local base = at * CFrame.Angles(0, face * math.pi / 2, 0) * CFrame.new((k - 1) * 2.2, y, -HALF)
			for c = 0, 2 do
				local tilt = CFrame.Angles(math.pi / 2 - 0.5 + c * 0.25, 0, (c - 1) * 0.4)
				Kit.crystal(m, 0.35, 0.6 + c * 0.25, 0.5, base * tilt, "B9C7E8", { material = Enum.Material.Glass, transparency = 0.15, shadow = false })
			end
			local glow = Kit.block(m, Vector3.new(0.3, 0.3, 0.3), base * CFrame.new(0, 0, 0.4), "B9C7E8", { material = Enum.Material.Neon, shadow = false })
			Kit.light(glow, "B9C7E8", 0.9, 12)
		end
	end,
}

local function stratumBands(m: Model, at: CFrame, height: number, chunk: number, accent: Color3)
	for k = 0, 1 do
		local y = (Hash.unit(chunk, k, 3) - 0.5) * height * 0.8
		for side = 0, 3 do
			local cf = at * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, y, -(HALF + 0.05))
			Kit.block(m, Vector3.new(G.BlockSize + 0.2, 0.35 + k * 0.2, 0.2), cf, accent, { shadow = false })
		end
	end
end

local function acquireWalls(chunk: number)
	local wall = table.remove(freeWalls) or newWallChunk()
	wall.chunk = chunk
	local blocks = G.WallChunkBlocks
	local height = blocks * H
	local midY = G.SurfaceY - chunk * height - height / 2
	local layer = Layers.layerAt(chunk * blocks + blocks / 2)
	local color = Color3.fromHex(layer.wallColor)
	local defs = {
		{ Vector3.new(G.BlockSize + 4, height, 2), Vector3.new(0, midY, -(HALF + 1)) },
		{ Vector3.new(G.BlockSize + 4, height, 2), Vector3.new(0, midY, HALF + 1) },
		{ Vector3.new(2, height, G.BlockSize), Vector3.new(-(HALF + 1), midY, 0) },
		{ Vector3.new(2, height, G.BlockSize), Vector3.new(HALF + 1, midY, 0) },
	}
	for i, part in wall.parts do
		part.Size = defs[i][1]
		part.CFrame = world(CFrame.new(defs[i][2]))
		applyLayerSurface(part, nil, layer, color)
		part.Parent = folder
	end
	local decor = Kit.model(`Chunk{chunk}`)
	local at = world(CFrame.new(0, midY, 0))
	stratumBands(decor, at, height, chunk, Color3.fromHex(layer.accentColor):Lerp(color, 0.4))
	local build = DECOR[layer.id]
	if build then
		build(decor, at, height, chunk)
	end
	decor.Parent = folder
	wall.decor = decor
	wallByChunk[chunk] = wall
end

local function releaseWalls(chunk: number)
	local wall = wallByChunk[chunk]
	if wall then
		for _, part in wall.parts do
			part.Parent = nil
		end
		if wall.decor then
			wall.decor:Destroy()
			wall.decor = nil
		end
		wallByChunk[chunk] = nil
		table.insert(freeWalls, wall)
	end
end

local function ensureCore(): Model
	if coreModel then
		return coreModel
	end
	local m = Kit.model("Core")
	local floor = ShaftRenderer.blockCFrame(CORE + 1)
	Kit.block(m, Vector3.new(G.BlockSize, H, G.BlockSize), floor, "2E2320", { material = Enum.Material.Basalt })
	local heartCf = floor * CFrame.new(0, H / 2 - 1, 0)
	local heart = Kit.ball(m, 4.5, heartCf, Palette.amber, { material = Enum.Material.Neon, name = "CoreHeart", shadow = false })
	Kit.ball(m, 5.6, heartCf, Palette.amber, { material = Enum.Material.Glass, transparency = 0.6, shadow = false })
	for _, p in Kit.ring(m, 3.2, 14, 0.3, 0.3, heartCf * CFrame.Angles(0.4, 0, 0), Palette.amberDark, { material = Enum.Material.Metal }) do
		p:SetAttribute("OrbRing", 1)
	end
	Kit.light(heart, Palette.amber, 3, 30)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = AssetIds.Particles.Ember
	emitter.Rate = 14
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Color = ColorSequence.new(Color3.fromHex(Palette.amber))
	emitter.LightEmission = 1
	emitter.Parent = heart
	coreModel = m
	return m
end

-- Damage on the block being dug -------------------------------------------------

local function clearCracks()
	for _, crack in cracks do
		crack:Destroy()
	end
	table.clear(cracks)
	damageStage = 0
end

--- Visual damage on block depth+1 for progress 0..1: tint, shake, cracks.
function ShaftRenderer.setDamage(progress: number)
	local index = depth + 1
	local view = blockByIndex[index]
	if index ~= damageIndex then
		clearCracks()
		damageIndex = index
	end
	if not view then
		return
	end
	local p = math.clamp(progress, 0, 1)
	view.part.Color = view.base:Lerp(Color3.new(0, 0, 0), p * 0.3)
	local amp = 0.07 * p
	local jitter = Vector3.new((math.random() - 0.5) * amp, 0, (math.random() - 0.5) * amp)
	view.part.CFrame = ShaftRenderer.blockCFrame(index) + jitter
	local stage = math.floor(p * 4)
	while damageStage < math.min(stage, 3) do
		damageStage += 1
		-- Each stage adds two crack lines radiating from the dig point.
		for k = 1, 2 do
			local a = Hash.unit(lootSeed, index * 7 + damageStage, SALT_CRACK + k) * math.pi * 2
			local length = 1.6 + damageStage * 0.9
			local top = ShaftRenderer.topCFrame(index)
			local crack = Kit.block(folder, Vector3.new(0.16, 0.06, length), top * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.03, -length / 2), "1A1410", {
				transparency = 0.15,
				shadow = false,
				name = "Crack",
			})
			table.insert(cracks, crack)
		end
	end
	if p <= 0 and damageStage > 0 then
		clearCracks()
	end
end

-- Window -------------------------------------------------------------------------

local function refresh()
	if not frame then
		return -- nothing to render until the plot is assigned
	end
	local lo = depth + 1
	local hi = math.min(depth + G.VisibleBlocksBelow, CORE)
	for index in blockByIndex do
		if index < lo or index > hi then
			releaseBlock(index)
		end
	end
	for index, deco in decoByIndex do
		if index < lo or index >= lo + G.DecoratedBlocks then
			deco:Destroy()
			decoByIndex[index] = nil
		end
	end
	for index, cave in caveByIndex do
		if index < lo or index > hi then
			cave:Destroy()
			caveByIndex[index] = nil
		end
	end
	for index = lo, hi do
		local kind = ShaftRenderer.kindAt(index)
		if kind == "pocket" then
			if not caveByIndex[index] and ShaftRenderer.kindAt(index - 1) ~= "pocket" then
				caveByIndex[index] = buildCave(index)
			end
		elseif not blockByIndex[index] then
			acquireBlock(index)
		end
		if index < lo + G.DecoratedBlocks and kind ~= "pocket" and not decoByIndex[index] then
			local deco = buildDeco(index)
			if deco then
				decoByIndex[index] = deco
			end
		end
	end

	local chunk = depth // G.WallChunkBlocks
	local lastChunk = CORE // G.WallChunkBlocks
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

	local core = ensureCore()
	core.Parent = if hi >= CORE - 2 then folder else nil
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

local function clearAll()
	for index in blockByIndex do
		releaseBlock(index)
	end
	for index, deco in decoByIndex do
		deco:Destroy()
		decoByIndex[index] = nil
	end
	for index, cave in caveByIndex do
		cave:Destroy()
		caveByIndex[index] = nil
	end
	for c in wallByChunk do
		releaseWalls(c)
	end
	clearCracks()
end

function ShaftRenderer.reset(newCourseSeed: number, newLootSeed: number, newDepth: number)
	courseSeed = newCourseSeed
	lootSeed = newLootSeed
	table.clear(rollCache)
	table.clear(kindCache)
	clearAll()
	depth = newDepth
	refresh()
end

function ShaftRenderer.setFrame(newFrame: CFrame)
	frame = newFrame
	clearAll()
	if coreModel then
		coreModel:Destroy()
		coreModel = nil
	end
	refresh()
end

--- The server's hatch keeps strangers out; locally it must not block the owner.
function ShaftRenderer.hideCap(plot: Model)
	local cap = plot:FindFirstChild("ShaftCap")
	if cap then
		for _, d in cap:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
				d.CanCollide = false
			end
		end
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
