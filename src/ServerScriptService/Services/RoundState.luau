--!strict
-- Explorer: ServerScriptService/Services/RoundState (ModuleScript)
-- Memory-only per-player round numbers. This table is the authority for
-- depth, cash, tiers and which cells are open; clients only ever see it
-- through attributes and remotes. Nothing in here is written to a profile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local CellGen = require(ReplicatedStorage.Shared.CellGen)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)

local RoundState = {}

export type PlayerRound = {
	seed: number,
	depth: number, -- deepest row dug this round
	cash: number,
	pickaxeTier: number,
	packTier: number,
	backpack: Types.Backpack,
	packUsed: number,
	opened: { [number]: boolean }, -- Grid.key -> dug this round (caves are implicit)
	caveCache: { [number]: boolean },
	digClock: number,
	lastPower: number,
	lastDigAt: number,
	violations: number,
	catchUp: number,
	dugThisRound: number,
	megaDug: number,
	cashEarned: number,
	travelingUntil: number,
	lastTravelAt: number,
	lastCol: number, -- where "travel down" returns to
	lastRow: number,
	reachedCore: boolean,
	reachedAt: number,
	nextMilestone: number,
}

RoundState.phase = "Lobby" :: "Lobby" | "Countdown" | "Active" | "Results"
RoundState.megaActive = false

local rng = Random.new()
local states: { [Player]: PlayerRound } = {}

function RoundState.get(player: Player): PlayerRound?
	return states[player]
end

function RoundState.all(): { [Player]: PlayerRound }
	return states
end

--- Dug this round or a cave pocket; row 0 (the surface) is always open.
function RoundState.isOpen(state: PlayerRound, col: number, row: number): boolean
	if row <= 0 then
		return true
	end
	if col < 1 or col > Grid.COLS or row > Grid.CORE_ROW then
		return false
	end
	local key = Grid.key(col, row)
	if state.opened[key] then
		return true
	end
	local cave = state.caveCache[key]
	if cave == nil then
		cave = CellGen.isCave(state.seed, col, row)
		state.caveCache[key] = cave
	end
	return cave
end

function RoundState.metaDigLevel(player: Player): number
	local data = DataService.get(player)
	return if data then data.meta.digSpeedLvl else 0
end

function RoundState.packCapacity(player: Player): number
	local state = states[player]
	local data = DataService.get(player)
	return Economy.packCapacity(if state then state.packTier else 1, if data then data.meta.packLvl else 0)
end

--- Effective dig power right now: tier x meta perk x Mega Drill x catch-up.
function RoundState.power(player: Player): number
	local state = states[player]
	if not state then
		return GameConfig.Pickaxes[1].power
	end
	return Economy.digPower({
		pickaxeTier = state.pickaxeTier,
		metaDigLevel = RoundState.metaDigLevel(player),
		megaActive = RoundState.megaActive,
		catchUp = state.catchUp,
	})
end

function RoundState.replicate(player: Player)
	local state = states[player]
	if not state then
		return
	end
	player:SetAttribute("Depth", state.depth)
	player:SetAttribute("Cash", state.cash)
	player:SetAttribute("PickaxeTier", state.pickaxeTier)
	player:SetAttribute("PackTier", state.packTier)
	player:SetAttribute("PackUsed", state.packUsed)
	player:SetAttribute("PackCap", RoundState.packCapacity(player))
	player:SetAttribute("DigPower", RoundState.power(player))
	player:SetAttribute("CatchUp", state.catchUp)
	player:SetAttribute("Seed", state.seed)
	player:SetAttribute("ReachedCore", state.reachedCore)
	local leaderstats = player:FindFirstChild("leaderstats")
	local depthStat = leaderstats and leaderstats:FindFirstChild("Depth")
	if depthStat and depthStat:IsA("IntValue") then
		depthStat.Value = state.depth
	end
end

function RoundState.syncBackpack(player: Player)
	local state = states[player]
	if state then
		Remotes.get("BackpackSync"):FireClient(player, state.backpack, state.packUsed)
	end
end

--- Full open-cell list so a client can rebuild its mine after any doubt.
function RoundState.sendResync(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local keys = {}
	for key in state.opened do
		table.insert(keys, key)
	end
	Remotes.get("Resync"):FireClient(player, state.seed, state.depth, keys)
end

function RoundState.reset(player: Player, startingPackTier: number)
	states[player] = {
		seed = rng:NextInteger(1, 2 ^ 31 - 1),
		depth = 0,
		cash = 0,
		pickaxeTier = 1,
		packTier = startingPackTier,
		backpack = {},
		packUsed = 0,
		opened = {},
		caveCache = {},
		digClock = 0,
		lastPower = 0,
		lastDigAt = 0,
		violations = 0,
		catchUp = 0,
		dugThisRound = 0,
		megaDug = 0,
		cashEarned = 0,
		travelingUntil = 0,
		lastTravelAt = 0,
		lastCol = math.ceil(Grid.COLS / 2),
		lastRow = 0,
		reachedCore = false,
		reachedAt = 0,
		nextMilestone = GameConfig.Round.DepthMilestone,
	}
	RoundState.replicate(player)
	RoundState.syncBackpack(player)
	RoundState.sendResync(player)
end

function RoundState.init()
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	-- IsDigging drives remote players' swing effects; 0.7 s covers the
	-- slowest legit cadence without flickering.
	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = os.clock()
			for player, state in states do
				local digging = now - state.lastDigAt < 0.7
				if player:GetAttribute("IsDigging") ~= digging then
					player:SetAttribute("IsDigging", digging)
				end
			end
		end
	end)
end

return RoundState
