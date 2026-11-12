"""Anti-aliased drawing on premultiplied float32 RGBA canvases of shape (H, W, 4).

Rects are (x, y, w, h); clip boxes and windows are (x0, y0, x1, y1).
Shapes use signed distance fields, so coverage is exact on axis-aligned edges.
"""
from __future__ import annotations

import math

import numpy as np

Rect = tuple[float, float, float, float]
Box = tuple[float, float, float, float]

AVATAR_HEAD, AVATAR_BODY = 0.72, 0.55
HATCH_BASE, HATCH_LINE = 0.46, 0.56


def new_canvas(width: int, height: int) -> np.ndarray:
    return np.zeros((height, width, 4), np.float32)


def full_box(canvas: np.ndarray) -> Box:
    return 0.0, 0.0, float(canvas.shape[1]), float(canvas.shape[0])


def intersect(a: Box, b: Box) -> Box:
    return max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])


def rect_box(rect: Rect, grow: float = 0.0) -> Box:
    x, y, w, h = rect
    return x - grow, y - grow, x + w + grow, y + h + grow


def window(canvas: np.ndarray, box: Box, clip: Box):
    """Integer pixel window covering box & clip & canvas, or None when empty."""
    x0, y0, x1, y1 = intersect(intersect(box, clip), full_box(canvas))
    win = (math.floor(x0), math.floor(y0), math.ceil(x1), math.ceil(y1))
    return win if win[2] > win[0] and win[3] > win[1] else None


def centres(win) -> tuple[np.ndarray, np.ndarray]:
    """Pixel-centre coordinates of a window: xs (1, w), ys (h, 1)."""
    x0, y0, x1, y1 = win
    return np.arange(x0, x1, dtype=np.float32)[None, :] + 0.5, np.arange(y0, y1, dtype=np.float32)[:, None] + 0.5


def clip_coverage(win, clip: Box) -> np.ndarray:
    """Fraction of each pixel inside the clip box."""
    x0, y0, x1, y1 = win
    xs, ys = np.arange(x0, x1, dtype=np.float32), np.arange(y0, y1, dtype=np.float32)
    cx = np.clip(np.minimum(xs + 1, clip[2]) - np.maximum(xs, clip[0]), 0, 1)
    cy = np.clip(np.minimum(ys + 1, clip[3]) - np.maximum(ys, clip[1]), 0, 1)
    return cy[:, None] * cx[None, :]


def coverage(distance: np.ndarray) -> np.ndarray:
    return np.clip(0.5 - distance, 0, 1)


def rounded_sdf(xs, ys, rect: Rect, radius: float) -> np.ndarray:
    """Signed distance to a rounded rect (negative inside)."""
    x, y, w, h = rect
    qx = np.abs(xs - (x + w / 2)) - (w / 2 - radius)
    qy = np.abs(ys - (y + h / 2)) - (h / 2 - radius)
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    return outside + np.minimum(np.maximum(qx, qy), 0) - radius


def blend(canvas: np.ndarray, win, rgb, alpha: np.ndarray):
    """Source-over of straight `rgb` ((3,) or (h, w, 3)) with per-pixel `alpha` (h, w)."""
    x0, y0, x1, y1 = win
    dst = canvas[y0:y1, x0:x1]
    a = alpha[..., None]
    dst[..., :3] = np.asarray(rgb, np.float32) * a + dst[..., :3] * (1 - a)
    dst[..., 3:] = a + dst[..., 3:] * (1 - a)


def _sample(keys, t: np.ndarray) -> np.ndarray:
    """Piecewise-linear sequence lookup; repeated times give hard steps."""
    keys = np.asarray(sorted(keys, key=lambda kp: kp[0]), np.float32)
    times, values = keys[:, 0], keys[:, 1:]
    i = np.clip(np.searchsorted(times, t, side="right") - 1, 0, len(times) - 1)
    j = np.minimum(i + 1, len(times) - 1)
    span = times[j] - times[i]
    f = np.clip(np.where(span > 0, (t - times[i]) / np.where(span > 0, span, 1), 0), 0, 1)
    return values[i] + (values[j] - values[i]) * f[..., None]


