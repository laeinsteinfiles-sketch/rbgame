--!nocheck
-- Lune harness: runs the game's own ModuleScripts outside Studio.
-- Loads the Rojo-built place, gives every module a Roblox-like environment
-- (script, require, game, datatypes), and polyfills the engine pieces Lune
-- does not implement (signals, tweens, pivots, services) so builders and UI
-- code execute unmodified. Property names and value types are still
-- validated by Lune's reflection database, which is the point: a typo or a
-- wrong value type throws here instead of in Studio.

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")
local serde = require("@lune/serde")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local Enum = roblox.Enum

local H = {}
H.roblox = roblox
H.viewport = Vector2.new(1280, 720)
H.side = "client"
H.touch = false
H.calls = {}

-- Signals --------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end
function Signal:Connect(fn)
	table.insert(self.handlers, fn)
	local connection = { Connected = true }
	function connection:Disconnect()
		self.Connected = false
	end
	return connection
end
Signal.Once = Signal.Connect
function Signal:Wait()
	return nil
end
function Signal:Fire(...)
	for _, handler in self.handlers do
		handler(...)
	end
end
H.Signal = Signal

local store = setmetatable({}, { __mode = "k" })
local function signalFor(inst, key)
	local bucket = store[inst]
	if not bucket then
		bucket = {}
		store[inst] = bucket
	end
	local s = bucket[key]
	if not s then
		s = Signal.new()
		bucket[key] = s
	end
	return s
end
H.signalFor = signalFor

local EVENTS = {
	Instance = { "Changed", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "Destroying", "AttributeChanged" },
	GuiObject = { "InputBegan", "InputEnded", "InputChanged", "MouseEnter", "MouseLeave", "MouseMoved", "TouchTap" },
	GuiButton = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click" },
	BasePart = { "Touched", "TouchEnded" },
	RemoteEvent = { "OnServerEvent", "OnClientEvent" },
	BindableEvent = { "Event" },
	ProximityPrompt = { "Triggered", "TriggerEnded", "PromptShown", "PromptHidden" },
	ProximityPromptService = { "PromptTriggered" },
	Players = { "PlayerAdded", "PlayerRemoving" },
	Player = { "CharacterAdded", "CharacterRemoving" },
	Humanoid = { "Died", "StateChanged" },
	RunService = { "Heartbeat", "RenderStepped", "Stepped", "PreSimulation", "PostSimulation", "PreRender", "PreAnimation" },
	UserInputService = { "InputBegan", "InputEnded", "InputChanged", "LastInputTypeChanged", "TouchStarted", "TouchEnded" },
	Sound = { "Ended" },
	MarketplaceService = { "PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished" },
	TextBox = { "FocusLost", "Focused" },
}
for className, names in EVENTS do
	for _, name in names do
		roblox.implementProperty(className, name, function(inst)
			return signalFor(inst, name)
		end)
	end
end

local function method(className, name, fn)
	roblox.implementMethod(className, name, fn)
end

method("Instance", "GetPropertyChangedSignal", function(inst, prop)
	return signalFor(inst, "prop:" .. prop)
end)
method("Instance", "GetAttributeChangedSignal", function(inst, attr)
	return signalFor(inst, "attr:" .. attr)
end)
method("Instance", "WaitForChild", function(inst, name, timeout)
	local child = inst:FindFirstChild(name)
	if not child and timeout == nil then
		error(`WaitForChild would hang: {inst:GetFullName()}.{name}`)
	end
	return child
end)

-- Pivots ---------------------------------------------------------------------

local function basePartsOf(model)
	local parts = {}
	if model:IsA("BasePart") then
		table.insert(parts, model)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

local function modelPivot(model)
	if model.PrimaryPart then
		return model.PrimaryPart.CFrame
	end
	return model.WorldPivot
end

method("Model", "GetPivot", modelPivot)
method("Model", "PivotTo", function(model, cf)
	local delta = cf * modelPivot(model):Inverse()
	for _, part in basePartsOf(model) do
		part.CFrame = delta * part.CFrame
	end
	if not model.PrimaryPart then
		model.WorldPivot = cf
	end
end)
method("Model", "ScaleTo", function(model, s)
	local pivot = modelPivot(model)
	for _, part in basePartsOf(model) do
		local rel = pivot:Inverse() * part.CFrame
		part.Size *= s
		part.CFrame = pivot * CFrame.new(rel.Position * s) * rel.Rotation
	end
end)
method("Model", "GetBoundingBox", function(model)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in basePartsOf(model) do
		local p, s = part.CFrame.Position, part.Size / 2
		lo = lo:Min(p - s)
		hi = hi:Max(p + s)
	end
	return CFrame.new((lo + hi) / 2), hi - lo
end)
method("BasePart", "GetPivot", function(part)
	return part.CFrame
end)
method("BasePart", "PivotTo", function(part, cf)
	part.CFrame = cf
end)
-- Lune stores CFrame only; Position is derived in the engine.
roblox.implementProperty("BasePart", "Position", function(part)
	return part.CFrame.Position
end, function(part, value)
	part.CFrame = CFrame.new(value) * part.CFrame.Rotation
end)

