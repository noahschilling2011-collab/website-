# Model Studio: low-risk restaging of the AI creation screen (safe_wizard)

Angle: keep every economy rule exactly as it is (size, focus, recipe, lines, refine, Lab level, pricing).
Only restage it: a short wizard with a live model card, readable on an iPhone in landscape, with honest
deltas and three big moments (training montage, score reveal, launch ceremony).
Everything below was checked against work/src on 2026-10-10 unless it is marked ASSUMPTION or UNVERIFIED.

## 0. Facts this design is built on (verified in code)

- Phone scale: UIRoot scales a 1280x720 design by min(w/1280, h/720). On 844x390 with insets 58/47/21/47 (guiprev
  preset) the safe area is 750x311 pt, so the scale is 0.432 and the overlay root is about 1736x720 design px.
  The Computer window has a UISizeConstraint MaxSize of 1180x740 (Computer.module.luau), so on the phone it uses
  only about 510 of the 750 pt. The Lab content area is about 939x542 design px, which is about 406x234 pt.
- Today's text on the phone: 12-15 design px, which is about 5-6.5 pt. START TRAINING is 50 px tall (about 21.6 pt)
  and below the fold (out/models/lab_rich_strip_creator.png, agents/lab_research/prev/lab_creator_phone.png).
- The client preview already runs the server's own pipeline: computeStats(recipeFactor) -> EmpireMath.boostStats
  -> ModelMath.capStats (LabApp:403-405 = AIModelService:487-489). Every preview number in this design reuses it.
- Noise: finish() adds session.rng:NextNumber(-2.5, 2.5) per stat (TRAINING.noise = 2.5). Overall is a weighted
  mean, so before events the final overall lies within expected ±2.5 (the 99 cap can only lower it).
- Events: one roll at 35 % progress with a 60 % chance. Quality effects: data_issue/ignore x0.94,
  instability/push x0.9 with a 50 % gamble, breakthrough x1.05. Time effects: x1.15, x1.2 (+15 % cost), x1.25, x0.8.
  The decision timeout is 25 s. event.outcome is written into data.training.event (applyChoice).
- Garage start: the laptop has 6 GB VRAM and 0.5 u/s, so only 100M (4 GB) can be trained. 500M needs 12 GB.
  The first training takes about 80 s (work 40 / 0.5 u/s), which matches CORE_SPEC 1.2 "0:00-1:18".
- Line fit: MarketMath.fit(stats, segment). Ageing: ModelMath.ageFit(ModelMath.versionAge(model)), up to 8 fit points
  after 3600 s (CORE_SPEC 7.3). Rivals: live.marketplace.offers carry stats, target, company, name, overall, npc and
  vage (MarketService.tickGlobal).
- ModelMath.releaseCheck(data, "", target) works for a model that does not exist yet (it skips id == modelId only).
- versionFor (AIModelService:73) = max(count of same-name models, highest version) + 1, so the client can show
  "becomes Nova v3".
- StartTraining returns {ok=true, modelId}. ActionController.call returns (ok, response).
- In the world, rack blades already react while training runs: the office attribute "Training" gates
  PropFxController fx (RoomKitsGarage:102, RoomKitsPavilion:1302, RoomKitsSpecial:187).
- Toast holder is anchored at the top centre of the Top layer (DisplayOrder 30). Toast has only mount/show (no mute).
- APIs used below, all present in tools/API-Dump.json: Instance:FindFirstAncestor, GuiBase2d.AbsoluteSize,
  UIScale.Scale, UIGradient.Offset/Rotation, GuiObject.Rotation, TextLabel.MaxVisibleGraphemes,
  UIAspectRatioConstraint, UITextSizeConstraint, GuiService.SelectedObject, UserInputService.GamepadEnabled/TouchEnabled,
  GuiObject.Selectable, ContextActionService:BindActionAtPriority, UIListLayout.Wraps.
- guiprev does not render tweens, ViewportFrames, UIPageLayout, Rotation or CanvasGroup. So the model card is built
  from Frames + UICorner + UIStroke + UIGradient only: it shows in previews. Rotation is used only in the launch beams.

## 1. Flow (open Lab -> live model)

