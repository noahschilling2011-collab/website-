# Requests from package "shop" (Robux shop) for files it does not own

Everything below is optional for correctness: the shop works today and hides every item whose feature is
missing. Each request turns one hidden item on (or removes a cast). Public API (ShopService):
`owns(player|session, passKey)`, `revenueMultiplier(session)`, `setRedeemHandler(voucherKey, fn(session) -> (ok, errCode?))`,
`onPassChanged(fn(session, passKey, owned))`. Catalogue + owner instructions: `ReplicatedStorage/Shared/Config/ShopConfig.module.luau`.

## 1. MarketService.module.luau (lead) — Investor Relations pass  [turns the "investor" pass on]
In `Market.tick`, where the player's own market revenue is finalised (today):
```lua
live.revenue*=b.revenue*cycle.revenue; live.cost*=b.serving*cycle.cost
for _, r in live.perModel do r.revenue*=b.revenue*cycle.revenue; r.cost*=b.serving*cycle.cost end
```
change to
```lua
local shopFactor=Shop.revenueMultiplier(session) -- Investor Relations game pass (1 without it)
live.revenue*=b.revenue*cycle.revenue*shopFactor; live.cost*=b.serving*cycle.cost
for _, r in live.perModel do r.revenue*=b.revenue*cycle.revenue*shopFactor; r.cost*=b.serving*cycle.cost end
```
plus `local Shop=require(script.Parent.ShopService)` at the top (no require cycle: ShopService needs only
SaveService, SessionService, EconomyService, ShopDecor/ArchKit, Template, Remote, Guard).
Why: the multiplier is applied after market shares are computed, so it never changes another player's share
(monetization.md). The FIRST call of `revenueMultiplier` is also what makes the pass sellable (`live.shop.available.investor`):
the pass is never offered while the game doesn't apply it. NPC sessions are safe to pass (they get 1). If
CORE_SPEC moves the revenue formula, apply the factor wherever the player's own consumer/API revenue ends up.
STATUS: done by econ (shopFactor after shares, market revenue only; INVESTOR_MULTIPLIER 1.10)

## 2. RecruitingService.module.luau (lead) — headhunter voucher  [turns the "headhunter" product on]
In `Recruiting.init()` register the redeem handler, e.g.:
```lua
local Shop=require(script.Parent.ShopService)
Shop.setRedeemHandler("headhunter",function(s)
	local e=s.data.empire
	if not s.data.company then return false,"NO_COMPANY" end
	if #e.applicants>=EmpireMath.MAX_APPLICANTS then return false,"APPLICANTS_FULL" end
	local a
	for _=1,40 do -- deterministic: walks the serial stream until a 4-5 star candidate comes up
		a=Recruiting.generate(e,s.userId,os.time())
		if Recruiting.traits(s.userId,a.serial).k>=4 then break end
	end
	table.insert(e.applicants,a)
	Session.markDirty(s,true)
	-- optional: Remote.fire(s.player,"Notify","PEOPLE_NOTICE",{...}) like a normal application
	return true
end)
```
Return `false, CODE` for anything that must not consume the voucher (ShopService keeps it). ShopApp already
has texts for `APPLICANTS_FULL` and `NO_COMPANY`; other codes fall back to ActionController.message.
Registering the handler makes the product sellable and the voucher redeemable (`live.shop.available/redeemable`).
STATUS: done by staffops (Recruiting.headhunt registered in Recruiting.init; applicant time = play time e.seconds; refuses NO_COMPANY / APPLICANTS_FULL / STAFF_FULL so the voucher is kept)

## 3. VehicleService.module.luau + CampusConfig.module.luau ("world" package) — Executive Limo pass
* `CampusConfig.CARS`: one entry with `pass = "limo"` (price 0 or ignored). As soon as it exists the limo pass
  becomes sellable (`ShopConfig.limoCarExists()`).
* `BuyCar`: refuse cars with `pass ~= nil` (`NOT_OWNED` or a new code).
* `SpawnCar` / fleet listing: allow a pass car only when `ShopService.owns(session, def.pass)`.
* Optional: `ShopService.onPassChanged(function(s,key,owned) ... end)` to show/hide it live.
* `Template.migrate` drops car ids that are not in `CampusConfig.CARS`; a pass car must never be stored as owned
  in `campus.cars` (ownership comes from the pass), so nothing changes there.

## 4. Types.module.luau (lead) — remove two casts (cosmetic)
Add `shop: any?` to `PlayerData` and `shop: any?` to `LiveInfo`. Template/ShopService/ShopApp currently use
`(data :: any).shop` / `(session.live :: any).shop`; the casts can stay, nothing breaks without this.
STATUS: done by econ

## 5. tests/lead/run_all.sh (lead) — add the shop suites
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_shop >/dev/null
run shop              $L tests/shop/test_shop.luau -a .gen_shop
run shop_client       $L tests/shop/test_client.luau -a .gen_shop
```
(works from the project root like the other suites; `tests/shop/run.sh` does the same.)
Expected today: 146/0 and 44/0, about 1 s together. Negative checks: `tests/shop/negative.sh` (14/14 detected).

## 6. DebugPanel.module.luau (client, owner of DebugPanel) — Studio buttons (optional)
DebugService now accepts (Studio only, never live): `{cmd="pass", key="vip"|"limo"|"founderSuite"|"investor"}`
(session flag, not saved) and `{cmd="voucher", key="party"|"headhunter"}`. Add buttons to `COMMANDS`, e.g.
`{cmd="pass",key="vip",label="Shop: VIP pass",done="VIP pass active (this session)"}` — the panel's
`ActionController.call("Debug", {cmd=def.cmd})` would need to pass `key` too.

## 7. Kit.module.luau (client, owner of Kit) — sidebar icon (optional)
`Kit.icon(parent, "shop")` falls back to the market bars. A small bag icon would fit, e.g.
`elseif kind=="shop" then ring(.16,.3,.68,.64,3);ring(.34,.06,.32,.32,6)`.

## 8. life / talk packages — react to shop moments (optional, attributes only)
* Office attribute `TeamPartyUntil` (number, `workspace:GetServerTimeNow()` deadline) is set while a team party
  runs in front of the HQ (ShopConfig.PARTY_SECONDS, default 180 s) and cleared afterwards. Staff could
  gather on the plaza / cheer; TalkService could add "Great party!" lines.
* Office attribute `FounderSuite = true` while the founder owns the Founder Suite pass (decor on the private
  founder terrace). Hotel/buildings could also dress the hotel VIP suite (hotel_site.md R12) with it.

## 9. Info for the net package (no action)
`data.shop` = `{ receipts, order, vouchers, passes, tips }`; receipts/order stay server-only (your strip).
`vouchers`, `passes` (fallback cache) and `tips` replicate (a few bytes, change only on purchases).
`live.shop` = `{ passes, available, redeemable, checked }` (~200 B), rewritten only on change (load, pass
change, handler registration, first investor multiplier call). Since every Template.new() save has
`shop.receipts`, `replicatedData` clones `data` on each send (shallow, cheap) — just so you know.
