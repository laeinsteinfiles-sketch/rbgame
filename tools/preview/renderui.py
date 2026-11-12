#!/usr/bin/env python3
"""Render a Roblox ScreenGui JSON to a PNG with Roblox layout semantics.

  python tools/preview/renderui.py ui.json out.png --viewport 1280x720 [--inset-top 58]
      [--inset-left 0] [--inset-right 0] [--inset-bottom 0] [--debug] [--backdrop scene.png]
"""
from __future__ import annotations

import argparse
import json
import math

import numpy as np
from PIL import Image, ImageDraw

import fonts
import raster
import ui_layout
import ui_paint
import ui_text
from scene import build_mesh
from ui_model import GRADIENT_CLASSES, IMAGE_CLASSES, Node, parse

DEFAULT_CAMERA_FOV = 70.0
DEBUG_COLOURS = [(255, 92, 92), (92, 200, 255), (130, 230, 110), (255, 196, 64), (220, 120, 255), (255, 140, 200)]
SAFE_AREA_COLOUR = (255, 255, 255, 110)


def safe_area(root: Node, viewport: tuple[int, int], insets: tuple[int, int, int, int]):
    """ScreenGui area (x, y, w, h): the viewport minus the insets its settings respect."""
    width, height = viewport
    top, left, right, bottom = insets
    mode = root["screenInsets"]
    if root["ignoreGuiInset"] and mode != "CoreUISafeInsets":
        top = 0
    if mode not in ("CoreUISafeInsets", "DeviceSafeInsets"):
        left = right = bottom = 0
    return float(left), float(top), float(width - left - right), float(height - top - bottom)


def corner_radius(node: Node) -> float:
    c = node.mod("UICorner")
    if not c:
        return 0.0
    m = min(node.rect[2], node.rect[3])
    return min(max(c["cornerRadius"][0] * m + c["cornerRadius"][1] * node.scale, 0.0), m / 2)


def _gradient(node: Node) -> dict | None:
    return node.mod("UIGradient") if node.cls in GRADIENT_CLASSES else None


def _stroke(node: Node) -> dict | None:
    s = node.mod("UIStroke")
    return s if s and s["transparency"] < 1 and s["thickness"] > 0 else None


def _glyph_outline(node: Node):
    """(thickness px, rgb, alpha) for UIStroke Contextual on text, else the legacy TextStroke."""
    s = _stroke(node)
    opacity = 1 - node["textTransparency"]
    if s and s["applyStrokeMode"] == "Contextual":
        return s["thickness"] * node.scale, s["color"], (1 - s["transparency"]) * opacity
    if node["textStrokeTransparency"] < 1:
        return max(1.0, node.scale), node["textStrokeColor3"], (1 - node["textStrokeTransparency"]) * opacity
    return None


def draw_text(canvas, node: Node, clip, grad):
    t = node.text
    if not any(t.lines):
        return
    outline = _glyph_outline(node)
    win = ui_paint.window(canvas, ui_text.glyph_box(t, outline[0] if outline else 0.0), clip)
    if win is None:
        return
    clip_cov = ui_paint.clip_coverage(win, clip)
    if outline:
        thickness, rgb, alpha = outline
        ui_paint.blend(canvas, win, rgb, ui_text.glyph_mask(t, win, thickness) * alpha * clip_cov)
    colour = np.asarray(node["textColor3"], np.float32)
    alpha = ui_text.glyph_mask(t, win) * (1 - node["textTransparency"]) * clip_cov
    if grad:
        g_rgb, g_alpha = ui_paint.gradient_at(grad, node.rect, *ui_paint.centres(win))
        colour, alpha = colour * g_rgb, alpha * g_alpha
    ui_paint.blend(canvas, win, colour, alpha)


def draw_viewport(canvas, node: Node, clip, grad):
    """3D parts through the rasterizer, lit like a ViewportFrame, tinted by ImageColor3."""
    x, y, w, h = node.rect
    size = (round(w), round(h))
    if not node["camera"] or not node["parts"] or min(size) < 1:
        return
    mesh = build_mesh(node["parts"])
    # ViewportFrame.LightDirection is the direction the light travels.
    light = raster.Lighting(-raster.unit(node["lightDirection"]), np.asarray(node["ambient"], float),
                            np.asarray(node["lightColor"], float))
    camera = raster.Camera.from_cframe(node["camera"]["cframe"], node["camera"].get("fov", DEFAULT_CAMERA_FOV))
    img = raster.render(mesh, camera, *size, light, outline=False, glow=False)
    img[..., :3] *= np.asarray(node["imageColor3"], np.float32)
    img *= 1 - node["imageTransparency"]
    if grad:
        g_rgb, g_alpha = ui_paint.gradient_at(grad, (0, 0, *size), *ui_paint.centres((0, 0, *size)))
        img[..., :3] *= g_rgb
        img *= g_alpha[..., None]
    ui_paint.paste(canvas, img, (round(x), round(y)), clip)


