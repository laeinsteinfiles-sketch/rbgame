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
	lootSeed: number,
	lastDigAt: number,
	lastPower: number,
	violations: number,
	catchUp: number,
	dugThisRound: number,
	megaDug: number,
	cashEarned: number,
	travelingUntil: number,
	lastTravelAt: number,
	reachedCore: boolean,
	coreTime: number?,
	nearCoreCalled: boolean,
}

RoundState.phase = "Lobby" :: "Lobby" | "Countdown" | "Active" | "Results"
RoundState.megaActive = false
-- One course per round shared by everyone: the race is the same shaft.
RoundState.courseSeed = 1
RoundState.activeSince = 0

local rng = Random.new()
local states: { [Player]: PlayerRound } = {}

function RoundState.newCourse()
	RoundState.courseSeed = rng:NextInteger(1, 2 ^ 31 - 1)
end

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
	-- Both seeds travel in one attribute so the client never renders a
	-- course from one round with loot from another.
	player:SetAttribute("RoundKey", `{RoundState.courseSeed}:{state.lootSeed}`)
end

function RoundState.syncBackpack(player: Player)
	local state = states[player]
	if state then
		Remotes.get("BackpackSync"):FireClient(player, state.backpack, state.packUsed)
	end
end

function RoundState.reset(player: Player, startingPackTier: number)
	states[player] = {
		depth = 0,
		cash = 0,
		drillTier = 1,
		packTier = startingPackTier,
		backpack = {},
		packUsed = 0,
		lootSeed = rng:NextInteger(1, 2 ^ 31 - 1),
		lastDigAt = 0,
		lastPower = 0,
		violations = 0,
		catchUp = 0,
		dugThisRound = 0,
		megaDug = 0,
		cashEarned = 0,
		travelingUntil = 0,
		lastTravelAt = 0,
		reachedCore = false,
		coreTime = nil,
		nearCoreCalled = false,
	}
	RoundState.replicate(player)
	RoundState.syncBackpack(player)
	Remotes.get("Resync"):FireClient(player, 0)
end

function RoundState.init()
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	-- IsDigging drives drill animation on every client; 0.7 s covers the
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
