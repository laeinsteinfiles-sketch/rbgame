--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/Juice (ModuleScript)
-- World-space feedback: dig chips, block shatter, ore pop-and-magnet,
-- blasts, chests, floating value text. Debris runs on a tiny pooled
-- particle sim (position, velocity, spin) instead of physics, so it costs
-- nothing on the network and never collides with the player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Palette = require(ReplicatedStorage.Config.Palette)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local LayerFX = require(script.Parent.LayerFX)
local SFX = require(script.Parent.SFX)

local Juice = {}

local GRAVITY = Vector3.new(0, -70, 0)
local POP_UP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FLOAT = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local folder = Instance.new("Folder")
folder.Name = "LocalJuice"
folder.Parent = Workspace

type Bit = {
	part: Part,
	velocity: Vector3,
	spin: Vector3,
	life: number,
	age: number,
	fade: boolean,
	onDone: ((Part) -> ())?,
}

local freeBits: { Part } = {}
local live: { Bit } = {}
local freeFloats: { BillboardGui } = {}

local function bitPart(): Part
	local part = table.remove(freeBits)
	if part then
		return part
	end
	local p = Instance.new("Part")
	p.Name = "Bit"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function launch(cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material, velocity: Vector3, life: number, fade: boolean): Bit
	local part = bitPart()
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = mat
	part.Transparency = 0
	part.Parent = folder
	local bit: Bit = {
		part = part,
		velocity = velocity,
		spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 14,
		life = life,
		age = 0,
		fade = fade,
		onDone = nil,
	}
	table.insert(live, bit)
	return bit
end

local function step(dt: number)
	for i = #live, 1, -1 do
		local b = live[i]
		b.age += dt
		if b.age >= b.life then
			b.part.Parent = nil
			table.insert(freeBits, b.part)
			table.remove(live, i)
		else
			b.velocity += GRAVITY * dt
			local cf = b.part.CFrame
			b.part.CFrame = (cf + b.velocity * dt) * CFrame.Angles(b.spin.X * dt, b.spin.Y * dt, b.spin.Z * dt)
			if b.fade then
				b.part.Transparency = math.clamp((b.age / b.life - 0.5) * 2, 0, 1)
			end
		end
	end
end

--- A few rock chips kicked up from the dig point on every dig tick.
function Juice.chips(at: Vector3, color: Color3, count: number)
	for _ = 1, count do
		local s = 0.25 + math.random() * 0.3
		local dir = Vector3.new(math.random() - 0.5, 1.4 + math.random(), math.random() - 0.5)
		launch(CFrame.new(at), Vector3.new(s, s, s), color, Enum.Material.Slate, dir * (8 + math.random() * 6), 0.55, true)
	end
end

--- The broken block bursts into chunks that fall away into the shaft.
function Juice.shatter(blockCf: CFrame, color: Color3)
	local half = GameConfig.Geometry.BlockSize / 4
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			for _, sy in { -1, 1 } do
				local offset = Vector3.new(sx * half, sy * 0.9, sz * half)
				local cf = blockCf * CFrame.new(offset)
				local outward = (cf.Position - blockCf.Position).Unit
				local shade = color:Lerp(Color3.new(0, 0, 0), math.random() * 0.25)
				launch(cf, Vector3.new(3.4, 1.7, 3.4) * (0.7 + math.random() * 0.25), shade, Enum.Material.Slate, outward * 10 + Vector3.new(0, 6, 0), 0.7, true)
			end
		end
	end
	SFX.play("BlockBreak", { pitch = 0.9 + math.random() * 0.2, volume = 0.55 })
end

local function emitter(parent: Instance, texture: string, color: Color3, count: number, speed: NumberRange, size: number)
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Speed = speed
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0, 1)
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.8
	e.Parent = parent
	e:Emit(count)
end

--- One-shot anchor part that removes itself after `life` seconds.
local function anchorAt(position: Vector3, life: number): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(position)
	p.Parent = folder
	task.delay(life, function()
		p:Destroy()
	end)
	return p
end

