# Assets

Every external asset, where it comes from, its licence and what credit it
needs. Ids go into `ReplicatedStorage/Config/AssetIds` only after they are
recorded here. No id in this project was typed from memory; every slot is 0
until sourced.

Rules in force: 3D only from the Creator Store or CC0/permissive packs
(Kenney, Quaternius, Poly Pizza); icons only from icon packs; panels are
9-slice sprites; one icon set; one font (Nunito, built into Roblox).

## Status

| Group | Slots | Sourced |
|---|---|---|
| UI 9-slice panel | 1 | 0 |
| Icons (game-icons.net) | 23 | 0 |
| Layer textures (your 204-material pack) | 3 layers | 0 — waiting on the material list |
| Sounds (Creator Store) | 23 | 0 |
| Meshes (Creator Store / Quaternius / Kenney) | 8 | 0 |
| Gamepass ids (Creator Dashboard) | 4 | 0 |

Every slot is consumed by code; there are no speculative slots. Until sourced
the game draws rounded frames instead of the 9-slice, hides icon slots
(layouts do not shift), stays silent on unset sounds (warned once at
startup), and uses part-built drill / pet / ore stand-ins. These stand-ins
are placeholders, not final art.

## UI panel (CC0)

Source: Kenney UI Pack (https://kenney.nl/assets/ui-pack) or Kenney UI Pack
Space Expansion. Upload the grey 9-slice panel and recolour in code
(`ImageColor3` is set to the palette, so pick a white/grey sprite).

| Slot | Search term in pack | Notes |
|---|---|---|
| `UI.PanelSlice` | `panel_grey` / `grey_panel` | set `PanelSliceCenter` to the sprite's border |

Licence CC0 1.0, no credit required (credited anyway on the Credits screen).

## Icons (CC BY 3.0, attribution required)

Source: https://game-icons.net — one set, white on transparent, 512 px,
uploaded as decals. The code recolours with `ImageColor3`.

| Slot | Search on game-icons.net |
|---|---|
| `Icons.Depth` | "plain arrow" (rotate down) |
| `Icons.Cash` | "coins" |
| `Icons.Gem` | "cut diamond" |
| `Icons.Backpack` | "knapsack" |
| `Icons.Drill` | "drill" |
| `Icons.Shop` | "shop" |
| `Icons.Book` | "book cover" |
| `Icons.Quest` | "scroll quill" |
| `Icons.Trophy` | "trophy cup" |
| `Icons.Settings` | "cog" |
| `Icons.Close` | "cancel" |
| `Icons.Sell` | "cash" |
| `Icons.Up` / `Icons.Down` | "upload" / "download" |
| `Icons.Mega` | "lightning trio" |
| `Icons.Egg` | "egg" |
| `Icons.Ore.coal` | "coal wagon" or "rock" |
| `Icons.Ore.copper/iron/silver/gold` | "ore" (recoloured per ore in code) |
| `Icons.Ore.sapphire/ruby` | "cut diamond" / "emerald" |

Credit required: "Icons by Lorc, Delapouite and contributors, game-icons.net,
CC BY 3.0" — shown on the in-game Credits screen (`Config/Credits`).

## Layer textures (developer's 204-material pack)

Slots: `Textures.topsoil/bedrock/hollows` each with `Top`, `Side` (image ids)
or `MaterialVariant` (name of a MaterialVariant under MaterialService). Both
paths are wired in `ShaftRenderer.applyLayerSurface`.

Pending: the material list. Intended mapping once it arrives:

| Layer | Look wanted | Base material now |
|---|---|---|
| Topsoil (0–150 m) | dry packed dirt, low saturation, warm | `Ground`, #8A6E4B |
| Bedrock (150–450 m) | grey slate/shale, cool, matte | `Slate`, #6B6E73 |
| The Hollows (450–1050 m) | dark basalt with faint violet-grey, matte | `Basalt`, #4F4A5C |

Record the pack's licence here when assigning.

## Sounds (Roblox Creator Store, audio)

Search the Creator Store (Audio, filter: free). Prefer Roblox-published
packs ("Roblox Audio Library" sound effects) which are licensed for use on
platform. Write the asset name and creator next to each id.

| Slot | Search terms | Feel |
|---|---|---|
| `DigHit` | "rock hit", "pickaxe impact low" | low thud, 100–150 ms |
| `DigTick` | "metal click", "ratchet tick" | high tick layered on DigHit |
| `DigLoop` | "drill loop", "motor hum loop" | quiet, loops while holding |
| `BlockBreak` | "rock crumble", "gravel fall" | short crumble |
| `OreChime` | "chime short", "gem pickup" | bright, pitch-shifted by rarity |
| `RareSting` | "magic sting short", "riser short" | ≤ 0.8 s, rare ore / relic |
| `Sell` | "cash register", "coins pour" | satisfying, ~0.8 s |
| `CoinTick` | "coin tick", "counter click" | tiny, plays under count-ups |
| `UpgradeBuy` | "mechanical ratchet", "upgrade confirm" | |
| `ButtonTap` | "ui tap soft", "button click light" | |
| `ButtonDenied` | "ui error short", "buzz low" | dull, not harsh |
| `LayerEnter` | "deep whoosh", "rumble short" | with the lighting transition |
| `MegaStart` | "air horn", "siren short" | |
| `MegaEnd` | "gong soft" | |
| `MegaGoal` | "fanfare short", "crowd cheer short" | |
| `RoundStart` | "air horn", "starting horn" | |
| `Countdown` | "beep countdown" | |
| `RoundEnd` | "gong", "bell large" | |
| `Win` | "victory fanfare short" | |
| `QuestClaim` | "reward jingle", "success chime" | |
| `ElevatorMove` | "elevator motor", "cable whir" | |
| `EggCrack` | "egg crack", "shell break" | |
| `CoreReached` | "impact huge", "resonant hit" | |

Creator Store audio is licensed for use on Roblox under the Creator Store
terms; note any creator-requested credit here.

## Meshes

| Slot | Suggested source | Search / file | Licence |
|---|---|---|---|
| `Meshes.Drill` | Creator Store (free models → mesh only) or Kenney "Tools" kit | "drill", "power drill lowpoly" | per listing / CC0 |
| `Meshes.Pets.*` | Quaternius "Ultimate Animated Animals" / Poly Pizza (CC0 filter) | mole, beetle, gecko, bat, crab, owl, salamander | CC0 |

Ore nuggets, relics and the core are part-built on purpose (chunky
silhouettes, recoloured per ore); add mesh slots only if a sourced mesh
reads better at phone size.

Until these are filled the drill, pets and ore are part-built stand-ins
(`DrillRig`, `ShaftRenderer`). They are deliberately chunky and readable but
they are not final.

## Code

ProfileStore — loleris / Mad Studio, Apache-2.0
(https://github.com/MadStudioRoblox/ProfileStore). Licence file next to the
module in `ServerScriptService/Packages`.

## Engine assets

`AssetIds.Particles` references textures shipped with the engine
(`rbxasset://textures/particles/...`). These are not uploaded ids and need no
credit.
