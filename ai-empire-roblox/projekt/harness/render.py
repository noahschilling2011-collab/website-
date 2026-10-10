#!/usr/bin/env python3
"""Honest geometric renders of a dump (no textures, no lighting tricks).

usage: render.py out/dump_tierN.json --prefix out/tierN [--cut-z 0 --cut-z 40] [--levels -24,0,16]
                 [--only plan,elev,iso,section] [--box x0,x1,y0,y1,z0,z1]
Outputs:
  {prefix}_plan_y{Y}.png        horizontal section per level: parts intersecting [Y+0.5, Y+7]
  {prefix}_elev_{front,back,left,right}.png   orthographic elevations (painter's, part depth order)
  {prefix}_iso.png              axonometric from front-left above (az 35, el 30), face painter's
  {prefix}_section_z{Z}.png     front view of everything behind the plane z = Z (cut faces darkened)
View conventions (building-local): front = -Z side.  front elevation: viewer at -Z looking +Z
(so +X is to the LEFT); back: viewer at +Z; left: viewer at -X looking +X; right: viewer at +X.
Plans are true top views: +X right, -Z (front) at the top.
"""
import argparse, math, os, time
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
from matplotlib.patches import Rectangle
from dumplib import Dump, convex_hull_2d

LIGHT = np.array([0.40, 0.85, -0.35])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
AMB, DIF = 0.50, 0.50
SKY = (0.93, 0.95, 0.97)

BOX_FACES = [([4, 6, 7, 5], 0, 1), ([0, 1, 3, 2], 0, -1), ([2, 3, 7, 6], 1, 1), ([0, 4, 5, 1], 1, -1), ([1, 5, 7, 3], 2, 1), ([0, 2, 6, 4], 2, -1)]


def parse():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--cut-z", type=float, action="append", default=None, help="section plane(s); default 0")
    ap.add_argument("--levels", default=None)
    ap.add_argument("--only", default="plan,elev,iso,section")
    ap.add_argument("--box", default="-142,145,-27,200,-221,228")
    ap.add_argument("--px-per-stud", type=float, default=3.0, help="plan scale (3 px/stud = 0.33 stud/px)")
    ap.add_argument("--max-width", type=int, default=1600)
    ap.add_argument("--tile", type=float, default=4.0, help="iso: subdivide faces larger than this (studs)")
    ap.add_argument("--view-box", default=None, help="x0,x1,z0,z1: elevations/iso/sections only show parts whose centre lies inside (close-ups; default: all)")
    return ap.parse_args()


# ------------------------------------------------------------------------------ geometry -> faces
def part_faces(D, sel, R=None, P=None, S=None, cutflag=None):
    """Return list of (verts (k,3), normal (3,), part j, is_cut) for the selected parts."""
    P = D.P if P is None else P
    R = D.R if R is None else R
    S = D.S if S is None else S
    out = []
    signs = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], dtype=float)
    for j in sel:
        Rj, Pj, Sj = R[j], P[j], S[j]
        h = Sj / 2
        kind = D.shape[j]
        if kind == "Wedge":
            loc = {
                "bot": [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)],
                "back": [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)],
                "slope": [(-1, -1, -1), (-1, 1, 1), (1, 1, 1), (1, -1, -1)],
                "l": [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1)],
                "r": [(1, -1, -1), (1, 1, 1), (1, -1, 1)],
            }
            nrm = {"bot": np.array([0, -1, 0.0]), "back": np.array([0, 0, 1.0]), "slope": np.array([0, h[2], -h[1]]) / max(np.hypot(h[2], h[1]), 1e-9),
                   "l": np.array([-1.0, 0, 0]), "r": np.array([1.0, 0, 0])}
            for k, vs in loc.items():
                v = Pj + (np.array(vs, dtype=float) * h) @ Rj.T
                out.append((v, Rj @ nrm[k], j, False))
        elif kind == "Ball":
            r = Sj.min() / 2
            out.append(("ball", np.array([Pj[0], Pj[1], Pj[2], r]), j, False))
        elif kind == "Cylinder":
            r = min(Sj[1], Sj[2]) / 2
            n = 12
            ang = np.arange(n) * 2 * np.pi / n
            ring = np.stack([np.cos(ang) * r, np.sin(ang) * r], axis=1)
            for sx in (-1, 1):
                v = np.stack([np.full(n, sx * h[0]), ring[:, 0], ring[:, 1]], axis=1)
                out.append((Pj + v @ Rj.T, Rj @ np.array([sx, 0, 0.0]), j, False))
            for i in range(n):
                a, b = ring[i], ring[(i + 1) % n]
                v = np.array([[-h[0], a[0], a[1]], [h[0], a[0], a[1]], [h[0], b[0], b[1]], [-h[0], b[0], b[1]]])
                mid = (a + b) / 2
                nn = np.array([0, mid[0], mid[1]]) / max(np.hypot(mid[0], mid[1]), 1e-9)
                out.append((Pj + v @ Rj.T, Rj @ nn, j, False))
        else:
            c = Pj + (signs * h) @ Rj.T
            for idx, ax, sg in BOX_FACES:
                is_cut = bool(cutflag is not None and cutflag[j] and ax == 2 and sg < 0)
                out.append((c[idx], Rj[:, ax] * sg, j, is_cut))
    return out


