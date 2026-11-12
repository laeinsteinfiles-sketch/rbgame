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
  inside the shaft footprint → timing.
- Timing uses a small time bank: each accepted dig costs
  `hardness / power + DropTime` seconds, judged against the kinder of current
  and previous power, and real elapsed time refills the bank up to
  `Dig.TimeBankSeconds` (0.75 s). Two requests bunched by lag pass; sustained
  over-speed does not, and skipping the fall gains at most the bank once.
  Only a gap under half the required time counts as a violation; other
  timing misses are rejected and resynced without penalty.
- A missing or dead character (respawn, death mid-dig) is a plain reject, not
  a violation. Out-of-order indices are not violations either (an honest
  client keeps predicting after a rejection); malformed args and positions
  far from the shaft are. 25 violations → kick.
- Selling needs the server to have seen the player reach the surface (an up
  ride, a respawn or the lobby reset) and proximity to their own pad, so a
  teleport exploit cannot skip the ride. Arriving at the top by elevator
  sells automatically; the pad and the HUD button cover respawns.
- A player who disconnects mid-round gets their exact state (depth, seed,
  cash, pack) back if they rejoin before the round ends.
- Only players who dug at least one block place, win, earn gems or count a
  finished round. Payout = participation 10 + 1 per 50 m (cap 30) + podium
  bonus 60/40/25, so a deep 4th never out-earns 3rd and idling earns nothing.
  Ties break on who reached the depth first; the core winner always places 1st.
- `SafetyService` returns characters that leave the playable space (map edge,
  void, or through a shaft whose local blocks failed) to where the server
  thinks they are, never to a more convenient place.
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

## Look and feel

The first build used a muted charcoal palette with Nunito and hidden icons;
it read as generic. The current look copies what the top Roblox dig games
(Dig to Earth's CORE!, Dig to Escape, Mining Simulator 2, Dig it!) actually
ship, measured from their screenshots:

- **Plates.** Charcoal windows (#303036 → #222226) with a 4 px near-black
  outline; saturated glossy plates (lime, sky, periwinkle, coral, amber,
  purple, orange) with a white shine strip and a darker 5 px 3D lip that the
  face sinks into on press. Hover grows, click pops (Back-out).
- **Type.** Fredoka One everywhere in caps on buttons and titles, white with
  a black outline at ~12% of the text size; Luckiest Guy only for big
  banners (countdown, round over, core reached). `UITheme` owns every colour.
- **Icons.** Every control has one: coins, gems and ores are drawn from
  frames; everything else is a colour emoji. Uploaded icons can override.
- **HUD.** Left: cash/gem/relic pills and a 2-wide grid of menu tiles with
  red badges (claimable quests, collection rewards, affordable upgrades, an
  affordable egg). Top centre: round timer that turns red in the last minute.
  Right: the race tracker, a layer-coloured surface-to-core track with every
  player's avatar at their depth and the top-5 standings. Bottom centre:
  depth + layer chip, backpack bar (orange near full, red and pulsing when
  full) and exactly one context action (SELL $n / SURFACE in the shaft, SELL
  or DIG n m at the top, elevator countdown while riding). Touch adds a big
  round DIG button left of the jump button.
- **Guidance.** A hint pill always says the next step (walk into your hole,
  hold to dig, backpack full, go sell, you can afford an upgrade, ride back
  down), with a glowing guide line to the hole or sell pad when walking is
  the next step.
- **Menus.** Tilted title chip over the top-left corner, tilted red X, Back-
  out open. Upgrades show tier pips, the next tier's gain and what's
  missing ("NEED $120 MORE"). The Ore Index shows "???" until an ore is
  found and a discovery meter. The Gem Shop hatches eggs in ~3 s (wobble,
  crack, pop to the pet in its rarity colour).
- **Big moments.** 3-2-1-DIG! countdown, layer title cards, rare/new-ore and
  relic banners in rarity colours, the Mega Drill banner with its shared
  goal bar, coins that fly into the cash pill on a sale, a full-screen
  flash and confetti at the core, and a podium results sheet with avatars.
- **Audio.** 25 verified public sound effects and 4 music tracks that
  crossfade by zone (surface, Topsoil, Bedrock, The Hollows); see ASSETS.md.

## Juice checklist

Block break: dust puff plus debris chunks in the layer colour, four dig
ticks per block (low thud + high tick). Ore: gem pops out with a sparkle
burst and flies at the camera, floating "+$n" in rarity colour; rare finds
add a banner, light flash and small shake. Sell: register sound, coin
burst into the cash pill, count-up with rising ticks, pill punch. Layer
change: lighting tween, whoosh, title card. Plus countdown punches, Mega
banner slide, egg hatch, button press/hover, elevator whir and the core
celebration.

## Deliberately not built

Forge, boss, cave-ins: not designed in the brief, so not guessed at. Daily
login calendar, gift timer and codes (common in the hits) are left for a
later pass; they need their own persistence and copy. The round loop, pets,
skins, quests, collection, meta shop, gamepass hooks and credits are all in.

## Known placeholders

Gamepass ids are 0 until the passes exist in the Creator Dashboard (their
buttons say SOON). Icons, panels, layer textures and meshes are code-built
on purpose; uploaded art can replace any of them through `AssetIds`.
