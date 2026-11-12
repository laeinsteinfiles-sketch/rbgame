--!strict
-- Explorer: ServerScriptService/Services/WorldService (ModuleScript)
-- The sky and the light. Bright, warm, saturated daylight on the surface;
-- each client's LayerFX darkens and tints this locally as its player digs.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local WorldService = {}

local function ensure<T>(className: string, name: string, parent: Instance): T
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing :: any
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created :: any
end

function WorldService.init()
	Lighting.ClockTime = 14.2
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromHex("8A7A6A")
	Lighting.OutdoorAmbient = Color3.fromHex("9C8C7A")
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.FogEnd = 100000

	local sky: Sky = ensure("Sky", "Sky", Lighting)
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 8
	sky.StarCount = 1500

	local atmosphere: Atmosphere = ensure("Atmosphere", "Atmosphere", Lighting)
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromHex("C7E6FF")
	atmosphere.Decay = Color3.fromHex("8FB6D9")
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2

	local bloom: BloomEffect = ensure("BloomEffect", "Bloom", Lighting)
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.6

	local rays: SunRaysEffect = ensure("SunRaysEffect", "SunRays", Lighting)
	rays.Intensity = 0.06
	rays.Spread = 0.6

	local grade: ColorCorrectionEffect = ensure("ColorCorrectionEffect", "Grade", Lighting)
	grade.Saturation = 0.12
	grade.Contrast = 0.06
	grade.Brightness = 0.02

	local clouds: Clouds = ensure("Clouds", "Clouds", Workspace.Terrain)
	clouds.Cover = 0.55
	clouds.Density = 0.55
	clouds.Color = Color3.fromHex("FFFFFF")
end

return WorldService
