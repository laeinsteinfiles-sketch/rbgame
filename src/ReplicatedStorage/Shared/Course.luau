--!strict
-- Explorer: ReplicatedStorage/Shared/Course (ModuleScript)
-- The race course: which blocks are free-fall pockets, blast charges or
-- treasure chests. Derived from the round's course seed only, so every
-- player races the exact same shaft; loot stays per player (OreGen).
-- Server and client both call resolve() and must agree block for block.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Hash = require(script.Parent.Hash)
local Layers = require(script.Parent.Layers)

export type Kind = "solid" | "pocket" | "blast" | "chest" | "core"
export type Broken = { index: number, kind: Kind }
export type Resolution = { broken: { Broken }, finalDepth: number }

local Course = {}

local C = GameConfig.Course
local CORE = GameConfig.CoreDepth
local SALT_POCKET = 61
local SALT_POCKET_LEN = 67
local SALT_BLAST = 73

function Course.isChest(index: number): boolean
	return index % C.ChestEvery == 0 and index < CORE
end

function Course.isBlast(seed: number, index: number): boolean
	if index < C.BlastMinDepth or index >= CORE or Course.isChest(index) then
		return false
	end
	return Hash.unit(seed, index, SALT_BLAST) < Layers.layerAt(index - 1).blastChance
end

-- Length of the pocket run that starts at `start`, 0 if none. Runs stop
-- short of chests and blast charges so those always stay diggable blocks.
local function pocketRun(seed: number, start: number): number
	if start < C.MinPocketDepth or start >= CORE then
		return 0
	end
	if Hash.unit(seed, start, SALT_POCKET) >= Layers.layerAt(start - 1).pocketChance then
		return 0
	end
	local span = C.PocketLength.max - C.PocketLength.min + 1
	local length = C.PocketLength.min + Hash.u32(seed, start, SALT_POCKET_LEN) % span
	for k = 0, length - 1 do
		local i = start + k
		if i >= CORE or Course.isChest(i) or Course.isBlast(seed, i) then
			return k
		end
	end
	return length
end

function Course.isPocket(seed: number, index: number): boolean
	for start = math.max(1, index - C.PocketLength.max + 1), index do
		local run = pocketRun(seed, start)
		if run > 0 and start + run - 1 >= index then
			return true
		end
	end
	return false
end

function Course.kind(seed: number, index: number): Kind
	if index >= CORE then
		return "core"
	elseif Course.isChest(index) then
		return "chest"
	elseif Course.isBlast(seed, index) then
		return "blast"
	elseif Course.isPocket(seed, index) then
		return "pocket"
	end
	return "solid"
end

--- Everything that breaks when block `index` is dug, in order, and the depth
--- the player ends at. Blasts clear BlastDepth blocks (no chain reactions);
--- any pocket run directly below is fallen through for free.
function Course.resolve(seed: number, index: number): Resolution
	local first = Course.kind(seed, index)
	local broken: { Broken } = { { index = index, kind = first } :: Broken }
	local nextIndex = index + 1
	if first == "blast" then
		for k = 1, C.BlastDepth do
			local j = index + k
			if j >= CORE then
				break
			end
			table.insert(broken, { index = j, kind = Course.kind(seed, j) } :: Broken)
			nextIndex = j + 1
		end
	end
	while nextIndex < CORE and Course.kind(seed, nextIndex) == "pocket" do
		table.insert(broken, { index = nextIndex, kind = "pocket" } :: Broken)
		nextIndex += 1
	end
	return { broken = broken, finalDepth = nextIndex - 1 }
end

function Course.chestCash(index: number): number
	return math.floor(C.ChestCashBase + C.ChestCashPerMetre * index)
end

return Course
