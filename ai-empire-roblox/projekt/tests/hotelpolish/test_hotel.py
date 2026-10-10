#!/usr/bin/env python3
"""Package "hotelpolish" - the company guest house reads as a real small hotel. Checks the harness dumps
in --out (dump_tierN.json + check_tierN.txt from `harness/run.sh --check`, baseline base/dump_tier2.json
built with the pre-package RoomKitsHotel/ExteriorDesign):
  * budgets: guest house + approach <= +300 parts vs. the baseline, guest house <= 16 lights, approach
    lights (Site/WestPathLights) <= 4 and all real lights together <= +4
  * lobby: two-station counter (>= 8 long, stone ledge, fluting, brass name plate), back wall with the
    company SurfaceGui line + a "GUEST HOUSE" SurfaceGui line (no built letters left: parts freed), a key-cubby
    grid with every guest-room number (one backlit SurfaceGui),
    lounge (sofa + 2 armchairs = Waiting seats Wait1..4, coffee table, rugs, floor lamp), pendants with a
    real light, plants, luggage trolley, concierge desk + sign, artwork, door mat; operations post 13
    with its job points and the printer prop; the reception and printer prompts
  * lobby details (review round 2): the table lamp stands on the side table (stem from the table top
    into the shade), the plants' foliage stays inside the room (north wall z 103.5, east glass x -98,
    south glass z 76), rug fields 0.05 above their borders and borders 0.05 above the floor
  * rooms: framed print (paper part + SurfaceGui picture: frames, one round via UICorner), dark TV set
    (not Neon) with the welcome page (company + room name) and curtains in all 12 rooms, rug steps;
    breakfast buffet (chafing dish, bread, fruit, menu board with the 8:00 - 10:30 hours), coffee prompt
  * exterior: built neon "GUEST HOUSE" on the south and west parapets (38 strokes each, decor, reading
    left to right for a viewer in front of the face, inside the site box, standing on the coping), the
    company band on the south sign, a dark metal backing plate behind each word (between the letters and
    the rail cap, covering every letter), canopy names + one SpotLight, the WestPath lane clear (no sign
    post), approach lamps outside the lane with 3 PointLights, the colonnade sign above head height,
    the blade sign on the corner pier (faces +-Z, name on both faces, neon edge, above head height, inside
    the window under the colonnade soffit and actually visible: rays from eye points in the colonnade
    and on the plaza edge reach it), shrubs clear of the HQ (x <= -84.6), forecourt/runner overlays
    stepped >= 0.05
  * every new decor part non-colliding / non-query / non-touch / no shadow
  * reachability (check report): every guest-house target reachable, nothing outside the site box;
    tier 2 holes = 0 (tests/lead/holes.py)
  * receptionist hops (stand <-> greet <-> printer): probes standable + connected (agent radius 1.0) and
    a radius-1.0 body touches no collidable part on the straight line (like tests/buildings)
  * NEGATIVE: a hop straight through the counter must be reported by both hop checks
  * review round 3: room drapes 3.2 wide in one warm colour and a white sheer across each window,
    clear of desk / desk legs / nightstands / headboard / side walls / facade glass; window-side nightstand clear of headboard and curtain; matching
    lounge armchairs; sheer curtain behind the lounge; text boards 100 px per stud (out/gui_tier2.json);
    the canopy's south end without text (the blade sign names the house there); the entrance camera under the
    soffit against the facade; the art screen on the entrance axis (plant clear of it); window boxes with
    flowers under the west rooms on both floors and under rooms 205 / 208 on the north cornice (inside the site
    box, clear of the glass, the flowers in front)
Usage: python3 tests/hotelpolish/test_hotel.py --out DIR [--tiers 2,3,4]
"""
import argparse, json, math, os, re, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
H = os.path.join(ROOT, "harness")
sys.path.insert(0, H)
import numpy as np
from dumplib import Dump, vertical_line_hits

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--tiers", default="2,3,4")
a = ap.parse_args()
passed = failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print(f"FAIL  {name}" + (f"  -- {detail}" if detail != "" else ""))


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    return r.returncode, r.stdout + r.stderr


HOTEL_PATH = re.compile(r"/(H[01]_[A-Z0-9_]+)|Door_H[01]_|Facade_Hotel|GuestHouse|HotelRoof")
APPROACH = re.compile(r"/Site/WestPathLights/")
LIGHTS = ("PointLight", "SpotLight", "SurfaceLight")
RIG = re.compile(r"/(Employees|OperationsEmployees|Assistant|Visitors)/")
TARGETS = ("workstations", "seats", "door models (both sides)", "doors (both sides)", "proximity prompts", "navigation nodes")
COMPANY = "Nimbus Labs"  # harness session company (harness/README.md)
CURTAIN_RGB = [170 + (198 - 170) * 0.35, 110 + (184 - 110) * 0.35, 84 + (160 - 84) * 0.35]  # terracotta:Lerp(fabricSand, 0.35), warm, darker than the sheer
WORD = [5, 3, 4, 5, 2, 3, 4, 3, 5, 4]  # strokes per letter of "GUEST HOUSE" in reading order
# decor added by this package (must not collide / query / touch / cast shadows)
DECOR = {"SignLetter", "SignRule", "WallWash", "WallWashCove", "ReceptionFlute", "ReceptionPanel", "ReceptionGlow", "PendantGlobe",
         "PendantCable", "DrumShade", "DrumDiffuser", "ArtPrint", "Curtain", "BudVase", "Bloom", "ChafingDish",
         "BreadBasket", "BreadRoll", "FruitBowl", "Fruit", "SneezeGuard", "MenuBoard", "ParapetNameBand", "FlowerHedge", "FlowerBox",
         "HotelCanopyGlow", "HotelCanopyLight", "TensionRod", "BayTreeStem", "BayTreeCrown", "BedShrub", "LampGlow",
         "ColonnadeHangingSign", "HangingSignRod", "EntranceForecourt", "EntranceRunner", "EntranceLantern", "EntranceLanternPlate", "ConciergeSign", "Brochure", "KeyCard", "KeyRack",
         "TrolleyCarpet", "TrolleyWheel", "TrolleyPost", "TrolleyRail", "Suitcase", "GarmentBag", "EntranceMat", "Rug", "RugBorder",
         "SignBacking", "BladeSign", "BladeSignGlow", "TableLampStem", "DeskBell",
         "LobbyHouseWord", "KeyRackFrame", "SheerCurtain", "CurtainTrack", "ArtScreen", "ArtScreenFrame",
         "WindowBox", "WindowBoxGreen", "WindowBoxBloom", "WindowSheer"}


