--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/DrillRig (ModuleScript)
-- A chunky part-built drill in every character's hand and a cute part-built
-- pet beside its owner, built client-side for all players from attributes:
-- Skin (body colour), DrillTier (bit look and size), Pet and IsDigging. The
-- local player's bit follows DigController progress so it reacts instantly;
-- other players use the replicated IsDigging. Pets are anchored roots with
-- welded features, CFramed here every frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Layers = require(ReplicatedStorage.Shared.Layers)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local ShaftRenderer = require(script.Parent.ShaftRenderer)

local DrillRig = {}

local G = GameConfig.Geometry
local M = Enum.Material
local BLOCK, BALL, CYLINDER = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder
local TAU = 2 * math.pi
local AXIS = CFrame.Angles(0, math.pi / 2, 0) -- cylinder X axis -> drill forward (-Z)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cylinder X axis -> up
local BODY_Y = 0.78 -- motor housing height above the grip
local IDLE_PITCH = math.rad(-18)
local DIG_PITCH = math.rad(-78) -- pointing at the block underfoot
local SPIN_SPEED = 32 -- rad/s at full speed
local LOCAL_GRACE = 0.3 -- keeps the bit turning through the drop between blocks
local SIDES = { -1, 1 }
local CONE = { 0.82, 0.64, 0.46, 0.28 } -- bit diameters, chuck to tip

local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromHex("1A1F36")
local RUBBER = Color3.fromHex("2B2F3A")
local CHUCK = Color3.fromHex("3B3F48")
local JAWS = Color3.fromHex("A9AFBA")
local TRIGGER = Color3.fromHex("E5484D")
local PINK = Color3.fromHex("FF9AB0")

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

type BitLook = {
	color: Color3,
	flute: Color3,
	material: Enum.Material,
	transparency: number,
	reflectance: number,
	glow: boolean,
	sparkle: boolean,
	spark: Color3,
}

-- One look per GameConfig.Drills tier.
local BIT_LOOKS: { BitLook } = {
	-- Hand Drill: worn, rusty steel
	{ color = hex("9A8F82"), flute = hex("6B645C"), material = M.CorrodedMetal, transparency = 0, reflectance = 0, glow = false, sparkle = false, spark = hex("FFC46B") },
	-- Copper Bit
	{ color = hex("E8803F"), flute = hex("B5582A"), material = M.Metal, transparency = 0, reflectance = 0.15, glow = false, sparkle = false, spark = hex("FFB45C") },
	-- Iron Bit
	{ color = hex("A7ADB8"), flute = hex("767C87"), material = M.Metal, transparency = 0, reflectance = 0.1, glow = false, sparkle = false, spark = hex("FFD27A") },
	-- Steel Auger: light blue-grey
	{ color = hex("BFD6EE"), flute = hex("86A2C2"), material = M.Metal, transparency = 0, reflectance = 0.25, glow = false, sparkle = false, spark = hex("FFE7A8") },
	-- Tungsten Auger: dark with bright edges
	{ color = hex("41454F"), flute = hex("D4DBE6"), material = M.Metal, transparency = 0, reflectance = 0.2, glow = false, sparkle = false, spark = hex("FFF1C9") },
	-- Diamond Core: cyan glass that glitters
	{ color = hex("7FF6FF"), flute = hex("E8FFFF"), material = M.Glass, transparency = 0.15, reflectance = 0.35, glow = false, sparkle = true, spark = hex("B8FBFF") },
	-- Plasma Bore: neon magenta with its own light
	{ color = hex("FF3DE8"), flute = hex("FFB8F6"), material = M.Neon, transparency = 0, reflectance = 0, glow = true, sparkle = true, spark = hex("FF7AF0") },
}

type Drill = {
	model: Model,
	handWeld: Weld,
	grip: CFrame,
	root: Part,
	bitRoot: Part,
	bitWeld: Weld,
	bitBase: CFrame,
	bitParts: { Part },
	skinned: { Part },
	accents: { Part },
	tip: Attachment,
	dust: ParticleEmitter,
	sparks: ParticleEmitter,
	glitter: ParticleEmitter,
	bitLight: PointLight,
	tier: number,
	spin: number,
	spinSpeed: number,
	pose: number,
	kick: number,
	digging: boolean,
	settled: boolean,
}

