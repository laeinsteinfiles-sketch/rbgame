--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/CameraController (ModuleScript)
-- Field-of-view kicks for big moments (blasts, pockets, layers, the core)
-- and a tiny pull-in on every dig tick. Offsets are applied on top of
-- whatever FOV the camera already has, and the "Camera shake" setting turns
-- all of it off along with LayerFX's shake.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraController = {}

local MAX_KICK = 20 -- degrees; stacked punches never exceed this
local NUDGE_DEGREES = 25 -- nudge(0.04) pulls in by 1 degree
local NUDGE_TIME = 0.1

local enabled = true
local kick = 0
local kickTime = 0.5
local kickStarted = 0
local nudge = 0
local nudgeStarted = 0
local applied = 0

--- Widens the view by `degrees`, easing back over `duration` seconds.
function CameraController.punch(degrees: number, duration: number)
	if not enabled then
		return
	end
	local now = os.clock()
	local remaining = kick * math.max(0, 1 - (now - kickStarted) / kickTime)
	kick = math.min(MAX_KICK, math.max(remaining, degrees))
	kickTime = math.max(0.1, duration)
	kickStarted = now
end

--- A short pull-in, sized as a fraction of a punch; used per dig tick.
function CameraController.nudge(amount: number)
	if not enabled then
		return
	end
	nudge = amount * NUDGE_DEGREES
	nudgeStarted = os.clock()
end

function CameraController.setEnabled(on: boolean)
	enabled = on
	if not on then
		kick = 0
		nudge = 0
	end
end

local function offsetAt(now: number): number
	local k = math.clamp((now - kickStarted) / kickTime, 0, 1)
	local n = math.clamp((now - nudgeStarted) / NUDGE_TIME, 0, 1)
	-- Quad-out on the way back so the kick lands instantly and settles softly.
	return kick * (1 - k) ^ 2 - nudge * (1 - n)
end

function CameraController.init()
	RunService:BindToRenderStep("CameraKick", Enum.RenderPriority.Camera.Value + 2, function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local offset = offsetAt(os.clock())
		if offset == applied then
			return
		end
		camera.FieldOfView = math.clamp(camera.FieldOfView - applied + offset, 1, 120)
		applied = offset
	end)
end

return CameraController
