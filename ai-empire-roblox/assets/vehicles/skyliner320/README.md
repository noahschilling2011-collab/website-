# Skyliner320 – generic narrow-body twin-jet for "AI Empire"

Game-ready, stylised airliner with the proportions of the Airbus A320neo, built headless with
`bpy 5.0.1` (`model.py` is the full, reproducible build). It has a fictional, generic identity:
no real brand names, logos or real liveries. The livery is "AI Empire Air": white fuselage, blue fin
with a white "AI" mark, a blue/gold cheatline and blue sharklets/nacelles.

| File | What it is |
|---|---|
| `model.py` | Full build script: geometry, materials, pivots, export, manifest, renders, re-import check |
| `Skyliner320.fbx` | **The file to import into Roblox Studio.** 34 mesh objects, vertex colours + materials, 1 unit = 1 stud |
| `Skyliner320.obj` + `Skyliner320.mtl` | Same geometry for other tools (same frame and scale; no vertex colours) |
| `manifest.json` | Objects, triangles, materials, pivots (studs), hinge axes, rotation limits, dimensions (m + studs) |
| `import_check.json` | Results of re-importing the FBX/OBJ into bpy plus a raw parse of the FBX file |
| `render_front.png`, `render_side.png`, `render_top.png`, `render_34.png`, `render_34_rear.png`, `render_closeup.png` | Cycles renders (CPU, OIDN denoise) |
| `_ref/` | Research material, **not a deliverable**: local copies of the Roblox docs pages used (`*.md`), plus the Airbus AC PDF, its text dump and page crops. The Airbus files are third-party copyrighted material kept for reference only: **do not commit or ship them with the game.** |
| `_tmp/` | Internal check scripts (`check_render.py`, `retract_check.py`, `angle_scan.py`, `sign_check.py`, `overlay.py`) and their output images. Not a deliverable. |

Rebuild everything (5–8 minutes on CPU, almost all of it rendering):

```bash
python3 model.py              # build, export, manifest, renders, re-import check
python3 model.py --no-render  # same, without the renders (about 4 s)
```

---

## 1. Real-world dimensions and what the model has

The primary source is the Airbus **A320 "Aircraft Characteristics – Airport and Maintenance Planning"**
document (AC), Rev. May 01/17, the chapters marked "ON A/C A320neo", hosted by SKYbrary:
<https://skybrary.aero/sites/default/files/bookshelf/2369.pdf> (local copy in `_ref/skybrary_2369.pdf`).
The headline numbers were cross-checked against Airbus' product page
<https://www.aircraft.airbus.com/en/aircraft/a320-family/a320neo> and Wikipedia.

