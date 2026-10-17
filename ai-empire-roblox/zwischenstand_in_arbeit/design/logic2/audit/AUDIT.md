# AI Empire: game-loop audit (logic2)

Date: 2026-10-17. Author: logic2 audit agent. Status: read-only design input for LOGIC2_SPEC (no game file changed).

**What this is.** How the game really plays today, measured on the shipped code, not on the specs. The six questions of
the brief are answered in sections 2–7; section 8 ranks the top 10 weaknesses.

**Sources and citation rules.**
- Code: `src/<path>:<line>` means the snapshot `design/logic2/audit/sim/src_snap/<path>`, a byte copy of `work/src`
  taken 2026-10-17 09:21:49 UTC (md5 list in `sim/src_snap.md5`). Other agents edit `work/src` right now (round 2b
  itinerary fix, shop previews), so later line numbers may drift a few lines.
- Simulations: `sim/out/<run>.txt`, tables in `sim/out/tables.md` (all under `design/logic2/audit/`). How they were
  made: section 1.
- Renders: `out/menu/*.png` (guiprev previews from the real UI tree, "not a Studio screenshot").
- Every claim cites code, a sim file or a command. Things I could not verify are marked **assumption** or **unsure**.
- Nothing here was run in Roblox Studio.

---

## 1. Method: the economy simulator

**Which simulator.** The project's current economy simulator is `agents/shop2_design/sim_shop2.luau` (header lines
1-36). It loads the real `work/src` modules into the headless Roblox mock (`harness/mock.luau`) and plays the game
through the real remote handlers (`StartTraining`, `ReleaseModel`, `BuyGPU`, `UpgradeOffice`, ...). In `--real` mode it
runs the game's own auto-HR, B2B pipeline, auto-price, Save mode and rack faults. The shop package re-ran it this
morning (`agents/shop2/sim/out/table.md`, 09:02 UTC). Older copies (`agents/econ/sim.luau`, `agents/verify_sim`,
`agents/menu_sim_new`) are earlier versions of the same bot.

**My copy.** `design/logic2/audit/sim/sim.luau` = `sim_shop2.luau` with `PATCHES = {}` (no shop patches; the shop code
is in the sources now), plus audit counters only:
- every successful player remote is logged (`ACT` lines);
- `EmpireMath.nextGoal` is recorded every minute: goal id, HUD ETA, cash, net, staff, clients (`GOAL` lines);
- `--afk MIN` / `--afkstage N`: no player decisions after minute MIN or once office stage ≥ N (automation keeps running);
- `--gpucap`: the bot buys GPUs only when servers are > 85 % full (no "spare slot" buys; a thriftier player).

**Validation.** My `a_bot` run (think 1) gives stages 7.5 / 34.7 / 83.0 / 168.8 min, identical to the shop package's
`ship_base` (`agents/shop2/sim/out/table.md` row 1). My `a_human` run (think 30) gives 12.5 / 38.5 / 92.0 / 174.5,
identical to their `r2_slow_base`. So the snapshot equals the code the shop package verified.

**Player profiles (all non-payers, seed 4242, server start 16:53 unless noted).**

| Run | Profile | Command (in `sim/`) |
|---|---|---|
| `a_bot` | active, acts the second something is possible (upper bound) | `--think 1 --minutes 300` |
| `a_human` | active human: looks every 30 s | `--think 30 --minutes 240` |
| `a_human_gpucap` | active human, buys GPUs only when servers are full | `--think 30 --gpucap` |
| `a_human_s7` | active human, other seed and start hour 12:00 | `--think 30 --seed 7 --hour 12` |
| `semi120` | semi-idle: checks in every 2 min | `--think 120` |
| `semi_gpucap` | semi-idle: checks in every 5 min, thrifty GPUs | `--think 300 --gpucap` |
| `semi`, `semi_s7` | semi-idle every 5 min with the bot's greedy GPU rule | `--think 300` |
| `afk_tut` | plays the tutorial (3 min), then stays connected and does nothing | `--afk 3` |
| `afk_hq` / `afk_s3` / `afk_s4` | plays actively until stage 2 / 3 / 4, then AFK | `--afkstage 2/3/4` |

Run: `design/logic2/audit/sim/run.sh` and `run2.sh` (all `rc=0`, 20-419 s each, logs `sim/out/run_log.txt`,
`run2_log.txt`); tables: `python3 -I analyze.py out <runs>` → `sim/out/tables.md`.

**What the bot does not model (limits).** It never walks, drives, flies, reads a screen or opens a menu; reaction
time is only `--think`. It uses the Recommended release price and the game's auto-price. Its research/hardware
rules are its own (`sim/sim.luau` capacityUpgrade 661, tryHardware 697, tryResearch 769); a real kid may play worse (slower stages) or spend differently. The bot
decisions are therefore an **upper bound on decision opportunities**, not a measure of fun.

