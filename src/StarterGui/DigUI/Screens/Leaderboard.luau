--!strict
-- Explorer: StarterGui/DigUI/Screens/Leaderboard (ModuleScript)
-- Live depth standings from every player's replicated Depth attribute.
-- Shows depth only: catch-up is deliberately invisible here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Format = require(ReplicatedStorage.Shared.Format)
local Base = require(script.Parent.Parent.Components.Base)
local Icon = require(script.Parent.Parent.Components.Icon)
local Label = require(script.Parent.Parent.Components.Label)
local Panel = require(script.Parent.Parent.Components.Panel)

local Leaderboard = {}

-- Four rows plus "you" keeps the panel clear of the menu row on a phone.
local ROWS = 4
local ROW_HEIGHT = 26

type Row = { frame: Frame, place: TextLabel, name: TextLabel, depth: TextLabel }

local function depthOf(player: Player): number
	local value = player:GetAttribute("Depth")
	return if typeof(value) == "number" then value else 0
end

function Leaderboard.new(ctx: Base.Context)
	local panel = Panel.new({
		parent = ctx.hud,
		name = "Leaderboard",
		size = UDim2.new(0.22, 0, 0, 24 + (ROWS + 1) * (ROW_HEIGHT + 4) + 8),
		position = UDim2.new(1, -12, 0, 120),
		anchor = Vector2.new(1, 0),
		padding = 8,
	})
	Base.sizeConstraint(panel, Vector2.new(170, 0), Vector2.new(260, 400))
	Icon.new({ parent = panel, id = AssetIds.Icons.Trophy, size = UDim2.fromOffset(18, 18), color = UITheme.Colors.TextDim })
	Label.new({
		parent = panel,
		text = "DEEPEST",
		size = UDim2.new(1, -24, 0, 18),
		position = UDim2.fromOffset(24, 0),
		textSize = UITheme.TextSize.Small,
		color = UITheme.Colors.TextDim,
	})
	local list = Base.frame(panel, "Rows", UDim2.new(1, 0, 1, -24), UDim2.fromOffset(0, 24))
	Base.list(list, Enum.FillDirection.Vertical, 4)

	local rows: { Row } = {}
	for i = 1, ROWS + 1 do
		local frame = Base.frame(list, `Row{i}`, UDim2.new(1, 0, 0, ROW_HEIGHT))
		frame.LayoutOrder = i
		frame.BackgroundTransparency = 1
		Base.corner(frame)
		local stroke = Base.stroke(frame, UITheme.Colors.Teal)
		stroke.Transparency = 1
		local place = Label.new({ parent = frame, text = "", size = UDim2.new(0, 30, 1, 0), position = UDim2.fromOffset(6, 0), textSize = UITheme.TextSize.Small, display = true, color = UITheme.Colors.TextDim })
		local name = Label.new({ parent = frame, text = "", size = UDim2.new(1, -100, 1, 0), position = UDim2.fromOffset(36, 0), textSize = UITheme.TextSize.Small, truncate = true })
		local depth = Label.new({ parent = frame, text = "", size = UDim2.new(0, 64, 1, 0), position = UDim2.new(1, -6, 0, 0), anchor = Vector2.new(1, 0), align = Enum.TextXAlignment.Right, textSize = UITheme.TextSize.Small, display = true })
		rows[i] = { frame = frame, place = place, name = name, depth = depth }
		frame.Visible = false
	end

	local function fill(row: Row, placement: number, player: Player, isYou: boolean)
		row.frame.Visible = true
		row.place.Text = `#{placement}`
		row.name.Text = player.DisplayName
		row.depth.Text = Format.depth(depthOf(player))
		local leader = placement == 1
		row.place.TextColor3 = if leader then UITheme.Colors.Amber else UITheme.Colors.TextDim
		row.depth.TextColor3 = if leader then UITheme.Colors.Amber else UITheme.Colors.Text
		row.name.TextColor3 = if isYou then UITheme.Colors.Teal else UITheme.Colors.Text
		local stroke = row.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = if isYou then 0 else 1
		end
	end

	local function refresh()
		local players = Players:GetPlayers()
		table.sort(players, function(a, b)
			local da, db = depthOf(a), depthOf(b)
			if da ~= db then
				return da > db
			end
			return a.Name < b.Name
		end)
		local me = Players.LocalPlayer
		local myPlace = 0
		for i, player in players do
			if player == me then
				myPlace = i
			end
		end
		for _, row in rows do
			row.frame.Visible = false
		end
		local shown = math.min(ROWS, #players)
		for i = 1, shown do
			fill(rows[i], i, players[i], players[i] == me)
		end
		if myPlace > ROWS then
			fill(rows[ROWS + 1], myPlace, me, true)
		end
	end

	task.spawn(function()
		while true do
			refresh()
			task.wait(0.5)
		end
	end)
end

return Leaderboard
