--!strict
-- Explorer: StarterGui/DigUI/Components/Modal (ModuleScript)
-- Centred window: light panel, coloured header ribbon with an outlined title,
-- round red close button, dimmed backdrop. One modal at a time; opening
-- another closes the current one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Config.UITheme)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Base = require(script.Parent.Base)
local Button = require(script.Parent.Button)
local Icon = require(script.Parent.Icon)
local Panel = require(script.Parent.Panel)

local Modal = {}

export type Props = {
	parent: Instance,
	title: string,
	name: string,
	maxWidth: number?,
	maxHeight: number?,
	sfx: ((name: string) -> ())?,
	color: string?, -- header swatch
	icon: string?, -- header icon name
}

export type Handle = {
	root: Frame,
	content: ScrollingFrame,
	open: () -> (),
	close: () -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
	onOpen: Signal.Signal<()>,
	onClose: Signal.Signal<()>,
	setTitle: (text: string) -> (),
}

local HEADER = 56
local OPEN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local current: Handle? = nil

function Modal.new(props: Props): Handle
	local root = Base.frame(props.parent, props.name, UDim2.fromScale(1, 1))
	root.Visible = false

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = UITheme.Colors.Ink
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = root

	local window = Base.frame(root, "Window", UDim2.fromScale(0.9, 0.82), UDim2.new(0.5, 0, 0.5, 14), Vector2.new(0.5, 0.5))
	Base.sizeConstraint(window, Vector2.new(320, 240), Vector2.new(props.maxWidth or 760, props.maxHeight or 560))
	local scale = Instance.new("UIScale")
	scale.Parent = window

	local body = Panel.new({ parent = window, name = "Body", size = UDim2.fromScale(1, 1), padding = 0 })

	local swatch = UITheme.swatch(props.color or "blue")
	local header = Base.fill(window, "Header", Color3.new(1, 1, 1), UDim2.new(1, -56, 0, HEADER), UDim2.new(0.5, 0, 0, -HEADER / 2), Vector2.new(0.5, 0))
	header.ZIndex = 3
	Base.corner(header)
	Base.stroke(header)
	Base.gradient(header, swatch.top, swatch.bottom)
	local headerShine = Base.fill(header, "Shine", Color3.new(1, 1, 1), UDim2.new(1, -12, 0.4, 0), UDim2.fromOffset(6, 4))
	headerShine.BackgroundTransparency = 0.7
	headerShine.ZIndex = 3
	Base.corner(headerShine, 10)

	local titleRow = Base.frame(header, "TitleRow", UDim2.fromScale(1, 1))
	titleRow.ZIndex = 4
	Base.list(titleRow, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	if props.icon then
		Icon.new({ parent = titleRow, name = props.icon, size = UDim2.fromOffset(34, 34), layoutOrder = 1, zIndex = 4 })
	end
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.AutomaticSize = Enum.AutomaticSize.X
	title.Size = UDim2.new(0, 0, 1, -6)
	title.FontFace = UITheme.Font.Display
	title.TextSize = UITheme.TextSize.Title + 2
	title.TextColor3 = UITheme.Colors.White
	title.Text = string.upper(props.title)
	title.LayoutOrder = 2
	title.ZIndex = 4
	Base.textStroke(title, 3)
	title.Parent = titleRow

	local handle: Handle
	Button.new({
		parent = window,
		name = "Close",
		text = "X",
		kind = "red",
		size = UDim2.fromOffset(50, 50),
		position = UDim2.new(1, 14, 0, -20),
		anchor = Vector2.new(1, 0),
		textSize = 26,
		sfx = props.sfx,
		zIndex = 6,
		onClick = function()
			handle.close()
		end,
	})

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -28, 1, -(HEADER / 2 + 30))
	content.Position = UDim2.fromOffset(14, HEADER / 2 + 18)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 8
	content.ScrollBarImageColor3 = UITheme.Colors.Ink
	content.ScrollBarImageTransparency = 0.5
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	content.ZIndex = 2
	content.Parent = body
	Base.padding(content, 4)

	local isOpen = false
	local onOpen = Signal.new() :: Signal.Signal<()>
	local onClose = Signal.new() :: Signal.Signal<()>

	local function close()
		if not isOpen then
			return
		end
		isOpen = false
		if current == handle then
			current = nil
		end
		TweenService:Create(backdrop, CLOSE, { BackgroundTransparency = 1 }):Play()
		local out = TweenService:Create(scale, CLOSE, { Scale = 0.7 })
		out:Play()
		out.Completed:Connect(function()
			if not isOpen then
				root.Visible = false
			end
		end)
		onClose:Fire()
	end

	local function open()
		if isOpen then
			return
		end
		local other = current
		if other and other ~= handle then
			other.close()
		end
		current = handle
		isOpen = true
		root.Visible = true
		scale.Scale = 0.6
		backdrop.BackgroundTransparency = 1
		TweenService:Create(backdrop, CLOSE, { BackgroundTransparency = 0.45 }):Play()
		TweenService:Create(scale, OPEN, { Scale = 1 }):Play()
		if props.sfx then
			props.sfx("Whoosh")
		end
		onOpen:Fire()
	end

	backdrop.Activated:Connect(close)

	handle = {
		root = root,
		content = content,
		open = open,
		close = close,
		toggle = function()
			if isOpen then
				close()
			else
				open()
			end
		end,
		isOpen = function()
			return isOpen
		end,
		onOpen = onOpen,
		onClose = onClose,
		setTitle = function(text: string)
			title.Text = string.upper(text)
		end,
	}
	return handle
end

function Modal.closeAll()
	local open = current
	if open then
		open.close()
	end
end

function Modal.anyOpen(): boolean
	return current ~= nil
end

return Modal
