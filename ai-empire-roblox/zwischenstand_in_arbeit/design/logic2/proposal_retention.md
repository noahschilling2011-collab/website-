# AI Empire: Retention, Social & Fairness proposal (logic2)

Date: 2026-10-17. Author: logic2 retention agent. Status: **design proposal**, read-only on the game. Nothing under
`work/`, `tests/`, `agents/stable/` or the existing `design/*` files was changed. Input for LOGIC2_SPEC.

**Lens.** Why a kid comes back tomorrow and next week; what happens while they are away; friendly multiplayer that
is safe for kids (visiting HQs, co-op deals, leaderboards, rivals between real players); monetization that stays fair
(owner decision S1: small cash packs, "it should take time"); anti-frustration.

**Labels.**
- **[M]** = measured: a `file:line` or a command with its output is given.
- **[P]** = a proposed number or rule. It is a design value, not a fact about the game.
- **[A]** = an assumption, stated as one.
- **[U]** = unsure.

**Sources and paths.** Paths are relative to `scratchpad/`
(`/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad`).
- `src/<path>:<line>` = my snapshot `design/logic2/sim_retention/src_snap`, a byte copy of `work/src` taken
  **2026-10-17 11:39:02 UTC** (`sim_retention/src_snap.time`, md5 list `src_snap.md5`).
- Against the audit snapshot (09:21:49) 21 files differ (`diff` of the two md5 lists): ShopConfig, ShopMath,
  ShopService, Template, EmpireService (shop pack credits, `EmpireService.module.luau:111-115`), the itinerary /
  driver / shuttle / jet services and client UI files. For a non-payer the economy is unchanged: my baseline run
  reproduces the audit exactly (STAGES 12.5 / 38.5 / 92.0 / 174.5, `sim_retention/out/base_human.txt:19`).
- Simulator, scripts and outputs: `design/logic2/sim_retention/` (§8, Appendix B).
- Other logic2 inputs I build on: the audit (`design/logic2/audit/AUDIT.md`) and the progression proposal
  (`design/logic2/proposal_progression.md`, P1–P8). A third lens (`design/logic2/sim_moment`, M1–M6) was still
  running when I wrote this; where it overlaps I say so (§6).

---------------------------------------------------------------------------------------------------------------------

## 0. Summary

{{SUMMARY}}

---------------------------------------------------------------------------------------------------------------------

## 1. What I re-checked before relying on the audit

| Audit claim | My check | Result |
|---|---|---|
| Nothing runs offline; `lastSeen` written and never read | `grep -rn lastSeen` over the snapshot | 2 hits: the default `src/ReplicatedStorage/Shared/EmpireMath.module.luau:17` and the write `src/ServerScriptService/Server/Services/EmpireService.module.luau:339`. Never read [M] |
| Daily grant $1,000 + $500·(streak−1), max 7; a missed day resets | `EmpireService.module.luau:163-174` | `streak = if e.daily.day == day - 1 then min(7, streak + 1) else 1` (:167), `reward = 1000 + (streak - 1) * 500` (:169). The client repeats the formula in `src/StarterPlayer/StarterPlayerScripts/Client/UI/Apps/HomeApp.module.luau:245-249` [M] |
| The sim bot claims the daily grant | `grep -n ClaimDaily` in the audit sim | **Only once, at founding** (`audit/sim/sim.luau:964`). The audit's long runs are one continuous session, so they could not show daily effects. My session model (§4.1) claims it at the start of every session [M] |
| No badges, invites, notifications, events | `grep -rl` over the snapshot for BadgeService, SocialService, ExperienceNotificationService, PolicyService, MessagingService, MemoryStoreService, GetFriendsAsync, Idled, AccountAge, GetJoinData | 0 files for every name [M] |
| Other players weigh 0.15 of one rival | `src/ReplicatedStorage/Shared/Config/MarketConfig.module.luau:174` | `PLAYER_RIVAL_WEIGHT = 0.15` [M]; decided in `design/CORE_SPEC.md:84` |
| API access is the only player-to-player money flow | `src/ServerScriptService/Server/Services/MarketService.module.luau:59-89`; prices `MarketConfig.module.luau:81-82`; release guard `src/ServerScriptService/Server/Services/AIModelService.module.luau:639-645` | fee = `max(100, sub×100 + api×50)`, sub ∈ {0,5,10,20}, api ≤ 20 → **at most $3,000 per game month (3,600 s, `GameConfig.module.luau:30`)**. Snack sales give the counter owner 55 % (`FacilityService.module.luau:245`). Both are tiny next to mid-game net, so there is no real money-transfer channel to abuse today [M] |
| Leaderboards tie at 99 | `src/ServerScriptService/Server/Services/LeaderboardService.module.luau:8,14-21,29`; cap `EmpireMath.module.luau:159` | modes = best stats + arena; every core stat `min(99, …)`; the server fallback breaks ties by **lower userId** (:29), so among capped players the oldest account always ranks first [M] |
| AFK companies lose money because auto-HR keeps hiring (AUDIT §7.4) | read `audit/sim/out/afk_hq.txt` rows 10-60 | Partly. The bigger cause is B2B: 4 accounts signed by min 20 reserve compute, consumer serving is starved (**cap use 376 %** at min 20, 254-263 % later), users fall from 35,067 (min 10) to 3,144-8,872, market income from 5,529 to 1,697 $/min while staff stays at 13 (rows 10-60 and the "min 45-60 income" line). B2B can reserve 100 % of compute: `Ops.tokenCap` = all throughput (`CompanyOps.module.luau:768-771`), new pilots check only `used + tokens <= tokenCap` (:903), `Ops.capacity` subtracts the reservation (:630-638) [M]. Isolated in batch B (§4.4) |
| Roblox kicks idle players after ~20 min | API dump | Only `Player.Idled` exists (Appendix A). The kick time is **[U]**, as in the audit |

