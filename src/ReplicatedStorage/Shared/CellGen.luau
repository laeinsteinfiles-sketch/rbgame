--!strict
-- Explorer: ReplicatedStorage/Shared/CellGen (ModuleScript)
-- What is inside every cell of a player's mine, derived from
-- (roundSeed, col, row) only. The server rolls exactly what the client drew,
-- so no cell data is ever sent over the network.
--
-- Priority per cell: core row > cave pocket > special (chest, TNT, gem,
-- relic) > ore (veined) > hard rock > plain rock.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Grid = require(script.Parent.Grid)
local Hash = require(script.Parent.Hash)
local Layers = require(script.Parent.Layers)
local Types = require(script.Parent.Types)

type Cell = Types.Cell

local CellGen = {}

local S = GameConfig.Specials
local CORE = GameConfig.CoreDepth

local SALT_SPECIAL = 11
local SALT_ORE = 13
local SALT_ORE_TYPE = 17
local SALT_MUTATION = 23
local SALT_VEIN = 29
local SALT_VEIN_TYPE = 31
local SALT_HARD = 43
local SALT_CAVE = 53

local function pickWeighted(ores: { Types.OreWeight }, roll: number): string
	local total = 0
	for _, entry in ores do
		total += entry.weight
	end
	local target = roll * total
	local acc = 0
	for _, entry in ores do
		acc += entry.weight
		if target < acc then
			return entry.id
		end
	end
	return ores[#ores].id
end

local function pickMutation(roll: number): string
	local acc = 0
	for _, mutation in GameConfig.Mutations do
		acc += mutation.chance
		if roll < acc then
			return mutation.id
		end
	end
	return "none"
end

--- True when the cell starts open: inside one of the elliptical cave pockets
--- seeded per region (each cell checks its own and the 8 surrounding regions).
function CellGen.isCave(seed: number, col: number, row: number): boolean
	if row < S.CaveMinDepth or row >= CORE - 2 then
		return false
	end
	local rc, rr = S.CaveRegionCols, S.CaveRegionRows
	local rx0, ry0 = (col - 1) // rc, (row - 1) // rr
	for ry = ry0 - 1, ry0 + 1 do
		for rx = rx0 - 1, rx0 + 1 do
			if ry >= 0 and rx >= 0 and rx * rc < Grid.COLS then
				local regionKey = ry * 16 + rx
				local layer = Layers.ofRow(ry * rr + 1)
				if Hash.unit(seed, regionKey, SALT_CAVE) < layer.caveChance then
					local cx = rx * rc + 1 + Hash.unit(seed, regionKey, SALT_CAVE + 1) * (rc - 1)
					local cy = ry * rr + 1 + Hash.unit(seed, regionKey, SALT_CAVE + 2) * (rr - 1)
					local ax = 1.1 + Hash.unit(seed, regionKey, SALT_CAVE + 3) * 1.7
					local ay = 0.8 + Hash.unit(seed, regionKey, SALT_CAVE + 4) * 1.2
					local dx, dy = (col - cx) / ax, (row - cy) / ay
					if dx * dx + dy * dy <= 1 then
						return true
					end
				end
			end
		end
	end
	return false
end

local function oreAt(seed: number, col: number, row: number, layer: Types.LayerDef, idx: number): string?
	local regionKey = ((row - 1) // S.VeinRegionRows) * 16 + (col - 1) // S.VeinRegionCols
	local rich = Hash.unit(seed, regionKey, SALT_VEIN) < S.RichRegionChance
	local chance = if rich then layer.richChance else layer.poorChance
	if Hash.unit(seed, idx, SALT_ORE) >= chance then
		return nil
	end
	-- Rich regions are one ore type (a visible vein); poor ones are mixed.
	local typeRoll = if rich then Hash.unit(seed, regionKey, SALT_VEIN_TYPE) else Hash.unit(seed, idx, SALT_ORE_TYPE)
	return pickWeighted(layer.ores, typeRoll)
end

function CellGen.at(seed: number, col: number, row: number): Cell
	if row >= CORE then
		return { kind = "core", hardness = GameConfig.CoreHardness }
	end
	if CellGen.isCave(seed, col, row) then
		return { kind = "cave", hardness = 0 }
	end
	local hardness = Layers.hardnessAt(row)
	local layer = Layers.ofRow(row)
	local idx = Grid.key(col, row)

	local special = Hash.unit(seed, idx, SALT_SPECIAL)
	local acc = 0
	if row >= S.Chest.minDepth then
		acc += S.Chest.chance
		if special < acc then
			return { kind = "chest", hardness = hardness }
		end
	end
	if row >= S.Tnt.minDepth then
		acc += S.Tnt.chance
		if special < acc then
			return { kind = "tnt", hardness = hardness * 0.5 }
		end
	end
	if row >= S.Gem.minDepth then
		acc += S.Gem.chance
		if special < acc then
			return { kind = "gem", hardness = hardness }
		end
	end
	if row >= S.Relic.minDepth then
		acc += S.Relic.chance
		if special < acc then
			return { kind = "relic", hardness = hardness }
		end
	end

	local oreId = oreAt(seed, col, row, layer, idx)
	if oreId then
		return {
			kind = "ore",
			oreId = oreId,
			mutationId = pickMutation(Hash.unit(seed, idx, SALT_MUTATION)),
			hardness = hardness,
		}
	end
	if row >= S.Hard.minDepth and Hash.unit(seed, idx, SALT_HARD) < S.Hard.chance then
		return { kind = "hard", hardness = hardness * S.Hard.mult }
	end
	return { kind = "dirt", hardness = hardness }
end

--- Cells a TNT blast at (col, row) would open, excluding the core row and
--- out-of-bounds cells. The caller filters already-open ones.
function CellGen.blastArea(col: number, row: number): { { number } }
	local out = {}
	local r = S.Tnt.radius
	for dr = -r, r do
		for dc = -r, r do
			local c, rw = col + dc, row + dr
			if (dc ~= 0 or dr ~= 0) and Grid.inBounds(c, rw) and rw < CORE then
				table.insert(out, { c, rw })
			end
		end
	end
	return out
end

--- Cash inside a treasure chest at `row`.
function CellGen.chestCash(row: number): number
	return math.floor(S.Chest.cashBase + S.Chest.cashPerMetre * row)
end

return CellGen
