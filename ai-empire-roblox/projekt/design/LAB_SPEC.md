# AI Empire: LAB_SPEC (binding spec for the new "Model Studio" creation screen)

Date: 2026-10-10. Status: BINDING for the builder. Supersedes the "creator" view of
`StarterPlayer/StarterPlayerScripts/Client/UI/Apps/LabApp.module.luau` (all paths below are relative to `work/src`
unless they start with `tests/`, `tools/`, `agents/`, `design/` or `out/`).

Inputs: the winning design `phone_maker` (judge scores 9/8/8/8/5), the judge's 8 grafts from `safe_wizard`, the judge's
9 must-fixes, CORE_SPEC section 7, LOGIC_BRIEF section 3, and the code as it is on 2026-10-10.

Click-through mockup: `out/lab_design/mockup.html` (self-contained). PNGs: `out/lab_design/phone_*.png` (844x390 @2x),
`out/lab_design/desktop_*.png` (1280x720). The mockup is a design draft, not the game; where the mockup and this text
disagree, this text wins.

Revision: critic pass of 2026-10-10 (section 0.6 lists every change and why). Sections marked "(critic)" were changed.

---

## 0. Decisions, sources and honesty notes

### 0.1 What the user asked
"Make the screen where you create the AI much better. Look at Roblox games where you create phones and do it in
that kind of way." The answer is a full-screen **Model Studio** modelled on the Design Studio of *Build a Phone Empire*.

### 0.2 Research basis (what is verified)
- *Build a Phone Empire* by DEVTEC STUDIOS: https://www.roblox.com/games/101914705206759/Build-a-Phone-Empire.
  Its layout was verified by the `roblox_phone` researcher (agents/lab_research/roblox_phone.md) from video frames
  and fan-hub frames. I opened these local frames myself with the image reader:
  `agents/lab_research/thumbs/on_design-studio-step-4-*.png` (option rows with price + difference + "Arrives 2009"),
  `.../on_design-studio-step-13-final-review-*.png` (money tiles, big primary button),
  `agents/lab_research/vid/Jh-nnWCn9f4_maxresdefault_big.png` (mobile layout, step pills at the bottom, Back/Continue,
  the Roblox top bar covering the title), `agents/lab_research/vid/oCb2DRp69Mw_hq1_big.png` (spotlit reveal, confetti,
  "8.7/10 EXCELLENT"), `.../on_launch-day-panel-*.png` (3-part launch panel, toasts covering the campaign cards).
- (critic) The game itself re-checked on 2026-10-10 through the official API
  https://games.roblox.com/v1/games?universeIds=10767582899 (opened): name "📱 Build a Phone Empire", creator DEVTEC
  STUDIOS (group), rootPlaceId 101914705206759, created 2026-09-22, about 1.82M visits. A web search for other Roblox
  phone games with a design screen found none (the hits were Steam/mobile games and "Prove Dad Wrong by Making Phones",
  whose page lists no design screen); that "only one" result stays **unverified** beyond these searches.
- Everything in this spec about *our* game was checked in `work/src` on 2026-10-10. Example numbers were computed by
  running the REAL shared Luau code in the mock (agents/lab_spec/probe_lab.luau, probe_flow.luau) on the test states
  of `tests/models/ui_setup.luau`; the mockup's JS copy of the formulas (agents/lab_spec/mathport.js) reproduces those
  numbers in 50 of 50 compared cases (agents/lab_spec/check_mathport.js). (critic) The Launch Day and reveal numbers of
  "Sage v2" come from `probe_flow.luau` with **seed 11** (`../../tools/luau probe_flow.luau -a <gen> 11`); the script's
  default seed 7 gives overall 75.7 instead of 75.2.
