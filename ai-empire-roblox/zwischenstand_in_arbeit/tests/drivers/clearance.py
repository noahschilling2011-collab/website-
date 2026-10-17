#!/usr/bin/env python3
"""drivers package: car clearance along every DrivePlan leg against the REAL geometry (harness dumps).
Input: legs from probe_legs.luau (@@LEG lines), the world dump (district + Business City + airport + Port Meridian)
and HQ dumps (building-local, placed on the legs' plot CFrames). The car = an oriented box along the path heading
(width 7.4, length 15 / limo 21, body band 0.6..5.6 above the path point, pitched on ramps). A hit = the box
intersects a collidable part, or a solid-looking decorative vehicle (Taxi/Car/Bus/Limousine bodies).
Vectorised: every car box is quantised (2 studs, 5 degrees) and tested once (separating axis test in numpy).
Prints "drivers_clearance: N passed, M failed" (one check per leg and geometry set).
usage: clearance.py LEGS.txt WORLD.json [HQ_TIER_DUMP.json ...] [--verbose] [--skip-hq-for-pm]"""
import json, sys, math
import numpy as np

args = [a for a in sys.argv[1:] if not a.startswith('--')]
verbose = '--verbose' in sys.argv
legs = [json.loads(l[6:]) for l in open(args[0]) if l.startswith('@@LEG ')]
PITCH, ROW, SY = 320, 252, 24
WIDTH_FLEET, WIDTH_LIMO, BAND_LO, BAND_HI = 7.0, 7.4, 0.6, 5.6


def plot_cf(i):
    row = -1 if i <= 6 else 1
    x = ((i - 1) % 6 - 2.5) * PITCH
    o = np.array([x, SY, row * ROW]); t = np.array([x, SY, 0.0]); f = (t - o) / np.linalg.norm(t - o)
    up = np.array([0, 1.0, 0]); r = np.cross(f, up); r /= np.linalg.norm(r); u = np.cross(r, f)
    R = np.stack([r, u, -f], axis=1)  # columns: right, up, back (Roblox: LookVector = -Z)
    M = np.eye(4); M[:3, :3] = R; M[:3, 3] = o
    return M


VEH = ('Taxi/', 'Car/', 'Bus/', 'Limousine')


# opened for the car by DriverService (Doors.requestNPC through the driver proxy) - checked in test_service;
# Port Meridian's invisible player barrier at the city edge (transparency 1) where Arrivals Drive enters its east
# tunnel: the limousine garage lies behind it (the tunnel mouth is open, the city traffic drives through it too)
PASSABLE = ('Door_SITE_BARRIER/Leaf',)
INVISIBLE_BARRIERS = ('PortMeridian/BoundaryWall',)


def solid(i):
    if 'size' not in i or 'cframe' not in i:
        return False
    if any(k in i['path'] for k in PASSABLE):
        return False
    if any(k in i['path'] for k in INVISIBLE_BARRIERS) and i.get('transparency') == 1:
        return False
    if i.get('canCollide'):
        return True
    p = i['path']
    return any(v in p for v in VEH) and i['name'] in ('Body', 'Cabin', 'Windows', 'Roof', 'Hood', 'Bonnet', 'Trunk', 'Chassis', 'Cab')


def boxes(path, xform=None):
    d = json.load(open(path))
    P, R, H, N, W = [], [], [], [], []
    for i in d['instances']:
        if not solid(i):
            continue
        cf = i['cframe']
        p = np.array(cf[:3], float); r = np.array(cf[3:12], float).reshape(3, 3); s = np.array(i['size'], float) / 2
        if xform is not None:
            p = xform[:3, :3] @ p + xform[:3, 3]; r = xform[:3, :3] @ r
        P.append(p); R.append(r); H.append(s); N.append(i['path']); W.append(i['class'] == 'WedgePart')
    if xform is not None and d['meta'].get('tier', 1) >= 1:
        # the founder's own car parked in the B1 pick-up bay (largest: the limousine, 19 x 7.4) - not in the dump
        p = np.array([100.0, -16 + 2.5, 2.0]); P.append(xform[:3, :3] @ p + xform[:3, 3]); R.append(xform[:3, :3].copy())
        H.append(np.array([3.7, 2.0, 9.5])); N.append('FounderCarInPickupBay'); W.append(False)
    return np.array(P), np.array(R), np.array(H), N, np.array(W, bool)


