--!strict
-- Explorer: ServerScriptService/Services/DigService (ModuleScript)
-- The only way depth changes. Validates every DigRequest in a fixed order:
-- rate limit -> shape -> phase -> sequence -> travel -> position -> timing,
-- then resolves the dig against the shared course (blasts clear blocks,
-- pockets drop you for free, chests pay out) and applies per-player loot.
-- Rejections resync the client; only cheat-shaped failures count as violations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Course = require(ReplicatedStorage.Shared.Course)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Layers = require(ReplicatedStorage.Shared.Layers)
local OreGen = require(ReplicatedStorage.Shared.OreGen)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local MetaService = require(script.Parent.MetaService)
local PlotService = require(script.Parent.PlotService)
local QuestService = require(script.Parent.QuestService)
local RateLimiter = require(script.Parent.RateLimiter)
local RoundService = require(script.Parent.RoundService)
local RoundState = require(script.Parent.RoundState)

local DigService = {}

local G = GameConfig.Geometry
local D = GameConfig.Dig

local lastPackFullNotice: { [Player]: number } = {}

local function violation(player: Player, state: RoundState.PlayerRound, reason: string)
	state.violations += 1
	if state.violations >= D.ViolationKickThreshold then
		player:Kick("Too many invalid requests.")
	else
		warn(`[DigService] {player.Name}: {reason} ({state.violations})`)
	end
end

local function reject(player: Player, state: RoundState.PlayerRound, index: number, snapPosition: boolean)
	Remotes.get("DigResult"):FireClient(player, index, false, state.depth)
	if snapPosition then
		PlotService.pivot(player, PlotService.standingCFrame(player, state.depth))
	end
end

--- True when the character is roughly where a player at `depth` should be.
local function positionOk(player: Player, depth: number): boolean
	local plot = PlotService.getPlot(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not plot or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local expectedY = G.SurfaceY - depth * G.BlockHeight + 3
	local dy = math.abs(root.Position.Y - expectedY)
	local dx = math.abs(root.Position.X - plot.center.X)
	local dz = math.abs(root.Position.Z - plot.center.Z)
	return dy <= D.MaxPositionErrorBlocks * G.BlockHeight and dx <= G.BlockSize and dz <= G.BlockSize
end

local function addOre(player: Player, state: RoundState.PlayerRound, oreId: string, mutationId: string, now: number): boolean
	if state.packUsed >= RoundState.packCapacity(player) then
		if now - (lastPackFullNotice[player] or 0) > 3 then
			lastPackFullNotice[player] = now
			Remotes.get("Notify"):FireClient(player, "packfull", "Backpack full! Ride up to sell")
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
	if mutationId ~= "none" then
		QuestService.add(player, "mutation", 1)
	end
	return true
end

local function onDigRequest(player: Player, index: any)
	local state = RoundState.get(player)
	if not state then
		return
	end
	if typeof(index) ~= "number" or index ~= index or index % 1 ~= 0 or index < 1 then
		violation(player, state, "malformed index")
		return
	end
	if RoundState.phase ~= "Active" or state.reachedCore then
		reject(player, state, index, false)
		return
	end
	-- Out-of-order indices are expected after any earlier rejection (the
	-- client keeps predicting), so they resync without a violation.
	if index ~= state.depth + 1 then
		reject(player, state, index, false)
		return
	end
	local now = os.clock()
	if state.travelingUntil > now then
		reject(player, state, index, false)
		return
	end
	if not positionOk(player, state.depth) then
		violation(player, state, "position out of range")
		reject(player, state, index, true)
		return
	end

	-- Power can only have gone up or down since the last block (upgrade, Mega
	-- Drill edge, catch-up tick). Judge against the kinder of the two.
	local powerNow = RoundState.power(player)
	local required = Economy.minInterval(index, math.max(powerNow, state.lastPower))
	local tolerance = math.max(D.ToleranceMin, required * D.ToleranceFraction)
	if now - state.lastDigAt < required - tolerance then
		violation(player, state, string.format("dug too fast (%.2fs < %.2fs)", now - state.lastDigAt, required))
		reject(player, state, index, false)
		return
	end
	state.lastDigAt = now
	state.lastPower = powerNow

	local resolution = Course.resolve(RoundState.courseSeed, index)
	local oreAdded = false
	local solidBroken = 0
	for _, broken in resolution.broken do
		if broken.kind == "pocket" then
			QuestService.add(player, "pocket", 1)
			continue
		end
		solidBroken += 1
		if broken.kind == "blast" and broken.index == index then
			QuestService.add(player, "blast", 1)
		elseif broken.kind == "chest" then
			local amount = Course.chestCash(broken.index)
			state.cash += amount
			state.cashEarned += amount
			QuestService.add(player, "chest", 1)
			Remotes.get("Notify"):FireClient(player, "chest", `Treasure! +${amount}`)
		end
		local roll = OreGen.roll(state.lootSeed, broken.index)
		if roll.oreId then
			oreAdded = addOre(player, state, roll.oreId, roll.mutationId or "none", now) or oreAdded
		end
		if roll.relic then
			MetaService.addRelic(player, 1)
			Remotes.get("Notify"):FireClient(player, "relic", "Relic found")
		end
	end

	local before = state.depth
	state.depth = resolution.finalDepth
	state.dugThisRound += solidBroken
	if RoundState.megaActive then
		state.megaDug += solidBroken
		RoundService.addMegaProgress(solidBroken)
		QuestService.add(player, "mega", solidBroken)
	end
	QuestService.add(player, "dig", solidBroken)
	QuestService.raise(player, "depth", state.depth)

	local data = DataService.get(player)
	if data and state.depth > data.stats.maxDepth then
		data.stats.maxDepth = state.depth
	end

	RoundState.replicate(player)
	if oreAdded then
		RoundState.syncBackpack(player)
	end
	Remotes.get("DigResult"):FireClient(player, index, true, state.depth)

	if Layers.indexAt(state.depth) ~= Layers.indexAt(before) then
		Remotes.get("Notify"):FireClient(player, "layer", Layers.layerAt(state.depth).name)
	end
	RoundService.onDepthChanged(player, state.depth)
	if state.depth >= GameConfig.CoreDepth then
		state.reachedCore = true
		RoundService.coreReached(player)
	end
end

function DigService.init()
	local limiter = RateLimiter.new(GameConfig.RateLimits.DigRequest.capacity, GameConfig.RateLimits.DigRequest.refill)
	Remotes.get("DigRequest").OnServerEvent:Connect(function(player, index)
		if limiter:allow(player) then
			onDigRequest(player, index)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player)
		lastPackFullNotice[player] = nil
	end)
end

return DigService
