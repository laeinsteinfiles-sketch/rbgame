--!strict
-- Explorer: ReplicatedStorage/Shared/ModelKit (ModuleScript)
-- Part-built art used by both server and client: the pickaxe tool, pets,
-- mine specials and surface props. Low-poly on purpose: few parts, chunky
-- proportions, bright colours, one material per surface. Every builder
-- returns ordinary instances, so Creator Store meshes can replace any of
-- them later without touching the callers.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Hash = require(script.Parent.Hash)
local Types = require(script.Parent.Types)

local ModelKit = {}

export type Shape = "block" | "ball" | "cylinder" | "wedge" | "ellipsoid"

local function toColor(c: string | Color3): Color3
	return if typeof(c) == "Color3" then c else Color3.fromHex(c)
end

local function toMaterial(name: string?): Enum.Material
	if not name then
		return Enum.Material.SmoothPlastic
	end
	local found = (Enum.Material :: any)[name]
	return if found then found else Enum.Material.SmoothPlastic
end

--- Anchored, non-colliding, non-queryable part: the default for decoration.
function ModelKit.part(
	parent: Instance?,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: string | Color3,
	material: string?,
	shape: Shape?
): BasePart
	local p: BasePart
	if shape == "wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		if shape == "ball" then
			part.Shape = Enum.PartType.Ball
		elseif shape == "cylinder" then
			part.Shape = Enum.PartType.Cylinder
		elseif shape == "ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
		p = part
	end
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = toColor(color)
	p.Material = toMaterial(material)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if parent then
		p.Parent = parent
	end
	return p
end