-- Services ------------------------------------------------------------------

local Tween = {}
Tween.__index = Tween
function Tween:Play()
	-- Previews show the settled state, so tweens apply their goals at once.
	for key, value in self.goals do
		self.object[key] = value
	end
	self.Completed:Fire(Enum.PlaybackState.Completed)
end
function Tween:Cancel() end
function Tween:Pause() end
method("TweenService", "Create", function(_, object, info, goals)
	return setmetatable({ object = object, info = info, goals = goals, Completed = Signal.new() }, Tween)
end)

method("RunService", "IsServer", function()
	return H.side == "server"
end)
method("RunService", "IsClient", function()
	return H.side == "client"
end)
method("RunService", "IsStudio", function()
	return true
end)
method("RunService", "BindToRenderStep", function() end)
method("RunService", "UnbindFromRenderStep", function() end)

for _, prop in { "TouchEnabled", "KeyboardEnabled", "MouseEnabled", "GamepadEnabled" } do
	roblox.implementProperty("UserInputService", prop, function()
		if prop == "TouchEnabled" then
			return H.touch
		elseif prop == "GamepadEnabled" then
			return false
		end
		return not H.touch
	end)
end
method("UserInputService", "GetLastInputType", function()
	return if H.touch then Enum.UserInputType.Touch else Enum.UserInputType.MouseButton1
end)
method("UserInputService", "GetMouseLocation", function()
	return Vector2.new(0, 0)
end)

method("RemoteEvent", "FireServer", function(remote, ...)
	table.insert(H.calls, { remote.Name, ... })
end)
method("RemoteEvent", "FireClient", function() end)
method("RemoteEvent", "FireAllClients", function() end)

