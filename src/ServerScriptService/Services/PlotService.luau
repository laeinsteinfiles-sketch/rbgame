--!strict
-- Explorer: ServerScriptService/Services/PlotService (ModuleScript)
-- Twelve dig sites on the valley lawn, one private shaft each. The server owns
-- only the surface; everything below is rendered client-side by ShaftRenderer.
-- A site is a timber collar and plank deck around the 8x8 opening, a headframe
-- whose pulley cable drops into it, a winch, a market stall at the SellPad and
-- a fenced yard whose gate (on +Z, facing the road) carries the owner's name.
-- WorldBuilder supplies the prop kit, palette and site layout.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local WorldBuilder = require(script.Parent.WorldBuilder)

local PlotService = {}

export type Plot = {
	index: number,
	center: Vector3,
	model: Model,
	sellPad: BasePart,
	cap: BasePart,
	nameLabel: TextLabel,
	owner: Player?,
}

local plots: { Plot } = {}
local plotByPlayer: { [Player]: Plot } = {}

local G = GameConfig.Geometry
local Kit = WorldBuilder.Kit
local Palette = WorldBuilder.Palette
local Site = WorldBuilder.Site

local WOOD = Enum.Material.Wood
local OPEN_PLOT = "Open Plot"

--- A point in a plot: (x, z) from the shaft axis, y above SurfaceY.
local function offset(center: Vector3, x: number, y: number, z: number): Vector3
	return center + Vector3.new(x, G.SurfaceY + y, z)
end

--- Timber collar and plank deck around the opening. Both sit on top of the
--- surface: the client draws the shaft walls right under the collar, so
--- nothing here reaches below SurfaceY.
local function buildDigSite(model: Model, center: Vector3)
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(offset(center, x, y, z))
	end
	local hole = G.BlockSize / 2
	local collar, deck = Site.CollarHalf, Site.DeckHalf
	local band, plank = collar - hole, deck - collar
	for _, s in { -1, 1 } do
		Kit.part(
			model,
			"Collar",
			Vector3.new(collar * 2, 0.6, band),
			at(0, 0.3, s * (hole + band / 2)),
			Palette.WoodDark,
			WOOD
		)
		Kit.part(
			model,
			"Collar",
			Vector3.new(band, 0.6, hole * 2),
			at(s * (hole + band / 2), 0.3, 0),
			Palette.WoodDark,
			WOOD
		)
		-- Gold lip so the opening reads from across the map.
		Kit.decor(
			Kit.part(
				model,
				"CollarTrim",
				Vector3.new(hole * 2 + 0.8, 0.08, 0.4),
				at(0, 0.64, s * (hole + 0.2)),
				Palette.Gold
			)
		)
		Kit.decor(
			Kit.part(model, "CollarTrim", Vector3.new(0.4, 0.08, hole * 2), at(s * (hole + 0.2), 0.64, 0), Palette.Gold)
		)
		local planks = Enum.Material.WoodPlanks
		Kit.part(
			model,
			"Deck",
			Vector3.new(deck * 2, 0.4, plank),
			at(0, 0.2, s * (collar + plank / 2)),
			Palette.WoodLight,
			planks
		)
		Kit.part(
			model,
			"Deck",
			Vector3.new(plank, 0.4, collar * 2),
			at(s * (collar + plank / 2), 0.2, 0),
			Palette.WoodLight,
			planks
		)
	end
end

