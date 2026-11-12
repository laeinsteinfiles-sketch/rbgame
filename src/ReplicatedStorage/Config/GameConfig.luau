--!strict
-- Explorer: ReplicatedStorage/Config/GameConfig (ModuleScript)
-- Every tunable number lives here. Colours are hex strings and materials are
-- Enum names so this file stays plain data: the economy sim loads it outside
-- Studio and ProfileStore never sees Roblox userdata.
--
-- Pacing numbers were tuned with tools/EconomySim.luau (see DESIGN.md for the
-- latest run). Treat anything marked (tuned) as a sim result, not a guess.

local Types = require(script.Parent.Parent.Shared.Types)

type LayerDef = Types.LayerDef
type OreDef = Types.OreDef

local GameConfig = {}

GameConfig.Geometry = {
	BlockSize = 8, -- shaft width in studs
	BlockHeight = 4, -- studs per metre of depth
	PlotSpacing = 96,
	PlotColumns = 4,
	MaxPlayers = 12,
	IslandSize = 44,
	SurfaceY = 0,
	SellPadOffset = 14, -- studs from the shaft centre along +X
	SellRadius = 12, -- how close the character must be to the sell pad
	VisibleBlocksBelow = 10, -- blocks rendered under the player
	WallChunkBlocks = 8, -- wall segment height in blocks
	WallChunksAround = 1, -- chunks rendered above and below the current one
}

GameConfig.Round = {
	LobbySeconds = 30,
	CountdownSeconds = 5,
	ActiveSeconds = 25 * 60,
	ResultsSeconds = 20,
	MegaDrill = {
		StartTimes = { 8 * 60, 16 * 60 }, -- seconds after Active starts
		Duration = 60,
		PowerMult = 1.5,
		GoalPerPlayer = 45, -- blocks dug per online player to fill the shared bar
		GemBonus = 20,
	},
	CatchUp = {
		MaxBonus = 0.15,
		FullGapFraction = 0.15, -- gap (as a fraction of CoreDepth) that earns the full bonus
		UpdateInterval = 3,
	},
	Gems = {
		Placement = { 60, 40, 25 },
		Participation = 10,
		DepthPerGem = 50, -- +1 gem per 50 m of final depth...
		DepthGemCap = 30, -- ...capped here
	},
}

GameConfig.Dig = {
	-- Physics drop between blocks. The server's minimum accepted interval is
	-- digTime + DropTime so a client that skips the fall gains nothing.
	DropTime = 0.18,
	-- Timing is judged against a small bank of earned time rather than each
	-- gap alone, so two requests bunched by lag still pass while sustained
	-- over-speed does not. Under TooFastFraction of the required gap is a
	-- violation; anything else that fails is only rejected and resynced.
	TimeBankSeconds = 0.75,
	TooFastFraction = 0.5,
	MaxPositionErrorBlocks = 6,
	ViolationKickThreshold = 25,
}

GameConfig.Travel = {
	Base = 1.0,
	PerMetre = 0.003,
	Max = 5,
	Cooldown = 2,
}

-- cost = cash to reach this tier from the previous one. Tier 1 is free.
GameConfig.Drills = {
	{ name = "Hand Drill", power = 1, cost = 0 },
	{ name = "Copper Bit", power = 1.6, cost = 50 },
	{ name = "Iron Bit", power = 2.6, cost = 140 },
	{ name = "Steel Auger", power = 4.2, cost = 380 },
	{ name = "Tungsten Auger", power = 6.7, cost = 1000 },
	{ name = "Diamond Core", power = 10.7, cost = 2700 },
	{ name = "Plasma Bore", power = 17, cost = 7300 },
} :: { Types.DrillTier }

GameConfig.Packs = {
	{ name = "Satchel", capacity = 12, cost = 0 },
	{ name = "Rucksack", capacity = 24, cost = 30 },
	{ name = "Ore Crate", capacity = 45, cost = 100 },
	{ name = "Cargo Rig", capacity = 80, cost = 300 },
	{ name = "Hauler", capacity = 140, cost = 850 },
	{ name = "Freight Frame", capacity = 240, cost = 2200 },
} :: { Types.PackTier }

GameConfig.CoreDepth = 1050 -- metres; the block at this index is the core seal (tuned)

