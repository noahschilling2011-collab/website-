#!/usr/bin/env python3
"""Package "life" - job routes are walkable on the real building geometry.
For each tier: tests/life/routes.luau checks the job points against the plan (inside a room, support
clearance) and prints the straight in-room hop segments of the operations jobs, the atrium mop loop and
the lunch queue. Every segment is sampled each 1.0 stud; the samples are added as probe Models with an
InteractionPosition to a copy of the harness dump (out/<dir>/dump_tierN.json, building-local frame), and
harness/check_geometry.py (agent radius 1.0, as a humanoid, lenient vs the 1.3 default) reports which
probes are not standable / not connected to the front plaza.
Usage: python3 tests/life/test_routes.py [--out out/life] [--tiers 1,2,3,4]
"""
import json, os, subprocess, sys, tempfile, argparse, re
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ap = argparse.ArgumentParser()
ap.add_argument("--out", default=os.path.join(ROOT, "out", "life"))
ap.add_argument("--tiers", default="1,2,3,4")
ap.add_argument("--step", type=float, default=1.0)
ap.add_argument("--negative", action="store_true", help="add the chef's direct range->pass line (through the prep island): must be reported")
a = ap.parse_args()
passed = failed = 0
def check(name, ok, detail=""):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1
        print(f"FAIL  {name}" + (f"  -- {detail}" if detail else ""))

for tier in [int(t) for t in a.tiers.split(",")]:
    run = subprocess.run([os.path.join(ROOT, "tools", "luau"), os.path.join(HERE, "routes.luau"), "-a", str(tier)], capture_output=True, text=True, cwd=ROOT)
    out = run.stdout + run.stderr
    m = re.search(r"life routes \(plan\): (\d+) passed, (\d+) failed", out)
    check(f"tier {tier} routes.luau ran", m is not None, out[-400:])
    if not m: continue
    passed += int(m.group(1))
    for line in out.splitlines():
        if line.startswith("FAIL"): print(f"tier {tier}: {line}")
    failed += int(m.group(2))
    segs = []
    for line in out.splitlines():
        if line.startswith("@@SEG "):
            _, label, pa, pb = line.split(" ")
            segs.append((label, [float(x) for x in pa.split(",")], [float(x) for x in pb.split(",")]))
    if a.negative:
        # the route the chef would take without the "aisle" via point: straight through the prep island
        segs = [("NEGATIVE_ChefDirect", [63.0, 2.9, 46.4], [76.0, 2.9, 32.6])]
    dump_path = os.path.join(a.out, f"dump_tier{tier}.json")
    check(f"tier {tier} harness dump exists", os.path.exists(dump_path), dump_path)
    if not os.path.exists(dump_path): continue
    D = json.load(open(dump_path))
    inst = D["instances"]
    office_id = inst[0]["id"]
    next_id = max(x["id"] for x in inst) + 1
    probes = 0
    labels = {}
    for si, (label, pa, pb) in enumerate(segs):
        dx, dy, dz = pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2]
        length = (dx * dx + dz * dz) ** 0.5
        n = max(1, int(length / a.step))
        for k in range(n + 1):
            t = k / n
            p = [pa[0] + dx * t, pa[1] + dy * t, pa[2] + dz * t]
            name = f"LifeProbe_{label}_{si}_{k}"
            labels[name] = (label, si, k, p)
            inst.append({"id": next_id, "parent": office_id, "path": f"Office/{name}", "parentPath": "Office", "class": "Model", "name": name,
                         "attrs": {"InteractionPosition": {"Vector3": p}}})
            next_id += 1
            probes += 1
    with tempfile.TemporaryDirectory() as tmp:
        synth = os.path.join(tmp, f"routes_tier{tier}.json")
        json.dump(D, open(synth, "w"))
        rep = subprocess.run([sys.executable, os.path.join(ROOT, "harness", "check_geometry.py"), synth, "--radius", "1.0", "--no-images", "--verbose"], capture_output=True, text=True, cwd=ROOT)
    bad = {}
    section = False
    for line in rep.stdout.splitlines():
        if line.startswith("UNREACHABLE workstations"): section = True; continue
        if section and not line.startswith("   "): section = False
        if section:
            mm = re.search(r"Office/(LifeProbe_[^ ]+) at", line)
            if mm:
                label, si, k, p = labels[mm.group(1)]
                bad.setdefault(f"{label} segment {si}", []).append((k, [round(v, 1) for v in p], line.split("--")[-1].strip()))
    check(f"tier {tier} check_geometry ran", "reachability by category" in rep.stdout, rep.stdout[-300:] + rep.stderr[-300:])
    for segname, pts in bad.items():
        check(f"tier {tier} hop walkable: {segname}", False, f"{len(pts)} sample(s), first {pts[0]}")
    good = len(segs) - len(bad)
    passed += good
    print(f"tier {tier}: {len(segs)} hop segments, {probes} probes, {len(bad)} segment(s) with blocked samples")

if a.negative:
    # inverted: the injected segment must be reported as blocked
    ok = failed > 0
    print(f"life routes (negative): {'detected' if ok else 'NOT detected'}")
    sys.exit(0 if ok else 1)
print(f"life routes: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
