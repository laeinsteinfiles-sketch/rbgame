--!strict
-- Explorer: ServerScriptService/Services/ToolService (ModuleScript)
-- Every character holds a pickaxe built for its current tier and skin. The
-- tool is server-made so everyone sees it, and the default Animate script's
-- tool animations (idle hold + slash) play from it. It is rebuilt whenever
-- the PickaxeTier or Skin attribute changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelKit = require(ReplicatedStorage.Shared.ModelKit)

local ToolService = {}

local function refresh(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	local tierAttr = player:GetAttribute("PickaxeTier")
	local tier = if typeof(tierAttr) == "number" then tierAttr else 1
	local skinAttr = player:GetAttribute("Skin")
	local skin = if typeof(skinAttr) == "string" then skinAttr else "default"

	local existing = character:FindFirstChild("Pickaxe")
	if existing and existing:IsA("Tool") and existing:GetAttribute("Tier") == tier and existing:GetAttribute("Skin") == skin then
		return
	end
	local containers: { Instance } = { character }
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		table.insert(containers, backpack)
	end
	for _, container in containers do
		for _, child in container:GetChildren() do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end
	end
	local tool = ModelKit.pickaxeTool(tier, skin)
	tool:SetAttribute("Skin", skin)
	tool.Parent = character -- parenting to the character equips it
end

function ToolService.refresh(player: Player)
	refresh(player)
end

function ToolService.init()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 5)
			task.defer(refresh, player)
		end)
		player:GetAttributeChangedSignal("PickaxeTier"):Connect(function()
			refresh(player)
		end)
		player:GetAttributeChangedSignal("Skin"):Connect(function()
			refresh(player)
		end)
		if player.Character then
			task.defer(refresh, player)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return ToolService
