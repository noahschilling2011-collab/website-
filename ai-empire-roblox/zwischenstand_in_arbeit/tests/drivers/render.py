#!/usr/bin/env python3
"""drivers package: Cycles renders (tools/blenderprev) of the chauffeur rides on the REAL geometry.

Each shot = a blenderprev scene (HQ tier 1 on Plot_10 inside the real district, or the shared world) + one extra
dump of what DriveController draws at a moment of a real ride (tests/drivers/dump_scene.luau: DriverService +
DriveController in the mock, rig limbs solved from their joints). Nothing is modelled by hand.

    python3 tests/drivers/render.py --list
    python3 tests/drivers/render.py hq_post airport_kerb pm_stand [--preview] [--samples N] [--res WxH]
Images: out/drivers/render/<shot>.png (+ a caption strip: "Render from game data - not a Studio screenshot").
"""
import argparse, json, os, subprocess, sys, time
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blenderprev"))
import dump2blend as d2b  # noqa: E402
import shots  # noqa: E402
import bpy  # noqa: E402

OUT = os.path.join(ROOT, "out", "drivers", "render")
WORLD = os.path.join(ROOT, "out", "drivers", "base", "world", "world_dump.json")
GEN = ".gen_drivers"
PLOT = 1  # client_setup claims the first free plot

# cam/look in the scene frame: hqN scenes are building-local (front = -Z), world scenes are world studs
SHOTS = {
    "hq_post": dict(moment="hq_post", scene="hq1", desc="the company driver waits under the HQ entrance canopy",
                    cam=(31, 6.2, -78), look=(15, 4.6, -56), lens=32, sun_az=40, preset="day"),
    "hq_pickup": dict(moment="hq_board", scene="hq1", desc="the fleet car waits at the HQ pick-up; the founder walks to the rear door",
                      cam=(132, 7.5, -190), look=(106, 3.5, -160), lens=30, sun_az=60, preset="day"),
    "airport_side": dict(moment="airport_kerb", scene="world", desc="drop-off at the City Airport departures kerb (seen from the drop-off lane)",
                         cam=(86, 31.2, 2393), look=(63, 27.4, 2417), lens=28, sun_az=200, preset="day"),
    "airport_kerb": dict(moment="airport_kerb", scene="world", desc="drop-off at the City Airport departures kerb",
                         cam=(104, 29.4, 2427), look=(62, 26.6, 2414), lens=26, sun_az=200, preset="day"),
    "pm_stand": dict(moment="pm_stand", scene="world", desc="the VIP limousine and its chauffeur at the Port Meridian stand (bay 1; bay 2 = the decorative limousine)",
                     cam=(206, 31, 7728), look=(160, 26, 7764), lens=30, sun_az=150, preset="golden"),
    "pm_front": dict(moment="pm_stand", scene="world", desc="the VIP limousine and its chauffeur at the Port Meridian stand, seen from the arrivals plaza",
                     cam=(165, 30.6, 7731), look=(177, 26.4, 7760), lens=30, sun_az=20, preset="day"),
    "pm_board": dict(moment="pm_board", scene="world", desc="the founder gets into the VIP limousine at the stand",
                     cam=(147, 30.5, 7737), look=(177, 26.4, 7761), lens=30, sun_az=150, preset="golden"),
    "hq_depot": dict(moment="hq_depot", scene="hq1", desc="the idle company car parked at the depot in B1 (the ride car takes exactly this place)",
                     cam=(93, -10, 27), look=(107.4, -14.5, 58), lens=22, sun_az=60, preset="day"),
    "ride_full_left": dict(moment="ride_full", scene="world", desc="driver, founder and two colleagues on the way to CloudDesk - left side (occupants inside the body)",
                           rel=(-24, 5.5, 3), look_up=2.4, lens=35, sun_az=210, preset="day"),
    "ride_full_cutaway": dict(moment="ride_full", scene="world", desc="CUTAWAY (glass + roof left out): the four seated occupants stay inside the body",
                              rel=(-8, 10, 7), look_up=2.2, lens=30, sun_az=30, preset="day",
                              hide=("Cabin", "Windscreen", "RearWindow", "Roof", "PillarC")),
    "field_door": dict(moment="field_door", scene="world", desc="the company driver dropped the field rep at CloudDesk; he walks to the door while the car waits",
                       rel=(16, 6, -14), lens=30, sun_az=210, preset="day"),
    "pm_depart": dict(moment="pm_depart", scene="world", desc="the booked limousine pulls away from bay 1 (no idle limousine drawn inside it; bay 2 = the decorative one)",
                      rel=(-12, 9, 22), lens=30, sun_az=150, preset="golden"),
    "ride_city": dict(moment="ride_city", scene="world", desc="a company car on its way to a client in Business City (aerial)",
                      cam=None, look=None, lens=40, sun_az=210, preset="day", follow=True),
}


def plot_cf(i):
    return shots.plot_cf(i)


def dump_moment(moment):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"dump_{moment}.json")
    res = subprocess.run([os.path.join(ROOT, "tools", "luau"), "dump_scene.luau", "-a", GEN, moment], cwd=HERE,
                         capture_output=True, text=True, timeout=600)
    line = next((l for l in res.stdout.splitlines() if l.startswith("@@DUMP ")), None)
    if not line:
        raise SystemExit(f"dump_scene {moment} failed:\n{res.stdout[-3000:]}\n{res.stderr[-2000:]}")
    d = json.loads(line[7:])
    for x in d["instances"]:
        x.setdefault("parent", None)  # JSONEncode drops nil
    json.dump(d, open(path, "w"))
    return path, d


