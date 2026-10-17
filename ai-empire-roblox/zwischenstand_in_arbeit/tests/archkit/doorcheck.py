#!/usr/bin/env python3
"""Door geometry checks on a harness dump: closed/open leaf vs frame/wall overlaps, opening side, hinge."""
import json, sys
import numpy as np

def cfm(a):
    M = np.eye(4); M[:3, 3] = a[:3]; M[:3, :3] = np.array(a[3:12]).reshape(3, 3); return M

def obb_overlap(A, sa, B, sb, tol=0.02):
    """SAT test; returns penetration depth (>tol means real overlap)."""
    Ra, Rb = A[:3, :3], B[:3, :3]
    ha, hb = np.array(sa) / 2, np.array(sb) / 2
    t = B[:3, 3] - A[:3, 3]
    axes = [Ra[:, i] for i in range(3)] + [Rb[:, i] for i in range(3)]
    for i in range(3):
        for j in range(3):
            c = np.cross(Ra[:, i], Rb[:, j])
            if np.linalg.norm(c) > 1e-6:
                axes.append(c / np.linalg.norm(c))
    depth = 1e9
    for ax in axes:
        ra = sum(ha[k] * abs(ax @ Ra[:, k]) for k in range(3))
        rb = sum(hb[k] * abs(ax @ Rb[:, k]) for k in range(3))
        d = ra + rb - abs(t @ ax)
        if d <= tol:
            return 0.0
        depth = min(depth, d)
    return depth

d = json.load(open(sys.argv[1]))
inst = d["instances"]
byId = {i["id"]: i for i in inst}
doors = [i for i in inst if i["class"] == "Model" and "DoorId" in i.get("attrs", {})]
walls = [i for i in inst if "cframe" in i and i["path"].startswith("Office/Walls/") and i.get("canCollide")]
problems = 0
for door in doors:
    a = door["attrs"]
    pre = door["path"] + "/"
    parts = [i for i in inst if "cframe" in i and i["path"].startswith(pre)]
    frame = [p for p in parts if p["path"].startswith(pre + "Frame/")]
    normal = np.array(a["SecureNormal"]["Vector3"])
    leaves = [i for i in inst if i["class"] == "Model" and i["parentPath"] == door["path"] and i["name"].startswith("Leaf")]
    sensor = [p for p in parts if p["name"] == "Sensor"]
    out = []
    dc = np.array(door["attrs"]["SecureNormal"]["Vector3"]) * 0
    fc = np.mean([np.array(p["cframe"][:3]) for p in parts], axis=0)
    near = [w for w in walls if np.linalg.norm(np.array(w["cframe"][:3]) - fc) < 12 + max(w["size"]) / 2]
    centre = np.mean([np.array(p["cframe"][:3]) for p in frame], axis=0) if frame else None
    for leaf in leaves:
        la = leaf["attrs"]
        C, O = cfm(la["ClosedPivot"]["CFrame"]), cfm(la["OpenPivot"]["CFrame"])
        T = O @ np.linalg.inv(C)
        lparts = [p for p in parts if p["path"].startswith(leaf["path"] + "/")]
        solid = [p for p in lparts if p.get("canCollide")]
        mods = [i for i in inst if i["class"] == "PathfindingModifier" and i["parentPath"].startswith(leaf["path"] + "/")]
        if not mods:
            out.append(f"{leaf['name']}: no PathfindingModifier")
        pivot_ok = abs(np.linalg.det(C[:3, :3]) - 1) < 1e-6
        side = []
        for p in lparts:
            P = cfm(p["cframe"]); Po = T @ P
            side.append(Po[:3, 3])
            for f in frame:
                for state, M in (("closed", P), ("open", Po)):
                    dep = obb_overlap(M, p["size"], cfm(f["cframe"]), f["size"])
                    if dep > 0.03 and p.get("canCollide") and f.get("canCollide"):
                        out.append(f"{leaf['name']}/{p['name']} {state} overlaps frame {f['name']} by {dep:.2f}")
            for w in near:
                for state, M in (("closed", P), ("open", Po)):
                    dep = obb_overlap(M, p["size"], cfm(w["cframe"]), w["size"])
                    if dep > 0.03 and p.get("canCollide"):
                        out.append(f"{leaf['name']}/{p['name']} {state} overlaps wall {w['name']} by {dep:.2f}")
        if centre is not None and side:
            disp = np.mean(side, axis=0) - centre
            s = disp @ normal
            out.append(f"{leaf['name']}: motion={la.get('Motion')} open-centre offset along SecureNormal {s:+.2f}")
    print(f"== {door['name']} kind={a['DoorKind']} access={a['AccessClass']} auto={a['AutoOpen']} hidden={a['Hidden']} leaves={len(leaves)} parts={len(parts)} sensor={len(sensor)}")
    for o in out:
        if "overlaps" in o or "no Pathfinding" in o:
            problems += 1
        print("   ", o)
    po = [p for p in parts if p["name"] in ("PromptOut", "PromptIn")]
    for p in po:
        pr = [i for i in inst if i["class"] == "ProximityPrompt" and i["parentPath"] == p["path"]]
        rl = [i for i in inst if i["name"] == "ReaderLight" and i["parentPath"] == p["path"]]
        side = (np.array(p["cframe"][:3]) - centre) @ normal if centre is not None else 0
        pa = pr[0]["attrs"] if pr else {}
        print(f"    {p['name']}: side {side:+.2f} prompt={bool(pr)} reader={bool(rl)} Side={pa.get('Side')} Public={pa.get('Public')} Owner={pa.get('OwnerUserId')} text={pr[0].get('objectText') if pr else None} dist={pr[0].get('maxActivationDistance') if pr else None}")
print("PROBLEMS", problems)
