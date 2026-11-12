--!strict
-- Explorer: StarterGui/DigUI/Screens/Hatch (ModuleScript)
-- The hatch sequence. The server has already rolled and saved the pet; this
-- only presents it: three wobbles, a flash, then the pet at its rolled size
-- on rays in its rarity colour. Tap skips the wobbles or closes the reveal.
-- Results that arrive mid-sequence queue up.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Format = require(ReplicatedStorage.Shared.Format)
local EggModels = require(ReplicatedStorage.Shared.Models.EggModels)
local PetModels = require(ReplicatedStorage.Shared.Models.PetModels)
local Base = require(script.Parent.Parent.Components.Base)
local Label = require(script.Parent.Parent.Components.Label)

local Hatch = {}

export type Handle = {
	play: (eggId: string, petId: string, sizeId: string, duplicate: boolean) -> (),
}

type Entry = { eggId: string, petId: string, sizeId: string, duplicate: boolean }

local RAY_COUNT = 12
local AUTO_CLOSE = 8 -- seconds a reveal stays up without a tap

local petById: { [string]: typeof(GameConfig.Pets[1]) } = {}
for _, pet in GameConfig.Pets do
	petById[pet.id] = pet
end
local sizeById: { [string]: typeof(GameConfig.PetSizes[1]) } = {}
for _, size in GameConfig.PetSizes do
	sizeById[size.id] = size
end
local eggById: { [string]: typeof(GameConfig.Eggs[1]) } = {}
for _, egg in GameConfig.Eggs do
	eggById[egg.id] = egg
end

