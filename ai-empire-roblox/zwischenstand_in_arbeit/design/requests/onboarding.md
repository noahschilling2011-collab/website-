# Requests from package "menu" (ONBOARDING_SPEC A + B: "First steps" guide, Menu shell, Home)

Date: 2026-10-12. The menu package could not edit these files because round 2b owns them (drivers / guests_jet /
itinerary). Everything works without them: each item names its fallback. Line numbers are from `work/src` today;
search for the quoted text instead.

Public API of the menu package used below: `ReplicatedStorage/Shared/TutorialMath` (`TutorialMath.active(data)`:
company exists and the guide is neither done nor skipped).

## 1. itinerary / owner of AssistantService - no greeting toast while the guide runs (ONBOARDING_SPEC A4)
`ServerScriptService/Server/Services/AssistantService.module.luau`, `local function proactive(rec, now)` (l.681):
the greeting block `if not greeted[s] and level==Plan.founderLevel(rec.tier) then ... notify(s, rec.name..": "..hello..", " ...`
should be skipped while the guide is active (the guide card already speaks for the assistant; a second toast at the top
centre competes with the first instruction). Add near the requires:
```lua
local TutorialMath=require(ReplicatedStorage.Shared.TutorialMath)
```
and change the condition to
```lua
 if not greeted[s] and level==Plan.founderLevel(rec.tier) and not TutorialMath.active(s.data) then
```
The training-decision reminder below it stays as it is. Fallback today: the greeting toast can show during step 1.
STATUS: blocked (itinerary): the one-line guard breaks people_harness/test_people.luau "greets once on the founder floor" /
"greeting not repeated" (its newSession uses Template.new(), so the guide is active for that stage-3 fixture company and the
greeting is skipped - run_all people rc=1). Lead / owner of people_harness: set `gs.data.empire.tutorial = {done = true}` in
that fixture (or expect no greeting while the guide runs); then the change above can land as written. Fallback stays: the
greeting toast can show during step 1.

## 2. itinerary / owner of AssistantService - one name per place (ONBOARDING_SPEC B7)
Same file, text only (the Menu has no "Company", "Models" or "Hardware" any more; `Computer.route` still opens the right
page for every old app id, so only the words are stale):
| line | today | new |
|---|---|---|
| 233 | `... (level %d / %d, %s) in Hardware` | `... (level %d / %d, %s) in Lab → GPUs` |
| 246 | `buy GPUs in Hardware: one more %s serves %s more users` | `buy GPUs in Lab → GPUs: one more %s serves %s more users` |
| 247 | `business clients reserve your compute right now: buy GPUs in Hardware` | `... buy GPUs in Lab → GPUs` |
| 256 | `: buy GPUs in Hardware or pick a smaller size (` | `: buy GPUs in Lab → GPUs or pick a smaller size (` |
| 281 | `... + %s in Models.` | `... + %s in Lab → Models.` |
| 504 | `"Automatic hiring is on (Company → Settings)"` / `"Automatic hiring is off: hire in Company → Team"` | `"Automatic hiring is on (Team → Settings)"` / `"Automatic hiring is off: hire in Team → Staff"` |
| 516 | `raise prices in Models, lower the HR budget or pause HR in Company → Settings.` | `raise prices in Market → My AIs, lower the HR budget or pause HR in Team → Settings.` |
Check `tests/apps/test_server.luau` / `tests/apps/test_adv.luau` for these strings before changing them (none matched a
grep for "in Hardware", "in Models" or "Company →" on 2026-10-12).
STATUS: done by itinerary (all rows of the table changed; also "Lab level x / y in Models" -> "in Lab → Models"; tests/apps suites unchanged and green in run_all)

## 3. phone / owner of PhoneMath - office message (ONBOARDING_SPEC B7)
`ReplicatedStorage/Shared/PhoneMath.module.luau` l.643:
`"... and a safety reserve. Open Company → Office when you want to move."` →
`"... and a safety reserve. Open Team → Office when you want to move."`

## 4. phone / owner of PhoneScreens - deep-link labels (ONBOARDING_SPEC B7)
`StarterPlayer/StarterPlayerScripts/Client/UI/Phone/PhoneScreens.module.luau`:
| line | today | new |
|---|---|---|
| 914 | `Kit.button(list, "Open Company → Money", ...)` | `"Open Home → Money"` |
| 918 | `"The same numbers as Company → Money: today's ledger ..."` | `"The same numbers as Home → Money: today's ledger ..."` |
| 969 | `"Nobody hired yet: hire your first specialists in Company → Team."` | `"... in Team → Staff."` |
| 982 | `Kit.button(list, "Open Company → Team", ...)` | `"Open Team"` |
The buttons keep calling `Computer.open("empire", "money")` / `("empire", "team")`: the Menu routes them to Home → Money and
Team → Staff (route table B9, tested in `tests/menu/test_client.luau`).