---------------------------------------------------------------------------------------------------------------------

## 2. Retention today, counted in real days

The audit counts minutes of one long session. A kid plays in sessions. I re-ran the audit bot (looks every 30 s,
seed 4242, non-payer) as a kid who plays a fixed number of minutes per real day; between sessions the clock jumps to
the same time next day and nothing ticks, exactly as today (method §4.1).

{{TODAY_DAYS}}

Reading [M]:
{{TODAY_READING}}

What a kid gets for coming back today [M]: the daily grant ($1,500-4,000 on days 2-7 of a streak, the `daily`
column of the per-day tables in `out/tables_A.md`), nothing from the time away, and no event, invite, badge or
notification (§1). The only "come back" signal is the DAILY button on Home (`HomeApp.module.luau:245-249`).

---------------------------------------------------------------------------------------------------------------------

## 3. The changes

Each change: problem (evidence) · change (rules, numbers marked [P]) · touches · save · test · effort / risk.
"Base net" below always means: a 10-minute moving average of the company's recurring net profit per second
(revenue − running costs), computed on the server, **with paid multipliers removed** (Keynote Boost, Investor
Relations: `ShopService.revenueMultiplier`, `src/ServerScriptService/Server/Services/ShopService.module.luau:348`,
applied to app/API income in `MarketService.module.luau:49-50`) and never below 0.

### R1 · Night crew: offline progress with a "While you were away" card

**Problem [M].**
- Nothing runs offline: `lastSeen` is written every tick (`EmpireService.module.luau:339`) and read nowhere (§1);
  the economy ticks only online sessions (`src/ServerScriptService/Server/Main.server.luau:92-100`).
  CORE_SPEC records it as a decision: "Offline | nothing runs offline" (`design/CORE_SPEC.md:654`).
- So the game pays only for being *connected*: a device left on in the garage earns $3,433-3,642 net per minute for
  hours (audit `afk_tut`, AUDIT §3.1), a kid who logs off earns $0. That rewards leaving a phone on overnight.
- A 15-minute-a-day kid needs **12 days** to reach Global HQ and 3 days between office moves (§2).

**Change [P].**
- Every tick the server keeps `empire.away.net` = base net (10-min average, see above).
- On load (`SessionService.onLoaded`, `src/ServerScriptService/Server/Services/SessionService.module.luau:47-49`,
  called at :331-333) `Empire.welcomeBack(session)` computes, with server time only:
  - `away = os.time() − e.lastSeen` (ignored if `lastSeen == 0`, negative, or under 10 minutes);
  - `credit = 0.03 × away.net × min(away, 16 h)` [P], **at most 15 % of the next office price** (at Global HQ: of
    the Global HQ price) [P], rounded down to $100;
  - stored as `away.pending` (+ `away.hours`), **not** paid yet.
- Home and the HUD show the card **"While you were away"**: "Your night crew kept the servers running for 16 h:
  +$71,000 (3 % of your usual profit per hour, max 16 h)". One button **COLLECT**. The card never expires and never
  shows a shop item.
- Nothing else moves offline (as today): no ageing, no churn, no wages, trips and terms pause. So being away is never
  punished.
- Not sellable: no "double it", no longer cap for Robux (R7).
- Counted per 24 h at most 16 h, so logging in many times a day gains nothing over once a day.

**Why these numbers.** The cap share decides the effect, the rate barely matters (o3 and o5 give identical runs because
the 25 % cap binds from day 4, `out/A_k30_o3.txt` vs `A_k30_o5.txt`). At 25 % the 15-min kid reaches Global HQ on day 8
instead of 12 and finishes all goals on day 10 instead of 14 — too much compression while the late game still ends
(P3 of the progression proposal is not built yet). {{R1_WHY}}

**Touches.** `EmpireService` (tick: average; `welcomeBack`; `EmpireAction {action = "collectAway"}` next to the other
actions in `empireAction`, `EmpireService.module.luau:495-506`), `SessionService.onLoaded` hook (exists), `EmpireMath.new` default
(`EmpireMath.module.luau:14-17`), `Template.cleanCompany` (cleaner next to `prefs`, `src/ServerScriptService/Server/Lib/Template.module.luau:414-415`),
HomeApp / HUD card, `AssistantService` morning line, CORE_SPEC table line 654 ("Offline: night crew, R1").

**Save.** `empire.away = { net = number, pending = integer, hours = number }`, additive. Cleaner: finite numbers,
`net` clamped 0..1e7, `pending` 0..1e9 integer, `hours` 0..16; else defaults `{net = 0, pending = 0, hours = 0}`.
`lastSeen` already exists. No DATA_VERSION change (stays 6).

