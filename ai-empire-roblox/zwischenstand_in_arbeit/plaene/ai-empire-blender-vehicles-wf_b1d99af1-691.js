export const meta = {
  name: 'ai-empire-blender-vehicles',
  description: 'Model an A380-like and an A320-like airliner and a car in Blender (headless bpy), export FBX for Roblox, critique renders against real proportions, fix',
  phases: [
    { title: 'Model', detail: '3 modelers in parallel (bpy scripts, FBX export, preview renders)' },
    { title: 'Critique', detail: 'independent critic per model compares renders with real reference data' },
    { title: 'Fix', detail: 'modeler applies the critique and re-exports' },
  ],
}
const ROOT = '/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad'
const COMMON = `You are a senior 3D artist + technical artist building game-ready vehicles for the Roblox game "AI Empire" using Blender's Python API headlessly. Blender is installed as the Python module bpy 5.0.1 (python3 -c "import bpy"); there is no GUI. FBX/OBJ export and Cycles CPU rendering work headlessly (EEVEE may not — use Cycles with low samples, e.g. 32, denoise if available, resolution ~1280x720). Work ONLY in your directory (given below); never touch ${ROOT}/work or ${ROOT}/src.
GOAL: a model that looks clearly like the real vehicle type at first glance, clean and stylish for Roblox (not photoreal), game-ready, with correct real-world proportions.
RULES:
- Generic in-game identity: NO real brand names, logos or trademarked liveries anywhere (Roblox IP rules). Use the generic name given below. A tasteful generic livery (white fuselage, coloured tail/cheatline in a neutral fictional airline style "AI Empire Air") is fine.
- Real proportions from published specifications — look them up yourself (WebSearch/WebFetch are available; cite your sources in the README) instead of trusting memory; never invent numbers silently.
- Roblox scale: verify Roblox's recommended real-world-to-stud scale and the current per-mesh triangle limit and import rules for MeshParts / the 3D Importer from the official Roblox documentation (create.roblox.com/docs, e.g. the art/modeling specifications pages) and state them with source in your README. Export in studs-friendly units so the model arrives at the correct size (document the scale factor and the export settings you used; test by re-importing your FBX into bpy and measuring bounding boxes).
- Split into separate named mesh objects by function so code can animate them: airliners → Fuselage, Wing_L, Wing_R, Engine_1..N (nacelle + fan as separate "Fan_1..N" for spinning), HStab_L/R, VStab, Rudder, Elevator_L/R, Aileron_L/R, Flap_L/R (inner/outer if useful), Spoiler panels optional, NoseGear, MainGear_* (each gear leg + wheels as objects so they can retract), Door_* (passenger doors), Cockpit windows as part of the fuselage material zones or separate WindowStrip meshes; the car → Body, Wheel_FL/FR/RL/RR (pivots at the wheel centre, axle along local X), Steering wheel optional, Interior simple, Seat_Driver anchor. Every object's origin/pivot must be at its real hinge/axis (control surfaces at the hinge line, wheels at the axle, fans at the engine axis, gear at the strut pivot) — document pivots in a JSON manifest (name → pivot position in studs, hinge axis, rotation limits).
- Keep EVERY object under the Roblox per-mesh triangle limit you verified; total triangles reasonable (airliner A380-like ≤ ~60k, A320-like ≤ ~35k, car ≤ ~15k). Smooth shading with sensible auto-smooth/normals, no non-manifold garbage, applied transforms, consistent normals (outward).
- Materials: simple named materials with base colours (Roblox imports materials/colours; textures optional — if you bake a small livery/window texture keep it ≤ 1024px and embed or ship it next to the FBX).
- Deliverables in your directory: model.py (the full reproducible bpy script), <Name>.fbx, <Name>.obj (+ .mtl), manifest.json (objects, triangle counts, pivots, scale, dimensions in studs and metres), renders: front, side, top, 3/4 view, plus a close-up (cockpit/engine or wheel) as PNG; README.md with sources (real dimensions, Roblox scale + limits), export settings and a step-by-step "import into Roblox Studio" guide: File → Import 3D (or Avatar/Asset Manager as documented), where to put the result in the place so the game code finds it: ReplicatedStorage › VehicleAssets › <Name> (a Model whose children are the MeshParts named exactly like the objects above), and what to set (Anchored false for vehicles, CanCollide on fuselage/body only, etc.).
- LOOK at your renders with the Read tool and iterate until the model is convincing (silhouette from all views, proportions, smoothness, no gaps between parts). Report honestly what is simplified.
Final message: concise summary — what was built, dimensions (m and studs), triangle counts per object and total, file paths, what you verified (re-import measurement, triangle limits, sources), what is simplified, open issues.
RESUME: a previous attempt was interrupted by a usage limit. Your directory may already contain that attempt's work (model.py, FBX/OBJ, manifest, renders, research notes). Read it first, keep what is good, fix what is broken, finish what is missing (e.g. renders, README with sources, import check) — do not start over unless it is unusable.`
const MODELS = [
  { key: 'skyliner380', name: 'Skyliner380', brief: 'a full-length DOUBLE-DECK, FOUR-ENGINE wide-body airliner with the proportions of the Airbus A380-800 (look up: length, wingspan, height, fuselage width/height, wing sweep and area, engine positions, landing gear arrangement incl. body gears). Distinctive features that must read: full-length upper deck with two rows of windows, large wing with winglet fences, four underwing engines, large vertical tail, 22-wheel main gear arrangement (simplified but recognisable).' },
  { key: 'skyliner320', name: 'Skyliner320', brief: 'a NARROW-BODY, TWIN-ENGINE single-aisle airliner with the proportions of the Airbus A320neo family A320 (look up length, wingspan incl. sharklets, height, fuselage diameter, engine size/position, gear). Distinctive: single deck with one window row, two large underwing engines, sharklet wingtips, typical rounded nose and cockpit window shape, low-mounted wings with sweep.' },
  { key: 'citycar', name: 'CityCar', brief: 'a modern compact executive electric car (generic, no brand) — think a contemporary 4-door premium EV sedan: realistic proportions (look up typical dimensions of a mid-size EV sedan: length ~4.7 m, width ~1.85 m, height ~1.45 m, wheelbase ~2.8 m — verify with a real reference), smooth body, glass greenhouse, headlight/taillight strips (emissive-coloured material), 4 separate wheels with rims and tyres, simple interior with seats and steering wheel; must match the game\'s existing car seat/size conventions — read ${ROOT}/work/src/ServerScriptService/Server/Services/VehicleService.module.luau and ${ROOT}/work/src/ReplicatedStorage/Shared/Config/CampusConfig.module.luau (CARS length/width in studs) read-only and state how your size relates (the code can scale; prefer real proportions at Roblox scale).' },
]
const CRIT_SCHEMA = { type: 'object', properties: {
  verdict: { type: 'string', enum: ['good', 'needs_fixes'] },
  proportion_errors: { type: 'array', items: { type: 'string' } },
  visual_issues: { type: 'array', items: { type: 'string' } },
  technical_issues: { type: 'array', items: { type: 'string' } },
  ip_issues: { type: 'array', items: { type: 'string' } },
  fixes: { type: 'array', items: { type: 'string' } } },
  required: ['verdict', 'proportion_errors', 'visual_issues', 'technical_issues', 'ip_issues', 'fixes'] }
