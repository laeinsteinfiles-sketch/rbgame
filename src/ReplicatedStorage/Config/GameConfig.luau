--!strict
-- Explorer: ReplicatedStorage/Config/GameConfig (ModuleScript)
-- Every tunable number lives here. Colours are hex strings and materials are
-- Enum names so this file stays plain data: the economy sim loads it outside
-- Studio and ProfileStore never sees Roblox userdata.
--
-- Pacing numbers marked (tuned) come from tools/EconomySim.luau; re-run
-- `python3 tools/run_sim.py` after changing any of them (see DESIGN.md).

local Types = require(script.Parent.Parent.Shared.Types)

type LayerDef = Types.LayerDef
type OreDef = Types.OreDef

local GameConfig = {}

-- The mine is a 2D cross-section: columns along world X, rows going down.
-- Row r spans SurfaceY - r*Cell .. SurfaceY - (r-1)*Cell. One row = 1 m.
GameConfig.Geometry = {
	Cell = 6, -- studs per cell edge; tall enough for any avatar to walk through
	Columns = 11, -- diggable columns per mine
	-- Unbreakable rock drawn beside the mine on each side. The island is
	-- exactly mine + border wide so its cliff face continues the cross-section.
	BorderColumns = 7,
	SurfaceY = 0,
	PlotColumns = 4,
	MaxPlayers = 12,
	PlotSpacingX = 175,
	PlotSpacingZ = 150,
	IslandBack = 60, -- Z extent of the surface behind the mine (the mine is the front edge)
	IslandRows = 2, -- island thickness in rows; client border rock starts below it
	SellPad = { x = 26, z = -24, radius = 9 }, -- offsets from the plot origin
	ShopPad = { x = -26, z = -24, radius = 9 },
	SpawnOffset = { x = 0, z = -16 },
	RenderRowsAbove = 8,
	RenderRowsBelow = 12,
	CameraDistance = 50,
	CameraHeight = 4,
	CameraPitch = -8, -- degrees; looking slightly down the mine
	CameraFov = 60,
}

GameConfig.Round = {
	LobbySeconds = 20,
	StudioLobbySeconds = 6, -- solo Studio tests should not wait on an empty lobby
	CountdownSeconds = 5,
	ActiveSeconds = 15 * 60,
	ResultsSeconds = 14,
	MegaDrill = {
		StartTimes = { 5 * 60, 10 * 60 }, -- seconds after Active starts
		Duration = 45,
		PowerMult = 2,
		GoalPerPlayer = 40, -- cells dug per online player to fill the shared bar
		GemBonus = 25,
	},
	CatchUp = {
		MaxBonus = 0.2,
		FullGapFraction = 0.15, -- gap (as a fraction of CoreDepth) that earns the full bonus
		UpdateInterval = 3,
	},
	Gems = {
		Placement = { 60, 40, 25 },
		Participation = 10,
		DepthPerGem = 25, -- +1 gem per 25 m of final depth...
		DepthGemCap = 30, -- ...capped here
		CoreBonus = 50, -- reaching the core at all, even after the winner
	},
	DepthMilestone = 50, -- metres between "you passed N m" moments
}

GameConfig.Dig = {
	MinDigTime = 0.12, -- seconds; caps cells per second on the best pickaxe
	SwingInterval = 0.32, -- visual swing cadence while holding
	-- The server keeps a virtual dig clock: each accepted cell adds its dig
	-- time; a cell is accepted while that clock is no further ahead of real
	-- time than the tolerance. Banked idle time is capped so it cannot be
	-- saved up and spent as a burst.
	BankSeconds = 0.6,
	ToleranceSeconds = 0.3,
	ViolationAheadSeconds = 1.5,
	ReachStuds = 12.5, -- root-to-cell-centre distance the server accepts
	ViolationReachStuds = 40,
	ViolationKickThreshold = 30,
	MaxPending = 3, -- unconfirmed predicted cells the client may have in flight
}

GameConfig.Travel = {
	Base = 1.2,
	PerMetre = 0.006,
	Max = 4.5,
	Cooldown = 1.5,
}

