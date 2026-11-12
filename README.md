# Dig to the Core

A 25-minute race to the core on a 12-player server. Everyone digs straight
down in a private shaft; first to the core, or deepest when the bell rings,
takes the round. Rounds reset, meta persists, meta never decides a round.

Everything is server-authoritative Luau (`--!strict`), laid out for Rojo. If
you do not use Rojo, every file starts with a header naming its exact Explorer
location and class.

## Open it in Studio

**Fastest:** open `build/DigToTheCore.rbxl` (built from this tree with Rojo
7.7.1). Enable **Game Settings → Security → Enable Studio Access to API
Services** if you want real DataStore saves; without it ProfileStore
automatically uses its in-memory mock and everything still runs.

**With Rojo:** `rojo serve default.project.json` and connect from the plugin,
or `rojo build -o build/DigToTheCore.rbxl`.

**By hand:** create each file as the class in its header. `.server.luau` is a
Script, `.client.luau` is a LocalScript, everything else is a ModuleScript.
`StarterGui/DigUI` is a ScreenGui (ResetOnSpawn off, ScreenInsets
CoreUISafeInsets, ZIndexBehavior Sibling). Set
`Workspace.FallenPartsDestroyHeight = -6000`.

## Explorer layout

```
ReplicatedStorage
  Config/      GameConfig, AssetIds, UITheme, Credits        (plain data)
  Shared/      Types, Hash, Layers, Economy, OreGen, Format, Signal, Remotes, Quests
  Remotes/     created at runtime by Shared/Remotes
  RoundState   Folder with phase/mega/leader attributes, created by RoundService
ServerScriptService
  Main                       boot order
  Packages/ProfileStore      vendored, Apache-2.0 (MadStudioRoblox/ProfileStore)
  Services/  RateLimiter, DataService, PlotService, RoundState, MetaService,
             QuestService, ShopService, TravelService, DigService, RoundService
ServerStorage
  EconomySim                 pacing simulation (tools/EconomySim.luau)
StarterPlayer/StarterPlayerScripts
  Main                       client boot
  Controllers/ ClientState, ShaftRenderer, DigController, LayerFX, Juice, SFX, DrillRig
StarterGui/DigUI (ScreenGui)
  App                        builds the three layers and wires the menu
  Components/  Base, Panel, Label, Icon, Button, Bar, Modal, Toast
  Screens/     HUD, Leaderboard, RoundOverlay, Shop, Collection, QuestsScreen, MetaShop, More
```

## How the pieces talk

- The server owns depth, cash, tiers and the backpack (`RoundState`, memory
  only). Clients see them as attributes on their Player (`Depth`, `Cash`,
  `DrillTier`, `PackTier`, `PackUsed`, `PackCap`, `DigPower`, `CatchUp`,
  `Seed`, `Gems`, `Relics`, ...). Backpack contents arrive via `BackpackSync`.
- Clients only send intent: `DigRequest(blockIndex)`, `SellAll()`,
  `BuyUpgrade(kind)`, `ClaimQuest(id)`, `Travel(dir)`, `BuyMeta`,
  `ClaimCollection`, `OpenEgg`, `Equip`. Every handler is rate-limited
  (token buckets in `GameConfig.RateLimits`) and validated.
- Block contents come from `OreGen.roll(seed, index)`, a deterministic hash of
  the per-round player seed and the block index. The server never sends block
  data; it rolls the same thing the client rendered.
- `DigService` accepts a dig only if the index is the next one down, the
  character is near the right height, and at least `hardness / power +
  DropTime` seconds have passed since the last accepted dig (minus a small
  tolerance). Rejections resync the client; only cheat-shaped failures count
  toward a kick.
- `ShaftRenderer` keeps a pool of 12 block parts, 12 ore decorations and 3
  wall chunks and recycles them as the player descends. Nothing else exists.
- Round flow lives in `RoundService`: Lobby 30 s → Countdown 5 s → Active
  25 min → Results 20 s. Mega Drill fires at 8:00 and 16:00 for 60 s (×1.5
  power, shared goal bar, +20 gems if met). Catch-up (up to +15%, scaled by
  gap to the leader) is recomputed every 3 s and is 0 for the leader, so the
  leader never sees the chip.
- Persistence is ProfileStore with a 60 s autosave and save on leave. Schema
  `version = 1`, see `DataService` for the template and the migration hook.

## Economy simulation

`tools/EconomySim.luau` plays the real `OreGen` with the real config and a
simple focused policy. Current results are in `DESIGN.md`.

In Studio (command bar):

```lua
local RS = game.ReplicatedStorage
require(game.ServerStorage.EconomySim).run({
    GameConfig = require(RS.Config.GameConfig), Layers = require(RS.Shared.Layers),
    Economy = require(RS.Shared.Economy), OreGen = require(RS.Shared.OreGen),
}, { seeds = 40 })
```

