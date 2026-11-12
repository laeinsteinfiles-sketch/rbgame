--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/ShaftRenderer (ModuleScript)
-- Renders only this player's shaft, only around the player, only from pools.
-- The whole 1050 m column is never instantiated: a window of blocks below the
-- player plus three wall chunks is all that exists at any time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local SALT_SHADE = 53

type Deco = {
	main: Part,
	small: Part,
	light: PointLight,
	emitter: ParticleEmitter,
}

type BlockView = {
	part: Part,
	textures: { Texture },
	deco: Deco?,
	index: number,
}

type WallChunk = { parts: { Part }, chunk: number }

local folder = Instance.new("Folder")
folder.Name = "LocalShaft"
folder.Parent = Workspace

local center: Vector3 = Vector3.zero
local centerKnown = false
local seed = 0
local depth = 0

local freeBlocks: { BlockView } = {}
local blockByIndex: { [number]: BlockView } = {}
local freeDecos: { Deco } = {}
local freeWalls: { WallChunk } = {}
local wallByChunk: { [number]: WallChunk } = {}
local rollCache: { [number]: Types.BlockRoll } = {}
local coreModel: Model? = nil

local function material(name: string): Enum.Material
	local found = (Enum.Material :: any)[name]
	return if found then found else Enum.Material.Slate
end

local function shade(color: Color3, index: number): Color3
	-- ±5% value jitter so a column of identical blocks still reads as rock.
	local t = (Hash.unit(seed, index, SALT_SHADE) - 0.5) * 0.1
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + t, 0, 1))
end

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

-- Pools -------------------------------------------------------------------------

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
	return { part = part, textures = textures, deco = nil, index = 0 }
end

local function newDeco(): Deco
	local main = Instance.new("Part")
	main.Name = "Ore"
	main.Anchored = true
	main.CanCollide = false
	main.CanQuery = false
	main.CastShadow = false
	main.Size = Vector3.new(2.4, 1.6, 2.4)
	local small = main:Clone()
	small.Size = Vector3.new(1.4, 1, 1.4)
	local light = Instance.new("PointLight")
	light.Range = 10
	light.Brightness = 0
	light.Parent = main
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = AssetIds.Particles.Sparkle
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(1, 2)
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.LightEmission = 1
	emitter.Parent = main
	return { main = main, small = small, light = light, emitter = emitter }
end

local function newWallChunk(): WallChunk
	local parts = {}
	for _ = 1, 4 do
		local part = Instance.new("Part")
		part.Name = "Wall"
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CastShadow = false
		table.insert(parts, part)
	end
	return { parts = parts, chunk = -1 }
end

-- Configuration ----------------------------------------------------------------

local function applyLayerSurface(part: Part, textures: { Texture }?, layer: Types.LayerDef, color: Color3)
	part.Material = material(layer.material)
	part.Color = color
	local slots = (AssetIds.Textures :: { [string]: any })[layer.id]
	local variant = if slots and typeof(slots.MaterialVariant) == "string" then slots.MaterialVariant else ""
	part.MaterialVariant = variant
	if textures and slots then
		for i, texture in textures do
			local id = if i == 1 then slots.Top else slots.Side
			texture.Texture = AssetIds.image(if typeof(id) == "number" then id else 0)
			texture.Color3 = color
		end
	end
end

local function showDeco(view: BlockView, roll: Types.BlockRoll)
	local deco = table.remove(freeDecos) or newDeco()
	view.deco = deco
	local cf = ShaftRenderer.blockCFrame(view.index)
	local top = cf.Position.Y + H / 2
	local spin = Hash.unit(seed, view.index, 71) * math.pi
	local emitterRate = 0
	local lightBrightness = 0
	local lightColor = Color3.new(1, 1, 1)

	if roll.relic then
		deco.main.Size = Vector3.new(3, 0.6, 2)
		deco.main.Material = Enum.Material.Neon
		deco.main.Color = Color3.fromHex("F2B33D")
		deco.main.CFrame = CFrame.new(cf.Position.X, top + 0.3, cf.Position.Z) * CFrame.Angles(0, spin, 0)
		deco.small.Size = Vector3.new(1.2, 0.9, 1.2)
		deco.small.Material = Enum.Material.Slate
		deco.small.Color = Color3.fromHex("6E5A40")
		deco.small.CFrame = CFrame.new(cf.Position.X + 1.6, top + 0.45, cf.Position.Z - 1.4) * CFrame.Angles(0, spin + 0.7, 0)
		lightBrightness = 1.5
		lightColor = deco.main.Color
		emitterRate = 3
	else
		local ore = Economy.oreById[roll.oreId or ""]
		local mutation = Economy.mutationById[roll.mutationId or "none"]
		local color = Color3.fromHex(if ore then ore.color else "FFFFFF")
		local mat = material(if ore then ore.material else "Slate")
		if mutation and mutation.id ~= "none" then
			-- Mutations glow; plain ore stays matte so the rare ones read instantly.
			mat = if mutation.id == "flawless" then Enum.Material.Glass else Enum.Material.Neon
			color = color:Lerp(Color3.fromHex(mutation.color), 0.45)
			lightBrightness = if mutation.id == "flawless" then 0.6 else 2
			lightColor = color
			emitterRate = if mutation.id == "molten" then 8 else 3
		end
		deco.main.Size = Vector3.new(2.4, 1.6, 2.4)
		deco.main.Material = mat
		deco.main.Color = color
		deco.main.CFrame = CFrame.new(cf.Position.X - 0.6, top + 0.5, cf.Position.Z + 0.4) * CFrame.Angles(0.3, spin, 0.2)
		deco.small.Size = Vector3.new(1.4, 1, 1.4)
		deco.small.Material = mat
		deco.small.Color = color
		deco.small.CFrame = CFrame.new(cf.Position.X + 1.7, top + 0.3, cf.Position.Z - 1.5) * CFrame.Angles(0.2, spin + 1.1, -0.2)
	end

	deco.light.Brightness = lightBrightness
	deco.light.Color = lightColor
	deco.emitter.Rate = emitterRate
	deco.emitter.Color = ColorSequence.new(lightColor)
	deco.main.Parent = folder
	deco.small.Parent = folder
