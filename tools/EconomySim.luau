--!strict
-- Explorer: ServerStorage/EconomySim (ModuleScript)
-- Also runnable outside Studio via tools/run_sim.py (bundles with the luau CLI).
--
-- Single-player pacing model. It plays the real OreGen with real config
-- numbers using a simple "focused" policy: dig, sell when the pack is full or
-- when the next upgrade is affordable, buy drill first and pack second.
-- Multiplayer effects (Mega Drill, catch-up) are deliberately excluded: the
-- targets in the brief describe one focused player.
--
-- Studio command bar:
--   local Sim = require(game.ServerStorage.EconomySim)
--   local RS = game.ReplicatedStorage
--   Sim.run({ GameConfig = require(RS.Config.GameConfig), Layers = require(RS.Shared.Layers),
--             Economy = require(RS.Shared.Economy), OreGen = require(RS.Shared.OreGen) }, { seeds = 40 })

local EconomySim = {}

export type Deps = {
	GameConfig: any,
	Layers: any,
	Economy: any,
	OreGen: any,
}

export type Options = {
	seeds: number?,
	maxTime: number?,
	policy: ("focused" | "casual")?,
	log: ((string) -> ())?,
}

export type RunResult = {
	firstOre: number?,
	firstSale: number?,
	firstUpgrade: number?,
	layerTimes: { number? },
	coreTime: number?,
	finalDepth: number,
	tierTimes: { number? },
	packTimes: { number? },
	trips: number,
	depthAtMinute: { number },
	cashEarned: number,
}

local SELL_SECONDS = 1.5

local function simulate(deps: Deps, seed: number, opts: Options): RunResult
	local cfg, Layers, Economy, OreGen = deps.GameConfig, deps.Layers, deps.Economy, deps.OreGen
	local maxTime = opts.maxTime or cfg.Round.ActiveSeconds
	local casual = opts.policy == "casual"

	local t = 0
	local depth = 0
	local cash = 0
	local earned = 0
	local drill, pack = 1, 1
	local units, packValue = 0, 0
	local trips = 0

	local r: RunResult = {
		firstOre = nil,
		firstSale = nil,
		firstUpgrade = nil,
		layerTimes = {},
		coreTime = nil,
		finalDepth = 0,
		tierTimes = { 0 },
		packTimes = { 0 },
		trips = 0,
		depthAtMinute = {},
		cashEarned = 0,
	}
	local nextMinuteMark = 60

	local function capacity(): number
		return Economy.packCapacity(pack, 0)
	end

	local function tryBuy()
		local bought = true
		while bought do
			bought = false
			local drillCost = Economy.upgradeCost("drill", drill)
			local packCost = Economy.upgradeCost("pack", pack)
			if drillCost and cash >= drillCost then
				cash -= drillCost
				drill += 1
				r.tierTimes[drill] = t
				r.firstUpgrade = r.firstUpgrade or t
				bought = true
			elseif not casual and packCost and cash >= packCost and (not drillCost or packCost <= drillCost * 0.6) then
				cash -= packCost
				pack += 1
				r.packTimes[pack] = t
				r.firstUpgrade = r.firstUpgrade or t
				bought = true
			end
		end
	end

	local function sellTrip()
		t += Economy.travelTime(depth) * 2 + SELL_SECONDS
		cash += packValue
		earned += packValue
		if packValue > 0 then
			r.firstSale = r.firstSale or t
		end
		packValue, units = 0, 0
		trips += 1
		tryBuy()
	end

	while t < maxTime and depth < cfg.CoreDepth do
		local index = depth + 1
		local power = Economy.drillPower({ drillTier = drill, metaDigLevel = 0, megaActive = false, catchUp = 0 })
		t += Economy.minInterval(index, power)
		depth = index

		while t >= nextMinuteMark and nextMinuteMark <= maxTime do
			table.insert(r.depthAtMinute, depth)
			nextMinuteMark += 60
		end

		local layerIndex = Layers.indexAt(depth)
		if not r.layerTimes[layerIndex] then
			r.layerTimes[layerIndex] = t
		end

		local roll = OreGen.roll(seed, index)
		if roll.oreId then
			r.firstOre = r.firstOre or t
			if units < capacity() then
				units += 1
				packValue += Economy.oreValue(roll.oreId, roll.mutationId)
			end
		end

		local drillCost = Economy.upgradeCost("drill", drill)
		local packCost = Economy.upgradeCost("pack", pack)
		local target = drillCost or packCost
		local full = units >= capacity()
		local canAffordNext = target ~= nil and packValue > 0 and cash + packValue >= target
		if full or (not casual and canAffordNext) then
			sellTrip()
		end
	end

	if depth >= cfg.CoreDepth then
		r.coreTime = t
	end
	r.finalDepth = depth
	r.trips = trips
	r.cashEarned = earned
	return r
