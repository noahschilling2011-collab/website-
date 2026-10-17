#!/usr/bin/env python3
"""Package "life" - geometry of the animated / new props on the real harness dumps.
For every tier: the parts of every PropFx root plus every part that is new against a baseline dump
(same name + position + size absent there) are tested (oriented boxes, separating axes, 0.08 stud
tolerance per side) against
  * structural parts: collidable Wall* / Glass* / Partition* / Column* / Core* / Shaft* / Stair* /
    Facade* / Mullion* / Pier* / Railing* parts that belong to no prop,
  * door swing volumes: every door leaf box at its closed and at its open pivot (Leaf models with
    ClosedPivot / OpenPivot) and the box spanning both (covers a quarter swing about the hinge),
  * other collidable parts for COLLIDABLE new parts (furniture overlap).
Moving parts (slider / hinge / belt / arm travel) are also tested at the end of their travel.
Prints "life props geometry: N passed, M failed".
Usage: python3 tests/life/check_props_geometry.py [--out out/life] [--base out/stable] [--tiers 1,4]
"""
import argparse, json, os, re, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "harness"))
from dumplib import Dump, cf_to_mat  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--out", default=os.path.join(ROOT, "out", "life"))
ap.add_argument("--base", default=os.path.join(ROOT, "out", "stable"))
ap.add_argument("--tiers", default="1,2,3,4")
ap.add_argument("--verbose", action="store_true")
a = ap.parse_args()
TOL = 0.08
STRUCT = re.compile(r"^(Wall|Glass|Partition|Column|Core|Shaft|Stair|Facade|Mullion|Pier|Railing|Balustrade)")
passed = failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print(f"FAIL  {name}" + (f"  -- {detail}" if detail else ""))


def obb_overlap(P1, R1, H1, P2, R2, H2):
    """Separating axis test for two oriented boxes (centre, rotation columns = axes, half sizes)."""
    A = [R1[:, i] for i in range(3)]
    B = [R2[:, i] for i in range(3)]
    T = P2 - P1
    axes = A + B + [np.cross(x, y) for x in A for y in B]
    for ax in axes:
        n = np.linalg.norm(ax)
        if n < 1e-9:
            continue
        ax = ax / n
        r1 = sum(H1[i] * abs(np.dot(A[i], ax)) for i in range(3))
        r2 = sum(H2[i] * abs(np.dot(B[i], ax)) for i in range(3))
        if abs(np.dot(T, ax)) >= r1 + r2:
            return False
    return True


def key(d, j):
    p = d.P[j]
    s = d.S[j]
    return (d.name[j], round(p[0], 1), round(p[1], 1), round(p[2], 1), round(s[0], 1), round(s[1], 1), round(s[2], 1))


