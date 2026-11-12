#!/usr/bin/env python3
"""Regenerate tools/uipreview/robloxdb.luau (classes, members, defaults, enums).

Sources (downloaded into build/preview/cache/ on first use):
  * Roblox API dump (member lists, value types, tags, security, enums)
    https://github.com/MaximumADHD/Roblox-Client-Tracker  Full-API-Dump.json
  * rbx-dom reflection database (Instance.new default values per class)
    https://github.com/rojo-rbx/rbx-dom  rbx_dom_lua/src/database.json

Usage: python3 tools/uipreview/gen_robloxdb.py [--refresh]
The generated file is committed so the preview works offline.
"""
import argparse
import json
import pathlib
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CACHE = ROOT / "build" / "preview" / "cache"
OUT = HERE / "robloxdb.luau"

API_URL = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Full-API-Dump.json"
DOM_URL = "https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/rbx_dom_lua/src/database.json"

# Classes that get full member info (plus all their superclasses and all
# descendants of the roots below). Everything else is name + superclass only.
FULL_ROOTS = ["GuiBase", "UIBase", "LuaSourceContainer", "ValueBase", "BaseRemoteEvent",
              "PostEffect", "Light", "FaceInstance", "BackpackItem", "LayerCollector"]
FULL_EXTRA = [
    "Instance", "DataModel", "ServiceProvider", "Folder", "Configuration", "Model", "PVInstance",
    "BasePart", "Part", "FormFactorPart", "MeshPart", "WedgePart", "Camera", "Humanoid", "Player",
    "PlayerGui", "BasePlayerGui", "CoreGui", "StarterGui", "PlayerScripts", "StarterPlayer",
    "StarterPlayerScripts", "StarterCharacterScripts", "StarterPack", "Backpack", "Sound",
    "SoundGroup", "RemoteFunction", "BindableEvent", "BindableFunction", "Attachment",
    "ProximityPrompt", "Highlight", "ParticleEmitter", "Beam", "Trail", "Animation", "Animator",
    "AnimationController", "Team", "LocalizationTable", "GetTextBoundsParams", "TweenBase", "Tween",
    "InputObject", "Mouse", "PlayerMouse", "Translator", "TextChannel", "Accessory", "Accoutrement",
    "WorldRoot", "Workspace", "Atmosphere", "Sky", "Clouds", "Terrain", "SpawnLocation", "Seat",
    "Actor", "ObjectValue", "AnimationTrack", "UserGameSettings", "Path2D", "AdGui",
    "EditableImage", "Script", "LocalScript", "ModuleScript",
]

PRIM = {"bool": "b", "int": "i", "int64": "i", "float": "n", "double": "n", "string": "s"}


def fetch(url, name, refresh):
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / name
    if refresh or not path.exists():
        print("downloading", url)
        with urllib.request.urlopen(url, timeout=60) as r:
            path.write_bytes(r.read())
    return json.loads(path.read_text())


def lstr(s):
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == '"' or ch == "\\":
            out.append("\\" + ch)
        elif ch == "\n":
            out.append("\\n")
        elif o < 32 or o == 127:
            out.append("\\%d" % o)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def num(v):
    if v is None:
        return "math.huge"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    r = repr(round(float(v), 6))
    if r in ("inf", "-inf"):
        return "math.huge" if r == "inf" else "-math.huge"
    if r.endswith(".0"):
        r = r[:-2]
    return r


def vtype(vt):
    cat, name = vt.get("Category"), vt.get("Name")
    if cat == "Primitive":
        return PRIM.get(name, "?")
    if cat == "Enum":
        return "E:" + name
    if cat == "Class":
        return "I:" + name
    if cat == "DataType":
        return "T:" + name
    return "?"