function Hatch.new(ctx: Base.Context): Handle
	-- Above the modal layer: hatching starts from the open gem shop.
	local root = Instance.new("TextButton")
	root.Name = "Hatch"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.new(0, 0, 0)
	root.BackgroundTransparency = 0.3
	root.BorderSizePixel = 0
	root.AutoButtonColor = false
	root.Text = ""
	root.Visible = false
	root.ZIndex = 10
	root.Parent = ctx.gui

	local rays = Base.frame(root, "Rays", UDim2.fromOffset(380, 380), UDim2.fromScale(0.5, 0.42), Vector2.new(0.5, 0.5))
	rays.ZIndex = 1
	local rayFrames: { Frame } = {}
	for k = 1, RAY_COUNT do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.new(0, 16, 1, 0)
		ray.Rotation = (k - 1) * 180 / RAY_COUNT
		ray.BorderSizePixel = 0
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = ray
		ray.Parent = rays
		table.insert(rayFrames, ray)
	end

	local stage = Instance.new("ViewportFrame")
	stage.Name = "Stage"
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.42)
	stage.Size = UDim2.fromOffset(240, 240)
	stage.BackgroundTransparency = 1
	stage.Ambient = Color3.fromRGB(165, 160, 150)
	stage.LightColor = Color3.fromRGB(255, 244, 225)
	stage.LightDirection = Vector3.new(-0.4, -1, 0.6)
	stage.ZIndex = 2
	stage.Parent = root
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.Parent = stage
	stage.CurrentCamera = camera

	local title = Label.new({ parent = root, text = "", size = UDim2.new(1, 0, 0, 44), position = UDim2.new(0.5, 0, 0.42, 128), anchor = Vector2.new(0.5, 0), align = Enum.TextXAlignment.Center, textSize = UITheme.TextSize.Display, display = true })
	local subtitle = Label.new({ parent = root, text = "", size = UDim2.new(1, 0, 0, 22), position = UDim2.new(0.5, 0, 0.42, 172), anchor = Vector2.new(0.5, 0), align = Enum.TextXAlignment.Center, textSize = UITheme.TextSize.Body, color = UITheme.Colors.TextDim })
	local hint = Label.new({ parent = root, text = "", size = UDim2.new(1, 0, 0, 18), position = UDim2.new(0.5, 0, 1, -16), anchor = Vector2.new(0.5, 1), align = Enum.TextXAlignment.Center, textSize = UITheme.TextSize.Small, color = UITheme.Colors.TextDim })
	for _, label in { title, subtitle, hint } do
		label.ZIndex = 3
	end

	local flash = Base.frame(root, "Flash", UDim2.fromScale(1, 1))
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.ZIndex = 4

	local queue: { Entry } = {}
	local playing = false
	local phase: "egg" | "pet" | "idle" = "idle"
	local skip = false
	local closeRequested = false
	local current: Model? = nil
	local basePivot = CFrame.identity
	local spin = 0

	local function setModel(model: Model?, frameHeight: number, centreY: number)
		if current then
			current:Destroy()
		end
		current = model
		spin = 0
		if model then
			basePivot = model:GetPivot()
			model.Parent = stage
			local distance = frameHeight / (1.1 * math.tan(math.rad(camera.FieldOfView / 2)))
			camera.CFrame = CFrame.lookAt(Vector3.new(0, centreY + frameHeight * 0.1, -distance), Vector3.new(0, centreY, 0))
		end
	end

	-- Rotates the current model about the world origin (an egg's base).
	local function pose(rotation: CFrame)
		if current then
			current:PivotTo(rotation * basePivot)
		end
	end

	local function waitOrSkip(seconds: number)
		local untilTime = os.clock() + seconds
		while os.clock() < untilTime and not skip do
			task.wait()
		end
	end

	local function wobble(k: number)
		ctx.sfx.play("HatchWobble", { pitch = 1 + k * 0.08, volume = 0.7 })
		local duration = 0.4
		local start = os.clock()
		while not skip do
			local p = (os.clock() - start) / duration
			if p >= 1 then
				break
			end
			pose(CFrame.Angles(0, 0, math.sin(p * math.pi * 3) * (1 - p) * math.rad(12 + k * 5)))
			task.wait()
		end
		pose(CFrame.identity)
	end

	local function reveal(entry: Entry)
		local pet = petById[entry.petId] or GameConfig.Pets[1]
		local size = sizeById[entry.sizeId] or GameConfig.PetSizes[1]
		local egg = eggById[entry.eggId]
		local rarity = GameConfig.Rarities[pet.tier]
		local color = Color3.fromHex(rarity.color)

		flash.BackgroundTransparency = 0
		TweenService:Create(flash, UITheme.Easing.Flash, { BackgroundTransparency = 1 }):Play()
		ctx.sfx.play("EggCrack", { volume = 0.8 })
		ctx.sfx.play("HatchReveal", { pitch = 0.9 + rarity.order * 0.06, volume = 0.9 })

		local built = PetModels.build(pet.id, size.scale)
		-- Framed for a Normal pet so Big and Huge visibly fill more of the stage.
		local normalHeight = built.height / size.scale
		setModel(built.model, normalHeight * 1.5, if built.flyer then 0 else built.height / 2)
		for _, ray in rayFrames do
			ray.BackgroundColor3 = color
		end
		rays.Visible = true

		title.Text = pet.name
		title.TextColor3 = color
		local parts = { size.name, rarity.name, `+{Format.percent(pet.gemBonus * size.mult)} gems` }
		if entry.duplicate and egg then
			table.insert(parts, `duplicate, {math.floor(egg.cost * GameConfig.DuplicateRefund)} gems back`)
		end
		subtitle.Text = table.concat(parts, "  ·  ")
		hint.Text = "Tap to continue"
		ctx.juice.punch(title, 0.25)
	end

	local function run()
		playing = true
		while #queue > 0 do
			local entry = table.remove(queue, 1) :: Entry
			local egg = eggById[entry.eggId]
			skip = false
			closeRequested = false
			phase = "egg"
			root.Visible = true
			rays.Visible = false
			flash.BackgroundTransparency = 1
			title.Text = if egg then egg.name else ""
			title.TextColor3 = UITheme.Colors.Text
			subtitle.Text = ""
			hint.Text = "Tap to skip"
			setModel(EggModels.build(entry.eggId, false), EggModels.Height * 1.4, EggModels.Height / 2)
			waitOrSkip(0.3)
			for k = 1, 3 do
				if skip then
					break
				end
				wobble(k)
				waitOrSkip(0.22)
			end
			reveal(entry)
			phase = "pet"
			local deadline = os.clock() + AUTO_CLOSE
			while not closeRequested and os.clock() < deadline do
				task.wait()
			end
		end
		phase = "idle"
		setModel(nil, 1, 0)
		root.Visible = false
		playing = false
	end

	root.Activated:Connect(function()
		if phase == "egg" then
			skip = true
		elseif phase == "pet" then
			closeRequested = true
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		if not root.Visible then
			return
		end
		rays.Rotation = (rays.Rotation + dt * 18) % 360
		if phase == "pet" then
			spin += dt * 0.9
			pose(CFrame.Angles(0, spin, 0))
		end
	end)

	return {
		play = function(eggId: string, petId: string, sizeId: string, duplicate: boolean)
			table.insert(queue, { eggId = eggId, petId = petId, sizeId = sizeId, duplicate = duplicate })
			if not playing then
				task.spawn(run)
			end
		end,
	}
end

return Hatch
