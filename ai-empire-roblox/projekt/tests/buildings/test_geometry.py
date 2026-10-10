#!/usr/bin/env python3
"""Package "buildings" - geometry of the garage stage (plan tier 0) and the guest house (tier 2) on the
real generated buildings (private dumps in tests/buildings/out/, built from tests/buildings/gen_build):
  * frame consistency: tier 0 and tier 2 built at a plot frame and at a rotated frame map back exactly
  * holes (tests/lead/holes.py): 0 sq studs on every walkable level of tier 0 and tier 2
  * check_geometry: nothing outside the site box; every workstation, seat, door model and prompt of the
    garage stage reachable; every guest-house workstation, seat, door and prompt reachable (tier 2)
  * budgets: garage stage < 2000 building parts and <= 16 lights; guest house lights <= 16
  * guest-house job hops (routes_hotel.luau): the straight in-room hops of posts 13/14 are walkable
    (probes along each segment, agent radius 1.0 like tests/life/test_routes.py)
  * NEGATIVE checks (must be detected): a hop straight through the reception desk; the garage floor
    removed from the tier-0 dump -> holes.
Usage: python3 tests/buildings/mkharness.py && python3 tests/buildings/test_geometry.py
"""
import json, os, re, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
LUAU = os.path.join(ROOT, "tools", "luau")
H = os.path.join(ROOT, "harness")
OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)
GEN = "../tests/buildings/gen_build"  # relative to harness/ (build_dump.luau --gen)
passed = failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print(f"FAIL  {name}" + (f"  -- {detail}" if detail else ""))


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    return r.returncode, r.stdout + r.stderr


def dump(tier, suffix="", extra=()):
    path = os.path.join(OUT, f"dump_tier{tier}{suffix}.json")
    log = os.path.join(OUT, f"log_tier{tier}{suffix}.txt")
    p1 = subprocess.Popen([LUAU, os.path.join(H, "build_dump.luau"), "-a", "--tier", str(tier), "--quiet", "--gen", GEN, *extra],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=ROOT)
    p2 = subprocess.run([sys.executable, os.path.join(H, "split_dump.py"), path, log], stdin=p1.stdout, capture_output=True, text=True, cwd=ROOT)
    p1.wait()
    ok = p1.returncode == 0 and p2.returncode == 0 and os.path.exists(path)
    check(f"tier {tier}{suffix} builds", ok, open(log).read()[-400:] if os.path.exists(log) else p2.stderr[-400:])
    return path if ok else None


def unreachable(report, categories):
    """{category: [path lines]} from a check_geometry report."""
    out, cat = {}, None
    for line in report.splitlines():
        m = re.match(r"UNREACHABLE (.+?) \(\d+\):", line)
        if m:
            cat = m.group(1) if m.group(1) in categories else None
            continue
        if cat and line.startswith("   "):
            out.setdefault(cat, []).append(line.strip())
        elif not line.startswith("   "):
            cat = None
    return out


HOTEL_PATH = re.compile(r"/(H[01]_[A-Z0-9_]+)|Door_H[01]_|Facade_Hotel|GuestHouse|HotelRoof")
TARGETS = ("workstations", "seats", "door models (both sides)", "doors (both sides)", "proximity prompts", "navigation nodes")

