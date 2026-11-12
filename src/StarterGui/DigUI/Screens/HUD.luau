--!strict
-- Explorer: StarterGui/DigUI/Screens/HUD (ModuleScript)
-- The always-on HUD, laid out like the big simulator hits: currency pills and
-- menu tiles down the left edge, round timer top-centre, depth + backpack +
-- one context action bottom-centre, a big DIG button on touch screens, and a
-- hint pill that always says what to do next. Layout units are 1280x720
-- design pixels (see Base.responsiveRoot) and fit a 667x375 phone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Layers = require(ReplicatedStorage.Shared.Layers)
local Quests = require(ReplicatedStorage.Shared.Quests)
local Base = require(script.Parent.Parent.Components.Base)
local Bar = require(script.Parent.Parent.Components.Bar)
local Button = require(script.Parent.Parent.Components.Button)
local Icon = require(script.Parent.Parent.Components.Icon)
local Label = require(script.Parent.Parent.Components.Label)
local Panel = require(script.Parent.Parent.Components.Panel)

local HUD = {}

export type Handle = {
	setMenuAction: (name: string, fn: () -> ()) -> (),
	setModalOpen: (open: boolean) -> (),
}

local PHASE_TEXT: { [string]: string } = {
	Lobby = "NEXT ROUND",
	Countdown = "GET READY",
	Active = "TIME LEFT",
	Results = "NEXT ROUND",
}

-- Layer chip colours (swatch names) by layer id; anything else is "red".
local LAYER_SWATCH: { [string]: string } = {
	topsoil = "orange",
	bedrock = "blue",
	hollows = "purple",
}

local MENU = {
	{ name = "Shop", label = "UPGRADES", icon = "Drill", kind = "green" },
	{ name = "Gems", label = "GEM SHOP", icon = "Gem", kind = "purple" },
	{ name = "Book", label = "BOOK", icon = "Book", kind = "blue" },
	{ name = "Quests", label = "QUESTS", icon = "Quest", kind = "orange" },
	{ name = "More", label = "SETTINGS", icon = "Settings", kind = "grey" },
}

local TUTORIAL_BLOCKS = 6 -- dig hints stop after this many blocks

local function backpackValue(backpack: { [string]: { [string]: number } }): number
	local total = 0
	for oreId, mutations in backpack do
		for mutationId, n in mutations do
			total += Economy.oreValue(oreId, mutationId) * n
		end
	end
	return total
end

