#!/usr/bin/env python3
"""CityCar - generic compact executive electric sedan for "AI Empire" (Roblox).

Fully reproducible, headless Blender (bpy 5.0.1) script:

    python3 model.py               # build, export FBX/OBJ, manifest, import check, renders
    python3 model.py --no-render   # everything except the Cycles renders

Frames
------
* Built in metres in Blender's frame: +X = car LEFT, +Y = REAR, +Z = UP, origin on the ground,
  on the centre line, half-way between the axles.
* Every mesh is then scaled by 1/0.28 (Roblox: 1 stud = 0.28 m), so 1 Blender unit = 1 stud.
* FBX export with axis_forward='Z', axis_up='Y' maps Blender (x, y, z) -> file (-x, z, y), which is
  Roblox's own frame: front = -Z (the Model's LookVector), right = +X, up = +Y.

No brand names, logos or trademarked design elements: the shape is a generic modern EV sedan
built from published dimensions of the segment (see README.md for sources).
"""
import bpy
import bmesh
import math
import os
import sys
import json
import time
from mathutils import Vector, Matrix

OUT = os.path.dirname(os.path.abspath(__file__))
NAME = "CityCar"
STUD = 0.28                      # m per stud (create.roblox.com/docs/physics/units)
S = 1.0 / STUD                   # metres -> studs
DO_RENDER = "--no-render" not in sys.argv
rad = math.radians

# ----------------------------------------------------------------------------------------------
# 1) target dimensions (m) - averaged from two published mid-size EV sedans (README "Sources"):
#    reference A = 2024 four-door EV sedan (4720 x 1850 x 1441, wb 2875, track 1584, 235/45 R18),
#    reference B = 2021 EV "gran coupe" (4783 x 1852 x 1448, wb 2856, track 1601/1630, gc 125)
# ----------------------------------------------------------------------------------------------
LENGTH = 4.750          # A 4.720 / B 4.783
WIDTH = 1.850           # body, without mirrors (A 1.850 / B 1.852)
HEIGHT = 1.445          # A 1.441 / B 1.448
WHEELBASE = 2.865       # A 2.875 / B 2.856
OH_F = 0.860            # front overhang (A's earlier 4.694 m body: 0.841); rear = the rest
OH_R = LENGTH - WHEELBASE - OH_F   # 1.025
TRACK_F = 1.593         # A 1.584 / B 1.601
TRACK_R = 1.607         # A 1.584 / B 1.630
GROUND_CLEAR = 0.132    # A 0.138-0.140 / B 0.125
MIRROR_W = 2.080        # width over mirrors (A 2.088 / B 2.073)
TYRE_W = 0.235          # 235/45 R18 (A's standard tyre)
TYRE_AR = 0.45
RIM_R = 18 * 0.0254 / 2                  # 0.2286
TYRE_R = RIM_R + TYRE_W * TYRE_AR        # 0.33435
YF = -WHEELBASE / 2 - OH_F               # front bumper (-2.2925)
YR = WHEELBASE / 2 + OH_R                # rear bumper (+2.4575)
YAF, YAR = -WHEELBASE / 2, WHEELBASE / 2
ZA = TYRE_R                              # axle height (static, unladen tyre radius)

# greenhouse stations (m, along +Y = rearwards)
Y_COWL = -1.05       # windshield base
Y_RF = -0.22         # windshield top / roof front
Y_RR = 0.78          # roof rear / backlight top
Y_DECK = 1.92        # backlight base / trunk lid
FRIT = 0.04          # black ceramic border on windshield/backlight

# ----------------------------------------------------------------------------------------------
# scene reset
# ----------------------------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
SCENE = bpy.context.scene
SCENE.unit_settings.system = 'NONE'      # Roblox Blender guide: Unit System = None
SCENE.unit_settings.scale_length = 1.0
COLL = SCENE.collection

# ----------------------------------------------------------------------------------------------
# 2) materials: (sRGB hex, roughness, metallic, emission, vertex-colour override)
#    Roblox gives one colour per MeshPart, so every face also carries its material colour as an
#    FBX vertex colour. Studio multiplies vertex colour by MeshPart.Color; the paint is baked WHITE
#    so the game can tint Body to any company colour while trim/glass/lights keep their colours.
# ----------------------------------------------------------------------------------------------
MATDEF = {
    "Paint":        ("2B5A86", 0.28, 0.35, 0.0, "FFFFFF"),
    "Trim_Black":   ("121417", 0.22, 0.0, 0.0, None),
    "Roof_Black":   ("0A0D11", 0.06, 0.0, 0.0, None),
    "Cladding":     ("1D1F22", 0.70, 0.0, 0.0, None),
    "Chrome":       ("C9CDD3", 0.15, 1.0, 0.0, None),
    "Panel_Gap":    ("0C0D0F", 0.80, 0.0, 0.0, None),
    "Wheelwell":    ("17181A", 0.90, 0.0, 0.0, None),
    "Underbody":    ("1A1B1D", 0.85, 0.0, 0.0, None),
    "Headlight":    ("F3F6FF", 0.10, 0.0, 4.0, None),
    "Taillight":    ("D8101F", 0.15, 0.0, 3.0, None),
    "Body_Inner":   ("2A2C30", 0.80, 0.0, 0.0, None),
    "Mirror_Glass": ("A9B3BD", 0.05, 1.0, 0.0, None),
    "Glass":        ("6E8696", 0.02, 0.0, 0.0, "1E2A33"),
    "Tire":         ("1C1C1E", 0.85, 0.0, 0.0, None),
    "Rim_Silver":   ("BCC1C8", 0.25, 0.9, 0.0, None),
    "Wheel_Dark":   ("2A2D31", 0.50, 0.3, 0.0, None),
    "Hub_Dark":     ("3A3D42", 0.40, 0.5, 0.0, None),
    "Interior_Dark": ("2B2D31", 0.75, 0.0, 0.0, None),
    "Seat_Leather": ("D9D3C6", 0.55, 0.0, 0.0, None),
    "Interior_Trim": ("9EA3AA", 0.35, 0.6, 0.0, None),
    "Screen":       ("0E1A26", 0.10, 0.0, 0.6, None),
}