def draw_self(canvas, node: Node, clip):
    """Background, border stroke, then the object's own content (image, 3D view or text)."""
    if node.rect[2] <= 0 or node.rect[3] <= 0:
        return
    radius, grad = corner_radius(node), _gradient(node)
    if node["backgroundTransparency"] < 1:
        ui_paint.fill(canvas, node.rect, radius, node["backgroundColor3"], 1 - node["backgroundTransparency"],
                      clip, grad)
    s = _stroke(node)
    if s and not (node.is_text and s["applyStrokeMode"] == "Contextual"):
        ui_paint.stroke(canvas, node.rect, radius, s["thickness"] * node.scale, s["color"], 1 - s["transparency"], clip)
    if node.cls in IMAGE_CLASSES and node["image"] and node["imageTransparency"] < 1:
        ui_paint.image_placeholder(canvas, node.rect, radius, node["image"], node["imageColor3"],
                                   1 - node["imageTransparency"], clip, grad, node.scale)
    elif node.cls == "ViewportFrame":
        draw_viewport(canvas, node, clip, grad)
    elif node.is_text:
        draw_text(canvas, node, clip, grad)


def _rotated(node: Node) -> bool:
    return node["rotation"] % 360 != 0


def _clips(node: Node) -> bool:
    # A rotated object's own ClipsDescendants is unsupported in Roblox; CanvasGroup clips via its layer mask.
    return node.cls in ("ScrollingFrame", "ViewportFrame") or (node["clipsDescendants"] and not _rotated(node))


def draw_subtree(canvas, node: Node, clip):
    draw_self(canvas, node, clip)
    inner = ui_paint.intersect(clip, ui_paint.rect_box(node.rect)) if _clips(node) else clip
    for child in node.z_ordered():
        paint(canvas, child, inner)


def paint(canvas, node: Node, clip):
    """Draw a node and its descendants; rotation and CanvasGroup go through an RGBA layer."""
    if not _rotated(node) and node.cls != "CanvasGroup":
        draw_subtree(canvas, node, clip)
        return
    layer = np.zeros_like(canvas)
    draw_subtree(layer, node, ui_paint.full_box(layer))
    if node.cls == "CanvasGroup":
        ui_paint.mask_rounded(layer, node.rect, corner_radius(node))
        opacity = 1 - node["groupTransparency"]
        layer[..., :3] *= np.asarray(node["groupColor3"], np.float32) * opacity
        layer[..., 3] *= opacity
    if _rotated(node):
        x, y, w, h = node.rect
        layer = ui_paint.rotate(layer, (x + w / 2, y + h / 2), node["rotation"])
    ui_paint.composite(canvas, layer, clip)


def dusty_backdrop(width: int, height: int) -> np.ndarray:
    """Default backdrop: warm dark vertical gradient, soft vignette, fine grain."""
    t = np.linspace(0, 1, height, dtype=np.float32)[:, None, None]
    top, bottom = np.array([0.25, 0.215, 0.18], np.float32), np.array([0.075, 0.068, 0.062], np.float32)
    img = np.broadcast_to(top + (bottom - top) * t**0.8, (height, width, 3))
    xs = np.linspace(-1, 1, width, dtype=np.float32)[None, :, None]
    ys = np.linspace(-1, 1, height, dtype=np.float32)[:, None, None]
    img = img * (1 - 0.32 * np.clip(0.55 * xs**2 + 0.75 * ys**2, 0, 1))
    grain = np.random.default_rng(7).normal(0, 0.012, (height, width, 1)).astype(np.float32)
    return np.clip(img + grain, 0, 1)


