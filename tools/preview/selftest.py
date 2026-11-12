#!/usr/bin/env python3
"""Checks the preview renderers against known pixel and layout facts, and renders the examples.

  python tools/preview/selftest.py [--out DIR] [--bench]

--out keeps the example renders (default: a temporary directory).
--bench also times a 3,000-part scene at 1000x700 (budget 60 s).
"""
from __future__ import annotations

import argparse
import math
import sys
import tempfile
import time
from pathlib import Path

import numpy as np

import raster
import render3d
import renderui
from scene import build_mesh

HERE = Path(__file__).resolve().parent
EXAMPLES = HERE / "examples"
VIEWPORT = (400, 300)
BACKDROP = np.full((VIEWPORT[1], VIEWPORT[0], 3), 0.5, np.float32)
GREY = (128, 128, 128)
NUNITO = "rbxasset://fonts/families/Nunito.json"
BG3D = (0.2, 0.2, 0.2)
failures: list[str] = []


def check(name: str, ok: bool, detail: str = ""):
    print(f"{'ok  ' if ok else 'FAIL'} {name}" + (f"  ({detail})" if detail and not ok else ""))
    if not ok:
        failures.append(name)


def close(a, b, tol=1.5) -> bool:
    return all(abs(x - y) <= tol for x, y in zip(np.ravel(a), np.ravel(b)))


# ---- UI ---------------------------------------------------------------------------------------

def frame(name, size, pos=(0, 0, 0, 0), color=(1, 0, 0), **kw):
    return {"class": kw.pop("cls", "Frame"), "name": name, "size": list(size), "position": list(pos),
            "backgroundColor3": list(color), **kw}


def ui(*children, **root):
    doc = {"root": {"class": "ScreenGui", "name": "Test", "children": list(children), **root}}
    img, tree = renderui.render(doc, VIEWPORT, insets=(30, 0, 0, 0), backdrop=BACKDROP)
    return np.asarray(img).astype(int), tree


def find(node, name):
    if node["name"] == name:
        return node
    for child in node.children:
        hit = find(child, name)
        if hit:
            return hit
    return None


