--!strict
-- Explorer: ServerScriptService/Services/RoundService (ModuleScript)
-- The race. Lobby -> Countdown -> Active -> Results, Mega Drill windows,
-- catch-up ticks, standings and gem payouts. Phase data is replicated through
-- attributes on ReplicatedStorage.RoundState so clients need no extra remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local MetaService = require(script.Parent.MetaService)
local PlotService = require(script.Parent.PlotService)
local QuestService = require(script.Parent.QuestService)
local RoundState = require(script.Parent.RoundState)

local RoundService = {}

local R = GameConfig.Round

local folder = Instance.new("Folder")
folder.Name = "RoundState"

local roundNumber = 0
local coreWinner: Player? = nil
local megaProgress = 0
local megaGoal = 0
local megaDirty = false

local function set(name: string, value: any)
	folder:SetAttribute(name, value)
end

local function setPhase(phase: "Lobby" | "Countdown" | "Active" | "Results", seconds: number)
	RoundState.phase = phase
	set("Phase", phase)
	set("PhaseEndsAt", Workspace:GetServerTimeNow() + seconds)
end

local function startingPackTier(player: Player): number
	return if MetaService.ownsPass(player, "BigPack") then GameConfig.Meta.StarterPackTierWithPass else 1
end

local function resetPlayer(player: Player, ontoMine: boolean)
	RoundState.reset(player, startingPackTier(player))
	player:SetAttribute("Traveling", "")
	if ontoMine then
		-- Everyone starts the race standing on top of their own mine.
		local character = player.Character
		local cf = PlotService.cellCFrame(player, math.ceil(Grid.COLS / 2), 0)
		if character and cf then
			character:PivotTo(cf)
		end
	else
		PlotService.teleportHome(player)
	end
end

local function resetAll(ontoMine: boolean)
	for _, player in Players:GetPlayers() do
		resetPlayer(player, ontoMine)
	end
end

local function replicateAll()
	for player in RoundState.all() do
		RoundState.replicate(player)
	end
end

