--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/ClientState (ModuleScript)
-- The client's single view of server state: player attributes, round
-- attributes and server->client remotes, exposed as values + signals so the
-- HUD and controllers never touch remotes directly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

local ClientState = {}

local player = Players.LocalPlayer
local roundFolder = ReplicatedStorage:WaitForChild("RoundState") :: Folder

export type Best = { depth: boolean, coreTime: number? }

ClientState.player = player
ClientState.backpack = {} :: Types.Backpack
ClientState.profile = nil :: { [string]: any }?
ClientState.quests = { day = 0, progress = {} :: { [string]: number }, claimed = {} :: { [string]: boolean } }

ClientState.settings = {
	sfxVolume = 0.8,
	shake = true,
	autoDig = false,
}

ClientState.onBackpack = Signal.new() :: Signal.Signal<Types.Backpack, number>
ClientState.onProfile = Signal.new() :: Signal.Signal<{ [string]: any }>
ClientState.onQuests = Signal.new() :: Signal.Signal<()>
ClientState.onNotify = Signal.new() :: Signal.Signal<string, string>
ClientState.onRaceEvent = Signal.new() :: Signal.Signal<string, string, number>
ClientState.onSellResult = Signal.new() :: Signal.Signal<number, number>
ClientState.onDigResult = Signal.new() :: Signal.Signal<number, boolean, number>
ClientState.onResync = Signal.new() :: Signal.Signal<number>
ClientState.onRoundResults = Signal.new() :: Signal.Signal<{ Types.Standing }, number, number, Best?>
ClientState.onMegaEvent = Signal.new() :: Signal.Signal<string, number>
ClientState.onEggResult = Signal.new() :: Signal.Signal<string, string, string, boolean>
ClientState.onSettings = Signal.new() :: Signal.Signal<()>
-- Fired by world prompts (workshop, egg shrine) to open a screen.
ClientState.onOpenScreen = Signal.new() :: Signal.Signal<string, string?>

function ClientState.attr(name: string): any
	return player:GetAttribute(name)
end

function ClientState.number(name: string, default: number?): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else (default or 0)
end

function ClientState.onAttr(name: string, fn: (any) -> ()): RBXScriptConnection
	fn(player:GetAttribute(name))
	return player:GetAttributeChangedSignal(name):Connect(function()
		fn(player:GetAttribute(name))
	end)
end

function ClientState.round(name: string): any
	return roundFolder:GetAttribute(name)
end

function ClientState.onRound(name: string, fn: (any) -> ()): RBXScriptConnection
	fn(roundFolder:GetAttribute(name))
	return roundFolder:GetAttributeChangedSignal(name):Connect(function()
		fn(roundFolder:GetAttribute(name))
	end)
end

function ClientState.phase(): string
	local phase = roundFolder:GetAttribute("Phase")
	return if typeof(phase) == "string" then phase else "Lobby"
end

--- Seconds left in the current phase using the server clock.
function ClientState.phaseRemaining(): number
	local endsAt = roundFolder:GetAttribute("PhaseEndsAt")
	if typeof(endsAt) ~= "number" then
		return 0
	end
	return math.max(0, endsAt - Workspace:GetServerTimeNow())
end

function ClientState.megaRemaining(): number
	local endsAt = roundFolder:GetAttribute("MegaEndsAt")
	if typeof(endsAt) ~= "number" or roundFolder:GetAttribute("MegaActive") ~= true then
		return 0
	end
	return math.max(0, endsAt - Workspace:GetServerTimeNow())
end

--- (courseSeed, lootSeed) for the current round, from the atomic RoundKey.
function ClientState.seeds(): (number?, number?)
	local key = player:GetAttribute("RoundKey")
	if typeof(key) ~= "string" then
		return nil, nil
	end
	local course, loot = string.match(key, "^(%d+):(%d+)$")
	return tonumber(course), tonumber(loot)
end

function ClientState.ownsPass(name: string): boolean
	local passes = player:GetAttribute("Passes")
	if typeof(passes) ~= "string" then
		return false
	end
	for entry in string.gmatch(passes, "[^,]+") do
		if entry == name then
			return true
		end
	end
	return false
end

function ClientState.plotModel(): Model?
	local index = player:GetAttribute("PlotIndex")
	local world = Workspace:FindFirstChild("World")
	if typeof(index) ~= "number" or not world then
		return nil
	end
	local model = world:FindFirstChild(`Plot{index}`)
	return if model and model:IsA("Model") then model else nil