**Test.**
- Sim batch A (§4.2, §4.3).
- New mock suite `tests/retention` [P]: first join → no credit; formula and both caps; `lastSeen` in the future (clock
  skew) → 0; < 10 min → 0; paid boost active → same credit as without; COLLECT twice → second `NOTHING_PENDING`;
  credit survives a rejoin before collecting (no double credit: `welcomeBack` adds only for the time since
  `lastSeen`, which the first session already moved forward); cleaner on NaN / strings / negatives; an old save
  without `away` loads with defaults (Template.migrate path).
- `tests/econ` net budget: `away` is not replicated except `pending` and `hours` (2 numbers).

**Effort / risk.** M / medium. Risks: content compresses (measured, §4.3; pair with progression P3); the average can be
nudged by a price spike just before logging out (10-min average + the office-price cap bound it); two servers at once
are already prevented by the save lock (`SessionService` / `SaveService.releaseLock`, `SessionService.module.luau:294-299`).

---

### R2 · Daily briefing, soft streak, Founder week and three daily tasks

**Problem [M].**
- The daily grant is $1,000-4,000 (`EmpireService.module.luau:169`): 4-10 seconds of mid-game net (AUDIT §5). In the
  14-day session runs it adds up to $44,500 against $14.5M of cash at the end (`A_k30_base`, §4.2).
- One missed day resets the streak to 1 (:167). In the 5-days-a-week run the streak never passes 5 and falls back to
  1 every Monday (`out/A_k30w_base.txt` DAY lines). That punishes a kid for a weekend.
- The audit's long runs never claimed it again after founding (§1), so its size was never visible in a sim.

**Change [P].**
- **Daily briefing** (same button, same 00:00 UTC day): reward = max(today's grant, **(1 + 0.25·(streak − 1))
  minutes of base net**) [P], rounded to $100; streak 1..7 as today. Text: "Daily briefing: +$X (2.5 minutes of your
  profit, day 7 of your streak)". Day 1 of a new player is unchanged ($1,000, base net 0), so the onboarding cash path
  ($11,000, ONBOARDING_SPEC A3) stays exact.
- **Soft streak**: a missed day lowers the streak by 1 per missed day instead of resetting it
  (`streak = min(7, max(1, streak − missed) + 1)`).
- **Founder week** (Mon–Sun UTC): the 4th day with a claim in a week gives a "Founder week" stamp on the milestone
  wall (progression P5) and +100 research points [P]. No cash. 4 of 7 days, so a weekend off still counts.
- **Three daily tasks** (seeded from userId + UTC day, the same all day, deterministic): drawn from a pool of tasks that
  each take 2-10 minutes of normal play, e.g. "Launch a new version", "Answer 2 training events", "Sign or renew a
  client", "Reach 50,000 users", "Visit another founder's HQ **or** tour your own Data Hall" (every social task has a
  solo option). Reward per task: 1 minute of base net + 10 RP [P]; all three: one extra Founder-week day. No reroll
  for Robux, no skip.
- One shared pure function `EmpireMath.dailyReward(e, day, baseNetPerMinute)` replaces the formula in the server
  (`EmpireService.module.luau:163-174`) and the copy in `HomeApp.module.luau:245-249`, so the button never shows a
  different number than the server pays.

**Touches.** EmpireService `daily`; new pure `EmpireMath.dailyReward`, `EmpireMath.dailyTasks(userId, day)`;
HomeApp (DAILY button text, "Today" tasks card), AssistantService line; Template cleaner (`e.daily` is cleaned at
`Template.module.luau:549-551`).

**Save.** `empire.week = { id = isoWeek, days = 0..7, stamped = bool }`, `empire.tasks = { day = utcDay, done = {3 bools} }`,
additive with cleaners (unknown keys dropped, ints clamped). `daily` unchanged.

**Test.** Sim batch A (`--daily2 K0/KS --softstreak`, §4.3). Mock: reward = max(old, minutes × base net) per streak;
soft streak after 1 / 3 / 10 missed days; week roll-over on Monday 00:00 UTC; 4th day stamps once; tasks are the same
for a user all day and differ between users/days; HomeApp shows exactly the server's amount (shared function).

**Effort / risk.** S for briefing + soft streak, M for tasks / week. Risk: the briefing is money too (measured
together with R1).

---

### R3 · AFK-safe automation: the company never hurts itself while you watch or wait

**Problem [M].**
- B2B can take 100 % of the servers: new pilots start whenever `used + tokens <= tokenCap` (all compute,
  `CompanyOps.module.luau:768-771,903`). In the audit's `afk_hq` the 4 signed clients starve the apps: cap use 376 %,
  users 35,067 → 3,144-8,872, net $1,282-1,419/min (§1).
- Auto-HR hires against a 5-minute trailing revenue (`EmpireService.module.luau:204-224`, `Ops.hrAllowed`
  `CompanyOps.module.luau:548-561`) and never looks at profit, so it keeps hiring on a fading peak (afk_s4: 124 staff,
  net $26.9k → $16.3k/min, AUDIT §7.4).
- Save mode freezes HR forever until the player taps "upgrade" (`CompanyOps.module.luau:557`; afk_tut $758k in the
  garage). Progression **P6** fixes this; I adopt it unchanged.

