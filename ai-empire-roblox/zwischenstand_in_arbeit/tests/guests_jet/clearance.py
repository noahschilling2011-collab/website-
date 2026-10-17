#!/usr/bin/env python3
"""guests_jet: clearance of the company jet and of the people's walks against the built world
(dump + log from tests/guests_jet/world_dump.sh).

1. Jet hull sweep (like tests/flight/clearance.py): the real AircraftModel "bizjet" hull (JetPlan scale, full LOD,
   airstair stowed) sampled with shell points (0.3-stud grid; box / wedge / cylinder / ball / sphere-mesh ellipsoid)
   at every low pose (0.25 s, < 150 studs above the ground) of the flights out / back / ferry to both Port Meridian
   slots, against every visible world part (exact shapes, inflated by MARGIN). Excluded: the airport's decorative
   PrivateJet in Hangar 1 and the Port Meridian stand-2 airliner (JetController hides both locally while a company
   jet uses their place), parts below 0.5 stud above the ground (markings). The parked frames (hangar, stand, PM
   slots) are included as the last pose of every flight.
2. Walks (WALK lines: pilots / companions from JetPlan, terminal passengers from GuestPlan): sampled every 0.4 stud;
   a body of the walk's radius (axis from 0.6 to 5 studs above the feet) must not touch any collidable world part
   (doors and the airport's non-colliding decor excluded by CanCollide), and a floor surface must be under the feet
   (within 0.75 stud) except on the airstairs (client-built, not in the dump) and inside the jet. Jet walks are also
   checked against the parked jet hull while on the ground (wings, engines, tail).
usage: python3 tests/guests_jet/clearance.py [out/guests_jet/world] [--margin 0.5] [--verbose]
"""
import json, sys, os, collections
import numpy as np

ARGS = [a for i, a in enumerate(sys.argv[1:], 1) if not a.startswith("--") and sys.argv[i - 1] != "--margin"]
OUT = ARGS[0] if ARGS else "out/guests_jet/world"
MARGIN = 0.5
if "--margin" in sys.argv:
    MARGIN = float(sys.argv[sys.argv.index("--margin") + 1])
VERBOSE = "--verbose" in sys.argv
STEP = 0.3
GROUND_SKIP = 24.75
HULL_SKIP = {"Gear", "GearDoor", "NoseGear", "MainGear", "Wheel", "Tyre", "Strut", "Axle"}

passed = failed = 0
def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL  " + name + (("  -- " + str(detail)) if detail != "" else ""))

dump = json.load(open(os.path.join(OUT, "dump.json")))
ins = dump["instances"]
mesh_parent = {x["parent"] for x in ins if x["class"] == "SpecialMesh" and x.get("meshType") == "Sphere"}

def frame(x):
    cf = x["cframe"]
    return np.array(cf[:3], float), np.array(cf[3:12], float).reshape(3, 3), np.array(x["size"], float) / 2

def shape_of(x):
    if x["id"] in mesh_parent:
        return "ellipsoid"
    if x["class"] == "WedgePart":
        return "wedge"
    if x["class"] in ("Part", "Seat") and x.get("shape") == "Cylinder":
        return "cylinder"
    if x["class"] in ("Part", "Seat") and x.get("shape") == "Ball":
        return "ball"
    return "box"

def inside_local(L, h, shape):
    ax = np.abs(L)
    m = np.all(ax <= h + 1e-9, axis=1)
    if shape == "wedge":
        m &= L[:, 1] * h[2] - L[:, 2] * h[1] <= 1e-9
    elif shape == "cylinder":
        r = min(h[1], h[2])
        m &= L[:, 1] ** 2 + L[:, 2] ** 2 <= r * r
    elif shape == "ball":
        r = h.min()
        m &= (L ** 2).sum(axis=1) <= r * r
    elif shape == "ellipsoid":
        m &= ((L / np.maximum(h, 1e-6)) ** 2).sum(axis=1) <= 1
    return m

def gear_like(name, attrs):
    return attrs.get("Gear") is True or any(name.startswith(s) for s in HULL_SKIP)

