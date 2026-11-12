--!strict
-- Explorer: StarterGui/DigUI/App (LocalScript)
-- Builds the three UI layers (hud, modals, overlay), hands every screen the
-- same context, and wires the menu row. Screens never reach into each other.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Base = require(script.Parent.Components.Base)
local Modal = require(script.Parent.Components.Modal)
local Toast = require(script.Parent.Components.Toast)
local Collection = require(script.Parent.Screens.Collection)
local HUD = require(script.Parent.Screens.HUD)
local Leaderboard = require(script.Parent.Screens.Leaderboard)
local MetaShop = require(script.Parent.Screens.MetaShop)
local More = require(script.Parent.Screens.More)
local QuestsScreen = require(script.Parent.Screens.QuestsScreen)
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
	hud = Base.frame(gui, "HUD", UDim2.fromScale(1, 1)),
	modals = Base.frame(gui, "Modals", UDim2.fromScale(1, 1)),
	overlay = Base.frame(gui, "Overlay", UDim2.fromScale(1, 1)),
	state = controller("ClientState"),
	dig = controller("DigController"),
	juice = controller("Juice"),
	fx = controller("LayerFX"),
	sfx = controller("SFX"),
	isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
}
ctx.hud.ZIndex = 1
ctx.overlay.ZIndex = 2
ctx.modals.ZIndex = 3

local toasts = Toast.new(ctx.overlay)
ctx.state.onNotify:Connect(function(kind, message)
	toasts.show(kind, if kind == "layer" then `Entering {message}` else message)
	if kind == "relic" then
		ctx.sfx.play("RareSting", { pitch = 0.8 })
	end
end)

local hud = HUD.new(ctx)
Leaderboard.new(ctx)
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

-- Any modal closes when the round flips to Results so the sheet is readable.
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