| Item | Real A320neo | Source | Skyliner320 (m) | Studs |
|---|---|---|---:|---:|
| Overall length | 37.57 m | Airbus page; AC fig. 2-2-0-991-009 | 37.570 | 134.18 |
| Wingspan (with sharklets) | 35.80 m | Airbus page; AC fig. 2-2-0-991-009 | 35.799 | 127.85 |
| Overall height | 11.76 m (Airbus page); 11.83–12.08 m depending on weight/CG (AC table 2-3-0, "VT") | Airbus page; AC fig. 2-3-0-991-032 | 11.800 | 42.14 |
| Fuselage width | 3.95 m | Airbus page; AC | 3.95 | 14.11 |
| Fuselage height | 4.14 m | AC fig. 2-2-0-991-009 | 4.14 | 14.79 |
| Fin height above fuselage crown | 5.87 m | AC fig. 2-2-0-991-009 | 5.86 | 20.9 |
| Horizontal tail span | 12.45 m | AC fig. 2-2-0-991-009 | 12.46 | 44.5 |
| Wheelbase (nose gear → main gear) | 12.64 m | AC | 12.64 | 45.14 |
| Nose gear aft of the nose | 5.07 m | AC | 5.07 | 18.1 |
| Main gear track | 7.59 m | AC | 7.59 | 27.11 |
| Main wheel spacing on the axle | 0.927 m | AC 7-2-0 | 0.927 | 3.31 |
| Main tyres | 46x17R20 (Ø 1.168 m) | AC 7-2-0 | Ø 1.168 | 4.17 |
| Nose tyres | 30x8.8R15 (Ø 0.762 m) | AC 7-2-0 | Ø 0.762 | 2.72 |
| Engine centreline from aircraft centreline | 5.75 m | AC fig. 2-2-0-991-009 | 5.75 | 20.54 |
| Nacelle (LEAP-1A) max. diameter | 2.52 m (2.60 m incl. fairings) | AC fig. 2-12-0-991-055 | 2.57 | 9.18 |
| Nacelle ground clearance | 0.46–0.56 m | AC table 2-3-0 (N1, LEAP-1A) | 0.52 | 1.85 |
| Fan diameter | 78 in = 1.98 m (LEAP-1A) | <https://en.wikipedia.org/wiki/CFM_International_LEAP>, <https://en.wikipedia.org/wiki/Airbus_A320neo_family> | 1.95 (blade tips inside the inlet lip) | 6.96 |
| Door sill heights | D1 3.48 m, D3 3.70 m (CG 26.5 %) | AC table 2-3-0 | same | – |
| Wing sweep | 25° | <https://en.wikipedia.org/wiki/Airbus_A320_family> (planform traced from AC fig. 2-2-0-991-009) | 25° at ¼ chord (27.7° leading edge) | – |

The fuselage side/top profiles, the cockpit window corners, the cabin window pitch (0.533 m),
the wing/tail planforms and the nacelle profile were traced from the AC drawings, scaled to 37.57 m.
`_tmp/overlay.py` overlays the AC drawings on the orthographic renders for checking.

## 2. Roblox rules (official docs, read 2026-10-04; each page says `last_updated: 2026-10-02`)

| Rule | Value | Source |
|---|---|---|
| Real-world scale | **1 stud = 28 cm**, so 1 m = 3.5714 studs. The docs recommend standard Roblox units. | <https://create.roblox.com/docs/physics/units> |
| Triangle budget | "Individual meshes can not exceed **20,000 triangles**." Meshes must also be watertight, have volume, and use no n-gons. | <https://create.roblox.com/docs/art/modeling/specifications> |
| Import | File ▸ **Import** opens the Importer. `.fbx`, `.obj`, `.gltf`. **FBX/glTF** support multiple mesh objects, hierarchies and **vertex colours**. Options: Import Only As Model, Upload to Roblox, Add to Workspace, Set Pivot to Scene Origin, Anchored, World Forward/Up, Scale Unit, Merge Meshes, Use Imported Pivot, Ignore Vertex Colors | <https://create.roblox.com/docs/studio/importer> (formerly `/docs/art/modeling/3d-importer`) |
| Blender FBX export | Path Mode **Copy** + **Embed Textures**; Apply Scalings **FBX Unit Scale**; no leaf bones; no baked animation | <https://create.roblox.com/docs/art/modeling/export-requirements> |
| Blender axes / scale | Export with **Forward = Z Forward, Up = Y Up**. Import with **World Forward = Front, World Up = Top, Scale Unit = Stud**. "FBX Unit Scale" is "the recommended way to export .fbx files at the same scale" | <https://create.roblox.com/docs/art/blender> (sections "Export settings", "Blender to Studio", "Adjust scale (FBX)") |

Local copies of these pages are in `_ref/*.md`.

## 3. Export settings used (done by `model.py`)

* Built in metres, then every mesh is scaled by 1/0.28, so **1 Blender unit = 1 stud**
  (scene Unit System = None, Unit Scale 1.0).
* **FBX** (`bpy.ops.export_scene.fbx`): `axis_forward='Z'`, `axis_up='Y'`,
  `apply_scale_options='FBX_SCALE_UNITS'`, `global_scale=1.0`, `apply_unit_scale=True`,
  `bake_space_transform=True` ("Apply Transform", so every node has rotation 0 and scale 1 and the
  vertices are already Y-up), `path_mode='COPY'`, `embed_textures=True`, `add_leaf_bones=False`,
  `bake_anim=False`, `colors_type='SRGB'`, `mesh_smooth_type='FACE'`, `use_triangles=True`,
  mesh objects only. No textures are used, so nothing has to be embedded.