def subdivide_quad(v, T):
    """Split a planar quad (4,3) into tiles with edges <= T."""
    a, b, c, d = v
    lu = max(np.linalg.norm(b - a), np.linalg.norm(c - d))
    lv = max(np.linalg.norm(d - a), np.linalg.norm(c - b))
    nu, nv = max(1, int(math.ceil(lu / T))), max(1, int(math.ceil(lv / T)))
    if nu == 1 and nv == 1:
        return [v]
    tiles = []
    us = np.linspace(0, 1, nu + 1)
    vs = np.linspace(0, 1, nv + 1)
    def at(u, w):
        return (1 - u) * (1 - w) * a + u * (1 - w) * b + u * w * c + (1 - u) * w * d
    for i in range(nu):
        for k in range(nv):
            tiles.append(np.array([at(us[i], vs[k]), at(us[i + 1], vs[k]), at(us[i + 1], vs[k + 1]), at(us[i], vs[k + 1])]))
    return tiles


def view_basis(name, az=35.0, el=30.0):
    """right, up, forward (into the scene)."""
    if name == "front":
        f = np.array([0, 0, 1.0])
    elif name == "back":
        f = np.array([0, 0, -1.0])
    elif name == "left":
        f = np.array([1.0, 0, 0])
    elif name == "right":
        f = np.array([-1.0, 0, 0])
    else:  # iso: camera at front-left above -> looks toward +Z, -X, down
        a, e = math.radians(az), math.radians(el)
        cam = np.array([math.sin(a) * math.cos(e), math.sin(e), -math.cos(a) * math.cos(e)])
        f = -cam
    up0 = np.array([0, 1.0, 0])
    r = np.cross(f, up0)
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return r, u, f