def test_ui():
    px, tree = ui(frame("Red", (0, 100, 0, 50), (0, 40, 0, 20)))
    check("frame rect honours the top inset", close(find(tree, "Red").rect, (40, 50, 100, 50), 1e-6))
    check("red 100x50 frame is red at its centre", close(px[75, 90], (255, 0, 0)))
    check("pixels just outside the frame are untouched",
          all(close(px[y, x], GREY) for x, y in ((39, 75), (140, 75), (90, 49), (90, 100))))

    _, tree = ui(frame("Red", (0, 100, 0, 50)), ignoreGuiInset=True, screenInsets="None")
    check("IgnoreGuiInset + ScreenInsets None uses the full viewport", find(tree, "Red").rect[1] == 0)

    _, tree = ui(frame("List", (0, 200, 0, 200), (0, 0, 0, 0), modifiers=[
        {"class": "UIListLayout", "padding": [0, 5]}, {"class": "UIPadding", "top": [0, 10], "left": [0, 4]}],
        children=[frame("Second", (1, 0, 0, 20), layoutOrder=2), frame("Hidden", (1, 0, 0, 20), visible=False),
                  frame("First", (0.5, 0, 0, 20), layoutOrder=1)]))
    first, second = find(tree, "First").rect, find(tree, "Second").rect
    check("UIListLayout sorts by LayoutOrder, pads, skips invisible",
          close(first, (4, 40, 98, 20), 1e-6) and close(second, (4, 65, 196, 20), 1e-6), f"{first} {second}")

    _, tree = ui(frame("Grid", (0, 200, 0, 200), modifiers=[
        {"class": "UIGridLayout", "cellSize": [0, 40, 0, 30], "cellPadding": [0, 10, 0, 5],
         "fillDirectionMaxCells": 3}], children=[frame(f"C{i}", (0, 1, 0, 1), layoutOrder=i) for i in range(5)]))
    check("UIGridLayout wraps at FillDirectionMaxCells",
          close(find(tree, "C3").rect, (0, 65, 40, 30), 1e-6) and close(find(tree, "C2").rect, (100, 30, 40, 30), 1e-6))

    _, tree = ui(frame("Scaled", (0, 100, 0, 100), (0.5, 0, 0.5, 0), anchorPoint=[0.5, 0.5],
                       modifiers=[{"class": "UIScale", "scale": 0.5}],
                       children=[frame("Child", (0, 20, 0, 20), (0, 10, 0, 10))]))
    check("UIScale scales size and descendants about the anchor point",
          close(find(tree, "Scaled").rect, (175, 140, 50, 50), 1e-6)
          and close(find(tree, "Child").rect, (180, 145, 10, 10), 1e-6))

    _, tree = ui(frame("Fit", (0, 200, 0, 100), modifiers=[{"class": "UIAspectRatioConstraint", "aspectRatio": 1}]),
                 frame("Clamp", (1, 0, 0, 20), modifiers=[{"class": "UISizeConstraint", "maxSize": [140, 1e30]}]),
                 frame("ByWidth", (0.5, 0, 0, 10), modifiers=[{"class": "UIAspectRatioConstraint", "aspectRatio": 4,
                                                               "aspectType": "ScaleWithParentSize"}]))
    check("UIAspectRatioConstraint FitWithinMaxSize shrinks into the box", close(find(tree, "Fit").rect[2:], (100, 100)))
    check("UISizeConstraint clamps scale sizes", close(find(tree, "Clamp").rect[2:], (140, 20)))
    check("UIAspectRatioConstraint ScaleWithParentSize follows width", close(find(tree, "ByWidth").rect[2:], (200, 50)))

    _, tree = ui(frame("Auto", (0, 0, 0, 0), cls="TextLabel", text="Hello", textSize=20, fontFamily=NUNITO, automaticSize="XY",
                       modifiers=[{"class": "UIPadding", "left": [0, 10], "right": [0, 10], "top": [0, 3],
                                   "bottom": [0, 3]}]))
    auto = find(tree, "Auto")
    check("AutomaticSize XY fits text bounds plus padding",
          close(auto.rect[2:], (auto.text.widths[0] + 20, 26), 1e-3), f"{auto.rect}")

    _, tree = ui(frame("Tip", (0, 0, 0, 0), cls="TextLabel", text="Sell ore at the pad to buy a faster drill",
                       textSize=16, textWrapped=True, fontFamily=NUNITO, automaticSize="XY",
                       modifiers=[{"class": "UISizeConstraint", "maxSize": [120, 1e30]}]))
    tip = find(tree, "Tip")
    check("AutomaticSize XY text wraps at the UISizeConstraint max width",
          close(tip.rect[2], max(tip.text.widths), 1e-3) and tip.rect[2] <= 120 and len(tip.text.lines) >= 3
          and tip.rect[3] == 16 * len(tip.text.lines), f"{tip.rect}")

    _, tree = ui(frame("Big", (0, 300, 0, 200), cls="TextLabel", text="Hi", textScaled=True, fontFamily=NUNITO),
                 frame("Capped", (0, 300, 0, 200), cls="TextLabel", text="Hi", textScaled=True, fontFamily=NUNITO,
                       modifiers=[{"class": "UITextSizeConstraint", "minTextSize": 1, "maxTextSize": 24}]))
    check("TextScaled grows to 100 px; UITextSizeConstraint caps it",
          find(tree, "Big").text.size == 100 and find(tree, "Capped").text.size == 24)

    px, _ = ui(frame("Bar", (0, 100, 0, 20), (0.5, 0, 0.5, 0), anchorPoint=[0.5, 0.5], rotation=90))
    check("Rotation turns a horizontal bar vertical about its centre",
          close(px[165 - 40, 200], (255, 0, 0)) and close(px[165, 200 + 40], GREY))

    px, _ = ui(frame("Clip", (0, 50, 0, 50), (0, 10, 0, 10), clipsDescendants=True, color=(0, 0, 1),
                     children=[frame("Out", (0, 100, 0, 20), (0, 0, 0, 0))]))
    check("ClipsDescendants hides overflow", close(px[45, 30], (255, 0, 0)) and close(px[45, 80], GREY))

    px, _ = ui(frame("Group", (0, 60, 0, 60), cls="CanvasGroup", groupTransparency=0.5, color=(1, 1, 1)))
    check("CanvasGroup composites at 1 - GroupTransparency", close(px[70, 30], (191, 191, 191), 2), f"{px[70, 30]}")

    stripes = {"class": "UIGradient", "color": [[0, 1, 0, 0], [0.5, 1, 0, 0], [0.5, 0, 0, 1], [1, 0, 0, 1]]}
    px, _ = ui(frame("H", (0, 100, 0, 40), (0, 0, 0, 0), color=(1, 1, 1), modifiers=[stripes]),
               frame("V", (0, 40, 0, 100), (0, 200, 0, 0), color=(1, 1, 1), modifiers=[{**stripes, "rotation": 90}]))
    check("UIGradient rotation 0 runs left to right with a hard stop",
          close(px[50, 10], (255, 0, 0)) and close(px[50, 90], (0, 0, 255)) and close(px[50, 48], (255, 0, 0)))
    check("UIGradient rotation 90 runs top to bottom", close(px[40, 220], (255, 0, 0)) and close(px[120, 220], (0, 0, 255)))

    px, _ = ui(frame("Stroked", (0, 100, 0, 50), (0, 50, 0, 50), color=(1, 1, 1),
                     modifiers=[{"class": "UIStroke", "thickness": 4, "color": [0, 0, 1], "applyStrokeMode": "Border"}]))
    check("UIStroke Border is an outset ring", close(px[105, 48], (0, 0, 255)) and close(px[105, 52], (255, 255, 255))
          and close(px[105, 45], GREY))

    cube = {"name": "Cube", "shape": "Block", "size": [4, 4, 4], "cframe": [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1],
            "color": [1, 1, 1], "transparency": 0, "material": "Plastic"}
    cam = {"cframe": [0, 0, 10, 1, 0, 0, 0, 1, 0, 0, 0, 1], "fov": 40}
    px, _ = ui(frame("VP", (0, 120, 0, 120), (0, 0, 0, 0), cls="ViewportFrame", backgroundTransparency=1,
                     imageColor3=[0, 0, 0], camera=cam, parts=[cube]))
    check("ViewportFrame with ImageColor3 black draws a silhouette",
          close(px[90, 60], (0, 0, 0)) and close(px[35, 5], GREY))


