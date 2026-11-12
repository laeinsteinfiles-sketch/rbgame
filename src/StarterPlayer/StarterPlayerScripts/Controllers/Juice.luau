--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/Juice (ModuleScript)
-- World-space feedback: a dust puff plus bouncing rock debris when a block
-- breaks, a faceted gem that pops out and whips to the camera, rare-find
-- bursts (sparkles, shockwave, light flash, shake), floating value text and
-- number count-ups. Everything is pooled and animated from one render step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Layers = require(ReplicatedStorage.Shared.Layers)
local Types = require(ReplicatedStorage.Shared.Types)
local LayerFX = require(script.Parent.LayerFX)
local SFX = require(script.Parent.SFX)

local Juice = {}

local G = GameConfig.Geometry
local H = G.BlockHeight
local HALF = G.BlockSize / 2
local TAU = 2 * math.pi
local GRAVITY = 70
local DEBRIS_PER_BREAK = 8
local POP_RISE, POP_HOLD, POP_FLY = 0.36, 0.2, 0.3
local RING_TIME = 0.45
local WHITE = Color3.new(1, 1, 1)
local RELIC_GOLD = Color3.fromHex("FFC93C")
local GEM_TILT = CFrame.Angles(math.rad(45), 0, math.rad(35.26)) -- cube balanced on a vertex
local FACET_TURN = CFrame.Angles(0, math.pi / 3, 0)
local NUGGET_OFFSET = CFrame.new(0.38, -0.12, 0.22) * CFrame.Angles(0.6, 0.4, 0)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local POP_IN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FLOAT_RISE = TweenInfo.new(1.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLOAT_FADE = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.65)

local folder = Instance.new("Folder")
folder.Name = "LocalJuice"
folder.Parent = Workspace

local rng = Random.new()

type Debris = {
	part: Part,
	pos: Vector3,
	vel: Vector3,
	spin: Vector3,
	rot: Vector3,
	age: number,
	life: number,
	size: number,
	floorY: number,
	cx: number,
	cz: number,
}

type Pop = {
	core: Part,
	facet: Part,
	glint: Part,
	burst: ParticleEmitter,
	light: PointLight,
	origin: Vector3,
	from: Vector3,
	age: number,
	scale: number,
	gem: boolean,
	rare: boolean,
	tilt: CFrame,
	flash: number,
}

type Ring = { part: Part, age: number, size: number }
type Dust = { part: Part, puff: ParticleEmitter }
type Float = { gui: BillboardGui, label: TextLabel, stroke: UIStroke, scale: UIScale, anchor: Attachment }

local liveDebris: { Debris } = {}
local freeDebris: { Debris } = {}
local livePops: { Pop } = {}
local freePops: { Pop } = {}
local liveRings: { Ring } = {}
local freeRings: { Ring } = {}
local freeDust: { Dust } = {}
local freeFloats: { Float } = {}

local function fxPart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function material(name: string): Enum.Material
	local found = (Enum.Material :: any)[name]
	return if found then found else Enum.Material.Slate
end

-- Constructors --------------------------------------------------------------------

local function newDebris(): Debris
	return {
		part = fxPart("Debris"),
		pos = Vector3.zero,
		vel = Vector3.zero,
		spin = Vector3.zero,
		rot = Vector3.zero,
		age = 0,
		life = 1,
		size = 1,
		floorY = 0,
		cx = 0,
		cz = 0,
	}
end

local function newPop(): Pop
	local core = fxPart("OrePop")
	local facet = fxPart("OreFacet")
	local glint = fxPart("OreGlint")
	glint.Shape = Enum.PartType.Ball
	glint.Material = Enum.Material.Neon
	glint.Color = WHITE
	glint.Size = Vector3.one * 0.32
	local burst = Instance.new("ParticleEmitter")
	burst.Name = "Burst"
	burst.Texture = AssetIds.Particles.Sparkle
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.45, 0.9)
	burst.Speed = NumberRange.new(7, 14)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Drag = 4
	burst.Size = NumberSequence.new(0.7, 0)
	burst.Transparency = NumberSequence.new(0, 1)
	burst.RotSpeed = NumberRange.new(-180, 180)
	burst.LightEmission = 1
	burst.Parent = core
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 0
	light.Shadows = false
	light.Parent = core
	return {
		core = core,
		facet = facet,
		glint = glint,
		burst = burst,
		light = light,
		origin = Vector3.zero,
		from = Vector3.zero,
		age = 0,
		scale = 1,
		gem = false,
		rare = false,
		tilt = CFrame.identity,
		flash = 0,
	}
