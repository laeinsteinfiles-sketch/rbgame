--!strict
-- Explorer: StarterGui/DigUI/Screens/RaceTracker (ModuleScript)
-- The race at a glance on the right edge: a vertical track from the surface
-- to the core, coloured by layer, with every player's avatar at their depth,
-- plus the top standings. Depth only; catch-up stays invisible here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Format = require(ReplicatedStorage.Shared.Format)
local Base = require(script.Parent.Parent.Components.Base)
local Icon = require(script.Parent.Parent.Components.Icon)
local Label = require(script.Parent.Parent.Components.Label)
local Panel = require(script.Parent.Parent.Components.Panel)

local RaceTracker = {}

local ROWS = 5
local ROW_H = 24
local MOVE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local LAYER_SWATCH: { [string]: string } = {
	topsoil = "orange",
	bedrock = "blue",
	hollows = "purple",
}

type Marker = { frame: Frame, ring: UIStroke, crown: TextLabel, tag: TextLabel }
type Row = { frame: Frame, place: TextLabel, name: TextLabel, depth: TextLabel }

function RaceTracker.new(ctx: Base.Context)
	local me = Players.LocalPlayer

	local function depthOf(player: Player): number
		local value = player:GetAttribute("Depth")
		local depth = if typeof(value) == "number" then value else 0
		if player == me then
			depth = math.max(depth, ctx.dig.localDepth())
		end
		return depth
	end

	local panel = Panel.new({
		parent = ctx.hud,
		name = "Race",
		style = "dark",
		size = UDim2.new(0, 200, 0.62, 0),
		position = UDim2.new(1, -12, 0, 86),
		anchor = Vector2.new(1, 0),
		padding = 8,
	})
	Base.sizeConstraint(panel, Vector2.new(200, 236), Vector2.new(200, 450))

	Label.new({ parent = panel, text = "🏁 RACE", size = UDim2.new(1, -60, 0, 24), textSize = 20, display = true })
	local placeChip = Base.fill(panel, "Place", Color3.new(1, 1, 1), UDim2.fromOffset(62, 26), UDim2.new(1, 0, 0, 0), Vector2.new(1, 0))
	Base.round(placeChip)
	Base.stroke(placeChip, UITheme.Colors.Ink, 2)
	Base.gradient(placeChip, UITheme.Swatches.gold.top, UITheme.Swatches.gold.bottom)
	local placeLabel = Label.new({ parent = placeChip, text = "#1", size = UDim2.fromScale(1, 1), align = Enum.TextXAlignment.Center, textSize = 17, display = true })

	-- Track: a rounded CanvasGroup so the layer bands clip to its corners.
	local track = Instance.new("CanvasGroup")
	track.Name = "Track"
	track.BackgroundColor3 = UITheme.Colors.Ink
	track.BorderSizePixel = 0
	track.Size = UDim2.new(0, 22, 1, -66)
	track.Position = UDim2.new(1, -22, 0, 36)
	track.AnchorPoint = Vector2.new(0.5, 0)
	Base.round(track)
	track.Parent = panel
	local trackStroke = Base.frame(panel, "TrackStroke", track.Size, track.Position, track.AnchorPoint)
	Base.round(trackStroke)
	Base.stroke(trackStroke, UITheme.Colors.Ink, 3)
	for i, layer in GameConfig.Layers do
		local nextLayer = GameConfig.Layers[i + 1]
		local y0 = layer.startDepth / GameConfig.CoreDepth
		local y1 = (if nextLayer then nextLayer.startDepth else GameConfig.CoreDepth) / GameConfig.CoreDepth
		local band = Base.fill(track, layer.id, Color3.new(1, 1, 1), UDim2.fromScale(1, y1 - y0), UDim2.fromScale(0, y0))
		local swatch = UITheme.swatch(LAYER_SWATCH[layer.id] or "grey")
		Base.gradient(band, swatch.top, swatch.bottom, 0)
	end
	local grass = Base.fill(track, "Grass", UITheme.Colors.Green, UDim2.new(1, 0, 0, 6))
	grass.ZIndex = 2
	Icon.new({ parent = panel, name = "Core", size = UDim2.fromOffset(30, 30), position = UDim2.new(1, -22, 1, 2), anchor = Vector2.new(0.5, 1), zIndex = 3 })

	local lane = Base.frame(panel, "Lane", track.Size, track.Position, track.AnchorPoint)
	lane.ZIndex = 5

	-- Standings rows (left of the track).
	local list = Base.frame(panel, "Rows", UDim2.new(1, -46, 0, (ROWS + 1) * (ROW_H + 3)), UDim2.fromOffset(0, 36))
	Base.list(list, Enum.FillDirection.Vertical, 3)
	local rows: { Row } = {}
	for i = 1, ROWS + 1 do
		local frame = Base.fill(list, `Row{i}`, UITheme.Colors.White, UDim2.new(1, 0, 0, ROW_H))
		frame.BackgroundTransparency = 1
		frame.LayoutOrder = i
		Base.corner(frame, 8)
		local place = Label.new({ parent = frame, text = "", size = UDim2.new(0, 26, 1, 0), position = UDim2.fromOffset(4, 0), textSize = 15, display = true, color = UITheme.Colors.Gold })
		local name = Label.new({ parent = frame, text = "", size = UDim2.new(1, -78, 1, 0), position = UDim2.fromOffset(28, 0), textSize = 14, truncate = true })
		local depth = Label.new({ parent = frame, text = "", size = UDim2.new(0, 48, 1, 0), position = UDim2.new(1, -4, 0, 0), anchor = Vector2.new(1, 0), align = Enum.TextXAlignment.Right, textSize = 14, display = true })
		frame.Visible = false
		rows[i] = { frame = frame, place = place, name = name, depth = depth }
	end

	local markers: { [Player]: Marker } = {}
	local function addMarker(player: Player)
		if markers[player] then
			return
		end
		local isMe = player == me
		local size = if isMe then 34 else 26
		local frame = Base.frame(lane, player.Name, UDim2.fromOffset(size, size), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0.5))
		frame.ZIndex = if isMe then 8 else 6
		local image = Instance.new("ImageLabel")
		image.Name = "Face"
		image.BackgroundColor3 = Color3.fromHex("DCE7FF")
		image.Size = UDim2.fromScale(1, 1)
		image.Image = Base.headshot(player.UserId)
		image.ZIndex = frame.ZIndex
		Base.round(image)
		local ring = Base.stroke(image, if isMe then UITheme.Colors.Gold else UITheme.Colors.White, if isMe then 3 else 2)
		image.Parent = frame
		local crown = Instance.new("TextLabel")
		crown.BackgroundTransparency = 1
		crown.Size = UDim2.fromOffset(20, 20)
		crown.Position = UDim2.new(0.5, 0, 0, -8)
		crown.AnchorPoint = Vector2.new(0.5, 0.5)
		crown.Text = "👑"
		crown.TextScaled = true
		crown.ZIndex = frame.ZIndex + 1
		crown.Visible = false
		crown.Parent = frame
		local tag = Label.new({
			parent = frame,
			text = "",
			size = UDim2.fromOffset(60, 20),
			position = UDim2.new(0, -6, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			align = Enum.TextXAlignment.Right,
			textSize = 15,
			display = true,
			color = UITheme.Colors.Gold,
			zIndex = frame.ZIndex,
		})
		tag.Visible = isMe
		markers[player] = { frame = frame, ring = ring, crown = crown, tag = tag }
	end
	local function removeMarker(player: Player)
		local marker = markers[player]
		if marker then
			marker.frame:Destroy()
			markers[player] = nil
		end
	end
	for _, player in Players:GetPlayers() do
		addMarker(player)
	end
	Players.PlayerAdded:Connect(addMarker)
	Players.PlayerRemoving:Connect(removeMarker)

	local function fill(row: Row, placement: number, player: Player)
		local isMe = player == me
		row.frame.Visible = true
		row.frame.BackgroundTransparency = if isMe then 0.82 else 1
		row.place.Text = `{placement}`
		row.name.Text = player.DisplayName
		row.depth.Text = Format.depth(depthOf(player))
		Label.setColor(row.place, if placement == 1 then UITheme.Colors.Gold else UITheme.Colors.White)
		Label.setColor(row.name, if isMe then UITheme.Colors.Gold else UITheme.Colors.White)
	end

	local function refresh()
		local players = Players:GetPlayers()
		local depths: { [Player]: number } = {}
		for _, player in players do
			depths[player] = depthOf(player)
		end
		table.sort(players, function(a, b)
			if depths[a] ~= depths[b] then
				return depths[a] > depths[b]
			end
			return a.Name < b.Name
		end)
		local myPlace = 1
		for i, player in players do
			if player == me then
				myPlace = i
			end
		end
		placeLabel.Text = `#{myPlace}/{#players}`

		for _, row in rows do
			row.frame.Visible = false
		end
		for i = 1, math.min(ROWS, #players) do
			fill(rows[i], i, players[i])
		end
		if myPlace > ROWS then
			fill(rows[ROWS + 1], myPlace, me)
		end

		-- Markers at the same depth fan out sideways so faces never stack.
		local seen: { [number]: number } = {}
		for i, player in players do
			local marker = markers[player]
			if marker then
				local frac = math.clamp(depths[player] / GameConfig.CoreDepth, 0, 1)
				local bucket = math.floor(frac * 40)
				local n = seen[bucket] or 0
				seen[bucket] = n + 1
				local spread = if player == me then 0 else (if n % 2 == 0 then -1 else 1) * math.ceil(n / 2) * 12
				TweenService:Create(marker.frame, MOVE, { Position = UDim2.new(0.5, spread, frac, 0) }):Play()
				marker.crown.Visible = i == 1 and depths[player] > 0
				if player == me then
					marker.tag.Text = Format.depth(depths[player])
				end
			end
		end
	end

	task.spawn(function()
		while true do
			refresh()
			task.wait(0.4)
		end
	end)
end

return RaceTracker
