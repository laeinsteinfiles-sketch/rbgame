"""Roblox GUI layout: AbsoluteSize/Position, constraints, padding, list and grid
layouts, AutomaticSize and UIScale.

Everything is in screen pixels. `k` is the product of the UIScales applied to a
node's offsets (UDim offsets, padding, constraint sizes, text sizes).
UIScale is applied after layout, about the object's anchor point, so siblings
in a list or grid do not reflow when an item is scaled.
"""
from __future__ import annotations

import math

import ui_text
from ui_model import INFINITE, Node

FRACTION = ui_text.FRACTION
SLACK = 1e-6


def _udim(u, length: float, k: float) -> float:
    return length * u[0] + u[1] * k


def _udim2(u, wh, k: float) -> tuple[float, float]:
    return wh[0] * u[0] + u[1] * k, wh[1] * u[2] + u[3] * k


def uiscale(node: Node) -> float:
    m = node.mod("UIScale")
    return float(m["scale"]) if m else 1.0


def padding(node: Node, wh, k: float) -> tuple[float, float, float, float]:
    """(left, top, right, bottom); scale padding is relative to the node's own size."""
    p = node.mod("UIPadding")
    if not p:
        return 0.0, 0.0, 0.0, 0.0
    return (_udim(p["left"], wh[0], k), _udim(p["top"], wh[1], k),
            _udim(p["right"], wh[0], k), _udim(p["bottom"], wh[1], k))


def _clamp_size(node: Node, w: float, h: float, k: float) -> tuple[float, float]:
    c = node.mod("UISizeConstraint")
    if not c:
        return w, h
    (min_w, min_h), (max_w, max_h) = c["minSize"], c["maxSize"]
    max_w = math.inf if max_w >= INFINITE else max_w * k
    max_h = math.inf if max_h >= INFINITE else max_h * k
    return max(min(w, max_w), min_w * k), max(min(h, max_h), min_h * k)


def _aspect(node: Node, w: float, h: float, parent_wh) -> tuple[float, float]:
    a = node.mod("UIAspectRatioConstraint")
    if not a or a["aspectRatio"] <= 0:
        return w, h
    ratio = float(a["aspectRatio"])
    if a["aspectType"] == "FitWithinMaxSize":
        return (h * ratio, h) if w > h * ratio else (w, w / ratio)
    w, h = (w, w / ratio) if a["dominantAxis"] == "Width" else (h * ratio, h)
    # ScaleWithParentSize never grows past the parent.
    fit = min([1.0] + [p / s for p, s in zip(parent_wh, (w, h)) if s > 0 and p > 0])
    return w * fit, h * fit


def _resolved_size(node: Node, parent_wh, k: float) -> tuple[float, float]:
    """AbsoluteSize before the node's own UIScale."""
    w, h = _udim2(node["size"], parent_wh, k)
    w, h = _aspect(node, *_clamp_size(node, w, h, k), parent_wh)
    auto = node["automaticSize"]
    if auto != "None":
        need_w, need_h = _content_extent(node, (w, h), k, auto)
        w = max(w, need_w) if "X" in auto else w
        h = max(h, need_h) if "Y" in auto else h
        w, h = _clamp_size(node, w, h, k)
    return max(w, 0.0), max(h, 0.0)


def _content_extent(node: Node, wh, k: float, auto: str) -> tuple[float, float]:
    """Size that contains the node's visible children and text, padding included."""
    pl, pt, pr, pb = padding(node, wh, k)
    inner = (wh[0] - pl - pr, wh[1] - pt - pb)
    need_w = need_h = 0.0
    kids = node.visible_children
    for child, (x, y, w, h) in zip(kids, _arrange(node, kids, inner, k)):
        s, (ax, ay) = uiscale(child), child["anchorPoint"]
        need_w = max(need_w, x + ax * w + (1 - ax) * w * s)
        need_h = max(need_h, y + ay * h + (1 - ay) * h * s)
    if node.is_text:
        wrap_width = inner[0] if node["textWrapped"] and "X" not in auto else None
        tw, th = ui_text.bounds(node, k, wrap_width)
        need_w, need_h = max(need_w, tw), max(need_h, th)
    return need_w + pl + pr, need_h + pt + pb


def _sorted(kids: list[Node], sort_order: str) -> list[int]:
    field = "name" if sort_order == "Name" else "layoutOrder"
    return sorted(range(len(kids)), key=lambda i: kids[i][field])


def _free(child: Node, size, inner, k: float):
    x, y = _udim2(child["position"], inner, k)
    ax, ay = child["anchorPoint"]
    return x - ax * size[0], y - ay * size[1], size[0], size[1]


def _lines(order, sizes, main: int, main_len: float, gap: float, wraps: bool) -> list[list[int]]:
    if not wraps:
        return [order]
    lines, current, used = [], [], 0.0
    for i in order:
        need = sizes[i][main] + (gap if current else 0.0)
        if current and used + need > main_len + SLACK:
            lines.append(current)
            current, need = [], sizes[i][main]
            used = 0.0
        current.append(i)
        used += need
    return lines + [current]