# ---- 3D ---------------------------------------------------------------------------------------

def part(shape, size, rot=(1, 0, 0, 0, 1, 0, 0, 0, 1), pos=(0, 0, 0), color=(0.9, 0.3, 0.2), **kw):
    return {"name": shape, "shape": shape, "size": list(size), "cframe": [*pos, *rot], "color": list(color),
            "transparency": 0, "material": "Plastic", **kw}


def shot(parts, direction, fov=12.0, size=(240, 240)):
    """Render looking from `direction` (a view name or vector); returns (pixels, camera)."""
    mesh = build_mesh(parts)
    cam = render3d.fitted_camera(mesh, render3d.VIEWS.get(direction, direction), fov, size[0] / size[1])
    img = raster.render(mesh, cam, *size, render3d.scene_lighting({}), background=(*BG3D, 1.0))
    return np.asarray(raster.to_image(img))[..., :3].astype(int), cam


def project(cam, point, size=(240, 240)) -> tuple[int, int]:
    """Pixel (row, col) of a world point."""
    rel = np.asarray(point, float) - cam.eye
    z = rel @ cam.forward
    focal = size[1] / 2 / math.tan(math.radians(cam.fov) / 2)
    return int(size[1] / 2 - focal * (rel @ cam.up) / z), int(size[0] / 2 + focal * (rel @ cam.right) / z)


def silhouette(px):
    mask = np.any(np.abs(px - np.array(BG3D) * 255) > 6, axis=2)
    ys, xs = np.nonzero(mask)
    return mask, (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)


def aspect(px) -> float:
    _, (x0, y0, x1, y1) = silhouette(px)
    return (x1 - x0) / (y1 - y0)