method("Players", "GetPlayers", function()
	return H.players or {}
end)
method("Players", "GetPlayerByUserId", function(_, id)
	for _, p in H.players or {} do
		if p.UserId == id then
			return p
		end
	end
	return nil
end)
method("Players", "GetUserThumbnailAsync", function(_, userId)
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=48&h=48`, true
end)
roblox.implementProperty("Players", "LocalPlayer", function()
	return H.localPlayer
end)
method("Player", "Kick", function() end)

method("MarketplaceService", "UserOwnsGamePassAsync", function()
	return false
end)
method("MarketplaceService", "PromptGamePassPurchase", function() end)
for className, names in { Sound = { "Play", "Stop", "Pause", "Resume" }, ParticleEmitter = { "Emit", "Clear" } } do
	for _, name in names do
		method(className, name, function() end)
	end
end
method("StarterGui", "SetCoreGuiEnabled", function() end)
method("StarterGui", "SetCore", function() end)
method("Workspace", "GetServerTimeNow", function()
	return H.serverTime or 1000
end)
method("Workspace", "BulkMoveTo", function(_, parts, cframes)
	for i, part in parts do
		part.CFrame = cframes[i]
	end
end)
roblox.implementProperty("Camera", "ViewportSize", function()
	return H.viewport
end)
method("TextService", "GetTextSize", function(_, text, size)
	return Vector2.new(#text * size * 0.56, size)
end)

-- Globals and require ---------------------------------------------------------

local TweenInfo = {}
function TweenInfo.new(timeValue, style, direction, repeatCount, reverses, delayTime)
	return {
		Time = timeValue or 1,
		EasingStyle = style or Enum.EasingStyle.Quad,
		EasingDirection = direction or Enum.EasingDirection.Out,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delayTime or 0,
	}
end

local Random = {}
Random.__index = Random
function Random.new(seed)
	return setmetatable({ state = (seed or 12345) % 2147483647 }, Random)
end
function Random:_next()
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end
function Random:NextNumber(lo, hi)
	lo, hi = lo or 0, hi or 1
	return lo + (hi - lo) * self:_next()
end
function Random:NextInteger(lo, hi)
	return math.floor(lo + (hi - lo + 1) * self:_next())
end

local cache = {}
local globals

function H.require(module)
	if typeof(module) ~= "Instance" or not module:IsA("ModuleScript") then
		error("require expects a ModuleScript, got " .. tostring(module), 2)
	end
	local key = module:GetFullName()
	if cache[key] ~= nil then
		return cache[key]
	end
	-- Lune injects its own globals into missing keys, so ours must be raw fields.
	local env = setmetatable({ script = module, require = H.require }, { __index = globals })
	for key, value in globals do
		env[key] = value
	end
	local chunk = luau.load(module.Source, { debugName = key, environment = env })
	local result = chunk()
	cache[key] = result
	return result
end

--- Loads the place and installs globals. side = "client" | "server".
function H.boot(options)
	H.side = options.side or "client"
	H.touch = options.touch == true
	if options.viewport then
		H.viewport = options.viewport
	end
	local game = roblox.deserializePlace(fs.readFile(options.place or "build/DigToTheCore.rbxl"))
	H.game = game
	local workspace = game:GetService("Workspace")
	local camera = Instance.new("Camera")
	camera.Parent = workspace
	workspace.CurrentCamera = camera
	globals = {
		game = game,
		workspace = workspace,
		Instance = Instance,
		Vector2 = Vector2,
		Vector3 = Vector3,
		CFrame = CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Rect = roblox.Rect,
		Enum = Enum,
		Font = roblox.Font,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		BrickColor = roblox.BrickColor,
		PhysicalProperties = roblox.PhysicalProperties,
		Ray = roblox.Ray,
		TweenInfo = TweenInfo,
		Random = Random,
		task = task,
		require = H.require,
		warn = function(...)
			print("[warn]", ...)
		end,
		tick = os.clock,
		time = os.clock,
	}
	return game
end

function H.addPlayer(userId, name)
	local players = H.game:GetService("Players")
	local player = Instance.new("Player")
	player.UserId = userId
	player.Name = name
	player.DisplayName = name
	player.Parent = players
	H.players = H.players or {}
	table.insert(H.players, player)
	return player
end

-- Export ---------------------------------------------------------------------

local function rgb(c)
	return { c.R, c.G, c.B }
end

function H.partsJson(root)
	local parts = {}
	for _, part in basePartsOf(root) do
		if part.Transparency < 0.98 then
			local shape = "Block"
			if part:IsA("Part") then
				shape = part.Shape.Name
			elseif part:IsA("WedgePart") then
				shape = "Wedge"
			end
			local mesh = part:FindFirstChildOfClass("SpecialMesh")
			if mesh and mesh.MeshType == Enum.MeshType.Sphere then
				shape = "Ellipsoid"
			end
			table.insert(parts, {
				name = part.Name,
				shape = shape,
				size = { part.Size.X, part.Size.Y, part.Size.Z },
				cframe = { part.CFrame:GetComponents() },
				color = rgb(part.Color),
				transparency = part.Transparency,
				material = part.Material.Name,
			})
		end
	end
	return parts
end

function H.writeScene(path, roots, extra)
	local parts = {}
	for _, root in roots do
		for _, p in H.partsJson(root) do
			table.insert(parts, p)
		end
	end
	local scene = extra or {}
	scene.parts = parts
	fs.writeFile(path, serde.encode("json", scene))
	return #parts
end

local function udim2(u)
	return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
end

local function sequence(seq)
	local out = {}
	for _, k in seq.Keypoints do
		if typeof(k.Value) == "Color3" then
			table.insert(out, { k.Time, k.Value.R, k.Value.G, k.Value.B })
		else
			table.insert(out, { k.Time, k.Value })
		end
	end
	return out
end

local MODIFIERS = {
	UICorner = function(m)
		return { cornerRadius = { m.CornerRadius.Scale, m.CornerRadius.Offset } }
	end,
	UIStroke = function(m)
		return { thickness = m.Thickness, color = rgb(m.Color), transparency = m.Transparency, applyStrokeMode = m.ApplyStrokeMode.Name, enabled = m.Enabled }
	end,
	UIGradient = function(m)
		return { color = sequence(m.Color), transparency = sequence(m.Transparency), rotation = m.Rotation, offset = { m.Offset.X, m.Offset.Y }, enabled = m.Enabled }
	end,
	UIPadding = function(m)
		return {
			top = { m.PaddingTop.Scale, m.PaddingTop.Offset },
			bottom = { m.PaddingBottom.Scale, m.PaddingBottom.Offset },
			left = { m.PaddingLeft.Scale, m.PaddingLeft.Offset },
			right = { m.PaddingRight.Scale, m.PaddingRight.Offset },
		}
	end,
	UIListLayout = function(m)
		return {
			fillDirection = m.FillDirection.Name,
			padding = { m.Padding.Scale, m.Padding.Offset },
			horizontalAlignment = m.HorizontalAlignment.Name,
			verticalAlignment = m.VerticalAlignment.Name,
			sortOrder = m.SortOrder.Name,
			wraps = m.Wraps,
		}
	end,
	UIGridLayout = function(m)
		return {
			cellSize = udim2(m.CellSize),
			cellPadding = udim2(m.CellPadding),
			fillDirection = m.FillDirection.Name,
			horizontalAlignment = m.HorizontalAlignment.Name,
			verticalAlignment = m.VerticalAlignment.Name,
			sortOrder = m.SortOrder.Name,
			fillDirectionMaxCells = m.FillDirectionMaxCells,
		}
	end,
	UISizeConstraint = function(m)
		return { minSize = { m.MinSize.X, m.MinSize.Y }, maxSize = { math.min(m.MaxSize.X, 1e6), math.min(m.MaxSize.Y, 1e6) } }
	end,
	UIAspectRatioConstraint = function(m)
		return { aspectRatio = m.AspectRatio, aspectType = m.AspectType.Name, dominantAxis = m.DominantAxis.Name }
	end,
	UIScale = function(m)
		return { scale = m.Scale }
	end,
	UITextSizeConstraint = function(m)
		return { minTextSize = m.MinTextSize, maxTextSize = m.MaxTextSize }
	end,
}

local GUI_CLASSES = { Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, ViewportFrame = true, CanvasGroup = true }

local function guiNode(obj)
	local node = {
		class = obj.ClassName,
		name = obj.Name,
		visible = obj.Visible,
		zIndex = obj.ZIndex,
		layoutOrder = obj.LayoutOrder,
		size = udim2(obj.Size),
		position = udim2(obj.Position),
		anchorPoint = { obj.AnchorPoint.X, obj.AnchorPoint.Y },
		rotation = obj.Rotation,
		backgroundColor3 = rgb(obj.BackgroundColor3),
		backgroundTransparency = obj.BackgroundTransparency,
		clipsDescendants = obj.ClipsDescendants,
		automaticSize = obj.AutomaticSize.Name,
		modifiers = {},
		children = {},
	}
	if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		node.text = obj.Text
		node.textSize = obj.TextSize
		node.textScaled = obj.TextScaled
		node.textWrapped = obj.TextWrapped
		node.textColor3 = rgb(obj.TextColor3)
		node.textTransparency = obj.TextTransparency
		node.textXAlignment = obj.TextXAlignment.Name
		node.textYAlignment = obj.TextYAlignment.Name
		node.fontFamily = obj.FontFace.Family
		node.fontWeight = obj.FontFace.Weight.Value
		node.textStrokeColor3 = rgb(obj.TextStrokeColor3)
		node.textStrokeTransparency = obj.TextStrokeTransparency
		node.textTruncate = obj.TextTruncate.Name
		node.richText = obj.RichText
		node.lineHeight = obj.LineHeight
	end
	if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
		node.image = obj.Image
		node.imageColor3 = rgb(obj.ImageColor3)
		node.imageTransparency = obj.ImageTransparency
	end
	if obj:IsA("CanvasGroup") then
		node.groupTransparency = obj.GroupTransparency
		node.groupColor3 = rgb(obj.GroupColor3)
	end
	if obj:IsA("ViewportFrame") then
		node.imageColor3 = rgb(obj.ImageColor3)
		node.imageTransparency = obj.ImageTransparency
		node.ambient = rgb(obj.Ambient)
		node.lightColor = rgb(obj.LightColor)
		node.lightDirection = { obj.LightDirection.X, obj.LightDirection.Y, obj.LightDirection.Z }
		local cam = obj.CurrentCamera
		if cam then
			node.camera = { cframe = { cam.CFrame:GetComponents() }, fov = cam.FieldOfView }
		end
		node.parts = H.partsJson(obj)
	end
	for _, child in obj:GetChildren() do
		local mod = MODIFIERS[child.ClassName]
		if mod then
			local m = mod(child)
			m.class = child.ClassName
			table.insert(node.modifiers, m)
		elseif GUI_CLASSES[child.ClassName] then
			table.insert(node.children, guiNode(child))
		end
	end
	return node
end

function H.writeGui(path, screenGui)
	local root = {
		class = "ScreenGui",
		name = screenGui.Name,
		ignoreGuiInset = screenGui.IgnoreGuiInset,
		screenInsets = screenGui.ScreenInsets.Name,
		children = {},
	}
	for _, child in screenGui:GetChildren() do
		if GUI_CLASSES[child.ClassName] then
			table.insert(root.children, guiNode(child))
		end
	end
	fs.writeFile(path, serde.encode("json", { root = root }))
end

return H
