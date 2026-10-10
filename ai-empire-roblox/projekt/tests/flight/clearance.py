#!/usr/bin/env python3
"""Flight package: clearance sweep of the shuttle, the ambient runway traffic and the VIP helicopter against the
built world (dump from tests/flight/clearance_dump.sh).

The aircraft hull is the real AircraftModel (FlightPlan.CONFIG kind/scale, full LOD) and the helicopter the real
buildHelicopter model, both dumped at the origin. Every solid of the hull above the landing gear (wings,
winglets, flap fairings, engines, pylons, stabilisers, fin, fuselage, nose, tail cone, belly fairing, cockpit) is
sampled with interior points (0.35-stud grid; exact shapes: box, Roblox wedge, cylinder, ball, sphere-mesh
ellipsoid) and tested at every low pose (0.25 s steps, below 150 studs above the ground) against every visible
world part (transparency < 0.99, exact shapes: box, wedge, cylinder, ball; meshes as boxes) inflated by MARGIN.
Excluded: the airport package's parked aircraft on the shuttle stand (hidden locally by ShuttleController),
parts below 0.5 stud above the ground (markings) and the helicopter's skids (they stand on the pads).
Obstacles that wait for another package (design/requests/flight.md) are printed as PENDING and are not counted
as failures; everything else is.

usage: python3 tests/flight/clearance.py [out/flight_clearance] [--margin 0.5] [--verbose]
"""
import json, sys, collections, os
import numpy as np

ARGS = [a for i, a in enumerate(sys.argv[1:], 1) if not a.startswith("--") and sys.argv[i - 1] != "--margin"]
OUT = ARGS[0] if ARGS else "out/flight_clearance"
MARGIN = 0.5
if "--margin" in sys.argv:
    MARGIN = float(sys.argv[sys.argv.index("--margin") + 1])
VERBOSE = "--verbose" in sys.argv
STEP = 0.35
GROUND_SKIP = 24.75  # world parts whose top is below this are ground / markings
HULL_PARTS = {"Wing", "Winglet", "FlapFairing", "Nacelle", "NacelleAft", "EngineLip", "Pylon", "Stabilizer", "Fin", "DorsalFin",
              "Fuselage", "Nose", "TailCone", "BellyFairing", "CockpitSkin", "Windshield", "CockpitSideWindow", "ExhaustPlug", "EngineCore"}
HELI_SKIP = {"HeliSkid", "HeliSkidTip", "HeliStrut", "HeliBlade", "HeliTailBlade", "HeliHub", "HeliTailHub", "HeliNavLight"}
# (path fragment, part names, request) - other packages' geometry, tracked in design/requests/flight.md
PENDING = [
    ("/Airport/Apron/", {"FloodMast", "FloodFrame", "FloodHead"}, "airport: flight.md #6 (flood masts in the wingtip corridor)"),
    ("/Airport/Apron/", {"HoldSign", "HoldSignPost"}, "airport: flight.md #6 (hold-short sign next to the connector)"),
]

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
byid = {x["id"]: x for x in ins}
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
    """Mask of local points L (n x 3) inside the solid with half size h."""
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

def shrink(h, shape, d):
    return np.maximum(h - d, 1e-3)

def samples(prefix, keep=None, skip=None):
    """Points on the hull: grid points inside each solid that lie within STEP of its boundary (a shell), minus
    the points that are deep inside another solid of the same hull (the overlapping lofts)."""
    solids = []
    for x in ins:
        if not x["path"].startswith(prefix) or "size" not in x or (x.get("transparency") or 0) >= 0.99:
            continue
        if keep is not None and x["name"] not in keep:
            continue
        if skip is not None and x["name"] in skip:
            continue
        c, R, h = frame(x)
        solids.append((x["name"], c, R, h, shape_of(x)))
    shells = []
    for name, c, R, h, shape in solids:
        g = [np.linspace(-hh, hh, max(2, int(2 * hh / STEP) + 1)) for hh in h]
        L = np.array(np.meshgrid(*g, indexing="ij")).reshape(3, -1).T
        L = L[inside_local(L, h, shape)]
        inner = inside_local(L, shrink(h, shape, STEP * 1.01), shape) if np.all(h > STEP * 1.5) else np.zeros(len(L), bool)
        L = L[~inner]
        if len(L) == 0:
            L = np.zeros((1, 3))
        W = c + L @ R.T
        shells.append((name, W, W.min(axis=0), W.max(axis=0)))
    pts, names = [], []
    for i, (name, W, lo, hi) in enumerate(shells):
        keepm = np.ones(len(W), bool)
        for j, (n2, c2, R2, h2, sh2) in enumerate(solids):
            if j == i:
                continue
            e2 = np.abs(R2) @ h2
            if np.any(c2 - e2 > hi) or np.any(c2 + e2 < lo):
                continue
            if not np.all(h2 > STEP * 1.5):
                continue
            L2 = (W - c2) @ R2
            keepm &= ~inside_local(L2, shrink(h2, sh2, STEP), sh2)
        pts.append(W[keepm]); names += [name] * int(keepm.sum())
    return np.concatenate(pts), np.array(names)