end

local function hideDeco(view: BlockView)
	local deco = view.deco
	if deco then
		deco.main.Parent = nil
		deco.small.Parent = nil
		deco.emitter.Rate = 0
		view.deco = nil
		table.insert(freeDecos, deco)
	end
end

local function acquireBlock(index: number)
	local view = table.remove(freeBlocks) or newBlock()
	view.index = index
	local layer = Layers.layerAt(index - 1)
	local isCore = index >= GameConfig.CoreDepth
	local color = if isCore then Color3.fromHex("3A2A1E") else shade(Color3.fromHex(layer.groundColor), index)
	applyLayerSurface(view.part, view.textures, layer, color)
	if isCore then
		view.part.Material = Enum.Material.Basalt
	end
	view.part.CFrame = ShaftRenderer.blockCFrame(index)
	view.part.Parent = folder
	blockByIndex[index] = view
	local roll = ShaftRenderer.rollAt(index)
	if roll.oreId or roll.relic then
		showDeco(view, roll)
	end
end

local function releaseBlock(index: number)
	local view = blockByIndex[index]
	if view then
		hideDeco(view)
		view.part.Parent = nil
		blockByIndex[index] = nil
		table.insert(freeBlocks, view)
	end
end

local function acquireWalls(chunk: number)
	local wall = table.remove(freeWalls) or newWallChunk()
	wall.chunk = chunk
	local blocks = G.WallChunkBlocks
	local height = blocks * H
	local top = G.SurfaceY - chunk * blocks * H
	local midY = top - height / 2
	local layer = Layers.layerAt(chunk * blocks + blocks / 2)
	local color = Color3.fromHex(layer.wallColor)
	local half = G.BlockSize / 2 + 1
	local defs = {
		{ Vector3.new(G.BlockSize + 4, height, 2), Vector3.new(0, midY, -half) },
		{ Vector3.new(G.BlockSize + 4, height, 2), Vector3.new(0, midY, half) },
		{ Vector3.new(2, height, G.BlockSize), Vector3.new(-half, midY, 0) },
		{ Vector3.new(2, height, G.BlockSize), Vector3.new(half, midY, 0) },
	}
	for i, part in wall.parts do
		part.Size = defs[i][1]
		part.CFrame = CFrame.new(center + defs[i][2])
		applyLayerSurface(part, nil, layer, color)
		part.Parent = folder
	end
	wallByChunk[chunk] = wall
end

local function releaseWalls(chunk: number)
	local wall = wallByChunk[chunk]
	if wall then
		for _, part in wall.parts do
			part.Parent = nil
		end
		wallByChunk[chunk] = nil
		table.insert(freeWalls, wall)
	end
end

local function ensureCore(): Model
	if coreModel then
		return coreModel
	end
	local model = Instance.new("Model")
	model.Name = "Core"
	local floor = Instance.new("Part")
	floor.Name = "CoreFloor"
	floor.Anchored = true
	floor.Size = Vector3.new(G.BlockSize, H, G.BlockSize)
	floor.Material = Enum.Material.Basalt
	floor.Color = Color3.fromHex("2E2320")
	floor.CFrame = ShaftRenderer.blockCFrame(GameConfig.CoreDepth + 1)
	floor.Parent = model
	local heart = Instance.new("Part")
	heart.Name = "CoreHeart"
	heart.Shape = Enum.PartType.Ball
	heart.Anchored = true
	heart.CanCollide = false
	heart.Size = Vector3.new(5, 5, 5)
	heart.Material = Enum.Material.Neon
	heart.Color = Color3.fromHex("F2B33D")
	heart.CFrame = floor.CFrame * CFrame.new(0, H / 2 - 1.5, 0)
	heart.Parent = model
	local light = Instance.new("PointLight")
	light.Color = heart.Color
	light.Brightness = 3
	light.Range = 30
	light.Parent = heart
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = AssetIds.Particles.Ember
	emitter.Rate = 12
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.Size = NumberSequence.new(0.6, 0)
	emitter.Color = ColorSequence.new(heart.Color)
	emitter.LightEmission = 1
	emitter.Parent = heart
	coreModel = model
	return model
end

-- Window -------------------------------------------------------------------------

local function refresh()
	if not centerKnown then
		return -- nothing to render until the plot is assigned
	end
	local lo = depth + 1
	local hi = math.min(depth + G.VisibleBlocksBelow, GameConfig.CoreDepth)
	for index in blockByIndex do
		if index < lo or index > hi then
			releaseBlock(index)
		end
	end
	for index = lo, hi do
		if not blockByIndex[index] then
			acquireBlock(index)
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

	local core = ensureCore()
	core.Parent = if hi >= GameConfig.CoreDepth - 2 then folder else nil
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
	for index in blockByIndex do
		releaseBlock(index)
	end
	for c in wallByChunk do
		releaseWalls(c)
	end
	depth = newDepth
	refresh()
end

function ShaftRenderer.setCenter(newCenter: Vector3)
	center = newCenter
	centerKnown = true
	for index in blockByIndex do
		releaseBlock(index)
	end
	for c in wallByChunk do
		releaseWalls(c)
	end
	if coreModel then
		coreModel:Destroy()
		coreModel = nil
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
