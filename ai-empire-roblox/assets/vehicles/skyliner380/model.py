#!/usr/bin/env python3
"""
Skyliner380 - generic full-length double-deck, four-engine wide-body airliner for the
Roblox game "AI Empire".  Proportions follow the Airbus A380-800 (published Airbus
"A380 Aircraft Characteristics - Airport and Maintenance Planning" document, see README),
but the model carries NO real brand names, logos or liveries (fictional "AI Empire Air").

Reproducible build (headless):
    python3 model.py                 # bpy 5.0.x installed as a Python module
    blender -b -P model.py           # or with a Blender 5.0 binary
Options (after the script name or after "--"):
    --no-render      skip the Cycles renders
    --no-verify      skip FBX/glTF re-import checks
    --no-motion      skip the motion (retraction / deflection clash) checks

Outputs next to this file:
    Skyliner380.fbx (Roblox), Skyliner380.gltf (alternative, unverified in Studio),
    Skyliner380.obj + .mtl (DCC interchange only), manifest.json, renders/*.png

Conventions
    * Geometry is authored in metres in "aircraft coordinates" A = (s, b, z):
        s = station, metres aft of the nose tip; b = lateral, + = starboard (right);
        z = height above ground (tyre contact patch = 0).
    * Blender space (metres, before scaling): X = -b, Y = s - S0, Z = z   (nose points to -Y,
      Blender's "front" convention).  S0 = 35.5 m = main-gear centroid -> model origin.
    * At the end everything is scaled by K = 1/0.28 so that 1 Blender unit = 1 Roblox stud
      (Roblox: 1 stud = 28 cm).  FBX export: Apply Scalings = "FBX Units Scale",
      Forward = Z, Up = Y (Roblox docs) -> Roblox model space X = right, Y = up, -Z = nose.
"""
import bpy, bmesh, math, json, os, sys, time
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
import numpy as np

ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
DO_RENDER = '--no-render' not in ARGS
DO_VERIFY = '--no-verify' not in ARGS
DO_MOTION = '--no-motion' not in ARGS

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = 'Skyliner380'
RENDER_DIR = os.path.join(HERE, 'renders')
STUD_M = 0.28                 # Roblox: 1 stud = 28 cm  (create.roblox.com/docs/physics/units)
K = 1.0 / STUD_M              # metres -> studs
S0 = 35.5                     # model origin station (m aft of nose) ~ centroid of 20 main wheels
ROBLOX_TRI_LIMIT = 20000      # per mesh (create.roblox.com/docs/art/modeling/specifications)

# ----------------------------------------------------------------------------------------
# reference data (metres).  Source: Airbus A380 AC doc (Rev. Nov 2012, figures 2-2-0, 2-3-0,
# 2-7-0, 7-2-0).  Profiles were traced from the official 3-view at 21.2 px/m and corrected
# for outline thickness; key numbers are quoted in the README.
# ----------------------------------------------------------------------------------------
REF = dict(length=72.72, length_ac_fig=72.73, span=79.75, height=24.09, fus_width=7.14,
           fus_height=8.41, wing_area=845.0, sweep_qc=33.5, hstab_span=30.37,
           nose_gear_s=4.97, wlg_s=33.58, blg_s=36.85, wlg_track=12.456, blg_track=5.264,
           wlg_axle=1.70, blg_axle=1.70, wlg_wheel_gap=1.35, blg_wheel_gap=1.53, nlg_wheel_gap=1.05,
           main_tyre=(1.40, 0.53), nose_tyre=(1.27, 0.455),
           eng_inner=(22.23, 14.80), eng_outer=(29.94, 25.70))

# ---------------- colours (sRGB) - fictional "AI Empire Air" livery ----------------------
PAL = {
    'white':   (0.955, 0.962, 0.972), 'belly': (0.78, 0.81, 0.84), 'navy': (0.06, 0.12, 0.29),
    'gold':    (0.87, 0.64, 0.18),    'wing':  (0.72, 0.75, 0.79), 'glass': (0.05, 0.08, 0.12),
    'seam':    (0.60, 0.64, 0.69),    'tyre':  (0.06, 0.06, 0.07), 'metal': (0.52, 0.54, 0.57),
    'strut':   (0.86, 0.87, 0.89),    'lip':   (0.80, 0.82, 0.85), 'core':  (0.40, 0.42, 0.45),
    'dark':    (0.09, 0.09, 0.10),    'fan':   (0.36, 0.38, 0.41), 'spinner': (0.10, 0.10, 0.11),
    'pylon':   (0.88, 0.89, 0.91),
}
CID = {k: i for i, k in enumerate(PAL)}
CNAME = list(PAL)


def srgb2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# ----------------------------------------------------------------------------------------
# small math helpers
# ----------------------------------------------------------------------------------------
def pchip(pts):
    """monotone cubic interpolation through [(x, y), ...] (clamped outside)."""
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]; n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    m[0], m[-1] = d[0], d[-1]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0:
            m[i] = 0.0
        else:
            w1 = 2 * h[i] + h[i - 1]; w2 = h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(x):
        if x <= xs[0]:
            return ys[0]
        if x >= xs[-1]:
            return ys[-1]
        lo, hi = 0, n - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if xs[mid] <= x:
                lo = mid
            else:
                hi = mid
        i = lo; t = (x - xs[i]) / h[i]
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i]
                + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1])
    return f


def lerp(a, b, t):
    return a + (b - a) * t


def lin(a, b, n):
    return [a + (b - a) * i / n for i in range(n + 1)]


def A(s, b, z):
    return Vector((s, b, z))


def to_blender(v):
    """aircraft coords (s,b,z) [m] -> Blender coords [m]"""
    return Vector((-v[1], v[0] - S0, v[2]))


def dir_to_blender(d):
    return Vector((-d[1], d[0], d[2])).normalized()


def blender_to_roblox(v):
    """Blender coords -> Roblox model coords (proper rotation; FBX Forward=Z, Up=Y)."""
    return Vector((-v[0], v[2], v[1]))


def perp_basis(axis):
    axis = axis.normalized()
    helper = Vector((0, 0, 1)) if abs(axis[2]) < 0.9 else Vector((0, 1, 0))
    u = axis.cross(helper).normalized()
    v = axis.cross(u).normalized()
    return u, v


def bilerp(c, u, v):
    """c = [p00, p10, p11, p01] (2-tuples)"""
    return tuple((1 - u) * (1 - v) * c[0][k] + u * (1 - v) * c[1][k] + u * v * c[2][k] + (1 - u) * v * c[3][k]
                 for k in range(2))


# ----------------------------------------------------------------------------------------
# mesh building helpers (bmesh, aircraft coordinates, per-face colour id + part id)
# ----------------------------------------------------------------------------------------
class MB:
    """Mesh builder: bmesh + per-face colour-id layer + per-face 'part' layer (0 main, 1 fairing/canoe)."""

    def __init__(self, bm=None):
        self.bm = bm if bm is not None else bmesh.new()
        L = self.bm.faces.layers.int
        self.cl = L.get('cid') or L.new('cid')
        self.pl = L.get('part') or L.new('part')
        self.part = 0

    def v(self, p):
        return self.bm.verts.new(to_blender(p))

    def f(self, verts, cid):
        # drop consecutive duplicates (cyclic) so collapsed corners turn quads into triangles
        vs = []
        for x in verts:
            if not vs or vs[-1] is not x:
                vs.append(x)
        while len(vs) > 1 and vs[0] is vs[-1]:
            vs.pop()
        if len(vs) < 3 or len(set(vs)) != len(vs):
            return None
        try:
            face = self.bm.faces.new(vs)
        except ValueError:
            return None
        face[self.cl] = CID[cid] if isinstance(cid, str) else cid
        face[self.pl] = self.part
        return face

    def loft(self, rings, cidf, cap0=True, cap1=True, tip0=None, tip1=None, closed=True, tip_cid0=None):
        """rings: list of lists of A-space points (same count). cidf(i, j) -> colour."""
        vs = [[self.v(p) for p in r] for r in rings]
        n = len(rings[0])
        for i in range(len(rings) - 1):
            a, b = vs[i], vs[i + 1]
            for j in range(n if closed else n - 1):
                j2 = (j + 1) % n
                self.f((a[j], a[j2], b[j2], b[j]), cidf(i, j))
        for ring, tip, cap, idx in ((vs[0], tip0, cap0, 0), (vs[-1], tip1, cap1, len(rings) - 2)):
            if tip is not None:
                tv = self.v(tip)
                for j in range(n):
                    c = tip_cid0 if (tip_cid0 is not None and tip is tip0) else cidf(idx, j)
                    self.f((tv, ring[(j + 1) % n], ring[j]), c)
            elif cap:
                self.f(ring, cidf(idx, 0))
        return vs

    def lathe(self, profile, origin, axis, segs, cids, phase=0.0):
        """profile: [(x, r)], x along axis from origin. r==0 at an end -> pole.
        cids: colour per profile segment (len(profile)-1) or len(profile) for closed loops."""
        axis = axis.normalized(); u, v = perp_basis(axis)
        closed_loop = profile[0][1] > 1e-9 and profile[-1][1] > 1e-9
        vrings = []
        for (x, r) in profile:
            if r <= 1e-9:
                vrings.append(self.v(origin + axis * x))
                continue
            ring = []
            for k in range(segs):
                t = phase + 2 * math.pi * k / segs
                ring.append(self.v(origin + axis * x + (u * math.cos(t) + v * math.sin(t)) * r))
            vrings.append(ring)
        npf = len(profile)
        nseg = npf if closed_loop else npf - 1
        for i in range(nseg):
            a = vrings[i]; b = vrings[(i + 1) % npf]; c = cids[i]
            if isinstance(a, list) and isinstance(b, list):
                for k in range(segs):
                    k2 = (k + 1) % segs
                    self.f((a[k], a[k2], b[k2], b[k]), c)
            elif isinstance(a, list):
                for k in range(segs):
                    self.f((a[k], a[(k + 1) % segs], b), c)
            elif isinstance(b, list):
                for k in range(segs):
                    self.f((a, b[(k + 1) % segs], b[k]), c)

    def cylinder(self, p0, p1, r, segs, cid, r1=None):
        axis = (p1 - p0); L = axis.length
        self.lathe([(0.0, 0.0), (0.0, r), (L, r if r1 is None else r1), (L, 0.0)], p0, axis, segs,
                   [cid, cid, cid])