hull, hull_names = samples("World/FlightShowcase/ShuttleHull/", keep=HULL_PARTS)
heli, heli_names = samples("World/FlightShowcase/HeliHull/", skip=HELI_SKIP)
# the main rotor sweeps a disc (radius = blade tip) around the hub
hub = None
for x in ins:
    if x["path"].startswith("World/FlightShowcase/HeliHull/") and x["name"] == "HeliHub":
        hub = np.array(x["cframe"][:3], float)
tipR = 0.0
for x in ins:
    if x["path"].startswith("World/FlightShowcase/HeliHull/") and x["name"] == "HeliBlade" and hub is not None:
        c, R, h = frame(x)
        tipR = max(tipR, np.linalg.norm((c - hub)[[0, 2]]) + h[0])
if hub is not None and tipR > 0:
    rr, aa = np.meshgrid(np.arange(0.5, tipR, STEP * 2), np.linspace(0, 2 * np.pi, 160, endpoint=False))
    disc = np.stack([hub[0] + (rr * np.cos(aa)).ravel(), np.full(rr.size, hub[1]), hub[2] + (rr * np.sin(aa)).ravel()], axis=1)
    heli = np.concatenate([heli, disc]); heli_names = np.concatenate([heli_names, np.array(["RotorDisc"] * len(disc))])
check("hull samples present", len(hull) > 20000, len(hull))
check("helicopter samples present (rotor disc included)", len(heli) > 2000 and tipR > 12, (len(heli), round(tipR, 1)))

# world obstacles
excluded_roots = set()
for x in ins:
    if x["class"] == "Model" and x["name"] == "ParkedAircraft" and (x.get("attrs") or {}).get("Stand") == 1 and "/Airport/" in x["path"]:
        excluded_roots.add(x["path"] + "/")
# the shuttle stand's pushback tug is animated with the aircraft by ShuttleController (FlightPlan.tugFrame)
stand_x = None
for x in ins:
    if x["class"] == "Model" and x["name"] == "ParkedAircraft" and (x.get("attrs") or {}).get("Stand") == 1 and "/Airport/" in x["path"]:
        stand_x = (x.get("pivot") or [None])[0]
tug_parts = set()
if stand_x is not None:
    for x in ins:
        if "/GroundVehicles/Pushback/" in x["path"] and "cframe" in x and abs(x["cframe"][0] - stand_x) < 6:
            tug_parts.add(x["id"])
# retracted jet bridge frames (BRIDGE lines: original position -> frame at u = 1)
bridge_alt = {}
for line in open(os.path.join(OUT, "log.txt")):
    f = line.split()
    if len(f) >= 17 and f[0] == "[print]" and f[1] == "BRIDGE":
        key = tuple(round(float(a), 2) for a in f[2:5])
        v = [float(a) for a in f[5:17]]
        bridge_alt[key] = (np.array(v[:3]), np.array(v[3:12]).reshape(3, 3))
def entry(p, name, c, R, h, shape):
    ext = np.abs(R) @ h
    return (p, name, c, R, h, shape, c - ext, c + ext)
docked, retracted = [], []
bridge_hits = 0
for x in ins:
    p = x["path"]
    if "size" not in x or "cframe" not in x or p.startswith("World/FlightShowcase/"):
        continue
    if (x.get("transparency") or 0) >= 0.99 or x["id"] in tug_parts:
        continue
    if any(p.startswith(r) for r in excluded_roots):
        continue
    c, R, h = frame(x)
    ext = np.abs(R) @ h
    if c[1] + ext[1] < GROUND_SKIP:
        continue
    sh = shape_of(x)
    if "/JetBridge_A1/" in p:
        alt = None
        for key, fr in bridge_alt.items():
            if max(abs(key[0] - c[0]), abs(key[1] - c[1]), abs(key[2] - c[2])) < 0.02:
                alt = fr
        if alt is not None:
            bridge_hits += 1
            retracted.append(entry(p, x["name"], alt[0], alt[1], h, sh))
            # docked: the bellows seal against the fuselage by design and the cab's open side stands 0.6 studs
            # off the door (AirportBuilder.bridgePlan), so the docked bridge is checked with a 0.25 margin
            if x["name"] != "Bellows":
                docked.append(entry(p, x["name"], c, R, np.maximum(h - (MARGIN - 0.25), 1e-3), sh))
            continue
    docked.append(entry(p, x["name"], c, R, h, sh))
    retracted.append(entry(p, x["name"], c, R, h, sh))
check("world built (district + city)", len(docked) > 4000, len(docked))
check("the shuttle stand's parked aircraft found and excluded", len(excluded_roots) == 1, len(excluded_roots))
check("the shuttle stand's pushback tug found (animated with the aircraft)", len(tug_parts) >= 4, len(tug_parts))
check("the shuttle stand's jet bridge: retracted frames for every part", bridge_hits >= 30 and bridge_hits == len(bridge_alt), (bridge_hits, len(bridge_alt)))
WORLDS = {}
for nm_, lst in (("docked", docked), ("retracted", retracted)):
    WORLDS[nm_] = (lst, np.array([w[6] for w in lst]), np.array([w[7] for w in lst]))