- (critic) The first-model example no longer rests on an assumption. It is the casual bot's verified start
  (`agents/corefix/out/out_casual_s11.txt`: "quest founder +1200" at 0.0 min, then "train Nova1 s100m steady … exp 40.2
  … data 4B q0.42", released as "s100m creative"): a fresh save (Template `data = {}`) with $12,200, then the bot's data
  plan (2× Web Crawl Chunk + 2× Public Repos = $7,400 → 4B tokens at 42.5 %). `agents/lab_crit/probe_first.luau`
  reproduces it with the real code (exp 40.2), and the mockup's JS states `fresh` and `starter` match it in 120 of 120
  cases (`agents/lab_crit/check_starter.js`: overall, cost, time, four fits and the lock for 5 sizes × 3 plans × 4 focuses).
- ASSUMPTION: phone sizes in points (844x390, safe area 750x311 with insets 58/47/21/47) come from the project's guiprev
  preset (`tools/guiprev/guiprev.py` PRESETS), not from a device measurement.

### 0.3 The three lead decisions (made here, binding)
1. **Expected value before training:** show `~74.5` (one decimal, with "~") plus `final 72.0–77.0 without events`. The
   range is `overall ± ModelConfig.TRAINING.noise` (2.5), capped to [1, 99]. Option deltas stay exact expected
   differences. Reason: the server adds uniform ±2.5 noise per stat in `AIModelService.finish`, so an exact promise would
   be wrong. (critic) "without events" is required: training events multiply `qualityMod` (Ignore ×0.94, Push through
   50 % ×0.9, Breakthrough ×1.05; ModelConfig.EVENTS), so the result can leave the ±2.5 band.
2. **Where the reveal happens:** in the Studio REVEAL stage. It plays automatically when `TRAINING_COMPLETE` arrives
   while the Computer is open; otherwise the HUD next-step card offers it (section 4.14).
3. **Stars:** relative to the live market (rank in the planned line), not fixed bands. The big number stays the
   absolute Overall. An info line always says "stars = market rank".

### 0.4 Must-fixes of the judge and where they are solved
| # | Must-fix | Solved in |
|---|---|---|
| 1 | Studio lifecycle (Computer.close must hide it) | 3.1: the Studio is a child of the Computer root frame, not its own ScreenGui |
| 2 | First-model speed | 2 (flow step 2), 4.9: first model opens at the Review; (critic) 4 taps from Lab home to a live model when the save already has data, 5 on a fresh save (one extra tap buys the data plan) |
| 3 | BEST I CAN AFFORD must keep a reserve | 5.2 `LabPreview.bestAffordable` (reserve + Save-mode cap) |
| 4 | Campaign cards and forecasts | 4.12 step 3: Recommended preselected, one forecast for the selected card only |
| 5 | Lock reasons must fit the 122 px tiles | 4.4: two short lines ("Needs" / "64 GB"); verified in phone_15 (critic: now the starter save, 7B reads "Needs / research" in the server's order) |
| 6 | Lab home unreadable on phones | 4.1: compact size tokens (critic: every text ≥ 28 px = 12.1 pt, buttons 104 px = 45 pt) |
| 7 | Record/delta after a refinement | 6.1 S1 payload field `before` + client rule in 4.11 |
| 8 | Re-check line references | references re-checked on 2026-10-10; HUD.module.luau is being edited by another agent, so HUD uses search anchors |
| 9 | Gamepad pass | 3.5; reported "not run" until tested in Studio with a controller |

### 0.5 Grafts taken from safe_wizard
All 8: pure `Shared/LabPreview` module + honesty test; line tiles are TextButtons whose Text starts with the short line
name (keeps `tests/models/test_ui.luau` unchanged); `TRAINING_COMPLETE` payload extension (S1); compact Lab home;
"Starting…" ignition state tied to the existing office `Training` attribute; "BEATS YOUR BEST" chip + best-value tick
on stat bars; the Deep tile states the real overfit rule; the REFINE pre-check also covers TRAINING_ACTIVE and the
EVALUATE caption becomes "BENCHMARK REPORT".

### 0.6 Critic pass (2026-10-10): problems found and what changed
Measured with `agents/lab_crit/audit.js` (text size and tap size in screen points on 844x390, Computer chrome excluded)
and the real-code probes in `agents/lab_crit/`.
| # | Problem | Change (section) |
|---|---|---|
| C1 | Tap targets below 44 pt: step chips 56 px wide (33 pt), preset chips 56 px tall, Launch Day price chips 60 px and stepper 66x60, "+ DATA" 70 px, "+ Show breakdown" a text link, Lab home SUCCESSOR buttons 80 px (35 pt at 0.432). Goal 1 even said "56 design px (33 pt)". | Everything tappable ≥ 74 Studio px (44.3 pt) in both directions; Lab home buttons 104 px (45 pt). Audit: smallest tap 44.3 pt (1, 3.3, 3.4, 4.1, 4.4, 4.6, 4.8, 4.12) |
| C2 | Text below 12 pt: 18 px "exceptions" (10.8 pt), a 16 px FREE tag (9.6 pt), 17 px check glyph, Lab home captions 24 px (10.4 pt) and body 26 px (11.2 pt). | Studio minimum 20 px (11.96 pt), no exceptions; Lab home minimum 28 px (12.1 pt). Audit: smallest text 11.96 pt (3.4, 4.1) |
| C3 | A fresh save has **no data** (Template `data = {}`), so "DESIGN → START" fails with NO_DATA; the "4 taps" claim and the garage example (1B tokens, an assumption) did not hold. | Review shows `LabPreview.dataPlan` (= the casual bot's verified data rule) and the primary button becomes `BUY DATA PLAN · $7,400` (existing `BuyData` remote, no server change). First model: 3 taps to start, 5 to live (2, 4.6, 4.8, 4.9, 5.2, 6.2) |
| C4 | First-model default focus Balanced differs from the path CORE_SPEC's numbers were measured on (the bot trains Consumer Chat with Creative) and fits the line worse (49.5 vs 46.2 fit). | Default focus = `LabPreview.bestFocus` (highest fit in the planned line); "BEST FIT" tag on that tile (4.5, 4.9) |
| C5 | Returning players: 7 taps from Lab home to START through all steps; "chip 6" was an unlabeled 56-px number. | Chip 6 always reads "6 Review" (110x74): DESIGN → 6 Review → START = 3 taps; SUCCESSOR → START = 2 (2, 3.3) |
| C6 | Lock order differed from the server (VRAM before the 7B research check; no MODEL_LIMIT), so a garage 7B tile showed "Needs 128 GB" while START would answer PREREQUISITE. | `estimate.lock` and the START button use the order of `AIModelService.startTraining` (4.4, 4.8, 5.2) |
| C7 | Joystick / jump buttons: nothing in the spec. The Computer's full-screen `Kit.blocker` (Dim layer, DisplayOrder 19, Modal) swallows touches, but whether the engine's TouchGui draws above it is not in this repo (unverified). | While the Studio is open on a touch device it sets `GuiService.TouchControlsEnabled = false` and restores the saved value on close (3.1) |
| C8 | Untraceable numbers: training loss "2.418" (the real `ModelMath.lossAt` gives 1.876 at 45 %), NOW LIVE "+2,580 since launch" (invented, "Example values"), probe seed not named. | Loss and epoch lines from `lossAt` (jitter 0); NOW LIVE shows the migrated 19,260 users at launch and the real 5-minute forecast; seed 11 named (0.2, 4.10, 4.13) |
| C9 | The range "final 72.0–77.0" and the "lucky roll" ignore training events that change quality. | "without events"; lucky roll only when no quality event, otherwise "vs expected" + the event name (0.3, 4.8, 4.11) |
| C10 | Economy: "simulator diff identical" only proves the server did not change. The UI's defaults (presets, data plan, first-model plan) were never compared with the bot path behind CORE_SPEC's targets. | Concrete re-verification with a `--ui-defaults` bot and pass thresholds from CORE_SPEC 9.4 (8.1) |
| C11 | Phone-maker feel: step 4 (Training plan) did not change the Model Card; the first model's 1-star "BEHIND" reveal gives no goal. | Card plan meter (1/2/3 bars, warn when Deep overfits); stars word "CHALLENGER" + "Next to beat: <rival> <fit>" (4.2, 4.11, 5.3) |
| C12 | The server-load warning of today's release card ("After launch: Servers 97 % full") was not placed in Launch Day. | Summary column shows it (4.12) |
| C13 | The DESIGN DRAFT label of the mockup covered the primary button. | Moved into the top inset strip (mockup only) |

Not changed (reviewed and kept): the 6-step order, the Model Card concept, the cost badge, option tiles with cost and
delta, the reveal / Launch Day / NOW LIVE ceremony, lifecycle under the Computer frame, own UIScale, S1 payload, phase 2.
Compared with today's creator (`out/models/lab_rich_strip_creator.png`: one 858x841 scroll form with three segmented
bars, no preview, no per-option price or delta, locked sizes only dimmed) the Studio is clearly closer to the phone-maker
pattern seen in the reference frames (step pills, cost badge, option rows with price + difference + lock reason, live
product preview, spotlit reveal).

---

## 1. Goals and non-goals

Goals:
- One decision per screen, a live product (the **Model Card**) that changes on every tap, prices and score differences on
  every option, locked options visible with the exact reason, a ceremony at the end (reveal, launch day, now live).
- (critic) Readable on an iPhone in landscape: every tap target in the Studio is at least 74 x 74 design px (44.3 pt at
  0.598 pt/px); every text at least 20 px (11.96 pt), body text 22 px (13.2 pt); no scrolling inside the Studio. Lab home
  (inside the Computer, 0.432 pt/px): text ≥ 28 px (12.1 pt), buttons ≥ 104 px (45 pt).
- (critic) Tap budget (from the Lab home): recommended path to START ≤ 3 taps, first model to a live product ≤ 5.
- Every number comes from the server's own pure functions on real state.

Non-goals (NOT in this package; each needs a CORE_SPEC amendment and simulator runs): new stats, costs, times or quality
rules; new or retuned sizes, focuses or recipes; per-model data mix; parallel training slots (CORE_SPEC 7.6 v2); a
personality step for the model chat (CORE_SPEC 11.6); 3D ViewportFrame cores (optional later polish only).

---

## 2. Flow (binding)

1. **Entry.** Computer → Models opens the **Lab home** (4.1). The Journey chip DESIGN and the HUD goal "Train your first
   AI" open `Computer.open("lab", "design")` → `LabApp.openSection("design")` → the Studio in DESIGN mode.
2. **DESIGN NEW MODEL.**
   - First model (`data.stats.modelsTrained == 0` and no model in `data.models` except `training`): the Studio opens at
     **step 6 Review** with defaults 100M · `LabPreview.bestFocus(...)` for Consumer Chat (Creative in every garage
     state checked) · Standard · Consumer Chat · a random NAME_IDEAS name (4.9). (critic) If the save has no usable data
     (`estimate.lock == "NO_DATA"`, always true on a fresh save because Template starts with `data = {}`), the primary
     button is `BUY DATA PLAN · $X` (`LabPreview.dataPlan`, 5.2); after the purchase it turns into START.
   - (critic) Tap counts from the open Lab home (each counted tap is a ≥ 44 pt target):
     | Path | Taps | Today |
     |---|---|---|
     | first model, fresh save → training starts | DESIGN · BUY DATA PLAN · START = **3** | impossible without visiting Datasets first |
     | first model, save with data → training starts | DESIGN · START = **2** | START = 1 (form already open) |
     | first model → live product | + LAUNCH › (reveal) · LAUNCH (Launch Day) = **5** fresh / **4** with data | 3 |
     | returning player, recommended path (prefilled plan) → START | DESIGN · 6 Review · START = **3** | START = 1 |
     | returning player, every step looked at | DESIGN · 5 × CONTINUE · START = 7 | – |
     | successor of the oldest line → START | SUCCESSOR · START = **2** | – |
     From the world add the HUD tap that opens the Computer and, if Models is not the last app, the sidebar tap. The HUD
     goal card "Train your first AI" skips both (`Computer.open("lab", "design")`). The extra taps versus today buy the
     step-by-step design the user asked for; the "6 Review" chip keeps the quick path at 3.
   - Otherwise the Studio opens at step 1, prefilled from `StateController.ui` (sizeId, focusId, recipeId, new lineId,
     name). The step chips jump to any step; chip 6 always shows its label "6 Review" (3.3).
3. **Steps.** 1 Product · 2 Brain size · 3 Skill focus · 4 Training plan · 5 Name & look · 6 Review. Every tap updates the
   cost badge, the Model Card and the Expected panel at once and writes the selection into `StateController.ui` right
   away (DataApp and JourneyMath read it).
4. **START TRAINING** on the Review sends `ActionController.call("StartTraining", {name, sizeId, focusId, recipeId})`
   (today's payload). While the call runs (ActionController's `busy[name]` guard, the server filters the name and
   yields) the button reads `STARTING…` and is disabled.
   - ok (`{ok = true, modelId}`): store `LabApp.plannedLine[modelId] = ui.lineId`; the Studio switches to TRAINING mode
     in the **starting** state ("Allocating GPUs…") until a snapshot carries `data.training` with that modelId.
   - error: ActionController already shows the toast; then jump to the fix:
     `BAD_NAME`, `NAME_FILTERED`, `FILTER_DOWN` → step 5 with the name box outlined in `C.bad`;
     `VRAM`, `NO_GPU` → close the Studio, `nav.show("compute")`; `NO_DATA` → stay on step 6 when `dataPlan` has packs
     (BUY DATA PLAN), else `nav.show("data")`;
     `PREREQUISITE` → `nav.show("empire")`; `NO_MONEY` → stay on step 6; `TRAINING_ACTIVE` → TRAINING mode;
     `MODEL_LIMIT` → stay, toast text from ActionController; `BAD_INPUT`, `LOADING`, `NETWORK`, `BUSY` → stay.
5. **Training** (12–140 s in the test states): the TRAINING stage (4.10). A decision event (rolled once at 35 % progress,
   60 % chance; 6 of the 12 event weight points are decisions) shows the event card with its 2 choices and the real
   25 s countdown. Closing never stops training (it runs on the server).
6. **TRAINING_COMPLETE.** Computer open → the REVEAL stage plays (4.11). Computer closed → the HUD toast says "Training
   complete! Open your computer for the reveal." (no score in the toast) and the HUD next-step card offers the reveal.
7. **From the reveal:** LAUNCH → Launch Day; REFINE n/3 · $X → `ImproveModel` (pre-checked, 5.2 `refineCheck`) and back
   to TRAINING; LATER → Lab home (the model waits on the Ready shelf).
8. **Launch Day** (4.12; also opened by `LabApp.openRelease(modelId)` from the HUD, the Journey chip LAUNCH and tests):
   steps 1 Line · 2 Price · 3 Campaign, the LAUNCH button is always visible, so one tap launches with the preselected
   line, the Auto/Recommended price and the Recommended campaign. Payload unchanged:
   `ReleaseModel {modelId, target, marketing, auto, subPrice/apiPrice only when auto == false}`.
9. **Release ok** → the NOW LIVE stage (4.13) replaces `playLaunch`'s "3-2-1 MODEL LIVE". Buttons BACK TO LAB and
   OPEN MARKET (`nav.show("market")`). No automatic jump.
10. **Later:** the Lab home shows each live line with its age penalty and a SUCCESSOR button; the SUCCESSOR hero tile opens
    the Review prefilled for the oldest line (5.2 `successor`). The Hall of fame shows the model cards of all versions.

Closing rules: `‹ LAB` returns to the Lab home and keeps every choice in `StateController.ui`. The `×` button and every
`Computer.close()` close the Studio too (3.1). Leaving the Lab app (any `Computer.show(otherApp)`) closes the Studio.

---

## 3. Studio shell (all modes)

### 3.1 Host and lifecycle (must-fix 1)
- New module `StarterPlayer/StarterPlayerScripts/Client/UI/Studio/Studio.module.luau`.
- Host = `container:FindFirstAncestor("Computer")`, where `container` is the Frame `LabApp.mount` receives. That ancestor
  is the Computer root frame (`Computer.mount`, `frame.Name = "Computer"`, ZIndex 10, size 1,1 of the Overlay root).
  LabApp cannot require Computer (Computer requires LabApp), so it finds the frame by name. Fallback when it is missing
  (isolated tests): host = `container`.
- The Studio root is `Frame "ModelStudio"`, child of the host, `ZIndex = 30` (the Computer window is 11; the layer uses
  `ZIndexBehavior.Sibling`), opaque background `C.bg`, built lazily on the first open.
- Visibility = Studio open AND host visible. `Computer.close()` hides the host after 0.18 s, so the Studio disappears with
  it. The Studio also listens to `host:GetPropertyChangedSignal("Visible")` and to the Lab container's `Visible`
  (`Computer.show` hides app containers) and then **closes** itself: mode = closed, input actions unbound (3.5).
- Layer order is the Computer's: Overlay DisplayOrder 20, above HUD 10 and Dim 19, below Intro 25 / ShuttlePass 25 /
  Phone 28 / Top 30 (toasts). Nothing new to manage.
- Optional polish (allowed): new `Computer.setShade(transparency: number)` so the Studio can darken the inset strips to
  0.1 while open and restore 0.32 on close.
- (critic) **Joystick and jump button.** While the Computer is open, `Kit.blocker` (a full-screen TextButton with
  `Modal = true` in the Dim layer, DisplayOrder 19, `ScreenInsets.None`; Computer.mount) covers the screen and swallows
  touches, and the opaque Studio covers the safe area. Whether the engine's TouchGui (PlayerModule, not in this repo)
  draws below DisplayOrder 19 is **unverified**. To be independent of it: when the Studio opens and
  `UserInputService.TouchEnabled`, store `GuiService.TouchControlsEnabled` and set it to `false`; on every close path
  (mode = closed, host hidden, `Computer.close()`) restore the stored value. Both members are in `tools/API-Dump.json`
  (GuiService.TouchControlsEnabled is script-writable). Nothing else in `work/src` writes that property (grep, 2026-10-10).
  `Phone.module.luau`'s jump-button lookup then returns nil and uses its own fallback, which is fine because the Phone
  layer (28) is above the Studio anyway.

### 3.2 Scale (own UIScale inside the Computer)
- `A = host.AbsoluteSize` (screen units of the safe area; the Overlay layer uses CoreUISafeInsets).
- `P` = product of every ancestor UIScale of the host up to the ScreenGui (the UIRoot root scale; same walk as
  `designScale` in `Computer.module.luau`).
- Target `s = math.clamp(math.min(A.X / 1254, A.Y / 520), 0.5, 1.25)`; Studio UIScale `k = s / P`;
  Studio `Size = UDim2.fromScale(1 / k, 1 / k)`, Position 0,0. The canvas in Studio units is then `A / s`.
- Recompute on `host:GetPropertyChangedSignal("AbsoluteSize")` (deferred one frame so UIRoot has applied its scale).
- Results: iPhone 844x390 (A 750x311) → s 0.598, canvas **1254 x 520**, 1 design px = 0.598 pt. Desktop 1280x720
  (A 1280x662) → s 1.021, canvas **1254 x 648**. 1920x1080 → s 1.25 (clamped), canvas 1536 x 818. iPad-like 1024x710
  → s 0.817, canvas 1254 x 869.
- Layout class: **compact** when the main area (canvas height − 184) is below 440 px (phones), otherwise **regular**.
  Extra width goes to the preview zone (right panel stays 686 px), extra height to the main area.

### 3.3 Grid (design px; compact = phone 1254x520, regular = desktop 1254x648)
| Region | compact | regular |
|---|---|---|
| margins | 16 left/right, 8 top/bottom | same |
| top bar | x 16, y 8, 1222 x 74 | same |
| main area | y 94, height 336 | y 94, height 464 (canvas − 184) |
| preview zone | x 16, width 520 (canvas width − 734) | same rule |
| right panel | x 552 (canvas width − 702), 686 x main | same |
| bottom bar | y 438, 1222 x 74 | y 566 |

Top bar, left to right: `‹ LAB` ghost button 140x74 (24 px bold) · title block 300 wide (title 32 px display:
"Model Studio" / "Training" / "Launch Day"; subtitle 20 px muted "<company> · time keeps running") · **empty toast lane**
(x ≈ 468–786 on the phone: the Toast holder is 440 px of the Top layer = ~190 pt centred, so nothing important goes
there) · cash block (caption "CASH" 20 px + value 30 px; after START it shows cash minus the paid training cost from the
snapshot) · `×` ghost 74x74 (closes the Computer). REVEAL and NOW LIVE show only `‹ LAB` and the cash.

Bottom bar (critic): step chips in the preview-zone width: chips 1–5 are 74x74 (number 26 px, "✓" when done, the
current one accent-filled with the number in accent; its name is the panel title), chip 6 is 110x74 and always reads
"6 Review", gap 8 (5 × 74 + 110 + 5 × 8 = 520). Launch Day: current 236, others 130 with "✓ Line". Then `‹ BACK` 180x74
(step 1: CLOSE) and the primary button 494x74 (26 px bold; long Launch Day labels 22 px).

### 3.4 Tokens
- Colours: only `Theme.colors` (bg, panel, panel2, raised, text, muted, dim, good, bad, warn) and `Theme.accent`
  (company colour, via `Theme.bindAccent`). Card colour per focus (`FOCUS_COLOR`): Balanced = `Theme.accent`;
  Coding = CompanyConfig.COLORS "blue" (134,171,198); Reasoning = "violet" (176,162,208); Creative = "amber"
  (224,189,122). Read them with `CompanyConfig.getColor(id)` + `Theme.rgb`.
- Fonts: `Theme.font` (BuilderSans family; RobotoMono only for the training log).
- Text sizes (design px): reveal overall 64; expected / training % 52–72; panel title 34; top title 32; option title
  24–26; body 22; caption / secondary 20 (uppercase captions with letter spacing). (critic) **20 px is the floor, no
  exceptions** (11.96 pt on the phone): tag chips (LIVE v2, FREE, NEW VERSION, BEST FIT), the card's line chip, emblem
  and "1B · Coding" sub-label, audience-chip second lines, the NEW RECORD pill, check badges (32 px circle, 20 px glyph)
  and two-line button captions ("needs 100M new tokens") are all 20 px.
- Tap targets (critic): **74 x 74 px minimum for everything tappable** (44.3 pt): bar buttons, choices, step chips
  (74x74, Review chip 110x74), preset chips (74 tall), name box, RANDOM NAME, data strip buttons (74 tall), Launch Day
  subscription chips (74x74) and API stepper buttons (74x74), the Review's lines block (one TextButton, ≥ 112 px tall).
  Tiles ≥ 98 px tall and ≥ 122 px wide.
- Money in the Studio: `"$" .. Format.int(n)` below $100,000 ("$7,040"), `Format.money(n)` from $100,000 ("$186.4K").
  Durations `Format.duration` ("0:12", "1:20"). Overall one decimal. Deltas `Format.signed(d)` coloured good/bad.

### 3.5 Input
- Touch / mouse: every tile is a `TextButton` (Kit.button style + child labels), clicks through `Kit.onClick` (ignores
  disabled buttons, `Kit.setDisabled`).
- Keyboard: Return / KeypadEnter = the primary bottom button, only when `UserInputService:GetFocusedTextBox()` is nil.
  In the name box `FocusLost(enterPressed)` confirms the name.
- Gamepad (mandatory pass): tiles, chips and bar buttons `Selectable = true`, labels and frames `Selectable = false`.
  On every step or mode change, if `UserInputService.GamepadEnabled`, set `GuiService.SelectedObject` to the selected
  tile (step 6: the primary button, START or BUY DATA PLAN; REVEAL: LAUNCH). On open bind
  `ContextActionService:BindActionAtPriority("AIEmpireStudio", handler, false, Enum.ContextActionPriority.High.Value,
  Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonB)`: L1/R1 = previous/next step, B = BACK (step 1:
  close the Studio); return `Enum.ContextActionResult.Sink` for handled `Begin` states. `UnbindAction("AIEmpireStudio")`
  on close and on hide. ButtonA is the engine's default activation of the selected button. (All names verified in
  `tools/API-Dump.json`.) Status of this pass: **not run** until tested in Roblox Studio with a controller.

### 3.6 Toasts during ceremonies
New `Toast.hold(on: boolean)` in `UI/Toast.module.luau`: while on, `info` and `success` toasts are queued (dedupe by text,
max 3) and `error`/`warn` still show at once; `hold(false)` flushes the queue one by one. REVEAL, LAUNCH and LIVE call
`hold(true)` on enter and `hold(false)` on leave/close.

---

## 4. Screens

Example values below come from the test state "rich" (Startup Campus, $186,400, 6 Workstation GPUs = 19.2 units/s and
288 GB, 16B tokens at 80.6 % quality, all research, Lab level 2) unless marked "garage".

### 4.1 Lab home (inside the Computer window; replaces the creator scroll)
PNG: `phone_01_lab_home.png`. It stays inside the Computer (content area 939x542 design px; on the phone the root scale is
0.432, so that is ~406x234 pt). One `Kit.scroll`, top to bottom.

Tokens: **compact** when the effective scale (`designScale(container)`) is below 0.62 (phones), else **regular**.
(critic) Compact floor 28 px = 12.1 pt; every compact button ≥ 104 x 104 px (45 pt).
| token | compact (pt at 0.432) | regular |
|---|---|---|
| caption | 28 px (12.1 pt) | 14 |
| body | 28–30 px (12.1–13 pt) | 15–16 |
| title | 44 px | 30 |
| row title | 32–36 px | 18–20 |
| tag | 28 px | 13 |
| button height | 104 px (45 pt) | 52 |

(critic) Out of scope but on the path: the Computer chrome around the Lab home (header 16/13 px, sidebar 16/12 px,
journey strip 12 px = 5–7 pt on the phone; sidebar buttons 58 px = 25 pt, journey chips 28 px = 12 pt tall) fails the
12 pt / 44 pt rule. That is a Computer.module change for its owner (request: compact chrome tokens like this table).
The phone-friendly entry is the HUD goal card, which opens the Studio directly.

Elements:
1. Heading "MODEL LAB" (Kit.heading) + one line "Design, train and launch your AI models."
2. Hero row (compact 236 px tall; regular 150):
   - **DESIGN NEW MODEL** (420 wide, accent fill, `Kit.icon(parent, "lab", 62)`, label 40 px, sub "6 steps · all
     prefilled" 28 px; first model: "Your first model · ready to start") → flow step 2.
   - **SUCCESSOR** (250 wide): caption "SUCCESSOR", "Coder v3", "Dev API · −6 fit", "1B Deep · ~88", "REVIEW ›"
     (5.2 `successor`; all 28 px, name 34 px); no live line → "No live line yet" and disabled.
   - **TRAINING SLOT** (241 wide, dashed): caption "TRAINING" (critic: "TRAINING SLOT" does not fit 201 px at 28 px),
     "Free" or a mini progress "45 % · ETA 0:07" (tap → TRAINING mode), and the test string
     **"1 training slot · one run at a time"** (critic: shortened to fit at 28 px; `test_ui.luau:148` looks only for
     "1 training slot").
3. **Ready to launch** card: one row per `status == "trained"` model, 120 px: name 36 px, "1B · Balanced · 61.6 ·
   refined 0/3" 28 px (`ModelsUI.refineText`), buttons `REFINE 1/3` + cost line (210x104, disabled with the `refineCheck`
   reason) and `LAUNCH` (210x104 primary → `LabApp.openRelease(id)`). Not-yet-revealed models (4.14) show `REVEAL`
   instead of LAUNCH. Empty text unchanged from today (LabApp:265).
4. **Product lines** card: today's code (LabApp:236-259 and :420-447) with the compact tokens, rows ≥ 120 px with the
   detail line wrapping to 2 lines at 28 px, plus a `SUCCESSOR` button (critic: 210x104, was 200x80 = 35 pt) on each LIVE
   row (prefills the Review for that line). Caption keeps "Product lines · 2 / 3 live at Startup Campus".
5. **Lab level** card: today's code (LabApp:303-317, :449-457, :511-519) unchanged, plus the line moved here from the
   estimate card: **"Every stat caps at 99. Lab level 2 adds +2 to each."** (exact LabApp:418 rule).
6. **Hall of fame**: horizontal strip of up to 8 mini cards (206 px wide; name vN 30 px, "Overall 61.5", tag LIVE · Chat /
   READY / RETIRED) from `data.modelOrder`, newest first.

Strings that `tests/models/test_ui.luau` reads right after `Computer.open("lab")` and that must stay visible here:
"MODEL LAB", "Product lines · …", "1 training slot", "Every stat caps at 99", "Lab level N", "Unlocks after the whole
research tree" (empty state, from `ModelsUI.lab`), "UPGRADE LAB · …", "Lab level 2 adds +2 to each", "REFINE 1/3",
"refined 0/3".

### 4.2 Studio DESIGN parts shared by steps 1–6
PNGs: `phone_02` … `phone_07`, `desktop_1_step2_size.png`.

Preview zone (compact 520x336):
- **Cost badge** (520x76, panel): three cells "TRAINING COST $7,040" (+ a 1.2 s delta chip "+$2,464" in `C.bad` /
  "−$…" in `C.good` when the cost changed), "TIME 0:12", "VRAM 24 of 288 GB" (value `C.bad` when the fleet has less).
- **Model Card** (compact 190x246; regular 220x270), 5.3. (critic) Every step now changes the card: line chip (1),
  core grid 3x3–7x7 (2), focus colour (3), **plan meter** = 3 vertical bars right of the grid, 1/2/3 lit for Quick /
  Standard / Deep, lit bars in `C.warn` when Deep overfits (4), name (5). Lit cores = data benefit, so a save without data
  shows a dark grid.
- **Expected panel** (compact 314x246, flex): "~74.5" 52 px accent + caption "EXPECTED" + "final 72.0–77.0"; "+12.9 vs
  your best (61.6)" (good/bad) or "Your first model"; a "BEATS YOUR BEST" chip on the card when expected > best; six
  core stat rows (24 px: label 20 px, bar, value 20 px bold) with a 3 px white tick at the best value of that stat among
  your models (non-training). (critic) With `lock == "NO_DATA"` the panel shows the data plan's result
  (`dataPlan.after`, its stats) with the warn line "After the data plan" instead of an unreachable no-data estimate.
- Regular only: **Spec sheet** under the card: "Max score 63 with perfect data · full data at 10B tokens" and "Serving
  1.4 units/user · $0.30 per 1M tokens · speed 76" (SizeDef potential/dataNeed/serveCost/speed,
  MarketConfig.SERVE_UNITS).