--- Mine headframe straddling the opening. Legs stand on the deck corners,
--- nothing crosses the opening lower than 10 studs, and the whole frame is
--- walk-through and invisible to the camera's occlusion checks.
local function buildHeadframe(model: Model, center: Vector3)
	local function v(x: number, y: number, z: number): Vector3
		return offset(center, x, y, z)
	end
	local function frame(p: Part)
		Kit.decor(p, true)
	end
	local base, top, topY = 7, 4, 17
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			frame(
				Kit.beam(
					model,
					"HeadframeLeg",
					v(sx * base, 0.4, sz * base),
					v(sx * top, topY, sz * top),
					0.9,
					Palette.Wood,
					WOOD
				)
			)
		end
	end
	local braceY = 10
	local brace = base - (base - top) * (braceY - 0.4) / (topY - 0.4)
	for _, s in { -1, 1 } do
		frame(
			Kit.part(
				model,
				"HeadframeBrace",
				Vector3.new(brace * 2 + 0.8, 0.8, 0.8),
				CFrame.new(v(0, braceY, s * brace)),
				Palette.WoodDark,
				WOOD
			)
		)
		frame(
			Kit.part(
				model,
				"HeadframeTop",
				Vector3.new(top * 2 + 1, 1, 1),
				CFrame.new(v(0, topY, s * top)),
				Palette.WoodDark,
				WOOD
			)
		)
		frame(
			Kit.part(
				model,
				"HeadframeTop",
				Vector3.new(1, 1, top * 2 - 1),
				CFrame.new(v(s * top, topY, 0)),
				Palette.WoodDark,
				WOOD
			)
		)
		frame(
			Kit.part(
				model,
				"SheaveStand",
				Vector3.new(0.8, 2.6, 0.8),
				CFrame.new(v(s * top, topY + 1.8, 0)),
				Palette.WoodDark,
				WOOD
			)
		)
	end

	-- Pulley wheel turning about X, so it faces the roads and the spawn
	-- camera (which sits inside the frame) never looks through its cable.
	local hub = v(0, topY + 2.9, 0)
	frame(Kit.cylinder(model, "Axle", hub, top * 2 + 0.8, 0.6, Palette.Steel, nil, CFrame.identity))
	frame(Kit.cylinder(model, "Wheel", hub, 0.6, 6.4, Palette.SteelDark, nil, CFrame.identity))
	frame(Kit.cylinder(model, "Wheel", hub, 0.75, 5.4, Palette.Red, nil, CFrame.identity))
	for _, angle in { math.pi / 4, -math.pi / 4 } do
		frame(
			Kit.part(
				model,
				"Spoke",
				Vector3.new(0.9, 5.6, 0.6),
				CFrame.new(hub) * CFrame.Angles(angle, 0, 0),
				Palette.Gold
			)
		)
	end
	frame(Kit.cylinder(model, "Hub", hub, 1.1, 1.6, Palette.GoldDeep, nil, CFrame.identity))

	-- The hoist line runs from the winch (north) over the wheel and drops
	-- into the shaft on the gate side, where a bucket hangs above block 1.
	Kit.decor(Kit.beam(model, "Cable", hub + Vector3.new(0, 0, 3.1), v(0, 1.6, 3.1), 0.18, Palette.Steel))
	Kit.decor(Kit.cylinder(model, "Bucket", v(0, 1, 3.1), 1.2, 1.5, Palette.Steel))
	Kit.decor(Kit.beam(model, "HoistLine", hub + Vector3.new(0, 2.26, -2.26), v(0, 3.7, -15), 0.18, Palette.Steel))
end

local function buildWinch(model: Model, center: Vector3)
	local z = -15
	local function at(x: number, y: number, dz: number): CFrame
		return CFrame.new(offset(center, x, y, z + dz))
	end
	Kit.part(model, "WinchBase", Vector3.new(4.6, 0.6, 3.2), at(0, 0.3, 0), Palette.WoodDark, WOOD)
	for _, s in { -1, 1 } do
		Kit.part(model, "WinchFrame", Vector3.new(0.5, 3.2, 2.4), at(s * 1.95, 2.2, 0), Palette.Steel)
	end
	Kit.cylinder(model, "WinchDrum", offset(center, 0, 2.6, z), 3.4, 2.2, Palette.Red, nil, CFrame.identity)
	Kit.decor(Kit.part(model, "WinchCrank", Vector3.new(0.4, 1.8, 0.4), at(2.45, 2.2, -0.5), Palette.Gold))
end

