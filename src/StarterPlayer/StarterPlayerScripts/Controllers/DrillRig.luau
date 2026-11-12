--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/DrillRig (ModuleScript)
-- Every character's drill and equipped pet, built on each client from
-- replicated attributes (DrillTier, Skin, Pet, IsDigging). The drill shows the
-- round tier, so rivals can read each other's progress at a glance. Models
-- come from Shared/Models until Meshes.Drill / Meshes.Pets are sourced.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local DrillModels = require(ReplicatedStorage.Shared.Models.DrillModels)
local Kit = require(ReplicatedStorage.Shared.Models.ModelKit)
local PetModels = require(ReplicatedStorage.Shared.Models.PetModels)
local DigController = require(script.Parent.DigController)

local DrillRig = {}

-- Grip in front of the root at waist height; the bit just reaches the floor.
local HOLD = CFrame.new(0, 0.3, -1.7)
local PET_UPDATE_RANGE = 300 -- studs from the camera; farther pets freeze

type Animated = { group: PetModels.Group, offset: CFrame }

type Pet = {
	model: Model,
	parts: { BasePart },
	rest: { CFrame }, -- root-relative pose of every part
	animated: { [number]: Animated },
	buffer: { CFrame },
	flyer: boolean,
	cframe: CFrame,
	t: number,
}

type Rig = {
	drill: Model?,
	weld: Weld?,
	built: string, -- "tier:skin" the drill was built for
	pet: Pet?,
	petKey: string,
}

local rigs: { [Player]: Rig } = {}

local petFolder = Instance.new("Folder")
petFolder.Name = "LocalPets"
petFolder.Parent = Workspace

local petById: { [string]: typeof(GameConfig.Pets[1]) } = {}
for _, pet in GameConfig.Pets do
	petById[pet.id] = pet
end
local sizeById: { [string]: typeof(GameConfig.PetSizes[1]) } = {}
for _, size in GameConfig.PetSizes do
	sizeById[size.id] = size
end
local skinById: { [string]: typeof(GameConfig.Skins[1]) } = {}
for _, skin in GameConfig.Skins do
	skinById[skin.id] = skin
end

local function stringAttr(player: Player, name: string, default: string): string
	local value = player:GetAttribute(name)
	return if typeof(value) == "string" then value else default
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

--- "mole:huge" -> "mole", 1.8. Bare ids from older saves count as Normal.
local function parsePetKey(key: string): (string?, number)
	local petId, sizeId = string.match(key, "^(%w+):(%w+)$")
	local id = petId or key
	if not petById[id] then
		return nil, 1
	end
	local size = if sizeId then sizeById[sizeId] else nil
	return id, if size then size.scale else 1
end

local function buildDrillModel(tier: number, skinId: string): Model
	local meshId = AssetIds.Meshes.Drill
	if not AssetIds.isSet(meshId) then
		return DrillModels.build(tier, skinId)
	end
	-- A sourced mesh replaces the part-built tiers; the skin still tints it.
	local skin = skinById[skinId] or skinById.default
	local m = Kit.model("Drill")
	local grip = Kit.block(m, Vector3.new(0.4, 0.4, 0.4), CFrame.new(), skin.color, { name = "Grip" })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = AssetIds.image(meshId)
	mesh.Offset = Vector3.new(0, -DrillModels.Length / 2, 0)
	mesh.Parent = grip
	m.PrimaryPart = grip
	return m
end

local function clearDrill(rig: Rig)
	if rig.drill then
		rig.drill:Destroy()
	end
	rig.drill = nil
	rig.weld = nil
	rig.built = ""
end

local function refreshDrill(player: Player, rig: Rig)
	local character = player.Character
	local root = rootOf(player)
	if not character or not root then
		clearDrill(rig)
		return
	end
	local tier = player:GetAttribute("DrillTier")
	local tierNumber = if typeof(tier) == "number" then tier else 1
	local skinId = stringAttr(player, "Skin", "default")
	local key = `{tierNumber}:{skinId}`
	if rig.drill and rig.drill.Parent == character and rig.built == key then
		return
	end
	clearDrill(rig)
	local model = buildDrillModel(tierNumber, skinId)
	local grip = model.PrimaryPart
	if not grip then
		model:Destroy()
		return
	end
	Kit.weld(model, grip)
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = grip
	weld.C0 = HOLD
	weld.Parent = grip
	model.Name = "DrillRig"
	model.Parent = character
	rig.drill = model
	rig.weld = weld
	rig.built = key
end

