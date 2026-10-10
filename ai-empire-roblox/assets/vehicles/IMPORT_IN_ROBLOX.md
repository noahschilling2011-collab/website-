# Importing the Blender aircraft into Roblox Studio (one time, needs Studio)

The game runs WITHOUT these meshes: `ReplicatedStorage/Shared/AircraftModel` builds both airliners from
ordinary parts (~345 parts for the narrow-body, ~355 for the double-deck). If you import the meshes once,
the same code uses them automatically for every full-detail aircraft (parked aircraft on the aprons, the
Port Meridian shuttle, the cutscene/fallback plane). Far-away aircraft keep the light part models.

This step cannot be done by a script or by Claude: the Studio 3D Importer is an interactive Studio tool and
every imported mesh gets an asset id from Roblox when you publish. Nothing in the code invents asset ids.

## What you need
| File | Model name in Studio | Used for |
|---|---|---|
| `assets/vehicles/skyliner320/Skyliner320.fbx` | `Skyliner320` | kind "320" (narrow-body twin, the shuttle) |
| `assets/vehicles/skyliner380/Skyliner380.fbx` | `Skyliner380` | kind "380" (double-deck, four engines) |

Both files are in studs (1 Blender unit = 1 stud, real size: 134.2 and 259.7 studs long), nose towards -Z,
up = +Y, origin on the ground under the aircraft (see each `manifest.json`).

## Steps (per file)
1. Open the place in Roblox Studio. Home tab -> **Import 3D** (File -> Import 3D also works).
2. Pick the `.fbx` file. In the import window:
   - **Import only as a model**: on (one Model with one MeshPart per part of the aircraft).
   - **Set Pivot to Scene Origin**: on (the Model pivot must be the aircraft origin on the ground).
   - **World Forward**: Front, **World Up**: Top.
   - **Scale unit**: Stud (do NOT let Studio rescale; the file is already in studs).
   - **Merge meshes**: off. **Anchored**: either (the code anchors everything).
   - Keep the vertex colours / materials.
3. Click **Import**. Studio uploads the meshes (you must be logged in; the place may need to be published once).
4. In the Explorer, create the folders `ReplicatedStorage/Assets/Aircraft` (or use the existing
   `ReplicatedStorage/VehicleAssets` folder from the asset manifests - both locations are checked).
5. Move the imported Model into that folder and rename it exactly `Skyliner320` (or `Skyliner380`).
   Its children must stay MeshParts named as in the manifest (`Fuselage`, `Wing_L`, `Fan_1`, `NoseGear`, ...).
6. Do not scale the Model in Studio. The code scales a clone per use (`Model:ScaleTo`): the stand aircraft and
   the shuttle use scale 1.8 of the old 66-stud reference = 0.885 x real size.
7. Publish / save the place.

## What the code does with it
- `AircraftModel.meshTemplate(kind)` looks for `ReplicatedStorage.Assets.Aircraft.<Name>` and then
  `ReplicatedStorage.VehicleAssets.<Name>`.
- `AircraftModel.build` (lod "full", option `mesh ~= false`) clones it, anchors every part, lets only the
  `Fuselage` collide when `collide = true`, marks `Fan*` parts as spinning and `*Gear*`/`*Wheel*` parts as
  landing gear (hidden in flight by the client), scales it, places it, and adds the same invisible
  `AircraftRoot` with the boarding attachments (`DoorL1` with `BoardingDoor = true`, `CaptainSeat`,
  `FirstOfficerSeat`, `CockpitCamera`, `CabinCamera`, `CabinSeat1..6`). Jet bridges, pilots and cameras
  therefore line up with both versions.
- Medium and low LODs (distant aircraft, air traffic) always use the light part models.

## Check in Studio (Play Solo)
- The parked aircraft at City Airport gates A1-A3 and the aircraft at Port Meridian show the mesh version.
- The shuttle at gate A1 is the mesh version on the client; its fans spin after "Doors closed".
- If anything looks wrong (rotated by 90/180 degrees, tiny/huge): delete the folder entry - the game falls back
  to the part models immediately - and re-import with the settings above.

## Not verified here
The import itself, the Studio orientation of the imported meshes and the mesh collision fidelity can only be
checked in Studio. The FBX files were re-imported into Blender for checking (`import_check.json`).
