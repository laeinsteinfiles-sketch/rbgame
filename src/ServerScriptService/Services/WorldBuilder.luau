--!strict
-- Explorer: ServerScriptService/Services/WorldBuilder (ModuleScript)
-- The surface world, built once at boot before the plots: a terrain valley
-- (flat lawn under the plot grid, dirt roads, grassy mounds, a water moat and
-- a ring of hills and cliffs as the natural boundary), the spawn plaza and
-- seeded part scenery. It also owns the cartoon prop kit and the plot site
-- layout PlotService builds with, so plots and world share one style.
--
-- Two rules keep gameplay intact: nothing, terrain or part, exists within one
-- BlockSize of a shaft axis below SurfaceY (the client renders the shaft
-- there), and every plot pad stays flat, open lawn at SurfaceY.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)

local WorldBuilder = {}

local G = GameConfig.Geometry
local Y0 = G.SurfaceY -- terrain voxels are 4 studs: SurfaceY must stay a multiple of 4
local VOXEL = 4
local SEED = 7331

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

-- Palette -------------------------------------------------------------------------

local Palette = {
	Wood = hex("A0673A"),
	WoodDark = hex("7A4A28"),
	WoodLight = hex("C98B55"),
	WoodDeep = hex("5A3418"),
	Stone = hex("8E9AAF"),
	StoneLight = hex("B5BED0"),
	Steel = UITheme.Swatches.dark.top,
	SteelDark = UITheme.Swatches.dark.bottom,
	Pit = hex("2A221C"),
	Gold = UITheme.Colors.Gold,
	GoldLight = UITheme.Swatches.gold.top,
	GoldDeep = UITheme.Swatches.gold.bottom,
	Orange = UITheme.Colors.Orange,
	Red = UITheme.Swatches.red.bottom,
	Green = UITheme.Colors.Green,
	Cyan = UITheme.Colors.Cyan,
	White = UITheme.Colors.White,
	Lamp = hex("FFD98A"),
	LampLight = hex("FFC46B"),
}
WorldBuilder.Palette = Palette

local LEAVES = { hex("4CB648"), hex("5FCB4F"), hex("3FA33F"), hex("74D65C") }
local AUTUMN = { hex("FF9A2E"), hex("FFB347"), hex("F27D2E") }
local BLOSSOM = { hex("FF9BE6"), hex("FFB8EC"), hex("F77FD0") }
local NEEDLES = { hex("2F8F4E"), hex("38A35A"), hex("44B566") }
local TRUNKS = { hex("7A4A28"), hex("8B5A33"), hex("6B4024") }
local ROCKS = { hex("8E9AAF"), hex("9AA6BC"), hex("7D8AA3") }
local FLOWERS = {
	UITheme.Colors.Pink,
	UITheme.Colors.Gold,
	UITheme.Colors.White,
	UITheme.Colors.Red,
	UITheme.Colors.Purple,
	UITheme.Colors.Blue,
}
local CRYSTALS = { UITheme.Colors.Cyan, UITheme.Colors.Purple, UITheme.Colors.Pink, UITheme.Colors.Green }

-- Plot site layout in studs from the shaft axis. PlotService builds inside
-- PadHalf; the gate (fence opening and name arch) is on the +Z side, facing
-- the road. Dirt extents are voxel aligned so painted terrain has crisp edges.
local Site = table.freeze({
	PadHalf = 24, -- fenced lawn; the old 44-stud island fits inside
	DeckHalf = 10, -- plank deck around the collar
	CollarHalf = 6.5, -- timber collar framing the 8x8 opening
	GateHalf = 6, -- fence opening, centred on the shaft
	DirtHalf = 16, -- trodden dirt around the dig site
	WalkHalf = 4, -- dirt walkway and spur road from the gate
})
WorldBuilder.Site = Site

-- Prop kit ------------------------------------------------------------------------

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis (local X) -> world Y

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--- Walk-through decoration: no collisions, raycasts (so no camera pops),
--- touches or, unless asked for, shadow.
local function decor(p: Part, castShadow: boolean?): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = castShadow == true
	return p
end

--- Upright by default; pass `axis` = CFrame.identity to lay it along world X.
local function cylinder(
	parent: Instance,
	name: string,
	center: Vector3,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	axis: CFrame?
): Part
	local cf = CFrame.new(center) * (axis or UPRIGHT)
	return part(parent, name, Vector3.new(length, diameter, diameter), cf, color, material, Enum.PartType.Cylinder)
end

