--!strict
-- Explorer: ReplicatedStorage/Config/AssetIds (ModuleScript)
-- Every external asset the game uses, by name. 0 means "not sourced yet":
-- the code treats 0 as absent (no image, no sound, fallback geometry) and
-- SFX/Icon warn once at startup so nothing is silently fake.
-- NEVER type an id here from memory. Source it, record it in ASSETS.md, then
-- paste the id. ASSETS.md lists a suggested source and search term per slot.

local AssetIds = {}

AssetIds.UI = {
	PanelSlice = 0, -- 9-slice dark panel, see ASSETS.md "UI panels"
	PanelSliceCenter = Rect.new(24, 24, 40, 40), -- slice centre for PanelSlice; adjust to the sprite
	ButtonSlice = 0,
	ButtonSliceCenter = Rect.new(16, 16, 32, 32),
	BarTrack = 0,
	BarFill = 0,
	BarSliceCenter = Rect.new(8, 8, 16, 16),
}

-- One icon set only (game-icons.net, CC BY 3.0, credited in the Credits screen).
AssetIds.Icons = {
	Depth = 0, -- "arrow down" / "plain arrow"
	Cash = 0, -- "coins"
	Gem = 0, -- "cut diamond"
	Relic = 0, -- "ancient ruins" or "scroll unfurled"
	Backpack = 0, -- "knapsack"
	Drill = 0, -- "drill"
	Shop = 0, -- "shop"
	Book = 0, -- "book cover"
	Quest = 0, -- "scroll quill"
	Trophy = 0, -- "trophy cup"
	Crown = 0, -- "crown"
	Settings = 0, -- "cog"
	Close = 0, -- "cancel"
	Lock = 0, -- "padlock"
	Check = 0, -- "check mark"
	Sell = 0, -- "cash"
	Up = 0, -- "upload" style arrow
	Down = 0, -- "download" style arrow
	Pet = 0, -- "paw print"
	Skin = 0, -- "paint brush"
	Mega = 0, -- "lightning trio"
	Timer = 0, -- "stopwatch"
	Info = 0, -- "info"
	Egg = 0, -- "egg"
	CatchUp = 0, -- "sprint"
	Ore = {
		coal = 0, -- "coal wagon" / "rock"
		copper = 0, -- "ore"
		iron = 0, -- "ore"
		silver = 0, -- "ore"
		gold = 0, -- "gold bar" / "ore"
		sapphire = 0, -- "cut diamond" (recolour in UI)
		ruby = 0, -- "cut diamond" (recolour in UI)
	},
}

-- Layer textures come from the developer's 204-material pack. Slots only;
-- assignment happens once the material list is shared (see ASSETS.md).
-- Either fill Top/Side with image ids, or set MaterialVariant to the name of
-- a MaterialVariant placed under MaterialService; both are applied per block.
AssetIds.Textures = {
	topsoil = { Top = 0, Side = 0, MaterialVariant = "" },
	bedrock = { Top = 0, Side = 0, MaterialVariant = "" },
	hollows = { Top = 0, Side = 0, MaterialVariant = "" },
	core = { Glow = 0 },
}

-- Engine-shipped textures are safe to reference by rbxasset path; they are
-- not invented ids. Replace with pack textures when sourced.
AssetIds.Particles = {
	Dust = "rbxasset://textures/particles/smoke_main.dds",
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Ember = "rbxasset://textures/particles/fire_main.dds",
}

AssetIds.Sounds = {
	DigHit = 0, -- layered low thud, per dig tick
	DigTick = 0, -- high mechanical click, layered over DigHit
	DigLoop = 0, -- drill motor loop while holding
	BlockBreak = 0, -- crumble when a block pops
	OreChime = 0, -- short bright chime on ore pickup (pitch-shifted by rarity)
	RareSting = 0, -- short riser/sting on rarity >= 3 or any mutation
	Sell = 0, -- cash register / coin pour
	CoinTick = 0, -- rapid tick layered under the cash count-up
	UpgradeBuy = 0, -- mechanical ratchet + confirm
	ButtonTap = 0, -- soft UI tap
	ButtonDenied = 0, -- short dull buzz
	LayerEnter = 0, -- deep whoosh + rumble on entering a new layer
	MegaStart = 0, -- siren/horn + crowd
	MegaEnd = 0, -- soft gong
	MegaGoal = 0, -- fanfare
	RoundStart = 0, -- air horn
	Countdown = 0, -- beep
	RoundEnd = 0, -- gong
	Win = 0, -- short fanfare
	QuestClaim = 0, -- reward jingle
	ElevatorMove = 0, -- cable/motor whir
	EggCrack = 0, -- crack + sparkle
	CoreReached = 0, -- big resonant hit
}

-- Creator Store meshes. The game draws chunky part-built stand-ins until these
-- are filled, which is a known placeholder (see ASSETS.md "Meshes").
AssetIds.Meshes = {
	Drill = 0,
	OreNugget = 0,
	Relic = 0,
	CoreCrystal = 0,
	Pets = {
		mole = 0,
		beetle = 0,
		gecko = 0,
		bat = 0,
		crab = 0,
		owl = 0,
		salamander = 0,
	},
}

-- Gamepass ids from the Creator Dashboard for this experience. 0 = not
-- configured; the server then treats the pass as owned by nobody.
AssetIds.Gamepasses = {
	DoubleGems = 0,
	AutoDig = 0,
	BigPack = 0,
	DrillSkins = 0,
}

function AssetIds.isSet(id: number): boolean
	return typeof(id) == "number" and id > 0
end

function AssetIds.image(id: number): string
	return if AssetIds.isSet(id) then `rbxassetid://{id}` else ""
end

function AssetIds.sound(id: number): string
	return if AssetIds.isSet(id) then `rbxassetid://{id}` else ""
end

--- Names of every unset slot, for the one-time startup warning.
function AssetIds.missing(): { string }
	local out = {}
	local function walk(tbl: { [string]: any }, prefix: string)
		for key, value in tbl do
			if typeof(value) == "number" then
				if value == 0 then
					table.insert(out, prefix .. key)
				end
			elseif typeof(value) == "table" then
				walk(value, prefix .. key .. ".")
			end
		end
	end
	walk(AssetIds.UI, "UI.")
	walk(AssetIds.Icons, "Icons.")
	walk(AssetIds.Textures, "Textures.")
	walk(AssetIds.Sounds, "Sounds.")
	walk(AssetIds.Meshes, "Meshes.")
	walk(AssetIds.Gamepasses, "Gamepasses.")
	table.sort(out)
	return out
end

return AssetIds
