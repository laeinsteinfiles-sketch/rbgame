#!/usr/bin/env python3
"""Runtime checks of the pure shared modules under the luau CLI.

Uses the same bundler as run_sim.py. Not a test framework: invariants that
type-checking cannot prove (hash determinism and spread, grid maths, cell
generation odds, every DigRules branch, economy edges).
"""
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import run_sim  # noqa: E402

CHECKS = r"""
local GameConfig = require(node("ReplicatedStorage/Config/GameConfig"))
local Hash = require(node("ReplicatedStorage/Shared/Hash"))
local Grid = require(node("ReplicatedStorage/Shared/Grid"))
local Layers = require(node("ReplicatedStorage/Shared/Layers"))
local Economy = require(node("ReplicatedStorage/Shared/Economy"))
local CellGen = require(node("ReplicatedStorage/Shared/CellGen"))
local DigRules = require(node("ReplicatedStorage/Shared/DigRules"))

local failures = 0
local function check(name, ok, detail)
    print((ok and "ok   " or "FAIL ") .. name .. (detail and ("  " .. detail) or ""))
    if not ok then failures += 1 end
end

-- Hash: deterministic, in range, roughly uniform
check("hash deterministic", Hash.u32(12345, 678, 11) == Hash.u32(12345, 678, 11))
local buckets = {0,0,0,0,0,0,0,0,0,0}
for i = 1, 20000 do
    local u = Hash.unit(99991, i, 11)
    assert(u >= 0 and u < 1)
    buckets[math.floor(u * 10) + 1] += 1
end
local minB, maxB = math.huge, 0
for _, n in buckets do minB = math.min(minB, n); maxB = math.max(maxB, n) end
check("hash spread (10 buckets of 20000)", minB > 1800 and maxB < 2200, string.format("min %d max %d", minB, maxB))
check("hash differs by salt", Hash.u32(1, 1, 11) ~= Hash.u32(1, 1, 23))

-- Config sums
local mutSum = 0
for _, m in GameConfig.Mutations do mutSum += m.chance end
check("mutation chances sum to 1", math.abs(mutSum - 1) < 1e-9, tostring(mutSum))
local oddsSum = 0
for _, o in GameConfig.Pets.Odds do oddsSum += o.chance end
check("pet odds sum to 100", oddsSum == 100, tostring(oddsSum))

-- Grid maths
local roundTrip = true
for row = 1, 40 do
    for col = 1, Grid.COLS do
        local c, r = Grid.unkey(Grid.key(col, row))
        local x, y = Grid.cellOffset(col, row)
        if c ~= col or r ~= row or Grid.colAt(x) ~= col or Grid.rowAt(y) ~= row then roundTrip = false end
        -- A standing character's root sits ~3 studs above the cell floor.
        if Grid.rowAt(y - Grid.CELL / 2 + 3.2) ~= row then roundTrip = false end
    end
end
check("grid key/offset round trip", roundTrip)
check("surface is row 0", Grid.rowAt(GameConfig.Geometry.SurfaceY + 3) <= 0)
local ax, az = Grid.plotOrigin(1)
local bx, bz = Grid.plotOrigin(2)
check("plots do not overlap", math.abs(bx - ax) >= 2 * (Grid.halfWidth() + GameConfig.Geometry.BorderColumns * Grid.CELL), string.format("spacing %d", math.abs(bx - ax)))

-- Cell generation odds per layer
for li = 1, Layers.count() do
    local layer = Layers.get(li)
    local startRow = layer.startDepth + 1
    local endRow = math.min(Layers.endDepth(li), GameConfig.CoreDepth - 3)
    local counts = { ore = 0, cave = 0, total = 0, special = 0, hard = 0 }
    for seed = 1, 12 do
        for row = startRow, endRow do
            for col = 1, Grid.COLS do
                local cell = CellGen.at(seed * 7919, col, row)
                counts.total += 1
                if cell.kind == "ore" then counts.ore += 1
                elseif cell.kind == "cave" then counts.cave += 1
                elseif cell.kind == "hard" then counts.hard += 1
                elseif cell.kind ~= "dirt" then counts.special += 1 end
            end
        end
    end
    local ore, cave = counts.ore / counts.total, counts.cave / counts.total
    check("ore share " .. layer.name, ore > 0.1 and ore < 0.3, string.format("%.3f", ore))
    check("cave share " .. layer.name, cave < 0.15, string.format("%.3f", cave))
end
local deterministic = true
for i = 1, 200 do
    local a, b = CellGen.at(42, (i % 11) + 1, i), CellGen.at(42, (i % 11) + 1, i)
    if a.kind ~= b.kind or a.oreId ~= b.oreId or a.mutationId ~= b.mutationId then deterministic = false end
end
check("cell generation deterministic", deterministic)
check("core row is core", CellGen.at(42, 3, GameConfig.CoreDepth).kind == "core")
local surfaceSimple = true
for col = 1, Grid.COLS do
    for row = 1, 3 do
        local kind = CellGen.at(99, col, row).kind
        if kind == "cave" or kind == "chest" or kind == "tnt" then surfaceSimple = false end
    end
end
check("first rows have no caves or specials", surfaceSimple)
local blastHasCore = false
for _, p in CellGen.blastArea(5, GameConfig.CoreDepth - 1) do
    if p[2] >= GameConfig.CoreDepth then blastHasCore = true end
end
check("TNT never blasts the core row", not blastHasCore)

-- DigRules: every branch
local SEED = 1234
local function ctx(overrides)
    local open = overrides.open or {}
    local base = {
        seed = SEED, phase = "Active", traveling = false, reachedCore = false,
        isOpen = function(c, r)
            if r <= 0 then return true end
            return open[Grid.key(c, r)] == true or CellGen.isCave(SEED, c, r)
        end,
        hasRoot = true, rootDx = 0, rootY = 3.2, rootDz = 0,
        now = 100, digClock = 0, power = 1,
    }
    for k, v in overrides do if k ~= "open" then base[k] = v end end
    return base
end
local mid = math.ceil(Grid.COLS / 2)
local v = DigRules.validate(mid, 1, ctx({}))
check("dig row 1 from the surface", v.ok, v.reason)
v = DigRules.validate("x", 1, ctx({}))
check("malformed is a violation", not v.ok and v.violation)
v = DigRules.validate(mid, 0, ctx({}))
check("row 0 is out of bounds (violation)", not v.ok and v.violation)
v = DigRules.validate(Grid.COLS + 1, 1, ctx({}))
check("column past the edge is a violation", not v.ok and v.violation)
v = DigRules.validate(mid, 1, ctx({ phase = "Lobby" }))
check("lobby rejects quietly", not v.ok and not v.violation and v.reason == "not active")
v = DigRules.validate(mid, 1, ctx({ traveling = true }))
check("travelling rejects quietly", not v.ok and not v.violation)
v = DigRules.validate(mid, 1, ctx({ open = { [Grid.key(mid, 1)] = true } }))
check("already open rejects quietly", not v.ok and not v.violation and v.reason == "already open")
v = DigRules.validate(mid, 4, ctx({ rootY = -18 }))
check("not adjacent rejects quietly", not v.ok and not v.violation and v.reason == "not adjacent")
local _, y2 = Grid.cellOffset(mid, 2)
v = DigRules.validate(mid, 3, ctx({ open = { [Grid.key(mid, 1)] = true, [Grid.key(mid, 2)] = true }, rootY = y2 - 2.8 }))
check("dig down from inside the mine", v.ok, v.reason)
v = DigRules.validate(mid, 1, ctx({ rootDx = 20 }))
check("slightly out of reach rejects quietly", not v.ok and not v.violation and v.reason == "out of reach")
v = DigRules.validate(mid, 1, ctx({ rootDx = 60 }))
check("far out of reach is a violation", not v.ok and v.violation)
v = DigRules.validate(mid, 1, ctx({ hasRoot = false }))
check("no character rejects quietly", not v.ok and not v.violation)
v = DigRules.validate(mid, 1, ctx({ digClock = 100.5 }))
check("too fast rejects quietly when close", not v.ok and not v.violation and v.reason == "too fast")
v = DigRules.validate(mid, 1, ctx({ digClock = 104 }))
check("much too fast is a violation", not v.ok and v.violation)
v = DigRules.validate(mid, 1, ctx({ digClock = 0, now = 100 }))
check("idle time is banked at most BankSeconds", v.ok and math.abs(v.digClock - (100 - GameConfig.Dig.BankSeconds)) < 1e-9, tostring(v.digClock))
-- Honest steady digging at exactly the dig time never trips the clock.
local clock, now, honest = 0, 100, true
for i = 1, 30 do
    local hardness = CellGen.at(SEED, mid, 1).hardness
    now += Economy.digTime(hardness, 1)
    local verdict = DigRules.validate(mid, 1, ctx({ digClock = clock, now = now }))
    if not verdict.ok then honest = false break end
    clock = verdict.digClock
end
check("honest cadence always accepted", honest)
-- A client digging twice as fast is cut off within a few cells.
clock, now = 0, 100
local accepted = 0
for i = 1, 20 do
    now += Economy.digTime(1, 1) / 2
    local verdict = DigRules.validate(mid, 1, ctx({ digClock = clock, now = now }))
    if verdict.ok then accepted += 1; clock = verdict.digClock end
end
check("double-speed client is throttled", accepted <= 12, string.format("%d/20 accepted", accepted))

-- Economy
check("meta dig cap is +10%", math.abs(Economy.digPower({pickaxeTier = 1, metaDigLevel = 5, megaActive = false, catchUp = 0}) - 1.10) < 1e-9)
check("catch-up caps", Economy.catchUpBonus(100000) == GameConfig.Round.CatchUp.MaxBonus and Economy.catchUpBonus(0) == 0)
check("upgrade cost chain", Economy.upgradeCost("pickaxe", 1) == GameConfig.Pickaxes[2].cost and Economy.upgradeCost("pickaxe", #GameConfig.Pickaxes) == nil and Economy.upgradeCost("pack", #GameConfig.Packs) == nil)
check("dig time floor", Economy.digTime(1, 1000) == GameConfig.Dig.MinDigTime)
check("ruby molten value", Economy.oreValue("ruby", "molten") == 260 * 20)
check("hardness ramps", Layers.hardnessAt(1) == 1 and Layers.hardnessAt(61) == GameConfig.Layers[2].hardness and Layers.hardnessAt(GameConfig.CoreDepth) == GameConfig.CoreHardness)
local value, count = Economy.backpackValue({ coal = { none = 3, flawless = 1 }, gold = { none = 2 } })
check("backpack value", value == 2 * 3 + 2 * 3 + 60 * 2 and count == 6, tostring(value))

if failures > 0 then error(failures .. " check(s) failed") end
print("all checks passed")
"""


def main():
    bundle = run_sim.build_bundle() + CHECKS
    out = run_sim.ROOT / "build" / "selftest_bundle.luau"
    out.parent.mkdir(exist_ok=True)
    out.write_text(bundle)
    sys.exit(subprocess.call([str(run_sim.ROOT / ".tools" / "luau"), str(out)]))


if __name__ == "__main__":
    main()
