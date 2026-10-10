"""shots.py - named marketing shots of the real AI Empire geometry (Cycles, headless bpy).

    python3 tools/blenderprev/shots.py --list
    python3 tools/blenderprev/shots.py hq4_aerial hq4_cafe            # render shots (1600x900)
    python3 tools/blenderprev/shots.py all                             # every shot
    python3 tools/blenderprev/shots.py hq4_cafe --preview              # 800x450, few samples
    python3 tools/blenderprev/shots.py hq4_cafe --dump other_tier4.json --preset night --samples 128
    python3 tools/blenderprev/shots.py custom --scene hq3 --cam -200,150,-300 --look 0,30,0 --lens 35
    python3 tools/blenderprev/shots.py hq4_cafe --probe                # camera sanity check only

Scenes (all coordinates Roblox studs):
  hqN            HQ dump of building PLAN tier N (out/blenderprev/dumps/dump_tierN.json from hq_dumps.sh; 0 = garage
                 stage = office stage 1 "Garage Lab", 1..4 = office stages 2..5 "Founder Headquarters" ..
                 "Global AI Headquarters") in building-local space (front = -Z), placed in the real district as if
                 claimed on Plot_10 (the district/city dump is moved by the inverse plot CFrame); the
                 other 11 plots carry PlotService's VacantPad.  --no-context renders the HQ alone.
  world          district + Business City + airport + harbour + Port Meridian (world space), 12 vacant pads.
  district_full  world + an HQ on every plot (tiers 1-4 mixed), each placed with its plot CFrame exactly
                 like PlotService.claim -> Design.build(plot.cframe) (the harness proves the generator is
                 frame-independent to 1e-8, see compare_dumps.py).
Images go to out/blenderprev/<shot>.png, a timing log to out/blenderprev/render_log.json.
"""
import argparse, json, math, os, sys, time
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dump2blend as d2b      # noqa: E402
import bpy                    # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "out", "blenderprev")
HQ_DUMP = os.path.join(OUT, "dumps", "dump_tier{}.json")
WORLD_DUMP = os.path.join(OUT, "world", "world_dump.json")
WORLD_DUMP_FALLBACK = os.path.join(ROOT, "out", "world", "world_dump.json")

# CampusConfig / PlotService
PITCH, ROW_OFFSET, STREET_Y = 320, 252, 24
SITE = dict(x1=-142, x2=145, z1=-217, z2=228)
HOME_PLOT = 10                                 # the plot the HQ shots pretend to be claimed on
DISTRICT_TIERS = [3, 1, 4, 0, 3, 1, 2, 4, 0, 3, 2, 4]   # plan tiers (0 = garage stage)
# district (x +-1150, z +-800) + Business City/airport (to the quay at z 3203) have their own ground
# blocks (y -2..24); the backdrop plane leaves this rectangle open so it never cuts through basements.
WORLD_HOLE = (-1150, 1150, -800, 3200)
QUAY_Z = 3203            # CityBuilder quay; the dump's "Sea" glass parts lie south of it at y 20.9..21.1
SEA_Y = 20.9
WATER_RGB = (58, 96, 110)


def plot_cf(i):
    row = -1 if i <= 6 else 1
    x = ((i - 1) % 6 - 2.5) * PITCH
    c = (x, STREET_Y, row * ROW_OFFSET)
    return d2b.cf_lookat(c, (x, STREET_Y, 0))


def vacant_pad(ps, cf_world, name):
    """PlotService.vacantPad: Part SITE-sized x 24 tall, Grass (140,154,127), at plot.cframe*(cx,-12,cz)."""
    off = np.eye(4)
    off[:3, 3] = ((SITE["x1"] + SITE["x2"]) / 2, -12, (SITE["z1"] + SITE["z2"]) / 2)
    ps.add_box(cf_world @ off, (SITE["x2"] - SITE["x1"], 24, SITE["z2"] - SITE["z1"]), (140, 154, 127), "Grass", name=name)


