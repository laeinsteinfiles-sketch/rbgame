--!strict
-- Explorer: StarterGui/DigUI/Screens/HUD (ModuleScript)
-- Depth meter, round timer, cash, backpack bar with sell/travel, dig control
-- and the menu row. Everything is scale-sized with min/max constraints so it
-- holds together from a phone to a 4K monitor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Format = require(ReplicatedStorage.Shared.Format)
local Layers = require(ReplicatedStorage.Shared.Layers)
local Base = require(script.Parent.Parent.Components.Base)
local Bar = require(script.Parent.Parent.Components.Bar)
local Button = require(script.Parent.Parent.Components.Button)
local Icon = require(script.Parent.Parent.Components.Icon)
local Label = require(script.Parent.Parent.Components.Label)
local Panel = require(script.Parent.Parent.Components.Panel)

local HUD = {}

export type Handle = {
	menu: Frame,
	setMenuAction: (name: string, fn: () -> ()) -> (),
}

local PHASE_TEXT = {
	Lobby = "Next round in",
	Countdown = "Get ready",
	Active = "Time left",
	Results = "Next round in",
}

function HUD.new(ctx: Base.Context): Handle
	local hud = ctx.hud
	local state = ctx.state
	local sfx = function(name: string)
		ctx.sfx.play(name)
	end

	-- Depth -----------------------------------------------------------------
	local depthPanel = Panel.new({
		parent = hud,
		name = "Depth",
		size = UDim2.new(0.22, 0, 0, 100),
		position = UDim2.fromOffset(12, 12),
	})
	Base.sizeConstraint(depthPanel, Vector2.new(170, 100), Vector2.new(260, 100))
	Icon.new({ parent = depthPanel, id = AssetIds.Icons.Depth, size = UDim2.fromOffset(20, 20), color = UITheme.Colors.TextDim })
	Label.new({
		parent = depthPanel,
		text = "DEPTH",
		size = UDim2.new(1, -26, 0, 18),
		position = UDim2.fromOffset(26, 0),
		textSize = UITheme.TextSize.Small,
		color = UITheme.Colors.TextDim,
	})
	local depthLabel = Label.new({
		parent = depthPanel,
		name = "Value",
		text = "0 m",
		size = UDim2.new(1, 0, 0, 40),
		position = UDim2.fromOffset(0, 18),
		textSize = UITheme.TextSize.Display,
		display = true,
	})
	local layerLabel = Label.new({
		parent = depthPanel,
		name = "Layer",
		text = Layers.get(1).name,
		size = UDim2.new(1, 0, 0, 16),
		position = UDim2.fromOffset(0, 58),
		textSize = UITheme.TextSize.Small,
		color = UITheme.Colors.TextDim,
	})
	local layerBar = Bar.new({
		parent = depthPanel,
		size = UDim2.new(1, 0, 0, 6),
		position = UDim2.new(0, 0, 1, 0),
		anchor = Vector2.new(0, 1),
		color = UITheme.Colors.Teal,
	})

	local catchUp = Panel.new({
		parent = hud,
		name = "CatchUp",
		size = UDim2.new(0, 170, 0, 32),
		position = UDim2.fromOffset(12, 120),
		padding = 0,
	})
	local catchStroke = catchUp:FindFirstChildOfClass("UIStroke")
	if catchStroke then
		catchStroke.Color = UITheme.Colors.Teal
	end
	local catchLabel = Label.new({
		parent = catchUp,
		text = "",
		size = UDim2.fromScale(1, 1),
		align = Enum.TextXAlignment.Center,
		textSize = UITheme.TextSize.Small,
		color = UITheme.Colors.Teal,
		display = true,
	})
	catchUp.Visible = false

	-- Timer -----------------------------------------------------------------
	local timerPanel = Panel.new({
		parent = hud,
		name = "Timer",
		size = UDim2.new(0, 200, 0, 56),
		position = UDim2.new(0.5, 0, 0, 12),
		anchor = Vector2.new(0.5, 0),
		padding = 6,
	})
	local phaseLabel = Label.new({
		parent = timerPanel,
		text = PHASE_TEXT.Lobby,
		size = UDim2.new(1, 0, 0, 16),
		align = Enum.TextXAlignment.Center,
		textSize = UITheme.TextSize.Small,
		color = UITheme.Colors.TextDim,
	})
	local timeLabel = Label.new({
		parent = timerPanel,
		text = "0:00",
		size = UDim2.new(1, 0, 0, 28),
		position = UDim2.fromOffset(0, 16),
		align = Enum.TextXAlignment.Center,
		textSize = UITheme.TextSize.Title,
		display = true,
	})

	-- Cash + gems ---------------------------------------------------------------
	local cashPanel = Panel.new({
		parent = hud,
		name = "Cash",
		size = UDim2.new(0.22, 0, 0, 56),
		position = UDim2.new(1, -12, 0, 12),
		anchor = Vector2.new(1, 0),
		padding = 8,
	})
	Base.sizeConstraint(cashPanel, Vector2.new(170, 56), Vector2.new(260, 56))
	Icon.new({ parent = cashPanel, id = AssetIds.Icons.Cash, size = UDim2.fromOffset(28, 28), position = UDim2.new(0, 0, 0.5, 0), anchor = Vector2.new(0, 0.5), color = UITheme.Colors.Amber })
	local cashLabel = Label.new({
		parent = cashPanel,
		name = "Value",
		text = "$0",
		size = UDim2.new(1, -36, 1, 0),
		position = UDim2.fromOffset(36, 0),
		align = Enum.TextXAlignment.Right,
		textSize = UITheme.TextSize.Title,
		display = true,
		color = UITheme.Colors.Amber,
	})
	local gemsPanel = Panel.new({
		parent = hud,
		name = "Gems",
		size = UDim2.new(0.22, 0, 0, 36),
		position = UDim2.new(1, -12, 0, 76),
		anchor = Vector2.new(1, 0),
		padding = 6,
	})
	Base.sizeConstraint(gemsPanel, Vector2.new(170, 36), Vector2.new(260, 36))
	Icon.new({ parent = gemsPanel, id = AssetIds.Icons.Gem, size = UDim2.fromOffset(20, 20), position = UDim2.new(0, 0, 0.5, 0), anchor = Vector2.new(0, 0.5), color = UITheme.Colors.Teal })
	local gemsLabel = Label.new({
		parent = gemsPanel,
		text = "0 gems",
		size = UDim2.new(0.6, 0, 1, 0),
		position = UDim2.fromOffset(26, 0),
		textSize = UITheme.TextSize.Small,
		display = true,
		color = UITheme.Colors.Teal,
	})
	local relicsLabel = Label.new({
		parent = gemsPanel,
		text = "0 relics",
		size = UDim2.new(0.4, 0, 1, 0),
		position = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		align = Enum.TextXAlignment.Right,
		textSize = UITheme.TextSize.Small,
		display = true,
		color = UITheme.Colors.Amber,
	})

	-- Backpack + travel --------------------------------------------------------------
	-- Bottom row budget on a 667 px phone: pack 210 + dig 130 + menu 272 + gaps.
	local menuButtonWidth = if ctx.isTouch then 48 else 58
	local menuWidth = 5 * menuButtonWidth + 4 * UITheme.Gap
	local packPanel = Panel.new({
		parent = hud,
		name = "Backpack",
		size = UDim2.new(0.28, 0, 0, 104),
		position = UDim2.new(0, 12, 1, -12),
		anchor = Vector2.new(0, 1),
	})
	Base.sizeConstraint(packPanel, Vector2.new(210, 104), Vector2.new(320, 104))
	Icon.new({ parent = packPanel, id = AssetIds.Icons.Backpack, size = UDim2.fromOffset(20, 20), color = UITheme.Colors.TextDim })
	local packTitle = Label.new({
		parent = packPanel,
		text = "BACKPACK",
		size = UDim2.new(1, -26, 0, 18),
		position = UDim2.fromOffset(26, 0),
		textSize = UITheme.TextSize.Small,
		color = UITheme.Colors.TextDim,
	})
	local packBar = Bar.new({
		parent = packPanel,
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.fromOffset(0, 22),
		color = UITheme.Colors.Teal,
		label = true,
	})
	local actions = Base.frame(packPanel, "Actions", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1))
	Base.list(actions, Enum.FillDirection.Horizontal, UITheme.Gap)
	local sellButton = Button.new({
		parent = actions,
		text = "Sell",
		icon = AssetIds.Icons.Sell,
		size = UDim2.new(0.46, 0, 1, 0),
		kind = "amber",
		layoutOrder = 1,
		sfx = sfx,
		minSize = Vector2.new(40, 40),
		onClick = function()
			state.send("SellAll")
		end,
	})
	local upButton = Button.new({
		parent = actions,
		text = "Up",
		icon = AssetIds.Icons.Up,
		size = UDim2.new(0.25, 0, 1, 0),
		layoutOrder = 2,
		sfx = sfx,
		minSize = Vector2.new(40, 40),
		onClick = function()
			state.send("Travel", "up")
		end,
	})
	local downButton = Button.new({
		parent = actions,
		text = "Down",
		icon = AssetIds.Icons.Down,
		size = UDim2.new(0.25, 0, 1, 0),
		layoutOrder = 3,
		sfx = sfx,
		minSize = Vector2.new(40, 40),
		onClick = function()
			state.send("Travel", "down")
		end,
	})

	-- Dig control ---------------------------------------------------------------------
	local digButton = Button.new({
		parent = hud,
		name = "DigButton",
		text = "HOLD TO DIG",
		size = UDim2.new(0, 130, 0, 86),
		position = UDim2.new(1, -(menuWidth + 24), 1, -12),
		anchor = Vector2.new(1, 1),
		kind = "primary",
		textSize = UITheme.TextSize.Small,
		sfx = sfx,
	})
	digButton.instance.Visible = ctx.isTouch
	local digProgress = Bar.new({
		parent = digButton.instance,
		size = UDim2.new(1, -16, 0, 8),
		position = UDim2.new(0.5, 0, 1, -8),
		anchor = Vector2.new(0.5, 1),
		color = UITheme.Colors.TextOnAccent,
	})
	digButton.instance.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			ctx.dig.setTouchHeld(true)
		end
	end)
	digButton.instance.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			ctx.dig.setTouchHeld(false)
		end
	end)

	local strip = Bar.new({
		parent = hud,
		name = "DigStrip",
		size = UDim2.new(0, 220, 0, 10),
		position = UDim2.new(0.5, 0, 1, -16),
		anchor = Vector2.new(0.5, 1),
		color = UITheme.Colors.Teal,
	})
	strip.instance.Visible = not ctx.isTouch
	local hint = Label.new({
		parent = hud,
		name = "Hint",
		text = "Hold left mouse to dig",
		size = UDim2.new(0, 260, 0, 18),
		position = UDim2.new(0.5, 0, 1, -30),
		anchor = Vector2.new(0.5, 1),
		align = Enum.TextXAlignment.Center,
		textSize = UITheme.TextSize.Small,
		color = UITheme.Colors.TextDim,
	})
	hint.Visible = not ctx.isTouch

	-- Menu row ---------------------------------------------------------------------------
	local menu = Base.frame(hud, "Menu", UDim2.new(0, menuWidth, 0, 60), UDim2.new(1, -12, 1, -12), Vector2.new(1, 1))
	Base.list(menu, Enum.FillDirection.Horizontal, UITheme.Gap, Enum.HorizontalAlignment.Right)
	local menuButtons: { [string]: Button.Handle } = {}
	local menuDefs: { { name: string, icon: number } } = {
		{ name = "Shop", icon = AssetIds.Icons.Shop },
		{ name = "Book", icon = AssetIds.Icons.Book },
		{ name = "Quests", icon = AssetIds.Icons.Quest },
		{ name = "Gems", icon = AssetIds.Icons.Gem },
		{ name = "More", icon = AssetIds.Icons.Settings },
	}
	for order, def in menuDefs do
		menuButtons[def.name] = Button.new({
			parent = menu,
			name = def.name,
			text = def.name,
			icon = def.icon,
			size = UDim2.new(0, menuButtonWidth, 1, 0),
			textSize = UITheme.TextSize.Small,
			layoutOrder = order,
			sfx = sfx,
			minSize = Vector2.new(menuButtonWidth, UITheme.TapMin),
		})
	end

	-- Wiring ----------------------------------------------------------------------------------
	local function renderDepth(depth: number)
		depthLabel.Text = Format.depth(depth)
		local layer = Layers.layerAt(depth)
		if layerLabel.Text ~= layer.name then
			layerLabel.Text = layer.name
			ctx.juice.punch(depthPanel, 0.06)
		end
		layerBar.setFraction(Layers.progressAt(depth))
	end
	ctx.dig.onDepth:Connect(renderDepth)
	state.onAttr("Depth", function(value)
		if typeof(value) == "number" then
			renderDepth(math.max(value, ctx.dig.localDepth()))
		end
	end)

	local shownCash = 0
	state.onAttr("Cash", function(value)
		if typeof(value) ~= "number" then
			return
		end
		local from = shownCash
		shownCash = value
		if value > from then
			ctx.juice.countUp(from, value, 0.5, function(n)
				cashLabel.Text = `${Format.cash(n)}`
			end)
			ctx.juice.punch(cashPanel, 0.1)
		else
			cashLabel.Text = `${Format.cash(value)}`
		end
	end)
	state.onAttr("Gems", function(value)
		if typeof(value) == "number" then
			gemsLabel.Text = `{Format.cash(value)} gems`
			ctx.juice.punch(gemsPanel, 0.06)
		end
	end)
	state.onAttr("Relics", function(value)
		if typeof(value) == "number" then
			relicsLabel.Text = `{value} relics`
		end
	end)

	local function renderPack()
		local used = state.number("PackUsed", 0)
		local cap = math.max(1, state.number("PackCap", GameConfig.Packs[1].capacity))
		packBar.setFraction(used / cap)
		packBar.setLabel(`{used} / {cap}`)
		packBar.setColor(if used >= cap then UITheme.Colors.Warn else UITheme.Colors.Teal)
		packTitle.Text = string.upper(GameConfig.Packs[math.clamp(state.number("PackTier", 1), 1, #GameConfig.Packs)].name)
	end
	state.onAttr("PackUsed", renderPack)
	state.onAttr("PackCap", renderPack)
	state.onAttr("PackTier", renderPack)

	state.onAttr("CatchUp", function(value)
		-- The leader's value is 0, so the leader never sees this chip.
		local bonus = if typeof(value) == "number" then value else 0
		catchUp.Visible = bonus > 0.005
		catchLabel.Text = `Catch-up +{Format.percent(bonus)} dig speed`
	end)

	ctx.dig.onProgress:Connect(function(progress)
		digProgress.setFraction(progress, false)
		strip.setFraction(progress, false)
	end)

	state.onSellResult:Connect(function(total, count)
		ctx.sfx.play("Sell", { volume = 0.8 })
		ctx.juice.punch(sellButton.instance, 0.15)
		ctx.juice.floatText((Players.LocalPlayer.Character and Players.LocalPlayer.Character:GetPivot().Position or Vector3.zero) + Vector3.new(0, 3, 0), `+${Format.cash(total)} · {count} ore`, UITheme.Colors.Amber)
	end)

	local lastTimer = -1
	RunService.Heartbeat:Connect(function()
		local phase = state.phase()
		local remaining = state.phaseRemaining()
		local whole = math.floor(remaining)
		if whole ~= lastTimer then
			lastTimer = whole
			timeLabel.Text = Format.clock(remaining)
			phaseLabel.Text = PHASE_TEXT[phase] or phase
			timeLabel.TextColor3 = if phase == "Active" and remaining <= 60 then UITheme.Colors.Amber else UITheme.Colors.Text
		end
		local active = phase == "Active"
		local traveling = state.isTraveling()
		local atSurface = state.atSurface()
		local depth = ctx.dig.localDepth()
		sellButton.setEnabled(active and not traveling and state.isNearSellPad() and state.number("PackUsed", 0) > 0)
		upButton.setEnabled(active and not traveling and not atSurface)
		downButton.setEnabled(active and not traveling and atSurface and depth > 0)
		digButton.setEnabled(active and not traveling)
	end)

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local touch = inputType == Enum.UserInputType.Touch
		digButton.instance.Visible = touch
		strip.instance.Visible = not touch
		hint.Visible = not touch
	end)

	return {
		menu = menu,
		setMenuAction = function(name: string, fn: () -> ())
			local button = menuButtons[name]
			if button then
				button.setOnClick(fn)
			end
		end,
	}
end

return HUD