def load(path):
    D = json.load(open(path))
    inst = D["instances"]
    by_id = {i["id"]: i for i in inst}
    kids = {}
    for i in inst:
        kids.setdefault(i.get("parent"), []).append(i)
    return inst, by_id, kids


def texts_under(kids, node):
    out, stack = [], [node["id"]]
    while stack:
        for c in kids.get(stack.pop(), []):
            if "text" in c:
                out.append(c["text"])
            stack.append(c["id"])
    return out


def gui_of(kids, node, name=None):
    return [c for c in kids.get(node["id"], []) if c["class"] == "SurfaceGui" and (name is None or c["name"] == name)]


def overlap(a, b, eps=0.005):
    A, B = lo_hi(a), lo_hi(b)
    return all(min(A[k][1], B[k][1]) - max(A[k][0], B[k][0]) > eps for k in range(3))


def counts(inst):
    parts = [i for i in inst if "size" in i and (HOTEL_PATH.search(i["path"]) or APPROACH.search(i["path"]))]
    lights = [i for i in inst if i["class"] in LIGHTS]
    return len(parts), [i for i in lights if HOTEL_PATH.search(i["path"])], [i for i in lights if APPROACH.search(i["path"])]


def named_inst(inst, n, where=""):
    return [i for i in inst if i["name"] == n and where in i["path"]]


def letters_order(strokes, axis, sign):
    """Group strokes along `axis` (0 = x, 2 = z) into letters (gap > 0.05) and return the stroke counts in
    reading order (`sign` = +1: reading towards +axis)."""
    spans = sorted(((s["cframe"][axis] - abs(extent(s, axis)), s["cframe"][axis] + abs(extent(s, axis))) for s in strokes), key=lambda t: t[0])
    groups = []
    for lo, hi in spans:
        if groups and lo <= groups[-1][1] + 0.05:
            groups[-1][1] = max(groups[-1][1], hi)
            groups[-1][2] += 1
        else:
            groups.append([lo, hi, 1])
    order = [g[2] for g in groups]
    return order if sign > 0 else order[::-1]


def extent(p, axis):
    """Half extent of an oriented box along a world axis."""
    r = p["cframe"][3:]
    R = [[r[0], r[1], r[2]], [r[3], r[4], r[5]], [r[6], r[7], r[8]]]
    return sum(abs(R[axis][k]) * p["size"][k] / 2 for k in range(3))


def lo_hi(p):
    return [(p["cframe"][k] - extent(p, k), p["cframe"][k] + extent(p, k)) for k in range(3)]


def unreachable(report, categories):
    out, cat = {}, None
    for line in report.splitlines():
        m = re.match(r"UNREACHABLE (.+?) \(\d+\):", line)
        if m:
            cat = m.group(1) if m.group(1) in categories else None
            continue
        if cat and line.startswith("   "):
            out.setdefault(cat, []).append(line.strip())
        elif not line.startswith("   "):
            cat = None
    return out


def probe(dump_path, segs, step=1.0):
    D = json.load(open(dump_path))
    inst = D["instances"]
    office_id = inst[0]["id"]
    next_id = max(x["id"] for x in inst) + 1
    labels = {}
    for si, (label, pa, pb) in enumerate(segs):
        dx, dy, dz = pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2]
        n = max(1, int((dx * dx + dz * dz) ** 0.5 / step))
        for k in range(n + 1):
            t = k / n
            name = f"HopProbe_{label}_{si}_{k}"
            labels[name] = (label, si)
            inst.append({"id": next_id, "parent": office_id, "path": f"Office/{name}", "parentPath": "Office", "class": "Model", "name": name,
                         "attrs": {"InteractionPosition": {"Vector3": [pa[0] + dx * t, pa[1] + dy * t, pa[2] + dz * t]}}})
            next_id += 1
    with tempfile.TemporaryDirectory() as tmp:
        synth = os.path.join(tmp, "probe.json")
        json.dump(D, open(synth, "w"))
        rc, rep = run([sys.executable, os.path.join(H, "check_geometry.py"), synth, "--radius", "1.0", "--no-images", "--verbose"])
    blocked = set()
    for line in unreachable(rep, ("workstations",)).get("workstations", []):
        m = re.search(r"Office/(HopProbe_[^ ]+) at", line)
        if m:
            blocked.add(labels[m.group(1)])
    return blocked, "== SUMMARY" in rep


def corridor(D, segs, r=1.0, step=0.25):
    door = np.array(["/Doors/" in D.inst[int(k)]["path"] for k in D.pidx])
    sel = np.where(D.collide & ~D.character & ~door & (np.array(D.group) == "Default"))[0]
    lo, hi = D.aabb(sel)
    ang = np.linspace(0, 2 * np.pi, 9)[:-1]
    out = {}
    for si, (_, pa, pb) in enumerate(segs):
        A, B = np.array(pa), np.array(pb)
        n = max(1, int(np.hypot(B[0] - A[0], B[2] - A[2]) / step))
        pts = [A + (B - A) * (k / n) for k in range(n + 1)]
        yf = min(A[1], B[1]) - 2.8
        near = (hi[:, 0] >= min(A[0], B[0]) - r - 0.1) & (lo[:, 0] <= max(A[0], B[0]) + r + 0.1) & \
               (hi[:, 2] >= min(A[2], B[2]) - r - 0.1) & (lo[:, 2] <= max(A[2], B[2]) + r + 0.1) & \
               (hi[:, 1] >= yf + 0.3) & (lo[:, 1] <= yf + 5.0)
        xs = np.concatenate([[p[0] for p in pts]] + [[p[0] + r * np.cos(t) for p in pts] for t in ang])
        zs = np.concatenate([[p[2] for p in pts]] + [[p[2] + r * np.sin(t) for p in pts] for t in ang])
        centre = np.zeros(len(xs), dtype=bool)
        centre[: len(pts)] = True
        band_lo = np.where(centre, yf + 0.3, yf + 1.6)
        for j in sel[near]:
            hit, t0, t1 = vertical_line_hits(D.P[j], D.R[j], D.S[j], D.shape[j], xs, zs)
            if np.any(hit & (t1 >= band_lo + 0.05) & (t0 <= yf + 5.0)):
                out[si] = D.inst[int(D.pidx[j])]["path"]
                break
    return out


