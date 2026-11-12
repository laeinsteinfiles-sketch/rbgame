--!strict
-- Explorer: StarterGui/DigUI/Components/Toast (ModuleScript)
-- Short notifications that pop in under the round timer: a coloured pill with
-- an icon and one outlined line of text. The kind picks colour and icon.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Config.UITheme)
local Base = require(script.Parent.Base)
local Icon = require(script.Parent.Icon)

local Toast = {}

export type Handle = {
	show: (kind: string, text: string) -> (),
}

local STYLE: { [string]: { swatch: string, icon: string } } = {
	error = { swatch = "red", icon = "Warning" },
	packfull = { swatch = "red", icon = "Backpack" },
	gems = { swatch = "purple", icon = "Gem" },
	buy = { swatch = "green", icon = "Check" },
	relic = { swatch = "gold", icon = "Relic" },
	layer = { swatch = "orange", icon = "Depth" },
	sell = { swatch = "gold", icon = "Cash" },
	quest = { swatch = "orange", icon = "Quest" },
	info = { swatch = "blue", icon = "Info" },
}

local LIFETIME = 2.6
local MAX_SHOWN = 3

function Toast.new(parent: Instance): Handle
	local stack = Base.frame(parent, "Toasts", UDim2.new(0, 520, 0, 200), UDim2.new(0.5, 0, 0, 138), Vector2.new(0.5, 0))
	Base.list(stack, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	local order = 0

	local function show(kind: string, text: string)
		local style = STYLE[kind] or STYLE.info
		local swatch = UITheme.swatch(style.swatch)
		order += 1

		local group = Instance.new("CanvasGroup")
		group.Name = "Toast"
		group.BackgroundColor3 = Color3.new(1, 1, 1)
		group.BorderSizePixel = 0
		group.AutomaticSize = Enum.AutomaticSize.X
		group.Size = UDim2.fromOffset(0, 46)
		group.LayoutOrder = order
		Base.round(group)
		Base.stroke(group, UITheme.Colors.Ink, 3)
		Base.gradient(group, swatch.top, swatch.bottom)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 18)
		pad.Parent = group
		Base.list(group, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		Icon.new({ parent = group, name = style.icon, size = UDim2.fromOffset(32, 32), layoutOrder = 1 })
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.new(0, 0, 1, 0)
		label.FontFace = UITheme.Font.Display
		label.TextSize = 22
		label.TextColor3 = UITheme.Colors.White
		label.Text = text
		label.LayoutOrder = 2
		Base.textStroke(label)
		label.Parent = group
		local scale = Instance.new("UIScale")
		scale.Scale = 0.3
		scale.Parent = group
		group.GroupTransparency = 1
		group.Parent = stack

		TweenService:Create(scale, UITheme.Easing.Pop, { Scale = 1 }):Play()
		TweenService:Create(group, UITheme.Easing.Settle, { GroupTransparency = 0 }):Play()
		task.delay(LIFETIME, function()
			if not group.Parent then
				return
			end
			local fade = TweenService:Create(group, UITheme.Easing.SlideOut, { GroupTransparency = 1 })
			TweenService:Create(scale, UITheme.Easing.SlideOut, { Scale = 0.8 }):Play()
			fade:Play()
			fade.Completed:Connect(function()
				group:Destroy()
			end)
		end)

		-- Keep the newest few; the oldest goes first.
		local live = {}
		for _, child in stack:GetChildren() do
			if child:IsA("CanvasGroup") then
				table.insert(live, child)
			end
		end
		if #live > MAX_SHOWN then
			table.sort(live, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			for i = 1, #live - MAX_SHOWN do
				live[i]:Destroy()
			end
		end
	end

	return { show = show }
end

return Toast
