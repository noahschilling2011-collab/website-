#!/usr/bin/env python3
"""Geometry + walkability report for a dump (building-local coordinates).

usage: check_geometry.py out/dump_tierN.json [--res 1.0] [--start x,y,z] [--box x0,x1,y0,y1,z0,z1]
                         [--lift auto|stops|doors|volume|none] [--no-images] [--verbose]
                         [--door-regex REGEX] [--include-characters] [--agent-group Default]
Images: out/walk_tierN_levelY.png (prefix configurable with --img-prefix).
See harness/README.md for the exact rules (step 1.6, clearance 0.3..5.0, radius ~1 cell).
"""
import argparse, os, re, sys, time
from collections import Counter, defaultdict
import numpy as np
from dumplib import Dump, vertical_line_hits, convex_hull_2d, name_prefix

STEP = 1.6       # max height change between neighbouring cells (and steppable obstacle height)
CLEAR_LO = 0.3   # body box starts this far above the surface ...
CLEAR_HI = 5.0   # ... and ends here (agent height 5.6 minus a little tolerance)
MERGE = 0.35     # surfaces closer than this in one column are one surface
BIG = 4096.0     # key spacing per cell (heights are offset by +OFF and stay < BIG)
OFF = 1000.0


def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("--res", type=float, default=1.0)
    ap.add_argument("--start", default="0,0,-60")
    ap.add_argument("--box", default="-142,145,-27,200,-221,228", help="x0,x1,y0,y1,z0,z1 allowed bounds")
    ap.add_argument("--lift", default="auto")
    ap.add_argument("--door-regex", default=r"Door(?!Frame|Transom)|Gate")
    ap.add_argument("--include-characters", action="store_true")
    ap.add_argument("--agent-group", default="Default")
    ap.add_argument("--radius", type=float, default=1.3, help="agent radius (studs) -> obstacle dilation")
    ap.add_argument("--htol", type=float, default=2.5)
    ap.add_argument("--vtol", type=float, default=3.0)
    ap.add_argument("--no-images", action="store_true")
    ap.add_argument("--img-prefix", default=None)
    ap.add_argument("--levels", default=None, help="comma list of floor heights for heatmaps")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--probe", action="append", default=[], help="x,y,z: print nodes/obstacles around a point (debug)")
    return ap.parse_args()


def fmtv(v):
    return "(" + ", ".join(f"{a:.1f}" for a in v) + ")"


class Report:
    def __init__(self):
        self.lines = []
        self.summary = []

    def p(self, *a):
        s = " ".join(str(x) for x in a)
        self.lines.append(s)
        print(s)

    def sum(self, s):
        self.summary.append(s)


