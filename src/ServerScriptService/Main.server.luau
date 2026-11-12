--!strict
-- Explorer: ServerScriptService/Main (Script)
-- Boot order matters: remotes first, data second, world third, then the
-- gameplay services that listen to remotes, and the round loop last.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Services = script.Parent.Services

Remotes.init()
require(Services.DataService).init()
require(Services.PlotService).init()
require(Services.RoundState).init()
require(Services.MetaService).init()
require(Services.QuestService).init()
require(Services.ShopService).init()
require(Services.TravelService).init()
require(Services.DigService).init()
require(Services.RoundService).init()

local unsetPasses = {}
for name, id in AssetIds.Gamepasses do
	if not AssetIds.isSet(id) then
		table.insert(unsetPasses, name)
	end
end
if #unsetPasses > 0 then
	table.sort(unsetPasses)
	warn(`[DigToTheCore] Gamepasses not configured (treated as unowned): {table.concat(unsetPasses, ", ")}`)
end
