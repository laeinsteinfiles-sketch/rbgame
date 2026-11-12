--!strict
-- Explorer: ServerScriptService/Services/PlotService (ModuleScript)
-- Twelve floating islands, one private shaft each. The server owns only the
-- surface; everything below is rendered client-side by ShaftRenderer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)

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
local surfaceLayer = GameConfig.Layers[1]

local function part(name: string, size: Vector3, cframe: CFrame, color: string, material: string, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = Color3.fromHex(color)
	p.Material = (Enum.Material :: any)[material]
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function buildSign(parent: Instance, cframe: CFrame): TextLabel
	local board = part("NameBoard", Vector3.new(12, 3, 0.6), cframe, "23272E", "SmoothPlastic", parent)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = UITheme.Font.Display
	label.TextScaled = true
	label.TextColor3 = UITheme.Colors.Amber
	label.Text = ""
	label.Parent = gui
	return label
end

local function buildPlot(index: number, center: Vector3): Plot
	local model = Instance.new("Model")
	model.Name = `Plot{index}`

	local S, H = G.IslandSize, G.BlockSize
	local ring = (S - H) / 2
	local groundY = G.SurfaceY - 1
	local color, material = surfaceLayer.groundColor, surfaceLayer.material
	part("North", Vector3.new(S, 2, ring), CFrame.new(center + Vector3.new(0, groundY, -(H / 2 + ring / 2))), color, material, model)
	part("South", Vector3.new(S, 2, ring), CFrame.new(center + Vector3.new(0, groundY, H / 2 + ring / 2)), color, material, model)
	part("West", Vector3.new(ring, 2, H), CFrame.new(center + Vector3.new(-(H / 2 + ring / 2), groundY, 0)), color, material, model)
	part("East", Vector3.new(ring, 2, H), CFrame.new(center + Vector3.new(H / 2 + ring / 2, groundY, 0)), color, material, model)

	-- Collar: a low rim so the shaft reads as a hole from across the map.
	local rimColor = surfaceLayer.wallColor
	for _, offset in { Vector3.new(0, 0, -(H / 2 + 0.5)), Vector3.new(0, 0, H / 2 + 0.5) } do
		part("Rim", Vector3.new(H + 2, 1, 1), CFrame.new(center + offset + Vector3.new(0, G.SurfaceY + 0.5, 0)), rimColor, "Slate", model)
	end
	for _, offset in { Vector3.new(-(H / 2 + 0.5), 0, 0), Vector3.new(H / 2 + 0.5, 0, 0) } do
		part("Rim", Vector3.new(1, 1, H), CFrame.new(center + offset + Vector3.new(0, G.SurfaceY + 0.5, 0)), rimColor, "Slate", model)
	end

	-- Cap keeps non-owners out of this shaft; the owner's client hides it.
	local cap = part("ShaftCap", Vector3.new(H, 1, H), CFrame.new(center + Vector3.new(0, G.SurfaceY - 0.5, 0)), color, material, model)

	-- Invisible rails so nobody walks off into the void.
	for _, def in {
		{ Vector3.new(S, 8, 1), Vector3.new(0, 3, -S / 2) },
		{ Vector3.new(S, 8, 1), Vector3.new(0, 3, S / 2) },
		{ Vector3.new(1, 8, S), Vector3.new(-S / 2, 3, 0) },
		{ Vector3.new(1, 8, S), Vector3.new(S / 2, 3, 0) },
	} do
		local rail = part("Rail", def[1], CFrame.new(center + def[2]), color, "SmoothPlastic", model)
		rail.Transparency = 1
	end

	local sellPad = part(
		"SellPad",
		Vector3.new(8, 0.4, 8),
		CFrame.new(center + Vector3.new(G.SellPadOffset, G.SurfaceY + 0.2, 0)),
		"F2B33D",
		"SmoothPlastic",
		model
	)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Sell ore"
	prompt.ObjectText = "Trading post"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = G.SellRadius
	prompt.RequiresLineOfSight = false
	prompt.Parent = sellPad

	local post = part("SellPost", Vector3.new(1, 7, 1), CFrame.new(center + Vector3.new(G.SellPadOffset, G.SurfaceY + 3.5, -5)), "23272E", "SmoothPlastic", model)
	post.Name = "SellPost"

	local nameLabel = buildSign(model, CFrame.new(center + Vector3.new(0, G.SurfaceY + 4, -S / 2 + 1.5)))

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
	return CFrame.new(plot.center + Vector3.new(G.SellPadOffset - 6, G.SurfaceY + 3.5, 0), plot.center + Vector3.new(G.SellPadOffset, G.SurfaceY + 3.5, 0))
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
	local cols = G.PlotColumns
	local rows = math.ceil(G.MaxPlayers / cols)
	for i = 0, G.MaxPlayers - 1 do
		local col, row = i % cols, i // cols
		local center = Vector3.new((col - (cols - 1) / 2) * G.PlotSpacing, 0, (row - (rows - 1) / 2) * G.PlotSpacing)
		plots[i + 1] = buildPlot(i + 1, center)
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
