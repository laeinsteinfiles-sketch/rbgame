--!strict
-- Explorer: ServerScriptService/Services/MetaService (ModuleScript)
-- The persistent layer: gems, relics, capped perks, pets, skins, collection
-- rewards and gamepass ownership. Nothing here can change who wins a round:
-- the only perk that touches the race is dig speed, capped at +10%.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Signal)
local DataService = require(script.Parent.DataService)
local RateLimiter = require(script.Parent.RateLimiter)

local MetaService = {}

export type PassName = "DoubleGems" | "AutoDig" | "BigPack" | "DrillSkins"

-- Fired after a perk purchase so RoundState can re-replicate power/capacity.
MetaService.onPerkChanged = Signal.new() :: Signal.Signal<Player>
-- Fired once gamepass ownership is known for a player (after the profile loads).
MetaService.onPassesRefreshed = Signal.new() :: Signal.Signal<Player>

local passCache: { [Player]: { [string]: boolean } } = {}
local rng = Random.new()

local petById: { [string]: typeof(GameConfig.Pets.List[1]) } = {}
for _, pet in GameConfig.Pets.List do
	petById[pet.id] = pet
end
local skinById: { [string]: typeof(GameConfig.Skins[1]) } = {}
for _, skin in GameConfig.Skins do
	skinById[skin.id] = skin
end

local function notify(player: Player, kind: string, message: string)
	Remotes.get("Notify"):FireClient(player, kind, message)
end

local function refreshPasses(player: Player)
	local owned: { [string]: boolean } = {}
	for name, id in AssetIds.Gamepasses do
		if AssetIds.isSet(id) then
			local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
			owned[name] = ok and result == true
		else
			owned[name] = false
		end
	end
	passCache[player] = owned
	local names = {}
	for name, has in owned do
		if has then
			table.insert(names, name)
		end
	end
	table.sort(names)
	player:SetAttribute("Passes", table.concat(names, ","))
	MetaService.onPassesRefreshed:Fire(player)
end

function MetaService.ownsPass(player: Player, name: PassName): boolean
	local owned = passCache[player]
	return owned ~= nil and owned[name] == true
end

function MetaService.gemMultiplier(player: Player): number
	local mult = if MetaService.ownsPass(player, "DoubleGems") then 2 else 1
	local data = DataService.get(player)
	if data then
		local pet = petById[data.purchases.equippedPet]
		if pet then
			mult *= 1 + pet.gemBonus
		end
	end
	return mult
end

--- Grants gems with the player's multiplier applied. Returns the amount given.
function MetaService.awardGems(player: Player, base: number, reason: string): number
	local data = DataService.get(player)
	if not data or base <= 0 then
		return 0
	end
	local amount = math.floor(base * MetaService.gemMultiplier(player) + 0.5)
	data.gems += amount
	DataService.push(player)
	notify(player, "gems", `+{amount} gems · {reason}`)
	return amount
end

function MetaService.addRelic(player: Player, amount: number)
	local data = DataService.get(player)
	if data then
		data.relics += amount
		DataService.push(player)
	end
end

local function buyPerk(player: Player, kind: "digSpeed" | "pack")
	local data = DataService.get(player)
	if not data then
		return
	end
	local level = if kind == "digSpeed" then data.meta.digSpeedLvl else data.meta.packLvl
	local cost = Economy.metaCost(kind, level)
	if not cost then
		notify(player, "error", "Already at the cap")
		return
	end
	if data.gems < cost then
		notify(player, "error", "Not enough gems")
		return
	end
	data.gems -= cost
	if kind == "digSpeed" then
		data.meta.digSpeedLvl += 1
	else
		data.meta.packLvl += 1
	end
	DataService.push(player)
	MetaService.onPerkChanged:Fire(player)
	notify(player, "buy", if kind == "digSpeed" then "Drill tuning upgraded" else "Pack frame upgraded")
end

local function buySkin(player: Player, skinId: string)
	local data = DataService.get(player)
	local skin = skinById[skinId]
	if not data or not skin then
		return
	end
	if data.purchases.skins[skinId] then
		notify(player, "error", "Already owned")
		return
	end
	if data.relics < skin.relics then
		notify(player, "error", "Not enough relics")
		return
	end
	data.relics -= skin.relics
	data.purchases.skins[skinId] = true
	DataService.push(player)
	notify(player, "buy", `{skin.name} unlocked`)
end

