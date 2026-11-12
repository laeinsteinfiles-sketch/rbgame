--!strict
-- Explorer: StarterGui/DigUI/Components/Modal (ModuleScript)
-- Centred panel with a title row and close button over a dimmed backdrop.
-- One modal at a time; opening another closes the current one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Base = require(script.Parent.Base)
local Button = require(script.Parent.Button)
local Label = require(script.Parent.Label)
local Panel = require(script.Parent.Panel)

local Modal = {}

export type Props = {
	parent: Instance,
	title: string,
	name: string,
	maxWidth: number?,
	maxHeight: number?,
	sfx: ((name: string) -> ())?,
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

local current: Handle? = nil

function Modal.new(props: Props): Handle
	local root = Base.frame(props.parent, props.name, UDim2.fromScale(1, 1))
	root.Visible = false

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = root

	local panel = Panel.new({
		parent = root,
		name = "Panel",
		size = UDim2.fromScale(0.92, 0.84),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		padding = UITheme.Padding,
	})
	Base.sizeConstraint(panel, Vector2.new(280, 220), Vector2.new(props.maxWidth or 720, props.maxHeight or 560))
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local titleRow = Base.frame(panel, "TitleRow", UDim2.new(1, 0, 0, 44))
	local title = Label.new({
		parent = titleRow,
		name = "Title",
		text = props.title,
		size = UDim2.new(1, -110, 1, 0),
		textSize = UITheme.TextSize.Title,
		display = true,
	})
	local handle: Handle
	Button.new({
		parent = titleRow,
		name = "Close",
		text = "Close",
		icon = AssetIds.Icons.Close,
		size = UDim2.new(0, 100, 0, 40),
		position = UDim2.new(1, 0, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		kind = "secondary",
		textSize = UITheme.TextSize.Small,
		sfx = props.sfx,
		onClick = function()
			handle.close()
		end,
	})

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 1, -(44 + UITheme.Gap))
	content.Position = UDim2.new(0, 0, 0, 44 + UITheme.Gap)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 6
	content.ScrollBarImageColor3 = UITheme.Colors.PanelOutline
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.Parent = panel

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
		local out = TweenService:Create(scale, UITheme.Easing.SlideOut, { Scale = 0.94 })
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
		scale.Scale = 0.92
		TweenService:Create(scale, UITheme.Easing.Slide, { Scale = 1 }):Play()
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
			title.Text = text
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

return Modal
