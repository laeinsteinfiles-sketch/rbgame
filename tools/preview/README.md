# Offline previews: 3D parts and Roblox GUI

Render part-built models and ScreenGui layouts to PNG without Roblox Studio, so
you can look at work in progress from a terminal. Roblox-side exporters write
JSON in the formats below; these tools turn it into images.

Only numpy and Pillow (with FreeType and raqm) are needed. In this repo, use the
project venv:

```sh
PY=.tools/venv/bin/python
tools/preview/fetch_fonts.sh            # once: Nunito (OFL) into .tools/fonts/ (git-ignored)
```

## Commands

```sh
# 3D: one view, or several tiled into a labelled grid (--size is per view)
$PY tools/preview/render3d.py scene.json out.png
$PY tools/preview/render3d.py scene.json out.png --views iso,front,side,top,back --size 640x420
$PY tools/preview/render3d.py scene.json out.png --eye 40,30,-40 --target 0,0,0 --fov 40
#   [--bg #rrggbb] [--no-outline]

# GUI: a ScreenGui tree laid out for a viewport, optionally over a 3D render
$PY tools/preview/renderui.py ui.json out.png --viewport 1280x720 --inset-top 58
$PY tools/preview/renderui.py ui.json out.png --viewport 1280x720 --inset-top 58 --backdrop scene.png
#   [--inset-left N] [--inset-right N] [--inset-bottom N] [--debug]

# Checks (layout and pixel facts, example renders); --bench times a 3,000-part scene
$PY tools/preview/selftest.py [--out DIR] [--bench]
```

`render3d.py` picks its camera from `--eye` (with `--target`, default the scene
centre), else `--views`, else the scene's `"camera"`, else `iso`. Named views
look at the scene centre from these directions, at a distance that fits the
scene's bounding sphere (Roblox's front is -Z):

| view  | camera direction from centre |
|-------|------------------------------|
| iso   | (+1, +0.75, -1)              |
| front | (0, 0.15, -1)                |
| back  | (0, 0.15, +1)                |
| side  | (+1, 0.15, 0)                |
| top   | (0, 1, -0.001)               |

`renderui.py --debug` outlines and names every visible GuiObject (rotated
outlines follow their objects) and marks the ScreenGui safe area. The default
backdrop is a dusty dark gradient. `--backdrop` scales an image to cover the
viewport and centre-crops it.

## Examples

Everything in [`examples/`](examples) can be regenerated with these commands:

| file | shows |
|------|-------|
| `shapes.json` -> `shapes.png` | every shape, rotated wedges and cylinders, Neon, Glass, transparency, skipped ForceField/0.99 parts; 5 views |
| `dig_site.json` -> `dig_site.png` | a 295-part model with a scene camera |
| `ui_showcase.json` -> `ui_showcase.png`, `ui_showcase_debug.png` | every modifier and object class, one card per feature |
| `hud.json` -> `hud.png` | a game HUD drawn over `dig_site.png` |

```sh
cd tools/preview
$PY render3d.py examples/shapes.json examples/shapes.png --views iso,front,side,top,back --size 640x420
$PY render3d.py examples/dig_site.json examples/dig_site.png --size 1280x720
$PY renderui.py examples/ui_showcase.json examples/ui_showcase.png --viewport 1280x720 --inset-top 58 [--debug]
$PY renderui.py examples/hud.json examples/hud.png --viewport 1280x720 --inset-top 58 --backdrop examples/dig_site.png
```

## 3D scene JSON

```json
{
  "parts": [
    {"name": "Ramp", "shape": "Wedge", "size": [4, 3, 6],
     "cframe": [0, 1.5, 0,  1, 0, 0,  0, 1, 0,  0, 0, 1],
     "color": [0.95, 0.7, 0.24], "transparency": 0, "material": "Plastic"}
  ],
  "camera": {"eye": [40, 30, -40], "target": [0, 0, 0], "fov": 40},
  "lightDirection": [0.4, 1, -0.3],
  "background": [0.2, 0.22, 0.26]
}
```

- `cframe` is `px, py, pz, R00, R01, R02, R10, R11, R12, R20, R21, R22`, and
  `world = p + R @ local`. Y is up; a part's front (LookVector) is -Z.
- **Block**: box of half-extents `size / 2`.
- **Wedge**: full bottom face (y = -sy/2) and full back face (z = +sz/2); the
  slope runs from the top-back edge down to the bottom-front edge.
- **Cylinder**: axis along local X, length `sx`, radius `min(sy, sz) / 2`, 24 segments.
- **Ball**: sphere of diameter `min(sx, sy, sz)` (subdivided icosahedron).
- Any other `shape` is drawn as a Block.
- Materials: `Neon` is unlit and lifted 20% toward white, with a soft glow;
  `Glass` has opacity `0.45 * (1 - transparency)`; `ForceField` and parts with
  transparency >= 0.98 are skipped; everything else is diffuse.
