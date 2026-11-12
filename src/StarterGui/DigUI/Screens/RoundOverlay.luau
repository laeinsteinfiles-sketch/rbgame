--!strict
-- Explorer: StarterGui/DigUI/Screens/RoundOverlay (ModuleScript)
-- Lobby/countdown chip, the Mega Drill banner with the shared goal bar, and
-- the round results sheet. All driven by RoundState attributes + two remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Base = require(script.Parent.Parent.Components.Base)
local Bar = require(script.Parent.Parent.Components.Bar)
local Icon = require(script.Parent.Parent.Components.Icon)
local Label = require(script.Parent.Parent.Components.Label)
local Panel = require(script.Parent.Parent.Components.Panel)

local RoundOverlay = {}

function RoundOverlay.new(ctx: Base.Context)
	local state = ctx.state
	local overlay = ctx.overlay

	-- Countdown numbers ----------------------------------------------------------
	local countdown = Label.new({
		parent = overlay,
		name = "Countdown",
		text = "",
		size = UDim2.new(0, 200, 0, 90),
		position = UDim2.fromScale(0.5, 0.35),
		anchor = Vector2.new(0.5, 0.5),
		align = Enum.TextXAlignment.Center,
		textSize = UITheme.TextSize.Hero,
		display = true,
		color = UITheme.Colors.Amber,
	})
	countdown.TextStrokeTransparency = 0.5
	countdown.TextStrokeColor3 = UITheme.Colors.PanelInset
	countdown.Visible = false

	local lastShown = -1
	RunService.Heartbeat:Connect(function()
		local phase = state.phase()
		if phase ~= "Countdown" then
			if countdown.Visible then
				countdown.Visible = false
				lastShown = -1
			end
			return
		end
		local remaining = math.ceil(state.phaseRemaining())
		if remaining ~= lastShown then
			lastShown = remaining
			countdown.Visible = true
			countdown.Text = if remaining <= 0 then "DIG!" else tostring(remaining)
			ctx.juice.punch(countdown, 0.35)
			ctx.sfx.play(if remaining <= 0 then "RoundStart" else "Countdown", { pitch = 1 + (5 - remaining) * 0.05 })
		end
	end)
	state.onRound("Phase", function(phase)
		if phase == "Active" then
			ctx.sfx.play("RoundStart")
		end
	end)

	-- Mega Drill banner -----------------------------------------------------------
	local banner = Panel.new({
		parent = overlay,
		name = "MegaBanner",
		size = UDim2.new(0, 300, 0, 74),
		position = UDim2.new(0.5, 0, 0, -90),
		anchor = Vector2.new(0.5, 0),
		padding = 8,
	})
	local bannerStroke = banner:FindFirstChildOfClass("UIStroke")
	if bannerStroke then
		bannerStroke.Color = UITheme.Colors.Amber
	end
	Icon.new({ parent = banner, id = AssetIds.Icons.Mega, size = UDim2.fromOffset(22, 22), color = UITheme.Colors.Amber })
	local megaTitle = Label.new({
		parent = banner,
		text = "MEGA DRILL  ×1.5 POWER",
		size = UDim2.new(1, -90, 0, 22),
		position = UDim2.fromOffset(28, 0),
		textSize = UITheme.TextSize.Body,
		display = true,
		color = UITheme.Colors.Amber,
	})
	local megaTime = Label.new({
		parent = banner,
		text = "0:60",
		size = UDim2.new(0, 60, 0, 22),
		position = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		align = Enum.TextXAlignment.Right,
		textSize = UITheme.TextSize.Body,
		display = true,
	})
	local goalBar = Bar.new({
		parent = banner,
		size = UDim2.new(1, 0, 0, 16),
		position = UDim2.fromOffset(0, 28),
		color = UITheme.Colors.Amber,
		label = true,
	})
	Label.new({
		parent = banner,
		text = `Shared goal · +{GameConfig.Round.MegaDrill.GemBonus} gems for everyone`,
		size = UDim2.new(1, 0, 0, 14),
		position = UDim2.fromOffset(0, 46),
		textSize = UITheme.TextSize.Small,
		color = UITheme.Colors.TextDim,
	})

	local SHOWN = UDim2.new(0.5, 0, 0, 76)
	local HIDDEN = UDim2.new(0.5, 0, 0, -90)
	local function setBanner(visible: boolean)
		TweenService:Create(banner, if visible then UITheme.Easing.Pop else UITheme.Easing.SlideOut, { Position = if visible then SHOWN else HIDDEN }):Play()
	end
	state.onRound("MegaActive", function(active)
		setBanner(active == true)
	end)
	state.onRound("MegaProgress", function(progress)
		local goal = math.max(1, tonumber(state.round("MegaGoal")) or 1)
		local p = if typeof(progress) == "number" then progress else 0
		goalBar.setFraction(p / goal)
		goalBar.setLabel(`{math.floor(p)} / {goal} blocks`)
	end)
	RunService.Heartbeat:Connect(function()
		if state.round("MegaActive") == true then
			megaTime.Text = Format.clock(state.megaRemaining())
		end
	end)
	state.onMegaEvent:Connect(function(kind)
		if kind == "start" then
			ctx.sfx.play("MegaStart", { volume = 0.8 })
			ctx.fx.shake(0.25, 0.5)
			megaTitle.Text = "MEGA DRILL  ×1.5 POWER"
		elseif kind == "goal" then
			ctx.sfx.play("MegaGoal", { volume = 0.9 })
			megaTitle.Text = "GOAL REACHED"
			ctx.juice.punch(banner, 0.12)
			task.delay(1.6, function()
				setBanner(false)
			end)
		else
			ctx.sfx.play("MegaEnd")
		end
	end)

	-- Results sheet --------------------------------------------------------------------
	local sheet = Panel.new({
		parent = overlay,
		name = "Results",
		size = UDim2.fromScale(0.8, 0.7),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		padding = 14,
	})
	Base.sizeConstraint(sheet, Vector2.new(300, 260), Vector2.new(560, 420))
	sheet.Visible = false
	local sheetScale = Instance.new("UIScale")
	sheetScale.Parent = sheet
	local headline = Label.new({
		parent = sheet,
		text = "",
		size = UDim2.new(1, 0, 0, 34),
		align = Enum.TextXAlignment.Center,
		textSize = UITheme.TextSize.Title,
		display = true,
		color = UITheme.Colors.Amber,
		truncate = true,
	})
	local subline = Label.new({
		parent = sheet,
		text = "",
		size = UDim2.new(1, 0, 0, 20),
		position = UDim2.fromOffset(0, 34),
		align = Enum.TextXAlignment.Center,
		textSize = UITheme.TextSize.Small,
		color = UITheme.Colors.TextDim,
	})
	local rowsFrame = Base.frame(sheet, "Rows", UDim2.new(1, 0, 1, -124), UDim2.fromOffset(0, 62))
	Base.list(rowsFrame, Enum.FillDirection.Vertical, 6)
	local rowLabels: { TextLabel } = {}
	for i = 1, 4 do
		local row = Panel.new({ parent = rowsFrame, inset = true, size = UDim2.new(1, 0, 0, 34), padding = 6, layoutOrder = i })
		rowLabels[i] = Label.new({ parent = row, text = "", size = UDim2.fromScale(1, 1), textSize = UITheme.TextSize.Body, display = i == 1, truncate = true })
		row.Visible = false
	end
	local yourLine = Label.new({
		parent = sheet,
		text = "",
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.new(0, 0, 1, -34),
		align = Enum.TextXAlignment.Center,
		textSize = UITheme.TextSize.Body,
		display = true,
		color = UITheme.Colors.Teal,
	})
	local nextLine = Label.new({
		parent = sheet,
		text = "",
		size = UDim2.new(1, 0, 0, 16),
		position = UDim2.new(0, 0, 1, -8),
		align = Enum.TextXAlignment.Center,
		textSize = UITheme.TextSize.Small,
		color = UITheme.Colors.TextDim,
	})

	state.onRoundResults:Connect(function(standings: { Types.Standing }, placement: number, gems: number)
		local winner = standings[1]
		local byCore = state.round("WinnerByCore") == true
		headline.Text = if winner then `{winner.name} wins` else "Round over"
		subline.Text = if winner then (if byCore then "Reached the core" else `Deepest at the bell · {Format.depth(winner.depth)}`) else ""
		for i, label in rowLabels do
			local s = standings[i]
			local row = label.Parent :: GuiObject
			row.Visible = s ~= nil
			if s then
				label.Text = `#{s.placement}   {s.name}   {Format.depth(s.depth)}`
				label.TextColor3 = if s.userId == Players.LocalPlayer.UserId then UITheme.Colors.Teal else (if i == 1 then UITheme.Colors.Amber else UITheme.Colors.Text)
			end
		end
		yourLine.Text = `You finished #{placement}  ·  +{gems} gems`
		sheet.Visible = true
		sheetScale.Scale = 0.9
		TweenService:Create(sheetScale, UITheme.Easing.Pop, { Scale = 1 }):Play()
		ctx.sfx.play(if placement == 1 then "Win" else "RoundEnd")
	end)
	RunService.Heartbeat:Connect(function()
		if sheet.Visible then
			if state.phase() ~= "Results" then
				sheet.Visible = false
			else
				nextLine.Text = `Next round in {Format.clock(state.phaseRemaining())}`
			end
		end
	end)
end

return RoundOverlay
