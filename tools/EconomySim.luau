--!strict
-- Explorer: ServerStorage/EconomySim (ModuleScript)
-- Plays the real round economy against the real cell generator with a
-- scripted player, so pacing numbers in GameConfig are measured, not guessed.
--
-- Studio (command bar):
--   local RS = game.ReplicatedStorage
--   require(game.ServerStorage.EconomySim).run({
--     GameConfig = require(RS.Config.GameConfig), Grid = require(RS.Shared.Grid),
--     Layers = require(RS.Shared.Layers), Economy = require(RS.Shared.Economy),
--     CellGen = require(RS.Shared.CellGen) }, { seeds = 40, policy = "focused" })
-- Outside Studio: python3 tools/run_sim.py --seeds 40 [--policy casual]
--
-- Model: the player stands in a cell, digs a neighbour (left/right/down),
-- falls through open cells, walks into side cells it chases, and rides the
-- elevator to sell. Time costs below are measured-feel guesses for movement.

local EconomySim = {}

local WALK_TIME = 0.4 -- one cell sideways
local FALL_TIME = 0.08 -- per cell fallen
local DIG_OVERHEAD = 0.06 -- re-aim between cells
local SELL_OVERHEAD = 3 -- walk to the pad, sell, open the shop

type Stats = { [string]: { number } }

