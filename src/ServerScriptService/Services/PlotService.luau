--!strict
-- Explorer: ServerScriptService/Services/PlotService (ModuleScript)
-- Twelve floating islands. Each island's front cliff IS its owner's mine:
-- the mine strip runs along the front edge and the side camera looks at it
-- from the open air in front. The server owns only the surface; every mine
-- cell is drawn client-side by MineRenderer.
--
-- Other players see a solid plug where the mine is; the owner's client hides
-- every part tagged HideForOwner so it can dig and see inside.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Hash = require(ReplicatedStorage.Shared.Hash)
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)

local PlotService = {}

export type Plot = {
	index: number,
	origin: Vector3,
	model: Model,
	sellPad: BasePart,
	shopPad: BasePart,
	spawn: SpawnLocation,
	nameLabels: { TextLabel },
	owner: Player?,
}

local plots: { Plot } = {}
local plotByPlayer: { [Player]: Plot } = {}

local G = GameConfig.Geometry
local CELL = G.Cell
local MINE_HALF = Grid.halfWidth()
local HALF_WIDTH = MINE_HALF + G.BorderColumns * CELL
local THICK = G.IslandRows * CELL
local FRONT = CELL / 2
local topsoil = GameConfig.Layers[1]

PlotService.HALF_WIDTH = HALF_WIDTH

local function solid(parent: Instance, name: string, size: Vector3, cf: CFrame, color: string, material: string): BasePart
	local p = ModelKit.part(parent, name, size, cf, color, material)
	p.CanCollide = true
	p.CanQuery = true
	return p
end

local function invisibleWall(parent: Instance, size: Vector3, cf: CFrame)
	local p = ModelKit.part(parent, "Rail", size, cf, "FFFFFF", "SmoothPlastic")
	p.Transparency = 1
	p.CanCollide = true
	p.CastShadow = false
end

local function place(m: Model, parent: Instance, cf: CFrame)
	m:PivotTo(cf)
	m.Parent = parent
end

--- Grass-topped dirt slab spanning [x0,x1] x [z0,z1], top at SurfaceY.
local function slab(parent: Instance, name: string, x0: number, x1: number, z0: number, z1: number, origin: Vector3)
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	solid(parent, name, Vector3.new(w, THICK - 1, d), CFrame.new(origin + Vector3.new(cx, G.SurfaceY - 1 - (THICK - 1) / 2, cz)), topsoil.color, topsoil.material)
	solid(parent, name .. "Grass", Vector3.new(w, 1, d), CFrame.new(origin + Vector3.new(cx, G.SurfaceY - 0.5, cz)), "5DBB4C", "Grass")
end

local function decorate(m: Model, origin: Vector3, index: number)
	local back = -FRONT - G.IslandBack
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = m

	-- A loose tree line along the back and the far corners.
	for i = 0, 9 do
		local seed = index * 100 + i
		local x = -HALF_WIDTH + 8 + i * (HALF_WIDTH * 2 - 16) / 9 + (Hash.unit(seed, 1, 1) - 0.5) * 6
		local z = back + 6 + Hash.unit(seed, 2, 1) * 8
		local tree = if i % 3 == 1 then ModelKit.pine(seed) else ModelKit.tree(seed)
		place(tree, props, CFrame.new(origin + Vector3.new(x, G.SurfaceY, z)) * CFrame.Angles(0, Hash.unit(seed, 3, 1) * math.pi * 2, 0))
	end
	for i = 0, 5 do
		local seed = index * 100 + 40 + i
		local side = if i % 2 == 0 then -1 else 1
		local x = side * (HALF_WIDTH - 10 - Hash.unit(seed, 1, 2) * 18)
		local z = -FRONT - 10 - Hash.unit(seed, 2, 2) * (G.IslandBack - 24)
		place(ModelKit.rock(seed, 2 + Hash.unit(seed, 3, 2) * 2.5), props, CFrame.new(origin + Vector3.new(x, G.SurfaceY, z)))
	end
	for i = 0, 7 do
		local seed = index * 100 + 60 + i
		local x = (Hash.unit(seed, 1, 3) - 0.5) * (HALF_WIDTH * 2 - 20)
		local z = -FRONT - 8 - Hash.unit(seed, 2, 3) * (G.IslandBack - 16)
		-- Keep the walkway between spawn and the mine clear.
		if math.abs(x) > 12 then
			place(ModelKit.flowers(seed), props, CFrame.new(origin + Vector3.new(x, G.SurfaceY, z)))
		end
	end
	-- Lanterns frame the mine mouth and light the walkway at dusk.
	for _, x in { -MINE_HALF - 3, MINE_HALF + 3, -14, 14 } do
		local z = if math.abs(x) > 20 then -FRONT - 2 else -FRONT - 12
		place(ModelKit.lantern(), props, CFrame.new(origin + Vector3.new(x, G.SurfaceY, z)) * CFrame.Angles(0, math.pi, 0))
	end
	-- Fences along the back edge and the sides.
	place(ModelKit.fence(HALF_WIDTH * 2 - 4), props, CFrame.new(origin + Vector3.new(0, G.SurfaceY, back + 1.5)))
	for _, side in { -1, 1 } do
		place(
			ModelKit.fence(G.IslandBack - 6),
			props,
			CFrame.new(origin + Vector3.new(side * (HALF_WIDTH - 1.5), G.SurfaceY, back + G.IslandBack / 2)) * CFrame.Angles(0, math.pi / 2, 0)
		)
	end
