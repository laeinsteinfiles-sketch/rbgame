--!strict
-- Explorer: ServerScriptService/Services/QuestService (ModuleScript)
-- Daily quests. Progress lives in the profile; the day's set is derived from
-- the UTC day number so no store round-trip is needed. Progress syncs to the
-- client at most every 2 s (digging would otherwise send a remote per block);
-- completions and claims sync immediately.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Quests = require(ReplicatedStorage.Shared.Quests)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local MetaService = require(script.Parent.MetaService)
local RateLimiter = require(script.Parent.RateLimiter)

local QuestService = {}

local SYNC_INTERVAL = 2

local dirty: { [Player]: boolean } = {}

local function today(data: DataService.ProfileData): { Types.QuestDef }
	local day = Quests.dayNumber()
	if data.quests.day ~= day then
		data.quests.day = day
		data.quests.progress = {}
		data.quests.claimed = {}
	end
	return Quests.dailySet(day)
end

function QuestService.sync(player: Player)
	dirty[player] = nil
	local data = DataService.get(player)
	if data then
		today(data)
		Remotes.get("QuestSync"):FireClient(player, data.quests.day, data.quests.progress, data.quests.claimed)
	end
end

local function bump(player: Player, quest: Types.QuestDef, data: DataService.ProfileData, value: number)
	data.quests.progress[quest.id] = value
	if value >= quest.goal then
		QuestService.sync(player)
		Remotes.get("Notify"):FireClient(player, "gems", `Quest complete · {quest.title}`)
	else
		dirty[player] = true
	end
end

--- Adds `amount` to every active quest of `kind` (optionally filtered by target).
function QuestService.add(player: Player, kind: string, amount: number, target: string?)
	local data = DataService.get(player)
	if not data then
		return
	end
	for _, quest in today(data) do
		if quest.kind == kind and (quest.target == nil or quest.target == target) and not data.quests.claimed[quest.id] then
			local current = data.quests.progress[quest.id] or 0
			if current < quest.goal then
				bump(player, quest, data, math.min(quest.goal, current + amount))
			end
		end
	end
end

--- For "reach depth" style quests: progress is the best value, not a sum.
function QuestService.raise(player: Player, kind: string, value: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	for _, quest in today(data) do
		if quest.kind == kind and not data.quests.claimed[quest.id] then
			local current = data.quests.progress[quest.id] or 0
			local capped = math.min(quest.goal, value)
			if capped > current then
				bump(player, quest, data, capped)
			end
		end
	end
end

local function claim(player: Player, questId: string)
	local data = DataService.get(player)
	if not data then
		return
	end
	for _, quest in today(data) do
		if quest.id == questId then
			if data.quests.claimed[questId] then
				return
			end
			if (data.quests.progress[questId] or 0) < quest.goal then
				Remotes.get("Notify"):FireClient(player, "error", "Quest not finished yet")
				return
			end
			data.quests.claimed[questId] = true
			MetaService.awardGems(player, quest.reward, quest.title)
			QuestService.sync(player)
			return
		end
	end
end

function QuestService.init()
	local limiter = RateLimiter.new(GameConfig.RateLimits.ClaimQuest.capacity, GameConfig.RateLimits.ClaimQuest.refill)
	Remotes.get("ClaimQuest").OnServerEvent:Connect(function(player, questId)
		if limiter:allow(player) and typeof(questId) == "string" then
			claim(player, questId)
		end
	end)
	DataService.onLoaded:Connect(function(player)
		QuestService.sync(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player)
		dirty[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(SYNC_INTERVAL)
			for player in dirty do
				if player.Parent == Players then
					QuestService.sync(player)
				else
					dirty[player] = nil
				end
			end
		end
	end)
end

return QuestService