def hull_samples(prefix):
    """Shell points of the hull's solids (Airstair / DoorPanel / gear / interior excluded)."""
    solids = []
    for x in ins:
        if not x["path"].startswith(prefix) or "size" not in x or (x.get("transparency") or 0) >= 0.99:
            continue
        a = x.get("attrs") or {}
        if gear_like(x["name"], a) or a.get("Airstair") or a.get("DoorPanel") or x["name"].startswith(("Cabin", "Cockpit", "Pilot", "Panel", "Display", "Glareshield",
                "Instrument", "Pedestal", "Thrust", "Headrest", "Titles", "TailName", "Spinner", "FanBlade", "Fan", "NavLight", "Beacon", "Window", "Outline")):
            continue
        c, R, h = frame(x)
        solids.append((x["name"], c, R, h, shape_of(x)))
    pts, names = [], []
    for name, c, R, h, shape in solids:
        g = [np.linspace(-hh, hh, max(2, int(2 * hh / STEP) + 1)) for hh in h]
        L = np.array(np.meshgrid(*g, indexing="ij")).reshape(3, -1).T
        L = L[inside_local(L, h, shape)]
        if np.all(h > STEP * 1.5):
            inner = inside_local(L, np.maximum(h - STEP * 1.01, 1e-3), shape)
            L = L[~inner]
        if len(L) == 0:
            L = np.zeros((1, 3))
        pts.append(c + L @ R.T); names += [name] * len(L)
    return np.concatenate(pts), np.array(names)

hull, hull_names = hull_samples("World/JetShowcase/JetHull/")
check("jet hull samples present", len(hull) > 5000, len(hull))

# world obstacles (visible parts above the ground)
excluded = []
for x in ins:
    if x["class"] == "Model" and ((x["name"] == "PrivateJet" and "/Hangar/" in x["path"]) or (x["name"] == "ParkedAircraft" and (x.get("attrs") or {}).get("Stand") == "PM2")):
        excluded.append(x["path"] + "/")
check("the hangar's PrivateJet and the PM stand-2 airliner found (hidden locally by JetController)", len(excluded) == 2, excluded)
world = []
for x in ins:
    p = x["path"]
    if "size" not in x or "cframe" not in x or p.startswith("World/JetShowcase/"):
        continue
    if (x.get("transparency") or 0) >= 0.99 and not x.get("canCollide"):
        continue
    if any(p.startswith(r) for r in excluded):
        continue
    c, R, h = frame(x)
    ext = np.abs(R) @ h
    world.append((p, x["name"], c, R, h, shape_of(x), c - ext, c + ext, bool(x.get("canCollide", True)), (x.get("transparency") or 0) < 0.99))
WLO = np.array([w[6] for w in world]); WHI = np.array([w[7] for w in world])
check("world built (district + city)", len(world) > 4000, len(world))

def corners(lo, hi):
    return np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])

def hit_points(P, j, margin, flat=False):
    """mask of world points P (n x 3) within `margin` of world part j (flat: horizontally only for upright parts -
    a body sample above a floor slab does not touch it)"""
    p, nm, c, Rw, h, shape = world[j][:6]
    L = (P - c) @ Rw
    up = abs(Rw[1, 1]) > 0.999
    inf = np.array([margin, 0.0, margin]) if (flat and up) else np.array([margin] * 3)
    m = inside_local(L, h + inf, "box")
    if shape == "wedge":
        m &= (L[:, 1] * h[2] - L[:, 2] * h[1]) / np.hypot(h[1], h[2]) <= margin
    elif shape == "cylinder":
        r = min(h[1], h[2]) + margin
        m &= L[:, 1] ** 2 + L[:, 2] ** 2 <= r * r
    elif shape == "ball":
        r = h.min() + margin
        m &= (L ** 2).sum(axis=1) <= r * r
    return m

# ------------------------------------------------------------------ jet poses
poses = collections.defaultdict(list)
parks = {}
walks = []
for line in open(os.path.join(OUT, "log.txt")):
    f = line.split()
    if len(f) >= 17 and f[0] == "[print]" and f[1] == "POSE":
        v = [float(a) for a in f[5:17]]
        poses[f[2]].append((float(f[3]), f[4], np.array(v[:3]), np.array(v[3:12]).reshape(3, 3)))
    elif len(f) >= 15 and f[0] == "[print]" and f[1] == "PARK":
        v = [float(a) for a in f[3:15]]
        parks[f[2]] = (np.array(v[:3]), np.array(v[3:12]).reshape(3, 3))
    elif len(f) >= 7 and f[0] == "[print]" and f[1] == "WALK":
        n = int(f[6]); vals = [float(a) for a in f[7:7 + 3 * n]]
        walks.append((f[2], float(f[3]), float(f[4]), float(f[5]), np.array(vals).reshape(n, 3)))