def default_expr(typ, val):
    """rbx-dom default -> Luau expression using the runtime's constructors."""
    (kind, v), = val.items()
    if typ.startswith("E:"):
        if kind == "Enum":
            return "E(%s,%d)" % (lstr(typ[2:]), v)
        return None
    if kind == "Bool":
        return "true" if v else "false"
    if kind in ("Int32", "Int64", "Float32", "Float64"):
        return num(v)
    if kind in ("String", "ContentId"):
        return lstr(v)
    if kind == "Content":
        if typ == "T:ContentId" or typ == "s":
            return lstr(v if isinstance(v, str) and v != "None" else (v.get("Uri", "") if isinstance(v, dict) else ""))
        if isinstance(v, dict) and "Uri" in v:
            return "Content.fromUri(%s)" % lstr(v["Uri"])
        return "Content.none"
    if kind == "Color3":
        return "Color3.new(%s,%s,%s)" % tuple(num(x) for x in v)
    if kind == "Color3uint8":
        return "Color3.fromRGB(%s,%s,%s)" % tuple(num(x) for x in v)
    if kind == "UDim":
        return "UDim.new(%s,%s)" % (num(v[0]), num(v[1]))
    if kind == "UDim2":
        return "UDim2.new(%s,%s,%s,%s)" % (num(v[0][0]), num(v[0][1]), num(v[1][0]), num(v[1][1]))
    if kind == "Vector2":
        return "Vector2.new(%s,%s)" % (num(v[0]), num(v[1]))
    if kind == "Vector3":
        return "Vector3.new(%s,%s,%s)" % tuple(num(x) for x in v)
    if kind == "Rect":
        return "Rect.new(%s,%s,%s,%s)" % (num(v[0][0]), num(v[0][1]), num(v[1][0]), num(v[1][1]))
    if kind == "NumberRange":
        return "NumberRange.new(%s,%s)" % (num(v[0]), num(v[1]))
    if kind == "NumberSequence":
        kps = ",".join("NumberSequenceKeypoint.new(%s,%s,%s)" % (num(k["time"]), num(k["value"]), num(k.get("envelope", 0)))
                       for k in v["keypoints"])
        return "NumberSequence.new({%s})" % kps
    if kind == "ColorSequence":
        kps = ",".join("ColorSequenceKeypoint.new(%s,Color3.new(%s,%s,%s))" % ((num(k["time"]),) + tuple(num(c) for c in k["color"]))
                       for k in v["keypoints"])
        return "ColorSequence.new({%s})" % kps
    if kind == "Font":
        return "Font.new(%s,Enum.FontWeight.%s,Enum.FontStyle.%s)" % (lstr(v["family"]), v.get("weight", "Regular"), v.get("style", "Normal"))
    if kind == "BrickColor":
        return "BrickColor.new(%d)" % v
    if kind == "CFrame":
        p = v["position"]
        o = v["orientation"]
        return "CFrame.new(%s,%s,%s,%s)" % (num(p[0]), num(p[1]), num(p[2]), ",".join(num(x) for row in o for x in row))
    if kind == "Ref":
        return None
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true", help="re-download the sources")
    args = ap.parse_args()
    api = fetch(API_URL, "Full-API-Dump.json", args.refresh)
    dom = fetch(DOM_URL, "rbx-dom-database.json", args.refresh)
    classes = {c["Name"]: c for c in api["Classes"]}
    dom_classes = dom["Classes"]

    children = {}
    for c in api["Classes"]:
        children.setdefault(c.get("Superclass"), []).append(c["Name"])

    full = set()

    def add_desc(name):
        if name in full or name not in classes:
            return
        full.add(name)
        for ch in children.get(name, []):
            add_desc(ch)

    for r in FULL_ROOTS:
        add_desc(r)
    for n in FULL_EXTRA:
        if n in classes:
            full.add(n)
    for c in api["Classes"]:
        if "Service" in (c.get("Tags") or []):
            full.add(c["Name"])
    # superclasses of full classes are full too
    for n in list(full):
        s = classes[n].get("Superclass")
        while s and s in classes and s != "<<<ROOT>>>":
            full.add(s)
            s = classes[s].get("Superclass")

    lines = []
    lines.append("--!nocheck")
    lines.append("-- GENERATED by tools/uipreview/gen_robloxdb.py -- do not edit by hand.")
    lines.append("-- Roblox API dump + rbx-dom defaults (rbx-dom db version %s)." % ".".join(str(x) for x in dom.get("Version", [])))
    lines.append("-- Loaded by fakeroblox.luau: return function(ctors) -> { classes, enums }")
    lines.append("return function(Enum, E, UDim, UDim2, Vector2, Vector3, Color3, Rect, NumberRange, NumberSequence, NumberSequenceKeypoint, ColorSequence, ColorSequenceKeypoint, Font, BrickColor, CFrame, Content)")
    lines.append("local C = {}")
    nprops = 0
    for name in sorted(classes):
        c = classes[name]
        sup = c.get("Superclass")
        if sup == "<<<ROOT>>>":
            sup = None
        tags = c.get("Tags") or []
        flags = ""
        if "NotCreatable" not in tags and "Service" not in tags:
            flags += "c"
        if "Service" in tags:
            flags += "s"
        if "Deprecated" in tags:
            flags += "d"
        if name not in full:
            lines.append("C[%s]={s=%s,f=%s}" % (lstr(name), lstr(sup) if sup else "nil", lstr(flags)))
            continue
        flags += "F"
        props, methods, events, callbacks = [], [], [], []
        defaults = dom_classes.get(name, {}).get("DefaultProperties", {}) if "c" in flags or "s" in flags else {}
        for m in c["Members"]:
            mtags = m.get("Tags") or []
            if "NotScriptable" in mtags:
                continue
            sec = m.get("Security")
            rsec = sec.get("Read") if isinstance(sec, dict) else sec
            wsec = sec.get("Write") if isinstance(sec, dict) else sec
            if rsec not in ("None", None):
                continue
            mt = m["MemberType"]
            if mt == "Property":
                typ = vtype(m["ValueType"])
                ro = "ReadOnly" in mtags or wsec not in ("None", None)
                props.append((m["Name"], typ, ro))
            elif mt == "Function":
                methods.append(m["Name"])
            elif mt == "Event":
                events.append(m["Name"])
            elif mt == "Callback":
                callbacks.append(m["Name"])
        # property table: name -> "type" or "type!" (read-only)
        ptxt = ",".join("[%s]=%s" % (lstr(p), lstr(t + ("!" if ro else ""))) for p, t, ro in props)
        nprops += len(props)
        out = "C[%s]={s=%s,f=%s,p={%s}" % (lstr(name), lstr(sup) if sup else "nil", lstr(flags), ptxt)
        if methods:
            out += ",m={%s}" % ",".join(lstr(x) for x in methods)
        if events:
            out += ",e={%s}" % ",".join(lstr(x) for x in events)
        if callbacks:
            out += ",cb={%s}" % ",".join(lstr(x) for x in callbacks)
        out += "}"
        lines.append(out)
        if defaults and ("c" in flags or "s" in flags):
            # Defaults include inherited properties; types come from the declaring class.
            dl = []
            for pname, pval in sorted(defaults.items()):
                typ = None
                k = name
                while k and k in classes:
                    for m in classes[k]["Members"]:
                        if m["MemberType"] == "Property" and m["Name"] == pname:
                            typ = vtype(m["ValueType"])
                            break
                    if typ:
                        break
                    k = classes[k].get("Superclass")
                if not typ:
                    continue
                expr = default_expr(typ, pval)
                if expr is not None:
                    dl.append("[%s]=%s" % (lstr(pname), expr))
            lines.append("C[%s].d=function() return {%s} end" % (lstr(name), ",".join(dl)))
    lines.append("local EN = {}")
    for e in sorted(api["Enums"], key=lambda e: e["Name"]):
        items = ",".join("%s=%d" % (it["Name"] if it["Name"].isidentifier() else "[%s]" % lstr(it["Name"]), it["Value"]) for it in e["Items"])
        lines.append("EN[%s]={%s}" % (lstr(e["Name"]), items))
    lines.append("return { classes = C, enums = EN }")
    lines.append("end")
    OUT.write_text("\n".join(lines) + "\n")
    print("wrote %s: %d classes (%d full, %d props), %d enums, %d bytes" % (
        OUT.relative_to(ROOT), len(classes), len(full), nprops, len(api["Enums"]), OUT.stat().st_size))


if __name__ == "__main__":
    main()