def _list(kids, sizes, lay: dict, inner, k: float):
    """UIListLayout: runs in sort order, aligned as a block on the main axis and per item across it."""
    horizontal = lay["fillDirection"] == "Horizontal"
    main, cross = (0, 1) if horizontal else (1, 0)
    gap = _udim(lay["padding"], inner[main], k)
    cross_gap = _udim(lay["padding"], inner[cross], k)
    main_frac = FRACTION[lay["horizontalAlignment"] if horizontal else lay["verticalAlignment"]]
    cross_frac = FRACTION[lay["verticalAlignment"] if horizontal else lay["horizontalAlignment"]]
    wraps = bool(lay["wraps"])
    lines = _lines(_sorted(kids, lay["sortOrder"]), sizes, main, inner[main], gap, wraps)
    line_cross = [max(sizes[i][cross] for i in line) for line in lines]
    block = sum(line_cross) + cross_gap * (len(lines) - 1)
    offset = (inner[cross] - block) * cross_frac if wraps else 0.0
    rects = [None] * len(kids)
    for line, thickness in zip(lines, line_cross):
        span = sum(sizes[i][main] for i in line) + gap * (len(line) - 1)
        along = (inner[main] - span) * main_frac
        room = thickness if wraps else inner[cross]
        for i in line:
            pos = [0.0, 0.0]
            pos[main] = along
            pos[cross] = offset + (room - sizes[i][cross]) * cross_frac
            rects[i] = (pos[0], pos[1], sizes[i][0], sizes[i][1])
            along += sizes[i][main] + gap
        offset += thickness + cross_gap
    return rects


def _grid(kids, grid: dict, inner, k: float):
    """UIGridLayout: CellSize cells filled along FillDirection, the block aligned in the content box."""
    cw, ch = _udim2(grid["cellSize"], inner, k)
    gx, gy = _udim2(grid["cellPadding"], inner, k)
    horizontal = grid["fillDirection"] == "Horizontal"
    room, cell, gap = (inner[0], cw, gx) if horizontal else (inner[1], ch, gy)
    per_line = int((room + gap + SLACK) // (cell + gap)) if cell + gap > 0 else len(kids)
    per_line = max(1, per_line)
    if grid["fillDirectionMaxCells"] > 0:
        per_line = min(per_line, int(grid["fillDirectionMaxCells"]))
    along, lines = min(len(kids), per_line), math.ceil(len(kids) / per_line)
    cols, rows = (along, lines) if horizontal else (lines, along)
    x0 = (inner[0] - (cols * cw + (cols - 1) * gx)) * FRACTION[grid["horizontalAlignment"]]
    y0 = (inner[1] - (rows * ch + (rows - 1) * gy)) * FRACTION[grid["verticalAlignment"]]
    rects = [None] * len(kids)
    for rank, i in enumerate(_sorted(kids, grid["sortOrder"])):
        line, slot = divmod(rank, per_line)
        col, row = (slot, line) if horizontal else (line, slot)
        rects[i] = (x0 + col * (cw + gx), y0 + row * (ch + gy), cw, ch)
    return rects


def _arrange(node: Node, kids: list[Node], inner, k: float):
    """Unscaled rects of `kids` relative to the content origin."""
    if not kids:
        return []
    grid = node.mod("UIGridLayout")
    if grid:
        return _grid(kids, grid, inner, k)
    sizes = [_resolved_size(c, inner, k) for c in kids]
    lst = node.mod("UIListLayout")
    if lst:
        return _list(kids, sizes, lst, inner, k)
    return [_free(c, size, inner, k) for c, size in zip(kids, sizes)]


def _place_contents(node: Node):
    x, y, w, h = node.rect
    pl, pt, pr, pb = padding(node, (w, h), node.scale)
    node.content = (x + pl, y + pt, w - pl - pr, h - pt - pb)
    if node.is_text:
        node.text = ui_text.layout(node, node.content, node.scale)
    cx, cy, cw, ch = node.content
    if node.cls == "ScrollingFrame":
        cx -= node["canvasPosition"][0] * node.scale
        cy -= node["canvasPosition"][1] * node.scale
    kids = node.visible_children
    for child, (rx, ry, rw, rh) in zip(kids, _arrange(node, kids, (cw, ch), node.scale)):
        _place(child, (cx + rx, cy + ry, rw, rh), node.scale)


def _place(node: Node, rect, k: float):
    """Commit an unscaled rect, apply the node's UIScale about its anchor point, recurse."""
    x, y, w, h = rect
    s, (ax, ay) = uiscale(node), node["anchorPoint"]
    px, py = x + ax * w, y + ay * h
    node.rect = (px - ax * w * s, py - ay * h * s, w * s, h * s)
    node.scale = k * s
    _place_contents(node)


def layout_screen(root: Node, area: tuple[float, float, float, float]):
    """Lay out a ScreenGui whose safe area is `area` (x, y, w, h).

    A UIScale on the ScreenGui scales offsets only: scale-based sizes still
    resolve against the full area (Roblox shrinks the virtual resolution).
    """
    root.rect = area
    root.scale = uiscale(root)
    _place_contents(root)
