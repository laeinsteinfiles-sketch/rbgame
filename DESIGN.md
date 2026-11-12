# Design notes

Decisions made without asking, in the order they shape the game. Numbers
marked (sim) come from `tools/EconomySim.luau`.

## The race is the game

- Round: Lobby 30 s → Countdown 5 s → Active 25 min → Results 20 s.
- Win: first to 1050 m (the core seal) ends the round on the spot; otherwise
  deepest at the bell. Ties break on blocks dug, then name.
- Core at 1050 m (sim). A focused solo player reaches it at 19:29 mean
  (p10 18:01, p90 20:54, 40 seeds). A casual one ("sell when full, drill
  only") at 20:59. Mega Drill windows shave ~40 s off both in real play.
- Mega Drill at 8:00 and 16:00, 60 s, ×1.5 power. Shared goal = 45 blocks per
  online player; met → +20 gems to everyone online. The bar is visible to
  all, the bonus is meta-only, so it is a party moment, not a lead swing.
- Catch-up: +15% dig speed at a gap of 15% of core depth (157 m) or more,
  linear below, recomputed every 3 s. The leader's bonus is 0 so the HUD chip
  simply never renders for them.

## Pacing (sim, focused policy)

| Target | Brief | Result |
|---|---|---|
| First ore | 5 s | 3 s mean |
| First sale | 30 s | 36 s mean (p10 12 s, p90 50 s) |
| First upgrade | 60 s | 36–45 s mean |
| Layer 2 | ~3 min | 2:46 mean |
| Layer 3 | — | 8:39 mean |
| Core | ~20 min | 19:29 mean |

What moved from the brief's guesses:

- Starting pack 12 (was 20) so the first sale lands near 30 s.
- Packs 12/24/45/80/140/240 at 0/30/100/300/850/2200.
- Drill power and costs kept exactly as given (1 → 17, 50 → 7300).
- Hardness ramps inside each layer: Topsoil 1→1.8, Bedrock 2.5→5, Hollows
  5→14. Without the ramp the late game was pure drop-time and depth numbers
  ran to 4000 m.
- Ore chance ~34% of blocks in every layer; values Coal 2 → Ruby 200.

Re-run after any change: `python3 tools/run_sim.py` (or the Studio snippet in
README). Everything else in `GameConfig` is a first guess.

## Fairness and anti-cheat

- The server owns every number. Clients send `DigRequest(index)` and the
  server checks: rate limit → integer → phase Active → `index == depth + 1`
  → not mid-elevator → character within 6 blocks of the expected height and
  inside the shaft footprint → elapsed ≥ `hardness / power + 0.18 s` with a
  12% (min 80 ms) tolerance, judged against the kinder of current and
  previous power so Mega Drill edges and upgrades never reject honest digs.
- Drop time is part of the minimum interval. A client that skips the physics
  fall gains nothing.
- Out-of-order indices are not violations (an honest client keeps predicting
  after a rejection); malformed args, position and timing failures are. 25
  violations → kick.
- Sell requires proximity to the player's own pad; value is computed from
  the server's backpack.
- Meta perks: dig speed +2%/level, max 5 (+10%); pack +1 slot/level, max 5.
  Pets add gems only. Skins are cosmetic. The BigPack pass starts you on the
  tier-2 pack (one fewer early trip), which is the most "advantage" any
  purchase gives.

## Persistence

ProfileStore, store `PlayerData_v1`, autosave 60 s
(`SetConstant("AUTO_SAVE_PERIOD")`), `EndSession` on leave. Template:

```
version 1, gems, relics,
meta { digSpeedLvl, packLvl },
collection { [oreId] = { count, mutations { [mutationId] = n } } },
quests { day, progress { [id] = n }, claimed { [id] = true } },
stats { rounds, wins, maxDepth },
purchases { skins, pets { [id] = count }, claimedCollection, equippedSkin, equippedPet }
```

`MIGRATIONS[n]` upgrades n → n+1; `Reconcile()` fills new keys. Round state
is never written.

## Art direction as implemented

- Palette: panel #23272E with #3B424D 2 px outline, amber #F2B33D for
  rewards/cash/winners, teal #3FB6A8 for positive actions/progress/gems,
  text #F1EFE8 / #A3A7AE. One warn colour (#C9655C) for "can't afford" and
  "pack full" only.
- Nunito SemiBold (body) and ExtraBold (numbers, titles). Radius 10 px.
- Layers: Topsoil dusty brown, Bedrock slate, Hollows desaturated
  violet-grey. Each has its own Ambient/OutdoorAmbient/Fog, Atmosphere
  density/haze/colour and ColorCorrection saturation/contrast/tint, tweened
  over 1.2 s (Sine) with a 0.35-stud shake.
- Saturation only on ore, mutations (Glass/Neon + light), relics (amber),
  the core, and the sell pad.
- UI is code-built from eight components; no screen owns a one-off frame
  style. Panels switch to the 9-slice sprite the moment the id is set.

## Juice checklist

Ore pop (Back-out rise, Quad-in whip to camera), dust puff in layer colour,
floating "+$n", rare sting + particle burst + 0.12 shake on rarity ≥ 3 or
any mutation, cash count-up (Quad-out, coin ticks) with panel punch, layer
transition + shake + whoosh, countdown punches, Mega banner Back-out slide,
results sheet Back-out, button tap punch + sound, elevator sound, four dig
ticks per block (low thud + high tick = the "haptic" layer).

## Deliberately not built

Forge, boss, cave-ins: not designed in the brief, so not guessed at. The
round loop, pets, skins, quests, collection, meta shop, gamepass hooks and
credits are all in.

## Known placeholders

Everything in `AssetIds` at 0 (see ASSETS.md). Part-built drill, pets and
ore nuggets. Layer textures pending the 204-material list.