---

## 2. Every implemented system and what the player actively does in it

Economic weight comes from the sim ledgers (`sim/out/semi.txt` / `a_human.txt`, "income" lines).

| System | What the player actively does | What runs by itself | Weight | Evidence |
|---|---|---|---|---|
| **Model Studio / Lab** (design + training) | picks product line, brain size (5), focus, recipe (Balanced / Quick / Deep), name, data plan; or taps the SUGGESTED tile; starts training; answers a training event (2 choices, 25 s, then default); watches reveal; launches | training progress; ageing of live models (−8 fit over 60 min of play) | consumer + API market = 86 % of income at min 45-60, 77 % at 120-180 (`semi.txt`) | `src/ServerScriptService/Server/Services/AIModelService.module.luau:458,619,657,806-812`; `src/ReplicatedStorage/Shared/Config/ModelConfig.module.luau:43-89,151-152,162-180,265-267`; `.../Config/MarketConfig.module.luau:169`; `design/LAB_SPEC.md` §2 |
| **Data** | buys data packs or scrapes for free | curators add tokens (300k/s each, x duty) | small cost line | `src/.../Services/DatasetService.module.luau:19,31`; `src/.../Services/EmpireService.module.luau` (curator block in `Empire.tick`) |
| **Market / pricing** | launches at the Recommended price; may override price, retire a model; 1-4 lines by stage | auto-price re-prices live models (default on); shared server demand | – | `src/.../Services/PricingService.module.luau:2-14`; `.../Config/MarketConfig.module.luau:167,171` |
| **Clients (B2B)** | *pin* or *skip* a client; optionally stand in the client's office and "Start meeting" (+0.15 trust) | everything else: founder/field-rep trips, trust, signing, daily retainers, renewals, hotel nights, guest-house hosting | 13-19 % of income mid/late + one-off pilot fees | `src/.../Services/EmpireService.module.luau:584-596` (pin/skip), `src/ReplicatedStorage/Shared/CompanyOps.module.luau:43,749-757,811-990` |
| **Staff / HR** | optional: HR budget 25/40/55 %, auto-HR on/off, night shift per role (stage ≥ 3), apprentices, fire, invite + interview applicants in the visitor lounge | auto-HR hires one person every 20 s within budget; vacations, sick days, unpaid leave | wages 26-39 % of income (`a_human.txt` wage% column) | `src/.../Services/EmpireService.module.luau:199-218,506-545`; `src/.../CompanyOps.module.luau:54,548-560`; `src/.../Services/RecruitingService.module.luau:1-33,55-56` |
| **Compute / GPUs** | buy / sell / swap GPUs, cooling level, training-vs-studio share | rack faults (6 % per GPU per game day) repaired by IT | caps users served; spare GPUs only speed training | `src/.../Services/ComputeService.module.luau:31-94`; `src/.../CompanyOps.module.luau:77` |
| **Research / Lab levels** | starts 8 research projects, then 10 Lab levels (+1 core stat each) | research points accrue | – | `src/ReplicatedStorage/Shared/Config/EmpireConfig.module.luau:23-32`; `src/.../CompanyOps.module.luau:478,487-489` |
| **Office / campus** | buys the next of 5 stages ($27k / $100k / $380k / $1.9M; stage 2 also needs the first signed client); retail level ($12k/$32k/$85k); snacks; cosmetic cars ($16k-$110k) | operations staff, rent, lunch, guest house income ($2,160/day) | office = the main goal and money sink | `src/.../Config/EmpireConfig.module.luau:7-13`; `src/.../Services/EmpireService.module.luau:103-115`; `src/.../Config/CampusConfig.module.luau:15-29,36`; `src/.../CompanyOps.module.luau:120` |
| **Trips / itinerary** | when the assistant calls: tap "Go" (or setting "join automatically", default off), ride along, "Start meeting", hotel check-in, "Fly home now"; may also buy a $700 return ticket and fly alone | the economic trip runs on its own clock either way | **none** except +0.15 trust per joined meeting | `src/.../Services/ItineraryService.module.luau:1-30` ("the economy is the same either way", line 7; "never touches the economy trip", line 24); `src/.../Services/CityService.module.luau:7-13,89` |
| **Drivers / jet** | calls a chauffeur on the phone for a ride; buys the jet ($900k, stage ≥ 4) | drivers drive field staff; jet flies abroad trips (1.5 days, +0.05 trust) | jet = "a money sink that adds convenience, not income" | `src/.../CompanyOps.module.luau:52,115-118`; DriverService actions (`grep` of `src/.../Services/DriverService.module.luau`) |
| **Phone / assistant** | reads news, calendar, inbox; chats with own models (TextGenerator or a labelled demo reply); calls the driver; toggles auto-trips | the assistant writes briefings and recommendations | flavour + information | `src/.../Services/PhoneService.module.luau:16-20,648`; `src/.../Services/AssistantService.module.luau:534,820` |
| **Tutorial / menu / goals** | 5-step "First steps" guide; Menu with 6 sections / 24 tabs; Next-goal card (13 goals); 12 one-time quests ("Collect $X"); daily grant | – | quests ≈ $77k total | `src/.../Shared/TutorialMath.module.luau:20,35-48`; `src/StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Computer.module.luau:63-76`; `src/.../Shared/EmpireMath.module.luau:205-231`; `src/.../Config/EmpireConfig.module.luau:36-49` |
| **Shop (Robux)** | nothing yet: all 23 products have `id = 0`, so nothing is offered until the owner creates ids | – | 0 for every player today | `src/ReplicatedStorage/Shared/Config/ShopConfig.module.luau:63-113,152,261` |
| **Studio projects** | builds a website / shop / game bot / workflow for 5 client briefs (each once per game day of play, reward x0.5 = $1,750-5,500) | gallery "visitors" grow by formula | 0-1 % of income | `src/.../Services/StudioService.module.luau:15-18,114`; `src/.../Config/StudioConfig.module.luau:3-17` |
| **Test arena** | runs a courier test of a model against an NPC lab's model | – | **no money, no progress** (only `arenaBest` for a leaderboard) | `src/.../Services/ArenaService.module.luau:27-43,59-67` |
| **Talk** | talks to staff and visitors (authored lines) | – | flavour | `src/.../Services/TalkService.module.luau:484` |
| **Leaderboard** | – (best stat per category, global when DataStores work) | – | – | `src/.../Services/LeaderboardService.module.luau:7-22` |

