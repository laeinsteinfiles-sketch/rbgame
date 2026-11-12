--!strict
-- Explorer: ServerScriptService/Services/PlotService (ModuleScript)
-- Assigns each player one island from the ring and answers "where is this
-- player's shaft / sell pad / workshop" for every other service.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local WorldService = require(script.Parent.WorldService)

local PlotService = {}

export type Plot = {
	index: number,
	frame: CFrame,
	center: Vector3,
	info: WorldService.IslandInfo,
	owner: Player?,
}

local G = GameConfig.Geometry
local HIP = 3.2 -- root height above the surface a character stands on

local plots: { Plot } = {}
local plotByPlayer: { [Player]: Plot } = {}

function PlotService.getPlot(player: Player): Plot?
	return plotByPlayer[player]
end

function PlotService.getAll(): { Plot }
	return plots
end

--- Root CFrame for a character standing on block `depth + 1`, facing the hub.
function PlotService.standingCFrame(player: Player, depth: number): CFrame?
	local plot = plotByPlayer[player]
	if not plot then
		return nil
	end
	local top = G.SurfaceY - depth * G.BlockHeight
	return plot.frame.Rotation + Vector3.new(plot.center.X, top + HIP, plot.center.Z)
end

--- Arrival spot after riding up: between the shaft and the trading post.
function PlotService.surfaceCFrame(player: Player): CFrame?
	local plot = plotByPlayer[player]
	if not plot then
		return nil
	end
	local pad = plot.info.sellPad.Position
	local toShaft = Vector3.new(plot.center.X - pad.X, 0, plot.center.Z - pad.Z).Unit
	local spot = pad + toShaft * 4.5
	return CFrame.lookAt(Vector3.new(spot.X, G.SurfaceY + HIP, spot.Z), Vector3.new(pad.X, G.SurfaceY + HIP, pad.Z))
end

function PlotService.homeCFrame(player: Player): CFrame?
	local plot = plotByPlayer[player]
	if not plot then
		return nil
	end
	local home = plot.frame * CFrame.new(GameConfig.World.Home.x, HIP, GameConfig.World.Home.z)
	return CFrame.lookAt(home.Position, Vector3.new(plot.center.X, home.Position.Y, plot.center.Z))
end

local function near(player: Player, part: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - part.Position).Magnitude <= G.SellRadius
end

function PlotService.isNearSellPad(player: Player): boolean
	local plot = plotByPlayer[player]
	return plot ~= nil and near(player, plot.info.sellPad)
end

function PlotService.pivot(player: Player, cf: CFrame?)
	local character = player.Character
	if character and cf then
		character:PivotTo(cf)
	end
end

function PlotService.teleportHome(player: Player)
	PlotService.pivot(player, PlotService.homeCFrame(player))
end

function PlotService.setDepthLabel(player: Player, depth: number)
	local plot = plotByPlayer[player]
	if plot then
		plot.info.depthLabel.Text = `{math.floor(depth)} m`
	end
end

local function assign(player: Player)
	for _, plot in plots do
		if plot.owner == nil then
			plot.owner = player
			plotByPlayer[player] = plot
			plot.info.nameLabel.Text = player.DisplayName
			plot.info.depthLabel.Text = "0 m"
			plot.info.model:SetAttribute("OwnerUserId", player.UserId)
			player:SetAttribute("PlotIndex", plot.index)
			return
		end
	end
	player:Kick("Server is full.")
end

local function release(player: Player)
	local plot = plotByPlayer[player]
	if plot then
		plot.owner = nil
		plot.info.nameLabel.Text = ""
		plot.info.depthLabel.Text = ""
		plot.info.model:SetAttribute("OwnerUserId", 0)
		plotByPlayer[player] = nil
	end
end

--- Where a respawning character should appear; RoundService overrides this
--- during the podium ceremony.
PlotService.respawnAt = PlotService.homeCFrame

function PlotService.init()
	for i, info in WorldService.islands do
		plots[i] = { index = i, frame = info.frame, center = info.frame.Position, info = info, owner = nil }
	end
	local function watch(player: Player)
		assign(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 5)
			task.defer(function()
				PlotService.pivot(player, PlotService.respawnAt(player))
			end)
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