def mb_to_temp_object(mb, name):
    bmesh.ops.remove_doubles(mb.bm, verts=mb.bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(mb.bm, faces=mb.bm.faces)
    me = bpy.data.meshes.new(name)
    mb.bm.to_mesh(me); mb.bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def boolean_union(mb_a, mb_b):
    """Exact boolean union of two closed shells; face attributes (cid, part) are propagated by Blender."""
    oa = mb_to_temp_object(mb_a, '_bool_a'); ob_ = mb_to_temp_object(mb_b, '_bool_b')
    mod = oa.modifiers.new('union', 'BOOLEAN')
    mod.operation = 'UNION'; mod.solver = 'EXACT'; mod.object = ob_
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(oa.evaluated_get(dg))
    bm = bmesh.new(); bm.from_mesh(me)
    for o in (oa, ob_):
        m = o.data; bpy.data.objects.remove(o); bpy.data.meshes.remove(m)
    bpy.data.meshes.remove(me)
    return MB(bm)


# ----------------------------------------------------------------------------------------
# FUSELAGE definition (traced from the AC 3-view, see README)
# ----------------------------------------------------------------------------------------
TOP = [(0.0, 4.98), (0.1, 5.22), (0.2, 5.41), (0.3, 5.55), (0.5, 5.86), (0.75, 6.12), (1.0, 6.35),
       (1.5, 6.69), (2.0, 7.06), (2.5, 7.54), (3.0, 7.96), (3.5, 8.39), (4.0, 8.72), (4.5, 9.00),
       (5.0, 9.24), (5.5, 9.43), (6.0, 9.62), (7.0, 9.90), (8.0, 10.13), (9.0, 10.32), (10.0, 10.47),
       (11.0, 10.56), (12.0, 10.65), (13.0, 10.71), (14.0, 10.75), (51.0, 10.75), (53.0, 10.68),
       (55.0, 10.57), (57.0, 10.45), (60.0, 10.22), (63.0, 10.00), (66.0, 9.80), (68.0, 9.56),
       (70.0, 9.30), (71.0, 9.12), (72.3, 8.92)]
BOT = [(0.0, 4.66), (0.1, 4.37), (0.2, 4.23), (0.3, 4.14), (0.5, 3.95), (0.75, 3.79), (1.0, 3.66),
       (1.5, 3.43), (2.0, 3.24), (2.5, 3.14), (3.0, 3.05), (3.5, 2.96), (4.0, 2.86), (4.5, 2.77),
       (5.0, 2.72), (6.0, 2.62), (7.0, 2.57), (8.0, 2.49), (9.0, 2.44), (10.0, 2.40), (11.0, 2.37),
       (12.0, 2.35), (13.0, 2.34), (45.0, 2.34), (46.0, 2.38), (47.0, 2.44), (48.0, 2.57), (49.0, 2.72),
       (50.0, 2.91), (51.0, 3.10), (52.0, 3.29), (53.0, 3.48), (54.0, 3.66), (55.0, 3.85), (56.0, 4.04),
       (57.0, 4.23), (58.0, 4.45), (59.0, 4.66), (60.0, 4.89), (61.0, 5.12), (62.0, 5.33), (63.0, 5.55),
       (64.0, 5.79), (65.0, 6.06), (66.0, 6.35), (67.0, 6.64), (68.0, 6.97), (69.0, 7.26), (70.0, 7.55),
       (71.0, 8.02), (71.6, 8.36), (72.3, 8.60)]
HW = [(0.0, 0.23), (0.1, 0.49), (0.2, 0.64), (0.3, 0.75), (0.5, 1.01), (0.75, 1.20), (1.0, 1.37),
      (1.5, 1.65), (2.0, 1.86), (3.0, 2.20), (4.0, 2.48), (5.0, 2.72), (6.0, 2.90), (7.0, 3.05), (8.0, 3.19),
      (9.0, 3.31), (10.0, 3.40), (11.0, 3.47), (12.0, 3.52), (13.0, 3.56), (14.0, 3.57), (50.0, 3.57),
      (51.0, 3.52), (52.0, 3.47), (53.0, 3.38), (54.0, 3.28), (55.0, 3.14), (56.0, 3.00), (57.0, 2.78),
      (58.0, 2.57), (60.0, 2.22), (62.0, 1.90), (64.0, 1.60), (66.0, 1.25), (68.0, 0.82), (69.0, 0.56),
      (70.0, 0.38), (71.0, 0.28), (72.3, 0.15)]
ZWF = [(0.0, 0.45), (3.0, 0.43), (8.0, 0.45), (12.0, 0.468), (50.0, 0.468), (58.0, 0.49), (66.0, 0.5),
       (72.3, 0.5)]                       # height of max width as fraction bottom->top
NUP = [(0.0, 2.0), (4.0, 2.05), (10.0, 2.3), (52.0, 2.3), (60.0, 2.1), (72.3, 2.0)]   # superellipse exp.
fTOP, fBOT, fHW, fZWF, fNUP = pchip(TOP), pchip(BOT), pchip(HW), pchip(ZWF), pchip(NUP)
NLO = 2.0
S_TAIL_END = 72.3
NOSE_TIP = A(0.0, 0.0, 4.81)
TAIL_TIP = A(72.55, 0.0, 8.77)


def fus(s):
    t, b, hw = fTOP(s), fBOT(s), fHW(s)
    zw = b + fZWF(s) * (t - b)
    return t, b, hw, zw, fNUP(s), NLO


def fus_pt(s, phi, side):
    """surface point at station s, angle phi (deg, -90 bottom .. +90 top), side +1 stbd/-1 port"""
    t, b, hw, zw, nu, nl = fus(s)
    ph = math.radians(phi)
    c = max(0.0, math.cos(ph)); sn = abs(math.sin(ph))
    if phi >= 0:
        H, n, sg = t - zw, nu, 1.0
    else:
        H, n, sg = zw - b, nl, -1.0
    return A(s, side * hw * c ** (2.0 / n), zw + sg * H * sn ** (2.0 / n))


def z_to_phi(s, z):
    t, b, hw, zw, nu, nl = fus(s)
    if z >= zw:
        r = min(1.0, (z - zw) / (t - zw)); return math.degrees(math.asin(r ** (nu / 2.0)))
    r = min(1.0, (zw - z) / (zw - b)); return -math.degrees(math.asin(r ** (nl / 2.0)))


def surf_frame(s, phi, side):
    p = fus_pt(s, phi, side)
    ps = fus_pt(s + 0.05, phi, side) - fus_pt(s - 0.05, phi, side)
    p1 = max(-89.8, min(89.8, phi + 0.4)); p2 = max(-89.8, min(89.8, phi - 0.4))
    pp = fus_pt(s, p1, side) - fus_pt(s, p2, side)
    n = ps.cross(pp).normalized()
    zw = fus(s)[3]
    if n.dot(A(0.0, p[1], p[2] - zw)) < 0:
        n = -n
    return p, n


def front_surface(b, z):
    """(s, phi, side) of the skin point that has lateral |b| and height z, searched from the nose
    (used to project the windscreen panes along the fuselage axis, i.e. a head-on projection)."""
    side = 1 if b >= 0 else -1; bb = abs(b)

    def F(s):
        t, bo, hw, zw, nu, nl = fus(s)
        if z >= zw:
            return (bb / hw) ** nu + (min(2.0, (z - zw) / (t - zw))) ** nu
        return (bb / hw) ** nl + (min(2.0, (zw - z) / (zw - bo))) ** nl
    lo, hi = 0.0005, 14.0
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        if F(mid) > 1.0:
            lo = mid
        else:
            hi = mid
    s = 0.5 * (lo + hi)
    return s, z_to_phi(s, z), side


# --- livery bands on the fuselage: every colour boundary lies on its own edge loop ---------
# belly (light grey) boundary: constant 3.30 m along the tube, rising smoothly to the radome tip and
# up the tail cone (dedicated ring index KB, so the boundary is one clean edge loop).
ZB_BELLY = pchip([(0.0, 4.60), (1.0, 4.36), (2.5, 4.06), (4.5, 3.76), (7.0, 3.50), (10.0, 3.35), (13.0, 3.30),
                  (46.0, 3.30), (49.0, 3.40), (52.0, 3.75), (55.0, 4.45), (58.0, 5.20), (61.0, 5.95),
                  (64.0, 6.70), (67.0, 7.45), (70.0, 8.15), (72.3, 8.70)])
N_LO, N_TR, N_UP = 6, 3, 16
CHEAT_ANCH = [-17.5, -15.5, -14.0, -10.0, -6.0]     # gold line -17.5..-15.5, navy band -14..-6
KB = N_LO + 1                                         # ring index of the belly boundary
IA0 = KB + N_TR + 1                                   # ring index of the first cheatline anchor
NPH = (N_LO + 1) + (N_TR + 1) + len(CHEAT_ANCH) + (N_UP + 1)   # 33 angles per side (64 per ring)


def ring_phis(s):
    pb = max(-80.0, min(z_to_phi(s, ZB_BELLY(s)), -19.0))
    anch = CHEAT_ANCH[:] if pb < -24.0 else [pb + (a + 24.0) * (-6.0 - pb) / 18.0 for a in CHEAT_ANCH]
    lo = [-90.0 + (pb + 90.0) * k / (N_LO + 1) for k in range(N_LO + 1)]
    tr = [pb + (anch[0] - pb) * k / (N_TR + 1) for k in range(N_TR + 1)]
    up = [-6.0 + 96.0 * k / (N_UP + 1) for k in range(1, N_UP + 2)]
    return lo + tr + anch + up


RING_SIDE = [1] * NPH + [-1] * (NPH - 2)
FUS_ST = ([0.03, 0.08, 0.15, 0.24, 0.35, 0.48, 0.63, 0.80, 1.0, 1.22, 1.46, 1.72, 2.0, 2.3, 2.62, 2.96, 3.32, 3.7,
           4.1, 4.52, 4.96, 5.42, 5.9, 6.45, 7.05, 7.7, 8.4, 9.15, 9.95, 10.8, 11.7, 12.65, 13.6, 14.6] +
          [16.5 + 2.0 * i for i in range(15)] + [46.0, 47.0, 48.0, 49.0, 50.0] + [51.0 + i for i in range(20)] +
          [70.6, 71.2, 71.8, S_TAIL_END])
CHEAT_S0, CHEAT_S1 = 3.3, 62.0


def fus_colour(s_mid, sg):
    if s_mid > 71.0 or sg < KB:
        return 'belly'
    if CHEAT_S0 < s_mid < CHEAT_S1:
        if sg == IA0:
            return 'gold'
        if sg in (IA0 + 2, IA0 + 3):
            return 'navy'
    return 'white'


# belly / wing-root fairing (boolean-unioned into the Fuselage object)
FAIR_W = pchip([(17.0, 1.6), (17.6, 2.7), (18.3, 3.35), (19.0, 3.7), (20.0, 3.92), (21.5, 4.03), (23.0, 4.1),
                (26.0, 4.17), (29.0, 4.2), (36.0, 4.2), (39.0, 4.12), (41.0, 4.0), (43.0, 3.8), (45.0, 3.5),
                (46.5, 3.1), (47.8, 2.5), (49.2, 1.5)])
FAIR_ZB = pchip([(17.0, 3.2), (18.0, 2.8), (19.0, 2.55), (20.0, 2.40), (21.0, 2.25), (22.0, 2.15), (24.0, 1.98),
                 (26.0, 1.84), (28.0, 1.76), (34.0, 1.74), (36.0, 1.78), (38.0, 1.86), (40.0, 1.96),
                 (42.0, 2.10), (44.0, 2.25), (45.5, 2.40), (47.0, 2.62), (48.5, 2.90), (49.2, 3.10)])
FAIR_ZC, FAIR_ZT = 3.5, 5.9
FAIR_ST = [17.0, 17.6, 18.3, 19.0, 20.0, 21.5, 23.0, 25.0, 27.0, 29.0, 31.0, 33.0, 35.0, 37.0, 39.0, 40.5,
           42.0, 43.5, 45.0, 46.3, 47.5, 48.5, 49.2]
FAIR_PHI = [-90, -75, -60, -45, -30, -15, 0, 15, 30, 45, 60, 75, 90]


def fair_pt(s, phi, side):
    wf, zb = FAIR_W(s), FAIR_ZB(s)
    zb = min(zb, FAIR_ZC - 0.05)
    ph = math.radians(phi); c = max(0.0, math.cos(ph)); sn = abs(math.sin(ph))
    if phi >= 0:
        H, n, sg = FAIR_ZT - FAIR_ZC, 2.2, 1.0
    else:
        H, n, sg = FAIR_ZC - zb, 3.5, -1.0
    return A(s, side * wf * c ** (2.0 / n), FAIR_ZC + sg * H * sn ** (2.0 / n))


def build_fuselage():
    tube = MB()
    rings = []
    for s in FUS_ST:
        ph = ring_phis(s)
        rp = ph + list(reversed(ph[1:-1]))
        rings.append([fus_pt(s, p, sd) for p, sd in zip(rp, RING_SIDE)])
    nr = len(RING_SIDE)

    def kidx(p):
        return p if p < NPH else 2 * NPH - 2 - p

    def cidf(i, j):
        s_mid = 0.5 * (FUS_ST[i] + FUS_ST[min(i + 1, len(FUS_ST) - 1)])
        return fus_colour(s_mid, min(kidx(j), kidx((j + 1) % nr)))
    tube.loft(rings, cidf, tip0=NOSE_TIP, tip1=TAIL_TIP, tip_cid0='white')   # radome tip cap white (no grey wedge)
    fair = MB(); fair.part = 1
    fr_phi = FAIR_PHI + [p for p in reversed(FAIR_PHI[1:-1])]
    fr_side = [1] * len(FAIR_PHI) + [-1] * (len(FAIR_PHI) - 2)
    frings = [[fair_pt(s, ph, sd) for ph, sd in zip(fr_phi, fr_side)] for s in FAIR_ST]
    fair.loft(frings, lambda i, j: 'belly')
    return boolean_union(tube, fair)


# ----------------------------------------------------------------------------------------
# AIRFOILS / LIFTING SURFACES
# ----------------------------------------------------------------------------------------
def naca_t(x, tc):
    x = max(0.0, min(1.0, x))
    return 5 * tc * (0.2969 * math.sqrt(x) - 0.1260 * x - 0.3516 * x ** 2 + 0.2843 * x ** 3 - 0.1015 * x ** 4)


def camber(x, m, p):
    if m == 0:
        return 0.0
    return m / p ** 2 * (2 * p * x - x * x) if x < p else m / (1 - p) ** 2 * ((1 - 2 * p) + 2 * p * x - x * x)


def map_h(side, b, zc, xle, c, inc):
    """horizontal surface: normalised (xn, yn) -> A coords, incidence about quarter chord"""
    xq = xle + 0.25 * c; ci, si = math.cos(math.radians(inc)), math.sin(math.radians(inc))

    def f(xn, yn):
        X = xle + xn * c; Y = zc + yn * c
        return A(xq + (X - xq) * ci + (Y - zc) * si, side * b, zc + (Y - zc) * ci - (X - xq) * si)
    return f


def map_v(z, xle, c):
    def f(xn, yn):
        return A(xle + xn * c, yn * c, z)
    return f


def main_ring(f, fc, tc, m, p, N):
    xs = [fc * (1 - math.cos(0.5 * math.pi * i / (N - 1))) for i in range(N)]
    up = [(x, camber(x, m, p) + naca_t(x, tc)) for x in xs]
    lo = [(x, camber(x, m, p) - naca_t(x, tc)) for x in xs]
    return [f(x, y) for (x, y) in reversed(up)] + [f(x, y) for (x, y) in lo[1:]]


def cs_ring(f, fh, tc, m, p, N2=6, NA=3):
    """control-surface section: rounded nose (circle about the hinge point) + aft airfoil part"""
    xs = [fh + (1 - fh) * i / (N2 - 1) for i in range(N2)]
    up = [(x, camber(x, m, p) + naca_t(x, tc)) for x in xs]
    lo = [(x, camber(x, m, p) - naca_t(x, tc)) for x in xs]
    yc, r = camber(fh, m, p), naca_t(fh, tc)
    pts = [f(x, y) for x, y in up] + [f(x, y) for x, y in reversed(lo)]
    for k in range(1, NA + 1):
        a = math.radians(270 - 180 * k / (NA + 1))
        pts.append(f(fh + r * math.cos(a), yc + r * math.sin(a)))
    return pts, f(fh, yc), (f(fh, yc + r) - f(fh, yc)).length      # nose radius in metres


# ---- wing planform (traced; LE kink at b=15.07, TE kink at b=12.8) ----
def wing_le(b):
    if b <= 15.07:
        x = 20.37 + 0.832 * (b - 5.0)
    else:
        x = 30.16 + 0.7338 * (b - 17.0)
    if b > 38.5:                                          # rounded tip leading edge
        x += pchip([(38.5, 0.0), (39.0, 0.10), (39.4, 0.33), (39.8, 0.62)])(b)
    return x


def wing_te(b):
    return 37.29 + 0.284 * (b - 4.5) if b <= 12.8 else 39.75 + 0.42 * (b - 13.0)


wing_zc = pchip([(0.0, 3.55), (3.0, 3.70), (4.0, 3.79), (8.0, 4.51), (12.0, 5.19), (17.0, 5.90), (20.0, 6.25),
                 (23.0, 6.51), (28.0, 6.89), (33.0, 7.26), (39.8, 7.70)])
wing_tc = pchip([(0.0, 0.13), (4.0, 0.13), (12.8, 0.11), (25.0, 0.095), (39.8, 0.085)])
WING_M, WING_P = 0.018, 0.55
WING_TIP_B = 39.80
FENCE_B = 39.80


def wing_inc(b):
    return 2.0 - 3.5 * b / WING_TIP_B


# (name template, b0, b1, hinge chord fraction at b0, at b1).  The inboard flap hinge sits at 78 % chord at
# its root so that the wing-gear trunnion (St 32.75, b 6.23) is in the fixed wing box, ahead of the flap.
WING_SURF = [('Flap_{S}_Inner', 4.3, 13.3, 0.78, 0.70), ('Flap_{S}_Outer', 13.5, 26.9, 0.70, 0.70),
             ('Aileron_{S}', 27.1, 38.3, 0.75, 0.75)]
WING_U = [0.0, 3.0, 4.3, 6.0, 8.0, 10.0, 12.8, 13.3, 13.5, 15.07, 17.0, 19.0, 21.0, 23.0, 25.0, 26.9, 27.1,
          29.0, 31.0, 33.0, 35.0, 37.0, 38.3, 38.33, 38.9, 39.4, WING_TIP_B]


def wing_hinge_x(b):
    hp = []
    for (_, b0, b1, f0, f1) in WING_SURF:
        hp.append((b0, wing_le(b0) + f0 * (wing_te(b0) - wing_le(b0))))
        hp.append((b1, wing_le(b1) + f1 * (wing_te(b1) - wing_le(b1))))
    if b <= hp[0][0]:
        return wing_le(b) + WING_SURF[0][3] * (wing_te(b) - wing_le(b))
    for (b0, x0), (b1, x1) in zip(hp[:-1], hp[1:]):
        if b0 <= b <= b1:
            return lerp(x0, x1, (b - b0) / (b1 - b0)) if b1 > b0 else x0
    return None


def wing_fc(b):
    if b > 38.31:
        return 1.0
    return (wing_hinge_x(b) - wing_le(b)) / (wing_te(b) - wing_le(b))


def wing_map(side, b):
    return map_h(side, b, wing_zc(b), wing_le(b), wing_te(b) - wing_le(b), wing_inc(b))


# flap-track fairings ("canoes"): lateral position, extension behind the TE, depth.  Each canoe is cut at
# the flap hinge line: the forward part belongs to Wing_*, the aft part to the flap it supports (moves with it).
CANOES = [(9.36, 1.0, 0.85), (12.95, 1.3, 0.85), (17.65, 2.2, 0.80), (21.87, 2.0, 0.75), (25.97, 1.7, 0.70)]


def wing_lower_z(b, x):
    le, te = wing_le(b), wing_te(b); c = te - le
    xn = max(0.0, min(1.0, (x - le) / c))
    return wing_map(1, b)(xn, camber(xn, WING_M, WING_P) - naca_t(xn, wing_tc(b)))[2]


def canoe_rings(side, bc, ext, depth):
    le, te = wing_le(bc), wing_te(bc); c = te - le
    x0, x1 = le + 0.45 * c, te + ext
    xh = wing_hinge_x(bc)
    ts = [0.0, 0.1, 0.3, 0.55, 0.75, 0.9, 1.0]
    fd = pchip(list(zip(ts, [0.05, 0.40, 0.75, 0.90, 0.78, 0.45, 0.06])))
    fw = pchip(list(zip(ts, [0.10, 0.35, 0.50, 0.55, 0.50, 0.33, 0.07])))
    th = (xh - x0) / (x1 - x0)
    tl = sorted(set([round(t, 4) for t in ts + [0.2, 0.42, 0.65, 0.83, 0.95]] + [round(th, 4)]))

    def ring(t):
        x = lerp(x0, x1, t); d = fd(t); w = fw(t)
        zl = wing_lower_z(bc, min(x, te - 0.05))
        ztop = wing_map(1, bc)((min(x, te) - le) / c, 0.0)[2] if x < te else zl + 0.05
        zbot = zl - depth * d
        zc = 0.5 * (ztop + zbot); hz = 0.5 * (ztop - zbot)
        out = []
        for k in range(12):
            a = 2 * math.pi * k / 12
            ca, sa = math.cos(a), math.sin(a)
            out.append(A(x, side * (bc + 0.30 * w / 0.55 * math.copysign(abs(ca) ** 0.8, ca)),
                         zc + hz * math.copysign(abs(sa) ** 0.8, sa)))
        return out
    th = round(th, 4)
    front = [ring(t) for t in tl if t <= th]
    aft = [ring(t) for t in tl if t >= th]
    return front, aft


def build_wing(side):
    mb = MB()
    NC = 14
    rings = [main_ring(wing_map(side, b), wing_fc(b), wing_tc(b), WING_M, WING_P, NC) for b in WING_U]
    mb.loft(rings, lambda i, j: 'wing')
    mb.part = 1
    for (bc, ext, depth) in CANOES:
        front, _ = canoe_rings(side, bc, ext, depth)
        mb.loft(front, lambda i, j: 'wing')
    return mb


def build_wing_surface(side, b0, b1):
    mb = MB()
    us = [b0] + [u for u in WING_U if b0 < u < b1] + [b1]
    rings, hinge, rr = [], [], []
    for b in us:
        r, h, rad = cs_ring(wing_map(side, b), wing_fc(b), wing_tc(b), WING_M, WING_P)
        rings.append(r); hinge.append(h); rr.append(rad)
    mb.loft(rings, lambda i, j: 'wing')
    mb.part = 1
    for (bc, ext, depth) in CANOES:
        if b0 < bc < b1:
            _, aft = canoe_rings(side, bc, ext, depth)
            mb.loft(aft, lambda i, j: 'wing')
    return mb, hinge[0], hinge[-1], max(rr)


def build_fence(side):
    mb = MB()
    le_tip = 46.97; zc = wing_zc(FENCE_B)
    poly = [(-0.55, 0.0), (0.6, 0.55), (3.7, 1.35), (4.4, 1.35), (5.1, 0.25), (5.1, -0.15), (4.0, -0.95),
            (3.3, -0.95), (0.6, -0.35)]
    rings = []
    for db in (-0.075, 0.075):
        rings.append([A(le_tip + x, side * (FENCE_B + db), zc + z) for (x, z) in poly])
    mb.loft(rings, lambda i, j: 'navy')
    bm = mb.bm
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.03, offset_type='OFFSET', segments=2, profile=0.5,
                    affect='EDGES', clamp_overlap=True)
    return mb