def render_view(D, name, out, sel, title, P=None, R=None, S=None, cutflag=None, tile=None, max_width=1600, part_order=True):
    t0 = time.time()
    r, u, f = view_basis(name)
    faces = part_faces(D, sel, R=R, P=P, S=S, cutflag=cutflag)
    Pv = D.P if P is None else P
    polys, cols, keys, tiled = [], [], [], []
    for v, n, j, is_cut in faces:
        tr = D.transp[j]
        alpha = 1.0 - tr
        if alpha <= 0.02:
            continue
        alpha = max(alpha, 0.18)
        base = D.color[j] / 255.0
        if isinstance(v, str):     # ball: camera-facing disc
            cx, cy, cz, rad = n
            ang = np.linspace(0, 2 * np.pi, 17)[:-1]
            ctr = np.array([cx, cy, cz])
            sx, sy = ctr @ r, ctr @ u
            poly = np.stack([sx + rad * np.cos(ang), sy + rad * np.sin(ang)], axis=1)
            shade = AMB + DIF * max(0.0, float(-f @ LIGHT))
            polys.append(poly); cols.append((*np.clip(base * shade, 0, 1), alpha))
            keys.append((float(ctr @ f), float(ctr @ f)))
            tiled.append(False)
            continue
        nf = float(n @ f)
        if nf >= -1e-6:
            continue
        shade = AMB + DIF * max(0.0, float(n @ LIGHT))
        col = base * shade
        if is_cut:
            col = col * 0.45 + np.array([0.35, 0.05, 0.05]) * 0.55
        pdepth = float(Pv[j] @ f)
        vlist = subdivide_quad(v, tile) if (tile and len(v) == 4) else [v]
        for vv in vlist:
            polys.append(np.stack([vv @ r, vv @ u], axis=1))
            cols.append((*np.clip(col, 0, 1), alpha))
            keys.append((pdepth, float(vv.mean(0) @ f)))
            tiled.append(len(vlist) > 1)
    if not polys:
        print(f"   {out}: nothing to draw")
        return
    keys = np.array(keys)
    if part_order:
        order = np.lexsort((-keys[:, 1], -keys[:, 0]))   # far parts first, then far faces
    else:
        order = np.argsort(-keys[:, 1], kind="stable")     # face-level painter's
    polys = [polys[i] for i in order]
    cols = np.array(cols)[order]
    allp = np.concatenate(polys)
    xmin, ymin = allp.min(0)
    xmax, ymax = allp.max(0)
    pad = 0.03 * max(xmax - xmin, ymax - ymin)
    xmin -= pad; xmax += pad; ymin -= pad; ymax += pad
    wspan, hspan = xmax - xmin, ymax - ymin
    W = min(max_width, max(800, int(wspan * 4)))
    H = int(W * hspan / wspan)
    H = min(max(H, 300), 2400)
    dpi = 100
    fig = plt.figure(figsize=(W / dpi, (H + 60) / dpi), dpi=dpi)
    ax = fig.add_axes([0, 0, 1, H / (H + 60)])
    ax.set_facecolor(SKY)
    tiled = np.array(tiled)[order]
    edge = np.clip(cols[:, :3] * np.where(tiled, 0.96, 0.8)[:, None], 0, 1)
    pc = PolyCollection(polys, facecolors=cols, edgecolors=np.concatenate([edge, cols[:, 3:]], axis=1), linewidths=0.25)
    ax.add_collection(pc)
    ax.set_xlim(xmin, xmax); ax.set_ylim(ymin, ymax)
    ax.set_aspect("equal")
    ax.set_xticks([]); ax.set_yticks([])
    if name != "iso":
        # stud grid every 16 vertically (floor heights) on the margin
        for yv in range(int(math.floor(ymin / 16)) * 16, int(ymax) + 1, 16):
            ax.axhline(yv, color=(0.5, 0.5, 0.55), lw=0.3, ls=":", zorder=0)
            ax.text(xmin + pad * 0.1, yv + 0.3, f"y={yv}", fontsize=6, color=(0.3, 0.3, 0.35), zorder=5)
    fig.text(0.01, 1 - 30 / (H + 60), title + f"   [{len(polys)} polygons]", fontsize=9, va="center")
    fig.savefig(out, facecolor="white")
    plt.close(fig)
    print(f"   wrote {out} ({W}x{H + 60}, {time.time() - t0:.1f}s)")