end

local function buildUnderside(m: Model, origin: Vector3, index: number)
	-- Hanging rock under the island so it reads as floating from afar.
	for i = 0, 7 do
		local seed = index * 31 + i
		local w = 18 + Hash.unit(seed, 1, 4) * 26
		local h = 10 + Hash.unit(seed, 2, 4) * 18
		local x = (Hash.unit(seed, 3, 4) - 0.5) * (HALF_WIDTH * 2 - w)
		local z = -FRONT - 10 - Hash.unit(seed, 4, 4) * (G.IslandBack - 20)
		local rock = ModelKit.part(
			m,
			"Underside",
			Vector3.new(w, h, w * 0.8),
			CFrame.new(origin + Vector3.new(x, G.SurfaceY - THICK - h / 2 + 3, z)) * CFrame.Angles(0, Hash.unit(seed, 5, 4) * 3, math.rad(180)),
			if i % 2 == 0 then "6E4A30" else "5A3C27",
			"Ground",
			"wedge"
		)
		rock.CastShadow = false
	end
end

local function buildPlot(index: number): Plot
	local ox, oz = Grid.plotOrigin(index)
	local origin = Vector3.new(ox, 0, oz)
	local m = Instance.new("Model")
	m.Name = `Plot{index}`
	m:SetAttribute("PlotIndex", index)
	m:SetAttribute("OwnerUserId", 0)

	local back = -FRONT - G.IslandBack
	slab(m, "Back", -HALF_WIDTH, HALF_WIDTH, back, -FRONT, origin)
	slab(m, "Left", -HALF_WIDTH, -MINE_HALF, -FRONT, FRONT, origin)
	slab(m, "Right", MINE_HALF, HALF_WIDTH, -FRONT, FRONT, origin)
	buildUnderside(m, origin, index)

	-- The plug fills the top of the mine for everyone except the owner.
	local plug = solid(m, "MinePlug", Vector3.new(MINE_HALF * 2, THICK - 1, CELL), CFrame.new(origin + Vector3.new(0, G.SurfaceY - 1 - (THICK - 1) / 2, 0)), topsoil.color, topsoil.material)
	plug:SetAttribute("HideForOwner", true)
	local plugGrass = solid(m, "MinePlugGrass", Vector3.new(MINE_HALF * 2, 1, CELL), CFrame.new(origin + Vector3.new(0, G.SurfaceY - 0.5, 0)), "5DBB4C", "Grass")
	plugGrass:SetAttribute("HideForOwner", true)

	-- Rails: the front edge (so nobody walks off the cliff at the surface),
	-- the back and the sides. Underground the client's front wall takes over.
	invisibleWall(m, Vector3.new(HALF_WIDTH * 2, 14, 1), CFrame.new(origin + Vector3.new(0, G.SurfaceY + 7, FRONT + 0.5)))
	invisibleWall(m, Vector3.new(HALF_WIDTH * 2, 14, 1), CFrame.new(origin + Vector3.new(0, G.SurfaceY + 7, back - 0.5)))
	for _, side in { -1, 1 } do
		invisibleWall(m, Vector3.new(1, 14, G.IslandBack + CELL), CFrame.new(origin + Vector3.new(side * (HALF_WIDTH + 0.5), G.SurfaceY + 7, back / 2 + FRONT / 2)))
	end

	-- Sell pad + stall (right), upgrade pad + stall (left), both facing the walkway.
	local function pad(name: string, def: { x: number, z: number, radius: number }, color: string, rim: string): BasePart
		local cf = CFrame.new(origin + Vector3.new(def.x, G.SurfaceY + 0.05, def.z)) * CFrame.Angles(0, 0, math.pi / 2)
		local disc = ModelKit.part(m, name, Vector3.new(0.6, def.radius * 2, def.radius * 2), cf, color, "SmoothPlastic", "cylinder")
		disc.CanTouch = true -- the sell pad sells on touch
		disc.CanQuery = true
		local ring = ModelKit.part(m, name .. "Rim", Vector3.new(0.5, def.radius * 2 + 1.2, def.radius * 2 + 1.2), cf * CFrame.new(-0.06, 0, 0), rim, "Neon", "cylinder")
		ring.CastShadow = false
		return disc
	end
	local sell = G.SellPad
	local sellPad = pad("SellPad", sell, "FFC83D", "FFE9A8")
	place(ModelKit.stall("SELL ORE", "FFC83D", "FFFFFF", "E59A1C"), m, CFrame.new(origin + Vector3.new(sell.x, G.SurfaceY, sell.z - sell.radius - 3)))
	local shop = G.ShopPad
	local shopPad = pad("ShopPad", shop, "3FD6C4", "B6FFF6")
	place(ModelKit.stall("UPGRADES", "3FD6C4", "FFFFFF", "1F9E8F"), m, CFrame.new(origin + Vector3.new(shop.x, G.SurfaceY, shop.z - shop.radius - 3)))

	local headframe, nameLabels = ModelKit.headframe(MINE_HALF * 2 + 4, 16)
	place(headframe, m, CFrame.new(origin + Vector3.new(0, G.SurfaceY, -FRONT - 1)))

	decorate(m, origin, index)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(origin + Vector3.new(G.SpawnOffset.x, G.SurfaceY - 0.5, G.SpawnOffset.z)) * CFrame.Angles(0, math.pi, 0)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = true
	spawn.Parent = m

	m.Parent = Workspace
	return {
		index = index,
		origin = origin,
		model = m,
		sellPad = sellPad,
		shopPad = shopPad,
		spawn = spawn,
		nameLabels = nameLabels,
		owner = nil,
	}
