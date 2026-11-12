--!strict
-- Explorer: ReplicatedStorage/Shared/Models/Props (ModuleScript)
-- Reusable world props and the shared building pieces for islands and the
-- hub: chamfered slabs, signs, stalls, trees, rocks, lanterns.

local Palette = require(script.Parent.Parent.Parent.Config.Palette)
local UITheme = require(script.Parent.Parent.Parent.Config.UITheme)
local Kit = require(script.Parent.ModelKit)

local Props = {}

type SlabOpts = { material: Enum.Material?, collide: boolean? }

local function box(m: Instance, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, c: Kit.ColorLike, o: SlabOpts)
	Kit.block(m, Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), c, {
		material = o.material,
		collide = o.collide,
	})
end

local function corners(m: Instance, inner: number, chamfer: number, y0: number, y1: number, c: Kit.ColorLike, o: SlabOpts, origin: CFrame)
	local side = chamfer * math.sqrt(2)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.block(m, Vector3.new(side, y1 - y0, side), origin * CFrame.new(sx * inner, (y0 + y1) / 2, sz * inner) * CFrame.Angles(0, math.pi / 4, 0), c, {
				material = o.material,
				collide = o.collide,
			})
		end
	end
end

--- Octagon slab (square with chamfered corners) with an optional square hole.
--- Built in the model's local space; callers pivot the finished model.
function Props.slab(m: Instance, half: number, chamfer: number, hole: number, y0: number, y1: number, c: Kit.ColorLike, o: SlabOpts)
	local inner = half - chamfer
	if hole > 0 then
		box(m, -half, half, y0, y1, -inner, -hole, c, o)
		box(m, -half, half, y0, y1, hole, inner, c, o)
		box(m, -half, -hole, y0, y1, -hole, hole, c, o)
		box(m, hole, half, y0, y1, -hole, hole, c, o)
	else
		box(m, -half, half, y0, y1, -inner, inner, c, o)
	end
	box(m, -inner, inner, y0, y1, -half, -inner, c, o)
	box(m, -inner, inner, y0, y1, inner, half, c, o)
	corners(m, inner, chamfer, y0, y1, c, o, CFrame.new())
end

--- Downward rock spike: diamond prism with a ridge tip, hanging from `top`.
function Props.spike(m: Instance, top: Vector3, width: number, length: number, c: Kit.ColorLike, material: Enum.Material?)
	local body = length * 0.65
	local cf = CFrame.new(top) * CFrame.Angles(0, math.pi / 4, 0)
	Kit.block(m, Vector3.new(width, body, width), cf * CFrame.new(0, -body / 2, 0), c, { material = material })
	Kit.ridge(m, width, length - body, width, cf * CFrame.new(0, -body, 0) * CFrame.Angles(0, 0, math.pi), c, { material = material })
end

function Props.rocks(m: Instance, at: CFrame, scale: number, seed: number)
	for i = 1, 3 do
		local s = scale * (0.6 + Kit.jitter(seed, i) * 0.7)
		local offset = Vector3.new((Kit.jitter(seed, i + 3) - 0.5) * 2.4 * scale, s * 0.3, (Kit.jitter(seed, i + 6) - 0.5) * 2.4 * scale)
		Kit.block(m, Vector3.new(s * 1.3, s, s * 1.1), at * CFrame.new(offset) * CFrame.Angles(Kit.jitter(seed, i + 9) * 0.5, Kit.jitter(seed, i + 12) * 3, Kit.jitter(seed, i + 15) * 0.4), Kit.shade(Palette.rock, (Kit.jitter(seed, i + 18) - 0.5) * 0.2), {
			material = Enum.Material.Rock,
			collide = i == 1,
		})
	end
end

function Props.pine(m: Instance, at: CFrame, scale: number)
	Kit.cylY(m, 3 * scale, 0.9 * scale, at * CFrame.new(0, 1.5 * scale, 0), Palette.woodDark, { material = Enum.Material.Wood, collide = true })
	local tiers = { { 6, 2.4, 3.4 }, { 4.6, 2.2, 5.2 }, { 3.2, 2, 6.9 }, { 1.8, 1.6, 8.3 } }
	for i, t in tiers do
		local c = if i % 2 == 0 then Palette.foliage else Palette.foliageDark
		Kit.block(m, Vector3.new(t[1], t[2], t[1]) * scale, at * CFrame.new(0, t[3] * scale, 0) * CFrame.Angles(0, math.pi / 4 * i, 0), c, {
			material = Enum.Material.Grass,
		})
	end
end

function Props.roundTree(m: Instance, at: CFrame, scale: number)
	Kit.cylY(m, 3.4 * scale, 1 * scale, at * CFrame.new(0, 1.7 * scale, 0) * CFrame.Angles(0, 0, 0.06), Palette.woodDark, {
		material = Enum.Material.Wood,
		collide = true,
	})
	local blobs = { { 4.4, 0, 4.6, 0 }, { 3.4, 1.4, 5.4, 0.6 }, { 3.2, -1.3, 5.2, -0.4 }, { 2.8, 0.2, 6.6, -0.2 } }
	for i, b in blobs do
		Kit.ball(m, b[1] * scale, at * CFrame.new(b[2] * scale, b[3] * scale, b[4] * scale), if i % 2 == 0 then Palette.foliage else Palette.foliageDark, {
			material = Enum.Material.Grass,
		})
	end
