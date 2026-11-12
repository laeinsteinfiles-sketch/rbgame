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

export type Settings = { music: number, sfx: number, shake: boolean, autoDig: boolean }

export type ProfileData = {
	version: number,
	gems: number,
	relics: number,
	meta: { digSpeedLvl: number, packLvl: number },
	collection: { [string]: CollectionEntry },
	quests: { day: number, progress: { [string]: number }, claimed: { [string]: boolean } },
	stats: { rounds: number, wins: number, maxDepth: number, cores: number },
	settings: Settings,
	purchases: {
		skins: { [string]: boolean },
		pets: { [string]: number },
		claimedCollection: { [string]: boolean },
		equippedSkin: string,
		equippedPet: string,
	},
}

local SCHEMA_VERSION = 1

local TEMPLATE: ProfileData = {
	version = SCHEMA_VERSION,
	gems = 0,
	relics = 0,
	meta = { digSpeedLvl = 0, packLvl = 0 },
	collection = {},
	quests = { day = 0, progress = {}, claimed = {} },
	stats = { rounds = 0, wins = 0, maxDepth = 0, cores = 0 },
	settings = { music = 0.5, sfx = 0.8, shake = true, autoDig = false },
	purchases = {
		skins = { default = true },
		pets = {},
		claimedCollection = {},
		equippedSkin = "default",
		equippedPet = "",
	},
}

-- MIGRATIONS[n] upgrades a profile from version n to n+1. Add one entry per
-- schema bump and raise SCHEMA_VERSION; Reconcile() only fills missing keys.
local MIGRATIONS: { [number]: (data: any) -> () } = {}

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
		settings = data.settings,
		purchases = data.purchases,
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

function DataService.waitFor(player: Player, timeout: number): ProfileData?
	local deadline = os.clock() + timeout
	while os.clock() < deadline and player.Parent == Players do
		local data = DataService.get(player)
		if data then
			return data
		end
		task.wait(0.1)
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
	migrate(profile.Data)
	profiles[player] = profile
	player:SetAttribute("Loaded", true)
	DataService.push(player)
	DataService.onLoaded:Fire(player, profile.Data)
end

function DataService.init()
	ProfileStore.SetConstant("AUTO_SAVE_PERIOD", GameConfig.Data.AutosaveSeconds)
	local store = ProfileStore.New(GameConfig.Data.StoreName, TEMPLATE)

	-- Settings are client preferences; validate shape and clamp, never trust.
	local lastSave: { [Player]: number } = {}
	Remotes.get("SaveSettings").OnServerEvent:Connect(function(player, incoming)
		local now = os.clock()
		if now - (lastSave[player] or 0) < 1 or typeof(incoming) ~= "table" then
			return
		end
		lastSave[player] = now
		local data = DataService.get(player)
		if not data then
			return
		end
		local s = data.settings
		if typeof(incoming.music) == "number" and incoming.music == incoming.music then
			s.music = math.clamp(incoming.music, 0, 1)
		end
		if typeof(incoming.sfx) == "number" and incoming.sfx == incoming.sfx then
			s.sfx = math.clamp(incoming.sfx, 0, 1)
		end
		if typeof(incoming.shake) == "boolean" then
			s.shake = incoming.shake
		end
		if typeof(incoming.autoDig) == "boolean" then
			s.autoDig = incoming.autoDig
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSave[player] = nil
	end)

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
