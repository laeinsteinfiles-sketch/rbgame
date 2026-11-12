--!strict
-- Explorer: ReplicatedStorage/Shared/Types (ModuleScript)
-- Shared type definitions. Pure data shapes only; no Roblox types so the
-- economy sim and self tests can load these modules outside Studio.

export type PickaxeTier = {
	name: string,
	power: number,
	cost: number,
	headColor: string,
	headMaterial: string,
	glow: boolean,
}

export type PackTier = { capacity: number, cost: number, name: string }

export type OreWeight = { id: string, weight: number }

export type LayerMood = {
	ambient: string,
	outdoorAmbient: string,
	fogColor: string,
	fogEnd: number,
	brightness: number,
	exposure: number,
	saturation: number,
	contrast: number,
	tint: string,
	lampRange: number,
	lampBrightness: number,
}

export type LayerDef = {
	id: string,
	name: string,
	startDepth: number,
	hardness: number,
	hardnessEnd: number,
	material: string,
	hardMaterial: string,
	color: string,
	hardColor: string,
	backColor: string,
	accent: string,
	richChance: number, -- ore chance inside a rich vein region
	poorChance: number, -- ore chance everywhere else
	caveChance: number, -- chance a cave pocket spawns in a region
	ores: { OreWeight },
	mood: LayerMood,
}

export type OreDef = {
	id: string,
	name: string,
	value: number,
	color: string,
	material: string,
	rarity: number, -- 1 (common) .. 5 (legendary); drives juice intensity
}

export type MutationDef = {
	id: string,
	name: string,
	chance: number,
	mult: number,
	color: string,
}

export type CellKind = "dirt" | "hard" | "ore" | "chest" | "tnt" | "gem" | "relic" | "cave" | "core"

export type Cell = {
	kind: CellKind,
	oreId: string?,
	mutationId: string?,
	hardness: number,
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
	tier: string,
	gemBonus: number,
	color: string,
	accent: string,
	flies: boolean,
}

export type SkinDef = {
	id: string,
	name: string,
	relics: number,
	handleColor: string,
	trailColor: string,
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
