--!strict
-- Explorer: ReplicatedStorage/Shared/Quests (ModuleScript)
-- Daily quest pool. The day's three quests are picked deterministically from
-- the UTC day number so every server and every client agree without a store.

local Hash = require(script.Parent.Hash)
local Types = require(script.Parent.Types)

type QuestDef = Types.QuestDef

local Quests = {}

local POOL: { QuestDef } = {
	{ id = "dig_200", kind = "dig", goal = 200, reward = 15, title = "Dig 200 blocks" },
	{ id = "dig_600", kind = "dig", goal = 600, reward = 30, title = "Dig 600 blocks" },
	{ id = "coal_30", kind = "collect", target = "coal", goal = 30, reward = 15, title = "Collect 30 Coal" },
	{ id = "copper_20", kind = "collect", target = "copper", goal = 20, reward = 15, title = "Collect 20 Copper" },
	{ id = "iron_15", kind = "collect", target = "iron", goal = 15, reward = 20, title = "Collect 15 Iron" },
	{ id = "silver_8", kind = "collect", target = "silver", goal = 8, reward = 25, title = "Collect 8 Silver" },
	{ id = "gold_5", kind = "collect", target = "gold", goal = 5, reward = 30, title = "Collect 5 Gold" },
	{ id = "sell_2000", kind = "sell", goal = 2000, reward = 20, title = "Sell $2,000 of ore" },
	{ id = "sell_8000", kind = "sell", goal = 8000, reward = 35, title = "Sell $8,000 of ore" },
	{ id = "depth_300", kind = "depth", goal = 300, reward = 20, title = "Reach 300 m in one round" },
	{ id = "depth_700", kind = "depth", goal = 700, reward = 40, title = "Reach 700 m in one round" },
	{ id = "rounds_2", kind = "rounds", goal = 2, reward = 25, title = "Finish 2 rounds" },
	{ id = "mutation_1", kind = "mutation", goal = 1, reward = 20, title = "Find a mutated ore" },
	{ id = "mega_60", kind = "mega", goal = 60, reward = 25, title = "Dig 60 blocks during Mega Drills" },
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