Right panel (686 x main, panel, padding 16): title 34 px + "STEP N OF 6" (20 px accent, right); hint 22 px muted, one line
(≤ 56 characters); body below y 92.

### 4.3 Step 1 PRODUCT (phone part: Device)
PNG `phone_02_step1_product.png`. Hint "Who is it for? You can still change the line at launch."
Body: 2x2 tiles (compact 321x108; regular 321x168), one per `ModelConfig.LINES` entry, named `Line_<target>`:
- row 1: "✓ " when selected + `line.label` (24 px) · right: "fit 77.2" (22 px accent) = `MarketMath.fit(expectedStats,
  segment)`;
- row 2: "Wants Coding + Reasoning" = the two highest weights of the line's MarketConfig.SEGMENTS entry;
- row 3: tag + status from `LabPreview.lineStatus`: `LIVE v1` "Coder v2 · 62.6 aged" (fit − `ModelMath.ageFit(
  ModelMath.versionAge(model))`), `FREE` "line 3 of 3", or `FULL` "opens with Innovation Campus"
  (`ModelsUI.officeForLines(usedLines)`). FULL tiles are disabled (cannot be planned).
- Tap: `StateController.setLine(target)` (new, 5.1). Card line chip shows `line.short`.

### 4.4 Step 2 BRAIN SIZE (phone part: Chassis / Screen size)
PNGs `phone_03_step2_size.png`, `phone_15_size_locked_garage.png`. Hint "Bigger = smarter, but needs more VRAM, data and
servers."
- Preset chips (critic: 74 px tall, 3 equal): `CHEAPEST` (s100m + rapid), `BEST I CAN AFFORD` (5.2 `bestAffordable`),
  `SAME AS LAST` (5.2 `sameAsLast`). The preset that matches the current pick is outlined.