def srgb(hexs):
    return tuple(int(hexs[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


MATS = {}
for nm, (hx, rough, metal, emit, _vc) in MATDEF.items():
    m = bpy.data.materials.new(nm)
    if m.node_tree is None:
        m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    col = lin(srgb(hx)) + (1.0,)
    b.inputs["Base Color"].default_value = col
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if nm == "Paint":
        b.inputs["Coat Weight"].default_value = 0.8
        b.inputs["Coat Roughness"].default_value = 0.05
    if nm == "Glass":
        b.inputs["Transmission Weight"].default_value = 1.0
        b.inputs["IOR"].default_value = 1.45
    if emit > 0:
        b.inputs["Emission Color"].default_value = col
        b.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = col
    MATS[nm] = m


def vcolor(nm):
    hx, _r, _m, _e, vc = MATDEF[nm]
    return srgb(vc or hx)


# ----------------------------------------------------------------------------------------------
# 3) small math helpers
# ----------------------------------------------------------------------------------------------
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


def new_faces_since(bm, before):
    return [f for f in bm.faces if f not in before]


# ----------------------------------------------------------------------------------------------
# 4) body: side/plan profiles (m).  Y = station (front -2.29 ... rear +2.46)
# ----------------------------------------------------------------------------------------------
LXF, LZTF, LZBF, ZCF = 0.40, 0.32, 0.12, 0.42     # nose round-over: plan depth, top, bottom, centre z
LXR, LZTR, LZBR, ZCR = 0.34, 0.07, 0.20, 0.72     # tail round-over
Y0F, Y0R = YF + LXF, YR - LXR

ZB = Curve([(-1.95, 0.230), (-1.70, 0.158), (-1.40, GROUND_CLEAR), (1.60, GROUND_CLEAR), (1.95, 0.200), (2.16, 0.312)])
ZSH = Curve([(-1.95, 0.565), (-1.50, 0.640), (-0.50, 0.660), (1.00, 0.700), (1.60, 0.730), (2.16, 0.725)])
HWB = Curve([(-1.95, 0.875), (-1.75, 0.905), (-1.43, 0.921), (-1.00, 0.918), (0.00, 0.912), (1.00, 0.918),
             (1.45, 0.925), (1.85, 0.918), (2.12, 0.872)])
ZBELT = Curve([(-1.95, 0.655), (-1.60, 0.752), (Y_COWL, 0.895), (-0.60, 0.945), (0.20, 0.975), (1.00, 1.000),
               (1.90, 1.015), (2.16, 1.010)])
HWBELT = Curve([(-1.95, 0.780), (-1.60, 0.830), (Y_COWL, 0.855), (-0.60, 0.860), (0.50, 0.862), (1.30, 0.870),
                (1.85, 0.863), (2.12, 0.808)])
ZTOP = Curve([(-1.95, 0.705), (-1.60, 0.800), (-1.30, 0.875), (Y_COWL, 0.945), (-0.635, 1.175), (Y_RF, 1.405),
              (0.15, 1.445), (0.45, 1.438), (Y_RR, 1.395), (1.35, 1.228), (Y_DECK, 1.040), (2.05, 1.034),
              (2.16, 1.040)])
ZRAIL = Curve([(-1.95, 0.677), (-1.60, 0.772), (-1.30, 0.847), (Y_COWL, 0.925), (-0.635, 1.1425), (Y_RF, 1.360),
               (0.15, 1.390), (0.45, 1.385), (Y_RR, 1.350), (1.35, 1.185), (Y_DECK, 1.035), (2.05, 1.031),
               (2.16, 1.034)])
HWRAIL = Curve([(-1.95, 0.715), (-1.60, 0.760), (Y_COWL, 0.785), (-0.635, 0.720), (Y_RF, 0.655), (0.15, 0.648),
                (Y_RR, 0.645), (1.35, 0.705), (Y_DECK, 0.795), (2.05, 0.790), (2.12, 0.758)])
PHIE = Curve([(-1.95, 85.0), (-1.25, 85.0), (-0.85, 62.0), (1.50, 62.0), (1.95, 85.0), (2.16, 85.0)])
BOW = Curve([(-1.95, 0.004), (-1.10, 0.004), (-0.80, 0.012), (1.45, 0.012), (1.90, 0.004), (2.16, 0.004)])
SCALLOP = Curve([(-1.02, 0.0), (-0.85, 0.013), (0.92, 0.013), (1.06, 0.0)])
I_SKIRT = 3                        # ring point that ends the black side skirt

RING_HALF = 16                     # points per half ring (bottom centre .. top centre)
I_C4, I_C4B, I_DM, I_C5, I_C5B = 8, 9, 10, 11, 12


def ring_half(y):
    zb, zsh, hwb = ZB(y), ZSH(y), HWB(y)
    hwf = hwb - 0.105
    z4, hw4, z5, hw5, z6 = ZBELT(y), HWBELT(y), ZRAIL(y), HWRAIL(y), ZTOP(y)
    pe = rad(PHIE(y))
    pts = [(0.0, zb), (hwf, zb)]
    n = 2.6                                  # rocker -> shoulder: superellipse quadrant
    for th in (-64.0, -46.0, -22.0, 0.0):
        t = rad(th)
        c, s = abs(math.cos(t)), abs(math.sin(t))
        dent = SCALLOP(y) if th == -22.0 else 0.0       # lower-door scallop (soft light catch)
        pts.append((hwf + (hwb - hwf) * c ** (2.0 / n) - dent, zsh - (zsh - zb) * s ** (2.0 / n)))
    a = (hwb - hw4) / (1.0 - math.cos(pe))  # shoulder -> belt arc ending at C4
    b = (z4 - zsh) / math.sin(pe)
    xc = hwb - a
    for f in (0.4, 0.75, 1.0):
        p = pe * f
        pts.append((xc + a * math.cos(p), zsh + b * math.sin(p)))
    dx, dz = hw5 - hw4, z5 - z4                 # side band C4 -> C5 (window / hood edge)
    lb = math.hypot(dx, dz)
    nx, nz = dz / lb, -dx / lb
    t4b = min(0.02 / lb, 0.3)
    pts.append((hw4 + dx * t4b, z4 + dz * t4b))                       # C4b (chrome belt strip)
    bw = BOW(y)
    pts.append((hw4 + dx * 0.55 + nx * bw, z4 + dz * 0.55 + nz * bw))  # Dm
    pts.append((hw5, z5))                                              # C5 (roof rail / A-pillar)
    for x in (hw5 - FRIT, hw5 * 0.62, hw5 * 0.30):                     # crown
        pts.append((x, z6 - (z6 - z5) * (x / hw5) ** 2))
    pts.append((0.0, z6))
    assert len(pts) == RING_HALF
    return pts


def ring_at(y):
    if y < Y0F:
        base = ring_half(Y0F)
        d = y - YF
        sx, st, sb = se(d / LXF, 2.5), se(d / LZTF, 1.6), se(d / LZBF, 2.0)
        return [(x * sx, ZCF + (z - ZCF) * (st if z > ZCF else sb)) for x, z in base]
    if y > Y0R:
        base = ring_half(Y0R)
        d = YR - y
        sx, st, sb = se(d / LXR, 2.5), se(d / LZTR, 2.6), se(d / LZBR, 2.0)
        return [(x * sx, ZCR + (z - ZCR) * (st if z > ZCR else sb)) for x, z in base]
    return ring_half(y)


def stations():
    ys = [YF + LXF * t for t in (0.006, 0.028, 0.07, 0.14, 0.25, 0.42, 0.68)]
    keys = [Y_COWL, Y_COWL + FRIT, Y_RF, Y_RR, Y_DECK - FRIT, Y_DECK]
    mid = []
    n = 23
    for i in range(n + 1):
        mid.append(Y0F + (Y0R - Y0F) * i / n)
    mid = [y for y in mid if all(abs(y - k) > 0.045 for k in keys)] + keys
    ys += sorted(mid)
    ys += [YR - LXR * t for t in (0.68, 0.42, 0.25, 0.14, 0.07, 0.028, 0.006)]
    return ys


def build_body_loft():
    bm = bmesh.new()
    ys = stations()
    print("  stations:", len(ys))
    rings = []
    for y in ys:
        h = ring_at(y)
        full = h + [(-x, z) for x, z in reversed(h[1:-1])]
        rings.append([bm.verts.new((x, y, z)) for x, z in full])
    pf = bm.verts.new((0.0, YF, ZCF))
    pr = bm.verts.new((0.0, YR, ZCR))
    n = len(rings[0])
    for a, b in zip(rings[:-1], rings[1:]):
        for j in range(n):
            k = (j + 1) % n
            bm.faces.new((a[j], a[k], b[k], b[j]))
    for j in range(n):
        k = (j + 1) % n
        bm.faces.new((pf, rings[0][k], rings[0][j]))
        bm.faces.new((pr, rings[-1][j], rings[-1][k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def bm_to_object(bm, name, mats=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    if mats:
        for m in mats:
            me.materials.append(MATS[m])
    ob = bpy.data.objects.new(name, me)
    COLL.objects.link(ob)
    return ob


def apply_modifiers(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)
    return ob


# wheel wells (boolean)
ARCH_R = 0.385
WELL_X = {YAF: 0.50, YAR: 0.585}     # inner wall of the well (front lower: room to steer)


def well_cutter(y_axle, side):
    bm = bmesh.new()
    x0 = WELL_X[y_axle]
    x1 = 1.30
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=48, radius1=ARCH_R, radius2=ARCH_R,
                          depth=x1 - x0)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(rad(90), 3, 'Y'))
    bmesh.ops.translate(bm, verts=bm.verts, vec=(side * (x0 + x1) / 2, y_axle, ZA))
    return bm_to_object(bm, "cutter")


def in_well(c):
    for ya, xw in WELL_X.items():
        if abs(c.x) >= xw - 1e-4 and (c.y - ya) ** 2 + (c.z - ZA) ** 2 <= (ARCH_R + 1e-5) ** 2:
            return True
    return False


# zone planes (normals have no X component -> they cut both sides)
def plane_through(y0, z0, y1, z1):
    d = Vector((0.0, y1 - y0, z1 - z0)).normalized()
    n = Vector((1.0, 0.0, 0.0)).cross(d).normalized()
    return Vector((0.0, y0, z0)), n


A_SHIFT = 0.16
A_CO, A_NO = plane_through(Y_COWL + A_SHIFT, ZRAIL(Y_COWL), Y_RF + A_SHIFT, ZRAIL(Y_RF))   # behind -> dot<0
C_CO, C_NO = plane_through(1.32, 1.00, 0.70, 1.37)                                       # in front -> dot>0
B_Y0, B_Y1 = 0.11, 0.19
GAPS = [-0.93, 0.15, 1.00]
GAP_W = 0.004
HANDLES = [(-0.42, -0.27), (0.62, 0.76)]
HANDLE_Z = (0.872, 0.902)
HL_CO1, HL_NO1 = Vector((0.0, 0.0, 0.548)), Vector((-0.09, 0.0, 1.0)).normalized()   # lower edge rises outward
HL_CO2, HL_NO2 = Vector((0.0, 0.0, 0.603)), Vector((-0.05, 0.0, 1.0)).normalized()
HL_XIN = 0.40
HL_YEND = YF + 0.25                  # wrap-around end of the headlight strips (clean vertical cut)
TL_YEND = YR - 0.17                  # wrap-around end of the rear light bar
HLH = (0.016, 0.008, 0.025, 0.022)   # gloss-black housing around the strips: below, above, inboard, wrap
GRILLE_Z = (0.25, 0.36)
VENT_X = (0.665, 0.745)
VENT_Z = 0.46
PLATE_R = (0.26, 0.50, 0.62)       # rear plate recess: half width, z0, z1
GRILLE_X = 0.52
TL_Z = (0.872, 0.930)
DIFF_Z = 0.37
SKIRT_Z = 0.25


def dot_plane(p, co, no):
    return (p - co).dot(no)


def a_behind(p):
    q = Vector((0.0, p.y, p.z))
    return dot_plane(q, A_CO, A_NO) < 0


def c_front(p):
    q = Vector((0.0, p.y, p.z))
    return dot_plane(q, C_CO, C_NO) > 0


def mirror_plane(co, no):
    """the same plane mirrored to -X (for planes with an X component)"""
    return Vector((-co.x, co.y, co.z)), Vector((-no.x, no.y, no.z))


OUTER_ONLY = [None]      # material index of the outer skin once the shell exists (detail cuts skip the inside)


def cut(bm, co, no, pred):
    bm.normal_update()
    oi = OUTER_ONLY[0]
    faces = [f for f in bm.faces if (oi is None or f.material_index == oi) and pred(f.calc_center_median(), f.normal)]
    if not faces:
        return
    edges = list({e for f in faces for e in f.edges})
    verts = list({v for f in faces for v in f.verts})
    bmesh.ops.bisect_plane(bm, geom=verts + edges + faces, dist=1e-6, plane_co=co, plane_no=no,
                           clear_inner=False, clear_outer=False)


def band_side(c):
    """face centre lies in the side band (between belt C4 and rail C5) of the greenhouse"""
    return abs(c.x) > HWRAIL(c.y) - 1e-3 and ZBELT(c.y) - 0.004 < c.z < ZRAIL(c.y) + 0.004


def window_cuts(bm):
    band = lambda c, n: abs(c.x) > HWRAIL(c.y) - 0.01 and ZBELT(c.y) - 0.012 < c.z < ZRAIL(c.y) + 0.01
    cut(bm, A_CO, A_NO, lambda c, n: band(c, n) and -1.15 < c.y < 0.1)
    cut(bm, C_CO, C_NO, lambda c, n: band(c, n) and 0.5 < c.y < 1.6)
    for y in (B_Y0, B_Y1):
        cut(bm, Vector((0, y, 0)), Vector((0, 1, 0)), lambda c, n: band(c, n) and -0.2 < c.y < 0.5)


def detail_cuts(bm):
    side = lambda c, n: abs(n.x) > 0.45 and SKIRT_Z - 0.05 < c.z < ZBELT(c.y) + 0.01
    for g in GAPS:
        for y in (g - GAP_W, g + GAP_W):
            cut(bm, Vector((0, y, 0)), Vector((0, 1, 0)), lambda c, n, g=g: side(c, n) and abs(c.y - g) < 0.2)
    for (y0, y1) in HANDLES:
        for y in (y0, y1):
            cut(bm, Vector((0, y, 0)), Vector((0, 1, 0)),
                lambda c, n, y0=y0, y1=y1: abs(n.x) > 0.45 and 0.80 < c.z < 0.96 and y0 - 0.2 < c.y < y1 + 0.2)
        for z in HANDLE_Z:
            cut(bm, Vector((0, 0, z)), Vector((0, 0, 1)),
                lambda c, n, y0=y0, y1=y1: abs(n.x) > 0.45 and 0.80 < c.z < 0.96 and y0 - 0.02 < c.y < y1 + 0.02)
    front = lambda c, n: c.y < -1.80
    rear = lambda c, n: c.y > 1.85
    for co, no in ((HL_CO1, HL_NO1), (HL_CO2, HL_NO2)):
        cut(bm, co, no, lambda c, n: front(c, n) and c.x > -0.05 and 0.40 < c.z < 0.80)
        mco, mno = mirror_plane(co, no)
        cut(bm, mco, mno, lambda c, n: front(c, n) and c.x < 0.05 and 0.40 < c.z < 0.80)
    for co, no in ((HL_CO1 - Vector((0, 0, HLH[0])), HL_NO1), (HL_CO2 + Vector((0, 0, HLH[1])), HL_NO2)):
        cut(bm, co, no, lambda c, n: front(c, n) and c.x > -0.05 and 0.40 < c.z < 0.80)
        mco, mno = mirror_plane(co, no)
        cut(bm, mco, mno, lambda c, n: front(c, n) and c.x < 0.05 and 0.40 < c.z < 0.80)
    for x in (HL_XIN, -HL_XIN, HL_XIN - HLH[2], -HL_XIN + HLH[2]):
        cut(bm, Vector((x, 0, 0)), Vector((1, 0, 0)), lambda c, n: front(c, n) and 0.45 < c.z < 0.72)
    for y in (HL_YEND, HL_YEND + HLH[3]):
        cut(bm, Vector((0, y, 0)), Vector((0, 1, 0)), lambda c, n: front(c, n) and 0.42 < c.z < 0.78)
    cut(bm, Vector((0, TL_YEND, 0)), Vector((0, 1, 0)), lambda c, n: rear(c, n) and 0.65 < c.z < 1.10)
    for z in GRILLE_Z:
        cut(bm, Vector((0, 0, z)), Vector((0, 0, 1)), lambda c, n: front(c, n) and 0.18 < c.z < 0.45)
    for x in (GRILLE_X, -GRILLE_X):
        cut(bm, Vector((x, 0, 0)), Vector((1, 0, 0)), lambda c, n: c.y < -2.0 and 0.20 < c.z < 0.42)
    for x in VENT_X + tuple(-v for v in VENT_X):
        cut(bm, Vector((x, 0, 0)), Vector((1, 0, 0)), lambda c, n: c.y < -1.95 and 0.20 < c.z < 0.50)
    cut(bm, Vector((0, 0, VENT_Z)), Vector((0, 0, 1)), lambda c, n: c.y < -1.95 and abs(c.x) > 0.55 and 0.35 < c.z < 0.52)
    for z in TL_Z:
        cut(bm, Vector((0, 0, z)), Vector((0, 0, 1)), lambda c, n: rear(c, n) and 0.65 < c.z < 1.10)
    cut(bm, Vector((0, 0, DIFF_Z)), Vector((0, 0, 1)), lambda c, n: rear(c, n) and 0.28 < c.z < 0.46)
    for x in (PLATE_R[0], -PLATE_R[0]):
        cut(bm, Vector((x, 0, 0)), Vector((1, 0, 0)), lambda c, n: c.y > 2.2 and 0.45 < c.z < 0.67)
    for z in PLATE_R[1:]:
        cut(bm, Vector((0, 0, z)), Vector((0, 0, 1)), lambda c, n: c.y > 2.2 and abs(c.x) < 0.35 and 0.45 < c.z < 0.67)


BODY_OUTER = ["Paint", "Trim_Black", "Roof_Black", "Cladding", "Chrome", "Panel_Gap", "Wheelwell",
              "Underbody", "Headlight", "Taillight", "Mirror_Glass"]
BI = {m: i for i, m in enumerate(BODY_OUTER)}


def classify(bm, faces=None):
    """returns {face: zone} where zone in BODY_OUTER or 'GLASS'"""
    bm.normal_update()
    zone = {}
    for f in (bm.faces if faces is None else faces):
        c = f.calc_center_median()
        n = f.normal
        ax = abs(c.x)
        z = "Paint"
        if in_well(c):
            z = "Wheelwell"
        elif n.z < -0.55 and c.z < 0.40:
            z = "Underbody"
        elif Y_COWL - 0.005 < c.y < Y_DECK + 0.005 and ax < HWRAIL(c.y) - 1e-3 and c.z > ZBELT(c.y):
            # top region of the greenhouse (between the two rails)
            if Y_RF < c.y < Y_RR:
                z = "Roof_Black"
            elif (Y_COWL + FRIT < c.y < Y_RF or Y_RR < c.y < Y_DECK - FRIT) and ax < HWRAIL(c.y) - FRIT + 1e-3:
                z = "GLASS"
            else:
                z = "Trim_Black"
        elif -1.2 < c.y < 1.6 and band_side(c) and c.z > 0.84:
            above_trim = c.z > ZBELT(c.y) + 0.0005 and _above_c4b(c)
            between = a_behind(c) and c_front(c)
            if between and not above_trim:
                z = "Chrome"
            elif between and B_Y0 < c.y < B_Y1:
                z = "Trim_Black"
            elif between:
                z = "GLASS"
        if z == "Paint":
            if any(abs(c.y - g) < GAP_W for g in GAPS) and abs(n.x) > 0.45 and \
                    ring_half(c.y)[I_SKIRT][1] < c.z < ZBELT(c.y) - 0.003:
                z = "Panel_Gap"
            elif any(y0 < c.y < y1 for y0, y1 in HANDLES) and HANDLE_Z[0] < c.z < HANDLE_Z[1] and abs(n.x) > 0.45:
                z = "Chrome"
            elif c.y < HL_YEND and ax > HL_XIN and n.z < 0.97 and \
                    dot_plane(Vector((ax, 0, c.z)), HL_CO1, HL_NO1) > 0 and \
                    dot_plane(Vector((ax, 0, c.z)), HL_CO2, HL_NO2) < 0:
                z = "Headlight"
            elif c.y < HL_YEND + HLH[3] and ax > HL_XIN - HLH[2] and n.z < 0.97 and \
                    dot_plane(Vector((ax, 0, c.z)), HL_CO1 - Vector((0, 0, HLH[0])), HL_NO1) > 0 and \
                    dot_plane(Vector((ax, 0, c.z)), HL_CO2 + Vector((0, 0, HLH[1])), HL_NO2) < 0:
                z = "Trim_Black"
            elif c.y < -2.0 and ax < GRILLE_X and GRILLE_Z[0] < c.z < GRILLE_Z[1] and n.y < -0.4:
                z = "Cladding"
            elif c.y < -1.95 and VENT_X[0] < ax < VENT_X[1] and GRILLE_Z[0] < c.z < VENT_Z and n.y < -0.3:
                z = "Cladding"
            elif c.y > TL_YEND and TL_Z[0] < c.z < TL_Z[1] and n.z < 0.8:
                z = "Taillight"
            elif c.y > 2.2 and ax < PLATE_R[0] and PLATE_R[1] < c.z < PLATE_R[2] and n.y > 0.5:
                z = "Trim_Black"
            elif c.y > 1.85 and c.z < DIFF_Z and n.y > 0.25:
                z = "Cladding"
            elif abs(n.x) > 0.3 and abs(c.y) < 1.12 and c.z < ring_half(c.y)[I_SKIRT][1]:
                z = "Cladding"
        zone[f] = z
    return zone


def _above_c4b(c):
    """above the chrome strip: compare with C4b of the ring at this station"""
    h = ring_half(c.y)
    return c.z > h[I_C4B][1] - 0.0008


# mirrors (closed shells added to Body after solidify)
def build_mirror(bm, side):
    """door mirror: teardrop housing (Paint), glass plate (Mirror_Glass), arm (Trim_Black)"""
    yc, zc = -0.80, 1.040
    dy_f, dy_r, dz = 0.080, 0.030, 0.056
    secs = [(0.885, 0.70), (0.925, 0.95), (0.978, 1.0), (1.020, 0.93), (MIRROR_W / 2, 0.62)]
    nseg = 14
    rings = []
    before = set(bm.faces)
    for x, s in secs:
        r = []
        for k in range(nseg):
            t = 2 * math.pi * k / nseg
            c, sn = math.cos(t), math.sin(t)
            yy = yc + (dy_r * abs(c) ** (2 / 3.0) if c >= 0 else -dy_f * abs(c) ** (2 / 2.2))
            zz = zc + dz * s * math.copysign(abs(sn) ** (2 / 3.0), sn)
            yy = yc + (yy - yc) * s
            r.append(bm.verts.new((side * x, yy, zz)))
        rings.append(r)
    for a, b in zip(rings[:-1], rings[1:]):
        for k in range(nseg):
            k2 = (k + 1) % nseg
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    housing = new_faces_since(bm, before)
    for f in housing:
        f.material_index = BI["Paint"]
    # glass plate on the rear face
    before = set(bm.faces)
    g = bmesh.ops.create_cube(bm, size=1.0)
    for v in g["verts"]:
        v.co = Vector((side * (0.958 + v.co.x * 0.10), yc + dy_r * 0.93 + v.co.y * 0.010, zc + v.co.z * 0.080))
    for f in new_faces_since(bm, before):
        f.material_index = BI["Mirror_Glass"]
    # arm into the door skin
    before = set(bm.faces)
    g = bmesh.ops.create_cube(bm, size=1.0)
    for v in g["verts"]:
        v.co = Vector((side * (0.875 + v.co.x * 0.075), -0.79 + v.co.y * 0.050, 0.985 + v.co.z * 0.030))
    for f in new_faces_since(bm, before):
        f.material_index = BI["Trim_Black"]


def build_body():
    bm = build_body_loft()
    body = bm_to_object(bm, "Body_tmp")
    bm.free()
    for ya in (YAF, YAR):
        for side in (1, -1):
            cu = well_cutter(ya, side)
            mod = body.modifiers.new("well", 'BOOLEAN')
            mod.operation = 'DIFFERENCE'
            mod.solver = 'EXACT'
            mod.object = cu
            apply_modifiers(body)
            bpy.data.objects.remove(cu)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bpy.data.objects.remove(body)
    # boolean n-gons can be concave (centroid outside the face): triangulate before classifying
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4], quad_method='BEAUTY',
                          ngon_method='BEAUTY')
    print("  body after boolean: %d faces, %d tris" % (len(bm.faces), sum(len(f.verts) - 2 for f in bm.faces)))
    # (a) window outlines, glazing out, shell
    window_cuts(bm)
    zone = classify(bm)
    glass_faces = [f for f, z in zone.items() if z == "GLASS"]
    bm.normal_update()
    glass = shell_from_faces(glass_faces, -0.004, 0.006, "Glass")
    bmesh.ops.delete(bm, geom=glass_faces, context='FACES')
    for f in bm.faces:
        f.material_index = 0
    ob = bm_to_object(bm, "Body", ["Paint", "Body_Inner", "Trim_Black"])
    bm.free()
    mod = ob.modifiers.new("shell", 'SOLIDIFY')       # inner skin -> slot 1, window reveals -> slot 2
    mod.thickness = 0.025
    mod.offset = -1.0
    mod.use_rim = True
    mod.use_even_offset = True
    mod.use_quality_normals = True
    mod.material_offset = 1
    mod.material_offset_rim = 2
    apply_modifiers(ob)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for v in bm.verts:                    # inner skin must not poke below the floor at the well corners
        if v.co.z < GROUND_CLEAR - 1e-4:
            v.co.z = GROUND_CLEAR + 0.0015
    print("  body after solidify: %d tris" % sum(len(f.verts) - 2 for f in bm.faces))
    # (b) detail lines on the outer skin only, then colour zones
    OUTER_ONLY[0] = 0
    detail_cuts(bm)
    OUTER_ONLY[0] = None
    final = BODY_OUTER + ["Body_Inner"]
    inner, rim = [], []
    for f in bm.faces:
        if f.material_index == 1:
            inner.append(f)
        elif f.material_index == 2:
            rim.append(f)
    outer = [f for f in bm.faces if f.material_index == 0]
    zone = classify(bm, outer)
    for f, z in zone.items():
        f.material_index = BI["Trim_Black"] if z == "GLASS" else BI[z]
    for f in inner:
        f.material_index = len(BODY_OUTER)
    for f in rim:
        f.material_index = BI["Trim_Black"]
    bm.normal_update()
    head = shell_from_faces([f for f, z in zone.items() if z == "Headlight"], 0.004, 0.009, "Headlight")
    tail = shell_from_faces([f for f, z in zone.items() if z == "Taillight"], 0.004, 0.009, "Taillight")
    print("  body after details: %d tris" % sum(len(f.verts) - 2 for f in bm.faces))
    for side in (1, -1):
        build_mirror(bm, side)
    ob.data.materials.clear()
    for m in final:
        ob.data.materials.append(MATS[m])
    bm.to_mesh(ob.data)
    bm.free()
    return ob, glass, head, tail


def shell_from_faces(faces, offset, thick, matname):
    """copy a set of surface faces, push along the normals by `offset` and give them `thick` inwards"""
    bm2 = bmesh.new()
    vmap = {}
    for f in faces:
        for v in f.verts:
            if v not in vmap:
                vmap[v] = bm2.verts.new(v.co)
    for f in faces:
        bm2.faces.new([vmap[v] for v in f.verts])
    bm2.normal_update()
    for v in bm2.verts:
        v.co += v.normal * offset
    ob = bm_to_object(bm2, matname, [matname])
    bm2.free()
    mod = ob.modifiers.new("shell", 'SOLIDIFY')
    mod.thickness = thick
    mod.offset = -1.0
    mod.use_rim = True
    mod.use_even_offset = True
    mod.use_quality_normals = True
    apply_modifiers(ob)
    return ob


# ----------------------------------------------------------------------------------------------
# 5) wheels
# ----------------------------------------------------------------------------------------------
def revolve(bm, prof, nseg, mat):
    """revolve a closed (x, r) profile about the X axis"""
    rings = []
    for k in range(nseg):
        t = 2 * math.pi * k / nseg
        c, s = math.cos(t), math.sin(t)
        rings.append([bm.verts.new((x, r * c, r * s)) for x, r in prof])
    n = len(prof)
    out = []
    for k in range(nseg):
        a, b = rings[k], rings[(k + 1) % nseg]
        for j in range(n):
            j2 = (j + 1) % n
            f = bm.faces.new((a[j], a[j2], b[j2], b[j]))
            f.material_index = mat
            out.append(f)
    return out


def cylinder_x(bm, x0, x1, r, nseg, mat, phase=0.0):
    rings = []
    for x in (x0, x1):
        rings.append([bm.verts.new((x, r * math.cos(2 * math.pi * k / nseg + phase),
                                    r * math.sin(2 * math.pi * k / nseg + phase))) for k in range(nseg)])
    for k in range(nseg):
        k2 = (k + 1) % nseg
        bm.faces.new((rings[0][k], rings[0][k2], rings[1][k2], rings[1][k])).material_index = mat
    bm.faces.new(rings[0][::-1]).material_index = mat
    bm.faces.new(rings[1]).material_index = mat


WHEEL_MATS = ["Tire", "Rim_Silver", "Wheel_Dark", "Hub_Dark"]


def build_wheel_bm():
    """wheel centred at the origin, axle along X, outer face towards +X"""
    bm = bmesh.new()
    rb, w2, R = RIM_R, TYRE_W / 2, TYRE_R
    tyre = [(0.098, rb), (w2, rb + 0.050), (0.106, R - 0.016), (0.084, R),
            (-0.084, R), (-0.106, R - 0.016), (-w2, rb + 0.050), (-0.098, rb)]
    NSEG = 24
    revolve(bm, tyre, NSEG, 0)
    rim = [(0.0975, rb - 0.0005), (0.108, rb + 0.010), (0.113, 0.212), (-0.100, 0.207), (-0.100, rb - 0.0005)]
    revolve(bm, rim, NSEG, 1)
    cylinder_x(bm, 0.018, 0.032, 0.212, 20, 2)            # dark wheel face behind the spokes
    cylinder_x(bm, 0.030, 0.090, 0.072, 14, 1)            # hub
    cylinder_x(bm, 0.088, 0.097, 0.034, 10, 3)            # centre cap
    # 5 twin spokes
    for k in range(5):
        for dphi in (-6.5, 6.5):
            phi = rad(k * 72 + dphi + 90)
            before = set(bm.faces)
            g = bmesh.ops.create_cube(bm, size=1.0)
            for v in g["verts"]:
                u = v.co.y + 0.5                           # 0 at hub, 1 at rim
                r = 0.062 + u * (0.214 - 0.062)
                wdt = 0.020 + u * 0.010
                xf = 0.088 + u * 0.014                     # concave face: outer end proud
                x = 0.036 + (v.co.x + 0.5) * (xf - 0.036)
                lat = v.co.z * wdt
                v.co = Vector((x, r * math.cos(phi) - lat * math.sin(phi), r * math.sin(phi) + lat * math.cos(phi)))
            for f in new_faces_since(bm, before):
                f.material_index = 1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# ----------------------------------------------------------------------------------------------
# 6) interior, seats, steering wheel
# ----------------------------------------------------------------------------------------------
def rbox(bm, center, size, bev, mat, rot_x=0.0, pivot=None):
    """chamfered box. rot_x tilts about X (degrees) around `pivot` (default: centre)"""
    before = set(bm.faces)
    g = bmesh.ops.create_cube(bm, size=1.0)
    vs = g["verts"]
    for v in vs:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bev > 0:
        es = list({e for v in vs for e in v.link_edges})
        bmesh.ops.bevel(bm, geom=vs + es, offset=bev, offset_type='OFFSET', segments=1, profile=0.5,
                        affect='EDGES', clamp_overlap=True)
    nf = new_faces_since(bm, before)
    nv = list({v for f in nf for v in f.verts})
    R = Matrix.Rotation(rad(rot_x), 3, 'X')
    c = Vector(center)
    p = Vector(pivot) if pivot is not None else c
    for v in nv:
        v.co = R @ (v.co + c - p) + p
    for f in nf:
        f.material_index = mat
    return nf


SEAT_MATS = ["Seat_Leather", "Interior_Dark"]
SEAT_TOP = 0.505          # cushion top above ground (m)
SEAT_X = 0.375            # driver on the car's left (Roblox -X), same side as the game's DriverSeat
SEAT_Y = -0.16


def build_seat(bm, x, y, mats=(0, 1)):
    L, D = mats
    rbox(bm, (x, y, SEAT_TOP - 0.065), (0.50, 0.50, 0.13), 0.035, L)                      # cushion
    rbox(bm, (x, y + 0.02, 0.385), (0.36, 0.40, 0.09), 0.0, D)                             # base / rails
    hinge = (x, y + 0.25, SEAT_TOP - 0.02)
    rbox(bm, (x, y + 0.30, SEAT_TOP + 0.30), (0.50, 0.12, 0.62), 0.035, L, rot_x=-18, pivot=hinge)  # backrest
    rbox(bm, (x, y + 0.31, SEAT_TOP + 0.70), (0.26, 0.10, 0.17), 0.03, L, rot_x=-18, pivot=hinge)   # headrest
    for s in (-1, 1):                                                                       # bolsters
        rbox(bm, (x + s * 0.22, y + 0.28, SEAT_TOP + 0.22), (0.07, 0.15, 0.42), 0.02, L, rot_x=-18, pivot=hinge)


INTERIOR_MATS = ["Interior_Dark", "Seat_Leather", "Interior_Trim", "Screen"]


def build_interior_bm():
    bm = bmesh.new()
    D, L, T, SC = 0, 1, 2, 3
    rbox(bm, (0, 0.0, 0.255), (1.58, 2.00, 0.17), 0.0, D)                     # floor / battery top
    # dashboard: loft across X of a side profile
    prof = [(-1.02, 0.905), (-0.90, 0.940), (-0.72, 0.935), (-0.655, 0.905), (-0.640, 0.800), (-0.700, 0.630),
            (-0.880, 0.480), (-1.020, 0.420)]
    xs = [-0.79, -0.70, -0.25, 0.25, 0.70, 0.79]
    rings = []
    for x in xs:
        shrink = 0.0 if abs(x) < 0.75 else 0.02
        rings.append([bm.verts.new((x, y, z - shrink)) for y, z in prof])
    n = len(prof)
    for a, b in zip(rings[:-1], rings[1:]):
        for j in range(n):
            j2 = (j + 1) % n
            bm.faces.new((a[j], a[j2], b[j2], b[j])).material_index = D
    bm.faces.new(rings[0]).material_index = D
    bm.faces.new(rings[-1][::-1]).material_index = D
    rbox(bm, (0, -0.660, 0.870), (1.50, 0.03, 0.035), 0.0, T)                 # trim strip / air vent bar
    rbox(bm, (0, -0.700, 1.035), (0.34, 0.02, 0.21), 0.006, SC, rot_x=-12)    # centre touch screen
    rbox(bm, (0, -0.15, 0.48), (0.22, 1.00, 0.28), 0.03, D)                   # centre console
    rbox(bm, (0, -0.15, 0.625), (0.20, 0.55, 0.02), 0.0, T)                   # console top
    build_seat(bm, -SEAT_X, SEAT_Y, (L, D))                                   # front passenger
    rbox(bm, (0, 0.62, 0.43), (1.36, 0.50, 0.15), 0.04, L)                    # rear bench
    rbox(bm, (0, 0.95, 0.70), (1.36, 0.12, 0.56), 0.04, L, rot_x=-20, pivot=(0, 0.90, 0.47))
    for x in (-0.45, 0.0, 0.45):
        rbox(bm, (x, 0.97, 1.03), (0.24, 0.09, 0.13), 0.025, L, rot_x=-20, pivot=(0, 0.90, 0.47))
    rbox(bm, (0, 1.55, 0.985), (1.40, 0.62, 0.025), 0.0, D)                   # parcel shelf
    for s in (-1, 1):                                                          # door armrests
        rbox(bm, (s * 0.80, -0.30, 0.68), (0.06, 0.55, 0.06), 0.015, T)
        rbox(bm, (s * 0.80, 0.62, 0.68), (0.06, 0.40, 0.06), 0.015, T)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


STEER_C = Vector((SEAT_X, -0.50, 0.86))
STEER_TILT = 24.0                         # column angle above horizontal
STEER_AXIS = Vector((0.0, math.cos(rad(STEER_TILT)), math.sin(rad(STEER_TILT))))  # towards the driver
STEER_MATS = ["Interior_Dark", "Interior_Trim"]


def build_steering_bm():
    """built around the origin with the column along +Y, then tilted; pivot = hub centre"""
    bm = bmesh.new()
    Rm, rr = 0.185, 0.016
    nu, nv = 18, 6
    rings = []
    for i in range(nu):
        u = 2 * math.pi * i / nu
        r = []
        for j in range(nv):
            v = 2 * math.pi * j / nv
            rad_ = Rm + rr * math.cos(v)
            r.append(bm.verts.new((rad_ * math.cos(u), rr * math.sin(v), rad_ * math.sin(u))))
        rings.append(r)
    for i in range(nu):
        a, b = rings[i], rings[(i + 1) % nu]
        for j in range(nv):
            j2 = (j + 1) % nv
            bm.faces.new((a[j], a[j2], b[j2], b[j])).material_index = 0
    before = set(bm.faces)
    g = bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.058, radius2=0.050, depth=0.05)
    bmesh.ops.rotate(bm, verts=g["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(rad(-90), 3, 'X'))
    for f in new_faces_since(bm, before):
        f.material_index = 0
    for ang in (0.0, 180.0, 270.0):                         # 3-spoke: left, right, down
        a = rad(ang)
        before = set(bm.faces)
        g = bmesh.ops.create_cube(bm, size=1.0)
        for v in g["verts"]:
            rr_ = 0.04 + (v.co.x + 0.5) * (Rm - 0.045)
            lat = v.co.z * 0.035
            v.co = Vector((rr_ * math.cos(a) - lat * math.sin(a), v.co.y * 0.018, rr_ * math.sin(a) + lat * math.cos(a)))
        for f in new_faces_since(bm, before):
            f.material_index = 1
    # column stub into the dash
    before = set(bm.faces)
    g = bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.032, radius2=0.032, depth=0.24)
    bmesh.ops.rotate(bm, verts=g["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(rad(-90), 3, 'X'))
    bmesh.ops.translate(bm, verts=g["verts"], vec=(0, -0.13, 0))
    for f in new_faces_since(bm, before):
        f.material_index = 0
    # tilt: local +Y (column, towards the driver) -> STEER_AXIS
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(rad(STEER_TILT), 3, 'X'))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# ----------------------------------------------------------------------------------------------
# 7) assemble objects (metres), set pivots
# ----------------------------------------------------------------------------------------------
t0 = time.time()
body, glass, headl, taill = build_body()
print("body built %.1fs" % (time.time() - t0))

objs = {"Body": body, "Glass": glass, "Headlights": headl, "Taillights": taill}
headl.name = "Headlights"
taill.name = "Taillights"
glass.name = "Glass"

WHEELS = {
    "Wheel_FL": (+TRACK_F / 2, YAF, +1),
    "Wheel_FR": (-TRACK_F / 2, YAF, -1),
    "Wheel_RL": (+TRACK_R / 2, YAR, +1),
    "Wheel_RR": (-TRACK_R / 2, YAR, -1),
}
for nm, (x, y, side) in WHEELS.items():
    bm = build_wheel_bm()
    if side < 0:
        bmesh.ops.scale(bm, vec=(-1, 1, 1), verts=bm.verts)
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    ob = bm_to_object(bm, nm, WHEEL_MATS)
    bm.free()
    ob.location = (x, y, ZA)          # pivot = wheel centre (axle along local X)
    objs[nm] = ob

bm = build_interior_bm()
objs["Interior"] = bm_to_object(bm, "Interior", INTERIOR_MATS)
bm.free()

bm = bmesh.new()
build_seat(bm, 0.0, 0.0, (0, 1))
bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, -SEAT_TOP))   # pivot = cushion top centre
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
ob = bm_to_object(bm, "Seat_Driver", SEAT_MATS)
bm.free()
ob.location = (SEAT_X, SEAT_Y, SEAT_TOP)
objs["Seat_Driver"] = ob

bm = build_steering_bm()
ob = bm_to_object(bm, "SteeringWheel", STEER_MATS)
bm.free()
ob.location = STEER_C
objs["SteeringWheel"] = ob

# move glass / lights / interior origins to the model origin (they are static, welded to Body)
for nm in ("Body", "Glass", "Headlights", "Taillights", "Interior"):
    objs[nm].location = (0, 0, 0)


# ----------------------------------------------------------------------------------------------
# 8) finish meshes: triangulate, normals, smoothing, vertex colours, checks; scale to studs
# ----------------------------------------------------------------------------------------------
SMOOTH_DEG = {"Body": 38.0, "Glass": 30.0, "Headlights": 30.0, "Taillights": 30.0, "Interior": 35.0,
              "Seat_Driver": 35.0, "SteeringWheel": 40.0}


def finish(ob, smooth_deg):
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-7)
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method='BEAUTY', ngon_method='BEAUTY')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # scale to studs (object-local data and the pivot location)
    bmesh.ops.scale(bm, vec=(S, S, S), verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    ob.location = ob.location * S
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=rad(smooth_deg))
    # vertex colours (sRGB bytes, face corners)
    ca = me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
    mats = [m.name for m in me.materials]
    for p in me.polygons:
        c = vcolor(mats[p.material_index]) + (1.0,)
        for li in p.loop_indices:
            ca.data[li].color_srgb = c
    me.color_attributes.active_color = ca
    me.update()