local function ball(
	parent: Instance,
	name: string,
	center: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	return part(parent, name, Vector3.one * diameter, CFrame.new(center), color, material, Enum.PartType.Ball)
end

--- A square-section block running from `a` to `b` (legs, cables, handles).
local function beam(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material?
): Part
	local span = b - a
	local up = if math.abs(span.Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	return part(
		parent,
		name,
		Vector3.new(thickness, thickness, span.Magnitude),
		CFrame.lookAt((a + b) / 2, b, up),
		color,
		material
	)
end

local function light(parent: BasePart, range: number, color: Color3?, brightness: number?): PointLight
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness or 1.2
	l.Color = color or Palette.LampLight
	l.Shadows = false
	l.Parent = parent
	return l
end

--- A text canvas on one face of a sign board.
local function surface(board: BasePart, face: Enum.NormalId): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = `{face.Name}Face`
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.Parent = board
	return gui
end

--- Chunky cartoon sign text: display font, white fill, ink outline.
local function text(gui: SurfaceGui, value: string, size: UDim2?, position: UDim2?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = size or UDim2.fromScale(1, 1)
	label.Position = position or UDim2.fromScale(0, 0)
	label.FontFace = UITheme.Font.Display
	label.TextScaled = true
	label.TextColor3 = UITheme.Colors.Text
	label.Text = value
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Colors.Ink
	stroke.Thickness = 4
	stroke.Parent = label
	label.Parent = gui
	return label
end

local function pick<T>(list: { T }, rng: Random): T
	return list[rng:NextInteger(1, #list)]
end

local function lamp(parent: Instance, base: Vector3, height: number?)
	local h = height or 9
	part(parent, "LampFoot", Vector3.new(1.4, 0.8, 1.4), CFrame.new(base + Vector3.new(0, 0.4, 0)), Palette.SteelDark)
	part(parent, "LampPost", Vector3.new(0.5, h, 0.5), CFrame.new(base + Vector3.new(0, h / 2, 0)), Palette.SteelDark)
	local cf = CFrame.new(base + Vector3.new(0, h + 0.75, 0))
	local glow = decor(part(parent, "Lamp", Vector3.new(1.2, 1.5, 1.2), cf, Palette.Lamp, Enum.Material.Neon))
	decor(
		part(
			parent,
			"LampCap",
			Vector3.new(1.8, 0.5, 1.8),
			CFrame.new(base + Vector3.new(0, h + 1.75, 0)),
			Palette.SteelDark
		),
		true
	)
	light(glow, 18)
end

local function bush(parent: Instance, base: Vector3, rng: Random, scale: number?)
	local s = scale or rng:NextNumber(0.8, 1.25)
	local yaw = CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
	local main = base + Vector3.new(0, s, 0)
	decor(ball(parent, "Bush", main, 3.6 * s, pick(LEAVES, rng)))
	decor(
		ball(
			parent,
			"Bush",
			base + yaw:VectorToWorldSpace(Vector3.new(1.7 * s, 0.6 * s, 0.5 * s)),
			2.7 * s,
			pick(LEAVES, rng)
		)
	)
	if rng:NextNumber() < 0.4 then
		local bloom = pick(FLOWERS, rng)
		for i = 1, 3 do
			local dir = CFrame.Angles(0, i * 2.1 + rng:NextNumber(0, 0.5), 0)
				:VectorToWorldSpace(Vector3.new(1, 0.9, 0)).Unit
			decor(ball(parent, "Bloom", main + dir * 1.75 * s, 0.7 * s, bloom))
		end
	end
end

local function flowerPatch(parent: Instance, base: Vector3, rng: Random)
	local bloom = pick(FLOWERS, rng)
	decor(ball(parent, "FlowerLeaves", base + Vector3.new(0, 0.1, 0), 2, pick(LEAVES, rng)))
	for i = 1, 3 do
		local a = i * 2.09 + rng:NextNumber(-0.3, 0.3)
		local p = base + Vector3.new(math.cos(a) * 0.75, 1 + rng:NextNumber(0, 0.35), math.sin(a) * 0.75)
		decor(ball(parent, "Flower", p, 0.8, bloom))
	end
end

local function rock(parent: Instance, base: Vector3, rng: Random, size: number)
	local tilt = CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 2 * math.pi), rng:NextNumber(-0.3, 0.3))
	local dims = Vector3.new(size, size * rng:NextNumber(0.55, 0.8), size * rng:NextNumber(0.7, 1))
	local main = part(
		parent,
		"Rock",
		dims,
		CFrame.new(base + Vector3.new(0, dims.Y * 0.3, 0)) * tilt,
		pick(ROCKS, rng),
		Enum.Material.Slate
	)
	if size < 4 then
		decor(main)
	end
	if rng:NextNumber() < 0.6 then
		local s2 = size * rng:NextNumber(0.4, 0.6)
		local off = tilt:VectorToWorldSpace(Vector3.new(size * 0.6, 0, size * 0.2))
		local cf = CFrame.new(base + Vector3.new(off.X, s2 * 0.2, off.Z))
			* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6.28), 0)
		decor(part(parent, "Rock", Vector3.new(s2, s2 * 0.7, s2 * 0.9), cf, pick(ROCKS, rng), Enum.Material.Slate))
	end
	if rng:NextNumber() < 0.35 then
		-- An ore crystal poking out: the valley hints at what lies below.
		local c = size / 4
		local cf = CFrame.new(base + Vector3.new(0, dims.Y * 0.6, 0))
			* CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.28), rng:NextNumber(-0.5, 0.5))
		decor(part(parent, "Crystal", Vector3.new(0.8, 2.6, 0.8) * c, cf, pick(CRYSTALS, rng), Enum.Material.Neon))
	end
end

--- Low-poly tree. `kind` is "round" (puffy crown), "poplar" (tall stacked)
--- or "pine" (tiered); about one in five round crowns is autumn or blossom.
local function tree(parent: Instance, base: Vector3, rng: Random, kind: string, scale: number)
	local model = Instance.new("Model")
	model.Name = "Tree"
	local s = scale
	local bark = pick(TRUNKS, rng)
	local roll = rng:NextNumber()
	local crown = if roll < 0.1 then AUTUMN elseif roll < 0.2 then BLOSSOM else LEAVES
	-- Trunks start 2 studs below `base` so slopes never leave them floating.
	local function trunk(height: number, width: number)
		cylinder(model, "Trunk", base + Vector3.new(0, height / 2 - 1, 0), height + 2, width, bark, Enum.Material.Wood)
	end
	if kind == "pine" then
		local h = 3 * s
		trunk(h, 1.3 * s)
		local y = h - 0.3 * s
		for i, radius in { 4.4, 3.3, 2.2 } do
			local tier = 2.8 * s
			decor(
				cylinder(model, "Needles", base + Vector3.new(0, y + tier / 2, 0), tier, radius * 2 * s, NEEDLES[i]),
				true
			)
			y += tier * 0.78
		end
		decor(ball(model, "Needles", base + Vector3.new(0, y + 0.9 * s, 0), 2.2 * s, NEEDLES[3]), true)
	elseif kind == "poplar" then
		local h = 6 * s
		trunk(h, 1.1 * s)
		decor(ball(model, "Leaves", base + Vector3.new(0, h + 2 * s, 0), 7 * s, pick(crown, rng)), true)
		decor(ball(model, "Leaves", base + Vector3.new(0, h + 6.2 * s, 0), 5.2 * s, pick(crown, rng)), true)
	else
		local h = 5.5 * s
		trunk(h, 1.6 * s)
		local yaw = CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
		local top = base + Vector3.new(0, h + 1.6 * s, 0)
		decor(ball(model, "Leaves", top, 8.5 * s, pick(crown, rng)), true)
		decor(
			ball(
				model,
				"Leaves",
				top + yaw:VectorToWorldSpace(Vector3.new(3 * s, -1.2 * s, 0.8 * s)),
				6 * s,
				pick(crown, rng)
			),
			true
		)
		decor(
			ball(
				model,
				"Leaves",
				top + yaw:VectorToWorldSpace(Vector3.new(-2.4 * s, 1.6 * s, -1.4 * s)),
				5.6 * s,
				pick(crown, rng)
			),
			true
		)
	end
	model.Parent = parent