def world_dump_path():
    return WORLD_DUMP if os.path.exists(WORLD_DUMP) else WORLD_DUMP_FALLBACK


def build_scene(scene, npcs=False, context=True, dump=None):
    """Returns (PartSet, ground dict)."""
    ps = d2b.PartSet()
    if scene.startswith("hq"):
        tier = int(scene[2:])
        ps.add_dump(dump or HQ_DUMP.format(tier), npcs=npcs, label=f"HQ tier {tier}")
        # alone: plane at street level with the site left open (garage ramp)
        ground = dict(y=-0.06, kind="grass", color=(112, 138, 96), center=(0, 0),
                      hole=(SITE["x1"], SITE["x2"], SITE["z1"], SITE["z2"]))
        if context:
            inv = np.linalg.inv(plot_cf(HOME_PLOT))
            ps.add_dump(world_dump_path(), xform=inv, label="district+city")
            for i in range(1, 13):
                if i != HOME_PLOT:
                    vacant_pad(ps, inv @ plot_cf(i), f"Plot_{i:02d}/VacantPad")
            # plane just below street level around the district+city block (plot 10 has no rotation)
            o = plot_cf(HOME_PLOT)[:3, 3]
            ground.update(y=20.5 - STREET_Y, hole=(WORLD_HOLE[0] - o[0], WORLD_HOLE[1] - o[0],
                                                  WORLD_HOLE[2] - o[2], WORLD_HOLE[3] - o[2]),
                          water_z=QUAY_Z - o[2], sea_y=SEA_Y - o[1])
    elif scene in ("world", "district_full"):
        ps.add_dump(dump or world_dump_path(), label="district+city")
        for i in range(1, 13):
            if scene == "world":
                vacant_pad(ps, plot_cf(i), f"Plot_{i:02d}/VacantPad")
            else:
                ps.add_dump(HQ_DUMP.format(DISTRICT_TIERS[i - 1]), xform=plot_cf(i), npcs=False,
                            label=f"Plot_{i:02d} HQ tier {DISTRICT_TIERS[i - 1]}")
        ground = dict(y=20.5, kind="grass", color=(112, 138, 96), center=(0, 2000), hole=WORLD_HOLE, water_z=QUAY_Z, sea_y=SEA_Y)
    else:
        raise SystemExit(f"unknown scene {scene}")
    return ps, ground


