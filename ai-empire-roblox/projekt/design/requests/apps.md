# Requests from package "apps" (HUD Next goal, assistant briefing, Company / Hardware apps, screens)

The apps package works without each item (it uses the fallbacks named below). Each one removes a duplicated
constant or an approximation in a frozen economy file.

## 1. HardwareConfig / MarketService (econ) - export the serving power price (small)
`MarketService.module.luau:158` charges `live.cost += fleet.throughput * 0.025` while any model is live
(electricity of serving). The Hardware app shows that cost per game day ("Power while serving $459") and has to
repeat the literal. Change:
```lua
-- HardwareConfig.module.luau
HardwareConfig.SERVE_POWER = 0.025 -- $ per compute unit per second while any model is live (MarketService.tick)
-- MarketService.module.luau:158
if #entries>0 then live.cost+=fleet.throughput*HardwareConfig.SERVE_POWER end
```
`Client/UI/Apps/ComputeApp.module.luau` already reads `(HardwareConfig :: any).SERVE_POWER or 0.025`, so it picks the
constant up automatically (no client change needed). tests/apps/test_ui.luau (mid) checks the shown value against
`throughput * 0.025 * 1200`.

## 2. EmpireService (econ) - exact repair countdown of rack faults (optional)
`live.compute.faults[i] = {slot, gpu, since}` (EmpireService.tick ~:293). The fault's repair progress `f.left`
(1 -> 0) runs at `1 / FAULT.it` per second while IT is on duty and `1 / FAULT.alone` otherwise
(`CompanyOps.faultStep`), so a fault that started at 17:59 slows down at 18:00. The Hardware app and the phone
count down from `since` at the current rate ("Rack R3 fault · IT on the way · ~45 s"), which is exact unless the
IT shift changes during the repair. To make it exact, add the remaining seconds at the current rate in whole 5 s
steps (changes at most every 5 s, a few bytes, faults are rare):
```lua
local rate = if Ops.itOnDuty(e, clock) then 1 / Ops.FAULT.it else 1 / Ops.FAULT.alone
for _, f in Ops.faults(e) do
	table.insert(faults, { slot = f.slot, gpu = f.gpu, since = math.floor(f.since), eta = math.ceil(f.left / rate / 5) * 5 })
end
```
ComputeApp would then prefer `f.eta` when present (a two-line change in an apps file; tell the apps owner or the
lead applies it: `local left = if typeof(f.eta) == "number" then f.eta else <current formula>`).
Client half: done by apps (ComputeApp already prefers `f.eta` when the server sends it).