# ---- horizontal stabiliser ----
def hs_le(b):
    return 57.21 + 0.760 * b


def hs_te(b):
    return 67.12 + 0.360 * b


def hs_zc(b):
    return 7.45 + 0.088 * b


def hs_tc(b):
    return 0.11 - 0.02 * b / 15.15


HS_TIP = 15.15
ELEV = (1.2, 14.9, 0.70)
HS_U = [0.0, 1.2, 3.0, 5.0, 7.0, 9.0, 11.0, 13.0, 14.9, 14.93, HS_TIP]


def hs_hinge_x(b):
    b0, b1, f = ELEV
    x0 = hs_le(b0) + f * (hs_te(b0) - hs_le(b0)); x1 = hs_le(b1) + f * (hs_te(b1) - hs_le(b1))
    return lerp(x0, x1, (b - b0) / (b1 - b0))


def hs_fc(b):
    if b > ELEV[1] + 0.01:
        return 1.0
    return (hs_hinge_x(b) - hs_le(b)) / (hs_te(b) - hs_le(b))


def hs_map(side, b):
    return map_h(side, b, hs_zc(b), hs_le(b), hs_te(b) - hs_le(b), 0.0)


def build_hstab(side):
    mb = MB()
    rings = [main_ring(hs_map(side, b), hs_fc(b), hs_tc(b), 0, 0.5, 12) for b in HS_U]
    mb.loft(rings, lambda i, j: 'wing')
    return mb


def build_elevator(side):
    mb = MB()
    b0, b1, _ = ELEV
    us = [b0] + [u for u in HS_U if b0 < u < b1] + [b1]
    rings, hinge, rr = [], [], []
    for b in us:
        r, h, rad = cs_ring(hs_map(side, b), hs_fc(b), hs_tc(b), 0, 0.5)
        rings.append(r); hinge.append(h); rr.append(rad)
    mb.loft(rings, lambda i, j: 'wing')
    return mb, hinge[0], hinge[-1], max(rr)


# ---- vertical stabiliser ----
def vs_le(z):
    return 53.94 + 1.058 * (z - 10.8)


def vs_te(z):
    return 66.06 + 0.46 * (z - 9.6)


def vs_tc(z):
    return 0.12 - 0.03 * (z - 9.0) / (24.09 - 9.0)


VS_Z = [9.0, 10.3, 12.0, 14.0, 16.0, 18.0, 20.0, 22.0, 23.7, 23.73, 24.09]
RUD = ((62.7, 10.3), (70.3, 23.7))


def vs_hinge_x(z):
    (x0, z0), (x1, z1) = RUD
    return lerp(x0, x1, (z - z0) / (z1 - z0))


def vs_fc(z):
    if z > RUD[1][1] + 0.01:
        return 1.0
    return (vs_hinge_x(z) - vs_le(z)) / (vs_te(z) - vs_le(z))


def vs_map(z):
    return map_v(z, vs_le(z), vs_te(z) - vs_le(z))


def build_vstab():
    mb = MB()
    rings = [main_ring(vs_map(z), vs_fc(z), vs_tc(z), 0, 0.5, 12) for z in VS_Z]
    mb.loft(rings, lambda i, j: 'navy')
    return mb


def build_rudder():
    mb = MB()
    z0, z1 = RUD[0][1], RUD[1][1]
    us = [z0] + [u for u in VS_Z if z0 < u < z1] + [z1]
    rings, hinge, rr = [], [], []
    for z in us:
        r, h, rad = cs_ring(vs_map(z), vs_fc(z), vs_tc(z), 0, 0.5)
        rings.append(r); hinge.append(h); rr.append(rad)
    mb.loft(rings, lambda i, j: 'navy')
    return mb, hinge[0], hinge[-1], max(rr)


# ----------------------------------------------------------------------------------------
# flat 2D artwork (text, emblem) -> conformal mesh on a curved skin
# ----------------------------------------------------------------------------------------
def subdivide_long_edges_2d(bm, maxlen):
    """split every OUTLINE edge (front/back rim of the extruded artwork) longer than maxlen in the artwork
    plane (x, y), so the visible outline follows a curved skin; caps are re-triangulated."""
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='EAR_CLIP')

    def is_rim(e):
        if abs(e.verts[0].co.z - e.verts[1].co.z) > 1e-6:
            return False
        return any(max(v.co.z for v in f.verts) - min(v.co.z for v in f.verts) > 1e-6 for f in e.link_faces)
    for _ in range(12):
        long = [e for e in bm.edges if is_rim(e) and (e.verts[0].co.xy - e.verts[1].co.xy).length > maxlen]
        if not long:
            break
        bmesh.ops.subdivide_edges(bm, edges=long, cuts=1, use_grid_fill=False)
        bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='EAR_CLIP')


