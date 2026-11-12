#!/usr/bin/env python3
"""Run tools/EconomySim.luau outside Studio with the luau CLI.

Bundles the pure shared modules (Config + Shared) into one chunk with a tiny
fake `script` tree so `require(script.Parent...)` resolves, then runs the sim.
Usage: python3 tools/run_sim.py [--seeds N] [--policy focused|casual] [--luau PATH]
"""
import argparse
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODULES = {
    "ReplicatedStorage/Shared/Types": "src/ReplicatedStorage/Shared/Types.luau",
    "ReplicatedStorage/Config/GameConfig": "src/ReplicatedStorage/Config/GameConfig.luau",
    "ReplicatedStorage/Shared/Hash": "src/ReplicatedStorage/Shared/Hash.luau",
    "ReplicatedStorage/Shared/Layers": "src/ReplicatedStorage/Shared/Layers.luau",
    "ReplicatedStorage/Shared/Economy": "src/ReplicatedStorage/Shared/Economy.luau",
    "ReplicatedStorage/Shared/OreGen": "src/ReplicatedStorage/Shared/OreGen.luau",
    "ReplicatedStorage/Shared/Course": "src/ReplicatedStorage/Shared/Course.luau",
    "ServerStorage/EconomySim": "tools/EconomySim.luau",
}

PRELUDE = r"""
local __nodes = {}
local __loaders = {}
local __cache = {}
local Node = {}
Node.__index = function(self, key)
    if key == "Parent" then return rawget(self, "__parent") end
    if key == "Name" then return rawget(self, "__name") end
    local child = rawget(self, "__children")[key]
    if child then return child end
    error("fake script tree: no child '" .. tostring(key) .. "' under " .. rawget(self, "__path"))
end
local function node(path)
    if __nodes[path] then return __nodes[path] end
    local parentPath, name = path:match("^(.*)/([^/]+)$")
    local n = setmetatable({ __path = path, __name = name or path, __children = {} }, Node)
    if parentPath and parentPath ~= "" then
        local p = node(parentPath)
        rawset(n, "__parent", p)
        rawget(p, "__children")[name] = n
    elseif path ~= "game" then
        local g = node("game")
        rawset(n, "__parent", g)
        rawget(g, "__children")[path] = n
    end
    __nodes[path] = n
    return n
end
local function require(target)
    local path = rawget(target, "__path")
    if __cache[path] ~= nil then return __cache[path] end
    local loader = __loaders[path] or error("fake script tree: no module at " .. path)
    local result = loader(target)
    __cache[path] = result
    return result
end
"""


def build_bundle():
    parts = [PRELUDE]
    for path, file in MODULES.items():
        source = (ROOT / file).read_text()
        parts.append(f"__loaders[{path!r}] = function(script)\n{source}\nend\nnode({path!r})\n")
    return "\n".join(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=40)
    ap.add_argument("--policy", default="focused")
    ap.add_argument("--luau", default=str(ROOT / ".tools" / "luau"))
    args = ap.parse_args()
    bundle = build_bundle() + f"""
local deps = {{
    GameConfig = require(node("ReplicatedStorage/Config/GameConfig")),
    Layers = require(node("ReplicatedStorage/Shared/Layers")),
    Economy = require(node("ReplicatedStorage/Shared/Economy")),
    OreGen = require(node("ReplicatedStorage/Shared/OreGen")),
    Course = require(node("ReplicatedStorage/Shared/Course")),
}}
require(node("ServerStorage/EconomySim")).run(deps, {{ seeds = {args.seeds}, policy = {args.policy!r} }})
"""
    out = ROOT / "build" / "sim_bundle.luau"
    out.parent.mkdir(exist_ok=True)
    out.write_text(bundle)
    sys.exit(subprocess.call([args.luau, str(out)]))


if __name__ == "__main__":
    main()