def car_pose(d):
    for x in d["instances"]:
        if x["name"] == "Root" and "DriveCar" in x["path"] and "cframe" in x:
            return np.array(x["cframe"][:3])
    return None


def car_frame(d):
    """position, right, look of the first drawn car (CFrame components: x y z R00 R01 R02 R10 ... R22)"""
    for x in d["instances"]:
        if x["name"] == "Root" and "DriveCar" in x["path"] and "cframe" in x:
            c = x["cframe"]
            R = np.array(c[3:]).reshape(3, 3)
            return np.array(c[:3]), R[:, 0], -R[:, 2]
    return None


def render(name, args):
    s = dict(SHOTS[name])
    t0 = time.time()
    extra, d = dump_moment(s["moment"])
    if s.get("hide"):
        # cutaway: leave the car's glass / roof parts out of the extra dump (occupants and body stay)
        keep = [x for x in d["instances"] if not ("DriveCar" in x["path"] and x["name"] in s["hide"] and x["path"].count("/") <= 3)]
        d = dict(d, instances=keep)
        extra = extra.replace(".json", "_cut.json")
        json.dump(d, open(extra, "w"))
    d2b.reset_scene()
    world = WORLD if os.path.exists(WORLD) else None
    ps, ground = shots.build_scene(s["scene"], npcs=True, context=True, dump=world if s["scene"] == "world" else None)
    xform = np.linalg.inv(plot_cf(shots.HOME_PLOT)) @ plot_cf(PLOT) if s["scene"].startswith("hq") else None
    # hq scenes: the HQ sits on Plot_10 in building-local space; the founder's plot in the mock is plot 1, so the
    # extra dump is moved by plot_cf(1)^-1 (world -> building-local)
    if s["scene"].startswith("hq"):
        xform = np.linalg.inv(plot_cf(PLOT))
    ps.add_dump(extra, xform=xform, npcs=True, label="drivers")
    cam, look = s.get("cam"), s.get("look")
    if s.get("rel"):
        pos, rv, lv = car_frame(d)
        r, u, f = s["rel"]
        cam = tuple(pos + rv * r + np.array([0, u, 0]) + lv * f)
        look = tuple(pos + np.array([0, s.get("look_up", 2.6), 0]))
    if s.get("follow"):
        p = car_pose(d)
        look = (p[0], p[1] + 2, p[2])
        cam = (p[0] - 70, p[1] + 55, p[2] - 60)
    D = ps.merged()
    d2b.build_meshes(ps)
    nl = d2b.build_lights(ps)
    g = dict(ground)
    wz = g.get("water_z")
    d2b.add_ground(g["y"], g.get("center", (0, 0)), kind=g["kind"], color=g["color"], hole=g.get("hole"),
                   zrange=(-1e9, wz) if wz is not None else None)
    if wz is not None:
        d2b.add_ground(g["sea_y"] - 0.4, g.get("center", (0, 0)), kind="water", color=shots.WATER_RGB, zrange=(wz, 1e9))
    p = d2b.setup_world(s["preset"], s.get("sun_az", 210.0))
    for ob in bpy.data.objects:
        if ob.type == "LIGHT" and ob.name.startswith("L"):
            ob.data.energy = ob.data.energy * p["lights"]
    res = args.res or ((800, 450) if args.preview else (1600, 900))
    samples = args.samples or (16 if args.preview else 64)
    d2b.setup_render(res, samples, p["exposure"] + s.get("exposure", 0.0), p["look"], fast=args.preview)
    d2b.setup_compositor(s.get("fog", 0.05), p["fog_color"], p["bloom"])
    d2b.set_camera(cam, look, s.get("lens", 35))
    out = os.path.join(OUT, f"{name}{'_preview' if args.preview else ''}.png")
    bpy.context.scene.render.filepath = out
    tr = time.time()
    bpy.ops.render.render(write_still=True)
    print(f"{name}: {out} {res[0]}x{res[1]} {samples} spp, {ps.count()} parts, {nl} lights, render {time.time() - tr:.0f}s, total {time.time() - t0:.0f}s")
    caption(out, s["desc"])
    return out


def caption(path, desc):
    try:
        from PIL import Image, ImageDraw, ImageFont
    except Exception:
        return
    im = Image.open(path).convert("RGB")
    w, h = im.size
    bar = max(28, h // 26)
    canvas = Image.new("RGB", (w, h + bar), (18, 20, 22))
    canvas.paste(im, (0, 0))
    dr = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", int(bar * 0.5))
    except Exception:
        font = ImageFont.load_default()
    dr.text((10, h + bar * 0.22), f"{desc}  -  Cycles render from game data (DriverService + DriveController in the mock), not a Studio screenshot",
            fill=(230, 214, 150), font=font)
    canvas.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("shots", nargs="*")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--samples", type=int)
    ap.add_argument("--res", type=lambda v: tuple(int(x) for x in v.split("x")))
    a = ap.parse_args()
    if a.list or not a.shots:
        for k, s in SHOTS.items():
            print(f"{k:14s} {s['scene']:6s} {s['desc']}")
        return
    names = list(SHOTS) if a.shots == ["all"] else a.shots
    # the moment dumps run on harness/.gen_drivers: rebuild it from work/src so a render never shows stale code
    subprocess.run([sys.executable, os.path.join(ROOT, "harness", "make_manifest.py"), "--src", "work/src", "--gen", f"harness/{GEN}"],
                   cwd=ROOT, check=True, capture_output=True)
    for n in names:
        render(n, a)


if __name__ == "__main__":
    main()
