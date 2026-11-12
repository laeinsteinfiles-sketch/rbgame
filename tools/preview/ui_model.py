"""ScreenGui JSON -> Node tree with Roblox defaults filled in."""
from __future__ import annotations

from dataclasses import dataclass

TEXT_CLASSES = {"TextLabel", "TextButton", "TextBox"}
IMAGE_CLASSES = {"ImageLabel", "ImageButton"}
GRADIENT_CLASSES = {"Frame", "TextLabel", "TextButton", "ImageLabel", "ImageButton", "ViewportFrame"}
INFINITE = 1e9  # UISizeConstraint maxSize at or above this means unbounded

DEFAULTS = {
    "name": "",
    "visible": True,
    "zIndex": 1,
    "layoutOrder": 0,
    "size": [0, 100, 0, 100],
    "position": [0, 0, 0, 0],
    "anchorPoint": [0, 0],
    "rotation": 0,
    "backgroundColor3": [1, 1, 1],
    "backgroundTransparency": 0,
    "clipsDescendants": False,
    "automaticSize": "None",
    "text": "",
    "textSize": 14,
    "textScaled": False,
    "textWrapped": False,
    "textColor3": [0, 0, 0],
    "textTransparency": 0,
    "textXAlignment": "Center",
    "textYAlignment": "Center",
    "fontFamily": "rbxasset://fonts/families/SourceSansPro.json",
    "fontWeight": 400,
    "textStrokeColor3": [0, 0, 0],
    "textStrokeTransparency": 1,
    "textTruncate": "None",
    "richText": False,
    "lineHeight": 1,
    "image": "",
    "imageColor3": [1, 1, 1],
    "imageTransparency": 0,
    "canvasPosition": [0, 0],
    "groupTransparency": 0,
    "groupColor3": [1, 1, 1],
    "ambient": [200 / 255] * 3,
    "lightColor": [140 / 255] * 3,
    "lightDirection": [-1, -1, -1],
    "camera": None,
    "parts": [],
}

MODIFIER_DEFAULTS = {
    "UICorner": {"cornerRadius": [0, 8]},
    "UIStroke": {"thickness": 1, "color": [0, 0, 0], "transparency": 0, "applyStrokeMode": "Contextual", "enabled": True},
    "UIGradient": {"color": [[0, 1, 1, 1], [1, 1, 1, 1]], "transparency": [[0, 0], [1, 0]], "rotation": 0,
                   "offset": [0, 0], "enabled": True},
    "UIPadding": {"top": [0, 0], "bottom": [0, 0], "left": [0, 0], "right": [0, 0]},
    "UIListLayout": {"fillDirection": "Vertical", "padding": [0, 0], "horizontalAlignment": "Left",
                     "verticalAlignment": "Top", "sortOrder": "LayoutOrder", "wraps": False},
    "UIGridLayout": {"cellSize": [0, 100, 0, 100], "cellPadding": [0, 5, 0, 5], "fillDirection": "Horizontal",
                     "horizontalAlignment": "Left", "verticalAlignment": "Top", "sortOrder": "LayoutOrder",
                     "fillDirectionMaxCells": 0},
    "UISizeConstraint": {"minSize": [0, 0], "maxSize": [INFINITE, INFINITE]},
    "UIAspectRatioConstraint": {"aspectRatio": 1, "aspectType": "FitWithinMaxSize", "dominantAxis": "Width"},
    "UIScale": {"scale": 1},
    "UITextSizeConstraint": {"minTextSize": 1, "maxTextSize": 100},
}

ROOT_DEFAULTS = {"name": "ScreenGui", "ignoreGuiInset": False, "screenInsets": "CoreUISafeInsets"}


@dataclass(eq=False)
class Node:
    cls: str
    props: dict
    modifiers: dict[str, dict]  # first modifier of each class
    children: list[Node]
    # Layout results, in screen pixels.
    rect: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 0.0)
    content: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 0.0)  # rect minus UIPadding
    scale: float = 1.0  # product of UIScales on this node and its ancestors
    text: object = None  # ui_text.TextLayout for text objects

    def __getitem__(self, key: str):
        return self.props[key]

    def mod(self, cls: str) -> dict | None:
        """The first modifier of a class, or None if absent or disabled."""
        m = self.modifiers.get(cls)
        return m if m and m.get("enabled", True) else None

    @property
    def is_text(self) -> bool:
        return self.cls in TEXT_CLASSES

    @property
    def visible_children(self) -> list[Node]:
        return [c for c in self.children if c["visible"]]

    def z_ordered(self) -> list[Node]:
        return sorted(self.visible_children, key=lambda c: c["zIndex"])


def _modifiers(raw: list[dict]) -> dict[str, dict]:
    found = {}
    for m in raw:
        cls = m.get("class")
        if cls in MODIFIER_DEFAULTS and cls not in found:
            found[cls] = {**MODIFIER_DEFAULTS[cls], **m}
    return found


def _node(raw: dict, defaults: dict) -> Node:
    return Node(
        cls=raw.get("class", "Frame"),
        props={**defaults, **{k: v for k, v in raw.items() if k not in ("children", "modifiers")}},
        modifiers=_modifiers(raw.get("modifiers", [])),
        children=[_node(c, DEFAULTS) for c in raw.get("children", [])],
    )


def parse(doc: dict) -> Node:
    """The ScreenGui root of a UI JSON document."""
    return _node(doc["root"], {**DEFAULTS, **ROOT_DEFAULTS})
