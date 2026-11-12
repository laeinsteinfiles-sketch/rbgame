--!strict
-- Explorer: ServerScriptService/Services/TravelService (ModuleScript)
-- The lift. Riding takes real time that scales with depth, so a bigger pack
-- is worth something and trips are a decision, not a free teleport. "Down"
-- returns you to the cell you rode up from (or your deepest dig).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlotService = require(script.Parent.PlotService)
local RateLimiter = require(script.Parent.RateLimiter)
local RoundState = require(script.Parent.RoundState)

local TravelService = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

--- The deepest open cell we can put the player back into.
local function returnCell(state: RoundState.PlayerRound): (number, number)
	if state.lastRow > 0 and RoundState.isOpen(state, state.lastCol, state.lastRow) then
		return state.lastCol, state.lastRow
	end
	local bestCol, bestRow = math.ceil(Grid.COLS / 2), 0
	for key in state.opened do
		local col, row = Grid.unkey(key)
		if row > bestRow then
			bestCol, bestRow = col, row
		end
	end
	return bestCol, bestRow
end

local function travel(player: Player, direction: any)
	if direction ~= "up" and direction ~= "down" then
		return
	end
	local state = RoundState.get(player)
	local plot = PlotService.getPlot(player)
	local root = rootOf(player)
	if not state or not plot or not root or RoundState.phase ~= "Active" then
		return
	end
	local now = os.clock()
	if state.travelingUntil > now or now - state.lastTravelAt < GameConfig.Travel.Cooldown then
		return
	end
	local underground = root.Position.Y < GameConfig.Geometry.SurfaceY - 2
	if direction == "up" then
		if not underground then
			return
		end
		local col = Grid.colAt(root.Position.X - plot.origin.X)
		local row = Grid.rowAt(root.Position.Y)
		if col >= 1 and col <= Grid.COLS and row >= 1 then
			state.lastCol, state.lastRow = col, row
		end
	elseif underground or state.depth <= 0 then
		return
	end

	local _, targetRow = returnCell(state)
	local duration = Economy.travelTime(if direction == "up" then state.depth else targetRow)
	state.lastTravelAt = now
	state.travelingUntil = now + duration
	player:SetAttribute("Traveling", direction)
	player:SetAttribute("TravelEndsAt", workspace:GetServerTimeNow() + duration)

	task.delay(duration, function()
		if RoundState.get(player) ~= state then
			return -- round reset or player left mid-ride
		end
		state.travelingUntil = 0
		player:SetAttribute("Traveling", "")
		local target: CFrame?
		if direction == "up" then
			target = PlotService.surfaceCFrame(player)
		else
			local col, row = returnCell(state)
			target = PlotService.cellCFrame(player, col, row)
		end
		local character = player.Character
		if target and character then
			character:PivotTo(target)
		end
	end)
end

function TravelService.init()
	local limiter = RateLimiter.new(GameConfig.RateLimits.Travel.capacity, GameConfig.RateLimits.Travel.refill)
	Remotes.get("Travel").OnServerEvent:Connect(function(player, direction)
		if limiter:allow(player) then
			travel(player, direction)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player)
	end)
end

return TravelService
