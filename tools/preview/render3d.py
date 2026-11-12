#!/usr/bin/env python3
"""Render a scene JSON of Roblox parts to a PNG, optionally as a labelled grid of views.

  python tools/preview/render3d.py scene.json out.png [--views iso,front,side,top,back]
      [--size 1000x700] [--eye x,y,z --target x,y,z --fov 40] [--bg #rrggbb] [--no-outline]

Camera precedence: --eye, then --views, then the scene's "camera", then iso.
--size is the size of each view; several views are tiled into one image.
"""
from __future__ import annotations

import argparse
import json
import math
import time

import numpy as np
from PIL import Image, ImageDraw

import fonts
import raster
from scene import Mesh, build_mesh

# Camera position relative to the scene centre (Roblox front is -Z).
VIEWS = {
    "iso": (1, 0.75, -1),
    "front": (0, 0.15, -1),
    "back": (0, 0.15, 1),
    "side": (1, 0.15, 0),
    "top": (0, 1, -0.001),
}
DEFAULT_FOV = 40.0
DEFAULT_LIGHT = (0.4, 1, -0.3)  # direction the light comes from
DEFAULT_BG = (0.2, 0.22, 0.26)
AMBIENT, DIFFUSE = 0.5, 0.6
FIT_MARGIN = 1.03


def _vec3(text: str) -> tuple[float, float, float]:
    x, y, z = (float(v) for v in text.split(","))
    return x, y, z


def _size(text: str) -> tuple[int, int]:
    w, h = text.lower().split("x")
    return int(w), int(h)


def _hex(text: str) -> tuple[float, float, float]:
    h = text.lstrip("#")
    return tuple(int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))


def fitted_camera(mesh: Mesh, view: str, fov: float, aspect: float) -> raster.Camera:
    """Camera looking at the scene centre from `view`, far enough to fit the bounding sphere."""
    centre, radius = mesh.bounding_sphere()
    half_v = math.radians(fov) / 2
    half = min(half_v, math.atan(math.tan(half_v) * aspect))
    direction = raster.unit(VIEWS[view])
    return raster.Camera.look_at(centre + direction * radius * FIT_MARGIN / math.sin(half), centre, fov)


def scene_lighting(scene: dict) -> raster.Lighting:
    grey = np.ones(3)
    return raster.Lighting(raster.unit(scene.get("lightDirection", DEFAULT_LIGHT)), grey * AMBIENT, grey * DIFFUSE)


def _views(args, scene: dict, mesh: Mesh, aspect: float) -> list[tuple[str, raster.Camera]]:
    if args.eye:
        target = args.target or tuple(mesh.bounding_sphere()[0])
        return [("custom", raster.Camera.look_at(args.eye, target, args.fov or DEFAULT_FOV))]
    if args.views:
        names = [v.strip() for v in args.views.split(",") if v.strip()]
        unknown = [v for v in names if v not in VIEWS]
        if unknown:
            raise SystemExit(f"unknown view(s) {unknown}; choose from {sorted(VIEWS)}")
        return [(v, fitted_camera(mesh, v, args.fov or DEFAULT_FOV, aspect)) for v in names]
    if "camera" in scene:
        cam = scene["camera"]
        return [("camera", raster.Camera.look_at(cam["eye"], cam["target"], args.fov or cam.get("fov", DEFAULT_FOV)))]
    return [("iso", fitted_camera(mesh, "iso", args.fov or DEFAULT_FOV, aspect))]


def _caption(img: Image.Image, text: str):
    draw = ImageDraw.Draw(img)
    font = fonts.label(15)
    x0, y0, x1, y1 = draw.textbbox((0, 0), text, font=font)
    pad = 7
    draw.rounded_rectangle((10, 10, 10 + x1 - x0 + 2 * pad, 10 + y1 - y0 + 2 * pad), 6, fill=(12, 13, 16, 190))
    draw.text((10 + pad - x0, 10 + pad - y0), text, font=font, fill=(236, 234, 228, 255))


def tile(frames: list[tuple[str, Image.Image]], bg: tuple[float, float, float]) -> Image.Image:
    """One frame as-is; several as a labelled grid (3 columns for 5-6 views, 2 for 4)."""
    if len(frames) == 1:
        return frames[0][1]
    w, h = frames[0][1].size
    cols = len(frames) if len(frames) <= 3 else math.ceil(len(frames) / 2)
    rows = math.ceil(len(frames) / cols)
    sheet = Image.new("RGBA", (cols * w, rows * h), tuple(int(c * 255) for c in bg) + (255,))
    for i, (name, frame) in enumerate(frames):
        cell = frame.copy()
        _caption(cell, name.upper())
        sheet.paste(cell, ((i % cols) * w, (i // cols) * h))
    draw = ImageDraw.Draw(sheet)
    for c in range(1, cols):
        draw.line([(c * w, 0), (c * w, rows * h)], fill=(10, 11, 14, 255), width=2)
    for r in range(1, rows):
        draw.line([(0, r * h), (cols * w, r * h)], fill=(10, 11, 14, 255), width=2)
    return sheet


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("scene")
    ap.add_argument("out")
    ap.add_argument("--views", help="comma list of " + ",".join(VIEWS))
    ap.add_argument("--size", type=_size, default=(1000, 700), help="WxH per view (default 1000x700)")
    ap.add_argument("--eye", type=_vec3)
    ap.add_argument("--target", type=_vec3)
    ap.add_argument("--fov", type=float, help="vertical field of view in degrees (default 40)")
    ap.add_argument("--bg", type=_hex, help="background #rrggbb")
    ap.add_argument("--no-outline", dest="outline", action="store_false")
    args = ap.parse_args(argv)

    with open(args.scene) as f:
        scene = json.load(f)
    started = time.perf_counter()
    mesh = build_mesh(scene.get("parts", []))
    width, height = args.size
    bg = args.bg or tuple(scene.get("background", DEFAULT_BG))
    light = scene_lighting(scene)
    frames = []
    for name, camera in _views(args, scene, mesh, width / height):
        rgba = raster.render(mesh, camera, width, height, light, background=(*bg, 1.0), outline=args.outline)
        frames.append((name, raster.to_image(rgba)))
    tile(frames, bg).convert("RGB").save(args.out)
    print(
        f"{args.out}: {len(scene.get('parts', []))} parts, {len(mesh)} triangles, "
        f"{len(frames)} view(s) at {width}x{height} in {time.perf_counter() - started:.1f}s"
    )


if __name__ == "__main__":
    main()
