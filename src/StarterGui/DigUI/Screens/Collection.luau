--!strict
-- Explorer: StarterGui/DigUI/Screens/Collection (ModuleScript)
-- Collection book: one card per ore with lifetime count, mutation chips,
-- threshold rewards, and the mutation odds printed in full.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
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

local Collection = {}

type Card = {
	count: TextLabel,
	chips: { [string]: TextLabel },
	claims: { Button.Handle },
	claimLabels: { TextLabel },
}

function Collection.new(ctx: Base.Context): Modal.Handle
	local state = ctx.state
	local sfx = function(name: string)
		ctx.sfx.play(name)
	end
	local modal = Modal.new({ parent = ctx.modals, title = "Collection", name = "Collection", maxWidth = 760, maxHeight = 560, sfx = sfx })

	local odds = {}
	for _, mutation in GameConfig.Mutations do
		if mutation.id ~= "none" then
			table.insert(odds, `{mutation.name} {Format.percent(mutation.chance)} (×{mutation.mult})`)
		end
	end
	Label.new({
		parent = modal.content,
		text = "Mutation odds on any ore: " .. table.concat(odds, "  ·  "),
		size = UDim2.new(1, 0, 0, 20),
		textSize = UITheme.TextSize.Small,
		color = UITheme.Colors.TextDim,
		layoutOrder = 0,
	})

	local grid = Base.frame(modal.content, "Grid", UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 26))
	grid.AutomaticSize = Enum.AutomaticSize.Y
	Base.grid(grid, UDim2.new(0.5, -UITheme.Gap / 2, 0, 170), UITheme.Gap)

	local cards: { [string]: Card } = {}
	for order, ore in GameConfig.Ores do
		local card = Panel.new({ parent = grid, inset = true, size = UDim2.new(), padding = 10, layoutOrder = order, name = ore.id })
		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.fromOffset(28, 28)
		swatch.BackgroundColor3 = Color3.fromHex(ore.color)
		swatch.BorderSizePixel = 0
		Base.corner(swatch)
		swatch.Parent = card
		local oreIconId = (AssetIds.Icons.Ore :: { [string]: number })[ore.id] or 0
		Icon.new({ parent = swatch, id = oreIconId, size = UDim2.fromScale(1, 1), color = UITheme.Colors.TextOnAccent })
		Label.new({ parent = card, text = ore.name, size = UDim2.new(1, -36, 0, 22), position = UDim2.fromOffset(36, 0), textSize = UITheme.TextSize.Body, display = true })
		local count = Label.new({ parent = card, text = "", size = UDim2.new(1, -36, 0, 16), position = UDim2.fromOffset(36, 20), textSize = UITheme.TextSize.Small, color = UITheme.Colors.TextDim })
		Label.new({ parent = card, text = `Sells for ${ore.value}`, size = UDim2.new(1, 0, 0, 16), position = UDim2.fromOffset(0, 42), textSize = UITheme.TextSize.Small, color = UITheme.Colors.Amber })

		local chipRow = Base.frame(card, "Chips", UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 62))
		Base.list(chipRow, Enum.FillDirection.Horizontal, 4)
		local chips: { [string]: TextLabel } = {}
		for i, mutation in GameConfig.Mutations do
			if mutation.id == "none" then
				continue
			end
			local chip = Label.new({ parent = chipRow, text = mutation.name, size = UDim2.new(0, 72, 1, 0), align = Enum.TextXAlignment.Center, textSize = UITheme.TextSize.Small, display = true, layoutOrder = i })
			chip.BackgroundTransparency = 0
			chip.BackgroundColor3 = UITheme.Colors.Panel
			Base.corner(chip)
			Base.stroke(chip, UITheme.Colors.PanelOutline)
			chips[mutation.id] = chip
		end

		local claimRow = Base.frame(card, "Claims", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1))
		Base.list(claimRow, Enum.FillDirection.Horizontal, 4)
		local claims: { Button.Handle } = {}
		local claimLabels: { TextLabel } = {}
		for tier, threshold in GameConfig.Collection.Thresholds do
			local cell = Base.frame(claimRow, `Tier{tier}`, UDim2.new(1 / 3, -3, 1, 0))
			cell.LayoutOrder = tier
			claimLabels[tier] = Label.new({ parent = cell, text = `{threshold} · +{Economy.collectionReward(ore.id, tier)} gems`, size = UDim2.new(1, 0, 0, 14), align = Enum.TextXAlignment.Center, textSize = 12, color = UITheme.Colors.TextDim })
			claims[tier] = Button.new({
				parent = cell,
				text = "Claim",
				size = UDim2.new(1, 0, 0, 26),
				position = UDim2.fromOffset(0, 14),
				kind = "primary",
				textSize = UITheme.TextSize.Small,
				minSize = Vector2.new(40, 26),
				sfx = sfx,
				onClick = function()
					state.send("ClaimCollection", ore.id, tier)
				end,
			})
		end
		cards[ore.id] = { count = count, chips = chips, claims = claims, claimLabels = claimLabels }
	end

	local function refresh()
		local profile = state.profile
		local collection = if profile then profile.collection else {}
		local claimed = if profile then profile.purchases.claimedCollection else {}
		for oreId, card in cards do
			local entry = collection[oreId]
			local total = if entry then entry.count else 0
			card.count.Text = if total > 0 then `{Format.cash(total)} collected` else "Not found yet"
			for mutationId, chip in card.chips do
				local found = entry ~= nil and (entry.mutations[mutationId] or 0) > 0
				chip.TextColor3 = if found then UITheme.Colors.TextOnAccent else UITheme.Colors.TextDim
				chip.BackgroundColor3 = if found then Color3.fromHex(Economy.mutationById[mutationId].color) else UITheme.Colors.Panel
			end
			for tier, threshold in GameConfig.Collection.Thresholds do
				local key = `{oreId}:{tier}`
				local done = claimed[key] == true
				card.claims[tier].setEnabled(not done and total >= threshold)
				card.claims[tier].setText(if done then "Claimed" else "Claim")
				card.claims[tier].setKind(if done then "secondary" else "primary")
			end
		end
	end

	state.onProfile:Connect(refresh)
	modal.onOpen:Connect(refresh)
	return modal
end

return Collection