Outside Studio: `python3 tools/run_sim.py --seeds 40 [--policy casual]`
(needs the `luau` CLI in `.tools/`, see Toolchain).

## Toolchain (optional)

`tools/check.sh` runs `rojo sourcemap` + `luau-lsp analyze` with Roblox types
in strict mode. Drop these into `.tools/`: `rojo` (rojo-rbx/rojo release),
`luau-lsp` (JohnnyMorganz/luau-lsp release), `luau` (luau-lang/luau
`luau-ubuntu.zip`) and `globalTypes.d.luau` from the luau-lsp repo
(`scripts/globalTypes.d.luau`).

## Studio test checklist

Run these in order with **Test → Clients and Servers → 2 players** (or Play
Solo for the single-player items).

1. **Boot.** Output shows one `[SFX] ... sound slots unset` warning and one
   `asset slots unset` warning (expected until assets are sourced), and
   `Gamepasses not configured`. No errors.
2. **Plots.** Each player stands on their own island; the name board shows
   their display name; the sell pad is the amber square.
3. **Lobby → Countdown → Active.** Timer counts down 30 s, then 5-4-3-2-1
   with punches, then "DIG!". Digging before Active does nothing (no error).
4. **Dig loop.** Walk onto the shaft opening, hold left mouse (or the HOLD TO
   DIG button on touch). The block below shrinks away after ~1.2 s, you drop,
   dust puffs in the layer colour, the depth meter reads 1 m. Within ~5 s an
   ore block pops up, chimes, floats a "+$2" and the backpack bar fills.
5. **Chunked rendering.** In the Explorer, `Workspace.LocalShaft` (client)
   never holds more than ~12 blocks, ~24 ore parts and 12 wall parts. The
   server's Workspace has no shaft parts at all.
6. **Backpack full.** Keep digging past 12 ore: the bar turns warn-red and a
   "Backpack full" toast appears, blocks still dig.
7. **Sell.** Press Up, wait the ride, you land by the sell pad. Sell is now
   enabled (HUD button or the pad prompt). Cash counts up with a punch and a
   float. Selling away from the pad is refused with a toast.
8. **Shop.** `E` or the Shop button. Buy Copper Bit at $50; cash drops, power
   on the card updates, digging is visibly faster. Buy with too little cash:
   button is disabled; the server also refuses if you fire the remote by hand.
9. **Layer change.** At 150 m the fog, ambient and tint shift over ~1 s with a
   small shake and an "Entering Bedrock" toast. At 450 m, again for The Hollows.
10. **Validation.** From the client command bar run
    `game.ReplicatedStorage.Remotes.DigRequest:FireServer(999)` → nothing
    happens except a resync. Fire `DigRequest` with the correct next index 20
    times in a loop → at most one is accepted, server Output logs
    "dug too fast", the client snaps back. 30 malformed calls → kicked.
11. **Catch-up.** Second player stays at the surface while the first digs to
    ~200 m: the trailing player's HUD shows "Catch-up +15% dig speed"; the
    leader never sees the chip. `DigPower` attribute on the trailing player
    is 15% higher than their tier's power.
12. **Mega Drill.** Temporarily set `GameConfig.Round.MegaDrill.StartTimes =
    {20, 60}`. At 0:20 the amber banner slides in, both players dig faster,
    the shared bar fills; at 60 s it says GOAL REACHED and both receive +20
    gems (×2 with the 2x pass).
13. **Results.** Set `ActiveSeconds = 120` to shorten. The sheet shows the
    winner, top rows and your placement/gems; stats.rounds/wins update
    (check `Gems` attribute and the next profile load). Everything resets:
    depth 0, cash 0, tier 1, fresh ore layout in the shaft.
14. **Core.** Set `CoreDepth = 30` and dig to it: the glowing core appears
    below the last blocks, the round ends immediately with you as winner.
15. **Persistence.** With API access on: earn gems, leave, rejoin → gems,
    collection counts and quest progress are back. Output shows no
    ProfileStore errors; profile `version` is 1.
16. **Quests / Collection / Meta.** Open each from the menu. Claim a finished
    quest (gems tick up). Claim a collection threshold once; the button turns
    "Claimed". Buy Drill tuning (100 gems) → `MetaDig` = 1, DigPower +2%.
    Open an egg: odds are printed above the button; result names the pet;
    equip it and a small follower appears behind you.
17. **Phone.** Device emulator, iPhone-class landscape: HOLD TO DIG button
    appears, every button is ≥ 48 px, nothing overlaps the top-left Roblox
    button, text ≥ 14 px.
