--!strict
-- Explorer: ReplicatedStorage/Shared/Models/EggModels (ModuleScript)
-- Eggs for the hub shrine, the egg screen and the hatch sequence. The egg
-- silhouette is three stacked balls (wide base, narrow crown); each egg type
-- gets its own surface story so they read apart at thumbnail size.

local GameConfig = require(script.Parent.Parent.Parent.Config.GameConfig)
local Kit = require(script.Parent.ModelKit)

local EggModels = {}

EggModels.Height = 2.9

local eggById: { [string]: typeof(GameConfig.Eggs[1]) } = {}
for _, egg in GameConfig.Eggs do
	eggById[egg.id] = egg
end

-- Point on the egg surface at height y (0..Height) and angle a, pushed out by `lift`.
local function surface(y: number, a: number, lift: number): Vector3
	local r: number
	if y < 1.35 then
		r = math.sqrt(math.max(0, 1 - (y - 1) ^ 2))
	elseif y < 2.15 then
		r = math.sqrt(math.max(0, 0.64 - (y - 1.75) ^ 2))
	else
		r = math.sqrt(math.max(0, 0.3 - (y - 2.35) ^ 2))
	end
	r += lift
	return Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
end

local DECOR: { [string]: (m: Model, egg: typeof(GameConfig.Eggs[1])) -> () } = {
	dusty = function(m, egg)
		for i = 0, 10 do
			local y = 0.5 + Kit.jitter(i, 1) * 1.9
			local a = Kit.jitter(i, 2) * math.pi * 2
			Kit.ball(m, 0.22 + Kit.jitter(i, 3) * 0.22, CFrame.new(surface(y, a, -0.06)), egg.spots)
		end
	end,
	crystal = function(m, egg)
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2 + 0.3
			local y = 0.7 + (i % 2) * 0.55
			local base = surface(y, a, -0.12)
			local outward = Vector3.new(math.cos(a), 0, math.sin(a))
			local cf = CFrame.lookAt(base, base + outward) * CFrame.Angles(-math.pi / 2 + 0.5, 0, 0)
			Kit.crystal(m, 0.28, 0.32, 0.22, cf, egg.spots, { material = Enum.Material.Glass, transparency = 0.05 })
		end
		Kit.cylY(m, 0.12, 2.04, CFrame.new(0, 1.0, 0), egg.spots)
	end,
	core = function(m, egg)
		-- Glowing seams: short neon strips hugging the shell.
		for i = 0, 6 do
			local a = i / 7 * math.pi * 2
			local y = 0.55 + Kit.jitter(i, 7) * 1.6
			local p = surface(y, a, -0.03)
			local outward = Vector3.new(math.cos(a), 0, math.sin(a))
			Kit.block(m, Vector3.new(0.08, 0.55, 0.05), CFrame.lookAt(p, p + outward) * CFrame.Angles(0, 0, (i % 2 - 0.5) * 0.9), egg.spots, {
				material = Enum.Material.Neon,
			})
		end
		local heart = m:FindFirstChild("Shell")
		if heart then
			Kit.light(heart, egg.spots, 1.6, 10)
		end
	end,
}

--- Egg standing on the origin (base at y = 0). `nest` adds a twig ring.
function EggModels.build(eggId: string, nest: boolean?): Model
	local egg = eggById[eggId] or GameConfig.Eggs[1]
	local m = Kit.model(egg.name)
	local shell = Kit.ball(m, 2, CFrame.new(0, 1, 0), egg.shell, { name = "Shell" })
	Kit.ball(m, 1.6, CFrame.new(0, 1.75, 0), egg.shell)
	Kit.ball(m, 1.1, CFrame.new(0, 2.35, 0), egg.shell)
	-- Soft top highlight so the egg reads round under flat lighting.
	Kit.ball(m, 0.5, CFrame.new(-0.28, 2.42, -0.3), Kit.shade(egg.shell, 0.35), { shadow = false })
	DECOR[egg.id](m, egg)
	if nest then
		for i = 0, 13 do
			local a = i / 14 * math.pi * 2
			local cf = CFrame.new(math.cos(a) * 1.05, 0.12, math.sin(a) * 1.05) * CFrame.Angles(0, -a + 0.4, 0.15)
			Kit.cylX(m, 0.9, 0.16, cf, if i % 2 == 0 then "8A6545" else "6E5136", { material = Enum.Material.Wood })
		end
	end
	m.PrimaryPart = shell
	return m
end

return EggModels