**Change [P].**
- **B2B half rule**: a **new** pilot trip starts only while reservations stay ≤ **50 %** of token capacity [P].
  Kept accounts and renewals keep today's 100 % rule, so no client is ever lost by the change. The Clients tab and the
  assistant say why: "Half of your servers are for business clients. Buy a GPU to take Atlas Search." For an active
  player that is a real choice (more GPUs → more clients).
- **HR earns its keep**: auto-HR hires only while net ≥ **25 %** of revenue [P], and its wage budget uses the lower of
  the 5-minute trailing and the current revenue. The HR status line says "HR paused: profit below 25 %".
- **P6 Save mode "Ready to move"** (progression proposal) as written there.
- Optional, owner decision, default **off**: "AFK = night crew". After 20 minutes without input (`Player.Idled`
  gives the idle time) the company earns at the night-crew rate until the next input. It makes leaving a device on
  pointless and equal to logging off. Measure first: log AFK minutes per session with `AnalyticsService:LogCustomEvent`
  for two weeks.

**Touches.** `CompanyOps` openFor (:903) + a constant `Ops.B2B_NEW_SHARE = 0.5`; `EmpireService.autoHire` (:204-224);
EmpireApp Clients / HR status texts; AssistantService; P6 files.

**Save.** None (P6 adds `prefs.autoMove`, see there).

**Test.** Sim batch B (§4.4) with exactly these two rules as in-memory patches (`--b2bshare 0.5 --hrguard 0.25`).
Mock: a new pilot is refused at 50 % but a renewal at 90 % still renews; kept accounts are not dropped; HR refuses a
hire at 20 % margin and hires at 30 %; trailing vs current revenue (fading peak) case.

**Effort / risk.** S / low-medium. {{R3_RISK}}

---

### R4 · Open House: visiting other founders' HQs is easy, safe and remembered

**Problem [M].** Multiplayer is co-presence (AUDIT §6). Visiting exists physically — 12 plots per server, a reception
hall open to everyone, one-hour guest cards for the work floors (`FacilityService.module.luau:260-266`; rules text
`CampusApp.module.luau:99`), a "Visitors in the building" counter on the office screens
(`src/ServerScriptService/Server/Services/BuildingStateService.module.luau:486,605`) — but nothing tells a kid who is
on the server, how to get there, or gives a reason to go. Snack sales (55 % to the owner) are the only reward.

**Change [P].**
- Phone app **Founders**: companies on this server (company name, office stage, "3 visitors today"), sorted friends
  first (`Players:GetFriendsAsync` once per session). Button **VISIT**: a 3-second fade, then the server moves the
  character to that plot's visitor entrance (`Model:PivotTo` on the character; same place, no TeleportService).
- **Visitor stamp**: 30 s inside another HQ's reception gives the visitor a stamp for that company (once per pair per
  UTC day) and the host +1 "visitors today". Stamps fill a collection (5 / 10 / 25 HQs → milestone + optional badge,
  ids 0 = off). **No cash** for either side.
- **Preset reactions** for visitors: "Cool office!", "Nice servers!", "Great team!" → a toast for the host, one per
  pair per 10 min. No free text.
- **Host settings**: Open House = Everyone / Friends only / Closed. Closed hides the company from the list and refuses
  VISIT (walking in stays as today: reception only).
- Visitors of the week feed the weekly board (R6).

**Touches.** New `VisitService` (server: list, VISIT, stamps, reactions; rate limits via the existing
`Lib/RateLimiter`), PhoneScreens app tile, BuildingStateService visitor line, FacilityService (reception zone check),
Template cleaner, milestone ladder (P5).

**Save.** `empire.social = { stamps = {[userId] = utcDay} (≤ 200 entries, oldest dropped), visitorsDay = utcDay,
visitors = 0..999, openHouse = "all" | "friends" | "closed" }`, additive.

**Test.** Mock: stamp once per pair per day; host count; Closed refuses VISIT; Friends-only uses the friends list;
reaction rate limit; only preset reaction ids accepted; cleaner caps 200 stamps. guiprev 844×390 of the Founders app.

