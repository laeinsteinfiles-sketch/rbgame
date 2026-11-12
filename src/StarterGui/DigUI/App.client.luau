--!strict
-- Explorer: StarterGui/DigUI/App (LocalScript)
-- Builds the three responsive UI layers (hud, overlay, modals), hands every
-- screen the same context, and wires the menu tiles. Screens never reach
-- into each other.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Base = require(script.Parent.Components.Base)
local Modal = require(script.Parent.Components.Modal)
local Toast = require(script.Parent.Components.Toast)
local Collection = require(script.Parent.Screens.Collection)
local HUD = require(script.Parent.Screens.HUD)
local MetaShop = require(script.Parent.Screens.MetaShop)
local More = require(script.Parent.Screens.More)
local QuestsScreen = require(script.Parent.Screens.QuestsScreen)
local RaceTracker = require(script.Parent.Screens.RaceTracker)
local RoundOverlay = require(script.Parent.Screens.RoundOverlay)
local Shop = require(script.Parent.Screens.Shop)

local gui = script.Parent :: ScreenGui

-- Live controller instances from PlayerScripts (module cache is shared).
local controllers = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers")
local function controller(name: string): any
	return require(controllers:WaitForChild(name) :: ModuleScript) :: any
end

local ctx: Base.Context = {
	gui = gui,
	hud = Base.responsiveRoot(gui, "HUD"),
	overlay = Base.responsiveRoot(gui, "Overlay"),
	modals = Base.responsiveRoot(gui, "Modals"),
	state = controller("ClientState"),
	dig = controller("DigController"),
	juice = controller("Juice"),
	fx = controller("LayerFX"),
	sfx = controller("SFX"),
	music = controller("Music"),
	isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
}
ctx.hud.ZIndex = 1
ctx.overlay.ZIndex = 2
ctx.modals.ZIndex = 3

-- Layer changes and relics get their own big banners (RoundOverlay).
local toasts = Toast.new(ctx.overlay)
ctx.state.onNotify:Connect(function(kind, message)
	if kind ~= "layer" and kind ~= "relic" then
		toasts.show(kind, message)
	end
end)

local hud = HUD.new(ctx)
RaceTracker.new(ctx)
RoundOverlay.new(ctx)

local shop = Shop.new(ctx)
local collection = Collection.new(ctx)
local quests = QuestsScreen.new(ctx)
local meta = MetaShop.new(ctx)
local more = More.new(ctx)

hud.setMenuAction("Shop", shop.toggle)
hud.setMenuAction("Book", collection.toggle)
hud.setMenuAction("Quests", quests.toggle)
hud.setMenuAction("Gems", meta.toggle)
hud.setMenuAction("More", more.toggle)

-- The HUD hides the touch DIG button and hints while any menu is open.
for _, modal in { shop, collection, quests, meta, more } do
	modal.onOpen:Connect(function()
		hud.setModalOpen(true)
	end)
	modal.onClose:Connect(function()
		hud.setModalOpen(Modal.anyOpen())
	end)
end

-- Any menu closes when the round flips to Results so the podium is readable.
ctx.state.onRound("Phase", function(phase)
	if phase == "Results" then
		Modal.closeAll()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		Modal.closeAll()
	elseif input.KeyCode == Enum.KeyCode.E then
		shop.toggle()
	end
end)