def mesh_report(ob):
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    nonman = sum(1 for e in bm.edges if not e.is_manifold)
    tris = len(bm.faces)
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
    ngons = sum(1 for f in bm.faces if len(f.verts) > 3)
    bm.free()
    return {"tris": tris, "non_manifold_edges": nonman, "signed_volume_studs3": round(vol, 4), "shells": shells,
            "ngons": ngons}


for nm, ob in objs.items():
    finish(ob, SMOOTH_DEG.get(nm, 35.0))

# ----------------------------------------------------------------------------------------------
# 9) export FBX + OBJ
# ----------------------------------------------------------------------------------------------
fbx_path = os.path.join(OUT, NAME + ".fbx")
obj_path = os.path.join(OUT, NAME + ".obj")
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.export_scene.fbx(filepath=fbx_path, use_selection=False, object_types={'MESH'},
                         global_scale=1.0, apply_unit_scale=True, apply_scale_options='FBX_SCALE_UNITS',
                         axis_forward='Z', axis_up='Y', use_space_transform=True, bake_space_transform=True,
                         use_mesh_modifiers=True, mesh_smooth_type='FACE', colors_type='SRGB',
                         use_triangles=True, use_tspace=False, add_leaf_bones=False, bake_anim=False,
                         path_mode='COPY', embed_textures=True, use_custom_props=False)
