--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/DigController (ModuleScript)
-- Hold-to-dig with client prediction. The client times the dig locally with
-- the server-replicated DigPower, removes the block optimistically, and lets
-- the server's DigResult confirm or roll it back. It never sends depth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Layers = require(ReplicatedStorage.Shared.Layers)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local Juice = require(script.Parent.Juice)
local LayerFX = require(script.Parent.LayerFX)
local SFX = require(script.Parent.SFX)
local ShaftRenderer = require(script.Parent.ShaftRenderer)

local DigController = {}

local G = GameConfig.Geometry
local player = Players.LocalPlayer

local held = false
local touchHeld = false
local progress = 0
local localDepth = 0
local waitingForGround = false
local groundDeadline = 0
local lastTickStep = -1
local pendingSince: { [number]: number } = {}

DigController.onProgress = Signal.new() :: Signal.Signal<number>
DigController.onDepth = Signal.new() :: Signal.Signal<number>

local function digPower(): number
	return math.max(0.1, ClientState.number("DigPower", GameConfig.Drills[1].power))
end

local function expectedY(depth: number): number
	return G.SurfaceY - depth * G.BlockHeight + 3
end

local function standingOnCurrentBlock(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end
	-- Over the shaft opening, not just somewhere on the island at the same height.
	local center = ClientState.plotCenter()
	if center then
		local dx = math.abs(root.Position.X - center.X)
		local dz = math.abs(root.Position.Z - center.Z)
		if dx > G.BlockSize / 2 + 1 or dz > G.BlockSize / 2 + 1 then
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
	LayerFX.setDepth(depth)
	-- A rollback re-solidifies blocks the character already fell through;
	-- lift it back onto the server's block so it is never inside rock.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local center = ClientState.plotCenter()
	if character and root and root:IsA("BasePart") and center and root.Position.Y < expectedY(depth) - 1.5 then
		character:PivotTo(CFrame.new(center.X, expectedY(depth) + 0.5, center.Z))
	end
	DigController.onDepth:Fire(depth)
	DigController.onProgress:Fire(0)
end

local function commitDig(index: number)
	local roll = ShaftRenderer.rollAt(index)
	local position = ShaftRenderer.blockCFrame(index).Position
	local layer = Layers.layerAt(index - 1)
	pendingSince[index] = os.clock()
	ClientState.send("DigRequest", index)
	ShaftRenderer.removeBlock(index)
	localDepth = index
	progress = 0
	waitingForGround = true
	groundDeadline = os.clock() + 0.6
	Juice.blockBreak(position, Color3.fromHex(layer.groundColor))
	if roll.oreId or roll.relic then
		Juice.orePop(position, roll)
	end
	if LayerFX.setDepth(index) then
		SFX.play("LayerEnter", { volume = 0.7 })
	end
	if index >= GameConfig.CoreDepth then
		SFX.play("CoreReached", { volume = 1 })
		LayerFX.shake(0.6, 0.8)
	end
	DigController.onDepth:Fire(index)
	DigController.onProgress:Fire(0)
end

local function step(dt: number)
	local wants = wantsToDig() and canDig()
	SFX.loop("DigLoop", wants and not waitingForGround)
	if not wants then
		if progress > 0 then
			progress = math.max(0, progress - dt * 2) -- release bleeds progress instead of snapping
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
	if not standingOnCurrentBlock() then
		return
	end
	local index = localDepth + 1
	local digTime = Economy.digTime(index, digPower())
	progress = math.min(1, progress + dt / digTime)
	DigController.onProgress:Fire(progress)

	-- Four audible steps per block, however long the block takes.
	local tickStep = math.floor(progress * 4)
	if tickStep ~= lastTickStep and progress < 1 then
		lastTickStep = tickStep
		SFX.digTick(progress)
	end
	if progress >= 1 then
		lastTickStep = -1
		commitDig(index)
	end
end

local function onDigResult(index: number, accepted: boolean, _roll: Types.BlockRoll?, serverDepth: number)
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

function DigController.init()
	ClientState.onDigResult:Connect(onDigResult)
	ClientState.onResync:Connect(function(depth)
		resync(depth)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			held = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
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