def gradient_at(grad: dict, rect: Rect, xs, ys) -> tuple[np.ndarray, np.ndarray]:
    """UIGradient colour (h, w, 3) and opacity (h, w) at pixel centres.

    The gradient runs clockwise from left-to-right by `rotation`, its end points
    snapped to the rect's extent along that direction, shifted by offset * size.
    """
    x, y, w, h = rect
    theta = math.radians(grad["rotation"])
    c, s = math.cos(theta), math.sin(theta)
    rx = xs - (x + w / 2 + grad["offset"][0] * w)
    ry = ys - (y + h / 2 + grad["offset"][1] * h)
    half = 0.5 * (abs(c) * w + abs(s) * h)
    t = np.broadcast_to(0.5 + (rx * c + ry * s) / (2 * half) if half > 0 else np.float32(0.5), np.broadcast(xs, ys).shape)
    return _sample(grad["color"], t), 1 - _sample(grad["transparency"], t)[..., 0]


def fill(canvas, rect: Rect, radius: float, rgb, alpha: float, clip: Box, grad: dict | None = None):
    """Rounded-rect fill, optionally multiplied by a UIGradient."""
    win = window(canvas, rect_box(rect, 1), clip)
    if win is None:
        return
    xs, ys = centres(win)
    cov = coverage(rounded_sdf(xs, ys, rect, radius)) * clip_coverage(win, clip) * alpha
    colour = np.asarray(rgb, np.float32)
    if grad:
        g_rgb, g_alpha = gradient_at(grad, rect, xs, ys)
        colour, cov = colour * g_rgb, cov * g_alpha
    blend(canvas, win, colour, cov)


def stroke(canvas, rect: Rect, radius: float, thickness: float, rgb, alpha: float, clip: Box):
    """Outset border: the ring between the rounded rect and its offset by `thickness`."""
    win = window(canvas, rect_box(rect, thickness + 1), clip)
    if win is None:
        return
    xs, ys = centres(win)
    d = rounded_sdf(xs, ys, rect, radius)
    blend(canvas, win, rgb, (coverage(d - thickness) - coverage(d)) * clip_coverage(win, clip) * alpha)


def _disc(xs, ys, cx, cy, rx, ry) -> np.ndarray:
    """Approximate signed distance to an ellipse, good enough for anti-aliasing."""
    return (np.hypot((xs - cx) / rx, (ys - cy) / ry) - 1) * min(rx, ry)


def image_placeholder(canvas, rect: Rect, radius: float, image: str, tint, alpha: float, clip: Box,
                      grad: dict | None, scale: float):
    """rbxthumb:// -> grey avatar headshot; any other asset -> hatched grey tile."""
    win = window(canvas, rect_box(rect, 1), clip)
    if win is None:
        return
    xs, ys = centres(win)
    x, y, w, h = rect
    mask = coverage(rounded_sdf(xs, ys, rect, radius)) * clip_coverage(win, clip) * alpha
    if image.startswith("rbxthumb://"):
        m = min(w, h)
        body = coverage(_disc(xs, ys, x + w / 2, y + h * 1.04, m * 0.36, m * 0.34))
        head = coverage(_disc(xs, ys, x + w / 2, y + h * 0.42, m * 0.2, m * 0.2))
        union = head + body * (1 - head)  # head drawn over the shoulders
        grey = (AVATAR_HEAD * head + AVATAR_BODY * body * (1 - head)) / np.maximum(union, 1e-6)
        mask = mask * union
    else:
        period = 8 * scale
        u = np.mod((xs + ys) / math.sqrt(2), period)
        line = coverage(np.minimum(u, period - u) - 0.75 * scale)
        grey = HATCH_BASE + (HATCH_LINE - HATCH_BASE) * line
    colour = grey[..., None] * np.asarray(tint, np.float32)
    if grad:
        g_rgb, g_alpha = gradient_at(grad, rect, xs, ys)
        colour, mask = colour * g_rgb, mask * g_alpha
    blend(canvas, win, colour, mask)


