#!/usr/bin/env python3
"""Render sections / elevations / plans of the CoreDesign-only dump (@@P lines from tests/core_only.luau).

usage: tools/luau tests/core_only.luau -a --dump | python3 tests/core_render.py OUTDIR
"""
import json, sys, os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon

out = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(out, exist_ok=True)
parts = []
for line in sys.stdin:
    if line.startswith("[print] "):
        line = line[8:]
    if line.startswith("@@P "):
        parts.append(json.loads(line[4:]))
    elif line.startswith("core_only") or "FAIL" in line or line.startswith("[print] tier"):
        print(line.rstrip())

EDGES = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]


def corners(p):
    c = np.array(p["cf"][:3])
    R = np.array(p["cf"][3:]).reshape(3, 3)
    s = np.array(p["size"]) / 2
    pts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                pts.append(c + R @ (s * np.array([sx, sy, sz])))
    return np.array(pts)


for p in parts:
    p["corners"] = corners(p)


def hull(pts):
    pts = sorted(set(map(tuple, np.round(pts, 6))))
    if len(pts) < 3:
        return np.array(pts)
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for q in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], q) <= 0:
            lower.pop()
        lower.append(q)
    for q in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], q) <= 0:
            upper.pop()
        upper.append(q)
    return np.array(lower[:-1] + upper[:-1])


def section(p, axis, v):
    """polygon (in the two remaining axes) of the box cut by plane coord[axis]=v"""
    C = p["corners"]
    other = {0: [2, 1], 1: [0, 2], 2: [0, 1]}[axis]  # (horizontal, vertical) plot axes
    pts = []
    for a, b in EDGES:
        da, db = C[a][axis] - v, C[b][axis] - v
        if abs(da) < 1e-9:
            pts.append(C[a][other])
        if (da < 0 < db) or (db < 0 < da):
            t = da / (da - db)
            pts.append((C[a] + t * (C[b] - C[a]))[other])
    if len(pts) < 3:
        return None
    return hull(np.array(pts))


def style(p):
    col = np.array(p["color"]) / 255
    if p["t"] >= 0.99:
        return dict(facecolor="none", edgecolor="red", linestyle="--", linewidth=0.8)
    return dict(facecolor=col, edgecolor=(0, 0, 0, 0.45), linewidth=0.3, alpha=1 - 0.6 * p["t"])


def draw_section(ax, axis, v, xlim, ylim, flipx=False):
    other = [k for k in range(3) if k != axis]
    for p in parts:
        poly = section(p, axis, v)
        if poly is None or len(poly) < 3:
            continue
        ax.add_patch(Polygon(poly, closed=True, **style(p)))
    ax.set_xlim(*xlim)
    ax.set_ylim(*ylim)
    if flipx:
        ax.invert_xaxis()
    ax.set_aspect("equal")
    ax.grid(True, linewidth=0.2)


def draw_projection(ax, view_axis, band, xlim, ylim, toward_positive=True, axes=None):
    """elevation looking along +view_axis (or -), parts whose extent overlaps band"""
    axes = axes or [k for k in range(3) if k != view_axis]
    sel = []
    for p in parts:
        C = p["corners"]
        lo, hi = C[:, view_axis].min(), C[:, view_axis].max()
        if hi < band[0] or lo > band[1]:
            continue
        depth = lo if toward_positive else -hi
        sel.append((depth, p))
    sel.sort(key=lambda t: -t[0])  # far first
    for _, p in sel:
        poly = hull(p["corners"][:, axes])
        if len(poly) >= 3:
            ax.add_patch(Polygon(poly, closed=True, **style(p)))
    ax.set_xlim(*xlim)
    ax.set_ylim(*ylim)
    ax.set_aspect("equal")
    ax.grid(True, linewidth=0.2)


def save(fig, name):
    path = os.path.join(out, name)
    fig.savefig(path, dpi=130, bbox_inches="tight")
    plt.close(fig)
    print("wrote", path)


Y4 = 16 * 7  # tier 4 roof
# 1. long section through the shaft centre (x=0): YZ
fig, ax = plt.subplots(figsize=(8, 18))
draw_section(ax, 0, 0.0, (40, 84), (-22, Y4 + 15))
ax.set_title("Section x=0 (z right, y up): shaft, cabin @G, landings, head house")
ax.set_xlabel("z"); ax.set_ylabel("y")
save(fig, "sec_x0_full.png")

# zoom around the G stop
fig, ax = plt.subplots(figsize=(12, 9))
draw_section(ax, 0, 0.0, (50, 70), (-2, 14))
ax.set_title("Section x=0 zoom at G: landing leaves, sill, cabin leaves, front wall")
save(fig, "sec_x0_G.png")