def text_bmesh(body, size, depth, res=3):
    """Blender text (bundled font) -> bmesh, x/y = artwork plane (m), z in [-depth/2, depth/2]."""
    cu = bpy.data.curves.new('txt_tmp', 'FONT')
    cu.body = body; cu.size = size; cu.extrude = depth / 2; cu.resolution_u = res
    ob = bpy.data.objects.new('txt_tmp', cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = ob.evaluated_get(dg).to_mesh()
    bm = bmesh.new(); bm.from_mesh(me)
    ob.evaluated_get(dg).to_mesh_clear()
    bpy.data.objects.remove(ob); bpy.data.curves.remove(cu)
    return bm


def polygon_bmesh(poly, depth):
    """closed 2D polygon -> extruded bmesh slab, z in [-depth/2, depth/2]"""
    bm = bmesh.new()
    lo = [bm.verts.new((x, y, -depth / 2)) for x, y in poly]
    hi = [bm.verts.new((x, y, depth / 2)) for x, y in poly]
    bm.faces.new(list(reversed(lo))); bm.faces.new(hi)
    n = len(poly)
    for j in range(n):
        j2 = (j + 1) % n
        bm.faces.new((lo[j], lo[j2], hi[j2], hi[j]))
    return bm


def map_artwork(mb, bm2d, mapping, cid, flip=False):
    """mapping(x, y, w) -> A point; w in [0, 1] from back to front of the artwork slab."""
    zs = [v.co.z for v in bm2d.verts]; z0, z1 = min(zs), max(zs)
    vmap = {}
    for v in bm2d.verts:
        vmap[v] = mb.v(mapping(v.co.x, v.co.y, (v.co.z - z0) / max(1e-9, z1 - z0)))
    for f in bm2d.faces:
        vs = [vmap[v] for v in f.verts]
        mb.f(list(reversed(vs)) if flip else vs, cid)
    bm2d.free()


def fin_y(s, z):
    c = vs_te(z) - vs_le(z); xn = (s - vs_le(z)) / c
    return naca_t(xn, vs_tc(z)) * c


CROWN = [(-1.70, 0.0), (1.70, 0.0), (1.95, 2.0), (1.35, 1.25), (0.90, 2.10), (0.45, 1.30), (0.0, 2.40),
         (-0.45, 1.30), (-0.90, 2.10), (-1.35, 1.25), (-1.95, 2.0)]
CROWN_Z0 = 15.4


def build_tail_logo():
    """fictional AI Empire emblem: five-point gold crown with a navy 'AI' monogram on its band,
    on both sides of the fin (sheared with the fin sweep)."""
    mb = MB()
    for side in (1, -1):
        dirn = -1.0 if side > 0 else 1.0           # reads correctly from either side

        def crown_map(x, y, w, side=side, dirn=dirn):
            z = CROWN_Z0 + y
            s = 0.5 * (vs_le(z) + vs_te(z)) - 0.6 + x * dirn
            return A(s, side * (fin_y(s, z) + lerp(-0.02, 0.035, w)), z)
        bm = polygon_bmesh(CROWN, 1.0)
        subdivide_long_edges_2d(bm, 0.3)
        map_artwork(mb, bm, crown_map, 'gold')
        tb = text_bmesh('AI', 0.78, 1.0, res=2)
        xs = [v.co.x for v in tb.verts]; ys = [v.co.y for v in tb.verts]
        cx, cy = 0.5 * (min(xs) + max(xs)), 0.5 * (min(ys) + max(ys))
        for v in tb.verts:
            v.co.x -= cx; v.co.y -= cy - 0.45
        subdivide_long_edges_2d(tb, 0.3)

        def ai_map(x, y, w, side=side, dirn=dirn):
            z = CROWN_Z0 + y
            s = 0.5 * (vs_le(z) + vs_te(z)) - 0.6 + x * dirn
            return A(s, side * (fin_y(s, z) + lerp(0.028, 0.050, w)), z)
        map_artwork(mb, tb, ai_map, 'navy')
    return mb


# ----------------------------------------------------------------------------------------
# ENGINES
# ----------------------------------------------------------------------------------------
ENGINES = [  # name, nose station, lateral b, axis height z
    ('1', REF['eng_outer'][0], -REF['eng_outer'][1], 4.25),
    ('2', REF['eng_inner'][0], -REF['eng_inner'][1], 3.08),
    ('3', REF['eng_inner'][0], REF['eng_inner'][1], 3.08),
    ('4', REF['eng_outer'][0], REF['eng_outer'][1], 4.25),
]
FAN_X = 0.95          # fan plane, m aft of the nacelle highlight
# nacelle (closed lathe loop): highlight at x=0, full 3.80 m barrel to x=4.6 m, fan-nozzle exit at x=6.2 m
# (Airbus 3-view: fan cowl about 6.1 m long, plug tip about 7.7 m behind the highlight)
NACELLE = [(0.00, 1.62, 'lip'), (0.07, 1.73, 'lip'), (0.22, 1.82, 'lip'), (0.45, 1.87, 'navy'),
           (0.55, 1.88, 'gold'), (0.72, 1.89, 'navy'), (2.00, 1.90, 'navy'), (3.60, 1.89, 'navy'),
           (4.60, 1.85, 'navy'), (5.20, 1.77, 'navy'), (5.75, 1.65, 'navy'),
           (6.20, 1.53, 'dark'), (6.20, 1.47, 'dark'), (3.40, 1.53, 'dark'), (1.00, 1.50, 'dark'),
           (0.45, 1.50, 'lip'), (0.12, 1.53, 'lip'), (0.03, 1.57, 'lip')]
NAC_EXIT = 6.20
CORE = [(1.20, 0.0, 'dark'), (1.20, 1.49, 'dark'), (1.32, 1.49, 'core'), (1.32, 0.97, 'core'),
        (2.60, 1.12, 'core'), (4.80, 1.16, 'core'), (6.00, 1.10, 'core'), (6.60, 0.98, 'core'),
        (7.00, 0.86, 'dark'), (7.00, 0.74, 'core'), (6.85, 0.66, 'core'), (7.25, 0.50, 'core'),
        (7.55, 0.22, 'core'), (7.70, 0.0, '')]
NAC_SEGS, CORE_SEGS = 48, 32


def nac_r(x):
    outer = [(p[0], p[1]) for p in NACELLE[:12]]
    if x <= outer[0][0]:
        return outer[0][1]
    for (x0, r0), (x1, r1) in zip(outer[:-1], outer[1:]):
        if x0 <= x <= x1:
            return lerp(r0, r1, (x - x0) / (x1 - x0)) if x1 > x0 else r1
    return outer[-1][1]


def build_engine(s0, b0, z0):
    mb = MB()
    o = A(s0, b0, z0); ax = A(1, 0, 0)
    mb.lathe([(x, r) for x, r, _ in NACELLE], o, ax, NAC_SEGS, [c for _, _, c in NACELLE])
    mb.lathe([(x, r) for x, r, _ in CORE], o, ax, CORE_SEGS, [c for _, _, c in CORE[:-1]])
    # pylon: sits on the nacelle top, rises into the wing leading edge, aft fairing above the exhaust
    bb = abs(b0)
    le_off = wing_le(bb) - s0
    xs = [1.50, 1.85, 2.60, 3.60, 4.60, 5.50, le_off - 0.2, le_off + 0.9, le_off + 2.1, le_off + 3.2, le_off + 3.9]
    half = [0.10, 0.26, 0.34, 0.36, 0.36, 0.35, 0.34, 0.30, 0.25, 0.18, 0.08]
    wz_top = wing_zc(bb) + 0.30
    x_end = xs[-1]
    rings = []
    for x, hw in zip(xs, half):
        s = s0 + x
        if x <= le_off:
            ztop = lerp(z0 + nac_r(1.5) + 0.32, wz_top, (x - 1.5) / (le_off - 1.5))
        else:
            ztop = wing_zc(bb) + 0.25
        if x <= NAC_EXIT:
            zbot = z0 + nac_r(x) - 0.10
        else:
            zl = wing_lower_z(bb, min(s, wing_te(bb) - 0.3))
            zbot = lerp(z0 + nac_r(NAC_EXIT) - 0.10, zl - 0.05, (x - NAC_EXIT) / (x_end - NAC_EXIT))
        zbot = min(zbot, ztop - 0.2)
        zc = 0.5 * (ztop + zbot); hz = 0.5 * (ztop - zbot)
        ring = []
        for k in range(12):
            a = 2 * math.pi * k / 12
            ca, sa = math.cos(a), math.sin(a)
            ring.append(A(s, b0 + hw * math.copysign(abs(ca) ** 0.5, ca), zc + hz * math.copysign(abs(sa) ** 0.5, sa)))
        rings.append(ring)
    mb.loft(rings, lambda i, j: 'pylon')
    return mb


def build_fan(s0, b0, z0, ccw):
    mb = MB()
    o = A(s0, b0, z0); ax = A(1, 0, 0)
    spinner = [(0.30, 0.0), (0.42, 0.22), (0.58, 0.40), (0.80, 0.54), (1.05, 0.60), (1.12, 0.60), (1.12, 0.0)]
    mb.lathe(spinner, o, ax, CORE_SEGS, ['spinner'] * 6)
    nb = 20
    for k in range(nb):
        t0 = 2 * math.pi * k / nb
        rings = []
        for (r, pitch, chord) in ((0.55, 52.0, 0.36), (1.0, 40.0, 0.40), (1.47, 28.0, 0.42)):
            t = t0
            rad = A(0, math.cos(t), math.sin(t)); tan = A(0, -math.sin(t), math.cos(t))
            pr = math.radians(pitch) * (1 if ccw else -1)
            cdir = A(1, 0, 0) * math.sin(pr) + tan * math.cos(pr)     # chord direction
            tdir = A(1, 0, 0) * math.cos(pr) - tan * math.sin(pr)     # thickness direction
            c = o + A(FAN_X, 0, 0) + rad * r
            th = 0.025
            rings.append([c - cdir * chord * 0.5 - tdir * th, c + cdir * chord * 0.5 - tdir * th,
                          c + cdir * chord * 0.5 + tdir * th, c - cdir * chord * 0.5 + tdir * th])
        mb.loft(rings, lambda i, j: 'fan')
    return mb


# ----------------------------------------------------------------------------------------
# LANDING GEAR  (22 wheels: nose 2, wing gears 2x4, body gears 2x6)
# ----------------------------------------------------------------------------------------
WHEEL_PROFILE = [(-0.17, 0.0), (-0.17, 0.29), (-0.265, 0.34), (-0.25, 0.62), (-0.14, 0.70), (0.14, 0.70),
                 (0.25, 0.62), (0.265, 0.34), (0.17, 0.29), (0.17, 0.0)]
WHEEL_CIDS = ['metal', 'metal', 'tyre', 'tyre', 'tyre', 'tyre', 'tyre', 'metal', 'metal']


def add_wheel(mb, centre, scale_r=1.0, scale_w=1.0):
    prof = [(w * scale_w, r * scale_r) for (w, r) in WHEEL_PROFILE]
    mb.lathe(prof, centre, A(0, 1, 0), 16, WHEEL_CIDS)


def rotation_between(v, v2):
    """axis (unit) and angle (deg) of the shortest rotation taking direction v to direction v2"""
    a = v.cross(v2)
    ang = math.degrees(math.atan2(a.length, v.dot(v2)))
    return a.normalized(), ang


def gear_defs():
    g = []
    # nose gear: trunnion high in the nose (St 6.0 m, 4.0 m), raked leg to the published axle position,
    # retracts forward about a lateral axis
    g.append(dict(name='NoseGear', kind='nose', trunnion=A(6.00, 0.0, 4.00), axles=[A(4.97, 0.0, 0.635)],
                  wheel_off=REF['nlg_wheel_gap'] / 2, r=0.635, w=0.455, strut_r=0.16, stow_deg=76.0))
    for side, tag in ((-1, 'L'), (1, 'R')):
        b = side * REF['wlg_track'] / 2
        # wing gear: trunnion in the wing box ahead of the inboard flap; retracts inboard about an
        # inclined axis that swings the bogie forward/inboard into the belly fairing
        g.append(dict(name='MainGear_W' + tag, kind='wing', side=side, trunnion=A(32.75, b, 4.10),
                      axles=[A(REF['wlg_s'] - 0.85, b, 0.70), A(REF['wlg_s'] + 0.85, b, 0.70)],
                      wheel_off=REF['wlg_wheel_gap'] / 2, r=0.70, w=0.53, strut_r=0.24,
                      stow_pivot=A(32.20, side * 3.05, 3.55)))
        b = side * REF['blg_track'] / 2
        # body gear: retracts aft about a lateral axis; the bogie counter-rotates (-90 deg) to lie flat
        g.append(dict(name='MainGear_B' + tag, kind='body', side=side, trunnion=A(36.55, b, 3.60),
                      axles=[A(REF['blg_s'] - 1.70, b, 0.70), A(REF['blg_s'], b, 0.70), A(REF['blg_s'] + 1.70, b, 0.70)],
                      wheel_off=REF['blg_wheel_gap'] / 2, r=0.70, w=0.53, strut_r=0.24, stow_deg=90.0))
    for gd in g:
        ax = gd['axles']; zr = gd['r']
        gd['bogie_pivot'] = A(sum(a[0] for a in ax) / len(ax), ax[0][1], zr + 0.28) if gd['kind'] != 'nose' else ax[0]
        tr = gd['trunnion']
        if gd['kind'] == 'nose':
            gd['axis'] = A(0, 1, 0); want = A(-1, 0, 0)
        elif gd['kind'] == 'body':
            gd['axis'] = A(0, 1, 0); want = A(1, 0, 0)
        else:
            v = gd['bogie_pivot'] - tr
            v2 = (gd['stow_pivot'] - tr).normalized() * v.length
            gd['axis'], gd['stow_deg'] = rotation_between(v, v2)
            want = None
        if want is not None:
            gd['axis'] = oriented_axis(tr, gd['axis'], gd['bogie_pivot'], want)
    return g


def build_bogie(mb, gd):
    ax = gd['axles']; zr = gd['r']; bc = ax[0][1]
    beam_z = zr + 0.28
    s_lo, s_hi = min(a[0] for a in ax) - 0.25, max(a[0] for a in ax) + 0.25
    mb.cylinder(A(s_lo, bc, beam_z), A(s_hi, bc, beam_z), 0.15, 12, 'metal')            # bogie beam
    for a in ax:
        mb.cylinder(A(a[0], bc, beam_z), A(a[0], bc, zr), 0.09, 8, 'metal')               # axle post
        mb.cylinder(A(a[0], bc - gd['wheel_off'] + 0.18, zr), A(a[0], bc + gd['wheel_off'] - 0.18, zr), 0.09, 8, 'metal')


def build_gear_leg(gd):
    mb = MB()
    tr = gd['trunnion']; ax = gd['axles']; zr = gd['r']
    if gd['kind'] == 'nose':
        a0 = ax[0]
        bottom = A(a0[0] + 0.02, 0.0, zr + 0.24)
        mb.cylinder(tr, bottom, gd['strut_r'], 16, 'strut')                                 # main strut
        mb.cylinder(tr + (bottom - tr) * 0.80, a0, 0.11, 12, 'metal')                     # slider
        mb.cylinder(A(a0[0], -gd['wheel_off'] + 0.12, zr), A(a0[0], gd['wheel_off'] - 0.12, zr), 0.08, 12, 'metal')
        p_leg = tr + (bottom - tr) * 0.55
        mb.cylinder(p_leg, A(tr[0] - 0.85, 0.0, tr[2] - 0.30), 0.07, 8, 'strut')           # drag brace
        return mb
    beam_z = zr + 0.28
    piv = gd['bogie_pivot']
    top_slider = A(piv[0], piv[1], beam_z + 0.75)
    mb.cylinder(tr, A(piv[0], piv[1], beam_z + 0.55), gd['strut_r'], 16, 'strut')         # main strut
    mb.cylinder(top_slider, piv, gd['strut_r'] * 0.7, 12, 'metal')                         # slider into the bogie pivot
    p_leg = tr + (A(piv[0], piv[1], beam_z + 0.55) - tr) * 0.45
    if gd['kind'] == 'wing':
        build_bogie(mb, gd)
        # drag brace: from the strut to a point on the retraction axis ahead of the trunnion (does not move)
        a_fwd = gd['axis'] if gd['axis'][0] < 0 else -gd['axis']
        mb.cylinder(p_leg, tr + a_fwd * 0.75, 0.09, 8, 'strut')
    else:
        mb.cylinder(p_leg, A(tr[0] - 0.95, tr[1], tr[2] - 0.15), 0.09, 8, 'strut')        # drag brace forward
    return mb


def build_gear_bogie(gd):
    mb = MB()
    build_bogie(mb, gd)
    return mb


def build_gear_wheels(gd, axle):
    mb = MB()
    for sgn in (-1, 1):
        add_wheel(mb, A(axle[0], axle[1] + sgn * gd['wheel_off'], axle[2]), gd['r'] / 0.70, gd['w'] / 0.53)
    return mb


# ----------------------------------------------------------------------------------------
# DECALS ON THE FUSELAGE: windows, doors, cockpit panes, titles (all conformal slabs that follow
# the skin: every outline edge <= 0.10-0.20 m, faces gridded so chords stay within ~1 mm of the skin)
# ----------------------------------------------------------------------------------------
DOORS = [('M1', 6.32, 'M'), ('M2', 16.50, 'M'), ('M3', 32.68, 'M'), ('M4', 44.74, 'M'), ('M5', 53.63, 'M'),
         ('U1', 20.94, 'U'), ('U2', 40.30, 'U'), ('U3', 49.19, 'U')]
DOOR_W, DOOR_H, DOOR_R = 1.07, 1.93, 0.22
DOOR_OUT, DOOR_IN = 0.045, 0.04
SILL = {'M': 5.15, 'U': 7.90}
WIN = {'M': dict(z=6.18, w=0.27, h=0.40, s0=7.95, s1=58.2, pitch=0.58),
       'U': dict(z=8.95, w=0.27, h=0.37, s0=13.0, s1=56.0, pitch=0.62)}


def side_P(side):
    def P(s, z, off):
        p, n = surf_frame(s, z_to_phi(s, z), side)
        return p + n * off
    return P


def grid_slab(mb, P, us, vs, off_out, off_in, cid, cid_side=None):
    """closed slab over the param grid us x vs: P(u, v, off) -> A point (off along the skin normal)."""
    cid_side = cid_side or cid
    nu, nv = len(us), len(vs)
    F = [[mb.v(P(u, v, off_out)) for v in vs] for u in us]
    B = [[mb.v(P(u, v, -off_in)) for v in vs] for u in us]
    for i in range(nu - 1):
        for j in range(nv - 1):
            mb.f((F[i][j], F[i + 1][j], F[i + 1][j + 1], F[i][j + 1]), cid)
            mb.f((B[i][j + 1], B[i + 1][j + 1], B[i + 1][j], B[i][j]), cid)
    loop = [(i, 0) for i in range(nu - 1)] + [(nu - 1, j) for j in range(nv - 1)] + \
           [(i, nv - 1) for i in range(nu - 1, 0, -1)] + [(0, j) for j in range(nv - 1, 0, -1)]
    for k in range(len(loop)):
        (i, j), (i2, j2) = loop[k], loop[(k + 1) % len(loop)]
        mb.f((F[i][j], B[i][j], B[i2][j2], F[i2][j2]), cid_side)


def rrect_loop(sc, zc, a, c, r, d, nv, nh, ncs):
    """rounded-rectangle outline inset by d (corner centres fixed, so all insets have the same vertex count)"""
    a2, c2, r2 = a - d, c - d, max(r - d, 0.0)
    ea, ec = a - r, c - r
    pts = []
    for k in range(nv):
        pts.append((sc + a2, zc - ec + 2 * ec * k / nv))
    for k in range(ncs):
        t = math.radians(90.0 * k / ncs); pts.append((sc + ea + r2 * math.cos(t), zc + ec + r2 * math.sin(t)))
    for k in range(nh):
        pts.append((sc + ea - 2 * ea * k / nh, zc + c2))
    for k in range(ncs):
        t = math.radians(90.0 + 90.0 * k / ncs); pts.append((sc - ea + r2 * math.cos(t), zc + ec + r2 * math.sin(t)))
    for k in range(nv):
        pts.append((sc - a2, zc + ec - 2 * ec * k / nv))
    for k in range(ncs):
        t = math.radians(180.0 + 90.0 * k / ncs); pts.append((sc - ea + r2 * math.cos(t), zc - ec + r2 * math.sin(t)))
    for k in range(nh):
        pts.append((sc - ea + 2 * ea * k / nh, zc - c2))
    for k in range(ncs):
        t = math.radians(270.0 + 90.0 * k / ncs); pts.append((sc + ea + r2 * math.cos(t), zc - ec + r2 * math.sin(t)))
    return pts


def rrect_panel(mb, P, sc, z0, w, h, r, off_out, off_in, cid_face, cid_band=None, band=0.0, dz=0.12, ds=0.21, ncs=6):
    """O-grid rounded-rectangle slab: outline ring (+ optional outline band), gridded face, fan back."""
    a, c = w / 2, h / 2; zc = z0 + c
    ea, ec = a - r, c - r
    nv = max(2, math.ceil(2 * ec / dz)); nh = max(1, math.ceil(2 * ea / ds))
    cache = {}

    def V(s, z, off):
        key = (round(s, 5), round(z, 5), off)
        if key not in cache:
            cache[key] = mb.v(P(s, z, off))
        return cache[key]
    insets = (0.0, band, r) if band > 0 else (0.0, r)
    loops = [rrect_loop(sc, zc, a, c, r, d, nv, nh, ncs) for d in insets]
    Fr = [[V(s, z, off_out) for s, z in L] for L in loops]
    n = len(loops[0])
    for li in range(len(loops) - 1):
        cid = cid_band if (band > 0 and li == 0) else cid_face
        for j in range(n):
            j2 = (j + 1) % n
            mb.f((Fr[li][j], Fr[li][j2], Fr[li + 1][j2], Fr[li + 1][j]), cid)
    for i in range(nh):
        for j in range(nv):
            s_a, s_b = sc - ea + 2 * ea * i / nh, sc - ea + 2 * ea * (i + 1) / nh
            z_a, z_b = zc - ec + 2 * ec * j / nv, zc - ec + 2 * ec * (j + 1) / nv
            mb.f((V(s_a, z_a, off_out), V(s_b, z_a, off_out), V(s_b, z_b, off_out), V(s_a, z_b, off_out)), cid_face)
    cside = cid_band or cid_face
    Bk = [V(s, z, -off_in) for s, z in loops[0]]
    cb = V(sc, zc, -off_in)
    for j in range(n):
        j2 = (j + 1) % n
        mb.f((Bk[j2], Bk[j], cb), cside)
        mb.f((Fr[0][j], Bk[j], Bk[j2], Fr[0][j2]), cside)


def door_window_gap(deck):
    return [d[1] for d in DOORS if d[2] == deck]


def build_windows(deck, side):
    """window row of one deck and side + dark door-opening plates (hidden behind the closed doors)."""
    mb = MB()
    w = WIN[deck]; P = side_P(side)
    door_s = door_window_gap(deck)
    s = w['s0']
    hw, hh = w['w'] / 2, w['h'] / 2
    while s <= w['s1']:
        if all(abs(s - ds) > DOOR_W / 2 + 0.30 for ds in door_s):
            grid_slab(mb, P, [s - hw, s + hw], [w['z'] - hh, w['z'], w['z'] + hh], 0.035, 0.03, 'glass')
        s += w['pitch']
    for ds in door_s:
        rrect_panel(mb, P, ds, SILL[deck] + 0.012, DOOR_W - 0.024, DOOR_H - 0.024, DOOR_R - 0.012,
                    0.032, 0.025, 'glass', dz=0.25, ds=0.70, ncs=2)
    return mb


def build_door(sc, deck, side):
    mb = MB()
    rrect_panel(mb, side_P(side), sc, SILL[deck], DOOR_W, DOOR_H, DOOR_R, DOOR_OUT, DOOR_IN, 'white',
                cid_band='seam', band=0.035, dz=0.10, ds=0.32, ncs=6)
    return mb


# cockpit panes.  Front windscreen: four-sided, defined head-on in (b, z) and projected along the fuselage axis;
# side panes defined in (s, z) on the side.  Corners: [inner/front-bottom, outer/aft-bottom, outer/aft-top, inner/front-top]
WS_FRONT = [(0.075, 6.62), (1.15, 6.70), (1.15, 7.40), (0.075, 7.36)]
WS_SIDE = [[(None, 6.72), (3.62, 6.76), (3.62, 7.36), (None, 7.40)],
           [(3.76, 6.78), (4.16, 6.80), (4.16, 7.28), (3.76, 7.33)]]
WS_POST = 0.15                          # surface width of the post between windscreen and first side pane


def front_P(side, corners):
    def P(u, v, off):
        b, z = bilerp(corners, u, v)
        s, phi, sd = front_surface(side * b, z)
        p, n = surf_frame(s, phi, sd)
        return p + n * off
    return P


def side_panel_P(side, corners):
    P0 = side_P(side)

    def P(u, v, off):
        s, z = bilerp(corners, u, v)
        return P0(s, z, off)
    return P


def cockpit_corners():
    """side-pane corner lists; the first side pane's forward edge runs parallel to the windscreen's outer
    edge, WS_POST away from it on the skin (found by bisection along s at the same height)"""
    out = []
    s1 = [list(p) for p in WS_SIDE[0]]
    for k_side, k_front in ((0, 1), (3, 2)):
        b, z = WS_FRONT[k_front]
        sf, phf, sd = front_surface(b, z)
        pf = fus_pt(sf, phf, 1)
        zz = s1[k_side][1]
        lo, hi = sf, sf + 2.0
        for _ in range(50):
            mid = 0.5 * (lo + hi)
            if (fus_pt(mid, z_to_phi(mid, zz), 1) - pf).length < WS_POST:
                lo = mid
            else:
                hi = mid
        s1[k_side][0] = 0.5 * (lo + hi)
        out.append(sf)
    return [tuple(p) for p in s1], WS_SIDE[1], tuple(out)


def pane_angles():
    """interior angles (deg, measured on the skin between the corner points) of every cockpit pane (stbd side)"""
    sp1, sp2, _ = cockpit_corners()
    panes = {'windscreen': front_P(1, WS_FRONT), 'side_1': side_panel_P(1, sp1), 'side_2': side_panel_P(1, sp2)}
    out = {}
    for nm, P in panes.items():
        c = [P(u, v, 0.0) for u, v in ((0, 0), (1, 0), (1, 1), (0, 1))]
        ang = []
        for k in range(4):
            e1 = c[(k - 1) % 4] - c[k]; e2 = c[(k + 1) % 4] - c[k]
            ang.append(round(math.degrees(e1.angle(e2)), 1))
        out[nm] = dict(angles_deg=ang, edge_lengths_m=[round((c[(k + 1) % 4] - c[k]).length, 2) for k in range(4)])
    return out


def build_cockpit():
    mb = MB()
    sp1, sp2, _ = cockpit_corners()
    for side in (1, -1):
        grid_slab(mb, front_P(side, WS_FRONT), lin(0, 1, 7), lin(0, 1, 6), 0.04, 0.04, 'glass')
        for corners in (sp1, sp2):
            grid_slab(mb, side_panel_P(side, corners), lin(0, 1, 4), lin(0, 1, 4), 0.04, 0.04, 'glass')
    return mb


def build_titles(side):
    """'AI EMPIRE AIR' fuselage titles (fictional airline), conformal to the skin."""
    tb = text_bmesh('AI EMPIRE AIR', 1.38, 0.04)
    xs = [v.co.x for v in tb.verts]; ys = [v.co.y for v in tb.verts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    for v in tb.verts:
        v.co.x -= x0; v.co.y -= y0
    width = x1 - x0
    subdivide_long_edges_2d(tb, 0.25)
    s_start, z_base = 22.6, 7.22
    P = side_P(side)

    def mapping(u, vv, w):
        s = s_start + u if side < 0 else s_start + width - u      # reads nose->tail on port, tail->nose on stbd
        return P(s, z_base + vv, 0.015 + w * 0.035)
    mb = MB()
    map_artwork(mb, tb, mapping, 'navy')
    return mb, (s_start, s_start + width, z_base, z_base + (y1 - y0))


# ----------------------------------------------------------------------------------------
# finalisation: bmesh -> object with colours, material, pivot, smoothing
# ----------------------------------------------------------------------------------------
MATS = {}
MAT_SRGB = {}     # material name -> sRGB base colour (written to the .mtl)


def get_mat(name, base):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    lin_c = tuple(srgb2lin(c) for c in base) + (1.0,)
    p.inputs['Base Color'].default_value = lin_c
    rough = {'MAT_WindowGlass': 0.12, 'MAT_Tyre': 0.85}.get(name, 0.38)
    p.inputs['Roughness'].default_value = rough
    if name in ('MAT_GearStrut', 'MAT_Fan'):
        p.inputs['Metallic'].default_value = 0.4
    m.diffuse_color = lin_c
    MATS[name] = m
    MAT_SRGB[name] = tuple(base)
    return m


OBJECTS = []   # (obj, info dict)


def finalize(mb, name, mat_name, mat_base, pivot_A, smooth_angle=40.0, info=None):
    bm = mb.bm
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='EAR_CLIP')
    deg = [f for f in bm.faces if f.calc_area() < 1e-10]
    if deg:
        bmesh.ops.delete(bm, geom=deg, context='FACES_ONLY')
    piv = to_blender(pivot_A)
    bmesh.ops.translate(bm, verts=bm.verts, vec=-piv)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    cols = []
    cid_attr = me.attributes.get('cid')
    if cid_attr is not None:
        cids = [0] * len(me.polygons)
        cid_attr.data.foreach_get('value', cids)
        loop_cols = [0.0] * (len(me.loops) * 4)
        for poly in me.polygons:
            c = PAL[CNAME[cids[poly.index]]]
            lc = (srgb2lin(c[0]), srgb2lin(c[1]), srgb2lin(c[2]), 1.0)
            for li in poly.loop_indices:
                loop_cols[li * 4:li * 4 + 4] = lc
        ca = me.color_attributes.new('Col', 'BYTE_COLOR', 'CORNER')
        ca.data.foreach_set('color', loop_cols)
        me.color_attributes.active_color = ca
        try:
            me.color_attributes.render_color_index = me.color_attributes.active_color_index
        except Exception:
            pass
        cols = sorted(set(CNAME[c] for c in cids))
        me.attributes.remove(me.attributes['cid'])
    aux = set()
    part_attr = me.attributes.get('part')
    if part_attr is not None:
        parts = [0] * len(me.polygons)
        part_attr.data.foreach_get('value', parts)
        for poly in me.polygons:
            if parts[poly.index]:
                aux.update(poly.vertices)
        me.attributes.remove(me.attributes['part'])
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(smooth_angle))
    me.materials.append(get_mat(mat_name, mat_base))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = piv
    inf = dict(info or {})
    inf.update(name=name, material=mat_name, colors=cols, pivot_A=list(pivot_A), aux_verts=aux)
    OBJECTS.append((ob, inf))
    return ob


