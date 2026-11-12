--!strict
-- Explorer: ServerScriptService/Services/DataService (ModuleScript)
-- ProfileStore session per player. Only meta data lives here; round numbers
-- are memory-only in RoundState and never touch the profile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Signal)
local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)

local DataService = {}

export type CollectionEntry = { count: number, mutations: { [string]: number } }
-- Pets are owned per size: pets.mole = { normal = 2, huge = 1 }.
export type PetCounts = { [string]: number }

export type ProfileData = {
	version: number,
	gems: number,
	relics: number,
	meta: { digSpeedLvl: number, packLvl: number },
	collection: { [string]: CollectionEntry },
	quests: { day: number, progress: { [string]: number }, claimed: { [string]: boolean } },
	stats: { rounds: number, wins: number, maxDepth: number, cores: number, bestCoreTime: number },
	purchases: {
		skins: { [string]: boolean },
		pets: { [string]: PetCounts },
		claimedCollection: { [string]: boolean },
		equippedSkin: string,
		equippedPet: string, -- "petId:sizeId" or ""
		eggsOpened: number,
	},
	settings: { sfx: number, shake: boolean, autoDig: boolean },
}

local SCHEMA_VERSION = 2

local TEMPLATE: ProfileData = {
	version = SCHEMA_VERSION,
	gems = 0,
	relics = 0,
	meta = { digSpeedLvl = 0, packLvl = 0 },
	collection = {},
	quests = { day = 0, progress = {}, claimed = {} },
	stats = { rounds = 0, wins = 0, maxDepth = 0, cores = 0, bestCoreTime = 0 },
	purchases = {
		skins = { default = true },
		pets = {},
		claimedCollection = {},
		equippedSkin = "default",
		equippedPet = "",
		eggsOpened = 0,
	},
	settings = { sfx = 0.8, shake = true, autoDig = false },
}

-- MIGRATIONS[n] upgrades a profile from version n to n+1. Add one entry per
-- schema bump and raise SCHEMA_VERSION; Reconcile() only fills missing keys.
local MIGRATIONS: { [number]: (data: any) -> () } = {
	-- v1 stored pets as plain counts and the equipped pet as a bare id;
	-- v2 tracks sizes, so every v1 pet becomes a Normal one.
	[1] = function(data)
		local pets = {}
		for petId, count in data.purchases.pets do
			if typeof(count) == "number" and count > 0 then
				pets[petId] = { normal = count }
			end
		end
		data.purchases.pets = pets
		local equipped = data.purchases.equippedPet
		if typeof(equipped) == "string" and equipped ~= "" and not string.find(equipped, ":", 1, true) then
			data.purchases.equippedPet = `{equipped}:normal`
		end
	end,
}

local profiles: { [Player]: any } = {}

DataService.onLoaded = Signal.new() :: Signal.Signal<Player, ProfileData>

local function migrate(data: any)
	while data.version < SCHEMA_VERSION do
		local step = MIGRATIONS[data.version]
		assert(step, `No migration from profile version {data.version}`)
		step(data)
		data.version += 1
	end
end

--- Snapshot sent to the owning client. Everything in it is display-only.
function DataService.snapshot(data: ProfileData): { [string]: any }
	return {
		gems = data.gems,
		relics = data.relics,
		meta = data.meta,
		collection = data.collection,
		stats = data.stats,
		purchases = data.purchases,
		settings = data.settings,
	}
end

function DataService.push(player: Player)
	local data = DataService.get(player)
	if data then
		player:SetAttribute("Gems", data.gems)
		player:SetAttribute("Relics", data.relics)
		player:SetAttribute("MetaDig", data.meta.digSpeedLvl)
		player:SetAttribute("MetaPack", data.meta.packLvl)
		player:SetAttribute("Skin", data.purchases.equippedSkin)
		player:SetAttribute("Pet", data.purchases.equippedPet)
		Remotes.get("ProfileSync"):FireClient(player, DataService.snapshot(data))
	end
end

function DataService.get(player: Player): ProfileData?
	local profile = profiles[player]
	if profile and profile:IsActive() then
		return profile.Data
	end
	return nil
end

local function onPlayerAdded(store: any, player: Player)
	local profile = store:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if not profile then
		player:Kick("Your data could not be loaded. Please rejoin.")
		return
	end
	profile:AddUserId(player.UserId)
	-- Migrate before Reconcile so old-shaped tables are converted, not merged.
	if typeof(profile.Data.version) ~= "number" then
		profile.Data.version = 1
	end
	migrate(profile.Data)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Your data was loaded elsewhere. Please rejoin.")
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	profiles[player] = profile
	player:SetAttribute("Loaded", true)
	DataService.push(player)
	DataService.onLoaded:Fire(player, profile.Data)
end

function DataService.init()
	ProfileStore.SetConstant("AUTO_SAVE_PERIOD", GameConfig.Data.AutosaveSeconds)
	local store = ProfileStore.New(GameConfig.Data.StoreName, TEMPLATE)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, store, player)
	end
	Players.PlayerAdded:Connect(function(player)
		onPlayerAdded(store, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			profile:EndSession() -- flushes to the DataStore and releases the lock
			profiles[player] = nil
		end
	end)
end

return DataService