function HUD.new(ctx: Base.Context): Handle
	local hud = ctx.hud
	local state = ctx.state
	local player = Players.LocalPlayer
	local sfx = function(name: string)
		ctx.sfx.play(name)
	end

	-- Left column: wallet pills over a 2-wide grid of menu tiles ----------------
	local left = Base.frame(hud, "Left", UDim2.fromOffset(212, 384), UDim2.new(0, 14, 0.5, 6), Vector2.new(0, 0.5))
	local wallet = Base.frame(left, "Wallet", UDim2.fromOffset(212, 146))
	Base.list(wallet, Enum.FillDirection.Vertical, 8)

	local function pill(name: string, iconName: string, order: number, height: number, textSize: number, width: number): (Frame, TextLabel)
		local frame = Base.frame(wallet, name, UDim2.fromOffset(width, height))
		frame.LayoutOrder = order
		local back = Panel.new({
			parent = frame,
			style = "dark",
			size = UDim2.new(1, -height / 2, 1, -10),
			position = UDim2.new(0, height / 2, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			padding = 0,
		})
		Icon.new({ parent = frame, name = iconName, size = UDim2.fromOffset(height, height), position = UDim2.new(0, 0, 0.5, 0), anchor = Vector2.new(0, 0.5), zIndex = 3 })
		local value = Label.new({
			parent = back,
			text = "0",
			size = UDim2.new(1, -(height / 2 + 12), 1, -4),
			position = UDim2.new(0, height / 2 + 4, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			textSize = textSize,
			display = true,
			scaled = true,
		})
		return frame, value
	end
	local cashPill, cashLabel = pill("Cash", "Cash", 1, 54, 32, 212)
	local gemsPill, gemsLabel = pill("Gems", "Gem", 2, 44, 24, 180)
	local relicsPill, relicsLabel = pill("Relics", "Relic", 3, 40, 21, 150)
	cashLabel.TextColor3 = Color3.fromHex("FFE066")

	local menu = Base.frame(left, "Menu", UDim2.fromOffset(150, 228), UDim2.fromOffset(0, 156))
	Base.grid(menu, UDim2.fromOffset(70, 70), 8).HorizontalAlignment = Enum.HorizontalAlignment.Left
	local menuButtons: { [string]: Button.Handle } = {}
	for order, def in MENU do
		menuButtons[def.name] = Button.new({
			parent = menu,
			name = def.name,
			text = def.label,
			icon = def.icon,
			iconSize = 34,
			stack = true,
			textSize = 13,
			kind = def.kind,
			size = UDim2.fromOffset(70, 70),
			layoutOrder = order,
			sfx = sfx,
		})
	end

	-- Timer -------------------------------------------------------------------
	local timer = Base.frame(hud, "Timer", UDim2.fromOffset(196, 70), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
	local timerFace = Base.fill(timer, "Face", Color3.new(1, 1, 1), UDim2.fromScale(1, 1))
	Base.corner(timerFace, 18)
	Base.stroke(timerFace)
	local timerGradient = Base.gradient(timerFace, UITheme.Swatches.blue.top, UITheme.Swatches.blue.bottom)
	Icon.new({ parent = timer, name = "Timer", size = UDim2.fromOffset(38, 38), position = UDim2.new(0, -12, 0.5, 0), anchor = Vector2.new(0, 0.5), zIndex = 3 })
	local phaseLabel = Label.new({ parent = timerFace, text = PHASE_TEXT.Lobby, size = UDim2.new(1, -20, 0, 20), position = UDim2.fromOffset(16, 6), align = Enum.TextXAlignment.Center, textSize = 15, display = true })
	local timeLabel = Label.new({ parent = timerFace, text = "0:00", size = UDim2.new(1, -20, 0, 38), position = UDim2.fromOffset(16, 26), align = Enum.TextXAlignment.Center, textSize = 36, display = true, stroke = 3 })
	local timerScale = Instance.new("UIScale")
	timerScale.Parent = timer

	-- Bottom-centre cluster -----------------------------------------------------
	local bottom = Base.frame(hud, "Bottom", UDim2.fromOffset(420, 196), UDim2.new(0.5, 0, 1, -10), Vector2.new(0.5, 1))

	local depthRow = Base.frame(bottom, "DepthRow", UDim2.new(1, 0, 0, 52), UDim2.fromOffset(0, 0))
	Base.list(depthRow, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local depthLabel = Label.new({ parent = depthRow, text = "0 m", size = UDim2.new(0, 0, 1, 0), textSize = 46, display = true, stroke = 3, layoutOrder = 1 })
	depthLabel.AutomaticSize = Enum.AutomaticSize.X
	local layerChip = Base.fill(depthRow, "Layer", Color3.new(1, 1, 1), UDim2.fromOffset(0, 32))
	layerChip.AutomaticSize = Enum.AutomaticSize.X
	layerChip.LayoutOrder = 2
	Base.round(layerChip)
	Base.stroke(layerChip, UITheme.Colors.Ink, 2.5)
	local layerGradient = Base.gradient(layerChip, UITheme.Swatches.orange.top, UITheme.Swatches.orange.bottom)
	local chipPad = Instance.new("UIPadding")
	chipPad.PaddingLeft = UDim.new(0, 12)
	chipPad.PaddingRight = UDim.new(0, 12)
	chipPad.Parent = layerChip
	local layerLabel = Label.new({ parent = layerChip, text = "TOPSOIL", size = UDim2.new(0, 0, 1, 0), textSize = 17, display = true })
	layerLabel.AutomaticSize = Enum.AutomaticSize.X

	local catchChip = Base.fill(bottom, "CatchUp", Color3.new(1, 1, 1), UDim2.fromOffset(0, 26), UDim2.new(0.5, 0, 0, -30), Vector2.new(0.5, 0))
	catchChip.AutomaticSize = Enum.AutomaticSize.X
	catchChip.Visible = false
	Base.round(catchChip)
	Base.stroke(catchChip, UITheme.Colors.Ink, 2)
	Base.gradient(catchChip, UITheme.Swatches.green.top, UITheme.Swatches.green.bottom)
	local catchPad = Instance.new("UIPadding")
	catchPad.PaddingLeft = UDim.new(0, 10)
	catchPad.PaddingRight = UDim.new(0, 10)
	catchPad.Parent = catchChip
	local catchLabel = Label.new({ parent = catchChip, text = "", size = UDim2.new(0, 0, 1, 0), textSize = 15, display = true })
	catchLabel.AutomaticSize = Enum.AutomaticSize.X

	local packRow = Base.frame(bottom, "Backpack", UDim2.new(1, -40, 0, 40), UDim2.new(0.5, 10, 0, 58), Vector2.new(0.5, 0))
	local packBar = Bar.new({ parent = packRow, size = UDim2.new(1, -20, 0, 30), position = UDim2.new(1, 0, 0.5, 0), anchor = Vector2.new(1, 0.5), swatch = "gold", label = true, textSize = 18 })
	Icon.new({ parent = packRow, name = "Backpack", size = UDim2.fromOffset(46, 46), position = UDim2.new(0, -10, 0.5, 0), anchor = Vector2.new(0, 0.5), zIndex = 4 })
	local packScale = Instance.new("UIScale")
	packScale.Parent = packRow

	local actions = Base.frame(bottom, "Actions", UDim2.new(1, 0, 0, 72), UDim2.new(0.5, 0, 1, 0), Vector2.new(0.5, 1))
	Base.list(actions, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)

	local upButton = Button.new({ parent = actions, name = "Surface", text = "SURFACE", icon = "Up", kind = "blue", size = UDim2.fromOffset(236, 66), textSize = 26, layoutOrder = 1, sfx = sfx, onClick = function()
		state.send("Travel", "up")
	end })
	local sellButton = Button.new({ parent = actions, name = "Sell", text = "SELL", icon = "Sell", kind = "gold", size = UDim2.fromOffset(200, 66), textSize = 26, layoutOrder = 2, sfx = sfx, onClick = function()
		state.send("SellAll")
	end })
	local downButton = Button.new({ parent = actions, name = "Down", text = "DIG DOWN", icon = "Down", kind = "orange", size = UDim2.fromOffset(236, 66), textSize = 26, layoutOrder = 3, sfx = sfx, onClick = function()
		state.send("Travel", "down")
	end })
	local rideButton = Button.new({ parent = actions, name = "Ride", text = "ELEVATOR", icon = "Elevator", kind = "dark", size = UDim2.fromOffset(250, 66), textSize = 24, layoutOrder = 4 })
	rideButton.setEnabled(false)
	local upPulse = Instance.new("UIScale")
	upPulse.Parent = upButton.face

	-- Hint pill -------------------------------------------------------------------
	local hint = Base.fill(hud, "Hint", UITheme.Colors.Shade, UDim2.fromOffset(0, 42), UDim2.new(0.5, 0, 1, -222), Vector2.new(0.5, 1))
	hint.BackgroundTransparency = 0.25
	hint.AutomaticSize = Enum.AutomaticSize.X
	Base.round(hint)
	Base.stroke(hint, UITheme.Colors.Ink, 2.5)
	local hintPad = Instance.new("UIPadding")
	hintPad.PaddingLeft = UDim.new(0, 18)
	hintPad.PaddingRight = UDim.new(0, 18)
	hintPad.Parent = hint
	local hintLabel = Label.new({ parent = hint, text = "", size = UDim2.new(0, 0, 1, 0), textSize = 21, display = true, rich = true })
	hintLabel.AutomaticSize = Enum.AutomaticSize.X
	hint.Visible = false

	-- Dig progress (centre-screen, under the character) ------------------------------
	local digBarHolder = Base.frame(hud, "DigProgress", UDim2.fromOffset(240, 34), UDim2.fromScale(0.5, 0.64), Vector2.new(0.5, 0.5))
	local digBar = Bar.new({ parent = digBarHolder, size = UDim2.new(1, -24, 0, 22), position = UDim2.new(1, 0, 0.5, 0), anchor = Vector2.new(1, 0.5), swatch = "orange" })
	Icon.new({ parent = digBarHolder, name = "Pickaxe", size = UDim2.fromOffset(36, 36), position = UDim2.new(0, -6, 0.5, 0), anchor = Vector2.new(0, 0.5), zIndex = 4 })
	digBarHolder.Visible = false

	-- Touch DIG button (left of Roblox's jump button) ------------------------------
	local digButton = Instance.new("TextButton")
	digButton.Name = "DigButton"
	digButton.AutoButtonColor = false
	digButton.Text = ""
	digButton.BackgroundColor3 = Color3.new(1, 1, 1)
	digButton.Size = UDim2.fromOffset(112, 112)
	digButton.Position = UDim2.new(1, -178, 1, -26)
	digButton.AnchorPoint = Vector2.new(1, 1)
	digButton.ClipsDescendants = false
	Base.round(digButton)
	Base.stroke(digButton, UITheme.Colors.Ink, 4)
	Base.gradient(digButton, UITheme.Swatches.orange.top, UITheme.Swatches.orange.bottom)
	digButton.Parent = hud
	local digFillClip = Base.frame(digButton, "Clip", UDim2.fromScale(1, 1))
	digFillClip.ClipsDescendants = true
	Base.round(digFillClip)
	local digFill = Base.fill(digFillClip, "Fill", Color3.fromHex("FFF3B0"), UDim2.fromScale(1, 0), UDim2.fromScale(0, 1), Vector2.new(0, 1))
	digFill.BackgroundTransparency = 0.35
	Icon.new({ parent = digButton, name = "Pickaxe", size = UDim2.fromOffset(46, 46), position = UDim2.new(0.5, 0, 0.42, 0), anchor = Vector2.new(0.5, 0.5), zIndex = 3 })
	Label.new({ parent = digButton, text = "DIG", size = UDim2.new(1, 0, 0, 30), position = UDim2.new(0.5, 0, 1, -14), anchor = Vector2.new(0.5, 1), align = Enum.TextXAlignment.Center, textSize = 28, display = true, stroke = 3, zIndex = 3 })
	local digScale = Instance.new("UIScale")
	digScale.Parent = digButton

	-- Touch dig is held by one specific touch; it ends when *that* touch ends
	-- anywhere on screen, so sliding a finger off can never latch digging on.
	local digTouch: InputObject? = nil
	local function releaseDig()
		digTouch = nil
		ctx.dig.setTouchHeld(false)
		TweenService:Create(digScale, UITheme.Easing.Settle, { Scale = 1 }):Play()
	end
	digButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			digTouch = input
			ctx.dig.setTouchHeld(true)
			TweenService:Create(digScale, UITheme.Easing.Settle, { Scale = 0.92 }):Play()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == digTouch or (digTouch ~= nil and input.UserInputType == Enum.UserInputType.MouseButton1 and digTouch.UserInputType == Enum.UserInputType.MouseButton1) then
			releaseDig()
		end
	end)

	local touchMode = ctx.isTouch
	local function setTouchMode(touch: boolean)
		touchMode = touch
		if not touch and digTouch then
			releaseDig()
		end
	end
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		if inputType == Enum.UserInputType.Touch then
			setTouchMode(true)
		elseif inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Keyboard then
			setTouchMode(false)
		end
	end)

	-- Wiring --------------------------------------------------------------------
	local currentLayerId = ""
	local function renderDepth(depth: number)
		depthLabel.Text = Format.depth(depth)
		local layer = if depth >= GameConfig.CoreDepth then nil else Layers.layerAt(depth)
		local id = if layer then layer.id else "core"
		if id ~= currentLayerId then
			currentLayerId = id
			layerLabel.Text = if layer then string.upper(layer.name) else "THE CORE"
			local swatch = UITheme.swatch(LAYER_SWATCH[id] or "red")
			layerGradient.Color = ColorSequence.new(swatch.top, swatch.bottom)
			ctx.juice.punch(layerChip, 0.25)
		end
	end
	ctx.dig.onDepth:Connect(renderDepth)
	state.onAttr("Depth", function(value)
		if typeof(value) == "number" then
			renderDepth(math.max(value, ctx.dig.localDepth()))
		end
	end)

	-- Coins fly from the middle of the screen into the cash pill on a sale.
	local function coinBurst(count: number)
		local target = cashPill.AbsolutePosition + Vector2.new(27, 27) - hud.AbsolutePosition
		local root = hud.AbsoluteSize
		for i = 1, count do
			local coin = Icon.new({
				parent = hud,
				name = "Coin",
				size = UDim2.fromOffset(34, 34),
				position = UDim2.new(0.5, math.random(-90, 90), 0.55, math.random(-50, 50)),
				anchor = Vector2.new(0.5, 0.5),
				zIndex = 20,
			})
			local goal = UDim2.fromScale(target.X / math.max(1, root.X), target.Y / math.max(1, root.Y))
			task.delay(0.03 * i, function()
				local tween = TweenService:Create(coin, TweenInfo.new(0.55 + math.random() * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = goal, Size = UDim2.fromOffset(22, 22) })
				tween:Play()
				tween.Completed:Connect(function()
					coin:Destroy()
					ctx.juice.punch(cashPill, 0.08)
				end)
			end)
		end
	end

	local function floatOver(anchorFrame: GuiObject, text: string, color: Color3)
		-- AbsolutePosition is in screen pixels; HUD offsets are design units.
		local uiScale = hud:FindFirstChildOfClass("UIScale")
		local k = if uiScale then uiScale.Scale else 1
		local at = (anchorFrame.AbsolutePosition - hud.AbsolutePosition) / k
		local start = UDim2.fromOffset(at.X + anchorFrame.AbsoluteSize.X / k + 8, at.Y)
		local label = Label.new({
			parent = hud,
			text = text,
			size = UDim2.fromOffset(240, 44),
			position = start,
			textSize = 34,
			display = true,
			color = color,
			stroke = 3,
			zIndex = 21,
		})
		local rise = TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = start - UDim2.fromOffset(0, 46),
			TextTransparency = 1,
		})
		rise:Play()
		rise.Completed:Connect(function()
			label:Destroy()
		end)
	end

	local shownCash = 0
	state.onAttr("Cash", function(value)
		if typeof(value) ~= "number" then
			return
		end
		local from = shownCash
		shownCash = value
		if value > from then
			ctx.juice.countUp(from, value, 0.6, function(n)
				cashLabel.Text = `${Format.cash(n)}`
			end)
			ctx.juice.punch(cashPill, 0.12)
		else
			cashLabel.Text = `${Format.cash(value)}`
		end
	end)
	local shownGems = -1
	state.onAttr("Gems", function(value)
		if typeof(value) == "number" then
			gemsLabel.Text = Format.cash(value)
			if shownGems >= 0 and value > shownGems then
				ctx.juice.punch(gemsPill, 0.15)
				floatOver(gemsPill, `+{Format.cash(value - shownGems)}`, UITheme.Colors.Cyan)
			end
			shownGems = value
		end
	end)
	state.onAttr("Relics", function(value)
		if typeof(value) == "number" then
			relicsLabel.Text = tostring(value)
			ctx.juice.punch(relicsPill, 0.1)
		end
	end)

	local packFull = false
	local function renderPack()
		local used = state.number("PackUsed", 0)
		local cap = math.max(1, state.number("PackCap", GameConfig.Packs[1].capacity))
		packFull = used >= cap
		packBar.setFraction(used / cap)
		packBar.setLabel(if packFull then `FULL!  {used} / {cap}` else `{used} / {cap}`)
		packBar.setSwatch(if packFull then "red" elseif used / cap > 0.75 then "orange" else "gold")
	end
	state.onAttr("PackUsed", function()
		local before = packFull
		renderPack()
		if packFull and not before then
			ctx.juice.punch(packRow, 0.2)
			ctx.sfx.play("ButtonDenied", { volume = 0.5 })
		end
	end)
	state.onAttr("PackCap", renderPack)
	state.onAttr("PackTier", renderPack)

	state.onAttr("CatchUp", function(value)
		-- The leader's value is 0, so the leader never sees this chip.
		local bonus = if typeof(value) == "number" then value else 0
		catchChip.Visible = bonus > 0.005
		catchLabel.Text = `🚀 CATCH-UP +{Format.percent(bonus)} SPEED`
	end)

	local digging = false
	ctx.dig.onProgress:Connect(function(progress)
		digBar.setFraction(progress, false)
		digFill.Size = UDim2.fromScale(1, progress)
		digging = progress > 0
	end)

	state.onSellResult:Connect(function(total, count)
		ctx.sfx.play("Sell", { volume = 0.8 })
		coinBurst(math.clamp(count, 4, 12))
		floatOver(cashPill, `+${Format.cash(total)}`, UITheme.Colors.Gold)
	end)

	-- Badges and nudges -------------------------------------------------------------
	local function affordableUpgrade(): boolean
		if state.phase() ~= "Active" then
			return false
		end
		local cash = state.number("Cash", 0)
		local drillCost = Economy.upgradeCost("drill", state.number("DrillTier", 1))
		local packCost = Economy.upgradeCost("pack", state.number("PackTier", 1))
		return (drillCost ~= nil and cash >= drillCost) or (packCost ~= nil and cash >= packCost)
	end
	local function claimableQuests(): number
		local quests = state.quests
		local n = 0
		for _, quest in Quests.dailySet(if quests.day > 0 then quests.day else Quests.dayNumber()) do
			if not quests.claimed[quest.id] and (quests.progress[quest.id] or 0) >= quest.goal then
				n += 1
			end
		end
		return n
	end
	local function claimableBook(): number
		local profile = state.profile
		if not profile then
			return 0
		end
		local n = 0
		for _, ore in GameConfig.Ores do
			local entry = profile.collection[ore.id]
			local count = if entry then entry.count else 0
			for tier, threshold in GameConfig.Collection.Thresholds do
				if count >= threshold and not profile.purchases.claimedCollection[`{ore.id}:{tier}`] then
					n += 1
				end
			end
		end
		return n
	end
	local function refreshBadges()
		local q = claimableQuests()
		menuButtons.Quests.setBadge(if q > 0 then tostring(q) else nil)
		local b = claimableBook()
		menuButtons.Book.setBadge(if b > 0 then tostring(b) else nil)
		menuButtons.Shop.setBadge(if affordableUpgrade() then "!" else nil)
		local gems = state.number("Gems", 0)
		menuButtons.Gems.setBadge(if gems >= GameConfig.Pets.EggCost then "!" else nil)
	end
	state.onQuests:Connect(refreshBadges)
	state.onProfile:Connect(refreshBadges)
	for _, name in { "Cash", "DrillTier", "PackTier", "Gems" } do
		state.onAttr(name, refreshBadges)
	end
	state.onRound("Phase", refreshBadges)

	-- Per-frame: timer, context action, hint ---------------------------------------
	local modalOpen = false
	local dugThisRound = 0
	ctx.dig.onDepth:Connect(function(depth)
		if depth > 0 then
			dugThisRound += 1
		end
	end)
	state.onRound("Phase", function(phase)
		if phase == "Active" then
			dugThisRound = 0
		end
	end)

	local function setHint(text: string)
		if text == "" then
			hint.Visible = false
			return
		end
		if hintLabel.Text ~= text or not hint.Visible then
			hintLabel.Text = text
			hint.Visible = true
			ctx.juice.punch(hint, 0.12)
		end
	end

	local lastTimer = -1
	local pulseClock = 0
	local nextSlow = 0
	RunService.Heartbeat:Connect(function(dt)
		pulseClock += dt
		local phase = state.phase()
		local remaining = state.phaseRemaining()
		local whole = math.floor(remaining)
		if whole ~= lastTimer then
			lastTimer = whole
			timeLabel.Text = Format.clock(remaining)
			phaseLabel.Text = PHASE_TEXT[phase] or string.upper(phase)
			local urgent = phase == "Active" and remaining <= 60
			local swatch = UITheme.swatch(if urgent then "red" elseif phase == "Active" then "blue" else "purple")
			timerGradient.Color = ColorSequence.new(swatch.top, swatch.bottom)
			if urgent and whole <= 10 then
				ctx.juice.punch(timer, 0.12)
			end
		end

		local active = phase == "Active"
		local traveling = state.isTraveling()
		local atSurface = state.atSurface()
		local depth = ctx.dig.localDepth()
		local packUsed = state.number("PackUsed", 0)
		local reachedCore = player:GetAttribute("ReachedCore") == true

		-- One obvious action at a time, like the simulator hits.
		local showUp = active and not traveling and not atSurface and not reachedCore
		local showSell = active and not traveling and atSurface and packUsed > 0
		local showDown = active and not traveling and atSurface and depth > 0 and packUsed == 0 and not reachedCore
		upButton.instance.Visible = showUp
		sellButton.instance.Visible = showSell
		downButton.instance.Visible = showDown
		rideButton.instance.Visible = traveling
		if traveling then
			local dir = player:GetAttribute("Traveling")
			rideButton.setText(`{if dir == "up" then "GOING UP" else "GOING DOWN"}  {math.ceil(state.travelRemaining())}s`)
		end
		if showUp then
			local value = backpackValue(state.backpack)
			upButton.setText(if packUsed > 0 then `SELL  ${Format.cash(value)}` else "SURFACE")
			upButton.setKind(if packUsed > 0 then "gold" else "blue")
			upPulse.Scale = if packFull then 1 + math.abs(math.sin(pulseClock * 5)) * 0.08 else 1
		end
		if showSell then
			sellButton.setEnabled(state.isNearSellPad())
		end
		if showDown then
			downButton.setText(`DIG  {Format.depth(depth)}`)
		end
		packScale.Scale = if packFull then 1 + math.abs(math.sin(pulseClock * 5)) * 0.05 else 1

		digButton.Visible = touchMode and not modalOpen
		digBarHolder.Visible = digging and not touchMode

		if os.clock() < nextSlow then
			return
		end
		nextSlow = os.clock() + 0.2
		local digHow = if touchMode then "Hold <font color=\"#FFB347\">DIG</font>" else "Hold <font color=\"#FFB347\">LEFT CLICK</font>"
		local text = ""
		if phase == "Lobby" then
			text = "⏳ Next race starts soon — get ready to dig!"
		elseif phase == "Countdown" or phase == "Results" then
			text = ""
		elseif reachedCore then
			text = "🏆 You reached the core!"
		elseif traveling then
			text = ""
		elseif atSurface then
			if packUsed > 0 then
				text = if state.isNearSellPad() then "💰 Press <font color=\"#FFE066\">SELL</font>!" else "💰 Walk onto your <font color=\"#FFE066\">SELL</font> pad"
			elseif affordableUpgrade() then
				text = "⛏️ You can afford an upgrade — open <font color=\"#8CF58C\">UPGRADES</font>!"
			elseif depth > 0 then
				text = "⬇️ Press <font color=\"#FFC766\">DIG</font> to ride back down"
			else
				text = `⬇️ Walk into your hole and {digHow} to dig!`
			end
		elseif packFull then
			text = "🎒 Backpack full! Press <font color=\"#FFE066\">SELL</font> to ride up"
		elseif dugThisRound < TUTORIAL_BLOCKS then
			text = `⛏️ {digHow} to dig down!`
		end
		setHint(if modalOpen then "" else text)

		-- Pulse the upgrades tile while there's something to buy and the player
		-- is at the surface (where they'd shop).
		local shopFace = menuButtons.Shop.face
		local shopScale = shopFace:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		shopScale.Parent = shopFace
		shopScale.Scale = if atSurface and affordableUpgrade() then 1.06 else 1
	end)

	return {
		setMenuAction = function(name: string, fn: () -> ())
			local button = menuButtons[name]
			if button then
				button.setOnClick(fn)
			end
		end,
		setModalOpen = function(open: boolean)
			modalOpen = open
			if open and digTouch then
				releaseDig()
			end
		end,
	}
end

return HUD