- `lightDirection` points toward the light (default `(0.4, 1, -0.3)`).
  Lighting is 0.5 ambient + 0.6 Lambert.
- Optional `camera.fov` is vertical, in degrees (default 40).

### Rasterizer

`raster.py` is a numpy z-buffer rasterizer: back-face culling, near-plane
clipping (cameras can sit inside a scene), and per-pixel depth on a 2x
supersampled grid, box-filtered down. Coverage is evaluated over every
triangle's bounding box, many triangles per numpy operation (bucketed by box
size). Shared edges are evaluated bit-identically from both sides, so meshes
have no cracks or double-covered pixels. Faces are flat-shaded. Ball and
Cylinder sides interpolate normals, so they read as round.

After the opaque pass, a dark ink pass draws silhouettes on the occluding side
of depth or part-id breaks, lighter seams between touching parts, and creases
above 35 degrees. `--no-outline` turns this off. Transparent fragments in front
of the opaque surface are then sorted per pixel and composited front to back.

Timing on this sandbox (2 vCPU), 1000x700:

| scene | time |
|-------|------|
| 3,000 mixed parts (119k triangles), dense block filling the frame, iso | 3.3 s |
| same scene, front view | 2.7 s |
| same scene, camera inside it at 70 degree FOV | 6.7 s |

## GUI JSON

The root is the ScreenGui:

```json
{"root": {"class": "ScreenGui", "name": "HUD", "ignoreGuiInset": false,
          "screenInsets": "CoreUISafeInsets", "children": [ ...nodes ]}}
```

A node has `class` (Frame, TextLabel, TextButton, TextBox, ImageLabel,
ImageButton, ScrollingFrame, ViewportFrame, CanvasGroup), `name`, `visible`,
`zIndex`, `layoutOrder`, `size` / `position` as `[xScale, xOffset, yScale, yOffset]`,
`anchorPoint`, `rotation`, `backgroundColor3`, `backgroundTransparency`,
`clipsDescendants`, `automaticSize`, `modifiers`, `children`. It also takes
class properties:

- **Text**: `text`, `textSize`, `textScaled`, `textWrapped`, `textColor3`,
  `textTransparency`, `textXAlignment`, `textYAlignment`, `fontFamily`,
  `fontWeight`, `textStrokeColor3`, `textStrokeTransparency`, `textTruncate`,
  `richText`, `lineHeight`.
- **Image**: `image`, `imageColor3`, `imageTransparency`.
- **ScrollingFrame**: `canvasPosition`.
- **CanvasGroup**: `groupTransparency`, `groupColor3`.
- **ViewportFrame**: `imageColor3`, `imageTransparency`, `ambient`,
  `lightColor`, `lightDirection`, `camera` (`cframe` as above, `fov`), and
  `parts` (3D parts as above).

Missing properties take Roblox defaults. Modifiers are objects with a `class`:
UICorner, UIStroke, UIGradient, UIPadding, UIListLayout, UIGridLayout,
UISizeConstraint, UIAspectRatioConstraint, UIScale, UITextSizeConstraint (see
`ui_model.py` for every field and default). When an object has several
modifiers of the same class, the first is used.

Fonts: `rbxasset://fonts/families/Nunito.json` maps to the Nunito variable font,
with `fontWeight` (e.g. 600 SemiBold, 700 Bold, 800 ExtraBold, 900 Heavy) set on
its weight axis. Other families fall back to DejaVu Sans Bold, with a warning on
stderr.

### Roblox semantics implemented

- **Safe area**: the viewport minus insets. The top inset applies unless
  IgnoreGuiInset is true and ScreenInsets is not CoreUISafeInsets. The
  left/right/bottom insets apply for CoreUISafeInsets and DeviceSafeInsets.
- **Size and position**: AbsoluteSize = parent content size * scale + offset,
  then UISizeConstraint, then UIAspectRatioConstraint. With FitWithinMaxSize it
  shrinks into the box; with ScaleWithParentSize the DominantAxis sets the other
  axis, never exceeding the parent. AbsolutePosition = content position +
  content size * scale + offset - anchorPoint * size. UIPadding (scale relative
  to the padded object) shrinks the content box for children and for text.
- **AutomaticSize** grows X/Y to fit visible children (after their own layout)
  and text bounds, never below the set size, then re-applies UISizeConstraint.
  Wrapped text that grows in X wraps at the UISizeConstraint max width.
- **UIListLayout**: visible children in LayoutOrder (stable) or Name order,
  Position ignored, UDim padding. The run is aligned on the main axis and each
  child across it. Wraps breaks runs into lines, which are aligned as a block.
- **UIGridLayout**: CellSize/CellPadding resolved against the content box,
  filled along FillDirection. It wraps when the next cell would not fit or at
  FillDirectionMaxCells, and the whole grid block is aligned in the content box.
- **UIScale** scales the object and its whole subtree (sizes, offsets, padding,
  strokes, text, corner radii) about its anchor point. On the ScreenGui, it
  scales offsets the way Roblox shrinks the virtual resolution.
