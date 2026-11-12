"""Numpy z-buffer rasterizer for scene.Mesh triangle soups.

Pipeline: back-face cull -> near-plane clip -> project -> coverage of each
triangle's bounding box, evaluated for many triangles per numpy op (triangles
are bucketed by power-of-two box size) -> opaque z-buffer -> deferred shading
-> edge ink -> per-pixel sorted transparent fragments -> Neon glow -> box
filter down from the supersampled grid.

Images are float32 (H, W, 4) premultiplied RGBA in 0..1.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageFilter

from scene import Mesh

NEAR = 0.05
CHUNK = 1 << 20  # candidate pixels per vectorised batch
TIE = np.nextafter(0.0, 1.0)  # a pixel centre exactly on a shared edge goes to one side only
INK = np.array([0.05, 0.05, 0.07])
INK_SILHOUETTE, INK_SEAM, INK_CREASE = 0.85, 0.42, 0.3
CREASE_COS = np.cos(np.radians(35))
FLUSH = 1.02  # neighbouring depths within 2% count as touching, not occluding
GLOW_RADIUS, GLOW_STRENGTH = 0.012, 0.65  # radius as a fraction of image height


def _unit(v) -> np.ndarray:
    v = np.asarray(v, float)
    n = np.linalg.norm(v)
    return v / n if n > 0 else v


@dataclass(frozen=True)
class Camera:
    eye: np.ndarray
    right: np.ndarray
    up: np.ndarray
    forward: np.ndarray
    fov: float  # vertical field of view, degrees

    @classmethod
    def look_at(cls, eye, target, fov: float) -> Camera:
        eye = np.asarray(eye, float)
        forward = _unit(np.asarray(target, float) - eye)
        right = np.cross(forward, (0.0, 1.0, 0.0))
        right = _unit(right if np.linalg.norm(right) > 1e-9 else (1.0, 0.0, 0.0))
        return cls(eye, right, np.cross(right, forward), forward, float(fov))

    @classmethod
    def from_cframe(cls, cframe, fov: float) -> Camera:
        """Roblox Camera CFrame: columns are Right, Up, Back (LookVector = -Z)."""
        cf = np.asarray(cframe, float)
        rot = cf[3:].reshape(3, 3)
        return cls(cf[:3], rot[:, 0], rot[:, 1], -rot[:, 2], float(fov))


@dataclass(frozen=True)
class Lighting:
    to_light: np.ndarray  # unit vector pointing toward the light
    ambient: np.ndarray  # rgb
    diffuse: np.ndarray  # rgb, scaled by max(0, n . to_light)


@dataclass
class _Tris:
    src: np.ndarray  # (N,) mesh triangle index
    screen: np.ndarray  # (N, 3, 2) pixel coordinates, y down
    zinv: np.ndarray  # (N, 3) 1 / view depth
    normals: np.ndarray  # (N, 3, 3) world normals per corner

    def take(self, keep) -> _Tris:
        return _Tris(self.src[keep], self.screen[keep], self.zinv[keep], self.normals[keep])


@dataclass
class _Setup:
    """Per-triangle edge equations and pixel-centre bounding boxes."""

    tris: _Tris
    p: np.ndarray  # (N, 3, 2) canonical start point of each edge
    d: np.ndarray  # (N, 3, 2) edge vector, sign folded so the inside is positive
    bias: np.ndarray  # (N, 3) 0 or TIE
    inv_area2: np.ndarray  # (N,)
    x0: np.ndarray  # (N,) bucket origin, int
    y0: np.ndarray
    bw: np.ndarray  # (N,) bucket size, power of two clamped to the image
    bh: np.ndarray

    def take(self, keep) -> _Setup:
        rest = (getattr(self, f)[keep] for f in self.__dataclass_fields__ if f != "tris")
        return _Setup(self.tris.take(keep), *rest)


def _clip_near(src, view, normals):
    """Clip view-space triangles against z = NEAR, keeping winding and normals."""
    inside = view[..., 2] > NEAR
    count = inside.sum(1)
    keep = count == 3
    out = [(src[keep], view[keep], normals[keep])]
    for n_in in (1, 2):
        sel = np.nonzero(count == n_in)[0]
        if not len(sel):
            continue
        lone = np.argmax(inside[sel] if n_in == 1 else ~inside[sel], axis=1)
        order = ((lone[:, None] + np.arange(3)) % 3)[:, :, None]
        v = np.take_along_axis(view[sel], order, 1)
        n = np.take_along_axis(normals[sel], order, 1)
        t_ab = ((NEAR - v[:, 0, 2]) / (v[:, 1, 2] - v[:, 0, 2]))[:, None]
        t_ac = ((NEAR - v[:, 0, 2]) / (v[:, 2, 2] - v[:, 0, 2]))[:, None]
        ab, ac = v[:, 0] + (v[:, 1] - v[:, 0]) * t_ab, v[:, 0] + (v[:, 2] - v[:, 0]) * t_ac
        nab, nac = n[:, 0] + (n[:, 1] - n[:, 0]) * t_ab, n[:, 0] + (n[:, 2] - n[:, 0]) * t_ac
        if n_in == 1:  # lone corner inside: one smaller triangle
            out.append((src[sel], np.stack([v[:, 0], ab, ac], 1), np.stack([n[:, 0], nab, nac], 1)))
        else:  # lone corner outside: the remaining quad as two triangles
            out.append((src[sel], np.stack([ab, v[:, 1], v[:, 2]], 1), np.stack([nab, n[:, 1], n[:, 2]], 1)))
            out.append((src[sel], np.stack([ab, v[:, 2], ac], 1), np.stack([nab, n[:, 2], nac], 1)))
    return tuple(np.concatenate(parts) for parts in zip(*out))


def _project(mesh: Mesh, camera: Camera, width: int, height: int) -> _Tris:
    c = mesh.corners
    face = np.cross(c[:, 1] - c[:, 0], c[:, 2] - c[:, 0])
    facing = np.nonzero(np.einsum("ij,ij->i", face, c[:, 0] - camera.eye) < 0)[0]
    rel = c[facing] - camera.eye
    view = np.stack([rel @ camera.right, rel @ camera.up, rel @ camera.forward], -1)
    src, view, normals = _clip_near(facing, view, mesh.normals[facing])
    focal = (height / 2) / np.tan(np.radians(camera.fov) / 2)
    z = view[..., 2]
    screen = np.stack([width / 2 + focal * view[..., 0] / z, height / 2 - focal * view[..., 1] / z], -1)
    return _Tris(src, screen, 1 / z, normals)


def _next_pow2(n: np.ndarray) -> np.ndarray:
    return np.left_shift(1, np.ceil(np.log2(np.maximum(n, 1))).astype(np.int64))


def _setup(tris: _Tris, width: int, height: int) -> _Setup:
    s = tris.screen
    # Range of pixel indices whose centres (i + 0.5) fall inside the triangle's box.
    x0 = np.maximum(np.ceil(s[..., 0].min(1) - 0.5), 0)
    x1 = np.minimum(np.floor(s[..., 0].max(1) - 0.5), width - 1)
    y0 = np.maximum(np.ceil(s[..., 1].min(1) - 0.5), 0)
    y1 = np.minimum(np.floor(s[..., 1].max(1) - 0.5), height - 1)
    p, d, area = np.empty_like(s), np.empty_like(s), np.empty(s.shape[:2])
    for i in range(3):
        a, b, opposite = s[:, (i + 1) % 3], s[:, (i + 2) % 3], s[:, i]
        # Both triangles sharing an edge evaluate it from the same endpoint, so
        # their coverage tests are exact negations of each other (watertight).
        swap = (a[:, 0] > b[:, 0]) | ((a[:, 0] == b[:, 0]) & (a[:, 1] > b[:, 1]))
        p[:, i] = np.where(swap[:, None], b, a)
        d[:, i] = np.where(swap[:, None], a, b) - p[:, i]
        area[:, i] = d[:, i, 0] * (opposite[:, 1] - p[:, i, 1]) - d[:, i, 1] * (opposite[:, 0] - p[:, i, 0])
    sign = np.sign(area)
    ok = np.all(sign != 0, 1) & (x0 <= x1) & (y0 <= y1)
    bw = np.minimum(_next_pow2(x1 - x0 + 1), width)
    bh = np.minimum(_next_pow2(y1 - y0 + 1), height)
    return _Setup(
        tris=tris.take(ok),
        p=p[ok],
        d=(d * sign[:, :, None])[ok],
        bias=np.where(sign > 0, 0.0, TIE)[ok],
        inv_area2=1 / np.abs(area[ok, 0]),
        x0=np.minimum(x0, width - bw)[ok].astype(np.int64),
        y0=np.minimum(y0, height - bh)[ok].astype(np.int64),
        bw=bw[ok],
        bh=bh[ok],
    )


def _edge_values(st: _Setup, t, cx, cy):
    """Edge functions F_i (inside >= bias) for triangles t at centres cx (n, w), cy (n, h)."""
    for i in range(3):
        rows = st.d[t, i, 0, None] * (cy - st.p[t, i, 1, None])
        cols = st.d[t, i, 1, None] * (cx - st.p[t, i, 0, None])
        yield rows[..., :, None] - cols[..., None, :]


def _fragments(st: _Setup, width: int):
    """Yield (triangle, pixel id, barycentrics (n,3), 1/depth) for covered pixel centres."""
    sizes, bucket = np.unique(np.stack([st.bw, st.bh], 1), axis=0, return_inverse=True)
    for k, (bw, bh) in enumerate(sizes):
        ids = np.nonzero(bucket.ravel() == k)[0]
        per = max(1, CHUNK // int(bw * bh))
        ox, oy = np.arange(bw) + 0.5, np.arange(bh) + 0.5
        for start in range(0, len(ids), per):
            t = ids[start : start + per]
            cx, cy = st.x0[t, None] + ox, st.y0[t, None] + oy
            values = list(_edge_values(st, t, cx, cy))
            inside = (values[0] >= st.bias[t, 0, None, None]) & (values[1] >= st.bias[t, 1, None, None])
            inside &= values[2] >= st.bias[t, 2, None, None]
            ti, yi, xi = np.nonzero(inside)
            tri = t[ti]
            bary = np.stack([v[ti, yi, xi] for v in values], 1) * st.inv_area2[tri, None]
            zinv = (bary * st.tris.zinv[tri]).sum(1)
            yield tri, (st.y0[tri] + yi) * width + st.x0[tri] + xi, bary, zinv


def _pixel_barycentrics(st: _Setup, t, pid, width: int) -> np.ndarray:
    cx = (pid % width + 0.5)[:, None]
    cy = (pid // width + 0.5)[:, None]
    values = [v[:, 0, 0] for v in _edge_values(st, t, cx, cy)]
    return np.clip(np.stack(values, 1) * st.inv_area2[t, None], 0, None)


def _shade(st: _Setup, mesh: Mesh, light: Lighting, t, bary):
    """Lambert shading with perspective-correct normals; Neon is unlit."""
    w = bary * st.tris.zinv[t]
    w /= np.maximum(w.sum(1, keepdims=True), 1e-30)
    normal = np.einsum("ni,nij->nj", w, st.tris.normals[t])
    normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-12)
    src = st.tris.src[t]
    lit = light.ambient + light.diffuse * np.clip(normal @ light.to_light, 0, None)[:, None]
    rgb = mesh.color[src] * np.where(mesh.emissive[src, None], 1.0, lit)
    return np.clip(rgb, 0, 1), normal


def _opaque(st: _Setup, width: int, height: int):
    zbuf = np.zeros(width * height)  # 1/depth, 0 = empty
    tbuf = np.full(width * height, -1, np.int64)
    for tri, pid, _, zinv in _fragments(st, width):
        np.maximum.at(zbuf, pid, zinv)
        win = zinv >= zbuf[pid]
        tbuf[pid[win]] = tri[win]
    return zbuf, tbuf


def _neighbour(a: np.ndarray, dx: int, dy: int, fill) -> np.ndarray:
    """q[y, x] = a[y + dy, x + dx], `fill` outside the image."""
    q = np.full_like(a, fill)
    h, w = a.shape[:2]
    q[max(-dy, 0) : h - max(dy, 0), max(-dx, 0) : w - max(dx, 0)] = a[
        max(dy, 0) : h - max(-dy, 0), max(dx, 0) : w - max(-dx, 0)
    ]
    return q


def _edge_ink(part: np.ndarray, zinv: np.ndarray, normal: np.ndarray) -> np.ndarray:
    """Ink alpha per pixel: silhouettes on the occluding side, seams between touching parts, creases."""
    ink = np.zeros(part.shape)
    fg = part >= 0
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        for dist in (1, 2):
            q_part = _neighbour(part, dx * dist, dy * dist, -1)
            q_z = _neighbour(zinv, dx * dist, dy * dist, 0.0)
            other = fg & (q_part != part)
            occluding = other & (q_z * FLUSH < zinv)
            ink = np.maximum(ink, occluding * INK_SILHOUETTE)
            if dist == 1:
                seam = other & ~occluding & (q_z <= zinv * FLUSH)
                q_n = _neighbour(normal, dx, dy, 0.0)
                crease = fg & (q_part == part) & (np.einsum("hwc,hwc->hw", normal, q_n) < CREASE_COS)
                ink = np.maximum(ink, np.maximum(seam * INK_SEAM, crease * INK_CREASE))
    return ink


def _transparent(st: _Setup, mesh: Mesh, light: Lighting, zbuf, width: int, height: int):
    """Front-to-back composite of fragments in front of the opaque surface."""
    pids, depth, color, emit = [], [], [], []
    for tri, pid, bary, zinv in _fragments(st, width):
        front = zinv > zbuf[pid]
        if not front.any():
            continue
        tri, pid, bary, zinv = tri[front], pid[front], bary[front], zinv[front]
        rgb, _ = _shade(st, mesh, light, tri, bary)
        src = st.tris.src[tri]
        a = mesh.alpha[src]
        pids.append(pid)
        depth.append((1 / zinv).astype(np.float32))
        color.append(np.concatenate([rgb * a[:, None], a[:, None]], 1))
        emit.append(mesh.emissive[src])
    acc = np.zeros((width * height, 4))
    acc_emit = np.zeros((width * height, 3))
    if not pids:
        return acc, acc_emit
    pid, color, emit = np.concatenate(pids), np.concatenate(color), np.concatenate(emit)
    # Nearest first per pixel: positive float32 depth bits sort like the depths.
    key = (pid.astype(np.uint64) << np.uint64(32)) | np.concatenate(depth).view(np.uint32).astype(np.uint64)
    order = np.argsort(key)
    pid, color, emit = pid[order], color[order], emit[order]
    first = np.r_[True, pid[1:] != pid[:-1]]
    rank = np.arange(len(pid)) - np.maximum.accumulate(np.where(first, np.arange(len(pid)), 0))
    by_rank = np.argsort(rank, kind="stable")
    bounds = np.searchsorted(rank[by_rank], np.arange(rank.max() + 2))
    for r in range(rank.max() + 1):
        sel = by_rank[bounds[r] : bounds[r + 1]]
        p = pid[sel]
        contrib = color[sel] * (1 - acc[p, 3:4])
        acc[p] += contrib
        acc_emit[p] += contrib[:, :3] * emit[sel, None]
    return acc, acc_emit


def _glow(img: np.ndarray, emit: np.ndarray) -> np.ndarray:
    """Screen-blend a blurred copy of the emissive light over the image."""
    h = img.shape[0]
    src = Image.fromarray((np.clip(emit, 0, 1) * 255).astype(np.uint8))
    blur = np.asarray(src.filter(ImageFilter.GaussianBlur(GLOW_RADIUS * h)), np.float32) / 255
    out = img.copy()
    out[..., :3] = 1 - (1 - img[..., :3]) * (1 - blur * GLOW_STRENGTH)
    out[..., 3] = np.maximum(img[..., 3], blur.max(2) * GLOW_STRENGTH)
    return out


def render(
    mesh: Mesh,
    camera: Camera,
    width: int,
    height: int,
    light: Lighting,
    background=(0.0, 0.0, 0.0, 0.0),
    outline: bool = True,
    glow: bool = True,
    ssaa: int = 2,
) -> np.ndarray:
    """Render to a (height, width, 4) float32 premultiplied RGBA image."""
    big_w, big_h = width * ssaa, height * ssaa
    bg = np.asarray(background, float)
    img = np.tile(np.r_[bg[:3] * bg[3], bg[3]], (big_w * big_h, 1))
    emit = np.zeros((big_w * big_h, 3))
    st = _setup(_project(mesh, camera, big_w, big_h), big_w, big_h)
    solid = mesh.alpha[st.tris.src] >= 1
    opaque = st.take(solid)
    zbuf, tbuf = _opaque(opaque, big_w, big_h)
    covered = np.nonzero(tbuf >= 0)[0]
    part = np.full(big_w * big_h, -1, np.int64)
    normal = np.zeros((big_w * big_h, 3))
    if len(covered):
        t = tbuf[covered]
        rgb, normal[covered] = _shade(opaque, mesh, light, t, _pixel_barycentrics(opaque, t, covered, big_w))
        img[covered] = np.c_[rgb, np.ones(len(covered))]
        src = opaque.tris.src[t]
        part[covered] = mesh.part[src]
        emit[covered] = rgb * mesh.emissive[src, None]
    if outline:
        ink = _edge_ink(part.reshape(big_h, big_w), zbuf.reshape(big_h, big_w), normal.reshape(big_h, big_w, 3))
        ink = ink.reshape(-1, 1)
        img[:, :3] = img[:, :3] * (1 - ink) + INK * ink
    acc, acc_emit = _transparent(st.take(~solid), mesh, light, zbuf, big_w, big_h)
    img = acc + (1 - acc[:, 3:4]) * img
    emit = acc_emit + (1 - acc[:, 3:4]) * emit
    img = img.reshape(big_h, big_w, 4)
    if glow and emit.any():
        img = _glow(img, emit.reshape(big_h, big_w, 3))
    return img.reshape(height, ssaa, width, ssaa, 4).mean((1, 3)).astype(np.float32)


def to_image(rgba: np.ndarray) -> Image.Image:
    """Premultiplied float RGBA -> straight-alpha 8-bit PIL image."""
    a = rgba[..., 3:4]
    rgb = np.divide(rgba[..., :3], a, out=np.zeros_like(rgba[..., :3]), where=a > 1e-6)
    out = np.concatenate([np.clip(rgb, 0, 1), np.clip(a, 0, 1)], -1)
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA")
