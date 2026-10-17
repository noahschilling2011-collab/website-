#!/usr/bin/env python3
"""ExecutiveLimo - generic stretch executive limousine for "AI Empire" (Roblox).

Fully reproducible, headless Blender (bpy 5.0.1) script:

    python3 model.py                 # build, export FBX/OBJ, manifest, import check, final renders
    python3 model.py --no-render     # everything except the Cycles renders
    python3 model.py --preview       # small, fast test renders (640x360, 16 spp)
    python3 model.py --only=render_hero.png,render_side.png   # render a subset
    python3 model.py --preview --only=dev_front.png --hide=Grille   # development views / hidden objects

Frames
------
* Built in metres in Blender's frame: +X = car LEFT (driver side), +Y = REAR, +Z = UP. The origin is on
  the ground, on the centre line, half-way between the axles (same convention as CityCar/model.py).
* Every mesh is then scaled by 1/0.28 (Roblox: 1 stud = 0.28 m), so 1 Blender unit = 1 stud.
* FBX export with axis_forward='Z', axis_up='Y' maps Blender (x, y, z) -> file (-x, z, y), which is the
  Roblox frame: front = -Z (Model LookVector), right = +X, up = +Y. Driver on the left (-X).

No brand names, logos or trademarked design elements: a generic modern full-size sedan, stretched by
90 in (2.286 m), built from published proportions (see README.md for the sources).
"""
import bpy
import bmesh
import math
import os
import sys
import json
import time
import random
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

T0 = time.time()
OUT = os.path.dirname(os.path.abspath(__file__))
NAME = "ExecutiveLimo"
STUD = 0.28                      # m per stud (create.roblox.com/docs/physics/units)
S = 1.0 / STUD                   # metres -> studs
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
DO_RENDER = "--no-render" not in ARGS
PREVIEW = "--preview" in ARGS
STAGE = ([a.split("=", 1)[1] for a in ARGS if a.startswith("--stage=")] or ["all"])[0]
ONLY = sum([a.split("=", 1)[1].split(",") for a in ARGS if a.startswith("--only=")], [])
HIDE = sum([a.split("=", 1)[1].split(",") for a in ARGS if a.startswith("--hide=")], [])   # debug: hide objects
rad = math.radians
V = Vector


def log(*a):
    print("[%6.1fs]" % (time.time() - T0), *a, flush=True)


# ==============================================================================================
# 1) dimensions (m).  Base car = generic full-size executive sedan, stretched in the middle.
#    Ref. A (coachbuilt 70 in stretch, Lehmann-Peterson XTS Limo): base 202.0 in long / 111.7 in wb ->
#            limo 272.0 in long / 171.7 in wb.   Ref. B (Lincoln Town Car 2003-11, Wikipedia): 5,471 mm
#            long, 2,990 mm wb, 1,994 mm wide, 1,499 mm high; Ford/Lincoln limo chassis up to +120 in.
#    UK licensing (Carmarthenshire): stretch <= 3,048 mm (120 in) between front-door rear edge and
#            rear-door front edge, up to 8 passengers, >= 400 mm seat width.
# ==============================================================================================
BASE_LEN = 5.300        # generic donor sedan: between ref. A (5.131) and ref. B (5.471)
BASE_WB = 3.050         # ref. A 2.837 / ref. B 2.990 (+ a little for the long-hood executive look)
STRETCH = 2.286         # 90 in: between the 70 in (ref. A) and the 120 in maximum (licensing rules)
LENGTH = BASE_LEN + STRETCH          # 7.586
WHEELBASE = BASE_WB + STRETCH        # 5.336
OH_F = 1.020
OH_R = LENGTH - WHEELBASE - OH_F     # 1.230
WIDTH = 1.960           # body without mirrors (ref. B 1.994)
HEIGHT = 1.500          # ref. B 1.499
TRACK = 1.660
GROUND = 0.140          # floor pan underside
TYRE_W = 0.245          # 245/45 R19
TYRE_AR = 0.45
RIM_R = 19 * 0.0254 / 2               # 0.2413
TYRE_R = RIM_R + TYRE_W * TYRE_AR     # 0.3516
YF = -WHEELBASE / 2 - OH_F            # front tip  (-3.688)
YR = WHEELBASE / 2 + OH_R             # rear tip   (+3.898)
YAF, YAR = -WHEELBASE / 2, WHEELBASE / 2
ZA = TYRE_R
ARCH_R = 0.430
HW = WIDTH / 2


def D(d):
    """station measured from the front tip"""
    return YF + d


def E(e):
    """station measured from the rear tip"""
    return YR - e


Y_B = D(2.95)                     # B-pillar (rear edge) = start of the stretch section
Y_C = D(2.95) + STRETCH           # end of the stretch section (front edge of the rear doors)
Y_COWL = D(1.85)
Y_RF = D(2.62)                    # windshield header
Y_RR = E(1.12)                    # backlight header
Y_DECK = E(0.64)                  # backlight base

# ==============================================================================================
# 2) materials: (sRGB hex, roughness, metallic, emission strength, vertex-colour override)
#    Roblox shows one colour per MeshPart, so every face also carries its material colour as an FBX
#    vertex colour (Studio multiplies it by MeshPart.Color). Paint is baked WHITE so Body.Color sets the
#    paint (manifest: midnight 18,20,27), trim/glass/lights keep their own colours.
# ==============================================================================================
MATDEF = {
    "Paint":         ("0B0E15", 0.30, 0.40, 0.0, "FFFFFF"),
    "Trim_Black":    ("0D0E10", 0.12, 0.0, 0.0, None),
    "Satin_Black":   ("17181B", 0.55, 0.0, 0.0, None),
    "Wheelwell":     ("0E0F10", 0.90, 0.0, 0.0, None),
    "Underbody":     ("131416", 0.85, 0.0, 0.0, None),
    "Body_Inner":    ("1B1C1F", 0.80, 0.0, 0.0, None),
    "Cabin_Trim":    ("2B2420", 0.65, 0.0, 0.0, None),
    "Chrome":        ("E2E5EA", 0.06, 1.0, 0.0, None),
    "Plate":         ("EEF0F0", 0.40, 0.0, 0.0, None),
    "Glass":         ("8FA4B0", 0.01, 0.0, 0.0, "2A3A44"),
    "Glass_Privacy": ("12161B", 0.02, 0.0, 0.0, "0E1216"),
    "Mirror_Glass":  ("B8C2CC", 0.02, 1.0, 0.0, None),
    "Headlight_LED": ("F4F8FF", 0.10, 0.0, 6.0, None),
    "Lens":          ("CFE0F0", 0.02, 0.0, 1.2, None),
    "Indicator":     ("FF9A1A", 0.20, 0.0, 0.6, None),
    "Taillight":     ("E0101C", 0.15, 0.0, 4.0, None),
    "Reflector":     ("8A0A12", 0.25, 0.0, 0.0, None),
    "Tire":          ("1A1A1C", 0.82, 0.0, 0.0, None),
    "Tire_Side":     ("222225", 0.70, 0.0, 0.0, None),
    "Rim_Silver":    ("C7CCD2", 0.18, 0.95, 0.0, None),
    "Rim_Dark":      ("3A3E44", 0.30, 0.80, 0.0, None),
    "Brake_Disc":    ("55585D", 0.46, 0.85, 0.0, None),
    "Caliper":       ("8E1C24", 0.32, 0.25, 0.0, None),
    "Leather":       ("D9CDB5", 0.48, 0.0, 0.0, None),
    "Leather_Dark":  ("3A2F28", 0.55, 0.0, 0.0, None),
    "Stitch":        ("B8A88C", 0.60, 0.0, 0.0, None),
    "Carpet":        ("221F1C", 0.95, 0.0, 0.0, None),
    "Headliner":     ("17171A", 0.90, 0.0, 0.0, None),
    "Piano_Black":   ("08090A", 0.05, 0.0, 0.0, None),
    "Wood":          ("4A2C1A", 0.25, 0.0, 0.0, None),
    "Alu":           ("A9AEB4", 0.28, 1.0, 0.0, None),
    "Screen":        ("0A1626", 0.08, 0.0, 0.8, None),
    "Screen_UI":     ("3A86D8", 0.20, 0.0, 2.5, None),
    "Bar_Glass":     ("DCE8EE", 0.02, 0.0, 0.0, None),
    "Water":         ("BFD8E2", 0.02, 0.0, 0.0, None),
    "Ice":           ("E8F2F6", 0.08, 0.0, 0.0, None),
    "LED":           ("8C7BFF", 0.30, 0.0, 14.0, "FFFFFF"),
    "Star":          ("FFFFFF", 0.30, 0.0, 30.0, None),
}