bpy.ops.wm.obj_export(filepath=obj_path, export_selected_objects=False, forward_axis='Z', up_axis='Y',
                      global_scale=1.0, apply_modifiers=True, export_uv=True, export_normals=True,
                      export_colors=False, export_materials=True, export_triangulated_mesh=True,
                      export_object_groups=False, export_material_groups=False, path_mode='STRIP')
print("exported")


# ----------------------------------------------------------------------------------------------
# 10) manifest (Roblox frame, studs): Blender (x, y, z) -> Roblox (-x, z, y)
# ----------------------------------------------------------------------------------------------
def to_r(v):
    return [round(-v[0], 4), round(v[2], 4), round(v[1], 4)]


def dir_r(v):
    v = Vector(v).normalized()
    return [round(-v.x, 5) + 0.0, round(v.z, 5) + 0.0, round(v.y, 5) + 0.0]


def bbox_world(ob):
    pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def bbox_r(lo, hi):
    a, b = to_r(lo), to_r(hi)
    return [min(a[i], b[i]) for i in range(3)], [max(a[i], b[i]) for i in range(3)]


SPIN_NOTE = ("spin about +X; forward roll (car moving towards -Z) is a NEGATIVE angle: "
             "part.CFrame = pivot * CFrame.Angles(-distance/radius, 0, 0)")
