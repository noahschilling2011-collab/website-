import json, sys
import numpy as np
from doorcheck_lib import cfm, obb_overlap
d = json.load(open(sys.argv[1]))
inst = d["instances"]
parts = [i for i in inst if "cframe" in i]
for m in [i for i in inst if i["class"] == "Model" and i.get("attrs", {}).get("WorkstationType") == "Computer"]:
    a = m["attrs"]
    ip = np.array(a["InteractionPosition"]["Vector3"])
    sp = cfm(a["SeatPosition"]["CFrame"])
    mine = [p for p in parts if p["path"].startswith(m["path"] + "/")]
    seat = [p for p in mine if p["name"] == "ChairSeat"][0]
    screen = [p for p in mine if p["name"] == "DisplayContent"][0]
    look = -sp[:3, 2]
    to_screen = np.array(screen["cframe"][:3]) - sp[:3, 3]
    to_screen[1] = 0
    facing = look @ (to_screen / np.linalg.norm(to_screen))
    # agent capsule at IP: box 2 x 4.6 x 2 centred 0.5 above IP (feet at IP.y-2.8)
    agent = np.eye(4); agent[:3, 3] = ip + np.array([0, -0.3, 0])
    hits = [p["name"] for p in parts if p.get("canCollide") and p["name"] != "Floor" and obb_overlap(agent, [1.6, 4.4, 1.6], cfm(p["cframe"]), p["size"]) > 0.02]
    sf = cfm(screen["cframe"]); scr_look = -sf[:3, 2]
    to_seat = sp[:3, 3] - sf[:3, 3]; to_seat[1] = 0
    prompts = [i for i in inst if i["class"] == "ProximityPrompt" and i["parentPath"].startswith(m["path"])]
    print(f"{m['name']:14s} style={a.get('WorkstationStyle'):9s} seatY={sp[1,3]:.2f} seat faces screen={facing:+.2f} screen faces seat={scr_look @ (to_seat/np.linalg.norm(to_seat)):+.2f} "
          f"canTouch={seat.get('canTouch')} IP->seat {np.linalg.norm((ip - sp[:3,3])[[0,2]]):.2f} IP blocked by {hits} tags={m.get('tags')} prompts={[ (p['attrs'].get('CampusAction'), p['attrs'].get('App'), p.get('maxActivationDistance')) for p in prompts]}")
