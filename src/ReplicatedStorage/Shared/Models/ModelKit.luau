--!strict
-- Explorer: ReplicatedStorage/Shared/Models/ModelKit (ModuleScript)
-- Small vocabulary for part-built models, shared by the world builder
-- (server) and item previews / rigs (client). Smooth plastic, no studs,
-- shadows only on parts big enough to read, collisions off unless asked.
--
-- These builders stand in for Creator Store meshes this project cannot
-- import from outside Studio; every model keeps a mesh slot in AssetIds.

local Kit = {}

export type Shape = "Block" | "Wedge" | "Cylinder" | "Ball"
export type Opts = {
	material: Enum.Material?,
	transparency: number?,
	collide: boolean?,
	shadow: boolean?,
	name: string?,
	reflectance: number?,
	tag: string?, -- stored as the "Skin" attribute so drills can be reskinned
}
export type ColorLike = Color3 | string

local SHAPES: { [Shape]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Wedge = Enum.PartType.Wedge,
	Cylinder = Enum.PartType.Cylinder,
	Ball = Enum.PartType.Ball,
}

local SHADOW_MIN = 1.6 -- studs; tiny trim casting shadows only adds noise

function Kit.color(c: ColorLike): Color3
	return if typeof(c) == "string" then Color3.fromHex(c) else c
end

--- Moves a colour toward white (amount > 0) or black (amount < 0).
function Kit.shade(c: ColorLike, amount: number): Color3
	local base = Kit.color(c)
	if amount >= 0 then
		return base:Lerp(Color3.new(1, 1, 1), amount)
	end
	return base:Lerp(Color3.new(0, 0, 0), -amount)
end

function Kit.part(parent: Instance, shape: Shape, size: Vector3, cf: CFrame, c: ColorLike, opts: Opts?): Part
	local o: Opts = opts or {}
	local p = Instance.new("Part")
	p.Name = o.name or shape
	p.Shape = SHAPES[shape]
	p.Size = size
	p.CFrame = cf
	p.Color = Kit.color(c)
	p.Material = o.material or Enum.Material.SmoothPlastic
	p.Transparency = o.transparency or 0
	p.Reflectance = o.reflectance or 0
	p.Anchored = true
	local collide = o.collide == true
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	p.CastShadow = o.shadow ~= false and math.max(size.X, size.Y, size.Z) >= SHADOW_MIN
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.tag then
		p:SetAttribute("Skin", o.tag)
	end
	p.Parent = parent
	return p
end

function Kit.block(parent: Instance, size: Vector3, cf: CFrame, c: ColorLike, opts: Opts?): Part
	return Kit.part(parent, "Block", size, cf, c, opts)
end

--- Roblox wedge: full bottom and back (+Z) faces, slope down toward -Z.
function Kit.wedge(parent: Instance, size: Vector3, cf: CFrame, c: ColorLike, opts: Opts?): Part
	return Kit.part(parent, "Wedge", size, cf, c, opts)
end

function Kit.ball(parent: Instance, diameter: number, cf: CFrame, c: ColorLike, opts: Opts?): Part
	return Kit.part(parent, "Ball", Vector3.new(diameter, diameter, diameter), cf, c, opts)
end

--- Smooth ellipsoid: a built-in Sphere SpecialMesh stretches to the part's
--- size (no asset needed). Collision stays a box, so keep these decorative.
function Kit.ellipsoid(parent: Instance, size: Vector3, cf: CFrame, c: ColorLike, opts: Opts?): Part
	local p = Kit.part(parent, "Block", size, cf, c, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local TO_Y = CFrame.Angles(0, 0, math.pi / 2)
local TO_Z = CFrame.Angles(0, math.pi / 2, 0)

--- Cylinder along the frame's X axis.
function Kit.cylX(parent: Instance, length: number, diameter: number, cf: CFrame, c: ColorLike, opts: Opts?): Part
	return Kit.part(parent, "Cylinder", Vector3.new(length, diameter, diameter), cf, c, opts)
end

--- Cylinder standing along the frame's Y axis.
function Kit.cylY(parent: Instance, length: number, diameter: number, cf: CFrame, c: ColorLike, opts: Opts?): Part
	return Kit.part(parent, "Cylinder", Vector3.new(length, diameter, diameter), cf * TO_Y, c, opts)
end

--- Cylinder along the frame's Z axis.
function Kit.cylZ(parent: Instance, length: number, diameter: number, cf: CFrame, c: ColorLike, opts: Opts?): Part
	return Kit.part(parent, "Cylinder", Vector3.new(length, diameter, diameter), cf * TO_Z, c, opts)
end

--- A beam between two points (square section), for legs, braces and ropes.
function Kit.beam(parent: Instance, a: Vector3, b: Vector3, thickness: number, c: ColorLike, opts: Opts?): Part
	local delta = b - a
	-- lookAt with an up vector parallel to the beam is undefined (NaN rotation).
	local up = if math.abs(delta.Unit.Y) > 0.98 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	return Kit.block(parent, Vector3.new(thickness, thickness, delta.Magnitude), CFrame.lookAt((a + b) / 2, b, up), c, opts)
end

--- Symmetric two-wedge ridge (roof or crystal tip). `cf` is the centre of the
--- base; the ridge runs along X and rises `height` along Y.
function Kit.ridge(parent: Instance, width: number, height: number, depth: number, cf: CFrame, c: ColorLike, opts: Opts?): { Part }
	local half = depth / 2
	local size = Vector3.new(width, height, half)
	local front = Kit.wedge(parent, size, cf * CFrame.new(0, height / 2, -half / 2), c, opts)
	local back = Kit.wedge(parent, size, cf * CFrame.new(0, height / 2, half / 2) * CFrame.Angles(0, math.pi, 0), c, opts)
	return { front, back }
end

--- Crystal prism with a ridge tip, standing on `cf` (base centre).
function Kit.crystal(parent: Instance, width: number, height: number, tip: number, cf: CFrame, c: ColorLike, opts: Opts?): { Part }
	local body = Kit.block(parent, Vector3.new(width, height, width), cf * CFrame.new(0, height / 2, 0), c, opts)
	local parts = Kit.ridge(parent, width, tip, width, cf * CFrame.new(0, height, 0), c, opts)
	table.insert(parts, 1, body)
	return parts
end

--- Segmented ring around the frame's Y axis (pulley rims, halos, trims).
function Kit.ring(parent: Instance, radius: number, segments: number, thickness: number, height: number, cf: CFrame, c: ColorLike, opts: Opts?): { Part }
	local parts = {}
	local arc = 2 * math.pi * radius / segments * 1.04 -- slight overlap hides seams
	for i = 0, segments - 1 do
		local angle = i / segments * math.pi * 2
		local seg = cf * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius)
		table.insert(parts, Kit.block(parent, Vector3.new(arc, height, thickness), seg, c, opts))
	end
	return parts
end

function Kit.model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	if parent then
		m.Parent = parent
	end
	return m
end

function Kit.light(parent: Instance, c: ColorLike, brightness: number, range: number, shadows: boolean?): PointLight
	local light = Instance.new("PointLight")
	light.Color = Kit.color(c)
	light.Brightness = brightness
	light.Range = range
	light.Shadows = shadows == true
	light.Parent = parent
	return light
end

--- Turns an anchored build into one welded, massless, non-colliding assembly
--- rooted at `root`, ready to be attached to a character.
function Kit.weld(model: Model, root: BasePart)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			if d ~= root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = d
				weld.Parent = d
			end
			d.Anchored = false
		end
	end
end

--- Deterministic 0..1 from integers, for asymmetric but stable props.
function Kit.jitter(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

return Kit
