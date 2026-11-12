"""Roblox part lists (scene JSON "parts") -> triangle meshes for raster.py.

Conventions follow Roblox: world = p + R @ local, Y up, a part's front is -Z.
"""
from __future__ import annotations

import functools
from dataclasses import dataclass

import numpy as np

SHAPES = ("Block", "Wedge", "Cylinder", "Ball")
CYLINDER_SEGMENTS = 24
BALL_SUBDIVISIONS = 2
NEON_WHITE_MIX = 0.2
GLASS_ALPHA = 0.45
SKIP_TRANSPARENCY = 0.98


@dataclass
class Mesh:
    corners: np.ndarray  # (T, 3, 3) world-space triangle corners, wound outward (CCW)
    normals: np.ndarray  # (T, 3, 3) unit normal per corner (equal on flat faces)
    color: np.ndarray  # (T, 3) linear 0..1 base colour
    alpha: np.ndarray  # (T,) opacity
    emissive: np.ndarray  # (T,) bool, Neon
    part: np.ndarray  # (T,) index of the source part

    def __len__(self) -> int:
        return len(self.corners)

    def bounding_sphere(self) -> tuple[np.ndarray, float]:
        if not len(self):
            return np.zeros(3), 1.0
        pts = self.corners.reshape(-1, 3)
        centre = (pts.min(0) + pts.max(0)) / 2
        return centre, max(float(np.linalg.norm(pts - centre, axis=1).max()), 1e-3)


def _wind_outward(corners: np.ndarray, normals: np.ndarray | None):
    """Flip triangles of a convex template so cross(b-a, c-a) points away from its centre."""
    centre = corners.reshape(-1, 3).mean(0)
    face = np.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
    flip = np.einsum("ij,ij->i", face, corners.mean(1) - centre) < 0
    corners[flip] = corners[flip][:, ::-1]
    if normals is not None:
        normals[flip] = normals[flip][:, ::-1]
    return corners, normals


def _quads(quads: list[list[tuple[float, float, float]]]) -> np.ndarray:
    tris = []
    for a, b, c, d in quads:
        tris += [(a, b, c), (a, c, d)]
    return np.array(tris, float)


def _block() -> np.ndarray:
    quads = []
    for axis in range(3):
        u, v = (i for i in range(3) if i != axis)
        for side in (-0.5, 0.5):
            quad = []
            for a, b in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)):
                p = [0.0, 0.0, 0.0]
                p[axis], p[u], p[v] = side, a, b
                quad.append(tuple(p))
            quads.append(quad)
    return _quads(quads)


def _wedge() -> np.ndarray:
    # Full bottom (y=-h) and back (z=+h) faces; the slope runs from the top-back
    # edge (y=+h, z=+h) down to the bottom-front edge (y=-h, z=-h).
    h = 0.5
    b0, b1, b2, b3 = (-h, -h, -h), (h, -h, -h), (h, -h, h), (-h, -h, h)
    t2, t3 = (h, h, h), (-h, h, h)
    tris = _quads([[b0, b1, b2, b3], [b3, b2, t2, t3], [b0, b1, t2, t3]]).tolist()
    tris += [[b0, b3, t3], [b1, b2, t2]]
    return np.array(tris, float)


def _cylinder() -> tuple[np.ndarray, np.ndarray]:
    # Axis along local X, length 1, radius 0.5; sides carry smooth radial normals.
    theta = np.linspace(0, 2 * np.pi, CYLINDER_SEGMENTS, endpoint=False)
    ring = np.stack([np.zeros_like(theta), np.cos(theta), np.sin(theta)], 1)
    corners, normals = [], []
    for k in range(CYLINDER_SEGMENTS):
        j = (k + 1) % CYLINDER_SEGMENTS
        lk, lj = ring[k] * 0.5 + (-0.5, 0, 0), ring[j] * 0.5 + (-0.5, 0, 0)
        rk, rj = ring[k] * 0.5 + (0.5, 0, 0), ring[j] * 0.5 + (0.5, 0, 0)
        corners += [(lk, lj, rj), (lk, rj, rk)]
        normals += [(ring[k], ring[j], ring[j]), (ring[k], ring[j], ring[k])]
        for x in (-0.5, 0.5):
            corners.append(((x, 0, 0), ring[k] * 0.5 + (x, 0, 0), ring[j] * 0.5 + (x, 0, 0)))
            normals.append([(np.sign(x), 0, 0)] * 3)
    return np.array(corners, float), np.array(normals, float)