INFO = {
    "Body": dict(kind="static", role="painted shell, mirrors, trim, wheel wells; tint with MeshPart.Color",
                 can_collide=True, meshpart_color="company colour (paint zone is white in the vertex colours)"),
    "Glass": dict(kind="static", role="all glazing (windshield, side windows, backlight)", can_collide=False,
                  meshpart_color=[255, 255, 255], transparency=0.35, material="Glass"),
    "Headlights": dict(kind="static", role="front light strips; set Material=Neon for lights on",
                       can_collide=False, meshpart_color=[255, 255, 255]),
    "Taillights": dict(kind="static", role="full-width rear light bar; Neon for brake/lights on",
                       can_collide=False, meshpart_color=[255, 255, 255]),
    "Interior": dict(kind="static", role="floor, dashboard, screen, console, passenger + rear seats",
                     can_collide=False, meshpart_color=[255, 255, 255]),
    "Seat_Driver": dict(kind="anchor", role="driver seat mesh; pivot = cushion top centre (VehicleSeat goes here)",
                        can_collide=False, meshpart_color=[255, 255, 255]),
    "SteeringWheel": dict(kind="rotating", role="steering wheel; rotate about the column axis", can_collide=False,
                          meshpart_color=[255, 255, 255]),
}
for nm in WHEELS:
    INFO[nm] = dict(kind="wheel", role="tyre + rim; spins about local X; front wheels also steer about Y",
                    can_collide=False, meshpart_color=[255, 255, 255])