-- Layer order matters: Layers.layerAt walks it top to bottom. Hardness ramps
-- linearly from `hardness` at startDepth to `hardnessEnd` at the next layer.
-- Ore weights are relative; id "" means "plain block".
GameConfig.Layers = {
	{
		id = "topsoil",
		name = "Topsoil",
		startDepth = 0,
		hardness = 1,
		hardnessEnd = 1.8,
		-- Warm chocolate / orange-brown dirt, lit like a cosy mine.
		material = "Ground",
		groundColor = "A8662F",
		wallColor = "7E4626",
		accentColor = "E0A050",
		mood = {
			ambient = "9A7456",
			outdoorAmbient = "B08660",
			fogColor = "3B2414",
			fogEnd = 260,
			atmosphereColor = "6B4326",
			atmosphereDecay = "3B2414",
			atmosphereDensity = 0.42,
			atmosphereHaze = 1.4,
			atmosphereGlare = 0,
			saturation = 0.18,
			contrast = 0.08,
			tint = "FFF0DC",
			brightness = 0.02,
			sunBrightness = 2,
			exposure = 0.2,
			bloom = 0.55,
			sunRays = 0,
		},
		ores = {
			{ id = "", weight = 66 },
			{ id = "coal", weight = 20 },
			{ id = "copper", weight = 10 },
			{ id = "iron", weight = 4 },
		},
	},
	{
		id = "bedrock",
		name = "Bedrock",
		startDepth = 150,
		hardness = 2.5,
		hardnessEnd = 5,
		-- Cool blue-grey stone with cyan crystal light.
		material = "Slate",
		groundColor = "7088AE",
		wallColor = "4F6282",
		accentColor = "8FD8FF",
		mood = {
			ambient = "6A82AA",
			outdoorAmbient = "7E96BE",
			fogColor = "17223A",
			fogEnd = 220,
			atmosphereColor = "2A3D63",
			atmosphereDecay = "17223A",
			atmosphereDensity = 0.48,
			atmosphereHaze = 1.8,
			atmosphereGlare = 0,
			saturation = 0.2,
			contrast = 0.1,
			tint = "EAF4FF",
			brightness = 0.02,
			sunBrightness = 1.6,
			exposure = 0.3,
			bloom = 0.8,
			sunRays = 0,
		},
		ores = {
			{ id = "", weight = 68 },
			{ id = "coal", weight = 6 },
			{ id = "copper", weight = 10 },
			{ id = "iron", weight = 10 },
			{ id = "silver", weight = 5 },
			{ id = "gold", weight = 1 },
		},
	},
	{
		id = "hollows",
		name = "The Hollows",
		startDepth = 450,
		hardness = 5,
		hardnessEnd = 14,
		-- Deep violet basalt, purple crystals and lava glow.
		material = "Basalt",
		groundColor = "62408F",
		wallColor = "3E2766",
		accentColor = "C77DFF",
		mood = {
			ambient = "7A55A8",
			outdoorAmbient = "8A62B8",
			fogColor = "1E0E30",
			fogEnd = 200,
			atmosphereColor = "3D1E5E",
			atmosphereDecay = "1E0E30",
			atmosphereDensity = 0.52,
			atmosphereHaze = 2.2,
			atmosphereGlare = 0,
			saturation = 0.24,
			contrast = 0.12,
			tint = "FFEAF6",
			brightness = 0.02,
			sunBrightness = 1.4,
			exposure = 0.35,
			bloom = 1,
			sunRays = 0,
		},
		ores = {
			{ id = "", weight = 65 },
			{ id = "iron", weight = 8 },
			{ id = "silver", weight = 10 },
			{ id = "gold", weight = 10 },
			{ id = "sapphire", weight = 6 },
			{ id = "ruby", weight = 1 },
		},
	},
} :: { LayerDef }

-- Ore colours also tint UI icons; keep them brighter than the strata so ore pops.
GameConfig.Ores = {
	{ id = "coal", name = "Coal", value = 2, color = "35333F", material = "Slate", rarity = 1 },
	{ id = "copper", name = "Copper", value = 6, color = "F2853A", material = "Metal", rarity = 1 },
	{ id = "iron", name = "Iron", value = 14, color = "D9AE90", material = "Metal", rarity = 2 },
	{ id = "silver", name = "Silver", value = 35, color = "E9F0FA", material = "Metal", rarity = 2 },
	{ id = "gold", name = "Gold", value = 70, color = "FFC93C", material = "Metal", rarity = 3 },
	{ id = "sapphire", name = "Sapphire", value = 120, color = "2F7BFF", material = "Glass", rarity = 4 },
	{ id = "ruby", name = "Ruby", value = 200, color = "FF2E4D", material = "Glass", rarity = 5 },
} :: { OreDef }