for kind in ("out", "back", "ferry"):
    for slot in (1, 2):
        check("jet_%s%d: low poses present" % (kind, slot), len(poses.get("jet_%s%d" % (kind, slot), [])) >= 150, len(poses.get("jet_%s%d" % (kind, slot), [])))
check("parked frames: hangar, stand, both PM slots", set(parks) >= {"home", "stand", "pm1", "pm2"}, sorted(parks))

order = np.argsort(hull[:, 0]); HULL = hull[order]; HNAMES = hull_names[order]; HX = HULL[:, 0]
HB = (HULL.min(axis=0), HULL.max(axis=0))
def sweep(name):
    hits = {}
    C8 = corners(*HB)
    seen = set()
    for tau, phase, pos, R in poses.get(name, []):
        key0 = tuple(np.round(pos, 2)) + tuple(np.round(R.ravel(), 4))
        if key0 in seen:
            continue
        seen.add(key0)
        W8 = pos + C8 @ R.T
        lo = W8.min(axis=0) - MARGIN; hi = W8.max(axis=0) + MARGIN
        cand = np.where(np.all(WLO <= hi, axis=1) & np.all(WHI >= lo, axis=1))[0]
        for j in cand:
            p, nm, c, Rw, h, shape, wlo, whi, col, vis = world[j]
            if not vis or whi[1] < GROUND_SKIP:
                continue
            A = Rw.T @ R; b = Rw.T @ (pos - c)
            Cw = (corners(-h - MARGIN, h + MARGIN) @ Rw.T) + c
            Cl = (Cw - pos) @ R
            plo, phi = Cl.min(axis=0), Cl.max(axis=0)
            i0, i1 = np.searchsorted(HX, plo[0]), np.searchsorted(HX, phi[0], side="right")
            if i1 <= i0:
                continue
            sub = HULL[i0:i1]
            sm = np.all(sub[:, 1:] >= plo[1:], axis=1) & np.all(sub[:, 1:] <= phi[1:], axis=1)
            if not sm.any():
                continue
            sel = np.arange(i0, i1)[sm]
            Wp = pos + HULL[sel] @ R.T
            m = hit_points(Wp, j, MARGIN)
            if not m.any():
                continue
            k = (p, nm, j)
            e = hits.get(k)
            if e is None:
                e = hits[k] = [tau, tau, set(), phase, np.round(c, 1)]
            e[0] = min(e[0], tau); e[1] = max(e[1], tau); e[2].update(HNAMES[sel][m].tolist())
    return hits
for kind in ("out", "back", "ferry"):
    for slot in (1, 2):
        name = "jet_%s%d" % (kind, slot)
        hits = sweep(name)
        for (p, nm, _j), e in sorted(hits.items(), key=lambda kv: kv[1][0]):
            print("HIT     %-10s t=%6.2f..%6.2f (%s) %s at %s  jet: %s" % (name, e[0], e[1], e[3], "/".join(p.split("/")[2:5]) + "/" + nm, e[4].tolist(), ",".join(sorted(e[2]))[:60]))
        check(name + ": no world part within %.1f stud of the jet hull" % MARGIN, len(hits) == 0, "%d obstacles" % len(hits))

# ------------------------------------------------------------------ walks
COL = np.array([w[8] for w in world])
def floor_under(P):
    """top surface heights of collidable parts under each point (nearest at or below y + 0.75)"""
    out = np.full(len(P), -1e9)
    lo = P.min(axis=0) - 1; hi = P.max(axis=0) + 1
    cand = np.where(COL & (WLO[:, 0] <= hi[0]) & (WHI[:, 0] >= lo[0]) & (WLO[:, 2] <= hi[2]) & (WHI[:, 2] >= lo[2]) & (WLO[:, 1] <= hi[1] + 1) & (WHI[:, 1] >= lo[1] - 3))[0]
    for j in cand:
        p, nm, c, Rw, h, shape = world[j][:6]
        L = (P - c) @ Rw
        if abs(Rw[1, 1]) > 0.999:  # axis-aligned up: top face
            m = (np.abs(L[:, 0]) <= h[0]) & (np.abs(L[:, 2]) <= h[2])
            top = c[1] + h[1]
            ok = m & (top <= P[:, 1] + 0.75)
            out = np.where(ok & (top > out), top, out)
        else:
            # sloped part (ramp / wedge / stair flight): sample its surface under the point by bisection along y
            for k in np.where((np.abs(L[:, 0]) <= h[0] + 1) & (np.abs(L[:, 2]) <= h[2] + 1))[0]:
                ys = np.linspace(P[k, 1] - 3, P[k, 1] + 0.75, 40)
                Q = np.stack([np.full(40, P[k, 0]), ys, np.full(40, P[k, 2])], axis=1)
                ins_ = inside_local((Q - c) @ Rw, h, shape)
                if ins_.any():
                    top = ys[np.where(ins_)[0].max()]
                    if top > out[k]:
                        out[k] = top
    return out
