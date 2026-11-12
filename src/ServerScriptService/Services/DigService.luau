--!strict
-- Explorer: ServerScriptService/Services/DigService (ModuleScript)
-- The only way cells open. Every DigRequest goes through DigRules.validate
-- (shape -> phase -> state -> adjacency -> reach -> timing); rejections tell
-- the client to restore that one cell, and only cheat-shaped failures count
-- towards a kick. Accepted cells apply their contents here: ore into the
-- backpack, chest cash, TNT blasts (with chain reactions), gem crystals,
-- relics and the core itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local CellGen = require(ReplicatedStorage.Shared.CellGen)
local DigRules = require(ReplicatedStorage.Shared.DigRules)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Layers = require(ReplicatedStorage.Shared.Layers)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local MetaService = require(script.Parent.MetaService)
local PlotService = require(script.Parent.PlotService)
local QuestService = require(script.Parent.QuestService)
local RateLimiter = require(script.Parent.RateLimiter)
local RoundService = require(script.Parent.RoundService)
local RoundState = require(script.Parent.RoundState)

local DigService = {}

local D = GameConfig.Dig
local S = GameConfig.Specials
local MAX_BLAST_CELLS = 40

local lastPackFullNotice: { [Player]: number } = {}

local function violation(player: Player, state: RoundState.PlayerRound, reason: string)
	state.violations += 1
	if state.violations >= D.ViolationKickThreshold then
		player:Kick("Too many invalid requests.")
	else
		warn(`[DigService] {player.Name}: {reason} ({state.violations})`)
	end
end

local function feed(kind: string, player: Player, text: string)
	Remotes.get("Feed"):FireAllClients(kind, player.DisplayName, text)
end

local function onNewDepth(player: Player, state: RoundState.PlayerRound, row: number)
	local previous = state.depth
	state.depth = row
	QuestService.raise(player, "depth", row)
	local data = DataService.get(player)
	if data and row > data.stats.maxDepth then
		data.stats.maxDepth = row
	end
	local before, after = Layers.indexAt(math.max(0, previous - 1)), Layers.indexAt(row - 1)
	if after > before and row < GameConfig.CoreDepth then
		local layer = Layers.get(after)
		Remotes.get("Notify"):FireClient(player, "layer", layer.name)
		feed("layer", player, `reached {layer.name}`)
	end
	while row >= state.nextMilestone and state.nextMilestone < GameConfig.CoreDepth do
		Remotes.get("Notify"):FireClient(player, "milestone", `{state.nextMilestone} m`)
		state.nextMilestone += GameConfig.Round.DepthMilestone
	end
end

local function collectOre(player: Player, state: RoundState.PlayerRound, cell: Types.Cell): boolean
	local oreId = cell.oreId
	if not oreId then
		return false
	end
	local mutationId = cell.mutationId or "none"
	if state.packUsed >= RoundState.packCapacity(player) then
		local now = os.clock()
		if now - (lastPackFullNotice[player] or 0) > 4 then
			lastPackFullNotice[player] = now
			Remotes.get("Notify"):FireClient(player, "packfull", "Backpack full! Ride the lift up to sell")
		end
		return false
	end
	local perOre = state.backpack[oreId]
	if not perOre then
		perOre = {}
		state.backpack[oreId] = perOre
	end
	perOre[mutationId] = (perOre[mutationId] or 0) + 1
	state.packUsed += 1
	MetaService.recordCollect(player, oreId, mutationId)
	QuestService.add(player, "collect", 1, oreId)
	local ore = Economy.oreById[oreId]
	local mutation = Economy.mutationById[mutationId]
	if mutationId ~= "none" then
		QuestService.add(player, "mutation", 1)
	end
	if ore and (ore.rarity >= 5 or (mutation and mutation.mult >= 8) or (ore.rarity >= 4 and mutationId ~= "none")) then
		local name = if mutationId ~= "none" and mutation then `{mutation.name} {ore.name}` else ore.name
		feed("rare", player, `found {name}!`)
	end
	return true
end