- **Rotation** (clockwise, about the centre) renders the subtree to a layer and
  rotates it with bilinear filtering. A rotated object's own ClipsDescendants is
  ignored, as in Roblox. Rotated children are still clipped by unrotated
  clipping ancestors.
- **Draw order**: parent, then children by ZIndex (ties in insertion order).
  `visible = false` skips the subtree. ClipsDescendants, ScrollingFrame and
  ViewportFrame clip descendants to their rect; CanvasGroup clips to its
  rounded rect.
- **Background**: a rounded rect with radius `scale * min(w, h) + offset`,
  clamped to half the short side, anti-aliased from a signed distance field.
- **UIStroke** Border mode is an outset ring (outer radius = corner radius +
  thickness), drawn over the background and under children. Contextual mode on
  text outlines the glyphs with round joins; on other objects it behaves like
  Border. `enabled = false` or transparency >= 1 skips it.
- **UIGradient** multiplies the object's own colour and opacity: background,
  glyphs, image or ViewportFrame content, but not the stroke or descendants. It
  supports rotation (end points snap to the object's extent along that
  direction), offset as a fraction of the size, and repeated keypoint times for
  hard stripes. Following Roblox, it is ignored on ScrollingFrame, TextBox and
  CanvasGroup.
- **Text**: TextSize is the line height (1 em); LineHeight scales it.
  TextScaled picks the largest whole size up to 100 (or the
  UITextSizeConstraint max) that fits with word wrapping and without splitting
  words. UITextSizeConstraint also clamps a plain TextSize. Wrapping prefers
  spaces and splits words that are too long. Wrapped lines below the box are
  not drawn. AtEnd truncation cuts at a word boundary where it can and adds
  "...". Rich text tags are stripped (`<br/>` becomes a newline, entities are
  decoded). The legacy TextStroke is a 1 px outline.
- **Images**: `""` draws nothing. `rbxthumb://...` draws a grey avatar headshot;
  any other asset draws a grey hatched tile. Both are tinted by ImageColor3,
  faded by ImageTransparency, and rounded by UICorner.
- **ViewportFrame**: its parts go through the rasterizer with its camera
  (vertical FOV) at the frame's pixel size, with a transparent background, no
  ink and no glow. They are lit by `ambient + lightColor * max(0, n . -lightDirection)`
  (LightDirection is the direction the light travels; default
  (-1, -1, -1) lights from above), multiplied by ImageColor3 (black gives a
  silhouette), faded by ImageTransparency, and rounded by UICorner.
- **CanvasGroup**: the subtree is composited as one layer, tinted by
  GroupColor3 and faded by GroupTransparency.

### Not implemented, or approximated

- Real images: assets are placeholders. No ScaleType, slicing or ImageRectOffset.
- ScrollingFrame: CanvasSize and AutomaticCanvasSize are ignored. Children lay
  out in the frame's own content box, shifted by CanvasPosition, and no
  scrollbar is drawn.
- UIScale is applied after layout, so list and grid siblings do not reflow
  around a scaled child, and AutomaticSize measures its scaled footprint.
- UIListLayout flex options (HorizontalFlex, ItemLineAlignment, UIFlexItem),
  UIGridLayout StartCorner, UITableLayout, UIPageLayout.
- Per-corner UICorner radii; UIStroke BorderStrokePosition, LineJoinMode and
  StrokeSizingMode (strokes are outset, round, in pixels); UIGradient Scale,
  TileMode and radial Type.
- Rich text styling (bold, colour, size), TextDirection, localisation,
  TextBox placeholder and cursor, and SplitWord truncation. Text metrics come
  from FreeType, so line breaks can differ from Roblox by a word in edge cases.
- AutomaticSize combined with TextScaled uses TextSize. Children with scale
  sizes on an auto-sized axis resolve against the pre-growth size.
- Clipping inside a rotated ancestor happens in that ancestor's rotated frame,
  where Roblox may skip it.
- 3D: no shadows, textures, reflections, terrain, MeshParts, unions, decals or
  SurfaceGuis. CornerWedge and Truss are drawn as Blocks. Transparent parts
  get no ink lines.

## Files

| file | role |
|------|------|
| `render3d.py` | 3D CLI: cameras, named views, grid tiling |
| `scene.py` | parts -> triangle meshes, materials |
| `raster.py` | rasterizer |
| `renderui.py` | GUI CLI: safe area, painting, ViewportFrame, debug overlay, backdrops |
| `ui_model.py` | GUI JSON -> node tree with Roblox defaults |
| `ui_layout.py` | layout semantics |
| `ui_text.py` | text sizing, wrapping, truncation, glyph masks |
| `ui_paint.py` | anti-aliased shapes, gradients, placeholders, layers |
| `fonts.py` | font family -> FreeType font |
| `fetch_fonts.sh` | downloads Nunito |
| `selftest.py` | checks and example renders |
