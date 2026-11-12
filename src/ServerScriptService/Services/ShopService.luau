--!strict
-- Explorer: ServerScriptService/Services/ShopService (ModuleScript)
-- Selling and round upgrades. Sale value is computed here from the server's
-- own backpack; the client only says "sell". Stepping on the sell pad sells
-- automatically; the HUD button is the same code path.

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

function ShopService.sell(player: Player, quiet: boolean?)
	local state = RoundState.get(player)
	if not state or RoundState.phase ~= "Active" then
		return
	end
	if state.packUsed <= 0 then
		if not quiet then
			notify(player, "error", "Nothing to sell yet. Go dig some ore!")
		end
		return
	end
	if not PlotService.isNearSellPad(player) then
		if not quiet then
			notify(player, "error", "Sell at the SELL ORE stall on your island")
		end
		return
	end
	local total, count = Economy.backpackValue(state.backpack)
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
		notify(player, "error", "Upgrades open when the round starts")
		return
	end
	if kind ~= "pickaxe" and kind ~= "pack" then
		return
	end
	local tier = if kind == "pickaxe" then state.pickaxeTier else state.packTier
	local cost = Economy.upgradeCost(kind, tier)
	if not cost then
		notify(player, "error", "Already maxed out")
		return
	end
	if state.cash < cost then
		notify(player, "error", "Not enough cash")
		return
	end
	state.cash -= cost
	local name
	if kind == "pickaxe" then
		state.pickaxeTier += 1
		name = GameConfig.Pickaxes[state.pickaxeTier].name
	else
		state.packTier += 1
		name = GameConfig.Packs[state.packTier].name
	end
	RoundState.replicate(player)
	notify(player, "buy", `{name} unlocked!`)
end

function ShopService.init()
	local sellLimiter = RateLimiter.new(GameConfig.RateLimits.SellAll.capacity, GameConfig.RateLimits.SellAll.refill)
	local buyLimiter = RateLimiter.new(GameConfig.RateLimits.BuyUpgrade.capacity, GameConfig.RateLimits.BuyUpgrade.refill)
	local lastPadSell: { [Player]: number } = {}

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

	for _, plot in PlotService.getAll() do
		plot.sellPad.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if not player or plot.owner ~= player then
				return
			end
			local now = os.clock()
			if now - (lastPadSell[player] or 0) < 1.5 then
				return
			end
			lastPadSell[player] = now
			ShopService.sell(player, true)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		sellLimiter:forget(player)
		buyLimiter:forget(player)
		lastPadSell[player] = nil
	end)
end

return ShopService