* **OBJ** (`bpy.ops.wm.obj_export`): `forward_axis='Z'`, `up_axis='Y'`, scale 1, normals + UVs +
  materials (`.mtl` with Kd colours), triangulated.
* **Frame in the files** (equal to Roblox's frame): **X = starboard (right wing), Y = up, Z = aft**.
  The **nose points to −Z**, which is Roblox's LookVector. Origin (0,0,0) = on the ground under the
  centreline, at mid-length (18.785 m behind the nose). The wheels touch Y = 0.

## 4. Object list, pivots and hinges

Every object's origin is its real pivot: control surfaces sit on their hinge line, the fans on the
engine axis, the gear legs at the strut trunnion, the wheels at the axle and the doors at their
forward hinge edge. Pivots and axes are in **model space, in studs**, relative to the model origin.
Rotations use the right-hand rule: `CFrame.fromAxisAngle(axis, math.rad(angle))` about the pivot.
A positive angle gives the motion in the "Positive rotation" column. `manifest.json` holds the same
data with more decimals, plus bounding boxes, hinge-line end points and per-object fallback colours.

| Object | Kind | Tris | Pivot (studs) | Hinge axis | Limits (°) | Positive rotation | CanCollide |
|---|---|---:|---|---|---|---|---|
| Fuselage | static | 7668 | 0.00, 0.00, 0.00 | – | – | – | **true** |
| WindowStrip_L | static | 1968 | -7.07, 16.43, -6.73 | – | – | – | false |
| WindowStrip_R | static | 1968 | 7.07, 16.43, -6.73 | – | – | – | false |
| CockpitWindows | static | 536 | 0.00, 16.07, -58.88 | – | – | – | false |
| Titles | static | 2304 | 0.00, 18.71, -27.09 | – | – | – | false |
| TailLogo | static | 368 | 0.00, 31.25, 52.73 | – | – | – | false |
| Door_1L | door | 764 | -6.60, 15.73, -50.54 | 0, -1, 0 | 0 .. 100 | door opens (aft edge swings outboard) | false |
| Door_1R | door | 764 | 6.60, 15.73, -50.54 | 0, 1, 0 | 0 .. 100 | door opens | false |
| Door_2L | door | 728 | -6.44, 16.52, 36.93 | 0, -1, 0 | 0 .. 100 | door opens | false |
| Door_2R | door | 728 | 6.44, 16.52, 36.93 | 0, 1, 0 | 0 .. 100 | door opens | false |
| Wing_L | static | 1232 | -7.07, 10.18, -21.06 | – | – | – | false |
| Wing_R | static | 1232 | 7.07, 10.18, -21.06 | – | – | – | false |
| Flap_L_In | control | 36 | -14.88, 11.16, -4.55 | 0.985, -0.080, -0.155 | 0 .. 40 | trailing edge down | false |
| Flap_L_Out | control | 36 | -33.91, 12.75, 0.83 | 0.934, -0.080, -0.348 | 0 .. 40 | trailing edge down | false |
| Flap_R_In | control | 36 | 14.88, 11.16, -4.55 | 0.985, 0.080, 0.155 | 0 .. 40 | trailing edge down | false |
| Flap_R_Out | control | 36 | 33.91, 12.75, 0.83 | 0.934, 0.080, 0.348 | 0 .. 40 | trailing edge down | false |
| Aileron_L | control | 36 | -50.79, 14.18, 7.57 | 0.938, -0.081, -0.337 | -25 .. 25 | trailing edge down | false |
| Aileron_R | control | 36 | 50.79, 14.18, 7.57 | 0.938, 0.081, 0.337 | -25 .. 25 | trailing edge down | false |
| HStab_L | static | 288 | -3.39, 18.04, 47.45 | – | – | – | false |
| HStab_R | static | 288 | 3.39, 18.04, 47.45 | – | – | – | false |
| Elevator_L | control | 36 | -12.59, 19.00, 59.06 | 0.941, -0.099, -0.323 | -30 .. 17 | trailing edge down (nose-down pitch) | false |
| Elevator_R | control | 36 | 12.59, 19.00, 59.06 | 0.941, 0.099, 0.323 | -30 .. 17 | trailing edge down | false |
| VStab | static | 588 | 0.00, 21.21, 36.12 | – | – | – | false |
| Rudder | control | 136 | 0.00, 32.05, 57.78 | 0, -0.922, -0.387 | -30 .. 30 | trailing edge to port (nose-left yaw) | false |
| Engine_1 | static | 1940 | -20.54, 6.43, -25.09 | – | – | – | false |
| Engine_2 | static | 1940 | 20.54, 6.43, -25.09 | – | – | – | false |
| Fan_1 | spin | 848 | -20.54, 6.43, -25.09 | 0, 0, -1 | continuous | clockwise seen from behind | false |
| Fan_2 | spin | 848 | 20.54, 6.43, -25.09 | 0, 0, -1 | continuous | clockwise seen from behind | false |
| NoseGear | gear | 192 | 0.00, 8.75, -48.98 | 1, 0, 0 | 0 .. 95 | retract (wheels swing forward and up) | false |
| NoseWheels | wheel | 896 | 0.00, 1.36, -48.98 | -1, 0, 0 | continuous | rolling forward; child of NoseGear | false |
| MainGear_L | gear | 236 | -13.55, 10.89, -5.62 | 0, 0, 1 | 0 .. 100 | retract (leg swings inboard and up) | false |
| MainWheels_L | wheel | 1120 | -13.55, 2.09, -3.84 | -1, 0, 0 | continuous | rolling forward; child of MainGear_L | false |
| MainGear_R | gear | 236 | 13.55, 10.89, -5.62 | 0, 0, -1 | 0 .. 100 | retract (leg swings inboard and up) | false |
| MainWheels_R | wheel | 1120 | 13.55, 2.09, -3.84 | -1, 0, 0 | continuous | rolling forward; child of MainGear_R | false |
| **Total** | | **31,224** | | | | | |

* Engine_1/Fan_1 is the port (left) engine and Engine_2/Fan_2 the starboard (right) one. Each fan shares its engine's pivot on the engine axis.
* The largest single mesh is the Fuselage at 7,668 triangles, 38 % of the 20,000 limit. The total
  of 31,224 is under the ≤ 35k target for an A320-class model.
* Every mesh is closed (0 non-manifold edges) and has a positive signed volume (normals point
  outward). It is smooth-shaded with angle-based sharp edges (30–40°) and has no n-gons
  (triangulated on export).
* The "kind" field tells game code how to treat each part. `static` parts get welded. `control`,
  `door` and `gear` parts get a hinge with limits. `spin` and `wheel` parts rotate continuously.
  A wheel set moves with its gear leg (`animate_with_parent` in the manifest).

## 5. Materials and colours

There are 15 named materials, each a single base colour. Roblox gives each MeshPart only one
`Color`/`Material`, so the per-face material colour is also **baked into vertex colours** (face
corner, sRGB). Those vertex colours carry the livery zones (cheatline, belly, door seams, nacelle
lip and so on) into Studio; the Importer's "Ignore Vertex Colors" option is off by default. No
textures are needed.

| Material | sRGB | Used for |
|---|---|---|
| Livery_White | #F3F5F8 | fuselage, doors, tail mark |
| Belly_Grey | #B7BDC5 | lower fuselage, gear doors |
| Accent_Blue | #1C3F94 | fin, rudder, cheatline, nacelles, sharklets, titles |
| Accent_Gold | #E2A72E | thin pinstripe under the cheatline |
| Wing_Grey | #C4C9D0 | wings, flaps, ailerons, tailplane, pylons |
| Window_Dark | #16202E | cabin windows |
| Cockpit_Glass | #0F1722 | cockpit windows |
| Door_Seam | #8E959E | door outlines |
| Metal_Lip | #C9CED6 | inlet lip, fan blades |
| Engine_Dark | #24272D | inlet interior, spinner area |
| Exhaust_Metal | #7D838B | core nozzle and plug |
| Gear_Grey | #8B9097 | gear legs and braces |
| Chrome | #D5D9DE | oleo pistons |
| Tire_Black | #1B1B1D | tyres |
| Hub_Silver | #A9AEB5 | wheel hubs |

## 6. Verification done (see `import_check.json`)

1. **FBX re-import into bpy**: 34 objects. Bounding box 127.853 × 42.143 × 134.179 studs
   (span × height × length), which is 35.799 × 11.800 × 37.570 m. Lowest point Y = 0. All 34
   pivots match the manifest within 0.01 stud. Triangle counts are identical. Every object has
   rotation 0 and scale 1. Every object is manifold with a positive volume. 0 mismatches.
2. **Raw FBX parse** (the file read without any axis conversion, as a Y-up importer sees it):
   GlobalSettings UpAxis = Y, UnitScaleFactor = 100 (Blender's FBX Unit Scale convention). Every
   node has Lcl Rotation (0,0,0) and Lcl Scaling 1. Node translations equal `pivot_studs` from the
   manifest. Nose at Z = −67.09, tail at Z = +67.09, port wing at −X, so **nose −Z, right wing +X,
   up +Y**, which is Roblox's own convention.
3. **OBJ re-import**: 34 objects, 35.799 × 11.800 × 37.570 m, 31,224 triangles.
4. **Animation sanity check** (`_tmp/sign_check.py`, `_tmp/retract_check.py`): every hinged part
   was rotated +10° about its manifest pivot/axis, and the motion matches "positive_rotation"
   (surfaces trailing edge down, rudder to port, doors outboard, nose gear forward, main gear
   inboard). The gear was retracted to its limits, and the flaps, ailerons, rudder and a door were
   deflected and rendered.
5. **Renders were inspected** from all views, plus close-ups of the titles, tail, gear, nose,
   underside and wing trailing edge. No gaps, no z-fighting, and the lettering is clean.

## 7. Importing into Roblox Studio

1. **File ▸ Import** and choose `Skyliner320.fbx`. Use the FBX, not the OBJ: only FBX/glTF carry
   multiple meshes and vertex colours into Studio.
2. In the Import Preview, set:
   * **File General**: Name = `Skyliner320`. **Import Only As Model = on** (the default; you get
     one `Model` with 34 MeshParts). Upload to Roblox = on if you want an asset ID. Add to
     Workspace = on. **Set Pivot to Scene Origin = on** (the default; the Model pivot becomes the
     ground/centreline/mid-length origin). **Anchored = off** (the default; it is a vehicle).
     Insert Using Scene Position = on (the Roblox Blender guide recommends it).
   * **File Transform**: **World Forward = Front**, **World Up = Top**.
   * **File Geometry**: **Scale Unit = Stud**. **Merge Meshes = off**, so every part stays a
     separate, animatable MeshPart.
   * **Object General** (per child, defaults are fine): **Use Imported Pivot = on**, so each
     MeshPart's pivot lands on its hinge/axle/fan axis and `part:GetPivot()` returns the hinge point.
     Object Geometry: Make Double Sided = off, **Ignore Vertex Colors = off**.
3. Click **Import**. Check the result:
   * The Model should be about 127.9 × 42.1 × 134.2 studs. The Importer shows the file
     dimensions; you can also run `print(workspace.Skyliner320:GetExtentsSize())` in the Command Bar.
   * **The nose must point to −Z (the Model's LookVector).** Run
     `local m = workspace.Skyliner320 print(m.CockpitWindows.Position.Z < m.Rudder.Position.Z)`.
     It should print `true`. If it prints `false`, your Studio version flips the file's forward
     axis: re-import with **World Forward = Back**. The manifest assumes the nose is at −Z.
4. **Placement for the game code**: in the Explorer, create `ReplicatedStorage ▸ VehicleAssets` (a
   `Folder`) if it does not exist yet. Move the imported Model there and name it exactly
   **`Skyliner320`**:
   `ReplicatedStorage ▸ VehicleAssets ▸ Skyliner320` is a Model whose 34 children are MeshParts,
   named exactly as in the table above. Keep the names; game code finds parts by name.
5. **Properties**:
   * Model: `PrimaryPart = Fuselage`. The `WorldPivot` stays at the scene origin (ground level), so
     `model:PivotTo(CFrame.new(x, groundY, z))` puts the tyres on the ground.
   * All MeshParts: **Anchored = false**, Material = SmoothPlastic, **Color = 255,255,255 (white)**
     so the baked vertex colours show unaltered. How vertex colours combine with `Color` is not
     spelled out in the docs. If a part looks flat grey or tinted, set `Color` to that object's
     `roblox_color_fallback` from `manifest.json`.
   * **Fuselage**: **CanCollide = true**, CanTouch = true, CanQuery = true, Massless = false,
     CollisionFidelity = Hull (cheap) or Default.
   * **Every other part**: **CanCollide = false**, CanTouch = false, Massless = true, and
     CanQuery = false. Set CanQuery = true only on the doors if players should click or raycast
     them. If you want wing-tip collisions, set Wing_L/Wing_R CanCollide = true with Hull fidelity.
   * Weld static parts to the Fuselage with `WeldConstraint`. Give animated parts a `Motor6D` at
     their pivot (snippet below).

```lua
-- Rig Skyliner320 at runtime (e.g. after cloning from ReplicatedStorage.VehicleAssets).
-- Axes are model-space hinge axes from manifest.json; a positive angle gives the manifest's "positive_rotation".
local AXES = {
	Door_1L = Vector3.new(0, -1, 0), Door_1R = Vector3.new(0, 1, 0),
	Door_2L = Vector3.new(0, -1, 0), Door_2R = Vector3.new(0, 1, 0),
	Flap_L_In = Vector3.new(0.9847, -0.07965, -0.15498), Flap_R_In = Vector3.new(0.9847, 0.07965, 0.15498),
	Flap_L_Out = Vector3.new(0.93407, -0.08013, -0.34799), Flap_R_Out = Vector3.new(0.93407, 0.08013, 0.34799),
	Aileron_L = Vector3.new(0.93795, -0.08091, -0.33721), Aileron_R = Vector3.new(0.93795, 0.08091, 0.33721),
	Elevator_L = Vector3.new(0.94112, -0.09892, -0.32328), Elevator_R = Vector3.new(0.94112, 0.09892, 0.32328),
	Rudder = Vector3.new(0, -0.9221, -0.38695),
	Fan_1 = Vector3.new(0, 0, -1), Fan_2 = Vector3.new(0, 0, -1),
	NoseGear = Vector3.new(1, 0, 0), MainGear_L = Vector3.new(0, 0, 1), MainGear_R = Vector3.new(0, 0, -1),
	NoseWheels = Vector3.new(-1, 0, 0), MainWheels_L = Vector3.new(-1, 0, 0), MainWheels_R = Vector3.new(-1, 0, 0),
}
local PARENT = { NoseWheels = "NoseGear", MainWheels_L = "MainGear_L", MainWheels_R = "MainGear_R" }

local function rig(model: Model)
	local root = model:FindFirstChild("Fuselage") :: BasePart
	model.PrimaryPart = root
	local motors = {}
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p ~= root then
			p.Anchored = false
			p.CanCollide = false
			p.Massless = true
			if AXES[p.Name] then
				local part0 = model:FindFirstChild(PARENT[p.Name] or "Fuselage") :: BasePart
				local hinge = p:GetPivot()            -- imported pivot = hinge point, model-aligned
				local m = Instance.new("Motor6D")
				m.Name = p.Name .. "_Hinge"
				m.Part0, m.Part1 = part0, p
				m.C0 = part0.CFrame:ToObjectSpace(hinge)
				m.C1 = p.CFrame:ToObjectSpace(hinge)
				m.Parent = p
				motors[p.Name] = m
			else
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = root, p
				w.Parent = p
			end
		end
	end
	return motors
end

-- usage:  local motors = rig(plane);  motors.Rudder.Transform = CFrame.fromAxisAngle(AXES.Rudder, math.rad(20))
-- Motor6D.Transform is not replicated: drive it on each client (e.g. in RunService.RenderStepped).
-- For a state that must replicate (e.g. gear down/up set by the server), change C0 instead:
--   m.C0 = baseC0 * CFrame.fromAxisAngle(AXES.MainGear_L, math.rad(100))
```

If "Use Imported Pivot" was off, the hinge is still known: `model:GetPivot() * CFrame.new(pivot_studs)`
(from `manifest.json`), with the model in its imported orientation and the Model pivot at the scene origin.

## 8. What is simplified (honest list)

* **Stylised, not photoreal**: no panel lines, no textures, no antennas or probes, no APU inlet,
  no slats, no spoiler panels (the brief marks spoilers optional), no flap-track fairing animation,
  no landing lights.
* **Control surfaces** are simple wedge solids (36 triangles each), set flush into the wing and
  tail trailing edges. Flaps rotate about a fixed hinge line, not Fowler-style along tracks.
* **Doors**: 4 passenger doors (1L/1R, 2L/2R). The overwing emergency exits and cargo doors are not
  modelled. Doors are thin hull-conforming panels that rotate about a vertical hinge at their front
  edge; real A320 doors use a parallel-arm mechanism.
* **Landing gear** is simplified: one leg per gear plus a side brace, a torque link and a strut
  door. There are no bay doors and no hollow wheel wells. Retracted, the **nose gear** (95°) sits
  completely inside the nose; this was checked with a point-in-mesh test, 0 vertices outside. The
  **main gear** pivots on a trunnion inside the wing-root box (3.05 m above the ground) and stows
  at 100°. The leg then lies inside the wing root and inner flap, with the strut door flush with
  the wing underside, and the wheels lie flat inside the belly. Point-in-mesh test: 7 of 564 wheel
  vertices are outside the hull, by at most 7 cm; 42 of 132 leg vertices are outside, by at most
  15 cm, near the wing/fuselage junction. On the real type the stowed tyres stay visible in the
  belly; here they are hidden.
* **Doors** open as panels only: there is no cut-out or interior behind them.
* **Fans** are 18 straight-twisted blades with a spinner. The fan diameter is 1.95 m against the
  LEAP-1A's 1.98 m, so the blade tips clear the modelled inlet lip. The nacelle is the LEAP-1A
  shape at 2.57 m (AC: 2.52 m bare, 2.60 m over fairings).
* **Height** is 11.80 m: between Airbus' 11.76 m marketing figure and the AC's 11.83–12.08 m
  (weight/CG dependent).
* **Interior**: none. The windows are dark inlays, not transparent.
* **Text**: "AI EMPIRE AIR" titles and the "AI" fin mark are real geometry (DejaVu Sans Bold
  outlines, free licence) sitting 1–2 cm proud of the skin. If the font is missing, `model.py`
  falls back to Blender's built-in font.

## 9. Open issues / not verifiable here

* **Studio itself could not be run here.** The import settings follow the official docs, and the
  FBX was checked by re-import into Blender and by a raw parse. The nose-direction check in step 7.3
  is there in case your Studio version treats the forward axis differently.
* How vertex colours mix with `MeshPart.Color` is not documented. Use white, or the fallback colours.
* Collision: only the Fuselage collides by default. For ground contact while taxiing, the game
  should use its own wheel raycasts/suspension or invisible collision parts at the wheel positions
  in the manifest. The visual wheels are massless and non-colliding.
