--!strict
-- Explorer: StarterGui/DigUI/Components/Toast (ModuleScript)
-- Short notifications stacked under the round timer. One line each, never a
-- wall of text; the kind picks the accent colour of the outline.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Config.UITheme)
local Base = require(script.Parent.Base)
local Label = require(script.Parent.Label)
local Panel = require(script.Parent.Panel)

local Toast = {}

export type Handle = {
	show: (kind: string, text: string) -> (),
}

local ACCENT: { [string]: Color3 } = {
	error = UITheme.Colors.Warn,
	packfull = UITheme.Colors.Warn,
	gems = UITheme.Colors.Teal,
	buy = UITheme.Colors.Teal,
	relic = UITheme.Colors.Amber,
	layer = UITheme.Colors.Amber,
	info = UITheme.Colors.PanelOutline,
}

local LIFETIME = 2.4

function Toast.new(parent: Instance): Handle
	local stack = Base.frame(parent, "Toasts", UDim2.new(0, 360, 0, 200), UDim2.new(0.5, 0, 0, 92), Vector2.new(0.5, 0))
	Base.sizeConstraint(stack, nil, Vector2.new(360, 200))
	Base.list(stack, Enum.FillDirection.Vertical, UITheme.Gap, Enum.HorizontalAlignment.Center)

	local function show(kind: string, text: string)
		local panel = Panel.new({
			parent = stack,
			name = "Toast",
			size = UDim2.new(1, 0, 0, 40),
			padding = 0,
		})
		local stroke = panel:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = ACCENT[kind] or ACCENT.info
		end
		local label = Label.new({
			parent = panel,
			text = text,
			size = UDim2.fromScale(1, 1),
			align = Enum.TextXAlignment.Center,
			textSize = UITheme.TextSize.Body,
			color = if kind == "error" or kind == "packfull" then UITheme.Colors.Warn else UITheme.Colors.Text,
			truncate = true,
		})
		label.LayoutOrder = 0
		panel.LayoutOrder = os.clock() * 1000 // 1
		panel.BackgroundTransparency = 1
		label.TextTransparency = 1
		TweenService:Create(panel, UITheme.Easing.Slide, { BackgroundTransparency = 0 }):Play()
		TweenService:Create(label, UITheme.Easing.Slide, { TextTransparency = 0 }):Play()
		task.delay(LIFETIME, function()
			local fade = TweenService:Create(label, UITheme.Easing.SlideOut, { TextTransparency = 1 })
			TweenService:Create(panel, UITheme.Easing.SlideOut, { BackgroundTransparency = 1 }):Play()
			if stroke then
				TweenService:Create(stroke, UITheme.Easing.SlideOut, { Transparency = 1 }):Play()
			end
			fade:Play()
			fade.Completed:Connect(function()
				panel:Destroy()
			end)
		end)
		-- Keep at most four on screen; the oldest goes first.
		local children = stack:GetChildren()
		local panels = {}
		for _, child in children do
			if child:IsA("GuiObject") then
				table.insert(panels, child)
			end
		end
		if #panels > 4 then
			table.sort(panels, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			panels[1]:Destroy()
		end
	end

	return { show = show }
end

return Toast
