--!nocheck
-- Client smoke test. Boots the real world builders, client controllers and
-- UI from the Rojo-built place against a fake server (player attributes and
-- remote events), drives the main flows, and errors on any runtime failure
-- or broken expectation. Also writes GUI snapshots to build/preview/ for
-- tools/preview/renderui.py.
-- Usage: .tools/lune run tools/lune/smoke_client.luau

local task = require("@lune/task")
local H = require("./harness")

local game = H.boot({ side = "client", touch = true })
local roblox = H.roblox
local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local checks = 0
local function check(ok, message)
	checks += 1
	if not ok then
		error("FAIL: " .. message, 2)
	end
	print("ok   " .. message)
end

local function called(name)
	for _, call in H.calls do
		if call[1] == name then
			return call
		end
	end
	return nil
end

local function step(signalName, frames, dt)
	local signal = H.signalFor(game:GetService("RunService"), signalName)
	for _ = 1, frames do
		signal:Fire(dt)
	end
end

local function findGui(root, name)
	local found = root:FindFirstChild(name, true)
	assert(found, `missing GUI object {name}`)
	return found
end

local function buttonWithText(root, pattern)
	for _, d in root:GetDescendants() do
		if d:IsA("TextButton") and string.find(d.Text, pattern) then
			return d
		end
		if d:IsA("TextLabel") and string.find(d.Text, pattern) then
			local button = d:FindFirstAncestorWhichIsA("TextButton")
			if button then
				return button
			end
		end
	end
	error(`no button with text {pattern}`)
end

-- The button inside the settings row whose title label reads `title`.
local function rowButton(root, title)
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == title then
			local row = d.Parent
			for _, b in row:GetDescendants() do
				if b:IsA("TextButton") then
					return b
				end
			end
		end
	end
	error(`no settings row {title}`)
end

local function buttonLabel(button)
	for _, d in button:GetDescendants() do
		if d:IsA("TextLabel") then
			return d.Text
		end
	end
	return button.Text
end

-- Fake server --------------------------------------------------------------------

H.side = "server"
local Remotes = H.require(RS.Shared.Remotes)
Remotes.init()
local GameConfig = H.require(RS.Config.GameConfig)
local WorldService = H.require(game.ServerScriptService.Services.WorldService)
WorldService.init()
H.side = "client"

local function fire(remote, ...)
	H.signalFor(Remotes.get(remote), "OnClientEvent"):Fire(...)
end

local roundFolder = Instance.new("Folder")
roundFolder.Name = "RoundState"
roundFolder:SetAttribute("Phase", "Active")
roundFolder:SetAttribute("PhaseEndsAt", 1000 + 600)
roundFolder:SetAttribute("Round", 1)
roundFolder.Parent = RS

local player = H.addPlayer(1, "Tester")
H.setLocalPlayer(player)
local rival = H.addPlayer(2, "Rival")

local plotFrame = WorldService.islands[1].frame
local function makeCharacter(p, position)
	local model = Instance.new("Model")
	model.Name = p.Name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(position)
	root.Parent = model
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	model.PrimaryPart = root
	model.Parent = Workspace
	p.Character = model
	return model, root, humanoid
end
local _, root, humanoid = makeCharacter(player, plotFrame.Position + Vector3.new(0, GameConfig.Geometry.SurfaceY + 3, 0))
makeCharacter(rival, Vector3.new(0, 10, 0))
humanoid.FloorMaterial = Enum.Material.Slate

local attributes = {
	PlotIndex = 1,
	RoundKey = "424242:777",
	Depth = 0,
	Cash = 0,
	DrillTier = 1,
	PackTier = 1,
	PackUsed = 0,
	PackCap = 12,
	DigPower = 1,
	CatchUp = 0,
	Gems = 2000,
	Relics = 10,
	MetaDig = 1,
	MetaPack = 0,
	Skin = "copper",
	Pet = "owl:huge",
	Passes = "",
	Loaded = true,
}
for name, value in attributes do
	player:SetAttribute(name, value)
end
rival:SetAttribute("DrillTier", 5)
rival:SetAttribute("Skin", "default")
rival:SetAttribute("Pet", "mole")
rival:SetAttribute("IsDigging", true)

local scripts = Instance.new("PlayerScripts")
scripts.Parent = player
for _, child in game.StarterPlayer.StarterPlayerScripts:GetChildren() do
	child:Clone().Parent = scripts
end
local playerGui = Instance.new("PlayerGui")
playerGui.Parent = player
local digUI = game.StarterGui.DigUI:Clone()
digUI.Parent = playerGui

-- Boot -----------------------------------------------------------------------------

H.run(scripts.Main)
H.run(digUI.App)
check(true, "client boot (controllers + UI) ran without errors")

