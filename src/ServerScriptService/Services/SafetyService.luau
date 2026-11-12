--!strict
-- Explorer: ServerScriptService/Services/SafetyService (ModuleScript)
-- Puts characters back when they leave the playable space: off the map
-- edge, into the void, or through a shaft whose local blocks failed to
-- render. They go back to where the server thinks they are (their block or
-- the surface), so a rescue is never a free elevator ride.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local PlotService = require(script.Parent.PlotService)
local RoundState = require(script.Parent.RoundState)

local SafetyService = {}

local G = GameConfig.Geometry
local CHECK_EVERY = 0.5
local WORLD_RADIUS = 900 -- studs from the origin on X or Z
local BELOW_SURFACE = 40 -- studs under the surface outside any shaft
local BELOW_BLOCK = 12 * G.BlockHeight -- studs under the player's own block

local function putBack(player: Player, character: Model, root: BasePart)
	local state = RoundState.get(player)
	local cf = if state and not state.atSurface then PlotService.standingCFrame(player, state.depth) else PlotService.surfaceCFrame(player)
	if cf then
		character:PivotTo(cf)
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function check(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local plot = PlotService.getPlot(player)
	if not character or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 or not plot then
		return
	end
	local state = RoundState.get(player)
	if state and state.travelingUntil > os.clock() then
		return -- the elevator owns the character mid-ride
	end
	local pos = root.Position
	local inShaft = math.abs(pos.X - plot.center.X) <= G.BlockSize and math.abs(pos.Z - plot.center.Z) <= G.BlockSize
	if inShaft then
		local depth = if state then state.depth else 0
		if pos.Y < G.SurfaceY - depth * G.BlockHeight - BELOW_BLOCK then
			putBack(player, character, root)
		end
		return
	end
	if pos.Y < G.SurfaceY - BELOW_SURFACE or math.abs(pos.X) > WORLD_RADIUS or math.abs(pos.Z) > WORLD_RADIUS then
		putBack(player, character, root)
	end
end

function SafetyService.init()
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			for _, player in Players:GetPlayers() do
				check(player)
			end
		end
	end)
end

return SafetyService
