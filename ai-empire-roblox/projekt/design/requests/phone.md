# Requests from package "phone" (company phone: calls, messages, calendar, contacts, settings, AI chat)

The phone works without every item below (guarded reads, honest "coming soon" states). Each item makes the phone
match the brief more closely or lets a later package plug in.

Public API of the phone (files owned by "phone"):
- Server `ServerScriptService/Server/Services/PhoneService`:
  - `PhoneService.ring(session, {from?, title, text, kind?, accept?, decline?, open?, section?, data?}) -> callId`
    rings the founder's phone (Notify "PHONE_CALL"; a call that is still ringing becomes "missed").
  - `PhoneService.onAction(kind, handler)`: `handler(session, {call?, answer?, contact?, data?}) -> {ok, text?, ...}`.
    `"itinerary"` runs when the founder answers a call of kind "itinerary" (accept AND decline are passed);
    `"driver"` runs when the founder presses the Driver contact. Without a handler the phone answers honestly
    ("The travel desk opens soon. Mia and Leo travel alone this time" / "rides are coming soon").
  - `PhoneService.BUILTIN_TRIP_CALLS = true`: the built-in assistant call for a new region/abroad pilot trip. The
    itinerary package sets it to `false` when it rings with its own booking.
  - `PhoneService.addCalendarItem(session, {key, title, detail?, at = workspace:GetServerTimeNow() time | day + hour, kind?})`,
    `PhoneService.removeCalendarItem(session, key)` (<= 24 items, same key replaces; Notify "PHONE_UPDATE" that carries
    the item / the removed key, so the phone shows it without a refetch). **Prefer `at`.** `day + hour` mean exactly what
    the phone's status bar shows at that moment: company days turn at 08:00, so `{day = 13, hour = 7}` is 07:00 at the
    END of company day 13 (the night before day 14 starts) and sorts after `{day = 13, hour = 9}`. For "Day 13 in the
    early morning" pass `{day = 12, hour = 7}` or, better, the server clock in `at`.
  - `PhoneService.message(session, {from, title, text, tone?})` (inbox message; Notify "PHONE_UPDATE" with the message).
  - `PhoneService.setting(session, "autoTrips") -> boolean` ("Join business trips automatically", default false).
- Client `Controllers/PhoneController`: `PhoneController.open(screen?, arg?)`, `PhoneController.openChat(modelId)`.
- Client `Controllers/PhoneController`: also the screens `"map" | "finance" | "team"`.
- Shared `ReplicatedStorage/Shared/PhoneMath` (pure): time/calendar/message helpers, `PhoneMath.tripCall(...)` text,
  `PhoneMath.travellers(e, trip)` (the field rep + engineer of a trip, the same people ShuttleService flies),
  `PhoneMath.arrivalAt / arrivalMessage` (field staff "Arrived in Port Meridian, checked in at the Meridian Grand"),
  `PhoneMath.systemPrompt(model, company)`, `PhoneMath.demoReply(...)`, `PhoneMath.recapPrompt(turns, text)`.
- AI chat breakers (review round 1): a failed / empty / blocked reply pauses TextGenerator for THAT player only
  (20 s, doubling to 300 s); the server-wide breaker opens only for "not available / not eligible" errors, a generator
  that cannot be created, or request errors of 2 different players within 60 s with no success in between.

## 1. econ owner (Template / EmpireMath.new are frozen) - save the phone setting
Add `empire.prefs = { autoTrips = false }`:
- `EmpireMath.new` (or `Template.new`): `prefs = { autoTrips = false }`;
- `Template.migrate` cleaner: `if typeof(e.prefs) ~= "table" then e.prefs = {} end; e.prefs.autoTrips = e.prefs.autoTrips == true`
  and drop every other key (no DATA_VERSION bump: a pure addition).
PhoneService already reads and writes `empire.prefs.autoTrips` when the table exists (and marks the session dirty);
the Settings screen then says "Saved with your company" instead of "Kept for this session". Covered by
tests/phone/test_phone.luau ("with empire.prefs the setting is saved there"). Replication cost: ~20 bytes once.

