--!strict
-- Explorer: StarterGui/DigUI/Screens/More (ModuleScript)
-- Settings (sound, music, shake, auto-dig) and the credits list.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Credits = require(ReplicatedStorage.Config.Credits)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Base = require(script.Parent.Parent.Components.Base)
local Button = require(script.Parent.Parent.Components.Button)
local Icon = require(script.Parent.Parent.Components.Icon)
local Label = require(script.Parent.Parent.Components.Label)
local Modal = require(script.Parent.Parent.Components.Modal)
local Panel = require(script.Parent.Parent.Components.Panel)

local More = {}

local VOLUME_STEPS = { 0, 0.25, 0.5, 0.75, 1 }

function More.new(ctx: Base.Context): Modal.Handle
	local state = ctx.state
	local sfx = function(name: string)
		ctx.sfx.play(name)
	end
	local modal = Modal.new({ parent = ctx.modals, title = "Settings", name = "More", maxWidth = 560, maxHeight = 500, sfx = sfx, color = "periwinkle", icon = "Settings" })
	local list = modal.content
	Base.list(list, Enum.FillDirection.Vertical, 10)

	local function row(title: string, icon: string, order: number): GuiObject
		local panel = Panel.new({ parent = list, style = "card", size = UDim2.new(1, 0, 0, 68), padding = 10, layoutOrder = order })
		Icon.new({ parent = panel, name = icon, size = UDim2.fromOffset(36, 36), position = UDim2.new(0, 0, 0.5, 0), anchor = Vector2.new(0, 0.5) })
		Label.new({ parent = panel, text = title, size = UDim2.new(1, -250, 1, 0), position = UDim2.fromOffset(46, 0), textSize = 21, display = true })
		return panel
	end

	local function nearest(value: number): number
		local best = 1
		for i, v in VOLUME_STEPS do
			if math.abs(v - value) < math.abs(VOLUME_STEPS[best] - value) then
				best = i
			end
		end
		return best
	end

	local function volumeRow(title: string, icon: string, order: number, get: () -> number, set: (number) -> ())
		local panel = row(title, icon, order)
		local valueLabel = Label.new({ parent = panel, text = "", size = UDim2.new(0, 64, 1, 0), position = UDim2.new(1, -66, 0, 0), anchor = Vector2.new(1, 0), align = Enum.TextXAlignment.Center, textSize = 22, display = true })
		local function apply(index: number)
			local v = VOLUME_STEPS[math.clamp(index, 1, #VOLUME_STEPS)]
			set(v)
			valueLabel.Text = `{math.floor(v * 100)}%`
			state.onSettings:Fire()
		end
		Button.new({ parent = panel, text = "-", kind = "grey", size = UDim2.fromOffset(52, 48), position = UDim2.new(1, -134, 0.5, 0), anchor = Vector2.new(1, 0.5), textSize = 28, sfx = sfx, onClick = function()
			apply(nearest(get()) - 1)
		end })
		Button.new({ parent = panel, text = "+", kind = "green", size = UDim2.fromOffset(52, 48), position = UDim2.new(1, 0, 0.5, 0), anchor = Vector2.new(1, 0.5), textSize = 28, sfx = sfx, onClick = function()
			apply(nearest(get()) + 1)
		end })
		apply(nearest(get()))
	end

	volumeRow("Sound effects", "Sound", 1, function()
		return state.settings.sfxVolume
	end, function(v)
		state.settings.sfxVolume = v
		ctx.sfx.setVolume(v)
	end)
	volumeRow("Music", "Music", 2, function()
		return state.settings.musicVolume
	end, function(v)
		state.settings.musicVolume = v
		ctx.music.setVolume(v)
	end)

	local function toggleRow(title: string, icon: string, order: number, initial: boolean, onChange: (boolean) -> ()): Button.Handle
		local panel = row(title, icon, order)
		local on = initial
		local button: Button.Handle
		button = Button.new({
			parent = panel,
			text = if on then "ON" else "OFF",
			kind = if on then "green" else "grey",
			size = UDim2.fromOffset(120, 48),
			position = UDim2.new(1, 0, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			textSize = 22,
			sfx = sfx,
			onClick = function()
				on = not on
				button.setText(if on then "ON" else "OFF")
				button.setKind(if on then "green" else "grey")
				onChange(on)
			end,
		})
		return button
	end

	toggleRow("Camera shake", "Shake", 3, state.settings.shake, function(on)
		state.settings.shake = on
		ctx.fx.setShakeEnabled(on)
	end)
	local autoButton = toggleRow("Auto-dig (gamepass)", "Robot", 4, state.settings.autoDig, function(on)
		state.settings.autoDig = on
	end)
	state.onAttr("Passes", function()
		autoButton.setEnabled(state.ownsPass("AutoDig"))
	end)

	local credits = Panel.new({ parent = list, style = "card", size = UDim2.new(1, 0, 0, 40 + #Credits * 46), padding = 12, layoutOrder = 5 })
	Label.new({ parent = credits, text = "CREDITS", size = UDim2.new(1, 0, 0, 28), textSize = 22, display = true })
	local creditList = Base.frame(credits, "List", UDim2.new(1, 0, 1, -32), UDim2.fromOffset(0, 32))
	Base.list(creditList, Enum.FillDirection.Vertical, 4)
	for order, entry in Credits do
		local line = Base.frame(creditList, entry.title, UDim2.new(1, 0, 0, 42))
		line.LayoutOrder = order
		Label.new({ parent = line, text = `{entry.title} — {entry.author}`, size = UDim2.new(1, 0, 0, 22), textSize = 16, truncate = true })
		Label.new({ parent = line, text = `{entry.licence} · {entry.url}`, size = UDim2.new(1, 0, 0, 18), position = UDim2.fromOffset(0, 22), textSize = 13, color = UITheme.Colors.TextDim, truncate = true })
	end

	return modal
end

return More
