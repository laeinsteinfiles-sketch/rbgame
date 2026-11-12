--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/MineRenderer (ModuleScript)
-- Draws only this player's mine, only around the player, mostly from pools.
-- The 500-row cross-section is never instantiated: a window of rows around
-- the character (solid cells, ore decorations, the back wall, the border
-- rock and an invisible front wall that keeps the character in the slab) is
-- all that exists at any time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local CellGen = require(ReplicatedStorage.Shared.CellGen)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Hash = require(ReplicatedStorage.Shared.Hash)
local Layers = require(ReplicatedStorage.Shared.Layers)
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
local Types = require(ReplicatedStorage.Shared.Types)

local MineRenderer = {}

local G = GameConfig.Geometry
local CELL = G.Cell
local COLS = Grid.COLS
local CORE = GameConfig.CoreDepth
local FRONT = CELL / 2
local MINE_HALF = Grid.halfWidth()
local BORDER_W = G.BorderColumns * CELL
local SALT_SHADE = 61

type CellView = {
	part: Part,
	grass: Part?,
	deco: Instance?,
	key: number,
}

type RowView = {
	back: Part,
	left: Part?,
	right: Part?,
}

local folder = Instance.new("Folder")
folder.Name = "LocalMine"
folder.Parent = Workspace

local origin = Vector3.zero
local originKnown = false
local seed = 0
local focusRow = 0
local lo, hi = 1, 0

local open: { [number]: boolean } = {}
local cellCache: { [number]: Types.Cell } = {}
local views: { [number]: CellView } = {}
local freeParts: { Part } = {}
local rows: { [number]: RowView } = {}
local frontWall: Part
local coreModel: Model? = nil

-- Helpers ----------------------------------------------------------------------

local function material(name: string): Enum.Material
	local found = (Enum.Material :: any)[name]
	return if found then found else Enum.Material.Slate
end

local function shade(color: Color3, key: number, amount: number): Color3
	local t = (Hash.unit(seed, key, SALT_SHADE) - 0.5) * amount
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + t, 0, 1))
end

local function darken(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v * (1 - amount), 0, 1))
end

function MineRenderer.cellAt(col: number, row: number): Types.Cell
	local key = Grid.key(col, row)
	local cell = cellCache[key]
	if not cell then
		cell = CellGen.at(seed, col, row)
		cellCache[key] = cell
	end
	return cell
end

--- Dug, predicted, or a cave pocket. Row 0 (the surface) is open.
function MineRenderer.isOpen(col: number, row: number): boolean
	if row <= 0 then
		return true
	end
	if col < 1 or col > COLS or row > CORE then
		return false
	end
	if open[Grid.key(col, row)] then
		return true
	end
	return MineRenderer.cellAt(col, row).kind == "cave"
end

function MineRenderer.cellPosition(col: number, row: number): Vector3
	local x, y = Grid.cellOffset(col, row)
	return origin + Vector3.new(x, y, 0)
end

function MineRenderer.frontPosition(col: number, row: number): Vector3
	return MineRenderer.cellPosition(col, row) + Vector3.new(0, 0, FRONT)
end

function MineRenderer.origin(): Vector3
	return origin
end

function MineRenderer.ready(): boolean
	return originKnown and seed ~= 0
end

function MineRenderer.seed(): number
	return seed
end

function MineRenderer.partAt(col: number, row: number): Part?
	local view = views[Grid.key(col, row)]
	return if view then view.part else nil
end

-- Decorations ------------------------------------------------------------------

local function nugget(parent: Instance, position: Vector3, size: Vector3, color: Color3, mat: Enum.Material, spin: number)
	local p = ModelKit.part(parent, "Nugget", size, CFrame.new(position) * CFrame.Angles(spin * 0.7, spin, spin * 0.4), color, nil, "ellipsoid")
	p.Material = mat
	p.CastShadow = false
end