local function light(parent: Instance, color: string | Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = toColor(color)
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

local function label(part: BasePart, face: Enum.NormalId, text: string, textColor: Color3, strokeColor: Color3?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part
	local text_ = Instance.new("TextLabel")
	text_.Size = UDim2.fromScale(1, 1)
	text_.BackgroundTransparency = 1
	text_.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	text_.TextScaled = true
	text_.TextColor3 = textColor
	text_.Text = text
	text_.Parent = gui
	if strokeColor then
		local stroke = Instance.new("UIStroke")
		stroke.Color = strokeColor
		stroke.Thickness = 4
		stroke.Parent = text_
	end
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.Parent = text_
	return text_
end
ModelKit.label = label

local function model(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	return m
end

-- Pickaxe ---------------------------------------------------------------------
-- Built around the Handle's origin: +Y runs up the shaft and -Z is where the
-- pick tip points. With the standard right-hand grip this holds the shaft
-- upright in the idle pose and swings the tip forward on the slash animation.

function ModelKit.pickaxeTool(tierIndex: number, skinId: string?): Tool
	local tiers = GameConfig.Pickaxes
	local tier = tiers[math.clamp(tierIndex, 1, #tiers)]
	local skin: Types.SkinDef = GameConfig.Skins[1]
	for _, s in GameConfig.Skins do
		if s.id == skinId then
			skin = s
		end
	end

	local tool = Instance.new("Tool")
	tool.Name = "Pickaxe"
	tool.ToolTip = tier.name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0, -1.05, 0)
	tool:SetAttribute("Tier", tierIndex)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.34, 3.4, 0.34)
	handle.CFrame = CFrame.new()
	handle.Color = Color3.fromHex(skin.handleColor)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	local function piece(name: string, size: Vector3, cf: CFrame, color: string, material: string?, shape: Shape?): BasePart
		local p = ModelKit.part(tool, name, size, cf, color, material, shape)
		p.Anchored = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end

	local head, mat = tier.headColor, tier.headMaterial
	local y = 1.42
	piece("Grip", Vector3.new(0.44, 0.95, 0.44), CFrame.new(0, -1.05, 0), "3B2A20", "Fabric")
	piece("Pommel", Vector3.new(0.46, 0.22, 0.46), CFrame.new(0, -1.65, 0), head, mat)
	piece("Collar", Vector3.new(0.52, 0.56, 0.66), CFrame.new(0, y, 0), head, mat)
	piece("ArmFront", Vector3.new(0.4, 0.44, 1.05), CFrame.new(0, y - 0.04, -0.78) * CFrame.Angles(math.rad(-9), 0, 0), head, mat)
	local tip = piece(
		"TipFront",
		Vector3.new(0.36, 0.4, 0.95),
		CFrame.new(0, y - 0.24, -1.68) * CFrame.Angles(math.rad(-20), 0, 0),
		head,
		mat,
		"wedge"
	)
	piece("ArmBack", Vector3.new(0.4, 0.44, 0.85), CFrame.new(0, y - 0.04, 0.68) * CFrame.Angles(math.rad(9), 0, 0), head, mat)
	piece(
		"TipBack",
		Vector3.new(0.36, 0.4, 0.7),
		CFrame.new(0, y - 0.2, 1.38) * CFrame.Angles(math.rad(20), math.pi, 0),
		head,
		mat,
		"wedge"
	)
	if tier.glow then
		light(handle, head, 8, 1.4)
		local core = piece("Gem", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, y, -0.34), "FFFFFF", "Neon", "ball")
		core.Color = Color3.fromHex(head):Lerp(Color3.new(1, 1, 1), 0.5)
	end

	-- Swing trail between the tip and the collar, in the skin colour.
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTip"
	a0.Position = Vector3.new(0, 0, -0.45)
	a0.Parent = tip
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBase"
	a1.Position = Vector3.new(0, y, 0)
	a1.Parent = handle
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromHex(skin.trailColor))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.18
	trail.MinLength = 0.05
	trail.LightEmission = if tier.glow then 0.8 else 0.3
	trail.FaceCamera = true
	trail.Parent = handle
	return tool
end

-- Pets ------------------------------------------------------------------------
-- Pets face -Z (their look vector) and sit on y = 0 at their feet; the client
-- pivots them every frame, so every part is anchored.

local function eyes(m: Model, x: number, y: number, z: number, size: number)
	for _, side in { -1, 1 } do
		ModelKit.part(m, "Eye", Vector3.one * size, CFrame.new(side * x, y, z), "FFFFFF", "SmoothPlastic", "ball")
		ModelKit.part(m, "Pupil", Vector3.one * size * 0.55, CFrame.new(side * x, y + size * 0.04, z - size * 0.32), "1B1B22", "SmoothPlastic", "ball")
		ModelKit.part(m, "Shine", Vector3.one * size * 0.18, CFrame.new(side * x + size * 0.12, y + size * 0.2, z - size * 0.5), "FFFFFF", "Neon", "ball")
	end
end

local PET_BUILDERS: { [string]: (m: Model, pet: Types.PetDef) -> BasePart } = {
	mole = function(m, pet)
		local body = ModelKit.part(m, "Body", Vector3.new(2.3, 2, 2.4), CFrame.new(0, 1, 0), pet.color, "SmoothPlastic", "ellipsoid")
		ModelKit.part(m, "Belly", Vector3.new(1.5, 1.3, 1), CFrame.new(0, 0.85, -0.85), "C9A58A", "SmoothPlastic", "ellipsoid")
		ModelKit.part(m, "Nose", Vector3.one * 0.55, CFrame.new(0, 1.15, -1.25), pet.accent, "SmoothPlastic", "ball")
		eyes(m, 0.42, 1.55, -1.0, 0.42)
		for _, side in { -1, 1 } do
			ModelKit.part(m, "Claw", Vector3.new(0.6, 0.22, 0.5), CFrame.new(side * 0.95, 0.25, -0.75) * CFrame.Angles(0, side * 0.3, 0), "F5D6C6", "SmoothPlastic")
			ModelKit.part(m, "Ear", Vector3.new(0.45, 0.45, 0.2), CFrame.new(side * 0.75, 1.9, -0.3), pet.color, "SmoothPlastic", "ellipsoid")
		end
		return body
	end,
	beetle = function(m, pet)
		local body = ModelKit.part(m, "Shell", Vector3.new(2.2, 1.5, 2.6), CFrame.new(0, 0.95, 0.2), pet.color, "SmoothPlastic", "ellipsoid")
		ModelKit.part(m, "Seam", Vector3.new(0.08, 1.52, 2.5), CFrame.new(0, 0.97, 0.2), "1F3A26", "SmoothPlastic")
		ModelKit.part(m, "Head", Vector3.new(1.3, 1, 1), CFrame.new(0, 0.85, -1.2), "1F2A22", "SmoothPlastic", "ellipsoid")
		eyes(m, 0.3, 1.05, -1.6, 0.36)
		for _, side in { -1, 1 } do
			ModelKit.part(m, "Antenna", Vector3.new(0.1, 0.9, 0.1), CFrame.new(side * 0.3, 1.6, -1.55) * CFrame.Angles(-0.5, 0, side * 0.35), "1F2A22", "SmoothPlastic")
			ModelKit.part(m, "Spot", Vector3.new(0.5, 0.3, 0.5), CFrame.new(side * 0.55, 1.55, 0.4), pet.accent, "SmoothPlastic", "ellipsoid")
			for i = -1, 1 do
				ModelKit.part(m, "Leg", Vector3.new(0.5, 0.14, 0.14), CFrame.new(side * 1.1, 0.25, i * 0.7) * CFrame.Angles(0, 0, side * -0.5), "1F2A22", "SmoothPlastic")
			end
		end
		return body
	end,
	gecko = function(m, pet)
		local body = ModelKit.part(m, "Body", Vector3.new(1.4, 0.9, 2.3), CFrame.new(0, 0.7, 0.2), pet.color, "SmoothPlastic", "ellipsoid")
		ModelKit.part(m, "Head", Vector3.new(1.35, 0.95, 1.2), CFrame.new(0, 0.95, -1.15), pet.color, "SmoothPlastic", "ellipsoid")
		eyes(m, 0.42, 1.4, -1.25, 0.55)
		ModelKit.part(m, "Tail", Vector3.new(0.5, 0.4, 1.8), CFrame.new(0, 0.55, 1.9) * CFrame.Angles(0.15, 0.3, 0), pet.color, "SmoothPlastic", "ellipsoid")
		for _, side in { -1, 1 } do
			for _, z in { -0.5, 0.8 } do
				ModelKit.part(m, "Foot", Vector3.one * 0.38, CFrame.new(side * 0.8, 0.2, z), pet.accent, "SmoothPlastic", "ball")
			end
			ModelKit.part(m, "Spot", Vector3.new(0.35, 0.2, 0.35), CFrame.new(side * 0.35, 1.13, 0.3), pet.accent, "SmoothPlastic", "ellipsoid")
		end
		return body
	end,
	bat = function(m, pet)
		local body = ModelKit.part(m, "Body", Vector3.one * 1.7, CFrame.new(0, 1.2, 0), pet.color, "SmoothPlastic", "ball")
		eyes(m, 0.33, 1.4, -0.72, 0.42)
		for _, side in { -1, 1 } do
			ModelKit.part(m, "Ear", Vector3.new(0.18, 0.75, 0.5), CFrame.new(side * 0.5, 2.1, 0) * CFrame.Angles(0, math.pi / 2, side * 0.25), pet.color, "SmoothPlastic", "wedge")
			ModelKit.part(m, "InnerEar", Vector3.new(0.1, 0.5, 0.3), CFrame.new(side * 0.5, 2.05, -0.12) * CFrame.Angles(0, math.pi / 2, side * 0.25), pet.accent, "SmoothPlastic", "wedge")
			local wing = ModelKit.part(m, "Wing", Vector3.new(0.12, 1.1, 1.9), CFrame.new(side * 1.45, 1.35, 0.1) * CFrame.Angles(0, 0, side * 1.2) * CFrame.Angles(0, math.pi / 2 * side, 0), "3A3150", "SmoothPlastic", "wedge")
			wing:SetAttribute("Flap", side)
			ModelKit.part(m, "Fang", Vector3.new(0.12, 0.2, 0.1), CFrame.new(side * 0.12, 0.88, -0.78), "FFFFFF", "SmoothPlastic")
		end
		return body
	end,
	crab = function(m, pet)
		local body = ModelKit.part(m, "Body", Vector3.new(2.5, 1.2, 1.9), CFrame.new(0, 0.9, 0), pet.color, "SmoothPlastic", "ellipsoid")
		for _, side in { -1, 1 } do
			ModelKit.part(m, "Stalk", Vector3.new(0.14, 0.6, 0.14), CFrame.new(side * 0.35, 1.6, -0.55), pet.color, "SmoothPlastic")
			ModelKit.part(m, "Claw", Vector3.new(0.95, 0.75, 0.95), CFrame.new(side * 1.45, 1.0, -0.85), pet.color, "SmoothPlastic", "ellipsoid")
			ModelKit.part(m, "Pincer", Vector3.new(0.3, 0.5, 0.45), CFrame.new(side * 1.45, 1.25, -1.35), pet.accent, "SmoothPlastic", "ellipsoid")
			for i = -1, 1 do
				ModelKit.part(m, "Leg", Vector3.new(0.7, 0.14, 0.14), CFrame.new(side * 1.25, 0.35, 0.2 + i * 0.4) * CFrame.Angles(0, 0, side * -0.6), pet.color, "SmoothPlastic")
			end
		end
		eyes(m, 0.35, 2.0, -0.55, 0.42)
		return body
	end,
	owl = function(m, pet)
		local body = ModelKit.part(m, "Body", Vector3.new(1.9, 2.3, 1.8), CFrame.new(0, 1.35, 0), pet.color, "SmoothPlastic", "ellipsoid")
		ModelKit.part(m, "Belly", Vector3.new(1.3, 1.5, 0.8), CFrame.new(0, 1.05, -0.6), "E9E0FF", "SmoothPlastic", "ellipsoid")
		for _, side in { -1, 1 } do
			ModelKit.part(m, "EyeRing", Vector3.new(0.85, 0.85, 0.2), CFrame.new(side * 0.42, 1.85, -0.8), "FFFFFF", "SmoothPlastic", "ellipsoid")
			ModelKit.part(m, "Iris", Vector3.new(0.55, 0.55, 0.2), CFrame.new(side * 0.42, 1.85, -0.88), pet.accent, "SmoothPlastic", "ellipsoid")
			ModelKit.part(m, "Pupil", Vector3.new(0.3, 0.3, 0.2), CFrame.new(side * 0.42, 1.85, -0.95), "1B1B22", "SmoothPlastic", "ellipsoid")
			ModelKit.part(m, "Tuft", Vector3.new(0.2, 0.55, 0.4), CFrame.new(side * 0.6, 2.55, -0.1) * CFrame.Angles(0, math.pi / 2, side * 0.35), pet.color, "SmoothPlastic", "wedge")
			local wing = ModelKit.part(m, "Wing", Vector3.new(0.35, 1.4, 1.1), CFrame.new(side * 1.0, 1.3, 0.1) * CFrame.Angles(0, 0, side * 0.15), "6A5BB5", "SmoothPlastic", "ellipsoid")
			wing:SetAttribute("Flap", side)
		end
		ModelKit.part(m, "Beak", Vector3.new(0.3, 0.35, 0.3), CFrame.new(0, 1.55, -0.95) * CFrame.Angles(math.pi, 0, 0), "FFB13D", "SmoothPlastic", "wedge")
		return body
	end,
	salamander = function(m, pet)
		local body = ModelKit.part(m, "Body", Vector3.new(1.3, 0.85, 2.6), CFrame.new(0, 0.75, 0.2), pet.color, "SmoothPlastic", "ellipsoid")
		ModelKit.part(m, "Head", Vector3.new(1.3, 0.95, 1.15), CFrame.new(0, 1.0, -1.35), pet.color, "SmoothPlastic", "ellipsoid")
		eyes(m, 0.38, 1.38, -1.5, 0.45)
		ModelKit.part(m, "Tail", Vector3.new(0.55, 0.45, 2.2), CFrame.new(0, 0.6, 2.2) * CFrame.Angles(0.2, -0.35, 0), pet.color, "SmoothPlastic", "ellipsoid")
		for i, z in { -0.5, 0.2, 0.9 } do
			ModelKit.part(m, "Spot", Vector3.new(0.4, 0.2, 0.4), CFrame.new(if i % 2 == 0 then 0.3 else -0.3, 1.15, z), pet.accent, "Neon", "ellipsoid")
		end
		for _, side in { -1, 1 } do
			for _, z in { -0.6, 0.9 } do
				ModelKit.part(m, "Foot", Vector3.one * 0.4, CFrame.new(side * 0.75, 0.2, z), pet.accent, "SmoothPlastic", "ball")
			end
		end
		light(body, pet.accent, 9, 1.2)
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = "rbxasset://textures/particles/fire_main.dds"
		fire.Color = ColorSequence.new(Color3.fromHex(pet.accent), Color3.fromHex(pet.color))
		fire.Size = NumberSequence.new(0.5, 0)
		fire.Lifetime = NumberRange.new(0.4, 0.7)
		fire.Rate = 14
		fire.Speed = NumberRange.new(1, 2)
		fire.LightEmission = 1
		fire.Parent = body
		return body
	end,
}

local TIER_AURA: { [string]: string } = {
	rare = "5AB3FF",
	epic = "C77DFF",
	legendary = "FFC83D",
}

function ModelKit.pet(pet: Types.PetDef): Model
	local m = model(pet.id)
	local build = PET_BUILDERS[pet.id] or PET_BUILDERS.mole
	local body = build(m, pet)
	m.PrimaryPart = body
	local aura = TIER_AURA[pet.tier]
	if aura then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(Color3.fromHex(aura))
		sparkle.Size = NumberSequence.new(0.35, 0)
		sparkle.Lifetime = NumberRange.new(0.6, 1.1)
		sparkle.Rate = 5
		sparkle.Speed = NumberRange.new(0.5, 1.2)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.LightEmission = 1
		sparkle.Parent = body
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = d == body
		end
	end
	return m
end

-- Mine specials ---------------------------------------------------------------
-- Built facing +Z (towards the side camera) around the origin; callers pivot
-- them onto a cell's front face.

function ModelKit.chest(): Model
	local m = model("Chest")
	local base = ModelKit.part(m, "Base", Vector3.new(3, 1.6, 2), CFrame.new(0, 0, 0), "8A5A2B", "Wood")
	ModelKit.part(m, "Lid", Vector3.new(3.1, 0.9, 2.1), CFrame.new(0, 1.2, 0), "6E4421", "Wood")
	for _, x in { -1.05, 1.05 } do
		ModelKit.part(m, "Band", Vector3.new(0.3, 2.6, 2.16), CFrame.new(x, 0.45, 0), "FFC83D", "Metal")
	end
	ModelKit.part(m, "Lock", Vector3.new(0.55, 0.65, 0.2), CFrame.new(0, 0.7, 1.12), "FFD86B", "Metal")
	light(base, "FFC83D", 10, 0.9)
	m.PrimaryPart = base
	return m
end

function ModelKit.crystalCluster(color: string, height: number, seed: number, glow: boolean): Model
	local m = model("Crystals")
	local main: BasePart? = nil
	local count = 3 + seed % 3
	for i = 1, count do
		local h = height * (0.55 + Hash.unit(seed, i, 3) * 0.45)
		local w = height * 0.28
		local tilt = (Hash.unit(seed, i, 5) - 0.5) * 1.2
		local spin = Hash.unit(seed, i, 7) * math.pi
		local x = (Hash.unit(seed, i, 9) - 0.5) * height * 0.9
		local p = ModelKit.part(
			m,
			"Crystal",
			Vector3.new(w, h, w),
			CFrame.new(x, h * 0.35, 0) * CFrame.Angles(0, spin, tilt),
			color,
			if glow then "Neon" else "Glass",
			nil
		)
		if not main then
			main = p
		end
	end
	if glow and main then
		light(main, color, 12, 1.4)
	end
	m.PrimaryPart = main
	return m
end

function ModelKit.relic(): Model
	local m = model("Relic")
	local orb = ModelKit.part(m, "Orb", Vector3.one * 1.6, CFrame.new(0, 0, 0), "F2B33D", "Neon", "ball")
	ModelKit.part(m, "Ring", Vector3.new(0.3, 2.6, 2.6), CFrame.new(0, 0, 0) * CFrame.Angles(0, 0.6, 0.4), "B8860B", "Metal", "cylinder")
	light(orb, "F2B33D", 14, 1.6)
	m.PrimaryPart = orb
	return m
end

-- Surface props -----------------------------------------------------------------
-- Built standing on y = 0 around the origin; callers pivot them into place.

function ModelKit.tree(seed: number): Model
	local m = model("Tree")
	local height = 7 + Hash.unit(seed, 1, 3) * 4
	local trunk = ModelKit.part(m, "Trunk", Vector3.new(1.5, height, 1.5), CFrame.new(0, height / 2, 0), "7A5130", "Wood")
	local greens = { "4CAF50", "5DBB4C", "3E9E47", "6CC24A" }
	for i = 1, 3 do
		local size = 5.5 - i * 0.8 + Hash.unit(seed, i, 5) * 1.5
		local offset = Vector3.new((Hash.unit(seed, i, 7) - 0.5) * 3, height + (i - 1) * 1.6, (Hash.unit(seed, i, 9) - 0.5) * 3)
		local leaf = ModelKit.part(m, "Leaves", Vector3.one * size, CFrame.new(offset), greens[(seed + i) % #greens + 1], "SmoothPlastic", "ball")
		leaf.CastShadow = true
	end
	m.PrimaryPart = trunk
	return m
end

function ModelKit.pine(seed: number): Model
	local m = model("Pine")
	local trunk = ModelKit.part(m, "Trunk", Vector3.new(1.2, 4, 1.2), CFrame.new(0, 2, 0), "6B4428", "Wood")
	local green = if seed % 2 == 0 then "2F8F4E" else "3A9A55"
	for i = 0, 2 do
		local w = 6.5 - i * 1.8
		local h = 3.4
		for _, rot in { 0, math.pi / 2, math.pi, math.pi * 1.5 } do
			ModelKit.part(m, "Needles", Vector3.new(w, h, w / 2), CFrame.new(0, 4 + i * 2.4 + h / 2, 0) * CFrame.Angles(0, rot, 0) * CFrame.new(0, 0, -w / 4), green, "SmoothPlastic", "wedge")
		end
	end
	m.PrimaryPart = trunk
	return m
end

function ModelKit.rock(seed: number, scale: number): Model
	local m = model("Rock")
	local greys = { "8E939B", "7D838C", "9AA0A8" }
	local main: BasePart? = nil
	for i = 1, 2 + seed % 2 do
		local s = scale * (0.6 + Hash.unit(seed, i, 3) * 0.6)
		local p = ModelKit.part(
			m,
			"Stone",
			Vector3.new(s * 1.3, s, s * 1.1),
			CFrame.new((i - 1.5) * s * 0.7, s * 0.35, (Hash.unit(seed, i, 5) - 0.5) * s) * CFrame.Angles(Hash.unit(seed, i, 7) * 0.6, Hash.unit(seed, i, 9) * 3, Hash.unit(seed, i, 11) * 0.5),
			greys[(seed + i) % #greys + 1],
			"Slate"
		)
		p.CastShadow = true
		if not main then
			main = p
		end
	end
	m.PrimaryPart = main
	return m
end

function ModelKit.flowers(seed: number): Model
	local m = model("Flowers")
	local petals = { "FF6B8B", "FFD23F", "FFFFFF", "B48CFF", "FF9F43" }
	local first: BasePart? = nil
	for i = 1, 4 do
		local x, z = (Hash.unit(seed, i, 3) - 0.5) * 3, (Hash.unit(seed, i, 5) - 0.5) * 3
		local stem = ModelKit.part(m, "Stem", Vector3.new(0.15, 0.9, 0.15), CFrame.new(x, 0.45, z), "3E9E47", "SmoothPlastic")
		ModelKit.part(m, "Bloom", Vector3.one * 0.55, CFrame.new(x, 1, z), petals[(seed + i) % #petals + 1], "SmoothPlastic", "ball")
		if not first then
			first = stem
		end
	end
	m.PrimaryPart = first
	return m
end

function ModelKit.lantern(): Model
	local m = model("Lantern")
	local post = ModelKit.part(m, "Post", Vector3.new(0.5, 6, 0.5), CFrame.new(0, 3, 0), "4A3324", "Wood")
	ModelKit.part(m, "Arm", Vector3.new(0.3, 0.3, 1.6), CFrame.new(0, 5.8, -0.6), "4A3324", "Wood")
	ModelKit.part(m, "Cage", Vector3.new(0.9, 1.1, 0.9), CFrame.new(0, 5.1, -1.2), "2B2B2B", "Metal")
	local glow = ModelKit.part(m, "Glow", Vector3.new(0.7, 0.85, 0.7), CFrame.new(0, 5.1, -1.2), "FFD27A", "Neon")
	light(glow, "FFC46B", 16, 1.3)
	m.PrimaryPart = post
	return m
end

function ModelKit.fence(length: number): Model
	local m = model("Fence")
	local posts = math.max(2, math.floor(length / 4) + 1)
	local first: BasePart? = nil
	for i = 0, posts - 1 do
		local x = -length / 2 + i * length / (posts - 1)
		local p = ModelKit.part(m, "Post", Vector3.new(0.6, 3, 0.6), CFrame.new(x, 1.5, 0), "8A5A2B", "Wood")
		if not first then
			first = p
		end
	end
	for _, y in { 1.2, 2.4 } do
		ModelKit.part(m, "Rail", Vector3.new(length, 0.35, 0.3), CFrame.new(0, y, 0), "A06B3A", "Wood")
	end
	m.PrimaryPart = first
	return m
end

--- Market stall with a striped awning and a sign. Faces +Z.
function ModelKit.stall(title: string, stripeA: string, stripeB: string, signColor: string): Model
	local m = model("Stall")
	local counter = ModelKit.part(m, "Counter", Vector3.new(9, 3, 3), CFrame.new(0, 1.5, 0), "9A6534", "Wood")
	ModelKit.part(m, "CounterTop", Vector3.new(9.6, 0.4, 3.6), CFrame.new(0, 3.2, 0), "C48A4A", "Wood")
	for _, x in { -4.3, 4.3 } do
		ModelKit.part(m, "Post", Vector3.new(0.6, 8, 0.6), CFrame.new(x, 4, -1.2), "7A4E2A", "Wood")
	end
	for i = 0, 5 do
		local stripe = ModelKit.part(
			m,
			"Awning",
			Vector3.new(1.75, 0.3, 4.8),
			CFrame.new(-4.4 + i * 1.75, 8.2, 0.2) * CFrame.Angles(math.rad(-16), 0, 0),
			if i % 2 == 0 then stripeA else stripeB,
			"Fabric"
		)
		stripe.CastShadow = true
	end
	local sign = ModelKit.part(m, "Sign", Vector3.new(8, 2.2, 0.4), CFrame.new(0, 10.3, -1.2), signColor, "SmoothPlastic")
	label(sign, Enum.NormalId.Back, title, Color3.new(1, 1, 1), Color3.fromHex("1B1E24"))
	label(sign, Enum.NormalId.Front, title, Color3.new(1, 1, 1), Color3.fromHex("1B1E24"))
	m.PrimaryPart = counter
	return m
end

--- Wooden headframe arching over the mine: two A-frames, a beam, sheave
--- wheels and a name board readable from both sides.
function ModelKit.headframe(span: number, height: number): (Model, { TextLabel })
	local m = model("Headframe")
	local wood, dark = "8A5A2B", "5E3B1E"
	local first: BasePart? = nil
	for _, side in { -1, 1 } do
		local x = side * span / 2
		for _, lean in { -1, 1 } do
			local beam = ModelKit.part(m, "Leg", Vector3.new(1, height + 1, 1), CFrame.new(x, height / 2, lean * 1.6) * CFrame.Angles(lean * 0.18, 0, 0), wood, "Wood")
			beam.CastShadow = true
			if not first then
				first = beam
			end
		end
		ModelKit.part(m, "Brace", Vector3.new(0.6, 0.6, 4), CFrame.new(x, height * 0.45, 0), dark, "Wood")
		-- Cylinders run along X; turn the wheel so its face shows from the front.
		ModelKit.part(m, "Wheel", Vector3.new(0.6, 4.4, 4.4), CFrame.new(x, height + 1.4, 0) * CFrame.Angles(0, math.pi / 2, 0), "4A4A4A", "Metal", "cylinder")
	end
	ModelKit.part(m, "Beam", Vector3.new(span + 2, 1.2, 1.4), CFrame.new(0, height, 0), dark, "Wood")
	local board = ModelKit.part(m, "Board", Vector3.new(math.min(26, span * 0.5), 3.6, 0.4), CFrame.new(0, height - 2.6, 0), "2D3142", "SmoothPlastic")
	local labels = {
		label(board, Enum.NormalId.Front, "", Color3.fromHex("FFD23F"), Color3.fromHex("14161C")),
		label(board, Enum.NormalId.Back, "", Color3.fromHex("FFD23F"), Color3.fromHex("14161C")),
	}
	m.PrimaryPart = first
	return m, labels
end

return ModelKit