- Five tiles (compact 122x160, gap 10; regular 190 tall with a VRAM line), named `Size_<id>`:
  label 32 px (line height 32) · 5-segment tier bar (tiers 1..5 by index) · cost 22 px bold · delta of expected overall
  vs the current pick 22 px (selected tile: "picked" in accent) · time 20 px. Check badge bottom-right.
- **Locked** tiles keep cost and delta and replace the time with two warn lines (fits 122 px, must-fix 5). (critic) The
  reason is the first one the server would return, in `AIModelService.startTraining` order: `Needs` / `research` (s7b
  without `data.empire.research.frontier` = PREREQUISITE), then `Needs` / `64 GB` (VRAM: `fleet.vram < size.vram`), then
  `Need` / `more cash` (cost > `StateController.money()`). NO_DATA and MODEL_LIMIT are not size-specific and never show
  on a tile (the Review and the START button handle them). Locked sizes stay selectable (as today); the Review shows the fix.
- Rich example (focus Coding, Standard): 100M $880 −15.1 · 500M $3,300 −4.6 · **1B $7,040 picked** · 3B $19,800 −2.8 ·
  7B $35,200 −3.6 ("bigger is not always better": 16B tokens fill only 64 % of what 3B wants). (critic) Garage example
  = starter save (4.9), Creative, Standard: **100M $1,280 picked 1:20** · 500M $4,800 +3.6 Needs 12 GB · 1B $10,240 +1.7
  Needs 24 GB · 3B $28,800 −0.3 Needs 64 GB · 7B $51,200 +2.7 Needs research (`probe_first.luau` SEST lines).
- Tap: `StateController.setSelection(sizeId, ui.focusId)` immediately.

### 4.5 Step 3 SKILL FOCUS (phone part: Specs / Features)
PNG `phone_04_step3_focus.png`. Hint "Focus shifts skills (in %) and changes who likes the model."
2x2 tiles (321x108, left border 6 px in the focus colour), named `Focus_<id>`, 4 rows at 22 px line height:
1. "✓ Coding" · right: delta of expected overall (or "picked");
2. green "+ Coding 18 · Reasoning 4" (from `ModelConfig.FOCUSES[i].mult`, values in %);
3. red "− Creativity 12 · Knowledge 6" (Balanced: "No bonus, no weakness");
4. "Dev API fit 77.2 (+1.9)" (fit in the planned line, difference vs the current pick); (critic) the tile with the
   highest fit in the planned line also shows the tag **BEST FIT** (20 px, accent) = `LabPreview.bestFocus`.
No ▲▼★ glyphs (font coverage unverified). Tap: `setSelection(ui.sizeId, focusId)`; the card colour tweens
(`Kit.tween` BackgroundColor3/UIStroke.Color 0.2 s).
Rich example (1B): Balanced 73.7 / dev fit 75.3 · Coding 74.5 / 77.2 BEST FIT · Reasoning 75.3 / 75.8 · Creative 73.5 / 72.7.
(critic) Note: the best overall (Reasoning 75.3) is not the best fit for Developers; the tag points at fit because fit
decides users (MarketMath), and the overall delta stays visible in row 1.

### 4.6 Step 4 TRAINING PLAN (phone part: Screen type / refresh)
PNG `phone_05_step4_plan.png`. Hint "More compute gives a better model, if you have enough data."
- 3 tiles (210x146), named `Recipe_<id>`, display labels **Quick pass / Standard / Deep** for ids rapid / steady / deep
  (UI labels only; `ModelConfig.RECIPES` stays unchanged): title 24 px · "0:12 · $7,040" 22 px bold · "Quality ×1.00"
  (= `ModelMath.recipeFactor`) · delta · last line: Quick "35 % less compute", Standard "Normal run", Deep "Data check ✓"
  or warn **"Overfits now (×0.85)"** when `recipeFactor` applied 0.68 (`data.total < 0.5·dataNeed` or quality < 0.6).
- Data strip (critic: 654x74): "Data 16B · 81 % · 1B wants 10B" + "· enough ✓" when the data plan is empty, a fill bar
  of `LabPreview.dataBenefit` (never "fill 200 %": the bar is the real benefit, 0–100 %), then (only when
  `LabPreview.dataPlan` has packs) `BUY DATA PLAN` 190x74 with "$2,500 · +0.8" (cost and expected gain), and `+ DATA`
  130x74 → close the Studio, `nav.show("data")`; reopening restores the step. Rich examples: 1B Coding Standard → plan
  empty ("enough ✓"); 3B Coding Standard → 1× Public Repos, $2,500, 71.7 → 72.5 (`agents/lab_crit/probe_dataplan.luau`).
- Regular adds: "Deep needs at least half of the data this size wants and 60 % quality: you have 16B of 5B and 81 % ✓".
- Rich example (1B Coding): Quick 0:12 $4,576 −5.9 · Standard 0:12 $7,040 · Deep 0:26 $16,896 +14.0. 7B Deep: "Overfits
  now (×0.85)", 61.9.
- Tap: `StateController.setRecipe(id)`.

### 4.7 Step 5 NAME & LOOK (phone part: Colour & branding)
PNG `phone_06_step5_name.png`. Hint "Give it a name. Looks never change the score."
- Name `Kit.input` (430x74, 30 px) + `RANDOM NAME` (212x74; next entry of NAME_IDEAS).
- "Becomes **Sage v2** · same name = next version" (`LabPreview.nextVersion`) or bad "Names need 2–20 characters"
  (`GameConfig.MODEL_NAME_MIN/MAX`, the `validName` rule of LabApp:91).
- "2–20 characters. Roblox checks the name when you start." (no client filter exists; none is claimed).
- Look box: focus-colour swatch + "Colour = skill focus (Coding) · Emblem = your logo "N"" (`data.company.logo`) and "Own
  colours and emblems: phase 2 (cosmetic only)".
- The card prints the name live.

### 4.8 Step 6 FINAL REVIEW (phone part: Final review)
PNG `phone_07_step6_review.png`. Hint "Check it, then start. The real score is revealed at the end."
- (critic) Money tiles 3 x (210x80): TRAINING COST $7,040 · TIME ~0:12 · CASH AFTER $179.4K (good colour, bad when
  negative; the cash itself is in the top bar). With a data plan the third tile is "CASH AFTER ALL" (cash − plan − cost).
- (critic) The four 22 px lines form **one TextButton** (654 x ≥ 112 px, a 44 pt target) with "BREAKDOWN ›" (20 px accent)
  at the right of line 1; tap = breakdown overlay over the right panel (compact); regular shows the breakdown open.
  The old text link "+ Show breakdown" (≈ 16 pt tall) is gone.
  1. "Expected **~74.5** · final 72.0–77.0 without events";
  2. "Developer API fit 77.2 · beats Coder v2 (62.6 after age)" or "· new product line";
  3. "Rank **#1 of 5** for Developers (quality, before price)" (5.2 `rank`);
  4. "3 in 10 runs pause for a decision · 1 in 10 get +5 %" (5.2 `eventOdds`: decisions 0.6 × 6/12, breakthrough
     0.6 × 2/12 for spec "general"; computed, not hard-coded).
- (critic) No data (`lock == "NO_DATA"`): the lines become "No training data yet · every AI learns from data" /
  "Data plan: 2× Web Crawl Chunk + 2× Public Repos" / "= 4B tokens · 43 % quality · $7,400" / "Then expected ~40.2 ·
  final 37.7–42.7 without events" (`dataPlan`), and the primary button is `BUY DATA PLAN · $7,400`.
- Breakdown: "Size potential 63 × data (0.92 amount × 0.91 quality) · plan ×1.00 · focus Coding" and "Bonuses: company
  spec +2 · research and Lab level +12 on each skill · cap 99" (5.2 `breakdown`).
- Primary button = today's labels (LabApp:483-505), (critic) re-ordered to the server's check order of
  `AIModelService.startTraining` so the button names the error START would get, plus three new states:
  `NAME NEEDS 2-20 CHARACTERS` · `TRAINING SLOT BUSY · <name> 45 %` (new; `data.training ~= nil`, tap → TRAINING mode)
  · `RESEARCH FRONTIER ARCHITECTURE · COMPANY` · `MODEL LIMIT · RETIRE OLD MODELS` (new; `ModelMath.activeModels(data)
  >= GameConfig.MODEL_LIMIT`, tap → Market) · `NO GPU · OPEN COMPUTE` · `NEEDS X GB MORE VRAM · OPEN COMPUTE` ·
  `BUY DATA PLAN · $X` (new; NO_DATA with a non-empty `dataPlan`) or `NEED TRAINING DATA · OPEN DATA` · `NEED $X` ·
  `START TRAINING · $7,040` · `STARTING…` / `BUYING DATA…` while a call runs.
- (critic) BUY DATA PLAN sends one `ActionController.call("BuyData", {packId = id, count = n})` per pack id of the plan
  (the existing DataApp payload, DataApp:144; server `DatasetService` unchanged, rate limit burst 6 / 3 per s, at most
  `DataConfig.MAX_BUY` = 10 per call, so a plan with more than 10 of one pack is split). It stops at the first error
  (ActionController shows the toast); the estimate refreshes from the next snapshot.