function Juice.floatText(position: Vector3, text: string, color: Color3, big: boolean?)
	local gui = table.remove(freeFloats)
	if not gui then
		local g = Instance.new("BillboardGui")
		g.Name = "FloatText"
		g.AlwaysOnTop = true
		g.Size = UDim2.fromOffset(220, 60)
		g.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.FontFace = UITheme.Font.Display
		label.TextScaled = true
		label.Parent = g
		local stroke = Instance.new("UIStroke")
		stroke.Color = UITheme.Colors.Ink
		stroke.Thickness = 3
		stroke.Parent = label
		gui = g
	end
	local billboard = gui :: BillboardGui
	local label = billboard:FindFirstChild("Label") :: TextLabel
	local stroke = label:FindFirstChildOfClass("UIStroke")
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	if stroke then
		stroke.Transparency = 0
	end
	billboard.Size = if big then UDim2.fromOffset(300, 80) else UDim2.fromOffset(200, 54)
	billboard.StudsOffsetWorldSpace = Vector3.zero
	local anchor = anchorAt(position, 1.2)
	billboard.Adornee = anchor
	billboard.Parent = folder
	local scale = label:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = label
	scale.Scale = 0.4
	TweenService:Create(scale, POP_UP, { Scale = 1 }):Play()
	TweenService:Create(billboard, FLOAT, { StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0) }):Play()
	local fade = TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), { TextTransparency = 1 })
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), { Transparency = 1 }):Play()
	end
	fade:Play()
	fade.Completed:Connect(function()
		billboard.Parent = nil
		table.insert(freeFloats, billboard)
	end)
end

local function playerRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

--- Ore pops out of the block, hangs a beat, then streaks into the player.
function Juice.orePop(position: Vector3, roll: Types.BlockRoll)
	local ore = Economy.oreById[roll.oreId or ""]
	local mutation = Economy.mutationById[roll.mutationId or "none"]
	local color = if roll.relic then Color3.fromHex(Palette.amber) else Color3.fromHex(if ore then ore.color else "FFFFFF")
	local mutated = mutation ~= nil and mutation.id ~= "none"
	if mutated and mutation then
		color = color:Lerp(Color3.fromHex(mutation.color), 0.45)
	end
	local rare = roll.relic or (ore ~= nil and ore.rarity >= 3) or mutated
	local bit = launch(CFrame.new(position + Vector3.new(0, 1, 0)), Vector3.new(1.3, 1.3, 1.3), color, if rare then Enum.Material.Neon else Enum.Material.SmoothPlastic, Vector3.new(0, 26, 0), 0.32, false)
	bit.spin = Vector3.new(4, 9, 3)
	task.delay(0.3, function()
		-- Magnet: the ore streaks to the player's chest and vanishes.
		local root = playerRoot()
		local part = bitPart()
		part.Size = Vector3.new(1.1, 1.1, 1.1)
		part.Color = color
		part.Material = Enum.Material.Neon
		part.Transparency = 0
		part.CFrame = CFrame.new(position + Vector3.new(0, 7, 0))
		part.Parent = folder
		local target = if root then root.Position + Vector3.new(0, 1, 0) else position
		local tween = TweenService:Create(part, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = CFrame.new(target),
			Size = Vector3.new(0.3, 0.3, 0.3),
		})
		tween:Play()
		tween.Completed:Connect(function()
			part.Parent = nil
			table.insert(freeBits, part)
		end)
	end)
	if rare then
		emitter(anchorAt(position + Vector3.new(0, 2, 0), 1.5), AssetIds.Particles.Sparkle, color, 28, NumberRange.new(8, 14), 0.5)
		SFX.play("RareSting", { pitch = if roll.relic then 0.9 else 1 })
		LayerFX.shake(0.12, 0.2)
	end
	local rarity = if ore then ore.rarity else 3
	SFX.play("OreChime", { pitch = 0.85 + rarity * 0.08, volume = 0.5 })
	local value = if roll.relic then "RELIC!" else `+${Format.cash(Economy.oreValue(roll.oreId or "", roll.mutationId))}`
	local label = if mutated and mutation then `{mutation.name}! {value}` else value
	Juice.floatText(position + Vector3.new(1.5, 3, 0), label, if rare then UITheme.Colors.Amber else UITheme.Colors.Text, rare)
end

