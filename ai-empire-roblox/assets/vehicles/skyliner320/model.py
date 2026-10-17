#!/usr/bin/env python3
"""
Skyliner320 -- generic narrow-body twin-jet airliner for the Roblox game "AI Empire".
Proportions: Airbus A320neo (sources in README.md).  No brand names / logos / real liveries.

Run headless (Blender as Python module, bpy 5.0.1):
    python3 model.py              # build + export FBX/OBJ + manifest + renders + re-import check
    python3 model.py --no-render  # skip the Cycles renders

Conventions
-----------
* Construction is done in metres in an "aircraft frame":
      s = distance aft of the nose tip (m), b = lateral, positive to STARBOARD (pilot's right),
      z = height above the ground plane (tyre contact).
* Blender frame (what gets exported):  X = -b, Y = s - L/2, Z = z
      -> nose points to Blender -Y (Blender "front" view), port wing on Blender +X.
* At the end every mesh is scaled by 1/0.28 (1 stud = 0.28 m, Roblox "Units" page),
  so 1 Blender unit = 1 stud.  FBX export as documented in the Roblox Blender guide: Forward = Z, Up = Y,
  Apply Scalings = FBX Unit Scale, Path Mode = Copy + Embed Textures; additionally "Apply Transform"
  (bake_space_transform) so every FBX node carries rotation (0,0,0) / scale 1 and the vertex data is Y-up.
* Expected Roblox frame (importer World Forward = Front, World Up = Top):
      X = b (starboard), Y = z (up), Z = s - L/2 (aft)  ->  nose = -Z = Model LookVector.
* Model origin (0,0,0) = ground level, on the centreline, at the longitudinal midpoint
  (18.785 m behind the nose).
"""
import bpy, bmesh, math, json, os, sys, time
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

OUT = os.path.dirname(os.path.abspath(__file__))
NAME = "Skyliner320"
STUD_M = 0.28                       # metres per stud (create.roblox.com/docs/physics/units)
S2 = 1.0 / STUD_M                   # studs per metre
LEN = 37.57                         # overall length (Airbus)
HALF = LEN / 2.0
DO_RENDER = "--no-render" not in sys.argv
rad = math.radians

# ----------------------------------------------------------------------------------------------
# scene reset
# ----------------------------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
SCENE = bpy.context.scene
SCENE.unit_settings.system = 'NONE'        # Roblox Blender guide: Unit System = None
SCENE.unit_settings.scale_length = 1.0
COLL = SCENE.collection


def P(s, b, z):
    """aircraft frame (m) -> Blender (m)"""
    return Vector((-b, s - HALF, z))


def Pv(v):
    return P(v[0], v[1], v[2])


def D(ds, db, dz):
    """aircraft-frame direction -> Blender direction"""
    return Vector((-db, ds, dz))


def to_roblox(s, b, z):
    """aircraft frame (m) -> expected Roblox model space (studs)"""
    return [round(b * S2, 4), round(z * S2, 4), round((s - HALF) * S2, 4)]


def dir_roblox(ds, db, dz):
    v = Vector((db, dz, ds)).normalized()
    return [round(v.x, 5), round(v.y, 5), round(v.z, 5)]


# ----------------------------------------------------------------------------------------------
# materials (single base colour each; also baked into vertex colours for Roblox)
# ----------------------------------------------------------------------------------------------
MATDEF = {
    #  name               sRGB hex   rough metal
    "Livery_White":     ("F3F5F8", 0.35, 0.0),
    "Belly_Grey":       ("B7BDC5", 0.45, 0.0),
    "Accent_Blue":      ("1C3F94", 0.35, 0.0),
    "Accent_Gold":      ("E2A72E", 0.30, 0.2),
    "Wing_Grey":        ("C4C9D0", 0.45, 0.0),
    "Window_Dark":      ("16202E", 0.10, 0.0),
    "Cockpit_Glass":    ("0F1722", 0.05, 0.0),
    "Door_Seam":        ("8E959E", 0.50, 0.0),
    "Metal_Lip":        ("C9CED6", 0.25, 0.8),
    "Engine_Dark":      ("24272D", 0.60, 0.1),
    "Exhaust_Metal":    ("7D838B", 0.40, 0.6),
    "Gear_Grey":        ("8B9097", 0.45, 0.3),
    "Chrome":           ("D5D9DE", 0.15, 0.9),
    "Tire_Black":       ("1B1B1D", 0.80, 0.0),
    "Hub_Silver":       ("A9AEB5", 0.35, 0.6),
}


