--!strict
-- Explorer: StarterGui/DigUI/Screens/MetaShop (ModuleScript)
-- The persistent layer in one place: capped perks, the pet egg (odds shown
-- next to the button), owned pets, relic skins and gamepasses. Nothing here
-- is pay-to-win; the copy says so where it matters.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
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

local MetaShop = {}

local PASS_COPY = {
	{ key = "DoubleGems", title = "2x Gems", body = "Doubles gem rewards. Never touches the race." },
	{ key = "AutoDig", title = "Auto-dig", body = "Keeps digging without holding. Same speed as manual." },
	{ key = "BigPack", title = "Bigger starting pack", body = "Start each round with the Rucksack." },
	{ key = "DrillSkins", title = "All drill skins", body = "Unlocks every skin. Cosmetic only." },
}

local function section(parent: Instance, title: string, order: number, height: number): GuiObject
	local panel = Panel.new({ parent = parent, inset = true, size = UDim2.new(1, 0, 0, height), padding = 12, layoutOrder = order })
	Label.new({ parent = panel, text = title, size = UDim2.new(1, 0, 0, 24), textSize = UITheme.TextSize.Title, display = true })
	return panel
end

-- A wrapping row of 92x60 cards that grows the section with it.
local function cardGrid(parent: GuiObject): Frame
	parent.AutomaticSize = Enum.AutomaticSize.Y
	local row = Base.frame(parent, "Row", UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 30))
	row.AutomaticSize = Enum.AutomaticSize.Y
	Base.grid(row, UDim2.fromOffset(92, 60), 6)
	return row
end