def mask_rounded(layer: np.ndarray, rect: Rect, radius: float):
    """Keep only the part of a premultiplied layer inside a rounded rect."""
    cov = np.zeros(layer.shape[:2], np.float32)
    win = window(layer, rect_box(rect, 1), full_box(layer))
    if win is not None:
        xs, ys = centres(win)
        cov[win[1] : win[3], win[0] : win[2]] = coverage(rounded_sdf(xs, ys, rect, radius))
    layer *= cov[..., None]


def content_box(layer: np.ndarray):
    """Integer window around the layer's non-transparent pixels, or None."""
    rows, cols = np.nonzero(layer[..., 3].any(1))[0], np.nonzero(layer[..., 3].any(0))[0]
    if not len(rows):
        return None
    return int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1


def rotate(layer: np.ndarray, centre: tuple[float, float], degrees: float) -> np.ndarray:
    """Rotate a premultiplied layer clockwise (screen y is down) about `centre`, bilinear."""
    src = content_box(layer)
    out = np.zeros_like(layer)
    if src is None:
        return out
    theta = math.radians(degrees)
    c, s = math.cos(theta), math.sin(theta)
    cx, cy = centre
    corners = [(src[0], src[1]), (src[2], src[1]), (src[0], src[3]), (src[2], src[3])]
    xs_r = [cx + (px - cx) * c - (py - cy) * s for px, py in corners]
    ys_r = [cy + (px - cx) * s + (py - cy) * c for px, py in corners]
    win = window(layer, (min(xs_r) - 1, min(ys_r) - 1, max(xs_r) + 1, max(ys_r) + 1), full_box(layer))
    if win is None:
        return out
    xs, ys = centres(win)
    # Inverse map each destination centre to source pixel-index space.
    u = cx + (xs - cx) * c + (ys - cy) * s - 0.5
    v = cy - (xs - cx) * s + (ys - cy) * c - 0.5
    i0, j0 = np.floor(u).astype(np.int64), np.floor(v).astype(np.int64)
    fu, fv = (u - i0)[..., None], (v - j0)[..., None]
    h, w = layer.shape[:2]

    def tap(i, j):
        ok = ((i >= 0) & (i < w) & (j >= 0) & (j < h))[..., None]
        return np.where(ok, layer[np.clip(j, 0, h - 1), np.clip(i, 0, w - 1)], 0)

    out[win[1] : win[3], win[0] : win[2]] = (
        tap(i0, j0) * (1 - fu) * (1 - fv) + tap(i0 + 1, j0) * fu * (1 - fv)
        + tap(i0, j0 + 1) * (1 - fu) * fv + tap(i0 + 1, j0 + 1) * fu * fv
    )
    return out


def paste(canvas: np.ndarray, image: np.ndarray, origin: tuple[int, int], clip: Box):
    """Premultiplied source-over of `image` with its top-left at integer `origin`, limited to `clip`."""
    ox, oy = origin
    win = window(canvas, (ox, oy, ox + image.shape[1], oy + image.shape[0]), clip)
    if win is None:
        return
    x0, y0, x1, y1 = win
    src = image[y0 - oy : y1 - oy, x0 - ox : x1 - ox] * clip_coverage(win, clip)[..., None]
    dst = canvas[y0:y1, x0:x1]
    dst[:] = src + dst * (1 - src[..., 3:])


def composite(canvas: np.ndarray, layer: np.ndarray, clip: Box):
    """Premultiplied source-over of a same-size layer, limited to `clip`."""
    box = content_box(layer)
    if box is not None:
        x0, y0, x1, y1 = box
        paste(canvas, layer[y0:y1, x0:x1], (x0, y0), clip)