### 4.9 First model variant (garage)
(critic, rewritten) PNGs `phone_14_first_model.png` (fresh save), `phone_16_first_model_ready.png` (after the data plan),
`phone_15_size_locked_garage.png` (step 2 of the same save). Values from `agents/lab_crit/probe_first.luau` (real code)
on the "empty" test state with the casual bot's start cash.
- Defaults: 100M · **Creative** (`bestFocus` for Consumer Chat: fit 49.5 vs Balanced 46.2, Reasoning 46.1, Coding 44.1
  with the starter data; also the casual bot's `LINE_FOCUS.general`) · Standard · Consumer Chat · "Nova v1".
- Fresh save ($12,200, no data): hint "FIRST MODEL · buy the data plan, then press START."; card grid dark (no data);
  Expected panel "~40.2 · final 37.7–42.7 · After the data plan"; money tiles $1,280 · ~1:20 · CASH AFTER ALL $3,520;
  primary `BUY DATA PLAN · $7,400` (2× Web Crawl Chunk + 2× Public Repos = 4B tokens at 42.5 %).
- After the plan ($4,800): hint "FIRST MODEL · a good starter is ready. Just press START."; VRAM 4 of 6 GB; expected
  ~40.2 (37.7–42.7 without events); CASH AFTER $3,520; "Consumer Chat fit 49.5 · new product line"; "Rank #6 of 6 for
  General" (fallback rivals `MarketConfig.NPC_MODELS` while `live.marketplace` is nil, LabApp:823 rule; consumer fits
  63.5 / 61.4 / 57.1 / 51.4 / 50.9); primary `START TRAINING · $1,280`.
- Honest expectation for the reveal: a first model is normally last in the market (all five NPC models fit General
  better), so 4.11 shows "CHALLENGER" with "Next to beat: Vector Lite · fit 50.9" (+1.4 needed) instead of a bare
  "BEHIND".

### 4.10 TRAINING stage (the phone game's "in development")
PNGs `phone_08_training.png`, `phone_09_training_event.png`.
- Starting state (graft): after START ok and before the snapshot has `data.training`: "Allocating GPUs…" + the card with
  a pulsing border. The office rack blades already light up through the office `Training` attribute (PropFxController);
  nothing new is needed there.
- Preview zone: podium (ellipse Frame with UIGradient) + card (190x246) whose cores light up in reading order with real
  progress (`StateController.trainingWork()` extrapolated per frame, like LabApp:724-748): done cells in the card colour,
  the last two cells white (scan head). Right of the card: caption "TRAINING" / "TRAINING PAUSED", "45 %" (72 px), "ETA
  0:07" (28 px muted, `StateController.trainingEta()`) or "PAUSED" (warn), (critic) "expected ~74.5" (one decimal like the
  Review; LabApp:661's "%.0f" would print 74 or 75), "$7,040 paid"; progress bar 520x18 at the bottom.
- (critic) Example values at 45 % (1B Coding, expected 74.5): current loss **1.876** = `ModelMath.lossAt(21/47, 74.5, 0)`
  (22 of 48 loss points; the server adds jitter ±0.05), log "Epoch 3/10  loss 2.219" / "Epoch 4/10  loss 1.996". The
  old "2.418" did not come from the formula.
- Right panel, normal: "Training loss · lower is better" + current loss (`training.loss[#loss]`, "%.3f"), 48 loss bars
  (654x118, same scaling as LabApp:668-681), metrics row (Compute "19.2 u/s" formatted with
  `string.format("%g", math.round(fleet.throughput * 10) / 10)` — fixes LabApp:685 "19.200000000000003 u/s"; Cost; Data
  `Format.tokens(model.dataUsed.total)`; Quality "×1.00" coloured), 2 log lines (RobotoMono 20 px; regular: 6).
- Right panel, decision (`training.event.pending`): warn-stroked card, title 34 px warn (`EventDef.title`), text 22 px +
  "Training is paused until you decide.", two choice buttons 321x118 (`choice.label` 26 px + `choice.desc` 20 px; first
  "sec", second "warn" style), "Auto-picks **Ignore** in **18 s**" from `event.expiresAt - workspace:GetServerTimeNow()`
  and a countdown bar. Choice → `ActionController.call("ResolveEvent", {choice = id})`.
- Refinement runs show "Refinement 1/3 · keeps serving users with the current version" (LabApp:658-661 rule) and no
  expected number.
- Bottom bar: "Runs on the server · close any time" · `‹ LAB` · `CLOSE · it keeps training` (ghost; closes the Computer).

### 4.11 REVEAL stage (the phone game's "INTRODUCING <name>")
PNGs `phone_10_reveal.png`, `desktop_2_reveal.png`. Full canvas, no step chips.
- Top centre: "INTRODUCING" (22 px, letter spacing) + "Sage v2" (44 px).
- Centre: card 206x286 (regular 250x340) on the podium, all cores lit, footer "75.2" + 5 star pips (16 px Frames).
- Left panel 360 x main: "BENCHMARKS", all 8 stats (32 px rows; bars in the card colour; speed/efficiency scale 100 as
  LabApp:812) + "Speed, Efficiency: not in Overall".
- Right panel 420 x main: "75.2" (64 px, card colour) + caption "OVERALL" + "NEW RECORD" pill (warn) when the record rule
  holds; star pips + word (26 px warn); "#1 of 5 for Developers · stars = market rank"; "+13.6 vs your best (61.6) ·
  +0.7 lucky roll"; four audience chips (2x2, 58 px: "Developers 77" / "key: Coding 83" = the segment's highest weight
  stat; the planned line's chip outlined).
- Bottom bar: "Saved · launch now or later" · `LATER` 180 · `REFINE 1/3 · $X` 330 (disabled with the reason from
  `refineCheck`, e.g. "needs 100M new tokens" right after training) · `LAUNCH ›` 400 primary.
- Sequence (all skippable by one tap → final frame): card flip (Size X scale 1 → 0 → 1 over 0.35 s, face swap), name,
  overall counts up from the payload's `expected` to `overall` (existing `animateNumber` pattern), pips + word, the 8 bars
  fill 0.12 s apart, audience chips; confetti (≤ 40 small Frames, destroyed after 2 s) only on a record.
- Numbers: stars from 5.2 `stars(rank)`: #1 = 5 "MARKET LEADER"; p = (rank−1)/(total−1): p ≤ 0.25 = 4 "EXCELLENT",
  ≤ 0.5 = 3 "GOOD", ≤ 0.75 = 2 "OKAY", else 1 (critic) "CHALLENGER" (was "BEHIND"; the rank number next to it stays the
  honest part). (critic) When rank > 1 the rank line adds "Next to beat: <name> · fit <q>" = the entry with the smallest
  quality above yours (5.2 `rank` returns it). Record rule (must-fix 7): `record = overall >
  math.max(previousBest, before or 0)` from the S1 payload; `previousBest == 0` and not a refinement → "YOUR FIRST MODEL"
  pill instead of NEW RECORD. Lucky roll = `overall - expected` (S1) for new models only, (critic) and only when no
  quality event touched the run: if `eventId`/`outcome` (S1) map to a choice or event with `quality` that applied
  (`ignore`, `push` without "_lucky", `breakthrough`), the chip reads "−4.1 vs expected · Ignore: −6% model quality"
  (choice/event text from ModelConfig.EVENTS). Refinements show "+X from refinement" = `overall - before`. If the payload
  lacks the S1 fields (must not happen), hide those chips.
- Opened through EVALUATE (`LabApp.openSection("evaluation")`): caption "BENCHMARK REPORT", no animation, no record /
  lucky-roll chips; still calls `EvaluateModel` as today (LabApp:1340).

### 4.12 LAUNCH DAY (the phone game's 3-part launch panel)
PNGs `phone_11_launch_line.png`, `phone_12_launch_campaign.png`. Chips "1 Line · 2 Price · 3 Campaign".
Preview zone: card 164x262 + **summary column** (flex, panel; visible on every step, so the test strings are always
visible): "PRICE" / "Recommended: $4 per 1M tokens" (`ModelsUI.priceText(rec.sub, rec.api)`; "Calculating the
Recommended price from the live market..." until ready) / "Auto price: the server sets the Recommended price and
re-checks it every 5 min." (Manual: "Manual price: auto price stays off for this model until you switch it on again in
the Market app.") / "AFTER 5 MIN" "40.5K users · +$217.4K/day" (PricingMath.profit over `PRICING.cardSeconds` with the
bonuses and cycle of LabApp:1152-1171) / "campaign adds +34 users" (forecast minus the cached no-campaign forecast of the
same line) / "LAUNCH TOTAL" "$5,000 · $174.4K left". (critic) Plus, only when today's rule fires (LabApp:1173-1175:
`serving.known and (serving.full >= 0.85 or serving.waitlist >= 1)`), a warn line "After launch: Servers 97 % full."
(`ModelsUI.serving(last)`); it replaces the campaign line if space runs out. Rich example: "Servers 39 % full" → no line.
- Step 1 Line: hint (2 lines, 20 px) = today's `lineInfo` text (LabApp:1130-1138), e.g. "Developer API: successor of
  Coder v2. Becomes version 2 of the line and takes over 90 % of its 21.4K users." 2x2 tiles (321x98). **Each tile is a
  TextButton whose `Text` is `line.short`** ("Chat", "Study", "Dev API", "Business"; tile name `Line_<target>`), with
  child labels: tag NEW VERSION / NEW LINE, "Replaces Coder v2 · 19.3K move" or "New line · 3 of 3", "fit 77.2 ·
  Developer API". Lines that `releaseCheck` refuses are dimmed but stay selectable (the LAUNCH button then reads NO FREE
  PRODUCT LINE), exactly like today's segmented control.
  Preselection: `plannedLine[modelId]` when `releaseCheck(...).ok`, else today's best-fit allowed line (LabApp:1229-1239).
- Step 2 Price (critic: re-laid out for 74 px targets, PNG `phone_17_launch_price.png`): hint "Auto picks the best menu
  price and keeps adjusting it."; tiles 321x90 AUTO ("$4 per 1M tokens" / "Recommended · every 5 min") / MANUAL ("You
  set the price" / "auto price stays off"). Manual controls (dimmed while AUTO) in ONE row under two captions
  "SUBSCRIPTION / MONTH" and "API PER 1M TOKENS": chips Free/$5/$10/$20 74x74 (MarketConfig.SUB_PRICES, gap 6), then the
  API stepper `−` 74x74 · "$4.00" 150 wide 30 px · `+` 74x74 (step 0.5 as MarketApp, clamped to MarketConfig.API_PRICE).
  Body height 90 + 12 + 24 + 4 + 74 = 204 ≤ 244. The release logic moves over unchanged: `requestRecommendation` with
  `PricingMath.slicer(ModelConfig.PRICING.clientBudget)`, `toManual`, `paintControls`, `updateForecast`.
