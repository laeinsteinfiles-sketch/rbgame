--!strict
-- Explorer: ReplicatedStorage/Shared/Models/Hub (ModuleScript)
-- The central hub every island faces: a stone plaza on a floating rock, the
-- Core Monument with four live race boards and a glowing core orb, the
-- results podium and the egg shrine.

local GameConfig = require(script.Parent.Parent.Parent.Config.GameConfig)
local Palette = require(script.Parent.Parent.Parent.Config.Palette)
local UITheme = require(script.Parent.Parent.Parent.Config.UITheme)
local EggModels = require(script.Parent.EggModels)
local Kit = require(script.Parent.ModelKit)
local Props = require(script.Parent.Props)

local Hub = {}

export type Board = { timer: TextLabel, rows: { TextLabel } }
export type Built = {
	model: Model,
	podium: { CFrame },
	crowd: { CFrame },
	boards: { Board },
	shrines: { [string]: BasePart },
	spawn: CFrame,
}

local W = GameConfig.World
local TOP = W.HubTop
local ROWS = 5

local function plaza(m: Model)
	local R = W.HubRadius
	Props.slab(m, R, 12, 0, 0, TOP, Palette.stone, { material = Enum.Material.Cobblestone, collide = true })
	Props.slab(m, R + 0.6, 12.2, 0, TOP - 0.6, TOP - 0.2, Palette.stoneTrim, { material = Enum.Material.Sandstone })
	Props.slab(m, 16, 5, 0, TOP, TOP + 1, Palette.stoneTrim, { material = Enum.Material.Sandstone, collide = true })
	Props.slab(m, R - 3, 10, 0, -7, 0, Palette.rock, { material = Enum.Material.Rock })
	Props.slab(m, R - 10, 8, 0, -16, -7, Palette.rockDark, { material = Enum.Material.Slate })
	Props.slab(m, R - 18, 5, 0, -26, -16, Kit.shade(Palette.rockDark, -0.15), { material = Enum.Material.Basalt })
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local radius = 8 + Kit.jitter(i, 31) * 10
		Props.spike(m, Vector3.new(math.cos(a) * radius, -18 - Kit.jitter(i, 32) * 6, math.sin(a) * radius), 4 + Kit.jitter(i, 33) * 2, 12 + Kit.jitter(i, 34) * 14, Palette.rockDark, Enum.Material.Slate)
	end
	-- Planters on the diagonals keep the plaza from reading as an empty slab.
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + math.pi / 4
		local at = CFrame.new(math.cos(a) * 27, TOP, math.sin(a) * 27) * CFrame.Angles(0, -a, 0)
		Kit.block(m, Vector3.new(7, 1.6, 7), at * CFrame.new(0, 0.8, 0), Palette.stoneTrim, { material = Enum.Material.Sandstone, collide = true })
		Kit.block(m, Vector3.new(6.2, 0.4, 6.2), at * CFrame.new(0, 1.65, 0), Palette.grass, { material = Enum.Material.Grass })
		if k % 2 == 0 then
			Props.pine(m, at * CFrame.new(0, 1.8, 0), 0.9)
		else
			Props.roundTree(m, at * CFrame.new(0, 1.8, 0), 0.85)
		end
	end
	-- Banner poles flank the podium: the hub's only colour, in the two accents.
	for i, x in { -12, 12 } do
		local at = CFrame.new(x, TOP, 19)
		Kit.cylY(m, 11, 0.5, at * CFrame.new(0, 5.5, 0), Palette.metalDark, { material = Enum.Material.Metal, collide = true })
		Kit.ball(m, 0.9, at * CFrame.new(0, 11.2, 0), Palette.gold, { material = Enum.Material.Metal })
		local c = if i == 1 then Palette.teal else Palette.amber
		Kit.block(m, Vector3.new(0.15, 6, 2.6), at * CFrame.new(0, 7.2, -1.5), c, { material = Enum.Material.Fabric })
		Kit.ridge(m, 0.15, 1, 2.6, at * CFrame.new(0, 4.2, -1.5) * CFrame.Angles(math.pi, 0, 0), c, { material = Enum.Material.Fabric })
	end
end

