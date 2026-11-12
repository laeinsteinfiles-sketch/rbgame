--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/SFX (ModuleScript)
-- Layered sound playback. Unset ids are skipped silently at play time and
-- listed once at startup so missing audio is always visible in the output.

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)

local SFX = {}

local VOICES = 4

local group = Instance.new("SoundGroup")
group.Name = "SFX"
group.Volume = 0.8
group.Parent = SoundService

local container = Instance.new("Folder")
container.Name = "SFXVoices"
container.Parent = SoundService

local voices: { [string]: { Sound } } = {}
local nextVoice: { [string]: number } = {}
local loops: { [string]: Sound } = {}
local missingLoops: { [string]: boolean } = {}

local function idFor(name: string): string
	local id = (AssetIds.Sounds :: { [string]: number })[name]
	return if id then AssetIds.sound(id) else ""
end

local function makeSound(name: string, looped: boolean): Sound?
	local assetId = idFor(name)
	if assetId == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = assetId
	sound.Looped = looped
	sound.SoundGroup = group
	sound.Parent = container
	return sound
end

export type PlayOptions = { pitch: number?, volume: number? }

function SFX.play(name: string, options: PlayOptions?)
	local pool = voices[name]
	if not pool then
		local made: { Sound } = {}
		for _ = 1, VOICES do
			local sound = makeSound(name, false)
			if sound then
				table.insert(made, sound)
			end
		end
		voices[name] = made
		nextVoice[name] = 1
		pool = made
	end
	if #pool == 0 then
		return
	end
	local index = nextVoice[name]
	nextVoice[name] = index % #pool + 1
	local sound = pool[index]
	sound.PlaybackSpeed = if options and options.pitch then options.pitch else 1
	sound.Volume = if options and options.volume then options.volume else 0.6
	sound:Play()
end

function SFX.loop(name: string, on: boolean)
	if missingLoops[name] then
		return
	end
	local sound = loops[name]
	if not sound then
		local made = makeSound(name, true)
		if not made then
			missingLoops[name] = true
			return
		end
		loops[name] = made
		sound = made
	end
	if on and not sound.IsPlaying then
		sound.Volume = 0.35
		sound:Play()
	elseif not on and sound.IsPlaying then
		sound:Stop()
	end
end

--- Low thud + high tick on every dig step: the "haptic" layer.
function SFX.digTick(progress: number)
	SFX.play("DigHit", { pitch = 0.95 + progress * 0.1, volume = 0.45 })
	SFX.play("DigTick", { pitch = 1 + progress * 0.3, volume = 0.3 })
end

function SFX.setVolume(volume: number)
	group.Volume = math.clamp(volume, 0, 1)
end

function SFX.init()
	local missing = {}
	for name, id in AssetIds.Sounds do
		if not AssetIds.isSet(id) then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		table.sort(missing)
		warn(`[SFX] {#missing} sound slots unset (silent): {table.concat(missing, ", ")}`)
	end
end

return SFX
