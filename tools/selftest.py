#!/usr/bin/env python3
"""Ad-hoc runtime checks of the pure shared modules under the luau CLI.

Uses the same bundler as run_sim.py. Not a test framework: a handful of
invariants that type-checking cannot prove (hash determinism and spread,
quest set uniqueness, config sums, ore odds per layer).
"""
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import run_sim  # noqa: E402

CHECKS = r"""
local GameConfig = require(node("ReplicatedStorage/Config/GameConfig"))
local Hash = require(node("ReplicatedStorage/Shared/Hash"))
local Layers = require(node("ReplicatedStorage/Shared/Layers"))
local Economy = require(node("ReplicatedStorage/Shared/Economy"))
local OreGen = require(node("ReplicatedStorage/Shared/OreGen"))

local failures = 0
local function check(name, ok, detail)
    print((ok and "ok   " or "FAIL ") .. name .. (detail and ("  " .. detail) or ""))
    if not ok then failures += 1 end
end

-- Hash: deterministic, in range, roughly uniform
local same = Hash.u32(12345, 678, 11) == Hash.u32(12345, 678, 11)
check("hash deterministic", same)
local buckets = {0,0,0,0,0,0,0,0,0,0}
for i = 1, 20000 do
    local u = Hash.unit(99991, i, 11)
    assert(u >= 0 and u < 1)
    local b = math.floor(u * 10) + 1
    buckets[b] += 1
end
local minB, maxB = math.huge, 0
for _, n in buckets do minB = math.min(minB, n); maxB = math.max(maxB, n) end
check("hash spread (10 buckets of 20000)", minB > 1800 and maxB < 2200, string.format("min %d max %d", minB, maxB))
check("hash differs by salt", Hash.u32(1, 1, 11) ~= Hash.u32(1, 1, 23))
check("hash differs by seed", Hash.u32(1, 1, 11) ~= Hash.u32(2, 1, 11))

-- Mutation chances sum to 1, pet odds to 100
local mutSum = 0
for _, m in GameConfig.Mutations do mutSum += m.chance end
check("mutation chances sum to 1", math.abs(mutSum - 1) < 1e-9, tostring(mutSum))
local oddsSum = 0
for _, o in GameConfig.Pets.Odds do oddsSum += o.chance end
check("pet odds sum to 100", oddsSum == 100, tostring(oddsSum))

-- Ore odds per layer from the real generator
for li = 1, Layers.count() do
    local layer = Layers.get(li)
    local startI = layer.startDepth + 1
    local endI = Layers.endDepth(li)
    local ore, total = 0, 0
    for seed = 1, 20 do
        for i = startI, endI do
            total += 1
            if OreGen.roll(seed * 7919, i).oreId then ore += 1 end
        end
    end
    local frac = ore / total
    check("ore fraction " .. layer.name, frac > 0.30 and frac < 0.38, string.format("%.3f", frac))
end
check("core seal has no ore", OreGen.roll(42, GameConfig.CoreDepth).oreId == nil)

-- Economy
check("meta dig cap is +10%", math.abs(Economy.drillPower({drillTier = 1, metaDigLevel = 5, megaActive = false, catchUp = 0}) - 1.10) < 1e-9)
check("catch-up caps at 15%", Economy.catchUpBonus(100000) == 0.15 and Economy.catchUpBonus(0) == 0)
check("upgrade cost chain", Economy.upgradeCost("drill", 1) == 50 and Economy.upgradeCost("drill", 7) == nil)
check("ruby molten value", Economy.oreValue("ruby", "molten") == 4000)
check("hardness ramps", Layers.hardnessAt(1) == 1 and Layers.hardnessAt(151) == 2.5 and Layers.hardnessAt(451) == 5)

if failures > 0 then error(failures .. " check(s) failed") end
print("all checks passed")
"""


def main():
    bundle = run_sim.build_bundle() + CHECKS
    out = run_sim.ROOT / "build" / "selftest_bundle.luau"
    out.write_text(bundle)
    sys.exit(subprocess.call([str(run_sim.ROOT / ".tools" / "luau"), str(out)]))


if __name__ == "__main__":
    main()