local function makeLeaderstats(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local depth = Instance.new("IntValue")
	depth.Name = "Depth"
	depth.Parent = stats
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = stats
	stats.Parent = player
end

local function setWinsStat(player: Player)
	local data = DataService.get(player)
	local stats = player:FindFirstChild("leaderstats")
	local wins = stats and stats:FindFirstChild("Wins")
	if data and wins and wins:IsA("IntValue") then
		wins.Value = data.stats.wins
	end
end

-- Mega Drill ---------------------------------------------------------------

local function endMega(index: number, round: number)
	if round ~= roundNumber or not RoundState.megaActive then
		return
	end
	RoundState.megaActive = false
	set("MegaActive", false)
	set("MegaProgress", megaProgress)
	replicateAll()
	local reached = megaProgress >= megaGoal
	for _, player in Players:GetPlayers() do
		Remotes.get("MegaEvent"):FireClient(player, if reached then "goal" else "end", index)
		if reached then
			MetaService.awardGems(player, R.MegaDrill.GemBonus, "Mega Drill goal")
		end
	end
end

local function startMega(index: number, round: number)
	if round ~= roundNumber or RoundState.phase ~= "Active" then
		return
	end
	megaProgress = 0
	megaGoal = math.max(1, #Players:GetPlayers()) * R.MegaDrill.GoalPerPlayer
	RoundState.megaActive = true
	set("MegaIndex", index)
	set("MegaGoal", megaGoal)
	set("MegaProgress", 0)
	set("MegaEndsAt", Workspace:GetServerTimeNow() + R.MegaDrill.Duration)
	set("MegaActive", true)
	replicateAll()
	Remotes.get("MegaEvent"):FireAllClients("start", index)
	task.delay(R.MegaDrill.Duration, endMega, index, round)
end

function RoundService.addMegaProgress(cells: number)
	megaProgress += cells
	megaDirty = true
end

-- Catch-up -------------------------------------------------------------------

local function catchUpTick()
	local leader = 0
	for _, state in RoundState.all() do
		leader = math.max(leader, state.depth)
	end
	set("LeaderDepth", leader)
	for player, state in RoundState.all() do
		local bonus = if RoundState.phase == "Active" then Economy.catchUpBonus(leader - state.depth) else 0
		if math.abs(bonus - state.catchUp) > 0.001 then
			state.catchUp = bonus
			RoundState.replicate(player)
		end
	end
end

-- Results --------------------------------------------------------------------

local function finishRound()
	local entries: { { player: Player, depth: number, dug: number, core: boolean, reachedAt: number } } = {}
	for player, state in RoundState.all() do
		table.insert(entries, { player = player, depth = state.depth, dug = state.dugThisRound, core = state.reachedCore, reachedAt = state.reachedAt })
	end
	table.sort(entries, function(a, b)
		if a.core ~= b.core then
			return a.core
		end
		if a.core and b.core and a.reachedAt ~= b.reachedAt then
			return a.reachedAt < b.reachedAt
		end
		if a.depth ~= b.depth then
			return a.depth > b.depth
		end
		if a.dug ~= b.dug then
			return a.dug > b.dug
		end
		return a.player.Name < b.player.Name
	end)

	local standings: { Types.Standing } = {}
	local gemsFor: { [Player]: number } = {}
	for placement, entry in entries do
		local data = DataService.get(entry.player)
		if data then
			data.stats.rounds += 1
			if placement == 1 and entry.depth > 0 then
				data.stats.wins += 1
			end
		end
		setWinsStat(entry.player)
		QuestService.add(entry.player, "rounds", 1)
		local base = R.Gems.Placement[placement]
			or (R.Gems.Participation + math.min(R.Gems.DepthGemCap, entry.depth // R.Gems.DepthPerGem))
		local reason = if placement <= 3 then `Finished {placement}{if placement == 1 then "st" elseif placement == 2 then "nd" else "rd"}` else "Round complete"
		gemsFor[entry.player] = MetaService.awardGems(entry.player, base, reason)
		table.insert(standings, {
			userId = entry.player.UserId,
			name = entry.player.DisplayName,
			depth = entry.depth,
			placement = placement,
			gems = gemsFor[entry.player] or 0,
		})
	end

	local winner = entries[1]
	set("WinnerName", if winner then winner.player.DisplayName else "")
	set("WinnerUserId", if winner then winner.player.UserId else 0)
	set("WinnerByCore", coreWinner ~= nil)

	for placement, entry in entries do
		Remotes.get("RoundResults"):FireClient(entry.player, standings, placement, gemsFor[entry.player] or 0)
	end
end

function RoundService.coreReached(player: Player)
	if RoundState.phase == "Active" and not coreWinner then
		coreWinner = player
	end
end

-- Loop -------------------------------------------------------------------------

local function runRound()
	roundNumber += 1
	set("RoundNumber", roundNumber)
	coreWinner = nil

	local lobby = if RunService:IsStudio() then R.StudioLobbySeconds else R.LobbySeconds
	setPhase("Lobby", lobby)
	resetAll(false)
	task.wait(lobby)

	setPhase("Countdown", R.CountdownSeconds)
	task.wait(R.CountdownSeconds)

	resetAll(true) -- fresh seeds for everyone at the exact same moment
	setPhase("Active", R.ActiveSeconds)
	local round = roundNumber
	for i, startTime in R.MegaDrill.StartTimes do
		task.delay(startTime, startMega, i, round)
	end
	local endAt = os.clock() + R.ActiveSeconds
	-- The first player to the core ends the round after a short grace so the
	-- moment lands and anyone a few metres away can still make it.
	local graceUntil: number? = nil
	while os.clock() < endAt do
		if coreWinner and not graceUntil then
			graceUntil = os.clock() + 8
			set("PhaseEndsAt", Workspace:GetServerTimeNow() + 8)
		end
		if graceUntil and os.clock() >= graceUntil then
			break
		end
		task.wait(0.25)
	end
	if RoundState.megaActive then
		endMega(folder:GetAttribute("MegaIndex") :: number, round)
	end

	finishRound()
	setPhase("Results", R.ResultsSeconds)
	task.wait(R.ResultsSeconds)
end

function RoundService.init()
	set("Phase", "Lobby")
	set("PhaseEndsAt", Workspace:GetServerTimeNow() + R.LobbySeconds)
	set("RoundNumber", 0)
	set("MegaActive", false)
	set("MegaProgress", 0)
	set("MegaGoal", 1)
	set("MegaIndex", 0)
	set("LeaderDepth", 0)
	set("WinnerName", "")
	set("WinnerUserId", 0)
	set("WinnerByCore", false)
	folder.Parent = ReplicatedStorage

	local function join(player: Player)
		makeLeaderstats(player)
		resetPlayer(player, false)
	end
	Players.PlayerAdded:Connect(join)
	for _, player in Players:GetPlayers() do
		join(player)
	end
	DataService.onLoaded:Connect(function(player)
		setWinsStat(player)
	end)

	-- Pass ownership arrives after the profile; a fresh BigPack owner who has
	-- not dug yet gets the starter pack applied late rather than never.
	MetaService.onPassesRefreshed:Connect(function(player)
		local state = RoundState.get(player)
		if state and state.depth == 0 and state.packTier < startingPackTier(player) then
			state.packTier = startingPackTier(player)
			RoundState.replicate(player)
		end
	end)
	MetaService.onPerkChanged:Connect(function(player)
		RoundState.replicate(player)
	end)

	task.spawn(function()
		while true do
			task.wait(R.CatchUp.UpdateInterval)
			catchUpTick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			if megaDirty then
				megaDirty = false
				set("MegaProgress", megaProgress)
			end
		end
	end)
	task.spawn(function()
		while true do
			runRound()
		end
	end)
end

return RoundService