- Step 3 Campaign: hint "Launch buzz in Developers: fades over about 10 minutes." 2x3 cards (210x98): No campaign Free
  +0 % · **Recommended** `PricingMath.recommendedMarketing(money, bonuses.wage)` (≤ $5,000, **preselected**) · Big push
  $25K · Mega $100K · Global $250K · Custom (opens today's marketing slider in an overlay, range rule of LabApp:1248-1256).
  Each card shows "+X % buzz" = `MarketMath.initialHype(target, m)[ModelMath.lineOf(target)]` and a bar (closed form,
  cheap). Cards above cash: "Need $250K", not selectable. The 5-minute forecast runs **only for the selected card**,
  sliced, newest request cancels older ones (`recGen` pattern of LabApp:1075-1100).
- LAUNCH button (always visible) keeps today's labels: `LAUNCH STUDY`, `NEW VERSION · CHAT · $5K MARKETING`, `NO FREE
  PRODUCT LINE`, `NOT ENOUGH MONEY FOR THIS BUDGET` (LabApp:1178-1190).
- Rich example for "Sage v2" (1B Coding, overall 75.2) into Developer API: Recommended $4 per 1M tokens; 40,482 users and
  +$217,388/day after 5 min with $5,000; 40,448 users with no campaign; 19,260 users move from Coder v2. Buzz at $5K /
  $25K / $100K: Developers 14 / 41 / 50 %, Students 8 / 28 / 48 %, General 1 / 6 / 16 %.

### 4.13 NOW LIVE stage (replaces `playLaunch`, LabApp:875-918)
PNG `phone_13_now_live.png`. "NOW LIVE" (good) + line label (40 px); card on the podium; left card 380x300 "LAUNCH DAY":
line + "line v2" (`ModelMath.lineVersion`), "Price Auto · $4 per 1M tokens" (from the ReleaseModel response
`subPrice/apiPrice/auto`), "Marketing $5,000", "Coder v2 retired · 19.3K users moved over" (users of
`releaseCheck(...).replaced` × `ModelConfig.MIGRATE`, captured **before** the call); right card "USERS RIGHT NOW" =
Σ `model.market.users` from each new snapshot + "+N since launch". Confetti once. Buttons BACK TO LAB / OPEN MARKET ›.
(critic) The PNG shows the moment of launch with traceable values only: 19,260 users (21,400 × 0.9 migrated from
Coder v2), "+0 since launch" and "Forecast: 40.5K users after 5 min" (the Launch Day forecast, probe_flow seed 11). The
old "21,840 / +2,580" was an invented example.

### 4.14 HUD ready card
`Screens/HUD.module.luau` (another agent edits this file at the moment, so use these search anchors, not line numbers):
the next-step card keeps its title (`EmpireMath.nextGoal` text, as tests/apps check) and its `app = "lab"`,
`section = "release"`, `releaseId` (the branches `id == "release"` and `id == "lines2"` that set `view.releaseId`).
New field `view.revealId` = the trained model when `LabApp.wasRevealed(id)` is false; then the body reads "<name> vN is
ready · tap to reveal its score" and the card's `Kit.onClick(step, ...)` handler calls `LabApp.openReveal(revealId)`
instead of `LabApp.openRelease`. `wasRevealed` is session memory: every model that is already `trained` in the first
snapshot of the session counts as revealed. The `TRAINING_COMPLETE` toast in HUD's `StateController.onNotify` handler
("Training complete! Overall … Open your computer to see it.") becomes "Training complete! Open your computer for the
reveal." (no score, no spoiler).

---

## 5. Components and exact effects

### 5.1 StateController (client)
- `StateController.ui` gains `lineId = "general"` and `name = ""` (empty = pick a NAME_IDEAS name on first open).
- New `StateController.setLine(target: string)` (validates against `ModelConfig.getLine`, fires `uiListeners`) and
  `StateController.setName(text: string)` (no listener fan-out per keystroke; the Studio refreshes itself).
- Existing `setSelection` (:172) and `setRecipe` (:184) unchanged.

### 5.2 `ReplicatedStorage/Shared/LabPreview.module.luau` (new, pure, unit-testable)
No Roblox APIs. Requires only ModelConfig, MarketConfig, CompanyConfig, ModelMath, EmpireMath, MarketMath and
(critic) DataConfig (packs) + GameConfig (MODEL_LIMIT).
Signatures (Luau, `--!strict`):
- `estimate(data, sel: {sizeId, focusId, recipeId}, money: number?) -> Estimate`
  = the exact server pipeline of `AIModelService.startTraining` (:476-489) and LabApp:397-407:
  `plan = ModelMath.plan(size, ModelMath.fleet(data.gpus), ModelMath.dataSummary(data.data), recipeId)`;
  `stats = ModelMath.computeStats(size.id, focus.id, summary, spec, ModelMath.recipeFactor(size, summary, recipeId), nil)`
  → `EmpireMath.boostStats(stats, data.empire)` → `ModelMath.capStats(stats)`;
  `rate = EmpireMath.trainingRate(data.gpus, plan.work, data.empire)`, `seconds = plan.work / rate`.
  Returns `{stats, overall, cost = plan.cost, work, seconds, readiness, recipeFactor, overfit, lock}`;
  (critic) `lock` in the order of `AIModelService.startTraining` (:448-458): `FRONTIER` (s7b without research =
  PREREQUISITE) → `MODEL_LIMIT` (`ModelMath.activeModels(data) >= GameConfig.MODEL_LIMIT`) → the `ModelMath.plan` reason
  (`NO_GPU` → `VRAM {need, have}` → `NO_DATA`) → `MONEY` (only when `money` given). The old order put FRONTIER after
  VRAM and had no MODEL_LIMIT.
- `range(overall) -> (lo, hi)` = `max(1, overall − TRAINING.noise)`, `min(STAT_CAP, overall + TRAINING.noise)`.
- `deltas(data, sel, field: "sizeId"|"focusId"|"recipeId", money) -> {[id]: {estimate, dOverall, dCost}}`
  (≤ 5 + 4 + 3 extra estimates per refresh; tiles are built once and only their texts change).
- `dataBenefit(readiness) -> number` = `min(1, quantity / (1 − exp(−DATA.quantityK × DATA.maxFill)))`.
- `cores(sizeId) -> number` = 3/4/5/6/7 by size index; `litCores(sizeId, readiness) = round(cores² × dataBenefit)`.
- `lineQuality(stats, target?, segmentId, vage) -> number` = `MarketMath.fit(stats, seg)` − (`LINE_PENALTY × FIT_SCALE`
  = 18 when `target ~= nil` and `ModelMath.lineOf(target) ~= segmentId`) − `ModelMath.ageFit(vage)` (MarketMath.playerUtility
  without the price term, in fit points).
- (critic) `bestFocus(data, sizeId, recipeId, target) -> focusId` = argmax over `ModelConfig.FOCUSES` of
  `MarketMath.fit(estimate(...).stats, segmentOf(target))`; ties → the earlier focus in ModelConfig order. Used for the
  first-model default and the BEST FIT tag. Starter save, Consumer Chat: Creative 49.5 (Balanced 46.2, Reasoning 46.1,
  Coding 44.1); rich, Developer API, 1B: Coding 77.2.
- (critic) `dataPlan(data, sel, money, wage) -> {packs = {[packId]: count}, cost, tokens, quality, before, after, stats}`
  = the casual bot's `planData` (agents/corefix/sim.luau:347-370) on a copy of `data.data`: `budget = 0.8 × (money −
  reserve − estimate(sel).cost)`, `reserve = max(1500, wage × 120)`; up to 60 times buy the `DataConfig.PACKS` entry
  with the highest `(expected overall after − before) / price` that still fits the budget; stop when that gain is below
  0.3 points per $1,000. Expected overall = `computeStats` + `boostStats` with `sel` (the bot uses the same, uncapped
  by `capStats`; boostStats already caps core stats at 99). Fresh garage ($12,200, Creative 100M Standard): 2× web_chunk
  + 2× repos, $7,400, 4B tokens at 0.425, 18.1 → 40.2. Rich 1B Coding: empty. Rich 3B Coding: 1× repos, $2,500,
  71.7 → 72.5. The mockup's JS port matches these three cases.
- `rank(snapshot, stats, target) -> {rank, total, next?}` ((critic) `next = {name, quality}` = the entry with the
  smallest quality above the candidate, for "Next to beat"): entries = `live.marketplace.offers` whose id is not in `data.models`
  (stats, target, `vage or 0`) + own live models whose line differs from `lineOf(target)`; fallback when
  `live.marketplace == nil`: `MarketConfig.NPC_MODELS` (no target, age 0). `rank = 1 + #{q > candidate}`, candidate in
  line with age 0. (Own models in the same line are excluded: the new model would replace them.)
- `stars(r) -> (pips, word)` as 4.11.
- `lineStatus(data, target) -> {kind: "LIVE"|"FREE"|"FULL", model?, agedFit?, version?, usedLines, slots}` from
  `ModelMath.releaseCheck(data, "", target)` (works for a model that does not exist yet) and `ModelMath.lineVersion`.
  The client turns `usedLines` into "opens with <office>" with `ModelsUI.officeForLines` + `ModelsUI.officeName`
  (LabPreview is shared and must not require client modules).
- `nextVersion(data, name) -> number` = the rule of `AIModelService.versionFor` (:73-84): max(count, highest) + 1 over
  models with the same lower-case name. The server keeps its own copy; a test compares them.
- `bestAffordable(data, focusId, money, saveMode: boolean) -> {sizeId, recipeId, estimate}?`: argmax expected overall over
  all size × recipe without lock, with `cost ≤ budget`; ties → cheaper. `reserve = max(1500, EmpireMath.bonuses(e).wage × 120)`
  (the reserve of `PricingMath.recommendedMarketing`); `free = money − reserve`; `budget = free`, or `0.3 × free` when
  `snapshot.live.ops.saveMode == true` (CORE_SPEC 8.1). The preset label shows "$X left after training" in the cost badge.
  Rich: 1B Deep, 88.0, $16,896.
- `sameAsLast(data) -> {sizeId, focusId}?` = newest non-training model in `modelOrder` (recipe is not saved in phase 1;
  `ui.recipeId` stays).
- `successor(data, money, saveMode) -> {target, name, focusId, sizeId, recipeId}?` = the live line with the largest
  `ageFit(versionAge(model))` (ties: modelOrder), its model's name and focus, size/recipe from `bestAffordable`.
  Rich: Developer API, "Coder" (v3), Balanced, 1B Deep.
- `refineCheck(data, model, money) -> {ok, err?, reason?, cost?, runs}` mirrors `AIModelService.improveModel` (:534-563)
  in the same order: `TRAINING_ACTIVE` ("Training slot busy") → `REFINE_LIMIT` ("Refined 3/3") → `NEW_DATA` ("needs
  100M new tokens" = `dataUsed.total + 1e8 − summary.total` rounded up, `Format.tokens`) → plan reason with the default
  recipe (`NO_GPU`/`VRAM`/`NO_DATA`) → `NO_MONEY` (`money < ModelMath.refinePlan(model, plan).cost`).
- `eventOdds(specId) -> (decision, boost)` = `TRAINING.eventChance ×` (weight of events with choices / total weight,
  with the spec's `breakthroughMult`) → 0.6 × 6/12 = 0.30 for spec "general"; (critic) `boost` = `eventChance ×`
  breakthrough weight / total → 0.6 × 2/12 = 0.10. Text: "3 in 10 runs pause for a decision · 1 in 10 get +5 %"
  (rounded to tenths; the +5 % is the breakthrough's `quality = 1.05`).
- `breakdown(data, sel) -> {potential, quantity, quality, recipeFactor, focusId, spec, core, reliabilityBonus, cap}`
  (`EmpireMath.bonuses(e).core`, `.reliability`, CompanyConfig spec `statBonus`).
- `campaignBuzz(target, marketing) -> number` = `MarketMath.initialHype(target, marketing)[ModelMath.lineOf(target)]`.

### 5.3 `Client/UI/Studio/StudioParts.module.luau` (new)
- `ModelCard.new(parent, size: Vector2) -> card` with `card:set({sizeId, focusId, name, version, lineShort, logo,
  lit, sweep?, overall?, stars?, beatsBest?, recipeId?, overfit?})` ((critic) `recipeId` drives the plan meter: three
  8x14 Frames right of the core grid, lit bottom-up 1/2/3, `C.warn` when `overfit`). Built from Frame, UICorner, UIStroke, UIGradient, UIGridLayout
  (CellSize from the core count), UIAspectRatioConstraint (all in `tools/API-Dump.json`). Card fill = UIGradient from
  the focus colour (30 %) to `C.panel`; stroke the focus colour; line chip (20 px), emblem (company logo, 30x30, 20 px),
  core grid, name 26 px, sub 20 px (critic: was 18), optional footer (overall + pips). Reused small on the Lab home Hall of fame.
- `OptionTile.new(parent, name)` → TextButton with child labels, `:set({title, lines, selected, locked, delta})`.
  Built once per step; texts updated in place (no destroy/rebuild per snapshot).
- `StepChips.new(parent, labels)`, `CostBadge.new(parent)`, `Stage.new(parent)` (background, two light beams = Frames with
  UIGradient transparency, no Rotation; podium; confetti burst).

### 5.4 Other client modules
- `Client/UI/Studio/Studio.module.luau`: host, scale, bars, modes `closed | design | training | reveal | launch | live`,
  input (3.5), `Toast.hold` calls.
- `Client/UI/Studio/DesignSteps.module.luau`: steps 1–6 + presets + START state machine.
- `Client/UI/Studio/Stages.module.luau`: training, reveal, live (moves the logic of LabApp:550-749 and :753-871).
- `Client/UI/Studio/LaunchDay.module.luau`: moves LabApp:920-1287 with unchanged logic.
- `Apps/LabApp.module.luau`: becomes the Lab home + public API. Keeps `mount`, `onShow`, `openRelease(modelId)`,
  `openSection(section)` (adds "design" and "train"); adds `openStudio(mode, opts)`, `openReveal(modelId)`,
  `wasRevealed(modelId)`, `plannedLine`. `onShow`: if `data.training.event.pending` → TRAINING mode; if a reveal is pending
  → REVEAL. Notify handling (LabApp:1309-1322): `TRAINING_COMPLETE` → store the payload; Computer open → REVEAL;
  `TRAINING_EVENT` with Computer open → TRAINING mode.
- `Apps/ModelsUI.module.luau`: unchanged API; LabPreview holds the new math.
- `Shared/JourneyMath.module.luau`: STEPS "design" gets `section = "design"`, "train" gets `section = "train"` (pure table
  fields; Computer:350-353 already passes `def.section`).
- `Screens/HUD.module.luau`: 4.14. `UI/Toast.module.luau`: `Toast.hold` (3.6).

---

## 6. Server and remote changes

### 6.1 Phase 1, S1 (the only server edit): extend the TRAINING_COMPLETE notify payload
File `ServerScriptService/Server/Services/AIModelService.module.luau`, function `finish` (:299-355). Display only; no
save, balance or rate-limit change.
```lua
-- at the top of `if model then`, before model.stats/overall are overwritten:
local before = model.overall
-- ... unchanged ...
Remote.fire(session.player, "Notify", "TRAINING_COMPLETE", {
	modelId = model.id,
	overall = overall,
	previousBest = previousBest,
	-- LAB_SPEC S1 (display only): reveal count-up, lucky roll, refinement gain, event chip
	expected = training.expected,
	refinement = training.refinement == true,
	before = if training.refinement then before else nil,
	eventId = if training.event then training.event.id else nil,
	outcome = if training.event then training.event.outcome else nil,
})
```
Client validation: every new field is read with a `typeof` check (`number`, `boolean`, `string`); missing → the matching
chip is hidden. Size: < 100 bytes per completed training (a Notify, not part of snapshots).

### 6.2 Unchanged remotes (validation recap, for the builder's error routing)
- `StartTraining {name, sizeId, focusId, recipeId}` (:430-532), order: `BAD_INPUT` (recipe) → `TRAINING_ACTIVE` →
  `BAD_NAME` (Guard.text 2–20) → `BAD_INPUT` (size/focus) → `PREREQUISITE` (7B without frontier) → `MODEL_LIMIT` →
  `NO_GPU`/`VRAM`/`NO_DATA` → `NO_MONEY` → filter yield → `FILTER_DOWN` / `NAME_FILTERED` → re-checks
  (`LOADING`, `TRAINING_ACTIVE`, plan, `MODEL_LIMIT`, `NO_MONEY`) → `{ok = true, modelId}`. Rate limit burst 3, 0.5/s.
- `ResolveEvent {choice}`, `ImproveModel {modelId}`, `EvaluateModel {modelId}`, `ReleaseModel {modelId, target,
  marketing, auto, subPrice?, apiPrice?}`: unchanged (:534-691, :745-750).
- (critic) `BuyData {packId, count}` (DatasetService, bound with burst 6 / 3 per s, `company = true`): unchanged; the
  Studio's BUY DATA PLAN uses exactly DataApp's payload. No new remote, no server edit.

### 6.3 Phase 2 (optional, after phase 1 ships; cosmetic + persistence, no balance change)
- `StartTraining` accepts optional `look` (string `"<colorId>:<emblemIndex>"`, colorId ∈ CompanyConfig.COLORS ids,
  emblemIndex 1..#CompanyConfig.LOGOS, the 8 company-logo glyphs the game already validates with
  `CompanyConfig.isLogo`) and optional `target` (`MarketConfig.isTarget`). Validation: absent = nil; present but
  invalid → `{ok = false, err = "BAD_INPUT"}` exactly like `recipeId` (:431-432), checked before the name filter yield.
- Stores `model.look`, `model.plan` (= target), `model.recipeId`. `Types.ModelData` gains `look: string?`,
  `plan: string?`, `recipeId: string?`.
- Launch Day preselects `model.plan` (fallback `plannedLine`, then best fit); SAME AS LAST reads `model.recipeId`.
- Net: ≤ 30 bytes per model; worst case 160 models ≈ 5 KB in a full snapshot (typical < 0.5 KB); deltas only on creation.
  Re-run `tests/net/test_e2e.luau` (budget ≤ 15 KB/s per player, CORE_SPEC 11.8).

---

## 7. Save compatibility
- Phase 1: **no save change.** `StateController.ui.lineId/name`, `plannedLine` and `wasRevealed` are client memory
  (lost on rejoin by design: Launch Day falls back to today's best-fit line; trained models count as revealed).
  No `DATA_VERSION` bump. Old saves load unchanged.
- Phase 2: new optional ModelData fields. No `DATA_VERSION` bump (absent fields = old behaviour). The model cleaner in
  `ServerScriptService/Server/Lib/Template.module.luau` (:388-397, the `for _, m in raw.models` loop) adds:
  `look` kept only if it parses to a valid colour id + emblem index; `plan` kept only if `MarketConfig.isTarget`;
  `recipeId` kept only if `ModelConfig.getRecipe`. Anything else → nil. Old models (no fields) load as today.
- (critic) Rollback check: today's cleaner edits model tables in place (vage, replacedBy, release.auto) and does not
  rebuild them, so a save written by phase 2 and loaded by a phase-1 server keeps `look/plan/recipeId` untouched and
  unused; nothing breaks in either direction. The phase-1 data plan only buys packs through the existing remote, so it
  writes nothing new into the save. `GuiService.TouchControlsEnabled` is client state and never saved.

---

## 8. Balance guard (what must stay equal)
- No change to ModelMath, EmpireMath, MarketMath, PricingMath, ModelConfig numbers, MarketConfig, AIModelService rules
  (only the S1 payload), PricingService, MarketService, Template (phase 1), Types (phase 1), Net.
- Must pass unchanged: `tests/models/test_models.luau`, `tests/models/test_ui.luau` (empty/rich/full) **without editing
  its checks**, `tests/apps/*` (HUD: `v.app == "lab" and v.section == "release"` in test_adv.luau:152 and the goal title
  checks), `tests/econ/*`, `tests/corefix/*`, `tests/net/*`, `tests/phone/*`, and the whole `tests/lead/run_all.sh`.
- Economy simulator: run `agents/corefix/run_sim.sh lab_guard --minutes 180` before and after the change (same work/src
  except this package) and diff the outputs; they must be identical (the bot calls `StartTraining` directly,
  `agents/corefix/sim.luau:447`, and does not read Notify payloads).
### 8.1 (critic) Economy re-verification: do the UI's suggestions keep CORE_SPEC's targets?
The diff above only proves the server is unchanged. CORE_SPEC 9 measured its targets with the casual bot, and a real
player now follows the Studio's suggestions instead. What is already equal to the bot (checked in sim.luau):
first model 100M Standard for Consumer Chat with Creative (bot: `LINE_FOCUS.general`, log "release Nova1 s100m
creative"); `dataPlan` = the bot's `planData` (same budget, gain rule and stop rule; reproduced: 4B q0.42, exp 40.2);
Recommended price + marketing ≤ $5,000 and auto price (unchanged release card logic); reserve = max($1,500, 2 min of
payroll); Save mode caps a training at 30 % of free cash (bot: `cost > (money − reserve) × 0.3` → skip).
What differs: `bestAffordable` takes the argmax over size × plan (incl. Quick pass) without the bot's server-capacity
check (`fits()`, sim.luau:409-420) and without its "≥ 3 better than the line's current model" rule; humans also act
slower than once per second.
Procedure (sim only, nothing shipped):
1. Add a flag `--ui-defaults` to `agents/corefix/sim.luau`: the training choice becomes
   `LabPreview.bestAffordable(data, LabPreview.bestFocus(data, …, line), money, saving)`, restricted to sizes that pass
   the bot's `fits()` and keeping the bot's "≥ current + 3" gate; data purchases use `LabPreview.dataPlan`; the launch
   line is the planned line (else the bot's choice); price and marketing unchanged.
2. Run the 12 casual runs of CORE_SPEC 9.4 twice, with and without the flag (seeds 7 / 11 / 23 / 4242 × start hours
   8.6 / 12 / 16.9, `--minutes 180`, as in `agents/corefix/run_batch.sh`; the batch uses `--hour 8.6` / `--hour 12` and
   the default start for 16.9).
3. Pass when, per run: Founder HQ move within CORE_SPEC's casual range 7.5–10.9 min; Startup Campus, Innovation and
   Global HQ each ≤ +10 % later than the same seed/hour without the flag; $/min at 10 and at 120 min ≥ −10 %; lowest
   cash ≥ $0 (CORE_SPEC casual minimum $1,521). Report all 24 runs as a table like CORE_SPEC 9.4.
4. Fail → BEST I CAN AFFORD stays a visible preset but is never preselected, the SUCCESSOR tile uses the bot's rule
   (largest size that passes `fits()`, Deep when affordable and data is enough) instead of `bestAffordable`, and the lead
   decides whether CORE_SPEC needs an amendment. Until the run is done, this item is reported as **not run**.

- Observation for the lead (NOT changed here): in the rich test state the 5-minute forecast barely reacts to marketing
  (Developer API 40,448 users with $0, 40,482 with $5,000, 40,498 with $100,000; probe_flow.luau). Big campaign cards could
  waste money; the UI therefore shows "campaign adds +N users" for the selected card, and Recommended stays preselected.
  Whether marketing is too weak at Startup Campus is a CORE_SPEC question.

---

## 9. Tests the builder must write (report each as passed / failed / not run)
1. `tests/models/test_labpreview.luau` (pure, mock):
   - `estimate` equals the server: call the real `StartTraining` handler in the mock state and compare
     `data.training.expected` and `trainCost` with `estimate(...)` for all 5 sizes × 3 recipes × 4 focuses (rich) and 100M
     (garage) — the **honesty check**.
   - rich values: 1B Standard 73.7 / $7,040 / 12 s; 1B Deep 88.0 / $16,896 / 25.8 s; 3B 70.9; 7B Deep 61.9 with overfit true.
   - `nextVersion` equals the server's `model.version` after StartTraining for "Sage" (2), "Nova" (3), "Coder" (3), "Zed" (1).
   - `refineCheck` returns the same error code as the real `ImproveModel` handler in 6 states (training active, limit,
     no new data, no GPU, no money, ok).
   - `bestAffordable`: rich → s1b/deep; with money $10,000 → never spends more than money − $1,500; with Save mode → cost ≤
     0.3 × free cash.
   - `rank` rich Developer API with the expected 1B Coding stats → #1 of 5; (critic) starter Consumer Chat (100M
     Creative) → #6 of 6 with `next = Vector Lite, 50.9`.
   - (critic) `estimate(...).lock` equals the error code of the real `StartTraining` handler for: 7B without frontier
     and too little VRAM (both → FRONTIER/PREREQUISITE), MODEL_LIMIT (80 non-retired models), VRAM, NO_DATA (fresh save),
     NO_MONEY.
   - (critic) `dataPlan` equals the bot: run `planData` of `agents/corefix/sim.luau` (dry) and `LabPreview.dataPlan` on
     the fresh garage ($12,200, Creative 100M Standard) → 2× web_chunk + 2× repos, $7,400; rich 1B Coding → empty; rich 3B
     Coding → 1× repos. After buying the plan through the real `BuyData` handler, `estimate` = 40.2.
   - (critic) `bestFocus`: starter + Consumer Chat → creative; rich 1B + Developer API → coding.
   - (critic) `eventOdds("general")` → 0.30, 0.10.
   - `lineQuality(Coder v2 stats, "developers", "developers", 2700)` = 68.55 − 6.0 (±0.01).
2. `tests/models/test_studio.luau` (UI in the mock via `ui_setup.luau`, states empty/rich/full):
   - DESIGN opens the Studio; `ModelStudio` is a descendant of the frame named "Computer"; `Computer.close()` + settle →
     Studio not visible; `Computer.open("market")` → Studio closed.
   - First model (empty + data): DESIGN opens at step 6 with "FIRST MODEL"; START sends exactly
     `{name, sizeId = "s100m", focusId = "balanced", recipeId = "steady"}` (wrap the RemoteFunction double).
   - Tile texts equal LabPreview values (Size_s3b delta "−2.8" in rich); a VRAM-locked tile in the garage shows "Needs" and
     "12 GB" and both labels fit (TextBounds.X ≤ tile width − padding in guiprev feedback, or text length ≤ 6 chars).
   - Review "~74.5" equals `string.format("~%.1f", data.training.expected)` right after START (honesty).
   - Error routing: force `NAME_FILTERED` (stub TextFilter) → step 5; `VRAM` → Computer shows "compute".
   - REFINE on the reveal right after training is disabled with "needs 100M new tokens"; clicking it sends nothing.
   - REVEAL shows `model.overall`; NEW RECORD only when `overall > max(previousBest, before)`; a refinement of the best
     model compares against its own old score (S1 `before`).
   - No visible text contains "19.2000" (u/s fix) or "fill 200".
   - Launch Day: summary strings visible on steps 1–3; Campaign: Recommended preselected; only one forecast job runs per
     selection (count `PricingMath.profit` calls via a wrapper).
   - Gamepad: with `GamepadEnabled` stubbed true, `GuiService.SelectedObject` is the selected tile after each step change;
     `UnbindAction` called on close (wrap ContextActionService in the mock). Real controller test: **not run** (Studio only).
   - (critic) Tap count: fresh save (empty state, $12,200) from Lab home to `status == "live"` ≤ 5 clicks (DESIGN, BUY DATA
     PLAN, START, LAUNCH ›, LAUNCH) with `AIModelService.finishNow` between; a save with data ≤ 4; rich returning player
     DESIGN → "6 Review" → START = 3 clicks and the sent payload equals the prefilled plan.
   - (critic) Sizes (guiprev feedback, phone preset): every TextLabel/TextButton inside `ModelStudio` has
     `TextSize × scale ≥ 11.9 pt` and every GuiButton `min(AbsoluteSize) ≥ 44 pt` (AbsoluteSize / screen points);
     inside the Lab home (compact) `TextSize ≥ 28`. Report the smallest values (mockup audit: 11.96 pt / 44.3 pt).
   - (critic) Touch controls: with `TouchEnabled` stubbed true, opening the Studio sets `GuiService.TouchControlsEnabled`
     to false and every close path (‹ LAB, ×, `Computer.close()`, `Computer.open("market")`) restores the stored value
     (stub GuiService in the mock); with `TouchEnabled` false the property is never written.
   - Performance: one design refresh in rich ≤ 2 ms of `os.clock` in the mock (report the number; soft check).
3. `tests/models/test_ui.luau`: must pass **unchanged** (the Lab home and Launch Day keep every string and the
   `buttons("Study")`, `buttons("Chat")` prefix clicks hit the Launch Day line tiles).
4. `tests/models/scene_models.luau`: add `app=lab view=studio mode=design step=1..6`, `mode=training [event=1]`,
   `mode=reveal`, `mode=launch ls=1..3`, `mode=live`; render each with guiprev `--viewport phone` and `--viewport desktop`
   into `out/lab_studio/` and look at every image (guiprev does not render Rotation, tweens, flex, CanvasGroup or
   ViewportFrames: every ceremony needs a static final frame).
5. `tests/lead/run_all.sh` full run; the simulator diff of section 8; (critic) the `--ui-defaults` runs of 8.1 (or
   report them as **not run**).

---

## 10. What stays unchanged (explicit)
- Product lines: one live model per line, release into a live line = next version (90 % users move), LINE_LIMIT per office
  (`MarketConfig.PRODUCT_SLOTS`), ageing (−8 fit over 3600 s).
- Refinement: max 3, cost × (1 + 0.5·runs), additive gain, model keeps serving; the NEW_DATA rule (100M new tokens).
- Lab level: price, +1 core per level, max 10, the UPGRADE LAB card and its remote `EmpireAction {action = "labLevel"}`.
- Pricing: Recommended (menu sub {5,10}, API {1,2,3,4}), Auto price every 300 s, manual price switches auto off, marketing
  ≤ $5,000 recommended, the release payload and server checks.
- MarketApp (lines, auto/manual price, refine buttons, capacity/waitlist), DataApp, ComputeApp, EmpireApp, the phone chat.
- Training events, their choices, the 25 s timeout and `autoResolve`; one training slot.
- The Computer window, its sidebar and journey flow (only two new `section` fields in JourneyMath).

---

## 11. Files, order and effort
Create: `Shared/LabPreview.module.luau`; `Client/UI/Studio/{Studio, StudioParts, DesignSteps, Stages, LaunchDay}.module.luau`;
`tests/models/test_labpreview.luau`; `tests/models/test_studio.luau`.
Modify: `Client/UI/Apps/LabApp.module.luau` (Lab home + API), `Client/Controllers/StateController.module.luau` (lineId,
name, setLine, setName), `Client/UI/Screens/HUD.module.luau` (ready card, toast text), `Client/UI/Toast.module.luau`
(hold), `Shared/JourneyMath.module.luau` (two section fields), `Server/Services/AIModelService.module.luau` (S1 only),
`tests/models/scene_models.luau`. Optional: `Client/UI/Screens/Computer.module.luau` (`setShade`).
Order: D1 LabPreview + its tests; D2 Studio shell, scale, parts, card; D3 design steps + START + error routing (critic: + BUY DATA PLAN, bestFocus, plan meter, 74 px chips); D4 Lab home
(compact tokens) + HUD + Toast + Journey; D5 training/reveal/live stages + S1; D6 Launch Day move + test_studio; D7 guiprev
phone/desktop pass, gamepad wiring, run_all + simulator diff. About 2,400–2,800 Luau lines (LabApp is 1,347 today; ~450
move over) + ~400 test lines; 6–7 agent-days. Then one playtest in Roblox Studio and on a real phone (tweens, flip,
confetti and gamepad cannot be checked headless).

---

## 12. Risks and open items
- Phone fit is tight: every compact body ≤ 244 px, ≤ 5 options, (critic) 20 px minimum text with no exceptions and 74 px
  minimum targets (3.4).
  Verified only in the HTML mockup (Figtree font as a stand-in for BuilderSans): BuilderSans metrics differ; the guiprev
  pass (9.4) is mandatory before review.
- (critic) Path to the first model: 4 taps with data (today 3), 5 on a fresh save, where today's form cannot start at all
  before a trip to Datasets; human time not measured. Measure in a playtest. BUY DATA PLAN spends $7,400 of $12,200 on a
  fresh save, exactly like the verified bot; a cheaper single "Web Crawl Chunk" would give a weaker first model (the
  greedy rule's first pack alone) and is still possible through + DATA.
- (critic) Not verified: whether the engine's TouchGui sits below the Dim layer (3.1 removes the dependency); the
  BuilderSans widths of the 20 px tags and of "6 Review" (110 px); the 8.1 economy runs.
- (critic) The Computer chrome on the way to the Lab (sidebar, journey strip) stays at 5–7 pt on phones; a request for its
  owner, not part of this package (4.1).
- Stars are market-relative: the same score can earn fewer stars later; the info line says so.
- Planned line and reveal memory are lost on rejoin (phase 1); acceptable fallbacks defined.
- The Lab home stays inside the 1180-px-wide Computer window (~510 pt on the phone); compact tokens make it readable, but
  the window width itself is out of scope.
- Toasts still sit at the top centre (Top layer 30); the Studio keeps that lane empty and holds info toasts in ceremonies.
- Marketing barely changes the forecast in the rich state (section 8): a balance question for the lead, not this package.

---

## 13. Mockup and renders
- Mockup: `out/lab_design/mockup.html` (open in a browser; the screen picker at the top switches screens and devices; tiles,
  presets, chips, name box, START, the event choice, Launch Day steps and campaign cards are clickable). Example values are
  computed with the game's formulas (`agents/lab_spec/mathport.js`, checked against the real Luau code); Launch Day
  forecasts are fixed values from `agents/lab_spec/probe_flow.luau` (seed 11) for the example model "Sage v2"; the
  first-model screens use the JS states `fresh` / `starter` and `GameMath.dataPlan` (port of the bot's rule).
- Renders (Playwright, `agents/lab_spec/shoot.js`):
  phone_01_lab_home, phone_02_step1_product, phone_03_step2_size, phone_04_step3_focus, phone_05_step4_plan,
  phone_06_step5_name, phone_07_step6_review, phone_08_training, phone_09_training_event, phone_10_reveal,
  phone_11_launch_line, phone_12_launch_campaign, phone_13_now_live, phone_14_first_model (fresh save, no data),
  phone_15_size_locked_garage (starter save), (critic) phone_16_first_model_ready, phone_17_launch_price
  (all 844x390 @2x), desktop_1_step2_size, desktop_2_reveal (1280x720). `shoot.js` also reports clipped text and
  children that spill out of tiles, panels, buttons, chips, cards or the Review's lines button (none on 2026-10-10).
- (critic) Checks: `agents/lab_crit/audit.js` (smallest text 11.96 pt, smallest tap 44.3 pt on all 17 phone screens),
  `agents/lab_crit/check_starter.js` (120/120 vs the real Luau), `agents/lab_spec/check_mathport.js` (50/50),
  `agents/lab_spec/clicktest.js` and `agents/lab_crit/firstpath.js` (no JS errors; fresh save → BUY DATA PLAN → START).