**Effort / risk.** M / low. Risk: griefing in receptions (already possible today); the PivotTo target must be a free
floor point (use the plot's existing visitor parking / path, `ExteriorDesign.module.luau:965-966`).

---

### R5 · Team-up deals: co-op clients for two real companies

**Problem [M].** No co-op exists (AUDIT §6: 45 `Remote.bind` calls in the services, none for co-op; my count
`grep -c` = 45). A second company changes progress by ≤ 5 % (SHOP_SPEC 10.2 duo rows). The only shared money flow is
API access, capped at $3,000 per game month (§1).

**Change [P].**
- When two companies at stage ≥ 3 are on one server and both have a free client slot, the assistant offers a
  **Team-up client** in Port Meridian (3 named clients [P], e.g. "Harbor Exchange"), which needs two strengths:
  partner A's best live stat X + partner B's best live stat Y ≥ 120 [P] (e.g. coding 62 + reasoning 58).
- Both founders tap **TEAM UP** on the phone within 5 minutes. No chat; the game picks the partner whose stat fits.
- Then a joint pilot trip runs on the normal CORE_SPEC clock (each company sends its own rep; both founders may join
  the same meeting — the itinerary already seats two founders separately, `src/ServerScriptService/Server/Services/ItineraryService.module.luau:37,367` SeatSet).
- On signing, **each** company gets its own account for one term (6 game days) at $30,000 per game day [P]
  (≈ a region client: $24,000-45,000, `CompanyOps.module.luau:132-136`). It renews only if both are online at renewal; otherwise it
  ends quietly. Non-zero-sum: nobody pays the other.
- Limits: one team-up at a time per company; the same pair at most once per real day; works the same with friends
  and strangers. Setting "Suggest me for team-ups" on/off.

**Touches.** CompanyOps (team-up client defs, eligibility with a partner, account creation), EmpireService
`DealAction {action = "teamUp"}`, AssistantService / PhoneService offer, Clients tab, CityPlan client tower by name.

**Save.** `empire.deals.teamUp = { partner = userId, client = id, until = playSeconds }` (≤ 1 entry), additive with a
cleaner; the account itself is a normal `deals.accounts` entry.

**Test.** Two-session mock: offer → both accept → trip → both accounts; one declines → nothing; partner leaves during
the trip → the remaining company still signs alone; renewal needs both online; pair limit per day. Sim with
`--players default@0,default@0` and a patch (not done here).

**Effort / risk.** L / medium. Not simulated: bounded by construction to one extra region-size client per company
(≈ $1,500/min ≈ 3-6 % of mid-game net, §2 of the audit table 3.1).

---

### R6 · Fair leaderboards and friendly rivals

**Problem [M].**
- Boards rank best stats (`LeaderboardService.module.luau:8,14-21`); stats cap at 99 (`EmpireMath.module.luau:159`); every
  sim run has a 99.0 model by ~2 h (AUDIT §6), payers by minute 90 (SHOP_SPEC 10.3). Ties go to the lower userId
  (`LeaderboardService.module.luau:29`). A new player can never appear on a board.
- The arena mode pays nothing and is against NPCs only (AUDIT §2).

**Change [P].**
- **Weekly boards** (reset Monday 00:00 UTC; one OrderedDataStore per mode and ISO week, same refresh loop as today
  `:42-72`): *Users gained this week*, *Clients signed this week*, *Visitors this week* (R4). Everyone starts at 0 each
  week. Values exclude shop cash by construction (users and clients, not money); the Keynote Boost adds revenue, not
  users (SHOP_SPEC 0.1 item 5).
- **All-time board**: *Peak users* (not capped at 99) or the progression proposal's *Global reach*; the stat boards stay
  as a "Hall of 99".
- **Tie-break by time**: stored value = score × 10⁶ + (10⁶ − minutes of play when reached) [P], so the first to get
  there ranks first, not the oldest account.
- **Leagues**: your rank among companies of the same office stage on this server, and among friends on this server.
  A global friends board needs one `GetAsync` per friend [U: DataStore read budget not in the API dump]; start with
  ≤ 10 friends per session, cached.
- **Rival of the day**: the closest company of the same stage on this server (or a friend) gets a card on Home:
  "You 412k users · Nova Labs 398k". It changes nothing in the market (weight stays 0.15).

**Touches.** LeaderboardService (modes, weekly stores, value encoding), Leaderboard tab UI, HomeApp rival card,
`stats.week` snapshot fields.

**Save.** `stats.week = { id, usersStart, signedStart }`, additive. The DataStore keys are new stores, not save fields.

**Test.** Mock DataStore (harness): week roll-over, tie-break order, payer with Keynote vs non-payer equal users →
equal score; Studio-mode fallback (`:35`) still works.

**Effort / risk.** M / low. Risk: DataStore request budgets with more stores [U]; keep the 180 s refresh (:76).

---

### R7 · Fair-monetization guardrails for the new loops

**Problem [M].** S1 is decided and built: cash packs are 10 / 20 / 30 % of the next office, each once per office
(`src/ReplicatedStorage/Shared/Config/ShopConfig.module.luau:67-71,136`; SHOP_SPEC 0.2). A heavy payer reaches Global
HQ at 104.7 min vs 168.8 for a non-payer (SHOP_SPEC 10.2). Every product id is still 0. New retention systems are the
classic places where games add pay-to-skip: double offline earnings, streak repair, task rerolls.

**Change [P]** (to be added to SHOP_SPEC as rules R9-R14):
1. **Never sold**: offline multipliers or longer caps, streak freeze or repair, daily-task rerolls or skips, Founder
   week days, visitor stamps, leaderboard boosts, team-up slots, notification perks.
2. Paid multipliers never count in the base net (R1/R2 formula above), so a boost bought today does not grow tomorrow's
   night-crew credit or briefing.
3. No purchase prompt on the away card, daily card, weekly stamp or team-up card, and none in a player's first session.
4. Leaderboards rank play (R6), never spend.
5. Cash packs keep S1. They are a share of the *next office*, so they cannot be multiplied by R1/R2 (both scale with base
   net, not with cash).
6. The heavy-payer bound of SHOP_SPEC 10 (every stage ≥ 0.48× the non-payer) must still hold with R1+R2 — checked in
   batch C (§4.5).

**Touches.** SHOP_SPEC rules table, ShopService (nothing to build: the rules forbid products), `ShopMath.offerAllowed`
(no offers on the four cards).

**Save.** None. **Test.** Batch C sim; mock: base net with a Keynote Boost active equals base net without; the four
cards have no shop button (UI test).

**Effort / risk.** S / low.

---

### R8 · Invites, opt-in notifications and the weekly "Tech Week"

**Problem [M].** No invite, badge, notification or event code exists (§1). A kid has no in-game way to bring a friend
and no signal outside the game.

**Change [P].**
- **Invite a friend** on Home: `SocialService:CanSendGameInviteAsync` then `SocialService:PromptGameInvite` with an
  `ExperienceInviteOptions` whose `LaunchData` carries the inviter's userId. Offered after an office move at most once a
  session, never in the first 10 minutes. **No reward for sending** (no spam incentive). When a friend joins through the
  invite (`Player:GetJoinData`), both get a "Co-founders" stamp, once per pair.
- **Notifications, opt-in only**: `ExperienceNotificationService:CanPromptOptInAsync` → `PromptOptIn` after the
  player collects a "While you were away" card in their 2nd+ session; after a decline ask again ≥ 7 days later.
  Content: "Your night crew report is ready", "Tech Week starts", ≤ 1 per day. Sending a notification is not an
  engine call in the API dump (only the opt-in prompt is) [U]; it needs the owner's setup outside the game. Until then
  nothing is sent.
- **Tech Week** (Mon–Sun UTC, theme seeded from the ISO week number, the same on every server): one product line is
  "hot" (demand +10 % [P]) — or, if adopted, the moment lens's segment trends (M2) provide the market part. Plus a
  **server goal** ("Together: 1,000,000 users served on this server this week"), counted per server, rewarded with a
  cosmetic trophy for everyone who contributed ≥ 1 %. If the owner creates Experience Events on the Creator Hub, Home
  lists them (`SocialService:GetUpcomingExperienceEventsAsync`) with an RSVP button (`PromptRsvpToEventAsync`).
- **Badges** with owner-created ids (0 = off), shared with progression P5 (`BadgeService:AwardBadgeAsync`).

**Touches.** New `SocialConfig` (ids = 0), `InviteService` (server: join data), HomeApp buttons, EmpireService week
theme, MarketMath line weight hook (only if not M2), Analytics events.

**Save.** `empire.social.invited = {[userId] = true}` (≤ 50), `empire.notify = { askedAt = os time }`, additive.

**Test.** Mock: invite button hidden in the first 10 min and when `CanSendGameInviteAsync` is false; join data stamps
both once; opt-in asked once per 7 days; theme = f(ISO week) identical across servers; server goal counter.

**Effort / risk.** M / low-medium (policy texts must follow Roblox rules [A]; nothing is sent until the owner sets it up).

---

### R9 · Anti-frustration: small fixes that stop kids from losing progress

**Problem [M].**
- GPU over-buying is allowed and useless: the greedy semi-idle bot spent $3.82M on hardware at 5-8 % server use and
  missed Global HQ in 240 min; the same rhythm with "buy only when > 85 % full" reached it at 175 min (AUDIT §3.1,
  §7.9). The Compute app gives advice only when users are waiting (`ComputeApp.module.luau:504-506`); idle servers
  show the title "Servers idle" (:483) [U: whether the buy button itself warns].
- Selling a GPU refunds 50 % (`src/ReplicatedStorage/Shared/Config/HardwareConfig.module.luau:69`), so a misclick
  costs half the price.
- "+$67.3K/day" means per 20-minute game day (AUDIT §7.8).

**Change [P].**
- **Idle-server check**: BuyGPU while servers are < 50 % used and training takes < 1 min opens a confirm sheet:
  "Your servers are 8 % used. More GPUs will not earn more now. Buy anyway?" (server returns `SERVERS_IDLE` unless
  `confirm = true`).
- **Undo**: a GPU bought in the last 30 s sells back at 100 % [P].
- **Welcome back after ≥ 3 days**: the assistant's first message is a 3-line summary (what is live, cash, the next
  goal) and one suggested action.
