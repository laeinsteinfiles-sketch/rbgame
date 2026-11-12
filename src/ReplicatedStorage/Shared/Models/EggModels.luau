--!strict
-- Explorer: ReplicatedStorage/Shared/Models/EggModels (ModuleScript)
-- Eggs for the hub shrine, the egg screen and the hatch sequence. One smooth
-- ellipsoid shell; each egg type gets its own surface story (speckles,
-- crystal growths, glowing seams) so they read apart at thumbnail size.

local GameConfig = require(script.Parent.Parent.Parent.Config.GameConfig)
local Kit = require(script.Parent.ModelKit)

local EggModels = {}

local A = 1.05 -- horizontal half-axis
local B = 1.42 -- vertical half-axis
local CY = B -- shell centre height; the egg stands on y = 0

EggModels.Height = 2 * B

local eggById: { [string]: typeof(GameConfig.Eggs[1]) } = {}
for _, egg in GameConfig.Eggs do
	eggById[egg.id] = egg
end

-- Frame on the shell at height y and angle a, Z axis along the outward normal.
local function onShell(y: number, a: number, lift: number): CFrame
	local t = math.clamp((y - CY) / B, -0.98, 0.98)
	local r = A * math.sqrt(1 - t * t)
	local p = Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
	local normal = Vector3.new(p.X / (A * A), (y - CY) / (B * B), p.Z / (A * A)).Unit
	return CFrame.lookAt(p + normal * lift, p + normal * (lift + 1))
end

local DECOR: { [string]: (m: Model, egg: typeof(GameConfig.Eggs[1])) -> () } = {
	dusty = function(m, egg)
		for i = 0, 13 do
			local y = 0.45 + Kit.jitter(i, 1) * 2.2
			local a = Kit.jitter(i, 2) * math.pi * 2
			local d = 0.28 + Kit.jitter(i, 3) * 0.3
			Kit.ellipsoid(m, Vector3.new(d, d * 0.8, 0.16), onShell(y, a, -0.04), egg.spots, { shadow = false })
		end
	end,
	crystal = function(m, egg)
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2 + 0.3
			local y = 0.55 + (i % 3) * 0.55
			local cf = onShell(y, a, -0.1) * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.Angles(0, math.pi / 4, 0)
			Kit.crystal(m, 0.3, 0.3, 0.4, cf, egg.spots, { material = Enum.Material.Glass, transparency = 0.05 })
		end
		for i = 0, 15 do
			local a = i / 16 * math.pi * 2
			Kit.ellipsoid(m, Vector3.new(0.5, 0.22, 0.14), onShell(CY - 0.35, a, -0.03), Kit.shade(egg.spots, 0.2), { shadow = false })
		end
	end,
	core = function(m, egg)
		-- Glowing seams hugging the shell, like magma through cracked rock.
		for i = 0, 8 do
			local a = i / 9 * math.pi * 2 + Kit.jitter(i, 5)
			local y = 0.5 + Kit.jitter(i, 7) * 1.9
			Kit.block(m, Vector3.new(0.1, 0.7, 0.06), onShell(y, a, 0) * CFrame.Angles(0, 0, (Kit.jitter(i, 8) - 0.5) * 1.6), egg.spots, {
				material = Enum.Material.Neon,
				shadow = false,
			})
		end
		local shell = m:FindFirstChild("Shell")
		if shell then
			Kit.light(shell, egg.spots, 1.6, 10)
		end
	end,
}

--- Egg standing on the origin (base at y = 0). `nest` adds a twig ring.
function EggModels.build(eggId: string, nest: boolean?): Model
	local egg = eggById[eggId] or GameConfig.Eggs[1]
	local m = Kit.model(egg.name)
	local shell = Kit.ellipsoid(m, Vector3.new(A * 2, B * 2, A * 2), CFrame.new(0, CY, 0), egg.shell, { name = "Shell" })
	-- Soft highlight so the shell reads round under flat lighting.
	Kit.ellipsoid(m, Vector3.new(0.55, 0.7, 0.2), onShell(CY + 0.75, math.rad(235), -0.02), Kit.shade(egg.shell, 0.4), { shadow = false })
	DECOR[egg.id](m, egg)
	if nest then
		for i = 0, 13 do
			local a = i / 14 * math.pi * 2
			local cf = CFrame.new(math.cos(a) * 1.1, 0.12, math.sin(a) * 1.1) * CFrame.Angles(0, -a + 0.4, 0.15)
			Kit.cylX(m, 0.95, 0.16, cf, if i % 2 == 0 then "8A6545" else "6E5136", { material = Enum.Material.Wood })
		end
	end
	m.PrimaryPart = shell
	return m
end

return EggModels