type Flap = { weld: Weld, pivot: CFrame, out: CFrame, side: number }

type Pet = {
	id: string,
	model: Model,
	root: Part,
	flaps: { Flap },
	flier: boolean,
	flapSpeed: number,
	flapAmp: number,
	bob: number,
	placed: boolean,
}

type Rig = { drill: Drill?, pet: Pet? }

type PetShape = { size: Vector3, flier: boolean, flapSpeed: number, flapAmp: number }

local PET_SHAPES: { [string]: PetShape } = {
	mole = { size = Vector3.new(1.7, 1.5, 1.9), flier = false, flapSpeed = 0, flapAmp = 0 },
	beetle = { size = Vector3.new(1.6, 1.1, 1.9), flier = false, flapSpeed = 0, flapAmp = 0 },
	gecko = { size = Vector3.new(1.1, 0.7, 1.8), flier = false, flapSpeed = 0, flapAmp = 0 },
	bat = { size = Vector3.new(1.25, 1.2, 1.15), flier = true, flapSpeed = 16, flapAmp = 0.7 },
	crab = { size = Vector3.new(1.8, 0.9, 1.35), flier = false, flapSpeed = 0, flapAmp = 0 },
	owl = { size = Vector3.new(1.45, 1.75, 1.35), flier = true, flapSpeed = 5, flapAmp = 0.25 },
	salamander = { size = Vector3.new(1.1, 0.75, 2), flier = false, flapSpeed = 0, flapAmp = 0 },
}

local localPlayer = Players.LocalPlayer
local rigs: { [Player]: Rig } = {}
local localDigUntil = 0
local lastProgress = 0

local petFolder = Instance.new("Folder")
petFolder.Name = "LocalPets"
petFolder.Parent = Workspace

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
	return if found then found else M.Metal
end