## 2. lead - tests/lead/run_all.sh (still open: the project-wide run does not cover the phone yet)
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_phone >/dev/null
run phone             bash -c "cd tests/phone && ../../tools/luau test_phone.luau -a .gen_phone"
run phone_ui_garage   bash -c "cd tests/phone && ../../tools/luau test_ui.luau -a .gen_phone garage"
run phone_ui_rich     bash -c "cd tests/phone && ../../tools/luau test_ui.luau -a .gen_phone rich"
run phone_ui_fixes    bash -c "cd tests/phone && ../../tools/luau test_ui.luau -a .gen_phone fixes"
run phone_ui_touch    bash -c "cd tests/phone && ../../tools/luau test_ui.luau -a .gen_phone touch"
```
Expected (review round 1): 226/0, 36/0, 50/0, 43/0, 19/0 (phone_ui_fixes runs about 4 min of mock time, a few
seconds real). Same as `tests/phone/run.sh`. Mutation proof: `tests/phone/negative.sh` (59 mutations). Previews:
`tests/phone/render.sh` -> `out/phone/*.png` (desktop 1280x720 + iPhone landscape 844x390 + touch).
test_ui requires `tools/guiprev/guidump` (sandbox.py already copies guiprev).

## 3. models / apps (MarketApp or LabApp) - "Chat" on a released model (user request 16: "Lab/Market app")
On each live (or retired) model card a small button "Chat" that opens the phone on that model's thread:
```lua
Kit.onClick(chatButton, function()
	-- lazy require: PhoneController requires Screens/Computer, which requires the apps (no require cycle)
	require(script.Parent.Parent.Parent.Controllers.PhoneController).openChat(model.id)
	Computer.close()
end)
```
Only models with `model.release` (status "live" or "retired") can chat; the server answers NO_MODEL otherwise.

## 4. staffops (EmployeeController, client) - a phone in the hand during calls (brief 17b)
When an employee shows the life package's phone pose (`Holding == "Phone"` / activity "PHONE"), weld a small
phone part to the right hand (client-side, LOD like the cup: Part 0.3 x 0.6 x 0.08, Color (20,22,24), a
SurfaceGui-free Neon strip 0.26 x 0.5 x 0.01 on the face in the company accent at Transparency 0.3), removed when
the pose ends. No server parts, no network.
STATUS: done by staffops (EmployeeController: a phone part in the right hand while the rig's Pose is "phone" and nothing else is held; Holding "Phone"/"phone" works too)

## 5. apps (HUD) - keep the phone's lane free (info, no change needed)
No change needed. The phone keeps left of the HUD column using the HUD frame's attribute `LaneWidth`
(`PlayerGui.AIEmpire_HUD.Root.HUD:GetAttribute("LaneWidth")`, HUD-layer px: 300 x the compact boost + 16, published by
`Screens/HUD` since the compact phone HUD) times `Root.UIScale`, and re-runs its layout when that attribute changes.
Without the attribute it falls back to `Phone.HUD_WIDTH = 316`. On a small phone the landscape phone first narrows
(580 -> 520 design px) and only then shrinks (667x375 touch: scale 0.84 next to the 466 px compact lane; 844x390:
0.96). Please keep publishing `LaneWidth` when the column changes. The phone button sits in the bottom-right corner
(touch devices: left of Roblox's jump button); please keep that corner free of HUD elements.

## 6. info for later packages (no change needed)
- The open phone raises its ScreenGui to DisplayOrder 28 (above ShuttlePass 25, below toasts / TravelGPS 30 and every
  panel at 40+); closed it is 15. FlightChoice, ShuttleRide and HeliRide close the phone when they appear
  (`PhoneController.PANELS`), like the talk / interview / assistant / lift / security panels.
- itinerary package: the phone's Settings "Join business trips automatically" (`PhoneService.setting(s, "autoTrips")`,
  saved once request #1 lands) and the auto-trip countdown with a cancel button (brief 24) are yours to wire through
  `PhoneService.onAction("itinerary", ...)`; the phone keeps saying "The travel desk that uses it is coming soon" until
  the hook is registered.