BODY_H = np.array([0.6, 1.4, 2.4, 3.4, 4.4, 5.0])
jet_world = {}
def jet_hull_at(key):
    if key not in jet_world:
        pos, R = parks[key]
        jet_world[key] = (pos, R)
    return jet_world[key]
stair_boxes = []  # (lo, hi) xz boxes where the client-built airstairs stand
total_bad = 0
nwalks = 0
for name, radius, t0, t1, path in walks:
    nwalks += 1
    seg = np.diff(path, axis=0); lens = np.linalg.norm(seg, axis=1); cum = np.concatenate([[0], np.cumsum(lens)])
    L = cum[-1]
    if L < 0.5:
        continue
    s = np.arange(0, L + 1e-6, 0.4)
    s = s[(s >= t0) & (s <= L - t1)]
    if len(s) == 0:
        continue
    idx = np.clip(np.searchsorted(cum, s, side="right") - 1, 0, len(lens) - 1)
    f = np.where(lens[idx] > 1e-9, (s - cum[idx]) / np.maximum(lens[idx], 1e-9), 0)
    P = path[idx] + seg[idx] * f[:, None]
    jetwalk = name.startswith(("pilot", "companion"))
    pm_stairs = name.startswith("pm:") or "stand" in name
    # body clearance
    lo = P.min(axis=0) - radius - 1; hi = P.max(axis=0) + radius + 6
    cand = np.where(COL & np.all(WLO <= hi, axis=1) & np.all(WHI >= lo, axis=1))[0]
    bad = []
    for j in cand:
        p, nm, c, Rw, h, shape, wlo, whi, col, vis = world[j]
        for dy in BODY_H:
            Q = P + np.array([0, dy, 0])
            m = hit_points(Q, j, radius, flat=True)
            if m.any():
                k0 = int(np.where(m)[0][0])
                bad.append("%s at %s (s=%.1f, %s)" % ("/".join(p.split("/")[2:5]) + "/" + nm, np.round(c, 1).tolist(), s[k0], np.round(P[k0], 1).tolist()))
                break
    # floor under the feet (not on the airstairs / inside the jet)
    fl = floor_under(P)
    off = np.abs(fl - P[:, 1]) > 0.75
    if jetwalk:
        off &= P[:, 1] < fl + 0.3  # above the apron = on the jet's own airstair / in the cabin
    if jetwalk or pm_stairs:
        # up the client-built airstair / in the cabin: no world floor expected
        ground = P[:, 1] < GROUND_SKIP + 1.0
        if pm_stairs:
            on_stairs = (P[:, 0] > 204) & (P[:, 0] < 218) & (P[:, 2] > 7668) & (P[:, 2] < 7690) & (P[:, 1] > fl + 0.3)
            ground &= ~on_stairs
        off &= ground
    if off.any():
        k0 = int(np.where(off)[0][0])
        bad.append("no floor under the feet at %s (floor %.2f)" % (np.round(P[k0], 2).tolist(), fl[k0]))
    # jet walks: clear of the parked hull while on the ground
    if jetwalk:
        key = "home" if ("home" in name or name.startswith("pilot")) else ("stand" if "stand" in name else ("pm1" if "pm1" in name else "pm2"))
        pos, R = jet_hull_at(key)
        Wh = pos + hull @ R.T
        ground = P[:, 1] < fl + 0.3  # on the apron (up the airstair the walk enters the door by design)
        for k in np.where(ground)[0]:
            for dy in (0.6, 2.4, 4.4):
                q = P[k] + np.array([0, dy, 0])
                d = np.linalg.norm(Wh - q, axis=1)
                if d.min() < radius:
                    bad.append("jet hull (%s) at %s" % (hull_names[int(np.argmin(d))], np.round(P[k], 1).tolist()))
                    break
            else:
                continue
            break
    for b in bad[:3]:
        print("WALK    %-34s %s" % (name, b))
    total_bad += 1 if bad else 0
check("walks present (pilots, companions, terminal passengers)", nwalks >= 60, nwalks)
check("every walk clear of collidable parts with a floor under the feet", total_bad == 0, "%d walks blocked" % total_bad)
print("guests_jet_clearance: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
