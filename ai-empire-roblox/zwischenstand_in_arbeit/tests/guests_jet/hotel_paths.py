#!/usr/bin/env python3
"""guests_jet: every hotel-guest walk (GuestPlan.hotelWalksForTests, building-local) against a built HQ dump with
the guest house (harness dump_tier2..4.json, building-local): a body of the walk's radius (axis 1.0..5.0 studs
above the feet - steps and kerbs below 1.0 are walkable, chair seats / tables / sofas / planters are not) touches
no collidable part (doors excluded: the guests use the door openings, DoorService opens the automatic and glass
doors), and a floor surface lies within 0.75 stud under the feet. The last / first 3.4 studs into / out of a seat
are not checked (the guest sits down there).
usage: python3 tests/guests_jet/hotel_paths.py WALKS.txt DUMP.json [DUMP2.json ...]
"""
import json, sys, re
import numpy as np

walks = []
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) >= 6 and f[0] == "WALK":
        n = int(f[5]); vals = [float(a) for a in f[6:6 + 3 * n]]
        walks.append((f[1], float(f[2]), float(f[3]), float(f[4]), np.array(vals).reshape(n, 3)))
passed = failed = 0
def check(name, ok, detail=""):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1; print("FAIL  " + name + (("  -- " + str(detail)) if detail != "" else ""))
check("hotel walks present", len(walks) >= 80, len(walks))
DOOR = re.compile(r"Door(?!Frame|Transom)|Gate", re.I)
for path_ in sys.argv[2:]:
    d = json.load(open(path_))
    tier = d["meta"].get("tier")
    ins = d["instances"]
    byid = {x["id"]: x for x in ins}
    def is_door(x):
        a = x.get("attrs") or {}
        if a.get("DoorLeaf") or a.get("DoorOpenCFrame") or a.get("ClosedCFrame"):
            return True
        p = x
        for _ in range(4):
            if DOOR.search(p["name"]) or (p.get("attrs") or {}).get("DoorLeaf"):
                return True
            if p.get("parent") is None or p["parent"] not in byid:
                break
            p = byid[p["parent"]]
        return False
    parts = []
    for x in ins:
        if "size" not in x or "cframe" not in x or not x.get("canCollide", True):
            continue
        c = np.array(x["cframe"][:3]); R = np.array(x["cframe"][3:12]).reshape(3, 3); h = np.array(x["size"]) / 2
        e = np.abs(R) @ h
        lo, hi = c - e, c + e
        if hi[0] < -146 or lo[0] > -82 or hi[2] < 50 or lo[2] > 178 or lo[1] > 40:
            continue
        shape = "wedge" if x["class"] == "WedgePart" else ("ball" if x.get("shape") == "Ball" else ("cyl" if x.get("shape") == "Cylinder" else "box"))
        parts.append((x["path"], x["name"], c, R, h, lo, hi, shape, is_door(x)))
    LO = np.array([p[5] for p in parts]); HI = np.array([p[6] for p in parts])
    def inside(L, h, shape, inf):
        m = np.all(np.abs(L) <= h + inf, axis=1)
        if shape == "wedge":
            m &= (L[:, 1] * h[2] - L[:, 2] * h[1]) / np.hypot(h[1], h[2]) <= inf.max()
        elif shape == "ball":
            m &= np.linalg.norm(L, axis=1) <= h.min() + inf.max()
        return m
    def floor_under(P):
        out = np.full(len(P), -1e9)
        for j in range(len(parts)):
            p, nm, c, R, h, lo, hi, shape, door = parts[j]
            if door:
                continue
            sel = np.where((P[:, 0] >= lo[0]) & (P[:, 0] <= hi[0]) & (P[:, 2] >= lo[2]) & (P[:, 2] <= hi[2]) & (lo[1] <= P[:, 1] + 0.75))[0]
            for k in sel:
                ys = np.linspace(P[k, 1] - 2.5, P[k, 1] + 0.75, 66)
                Q = np.stack([np.full(66, P[k, 0]), ys, np.full(66, P[k, 2])], axis=1)
                ins_ = inside((Q - c) @ R, h, shape, np.zeros(3))
                if ins_.any():
                    out[k] = max(out[k], ys[np.where(ins_)[0].max()])
        return out
    bad_walks = 0
    for name, r, t0, t1, path in walks:
        seg = np.diff(path, axis=0); lens = np.linalg.norm(seg, axis=1); cum = np.concatenate([[0], np.cumsum(lens)])
        L = cum[-1]
        s = np.arange(0, L + 1e-6, 0.35)
        s = s[(s >= t0) & (s <= L - t1)]
        if len(s) == 0:
            continue
        idx = np.clip(np.searchsorted(cum, s, side="right") - 1, 0, max(0, len(lens) - 1))
        f = np.where(lens[idx] > 1e-9, (s - cum[idx]) / np.maximum(lens[idx], 1e-9), 0)
        P = path[idx] + seg[idx] * f[:, None]
        lo = P.min(axis=0) - r - 1; hi = P.max(axis=0) + r + 6
        cand = np.where(np.all(LO <= hi, axis=1) & np.all(HI >= lo, axis=1))[0]
        bad = []
        for j in cand:
            p, nm, c, R, h, plo, phi, shape, door = parts[j]
            if door:
                continue
            up = abs(R[1, 1]) > 0.999
            inf = np.array([r, 0.0, r]) if up else np.array([r] * 3)
            for dy in (1.0, 1.8, 2.8, 3.8, 4.8):
                m = inside((P + np.array([0, dy, 0]) - c) @ R, h, shape, inf)
                if m.any():
                    k0 = int(np.where(m)[0][0])
                    bad.append("%s at %s (s=%.1f, %s)" % ("/".join(p.split("/")[-3:]), np.round(c, 1).tolist(), s[k0], np.round(P[k0], 2).tolist()))
                    break
        fl = floor_under(P)
        off = np.abs(fl - P[:, 1]) > 0.75
        if off.any():
            # the body stands on whatever is under its footprint: also look 0.25 stud around the centre (seams
            # between a stair ramp and its landing)
            for dx, dz in ((0.25, 0), (-0.25, 0), (0, 0.25), (0, -0.25)):
                k = np.where(off)[0]
                fl2 = floor_under(P[k] + np.array([dx, 0, dz]))
                ok = np.abs(fl2 - P[k, 1]) <= 0.75
                off[k[ok]] = False
                if not off.any():
                    break
        if off.any():
            k0 = int(np.where(off)[0][0])
            bad.append("no floor under the feet at %s (floor %.2f)" % (np.round(P[k0], 2).tolist(), fl[k0]))
        for b in bad[:3]:
            print("WALK  tier%s %-30s %s" % (tier, name, b))
        bad_walks += 1 if bad else 0
    check("tier %s: every hotel walk clear of walls / furniture with a floor under the feet" % tier, bad_walks == 0, "%d walks blocked" % bad_walks)
print("guests_jet_hotel_paths: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
