--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Main (LocalScript)
-- Client boot. Controllers are modules so the UI (StarterGui/DigUI) can
-- require the same instances through PlayerScripts.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local Controllers = script.Parent.Controllers

local CameraController = require(Controllers.CameraController)
local ClientState = require(Controllers.ClientState)
local DigController = require(Controllers.DigController)
local DrillRig = require(Controllers.DrillRig)
local LayerFX = require(Controllers.LayerFX)
local SFX = require(Controllers.SFX)
local ShaftRenderer = require(Controllers.ShaftRenderer)

local player = Players.LocalPlayer

ClientState.init()
SFX.init()
LayerFX.init()
CameraController.init()
ShaftRenderer.init()
DigController.init()
DrillRig.init()

-- Saved settings arrive with the first profile sync and every change in the
-- settings screen fires onSettings; the controllers own sound and motion.
local function applySettings()
	SFX.setVolume(ClientState.settings.sfxVolume)
	LayerFX.setShakeEnabled(ClientState.settings.shake)
	CameraController.setEnabled(ClientState.settings.shake)
end
ClientState.onSettings:Connect(applySettings)
applySettings()

-- The shaft is drawn in the assigned island's frame; PlotIndex arrives
-- right after join and the island models are built at server boot.
ClientState.onAttr("PlotIndex", function(index)
	if typeof(index) ~= "number" then
		return
	end
	task.spawn(function()
		local world = Workspace:WaitForChild("World", 10)
		local model = world and world:WaitForChild(`Plot{index}`, 10)
		if model and model:IsA("Model") and player:GetAttribute("PlotIndex") == index then
			ShaftRenderer.hideCap(model)
			ShaftRenderer.setFrame(model:GetPivot())
		end
	end)
end)

-- A new RoundKey means a new round: rebuild the shared course with this
-- player's loot seed from the server's depth.
ClientState.onAttr("RoundKey", function()
	local courseSeed, lootSeed = ClientState.seeds()
	if courseSeed and lootSeed then
		local depth = ClientState.number("Depth", 0)
		ShaftRenderer.reset(courseSeed, lootSeed, depth)
		LayerFX.setDepth(depth, true)
	end
end)

ClientState.onAttr("Traveling", function(direction)
	if typeof(direction) == "string" and direction ~= "" then
		SFX.play("ElevatorMove", { volume = 0.5 })
	end
end)

-- Prompts that only open UI (workshop, egg shrines) carry OpensScreen; the
-- screen itself still goes through the normal server-validated remotes.
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local screen = prompt:GetAttribute("OpensScreen")
	if typeof(screen) == "string" then
		local arg = prompt:GetAttribute("ScreenArg")
		ClientState.onOpenScreen:Fire(screen, if typeof(arg) == "string" then arg else nil)
	end
end)

player.CharacterAdded:Connect(function()
	LayerFX.setDepth(0, true)
end)

local missing = AssetIds.missing()
if #missing > 0 then
	warn(`[DigToTheCore] {#missing} asset slots unset; see ASSETS.md. First: {table.concat(missing, ", ", 1, math.min(8, #missing))}`)
end
