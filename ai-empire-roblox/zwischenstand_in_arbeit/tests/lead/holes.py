#!/usr/bin/env python3
"""Hole check: sample every walkable footprint of every level on a 0.5-stud grid and look straight
down from 1.2 above the level to 3 below it. A sample with no collidable part in that band is a
place where somebody would fall (a hole). Planned openings (lift shaft, stair core, atrium void,
reception void, ramp channel) are excluded. Usage: holes.py dump_tierN.json [png_prefix]"""
import sys, numpy as np
sys.path.insert(0, __import__("os").path.join(__import__("os").path.dirname(__file__), "..", "..", "harness"))
from dumplib import Dump, vertical_line_hits

FH = 16
MAIN = (-82, 82, -48, 80); PAV = (-82, 82, 80, 160); GAR = (-94, 112, -64, 88); SITE = (-142, 145, -217, 228)
SHAFT = (-7, 7, 54, 68); STAIR = (-22, -7, 54, 80); ATRIUM = (-14, 14, -16, 36); LVOID = (-22, 22, -48, -24)
RAMP = (92, 112, -146, -36); FOUNDER_FRONT_Z = -32
# guest house (hotel annex, BuildingPlan.HOTEL) and its stair void on level 1; garage stage (plan tier 0)
HOTEL = (-141, -98, 76, 172); HOTEL_STAIR_VOID = (-141, -124.5, 83, 101.5)
RES = 0.5

def main():
    D = Dump(sys.argv[1])
    prefix = sys.argv[2] if len(sys.argv) > 2 else None
    floors = D.floors(); founder = floors - 1; roof = floors
    garage_stage = D.meta.get("tier") == 0 or (D.inst[0].get("attrs") or {}).get("GarageStage") is True
    hotel = any(i.get("path", "").endswith("/Rooms/H0_LOBBY") for i in D.inst)
    sel = np.where(D.collide & ~D.character)[0]
    lo_all, hi_all = D.aabb(sel)
    def zones(level):
        if garage_stage:
            return [SITE] if level == 0 else []  # one storey on the site; no B1, the flat roof is not walkable
        extra = [HOTEL] if hotel and level in (1, 2) else []  # guest house first floor and closed roof
        if level == -1: return [GAR]
        if level == 0: return [SITE]
        if level == 1: return [MAIN, PAV] + extra
        if level == 2: return [MAIN, PAV] + extra  # pavilion roof garden is walkable
        if level == roof: return [(MAIN[0], MAIN[1], FOUNDER_FRONT_Z, MAIN[3])]
        return [MAIN]
    def planned(level, X, Z):
        def inr(r, m=0.0): return (X > r[0] + m) & (X < r[1] - m) & (Z > r[2] + m) & (Z < r[3] - m)
        m = inr(SHAFT) | inr(STAIR)
        if 1 <= level <= roof: m |= inr(ATRIUM)
        if level == 1: m |= inr(LVOID)
        if level == 0 and not garage_stage: m |= inr(RAMP)
        if level == -1: m |= inr(RAMP)  # ramp foot enters the garage through the front wall opening
        if hotel and level == 1: m |= inr(HOTEL_STAIR_VOID)
        if garage_stage: m = inr((0, 0, 0, 0))  # the garage stage has no core, atrium or ramp openings
        return m
    total = 0
    for level in (range(0, 1) if garage_stage else range(-1, roof + 1)):
        y = level * FH
        ylo, yhi = y - 3.0, y + 1.2
        for zi, (x1, x2, z1, z2) in enumerate(zones(level)):
            xs = np.arange(x1 + RES / 2, x2, RES); zs = np.arange(z1 + RES / 2, z2, RES)
            X, Z = np.meshgrid(xs, zs, indexing="ij")
            covered = np.zeros(X.shape, dtype=bool)
            band = (hi_all[:, 1] >= ylo) & (lo_all[:, 1] <= yhi) & (hi_all[:, 0] >= x1) & (lo_all[:, 0] <= x2) & (hi_all[:, 2] >= z1) & (lo_all[:, 2] <= z2)
            for j in sel[band]:
                k = np.searchsorted(sel, j)
                a = max(0, int(np.floor((lo_all[k, 0] - x1) / RES)) - 1); b = min(len(xs), int(np.ceil((hi_all[k, 0] - x1) / RES)) + 1)
                c = max(0, int(np.floor((lo_all[k, 2] - z1) / RES)) - 1); d = min(len(zs), int(np.ceil((hi_all[k, 2] - z1) / RES)) + 1)
                if a >= b or c >= d: continue
                sub = covered[a:b, c:d]
                if sub.all(): continue
                hit, t0, t1 = vertical_line_hits(D.P[j], D.R[j], D.S[j], D.shape[j], X[a:b, c:d].ravel(), Z[a:b, c:d].ravel())
                ok = hit & (t1 >= ylo) & (t0 <= yhi)
                covered[a:b, c:d] |= ok.reshape(sub.shape)
            holes = ~covered & ~planned(level, X, Z)
            n = int(holes.sum())
            if n == 0:
                print(f"level {level:>2} zone {zi}: no holes ({covered.size} samples)")
                continue
            # connected components (4-neighbour) for a readable report
            from collections import deque
            seen = np.zeros_like(holes); comps = []
            for i0, k0 in zip(*np.where(holes)):
                if seen[i0, k0]: continue
                q = deque([(i0, k0)]); seen[i0, k0] = True; cells = []
                while q:
                    i, k = q.popleft(); cells.append((i, k))
                    for di, dk in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ii, kk = i + di, k + dk
                        if 0 <= ii < holes.shape[0] and 0 <= kk < holes.shape[1] and holes[ii, kk] and not seen[ii, kk]:
                            seen[ii, kk] = True; q.append((ii, kk))
                ci = np.array(cells)
                comps.append((len(cells), xs[ci[:, 0]].min(), xs[ci[:, 0]].max(), zs[ci[:, 1]].min(), zs[ci[:, 1]].max()))
            comps.sort(reverse=True)
            total += n
            print(f"level {level:>2} zone {zi}: {n} hole samples ({n * RES * RES:.1f} sq studs) in {len(comps)} patches")
            for c in comps[:12]:
                print(f"     {c[0] * RES * RES:7.2f} sq  x {c[1]:7.2f}..{c[2]:7.2f}  z {c[3]:7.2f}..{c[4]:7.2f}")
    print(f"TOTAL hole area {total * RES * RES:.1f} sq studs")

main()