# ----------------------------------------------------------------------------------------------
# shot table (Roblox coordinates of the scene).  sun_az: 0 = sun towards -Z (building front),
# 90 = towards +X.  fog = haze strength (0 = off), fog_start/depth in studs.
# ----------------------------------------------------------------------------------------------
SHOTS = {
    # ---------------- HQ tier 4 ----------------
    "hq4_aerial": dict(scene="hq4", desc="HQ tier 4 - aerial 3/4 view of the whole campus plot",
                       cam=(-330, 235, -440), look=(0, 30, 0), lens=35, preset="day", sun_az=35,
                       fog=0.18, fog_start=300, fog_depth=5000),
    "hq4_entrance": dict(scene="hq4", desc="HQ tier 4 - main entrance from the plaza at eye height",
                         cam=(-12, 5.5, -150), look=(0, 22, -50), lens=28, preset="day", sun_az=25, npcs=True,
                         fog=0.05),
    "hq4_plaza": dict(scene="hq4", desc="HQ tier 4 - entrance plaza and canopy",
                      cam=(-76, 5.5, -72), look=(0, 13, -56), lens=28, preset="day", sun_az=40, npcs=True, fog=0.05),
    "hq4_atrium": dict(scene="hq4", desc="HQ tier 4 - atrium, looking up to the skylight",
                       cam=(-11, 4.5, -13), look=(6, 80, 34), lens=16, preset="day", sun_az=20, npcs=True, fog=0.0,
                       exposure=0.6),
    "hq4_cafe": dict(scene="hq4", desc="HQ tier 4 - ground-floor cafe",
                     cam=(79, 5.5, 12), look=(40, 5.0, -40), lens=22, preset="day", sun_az=30, npcs=True, fog=0.0,
                     exposure=0.5, samples=48),
    "hq4_datahall": dict(scene="hq4", desc="HQ tier 4 - basement data hall",
                         cam=(-28, -9.0, 38), look=(-60, -12.2, 14), lens=20, preset="day", npcs=True, fog=0.0,
                         exposure=1.6, lights=3.0, samples=48),
    "hq4_office": dict(scene="hq4", desc="HQ tier 4 - open-plan work floor (level 1 west) with staff at their desks",
                       cam=(-51, 21.6, -11), look=(-76, 19.0, -42), lens=22, preset="day", sun_az=-60, npcs=True,
                       fog=0.0, exposure=0.4, samples=48),
    "hq4_founder": dict(scene="hq4", desc="HQ tier 4 - founder office and private terrace",
                        cam=(79, 101.5, 11), look=(55, 100, -44), lens=22, preset="golden", sun_az=-30, npcs=True,
                        fog=0.1, exposure=0.3, samples=48),
    "hq4_night": dict(scene="hq4", desc="HQ tier 4 - night aerial, interior lights and neon",
                      cam=(-215, 100, -300), look=(0, 42, -10), lens=30, preset="night", sun_az=35,
                      fog=0.2, fog_start=300, fog_depth=5000),
    # ---------------- guest house (hotel annex, HQ tiers 2-4; Office/Facade/Facade_Hotel*, Rooms/H0_*, H1_*) ----
    "guesthouse_exterior": dict(scene="hq4", desc="HQ tier 4 - guest house (hotel annex) from the north-west at golden hour, HQ tower behind",
                                cam=(-205, 40, 235), look=(-118, 12, 120), lens=28, preset="golden", sun_az=-120,
                                fog=0.1, fog_start=300, fog_depth=5000),
    "guesthouse_room": dict(scene="hq4", desc="HQ tier 4 - guest house room H1_R12 (bed, lounge chairs, sofa, glazing)",
                            cam=(-99.8, 21.5, 151.2), look=(-109, 18, 168), lens=18, preset="day", sun_az=70, fog=0.0,
                            exposure=1.0, samples=48),
    "guesthouse_lobby": dict(scene="hq4", desc="HQ tier 4 - guest house lobby with reception desk and logo wall",
                             cam=(-101, 5.5, 81), look=(-110, 4.5, 100), lens=20, preset="day", sun_az=70, npcs=True,
                             fog=0.0, exposure=0.5, samples=48),
    "guesthouse_breakfast": dict(scene="hq4", desc="HQ tier 4 - guest house breakfast room (window bar, tables, buffet)",
                                 cam=(-102, 5.5, 108), look=(-110, 3.5, 136), lens=20, preset="day", sun_az=70, npcs=True,
                                 fog=0.0, exposure=0.5, samples=48),
    # ---------------- HQ tier 0 (garage stage) / tier 1 ----------------
    "hq0_aerial": dict(scene="hq0", desc="HQ tier 0 - garage stage: the founder's garage next to the HQ construction site",
                       cam=(-160, 150, -330), look=(40, 0, -60), lens=35, preset="day", sun_az=35,
                       fog=0.18, fog_start=300, fog_depth=5000),
    "hq0_garage": dict(scene="hq0", desc="HQ tier 0 - the garage office close-up (porch, roof lights, parking)",
                       cam=(-20, 70, -230), look=(86, 5, -100), lens=35, preset="day", sun_az=35,
                       fog=0.12, fog_start=300, fog_depth=5000),
    "hq1_aerial": dict(scene="hq1", desc="HQ tier 1 - aerial 3/4 view (first real office: 3 storeys + pavilion)",
                       cam=(-210, 120, -270), look=(5, 16, 25), lens=35, preset="day", sun_az=35,
                       fog=0.18, fog_start=300, fog_depth=5000),
    # ---------------- shared world ----------------
    "city_aerial": dict(scene="world", desc="Business City (Downtown) - aerial",
                        cam=(-1350, 760, 560), look=(-60, 40, 1600), lens=35, preset="day", sun_az=60,
                        fog=0.25, fog_start=600, fog_depth=9000),
    "city_boulevard": dict(scene="world", desc="Business City - street-level boulevard (client offices along the z=1500 avenue)",
                           cam=(372, 29.5, 1490), look=(900, 46, 1534), lens=28, preset="day", sun_az=-30,
                           fog=0.12, fog_start=200, fog_depth=4000),
    "city_hotel": dict(scene="world", desc="Business City - the city hotel tower (Hotel_city_hotel) from across the avenue",
                       cam=(740, 29.5, 930), look=(860, 75, 1060), lens=20, preset="day", sun_az=-35,
                       fog=0.12, fog_start=200, fog_depth=4000),
    "airport_aerial": dict(scene="world", desc="Airport - airside aerial: runway, parked aircraft, terminal, hangar, Downtown behind",
                           cam=(380, 210, 3180), look=(-40, 30, 2560), lens=30, preset="day", sun_az=150,
                           fog=0.15, fog_start=500, fog_depth=8000),
    "airport_apron": dict(scene="world", desc="Airport - landside aerial: terminal roof, jet bridges, aircraft, runway, tower, sea",
                          cam=(-480, 260, 2330), look=(120, 24, 2740), lens=32, preset="day", sun_az=30,
                          fog=0.1, fog_start=500, fog_depth=8000),
    "airport_terminal": dict(scene="world", desc="Airport - terminal front (glass hall, canopy, drop-off lane) at eye height",
                             cam=(-60, 31.0, 2330), look=(60, 40, 2428), lens=20, preset="day", sun_az=20,
                             fog=0.08),
    "pm_aerial": dict(scene="world", desc="Port Meridian - aerial",
                      cam=(-950, 520, 7250), look=(0, 40, 8150), lens=35, preset="day", sun_az=60,
                      fog=0.22, fog_start=600, fog_depth=9000),
    "pm_waterfront": dict(scene="world", desc="Port Meridian - waterfront skyline and promenade from the harbour at golden hour",
                          cam=(300, 45, 8900), look=(-50, 80, 8500), lens=28, preset="golden", sun_az=235,
                          fog=0.2, fog_start=300, fog_depth=6000),
    "pm_hotel": dict(scene="world", desc="Port Meridian - international hotel at the end of the boulevard, golden hour",
                     cam=(-10, 29.5, 8160), look=(0, 78, 8400), lens=26, preset="golden", sun_az=15,
                     fog=0.2, fog_start=300, fog_depth=6000),
    "district_aerial": dict(scene="district_full", desc="Tech district - all 12 plots claimed (garage stage and HQ plan tiers 1-4 mixed) from above",
                            cam=(-700, 1500, -1750), look=(0, 0, 60), lens=35, preset="day", sun_az=40,
                            fog=0.2, fog_start=1200, fog_depth=9000, samples=40),
}

