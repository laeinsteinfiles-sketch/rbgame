--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/LayerFX (ModuleScript)
-- One mood per layer: Lighting, Atmosphere and ColorCorrection tween together
-- when the player crosses a boundary, plus a short camera shake. The world is
-- desaturated on purpose; ore and rewards are the only saturated things.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Layers = require(ReplicatedStorage.Shared.Layers)
local Types = require(ReplicatedStorage.Shared.Types)

local LayerFX = {}

local MOOD_TWEEN = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
atmosphere.Parent = Lighting
local correction = Instance.new("ColorCorrectionEffect")
correction.Name = "LayerMood"
correction.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Name = "LayerBloom"
bloom.Intensity = 0.4
bloom.Size = 24
bloom.Threshold = 1.1
bloom.Parent = Lighting

local currentLayer = 0
local shakeUntil = 0
local shakeAmplitude = 0
local shakeEnabled = true

local function applyMood(mood: Types.LayerMood, instant: boolean)
	local lightingGoal = {
		Ambient = Color3.fromHex(mood.ambient),
		OutdoorAmbient = Color3.fromHex(mood.outdoorAmbient),
		FogColor = Color3.fromHex(mood.fogColor),
		FogEnd = mood.fogEnd,
		FogStart = mood.fogEnd * 0.25,
		Brightness = 2 + mood.brightness * 4,
	}
	local atmosphereGoal = {
		Color = Color3.fromHex(mood.atmosphereColor),
		Decay = Color3.fromHex(mood.atmosphereColor),
		Density = mood.atmosphereDensity,
		Haze = mood.atmosphereHaze,
		Glare = 0,
	}
	local correctionGoal = {
		Saturation = mood.saturation,
		Contrast = mood.contrast,
		TintColor = Color3.fromHex(mood.tint),
		Brightness = mood.brightness,
	}
	if instant then
		for key, value in lightingGoal do
			(Lighting :: any)[key] = value
		end
		for key, value in atmosphereGoal do
			(atmosphere :: any)[key] = value
		end
		for key, value in correctionGoal do
			(correction :: any)[key] = value
		end
		return
	end
	TweenService:Create(Lighting, MOOD_TWEEN, lightingGoal):Play()
	TweenService:Create(atmosphere, MOOD_TWEEN, atmosphereGoal):Play()
	TweenService:Create(correction, MOOD_TWEEN, correctionGoal):Play()
end

--- Small decaying camera shake. `amplitude` in studs (0.3 is a layer change).
function LayerFX.shake(amplitude: number, duration: number)
	if not shakeEnabled then
		return
	end
	shakeAmplitude = math.max(shakeAmplitude, amplitude)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

function LayerFX.setShakeEnabled(enabled: boolean)
	shakeEnabled = enabled
end

--- Returns true when the layer actually changed.
function LayerFX.setDepth(depth: number, instant: boolean?): boolean
	local index = Layers.indexAt(depth)
	if index == currentLayer then
		return false
	end
	local wasSet = currentLayer ~= 0
	currentLayer = index
	applyMood(Layers.get(index).mood, instant == true or not wasSet)
	if wasSet and not instant then
		LayerFX.shake(0.35, 0.45)
	end
	return wasSet
end

function LayerFX.currentLayer(): number
	return currentLayer
end

function LayerFX.init()
	Lighting.GlobalShadows = true
	Lighting.ClockTime = 14.5
	LayerFX.setDepth(0, true)

	local camera = Workspace.CurrentCamera
	local rng = Random.new()
	RunService:BindToRenderStep("LayerFXShake", Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		if now >= shakeUntil then
			shakeAmplitude = 0
			return
		end
		local remaining = shakeUntil - now
		local falloff = math.min(1, remaining / 0.3)
		local a = shakeAmplitude * falloff
		camera.CFrame = camera.CFrame * CFrame.new(rng:NextNumber(-a, a), rng:NextNumber(-a, a), 0)
	end)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		camera = Workspace.CurrentCamera
	end)
end

return LayerFX
