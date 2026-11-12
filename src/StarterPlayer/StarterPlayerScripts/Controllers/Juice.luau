--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/Juice (ModuleScript)
-- World-space feedback: ore pop-outs, dust bursts, floating value text and
-- number count-ups. Every tween names its easing on purpose.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local LayerFX = require(script.Parent.LayerFX)
local SFX = require(script.Parent.SFX)

local Juice = {}

local POP_UP = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_AWAY = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FLOAT = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local folder = Instance.new("Folder")
folder.Name = "LocalJuice"
folder.Parent = Workspace

local freePops: { Part } = {}
local freeDust: { Part } = {}
local freeFloats: { BillboardGui } = {}

local function newPop(): Part
	local part = Instance.new("Part")
	part.Name = "OrePop"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = Vector3.new(1.6, 1.6, 1.6)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Burst"
	emitter.Texture = AssetIds.Particles.Sparkle
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(6, 10)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.LightEmission = 1
	emitter.Parent = part
	return part
end

local function newDust(): Part
	local part = Instance.new("Part")
	part.Name = "Dust"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(4, 1, 4)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Puff"
	emitter.Texture = AssetIds.Particles.Dust
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Size = NumberSequence.new(1.5, 3)
	emitter.Transparency = NumberSequence.new(0.5, 1)
	emitter.Parent = part
	return part
end

local function newFloat(): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "FloatText"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(120, 40)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = UITheme.Font.Display
	label.TextSize = 26
	label.TextStrokeTransparency = 0.6
	label.TextStrokeColor3 = UITheme.Colors.PanelInset
	label.Parent = gui
	return gui
end

--- Ore pops up out of the block, hangs, then whips toward the camera.
function Juice.orePop(position: Vector3, roll: Types.BlockRoll)
	local ore = Economy.oreById[roll.oreId or ""]
	local mutation = Economy.mutationById[roll.mutationId or "none"]
	local part = table.remove(freePops) or newPop()
	local color = if roll.relic then Color3.fromHex("F2B33D") else Color3.fromHex(if ore then ore.color else "FFFFFF")
	local rare = roll.relic or (ore ~= nil and ore.rarity >= 3) or (mutation ~= nil and mutation.id ~= "none")
	if mutation and mutation.id ~= "none" then
		color = color:Lerp(Color3.fromHex(mutation.color), 0.45)
	end
	part.Color = color
	part.Material = if rare then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Size = Vector3.new(1.6, 1.6, 1.6)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0.4, 0.6, 0.2)
	part.Parent = folder

	local burst = part:FindFirstChild("Burst") :: ParticleEmitter
	burst.Color = ColorSequence.new(color)
	if rare then
		burst:Emit(28)
		SFX.play("RareSting", { pitch = if roll.relic then 0.9 else 1 })
		LayerFX.shake(0.12, 0.2)
	end
	local rarity = if ore then ore.rarity else 3
	SFX.play("OreChime", { pitch = 0.85 + rarity * 0.08, volume = 0.5 })

	local up = TweenService:Create(part, POP_UP, {
		CFrame = CFrame.new(position + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, 1.2, 0.3),
		Size = Vector3.new(2.2, 2.2, 2.2),
	})
	up:Play()
	up.Completed:Connect(function()
		local camera = Workspace.CurrentCamera
		local target = camera.CFrame.Position + camera.CFrame.LookVector * 4 - camera.CFrame.RightVector * 2
		local away = TweenService:Create(part, POP_AWAY, { CFrame = CFrame.new(target), Size = Vector3.new(0.2, 0.2, 0.2) })
		away:Play()
		away.Completed:Connect(function()
			part.Parent = nil
			table.insert(freePops, part)
		end)
	end)

	local value = if roll.relic then "Relic" else `+{Format.cash(Economy.oreValue(roll.oreId or "", roll.mutationId))}`
	Juice.floatText(position + Vector3.new(1.5, 1, 0), value, if roll.relic then UITheme.Colors.Amber else UITheme.Colors.Text)
end

--- Dust puff in the layer's own colour when a block breaks.
function Juice.blockBreak(position: Vector3, groundColor: Color3)
	local part = table.remove(freeDust) or newDust()
	part.CFrame = CFrame.new(position)
	part.Parent = folder
	local puff = part:FindFirstChild("Puff") :: ParticleEmitter
	puff.Color = ColorSequence.new(groundColor)
	puff:Emit(10)
	SFX.play("BlockBreak", { pitch = 0.9 + math.random() * 0.2, volume = 0.5 })
	task.delay(1.2, function()
		part.Parent = nil
		table.insert(freeDust, part)
	end)
end

function Juice.floatText(position: Vector3, text: string, color: Color3)
	local gui = table.remove(freeFloats) or newFloat()
	local label = gui:FindFirstChild("Label") :: TextLabel
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	gui.StudsOffsetWorldSpace = Vector3.zero
	local anchor = Instance.new("Attachment")
	anchor.Position = position -- Terrain's CFrame is identity, so Position is world space
	anchor.Parent = Workspace:FindFirstChildOfClass("Terrain")
	gui.Adornee = anchor
	gui.Parent = folder
	local rise = TweenService:Create(gui, FLOAT, { StudsOffsetWorldSpace = Vector3.new(0, 3, 0) })
	local fade = TweenService:Create(label, FLOAT, { TextTransparency = 1 })
	rise:Play()
	fade:Play()
	fade.Completed:Connect(function()
		gui.Parent = nil
		anchor:Destroy()
		table.insert(freeFloats, gui)
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