RENDER_DEFAULTS = dict(res=(1600, 900), samples=64)


def probe(D, shot):
    cam = np.array(shot["cam"], float)
    look = np.array(shot["look"], float)
    solid = d2b.solid_mask(D)
    ins = d2b.point_inside(D, cam, margin=0.3, sel=solid)
    t, name = d2b.ray_hit(D, cam, look - cam, sel=solid)
    dist = float(np.linalg.norm(look - cam))
    print(f"  probe: camera inside {len(ins)} solid part(s) {ins[:4]}; first hit along view at "
          f"{t if t is None else round(t, 1)} studs ({name}); target at {dist:.1f}")
    # 8 directions around the camera: clearance
    cl = []
    for a in range(0, 360, 45):
        d = (math.cos(math.radians(a)), 0, math.sin(math.radians(a)))
        tt, _ = d2b.ray_hit(D, cam, d, sel=solid, tmax=50)
        cl.append(round(tt, 1) if tt is not None else None)
    up, nm = d2b.ray_hit(D, cam, (0, 1, 0), sel=solid, tmax=500)
    dn, nm2 = d2b.ray_hit(D, cam, (0, -1, 0), sel=solid, tmax=500)
    print(f"  probe: horizontal clearance {cl}; up {up} ({nm}); down {dn} ({nm2})")