dumps = {}
for tier in (0, 2):
    d = dump(tier)
    if not d:
        continue
    dumps[tier] = d
    for suffix, extra in (("_plot", ("--plot",)), ("_rot", ("--cf", "-37.5,11,90,37"))):
        o = dump(tier, suffix, extra)
        if o:
            rc, txt = run([sys.executable, os.path.join(H, "compare_dumps.py"), d, o])
            check(f"tier {tier} frame consistency ({suffix[1:]})", rc == 0 and "frame consistency: OK" in txt, txt[-300:])
    rc, txt = run([sys.executable, os.path.join(ROOT, "tests", "lead", "holes.py"), d])
    check(f"tier {tier}: 0 holes", rc == 0 and "TOTAL hole area 0.0 sq studs" in txt, txt[-500:])
    rc, rep = run([sys.executable, os.path.join(H, "check_geometry.py"), d, "--no-images", "--verbose"])
    check(f"tier {tier} check_geometry ran", "== SUMMARY" in rep, rep[-300:])
    m = re.search(r"parts outside allowed box: (\d+)", rep)
    check(f"tier {tier}: no part outside the site box", m is not None and m.group(1) == "0", m and m.group(1))
    bad = unreachable(rep, TARGETS)
    if tier == 0:
        for cat in TARGETS:
            check(f"tier 0: every {cat} target reachable", not bad.get(cat), (bad.get(cat) or [""])[0])
        for cat in ("workstations", "door models (both sides)", "proximity prompts"):
            m = re.search(re.escape(cat) + r": (\d+)/(\d+) reachable", rep)
            check(f"tier 0: {cat} counted", m is not None and int(m.group(2)) > 0, cat)
    else:
        for cat in TARGETS:
            hotel = [p for p in bad.get(cat, []) if HOTEL_PATH.search(p)]
            check(f"tier {tier}: every guest-house {cat} target reachable", not hotel, hotel[0] if hotel else "")
    D = json.load(open(d))
    inst = D["instances"]
    lights = [i for i in inst if i["class"] in ("PointLight", "SpotLight", "SurfaceLight")]
    if tier == 0:
        rig = re.compile(r"/(Employees|OperationsEmployees|Assistant|Visitors)/")
        parts = [i for i in inst if "size" in i and not rig.search(i["path"])]
        print(f"tier 0 (garage stage): {len(parts)} building parts, {len(lights)} lights, {len(inst)} instances")
        own = [i for i in lights if re.search(r"/Rooms/G0_|Facade_Garage|GarageForecourt|ConstructionSite|GarageRoof", i["path"])]
        print(f"tier 0: {len(own)} lights in the garage, its forecourt and the construction site")
        check("tier 0: garage stage < 2000 building parts", len(parts) < 2000, len(parts))
        check("tier 0: garage + construction site <= 12 lights", len(own) <= 12, len(own))
        check("tier 0: whole site <= 40 lights", len(lights) <= 40, len(lights))
    else:
        hl = [i for i in lights if HOTEL_PATH.search(i["path"])]
        print(f"tier {tier}: {len(lights)} lights in the building, {len(hl)} in the guest house")
        check(f"tier {tier}: guest house <= 16 lights", len(hl) <= 16, len(hl))

# guest-house job hops: probes along each straight in-room segment must be standable and connected
def probe(dump_path, segs, step=1.0):
    D = json.load(open(dump_path))
    inst = D["instances"]
    office_id = inst[0]["id"]
    next_id = max(x["id"] for x in inst) + 1
    labels = {}
    for si, (label, pa, pb) in enumerate(segs):
        dx, dy, dz = pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2]
        n = max(1, int((dx * dx + dz * dz) ** 0.5 / step))
        for k in range(n + 1):
            t = k / n
            p = [pa[0] + dx * t, pa[1] + dy * t, pa[2] + dz * t]
            name = f"HopProbe_{label}_{si}_{k}"
            labels[name] = (label, si)
            inst.append({"id": next_id, "parent": office_id, "path": f"Office/{name}", "parentPath": "Office", "class": "Model", "name": name,
                         "attrs": {"InteractionPosition": {"Vector3": p}}})
            next_id += 1
    with tempfile.TemporaryDirectory() as tmp:
        synth = os.path.join(tmp, "probe.json")
        json.dump(D, open(synth, "w"))
        rc, rep = run([sys.executable, os.path.join(H, "check_geometry.py"), synth, "--radius", "1.0", "--no-images", "--verbose"])
    blocked = set()
    for line in unreachable(rep, ("workstations",)).get("workstations", []):
        m = re.search(r"Office/(HopProbe_[^ ]+) at", line)
        if m:
            blocked.add(labels[m.group(1)])
    return blocked, "== SUMMARY" in rep


sys.path.insert(0, H)
import numpy as np
from dumplib import Dump, vertical_line_hits