# ----------------------------------------------------------------------------------------
# axis helper: choose axis sign so that +angle moves `probe` towards `want` (A coords)
# ----------------------------------------------------------------------------------------
def oriented_axis(pivot, axis, probe, want):
    r = probe - pivot
    d = axis.normalized().cross(r)          # instantaneous velocity for +rotation (right-hand rule)
    return axis.normalized() if d.dot(want) >= 0 else -axis.normalized()


def A_dir_to_roblox(d):
    return blender_to_roblox(Vector((-d[1], d[0], d[2]))).normalized()


# ----------------------------------------------------------------------------------------
# BUILD
# ----------------------------------------------------------------------------------------
def build_all():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    OBJECTS.clear(); MATS.clear(); MAT_SRGB.clear()
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'; sc.unit_settings.scale_length = 1.0

    finalize(build_fuselage(), 'Fuselage', 'MAT_Fuselage', PAL['white'], A(S0, 0, 0),
             info=dict(role='fuselage incl. belly / wing-root fairing (boolean union, one closed shell)',
                       movable=False, can_collide=True))
    for deck, dname in (('M', 'Main'), ('U', 'Upper')):
        for side, tag in ((-1, 'L'), (1, 'R')):
            w = WIN[deck]
            finalize(build_windows(deck, side), f'WindowStrip_{dname}_{tag}', 'MAT_WindowGlass', PAL['glass'],
                     fus_pt(0.5 * (w['s0'] + w['s1']), z_to_phi(0.5 * (w['s0'] + w['s1']), w['z']), side),
                     smooth_angle=30, info=dict(role=f'{dname.lower()}-deck window row + dark door-opening plates',
                                                movable=False))
    finalize(build_cockpit(), 'WindowStrip_Cockpit', 'MAT_WindowGlass', PAL['glass'], A(3.0, 0, 7.2),
             smooth_angle=50, info=dict(role='cockpit windscreen + side panes', movable=False))
    # doors: hinge at forward edge, swing outward
    for dn, ds, deck in DOORS:
        for side, tag in ((-1, 'L'), (1, 'R')):
            zc = SILL[deck] + DOOR_H / 2
            s_h = ds - DOOR_W / 2
            p_h, n_h = surf_frame(s_h, z_to_phi(s_h, zc), side)
            pivot = p_h + n_h * DOOR_OUT
            top = surf_frame(s_h, z_to_phi(s_h, SILL[deck] + DOOR_H), side)[0]
            bot = surf_frame(s_h, z_to_phi(s_h, SILL[deck]), side)[0]
            axis = oriented_axis(pivot, top - bot, surf_frame(ds + DOOR_W / 2, z_to_phi(ds, zc), side)[0],
                                 A(0, side, 0))
            finalize(build_door(ds, deck, side), f'Door_{dn}{tag}', 'MAT_Door', PAL['white'], pivot, smooth_angle=35,
                     info=dict(role=f'passenger door {dn}{tag} ({"main" if deck == "M" else "upper"} deck)', movable=True,
                               hinge_axis_A=list(axis), limits_deg=[0, 100], parent='Fuselage', hinge_r=0.05,
                               positive='opens outward (simplified swing about forward edge; real doors of this '
                                        'type translate out and slide forward)'))
    # wings & control surfaces
    for side, tag in ((-1, 'L'), (1, 'R')):
        finalize(build_wing(side), f'Wing_{tag}', 'MAT_Wing', PAL['wing'],
                 A(wing_le(4.0), side * 4.0, wing_zc(4.0)),
                 info=dict(role='wing (incl. forward halves of the flap-track fairings)', movable=False))
        finalize(build_fence(side), f'Fence_{tag}', 'MAT_Fence', PAL['navy'], A(46.97, side * FENCE_B, wing_zc(FENCE_B)),
                 info=dict(role='wing-tip fence', movable=False))
        for (tmpl, b0, b1, f0, f1) in WING_SURF:
            nm = tmpl.format(S=tag)
            mb, h0, h1, rmax = build_wing_surface(side, b0, b1)
            mid = (h0 + h1) * 0.5
            axis = oriented_axis(mid, h1 - h0, A(wing_te(0.5 * (b0 + b1)), side * 0.5 * (b0 + b1), mid[2]), A(0, 0, -1))
            lim = [-25, 20] if nm.startswith('Aileron') else [0, 35]
            finalize(mb, nm, 'MAT_ControlSurface', PAL['wing'], mid,
                     info=dict(role='aileron' if 'Aileron' in nm else 'flap (incl. aft halves of its flap-track fairings)',
                               movable=True, hinge_axis_A=list(axis), parent='Fuselage', fixed_parent=f'Wing_{tag}',
                               hinge_line_A=[list(h0), list(h1)], limits_deg=lim, positive='trailing edge down',
                               hinge_r=rmax,
                               note='flaps simplified as pure rotation about the hinge line (real Fowler flaps '
                                    'also translate aft)' if 'Flap' in nm else ''))
        finalize(build_hstab(side), f'HStab_{tag}', 'MAT_HStab', PAL['wing'], A(hs_le(0.0), 0.0, hs_zc(0.0)),
                 info=dict(role='horizontal stabiliser', movable=False))
        mb, h0, h1, rmax = build_elevator(side)
        mid = (h0 + h1) * 0.5
        axis = oriented_axis(mid, h1 - h0, A(hs_te(8.0), side * 8.0, mid[2]), A(0, 0, -1))
        finalize(mb, f'Elevator_{tag}', 'MAT_ControlSurface', PAL['wing'], mid,
                 info=dict(role='elevator', movable=True, hinge_axis_A=list(axis), hinge_line_A=[list(h0), list(h1)],
                           parent='Fuselage', fixed_parent=f'HStab_{tag}', hinge_r=rmax,
                           limits_deg=[-30, 20], positive='trailing edge down (nose-down pitch)'))
    finalize(build_vstab(), 'VStab', 'MAT_Tail', PAL['navy'], A(vs_le(10.8), 0.0, 10.8),
             info=dict(role='vertical stabiliser (fin)', movable=False))
    mb, h0, h1, rmax = build_rudder()
    mid = (h0 + h1) * 0.5
    axis = oriented_axis(mid, h1 - h0, A(vs_te(17.0), 0.0, 17.0), A(0, 1, 0))
    finalize(mb, 'Rudder', 'MAT_Tail', PAL['navy'], mid,
             info=dict(role='rudder', movable=True, hinge_axis_A=list(axis), hinge_line_A=[list(h0), list(h1)],
                       parent='Fuselage', fixed_parent='VStab', hinge_r=rmax,
                       limits_deg=[-30, 30], positive='trailing edge to starboard (nose-right yaw)'))
    finalize(build_tail_logo(), 'TailLogo', 'MAT_Logo', PAL['gold'], A(vs_le(16.5) + 4.0, 0.0, 16.5),
             smooth_angle=30, info=dict(role='fictional AI Empire emblem: gold crown + navy "AI" monogram (both sides)',
                                        movable=False))
    for side, tag in ((-1, 'L'), (1, 'R')):
        mb, rng = build_titles(side)
        finalize(mb, f'Titles_{tag}', 'MAT_Titles', PAL['navy'],
                 surf_frame(0.5 * (rng[0] + rng[1]), z_to_phi(0.5 * (rng[0] + rng[1]), 0.5 * (rng[2] + rng[3])), side)[0],
                 smooth_angle=30, info=dict(role='"AI EMPIRE AIR" titles (fictional)', movable=False))
    # engines + fans
    for (n, s0, b0, z0) in ENGINES:
        finalize(build_engine(s0, b0, z0), f'Engine_{n}', 'MAT_Engine', PAL['navy'], A(s0 + FAN_X, b0, z0),
                 smooth_angle=50, info=dict(role='engine nacelle + core/plug + pylon', movable=False))
        piv = A(s0 + FAN_X, b0, z0)
        axis = oriented_axis(piv, A(-1, 0, 0), piv + A(0, 0, 1.0), A(0, -1, 0))
        finalize(build_fan(s0, b0, z0, True), f'Fan_{n}', 'MAT_Fan', PAL['fan'], piv, smooth_angle=30,
                 info=dict(role='fan + spinner (spins)', movable=True, hinge_axis_A=list(axis), limits_deg=None,
                           parent='Fuselage', positive='clockwise as seen from in front of the engine (continuous)'))
    # landing gear
    for gd in gear_defs():
        tr = gd['trunnion']
        desc = {'nose': 'retracts forward', 'body': 'retracts aft into the belly fairing',
                'wing': 'retracts inboard (inclined axis) into the belly fairing'}[gd['kind']]
        ang = round(gd['stow_deg'], 2)
        finalize(build_gear_leg(gd), gd['name'], 'MAT_GearStrut', PAL['strut'], tr, smooth_angle=45,
                 info=dict(role='landing-gear leg (' + desc + ')', movable=True, hinge_axis_A=list(gd['axis']),
                           limits_deg=[0, ang], retract_deg=ang, parent='Fuselage',
                           positive=desc + ' (retracted at +%g deg)' % ang))
        wheel_parent = gd['name']
        if gd['kind'] == 'body':
            bname = gd['name'] + '_Bogie'
            finalize(build_gear_bogie(gd), bname, 'MAT_GearStrut', PAL['metal'], gd['bogie_pivot'], smooth_angle=45,
                     info=dict(role=f'bogie beam + axles of {gd["name"]} (tilts flat when stowed)', movable=True,
                               hinge_axis_A=list(gd['axis']), limits_deg=[-90, 0], retract_deg=-90.0, parent=gd['name'],
                               positive='same axis as the leg; -90 deg (relative to the leg) = bogie flat when stowed'))
            wheel_parent = bname
        for k, axl in enumerate(gd['axles']):
            wname = gd['name'] + ('_Wheels' if len(gd['axles']) == 1 else f'_Wheels{k + 1}')
            waxis = oriented_axis(axl, A(0, 1, 0), axl + A(0, 0, gd['r']), A(-1, 0, 0))
            finalize(build_gear_wheels(gd, axl), wname, 'MAT_Tyre', PAL['tyre'], axl, smooth_angle=50,
                     info=dict(role=f'wheel pair on axle {k + 1} of {gd["name"]} (spins; moves with {wheel_parent})',
                               movable=True, hinge_axis_A=list(waxis), limits_deg=None, parent=wheel_parent,
                               positive='forward rolling (continuous)'))