# ------------------------------------------------------------------------------ plans
def render_plan(D, Y, out, box, pxs, labels, max_width):
    t0 = time.time()
    x0, x1, _, _, z0, z1 = box
    cor = D.corners()
    ylo, yhi = cor[:, :, 1].min(1), cor[:, :, 1].max(1)
    build = ~D.character
    band = (yhi > Y + 0.5) & (ylo < Y + 7)
    vis = D.transp < 0.99
    under = build & vis & (yhi >= Y - 1.2) & (yhi <= Y + 0.5) & ~band
    W = min(max_width, int((x1 - x0) * pxs))
    scale = W / (x1 - x0)
    H = int((z1 - z0) * scale)
    dpi = 100
    fig = plt.figure(figsize=(W / dpi, (H + 70) / dpi), dpi=dpi)
    ax = fig.add_axes([0, 0, 1, H / (H + 70)])
    ax.set_facecolor((0.97, 0.97, 0.96))
    def hull_of(j):
        return np.array(convex_hull_2d(cor[j][:, [0, 2]]))
    # underlay floors
    polys, cols = [], []
    for j in np.nonzero(under)[0]:
        if D.S[j][0] * D.S[j][2] < 4 and D.S[j][0] * D.S[j][1] < 4:
            continue
        hpoly = hull_of(j)
        if len(hpoly) < 3:
            continue
        polys.append(hpoly); c = D.color[j] / 255
        cols.append((*(c * 0.35 + 0.65), 1.0))
    if polys:
        ax.add_collection(PolyCollection(polys, facecolors=cols, edgecolors=(0.75, 0.75, 0.75, 1), linewidths=0.2))
    # parts in the band: low tops first
    selj = np.nonzero(band & build)[0]
    selj = selj[np.argsort(yhi[selj])]
    polys, fcols, ecols, lws, styles = [], [], [], [], []
    inv_polys = []
    for j in selj:
        hpoly = hull_of(j)
        if len(hpoly) < 3:
            continue
        c = D.color[j] / 255
        if D.transp[j] >= 0.99:
            if D.collide[j]:
                inv_polys.append(hpoly)
            continue
        alpha = max(0.15, 1 - D.transp[j])
        if D.collide[j]:
            polys.append(hpoly); fcols.append((*c, alpha)); ecols.append((*(c * 0.5), min(1, alpha + 0.3))); lws.append(0.4)
        else:
            polys.append(hpoly); fcols.append((*c, alpha * 0.45)); ecols.append((0.4, 0.4, 0.4, 0.35)); lws.append(0.2)
    if polys:
        ax.add_collection(PolyCollection(polys, facecolors=fcols, edgecolors=ecols, linewidths=lws))
    if inv_polys:
        ax.add_collection(PolyCollection(inv_polys, facecolors="none", edgecolors=(0.85, 0.1, 0.75, 0.9), linewidths=0.6, linestyles="--"))
    for txt, x, z in labels:
        ax.text(x, z, txt, fontsize=6.5, ha="center", va="center", color=(0.1, 0.1, 0.35),
                bbox=dict(boxstyle="round,pad=0.15", fc=(1, 1, 1, 0.75), ec="none"))
    ax.set_xlim(x0, x1); ax.set_ylim(z1, z0)     # -Z (front) at the top
    ax.set_aspect("equal")
    ax.set_xticks(range(int(math.ceil(x0 / 20)) * 20, int(x1) + 1, 20)); ax.set_yticks(range(int(math.ceil(z0 / 20)) * 20, int(z1) + 1, 20))
    ax.tick_params(labelsize=6, direction="in", pad=-12)
    for lab in ax.get_xticklabels() + ax.get_yticklabels():
        lab.set_color((0.45, 0.45, 0.5))
    ax.grid(color=(0.85, 0.85, 0.88), lw=0.3)
    ax.set_axisbelow(True)
    # scale bar 20 studs
    sb_x, sb_z = x0 + 6, z1 - 8
    ax.add_patch(Rectangle((sb_x, sb_z), 20, 1.2, color="black"))
    ax.add_patch(Rectangle((sb_x + 10, sb_z), 10, 1.2, color="white", ec="black", lw=0.5))
    ax.text(sb_x + 10, sb_z - 1.5, "20 studs", fontsize=7, ha="center")
    ax.text((x0 + x1) / 2, z0 + 3, "FRONT (-Z)", fontsize=8, ha="center", va="top", color=(0.3, 0.3, 0.3))
    fig.text(0.01, 1 - 22 / (H + 70), f"{os.path.basename(D.path)} tier {D.meta.get('tier')}: plan section y={Y:g}, parts intersecting [{Y + 0.5:g}, {Y + 7:g}]  ({1/scale:.2f} stud/px)", fontsize=8, va="center")
    fig.text(0.01, 1 - 48 / (H + 70), "solid = collidable, faint = non-collidable decor, dashed magenta = invisible collidable, light = floor underlay", fontsize=7, va="center", color=(0.3, 0.3, 0.3))
    fig.savefig(out, facecolor="white")
    plt.close(fig)
    print(f"   wrote {out} ({W}x{H + 70}, {time.time() - t0:.1f}s)")