local function raceBoard(m: Model, at: CFrame): Board
	local board = Kit.block(m, Vector3.new(13, 8.4, 0.6), at, Palette.ink, { material = Enum.Material.SmoothPlastic })
	Kit.block(m, Vector3.new(13.6, 0.5, 0.9), at * CFrame.new(0, 4.45, 0), Palette.amber)
	Kit.block(m, Vector3.new(13.6, 0.5, 0.9), at * CFrame.new(0, -4.45, 0), Palette.amberDark)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = board
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromHex("23272E")
	root.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 24)
	padding.PaddingRight = UDim.new(0, 24)
	padding.PaddingTop = UDim.new(0, 14)
	padding.Parent = root
	local function line(text: string, y: number, h: number, color: string, align: Enum.TextXAlignment): TextLabel
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(0, y)
		label.Size = UDim2.new(1, 0, 0, h)
		label.FontFace = UITheme.Font.Display
		label.TextScaled = true
		label.TextXAlignment = align
		label.Text = text
		label.TextColor3 = Color3.fromHex(color)
		label.Parent = root
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromHex(Palette.ink)
		stroke.Thickness = 3
		stroke.Parent = label
		return label
	end
	line("THE RACE", 0, 62, Palette.amber, Enum.TextXAlignment.Left)
	local timer = line("", 0, 62, Palette.cream, Enum.TextXAlignment.Right)
	local rows = {}
	for i = 1, ROWS do
		rows[i] = line("", 74 + (i - 1) * 54, 46, if i == 1 then Palette.amber else Palette.cream, Enum.TextXAlignment.Left)
	end
	return { timer = timer, rows = rows }
end

local function monument(m: Model): { Board }
	local base = TOP + 1
	Kit.block(m, Vector3.new(13, 5, 13), CFrame.new(0, base + 2.5, 0) * CFrame.Angles(0, math.pi / 4, 0), Palette.stoneDark, {
		material = Enum.Material.Slate,
		collide = true,
	})
	Kit.block(m, Vector3.new(14, 0.8, 14), CFrame.new(0, base + 5.2, 0) * CFrame.Angles(0, math.pi / 4, 0), Palette.stoneTrim, {
		material = Enum.Material.Sandstone,
	})
	local columnHeight = 34
	local columnBase = base + 5.6
	Kit.block(m, Vector3.new(6.5, columnHeight, 6.5), CFrame.new(0, columnBase + columnHeight / 2, 0) * CFrame.Angles(0, math.pi / 4, 0), Palette.stone, {
		material = Enum.Material.Slate,
		collide = true,
	})
	for _, y in { 8, 16, 24, 32 } do
		Kit.block(m, Vector3.new(7.3, 0.7, 7.3), CFrame.new(0, columnBase + y, 0) * CFrame.Angles(0, math.pi / 4, 0), Palette.stoneTrim, {
			material = Enum.Material.Sandstone,
		})
	end
	local top = columnBase + columnHeight
	local orbY = top + 7
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + math.pi / 4
		Kit.beam(m, Vector3.new(math.cos(a) * 3.2, top, math.sin(a) * 3.2), Vector3.new(math.cos(a) * 3.6, orbY + 2.5, math.sin(a) * 3.6), 0.9, Palette.metalDark, {
			material = Enum.Material.Metal,
		})
	end
	local orb = Kit.ball(m, 6, CFrame.new(0, orbY, 0), Palette.amber, { material = Enum.Material.Neon, name = "CoreOrb", shadow = false })
	Kit.ball(m, 7.4, CFrame.new(0, orbY, 0), Palette.amber, { material = Enum.Material.Glass, transparency = 0.65, shadow = false })
	Kit.light(orb, Palette.amber, 3, 60)
	for _, p in Kit.ring(m, 5.4, 18, 0.5, 0.5, CFrame.new(0, orbY, 0) * CFrame.Angles(0.35, 0, 0), Palette.metal, { material = Enum.Material.Metal, shadow = false }) do
		p:SetAttribute("OrbRing", 1)
	end
	for _, p in Kit.ring(m, 6.4, 22, 0.4, 0.4, CFrame.new(0, orbY, 0) * CFrame.Angles(-0.5, 0, 0.3), Palette.amberDark, { material = Enum.Material.Metal, shadow = false }) do
		p:SetAttribute("OrbRing", -1)
	end
	-- Four separate screens on brackets (not a closed box) so the column reads.
	local boards = {}
	for k = 0, 3 do
		local yaw = k * math.pi / 2
		local at = CFrame.Angles(0, yaw, 0) * CFrame.new(0, columnBase + 21, -8.5)
		Kit.beam(m, (at * CFrame.new(0, 0, 0.4)).Position, (CFrame.Angles(0, yaw, 0) * CFrame.new(0, columnBase + 21, -2.6)).Position, 0.7, Palette.metalDark, {
			material = Enum.Material.Metal,
		})
		table.insert(boards, raceBoard(m, at))
	end
	return boards
