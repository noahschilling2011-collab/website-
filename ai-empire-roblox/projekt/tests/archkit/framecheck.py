import json, sys
import numpy as np
from doorcheck_lib import cfm, obb_overlap
d = json.load(open(sys.argv[1]))
inst = d["instances"]
walls = [i for i in inst if "cframe" in i and i["path"].startswith("Office/Walls/") and i.get("canCollide")]
W = np.array([w["cframe"][:3] for w in walls])
for door in [i for i in inst if i["class"] == "Model" and "DoorId" in i.get("attrs", {})]:
    parts = [p for p in inst if "cframe" in p and p["path"].startswith(door["path"] + "/") and p.get("canCollide")]
    if not parts:
        continue
    fc = np.mean([p["cframe"][:3] for p in parts], axis=0)
    near = [walls[k] for k in np.where(np.linalg.norm(W - fc, axis=1) < 40)[0]]
    hits = set()
    for p in parts:
        for w in near:
            dep = obb_overlap(cfm(p["cframe"]), p["size"], cfm(w["cframe"]), w["size"])
            if dep > 0.03:
                hits.add((p["path"].split("/", 3)[-1], w["path"].split("/")[-2], round(dep, 2)))
    if hits:
        print(door["name"], door["attrs"]["DoorKind"], sorted(hits)[:4])