def wedge_verts(p, R, h):
    """WedgePart (Roblox): high side at local +Z (back), slope down to the front bottom edge"""
    v = np.array([[sx * h[0], -h[1], -h[2]] for sx in (-1, 1)] + [[sx * h[0], -h[1], h[2]] for sx in (-1, 1)]
                 + [[sx * h[0], h[1], h[2]] for sx in (-1, 1)])
    return p + v @ R.T


def box_verts(c, R, h):
    v = np.array([[sx * h[0], sy * h[1], sz * h[2]] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)])
    return c + v @ R.T


def sat_wedge(c, R, h, p, R2, h2):
    """car box vs wedge (convex prism): separating axes from both face normals and edge cross products"""
    A = box_verts(c, R, h); B = wedge_verts(p, R2, h2)
    slope_dir = R2 @ np.array([0, h2[1], h2[2]]); slope_dir /= np.linalg.norm(slope_dir)
    slope_n = R2 @ np.array([0, h2[2], -h2[1]]); slope_n /= np.linalg.norm(slope_n)
    axes = [R[:, k] for k in range(3)] + [R2[:, k] for k in range(3)] + [slope_n]
    for e1 in [R[:, k] for k in range(3)]:
        for e2 in [R2[:, 0], R2[:, 1], R2[:, 2], slope_dir]:
            v = np.cross(e1, e2); n = np.linalg.norm(v)
            if n > 1e-6:
                axes.append(v / n)
    for ax in axes:
        a = A @ ax; b = B @ ax
        if a.max() < b.min() + 1e-3 or b.max() < a.min() + 1e-3:
            return False
    return True


class Grid:
    def __init__(s, P, R, H, cell=32):
        s.c = cell; s.g = {}
        ext = np.einsum('kij,kj->ki', np.abs(R), H)
        for k in range(len(P)):
            for gx in range(int(math.floor((P[k, 0] - ext[k, 0]) / cell)), int(math.floor((P[k, 0] + ext[k, 0]) / cell)) + 1):
                for gz in range(int(math.floor((P[k, 2] - ext[k, 2]) / cell)), int(math.floor((P[k, 2] + ext[k, 2]) / cell)) + 1):
                    s.g.setdefault((gx, gz), []).append(k)

    def near(s, p, r):
        out = set()
        for gx in range(int(math.floor((p[0] - r) / s.c)), int(math.floor((p[0] + r) / s.c)) + 1):
            for gz in range(int(math.floor((p[2] - r) / s.c)), int(math.floor((p[2] + r) / s.c)) + 1):
                out.update(s.g.get((gx, gz), ()))
        return out


def sat_batch(c1, R1, h1, c2, R2, h2):
    """vectorised OBB/OBB separating axis test; all arrays (n,3)/(n,3,3); True = overlap"""
    n = len(c1)
    T = c2 - c1
    axes = [R1[:, :, k] for k in range(3)] + [R2[:, :, k] for k in range(3)]
    for a in range(3):
        for b in range(3):
            v = np.cross(R1[:, :, a], R2[:, :, b])
            nv = np.linalg.norm(v, axis=1, keepdims=True)
            v = np.where(nv > 1e-6, v / np.maximum(nv, 1e-9), 0.0)
            axes.append(v)
    overlap = np.ones(n, bool)
    for ax in axes:
        ra = sum(h1[:, k] * np.abs(np.einsum('ij,ij->i', R1[:, :, k], ax)) for k in range(3))
        rb = sum(h2[:, k] * np.abs(np.einsum('ij,ij->i', R2[:, :, k], ax)) for k in range(3))
        sep = np.abs(np.einsum('ij,ij->i', T, ax)) > ra + rb - 1e-3
        valid = np.linalg.norm(ax, axis=1) > 0.5
        overlap &= ~(sep & valid)
    return overlap