- Money rates in minutes, not "per day" (shared with progression P4).

**Touches.** ComputeService `BuyGPU` / `SellGPU` (`src/ServerScriptService/Server/Services/ComputeService.module.luau:93-94`), ComputeApp
sheet, AssistantService, HUD/Home labels.

**Save.** `gpus.lastBuy = { id, at = playSeconds }` (runtime only is enough [P]: no save field).

**Test.** Mock: idle check refuses without confirm, accepts with it; undo inside / outside 30 s; the audit's `semi`
vs `semi_gpucap` rows are the measured upper / lower bound of the effect.

**Effort / risk.** S / low.

---------------------------------------------------------------------------------------------------------------------

## 4. Simulation: method and before / after tables

{{SIMS}}

---------------------------------------------------------------------------------------------------------------------

## 5. Kid-safety and fairness checklist (applies to every change above)

| Rule [P] | Why | Where it bites |
|---|---|---|
| **No free text between players.** Social actions use preset buttons ("Cool office!", "Team up", "Thanks!"); names shown are company names that already pass the broadcast filter (`src/ServerScriptService/Server/Lib/TextFilter.module.luau:12-13`) and Roblox display names | kids; Roblox chat settings stay the only path for free text | R4, R5, R6 |
| **Every social reward has a solo route.** A daily task that needs another player always has a solo alternative; the co-op client is extra, never required for a goal | kids play alone on quiet servers | R2, R5 |
| **No player can take money from another.** Visits, reactions, stamps, ranks and co-op pay nothing to the other side; co-op pays both companies in full (non-zero-sum). Existing transfers stay capped ($3,000 per game month API fee, 55 % of a snack) | no alt-account farming, no "give me cash" pressure | R4, R5 |
| **Privacy switch.** "Open House": Everyone / Friends only / Closed; "Suggest me for team-ups": on/off. Founder rooms and labs stay private as today (`src/StarterPlayer/StarterPlayerScripts/Client/UI/Apps/CampusApp.module.luau:99`) | some kids do not want visitors | R4, R5 |
| **No FOMO.** Nothing is lost by being away: offline credit waits until collected, a missed day lowers the streak by one instead of resetting it, weekly goals need 4 of 7 days, no countdown timers on rewards | wellbeing; Roblox audience | R1, R2, R8 |
| **No upsell at reward moments.** The away card, the daily card, the weekly stamp and the co-op card never show a shop item; no purchase prompt in a player's first session | fair, kid-friendly | R1, R2, R7 |
| **Opt-in only** for notifications; ask at most once a week after a decline; at most one notification per day | Roblox guidelines [A], kids | R8 |
| **Leaderboards measure play, not spend** (users, clients, visitors, growth), reset weekly, ties break by who got there first | payers and veterans cannot lock the top | R6, R7 |
| **Rivals compare, never hurt.** `PLAYER_RIVAL_WEIGHT` stays 0.15 (`MarketConfig.module.luau:174`); rival cards are a comparison only | a kid never loses income because of another kid | R6 |

