--!strict
-- Explorer: ReplicatedStorage/Shared/Economy (ModuleScript)
-- Pure economy maths used by the server (authority), the client (prediction
-- and UI) and the sim. Nothing here touches Roblox APIs.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Layers = require(script.Parent.Layers)

local Economy = {}

local oreById: { [string]: typeof(GameConfig.Ores[1]) } = {}
for _, ore in GameConfig.Ores do
	oreById[ore.id] = ore
end

local mutationById: { [string]: typeof(GameConfig.Mutations[1]) } = {}
for _, mutation in GameConfig.Mutations do
	mutationById[mutation.id] = mutation
end

Economy.oreById = oreById
Economy.mutationById = mutationById

export type PowerInputs = {
	drillTier: number,
	metaDigLevel: number,
	megaActive: boolean,
	catchUp: number, -- 0..MaxBonus
}

function Economy.drillPower(inputs: PowerInputs): number
	local tier = GameConfig.Drills[math.clamp(inputs.drillTier, 1, #GameConfig.Drills)]
	local power = tier.power
	power *= 1 + GameConfig.Meta.DigSpeed.perLevel * inputs.metaDigLevel
	if inputs.megaActive then
		power *= GameConfig.Round.MegaDrill.PowerMult
	end
	power *= 1 + inputs.catchUp
	return power
end

function Economy.digTime(blockIndex: number, power: number): number
	return Layers.hardnessAt(blockIndex) / power
end

--- Minimum wall-clock gap the server accepts between two consecutive digs.
function Economy.minInterval(blockIndex: number, power: number): number
	return Economy.digTime(blockIndex, power) + GameConfig.Dig.DropTime
end

function Economy.oreValue(oreId: string, mutationId: string?): number
	local ore = oreById[oreId]
	if not ore then
		return 0
	end
	local mutation = mutationById[mutationId or "none"]
	return ore.value * (if mutation then mutation.mult else 1)
end

function Economy.packCapacity(packTier: number, metaPackLevel: number): number
	local tier = GameConfig.Packs[math.clamp(packTier, 1, #GameConfig.Packs)]
	return tier.capacity + GameConfig.Meta.Pack.perLevel * metaPackLevel
end

--- Cost to go from `currentTier` to the next one, or nil at the cap.
function Economy.upgradeCost(kind: "drill" | "pack", currentTier: number): number?
	local list = if kind == "drill" then GameConfig.Drills else GameConfig.Packs
	local nextTier = list[currentTier + 1]
	return if nextTier then nextTier.cost else nil
end

function Economy.travelTime(depth: number): number
	local t = GameConfig.Travel
	return math.min(t.Max, t.Base + t.PerMetre * depth)
end

--- Catch-up bonus (0..MaxBonus) for a player `gap` metres behind the leader.
function Economy.catchUpBonus(gap: number): number
	local c = GameConfig.Round.CatchUp
	local fullGap = GameConfig.CoreDepth * c.FullGapFraction
	return c.MaxBonus * math.clamp(gap / fullGap, 0, 1)
end

function Economy.metaCost(kind: "digSpeed" | "pack", currentLevel: number): number?
	local def = if kind == "digSpeed" then GameConfig.Meta.DigSpeed else GameConfig.Meta.Pack
	if currentLevel >= def.maxLevel then
		return nil
	end
	return def.costs[currentLevel + 1]
end

function Economy.collectionReward(oreId: string, thresholdIndex: number): number
	local ore = oreById[oreId]
	local base = GameConfig.Collection.Rewards[thresholdIndex]
	if not ore or not base then
		return 0
	end
	return base * ore.rarity
end

return Economy
