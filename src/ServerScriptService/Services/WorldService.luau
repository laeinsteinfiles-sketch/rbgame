--!strict
-- Explorer: ServerScriptService/Services/WorldService (ModuleScript)
-- Builds the world once at boot: the hub at the origin and twelve islands
-- on a ring around it, each facing the hub. Everything here is static and
-- replicated; per-player shafts are rendered locally by each client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Hub = require(ReplicatedStorage.Shared.Models.Hub)
local Island = require(ReplicatedStorage.Shared.Models.Island)

local WorldService = {}

export type IslandInfo = Island.Built & { index: number, frame: CFrame }

WorldService.islands = {} :: { IslandInfo }
WorldService.hub = (nil :: any) :: Hub.Built

local function addClouds()
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain and not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.45
		clouds.Color = Color3.fromHex("F2E6D3")
		clouds.Parent = terrain
	end
end

function WorldService.init()
	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = Workspace

	local hub = Hub.build()
	hub.model.Parent = world
	WorldService.hub = hub

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "Spawn"
	spawnLocation.Anchored = true
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	spawnLocation.Size = Vector3.new(6, 1, 6)
	spawnLocation.CFrame = hub.spawn
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Parent = world

	local count = GameConfig.Geometry.MaxPlayers
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local position = Vector3.new(math.cos(angle), 0, math.sin(angle)) * GameConfig.World.RingRadius
		local frame = CFrame.lookAt(position, Vector3.zero)
		local built = Island.build(i)
		built.model:PivotTo(frame)
		built.model:SetAttribute("OwnerUserId", 0)
		built.model.Parent = world
		local info = table.clone(built) :: any
		info.index = i
		info.frame = frame
		WorldService.islands[i] = info
	end

	addClouds()
end

return WorldService