local function openEgg(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	if data.gems < GameConfig.Pets.EggCost then
		notify(player, "error", "Not enough gems")
		return
	end
	data.gems -= GameConfig.Pets.EggCost

	local roll = rng:NextNumber() * 100
	local acc = 0
	local tier = GameConfig.Pets.Odds[1].tier
	for _, entry in GameConfig.Pets.Odds do
		acc += entry.chance
		if roll < acc then
			tier = entry.tier
			break
		end
	end
	local candidates = {}
	for _, pet in GameConfig.Pets.List do
		if pet.tier == tier then
			table.insert(candidates, pet)
		end
	end
	local pet = candidates[rng:NextInteger(1, #candidates)]
	local duplicate = (data.purchases.pets[pet.id] or 0) > 0
	data.purchases.pets[pet.id] = (data.purchases.pets[pet.id] or 0) + 1
	if duplicate then
		-- Duplicates refund a third of the egg so repeat rolls never feel like nothing.
		data.gems += math.floor(GameConfig.Pets.EggCost / 3)
	end
	DataService.push(player)
	Remotes.get("EggResult"):FireClient(player, pet.id, duplicate)
end

local function equip(player: Player, kind: string, id: string)
	local data = DataService.get(player)
	if not data then
		return
	end
	if kind == "skin" then
		local owned = data.purchases.skins[id] or MetaService.ownsPass(player, "DrillSkins")
		if skinById[id] and owned then
			data.purchases.equippedSkin = id
		end
	elseif kind == "pet" then
		if id == "" or (petById[id] and (data.purchases.pets[id] or 0) > 0) then
			data.purchases.equippedPet = id
		end
	end
	DataService.push(player)
end

local function claimCollection(player: Player, oreId: string, thresholdIndex: number)
	local data = DataService.get(player)
	if not data or not Economy.oreById[oreId] then
		return
	end
	local threshold = GameConfig.Collection.Thresholds[thresholdIndex]
	if not threshold then
		return
	end
	local key = `{oreId}:{thresholdIndex}`
	if data.purchases.claimedCollection[key] then
		return
	end
	local entry = data.collection[oreId]
	if not entry or entry.count < threshold then
		notify(player, "error", "Not collected enough yet")
		return
	end
	data.purchases.claimedCollection[key] = true
	MetaService.awardGems(player, Economy.collectionReward(oreId, thresholdIndex), `{Economy.oreById[oreId].name} collection`)
end

--- Records a collected ore in the persistent collection book.
function MetaService.recordCollect(player: Player, oreId: string, mutationId: string)
	local data = DataService.get(player)
	if not data then
		return
	end
	local entry = data.collection[oreId]
	if not entry then
		entry = { count = 0, mutations = {} }
		data.collection[oreId] = entry
	end
	entry.count += 1
	entry.mutations[mutationId] = (entry.mutations[mutationId] or 0) + 1
end

function MetaService.init()
	local limits = GameConfig.RateLimits
	local buyLimiter = RateLimiter.new(limits.BuyMeta.capacity, limits.BuyMeta.refill)
	local claimLimiter = RateLimiter.new(limits.ClaimCollection.capacity, limits.ClaimCollection.refill)
	local eggLimiter = RateLimiter.new(limits.OpenEgg.capacity, limits.OpenEgg.refill)
	local equipLimiter = RateLimiter.new(limits.Equip.capacity, limits.Equip.refill)

	Remotes.get("BuyMeta").OnServerEvent:Connect(function(player, kind, id)
		if not buyLimiter:allow(player) then
			return
		end
		if kind == "digSpeed" or kind == "pack" then
			buyPerk(player, kind)
		elseif kind == "skin" and typeof(id) == "string" then
			buySkin(player, id)
		end
	end)

	Remotes.get("ClaimCollection").OnServerEvent:Connect(function(player, oreId, thresholdIndex)
		if not claimLimiter:allow(player) then
			return
		end
		if typeof(oreId) == "string" and typeof(thresholdIndex) == "number" then
			claimCollection(player, oreId, math.floor(thresholdIndex))
		end
	end)

	Remotes.get("OpenEgg").OnServerEvent:Connect(function(player)
		if eggLimiter:allow(player) then
			openEgg(player)
		end
	end)

	Remotes.get("Equip").OnServerEvent:Connect(function(player, kind, id)
		if equipLimiter:allow(player) and typeof(kind) == "string" and typeof(id) == "string" then
			equip(player, kind, id)
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _passId, purchased)
		if purchased then
			refreshPasses(player)
		end
	end)

	DataService.onLoaded:Connect(function(player)
		refreshPasses(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
		buyLimiter:forget(player)
		claimLimiter:forget(player)
		eggLimiter:forget(player)
		equipLimiter:forget(player)
	end)
end

return MetaService
