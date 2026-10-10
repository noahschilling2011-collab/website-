#!/usr/bin/env python3
"""Metro package: walkability of Port Meridian's arrival area in the world dump (agents/metro/world_dump.sh).

usage: reach.py out/metro/dump/world_dump.json [--png out.png]
1-stud grid over the airport district + arrival plaza + Arrivals Drive (x -170..360, z 7600..7800) and, as a
second area, the spire plaza / waterfront (x -120..120, z 8500..8700). A cell is standable when a collidable
surface top lies within [G-0.5, G+1.7] under it and no collidable part occupies the body band (top+1.6 ..
top+5) within the agent radius 1.3 (steps <= 1.6 between neighbours). Flood fill from the arrival point
(CityPlan.ABROAD.arrival). Targets: both "Fly home" check-in prompts, the GPS kiosks, every Seat of the
business lounge (front 2.5 studs; desk chairs any side), the lounge door, the terminal exits, the VIP limo stand, the airport helipad
(pad + gate), the taxi rank and the spire entrance. Exit code 1 when a target is unreachable.
"""
import json, sys, math
import numpy as np

D = json.load(open(sys.argv[1]))
png = sys.argv[sys.argv.index("--png") + 1] if "--png" in sys.argv else None
inst = D["instances"]
by_id = {i["id"]: i for i in inst}
G = 24.0
for i in inst:
    if i["name"] == "MeridianGround": G = i["cframe"][1] + i["size"][1] / 2; break
parts = [i for i in inst if "size" in i and i["class"] != "Attachment" and i["path"].startswith("World/WorldCity/PortMeridian")]

def corners(p):
    c = np.array(p["cframe"][:3]); R = np.array(p["cframe"][3:12]).reshape(3, 3); s = np.array(p["size"]) / 2
    return np.array([c + R @ (s * np.array([a, b, d])) for a in (-1, 1) for b in (-1, 1) for d in (-1, 1)])

def solid(p):
    if not p.get("canCollide", True): return False
    if p.get("class") == "Seat": return True
    return True

def area(x1, x2, z1, z2, start, targets, name):
    xs = np.arange(x1 + .5, x2, 1.0); zs = np.arange(z1 + .5, z2, 1.0)
    nx, nz = len(xs), len(zs)
    top = np.full((nz, nx), -1e9)
    pool = []
    for p in parts:
        if not solid(p): continue
        cs = corners(p); mn, mx = cs.min(0), cs.max(0)
        if mx[0] < x1 - 3 or mn[0] > x2 + 3 or mx[2] < z1 - 3 or mn[2] > z2 + 3: continue
        pool.append((p, mn, mx))
    # surfaces (axis-aligned bounding boxes; the area has no rotated walkable parts)
    for p, mn, mx in pool:
        if not (G - 0.5 <= mx[1] <= G + 1.7): continue
        i0, i1 = np.searchsorted(xs, mn[0]), np.searchsorted(xs, mx[0]); j0, j1 = np.searchsorted(zs, mn[2]), np.searchsorted(zs, mx[2])
        if i1 > i0 and j1 > j0: top[j0:j1, i0:i1] = np.maximum(top[j0:j1, i0:i1], mx[1])
    ok = top > -1e8
    # body band blockers (dilated by the agent radius)
    block = np.zeros((nz, nx), dtype=bool)
    rad = 1.3
    for p, mn, mx in pool:
        if mx[1] <= G + 1.7: continue  # a surface (handled above) or a low step
        if mn[1] >= G + 7.5: continue  # overhead (canopies, signs)
        i0, i1 = np.searchsorted(xs, mn[0] - rad), np.searchsorted(xs, mx[0] + rad); j0, j1 = np.searchsorted(zs, mn[2] - rad), np.searchsorted(zs, mx[2] + rad)
        if i1 > i0 and j1 > j0:
            # only if it intersects the body band above the local surface
            sub = top[j0:j1, i0:i1]
            hit = (mn[1] < sub + 5.0) & (mx[1] > sub + 1.6)
            block[j0:j1, i0:i1] |= hit | (sub < -1e8)
    stand = ok & ~block
    # flood fill
    si, sj = int(np.searchsorted(xs, start[0])), int(np.searchsorted(zs, start[1]))
    seen = np.zeros_like(stand)
    if not stand[sj, si]:
        # nearest standable cell
        jj, ii = np.nonzero(stand); k = np.argmin((ii - si) ** 2 + (jj - sj) ** 2); si, sj = ii[k], jj[k]
    stack = [(sj, si)]; seen[sj, si] = True
    while stack:
        j, i = stack.pop()
        for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            a, b = j + dj, i + di
            if 0 <= a < nz and 0 <= b < nx and stand[a, b] and not seen[a, b] and abs(top[a, b] - top[j, i]) <= 1.6:
                seen[a, b] = True; stack.append((a, b))
    fails = []
    for label, (tx, tz, r) in targets:
        i0, i1 = np.searchsorted(xs, tx - r), np.searchsorted(xs, tx + r); j0, j1 = np.searchsorted(zs, tz - r), np.searchsorted(zs, tz + r)
        if not seen[j0:j1, i0:i1].any(): fails.append(label)
    print(f"{name}: {int(seen.sum())} reachable cells of {int(stand.sum())} standable; targets {len(targets) - len(fails)}/{len(targets)} reachable" + (" -- UNREACHABLE: " + ", ".join(fails) if fails else ""))
    if png:
        import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
        img = np.zeros((nz, nx, 3)); img[stand] = (.85, .55, .2); img[seen] = (.3, .8, .3); img[~ok] = (.2, .2, .2)
        fig, ax = plt.subplots(figsize=(14, 14 * nz / nx + .5)); ax.imshow(img, extent=(x1, x2, z2, z1))
        for label, (tx, tz, r) in targets: ax.plot(tx, tz, "o", color="red" if label in fails else "blue", ms=4)
        ax.set_title(name); fig.savefig(png.replace(".png", f"_{name}.png"), bbox_inches="tight"); plt.close(fig)
    return fails

