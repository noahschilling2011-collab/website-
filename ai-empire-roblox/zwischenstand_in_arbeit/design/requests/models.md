# Requests from package "models" (AI models: lines, versions, ageing, refinement, pricing + Lab/Market UI)

The models package owns AIModelService, ModelMath, ModelConfig, the new shared `ReplicatedStorage/Shared/PricingMath`,
the new server `Services/PricingService`, LabApp, MarketApp and the new client helper `UI/Apps/ModelsUI`. Everything below is in files owned by the
**econ** package (or nobody listed). The models code already works around each item (guarded reads, `:: any`),
so none of them blocks the other package; they make both halves fit exactly.

## 1. MarketService.tickGlobal — richer marketplace offers (econ)
In the `table.insert(offers,{...})` row (today ~:105) add three fields:
```lua
target = m.release.target, npc = s.isNPC == true, vage = m.market.vage,
```
Why: CORE_SPEC 7.7 — the Lab release forecast and the Recommended price on the client must see rivals the way
`MarketMath.tick` does (line penalty needs `target`, the rival-player weight needs the NPC flag, ageing needs
`vage`). Without them the client forecast falls back to: NPC = `providerId < 0`, no line penalty, no ageing
(the server-side price is exact either way, it reads sessions directly).

STATUS (checked by models, 2026-10-04): partly done by econ: offers carry `target` and `npc`. Still open: `vage = m.market.vage` (the client forecast treats rival models as brand new until then; the server price is exact).
STATUS: done by econ

## 2. EmpireAction "autoPrice" handler (econ, EmpireService)
`{action = "autoPrice", model = <id>, on = <bool>}` — please delegate to the models helper so the rule lives in
one place:
```lua
return require(script.Parent.AIModelService).setAutoPrice(session, payload.model, payload.on == true)
```
`setAutoPrice` validates (live model of this session, boolean), sets `model.release.auto`, and when switched on
re-prices on the next tick. It returns `{ok=true}` or `{ok=false, err="BAD_MODEL"|"BAD_INPUT"}`.
(Until EmpireAction exists the Market app falls back to `UpdatePricing {modelId, auto = true|false}`, which
the models package accepts.)

STATUS (checked by models, 2026-10-04): econ handler exists but reads `p.modelId` (CORE_SPEC/task text says `model`) and sets the flag on any model with a release (also retired ones). Still open: accept `p.model or p.modelId` and delegate to `AIModelService.setAutoPrice` (live check). Workaround in place: the Market app sends both `model` and `modelId`; PricingService notices a flag flipped to on at the next tick and re-prices, so the switch works today.
STATUS: done by econ

## 3. EmpireMath (econ) — confirm two CORE_SPEC patches the models code relies on
- `bonuses(e).core` includes `+ (tonumber(e.labLevel) or 0)` (patch EM `core = ...`): Lab levels reach new models
  only through `EmpireMath.boostStats`. AIModelService does NOT add Lab levels again.
- `boostStats` caps every core stat at 99 (AIModelService additionally applies `ModelMath.capStats` after it,
  so the cap holds even before the patch).

STATUS: done by econ (verified by tests/models: Lab level 3 = +3 on every core stat; every core stat <= 99).

## 4. A shared Lab-level price (econ, CompanyOps)
Please export `function Ops.labCost(level: number): (number, number)` returning
`math.floor(200 * 1.35 ^ level), math.floor(6000 * 1.6 ^ level)` (points, dollars) and use it in
`EmpireService.labLevel`. LabApp shows "Lab level L/10 · next: X RP + $Y" from it; until it exists LabApp uses
the same CORE_SPEC 7.5 formula as a fallback.

STATUS (checked by models, 2026-10-04): econ put `Empire.labCost` in EmpireService (server only). Still open: export it from CompanyOps so the client reads the same function; LabApp uses the identical CORE_SPEC 7.5 formula meanwhile (tests/models/test_ui checks 364 RP + $15.4K at level 2 and the server charge).
STATUS: done by econ

## 5. ActionController error texts (econ, client)
```lua
LINE_LIMIT = "All product lines of this office are taken. Release a new version into a live line, or move to a bigger office for another line.",
REFINE_LIMIT = "This model was already refined 3 times. Train a new version instead.",
MODEL_LIMIT = "Your company reached the limit of 80 active models. Retire old models first.",
MAX_LEVEL = "The Lab is at its highest level.",
```
(LabApp/MarketApp show the same texts themselves when ActionController has none.)

STATUS: done by econ (LINE_LIMIT, REFINE_LIMIT, MODEL_LIMIT, MAX_LEVEL present).

## 6. Types.module.luau (owner: econ or lead) — optional typing only
`MarketState.vage: number?`, `ReleaseConfig.auto: boolean?`, `ModelData.replacedBy: string?`,
`LiveInfo.capacity/waitlist/load: number?`, `LiveInfo.pricing: any?` (models writes
`live.pricing[modelId] = {note = string, at = number}` only when auto-price changes a price). The models code
uses `:: any` casts meanwhile.

STATUS: done (vage, auto, replacedBy, trainings, capacity/waitlist/load, pricing present).
STATUS: done by econ

## 7. Template cleaners (econ) — as CORE_SPEC Appendix A, nothing extra
`model.market.vage` (old live: = age), `model.replacedBy` (valid id or nil), `model.release.auto` (default true),
`data.trainings` ({} with keys "2".."4" only). Models never writes `data.trainings` in v1.
Note: retired models no longer count toward `MODEL_LIMIT`; to keep saves bounded AIModelService prunes the
oldest retired models beyond `ModelConfig.RETIRED_KEEP` (80) when a model is created — never a model that is
training, referenced by a studio project (`sourceId`) or live; `replacedBy` chains are re-linked around a pruned
model.

STATUS: done by econ (vage, replacedBy, release.auto, trainings cleaners present).

## 8. tests/lead/run_all.sh (lead) — add the models suites
```bash
run models            bash tests/models/run.sh
```
`tests/models/run.sh` exits non-zero unless `test_models` and `test_ui` (empty/rich/full) all report 0 failed.
Why: the models package ships 4 suites (276 checks) that run_all does not call yet.
STATUS: already done (integrate: run_all runs `models` = tests/models/run.sh)

## 9. Note for every package: auto-price runs in a Heartbeat worker
`PricingService.init()` (called from `AIModelService.init()`) connects one `RunService.Heartbeat` handler that
advances the auto-price forecasts of the whole server within `ModelConfig.PRICING.frameBudget` (1.5 ms) of CPU per
frame and does nothing when no job waits. No change needed elsewhere; mentioned so nobody is surprised by it.
STATUS: already done (integrate: info)
