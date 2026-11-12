--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Main (LocalScript)
-- Client boot. Controllers are modules so the UI (StarterGui/DigUI) can
-- require the same instances through PlayerScripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local Controllers = script.Parent.Controllers

local CameraRig = require(Controllers.CameraRig)
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
ShaftRenderer.init()
DigController.init()
DrillRig.init()
CameraRig.init()

-- The shaft follows the assigned plot; PlotIndex arrives right after join.
ClientState.onAttr("PlotIndex", function(index)
	if typeof(index) ~= "number" then
		return
	end
	task.spawn(function()
		local model = workspace:WaitForChild(`Plot{index}`, 10)
		local center = ClientState.plotCenter()
		if model and model:IsA("Model") and center then
			ShaftRenderer.hideCap(model)
			ShaftRenderer.setCenter(center)
		end
	end)
end)

-- A new seed means a new round: rebuild from the server's depth.
ClientState.onAttr("Seed", function(seed)
	if typeof(seed) == "number" then
		ShaftRenderer.reset(seed, ClientState.number("Depth", 0))
		LayerFX.setDepth(ClientState.number("Depth", 0), true)
	end
end)

ClientState.onAttr("Traveling", function(direction)
	if typeof(direction) == "string" and direction ~= "" then
		SFX.play("ElevatorMove", { volume = 0.5 })
	end
end)

player.CharacterAdded:Connect(function()
	LayerFX.setDepth(0, true)
end)

local missing = AssetIds.missing()
if #missing > 0 then
	warn(`[DigToTheCore] {#missing} asset slots unset; see ASSETS.md. First: {table.concat(missing, ", ", 1, math.min(8, #missing))}`)
end