local function makePart(name: string, shape: Enum.PartType, size: Vector3, color: Color3, mat: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = mat
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function weldTo(part0: BasePart, part1: BasePart, c0: CFrame): Weld
	local weld = Instance.new("Weld")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.C0 = c0
	weld.Parent = part1
	return weld
end

local function sphereMesh(part: BasePart)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
end

local function stringAttr(player: Player, name: string, default: string): string
	local value = player:GetAttribute(name)
	return if typeof(value) == "string" then value else default
end

local function tierOf(player: Player): number
	local value = player:GetAttribute("DrillTier")
	return math.clamp(if typeof(value) == "number" then math.floor(value) else 1, 1, #BIT_LOOKS)
end

local function dustColor(depth: number): ColorSequence
	return ColorSequence.new(Color3.fromHex(Layers.layerAt(depth).groundColor):Lerp(WHITE, 0.15))
end

-- Drill ---------------------------------------------------------------------------

local function applySkin(drill: Drill, skinId: string)
	local skin = skinById[skinId] or skinById.default
	local body = Color3.fromHex(skin.color)
	local bodyMat = material(skin.material)
	-- Glowing stripes on the glassy/lava skins, plain paint elsewhere.
	local accentMat = if bodyMat == M.CrackedLava or bodyMat == M.Glass then M.Neon else M.SmoothPlastic
	for _, part in drill.skinned do
		part.Color = body
		part.Material = bodyMat
	end
	for _, part in drill.accents do
		part.Color = Color3.fromHex(skin.bitColor)
		part.Material = accentMat
	end
end

local function buildBit(drill: Drill, tier: number)
	for _, part in drill.bitParts do
		part:Destroy()
	end
	table.clear(drill.bitParts)
	local look = BIT_LOOKS[math.clamp(tier, 1, #BIT_LOOKS)]
	local s = 1 + (tier - 1) * 0.09
	local function add(shape: Enum.PartType, size: Vector3, color: Color3, offset: CFrame)
		local part = makePart("Bit", shape, size, color, look.material)
		part.Transparency = look.transparency
		part.Reflectance = look.reflectance
		weldTo(drill.bitRoot, part, offset)
		part.Parent = drill.model
		table.insert(drill.bitParts, part)
	end
	-- Stacked cylinders make the cone; two skewed flutes blur into a spiral when spinning.
	add(CYLINDER, Vector3.new(0.3 * s, 0.3 * s, 0.3 * s), look.flute, CFrame.new(0, 0, -0.15 * s) * AXIS)
	local z = 0.3 * s
	for i, d in CONE do
		local len = (if i == #CONE then 0.36 else 0.42) * s
		add(CYLINDER, Vector3.new(len, d * s, d * s), look.color, CFrame.new(0, 0, -(z + len / 2)) * AXIS)
		z += len
	end
	add(BALL, Vector3.one * 0.2 * s, look.flute, CFrame.new(0, 0, -(z + 0.02 * s)))
	for _, side in SIDES do
		local offset = CFrame.Angles(0, 0, side * 0.9) * CFrame.new(0, 0.27 * s, -1.08 * s) * CFrame.Angles(-0.17, 0.35 * side, 0)
		add(BLOCK, Vector3.new(0.12 * s, 0.14 * s, 1.5 * s), look.flute, offset)
	end
	drill.tip.Position = drill.bitBase.Position + Vector3.new(0, 0, -(z + 0.1 * s))
	drill.bitLight.Color = look.color
	drill.bitLight.Enabled = look.glow
	drill.glitter.Color = ColorSequence.new(look.spark)
	drill.glitter.Enabled = look.sparkle
	drill.sparks.Color = ColorSequence.new(look.spark)
	drill.tier = tier
end

local function buildDrill(character: Model, humanoid: Humanoid): Drill?
	local r6 = humanoid.RigType == Enum.HumanoidRigType.R6
	local hand = character:WaitForChild(if r6 then "Right Arm" else "RightHand", 5)
	if not hand or not hand:IsA("BasePart") then
		return nil
	end
	local gripAttachment = hand:FindFirstChild("RightGripAttachment")
	local gripPos = if gripAttachment and gripAttachment:IsA("Attachment")
		then gripAttachment.Position
		elseif r6 then Vector3.new(0, -1, 0)
		else Vector3.new(0, -0.15, 0)

	local model = Instance.new("Model")
	model.Name = "DrillRig"
	local root = makePart("DrillRoot", BLOCK, Vector3.one * 0.2, WHITE, M.SmoothPlastic)
	root.Transparency = 1
	local skinned: { Part } = {}
	local accents: { Part } = {}
	local function add(name: string, shape: Enum.PartType, size: Vector3, color: Color3, mat: Enum.Material, c0: CFrame, list: { Part }?): Part
		local part = makePart(name, shape, size, color, mat)
		weldTo(root, part, c0)
		part.Parent = model
		if list then
			table.insert(list, part)
		end
		return part
	end

	-- Drill space: origin at the grip, -Z is where the bit points.
	add("Handle", BLOCK, Vector3.new(0.44, 1.1, 0.58), RUBBER, M.SmoothPlastic, CFrame.new(0, 0.05, 0.08) * CFrame.Angles(math.rad(14), 0, 0))
	add("Battery", BLOCK, Vector3.new(0.72, 0.38, 0.9), RUBBER, M.SmoothPlastic, CFrame.new(0, -0.62, 0.06), skinned)
	add("Body", CYLINDER, Vector3.new(1.8, 1.08, 1.08), WHITE, M.SmoothPlastic, CFrame.new(0, BODY_Y, -0.35) * AXIS, skinned)
	add("Cap", BALL, Vector3.one * 1.08, WHITE, M.SmoothPlastic, CFrame.new(0, BODY_Y, 0.55), skinned)
	add("StripeA", CYLINDER, Vector3.new(0.16, 1.14, 1.14), INK, M.SmoothPlastic, CFrame.new(0, BODY_Y, 0.05) * AXIS, accents)
	add("StripeB", CYLINDER, Vector3.new(0.16, 1.14, 1.14), INK, M.SmoothPlastic, CFrame.new(0, BODY_Y, -0.7) * AXIS, accents)
	add("Vent", BLOCK, Vector3.new(0.46, 0.14, 0.7), RUBBER, M.SmoothPlastic, CFrame.new(0, BODY_Y + 0.52, -0.25))
	add("Trigger", BLOCK, Vector3.new(0.16, 0.3, 0.2), TRIGGER, M.SmoothPlastic, CFrame.new(0, 0.33, -0.33))
	add("Chuck", CYLINDER, Vector3.new(0.45, 0.84, 0.84), CHUCK, M.Metal, CFrame.new(0, BODY_Y, -1.47) * AXIS)
	add("Jaws", CYLINDER, Vector3.new(0.2, 0.64, 0.64), JAWS, M.Metal, CFrame.new(0, BODY_Y, -1.79) * AXIS)

	local meshId = AssetIds.Meshes.Drill
	if AssetIds.isSet(meshId) then
		-- A sourced mesh replaces the housing; the tier bit still shows in front.
		local body = model:FindFirstChild("Body")
		if body and body:IsA("BasePart") then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = AssetIds.image(meshId)
			mesh.Parent = body
		end
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and part.Name ~= "Body" and part.Name ~= "Chuck" and part.Name ~= "Jaws" then
				part.Transparency = 1
			end
		end
	end

	local bitBase = CFrame.new(0, BODY_Y, -1.89)
	local bitRoot = makePart("BitRoot", BLOCK, Vector3.one * 0.1, WHITE, M.SmoothPlastic)
	bitRoot.Transparency = 1
	local bitWeld = weldTo(root, bitRoot, bitBase)
	bitRoot.Parent = model

	local tip = Instance.new("Attachment")
	tip.Name = "BitTip"
	tip.Parent = root
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Texture = AssetIds.Particles.Dust
	dust.Enabled = false
	dust.Rate = 18
	dust.Lifetime = NumberRange.new(0.35, 0.7)
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Drag = 3
	dust.Size = NumberSequence.new(0.5, 1.6)
	dust.Transparency = NumberSequence.new(0.35, 1)
	dust.Parent = tip
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Texture = AssetIds.Particles.Sparkle
	sparks.Enabled = false
	sparks.Rate = 14
	sparks.Lifetime = NumberRange.new(0.15, 0.4)
	sparks.Speed = NumberRange.new(6, 12)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -35, 0)
	sparks.Size = NumberSequence.new(0.28, 0)
	sparks.LightEmission = 1
	sparks.Parent = tip
	local glitter = Instance.new("ParticleEmitter")
	glitter.Name = "Glitter"
	glitter.Texture = AssetIds.Particles.Sparkle
	glitter.Enabled = false
	glitter.Rate = 4
	glitter.Lifetime = NumberRange.new(0.4, 0.8)
	glitter.Speed = NumberRange.new(0.3, 1)
	glitter.SpreadAngle = Vector2.new(180, 180)
	glitter.Size = NumberSequence.new(0.3, 0)
	glitter.LightEmission = 1
	glitter.Parent = tip
	local bitLight = Instance.new("PointLight")
	bitLight.Range = 8
	bitLight.Brightness = 2
	bitLight.Shadows = false
	bitLight.Enabled = false
	bitLight.Parent = tip

	local grip = CFrame.new(gripPos)
	local handWeld = weldTo(hand, root, grip * CFrame.Angles(IDLE_PITCH, 0, 0))
	root.Parent = model
	model.Parent = character

	return {
		model = model,
		handWeld = handWeld,
		grip = grip,
		root = root,
		bitRoot = bitRoot,
		bitWeld = bitWeld,
		bitBase = bitBase,
		bitParts = {},
		skinned = skinned,
		accents = accents,
		tip = tip,
		dust = dust,
		sparks = sparks,
		glitter = glitter,
		bitLight = bitLight,
		tier = 0,
		spin = 0,
		spinSpeed = 0,
		pose = 0,
		kick = 0,
		digging = false,
		settled = false,
	}
end

local function stepDrill(drill: Drill, player: Player, digging: boolean, dt: number)
	if digging ~= drill.digging then
		drill.digging = digging
		drill.dust.Enabled = digging
		drill.sparks.Enabled = digging
		if digging then
			local value = player:GetAttribute("Depth")
			local depth = if player == localPlayer then ShaftRenderer.depth() elseif typeof(value) == "number" then value else 0
			drill.dust.Color = dustColor(depth)
		end
	end
	drill.spinSpeed += ((if digging then SPIN_SPEED else 0) - drill.spinSpeed) * math.min(1, dt * (if digging then 10 else 2.5))
	drill.pose += ((if digging then 1 else 0) - drill.pose) * math.min(1, dt * 9)
	drill.kick = math.max(0, drill.kick - dt * 6)
	if not digging and drill.spinSpeed < 0.05 and drill.pose < 0.002 and drill.kick <= 0 then
		if not drill.settled then
			drill.settled = true
			drill.handWeld.C0 = drill.grip * CFrame.Angles(IDLE_PITCH, 0, 0)
		end
		return
	end
	drill.settled = false
	drill.spin = (drill.spin + drill.spinSpeed * dt) % TAU
	local buzz = if digging then math.sin(os.clock() * 70) * 0.025 else 0
	local pitch = IDLE_PITCH + (DIG_PITCH - IDLE_PITCH) * drill.pose + buzz
	drill.handWeld.C0 = drill.grip * CFrame.Angles(pitch, 0, 0) * CFrame.new(0, 0, drill.kick * 0.3)
	drill.bitWeld.C0 = drill.bitBase * CFrame.Angles(0, 0, drill.spin)
end

-- Pets ----------------------------------------------------------------------------

local function petAdd(pet: Pet, shape: Enum.PartType, size: Vector3, color: Color3, mat: Enum.Material, offset: CFrame, round: boolean?): (Part, Weld)
	local part = makePart("PetPart", shape, size, color, mat)
	if round then
		sphereMesh(part)
	end
	local weld = weldTo(pet.root, part, offset)
	part.Parent = pet.model
	return part, weld
end

local function petEyes(pet: Pet, x: number, y: number, z: number, size: number, sclera: Color3?)
	for _, side in SIDES do
		petAdd(pet, BALL, Vector3.one * size, sclera or WHITE, M.SmoothPlastic, CFrame.new(side * x, y, z))
		petAdd(pet, BALL, Vector3.one * size * 0.56, INK, M.SmoothPlastic, CFrame.new(side * x, y - size * 0.04, z - size * 0.3))
		petAdd(pet, BALL, Vector3.one * size * 0.2, WHITE, M.Neon, CFrame.new(side * (x + size * 0.1), y + size * 0.14, z - size * 0.56))
	end
end

local function petWing(pet: Pet, side: number, pivot: CFrame, size: Vector3, color: Color3)
	local out = CFrame.new(side * size.X / 2, 0, 0)
	local _, weld = petAdd(pet, BLOCK, size, color, M.SmoothPlastic, pivot * out, true)
	table.insert(pet.flaps, { weld = weld, pivot = pivot, out = out, side = side })
end

local PET_BUILDERS: { [string]: (Pet, Color3) -> () } = {
	mole = function(pet: Pet, color: Color3)
		petAdd(pet, BLOCK, Vector3.new(1.15, 0.95, 0.35), color:Lerp(WHITE, 0.35), M.SmoothPlastic, CFrame.new(0, -0.2, -0.8), true)
		petAdd(pet, BALL, Vector3.one * 0.5, PINK, M.SmoothPlastic, CFrame.new(0, -0.05, -1.05))
		petEyes(pet, 0.33, 0.32, -0.72, 0.46)
		for _, side in SIDES do
			local claw = CFrame.new(side * 0.68, -0.55, -0.62) * CFrame.Angles(0, side * 0.4, side * 0.3)
			petAdd(pet, BLOCK, Vector3.new(0.6, 0.18, 0.45), PINK, M.SmoothPlastic, claw, true)
		end
	end,
	beetle = function(pet: Pet, color: Color3)
		local dark = hex("2A2D3A")
		pet.root.Reflectance = 0.15
		petAdd(pet, BLOCK, Vector3.new(0.07, 0.25, 1.55), dark, M.SmoothPlastic, CFrame.new(0, 0.5, 0.15))
		petAdd(pet, BLOCK, Vector3.new(1, 0.8, 0.75), dark, M.SmoothPlastic, CFrame.new(0, -0.05, -0.92), true)
		petAdd(pet, BLOCK, Vector3.new(0.22, 0.9, 0.22), color:Lerp(WHITE, 0.2), M.SmoothPlastic, CFrame.new(0, 0.42, -1.18) * CFrame.Angles(math.rad(-30), 0, 0))
		petEyes(pet, 0.27, 0.12, -1.18, 0.38)
		for _, side in SIDES do
			local antenna = CFrame.new(side * 0.28, 0.45, -1.05) * CFrame.Angles(math.rad(-25), 0, side * math.rad(-25))
			petAdd(pet, BLOCK, Vector3.new(0.08, 0.6, 0.08), dark, M.SmoothPlastic, antenna)
			for _, z in SIDES do
				petAdd(pet, BLOCK, Vector3.new(0.5, 0.14, 0.14), dark, M.SmoothPlastic, CFrame.new(side * 0.78, -0.42, z * 0.35) * CFrame.Angles(0, 0, side * -0.5))
			end
		end
	end,
	gecko = function(pet: Pet, color: Color3)
		local dark = color:Lerp(INK, 0.25)
		petAdd(pet, BLOCK, Vector3.new(1, 0.75, 1), color, M.SmoothPlastic, CFrame.new(0, 0.18, -1.05), true)
		petEyes(pet, 0.36, 0.5, -1.12, 0.48)
		petAdd(pet, BLOCK, Vector3.new(0.42, 0.34, 1.1), color, M.SmoothPlastic, CFrame.new(0, -0.05, 1.2) * CFrame.Angles(0, 0.25, 0), true)
		petAdd(pet, BLOCK, Vector3.new(0.26, 0.22, 0.9), dark, M.SmoothPlastic, CFrame.new(0.32, -0.05, 1.95) * CFrame.Angles(0, 0.7, 0), true)
		for _, side in SIDES do
			for _, z in SIDES do
				petAdd(pet, BLOCK, Vector3.new(0.42, 0.14, 0.42), dark, M.SmoothPlastic, CFrame.new(side * 0.6, -0.33, z * 0.5), true)
			end
			petAdd(pet, BLOCK, Vector3.new(0.3, 0.08, 0.3), hex("FFB347"), M.SmoothPlastic, CFrame.new(side * 0.22, 0.36, 0.15 + side * 0.25), true)
		end
	end,
	bat = function(pet: Pet, color: Color3)
		petAdd(pet, BLOCK, Vector3.new(0.8, 0.8, 0.25), color:Lerp(WHITE, 0.3), M.SmoothPlastic, CFrame.new(0, -0.12, -0.52), true)
		petEyes(pet, 0.27, 0.18, -0.5, 0.42)
		for _, side in SIDES do
			petAdd(pet, BLOCK, Vector3.new(0.32, 0.55, 0.14), color:Lerp(INK, 0.15), M.SmoothPlastic, CFrame.new(side * 0.36, 0.72, -0.05) * CFrame.Angles(0, 0, side * -0.35))
			petAdd(pet, BLOCK, Vector3.new(0.07, 0.17, 0.06), WHITE, M.SmoothPlastic, CFrame.new(side * 0.1, -0.22, -0.62))
			petWing(pet, side, CFrame.new(side * 0.45, 0.12, 0), Vector3.new(1.5, 0.08, 0.95), color:Lerp(INK, 0.25))
		end
	end,
	crab = function(pet: Pet, color: Color3)
		local light = color:Lerp(WHITE, 0.25)
		for _, side in SIDES do
			petAdd(pet, CYLINDER, Vector3.new(0.45, 0.13, 0.13), color, M.SmoothPlastic, CFrame.new(side * 0.32, 0.5, -0.35) * UPRIGHT)
			petAdd(pet, BLOCK, Vector3.new(0.8, 0.62, 0.85), light, M.SmoothPlastic, CFrame.new(side * 1.12, 0.05, -0.7) * CFrame.Angles(0, side * 0.35, 0), true)
			petAdd(pet, BLOCK, Vector3.new(0.18, 0.18, 0.5), light, M.SmoothPlastic, CFrame.new(side * 0.95, 0.12, -1.18) * CFrame.Angles(0, side * -0.3, 0))
			for _, z in SIDES do
				petAdd(pet, BLOCK, Vector3.new(0.6, 0.12, 0.12), color:Lerp(INK, 0.15), M.SmoothPlastic, CFrame.new(side * 0.95, -0.32, 0.08 + z * 0.22) * CFrame.Angles(0, 0, side * -0.55))
			end
		end
		petEyes(pet, 0.32, 0.86, -0.38, 0.36)
	end,
	owl = function(pet: Pet, color: Color3)
		local belly = color:Lerp(WHITE, 0.45)
		petAdd(pet, BLOCK, Vector3.new(1, 1.15, 0.3), belly, M.SmoothPlastic, CFrame.new(0, -0.25, -0.58), true)
		petAdd(pet, BLOCK, Vector3.new(1.25, 0.75, 0.25), belly, M.SmoothPlastic, CFrame.new(0, 0.42, -0.6), true)
		petEyes(pet, 0.3, 0.45, -0.66, 0.52, hex("FFD23C"))
		petAdd(pet, BLOCK, Vector3.new(0.2, 0.26, 0.2), hex("FF9A2E"), M.SmoothPlastic, CFrame.new(0, 0.18, -0.82) * CFrame.Angles(math.rad(45), 0, 0))
		for _, side in SIDES do
			petAdd(pet, BLOCK, Vector3.new(0.24, 0.5, 0.16), color:Lerp(INK, 0.2), M.SmoothPlastic, CFrame.new(side * 0.42, 0.98, -0.25) * CFrame.Angles(0, 0, side * -0.4))
			petWing(pet, side, CFrame.new(side * 0.55, 0.05, 0.05), Vector3.new(0.3, 1.05, 0.85), color:Lerp(INK, 0.1))
		end
	end,
	salamander = function(pet: Pet, color: Color3)
		local hot = hex("FF5A1F")
		petAdd(pet, BLOCK, Vector3.new(1.05, 0.8, 1), color, M.SmoothPlastic, CFrame.new(0, 0.18, -1.15), true)
		petEyes(pet, 0.36, 0.5, -1.2, 0.48)
		petAdd(pet, BLOCK, Vector3.new(0.45, 0.36, 1.1), color:Lerp(hot, 0.4), M.SmoothPlastic, CFrame.new(0, -0.05, 1.25) * CFrame.Angles(0, -0.25, 0), true)
		local tail = petAdd(pet, BLOCK, Vector3.new(0.28, 0.24, 0.9), hot, M.Neon, CFrame.new(-0.3, -0.05, 2) * CFrame.Angles(0, -0.7, 0), true)
		for _, side in SIDES do
			for _, z in SIDES do
				petAdd(pet, BLOCK, Vector3.new(0.42, 0.14, 0.42), color:Lerp(WHITE, 0.3), M.SmoothPlastic, CFrame.new(side * 0.58, -0.33, z * 0.55), true)
			end
		end
		for i = 1, 3 do
			petAdd(pet, BALL, Vector3.one * 0.22, hot, M.Neon, CFrame.new(((i % 2) * 2 - 1) * 0.2, 0.36, -0.5 + i * 0.35))
		end
		local light = Instance.new("PointLight")
		light.Color = hot
		light.Range = 8
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = pet.root
		local embers = Instance.new("ParticleEmitter")
		embers.Texture = AssetIds.Particles.Ember
		embers.Rate = 6
		embers.Lifetime = NumberRange.new(0.5, 1)
		embers.Speed = NumberRange.new(1, 2)
		embers.Acceleration = Vector3.new(0, 3, 0)
		embers.Size = NumberSequence.new(0.35, 0)
		embers.Color = ColorSequence.new(hex("FFC65A"), hot)
		embers.LightEmission = 1
		embers.Parent = tail
	end,
}

local function destroyPet(rig: Rig)
	if rig.pet then
		rig.pet.model:Destroy()
		rig.pet = nil
	end
end

local function setPet(player: Player, petId: string)
	local rig = rigs[player]
	if not rig then
		return
	end
	destroyPet(rig)
	local def = petById[petId]
	if not def then
		return
	end
	local shape = PET_SHAPES[petId] or PET_SHAPES.mole
	local color = Color3.fromHex(def.color)
	local model = Instance.new("Model")
	model.Name = `Pet_{player.Name}`
	local root = makePart("PetBody", BLOCK, shape.size, color, M.SmoothPlastic)
	root.Anchored = true
	root.Parent = model
	local pet: Pet = {
		id = petId,
		model = model,
		root = root,
		flaps = {},
		flier = shape.flier,
		flapSpeed = shape.flapSpeed,
		flapAmp = shape.flapAmp,
		bob = math.random() * TAU,
		placed = false,
	}
	local meshId = AssetIds.Meshes.Pets[petId]
	if meshId and AssetIds.isSet(meshId) then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = AssetIds.image(meshId)
		mesh.Parent = root
	else
		sphereMesh(root)
		local build = PET_BUILDERS[petId]
		if build then
			build(pet, color)
		end
	end
	rig.pet = pet
end

local function stepPet(pet: Pet, player: Player, dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		if pet.model.Parent then
			pet.model.Parent = nil
			pet.placed = false
		end
		return
	end
	pet.bob += dt * (if pet.flier then 4 else 3)
	local hover = if pet.flier then 0.9 + math.sin(pet.bob) * 0.35 else -1.75 + math.sin(pet.bob) * 0.15
	local target = (root.CFrame * CFrame.new(2.4, hover, 1.8)).Position
	if player == localPlayer and root.Position.Y < G.SurfaceY - 2 then
		-- Stay inside our own shaft instead of swimming through its walls.
		local center = ClientState.plotCenter()
		if center then
			local limit = G.BlockSize / 2 - 1.4
			target = Vector3.new(math.clamp(target.X, center.X - limit, center.X + limit), target.Y, math.clamp(target.Z, center.Z - limit, center.Z + limit))
		end
	end
	local look = root.CFrame.LookVector
	local goal = CFrame.lookAt(target, target + Vector3.new(look.X, 0, look.Z))
	if not pet.placed then
		pet.placed = true
		pet.root.CFrame = goal
		pet.model.Parent = petFolder
	else
		pet.root.CFrame = pet.root.CFrame:Lerp(goal, math.min(1, dt * 6))
	end
	if #pet.flaps > 0 then
		local angle = math.sin(os.clock() * pet.flapSpeed) * pet.flapAmp
		for _, flap in pet.flaps do
			flap.weld.C0 = flap.pivot * CFrame.Angles(0, 0, flap.side * angle) * flap.out
		end
	end
end

-- Lifecycle -----------------------------------------------------------------------

local function rigFor(player: Player): Rig
	local rig = rigs[player]
	if not rig then
		rig = { drill = nil, pet = nil }
		rigs[player] = rig
	end
	return rig
end

local function attach(player: Player, character: Model)
	local rig = rigFor(player)
	if rig.drill then
		rig.drill.model:Destroy()
		rig.drill = nil
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or player.Character ~= character then
		return
	end
	local drill = buildDrill(character, humanoid)
	if not drill or rigs[player] ~= rig then
		return
	end
	rig.drill = drill
	applySkin(drill, stringAttr(player, "Skin", "default"))
	buildBit(drill, tierOf(player))
end

local function watch(player: Player)
	local rig = rigFor(player)
	if player.Character then
		task.spawn(attach, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		attach(player, character)
	end)
	player:GetAttributeChangedSignal("Skin"):Connect(function()
		local drill = rig.drill
		if drill then
			applySkin(drill, stringAttr(player, "Skin", "default"))
		end
	end)
	player:GetAttributeChangedSignal("DrillTier"):Connect(function()
		local drill = rig.drill
		if drill and drill.tier ~= tierOf(player) then
			buildBit(drill, tierOf(player))
		end
	end)
	player:GetAttributeChangedSignal("Pet"):Connect(function()
		setPet(player, stringAttr(player, "Pet", ""))
	end)
	setPet(player, stringAttr(player, "Pet", ""))
end

function DrillRig.init()
	-- Required here, not at the top: DigController pulls in Juice/LayerFX/ShaftRenderer.
	local DigController = require(script.Parent.DigController)
	DigController.onProgress:Connect(function(progress: number)
		if progress > lastProgress then
			localDigUntil = os.clock() + LOCAL_GRACE
		end
		lastProgress = progress
		ShaftRenderer.setDigProgress(progress)
	end)
	DigController.onDepth:Connect(function(_depth: number)
		local rig = rigs[localPlayer]
		local drill = rig and rig.drill
		if drill and os.clock() < localDigUntil then
			drill.kick = 1 -- recoil as the block gives way
			drill.dust.Color = dustColor(DigController.localDepth())
		end
	end)

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local rig = rigs[player]
		if rig then
			if rig.drill then
				rig.drill.model:Destroy()
			end
			destroyPet(rig)
			rigs[player] = nil
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		for player, rig in rigs do
			local drill = rig.drill
			if drill then
				if drill.model.Parent == nil then
					rig.drill = nil -- the character it lived on is gone
				else
					local digging = if player == localPlayer then now < localDigUntil else player:GetAttribute("IsDigging") == true
					stepDrill(drill, player, digging, dt)
				end
			end
			local pet = rig.pet
			if pet then
				stepPet(pet, player, dt)
			end
		end
	end)
end

return DrillRig