--- Blast charge: flash, shockwave ring, debris storm, big shake.
function Juice.blast(position: Vector3, color: Color3)
	local flash = anchorAt(position, 0.6)
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromHex("FFC46B")
	flash.Transparency = 0
	flash.Size = Vector3.new(2, 2, 2)
	TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(14, 14, 14),
		Transparency = 1,
	}):Play()
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("FF9B4A")
	light.Brightness = 6
	light.Range = 40
	light.Parent = flash
	TweenService:Create(light, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	local ring = anchorAt(position, 0.6)
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromHex("FFE2A8")
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.3, 2, 2)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, 16, 16),
		Transparency = 1,
	}):Play()
	for _ = 1, 18 do
		local s = 0.4 + math.random() * 0.8
		local dir = Vector3.new(math.random() - 0.5, math.random() * 1.6, math.random() - 0.5).Unit
		launch(CFrame.new(position), Vector3.new(s, s, s), color:Lerp(Color3.new(0, 0, 0), math.random() * 0.4), Enum.Material.Slate, dir * (18 + math.random() * 14), 0.9, true)
	end
	emitter(anchorAt(position, 1.5), AssetIds.Particles.Dust, color, 30, NumberRange.new(10, 20), 3)
	emitter(anchorAt(position, 1.5), AssetIds.Particles.Ember, Color3.fromHex("FF8A3D"), 24, NumberRange.new(12, 22), 0.6)
	LayerFX.shake(0.7, 0.6)
	SFX.play("Blast", { volume = 0.9 })
end

--- Opens a chest deco model: lid swings, coins fountain, value floats up.
function Juice.chest(model: Model, amount: number)
	local pivot = model:GetPivot()
	local hinge = pivot * CFrame.new(0, 0.9, 0.6)
	local lidParts: { BasePart } = {}
	local offsets: { CFrame } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Lid") then
			table.insert(lidParts, d)
			table.insert(offsets, hinge:Inverse() * d.CFrame)
		end
	end
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = math.min(1, (os.clock() - start) / 0.35)
		local eased = 1 - (1 - t) ^ 3
		local open = hinge * CFrame.Angles(-eased * 1.9, 0, 0)
		for i, part in lidParts do
			part.CFrame = open * offsets[i]
		end
		if t >= 1 then
			connection:Disconnect()
		end
	end)
	for _ = 1, 16 do
		local dir = Vector3.new(math.random() - 0.5, 2.5 + math.random(), math.random() - 0.5)
		local coin = launch(pivot * CFrame.new(0, 1, 0), Vector3.new(0.12, 0.6, 0.6), Color3.fromHex(Palette.gold), Enum.Material.Metal, dir * 9, 1.1, true)
		coin.part.Shape = Enum.PartType.Cylinder
	end
	emitter(anchorAt(pivot.Position + Vector3.new(0, 1.5, 0), 1.5), AssetIds.Particles.Sparkle, Color3.fromHex(Palette.gold), 30, NumberRange.new(6, 12), 0.5)
	SFX.play("ChestOpen", { volume = 0.8 })
	Juice.floatText(pivot.Position + Vector3.new(0, 4, 0), `TREASURE +${Format.cash(amount)}`, UITheme.Colors.Amber, true)
	task.delay(1.4, function()
		model:Destroy()
	end)
end

--- Breaking into a free-fall pocket: a puff of dust follows you down.
function Juice.pocket(position: Vector3, color: Color3)
	emitter(anchorAt(position, 1.5), AssetIds.Particles.Dust, color, 18, NumberRange.new(4, 9), 2.2)
	SFX.play("PocketFall", { volume = 0.7 })
end

--- Counts a number up over `duration` with Quad-out easing; `fn` gets each frame.
function Juice.countUp(from: number, to: number, duration: number, fn: (number) -> ())
	local start = os.clock()
	local lastTick = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = math.min(1, (os.clock() - start) / duration)
		local eased = 1 - (1 - t) * (1 - t)
		fn(from + (to - from) * eased)
		if to > from and os.clock() - lastTick > 0.05 and t < 1 then
			lastTick = os.clock()
			SFX.play("CoinTick", { pitch = 0.9 + eased * 0.4, volume = 0.25 })
		end
		if t >= 1 then
			connection:Disconnect()
		end
	end)
end

--- Scale punch for a GUI object (needs a UIScale child; creates one).
function Juice.punch(object: GuiObject, amount: number?)
	local scale = object:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = object
	scale.Scale = 1 + (amount or 0.12)
	TweenService:Create(scale, UITheme.Easing.Pop, { Scale = 1 }):Play()
end

function Juice.init()
	RunService.Heartbeat:Connect(step)
end

return Juice
