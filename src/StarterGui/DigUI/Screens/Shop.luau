--!strict
-- Explorer: StarterGui/DigUI/Screens/Shop (ModuleScript)
-- Round-layer shop: drill and pack tiers bought with this round's cash.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Base = require(script.Parent.Parent.Components.Base)
local Button = require(script.Parent.Parent.Components.Button)
local Label = require(script.Parent.Parent.Components.Label)
local Modal = require(script.Parent.Parent.Components.Modal)
local Panel = require(script.Parent.Parent.Components.Panel)

local Shop = {}

type Card = {
	current: TextLabel,
	stat: TextLabel,
	nextName: TextLabel,
	nextStat: TextLabel,
	cost: TextLabel,
	buy: Button.Handle,
}

function Shop.new(ctx: Base.Context): Modal.Handle
	local state = ctx.state
	local sfx = function(name: string)
		ctx.sfx.play(name)
	end
	local modal = Modal.new({ parent = ctx.modals, title = "Upgrades", name = "Shop", maxWidth = 640, maxHeight = 420, sfx = sfx })

	local cashLine = Label.new({
		parent = modal.content,
		text = "",
		size = UDim2.new(1, 0, 0, 24),
		textSize = UITheme.TextSize.Body,
		color = UITheme.Colors.Amber,
		display = true,
		layoutOrder = 0,
	})
	local row = Base.frame(modal.content, "Cards", UDim2.new(1, 0, 0, 250), UDim2.fromOffset(0, 30))
	Base.list(row, Enum.FillDirection.Horizontal, UITheme.Gap)

	local function makeCard(kind: "drill" | "pack", title: string, icon: number): Card
		local card = Panel.new({ parent = row, inset = true, size = UDim2.new(0.5, -UITheme.Gap / 2, 1, 0), padding = 12, layoutOrder = if kind == "drill" then 1 else 2 })
		Label.new({ parent = card, text = title, size = UDim2.new(1, 0, 0, 24), textSize = UITheme.TextSize.Title, display = true })
		local current = Label.new({ parent = card, text = "", size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 30), textSize = UITheme.TextSize.Body })
		local stat = Label.new({ parent = card, text = "", size = UDim2.new(1, 0, 0, 18), position = UDim2.fromOffset(0, 50), textSize = UITheme.TextSize.Small, color = UITheme.Colors.TextDim })
		Label.new({ parent = card, text = "NEXT", size = UDim2.new(1, 0, 0, 16), position = UDim2.fromOffset(0, 84), textSize = UITheme.TextSize.Small, color = UITheme.Colors.TextDim })
		local nextName = Label.new({ parent = card, text = "", size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 100), textSize = UITheme.TextSize.Body, color = UITheme.Colors.Teal })
		local nextStat = Label.new({ parent = card, text = "", size = UDim2.new(1, 0, 0, 18), position = UDim2.fromOffset(0, 120), textSize = UITheme.TextSize.Small, color = UITheme.Colors.TextDim })
		local cost = Label.new({ parent = card, text = "", size = UDim2.new(1, 0, 0, 22), position = UDim2.fromOffset(0, 146), textSize = UITheme.TextSize.Body, display = true, color = UITheme.Colors.Amber })
		local buy = Button.new({
			parent = card,
			text = "Buy",
			icon = icon,
			size = UDim2.new(1, 0, 0, 48),
			position = UDim2.new(0, 0, 1, 0),
			anchor = Vector2.new(0, 1),
			kind = "primary",
			sfx = sfx,
			onClick = function()
				state.send("BuyUpgrade", kind)
			end,
		})
		return { current = current, stat = stat, nextName = nextName, nextStat = nextStat, cost = cost, buy = buy }
	end

	local drillCard = makeCard("drill", "Drill", AssetIds.Icons.Drill)
	local packCard = makeCard("pack", "Backpack", AssetIds.Icons.Backpack)

	local function refresh()
		local cash = state.number("Cash", 0)
		cashLine.Text = `Cash ${Format.cash(cash)}`

		local drillTier = math.clamp(state.number("DrillTier", 1), 1, #GameConfig.Drills)
		local drill = GameConfig.Drills[drillTier]
		drillCard.current.Text = `{drill.name}  ·  tier {drillTier}/{#GameConfig.Drills}`
		drillCard.stat.Text = `Power {drill.power}`
		local nextDrill = GameConfig.Drills[drillTier + 1]
		local drillCost = Economy.upgradeCost("drill", drillTier)
		if nextDrill and drillCost then
			drillCard.nextName.Text = nextDrill.name
			drillCard.nextStat.Text = `Power {nextDrill.power}  (+{Format.percent(nextDrill.power / drill.power - 1)})`
			drillCard.cost.Text = `${Format.cash(drillCost)}`
			drillCard.cost.TextColor3 = if cash >= drillCost then UITheme.Colors.Amber else UITheme.Colors.Warn
			drillCard.buy.setEnabled(cash >= drillCost and state.phase() == "Active")
			drillCard.buy.setText("Buy")
		else
			drillCard.nextName.Text = "Fully upgraded"
			drillCard.nextStat.Text = ""
			drillCard.cost.Text = ""
			drillCard.buy.setEnabled(false)
			drillCard.buy.setText("Maxed")
		end

		local packTier = math.clamp(state.number("PackTier", 1), 1, #GameConfig.Packs)
		local pack = GameConfig.Packs[packTier]
		packCard.current.Text = `{pack.name}  ·  tier {packTier}/{#GameConfig.Packs}`
		packCard.stat.Text = `Holds {state.number("PackCap", pack.capacity)} ore`
		local nextPack = GameConfig.Packs[packTier + 1]
		local packCost = Economy.upgradeCost("pack", packTier)
		if nextPack and packCost then
			packCard.nextName.Text = nextPack.name
			packCard.nextStat.Text = `Holds {nextPack.capacity + (state.number("PackCap", pack.capacity) - pack.capacity)} ore`
			packCard.cost.Text = `${Format.cash(packCost)}`
			packCard.cost.TextColor3 = if cash >= packCost then UITheme.Colors.Amber else UITheme.Colors.Warn
			packCard.buy.setEnabled(cash >= packCost and state.phase() == "Active")
			packCard.buy.setText("Buy")
		else
			packCard.nextName.Text = "Fully upgraded"
			packCard.nextStat.Text = ""
			packCard.cost.Text = ""
			packCard.buy.setEnabled(false)
			packCard.buy.setText("Maxed")
		end
	end

	for _, name in { "Cash", "DrillTier", "PackTier", "PackCap" } do
		state.onAttr(name, refresh)
	end
	state.onRound("Phase", refresh)
	modal.onOpen:Connect(refresh)
	state.onNotify:Connect(function(kind)
		if kind == "buy" then
			ctx.sfx.play("UpgradeBuy", { volume = 0.7 })
		end
	end)

	return modal
end

return Shop