def _ball() -> tuple[np.ndarray, np.ndarray]:
    g = (1 + 5**0.5) / 2
    verts = [(-1, g, 0), (1, g, 0), (-1, -g, 0), (1, -g, 0), (0, -1, g), (0, 1, g),
             (0, -1, -g), (0, 1, -g), (g, 0, -1), (g, 0, 1), (-g, 0, -1), (-g, 0, 1)]
    faces = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4),
             (11, 10, 2), (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8),
             (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    tris = np.array([[verts[i] for i in f] for f in faces], float)
    for _ in range(BALL_SUBDIVISIONS):
        a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
        ab, bc, ca = (a + b) / 2, (b + c) / 2, (c + a) / 2
        tris = np.concatenate([np.stack(t, 1) for t in ((a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca))])
    unit = tris / np.linalg.norm(tris, axis=2, keepdims=True)
    return unit * 0.5, unit


@functools.cache
def template(shape: str) -> tuple[np.ndarray, np.ndarray | None]:
    """Unit-size triangles for a shape; normals are None for flat-faced shapes."""
    if shape == "Wedge":
        return _wind_outward(_wedge(), None)
    if shape == "Cylinder":
        return _wind_outward(*_cylinder())
    if shape == "Ball":
        return _wind_outward(*_ball())
    return _wind_outward(_block(), None)


def _shape_scale(shape: str, size: np.ndarray) -> np.ndarray:
    if shape == "Cylinder":
        d = np.minimum(size[:, 1], size[:, 2])
        return np.stack([size[:, 0], d, d], 1)
    if shape == "Ball":
        d = size.min(1)
        return np.stack([d, d, d], 1)
    return size


def appearance(part: dict) -> tuple[tuple[float, float, float], float, bool] | None:
    """(rgb, alpha, emissive) for a part, or None when it should not be drawn."""
    material = part.get("material", "Plastic")
    transparency = float(part.get("transparency", 0))
    if material == "ForceField" or transparency >= SKIP_TRANSPARENCY:
        return None
    rgb = tuple(float(c) for c in part.get("color", (0.64, 0.64, 0.65)))
    alpha = 1.0 - transparency
    if material == "Neon":
        rgb = tuple(c + (1 - c) * NEON_WHITE_MIX for c in rgb)
    elif material == "Glass":
        alpha *= GLASS_ALPHA
    return rgb, alpha, material == "Neon"


def _flat_normals(corners: np.ndarray) -> np.ndarray:
    face = np.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
    length = np.linalg.norm(face, axis=1, keepdims=True)
    face = np.divide(face, length, out=np.zeros_like(face), where=length > 0)
    return np.repeat(face[:, None, :], 3, axis=1)


def _shape_group(shape: str, parts: list[dict], index: np.ndarray, looks: list) -> Mesh:
    corners, normals = template(shape)
    size = np.array([parts[i]["size"] for i in index], float).reshape(-1, 3)
    cframe = np.array([parts[i]["cframe"] for i in index], float).reshape(-1, 12)
    pos, rot = cframe[:, :3], cframe[:, 3:].reshape(-1, 3, 3)
    local = corners[None] * _shape_scale(shape, size)[:, None, None, :]
    world = np.einsum("pij,ptkj->ptki", rot, local) + pos[:, None, None, :]
    world = world.reshape(-1, 3, 3)
    if normals is None:
        world_normals = _flat_normals(world)
    else:
        world_normals = np.einsum("pij,tkj->ptki", rot, normals).reshape(-1, 3, 3)
    per_tri = len(corners)
    rgb = np.array([looks[i][0] for i in index], float)
    return Mesh(
        corners=world,
        normals=world_normals,
        color=np.repeat(rgb, per_tri, axis=0),
        alpha=np.repeat([looks[i][1] for i in index], per_tri).astype(float),
        emissive=np.repeat([looks[i][2] for i in index], per_tri).astype(bool),
        part=np.repeat(index, per_tri).astype(np.int64),
    )


def build_mesh(parts: list[dict]) -> Mesh:
    """Triangulate every drawable part; Mesh.part indexes back into `parts`.

    Shapes other than Wedge, Cylinder and Ball are drawn as Blocks.
    """
    looks = [appearance(p) for p in parts]
    shapes = [p.get("shape") if p.get("shape") in SHAPES else "Block" for p in parts]
    groups = []
    for shape in SHAPES:
        index = np.array([i for i, s in enumerate(shapes) if looks[i] and s == shape], np.int64)
        if len(index):
            groups.append(_shape_group(shape, parts, index, looks))
    if not groups:
        empty = np.zeros((0, 3, 3))
        return Mesh(empty, empty, np.zeros((0, 3)), np.zeros(0), np.zeros(0, bool), np.zeros(0, np.int64))
    return Mesh(*(np.concatenate([getattr(g, f) for g in groups]) for f in Mesh.__dataclass_fields__))
