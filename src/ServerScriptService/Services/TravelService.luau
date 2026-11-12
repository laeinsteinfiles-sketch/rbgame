--!strict
-- Explorer: ServerScriptService/Services/TravelService (ModuleScript)
-- The elevator. Travel takes real time that scales with depth, so a bigger
-- pack is worth something and trips are a decision, not a free teleport.
-- Arriving at the top sells the backpack: one tap, one decision.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlotService = require(script.Parent.PlotService)
local RateLimiter = require(script.Parent.RateLimiter)
local RoundState = require(script.Parent.RoundState)
local ShopService = require(script.Parent.ShopService)

local TravelService = {}

local function travel(player: Player, direction: any)
	if direction ~= "up" and direction ~= "down" then
		return
	end
	local state = RoundState.get(player)
	if not state or RoundState.phase ~= "Active" then
		return
	end
	local now = os.clock()
	if state.travelingUntil > now or now - state.lastTravelAt < GameConfig.Travel.Cooldown then
		return
	end
	if direction == "down" and state.depth == 0 then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end

	local duration = Economy.travelTime(state.depth)
	state.lastTravelAt = now
	state.travelingUntil = now + duration
	player:SetAttribute("Traveling", direction)
	player:SetAttribute("TravelEndsAt", Workspace:GetServerTimeNow() + duration)

	task.delay(duration, function()
		if RoundState.get(player) ~= state then
			return -- round reset or player left mid-ride
		end
		state.travelingUntil = 0
		player:SetAttribute("Traveling", "")
		if direction == "up" then
			PlotService.pivot(player, PlotService.surfaceCFrame(player))
			ShopService.sell(player, true)
		else
			PlotService.pivot(player, PlotService.standingCFrame(player, state.depth))
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