local function buildDeco(cell: Types.Cell, key: number, center: Vector3): Instance?
	local face = center + Vector3.new(0, 0, FRONT)
	local kind = cell.kind
	if kind == "ore" then
		local ore = Economy.oreById[cell.oreId or ""]
		if not ore then
			return nil
		end
		local mutation = Economy.mutationById[cell.mutationId or "none"]
		local color = Color3.fromHex(ore.color)
		local glow = false
		if mutation and mutation.id ~= "none" then
			color = color:Lerp(Color3.fromHex(mutation.color), 0.45)
			glow = true
		end
		local m = Instance.new("Model")
		m.Name = "Ore"
		if ore.material == "Glass" then
			-- Gems grow as crystal spikes reaching out of the face.
			local cluster = ModelKit.crystalCluster(color:ToHex(), 3.2, key % 997 + 1, glow or ore.rarity >= 4)
			cluster:PivotTo(CFrame.new(face + Vector3.new(0, -0.6, -0.4)) * CFrame.Angles(math.rad(62), 0, 0))
			cluster.Parent = m
		else
			local mat = if glow then Enum.Material.Neon else material(ore.material)
			local count = 3 + key % 3
			for i = 1, count do
				local spin = Hash.unit(seed, key, 70 + i) * math.pi
				local offset = Vector3.new((Hash.unit(seed, key, 80 + i) - 0.5) * 3.6, (Hash.unit(seed, key, 90 + i) - 0.5) * 3.6, 0)
				local s = 1.1 + Hash.unit(seed, key, 100 + i) * 0.9
				nugget(m, face + offset, Vector3.new(s * 1.2, s, s * 0.9), color, mat, spin)
			end
			if ore.id == "gold" or glow then
				local l = Instance.new("PointLight")
				l.Color = color
				l.Range = if glow then 12 else 7
				l.Brightness = if glow then 1.6 else 0.6
				l.Parent = m:FindFirstChildWhichIsA("BasePart")
			end
		end
		if glow then
			local first = m:FindFirstChildWhichIsA("BasePart", true)
			if first then
				local sparkle = Instance.new("ParticleEmitter")
				sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				sparkle.Color = ColorSequence.new(color)
				sparkle.Size = NumberSequence.new(0.4, 0)
				sparkle.Lifetime = NumberRange.new(0.6, 1.2)
				sparkle.Rate = if cell.mutationId == "molten" then 10 else 4
				sparkle.Speed = NumberRange.new(0.5, 1.5)
				sparkle.SpreadAngle = Vector2.new(60, 60)
				sparkle.LightEmission = 1
				sparkle.Parent = first
			end
		end
		return m
	elseif kind == "chest" then
		local chest = ModelKit.chest()
		chest:PivotTo(CFrame.new(face + Vector3.new(0, -1.2, 0.2)))
		return chest
	elseif kind == "gem" then
		local cluster = ModelKit.crystalCluster("3FF2D6", 3.6, key % 997 + 7, true)
		cluster:PivotTo(CFrame.new(face + Vector3.new(0, -0.8, -0.3)) * CFrame.Angles(math.rad(58), 0, 0))
		return cluster
	elseif kind == "relic" then
		local relic = ModelKit.relic()
		relic:PivotTo(CFrame.new(face + Vector3.new(0, 0, 0.3)))
		return relic
	elseif kind == "tnt" then
		local m = Instance.new("Model")
		m.Name = "Tnt"
		local band = ModelKit.part(m, "Band", Vector3.new(CELL + 0.06, 2, CELL + 0.06), CFrame.new(center), "F4F1EA", "SmoothPlastic")
		ModelKit.label(band, Enum.NormalId.Back, "TNT", Color3.fromHex("C0392B"), nil)
		local fuse = ModelKit.part(m, "Fuse", Vector3.new(0.3, 1.4, 0.3), CFrame.new(center + Vector3.new(0, CELL / 2 + 0.5, FRONT - 1)), "2B2B2B", "SmoothPlastic")
		local spark = Instance.new("ParticleEmitter")
		spark.Texture = "rbxasset://textures/particles/fire_sparks_main.dds"
		spark.Color = ColorSequence.new(Color3.fromHex("FFD27A"))
		spark.Size = NumberSequence.new(0.3, 0)
		spark.Lifetime = NumberRange.new(0.2, 0.4)
		spark.Rate = 18
		spark.Speed = NumberRange.new(2, 4)
		spark.LightEmission = 1
		spark.EmissionDirection = Enum.NormalId.Top
		spark.Parent = fuse
		return m
	end
	return nil
end

-- Pools ------------------------------------------------------------------------

