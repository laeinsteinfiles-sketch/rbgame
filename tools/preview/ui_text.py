"""Roblox text layout: font size (incl. TextScaled), wrapping, truncation, line placement."""
from __future__ import annotations

import html
import re
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import fonts

SCALED_MAX = 100
ELLIPSIS = "..."
SLACK = 0.01  # px of tolerance when testing whether text fits
FRACTION = {"Left": 0.0, "Top": 0.0, "Center": 0.5, "Right": 1.0, "Bottom": 1.0}
_TAG = re.compile(r"<[^<>]+>")
_BREAK = re.compile(r"<br\s*/?>", re.IGNORECASE)


@dataclass
class TextLayout:
    lines: list[str]
    font: ImageFont.FreeTypeFont
    size: float  # px per em, UIScale included
    origins: list[tuple[float, float]]  # left end of each line's baseline
    widths: list[float]
    bounds: tuple[float, float, float, float]  # x, y, w, h of the line boxes


def display_text(node) -> str:
    text = str(node["text"])
    if node["richText"]:
        text = html.unescape(_TAG.sub("", _BREAK.sub("\n", text)))
    return text


def _font(node, px: float) -> ImageFont.FreeTypeFont:
    return fonts.load(node["fontFamily"], node["fontWeight"], px)


def _line_factor(node) -> float:
    return min(max(float(node["lineHeight"]), 1.0), 3.0)


def _break_word(word: str, font, width: float) -> list[str]:
    pieces, current = [], ""
    for ch in word:
        if current and font.getlength(current + ch) > width + SLACK:
            pieces.append(current)
            current = ch
        else:
            current += ch
    return pieces + [current]


def wrap(text: str, font, width: float) -> tuple[list[str], bool]:
    """Greedy wrap preferring spaces; long words are split. Returns (lines, no word was split)."""
    lines, whole = [], True
    for paragraph in text.split("\n"):
        line = None
        for word in paragraph.split(" "):
            trial = word if line is None else f"{line} {word}"
            if font.getlength(trial) <= width + SLACK:
                line = trial
                continue
            if line is not None:
                lines.append(line)
            if font.getlength(word) <= width + SLACK:
                line = word
                continue
            whole = False
            *done, line = _break_word(word, font, width)
            lines += done
        lines.append(line or "")
    return lines, whole


def _size_range(node) -> tuple[int, int] | None:
    c = node.mod("UITextSizeConstraint")
    return (int(c["minTextSize"]), int(c["maxTextSize"])) if c else None


def _fitted_size(node, text: str, width: float, height: float) -> int:
    """TextScaled: the largest whole size whose wrapped text fits without splitting words."""
    lo, hi = _size_range(node) or (1, SCALED_MAX)
    factor = _line_factor(node)
    best, a, b = lo, lo, hi
    while a <= b:
        mid = (a + b) // 2
        lines, whole = wrap(text, _font(node, mid), width)
        if whole and len(lines) * mid * factor <= height + SLACK:
            best, a = mid, mid + 1
        else:
            b = mid - 1
    return best


def text_size(node) -> float:
    """TextSize clamped by a UITextSizeConstraint (unscaled px)."""
    size = float(node["textSize"])
    limits = _size_range(node)
    return min(max(size, limits[0]), limits[1]) if limits else size


def ellipsize(line: str, font, width: float, force: bool = False) -> str:
    """AtEnd truncation: cut at a word boundary where possible and append an ellipsis."""
    if not force and font.getlength(line) <= width + SLACK:
        return line
    if font.getlength(line + ELLIPSIS) <= width + SLACK:
        return line + ELLIPSIS
    words = line.split(" ")
    for n in range(len(words) - 1, 0, -1):
        candidate = " ".join(words[:n]).rstrip() + ELLIPSIS
        if font.getlength(candidate) <= width + SLACK:
            return candidate
    a, b = 0, len(line)
    while a < b:
        mid = (a + b + 1) // 2
        if font.getlength(line[:mid] + ELLIPSIS) <= width + SLACK:
            a = mid
        else:
            b = mid - 1
    return line[:a] + ELLIPSIS


def bounds(node, scale: float, wrap_width: float | None) -> tuple[float, float]:
    """TextBounds for AutomaticSize: wrapped at wrap_width, or one line per paragraph."""
    text = display_text(node)
    px = text_size(node) * scale
    font = _font(node, px)
    lines = wrap(text, font, wrap_width)[0] if wrap_width is not None else text.split("\n")
    width = max((font.getlength(line) for line in lines), default=0.0)
    return width, len(lines) * px * _line_factor(node)


def layout(node, content: tuple[float, float, float, float], scale: float) -> TextLayout:
    """Place the node's text inside its content box (screen px)."""
    text = display_text(node)
    x, y, w, h = content
    wrapped = node["textWrapped"] or node["textScaled"]
    size = _fitted_size(node, text, w / scale, h / scale) if node["textScaled"] else text_size(node)
    px = size * scale
    font = _font(node, px)
    line_h = px * _line_factor(node)
    overflow = False
    if wrapped:
        lines, _ = wrap(text, font, w)
        keep = max(1, int((h + SLACK) // line_h))  # lines past the box height are not drawn
        overflow = len(lines) > keep
        lines = lines[:keep]
    else:
        lines = text.split("\n")
    if node["textTruncate"] == "AtEnd":
        if overflow:
            lines[-1] = ellipsize(lines[-1], font, w, force=True)
        else:
            lines = [ellipsize(line, font, w) for line in lines]
    widths = [font.getlength(line) for line in lines]
    block_h = len(lines) * line_h
    top = y + (h - block_h) * FRACTION[node["textYAlignment"]]
    ascent, descent = font.getmetrics()
    baseline = (line_h + ascent - descent) / 2  # glyph box centred in each line box
    fx = FRACTION[node["textXAlignment"]]
    origins = [(x + (w - lw) * fx, top + i * line_h + baseline) for i, lw in enumerate(widths)]
    left = min((o[0] for o in origins), default=x)
    return TextLayout(lines, font, px, origins, widths, (left, top, max(widths, default=0.0), block_h))


def glyph_box(t: TextLayout, stroke: float) -> tuple[int, int, int, int]:
    """Integer pixel box that contains every glyph (plus `stroke` outset)."""
    margin = t.size * 0.6 + stroke + 2
    x, y, w, h = t.bounds
    return (int(np.floor(x - margin)), int(np.floor(y - margin)),
            int(np.ceil(x + w + margin)), int(np.ceil(y + h + margin)))


def glyph_mask(t: TextLayout, box: tuple[int, int, int, int], stroke: float = 0.0) -> np.ndarray:
    """Coverage (h, w) of the glyphs inside `box`, outset by `stroke` px with round joins."""
    x0, y0, x1, y1 = box
    im = Image.new("L", (x1 - x0, y1 - y0))
    draw = ImageDraw.Draw(im)
    for line, (ox, oy) in zip(t.lines, t.origins):
        draw.text((ox - x0, oy - y0), line, font=t.font, fill=255, anchor="ls", stroke_width=stroke)
    return np.asarray(im, np.float32) / 255
