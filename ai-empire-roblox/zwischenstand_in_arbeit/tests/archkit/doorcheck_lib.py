#!/usr/bin/env python3
"""Door geometry checks on a harness dump: closed/open leaf vs frame/wall overlaps, opening side, hinge."""
import json, sys
import numpy as np

def cfm(a):
    M = np.eye(4); M[:3, 3] = a[:3]; M[:3, :3] = np.array(a[3:12]).reshape(3, 3); return M

def obb_overlap(A, sa, B, sb, tol=0.02):
    """SAT test; returns penetration depth (>tol means real overlap)."""
    Ra, Rb = A[:3, :3], B[:3, :3]
    ha, hb = np.array(sa) / 2, np.array(sb) / 2
    t = B[:3, 3] - A[:3, 3]
    axes = [Ra[:, i] for i in range(3)] + [Rb[:, i] for i in range(3)]
    for i in range(3):
        for j in range(3):
            c = np.cross(Ra[:, i], Rb[:, j])
            if np.linalg.norm(c) > 1e-6:
                axes.append(c / np.linalg.norm(c))
    depth = 1e9
    for ax in axes:
        ra = sum(ha[k] * abs(ax @ Ra[:, k]) for k in range(3))
        rb = sum(hb[k] * abs(ax @ Rb[:, k]) for k in range(3))
        d = ra + rb - abs(t @ ax)
        if d <= tol:
            return 0.0
        depth = min(depth, d)
    return depth