end

local function newRing(): Ring
	local part = fxPart("Shockwave")
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	return { part = part, age = 0, size = 1 }
end

local function newDust(): Dust
	local part = fxPart("Dust")
	part.Transparency = 1
	part.Size = Vector3.new(G.BlockSize - 1, 0.5, G.BlockSize - 1)
	local puff = Instance.new("ParticleEmitter")
	puff.Name = "Puff"
	puff.Texture = AssetIds.Particles.Dust
	puff.Rate = 0
	puff.Lifetime = NumberRange.new(0.5, 1)
	puff.Speed = NumberRange.new(3, 7)
	puff.SpreadAngle = Vector2.new(70, 70)
	puff.EmissionDirection = Enum.NormalId.Top
	puff.Drag = 3
	puff.Acceleration = Vector3.new(0, -2, 0)
	puff.RotSpeed = NumberRange.new(-60, 60)
	puff.Size = NumberSequence.new(1.3, 3.4)
	puff.Transparency = NumberSequence.new(0.3, 1)
	puff.Parent = part
	return { part = part, puff = puff }
end

local function newFloat(): Float
	local anchor = Instance.new("Attachment")
	anchor.Name = "FloatAnchor"
	local gui = Instance.new("BillboardGui")
	gui.Name = "FloatText"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(280, 76)
	gui.MaxDistance = 150
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = UITheme.Font.Display
	label.TextSize = 30
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Colors.Ink
	stroke.Thickness = UITheme.TextStroke + 0.5
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	return { gui = gui, label = label, stroke = stroke, scale = scale, anchor = anchor }
end

-- Animation -----------------------------------------------------------------------

local function backOut(t: number): number
	local c1 = 1.70158
	local u = t - 1
	return 1 + (c1 + 1) * u * u * u + c1 * u * u
end

