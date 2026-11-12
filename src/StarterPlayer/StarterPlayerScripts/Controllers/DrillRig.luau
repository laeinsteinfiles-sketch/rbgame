--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/DrillRig (ModuleScript)
-- Drill in every character's hand plus the owner's pet, built client-side
-- for all players from attributes (Skin, Pet, IsDigging). Part-built
-- stand-ins until Meshes.Drill / Meshes.Pets are sourced (ASSETS.md).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Types = require(ReplicatedStorage.Shared.Types)

local DrillRig = {}

type Rig = {
	model: Model,
	bit: Part,
	bitWeld: Weld,
	spin: number,
	pet: Part?,
	petBob: number,
}

local rigs: { [Player]: Rig } = {}

local skinById: { [string]: Types.SkinDef } = {}
for _, skin in GameConfig.Skins do
	skinById[skin.id] = skin
end
local petById: { [string]: Types.PetDef } = {}
for _, pet in GameConfig.Pets.List do
	petById[pet.id] = pet
end

local function material(name: string): Enum.Material
	local found = (Enum.Material :: any)[name]
	return if found then found else Enum.Material.Metal
end

local function makePart(name: string, size: Vector3, shape: Enum.PartType): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	return part
end

local function applySkin(rig: Rig, skinId: string)
	local skin = skinById[skinId] or skinById.default
	for _, child in rig.model:GetChildren() do
		if child:IsA("BasePart") then
			if child.Name == "Bit" then
				child.Color = Color3.fromHex(skin.bitColor)
				child.Material = Enum.Material.Metal
			else
				child.Color = Color3.fromHex(skin.color)
				child.Material = material(skin.material)
			end
		end
	end
end

local function buildDrill(character: Model, humanoid: Humanoid): Rig?
	local handName = if humanoid.RigType == Enum.HumanoidRigType.R6 then "Right Arm" else "RightHand"
	local hand = character:WaitForChild(handName, 5)
	if not hand or not hand:IsA("BasePart") then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "DrillRig"

	local body = makePart("Body", Vector3.new(2.2, 1.2, 1.2), Enum.PartType.Cylinder)
	local grip = makePart("Grip", Vector3.new(0.6, 1.1, 0.6), Enum.PartType.Block)
	local bit = makePart("Bit", Vector3.new(1.6, 0.7, 0.7), Enum.PartType.Cylinder)

	local meshId = AssetIds.Meshes.Drill
	if AssetIds.isSet(meshId) then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = AssetIds.image(meshId)
		mesh.Parent = body
		grip.Transparency = 1
	end

	local function weld(part0: BasePart, part1: BasePart, c0: CFrame): Weld
		local w = Instance.new("Weld")
		w.Part0 = part0
		w.Part1 = part1
		w.C0 = c0
		w.Parent = part1
		return w
	end
	-- Cylinder axis is X; point it forward out of the palm.
	weld(hand, body, CFrame.new(0, -0.3, -1.4) * CFrame.Angles(0, math.rad(90), 0))
	weld(body, grip, CFrame.new(-0.6, -0.9, 0))
	local bitWeld = weld(body, bit, CFrame.new(1.8, 0, 0))

	body.Parent = model
	grip.Parent = model
	bit.Parent = model
	model.Parent = character

	return { model = model, bit = bit, bitWeld = bitWeld, spin = 0, pet = nil, petBob = 0 }
end

local function setPet(rig: Rig, player: Player, petId: string)
	if rig.pet then
		rig.pet:Destroy()
		rig.pet = nil
	end
	local pet = petById[petId]
	if not pet then
		return
	end
	local part = makePart("Pet", Vector3.new(1.6, 1.2, 2), Enum.PartType.Block)
	part.Anchored = true
	part.Color = Color3.fromHex(pet.color)
	part.Material = Enum.Material.SmoothPlastic
	local meshId = AssetIds.Meshes.Pets[petId]
	if meshId and AssetIds.isSet(meshId) then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = AssetIds.image(meshId)
		mesh.Parent = part
	else
		-- Two eye studs give the stand-in a readable "front" at phone size.
		for _, x in { -0.4, 0.4 } do
			local eye = makePart("Eye", Vector3.new(0.3, 0.3, 0.1), Enum.PartType.Block)
			eye.Color = Color3.fromHex("F1EFE8")
			eye.Material = Enum.Material.Neon
			local w = Instance.new("Weld")
			w.Part0 = part
			w.Part1 = eye
			w.C0 = CFrame.new(x, 0.25, -1)
			w.Parent = eye
			eye.Parent = part
		end
	end
	local character = player.Character
	part.Parent = if character then character else nil
	rig.pet = part
end

local function attach(player: Player, character: Model)
	local existing = rigs[player]
	if existing then
		existing.model:Destroy()
		if existing.pet then
			existing.pet:Destroy()
		end
		rigs[player] = nil
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local rig = buildDrill(character, humanoid)
	if not rig then
		return
	end
	rigs[player] = rig
	local skin = player:GetAttribute("Skin")
	applySkin(rig, if typeof(skin) == "string" then skin else "default")
	local pet = player:GetAttribute("Pet")
	setPet(rig, player, if typeof(pet) == "string" then pet else "")
end

local function watch(player: Player)
	if player.Character then
		task.spawn(attach, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		attach(player, character)
	end)
	player:GetAttributeChangedSignal("Skin"):Connect(function()
		local rig = rigs[player]
		local skin = player:GetAttribute("Skin")
		if rig and typeof(skin) == "string" then
			applySkin(rig, skin)
		end
	end)
	player:GetAttributeChangedSignal("Pet"):Connect(function()
		local rig = rigs[player]
		local pet = player:GetAttribute("Pet")
		if rig then
			setPet(rig, player, if typeof(pet) == "string" then pet else "")
		end
	end)
end

function DrillRig.init()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local rig = rigs[player]
		if rig then
			rig.model:Destroy()
			if rig.pet then
				rig.pet:Destroy()
			end
			rigs[player] = nil
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		for player, rig in rigs do
			local digging = player:GetAttribute("IsDigging") == true
			if digging then
				rig.spin += dt * 28
				local jitter = math.sin(rig.spin * 9) * 0.04
				rig.bitWeld.C0 = CFrame.new(1.8 + jitter, 0, 0) * CFrame.Angles(rig.spin, 0, 0)
			end
			local pet = rig.pet
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if pet and root and root:IsA("BasePart") then
				rig.petBob += dt * 3
				local target = root.CFrame * CFrame.new(-3, -1.2 + math.sin(rig.petBob) * 0.25, 1.5)
				pet.CFrame = pet.CFrame:Lerp(CFrame.lookAt(target.Position, target.Position + root.CFrame.LookVector), math.min(1, dt * 6))
			end
		end
	end)
end

return DrillRig
