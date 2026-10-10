# Requests from package "lab" (Model Studio: the new AI creation screen, LAB_SPEC)

The Studio works without every item below (local fallbacks are in place and named per item). Each item makes it match
LAB_SPEC more closely or keeps a non-lab file consistent with it.

Public API of the lab package (files owned by "lab"):
- Client `UI/Apps/LabApp`: `openRelease(modelId)` (plays the reveal first if the model finished in this session and was
  not revealed yet), `openReveal(modelId)`, `wasRevealed(modelId)`, `openStudio(mode, opts)`,
  `openSection("design" | "train" | "evaluation" | "release")`, `plannedLine` (modelId -> target planned in the Studio).
- Client `UI/Lab/LabPreview` (pure maths of the Studio): `estimate`, `deltas`, `range`, `dataPlan`, `bestFocus`,
  `bestAffordable`, `successor`, `rank`, `stars`, `lineStatus`, `refineCheck`, `eventOdds`, `breakdown`.
- Shared `ModelMath.nextVersion(data, name)` (the "Nova v2" rule; AIModelService uses it) and
  `ModelMath.parseLook(look)` ("<colorId>:<emblemIndex>", cosmetic).
- Server `StartTraining` accepts two OPTIONAL fields (absent = old behaviour; invalid = `BAD_INPUT` before any other
  check): `look` (`ModelMath.parseLook`) and `target` (`MarketConfig.isTarget`, the planned line). Stored as
  `model.look`, `model.plan`, and every new model also stores `model.recipeId`.
- `TRAINING_COMPLETE` Notify payload (LAB_SPEC S1, display only): `expected`, `refinement`, `before`, `eventId`, `outcome`
  next to `modelId`, `overall`, `previousBest`.

## 1. apps (HUD) - no score in the TRAINING_COMPLETE toast (LAB_SPEC 4.14)
In `Screens/HUD.module.luau`, `StateController.onNotify` handler, branch `kind == "TRAINING_COMPLETE"`:
```lua
Toast.show("success", "Training complete! Open your computer for the reveal.", 5)
```
(today: "Training complete! Overall 61.5. Open your computer to see it." - it spoils the reveal's surprise).
The next-step card needs no change: its `LabApp.openRelease(releaseId)` call now plays the reveal first when the model
was not revealed yet. Optional polish: while `not LabApp.wasRevealed(id)`, card body "<name> vN is ready · tap to reveal
its score".
Fallback today: the toast shows the score; the reveal itself still plays.

## 2. econ / lead (JourneyMath) - DESIGN and TRAIN chips open the Studio directly (LAB_SPEC 2.1)
`Shared/JourneyMath.module.luau`, `Journey.STEPS`: add `section = "design"` to the `design` step and `section = "train"` to
the `train` step (pure table fields; `Computer.open(def.app, def.section)` already passes them, `LabApp.openSection`
handles both). Then the HUD goal "Train your first AI" (when its journey step is DESIGN) and the Journey chips skip the
Lab home: 2 taps (DESIGN · START) instead of 3 for a save with data.
Fallback today: they open the Lab home; its big DESIGN NEW MODEL tile is one more tap.

## 3. econ (Template) - clean the optional model fields on load (LAB_SPEC 7, phase 2)
In `ServerScriptService/Server/Lib/Template.module.luau`, the `for _, m in raw.models` cleaner (~l.392):
```lua
local ModelMath = require(ReplicatedStorage.Shared.ModelMath) -- (already reachable from Template's requires)
if m.look ~= nil and ModelMath.parseLook(m.look) == nil then m.look = nil end
if m.plan ~= nil and not (typeof(m.plan) == "string" and MarketConfig.isTarget(m.plan)) then m.plan = nil end
if m.recipeId ~= nil and not (typeof(m.recipeId) == "string" and ModelConfig.getRecipe(m.recipeId)) then m.recipeId = nil end
```
Checked: today's cleaner edits model tables in place and keeps unknown fields, so the new fields survive a save/load
round trip and old models (without them) load exactly as before. Every reader validates the fields (look via
`ModelMath.parseLook`, plan via `ModelConfig.getLine` + `releaseCheck`, recipe via `ModelConfig.getRecipe`), so a
hand-edited save cannot break anything; the cleaner is hygiene. No DATA_VERSION bump.

## 4. econ / lead (Types) - optional typing only
`Types.ModelData`: `look: string?`, `plan: string?`, `recipeId: string?`. The lab code uses `(model :: any)` meanwhile.

## 5. apps (Toast) - hold info toasts during the ceremonies (LAB_SPEC 3.6)
New `Toast.hold(on: boolean)`: while on, `info`/`success` toasts are queued (dedupe by text, max 3), `error`/`warn` still
show; `hold(false)` flushes the queue one by one. The Studio would call it on entering/leaving REVEAL, LAUNCH and LIVE.
Fallback today: toasts can appear during a ceremony; the Studio keeps the top-centre toast lane free.

## 6. apps (Computer) - compact chrome on phones (LAB_SPEC 4.1 note)
The Computer header (16/13 px), sidebar (16/12 px, 58 px buttons) and journey strip (12 px text, 28 px chips) are 5-7 pt
and 12-25 pt tall at the phone's 0.432 root scale. The Lab home uses compact tokens (text >= 28 px = 12.1 pt, buttons
>= 104 px = 45 pt, checked by tests/lab/test_studio) and the Studio its own UIScale (>= 11.96 pt / 44.3 pt), but the path
through the chrome stays small. Suggested: the same compact token table for the chrome when `designScale < 0.62`.
Optional: `Computer.setShade(transparency)` so the Studio can darken the inset strips while open.

## 7. lead (tests/lead/run_all.sh) - add the lab suites
```
run lab               bash tests/lab/run.sh
```
`tests/lab/run.sh` builds harness/.gen_lab and runs test_labpreview, test_studio and tests/models/test_ui x3 (must stay
unchanged and green). Mutation proof: `tests/lab/negative.sh`. Previews: `tests/lab/render.sh` -> out/lab/*.png.

## 8. corefix / lead (agents/corefix/sim.luau) - the `--ui-defaults` economy runs of LAB_SPEC 8.1
Implemented in the lab copy `agents/lab/sim.luau` (see agents/lab/BALANCE.md). If the lead wants it in the shared
simulator, the diff is the `uiDefaults` branch of `tryTrain` (training choice = LabPreview.bestAffordable on the bot's
`fits()` sizes, data purchases = LabPreview.dataPlan, launch line = the planned line).
