--!strict
-- Explorer: ServerScriptService/Services/ShopService (ModuleScript)
-- SellAll and BuyUpgrade. Sale value is computed here from the server's own
-- backpack; the client only says "sell".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlotService = require(script.Parent.PlotService)
local QuestService = require(script.Parent.QuestService)
local RateLimiter = require(script.Parent.RateLimiter)
local RoundState = require(script.Parent.RoundState)

local ShopService = {}

local function notify(player: Player, kind: string, message: string)
	Remotes.get("Notify"):FireClient(player, kind, message)
end

function ShopService.sell(player: Player)
	local state = RoundState.get(player)
	if not state or RoundState.phase ~= "Active" then
		return
	end
	if state.packUsed <= 0 then
		notify(player, "error", "Nothing to sell")
		return
	end
	if not PlotService.isNearSellPad(player) then
		notify(player, "error", "Sell at your trading post")
		return
	end
	local total, count = 0, 0
	for oreId, mutations in state.backpack do
		for mutationId, n in mutations do
			total += Economy.oreValue(oreId, mutationId) * n
			count += n
		end
	end
	state.backpack = {}
	state.packUsed = 0
	state.cash += total
	state.cashEarned += total
	QuestService.add(player, "sell", total)
	RoundState.replicate(player)
	RoundState.syncBackpack(player)
	Remotes.get("SellResult"):FireClient(player, total, count)
end

local function buy(player: Player, kind: any)
	local state = RoundState.get(player)
	if not state or RoundState.phase ~= "Active" then
		return
	end
	if kind ~= "drill" and kind ~= "pack" then
		return
	end
	local tier = if kind == "drill" then state.drillTier else state.packTier
	local cost = Economy.upgradeCost(kind, tier)
	if not cost then
		notify(player, "error", "Already maxed")
		return
	end
	if state.cash < cost then
		notify(player, "error", "Not enough cash")
		return
	end
	state.cash -= cost
	local name
	if kind == "drill" then
		state.drillTier += 1
		name = GameConfig.Drills[state.drillTier].name
	else
		state.packTier += 1
		name = GameConfig.Packs[state.packTier].name
	end
	RoundState.replicate(player)
	notify(player, "buy", name)
end

function ShopService.init()
	local sellLimiter = RateLimiter.new(GameConfig.RateLimits.SellAll.capacity, GameConfig.RateLimits.SellAll.refill)
	local buyLimiter = RateLimiter.new(GameConfig.RateLimits.BuyUpgrade.capacity, GameConfig.RateLimits.BuyUpgrade.refill)

	Remotes.get("SellAll").OnServerEvent:Connect(function(player)
		if sellLimiter:allow(player) then
			ShopService.sell(player)
		end
	end)
	Remotes.get("BuyUpgrade").OnServerEvent:Connect(function(player, kind)
		if buyLimiter:allow(player) then
			buy(player, kind)
		end
	end)

	-- The pad prompt is the same code path as the HUD button.
	for _, plot in PlotService.getAll() do
		local prompt = plot.sellPad:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				if plot.owner == player and sellLimiter:allow(player) then
					ShopService.sell(player)
				end
			end)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		sellLimiter:forget(player)
		buyLimiter:forget(player)
	end)
end

return ShopService
