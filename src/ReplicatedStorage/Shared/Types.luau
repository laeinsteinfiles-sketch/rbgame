--!strict
-- Explorer: ReplicatedStorage/Shared/Types (ModuleScript)
-- Shared type definitions. Pure data shapes only; no Roblox types so the
-- economy sim can load these modules outside Studio.

export type DrillTier = { power: number, cost: number, name: string }
export type PackTier = { capacity: number, cost: number, name: string }

export type OreWeight = { id: string, weight: number }

export type LayerMood = {
	ambient: string,
	outdoorAmbient: string,
	fogColor: string,
	fogEnd: number,
	atmosphereColor: string,
	atmosphereDensity: number,
	atmosphereHaze: number,
	saturation: number,
	contrast: number,
	tint: string,
	brightness: number,
}

export type LayerDef = {
	id: string,
	name: string,
	startDepth: number,
	hardness: number,
	hardnessEnd: number,
	material: string,
	groundColor: string,
	wallColor: string,
	accentColor: string,
	pocketChance: number, -- chance a free-fall pocket starts at any block
	blastChance: number, -- chance any block is a blast charge
	mood: LayerMood,
	ores: { OreWeight },
}

export type Rarity = "common" | "uncommon" | "rare" | "epic" | "legendary" | "mythic"

export type OreDef = {
	id: string,
	name: string,
	value: number,
	color: string,
	material: string,
	rarity: number, -- 1 (common) .. 5 (legendary); drives juice intensity
	shape: "chunk" | "nugget" | "crystal",
}

export type MutationDef = {
	id: string,
	name: string,
	chance: number,
	mult: number,
	color: string,
}

export type QuestDef = {
	id: string,
	kind: string,
	target: string?,
	goal: number,
	reward: number,
	title: string,
}

export type PetDef = {
	id: string,
	name: string,
	tier: Rarity,
	gemBonus: number,
	color: string,
	flyer: boolean,
}

export type PetSize = {
	id: string,
	name: string,
	chance: number, -- percent
	scale: number,
	mult: number, -- multiplies the pet's gem bonus
}

export type EggDef = {
	id: string,
	name: string,
	cost: number,
	shell: string,
	spots: string,
	pets: { { id: string, chance: number } }, -- percent, sums to 100
}

export type SkinDef = {
	id: string,
	name: string,
	relics: number,
	color: string,
	material: string,
	bitColor: string,
}

export type BlockRoll = {
	oreId: string?,
	mutationId: string?,
	relic: boolean,
}

export type Backpack = { [string]: { [string]: number } }

export type Standing = {
	userId: number,
	name: string,
	depth: number,
	placement: number,
	gems: number,
}

return {}