**Bottom line of section 2.** Only four systems carry the economy: the Model Studio (what to train), the market
(launch it), the office purchase, and (indirectly) GPUs. Clients, staff, trips, drivers, hotel, jet, phone, talk,
arena and studio either run by themselves or have no economic effect. The player's real lever on clients is the stat
of the best live model (`CompanyOps.module.luau:758-762` `eligible`).

---

## 3. Simulation results (non-payers)

### 3.1 Time to each office stage and income

Minutes of play from founding. "Done" = minute the Next-goal card says "Every goal reached"
(`src/.../UI/GoalText.module.luau:148`).

| Run | Founder HQ | Startup Campus | Innovation Campus | Global HQ | Done | Revenue $/min at 60 / 120 / 180 | Net $/min at 60 / 120 / 180 | Recurring revenue per hour h1 / h2 / h3 |
|---|---|---|---|---|---|---|---|---|
| a_bot (think 1) | 7.5 | 34.7 | 83.0 | 168.8 | 191 | 42,482 / 80,773 / 78,836 | 26,913 / 49,730 / 40,821 | 1.28M / 3.65M / 4.76M |
| a_human (30 s) | 12.5 | 38.5 | 92.0 | 174.5 | 210 | 39,971 / 80,597 / 73,671 | 25,147 / 49,558 / 38,045 | 1.10M / 3.42M / 4.72M |
| a_human_gpucap | 10.0 | 31.5 | 81.5 | 167.0 | 193 | 44,560 / 74,187 / 84,173 | 28,662 / 43,394 / 44,205 | 1.31M / 3.67M / 4.73M |
| a_human_s7 (12:00 start) | 14.0 | 33.0 | 81.0 | 164.5 | 203 | 51,096 / 91,464 / 100,391 | 35,597 / 61,131 / 59,206 | 1.22M / 3.77M / 4.88M |
| semi120 (2 min) | 12.0 | 28.0 | 78.0 | 174.0 | >240 | 40,307 / 78,658 / 74,291 | 24,747 / 47,645 / 38,547 | 1.08M / 3.71M / 4.67M |
| semi_gpucap (5 min) | 10.0 | 50.0 | 90.0 | 175.0 | 200 | 26,670 / 72,619 / 71,744 | 14,848 / 41,910 / 36,862 | 0.70M / 2.99M / 4.65M |
| semi (5 min, greedy GPUs) | 10.0 | 50.0 | 100.0 | not in 240 | – | 23,224 / 62,952 / 72,380 | 12,653 / 33,248 / 41,812 | 0.67M / 2.64M / 4.56M |
| afk_tut (AFK after 3 min) | never | – | – | – | – | 4,205 / 4,004 / 3,998 | 3,642 / 3,439 / 3,433 | 0.27M / 0.27M / 0.28M |
| afk_hq (AFK at stage 2) | 7.5 | never | – | – | – | 4,374 / 4,307 / 4,237 | 1,419 / 1,352 / 1,282 | 0.29M / 0.27M / 0.27M |
| afk_s3 (AFK at stage 3) | 7.5 | 34.7 | never | – | – | 25,317 / 23,819 / 23,079 | 12,631 / 11,461 / 10,744 | 1.12M / 1.54M / 1.48M |
| afk_s4 (AFK at stage 4) | 7.5 | 34.7 | 83.0 | never | – | 42,482 / 54,202 / 43,697 | 26,913 / 25,844 / 16,316 | 1.28M / 3.20M / 3.10M |