end

local function fmtTime(seconds: number?): string
	if not seconds then
		return "  --  "
	end
	local s = math.floor(seconds + 0.5)
	return string.format("%2d:%02d", s // 60, s % 60)
end

local function percentile(values: { number }, p: number): number?
	if #values == 0 then
		return nil
	end
	table.sort(values)
	local idx = math.clamp(math.floor(p * (#values - 1) + 0.5) + 1, 1, #values)
	return values[idx]
end

local function stats(list: { number? }, count: number): string
	local present = {}
	for i = 1, count do
		local v = list[i]
		if v then
			table.insert(present, v)
		end
	end
	if #present == 0 then
		return "never"
	end
	local sum = 0
	for _, v in present do
		sum += v
	end
	return string.format(
		"mean %s  p10 %s  p90 %s  (%d/%d reached)",
		fmtTime(sum / #present),
		fmtTime(percentile(present, 0.1)),
		fmtTime(percentile(present, 0.9)),
		#present,
		count
	)
end

function EconomySim.run(deps: Deps, opts: Options?): { RunResult }
	local options: Options = opts or {}
	local log: (string) -> () = options.log or print
	local seedCount = options.seeds or 40
	local cfg = deps.GameConfig

	local results: { RunResult } = {}
	for i = 1, seedCount do
		results[i] = simulate(deps, 1000 + i * 7919, options)
	end

	local function column(getter: (RunResult) -> number?): { number? }
		local out = {}
		for i, r in results do
			out[i] = getter(r)
		end
		return out
	end

	log(string.format("== EconomySim: %d seeds, policy=%s, core at %d m ==", seedCount, options.policy or "focused", cfg.CoreDepth))
	log("first ore      " .. stats(column(function(r) return r.firstOre end), seedCount) .. "   target 0:05")
	log("first sale     " .. stats(column(function(r) return r.firstSale end), seedCount) .. "   target 0:30")
	log("first upgrade  " .. stats(column(function(r) return r.firstUpgrade end), seedCount) .. "   target 1:00")
	for li = 2, deps.Layers.count() do
		local layer = deps.Layers.get(li)
		log(string.format("%-14s %s%s", layer.name, stats(column(function(r) return r.layerTimes[li] end), seedCount), if li == 2 then "   target 3:00" else ""))
	end
	log("core           " .. stats(column(function(r) return r.coreTime end), seedCount) .. "   target 20:00")
	for tier = 2, #cfg.Drills do
		log(string.format("drill tier %d   %s", tier, stats(column(function(r) return r.tierTimes[tier] end), seedCount)))
	end
	for tier = 2, #cfg.Packs do
		log(string.format("pack tier %d    %s", tier, stats(column(function(r) return r.packTimes[tier] end), seedCount)))
	end

	local first = results[1]
	local line = "depth by minute (seed 1):"
	for m, d in first.depthAtMinute do
		if m % 2 == 0 or m == 1 then
			line ..= string.format(" %d'=%dm", m, d)
		end
	end
	log(line)
	log(string.format("seed 1: %d sell trips, %d cash earned, final depth %d m", first.trips, first.cashEarned, first.finalDepth))
	return results
end

return EconomySim