--- Market stall behind the SellPad, facing the deck: glowing pad ring,
--- counter, striped awning and a big gold "SELL" coin.
local function buildStall(model: Model, center: Vector3, pad: BasePart)
	local px = G.SellPadOffset
	local function v(x: number, y: number, z: number): Vector3
		return offset(center, px + x, y, z)
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(v(x, y, z))
	end
	local neon = Enum.Material.Neon
	for _, s in { -1, 1 } do
		Kit.decor(Kit.part(model, "PadGlow", Vector3.new(8, 0.15, 0.5), at(0, 0.475, s * 3.75), Palette.Green, neon))
		Kit.decor(Kit.part(model, "PadGlow", Vector3.new(0.5, 0.15, 7), at(s * 3.75, 0.475, 0), Palette.Green, neon))
	end
	Kit.light(pad, 12, Palette.Gold, 1.4)

	Kit.part(model, "Counter", Vector3.new(2.6, 3, 10), at(6.3, 1.5, 0), Palette.Wood, Enum.Material.WoodPlanks)
	Kit.part(model, "CounterTop", Vector3.new(3.4, 0.5, 10.8), at(6.3, 3.25, 0), Palette.WoodDark, WOOD)
	Kit.decor(Kit.part(model, "CounterStripe", Vector3.new(0.12, 0.7, 10), at(4.94, 2, 0), Palette.Gold))
	for _, s in { -1, 1 } do
		Kit.part(model, "StallPost", Vector3.new(0.7, 8, 0.7), at(5, 4, s * 5.6), Palette.WoodDark, WOOD)
		Kit.part(model, "StallPost", Vector3.new(0.7, 9.3, 0.7), at(9, 4.65, s * 5.6), Palette.WoodDark, WOOD)
	end
	Kit.part(model, "StallBack", Vector3.new(0.5, 5.4, 10.6), at(9.05, 6.2, 0), Palette.WoodLight, WOOD)
	Kit.decor(Kit.ball(model, "Nugget", v(6.2, 3.95, -2.6), 0.9, Palette.GoldDeep, Enum.Material.Metal))
	Kit.decor(
		Kit.part(
			model,
			"Gem",
			Vector3.one * 0.8,
			at(6.4, 3.95, 2.6) * CFrame.Angles(0.6, 0.8, 0),
			Palette.Cyan,
			Enum.Material.Glass
		)
	)

	-- Awning slopes from 7.8 studs over the pad's edge up to 9.6 at the back.
	local slope = math.atan2(1.8, 6)
	for i = 1, 6 do
		local z = -6 + (i - 0.5) * 2
		local stripe = if i % 2 == 1 then Palette.Red else Palette.White
		local trim = if i % 2 == 1 then Palette.White else Palette.Red
		Kit.decor(
			Kit.part(model, "Awning", Vector3.new(6.4, 0.3, 2), at(6.6, 8.7, z) * CFrame.Angles(0, 0, slope), stripe),
			true
		)
		Kit.decor(Kit.part(model, "Valance", Vector3.new(0.15, 0.8, 2), at(3.5, 7.35, z), trim))
	end

	-- Coin sign (cylinder axis along X, so its faces look along the deck).
	Kit.decor(Kit.part(model, "CoinPost", Vector3.new(0.5, 1.8, 0.5), at(7.4, 9.9, 0), Palette.WoodDark, WOOD))
	Kit.decor(Kit.cylinder(model, "Coin", v(7.4, 13.2, 0), 0.7, 6.4, Palette.GoldDeep, nil, CFrame.identity), true)
	local coin = Kit.decor(
		Kit.cylinder(model, "CoinFace", v(7.4, 13.2, 0), 0.9, 5.3, Palette.GoldLight, nil, CFrame.identity),
		true
	)
	for _, side in { Enum.NormalId.Left, Enum.NormalId.Right } do
		Kit.text(Kit.surface(coin, side), "SELL")
	end
end

--- Name arch over the yard gate. The front faces into the yard and the back
--- repeats the owner for the road; both read "Open Plot" while unowned.
local function buildGate(model: Model, center: Vector3): TextLabel
	local z = Site.PadHalf
	local px = Site.GateHalf + 1
	local function at(x: number, y: number): CFrame
		return CFrame.new(offset(center, x, y, z))
	end
	for _, s in { -1, 1 } do
		Kit.part(model, "GatePost", Vector3.new(1.4, 12.4, 1.4), at(s * px, 6.2), Palette.WoodDark, WOOD)
		Kit.decor(
			Kit.part(
				model,
				"GateLantern",
				Vector3.new(1.1, 1.3, 1.1),
				at(s * px, 13.05),
				Palette.Lamp,
				Enum.Material.Neon
			)
		)
		Kit.decor(
			Kit.part(model, "GateLanternCap", Vector3.new(1.7, 0.4, 1.7), at(s * px, 13.9), Palette.SteelDark),
			true
		)
	end
	local frame =
		Kit.decor(Kit.part(model, "NameFrame", Vector3.new(16, 4.2, 0.5), at(0, 10.3), Palette.WoodDeep, WOOD), true)
	Kit.light(frame, 18)
	local board =
		Kit.decor(Kit.part(model, "NameBoard", Vector3.new(15, 3.4, 0.7), at(0, 10.3), Palette.WoodLight, WOOD), true)

	local front = Kit.surface(board, Enum.NormalId.Front)
	local placeholder = Kit.text(front, OPEN_PLOT)
	placeholder.TextColor3 = UITheme.Colors.Muted
	local nameLabel = Kit.text(front, "")
	local back = Kit.text(Kit.surface(board, Enum.NormalId.Back), OPEN_PLOT)
	local function sync()
		local owner = nameLabel.Text
		placeholder.Visible = owner == ""
		back.Text = if owner == "" then OPEN_PLOT else owner
		back.TextColor3 = if owner == "" then UITheme.Colors.Muted else UITheme.Colors.Text
	end
	nameLabel:GetPropertyChangedSignal("Text"):Connect(sync)
	sync()
	return nameLabel
