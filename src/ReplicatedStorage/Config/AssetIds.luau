--!strict
-- Explorer: ReplicatedStorage/Config/AssetIds (ModuleScript)
-- Every external asset the game uses, by name. 0 means "not sourced": the
-- code then falls back to code-built art (icons, panels, meshes) or silence
-- (audio, warned once at startup).
-- NEVER type an id here from memory. Verify it, record it in ASSETS.md, then
-- paste the id.

local AssetIds = {}

AssetIds.UI = {
	PanelSlice = 0, -- optional 9-slice panel sprite; panels are code-built plates without it
	PanelSliceCenter = Rect.new(24, 24, 40, 40), -- slice centre for PanelSlice; adjust to the sprite
}

-- Optional uploaded icons. Unset slots draw code-built coins/gems/ores or a
-- colour emoji (Components/Icon), so every slot already renders something.
AssetIds.Icons = {
	Depth = 0, -- "plain arrow"
	Cash = 0, -- "coins"
	Gem = 0, -- "cut diamond"
	Backpack = 0, -- "knapsack"
	Drill = 0, -- "drill"
	Shop = 0, -- "shop"
	Book = 0, -- "book cover"
	Quest = 0, -- "scroll quill"
	Trophy = 0, -- "trophy cup"
	Settings = 0, -- "cog"
	Close = 0, -- "cancel"
	Sell = 0, -- "cash"
	Up = 0, -- "upload" style arrow
	Down = 0, -- "download" style arrow
	Mega = 0, -- "lightning trio"
	Egg = 0, -- "egg"
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
}

-- Engine-shipped textures are safe to reference by rbxasset path; they are
-- not invented ids. Replace with pack textures when sourced.
AssetIds.Particles = {
	Dust = "rbxasset://textures/particles/smoke_main.dds",
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Ember = "rbxasset://textures/particles/fire_main.dds",
}

-- Every id below was looked up on 2026-11-12 through
-- economy.roblox.com/v2/assets/<id>/details: AssetTypeId 3 (Audio),
-- IsPublicDomain true, uploaded by Roblox (1) or Roblox's licensed partner
-- libraries Pro Sound Effects (7462895450) and APM Music (7462718749), so
-- they play in any experience. Names are recorded in ASSETS.md.
AssetIds.Sounds = {
	DigHit = 9118680621, -- Rocks Dirt Impacts In Ground 9 (PSE)
	DigTick = 16480549947, -- Roblox_Pinball_Tiny_Button_Press_06
	DigLoop = 16480557782, -- Roblox_Pinball_Joystick_Rotate_Loop_01
	BlockBreak = 9119037874, -- Shale Break 15 (PSE)
	OreChime = 17208319162, -- Roblox GUI - Pickup
	RareSting = 9116421762, -- Magic Transformation 9 (PSE)
	Sell = 9113728625, -- Cash Register 1 (PSE)
	CoinTick = 16480549708, -- Roblox_Pinball_Tiny_Button_Press_08
	UpgradeBuy = 17208380755, -- Roblox GUI - Purchase
	ButtonTap = 15675032796, -- Roblox_UI_Small_Click
	ButtonDenied = 17208353912, -- Roblox GUI - Negative
	LayerEnter = 9120703816, -- Whoosh Combo Of Impacts Bys 1 (PSE)
	MegaStart = 9113071344, -- Air Horn Bursts 9 (PSE)
	MegaEnd = 9116985195, -- Motor Wind- Down 5 (PSE)
	MegaGoal = 9120974708, -- Wrestling Crowd 8 (PSE)
	RoundStart = 9114402619, -- Ferrari 308 Car Honking Dual Air Horns 9 (PSE)
	Countdown = 15930291180, -- Roblox_RetroSFX_08
	RoundEnd = 16480570385, -- Roblox_Pinball_Bumper_Low_Bells_05
	Win = 12222253, -- victory.wav
	QuestClaim = 17208361335, -- Roblox GUI - Notification High
	ElevatorMove = 9118934517, -- Servo Motor 11
	EggCrack = 9113959343, -- Crack Egg Crunchy 11 (PSE)
	CoreReached = 3149249837, -- Cannon_Explode
	Whoosh = 15675012262, -- Roblox_UI_Whoosh_04
	Pop = 15675059323, -- Roblox_UI_Bright_Click
}

-- Looping background music, crossfaded by zone (Controllers/Music).
AssetIds.Music = {
	Lobby = 1836914203, -- Happy Thoughts (APM): surface, lobby and results
	Topsoil = 1838661059, -- Magical Adventure (Light Vs) (APM)
	Deep = 15675069601, -- Roblox_UI_Loop_Calm_Music: Bedrock
	Hollows = 17422163655, -- Generic - Cloud Blitz: the deep stretch
}

-- Creator Store meshes. The game draws chunky part-built stand-ins until these
-- are filled, which is a known placeholder (see ASSETS.md "Meshes").
AssetIds.Meshes = {
	Drill = 0,
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
} :: { [string]: number }

function AssetIds.isSet(id: number): boolean
	return typeof(id) == "number" and id > 0
end

function AssetIds.image(id: number): string
	return if AssetIds.isSet(id) then `rbxassetid://{id}` else ""
end

function AssetIds.sound(id: number): string
	return if AssetIds.isSet(id) then `rbxassetid://{id}` else ""
end

--- Unset audio slots (the only ones that leave the game worse: silent), for
--- the one-time startup warning. Icons, panels, textures and meshes are
--- optional overrides of code-built art and are not reported.
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
	walk(AssetIds.Sounds, "Sounds.")
	walk(AssetIds.Music, "Music.")
	table.sort(out)
	return out
end

return AssetIds
