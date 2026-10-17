# Lab package (Model Studio): balance guard, before / after

Date 2026-10-10, fix round 1 on 2026-10-11 (section 6). Spec: design/LAB_SPEC.md section 8 (balance guard) and 8.1
(UI-defaults economy re-check).

## 1. What changed in game rules: nothing

The Model Studio adds **no** new stat, cost, training-time or quality rule. ModelConfig, PricingMath, EmpireMath,
MarketMath, MarketConfig, PricingService, MarketService, Template and Types are byte-identical to the baseline
(agents/stable/snap_1655). Server edits of the package:

| file | change | balance effect |
|---|---|---|
| ModelMath | `nextVersion` moved here from AIModelService (same code), new `parseLook` (cosmetic validator) | none |
| AIModelService | uses `ModelMath.nextVersion`; TRAINING_COMPLETE payload + `expected/refinement/before/eventId/outcome` (display only); StartTraining accepts optional `look` / `target` (BAD_INPUT when invalid, before any other check) and stores `model.look`, `model.plan`, `model.recipeId` | none (the economy bot never sends the new fields; old payloads behave exactly as before) |

Every number the Studio shows comes from `UI/Lab/LabPreview` = the server pipeline of `AIModelService.startTraining`
(ModelMath.plan / computeStats / recipeFactor, EmpireMath.boostStats / trainingRate, ModelMath.capStats).

## 2. Proof that the Studio shows today's numbers (tests/lab/test_labpreview.luau)

- Honesty: for 4 states (rich, starter garage, stage-5 hq, fresh) x 5 sizes x 3 plans x 4 focuses = 240 choices,
  `LabPreview.estimate` equals (a) the old LabApp creator formula and (b) the real `StartTraining` handler
  (`training.expected`, `trainCost`, work, seconds); every refused choice shows the server's error code as its lock.
- Recommended path = today's verified path: the first model the Studio opens with (100M, Standard, Creative for
  Consumer Chat, data plan 2x Web Crawl Chunk + 2x Public Repos = $7,400) is exactly the casual bot's start that
  CORE_SPEC's targets were measured on: `dataPlan` == the bot's `planData` (spent, packs, expected), then expected
  40.2, cost $1,280, 80 s, cash $4,800 (checked through the real BuyData and StartTraining handlers).
- Recommended launch = unchanged rules: Recommended price via `PricingMath` slicer, marketing via
  `PricingMath.recommendedMarketing` (<= $5,000 above the reserve), auto price on.
- Negative checks (tests/lab/negative.sh, 28 of 28 detected): e.g. "estimate ignores the training plan factor",
  "estimate skips the research/Lab boost", "data plan stops later than the bot", "best I can afford ignores the
  reserve", "successor falls back to BEST I CAN AFFORD" all make the suite fail.

## 3. Simulator before / after (same work/src except this package)

`agents/lab/run_sims.sh before|after` (CORE_SPEC 9.4 casual set + main runs, 180 min each;
`sim_before.luau` on `src_before`, `sim.luau` on work/src). Outputs in agents/lab/out/sim_before, sim_after.

