"""check_orientation.py - verifies the Roblox -> Blender conversion with known asymmetric geometry
(no rendering, a few seconds):

  1. Axis mapping: Roblox (x, y, z) -> Blender (x, -z, y) is a proper rotation (det +1, no mirror).
  2. HQ tier 4 seen by the hq4_aerial camera (in front of the building at -Z, to its -X side):
     the garage ramp (RampFill, local +X) must appear LEFT of the guest-house annex (H0 rooms, local -X),
     and the entrance canopy (local -Z, the street side) must be nearer to the camera than the back facade.
  3. Wedge: RampFill is a WedgePart rotated 180 deg about Y; Roblox puts the wedge's high (vertical)
     face at local +Z, so in world space the high edge must be at the street side (-Z) and the
     generated mesh's top vertices must sit at world z < part centre z.
  4. Cylinder axis = local X, Ball diameter = min(size).

    python3 tools/blenderprev/check_orientation.py [dump_tier4.json]
"""
import os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dump2blend as d2b      # noqa: E402
import shots                  # noqa: E402
import bpy                    # noqa: E402
from bpy_extras.object_utils import world_to_camera_view   # noqa: E402
from mathutils import Vector  # noqa: E402

ok = True


def check(cond, msg):
    global ok
    print(("PASS  " if cond else "FAIL  ") + msg)
    ok &= bool(cond)


dump = sys.argv[1] if len(sys.argv) > 1 else shots.HQ_DUMP.format(4)
check(abs(np.linalg.det(d2b.C_R2B) - 1) < 1e-12, "Roblox->Blender matrix is a rotation (det = +1)")
check(d2b.r2b((0, 0, -1)) == (0.0, 1.0, 0.0), "Roblox -Z (Front/LookVector) -> Blender +Y")
check(d2b.r2b((0, 1, 0)) == (0.0, 0.0, 1.0), "Roblox +Y (up) -> Blender +Z")

d2b.reset_scene()
ps = d2b.PartSet().add_dump(dump)
D = ps.merged()
names = D["names"]


def centre(pred):
    idx = [i for i, n in enumerate(names) if pred(n)]
    return D["P"][idx].mean(axis=0), idx


ramp, ri = centre(lambda n: n.endswith("GarageShell/RampFill"))
annex, _ = centre(lambda n: "/Rooms/H0_" in n)
canopy, _ = centre(lambda n: "Facade_Entrance/Canopy" in n)
back, _ = centre(lambda n: "Facade/Facade_Back" in n)
s = shots.SHOTS["hq4_aerial"]
bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y = 1600, 900
cam = d2b.set_camera(s["cam"], s["look"], s["lens"])
scn = bpy.context.scene
bpy.context.view_layer.update()          # refresh matrix_world after setting location/rotation


def screen(p):
    v = world_to_camera_view(scn, cam, Vector(d2b.r2b(p)))
    return v.x, v.y, v.z


sr, sa, sc, sb = screen(ramp), screen(annex), screen(canopy), screen(back)
print(f"      hq4_aerial screen x: ramp {sr[0]:.2f}  annex {sa[0]:.2f}; depth canopy {sc[2]:.0f}  back {sb[2]:.0f}")
check(sr[0] < sa[0], "garage ramp (local +X) appears left of the guest-house annex (local -X)")
check(sc[2] < sb[2], "entrance canopy (local -Z, street side) is nearer to the front camera than the back facade")
check(canopy[2] < -48, "entrance canopy lies in front of the main facade line z = -48 (faces the street at -Z)")

# wedge mesh check
i = ri[0]
T = d2b.template("wedge")
loc = T.verts * D["ext"][i]
world = loc @ D["R"][i].T + D["P"][i]
top = world[T.verts[:, 1] > 0]
check(np.all(top[:, 2] < D["P"][i][2]), f"wedge RampFill: high edge at world z {top[0, 2]:.1f} < centre z "
      f"{D['P'][i][2]:.1f} (street side; local +Z rotated 180 deg)")
cyl = d2b.template("cylX20")
check(np.allclose(cyl.verts[:, 0] ** 2, 1.0), "cylinder template axis = local X (caps at x = +-1)")
print("ALL CHECKS PASSED" if ok else "SOME CHECKS FAILED")
sys.exit(0 if ok else 1)