---------------------------------------------------------------------------------------------------------------------

## 6. How this fits the other logic2 proposals

| Other proposal | Relation to this one | Decision needed |
|---|---|---|
| Progression **P3 World Expansion** (endless levels after Global HQ) | **Needed together with R1/R2.** R1/R2 bring Global HQ and "Every goal reached" earlier in real days (§4.3); without a late loop a daily kid runs out sooner. With P3 the extra cash has a sink: today cash piles up to $14.5M by day 14 (`A_k30_base`), with the recommended R1/R2 to more (§4.3) | ship R1/R2 with or after P3 |
| Progression **P5 milestone ladder + badges** | R2's Founder week, R4's visitor stamps and R8's co-founder stamp are milestone entries; one badge config with ids = 0 | one `MilestoneConfig` |
| Progression **P6 Save mode "Ready to move"** | adopted unchanged inside R3 | – |
| Progression **P2 "Be there"** (founder in the meeting closes the deal) | R5 team-up meetings use the same rule: both founders in the room close it | build P2 first |
| Progression **P4 honest ETA** | the away card and the daily briefing state minutes of profit, same honesty rule | – |
| Moment lens **M6 fair B2B** (automatic signing only when the retainer pays for the users it displaces; seen in `sim_moment/sim.luau:68`, its write-up was not finished when I read it) | **Same failure as R3's B2B half rule** (§1, `afk_hq`). Pick one: M6 is economically sharper, R3's 50 % rule is easier to explain to a kid ("half of your servers are for business clients") | choose M6 or R3a |
| Moment lens **M2 segment trends** (`sim_moment/sim.luau:69`) | R8 Tech Week needs exactly such a weekly market theme; if M2 ships, Tech Week only adds the calendar, the server goal and the RSVP | use M2 for the market part |
| GRANDHOTEL_SPEC (§0.4: no economy, no save field, no remote) | none of R1-R9 touches the hotel packages; R5 meetings use existing Port Meridian client towers | – |
| SHOP_SPEC S1 | R7 adds rules only, no product; S1 shares unchanged | add rules R9-R14 to SHOP_SPEC |

---------------------------------------------------------------------------------------------------------------------

## 7. Risks, open knobs, owner decisions

1. **Bot ≠ kid.** The session runs use the audit bot (looks every 30 s / every 2 min) on one seed. A real kid's session
   is not a fixed 30 minutes, and kids skip days at random. Every number in R1-R3 is one knob; re-fit after a
   play-test with `AnalyticsService:LogCustomEvent` (away hours, credit collected, streak, AFK minutes).
2. **Content compression (R1/R2).** Measured in §4.3. The recommended setting moves "Every goal reached" earlier by
   about {{COMPRESS}}. Without progression P3 this shortens the game for daily players; that is the main cost.
3. **The away credit is money for not playing.** It is capped (16 h, 15 % of the next office) and only a share of
   what the company earns online, so playing stays the main source ({{SHARE_REC}} of all income with the recommended
   setting, §4.3).
4. **Session model limits.** A real rejoin starts a fresh session: the auto-HR clock and the 5-min trailing income
   reset, the market cycle phase and the server hour are whatever the new server has. The sim keeps one session and
   only jumps `os.time` (§4.1) [A]. The 10-min base-net average would also restart on a real rejoin; the proposal saves
   it in `empire.away.net` so it survives.
5. **AFK parity knob (R3, optional)** may annoy a kid who watches without touching; default off, measure first.
6. **Team-ups (R5)** depend on two kids at stage ≥ 3 on one server. On quiet servers it simply never appears; nothing
   depends on it.