| run | stages before | stages after | rev/min 10 / 120 before | after | lowest cash before / after | identical |
|---|---|---|---|---|---|---|
| main_casual | 7.5 / 34.7 / 83.0 / 168.8 | 7.5 / 34.7 / 83.0 / 168.8 | 9,100 / 80,773 | 9,100 / 80,773 | 1,776 / 1,776 | yes (byte-identical) |
| casual_s4242_h8.6 | 10.2 / 34.2 / 86.3 / 173.0 | 10.2 / 34.2 / 86.3 / 173.0 | 6,903 / 75,990 | 6,903 / 75,990 | 1,535 / 1,535 | yes (byte-identical) |
| casual_s4242_h12 | 10.6 / 32.1 / 92.4 / 175.0 | 10.6 / 32.1 / 92.4 / 175.0 | 7,673 / 86,702 | 7,673 / 86,702 | 1,583 / 1,583 | yes (byte-identical) |
| casual_s7 | 9.4 / 25.1 / 76.9 / 164.4 | 9.4 / 25.1 / 76.9 / 164.4 | 8,143 / 78,961 | 8,143 / 78,961 | 1,659 / 1,659 | yes (byte-identical) |
| casual_s7_h8.6 | 10.2 / 24.6 / 76.1 / 166.1 | 10.2 / 24.6 / 76.1 / 166.1 | 7,115 / 76,155 | 7,115 / 76,155 | 1,549 / 1,549 | yes (byte-identical) |
| casual_s7_h12 | 10.9 / 32.0 / 96.1 / 166.6 | 10.9 / 32.0 / 96.1 / 166.6 | 7,524 / 87,765 | 7,524 / 87,765 | 1,533 / 1,533 | yes (byte-identical) |
| casual_s11 | 8.2 / 34.2 / 83.1 / 172.9 | 8.2 / 34.2 / 83.1 / 172.9 | 8,992 / 75,906 | 8,992 / 75,906 | 1,529 / 1,529 | yes (byte-identical) |
| casual_s11_h8.6 | 10.5 / 37.0 / 86.2 / 166.6 | 10.5 / 37.0 / 86.2 / 166.6 | 6,876 / 79,023 | 6,876 / 79,023 | 1,607 / 1,607 | yes (byte-identical) |
| casual_s11_h12 | 10.9 / 25.1 / 78.2 / 168.0 | 10.9 / 25.1 / 78.2 / 168.0 | 7,546 / 90,905 | 7,546 / 90,905 | 1,635 / 1,635 | yes (byte-identical) |
| casual_s23 | 9.5 / 23.9 / 90.2 / 164.8 | 9.5 / 23.9 / 90.2 / 164.8 | 7,807 / 75,679 | 7,807 / 75,679 | 1,515 / 1,515 | yes (byte-identical) |
| casual_s23_h8.6 | 10.4 / 31.4 / 77.7 / 165.3 | 10.4 / 31.4 / 77.7 / 165.3 | 6,951 / 73,937 | 6,951 / 73,937 | 1,528 / 1,528 | yes (byte-identical) |
| casual_s23_h12 | 10.7 / 29.5 / 81.4 / 163.5 | 10.7 / 29.5 / 81.4 / 163.5 | 7,740 / 91,925 | 7,740 / 91,925 | 1,531 / 1,531 | yes (byte-identical) |
| main_opt | 7.1 / 28.4 / 64.4 / 129.9 | 7.1 / 28.4 / 64.4 / 129.9 | 8,838 / 93,788 | 8,838 / 93,788 | 1,589 / 1,589 | yes (byte-identical) |

Stages = minutes of the moves to Founder HQ / Startup Campus / Innovation Campus / Global HQ. All 13 outputs are
byte-identical: the server rules did not move. (The lab's server files were last edited at 17:06; the after run
started 17:58.)

## 4. LAB_SPEC 8.1: does a player who follows the Studio's suggestions keep CORE_SPEC's targets?

`agents/lab/sim.luau --ui-defaults` = the casual bot, but its training choice, data purchases and launch line come
from the Studio (`LabPreview`): first model = the Studio's first-model plan, data = `LabPreview.dataPlan`, the
launch line = the planned line, price/marketing unchanged. Pass rule per run (LAB_SPEC 8.1 step 3): Founder HQ in
7.5-10.9 min, Startup Campus / Innovation / Global HQ each <= +10 % later than the same run without the flag,
$/min at 10 and 120 min >= -10 %, lowest cash >= $0.