-- cost = cash to reach this tier from the previous one. Tier 1 is free. (tuned)
GameConfig.Pickaxes = {
	{ name = "Wooden Pickaxe", power = 1, cost = 0, headColor = "9C9C9C", headMaterial = "Slate", glow = false },
	{ name = "Stone Pickaxe", power = 1.6, cost = 45, headColor = "7D838C", headMaterial = "Rock", glow = false },
	{ name = "Iron Pickaxe", power = 2.5, cost = 140, headColor = "D8DDE6", headMaterial = "Metal", glow = false },
	{ name = "Golden Pickaxe", power = 3.8, cost = 380, headColor = "FFC83D", headMaterial = "Metal", glow = false },
	{ name = "Crystal Pickaxe", power = 5.7, cost = 950, headColor = "B266FF", headMaterial = "Glass", glow = true },
	{ name = "Ruby Pickaxe", power = 8.4, cost = 2300, headColor = "FF2E55", headMaterial = "Glass", glow = true },
	{ name = "Plasma Pickaxe", power = 12.5, cost = 5400, headColor = "38E1FF", headMaterial = "Neon", glow = true },
	{ name = "Core Breaker", power = 18.5, cost = 12500, headColor = "FF8A1F", headMaterial = "Neon", glow = true },
} :: { Types.PickaxeTier }

GameConfig.Packs = {
	{ name = "Pouch", capacity = 10, cost = 0 },
	{ name = "Satchel", capacity = 20, cost = 30 },
	{ name = "Rucksack", capacity = 40, cost = 110 },
	{ name = "Ore Crate", capacity = 70, cost = 320 },
	{ name = "Hauler", capacity = 120, cost = 900 },
	{ name = "Titan Hauler", capacity = 200, cost = 2400 },
} :: { Types.PackTier }

GameConfig.CoreDepth = 500 -- metres; row 500 is the core seal (tuned)
GameConfig.CoreHardness = 18

-- Layer order matters: Layers.indexAt walks it top to bottom. Hardness ramps
-- linearly from `hardness` at startDepth to `hardnessEnd` at the next layer.
-- Ore weights are relative and only pick *which* ore; how often a cell is ore
-- at all comes from richChance/poorChance.
GameConfig.Layers = {
	{
		id = "topsoil",
		name = "Topsoil",
		startDepth = 0,
		hardness = 1,
		hardnessEnd = 1.6,
		material = "Ground",
		hardMaterial = "Rock",
		color = "8C5E3C",
		hardColor = "6A6560",
		backColor = "3B2618",
		accent = "C99566",
		richChance = 0.42,
		poorChance = 0.09,
		caveChance = 0.1,
		ores = {
			{ id = "coal", weight = 55 },
			{ id = "copper", weight = 35 },
			{ id = "iron", weight = 10 },
		},
		mood = {
			ambient = "8A7A6A",
			outdoorAmbient = "9C8C7A",
			fogColor = "2A1C12",
			fogEnd = 420,
			brightness = 2.2,
			exposure = 0,
			saturation = 0.05,
			contrast = 0.08,
			tint = "FFF4E6",
			lampRange = 26,
			lampBrightness = 0.8,
		},
	},
	{
		id = "stone",
		name = "Stone",
		startDepth = 60,
		hardness = 1.8,
		hardnessEnd = 3,
		material = "Rock",
		hardMaterial = "Slate",
		color = "8E939B",
		hardColor = "5E636B",
		backColor = "2B2E33",
		accent = "B9BEC6",
		richChance = 0.4,
		poorChance = 0.08,
		caveChance = 0.16,
		ores = {
			{ id = "coal", weight = 25 },
			{ id = "copper", weight = 30 },
			{ id = "iron", weight = 30 },
			{ id = "silver", weight = 15 },
		},
		mood = {
			ambient = "6E737C",
			outdoorAmbient = "7C828C",
			fogColor = "1E2126",
			fogEnd = 380,
			brightness = 1.6,
			exposure = -0.1,
			saturation = 0.05,
			contrast = 0.1,
			tint = "F2F6FF",
			lampRange = 30,
			lampBrightness = 1.1,
		},
	},
	{
		id = "deepslate",
		name = "Deep Slate",
		startDepth = 150,
		hardness = 3.2,
		hardnessEnd = 5.5,
		material = "Slate",
		hardMaterial = "Basalt",
		color = "4F5B6E",
		hardColor = "323A47",
		backColor = "171C24",
		accent = "7F8DA6",
		richChance = 0.38,
		poorChance = 0.075,
		caveChance = 0.2,
		ores = {
			{ id = "iron", weight = 30 },
			{ id = "silver", weight = 35 },
			{ id = "gold", weight = 25 },
			{ id = "amethyst", weight = 10 },
		},
		mood = {
			ambient = "4E586A",
			outdoorAmbient = "5A6478",
			fogColor = "10141B",
			fogEnd = 340,
			brightness = 1.1,
			exposure = -0.2,
			saturation = 0.08,
			contrast = 0.12,
			tint = "E8F0FF",
			lampRange = 34,
			lampBrightness = 1.4,
		},
	},
	{
		id = "crystal",
		name = "Crystal Caverns",
		startDepth = 270,
		hardness = 6,
		hardnessEnd = 9.5,
		material = "Basalt",
		hardMaterial = "Slate",
		color = "4A3C6E",
		hardColor = "2E2547",
		backColor = "140F24",
		accent = "B48CFF",
		richChance = 0.38,
		poorChance = 0.07,
		caveChance = 0.24,
		ores = {
			{ id = "silver", weight = 15 },
			{ id = "gold", weight = 30 },
			{ id = "amethyst", weight = 30 },
			{ id = "sapphire", weight = 20 },
			{ id = "ruby", weight = 5 },
		},
		mood = {
			ambient = "51456E",
			outdoorAmbient = "5C4F7C",
			fogColor = "120C22",
			fogEnd = 320,
			brightness = 0.8,
			exposure = -0.25,
			saturation = 0.15,
			contrast = 0.14,
			tint = "F0E8FF",
			lampRange = 36,
			lampBrightness = 1.6,
		},
	},
	{
		id = "magma",
		name = "Magma Depths",
		startDepth = 390,
		hardness = 10,
		hardnessEnd = 15,
		material = "Basalt",
		hardMaterial = "CrackedLava",
		color = "3A2A28",
		hardColor = "2A1A16",
		backColor = "160806",
		accent = "FF7A2E",
		richChance = 0.36,
		poorChance = 0.07,
		caveChance = 0.2,
		ores = {
			{ id = "gold", weight = 20 },
			{ id = "sapphire", weight = 30 },
			{ id = "ruby", weight = 30 },
			{ id = "diamond", weight = 20 },
		},
		mood = {
			ambient = "6E4436",
			outdoorAmbient = "7A4A3A",
			fogColor = "2A0E06",
			fogEnd = 300,
			brightness = 0.7,
			exposure = -0.2,
			saturation = 0.18,
			contrast = 0.16,
			tint = "FFE6D6",
			lampRange = 36,
			lampBrightness = 1.6,
		},
	},
} :: { LayerDef }