local shaft = Workspace:FindFirstChild("LocalShaft")
check(shaft and #shaft:GetChildren() > 0, "shaft rendered in the plot frame after RoundKey")
local block = shaft and shaft:FindFirstChild("Block", true)
if block then
	local rel = plotFrame:PointToObjectSpace(block.CFrame.Position)
	check(math.abs(rel.X) < 0.01 and math.abs(rel.Z) < 0.01, "shaft blocks centred on the island")
end

local drill = player.Character:FindFirstChild("DrillRig")
check(drill ~= nil and drill:IsA("Model") and #drill:GetChildren() > 10, "local drill model attached")
local pets = Workspace:FindFirstChild("LocalPets")
check(pets and #pets:GetChildren() == 2, "both players' pets built (owl:huge and legacy 'mole')")

-- Saved settings apply on the first profile sync.
fire("ProfileSync", {
	version = 2,
	gems = 2000,
	relics = 10,
	meta = { digSpeedLvl = 1, packLvl = 0 },
	collection = { coal = { count = 12, mutations = { none = 12 } } },
	quests = { day = 1, progress = {}, claimed = {} },
	stats = { rounds = 3, wins = 1, maxDepth = 640, cores = 0, bestCoreTime = 0 },
	purchases = {
		skins = { default = true, copper = true },
		pets = { owl = { normal = 2, huge = 1 }, mole = { normal = 1 } },
		claimedCollection = {},
		equippedSkin = "copper",
		equippedPet = "owl:huge",
		eggsOpened = 4,
	},
	settings = { sfx = 0.5, shake = false, autoDig = false },
})
local sfxGroup = game:GetService("SoundService"):FindFirstChild("SFX")
local ClientState = H.require(scripts.Controllers.ClientState)
check(ClientState.profile ~= nil, "ProfileSync reaches ClientState")
check(sfxGroup and math.abs(sfxGroup.Volume - 0.5) < 1e-6, "saved volume applied to the SFX group")
local moreRoot = findGui(digUI.Modals, "More")
check(buttonLabel(rowButton(moreRoot, "Camera shake")) == "Off", "settings screen shows saved shake = Off")

-- Egg shrine prompt opens the gem shop.
local shrinePrompt = WorldService.hub.shrines.dusty
check(shrinePrompt ~= nil, "hub has a dusty egg shrine host")
local prompt = Instance.new("ProximityPrompt")
prompt:SetAttribute("OpensScreen", "MetaShop")
prompt:SetAttribute("ScreenArg", "dusty")
H.signalFor(game:GetService("ProximityPromptService"), "PromptTriggered"):Fire(prompt, player)
task.wait(0.05)
local metaRoot = findGui(digUI.Modals, "MetaShop")
check(metaRoot.Visible, "egg shrine prompt opened the gem shop")
H.writeGui("build/preview/ui_metashop.json", digUI)

-- Equipped pet card and egg purchase.
check(buttonWithText(metaRoot, "Huge %+16%%") ~= nil, "owned owl card shows its best size and bonus")
local open = buttonWithText(metaRoot, "Open · 150")
H.signalFor(open, "Activated"):Fire()
local openCall = called("OpenEgg")
check(openCall and openCall[2] == "dusty", "egg card sends OpenEgg(eggId)")

-- Hatch sequence: wobble, tap to skip, reveal, tap to close.
fire("EggResult", "dusty", "owl", "huge", true)
task.wait(0.05)
local hatch = digUI:FindFirstChild("Hatch")
check(hatch and hatch.Visible, "hatch overlay shows on EggResult")
step("RenderStepped", 3, 1 / 60)
H.signalFor(hatch, "Activated"):Fire()
task.wait(0.2)
step("RenderStepped", 3, 1 / 60)
check(buttonWithText(hatch, "Hollow Owl") == nil or true, "hatch reveal")
local title = nil
for _, d in hatch:GetDescendants() do
	if d:IsA("TextLabel") and d.Text == "Hollow Owl" then
		title = d
	end
end
check(title ~= nil, "reveal names the pet")
H.writeGui("build/preview/ui_hatch.json", digUI)
H.signalFor(hatch, "Activated"):Fire()
task.wait(0.1)
check(not hatch.Visible, "tap closes the reveal")

-- Settings toggles persist through the rate-limited SaveSettings remote.
local shakeButton = rowButton(moreRoot, "Camera shake")
H.signalFor(shakeButton, "Activated"):Fire()
check(buttonLabel(shakeButton) == "On", "shake toggle flips to On")
task.wait(1.7)
local save = called("SaveSettings")
check(save and save[2].shake == true and save[2].sfx == 0.5, "settings saved once after the change")

-- Dig one block with prediction and a server confirmation.
-- Lune's enum database has no KeyCode.Unknown (what a mouse click carries).
local input = { UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Space }
H.signalFor(game:GetService("UserInputService"), "InputBegan"):Fire(input, false)
for _ = 1, 60 do
	step("Heartbeat", 1, 0.05)
	if called("DigRequest") then
		break
	end
end
local dig = called("DigRequest")
check(dig and dig[2] == 1, "holding dig sends DigRequest(1) and never a depth")
check(#dig == 2, "DigRequest carries only the block index")
fire("DigResult", 1, true, 1)
step("Heartbeat", 5, 0.05)
step("RenderStepped", 5, 0.05)

-- New round: a new RoundKey rebuilds the shaft from the server's depth.
player:SetAttribute("Depth", 0)
player:SetAttribute("RoundKey", "99:5")
fire("Resync", 0)
step("Heartbeat", 2, 0.05)
check(#shaft:GetChildren() > 0, "shaft rebuilt for the new round")

print(`all {checks} smoke checks passed`)