def srgb(hexs):
    return tuple(int(hexs[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


MAT = {}
for mname, (hx, rough, metal) in MATDEF.items():
    m = bpy.data.materials.new(mname)
    c = srgb(hx)
    m.diffuse_color = (lin(c[0]), lin(c[1]), lin(c[2]), 1.0)
    if m.node_tree is None:
        m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (lin(c[0]), lin(c[1]), lin(c[2]), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.roughness = rough
    m.metallic = metal
    MAT[mname] = m

# ----------------------------------------------------------------------------------------------
# small math helpers
# ----------------------------------------------------------------------------------------------
class Curve1D:
    """monotone piecewise-cubic interpolation (Fritsch-Carlson), clamped ends"""

    def __init__(self, pts):
        pts = sorted(pts)
        self.x = [p[0] for p in pts]
        self.y = [p[1] for p in pts]
        n = len(pts)
        d = [(self.y[i + 1] - self.y[i]) / (self.x[i + 1] - self.x[i]) for i in range(n - 1)]
        m = [0.0] * n
        m[0], m[-1] = d[0], d[-1]
        for i in range(1, n - 1):
            m[i] = 0.0 if d[i - 1] * d[i] <= 0 else (d[i - 1] + d[i]) / 2.0
        for i in range(n - 1):
            if d[i] == 0:
                m[i] = m[i + 1] = 0.0
                continue
            a, b = m[i] / d[i], m[i + 1] / d[i]
            h = a * a + b * b
            if h > 9:
                t = 3 / math.sqrt(h)
                m[i], m[i + 1] = t * a * d[i], t * b * d[i]
        self.m = m

    def __call__(self, x):
        X, Y, M = self.x, self.y, self.m
        if x <= X[0]:
            return Y[0]
        if x >= X[-1]:
            return Y[-1]
        lo, hi = 0, len(X) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if X[mid] <= x:
                lo = mid
            else:
                hi = mid
        h = X[hi] - X[lo]
        t = (x - X[lo]) / h
        h00 = 2 * t ** 3 - 3 * t ** 2 + 1
        h10 = t ** 3 - 2 * t ** 2 + t
        h01 = -2 * t ** 3 + 3 * t ** 2
        h11 = t ** 3 - t ** 2
        return h00 * Y[lo] + h10 * h * M[lo] + h01 * Y[hi] + h11 * h * M[hi]


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


# ----------------------------------------------------------------------------------------------
# generic mesh builders (all work in Blender metres on a bmesh)
# ----------------------------------------------------------------------------------------------
def face(bm, vs, mat):
    try:
        f = bm.faces.new(vs)
    except ValueError:
        return None
    f.material_index = mat
    return f


def cap(bm, ring, mat):
    f = face(bm, ring, mat)
    if f is not None and len(ring) > 4:
        bmesh.ops.triangulate(bm, faces=[f], quad_method='BEAUTY', ngon_method='BEAUTY')
    return f


def loft(bm, sections, mat=0, mat_fn=None, cap0=True, cap1=True, cap_mat=None):
    """sections: list of rings (list of Blender Vectors, equal length, closed loops)."""
    rings = [[bm.verts.new(p) for p in sec] for sec in sections]
    n = len(rings[0])
    for i in range(len(rings) - 1):
        A, B = rings[i], rings[i + 1]
        for j in range(n):
            j2 = (j + 1) % n
            face(bm, (A[j], A[j2], B[j2], B[j]), mat if mat_fn is None else mat_fn(i, j))
    cm = (mat, mat) if cap_mat is None else (cap_mat if isinstance(cap_mat, tuple) else (cap_mat, cap_mat))
    if cap0:
        cap(bm, rings[0], cm[0])
    if cap1:
        cap(bm, rings[-1], cm[1])
    return rings


def frame_from_axis(d):
    d = d.normalized()
    tmp = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = d.cross(tmp).normalized()
    v = d.cross(u).normalized()
    return u, v


def revolve(bm, profile, origin, axis, nseg, phase=0.0):
    """profile: list of (a, r, mat) with a along axis, r radius; r==0 -> pole.
    mat of point i is used for the band between point i and i+1."""
    axis = axis.normalized()
    u, v = frame_from_axis(axis)
    rings = []
    for (a, r, _m) in profile:
        c = origin + axis * a
        if r < 1e-7:
            rings.append([bm.verts.new(c)])
        else:
            rings.append([bm.verts.new(c + (u * math.cos(t) + v * math.sin(t)) * r)
                          for t in [phase + 2 * math.pi * k / nseg for k in range(nseg)]])
    for i in range(len(rings) - 1):
        A, B, m = rings[i], rings[i + 1], profile[i][2]
        if len(A) == 1 and len(B) == 1:
            continue
        for k in range(nseg):
            k2 = (k + 1) % nseg
            if len(A) == 1:
                face(bm, (A[0], B[k], B[k2]), m)
            elif len(B) == 1:
                face(bm, (A[k], A[k2], B[0]), m)
            else:
                face(bm, (A[k], A[k2], B[k2], B[k]), m)
    return rings


def cylinder(bm, p0, p1, r, nseg, mat, r1=None):
    d = (p1 - p0)
    L = d.length
    prof = [(0.0, 0.0, mat), (0.0, r, mat), (L, r if r1 is None else r1, mat), (L, 0.0, mat)]
    revolve(bm, prof, p0, d, nseg)


def box(bm, center, hx, hy, hz, mat, rot=None):
    vs = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                p = Vector((sx * hx, sy * hy, sz * hz))
                if rot is not None:
                    p = rot @ p
                vs.append(bm.verts.new(center + p))
    idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for q in idx:
        face(bm, [vs[i] for i in q], mat)


def solid_from_surface(bm, pts, normals, tris_or_quads, thick, mat_top, mat_side=None, top_mats=None):
    """Builds a closed thin shell from a surface patch: top = pts, bottom = pts - n*thick."""
    top = [bm.verts.new(p) for p in pts]
    bot = [bm.verts.new(p - n * thick) for p, n in zip(pts, normals)]
    edges = {}
    for fi, f in enumerate(tris_or_quads):
        mt = mat_top if top_mats is None else top_mats[fi]
        face(bm, [top[i] for i in f], mt)
        face(bm, [bot[i] for i in reversed(f)], mt)
        for k in range(len(f)):
            a, b = f[k], f[(k + 1) % len(f)]
            key = (min(a, b), max(a, b))
            edges.setdefault(key, []).append((a, b))
    ms = mat_top if mat_side is None else mat_side
    for key, lst in edges.items():
        if len(lst) == 1:
            a, b = lst[0]
            face(bm, (top[b], top[a], bot[a], bot[b]), ms)


# ----------------------------------------------------------------------------------------------
# object registry
# ----------------------------------------------------------------------------------------------
OBJ_META = {}


def finish(name, bm, pivot_af, matnames, smooth_deg=35.0, meta=None):
    """bm in Blender metres. pivot given in aircraft frame (s,b,z)."""
    ngons = [f for f in bm.faces if len(f.verts) > 4]
    if ngons:
        bmesh.ops.triangulate(bm, faces=ngons, quad_method='BEAUTY', ngon_method='BEAUTY')
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-7)
    ngons = [f for f in bm.faces if len(f.verts) > 4]
    if ngons:
        bmesh.ops.triangulate(bm, faces=ngons, quad_method='BEAUTY', ngon_method='BEAUTY')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    piv = Pv(pivot_af)
    me.transform(Matrix.Translation(-piv))
    for mn in matnames:
        me.materials.append(MAT[mn])
    ob = bpy.data.objects.new(name, me)
    ob.location = piv
    COLL.objects.link(ob)
    me.shade_smooth()
    me.set_sharp_from_angle(angle=rad(smooth_deg))
    # vertex colours (face corner, sRGB bytes) = material base colour -> Roblox shows zones
    ca = me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
    cols = [srgb(MATDEF[mn][0]) for mn in matnames]
    for poly in me.polygons:
        c = cols[poly.material_index] if poly.material_index < len(cols) else (1, 1, 1)
        for li in poly.loop_indices:
            ca.data[li].color_srgb = (c[0], c[1], c[2], 1.0)
    me.color_attributes.active_color = ca
    # simple planar UVs (no textures are used; present so importers never complain)
    uvl = me.uv_layers.new(name="UVMap")
    xs = [v.co.x for v in me.vertices] or [0]
    zs = [v.co.z for v in me.vertices] or [0]
    ys = [v.co.y for v in me.vertices] or [0]
    sx = max(1e-6, max(xs) - min(xs)); sy = max(1e-6, max(ys) - min(ys)); sz = max(1e-6, max(zs) - min(zs))
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uvl.data[li].uv = ((co.y - min(ys)) / sy, (co.z - min(zs)) / sz)
    me.update()
    OBJ_META[name] = dict(meta or {})
    OBJ_META[name]["pivot_af"] = list(pivot_af)
    OBJ_META[name]["materials"] = list(matnames)
    return ob


# ----------------------------------------------------------------------------------------------
# 1) FUSELAGE  (profiles traced from Airbus A320 AC, fig. 2-2-0-991-009, scaled to 37.57 m)
# ----------------------------------------------------------------------------------------------
TOP = Curve1D([(0.0, 3.10), (0.04, 3.32), (0.10, 3.44), (0.18, 3.56), (0.28, 3.67), (0.40, 3.79),
               (0.55, 3.91), (0.70, 3.99), (0.85, 4.05), (1.0, 4.11), (1.15, 4.17), (1.35, 4.27),
               (1.65, 4.60), (2.0, 4.93), (2.5, 5.21), (3.0, 5.42), (3.5, 5.58), (4.0, 5.70),
               (4.5, 5.79), (5.0, 5.85), (6.0, 5.91), (7.0, 5.94), (29.0, 5.94), (31.0, 5.92),
               (33.0, 5.89), (34.0, 5.86), (35.0, 5.80), (36.0, 5.68), (36.5, 5.58), (37.0, 5.45),
               (37.57, 5.27)])
BOT = Curve1D([(0.0, 3.10), (0.04, 2.90), (0.10, 2.80), (0.18, 2.71), (0.28, 2.63), (0.40, 2.54),
               (0.55, 2.46), (0.70, 2.39), (1.0, 2.25), (1.5, 2.09), (2.0, 1.99), (2.5, 1.93),
               (3.0, 1.88), (3.5, 1.84), (4.0, 1.82), (5.0, 1.80), (24.5, 1.80), (25.0, 1.82),
               (26.0, 1.93), (27.0, 2.06), (28.0, 2.21), (29.0, 2.41), (30.0, 2.65), (31.0, 2.87),
               (32.0, 3.09), (33.0, 3.35), (34.0, 3.62), (35.0, 3.90), (36.0, 4.18), (37.0, 4.48),
               (37.57, 4.75)])
HW = Curve1D([(0.0, 0.0), (0.04, 0.20), (0.10, 0.31), (0.18, 0.42), (0.28, 0.52), (0.40, 0.62),
              (0.55, 0.73), (0.70, 0.83), (1.0, 1.00), (1.5, 1.22), (2.0, 1.40), (2.5, 1.55),
              (3.0, 1.67), (3.5, 1.79), (4.0, 1.87), (4.5, 1.93), (5.0, 1.96), (6.0, 1.975),
              (28.0, 1.975), (29.0, 1.88), (30.0, 1.72), (31.0, 1.55), (32.0, 1.38), (33.0, 1.21),
              (34.0, 1.05), (35.0, 0.90), (36.0, 0.74), (37.0, 0.47), (37.57, 0.26)])


def fairing(s):
    """belly (wing-to-body) fairing weight"""
    return smoothstep(10.0, 12.2, s) * (1.0 - smoothstep(20.6, 22.9, s))


def fus_section(s):
    top, bot, w = TOP(s), BOT(s), HW(s)
    zc = 0.5 * (top + bot)
    h = 0.5 * (top - bot)
    return zc, h, w


def fus_point(s, phi, side=1):
    """phi: section parameter (rad), 0 = widest line, +pi/2 = crown, -pi/2 = keel; side +1 stbd/-1 port"""
    zc, h, w = fus_section(s)
    c, sn = math.cos(phi), math.sin(phi)
    x = w * c
    z = zc + h * sn
    if sn < 0:
        f = fairing(s)
        x *= 1.0 + f * 0.10 * math.sin(2 * phi) ** 2
        z -= f * 0.07 * abs(sn) ** 4
    return Vector((s, side * x, z))


def fus_normal(s, phi, side=1):
    zc, h, w = fus_section(s)
    n = Vector((0.0, side * math.cos(phi) / max(w, 1e-3), math.sin(phi) / max(h, 1e-3)))
    return n.normalized()


# livery bands (section parameter, degrees, in the constant cabin section)
def _phi_for_z(z, zc=3.87, h=2.07):
    return math.degrees(math.asin(max(-1, min(1, (z - zc) / h))))


PHI_GOLD = (_phi_for_z(3.60), _phi_for_z(3.67))
PHI_BLUE = (_phi_for_z(3.71), _phi_for_z(3.99))
PHI_BELLY = -58.0

base = [i * 360.0 / 48 for i in range(48)]
extra = []
for a in (PHI_GOLD[0], PHI_GOLD[1], PHI_BLUE[0], PHI_BLUE[1], PHI_BELLY):
    extra += [a % 360.0, (180.0 - a) % 360.0]
ring_deg = sorted(set([round(a, 4) for a in extra] +
                      [b0 for b0 in base if min(abs(((b0 - e + 180) % 360) - 180) for e in extra) > 2.0]))

STATIONS = [0.04, 0.10, 0.18, 0.28, 0.40, 0.55, 0.70, 0.85, 1.0, 1.15, 1.30, 1.42, 1.55, 1.70, 1.85,
            2.0, 2.2, 2.4, 2.6, 2.8, 3.0, 3.3, 3.6, 3.9, 4.2, 4.6, 5.0, 5.5, 6.0, 6.6, 7.4, 8.4, 9.4,
            10.2, 11.0, 11.6, 12.2, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 20.8, 21.5, 22.2,
            22.9, 23.6, 24.4, 25.2, 26.0, 26.8, 27.6, 28.4, 29.2, 30.0, 30.8, 31.6, 32.4, 33.2, 34.0,
            34.8, 35.5, 36.1, 36.6, 37.0, 37.3, 37.57]


def side_phi(theta_deg):
    """ring angle (0 = stbd widest, 90 = crown) -> (side, phi_deg in [-90,90])"""
    t = theta_deg % 360.0
    c = math.cos(rad(t))
    if c >= -1e-9:
        phi = t if t <= 90 else t - 360.0
        return 1, phi
    return -1, 180.0 - t


def ring_point(s, theta_deg):
    side, phi = side_phi(theta_deg)
    if abs(math.cos(rad(theta_deg))) < 1e-9:     # crown / keel exactly
        side = 1
    return fus_point(s, rad(phi), side)


def fus_zone(s, theta_mid):
    side, phi = side_phi(theta_mid)
    if 2.8 <= s <= 37.3 and PHI_BLUE[0] <= phi <= PHI_BLUE[1]:
        return 2      # blue
    if 3.6 <= s <= 37.3 and PHI_GOLD[0] <= phi <= PHI_GOLD[1]:
        return 3      # gold
    if 2.6 <= s <= 32.4 and phi < PHI_BELLY:
        return 1      # belly grey
    return 0          # white


def build_fuselage():
    bm = bmesh.new()
    nose = bm.verts.new(P(0.0, 0.0, TOP(0.0)))
    rings = []
    for s in STATIONS:
        rings.append([bm.verts.new(Pv(ring_point(s, t))) for t in ring_deg])
    n = len(ring_deg)
    th_mid = [((ring_deg[j] + ((ring_deg[(j + 1) % n] + (360 if j == n - 1 else 0)))) / 2.0) for j in range(n)]
    for j in range(n):
        face(bm, (nose, rings[0][(j + 1) % n], rings[0][j]), 0)
    for i in range(len(rings) - 1):
        smid = 0.5 * (STATIONS[i] + STATIONS[i + 1])
        for j in range(n):
            j2 = (j + 1) % n
            face(bm, (rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]), fus_zone(smid, th_mid[j]))
    # APU exhaust at the tail tip: short inset lip + dark cavity
    s_end = STATIONS[-1]
    zc, h, w = fus_section(s_end)
    inset = [bm.verts.new(P(s_end - 0.01, side_b * 0.78, zc + (z0 - zc) * 0.78))
             for (side_b, z0) in [(v.co.x * -1, v.co.z) for v in rings[-1]]]
    for j in range(n):
        j2 = (j + 1) % n
        face(bm, (rings[-1][j], rings[-1][j2], inset[j2], inset[j]), 4)
    pole = bm.verts.new(P(s_end - 0.25, 0.0, zc))
    for j in range(n):
        face(bm, (inset[j], inset[(j + 1) % n], pole), 5)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bvh = BVHTree.FromBMesh(bm)
    ob = finish("Fuselage", bm, (HALF, 0.0, 0.0),
                ["Livery_White", "Belly_Grey", "Accent_Blue", "Accent_Gold", "Exhaust_Metal", "Engine_Dark"],
                smooth_deg=50.0,
                meta=dict(kind="static", can_collide=True,
                          note="main hull incl. belly fairing, livery bands as vertex colours"))
    return bvh


FUS_BVH = build_fuselage()


def project_fus(s, phi, side, offset):
    """analytic point -> exact point on the fuselage mesh + outward offset. returns (Blender pos, normal)"""
    p = fus_point(s, phi, side)
    n = fus_normal(s, phi, side)
    origin = Pv(p + n * 0.6)
    direction = D(-n.x, -n.y, -n.z)
    loc, nrm, _i, _d = FUS_BVH.ray_cast(origin, direction, 2.0)
    if loc is None:
        bn = D(n.x, n.y, n.z)
        return Pv(p) + bn * offset, bn
    return loc + nrm * offset, nrm


def phi_at(s, z):
    zc, h, w = fus_section(s)
    return math.asin(max(-0.995, min(0.995, (z - zc) / h)))


# ----------------------------------------------------------------------------------------------
# 2) WINDOWS, COCKPIT WINDOWS, DOORS, TITLES  (decal shells projected onto the hull)
# ----------------------------------------------------------------------------------------------
def rounded_rect(wd, ht, rr, n_corner=2):
    pts = []
    corners = [(wd / 2 - rr, ht / 2 - rr, 0), (-wd / 2 + rr, ht / 2 - rr, 90),
               (-wd / 2 + rr, -ht / 2 + rr, 180), (wd / 2 - rr, -ht / 2 + rr, 270)]
    for cx, cy, a0 in corners:
        for k in range(n_corner + 1):
            a = rad(a0 + 90.0 * k / n_corner)
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def polar_decal(bm, sc, zc, outline, side, rings, offset, thick, mats_by_ring, mat_side):
    """outline: (du, dz) in metres relative to centre; du positive = aft. rings: list of scale factors
    (ascending, last = 1.0). mats_by_ring[k] = material for band between ring k-1 and k (k=0 centre fan)."""
    pts, nrms = [], []
    pc, nc = project_fus(sc, phi_at(sc, zc), side, offset)
    pts.append(pc); nrms.append(nc)
    for sf in rings:
        for (du, dz) in outline:
            s = sc + du * sf
            z = zc + dz * sf
            p, n = project_fus(s, phi_at(s, z), side, offset)
            pts.append(p); nrms.append(n)
    m = len(outline)
    faces, fm = [], []
    for j in range(m):
        faces.append((0, 1 + j, 1 + (j + 1) % m)); fm.append(mats_by_ring[0])
    for k in range(1, len(rings)):
        a0, b0 = 1 + (k - 1) * m, 1 + k * m
        for j in range(m):
            j2 = (j + 1) % m
            faces.append((a0 + j, b0 + j, b0 + j2, a0 + j2)); fm.append(mats_by_ring[k])
    solid_from_surface(bm, pts, nrms, faces, thick, None, mat_side, top_mats=fm)


def quad_decal(bm, corners_sz, side, nu, nv, offset, thick, mat):
    """bilinear patch; corners (s,z) in order: c00 (front-bottom), c10 (aft-bottom), c11 (aft-top), c01 (front-top)"""
    cs = []
    for c in corners_sz:
        if len(c) == 3:                       # (s, None, phi_deg)
            cs.append((c[0], rad(c[2])))
        else:
            cs.append((c[0], phi_at(c[0], c[1])))
    (s00, f00), (s10, f10), (s11, f11), (s01, f01) = cs
    pts, nrms = [], []
    for jv in range(nv + 1):
        v = jv / nv
        for iu in range(nu + 1):
            u = iu / nu
            s = (1 - u) * (1 - v) * s00 + u * (1 - v) * s10 + u * v * s11 + (1 - u) * v * s01
            ph = (1 - u) * (1 - v) * f00 + u * (1 - v) * f10 + u * v * f11 + (1 - u) * v * f01
            p, n = project_fus(s, ph, side, offset)
            pts.append(p); nrms.append(n)
    faces = []
    for jv in range(nv):
        for iu in range(nu):
            a = jv * (nu + 1) + iu
            faces.append((a, a + 1, a + nu + 2, a + nu + 1))
    solid_from_surface(bm, pts, nrms, faces, thick, mat)


# --- cabin windows: pitch 0.533 m (traced from AC side view), 0.23 x 0.33 m, centre z = 4.60 m
WIN_S = []
s = 6.19
while s <= 27.80:
    WIN_S.append(round(s, 3))
    s += 0.5334
WIN_OUTLINE = rounded_rect(0.23, 0.33, 0.085, n_corner=2)
for side, nm in ((-1, "WindowStrip_L"), (1, "WindowStrip_R")):
    bm = bmesh.new()
    for sc in WIN_S:
        polar_decal(bm, sc, 4.60, WIN_OUTLINE, side, [1.0], 0.022, 0.012, [0], 0)
    finish(nm, bm, (16.9, side * 1.98, 4.60), ["Window_Dark"], smooth_deg=30.0,
           meta=dict(kind="static", can_collide=False,
                     note="%d cabin windows (pitch 0.533 m) on the %s side" % (len(WIN_S), "port" if side < 0 else "starboard")))

# --- cockpit windows (6 panes), corners traced from the AC side view (s, z in metres)
bm = bmesh.new()
for side in (-1, 1):
    # front windscreen pane (centre post at the crown, side post towards the first side window)
    quad_decal(bm, [(1.42, None, 85.0), (1.86, 4.28), (2.22, 4.73), (1.84, None, 85.5)], side, 5, 4, 0.02, 0.012, 0)
    # side window 1 (slanted front edge)
    quad_decal(bm, [(1.93, 4.27), (2.60, 4.19), (2.60, 4.73), (2.28, 4.73)], side, 4, 3, 0.02, 0.012, 0)
    # side window 2 (sliding / DV window)
    quad_decal(bm, [(2.67, 4.19), (3.27, 4.20), (3.33, 4.70), (2.67, 4.73)], side, 4, 3, 0.02, 0.012, 0)
finish("CockpitWindows", bm, (2.3, 0.0, 4.5), ["Cockpit_Glass"], smooth_deg=30.0,
       meta=dict(kind="static", can_collide=False, note="2 windscreen + 4 side panes"))


# --- passenger doors (0.81 x 1.85 m, sill heights from AC table 2-3-0: D1 3.48 m, D3 3.70 m)
DOORS = [("Door_1L", 5.04, 3.48, -1), ("Door_1R", 5.04, 3.48, 1),
         ("Door_2L", 29.53, 3.70, -1), ("Door_2R", 29.53, 3.70, 1)]
DOOR_W, DOOR_H = 0.81, 1.85
ZONE2DOORMAT = {0: 0, 1: 3, 2: 4, 3: 5}


def door_grid(bm, sc, sill, side, offset=0.026, thick=0.02, seam=0.035, corner_r=0.15):
    """door panel as a structured (s, phi) grid; outer ring of cells = seam colour, inner cells carry the
    hull livery (stripe continues across the door)."""
    s0, s1 = sc - DOOR_W / 2, sc + DOOR_W / 2
    cols = [s0, s0 + seam] + [lerp(s0 + seam, s1 - seam, k / 6.0) for k in range(1, 6)] + [s1 - seam, s1]
    ztop = sill + DOOR_H
    zrows = [sill, sill + seam] + [lerp(sill + seam, ztop - seam, k / 16.0) for k in range(1, 16)] + [ztop - seam, ztop]
    band = [rad(a) for a in (PHI_GOLD[0], PHI_GOLD[1], PHI_BLUE[0], PHI_BLUE[1])]
    zc_band = [fus_section(sc)[0] + fus_section(sc)[1] * math.sin(a) for a in band]
    rows = [('z', z) for z in zrows if (z in (sill, sill + seam, ztop - seam, ztop)) or
            min(abs(z - zb) for zb in zc_band) > 0.07]
    rows += [('phi', a) for a, zb in zip(band, zc_band) if sill + seam + 0.02 < zb < ztop - seam - 0.02]
    rows.sort(key=lambda r: r[1] if r[0] == 'z' else fus_section(sc)[0] + fus_section(sc)[1] * math.sin(r[1]))
    nu, nv = len(cols), len(rows)
    grid_phi = []
    for s in cols:
        col = [phi_at(s, r[1]) if r[0] == 'z' else r[1] for r in rows]
        for k in range(1, nv):                       # keep strictly monotonic
            if col[k] <= col[k - 1]:
                col[k] = col[k - 1] + 1e-4
        grid_phi.append(col)
    pts, nrms = [], []
    cut = corner_r * (1 - math.cos(rad(45)))
    for jv in range(nv):
        for iu in range(nu):
            s = cols[iu]
            ph = grid_phi[iu][jv]
            if iu in (0, nu - 1) and jv in (0, nv - 1):      # round the four corners
                s += cut if iu == 0 else -cut
                zc_, h_, _w = fus_section(s)
                z = zc_ + h_ * math.sin(ph) + (cut if jv == 0 else -cut)
                ph = phi_at(s, z)
            p, n = project_fus(s, ph, side, offset)
            pts.append(p); nrms.append(n)
    faces, fm = [], []
    for jv in range(nv - 1):
        for iu in range(nu - 1):
            a = jv * nu + iu
            faces.append((a, a + 1, a + nu + 1, a + nu))
            if iu in (0, nu - 2) or jv in (0, nv - 2):
                fm.append(1)
            else:
                smid = 0.5 * (cols[iu] + cols[iu + 1])
                pmid = math.degrees(0.25 * (grid_phi[iu][jv] + grid_phi[iu + 1][jv] + grid_phi[iu][jv + 1] + grid_phi[iu + 1][jv + 1]))
                theta = pmid if side > 0 else 180.0 - pmid
                fm.append(ZONE2DOORMAT[fus_zone(smid, theta)])
    solid_from_surface(bm, pts, nrms, faces, thick, None, 1, top_mats=fm)


for nm, sc, sill, side in DOORS:
    bm = bmesh.new()
    zc = sill + DOOR_H / 2
    door_grid(bm, sc, sill, side)
    # small dark viewport window in the door
    polar_decal(bm, sc, zc + 0.42, rounded_rect(0.20, 0.26, 0.07, 2), side, [1.0], 0.05, 0.012, [2], 2)
    s_front = sc - DOOR_W / 2
    pv = project_fus(s_front, phi_at(s_front, zc), side, 0.0)[0]
    piv_af = (pv.y + HALF, -pv.x, pv.z)
    finish(nm, bm, piv_af, ["Livery_White", "Door_Seam", "Window_Dark", "Belly_Grey", "Accent_Blue", "Accent_Gold"],
           smooth_deg=40.0,
           meta=dict(kind="door", can_collide=False))

# --- titles  "AI EMPIRE AIR" (generic fictional airline) + "AI" tail mark
# A real bold sans-serif outline (DejaVu Sans Bold, free licence) is used when present; Blender's built-in
# font is the fallback, thickened with a small outline offset (the offset can self-intersect at sharp
# inner corners such as the notch of the 'M', so it is avoided whenever a bold font is available).
TITLE_FONTS = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
               "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]
_FONT = None
for _fp in TITLE_FONTS:
    if os.path.exists(_fp):
        try:
            _FONT = bpy.data.fonts.load(_fp)
            break
        except Exception:
            _FONT = None


def text_mesh(body, size, res=2, bold=0.0, maxlen=None):
    cu = bpy.data.curves.new("tmp_text", 'FONT')
    cu.body = body
    cu.size = size
    cu.resolution_u = res
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    cu.shear = 0.18
    if _FONT is not None:
        cu.font = _FONT
        cu.size = size * 0.92          # DejaVu Bold runs slightly larger/wider than the built-in font
    else:
        cu.offset = bold
    ob = bpy.data.objects.new("tmp_text", cu)
    COLL.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    verts = [(v.co.x, v.co.y) for v in me.vertices]
    faces = [tuple(p.vertices) for p in me.polygons]
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    bpy.data.meshes.remove(me)
    return densify2d(verts, faces, maxlen) if maxlen else (verts, faces)


def densify2d(verts, faces, maxlen):
    """Triangulate a flat glyph mesh and split every edge longer than maxlen (m).  Long, thin glyph
    triangles (the stem of an 'I', the middle of an 'M') would otherwise dip below the curved hull
    once only their corners are projected onto it (chord sagitta > offset)."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, 0.0)) for x, y in verts]
    for f in faces:
        try:
            bm.faces.new([vs[i] for i in f])
        except ValueError:
            pass
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='BEAUTY')
    for _ in range(10):
        longe = [e for e in bm.edges if e.calc_length() > maxlen]
        if not longe:
            break
        bmesh.ops.subdivide_edges(bm, edges=longe, cuts=1, use_grid_fill=True)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3],
                              quad_method='BEAUTY', ngon_method='BEAUTY')
    bm.verts.index_update()
    out_v = [(v.co.x, v.co.y) for v in bm.verts]
    out_f = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    return out_v, out_f


bm = bmesh.new()
tv, tf = text_mesh("AI EMPIRE AIR", 0.90, bold=0.012, maxlen=0.18)
for side in (-1, 1):
    pts, nrms = [], []
    for (u, v) in tv:
        s = 11.2 + (u if side < 0 else -u)      # reads front->back on both sides
        z = 5.24 + v
        p, n = project_fus(s, phi_at(s, z), side, 0.02)
        pts.append(p); nrms.append(n)
    fl = tf if side < 0 else [tuple(reversed(f)) for f in tf]
    solid_from_surface(bm, pts, nrms, fl, 0.01, 0)
finish("Titles", bm, (11.2, 0.0, 5.24), ["Accent_Blue"], smooth_deg=30.0,
       meta=dict(kind="static", can_collide=False, note="generic title 'AI EMPIRE AIR' (no real brand)"))


# ----------------------------------------------------------------------------------------------
# 3) LIFTING SURFACES (wing + sharklet, flaps, ailerons, tailplane, fin, rudder)
# ----------------------------------------------------------------------------------------------
def yt(x, t):
    x = min(max(x, 0.0), 1.0)
    return 5 * t * (0.2969 * math.sqrt(x) - 0.1260 * x - 0.3516 * x * x + 0.2843 * x ** 3 - 0.1015 * x ** 4) + 0.0025 * x


def yc(x, m, p=0.45):
    if m == 0:
        return 0.0
    return m / p ** 2 * (2 * p * x - x * x) if x < p else m / (1 - p) ** 2 * ((1 - 2 * p) + 2 * p * x - x * x)


NF, NA = 12, 4


def af_loop(part, h, t, m):
    """returns list of (x, y) in chord units, closed loop. part: 'fore' (0..h) or 'aft' (h..1)"""
    if part == "fore":
        xs = [h * (1 - math.cos(k / NF * math.pi / 2)) for k in range(NF + 1)]
        top = [(x, yc(x, m) + yt(x, t)) for x in reversed(xs)]          # h -> 0
        bot = [(x, yc(x, m) - yt(x, t)) for x in xs[1:]]                # >0 -> h
        return top + bot
    xs = [h + (1 - h) * k / NA for k in range(NA + 1)]
    top = [(x, yc(x, m) + yt(x, t)) for x in reversed(xs)]              # 1 -> h
    bot = [(x, yc(x, m) - yt(x, t)) for x in xs]                        # h -> 1
    return top + bot


def section(st, part, h, mirror=1):
    """st: dict(s_le, b, z, c, t, m, th) ; returns ring of Blender points"""
    th = rad(st["th"])
    nrm = (0.0, -math.sin(th), math.cos(th))     # thickness direction in (s, b, z)
    out = []
    for (x, y) in af_loop(part, h, st["t"], st["m"]):
        s = st["s_le"] + x * st["c"]
        b = st["b"] + nrm[1] * y * st["c"]
        z = st["z"] + nrm[2] * y * st["c"]
        out.append(P(s, mirror * b, z))
    return out


# --- main wing planform (A320neo AC fig. 2-2-0-991-009 traced; 25 deg quarter-chord sweep)
TAN_LE = math.tan(rad(27.7))
DIH = 5.1
B_SOB, B_KINK, B_TIP = 1.98, 6.40, 16.29


def wing_station(b):
    s_le = 13.04 + (b - 2.27) * TAN_LE
    s_te = 19.0 if b <= B_KINK else 19.0 + (b - B_KINK) * (22.04 - 19.0) / (B_TIP - B_KINK)
    if b <= B_SOB:
        t = 0.15
    elif b <= B_KINK:
        t = lerp(0.15, 0.12, (b - B_SOB) / (B_KINK - B_SOB))
    else:
        t = lerp(0.12, 0.105, (b - B_KINK) / (B_TIP - B_KINK))
    z = 2.85 + (b - B_SOB) * math.tan(rad(DIH))
    return dict(s_le=s_le, b=b, z=z, c=s_te - s_le, t=t, m=0.02, th=DIH)


H_FLAP, H_AIL = 0.70, 0.76


def sharklet_stations():
    j = wing_station(B_TIP)
    R, th0, th1, Ls = 1.44, DIH, 77.0, 1.40
    bc = B_TIP - R * math.sin(rad(th0))
    zc = j["z"] + R * math.cos(rad(th0))
    path = []
    for th in (th0, 16.0, 28.0, 40.0, 52.0, 64.0, th1):
        path.append((bc + R * math.sin(rad(th)), zc - R * math.cos(rad(th)), th))
    bx, zx, _ = path[-1]
    for L in (0.7, Ls):
        path.append((bx + L * math.cos(rad(th1)), zx + L * math.sin(rad(th1)), th1))
    # arc length param
    acc = [0.0]
    for i in range(1, len(path)):
        acc.append(acc[-1] + math.hypot(path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]))
    tot = acc[-1]
    sts = []
    for (bb, zz, th), a in zip(path, acc):
        t = a / tot
        le = 20.40 + (22.90 - 20.40) * t ** 0.9
        te = 22.04 + (23.45 - 22.04) * t
        sts.append(dict(s_le=le, b=bb, z=zz, c=te - le, t=lerp(0.105, 0.085, t), m=lerp(0.02, 0.008, t), th=th))
    return sts


def fairing_canoe(bm, b, mirror, mat):
    st = wing_station(b)
    s0 = st["s_le"] + 0.42 * st["c"]
    s1 = st["s_le"] + st["c"] + 0.55
    secs = []
    N = 10
    for k in range(9):
        t = k / 8.0
        s = lerp(s0, s1, t)
        f = max(0.08, math.sin(math.pi * t) ** 0.6)
        x = min(1.0, (s - st["s_le"]) / st["c"])
        zl = st["z"] + st["c"] * (yc(x, st["m"]) - yt(x, st["t"]))
        zcen = zl - 0.08 - 0.10 * math.sin(math.pi * min(1.0, t * 1.2))
        ring = []
        for j in range(N):
            a = 2 * math.pi * j / N
            ring.append(P(s, mirror * (b + 0.15 * f * math.cos(a)), zcen + 0.24 * f * math.sin(a)))
        secs.append(ring)
    loft(bm, secs, mat)


HINGES = {}


def hinge_from(stA, stB, h, mirror):
    """hinge line endpoints at chord fraction h (mid thickness) -> aircraft frame points"""
    pts = []
    for st in (stA, stB):
        x = h
        y = yc(x, st["m"])
        th = rad(st["th"])
        s = st["s_le"] + x * st["c"]
        b = st["b"] + (-math.sin(th)) * y * st["c"]
        z = st["z"] + math.cos(th) * y * st["c"]
        pts.append(Vector((s, mirror * b, z)))
    return pts


def build_wing(mirror, tag):
    bm = bmesh.new()
    W = wing_station
    # W0: inside the fuselage, full chord
    loft(bm, [section(W(0.5), "fore", 1.0, mirror), section(W(1.95), "fore", 1.0, mirror)], 0)
    # W1: inboard segment, cut at flap hinge
    loft(bm, [section(W(1.95), "fore", H_FLAP, mirror), section(W(B_KINK), "fore", H_FLAP, mirror)], 0)
    # W2: outboard flap segment
    loft(bm, [section(W(B_KINK), "fore", H_FLAP, mirror), section(W(12.6), "fore", H_FLAP, mirror)], 0)
    # W3: aileron segment
    loft(bm, [section(W(12.6), "fore", H_AIL, mirror), section(W(15.85), "fore", H_AIL, mirror)], 0)
    # W4: fixed tip + sharklet (one continuous loft)
    sts = [W(15.85)] + sharklet_stations()
    secs = [section(st, "fore", 1.0, mirror) for st in sts]
    nsec = len(secs)
    loft(bm, secs, 0, mat_fn=lambda i, j: 1 if i >= 2 else 0, cap_mat=(0, 1))
    # flap track fairings
    for bb in (8.4, 12.2):
        fairing_canoe(bm, bb, mirror, 0)
    finish("Wing_" + tag, bm, (wing_station(B_SOB)["s_le"], mirror * B_SOB, wing_station(B_SOB)["z"]),
           ["Wing_Grey", "Accent_Blue"], smooth_deg=40.0,
           meta=dict(kind="static", can_collide=False,
                     note="wing box + fixed tip + sharklet + 2 flap-track fairings; pivot at wing root LE (side of body)"))

    def surface(name, b0, b1, h, lim, note):
        bmx = bmesh.new()
        A, B = W(b0), W(b1)
        loft(bmx, [section(A, "aft", h, mirror), section(B, "aft", h, mirror)], 0)
        hp = hinge_from(A, B, h, mirror)
        piv = (hp[0] + hp[1]) * 0.5
        finish(name, bmx, tuple(piv), ["Wing_Grey"], smooth_deg=40.0,
               meta=dict(kind="control", can_collide=False, hinge=[list(hp[0]), list(hp[1])],
                         limits=lim, positive="trailing edge DOWN", note=note))

    surface("Flap_%s_In" % tag, 1.96, B_KINK - 0.012, H_FLAP, [0, 40],
            "inboard flap (simplified: pure rotation, real flap is Fowler-type)")
    surface("Flap_%s_Out" % tag, B_KINK + 0.012, 12.6 - 0.012, H_FLAP, [0, 40],
            "outboard flap (simplified: pure rotation)")
    surface("Aileron_%s" % tag, 12.6 + 0.012, 15.85 - 0.012, H_AIL, [-25, 25], "aileron")


build_wing(-1, "L")
build_wing(1, "R")


# --- horizontal tailplane (span 12.45 m, AC); root at fuselage side LE 32.07 / TE 35.45 (traced)
def hstab_station(b):
    return dict(s_le=32.07 + (b - 0.95) * (3.31 / 5.275), b=b,
                z=5.05 + (b - 0.95) * math.tan(rad(6.0)),
                c=(35.45 + (b - 0.95) * (1.17 / 5.275)) - (32.07 + (b - 0.95) * (3.31 / 5.275)),
                t=lerp(0.11, 0.09, (b - 0.25) / 6.0), m=0.0, th=6.0)


H_ELEV = 0.70
for mirror, tag in ((-1, "L"), (1, "R")):
    bm = bmesh.new()
    H = hstab_station
    loft(bm, [section(H(0.25), "fore", 1.0, mirror), section(H(1.0), "fore", 1.0, mirror)], 0)
    loft(bm, [section(H(1.0), "fore", H_ELEV, mirror), section(H(6.05), "fore", H_ELEV, mirror)], 0)
    tipst = dict(H(6.225))
    loft(bm, [section(H(6.05), "fore", 1.0, mirror), section(tipst, "fore", 1.0, mirror)], 0)
    finish("HStab_" + tag, bm, (32.07, mirror * 0.95, 5.05), ["Wing_Grey"], smooth_deg=40.0,
           meta=dict(kind="static", can_collide=False, note="trimmable horizontal stabiliser (static here)"))
    bm = bmesh.new()
    A, B = H(1.012), H(6.038)
    loft(bm, [section(A, "aft", H_ELEV, mirror), section(B, "aft", H_ELEV, mirror)], 0)
    hp = hinge_from(A, B, H_ELEV, mirror)
    finish("Elevator_" + tag, bm, tuple((hp[0] + hp[1]) * 0.5), ["Wing_Grey"], smooth_deg=40.0,
           meta=dict(kind="control", can_collide=False, hinge=[list(hp[0]), list(hp[1])], limits=[-30, 17],
                     positive="trailing edge DOWN (nose-down pitch)", note="elevator"))

# --- vertical fin (5.87 m above fuselage top, AC) + rudder
VLE_FILLET = Curve1D([(5.30, 28.70), (5.94, 28.90), (6.10, 29.50), (6.25, 29.85), (6.45, 30.20),
                      (6.70, 30.55), (7.05, 30.99)])


def vstab_station(z, le_round=0.0):
    if z >= 7.05:
        s_le = 34.91 - (11.80 - z) * math.tan(rad(39.5))
    else:
        s_le = VLE_FILLET(z)
    s_le += le_round
    s_te = 35.55 + (z - 6.2) * (1.2 / 5.6)
    c = s_te - s_le
    t = 0.075 if z <= 6.25 else (lerp(0.075, 0.095, (z - 6.25) / 0.8) if z < 7.05 else 0.10)
    return dict(s_le=s_le, b=0.0, z=z, c=c, t=t, m=0.0, th=90.0)


def rudder_hinge_s(z):
    return 33.8 + (z - 6.2) * ((36.15 - 33.8) / 5.6)


def vfrac(st):
    return (rudder_hinge_s(st["z"]) - st["s_le"]) / st["c"]


bm = bmesh.new()
V = vstab_station
loft(bm, [section(V(5.30), "fore", 1.0), section(V(5.94), "fore", 1.0), section(V(6.25), "fore", 1.0)], 0)
vz = [6.25, 6.45, 6.70, 7.05, 8.6, 10.2, 11.70]
# all stations of one loft must share point count -> per-station hinge fraction, same NF
secs = []
for z in vz:
    st = V(z)
    secs.append(section(st, "fore", vfrac(st)))
loft(bm, secs, 0)
loft(bm, [section(V(11.70), "fore", 1.0), section(V(11.80, le_round=0.10), "fore", 1.0)], 0)
finish("VStab", bm, (V(5.94)["s_le"], 0.0, 5.94), ["Accent_Blue"], smooth_deg=40.0,
       meta=dict(kind="static", can_collide=False, note="fin incl. dorsal fillet"))

bm = bmesh.new()
rz = [6.25, 6.45, 6.70, 7.05, 8.6, 10.2, 11.70]
loft(bm, [section(V(z), "aft", vfrac(V(z))) for z in rz], 0)
hpA = Vector((rudder_hinge_s(6.25), 0.0, 6.25))
hpB = Vector((rudder_hinge_s(11.70), 0.0, 11.70))
finish("Rudder", bm, tuple((hpA + hpB) * 0.5), ["Accent_Blue"], smooth_deg=40.0,
       meta=dict(kind="control", can_collide=False, hinge=[list(hpA), list(hpB)], limits=[-30, 30],
                 positive="trailing edge to PORT (nose-left yaw)", note="rudder"))

# --- tail mark "AI" on both sides of the fin (white, italic)
bm = bmesh.new()
tv, tf = text_mesh("AI", 2.05, bold=0.06, maxlen=0.35)
fin_bvh_src = bpy.data.objects["VStab"]
fin_mesh = fin_bvh_src.data
fin_bm = bmesh.new()
fin_bm.from_mesh(fin_mesh)
fin_bm.transform(Matrix.Translation(fin_bvh_src.location))
fin_bvh = BVHTree.FromBMesh(fin_bm)
fin_bm.free()
for side in (-1, 1):
    pts, nrms = [], []
    for (u, v) in tv:
        z = 8.75 + v
        s = 33.55 + (u if side < 0 else -u) + (v * 0.55)      # leans back with the fin sweep
        origin = P(s, side * 1.5, z)
        loc, nrm, _i, _d = fin_bvh.ray_cast(origin, D(0, -side, 0), 3.0)
        if loc is None:
            loc, nrm = P(s, side * 0.12, z), D(0, side, 0)
        pts.append(loc + nrm * 0.015); nrms.append(nrm)
    fl = tf if side < 0 else [tuple(reversed(f)) for f in tf]
    solid_from_surface(bm, pts, nrms, fl, 0.008, 0)
finish("TailLogo", bm, (33.55, 0.0, 8.75), ["Livery_White"], smooth_deg=30.0,
       meta=dict(kind="static", can_collide=False, note="generic 'AI' tail mark (fixed fin part only)"))

# ----------------------------------------------------------------------------------------------
# 4) ENGINES (CFM LEAP-1A-like nacelle per AC fig. 2-12-0-991-054/055) + FANS
# ----------------------------------------------------------------------------------------------
ENG_B, ENG_Z, ENG_S = 5.75, 1.80, 11.14     # lateral (AC), axis height (from N1 clearance), inlet (AC)
FAN_SP = 0.62                                # fan plane behind the inlet lip

NAC_OUT = Curve1D([(0.0, 1.14), (0.02, 1.18), (0.08, 1.215), (0.25, 1.25), (0.6, 1.275), (1.0, 1.285),
                   (1.6, 1.28), (2.25, 1.26), (2.9, 1.20), (3.6, 1.10), (4.1, 1.00), (4.23, 0.96)])
# (a, r, material-index-of-following-band)  0 nacelle blue, 1 lip metal, 2 dark, 3 exhaust metal
NAC_PROFILE = [
    (0.90, 0.00, 2), (0.90, 0.99, 2), (0.60, 1.00, 2), (0.30, 1.03, 2), (0.10, 1.07, 1),
    (0.02, 1.10, 1), (0.0, 1.14, 1), (0.02, 1.18, 1), (0.08, 1.215, 0), (0.25, 1.25, 0),
    (0.6, 1.275, 0), (1.0, 1.285, 0), (1.6, 1.28, 0), (2.25, 1.26, 0), (2.9, 1.20, 0),
    (3.6, 1.10, 0), (4.1, 1.00, 1), (4.23, 0.96, 2), (4.20, 0.925, 2), (3.95, 0.905, 2),
    (3.95, 0.72, 3), (4.20, 0.68, 3), (4.46, 0.585, 2), (4.44, 0.53, 2), (4.44, 0.44, 3),
    (4.75, 0.38, 3), (5.10, 0.24, 3), (5.38, 0.07, 3), (5.44, 0.0, 3)]

PYL = [  # s, z_top, z_bot, half-width
    (12.25, 3.06, None, 0.06), (12.6, 3.17, None, 0.20), (13.4, 3.25, None, 0.24), (14.4, 3.29, None, 0.24),
    (15.4, 3.25, 2.70, 0.24), (16.4, 3.12, 2.62, 0.23), (17.4, 3.02, 2.62, 0.21), (18.5, 2.96, 2.66, 0.17),
    (19.5, 2.88, 2.80, 0.05)]


def build_engine(idx, side):
    bm = bmesh.new()
    origin = P(ENG_S, side * ENG_B, ENG_Z)
    axis = D(1, 0, 0)
    revolve(bm, NAC_PROFILE, origin, axis, 32, phase=rad(90 / 32))
    # pylon
    secs = []
    for (s, zt, zb, hw) in PYL:
        if zb is None:
            zb = ENG_Z + NAC_OUT(s - ENG_S) - 0.07
        zc = 0.5 * (zt + zb); hh = 0.5 * (zt - zb)
        ring = []
        for j in range(12):
            a = 2 * math.pi * j / 12
            c, sn = math.cos(a), math.sin(a)
            x = hw * math.copysign(abs(c) ** (2 / 3.0), c)
            z = zc + hh * math.copysign(abs(sn) ** (2 / 3.0), sn)
            ring.append(P(s, side * ENG_B + x, z))
        secs.append(ring)
    loft(bm, secs, 4)
    finish("Engine_%d" % idx, bm, (ENG_S + FAN_SP, side * ENG_B, ENG_Z),
           ["Accent_Blue", "Metal_Lip", "Engine_Dark", "Exhaust_Metal", "Wing_Grey"], smooth_deg=40.0,
           meta=dict(kind="static", can_collide=False,
                     note="nacelle (2.52 x 2.60 m class, 5.44 m incl. plug) + pylon; #1 = port, #2 = starboard"))
    # fan: spinner + 18 blades
    bm = bmesh.new()
    sp = [(0.30, 0.0, 0), (0.36, 0.08, 0), (0.45, 0.17, 0), (0.56, 0.255, 0), (0.66, 0.30, 0),
          (0.76, 0.31, 0), (0.80, 0.0, 0)]
    revolve(bm, sp, origin, axis, 20)
    nb = 18
    for k in range(nb):
        a0 = 2 * math.pi * k / nb
        secs = []
        for jr, r in enumerate((0.29, 0.45, 0.62, 0.80, 0.975)):
            tw = rad(lerp(52, 28, (r - 0.29) / 0.685))      # blade angle to the disc plane
            ch = lerp(0.22, 0.36, (r - 0.29) / 0.685)
            th = 0.022
            ring = []
            for (dc, dt) in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)):
                # local blade coords: along chord (in the plane tilted by tw) and thickness
                ax = dc * ch * math.sin(tw) + dt * th * math.cos(tw)       # along engine axis
                tg = dc * ch * math.cos(tw) - dt * th * math.sin(tw)       # tangential
                ang = a0 + tg / r
                y = r * math.cos(ang); zz = r * math.sin(ang)
                ring.append(P(ENG_S + 0.64 + ax, side * ENG_B + y, ENG_Z + zz))
            secs.append(ring)
        loft(bm, secs, 1)
    finish("Fan_%d" % idx, bm, (ENG_S + FAN_SP, side * ENG_B, ENG_Z), ["Metal_Lip", "Engine_Dark"],
           smooth_deg=35.0,
           meta=dict(kind="spin", can_collide=False, note="fan 1.98 m (78 in) class, 18 blades + spinner"))


build_engine(1, -1)
build_engine(2, 1)


# ----------------------------------------------------------------------------------------------
# 5) LANDING GEAR (AC 7-2-0: wheelbase 12.64, track 7.59, MLG twin 0.927, NLG twin 0.50,
#    tyres 46x17R20 main, 30x8.8R15 nose)
# ----------------------------------------------------------------------------------------------
def tire_profile(R, W, Rrim):
    w2 = W / 2
    T, H = 0, 1
    return [(w2 - 0.03, 0.0, H), (w2 - 0.05, 0.10 * R / 0.58, H), (w2 - 0.07, Rrim * 0.75, H),
            (w2 - 0.03, Rrim, H), (w2, Rrim + 0.04 * R / 0.58, T), (w2, R - 0.12 * R / 0.58, T),
            (w2 - 0.03 * R / 0.58, R - 0.04 * R / 0.58, T), (w2 - 0.09 * W / 0.43, R, T),
            (-w2 + 0.09 * W / 0.43, R, T), (-w2 + 0.03 * R / 0.58, R - 0.04 * R / 0.58, T),
            (-w2, R - 0.12 * R / 0.58, T), (-w2, Rrim + 0.04 * R / 0.58, H), (-w2 + 0.03, Rrim, H),
            (-w2 + 0.07, Rrim * 0.75, H), (-w2 + 0.05, 0.10 * R / 0.58, H), (-w2 + 0.03, 0.0, H)]


NLG_S, MLG_S = 5.07, 5.07 + 12.64
MLG_B = 7.59 / 2
R_MAIN, W_MAIN, RIM_MAIN = 46 * 0.0254 / 2, 17 * 0.0254, 20 * 0.0254 / 2
R_NOSE, W_NOSE, RIM_NOSE = 30 * 0.0254 / 2, 8.8 * 0.0254, 15 * 0.0254 / 2

# nose gear leg
NLG_PIV = (NLG_S, 0.0, 2.45)
bm = bmesh.new()
cylinder(bm, P(NLG_S, 0, 2.55), P(NLG_S, 0, 1.05), 0.10, 12, 0)
cylinder(bm, P(NLG_S, 0, 1.12), P(NLG_S, 0, R_NOSE + 0.06), 0.068, 12, 1)
cylinder(bm, P(NLG_S, -0.17, R_NOSE), P(NLG_S, 0.17, R_NOSE), 0.05, 10, 0)
box(bm, P(NLG_S, 0, R_NOSE + 0.08), 0.17, 0.08, 0.06, 0)                     # fork / axle block
cylinder(bm, P(NLG_S, 0, 1.55), P(NLG_S - 1.05, 0, 2.25), 0.045, 8, 0)       # drag brace (fwd)
box(bm, P(NLG_S + 0.12, 0, 0.82), 0.03, 0.10, 0.16, 0)                       # torque link
finish("NoseGear", bm, NLG_PIV, ["Gear_Grey", "Chrome"], smooth_deg=40.0,
       meta=dict(kind="gear", can_collide=False, limits=[0, 95], positive="retract (wheels swing FORWARD and up)",
                 axis_af=[0, 1, 0], note="leg retracts forward into the nose bay"))
bm = bmesh.new()
for bb in (-0.25, 0.25):
    revolve(bm, tire_profile(R_NOSE, W_NOSE, RIM_NOSE), P(NLG_S, bb, R_NOSE), D(0, 1, 0), 16)
finish("NoseWheels", bm, (NLG_S, 0.0, R_NOSE), ["Tire_Black", "Hub_Silver"], smooth_deg=40.0,
       meta=dict(kind="wheel", can_collide=False, parent="NoseGear", axis_af=[0, 1, 0],
                 note="2 x 30x8.8R15 (0.762 m) on one axle"))

for side, tag in ((-1, "L"), (1, "R")):
    bmid = side * MLG_B
    piv = (MLG_S - 0.50, bmid, 3.05)          # trunnion inside the wing root box (lower skin 2.85 m, upper 3.36 m)
    bm = bmesh.new()
    top = P(MLG_S - 0.50, bmid, 3.15)
    low = P(MLG_S - 0.08, bmid, 1.25)
    cylinder(bm, top, low, 0.15, 14, 0)
    cylinder(bm, P(MLG_S - 0.10, bmid, 1.32), P(MLG_S, bmid, R_MAIN + 0.05), 0.105, 14, 1)
    cylinder(bm, P(MLG_S, bmid - 0.30, R_MAIN), P(MLG_S, bmid + 0.30, R_MAIN), 0.075, 12, 0)
    box(bm, P(MLG_S, bmid, R_MAIN + 0.07), 0.12, 0.12, 0.09, 0)
    # side stay: runs from the leg up to a point just inboard of the trunnion so that it stays inside the
    # wing root when the leg is stowed (a full-length stay to the fuselage would poke through the wing)
    cylinder(bm, P(MLG_S - 0.25, bmid, 1.95), P(MLG_S - 0.45, bmid - side * 0.30, 3.00), 0.07, 10, 0)
    box(bm, P(MLG_S + 0.18, bmid, 1.0), 0.035, 0.10, 0.18, 0)                                    # torque link
    # strut door (leg fairing) on the outboard side
    box(bm, P(MLG_S - 0.30, bmid + side * 0.21, 1.95), 0.025, 0.40, 0.85, 2)
    finish("MainGear_" + tag, bm, piv, ["Gear_Grey", "Chrome", "Belly_Grey"], smooth_deg=40.0,
           meta=dict(kind="gear", can_collide=False, limits=[0, 100],
                     positive="retract (leg swings INBOARD and up; at 100 deg the leg lies under the wing root and the "
                              "wheels lie flat inside the belly)",
                     axis_af=[1, 0, 0], note="raked oleo leg, side brace, strut door"))
    bm = bmesh.new()
    for off in (-0.927 / 2, 0.927 / 2):
        revolve(bm, tire_profile(R_MAIN, W_MAIN, RIM_MAIN), P(MLG_S, bmid + off, R_MAIN), D(0, 1, 0), 20)
    finish("MainWheels_" + tag, bm, (MLG_S, bmid, R_MAIN), ["Tire_Black", "Hub_Silver"], smooth_deg=40.0,
           meta=dict(kind="wheel", can_collide=False, parent="MainGear_" + tag, axis_af=[0, 1, 0],
                     note="2 x 46x17R20 (1.168 m) on one axle"))


# ----------------------------------------------------------------------------------------------
# 6) bookkeeping: triangle counts, manifold check, pivots/axes in Roblox space
# ----------------------------------------------------------------------------------------------
bpy.context.view_layer.update()      # make matrix_world valid for freshly created objects


def tri_count(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


def manifold_report(me):
    bm = bmesh.new()
    bm.from_mesh(me)
    nonman = sum(1 for e in bm.edges if not e.is_manifold)
    boundary = sum(1 for e in bm.edges if e.is_boundary)
    bm.free()
    return nonman, boundary


def bbox_af(ob):
    """world bbox of object in aircraft frame (metres)"""
    pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
    s = [p.y + HALF for p in pts]; b = [-p.x for p in pts]; z = [p.z for p in pts]
    return (min(s), max(s)), (min(b), max(b)), (min(z), max(z))


def axis_with_sign(meta, name):
    """choose the hinge axis direction so that a POSITIVE right-hand rotation (Roblox space) gives
    the documented positive motion. Returns (axis aircraft-frame Vector, pivot Vector)."""
    piv = Vector(meta["pivot_af"])
    kind = meta["kind"]
    ob = bpy.data.objects[name]
    pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
    afp = [Vector((p.y + HALF, -p.x, p.z)) for p in pts]

    def to_r(v):          # aircraft frame -> Roblox (right-handed): (b, z, s)
        return Vector((v.y, v.z, v.x))

    if "hinge" in meta:
        a = (Vector(meta["hinge"][1]) - Vector(meta["hinge"][0])).normalized()
    elif "axis_af" in meta:
        a = Vector(meta["axis_af"]).normalized()
    else:
        return None, piv
    # probe point: the vertex farthest from the hinge line
    far = max(afp, key=lambda q: ((q - piv) - a * (q - piv).dot(a)).length)
    r = to_r(far - piv)
    ar = to_r(a)
    dv = ar.cross(r)                 # instantaneous motion (Roblox space) for +rotation
    d_af = Vector((dv.z, dv.x, dv.y))  # back to aircraft frame (s, b, z)
    flip = False
    if kind == "control":
        if name.startswith("Rudder"):
            flip = d_af.y > 0            # want TE to move to port (b negative)
        else:
            flip = d_af.z > 0            # want TE down
    elif kind == "gear":
        if name == "NoseGear":
            flip = d_af.x > 0            # want wheel to move forward (s decreasing)
        else:
            flip = d_af.y * piv.y > 0    # want the leg to swing inboard (towards b = 0)
    elif kind == "wheel":
        # rolling forward: top of wheel moves forward (s decreasing)
        top = Vector((0, 0, 1.0))
        dtop = ar.cross(to_r(top))
        flip = dtop.z > 0
    elif kind == "spin":
        flip = False
    elif kind == "door":
        pass
    if flip:
        a = -a
    return a, piv


# doors & fans: explicit axes
for nm, sc, sill, side in DOORS:
    OBJ_META[nm]["axis_af"] = [0, 0, 1]
    OBJ_META[nm]["limits"] = [0, 100]
for i, side in ((1, -1), (2, 1)):
    OBJ_META["Fan_%d" % i]["axis_af"] = [-1, 0, 0]
    OBJ_META["Fan_%d" % i]["positive"] = "clockwise when viewed from behind the engine (looking forward)"

for nm, meta in OBJ_META.items():
    if meta["kind"] == "door":
        side = -1 if nm.endswith("L") else 1
        # +rotation should swing the aft edge OUTBOARD: aft edge relative to hinge = (+s); want +b*side
        r = Vector((0.0, 0.0, 1.0))          # Roblox: aft = +Z (s)
        a = Vector((0.0, 1.0, 0.0))          # Roblox up
        dv = a.cross(r)                      # (1,0,0)*? -> motion along +X(b) for +rot about +Y
        want_x = side
        if dv.x * want_x < 0:
            meta["axis_af"] = [0, 0, -1]
        meta["positive"] = "door opens (aft edge swings outboard, door folds forward along the hull)"

# ----------------------------------------------------------------------------------------------
# 7) scale to studs (1 BU = 1 stud)
# ----------------------------------------------------------------------------------------------
mesh_objs = [o for o in COLL.objects if o.type == 'MESH']
measure_m = {}
for ob in mesh_objs:
    measure_m[ob.name] = bbox_af(ob)

axes = {}
for nm, meta in OBJ_META.items():
    a, piv = axis_with_sign(meta, nm)
    axes[nm] = (a, piv)

for ob in mesh_objs:
    ob.data.transform(Matrix.Scale(S2, 4))
    ob.location = ob.location * S2
    ob.data.update()

# ----------------------------------------------------------------------------------------------
# 8) export FBX + OBJ
# ----------------------------------------------------------------------------------------------
fbx_path = os.path.join(OUT, NAME + ".fbx")
obj_path = os.path.join(OUT, NAME + ".obj")
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

# ----------------------------------------------------------------------------------------------
# 9) manifest
# ----------------------------------------------------------------------------------------------
ORDER = ["Fuselage", "WindowStrip_L", "WindowStrip_R", "CockpitWindows", "Titles", "TailLogo",
         "Door_1L", "Door_1R", "Door_2L", "Door_2R",
         "Wing_L", "Wing_R", "Flap_L_In", "Flap_L_Out", "Flap_R_In", "Flap_R_Out", "Aileron_L", "Aileron_R",
         "HStab_L", "HStab_R", "Elevator_L", "Elevator_R", "VStab", "Rudder",
         "Engine_1", "Engine_2", "Fan_1", "Fan_2",
         "NoseGear", "NoseWheels", "MainGear_L", "MainWheels_L", "MainGear_R", "MainWheels_R"]
assert sorted(ORDER) == sorted(OBJ_META.keys()), (sorted(OBJ_META.keys()))

objs_out = []
total = 0
problems = []
for nm in ORDER:
    ob = bpy.data.objects[nm]
    me = ob.data
    tris = tri_count(me)
    total += tris
    nonman, boundary = manifold_report(me)
    if tris >= 20000:
        problems.append("%s over 20k triangles" % nm)
    if nonman:
        problems.append("%s has %d non-manifold edges" % (nm, nonman))
    meta = OBJ_META[nm]
    (s0, s1), (b0, b1), (z0, z1) = measure_m[nm]
    a, piv = axes[nm]
    entry = dict(
        name=nm, kind=meta["kind"], triangles=tris, non_manifold_edges=nonman,
        materials=meta["materials"],
        roblox_color_if_vertex_colors=[255, 255, 255],
        roblox_color_fallback=[int(round(c * 255)) for c in srgb(MATDEF[meta["materials"][0]][0])],
        can_collide=bool(meta.get("can_collide", False)),
        pivot_studs=to_roblox(*piv), pivot_m_aircraft=dict(s_aft_of_nose=round(piv.x, 4), b_starboard=round(piv.y, 4), z_up=round(piv.z, 4)),
        bbox_studs=dict(min=[round(b0 * S2, 3), round(z0 * S2, 3), round((s0 - HALF) * S2, 3)],
                        max=[round(b1 * S2, 3), round(z1 * S2, 3), round((s1 - HALF) * S2, 3)]),
        size_m=[round(b1 - b0, 3), round(z1 - z0, 3), round(s1 - s0, 3)],
        note=meta.get("note", ""))
    if a is not None:
        entry["hinge_axis_roblox"] = dir_roblox(a.x, a.y, a.z)
        entry["rotation_limits_deg"] = meta.get("limits", None)
        entry["positive_rotation"] = meta.get("positive", "")
    if "parent" in meta:
        entry["animate_with_parent"] = meta["parent"]
    if "hinge" in meta:
        entry["hinge_line_studs"] = [to_roblox(*meta["hinge"][0]), to_roblox(*meta["hinge"][1])]
    objs_out.append(entry)

all_s = [measure_m[n][0] for n in ORDER]; all_b = [measure_m[n][1] for n in ORDER]; all_z = [measure_m[n][2] for n in ORDER]
L_m = max(x[1] for x in all_s) - min(x[0] for x in all_s)
SPAN_m = max(x[1] for x in all_b) - min(x[0] for x in all_b)
H_m = max(x[1] for x in all_z) - min(x[0] for x in all_z)
fus = measure_m["Fuselage"]


def mstud(v):
    return dict(m=round(v, 3), studs=round(v * S2, 2))


manifest = dict(
    name=NAME,
    description="Generic narrow-body twin-jet airliner (A320neo proportions) for AI Empire. No real brands.",
    generator="model.py (bpy %s)" % bpy.app.version_string,
    scale=dict(metres_per_stud=STUD_M, studs_per_metre=round(S2, 6),
               source="https://create.roblox.com/docs/physics/units (1 stud = 28 cm)",
               blender_units="1 Blender unit = 1 stud (Unit System None, unit scale 1.0)"),
    axes=dict(blender="nose -> -Y, up +Z, starboard -> -X",
              fbx_export="axis_forward=Z, axis_up=Y, apply_scale_options=FBX_SCALE_UNITS, bake_space_transform=True "
                         "(Roblox Blender guide: 'Z Forward' / 'Y Up' / Apply Scalings 'FBX Unit Scale')",
              fbx_raw_frame="X = starboard, Y = up, Z = aft (nose towards -Z); every node has rotation (0,0,0), scale 1",
              roblox_expected="nose -> -Z (LookVector), up +Y, starboard -> +X  (importer: World Forward=Front, World Up=Top)"),
    origin="ground plane (tyre contact), aircraft centreline, longitudinal midpoint 18.785 m behind the nose",
    roblox_location="ReplicatedStorage/VehicleAssets/Skyliner320 (Model; children = MeshParts named as in 'objects')",
    roblox_import_settings=dict(file="Skyliner320.fbx", import_only_as_model=True, set_pivot_to_scene_origin=True,
                                anchored=False, world_forward="Front", world_up="Top", scale_unit="Stud",
                                merge_meshes=False, use_imported_pivot=True, ignore_vertex_colors=False,
                                source="https://create.roblox.com/docs/studio/importer, "
                                       "https://create.roblox.com/docs/art/blender"),
    roblox_part_settings=dict(all=dict(Anchored=False, Color=[255, 255, 255], Material="SmoothPlastic"),
                              Fuselage=dict(CanCollide=True, Massless=False, CollisionFidelity="Hull"),
                              others=dict(CanCollide=False, CanTouch=False, CanQuery=False, Massless=True)),
    dimensions=dict(length=mstud(L_m), wingspan=mstud(SPAN_m), height=mstud(H_m),
                    fuselage_width=mstud(fus[1][1] - fus[1][0]),
                    fuselage_height_cabin=mstud(TOP(15.0) - BOT(15.0)),
                    wheelbase=mstud(12.64), main_gear_track=mstud(7.59),
                    engine_centreline_lateral=mstud(ENG_B), engine_axis_height=mstud(ENG_Z),
                    nacelle_max_diameter=mstud(2 * 1.285), fan_diameter=mstud(1.95)),
    triangle_limit_per_mesh=dict(value=20000, source="https://create.roblox.com/docs/art/modeling/specifications"),
    total_triangles=total,
    objects=objs_out,
    rotation_convention="CFrame.fromAxisAngle(hinge_axis_roblox, math.rad(angle)) about pivot_studs; right-hand rule; "
                        "positive angle produces 'positive_rotation'. Pivot/axes are in model space (relative to the "
                        "Model pivot = scene origin) with the model un-rotated.",
    problems=problems)
with open(os.path.join(OUT, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent=2)
print("TOTAL TRIS", total, "PROBLEMS", problems)
print("DIMS m: L %.3f  span %.3f  H %.3f" % (L_m, SPAN_m, H_m))


# ----------------------------------------------------------------------------------------------
# 10) renders (Cycles CPU)
# ----------------------------------------------------------------------------------------------
def setup_render():
    sc = SCENE
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 48
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    try:                                   # OpenImageDenoise is compiled into the bpy 5.0.1 wheel
        sc.cycles.use_denoising = True
        sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    except Exception:
        sc.cycles.use_denoising = False
        sc.cycles.samples = 128
    sc.cycles.max_bounces = 4
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    w = bpy.data.worlds.new("Sky")
    sc.world = w
    if w.node_tree is None:
        w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.62, 0.74, 0.92, 1.0)
    bg.inputs[1].default_value = 0.9
    sun = bpy.data.lights.new("Sun", 'SUN')
    sun.energy = 3.2
    sun.angle = rad(4.0)
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (rad(50), rad(8), rad(-35))
    COLL.objects.link(so)
    gm = bpy.data.materials.new("Ground")
    if gm.node_tree is None:
        gm.use_nodes = True
    gb = gm.node_tree.nodes.get("Principled BSDF")
    gb.inputs["Base Color"].default_value = (0.30, 0.31, 0.32, 1.0)
    gb.inputs["Roughness"].default_value = 0.9
    gme = bpy.data.meshes.new("Ground")
    gbm = bmesh.new()
    bmesh.ops.create_grid(gbm, x_segments=1, y_segments=1, size=600.0)
    gbm.to_mesh(gme); gbm.free()
    gme.materials.append(gm)
    go = bpy.data.objects.new("Ground", gme)
    COLL.objects.link(go)
    return go


def camera(name, loc, target, ortho=None, lens=50.0, up_hint=None):
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


def render(co, path, res=(1280, 720), hide_ground=False, ground=None):
    SCENE.camera = co
    SCENE.render.resolution_x, SCENE.render.resolution_y = res
    if ground is not None:
        ground.hide_render = hide_ground
    SCENE.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    print("rendered", os.path.basename(path), "%.1fs" % (time.time() - t))


if DO_RENDER:
    ground = setup_render()
    k = S2
    ctr = Vector((0, 0, 4.5 * k))
    views = []
    # front (looking at the nose, ortho)
    co = camera("cam_front", (0, -140 * k, 5.2 * k), (0, 0, 5.2 * k), ortho=40 * k)
    views.append((co, "render_front.png", (1280, 720)))
    # side (port side, nose to the left, ortho) -- framed to match compare_side.png
    co = camera("cam_side", (140 * k, 0, 6.0 * k), (0, 0, 6.0 * k), ortho=41 * k)
    views.append((co, "render_side.png", (1280, 720)))
    # top (nose to the left)
    co = camera("cam_top", (0, 0, 200 * k), (0, 0, 0), ortho=41 * k)
    co.rotation_euler = (0, 0, rad(90))
    views.append((co, "render_top.png", (1280, 1200)))
    # 3/4 front-left-above
    co = camera("cam_34", (34 * k, -46 * k, 15 * k), (0, -3 * k, 3.2 * k), lens=40)
    views.append((co, "render_34.png", (1280, 720)))
    # rear 3/4 from below (gear, belly, control surfaces)
    co = camera("cam_34rear", (-30 * k, 40 * k, 4.0 * k), (0, 2 * k, 3.5 * k), lens=40)
    views.append((co, "render_34_rear.png", (1280, 720)))
    # close-up: cockpit + engine (port side)
    co = camera("cam_close", (12.5 * k, -32 * k, 5.2 * k), (3.0 * k, -15.0 * k, 3.4 * k), lens=45)
    views.append((co, "render_closeup.png", (1280, 720)))
    for co, fn, res in views:
        render(co, os.path.join(OUT, fn), res, ground=ground)

print("RENDERS DONE")


# ----------------------------------------------------------------------------------------------
# 11) re-import check: load the exported FBX/OBJ into an empty scene and measure them
# ----------------------------------------------------------------------------------------------
def raw_fbx_check(path, exp):
    """Read the FBX *without* any axis conversion (what an importer that keeps the file's Y-up frame,
    such as Roblox Studio with World Forward = Front / World Up = Top, receives) and check node
    transforms, pivots and the overall orientation."""
    addons = os.path.join(os.path.dirname(bpy.__file__), "%d.%d" % bpy.app.version[:2], "scripts", "addons_core")
    if addons not in sys.path:
        sys.path.append(addons)
    from io_scene_fbx import parse_fbx
    root, _ver = parse_fbx.parse(path)

    def kids(el, name):
        return [c for c in el.elems if c.id == name.encode()]

    gs = {}
    for p in kids(kids(root, "GlobalSettings")[0], "Properties70")[0].elems:
        gs[p.props[0].decode()] = p.props[4] if len(p.props) > 4 else None
    objs = kids(root, "Objects")[0]
    models, geoms = {}, {}
    for m in kids(objs, "Model"):
        nm = m.props[1].decode().split("\x00")[0]
        tr = dict(t=[0.0, 0.0, 0.0], r=[0.0, 0.0, 0.0], s=[1.0, 1.0, 1.0])
        for p in kids(m, "Properties70")[0].elems if kids(m, "Properties70") else []:
            k = p.props[0].decode()
            if k == "Lcl Translation":
                tr["t"] = list(p.props[4:7])
            elif k == "Lcl Rotation":
                tr["r"] = list(p.props[4:7])
            elif k == "Lcl Scaling":
                tr["s"] = list(p.props[4:7])
        models[m.props[0]] = (nm, tr)
    for g in kids(objs, "Geometry"):
        v = kids(g, "Vertices")[0].props[0]
        geoms[g.props[0]] = [(v[i], v[i + 1], v[i + 2]) for i in range(0, len(v), 3)]
    link = {}
    for c in kids(kids(root, "Connections")[0], "C"):
        if c.props[0] == b"OO" and c.props[1] in geoms and c.props[2] in models:
            link[c.props[2]] = c.props[1]
    out, problems = {}, []
    lo = [1e9] * 3; hi = [-1e9] * 3
    for mid, (nm, tr) in models.items():
        t = tr["t"]
        vs = geoms.get(link.get(mid), [])
        for (x, y, z) in vs:
            for k, c in enumerate((x + t[0], y + t[1], z + t[2])):
                lo[k] = min(lo[k], c); hi[k] = max(hi[k], c)
        out[nm] = dict(translation=[round(c, 3) for c in t], rotation=[round(c, 4) for c in tr["r"]],
                       scale=[round(c, 5) for c in tr["s"]])
        if any(abs(c) > 1e-3 for c in tr["r"]) or any(abs(c - 1) > 1e-4 for c in tr["s"]):
            problems.append("%s node has rotation/scale" % nm)
        if nm in exp:
            d = max(abs(a - b) for a, b in zip(t, exp[nm]["pivot_studs"]))
            if d > 0.01:
                problems.append("%s raw pivot off by %.3f studs" % (nm, d))
    fus = exp.get("Fuselage")
    nose_z = None
    for mid, (nm, tr) in models.items():
        if nm == "Fuselage":
            vs = geoms[link[mid]]
            nose = min(vs, key=lambda q: q[2])
            tail = max(vs, key=lambda q: q[2])
            nose_z = (round(nose[2] + tr["t"][2], 3), round(tail[2] + tr["t"][2], 3))
    wl = out.get("Wing_L", {}).get("translation", [0])[0]
    return dict(global_settings={k: gs.get(k) for k in ("UpAxis", "UpAxisSign", "FrontAxis", "FrontAxisSign",
                                                       "CoordAxis", "CoordAxisSign", "UnitScaleFactor")},
                bbox_min_studs=[round(c, 3) for c in lo], bbox_max_studs=[round(c, 3) for c in hi],
                bbox_size_studs=[round(h - l, 3) for h, l in zip(hi, lo)],
                fuselage_nose_z_tail_z=nose_z,
                orientation=("nose -Z, port wing -X, up +Y (matches Roblox: LookVector -Z, RightVector +X)"
                             if nose_z and nose_z[0] < 0 < nose_z[1] and wl < 0 else "UNEXPECTED"),
                node_count=len(models), problems=problems, nodes=out)


def reimport_check():
    man = json.load(open(os.path.join(OUT, "manifest.json")))
    exp = {o["name"]: o for o in man["objects"]}
    res = {}
    for kind, path in (("fbx", fbx_path), ("obj", obj_path)):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        if kind == "fbx":
            # axes are read from the file's GlobalSettings; bake the Y-up -> Z-up conversion into the
            # mesh data so object rotations stay (0,0,0) exactly as they are stored in the file
            bpy.ops.import_scene.fbx(filepath=path, use_custom_normals=True, bake_space_transform=True)
        else:
            bpy.ops.wm.obj_import(filepath=path, forward_axis='Z', up_axis='Y')
        bpy.context.view_layer.update()
        obs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
        mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
        per = {}
        for o in obs:
            ws = [o.matrix_world @ v.co for v in o.data.vertices]
            lo = Vector((min(p.x for p in ws), min(p.y for p in ws), min(p.z for p in ws)))
            hi = Vector((max(p.x for p in ws), max(p.y for p in ws), max(p.z for p in ws)))
            mn = Vector((min(mn.x, lo.x), min(mn.y, lo.y), min(mn.z, lo.z)))
            mx = Vector((max(mx.x, hi.x), max(mx.y, hi.y), max(mx.z, hi.z)))
            tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
            # Blender (x,y,z) -> expected Roblox (X=-x, Y=z, Z=y)
            loc = o.matrix_world.translation
            _bm = bmesh.new(); _bm.from_mesh(o.data)
            vol = _bm.calc_volume(signed=True)
            nonman = sum(1 for e in _bm.edges if not e.is_manifold)
            _bm.free()
            per[o.name] = dict(triangles=tris, pivot_roblox=[round(-loc.x, 3), round(loc.z, 3), round(loc.y, 3)],
                               signed_volume_studs3=round(vol, 3), non_manifold_edges=nonman,
                               has_vertex_colors=len(o.data.color_attributes) > 0,
                               scale=[round(v, 4) for v in o.matrix_world.to_scale()],
                               rotation_deg=[round(math.degrees(a), 3) for a in o.matrix_world.to_euler()])
        size = mx - mn
        r = dict(object_count=len(obs),
                 bbox_size_studs=dict(span_X=round(size.x, 3), height_Y=round(size.z, 3), length_Z=round(size.y, 3)),
                 bbox_size_m=dict(span=round(size.x * STUD_M, 3), height=round(size.z * STUD_M, 3),
                                  length=round(size.y * STUD_M, 3)),
                 min_height_studs=round(mn.z, 4), nose_direction="-Y blender" if (mn.y + mx.y) / 2 < 0.01 and
                 abs(mn.y) > 0 else "?", total_triangles=sum(v["triangles"] for v in per.values()))
        if kind == "fbx":
            mism = []
            for n, e in exp.items():
                if n not in per:
                    mism.append("missing " + n)
                    continue
                d = max(abs(a - b) for a, b in zip(per[n]["pivot_roblox"], e["pivot_studs"]))
                if d > 0.01:
                    mism.append("%s pivot off by %.3f studs" % (n, d))
                if per[n]["signed_volume_studs3"] <= 0:
                    mism.append("%s has inward normals / zero volume" % n)
                if per[n]["non_manifold_edges"]:
                    mism.append("%s non-manifold after re-import" % n)
                if per[n]["triangles"] != e["triangles"]:
                    mism.append("%s tris %d != %d" % (n, per[n]["triangles"], e["triangles"]))
                if any(abs(s - 1) > 1e-4 for s in per[n]["scale"]) or any(abs(a) > 1e-3 for a in per[n]["rotation_deg"]):
                    mism.append("%s has unapplied transform" % n)
            r["mismatches_vs_manifest"] = mism
            r["max_triangles_single_object"] = max(v["triangles"] for v in per.values())
            r["objects"] = per
        res[kind] = r
    res["fbx_raw"] = raw_fbx_check(fbx_path, exp)
    with open(os.path.join(OUT, "import_check.json"), "w") as f:
        json.dump(res, f, indent=2)
    print("REIMPORT FBX:", res["fbx"]["object_count"], "objects", res["fbx"]["bbox_size_studs"], res["fbx"]["bbox_size_m"],
          "tris", res["fbx"]["total_triangles"], "mismatches", res["fbx"]["mismatches_vs_manifest"])
    print("REIMPORT OBJ:", res["obj"]["object_count"], "objects", res["obj"]["bbox_size_m"], "tris", res["obj"]["total_triangles"])
    print("RAW FBX:", res["fbx_raw"]["orientation"], res["fbx_raw"]["bbox_size_studs"], res["fbx_raw"]["global_settings"],
          "problems", res["fbx_raw"]["problems"])


reimport_check()
print("ALL DONE")
