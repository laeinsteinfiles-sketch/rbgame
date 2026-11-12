--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/ClientState (ModuleScript)
-- The client's single view of server state: player attributes, round
-- attributes and server->client remotes, exposed as values + signals so the
-- HUD and controllers never touch remotes directly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

local ClientState = {}

local player = Players.LocalPlayer
local roundFolder = ReplicatedStorage:WaitForChild("RoundState") :: Folder
local G = GameConfig.Geometry

export type Settings = { music: number, sfx: number, shake: boolean, autoDig: boolean }

ClientState.player = player
ClientState.backpack = {} :: Types.Backpack
ClientState.profile = nil :: { [string]: any }?
ClientState.quests = { day = 0, progress = {} :: { [string]: number }, claimed = {} :: { [string]: boolean } }
ClientState.settings = { music = 0.5, sfx = 0.8, shake = true, autoDig = false } :: Settings

ClientState.onBackpack = Signal.new() :: Signal.Signal<Types.Backpack, number>
ClientState.onProfile = Signal.new() :: Signal.Signal<{ [string]: any }>
ClientState.onQuests = Signal.new() :: Signal.Signal<()>
ClientState.onNotify = Signal.new() :: Signal.Signal<string, string>
ClientState.onFeed = Signal.new() :: Signal.Signal<string, string, string>
ClientState.onReward = Signal.new() :: Signal.Signal<string, number, string>
ClientState.onSellResult = Signal.new() :: Signal.Signal<number, number>
ClientState.onDigResult = Signal.new() :: Signal.Signal<number, number, boolean, number, { number }?>
ClientState.onResync = Signal.new() :: Signal.Signal<number, number, { number }>
ClientState.onRoundResults = Signal.new() :: Signal.Signal<{ Types.Standing }, number, number>
ClientState.onMegaEvent = Signal.new() :: Signal.Signal<string, number>
ClientState.onEggResult = Signal.new() :: Signal.Signal<string, boolean>
ClientState.onSettings = Signal.new() :: Signal.Signal<()>

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

function ClientState.travelRemaining(): number
	local endsAt = player:GetAttribute("TravelEndsAt")
	if typeof(endsAt) ~= "number" or not ClientState.isTraveling() then
		return 0
	end
	return math.max(0, endsAt - Workspace:GetServerTimeNow())
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

--- The plot origin (centre of the mine's top edge), computed from the plot
--- index so it never depends on surface parts having streamed in.
function ClientState.plotOrigin(): Vector3?
	local index = player:GetAttribute("PlotIndex")
	if typeof(index) ~= "number" then
		return nil
	end
	local x, z = Grid.plotOrigin(index)
	return Vector3.new(x, 0, z)
end

function ClientState.plotModel(): Model?
	local index = player:GetAttribute("PlotIndex")
	if typeof(index) ~= "number" then
		return nil
	end
	local model = Workspace:FindFirstChild(`Plot{index}`)
	return if model and model:IsA("Model") then model else nil
end

function ClientState.rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function nearPad(def: { x: number, z: number, radius: number }): boolean
	local origin = ClientState.plotOrigin()
	local root = ClientState.rootPart()
	if not origin or not root then
		return false
	end
	local dx = root.Position.X - (origin.X + def.x)
	local dz = root.Position.Z - (origin.Z + def.z)
	return math.sqrt(dx * dx + dz * dz) <= def.radius + 1 and math.abs(root.Position.Y - G.SurfaceY) < 8
end

function ClientState.isNearSellPad(): boolean
	return nearPad(G.SellPad)
end

function ClientState.isNearShopPad(): boolean
	return nearPad(G.ShopPad)
end

function ClientState.isTraveling(): boolean
	local traveling = player:GetAttribute("Traveling")
	return typeof(traveling) == "string" and traveling ~= ""
end

--- True while the character is at island height (not down the mine).
function ClientState.atSurface(): boolean
	local root = ClientState.rootPart()
	return root ~= nil and root.Position.Y > G.SurfaceY - 1.5
end

function ClientState.send(name: string, ...: any)
	Remotes.get(name):FireServer(...)
end

function ClientState.saveSettings()
	ClientState.onSettings:Fire()
	ClientState.send("SaveSettings", ClientState.settings)
end

function ClientState.init()
	Remotes.get("BackpackSync").OnClientEvent:Connect(function(backpack, used)
		ClientState.backpack = backpack
		ClientState.onBackpack:Fire(backpack, used)
	end)
	Remotes.get("ProfileSync").OnClientEvent:Connect(function(snapshot)
		local first = ClientState.profile == nil
		ClientState.profile = snapshot
		if first and typeof(snapshot) == "table" and typeof(snapshot.settings) == "table" then
			local s = snapshot.settings
			local settings = ClientState.settings
			if typeof(s.music) == "number" then
				settings.music = s.music
			end
			if typeof(s.sfx) == "number" then
				settings.sfx = s.sfx
			end
			if typeof(s.shake) == "boolean" then
				settings.shake = s.shake
			end
			if typeof(s.autoDig) == "boolean" then
				settings.autoDig = s.autoDig
			end
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
	Remotes.get("Feed").OnClientEvent:Connect(function(kind, name, text)
		ClientState.onFeed:Fire(kind, name, text)
	end)
	Remotes.get("Reward").OnClientEvent:Connect(function(kind, amount, label)
		ClientState.onReward:Fire(kind, amount, label)
	end)
	Remotes.get("SellResult").OnClientEvent:Connect(function(total, count)
		ClientState.onSellResult:Fire(total, count)
	end)
	Remotes.get("DigResult").OnClientEvent:Connect(function(col, row, accepted, depth, extra)
		ClientState.onDigResult:Fire(col, row, accepted, depth, extra)
	end)
	Remotes.get("Resync").OnClientEvent:Connect(function(seed, depth, keys)
		ClientState.onResync:Fire(seed, depth, keys)
	end)
	Remotes.get("RoundResults").OnClientEvent:Connect(function(standings, placement, gems)
		ClientState.onRoundResults:Fire(standings, placement, gems)
	end)
	Remotes.get("MegaEvent").OnClientEvent:Connect(function(kind, index)
		ClientState.onMegaEvent:Fire(kind, index)
	end)
	Remotes.get("EggResult").OnClientEvent:Connect(function(petId, duplicate)
		ClientState.onEggResult:Fire(petId, duplicate)
	end)
end

return ClientState
