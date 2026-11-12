--!strict
-- Explorer: ServerScriptService/Services/RoundService (ModuleScript)
-- The race. Lobby -> Countdown -> Active -> Results, Mega Drill windows,
-- catch-up ticks, race calls (lead changes, near-core, final minute), the
-- live boards, standings, gem payouts and the podium ceremony. Phase data is
-- replicated through attributes on ReplicatedStorage.RoundState.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local MetaService = require(script.Parent.MetaService)
local PlotService = require(script.Parent.PlotService)
local QuestService = require(script.Parent.QuestService)
local RoundState = require(script.Parent.RoundState)
local WorldService = require(script.Parent.WorldService)

local RoundService = {}

local R = GameConfig.Round
local E = R.Events

local folder = Instance.new("Folder")
folder.Name = "RoundState"

local roundNumber = 0
local coreWinner: Player? = nil
local megaProgress = 0
local megaGoal = 0
local megaDirty = false
local leader: Player? = nil
local lastLeadCall = 0
local podiumSpots: { [Player]: CFrame } = {}

local function set(name: string, value: any)
	folder:SetAttribute(name, value)
end

local function race(kind: string, name: string, value: number)
	Remotes.get("RaceEvent"):FireAllClients(kind, name, value)
end

local function setPhase(phase: "Lobby" | "Countdown" | "Active" | "Results", seconds: number)
	RoundState.phase = phase
	set("Phase", phase)
	set("PhaseEndsAt", Workspace:GetServerTimeNow() + seconds)
end

local function startingPackTier(player: Player): number
	return if MetaService.ownsPass(player, "BigPack") then GameConfig.Meta.StarterPackTierWithPass else 1
end

local function resetPlayer(player: Player, ontoShaft: boolean)
	RoundState.reset(player, startingPackTier(player))
	PlotService.setDepthLabel(player, 0)
	-- Everyone starts the race standing on their first block.
	PlotService.pivot(player, if ontoShaft then PlotService.standingCFrame(player, 0) else PlotService.homeCFrame(player))
end

local function resetAll(ontoShaft: boolean)
	for _, player in Players:GetPlayers() do
		resetPlayer(player, ontoShaft)
	end
end

local function replicateAll()
	for player in RoundState.all() do
		RoundState.replicate(player)
	end
end

local function standingsByDepth(): { { player: Player, depth: number, dug: number } }
	local entries = {}
	for player, state in RoundState.all() do
		table.insert(entries, { player = player, depth = state.depth, dug = state.dugThisRound })
	end
	table.sort(entries, function(a, b)
		if a.depth ~= b.depth then
			return a.depth > b.depth
		end
		if a.dug ~= b.dug then
			return a.dug > b.dug
		end
		return a.player.Name < b.player.Name
	end)
	return entries
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

local function warnMega(index: number, round: number)
	if round == roundNumber and RoundState.phase == "Active" then
		Remotes.get("MegaEvent"):FireAllClients("warn", index)
	end
end

function RoundService.addMegaProgress(blocks: number)
	megaProgress += blocks
	megaDirty = true
end

-- Race calls ----------------------------------------------------------------

local function raceTick()
	local entries = standingsByDepth()
	local top = entries[1]
	set("LeaderDepth", if top then top.depth else 0)
	for _, entry in entries do
		local state = RoundState.get(entry.player)
		if state then
			local bonus = if RoundState.phase == "Active" and top then Economy.catchUpBonus(top.depth - state.depth) else 0
			if math.abs(bonus - state.catchUp) > 0.001 then
				state.catchUp = bonus
				RoundState.replicate(entry.player)
			end
		end
	end
	if RoundState.phase ~= "Active" or not top then
		return
	end
	local now = os.clock()
	if top.player ~= leader and top.depth >= E.LeadMinDepth and now - lastLeadCall >= E.LeadCooldown then
		local second = entries[2]
		-- A tie is not a lead change; wait until someone is actually ahead.
		if not second or second.depth < top.depth then
			leader = top.player
			lastLeadCall = now
			race("lead", top.player.DisplayName, top.depth)
		end
	end
end

function RoundService.onDepthChanged(player: Player, depth: number)
	local state = RoundState.get(player)
	if state and not state.nearCoreCalled and depth >= GameConfig.CoreDepth - E.NearCoreMetres and RoundState.phase == "Active" then
		state.nearCoreCalled = true
		race("nearcore", player.DisplayName, GameConfig.CoreDepth - depth)
	end
end

function RoundService.coreReached(player: Player)
	if RoundState.phase == "Active" and not coreWinner then
		coreWinner = player
		local state = RoundState.get(player)
		if state then
			state.coreTime = os.clock() - RoundState.activeSince
		end
		race("core", player.DisplayName, if state and state.coreTime then state.coreTime else 0)
	end
end

-- Boards ----------------------------------------------------------------------