end

--- Low rail fence round the yard, open at the gate. It is jumpable: it only
--- guides players toward the road.
local function buildFence(model: Model, center: Vector3)
	local h = Site.PadHalf
	local gate = Site.GateHalf + 1 -- the gate posts carry the rails' ends
	local placed: { [string]: boolean } = {}
	local function post(x: number, z: number)
		local key = `{x},{z}`
		if not placed[key] then
			placed[key] = true
			Kit.part(
				model,
				"FencePost",
				Vector3.new(0.8, 3.4, 0.8),
				CFrame.new(offset(center, x, 1.7, z)),
				Palette.WoodDark,
				WOOD
			)
		end
	end
	local function run(a: Vector3, b: Vector3, postAtA: boolean, postAtB: boolean)
		local span = b - a
		local length = span.Magnitude
		local size = if math.abs(span.X) > 0 then Vector3.new(length, 0.45, 0.35) else Vector3.new(0.35, 0.45, length)
		local mid = (a + b) / 2
		for _, y in { 1.3, 2.6 } do
			local rail =
				Kit.part(model, "FenceRail", size, CFrame.new(offset(center, mid.X, y, mid.Z)), Palette.WoodLight, WOOD)
			rail.CastShadow = false
		end
		local count = math.ceil(length / 12)
		for i = 0, count do
			if (i > 0 or postAtA) and (i < count or postAtB) then
				local p = a + span * (i / count)
				post(p.X, p.Z)
			end
		end
	end
	run(Vector3.new(-h, 0, -h), Vector3.new(h, 0, -h), true, true)
	run(Vector3.new(-h, 0, -h), Vector3.new(-h, 0, h), true, true)
	run(Vector3.new(h, 0, -h), Vector3.new(h, 0, h), true, true)
	run(Vector3.new(-h, 0, h), Vector3.new(-gate, 0, h), true, false)
	run(Vector3.new(gate, 0, h), Vector3.new(h, 0, h), false, true)
end

--- Yard dressing, kept clear of the deck, the pad and the gate walkway.
local function buildProps(model: Model, center: Vector3, rng: Random)
	local function v(x: number, y: number, z: number): Vector3
		return offset(center, x, y, z)
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(v(x, y, z))
	end
	-- Ore cart on a short track running west off the deck.
	local track = 11.2
	Kit.oreCart(model, at(-(Site.DeckHalf + 0.2 + track / 2), 0, 0) * CFrame.Angles(0, math.pi / 2, 0), track, 0)

	Kit.crate(model, at(-18, 1.6, -18) * CFrame.Angles(0, 0.15, 0), 3.2)
	Kit.crate(model, at(-17.8, 4.4, -18.1) * CFrame.Angles(0, -0.3, 0), 2.4)
	Kit.barrel(model, v(-13.8, 0, -19.5))

	local slate = Enum.Material.Slate
	Kit.decor(
		Kit.part(
			model,
			"Rock",
			Vector3.new(2.8, 2, 2.4),
			at(15, 0.8, -17) * CFrame.Angles(0.2, 0.7, -0.1),
			Palette.Stone,
			slate
		)
	)
	Kit.decor(
		Kit.part(
			model,
			"Rock",
			Vector3.new(1.8, 1.3, 1.6),
			at(13.2, 0.5, -18.4) * CFrame.Angles(-0.2, 1.9, 0.15),
			Palette.StoneLight,
			slate
		)
	)
	Kit.decor(
		Kit.part(
			model,
			"Crystal",
			Vector3.new(0.8, 2.6, 0.8),
			at(15.6, 2, -16.4) * CFrame.Angles(0.35, 0.4, -0.25),
			Palette.Cyan,
			Enum.Material.Neon
		)
	)
	local handle =
		Kit.decor(Kit.beam(model, "Pickaxe", v(12.4, 0.1, -15.2), v(13.6, 3.9, -16.2), 0.35, Palette.Wood, WOOD))
	local head = handle.CFrame * CFrame.new(0, 0, -handle.Size.Z / 2 + 0.25)
	Kit.decor(Kit.part(model, "PickaxeHead", Vector3.new(2.8, 0.45, 0.5), head, Palette.Steel, Enum.Material.Metal))

	Kit.bush(model, v(-20.5, 0, 20), rng, 1)
	Kit.bush(model, v(20.5, 0, -20.5), rng, 1.1)
