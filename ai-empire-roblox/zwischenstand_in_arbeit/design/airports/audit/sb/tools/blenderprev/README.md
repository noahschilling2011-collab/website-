# blenderprev - Cycles previews of the real AI Empire geometry

Headless `bpy` 5.0.1 (Cycles CPU, OpenImageDenoise). Input = harness dumps; nothing is modelled by hand
(the only additions are a backdrop ground/water plane, sky, sun and PlotService's VacantPad blocks).

```bash
# inputs (once, or after source changes)
GEN=blenderprev harness/run.sh --out out/blenderprev/dumps                 # HQ tiers 1-4 -> dump_tierN.json
TIERS="0" GEN=blenderprev harness/run.sh --out out/blenderprev/dumps       # garage stage -> dump_tier0.json
tools/blenderprev/world_dump.sh                                             # district + city -> out/blenderprev/world/world_dump.json

python3 tools/blenderprev/shots.py --list                         # named shots
python3 tools/blenderprev/shots.py airport_aerial                 # one shot, 1600x900, 64 spp (interiors 48)
python3 tools/blenderprev/shots.py all                            # every shot (~2-3 h on 4 shared cores)
python3 tools/blenderprev/shots.py hq4_aerial --dump X.json --preset night   # any HQ dump / lighting
python3 tools/blenderprev/shots.py hq4_aerial --scene hq2         # same camera on another tier (hq0..hq4)
python3 tools/blenderprev/shots.py custom --scene world --cam -1350,760,560 --look -60,40,1600 --lens 35
python3 tools/blenderprev/shots.py pm_hotel --sun-az 40 --fog 0.1 # override sun azimuth / haze
python3 tools/blenderprev/shots.py hq4_cafe --preview             # 800x450, 16 spp (~30-60 s)
python3 tools/blenderprev/shots.py hq4_cafe --probe               # camera inside a part? clearance?
python3 tools/blenderprev/dump2blend.py DUMP.json --cam x,y,z --look x,y,z --out a.png [--blend a.blend]
python3 tools/blenderprev/check_orientation.py                   # axis/handedness/wedge self-check
```

All coordinates are Roblox studs (Y up, Front = -Z). Images: `out/blenderprev/<shot>.png`, timings in
`out/blenderprev/render_log.json`.

* `dump2blend.py` - parts -> merged meshes per material (face attributes carry colour / opacity / random),
  shapes (Block, Wedge, CornerWedge, Cylinder, Ball, SpecialMesh Head/Sphere/Cylinder), materials, lights,
  presets `day` / `golden` / `night`, aerial haze + bloom compositor, probes.
* `shots.py` - scenes (`hqN` = HQ dump tier N on Plot_10 inside the real district, `world`,
  `district_full` = 12 HQs on their plot CFrames) and the shot table.
* `world_dump.sh` - copy of agents/world/world_dump.sh writing only to out/blenderprev/world.

## Shots

| shot | scene | what |
|---|---|---|
| hq4_aerial, hq4_night | hq4 | campus plot 3/4 aerial (day / night) |
| hq4_entrance, hq4_plaza | hq4 | entrance + canopy at eye height, plaza |
| hq4_atrium, hq4_cafe, hq4_datahall, hq4_office, hq4_founder | hq4 | interiors |
| guesthouse_exterior, guesthouse_room, guesthouse_lobby, guesthouse_breakfast | hq4 | the hotel annex (tiers 2-4) |
| hq0_aerial, hq0_garage | hq0 | garage stage (tier 0) next to the HQ construction site |
| hq1_aerial | hq1 | first office (tier 1) |
| city_aerial, city_boulevard, city_hotel | world | Business City / Downtown |
| airport_aerial, airport_apron, airport_terminal | world | airport (airside, landside, terminal front) |
| pm_aerial, pm_waterfront, pm_hotel | world | Port Meridian |
| district_aerial | district_full | all 12 plots claimed with mixed tiers |

## Not represented

SurfaceGui/Billboard text and images (signs and screens are blank dark panels), decals/textures (Roblox
material textures are only hinted at with procedural noise), MeshPart/Union meshes (bounding boxes; none in
the current dumps), particles/beams/fire, Terrain (none used), NPC animation (rigs stand/sit as dumped),
vehicles/players spawned at runtime. Lighting is Cycles path tracing approximating Roblox Future lighting;
light power is a tuned mapping of Brightness x Range^2 without Roblox's hard range cut-off. Sun azimuth is
chosen per shot for the picture, not taken from the game's ClockTime/latitude. The world outside the dumps
is a flat grass plane (north of the airport quay) and a flat water plane (south of it, also around Port
Meridian); the game's own Sea parts are light teal Glass slabs and render as such.
