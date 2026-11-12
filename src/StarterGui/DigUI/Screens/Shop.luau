--!strict
-- Explorer: StarterGui/DigUI/Screens/Shop (ModuleScript)
-- Round upgrades bought with this round's cash: drill power and backpack
-- size. One big card each with tier pips, the next tier's gain and a single
-- buy button that says exactly what's missing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Base = require(script.Parent.Parent.Components.Base)
local Button = require(script.Parent.Parent.Components.Button)
local Icon = require(script.Parent.Parent.Components.Icon)
local Label = require(script.Parent.Parent.Components.Label)
local Modal = require(script.Parent.Parent.Components.Modal)
local Panel = require(script.Parent.Parent.Components.Panel)

local Shop = {}

type Card = {
	frame: Frame,
	current: TextLabel,
	pips: { Frame },
	nextName: TextLabel,
	stat: TextLabel,
	buy: Button.Handle,
}

local GAIN = "#C6F75C"

function Shop.new(ctx: Base.Context): Modal.Handle
	local state = ctx.state
	local sfx = function(name: string)
		ctx.sfx.play(name)
	end
	local modal = Modal.new({ parent = ctx.modals, title = "Upgrades", name = "Shop", maxWidth = 700, maxHeight = 470, sfx = sfx, color = "green", icon = "Drill" })

	local topRow = Base.frame(modal.content, "Top", UDim2.new(1, 0, 0, 40))
	Icon.new({ parent = topRow, name = "Cash", size = UDim2.fromOffset(36, 36), position = UDim2.new(0, 0, 0.5, 0), anchor = Vector2.new(0, 0.5) })
	local cashLine = Label.new({ parent = topRow, text = "$0", size = UDim2.new(0.5, -44, 1, 0), position = UDim2.fromOffset(44, 0), textSize = 28, display = true, color = UITheme.Colors.Gold })
	Label.new({ parent = topRow, text = "Upgrades reset every round", size = UDim2.new(0.5, 0, 1, 0), position = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0), align = Enum.TextXAlignment.Right, textSize = 16, color = UITheme.Colors.TextDim })

	local row = Base.frame(modal.content, "Cards", UDim2.new(1, 0, 0, 316), UDim2.fromOffset(0, 50))
	Base.list(row, Enum.FillDirection.Horizontal, 14)

	local function makeCard(kind: "drill" | "pack", title: string, icon: string, swatchName: string, tiers: number): Card
		local card = Panel.new({ parent = row, style = "card", size = UDim2.new(0.5, -7, 1, 0), padding = 14, layoutOrder = if kind == "drill" then 1 else 2 })
		local swatch = UITheme.swatch(swatchName)
		local plate = Base.fill(card, "IconPlate", Color3.new(1, 1, 1), UDim2.fromOffset(70, 70))
		Base.corner(plate, 16)
		Base.stroke(plate, UITheme.Colors.Ink, 3)
		Base.gradient(plate, swatch.top, swatch.bottom)
		Icon.new({ parent = plate, name = icon, size = UDim2.fromOffset(48, 48), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5) })
		Label.new({ parent = card, text = title, size = UDim2.new(1, -84, 0, 32), position = UDim2.fromOffset(84, 2), textSize = 28, display = true })
		local current = Label.new({ parent = card, text = "", size = UDim2.new(1, -84, 0, 24), position = UDim2.fromOffset(84, 38), textSize = 18, color = UITheme.Colors.TextDim, truncate = true })

		local pipRow = Base.frame(card, "Pips", UDim2.new(1, 0, 0, 18), UDim2.fromOffset(0, 84))
		Base.list(pipRow, Enum.FillDirection.Horizontal, 6)
		local pips: { Frame } = {}
		for i = 1, tiers do
			local pip = Base.fill(pipRow, `Pip{i}`, Color3.new(1, 1, 1), UDim2.fromOffset(18, 18))
			pip.LayoutOrder = i
			Base.round(pip)
			Base.stroke(pip, UITheme.Colors.Ink, 2.5)
			pips[i] = pip
		end

		local nextName = Label.new({ parent = card, text = "", size = UDim2.new(1, 0, 0, 26), position = UDim2.fromOffset(0, 116), textSize = 21, display = true, color = UITheme.Colors.Gold, truncate = true })
		local stat = Label.new({ parent = card, text = "", size = UDim2.new(1, 0, 0, 30), position = UDim2.fromOffset(0, 146), textSize = 24, display = true, rich = true })
		local buy = Button.new({
			parent = card,
			text = "BUY",
			icon = "Cash",
			size = UDim2.new(1, 0, 0, 64),
			position = UDim2.new(0, 0, 1, 0),
			anchor = Vector2.new(0, 1),
			kind = "green",
			textSize = 24,
			sfx = sfx,
			onClick = function()
				state.send("BuyUpgrade", kind)
			end,
		})
		return { frame = card, current = current, pips = pips, nextName = nextName, stat = stat, buy = buy }
	end

	local drillCard = makeCard("drill", "DRILL", "Drill", "orange", #GameConfig.Drills)
	local packCard = makeCard("pack", "BACKPACK", "Backpack", "blue", #GameConfig.Packs)

	local function paintPips(card: Card, tier: number, swatchName: string)
		local swatch = UITheme.swatch(swatchName)
		for i, pip in card.pips do
			pip.BackgroundColor3 = if i <= tier then swatch.bottom else Color3.fromHex("1E1E22")
		end
	end

	local function setBuy(card: Card, cost: number?, cash: number)
		if not cost then
			card.buy.setText("MAXED")
			card.buy.setEnabled(false)
			return
		end
		if state.phase() ~= "Active" then
			card.buy.setText("WAIT FOR ROUND")
			card.buy.setEnabled(false)
		elseif cash < cost then
			card.buy.setText(`NEED ${Format.cash(cost - cash)} MORE`)
			card.buy.setEnabled(false)
		else
			card.buy.setText(`BUY  ${Format.cash(cost)}`)
			card.buy.setEnabled(true)
		end
	end

	local function refresh()
		local cash = state.number("Cash", 0)
		cashLine.Text = `${Format.cash(cash)}`

		local drillTier = math.clamp(state.number("DrillTier", 1), 1, #GameConfig.Drills)
		local drill = GameConfig.Drills[drillTier]
		drillCard.current.Text = `{drill.name} · power {drill.power}`
		paintPips(drillCard, drillTier, "orange")
		local nextDrill = GameConfig.Drills[drillTier + 1]
		if nextDrill then
			drillCard.nextName.Text = `NEXT: {string.upper(nextDrill.name)}`
			drillCard.stat.Text = `⚡ {drill.power} → <font color="{GAIN}">{nextDrill.power}</font>  <font color="{GAIN}">+{Format.percent(nextDrill.power / drill.power - 1)}</font>`
		else
			drillCard.nextName.Text = "FULLY UPGRADED!"
			drillCard.stat.Text = `⚡ {drill.power}`
		end
		setBuy(drillCard, Economy.upgradeCost("drill", drillTier), cash)

		local packTier = math.clamp(state.number("PackTier", 1), 1, #GameConfig.Packs)
		local pack = GameConfig.Packs[packTier]
		local cap = state.number("PackCap", pack.capacity)
		local bonus = cap - pack.capacity -- permanent pack perk slots
		packCard.current.Text = `{pack.name} · holds {cap}`
		paintPips(packCard, packTier, "blue")
		local nextPack = GameConfig.Packs[packTier + 1]
		if nextPack then
			packCard.nextName.Text = `NEXT: {string.upper(nextPack.name)}`
			packCard.stat.Text = `🎒 {cap} → <font color="{GAIN}">{nextPack.capacity + bonus}</font> ore`
		else
			packCard.nextName.Text = "FULLY UPGRADED!"
			packCard.stat.Text = `🎒 {cap} ore`
		end
		setBuy(packCard, Economy.upgradeCost("pack", packTier), cash)
	end

	for _, name in { "Cash", "DrillTier", "PackTier", "PackCap" } do
		state.onAttr(name, refresh)
	end
	state.onRound("Phase", refresh)
	modal.onOpen:Connect(refresh)
	local lastDrill = state.number("DrillTier", 1)
	local lastPack = state.number("PackTier", 1)
	state.onNotify:Connect(function(kind)
		if kind ~= "buy" then
			return
		end
		ctx.sfx.play("UpgradeBuy", { volume = 0.7 })
		local drillTier = state.number("DrillTier", 1)
		local packTier = state.number("PackTier", 1)
		if drillTier > lastDrill then
			ctx.juice.punch(drillCard.frame, 0.08)
		end
		if packTier > lastPack then
			ctx.juice.punch(packCard.frame, 0.08)
		end
		lastDrill, lastPack = drillTier, packTier
	end)
	state.onRound("Phase", function()
		lastDrill = state.number("DrillTier", 1)
		lastPack = state.number("PackTier", 1)
	end)

	return modal
end

return Shop