def test_3d():
    # The side view looks along -X, so screen right is -Z: the tall back face (+Z) is on the left.
    mask, (x0, y0, x1, y1) = silhouette(shot([part("Wedge", (4, 4, 4))], "side")[0])
    w, h = x1 - x0, y1 - y0
    check("Wedge tall face is at +Z (side view)", mask[y0 + h // 3, x0 + w // 10]
          and not mask[y0 + h // 3, x1 - w // 8] and mask[y1 - h // 10, x1 - w // 4])

    cyl = [part("Cylinder", (6, 2, 2))]
    check("Cylinder axis is local X (3:1 from the front)", abs(aspect(shot(cyl, (0, 0, -1))[0]) - 3) < 0.15)
    check("Cylinder is round end-on (from +X)", abs(aspect(shot(cyl, (1, 0, 0))[0]) - 1) < 0.08)
    upright = [part("Cylinder", (6, 2, 2), rot=(0, -1, 0, 1, 0, 0, 0, 0, 1))]
    check("Cylinder rotated 90 about Z stands upright", abs(aspect(shot(upright, (0, 0, -1))[0]) - 1 / 3) < 0.03)
    check("Ball diameter is the smallest size component",
          abs(aspect(shot([part("Ball", (6, 2, 4))], (0, 0, -1))[0]) - 1) < 0.08)

    blue = (0.2, 0.6, 1.0)
    neon, cam = shot([part("Block", (4, 4, 4), color=blue, material="Neon")], "iso", fov=30)
    lit, _ = shot([part("Block", (4, 4, 4), color=blue)], "iso", fov=30)
    top, front = project(cam, (0, 2, 0)), project(cam, (0, 0, -2))
    check("Neon is unlit and brightened toward white", close(neon[top], neon[front], 3)
          and np.all(neon[front] >= np.array(blue) * 255 - 2) and not close(lit[top], lit[front], 3),
          f"neon {neon[top]} {neon[front]} lit {lit[top]} {lit[front]}")

    back = part("Block", (6, 6, 1), pos=(0, 0, 3), color=(1, 0, 0))
    front_part = part("Block", (3, 3, 1), pos=(0, 0, -3), color=(0, 0, 1), transparency=0.5)
    mix = shot([back, front_part], (0, 0, -1), fov=30)[0][120, 120]
    check("Transparent parts blend over what is behind them", mix[0] > 60 and mix[2] > 60, f"{mix}")

    hidden = [part("Block", (4, 4, 4), material="ForceField"), part("Block", (4, 4, 4), transparency=0.99)]
    check("ForceField and transparency >= 0.98 are skipped", len(build_mesh(hidden)) == 0)


# ---- examples and benchmark -------------------------------------------------------------------

def test_examples(out: Path):
    render3d.main([str(EXAMPLES / "shapes.json"), str(out / "shapes.png"), "--views", "iso,front,side,top,back",
                   "--size", "640x420"])
    renderui.main([str(EXAMPLES / "ui_showcase.json"), str(out / "ui_showcase.png"), "--viewport", "1280x720",
                   "--inset-top", "58"])
    check("examples render", (out / "shapes.png").exists() and (out / "ui_showcase.png").exists())


def stress_parts(n: int = 3000, seed: int = 1) -> list[dict]:
    """A dense block of mixed shapes, ~120k triangles."""
    rng = np.random.default_rng(seed)
    shapes = rng.choice(["Block", "Wedge", "Cylinder", "Ball"], n, p=[0.6, 0.2, 0.15, 0.05])
    parts = []
    for i, shape in enumerate(shapes):
        a = rng.uniform(0, 2 * math.pi)
        rot = (math.cos(a), 0, math.sin(a), 0, 1, 0, -math.sin(a), 0, math.cos(a))
        parts.append(part(str(shape), rng.uniform(1.2, 3.4, 3), rot,
                          ((i % 20) * 2.2 - 22, ((i // 20) % 10) * 2.2 + 1, (i // 200) * 2.2 - 16),
                          rng.uniform(0.2, 0.9, 3), material=str(rng.choice(["Plastic", "Neon", "Glass"],
                                                                             p=[0.9, 0.05, 0.05]))))
    return parts


def bench():
    parts = stress_parts()
    started = time.perf_counter()
    mesh = build_mesh(parts)
    cam = render3d.fitted_camera(mesh, render3d.VIEWS["iso"], 40, 1000 / 700)
    raster.render(mesh, cam, 1000, 700, render3d.scene_lighting({}), background=(*BG3D, 1.0))
    elapsed = time.perf_counter() - started
    print(f"bench: {len(parts)} parts, {len(mesh)} triangles, 1000x700 in {elapsed:.1f}s")
    check("3,000-part scene renders within 60 s", elapsed < 60)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, help="keep example renders in this directory")
    ap.add_argument("--bench", action="store_true")
    args = ap.parse_args()
    test_ui()
    test_3d()
    with tempfile.TemporaryDirectory() as tmp:
        out = args.out or Path(tmp)
        out.mkdir(parents=True, exist_ok=True)
        test_examples(out)
    if args.bench:
        bench()
    print("all checks passed" if not failures else f"{len(failures)} check(s) failed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