1. Lab Home (inside the Computer window, the old "creator" view replaced). It is a hub and keeps every string that
   tests/models/test_ui.luau checks: "MODEL LAB", "Product lines · x / y live at <office>", "1 training slot",
   "Every stat caps at 99", "Lab level N" + "Lab level N adds +N to each", "UPGRADE LAB · ...", ready rows with
   "REFINE 1/3" + "refined 0/3".
   Its hero card changes with the state:
   - idle: DESIGN NEW MODEL + "Same again" (last size/focus/plan -> opens the Review step);
   - training: the progress and a WATCH button;
   - ready: <name> is ready + LAUNCH.
   Every live line row gets TRAIN SUCCESSOR (opens the Studio with that line picked and the live model's size and focus).
2. Model Studio (a full-screen takeover; the same frame is used on phone and desktop). Six steps:
   GOAL (product line) -> SIZE -> SKILLS (focus) -> PLAN (recipe) -> NAME (Phase B: LOOK) -> REVIEW.
   - Every step has a valid default, so a repeat player taps chip 6 and then START (2 taps).
   - Each step writes StateController.ui right away (setSelection/setRecipe), as today, because DataApp and
     JourneyMath read that selection.
3. START TRAINING sends the unchanged payload {name, sizeId, focusId, recipeId}. On ok the Studio switches at once to
   a "starting" state ("Allocating GPUs..."). The training montage starts when the snapshot carries data.training.
4. Training montage: progress, loss columns (server data), log lines (server text) and the event decision card.
   It can be closed at any time; training keeps running and the HUD and Lab Home show it.
5. Result reveal on TRAINING_COMPLETE (only when the Computer is open, as today): expected -> actual count-up, a
   staged benchmark reveal, record and market-rank badges, then LAUNCH / REFINE / LATER.
6. Launch Day: 1 Line, 2 Price (Auto/Recommended by default), 3 Hype (marketing), and a fixed footer
   "Launch cost · you have · left after launch" + a LAUNCH button that never scrolls away.
7. Launch ceremony: replaces playLaunch's "3-2-1 MODEL LIVE". Spotlit stage, INTRODUCING <name>, confetti, a score
   card with the market rank. Tap goes to Market or back to the Lab.

## 2. Studio frame and density

- Host: `container:FindFirstAncestor("Computer")` (the Computer frame covers the whole overlay root; Kit.frame
  defaults to scale 1,1). If it is missing, fall back to `container`. Use ZIndex 30 above the window (ZIndex 11).
  A UISizeConstraint MaxSize of 1760x720 keeps it from stretching on big monitors. Closing the Computer hides it too.
- Density class: multiply the UIScale values of the ancestors (same walk as Computer.designScale).
  compact = scale < 0.62 (phones in landscape: 0.43-0.49), otherwise regular. Rebuild the Studio when the class
  changes (AbsoluteSize signal).
- Size table (design px; pt at 0.432 / px at 0.919):

| token | compact | regular |
|---|---|---|
| caption | 26 (11.2 pt) | 14 |
| body | 30 (13 pt) | 16 |
| option title | 36 (15.6 pt) | 20 |
| step title | 44 (19 pt) | 30 |
| big number | 96-120 (41-52 pt) | 64 |
| button / tile min height | 104 (45 pt) | 52 |
| step chip | 102 tall (44 pt) | 44 |

  The 44 pt / 11 pt mobile minimums are the commonly cited Apple HIG values (from memory, not re-opened).

### Phone landscape (Studio = 1736x720 design px at 0.432)
- Top bar, 110 px:
  - "MODEL STUDIO" (44 px) + "<company> · the company keeps running" (26 px). The clock is shared, so we never claim
    time is paused.
  - Six step chips "1 Goal" .. "6 Review", 150x102 each, all tappable. The current chip uses the accent fill and done
    chips get a check mark.
  - × close at the right (104x104).
- Left column x 24-600 (about 249 pt):
  - COST BADGE (training cost, time, VRAM used/have, your cash). It updates on every tap.
  - MODEL CARD below it.
- Right panel x 624-1712 (about 470 pt), from top to bottom:
  - "STEP n OF 6" + title + a one-line honest hint (120 px);
  - the options area (about 340 px, at most 4-5 options);
  - a nav row of 104 px: [‹ Back 30 %] [Continue › 70 %], or on REVIEW [START TRAINING · $X].
- Nothing primary is below the fold.

### Desktop (Studio = about 1392x720 design px at 0.919)
- Same three zones at regular sizes.
- Tiles gain one extra detail line (VRAM, data fill, per-stat deltas).
- The estimate breakdown "Why this number?" is open by default on desktop and collapsed on the phone.

## 3. Steps (all numbers from real state)

1. GOAL "Who is it for?": four line cards (2x2), each a TextButton whose Text starts with the line's short name.
   - LIVE line: "Nova v2 · fit 58 now (61 − 3 age)".
   - FREE line: "Free line (2 of 3 used)".
   - LOCKED line: "Opens with <office>" (ModelsUI.officeForLines).
   - "Suggested" chip, a documented rule:
     - first choice: the free line with the highest fit for the current settings;
     - otherwise: the live line whose aged fit the new model beats by the most.
   - The pick is kept client-side as plannedLine. It is not sent to the server; Launch Day preselects it if
     releaseCheck allows it.
2. SIZE "How big?": five tiles 100M..7B.
   - Each tile shows: a tier bar (potential 46/57/63/71/83), its expected Overall, a green/red delta chip vs the
     current pick, cost and time.
   - Locked tiles stay visible with the exact reason: "Needs 12 GB VRAM (you have 6)" / "Needs Frontier research".
     Tapping one still selects it (as today) and shows a reason bar with OPEN HARDWARE / OPEN COMPANY.
   - Hint: "Bigger = smarter, but needs more VRAM, data and money, and costs more to serve."
3. SKILLS "What is it good at?": four focus tiles (2x2).
   - Each tile shows the real multipliers ("Coding +18% · Reasoning +4% · Creativity −12% · Knowledge −6%") and
     "<line> fit +5.1" for the picked goal line, from MarketMath.fit on the previewed stats.
4. PLAN "How do you train it?": three rows, Quick pass / Standard / Deep training.
   - UI label "Standard" for recipe steady, so it no longer clashes with focus "Balanced". This is either a
     ModelConfig.RECIPES label text change or a LabApp-only label.
   - Each row shows time, cost and an Overall delta.
   - The Deep row shows the real overfit rule: "Needs ≥ 50 % of the data this size wants and ≥ 60 % quality.
     You have 16B (10.7x) / 81 % ✓", or "✗ → gains drop to x0.85".
5. NAME, Phase A:
   - TextBox (2-20 characters, as GameConfig) + a dice button (NAME_IDEAS) + "Becomes Nova v3" (the versionFor rule).
   - Phase B turns this step into LOOK: colour swatches, emblem and personality, labelled "Looks only — no effect on
     scores or money".
6. REVIEW:
   - Three tiles: TRAINING COST / TIME / CASH LEFT.
   - "Expected 61.6 · final 59.1–64.1 before events; a training event can change it (−10 % to +5 %)".
   - Three comparison lines:
     - vs your best (bestOverall);
     - vs the live model of the goal line ("would replace Nova v2: +6.3 fit after ageing → worth a new version"; the
       ≥ 3 threshold is the casual bot's rule in CORE_SPEC 7.3);
     - "#2 of 6 in Consumer Chat by fit" among marketplace offers of that line (fallback when the marketplace is
       missing: overall vs MarketConfig.NPC_MODELS, as the result view does today).
   - Collapsible "Why this number?":
     - size potential;
     - data fill × quality (ModelMath.readiness);
     - focus multipliers;
     - plan factor;
     - company spec statBonus;
     - research + Lab core bonus (EmpireMath.bonuses(e).core);
     - the 99 cap.
   - The primary button keeps today's blocker labels and actions (NAME NEEDS..., NEEDS n GB MORE VRAM · OPEN COMPUTE,
     NEED TRAINING DATA · OPEN DATA, RESEARCH FRONTIER..., NEED $X).
   - On a server NAME_FILTERED or BAD_NAME, jump back to step 5 and outline the name field.

## 4. Model card (the growing preview), Frames only

- Orb: a circle Frame with UICorner 0.5, a UIGradient in the card colour and a UIAspectRatioConstraint. The diameter
  grows with the size tier (about 180 -> 300 px) and there is one ring (UIStroke) per tier (100M = 1 ... 7B = 5).
- A 12-dot dial around the orb. Positions use cos/sin (no Rotation). In design mode the lit dots show the data fill
  (min(fill, 1)); in training mode they show progress.
- Inside the orb: the company logo glyph. In Phase B it is the chosen emblem.
- Below the orb: name + "v3", chips "1B · Coding · Deep" and "for Developer API".
- Six stat bars (2x3) with the expected values plus a thin white tick at your best model's value for each stat.
- A big Overall number (count-up tween 0.3 s on change).
- A "BEATS YOUR BEST" chip when expected > best.
- Each tap gives a pulse: UIScale 1 -> 1.04 -> 1 over 0.15 s.
- The same component is reused in training, reveal and Launch Day, so the player keeps seeing "their" model.

## 5. Training / reveal / launch layouts

- Training (phone):
  - left: the card (dots = progress, stats dimmed with a moving UIGradient.Offset shimmer; no fake intermediate
    stats) and "~61.6 expected";
  - right: "46 %" (96 px) + ETA; the loss columns (48, from data.training.loss); the last 3 log lines with a
    MaxVisibleGraphemes typewriter; metrics with Compute formatted the same way as the creator (fixes
    "19.200000000000003 u/s"); the quality multiplier.
  - The event card covers the right panel:
    - title (44 px, warn colour) and text;
    - two 150 px choice buttons with the real effects ("+20% remaining time, +15% cost" / "−6% model quality");
    - a 25 s countdown bar from event.expiresAt.
  - Desktop shows 6 log lines.
- Reveal:
  - "TRAINING COMPLETE", or "BENCHMARK REPORT" when opened through EVALUATE (fixes the caption bug).
  - Overall counts from the captured expected value to the actual one, with "+0.8 lucky roll" / "−1.1 unlucky roll"
    (the difference is the noise plus the event; the event chip names the event and the choice from
    training.event.outcome).
  - 8 benchmark bars fill one after another (0.12 s stagger).
  - Badges: NEW COMPANY RECORD (vs payload.previousBest) or "Your first model!", the line rank, and "worth a new
    version of Nova v2".
  - Buttons: LAUNCH (primary, 50 %); REFINE n/3 · $X (pre-checks NEW_DATA, REFINE_LIMIT and TRAINING_ACTIVE and
    shows the reason instead of a server error toast); LATER.
- Launch Day:
  - Left: the card + a 5-minute forecast (Users, Net income/day) + the existing honest caveat line.
  - Right:
    - 1 Line: TextButtons whose Text starts with "Chat"/"Study"/"Dev API"/"Business". Status:
      - "NEW VERSION of Nova v2 · 39K users move (90 %)";
      - "NEW LINE (3 of 3)";
      - "NO FREE LINE".
    - 2 Price: Auto price / Manual. The texts "Recommended: ..." and "Auto price: the server sets the Recommended
      price ..." are kept. Manual uses a −/+ stepper for the API price on the phone instead of the 8 px slider.
    - 3 Hype: chips None $0 / Recommended (PricingMath.recommendedMarketing) / More (the slider).
  - Footer: "Launch cost $5K · you have $186.4K · $181.4K left" + LAUNCH button. The label prefixes are kept:
    LAUNCH <SHORT> / NEW VERSION · <SHORT> / NO FREE PRODUCT LINE / NOT ENOUGH MONEY FOR THIS BUDGET.
- Ceremony, after ReleaseModel ok:
  - a 4-5 s takeover, tap to skip;
  - a dark gradient stage, two beams (Frames + UIGradient, Rotation), a podium ellipse, the card orb pulsing;
  - "INTRODUCING" + the name, and 30 confetti Frames tweened and destroyed;
  - left card LAUNCH DAY: line, the price the server applied (from the ReleaseModel response subPrice/apiPrice/auto)
    and the marketing spent;
  - right card: Overall + rank "#2 of 6 in Study App".
  - Buttons: SEE IT IN MARKET / BACK TO LAB.
  - No sound: no verified asset ids exist, so the owner can add them later.

## 6. Component -> code mapping

- LabApp.module.luau (rewrite of the buildCreator, buildTraining, buildResult and buildRelease bodies; playLaunch
  becomes the ceremony):
  - Keep the public API: mount, onShow, openRelease, openSection('evaluation' | 'release').
  - Add openSection('design'), and LabApp.openStudio(opts) for successor shortcuts.
- New Client/UI/Apps/ModelCard.module.luau: the card component (build(parent, density) -> {set(preview), mode(m)}).
- New Client/UI/Apps/LabStudio.module.luau: the takeover with the step machine and the training/reveal/launch/ceremony
  modes. It contains a small local Stepper and Tile factory built from Kit.button/Kit.frame (Kit has no tabs or stepper).
- New Shared/LabPreview.module.luau (pure, unit-testable): estimate(data, ui), optionDeltas, range, lineCompare,
  rank, nextVersion, deepOk, breakdown. It is built only on ModelMath, EmpireMath, MarketMath, MarketConfig and
  ModelConfig.
- Kit/Theme: no change needed. Optionally Kit.segmented gets a height parameter at call sites (it already exists).
- Bug fixes folded in:
  - u/s formatting;
  - "fill 200 %" -> "Data: full (16B of 1.5B needed)";
  - the truncated ready row;
  - the REFINE pre-check;
  - the EVALUATE caption.

## 7. Server changes

- Phase A: none. Same payloads, same validation. The economy sim is unaffected; the bot calls StartTraining directly.
- Phase B (identity, approve first):
  - StartTraining gets an optional `look = {color = CompanyConfig.COLORS id, emblem = index into CompanyConfig.LOGOS,
    persona = id in a new ModelConfig.PERSONAS}`. It is validated like CompanyService's isLogo/getColor; a bad look
    returns BAD_INPUT.
  - `model.look` is saved; add the Types.ModelData field and a Template.migrate model cleaner (Template.module.luau
    ~387-398) that drops invalid values.
  - PhoneMath.systemPrompt uses PERSONAS[persona].tone instead of TONE[focus] when present. Temperature stays
    focus-based.
  - Amend CORE_SPEC 11.6: the model chat may also read the cosmetic look.persona; still no economic effect.
  - Update tests/phone/test_phone.luau:209-230 and tests/models/test_models.luau.
  - Check the net budget (tests/net/test_e2e.luau ≤ 15 KB/s; about 40 bytes per model).
  - Market and Lab Home shelves then show the colour and emblem.
- Optional S3: save recipeId on the model and in data.training. This is display only ("Deep" on the shelf, the plan
  factor in the montage after a rejoin).
- Recommended S4: add `expected = training.expected` and `eventId/outcome` to the TRAINING_COMPLETE payload so the
  reveal's lucky/unlucky roll does not depend on the client having seen the last training snapshot. For a refinement,
  show "+x from refinement" and no "roll".

## 8. Tests / verification plan

- test_ui.luau keeps passing if the strings and button prefixes listed in sections 1 and 5 are kept. Lab level text
  moves from the estimate card to the Lab level card on Lab Home.
- New checks:
  - the Studio opens/closes;
  - chip 6 jumps to Review;
  - the Review "Expected" equals the server's data.training.expected right after StartTraining (honesty guard);
  - a locked 7B tile shows "Needs Frontier research";
  - REFINE is disabled with a NEW_DATA reason;
  - the release flow uses the same prefixes.
- guiprev: add view=studio step=1..6, view=training, view=result and view=launch to tests/models/scene_models.luau,
  rendered with --viewport phone and desktop. Tweens and Rotation are not rendered, so the previews show end states only.
- Not possible here: a real-device test (Roblox iPhone) and a gamepad test (set GuiService.SelectedObject to Continue
  on open when UserInputService.GamepadEnabled; ButtonB = Back via ContextActionService). Both stay "not run" until a
  Studio/device session.

## 9. Risks

- The first model now takes 6 screens instead of 1 tap. Mitigation: defaults are preselected, chip 6 jumps to Review,
  and "Same again". Human time to the first $ grows by about 20-40 s (ASSUMPTION, not measured). The bot timing in
  CORE_SPEC 1.2 is unchanged.
- The takeover depends on the Computer frame's Name "Computer". A fallback to the content container is planned.
- Toasts (top centre, DisplayOrder 30) can cover the Studio top bar. Toast has no mute; accept this or add one later.
- Launch Day forecasts: one PricingMath.profit per change exists today. Hype chips must not add 3 synchronous
  forecasts per refresh; compute only the selected one, or one per frame.
- Refresh cost: 12 extra computeStats calls + MarketMath.fit over at most about 50 offers per refresh. This is cheap,
  but only refresh while the Studio is visible.
- Identity (Phase B) touches save + phone chat + CORE_SPEC 11.6. Do not ship persona without those.
- Research caveat: Build a Phone Empire was created on 2026-09-22. Four of its 13 steps come only from a fan site.
  Its "time is paused" and pay-to-win passes are not copied.
