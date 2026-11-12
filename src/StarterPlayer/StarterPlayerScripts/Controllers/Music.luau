--!strict
-- Explorer: StarterPlayer/StarterPlayerScripts/Controllers/Music (ModuleScript)
-- Background music by zone: the surface/lobby track, then one per layer as
-- the player digs, crossfaded. Unset ids (AssetIds.Music) stay silent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Config.AssetIds)
local Layers = require(ReplicatedStorage.Shared.Layers)
local ClientState = require(script.Parent.ClientState)
local DigController = require(script.Parent.DigController)

local Music = {}

local FADE = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local TRACK_VOLUME = 0.4

-- Layer id -> AssetIds.Music slot.
local ZONE_BY_LAYER: { [string]: string } = {
	topsoil = "Topsoil",
	bedrock = "Deep",
	hollows = "Hollows",
}

local group = Instance.new("SoundGroup")
group.Name = "Music"
group.Volume = 0.5
group.Parent = SoundService

local folder = Instance.new("Folder")
folder.Name = "MusicTracks"
folder.Parent = SoundService

local tracks: { [string]: Sound } = {}
local current = ""

local function track(name: string): Sound?
	local existing = tracks[name]
	if existing then
		return existing
	end
	local id = (AssetIds.Music :: { [string]: number })[name]
	if not id or not AssetIds.isSet(id) then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = AssetIds.sound(id)
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = group
	sound.Parent = folder
	tracks[name] = sound
	return sound
end

local function zone(): string
	if ClientState.phase() ~= "Active" or ClientState.atSurface() then
		return "Lobby"
	end
	local layer = Layers.layerAt(DigController.localDepth())
	return ZONE_BY_LAYER[layer.id] or "Hollows"
end

local function switchTo(name: string)
	if name == current then
		return
	end
	local old = tracks[current]
	current = name
	if old then
		local out = TweenService:Create(old, FADE, { Volume = 0 })
		out:Play()
		out.Completed:Connect(function()
			if tracks[current] ~= old then
				old:Pause()
			end
		end)
	end
	local nextTrack = track(name)
	if nextTrack then
		if not nextTrack.IsPlaying then
			nextTrack:Resume()
		end
		TweenService:Create(nextTrack, FADE, { Volume = TRACK_VOLUME }):Play()
	end
end

function Music.setVolume(volume: number)
	group.Volume = math.clamp(volume, 0, 1)
end

function Music.init()
	Music.setVolume(ClientState.settings.musicVolume)
	task.spawn(function()
		while true do
			switchTo(zone())
			task.wait(0.5)
		end
	end)
end

return Music
