#!/usr/bin/env python3
"""Synthetic regression test for check_geometry.py walkability (known answers).

Scene (building-local, ground top at y=0, start at (0,0,-60)):
  P_ramp   platform top y=8 reached by a rotated invisible ramp part      -> reachable
  P_jump   platform top y=8 with no access                                -> unreachable
  P_wedge  platform top y=8 reached by a WedgePart (high side = local +Z)  -> reachable
  P_stairs platform top y=6 reached by stacked 0.5-rise steps            -> reachable
  R_narrow room whose only opening is 2.0 studs wide                     -> unreachable (radius 1.3)
  R_wide   room whose only opening is 4.0 studs wide (>= 2*radius + grid) -> reachable
  R_door   room closed by a collidable 'DepartmentDoor_T' part            -> reachable (doors open)
  C_low    spot under a slab 3 studs above the ground                     -> unreachable (no clearance)
  L_top    roof slab at y=40 only connected through LiftStop markers      -> reachable
usage: python3 harness/test_check.py   (exit 1 on failure)
"""
import json, math, os, subprocess, sys, tempfile
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
insts = []


def add(name, size, pos, R=None, cls="Part", collide=True, transparency=0.0, attrs=None, parent=1):
    R = np.eye(3) if R is None else np.asarray(R)
    rec = {"id": len(insts) + 1, "parent": parent, "path": "Office/" + name, "class": cls, "name": name,
           "size": list(map(float, size)), "cframe": list(map(float, pos)) + [float(x) for x in R.reshape(-1)],
           "color": [200, 200, 200], "material": "Concrete", "transparency": transparency, "canCollide": collide,
           "canQuery": True, "canTouch": True, "anchored": True, "collisionGroup": "Default", "shape": "Block"}
    if attrs:
        rec["attrs"] = attrs
    insts.append(rec)
    return rec


def nav(name, x, y, z):
    add(name, (0.2, 0.2, 0.2), (x, y + 2.8, z), collide=False, transparency=1, attrs={"NavigationNode": name})


def room(prefix, cx, cz, gap, door=False):
    """10x10 room (walls 0.4 thick, 10 high) with an opening of `gap` studs in the -Z wall."""
    add(prefix + "_back", (10, 10, 0.4), (cx, 5, cz + 5))
    add(prefix + "_l", (0.4, 10, 10), (cx - 5, 5, cz))
    add(prefix + "_r", (0.4, 10, 10), (cx + 5, 5, cz))
    side = (10 - gap) / 2
    add(prefix + "_f1", (side, 10, 0.4), (cx - 5 + side / 2, 5, cz - 5))
    add(prefix + "_f2", (side, 10, 0.4), (cx + 5 - side / 2, 5, cz - 5))
    if door:
        add("DepartmentDoor_T", (gap, 10, 0.3), (cx, 5, cz - 5))
    nav(prefix, cx, 0, cz)


insts.append({"id": 1, "parent": None, "path": "Office", "class": "Model", "name": "Office", "attrs": {"FloorCount": 1}})
add("Ground", (300, 1, 300), (0, -0.5, 0))
# ramp: from (6,0) to (30,8) along +X, rotated about Z
th = math.atan2(8, 24)
L = math.hypot(24, 8)
Rz = np.array([[math.cos(th), -math.sin(th), 0], [math.sin(th), math.cos(th), 0], [0, 0, 1]])
n = Rz[:, 1]
add("Ramp", (L, 1, 8), np.array([18, 4, -100]) - n * 0.5, R=Rz, transparency=1)
add("P_ramp_top", (20, 8, 20), (40, 4, -100))
nav("P_ramp", 40, 8, -100)
add("P_jump_top", (10, 8, 10), (-40, 4, -100))
nav("P_jump", -40, 8, -100)
# wedge: 8 wide, 8 high, 24 long, high side at local +Z (z=30) next to the platform
add("Wedge", (8, 8, 24), (0, 4, 18), cls="WedgePart")
insts[-1].pop("shape")
add("P_wedge_top", (20, 8, 20), (0, 4, 40))
nav("P_wedge", 0, 8, 40)
# stairs: 12 steps of 0.5 rise / 1.2 run along -X, then a platform at y=6
for i in range(1, 13):
    add(f"Step{i}", (6, i * 0.5, 1.2), (-60, i * 0.25, -40 + i * 1.2))
add("P_stairs_top", (10, 6, 10), (-60, 3, -40 + 13 * 1.2 + 4.4))
nav("P_stairs", -60, 6, -40 + 13 * 1.2 + 4.4)
room("R_narrow", 60, -30, 2.0)
room("R_wide", 80, -30, 4.0)
room("R_door", 100, -30, 8, door=True)
add("LowSlab", (10, 0.5, 10), (-90, 3.25, -100))
nav("C_low", -90, 0, -100)
add("L_top", (30, 1, 30), (60, 39.5, 60))
nav("L_top", 60, 40, 60)
add("LiftStopG", (0.2, 0.2, 0.2), (60, 2.8, 30), collide=False, transparency=1, attrs={"LiftStop": 0})
add("LiftStopTop", (0.2, 0.2, 0.2), (60, 42.8, 60), collide=False, transparency=1, attrs={"LiftStop": 1})

EXPECT = {"P_ramp": True, "P_jump": False, "P_wedge": True, "P_stairs": True, "R_narrow": False,
          "R_wide": True, "R_door": True, "C_low": False, "L_top": True}

with tempfile.TemporaryDirectory() as td:
    path = os.path.join(td, "dump_synthetic.json")
    with open(path, "w") as f:
        json.dump({"meta": {"tier": 0, "mode": "local", "campusCFrame": [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]}, "instances": insts}, f)
    out = subprocess.run([sys.executable, os.path.join(HERE, "check_geometry.py"), path, "--no-images", "--box=-140,140,-10,60,-140,140", "--verbose"],
                         capture_output=True, text=True)
    text = out.stdout + out.stderr
    if out.returncode != 0:
        print(text)
        sys.exit(1)
unreach = set()
sec = None
for line in text.splitlines():
    if line.startswith("UNREACHABLE"):
        sec = line
        continue
    if sec and sec.startswith("UNREACHABLE navigation nodes") and line.startswith("   Office/"):
        unreach.add(line.split()[0].split("/")[1])
fail = 0
for name, ok in EXPECT.items():
    got = name not in unreach
    status = "ok  " if got == ok else "FAIL"
    if got != ok:
        fail += 1
    print(f"{status} {name:<10} expected {'reachable' if ok else 'unreachable'}, got {'reachable' if got else 'unreachable'}")
door_line = [l for l in text.splitlines() if l.strip().startswith("doors (both sides)")]
print("door check:", door_line[0].strip() if door_line else "missing")
if not door_line or not door_line[0].split()[-3] == "1":
    fail += 1
    print("FAIL door both-sides check")
print(f"test_check: {len(EXPECT) - fail}/{len(EXPECT)} expectations met")
sys.exit(1 if fail else 0)
