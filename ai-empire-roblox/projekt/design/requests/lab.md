# Requests from package "lab" (Model Studio: the new AI creation screen, LAB_SPEC)

The Studio works without every item below (local fallbacks are in place and named per item). Each item makes it match
LAB_SPEC more closely or keeps a non-lab file consistent with it.

Status check 2026-10-11 (fix round 1, re-read in work/src): items 1-8 are all still OPEN. HUD.module.luau:722 still
toasts "Training complete! Overall …" (both reviewers: spoils the reveal; #1 is now the most important item),
JourneyMath has no `section` on design/train, Template has no cleaner lines for look/plan/recipeId (not needed for
correctness: it keeps unknown fields, proven by tests/lab/test_labpreview.luau "save round trip"), Toast has no
`hold`, run_all.sh has no lab line. New in fix round 1: #9 (one logo glyph).

Public API of the lab package (files owned by "lab"):
- Client `UI/Apps/LabApp`: `openRelease(modelId)` (plays the reveal first if the model finished in this session and was
  not revealed yet), `openReveal(modelId)`, `wasRevealed(modelId)`, `openStudio(mode, opts)`,
  `openSection("design" | "train" | "evaluation" | "release")`, `plannedLine` (modelId -> target planned in the Studio).
- Client `UI/Lab/LabPreview` (pure maths of the Studio): `estimate`, `deltas`, `range`, `dataPlan`, `bestFocus`,
  `bestAffordable`, `suggest` (the Lab home's SUGGESTED model = the economy bot's line rule), `lineSuccessor`,
  `successorPick`, `prefillOf`, `rank`, `stars`, `lineStatus`, `refineCheck`, `eventOdds`, `breakdown`, `ceiling`,
  `deepShort`, `specBonusText`.
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
Fallback today: the toast shows the score; the reveal itself still plays (fix round 1: it is no longer skipped on the
HUD card / Journey LAUNCH path). Both fix-round-1 reviewers rate this toast BLOCKING for the surprise score (the
Training stage's own button says "CLOSE · it keeps training", so the closed-Computer path is the normal one).
Guard: tests/lab/test_studio.luau section 14 B captures the toast; it prints `NOTE OPEN request lab #1` while the
toast has digits and becomes a hard check (no digits) once this lands.

## 2. econ / lead (JourneyMath) - DESIGN and TRAIN chips open the Studio directly (LAB_SPEC 2.1)
`Shared/JourneyMath.module.luau`, `Journey.STEPS`: add `section = "design"` to the `design` step and `section = "train"` to
the `train` step (pure table fields; `Computer.open(def.app, def.section)` already passes them, `LabApp.openSection`
handles both). Then the HUD goal "Train your first AI" (when its journey step is DESIGN) and the Journey chips skip the
Lab home: 2 taps (DESIGN · START) instead of 3 for a save with data.
Fallback today: they open the Lab home; its big DESIGN NEW MODEL tile is one more tap.
Fix round 1 (UX review, high priority for phones): on a FRESH save the HUD goal "Train your first AI" follows the
journey's data step and opens Datasets ("scrape the web for free or buy a pack"), so a new iPhone player buys data by
hand through the 5-7 pt Computer chrome instead of the Studio's verified BUY DATA PLAN ($7,400, 2 taps). In
`Screens/HUD.module.luau` (`id == "train"` branch): when `not training`, set `view.app = "lab"` and
`view.section = "design"` also on the data step (the Studio opens at the Review with BUY DATA PLAN · START), and
replace the stale `JOURNEY_HINT.design` text "Design your model in Models: pick a name, size and focus." with
"Open the Model Studio: everything is prefilled, just press START."

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
Fallback today: toasts can appear during a ceremony. Fix round 1: the ceremony captions ("INTRODUCING / <name>",
"NOW LIVE / <line>") moved from the top centre to the left title slot (x 172, TextScaled 24-44 px), so a toast no
longer covers the model's name; the card itself can still sit under a toast for its 5 s.

## 6. apps (Computer) - compact chrome on phones (LAB_SPEC 4.1 note)
The Computer header (16/13 px), sidebar (16/12 px, 58 px buttons) and journey strip (12 px text, 28 px chips) are 5-7 pt
and 12-25 pt tall at the phone's 0.432 root scale. The Lab home uses compact tokens (text >= 28 px = 12.1 pt, buttons
>= 104 px = 45 pt, checked by tests/lab/test_studio) and the Studio its own UIScale (>= 11.96 pt / 44.3 pt), but the path
through the chrome stays small. Suggested: the same compact token table for the chrome when `designScale < 0.62`.
Optional: `Computer.setShade(transparency)` so the Studio can darken the inset strips while open.
Documented limit (fix round 1, no request): on a 667x375 phone (iPhone SE/8 landscape) the Studio's 1254-px design
canvas is width-bound, scale 0.532: 20 px text = 10.6 pt, 74 px taps = 39 pt (out/lab/se_*.png). A narrower canvas
would squeeze the Expected panel below its bars' width; the 844x390 class (iPhone 12-15) keeps 11.96 pt / 44.3 pt.

## 7. lead (tests/lead/run_all.sh) - add the lab suites
```
run lab               bash tests/lab/run.sh
```
`tests/lab/run.sh` builds harness/.gen_lab and runs test_labpreview, test_studio and tests/models/test_ui x3 (must stay
unchanged and green). Mutation proof: `tests/lab/negative.sh`. Previews: `tests/lab/render.sh` -> out/lab/*.png.

## 8. corefix / lead (agents/corefix/sim.luau) - the `--ui-defaults` economy runs of LAB_SPEC 8.1
Implemented in the lab copy `agents/lab/sim.luau` (see agents/lab/BALANCE.md). If the lead wants it in the shared
simulator, the diff is the `uiDefaults` branch of `tryTrain`. Corrected in fix round 1 (the earlier text named
`bestAffordable`, which is only the failed variant A `--ui-best`): first model = the Studio's first-model plan
(100M Standard, best focus for Consumer Chat, data = LabPreview.dataPlan); every later model = exactly what the Lab
home's SUGGESTED tile opens (`LabPreview.suggest`: line, focus, size, plan) and only the data plan its Review offers
(`suggest(...).pick.plan`, bought before START); no suggestion (nothing beats the line by +3) = no training. Launch
line = the suggestion's line. Limits: humans act slower than once per second, and DESIGN NEW MODEL for a returning
player (it prefills the last selection, not a suggestion) is not simulated.

## 9. econ / apps (CompanyConfig) - one company logo glyph is missing from common fonts
`Shared/Config/CompanyConfig.module.luau`: `LOGOS[6] = "⦿"` (U+29BF) renders as a missing-glyph box in the previews
(Liberation Sans and the DejaVu fallback both lack it); "◉" (U+25C9) exists in DejaVu. Please check it in Studio and,
if it shows a box there too, replace it with "◉" (saves store the glyph as `company.logo`, so a migration line
`if company.logo == "⦿" then company.logo = "◉" end` keeps old companies valid). Fallback today: the Studio draws
"◉" for it (`StudioParts.glyph`, display only; the saved look keeps its index).