def scale_to_studs():
    S = Matrix.Scale(K, 4)
    for ob, _ in OBJECTS:
        ob.data.transform(S)
        ob.location = ob.location * K
        ob.data.update()
    bpy.context.view_layer.update()      # refresh matrix_world after moving the origins


# ----------------------------------------------------------------------------------------
# checks
# ----------------------------------------------------------------------------------------
def mesh_stats(ob):
    """triangles, non-manifold edges, signed volume (studs^3; > 0 <=> normals point outward), shells"""
    bm = bmesh.new(); bm.from_mesh(ob.data)
    nonman = sum(1 for e in bm.edges if len(e.link_faces) != 2)
    tris = len(bm.faces)
    vol = bm.calc_volume(signed=True)
    # connected components (closed shells)
    seen = set(); shells = 0
    for v in bm.verts:
        if v.index in seen:
            continue
        shells += 1
        stack = [v]; seen.add(v.index)
        while stack:
            x = stack.pop()
            for e in x.link_edges:
                o = e.other_vert(x)
                if o.index not in seen:
                    seen.add(o.index); stack.append(o)
    bm.free()
    return tris, nonman, vol, shells


FALLBACK_OVERRIDE = {'Fuselage': 'white', 'Engine_': 'navy', 'MainGear_B': 'strut', 'Door_': 'white'}


def dominant_colour(ob):
    """sRGB 0-255 of the vertex colour covering the largest surface area (Studio fallback colour)"""
    for prefix, cname in FALLBACK_OVERRIDE.items():
        if ob.name.startswith(prefix) and not ob.name.endswith('_Bogie') and '_Wheels' not in ob.name:
            return [int(round(x * 255)) for x in PAL[cname]]
    me = ob.data
    ca = me.color_attributes.get('Col')
    if ca is None:
        return None
    area = {}
    for poly in me.polygons:
        c = tuple(round(x, 3) for x in ca.data[poly.loop_indices[0]].color_srgb[:3])
        area[c] = area.get(c, 0.0) + poly.area
    best = max(area, key=area.get)
    return [int(round(x * 255)) for x in best]


def world_bbox(obs):
    lo = Vector((1e9, 1e9, 1e9)); hi = -lo
    for ob in obs:
        mw = ob.matrix_world
        for v in ob.data.vertices:
            w = mw @ v.co
            lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
    return lo, hi


def r3(v, nd=3):
    return [round(float(x), nd) for x in v]


# ---------------- motion checks (posed geometry, generalised winding numbers) ------------------
def ob_verts(ob):
    co = np.empty(len(ob.data.vertices) * 3); ob.data.vertices.foreach_get('co', co)
    return co.reshape(-1, 3) + np.array(ob.matrix_world.translation)


def ob_tris(ob, M=None, subset=None, aux=None):
    """world-space triangles; subset='main' / 'aux' keeps only main-body / fairing shells (aux = vertex ids)"""
    me = ob.data; me.calc_loop_triangles()
    idx = np.empty(len(me.loop_triangles) * 3, dtype=np.int64); me.loop_triangles.foreach_get('vertices', idx)
    idx = idx.reshape(-1, 3)
    if subset is not None:
        is_aux = np.array([int(i) in aux for i in idx[:, 0]], dtype=bool)
        idx = idx[~is_aux] if subset == 'main' else idx[is_aux]
    V = ob_verts(ob)
    if M is not None:
        V = V @ M[:3, :3].T + M[:3, 3]
    return V[idx]


