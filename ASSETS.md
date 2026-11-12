# Assets

Every external asset the game uses, where it comes from and what credit it
needs. Ids go into `ReplicatedStorage/Config/AssetIds` only after they are
verified and recorded here; none was typed from memory.

## Status

| Group | Slots | Sourced |
|---|---|---|
| Sound effects | 25 | 25 (verified public audio) |
| Music | 4 | 4 (verified public audio) |
| Icons | 23 | 0 uploads needed: coins, gems and ores are drawn in code, the rest are colour emoji |
| UI 9-slice panel | 1 | 0, optional: panels are code-built plates |
| Layer textures (your 204-material pack) | 3 layers | 0, optional: the shaft uses built-in materials |
| Meshes | 8 | 0, optional: drill, pets and props are part-built |
| Gamepass ids (Creator Dashboard) | 4 | 0, set them once the passes exist |

Nothing is a blank placeholder any more: every icon renders, every sound
slot plays, and the world, drill, pets and ores are deliberately styled
part-built models. Uploaded art can still replace any of them through the
same slots.

## Sound effects and music

Verified on 2026-11-12 through
`https://economy.roblox.com/v2/assets/<id>/details`: every id below is
`AssetTypeId` 3 (Audio) and `IsPublicDomain: true`, uploaded by Roblox
itself or by Roblox's licensed partner libraries (Pro Sound Effects, APM
Music). Since the 2022 audio privacy change only public audio like this
plays in every experience; a random user upload would be silent.

| Slot | Id | Asset name | Creator |
|---|---|---|---|
| `DigHit` | 9118680621 | Rocks Dirt Impacts In Ground 9 (SFX) | ProSoundEffects (7462895450) |
| `DigTick` | 16480549947 | Audio/Roblox_Pinball_Tiny_Button_Press_06 | Roblox (1) |
| `DigLoop` | 16480557782 | Audio/Roblox_Pinball_Joystick_Rotate_Loop_01 | Roblox (1) |
| `BlockBreak` | 9119037874 | Shale Break 15 (SFX) | ProSoundEffects |
| `OreChime` | 17208319162 | Roblox GUI - Pickup | Roblox |
| `RareSting` | 9116421762 | Magic Transformation 9 (SFX) | ProSoundEffects |
| `Sell` | 9113728625 | Cash Register 1 (SFX) | ProSoundEffects |
| `CoinTick` | 16480549708 | Audio/Roblox_Pinball_Tiny_Button_Press_08 | Roblox |
| `UpgradeBuy` | 17208380755 | Roblox GUI - Purchase | Roblox |
| `ButtonTap` | 15675032796 | Roblox_UI_Small_Click | Roblox |
| `ButtonDenied` | 17208353912 | Roblox GUI - Negative | Roblox |
| `LayerEnter` | 9120703816 | Whoosh Combo Of Impacts Bys 1 (SFX) | ProSoundEffects |
| `MegaStart` | 9113071344 | Air Horn Bursts 9 (SFX) | ProSoundEffects |
| `MegaEnd` | 9116985195 | Motor Wind- Down 5 (SFX) | ProSoundEffects |
| `MegaGoal` | 9120974708 | Wrestling Crowd 8 (SFX) | ProSoundEffects |
| `RoundStart` | 9114402619 | Ferrari 308 Car Honking Dual Air Horns 9 (SFX) | ProSoundEffects |
| `Countdown` | 15930291180 | Roblox_RetroSFX_08 | Roblox |
| `RoundEnd` | 16480570385 | Audio/Roblox_Pinball_Bumper_Low_Bells_05 | Roblox |
| `Win` | 12222253 | victory.wav | Roblox |
| `QuestClaim` | 17208361335 | Roblox GUI - Notification High | Roblox |
| `ElevatorMove` | 9118934517 | Servo Motor 11 (SFX) | Roblox |
| `EggCrack` | 9113959343 | Crack Egg Crunchy 11 (SFX) | ProSoundEffects |
| `CoreReached` | 3149249837 | Cannon_Explode | Roblox |
| `Whoosh` | 15675012262 | Roblox_UI_Whoosh_04 | Roblox |
| `Pop` | 15675059323 | Roblox_UI_Bright_Click | Roblox |
| `Music.Lobby` | 1836914203 | Happy Thoughts | APMOfficial (7462718749) |
| `Music.Topsoil` | 1838661059 | Magical Adventure (Light Vs) | APMOfficial |
| `Music.Deep` | 15675069601 | Roblox_UI_Loop_Calm_Music | Roblox |
| `Music.Hollows` | 17422163655 | Generic - Cloud Blitz | Roblox |

Choices were made from asset names, Roblox's tags and measured durations,
not by ear; swap any slot after a listen in Studio. Good alternates that
also verified: Rock Impacts 9 (9118631051), Shale Break 8 (9119043991),
Cash Register 5 (9113728756), CoinTransfer_01 (127645268874265), Siren Blat
3 (9119161937), Calm Drone (1846999385), Lurking Gloom (1847027681).

## Icons

`Components/Icon` resolves an icon by name: an uploaded image in
`AssetIds.Icons` wins; otherwise coins, gems and ores are drawn from frames
(gradient, ink outline, highlight) and everything else uses a colour emoji.
Emoji ignore `TextColor3` and text outlines and look slightly different per
OS; upload a matching icon set into `AssetIds.Icons` to replace them.

## Fonts

Fredoka One (all UI text) and Luckiest Guy (big banners) are built into
Roblox; nothing to upload.

## Models, meshes and textures

Runtime loading of other creators' Creator Store models is not available to
a live game (`InsertService:LoadAsset` needs assets the experience owner
owns), and asset downloads need an authenticated account, so the world, the
drill, the pets, ores and the core are part-built in code with built-in
materials and lights. To use real meshes, insert them in Studio (or upload
your own) and fill `AssetIds.Meshes`; `DrillRig` and the pet builder already
read those slots. `AssetIds.Textures` and `AssetIds.UI.PanelSlice` work the
same way.

## Code

ProfileStore — loleris / Mad Studio, Apache-2.0
(https://github.com/MadStudioRoblox/ProfileStore). Licence file next to the
module in `ServerScriptService/Packages`.

## Engine assets

`AssetIds.Particles` and avatar headshots (`rbxthumb://`) use content that
ships with the engine; no ids or credit needed.