def render_shots(names, args):
    log_path = os.path.join(OUT, "render_log.json")
    try:
        log = json.load(open(log_path))
    except Exception:
        log = {}
    # group by scene configuration so geometry is built once per group
    groups = {}
    for n in names:
        s = dict(SHOTS[n])
        if args.preset:
            s["preset"] = args.preset
        key = (args.scene or s["scene"], bool(s.get("npcs", False) or args.npcs) and not args.no_npcs, args.dump)
        groups.setdefault(key, []).append((n, s))
    for (scene, npcs, dump), items in groups.items():
        t0 = time.time()
        d2b.reset_scene()
        ps, ground = build_scene(scene, npcs=npcs, context=not args.no_context, dump=dump)
        t_load = time.time() - t0
        D = ps.merged()
        if args.probe:
            for n, s in items:
                print(f"{n}:")
                probe(D, s)
            continue
        d2b.build_meshes(ps)
        nl = d2b.build_lights(ps)
        t_build = time.time() - t0
        print(f"[{scene}] {ps.count()} parts, {nl} lights; load {t_load:.1f}s, build {t_build:.1f}s; "
              + ", ".join(f"{s['label']}:{s['parts']}" for s in ps.sources))
        ground_objs = []
        for n, s in items:
            ts = time.time()
            g = dict(ground)
            g.update(s.get("ground", {}))
            for ob in ground_objs:
                bpy.data.objects.remove(ob)
            ground_objs = []
            wz = g.get("water_z")          # scene frame z of the quay: land plane north, sea plane south
            ground_objs.append(d2b.add_ground(g["y"], g.get("center", (0, 0)), kind=g["kind"], color=g["color"],
                                              hole=g.get("hole"), zrange=(-1e9, wz) if wz is not None else None))
            if wz is not None:
                ground_objs.append(d2b.add_ground(g["sea_y"] - 0.4, g.get("center", (0, 0)), kind="water", color=WATER_RGB,
                                                  zrange=(wz, 1e9)))
            # fresh lights/world per shot
            for ob in [o for o in bpy.data.objects if o.name.startswith("Sun")]:
                bpy.data.objects.remove(ob)
            if args.sun_az is not None:
                s["sun_az"] = args.sun_az
            if args.fog is not None:
                s["fog"] = args.fog
            p = d2b.setup_world(s["preset"], s.get("sun_az", 210.0), overrides=dict(
                {k: s[k] for k in ("fog_start", "fog_depth") if k in s}))
            # interior light scale for the preset
            for ob in bpy.data.objects:
                if ob.type == "LIGHT" and ob.name.startswith("L"):
                    base = ob.get("base_energy")
                    if base is None:
                        ob["base_energy"] = ob.data.energy
                        base = ob.data.energy
                    ob.data.energy = base * p["lights"] * s.get("lights", 1.0)
            res = args.res or ((800, 450) if args.preview else RENDER_DEFAULTS["res"])
            samples = args.samples or (16 if args.preview else s.get("samples", RENDER_DEFAULTS["samples"]))
            exposure = p["exposure"] + s.get("exposure", 0.0) + (args.exposure or 0.0)
            d2b.setup_render(res, samples, exposure, p["look"], fast=args.preview)
            fog = s.get("fog", p["fog"])
            d2b.setup_compositor(fog, p["fog_color"], s.get("bloom", p["bloom"]))
            cam, look, lens = s["cam"], s["look"], s.get("lens", 35)
            if args.cam:
                cam = args.cam
            if args.look:
                look = args.look
            if args.lens:
                lens = args.lens
            d2b.set_camera(cam, look, lens)
            suffix = args.suffix or ("_preview" if args.preview else "")
            out = os.path.join(args.out or OUT, f"{n}{suffix}.png")
            bpy.context.scene.render.filepath = out
            if args.blend:
                bpy.ops.wm.save_as_mainfile(filepath=os.path.join(args.out or OUT, f"{n}.blend"))
            tr = time.time()
            bpy.ops.render.render(write_still=True)
            secs = time.time() - tr
            print(f"  {n}: {out}  {res[0]}x{res[1]} {samples} spp  render {secs:.1f}s")
            try:                      # re-read: other shots.py processes may have logged meanwhile
                log = json.load(open(log_path))
            except Exception:
                pass
            log[n + suffix] = dict(path=out, desc=s.get("desc", ""), scene=scene, res=list(res), samples=samples,
                                   preset=s["preset"], render_s=round(secs, 1), scene_build_s=round(t_build, 1),
                                   parts=ps.count(), lights=nl, cam=list(cam), look=list(look), lens=lens,
                                   when=time.strftime("%Y-%m-%d %H:%M:%S"))
            tmp = log_path + f".{os.getpid()}.tmp"
            json.dump(log, open(tmp, "w"), indent=1)
            os.replace(tmp, log_path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("shots", nargs="*")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--preview", action="store_true", help="800x450, 16 spp")
    ap.add_argument("--probe", action="store_true", help="only check camera placement against the geometry")
    ap.add_argument("--samples", type=int)
    ap.add_argument("--res", type=lambda s: tuple(int(v) for v in s.split("x")))
    ap.add_argument("--preset", choices=sorted(d2b.PRESETS))
    ap.add_argument("--exposure", type=float, help="extra exposure (stops)")
    ap.add_argument("--dump", help="use this dump instead of the scene's default (hqN: HQ dump; world: world dump)")
    ap.add_argument("--scene", help="override the shot's scene (hq1..hq4, world, district_full)")
    ap.add_argument("--cam", type=d2b._vec)
    ap.add_argument("--look", type=d2b._vec)
    ap.add_argument("--lens", type=float)
    ap.add_argument("--sun-az", type=float, help="override the sun azimuth (0 = sun towards -Z, 90 = towards +X)")
    ap.add_argument("--fog", type=float, help="override the haze strength (0 = off)")
    ap.add_argument("--npcs", action="store_true", help="include NPC rigs in every shot")
    ap.add_argument("--no-npcs", action="store_true")
    ap.add_argument("--no-context", action="store_true", help="hqN: HQ alone on the ground plane")
    ap.add_argument("--out", help="output folder (default out/blenderprev)")
    ap.add_argument("--suffix", default="")
    ap.add_argument("--blend", action="store_true", help="also save <shot>.blend")
    a = ap.parse_args()
    if a.list or not a.shots:
        for k, s in SHOTS.items():
            print(f"{k:18s} {s['scene']:14s} {s['preset']:7s} {s['desc']}")
        return
    names = list(SHOTS) if a.shots == ["all"] else a.shots
    if names == ["custom"]:
        if not (a.cam and a.look and a.scene):
            raise SystemExit("custom needs --scene --cam --look")
        SHOTS["custom"] = dict(scene=a.scene, desc="custom", cam=a.cam, look=a.look, lens=a.lens or 35,
                               preset=a.preset or "day")
    for n in names:
        if n not in SHOTS:
            raise SystemExit(f"unknown shot {n}; --list shows them")
    if a.out:
        os.makedirs(a.out, exist_ok=True)
    render_shots(names, a)


if __name__ == "__main__":
    main()
