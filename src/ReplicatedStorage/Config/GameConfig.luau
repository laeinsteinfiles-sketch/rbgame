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
	MaxPlayers = 12,
	SurfaceY = 0,
	SellRadius = 12, -- how close the character must be to the sell pad
	VisibleBlocksBelow = 10, -- blocks rendered under the player
	DecoratedBlocks = 2, -- only the top blocks are visible from the shaft camera
	WallChunkBlocks = 8, -- wall segment height in blocks
	WallChunksAround = 1, -- chunks rendered above and below the current one
}

-- Island ring around the hub. Local island frame: -Z faces the hub.
GameConfig.World = {
	RingRadius = 150,
	HubRadius = 46,
	HubTop = 4,
	IslandHalf = 23,
	SellPad = { x = 13, z = -7 },
	Workshop = { x = -13, z = -7 },
	Spawn = { x = 0, z = 14 },
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
		WarnSeconds = 10,
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
	Events = {
		LeadMinDepth = 12, -- no lead-change calls in the first scramble
		LeadCooldown = 8, -- seconds between "takes the lead" calls
		NearCoreMetres = 100,
		FinalCallSeconds = 60,
	},
}

GameConfig.Dig = {
	-- Physics drop between blocks. The server's minimum accepted interval is
	-- digTime + DropTime so a client that skips the fall gains nothing.
	DropTime = 0.18,
	ToleranceFraction = 0.12,
	ToleranceMin = 0.08,
	MaxPositionErrorBlocks = 8,
	ViolationKickThreshold = 25,
	TicksPerBlock = 4, -- audible/visible steps per block
}

GameConfig.Travel = {
	Base = 1.0,
	PerMetre = 0.003,
	Max = 5,
	Cooldown = 2,
}