local function newPart(name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanTouch = false
	p.CanQuery = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function takePart(): Part
	local p = table.remove(freeParts)
	if p then
		return p
	end
	return newPart("Cell")
end

local function acquireCell(col: number, row: number)
	local key = Grid.key(col, row)
	local cell = MineRenderer.cellAt(col, row)
	local layer = Layers.ofRow(row)
	local center = MineRenderer.cellPosition(col, row)
	local part = takePart()
	part.Name = "Cell"
	part.CanCollide = true
	part:SetAttribute("Col", col)
	part:SetAttribute("Row", row)

	local color: Color3
	local mat: Enum.Material
	if cell.kind == "core" then
		color, mat = Color3.fromHex("FF6A1F"), Enum.Material.CrackedLava
	elseif cell.kind == "hard" then
		color, mat = shade(Color3.fromHex(layer.hardColor), key, 0.08), material(layer.hardMaterial)
	elseif cell.kind == "tnt" then
		color, mat = Color3.fromHex("C0392B"), Enum.Material.SmoothPlastic
	else
		color, mat = shade(Color3.fromHex(layer.color), key, 0.12), material(layer.material)
	end
	part.Color = color
	part.Material = mat

	local grass: Part? = nil
	if row == 1 then
		-- The top row wears the island's grass so the mine mouth reads as ground.
		part.Size = Vector3.new(CELL, CELL - 0.8, CELL)
		part.CFrame = CFrame.new(center - Vector3.new(0, 0.4, 0))
		grass = takePart()
		local g = grass :: Part
		g.Name = "Grass"
		g.Size = Vector3.new(CELL, 0.8, CELL)
		g.CFrame = CFrame.new(center + Vector3.new(0, CELL / 2 - 0.4, 0))
		g.Color = Color3.fromHex("5DBB4C")
		g.Material = Enum.Material.Grass
		g.CanCollide = true
		g.Parent = folder
	else
		part.Size = Vector3.new(CELL, CELL, CELL)
		part.CFrame = CFrame.new(center)
	end
	part.Parent = folder

	local deco = buildDeco(cell, key, center)
	if deco then
		deco.Parent = folder
	end
	views[key] = { part = part, grass = grass, deco = deco, key = key }
end

local function releaseCell(key: number)
	local view = views[key]
	if not view then
		return
	end
	views[key] = nil
	view.part.Parent = nil
	for _, child in view.part:GetChildren() do
		child:Destroy()
	end
	table.insert(freeParts, view.part)
	local grass = view.grass
	if grass then
		grass.Parent = nil
		table.insert(freeParts, grass)
	end
	if view.deco then
		view.deco:Destroy()
	end
end

local function acquireRow(row: number)
	local layer = Layers.ofRow(row)
	local y = select(2, Grid.cellOffset(1, row))
	local back = takePart()
	back.Name = "Back"
	back.CanCollide = true
	back.Size = Vector3.new(MINE_HALF * 2, CELL, 0.5)
	back.CFrame = CFrame.new(origin + Vector3.new(0, y, -FRONT + 0.15))
	back.Color = Color3.fromHex(if row >= CORE then "3A1208" else layer.backColor)
	back.Material = material(layer.material)
	back.Parent = folder
	local view: RowView = { back = back }
	-- The island itself covers the borders of its top rows.
	if row > G.IslandRows then
		local borderColor = darken(Color3.fromHex(layer.color), 0.18)
		for _, side in { -1, 1 } do
			local border = takePart()
			border.Name = "Border"
			border.CanCollide = true
			border.Size = Vector3.new(BORDER_W, CELL, CELL)
			border.CFrame = CFrame.new(origin + Vector3.new(side * (MINE_HALF + BORDER_W / 2), y, 0))
			border.Color = shade(borderColor, row * 2 + (side + 1) / 2, 0.06)
			border.Material = material(layer.material)
			border.Parent = folder
			if side < 0 then
				view.left = border
			else
				view.right = border
			end
		end
	end
	rows[row] = view
end

local function releaseRow(row: number)
	local view = rows[row]
	if not view then
		return
	end
	rows[row] = nil
	for _, part in { view.back, view.left, view.right } do
		if part then
			part.Parent = nil
			table.insert(freeParts, part)
		end
	end
end

local function ensureCore(): Model
	if coreModel then
		return coreModel
	end
	local m = Instance.new("Model")
	m.Name = "Core"
	local floorY = select(2, Grid.cellOffset(1, CORE)) - CELL / 2
	local floor = ModelKit.part(m, "CoreFloor", Vector3.new(MINE_HALF * 2, 2, CELL), CFrame.new(origin + Vector3.new(0, floorY - 1, 0)), "FF8A1F", "Neon")
	floor.CanCollide = true
	local heart = ModelKit.part(m, "Heart", Vector3.one * 60, CFrame.new(origin + Vector3.new(0, floorY - 34, -6)), "FF7A1A", "Neon", "ball")
	heart.CastShadow = false
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromHex("FF9A3D")
	glow.Range = 60
	glow.Brightness = 3
	glow.Parent = floor
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/fire_main.dds"
	embers.Color = ColorSequence.new(Color3.fromHex("FFD27A"), Color3.fromHex("FF5A1F"))
	embers.Size = NumberSequence.new(1.2, 0)
	embers.Lifetime = NumberRange.new(1, 2)
	embers.Rate = 30
	embers.Speed = NumberRange.new(4, 9)
	embers.SpreadAngle = Vector2.new(40, 40)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.LightEmission = 1
	embers.Parent = floor
	coreModel = m
	return m
end

-- Window -----------------------------------------------------------------------

local function refresh()
	if not MineRenderer.ready() then
		return
	end
	local newLo = math.max(1, focusRow - G.RenderRowsAbove)
	local newHi = math.min(CORE, math.max(focusRow, 0) + G.RenderRowsBelow)
	for key in views do
		local col, row = Grid.unkey(key)
		if row < newLo or row > newHi or MineRenderer.isOpen(col, row) then
			releaseCell(key)
		end
	end
	for row in rows do
		if row < newLo or row > newHi then
			releaseRow(row)
		end
	end
	for row = newLo, newHi do
		if not rows[row] then
			acquireRow(row)
		end
		for col = 1, COLS do
			if not views[Grid.key(col, row)] and not MineRenderer.isOpen(col, row) then
				acquireCell(col, row)
			end
		end
	end
	lo, hi = newLo, newHi

	-- The invisible front wall keeps the character inside the slab.
	local topY = select(2, Grid.cellOffset(1, newLo)) + CELL / 2
	local bottomY = select(2, Grid.cellOffset(1, newHi)) - CELL / 2
	frontWall.Size = Vector3.new(MINE_HALF * 2 + BORDER_W * 2, topY - bottomY, 1)
	frontWall.CFrame = CFrame.new(origin + Vector3.new(0, (topY + bottomY) / 2, FRONT + 0.5))
	frontWall.Parent = folder

	local core = ensureCore()
	core.Parent = if newHi >= CORE - 1 then folder else nil
end

function MineRenderer.setFocus(row: number)
	if row ~= focusRow then
		focusRow = row
		refresh()
	end
end

function MineRenderer.window(): (number, number)
	return lo, hi
end

--- Prediction: the cell is gone locally. Returns the cell that was there.
function MineRenderer.openCell(col: number, row: number): Types.Cell
	local key = Grid.key(col, row)
	open[key] = true
	releaseCell(key)
	return MineRenderer.cellAt(col, row)
end

--- Rollback: the server said no, so the cell comes back.
function MineRenderer.closeCell(col: number, row: number)
	local key = Grid.key(col, row)
	if not open[key] then
		return
	end
	open[key] = nil
	if row >= lo and row <= hi and not views[key] and not MineRenderer.isOpen(col, row) then
		acquireCell(col, row)
	end
end

local function clearAll()
	for key in views do
		releaseCell(key)
	end
	for row in rows do
		releaseRow(row)
	end
	if coreModel then
		coreModel:Destroy()
		coreModel = nil
	end
end

--- New round or a full resync from the server.
function MineRenderer.reset(newSeed: number, openKeys: { number })
	clearAll()
	if newSeed ~= seed then
		table.clear(cellCache)
	end
	seed = newSeed
	table.clear(open)
	for _, key in openKeys do
		open[key] = true
	end
	refresh()
end

function MineRenderer.setOrigin(newOrigin: Vector3)
	clearAll()
	origin = newOrigin
	originKnown = true
	refresh()
end

function MineRenderer.init()
	frontWall = newPart("FrontWall")
	frontWall.Transparency = 1
	frontWall.CanCollide = true
	frontWall.CanQuery = false
	frontWall.CastShadow = false
	for _ = 1, (COLS + 3) * (G.RenderRowsAbove + G.RenderRowsBelow + 1) do
		table.insert(freeParts, newPart("Cell"))
	end
end

return MineRenderer
