"""Roblox font families -> FreeType fonts for the preview renderers."""
from __future__ import annotations

import functools
import sys
from pathlib import Path

from PIL import ImageFont, features

ROOT = Path(__file__).resolve().parents[2]
NUNITO = ROOT / ".tools" / "fonts" / "Nunito[wght].ttf"
FALLBACK = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")
FAMILIES = {"rbxasset://fonts/families/Nunito.json": NUNITO}
WEIGHT_AXES = {NUNITO: (200, 1000)}  # variable fonts and their wght range
LAYOUT = ImageFont.Layout.RAQM if features.check("raqm") else ImageFont.Layout.BASIC


@functools.cache
def _font_file(family: str) -> Path:
    path = FAMILIES.get(family)
    if path is None:
        print(f"preview: no font file for {family!r}; using DejaVu Sans Bold", file=sys.stderr)
        return FALLBACK
    if not path.exists():
        print(f"preview: {path.name} missing (run tools/preview/fetch_fonts.sh); using DejaVu Sans Bold",
              file=sys.stderr)
        return FALLBACK
    return path


@functools.lru_cache(maxsize=1024)
def _load(path: Path, weight: int, size: float) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(str(path), size, layout_engine=LAYOUT)
    if path in WEIGHT_AXES:
        lo, hi = WEIGHT_AXES[path]
        font.set_variation_by_axes([min(max(weight, lo), hi)])
    return font


def load(family: str, weight: int, size: float) -> ImageFont.FreeTypeFont:
    """Font for a Roblox FontFace at `size` px per em (Roblox TextSize = one line = 1 em)."""
    return _load(_font_file(family), int(weight), max(round(size * 4) / 4, 1.0))


def label(size: float) -> ImageFont.FreeTypeFont:
    """The preview tools' own caption font."""
    return load("rbxasset://fonts/families/Nunito.json", 800, size)