def carbox(cf, length, width):
    """car body box from a playback pose [x,y,z, look xyz, up xyz] (DrivePlan.poseAtDist)"""
    p = np.array(cf[0:3], float); f = np.array(cf[3:6], float); u = np.array(cf[6:9], float)
    f /= np.linalg.norm(f); u /= np.linalg.norm(u)
    r = np.cross(f, u); r /= np.linalg.norm(r)
    R = np.stack([r, u, -f], axis=1)
    hh = (BAND_HI - BAND_LO) / 2
    h = np.array([width / 2, hh, length / 2]); c = p + u * (BAND_LO + hh)
    return c, R, h


sets = [('world', boxes(args[1]), None)]
hq = args[2:]
plots = sorted(set(l['plot'] for l in legs if l.get('plot')))
for path in hq:
    for plot in plots:
        sets.append((path.split('/')[-1] + '#' + str(plot), boxes(path, plot_cf(plot)), plot))
grids = [(name, b, plot, Grid(b[0], b[1], b[2])) for name, b, plot in sets]

# unique car boxes
key_of = {}
boxes_c, boxes_R, boxes_h = [], [], []
leg_keys = []
for l in legs:
    length = l.get('length') or (21 if l.get('limo') else 15)
    width = l.get('width') or (WIDTH_LIMO if l.get('limo') else WIDTH_FLEET)
    ks = []
    pts = l['cfs']
    for i in range(len(pts)):
        c, R, h = carbox(pts[i], length, width)
        yaw = math.degrees(math.atan2(R[0, 2], R[2, 2]))
        pitch = math.degrees(math.asin(max(-1, min(1, R[1, 2]))))
        k = (round(c[0] / 2), round(c[1]), round(c[2] / 2), round(yaw / 5) % 72, round(pitch / 2), length)
        if k not in key_of:
            key_of[k] = len(boxes_c)
            boxes_c.append(c); boxes_R.append(R); boxes_h.append(h)
        ks.append((key_of[k], i))
    leg_keys.append(ks)
boxes_c = np.array(boxes_c); boxes_R = np.array(boxes_R); boxes_h = np.array(boxes_h)
print(f"legs {len(legs)}, unique car boxes {len(boxes_c)}", flush=True)

hits = {}  # (box index, set name) -> part name
for name, (P, R, H, N, WEDGE), plot, g in grids:
    pi, pj = [], []
    for bi in range(len(boxes_c)):
        for k in g.near(boxes_c[bi], 14):
            pi.append(bi); pj.append(k)
    if not pi:
        continue
    pi = np.array(pi); pj = np.array(pj)
    ov = np.zeros(len(pi), bool)
    CH = 200000
    for s in range(0, len(pi), CH):
        a, b = pi[s:s + CH], pj[s:s + CH]
        ov[s:s + CH] = sat_batch(boxes_c[a], boxes_R[a], boxes_h[a], P[b], R[b], H[b])
    for a, b in zip(pi[ov], pj[ov]):
        a, b = int(a), int(b)
        if WEDGE[b] and not sat_wedge(boxes_c[a], boxes_R[a], boxes_h[a], P[b], R[b], H[b]):
            continue  # only the wedge's bounding box was hit, not the prism
        hits.setdefault((a, name), N[b])
    print(f"  {name}: {len(pi)} pairs, {int(ov.sum())} overlaps", flush=True)

passed = failed = 0
for l, ks in zip(legs, leg_keys):
    for name, b, plot, g in grids:
        if plot is not None and l.get('plot') != plot:
            continue
        found = {}
        for bi, i in ks:
            n = hits.get((bi, name))
            if n and n not in found:
                found[n] = (i, tuple(round(v, 1) for v in l['cfs'][i][:3]))
        if found:
            failed += 1
            items = list(found.items())[:40 if verbose else 4]
            print(f"FAIL {l['key']} vs {name}: {len(found)} parts, e.g. " + "; ".join(f"{n} @ {v}" for n, v in items))
        else:
            passed += 1
print(f"drivers_clearance: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
