--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/LayerFX (ModuleScript)
-- Owns every Lighting setting. The islands get a bright, saturated, sunny
-- look; underground each layer has its own coloured ambient, haze, grade and
-- bloom. The visible mood follows where the character physically is
-- (surface, or the layer at its feet) and tweens over 1.2 s; setDepth only
-- tracks the dig layer for its return value and the boundary shake.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Layers = require(ReplicatedStorage.Shared.Layers)
local Types = require(ReplicatedStorage.Shared.Types)

local LayerFX = {}

local G = GameConfig.Geometry
local MOOD_TWEEN = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local SURFACE_KEY = 0
local CHECK_INTERVAL = 0.2
-- Feet height (studs, relative to SurfaceY) that switches surface <-> underground.
-- The gap is hysteresis so the first blocks never flicker between moods.
local ENTER_UNDERGROUND = -9
local LEAVE_UNDERGROUND = -5

-- Sunny cartoon daylight for the islands.
local SURFACE_MOOD: Types.LayerMood = {
	ambient = "7F8AA3",
	outdoorAmbient = "A2B6D8",
	fogColor = "BFE0FF",
	fogEnd = 2000,
	atmosphereColor = "C9E6FF",
	atmosphereDecay = "7DB4F5",
	atmosphereDensity = 0.27,
	atmosphereHaze = 1,
	atmosphereGlare = 0.3,
	saturation = 0.15,
	contrast = 0.06,
	tint = "FFFFFF",
	brightness = 0.02,
	sunBrightness = 3,
	exposure = 0,
	bloom = 0.35,
	sunRays = 0.08,
}

local function named<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing :: any
	end
	local made = Instance.new(className :: any)
	made.Name = name
	made.Parent = Lighting
	return made :: any
end

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
atmosphere.Offset = 0.15
atmosphere.Parent = Lighting
local correction: ColorCorrectionEffect = named("ColorCorrectionEffect", "LayerMood")
local bloom: BloomEffect = named("BloomEffect", "LayerBloom")
bloom.Size = 28
bloom.Threshold = 1.1
local sunRays: SunRaysEffect = named("SunRaysEffect", "LayerSunRays")
sunRays.Spread = 0.7

local player = Players.LocalPlayer
local currentLayer = 0
local appliedKey = -1
local nextCheck = 0
local shakeUntil = 0
local shakeAmplitude = 0
local shakeEnabled = true

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local function applyMood(mood: Types.LayerMood, instant: boolean)
	local lightingGoal = {
		Ambient = hex(mood.ambient),
		OutdoorAmbient = hex(mood.outdoorAmbient),
		FogColor = hex(mood.fogColor),
		FogEnd = mood.fogEnd,
		FogStart = mood.fogEnd * 0.25,
		Brightness = mood.sunBrightness or 2,
		ExposureCompensation = mood.exposure or 0,
	}
	local atmosphereGoal = {
		Color = hex(mood.atmosphereColor),
		Decay = hex(mood.atmosphereDecay or mood.atmosphereColor),
		Density = mood.atmosphereDensity,
		Haze = mood.atmosphereHaze,
		Glare = mood.atmosphereGlare or 0,
	}
	local correctionGoal = {
		Saturation = mood.saturation,
		Contrast = mood.contrast,
		TintColor = hex(mood.tint),
		Brightness = mood.brightness,
	}
	local bloomGoal = { Intensity = mood.bloom or 0.5 }
	local raysGoal = { Intensity = mood.sunRays or 0 }
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
		bloom.Intensity = bloomGoal.Intensity
		sunRays.Intensity = raysGoal.Intensity
		return
	end
	TweenService:Create(Lighting, MOOD_TWEEN, lightingGoal):Play()
	TweenService:Create(atmosphere, MOOD_TWEEN, atmosphereGoal):Play()
	TweenService:Create(correction, MOOD_TWEEN, correctionGoal):Play()
	TweenService:Create(bloom, MOOD_TWEEN, bloomGoal):Play()
	TweenService:Create(sunRays, MOOD_TWEEN, raysGoal):Play()
end

local function moodFor(key: number): Types.LayerMood
	return if key == SURFACE_KEY then SURFACE_MOOD else Layers.get(key).mood
end

--- Surface, or the index of the layer the character is standing in.
local function physicalKey(): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return SURFACE_KEY
	end
	local feet = root.Position.Y - 3 - G.SurfaceY
	local threshold = if appliedKey == SURFACE_KEY then ENTER_UNDERGROUND else LEAVE_UNDERGROUND
	if feet > threshold then
		return SURFACE_KEY
	end
	return Layers.indexAt(math.max(0, math.floor(-feet / G.BlockHeight)))
end

local function refreshMood(instant: boolean)
	local key = physicalKey()
	if key ~= appliedKey or instant then
		appliedKey = key
		applyMood(moodFor(key), instant)
	end
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

--- Tracks the dig layer. Returns true when the layer actually changed.
function LayerFX.setDepth(depth: number, instant: boolean?): boolean
	if instant then
		refreshMood(true)
	end
	local index = Layers.indexAt(depth)
	if index == currentLayer then
		return false
	end
	local wasSet = currentLayer ~= 0
	currentLayer = index
	-- Shake only when a boundary was just dug through, not on rides or respawns.
	if wasSet and not instant and depth - Layers.get(index).startDepth <= 2 then
		LayerFX.shake(0.35, 0.45)
	end
	return wasSet
end

function LayerFX.currentLayer(): number
	return currentLayer
end

function LayerFX.init()
	Lighting.GlobalShadows = true
	Lighting.ClockTime = 14
	Lighting.ShadowSoftness = 0.3
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.ColorShift_Top = hex("FFF0D8")
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
	LayerFX.setDepth(0, true)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now >= nextCheck then
			nextCheck = now + CHECK_INTERVAL
			refreshMood(false)
		end
	end)

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