function MetaShop.new(ctx: Base.Context): Modal.Handle
	local state = ctx.state
	local sfx = function(name: string)
		ctx.sfx.play(name)
	end
	local modal = Modal.new({ parent = ctx.modals, title = "Gems & relics", name = "MetaShop", maxWidth = 680, maxHeight = 560, sfx = sfx })
	local list = modal.content
	Base.list(list, Enum.FillDirection.Vertical, UITheme.Gap)

	local wallet = Label.new({ parent = list, text = "", size = UDim2.new(1, 0, 0, 22), textSize = UITheme.TextSize.Body, display = true, color = UITheme.Colors.Teal, layoutOrder = 0 })

	-- Perks --------------------------------------------------------------------------
	local perks = section(list, "Perks (capped)", 1, 150)
	Label.new({ parent = perks, text = "Small, permanent, and capped so a round is still won by digging.", size = UDim2.new(1, 0, 0, 16), position = UDim2.fromOffset(0, 24), textSize = UITheme.TextSize.Small, color = UITheme.Colors.TextDim })
	local perkRow = Base.frame(perks, "Row", UDim2.new(1, 0, 0, 92), UDim2.fromOffset(0, 46))
	Base.list(perkRow, Enum.FillDirection.Horizontal, UITheme.Gap)
	local function perkCard(kind: "digSpeed" | "pack", title: string, order: number)
		local card = Base.frame(perkRow, kind, UDim2.new(0.5, -UITheme.Gap / 2, 1, 0))
		card.LayoutOrder = order
		local name = Label.new({ parent = card, text = title, size = UDim2.new(1, 0, 0, 20), textSize = UITheme.TextSize.Body, display = true })
		local detail = Label.new({ parent = card, text = "", size = UDim2.new(1, 0, 0, 16), position = UDim2.fromOffset(0, 20), textSize = UITheme.TextSize.Small, color = UITheme.Colors.TextDim })
		local buy = Button.new({
			parent = card,
			text = "",
			size = UDim2.new(1, 0, 0, 44),
			position = UDim2.new(0, 0, 1, 0),
			anchor = Vector2.new(0, 1),
			kind = "primary",
			sfx = sfx,
			onClick = function()
				state.send("BuyMeta", kind)
			end,
		})
		return { name = name, detail = detail, buy = buy }
	end
	local digPerk = perkCard("digSpeed", "Drill tuning", 1)
	local packPerk = perkCard("pack", "Pack frame", 2)

	-- Egg --------------------------------------------------------------------------------
	local egg = section(list, "Pet egg", 2, 150)
	local oddsParts = {}
	for _, entry in GameConfig.Pets.Odds do
		table.insert(oddsParts, `{entry.tier} {entry.chance}%`)
	end
	Label.new({ parent = egg, text = "Odds: " .. table.concat(oddsParts, "  ·  "), size = UDim2.new(1, 0, 0, 16), position = UDim2.fromOffset(0, 24), textSize = UITheme.TextSize.Small, color = UITheme.Colors.TextDim })
	Label.new({ parent = egg, text = `Pets follow you and add up to +15% gems. Duplicates refund {math.floor(GameConfig.Pets.EggCost / 3)} gems.`, size = UDim2.new(1, 0, 0, 16), position = UDim2.fromOffset(0, 40), textSize = UITheme.TextSize.Small, color = UITheme.Colors.TextDim })
	local eggResult = Label.new({ parent = egg, text = "", size = UDim2.new(1, -170, 0, 44), position = UDim2.new(0, 0, 1, 0), anchor = Vector2.new(0, 1), textSize = UITheme.TextSize.Body, display = true, color = UITheme.Colors.Amber })
	local eggButton = Button.new({
		parent = egg,
		text = `Open · {GameConfig.Pets.EggCost} gems`,
		icon = AssetIds.Icons.Egg,
		size = UDim2.new(0, 160, 0, 48),
		position = UDim2.new(1, 0, 1, 0),
		anchor = Vector2.new(1, 1),
		kind = "amber",
		sfx = sfx,
		onClick = function()
			state.send("OpenEgg")
		end,
	})

	-- Pets owned ---------------------------------------------------------------------------
	local petsPanel = section(list, "Your pets", 3, 100)
	local petRow = cardGrid(petsPanel)
	local petButtons: { [string]: Button.Handle } = {}
	for order, pet in GameConfig.Pets.List do
		petButtons[pet.id] = Button.new({
			parent = petRow,
			text = pet.name,
			size = UDim2.new(0, 92, 0, 60),
			textSize = 12,
			layoutOrder = order,
			sfx = sfx,
			onClick = function()
				local profile = state.profile
				local equipped = if profile then profile.purchases.equippedPet else ""
				state.send("Equip", "pet", if equipped == pet.id then "" else pet.id)
			end,
		})
	end

	-- Skins ----------------------------------------------------------------------------------
	local skinsPanel = section(list, "Drill skins (relics)", 4, 100)
	local skinRow = cardGrid(skinsPanel)
	local skinButtons: { [string]: Button.Handle } = {}
	for order, skin in GameConfig.Skins do
		skinButtons[skin.id] = Button.new({
			parent = skinRow,
			text = skin.name,
			size = UDim2.new(0, 92, 0, 60),
			textSize = 12,
			layoutOrder = order,
			sfx = sfx,
		})
	end

	-- Gamepasses ---------------------------------------------------------------------------
	local passPanel = section(list, "Gamepasses", 5, 40 + #PASS_COPY * 56)
	local passList = Base.frame(passPanel, "List", UDim2.new(1, 0, 1, -30), UDim2.fromOffset(0, 30))
	Base.list(passList, Enum.FillDirection.Vertical, 6)
	local passButtons: { [string]: Button.Handle } = {}
	for order, pass in PASS_COPY do
		local row = Base.frame(passList, pass.key, UDim2.new(1, 0, 0, 50))
		row.LayoutOrder = order
		Label.new({ parent = row, text = pass.title, size = UDim2.new(1, -130, 0, 22), textSize = UITheme.TextSize.Body, display = true })
		Label.new({ parent = row, text = pass.body, size = UDim2.new(1, -130, 0, 16), position = UDim2.fromOffset(0, 22), textSize = UITheme.TextSize.Small, color = UITheme.Colors.TextDim, truncate = true })
		local id = (AssetIds.Gamepasses :: { [string]: number })[pass.key] or 0
		passButtons[pass.key] = Button.new({
			parent = row,
			text = if AssetIds.isSet(id) then "Buy" else "Soon",
			size = UDim2.new(0, 120, 0, 44),
			position = UDim2.new(1, 0, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			kind = "amber",
			sfx = sfx,
			onClick = function()
				if AssetIds.isSet(id) then
					MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, id)
				end
			end,
		})
	end

	-- Refresh ------------------------------------------------------------------------------------
	local function refresh()
		local profile = state.profile
		local gems = state.number("Gems", 0)
		local relics = state.number("Relics", 0)
		wallet.Text = `{Format.cash(gems)} gems  ·  {relics} relics`

		local digLvl = state.number("MetaDig", 0)
		local digCost = Economy.metaCost("digSpeed", digLvl)
		digPerk.detail.Text = `Level {digLvl}/{GameConfig.Meta.DigSpeed.maxLevel}  ·  +{Format.percent(digLvl * GameConfig.Meta.DigSpeed.perLevel)} dig speed`
		digPerk.buy.setText(if digCost then `Upgrade · {digCost} gems` else "Maxed")
		digPerk.buy.setEnabled(digCost ~= nil and gems >= digCost)

		local packLvl = state.number("MetaPack", 0)
		local packCost = Economy.metaCost("pack", packLvl)
		packPerk.detail.Text = `Level {packLvl}/{GameConfig.Meta.Pack.maxLevel}  ·  +{packLvl * GameConfig.Meta.Pack.perLevel} pack slots`
		packPerk.buy.setText(if packCost then `Upgrade · {packCost} gems` else "Maxed")
		packPerk.buy.setEnabled(packCost ~= nil and gems >= packCost)

		eggButton.setEnabled(gems >= GameConfig.Pets.EggCost)

		local owned = if profile then profile.purchases.pets else {}
		local equippedPet = if profile then profile.purchases.equippedPet else ""
		for _, pet in GameConfig.Pets.List do
			local button = petButtons[pet.id]
			local has = (owned[pet.id] or 0) > 0
			button.setEnabled(has)
			button.setKind(if equippedPet == pet.id then "primary" else "secondary")
			button.setText(if has then pet.name else `{pet.name}\n{pet.tier}`)
		end

		local skins = if profile then profile.purchases.skins else {}
		local equippedSkin = if profile then profile.purchases.equippedSkin else "default"
		local allSkins = state.ownsPass("DrillSkins")
		for _, skin in GameConfig.Skins do
			local button = skinButtons[skin.id]
			local has = skins[skin.id] == true or allSkins
			if has then
				button.setText(skin.name)
				button.setKind(if equippedSkin == skin.id then "primary" else "secondary")
				button.setEnabled(true)
				button.setOnClick(function()
					state.send("Equip", "skin", skin.id)
				end)
			else
				button.setText(`{skin.name}\n{skin.relics} relics`)
				button.setKind("ghost")
				button.setEnabled(relics >= skin.relics)
				button.setOnClick(function()
					state.send("BuyMeta", "skin", skin.id)
				end)
			end
		end

		for _, pass in PASS_COPY do
			local button = passButtons[pass.key]
			if state.ownsPass(pass.key) then
				button.setText("Owned")
				button.setEnabled(false)
			end
		end
	end

	for _, name in { "Gems", "Relics", "MetaDig", "MetaPack", "Passes" } do
		state.onAttr(name, refresh)
	end
	state.onProfile:Connect(refresh)
	modal.onOpen:Connect(refresh)
	state.onEggResult:Connect(function(petId, duplicate)
		local pet
		for _, def in GameConfig.Pets.List do
			if def.id == petId then
				pet = def
			end
		end
		eggResult.Text = if pet then `{pet.name} ({pet.tier}){if duplicate then " · duplicate" else ""}` else ""
		ctx.sfx.play("EggCrack", { volume = 0.7 })
		ctx.juice.punch(eggResult, 0.2)
		modal.open()
	end)

	return modal
end

return MetaShop