end

--- The island's frame: shaft centre on the surface, -Z facing the hub.
function ClientState.plotFrame(): CFrame?
	local model = ClientState.plotModel()
	return if model then model:GetPivot() else nil
end

function ClientState.plotCenter(): Vector3?
	local frame = ClientState.plotFrame()
	return if frame then frame.Position else nil
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end
ClientState.rootPart = rootPart

function ClientState.isNearSellPad(): boolean
	local model = ClientState.plotModel()
	local pad = model and model:FindFirstChild("SellPad", true)
	local root = rootPart()
	if not pad or not pad:IsA("BasePart") or not root then
		return false
	end
	return (root.Position - pad.Position).Magnitude <= GameConfig.Geometry.SellRadius
end

function ClientState.isTraveling(): boolean
	local traveling = player:GetAttribute("Traveling")
	return typeof(traveling) == "string" and traveling ~= ""
end

--- True while the character is at island height (not down the shaft).
function ClientState.atSurface(): boolean
	local root = rootPart()
	return root ~= nil and root.Position.Y > GameConfig.Geometry.SurfaceY - 2
end

--- True while the character is inside its own shaft below the surface.
function ClientState.inShaft(): boolean
	local root = rootPart()
	local frame = ClientState.plotFrame()
	if not root or not frame then
		return false
	end
	local rel = frame:PointToObjectSpace(root.Position)
	local half = GameConfig.Geometry.BlockSize / 2 + 1
	return rel.Y < -2 and math.abs(rel.X) < half and math.abs(rel.Z) < half
end

function ClientState.send(name: string, ...: any)
	Remotes.get(name):FireServer(...)
end

function ClientState.saveSettings()
	ClientState.onSettings:Fire()
	ClientState.send("SaveSettings", {
		sfx = ClientState.settings.sfxVolume,
		shake = ClientState.settings.shake,
		autoDig = ClientState.settings.autoDig,
	})
end

function ClientState.init()
	local settingsLoaded = false
	Remotes.get("BackpackSync").OnClientEvent:Connect(function(backpack, used)
		ClientState.backpack = backpack
		ClientState.onBackpack:Fire(backpack, used)
	end)
	Remotes.get("ProfileSync").OnClientEvent:Connect(function(snapshot)
		ClientState.profile = snapshot
		-- Saved settings apply once per session; later syncs must not undo
		-- a slider the player is dragging.
		if not settingsLoaded and typeof(snapshot.settings) == "table" then
			settingsLoaded = true
			ClientState.settings.sfxVolume = snapshot.settings.sfx
			ClientState.settings.shake = snapshot.settings.shake
			ClientState.settings.autoDig = snapshot.settings.autoDig
			ClientState.onSettings:Fire()
		end
		ClientState.onProfile:Fire(snapshot)
	end)
	Remotes.get("QuestSync").OnClientEvent:Connect(function(day, progress, claimed)
		ClientState.quests = { day = day, progress = progress, claimed = claimed }
		ClientState.onQuests:Fire()
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, message)
		ClientState.onNotify:Fire(kind, message)
	end)
	Remotes.get("RaceEvent").OnClientEvent:Connect(function(kind, name, value)
		ClientState.onRaceEvent:Fire(kind, name, value)
	end)
	Remotes.get("SellResult").OnClientEvent:Connect(function(total, count)
		ClientState.onSellResult:Fire(total, count)
	end)
	Remotes.get("DigResult").OnClientEvent:Connect(function(index, accepted, finalDepth)
		ClientState.onDigResult:Fire(index, accepted, finalDepth)
	end)
	Remotes.get("Resync").OnClientEvent:Connect(function(depth)
		ClientState.onResync:Fire(depth)
	end)
	Remotes.get("RoundResults").OnClientEvent:Connect(function(standings, placement, gems, best)
		ClientState.onRoundResults:Fire(standings, placement, gems, best)
	end)
	Remotes.get("MegaEvent").OnClientEvent:Connect(function(kind, index)
		ClientState.onMegaEvent:Fire(kind, index)
	end)
	Remotes.get("EggResult").OnClientEvent:Connect(function(eggId, petId, sizeId, duplicate)
		ClientState.onEggResult:Fire(eggId, petId, sizeId, duplicate)
	end)
end

return ClientState