-- Chances must sum to 1. Odds are shown in the collection book.
GameConfig.Mutations = {
	{ id = "none", name = "Plain", chance = 0.94, mult = 1, color = "FFFFFF" },
	{ id = "flawless", name = "Flawless", chance = 0.04, mult = 3, color = "DDF4FF" },
	{ id = "ancient", name = "Ancient", chance = 0.015, mult = 8, color = "F2B33D" },
	{ id = "molten", name = "Molten", chance = 0.005, mult = 20, color = "FF6A2A" },
} :: { Types.MutationDef }

GameConfig.Relic = {
	MinDepth = 100,
	Chance = 0.0025,
}

GameConfig.Collection = {
	Thresholds = { 10, 100, 500 },
	Rewards = { 5, 20, 60 }, -- gems, multiplied by ore rarity
}

GameConfig.Meta = {
	DigSpeed = { perLevel = 0.02, maxLevel = 5, costs = { 100, 200, 350, 550, 800 } },
	Pack = { perLevel = 1, maxLevel = 5, costs = { 80, 160, 280, 450, 700 } },
	StarterPackTierWithPass = 2,
}

GameConfig.Pets = {
	EggCost = 150,
	-- Odds are displayed verbatim in the meta shop. Must sum to 100.
	Odds = {
		{ tier = "common", chance = 60 },
		{ tier = "uncommon", chance = 25 },
		{ tier = "rare", chance = 10 },
		{ tier = "epic", chance = 4 },
		{ tier = "legendary", chance = 1 },
	},
	-- gemBonus is a meta-only multiplier on gem rewards; pets never touch the race.
	List = {
		{ id = "mole", name = "Mole", tier = "common", gemBonus = 0.02, color = "9C6B4A" },
		{ id = "beetle", name = "Dust Beetle", tier = "common", gemBonus = 0.02, color = "2FB36E" },
		{ id = "gecko", name = "Shale Gecko", tier = "uncommon", gemBonus = 0.04, color = "8BDB4F" },
		{ id = "bat", name = "Cave Bat", tier = "uncommon", gemBonus = 0.04, color = "7A55C9" },
		{ id = "crab", name = "Copper Crab", tier = "rare", gemBonus = 0.07, color = "FF6B3D" },
		{ id = "owl", name = "Hollow Owl", tier = "epic", gemBonus = 0.1, color = "8E7CC3" },
		{ id = "salamander", name = "Core Salamander", tier = "legendary", gemBonus = 0.15, color = "FFB21E" },
	},
} :: { EggCost: number, Odds: { { tier: string, chance: number } }, List: { Types.PetDef } }

-- Skins are cosmetic. Relic prices only; the Drill Skins gamepass unlocks all.
GameConfig.Skins = {
	-- color/material = drill body; bitColor = the body's accent stripes (the bit itself shows the drill tier).
	{ id = "default", name = "Workshop", relics = 0, color = "FFB627", material = "Plastic", bitColor = "2B2F3A" },
	{ id = "copper", name = "Copperhead", relics = 5, color = "D9652B", material = "Metal", bitColor = "FFD27A" },
	{ id = "slate", name = "Slate Runner", relics = 8, color = "4A5D7E", material = "Slate", bitColor = "8FE3FF" },
	{ id = "amber", name = "Amber Core", relics = 15, color = "FF9F1C", material = "Glass", bitColor = "FFE066" },
	{ id = "teal", name = "Deep Teal", relics = 15, color = "17A398", material = "SmoothPlastic", bitColor = "B8FFF2" },
	{ id = "molten", name = "Molten", relics = 25, color = "3A1C14", material = "CrackedLava", bitColor = "FF6A1A" },
} :: { Types.SkinDef }

-- Token buckets per remote: capacity burst, refill per second.
GameConfig.RateLimits = {
	DigRequest = { capacity = 8, refill = 8 },
	DigHold = { capacity = 6, refill = 4 },
	SellAll = { capacity = 2, refill = 1 },
	BuyUpgrade = { capacity = 3, refill = 2 },
	ClaimQuest = { capacity = 2, refill = 1 },
	Travel = { capacity = 2, refill = 0.5 },
	BuyMeta = { capacity = 3, refill = 1 },
	ClaimCollection = { capacity = 3, refill = 1 },
	OpenEgg = { capacity = 2, refill = 0.5 },
	Equip = { capacity = 4, refill = 2 },
}

GameConfig.Data = {
	StoreName = "PlayerData_v1",
	AutosaveSeconds = 60,
}

return GameConfig