ORDER = ["Body", "Glass", "Headlights", "Taillights", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR",
         "Interior", "Seat_Driver", "SteeringWheel"]
manifest_objs = []
total = 0
problems = []
for nm in ORDER:
    ob = objs[nm]
    rep = mesh_report(ob)
    total += rep["tris"]
    if rep["tris"] > 20000:
        problems.append(nm + " over 20k triangles")
    if rep["non_manifold_edges"]:
        problems.append("%s: %d non-manifold edges" % (nm, rep["non_manifold_edges"]))
    if rep["signed_volume_studs3"] <= 0:
        problems.append(nm + ": non-positive volume (inward normals?)")
    lo, hi = bbox_world(ob)
    rlo, rhi = bbox_r(lo, hi)
    piv = ob.location
    e = {"name": nm, **INFO[nm], "triangles": rep["tris"], "materials": [m.name for m in ob.data.materials],
         "pivot_studs": to_r(piv), "pivot_m": [round(c * STUD, 4) for c in to_r(piv)],
         "bbox_min_studs": rlo, "bbox_max_studs": rhi,
         "size_studs": [round(rhi[i] - rlo[i], 4) for i in range(3)],
         "mesh_check": rep}
    if nm.startswith("Wheel_"):
        e["spin_axis"] = [1.0, 0.0, 0.0]
        e["spin"] = SPIN_NOTE
        e["radius_studs"] = round(TYRE_R * S, 4)
        e["radius_m"] = round(TYRE_R, 5)
        e["width_m"] = TYRE_W
        e["tyre"] = "235/45 R18"
        if nm in ("Wheel_FL", "Wheel_FR"):
            e["steer_axis"] = [0.0, 1.0, 0.0]
            e["steer_limits_deg"] = [-30.0, 30.0]
            e["steer_note"] = "positive angle about +Y turns the wheel's front towards the car's left (-X)"
    if nm == "SteeringWheel":
        e["hinge_axis"] = dir_r(STEER_AXIS)
        e["hinge_axis_note"] = "column axis, pointing from the dashboard towards the driver"
        e["rotation_limits_deg"] = [-450.0, 450.0]
        e["suggested_game_limits_deg"] = [-120.0, 120.0]
        e["rotation_note"] = ("positive angle (right-hand rule about hinge_axis) turns the rim counter-clockwise "
                              "as seen by the driver = steering LEFT")
    if nm == "Seat_Driver":
        e["seat_note"] = ("Weld a VehicleSeat (Size 2,0.5,2, Transparency 1) so its top face is at the pivot: "
                          "seat.CFrame = Seat_Driver:GetPivot() * CFrame.new(0, -0.25, 0)")
    manifest_objs.append(e)

