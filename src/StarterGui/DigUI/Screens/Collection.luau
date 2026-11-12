--!strict
-- Explorer: StarterGui/DigUI/Screens/Collection (ModuleScript)
-- The ore index: one card per ore, "???" until first found, rarity-coloured
-- once discovered, with lifetime count, mutation chips, the mutation odds
-- printed in full and threshold rewards to claim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Base = require(script.Parent.Parent.Components.Base)
local Bar = require(script.Parent.Parent.Components.Bar)
local Button = require(script.Parent.Parent.Components.Button)
local Icon = require(script.Parent.Parent.Components.Icon)
local Label = require(script.Parent.Parent.Components.Label)
local Modal = require(script.Parent.Parent.Components.Modal)
local Panel = require(script.Parent.Parent.Components.Panel)

local Collection = {}

type Card = {
	frame: Frame,
	icon: Frame,
	unknown: TextLabel,
	name: TextLabel,
	rarity: TextLabel,
	count: TextLabel,
	chips: { [string]: Frame },
	claims: { Button.Handle },
}

function Collection.new(ctx: Base.Context): Modal.Handle
	local state = ctx.state
	local sfx = function(name: string)
		ctx.sfx.play(name)
	end
	local modal = Modal.new({ parent = ctx.modals, title = "Ore Index", name = "Collection", maxWidth = 800, maxHeight = 580, sfx = sfx, color = "blue", icon = "Book" })

	local discovered = Label.new({ parent = modal.content, text = "", size = UDim2.new(1, 0, 0, 26), textSize = 21, display = true })
	local discoveryBar = Bar.new({ parent = modal.content, size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 30), swatch = "blue" })
	local odds = {}
	for _, mutation in GameConfig.Mutations do
		if mutation.id ~= "none" then
			table.insert(odds, `{mutation.name} {Format.percent(mutation.chance)} (x{mutation.mult})`)
		end
	end
	Label.new({
		parent = modal.content,
		text = "Mutations can hit any ore: " .. table.concat(odds, "  ·  "),
		size = UDim2.new(1, 0, 0, 20),
		position = UDim2.fromOffset(0, 56),
		textSize = 14,
		color = UITheme.Colors.TextDim,
		scaled = true,
	})

	local grid = Base.frame(modal.content, "Grid", UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 86))
	grid.AutomaticSize = Enum.AutomaticSize.Y
	Base.grid(grid, UDim2.new(0.5, -6, 0, 208), 12)

	local cards: { [string]: Card } = {}
	for order, ore in GameConfig.Ores do
		local card = Panel.new({ parent = grid, style = "card", size = UDim2.new(), padding = 10, layoutOrder = order, name = ore.id })
		local icon = Icon.new({ parent = card, name = `Ore:{ore.id}`, size = UDim2.fromOffset(56, 56) })
		local unknown = Label.new({ parent = icon, text = "?", size = UDim2.fromScale(1, 1), align = Enum.TextXAlignment.Center, textSize = 34, display = true, zIndex = 5 })
		local name = Label.new({ parent = card, text = "", size = UDim2.new(1, -66, 0, 28), position = UDim2.fromOffset(66, 0), textSize = 23, display = true, truncate = true })
		local rarity = Label.new({ parent = card, text = "", size = UDim2.new(1, -66, 0, 18), position = UDim2.fromOffset(66, 30), textSize = 15, display = true })
		local count = Label.new({ parent = card, text = "", size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 62), textSize = 16 })
		Label.new({ parent = card, text = `Sells for ${ore.value}`, size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 82), textSize = 16, display = true, color = UITheme.Colors.Gold })

		local chipRow = Base.frame(card, "Chips", UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 106))
		Base.list(chipRow, Enum.FillDirection.Horizontal, 5)
		local chips: { [string]: Frame } = {}
		for i, mutation in GameConfig.Mutations do
			if mutation.id == "none" then
				continue
			end
			local chip = Base.fill(chipRow, mutation.id, Color3.fromHex("1E1E22"), UDim2.fromOffset(0, 24))
			chip.AutomaticSize = Enum.AutomaticSize.X
			chip.LayoutOrder = i
			Base.round(chip)
			Base.stroke(chip, UITheme.Colors.Ink, 2)
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 8)
			pad.PaddingRight = UDim.new(0, 8)
			pad.Parent = chip
			local text = Label.new({ parent = chip, text = string.upper(mutation.name), size = UDim2.new(0, 0, 1, 0), textSize = 13, display = true })
			text.AutomaticSize = Enum.AutomaticSize.X
			chips[mutation.id] = chip
		end

		local claimRow = Base.frame(card, "Claims", UDim2.new(1, 0, 0, 52), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1))
		Base.list(claimRow, Enum.FillDirection.Horizontal, 6)
		local claims: { Button.Handle } = {}
		for tier, threshold in GameConfig.Collection.Thresholds do
			claims[tier] = Button.new({
				parent = claimRow,
				text = `{threshold}: +{Economy.collectionReward(ore.id, tier)}`,
				icon = "Gem",
				iconSize = 18,
				size = UDim2.new(1 / 3, -4, 1, 0),
				kind = "purple",
				textSize = 14,
				layoutOrder = tier,
				minSize = Vector2.new(40, 44),
				sfx = sfx,
				onClick = function()
					state.send("ClaimCollection", ore.id, tier)
				end,
			})
		end
		cards[ore.id] = { frame = card, icon = icon, unknown = unknown, name = name, rarity = rarity, count = count, chips = chips, claims = claims }
	end

	local function refresh()
		local profile = state.profile
		local collection = if profile then profile.collection else {}
		local claimed = if profile then profile.purchases.claimedCollection else {}
		local found = 0
		for _, ore in GameConfig.Ores do
			local card = cards[ore.id]
			local entry = collection[ore.id]
			local total = if entry then entry.count else 0
			local known = total > 0
			if known then
				found += 1
			end
			local rarity = UITheme.rarity(ore.rarity)
			Panel.setTint(card.frame, if known then rarity.color else nil)
			card.icon.Visible = true
			card.unknown.Visible = not known
			for _, child in card.icon:GetChildren() do
				if child:IsA("Frame") then
					child.BackgroundTransparency = if known then 0 else 0.75
				end
			end
			card.name.Text = if known then string.upper(ore.name) else "???"
			card.rarity.Text = string.upper(rarity.name)
			card.count.Text = if known then `Found {Format.cash(total)}` else "Not found yet — dig deeper!"
			for mutationId, chip in card.chips do
				local has = entry ~= nil and (entry.mutations[mutationId] or 0) > 0
				chip.BackgroundColor3 = if has then Color3.fromHex(Economy.mutationById[mutationId].color) else Color3.fromHex("1E1E22")
			end
			for tier, threshold in GameConfig.Collection.Thresholds do
				local done = claimed[`{ore.id}:{tier}`] == true
				local ready = not done and total >= threshold
				local button = card.claims[tier]
				button.setEnabled(ready)
				button.setKind(if done then "grey" else "purple")
				button.setText(if done then "✓" else `{threshold}: +{Economy.collectionReward(ore.id, tier)}`)
			end
		end
		discovered.Text = `DISCOVERED {found} / {#GameConfig.Ores}`
		discoveryBar.setFraction(found / #GameConfig.Ores)
	end

	state.onProfile:Connect(refresh)
	modal.onOpen:Connect(refresh)
	return modal
end

return Collection