local function stepDebris(dt: number)
	for i = #liveDebris, 1, -1 do
		local d = liveDebris[i]
		d.age += dt
		if d.age >= d.life then
			d.part.Parent = nil
			liveDebris[i] = liveDebris[#liveDebris]
			liveDebris[#liveDebris] = nil
			table.insert(freeDebris, d)
		else
			d.vel += Vector3.new(0, -GRAVITY * dt, 0)
			local pos = d.pos + d.vel * dt
			local half = d.size * 0.5
			-- Bounce on the next block and off the shaft walls.
			if pos.Y - half < d.floorY then
				pos = Vector3.new(pos.X, d.floorY + half, pos.Z)
				d.vel = Vector3.new(d.vel.X * 0.55, math.abs(d.vel.Y) * 0.32, d.vel.Z * 0.55)
			end
			local limit = HALF - half - 0.1
			local dx, dz = pos.X - d.cx, pos.Z - d.cz
			if math.abs(dx) > limit then
				pos = Vector3.new(d.cx + math.sign(dx) * limit, pos.Y, pos.Z)
				d.vel = Vector3.new(-d.vel.X * 0.4, d.vel.Y, d.vel.Z)
			end
			if math.abs(dz) > limit then
				pos = Vector3.new(pos.X, pos.Y, d.cz + math.sign(dz) * limit)
				d.vel = Vector3.new(d.vel.X, d.vel.Y, -d.vel.Z * 0.4)
			end
			d.pos = pos
			d.rot += d.spin * dt
			local t = d.age / d.life
			local s = if t > 0.6 then d.size * (1 - (t - 0.6) / 0.4) else d.size
			d.part.Size = Vector3.one * math.max(s, 0.05)
			d.part.CFrame = CFrame.new(pos) * CFrame.Angles(d.rot.X, d.rot.Y, d.rot.Z)
		end
	end
end

local function releasePop(i: number)
	local pop = livePops[i]
	pop.core.Parent = nil
	pop.facet.Parent = nil
	pop.glint.Parent = nil
	pop.light.Brightness = 0
	livePops[i] = livePops[#livePops]
	livePops[#livePops] = nil
	table.insert(freePops, pop)
end

local function stepPops(dt: number)
	local camera = Workspace.CurrentCamera
	for i = #livePops, 1, -1 do
		local pop = livePops[i]
		pop.age += dt
		local age = pop.age
		local pos: Vector3
		local s: number
		if age < POP_RISE then
			local e = backOut(age / POP_RISE)
			pos = pop.origin + Vector3.new(0, 0.6 + 3.4 * e, 0)
			s = pop.scale * (0.35 + 0.65 * e)
		elseif age < POP_RISE + POP_HOLD then
			pos = pop.origin + Vector3.new(0, 4 + math.sin((age - POP_RISE) * 12) * 0.12, 0)
			s = pop.scale
			pop.from = pos
		elseif age < POP_RISE + POP_HOLD + POP_FLY and camera then
			-- Whip toward the bottom of the screen, as if into the backpack.
			local u = (age - POP_RISE - POP_HOLD) / POP_FLY
			local e = u * u
			local target = (camera.CFrame * CFrame.new(0, -2.2, -5)).Position
			pos = pop.from:Lerp(target, e)
			s = pop.scale * (1 - 0.8 * e)
		else
			releasePop(i)
			continue
		end
		local turn = CFrame.Angles(0, age * 6, 0)
		local frame = CFrame.new(pos) * turn
		pop.core.Size = Vector3.one * s
		pop.core.CFrame = frame * pop.tilt
		if pop.gem then
			pop.facet.Size = Vector3.one * (s * 0.86)
			pop.facet.CFrame = frame * FACET_TURN * pop.tilt
		else
			pop.facet.Size = Vector3.one * (s * 0.62)
			pop.facet.CFrame = frame * pop.tilt * NUGGET_OFFSET
		end
		if pop.rare then
			local orbit = age * 9
			pop.glint.CFrame =
				CFrame.new(pos + Vector3.new(math.cos(orbit) * s * 0.9, s * 0.45, math.sin(orbit) * s * 0.9))
		end
		local fade = math.max(0, 1 - age / 0.5)
		pop.light.Brightness = pop.flash * fade * fade
	end
end

local function stepRings(dt: number)
	for i = #liveRings, 1, -1 do
		local ring = liveRings[i]
		ring.age += dt
		local t = ring.age / RING_TIME
		if t >= 1 then
			ring.part.Parent = nil
			liveRings[i] = liveRings[#liveRings]
			liveRings[#liveRings] = nil
			table.insert(freeRings, ring)
		else
			local e = 1 - (1 - t) * (1 - t)
			local d = 1 + (ring.size - 1) * e
			ring.part.Size = Vector3.new(0.12, d, d)
			ring.part.Transparency = 0.35 + 0.65 * t
		end
	end
end

RunService:BindToRenderStep("JuiceWorldFX", Enum.RenderPriority.Camera.Value + 5, function(dt: number)
	if #liveDebris > 0 then
		stepDebris(dt)
	end
	if #livePops > 0 then
		stepPops(dt)
	end
	if #liveRings > 0 then
		stepRings(dt)
	end
end)

-- Spawners ------------------------------------------------------------------------

local function spawnDebris(center: Vector3, color: Color3, mat: Enum.Material, big: boolean)
	local d = table.remove(freeDebris) or newDebris()
	local angle = rng:NextNumber(0, TAU)
	local radius = rng:NextNumber(0.4, 2.8)
	local out = rng:NextNumber(3, 8)
	d.pos = center + Vector3.new(math.cos(angle) * radius, H / 2 + rng:NextNumber(-0.6, 0.4), math.sin(angle) * radius)
	d.vel = Vector3.new(math.cos(angle) * out, rng:NextNumber(10, 17), math.sin(angle) * out)
	d.spin = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9))
	d.rot = Vector3.zero
	d.age = 0
	d.life = rng:NextNumber(0.75, 1.05)
	d.size = if big then rng:NextNumber(1, 1.3) else rng:NextNumber(0.4, 0.85)
	d.floorY = center.Y - H / 2 -- top of the block underneath
	d.cx, d.cz = center.X, center.Z
	local h, s, v = color:ToHSV()
	d.part.Color = Color3.fromHSV(h, s, math.clamp(v + rng:NextNumber(-0.1, 0.08), 0, 1))
	d.part.Material = mat
	d.part.Size = Vector3.one * d.size
	d.part.CFrame = CFrame.new(d.pos)
	d.part.Parent = folder
	table.insert(liveDebris, d)
end

local function spawnPop(origin: Vector3, color: Color3, mat: Enum.Material, gem: boolean, rare: boolean, scale: number)
	local pop = table.remove(freePops) or newPop()
	pop.origin = origin
	pop.from = origin
	pop.age = 0
	pop.scale = scale
	pop.gem = gem
	pop.rare = rare
	pop.flash = if rare then 8 else 1.5
	pop.tilt = if gem then GEM_TILT else CFrame.Angles(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), 0)
	pop.core.Color = color
	pop.core.Material = mat
	pop.facet.Color = color:Lerp(WHITE, 0.18)
	pop.facet.Material = mat
	local glass = mat == Enum.Material.Glass
	pop.core.Transparency = if glass then 0.08 else 0
	pop.facet.Transparency = if glass then 0.08 else 0
	pop.core.Reflectance = if glass or mat == Enum.Material.Metal then 0.25 else 0
	pop.facet.Reflectance = pop.core.Reflectance
	pop.core.Size = Vector3.one * scale * 0.35
	pop.core.CFrame = CFrame.new(origin) * pop.tilt
	pop.facet.Size = pop.core.Size
	pop.facet.CFrame = pop.core.CFrame
	pop.glint.CFrame = CFrame.new(origin)
	pop.light.Color = color
	pop.light.Brightness = pop.flash
	pop.core.Parent = folder
	pop.facet.Parent = folder
	pop.glint.Parent = if rare then folder else nil
	pop.burst.Color = ColorSequence.new(color:Lerp(WHITE, 0.35))
	pop.burst:Emit(if rare then 42 else 16)
	table.insert(livePops, pop)
end

local function spawnRing(position: Vector3, color: Color3)
	local ring = table.remove(freeRings) or newRing()
	ring.age = 0
	ring.size = G.BlockSize - 0.6
	ring.part.Color = color
	ring.part.Size = Vector3.new(0.12, 1, 1)
	ring.part.Transparency = 0.35
	ring.part.CFrame = CFrame.new(position) * UPRIGHT
	ring.part.Parent = folder
	table.insert(liveRings, ring)
end

-- Public --------------------------------------------------------------------------

--- Ore pops up out of the block, hangs, then whips toward the camera.
function Juice.orePop(position: Vector3, roll: Types.BlockRoll)
	local ore = Economy.oreById[roll.oreId or ""]
	local mutation = Economy.mutationById[roll.mutationId or "none"]
	local mutationId = if mutation then mutation.id else "none"
	local mutated = mutationId ~= "none"
	local rarity = if ore then ore.rarity else 3
	local rare = roll.relic or rarity >= 3 or mutated
	local top = position + Vector3.new(0, H / 2, 0)

	if ore then
		local color = Color3.fromHex(ore.color)
		local mat = material(ore.material)
		local gem = ore.material == "Glass" or mutated
		if mutation and mutated then
			color = color:Lerp(Color3.fromHex(mutation.color), 0.45)
			mat = if mutationId == "flawless" then Enum.Material.Glass else Enum.Material.Neon
		elseif rarity >= 3 then
			mat = Enum.Material.Neon
		end
		spawnPop(position, color, mat, gem, rare, 1.25 + rarity * 0.12 + (if mutated then 0.25 else 0))
		if rare then
			spawnRing(top + Vector3.new(0, 0.15, 0), color)
		end
	end
	if roll.relic then
		spawnPop(position + Vector3.new(0.8, 0, -0.6), RELIC_GOLD, Enum.Material.Neon, true, true, 1.9)
		spawnRing(top + Vector3.new(0, 0.2, 0), RELIC_GOLD)
	end

	if rare then
		SFX.play("RareSting", { pitch = if roll.relic then 0.9 else 1 })
		local big = roll.relic or rarity >= 5 or mutationId == "molten" or mutationId == "ancient"
		LayerFX.shake(if big then 0.24 else 0.14, if big then 0.32 else 0.22)
	end
	SFX.play("OreChime", { pitch = 0.85 + rarity * 0.08, volume = 0.5 })

	if ore then
		local value = Economy.oreValue(ore.id, roll.mutationId)
		local text = `+${Format.cash(value)}`
		local color = UITheme.Colors.Gold
		if mutation and mutated then
			text = `{string.upper(mutation.name)} {text}`
			color = Color3.fromHex(mutation.color)
		elseif rarity >= 3 then
			color = UITheme.rarity(rarity).color
		end
		Juice.floatText(top + Vector3.new(0, 1, 0), text, color, 28 + rarity * 4 + (if mutated then 6 else 0))
	end
	if roll.relic then
		Juice.floatText(top + Vector3.new(0, 2.6, 0), "RELIC!", UITheme.Colors.Gold, 46)
	end
end

--- Dust puff in the layer's colour plus rock chunks that pop out and bounce.
function Juice.blockBreak(position: Vector3, groundColor: Color3)
	local dust = table.remove(freeDust) or newDust()
	dust.part.CFrame = CFrame.new(position + Vector3.new(0, H / 2, 0))
	dust.part.Parent = folder
	dust.puff.Color = ColorSequence.new(groundColor:Lerp(WHITE, 0.2))
	dust.puff:Emit(16)
	SFX.play("BlockBreak", { pitch = 0.9 + math.random() * 0.2, volume = 0.5 })
	task.delay(1.4, function()
		dust.part.Parent = nil
		table.insert(freeDust, dust)
	end)

	local layer = Layers.layerAt(math.max(0, math.floor((G.SurfaceY - position.Y) / H)))
	local mat = material(layer.material)
	for i = 1, DEBRIS_PER_BREAK do
		spawnDebris(position, groundColor, mat, i <= 2)
	end
end

--- Floating label in the display font with an ink outline. `size` defaults to 30.
function Juice.floatText(position: Vector3, text: string, color: Color3, size: number?)
	local float = table.remove(freeFloats) or newFloat()
	local textSize = size or 30
	float.label.Text = text
	float.label.TextColor3 = color
	float.label.TextSize = textSize
	float.label.TextTransparency = 0
	float.stroke.Transparency = 0
	float.stroke.Thickness = math.max(UITheme.TextStroke, textSize / 12)
	float.scale.Scale = 0.3
	float.anchor.Position = position -- Terrain's CFrame is identity, so Position is world space
	float.anchor.Parent = Workspace.Terrain
	float.gui.Adornee = float.anchor
	float.gui.StudsOffsetWorldSpace = Vector3.zero
	float.gui.Parent = folder
	TweenService:Create(float.scale, POP_IN, { Scale = 1 }):Play()
	TweenService:Create(float.gui, FLOAT_RISE, { StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0) }):Play()
	TweenService:Create(float.stroke, FLOAT_FADE, { Transparency = 1 }):Play()
	local fade = TweenService:Create(float.label, FLOAT_FADE, { TextTransparency = 1 })
	fade:Play()
	fade.Completed:Connect(function()
		float.gui.Parent = nil
		float.anchor.Parent = nil
		table.insert(freeFloats, float)
	end)
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

return Juice