const results = await pipeline(MODELS,
  m => agent(`${COMMON}
YOUR MODEL: "${m.name}" — ${m.brief}
Your directory: ${ROOT}/assets/vehicles/${m.key}/ (create it).`, { label: `model:${m.key}`, phase: 'Model' }),
  (summary, m) => agent(`You are an independent, strict reviewer of a game-ready 3D vehicle model for Roblox. Do NOT edit any files. Directory: ${ROOT}/assets/vehicles/${m.key}/ (renders *.png, manifest.json, README.md, model.py, FBX/OBJ). The model should be: ${m.brief}
Check with your own eyes (Read the PNG renders) and your own research (WebSearch/WebFetch the real specifications and Roblox's official mesh import limits/scale): silhouette and proportions vs the real type from front/side/top (measure ratios from manifest.json dimensions vs real data: length, span, height, fuselage diameter, engine size/position, wheelbase…), visual quality (smoothness, gaps, floating parts, wrong normals, ugly faceting), technical readiness (objects split as required, pivots at hinges/axles per manifest, triangle counts under the verified Roblox per-mesh limit, scale documented and consistent, re-import measurement plausible, materials sane), and IP (no real brand names/logos/trademarked liveries). The modeler's summary: ${JSON.stringify(summary).slice(0, 3000)}
Return a precise list of fixes (each actionable: what, where, target value).`, { label: `critique:${m.key}`, phase: 'Critique', schema: CRIT_SCHEMA }),
  (crit, m) => crit && crit.verdict === 'good' ? { key: m.key, critique: crit, final: 'accepted by critic' } :
    agent(`${COMMON}
YOUR MODEL: "${m.name}" — ${m.brief}
Your directory: ${ROOT}/assets/vehicles/${m.key}/ (it already contains your first version: model.py, exports, renders, manifest, README).
An independent reviewer found these problems — fix ALL of them in model.py, re-run it, re-export, re-render, update manifest/README, LOOK at the new renders, and iterate until clean:
${JSON.stringify(crit, null, 1)}`, { label: `fix:${m.key}`, phase: 'Fix' }).then(r => ({ key: m.key, critique: crit, final: r })))
return results