def image_backdrop(path: str, width: int, height: int) -> np.ndarray:
    """An image scaled to cover the viewport, centre-cropped."""
    im = Image.open(path).convert("RGB")
    scale = max(width / im.width, height / im.height)
    im = im.resize((max(width, round(im.width * scale)), max(height, round(im.height * scale))), Image.LANCZOS)
    left, top = (im.width - width) // 2, (im.height - height) // 2
    return np.asarray(im.crop((left, top, left + width, top + height)), np.float32) / 255


def _corners(node: Node, transform: np.ndarray) -> list[tuple[float, float]]:
    x, y, w, h = node.rect
    pts = np.array([[x, y, 1], [x + w, y, 1], [x + w, y + h, 1], [x, y + h, 1]], float)
    return [tuple(p) for p in (pts @ transform.T)[:, :2]]


def _about(transform: np.ndarray, node: Node) -> np.ndarray:
    """Compose a node's rotation about its centre onto its parent's screen transform."""
    if not _rotated(node):
        return transform
    x, y, w, h = node.rect
    cx, cy = x + w / 2, y + h / 2
    c, s = math.cos(math.radians(node["rotation"])), math.sin(math.radians(node["rotation"]))
    rot = np.array([[c, -s, cx - c * cx + s * cy], [s, c, cy - s * cx - c * cy], [0, 0, 1]])
    return transform @ rot


def debug_overlay(img: Image.Image, root: Node):
    """Thin outline and name for every visible GuiObject, plus the ScreenGui safe area."""
    draw = ImageDraw.Draw(img, "RGBA")
    font = fonts.label(11)
    x, y, w, h = root.rect
    draw.rectangle((x, y, x + w - 1, y + h - 1), outline=SAFE_AREA_COLOUR)

    def walk(node: Node, transform: np.ndarray, depth: int):
        for child in node.z_ordered():
            t = _about(transform, child)
            colour = DEBUG_COLOURS[depth % len(DEBUG_COLOURS)]
            corners = _corners(child, t)
            draw.polygon(corners, outline=colour + (255,))
            lx, ly = corners[0]
            box = draw.textbbox((lx + 2, ly + 1), child["name"], font=font)
            draw.rectangle((box[0] - 2, box[1] - 1, box[2] + 2, box[3] + 1), fill=(0, 0, 0, 170))
            draw.text((lx + 2, ly + 1), child["name"], font=font, fill=colour + (255,))
            walk(child, t, depth + 1)

    walk(root, np.eye(3), 0)


def render(doc: dict, viewport: tuple[int, int], insets=(0, 0, 0, 0), backdrop: np.ndarray | None = None,
           debug: bool = False) -> tuple[Image.Image, Node]:
    """Lay out and draw a UI document; returns the RGB image and the laid-out tree."""
    width, height = viewport
    root = parse(doc)
    ui_layout.layout_screen(root, safe_area(root, viewport, insets))
    canvas = ui_paint.new_canvas(width, height)
    for child in root.z_ordered():
        paint(canvas, child, ui_paint.full_box(canvas))
    base = dusty_backdrop(width, height) if backdrop is None else backdrop
    rgb = canvas[..., :3] + base * (1 - canvas[..., 3:])
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
    if debug:
        debug_overlay(img, root)
    return img, root


def _size(text: str) -> tuple[int, int]:
    w, h = text.lower().split("x")
    return int(w), int(h)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ui")
    ap.add_argument("out")
    ap.add_argument("--viewport", type=_size, default=(1280, 720), help="WxH (default 1280x720)")
    ap.add_argument("--inset-top", type=int, default=0, help="core UI top bar inset, e.g. 58")
    ap.add_argument("--inset-left", type=int, default=0)
    ap.add_argument("--inset-right", type=int, default=0)
    ap.add_argument("--inset-bottom", type=int, default=0)
    ap.add_argument("--debug", action="store_true", help="outline and name every GuiObject")
    ap.add_argument("--backdrop", help="image to draw the UI over (scaled to cover the viewport)")
    args = ap.parse_args(argv)

    with open(args.ui) as f:
        doc = json.load(f)
    width, height = args.viewport
    backdrop = image_backdrop(args.backdrop, width, height) if args.backdrop else None
    insets = (args.inset_top, args.inset_left, args.inset_right, args.inset_bottom)
    img, root = render(doc, args.viewport, insets, backdrop, args.debug)
    img.save(args.out)
    x, y, w, h = root.rect
    print(f"{args.out}: {width}x{height}, ScreenGui area {w:g}x{h:g} at ({x:g}, {y:g})")


if __name__ == "__main__":
    main()