-- The race course is shared by every player in a round (one course seed);
-- only loot is per player. See Shared/Course.
GameConfig.Course = {
	MinPocketDepth = 15,
	PocketLength = { min = 2, max = 6 },
	BlastMinDepth = 40,
	BlastDepth = 3, -- blocks a blast charge clears below itself
	ChestEvery = 100, -- metres
	ChestCashBase = 25,
	ChestCashPerMetre = 0.3, -- (tuned)
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
		material = "Ground",
		groundColor = "8A6E4B",
		wallColor = "6E5A40",
		accentColor = "B8956A",
		pocketChance = 0.006,
		blastChance = 0,
		mood = {
			ambient = "8F8578",
			outdoorAmbient = "A89C8C",
			fogColor = "C9B79C",
			fogEnd = 160,
			atmosphereColor = "C9B79C",
			atmosphereDensity = 0.38,
			atmosphereHaze = 1.6,
			saturation = -0.12,
			contrast = 0.06,
			tint = "FFF6E8",
			brightness = 0,
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
		material = "Slate",
		groundColor = "6B6E73",
		wallColor = "55585E",
		accentColor = "8A8E96",
		pocketChance = 0.01,
		blastChance = 0.005,
		mood = {
			ambient = "5E6166",
			outdoorAmbient = "6F7378",
			fogColor = "8C8F94",
			fogEnd = 120,
			atmosphereColor = "8C8F94",
			atmosphereDensity = 0.48,
			atmosphereHaze = 2.2,
			saturation = -0.28,
			contrast = 0.1,
			tint = "EAF0F5",
			brightness = -0.03,
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
		material = "Basalt",
		groundColor = "4F4A5C",
		wallColor = "3E3A4A",
		accentColor = "6E667F",
		pocketChance = 0.016,
		blastChance = 0.007,
		mood = {
			ambient = "3C3845",
			outdoorAmbient = "4A4654",
			fogColor = "5B5666",
			fogEnd = 90,
			atmosphereColor = "5B5666",
			atmosphereDensity = 0.58,
			atmosphereHaze = 2.8,
			saturation = -0.18,
			contrast = 0.15,
			tint = "F2E6D8",
			brightness = -0.06,
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

-- Ore is the only saturated thing in the ground, by design.
GameConfig.Ores = {
	{ id = "coal", name = "Coal", value = 2, color = "2B2B2B", material = "Slate", rarity = 1, shape = "chunk" },
	{ id = "copper", name = "Copper", value = 6, color = "E07A3F", material = "Metal", rarity = 1, shape = "nugget" },
	{ id = "iron", name = "Iron", value = 14, color = "A9ACB6", material = "Metal", rarity = 2, shape = "nugget" },
	{ id = "silver", name = "Silver", value = 35, color = "E6E8EF", material = "Metal", rarity = 2, shape = "nugget" },
	{ id = "gold", name = "Gold", value = 70, color = "FFC53D", material = "Metal", rarity = 3, shape = "nugget" },
	{ id = "sapphire", name = "Sapphire", value = 120, color = "2F6FE6", material = "Glass", rarity = 4, shape = "crystal" },
	{ id = "ruby", name = "Ruby", value = 200, color = "E0243F", material = "Glass", rarity = 5, shape = "crystal" },
} :: { OreDef }

-- Chances must sum to 1. Odds are shown in the collection book.
GameConfig.Mutations = {
	{ id = "none", name = "Plain", chance = 0.94, mult = 1, color = "FFFFFF" },
	{ id = "flawless", name = "Flawless", chance = 0.04, mult = 3, color = "DDF4FF" },
	{ id = "ancient", name = "Ancient", chance = 0.015, mult = 8, color = "F2B33D" },
	{ id = "molten", name = "Molten", chance = 0.005, mult = 20, color = "FF6A2A" },
} :: { Types.MutationDef }

-- Rarity colours are UI accents (chips, card rims, hatch rays), never panel fills.
GameConfig.Rarities = {
	common = { name = "Common", color = "C9C2B4", order = 1 },
	uncommon = { name = "Uncommon", color = "8BCB6B", order = 2 },
	rare = { name = "Rare", color = "4FA8E8", order = 3 },
	epic = { name = "Epic", color = "C08CF0", order = 4 },
	legendary = { name = "Legendary", color = "F2B33D", order = 5 },
	mythic = { name = "Mythic", color = "FF5E7A", order = 6 },
}

-- Ore rarity number -> rarity id, for chips and card rims.
GameConfig.OreRarity = { "common", "uncommon", "rare", "epic", "legendary" } :: { Types.Rarity }

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

-- gemBonus is a meta-only multiplier on gem rewards; pets never touch the race.
GameConfig.Pets = {
	{ id = "mole", name = "Mole", tier = "common", gemBonus = 0.02, color = "7A6652", flyer = false },
	{ id = "beetle", name = "Dust Beetle", tier = "common", gemBonus = 0.02, color = "5F6B5A", flyer = false },
	{ id = "gecko", name = "Shale Gecko", tier = "uncommon", gemBonus = 0.04, color = "7C8A96", flyer = false },
	{ id = "bat", name = "Cave Bat", tier = "rare", gemBonus = 0.06, color = "5A5466", flyer = true },
	{ id = "crab", name = "Copper Crab", tier = "rare", gemBonus = 0.07, color = "C9743E", flyer = false },
	{ id = "owl", name = "Hollow Owl", tier = "epic", gemBonus = 0.1, color = "6F6A85", flyer = true },
	{ id = "salamander", name = "Core Salamander", tier = "legendary", gemBonus = 0.15, color = "D9762B", flyer = false },
} :: { Types.PetDef }

-- Every egg prints these odds next to its buy button. Each list sums to 100.
GameConfig.Eggs = {
	{
		id = "dusty",
		name = "Dusty Egg",
		cost = 150,
		shell = "D8C9A8",
		spots = "9C8566",
		pets = { { id = "mole", chance = 45 }, { id = "beetle", chance = 35 }, { id = "gecko", chance = 15 }, { id = "bat", chance = 5 } },
	},
	{
		id = "crystal",
		name = "Crystal Egg",
		cost = 450,
		shell = "B9D7DA",
		spots = "4F9AA5",
		pets = { { id = "gecko", chance = 30 }, { id = "bat", chance = 30 }, { id = "crab", chance = 30 }, { id = "owl", chance = 10 } },
	},
	{
		id = "core",
		name = "Core Egg",
		cost = 1200,
		shell = "3A2A24",
		spots = "F2B33D",
		pets = { { id = "crab", chance = 50 }, { id = "owl", chance = 38 }, { id = "salamander", chance = 12 } },
	},
} :: { Types.EggDef }

-- Rolled on every hatch, odds shown on the egg screen. Sums to 100.
GameConfig.PetSizes = {
	{ id = "normal", name = "Normal", chance = 88, scale = 1, mult = 1 },
	{ id = "big", name = "Big", chance = 10, scale = 1.35, mult = 1.25 },
	{ id = "huge", name = "Huge", chance = 2, scale = 1.8, mult = 1.6 },
} :: { Types.PetSize }

GameConfig.DuplicateRefund = 1 / 3 -- of the egg price, so repeat rolls never feel like nothing

-- Skins are cosmetic. Relic prices only; the Drill Skins gamepass unlocks all.
GameConfig.Skins = {
	{ id = "default", name = "Workshop", relics = 0, color = "6B6E73", material = "Metal", bitColor = "A9ACB6" },
	{ id = "copper", name = "Copperhead", relics = 5, color = "A8623A", material = "Metal", bitColor = "E07A3F" },
	{ id = "slate", name = "Slate Runner", relics = 8, color = "3E4450", material = "Slate", bitColor = "8A8E96" },
	{ id = "amber", name = "Amber Core", relics = 15, color = "4A3A24", material = "Metal", bitColor = "F2B33D" },
	{ id = "teal", name = "Deep Teal", relics = 15, color = "25413E", material = "Metal", bitColor = "3FB6A8" },
	{ id = "molten", name = "Molten", relics = 25, color = "3A2622", material = "Basalt", bitColor = "FF6A2A" },
} :: { Types.SkinDef }

-- Token buckets per remote: capacity burst, refill per second.
GameConfig.RateLimits = {
	DigRequest = { capacity = 8, refill = 8 },
	SellAll = { capacity = 2, refill = 1 },
	BuyUpgrade = { capacity = 3, refill = 2 },
	ClaimQuest = { capacity = 2, refill = 1 },
	Travel = { capacity = 2, refill = 0.5 },
	BuyMeta = { capacity = 3, refill = 1 },
	ClaimCollection = { capacity = 3, refill = 1 },
	OpenEgg = { capacity = 2, refill = 0.5 },
	Equip = { capacity = 4, refill = 2 },
	SaveSettings = { capacity = 2, refill = 0.5 },
}

GameConfig.Data = {
	StoreName = "PlayerData_v1",
	AutosaveSeconds = 60,
}

return GameConfig
