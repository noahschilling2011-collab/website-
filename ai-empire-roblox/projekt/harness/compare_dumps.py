#!/usr/bin/env python3
"""Compare two dumps of the same tier built at different campus CFrames.

usage: compare_dumps.py out/dump_tier1.json out/dump_tier1_plot.json [--tol 1e-4]
Both dumps are mapped into building-local coordinates (inverse of meta.campusCFrame) and every
BasePart CFrame/Size is compared instance by instance (same traversal order).  World-space
attributes (Vector3/CFrame) must match after the transform; local-space ones must match raw.
Exit 1 when anything differs: that means some generator code mixes world and local coordinates
(or the mock's CFrame math is wrong).
"""
import json, sys
import numpy as np


def cf_mat(c):
    m = np.eye(4)
    m[:3, 3] = c[0:3]
    m[:3, :3] = np.array(c[3:12]).reshape(3, 3)
    return m


def main():
    a_path, b_path = sys.argv[1], sys.argv[2]
    tol = float(sys.argv[sys.argv.index("--tol") + 1]) if "--tol" in sys.argv else 1e-4
    A, B = json.load(open(a_path)), json.load(open(b_path))
    ia, ib = A["instances"], B["instances"]
    inva = np.linalg.inv(cf_mat(A["meta"]["campusCFrame"]))
    invb = np.linalg.inv(cf_mat(B["meta"]["campusCFrame"]))
    problems = []
    if len(ia) != len(ib):
        problems.append(f"instance count differs: {len(ia)} vs {len(ib)}")
    n = min(len(ia), len(ib))
    worst = 0.0
    nparts = 0
    attr_bad = {}
    for k in range(n):
        x, y = ia[k], ib[k]
        if x["path"] != y["path"] or x["class"] != y["class"]:
            problems.append(f"#{k} structure differs: {x['path']} vs {y['path']}")
            if len(problems) > 20:
                break
            continue
        if "cframe" in x and "size" in x:
            nparts += 1
            ma = inva @ cf_mat(x["cframe"])
            mb = invb @ cf_mat(y["cframe"])
            d = float(np.abs(ma - mb).max())
            worst = max(worst, d)
            if d > tol and len(problems) < 40:
                problems.append(f"{x['path']}: local CFrame differs by {d:.4g} (A pos {np.round(ma[:3,3],3).tolist()} B pos {np.round(mb[:3,3],3).tolist()})")
            if x["size"] != y["size"]:
                problems.append(f"{x['path']}: size differs {x['size']} vs {y['size']}")
        for key, va in (x.get("attrs") or {}).items():
            vb = (y.get("attrs") or {}).get(key)
            if isinstance(va, dict) and ("Vector3" in va or "CFrame" in va):
                if not isinstance(vb, dict):
                    attr_bad.setdefault(key, []).append(x["path"])
                    continue
                if "Vector3" in va:
                    # direction attributes (unit normals) transform without translation
                    dirlike = key in ("SecureNormal",) or key.endswith("Normal") or key.endswith("Direction")
                    hw = 0.0 if dirlike else 1.0
                    pa, pb = np.array(va["Vector3"] + [hw]), np.array(vb["Vector3"] + [hw])
                    raw = np.abs(pa - pb).max()
                    w = np.abs((inva @ pa) - (invb @ pb)).max()
                else:
                    ma, mb = cf_mat(va["CFrame"]), cf_mat(vb["CFrame"])
                    raw = np.abs(ma - mb).max()
                    w = np.abs(inva @ ma - invb @ mb).max()
                if min(raw, w) > tol:
                    attr_bad.setdefault(key, []).append(x["path"])
            elif va != vb and not (isinstance(va, float) and isinstance(vb, float) and abs(va - vb) <= tol):
                # plain values that legitimately encode world coordinates are reported but not fatal
                attr_bad.setdefault(key + " (scalar)", []).append(x["path"])
    scalar_only = {k: v for k, v in attr_bad.items() if k.endswith("(scalar)")}
    vec_bad = {k: v for k, v in attr_bad.items() if not k.endswith("(scalar)")}
    print(f"compare {a_path} vs {b_path}: {nparts} parts, worst local CFrame deviation {worst:.3g}")
    for p in problems[:40]:
        print("  DIFF", p)
    for k, v in vec_bad.items():
        print(f"  ATTR {k}: inconsistent on {len(v)} instance(s), e.g. {v[:3]}")
    for k, v in scalar_only.items():
        print(f"  note: scalar attr {k} differs on {len(v)} instance(s) (ok if it stores world coordinates), e.g. {v[:2]}")
    ok = not problems and not vec_bad
    print("  frame consistency:", "OK" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