-- Ore is the only saturated thing in the rock, by design. (tuned)
GameConfig.Ores = {
	{ id = "coal", name = "Coal", value = 2, color = "2E2E36", material = "Slate", rarity = 1 },
	{ id = "copper", name = "Copper", value = 5, color = "E07A3F", material = "Metal", rarity = 1 },
	{ id = "iron", name = "Iron", value = 12, color = "C9CED8", material = "Metal", rarity = 2 },
	{ id = "silver", name = "Silver", value = 28, color = "EEF2FA", material = "Metal", rarity = 2 },
	{ id = "gold", name = "Gold", value = 60, color = "FFC83D", material = "Metal", rarity = 3 },
	{ id = "amethyst", name = "Amethyst", value = 100, color = "B266FF", material = "Glass", rarity = 3 },
	{ id = "sapphire", name = "Sapphire", value = 160, color = "2F7BFF", material = "Glass", rarity = 4 },
	{ id = "ruby", name = "Ruby", value = 260, color = "FF2E55", material = "Glass", rarity = 4 },
	{ id = "diamond", name = "Diamond", value = 420, color = "7DF9FF", material = "Glass", rarity = 5 },
} :: { OreDef }

-- Chances must sum to 1. Odds are shown in the collection book.
GameConfig.Mutations = {
	{ id = "none", name = "Plain", chance = 0.94, mult = 1, color = "FFFFFF" },
	{ id = "flawless", name = "Flawless", chance = 0.04, mult = 3, color = "DDF4FF" },
	{ id = "ancient", name = "Ancient", chance = 0.015, mult = 8, color = "F2B33D" },
	{ id = "molten", name = "Molten", chance = 0.005, mult = 20, color = "FF6A2A" },
} :: { Types.MutationDef }