7. **DataStore budgets (R6)** and **notification sending (R8)** are [U]: not visible in the API dump; check the
   Creator Hub limits before building.
8. **Owner decisions:**
   - R1 rate / cap / share: recommended 3 % · 16 h · 15 % of the next office [P];
   - R2 briefing minutes: 1 + 0.25 per streak day [P]; soft streak yes/no;
   - R3a B2B half rule vs moment M6;
   - R3 AFK parity knob (default off);
   - R4 default Open House setting (Everyone vs Friends only);
   - R6 which all-time board replaces "best overall" (peak users or the progression "reach");
   - R8 whether to set up notifications and Experience Events on the Creator Hub; badge ids.

---------------------------------------------------------------------------------------------------------------------

## 8. Reproduce

```bash
cd design/logic2/sim_retention
python3 -I make_sim.py                 # sim.luau = audit sim + retention options (identity without the new flags)
python3 -I ../../../harness/make_manifest.py --src src_snap --gen gen
../../../tools/luau sim.luau -a --real --label base_human --think 30 --minutes 240 > out/base_human.txt   # identity
./run_sessions.sh    # batch A  -> out/A_*            (session profiles, today vs R1/R2 variants)
./run_sessions2.sh   # batch A2 + C -> out/A_k30_s10 ... out/C_*   (cap sensitivity, payers)
./run_sessions3.sh   # batch A3 -> out/A_*_rec, A_k30w_base       (recommended setting)
./run_afk.sh         # batch B  -> out/B_*            (R3 AFK-safe automation)
python3 -I analyze_ret.py out <labels...>        # tables (sessions or AFK mode, chosen by the runs)
python3 -I apicheck_ret.py ../../../tools/API-Dump.json > out/apicheck_out.txt
```
All runs `rc=0` (`out/run_*_log.txt`). Identity: `out/id_human.txt` equals `out/base_human.txt` except the label
line (`diff`), and both reproduce the audit's a_human stages.

## Appendix A. Roblox APIs named (all in `tools/API-Dump.json`, version `0.741.19.7411056`)

`python3 -I apicheck_ret.py ../../../tools/API-Dump.json` → `out/apicheck_out.txt`: **52 checked, 0 missing**.
Used in this proposal:
- `Players:GetFriendsAsync` (Yields) — R4, R6. **Not** `Player:IsFriendsWith` / `Player:GetFriendsOnline`: both are
  tagged *Deprecated* in this dump.
- `Model:PivotTo` — R4 VISIT move inside the place (no `TeleportService`).
- `SocialService:CanSendGameInviteAsync`, `SocialService:PromptGameInvite(player, experienceInviteOptions)`,
  `ExperienceInviteOptions.LaunchData`, `Player:GetJoinData`, `SocialService.GameInvitePromptClosed` — R8.
- `ExperienceNotificationService:CanPromptOptInAsync`, `:PromptOptIn`, `.OptInPromptClosed` — R8. The dump has no
  engine call that *sends* a notification (members: InvokeOptInPromptClosed, PromptOptIn, CanPromptOptInAsync,
  OptInPromptClosed, PromptOptInRequested) → sending is [U] / outside the engine.
- `SocialService:GetUpcomingExperienceEventsAsync`, `:PromptRsvpToEventAsync`, `:GetEventRsvpStatusAsync` — R8.
- `BadgeService:AwardBadgeAsync`, `:UserHasBadgeAsync` — R2, R4, R8 (ids 0 = off).
- `DataStoreService:GetOrderedDataStore`, `OrderedDataStore:GetSortedAsync`, `:UpdateAsync`, `DataStorePages:GetCurrentPage`,
  `GlobalDataStore:GetAsync` — R6 (the same calls LeaderboardService uses today).
- `AnalyticsService:LogCustomEvent` — R1/R3 tuning.
- `Player.Idled` — R3 optional AFK parity. The idle-kick time is [U].
- `TextService:FilterStringAsync`, `TextFilterResult:GetNonChatStringForBroadcastAsync` — already used for names
  (`TextFilter.module.luau:12-13`), no new text.
- `Workspace:GetServerTimeNow`, `ProximityPrompt.Triggered`, `Instance:SetAttribute` — existing patterns.
- Not used, checked only: `PolicyService:GetPolicyInfoForPlayerAsync` (its result keys are not in the dump [U]; no
  feature here needs it because nothing random is sold), `MemoryStoreService:GetSortedMap`, `MessagingService`
  (cross-server features were left out on purpose: server-local is simpler and safer).

## Appendix B. Files (all under `design/logic2/sim_retention/`)

- `make_sim.py` → `sim.luau` (built from `sim_audit_copy.luau`, the audit simulator byte copy).
- `run_sessions.sh`, `run_sessions2.sh`, `run_sessions3.sh`, `run_afk.sh`.
- `analyze_ret.py` (tables), `analyze.py` (audit copy, unused here), `apicheck_ret.py`.
- `out/tables_A.md`, `out/tables_B.md`, `out/tables_C.md`, `out/apicheck_out.txt`, `out/*.txt` (raw runs),
  `out/A_k30w_base_patternbug.txt` (first 5-day run with a day-counter bug in the sim, kept for the record, not used).
- `src_snap/` (+ `src_snap.time`, `src_snap.md5`), `gen/`.