--- Opens one cell and applies its contents. Returns true if ore was added.
local function applyCell(player: Player, state: RoundState.PlayerRound, col: number, row: number, cell: Types.Cell, blasted: { number }): boolean
	state.opened[Grid.key(col, row)] = true
	state.dugThisRound += 1
	QuestService.add(player, "dig", 1)
	if RoundState.megaActive then
		state.megaDug += 1
		RoundService.addMegaProgress(1)
		QuestService.add(player, "mega", 1)
	end
	if row > state.depth then
		onNewDepth(player, state, row)
	end

	local kind = cell.kind
	if kind == "ore" then
		return collectOre(player, state, cell)
	elseif kind == "chest" then
		local cash = CellGen.chestCash(row)
		state.cash += cash
		state.cashEarned += cash
		QuestService.add(player, "chest", 1)
		Remotes.get("Reward"):FireClient(player, "cash", cash, "Treasure chest")
	elseif kind == "gem" then
		MetaService.awardGems(player, S.Gem.gems, "Gem crystal")
	elseif kind == "relic" then
		MetaService.addRelic(player, 1)
		Remotes.get("Reward"):FireClient(player, "relic", 1, "Ancient relic")
		feed("relic", player, "unearthed an ancient relic!")
	elseif kind == "tnt" then
		QuestService.add(player, "tnt", 1)
		local oreAdded = false
		local queue = { { col, row } }
		local head = 1
		while head <= #queue and #blasted < MAX_BLAST_CELLS do
			local center = queue[head]
			head += 1
			for _, p in CellGen.blastArea(center[1], center[2]) do
				local c, r = p[1], p[2]
				if not RoundState.isOpen(state, c, r) and #blasted < MAX_BLAST_CELLS then
					table.insert(blasted, Grid.key(c, r))
					local inner = CellGen.at(state.seed, c, r)
					if inner.kind == "tnt" then
						-- Chain reaction: open it, then blast from it too.
						state.opened[Grid.key(c, r)] = true
						state.dugThisRound += 1
						if r > state.depth then
							onNewDepth(player, state, r)
						end
						table.insert(queue, { c, r })
					elseif applyCell(player, state, c, r, inner, blasted) then
						oreAdded = true
					end
				end
			end
		end
		return oreAdded
	elseif kind == "core" then
		if not state.reachedCore then
			state.reachedCore = true
			state.reachedAt = os.clock()
			local data = DataService.get(player)
			if data then
				data.stats.cores = (data.stats.cores or 0) + 1
			end
			MetaService.awardGems(player, GameConfig.Round.Gems.CoreBonus, "Reached the core")
			feed("core", player, "REACHED THE CORE!")
			RoundService.coreReached(player)
		end
	end
	return false
end

local function onDigRequest(player: Player, col: any, row: any)
	local state = RoundState.get(player)
	if not state then
		return
	end
	local plot = PlotService.getPlot(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hasRoot = plot ~= nil and root ~= nil and root:IsA("BasePart") and humanoid ~= nil and humanoid.Health > 0
	local rootDx, rootY, rootDz = 0, 0, 0
	if hasRoot and plot and root and root:IsA("BasePart") then
		local p = root.Position
		rootDx, rootY, rootDz = p.X - plot.origin.X, p.Y, p.Z - plot.origin.Z
	end

	local now = os.clock()
	local powerNow = RoundState.power(player)
	local verdict = DigRules.validate(col, row, {
		seed = state.seed,
		phase = RoundState.phase,
		traveling = state.travelingUntil > now,
		reachedCore = state.reachedCore,
		isOpen = function(c: number, r: number): boolean
			return RoundState.isOpen(state, c, r)
		end,
		hasRoot = hasRoot,
		rootDx = rootDx,
		rootY = rootY,
		rootDz = rootDz,
		now = now,
		digClock = state.digClock,
		-- Power can drop between the client's start and the server's check
		-- (Mega Drill ending, catch-up tick); judge by the kinder value.
		power = math.max(powerNow, state.lastPower),
	})
	if not verdict.ok then
		if verdict.violation then
			violation(player, state, verdict.reason)
		end
		if typeof(col) == "number" and typeof(row) == "number" and col == col and row == row then
			Remotes.get("DigResult"):FireClient(player, col, row, false, state.depth)
		end
		return
	end

	state.digClock = verdict.digClock
	state.lastPower = powerNow
	state.lastDigAt = now
	local cell = verdict.cell :: Types.Cell
	local blasted: { number } = {}
	local packBefore = state.packUsed
	applyCell(player, state, col, row, cell, blasted)

	RoundState.replicate(player)
	if state.packUsed ~= packBefore then
		RoundState.syncBackpack(player)
	end
	Remotes.get("DigResult"):FireClient(player, col, row, true, state.depth, if #blasted > 0 then blasted else nil)
end

function DigService.init()
	local limits = GameConfig.RateLimits
	local limiter = RateLimiter.new(limits.DigRequest.capacity, limits.DigRequest.refill)
	local resyncLimiter = RateLimiter.new(2, 0.5)
	Remotes.get("DigRequest").OnServerEvent:Connect(function(player, col, row)
		if limiter:allow(player) then
			onDigRequest(player, col, row)
		end
	end)
	Remotes.get("RequestResync").OnServerEvent:Connect(function(player)
		if resyncLimiter:allow(player) then
			RoundState.sendResync(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player)
		resyncLimiter:forget(player)
		lastPackFullNotice[player] = nil
	end)
end

return DigService