# 2. stair sections: flight A (x=-18) and flight B (x=-11)
for x, tag in ((-18.0, "A"), (-11.0, "B")):
    fig, ax = plt.subplots(figsize=(8, 18))
    draw_section(ax, 0, x, (52, 82), (-18, Y4 + 14))
    ax.set_title(f"Section x={x} (flight {tag}) all levels")
    save(fig, f"sec_stair_{tag}_full.png")
    fig, ax = plt.subplots(figsize=(12, 10))
    draw_section(ax, 0, x, (52, 82), (28, 50))
    # walking line overlay for level 2
    if tag == "A":
        ax.plot([60, 75], [32, 40], "b-", linewidth=0.8)
        ax.plot([60, 60], [29, 35], "b:", linewidth=0.5)
    else:
        ax.plot([75, 60], [40, 48], "b-", linewidth=0.8)
    ax.set_title(f"Section x={x} (flight {tag}) level 2 zoom; blue = expected walking line")
    save(fig, f"sec_stair_{tag}_L2.png")

# section across both flights at z=67.5 (x right, y up)
fig, ax = plt.subplots(figsize=(14, 10))
draw_section(ax, 2, 67.5, (-24, 10), (28, 52))
ax.set_title("Section z=67.5 (x right, y up): flight A | divider | flight B | lining | shaft | cabin")
save(fig, "sec_z67_L2.png")

# 3. front elevation of the landing at level 2 looking +Z (x right, y up): parts with z < 54.3
fig, ax = plt.subplots(figsize=(12, 10))
draw_projection(ax, 2, (50, 54.3), (-10, 10), (30, 46), toward_positive=True, axes=[0, 1])
ax.set_title("Lobby elevation of the level-2 portal (looking +Z)")
save(fig, "elev_portal_L2.png")
# same with doors removed to show the opening + parked position
fig, ax = plt.subplots(figsize=(12, 10))
bak = parts[:]
parts[:] = [p for p in parts if not (p["name"] in ("DoorL", "DoorR"))]
draw_projection(ax, 2, (50, 54.3), (-10, 10), (30, 46), toward_positive=True, axes=[0, 1])
parts[:] = bak
ax.set_title("Lobby elevation level 2 without landing leaves (opening visible, cabin behind not drawn)")
save(fig, "elev_portal_L2_open.png")

# 4. plans (horizontal sections, x right, z up)
for y, tag in ((1.0, "G_y1"), (33.0, "L2_y33"), (38.0, "L2_y38"), (44.0, "L2_y44"), (Y4 + 2.0, "R_y2"), (Y4 + 12.5, "R_roofslab"), (-15.0, "B1_y1")):
    fig, ax = plt.subplots(figsize=(12, 10))
    draw_section(ax, 1, y, (-25, 25), (40, 83))
    ax.set_title(f"Plan section y={y} ({tag}); x right, z up")
    ax.set_xlabel("x"); ax.set_ylabel("z")
    save(fig, f"plan_{tag}.png")

# cabin plan zooms
for y in (1.0, 3.2, 10.2):
    fig, ax = plt.subplots(figsize=(10, 10))
    draw_section(ax, 1, y, (-8, 8), (52.5, 69))
    # clear volume
    ax.add_patch(Polygon([(-5.5, 55.41), (5.5, 55.41), (5.5, 66.41), (-5.5, 66.41)], closed=True, facecolor="none", edgecolor="green", linestyle=":"))
    ax.set_title(f"Cabin plan y={y} (green dotted = 11x11 clear area)")
    save(fig, f"cabin_plan_y{y}.png")

# cabin interior elevation looking -Z (towards the doors) from inside: x right? we look along -Z so +X is to the right
fig, ax = plt.subplots(figsize=(10, 9))
bak = parts[:]
parts[:] = [p for p in parts if "LiftCabin" in p["path"]]
draw_projection(ax, 2, (54.8, 56), (-6.5, 6.5), (-0.7, 11.2), toward_positive=False, axes=[0, 1])
parts[:] = bak
ax.set_title("Cabin front wall seen from inside (looking -Z; +x right)")
save(fig, "cabin_front_inside.png")
fig, ax = plt.subplots(figsize=(10, 9))
bak = parts[:]
parts[:] = [p for p in parts if "LiftCabin" in p["path"]]
draw_projection(ax, 2, (65, 67), (-6.5, 6.5), (-0.7, 11.2), toward_positive=True, axes=[0, 1])
parts[:] = bak
ax.set_title("Cabin back wall seen from inside (looking +Z; drawn with +x right)")
save(fig, "cabin_back_inside.png")