-- Special cells. Each is rolled per cell before ore; `minDepth` keeps the
-- first metres simple so new players learn plain digging first.
GameConfig.Specials = {
	Chest = { chance = 0.005, minDepth = 6, cashBase = 30, cashPerMetre = 3 },
	Tnt = { chance = 0.007, minDepth = 4, radius = 1 },
	Gem = { chance = 0.0035, minDepth = 20, gems = 2 },
	Relic = { chance = 0.002, minDepth = 80 },
	Hard = { chance = 0.07, minDepth = 10, mult = 2.5 },
	-- Caves: one candidate pocket per region; cells inside the ellipse start open.
	CaveRegionCols = 6,
	CaveRegionRows = 7,
	CaveMinDepth = 12,
	-- Ore veins: regions are "rich" (dense, one ore type) or "poor" (sparse, mixed).
	VeinRegionCols = 3,
	VeinRegionRows = 3,
	RichRegionChance = 0.3,
}

GameConfig.Collection = {
	Thresholds = { 10, 100, 500 },
	Rewards = { 5, 20, 60 }, -- gems, multiplied by ore rarity
}

GameConfig.Meta = {
	DigSpeed = { perLevel = 0.02, maxLevel = 5, costs = { 100, 200, 350, 550, 800 } },
	Pack = { perLevel = 2, maxLevel = 5, costs = { 80, 160, 280, 450, 700 } },
	StarterPackTierWithPass = 2,
}

GameConfig.Pets = {
	EggCost = 150,
	-- Odds are displayed verbatim in the egg shop. Must sum to 100.
	Odds = {
		{ tier = "common", chance = 60 },
		{ tier = "uncommon", chance = 25 },
		{ tier = "rare", chance = 10 },
		{ tier = "epic", chance = 4 },
		{ tier = "legendary", chance = 1 },
	},
	-- gemBonus is a meta-only multiplier on gem rewards; pets never touch the race.
	List = {
		{ id = "mole", name = "Mole", tier = "common", gemBonus = 0.02, color = "7A5C48", accent = "F2A0A0", flies = false },
		{ id = "beetle", name = "Dust Beetle", tier = "common", gemBonus = 0.02, color = "3F7A4F", accent = "A6E3A1", flies = false },
		{ id = "gecko", name = "Shale Gecko", tier = "uncommon", gemBonus = 0.04, color = "5FA8D3", accent = "FFE08A", flies = false },
		{ id = "bat", name = "Cave Bat", tier = "uncommon", gemBonus = 0.04, color = "5A4E7A", accent = "FF9AD5", flies = true },
		{ id = "crab", name = "Copper Crab", tier = "rare", gemBonus = 0.07, color = "E07A3F", accent = "FFD27A", flies = false },
		{ id = "owl", name = "Hollow Owl", tier = "epic", gemBonus = 0.1, color = "8C7BD9", accent = "FFE38A", flies = true },
		{ id = "salamander", name = "Core Salamander", tier = "legendary", gemBonus = 0.15, color = "FF7A2E", accent = "FFE066", flies = false },
	},
} :: { EggCost: number, Odds: { { tier: string, chance: number } }, List: { Types.PetDef } }

-- Skins recolour the pickaxe handle and add a swing trail. Cosmetic only;
-- relic prices, and the Pickaxe Skins gamepass unlocks all of them.
GameConfig.Skins = {
	{ id = "default", name = "Workshop", relics = 0, handleColor = "8A5A3A", trailColor = "FFFFFF" },
	{ id = "copper", name = "Copperhead", relics = 5, handleColor = "A8623A", trailColor = "E07A3F" },
	{ id = "slate", name = "Slate Runner", relics = 8, handleColor = "3E4450", trailColor = "8A8E96" },
	{ id = "amber", name = "Amber Core", relics = 15, handleColor = "4A3A24", trailColor = "F2B33D" },
	{ id = "teal", name = "Deep Teal", relics = 15, handleColor = "25413E", trailColor = "3FD6C4" },
	{ id = "molten", name = "Molten", relics = 25, handleColor = "3A2622", trailColor = "FF6A2A" },
} :: { Types.SkinDef }

-- Token buckets per remote: capacity burst, refill per second.
GameConfig.RateLimits = {
	DigRequest = { capacity = 12, refill = 10 },
	SellAll = { capacity = 2, refill = 1 },
	BuyUpgrade = { capacity = 4, refill = 3 },
	ClaimQuest = { capacity = 2, refill = 1 },
	Travel = { capacity = 2, refill = 0.5 },
	BuyMeta = { capacity = 3, refill = 1 },
	ClaimCollection = { capacity = 3, refill = 1 },
	OpenEgg = { capacity = 2, refill = 0.5 },
	Equip = { capacity = 4, refill = 2 },
	SaveSettings = { capacity = 3, refill = 0.5 },
}

GameConfig.Data = {
	StoreName = "PlayerData_v1",
	AutosaveSeconds = 60,
}

return GameConfig
