--!strict
-- Explorer: ReplicatedStorage/Shared/Quests (ModuleScript)
-- Daily quest pool. The day's three quests are picked deterministically from
-- the UTC day number so every server and every client agree without a store.

local Hash = require(script.Parent.Hash)
local Types = require(script.Parent.Types)

type QuestDef = Types.QuestDef

local Quests = {}

local POOL: { QuestDef } = {
	{ id = "dig_150", kind = "dig", goal = 150, reward = 15, title = "Dig 150 blocks" },
	{ id = "dig_500", kind = "dig", goal = 500, reward = 30, title = "Dig 500 blocks" },
	{ id = "coal_25", kind = "collect", target = "coal", goal = 25, reward = 15, title = "Mine 25 Coal" },
	{ id = "copper_20", kind = "collect", target = "copper", goal = 20, reward = 15, title = "Mine 20 Copper" },
	{ id = "iron_15", kind = "collect", target = "iron", goal = 15, reward = 20, title = "Mine 15 Iron" },
	{ id = "silver_10", kind = "collect", target = "silver", goal = 10, reward = 25, title = "Mine 10 Silver" },
	{ id = "gold_6", kind = "collect", target = "gold", goal = 6, reward = 30, title = "Mine 6 Gold" },
	{ id = "sell_1500", kind = "sell", goal = 1500, reward = 20, title = "Sell $1,500 of ore" },
	{ id = "sell_6000", kind = "sell", goal = 6000, reward = 35, title = "Sell $6,000 of ore" },
	{ id = "depth_150", kind = "depth", goal = 150, reward = 20, title = "Reach 150 m in one round" },
	{ id = "depth_350", kind = "depth", goal = 350, reward = 40, title = "Reach 350 m in one round" },
	{ id = "rounds_2", kind = "rounds", goal = 2, reward = 25, title = "Finish 2 rounds" },
	{ id = "mutation_1", kind = "mutation", goal = 1, reward = 20, title = "Find a mutated ore" },
	{ id = "mega_50", kind = "mega", goal = 50, reward = 25, title = "Dig 50 blocks during Mega Drills" },
	{ id = "chest_3", kind = "chest", goal = 3, reward = 25, title = "Open 3 treasure chests" },
	{ id = "tnt_3", kind = "tnt", goal = 3, reward = 20, title = "Blow up 3 TNT blocks" },
}

local byId: { [string]: QuestDef } = {}
for _, q in POOL do
	byId[q.id] = q
end

Quests.POOL = POOL
Quests.PER_DAY = 3

function Quests.get(id: string): QuestDef?
	return byId[id]
end

function Quests.dayNumber(now: number?): number
	return math.floor((now or os.time()) / 86400)
end

function Quests.secondsUntilReset(now: number?): number
	local t = now or os.time()
	return 86400 - (t % 86400)
end

--- Three distinct quests for a day, same on every machine.
function Quests.dailySet(dayNumber: number): { QuestDef }
	local picked: { QuestDef } = {}
	local used: { [number]: boolean } = {}
	local salt = 0
	while #picked < Quests.PER_DAY do
		local roll = Hash.u32(dayNumber, salt, 101) % #POOL + 1
		salt += 1
		if not used[roll] then
			used[roll] = true
			table.insert(picked, POOL[roll])
		end
	end
	return picked
end

return Quests