end

function Props.barrel(m: Instance, at: CFrame)
	Kit.cylY(m, 1.8, 1.4, at * CFrame.new(0, 0.9, 0), Palette.wood, { material = Enum.Material.WoodPlanks, collide = true })
	for _, y in { 0.35, 1.45 } do
		Kit.cylY(m, 0.14, 1.46, at * CFrame.new(0, y, 0), Palette.metalDark, { material = Enum.Material.Metal })
	end
end

function Props.crate(m: Instance, at: CFrame, size: number)
	Kit.block(m, Vector3.new(size, size, size), at * CFrame.new(0, size / 2, 0), Palette.plank, { material = Enum.Material.WoodPlanks, collide = true })
	for _, sx in { -1, 1 } do
		Kit.block(m, Vector3.new(0.18, size + 0.04, size + 0.04), at * CFrame.new(sx * (size / 2 - 0.09), size / 2, 0), Palette.woodDark)
	end
end

function Props.lantern(m: Instance, at: CFrame): BasePart
	Kit.block(m, Vector3.new(0.7, 0.12, 0.7), at * CFrame.new(0, 0.5, 0), Palette.metalDark)
	Kit.block(m, Vector3.new(0.7, 0.12, 0.7), at * CFrame.new(0, -0.5, 0), Palette.metalDark)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.block(m, Vector3.new(0.08, 1, 0.08), at * CFrame.new(sx * 0.3, 0, sz * 0.3), Palette.metalDark)
		end
	end
	local glow = Kit.block(m, Vector3.new(0.42, 0.7, 0.42), at, Palette.lantern, { material = Enum.Material.Neon, name = "LanternGlow", shadow = false })
	Kit.light(glow, Palette.lantern, 1.4, 16, true)
	return glow
end

function Props.lanternPost(m: Instance, at: CFrame): BasePart
	Kit.block(m, Vector3.new(0.45, 5.2, 0.45), at * CFrame.new(0, 2.6, 0), Palette.woodDark, { material = Enum.Material.Wood, collide = true })
	Kit.block(m, Vector3.new(0.3, 0.3, 1.6), at * CFrame.new(0, 5, -0.6), Palette.woodDark, { material = Enum.Material.Wood })
	return Props.lantern(m, at * CFrame.new(0, 4.2, -1.25))
end

--- A sign board whose front (-Z) carries stacked text lines. Returns labels.
function Props.signText(board: BasePart, lines: { { text: string, color: string, weight: number } }, ppsOverride: number?): { TextLabel }
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppsOverride or 40
	gui.LightInfluence = 0.15
	gui.Parent = board
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = frame
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = frame
	local labels = {}
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = `Line{i}`
		label.LayoutOrder = i
		label.Size = UDim2.fromScale(1, line.weight)
		label.BackgroundTransparency = 1
		label.FontFace = UITheme.Font.Display
		label.TextScaled = true
		label.Text = line.text
		label.TextColor3 = Color3.fromHex(line.color)
		label.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromHex(Palette.ink)
		stroke.Thickness = 3
		stroke.Parent = label
		table.insert(labels, label)
	end
	return labels
end

--- Open market stall shell shared by the trading post and the workshop.
--- Local frame: floor centre at the origin, customers stand on the -Z side.
function Props.stall(m: Instance, at: CFrame, roofA: string, roofB: string)
	local plank = Enum.Material.WoodPlanks
	Kit.block(m, Vector3.new(9, 0.4, 6.6), at * CFrame.new(0, 0.2, 0), Palette.plank, { material = plank, collide = true })
	Kit.block(m, Vector3.new(8.4, 5.8, 0.4), at * CFrame.new(0, 3.3, 2.95), Palette.plank, { material = plank, collide = true })
	for _, x in { -4.1, 4.1 } do
		for _, z in { -3, 2.95 } do
			Kit.block(m, Vector3.new(0.6, 6.7, 0.6), at * CFrame.new(x, 3.35, z), Palette.woodDark, { material = Enum.Material.Wood, collide = true })
		end
	end
	-- Striped awning: alternating slats pitched toward the customer side.
	for i = 0, 7 do
		local x = -3.85 + i * 1.1
		local c = if i % 2 == 0 then roofA else roofB
		Kit.block(m, Vector3.new(1.12, 0.24, 7.6), at * CFrame.new(x, 7, -0.2) * CFrame.Angles(-0.2, 0, 0), c, { material = Enum.Material.Fabric })
		Kit.ridge(m, 0.12, 0.6, 1.1, at * CFrame.new(x, 6.3, -3.95) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi), c, {
			material = Enum.Material.Fabric,
			shadow = false,
		})
	end
end

return Props
