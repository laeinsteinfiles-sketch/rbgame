--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/DigController (ModuleScript)
-- Hold-to-dig with client prediction. The client times the dig with the
-- server-replicated DigPower, resolves the same course the server will
-- (blasts, pockets, chests), plays every effect immediately, and lets the
-- server's DigResult confirm or roll back. It never sends depth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Course = require(ReplicatedStorage.Shared.Course)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Signal = require(ReplicatedStorage.Shared.Signal)
local CameraController = require(script.Parent.CameraController)
local ClientState = require(script.Parent.ClientState)
local Juice = require(script.Parent.Juice)
local LayerFX = require(script.Parent.LayerFX)
local SFX = require(script.Parent.SFX)
local ShaftRenderer = require(script.Parent.ShaftRenderer)

local DigController = {}

local G = GameConfig.Geometry
local TICKS = GameConfig.Dig.TicksPerBlock
local player = Players.LocalPlayer

local held = false
local touchHeld = false
local progress = 0
local localDepth = 0
local waitingForGround = false
local groundDeadline = 0
local lastTickStep = -1
local pendingSince: { [number]: number } = {}
local digging = false

DigController.onProgress = Signal.new() :: Signal.Signal<number>
DigController.onDepth = Signal.new() :: Signal.Signal<number>
-- (kind, index) for every special block broken locally: "blast" | "chest" | "pocket"
DigController.onSpecial = Signal.new() :: Signal.Signal<string, number>

local function digPower(): number
	return math.max(0.1, ClientState.number("DigPower", GameConfig.Drills[1].power))
end

local function expectedY(depth: number): number
	return G.SurfaceY - depth * G.BlockHeight + 3
end

local function standingOnCurrentBlock(): boolean
	local character = player.Character
	local root = ClientState.rootPart()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end
	-- Over the shaft opening, not just somewhere on the island at that height.
	local frame = ClientState.plotFrame()
	if frame then
		local rel = frame:PointToObjectSpace(root.Position)
		if math.abs(rel.X) > G.BlockSize / 2 + 1 or math.abs(rel.Z) > G.BlockSize / 2 + 1 then
			return false
		end
	end
	return math.abs(root.Position.Y - expectedY(localDepth)) < 2.5
end

local function canDig(): boolean
	if ClientState.phase() ~= "Active" or ClientState.isTraveling() then
		return false
	end
	if localDepth >= GameConfig.CoreDepth then
		return false
	end
	-- Never pile more than a few unconfirmed blocks; a rejected one would
	-- otherwise cascade into a long visible rollback.
	local pending = 0
	for _ in pendingSince do
		pending += 1
	end
	return pending < 4
end

local function wantsToDig(): boolean
	if held or touchHeld then
		return true
	end
	return ClientState.settings.autoDig and ClientState.ownsPass("AutoDig")
end

local function resync(depth: number)
	localDepth = depth
	progress = 0
	table.clear(pendingSince)
	waitingForGround = false
	ShaftRenderer.setDepth(depth)
	ShaftRenderer.setDamage(0)
	LayerFX.setDepth(depth)
	-- A rollback re-solidifies blocks the character already fell through;
	-- lift it back onto the server's block so it is never inside rock.
	local character = player.Character
	local root = ClientState.rootPart()
	local frame = ClientState.plotFrame()
	if character and root and frame and root.Position.Y < expectedY(depth) - 1.5 then
		character:PivotTo(frame.Rotation + Vector3.new(frame.Position.X, expectedY(depth) + 0.5, frame.Position.Z))
	end
	DigController.onDepth:Fire(depth)
	DigController.onProgress:Fire(0)
end

