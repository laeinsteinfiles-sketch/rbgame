--!strict
-- Explorer: ServerScriptService/Services/MetaService (ModuleScript)
-- The persistent layer: gems, relics, capped perks, eggs (pets with sizes),
-- skins, collection rewards, settings and gamepass ownership. Nothing here
-- can change who wins a round: the only perk that touches the race is dig
-- speed, capped at +10%.

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

local petById: { [string]: typeof(GameConfig.Pets[1]) } = {}
for _, pet in GameConfig.Pets do
	petById[pet.id] = pet
end
local sizeById: { [string]: typeof(GameConfig.PetSizes[1]) } = {}
for _, size in GameConfig.PetSizes do
	sizeById[size.id] = size
end
local eggById: { [string]: typeof(GameConfig.Eggs[1]) } = {}
for _, egg in GameConfig.Eggs do
	eggById[egg.id] = egg
end
local skinById: { [string]: typeof(GameConfig.Skins[1]) } = {}
for _, skin in GameConfig.Skins do
	skinById[skin.id] = skin
end

local function notify(player: Player, kind: string, message: string)
	Remotes.get("Notify"):FireClient(player, kind, message)
end

--- "mole:huge" -> pet def, size def (nil if either part is unknown).
function MetaService.parsePetKey(key: string): (typeof(GameConfig.Pets[1])?, typeof(GameConfig.PetSizes[1])?)
	local petId, sizeId = string.match(key, "^(%w+):(%w+)$")
	if not petId or not sizeId then
		return nil, nil
	end
	return petById[petId], sizeById[sizeId]
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
		local pet, size = MetaService.parsePetKey(data.purchases.equippedPet)
		if pet and size then
			mult *= 1 + pet.gemBonus * size.mult
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

-- Rolls one entry from a { chance = percent } list.
local function pick<T>(list: { T }, chanceOf: (T) -> number): T
	local roll = rng:NextNumber() * 100
	local acc = 0
	for _, entry in list do
		acc += chanceOf(entry)
		if roll < acc then
			return entry
		end
	end
	return list[#list]
end

local function openEgg(player: Player, eggId: string)
	local data = DataService.get(player)
	local egg = eggById[eggId]
	if not data or not egg then
		return
	end
	if data.gems < egg.cost then
		notify(player, "error", "Not enough gems")
		return
	end
	data.gems -= egg.cost
	local petEntry = pick(egg.pets, function(e)
		return e.chance
	end)
	local size = pick(GameConfig.PetSizes, function(s)
		return s.chance
	end)
	local owned = data.purchases.pets[petEntry.id]
	if not owned then
		owned = {}
		data.purchases.pets[petEntry.id] = owned
	end
	local duplicate = (owned[size.id] or 0) > 0
	owned[size.id] = (owned[size.id] or 0) + 1
	if duplicate then
		data.gems += math.floor(egg.cost * GameConfig.DuplicateRefund)
	end
	data.purchases.eggsOpened += 1
	DataService.push(player)
	Remotes.get("EggResult"):FireClient(player, egg.id, petEntry.id, size.id, duplicate)
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
		if id == "" then
			data.purchases.equippedPet = ""
		else
			local pet, size = MetaService.parsePetKey(id)
			local counts = pet and data.purchases.pets[pet.id]
			if pet and size and counts and (counts[size.id] or 0) > 0 then
				data.purchases.equippedPet = id
			end
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

local function saveSettings(player: Player, settings: any)
	local data = DataService.get(player)
	if not data or typeof(settings) ~= "table" then
		return
	end
	local sfx, shake, autoDig = settings.sfx, settings.shake, settings.autoDig
	if typeof(sfx) == "number" and sfx == sfx then
		data.settings.sfx = math.clamp(sfx, 0, 1)
	end
	if typeof(shake) == "boolean" then
		data.settings.shake = shake
	end
	if typeof(autoDig) == "boolean" then
		data.settings.autoDig = autoDig
	end
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
	local settingsLimiter = RateLimiter.new(limits.SaveSettings.capacity, limits.SaveSettings.refill)

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
		if claimLimiter:allow(player) and typeof(oreId) == "string" and typeof(thresholdIndex) == "number" then
			claimCollection(player, oreId, math.floor(thresholdIndex))
		end
	end)
	Remotes.get("OpenEgg").OnServerEvent:Connect(function(player, eggId)
		if eggLimiter:allow(player) and typeof(eggId) == "string" then
			openEgg(player, eggId)
		end
	end)
	Remotes.get("Equip").OnServerEvent:Connect(function(player, kind, id)
		if equipLimiter:allow(player) and typeof(kind) == "string" and typeof(id) == "string" then
			equip(player, kind, id)
		end
	end)
	Remotes.get("SaveSettings").OnServerEvent:Connect(function(player, settings)
		if settingsLimiter:allow(player) then
			saveSettings(player, settings)
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
		for _, limiter in { buyLimiter, claimLimiter, eggLimiter, equipLimiter, settingsLimiter } do
			limiter:forget(player)
		end
	end)
end

return MetaService