### Variant A (BEST I CAN AFFORD preselected): FAILED (kept for the record)
`run_sims.sh uibest` -> out/sim_uibest, table out/table_ui_bestaffordable.md: 10 of 12 pass; casual_s7_h8.6
(Startup Campus 24.6 -> 30.7 min) and casual_s23 (23.9 -> 30.7 min) move the Campus more than 10 % later
(spending on the best affordable model delays the office move). Per LAB_SPEC 8.1 step 4: BEST I CAN AFFORD stays a
visible preset but is **never preselected**, and every successor suggestion (Lab home SUCCESSOR tile, the SUCCESSOR
buttons of the product lines, "DESIGN ITS SUCCESSOR" after a launch) uses the bot's rule
(`LabPreview.successorPick`: largest size the servers carry and the cash above the reserve pays for, after its data
plan >= the line's current model + 3, Deep only when the data is enough and the rest of the cash pays).

### Variant B (shipped): ALL 12 PASS
`run_sims.sh ui` -> out/sim_ui (200 min each). "after" = the run without the flag, "ui" = with it.

| run | Founder HQ (7.5-10.9) | Startup Campus | Innovation | Global HQ | rev/min 10 | rev/min 120 | lowest cash | pass |
|---|---|---|---|---|---|---|---|---|
| main_casual | 7.5 -> 7.5 | 34.7 -> 34.7 | 83.0 -> 83.0 | 168.8 -> 167.8 | 9,100 -> 9,100 | 80,773 -> 80,796 | 1,776 -> 1,776 | pass |
| casual_s4242_h8.6 | 10.2 -> 10.2 | 34.2 -> 34.2 | 86.3 -> 86.3 | 173.0 -> 173.0 | 6,903 -> 6,903 | 75,990 -> 75,625 | 1,535 -> 1,535 | pass |
| casual_s4242_h12 | 10.6 -> 10.6 | 32.1 -> 32.1 | 92.4 -> 92.4 | 175.0 -> 172.7 | 7,673 -> 7,673 | 86,702 -> 87,912 | 1,583 -> 1,583 | pass |
| casual_s7 | 9.4 -> 9.4 | 25.1 -> 25.1 | 76.9 -> 76.9 | 164.4 -> 162.7 | 8,143 -> 8,143 | 78,961 -> 79,192 | 1,659 -> 1,659 | pass |
| casual_s7_h8.6 | 10.2 -> 10.2 | 24.6 -> 24.6 | 76.1 -> 76.1 | 166.1 -> 166.0 | 7,115 -> 7,115 | 76,155 -> 76,126 | 1,549 -> 1,549 | pass |
| casual_s7_h12 | 10.9 -> 10.9 | 32.0 -> 32.0 | 96.1 -> 96.1 | 166.6 -> 166.2 | 7,524 -> 7,524 | 87,765 -> 87,595 | 1,533 -> 1,533 | pass |
| casual_s11 | 8.2 -> 8.2 | 34.2 -> 34.2 | 83.1 -> 83.1 | 172.9 -> 173.7 | 8,992 -> 8,992 | 75,906 -> 76,280 | 1,529 -> 1,529 | pass |
| casual_s11_h8.6 | 10.5 -> 10.5 | 37.0 -> 37.0 | 86.2 -> 86.2 | 166.6 -> 169.6 | 6,876 -> 6,876 | 79,023 -> 79,465 | 1,607 -> 1,607 | pass |
| casual_s11_h12 | 10.9 -> 10.9 | 25.1 -> 25.1 | 78.2 -> 78.2 | 168.0 -> 160.8 | 7,546 -> 7,546 | 90,905 -> 90,158 | 1,635 -> 1,635 | pass |
| casual_s23 | 9.5 -> 9.5 | 23.9 -> 23.9 | 90.2 -> 90.2 | 164.8 -> 164.7 | 7,807 -> 7,807 | 75,679 -> 75,757 | 1,515 -> 1,515 | pass |
| casual_s23_h8.6 | 10.4 -> 10.4 | 31.4 -> 31.4 | 77.7 -> 77.7 | 165.3 -> 163.0 | 6,951 -> 6,951 | 73,937 -> 78,260 | 1,528 -> 1,528 | pass |
| casual_s23_h12 | 10.7 -> 10.7 | 29.5 -> 29.5 | 81.4 -> 81.4 | 163.5 -> 162.8 | 7,740 -> 7,740 | 91,925 -> 91,544 | 1,531 -> 1,531 | pass |

First model in both runs (e.g. casual_s11): "train Nova1 s100m steady ... exp 40.2 cost 1280 data 4B q0.42",
released "s100m creative ov 40.8" - the Studio's first-model plan is the bot's path to the number.
Largest drift: Global HQ -7.2 min (casual_s11_h12, earlier) / +3.0 min (casual_s11_h8.6, +1.8 %); every earlier
stage is identical. Lowest cash unchanged in every run (>= $1,515; CORE_SPEC casual minimum $1,521 applies to the
CORE_SPEC run set, the values here are the same with and without the flag).

Not covered by the simulator: humans act slower than once per second, may pick BEST I CAN AFFORD by hand (a visible
preset that keeps the reserve and the Save-mode cap), and may buy more data through "+ DATA".

## 5. Suites (before -> after, build round)
`RUNALL_TAG=lab tests/lead/run_all.sh`: before the package (agents/lab/out/runall_before.txt) and after
(agents/lab/out/runall_final.txt, 2026-10-10 evening): 99 of 99 suites rc=0, 233,105 checks passed, 0 failed.
Economy-relevant suites, before -> after (the after counts include tests other packages added meanwhile):
econ_ops 173 -> 173, econ_b2b 61 -> 61, econ_service 83 -> 92, econ_migration 89 -> 95, econ_net 18 -> 18,
corefix 52 -> 55, corefix_ui 8 -> 8, models (test_models + test_ui empty/rich/full) all green before and after,
net 90, net_e2e 9 (snapshot budget unchanged by the package).
Lab suites (`bash tests/lab/run.sh`): lab_preview 95/0, lab_studio 108/0, models_ui_empty 17/0, models_ui_rich 38/0,
models_ui_full 42/0. Mutation proof (`bash tests/lab/negative.sh`): 28 of 28 mutations detected.

## 6. Fix round 1 (2026-10-11): the bot buys only what the UI offers

Review finding (blocking): the successor suggestion assumed a data plan that the 2-tap path SUCCESSOR -> START never
bought (the Review offered a plan only on a save without data). Re-run by the reviewer with the plan NOT bought:
0 of 12 runs passed (Startup Campus 58.8-69.8 min, rev/min at 10 down 21-44 %, the same ~44 model retrained).

Fix (UI only, no rule changed; server files untouched in this round):
- `LabPreview.suggest` (Lab home tile, now "SUGGESTED") = the economy bot's line rule (a free product line first in the
  bot's order, else the weakest live line), its focus, and `successorPick` (size, plan, data plan). `lineSuccessor`
  (a line's SUCCESSOR button, "Design its successor") = the same for one line. `prefillOf` hands the data plan to the
  Studio: the Review then shows "Data plan: <packs> · $X", a DATA PLAN ON/OFF tile, and its primary button is
  BUY DATA PLAN · $X, then START (exactly like the first model). Expected / fit / deltas of every step use the data
  after the plan. OFF trains on today's data with honest numbers (tested).
- Proof that what ships = what was simulated: tests/lab/test_studio.luau section 14 A runs 7 flows through the real
  UI and server handlers (SUGGESTED tile in rich and full at 25 % and 12 % data, a line's SUCCESSOR button, NOW LIVE
  "Design its successor"): the Review shows the tile's ~X, BUY DATA PLAN buys exactly the plan's packs (a double tap
  buys it once), and START's `training.expected` equals the tile's promise. test_labpreview section 9:
  `suggest` = the bot's line choice and gate base in 48 states (3 saves x 4 age mixes x 4 cash levels).
- `agents/lab/sim.luau --ui-defaults` now plays exactly what the UI offers: every model after the first is what the
  SUGGESTED tile opens (`LabPreview.suggest`), and the only data it buys is the plan that Review offers
  (`suggest(...).pick.plan`, bought before START); no suggestion = no training. The first model is the Studio's
  first-model plan (unchanged). A counter logs every time the tile's line differs from the bot's line rule.

`OUTDIR=sim_ui_fix1 agents/lab/run_sims.sh ui` (12 casual runs, 200 min) -> agents/lab/out/sim_ui_fix1,
`python3 agents/lab/tools/simtable.py ui sim_ui_fix1`. "after" = the same run without the flag (sim_after):

| run | Founder HQ (7.5-10.9) | Startup Campus | Innovation | Global HQ | rev/min 10 | rev/min 120 | lowest cash | pass |
|---|---|---|---|---|---|---|---|---|
| main_casual | 7.5 -> 7.5 | 34.7 -> 34.7 | 83.0 -> 83.0 | 168.8 -> 167.8 | 9,100 -> 9,100 | 80,773 -> 80,796 | 1,776 -> 1,776 | pass |
| casual_s4242_h8.6 | 10.2 -> 10.2 | 34.2 -> 34.2 | 86.3 -> 86.3 | 173.0 -> 173.0 | 6,903 -> 6,903 | 75,990 -> 75,625 | 1,535 -> 1,535 | pass |
| casual_s4242_h12 | 10.6 -> 10.6 | 32.1 -> 32.1 | 92.4 -> 92.4 | 175.0 -> 172.7 | 7,673 -> 7,673 | 86,702 -> 87,912 | 1,583 -> 1,583 | pass |
| casual_s7 | 9.4 -> 9.4 | 25.1 -> 25.1 | 76.9 -> 76.9 | 164.4 -> 162.7 | 8,143 -> 8,143 | 78,961 -> 79,192 | 1,659 -> 1,659 | pass |
| casual_s7_h8.6 | 10.2 -> 10.2 | 24.6 -> 24.6 | 76.1 -> 76.1 | 166.1 -> 166.0 | 7,115 -> 7,115 | 76,155 -> 76,126 | 1,549 -> 1,549 | pass |
| casual_s7_h12 | 10.9 -> 10.9 | 32.0 -> 32.0 | 96.1 -> 96.1 | 166.6 -> 166.2 | 7,524 -> 7,524 | 87,765 -> 87,595 | 1,533 -> 1,533 | pass |
| casual_s11 | 8.2 -> 8.2 | 34.2 -> 34.2 | 83.1 -> 83.1 | 172.9 -> 173.7 | 8,992 -> 8,992 | 75,906 -> 76,280 | 1,529 -> 1,529 | pass |
| casual_s11_h8.6 | 10.5 -> 10.5 | 37.0 -> 37.0 | 86.2 -> 86.2 | 166.6 -> 169.6 | 6,876 -> 6,876 | 79,023 -> 79,465 | 1,607 -> 1,607 | pass |
| casual_s11_h12 | 10.9 -> 10.9 | 25.1 -> 25.1 | 78.2 -> 78.2 | 168.0 -> 160.8 | 7,546 -> 7,546 | 90,905 -> 90,158 | 1,635 -> 1,635 | pass |
| casual_s23 | 9.5 -> 9.5 | 23.9 -> 23.9 | 90.2 -> 90.2 | 164.8 -> 164.7 | 7,807 -> 7,807 | 75,679 -> 75,757 | 1,515 -> 1,515 | pass |
| casual_s23_h8.6 | 10.4 -> 10.4 | 31.4 -> 31.4 | 77.7 -> 77.7 | 165.3 -> 163.0 | 6,951 -> 6,951 | 73,937 -> 78,260 | 1,528 -> 1,528 | pass |
| casual_s23_h12 | 10.7 -> 10.7 | 29.5 -> 29.5 | 81.4 -> 81.4 | 163.5 -> 162.8 | 7,740 -> 7,740 | 91,925 -> 91,544 | 1,531 -> 1,531 | pass |

**ALL 12 PASS.** Every output is byte-identical to the build's variant B (out/sim_ui) except the new line
"ui suggest vs bot line rule: 0 mismatches": the SUGGESTED tile picks the bot's line in every decision of every run,
and the plan the Review offers is the plan variant B bought. Data spend $30,700-36,000 per run, 48-58 trainings
(UI path) in 200 min (the reviewer's no-plan path: $7,400 and 76-92 trainings). CORE_SPEC targets: Founder HQ
7.5-10.9 min, lowest cash >= $1,515, Startup Campus / Innovation / Global HQ never later than without the flag.

Limits (stated): the simulator acts every second (humans are slower); DESIGN NEW MODEL for a returning player prefills
the LAST selection, not a suggestion, and is not simulated (the Review then warns: "only +x over <live model>" when the
gain is below +3, and "Leaves $X: below your $1,500 safety reserve" in the warn colour); BEST I CAN AFFORD (variant A,
a visible preset, never preselected) and "+ DATA" by hand are not simulated. The data plan can be switched OFF on the
Review (honest lower numbers are shown before START).

Suites after fix round 1: `bash tests/lab/run.sh` -> lab_preview 110/0, lab_studio 206/0, models_ui_empty 17/0,
models_ui_rich 38/0, models_ui_full 42/0; `bash tests/lab/negative.sh` -> 45 of 45 mutations detected (17 new ones
for this round, e.g. "suggestion prefill drops its data plan", "BUY DATA PLAN re-enabled before the snapshot",
"suggest skips the free product line", "ceiling = the size's raw potential"). run_all: see the final report.