all_lo = Vector((1e9, 1e9, 1e9))
all_hi = Vector((-1e9, -1e9, -1e9))
for ob in objs.values():
    lo, hi = bbox_world(ob)
    all_lo = Vector(tuple(min(a, b) for a, b in zip(all_lo, lo)))
    all_hi = Vector(tuple(max(a, b) for a, b in zip(all_hi, hi)))
rlo, rhi = bbox_r(all_lo, all_hi)
ext = [rhi[i] - rlo[i] for i in range(3)]
blo, bhi = bbox_r(*bbox_world(objs["Body"]))
body_ext = [bhi[i] - blo[i] for i in range(3)]
bw = objs["Body"]
body_w = 2 * max(abs(v.co.x) for v in bw.data.vertices if v.co.z < 0.90 * S)   # below the mirrors
piv = {nm: Vector(objs[nm].location) for nm in WHEELS}
wb_meas = (piv["Wheel_RL"].y - piv["Wheel_FL"].y)
trf_meas = (piv["Wheel_FL"].x - piv["Wheel_FR"].x)
trr_meas = (piv["Wheel_RL"].x - piv["Wheel_RR"].x)


def surface_y(z, front=True):
    """station where the centre line of the nose/tail reaches height z (for plate anchors)"""
    best = None
    for i in range(1, 400):
        d = 0.0006 * i
        y = YF + d if front else YR - d
        h = ring_at(y)
        zlo, zhi = h[0][1], h[-1][1]
        if zlo <= z <= zhi:
            best = y
            break
    return best


def mm(v):
    return {"m": round(v * STUD, 4), "studs": round(v, 3)}


manifest = {
    "name": NAME,
    "generic_identity": "CityCar - generic compact executive electric sedan (no brand, no logos)",
    "units": {"studs_per_metre": round(S, 6), "metres_per_stud": STUD,
              "source": "https://create.roblox.com/docs/physics/units (1 stud = 28 cm)"},
    "frame": {"forward": "-Z (Model LookVector)", "right": "+X", "up": "+Y",
              "origin": "ground level, car centre line, half-way between the axles",
              "driver_side": "left (-X), like the game's DriverSeat at x = -1.35"},
    "dimensions_measured_from_mesh": {
        "length": mm(body_ext[2]),
        "width_body_without_mirrors": mm(body_w),
        "width_over_mirrors": mm(body_ext[0]),
        "height": mm(ext[1]),
        "ground_clearance": mm(blo[1]),
        "wheelbase": mm(wb_meas),
        "track_front": mm(trf_meas),
        "track_rear": mm(trr_meas),
        "wheel_diameter": mm(2 * TYRE_R * S),
        "front_overhang": mm(-blo[2] - wb_meas / 2),
        "rear_overhang": mm(bhi[2] - wb_meas / 2),
        "overall_bbox_studs_XYZ": [round(v, 3) for v in ext],
        "overall_bbox_min_studs": rlo, "overall_bbox_max_studs": rhi,
    },
    "dimensions_target_m": {"length": LENGTH, "width": WIDTH, "height": HEIGHT, "wheelbase": WHEELBASE,
                            "track_front": TRACK_F, "track_rear": TRACK_R, "ground_clearance": GROUND_CLEAR,
                            "width_over_mirrors": MIRROR_W, "front_overhang": OH_F, "rear_overhang": round(OH_R, 4),
                            "tyre": "235/45 R18 (diameter %.4f m)" % (2 * TYRE_R)},
    "anchors": {
        "seat_driver_top_studs": to_r(Vector((SEAT_X, SEAT_Y, SEAT_TOP)) * S),
        "seat_passenger_top_studs": to_r(Vector((-SEAT_X, SEAT_Y, SEAT_TOP)) * S),
        "front_plate_centre_studs": to_r(Vector((0.0, surface_y(0.315, True), 0.315)) * S),
        "rear_plate_centre_studs": to_r(Vector((0.0, surface_y(0.56, False), 0.56)) * S),
        "plate_note": "centre of the plate face on the bumper surface; plate faces -Z (front) / +Z (rear)",
        "ground_contact_y_studs": 0.0,
    },
    "game_config_relation": {
        "CampusConfig.CARS.executive": {"length_studs": 15, "width_studs": 7},
        "model_length_studs": round(body_ext[2], 3), "model_body_width_studs": round(body_w, 3),
        "model_width_over_mirrors_studs": round(body_ext[0], 3),
        "scale_to_match_config_length": round(15.0 / body_ext[2], 4),
        "note": "Model is real-world size at 1 stud = 0.28 m. Model:ScaleTo(scale_to_match_config_length) "
                "makes it as long as the procedural 'executive' car if the garage needs it.",
    },
    "triangles_total": total,
    "triangle_limit_per_mesh": 20000,
    "triangle_limit_source": "https://create.roblox.com/docs/art/modeling/specifications",
    "objects": manifest_objs,
    "materials": {m: {"srgb_hex": MATDEF[m][0], "vertex_colour_hex": (MATDEF[m][4] or MATDEF[m][0])}
                  for m in MATDEF},
    "export": {"fbx": NAME + ".fbx", "obj": NAME + ".obj",
               "fbx_settings": "axis_forward=Z, axis_up=Y, apply_scale_options=FBX_SCALE_UNITS, global_scale=1, "
                               "bake_space_transform, mesh_smooth_type=FACE, colors_type=SRGB, triangulated, "
                               "no leaf bones, no animation, path_mode=COPY+embed (no textures used)",
               "blender_units": "1 Blender unit = 1 stud (scene Unit System None, Unit Scale 1.0)"},
    "problems": problems,
}
with open(os.path.join(OUT, "manifest.json"), "w") as fh:
    json.dump(manifest, fh, indent=2)
print("TOTAL TRIS", total, "PROBLEMS", problems)
for e in manifest_objs:
    print("  %-14s %6d tris  pivot %s" % (e["name"], e["triangles"], e["pivot_studs"]))
print("OVERALL studs", [round(v, 3) for v in ext], "m", [round(v * STUD, 3) for v in ext])
print("DIMS", json.dumps(manifest["dimensions_measured_from_mesh"]))


# ----------------------------------------------------------------------------------------------
# 11) renders (Cycles CPU)
# ----------------------------------------------------------------------------------------------
def setup_render():
    sc = SCENE
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 12 if PREVIEW else 40
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.03
    try:
        sc.cycles.use_denoising = True
        sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    except Exception:
        sc.cycles.use_denoising = False
        sc.cycles.samples = 96
    sc.cycles.max_bounces = 6
    sc.cycles.transmission_bounces = 6
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Medium High Contrast'
    w = bpy.data.worlds.new("Sky")
    sc.world = w
    if w.node_tree is None:
        w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.60, 0.70, 0.86, 1.0)
    bg.inputs[1].default_value = 1.0
    sun = bpy.data.lights.new("Sun", 'SUN')
    sun.energy = 3.0
    sun.angle = rad(3.0)
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (rad(48), rad(10), rad(-140))
    COLL.objects.link(so)
    fill = bpy.data.lights.new("Fill", 'AREA')
    fill.energy = 2500.0
    fill.size = 20.0
    fo = bpy.data.objects.new("Fill", fill)
    fo.location = (25, -25, 20)
    fo.rotation_euler = (Vector((0, 0, 3)) - Vector(fo.location)).to_track_quat('-Z', 'Y').to_euler()
    COLL.objects.link(fo)
    gm = bpy.data.materials.new("Ground")
    if gm.node_tree is None:
        gm.use_nodes = True
    gb = gm.node_tree.nodes.get("Principled BSDF")
    gb.inputs["Base Color"].default_value = (0.20, 0.21, 0.22, 1.0)
    gb.inputs["Roughness"].default_value = 0.65
    gme = bpy.data.meshes.new("Ground")
    gbm = bmesh.new()
    bmesh.ops.create_grid(gbm, x_segments=1, y_segments=1, size=400.0)
    gbm.to_mesh(gme)
    gbm.free()
    gme.materials.append(gm)
    go = bpy.data.objects.new("Ground", gme)
    COLL.objects.link(go)
    return go


def camera(name, loc, target, ortho=None, lens=50.0):
    cam = bpy.data.cameras.new(name)
    co = bpy.data.objects.new(name, cam)
    COLL.objects.link(co)
    co.location = loc
    d = (Vector(target) - Vector(loc)).normalized()
    co.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    if ortho:
        cam.type = 'ORTHO'
        cam.ortho_scale = ortho
    else:
        cam.lens = lens
    cam.clip_end = 2000
    return co