Source: `sim/out/tables.md` "Stage times and income"; done minutes from the "Next-goal timeline" of the same file.

**What the table says.**
1. **Active vs semi-idle barely differs.** Global HQ at 167-174.5 min for active humans, 174.0 for a 2-minute and
   175.0 for a 5-minute check-in (thrifty GPUs). The bot that acts every second is only 5 % faster (168.8).
2. **The run ends at about 3.2-3.5 h of play.** After Global HQ only "All 4 lines at 90+", "Lab level 10" and the
   jet are left, and those are already met or cheap; then "Every goal reached" (a_human: minute 210).
3. **AFK players are frozen, not slowly growing.** Revenue stays flat for hours (afk_tut $4,000-5,400/min from minute 10 to 180) and net falls when automation keeps hiring (section 7.4).
4. The "semi" stall at stage 4 is mostly a bot artefact: with the greedy GPU rule it spent $3.82M on hardware while
   servers were 5-8 % used (`sim/out/semi.txt` ledger "hardware out 3,819,526"; "cap use 8 %" at minute 180). With
   the thrifty rule the same player reaches Global HQ at 175 min (hardware $549k, `semi_gpucap.txt`). The real game
   allows the same over-buying (section 7.9).

### 3.2 Longest waits

Duration of each Next-goal (minutes the same goal stays on the card), `sim/out/tables.md` "Next-goal timeline":

| Goal | a_human | a_human_gpucap | semi_gpucap | What the player can do meanwhile |
|---|---|---|---|---|
| Train / release / first client | 0→6 | 0→6 | 0→9 | tutorial; the CloudDesk pilot is scripted (`CompanyOps.module.luau:42`) |
| Founder HQ $27k | 6→13 | 6→10 | 9→10 | – |
| Second product line | 13→17 | 10→11 | 10→20 | train + launch a 2nd model |
| Startup Campus $100k | 17→39 (22) | 11→32 (21) | 20→50 (30) | train successors, buy GPUs, research |
| First region client | 39→67 (**28**) | 32→52 (20) | 50→70 (20) | nothing direct: field reps are auto-hired and travel by themselves; only a model with the right stat helps |
| Innovation Campus $380k | 67→92 (25) | 52→82 (30) | 70→90 (20) | successors, Lab levels |
| Global AI HQ $1.9M | 92→175 (**83**) | 82→167 (**85**) | 90→175 (**85**) | refresh trainings (models already at 99), GPUs |
| Company jet $900k | 175→210 | 167→193 | 175→200 | wait |

The single longest wait is **Innovation Campus → Global HQ: 83-86 minutes** in every active and semi-idle run, in a
phase where staff is capped (128 at stage 4, reached ~120 min: `a_human.txt` row 120) and every model is already
99.0 (first 99.0 release at 115.5 min, all four lines at 99 by 139 min: `a_human.txt` events).

### 3.3 Is the HUD's "~98 min" typical?

The mid-game HUD preview (`out/menu/phone_hud_normal.png`, dump `agents/menu/prev4/phone_menu_home_mid.dump`) shows
"Innovation Campus $380,000 · $74.3K / $380K · ~98 min" with "+$67.3K/day" and a SAVE MODE badge. That is a
**synthetic test state**, not a sim: $67.3K per game day = $3,365/min net. In the sims the net at Startup Campus is
$24.7-35.6K/min at minute 60 (table 3.1), 7-10x more.

HUD ETA while the office goal is shown (minutes; formula `(price + 2·reserve − cash) / net per minute`,
`src/ReplicatedStorage/Shared/EmpireMath.module.luau:200-203`):

