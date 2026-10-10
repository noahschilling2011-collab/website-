#!/usr/bin/env python3
"""crop.py dump.json out.json x0,x1,z0,z1 [--drop Name,Name]  -> keeps parts whose centre lies in the box."""
import json, sys
src, dst, box = sys.argv[1], sys.argv[2], [float(v) for v in sys.argv[3].split(",")]
drop = set(sys.argv[sys.argv.index("--drop") + 1].split(",")) if "--drop" in sys.argv else set()
d = json.load(open(src))
import numpy as np
def cfm(a):
    M = np.eye(4); M[:3, 3] = a[:3]; M[:3, :3] = np.array(a[3:12]).reshape(3, 3); return M
if "--open" in sys.argv:  # move every door leaf to its OpenPivot
    leaves = {i["path"]: i for i in d["instances"] if i["class"] == "Model" and "OpenPivot" in i.get("attrs", {})}
    for inst in d["instances"]:
        if "cframe" not in inst:
            continue
        for lp, leaf in leaves.items():
            if inst["path"].startswith(lp + "/"):
                T = cfm(leaf["attrs"]["OpenPivot"]["CFrame"]) @ np.linalg.inv(cfm(leaf["attrs"]["ClosedPivot"]["CFrame"]))
                M = T @ cfm(inst["cframe"])
                inst["cframe"] = list(M[:3, 3]) + list(M[:3, :3].reshape(9))
out = []
for inst in d["instances"]:
    if "cframe" in inst:
        x, y, z = inst["cframe"][0], inst["cframe"][1], inst["cframe"][2]
        if inst["name"] in drop:
            continue
        if not (box[0] <= x <= box[1] and box[2] <= z <= box[3]):
            continue
    out.append(inst)
d["instances"] = out
json.dump(d, open(dst, "w"))
print(len(out), "instances kept")
