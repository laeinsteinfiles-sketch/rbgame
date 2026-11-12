--!strict
-- Explorer: StarterGui/DigUI/Screens/MetaShop (ModuleScript)
-- The gem shop, i.e. everything that persists between rounds: the pet egg
-- (odds shown next to the button, 3-second hatch), capped perks, pets,
-- relic skins and gamepasses. Nothing here decides a race.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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

local MetaShop = {}

local PASS_COPY = {
	{ key = "DoubleGems", title = "2x Gems", body = "Doubles every gem reward. Never touches the race.", icon = "Gem" },
	{ key = "AutoDig", title = "Auto-Dig", body = "Keeps digging without holding. Same speed as manual.", icon = "Robot" },
	{ key = "BigPack", title = "Bigger starting pack", body = "Start every round with the Rucksack.", icon = "Backpack" },
	{ key = "DrillSkins", title = "All drill skins", body = "Unlocks every skin. Cosmetic only.", icon = "Skin" },
}

local SHAKE = TweenInfo.new(0.09, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local POP = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function section(parent: Instance, title: string, icon: string, order: number): Frame
	local panel = Panel.new({ parent = parent, style = "card", size = UDim2.new(1, 0, 0, 0), padding = 12, layoutOrder = order })
	panel.AutomaticSize = Enum.AutomaticSize.Y
	Base.list(panel, Enum.FillDirection.Vertical, 8)
	local head = Base.frame(panel, "Head", UDim2.new(1, 0, 0, 32))
	head.LayoutOrder = 0
	Icon.new({ parent = head, name = icon, size = UDim2.fromOffset(30, 30), position = UDim2.new(0, 0, 0.5, 0), anchor = Vector2.new(0, 0.5) })
	Label.new({ parent = head, text = string.upper(title), size = UDim2.new(1, -40, 1, 0), position = UDim2.fromOffset(38, 0), textSize = 23, display = true })
	return panel
end

local function grid(parent: Instance, cell: Vector2, order: number): Frame
	local frame = Base.frame(parent, "Grid", UDim2.new(1, 0, 0, 0))
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	local layout = Base.grid(frame, UDim2.fromOffset(cell.X, cell.Y), 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	return frame
end

function MetaShop.new(ctx: Base.Context): Modal.Handle
	local state = ctx.state
	local sfx = function(name: string)
		ctx.sfx.play(name)
	end
	local modal = Modal.new({ parent = ctx.modals, title = "Gem Shop", name = "MetaShop", maxWidth = 760, maxHeight = 580, sfx = sfx, color = "purple", icon = "Gem" })
	local list = modal.content
	Base.list(list, Enum.FillDirection.Vertical, 12)

	-- Wallet --------------------------------------------------------------------------
	local walletRow = Base.frame(list, "Wallet", UDim2.new(1, 0, 0, 40))
	walletRow.LayoutOrder = 0
	Base.list(walletRow, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	Icon.new({ parent = walletRow, name = "Gem", size = UDim2.fromOffset(34, 34), layoutOrder = 1 })
	local gemsLabel = Label.new({ parent = walletRow, text = "0", size = UDim2.new(0, 0, 1, 0), textSize = 28, display = true, color = UITheme.Colors.Cyan, layoutOrder = 2 })
	gemsLabel.AutomaticSize = Enum.AutomaticSize.X
	Icon.new({ parent = walletRow, name = "Relic", size = UDim2.fromOffset(32, 32), layoutOrder = 3 })
	local relicsLabel = Label.new({ parent = walletRow, text = "0", size = UDim2.new(0, 0, 1, 0), textSize = 28, display = true, color = UITheme.Colors.Gold, layoutOrder = 4 })
	relicsLabel.AutomaticSize = Enum.AutomaticSize.X

	-- Egg -------------------------------------------------------------------------------
	local egg = section(list, "Pet egg", "Egg", 1)
	local eggBody = Base.frame(egg, "Body", UDim2.new(1, 0, 0, 160))
	eggBody.LayoutOrder = 1
	local stage = Base.fill(eggBody, "Stage", Color3.new(1, 1, 1), UDim2.fromOffset(150, 150))
	Base.corner(stage, 20)
	Base.stroke(stage, UITheme.Colors.Ink, 3.5)
	local stageGradient = Base.gradient(stage, UITheme.Swatches.purple.top, UITheme.Swatches.purple.bottom)
	local eggIcon = Icon.new({ parent = stage, name = "Egg", size = UDim2.fromOffset(96, 96), position = UDim2.fromScale(0.5, 0.48), anchor = Vector2.new(0.5, 0.5) })
	local eggScale = Instance.new("UIScale")
	eggScale.Parent = eggIcon
	local eggResult = Label.new({ parent = stage, text = "", size = UDim2.new(1, -8, 0, 22), position = UDim2.new(0.5, 0, 1, -4), anchor = Vector2.new(0.5, 1), align = Enum.TextXAlignment.Center, textSize = 17, display = true, scaled = true })

	local info = Base.frame(eggBody, "Info", UDim2.new(1, -164, 1, 0), UDim2.fromOffset(164, 0))
	Label.new({ parent = info, text = `Pets follow you and add up to +15% gems. Duplicates refund {math.floor(GameConfig.Pets.EggCost / 3)} gems.`, size = UDim2.new(1, 0, 0, 44), textSize = 16, color = UITheme.Colors.TextDim, wrap = true, valign = Enum.TextYAlignment.Top })
	local oddsRow = Base.frame(info, "Odds", UDim2.new(1, 0, 0, 56), UDim2.fromOffset(0, 48))
	local oddsLayout = Base.list(oddsRow, Enum.FillDirection.Horizontal, 5)
	oddsLayout.Wraps = true
	for i, entry in GameConfig.Pets.Odds do
		local rarity = UITheme.rarity(UITheme.PetTier[entry.tier] or 1)
		local chip = Base.fill(oddsRow, entry.tier, rarity.color, UDim2.fromOffset(0, 24))
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.LayoutOrder = i
		Base.round(chip)
		Base.stroke(chip, UITheme.Colors.Ink, 2)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = chip
		local text = Label.new({ parent = chip, text = `{string.upper(entry.tier)} {entry.chance}%`, size = UDim2.new(0, 0, 1, 0), textSize = 13, display = true })
		text.AutomaticSize = Enum.AutomaticSize.X
	end
	local eggButton = Button.new({
		parent = info,
		text = `OPEN  {GameConfig.Pets.EggCost}`,
		icon = "Gem",
		size = UDim2.new(1, 0, 0, 58),
		position = UDim2.new(0, 0, 1, 0),
		anchor = Vector2.new(0, 1),
		kind = "purple",
		textSize = 24,
		sfx = sfx,
		onClick = function()
			state.send("OpenEgg")
		end,
	})

	-- Perks ------------------------------------------------------------------------------
	local perks = section(list, "Perks (permanent, capped)", "Muscle", 2)
	local perkRow = Base.frame(perks, "Row", UDim2.new(1, 0, 0, 112))
	perkRow.LayoutOrder = 1
	Base.list(perkRow, Enum.FillDirection.Horizontal, 10)
	local function perkCard(kind: "digSpeed" | "pack", title: string, order: number)
		local card = Base.frame(perkRow, kind, UDim2.new(0.5, -5, 1, 0))
		card.LayoutOrder = order
		Label.new({ parent = card, text = title, size = UDim2.new(1, 0, 0, 26), textSize = 21, display = true })
		local detail = Label.new({ parent = card, text = "", size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 26), textSize = 15, color = UITheme.Colors.TextDim })
		local buy = Button.new({
			parent = card,
			text = "",
			icon = "Gem",
			size = UDim2.new(1, 0, 0, 56),
			position = UDim2.new(0, 0, 1, 0),
			anchor = Vector2.new(0, 1),
			kind = "green",
			textSize = 20,
			sfx = sfx,
			onClick = function()
				state.send("BuyMeta", kind)
			end,
		})
		return { detail = detail, buy = buy }
	end
	local digPerk = perkCard("digSpeed", "DRILL TUNING", 1)
	local packPerk = perkCard("pack", "PACK FRAME", 2)

	-- Pets ---------------------------------------------------------------------------------
	local petsPanel = section(list, "Your pets", "Pet", 3)
	local petGrid = grid(petsPanel, Vector2.new(108, 108), 1)
	local petButtons: { [string]: Button.Handle } = {}
	for order, pet in GameConfig.Pets.List do
		petButtons[pet.id] = Button.new({
			parent = petGrid,
			text = pet.name,
			icon = `Pet:{pet.id}`,
			iconSize = 46,
			stack = true,
			size = UDim2.fromOffset(108, 108),
			textSize = 14,
			layoutOrder = order,
			sfx = sfx,
			onClick = function()
				local profile = state.profile
				local equipped = if profile then profile.purchases.equippedPet else ""
				state.send("Equip", "pet", if equipped == pet.id then "" else pet.id)
			end,
		})
	end

	-- Skins ------------------------------------------------------------------------------------
	local skinsPanel = section(list, "Drill skins (relics)", "Skin", 4)
	local skinGrid = grid(skinsPanel, Vector2.new(108, 108), 1)
	local skinButtons: { [string]: Button.Handle } = {}
	for order, skin in GameConfig.Skins do
		local button = Button.new({
			parent = skinGrid,
			text = skin.name,
			size = UDim2.fromOffset(108, 108),
			textSize = 14,
			stack = true,
			layoutOrder = order,
			sfx = sfx,
		})
		-- Two dots preview the body and bit colours.
		local dots = Base.frame(button.face, "Dots", UDim2.fromOffset(60, 34), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0))
		dots.ZIndex = 4
		Base.list(dots, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		for i, hex in { skin.color, skin.bitColor } do
			local dot = Base.fill(dots, `Dot{i}`, Color3.fromHex(hex), UDim2.fromOffset(28, 28))
			dot.ZIndex = 4
			dot.LayoutOrder = i
			Base.round(dot)
			Base.stroke(dot, UITheme.Colors.Ink, 2.5)
		end
		skinButtons[skin.id] = button
	end

	-- Gamepasses ----------------------------------------------------------------------------------
	local passPanel = section(list, "Gamepasses", "Star", 5)
	local passButtons: { [string]: Button.Handle } = {}
	for order, pass in PASS_COPY do
		local row = Base.frame(passPanel, pass.key, UDim2.new(1, 0, 0, 60))
		row.LayoutOrder = order
		Icon.new({ parent = row, name = pass.icon, size = UDim2.fromOffset(40, 40), position = UDim2.new(0, 0, 0.5, 0), anchor = Vector2.new(0, 0.5) })
		Label.new({ parent = row, text = string.upper(pass.title), size = UDim2.new(1, -190, 0, 26), position = UDim2.fromOffset(50, 4), textSize = 19, display = true })
		Label.new({ parent = row, text = pass.body, size = UDim2.new(1, -190, 0, 20), position = UDim2.fromOffset(50, 32), textSize = 14, color = UITheme.Colors.TextDim, truncate = true })
		local id = (AssetIds.Gamepasses :: { [string]: number })[pass.key] or 0
		passButtons[pass.key] = Button.new({
			parent = row,
			text = if AssetIds.isSet(id) then "BUY" else "SOON",
			size = UDim2.fromOffset(124, 50),
			position = UDim2.new(1, 0, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			kind = "gold",
			textSize = 20,
			sfx = sfx,
			onClick = function()
				if AssetIds.isSet(id) then
					MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, id)
				end
			end,
		})
		if not AssetIds.isSet(id) then
			passButtons[pass.key].setEnabled(false)
		end
	end

	-- Refresh -----------------------------------------------------------------------------------------
	local hatching = false
	local function refresh()
		local profile = state.profile
		local gems = state.number("Gems", 0)
		local relics = state.number("Relics", 0)
		gemsLabel.Text = Format.cash(gems)
		relicsLabel.Text = tostring(relics)

		local digLvl = state.number("MetaDig", 0)
		local digCost = Economy.metaCost("digSpeed", digLvl)
		digPerk.detail.Text = `Level {digLvl}/{GameConfig.Meta.DigSpeed.maxLevel} · +{Format.percent(digLvl * GameConfig.Meta.DigSpeed.perLevel)} dig speed`
		digPerk.buy.setText(if digCost then `UPGRADE  {digCost}` else "MAXED")
		digPerk.buy.setEnabled(digCost ~= nil and gems >= digCost)

		local packLvl = state.number("MetaPack", 0)
		local packCost = Economy.metaCost("pack", packLvl)
		packPerk.detail.Text = `Level {packLvl}/{GameConfig.Meta.Pack.maxLevel} · +{packLvl * GameConfig.Meta.Pack.perLevel} pack slots`
		packPerk.buy.setText(if packCost then `UPGRADE  {packCost}` else "MAXED")
		packPerk.buy.setEnabled(packCost ~= nil and gems >= packCost)

		eggButton.setEnabled(gems >= GameConfig.Pets.EggCost and not hatching)

		local owned = if profile then profile.purchases.pets else {}
		local equippedPet = if profile then profile.purchases.equippedPet else ""
		for _, pet in GameConfig.Pets.List do
			local button = petButtons[pet.id]
			local has = (owned[pet.id] or 0) > 0
			local rarity = UITheme.rarity(UITheme.PetTier[pet.tier] or 1)
			button.setEnabled(has)
			button.setKind(if equippedPet == pet.id then "green" else rarity.swatch)
			button.setText(if not has then `🔒 {pet.tier}` elseif equippedPet == pet.id then "EQUIPPED" else pet.name)
		end

		local skins = if profile then profile.purchases.skins else {}
		local equippedSkin = if profile then profile.purchases.equippedSkin else "default"
		local allSkins = state.ownsPass("DrillSkins")
		for _, skin in GameConfig.Skins do
			local button = skinButtons[skin.id]
			local has = skins[skin.id] == true or allSkins
			if has then
				button.setText(if equippedSkin == skin.id then "EQUIPPED" else skin.name)
				button.setKind(if equippedSkin == skin.id then "green" else "blue")
				button.setEnabled(true)
				button.setOnClick(function()
					state.send("Equip", "skin", skin.id)
				end)
			else
				button.setText(`🏺 {skin.relics}`)
				button.setKind("gold")
				button.setEnabled(relics >= skin.relics)
				button.setOnClick(function()
					state.send("BuyMeta", "skin", skin.id)
				end)
			end
		end

		for _, pass in PASS_COPY do
			if state.ownsPass(pass.key) then
				local button = passButtons[pass.key]
				button.setText("OWNED")
				button.setKind("green")
				button.setEnabled(false)
			end
		end
	end

	for _, name in { "Gems", "Relics", "MetaDig", "MetaPack", "Passes" } do
		state.onAttr(name, refresh)
	end
	state.onProfile:Connect(refresh)
	modal.onOpen:Connect(refresh)

	-- Hatch: the egg wobbles harder and harder, flashes, and pops into the pet.
	state.onEggResult:Connect(function(petId, duplicate)
		local pet
		for _, def in GameConfig.Pets.List do
			if def.id == petId then
				pet = def
			end
		end
		if not pet then
			return
		end
		modal.open()
		hatching = true
		refresh()
		Icon.set(eggIcon, "Egg")
		eggResult.Text = ""
		stageGradient.Color = ColorSequence.new(UITheme.Swatches.purple.top, UITheme.Swatches.purple.bottom)
		task.spawn(function()
			for i = 1, 8 do
				local angle = (if i % 2 == 0 then -1 else 1) * (6 + i * 3)
				local tween = TweenService:Create(eggIcon, SHAKE, { Rotation = angle })
				tween:Play()
				tween.Completed:Wait()
			end
			eggIcon.Rotation = 0
			ctx.sfx.play("EggCrack", { volume = 0.8 })
			local rarity = UITheme.rarity(UITheme.PetTier[pet.tier] or 1)
			local swatch = UITheme.swatch(rarity.swatch)
			stageGradient.Color = ColorSequence.new(swatch.top, swatch.bottom)
			Icon.set(eggIcon, `Pet:{pet.id}`)
			eggScale.Scale = 0.2
			TweenService:Create(eggScale, POP, { Scale = 1 }):Play()
			ctx.juice.punch(stage, 0.15)
			eggResult.Text = if duplicate then `{string.upper(pet.name)} (DUPE +{math.floor(GameConfig.Pets.EggCost / 3)})` else `{string.upper(pet.name)}!`
			if (UITheme.PetTier[pet.tier] or 1) >= 4 then
				ctx.fx.shake(0.2, 0.4)
				ctx.sfx.play("RareSting")
			end
			hatching = false
			refresh()
		end)
	end)

	return modal
end

return MetaShop