def ray_blocked(D, sel, o, q, skip):
    """True if the segment o -> q hits any oriented box in `sel` (except indices in `skip`)."""
    o, q = np.array(o, float), np.array(q, float)
    d = q - o
    for j in sel:
        if j in skip:
            continue
        lo_ = (o - D.P[j]) @ D.R[j]
        dd = d @ D.R[j]
        h = D.S[j] / 2
        t0, t1 = 0.0, 1.0
        ok = True
        for k in range(3):
            if abs(dd[k]) < 1e-9:
                if abs(lo_[k]) > h[k]:
                    ok = False
                    break
            else:
                a_, b_ = (-h[k] - lo_[k]) / dd[k], (h[k] - lo_[k]) / dd[k]
                if a_ > b_:
                    a_, b_ = b_, a_
                t0, t1 = max(t0, a_), min(t1, b_)
                if t0 > t1:
                    ok = False
                    break
        if ok and t1 > 1e-4 and t0 < 1 - 1e-4:
            return True
    return False


def ball_r(p):
    return p["size"][0] / 2


def v3(attr):
    return attr["Vector3"] if isinstance(attr, dict) and "Vector3" in attr else None


tiers = [int(t) for t in a.tiers.split(",")]
base_path = os.path.join(a.out, "base", "dump_tier2.json")
base = counts(load(base_path)[0]) if os.path.exists(base_path) else None
check("baseline dump (pre-package files) present", base is not None, base_path)

