--!strict
-- Explorer: ServerScriptService/Services/RoundState (ModuleScript)
-- Memory-only per-player round numbers. This table is the authority for
-- depth, cash and tiers; clients only ever see it through attributes.
-- Nothing in here is ever written to a profile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)

local RoundState = {}

export type PlayerRound = {
	depth: number,
	cash: number,
	drillTier: number,
	packTier: number,
	backpack: Types.Backpack,
	packUsed: number,
	seed: number,
	lastDigAt: number,
	lastPower: number,
	digBank: number, -- seconds of dig time banked against network bunching
	violations: number,
	catchUp: number,
	dugThisRound: number,
	megaDug: number,
	cashEarned: number,
	travelingUntil: number,
	lastTravelAt: number,
	reachedCore: boolean,
	depthReachedAt: number, -- os.clock() when the current depth was reached (tiebreak)
	atSurface: boolean, -- server-tracked: rode up, spawned or reset at the surface
	holding: boolean, -- the client says the dig input is held (cosmetic only)
	round: number, -- round number this state belongs to
}

RoundState.phase = "Lobby" :: "Lobby" | "Countdown" | "Active" | "Results"
RoundState.megaActive = false
RoundState.roundNumber = 0

local rng = Random.new()
local states: { [Player]: PlayerRound } = {}
-- Active-round states of players who disconnected, restored if they rejoin
-- before the round ends so a dropped connection doesn't forfeit the race.
local parked: { [number]: PlayerRound } = {}

function RoundState.get(player: Player): PlayerRound?
	return states[player]
end

function RoundState.all(): { [Player]: PlayerRound }
	return states
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
		return GameConfig.Drills[1].power
	end
	return Economy.drillPower({
		drillTier = state.drillTier,
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
	player:SetAttribute("DrillTier", state.drillTier)
	player:SetAttribute("PackTier", state.packTier)
	player:SetAttribute("PackUsed", state.packUsed)
	player:SetAttribute("PackCap", RoundState.packCapacity(player))
	player:SetAttribute("DigPower", RoundState.power(player))
	player:SetAttribute("CatchUp", state.catchUp)
	player:SetAttribute("Seed", state.seed)
	player:SetAttribute("ReachedCore", state.reachedCore)
end

function RoundState.syncBackpack(player: Player)
	local state = states[player]
	if state then
		Remotes.get("BackpackSync"):FireClient(player, state.backpack, state.packUsed)
	end
end

function RoundState.reset(player: Player, startingPackTier: number, atSurface: boolean)
	states[player] = {
		depth = 0,
		cash = 0,
		drillTier = 1,
		packTier = startingPackTier,
		backpack = {},
		packUsed = 0,
		seed = rng:NextInteger(1, 2 ^ 31 - 1),
		lastDigAt = 0,
		lastPower = 0,
		digBank = GameConfig.Dig.TimeBankSeconds,
		violations = 0,
		catchUp = 0,
		dugThisRound = 0,
		megaDug = 0,
		cashEarned = 0,
		travelingUntil = 0,
		lastTravelAt = 0,
		reachedCore = false,
		depthReachedAt = 0,
		atSurface = atSurface,
		holding = false,
		round = RoundState.roundNumber,
	}
	player:SetAttribute("Traveling", "")
	RoundState.replicate(player)
	RoundState.syncBackpack(player)
	Remotes.get("Resync"):FireClient(player, 0)
end

--- Gives a rejoining player back the state they left this round with.
--- Returns false when there is nothing to restore.
function RoundState.restore(player: Player): boolean
	local state = parked[player.UserId]
	parked[player.UserId] = nil
	if not state or state.round ~= RoundState.roundNumber then
		return false
	end
	state.travelingUntil = 0
	state.lastDigAt = 0
	state.digBank = GameConfig.Dig.TimeBankSeconds
	state.atSurface = true -- they respawn at home
	state.holding = false
	states[player] = state
	player:SetAttribute("Traveling", "")
	RoundState.replicate(player)
	RoundState.syncBackpack(player)
	Remotes.get("Resync"):FireClient(player, state.depth)
	return true
end

function RoundState.clearParked()
	table.clear(parked)
end

function RoundState.init()
	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state and RoundState.phase == "Active" and state.dugThisRound > 0 then
			parked[player.UserId] = state
		end
		states[player] = nil
	end)

	-- IsDigging drives the drill spin every client draws for this player.
	-- The client reports holding; the recent-dig window covers a dropped packet.
	task.spawn(function()
		while true do
			task.wait(0.2)
			local now = os.clock()
			local active = RoundState.phase == "Active"
			for player, state in states do
				local digging = active and state.travelingUntil <= now and (state.holding or now - state.lastDigAt < 0.7)
				if player:GetAttribute("IsDigging") ~= digging then
					player:SetAttribute("IsDigging", digging)
				end
			end
		end
	end)
end

return RoundState
