--!strict
-- Explorer: ReplicatedStorage/Shared/Remotes (ModuleScript)
-- Single place that names every remote. The server creates them, the client
-- waits for them, nobody else makes RemoteEvents ad hoc.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- client -> server (intent only, never numbers the server already owns)
Remotes.ClientToServer = {
	"DigRequest", -- (blockIndex)
	"SellAll", -- ()
	"BuyUpgrade", -- ("drill" | "pack")
	"ClaimQuest", -- (questId)
	"Travel", -- ("up" | "down")
	"BuyMeta", -- ("digSpeed" | "pack" | "skin", skinId?)
	"ClaimCollection", -- (oreId, thresholdIndex)
	"OpenEgg", -- (eggId)
	"Equip", -- ("skin" | "pet", id)
	"SaveSettings", -- ({ sfx, shake, autoDig })
}

-- server -> client
Remotes.ServerToClient = {
	"DigResult", -- (blockIndex, accepted, finalDepth)
	"Resync", -- (depth)
	"BackpackSync", -- (backpack, packUsed)
	"SellResult", -- (cashGained, oreCount)
	"Notify", -- (kind, message)
	"RaceEvent", -- (kind, name, value) lead changes, near-core calls, final minute
	"RoundResults", -- (standings, yourPlacement, gemsEarned, personalBest)
	"ProfileSync", -- (snapshot)
	"QuestSync", -- (dayNumber, progress, claimed)
	"EggResult", -- (eggId, petId, sizeId, duplicate)
	"MegaEvent", -- ("warn" | "start" | "end" | "goal", index)
}

local FOLDER_NAME = "Remotes"

local folder: Folder? = nil

local function getFolder(): Folder
	local existing = folder
	if existing then
		return existing
	end
	local f: Folder
	if RunService:IsServer() then
		f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		for _, name in Remotes.ClientToServer do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = f
		end
		for _, name in Remotes.ServerToClient do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = f
		end
		f.Parent = ReplicatedStorage
	else
		f = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: any
	end
	folder = f
	return f
end

function Remotes.get(name: string): RemoteEvent
	local f = getFolder()
	local remote = if RunService:IsServer() then f:FindFirstChild(name) else f:WaitForChild(name)
	assert(remote and remote:IsA("RemoteEvent"), `Unknown remote {name}`)
	return remote
end

--- Call once on the server before anything else requires a remote.
function Remotes.init()
	getFolder()
end

return Remotes
