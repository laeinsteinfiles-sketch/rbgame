--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/Juice (ModuleScript)
-- World-space feedback: rock chips and dust on every swing, debris when a
-- cell breaks, ore nuggets that fly into the player, floating reward text,
-- TNT blasts and chest coin bursts. Everything is local, short-lived and
-- capped so a long dig never accumulates parts.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Juice = {}

local MAX_DEBRIS = 60
local rng = Random.new()

local folder = Instance.new("Folder")
folder.Name = "LocalJuice"
folder.Parent = Workspace

local liveDebris = 0

local DISPLAY_FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)

local function emitterPart(texture: string, lightEmission: number): (Part, ParticleEmitter)
	local p = Instance.new("Part")
	p.Name = "Emitter"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Parent = folder
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Rate = 0
	e.LightEmission = lightEmission
	e.Parent = p
	return p, e
end

local dustPart, dust = emitterPart("rbxasset://textures/particles/smoke_main.dds", 0)
dust.Lifetime = NumberRange.new(0.5, 0.9)
dust.Speed = NumberRange.new(3, 7)
dust.SpreadAngle = Vector2.new(70, 70)
dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3) })
dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
dust.Drag = 4
dust.EmissionDirection = Enum.NormalId.Back

local sparkPart, sparks = emitterPart("rbxasset://textures/particles/sparkles_main.dds", 1)
sparks.Lifetime = NumberRange.new(0.4, 0.9)
sparks.Speed = NumberRange.new(6, 14)
sparks.SpreadAngle = Vector2.new(180, 180)
sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
sparks.Drag = 3

local function emitDust(position: Vector3, color: Color3, count: number)
	dustPart.CFrame = CFrame.new(position)
	dust.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.25))
	dust:Emit(count)
end

function Juice.sparkle(position: Vector3, color: Color3, count: number)
	sparkPart.CFrame = CFrame.new(position)
	sparks.Color = ColorSequence.new(color)
	sparks:Emit(count)
end

--- Physical rock chips with a short life. Capped globally.
function Juice.chips(position: Vector3, color: Color3, count: number, speed: number)
	for _ = 1, count do
		if liveDebris >= MAX_DEBRIS then
			return
		end
		liveDebris += 1
		local s = rng:NextNumber(0.35, 0.85)
		local p = Instance.new("Part")
		p.Name = "Chip"
		p.Size = Vector3.new(s, s * rng:NextNumber(0.6, 1), s)
		p.Color = color:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.25))
		p.Material = Enum.Material.Slate
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.CFrame = CFrame.new(position + rng:NextUnitVector() * 0.8) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		p.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-1, 1) * speed, rng:NextNumber(0.4, 1.2) * speed, rng:NextNumber(0.2, 1) * speed)
		p.AssemblyAngularVelocity = rng:NextUnitVector() * 12
		p.Parent = folder
		task.delay(0.9, function()
			liveDebris -= 1
			p:Destroy()
		end)
	end
end

--- One pickaxe swing landing on a cell face.
function Juice.hit(position: Vector3, color: Color3)
	emitDust(position, color, 3)
	Juice.chips(position, color, 2, 10)
end

--- A cell breaking apart.
function Juice.cellBreak(position: Vector3, color: Color3)
	emitDust(position, color, 10)
	Juice.chips(position, color, 7, 16)
end

function Juice.floatText(position: Vector3, text: string, color: Color3, scale: number?)
	local size = scale or 1
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(math.floor(220 * size), math.floor(60 * size))
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.Adornee = attachment
	gui.Parent = attachment
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = DISPLAY_FONT
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex("14161C")
	stroke.Thickness = 3
	stroke.Parent = label
	local scaleObj = Instance.new("UIScale")
	scaleObj.Scale = 0.4
	scaleObj.Parent = label
	TweenService:Create(scaleObj, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(gui, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 4, 0) }):Play()
	local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.75)
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	Debris:AddItem(attachment, 1.2)
end

local function rootPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

--- An ore nugget pops out of the rock and flies into the player.
function Juice.collect(position: Vector3, color: Color3, material: Enum.Material, glow: boolean, onArrive: (() -> ())?)
	local p = Instance.new("Part")
	p.Name = "Collect"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * 1.4
	p.Color = color
	p.Material = if glow then Enum.Material.Neon else material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.new(position)
	p.Parent = folder
	if glow then
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = 8
		l.Brightness = 2
		l.Parent = p
	end
	local up = TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = CFrame.new(position + Vector3.new(0, 2.2, 1.5)) })
	up:Play()
	up.Completed:Connect(function()
		local target = rootPosition() or position
		local fly = TweenService:Create(p, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(target), Size = Vector3.one * 0.5 })
		fly:Play()
		fly.Completed:Connect(function()
			p:Destroy()
			if onArrive then
				onArrive()
			end
		end)
	end)
end

--- Gold coins burst out of a chest, then funnel into the player.
function Juice.coins(position: Vector3, count: number)
	for i = 1, count do
		local coin = Instance.new("Part")
		coin.Name = "Coin"
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.25, 1.1, 1.1)
		coin.Color = Color3.fromHex("FFC83D")
		coin.Material = Enum.Material.Metal
		coin.Anchored = true
		coin.CanCollide = false
		coin.CanQuery = false
		coin.CanTouch = false
		coin.CastShadow = false
		local burst = position + Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(1.5, 4), rng:NextNumber(0.5, 3))
		coin.CFrame = CFrame.new(position)
		coin.Parent = folder
		local out = TweenService:Create(coin, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(burst) * CFrame.Angles(0, rng:NextNumber(0, 6), math.pi / 2) })
		task.delay(i * 0.02, function()
			out:Play()
		end)
		out.Completed:Connect(function()
			local target = rootPosition() or position
			local fly = TweenService:Create(coin, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.15 + i * 0.02), { CFrame = CFrame.new(target) })
			fly:Play()
			fly.Completed:Connect(function()
				coin:Destroy()
			end)
		end)
	end
end

function Juice.explosion(position: Vector3)
	local blast = Instance.new("Explosion")
	blast.Position = position
	blast.BlastPressure = 0
	blast.BlastRadius = 8
	blast.DestroyJointRadiusPercent = 0
	blast.ExplosionType = Enum.ExplosionType.NoCraters
	blast.Parent = Workspace
	emitDust(position, Color3.fromHex("6B5B4B"), 24)
	Juice.chips(position, Color3.fromHex("5A4A3A"), 14, 26)
	Juice.sparkle(position, Color3.fromHex("FFB13D"), 20)
end

return Juice
