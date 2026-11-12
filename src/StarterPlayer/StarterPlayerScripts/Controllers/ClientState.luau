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
ClientState.onSellResult = Signal.new() :: Signal.Signal<number, number>
ClientState.onDigResult = Signal.new() :: Signal.Signal<number, boolean, Types.BlockRoll?, number>
ClientState.onResync = Signal.new() :: Signal.Signal<number>
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
	if typeof(index) ~= "number" then
		return nil
	end
	local model = Workspace:FindFirstChild(`Plot{index}`)
	return if model and model:IsA("Model") then model else nil
end

function ClientState.plotCenter(): Vector3?
	local model = ClientState.plotModel()
	local cap = model and model:FindFirstChild("ShaftCap")
	if cap and cap:IsA("BasePart") then
		return Vector3.new(cap.Position.X, GameConfig.Geometry.SurfaceY, cap.Position.Z)
	end
	return nil
end

function ClientState.isNearSellPad(): boolean
	local model = ClientState.plotModel()
	local pad = model and model:FindFirstChild("SellPad")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not pad or not pad:IsA("BasePart") or not root or not root:IsA("BasePart") then
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
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return root.Position.Y > GameConfig.Geometry.SurfaceY - 2
end

function ClientState.send(name: string, ...: any)
	Remotes.get(name):FireServer(...)
end

function ClientState.init()
	Remotes.get("BackpackSync").OnClientEvent:Connect(function(backpack, used)
		ClientState.backpack = backpack
		ClientState.onBackpack:Fire(backpack, used)
	end)
	Remotes.get("ProfileSync").OnClientEvent:Connect(function(snapshot)
		ClientState.profile = snapshot
		ClientState.onProfile:Fire(snapshot)
	end)
	Remotes.get("QuestSync").OnClientEvent:Connect(function(day, progress, claimed)
		ClientState.quests = { day = day, progress = progress, claimed = claimed }
		ClientState.onQuests:Fire()
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, message)
		ClientState.onNotify:Fire(kind, message)
	end)
	Remotes.get("SellResult").OnClientEvent:Connect(function(total, count)
		ClientState.onSellResult:Fire(total, count)
	end)
	Remotes.get("DigResult").OnClientEvent:Connect(function(index, accepted, roll, depth)
		ClientState.onDigResult:Fire(index, accepted, roll, depth)
	end)
	Remotes.get("Resync").OnClientEvent:Connect(function(depth)
		ClientState.onResync:Fire(depth)
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
