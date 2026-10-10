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
    `PhoneService.removeCalendarItem(session, key)` (<= 24 items, same key replaces; Notify "PHONE_UPDATE").
  - `PhoneService.message(session, {from, title, text, tone?})` (inbox message; Notify "PHONE_UPDATE").
  - `PhoneService.setting(session, "autoTrips") -> boolean` ("Join business trips automatically", default false).
- Client `Controllers/PhoneController`: `PhoneController.open(screen?, arg?)`, `PhoneController.openChat(modelId)`.
- Shared `ReplicatedStorage/Shared/PhoneMath` (pure): time/calendar/message helpers, `PhoneMath.tripCall(...)` text,
  `PhoneMath.systemPrompt(model, company)`, `PhoneMath.demoReply(...)`.

## 1. econ owner (Template / EmpireMath.new are frozen) - save the phone setting
Add `empire.prefs = { autoTrips = false }`:
- `EmpireMath.new` (or `Template.new`): `prefs = { autoTrips = false }`;
- `Template.migrate` cleaner: `if typeof(e.prefs) ~= "table" then e.prefs = {} end; e.prefs.autoTrips = e.prefs.autoTrips == true`
  and drop every other key (no DATA_VERSION bump: a pure addition).
PhoneService already reads and writes `empire.prefs.autoTrips` when the table exists (and marks the session dirty);
the Settings screen then says "Saved with your company" instead of "Kept for this session". Covered by
tests/phone/test_phone.luau ("with empire.prefs the setting is saved there"). Replication cost: ~20 bytes once.

## 2. lead - tests/lead/run_all.sh
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_phone >/dev/null
run phone             bash -c "cd tests/phone && ../../tools/luau test_phone.luau -a .gen_phone"
run phone_ui_garage   bash -c "cd tests/phone && ../../tools/luau test_ui.luau -a .gen_phone garage"
run phone_ui_rich     bash -c "cd tests/phone && ../../tools/luau test_ui.luau -a .gen_phone rich"
```
Expected: 183/0, 33/0, 45/0 (about 40 s together). Mutation proof: `tests/phone/negative.sh` (23 mutations).
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

## 5. apps (HUD) - keep the phone's lane free
No change needed. The phone reads `PlayerGui.AIEmpire_HUD.Root.UIScale` and `Root.HUD.Visible` and keeps the phone
left of the HUD column (`Screens/HUD`: WIDTH 300 at offset -16 from the right edge, `Phone.HUD_WIDTH = 316`). If the
HUD column changes width or margin, update `Phone.HUD_WIDTH` in `Client/UI/Screens/Phone` (phone package) or tell the
phone owner. The phone button sits in the bottom-right corner (touch devices: left of Roblox's jump button); please
keep that corner free of HUD elements.