end

function PlotService.getPlot(player: Player): Plot?
	return plotByPlayer[player]
end

function PlotService.getAll(): { Plot }
	return plots
end

--- Where a character stands inside cell (col, row); row 0 is the surface.
function PlotService.cellCFrame(player: Player, col: number, row: number): CFrame?
	local plot = plotByPlayer[player]
	if not plot then
		return nil
	end
	local x, y = Grid.cellOffset(col, math.max(row, 0))
	local floor = y - CELL / 2
	return CFrame.new(plot.origin + Vector3.new(x, floor + 3.2, 0)) * CFrame.Angles(0, math.pi, 0)
end

--- Next to the sell stall: where the elevator lets you out.
function PlotService.surfaceCFrame(player: Player): CFrame?
	local plot = plotByPlayer[player]
	if not plot then
		return nil
	end
	local position = plot.origin + Vector3.new(G.SellPad.x - G.SellPad.radius - 3, G.SurfaceY + 3.2, G.SellPad.z + 4)
	return CFrame.lookAt(position, plot.origin + Vector3.new(G.SellPad.x, G.SurfaceY + 3.2, G.SellPad.z))
end

function PlotService.isNearSellPad(player: Player): boolean
	local plot = plotByPlayer[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not plot or not root or not root:IsA("BasePart") then
		return false
	end
	local pad = plot.sellPad.Position
	local flat = Vector3.new(root.Position.X - pad.X, 0, root.Position.Z - pad.Z)
	return flat.Magnitude <= G.SellPad.radius + 3 and math.abs(root.Position.Y - pad.Y) < 8
end

local function assign(player: Player)
	for _, plot in plots do
		if plot.owner == nil then
			plot.owner = player
			plotByPlayer[player] = plot
			for _, text in plot.nameLabels do
				text.Text = `{string.upper(player.DisplayName)}'S MINE`
			end
			player:SetAttribute("PlotIndex", plot.index)
			plot.model:SetAttribute("OwnerUserId", player.UserId)
			player.RespawnLocation = plot.spawn
			return
		end
	end
	player:Kick("Server is full.")
end

local function release(player: Player)
	local plot = plotByPlayer[player]
	if plot then
		plot.owner = nil
		for _, text in plot.nameLabels do
			text.Text = "EMPTY MINE"
		end
		plot.model:SetAttribute("OwnerUserId", 0)
		plotByPlayer[player] = nil
	end
end

function PlotService.teleportHome(player: Player)
	local character = player.Character
	local plot = plotByPlayer[player]
	if character and plot then
		character:PivotTo(plot.spawn.CFrame * CFrame.new(0, 3.7, 0))
	end
end

function PlotService.init()
	for i = 1, G.MaxPlayers do
		local plot = buildPlot(i)
		plots[i] = plot
		for _, text in plot.nameLabels do
			text.Text = "EMPTY MINE"
		end
	end

	local function watch(player: Player)
		assign(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 5)
			-- RespawnLocation already spawns on the plot; this covers the first
			-- spawn racing the plot assignment.
			task.defer(PlotService.teleportHome, player)
		end)
		if player.Character then
			task.defer(PlotService.teleportHome, player)
		end
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return PlotService