def main():
    a = parse_args()
    t0 = time.time()
    D = Dump(a.dump)
    rep = Report()
    m = D.meta
    tier = m.get("tier")
    rep.p(f"== GEOMETRY REPORT  {a.dump}  tier {tier}  mode {m.get('mode')}  (converted to local: {D.transformed})")
    rep.p(f"instances {len(D.inst)}  parts {D.n}  mock thread errors {m.get('mock', {}).get('threadErrors')}  stubs {m.get('mock', {}).get('stubs')}")

    # ---------------------------------------------------------------- counts
    build = ~D.character
    coll = D.collide & build
    rep.p("\n== PART COUNTS")
    rep.p(f"total parts {D.n}  (character/NPC rig parts {int(D.character.sum())}, building parts {int(build.sum())})")
    rep.p(f"collidable building parts {int(coll.sum())}   non-collidable detail parts {int((~D.collide & build).sum())}")
    rep.p(f"invisible collidable parts (Transparency>=0.99) {int((coll & (D.transp >= 0.99)).sum())}   glass-like (0<T<0.99) {int((build & (D.transp > 0) & (D.transp < 0.99)).sum())}")
    cnt = Counter(name_prefix(n) for n, b in zip(D.name, build) if b)
    ccnt = Counter(name_prefix(n) for n, b in zip(D.name, coll) if b)
    rep.p("by name prefix (building parts; count / collidable):")
    items = cnt.most_common() if a.verbose else cnt.most_common(45)
    for k, v in items:
        rep.p(f"   {k:<28} {v:>6} / {ccnt.get(k, 0)}")
    if not a.verbose and len(cnt) > 45:
        rep.p(f"   ... {len(cnt) - 45} more prefixes (use --verbose)")

    # ---------------------------------------------------------------- bounds
    x0, x1, y0, y1, z0, z1 = [float(v) for v in a.box.split(",")]
    lo, hi = D.aabb()
    rep.p("\n== BOUNDS (building-local, from oriented boxes)")
    if D.n:
        rep.p(f"all parts: x [{lo[:,0].min():.1f}, {hi[:,0].max():.1f}]  y [{lo[:,1].min():.1f}, {hi[:,1].max():.1f}]  z [{lo[:,2].min():.1f}, {hi[:,2].max():.1f}]")
        b2 = build
        rep.p(f"building : x [{lo[b2,0].min():.1f}, {hi[b2,0].max():.1f}]  y [{lo[b2,1].min():.1f}, {hi[b2,1].max():.1f}]  z [{lo[b2,2].min():.1f}, {hi[b2,2].max():.1f}]")
    out = (lo[:, 0] < x0 - 1e-6) | (hi[:, 0] > x1 + 1e-6) | (lo[:, 1] < y0 - 1e-6) | (hi[:, 1] > y1 + 1e-6) | (lo[:, 2] < z0 - 1e-6) | (hi[:, 2] > z1 + 1e-6)
    rep.p(f"allowed box x[{x0},{x1}] y[{y0},{y1}] z[{z0},{z1}]: {int(out.sum())} part(s) outside")
    for j in np.nonzero(out)[0][: (10**9 if a.verbose else 30)]:
        rep.p(f"   OUTSIDE {D.inst[D.pidx[j]]['path']}  aabb {fmtv(lo[j])}..{fmtv(hi[j])}")
    rep.sum(f"parts outside allowed box: {int(out.sum())}")

    # ---------------------------------------------------------------- degenerate
    rep.p("\n== DEGENERATE / INVALID")
    nan = ~np.isfinite(D.P).all(1) | ~np.isfinite(D.S).all(1) | ~np.isfinite(D.R.reshape(D.n, 9)).all(1)
    small = (D.S < 0.05).any(1) & ~nan
    large = (D.S >= 2048).any(1) & ~nan
    req = np.array(["requestedSize" in D.inst[k] for k in D.pidx], dtype=bool)
    RtR = np.einsum("nji,njk->nik", D.R, D.R)
    nonortho = (np.abs(RtR - np.eye(3)[None]).reshape(D.n, 9).max(1) > 1e-3) & ~nan
    rep.p(f"NaN/inf values: {int(nan.sum())}   size<0.05: {int(small.sum())}   size>=2048: {int(large.sum())}   clamped by Roblox (requested size out of range): {int(req.sum())}   non-orthonormal rotation: {int(nonortho.sum())}")
    for label, mask in (("NAN", nan), ("SMALL", small), ("LARGE", large), ("CLAMPED", req), ("NONORTHO", nonortho)):
        for j in np.nonzero(mask)[0][: (10**9 if a.verbose else 15)]:
            k = D.pidx[j]
            rep.p(f"   {label} {D.inst[k]['path']} size {D.inst[k]['size']}" + (f" requested {D.inst[k].get('requestedSize')}" if label == "CLAMPED" else ""))
    rep.sum(f"degenerate: NaN {int(nan.sum())}, tiny(<0.05) {int(small.sum())}, huge {int(large.sum())}, non-orthonormal {int(nonortho.sum())}")

    # ---------------------------------------------------------------- duplicates
    rep.p("\n== DUPLICATE COLLIDABLE PARTS (identical CFrame and size)")
    keys = defaultdict(list)
    for j in np.nonzero(coll)[0]:
        key = tuple(np.round(np.concatenate([D.P[j], D.R[j].reshape(-1), D.S[j]]), 3))
        keys[key].append(j)
    dups = [v for v in keys.values() if len(v) > 1]
    rep.p(f"{len(dups)} group(s) of exact duplicates ({sum(len(v) - 1 for v in dups)} redundant parts)")
    for v in dups[: (10**9 if a.verbose else 20)]:
        rep.p("   DUP " + " | ".join(D.inst[D.pidx[j]]["path"] for j in v[:4]) + f"  at {fmtv(D.P[v[0]])} size {fmtv(D.S[v[0]])}")
    rep.sum(f"exact duplicate collidable groups: {len(dups)}")

    # ---------------------------------------------------------------- walkability
    walk(D, a, rep, (x0, x1, y0, y1, z0, z1))
    rep.p(f"\n(checked in {time.time() - t0:.1f}s)")
    print("\n== SUMMARY")
    for s in rep.summary:
        print("  " + s)


# ======================================================================================
def door_like(D, j, rx):
    at = D.part_attrs(j)
    if at.get("DoorLeaf") is True or "DoorOpenCFrame" in at or "ClosedCFrame" in at:
        return True
    # ArchKit door models: every part under Office/Doors/Door_*/Leaf1|Leaf2 moves when the door opens
    path = D.inst[int(D.pidx[j])].get("path", "")
    if "/Doors/Door_" in path and ("/Leaf1/" in path or "/Leaf2/" in path):
        return True
    return rx.search(D.name[j]) is not None