| Run | Innovation Campus: ETA median (p10..p90) → real | Global HQ: ETA median (p10..p90) → real |
|---|---|---|
| a_bot | 11 (2..14) → 28 | 30 (8..53) → 86 |
| a_human | 9 (2..12) → 25 | 28 (7..51) → 83 |
| a_human_gpucap | 10 (2..13) → 30 | 31 (9..53) → 85 |
| semi120 | 11 (1..18) → 30 | 32 (8..60) → 96 |
| semi_gpucap | 4 (0..11) → 20 | 32 (3..47) → 85 |

So: **"~98 min" is not typical for Innovation Campus** (no run showed more than ~18 min at p90), but the real time
to the *next* big goal is. And the ETA is **2.5-3x too optimistic**: it assumes every dollar of net profit is saved,
while the player keeps paying for trainings, GPUs and Lab levels, and auto-HR fees are one-offs outside "net". The
SAVE MODE badge next to "~98 min" cannot happen in the real game: Save mode is only on when the next office is < 8
minutes of net profit away (`src/.../CompanyOps.module.luau:57,538-546`).

---

## 4. Decisions per 10 minutes, by phase

"Real decision" = a remote that changes the company by choice: StartTraining, ReleaseModel, Buy/SellGPU,
UpgradeCooling, StartResearch, Lab level, UpgradeOffice, buyJet, ResolveEvent, BuildProject, ImproveModel,
UpdatePricing. "Chores" = ClaimQuest, ClaimDaily, BuyData, DeliverProject, PublishProject. "Decision moment" =
a distinct 0.1-minute slot with at least one real decision. Full table: `sim/out/tables.md` "Player actions".

| Phase (stage) | a_human: decisions / moments per 10 min | longest gap (min) | a_human_gpucap | semi_gpucap (check-in every 5 min) | Main decisions |
|---|---|---|---|---|---|
| 1 Garage (0-10/12 min) | 10.4 / 9.6 | 3.0 | 10.0 / 8.0, gap 2.5 | 5.0 / 3.0 | first models, first GPUs, studio briefs |
| 2 Founder HQ (~25 min) | 14.6 / 9.2 | 4.0 | 12.1 / 9.3, gap 7.0 | 6.2 / 2.0 | train+launch, research, GPUs |
| 3 Startup Campus (~50 min) | 17.8 / 12.1 | 7.0 | 18.4 / 13.2, gap 7.0 | 7.0 / 2.0 | train+launch (21 pairs), GPUs, Lab levels |
| 4 Innovation Campus (~85 min) | 7.4 / 5.6 | 13.5 | **5.3 / 4.4, gap 18.5** | 4.8 / 1.6, gap 10 | refresh trainings, GPUs |
| 5 Global HQ | 8.2 / 7.3 | 17.5 | **2.5 / 1.8, gap 24.0** | 3.0 / 1.7, gap 10 | GPUs (35 of 53 in a_human), refreshes |


Reading it:
- **Early and mid game (stages 1-3) are busy**: a decision moment every ~50-65 s for an active player (9.2-12.1 moments per 10 min). Training is
  never the wait: train → launch takes 1.7 min in the garage and 0.5-0.6 min from stage 3 on (computed from the
  `a_human.txt` event log; `ModelConfig.TRAINING.minSeconds = 12`, `ModelConfig.module.luau:148`).
- **The late game collapses**: with sensible GPU buying, stage 5 has 2.5 decisions per 10 min and gaps up to 24 min.
  Most of what is left is "train the same 99.0 model again" (`a_human.txt`: Nova41-43 all "ov 99.0") or "buy another
  GPU".
- **Many "decisions" have one sensible answer.** UpgradeOffice has no alternative, launches use the Recommended price,
  B2B picks itself, HR hires itself. In a_human, 79 of 350 logged actions are BuyGPU and 90 are studio-brief actions (Build/Deliver/Publish, 30 each), versus 55 training starts (`grep -c` / `uniq -c` of `ACT` lines in `a_human.txt`).
- **A 5-minute check-in finds something to do almost every time** (decision moments 2.0 per 10 min = every check-in in stages 2-3, 1.6-1.7 in stages 4-5) and still
  reaches Global HQ as fast as an active player (175.0 vs 167.0-174.5 min). The game rewards being *connected*, not
  being *active*.
- Training events: 9-10 per run (`ResolveEvent` count, a_human / a_human_gpucap); they time out to a default after
  25 s (`ModelConfig.module.luau:151-152`), so they are not a real stake either.

---

## 5. What makes a player come back tomorrow (today)

