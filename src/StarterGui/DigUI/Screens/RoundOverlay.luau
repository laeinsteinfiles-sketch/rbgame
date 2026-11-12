--!strict
-- Explorer: StarterGui/DigUI/Screens/RoundOverlay (ModuleScript)
-- Big moments, drawn over everything: the countdown, the Mega Drill banner
-- with its shared goal, layer title cards, rare-find and new-ore banners,
-- the core celebration, and the podium results sheet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Layers = require(ReplicatedStorage.Shared.Layers)
local Types = require(ReplicatedStorage.Shared.Types)
local Base = require(script.Parent.Parent.Components.Base)
local Bar = require(script.Parent.Parent.Components.Bar)
local Icon = require(script.Parent.Parent.Components.Icon)
local Label = require(script.Parent.Parent.Components.Label)
local Panel = require(script.Parent.Parent.Components.Panel)

local RoundOverlay = {}

local BOUNCE = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local LAYER_SWATCH: { [string]: string } = {
	topsoil = "orange",
	bedrock = "blue",
	hollows = "purple",
}

local MEDALS = { "Medal1", "Medal2", "Medal3" }

--- Big outlined title text with a vertical gradient fill.
local function heroText(parent: Instance, name: string, size: number, top: Color3, bottom: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = UITheme.Font.Display
	label.TextSize = size
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Size = UDim2.fromOffset(900, size + 12)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Text = ""
	Base.gradient(label, top, bottom)
	Base.textStroke(label, math.max(3, math.floor(size / 18)))
	label.Parent = parent
	return label
end

--- A centred card that pops in, holds, and fades: used for layer and rare banners.
local function makeBanner(parent: Instance, name: string, y: number): (CanvasGroup, TextLabel, TextLabel, UIGradient, UIScale)
	local group = Instance.new("CanvasGroup")
	group.Name = name
	group.BackgroundColor3 = Color3.new(1, 1, 1)
	group.BorderSizePixel = 0
	group.Size = UDim2.fromOffset(460, 92)
	group.Position = UDim2.new(0.5, 0, 0, y)
	group.AnchorPoint = Vector2.new(0.5, 0)
	group.GroupTransparency = 1
	group.Visible = false
	Base.corner(group, 20)
	Base.stroke(group, UITheme.Colors.Ink, 4)
	local gradient = Base.gradient(group, UITheme.Swatches.orange.top, UITheme.Swatches.orange.bottom)
	local title = Label.new({ parent = group, text = "", size = UDim2.new(1, -20, 0, 46), position = UDim2.fromOffset(10, 8), align = Enum.TextXAlignment.Center, textSize = 40, display = true, stroke = 3, scaled = true })
	local sub = Label.new({ parent = group, text = "", size = UDim2.new(1, -20, 0, 26), position = UDim2.fromOffset(10, 56), align = Enum.TextXAlignment.Center, textSize = 22, display = true, scaled = true })
	local scale = Instance.new("UIScale")
	scale.Parent = group
	group.Parent = parent
	return group, title, sub, gradient, scale
end

function RoundOverlay.new(ctx: Base.Context)
	local state = ctx.state
	local overlay = ctx.overlay
	local me = Players.LocalPlayer

	-- Countdown -------------------------------------------------------------------
	local countdown = heroText(overlay, "Countdown", 150, Color3.fromHex("FFF27A"), Color3.fromHex("FF9A2E"))
	countdown.Position = UDim2.fromScale(0.5, 0.38)
	countdown.Visible = false
	local countScale = Instance.new("UIScale")
	countScale.Parent = countdown

	local lastShown = -1
	local holdUntil = 0 -- keeps the "DIG!" splash up briefly after the phase flips
	RunService.Heartbeat:Connect(function()
		local phase = state.phase()
		if phase ~= "Countdown" then
			lastShown = -1
			if countdown.Visible and os.clock() > holdUntil then
				countdown.Visible = false
			end
			return
		end
		local remaining = math.ceil(state.phaseRemaining())
		if remaining ~= lastShown and remaining > 0 then
			lastShown = remaining
			countdown.Visible = true
			countdown.Text = tostring(remaining)
			countdown.Rotation = if remaining % 2 == 0 then -6 else 6
			countScale.Scale = 2.2
			TweenService:Create(countScale, BOUNCE, { Scale = 1 }):Play()
			ctx.sfx.play("Countdown", { pitch = 1 + (5 - remaining) * 0.05 })
		end
	end)
	state.onRound("Phase", function(phase)
		if phase == "Active" then
			countdown.Text = "DIG!"
			countdown.Rotation = 0
			countdown.Visible = true
			holdUntil = os.clock() + 1.1
			countScale.Scale = 2.4
			TweenService:Create(countScale, BOUNCE, { Scale = 1.1 }):Play()
			ctx.sfx.play("RoundStart")
		end
	end)

	-- Mega Drill banner --------------------------------------------------------------
	local mega = Base.fill(overlay, "MegaBanner", Color3.new(1, 1, 1), UDim2.fromOffset(380, 92), UDim2.new(0.5, 0, 0, -120), Vector2.new(0.5, 0))
	Base.corner(mega, 18)
	Base.stroke(mega, UITheme.Colors.Ink, 3.5)
	Base.gradient(mega, Color3.fromHex("FFE66E"), Color3.fromHex("FF7A1F"))
	Icon.new({ parent = mega, name = "Mega", size = UDim2.fromOffset(44, 44), position = UDim2.new(0, -14, 0, -12), zIndex = 3 })
	local megaTitle = Label.new({ parent = mega, text = "MEGA DRILL  x1.5", size = UDim2.new(1, -90, 0, 30), position = UDim2.fromOffset(22, 6), textSize = 26, display = true, stroke = 3 })
	local megaTime = Label.new({ parent = mega, text = "1:00", size = UDim2.new(0, 70, 0, 30), position = UDim2.new(1, -12, 0, 6), anchor = Vector2.new(1, 0), align = Enum.TextXAlignment.Right, textSize = 26, display = true, stroke = 3 })
	local goalBar = Bar.new({ parent = mega, size = UDim2.new(1, -24, 0, 22), position = UDim2.fromOffset(12, 40), swatch = "green", label = true, textSize = 14 })
	Label.new({ parent = mega, text = `SHARED GOAL · +{GameConfig.Round.MegaDrill.GemBonus} 💎 FOR EVERYONE`, size = UDim2.new(1, -24, 0, 18), position = UDim2.fromOffset(12, 66), align = Enum.TextXAlignment.Center, textSize = 14, display = true })

	local SHOWN = UDim2.new(0.5, 0, 0, 88)
	local HIDDEN = UDim2.new(0.5, 0, 0, -120)
	local function setMega(visible: boolean)
		TweenService:Create(mega, if visible then BOUNCE else FADE, { Position = if visible then SHOWN else HIDDEN }):Play()
	end
	state.onRound("MegaActive", function(active)
		setMega(active == true)
	end)
	state.onRound("MegaProgress", function(progress)
		local goal = math.max(1, tonumber(state.round("MegaGoal")) or 1)
		local p = if typeof(progress) == "number" then progress else 0
		goalBar.setFraction(p / goal)
		goalBar.setLabel(`{math.floor(p)} / {goal} BLOCKS`)
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
			megaTitle.Text = "MEGA DRILL  x1.5"
		elseif kind == "goal" then
			ctx.sfx.play("MegaGoal", { volume = 0.9 })
			megaTitle.Text = "GOAL REACHED!"
			ctx.juice.punch(mega, 0.15)
			task.delay(1.8, function()
				setMega(false)
			end)
		else
			ctx.sfx.play("MegaEnd")
		end
	end)

	-- Banners: layer title card and rare finds ------------------------------------------
	local layerCard, layerTitle, layerSub, layerGradient, layerScale = makeBanner(overlay, "LayerCard", 150)
	local rareCard, rareTitle, rareSub, rareGradient, rareScale = makeBanner(overlay, "RareCard", 250)
	local function flash(group: CanvasGroup, scale: UIScale, hold: number)
		group.Visible = true
		group.GroupTransparency = 0
		scale.Scale = 0.4
		TweenService:Create(scale, BOUNCE, { Scale = 1 }):Play()
		local token = os.clock()
		group:SetAttribute("Token", token)
		task.delay(hold, function()
			if group:GetAttribute("Token") ~= token then
				return
			end
			local out = TweenService:Create(group, FADE, { GroupTransparency = 1 })
			out:Play()
			out.Completed:Connect(function()
				if group:GetAttribute("Token") == token then
					group.Visible = false
				end
			end)
		end)
	end

	local function showLayer(depth: number)
		local layer = Layers.layerAt(depth)
		local swatch = UITheme.swatch(LAYER_SWATCH[layer.id] or "red")
		layerGradient.Color = ColorSequence.new(swatch.top, swatch.bottom)
		layerTitle.Text = string.upper(layer.name)
		layerSub.Text = `LAYER {Layers.indexAt(depth)} · {Format.depth(layer.startDepth)} DEEP · ROCK GETS HARDER`
		flash(layerCard, layerScale, 2.4)
	end
	state.onNotify:Connect(function(kind, message)
		if kind == "layer" then
			for _, layer in GameConfig.Layers do
				if layer.name == message then
					showLayer(layer.startDepth)
				end
			end
		end
	end)

	local seenOre: { [string]: boolean } = {}
	state.onDigResult:Connect(function(_index: number, accepted: boolean, roll: Types.BlockRoll?, _depth: number, kept: boolean)
		if not accepted or not roll then
			return
		end
		if roll.relic then
			rareGradient.Color = ColorSequence.new(UITheme.Swatches.gold.top, UITheme.Swatches.gold.bottom)
			rareTitle.Text = "🏺 RELIC FOUND! 🏺"
			rareSub.Text = "SPEND RELICS ON DRILL SKINS"
			flash(rareCard, rareScale, 2.2)
			return
		end
		local oreId = roll.oreId
		if not oreId then
			return
		end
		local ore = Economy.oreById[oreId]
		local mutation = Economy.mutationById[roll.mutationId or "none"]
		if not ore then
			return
		end
		local profile = state.profile
		local isNew = not seenOre[oreId] and (profile == nil or profile.collection[oreId] == nil)
		seenOre[oreId] = true
		local mutated = mutation ~= nil and mutation.id ~= "none"
		if not (isNew or mutated or ore.rarity >= 3) then
			return
		end
		local rarity = UITheme.rarity(ore.rarity + (if mutated then 1 else 0))
		local swatch = UITheme.swatch(rarity.swatch)
		rareGradient.Color = ColorSequence.new(swatch.top, swatch.bottom)
		local name = if mutated and mutation then `{string.upper(mutation.name)} {string.upper(ore.name)}` else string.upper(ore.name)
		rareTitle.Text = if isNew then `✨ NEW: {name}! ✨` else `✨ {name}! ✨`
		local value = `${Format.cash(Economy.oreValue(oreId, roll.mutationId))}`
		rareSub.Text = if kept
			then `{string.upper(rarity.name)} · WORTH {value}{if mutated and mutation then ` (x{mutation.mult})` else ""}`
			else "BACKPACK FULL — LEFT BEHIND!"
		flash(rareCard, rareScale, 2)
		if ore.rarity >= 3 or mutated then
			ctx.fx.shake(0.15, 0.25)
		end
	end)

	-- Core celebration --------------------------------------------------------------------
	local coreFlash = Base.fill(overlay, "CoreFlash", Color3.fromHex("FFE9A8"), UDim2.fromScale(1, 1))
	coreFlash.BackgroundTransparency = 1
	coreFlash.Visible = false
	local coreText = heroText(overlay, "CoreText", 88, Color3.fromHex("FFF7B0"), Color3.fromHex("FF8A1F"))
	coreText.Position = UDim2.fromScale(0.5, 0.32)
	coreText.Visible = false
	local coreScale = Instance.new("UIScale")
	coreScale.Parent = coreText
	local celebrated = false

	local function confetti()
		local colors = { UITheme.Colors.Gold, UITheme.Colors.Pink, UITheme.Colors.Cyan, UITheme.Colors.Green, UITheme.Colors.Orange, UITheme.Colors.Purple }
		for _ = 1, 70 do
			local piece = Base.fill(overlay, "Confetti", colors[math.random(1, #colors)], UDim2.fromOffset(math.random(8, 14), math.random(14, 22)), UDim2.new(math.random(), 0, 0, -30))
			piece.Rotation = math.random(0, 360)
			piece.ZIndex = 30
			local fall = TweenService:Create(piece, TweenInfo.new(2.2 + math.random() * 1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.1, 0),
				Rotation = piece.Rotation + math.random(-540, 540),
			})
			task.delay(math.random() * 0.8, function()
				fall:Play()
			end)
			fall.Completed:Connect(function()
				piece:Destroy()
			end)
		end
	end

	local function celebrateCore()
		if celebrated then
			return
		end
		celebrated = true
		coreFlash.Visible = true
		coreFlash.BackgroundTransparency = 0.1
		TweenService:Create(coreFlash, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		coreText.Text = "YOU REACHED THE CORE!"
		coreText.Visible = true
		coreScale.Scale = 0.3
		TweenService:Create(coreScale, BOUNCE, { Scale = 1 }):Play()
		confetti()
		ctx.sfx.play("Win", { volume = 0.9 })
		task.delay(4, function()
			coreText.Visible = false
			coreFlash.Visible = false
		end)
	end
	ctx.dig.onDepth:Connect(function(depth)
		if depth >= GameConfig.CoreDepth then
			celebrateCore()
		end
	end)
	state.onRound("Phase", function(phase)
		if phase == "Lobby" then
			celebrated = false
		end
	end)

	-- Results sheet ------------------------------------------------------------------------
	local sheet = Panel.new({
		parent = overlay,
		name = "Results",
		size = UDim2.fromScale(0.86, 0.82),
		position = UDim2.fromScale(0.5, 0.53),
		anchor = Vector2.new(0.5, 0.5),
		padding = 16,
	})
	Base.sizeConstraint(sheet, Vector2.new(320, 300), Vector2.new(600, 520))
	sheet.Visible = false
	local sheetScale = Instance.new("UIScale")
	sheetScale.Parent = sheet

	local ribbon = Base.fill(sheet, "Ribbon", Color3.new(1, 1, 1), UDim2.new(1, -40, 0, 58), UDim2.new(0.5, 0, 0, -46), Vector2.new(0.5, 0))
	Base.corner(ribbon, 16)
	Base.stroke(ribbon)
	Base.gradient(ribbon, UITheme.Swatches.gold.top, UITheme.Swatches.gold.bottom)
	Label.new({ parent = ribbon, text = "🏆 ROUND OVER 🏆", size = UDim2.fromScale(1, 1), align = Enum.TextXAlignment.Center, textSize = 32, display = true, stroke = 3 })

	local winnerFace = Instance.new("ImageLabel")
	winnerFace.Name = "WinnerFace"
	winnerFace.BackgroundColor3 = Color3.fromHex("FFF3C4")
	winnerFace.Size = UDim2.fromOffset(92, 92)
	winnerFace.Position = UDim2.new(0.5, 0, 0, 22)
	winnerFace.AnchorPoint = Vector2.new(0.5, 0)
	Base.round(winnerFace)
	Base.stroke(winnerFace, UITheme.Colors.Gold, 4)
	winnerFace.Parent = sheet
	local crown = Instance.new("TextLabel")
	crown.BackgroundTransparency = 1
	crown.Size = UDim2.fromOffset(40, 40)
	crown.Position = UDim2.new(0.5, 0, 0, 0)
	crown.AnchorPoint = Vector2.new(0.5, 0.5)
	crown.Text = "👑"
	crown.TextScaled = true
	crown.Rotation = -12
	crown.Parent = winnerFace

	local headline = Label.new({ parent = sheet, text = "", size = UDim2.new(1, 0, 0, 38), position = UDim2.fromOffset(0, 118), align = Enum.TextXAlignment.Center, textSize = 34, display = true, color = UITheme.Colors.Gold, stroke = 3, truncate = true })
	local subline = Label.new({ parent = sheet, text = "", size = UDim2.new(1, 0, 0, 22), position = UDim2.fromOffset(0, 156), align = Enum.TextXAlignment.Center, textSize = 18, color = UITheme.Colors.TextDark })

	local rowsFrame = Base.frame(sheet, "Rows", UDim2.new(1, 0, 1, -270), UDim2.fromOffset(0, 186))
	Base.list(rowsFrame, Enum.FillDirection.Vertical, 6)
	local rowLabels: { { frame: Frame, medal: Frame, face: ImageLabel, name: TextLabel, depth: TextLabel } } = {}
	for i = 1, 4 do
		local row = Panel.new({ parent = rowsFrame, style = "card", size = UDim2.new(1, 0, 0, 40), padding = 0, layoutOrder = i })
		local medal = Icon.new({ parent = row, name = MEDALS[i] or "Star", size = UDim2.fromOffset(30, 30), position = UDim2.new(0, 8, 0.5, 0), anchor = Vector2.new(0, 0.5) })
		local face = Instance.new("ImageLabel")
		face.BackgroundColor3 = Color3.fromHex("DCE7FF")
		face.Size = UDim2.fromOffset(30, 30)
		face.Position = UDim2.new(0, 44, 0.5, 0)
		face.AnchorPoint = Vector2.new(0, 0.5)
		Base.round(face)
		face.Parent = row
		local name = Label.new({ parent = row, text = "", size = UDim2.new(1, -170, 1, 0), position = UDim2.fromOffset(82, 0), textSize = 19, color = UITheme.Colors.TextDark, truncate = true })
		local depth = Label.new({ parent = row, text = "", size = UDim2.new(0, 80, 1, 0), position = UDim2.new(1, -10, 0, 0), anchor = Vector2.new(1, 0), align = Enum.TextXAlignment.Right, textSize = 20, display = true, color = UITheme.Colors.TextDark })
		row.Visible = false
		rowLabels[i] = { frame = row, medal = medal, face = face, name = name, depth = depth }
	end

	local yourLine = Label.new({ parent = sheet, text = "", size = UDim2.new(1, 0, 0, 34), position = UDim2.new(0, 0, 1, -66), align = Enum.TextXAlignment.Center, textSize = 28, display = true, color = UITheme.Colors.Green, stroke = 3 })
	local nextLine = Label.new({ parent = sheet, text = "", size = UDim2.new(1, 0, 0, 22), position = UDim2.new(0, 0, 1, -24), align = Enum.TextXAlignment.Center, textSize = 18, color = UITheme.Colors.TextDim })

	state.onRoundResults:Connect(function(standings: { Types.Standing }, placement: number, gems: number)
		local winner = standings[1]
		local byCore = state.round("WinnerByCore") == true
		winnerFace.Visible = winner ~= nil
		if winner then
			winnerFace.Image = Base.headshot(winner.userId)
			headline.Text = `{winner.name} WINS!`
			subline.Text = if byCore then "Reached the core first!" else `Deepest when time ran out · {Format.depth(winner.depth)}`
		else
			headline.Text = "NOBODY DUG!"
			subline.Text = "Grab a drill next round"
		end
		for i, row in rowLabels do
			local s = standings[i]
			row.frame.Visible = s ~= nil
			if s then
				row.face.Image = Base.headshot(s.userId)
				row.name.Text = s.name
				row.depth.Text = Format.depth(s.depth)
				local mine = s.userId == me.UserId
				Label.setColor(row.name, if mine then Color3.fromHex("1B8434") else UITheme.Colors.TextDark)
			end
		end
		if placement > 0 then
			yourLine.Text = `YOU FINISHED #{placement}  ·  +0 💎`
			Label.setColor(yourLine, if placement == 1 then UITheme.Colors.Gold else UITheme.Colors.Green)
			ctx.juice.countUp(0, gems, 1.2, function(n)
				yourLine.Text = `YOU FINISHED #{placement}  ·  +{math.floor(n + 0.5)} 💎`
			end)
		else
			yourLine.Text = "DIG NEXT ROUND TO EARN 💎"
			Label.setColor(yourLine, UITheme.Colors.Orange)
		end
		sheet.Visible = true
		sheetScale.Scale = 0.5
		TweenService:Create(sheetScale, BOUNCE, { Scale = 1 }):Play()
		ctx.sfx.play(if placement == 1 then "Win" else "RoundEnd")
		if placement == 1 then
			confetti()
		end
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
