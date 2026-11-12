--!strict
-- Explorer: ReplicatedStorage/Shared/Economy (ModuleScript)
-- Pure economy maths used by the server (authority), the client (prediction
-- and UI) and the sim. Nothing here touches Roblox APIs.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

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
	pickaxeTier: number,
	metaDigLevel: number,
	megaActive: boolean,
	catchUp: number, -- 0..MaxBonus
}

export type UpgradeKind = "pickaxe" | "pack"

function Economy.digPower(inputs: PowerInputs): number
	local tier = GameConfig.Pickaxes[math.clamp(inputs.pickaxeTier, 1, #GameConfig.Pickaxes)]
	local power = tier.power
	power *= 1 + GameConfig.Meta.DigSpeed.perLevel * inputs.metaDigLevel
	if inputs.megaActive then
		power *= GameConfig.Round.MegaDrill.PowerMult
	end
	power *= 1 + inputs.catchUp
	return power
end

--- Seconds to break a cell of `hardness` at `power`.
function Economy.digTime(hardness: number, power: number): number
	return math.max(GameConfig.Dig.MinDigTime, hardness / math.max(0.05, power))
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
function Economy.upgradeCost(kind: UpgradeKind, currentTier: number): number?
	if kind == "pickaxe" then
		local nextPickaxe = GameConfig.Pickaxes[currentTier + 1]
		return if nextPickaxe then nextPickaxe.cost else nil
	end
	local nextPack = GameConfig.Packs[currentTier + 1]
	return if nextPack then nextPack.cost else nil
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

--- Total sale value of a backpack.
function Economy.backpackValue(backpack: { [string]: { [string]: number } }): (number, number)
	local total, count = 0, 0
	for oreId, mutations in backpack do
		for mutationId, n in mutations do
			total += Economy.oreValue(oreId, mutationId) * n
			count += n
		end
	end
	return total, count
end

return Economy