| Hook | What it gives | Evidence |
|---|---|---|
| Daily grant | $1,000 + $500 per streak day, max $4,000 at day 7, +15 research points; resets 00:00 UTC; manual claim (Home "DAILY" button) | `src/.../Services/EmpireService.module.luau:158-168`; `src/.../UI/Apps/HomeApp.module.luau:245-249,503` |
| Offline income | **none**. `e.lastSeen` is written every tick and read nowhere; the economy only ticks sessions that are online; model ageing, trips, contracts and the calendar also stop while away | `EmpireService.module.luau:334` (only write; `grep -rn lastSeen` finds 2 hits: this and the default in `EmpireMath.module.luau:17`); `src/ServerScriptService/Server/Main.server.luau:95`; `src/.../Shared/MarketMath.module.luau:140`; `src/.../CompanyOps.module.luau:651-658` |
| Quests | 12, one-time, all done by minute 54.5 in a_human | `src/.../Config/EmpireConfig.module.luau:36-49`; `a_human.txt` events |
| Studio briefs | 5 briefs, each once per **game day of play** (20 min online), $1,750-5,500 | `StudioService.module.luau:15-18` |
| Market cycles | a 4-state cycle every 300 s of server time (±12-20 %) — not a daily thing | `EmpireConfig.module.luau:50-64` |
| Events, seasons, badges, invites, notifications | **none** in code: no BadgeService, SocialService (invites) or ExperienceNotificationService calls (`grep -rln` over the snapshot: 0 files), although all three exist in `tools/API-Dump.json` | command output in this audit |
| Shop daily limits | boosts ≤ 4 / UTC day — only for payers, and the shop is empty today | `ShopConfig.module.luau:152` |

Size of the daily grant vs income: $4,000 is 4-10 seconds of net profit at stage 3-5 (net $25-60K/min, table 3.1).
Session math: because nothing happens offline, a kid who plays 30 min a day needs about 6 days of sessions to reach
Global HQ (~170 min of play) and has seen everything on day 7 (~200 min) — the same day the streak maxes out.
**Assumption (unsure):** Roblox disconnects players after about 20 minutes without input; the API dump only confirms
that `Player.Idled` exists (`tools/API-Dump.json`, class Player, event Idled). If true, an AFK player stops earning
after ~20 min, and the afk_* runs above are an upper bound.

---

## 6. Multiplayer: what players can do with / against each other today

| Interaction | What really happens | Evidence |
|---|---|---|
| Shared market | other players' live models compete for the same consumer/API demand, weighted 0.15 of an NPC lab | `src/.../Config/MarketConfig.module.luau:174`; `src/.../Shared/MarketMath.module.luau:116,134` |
| Effect of a second company | two non-payers on one server: Global HQ 173.5 vs 168.8 min alone; a heavy payer next to a non-payer slows the non-payer by 5.0 % | `agents/shop2/sim/out/table.md` rows ship_duo@2, ship_base; `agents/shop2/sim/out/bounds.txt` |
| Buy API access to another player's model | buyer pays `sub×100 + api×50` (≥ $100) for one game month and gets up to +3 research points/s; provider gets the fee | `src/.../Services/MarketService.module.luau:59-89`; `EmpireService.module.luau:330-333` |
| Guest card | give a player a 1-hour card to walk through your office (founder rooms and labs stay private) | `src/.../Services/FacilityService.module.luau:260-266` |
| Snack counter | a visitor buying snacks at your counter gives you 55 % of the price ($18-65 items) | `FacilityService.module.luau:243-246`; `CampusConfig.module.luau:24-29` |
| Shared world | one shuttle timetable per server, shared airport and Port Meridian; two founders visiting the same client get separate seats | `src/.../Services/ItineraryService.module.luau:37,359` (SeatSet) |
| Leaderboards | best overall / coding / math / reasoning / creativity / arena score, global via OrderedDataStore | `LeaderboardService.module.luau:7-22,36-41` |
| Test arena | against an NPC lab's model, never against a player | `ArenaService.module.luau:35-38` |
| Not present | co-op companies, trading, contracts between players, PvP races, server events, friend invites, parties | absence in the remotes list (`grep -rn "Remote.bind("` over `src/ServerScriptService/Server/Services`: 44 binds, none of these) |

Verdict: multiplayer is **co-presence**. By design (CORE_SPEC 9.7 "Decision: PLAYER_RIVAL_WEIGHT = 0.15") other players
can never matter more than 15 % of an NPC lab, so nobody is a rival and nobody is a partner. Leaderboards saturate:
every core stat is capped at 99 (`EmpireMath.module.luau:159`), and every sim run had 99.0 models by ~2 h, so all
veterans tie at the top of "overall".

---

## 7. Dead ends, confusing, unfair or boring parts (with evidence)

### 7.1 The content ends after ~3.5 hours
- All 8 research projects by minute 56.5, all 12 quests by 54.5, Lab level 10 by 126.5, first 99.0 model at 115.5,
  Global HQ 174.5, jet 210, then "Every goal reached" (`a_human.txt` events and GOAL lines; GoalText:148).