local function updateBoards()
	local entries = standingsByDepth()
	local remaining = math.max(0, (folder:GetAttribute("PhaseEndsAt") :: number? or 0) - Workspace:GetServerTimeNow())
	local phase = RoundState.phase
	local timerText = if phase == "Active" then Format.clock(remaining) elseif phase == "Results" then "FINISH" else `NEXT {Format.clock(remaining)}`
	for _, board in WorldService.hub.boards do
		board.timer.Text = timerText
		for i, row in board.rows do
			local entry = entries[i]
			row.Text = if entry then `{i}. {entry.player.DisplayName}  {Format.depth(entry.depth)}` else ""
		end
	end
	for player, state in RoundState.all() do
		PlotService.setDepthLabel(player, state.depth)
	end
end

-- Results ----------------------------------------------------------------------

local function podium(entries: { { player: Player, depth: number, dug: number } })
	local hub = WorldService.hub
	table.clear(podiumSpots)
	local crowdIndex = 1
	for placement, entry in entries do
		local spot: CFrame
		if placement <= 3 then
			spot = hub.podium[placement]
		else
			spot = hub.crowd[(crowdIndex - 1) % #hub.crowd + 1]
			crowdIndex += 1
		end
		podiumSpots[entry.player] = spot
		PlotService.pivot(entry.player, spot)
	end
end

local function finishRound()
	local entries = standingsByDepth()
	local standings: { Types.Standing } = {}
	local gemsFor: { [Player]: number } = {}
	local bests: { [Player]: { depth: boolean, coreTime: number? } } = {}
	for placement, entry in entries do
		local data = DataService.get(entry.player)
		local state = RoundState.get(entry.player)
		local best = { depth = false, coreTime = nil :: number? }
		if data then
			data.stats.rounds += 1
			if placement == 1 then
				data.stats.wins += 1
			end
			if entry.depth > data.stats.maxDepth then
				data.stats.maxDepth = entry.depth
				best.depth = true
			end
			if state and state.coreTime then
				data.stats.cores += 1
				if data.stats.bestCoreTime == 0 or state.coreTime < data.stats.bestCoreTime then
					data.stats.bestCoreTime = math.floor(state.coreTime)
					best.coreTime = data.stats.bestCoreTime
				end
			end
		end
		bests[entry.player] = best
		QuestService.add(entry.player, "rounds", 1)
		local base = R.Gems.Placement[placement]
			or (R.Gems.Participation + math.min(R.Gems.DepthGemCap, entry.depth // R.Gems.DepthPerGem))
		local reason = if placement <= 3 then `Finished #{placement}` else "Round complete"
		-- awardGems pushes the profile, which also carries the stats above.
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

	podium(entries)
	for placement, entry in entries do
		Remotes.get("RoundResults"):FireClient(entry.player, standings, placement, gemsFor[entry.player] or 0, bests[entry.player])
	end
end

-- Loop -------------------------------------------------------------------------

local function runRound()
	roundNumber += 1
	set("RoundNumber", roundNumber)
	coreWinner = nil
	leader = nil
	lastLeadCall = 0
	table.clear(podiumSpots)

	setPhase("Lobby", R.LobbySeconds)
	resetAll(false)
	task.wait(R.LobbySeconds)

	setPhase("Countdown", R.CountdownSeconds)
	task.wait(R.CountdownSeconds)

	RoundState.newCourse()
	resetAll(true) -- fresh seeds for everyone at the exact same moment
	RoundState.activeSince = os.clock()
	setPhase("Active", R.ActiveSeconds)
	local round = roundNumber
	for i, startTime in R.MegaDrill.StartTimes do
		task.delay(startTime - R.MegaDrill.WarnSeconds, warnMega, i, round)
		task.delay(startTime, startMega, i, round)
	end
	task.delay(R.ActiveSeconds - E.FinalCallSeconds, function()
		if round == roundNumber and RoundState.phase == "Active" and not coreWinner then
			race("final", "", E.FinalCallSeconds)
		end
	end)
	local endAt = os.clock() + R.ActiveSeconds
	while os.clock() < endAt and not coreWinner do
		task.wait(0.25)
	end
	if RoundState.megaActive then
		endMega(folder:GetAttribute("MegaIndex") :: number, round)
	end

	setPhase("Results", R.ResultsSeconds)
	finishRound()
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

	-- Respawns during the ceremony go back to the podium, not home.
	PlotService.respawnAt = function(player: Player): CFrame?
		if RoundState.phase == "Results" and podiumSpots[player] then
			return podiumSpots[player]
		end
		local state = RoundState.get(player)
		if RoundState.phase == "Active" and state and state.depth > 0 then
			return PlotService.standingCFrame(player, state.depth)
		end
		return PlotService.homeCFrame(player)
	end

	Players.PlayerAdded:Connect(function(player)
		resetPlayer(player, false)
	end)
	for _, player in Players:GetPlayers() do
		resetPlayer(player, false)
	end

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
			raceTick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			updateBoards()
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