def winding(points, tris):
    """generalised winding number of each point w.r.t. a closed, outward-oriented triangle soup
    (robust for overlapping shells: inside -> >= 1, outside -> 0)."""
    out = np.zeros(len(points))
    if len(points) == 0 or len(tris) == 0:
        return out
    ch = max(1, int(1.5e6 // len(tris)))
    for i in range(0, len(points), ch):
        p = points[i:i + ch][:, None, :]
        a = tris[None, :, 0, :] - p; b = tris[None, :, 1, :] - p; c = tris[None, :, 2, :] - p
        la = np.linalg.norm(a, axis=2); lb = np.linalg.norm(b, axis=2); lc = np.linalg.norm(c, axis=2)
        det = np.einsum('ijk,ijk->ij', a, np.cross(b, c))
        den = la * lb * lc + np.einsum('ijk,ijk->ij', a, b) * lc + np.einsum('ijk,ijk->ij', b, c) * la + \
            np.einsum('ijk,ijk->ij', c, a) * lb
        out[i:i + ch] = np.arctan2(det, den).sum(axis=1) / (2 * math.pi)
    return out


def rot4(pivot, axis, deg):
    a = np.array(axis) / np.linalg.norm(axis); t = math.radians(deg)
    Kx = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    R = np.eye(3) + math.sin(t) * Kx + (1 - math.cos(t)) * Kx @ Kx
    M = np.eye(4); M[:3, :3] = R; M[:3, 3] = np.array(pivot) - R @ np.array(pivot)
    return M


def joint_table():
    J = {}
    for ob, inf in OBJECTS:
        if 'hinge_axis_A' in inf:
            J[ob.name] = dict(pivot=np.array(ob.location), axis=np.array(dir_to_blender(inf['hinge_axis_A'])),
                              parent=inf.get('parent', 'Fuselage'), limits=inf.get('limits_deg'),
                              retract=inf.get('retract_deg'), hinge_r=inf.get('hinge_r', 0.0) * K,
                              fixed_parent=inf.get('fixed_parent'))
    return J


def pose_matrix(name, angles, J):
    if name not in J:
        return np.eye(4)
    j = J[name]
    return pose_matrix(j['parent'], angles, J) @ rot4(j['pivot'], j['axis'], angles.get(name, 0.0))


def posed_verts(ob, M):
    V = ob_verts(ob)
    return V @ M[:3, :3].T + M[:3, 3]


def dist_to_line(P, p0, a):
    a = a / np.linalg.norm(a)
    d = P - p0
    return np.linalg.norm(d - np.outer(d @ a, a), axis=1)


def motion_checks():
    t0 = time.time()
    obs = {ob.name: ob for ob, _ in OBJECTS}
    infs = {ob.name: inf for ob, inf in OBJECTS}
    J = joint_table()
    res = dict(method='generalised winding number (inside >= 0.5) of posed vertices against closed target meshes; '
                      'poses = manifest pivots, hinge axes and rotation limits (children follow their "parent" chain)')
    hull_names = ['Fuselage', 'Wing_L', 'Wing_R']
    hull = np.concatenate([ob_tris(obs[n]) for n in hull_names])
    hull_bvh = []
    for n in hull_names:
        ob = obs[n]; V = ob_verts(ob)
        hull_bvh.append(BVHTree.FromPolygons([tuple(v) for v in V], [tuple(p.vertices) for p in ob.data.polygons]))

    def outside_depth(P):
        return max((min(b.find_nearest(Vector(p))[3] for b in hull_bvh) for p in P), default=0.0)

    # 1) gear retraction: every leg / bogie / wheel vertex inside Fuselage u Wing at full retraction
    groups = {}
    for n, j in J.items():
        if j['retract'] is not None and j['parent'] == 'Fuselage':
            groups[n] = [n] + [m for m in J if m != n and n in chain(m, J)]
    stow = {n: J[n]['retract'] for n in J if J[n]['retract'] is not None}
    gear = {}
    posed_cache = {}
    for g, members in groups.items():
        gres = {}
        for m in members:
            P = posed_verts(obs[m], pose_matrix(m, stow, J))
            posed_cache[m] = P
            w = winding(P, hull)
            out = P[w < 0.5]
            gres[m] = dict(vertices=len(P), outside=int(len(out)),
                           max_outside_m=round(outside_depth(out) * STUD_M, 3) if len(out) else 0.0)
        gear[g] = gres
    res['gear_retracted_inside_hull'] = gear
    res['gear_retracted_total_outside'] = sum(x['outside'] for g in gear.values() for x in g.values())
    # control test (proves the inside test is not vacuous): with the gear DOWN the tyres must be outside
    ctrl = {}
    for g, members in groups.items():
        P = np.concatenate([ob_verts(obs[m]) for m in members if '_Wheels' in m])
        ctrl[g] = dict(wheel_vertices=len(P), outside_when_down=int((winding(P, hull) < 0.5).sum()))
    res['control_test_gear_down_wheels_outside'] = ctrl
    # 2) stowed gears must not overlap each other
    clash = {}
    gl = list(groups)
    for i in range(len(gl)):
        for k in range(i + 1, len(gl)):
            ga, gb = gl[i], gl[k]
            Pa = np.concatenate([posed_cache[m] for m in groups[ga]])
            tb = np.concatenate([ob_tris(obs[m], pose_matrix(m, stow, J)) for m in groups[gb]])
            lo = np.minimum(Pa.min(0), tb.reshape(-1, 3).min(0)); hi = np.maximum(Pa.max(0), tb.reshape(-1, 3).max(0))
            bmin_a, bmax_a = Pa.min(0), Pa.max(0); bmin_b, bmax_b = tb.reshape(-1, 3).min(0), tb.reshape(-1, 3).max(0)
            if np.any(bmax_a < bmin_b) or np.any(bmax_b < bmin_a):
                n_in = 0
            else:
                n_in = int((winding(Pa, tb) > 0.5).sum())
            if n_in:
                clash[f'{ga}/{gb}'] = n_in
    res['stowed_gear_overlaps'] = clash or 'none'
    # 3) control surfaces at both limits vs. their fixed parent surface
    cs = {}
    for n, j in J.items():
        if not j.get('fixed_parent') or not j['limits']:
            continue
        par = obs[j['fixed_parent']]
        Vpar = ob_verts(par); Tpar = ob_tris(par)
        zone = 1.5 * j['hinge_r'] + 0.05 * K
        aux = infs[n]['aux_verts']; aux_p = infs[par.name]['aux_verts']
        idx_main = np.array([i for i in range(len(obs[n].data.vertices)) if i not in aux], dtype=np.int64)
        entry = {}
        for lim in j['limits']:
            M = pose_matrix(n, {n: lim}, J)
            Ts = ob_tris(obs[n], M, 'main', aux)          # moving surface body (without its fairing halves)
            Ps = posed_verts(obs[n], M)
            wa = winding(Vpar, Ts)
            far_par = dist_to_line(Vpar, j['pivot'], j['axis']) > zone
            a_cnt = int(((wa > 0.5) & far_par).sum())
            Pm = Ps[idx_main]
            wb = winding(Pm, Tpar)
            far_s = dist_to_line(Pm, j['pivot'], j['axis']) > zone
            b_cnt = int(((wb > 0.5) & far_s).sum())
            e = dict(parent_vertices_inside_surface=a_cnt, surface_vertices_inside_parent=b_cnt)
            if len(aux):
                # info only: the aft fairing half (moves with the flap) slides into the forward half (fixed) at
                # the cut below the hinge - fairing against fairing, under the wing
                Pa = Ps[np.array(sorted(aux), dtype=np.int64)]
                Tpa = ob_tris(par, None, 'aux', aux_p)
                e['info_fairing_halves_overlap_vertices'] = int((winding(Pa, Tpa) > 0.5).sum())
            entry[f'{lim:+d}deg'] = e
        cs[n] = entry
    res['control_surfaces_at_limits'] = cs
    res['control_surfaces_breakthroughs_total'] = sum(e['parent_vertices_inside_surface'] + e['surface_vertices_inside_parent']
                                                      for d in cs.values() for e in d.values())
    # 4) flaps at max deflection vs. deployed gear legs (both static), and adjacent flaps together
    misc = {}
    for tag in 'LR':
        names = [f'Flap_{tag}_Inner', f'Flap_{tag}_Outer']
        Ms = {n: pose_matrix(n, {n: 35}, J) for n in names}
        for gname in (f'MainGear_W{tag}', f'MainGear_B{tag}'):
            Pg = ob_verts(obs[gname])
            for n in names:
                Ts = ob_tris(obs[n], Ms[n])
                misc[f'{gname} (down) inside {n}@35'] = int((winding(Pg, Ts) > 0.5).sum())
                misc[f'{n}@35 inside {gname} (down)'] = int((winding(posed_verts(obs[n], Ms[n]), ob_tris(obs[gname])) > 0.5).sum())
        misc[f'{names[0]}@35 inside {names[1]}@35'] = int((winding(posed_verts(obs[names[0]], Ms[names[0]]),
                                                                    ob_tris(obs[names[1]], Ms[names[1]])) > 0.5).sum())
    res['flaps_vs_gear_and_neighbours'] = misc
    # 5) doors at 100 deg: no intersection with the fuselage (outside a 0.12 m hinge zone), windows, wing
    door = {}
    fus_t = ob_tris(obs['Fuselage'])
    strips = {('M', 'L'): 'WindowStrip_Main_L', ('M', 'R'): 'WindowStrip_Main_R',
              ('U', 'L'): 'WindowStrip_Upper_L', ('U', 'R'): 'WindowStrip_Upper_R'}
    for n, j in J.items():
        if not n.startswith('Door_'):
            continue
        M = pose_matrix(n, {n: j['limits'][1]}, J)
        P = posed_verts(obs[n], M)
        far = dist_to_line(P, j['pivot'], j['axis']) > 0.12 * K
        in_fus = int(((winding(P, fus_t) > 0.5) & far).sum())
        Td = ob_tris(obs[n], M)
        strip = obs[strips[(n[5], n[-1])]]
        Vs = ob_verts(strip)
        near = np.linalg.norm(Vs - P.mean(0), axis=1) < 3.0 * K
        in_door = int((winding(Vs[near], Td) > 0.5).sum()) if near.any() else 0
        in_wing = int((winding(P, ob_tris(obs['Wing_' + n[-1]])) > 0.5).sum())
        door[n] = dict(door_vertices_in_fuselage=in_fus, window_vertices_in_door=in_door, door_vertices_in_wing=in_wing)
    res['doors_open_100deg'] = door
    res['doors_total_intersections'] = sum(sum(d.values()) for d in door.values())
    res['seconds'] = round(time.time() - t0, 1)
    return res


def chain(name, J):
    out = []
    while name in J:
        name = J[name]['parent']
        out.append(name)
    return out


# ----------------------------------------------------------------------------------------
# export
# ----------------------------------------------------------------------------------------
def export_all():
    fbx = os.path.join(HERE, NAME + '.fbx')
    obj = os.path.join(HERE, NAME + '.obj')
    bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.export_scene.fbx(filepath=fbx, use_selection=False, object_types={'MESH'},
                             global_scale=1.0, apply_unit_scale=True, apply_scale_options='FBX_SCALE_UNITS',
                             axis_forward='Z', axis_up='Y', bake_space_transform=True,
                             use_mesh_modifiers=True, mesh_smooth_type='FACE', colors_type='SRGB',
                             use_triangles=True, add_leaf_bones=False, bake_anim=False,
                             path_mode='COPY', embed_textures=True, use_custom_props=False)
    bpy.ops.wm.obj_export(filepath=obj, forward_axis='Z', up_axis='Y', global_scale=1.0,
                          apply_modifiers=True, export_selected_objects=False, export_uv=True,
                          export_normals=True, export_colors=False, export_materials=True,
                          export_triangulated_mesh=True, export_object_groups=False, path_mode='AUTO')
    # Blender writes linear base colours as Kd; most OBJ readers treat Kd as display (sRGB) colour.
    mtl = os.path.join(HERE, NAME + '.mtl')
    out, cur = [], None
    for line in open(mtl).read().splitlines():
        if line.startswith('newmtl '):
            cur = line.split(None, 1)[1].strip()
        if line.startswith('Kd ') and cur in MAT_SRGB:
            line = 'Kd %.6f %.6f %.6f' % MAT_SRGB[cur]
        out.append(line)
    open(mtl, 'w').write('\n'.join(out) + '\n')
    gltf = export_gltf()
    return fbx, obj, gltf


def export_gltf():
    """glTF 2.0 with one node per object (pivot = node translation), vertex colours, 1 unit = 1 stud.
    The scene is turned 180 deg about the vertical for the export so that the raw glTF coordinates equal the
    FBX layout (X right, Y up, nose at -Z)."""
    R = Matrix.Rotation(math.pi, 4, 'Z')
    for ob, _ in OBJECTS:
        ob.data.transform(R); ob.location = R @ ob.location
    bpy.context.view_layer.update()
    path = os.path.join(HERE, NAME + '.gltf')
    fmt_used = None
    for fmt in ('GLTF_EMBEDDED', 'GLTF_SEPARATE'):
        try:
            bpy.ops.export_scene.gltf(filepath=path, export_format=fmt, use_selection=False, export_yup=True,
                                      export_apply=False, export_vertex_color='ACTIVE', export_normals=True,
                                      export_texcoords=True, export_materials='EXPORT', export_animations=False,
                                      export_extras=False)
            fmt_used = fmt
            break
        except Exception as ex:     # GLTF_EMBEDDED needs an add-on preference in newer Blender builds
            print('glTF export with', fmt, 'failed:', ex)
    Ri = Matrix.Rotation(-math.pi, 4, 'Z')
    for ob, _ in OBJECTS:
        ob.data.transform(Ri); ob.location = Ri @ ob.location
    bpy.context.view_layer.update()
    return dict(path=path, format=fmt_used)


# ----------------------------------------------------------------------------------------
# rendering (Cycles CPU)
# ----------------------------------------------------------------------------------------
def setup_render_scene():
    import addon_utils
    addon_utils.enable('cycles', default_set=True, persistent=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 32
    sc.cycles.use_denoising = True
    try:
        sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = 'Standard'
    sc.render.image_settings.file_format = 'PNG'
    for m in MATS.values():
        nt = m.node_tree
        p = nt.nodes.get('Principled BSDF')
        vc = nt.nodes.new('ShaderNodeVertexColor'); vc.layer_name = 'Col'
        nt.links.new(vc.outputs['Color'], p.inputs['Base Color'])
    world = bpy.data.worlds.new('World'); sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get('Background')
    bg.inputs['Color'].default_value = (0.50, 0.62, 0.80, 1.0)
    bg.inputs['Strength'].default_value = 0.85
    sun = bpy.data.lights.new('Sun', 'SUN'); sun.energy = 3.6; sun.angle = math.radians(4)
    so = bpy.data.objects.new('Sun', sun); sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(48), math.radians(12), math.radians(-35))
    gm = bpy.data.meshes.new('Ground')
    s = 4000
    gm.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    go = bpy.data.objects.new('Ground', gm); sc.collection.objects.link(go)
    gmat = bpy.data.materials.new('Ground'); gmat.use_nodes = True
    gp = gmat.node_tree.nodes.get('Principled BSDF')
    gp.inputs['Base Color'].default_value = (0.30, 0.31, 0.32, 1); gp.inputs['Roughness'].default_value = 0.9
    gm.materials.append(gmat)
    return go


def look_at(cam_ob, target):
    d = (Vector(target) - cam_ob.location)
    cam_ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()


def render_view(name, loc, target=None, ortho=None, rot=None, lens=50, ground=None, show_ground=True,
                res=(1280, 720)):
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = res
    cd = bpy.data.cameras.new(name)
    co = bpy.data.objects.new(name, cd); sc.collection.objects.link(co)
    co.location = Vector(loc)
    if ortho:
        cd.type = 'ORTHO'; cd.ortho_scale = ortho
    else:
        cd.lens = lens
    cd.clip_start = 1.0; cd.clip_end = 20000
    if rot is not None:
        co.rotation_euler = rot
    else:
        look_at(co, target)
    sc.camera = co
    if ground is not None:
        ground.hide_render = not show_ground
    sc.render.filepath = os.path.join(RENDER_DIR, name + '.png')
    t = time.time()
    bpy.ops.render.render(write_still=True)
    print(f'  render {name}: {time.time() - t:.1f}s')


def m2b(s, b, z):
    """aircraft metres -> Blender studs (after scaling)"""
    return to_blender(A(s, b, z)) * K


def set_pose(angles):
    """pose movable parts (render only); angles = {object name: deg}; {} restores the rest pose"""
    J = joint_table() if not hasattr(set_pose, 'J') else set_pose.J
    set_pose.J = J
    for ob, _ in OBJECTS:
        if ob.name in J:
            M = pose_matrix(ob.name, angles, J)
            ob.matrix_world = Matrix(M.tolist()) @ Matrix.Translation(Vector(J[ob.name]['pivot']))
    bpy.context.view_layer.update()


def do_renders(only=None):
    os.makedirs(RENDER_DIR, exist_ok=True)
    g = setup_render_scene()
    V = [
        ('front', dict(loc=m2b(-400, 0, 12.0), rot=(math.radians(90), 0, 0), ortho=300)),
        ('side', dict(loc=m2b(36.0, -400, 12.0), rot=(math.radians(90), 0, math.radians(90)), ortho=285)),
        ('top', dict(loc=m2b(36.0, 0, 400), rot=(0, 0, math.radians(90)), ortho=300, res=(1280, 1280))),
        ('three_quarter', dict(loc=m2b(-52.0, -88.0, 32.0), target=m2b(34.0, 0, 6.0), lens=38)),
        ('rear_three_quarter', dict(loc=m2b(118.0, 62.0, 30.0), target=m2b(38.0, 0, 7.0), lens=40)),
        ('closeup_cockpit', dict(loc=m2b(-9.0, -11.0, 9.5), target=m2b(4.0, 0, 6.8), lens=45)),
        ('closeup_cockpit_front', dict(loc=m2b(-16.0, -1.5, 7.6), target=m2b(2.0, 0, 6.6), lens=60)),
        ('closeup_engine', dict(loc=m2b(15.0, -40.0, 2.4), target=m2b(30.5, -25.7, 4.1), lens=50)),
        ('closeup_gear', dict(loc=m2b(27.0, -19.0, 1.6), target=m2b(35.2, -3.5, 1.2), lens=32)),
    ]
    for name, kw in V:
        if only and name not in only:
            continue
        render_view(name, ground=g, **kw)
    J = joint_table(); set_pose.J = J
    stow = {n: j['retract'] for n, j in J.items() if j['retract'] is not None}
    if not only or 'motion_gear_up' in only:
        set_pose(stow)
        render_view('motion_gear_up', loc=m2b(10.0, -55.0, -6.0), target=m2b(36.0, 0, 4.0), lens=30, ground=g,
                    show_ground=False)
        set_pose({})
    if not only or 'motion_flaps_doors' in only:
        pose = {n: 35 for n in J if n.startswith('Flap_')}
        pose.update({n: 100 for n in J if n.startswith('Door_')})
        pose.update({'Aileron_L': -25, 'Aileron_R': 20, 'Elevator_L': -30, 'Elevator_R': -30, 'Rudder': 30})
        set_pose(pose)
        render_view('motion_flaps_doors', loc=m2b(64.0, -40.0, 14.0), target=m2b(34.0, -8.0, 5.0), lens=30, ground=g)
        set_pose({})


# ----------------------------------------------------------------------------------------
# verification of the exported FBX (re-import + raw parse) and glTF (re-import)
# ----------------------------------------------------------------------------------------
def verify_fbx(fbx_path, expected):
    res = {}
    try:
        from io_scene_fbx import parse_fbx
        root, ver = parse_fbx.parse(fbx_path)

        def find(e, name):
            for c in e.elems:
                if c.id == name:
                    return c
            return None
        gs = find(find(root, b'GlobalSettings'), b'Properties70')
        props = {}
        for p in gs.elems:
            key = p.props[0].decode() if isinstance(p.props[0], bytes) else p.props[0]
            props[key] = p.props[-1] if len(p.props) > 4 else None
        res['fbx_version'] = ver
        res['GlobalSettings'] = {k: props.get(k) for k in ('UpAxis', 'UpAxisSign', 'FrontAxis', 'FrontAxisSign',
                                                         'CoordAxis', 'CoordAxisSign', 'UnitScaleFactor',
                                                         'OriginalUnitScaleFactor')}
        objs = find(root, b'Objects')
        lo = [1e9] * 3; hi = [-1e9] * 3
        models = {}
        geoms = {}
        for e in objs.elems:
            if e.id == b'Model':
                nm = e.props[1].split(b'\x00')[0].decode()
                p70 = find(e, b'Properties70')
                d = {}
                for p in p70.elems:
                    k = p.props[0].decode()
                    if k in ('Lcl Translation', 'Lcl Rotation', 'Lcl Scaling'):
                        d[k] = [round(float(x), 4) for x in p.props[4:7]]
                models[nm] = d
            if e.id == b'Geometry':
                vv = find(e, b'Vertices')
                geoms[e.props[0]] = vv.props[0]
        res['raw_models'] = len(models)
        conns = find(root, b'Connections')
        geo_to_model = {}
        model_ids = {}
        for e in objs.elems:
            if e.id == b'Model':
                model_ids[e.props[0]] = e.props[1].split(b'\x00')[0].decode()
        for c in conns.elems:
            if c.props[0] == b'OO' and c.props[1] in geoms and c.props[2] in model_ids:
                geo_to_model[c.props[1]] = model_ids[c.props[2]]
        rot_nonzero = [n for n, d in models.items() if any(abs(x) > 1e-3 for x in d.get('Lcl Rotation', [0, 0, 0]))]
        scl_nonone = [n for n, d in models.items() if any(abs(x - 1) > 1e-4 for x in d.get('Lcl Scaling', [1, 1, 1]))]
        for gid, arr in geoms.items():
            t = models.get(geo_to_model.get(gid, ''), {}).get('Lcl Translation', [0, 0, 0])
            for i in range(0, len(arr), 3):
                for k in range(3):
                    val = arr[i + k] + t[k]
                    lo[k] = min(lo[k], val); hi[k] = max(hi[k], val)
        res['raw_extent_fbx_space'] = dict(min=r3(lo), max=r3(hi), size=r3([hi[k] - lo[k] for k in range(3)]))
        res['raw_models_with_rotation'] = rot_nonzero
        res['raw_models_with_scale'] = scl_nonone
        res['raw_translation_sample'] = {n: models[n].get('Lcl Translation') for n in
                                         ('Fuselage', 'Rudder', 'Aileron_R', 'Fan_4', 'NoseGear', 'MainGear_BR_Bogie')
                                         if n in models}
    except Exception as ex:   # pragma: no cover
        res['raw_parse_error'] = repr(ex)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fbx_path, axis_forward='Z', axis_up='Y')
    res.update(reimport_summary(expected, 'fbx'))
    return res


def reimport_summary(expected, tag):
    res = {}
    obs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    lo, hi = world_bbox(obs)
    size = hi - lo
    res['reimport_objects'] = len(obs)
    res['reimport_bbox_blender_units'] = dict(min=r3(lo), max=r3(hi), size=r3(size))
    res['reimport_size_studs'] = dict(span_X=round(size.x, 2), length_Y=round(size.y, 2), height_Z=round(size.z, 2))
    res['reimport_size_m'] = {k: round(v * STUD_M, 3) for k, v in res['reimport_size_studs'].items()}
    tri_total = 0
    over = []
    for o in obs:
        n = sum(len(p.vertices) - 2 for p in o.data.polygons)
        tri_total += n
        if n > ROBLOX_TRI_LIMIT:
            over.append(o.name)
    res['reimport_triangles_total'] = tri_total
    res['reimport_objects_over_limit'] = over
    piv_err = 0.0
    for o in obs:
        if o.name in expected['pivots']:
            want = Vector(expected['pivots'][o.name])
            piv_err = max(piv_err, (o.matrix_world.translation - want).length)
    res['reimport_max_pivot_error_studs'] = round(piv_err, 5)
    res['reimport_missing_objects'] = sorted(set(expected['pivots']) - set(o.name for o in obs))
    pal255 = {tuple(int(round(c * 255)) for c in v): k for k, v in PAL.items()}
    no_col, off_pal, seen = [], set(), set()
    for o in obs:
        ca = o.data.color_attributes[0] if len(o.data.color_attributes) else None
        if ca is None:
            no_col.append(o.name); continue
        vals = set()
        for d in ca.data:
            vals.add(tuple(int(round(x * 255)) for x in d.color_srgb[:3]))
        for v in vals:
            hit = [k for c, k in pal255.items() if max(abs(c[i] - v[i]) for i in range(3)) <= 2]
            if hit:
                seen.add(hit[0])
            else:
                off_pal.add(v)
    res['reimport_objects_without_vertex_colors'] = no_col
    res['reimport_vertex_colors_matching_palette'] = sorted(seen)
    res['reimport_vertex_colors_off_palette'] = sorted(off_pal)[:10]
    return res


def verify_gltf(path, expected):
    """re-import the glTF; Blender's importer turns glTF Y-up back into Z-up, which reproduces the 180-degree
    turned export scene, so expected pivots are compared after the same turn."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    R = Matrix.Rotation(math.pi, 4, 'Z')
    exp = dict(pivots={k: list(R @ Vector(v)) for k, v in expected['pivots'].items()})
    res = reimport_summary(exp, 'gltf')
    # raw node translations straight from the JSON (what an importer reads)
    try:
        import base64
        js = json.load(open(path))
        nodes = {n.get('name'): n.get('translation', [0, 0, 0]) for n in js.get('nodes', [])}
        res['raw_node_translation_sample'] = {k: r3(nodes[k]) for k in ('Fuselage', 'Rudder', 'Fan_4', 'NoseGear') if k in nodes}
        res['raw_nodes'] = len(nodes)
        mins = []; maxs = []
        for nd in js.get('nodes', []):
            if 'mesh' not in nd:
                continue
            t = nd.get('translation', [0, 0, 0])
            for prim in js['meshes'][nd['mesh']]['primitives']:
                acc = js['accessors'][prim['attributes']['POSITION']]
                mins.append([acc['min'][k] + t[k] for k in range(3)]); maxs.append([acc['max'][k] + t[k] for k in range(3)])
        lo = np.min(np.array(mins), 0); hi = np.max(np.array(maxs), 0)
        res['raw_extent_gltf_space'] = dict(min=r3(lo), max=r3(hi), size=r3(hi - lo))
        res['has_COLOR_0'] = all('COLOR_0' in p['attributes'] for m in js['meshes'] for p in m['primitives'])
    except Exception as ex:
        res['raw_parse_error'] = repr(ex)
    return res


# ----------------------------------------------------------------------------------------
def main():
    t0 = time.time()
    build_all()
    scale_to_studs()
    obs = [o for o, _ in OBJECTS]
    lo, hi = world_bbox(obs)
    size = hi - lo
    objs_json = []
    total = 0
    problems = []
    pivots_blender = {}
    multi_shell = {}
    for ob, inf in OBJECTS:
        tris, nonman, vol, shells = mesh_stats(ob)
        total += tris
        if vol <= 0:
            problems.append(f'{ob.name}: signed volume {vol:.3f} <= 0 (inward normals?)')
        if tris > ROBLOX_TRI_LIMIT:
            problems.append(f'{ob.name}: {tris} tris > limit')
        if nonman:
            problems.append(f'{ob.name}: {nonman} non-manifold edges')
        if any(abs(r) > 1e-9 for r in ob.rotation_euler) or any(abs(s - 1) > 1e-9 for s in ob.scale):
            problems.append(f'{ob.name}: unapplied transform')
        blo, bhi = world_bbox([ob])
        piv_b = ob.location.copy()
        pivots_blender[ob.name] = list(piv_b)
        piv_r = blender_to_roblox(piv_b)
        e = dict(name=ob.name, role=inf.get('role', ''), triangles=tris, non_manifold_edges=nonman,
                 closed_shells=shells, material=inf['material'], vertex_colors=inf['colors'],
                 signed_volume_studs3=round(vol, 2), studio_fallback_color_rgb=dominant_colour(ob),
                 movable=inf.get('movable', False), can_collide=inf.get('can_collide', False),
                 pivot_studs_roblox=r3(piv_r), pivot_m_roblox=r3(piv_r * STUD_M),
                 pivot_aircraft_m=dict(station_from_nose=round(inf['pivot_A'][0], 3),
                                       lateral_stbd=round(inf['pivot_A'][1], 3), height=round(inf['pivot_A'][2], 3)),
                 bbox_size_studs_roblox=r3([bhi.x - blo.x, bhi.z - blo.z, bhi.y - blo.y]))
        if shells > 1:
            multi_shell[ob.name] = shells
        if 'hinge_axis_A' in inf:
            e['hinge_axis_roblox'] = r3(A_dir_to_roblox(Vector(inf['hinge_axis_A'])), 4)
            e['rotation_limits_deg'] = inf.get('limits_deg')
            e['positive_rotation'] = inf.get('positive', '')
            e['parent'] = inf.get('parent', 'Fuselage')
            if inf.get('retract_deg') is not None:
                e['retracted_deg'] = inf['retract_deg']
        if 'hinge_line_A' in inf:
            e['hinge_line_studs_roblox'] = [r3(blender_to_roblox(to_blender(Vector(p)) * K)) for p in inf['hinge_line_A']]
        if inf.get('note'):
            e['note'] = inf['note']
        objs_json.append(e)
    dims_studs = dict(length=round(size.y, 2), wingspan=round(size.x, 2), height=round(size.z, 2))
    dims_m = {k: round(v * STUD_M, 3) for k, v in dims_studs.items()}
    print(f'objects: {len(OBJECTS)}  triangles: {total}')
    for e in objs_json:
        print(f"   {e['name']:24s} {e['triangles']:6d}  shells {e['closed_shells']}")
    print('dims studs', dims_studs, 'dims m', dims_m)
    print('problems:', problems or 'none')
    motion = None
    if DO_MOTION:
        motion = motion_checks()
        print(json.dumps(motion, indent=1))
    fbx, obj, gltf = export_all()
    print('exported', fbx, obj, gltf)
    if DO_RENDER:
        do_renders()
    gear_groups = {}
    for gd in gear_defs():
        mem = []
        if gd['kind'] == 'body':
            mem.append(gd['name'] + '_Bogie')
        mem += [gd['name'] + ('_Wheels' if len(gd['axles']) == 1 else f'_Wheels{k + 1}') for k in range(len(gd['axles']))]
        gear_groups[gd['name']] = mem
    sp1, sp2, _ = cockpit_corners()
    manifest = dict(
        name=NAME, kind='airliner', reference='proportions of the Airbus A380-800 (generic model, no branding; '
                                              'developer documentation only - do not use this wording in game UI)',
        generated_by='model.py (bpy %s)' % bpy.app.version_string,
        units=dict(blender_unit='1 Roblox stud', stud_in_m=STUD_M, metres_to_studs=round(K, 6),
                   source='https://create.roblox.com/docs/physics/units (1 stud = 28 cm)'),
        axes=dict(roblox_model_space='X = right/starboard, Y = up, -Z = forward (nose); right-handed',
                  blender='X = port(left), Y = aft, Z = up (nose points to -Y)',
                  fbx_export='axis_forward=Z, axis_up=Y, bake_space_transform=True, apply_scale_options=FBX_SCALE_UNITS',
                  hinge_axes='unit vectors in Roblox model space; positive angle = right-hand rule about the axis'),
        joints=('Every movable object has "parent" (the part it is jointed to), pivot, hinge_axis_roblox and '
                'rotation_limits_deg. A child rotation is applied relative to its parent (Motor6D chain): '
                'wheels -> bogie -> leg -> Fuselage for the body gears, wheels -> leg -> Fuselage otherwise. '
                'Retracted pose = every object at its "retracted_deg" (legs +, body-gear bogies -90).'),
        origin='model origin = ground level (Y=0 at tyre contact), on the centreline, %.2f m (%.2f studs) aft of the '
               'nose = centroid of the 20 main-gear wheels; this is the Model pivot when importing with '
               '"Set Pivot to Scene Origin"' % (S0, S0 * K),
        dimensions_studs=dims_studs, dimensions_m=dims_m,
        reference_dimensions_m=dict(length=REF['length'], wingspan=REF['span'], height=REF['height'],
                                    fuselage_width=REF['fus_width'], fuselage_height=REF['fus_height']),
        triangles_total=total, roblox_triangle_limit_per_mesh=ROBLOX_TRI_LIMIT,
        max_triangles_single_mesh=max(o['triangles'] for o in objs_json),
        problems=problems,
        mesh_notes=dict(
            closed_shells_per_object=multi_shell,
            text=('Every object is closed (0 non-manifold edges) with outward normals. Fuselage is one shell: the '
                  'belly fairing is boolean-unioned into the tube. Objects listed in closed_shells_per_object are '
                  'built from several closed shells that may intersect each other inside the object (e.g. wing + '
                  'flap-track fairings, nacelle + core + pylon, gear cylinders, window panes, letters).')),
        objects=objs_json,
        groups=dict(
            Flap_L=['Flap_L_Inner', 'Flap_L_Outer'], Flap_R=['Flap_R_Inner', 'Flap_R_Outer'],
            Doors=[f'Door_{d[0]}{t}' for d in DOORS for t in 'LR'],
            Windows=['WindowStrip_Main_L', 'WindowStrip_Main_R', 'WindowStrip_Upper_L', 'WindowStrip_Upper_R',
                     'WindowStrip_Cockpit'],
            Gear=gear_groups,
            Engines={f'Engine_{n}': f'Fan_{n}' for n, *_ in ENGINES}),
        colors_srgb={k: [round(c, 3) for c in v] for k, v in PAL.items()},
        export=dict(
            fbx=dict(file=NAME + '.fbx', use='Roblox (primary)',
                     apply_scale_options='FBX_SCALE_UNITS (Roblox docs: "FBX Unit Scale")',
                     global_scale=1.0, axis_forward='Z', axis_up='Y', bake_space_transform=True,
                     use_triangles=True, mesh_smooth_type='FACE', colors_type='SRGB (face-corner vertex colours)',
                     add_leaf_bones=False, bake_anim=False, path_mode='COPY', embed_textures=True,
                     note='1 Blender unit = 1 stud; raw FBX vertex numbers are studs'),
            gltf=dict(file=os.path.basename(gltf['path']), format=gltf['format'],
                      use='alternative for Roblox (Importer lists .gltf with multiple meshes, hierarchy, vertex colours); '
                          'not tested in Studio',
                      units='1 glTF unit = 1 stud (Importer Scale Unit = Studs)',
                      axes='raw glTF coordinates = FBX layout: X right, Y up, nose at -Z (scene turned 180 deg about '
                           'the vertical before export). If Studio shows the nose at +Z, set World Forward = Back.',
                      vertex_colors='COLOR_0 (active colour attribute)'),
            obj=dict(file=NAME + '.obj', mtl=NAME + '.mtl', use='DCC interchange only - NOT for Roblox',
                     forward_axis='Z', up_axis='Y', global_scale=1.0, triangulated=True, vertex_colors=False,
                     note='OBJ stores no object transforms (every hinge/axle pivot is lost) and no vertex colours here '
                          '(one Kd colour per object). The Roblox Importer lists multiple meshes / hierarchies / '
                          'vertex colours only for .fbx and .gltf; merged, the OBJ would exceed 20,000 triangles.')),
        roblox_import=dict(
            importer='Studio File > Import 3D (Importer)', scale_unit='Studs', set_pivot_to_scene_origin=True,
            use_imported_pivot=True, merge_meshes=False, anchored=False, ignore_vertex_colors=False,
            target_path='ReplicatedStorage/VehicleAssets/' + NAME,
            after_import='set every MeshPart.Color = (255,255,255): Roblox multiplies vertex colours with '
                         'MeshPart.Color (default Medium Stone Grey)',
            can_collide=[o['name'] for o in objs_json if o['can_collide']]),
        cockpit_panes=dict(front_pane_corners_b_z_m=WS_FRONT, side_pane_corners_s_z_m=[sp1, sp2],
                           shape_check=pane_angles()),
        build_seconds=round(time.time() - t0, 1),
    )
    if motion is not None:
        manifest['motion_checks'] = motion
    if DO_VERIFY:
        expected = dict(pivots=pivots_blender)
        ver = verify_fbx(fbx, expected)
        if gltf['format']:
            ver['gltf'] = verify_gltf(gltf['path'], expected)
        manifest['verification'] = ver
        print(json.dumps(ver, indent=1))
    with open(os.path.join(HERE, 'manifest.json'), 'w') as fh:
        json.dump(manifest, fh, indent=2)
    print('done in %.1fs' % (time.time() - t0))


if __name__ == '__main__':
    main()