def room_labels(D):
    """(text, x, z, y) for Models/Parts with RoomId/RoomName."""
    labs = []
    for k, x in enumerate(D.inst):
        at = x.get("attrs") or {}
        rid = at.get("RoomName") or at.get("RoomId")
        if not isinstance(rid, str):
            continue
        if x["class"] == "Model" or x["class"] == "Folder":
            mn, mx = at.get("RoomMin"), at.get("RoomMax")
            if isinstance(mn, dict) and isinstance(mx, dict):
                a, b = np.array(mn["Vector3"]), np.array(mx["Vector3"])
                labs.append((rid + (f"\n{at['Department']}" if isinstance(at.get("Department"), str) else ""), (a[0] + b[0]) / 2, (a[2] + b[2]) / 2, min(a[1], b[1])))
                continue
            # centre of descendant parts
            desc = [j for j in range(D.n) if k in D.ancestors(int(D.pidx[j]))] if D.n < 30000 else []
            if desc:
                c = D.P[desc]
                labs.append((rid, c[:, 0].mean(), c[:, 2].mean(), float(np.median(c[:, 1]))))
        elif "size" in x:
            s = x["size"]
            if s[0] * s[2] >= 100:      # only large parts (rooms/floors), not doors
                c = x["cframe"]
                labs.append((rid, c[0], c[2], c[1]))
    return labs


def main():
    a = parse()
    t0 = time.time()
    D = Dump(a.dump)
    box = [float(v) for v in a.box.split(",")]
    only = set(a.only.split(","))
    floors = D.floors()
    levels = [float(v) for v in a.levels.split(",")] if a.levels else [-24.0] + [16.0 * f for f in range(floors + 1)]
    tier = D.meta.get("tier")
    print(f"render {a.dump}: {D.n} parts, levels {levels}")
    os.makedirs(os.path.dirname(os.path.abspath(a.prefix)), exist_ok=True)
    if "plan" in only:
        labs = room_labels(D)
        for Y in levels:
            ls = [(t, x, z) for (t, x, z, y) in labs if Y - 2 <= y < Y + 14]
            render_plan(D, Y, f"{a.prefix}_plan_y{int(Y)}.png", box, a.px_per_stud, ls, a.max_width)
    vis = (D.transp < 0.98)
    far = vis & (D.S.max(1) >= 0.3)
    if a.view_box:
        vx0, vx1, vz0, vz1 = [float(v) for v in a.view_box.split(",")]
        far = far & (D.P[:, 0] >= vx0) & (D.P[:, 0] <= vx1) & (D.P[:, 2] >= vz0) & (D.P[:, 2] <= vz1)
    allsel = np.nonzero(far)[0]
    if "elev" in only:
        names = {"front": "front elevation (viewer at -Z looking +Z; +X is LEFT)", "back": "back elevation (viewer at +Z looking -Z; +X is right)",
                 "left": "left elevation (viewer at -X looking +X; +Z is right)", "right": "right elevation (viewer at +X looking -X; +Z is left)"}
        for nm, desc in names.items():
            render_view(D, nm, f"{a.prefix}_elev_{nm}.png", allsel, f"tier {tier}: {desc}", max_width=a.max_width)
    if "iso" in only:
        render_view(D, "iso", f"{a.prefix}_iso.png", allsel, f"tier {tier}: axonometric from front-left above (az 35, el 30), face-level painter's",
                    tile=a.tile, max_width=a.max_width, part_order=False)
    if "section" in only:
        for zc in (a.cut_z if a.cut_z is not None else [0.0]):
            P2, R2, S2 = D.P.copy(), D.R.copy(), D.S.copy()
            cut = np.zeros(D.n, dtype=bool)
            keep = np.zeros(D.n, dtype=bool)
            for j in allsel:
                Rj = D.R[j]
                axis_aligned = np.all((np.abs(Rj) < 1e-6) | (np.abs(np.abs(Rj) - 1) < 1e-6))
                if axis_aligned and D.shape[j] == "Block":
                    ext = np.abs(Rj) @ D.S[j]
                    lo, hi = D.P[j] - ext / 2, D.P[j] + ext / 2
                    if hi[2] <= zc:
                        continue
                    if lo[2] < zc:
                        lo[2] = zc
                        cut[j] = True
                    P2[j] = (lo + hi) / 2; S2[j] = hi - lo; R2[j] = np.eye(3)
                    keep[j] = True
                elif D.P[j][2] > zc:
                    keep[j] = True
            render_view(D, "front", f"{a.prefix}_section_z{int(zc)}.png", np.nonzero(keep)[0],
                        f"tier {tier}: section at z={zc:g}, looking +Z (everything behind the cut; cut faces dark red; +X is LEFT)",
                        P=P2, R=R2, S=S2, cutflag=cut, max_width=a.max_width)
    print(f"render done in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