for tier in [int(t) for t in a.tiers.split(",")]:
    path = os.path.join(a.out, f"dump_tier{tier}.json")
    check(f"tier {tier} dump exists", os.path.exists(path), path)
    if not os.path.exists(path):
        continue
    d = Dump(path)
    base_keys = set()
    bpath = os.path.join(a.base, f"dump_tier{tier}.json")
    if os.path.exists(bpath):
        b = Dump(bpath)
        base_keys = {key(b, j) for j in range(b.n) if not b.character[j]}
    else:
        print(f"note: no baseline {bpath}; only PropFx parts are tested")
    # instance index -> part row
    row = {int(k): j for j, k in enumerate(d.pidx)}
    # prop roots and their parts (row -> root instance index)
    prop_of = {}
    roots = []
    for k, x in enumerate(d.inst):
        if "PropFx" in (x.get("tags") or []):
            roots.append(k)
    children = {}
    for k, x in enumerate(d.inst):
        p = x["parent"]
        if p is not None:
            children.setdefault(d.by_id[p], []).append(k)

    def descendants(k):
        out, stack = [], [k]
        while stack:
            n = stack.pop()
            out.append(n)
            stack.extend(children.get(n, []))
        return out
    for k in roots:
        for n in descendants(k):
            if n in row:
                prop_of[row[n]] = k
    new_rows = [j for j in range(d.n) if not d.character[j] and key(d, j) not in base_keys] if base_keys else []
    test_rows = sorted(set(prop_of) | set(new_rows))
    # obstacles
    struct = [j for j in range(d.n) if d.collide[j] and not d.character[j] and j not in prop_of and STRUCT.match(d.name[j]) and key(d, j) in base_keys | ({key(d, j)} if not base_keys else set())]
    furniture = [j for j in range(d.n) if d.collide[j] and not d.character[j] and j not in prop_of and not STRUCT.match(d.name[j])]
    # door swing boxes
    swings = []  # (P, R, H, label)
    for k, x in enumerate(d.inst):
        at = x.get("attrs") or {}
        if x["class"] == "Model" and "ClosedPivot" in at and "OpenPivot" in at:
            C = cf_to_mat(at["ClosedPivot"]["CFrame"])
            O = cf_to_mat(at["OpenPivot"]["CFrame"])
            if d.transformed:
                inv = np.linalg.inv(d.campus)
                C, O = inv @ C, inv @ O
            move = O @ np.linalg.inv(C)
            pts = []
            for n in descendants(k):
                if n in row:
                    j = row[n]
                    corners = d.corners(np.array([j]))[0]
                    pts.extend(corners)
                    pts.extend((move[:3, :3] @ corners.T).T + move[:3, 3])
            if not pts:
                continue
            # box spanning both poses in the door's closed frame
            Rc = C[:3, :3]
            loc = (np.array(pts) - C[:3, 3]) @ Rc
            lo, hi = loc.min(axis=0), loc.max(axis=0)
            centre = C[:3, 3] + Rc @ ((lo + hi) / 2)
            swings.append((centre, Rc, (hi - lo) / 2, d.inst[d.parent(k)]["name"] if d.parent(k) is not None else x["name"]))

    def boxes_of(j):
        """the part's box at rest, plus at the end of its prop's travel (slider / hinge)."""
        out = [(d.P[j], d.R[j])]
        k = prop_of.get(j)
        if k is None:
            return out
        at = d.inst[k].get("attrs") or {}
        fx = str(at.get("Fx", ""))
        axis = {"x": 0, "y": 1, "z": 2}.get(at.get("FxAxis", "y"), 1)
        travel = at.get("FxTravel", 0) or 0
        pa = d.part_attrs(j)
        flagged = any(d.part_attrs(r).get("FxMove") for r, kk in prop_of.items() if kk == k)
        if flagged and not pa.get("FxMove"):
            return out
        x = d.inst[k]
        if x["class"] == "Model":
            M = cf_to_mat(x["pivot"])
        else:
            M = cf_to_mat(x["cframe"])
        Rm, Pm = M[:3, :3], M[:3, 3]
        if "slider" in fx and travel:
            out.append((d.P[j] + Rm[:, axis] * travel, d.R[j]))
        if "hinge" in fx and travel:
            h = at.get("FxHinge", {}).get("Vector3", [0, 0, 0])
            hw = Pm + Rm @ np.array(h)
            ax = Rm[:, axis]
            c, s = np.cos(travel), np.sin(travel)
            K = np.array([[0, -ax[2], ax[1]], [ax[2], 0, -ax[0]], [-ax[1], ax[0], 0]])
            Rot = np.eye(3) + s * K + (1 - c) * (K @ K)
            out.append((hw + Rot @ (d.P[j] - hw), Rot @ d.R[j]))
        return out

    # broad phase by AABB
    lo_all, hi_all = d.aabb()
    hits = {}
    for j in test_rows:
        if min(d.S[j]) < 0.02:
            continue
        H = np.maximum(d.S[j] / 2 - TOL, 0.005)
        for (P, R) in boxes_of(j):
            ext = np.abs(R) @ (d.S[j] / 2)
            jlo, jhi = P - ext, P + ext
            cands = struct + (furniture if d.collide[j] and j in new_rows else [])
            for o in cands:
                if o == j:
                    continue
                if (hi_all[o] < jlo).any() or (lo_all[o] > jhi).any():
                    continue
                Ho = np.maximum(d.S[o] / 2 - TOL, 0.005)
                if obb_overlap(P, R, H, d.P[o], d.R[o], Ho):
                    # parts of the same model (furniture assembled from parts) are fine
                    if d.parent(int(d.pidx[o])) == d.parent(int(d.pidx[j])):
                        continue
                    if j in prop_of and o in prop_of:
                        continue
                    hits.setdefault(j, set()).add(d.name[o])
            for (Ps, Rs, Hs, label) in swings:
                ext2 = np.abs(Rs) @ Hs
                if ((Ps + ext2) < jlo).any() or ((Ps - ext2) > jhi).any():
                    continue
                if obb_overlap(P, R, H, Ps, Rs, np.maximum(Hs - TOL, 0.005)):
                    hits.setdefault(j, set()).add("swing:" + label)
    for j in test_rows:
        label = f"tier {tier} {d.name[j]} @ {d.P[j].round(1).tolist()}" + (f" (prop {d.inst[prop_of[j]]['name']})" if j in prop_of else "")
        check("prop part clear of walls / doors", j not in hits, label + " vs " + ", ".join(sorted(hits.get(j, []))))
    print(f"tier {tier}: {len(roots)} PropFx roots, {len(prop_of)} prop parts, {len(new_rows)} new parts vs baseline, {len(swings)} door leaves, {len(hits)} conflicts")
print(f"life props geometry: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