## 3. tests/lead/run_all.sh (lead) - add the apps suites
```
run apps              bash tests/apps/run.sh .gen_apps_runall
```
(`tests/apps/run.sh [gen]` builds `harness/<gen>` from `work/src` when no gen is given; with a gen name it expects the
manifest to exist, so in run_all use
`python3 harness/make_manifest.py --src work/src --gen harness/.gen_apps >/dev/null` first and then
`run apps bash tests/apps/run.sh .gen_apps`.) Expected today (fix round): 18 suites (6 UI states, 3 server states, 9 adversarial scenarios incl. the real rate
limiter with 100 ms round trips), 0 failed, about 20 s together.
GUI previews: `tests/apps/render.sh` (about 6 min, out/apps/*.png). Negative checks: `tests/apps/negative.sh`.

## 4. phone (Screens/Phone) - read the HUD's lane width on phones (HUD fix round, user plays on an iPhone)
On phones the HUD column now has its own UIScale (`HUD.COMPACT_BOOST = 1.5`) so the goal card reads at ~13 pt and
"Open company" is a 44 pt touch target (review: the old HUD text was ~6-8 pt). The column is still 300 design px
wide at -16, but in compact mode it takes 300 x 1.5 + 16 = 466 HUD-layer px. The HUD publishes that lane on its
frame: `PlayerGui.AIEmpire_HUD.Root.HUD:GetAttribute("LaneWidth")` (466 on phones, 316 on desktops; also
`Compact` = true/false). `Phone.applyLayout` still uses the constant `Phone.HUD_WIDTH = 316`, so on an iPhone the
open phone would overlap the HUD column by about 65 screen px. Change in
`Client/UI/Screens/Phone.module.luau` applyLayout:
```lua
local hudFrame = hud and hud:FindFirstChild("HUD") -- the HUD layer's Root (already read for its UIScale)
local lane = hudFrame and hudFrame:GetAttribute("LaneWidth")
local hudW = (if typeof(lane) == "number" then lane else Phone.HUD_WIDTH) * hs
```
and re-run applyLayout on `hudFrame:GetAttributeChangedSignal("LaneWidth")`. tests/apps/test_ui.luau (phone) checks
the attribute (466).
STATUS: already done by phone in its parallel fix round (Phone.module reads "LaneWidth" and re-runs the layout on its
change); verified in out/apps/hud_mid_phoneopen.png (844x390: the open phone ends left of the boosted HUD column).

## 5. econ (EmpireService.empireAction) - night shift per role in one call (small)
The Settings switch is per role but the action is per department, so one tap sends 1-3 EmpireActions (researcher 3,
engineer 2, marketer 2). The Company app now queues them in a lane that mirrors the token bucket and retries
RATE_LIMIT (tests/apps/test_adv.luau spam: no half-on role), but an atomic action is simpler and cheaper:
```lua
-- EmpireService.empireAction, next to action == "nightShift"
if action == "nightShift" and p.role ~= nil then
	local list = Ops.ROLE_DEPTS[Guard.id(p.role) or ""]
	if not list or typeof(p.on) ~= "boolean" then return {ok=false, err="BAD_INPUT"} end
	if Ops.stageIndex(e) < Ops.NIGHT.from then return {ok=false, err="OFFICE"} end
	if typeof(e.nightShift) ~= "table" then e.nightShift = {} end
	for _, dept in list do e.nightShift[dept] = if p.on then true else nil end
	return setFlag(session)
end
```
EmpireApp then sends `{action="nightShift", role=roleId, on=bool}` once (a one-line change in the apps file).

## 6. econ (EmpireService.dealAction) - explicit Pin / Skip state (small)
`pin` and `skip` toggle on the server, so a repeated request undoes the first one. The app now locks a row's buttons
until a snapshot shows the new state and at least 0.6 s have passed (test_adv spam: double tap keeps the pin), but an
explicit state makes it idempotent: accept an optional boolean `on` and keep toggling when it is nil:
```lua
if p.action == "pin" then
	local want = if typeof(p.on) == "boolean" then p.on else d.pinned ~= client.id
	d.pinned = if want then client.id elseif d.pinned == client.id then nil else d.pinned
	if d.pinned == client.id then d.skip[client.id] = nil end
	return success(session)
end
if p.action == "skip" then
	local want = if typeof(p.on) == "boolean" then p.on else not d.skip[client.id]
	d.skip[client.id] = if want then true else nil
	if want and d.pinned == client.id then d.pinned = nil end
	return success(session)
end
```
EmpireApp then sends `on = not current` (one line).

## 7. econ (CompanyOps / EmpireService) - per-department HR target (CORE_SPEC 8.1 player decision, spec gap)
CORE_SPEC 8.1 lists "per-department target" as a player decision; there is no action and no field, so the Settings
card shows the targets read-only ("People / HR target: ML Engineer 10 / 28 ..."). Proposal (save-compatible, no
staff-profile field): `e.hr.targets = { [roleId] = n }` (optional, nil = automatic), `Ops.hrNeed(e, role)` returns
`math.min(seats, e.hr.targets[role])` when set, and `EmpireAction {action="hrTarget", role=roleId, target=n|nil}`
(validated 0..seats, OFFICE below stage 2). The apps package adds a -/+ stepper per role to the HR card as soon as the
action exists (the status line already explains why HR waits).

## 8. Computer.module owner (lead) - a touch scale for the Computer window on phones (review: touch targets)
UIRoot draws the Computer window at ~0.43 on an iPhone in landscape, so a 36 px control is ~15 pt. The apps now use
touch sizes on touch-first screens (`Kit.tap(normal, 96)`: switches, Pin/Skip/Join, apprentices, Buy/Sell, tabs,
Invite/Reject, Hire), about 41 pt each, but Apple asks for 44 pt and the sidebar / other apps do not do it. A window-wide
answer in `Client/UI/Screens/Computer.module.luau`: on `Kit.isTouch()` and a small screen give the window's UIScale
`math.clamp(0.62 / rootScale, 1, 1.35)` and size the window `UDim2.fromScale(1 / s, 1 / s)` so it still fills the
screen (content reflows, rows get ~1.3x taller in points). With that the apps could go back to `Kit.tap(x, 72)`.

## 9. lead (info) - LOGIC_BRIEF 15 "work items" have no system yet
The review notes that LOGIC_BRIEF 15 wants the assistant and the screens to show "the item and its progress". No
work-item system exists in src (only the training run, the research job and studio projects), so the briefing and
screens show those. This needs an econ/staff design decision before an apps change.