PARKED = {"boarding", "doors", "deboarding"}

# poses
poses = collections.defaultdict(list)
for line in open(os.path.join(OUT, "log.txt")):
    f = line.split()
    if len(f) < 17 or f[0] != "[print]" or f[1] != "POSE":
        continue
    v = [float(a) for a in f[5:17]]
    poses[f[2]].append((float(f[3]), f[4], np.array(v[:3]), np.array(v[3:12]).reshape(3, 3)))
for what, need in (("shuttle_out", 300), ("shuttle_back", 250), ("ambient_arrival", 60), ("ambient_departure", 60), ("heli_to_hotel", 60), ("heli_to_airport", 60)):
    check(what + ": low poses present", len(poses.get(what, [])) >= need, len(poses.get(what, [])))

def local_aabb(P):
    return P.min(axis=0), P.max(axis=0)
HULL_BOX = local_aabb(hull); HELI_BOX = local_aabb(heli)

def corners(lo, hi):
    return np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])

def pending_of(path, name):
    for frag, names, req in PENDING:
        if frag in path and name in names:
            return req
    return None

def sweep(what, P, names, box):
    order = np.argsort(P[:, 0]); P = P[order]; names = names[order]; PX = P[:, 0]
    hits = {}
    C8 = corners(*box)
    seen = set()
    for tau, phase, pos, R in poses.get(what, []):
        key0 = tuple(np.round(pos, 2)) + tuple(np.round(R.ravel(), 4))
        if key0 in seen:
            continue  # parked / holding: the same pose again
        seen.add(key0)
        W8 = pos + C8 @ R.T
        lo = W8.min(axis=0) - MARGIN; hi = W8.max(axis=0) + MARGIN
        world, WLO, WHI = WORLDS["docked" if (phase in PARKED and what.startswith("shuttle")) else "retracted"]
        cand = np.where(np.all(WLO <= hi, axis=1) & np.all(WHI >= lo, axis=1))[0]
        for j in cand:
            p, nm, c, Rw, h, shape, wlo, whi = world[j]
            # aircraft-local point q -> world pos + R q -> part-local L = (Rw^T R) q + Rw^T (pos - c)
            A = Rw.T @ R; b = Rw.T @ (pos - c)
            Cw = (corners(-h - MARGIN, h + MARGIN) @ Rw.T) + c  # the inflated part's corners (world)
            Cl = (Cw - pos) @ R
            plo, phi = Cl.min(axis=0), Cl.max(axis=0)
            i0, i1 = np.searchsorted(PX, plo[0]), np.searchsorted(PX, phi[0], side="right")
            if i1 <= i0:
                continue
            sub = P[i0:i1]
            sm = np.all(sub[:, 1:] >= plo[1:], axis=1) & np.all(sub[:, 1:] <= phi[1:], axis=1)
            if not sm.any():
                continue
            sel = np.arange(i0, i1)[sm]
            L = P[sel] @ A.T + b
            m = inside_local(L, h + MARGIN, "box")
            if shape == "wedge":
                m &= (L[:, 1] * h[2] - L[:, 2] * h[1]) / np.hypot(h[1], h[2]) <= MARGIN
            elif shape == "cylinder":
                r = min(h[1], h[2]) + MARGIN
                m &= L[:, 1] ** 2 + L[:, 2] ** 2 <= r * r
            elif shape == "ball":
                r = h.min() + MARGIN
                m &= (L ** 2).sum(axis=1) <= r * r
            if not m.any():
                continue
            depth = float((h + MARGIN - np.abs(L[m])).min(axis=1).max())
            key = (p, nm, j)
            e = hits.get(key)
            if e is None:
                e = hits[key] = [tau, tau, set(), 0.0, phase, np.round(c, 1)]
            e[0] = min(e[0], tau); e[1] = max(e[1], tau); e[2].update(names[sel][m].tolist()); e[3] = max(e[3], depth)
    return hits

total_pending = 0
for what in ("shuttle_out", "shuttle_back", "ambient_arrival", "ambient_departure", "heli_to_hotel", "heli_to_airport"):
    P, nm, box = (heli, heli_names, HELI_BOX) if what.startswith("heli") else (hull, hull_names, HULL_BOX)
    hits = sweep(what, P, nm, box)
    bad = []
    for (p, name, _j), e in sorted(hits.items(), key=lambda kv: kv[1][0]):
        req = pending_of(p, name)
        txt = "%-18s t=%6.2f..%6.2f (%s) depth<=%.2f (margin %.1f) %s at %s  aircraft: %s" % (
            what, e[0], e[1], e[4], e[3], MARGIN, "/".join(p.split("/")[2:5]) + "/" + name, e[5].tolist(), ",".join(sorted(e[2]))[:70])
        if req:
            total_pending += 1
            print("PENDING " + txt + "  -> " + req)
        else:
            bad.append(txt)
    for t in bad:
        print("HIT     " + t)
    check(what + ": no world part within %.1f stud of the hull" % MARGIN, len(bad) == 0, "%d obstacles" % len(bad))
print("pending obstacles (other packages, requested): %d" % total_pending)
print("flight_clearance: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
