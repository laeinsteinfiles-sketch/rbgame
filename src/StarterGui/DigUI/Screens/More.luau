--!strict
-- Explorer: StarterGui/DigUI/Screens/More (ModuleScript)
-- Settings (sound, shake, auto-dig) and the credits list that game-icons.net
-- attribution requires.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Credits = require(ReplicatedStorage.Config.Credits)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Base = require(script.Parent.Parent.Components.Base)
local Button = require(script.Parent.Parent.Components.Button)
local Label = require(script.Parent.Parent.Components.Label)
local Modal = require(script.Parent.Parent.Components.Modal)
local Panel = require(script.Parent.Parent.Components.Panel)

local More = {}

local VOLUME_STEPS = { 0, 0.25, 0.5, 0.8, 1 }

function More.new(ctx: Base.Context): Modal.Handle
	local state = ctx.state
	local sfx = function(name: string)
		ctx.sfx.play(name)
	end
	local modal = Modal.new({ parent = ctx.modals, title = "Settings", name = "More", maxWidth = 520, maxHeight = 460, sfx = sfx })
	local list = modal.content
	Base.list(list, Enum.FillDirection.Vertical, UITheme.Gap)

	local function row(title: string, order: number): GuiObject
		local panel = Panel.new({ parent = list, inset = true, size = UDim2.new(1, 0, 0, 60), padding = 10, layoutOrder = order })
		Label.new({ parent = panel, text = title, size = UDim2.new(1, -200, 1, 0), textSize = UITheme.TextSize.Body, display = true })
		return panel
	end

	-- Sound
	local sound = row("Sound volume", 1)
	local volumeLabel = Label.new({ parent = sound, text = "", size = UDim2.new(0, 50, 1, 0), position = UDim2.new(1, -120, 0, 0), anchor = Vector2.new(1, 0), align = Enum.TextXAlignment.Center, textSize = UITheme.TextSize.Body, display = true })
	local function volumeIndex(): number
		local best = 1
		for i, v in VOLUME_STEPS do
			if math.abs(v - state.settings.sfxVolume) < math.abs(VOLUME_STEPS[best] - state.settings.sfxVolume) then
				best = i
			end
		end
		return best
	end
	local function setVolume(index: number)
		state.settings.sfxVolume = VOLUME_STEPS[math.clamp(index, 1, #VOLUME_STEPS)]
		ctx.sfx.setVolume(state.settings.sfxVolume)
		volumeLabel.Text = tostring(math.floor(state.settings.sfxVolume * 100))
		state.onSettings:Fire()
	end
	Button.new({ parent = sound, text = "-", size = UDim2.new(0, 48, 0, 40), position = UDim2.new(1, -176, 0.5, 0), anchor = Vector2.new(1, 0.5), sfx = sfx, onClick = function() setVolume(volumeIndex() - 1) end })
	Button.new({ parent = sound, text = "+", size = UDim2.new(0, 48, 0, 40), position = UDim2.new(1, 0, 0.5, 0), anchor = Vector2.new(1, 0.5), sfx = sfx, onClick = function() setVolume(volumeIndex() + 1) end })
	setVolume(volumeIndex())

	-- Shake
	local shake = row("Camera shake", 2)
	local shakeButton: Button.Handle
	shakeButton = Button.new({
		parent = shake,
		text = "",
		size = UDim2.new(0, 120, 0, 40),
		position = UDim2.new(1, 0, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		sfx = sfx,
		onClick = function()
			state.settings.shake = not state.settings.shake
			ctx.fx.setShakeEnabled(state.settings.shake)
			shakeButton.setText(if state.settings.shake then "On" else "Off")
			shakeButton.setKind(if state.settings.shake then "primary" else "secondary")
		end,
	})
	shakeButton.setText("On")
	shakeButton.setKind("primary")

	-- Auto-dig
	local auto = row("Auto-dig (gamepass)", 3)
	local autoButton: Button.Handle
	autoButton = Button.new({
		parent = auto,
		text = "Off",
		size = UDim2.new(0, 120, 0, 40),
		position = UDim2.new(1, 0, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		sfx = sfx,
		onClick = function()
			state.settings.autoDig = not state.settings.autoDig
			autoButton.setText(if state.settings.autoDig then "On" else "Off")
			autoButton.setKind(if state.settings.autoDig then "primary" else "secondary")
		end,
	})
	state.onAttr("Passes", function()
		autoButton.setEnabled(state.ownsPass("AutoDig"))
	end)

	-- Credits
	local credits = Panel.new({ parent = list, inset = true, size = UDim2.new(1, 0, 0, 30 + #Credits * 44), padding = 10, layoutOrder = 4 })
	Label.new({ parent = credits, text = "Credits", size = UDim2.new(1, 0, 0, 24), textSize = UITheme.TextSize.Title, display = true })
	local creditList = Base.frame(credits, "List", UDim2.new(1, 0, 1, -28), UDim2.fromOffset(0, 28))
	Base.list(creditList, Enum.FillDirection.Vertical, 4)
	for order, entry in Credits do
		local line = Base.frame(creditList, entry.title, UDim2.new(1, 0, 0, 40))
		line.LayoutOrder = order
		Label.new({ parent = line, text = `{entry.title} — {entry.author}`, size = UDim2.new(1, 0, 0, 20), textSize = UITheme.TextSize.Small, truncate = true })
		Label.new({ parent = line, text = `{entry.licence} · {entry.url}`, size = UDim2.new(1, 0, 0, 16), position = UDim2.fromOffset(0, 20), textSize = 12, color = UITheme.Colors.TextDim, truncate = true })
	end

	return modal
end

return More