end

local function crate(parent: Instance, cframe: CFrame, size: number): Part
	return part(parent, "Crate", Vector3.one * size, cframe, Palette.WoodLight, Enum.Material.WoodPlanks)
end

local function barrel(parent: Instance, base: Vector3)
	cylinder(parent, "Barrel", base + Vector3.new(0, 1.4, 0), 2.8, 2.2, Palette.Wood, Enum.Material.Wood)
	for _, y in { 0.5, 2.3 } do
		decor(cylinder(parent, "Hoop", base + Vector3.new(0, y, 0), 0.3, 2.36, Palette.Steel))
	end
end

--- Ore cart on a short track. The track runs along `cframe`'s Z axis,
--- centred on it; the cart sits `cartOffset` studs along the track.
local function oreCart(parent: Instance, cframe: CFrame, trackLength: number, cartOffset: number)
	local function at(x: number, y: number, z: number): CFrame
		return cframe * CFrame.new(x, y, z)
	end
	for _, x in { -1.1, 1.1 } do
		decor(
			part(parent, "Rail", Vector3.new(0.3, 0.3, trackLength), at(x, 0.4, 0), Palette.Stone, Enum.Material.Metal)
		)
	end
	local ties = math.max(2, math.floor(trackLength / 7))
	for i = 1, ties do
		local z = -trackLength / 2 + (i - 0.5) * trackLength / ties
		decor(part(parent, "Tie", Vector3.new(3.4, 0.25, 0.8), at(0, 0.125, z), Palette.WoodDark, Enum.Material.Wood))
	end
	for _, dz in { -0.9, 0.9 } do
		local wheels = at(0, 0.95, cartOffset + dz)
		decor(
			part(parent, "Wheels", Vector3.new(2.9, 1.2, 1.2), wheels, Palette.SteelDark, nil, Enum.PartType.Cylinder)
		)
	end
	part(parent, "Cart", Vector3.new(2.6, 1.7, 3.4), at(0, 2.25, cartOffset), Palette.Red)
	decor(part(parent, "CartRim", Vector3.new(2.9, 0.3, 3.7), at(0, 3.2, cartOffset), Palette.Steel))
	decor(ball(parent, "Ore", at(-0.4, 3.45, cartOffset + 0.4).Position, 1.5, Palette.GoldDeep, Enum.Material.Metal))
	decor(ball(parent, "Ore", at(0.5, 3.35, cartOffset - 0.6).Position, 1.2, Palette.Cyan, Enum.Material.Neon))
end

WorldBuilder.Kit = {
	part = part,
	decor = decor,
	cylinder = cylinder,
	ball = ball,
	beam = beam,
	light = light,
	surface = surface,
	text = text,
	bush = bush,
	crate = crate,
	barrel = barrel,
	oreCart = oreCart,
}

-- Layout --------------------------------------------------------------------------

type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

local function rect(minX: number, maxX: number, minZ: number, maxZ: number): Rect
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

local function grow(r: Rect, by: number): Rect
	return rect(r.minX - by, r.maxX + by, r.minZ - by, r.maxZ + by)
end

local function touches(r: Rect, x: number, z: number, radius: number): boolean
	return x + radius > r.minX and x - radius < r.maxX and z + radius > r.minZ and z - radius < r.maxZ
end

local function snap(v: number): number
	return math.floor(v / VOXEL + 0.5) * VOXEL
end

--- Shaft axes on the surface. Same grid as PlotService has always used.
function WorldBuilder.plotCenters(): { Vector3 }
	local cols = G.PlotColumns
	local rows = math.ceil(G.MaxPlayers / cols)
	local centers: { Vector3 } = {}
	for i = 0, G.MaxPlayers - 1 do
		local col, row = i % cols, i // cols
		centers[i + 1] = Vector3.new((col - (cols - 1) / 2) * G.PlotSpacing, 0, (row - (rows - 1) / 2) * G.PlotSpacing)
	end
	return centers
end

type Layout = {
	centers: { Vector3 },
	rows: { number }, -- distinct plot row Z, ascending
	avenues: { number }, -- road Z on the gate side of each row
	roadMinX: number,
	roadMaxX: number,
	spineX: number, -- north-south road through the plaza
	spineMinZ: number,
	spineMaxZ: number,
	plaza: Vector3,
	mineZ: number, -- face of the mine mesa, north of the first road
	floor: Rect, -- flat lawn
	moat: Rect, -- outer edge of the water ring around the lawn
	world: Rect, -- terrain extent (hills beyond the moat)
	keepOut: { Rect }, -- plots, roads and set pieces: no mounds or scatter
}