- The goal card's last text is "Keep shipping new versions: models age and rivals never stop" (GoalText:149):
  the only loop left is re-training 99.0 models to reset ageing (`MarketConfig.module.luau:169`).

### 7.2 Model design stops mattering
- Stats cap at 99 (`EmpireMath.module.luau:159`). From ~2 h on every new model is 99.0 regardless of choices
  (`semi.txt` events: Nova17-24 all "ov 99.0"). The Studio's choices (size, focus, recipe) have no target left.

### 7.3 The big world has no gameplay hook
- Airport, Port Meridian, Meridian Grand, drivers, VIP limo and the jet are optional: "the economy is the same either
  way" (`ItineraryService.module.luau:7`), the itinerary "never touches the economy trip ... and never charges
  anything" (line 24). The only effect: +0.15 trust if the founder joins a meeting (`CompanyOps.module.luau:43`,
  `trustGain` line 749-757). The jet is "a money sink that adds convenience, not income" (line 115).
- The owner's new wish (airport + hotel on the other island, "much better") adds more of this world; without a
  gameplay reason to go there it stays sightseeing.

### 7.4 Automation punishes idle players (unfair)
- **Save-mode freeze:** Save mode stops auto-HR at half the desks (`CompanyOps.module.luau:557`) and stays on as long
  as the next office is affordable but not bought. afk_tut: Save mode 100 % of 174 minutes, staff stuck at 3, cash
  $758k in the garage while Founder HQ costs $27k (`sim/out/afk_tut.txt` rows 30-180, GOAL lines "save=true").
  The move needs a manual tap; nothing moves an idle company forward.
- **Hiring without growth:** afk_hq (AFK after the first move) keeps auto-hiring to 13 people while revenue stays flat;
  wages reach 62-66 % of income, net falls to $1,282/min — a third of the garage AFK player's $3,433/min
  (`afk_hq.txt` rows 45-180 vs `afk_tut.txt`). afk_s4: auto-HR fills to 124 staff, models age, servers overflow
  ("cap use 147-149 %"), net falls from $26.9K to $16.3K/min (`afk_s4.txt` rows 60-240).

### 7.5 Being active is not rewarded
- Global HQ: 167.0-174.5 min (active humans) vs 174.0 (2-min check-in) vs 175.0 (5-min check-in) (table 3.1).
  The economy is an idle game that requires the player to stay connected (no offline income, section 5).

### 7.6 The late game is a waiting room
- Stage 4→5 takes 83-86 min with 2.5-5.3 real decisions per 10 min and gaps up to 24 min (section 4).
- Staff is capped at 128 from ~120 min (`a_human.txt` row 120), so revenue plateaus (80.6K at 120 → 73.7K at 180).
- The biggest purchase feels flat: net/min 10 min before the Global HQ move 49,807, 5-20 min after 47,365; Innovation
  Campus 34,370 → 35,556 (`a_human.txt` "office moves").

### 7.7 Clients are not a game
- Trips, trust, signing and renewals are automatic (`CompanyOps.module.luau:811-990`); the player can only pin or skip
  (`EmpireService.module.luau:584-596`). The "First region client" goal lasts 20-28 min with no direct action
  (table 3.2). The first client is scripted to sign on the first visit (`CompanyOps.module.luau:42`).

### 7.8 Misleading or confusing numbers
- HUD ETA 2.5-3x too optimistic (section 3.3).
- "+$67.3K/day" on the HUD and Home (`out/menu/phone_hud_normal.png`, `phone_menu_home_mid.png`) means per game day =
  20 real minutes (`CompanyOps.module.luau:30`), right next to an ETA in real minutes.
- The Save-mode line says "research, Lab levels and big buys wait until the move" (`GoalText.module.luau:231`), but
  the server only pauses auto-HR (`CompanyOps.module.luau:557`) and the assistant's research tip
  (`AssistantService.module.luau:534`); the player can still buy everything.

### 7.9 GPU over-buying is allowed and useless
- Training is already ≤ 1 min from stage 3; spare GPUs above server demand add nothing. The greedy bot spent $3.82M on
  hardware at 5-8 % server use and missed Global HQ in 240 min (`semi.txt`); the same check-in rhythm with thrifty
  buying reached it at 175 min (`semi_gpucap.txt`). **Unsure** how strongly the ComputeApp warns a kid (its "advice"
  texts exist per notes_integration.md "apps fix: compute advice"; not measured here).