def walk(D, a, rep, box):
    x0, x1, y0, y1, z0, z1 = box
    res = a.res
    rx = re.compile(a.door_regex)
    rep.p(f"\n== WALKABILITY  grid {res} stud, step {STEP}, clearance [{CLEAR_LO}, {CLEAR_HI}], radius {a.radius}")
    # which groups collide with the agent group
    cg = D.meta.get("collisionGroups") or {}
    pairs = cg.get("pairs") or {}
    def collides(g):
        k = "|".join(sorted([g, a.agent_group]))
        return pairs.get(k, True) is not False
    door = np.array([door_like(D, j, rx) for j in range(D.n)], dtype=bool)
    grp_ok = np.array([collides(g) for g in D.group], dtype=bool)
    solid = D.collide & grp_ok & (a.include_characters | ~D.character)
    solid_nodoor = solid & ~door
    rep.p(f"solid parts {int(solid.sum())} (doors/gates treated as open: {int((solid & door).sum())}; characters {'included' if a.include_characters else 'ignored'}; non-colliding groups: {int((D.collide & ~grp_ok).sum())})")

    nx = int(np.ceil((x1 - x0) / res))
    nz = int(np.ceil((z1 - z0) / res))
    ncell = nx * nz
    gx = x0 + (np.arange(nx) + 0.5) * res
    gz = z0 + (np.arange(nz) + 0.5) * res
    corners = D.corners()
    upright = np.zeros(D.n, dtype=bool)
    for j in range(D.n):
        upright[j] = (np.abs(D.R[j][1, :]) > 1 - 1e-9).any() and D.shape[j] in ("Block", "Cylinder", "Ball")

    surf_cell, surf_h, surf_part = [], [], []
    F_cell, F_lo, F_hi = [], [], []      # forbidden standing-height intervals per cell
    O_cell, O_lo, O_hi = [], [], []      # physical obstacle spans (for images / probes)
    R_ag = a.radius
    ring_off = np.array([[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]], dtype=float) * (R_ag * 0.7)
    n_ob = 0
    for j in np.nonzero(solid_nodoor)[0]:
        c = corners[j]
        cx0, cx1 = c[:, 0].min(), c[:, 0].max()
        cz0, cz1 = c[:, 2].min(), c[:, 2].max()
        cy0, cy1 = c[:, 1].min(), c[:, 1].max()
        i0 = max(int(np.floor((cx0 - R_ag - x0) / res)), 0)
        i1 = min(int(np.floor((cx1 + R_ag - x0) / res)), nx - 1)
        k0 = max(int(np.floor((cz0 - R_ag - z0) / res)), 0)
        k1 = min(int(np.floor((cz1 + R_ag - z0) / res)), nz - 1)
        if i1 < i0 or k1 < k0:
            continue
        II, KK = np.meshgrid(np.arange(i0, i1 + 1), np.arange(k0, k1 + 1), indexing="ij")
        II = II.ravel(); KK = KK.ravel()
        cxs = gx[II]; czs = gz[KK]
        cell = KK * nx + II
        # (1) exact vertical extent along each cell's centre line -> walkable surface + centre obstacle
        hit, tmin, tmax = vertical_line_hits(D.P[j], D.R[j], D.S[j], D.shape[j], cxs, czs)
        if hit.any():
            surf_cell.append(cell[hit]); surf_h.append(tmax[hit]); surf_part.append(np.full(int(hit.sum()), j))
            # body box [h+CLEAR_LO, h+CLEAR_HI] must not intersect the solid under the centre
            F_cell.append(cell[hit]); F_lo.append(tmin[hit] - CLEAR_HI); F_hi.append(tmax[hit] - CLEAR_LO)
            O_cell.append(cell[hit]); O_lo.append(tmin[hit]); O_hi.append(tmax[hit])
        # (2) radius ring: exact 2D distance from the cell centre to the footprint polygon
        hull = np.array(convex_hull_2d(c[:, [0, 2]]))
        pts = np.stack([cxs, czs], axis=1)
        if len(hull) >= 3:
            A = hull; B = np.roll(hull, -1, axis=0)
            E = B - A
            L2 = np.maximum((E ** 2).sum(1), 1e-12)
            t = np.clip(((pts[:, None, :] - A[None]) * E[None]).sum(2) / L2[None], 0, 1)
            Q = A[None] + t[..., None] * E[None]                         # nearest points per edge
            dist_e = np.linalg.norm(pts[:, None, :] - Q, axis=2)
            ei = dist_e.argmin(1)
            dist = dist_e[np.arange(len(pts)), ei]
            nearest = Q[np.arange(len(pts)), ei]
            cross = E[None, :, 0] * (pts[:, None, 1] - A[None, :, 1]) - E[None, :, 1] * (pts[:, None, 0] - A[None, :, 0])
            inside = (cross >= -1e-9).all(1) | (cross <= 1e-9).all(1)
            dist[inside] = 0
            nearest[inside] = pts[inside]
        else:
            # degenerate (zero-area) footprint: distance to its AABB
            dxv = np.maximum(np.maximum(cx0 - cxs, cxs - cx1), 0); dzv = np.maximum(np.maximum(cz0 - czs, czs - cz1), 0)
            dist = np.hypot(dxv, dzv)
            nearest = np.stack([np.clip(cxs, cx0, cx1), np.clip(czs, cz0, cz1)], axis=1)
            inside = dist == 0
        ring = (dist < R_ag) & ~hit
        if not ring.any():
            continue
        n_ob += int(ring.sum())
        if upright[j]:
            ylo = np.full(int(ring.sum()), cy0); yhi = np.full(int(ring.sum()), cy1)
        else:
            # vertical range of a tilted part near this body position: sample the footprint around the
            # nearest point (pulled slightly into the polygon); fall back to the full extent
            cen = hull.mean(0) if len(hull) else np.array([(cx0 + cx1) / 2, (cz0 + cz1) / 2])
            base = nearest[ring]
            samp = base[:, None, :] + ring_off[None, :, :]
            samp = samp + (cen - samp) * 1e-4
            h2, a2, b2 = vertical_line_hits(D.P[j], D.R[j], D.S[j], D.shape[j], samp[..., 0].ravel(), samp[..., 1].ravel())
            h2 = h2.reshape(-1, len(ring_off))
            a2 = np.where(h2, a2.reshape(h2.shape), np.inf); b2 = np.where(h2, b2.reshape(h2.shape), -np.inf)
            ylo = a2.min(1); yhi = b2.max(1)
            none = ~h2.any(1)
            ylo[none] = cy0; yhi[none] = cy1
        F_cell.append(cell[ring]); F_lo.append(ylo - CLEAR_HI); F_hi.append(yhi - STEP)
        near_cell = dist[ring] <= res * 0.5
        O_cell.append(cell[ring][near_cell]); O_lo.append(ylo[near_cell]); O_hi.append(yhi[near_cell])
    S_cell = np.concatenate(surf_cell) if surf_cell else np.zeros(0, int)
    S_h = np.concatenate(surf_h) if surf_h else np.zeros(0)
    S_p = np.concatenate(surf_part) if surf_part else np.zeros(0, int)
    F_cell = np.concatenate(F_cell) if F_cell else np.zeros(0, int)
    F_lo = np.concatenate(F_lo) if F_lo else np.zeros(0)
    F_hi = np.concatenate(F_hi) if F_hi else np.zeros(0)
    O_cell = np.concatenate(O_cell) if O_cell else np.zeros(0, int)
    O_lo = np.concatenate(O_lo) if O_lo else np.zeros(0)
    O_hi = np.concatenate(O_hi) if O_hi else np.zeros(0)

    # merge surfaces per column (keep highest of a cluster)
    order = np.lexsort((S_h, S_cell))
    S_cell, S_h, S_p = S_cell[order], S_h[order], S_p[order]
    if len(S_h):
        nxt_same = np.zeros(len(S_h), dtype=bool)
        nxt_same[:-1] = (S_cell[1:] == S_cell[:-1]) & (S_h[1:] - S_h[:-1] <= MERGE)
        keep = ~nxt_same
        S_cell, S_h, S_p = S_cell[keep], S_h[keep], S_p[keep]

    # union of forbidden intervals per cell, then test every surface
    keyl = F_cell * BIG + (F_lo + OFF)
    keyh = F_cell * BIG + (F_hi + OFF)
    o = np.argsort(keyl, kind="stable")
    keyl, keyh = keyl[o], keyh[o]
    if len(keyl):
        runmax = np.maximum.accumulate(keyh)
        newgrp = np.ones(len(keyl), dtype=bool)
        newgrp[1:] = keyl[1:] > runmax[:-1]
        starts = np.nonzero(newgrp)[0]
        M_lo = keyl[starts]
        M_hi = np.maximum.reduceat(keyh, starts)
    else:
        M_lo = M_hi = np.zeros(0)
    skey = S_cell * BIG + (S_h + OFF)
    pos = np.searchsorted(M_lo, skey, side="right") - 1
    blocked = np.zeros(len(skey), dtype=bool)
    v = pos >= 0
    blocked[v] = skey[v] < M_hi[pos[v]]
    valid = ~blocked
    N_cell, N_h, N_p = S_cell[valid], S_h[valid], S_p[valid]
    N = len(N_cell)
    nkey = N_cell * BIG + (N_h + OFF)       # sorted (cells ascending, h ascending)
    rep.p(f"grid {nx}x{nz} cells, surfaces {len(S_h)}, standable nodes {N}, clearance constraints {len(F_cell)}")

    # ---------------------------------------------------------------- edges
    U, V = [], []
    ni = N_cell % nx; nk = N_cell // nx
    def neighbours(dx, dz, collect=True):
        ii = ni + dx; kk = nk + dz
        inb = (ii >= 0) & (ii < nx) & (kk >= 0) & (kk < nz)
        c2 = kk * nx + ii
        lo_k = c2 * BIG + (N_h - STEP + OFF)
        hi_k = c2 * BIG + (N_h + STEP + OFF)
        l = np.searchsorted(nkey, lo_k, side="left")
        h = np.searchsorted(nkey, hi_k, side="right")
        cntn = np.where(inb, h - l, 0)
        return l, cntn
    has = {}
    for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        l, cntn = neighbours(*d)
        has[d] = cntn > 0
        for t in range(int(cntn.max()) if len(cntn) else 0):
            mm = cntn > t
            U.append(np.nonzero(mm)[0]); V.append(l[mm] + t)
    for d in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        l, cntn = neighbours(*d)
        allow = has[(d[0], 0)] & has[(0, d[1])]
        cntn = np.where(allow, cntn, 0)
        for t in range(int(cntn.max()) if len(cntn) else 0):
            mm = cntn > t
            U.append(np.nonzero(mm)[0]); V.append(l[mm] + t)

    # ---------------------------------------------------------------- helpers to find nodes near a point
    def nodes_near(p, htol=a.htol, vtol=a.vtol, href=None):
        """indices of standable nodes within htol horizontally and |h - href| <= vtol."""
        href = p[1] if href is None else href
        rr = int(np.ceil(htol / res))
        ci = int(np.floor((p[0] - x0) / res)); ck = int(np.floor((p[2] - z0) / res))
        out = []
        for dx in range(-rr, rr + 1):
            for dz in range(-rr, rr + 1):
                ii, kk = ci + dx, ck + dz
                if ii < 0 or ii >= nx or kk < 0 or kk >= nz:
                    continue
                if (gx[ii] - p[0]) ** 2 + (gz[kk] - p[2]) ** 2 > htol * htol:
                    continue
                c2 = kk * nx + ii
                l = np.searchsorted(nkey, c2 * BIG + (href - vtol + OFF), side="left")
                h = np.searchsorted(nkey, c2 * BIG + (href + vtol + OFF), side="right")
                out.extend(range(l, h))
        return np.array(out, dtype=np.int64)

    # ---------------------------------------------------------------- lifts (teleport links)
    links = []      # list of arrays of node indices; each array becomes one connected group
    lift_targets = []
    lift_mode = a.lift
    stops = [j for j in range(D.n) if "LiftStop" in D.part_attrs(j) and "/LiftCabin/" not in D.inst[D.pidx[j]].get("path", "")]
    ldoors = [j for j in range(D.n) if "LiftFloor" in D.part_attrs(j) and "Door" in D.name[j]]
    vols = [j for j in range(D.n) if D.part_attrs(j).get("LiftShaftVolume") or (D.name[j].startswith("LiftShaft") and not D.collide[j])]
    use_stops = lift_mode in ("auto", "stops") and stops
    use_doors = lift_mode in ("auto", "doors") and ldoors and not (lift_mode == "auto" and stops)
    use_vols = lift_mode in ("auto", "volume") and vols
    group = []
    if use_stops:
        for j in stops:
            p = D.P[j]
            lift_targets.append((f"{D.inst[D.pidx[j]]['path']} [LiftStop={D.part_attrs(j).get('LiftStop')}]", p, None))
            group.append(nodes_near(p))
    if use_doors:
        for j in ldoors:
            look = -D.R[j][:, 2]
            bottom = D.P[j] - np.array([0, D.S[j][1] / 2, 0])
            p = bottom + look * 4 + np.array([0, 2.8, 0])
            lift_targets.append((f"{D.inst[D.pidx[j]]['path']} [LiftFloor={D.part_attrs(j).get('LiftFloor')}] front", p, None))
            group.append(nodes_near(p))
    if group:
        links.append(np.concatenate(group))
    if use_vols:
        for j in vols:
            # every node whose body point lies inside the volume
            Rj, Pj, Sj = D.R[j], D.P[j], D.S[j]
            pts = np.stack([gx[ni], N_h + 1.0, gz[nk]], axis=1)
            loc = (pts - Pj) @ Rj
            inside = (np.abs(loc) <= Sj / 2 + 1e-6).all(1)
            if inside.any():
                links.append(np.nonzero(inside)[0])
    for g in links:
        if len(g) > 1:
            U.append(g[:-1]); V.append(g[1:])
    lift_desc = ("LiftStop markers" if use_stops else "") + (" LiftLandingDoor fronts" if use_doors else "") + (" shaft volumes" if use_vols else "")
    rep.p(f"lift links: {lift_desc.strip() or 'none'} ({sum(len(g) for g in links)} nodes linked)")

    # ---------------------------------------------------------------- components
    Ue = np.concatenate(U) if U else np.zeros(0, np.int64)
    Ve = np.concatenate(V) if V else np.zeros(0, np.int64)
    parent = np.arange(N)
    it = 0
    while len(Ue):
        it += 1
        pu, pv = parent[Ue], parent[Ve]
        ne = pu != pv
        if not ne.any():
            break
        hi_ = np.maximum(pu[ne], pv[ne]); lo_ = np.minimum(pu[ne], pv[ne])
        parent[hi_] = np.minimum(parent[hi_], lo_)
        while True:
            pp = parent[parent]
            if np.array_equal(pp, parent):
                break
            parent = pp
    comp = parent
    sx, sy, sz = [float(v) for v in a.start.split(",")]
    cand = nodes_near(np.array([sx, sy, sz]))
    if len(cand) == 0:
        rep.p(f"!! no standable node near start {a.start}; walkability cannot be evaluated")
        rep.sum(f"walkability: NO START NODE near {a.start}")
        reach = np.zeros(N, dtype=bool)
        start_node = None
    else:
        dd = (gx[ni[cand]] - sx) ** 2 + (gz[nk[cand]] - sz) ** 2 + (N_h[cand] - sy) ** 2
        start_node = cand[np.argmin(dd)]
        reach = comp == comp[start_node]
    ncomp = len(np.unique(comp)) if N else 0
    rep.p(f"edges {len(Ue)}, components {ncomp}, union-find iterations {it}")
    if start_node is not None:
        rep.p(f"start node at ({gx[ni[start_node]]:.1f}, {N_h[start_node]:.2f}, {gz[nk[start_node]]:.1f}); reachable nodes {int(reach.sum())} / {N} ({100*reach.mean():.1f}%)")

    # ---------------------------------------------------------------- probes (debug)
    for pr in a.probe:
        px, py, pz = [float(v) for v in pr.split(",")]
        ci = int(np.floor((px - x0) / res)); ck = int(np.floor((pz - z0) / res))
        rep.p(f"\nPROBE ({px}, {py}, {pz}) cell ({ci},{ck}) centre ({gx[ci]:.2f}, {gz[ck]:.2f})")
        for dz in (-2, -1, 0, 1, 2):
            row = []
            for dx in (-2, -1, 0, 1, 2):
                c2 = (ck + dz) * nx + (ci + dx)
                l = np.searchsorted(nkey, c2 * BIG + (py - 4 + OFF)); h = np.searchsorted(nkey, c2 * BIG + (py + 4 + OFF), side="right")
                hs = [f"{N_h[q]:.1f}{'R' if reach[q] else 'u'}" for q in range(l, h)]
                row.append(",".join(hs) or "-")
            rep.p("   " + " | ".join(f"{t:>12}" for t in row))
        c0 = ck * nx + ci
        sel = (O_cell == c0) & (O_lo < py + 8) & (O_hi > py - 4)
        for q in np.nonzero(sel)[0][:20]:
            rep.p(f"   obstacle in centre cell: y [{O_lo[q]:.2f}, {O_hi[q]:.2f}]")
        sel = (F_cell == c0) & (F_lo < py + 4) & (F_hi > py - 4)
        for q in np.nonzero(sel)[0][:30]:
            rep.p(f"   forbidden standing heights here: ({F_lo[q]:.2f}, {F_hi[q]:.2f})")
        sel = (S_cell == c0)
        rep.p("   surfaces in centre cell: " + ", ".join(f"{h_:.2f}(part {D.inst[D.pidx[p_]]['path']})" for h_, p_ in zip(S_h[sel], S_p[sel])))

    # ---------------------------------------------------------------- targets
    results = {}
    def check_point(cat, label, p, href=None, htol=None, vtol=None):
        c = nodes_near(p, htol or a.htol, vtol or a.vtol, href)
        ok = bool(len(c)) and bool(reach[c].any())
        near = None
        if len(c):
            d = (gx[ni[c]] - p[0]) ** 2 + (gz[nk[c]] - p[2]) ** 2
            near = (gx[ni[c[np.argmin(d)]]], N_h[c[np.argmin(d)]], gz[nk[c[np.argmin(d)]]])
        results.setdefault(cat, []).append((label, p, ok, len(c) > 0, near))
        return ok

    # workstations (Models with InteractionPosition)
    for k, x in enumerate(D.inst):
        at = x.get("attrs") or {}
        ip = at.get("InteractionPosition")
        if x["class"] == "Model" and isinstance(ip, dict) and "Vector3" in ip and not D.in_character(k):
            check_point("workstations", x["path"], np.array(ip["Vector3"]))
    # seats
    for j in range(D.n):
        if D.cls[j] in ("Seat", "VehicleSeat") and not D.character[j]:
            k = D.pidx[j]
            P, Rj = D.P[j], D.R[j]
            look = -Rj[:, 2]; right = Rj[:, 0]
            front = P + look * 2.5
            c_front = nodes_near(front)
            ok_front = bool(len(c_front)) and bool(reach[c_front].any())
            ok_any = ok_front
            for dvec in (right, -right, -look):
                if ok_any:
                    break
                cc = nodes_near(P + dvec * 2.5)
                ok_any = bool(len(cc)) and bool(reach[cc].any())
            results.setdefault("seats", []).append((D.inst[k]["path"], P, ok_any, True, None))
            results.setdefault("seats (front side)", []).append((D.inst[k]["path"], P, ok_front, len(c_front) > 0, None))
    # navigation nodes
    for j in range(D.n):
        if "NavigationNode" in D.part_attrs(j):
            check_point("navigation nodes", f"{D.inst[D.pidx[j]]['path']} [{D.part_attrs(j).get('NavigationNode')}]", D.P[j])
    # doors: both sides (lift doors: the landing side only)
    for j in range(D.n):
        nm = D.name[j]
        k = D.pidx[j]
        path = D.inst[k].get("path", "")
        if "/Doors/Door_" in path:
            # ArchKit door model: the Sensor part spans the doorway; SecureNormal (model attr) is its axis
            if nm != "Sensor":
                continue
            pmodel = D.inst[D.by_id[D.inst[k]["parent"]]]
            sn = (pmodel.get("attrs") or {}).get("SecureNormal")
            if isinstance(sn, dict):
                sn = sn.get("Vector3")
            if not isinstance(sn, (list, tuple)) or len(sn) != 3:
                continue
            nrm = np.array(sn, dtype=float)
            nrm = nrm / (np.linalg.norm(nrm) or 1)
            kind = (pmodel.get("attrs") or {}).get("DoorKind")
            bottom = D.P[j] - np.array([0, abs(D.R[j][1, :]) @ D.S[j] / 2, 0])
            base = bottom + np.array([0, 2.8, 0])
            sides = []
            for sgn in (1, -1):
                ok = False
                for dist in (2.5, 3.5, 5):
                    cc = nodes_near(base + nrm * dist * sgn, href=bottom[1] - 1, vtol=2)
                    if len(cc) and reach[cc].any():
                        ok = True
                        break
                sides.append(ok)
            label = f"{pmodel.get('path', '')} [{kind}]"
            results.setdefault("door models (both sides)", []).append((label, base, all(sides), True, f"inside(secure) {sides[0]} outside {sides[1]}"))
            continue
        if not (rx.search(nm) or "DoorOpenCFrame" in D.part_attrs(j)) or D.character[j]:
            continue
        if "/Rooms/" in path or "/Site/" in path:
            continue  # furniture/cabinet doors and gates are props, not passage doors
        thin = int(np.argmin(D.S[j]))
        nrm = D.R[j][:, thin]
        bottom = D.P[j] - np.array([0, abs(D.R[j][1, :]) @ D.S[j] / 2, 0])
        base = bottom + np.array([0, 2.8, 0])
        sides = []
        # feet within [bottom-3, bottom+1] (gates/arms may float above the ground)
        for sgn in (1, -1):
            pp = base + nrm * 3 * sgn
            cc = nodes_near(pp, href=bottom[1] - 1, vtol=2)
            sides.append(bool(len(cc)) and bool(reach[cc].any()))
        if "LiftFloor" in D.part_attrs(j):
            look = -D.R[j][:, 2]
            cc = nodes_near(base + look * 3, href=bottom[1] - 1, vtol=2)
            ok = bool(len(cc)) and bool(reach[cc].any())
            results.setdefault("lift doors (landing side)", []).append((D.inst[k]["path"] + f" [LiftFloor={D.part_attrs(j).get('LiftFloor')}]", base, ok, True, None))
        else:
            results.setdefault("doors (both sides)", []).append((D.inst[k]["path"], base, all(sides), True, f"sides reachable {sides}"))
    # lift landings
    for label, p, _ in lift_targets:
        check_point("lift landings", label, p)
    # proximity prompts: some reachable body point within MaxActivationDistance of the part
    for k, x in enumerate(D.inst):
        if x["class"] != "ProximityPrompt" or D.in_character(k):
            continue
        pk = D.parent(k)
        if pk is None or "cframe" not in D.inst[pk]:
            continue
        j = int(np.searchsorted(D.pidx, pk))
        if j >= D.n or D.pidx[j] != pk:
            continue
        dist = float(x.get("maxActivationDistance", 10))
        P, Rj, Sj = D.P[j], D.R[j], D.S[j]
        c = nodes_near(P, htol=dist, vtol=dist + 3)
        ok = False
        if len(c):
            body = np.stack([gx[ni[c]], N_h[c] + 2.8, gz[nk[c]]], axis=1)
            loc = (body - P) @ Rj
            clamped = np.clip(loc, -Sj / 2, Sj / 2)
            dd = np.linalg.norm(loc - clamped, axis=1)
            ok = bool((reach[c] & (dd <= dist)).any())
        results.setdefault("proximity prompts", []).append((f"{D.inst[pk]['path']} '{x.get('objectText', '')}'", P, ok, len(c) > 0, None))

    rep.p("\nreachability by category (reachable / total):")
    for cat, lst in results.items():
        okc = sum(1 for r in lst if r[2])
        rep.p(f"   {cat:<28} {okc:>5} / {len(lst)}")
        rep.sum(f"{cat}: {okc}/{len(lst)} reachable")
    for cat, lst in results.items():
        bad = [r for r in lst if not r[2]]
        if not bad:
            continue
        rep.p(f"\nUNREACHABLE {cat} ({len(bad)}):")
        for label, p, ok, anynode, extra in bad[: (10**9 if a.verbose else 40)]:
            why = "no standable node nearby" if not anynode else "standable but not connected to start"
            ex = f"; {extra}" if isinstance(extra, str) else (f"; nearest node {fmtv(extra)}" if extra is not None else "")
            rep.p(f"   {label} at {fmtv(p)} -- {why}{ex}")
        if len(bad) > 40 and not a.verbose:
            rep.p(f"   ... {len(bad) - 40} more (use --verbose)")

    # ---------------------------------------------------------------- per-level area table + heatmaps
    floors = D.floors()
    levels = [float(v) for v in a.levels.split(",")] if a.levels else [-24.0] + [16.0 * f for f in range(floors + 1)]
    rep.p("\nper level (nodes with surface in [Y-2, Y+12)): standable / reachable cells")
    for Y in levels:
        sel = (N_h >= Y - 2) & (N_h < Y + 12)
        rep.p(f"   level {Y:>6.0f}: standable {int(sel.sum()):>6}  reachable {int((sel & reach).sum()):>6}")
    if not a.no_images:
        prefix = a.img_prefix or os.path.join(os.path.dirname(os.path.abspath(a.dump)), f"walk_tier{D.meta.get('tier')}")
        draw_levels(prefix, levels, nx, nz, x0, z0, res, N_cell, N_h, reach, O_cell, O_lo, O_hi, S_cell, S_h, results, start_node, gx, gz, ni, nk, rep)
    rep.sum(f"standable nodes {N}, reachable {int(reach.sum())} ({(100*reach.mean() if N else 0):.1f}%), components {ncomp}")