end

local function buildPlot(index: number, center: Vector3): Plot
	local model = Instance.new("Model")
	model.Name = `Plot{index}`

	local H = G.BlockSize
	buildDigSite(model, center)

	-- Cap keeps non-owners out of this shaft; the owner's client hides it.
	local cap = Kit.part(
		model,
		"ShaftCap",
		Vector3.new(H, 1, H),
		CFrame.new(center + Vector3.new(0, G.SurfaceY - 0.5, 0)),
		Palette.Pit
	)

	local sellPad = Kit.part(
		model,
		"SellPad",
		Vector3.new(8, 0.4, 8),
		CFrame.new(center + Vector3.new(G.SellPadOffset, G.SurfaceY + 0.2, 0)),
		Palette.Gold
	)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Sell ore"
	prompt.ObjectText = "Trading post"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = G.SellRadius
	prompt.RequiresLineOfSight = false
	prompt.Parent = sellPad

	buildHeadframe(model, center)
	buildWinch(model, center)
	buildStall(model, center, sellPad)
	buildFence(model, center)
	buildProps(model, center, Random.new(index))
	local nameLabel = buildGate(model, center)

	model.Parent = Workspace

	return {
		index = index,
		center = center,
		model = model,
		sellPad = sellPad,
		cap = cap,
		nameLabel = nameLabel,
		owner = nil,
	}
end

function PlotService.getPlot(player: Player): Plot?
	return plotByPlayer[player]
end

function PlotService.getAll(): { Plot }
	return plots
end

--- Where a character stands when it is on top of block `depth + 1`.
function PlotService.standingCFrame(player: Player, depth: number): CFrame?
	local plot = plotByPlayer[player]
	if not plot then
		return nil
	end
	local top = G.SurfaceY - depth * G.BlockHeight
	return CFrame.new(plot.center + Vector3.new(0, top + 3.5, 0))
end

function PlotService.surfaceCFrame(player: Player): CFrame?
	local plot = plotByPlayer[player]
	if not plot then
		return nil
	end
	return CFrame.new(
		plot.center + Vector3.new(G.SellPadOffset - 6, G.SurfaceY + 3.5, 0),
		plot.center + Vector3.new(G.SellPadOffset, G.SurfaceY + 3.5, 0)
	)
end

function PlotService.isNearSellPad(player: Player): boolean
	local plot = plotByPlayer[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not plot or not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - plot.sellPad.Position).Magnitude <= G.SellRadius
end

local function assign(player: Player)
	for _, plot in plots do
		if plot.owner == nil then
			plot.owner = player
			plotByPlayer[player] = plot
			plot.nameLabel.Text = player.DisplayName
			player:SetAttribute("PlotIndex", plot.index)
			plot.model:SetAttribute("OwnerUserId", player.UserId)
			return
		end
	end
	player:Kick("Server is full.")
end

local function release(player: Player)
	local plot = plotByPlayer[player]
	if plot then
		plot.owner = nil
		plot.nameLabel.Text = ""
		plot.model:SetAttribute("OwnerUserId", 0)
		plotByPlayer[player] = nil
	end
end

function PlotService.teleportHome(player: Player)
	local character = player.Character
	local cf = PlotService.surfaceCFrame(player)
	if character and cf then
		character:PivotTo(cf)
	end
end

function PlotService.init()
	for i, center in WorldBuilder.plotCenters() do
		plots[i] = buildPlot(i, center)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Size = Vector3.new(4, 1, 4)
	spawn.Position = Vector3.new(0, 60, 0)
	spawn.Neutral = true
	spawn.Parent = Workspace

	local function watch(player: Player)
		assign(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 5)
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