## 5. shop package (next) / lab files - Studio button text (ONBOARDING_SPEC B7)  [DONE by the shop package, 2026-10-12]
`UI/Lab/DesignSteps.module.luau`: the lock action "OPEN COMPUTE" → "OPEN GPUs" (the Menu calls the page Lab → GPUs).
The shop package edits DesignSteps for SHOP_SPEC 5.2.4 anyway; `nav.show("compute")` keeps working (route table).

---------------------------------------------------------------------------------------------------------------------
# Requests from package "shop" (SHOP_SPEC phases 1 + 2, round 3)

Date: 2026-10-12. The shop package needed **no change in a round-2b file** (AssistantService, PhoneService, Phone UI,
Shuttle/City/Driver/Jet/Vehicle/Itinerary/Guest files are untouched). Menu request #5 above is done
(`UI/Lab/DesignSteps.module.luau`: "OPEN GPUs ›").

## 6. lead / `tests/lead/run_all.sh` - add the shop package suites (round 3)
After the two existing lines `run shop ...` / `run shop_client ...` (search `run shop_client`), add:
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_shop2 >/dev/null
python3 tests/shop2/spec_texts.py design/SHOP_SPEC.md work/src tests/shop2/.spec_texts.luau >/dev/null
for t in server math client; do run "shop2_$t" bash -c "cd tests/shop2 && ../../tools/luau test_$t.luau -a .gen_shop2"; done
```
(about 25 s together; not added by the shop package to avoid editing run_all.sh while round 2b may append to it.)
Optional, slower: `bash tests/shop2/negative.sh` (29 mutations: 28 suite + 1 geometry, ~6 min) and
`tests/shop2/render.sh` + `python3 tests/shop2/sizes.py out/shop/*.dump` (70 previews, ~8 min). Shortcut for all of it:
`bash tests/shop2/run.sh --negative --render --sizes`.

## 7. Info for the lab package (no action): shop edits in lab files
- `UI/Lab/DesignSteps.module.luau`: step-2 / step-6 lock strip (`LockStrip`: OPEN RESEARCH ›, OPEN GPUs ›, SKIP RESEARCH ·
  EUREKA) while the picked size is locked by FRONTIER; review primary "OPEN RESEARCH › FRONTIER ARCHITECTURE"; look
  picker rows scroll horizontally and show the 8 Identity Kit colours / 6 Kit logos (lock badge, no buy button);
  locked size tiles draw their lines 4-8 px higher (T18: "research" ends >= 4 px above the border); compound lock hints
  are shorter ("7B needs Frontier Architecture + 128 GB VRAM (have 102)") so they fit one phone line.
- `UI/Lab/Stages.module.luau`: FINISH NOW · LAST EPOCH in the training view's bottom bar (replaces the "Runs on the
  server" label only while the offer shows); Stage Lights sweeps + gold card stroke on the reveal (pass owners); the
  `paid` line under the ETA wraps to 2 lines (56 px box) instead of ending in "…" ("Last Epoch saves 0:17" did not fit
  the desktop column, 2026-10-17).
- `UI/Apps/LabApp.module.luau`: Lab level card button row (UPGRADE LAB + LEVEL UP · EUREKA) and its note. The hero
  TRAINING tile stays one tap target (opens the training view, which carries the Last Epoch button).
- `UI/Lab/StudioParts.module.luau`: `Parts.emblem` draws Kit logos 9-14. `tests/lab/test_labpreview.luau`: parseLook now
  accepts emblem 9 (a Kit logo) and rejects 15 (commented).

## 8. Info for round 2b / itinerary (no action): `tests/itinerary/common.luau` restored (2026-10-17)
The shop package's first attempt (2026-10-12 06:56) had added a 5-line no-op guard for `ShopService.setRedeemHandler`
to `tests/itinerary/common.luau` (a round-2b file). It is removed again, so the file is the itinerary package's own
version. Instead `EmpireService.init` registers the Eureka handler only when the ShopService it gets has the hook
(`if typeof((ShopService :: any).setRedeemHandler) == "function"`), so the world test double `tests/world/stubs.luau`
works unchanged. Proof on 2026-10-17 09:2x (private gen `.gen_shop2_itin`): itinerary_math 223/0, service abroad 91/0,
jet 34/0, region 21/0, offer 33/0, edge 41/0, remote 29/0; itinerary_client 55/1 - the one failure is
"offer buttons Go / Not now", because round 2b's running itinerary fix changed `ItineraryMath.BUTTON_TEXT.decline` to
"Not this time" (09:18) while `tests/itinerary/test_client.luau:87` still expects "Not now"; no shop file is involved.
Re-checked on the final tree (2026-10-17, after round 2b's fix): `bash tests/itinerary/run.sh` 726 passed, 0 failed.