end

local function podium(m: Model): { CFrame }
	local spots = {}
	local steps = { { 0, 4, Palette.gold, "1" }, { -6.4, 3, Palette.silver, "2" }, { 6.4, 2, Palette.bronze, "3" } }
	for i, s in steps do
		local x, h, c, label = s[1], s[2], s[3], s[4]
		local at = CFrame.new(x, TOP + 1, 22)
		local block = Kit.block(m, Vector3.new(6, h, 5.5), at * CFrame.new(0, h / 2, 0), c, { material = Enum.Material.SmoothPlastic, collide = true })
		Kit.block(m, Vector3.new(6.4, 0.4, 5.9), at * CFrame.new(0, h + 0.2, 0), Kit.shade(c, 0.25), { collide = true })
		local gui = Props.signText(block, { { text = label, color = Palette.cream, weight = 1 } }, 30)
		gui[1].TextColor3 = Color3.fromHex(Palette.cream)
		spots[i] = CFrame.new(at.Position + Vector3.new(0, h + 3.4, 0), Vector3.new(0, TOP + 4, 0))
	end
	return spots
end

local function crowd(): { CFrame }
	local spots = {}
	for i = 0, 10 do
		local a = math.rad(-70 + i * 14)
		local p = Vector3.new(math.sin(a) * 13, TOP + 4, 22 - math.cos(a) * 13)
		spots[i + 1] = CFrame.lookAt(p, Vector3.new(0, TOP + 4, 22))
	end
	return spots
end

local function shrine(m: Model): { [string]: BasePart }
	local hosts = {}
	local spots = { { -15, -17 }, { 0, -22 }, { 15, -17 } }
	for i, egg in GameConfig.Eggs do
		local s = spots[i]
		local at = CFrame.lookAt(Vector3.new(s[1], TOP + 1, s[2]), Vector3.new(0, TOP + 1, 0))
		local stone: Kit.Opts = { material = Enum.Material.Sandstone, collide = true }
		Kit.cylY(m, 1, 4.6, at * CFrame.new(0, 0.5, 0), Palette.stoneTrim, stone)
		Kit.cylY(m, 3.4, 3.2, at * CFrame.new(0, 2.7, 0), Palette.stone, { material = Enum.Material.Slate, collide = true })
		local top = Kit.cylY(m, 0.6, 4, at * CFrame.new(0, 4.7, 0), Palette.stoneTrim, stone)
		local eggModel = EggModels.build(egg.id, true)
		eggModel.Name = `ShrineEgg_{egg.id}`
		eggModel:SetAttribute("EggId", egg.id)
		eggModel:PivotTo(at * CFrame.new(0, 5, 0) * eggModel:GetPivot().Rotation)
		eggModel.Parent = m
		local plate = Kit.block(m, Vector3.new(4.4, 1.6, 0.3), at * CFrame.new(0, 2.6, -1.75), Palette.ink)
		Props.signText(plate, {
			{ text = string.upper(egg.name), color = Palette.cream, weight = 0.55 },
			{ text = `{egg.cost} GEMS`, color = Palette.teal, weight = 0.45 },
		})
		top.Name = `Shrine_{egg.id}`
		top:SetAttribute("EggId", egg.id)
		hosts[egg.id] = top
	end
	return hosts
end

local function braziers(m: Model)
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + math.pi / 4
		local at = CFrame.new(math.cos(a) * 13, TOP + 1, math.sin(a) * 13)
		Kit.cylY(m, 2.6, 1, at * CFrame.new(0, 1.3, 0), Palette.stoneDark, { material = Enum.Material.Slate, collide = true })
		local bowl = Kit.cylY(m, 0.8, 2.6, at * CFrame.new(0, 2.9, 0), Palette.metalDark, { material = Enum.Material.Metal })
		local fire = Instance.new("Fire")
		fire.Color = Color3.fromHex("FFB347")
		fire.SecondaryColor = Color3.fromHex("C2410C")
		fire.Heat = 8
		fire.Size = 4
		fire.Parent = bowl
		Kit.light(bowl, Palette.lantern, 1.6, 18, true)
	end
end

function Hub.build(): Built
	local m = Kit.model("Hub")
	plaza(m)
	local boards = monument(m)
	local spots = podium(m)
	local shrines = shrine(m)
	braziers(m)
	m.WorldPivot = CFrame.new()
	return {
		model = m,
		podium = spots,
		crowd = crowd(),
		boards = boards,
		shrines = shrines,
		spawn = CFrame.new(0, TOP + 4, 12),
	}
end

return Hub