def srgb(hexs):
    return tuple(int(hexs[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def vcolor(nm):
    hx, _r, _m, _e, vc = MATDEF[nm]
    return srgb(vc or hx)


MATS = {}


def make_materials():
    for nm, (hx, rough, metal, emit, _vc) in MATDEF.items():
        m = bpy.data.materials.new(nm)
        if m.node_tree is None:
            m.use_nodes = True
        nt = m.node_tree
        b = nt.nodes.get("Principled BSDF")
        col = lin(srgb(hx)) + (1.0,)
        b.inputs["Base Color"].default_value = col
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        if nm == "Paint":
            # deep midnight metallic with a fine flake + clear coat
            b.inputs["Coat Weight"].default_value = 1.0
            b.inputs["Coat Roughness"].default_value = 0.02
            b.inputs["Coat IOR"].default_value = 1.5
            vor = nt.nodes.new("ShaderNodeTexVoronoi")
            vor.inputs["Scale"].default_value = 2600.0
            tc = nt.nodes.new("ShaderNodeTexCoord")
            nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
            ramp = nt.nodes.new("ShaderNodeMapRange")
            ramp.inputs["From Min"].default_value = 0.0
            ramp.inputs["From Max"].default_value = 1.0
            ramp.inputs["To Min"].default_value = 0.22
            ramp.inputs["To Max"].default_value = 0.40
            nt.links.new(vor.outputs["Distance"], ramp.inputs["Value"])
            nt.links.new(ramp.outputs["Result"], b.inputs["Roughness"])
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = 'RGBA'
            mix.inputs["Factor"].default_value = 0.35
            nt.links.new(vor.outputs["Color"], mix.inputs[7])
            mix.inputs[6].default_value = col
            hsv = nt.nodes.new("ShaderNodeMix")
            hsv.data_type = 'RGBA'
            hsv.blend_type = 'MULTIPLY'
            hsv.inputs["Factor"].default_value = 1.0
            hsv.inputs[6].default_value = col
            nt.links.new(mix.outputs[2], hsv.inputs[7])
            nt.links.new(hsv.outputs[2], b.inputs["Base Color"])
        if nm in ("Glass", "Glass_Privacy", "Bar_Glass", "Water", "Ice"):
            b.inputs["Transmission Weight"].default_value = 1.0 if nm != "Glass_Privacy" else 0.85
            b.inputs["IOR"].default_value = 1.45 if nm != "Water" else 1.33
            if nm == "Glass_Privacy":
                b.inputs["Base Color"].default_value = lin(srgb("2A3038")) + (1.0,)
        if nm == "Lens":
            b.inputs["Transmission Weight"].default_value = 0.6
        if emit > 0:
            b.inputs["Emission Color"].default_value = col
            b.inputs["Emission Strength"].default_value = emit
        m.diffuse_color = col
        MATS[nm] = m


# ==============================================================================================
# 3) helpers
# ==============================================================================================
class Curve:
    """Monotone piecewise-cubic (PCHIP) interpolation, clamped outside the table."""

    def __init__(self, pts):
        pts = sorted(pts)
        self.x = [p[0] for p in pts]
        self.y = [p[1] for p in pts]
        n = len(pts)
        h = [self.x[i + 1] - self.x[i] for i in range(n - 1)]
        d = [(self.y[i + 1] - self.y[i]) / h[i] for i in range(n - 1)]
        m = [0.0] * n
        m[0], m[-1] = d[0], d[-1]
        for i in range(1, n - 1):
            if d[i - 1] * d[i] <= 0:
                m[i] = 0.0
            else:
                w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
                m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
        self.h, self.m = h, m

    def __call__(self, x):
        xs = self.x
        if x <= xs[0]:
            return self.y[0]
        if x >= xs[-1]:
            return self.y[-1]
        i = 0
        while xs[i + 1] < x:
            i += 1
        h = self.h[i]
        t = (x - xs[i]) / h
        h00, h10 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t
        h01, h11 = -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
        return h00 * self.y[i] + h10 * h * self.m[i] + h01 * self.y[i + 1] + h11 * h * self.m[i + 1]


def se(t, n):
    """superellipse round-over 0..1 (vertical tangent at 0, horizontal at 1)"""
    t = min(max(t, 0.0), 1.0)
    return (1.0 - (1.0 - t) ** n) ** (1.0 / n)


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


class Part:
    """a mesh under construction: bmesh in metres + material list + pivot (m, Blender frame)"""

    def __init__(self, name, pivot=(0.0, 0.0, 0.0)):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []
        self.pivot = V(pivot)

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)


def faces_new(bm, vs, mat):
    f = bm.faces.new(vs)
    f.material_index = mat
    return f


def add_grid(p, grid, mat, closed_u=False, flip=False):
    """grid[j][i] of Vectors -> quads; returns vertex grid"""
    bm = p.bm
    vg = [[bm.verts.new(c) for c in row] for row in grid]
    mi = p.mi(mat)
    nj, ni = len(vg), len(vg[0])
    for j in range(nj - 1):
        for i in range(ni if closed_u else ni - 1):
            i2 = (i + 1) % ni
            q = (vg[j][i], vg[j][i2], vg[j + 1][i2], vg[j + 1][i])
            faces_new(bm, q[::-1] if flip else q, mi)
    return vg


def box(p, center, size, mat, bev=0.0, rot=None, segs=1):
    """(chamfered) box; rot = 3x3 Matrix applied about the centre"""
    bm = p.bm
    before = set(bm.faces)
    g = bmesh.ops.create_cube(bm, size=1.0)
    vs = g["verts"]
    for v in vs:
        v.co = V((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bev > 0:
        es = list({e for v in vs for e in v.link_edges})
        bmesh.ops.bevel(bm, geom=vs + es, offset=bev, offset_type='OFFSET', segments=segs, profile=0.5,
                        affect='EDGES', clamp_overlap=True)
    nf = [f for f in bm.faces if f not in before]
    nv = list({v for f in nf for v in f.verts})
    c = V(center)
    for v in nv:
        v.co = (rot @ v.co if rot is not None else v.co) + c
    mi = p.mi(mat)
    for f in nf:
        f.material_index = mi
    return nf


def frame_from(axis):
    """orthonormal frame (u, v, w) with w = axis"""
    w = V(axis).normalized()
    a = V((0, 0, 1)) if abs(w.z) < 0.9 else V((1, 0, 0))
    u = a.cross(w).normalized()
    v = w.cross(u)
    return u, v, w


def revolve(p, prof, nseg, mat, center=(0, 0, 0), axis=(1, 0, 0), phase=0.0, closed=True, mats=None, weld=False):
    """revolve profile [(axial, radius)] around `axis` through `center`. closed=True closes the profile
    loop (last -> first). mats: optional per-segment material list."""
    bm = p.bm
    u, v, w = frame_from(axis)
    c = V(center)
    rings = []
    for k in range(nseg):
        t = 2 * math.pi * k / nseg + phase
        ct, st = math.cos(t), math.sin(t)
        rings.append([bm.verts.new(c + w * a + (u * ct + v * st) * r) for a, r in prof])
    n = len(prof)
    for k in range(nseg):
        A, B = rings[k], rings[(k + 1) % nseg]
        for j in range(n if closed else n - 1):
            j2 = (j + 1) % n
            mm = p.mi(mats[j] if mats else mat)
            faces_new(bm, (A[j], A[j2], B[j2], B[j]), mm)
    if weld:
        bmesh.ops.remove_doubles(bm, verts=[v for r in rings for v in r], dist=1e-7)
        return None
    return rings


def cylinder(p, c0, c1, r, nseg, mat, phase=0.0, r1=None):
    bm = p.bm
    c0, c1 = V(c0), V(c1)
    u, v, w = frame_from(c1 - c0)
    r1 = r if r1 is None else r1
    rings = []
    for c, rr in ((c0, r), (c1, r1)):
        rings.append([bm.verts.new(c + (u * math.cos(2 * math.pi * k / nseg + phase) +
                                       v * math.sin(2 * math.pi * k / nseg + phase)) * rr) for k in range(nseg)])
    mi = p.mi(mat)
    for k in range(nseg):
        k2 = (k + 1) % nseg
        faces_new(bm, (rings[0][k], rings[0][k2], rings[1][k2], rings[1][k]), mi)
    faces_new(bm, rings[0][::-1], mi)
    faces_new(bm, rings[1], mi)
    return rings


def sweep(p, path, prof, mat, closed_path=False, up=(0, 0, 1), cap=True):
    """sweep a closed 2D profile [(a, b)] along a polyline; a along the side vector, b along `up`-ish"""
    bm = p.bm
    pts = [V(q) for q in path]
    n = len(pts)
    upv = V(up)
    rings = []
    for i in range(n):
        if closed_path:
            t = (pts[(i + 1) % n] - pts[(i - 1) % n])
        else:
            t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)])
        t.normalize()
        sd = t.cross(upv)
        if sd.length < 1e-6:
            sd = t.cross(V((1, 0, 0)))
        sd.normalize()
        nn = sd.cross(t).normalized()
        # mitre: scale profile on sharp corners
        rings.append([bm.verts.new(pts[i] + sd * a + nn * b) for a, b in prof])
    mi = p.mi(mat)
    m = len(prof)
    for i in range(n if closed_path else n - 1):
        A, B = rings[i], rings[(i + 1) % n]
        for j in range(m):
            j2 = (j + 1) % m
            faces_new(bm, (A[j], A[j2], B[j2], B[j]), mi)
    if cap and not closed_path:
        faces_new(bm, rings[0][::-1], mi)
        faces_new(bm, rings[-1], mi)
    return rings


def circle_prof(r, n, sx=1.0, sy=1.0):
    return [(r * sx * math.cos(2 * math.pi * k / n), r * sy * math.sin(2 * math.pi * k / n)) for k in range(n)]


def rounded_poly(pts, r, nseg=4):
    """2D polygon (CCW or CW) with each corner rounded by radius r (r may be a list per corner)"""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = V(pts[i - 1]), V(pts[i]), V(pts[(i + 1) % n])
        ri = r[i] if isinstance(r, (list, tuple)) else r
        a = (p0 - p1)
        b = (p2 - p1)
        la, lb = a.length, b.length
        a.normalize()
        b.normalize()
        ang = math.acos(max(-1.0, min(1.0, a.dot(b))))
        if ri <= 1e-6 or ang > math.pi - 1e-3:
            out.append(p1.copy())
            continue
        t = ri / math.tan(ang / 2)
        t = min(t, 0.45 * la, 0.45 * lb)
        ri = t * math.tan(ang / 2)
        q0, q1 = p1 + a * t, p1 + b * t
        bis = (a + b).normalized()
        cc = p1 + bis * (ri / math.sin(ang / 2))
        a0 = math.atan2(q0.y - cc.y, q0.x - cc.x)
        a1 = math.atan2(q1.y - cc.y, q1.x - cc.x)
        da = a1 - a0
        while da > math.pi:
            da -= 2 * math.pi
        while da < -math.pi:
            da += 2 * math.pi
        for k in range(nseg + 1):
            aa = a0 + da * k / nseg
            out.append(V((cc.x + ri * math.cos(aa), cc.y + ri * math.sin(aa))))
    return out


def densify(pts, step):
    """closed polyline with extra points so that no edge is longer than `step` (mapped bands then follow the
    curved surface instead of cutting chords through it)"""
    out = []
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        k = max(1, int(math.ceil((b - a).length / step)))
        for j in range(k):
            out.append(a + (b - a) * (j / k))
    return out


def poly_area(pts):
    return 0.5 * sum(pts[i - 1].x * pts[i].y - pts[i].x * pts[i - 1].y for i in range(len(pts)))


def offset_poly(pts, d):
    """offset a closed 2D polygon outward by d (miter); works for CCW or CW"""
    n = len(pts)
    sgn = 1.0 if poly_area(pts) > 0 else -1.0
    out = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        e0 = (p1 - p0).normalized()
        e1 = (p2 - p1).normalized()
        n0 = V((e0.y, -e0.x)) * sgn
        n1 = V((e1.y, -e1.x)) * sgn
        nb = (n0 + n1)
        if nb.length < 1e-9:
            nb = n0
        nb.normalize()
        c = max(0.3, nb.dot(n0))
        out.append(p1 + nb * (d / c))
    return out


def prism(p, outline, axis, a0, a1, mat, origin=(0, 0, 0)):
    """extrude a closed 2D outline [(s, t)] along `axis` from a0 to a1. The 2D coords map to the frame
    (u, v) of `axis` unless axis is one of 'X','Y','Z' (then s,t = the other two axes in order)."""
    bm = p.bm
    o = V(origin)
    if axis == 'X':
        f = lambda s, t, a: o + V((a, s, t))
    elif axis == 'Y':
        f = lambda s, t, a: o + V((s, a, t))
    elif axis == 'Z':
        f = lambda s, t, a: o + V((s, t, a))
    else:
        u, v, w = axis
        f = lambda s, t, a: o + u * s + v * t + w * a
    r0 = [bm.verts.new(f(q[0], q[1], a0)) for q in outline]
    r1 = [bm.verts.new(f(q[0], q[1], a1)) for q in outline]
    mi = p.mi(mat)
    n = len(outline)
    for i in range(n):
        i2 = (i + 1) % n
        faces_new(bm, (r0[i], r0[i2], r1[i2], r1[i]), mi)
    faces_new(bm, r0[::-1], mi)
    faces_new(bm, r1, mi)
    bmesh.ops.recalc_face_normals(bm, faces=list({f for v in r0 + r1 for f in v.link_faces}))
    return r0, r1


def part_to_object(p, name=None, link=True):
    me = bpy.data.meshes.new(name or p.name)
    p.bm.to_mesh(me)
    for m in p.mats:
        me.materials.append(MATS[m])
    ob = bpy.data.objects.new(name or p.name, me)
    if link:
        bpy.context.scene.collection.objects.link(ob)
    return ob


def object_to_part(ob, name, pivot=(0, 0, 0)):
    """evaluated mesh (modifiers applied) -> Part"""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    p = Part(name, pivot)
    p.bm.from_mesh(me)
    p.mats = [m.name if m else "Paint" for m in me.materials]
    # Blender may suffix material names (.001) - map back
    p.mats = [m.split(".")[0] for m in p.mats]
    bpy.data.meshes.remove(me)
    # merge duplicate material slots
    uniq = []
    remap = {}
    for i, m in enumerate(p.mats):
        if m not in uniq:
            uniq.append(m)
        remap[i] = uniq.index(m)
    for f in p.bm.faces:
        f.material_index = remap.get(f.material_index, 0)
    p.mats = uniq
    return p


def merge_part(dst, src, transform=None):
    """append src's geometry into dst (with material remap)"""
    me = bpy.data.meshes.new("tmp")
    src.bm.to_mesh(me)
    if transform is not None:
        me.transform(transform)
    remap = {i: dst.mi(m) for i, m in enumerate(src.mats)}
    before = set(dst.bm.faces)
    dst.bm.from_mesh(me)
    for f in dst.bm.faces:
        if f not in before:
            f.material_index = remap.get(f.material_index, 0)
    bpy.data.meshes.remove(me)


def boolean(target, cutters, op, name=None, self_check=False):
    """exact boolean: target Part (op) list of Parts -> new Part (materials transferred)"""
    ob = part_to_object(target, "tgt_" + target.name)
    col = bpy.data.collections.new("cut_" + target.name)
    bpy.context.scene.collection.children.link(col)
    obs = []
    for i, c in enumerate(cutters):
        o = part_to_object(c, "cut%d_%s" % (i, c.name), link=False)
        col.objects.link(o)
        obs.append(o)
    md = ob.modifiers.new("bool", 'BOOLEAN')
    md.operation = op
    md.solver = 'EXACT'
    md.operand_type = 'COLLECTION'
    md.collection = col
    md.material_mode = 'TRANSFER'
    md.use_self = self_check
    md.use_hole_tolerant = False
    res = object_to_part(ob, name or target.name, target.pivot)
    for o in obs:
        bpy.data.meshes.remove(o.data)
    bpy.data.collections.remove(col)
    bpy.data.meshes.remove(ob.data)
    return res


def nonmanifold(p):
    return sum(1 for e in p.bm.edges if not e.is_manifold)


def drop_loose_islands(p, max_faces=3):
    """delete connected face islands of at most max_faces faces that are not closed (boolean slivers)"""
    bm = p.bm
    seen, kill = set(), []
    for f in bm.faces:
        if f in seen:
            continue
        isl, stack = [], [f]
        seen.add(f)
        while stack:
            g = stack.pop()
            isl.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h not in seen:
                        seen.add(h)
                        stack.append(h)
        if len(isl) <= max_faces and any(not e.is_manifold for g in isl for e in g.edges):
            kill += isl
    if kill:
        bmesh.ops.delete(bm, geom=kill, context='FACES')
    # tiny holes (boolean slivers where two cut planes almost coincide): fill them
    bnd = [e for e in bm.edges if len(e.link_faces) == 1]
    if bnd:
        res = bmesh.ops.holes_fill(bm, edges=bnd, sides=6)
        for f in res["faces"]:
            nb = [g for e in f.edges for g in e.link_faces if g is not f]
            if nb:
                f.material_index = nb[0].material_index
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        kill += res["faces"]
    return len(kill)


# ==============================================================================================
# 4) body skin: profile curves (m) along Y, a structured cage loft (rings x stations) closed by two
#    Coons-patch end caps, Catmull-Clark subdivision (level 1) with creases on the character lines.
# ==============================================================================================
def CY(pts):
    """Curve from [(station_func_value, value)]"""
    return Curve(pts)


ZB = CY([(D(0.10), 0.250), (D(0.45), 0.215), (D(0.80), 0.175), (D(1.45), GROUND), (E(1.65), GROUND),
         (E(0.95), 0.175), (E(0.55), 0.212), (E(0.15), 0.240)])
HWM = CY([(D(0.10), 0.930), (D(0.40), 0.958), (D(0.85), 0.974), (D(1.40), HW), (E(1.40), HW),
          (E(0.85), 0.975), (E(0.40), 0.960), (E(0.10), 0.935)])
Z_SILL = CY([(D(0.3), 0.300), (D(1.5), 0.330), (E(1.6), 0.330), (E(0.3), 0.320)])
Z_MAXW = CY([(D(0.2), 0.560), (D(1.2), 0.600), (E(1.2), 0.610), (E(0.2), 0.640)])
Z_CL = CY([(D(0.20), 0.770), (D(1.00), 0.790), (D(2.0), 0.800), (E(2.0), 0.800), (E(1.0), 0.812),
           (E(0.20), 0.835)])
Z_BELT = CY([(D(0.10), 0.798), (D(0.55), 0.840), (D(1.20), 0.898), (D(1.72), 0.952), (D(1.95), 0.980),
             (D(2.25), 0.985), (E(1.55), 0.985), (E(1.10), 0.993), (E(0.70), 1.012), (E(0.35), 1.026),
             (E(0.10), 1.020), (E(0.02), 1.005)])
HW_BELT = CY([(D(0.10), 0.840), (D(0.55), 0.872), (D(1.20), 0.888), (D(1.90), 0.895), (E(1.40), 0.895),
              (E(0.70), 0.888), (E(0.30), 0.872), (E(0.05), 0.845)])
Z_RAIL = CY([(D(0.10), 0.812), (D(0.55), 0.850), (D(1.20), 0.905), (D(1.76), 0.958), (D(1.86), 0.978),
             (D(1.96), 1.012), (D(2.30), 1.205), (D(2.60), 1.392), (D(2.80), 1.430), (D(2.95), 1.432),
             (E(1.75), 1.432), (E(1.55), 1.428), (E(1.25), 1.405), (E(1.10), 1.380), (E(0.85), 1.230),
             (E(0.66), 1.090), (E(0.55), 1.074), (E(0.20), 1.068), (E(0.04), 1.050)])
HW_RAIL = CY([(D(0.10), 0.760), (D(0.55), 0.780), (D(1.76), 0.795), (D(1.90), 0.800), (D(2.30), 0.775),
              (D(2.65), 0.738), (D(2.80), 0.735), (E(1.70), 0.735), (E(1.10), 0.742), (E(0.70), 0.770),
              (E(0.55), 0.785), (E(0.10), 0.790)])
Z_TOP = CY([(D(0.10), 0.808), (D(0.30), 0.840), (D(0.70), 0.884), (D(1.25), 0.930), (D(1.78), 0.966),
            (D(1.86), 0.972), (D(2.24), 1.215), (D(2.58), 1.440), (D(2.72), 1.478), (D(2.95), 1.497),
            (D(3.20), 1.500), (E(1.60), 1.500), (E(1.35), 1.494), (E(1.15), 1.470), (E(1.00), 1.395),
            (E(0.80), 1.240), (E(0.66), 1.118), (E(0.56), 1.094), (E(0.30), 1.086), (E(0.10), 1.074),
            (E(0.03), 1.058)])
BOW = 0.010
RING_N = 18             # points per half ring (bottom centre .. top centre)
I_SILL, I_MAXW, I_CL, I_BELT, I_RAIL = 4, 6, 8, 10, 13


def ring_half(y):
    zb, hw = ZB(y), HWM(y)
    zs, zm, zc = Z_SILL(y), Z_MAXW(y), Z_CL(y)
    z4, hw4 = Z_BELT(y), HW_BELT(y)
    z5, hw5, z6 = Z_RAIL(y), HW_RAIL(y), Z_TOP(y)
    zc = min(zc, z4 - 0.06)
    zm = min(zm, zc - 0.08)
    pts = [(0.0, zb), (hw - 0.24, zb), (hw - 0.075, zb + 0.012), (hw - 0.026, zb + 0.065),
           (hw - 0.011, zs),                                   # 4 sill crease
           (hw - 0.002, 0.5 * (zs + zm)),
           (hw, zm),                                           # 6 max width
           (hw - 0.005, zc - 0.07),
           (hw - 0.010, zc),                                   # 8 character line (crease)
           (hw4 + (hw - 0.012 - hw4) * 0.62, zc + (z4 - zc) * 0.52),
           (hw4, z4)]                                          # 10 belt
    dx, dz = hw5 - hw4, z5 - z4
    lb = math.hypot(dx, dz) + 1e-9
    nx, nz = dz / lb, -dx / lb
    if nx < 0:
        nx, nz = -nx, -nz
    for f in (0.36, 0.70):
        b = BOW * math.sin(math.pi * f)
        pts.append((hw4 + dx * f + nx * b, z4 + dz * f + nz * b))
    pts.append((hw5, z5))                                      # 13 rail
    dh = max(z6 - z5, 0.004)
    pts.append((hw5 - 0.035, z5 + dh * 0.45))
    pts.append((hw5 * 0.62, z6 - dh * 0.10))
    pts.append((hw5 * 0.30, z6 - dh * 0.025))
    pts.append((0.0, z6))
    assert len(pts) == RING_N
    return pts


# nose / tail round-over (plan corner radius, hood leading edge, bumper lip) and face lean / plan bow
NOSE = dict(L=0.42, sx0=0.62, nx=2.5, zc=0.48, lt=0.11, st0=0.86, nt=2.2, lb=0.11, sb0=0.87, nb=2.2,
            lean=0.15, bow=0.17)
TAIL = dict(L=0.34, sx0=0.64, nx=2.7, zc=0.62, lt=0.075, st0=0.90, nt=2.4, lb=0.14, sb0=0.85, nb=2.0,
            lean=-0.03, bow=0.12)


def ring_at(y):
    """half ring at station y, incl. nose/tail round-over. returns [(x, y, z)]"""
    for P, tip, sgn in ((NOSE, YF, 1.0), (TAIL, YR, -1.0)):
        d = (y - tip) * sgn
        if d < P["L"]:
            y0 = tip + sgn * P["L"]
            base = ring_half(y0)
            t = d / P["L"]
            sx = P["sx0"] + (1 - P["sx0"]) * se(t, P["nx"])
            st = P["st0"] + (1 - P["st0"]) * se(d / P["lt"], P["nt"])
            sb = P["sb0"] + (1 - P["sb0"]) * se(d / P["lb"], P["nb"])
            w = (1.0 - t) ** 2
            out = []
            for x, z in base:
                zz = P["zc"] + (z - P["zc"]) * (st if z > P["zc"] else sb)
                xx = x * sx
                lean = P["lean"] * min(max((zz - 0.30) / 0.45, 0.0), 1.0)
                bow = P["bow"] * (xx / HW) ** 2
                out.append((xx, y + sgn * w * (lean + bow), zz))
            return out
    return [(x, y, z) for x, z in ring_half(y)]


def full_ring(h):
    return h + [(-x, y, z) for x, y, z in reversed(h[1:-1])]


STATIONS = ([D(d) for d in (0.0, 0.018, 0.05, 0.10, 0.17, 0.27, 0.42, 0.62, 0.88, 1.15, 1.42, 1.66, 1.80,
                            1.92, 2.10, 2.30, 2.48, 2.64, 2.80)] +
            [Y_B, Y_C] +
            [E(e) for e in (2.05, 1.75, 1.50, 1.30, 1.14, 0.98, 0.80, 0.66, 0.52, 0.36, 0.22, 0.12, 0.055,
                            0.018, 0.0)])


def coons(bot, top, left, right):
    nu, nv = len(bot) - 1, len(left) - 1
    P = []
    for j in range(nv + 1):
        v = j / nv
        row = []
        for i in range(nu + 1):
            u = i / nu
            Lc = bot[i] * (1 - v) + top[i] * v
            Ld = left[j] * (1 - u) + right[j] * u
            B = (bot[0] * (1 - u) * (1 - v) + bot[nu] * u * (1 - v) + top[0] * (1 - u) * v + top[nu] * u * v)
            row.append(Lc + Ld - B)
        P.append(row)
    return P


def build_skin():
    """closed outer skin (cage), crease layer, then subdivided -> Part 'Skin'"""
    p = Part("Skin")
    bm = p.bm
    cr = bm.edges.layers.float.get("crease_edge") or bm.edges.layers.float.new("crease_edge")
    rings = []
    for y in STATIONS:
        h = ring_at(y)
        rings.append([bm.verts.new(c) for c in full_ring(h)])
    n = len(rings[0])
    paint, under = p.mi("Paint"), p.mi("Underbody")
    for a, b in zip(rings[:-1], rings[1:]):
        for j in range(n):
            k = (j + 1) % n
            mat = under if (j == 0 or k == 0) else paint
            faces_new(bm, (a[j], a[k], b[k], b[j]), mat)
    # crease the character line / sill line, faded out in the nose and tail
    for si, (a, b) in enumerate(zip(rings[:-1], rings[1:])):
        ym = 0.5 * (STATIONS[si] + STATIONS[si + 1])
        fade = smooth((ym - D(0.30)) / 0.45) * smooth((E(0.25) - ym) / 0.40)
        for idx, val in ((I_CL, 0.85), (n - I_CL, 0.85), (I_SILL, 0.55), (n - I_SILL, 0.55)):
            e = bm.edges.get((a[idx], b[idx]))
            if e:
                e[cr] = val * fade
    # end caps: Coons patches. bottom edge = sill(R) .. bottom centre .. sill(L); top = rail(R)..rail(L)
    for rg in (rings[0], rings[-1]):
        F = rg
        B = I_SILL
        T = RING_N - 1 - I_RAIL          # 4
        assert B == T
        bot_i = [n - B + k for k in range(B)] + list(range(0, B + 1))
        top_i = [RING_N - 1 + B - k for k in range(B)] + [RING_N - 1 - k for k in range(0, B + 1)][::-1][::-1]
        top_i = [(RING_N - 1 + B - k) % n for k in range(2 * B + 1)]
        left_i = list(range(B, I_RAIL + 1))
        right_i = [(n - k) % n for k in range(B, I_RAIL + 1)]
        bot = [F[i].co.copy() for i in bot_i]
        top = [F[i].co.copy() for i in top_i]
        right = [F[i].co.copy() for i in left_i]
        left = [F[i].co.copy() for i in right_i]
        G = coons(bot, top, left, right)
        nv, nu = len(G) - 1, len(G[0]) - 1
        vg = []
        for j in range(nv + 1):
            row = []
            for i in range(nu + 1):
                if j == 0:
                    row.append(F[bot_i[i]])
                elif j == nv:
                    row.append(F[top_i[i]])
                elif i == 0:
                    row.append(F[right_i[j]])
                elif i == nu:
                    row.append(F[left_i[j]])
                else:
                    row.append(bm.verts.new(G[j][i]))
            vg.append(row)
        for j in range(nv):
            for i in range(nu):
                faces_new(bm, (vg[j][i], vg[j][i + 1], vg[j + 1][i + 1], vg[j + 1][i]), paint)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    log("skin cage: %d verts %d faces, non-manifold %d" % (len(bm.verts), len(bm.faces), nonmanifold(p)))
    ob = part_to_object(p, "skin_cage")
    md = ob.modifiers.new("ss", 'SUBSURF')
    md.levels = 1
    md.render_levels = 1
    md.use_creases = True
    md.quality = 3
    q = object_to_part(ob, "Skin")
    bpy.data.meshes.remove(ob.data)
    log("skin: %d faces, non-manifold %d" % (len(q.bm.faces), nonmanifold(q)))
    return q, p


# ==============================================================================================
# render helpers (Cycles CPU)
# ==============================================================================================
def setup_studio(night=False):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 16 if PREVIEW else 56
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    try:
        sc.cycles.use_denoising = True
        sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    except Exception:
        sc.cycles.use_denoising = False
    sc.cycles.max_bounces = 8
    sc.cycles.glossy_bounces = 4
    sc.cycles.transmission_bounces = 8
    sc.cycles.transparent_max_bounces = 8
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.blur_glossy = 1.0
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Medium High Contrast'
    sc.render.threads_mode = 'FIXED'
    sc.render.threads = 3
    # world: bundled studio HDRI (reflections only, low strength)
    w = bpy.data.worlds.new("World")
    sc.world = w
    if w.node_tree is None:
        w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes.get("Background")
    hdr = os.path.join(os.path.dirname(bpy.__file__), "..", "..", "datafiles", "studiolights", "world",
                       "night.exr" if night else "studio.exr")
    hdr = os.path.normpath(hdr)
    if not os.path.exists(hdr):
        for root, _d, files in os.walk(os.path.dirname(os.path.dirname(bpy.__file__))):
            if ("night.exr" if night else "studio.exr") in files and "studiolights" in root:
                hdr = os.path.join(root, "night.exr" if night else "studio.exr")
                break
    if os.path.exists(hdr):
        env = nt.nodes.new("ShaderNodeTexEnvironment")
        env.image = bpy.data.images.load(hdr)
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Rotation"].default_value = (0, 0, rad(70))
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nt.links.new(tc.outputs["Generated"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], env.inputs["Vector"])
        nt.links.new(env.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.08 if night else 0.75
    k = S
    # cyclorama (floor curving into a back wall), in studs
    gm = bpy.data.materials.new("Cyc")
    if gm.node_tree is None:
        gm.use_nodes = True
    gb = gm.node_tree.nodes.get("Principled BSDF")
    gb.inputs["Base Color"].default_value = (0.020, 0.021, 0.023, 1.0) if night else (0.034, 0.035, 0.038, 1.0)
    gb.inputs["Roughness"].default_value = 0.16 if night else 0.24
    gb.inputs["Specular IOR Level"].default_value = 0.5
    p = Part("Cyc")
    prof = []
    Rr = 6.0
    for i in range(14):
        a = (math.pi / 2) * i / 13
        prof.append((-14.0 + 0.0, 0.0))
    xs = []
    rows = []
    ys = [-400, -150] + [-40 + i * 2.0 for i in range(18)] + [14 + Rr * math.sin(math.pi / 2 * i / 10) for i in range(1, 11)]
    zs = [0.0, 0.0] + [0.0] * 18 + [Rr * (1 - math.cos(math.pi / 2 * i / 10)) for i in range(1, 11)]
    ys += [14 + Rr] * 3
    zs += [Rr + 6, Rr + 14, Rr + 60]
    grid = [[V((x * k, y * k, z * k)) for x in (-900, -300, -120, -40, -20, -8, 0, 8, 20, 40, 120, 300, 900)]
            for y, z in zip(ys, zs)]
    add_grid(p, grid, "Plate")
    ob = part_to_object(p, "Cyc")
    ob.data.materials.clear()
    ob.data.materials.append(gm)
    for f in ob.data.polygons:
        f.use_smooth = True
    ob.rotation_euler = (0, 0, rad(-28))
    lights = []

    def area(name, loc, target, size, energy, shape='RECTANGLE', size_y=None, color=(1, 1, 1)):
        L = bpy.data.lights.new(name, 'AREA')
        L.shape = shape
        L.size = size * k
        if size_y:
            L.size_y = size_y * k
        L.energy = energy * k * k
        L.color = color
        o = bpy.data.objects.new(name, L)
        o.location = V(loc) * k
        o.rotation_euler = (V(target) * k - o.location).to_track_quat('-Z', 'Y').to_euler()
        bpy.context.scene.collection.objects.link(o)
        lights.append(o)
        return o

    if night:
        area("Top", (0, 0, 5.5), (0, 0, 0), 9.0, 120, size_y=1.2, color=(0.75, 0.82, 1.0))
        area("RimL", (-6, 7, 2.0), (0, 0, 0.6), 4.0, 260, size_y=0.6, color=(0.6, 0.7, 1.0))
        area("RimR", (6, -7, 2.0), (0, 0, 0.6), 4.0, 200, size_y=0.6, color=(1.0, 0.85, 0.7))
    else:
        # long overhead strip along the car: draws the roof/bonnet highlight; narrow in X so the windshield and the
        # glass (which mirror the sky at grazing angles) do not reflect it as a white slab
        area("Top", (0, 0.2, 5.0), (0, 0.2, 0), 3.0, 1100, size_y=9.0)
        area("Key", (7.0, -8.0, 3.0), (0, -0.8, 0.6), 4.0, 900, size_y=2.0)
        area("StripL", (-7.0, -1.0, 1.25), (0, -1.0, 0.75), 11.0, 650, size_y=0.45)
        area("StripR", (7.0, 1.0, 1.25), (0, 1.0, 0.75), 11.0, 650, size_y=0.45)
        area("Back", (-2.0, 12, 2.6), (0, 0, 0.8), 6.0, 700, size_y=1.6)
        area("Front", (2.0, -12, 2.2), (0, 0, 0.6), 6.0, 450, size_y=1.6)
        area("Wall", (0, 18.5, 3.0), (0, 30, 3.0), 18.0, 900, size_y=6.0)
    return lights


def camera(name, loc, target, lens=50.0, ortho=None, shift_y=0.0):
    cam = bpy.data.cameras.new(name)
    co = bpy.data.objects.new(name, cam)
    bpy.context.scene.collection.objects.link(co)
    co.location = V(loc) * S
    d = (V(target) * S - co.location).normalized()
    co.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    if ortho:
        cam.type = 'ORTHO'
        cam.ortho_scale = ortho * S
    else:
        cam.lens = lens
    cam.shift_y = shift_y
    cam.clip_start = 0.05
    cam.clip_end = 4000
    return co


def render(co, path, res=(1280, 720), samples=None):
    sc = bpy.context.scene
    if PREVIEW:
        res = (640, 360)
        path = path.replace(".png", "_prev.png")
    sc.camera = co
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    if samples and not PREVIEW:
        sc.cycles.samples = samples
    sc.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    log("rendered", os.path.basename(path), "%.1fs" % (time.time() - t))


# ==============================================================================================
# 5) body openings: cabin cavity, wheel arches, window / door outlines (side view y,z), front and
#    rear face openings (x,z), seams. All cutters are closed prisms; Exact booleans keep Body closed.
# ==============================================================================================
CAV_ST = [D(1.70), D(1.80), D(1.92), D(2.10), D(2.30), D(2.48), D(2.64), D(2.80), Y_B, Y_C,
          E(2.05), E(1.75), E(1.50), E(1.30), E(1.14), E(0.98), E(0.80), E(0.66)]
WALL = 0.035            # roof / pillar wall thickness
DOOR_T = 0.095          # door / side wall thickness below the belt
Z_FLOOR = GROUND + 0.05  # cavity floor (floor pan 5 cm)


def cavity_half(y):
    zb, hw = ZB(y), HWM(y)
    z4, hw4 = Z_BELT(y), HW_BELT(y)
    z5, hw5, z6 = Z_RAIL(y), HW_RAIL(y), Z_TOP(y)
    zf = max(zb + 0.05, Z_FLOOR)
    top = z6 - WALL
    dx, dz = hw5 - hw4, z5 - z4
    lb = math.hypot(dx, dz) + 1e-9
    nx, nz = dz / lb, -dx / lb
    if nx < 0:
        nx, nz = -nx, -nz
    c4 = (min(hw4 - nx * WALL - 0.004, hw - DOOR_T), z4 - nz * WALL)
    pts = [(0.0, zf), (hw - 0.14, zf), (hw - DOOR_T, zf + 0.09), (hw - DOOR_T, min(z4 - 0.03, c4[1] - 0.012)),
           c4]
    pts.append((hw5 - nx * WALL - 0.012, min(z5 - nz * WALL, top - 0.01)))
    pts.append((hw5 * 0.62, top - max(z6 - z5, 0.0) * 0.12))
    pts.append((0.0, top))
    return pts


def build_cavity():
    p = Part("Cavity")
    bm = p.bm
    mi = p.mi("Cabin_Trim")
    rings = []
    for y in CAV_ST:
        h = cavity_half(y)
        full = h + [(-x, z) for x, z in reversed(h[1:-1])]
        rings.append([bm.verts.new((x, y, z)) for x, z in full])
    n = len(rings[0])
    for a, b in zip(rings[:-1], rings[1:]):
        for j in range(n):
            k = (j + 1) % n
            faces_new(bm, (a[j], a[k], b[k], b[j]), mi)
    faces_new(bm, rings[0][::-1], mi)
    faces_new(bm, rings[-1], mi)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # rear wheelhouses stay solid (3 cm wall around the arch)
    whs = []
    for sx in (1, -1):
        c = Part("wh")
        cylinder(c, (sx * (REAR_WELL_X - 0.035), YAR, ZA), (sx * 1.6, YAR, ZA), ARCH_R + 0.035, 40, "Cabin_Trim")
        whs.append(c)
    return boolean(p, whs, 'DIFFERENCE', "Cavity")


REAR_WELL_X = 0.640      # inner wall of the rear wheel wells (front: 0.50, room to steer)


def arch_cutters():
    out = []
    for ya in (YAF, YAR):
        for sx in (1, -1):
            c = Part("arch")
            x0 = 0.50 if ya < 0 else REAR_WELL_X
            cylinder(c, (sx * x0, ya, ZA), (sx * 1.6, ya, ZA), ARCH_R, 56, "Wheelwell")
            out.append(c)
    return out


# ---------------------------------------------------------------- side window outlines (y, z)
Z_DLO = 0.997            # bottom of the side glass (belt + chrome strip)


def top_edge(y):
    """top edge of the side glass opening: below the roof rail / A-pillar / C-pillar"""
    off = 0.034 + 0.018 * smooth((D(2.62) - y) / 0.30)
    return Z_RAIL(y) - off


Y_DLO0 = D(2.14)                  # front edge of the side glass (mirror sail ahead of it)
Y_DLO1, Y_DLO1T = E(1.40), E(1.62)  # C-pillar edge at the belt / at the roof
Y_MID = 0.5 * (Y_B + Y_C)
POSTS = [(D(2.85), Y_B + 0.040), (Y_MID - 0.042, Y_MID + 0.042), (Y_C - 0.048, Y_C + 0.042)]


def dlo_outline(grow=0.0):
    """outline of the whole side glasshouse (y, z), optionally grown"""
    pts = [V((Y_DLO0, Z_DLO)), V((Y_DLO1, Z_DLO)), V((Y_DLO1T, top_edge(Y_DLO1T)))]
    n = 34
    for i in range(1, n):
        y = Y_DLO1T + (Y_DLO0 - Y_DLO1T) * (i / n) ** 1.0
        pts.append(V((y, top_edge(y))))
    pts.append(V((Y_DLO0, top_edge(Y_DLO0))))
    poly = rounded_poly(pts, [0.022, 0.03, 0.07] + [0.0] * (len(pts) - 4) + [0.03], 4)
    return offset_poly(poly, grow) if grow else poly


def pane(y0, y1, ov_top=0.016, ov_bot=0.016, slant_rear=False):
    """glass pane polygon (y, z) between y0..y1 under the DLO top edge (overlaps hidden in the walls)"""
    zb = Z_DLO - ov_bot
    if slant_rear:
        # rear edge follows the C-pillar slant, grown by ov_top
        pts = [V((y0, zb)), V((Y_DLO1 + ov_top, zb)), V((Y_DLO1T + ov_top, top_edge(Y_DLO1T) + ov_top))]
        n = 8
        for i in range(1, n):
            y = Y_DLO1T + (y0 - Y_DLO1T) * i / n
            pts.append(V((y, top_edge(y) + ov_top)))
        pts.append(V((y0, top_edge(y0) + ov_top)))
        return pts
    pts = [V((y0, zb)), V((y1, zb))]
    n = max(2, int((y1 - y0) / 0.08))
    for i in range(n + 1):
        y = y1 + (y0 - y1) * i / n
        pts.append(V((y, top_edge(y) + ov_top)))
    return pts


def panes():
    """{key: polygon}: front door glass, two stretch panes, rear door glass (left side)"""
    # the static stretch panes stop 3 mm short of the door shut lines (their bottom overlap would otherwise sit inside
    # the top of the opening doors); the posts cover their ends
    return {
        "front": pane(Y_DLO0 - 0.016, POSTS[0][0] - 0.003),
        "s1": pane(max(POSTS[0][0] + 0.02, D(2.885) + DOOR_GAP + 0.003), POSTS[1][1] - 0.02),
        "s2": pane(POSTS[1][0] + 0.02, min(POSTS[2][1] - 0.02, Y_C + 0.010 - DOOR_GAP - 0.003)),
        "rear": pane(POSTS[2][1] + 0.003, None, slant_rear=True),
    }


def door_glass_clip(sx):
    """cutter for a door glass = everything outside (side-glass opening shrunk by 3 mm) + (a strip under the straight
    part of the opening's bottom edge, reaching 5 cm down into the door). The door glass then never reaches under
    the roof rail, the sail, the posts or the C-pillar, so it swings out freely; its lower edge stays inside the
    door, which moves with it. (The 3 mm reads as a dark seal between the chrome surround and the glass.)"""
    x0, x1 = (0.40, 1.40) if sx > 0 else (-1.40, -0.40)
    box_ = side_prism(strip_rect(Y_DLO0 - 1.50, Y_DLO1 + 0.30, 0.30, 2.0), x0, x1, "Glass")
    hole = side_prism(dlo_outline(-0.003), x0 - 0.01, x1 + 0.01, "Glass")
    hole2 = side_prism(strip_rect(Y_DLO0 + 0.030, Y_DLO1 - 0.040, Z_DLO - 0.05, Z_DLO + 0.006), x0 - 0.01, x1 + 0.01,
                       "Glass")
    c = boolean(box_, [hole], 'DIFFERENCE', "glass_clip")
    c = boolean(c, [hole2], 'DIFFERENCE', "glass_clip")
    assert len(c.bm.faces) > 0, "door glass clip failed"
    return c


# ---------------------------------------------------------------- doors (y, z)
Z_DOOR_BOT = 0.345
DOOR_GAP = 0.0022        # half gap -> 4.4 mm shut line
DOOR_TOP_CLEAR = Z_DLO + 0.003 + DOOR_GAP + 0.0006   # static trim above a door top starts here (door top + gap)


def door_outlines():
    """front door (driver / passenger shape) and rear door polygons (y, z)"""
    yf0, yf1 = D(1.72), D(2.885)
    ztop = Z_DLO + 0.003
    n = 8
    pts = [V((yf0, Z_DOOR_BOT)), V((yf1, Z_DOOR_BOT)), V((yf1, ztop))]
    for i in range(1, n):
        y = yf1 + (yf0 - yf1) * i / n
        f = smooth((y - D(1.80)) / (D(2.07) - D(1.80)))
        pts.append(V((y, (Z_BELT(y) + 0.004) * (1 - f) + ztop * f)))
    pts.append(V((yf0, Z_BELT(yf0) + 0.004)))
    front = rounded_poly(pts, [0.04, 0.04, 0.008] + [0.0] * (n - 1) + [0.01], 4)
    yr0 = Y_C + 0.010
    # tight inner (concave) corner of the dog-leg: the swing clearance (door_trailing_cutter) follows the outline
    rear = rounded_poly([V((yr0, Z_DOOR_BOT)), V((E(1.72), Z_DOOR_BOT)), V((E(1.72), REAR_STEP_Z)),
                         V((E(1.40), 0.862)), V((E(1.40), ztop)), V((yr0, ztop))],
                        [0.04, 0.04, 0.010, 0.04, 0.008, 0.008], 5)
    return front, rear


# hinge pivots (m, Blender): vertical axis at the max body width, 3 cm ahead of the door front edge
HINGE_F = (D(1.72) - 0.030)
HINGE_R = (Y_C + 0.010 - 0.030)
DOOR_OPEN_DEG = 65.0
REAR_STEP_Z = 0.80       # rear door: height of the dog-leg step (lower trailing edge E(1.72) below, E(1.40) above)
# door slabs reach inwards only to the door wall: the cavity side wall is at HW - DOOR_T (0.885) and the wall above
# the belt slants in to x = 0.841 at the glass line; 0.835 keeps the whole wall on the door without taking cowl/dash
# material (the cowl ahead of the cavity is solid body)
DOOR_X_IN = 0.835


def outline_ymax(poly, z):
    """rearmost y of a closed (y, z) outline on the horizontal line at height z (None if the line misses it)"""
    best = None
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        if abs(a.y - b.y) < 1e-12:
            if abs(a.y - z) < 1e-9:
                yy = max(a.x, b.x)
                best = yy if best is None else max(best, yy)
            continue
        if min(a.y, b.y) - 1e-12 <= z <= max(a.y, b.y) + 1e-12:
            t = (z - a.y) / (b.y - a.y)
            yy = a.x + t * (b.x - a.x)
            best = yy if best is None else max(best, yy)
    return best


def door_trailing_cutter(sx, hinge_y, poly_body, margin=0.0008):
    """swing clearance for a door hinged on a vertical axis at (sx*HW, hinge_y): a sector of a solid of revolution
    around that axis whose inner radius at every height z is the hinge distance of the body jamb behind the door,
    R(z) = rearmost y of the body-side outline (door outline grown by the gap) - hinge_y - margin. Every body point
    behind the door at height z is at least R(z) from the axis, the door keeps only points closer than R(z), and a
    rotation about the axis keeps every point's distance -> the door can never swing into the jamb, its rounded
    corners included. On the outer skin the shut line stays 4.4 mm; only the inner side of the trailing face gets a
    few mm of draft."""
    zs = sorted({round(q.y, 6) for q in poly_body} |
                {round(min(q.y for q in poly_body) + k * 0.02, 6) for k in range(80)})
    zlo, zhi = min(q.y for q in poly_body), max(q.y for q in poly_body)
    prof = []
    for z in zs:
        if z < zlo or z > zhi:
            continue
        y = outline_ymax(poly_body, z)
        if y is not None:
            prof.append((z, y - hinge_y - margin))
    # extend below / above the door so the cutter fully encloses its bottom and top faces
    prof = [(zlo - 0.05, prof[0][1])] + prof + [(zhi + 0.05, prof[-1][1])]
    ro = max(r for _z, r in prof) + 0.45
    loop = [(z, r) for z, r in prof] + [(z, ro) for z, _r in reversed(prof)]
    c = Part("trail")
    bm = c.bm
    K = 64
    rings = []
    for k in range(K + 1):
        ang = math.radians(-40.0 + 110.0 * k / K)          # around +Y, towards the car's inside
        dx, dy = -sx * math.sin(ang), math.cos(ang)
        rings.append([bm.verts.new((sx * HW + dx * r, hinge_y + dy * r, z)) for z, r in loop])
    mi = c.mi("Paint")
    n = len(loop)
    for k in range(K):
        A, B = rings[k], rings[k + 1]
        for j in range(n):
            j2 = (j + 1) % n
            faces_new(bm, (A[j], A[j2], B[j2], B[j]), mi)
    faces_new(bm, rings[0][::-1], mi)
    faces_new(bm, rings[-1], mi)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return c


def side_prism(poly, x0, x1, mat, name="cut"):
    c = Part(name)
    prism(c, [(q.x, q.y) for q in poly], 'X', x0, x1, mat)
    # 'X' axis maps (s, t, a) -> (a, s, t): s = y, t = z
    return c


def face_prism(poly, y0, y1, mat, name="cut"):
    c = Part(name)
    prism(c, [(q.x, q.y) for q in poly], 'Y', y0, y1, mat)
    return c


def seam_z(poly_xy, z0, z1, mat="Body_Inner"):
    c = Part("seam")
    prism(c, [(q.x, q.y) for q in poly_xy], 'Z', z0, z1, mat)
    return c


def strip_rect(a0, a1, b0, b1):
    return [V((a0, b0)), V((a1, b0)), V((a1, b1)), V((a0, b1))]


# front face (x, z) outlines
GRILLE = rounded_poly([V((-0.385, 0.418)), V((0.385, 0.418)), V((0.412, 0.688)), V((-0.412, 0.688))], 0.05, 5)
HEADL = rounded_poly([V((0.468, 0.606)), V((0.752, 0.612)), V((0.862, 0.646)), V((0.880, 0.684)),
                      V((0.880, 0.722)), V((0.468, 0.722))], [0.022, 0.05, 0.03, 0.012, 0.014, 0.022], 4)
VENT = rounded_poly([V((0.585, 0.315)), V((0.790, 0.315)), V((0.830, 0.440)), V((0.640, 0.440))], 0.02, 3)
PLATE_F = rounded_poly(strip_rect(-0.265, 0.265, 0.297, 0.403), 0.012, 3)
HL_DEPTH = 0.055        # headlight bucket: back plate this far behind the skin
HOOD_Z = 0.738          # bonnet front shut line on the face (just above the headlights)
# rear face
TAILBAR = rounded_poly([V((-0.900, 0.888)), V((0.900, 0.888)), V((0.900, 0.936)), V((-0.900, 0.936))], 0.012, 3)
PLATE_R = rounded_poly(strip_rect(-0.280, 0.280, 0.700, 0.832), 0.014, 3)
EXH = rounded_poly(strip_rect(0.515, 0.705, 0.312, 0.366), 0.024, 4)
DIFF = rounded_poly([V((-0.47, 0.300)), V((0.47, 0.300)), V((0.43, 0.378)), V((-0.43, 0.378))], 0.02, 3)
FUEL = (E(0.62), 0.885, 0.074)          # right rear fender: station, height, radius


def mirror_x(poly):
    return [V((-q.x, q.y)) for q in reversed(poly)]


# ---------------------------------------------------------------- mapping onto the (uncut) skin
SKIN = {}


def set_skin_bvh(skin):
    SKIN["bvh"] = BVHTree.FromBMesh(skin.bm)


def hit(origin, direction):
    loc, nor, _i, _d = SKIN["bvh"].ray_cast(V(origin), V(direction).normalized())
    return loc, nor


def map_side(y, z, h, side=1):
    loc, nor = hit((2.5, y, z), (-1, 0, 0))
    if loc is None:
        raise RuntimeError("map_side miss at y=%.3f z=%.3f" % (y, z))
    q = loc + nor * h
    if side < 0:
        q = V((-q.x, q.y, q.z))
    return q


def map_front(x, z, h):
    loc, nor = hit((x, YF - 1.0, z), (0, 1, 0))
    if loc is None:
        raise RuntimeError("map_front miss at x=%.3f z=%.3f" % (x, z))
    return loc + nor * h


def map_rear(x, z, h):
    loc, nor = hit((x, YR + 1.0, z), (0, -1, 0))
    if loc is None:
        raise RuntimeError("map_rear miss at x=%.3f z=%.3f" % (x, z))
    return loc + nor * h


def map_top(x, y, h):
    loc, nor = hit((x, y, 3.0), (0, 0, -1))
    if loc is None:
        raise RuntimeError("map_top miss at x=%.3f y=%.3f" % (x, y))
    return loc + nor * h


def glass_frame(y_bot, y_top):
    pb = V((0.0, y_bot, Z_TOP(y_bot)))
    pt = V((0.0, y_top, Z_TOP(y_top)))
    u = V((1.0, 0.0, 0.0))
    v = (pt - pb).normalized()
    w = u.cross(v)
    if w.z < 0:
        w = -w
    return pb, u, v, w, (pt - pb).length


def map_frame(fr, s, t, h):
    o, u, v, w, _l = fr
    loc, nor = hit(o + u * s + v * t + w * 0.6, -w)
    if loc is None:
        raise RuntimeError("map_frame miss s=%.3f t=%.3f" % (s, t))
    return loc + nor * h


def frame_outline(fr, ys, inset, t_bot, t_top_off, r):
    """windshield/backlight outline in the frame plane from the rail line (A-/C-pillar) inset by `inset`"""
    o, u, v, w, L = fr
    side = []
    for y in ys:
        R = V((HW_RAIL(y) - inset, y, Z_RAIL(y) - 0.01))
        side.append(((R - o).dot(u), (R - o).dot(v)))
    side = [q for q in side if t_bot - 0.05 <= q[1] <= L - t_top_off + 0.05]
    side.sort(key=lambda q: q[1])
    t_top = L - t_top_off

    def s_at(t):
        for a, b in zip(side[:-1], side[1:]):
            if a[1] <= t <= b[1]:
                f = (t - a[1]) / max(b[1] - a[1], 1e-9)
                return a[0] + (b[0] - a[0]) * f
        return side[0][0] if t < side[0][1] else side[-1][0]
    ts = [t_bot + (t_top - t_bot) * i / 10 for i in range(11)]
    left = [V((s_at(t), t)) for t in ts]
    right = [V((-q.x, q.y)) for q in reversed(left)]
    pts = left + right                     # left bottom->top, then right top->bottom (closes along bottom)
    radii = [r] + [0.0] * 9 + [r * 0.8, r * 0.8] + [0.0] * 9 + [r]
    return rounded_poly(pts, radii, 5)


def row_fill(poly, rows=8, col_step=0.12, cols=None):
    """structured grid covering a 2D polygon (rows along the 2nd coord)"""
    tmin = min(q.y for q in poly) + 0.0015
    tmax = max(q.y for q in poly) - 0.0015
    n = len(poly)
    G = []
    ext = []
    for k in range(rows + 1):
        t = tmin + (tmax - tmin) * k / rows
        xs = []
        for i in range(n):
            a, b = poly[i], poly[(i + 1) % n]
            if (a.y - t) * (b.y - t) <= 0 and abs(b.y - a.y) > 1e-12:
                f = (t - a.y) / (b.y - a.y)
                xs.append(a.x + (b.x - a.x) * f)
        ext.append((min(xs), max(xs), t))
    if cols is None:
        cols = max(2, int(max(e[1] - e[0] for e in ext) / col_step) + 1)
    for s0, s1, t in ext:
        G.append([V((s0 + (s1 - s0) * i / cols, t)) for i in range(cols + 1)])
    return G


def patch_shell(p, poly, mapper, h_top, h_bot, mat, rows=8, col_step=0.12):
    G = row_fill(poly, rows, col_step)
    bm = p.bm
    mi = p.mi(mat)
    T = [[bm.verts.new(mapper(q.x, q.y, h_top)) for q in row] for row in G]
    B = [[bm.verts.new(mapper(q.x, q.y, h_bot)) for q in row] for row in G]
    nj, ni = len(G), len(G[0])
    for j in range(nj - 1):
        for i in range(ni - 1):
            faces_new(bm, (T[j][i], T[j][i + 1], T[j + 1][i + 1], T[j + 1][i]), mi)
            faces_new(bm, (B[j][i], B[j + 1][i], B[j + 1][i + 1], B[j][i + 1]), mi)
    loop = [(0, i) for i in range(ni)] + [(j, ni - 1) for j in range(1, nj)] + \
           [(nj - 1, i) for i in range(ni - 2, -1, -1)] + [(j, 0) for j in range(nj - 2, 0, -1)]
    for k in range(len(loop)):
        a, b = loop[k], loop[(k + 1) % len(loop)]
        faces_new(bm, (T[a[0]][a[1]], B[a[0]][a[1]], B[b[0]][b[1]], T[b[0]][b[1]]), mi)
    fs = list({f for row in T + B for v in row for f in v.link_faces})
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    return fs


def band_shell(p, A, Bp, mapper, h_top, h_bot, mat, closed=True):
    """closed shell over the band between 2D polylines A and Bp (same length)"""
    bm = p.bm
    mi = p.mi(mat)
    n = len(A)
    At = [bm.verts.new(mapper(q.x, q.y, h_top)) for q in A]
    Ab = [bm.verts.new(mapper(q.x, q.y, h_bot)) for q in A]
    Bt = [bm.verts.new(mapper(q.x, q.y, h_top)) for q in Bp]
    Bb = [bm.verts.new(mapper(q.x, q.y, h_bot)) for q in Bp]
    fs = []
    for i in range(n if closed else n - 1):
        j = (i + 1) % n
        fs.append(faces_new(bm, (At[i], At[j], Bt[j], Bt[i]), mi))
        fs.append(faces_new(bm, (Ab[i], Bb[i], Bb[j], Ab[j]), mi))
        fs.append(faces_new(bm, (At[i], Ab[i], Ab[j], At[j]), mi))
        fs.append(faces_new(bm, (Bt[i], Bt[j], Bb[j], Bb[i]), mi))
    if not closed:
        fs.append(faces_new(bm, (At[0], Bt[0], Bb[0], Ab[0]), mi))
        fs.append(faces_new(bm, (At[-1], Ab[-1], Bb[-1], Bt[-1]), mi))
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    return fs


def poly_strip(path, w):
    """2D polyline -> (A, B) offset polylines (half width w each side)"""
    A, B = [], []
    n = len(path)
    for i in range(n):
        t = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
        nn = V((-t.y, t.x))
        A.append(path[i] + nn * w)
        B.append(path[i] - nn * w)
    return A, B


def ring_cutter(c, r_in, r_out, x0, x1, mat, nseg=40):
    """annular groove cutter around the X axis through c (local axial along X)"""
    p = Part("ring")
    revolve(p, [(x0, r_in), (x1, r_in), (x1, r_out), (x0, r_out)], nseg, mat, center=c, axis=(1, 0, 0))
    bmesh.ops.recalc_face_normals(p.bm, faces=p.bm.faces)
    return p


# ==============================================================================================
# 6) Body assembly
# ==============================================================================================
def build_body():
    skin, cage = build_skin()
    set_skin_bvh(skin)
    cav = build_cavity()
    log("cavity: %d faces nm %d" % (len(cav.bm.faces), nonmanifold(cav)))
    base = boolean(skin, [cav], 'DIFFERENCE', "Base")
    log("base: %d faces nm %d" % (len(base.bm.faces), nonmanifold(base)))
    front, rear = door_outlines()
    doors = {}
    gaps = []
    for nm, poly, sx in (("Door_Driver", front, 1), ("Door_PassengerFront", front, -1),
                         ("Door_RearL", rear, 1), ("Door_RearR", rear, -1)):
        x0, x1 = (DOOR_X_IN, 1.40) if sx > 0 else (-1.40, -DOOR_X_IN)
        cut_in = side_prism(offset_poly(poly, -DOOR_GAP), x0, x1, "Paint")
        hy = HINGE_F if "Front" in nm or "Driver" in nm else HINGE_R
        d = boolean(base, [cut_in], 'INTERSECT', nm)
        # swing clearance about the hinge (trailing face and rounded corners)
        d = boolean(d, [door_trailing_cutter(sx, hy, offset_poly(poly, DOOR_GAP))], 'DIFFERENCE', nm)
        k = drop_loose_islands(d)
        if k:
            log("%s: cleaned %d sliver faces (loose islands dropped / tiny holes filled)" % (nm, k))
        d.pivot = V((sx * HW, hy, 0.62))
        doors[nm] = d
        # body side of the shut line; on the inside it starts 4 mm further in, so the cowl edge does not touch the door
        gaps.append(side_prism(offset_poly(poly, DOOR_GAP), x0 - 0.004 if sx > 0 else x0, x1 if sx > 0 else x1 + 0.004,
                               "Paint"))
        log("%s: %d faces nm %d" % (nm, len(d.bm.faces), nonmanifold(d)))
    cut = list(gaps) + arch_cutters()
    cut.append(side_prism(dlo_outline(), -1.40, 1.40, "Trim_Black"))
    # windshield + backlight
    fr = glass_frame(D(1.862), D(2.615))
    ws = frame_outline(fr, [D(1.80) + i * 0.02 for i in range(46)], 0.058, 0.018, 0.030, 0.07)
    o, u, v, w, L = fr
    c = Part("ws")
    prism(c, [(q.x, q.y) for q in ws], (u, v, w), -0.16, 0.16, "Trim_Black", origin=o)
    cut.append(c)
    frb = glass_frame(E(0.665), E(1.115))
    bl = frame_outline(frb, [E(1.20) + i * 0.02 for i in range(30)], 0.062, 0.030, 0.035, 0.08)
    o, u, v, w, L = frb
    c = Part("bl")
    prism(c, [(q.x, q.y) for q in bl], (u, v, w), -0.16, 0.16, "Trim_Black", origin=o)
    cut.append(c)
    SKIN["ws"] = (fr, ws)
    SKIN["bl"] = (frb, bl)
    # front face
    yfs = lambda x, z: map_front(x, z, 0.0).y
    ydeep = lambda poly, extra: max(yfs(q.x, q.y) for q in poly) + extra
    cut.append(face_prism(GRILLE, YF - 0.3, max(yfs(0.0, 0.56) + 0.085, ydeep(GRILLE, 0.05)), "Trim_Black"))
    for sgn in (1, -1):
        hl = HEADL if sgn > 0 else mirror_x(HEADL)
        cut.append(face_prism(hl, YF - 0.3, ydeep(hl, HL_DEPTH + 0.02), "Trim_Black"))
        vt = VENT if sgn > 0 else mirror_x(VENT)
        cut.append(face_prism(vt, YF - 0.3, ydeep(vt, 0.05), "Trim_Black"))
    cut.append(face_prism(PLATE_F, YF - 0.3, ydeep(PLATE_F, 0.012), "Satin_Black"))
    # rear face
    yrs = lambda x, z: map_rear(x, z, 0.0).y
    # rear pockets: measured from the most forward point of each outline on the bowed tail (else they end short)
    rdeep = lambda poly, extra: min(yrs(q.x, q.y) for q in poly) - extra
    cut.append(face_prism(TAILBAR, rdeep(TAILBAR, 0.05), YR + 0.3, "Trim_Black"))
    cut.append(face_prism(PLATE_R, rdeep(PLATE_R, 0.014), YR + 0.3, "Satin_Black"))
    for sgn in (1, -1):
        ex = EXH if sgn > 0 else mirror_x(EXH)
        cut.append(face_prism(ex, yrs(sgn * 0.61, 0.34) - 0.10, YR + 0.3, "Trim_Black"))
    cut.append(face_prism(DIFF, rdeep(DIFF, 0.016), YR + 0.3, "Satin_Black"))
    # fuel filler door (right rear fender, groove ring)
    fy, fz, fr_ = FUEL
    fx = map_side(fy, fz, 0.0, -1).x
    cut.append(ring_cutter(V((fx, fy, fz)), fr_ - 0.0022, fr_ + 0.0022, -0.03, 0.03, "Body_Inner"))
    # hood + trunk shut lines (4 mm slots)
    g = 0.002
    HX = 0.772
    for sx in (1, -1):
        cut.append(seam_z(strip_rect(sx * HX - g, sx * HX + g, D(0.05), D(1.782)), HOOD_Z, 1.20))
    cut.append(seam_z(strip_rect(-HX - g, HX + g, D(1.778), D(1.782)), 0.80, 1.20))
    hs = strip_rect(-HX, HX, HOOD_Z, HOOD_Z + 0.004)
    cut.append(face_prism(hs, YF - 0.3, ydeep(hs, 0.03), "Body_Inner"))
    TX = 0.662
    for sx in (1, -1):
        cut.append(seam_z(strip_rect(sx * TX - g, sx * TX + g, E(0.603), YR + 0.3), 0.66, 1.30))
    cut.append(seam_z(strip_rect(-TX - g, TX + g, E(0.603), E(0.599)), 0.95, 1.30))
    cut.append(face_prism(strip_rect(-TX, TX, 0.658, 0.662), yrs(0.0, 0.66) - 0.04, YR + 0.3, "Body_Inner"))
    body = boolean(base, cut, 'DIFFERENCE', "Body")
    log("body: %d faces nm %d" % (len(body.bm.faces), nonmanifold(body)))
    # the front passenger door does not open: it stays part of Body (separate shell, real shut lines)
    merge_part(body, doors.pop("Door_PassengerFront"))
    return body, doors, skin


# ==============================================================================================
# 7) exterior details: glass, posts, chrome, grille, lights, mirrors, plates, wipers, antenna
# ==============================================================================================
def rr_tube(p, outer, inner, y0, y1, mat, mapper=None):
    """closed tube between two 2D outlines (x, z) running along Y from y0 to y1"""
    bm = p.bm
    mi = p.mi(mat)
    rings = []
    for poly, y in ((outer, y0), (outer, y1), (inner, y1), (inner, y0)):
        rings.append([bm.verts.new((q.x, y, q.y)) for q in poly])
    n = len(outer)
    fs = []
    for r in range(4):
        A, B = rings[r], rings[(r + 1) % 4]
        for i in range(n):
            j = (i + 1) % n
            fs.append(faces_new(bm, (A[i], A[j], B[j], B[i]), mi))
    bmesh.ops.recalc_face_normals(bm, faces=fs)


def chevron_bars(cx, cz, w, h, t):
    """abstract emblem: ONE slim upward chevron (two convex parallelograms meeting at the apex), x/z. Deliberately
    not a double chevron and not framed by an oval (that combination is a registered car-maker logo)."""
    out = []
    for sx in (1, -1):
        a = V((cx, cz + h * 0.5))
        b = V((cx + sx * w * 0.5, cz - h * 0.5))
        pts = [a, b, b + V((0, -t)), a + V((0, -t))]
        if sx < 0:
            pts = pts[::-1]
        out.append(pts)
    return out


# mount point on the A-pillar sail (left side, Blender frame). The housing's lower edge (about MIRROR_Z - 0.027) and
# the arm (MIRROR_Z - 0.020) stay above the driver door's top edge (1.000 there), so the opening door swings under
# the mirror instead of through it
MIRROR_Y, MIRROR_Z = D(2.05), 1.036


def mirror_section(ry_f, ry_r, rz, rc, nf=12):
    """closed D-shaped section (y, z): elliptic front half (towards -Y), flat rear face with rounded corners"""
    pts = []
    for k in range(nf + 1):                      # top -> front -> bottom
        t = math.pi / 2 + math.pi * k / nf
        pts.append((ry_f * math.cos(t), rz * math.sin(t)))
    for k in range(4):                           # bottom-rear corner
        t = -math.pi / 2 + (math.pi / 2) * k / 3
        pts.append((ry_r - rc + rc * math.cos(t), -rz + rc + rc * math.sin(t)))
    for k in range(4):                           # top-rear corner
        t = (math.pi / 2) * k / 3
        pts.append((ry_r - rc + rc * math.cos(t), rz - rc + rc * math.sin(t)))
    return pts


def build_mirror(M, q, sgn):
    """aerodynamic door mirror: lofted D-section housing (paint cap, black lower shell), slim arm from the
    sail, mirror glass on the flat rear face, LED indicator along the front-lower edge"""
    rot = Matrix.Rotation(rad(-6.0 * sgn), 3, 'Z')     # toe: outer end swept back

    def P(a, y, z):
        return q + rot @ V((sgn * a, y, z))

    A0, A1 = 0.060, 0.232
    DY, DZ = 0.012, 0.034
    secs = [A0 + (A1 - A0) * f for f in (0.0, 0.06, 0.18, 0.34, 0.52, 0.70, 0.84, 0.93, 0.975, 1.0)]
    rings = []
    meta = []
    for a in secs:
        f = (a - A0) / (A1 - A0)
        sc = se((A1 - a) / 0.032, 2.2) * 0.85 + 0.15 if a > A1 - 0.032 else 1.0
        rz = (0.050 + 0.016 * math.sin(math.pi * min(1.0, f * 1.25)) ** 0.7) * sc
        ry_f = (0.047 + 0.016 * f) * sc
        ry_r = 0.036 * (0.6 + 0.4 * sc)
        rc = min(0.018, 0.4 * rz)
        yc = DY + 0.014 * f * f
        zc = DZ + 0.010 * f
        sec = mirror_section(ry_f, ry_r, rz, rc)
        rings.append([P(a, yc + y, zc + z) for y, z in sec])
        meta.append((yc, zc, rz, ry_r))
    bm = M.bm
    vg = [[bm.verts.new(c) for c in r] for r in rings]
    paint, black = M.mi("Paint"), M.mi("Trim_Black")
    n = len(vg[0])
    for i in range(len(vg) - 1):
        for j in range(n):
            j2 = (j + 1) % n
            zrel = 0.5 * (rings[i][j].z + rings[i][j2].z) - (q.z + meta[i][1])
            faces_new(bm, (vg[i][j], vg[i][j2], vg[i + 1][j2], vg[i + 1][j]), black if zrel < -0.6 * meta[i][2] else paint)
    for ring, flip in ((vg[0], True), (vg[-1], False)):
        c = bm.verts.new(sum((v.co for v in ring), V()) / len(ring))
        for j in range(n):
            tri = (ring[j], ring[(j + 1) % n], c)
            faces_new(bm, tri[::-1] if flip else tri, paint if ring is vg[-1] else black)
    # arm: tapered elliptic blade from inside the sail into the housing's lower half
    arm = []
    for a, ry, rz, zc in ((-0.012, 0.042, 0.020, 0.000), (0.030, 0.034, 0.016, 0.010), (0.090, 0.028, 0.013, DZ - 0.028)):
        arm.append([P(a, DY + 0.004 + ry * math.cos(2 * math.pi * k / 12), zc + rz * math.sin(2 * math.pi * k / 12))
                    for k in range(12)])
    av = add_grid(M, arm, "Trim_Black", closed_u=True)
    faces_new(bm, av[0][::-1], black)
    faces_new(bm, av[-1], black)
    # mirror glass: thin plate on the flat rear face
    g0, g1 = A0 + 0.016, A1 - 0.030
    gl = rounded_poly([V((g0, -0.040)), V((g1, -0.034)), V((g1, 0.046)), V((g0, 0.044))], 0.016, 3)
    fr = lambda s, t, h: P(s, DY + 0.036 + 0.0015 + h + 0.014 * ((s - A0) / (A1 - A0)) ** 2,
                           DZ + 0.010 * (s - A0) / (A1 - A0) + t)
    patch_shell(M, gl, fr, 0.003, -0.001, "Mirror_Glass", 3, 0.04)
    # LED indicator along the front-lower edge of the outer half
    path = []
    for k in range(8):
        a = A0 + 0.085 + (A1 - 0.020 - A0 - 0.085) * k / 7
        f = (a - A0) / (A1 - A0)
        sc = se((A1 - a) / 0.032, 2.2) * 0.85 + 0.15 if a > A1 - 0.032 else 1.0
        rz = (0.050 + 0.016 * math.sin(math.pi * min(1.0, f * 1.25)) ** 0.7) * sc
        ry_f = (0.047 + 0.016 * f) * sc
        t = math.radians(212)
        path.append(P(a, DY + 0.014 * f * f + (ry_f + 0.0012) * math.cos(t), DZ + 0.010 * f + (rz + 0.0012) * math.sin(t)))
    sweep(M, path, [(-0.0035, -0.0020), (0.0035, -0.0020), (0.0035, 0.0020), (-0.0035, 0.0020)], "Indicator",
          up=(0, -0.85, -0.53))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def build_exterior(body, doors):
    P = {n: Part(n) for n in ("Glass", "GlassPrivacy", "Chrome", "Grille", "Lights_Front", "Lights_Rear")}
    DG = {d: Part(d + "_Glass", doors[d].pivot) for d in doors}
    trims = Part("BodyTrims")
    pn = panes()
    GT, GB = -0.0080, -0.0125                      # glass outer / inner offset below the skin
    for side in (1, -1):
        m = (lambda s, t, h, side=side: map_side(s, t, h, side))
        patch_shell(DG["Door_Driver"] if side > 0 else P["Glass"], pn["front"], m, GT, GB, "Glass", 6, 0.10)
        patch_shell(P["GlassPrivacy"], pn["s1"], m, GT, GB, "Glass_Privacy", 6, 0.12)
        patch_shell(P["GlassPrivacy"], pn["s2"], m, GT, GB, "Glass_Privacy", 6, 0.12)
        patch_shell(DG["Door_RearL"] if side > 0 else DG["Door_RearR"], pn["rear"], m, GT, GB,
                    "Glass_Privacy", 6, 0.10)
        # gloss-black pillar posts between the panes (Body). Where a post overlaps a door (B post over the driver
        # door's rear end, C post over the rear door's front end) it starts above the door top + gap, so the
        # opening door does not pass through it
        ye_f = D(2.885) + DOOR_GAP + 0.0005          # driver door trailing edge (+ gap)
        ys_r = Y_C + 0.010 - DOOR_GAP - 0.0005       # rear door leading edge (- gap)
        for y0, y1 in POSTS:
            cuts = sorted({y0, y1} | {y for y in (ye_f, ys_r) if y0 < y < y1})
            for a, b in zip(cuts[:-1], cuts[1:]):
                over_door = (b <= ye_f + 1e-6 and a < ye_f) or (a >= ys_r - 1e-6 and b > ys_r)
                zb_ = DOOR_TOP_CLEAR if over_door else Z_DLO - 0.004
                poly = [V((a, zb_)), V((b, zb_)), V((b, top_edge(b) + 0.004)), V((a, top_edge(a) + 0.004))]
                # over a door the post's depth is offset horizontally (not along the sloped surface normal, which
                # would drop its inner bottom edge ~14 mm into the door top)
                mp = m if not over_door else (lambda s_, t_, h_, side=side: map_side(s_, t_, 0.0, side)
                                              + V((side * h_, 0.0, 0.0)))
                patch_shell(trims, poly, mp, -0.0028, -0.040, "Trim_Black", 4, 0.05)
        # chrome DLO surround (static): open U from the bottom-rear corner around to the bottom-front corner. Both
        # ends sit above door tops (driver / front passenger door, rear doors): they stop at DOOR_TOP_CLEAR
        A = dlo_outline(0.003)
        B = dlo_outline(0.021)
        k0, k1 = 5, 4                       # skip the straight bottom edge (between corner arcs 0 and 1)
        idx = list(range(k0, len(A))) + list(range(0, k1 + 1))
        idx = [i for i in idx if A[i].y >= DOOR_TOP_CLEAR and B[i].y >= DOOR_TOP_CLEAR]
        band_shell(P["Chrome"], [A[i] for i in idx], [B[i] for i in idx], m, 0.0016, -0.0035, "Chrome", closed=False)
        # belt-line chrome: door segments go with the doors
        zb0, zb1 = Z_DLO - 0.021, Z_DLO - 0.0025
        front_door = doors["Door_Driver"] if side > 0 else trims
        rear_door = doors["Door_RearL"] if side > 0 else doors["Door_RearR"]
        segs = [(front_door if side > 0 else P["Chrome"], Y_DLO0 + 0.012, D(2.8795)),
                (P["Chrome"], D(2.8905), Y_C + 0.0055),
                (rear_door, Y_C + 0.0145, Y_DLO1 - 0.012)]
        for tgt, a, b in segs:
            nseg = max(2, int(abs(b - a) / 0.10))
            ys_ = [a + (b - a) * i / nseg for i in range(nseg + 1)]
            band_shell(tgt, [V((y, zb1)) for y in ys_], [V((y, zb0)) for y in ys_], m, 0.0016, -0.0035, "Chrome",
                       closed=False)
        # lower side chrome strip (z 0.405 .. 0.430)
        za, zc = 0.405, 0.430
        segs = [(P["Chrome"], D(1.468), D(1.7145)),
                (front_door if side > 0 else P["Chrome"], D(1.7255), D(2.8795)),
                (P["Chrome"], D(2.8905), Y_C + 0.0055),
                (rear_door, Y_C + 0.0145, E(1.7255))]
        for tgt, a, b in segs:
            path = [V((a + (b - a) * i / 12, 0.5 * (za + zc))) for i in range(13)]
            AA, BB = poly_strip(path, 0.5 * (zc - za))
            band_shell(tgt, AA, BB, m, 0.0022, -0.0030, "Chrome", closed=False)
        # door handles
        for tgt, y0, y1 in ((front_door if side > 0 else P["Chrome"], D(2.60), D(2.80)),
                            (rear_door, E(1.64), E(1.47))):
            ya, yb = min(y0, y1), max(y0, y1)
            poly = rounded_poly([V((ya, 0.876)), V((yb, 0.876)), V((yb, 0.901)), V((ya, 0.901))], 0.011, 3)
            patch_shell(tgt, poly, m, 0.013, -0.004, "Chrome", 2, 0.05)
            # dark finger recess below the handle
            poly = rounded_poly([V((ya + 0.02, 0.868)), V((yb - 0.02, 0.868)), V((yb - 0.02, 0.880)),
                                 V((ya + 0.02, 0.880))], 0.005, 2)
            patch_shell(tgt, poly, m, 0.0012, -0.003, "Trim_Black", 2, 0.05)
    # windshield + backlight glass, black frit (Body)
    for key, tgt, mat in (("ws", P["Glass"], "Glass"), ("bl", P["GlassPrivacy"], "Glass_Privacy")):
        fr, ol = SKIN[key]
        mf = (lambda s, t, h, fr=fr: map_frame(fr, s, t, h))
        patch_shell(tgt, offset_poly(ol, 0.020), mf, GT, GB, mat, 10, 0.10)
        band_shell(trims, offset_poly(ol, 0.014), offset_poly(ol, -0.042), mf, -0.0134, -0.0158, "Trim_Black")
    # cowl panel + wipers
    mt = (lambda s, t, h: map_top(s, t, h))
    patch_shell(trims, rounded_poly([V((-0.765, D(1.786))), V((0.765, D(1.786))), V((0.745, D(1.875))),
                                     V((-0.745, D(1.875)))], 0.02, 2), mt, 0.0025, -0.012, "Satin_Black", 3, 0.10)
    fr, ol = SKIN["ws"]
    for s0, s1 in ((-0.70, -0.06), (0.02, 0.64)):
        path = [map_frame(fr, s0 + (s1 - s0) * i / 10, 0.045 + 0.05 * (i / 10) ** 1.5, 0.004) for i in range(11)]
        sweep(trims, path, [(-0.007, -0.003), (0.007, -0.003), (0.006, 0.005), (-0.006, 0.005)], "Satin_Black",
              up=(0, -0.5, 0.85))
    # antenna fin (body colour)
    ya = E(1.52)
    zr = map_top(0.0, ya, 0.0).z
    fin = []
    for k in range(7):
        f = k / 6.0
        L = 0.175 * (1 - 0.82 * f ** 1.2)
        wd = 0.032 * (1 - 0.75 * f)
        yc = ya + 0.03 * f ** 1.3
        zz = zr - 0.006 + 0.068 * f
        ring = []
        for j in range(10):
            a = 2 * math.pi * j / 10
            ring.append(V((wd * math.sin(a), yc - L * 0.5 * math.cos(a) + 0.02 * (1 - math.cos(a)) * f, zz)))
        fin.append(ring)
    vg = add_grid(trims, fin, "Paint", closed_u=True)
    faces_new(trims.bm, [v for v in vg[0]][::-1], trims.mi("Paint"))
    faces_new(trims.bm, vg[-1], trims.mi("Paint"))
    # licence plates (blank) in their recesses
    for poly, zc, front in ((PLATE_F, 0.350, True), (PLATE_R, 0.766, False)):
        x0, x1 = min(q.x for q in poly), max(q.x for q in poly)
        z0, z1 = min(q.y for q in poly), max(q.y for q in poly)
        mp = map_front if front else map_rear
        depth = 0.012 if front else 0.014
        sgn = 1 if front else -1
        pl = rounded_poly(strip_rect(x0 + 0.012, x1 - 0.012, z0 + 0.008, z1 - 0.008), 0.008, 3)

        def mpl(s, t, h, mp=mp, depth=depth, sgn=sgn):
            q = mp(s, t, 0.0)
            return V((q.x, q.y + sgn * (depth - 0.0045) - sgn * h, q.z))
        patch_shell(trims, pl, mpl, 0.0, -0.004, "Plate", 2, 0.12)
    # ---------------- grille
    G = P["Grille"]
    zg0, zg1 = 0.418, 0.688
    # back plate following the curved, leaning face 6 cm behind the skin (a flat plate would poke through the
    # top corners of the face)
    patch_shell(G, offset_poly(GRILLE, 0.008), (lambda s, t, h: map_front(s, t, 0.0) + V((0, 0.060 - h, 0))), 0.0,
                -0.010, "Satin_Black", 6, 0.08)
    nb = 9
    for k in range(nb):
        z = zg0 + 0.020 + (zg1 - zg0 - 0.040) * k / (nb - 1)
        f = (z - 0.418) / (0.688 - 0.418)
        hw_ = 0.385 + 0.027 * f - 0.028
        path = []
        for i in range(17):
            x = -hw_ + 2 * hw_ * i / 16
            q = map_front(x, z, 0.0)
            path.append(V((x, q.y + 0.010, z)))
        # bars stand 1 cm proud of the leaning face (more would hide the paint above the opening from above)
        sweep(G, path, [(0.0, -0.006), (0.020, -0.005), (0.020, 0.005), (0.0, 0.006)], "Chrome", up=(0, 0, 1))
    for xv in (0.0,):
        path = [V((xv, map_front(xv, z, 0.0).y + 0.016, z)) for z in (zg0 + 0.01, 0.5 * (zg0 + zg1), zg1 - 0.01)]
        sweep(G, path, [(-0.007, 0.0), (0.007, 0.0), (0.007, 0.03), (-0.007, 0.03)], "Chrome", up=(0, 1, 0))
    mfront = (lambda s, t, h: map_front(s, t, h))
    # surround: densified outline - one long quad per straight edge cut a chord through the bowed face (its middle
    # sank under the paint and only the corners showed, as dark "tabs")
    gd = densify(GRILLE, 0.04)
    band_shell(G, offset_poly(gd, 0.0015), offset_poly(gd, 0.030), mfront, 0.0085, -0.008, "Chrome")
    # emblem: chrome-edged black horizontal plaque (square-cut, small corner radius) + one raised chrome chevron
    badge = rounded_poly(strip_rect(-0.066, 0.066, 0.588, 0.636), 0.009, 3)
    fwd = (lambda dy: (lambda s, t, h: map_front(s, t, 0.0) + V((0, -dy - h, 0))))
    patch_shell(G, badge, fwd(0.014), 0.0, -0.008, "Piano_Black", 2, 0.03)
    band_shell(G, offset_poly(badge, -0.001), offset_poly(badge, 0.006), fwd(0.016), 0.0, -0.009, "Chrome")
    for pg in chevron_bars(0.0, 0.613, 0.070, 0.024, 0.0075):
        patch_shell(G, pg, fwd(0.020), 0.0, -0.006, "Chrome", 1, 0.02)
    # chrome lower bumper blade + corner vent surrounds
    path = [V((x, 0.282)) for x in [-0.56 + 1.12 * i / 16 for i in range(17)]]
    AA, BB = poly_strip(path, 0.007)
    band_shell(P["Chrome"], AA, BB, mfront, 0.006, -0.004, "Chrome", closed=False)
    for sgn in (1, -1):
        vt = VENT if sgn > 0 else mirror_x(VENT)
        band_shell(P["Chrome"], offset_poly(vt, 0.001), offset_poly(vt, 0.012), mfront, 0.0045, -0.005, "Chrome")
        # three slim horizontal fins inside the vent (dark chrome)
        for k in range(3):
            z = 0.345 + 0.032 * k
            xa = 0.600 + (0.655 - 0.600) * (z - 0.315) / 0.125
            xb = 0.795 + (0.830 - 0.795) * (z - 0.315) / 0.125
            pth = [V((sgn * (xa + (xb - xa) * i / 6), map_front(sgn * (xa + (xb - xa) * i / 6), z, 0.0).y + 0.02, z))
                   for i in range(7)]
            sweep(P["Grille"], pth, [(0.0, -0.003), (0.020, -0.003), (0.020, 0.003), (0.0, 0.003)], "Chrome",
                  up=(0, 0, 1))
    # ---------------- front lights
    LF, CH, GL = P["Lights_Front"], P["Chrome"], P["Glass"]
    def inset(x, z, d):
        """point on the front skin moved d metres straight back (+Y) - inside the headlight bucket"""
        q = map_front(x, z, 0.0)
        return V((x, q.y + d, z))

    for sgn in (1, -1):
        hl = HEADL if sgn > 0 else mirror_x(HEADL)
        patch_shell(GL, offset_poly(hl, 0.004), mfront, -0.0015, -0.0045, "Glass", 4, 0.03)
        # bucket: dark back plate following the skin HL_DEPTH behind it, satin bezel strip inside the top edge
        patch_shell(trims, offset_poly(hl, 0.006), (lambda s, t, h: inset(s, t, HL_DEPTH - h)), 0.0, -0.006,
                    "Trim_Black", 4, 0.03)
        # DRL light guide ("eyebrow"): along the top edge, round the outer corner and down the outer end
        path = []
        for i in range(16):
            x = 0.500 + (0.846 - 0.500) * i / 15
            path.append(inset(sgn * x, 0.708, 0.016))
        for x, z in ((0.858, 0.703), (0.864, 0.692), (0.865, 0.680)):
            path.append(inset(sgn * x, z, 0.016))
        sweep(LF, path, [(-0.004, -0.0045), (0.006, -0.0045), (0.006, 0.0045), (-0.004, 0.0045)], "Headlight_LED",
              up=(0, 0, 1))
        # vertical DRL blade at the inner end
        path = [inset(sgn * 0.486, z, 0.016) for z in (0.704, 0.680, 0.656, 0.632)]
        sweep(LF, path, [(-0.0035, -0.004), (0.0035, -0.004), (0.0035, 0.004), (-0.0035, 0.004)], "Headlight_LED",
              up=(0, 1, 0))
        # lower accent line
        path = [inset(sgn * x, 0.626, 0.020) for x in [0.512 + 0.22 * i / 8 for i in range(9)]]
        sweep(LF, path, [(-0.003, -0.002), (0.005, -0.002), (0.005, 0.002), (-0.003, 0.002)], "Headlight_LED",
              up=(0, 0, 1))
        # projector modules: chrome bezel (Chrome) + lens (Lights_Front)
        for xp in (0.560, 0.668):
            c = inset(sgn * xp, 0.668, 0.026)
            revolve(CH, [(-0.012, 0.0250), (-0.004, 0.0335), (0.024, 0.0335), (0.024, 0.0250)], 22, "Chrome",
                    center=c, axis=(0, 1, 0))
            revolve(LF, [(-0.010, 0.0), (-0.0098, 0.007), (-0.008, 0.016), (-0.003, 0.0230), (0.004, 0.0250),
                         (0.014, 0.0250), (0.014, 0.0)], 20, "Lens", center=c, axis=(0, 1, 0), closed=False,
                    weld=True)
        # LED high-beam cubes in a chrome strip
        for xp in (0.748, 0.776, 0.804):
            c = inset(sgn * xp, 0.672, 0.026)
            box(LF, c, (0.017, 0.010, 0.017), "Headlight_LED", bev=0.003)
            box(CH, c + V((0, 0.008, 0)), (0.024, 0.008, 0.024), "Chrome", bev=0.003)
        # amber indicator along the rising lower edge at the outer end
        path = [inset(sgn * x, 0.618 + (x - 0.75) * 0.31, 0.014) for x in [0.760 + 0.085 * i / 5 for i in range(6)]]
        sweep(LF, path, [(-0.003, -0.0045), (0.005, -0.0045), (0.005, 0.0045), (-0.003, 0.0045)], "Indicator",
              up=(0, 0, 1))
    # ---------------- rear lights
    LR = P["Lights_Rear"]
    mrear = (lambda s, t, h: map_rear(s, t, h))
    for zc_, hh in ((0.927, 0.0045), (0.903, 0.0105)):
        path = []
        for i in range(41):
            x = -0.884 + 1.768 * i / 40
            q = map_rear(x, zc_, -0.012)
            path.append(q)
        sweep(LR, path, [(-0.005, -hh), (0.005, -hh), (0.005, hh), (-0.005, hh)], "Taillight", up=(0, 0, 1))
    # vertical light blades at both ends (3D look)
    for sgn in (1, -1):
        for k in range(6):
            x = sgn * (0.70 + 0.03 * k)
            q = map_rear(x, 0.912, -0.020)
            box(LR, (q.x, q.y, 0.912), (0.006, 0.010, 0.040), "Taillight")
        rf = rounded_poly(strip_rect(0.79, 0.875, 0.420, 0.452), 0.010, 3)
        rf = rf if sgn > 0 else mirror_x(rf)
        patch_shell(LR, rf, mrear, 0.0025, -0.003, "Reflector", 2, 0.03)
    # third brake light on the roof's rear edge
    path = [map_top(x, E(1.150), 0.003) for x in [-0.26 + 0.52 * i / 8 for i in range(9)]]
    sweep(LR, path, [(-0.012, -0.003), (0.012, -0.003), (0.010, 0.004), (-0.010, 0.004)], "Taillight", up=(0, 0, 1))
    # dark housing behind the bar, following the bowed tail 3 cm inside the skin (a flat plate poked out at the
    # corners)
    patch_shell(trims, offset_poly(TAILBAR, 0.004), (lambda s, t, h: map_rear(s, t, 0.0) - V((0, 0.030 - h, 0))),
                0.0, -0.006, "Trim_Black", 2, 0.06)
    # ---------------- exhaust tips (Chrome)
    for sgn in (1, -1):
        ex = EXH if sgn > 0 else mirror_x(EXH)
        ys = map_rear(sgn * 0.61, 0.34, 0.0).y
        rr_tube(CH, offset_poly(ex, -0.004), offset_poly(ex, -0.011), ys - 0.07, ys + 0.004, "Chrome")
        box(trims, (sgn * 0.61, ys - 0.075, 0.339), (0.17, 0.006, 0.04), "Trim_Black")
    # trunk emblem (one chrome chevron above the plate)
    for pg in chevron_bars(0.0, 0.862, 0.062, 0.020, 0.0065):
        patch_shell(CH, pg, mrear, 0.0035, -0.002, "Chrome", 1, 0.02)
    # ---------------- mirrors (on the A-pillar sail, static -> weld to Body)
    mirrors = {}
    for nm, sgn in (("Mirror_L", 1), ("Mirror_R", -1)):
        q = map_side(MIRROR_Y, MIRROR_Z, 0.0, sgn)
        M = Part(nm, q)
        build_mirror(M, q, sgn)
        mirrors[nm] = M
    merge_part(body, trims)
    for d, g in list(DG.items()):
        sx = 1 if doors[d].pivot.x > 0 else -1
        clipped = boolean(g, [door_glass_clip(sx)], 'DIFFERENCE', g.name)
        assert len(clipped.bm.faces) > 0, d
        clipped.pivot = g.pivot
        DG[d] = clipped
    out = dict(P)
    out.update(DG)
    out.update(mirrors)
    return out


# ==============================================================================================
# 8) wheels (tyre + multi-spoke rim + brake disc; spin) and calipers (steer, no spin)
#    local frame: axle along X, outer face towards +X, centre at the origin (mirrored for the right side)
# ==============================================================================================
NSEG_W = 44                 # tyre + rim revolve segments (sagitta 0.9 mm on the tyre; spokes are separate)


def build_wheel(name, pivot, right):
    p = Part(name, pivot)
    R, rb, w2 = TYRE_R, RIM_R, TYRE_W / 2
    # tyre: sidewall bulge, rounded shoulders, 3 circumferential grooves (tread hint)
    prof = [(-0.104, rb + 0.004), (-0.119, rb + 0.045), (-0.1205, 0.312), (-0.109, R - 0.006), (-0.094, R)]
    for g in (-0.044, 0.0, 0.044):
        prof += [(g - 0.0065, R), (g - 0.0050, R - 0.008), (g + 0.0050, R - 0.008), (g + 0.0065, R)]
    prof += [(0.094, R), (0.109, R - 0.006), (0.1205, 0.312), (0.119, rb + 0.045), (0.104, rb + 0.004)]
    mats = ["Tire_Side"] * 4 + ["Tire"] * (len(prof) - 8) + ["Tire_Side"] * 4
    revolve(p, prof, NSEG_W, "Tire", mats=mats)
    # rim barrel + polished lip
    rim = [(0.096, rb - 0.010), (0.1065, rb + 0.006), (0.1125, rb + 0.014), (0.1095, rb + 0.019),
           (0.0985, rb + 0.006), (-0.100, rb + 0.002), (-0.110, rb + 0.008), (-0.104, rb - 0.012)]
    revolve(p, rim, NSEG_W, "Rim_Silver")
    # 10 spokes (5 split pairs), concave face, chamfered edges
    for k in range(10):
        base = 2 * math.pi * (k // 2) / 5 + (0.105 if k % 2 else -0.105)
        rings = []
        for i, u in enumerate((0.0, 0.33, 0.70, 1.0)):
            r = 0.070 + u * (rb - 0.012 - 0.070)
            phi = base + (0.0 if k % 2 == 0 else 0.0) + (0.06 * u * (1 if k % 2 else -1))
            wd = 0.011 + 0.010 * u
            xf = 0.085 - 0.020 * math.sin(math.pi * u * 0.8) + 0.012 * u
            xb = xf - 0.030
            cs, sn = math.cos(phi), math.sin(phi)
            ring = []
            for lat, x in ((-wd, xb), (wd, xb), (wd, xf - 0.004), (wd * 0.6, xf), (-wd * 0.6, xf), (-wd, xf - 0.004)):
                ring.append(V((x, r * cs - lat * sn, r * sn + lat * cs)))
            rings.append(ring)
        vg = add_grid(p, rings, "Rim_Silver", closed_u=True)
        faces_new(p.bm, vg[0][::-1], p.mi("Rim_Silver"))
        faces_new(p.bm, vg[-1], p.mi("Rim_Silver"))
    # hub, centre cap, 5 lug bolts
    cylinder(p, (0.052, 0, 0), (0.080, 0, 0), 0.074, 30, "Rim_Silver")
    cylinder(p, (0.079, 0, 0), (0.088, 0, 0), 0.034, 24, "Rim_Dark")
    cylinder(p, (0.087, 0, 0), (0.0905, 0, 0), 0.026, 24, "Rim_Silver", r1=0.022)
    for k in range(5):
        a = 2 * math.pi * k / 5 + math.pi / 10
        c = V((0.079, 0.052 * math.cos(a), 0.052 * math.sin(a)))
        cylinder(p, c, c + V((0.010, 0, 0)), 0.0085, 6, "Rim_Dark")
    # brake disc + hat (spins with the wheel)
    revolve(p, [(-0.010, 0.090), (0.020, 0.090), (0.020, 0.180), (-0.010, 0.180)], 28, "Brake_Disc")
    revolve(p, [(0.018, 0.058), (0.054, 0.058), (0.054, 0.092), (0.018, 0.092)], 24, "Rim_Dark")
    bmesh.ops.recalc_face_normals(p.bm, faces=p.bm.faces)
    if right:
        bmesh.ops.scale(p.bm, vec=(-1, 1, 1), verts=p.bm.verts)
        bmesh.ops.reverse_faces(p.bm, faces=p.bm.faces)
    bmesh.ops.translate(p.bm, vec=pivot, verts=p.bm.verts)
    return p


def build_caliper(name, pivot, right):
    p = Part(name, pivot)
    bm = p.bm
    mi = p.mi("Caliper")
    a_c = rad(30)          # behind the axle, 30 deg above horizontal (local +Y = rearwards)
    span = rad(26)
    r0, r1 = 0.128, 0.206
    x0, x1 = -0.034, 0.050
    n = 8
    rings = []
    for i in range(n + 1):
        a = a_c - span + 2 * span * i / n
        ca, sa = math.cos(a), math.sin(a)
        ring = []
        for x, r in ((x0, r0), (x1, r0), (x1 + 0.006, 0.5 * (r0 + r1)), (x1, r1), (x0, r1)):
            ring.append(bm.verts.new((x, r * ca, r * sa)))
        rings.append(ring)
    m = len(rings[0])
    for i in range(n):
        for j in range(m):
            j2 = (j + 1) % m
            faces_new(bm, (rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]), mi)
    faces_new(bm, rings[0][::-1], mi)
    faces_new(bm, rings[-1], mi)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if right:
        bmesh.ops.scale(bm, vec=(-1, 1, 1), verts=bm.verts)
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bmesh.ops.translate(bm, vec=pivot, verts=bm.verts)
    return p


WHEELS = {"Wheel_FL": (TRACK / 2, YAF), "Wheel_FR": (-TRACK / 2, YAF),
          "Wheel_RL": (TRACK / 2, YAR), "Wheel_RR": (-TRACK / 2, YAR)}


def build_wheels():
    out = {}
    for nm, (x, y) in WHEELS.items():
        right = x < 0
        piv = V((x, y, ZA))
        out[nm] = build_wheel(nm, piv, right)
        cn = "Caliper_" + nm.split("_")[1]
        out[cn] = build_caliper(cn, piv, right)
    return out


# ==============================================================================================
# 9) interior: driver cockpit, partition, lounge (side bench + rear bench), bar, ceiling, LEDs
# ==============================================================================================
SEAT_TOP = 0.490            # cushion top above ground (m) = 1.75 studs (R6 rig roots: see manifest anchors)
DRV_X = 0.400               # driver on the car's left (Blender +X = Roblox -X)
DRV_Y = D(2.48)
Z_LFLOOR = Z_FLOOR + 0.045  # lounge carpet top
Z_FFLOOR = Z_FLOOR + 0.025  # front carpet top
STEER_C = V((DRV_X, D(2.115), 0.875))
STEER_TILT = 24.0
STEER_AXIS = V((0.0, math.cos(rad(STEER_TILT)), math.sin(rad(STEER_TILT))))    # towards the driver
SIDE_X0 = -0.885            # side bench (right wall, Blender -X)
SIDE_Y0, SIDE_Y1 = D(3.12), D(5.19)
BAR_Y0, BAR_Y1 = D(3.08), D(5.21)
BAR_Z = 0.705
REAR_Y0, REAR_Y1 = E(1.60), E(1.13)     # rear bench cushion front / back
PART_Y0, PART_Y1 = D(2.965), D(3.035)  # partition wall
SEATS = {}                   # anchor name -> (position m, facing vector) in Blender frame


def rot_x(deg):
    return Matrix.Rotation(rad(deg), 3, 'X')


def rot_z(deg):
    return Matrix.Rotation(rad(deg), 3, 'Z')


def fluted_pad(p, c, size, n, axis, mat, gap=0.006, bev=0.016, rot=None, piping=None, segs=1):
    """cushion split into n flutes along `axis` (0 = x, 1 = y), optional piping strip at the front"""
    c = V(c)
    L = size[axis]
    for k in range(n):
        w = (L - gap * (n - 1)) / n
        off = -L / 2 + w / 2 + k * (w + gap)
        sz = list(size)
        sz[axis] = w
        d = V((0, 0, 0))
        d[axis] = off
        box(p, c + (rot @ d if rot is not None else d), sz, mat, bev=bev, rot=rot, segs=segs)
    # dark base under the flutes (shows in the gaps as stitch lines)
    sz = list(size)
    sz[2] = size[2] * 0.6
    dz = V((0, 0, -size[2] * 0.15))
    box(p, c + (rot @ dz if rot is not None else dz), sz, "Stitch", rot=rot)


def front_seat(p, x, y, mirror=False):
    z = SEAT_TOP
    # base + rails
    box(p, (x, y + 0.02, Z_FFLOOR + 0.08), (0.36, 0.42, 0.14), "Leather_Dark", bev=0.01)
    # cushion with side bolsters
    fluted_pad(p, (x, y, z - 0.055), (0.34, 0.48, 0.11), 5, 1, "Leather", bev=0.014)
    for sx in (-1, 1):
        box(p, (x + sx * 0.235, y, z - 0.045), (0.11, 0.50, 0.13), "Leather", bev=0.03, segs=2)
    # backrest (reclined 18 deg about its lower edge)
    R = rot_x(-18)
    hinge = V((x, y + 0.255, z - 0.02))
    for k, (dz, sz, mat, n) in enumerate(((0.33, (0.33, 0.09, 0.56), "Leather", 6),)):
        fluted_pad(p, hinge + R @ V((0, 0.035, dz)), sz, n, 2, mat, bev=0.014, rot=R)
    for sx in (-1, 1):
        box(p, hinge + R @ V((sx * 0.215, 0.045, 0.30)), (0.10, 0.12, 0.60), "Leather", bev=0.03, segs=2, rot=R)
    box(p, hinge + R @ V((0, 0.085, 0.30)), (0.50, 0.04, 0.62), "Leather_Dark", bev=0.015, rot=R)
    # headrest
    box(p, hinge + R @ V((0, 0.050, 0.70)), (0.27, 0.10, 0.17), "Leather", bev=0.035, segs=2, rot=R)
    for sx in (-1, 1):
        cylinder(p, hinge + R @ V((sx * 0.07, 0.05, 0.60)), hinge + R @ V((sx * 0.07, 0.05, 0.64)), 0.006, 6, "Alu")


def build_interior_front():
    p = Part("Interior_Front")
    # carpet + toe board + firewall cover
    box(p, (0.0, 0.5 * (D(1.86) + PART_Y0), Z_FLOOR + 0.0125), (1.68, PART_Y0 - D(1.86), 0.025), "Carpet")
    toe = [V((D(1.70) + 0.005, Z_FLOOR)), V((D(1.86), Z_FLOOR)), V((D(1.86), Z_FFLOOR)), V((D(1.74), 0.42)),
           V((D(1.70) + 0.005, 0.42))]
    prism(p, [(q.x, q.y) for q in toe], 'X', -0.84, 0.84, "Carpet")
    # dashboard: one swept section across the car
    dash = [V((D(1.715), 0.50)), V((D(1.98), 0.52)), V((D(2.07), 0.60)), V((D(2.105), 0.70)),
            V((D(2.10), 0.82)), V((D(2.06), 0.905)), V((D(1.97), 0.948)), V((D(1.82), 0.955)),
            V((D(1.715), 0.945))]
    dash = rounded_poly(dash, [0.0, 0.03, 0.04, 0.02, 0.03, 0.05, 0.04, 0.0, 0.0], 3)
    # ends 7 mm inside the driver door's inner edge (DOOR_X_IN): the dash top reaches into the cowl skin, which on the
    # left is partly the door's cowl lip
    prism(p, [(q.x, q.y) for q in dash], 'X', -(DOOR_X_IN - 0.007), DOOR_X_IN - 0.007, "Leather_Dark")
    # wood + aluminium band across the dash face
    band = rounded_poly([V((D(2.085), 0.66)), V((D(2.112), 0.66)), V((D(2.116), 0.715)), V((D(2.090), 0.715))], 0.004, 2)
    prism(p, [(q.x, q.y) for q in band], 'X', -0.80, 0.80, "Wood")
    prism(p, [(D(2.096), 0.716), (D(2.118), 0.716), (D(2.118), 0.724), (D(2.096), 0.724)], 'X', -0.80, 0.80, "Alu")
    # air vents (chrome slats)
    for xv in (-0.60, -0.16, 0.16, 0.60):
        box(p, (xv, D(2.110), 0.775), (0.16, 0.020, 0.050), "Piano_Black", bev=0.006)
        for k in range(3):
            box(p, (xv, D(2.121), 0.760 + 0.015 * k), (0.15, 0.006, 0.004), "Alu")
    # two screens: driver cluster + centre screen (emissive UI)
    for (cx, cz, w, h, tilt) in ((DRV_X, 0.900, 0.31, 0.115, 12), (0.0, 0.840, 0.30, 0.17, 20)):
        R = rot_x(tilt)
        c = V((cx, D(2.085), cz))
        box(p, c, (w + 0.02, 0.024, h + 0.02), "Piano_Black", bev=0.006, rot=R)
        box(p, c + R @ V((0, 0.0125, 0)), (w, 0.003, h), "Screen", rot=R)
        # UI elements: dials / bars
        if w > 0.30:
            for k, dx in enumerate((-0.09, 0.09)):
                revolve(p, [(-0.0005, 0.032), (0.0015, 0.032), (0.0015, 0.040), (-0.0005, 0.040)], 24, "Screen_UI",
                        center=c + R @ V((dx, 0.0145, 0.0)), axis=R @ V((0, 1, 0)))
        else:
            for k in range(3):
                box(p, c + R @ V((-0.06 + 0.06 * k, 0.0145, 0.03)), (0.05, 0.002, 0.04), "Screen_UI", rot=R)
            box(p, c + R @ V((0.0, 0.0145, -0.045)), (0.22, 0.002, 0.018), "Screen_UI", rot=R)
    # steering column (static) + instrument hood
    col0 = STEER_C - STEER_AXIS * 0.30
    cylinder(p, col0, STEER_C - STEER_AXIS * 0.05, 0.032, 12, "Piano_Black")
    box(p, (DRV_X, D(2.035), 0.940), (0.36, 0.12, 0.05), "Leather_Dark", bev=0.02, segs=2)
    # centre console with gear selector and cup holders
    box(p, (0.0, 0.5 * (D(2.05) + D(2.86)), 0.40), (0.24, D(2.86) - D(2.05), 0.36), "Leather_Dark", bev=0.02, segs=2)
    box(p, (0.0, D(2.40), 0.585), (0.22, 0.42, 0.012), "Piano_Black", bev=0.004)
    box(p, (0.0, D(2.72), 0.615), (0.21, 0.26, 0.07), "Leather", bev=0.025, segs=2)
    cylinder(p, (0.0, D(2.30), 0.59), (0.0, D(2.30), 0.625), 0.022, 16, "Alu")
    box(p, (0.0, D(2.30), 0.655), (0.040, 0.060, 0.050), "Alu", bev=0.016, segs=2)
    for dx in (-0.05, 0.05):
        revolve(p, [(-0.002, 0.030), (0.002, 0.030), (0.002, 0.036), (-0.002, 0.036)], 20, "Alu",
                center=(dx, D(2.50), 0.592), axis=(0, 0, 1))
        cylinder(p, (dx, D(2.50), 0.560), (dx, D(2.50), 0.5915), 0.029, 16, "Piano_Black")
    # pedals
    for dx, w in ((0.05, 0.10), (-0.10, 0.06)):
        box(p, (DRV_X + dx, D(1.84), 0.30), (w, 0.02, 0.07), "Alu", bev=0.004, rot=rot_x(-30))
    # seats
    front_seat(p, DRV_X, DRV_Y)
    front_seat(p, -DRV_X, DRV_Y)
    # door sill plates (front)
    for sx in (1, -1):
        box(p, (sx * 0.86, 0.5 * (D(1.76) + D(2.86)), Z_FLOOR + 0.03), (0.06, D(2.86) - D(1.76), 0.012), "Alu")
    SEATS["DriverSeat"] = (V((DRV_X, DRV_Y, SEAT_TOP)), V((0, -1, 0)))
    SEATS["FrontPassengerSeat"] = (V((-DRV_X, DRV_Y, SEAT_TOP)), V((0, -1, 0)))
    return p


def build_steering_wheel():
    p = Part("SteeringWheel", STEER_C)
    u, v, w = frame_from(STEER_AXIS)
    R0 = 0.185
    ring = [STEER_C + (u * math.cos(2 * math.pi * k / 36) + v * math.sin(2 * math.pi * k / 36)) * R0 for k in range(36)]
    sweep(p, ring, circle_prof(0.016, 8, 1.0, 1.25), "Leather_Dark", closed_path=True, up=tuple(STEER_AXIS))
    # 3 spokes (left, right, bottom) + hub
    for a in (0.0, math.pi, -math.pi / 2):
        d = u * math.cos(a) + v * math.sin(a)
        c = STEER_C + d * 0.105 - STEER_AXIS * 0.012
        Rm = Matrix((u, v, w)).transposed()
        rot = Rm @ Matrix.Rotation(a, 3, 'Z')
        box(p, c, (0.15, 0.035, 0.016), "Alu" if a != -math.pi / 2 else "Leather_Dark", bev=0.006, rot=rot)
    cylinder(p, STEER_C - STEER_AXIS * 0.03, STEER_C + STEER_AXIS * 0.012, 0.058, 20, "Leather_Dark")
    cylinder(p, STEER_C + STEER_AXIS * 0.011, STEER_C + STEER_AXIS * 0.016, 0.022, 16, "Alu")
    return p


def cavity_outline_at(y, shrink=0.006):
    h = cavity_half(y)
    full = [V((x, z)) for x, z in h] + [V((-x, z)) for x, z in reversed(h[1:-1])]
    return offset_poly(full, -shrink)


def bench_side(p):
    """long side-facing bench on the right wall (Blender -X), 3 seats facing +X"""
    y0, y1 = SIDE_Y0, SIDE_Y1
    L = y1 - y0
    xb = SIDE_X0
    # plinth with toe-kick recess
    box(p, (xb + 0.215, 0.5 * (y0 + y1), 0.5 * (Z_LFLOOR + 0.335)), (0.43, L, 0.335 - Z_LFLOOR), "Leather_Dark",
        bev=0.01)
    box(p, (xb + 0.44, 0.5 * (y0 + y1), Z_LFLOOR + 0.025), (0.03, L - 0.04, 0.05), "Piano_Black")
    # 3 cushions, fluted along y
    for k in range(3):
        yc = y0 + L * (k + 0.5) / 3
        fluted_pad(p, (xb + 0.255, yc, SEAT_TOP - 0.075), (0.46, L / 3 - 0.012, 0.15), 6, 1, "Leather", bev=0.018)
        SEATS["Side%d" % k] = (V((xb + 0.27, yc, SEAT_TOP)), V((1, 0, 0)))
    # piping along the front edge
    sweep(p, [V((xb + 0.487, y0 + 0.02, SEAT_TOP - 0.02)), V((xb + 0.487, y1 - 0.02, SEAT_TOP - 0.02))],
          circle_prof(0.006, 6), "Stitch", up=(0, 0, 1))
    # backrest against the wall: 3 pads, vertical flutes, reclined 10 deg
    R = Matrix.Rotation(rad(10), 3, 'Y')
    for k in range(3):
        yc = y0 + L * (k + 0.5) / 3
        fluted_pad(p, (xb + 0.075, yc, 0.735), (0.10, L / 3 - 0.02, 0.44), 4, 1, "Leather", bev=0.026, rot=R, segs=2)
    box(p, (xb + 0.035, 0.5 * (y0 + y1), 0.74), (0.05, L, 0.50), "Leather_Dark", bev=0.01)
    # end armrests
    for ya in (y0 - 0.06, y1 + 0.06):
        box(p, (xb + 0.24, ya, 0.53), (0.46, 0.11, 0.38), "Leather_Dark", bev=0.03, segs=2)
        box(p, (xb + 0.24, ya, 0.725), (0.44, 0.10, 0.03), "Wood", bev=0.01)


def bench_rear(p, pw):
    """forward-facing rear bench between the wheelhouses: 3 seats, armrests on the wheelhouse humps. The pieces that
    reach over the wheelhouses (armrest blocks, backrest back panel) go into pw, which is clipped to the cabin"""
    y0, y1 = REAR_Y0, REAR_Y1
    hw = REAR_WELL_X - 0.045
    box(p, (0.0, 0.5 * (y0 + y1) + 0.02, 0.5 * (Z_LFLOOR + 0.34)), (2 * hw, y1 - y0 - 0.04, 0.34 - Z_LFLOOR),
        "Leather_Dark", bev=0.01)
    for k, x in enumerate((0.40, 0.0, -0.40)):
        fluted_pad(p, (x, 0.5 * (y0 + y1), SEAT_TOP - 0.075), (0.385, y1 - y0, 0.15), 5, 0, "Leather", bev=0.018)
        SEATS["Rear%d" % k] = (V((x, 0.5 * (y0 + y1) - 0.02, SEAT_TOP)), V((0, -1, 0)))
    sweep(p, [V((-hw + 0.02, y0 - 0.005, SEAT_TOP - 0.02)), V((hw - 0.02, y0 - 0.005, SEAT_TOP - 0.02))],
          circle_prof(0.006, 6), "Stitch", up=(0, 0, 1))
    # backrest (reclined 22 deg) + headrests
    R = rot_x(-22)
    hinge = V((0.0, y1 - 0.02, SEAT_TOP - 0.02))
    for k, x in enumerate((0.40, 0.0, -0.40)):
        fluted_pad(p, hinge + R @ V((x, 0.04, 0.27)), (0.385, 0.10, 0.48), 5, 0, "Leather", bev=0.02, rot=R)
        box(p, hinge + R @ V((x, 0.05, 0.60)), (0.26, 0.10, 0.15), "Leather", bev=0.035, segs=2, rot=R)
    box(pw, hinge + R @ V((0, 0.10, 0.30)), (2 * hw + 0.30, 0.06, 0.66), "Leather_Dark", bev=0.015, rot=R)
    # armrests on the wheelhouse humps (+ cup holders)
    for sx in (1, -1):
        cx = sx * (hw + 0.135)
        box(pw, (cx, 0.5 * (y0 + y1) + 0.03, 0.58), (0.27, y1 - y0 + 0.05, 0.56), "Leather_Dark", bev=0.03, segs=2)
        box(p, (cx, 0.5 * (y0 + y1) + 0.03, 0.865), (0.25, y1 - y0 + 0.03, 0.02), "Wood", bev=0.008)
        for dy in (-0.07, 0.07):
            c = V((cx, 0.5 * (y0 + y1) + dy, 0.876))
            revolve(p, [(-0.002, 0.030), (0.002, 0.030), (0.002, 0.036), (-0.002, 0.036)], 18, "Alu", center=c,
                    axis=(0, 0, 1))
    # parcel shelf behind the backrest (covers the trunk void)
    box(p, (0.0, 0.5 * (y1 + E(0.665)) + 0.05, 1.035), (1.40, E(0.665) - y1 - 0.08, 0.02), "Leather_Dark")


def build_interior_lounge():
    p = Part("Interior_Lounge")
    pw = Part("lounge_over_wheelhouses")
    # carpet floor
    box(pw, (0.0, 0.5 * (PART_Y1 + E(1.02)), Z_FLOOR + 0.0225), (1.70, E(1.02) - PART_Y1, 0.045), "Carpet")
    # rear door sill plates
    for sx in (1, -1):
        box(p, (sx * 0.855, 0.5 * (Y_C + 0.02 + E(1.70)), Z_LFLOOR + 0.006), (0.07, E(1.70) - Y_C - 0.02, 0.012), "Alu")
    bench_side(p)
    bench_rear(p, pw)
    # nothing of the lounge may reach into the rear wheel wells (seen through the arch from outside): carpet, armrest
    # blocks and the backrest panel are clipped by a cylinder 1.5 cm inside the 3.5 cm wheelhouse wall, so the cut
    # faces stay hidden in that wall and the armrests sit on the humps
    whs = []
    for sx in (1, -1):
        c = Part("wh")
        cylinder(c, (sx * (REAR_WELL_X - 0.015), YAR, ZA), (sx * 1.6, YAR, ZA), ARCH_R + 0.015, 56, "Carpet")
        whs.append(c)
    merge_part(p, boolean(pw, whs, 'DIFFERENCE', "lounge_over_wheelhouses", self_check=True))
    # partition: wall clipped to the cabin section, with a window and a TV (screen faces the lounge)
    wall = Part("partition")
    prism(wall, [(q.x, q.y) for q in cavity_outline_at(0.5 * (PART_Y0 + PART_Y1))], 'Y', PART_Y0, PART_Y1,
          "Leather_Dark")
    win = Part("pwin")
    prism(win, [(q.x, q.y) for q in rounded_poly(strip_rect(0.06, 0.60, 1.00, 1.31), 0.03, 4)], 'Y',
          PART_Y0 - 0.1, PART_Y1 + 0.1, "Piano_Black")
    wall = boolean(wall, [win], 'DIFFERENCE', "partition")
    merge_part(p, wall)
    # wood band on the lounge face + TV
    box(p, (0.0, PART_Y1 + 0.006, 0.86), (1.56, 0.012, 0.06), "Wood", bev=0.004)
    tv_c = V((-0.36, PART_Y1 + 0.02, 1.155))
    box(p, tv_c, (0.58, 0.028, 0.34), "Piano_Black", bev=0.006)
    box(p, tv_c + V((0, 0.0145, 0)), (0.55, 0.002, 0.31), "Screen")
    for k in range(4):
        box(p, tv_c + V((-0.19 + 0.127 * k, 0.0160, 0.04)), (0.11, 0.002, 0.15), "Screen_UI")
    box(p, tv_c + V((0.0, 0.0160, -0.10)), (0.48, 0.002, 0.03), "Screen_UI")
    # lower partition cabinet + small control panel
    box(p, (0.0, PART_Y1 + 0.09, 0.42), (1.50, 0.18, 0.37), "Leather_Dark", bev=0.015)
    box(p, (0.0, PART_Y1 + 0.181, 0.42), (1.30, 0.004, 0.24), "Wood", bev=0.002)
    box(p, (0.25, PART_Y1 + 0.186, 0.52), (0.16, 0.004, 0.05), "Screen_UI")
    # ceiling: star panel framed in piano black (stars + LEDs are separate emissive parts)
    zc = Z_TOP(Y_MID) - WALL - 0.035
    box(p, (0.0, 0.5 * (D(3.10) + E(1.32)), zc + 0.008), (1.18, E(1.32) - D(3.10), 0.016), "Headliner")
    for sx in (1, -1):
        box(p, (sx * 0.605, 0.5 * (D(3.10) + E(1.32)), zc - 0.004), (0.05, E(1.32) - D(3.10), 0.03), "Piano_Black",
            bev=0.006)
    for yy in (D(3.10), E(1.32)):
        box(p, (0.0, yy, zc - 0.004), (1.26, 0.05, 0.03), "Piano_Black", bev=0.006)
    # reading lights above the rear bench
    for sx in (1, -1):
        cylinder(p, (sx * 0.40, E(1.42), zc + 0.004), (sx * 0.40, E(1.42), zc - 0.006), 0.03, 12, "Alu")
    return p


def build_interior_bar():
    p = Part("Interior_Bar")
    x0, x1 = 0.885, 0.50
    L = BAR_Y1 - BAR_Y0
    yc = 0.5 * (BAR_Y0 + BAR_Y1)
    # cabinet: piano black front with wood inlay panels
    box(p, (0.5 * (x0 + x1), yc, 0.5 * (Z_LFLOOR + BAR_Z - 0.03)), (x0 - x1, L, BAR_Z - 0.03 - Z_LFLOOR),
        "Piano_Black", bev=0.008)
    for k in range(4):
        y = BAR_Y0 + L * (k + 0.5) / 4
        box(p, (x1 - 0.002, y, 0.47), (0.006, L / 4 - 0.05, 0.30), "Wood", bev=0.003)
        box(p, (x1 - 0.008, y, 0.60), (0.008, 0.12, 0.012), "Alu", bev=0.003)
    # counter top (overhang = LED lip) + mirrored back panel
    box(p, (0.5 * (x0 + x1) - 0.02, yc, BAR_Z - 0.012), (x0 - x1 + 0.04, L + 0.02, 0.024), "Piano_Black", bev=0.008)
    box(p, (0.865, yc, 0.5 * (BAR_Z + 0.975)), (0.02, L, 0.975 - BAR_Z), "Mirror_Glass")
    box(p, (0.858, yc, 0.978), (0.05, L + 0.02, 0.012), "Alu", bev=0.004)
    top = BAR_Z
    # glass rack with 6 tumblers
    gy0 = BAR_Y0 + 0.12
    box(p, (0.70, gy0 + 0.16, top + 0.006), (0.22, 0.34, 0.012), "Alu", bev=0.004)
    tumbler = [(0.0, 0.0), (0.0, 0.031), (0.004, 0.034), (0.090, 0.036), (0.090, 0.031), (0.012, 0.028),
               (0.012, 0.0)]
    for i in range(3):
        for j in range(2):
            c = V((0.65 + 0.10 * j, gy0 + 0.055 + 0.105 * i, top + 0.012))
            revolve(p, tumbler, 16, "Bar_Glass", center=c, axis=(0, 0, 1), closed=False, weld=True)
    # two water carafes
    carafe = [(0.0, 0.0), (0.0, 0.050), (0.012, 0.058), (0.120, 0.060), (0.170, 0.040), (0.215, 0.022),
              (0.250, 0.022), (0.262, 0.027), (0.266, 0.021), (0.236, 0.017), (0.200, 0.018), (0.160, 0.035),
              (0.115, 0.054), (0.016, 0.052), (0.008, 0.0)]
    water = [(0.0, 0.0), (0.0, 0.048), (0.110, 0.0505), (0.140, 0.045), (0.140, 0.0)]
    for y in (BAR_Y0 + 0.70, BAR_Y0 + 1.52):
        c = V((0.69, y, top))
        revolve(p, carafe, 20, "Bar_Glass", center=c, axis=(0, 0, 1), closed=False, weld=True)
        revolve(p, water, 20, "Water", center=c + V((0, 0, 0.018)), axis=(0, 0, 1), closed=False, weld=True)
    # ice bucket (polished) with ice cubes
    c = V((0.69, BAR_Y0 + 1.10, top))
    bucket = [(0.0, 0.0), (0.0, 0.074), (0.165, 0.090), (0.178, 0.094), (0.180, 0.086), (0.168, 0.082),
              (0.030, 0.066), (0.030, 0.0)]
    revolve(p, bucket, 24, "Alu", center=c, axis=(0, 0, 1), closed=False, weld=True)
    rnd = random.Random(7)
    for k in range(14):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(0.0, 0.050)
        cc = c + V((r * math.cos(a), r * math.sin(a), 0.135 + rnd.uniform(-0.01, 0.025)))
        box(p, cc, (0.032, 0.032, 0.030), "Ice", bev=0.006, rot=Matrix.Rotation(rnd.uniform(0, 1.5), 3, (1, 1, 0.3)))
    # tongs + small tray
    box(p, (0.80, BAR_Y0 + 1.10, top + 0.006), (0.10, 0.32, 0.012), "Alu", bev=0.004)
    # cup holders (recessed look: chrome rings + dark wells)
    for y in (BAR_Y1 - 0.30, BAR_Y1 - 0.18):
        for x in (0.62, 0.76):
            revolve(p, [(-0.002, 0.033), (0.003, 0.033), (0.003, 0.040), (-0.002, 0.040)], 20, "Alu",
                    center=(x, y, top + 0.001), axis=(0, 0, 1))
            cylinder(p, (x, y, top - 0.003), (x, y, top + 0.0012), 0.032, 16, "Piano_Black")
    # small control panel at the rear end
    box(p, (0.70, BAR_Y1 - 0.05, top + 0.02), (0.24, 0.06, 0.04), "Piano_Black", bev=0.01, rot=rot_x(-25))
    box(p, (0.70, BAR_Y1 - 0.065, top + 0.03), (0.20, 0.004, 0.022), "Screen_UI", rot=rot_x(-25))
    return p


def build_doors_interior(doors):
    """door cards on the inside of the opening doors"""
    for nm, d in doors.items():
        sx = 1 if d.pivot.x > 0 else -1
        xi = sx * (HW - DOOR_T)
        if nm == "Door_Driver":
            y0, y1 = D(1.80), D(2.84)
        else:
            y0, y1 = Y_C + 0.06, E(1.78)
        yc = 0.5 * (y0 + y1)
        Ld = y1 - y0
        box(d, (xi - sx * 0.010, yc, 0.62), (0.020, Ld, 0.50), "Leather_Dark", bev=0.006)
        box(d, (xi - sx * 0.040, yc + 0.08 * (1 if nm == "Door_Driver" else -1), 0.635), (0.06, Ld * 0.55, 0.05),
            "Leather", bev=0.02, segs=2)
        box(d, (xi - sx * 0.024, yc, 0.80), (0.010, Ld - 0.04, 0.035), "Wood", bev=0.004)
        box(d, (xi - sx * 0.030, yc, 0.822), (0.010, Ld - 0.04, 0.008), "Alu")
        hy = y0 + 0.14 if nm == "Door_Driver" else y0 + 0.12
        box(d, (xi - sx * 0.035, hy, 0.735), (0.03, 0.10, 0.025), "Alu", bev=0.008)
        c = V((xi - sx * 0.022, y0 + 0.22, 0.42))
        revolve(d, [(-0.004, 0.0), (-0.004, 0.065), (0.006, 0.065), (0.006, 0.0)], 20, "Alu", center=c,
                axis=(sx, 0, 0), closed=False, weld=True)


def build_ambient():
    """Ambient_LED (strips) and StarLights (ceiling stars): emissive parts the game can light as Neon"""
    led = Part("Ambient_LED")
    stars = Part("StarLights")
    prof = [(-0.005, -0.003), (0.005, -0.003), (0.005, 0.003), (-0.005, 0.003)]
    zc = Z_TOP(Y_MID) - WALL - 0.035
    ya, yb = D(3.13), E(1.35)
    # ceiling: lines along the inner edges of the piano-black frame + cross lines
    for sx in (1, -1):
        sweep(led, [V((sx * 0.575, ya, zc - 0.012)), V((sx * 0.575, yb, zc - 0.012))], prof, "LED", up=(0, 0, 1))
        # roof side rails above the windows
        x = sx * (HW_RAIL(Y_MID) - 0.06)
        sweep(led, [V((x, PART_Y1 + 0.03, Z_RAIL(Y_MID) - 0.055)), V((x, E(1.30), Z_RAIL(Y_MID) - 0.055))], prof, "LED",
              up=(0, 0, 1))
    for yy in (ya, yb):
        sweep(led, [V((-0.575, yy, zc - 0.012)), V((0.575, yy, zc - 0.012))], prof, "LED", up=(0, 0, 1))
    # bar: under the counter lip and along the top of the mirrored back panel
    sweep(led, [V((0.478, BAR_Y0 + 0.02, BAR_Z - 0.028)), V((0.478, BAR_Y1 - 0.02, BAR_Z - 0.028))], prof, "LED",
          up=(0, 0, 1))
    sweep(led, [V((0.852, BAR_Y0 + 0.02, 0.968)), V((0.852, BAR_Y1 - 0.02, 0.968))], prof, "LED", up=(0, 0, 1))
    # toe-kick under the side bench, along the floor edge
    sweep(led, [V((SIDE_X0 + 0.452, SIDE_Y0 + 0.03, Z_LFLOOR + 0.008)), V((SIDE_X0 + 0.452, SIDE_Y1 - 0.03,
                                                                          Z_LFLOOR + 0.008))], prof, "LED", up=(0, 0, 1))
    sweep(led, [V((0.478, BAR_Y0 + 0.03, Z_LFLOOR + 0.008)), V((0.478, BAR_Y1 - 0.03, Z_LFLOOR + 0.008))], prof, "LED",
          up=(0, 0, 1))
    # partition: frame around the lounge side (wood band) + under the rear bench front
    sweep(led, [V((-0.78, PART_Y1 + 0.004, 0.83)), V((0.78, PART_Y1 + 0.004, 0.83))], prof, "LED", up=(0, 0, 1))
    hw = REAR_WELL_X - 0.05
    sweep(led, [V((-hw, REAR_Y0 + 0.012, Z_LFLOOR + 0.012)), V((hw, REAR_Y0 + 0.012, Z_LFLOOR + 0.012))], prof, "LED",
          up=(0, 0, 1))
    # stars: small octahedra scattered over the panel (fixed seed)
    rnd = random.Random(42)
    n = 0
    while n < 150:
        x = rnd.uniform(-0.54, 0.54)
        y = rnd.uniform(ya + 0.04, yb - 0.04)
        r = rnd.choice((0.0035, 0.0045, 0.006))
        c = V((x, y, zc - 0.0005))
        bm = stars.bm
        # tetrahedron: flat triangle up (hidden in the panel), apex pointing down into the cabin. Faces are wound
        # outwards explicitly (no recalc: the islands are far smaller than the recalc heuristic likes)
        ph = rnd.uniform(0.0, 2 * math.pi / 3)
        top = [c + V((r * 1.15 * math.cos(ph + 2 * math.pi * k / 3), r * 1.15 * math.sin(ph + 2 * math.pi * k / 3),
                      r * 0.5)) for k in range(3)]
        vv = [bm.verts.new(q) for q in top] + [bm.verts.new(c + V((0, 0, -r * 0.9)))]
        mi = stars.mi("Star")
        faces_new(bm, (vv[0], vv[1], vv[2]), mi)                 # CCW seen from above -> normal up
        for a in range(3):
            faces_new(bm, (vv[(a + 1) % 3], vv[a], vv[3]), mi)
        n += 1
    return led, stars


def build_interior(doors, extra_privacy):
    parts = {"Interior_Front": build_interior_front(), "SteeringWheel": build_steering_wheel(),
             "Interior_Lounge": build_interior_lounge(), "Interior_Bar": build_interior_bar()}
    led, stars = build_ambient()
    parts["Ambient_LED"] = led
    parts["StarLights"] = stars
    build_doors_interior(doors)
    # partition window glass (privacy, static)
    pw = rounded_poly(strip_rect(0.06, 0.60, 1.00, 1.31), 0.03, 4)
    prism(extra_privacy, [(q.x, q.y) for q in offset_poly(pw, 0.012)], 'Y', 0.5 * (PART_Y0 + PART_Y1) - 0.003,
          0.5 * (PART_Y0 + PART_Y1) + 0.003, "Glass_Privacy")
    return parts


# ===MAIN===
# ==============================================================================================
# 10) build everything (metres), then finish: triangulate, normals, smoothing, vertex colours, studs
# ==============================================================================================
bpy.ops.wm.read_factory_settings(use_empty=True)
make_materials()
log("building body")
BODY, DOORS, SKIN_PART = build_body()
log("exterior details")
EXT = build_exterior(BODY, DOORS)
log("wheels")
WHL = build_wheels()
log("interior")
INT = build_interior(DOORS, EXT["GlassPrivacy"])
PARTS = {}
for p in [BODY] + list(DOORS.values()) + list(EXT.values()) + list(WHL.values()) + list(INT.values()):
    PARTS[p.name] = p

ORDER = ["Body", "Glass", "GlassPrivacy", "Chrome", "Grille", "Lights_Front", "Lights_Rear", "Mirror_L", "Mirror_R",
         "Door_Driver", "Door_Driver_Glass", "Door_RearL", "Door_RearL_Glass", "Door_RearR", "Door_RearR_Glass",
         "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR", "Caliper_FL", "Caliper_FR", "Caliper_RL", "Caliper_RR",
         "Interior_Front", "SteeringWheel", "Interior_Lounge", "Interior_Bar", "Ambient_LED", "StarLights"]
assert sorted(ORDER) == sorted(PARTS), (sorted(PARTS), sorted(ORDER))
SMOOTH_DEG = {"Body": 32.0, "Glass": 30.0, "GlassPrivacy": 30.0, "Chrome": 40.0, "Grille": 35.0,
              "Lights_Front": 35.0, "Lights_Rear": 35.0, "Mirror_L": 40.0, "Mirror_R": 40.0, "Door_Driver": 32.0,
              "Door_RearL": 32.0, "Door_RearR": 32.0, "SteeringWheel": 45.0, "Ambient_LED": 30.0, "StarLights": 30.0}


DEGEN_DIST = 2e-4          # m: boolean slivers have edges of 0.003 .. 0.2 mm; the smallest real feature is ~1.5 mm
NEEDLE_AREA = 1e-8         # m2 (= 1.3e-7 studs2): the smallest real triangles (4 mm star facets) are ~7e-6 m2


def finish(p):
    bm = p.bm
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=DEGEN_DIST)
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method='BEAUTY', ngon_method='BEAUTY')
    # needles made by the triangulation (collinear ngon corners): collapse once more, re-triangulate what merged
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=DEGEN_DIST)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3], quad_method='BEAUTY',
                          ngon_method='BEAUTY')
    # needle triangles whose edges are all longer than DEGEN_DIST but whose apex lies (almost) on the longest edge:
    # flip that edge with the neighbour across it. No vertex moves and the triangle count stays the same; the apex
    # lies between the edge's endpoints, so both new triangles are proper
    for _it in range(4):
        needles = [f for f in bm.faces if len(f.verts) == 3 and f.calc_area() < NEEDLE_AREA]
        if not needles:
            break
        for f in needles:
            if not f.is_valid or f.calc_area() >= NEEDLE_AREA:
                continue
            e = max(f.edges, key=lambda e_: e_.calc_length())
            if len(e.link_faces) == 2:
                bmesh.ops.rotate_edges(bm, edges=[e], use_ccw=False)
    if p.name != "StarLights":           # stars are wound outwards by construction (tiny islands: no recalc)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(p.name)
    bm.to_mesh(me)
    for m in p.mats:
        me.materials.append(MATS[m])
    me.transform(Matrix.Translation(-p.pivot))
    me.transform(Matrix.Scale(S, 4))
    ob = bpy.data.objects.new(p.name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = p.pivot * S
    for f in me.polygons:
        f.use_smooth = True
    me.set_sharp_from_angle(angle=rad(SMOOTH_DEG.get(p.name, 35.0)))
    ca = me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
    for f in me.polygons:
        c = vcolor(p.mats[f.material_index]) + (1.0,)
        for li in f.loop_indices:
            ca.data[li].color_srgb = c
    me.color_attributes.active_color = ca
    me.update()
    return ob


def mesh_report(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    nonman = sum(1 for e in bm.edges if not e.is_manifold)
    vol = bm.calc_volume(signed=True)
    shells = 0
    seen = set()
    for f in bm.faces:
        if f in seen:
            continue
        shells += 1
        stack = [f]
        seen.add(f)
        while stack:
            g = stack.pop()
            for e in g.edges:
                for h in e.link_faces:
                    if h not in seen:
                        seen.add(h)
                        stack.append(h)
    zero = sum(1 for f in bm.faces if f.calc_area() < 1e-9)
    amin = min(f.calc_area() for f in bm.faces)
    res = {"tris": len(bm.faces), "non_manifold_edges": nonman, "signed_volume_studs3": round(vol, 4),
           "shells": shells, "zero_area_faces": zero, "min_triangle_area_studs2": float("%.3g" % amin)}
    bm.free()
    return res


OBJS = {}
for nm in ORDER:
    OBJS[nm] = finish(PARTS[nm])
log("finished meshes")

# ==============================================================================================
# 11) export FBX + OBJ (CityCar settings: Z forward / Y up, FBX unit scale, triangulated)
# ==============================================================================================
FBX_PATH = os.path.join(OUT, NAME + ".fbx")
OBJ_PATH = os.path.join(OUT, NAME + ".obj")
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.export_scene.fbx(filepath=FBX_PATH, use_selection=False, object_types={'MESH'},
                         global_scale=1.0, apply_unit_scale=True, apply_scale_options='FBX_SCALE_UNITS',
                         axis_forward='Z', axis_up='Y', use_space_transform=True, bake_space_transform=True,
                         use_mesh_modifiers=True, mesh_smooth_type='FACE', colors_type='SRGB',
                         use_triangles=True, use_tspace=False, add_leaf_bones=False, bake_anim=False,
                         path_mode='COPY', embed_textures=True, use_custom_props=False)
bpy.ops.wm.obj_export(filepath=OBJ_PATH, export_selected_objects=False, forward_axis='Z', up_axis='Y',
                      global_scale=1.0, apply_modifiers=True, export_uv=True, export_normals=True,
                      export_colors=False, export_materials=True, export_triangulated_mesh=True,
                      export_object_groups=False, export_material_groups=False, path_mode='STRIP')
log("exported", os.path.basename(FBX_PATH), os.path.basename(OBJ_PATH))


# ==============================================================================================
# 12) manifest (Roblox frame, studs): Blender (x, y, z) -> Roblox (-x, z, y)
# ==============================================================================================
def to_r(v, scale=1.0):
    return [round(-v[0] * scale, 4) + 0.0, round(v[2] * scale, 4) + 0.0, round(v[1] * scale, 4) + 0.0]


def dir_r(v):
    v = V(v).normalized()
    return [round(-v.x, 5) + 0.0, round(v.z, 5) + 0.0, round(v.y, 5) + 0.0]


def cframe_r(pos_m, look_b, up_b=(0, 0, 1)):
    """Roblox CFrame.new(x,y,z, R00..R22) components from a Blender position (m) and look direction"""
    p = to_r(pos_m, S)
    lk = V(dir_r(look_b))
    up = V(dir_r(up_b))
    rt = lk.cross(up).normalized()
    up = rt.cross(lk).normalized()
    bk = -lk
    r = lambda a: round(a, 5) + 0.0
    return {"position_studs": p, "look_vector": [r(lk.x), r(lk.y), r(lk.z)],
            "cframe_components": p + [r(rt.x), r(up.x), r(bk.x), r(rt.y), r(up.y), r(bk.y), r(rt.z), r(up.z), r(bk.z)]}


def bbox_world(ob):
    pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = V((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = V((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def bbox_r(lo, hi):
    a, b = to_r(lo), to_r(hi)
    return [min(a[i], b[i]) for i in range(3)], [max(a[i], b[i]) for i in range(3)]


WHITE = [255, 255, 255]
SPIN = ("spin about the part's local +X axis; rolling forward (towards -Z) is a NEGATIVE angle: "
        "motor.Transform = CFrame.Angles(-distance / radius_studs, 0, 0)")
INFO = {
    "Body": dict(kind="static_root", role="painted shell with shut lines, wheel wells, black pillar posts, frit, "
                 "cowl, wipers, antenna fin, plates, light housings, front passenger door (does not open)",
                 can_collide=True, color=[18, 20, 27], material="SmoothPlastic", reflectance=0.12,
                 note="paint zone is WHITE in the vertex colours: Body.Color = paint (midnight 18,20,27)"),
    "Glass": dict(kind="static", role="clear glass: windshield, front passenger window, headlight covers",
                  can_collide=False, color=WHITE, material="Glass", transparency=0.45),
    "GlassPrivacy": dict(kind="static", role="tinted privacy glass: 4 stretch windows, rear window, partition window",
                         can_collide=False, color=WHITE, material="Glass", transparency=0.22),
    "Chrome": dict(kind="static", role="DLO surround, belt + lower side strips (body parts), passenger door handle, "
                   "projector bezels, exhaust tips, trunk emblem", can_collide=False, color=WHITE, material="Metal",
                   reflectance=0.35),
    "Grille": dict(kind="static", role="multi-bar grille, chrome surround, centre badge (one abstract chevron on a black plaque)",
                   can_collide=False, color=WHITE, material="Metal", reflectance=0.25),
    "Lights_Front": dict(kind="light", role="LED DRL light guides, projector lenses, high-beam LEDs, amber indicators",
                         can_collide=False, color=WHITE, material="SmoothPlastic",
                         note="Material = Neon when the lights are on (put SpotLights at anchors Headlight_L/R)"),
    "Lights_Rear": dict(kind="light", role="full-width tail light bar, light blades, third brake light, reflectors",
                        can_collide=False, color=WHITE, material="SmoothPlastic",
                        note="Material = Neon for tail/brake light"),
    "Mirror_L": dict(kind="static", role="left door mirror (lofted housing, arm, glass, LED indicator) on the A-pillar sail (does not move with the door)",
                     can_collide=False, color=[18, 20, 27], material="SmoothPlastic", welded_to="Body",
                     note="cap is paint (white vertex colour) -> Color = paint like Body"),
    "Mirror_R": dict(kind="static", role="right door mirror on the A-pillar sail", can_collide=False,
                     color=[18, 20, 27], material="SmoothPlastic", welded_to="Body",
                     note="cap is paint (white vertex colour) -> Color = paint like Body"),
    "Interior_Front": dict(kind="static", role="driver cockpit: dashboard, 2 screens, vents, column, console, gear "
                           "selector, cup holders, pedals, driver + passenger seat, carpet, sill plates",
                           can_collide=False, color=WHITE, material="SmoothPlastic"),
    "SteeringWheel": dict(kind="rotating", role="3-spoke steering wheel; rotate about hinge_axis", can_collide=False,
                          color=WHITE, material="SmoothPlastic"),
    "Interior_Lounge": dict(kind="static", role="lounge: carpet, long side bench (3 seats), rear bench (3 seats, "
                            "armrests, cup holders), partition with window + TV, star-ceiling panel, sill plates",
                            can_collide=False, color=WHITE, material="SmoothPlastic"),
    "Interior_Bar": dict(kind="static", role="refreshment console: cabinet, mirrored back, tumblers, 2 water carafes, "
                         "ice bucket with ice, cup holders, control panel (no alcohol, no labels)",
                         can_collide=False, color=WHITE, material="SmoothPlastic"),
    "Ambient_LED": dict(kind="light", role="ambient LED strips (ceiling, roof rails, bar, toe-kicks, partition)",
                        can_collide=False, color=[140, 123, 255], material="Neon",
                        note="vertex colour white: MeshPart.Color sets the LED colour (render: 140,123,255)"),
    "StarLights": dict(kind="light", role="150 star points of the ceiling panel", can_collide=False,
                       color=WHITE, material="Neon"),
}
for d in ("Door_Driver", "Door_RearL", "Door_RearR"):
    INFO[d] = dict(kind="door", role="opening door: outer panel, jamb faces, door card (armrest, wood, handle, "
                   "speaker), belt + lower chrome strips, handle", can_collide=False, color=[18, 20, 27],
                   material="SmoothPlastic", note="paint zone white -> Color = paint like Body")
    INFO[d + "_Glass"] = dict(kind="door_glass", role="frameless door glass; moves with " + d, can_collide=False,
                              color=WHITE, material="Glass", welded_to=d,
                              transparency=0.45 if d == "Door_Driver" else 0.22)
for w in WHEELS:
    INFO[w] = dict(kind="wheel", role="245/45 R19 tyre (sidewall bulge, 3 tread grooves), 10-spoke rim, hub, lug "
                   "bolts, brake disc (spins with the wheel)", can_collide=False, color=WHITE, material="SmoothPlastic")
    c = "Caliper_" + w.split("_")[1]
    INFO[c] = dict(kind="caliper", role="dark-red brake caliper; does not spin" + ("; steers with " + w if "_F" in w else ""),
                   can_collide=False, color=WHITE, material="Metal", welded_to=("steering knuckle of " + w)
                   if "_F" in w else "Body")

HINGES = {"Door_Driver": 1, "Door_RearL": 1, "Door_RearR": -1}
manifest_objs = []
TOTAL = 0
PROBLEMS = []
for nm in ORDER:
    ob = OBJS[nm]
    rep = mesh_report(ob)
    TOTAL += rep["tris"]
    if rep["tris"] > 20000:
        PROBLEMS.append(nm + " over 20k triangles")
    if rep["non_manifold_edges"]:
        PROBLEMS.append("%s: %d non-manifold edges" % (nm, rep["non_manifold_edges"]))
    if rep["signed_volume_studs3"] <= 0:
        PROBLEMS.append(nm + ": non-positive volume (inward normals?)")
    lo, hi = bbox_world(ob)
    rlo, rhi = bbox_r(lo, hi)
    piv = ob.location
    e = {"name": nm}
    e.update(INFO[nm])
    e.update({"triangles": rep["tris"], "materials": [m.name for m in ob.data.materials],
              "pivot_studs": to_r(piv), "pivot_m": [round(c * STUD, 4) for c in to_r(piv)],
              "bbox_min_studs": rlo, "bbox_max_studs": rhi, "size_studs": [round(rhi[i] - rlo[i], 4) for i in range(3)],
              "mesh_check": rep})
    if nm.startswith("Wheel_"):
        e["spin_axis"] = [1.0, 0.0, 0.0]
        e["spin"] = SPIN
        e["radius_studs"] = round(TYRE_R * S, 4)
        e["radius_m"] = round(TYRE_R, 4)
        e["tyre"] = "245/45 R19 (diameter %.4f m)" % (2 * TYRE_R)
        if "_F" in nm:
            e["steer_axis"] = [0.0, 1.0, 0.0]
            e["steer_limits_deg"] = [-30.0, 30.0]
            e["steer_note"] = "positive angle about +Y turns the wheel's front towards the car's left (-X)"
    if nm.startswith("Caliper_"):
        e["note"] = "pivot = wheel centre. Front calipers: apply the same steer angle as the wheel, no spin."
    if nm in HINGES:
        sgn = HINGES[nm]
        e["hinge_axis"] = [0.0, 1.0, 0.0]
        e["open_angle_deg"] = round(-DOOR_OPEN_DEG * sgn, 1)
        e["open_cframe"] = "door:PivotTo(closedPivot * CFrame.Angles(0, math.rad(open_angle_deg * t), 0)), t = 0..1"
        e["hinge_note"] = ("vertical hinge at the door's front edge (3 cm ahead of it, on the body's widest line). "
                           "Left doors open with a negative angle about +Y, right doors with a positive one; the door "
                           "glass (" + nm + "_Glass) uses the same pivot and angle.")
    if nm.endswith("_Glass"):
        e["hinge_axis"] = [0.0, 1.0, 0.0]
        e["open_angle_deg"] = round(-DOOR_OPEN_DEG * HINGES[nm[:-6]], 1)
    if nm == "SteeringWheel":
        e["hinge_axis"] = dir_r(STEER_AXIS)
        e["hinge_axis_note"] = "steering column axis, pointing from the dashboard towards the driver"
        e["rotation_limits_deg"] = [-450.0, 450.0]
        e["suggested_game_limits_deg"] = [-120.0, 120.0]
        e["rotation_note"] = ("positive angle (right-hand rule about hinge_axis) turns the rim counter-clockwise as "
                              "the driver sees it = steering LEFT")
    manifest_objs.append(e)

all_lo = V((1e9, 1e9, 1e9))
all_hi = V((-1e9, -1e9, -1e9))
for ob in OBJS.values():
    lo, hi = bbox_world(ob)
    all_lo = V(tuple(min(a, b) for a, b in zip(all_lo, lo)))
    all_hi = V(tuple(max(a, b) for a, b in zip(all_hi, hi)))
rlo, rhi = bbox_r(all_lo, all_hi)
EXT_STUDS = [rhi[i] - rlo[i] for i in range(3)]
blo, bhi = bbox_r(*bbox_world(OBJS["Body"]))
body_w = 2 * max(abs(v.co.x) for v in OBJS["Body"].data.vertices if v.co.z < 0.95 * S)
mlo, mhi = bbox_r(*bbox_world(OBJS["Mirror_L"]))
piv = {nm: V(OBJS[nm].location) for nm in WHEELS}
wb_meas = piv["Wheel_RL"].y - piv["Wheel_FL"].y
tr_meas = piv["Wheel_FL"].x - piv["Wheel_FR"].x
gc_meas = min(v.co.z for v in OBJS["Body"].data.vertices
              if abs(v.co.y) < (WHEELBASE / 2 - 0.6) * S and abs(v.co.x) < 0.7 * S)


def mm(v):
    return {"m": round(v * STUD, 4), "studs": round(v, 3)}


ANCH = {}
seat_map = [("DriverSeat", "DriverSeat"), ("PassengerSeat1", "Rear0"), ("PassengerSeat2", "Rear1"),
            ("PassengerSeat3", "Rear2"), ("PassengerSeat4", "Side2"), ("PassengerSeat5", "Side1"),
            ("PassengerSeat6", "Side0"), ("FrontPassengerSeat", "FrontPassengerSeat")]
# R6 seated pose as DrivePlan.SEATS / DriveController use it: HumanoidRootPart 1.5 studs above the seat surface,
# head top (with a driver's cap) 2.32 studs above the root. The headliner above every seat is measured by
# ray casts (up from the cushion, over the head's 1x1 stud footprint) against the cabin geometry.
GAME_SCALE = 0.95
R6_ROOT_ABOVE_SEAT, R6_HEAD_ABOVE_ROOT, HEAD_MARGIN = 1.5, 2.32, 0.05
HEAD_BVH = [BVHTree.FromBMesh(PARTS[n].bm) for n in ("Body", "Interior_Front", "Interior_Lounge", "Ambient_LED",
                                                      "StarLights", "Glass", "GlassPrivacy")]


def ceiling_above(rp, look, zmin):
    """lowest cabin surface above the head footprint (0.30 m across x 0.20 m deep around the rig root). The rays
    start at zmin (0.55 m above the cushion), above every backrest / bench / cabinet next to the seat."""
    fw = V(look).normalized()
    lat = fw.cross(V((0.0, 0.0, 1.0))).normalized()
    best = 9.0
    for a in (-0.15, 0.0, 0.15):
        for b in (-0.10, 0.0, 0.10):
            o = rp + lat * a + fw * b
            for bvh in HEAD_BVH:
                loc, _n, _i, _d = bvh.ray_cast(V((o.x, o.y, zmin)), V((0.0, 0.0, 1.0)))
                if loc is not None:
                    best = min(best, loc.z)
    return best


ROOT_BACK = {"DriverSeat": 0.10, "FrontPassengerSeat": 0.10, "Rear0": 0.08, "Rear1": 0.08, "Rear2": 0.08}
SEAT_FIT = {}
for an, key in seat_map:
    pos, look = SEATS[key]
    a = cframe_r(pos, look)
    a["kind"] = "seat"
    # rig root over the rear part of the cushion (torso against the backrest)
    rp = pos + V((0.0, ROOT_BACK.get(key, 0.0), 0.0))
    ceil_m = ceiling_above(rp, look, pos.z + 0.55)
    fit = {}
    for tag, g in (("scale_1", 1.0), ("scale_%g" % GAME_SCALE, GAME_SCALE)):
        cush = pos.z * S * g
        ceil = ceil_m * S * g
        ideal = cush + R6_ROOT_ABOVE_SEAT
        root_y = min(ideal, ceil - R6_HEAD_ABOVE_ROOT - HEAD_MARGIN)
        rr = to_r(rp, S * g)
        fit[tag] = {"cushion_top_y": round(cush, 3), "headliner_y": round(ceil, 3),
                    "clearance_cushion_to_headliner": round(ceil - cush, 3),
                    "rig_root_studs": [rr[0], round(root_y, 3), rr[2]],
                    "sink_into_cushion": round(ideal - root_y, 3)}
    a["rig_root_studs"] = fit["scale_1"]["rig_root_studs"]
    a["headliner_y_studs"] = fit["scale_1"]["headliner_y"]
    a["r6_fit"] = fit
    a["note"] = ("position = cushion top centre, LookVector = where the passenger faces. rig_root_studs = where to put "
                 "an R6 HumanoidRootPart (DrivePlan convention: 1.5 above the seat surface, head + cap 2.32 above "
                 "the root), moved over the rear of the cushion and lowered ('sink_into_cushion') so the head stays "
                 "0.05 under the measured headliner. r6_fit lists the numbers at scale 1 and at the game scale.")
    ANCH[an] = a
    SEAT_FIT[an] = fit
# door entry points: 0.55 m (about 2 studs) outside the body side, facing the car, moved rearward from the door
# centre until a standing R6 footprint (2 studs along the car x 1 stud x 5 studs tall, + 0.1 stud margin) is clear of
# the OPEN door and its glass (and of body, mirrors, wheels), i.e. the character stands just behind the open door,
# in front of the opening.
def mesh_bvh(names, M=None):
    verts, polys = [], []
    for nm in names:
        bm = PARTS[nm].bm
        bm.verts.index_update()
        off = len(verts)
        verts += [(M @ v.co) if M is not None else v.co.copy() for v in bm.verts]
        polys += [[v.index + off for v in f.verts] for f in bm.faces]
    return BVHTree.FromPolygons(verts, polys), verts


def open_matrix(d):
    piv = PARTS[d].pivot
    return Matrix.Translation(piv) @ Matrix.Rotation(rad(-DOOR_OPEN_DEG * HINGES[d]), 4, 'Z') @ Matrix.Translation(-piv)


def r6_box(c, margin):
    hx, hy, hz = 0.5 * STUD + margin, 1.0 * STUD + margin, 2.5 * STUD + margin
    vs = [V((c.x + sx * hx, c.y + sy * hy, c.z + sz * hz)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    F = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return BVHTree.FromPolygons(vs, F), (c, hx, hy, hz)


STATIC_BVH = [mesh_bvh([n])[0] for n in ("Body", "Chrome", "Mirror_L", "Mirror_R", "Wheel_FL", "Wheel_FR", "Wheel_RL",
                                          "Wheel_RR")]
ENTRY_FIT = {}
yr_door = 0.5 * (Y_C + E(1.56))
yf_door = 0.5 * (D(1.72) + D(2.88))
for an, door, x, y0, look in (("DoorL1", "Door_Driver", HW + 0.55, yf_door, (-1, 0, 0)),
                              ("DoorL2", "Door_RearL", HW + 0.55, yr_door, (-1, 0, 0)),
                              ("DoorR2", "Door_RearR", -(HW + 0.55), yr_door, (1, 0, 0))):
    dbvh, dverts = mesh_bvh([door, door + "_Glass"], open_matrix(door))

    def blocked(y, margin=0.1 * STUD):
        bb, (c, hx, hy, hz) = r6_box(V((x, y, 2.5 * STUD + 0.005)), margin)
        if bb.overlap(dbvh) or any(bb.overlap(t) for t in STATIC_BVH):
            return True
        return any(abs(q.x - c.x) < hx and abs(q.y - c.y) < hy and abs(q.z - c.z) < hz for q in dverts)
    y = y0
    while blocked(y) and y < y0 + 1.2:
        y += 0.01
    y = round(y + 0.03, 3)                       # + 3 cm extra
    assert not blocked(y), an
    ENTRY_FIT[an] = {"moved_rearward_m": round(y - y0, 3), "moved_rearward_studs": round((y - y0) * S, 3)}
    a = cframe_r(V((x, y, 0.0)), look)
    a["kind"] = "entry"
    a["clear_of_open_door"] = True
    a["note"] = ("ground point 0.55 m outside the body side, facing the car (character HumanoidRootPart goes 3 studs "
                 "above). It sits just behind the OPEN door (%s at its open angle): a standing R6 footprint "
                 "(2 x 1 x 5 studs, +0.1 stud margin) there touches neither the open door, its glass, the body, the "
                 "mirrors nor the wheels. DoorL1 = driver door, DoorL2 = rear-left door, DoorR2 = rear-right door "
                 "(kerb side at the Port Meridian VIP stand, whose kerb is on the car's right)." % door)
    ANCH[an] = a
log("ENTRY", json.dumps(ENTRY_FIT))
# light / plate / exhaust points on the actual surfaces (ray casts on the skin), 2 cm in front of them
fx_pts = []
for sx, nm in ((1, "L"), (-1, "R")):
    fx_pts.append(("Headlight_" + nm, sx * 0.614, map_front(sx * 0.614, 0.668, 0.0).y - 0.02, 0.668, (0, -1, 0)))
    fx_pts.append(("Taillight_" + nm, sx * 0.80, map_rear(sx * 0.80, 0.912, 0.0).y + 0.02, 0.912, (0, 1, 0)))
    fx_pts.append(("Exhaust_" + nm, sx * 0.61, map_rear(sx * 0.61, 0.339, 0.0).y + 0.02, 0.339, (0, 1, 0)))
fx_pts += [("CabinLight", 0.0, Y_MID, 1.38, (0, 0, -1)),
           ("PlateFront", 0.0, map_front(0.0, 0.350, 0.0).y - 0.005, 0.350, (0, -1, 0)),
           ("PlateRear", 0.0, map_rear(0.0, 0.766, 0.0).y + 0.005, 0.766, (0, 1, 0))]
for an, x, y, z, look in fx_pts:
    a = cframe_r(V((x, y, z)), look, up_b=(0, 0, 1) if abs(look[2]) < 0.5 else (0, -1, 0))
    a["kind"] = "fx"
    ANCH[an] = a
ANCH["BootLid"] = None

DIMS = {
    "length": mm(bhi[2] - blo[2]),
    "width_body_without_mirrors": mm(body_w),
    "width_over_mirrors": mm(max(abs(mlo[0]), abs(mhi[0])) * 2),
    "height": mm(EXT_STUDS[1]),
    "wheelbase": mm(wb_meas),
    "track": mm(tr_meas),
    "ground_clearance_between_axles": mm(gc_meas),
    "front_overhang": mm(-blo[2] - wb_meas / 2),
    "rear_overhang": mm(bhi[2] - wb_meas / 2),
    "stretch_section": mm(STRETCH * S),
    "wheel_diameter": mm(2 * TYRE_R * S),
    "overall_bbox_studs_XYZ": [round(v, 3) for v in EXT_STUDS],
    "overall_bbox_min_studs": rlo, "overall_bbox_max_studs": rhi,
}
manifest = {
    "name": NAME,
    "generic_identity": "ExecutiveLimo - generic stretch executive limousine (no brand, no logos; emblem = one abstract chevron)",
    "units": {"studs_per_metre": round(S, 6), "metres_per_stud": STUD, "scale_factor_m_to_studs": round(S, 6),
              "source": "https://create.roblox.com/docs/physics/units (1 stud = 28 cm), same factor as CityCar"},
    "frame": {"forward": "-Z (Model LookVector)", "right": "+X", "up": "+Y",
              "origin": "ground level, car centre line, half-way between the axles",
              "driver_side": "left (-X), like CityCar and DrivePlan.SEATS"},
    "dimensions_measured_from_mesh": DIMS,
    "dimensions_target_m": {"base_sedan_length": BASE_LEN, "base_wheelbase": BASE_WB, "stretch": STRETCH,
                            "length": LENGTH, "wheelbase": WHEELBASE, "width": WIDTH, "height": HEIGHT,
                            "track": TRACK, "front_overhang": OH_F, "rear_overhang": round(OH_R, 4),
                            "ground_clearance": GROUND, "tyre": "245/45 R19"},
    "anchors": ANCH,
    "game_fit": {
        "read_from_game_code_on": "2026-10-11 (work/src, read only)",
        "DrivePlan.CAR_LENGTH.limo": 21, "DrivePlan.CAR_WIDTH.limo_incl_mirrors": 7.4, "DrivePlan.WHEELBASE.limo": 13,
        "DrivePlan.SEATS.limo_rig_roots": {"driver": [-1.6, 2.6, -2.6], "front": [1.6, 2.6, -2.6],
                                           "rearL": [-1.6, 2.6, 4.4], "rearR": [1.6, 2.6, 4.4]},
        "DriveController.SHAPES.limo": {"w": 7.0, "l": 21, "h": 5.4, "wb": 13, "r": 1.35},
        "CampusConfig.CARS.limo": {"length": 19, "width": 7.4},
        "MetroPlan.VIP_LIMO": {"stand_pad_studs": [8, 22], "layby_x": [104, 200], "bay_centres_x": [176, 128],
                               "cars_face": "west (-X world)"},
        "model_length_studs": round(bhi[2] - blo[2], 3),
        "recommended_scale": GAME_SCALE,
        "scale_to_match_CAR_LENGTH_21": round(21.0 / (bhi[2] - blo[2]), 4),
        "note": ("Scale %.3f (game_scale) keeps the width over the mirrors inside DrivePlan.CAR_WIDTH.limo = 7.4. "
                 "The car is then %.1f studs long instead of the part-built 21: it overhangs the 22-stud gold pad by "
                 "about %.1f studs at each end, but the lay-by bays are 48 studs apart, so two cars still leave about "
                 "%.0f studs between them. Model:ScaleTo(scale_to_match_CAR_LENGTH_21) fits the old 21-stud slot, "
                 "but the cabin then gets too low for seated R6 rigs." % (GAME_SCALE, (bhi[2] - blo[2]) * GAME_SCALE,
                                                                         ((bhi[2] - blo[2]) * GAME_SCALE - 22) / 2,
                                                                         48 - (bhi[2] - blo[2]) * GAME_SCALE)),
        "seat_mapping_for_DrivePlan.SEATS.limo": {"driver": "DriverSeat", "front": "FrontPassengerSeat",
                                                   "rearL": "PassengerSeat1", "rearR": "PassengerSeat3",
                                                   "extra companions / guests": ["PassengerSeat2", "PassengerSeat6",
                                                                                 "PassengerSeat5", "PassengerSeat4"]},
    },
    "game_scale": None,
    "triangles_total": TOTAL,
    "triangle_limit_per_mesh": 20000,
    "triangle_limit_source": "https://create.roblox.com/docs/art/modeling/specifications",
    "objects": manifest_objs,
    "materials": {m: {"srgb_hex": MATDEF[m][0], "vertex_colour_hex": (MATDEF[m][4] or MATDEF[m][0])} for m in MATDEF},
    "export": {"fbx": NAME + ".fbx", "obj": NAME + ".obj", "mtl": NAME + ".mtl",
               "fbx_settings": "axis_forward=Z, axis_up=Y, apply_scale_options=FBX_SCALE_UNITS, global_scale=1, "
                               "bake_space_transform, mesh_smooth_type=FACE, colors_type=SRGB, triangulated, "
                               "no leaf bones, no animation, path_mode=COPY+embed (no textures used)",
               "blender_units": "1 Blender unit = 1 stud (scene Unit System None, Unit Scale 1.0)"},
    "problems": PROBLEMS,
}
def scaled_anchor(a, s):
    if a is None:
        return None
    b = dict(a)
    b["position_studs"] = [round(c * s, 4) for c in a["position_studs"]]
    b["cframe_components"] = b["position_studs"] + a["cframe_components"][3:]
    if "r6_fit" in a:
        f = a["r6_fit"]["scale_%g" % s]
        b["rig_root_studs"] = f["rig_root_studs"]
        b["headliner_y_studs"] = f["headliner_y"]
        b.pop("r6_fit")
    return b


L_st = bhi[2] - blo[2]
manifest["game_scale"] = {
    "recommended": GAME_SCALE,
    "why": ("width over mirrors %.2f studs <= DrivePlan.CAR_WIDTH.limo 7.4 (HQ B1 lane clearance) while the cabin "
            "keeps the real proportions; seated R6 rigs need the rig roots from anchors_at_scale (lowered so heads "
            "stay under the headliner)" % (DIMS["width_over_mirrors"]["studs"] * GAME_SCALE)),
    "how": ("clone:ScaleTo(%g) - the Model pivot is the origin on the ground, so every pivot and anchor position "
            "scales by %g (rig roots: anchors_at_scale, already lowered for the headliner)" % (GAME_SCALE, GAME_SCALE)),
    "dimensions_studs_at_scale": {"length": round(L_st * GAME_SCALE, 3),
                                  "width_body": round(body_w * GAME_SCALE, 3),
                                  "width_over_mirrors": round(DIMS["width_over_mirrors"]["studs"] * GAME_SCALE, 3),
                                  "height_roof": round(HEIGHT * S * GAME_SCALE, 3),
                                  "wheelbase": round(wb_meas * GAME_SCALE, 3),
                                  "wheel_radius": round(TYRE_R * S * GAME_SCALE, 4)},
    "pivots_studs_at_scale": {e["name"]: [round(c * GAME_SCALE, 4) for c in e["pivot_studs"]] for e in manifest_objs
                              if e["pivot_studs"] != [0.0, 0.0, 0.0]},
    "anchors_at_scale": {k: scaled_anchor(a, GAME_SCALE) for k, a in ANCH.items()},
    "alternatives": {"real_size": 1.0, "fit_old_21_stud_slot": round(21.0 / L_st, 4)},
}
with open(os.path.join(OUT, "manifest.json"), "w") as fh:
    json.dump(manifest, fh, indent=2)
log("TOTAL TRIS", TOTAL, "PROBLEMS", PROBLEMS)
for e in manifest_objs:
    log("  %-20s %6d tris  pivot %s" % (e["name"], e["triangles"], e["pivot_studs"]))
log("DIMS", json.dumps(DIMS))


# ==============================================================================================
# 13) renders (Cycles CPU): studio, front/rear 3/4, side, top, interior through the open rear door,
#     close-ups (headlight + grille, wheel); extras: doors open, cut-away, Roblox vertex-colour preview
# ==============================================================================================
DOOR_FRAC = float(([a.split("=", 1)[1] for a in ARGS if a.startswith("--door-frac=")] or ["1.0"])[0])  # dev views


def set_doors(open_names):
    for d, sgn in HINGES.items():
        ang = rad(-DOOR_OPEN_DEG * sgn * DOOR_FRAC) if d in open_names else 0.0
        for nm in (d, d + "_Glass"):
            OBJS[nm].rotation_euler = (0.0, 0.0, ang)


def cabin_light(on):
    for o in bpy.data.objects:
        if o.name.startswith("CabinFill"):
            o.hide_render = not on


def want(fn):
    return not ONLY or fn in ONLY


if DO_RENDER:
    for nm in HIDE:
        OBJS[nm].hide_render = True
    lights = setup_studio()
    # warm cabin fill lights (only for interior shots) - stands in for the courtesy lights
    for i, (yy, en) in enumerate(((D(3.5), 9.0), (D(4.4), 9.0), (D(5.3), 7.0), (E(1.45), 5.0))):
        L = bpy.data.lights.new("CabinFill%d" % i, 'AREA')
        L.size = 0.5 * S
        L.energy = en * S * S
        L.color = (1.0, 0.86, 0.70)
        o = bpy.data.objects.new("CabinFill%d" % i, L)
        o.location = V((0.0, yy, 1.36)) * S
        o.rotation_euler = (0, 0, 0)
        bpy.context.scene.collection.objects.link(o)
    cabin_light(False)
    RF = bpy.data.lights.new("RoofFill", 'AREA')
    RF.shape = 'RECTANGLE'
    RF.size, RF.size_y = 4.0 * S, 10.0 * S
    RF.energy = 150.0 * S * S
    roof_fill = bpy.data.objects.new("RoofFill", RF)
    roof_fill.location = V((0.0, 0.1, 4.2)) * S           # area lights point down (-Z) by default
    roof_fill.visible_camera = False
    roof_fill.hide_render = True
    bpy.context.scene.collection.objects.link(roof_fill)
    # light linking: the panel lights (and is mirrored by) the car only, so the floor keeps its studio gradient
    rf_recv = bpy.data.collections.new("RoofFillReceivers")
    for ob in OBJS.values():
        rf_recv.objects.link(ob)
    roof_fill.light_linking.receiver_collection = rf_recv
    R = os.path.join
    views = [
        ("render_hero.png", lambda: camera("cam_hero", (5.7, -8.2, 1.25), (0.05, -0.75, 0.58), lens=40), [], False),
        ("render_rear34.png", lambda: camera("cam_rear", (-6.2, 8.9, 1.9), (0.0, 0.7, 0.62), lens=42), [], False),
        ("render_side.png", lambda: camera("cam_side", (30.0, 0.1, 0.78), (0.0, 0.1, 0.78), ortho=8.4), [], False),
        ("render_top.png", lambda: camera("cam_top", (0.0, 0.1, 30.0), (0.0, 0.1, 0.0), ortho=8.4), [], False),
        ("render_interior.png", lambda: camera("cam_int", (-0.93, D(6.02), 1.12), (0.42, D(3.45), 0.80), lens=18),
         ["Door_RearR"], True),
        ("render_closeup_front.png", lambda: camera("cam_cf", (1.55, YF - 1.25, 0.86), (0.36, YF + 0.10, 0.60),
                                                    lens=48), [], False),
        ("render_closeup_wheel.png", lambda: camera("cam_cw", (2.25, YAF - 1.10, 0.52), (0.88, YAF + 0.02, 0.36),
                                                    lens=50), [], False),
        ("render_doors_open.png", lambda: camera("cam_do", (5.6, -5.6, 2.6), (0.2, -0.3, 0.6), lens=36),
         ["Door_Driver", "Door_RearL"], True),
        # whole cabin, dashboard to rear bench (y -1.95 .. 3.2 m)
        ("render_interior_cutaway.png", lambda: camera("cam_cut", (0.0, 0.62, 1.41), (0.0, 0.62, 0.0), ortho=5.5),
         [], True),
        # development views (rendered only when named in --only=)
        ("dev_front.png", lambda: camera("cam_df", (1.9, YF - 3.2, 0.95), (0.0, YF + 0.45, 0.58), lens=50), [], False),
        ("dev_mirror.png", lambda: camera("cam_dm", (1.75, MIRROR_Y - 1.05, 1.32), (0.98, MIRROR_Y, 1.05), lens=50),
         [], False),
        ("dev_plan.png", lambda: camera("cam_dp", (0.0, YF + 1.0, 12.0), (0.0, YF + 1.0, 0.0), ortho=2.6), [], False),
        ("dev_grille.png", lambda: camera("cam_dg", (0.25, YF - 6.0, 1.6), (0.25, YF, 0.58), ortho=1.0), [], False),
        ("dev_rear.png", lambda: camera("cam_dr", (-1.9, YR + 3.2, 1.10), (0.0, YR - 0.45, 0.70), lens=50), [], False),
        ("dev_gcorner.png", lambda: camera("cam_dgc", (0.95, YF - 0.80, 0.98), (0.40, YF + 0.06, 0.70), lens=80), [],
         False),
        ("dev_reararch.png", lambda: camera("cam_da", (2.55, YAR - 1.05, 0.62), (0.90, YAR, 0.45), lens=45), [], False),
        ("dev_cowl.png", lambda: camera("cam_dc", (1.30, YF - 0.55, 2.25), (0.55, D(2.45), 0.95), lens=32),
         ["Door_Driver"], False),
        ("dev_doorhalf.png", lambda: camera("cam_dh", (2.2, D(1.10), 1.55), (0.98, D(2.10), 0.98), lens=40),
         ["Door_Driver"], False),
        ("dev_badge.png", lambda: camera("cam_db", (0.22, YF - 0.75, 0.74), (0.0, YF + 0.05, 0.60), lens=70), [], False),
        ("dev_bootbadge.png", lambda: camera("cam_dbb", (-0.25, YR + 0.85, 1.05), (0.0, YR - 0.05, 0.84), lens=70), [],
         False),
        ("dev_reardoor.png", lambda: camera("cam_drd", (2.6, E(2.6), 1.35), (0.95, E(1.75), 0.85), lens=36),
         ["Door_RearL"], True),
    ]
    for fn, mk, opened, cab in views:
        if not want(fn) or (fn.startswith("dev_") and fn not in ONLY):
            continue
        co = mk()
        if fn in ("render_top.png", "dev_plan.png"):
            co.rotation_euler = (0, 0, rad(90))
        if fn == "render_interior_cutaway.png":
            co.rotation_euler = (0, 0, rad(90))
            co.data.clip_start = 0.02
        set_doors(opened)
        cabin_light(cab)
        cut = fn == "render_interior_cutaway.png"
        for ob in OBJS.values():
            ob.visible_shadow = not cut
        bpy.data.objects["Cyc"].hide_render = fn in ("render_side.png",)
        top = bpy.data.objects["Top"]
        keep = (top.location.copy(), top.rotation_euler.copy(), top.data.size, top.data.size_y)
        if fn == "render_top.png":
            # short, wide box for this view: the long strip would lie on the flat roof as a white slab
            top.data.size, top.data.size_y = 10.0 * S, 2.4 * S
            # overhead softbox moved to the side: a flat roof would mirror it as a white slab straight into an
            # orthographic top camera; from the side it draws highlight lines on the curved roof edges instead
            top.location = V((4.5, 0.2, 3.2)) * S
            top.rotation_euler = (V((0.0, 0.2, 0.0)) * S - top.location).to_track_quat('-Z', 'Y').to_euler()
        # top view: a large, dim panel straight above the car, invisible to the camera. The flat roof mirrors it as
        # an even dark grey (instead of the black zenith of the HDRI), so the roof, glass and pillars read as shapes
        roof_fill.hide_render = fn != "render_top.png"
        # side view (orthographic, no floor): the far-side strip light shone through the clear front glass as a white
        # slab; seen through glass, the lights are hidden (they still light the car)
        for lo in lights:
            lo.visible_transmission = fn != "render_side.png"
        render(co, R(OUT, fn))
        top.location, top.rotation_euler, top.data.size, top.data.size_y = keep
    roof_fill.hide_render = True
    for lo in lights:
        lo.visible_transmission = True
    set_doors([])
    cabin_light(False)
    for ob in OBJS.values():
        ob.visible_shadow = True

    # what Studio shows: vertex colours x MeshPart.Color (manifest colours), glass transparent, LEDs neon
    def vc_material(name, tint=(255, 255, 255), alpha=1.0, emit=0.0):
        m = bpy.data.materials.new(name)
        if m.node_tree is None:
            m.use_nodes = True
        nt = m.node_tree
        b = nt.nodes.get("Principled BSDF")
        ca = nt.nodes.new("ShaderNodeVertexColor")
        ca.layer_name = "Col"
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = 'RGBA'
        mix.blend_type = 'MULTIPLY'
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(ca.outputs["Color"], mix.inputs[6])
        mix.inputs[7].default_value = lin(tuple(c / 255.0 for c in tint)) + (1.0,)
        nt.links.new(mix.outputs[2], b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = 0.45
        b.inputs["Alpha"].default_value = alpha
        if emit:
            nt.links.new(mix.outputs[2], b.inputs["Emission Color"])
            b.inputs["Emission Strength"].default_value = emit
        return m

    fn = "render_roblox_preview.png"
    if want(fn):
        saved = {}
        for e in manifest_objs:
            ob = OBJS[e["name"]]
            saved[e["name"]] = list(ob.data.materials)
            col = e.get("color", WHITE)
            alpha = 1.0 - e.get("transparency", 0.0)
            emit = 3.0 if e.get("material") == "Neon" else 0.0
            sub = vc_material("VC_" + e["name"], tuple(col), alpha, emit)
            for i in range(len(ob.data.materials)):
                ob.data.materials[i] = sub
        render(camera("cam_vc", (6.3, -8.7, 1.55), (0.05, -0.9, 0.60), lens=42), R(OUT, fn))
        for nm, mats in saved.items():
            for i, m in enumerate(mats):
                OBJS[nm].data.materials[i] = m
    log("RENDERS DONE")


# ==============================================================================================
# 14) re-import check: load the exported FBX/OBJ into an empty scene and compare with the manifest
# ==============================================================================================
def raw_fbx(path):
    """parse the FBX without axis conversion (the file's own Y-up frame, as Studio reads it)"""
    addons = os.path.join(os.path.dirname(bpy.__file__), "..", "..", "scripts", "addons_core")
    for cand in (addons, os.path.join(os.path.dirname(os.path.dirname(bpy.__file__)), "addons_core")):
        if os.path.isdir(cand) and cand not in sys.path:
            sys.path.append(cand)
    try:
        from io_scene_fbx import parse_fbx
    except Exception:
        import addon_utils
        for mod in addon_utils.modules():
            if mod.__name__ == "io_scene_fbx":
                sys.path.append(os.path.dirname(os.path.dirname(mod.__file__)))
        from io_scene_fbx import parse_fbx
    root, _ver = parse_fbx.parse(path)

    def kids(el, name):
        return [c for c in el.elems if c.id == name]

    def p70(el):
        out = {}
        for p in kids(el, b"Properties70"):
            for q in p.elems:
                out[q.props[0].decode()] = q.props[4:]
        return out

    gs = p70(kids(root, b"GlobalSettings")[0])
    objects = kids(root, b"Objects")[0]
    models, geoms = {}, {}
    for el in objects.elems:
        if el.id == b"Model":
            models[el.props[0]] = (el.props[1].split(b"\x00")[0].decode(), p70(el))
        elif el.id == b"Geometry":
            geoms[el.props[0]] = kids(el, b"Vertices")[0].props[0]
    geo_of = {}
    for c in kids(root, b"Connections")[0].elems:
        if c.props[0] == b"OO" and c.props[1] in geoms and c.props[2] in models:
            geo_of[c.props[2]] = c.props[1]
    res = {"UpAxis": gs.get("UpAxis", [None])[0], "UpAxisSign": gs.get("UpAxisSign", [None])[0],
           "FrontAxis": gs.get("FrontAxis", [None])[0], "FrontAxisSign": gs.get("FrontAxisSign", [None])[0],
           "UnitScaleFactor": gs.get("UnitScaleFactor", [None])[0], "nodes": {}}
    for mid, (nm, pr) in models.items():
        t = list(pr.get("Lcl Translation", [0, 0, 0]))
        node = {"translation": [round(v, 4) for v in t],
                "rotation": [round(v, 4) for v in pr.get("Lcl Rotation", [0, 0, 0])],
                "scaling": [round(v, 4) for v in pr.get("Lcl Scaling", [1, 1, 1])]}
        if mid in geo_of:
            vv = geoms[geo_of[mid]]
            xs, ys, zs = vv[0::3], vv[1::3], vv[2::3]
            node["bbox_min"] = [round(min(xs) + t[0], 3), round(min(ys) + t[1], 3), round(min(zs) + t[2], 3)]
            node["bbox_max"] = [round(max(xs) + t[0], 3), round(max(ys) + t[1], 3), round(max(zs) + t[2], 3)]
        res["nodes"][nm] = node
    return res


def reimport_check():
    exp = {e["name"]: e for e in manifest_objs}
    report = {"fbx": {}, "obj": {}, "raw_fbx": {}, "mismatches": []}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=FBX_PATH, axis_forward='Z', axis_up='Y', global_scale=1.0)
    lo, hi = V((1e9,) * 3), V((-1e9,) * 3)
    tot = 0
    bpy.context.view_layer.update()
    for ob in bpy.context.scene.objects:
        if ob.type != 'MESH':
            continue
        me = ob.data
        me.calc_loop_triangles()
        tris = len(me.loop_triangles)
        tot += tris
        olo, ohi = V((1e9,) * 3), V((-1e9,) * 3)
        for v in me.vertices:
            p = ob.matrix_world @ v.co
            olo = V((min(olo.x, p.x), min(olo.y, p.y), min(olo.z, p.z)))
            ohi = V((max(ohi.x, p.x), max(ohi.y, p.y), max(ohi.z, p.z)))
        lo = V((min(lo.x, olo.x), min(lo.y, olo.y), min(lo.z, olo.z)))
        hi = V((max(hi.x, ohi.x), max(hi.y, ohi.y), max(hi.z, ohi.z)))
        piv = to_r(ob.matrix_world.translation)
        rot = [round(math.degrees(a), 3) for a in ob.matrix_world.to_euler()]
        scl = [round(a, 4) for a in ob.matrix_world.to_scale()]
        blo_, bhi_ = bbox_r(olo, ohi)
        report["fbx"][ob.name] = {"tris": tris, "pivot_studs": piv, "rotation_deg": rot, "scale": scl,
                                  "bbox_min_studs": blo_, "bbox_max_studs": bhi_,
                                  "has_vertex_colours": len(me.color_attributes) > 0}
        e = exp.get(ob.name)
        if e is None:
            report["mismatches"].append("unexpected object " + ob.name)
            continue
        if tris != e["triangles"]:
            report["mismatches"].append("%s tris %d != %d" % (ob.name, tris, e["triangles"]))
        if max(abs(a - b) for a, b in zip(piv, e["pivot_studs"])) > 0.01:
            report["mismatches"].append("%s pivot %s != %s" % (ob.name, piv, e["pivot_studs"]))
        if any(abs(a - 1) > 1e-3 for a in scl):
            report["mismatches"].append("%s scale %s" % (ob.name, scl))
        if max(abs(a - b) for a, b in zip(blo_ + bhi_, e["bbox_min_studs"] + e["bbox_max_studs"])) > 0.01:
            report["mismatches"].append("%s bbox differs" % ob.name)
    rlo_, rhi_ = bbox_r(lo, hi)
    size = [round(rhi_[i] - rlo_[i], 3) for i in range(3)]
    report["fbx"]["_overall"] = {"objects": len(report["fbx"]), "tris": tot, "size_studs_XYZ": size,
                                 "size_m_XYZ": [round(v * STUD, 4) for v in size], "min_studs": rlo_,
                                 "max_studs": rhi_}
    if max(abs(a - b) for a, b in zip(size, EXT_STUDS)) > 0.01:
        report["mismatches"].append("overall bbox %s != %s" % (size, EXT_STUDS))
    missing = [n for n in exp if n not in report["fbx"]]
    if missing:
        report["mismatches"].append("missing in FBX: %s" % missing)
    if tot != TOTAL:
        report["mismatches"].append("total tris %d != %d" % (tot, TOTAL))
    # OBJ
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=OBJ_PATH, forward_axis='Z', up_axis='Y', global_scale=1.0)
    lo, hi = V((1e9,) * 3), V((-1e9,) * 3)
    tot, n, names = 0, 0, []
    for ob in bpy.context.scene.objects:
        if ob.type != 'MESH':
            continue
        n += 1
        names.append(ob.name)
        me = ob.data
        me.calc_loop_triangles()
        tot += len(me.loop_triangles)
        for v in me.vertices:
            p = ob.matrix_world @ v.co
            lo = V((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = V((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
    rlo_, rhi_ = bbox_r(lo, hi)
    report["obj"] = {"objects": n, "tris": tot, "size_studs_XYZ": [round(rhi_[i] - rlo_[i], 3) for i in range(3)],
                     "names_match": sorted(names) == sorted(exp)}
    raw = raw_fbx(FBX_PATH)
    report["raw_fbx"] = raw
    for nm, node in raw["nodes"].items():
        e = exp.get(nm)
        if e and max(abs(a - b) for a, b in zip(node["translation"], e["pivot_studs"])) > 0.01:
            report["mismatches"].append("raw %s translation %s != %s" % (nm, node["translation"], e["pivot_studs"]))
    return report


REP = reimport_check()
with open(os.path.join(OUT, "import_check.json"), "w") as fh:
    json.dump(REP, fh, indent=2)
log("IMPORT CHECK fbx overall", REP["fbx"]["_overall"])
log("IMPORT CHECK obj", REP["obj"])
log("RAW FBX up/front/unit", REP["raw_fbx"]["UpAxis"], REP["raw_fbx"]["FrontAxis"], REP["raw_fbx"]["FrontAxisSign"],
    REP["raw_fbx"]["UnitScaleFactor"])
log("MISMATCHES", REP["mismatches"])