### 7.10 Menu overload for kids
- 6 sections, 24 tabs (`Computer.module.luau:63-76`). The first launch (wave 2, ~1.5-2 min of play) unlocks 16 tabs at
  once — Money, My AIs, Lines, Leaderboard, Clients, Staff, Office, Fleet, Campus, Settings, Research and 5 Shop tabs
  (`TutorialMath.module.luau:35-48`); the mid-game preview shows NEW on every rail entry
  (`out/menu/phone_menu_home_mid.png`). Positive: the Home → Today page leads with one Next goal + one idea + one
  DAILY button, which is the right shape.

### 7.11 Chores and dead features
- Studio briefs: 8-15 builds per stage in the bot runs for $1,750-5,500 each while net is $25-60K/min (studio = 0-1 %
  of income, `semi.txt`).
- Test arena: no reward (`ArenaService.module.luau:59-67`, no Economy call).
- Retail upgrade $12k-85k for $24-144/min (`semi.txt` "retail"; `CampusConfig.module.luau:36`).
- Cars $16k-110k: cosmetic (`CampusConfig.module.luau:15-22`).
- Interviews: a hand-interviewed skill-5 hire works 1.2x a skill-3 agency hire (`WorkforceMath.module.luau:19`,
  factor (7+k)/10), but auto-HR hires one person every 20 s up to 240 — one interview every 90-180 s
  (`RecruitingService.module.luau:55`) cannot compete.

### 7.12 Shop gives nothing today
- Every product id is 0 (`ShopConfig.module.luau:63-113`), so the Shop tab shows nothing to buy until the owner
  creates products. Not a bug (project rule), but it means monetisation is untested with real players.

---

## 8. Top 10 weaknesses (ranked by impact on "does a kid keep playing")

1. **No reason to return tomorrow.** No offline progress (`lastSeen` never read), a $1-4k daily grant worth seconds of
   income, no events, badges, invites or notifications. A session player sees everything by day 7.
2. **Content runs out at ~3.2-3.5 h of active play**, and every progression system saturates: research ~57 min,
   quests ~55 min, Lab 10 ~127 min, 99-stat cap ~2 h, Global HQ ~2.8-2.9 h, "Every goal reached" 191-210 min.
3. **Activity is not rewarded:** a 5-minute check-in reaches Global HQ as fast as an active player (175.0 vs
   167.0-174.5 min); B2B, HR, pricing and trips play themselves; most "decisions" have one right answer.
4. **The huge world has no gameplay purpose:** airport, Port Meridian, hotel, limo, drivers, jet and itinerary leave the
   economy unchanged (+0.15 trust per joined meeting is the only effect). New airports/hotels will repeat this
   unless they get a mechanic.
5. **Late-game waiting room:** Innovation Campus → Global HQ takes 83-86 min with 2.5-5.3 decisions per 10 min, gaps up
   to 24 min, staff capped, models at 99, and the $1.9M move gives no immediate net gain.
6. **Automation traps idle and casual players:** Save mode freezes HR forever until the player taps "upgrade"
   (afk_tut: $758k hoarded in the garage); auto-HR keeps hiring while models age, cutting net 40-60 % (afk_hq, afk_s4).
7. **Customers are not a game:** fully automatic pipeline; the player only pins/skips; a 20-28-min "First region client"
   goal with nothing to do.
8. **Misleading feedback:** the HUD ETA is 2.5-3x too optimistic for the big goals; "per day" means 20 minutes; the
   Save-mode text claims a block that does not exist. The "~98 min" preview is a test fixture, not a typical state.
9. **Menu overload:** 24 tabs, 16 unlocked at once after the first launch, NEW badges everywhere; several tabs (arena,
   retail, cars, studio) have no economic value.
10. **Multiplayer is cosmetic:** other players weigh 0.15, a second company changes progress by ≤ 5 %, no co-op, trade,
    PvP or shared goals; leaderboards tie at 99.

Also noted (not in the top 10): GPU over-buying is possible and useless (7.9); Studio briefs are low-value chores
(7.11); the shop is empty until ids exist (7.12).

---

## 9. Reproduce

```bash
cd design/logic2/audit/sim
./run.sh        # 8 runs (a_bot, a_human, semi, afk_tut, afk_hq, a_human_s7, semi_s7, semi120) -> out/*.txt
./run2.sh       # semi_gpucap, a_human_gpucap, afk_s3, afk_s4
python3 -I analyze.py out a_bot a_human a_human_gpucap a_human_s7 semi120 semi_gpucap semi semi_s7 \
  afk_tut afk_hq afk_s3 afk_s4 > out/tables.md
```
`gen/` was built with `python3 harness/make_manifest.py --src design/logic2/audit/sim/src_snap --gen
design/logic2/audit/sim/gen` (181 entries, 167 scripts). Tests of the game were **not run** by this audit (read-only
design task; no game file changed).