for tier in tiers:
    path = os.path.join(a.out, f"dump_tier{tier}.json")
    if not os.path.exists(path):
        check(f"tier {tier} dump present", False, path)
        continue
    inst, by_id, kids = load(path)
    T = f"tier {tier}"
    parts = [i for i in inst if "size" in i]
    named = lambda n, where="": [p for p in parts if p["name"] == n and where in p["path"]]

    # ---- budgets
    n, hl, al = counts(inst)
    if base:
        n0, hl0, al0 = base
        print(f"{T}: guest house + approach {n} parts ({n - n0:+d} vs baseline {n0}), lights: guest house {len(hl)}, approach {len(al)} (baseline {len(hl0)} + {len(al0)})")
        check(f"{T}: <= +300 parts", n - n0 <= 300, n - n0)
        check(f"{T}: real lights <= +4", len(hl) + len(al) - len(hl0) - len(al0) <= 4, len(hl) + len(al) - len(hl0) - len(al0))
    check(f"{T}: guest house <= 16 lights", len(hl) <= 16, len(hl))
    check(f"{T}: approach lights <= 4", len(al) <= 4, len(al))

    # ---- lobby
    L = "/Rooms/H0_LOBBY/"
    front = named("ReceptionFront", L)
    check(f"{T}: reception counter >= 8 long", len(front) == 1 and front[0]["size"][2] >= 7.8, front and front[0]["size"])
    ledge = named("ReceptionLedge", L)
    check(f"{T}: stone (marble) transaction ledge", len(ledge) == 1 and ledge[0]["material"] == "Marble", ledge and ledge[0]["material"])
    check(f"{T}: fluted counter front", len(named("ReceptionFlute", L)) >= 4, len(named("ReceptionFlute", L)))
    plate = named("ReceptionPanel", L)
    check(f"{T}: brass RECEPTION plate", len(plate) == 1 and "RECEPTION" in texts_under(kids, plate[0]), plate and texts_under(kids, plate[0]))
    seats = [p for p in inst if p["class"] == "Seat" and L in p["path"] and p["cframe"][0] < -112 and 94 < p["cframe"][2] < 104]
    check(f"{T}: two staff stations behind the counter", len(seats) >= 2, len(seats))
    check(f"{T}: two staff monitors", len(named("StaffMonitor", L)) == 2, len(named("StaffMonitor", L)))
    sign = named("LobbyHouseSign", L)
    check(f"{T}: company line on the back wall (SurfaceGui)", len(sign) == 1 and COMPANY.upper() in texts_under(kids, sign[0]), sign and texts_under(kids, sign[0]))
    word = named("LobbyHouseWord", L)
    wg = gui_of(kids, word[0]) if word else []
    check(f"{T}: GUEST HOUSE line on the back wall (SurfaceGui facing the lobby, clear carrier)",
          len(word) == 1 and "GUEST HOUSE" in texts_under(kids, word[0]) and -115.55 < word[0]["cframe"][0] < -115.3 and len(wg) == 1 and wg[0].get("face") == "Right"
          and word[0].get("transparency", 0) >= 0.99, word and (texts_under(kids, word[0]), word[0]["cframe"][:3], [g.get("face") for g in wg]))
    check(f"{T}: no built letters left in the lobby (parts freed for the facade)", not named("SignLetter", L), len(named("SignLetter", L)))
    if word and sign:
        check(f"{T}: GUEST HOUSE line under the company line", lo_hi(word[0])[1][1] <= lo_hi(sign[0])[1][0] + 1e-6, (lo_hi(word[0])[1], lo_hi(sign[0])[1]))
    rack = named("KeyRack", L)
    room_numbers = sorted(int(m.group(1)) for i in inst if i["class"] == "Model" and re.match(r"H[01]_R\d\d$", i["name"])
                          for m in [re.search(r"(\d+)$", i.get("attrs", {}).get("RoomName", ""))] if m)
    kg = gui_of(kids, rack[0], "KeyGrid") if rack else []
    nums = sorted(int(t) for t in texts_under(kids, rack[0]) if t.isdigit()) if rack else []
    cubbies = [c for c in inst if c["class"] == "Frame" and re.match(r"Cubby\d+$", c["name"]) and c["path"].startswith(rack[0]["path"] + "/KeyGrid/")] if rack else []
    check(f"{T}: key-cubby grid: one cubby per guest room with its number (12)", len(kg) == 1 and kg[0].get("face") == "Right" and len(room_numbers) == 12 and nums == room_numbers
          and len(cubbies) == 12, (len(kg), nums, room_numbers))
    check(f"{T}: key tags hang in some cubbies, not all", 0 < len(named_inst(inst, "KeyTag", "/KeyRack/")) < 12, len(named_inst(inst, "KeyTag", "/KeyRack/")))
    check(f"{T}: no loose key-card parts (now in the grid)", not named("KeyCard", L))
    waits = [p for p in inst if p["class"] == "Model" and re.match(r"H0_LOBBY_Wait\d+$", p["name"])]
    check(f"{T}: lounge Waiting seats H0_LOBBY_Wait1..4 (sofa + 2 armchairs; ids documented in requests/buildings.md)",
          sorted(w["name"] for w in waits) == [f"H0_LOBBY_Wait{k}" for k in range(1, 5)], sorted(w["name"] for w in waits))
    check(f"{T}: coffee table", len(named("CoffeeTable", L)) == 1)
    check(f"{T}: >= 2 rugs", len(named("Rug", L)) >= 2, len(named("Rug", L)))
    check(f"{T}: floor lamp", len(named("LampShade", L)) >= 1)
    globes = named("PendantGlobe", L)
    lobby_lights = [i for i in inst if i["class"] in LIGHTS and L in i["path"] and "/FitOut/" in i["path"]]
    check(f"{T}: >= 3 pendant globes, one real light", len(globes) >= 3 and len(lobby_lights) == 1, (len(globes), len(lobby_lights)))
    check(f"{T}: >= 3 plants", len(named("Planter", L)) >= 3, len(named("Planter", L)))
    check(f"{T}: luggage trolley (deck, 4 wheels, luggage)", len(named("TrolleyDeck", L)) == 1 and len(named("TrolleyWheel", L)) == 4 and len(named("Suitcase", L)) >= 1)
    conc = named("ConciergeSign", L)
    check(f"{T}: concierge desk + sign", len(named("ConciergeDesk", L)) == 1 and len(conc) == 1 and "CONCIERGE" in texts_under(kids, conc[0]))
    check(f"{T}: artwork", len(named("Canvas", L)) >= 1)
    check(f"{T}: door mat", len(named("EntranceMat", L)) == 1)
    # review round 2: table lamp on the side table, plants inside the room, rug steps
    tbl, stem, shade = named("SideTable", L), named("TableLampStem", L), named("TableLampShade", L)
    if tbl and stem and shade:
        ttop = lo_hi(tbl[0])[1][1]
        (sy0, sy1), (hy0, hy1) = lo_hi(stem[0])[1], lo_hi(shade[0])[1]
        check(f"{T}: table lamp stem stands on the side table", abs(sy0 - ttop) <= 0.02, (sy0, ttop))
        check(f"{T}: table lamp shade sits on its stem (no gap)", hy0 <= sy1 + 1e-6 and hy0 >= sy0, (hy0, sy1))
        check(f"{T}: lamp stem thin and brass", stem[0]["size"][1] <= 0.2 and stem[0]["material"] == "Metal")
    else:
        check(f"{T}: side table + lamp stem + shade present", False, (len(tbl), len(stem), len(shade)))
    fol = [p for p in named("Foliage", L)]
    bad_f = []
    for p in fol:
        c, r = p["cframe"], ball_r(p)
        if c[2] + r > 103.5 + 1e-6 or c[0] + r > -98.0 + 1e-6 or c[2] - r < 76.0 - 1e-6:
            bad_f.append((round(c[0], 2), round(c[2], 2), r))
    check(f"{T}: lobby plant foliage inside the room (walls / facade glass)", fol and not bad_f, bad_f)
    # every plant ball (lobby + breakfast) clear of walls, facade/glazing and collidable furniture (sphere vs box, > 0.03)
    Dg = Dump(path)
    gp = [Dg.inst[int(k)]["path"] for k in Dg.pidx]
    obst = np.array([j for j in range(Dg.n) if (re.search(r"/Walls/|/Facade/", gp[j]) or (re.search(r"/Rooms/H0_(LOBBY|BREAKFAST)/FitOut/", gp[j]) and Dg.collide[j]))
                     and Dg.transp[j] < 0.99 and Dg.shape[j] == "Block" and not gp[j].endswith("/Planter")])
    olo, ohi = Dg.aabb(obst)
    clip = []
    for j in range(Dg.n):
        if Dg.name[j] != "Foliage" or not re.search(r"/Rooms/H0_(LOBBY|BREAKFAST)/FitOut/", gp[j]):
            continue
        c, r = Dg.P[j], Dg.S[j][0] / 2
        near_ = obst[np.all((ohi > c - r) & (olo < c + r), axis=1)]
        for k in near_:
            loc = (c - Dg.P[k]) @ Dg.R[k]
            hh = Dg.S[k] / 2
            dist = np.linalg.norm(loc - np.clip(loc, -hh, hh))
            if r - dist > 0.03:
                clip.append((gp[j].split("/")[2], gp[k].split("/")[-1], round(float(r - dist), 2)))
    check(f"{T}: lobby + breakfast plants clear of walls, glazing and furniture", not clip, clip[:4])
    pl_bad = [p["path"] for p in named("Planter", L) if lo_hi(p)[2][1] > 103.44 - 1e-6]
    check(f"{T}: lobby planters clear of the north wall skirting", not pl_bad, pl_bad)
    post = [p for p in inst if p["class"] == "Model" and p.get("attrs", {}).get("OpsIndex") == 13]
    check(f"{T}: operations post 13 in the lobby", len(post) == 1 and L in post[0]["path"])
    if post:
        at = post[0]["attrs"]
        check(f"{T}: post 13 job points greet + printer (prop HotelKeyPrinter), seated",
              v3(at.get("JobPoint_greet")) and v3(at.get("JobPoint_printer")) and at.get("JobProp_printer") == "HotelKeyPrinter" and "SeatPosition" in at, sorted(at))
    prompts = {i["path"].split("/")[-2] for i in inst if i["class"] == "ProximityPrompt" and L in i["path"]}
    check(f"{T}: reception + key-card printer prompts", {"ReceptionScreen", "KeyCardPrinter"} <= prompts, prompts)

    # rug steps (lobby and guest rooms): every Rug field 0.05 above the border it lies in, border 0.05 above the floor
    rugs_bad = []
    for rg in [p for p in parts if p["name"] == "Rug" and re.search(r"/Rooms/H[01]_", p["path"])]:
        par = rg["path"].rsplit("/", 1)[0]
        (x0, x1), (y0, y1), (z0, z1) = lo_hi(rg)
        bs = [b for b in parts if b["name"] == "RugBorder" and b["path"].rsplit("/", 1)[0] == par and
              lo_hi(b)[0][0] <= x0 + 1e-6 and lo_hi(b)[0][1] >= x1 - 1e-6 and lo_hi(b)[2][0] <= z0 + 1e-6 and lo_hi(b)[2][1] >= z1 - 1e-6]
        if len(bs) != 1:
            rugs_bad.append((rg["path"], "border?"))
            continue
        bt = lo_hi(bs[0])[1]
        if y1 - bt[1] < 0.05 - 1e-6 or bt[1] - bt[0] < 0.05 - 1e-6:
            rugs_bad.append((rg["path"], round(y1 - bt[1], 3), round(bt[1] - bt[0], 3)))
    check(f"{T}: rug overlays stepped >= 0.05 (lobby + rooms)", not rugs_bad, rugs_bad[:3])
    mat = named("EntranceMat", L)
    check(f"{T}: door mat >= 0.05 above the floor", mat and mat[0]["size"][1] >= 0.05 - 1e-6)

    # review round 3: lounge pair, sheer curtain, art screen on the entrance axis
    lounge = [p for p in named("ChairBase", L) if p["cframe"][2] < 86]
    sofa = named("SofaBase", L)
    check(f"{T}: lounge armchairs are a matching pair", len(lounge) == 2 and lounge[0]["color"] == lounge[1]["color"] and lounge[0]["material"] == lounge[1]["material"],
          [(p["color"], p["material"]) for p in lounge])
    check(f"{T}: lounge armchairs differ from the cream sofa", sofa and lounge and lounge[0]["color"] != sofa[0]["color"])
    sh, sb = named("SheerCurtain", L), named("SofaBack", L)
    if len(sh) == 1 and sb:
        (sx0, sx1), (sy0, sy1), (sz0, sz1) = lo_hi(sh[0])
        (bx0, bx1), _, (bz0, _) = lo_hi(sb[0])
        check(f"{T}: sheer curtain spans the sofa, between the south glass (z 76) and the sofa back", sx0 <= bx0 and sx1 >= bx1 and sz0 >= 76.0 + 0.05 and sz1 <= bz0 - 0.1,
              ((sx0, sx1), (sz0, sz1), (bx0, bx1), bz0))
        check(f"{T}: sheer curtain translucent fabric, floor to ceiling", 0.2 <= sh[0].get("transparency", 0) <= 0.5 and sh[0]["material"] == "Fabric" and sy0 <= 0.3 and sy1 >= 12.5,
              (sh[0].get("transparency"), sy0, sy1))
        hit = [p["path"].split("/")[-1] for p in parts if L in p["path"] and p is not sh[0] and p["name"] not in ("CurtainTrack",) and overlap(sh[0], p)]
        check(f"{T}: sheer curtain clear of furniture and plants", not hit, hit[:4])
    else:
        check(f"{T}: one sheer curtain", False, len(sh))
    scr, scf = named("ArtScreen", L), named("ArtScreenFrame", L)
    if len(scr) == 1 and len(scf) == 1:
        (fx0, fx1), (fy0, fy1), (fz0, fz1) = lo_hi(scf[0])
        pg = gui_of(kids, scr[0], "Print")
        frames = [c for c in inst if c["class"] == "Frame" and pg and c["path"].startswith(pg[0]["path"] + "/")]
        check(f"{T}: art screen on the entrance axis (z 90 +- 1 inside it), in front of the corridor glass", fz0 <= 89.5 and fz1 >= 91.5 and -115.94 < fx0 and fx1 < -115.4, ((fx0, fx1), (fz0, fz1)))
        check(f"{T}: art screen stands on the floor, clear of door D2 (z 89) and the back wall (z 93)", fy0 <= 0.15 and fz0 >= 89.1 and fz1 <= 92.9, (fy0, fz0, fz1))
        check(f"{T}: art screen shows a composition (SurfaceGui, >= 4 frames, faces the lobby)", len(pg) == 1 and pg[0].get("face") == "Right" and len(frames) >= 4, (len(pg), len(frames)))
        near_f = [p for p in named("Foliage", L) if abs(p["cframe"][2] - 91) < 3 and p["cframe"][0] < -112]
        gap = min((p["cframe"][0] - ball_r(p)) - fx1 for p in near_f) if near_f else None
        check(f"{T}: plant in front of the art screen, foliage clear of it", gap is not None and gap > 0.05, gap)
    else:
        check(f"{T}: art screen + frame", False, (len(scr), len(scf)))

    # ---- rooms and breakfast
    rooms = sorted({m.group(1) for p in parts for m in [re.search(r"/Rooms/(H[01]_R\d\d)/", p["path"])] if m})
    check(f"{T}: 12 guest rooms furnished", len(rooms) == 12, rooms)
    for rid in rooms:
        R = f"/Rooms/{rid}/"
        tv = named("TV", R)
        txt = texts_under(kids, tv[0]) if tv else []
        ok = len(named("ArtFrame", R)) == 1 and len(named("ArtPrint", R)) == 1 and len(named("Curtain", R)) >= 2 and len(tv) == 1 and \
            "WELCOME" in txt and any(COMPANY in t for t in txt) and any(re.match(r"(Room|Suite) \d{3}$", t) for t in txt)
        check(f"{T}: {rid} print, curtains, TV welcome page", ok, (len(named("ArtFrame", R)), len(named("Curtain", R)), txt))
        if tv:
            check(f"{T}: {rid} TV is a dark screen, not Neon", tv[0]["material"] != "Neon", tv[0]["material"])
        ap = named("ArtPrint", R)
        if ap:
            guis = [c for c in kids.get(ap[0]["id"], []) if c["class"] == "SurfaceGui" and c["name"] == "Print"]
            frames, corners = [], []
            if guis:
                stack = [guis[0]["id"]]
                while stack:
                    for c in kids.get(stack.pop(), []):
                        (frames if c["class"] == "Frame" else corners if c["class"] == "UICorner" else []).append(c)
                        stack.append(c["id"])
            check(f"{T}: {rid} print shows a picture (SurfaceGui, >= 3 frames, >= 1 round)", len(guis) == 1 and guis[0].get("face", "Front") == "Front" and len(frames) >= 3 and len(corners) >= 1,
                  (len(guis), len(frames), len(corners)))
        frame = named("ArtFrame", R)
        check(f"{T}: {rid} print frame is decor", frame and not frame[0]["canCollide"] and not frame[0]["canQuery"])
        cur = named("Curtain", R)
        check(f"{T}: {rid} two curtains 3.2 wide, 0.15 thick, one warm colour", len(cur) == 2 and all(sorted(round(v, 3) for v in c["size"]) == [0.15, 3.2, 11.6] for c in cur)
              and all(max(abs(u - v) for u, v in zip(c["color"], CURTAIN_RGB)) < 0.6 for c in cur), [(c["size"], c["color"]) for c in cur])
        lvl = rid[1]
        obst = [p for p in parts if (R in p["path"] and p["name"] in ("WritingDesk", "DeskLeg", "Nightstand", "Headboard", "LampShade", "DeskLamp", "BedBase"))
                or (f"/Walls/Level_{lvl}/" in p["path"] and p["name"] in ("Wall", "Skirting")) or ("/Facade/" in p["path"] and p["name"] == "Glass")]
        clip = [(c["name"], o["name"]) for c in cur for o in obst if overlap(c, o, 0.0)]
        check(f"{T}: {rid} curtains clear of desk, legs, nightstands, headboard, walls and the facade glass", not clip, clip[:3])
        sh_ = named("WindowSheer", R)
        sclip = [o["name"] for c in sh_ for o in obst + cur if overlap(c, o, 0.0)]
        check(f"{T}: {rid} white sheer across the window, translucent, between the glass and the drapes", len(sh_) == 1 and 0.3 <= sh_[0].get("transparency", 0) <= 0.6
              and not sh_[0]["canCollide"] and not sclip and max(sh_[0]["size"]) >= 12.0, (len(sh_), sclip[:3]))
        ns, hb = named("Nightstand", R), named("Headboard", R)
        nclip = [(n["name"], o["name"]) for n in ns for o in hb + cur if overlap(n, o, 0.0)]
        check(f"{T}: {rid} nightstands clear of the headboard and the curtains", len(ns) == 2 and not nclip, nclip[:3])
    Bk = "/Rooms/H0_BREAKFAST/"
    menu = named("MenuBoard", Bk)
    check(f"{T}: breakfast buffet (chafing dish, bread, fruit)", len(named("ChafingDish", Bk)) == 1 and len(named("BreadRoll", Bk)) >= 3 and len(named("Fruit", Bk)) >= 3)
    check(f"{T}: breakfast menu board", len(menu) == 1 and "BREAKFAST" in texts_under(kids, menu[0]))
    check(f"{T}: breakfast hours inside the game day (8:00 - 10:30)", menu and any("8:00" in t and "10:30" in t for t in texts_under(kids, menu[0])), menu and texts_under(kids, menu[0]))
    check(f"{T}: breakfast coffee machine prompt", any(i["class"] == "ProximityPrompt" and Bk + "FitOut/PantryCoffee/" in i["path"] for i in inst))

    # ---- exterior identity
    for face, axis, sign_, word_axis in (("Facade_HotelSouth", 2, -1, 0), ("Facade_HotelWest", 0, -1, 2)):
        st = named("SignLetter", "/" + face + "/")
        check(f"{T}: {face}: 38 built neon strokes", len(st) == 38 and all(p["material"] == "Neon" for p in st), len(st))
        if st:
            # reading direction for a viewer in front of the face: south (looks +Z) reads -X, west (looks +X) reads +Z
            order = letters_order(st, word_axis, -1 if face.endswith("South") else 1)
            check(f"{T}: {face}: GUEST HOUSE reads left to right", order == WORD, order)
            ys = [lo_hi(p)[1][0] for p in st]
            check(f"{T}: {face}: letters stand on the coping (y >= 33.2)", min(ys) >= 33.19, min(ys))
            xs = [lo_hi(p)[0][0] for p in st]
            check(f"{T}: {face}: inside the site box (x >= -142)", min(xs) >= -142.0, min(xs))
            if face.endswith("West"):
                check(f"{T}: west letters clear of the rail cap (x <= -141.7)", max(lo_hi(p)[0][1] for p in st) <= -141.7 + 1e-6)
            # backing plate: dark metal, behind every letter (between the letters and the rail cap)
            bk = named("SignBacking", "/" + face + "/")
            caps = named("RailCap", "/" + face + "/")
            if len(bk) == 1:
                B_ = lo_hi(bk[0])
                L_ = [lo_hi(p) for p in st]
                wa = word_axis
                na = axis  # the face normal axis
                cover = all(B_[wa][0] <= l[wa][0] + 1e-6 and B_[wa][1] >= l[wa][1] - 1e-6 and B_[1][0] <= l[1][0] + 1e-6 and B_[1][1] >= l[1][1] - 1e-6 for l in L_)
                # outward = -1 for both faces here (south: -Z, west: -X): letters lie further out (smaller coordinate)
                letters_in = max(l[na][1] for l in L_)
                behind = letters_in - 0.02 <= B_[na][0] <= letters_in + 0.05  # the plate starts at the letters' inner face
                # the rail cap's outer face (largest outward extent = smallest coordinate) must not lie inside the plate
                cap_out = min(lo_hi(c)[na][0] for c in caps) if caps else None
                dark = sum(bk[0]["color"]) / 3 < 80
                check(f"{T}: {face}: one dark metal backing plate covers every letter", cover and bk[0]["material"] == "Metal" and dark, (B_, bk[0]["material"], bk[0]["color"]))
                check(f"{T}: {face}: backing plate clear of the rail cap's outer face (no coplanar faces)", cap_out is not None and (B_[na][1] < cap_out - 0.005 or B_[na][0] > cap_out + 0.005), (B_[na], cap_out))
                check(f"{T}: {face}: backing plate directly behind the letters (towards the building)", behind, (B_[na], letters_in))
                check(f"{T}: {face}: backing plate stands on the coping (y >= 33.2)", B_[1][0] >= 33.19, B_[1][0])
            else:
                check(f"{T}: {face}: one backing plate", False, len(bk))
    band = named("ParapetNameBand", "/Facade_HotelSouth/")
    check(f"{T}: company band under the south letters", len(band) == 1 and COMPANY.upper() in texts_under(kids, band[0]))
    fas = [t for p in named("HotelCanopyFascia") for t in texts_under(kids, p)]
    check(f"{T}: canopy front names the house (once)", fas.count("GUEST HOUSE") == 1, fas)
    endf = [p for p in named("HotelCanopyFascia") if lo_hi(p)[2][1] <= 82.01]
    check(f"{T}: canopy south end is a plain fascia (behind the blade sign from the colonnade)", len(endf) == 1 and not gui_of(kids, endf[0]), len(endf) and len(gui_of(kids, endf[0])))
    cam = [i for i in inst if i["name"] == "CampusCamera_EXT_HOTEL"]
    if cam:
        mounts = [p for p in parts if p["path"].startswith(cam[0]["path"] + "/") and p["name"] == "Mount"]
        (cx0, cx1), _, (cz0, cz1) = lo_hi(cam[0])
        mtop = lo_hi(mounts[0])[1][1] if mounts else None
        check(f"{T}: entrance camera tucked against the facade (x <= -96.5, off the approach view)", cx1 <= -96.5 and cx0 >= -97.8, (cx0, cx1))
        check(f"{T}: entrance camera mounted on the canopy soffit's underside (y 11.0, z 82.3..97.7)", mtop is not None and abs(mtop - 11.0) < 0.02 and cz0 >= 82.3 and cz1 <= 98.0, (mtop, cz0, cz1))
    else:
        check(f"{T}: entrance camera EXT_HOTEL", False)
    # west window boxes (review round 3): ground floor on the base course, first floor on the cornice
    W_ = "/Facade_HotelWest/"
    wb, fb = named("WindowBox", W_), named("FlowerBox", W_)
    wg, wbl = named("WindowBoxGreen", W_), named("WindowBoxBloom", W_)
    check(f"{T}: west window boxes: 5 on the cornice (first-floor rooms), 5 on the base course", len(wb) == 5 and len(fb) == 5 and len(wg) == 5 and len(wbl) == 5
          and all(abs(lo_hi(p)[1][0] - 16.6) < 1e-3 for p in wb) and all(abs(lo_hi(p)[1][0] - 0.9) < 1e-3 for p in fb), (len(wb), len(fb), len(wg), len(wbl)))
    allw = wb + fb + wg + wbl + named("FlowerHedge", W_)
    check(f"{T}: west window boxes inside the site box (x >= -142) and clear of the glass (x <= -141.2)", allw and all(lo_hi(p)[0][0] >= -142.0 - 1e-6 and lo_hi(p)[0][1] <= -141.2 + 1e-6 for p in allw),
          [(p["name"], lo_hi(p)[0]) for p in allw if not (lo_hi(p)[0][0] >= -142.0 - 1e-6 and lo_hi(p)[0][1] <= -141.2 + 1e-6)][:3])
    vis = all(any(abs(g["cframe"][2] - b["cframe"][2]) < 0.5 and lo_hi(b)[0][0] < lo_hi(g)[0][0] - 0.05 and b["cframe"][1] < g["cframe"][1] for g in wg) for b in wbl)
    check(f"{T}: window-box flowers in front of and below the foliage (seen from the path)", wbl and vis)
    above = all(any(abs(w["cframe"][2] - b["cframe"][2]) < 0.5 and lo_hi(b)[1][0] >= lo_hi(w)[1][1] - 0.01 and lo_hi(b)[0][0] < lo_hi(w)[0][0] for w in wb) for b in wbl)
    check(f"{T}: window-box flowers stand on the box's front edge (above its top, in front of its face)", wbl and above)
    rooms_up = [r for r in ("H1_R05", "H1_R06", "H1_R07", "H1_R08", "H1_R09")]
    under = all(any(lo_hi(b)[2][0] >= lo_hi(acc)[2][0] and lo_hi(b)[2][1] <= lo_hi(acc)[2][1] for b in wb)
                for rid in rooms_up for acc in named(f"Access_{rid}"))
    check(f"{T}: a window box under each first-floor west room (201-205)", under)
    N_ = "/Facade_HotelNorth/"
    nb, ng, nbl = named("WindowBox", N_), named("WindowBoxGreen", N_), named("WindowBoxBloom", N_)
    check(f"{T}: north window boxes under rooms 205 and 208 on the cornice, clear of the glass (z >= 172.2)", len(nb) == 2 and len(ng) == 2 and len(nbl) == 2
          and all(abs(lo_hi(p)[1][0] - 16.6) < 1e-3 for p in nb) and all(lo_hi(p)[2][0] >= 172.2 - 1e-6 for p in nb + ng + nbl), (len(nb), len(ng), len(nbl)))
    check(f"{T}: north window-box flowers in front of the foliage, on the box's front edge",
          all(any(abs(g["cframe"][0] - b["cframe"][0]) < 0.5 and lo_hi(b)[2][1] > lo_hi(g)[2][1] + 0.05 for g in ng) and
              any(abs(w["cframe"][0] - b["cframe"][0]) < 0.5 and lo_hi(b)[1][0] >= lo_hi(w)[1][1] - 0.01 for w in nb) for b in nbl) and len(nbl) == 2)
    spots = [i for i in inst if i["class"] == "SpotLight" and "/HotelCanopyLight/" in i["path"]]
    check(f"{T}: canopy one SpotLight", len(spots) == 1, len(spots))
    canopy = named("HotelCanopy")
    check(f"{T}: canopy above head height", len(canopy) == 1 and lo_hi(canopy[0])[1][0] >= 10.5)
    lane = []
    for p in parts:
        (x0, x1), (y0, y1), (z0, z1) = lo_hi(p)
        if x1 > -95.0 and x0 < -89.0 and z1 > 72 and z0 < 125 and y1 > 0.3 and y0 < 7.5 and "/Doors/" not in p["path"] and not RIG.search(p["path"]):
            lane.append(p["path"])
    check(f"{T}: WestPath lane clear (x -95..-89, z 72..125, body height)", not lane, lane[:3])
    check(f"{T}: old way sign post gone", not named("GuestHouseSignPost"))
    # blade sign on the south-east corner pier
    bl, bg = named("BladeSign", "/Facade_HotelEast/"), named("BladeSignGlow", "/Facade_HotelEast/")
    if len(bl) == 1 and len(bg) == 1:
        (bx0, bx1), (by0, by1), (bz0, bz1) = lo_hi(bl[0])
        guis = [c for c in kids.get(bl[0]["id"], []) if c["class"] == "SurfaceGui"]
        faces = sorted(g.get("face", "") for g in guis)
        txt = texts_under(kids, bl[0])
        check(f"{T}: blade sign faces +-Z (thin in z), projects from the pier face x -96.4", bz1 - bz0 <= 0.4 and abs(bx0 + 96.4) < 1e-3 and bx1 - bx0 >= 3.5, (bx0, bx1, bz0, bz1))
        check(f"{T}: blade sign names the house on both faces", faces == ["Back", "Front"] and txt.count("GUEST\nHOUSE") == 2, (faces, txt))
        check(f"{T}: blade sign above head height and inside the colonnade view window (y 7.75..11.0)", by0 >= 7.75 and by1 <= 11.0 + 1e-6, (by0, by1))
        check(f"{T}: blade sign neon edge", bg[0]["material"] == "Neon" and abs(lo_hi(bg[0])[0][0] - bx1) < 1e-3)
        # visibility: rays from eye points in the colonnade and at its plaza end to points on the sign face
        D = Dump(path)
        nm = D.name
        opaque = np.where((D.transp < 0.5) & ~D.character)[0]
        lo_a, hi_a = D.aabb(opaque)
        box_x0, box_x1 = -100.0, -80.0
        near = opaque[(hi_a[:, 0] >= box_x0) & (lo_a[:, 0] <= box_x1) & (hi_a[:, 2] >= -90) & (lo_a[:, 2] <= 79) & (lo_a[:, 1] <= 14)]
        me = {j for j in near if D.inst[int(D.pidx[j])]["path"] in (bl[0]["path"], bg[0]["path"])}
        targets = [(x, y, bz0 - 0.01) for x in np.linspace(bx0 + 0.6, bx1 - 0.4, 4) for y in np.linspace(by0 + 0.4, by1 - 0.4, 3)]
        for label, eye in (("colonnade z 52", (-90.5, 5.6, 52.0)), ("colonnade z 38", (-91.0, 5.6, 38.0)), ("colonnade z 10", (-92.0, 5.6, 10.0)),
                           ("plaza end z -46", (-90.0, 5.6, -46.0)), ("plaza z -80", (-91.0, 5.6, -80.0))):
            seen = sum(1 for t in targets if not ray_blocked(D, near, eye, t, me))
            check(f"{T}: blade sign visible from the {label} (>= 2/3 of the face)", seen >= len(targets) * 2 / 3, f"{seen}/{len(targets)}")
    else:
        check(f"{T}: blade sign + neon edge on the east facade", False, (len(bl), len(bg)))
    shr = named("BedShrub")
    check(f"{T}: bed shrubs clear of the HQ (x + r <= -84.6) and of the lane (x - r >= -89)", shr and all(p["cframe"][0] + ball_r(p) <= -84.6 and p["cframe"][0] - ball_r(p) >= -89 for p in shr),
          [(round(p["cframe"][0], 2), ball_r(p)) for p in shr])
    fc, rn, wp = named("EntranceForecourt"), named("EntranceRunner"), [p for p in parts if p["name"] == "WestPath"]
    if fc and rn and wp:
        ft, rt, wt = lo_hi(fc[0])[1][1], lo_hi(rn[0])[1][1], max(lo_hi(p)[1][1] for p in wp)
        check(f"{T}: forecourt / runner overlays stepped >= 0.05 (path {wt}, forecourt {ft}, runner {rt})", ft - wt >= 0.05 - 1e-6 and rt - ft >= 0.05 - 1e-6)
    lp = [p for p in parts if "/WestPathLights/" in p["path"]]
    check(f"{T}: approach lamps beside the lane (x >= -88)", lp and all(lo_hi(p)[0][0] >= -88 for p in lp))
    check(f"{T}: approach 3 PointLights", len([i for i in al if i["class"] == "PointLight"]) == 3, len(al))
    hang = named("ColonnadeHangingSign")
    check(f"{T}: colonnade sign above head height", len(hang) == 1 and lo_hi(hang[0])[1][0] >= 8.5 and "GUEST HOUSE  ↑" in texts_under(kids, hang[0]))
    if hang:
        check(f"{T}: colonnade sign in the east half (off the blade-sign sightline, x >= -92)", lo_hi(hang[0])[0][0] >= -92.0, lo_hi(hang[0])[0])

    # ---- text boards: pixels per stud from the GUI dump (tier 2)
    gpath = os.path.join(a.out, f"gui_tier{tier}.json")
    if tier == tiers[0]:
        if os.path.exists(gpath):
            G = json.load(open(gpath))["instances"]
            gp = {i["path"]: i for i in G if i["class"] == "SurfaceGui"}
            def pps(path):
                return gp.get(path, {}).get("pps")
            check(f"{T}: breakfast menu board 100 px per stud (subtitle glyphs sharp)", pps("Office/Rooms/H0_BREAKFAST/FitOut/MenuBoard/Sign") == 100, pps("Office/Rooms/H0_BREAKFAST/FitOut/MenuBoard/Sign"))
            for nm in ("ConciergeSign/Sign", "LobbyHouseSign/Sign", "LobbyHouseWord/SurfaceGui", "KeyRack/KeyGrid"):
                v = pps("Office/Rooms/H0_LOBBY/FitOut/" + nm)
                check(f"{T}: lobby {nm} >= 100 px per stud", v is not None and v >= 100, v)
            big = [(k, v["pps"]) for k, v in gp.items() if "/Rooms/H0_" in k and k.endswith("/Sign") and v.get("pps")]
            sizes = {i["path"]: i for i in G if "size" in i}
            over = [k for k, v in big if max(sizes[k.rsplit("/", 1)[0]]["size"]) * v > 1000 + 1e-6]
            check(f"{T}: sign canvases <= 1000 px on the long side", not over, over[:3])
            kgl = gp.get("Office/Rooms/H0_LOBBY/FitOut/KeyRack/KeyGrid", {})
            check(f"{T}: key-cubby grid backlit (LightInfluence 0)", kgl.get("lightInfluence") == 0, kgl.get("lightInfluence"))
        else:
            check(f"{T}: GUI dump present", False, gpath)

    # ---- decor flags
    bad = [p["path"] for p in parts if p["name"] in DECOR and (HOTEL_PATH.search(p["path"]) or "/Site/" in p["path"]) and
           (p["canCollide"] or p["canQuery"] or p["canTouch"] or p.get("castShadow", False))]
    check(f"{T}: package decor non-colliding, no query/touch/shadow", not bad, bad[:3])

    # ---- reachability (check_geometry report of harness/run.sh --check)
    rp = os.path.join(a.out, f"check_tier{tier}.txt")
    rep = open(rp).read() if os.path.exists(rp) else ""
    check(f"{T}: check report present", "== SUMMARY" in rep or "workstations:" in rep, rp)
    m = re.search(r"parts outside allowed box: (\d+)", rep) or re.search(r"(\d+) part\(s\) outside", rep)
    check(f"{T}: nothing outside the site box", m is not None and m.group(1) == "0", m and m.group(0))
    badr = unreachable(rep, TARGETS)
    for cat in TARGETS:
        hotel = [p for p in badr.get(cat, []) if HOTEL_PATH.search(p)]
        check(f"{T}: every guest-house {cat} target reachable", not hotel, hotel[:2])
    if tier == tiers[0]:
        rc, txt = run([sys.executable, os.path.join(ROOT, "tests", "lead", "holes.py"), path])
        check(f"{T}: 0 holes", rc == 0 and "TOTAL hole area 0.0 sq studs" in txt, txt[-300:])

    # ---- receptionist hops
    if post:
        at = post[0]["attrs"]
        pts = {"stand": v3(at["InteractionPosition"]), "greet": v3(at.get("JobPoint_greet")), "printer": v3(at.get("JobPoint_printer"))}
        segs = [(f"{p}-{q}", pts[p], pts[q]) for p, q in (("stand", "greet"), ("greet", "printer"), ("printer", "stand"))]
        neg = [("NEGATIVE_through_counter", [-113.4, 2.9, 99.5], [-105.0, 2.9, 99.5])]
        blocked, ran = probe(path, segs + neg)
        check(f"{T}: hop probe ran", ran)
        for label, si in sorted(blocked):
            if not label.startswith("NEGATIVE"):
                check(f"{T}: hop walkable {label}", False, segs[si][1:])
        check(f"{T}: NEGATIVE hop through the counter reported (probe)", ("NEGATIVE_through_counter", 3) in blocked)
        passed += sum(1 for s in range(3) if (segs[s][0], s) not in blocked)
        D = Dump(path)
        strict = corridor(D, segs + neg)
        for si in range(3):
            check(f"{T}: hop clear for a body of radius 1.0: {segs[si][0]}", si not in strict, strict.get(si))
        check(f"{T}: NEGATIVE hop through the counter reported (corridor)", 3 in strict and "Reception" in strict[3], strict.get(3))

print(f"hotelpolish: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