def find(name=None, cls=None, attr=None):
    out = []
    for i in inst:
        if not i["path"].startswith("World/WorldCity/PortMeridian"): continue
        if name and i["name"] != name: continue
        if cls and i["class"] != cls: continue
        if attr and (i.get("attrs") or {}).get(attr[0]) != attr[1]: continue
        out.append(i)
    return out

targets = []
for q in find(cls="ProximityPrompt"):
    par = by_id[q["parent"]]
    if par["cframe"][2] < 7800:
        targets.append((f"prompt {q.get('actionText')}", (par["cframe"][0], par["cframe"][2], q.get("maxActivationDistance", 10) - 1)))
for s in find(cls="Seat"):
    if "BusinessLounge" in s["path"]:
        # sofas / armchairs from the front (2.5 studs), desk chairs from any side (the desk is in front)
        c = s["cframe"]; look = (-c[5], -c[11])
        if s["name"] == "WorkChair": targets.append((f"lounge {s['name']}", (c[0], c[2], 3.2)))
        else: targets.append((f"lounge {s['name']}", (c[0] + look[0] * 2.5, c[2] + look[1] * 2.5, 1.8)))
for x in (-80, 0, 80): targets.append((f"exit {x}", (x, 7695, 2)))
st = find(name="VipLimoStand", cls="Part")
if st: targets.append(("VipLimoStand", (st[0]["cframe"][0], st[0]["cframe"][2], 3)))
hp = [h for h in find(name="Helipad") if (h.get("attrs") or {}).get("Purpose") == "VIPAirport"]
if hp: targets.append(("airport helipad", (hp[0]["cframe"][0], hp[0]["cframe"][2], 4)))
targets.append(("lounge door", (-100, 7650, 2))); targets.append(("taxi rank", (-150, 7762, 3)))
# apron (flight request #7): out through the ApronDoor to stand 1's airstair foot; heliport gate and VIP canopy
ad = find(name="ApronDoor")
if ad: targets.append(("apron door (outside)", (ad[0]["cframe"][0] + 3, ad[0]["cframe"][2], 2)))
ss = find(name="ShuttleStand")
if ss:
    c = ss[0]["cframe"]; look = (-c[5], -c[11]); right = (c[3], c[9])
    door = (c[0] + look[0] * 41.3 - right[0] * 6.24, c[2] + look[1] * 41.3 - right[1] * 6.24)
    targets.append(("stand 1 airstair foot", (door[0], door[1] + 20, 3)))
if hp:
    targets.append(("heliport gate", (hp[0]["cframe"][0] - 28, hp[0]["cframe"][2] + 36, 2)))
    targets.append(("VIP terminal canopy", (hp[0]["cframe"][0] + 42, hp[0]["cframe"][2] + 14, 3)))
arr = (0, 7655)
f1 = area(-170, 700, 7590, 7800, arr, targets, "arrival")
t2 = [("spire entrance", (0, 8584, 3)), ("kiosk", (24, 8592, 4)), ("promenade", (0, 8650, 3)), ("quay", (300, 8690, 3))]
f2 = area(-120, 360, 8500, 8700, (0, 8620), t2, "waterfront")
sys.exit(1 if f1 or f2 else 0)