local function computeLayout(): Layout
	local centers = WorldBuilder.plotCenters()
	local pad = Site.PadHalf
	local minX, maxX, minZ = math.huge, -math.huge, math.huge
	local seen: { [number]: boolean } = {}
	local rows: { number } = {}
	for _, c in centers do
		minX, maxX, minZ = math.min(minX, c.X), math.max(maxX, c.X), math.min(minZ, c.Z)
		if not seen[c.Z] then
			seen[c.Z] = true
			table.insert(rows, c.Z)
		end
	end
	table.sort(rows)
	local avenues: { number } = {}
	for i, z in rows do
		avenues[i] = z + G.PlotSpacing / 2
	end
	-- An even column count leaves a free corridor on x = 0 between the middle columns.
	local spineX = if G.PlotColumns % 2 == 0 then 0 else G.PlotSpacing / 2
	local lastAvenue = avenues[#avenues]
	local mineZ = snap(rows[1] - 20)
	local roadMinX, roadMaxX = snap(minX - pad - 4), snap(maxX + pad + 4)
	local floor = rect(snap(minX - pad - 32), snap(maxX + pad + 32), snap(minZ - pad - 40), snap(lastAvenue + 32))
	local moat = grow(floor, 24)
	local plaza = Vector3.new(spineX, Y0, rows[math.ceil(#rows / 2)])

	local keepOut: { Rect } = {}
	for _, c in centers do
		table.insert(keepOut, rect(c.X - pad - 2, c.X + pad + 2, c.Z - pad - 2, c.Z + pad + 2))
		local walk = Site.WalkHalf + 2
		table.insert(keepOut, rect(c.X - walk, c.X + walk, c.Z + pad, c.Z + G.PlotSpacing / 2 + 6))
	end
	for _, z in avenues do
		table.insert(keepOut, rect(roadMinX - 2, roadMaxX + 2, z - 6, z + 6))
	end
	table.insert(keepOut, rect(spineX - 6, spineX + 6, mineZ - 4, lastAvenue + 6))
	table.insert(keepOut, rect(plaza.X - 24, plaza.X + 24, plaza.Z - 28, plaza.Z + 24))
	table.insert(keepOut, rect(spineX - 24, spineX + 24, floor.minZ, mineZ + 4))

	return {
		centers = centers,
		rows = rows,
		avenues = avenues,
		roadMinX = roadMinX,
		roadMaxX = roadMaxX,
		spineX = spineX,
		spineMinZ = mineZ,
		spineMaxZ = lastAvenue + 4,
		plaza = plaza,
		mineZ = mineZ,
		floor = floor,
		moat = moat,
		world = grow(moat, 96),
		keepOut = keepOut,
	}
end

-- Terrain -------------------------------------------------------------------------

type Mound = { x: number, z: number, cy: number, r: number }
local mounds: { Mound } = {}

local function fill(
	minX: number,
	maxX: number,
	minY: number,
	maxY: number,
	minZ: number,
	maxZ: number,
	material: Enum.Material
)
	Workspace.Terrain:FillBlock(
		CFrame.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2),
		Vector3.new(maxX - minX, maxY - minY, maxZ - minZ),
		material
	)
end

local function replace(r: Rect, minY: number, maxY: number, from: { Enum.Material }, to: Enum.Material)
	local region = Region3.new(Vector3.new(r.minX, minY, r.minZ), Vector3.new(r.maxX, maxY, r.maxZ)):ExpandToGrid(VOXEL)
	for _, material in from do
		Workspace.Terrain:ReplaceMaterial(region, VOXEL, material, to)
	end
end

--- Repaints the top voxel layer of the lawn (roads, dirt) without changing its shape.
local function paint(minX: number, maxX: number, minZ: number, maxZ: number, material: Enum.Material)
	fill(minX, maxX, Y0 - VOXEL, Y0, minZ, maxZ, material)
end

--- A terrain ball whose crown rises `peak` studs above the lawn.
local function mound(x: number, z: number, radius: number, peak: number, material: Enum.Material)
	local cy = Y0 + peak - radius
	Workspace.Terrain:FillBall(Vector3.new(x, cy, z), radius, material)
	table.insert(mounds, { x = x, z = z, cy = cy, r = radius })
end

local function footprint(radius: number, peak: number): number
	return math.sqrt(math.max(0, 2 * radius * peak - peak * peak))
end

--- Ground height at (x, z), following every mound and hill built so far.
local function groundY(x: number, z: number): number
	local y = Y0
	for _, m in mounds do
		local d2 = (x - m.x) ^ 2 + (z - m.z) ^ 2
		if d2 < m.r * m.r then
			y = math.max(y, m.cy + math.sqrt(m.r * m.r - d2))
		end
	end
	return y
end

--- A lawn mound, skipped if it would spill onto a plot, road or set piece.
local function valleyMound(L: Layout, x: number, z: number, radius: number, peak: number)
	local reach = footprint(radius, peak) + 1
	for _, r in L.keepOut do
		if touches(r, x, z, reach) then
			return
		end
	end
	mound(x, z, radius, peak, Enum.Material.Grass)
end

type RingPoint = { p: Vector3, n: Vector3 }

--- Points around a rectangle with outward normals, corners included.
local function ring(r: Rect, spacing: number): { RingPoint }
	local points: { RingPoint } = {}
	local w, d = r.maxX - r.minX, r.maxZ - r.minZ
	local nx, nz = math.max(1, math.round(w / spacing)), math.max(1, math.round(d / spacing))
	for i = 1, nx - 1 do
		local x = r.minX + w * i / nx
		table.insert(points, { p = Vector3.new(x, 0, r.minZ), n = Vector3.new(0, 0, -1) })
		table.insert(points, { p = Vector3.new(x, 0, r.maxZ), n = Vector3.new(0, 0, 1) })
	end
	for i = 1, nz - 1 do
		local z = r.minZ + d * i / nz
		table.insert(points, { p = Vector3.new(r.minX, 0, z), n = Vector3.new(-1, 0, 0) })
		table.insert(points, { p = Vector3.new(r.maxX, 0, z), n = Vector3.new(1, 0, 0) })
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x = if sx < 0 then r.minX else r.maxX
			local z = if sz < 0 then r.minZ else r.maxZ
			table.insert(points, { p = Vector3.new(x, 0, z), n = Vector3.new(sx, 0, sz).Unit })
		end
	end
	return points
end

local function buildTerrain(L: Layout, rng: Random)
	local terrain = Workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Grass, hex("6CCB4A"))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, hex("5BBE3E"))
	terrain:SetMaterialColor(Enum.Material.Ground, hex("D6A866"))
	terrain:SetMaterialColor(Enum.Material.Sand, hex("F2D492"))
	terrain:SetMaterialColor(Enum.Material.Rock, hex("8E9AAF"))
	terrain:SetMaterialColor(Enum.Material.Slate, hex("7D8AA3"))
	terrain.WaterColor = hex("38BDF0")
	terrain.WaterTransparency = 0.35
	terrain.WaterReflectance = 0.35
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 6

	local W, F, M = L.world, L.floor, L.moat

	-- Lawn: one slab whose top is exactly SurfaceY everywhere.
	fill(W.minX, W.maxX, Y0 - 12, Y0, W.minZ, W.maxZ, Enum.Material.Grass)

	-- Hills ring beyond the moat: a broken inner ridge the moat later cuts into
	-- cliffs, taller rolling hills behind it, and rocky knobs.
	for _, point in ring(M, 40) do
		local tangent = Vector3.new(-point.n.Z, 0, point.n.X)
		local r1 = rng:NextNumber(24, 34)
		local c1 = point.p + point.n * (r1 * 0.5 + rng:NextNumber(0, 8)) + tangent * rng:NextNumber(-8, 8)
		mound(c1.X, c1.Z, r1, r1 * rng:NextNumber(0.45, 0.65), Enum.Material.Grass)
		local r2 = rng:NextNumber(36, 50)
		local c2 = point.p + point.n * (r2 * 0.8 + 24) + tangent * rng:NextNumber(-12, 12)
		mound(c2.X, c2.Z, r2, r2 * rng:NextNumber(0.6, 0.8), Enum.Material.LeafyGrass)
		if rng:NextNumber() < 0.45 then
			local c3 = point.p + point.n * rng:NextNumber(6, 18) + tangent * rng:NextNumber(-14, 14)
			local r3 = rng:NextNumber(7, 12)
			mound(
				c3.X,
				c3.Z,
				r3,
				r3 + rng:NextNumber(-3, 4),
				if rng:NextNumber() < 0.5 then Enum.Material.Rock else Enum.Material.Slate
			)
		end
	end

	-- Gentle mounds in the gaps between plots and along the lawn's edges.
	for i = 1, G.PlotColumns - 1 do
		local gapX = (i - G.PlotColumns / 2) * G.PlotSpacing
		if gapX ~= L.spineX then
			for _, z in L.rows do
				valleyMound(L, gapX, z, 18, 6)
				valleyMound(L, gapX + 7, z + 15, 12, 4)
				valleyMound(L, gapX - 6, z - 14, 11, 3.5)
			end
		end
	end
	for _, c in L.centers do
		if c.Z == L.rows[1] then
			valleyMound(L, c.X, F.minZ + 18, 13, 5)
		end
	end
	for _, z in L.rows do
		valleyMound(L, F.minX + 14, z, 12, 4.5)
		valleyMound(L, F.maxX - 14, z, 12, 4.5)
	end
	for _, x in { -0.8, -0.3, 0.3, 0.8 } do
		valleyMound(L, x * F.maxX, F.maxZ - 14, 10, 3.5)
	end

	-- Mine mesa north of the plaza: a grassy dome with a sheer rock face.
	local mx, mz = L.spineX, L.mineZ
	mound(mx, mz - 26, 22, 12, Enum.Material.Grass)
	fill(mx - 12, mx + 12, Y0, Y0 + 12, mz - 12, mz, Enum.Material.Rock)
	for _, sx in { -1, 1 } do
		terrain:FillBall(Vector3.new(mx + sx * 11, Y0 + 3, mz - 5), 6, Enum.Material.Rock)
	end
	replace(rect(mx - 24, mx + 24, mz - 16, mz), Y0, Y0 + 24, { Enum.Material.Grass }, Enum.Material.Rock)

	-- Moat: carve every strip full height (hills become cliffs), then lay a
	-- sand bed and water whose surface sits 2 studs under the lawn.
	local strips = {
		rect(M.minX, M.maxX, M.minZ, F.minZ),
		rect(M.minX, M.maxX, F.maxZ, M.maxZ),
		rect(M.minX, F.minX, F.minZ, F.maxZ),
		rect(F.maxX, M.maxX, F.minZ, F.maxZ),
	}
	for _, s in strips do
		fill(s.minX, s.maxX, Y0 - 8, Y0 + 160, s.minZ, s.maxZ, Enum.Material.Air)
		fill(s.minX, s.maxX, Y0 - 12, Y0 - 8, s.minZ, s.maxZ, Enum.Material.Sand)
		fill(s.minX, s.maxX, Y0 - 8, Y0 - 2, s.minZ, s.maxZ, Enum.Material.Water)
	end
	-- Sandy shore on the lawn side, rock cliffs on the hill side.
	local hills = { Enum.Material.Grass, Enum.Material.LeafyGrass }
	replace(rect(F.minX, F.maxX, F.minZ, F.minZ + 8), Y0 - 12, Y0, hills, Enum.Material.Sand)
	replace(rect(F.minX, F.maxX, F.maxZ - 8, F.maxZ), Y0 - 12, Y0, hills, Enum.Material.Sand)
	replace(rect(F.minX, F.minX + 8, F.minZ, F.maxZ), Y0 - 12, Y0, hills, Enum.Material.Sand)
	replace(rect(F.maxX - 8, F.maxX, F.minZ, F.maxZ), Y0 - 12, Y0, hills, Enum.Material.Sand)
	replace(rect(M.minX - 12, M.maxX + 12, M.minZ - 12, M.minZ), Y0 - 12, Y0 + 160, hills, Enum.Material.Rock)
	replace(rect(M.minX - 12, M.maxX + 12, M.maxZ, M.maxZ + 12), Y0 - 12, Y0 + 160, hills, Enum.Material.Rock)
	replace(rect(M.minX - 12, M.minX, M.minZ, M.maxZ), Y0 - 12, Y0 + 160, hills, Enum.Material.Rock)
	replace(rect(M.maxX, M.maxX + 12, M.minZ, M.maxZ), Y0 - 12, Y0 + 160, hills, Enum.Material.Rock)
	-- Boulders along the shore and a few rock islets.
	for _ = 1, 18 do
		local s = pick(strips, rng)
		local x, z = rng:NextNumber(s.minX + 4, s.maxX - 4), rng:NextNumber(s.minZ + 4, s.maxZ - 4)
		terrain:FillBall(Vector3.new(x, Y0 - 4, z), rng:NextNumber(3, 5.5), Enum.Material.Rock)
	end

	-- Roads, the plaza spine and each dig site's dirt yard.
	local dirt = Enum.Material.Ground
	for _, z in L.avenues do
		paint(L.roadMinX, L.roadMaxX, z - 4, z + 4, dirt)
	end
	paint(L.spineX - 4, L.spineX + 4, L.spineMinZ, L.spineMaxZ, dirt)
	for _, c in L.centers do
		local walk, yard = Site.WalkHalf, Site.DirtHalf
		paint(c.X - yard, c.X + yard, c.Z - yard, c.Z + yard, dirt)
		paint(c.X - walk, c.X + walk, c.Z + yard, c.Z + G.PlotSpacing / 2 - 4, dirt)
		paint(c.X + yard, c.X + Site.PadHalf, c.Z - 8, c.Z + 8, dirt)
	end

	-- Last: empty a 16x16 column under every shaft so no terrain can poke into
	-- the client-rendered blocks and walls (plot centres sit on the voxel grid).
	for _, c in L.centers do
		local h = G.BlockSize
		fill(c.X - h, c.X + h, Y0 - 64, Y0 + 8, c.Z - h, c.Z + h, Enum.Material.Air)
	end
end

-- Set pieces ----------------------------------------------------------------------

local function buildPlaza(parent: Instance, L: Layout)
	local model = Instance.new("Model")
	model.Name = "SpawnPlaza"
	local o = L.plaza
	local function v(x: number, y: number, z: number): Vector3
		return o + Vector3.new(x, y, z)
	end

	-- Paving: stacked discs read as a rim, the floor and an inlay.
	cylinder(model, "PlazaRim", v(0, 0.15, 0), 0.3, 38, Palette.Stone)
	cylinder(model, "PlazaFloor", v(0, 0.2, 0), 0.4, 35.6, hex("F4E4BC"))
	cylinder(model, "PlazaInlay", v(0, 0.25, 0), 0.5, 20, hex("E8C27E"))

	-- Monument: a giant drill biting into a stone pedestal, ringed by crystals.
	cylinder(model, "Pedestal", v(0, 1.5, 0), 2, 12, Palette.Stone)
	cylinder(model, "PedestalTrim", v(0, 2.35, 0), 0.5, 12.6, Palette.Gold)
	cylinder(model, "PedestalTop", v(0, 3, 0), 1, 10, Palette.StoneLight)
	for i = 1, 5 do
		local color = if i % 2 == 1 then Palette.Gold else Palette.Orange
		cylinder(model, "DrillBit", v(0, 3.5 + (i - 0.5) * 1.8, 0), 1.8, 2 * (0.7 + 0.55 * i), color)
	end
	local collar = cylinder(model, "DrillCollar", v(0, 13, 0), 1, 7.6, Palette.Steel)
	cylinder(model, "DrillBody", v(0, 17, 0), 7, 7, Palette.Red)
	for _, y in { 15.3, 18.9 } do
		cylinder(model, "DrillBand", v(0, y, 0), 0.6, 7.4, Palette.Gold)
	end
	cylinder(model, "DrillCap", v(0, 21.1, 0), 1.2, 5.6, Palette.SteelDark)
	cylinder(model, "DrillExhaust", v(1.3, 22.7, 0.8), 2, 1.2, Palette.Steel)
	part(model, "DrillHandles", Vector3.new(13, 1, 1), CFrame.new(v(0, 17, 0)), Palette.Steel)
	for _, sx in { -1, 1 } do
		cylinder(model, "DrillGrip", v(sx * 6.4, 17, 0), 2.4, 1.6, Palette.SteelDark, nil, CFrame.identity)
	end
	light(collar, 26, Palette.LampLight, 1.6)
	for i, color in CRYSTALS do
		local angle = math.rad(45 + (i - 1) * 90)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local base = v(0, 0.5, 0) + dir * 8
		local face = CFrame.lookAt(base, base + dir) -- -Z points away from the drill
		decor(
			part(
				model,
				"Crystal",
				Vector3.new(1.4, 4.4, 1.4),
				face * CFrame.new(0, 1.8, 0) * CFrame.Angles(-0.35, 0, 0),
				color,
				Enum.Material.Neon
			)
		)
		decor(
			part(
				model,
				"Crystal",
				Vector3.new(1, 2.6, 1),
				face * CFrame.new(1, 1, 0.4) * CFrame.Angles(-0.2, 0, -0.55),
				color,
				Enum.Material.Neon
			)
		)
	end

	-- Plaques on the pedestal, readable from both roads.
	for _, sz in { -1, 1 } do
		local plaque =
			decor(part(model, "Plaque", Vector3.new(7, 1.6, 0.3), CFrame.new(v(0, 1.5, sz * 6.4)), Palette.GoldDeep))
		text(
			surface(plaque, if sz > 0 then Enum.NormalId.Back else Enum.NormalId.Front),
			`RACE TO {GameConfig.CoreDepth}M!`
		)
	end

	-- Title gateway over the north entrance. Its two boards leave a gap so the
	-- monument completes the title from either side: "DIG TO [drill] THE CORE".
	local archZ = -23
	for _, sx in { -1, 1 } do
		local post = CFrame.new(v(sx * 15.5, 10, archZ))
		part(model, "TitlePost", Vector3.new(1.8, 20, 1.8), post, Palette.WoodDark, Enum.Material.Wood)
		ball(model, "TitleKnob", v(sx * 15.5, 20.6, archZ), 2.6, Palette.Gold)
	end
	local beam = CFrame.new(v(0, 18.4, archZ))
	decor(part(model, "TitleBeam", Vector3.new(32, 1.2, 1.2), beam, Palette.WoodDark, Enum.Material.Wood), true)
	local words = { "DIG TO", "THE CORE" }
	for i, sx in { -1, 1 } do
		local cf = CFrame.new(v(sx * 9.75, 14.6, archZ))
		decor(part(model, "TitleFrame", Vector3.new(11.6, 6, 0.6), cf, Palette.GoldDeep), true)
		local board = decor(part(model, "TitleBoard", Vector3.new(10.6, 5, 0.8), cf, Palette.SteelDark), true)
		-- Back (+Z) is read from the plaza side, Front from the mine side,
		-- where west and east swap places, so the words swap too.
		for face, word in { [Enum.NormalId.Back] = words[i], [Enum.NormalId.Front] = words[3 - i] } do
			local title = text(surface(board, face), word)
			local gradient = Instance.new("UIGradient")
			gradient.Color = ColorSequence.new(UITheme.Colors.White, UITheme.Swatches.gold.top)
			gradient.Rotation = 90
			gradient.Parent = title
		end
	end

	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		lamp(model, v(math.cos(a) * 15, 0.4, math.sin(a) * 15), 8)
	end
	for _, sx in { -1, 1 } do
		local cf = CFrame.lookAt(v(sx * 14, 0.4, 0), v(0, 0.4, 0))
		part(model, "BenchSeat", Vector3.new(5, 0.4, 1.8), cf * CFrame.new(0, 1.5, 0), Palette.Wood, Enum.Material.Wood)
		part(
			model,
			"BenchBack",
			Vector3.new(5, 1.6, 0.35),
			cf * CFrame.new(0, 2.6, 0.75),
			Palette.Wood,
			Enum.Material.Wood
		)
		for _, lx in { -2, 2 } do
			part(model, "BenchLeg", Vector3.new(0.5, 1.3, 1.6), cf * CFrame.new(lx, 0.65, 0), Palette.SteelDark)
		end
	end
	model.Parent = parent
end

local function buildMine(parent: Instance, L: Layout)
	local model = Instance.new("Model")
	model.Name = "OldMine"
	local x, z = L.spineX, L.mineZ
	local function at(dx: number, y: number, dz: number): CFrame
		return CFrame.new(x + dx, Y0 + y, z + dz)
	end
	for _, sx in { -1, 1 } do
		part(model, "MinePost", Vector3.new(1.3, 8, 1.3), at(sx * 3.6, 4, 0.4), Palette.WoodDark, Enum.Material.Wood)
		local lantern = decor(
			part(model, "Lantern", Vector3.new(0.9, 1.2, 0.9), at(sx * 3.6, 6.4, 1.4), Palette.Lamp, Enum.Material.Neon)
		)
		if sx > 0 then
			light(lantern, 16)
		end
	end
	part(model, "MineLintel", Vector3.new(9.8, 1.3, 1.5), at(0, 8.6, 0.4), Palette.WoodDark, Enum.Material.Wood)
	part(model, "MineTunnel", Vector3.new(6, 7.4, 0.6), at(0, 3.7, 0.3), hex("15121C"))
	local plank = decor(
		part(model, "MineSign", Vector3.new(7.5, 2, 0.5), at(0, 10.6, 0.6), Palette.WoodLight, Enum.Material.Wood),
		true
	)
	text(surface(plank, Enum.NormalId.Back), "MINE")
	oreCart(model, at(0, 0, 19), 36, -10)
	model.Parent = parent
end

local function buildDock(parent: Instance, L: Layout)
	local model = Instance.new("Model")
	model.Name = "Dock"
	local x, z = L.spineX - 60, L.floor.maxZ
	part(
		model,
		"DockDeck",
		Vector3.new(5, 0.4, 20),
		CFrame.new(x, Y0 + 0.6, z + 4),
		Palette.WoodLight,
		Enum.Material.WoodPlanks
	)
	for _, dz in { 4, 12 } do
		for _, sx in { -1, 1 } do
			part(
				model,
				"DockPost",
				Vector3.new(0.8, 8, 0.8),
				CFrame.new(x + sx * 2.2, Y0 - 3.2, z + dz),
				Palette.WoodDark,
				Enum.Material.Wood
			)
		end
	end
	barrel(model, Vector3.new(x + 1, Y0 + 0.8, z + 11))
	crate(model, CFrame.new(x - 1.1, Y0 + 2, z + 12.5) * CFrame.Angles(0, 0.3, 0), 2.4)
	model.Parent = parent
end

local function buildBoundary(parent: Instance, L: Layout)
	-- Invisible walls inside the outer hills so nobody walks off the terrain.
	local W = grow(L.world, -24)
	local height = 400
	local function wall(x: number, z: number, sx: number, sz: number)
		local p =
			part(parent, "Boundary", Vector3.new(sx, height, sz), CFrame.new(x, Y0 + height / 2 - 20, z), Palette.White)
		p.Transparency = 1
		p.CastShadow = false
	end
	local midX, midZ = (W.minX + W.maxX) / 2, (W.minZ + W.maxZ) / 2
	wall(W.minX, midZ, 4, W.maxZ - W.minZ + 4)
	wall(W.maxX, midZ, 4, W.maxZ - W.minZ + 4)
	wall(midX, W.minZ, W.maxX - W.minX + 4, 4)
	wall(midX, W.maxZ, W.maxX - W.minX + 4, 4)
end

-- Scenery -------------------------------------------------------------------------

type Claim = { x: number, z: number, r: number }

local function scatter(parent: Instance, L: Layout, rng: Random, claims: { Claim })
	local F, M, W = L.floor, L.moat, L.world
	local function free(x: number, z: number, radius: number): boolean
		for _, r in L.keepOut do
			if touches(r, x, z, radius) then
				return false
			end
		end
		for _, c in claims do
			if (x - c.x) ^ 2 + (z - c.z) ^ 2 < (radius + c.r) ^ 2 then
				return false
			end
		end
		return true
	end
	local function slope(x: number, z: number): number
		local a, b = groundY(x + 3, z), groundY(x - 3, z)
		local c, d = groundY(x, z + 3), groundY(x, z - 3)
		return math.max(a, b, c, d) - math.min(a, b, c, d)
	end
	-- Rejection sampling: `spot` proposes (x, z) or nil, `make` builds there.
	local function place(count: number, radius: number, spot: () -> Vector3?, make: (Vector3) -> ())
		local placed, tries = 0, 0
		while placed < count and tries < count * 60 do
			tries += 1
			local p = spot()
			if p and free(p.X, p.Z, radius) then
				make(p)
				table.insert(claims, { x = p.X, z = p.Z, r = radius })
				placed += 1
			end
		end
	end
	local function onLawn(): Vector3?
		local x, z = rng:NextNumber(F.minX + 10, F.maxX - 10), rng:NextNumber(F.minZ + 10, F.maxZ - 10)
		return Vector3.new(x, groundY(x, z), z)
	end
	local beyond = grow(M, 6)
	local function onHills(): Vector3?
		local x, z = rng:NextNumber(W.minX + 30, W.maxX - 30), rng:NextNumber(W.minZ + 30, W.maxZ - 30)
		if touches(beyond, x, z, 0) or slope(x, z) > 4 then
			return nil
		end
		return Vector3.new(x, groundY(x, z) - 1, z)
	end

	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	place(56, 4.5, onLawn, function(p)
		local roll = rng:NextNumber()
		local kind = if roll < 0.62 then "round" elseif roll < 0.85 then "poplar" else "pine"
		tree(folder, p, rng, kind, rng:NextNumber(0.9, 1.3))
	end)
	place(34, 6, onHills, function(p)
		local roll = rng:NextNumber()
		local kind = if roll < 0.55 then "pine" elseif roll < 0.85 then "round" else "poplar"
		tree(folder, p, rng, kind, rng:NextNumber(1.1, 1.6))
	end)
	place(12, 4, onHills, function(p)
		rock(folder, p, rng, rng:NextNumber(4, 8))
	end)
	place(18, 3, onLawn, function(p)
		rock(folder, p, rng, rng:NextNumber(2.5, 5))
	end)
	place(30, 2.5, onLawn, function(p)
		bush(folder, p, rng)
	end)
	place(18, 1.8, onLawn, function(p)
		flowerPatch(folder, p, rng)
	end)
	folder.Parent = parent
end

-- Init ----------------------------------------------------------------------------

function WorldBuilder.init()
	local L = computeLayout()
	local rng = Random.new(SEED)
	buildTerrain(L, rng)

	local world = Instance.new("Folder")
	world.Name = "World"
	buildPlaza(world, L)
	buildMine(world, L)
	buildDock(world, L)
	buildBoundary(world, L)

	-- Street lamps on the plot side of every road, flanking the spine and in
	-- the gaps between columns (clear of the spur roads to each gate).
	local claims: { Claim } = {}
	local lamps = Instance.new("Folder")
	lamps.Name = "Lamps"
	for _, z in L.avenues do
		for i = 1, G.PlotColumns - 1 do
			local gapX = (i - G.PlotColumns / 2) * G.PlotSpacing
			local xs: { number } = if gapX == L.spineX then { gapX - 12, gapX + 12 } else { gapX }
			for _, x in xs do
				lamp(lamps, Vector3.new(x, Y0, z - 7))
				table.insert(claims, { x = x, z = z - 7, r = 2 })
			end
		end
	end
	lamps.Parent = world

	-- A supply depot at the west end of each road.
	local depots = Instance.new("Folder")
	depots.Name = "Depots"
	for _, z in L.avenues do
		local x = L.roadMinX - 6
		crate(depots, CFrame.new(x, Y0 + 1.6, z - 2) * CFrame.Angles(0, 0.2, 0), 3.2)
		crate(depots, CFrame.new(x + 0.3, Y0 + 4.4, z - 2.2) * CFrame.Angles(0, -0.25, 0), 2.4)
		barrel(depots, Vector3.new(x + 0.5, Y0, z + 2.2))
		table.insert(claims, { x = x, z = z, r = 5 })
	end
	depots.Parent = world
	table.insert(claims, { x = L.spineX - 60, z = L.floor.maxZ, r = 8 }) -- dock

	scatter(world, L, rng, claims)
	world.Parent = Workspace
end

return WorldBuilder