def draw_levels(prefix, levels, nx, nz, x0, z0, res, N_cell, N_h, reach, O_cell, O_lo, O_hi, S_cell, S_h, results, start_node, gx, gz, ni, nk, rep):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.lines import Line2D
    from matplotlib.patches import Patch
    for Y in levels:
        img = np.ones((nz, nx, 3))
        # obstacles in the body band of this level
        ob = (O_lo < Y + 7) & (O_hi > Y + 0.5)
        oc = np.unique(O_cell[ob])
        img.reshape(-1, 3)[oc] = (0.25, 0.27, 0.30)
        # surfaces that exist but are not standable (blocked)
        sb = (S_h >= Y - 2) & (S_h < Y + 12)
        img.reshape(-1, 3)[np.unique(S_cell[sb])] = (0.80, 0.80, 0.80)
        img.reshape(-1, 3)[oc] = (0.25, 0.27, 0.30)
        sel = (N_h >= Y - 2) & (N_h < Y + 12)
        un = sel & ~reach
        img.reshape(-1, 3)[N_cell[un]] = (0.98, 0.70, 0.25)
        rc = sel & reach
        img.reshape(-1, 3)[N_cell[rc]] = (0.35, 0.75, 0.40)
        w_in = min(16.0, max(6.0, nx * 3 / 100))
        h_in = w_in * nz / nx + 0.9
        fig = plt.figure(figsize=(w_in, h_in), dpi=100)
        ax = fig.add_axes([0.06, 0.6 / h_in, 0.92, 1 - 0.95 / h_in])
        ax.imshow(img, origin="upper", extent=(x0, x0 + nx * res, z0 + nz * res, z0), interpolation="nearest")
        okx, oky, bx, by = [], [], [], []
        for cat, lst in results.items():
            for label, p, ok, anynode, extra in lst:
                if Y - 2 <= p[1] - 2.8 < Y + 14 or Y - 2 <= p[1] < Y + 12:
                    (okx if ok else bx).append(p[0])
                    (oky if ok else by).append(p[2])
        ax.scatter(okx, oky, s=4, c="#1f4fbf", linewidths=0, zorder=3)
        ax.scatter(bx, by, s=22, c="#e01010", edgecolors="white", linewidths=0.4, zorder=4)
        if start_node is not None and Y - 2 <= N_h[start_node] < Y + 12:
            ax.scatter([gx[ni[start_node]]], [gz[nk[start_node]]], s=60, marker="*", c="black", zorder=5)
        ax.set_title(f"walkability level y={Y:.0f}  (top view, x right, front/-Z at top)  reachable {int(rc.sum())}  unreachable-standable {int(un.sum())}", fontsize=9)
        ax.set_xlabel("x (studs)"); ax.set_ylabel("z (studs)")
        ax.legend(handles=[Patch(color=(0.35, 0.75, 0.40), label="reachable"), Patch(color=(0.98, 0.70, 0.25), label="standable, not reachable"),
                           Patch(color=(0.80, 0.80, 0.80), label="surface, no clearance"), Patch(color=(0.25, 0.27, 0.30), label="obstacle in body band"),
                           Line2D([], [], marker="o", ls="", color="#e01010", label="unreachable target"), Line2D([], [], marker="o", ls="", color="#1f4fbf", markersize=3, label="reachable target")],
                  loc="lower left", fontsize=7, framealpha=0.85)
        out = f"{prefix}_level{int(Y)}.png"
        fig.savefig(out)
        plt.close(fig)
        rep.p(f"   wrote {out}")


if __name__ == "__main__":
    main()