def corridor(dump_path, segs, r=1.0, step=0.25):
    """Strict hop check: a body of radius r walking the straight segment touches no collidable part
    (doors and rigs excluded) in the band floor+1.6..floor+5 (centre line: floor+0.3..floor+5, i.e.
    nothing to stumble over). Floor = point height - 2.8 (job points are root heights). Returns
    {segment index: first blocking part path}."""
    D = Dump(dump_path)
    door = np.array(["/Doors/" in D.inst[int(k)]["path"] for k in D.pidx])
    sel = np.where(D.collide & ~D.character & ~door & (np.array(D.group) == "Default"))[0]
    lo, hi = D.aabb(sel)
    ang = np.linspace(0, 2 * np.pi, 9)[:-1]
    out = {}
    for si, (_, pa, pb) in enumerate(segs):
        a, b = np.array(pa), np.array(pb)
        n = max(1, int(np.hypot(b[0] - a[0], b[2] - a[2]) / step))
        pts = [a + (b - a) * (k / n) for k in range(n + 1)]
        yf = min(a[1], b[1]) - 2.8
        near = (hi[:, 0] >= min(a[0], b[0]) - r - 0.1) & (lo[:, 0] <= max(a[0], b[0]) + r + 0.1) & \
               (hi[:, 2] >= min(a[2], b[2]) - r - 0.1) & (lo[:, 2] <= max(a[2], b[2]) + r + 0.1) & \
               (hi[:, 1] >= yf + 0.3) & (lo[:, 1] <= yf + 5.0)
        xs = np.concatenate([[p[0] for p in pts]] + [[p[0] + r * np.cos(t) for p in pts] for t in ang])
        zs = np.concatenate([[p[2] for p in pts]] + [[p[2] + r * np.sin(t) for p in pts] for t in ang])
        centre = np.zeros(len(xs), dtype=bool)
        centre[: len(pts)] = True
        band_lo = np.where(centre, yf + 0.3, yf + 1.6)
        for j in sel[near]:
            hit, t0, t1 = vertical_line_hits(D.P[j], D.R[j], D.S[j], D.shape[j], xs, zs)
            if np.any(hit & (t1 >= band_lo + 0.05) & (t0 <= yf + 5.0)):
                out[si] = D.inst[int(D.pidx[j])]["path"]
                break
    return out


if 2 in dumps:
    rc, txt = run([LUAU, os.path.join(HERE, "routes_hotel.luau"), "-a", "2"])
    m = re.search(r"buildings routes \(plan\): (\d+) passed, (\d+) failed", txt)
    check("routes_hotel.luau ran", m is not None, txt[-400:])
    if m:
        passed += int(m.group(1))
        failed += int(m.group(2))
        for line in txt.splitlines():
            if line.startswith("FAIL"):
                print("routes: " + line)
    segs = []
    for line in txt.splitlines():
        if line.startswith("@@SEG "):
            _, label, pa, pb = line.split(" ")
            segs.append((label, [float(x) for x in pa.split(",")], [float(x) for x in pb.split(",")]))
    check("guest-house posts have in-room hops", len(segs) >= 4, len(segs))
    blocked, ran = probe(dumps[2], segs)
    check("hop probe ran", ran)
    for label, si in sorted(blocked):
        a, b = segs[si][1], segs[si][2]
        check(f"hop walkable: {label} segment {si}", False, f"{a} -> {b}")
    passed += len(segs) - len(blocked)
    print(f"tier 2: {len(segs)} guest-house hop segments, {len(blocked)} blocked")
    strict = corridor(dumps[2], segs)
    for si, path in sorted(strict.items()):
        check(f"hop clear for a body of radius 1.0: {segs[si][0]} segment {si}", False, f"{segs[si][1]} -> {segs[si][2]} touches {path}")
    passed += len(segs) - len(strict)
    # NEGATIVE: straight from behind the reception desk through its middle to the lobby
    through = [("NEGATIVE_ThroughDesk", [-113.9, 2.9, 100.5], [-106.0, 2.9, 100.5])]
    nb, ran = probe(dumps[2], through)
    check("NEGATIVE: probe detects a hop through the reception desk", ran and len(nb) == 1, nb)
    ns = corridor(dumps[2], through)
    check("NEGATIVE: strict check detects a hop through the reception desk", 0 in ns and "Reception" in ns[0], ns)

if 0 in dumps:
    # NEGATIVE: drop every collidable part that carries the garage floor (slab, foundation under the
    # garage, floor finishes) -> holes.py must report holes inside the garage
    D = json.load(open(dumps[0]))
    keep = []
    removed = 0
    for i in D["instances"]:
        if "size" in i and i.get("canCollide"):
            cfv, s = i["cframe"], i["size"]
            x, y, z = cfv[0], cfv[1], cfv[2]
            if 64 < x < 108 and -114 < z < -82 and y < 0.5 and s[0] > 8 and s[2] > 8:
                removed += 1
                continue
        keep.append(i)
    D["instances"] = keep
    with tempfile.TemporaryDirectory() as tmp:
        synth = os.path.join(tmp, "nofloor.json")
        json.dump(D, open(synth, "w"))
        rc, txt = run([sys.executable, os.path.join(ROOT, "tests", "lead", "holes.py"), synth])
    m = re.search(r"TOTAL hole area ([\d.]+) sq studs", txt)
    check("NEGATIVE: removing the garage floor is detected as holes", removed > 0 and m is not None and float(m.group(1)) > 100, f"removed {removed}, {m and m.group(1)}")

print(f"buildings geometry: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