local function commitDig(index: number)
	local courseSeed = ShaftRenderer.seeds()
	local resolution = Course.resolve(courseSeed, index)
	pendingSince[index] = os.clock()
	ClientState.send("DigRequest", index)

	local fell = 0
	for _, broken in resolution.broken do
		local blockCf = ShaftRenderer.blockCFrame(broken.index)
		local top = ShaftRenderer.topCFrame(broken.index).Position
		local color = ShaftRenderer.groundColor(broken.index)
		if broken.kind == "pocket" then
			fell += 1
			continue
		end
		if broken.kind == "chest" then
			local deco = ShaftRenderer.takeDeco(broken.index)
			if deco then
				Juice.chest(deco, Course.chestCash(broken.index))
			end
			DigController.onSpecial:Fire("chest", broken.index)
		elseif broken.kind == "blast" and broken.index == index then
			local charge = ShaftRenderer.takeDeco(broken.index)
			if charge then
				charge:Destroy()
			end
			Juice.blast(top, color)
			CameraController.punch(14, 0.5)
			DigController.onSpecial:Fire("blast", broken.index)
		end
		Juice.shatter(blockCf, color)
		local roll = ShaftRenderer.rollAt(broken.index)
		if roll.oreId or roll.relic then
			Juice.orePop(top, roll)
		end
	end

	ShaftRenderer.setDepth(resolution.finalDepth)
	localDepth = resolution.finalDepth
	progress = 0
	waitingForGround = true
	groundDeadline = os.clock() + 0.6 + 0.12 * (resolution.finalDepth - index)
	if fell > 0 then
		Juice.pocket(ShaftRenderer.topCFrame(index + 1).Position, ShaftRenderer.groundColor(index + 1))
		CameraController.punch(8 + fell * 2, 0.6)
		DigController.onSpecial:Fire("pocket", fell)
	end
	LayerFX.shake(0.06, 0.12)
	if LayerFX.setDepth(localDepth) then
		SFX.play("LayerEnter", { volume = 0.7 })
		CameraController.punch(10, 0.8)
	end
	if localDepth >= GameConfig.CoreDepth then
		SFX.play("CoreReached", { volume = 1 })
		LayerFX.shake(0.8, 1)
		CameraController.punch(20, 1.2)
	end
	DigController.onDepth:Fire(localDepth)
	DigController.onProgress:Fire(0)
end

local function step(dt: number)
	local wants = wantsToDig() and canDig()
	local active = wants and not waitingForGround and standingOnCurrentBlock()
	digging = active
	SFX.loop("DigLoop", active)
	if not wants then
		if progress > 0 then
			progress = math.max(0, progress - dt * 2) -- release bleeds progress instead of snapping
			ShaftRenderer.setDamage(progress)
			DigController.onProgress:Fire(progress)
		end
		return
	end
	if waitingForGround then
		if standingOnCurrentBlock() or os.clock() > groundDeadline then
			waitingForGround = false
		else
			return
		end
	end
	if not active then
		return
	end
	local index = localDepth + 1
	local digTime = Economy.digTime(index, digPower())
	progress = math.min(1, progress + dt / digTime)
	ShaftRenderer.setDamage(progress)
	DigController.onProgress:Fire(progress)

	-- Fixed audible/visible steps per block, however long the block takes.
	local tickStep = math.floor(progress * TICKS)
	if tickStep ~= lastTickStep and progress < 1 then
		lastTickStep = tickStep
		SFX.digTick(progress)
		Juice.chips(ShaftRenderer.topCFrame(index).Position, ShaftRenderer.groundColor(index), 3)
		CameraController.nudge(0.04)
	end
	if progress >= 1 then
		lastTickStep = -1
		commitDig(index)
	end
end

local function onDigResult(index: number, accepted: boolean, serverDepth: number)
	pendingSince[index] = nil
	if accepted then
		if serverDepth > localDepth then
			resync(serverDepth)
		end
		return
	end
	-- Stale rejections for indices we already rolled back can be ignored.
	if serverDepth ~= localDepth or index <= serverDepth then
		resync(serverDepth)
	end
end

function DigController.setTouchHeld(isHeld: boolean)
	touchHeld = isHeld
end

function DigController.localDepth(): number
	return localDepth
end

--- True while the local player is actively drilling (for the rig pose).
function DigController.isDigging(): boolean
	return digging
end

function DigController.init()
	ClientState.onDigResult:Connect(onDigResult)
	ClientState.onResync:Connect(function(depth)
		resync(depth)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.F then
			held = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.F then
			held = false
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		step(dt)
		-- A request with no answer for 2 s means the packet or the server
		-- state moved on; fall back to the server's depth attribute.
		local now = os.clock()
		for index, sentAt in pendingSince do
			if now - sentAt > 2 then
				pendingSince[index] = nil
				resync(ClientState.number("Depth", 0))
			end
		end
	end)
end

return DigController
