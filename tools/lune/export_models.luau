--!nocheck
-- Builds every part-built model with the game's own builders and writes
-- render scenes to build/preview/*.json (see tools/preview.sh).
-- Usage: .tools/lune run tools/lune/export_models.luau [filter]

local fs = require("@lune/fs")
local process = require("@lune/process")
local H = require("./harness")

local game = H.boot({ side = "server" })
local roblox = H.roblox
local CFrame = roblox.CFrame
local RS = game:GetService("ReplicatedStorage")
local Models = RS.Shared.Models
local Config = RS.Config

local Island = H.require(Models.Island)
local Hub = H.require(Models.Hub)
local DrillModels = H.require(Models.DrillModels)
local PetModels = H.require(Models.PetModels)
local EggModels = H.require(Models.EggModels)
local OreModels = H.require(Models.OreModels)
local GameConfig = H.require(Config.GameConfig)

local filter = process.args[1]
local out = "build/preview"
fs.writeDir(out)

local function want(name)
	return filter == nil or string.find(name, filter, 1, true) ~= nil
end

local function row(models, spacing)
	for i, m in models do
		m:PivotTo(CFrame.new((i - 1 - (#models - 1) / 2) * spacing, 0, 0) * m:GetPivot().Rotation)
	end
	return models
end

local written = {}
local function scene(name, roots, extra)
	if want(name) then
		local count = H.writeScene(`{out}/{name}.json`, roots, extra)
		table.insert(written, `{name} ({count} parts)`)
	end
end

if want("island") then
	local built = Island.build(1)
	scene("island", { built.model })
end
if want("hub") then
	local built = Hub.build()
	scene("hub", { built.model })
end
if want("drills") then
	local drills = {}
	for tier = 1, #GameConfig.Drills do
		table.insert(drills, DrillModels.build(tier))
	end
	scene("drills", row(drills, 3.2), { camera = { eye = { 10, 1, -14 }, target = { 0, -1.6, 0 }, fov = 40 } })
	local skins = {}
	for _, skin in GameConfig.Skins do
		table.insert(skins, DrillModels.build(4, skin.id))
	end
	scene("drill_skins", row(skins, 3.2), { camera = { eye = { 8, 1, -12 }, target = { 0, -1.6, 0 }, fov = 40 } })
end
if want("pets") then
	local pets = {}
	for _, pet in GameConfig.Pets do
		table.insert(pets, PetModels.build(pet.id, 1).model)
	end
	scene("pets", row(pets, 3.4), { camera = { eye = { 6, 4, -13 }, target = { 0, 0.6, 0 }, fov = 45 } })
	local sizes = {}
	for _, size in GameConfig.PetSizes do
		table.insert(sizes, PetModels.build("owl", size.scale).model)
	end
	scene("pet_sizes", row(sizes, 4.5), { camera = { eye = { 4, 3, -11 }, target = { 0, 0.5, 0 }, fov = 45 } })
end
if want("eggs") then
	local eggs = {}
	for _, egg in GameConfig.Eggs do
		table.insert(eggs, EggModels.build(egg.id, true))
	end
	scene("eggs", row(eggs, 4), { camera = { eye = { 3, 3.5, -9 }, target = { 0, 1.4, 0 }, fov = 45 } })
end
if want("ores") then
	local ores = {}
	for i, ore in GameConfig.Ores do
		table.insert(ores, OreModels.cluster(ore.id, "none", i * 31))
	end
	for _, mutation in { "flawless", "ancient", "molten" } do
		table.insert(ores, OreModels.cluster("gold", mutation, 5))
	end
	table.insert(ores, OreModels.relic(3))
	table.insert(ores, OreModels.chest())
	table.insert(ores, OreModels.charge())
	scene("ores", row(ores, 2.8), { camera = { eye = { 6, 9, -14 }, target = { 0, 0, 0 }, fov = 50 } })
end

print("wrote " .. table.concat(written, ", "))