def render(co, path, res=(1280, 720)):
    if PREVIEW:
        res = (res[0] * 3 // 4, res[1] * 3 // 4)
        path = path.replace(".png", "_prev.png")
    SCENE.camera = co
    SCENE.render.resolution_x, SCENE.render.resolution_y = res
    SCENE.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    print("rendered", os.path.basename(path), "%.1fs" % (time.time() - t))


ONLY = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--only=")]
PREVIEW = "--preview" in sys.argv
if DO_RENDER:
    setup_render()
    k = S
    views = [
        ("render_front.png", camera("cam_front", (0, -60 * k, 0.74 * k), (0, 0, 0.74 * k), ortho=3.5 * k), (1280, 720)),
        ("render_side.png", camera("cam_side", (60 * k, 0.08 * k, 0.72 * k), (0, 0.08 * k, 0.72 * k), ortho=5.3 * k),
         (1280, 720)),
        ("render_top.png", camera("cam_top", (0, 0.08 * k, 60 * k), (0, 0.08 * k, 0), ortho=5.3 * k), (1280, 720)),
        ("render_34.png", camera("cam_34", (4.6 * k, -6.2 * k, 2.1 * k), (0, -0.15 * k, 0.62 * k), lens=45),
         (1280, 720)),
        ("render_34_rear.png", camera("cam_34r", (-4.8 * k, 6.0 * k, 2.0 * k), (0, 0.2 * k, 0.65 * k), lens=45),
         (1280, 720)),
        ("render_closeup.png", camera("cam_close", (2.15 * k, -3.05 * k, 0.95 * k), (0.75 * k, -1.55 * k, 0.45 * k),
                                      lens=50), (1280, 720)),
        ("render_interior.png", camera("cam_int", (2.3 * k, 1.7 * k, 2.3 * k), (0.05 * k, -0.25 * k, 0.55 * k),
                                       lens=32), (1280, 720)),
    ]
    top = [v for v in views if v[0] == "render_top.png"][0][1]
    top.rotation_euler = (0, 0, rad(90))
    for fn, co, res in views:
        if ONLY and fn not in ONLY:
            continue
        cutaway = fn == "render_interior.png"
        for nm in ("Body", "Glass"):
            objs[nm].hide_render = cutaway        # interior shot: body + glazing hidden (cut-away)
        render(co, os.path.join(OUT, fn), res)
    for nm in ("Body", "Glass"):
        objs[nm].hide_render = False

    # what Studio shows: vertex colours x MeshPart.Color (Body tinted with the game's fallback company
    # colour 91,125,100 from VehicleService; every other part white), glass 35 % transparent
    def vc_material(name, tint=(1, 1, 1), alpha=1.0):
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
        mix.inputs[7].default_value = lin(tint) + (1.0,)
        nt.links.new(mix.outputs[2], b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = 0.5
        b.inputs["Alpha"].default_value = alpha
        return m

    vc_body = vc_material("VC_Body", tuple(c / 255.0 for c in (91, 125, 100)))
    vc_white = vc_material("VC_White")
    vc_glass = vc_material("VC_Glass", alpha=0.65)
    saved = {}
    for nm, ob in objs.items():
        saved[nm] = list(ob.data.materials)
        sub = vc_body if nm == "Body" else (vc_glass if nm == "Glass" else vc_white)
        for i in range(len(ob.data.materials)):
            ob.data.materials[i] = sub
    fn = "render_roblox_preview.png"
    if not ONLY or fn in ONLY:
        render(camera("cam_vc", (4.6 * k, -6.2 * k, 2.1 * k), (0, -0.15 * k, 0.62 * k), lens=45),
               os.path.join(OUT, fn), (1280, 720))
    for nm, ob in objs.items():
        for i, m in enumerate(saved[nm]):
            ob.data.materials[i] = m
    print("RENDERS DONE")


# ----------------------------------------------------------------------------------------------
# 12) re-import check: load the exported FBX/OBJ into an empty scene and measure them
# ----------------------------------------------------------------------------------------------
def raw_fbx(path):
    """parse the FBX without any axis conversion (the file's own Y-up frame, as Studio reads it)"""
    addons = os.path.join(os.path.dirname(bpy.__file__), "%d.%d" % bpy.app.version[:2], "scripts", "addons_core")
    if addons not in sys.path:
        sys.path.append(addons)
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
    models = {}
    geoms = {}
    for el in objects.elems:
        if el.id == b"Model":
            nm = el.props[1].split(b"\x00")[0].decode()
            pr = p70(el)
            models[el.props[0]] = (nm, pr)
        elif el.id == b"Geometry":
            vv = kids(el, b"Vertices")[0].props[0]
            geoms[el.props[0]] = vv
    conns = kids(root, b"Connections")[0]
    geo_of = {}
    for c in conns.elems:
        if c.props[0] == b"OO" and c.props[1] in geoms and c.props[2] in models:
            geo_of[c.props[2]] = c.props[1]
    res = {"UpAxis": gs.get("UpAxis", [None])[0], "UpAxisSign": gs.get("UpAxisSign", [None])[0],
           "FrontAxis": gs.get("FrontAxis", [None])[0], "FrontAxisSign": gs.get("FrontAxisSign", [None])[0],
           "CoordAxis": gs.get("CoordAxis", [None])[0], "UnitScaleFactor": gs.get("UnitScaleFactor", [None])[0],
           "nodes": {}}
    for mid, (nm, pr) in models.items():
        t = list(pr.get("Lcl Translation", [0, 0, 0]))
        r = list(pr.get("Lcl Rotation", [0, 0, 0]))
        s = list(pr.get("Lcl Scaling", [1, 1, 1]))
        node = {"translation": [round(v, 4) for v in t], "rotation": [round(v, 4) for v in r],
                "scaling": [round(v, 4) for v in s]}
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
    # FBX through Blender's importer (converts back to Blender's frame)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fbx_path, axis_forward='Z', axis_up='Y', global_scale=1.0)
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    tot = 0
    for ob in bpy.context.scene.objects:
        if ob.type != 'MESH':
            continue
        bpy.context.view_layer.update()
        me = ob.data
        me.calc_loop_triangles()
        tris = len(me.loop_triangles)
        tot += tris
        pts = [ob.matrix_world @ v.co for v in me.vertices]
        for p in pts:
            lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
        piv = to_r(ob.matrix_world.translation)
        e = exp.get(ob.name)
        rot = [round(math.degrees(a), 3) for a in ob.matrix_world.to_euler()]
        scl = [round(a, 4) for a in ob.matrix_world.to_scale()]
        report["fbx"][ob.name] = {"tris": tris, "pivot_studs": piv, "rotation_deg": rot, "scale": scl,
                                  "has_vertex_colours": len(me.color_attributes) > 0}
        if e is None:
            report["mismatches"].append("unexpected object " + ob.name)
            continue
        if tris != e["triangles"]:
            report["mismatches"].append("%s tris %d != %d" % (ob.name, tris, e["triangles"]))
        if max(abs(a - b) for a, b in zip(piv, e["pivot_studs"])) > 0.01:
            report["mismatches"].append("%s pivot %s != %s" % (ob.name, piv, e["pivot_studs"]))
        if max(abs(a) for a in scl) and any(abs(a - 1) > 1e-3 for a in scl):
            report["mismatches"].append("%s scale %s" % (ob.name, scl))
    rlo, rhi = bbox_r(lo, hi)
    size = [round(rhi[i] - rlo[i], 3) for i in range(3)]
    report["fbx"]["_overall"] = {"objects": len(report["fbx"]), "tris": tot, "size_studs_XYZ": size,
                                 "size_m_XYZ": [round(v * STUD, 4) for v in size], "min_studs": rlo, "max_studs": rhi}
    missing = [n for n in exp if n not in report["fbx"]]
    if missing:
        report["mismatches"].append("missing in FBX: %s" % missing)
    # OBJ
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=obj_path, forward_axis='Z', up_axis='Y', global_scale=1.0)
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    tot = 0
    n = 0
    for ob in bpy.context.scene.objects:
        if ob.type != 'MESH':
            continue
        n += 1
        me = ob.data
        me.calc_loop_triangles()
        tot += len(me.loop_triangles)
        for v in me.vertices:
            p = ob.matrix_world @ v.co
            lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
    rlo, rhi = bbox_r(lo, hi)
    report["obj"] = {"objects": n, "tris": tot, "size_studs_XYZ": [round(rhi[i] - rlo[i], 3) for i in range(3)]}
    # raw FBX
    raw = raw_fbx(fbx_path)
    report["raw_fbx"] = raw
    for nm, node in raw["nodes"].items():
        e = exp.get(nm)
        if e and max(abs(a - b) for a, b in zip(node["translation"], e["pivot_studs"])) > 0.01:
            report["mismatches"].append("raw %s translation %s != %s" % (nm, node["translation"], e["pivot_studs"]))
    return report


rep = reimport_check()
with open(os.path.join(OUT, "import_check.json"), "w") as fh:
    json.dump(rep, fh, indent=2)
print("IMPORT CHECK fbx overall", rep["fbx"]["_overall"])
print("IMPORT CHECK obj", rep["obj"])
print("RAW FBX up/front/unit", rep["raw_fbx"]["UpAxis"], rep["raw_fbx"]["FrontAxis"], rep["raw_fbx"]["FrontAxisSign"],
      rep["raw_fbx"]["UnitScaleFactor"])
print("MISMATCHES", rep["mismatches"])
