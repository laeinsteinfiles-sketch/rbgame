--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/CameraRig (ModuleScript)
-- A warm headlamp on the local character that fades in below the surface, and
-- a one-shot camera nudge that looks down the shaft whenever the character
-- arrives in it (round start, riding down). The nudge sets the default
-- camera's CFrame once; the camera module carries on from that orientation,
-- so player input is never fought.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local ClientState = require(script.Parent.ClientState)

local CameraRig = {}

local G = GameConfig.Geometry
local LOOK_PITCH = math.rad(-74) -- the default camera clamps at -80
local TELEPORT_STUDS = 6 -- a jump this big in one frame is a server PivotTo, not movement
local NUDGE_COOLDOWN = 1.5
local LAMP_COLOR = Color3.fromHex("FFD9A6")
local LAMP_RANGE = 24
local LAMP_BRIGHTNESS = 1.35
local LAMP_DEEP_BONUS = 0.5 -- extra brightness by the core, where the ambient is darkest

local player = Players.LocalPlayer
local lamp: PointLight? = nil
local lastRoot: Vector3? = nil
local nudgePending = false
local lastNudge = -math.huge

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

--- Over our own shaft column, at or below the opening.
local function inShaft(position: Vector3): boolean
	local center = ClientState.plotCenter()
	if not center then
		return false
	end
	local reach = G.BlockSize / 2 + 1
	return math.abs(position.X - center.X) <= reach
		and math.abs(position.Z - center.Z) <= reach
		and position.Y <= center.Y + 6
end

local function requestNudge()
	if os.clock() - lastNudge > NUDGE_COOLDOWN then
		nudgePending = true
	end
end

local function applyNudge()
	nudgePending = false
	local camera = Workspace.CurrentCamera
	local root = rootOf(player.Character)
	if not camera or not root or camera.CameraType ~= Enum.CameraType.Custom then
		return
	end
	lastNudge = os.clock()
	-- Keep the player's yaw and zoom; only tip the view down the shaft.
	local focus = root.Position + Vector3.new(0, 1.5, 0)
	local distance = math.clamp((camera.CFrame.Position - camera.Focus.Position).Magnitude, 2, 60)
	local _, yaw = camera.CFrame:ToEulerAnglesYXZ()
	camera.CFrame = CFrame.new(focus) * CFrame.fromEulerAnglesYXZ(LOOK_PITCH, yaw, 0) * CFrame.new(0, 0, distance)
end

local function attachLamp(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") or player.Character ~= character then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "Headlamp"
	attachment.Position = Vector3.new(0, 1.8, -0.8) -- forehead height, just in front
	local light = Instance.new("PointLight")
	light.Name = "HeadlampLight"
	light.Color = LAMP_COLOR
	light.Range = LAMP_RANGE
	light.Brightness = 0
	light.Shadows = false
	light.Parent = attachment
	attachment.Parent = root
	lamp = light
end

local function step(dt: number)
	local root = rootOf(player.Character)
	if not root then
		lastRoot = nil
		return
	end
	local position = root.Position
	if lastRoot and (position - lastRoot).Magnitude > TELEPORT_STUDS and inShaft(position) then
		requestNudge()
	end
	lastRoot = position

	local light = lamp
	if light and light.Parent then
		-- Off at the surface, full a couple of blocks down, a touch brighter deep down.
		local below = G.SurfaceY - (position.Y - 3)
		local strength = math.clamp((below - 6) / 10, 0, 1)
		local target = strength
			* (LAMP_BRIGHTNESS + LAMP_DEEP_BONUS * math.clamp(below / (GameConfig.CoreDepth * G.BlockHeight), 0, 1))
		local current = light.Brightness
		if math.abs(target - current) > 0.01 then
			light.Brightness = current + (target - current) * math.min(1, dt * 3)
		end
	end
end

function CameraRig.init()
	if player.Character then
		task.spawn(attachLamp, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		lastRoot = nil
		attachLamp(character)
	end)

	-- Round start pivots everyone onto block 1; the move can be shorter than
	-- TELEPORT_STUDS if the player was already near the shaft.
	ClientState.onRound("Phase", function(phase)
		if phase == "Active" then
			task.delay(0.35, function()
				local root = rootOf(player.Character)
				if root and inShaft(root.Position) then
					requestNudge()
				end
			end)
		end
	end)

	RunService.Heartbeat:Connect(step)
	-- After the camera module has updated, so this frame renders the new view
	-- and the module reads its orientation back next frame.
	RunService:BindToRenderStep("CameraRigNudge", Enum.RenderPriority.Camera.Value + 2, function()
		if nudgePending then
			applyNudge()
		end
	end)
end

return CameraRig
