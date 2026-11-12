--!strict
-- Explorer: ReplicatedStorage/Shared/OreGen (ModuleScript)
-- What is inside block `index` of a player's shaft, derived from
-- (playerSeed, blockIndex) only. The server rolls the same thing the client
-- rendered, so no block data is ever sent.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Hash = require(script.Parent.Hash)
local Layers = require(script.Parent.Layers)
local Types = require(script.Parent.Types)

local OreGen = {}

local SALT_ORE = 11
local SALT_MUTATION = 23
local SALT_RELIC = 37

local function pickOre(layer: Types.LayerDef, roll: number): string?
	local total = 0
	for _, entry in layer.ores do
		total += entry.weight
	end
	local target = roll * total
	local acc = 0
	for _, entry in layer.ores do
		acc += entry.weight
		if target < acc then
			return if entry.id == "" then nil else entry.id
		end
	end
	return nil
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

function OreGen.roll(seed: number, index: number): Types.BlockRoll
	if index >= GameConfig.CoreDepth then
		return { oreId = nil, mutationId = nil, relic = false }
	end
	local layer = Layers.layerAt(index - 1)
	local oreId = pickOre(layer, Hash.unit(seed, index, SALT_ORE))
	local mutationId: string? = nil
	if oreId then
		mutationId = pickMutation(Hash.unit(seed, index, SALT_MUTATION))
	end
	local relic = index >= GameConfig.Relic.MinDepth
		and Hash.unit(seed, index, SALT_RELIC) < GameConfig.Relic.Chance
	return { oreId = oreId, mutationId = mutationId, relic = relic }
end

return OreGen