local function percentile(values: { number }, p: number): number
	local sorted = table.clone(values)
	table.sort(sorted)
	local i = math.clamp(math.floor(p * (#sorted - 1) + 0.5) + 1, 1, #sorted)
	return sorted[i]
end

local function clock(seconds: number): string
	seconds = math.floor(seconds + 0.5)
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function EconomySim.run(deps: any, options: any)
	local GameConfig = deps.GameConfig
	local Grid = deps.Grid
	local Layers = deps.Layers
	local Economy = deps.Economy
	local CellGen = deps.CellGen

	local seeds: number = options.seeds or 40
	local policy: string = options.policy or "focused"
	local ACTIVE: number = GameConfig.Round.ActiveSeconds
	local CORE: number = GameConfig.CoreDepth
	local COLS: number = Grid.COLS
	local mega = GameConfig.Round.MegaDrill

	local stats: Stats = {}
	local reachedCount: { [string]: number } = {}
	local order: { string } = {}
	local function record(name: string, value: number)
		if not stats[name] then
			stats[name] = {}
			reachedCount[name] = 0
			table.insert(order, name)
		end
		table.insert(stats[name], value)
		reachedCount[name] += 1
	end

	local depthSamples: { [number]: { number } } = {}
	local tripsTotal, cashTotal, oreTotal, cellsTotal = 0, 0, 0, 0

	for s = 1, seeds do
		local seed = s * 7919 + 13
		local t = 0
		local open: { [number]: boolean } = {}
		local cellCache: { [number]: any } = {}
		local caveCache: { [number]: boolean } = {}
		local col, row = math.ceil(COLS / 2), 0
		local cash, pickTier, packTier, packUsed, packValue = 0, 1, 1, 0, 0
		local depth = 0
		local reachedCore = false
		local events: { [string]: number } = {}
		local trips, cellsDug, oreGot = 0, 0, 0
		local nextMinute = 60

		local function mark(name: string)
			if events[name] == nil then
				events[name] = t
			end
		end
		local function cellAt(c: number, r: number): any
			local k = Grid.key(c, r)
			local v = cellCache[k]
			if not v then
				v = CellGen.at(seed, c, r)
				cellCache[k] = v
			end
			return v
		end
		local function isOpen(c: number, r: number): boolean
			if r <= 0 then
				return true
			end
			if c < 1 or c > COLS or r > CORE then
				return false
			end
			local k = Grid.key(c, r)
			if open[k] then
				return true
			end
			local cave = caveCache[k]
			if cave == nil then
				cave = CellGen.isCave(seed, c, r)
				caveCache[k] = cave
			end
			return cave
		end
		local function power(): number
			local active = false
			for _, start in mega.StartTimes do
				if t >= start and t < start + mega.Duration then
					active = true
				end
			end
			return Economy.digPower({ pickaxeTier = pickTier, metaDigLevel = 0, megaActive = active, catchUp = 0 })
		end
		local function capacity(): number
			return Economy.packCapacity(packTier, 0)
		end
		local function settle()
			while row < CORE and isOpen(col, row + 1) do
				row += 1
				t += FALL_TIME
			end
		end
		local function onDepth(r: number)
			if r > depth then
				depth = r
				local li = Layers.indexAt(r - 1)
				if li > 1 then
					mark(Layers.get(li).name)
				end
			end
		end

		local function collect(c: number, r: number)
			local cell = cellAt(c, r)
			if cell.kind == "ore" then
				mark("first ore")
				if packUsed < capacity() then
					packUsed += 1
					packValue += Economy.oreValue(cell.oreId, cell.mutationId)
					oreGot += 1
				end
			elseif cell.kind == "chest" then
				cash += CellGen.chestCash(r)
				mark("first chest")
			elseif cell.kind == "tnt" then
				mark("first tnt")
				for _, p in CellGen.blastArea(c, r) do
					if not isOpen(p[1], p[2]) then
						open[Grid.key(p[1], p[2])] = true
						onDepth(p[2])
						collect(p[1], p[2])
					end
				end
			elseif cell.kind == "core" then
				reachedCore = true
			end
		end

		local function dig(c: number, r: number)
			local cell = cellAt(c, r)
			t += Economy.digTime(cell.hardness, power()) + DIG_OVERHEAD
			open[Grid.key(c, r)] = true
			cellsDug += 1
			onDepth(r)
			collect(c, r)
		end

		local function worth(c: number, r: number): number
			if c < 1 or c > COLS or r < 1 or r > CORE or isOpen(c, r) then
				return 0
			end
			local cell = cellAt(c, r)
			if cell.kind == "ore" then
				return if packUsed < capacity() then Economy.oreValue(cell.oreId, cell.mutationId) else 0
			elseif cell.kind == "chest" then
				return CellGen.chestCash(r)
			elseif cell.kind == "tnt" then
				return 4
			end
			return 0
		end

		local function sellTrip()
			trips += 1
			t += Economy.travelTime(depth) + SELL_OVERHEAD
			cash += packValue
			mark("first sale")
			packUsed, packValue = 0, 0
			local bought = true
			while bought do
				bought = false
				local pickCost = Economy.upgradeCost("pickaxe", pickTier)
				local packCost = Economy.upgradeCost("pack", packTier)
				if pickCost and cash >= pickCost then
					cash -= pickCost
					pickTier += 1
					bought = true
					mark("first upgrade")
					mark(`pickaxe {pickTier}`)
				elseif packCost and cash >= packCost and (policy == "casual" or packCost <= (pickCost or math.huge) * 0.6) then
					cash -= packCost
					packTier += 1
					bought = true
					mark("first upgrade")
					mark(`pack {packTier}`)
				end
			end
			t += Economy.travelTime(depth)
		end

		while t < ACTIVE and not reachedCore do
			while t >= nextMinute do
				local minute = nextMinute // 60
				depthSamples[minute] = depthSamples[minute] or {}
				table.insert(depthSamples[minute], depth)
				nextMinute += 60
			end

			local full = packUsed >= capacity()
			local nextPick = Economy.upgradeCost("pickaxe", pickTier)
			local wantTrip = full
				or (policy == "focused" and nextPick ~= nil and cash + packValue >= nextPick and packUsed >= capacity() * 0.5)
			if wantTrip and packUsed > 0 then
				sellTrip()
			end

			-- Greedy neighbours first (left, right, below), then the focused
			-- player chases ore two cells sideways; otherwise dig down.
			local bestC, bestR, bestValue = col, row + 1, 0
			if row >= 1 then
				for _, dc in { -1, 1 } do
					local v = worth(col + dc, row)
					if v > bestValue then
						bestC, bestR, bestValue = col + dc, row, v
					end
				end
			end
			local below = worth(col, row + 1)
			if below >= bestValue then
				bestC, bestR, bestValue = col, row + 1, below
			end

			if bestValue == 0 and policy == "focused" and row >= 1 then
				local threshold = Layers.ofRow(row).ores[1] and Economy.oreValue(Layers.ofRow(row).ores[1].id, "none") * 2 or 10
				for _, dc in { -2, 2 } do
					local v = worth(col + dc, row)
					if v >= threshold and not isOpen(col + dc // 2, row) then
						bestC, bestR, bestValue = col + dc // 2, row, v
						break
					end
				end
			end

			if not isOpen(bestC, bestR) then
				dig(bestC, bestR)
			end
			if bestR == row and bestC ~= col and bestValue > 0 and policy == "focused" and worth(bestC + (bestC - col), row) > 0 then
				col = bestC
				t += WALK_TIME
			end
			settle()
		end

		tripsTotal += trips
		cashTotal += cash
		oreTotal += oreGot
		cellsTotal += cellsDug
		for name, time in events do
			record(name, time)
		end
		if reachedCore then
			record("core", t)
		end
		if s == 1 then
			print(string.format("seed 1: %d sell trips, %d cells dug, %d ore, final depth %d m, %s", trips, cellsDug, oreGot, depth, if reachedCore then "core at " .. clock(t) else "no core"))
		end
	end

	print(string.format("== EconomySim: %d seeds, policy=%s, core at %d m, round %s ==", seeds, policy, CORE, clock(ACTIVE)))
	local preferred = { "first ore", "first sale", "first upgrade", "first chest", "first tnt" }
	for li = 2, Layers.count() do
		table.insert(preferred, Layers.get(li).name)
	end
	table.insert(preferred, "core")
	local printed: { [string]: boolean } = {}
	local function line(name: string)
		local values = stats[name]
		if not values or printed[name] then
			return
		end
		printed[name] = true
		local sum = 0
		for _, v in values do
			sum += v
		end
		print(string.format("%-16s mean %6s  p10 %6s  p90 %6s  (%d/%d reached)", name, clock(sum / #values), clock(percentile(values, 0.1)), clock(percentile(values, 0.9)), reachedCount[name], seeds))
	end
	for _, name in preferred do
		line(name)
	end
	table.sort(order)
	for _, name in order do
		line(name)
	end
	local parts = {}
	for minute = 1, ACTIVE // 60 do
		local samples = depthSamples[minute]
		if samples and #samples > 0 then
			local sum = 0
			for _, v in samples do
				sum += v
			end
			table.insert(parts, string.format("%d'=%dm", minute, math.floor(sum / #samples)))
		end
	end
	print("mean depth by minute: " .. table.concat(parts, " "))
	print(string.format("per round: %.1f sell trips, %.0f cells dug, %.0f ore, $%.0f unspent", tripsTotal / seeds, cellsTotal / seeds, oreTotal / seeds, cashTotal / seeds))
end

return EconomySim