local function buildPet(petId: string, scale: number): Pet
	local def = petById[petId]
	local meshId = AssetIds.Meshes.Pets[petId]
	local model: Model
	local groups: { [string]: PetModels.Group } = {}
	if meshId and AssetIds.isSet(meshId) then
		model = Kit.model(def.name)
		local body = Kit.block(model, Vector3.new(1.6, 1.2, 2) * scale, CFrame.new(0, 0.6 * scale, 0), def.color, { name = "Root" })
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = AssetIds.image(meshId)
		mesh.Scale = Vector3.one * scale
		mesh.Parent = body
	else
		local built = PetModels.build(petId, scale)
		model, groups = built.model, built.groups
	end

	local animatedByPart: { [BasePart]: Animated } = {}
	for _, group in groups do
		for i, part in group.parts do
			animatedByPart[part] = { group = group, offset = group.offsets[i] }
		end
	end
	local pet: Pet = {
		model = model,
		parts = {},
		rest = {},
		animated = {},
		buffer = {},
		flyer = def.flyer,
		cframe = CFrame.new(),
		t = math.random() * 10,
	}
	-- Built around the origin, so world CFrames are root-relative.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			table.insert(pet.parts, d)
			pet.rest[#pet.parts] = d.CFrame
			pet.animated[#pet.parts] = animatedByPart[d]
			pet.buffer[#pet.parts] = d.CFrame
		end
	end
	return pet
end

local function clearPet(rig: Rig)
	if rig.pet then
		rig.pet.model:Destroy()
	end
	rig.pet = nil
	rig.petKey = ""
end

local function refreshPet(player: Player, rig: Rig)
	local key = stringAttr(player, "Pet", "")
	local root = rootOf(player)
	if key == rig.petKey and (rig.pet ~= nil) == (root ~= nil) then
		return
	end
	clearPet(rig)
	local petId, scale = parsePetKey(key)
	if not petId or not root then
		return
	end
	local pet = buildPet(petId, scale)
	pet.cframe = root.CFrame * CFrame.new(-3, 0, 2)
	pet.model.Parent = petFolder
	rig.pet = pet
	rig.petKey = key
end

local function updatePet(player: Player, pet: Pet, dt: number, camera: Camera?)
	local character = player.Character
	local root = rootOf(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	if camera and (camera.CFrame.Position - root.Position).Magnitude > PET_UPDATE_RANGE then
		return
	end
	pet.t += dt
	local t = pet.t
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	local beside = root.CFrame * CFrame.new(-3.2, 0, 2.2)
	local groundY = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
	local moving = root.AssemblyLinearVelocity.Magnitude > 1
	local y = if pet.flyer
		then root.Position.Y + 1.2 + math.sin(t * 2.2) * 0.35
		else groundY + (if moving then math.abs(math.sin(t * 12)) * 0.3 else 0)
	local position = Vector3.new(beside.Position.X, y, beside.Position.Z)
	local goal = CFrame.lookAt(position, position + look.Unit)
	pet.cframe = pet.cframe:Lerp(goal, math.min(1, dt * 8))

	local wag = CFrame.Angles(0, math.sin(t * (if moving then 12 else 5)) * 0.35, 0)
	for i, rest in pet.rest do
		local animated = pet.animated[i]
		pet.buffer[i] = if animated
			then pet.cframe * animated.group.pivot * wag * animated.offset
			else pet.cframe * rest
	end
	Workspace:BulkMoveTo(pet.parts, pet.buffer, Enum.BulkMoveMode.FireCFrameChanged)
end

local function rigFor(player: Player): Rig
	local rig = rigs[player]
	if not rig then
		rig = { drill = nil, weld = nil, built = "", pet = nil, petKey = "" }
		rigs[player] = rig
	end
	return rig
end

local function refresh(player: Player)
	local rig = rigFor(player)
	refreshDrill(player, rig)
	refreshPet(player, rig)
end

local function watch(player: Player)
	local function onCharacter(character: Model)
		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 10)
			if player.Character == character then
				refresh(player)
			end
		end)
	end
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function()
		local rig = rigs[player]
		if rig then
			clearDrill(rig)
			clearPet(rig)
		end
	end)
	for _, name in { "DrillTier", "Skin", "Pet" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			refresh(player)
		end)
	end
end

function DrillRig.init()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local rig = rigs[player]
		if rig then
			clearDrill(rig)
			clearPet(rig)
			rigs[player] = nil
		end
	end)

	local localPlayer = Players.LocalPlayer
	local jitter = Random.new()
	RunService.Heartbeat:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		for player, rig in rigs do
			local weld = rig.weld
			if weld then
				local digging = if player == localPlayer
					then DigController.isDigging()
					else player:GetAttribute("IsDigging") == true
				-- Jackhammer buzz while drilling; still otherwise.
				weld.C0 = if digging
					then HOLD * CFrame.new(jitter:NextNumber(-0.05, 0.05), jitter:NextNumber(-0.08, 0.04), 0) * CFrame.Angles(0, 0, jitter:NextNumber(-0.03, 0.03))
					else HOLD
			end
			if rig.pet then
				updatePet(player, rig.pet, dt, camera)
			end
		end
	end)
end

return DrillRig
