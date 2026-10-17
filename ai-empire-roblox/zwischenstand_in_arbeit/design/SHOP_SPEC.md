# AI Empire: SHOP_SPEC (binding): skip research with Robux, and a bigger AI-themed shop

Date: 2026-10-11. Status: **binding for the builder**, except the items in 0.2, which wait for the lead or the owner.
Paths are relative to `scratchpad/work/src` unless they start with `scratchpad/`. Line numbers are hints only; search
for the quoted names.

This file builds on `scratchpad/agents/shop2_design/design.md` ("design" below: full reasoning, simulator method,
proposed server code `shop2_patches.luau`) and the research notes `scratchpad/agents/shop2_research/{stores,code}.md`.
Where this file and the design disagree, **this file wins** (0.3 lists every difference).

Relation to ONBOARDING_SPEC: this file **replaces** ONBOARDING_SPEC C2 (Shop page layout) and C3 (catalogue and
texts). C1 (placement, "Never" list), C4 (small fixes) and C6 (owner guide) stay and are extended here (5.5, 3.12, 11).

**No product or pass id is created or invented here. Every `id` stays 0 until the owner creates the item on the Creator
Hub.** Every Robux price is a **suggestion**; the game always shows the price Roblox returns (`GetProductInfoAsync`).

Tags:
- **[V]** checked today: code read, API dump, simulator run, a render I looked at, or a source page I opened (URL given).
- **[R]** from the research notes or the design; that agent opened the source (section given).
- **[A]** assumption or design choice that Studio, a playtest or the owner must confirm.

The wish (German teenager, translated): *"Also make it possible to skip the research with Robux, and that you can buy
many more things. Look at what you can buy in the phone game (Build a Phone Empire), adapt it and make it for the AI."*

How the other game is used: only the **categories** that are common across the genre (time skips, timed boosts,
passes, cosmetics, convenience, bundles). Every name, text, icon idea and number in this file is our own and made for an
AI company. No name from the collision list (stores.md 6.4) is used [V: I checked all 23 names against it]. Review
round (same day): no number or text copies the closest Build a Phone Empire item either; two did and were changed
(Identity Kit had 6 extra colours like its "Premium Finishes" pass, Keynote Boost cost 39 like its "Viral Marketing
Campaign", one Kit colour id echoed one of its colour names; 0.3 items 11–12).

---------------------------------------------------------------------------------------------------------------------
## 0. Summary, decisions, sources

### 0.1 Binding decisions
1. **Research skip = "Eureka"**, a developer product granted as a **voucher**. Using one finishes **one research project
   or one Lab level now**: it covers the research points (RP) and the timer, and **the $ price is still paid**. One
   price, no tiers, deterministic, at most 18 uses per save, never sold when it cannot be used (3.1).
2. **Honest size:** a Eureka usually saves 30 seconds to a few minutes (more in the garage, where research points come
   slowly). Every Eureka button shows the saving for that job, and **no Robux (buy) button appears for a saving under
   30 s** (`EUREKA_MIN_SAVING`). A Eureka the player already owns can always be used on any job the server accepts
   (its note then shows the real, maybe small, saving), so a bought Eureka is never stranded. Research is held by cash,
   not by waiting, and **research is not slowed down** to make the skip worth more.
3. **Where the Eureka button appears** (always a secondary button next to the free action, only when it works right
   now, never during the guide, never after an error):
   - Lab → Research: running project card (FINISH NOW · EUREKA) and idle project cards (EUREKA beside START);
   - Lab → Models, Lab level card (LEVEL UP · EUREKA); the **buy** state only while research points are short (a Lab
     level has no timer, so with enough RP a Eureka saves no time); an owned Eureka shows there either way;
   - **Model Studio "Needs research" (7B)**: a lock strip with the free **OPEN RESEARCH ›** and **SKIP RESEARCH ·
     EUREKA**, shown **only when Frontier Architecture is the only thing that blocks 7B** (no VRAM, GPU, data or
     model-limit lock after it, no training running, and the cash covers Frontier and the 7B training). Otherwise only
     the free link (5.2.4). This rule holds in the owned state too; an owned Eureka can always be used in Lab → Research.
4. **Other skip:** "Last Epoch" finishes the running training; the run's one event check happens first, so the chances
   are unchanged. Max 10 a day; offered for Robux only while at least 20 s are left (`LAST_EPOCH_MIN_LEFT`); an owned
   one can be used at any time left.
5. **Timed boosts:** "Keynote Boost" (+20 % app and API income, after market shares, never B2B or other players) and
   "Overclock" (training ×1.5, 12 s floor kept). 15 min of play each, max 4 starts a day each, max 60 min left at once.
6. **Many more things, mostly cosmetic:** Identity Kit (+ a free colour/logo change for everyone), Server Glow, Stage
   Lights, Rooftop Fireworks, AI Gallery, Team Hoodies, Robo Buddy and the Style Collection bundle. The catalogue grows
   from **11 to 23 items**, built in 3 phases.
7. **The Shop page gets 5 sub-tabs:** Home · Speed-ups · Boosts · Style · Extras (5.1).
8. **Not sold** (reasons in 3.13): auto-research pass, extra product line, faster hiring, extra training slot, 2× income,
   RP boosts, luck items, starter pack, consumable bundles, gifts, founder outfits.
9. **Economy:** non-payer byte-identical to today; light payer inside every casual window (with the S1 share for its
   Series A); heavy payer ≥ 0.48× of the non-payer's time per stage; a non-payer next to a heavy payer +5 % to Global
   HQ (section 10). The cash packs need a decision (S1).
10. **No DATA_VERSION bump** (stays 6), **no new remote**; ShopAction gets an optional `target`, EmpireAction gets
    `rebrand`.
11. **Headhunter becomes deterministic** (review): one applicant with skill exactly 4 for the smallest team, fixed
    salary ask, shown before redeeming (3.12). Today it draws skill 4 or 5 (about 73 % / 27 %), a weighted-random role
    and a random ask [V RecruitingService.headhunt/traits/generate], which is a paid random result (R2). The owner
    creates no Headhunter product until this ships (owner guide 11).

### 0.2 Waiting for the lead or the owner (the builder does NOT do these without a "yes")
| # | Question | Default until answered |
|---|---|---|
| S1 | **Cash packs: 10 % / 20 % / 30 % of the next office price, each size at most once per office** (replaces CORE_SPEC 11.7 shares 0.25/0.75/2.0 and ONBOARDING_SPEC O1). Simulated: with today's shares a payer who buys every pack on entering each office reaches Global HQ at **5.7 min**, with the O1 caps at **8.6 min** (10.3). | The once-per-office rule and its save field ship (inert while ids are 0). **`share` values stay as today.** The owner creates **no** cash-pack products until S1 is answered (owner guide 11, step 0). Nothing has been sold yet, so changing the shares breaks no promise to a buyer. |
| S2 | A free **Auto-research** toggle in Lab → Research (not a shop item, 3.13) | not built |
| S3 | Robux prices on the Creator Hub | owner decides; column "R$" in section 2 is a suggestion |
| S4 | Free "Change colour & logo" for everyone (Team → Settings), needed by Identity Kit | built with Identity Kit (phase 1) |
| S5 | Work requests to other packages (lab, life, buildings, staff rigs; 8.4) | phase-2/3 passes keep `ready = false` (not sellable) until their effect ships |
| S6 | Investor Relations stays +10 %; with a Keynote Boost +30 % (added, not multiplied) | keep; inside the heavy-payer bound (10) |

Owner answers (2026-10-12, built by the shop package): **S1 yes** (shares 0.10 / 0.20 / 0.30, once per office; CORE_SPEC
11.7 updated, simulator re-run on the shipped code reproduces 10.2), **S2 not built**, **S3** prices stay suggestions
(every id stays 0), **S4 built** with Identity Kit, **S6 keep**.

### 0.3 What changed against design.md (and why)
1. **Studio "Needs research" gets a conditional Eureka offer** (design: never). The user asked for exactly this, and the
   lead's task names it. The design's two objections are handled: (a) "a Eureka there hits the next lock" → the offer
   shows only when a what-if estimate with Frontier done has no VRAM / NO_GPU / MODEL_LIMIT lock and the cash covers
   Frontier + the 7B training (5.2.4); (b) "a buy button at a lock is pushy" → it is secondary, never the primary,
   next to the free OPEN RESEARCH ›, never during the guide, never after an error, and gone as soon as it would not work.
2. **Unlisted products are confirmed by Roblox's docs** (design: [A]). The Shop page says an unlisted developer product
   "can still be purchased through your own in-game purchase flows" (https://create.roblox.com/docs/production/monetization/shop,
   opened today [V]). A test in the published game stays in the test list (T22) because the docs could change.
3. **Bundle:** hidden in our UI once the player owns any of its parts (design: show a warning line). The bundle text
   no longer quotes a "one by one" sum: a comparison price reads like a discount and goes stale when the owner changes
   a price.
4. **Shop sub-tabs** instead of one long scroll (23 rows ≈ 7 phone screens). The ONBOARDING C2 one-scroll order is
   replaced by 5.1.
5. **Featured tile: cosmetic passes only**, order {Style Collection, Identity Kit, VIP Founder, Founder Suite, Robo
   Buddy, AI Gallery}. Executive Limo left the list (it is a car + perk, not cosmetic). Never a speed-up, boost or cash.
6. **Daily counters** live in `data.shop.daily` (generic, also for Last Epoch); `data.shop.boosts` holds only end
   times. The simulated patch kept `day/used` inside `boosts`; this is a rename with the same behaviour.
7. **New cap: at most 60 min of a boost left at once** (`BOOST_FULL`). It stops a player stacking 4 starts before and 4
   after UTC midnight into 2 h. It can only lower use, so the simulated upper bound stays valid.
8. **"Saves …" uses the peak office-hours RP speed** (`Ops.duty` peak ≈ 1.70 [V CompanyOps.timesheet: max 0.94,
   TS_MEAN 0.5538]), so the shown saving is never more than the real one. The design's "× 4/3" is not the game's
   formula.
9. **Paid colours are a separate list** `CompanyConfig.KIT_COLORS` (first named `PREMIUM_COLORS`, renamed in item 11),
   not part of `COLORS`, so default and random picks (Intro, DesignSteps picker) never select a paid colour; Kit logos
   are appended after `LOGOS`, so saved model looks (emblem index into LOGOS) keep their meaning [V ModelMath.parseLook,
   DesignSteps:353/371].
10. **Shorter texts** so every row fits ≤ 3 lines on the phone without an ellipsis (checked in the mockup).

Review round (critic, same day; each change is also in the section named):
11. **Identity Kit: 8 extra colours, not 6** (2, 3.5). Build a Phone Empire's "Premium Finishes" pass reads "6 exclusive
    colours (Matte Black, Rose Gold, Midnight Green, Sunset Fade, Carbon, Pearl)" [V `shop_spec/raw/bape_passes.json`,
    `displayDescription`]; the same number on the same kind of item looked copied, and the Kit colour id `midnight`
    echoed "Midnight Green", so it became `navy` (since replaced for readability, item 19; no Kit colour id matches one
    of those six names). The internal names
    `PREMIUM_COLORS`/`PREMIUM_LOGOS` became `KIT_COLORS`/`KIT_LOGOS`: "Premium" is also Roblox's paid membership and the
    word must never reach a player.
12. **Keynote Boost 35 R$, not 39** (2): 39 is the price of Build a Phone Empire's "Viral Marketing Campaign"
    (stores.md 1.2), the closest item to a launch-income boost. No other suggested price equals the price of its
    closest item there.
13. **Headhunter deterministic** (0.1 item 11, 3.12): R2 said "no item has a random result", but the existing
    Headhunter has one. Roblox's paid-random-items page lists even partly random paid results ("Potion for ability
    with random duration", "Upgrade spell with some chance of working") [V, opened today].
14. **Eureka text and minimum saving** (2, 5.2): the old text "Saves about 35 s to a few minutes" was wrong at both ends
    (a running project with 5 s left saves 5 s; in the garage the research points alone can take several minutes).
    New text points to the saving shown on the button, and a Eureka is never offered **for Robux** for less than 30 s.
    Lab level Eureka for Robux only while RP are short. Last Epoch for Robux only with ≥ 20 s left (owned vouchers:
    item 20).
15. **Last Epoch: "same chances as waiting", not "same result"** (2, 3.2, 5.3): the final stats roll and a possible event
    are random either way, so the result is not the same, only the chances.
16. **Bundle text is one string** (2, 5.1): the mockup showed a different featured text than section 2, against R3.
17. **Research speed is labelled as office-hours speed** (5.2.2, 5.3): research points come only in office hours
    (`Ops.duty`, 0 at night) while the job timer runs always [V EmpireService.tick]; the old status line "Research runs
    in office hours" was wrong, and an unlabelled "+4.9/s" at night would overstate the speed.
18. **Boost START needs an effect** (3.3, 5.1): Keynote START is disabled with no live AI (+20 % of nothing), and the
    Overclock row says so when the current run already trains at the 12 s minimum.

Review round, part 2 (same critic, resumed after an interruption; checked against `work/src` again):
19. **Identity Kit colours must keep the UI readable** (3.5, T11). The company colour is the accent of the whole UI
    (`Main.client.luau`: `Theme.setAccent(Theme.rgb(def.rgb))`), and primary buttons draw Theme `bg` text on it
    (`Kit.button` primary: `bindAccent(button, "BackgroundColor3")`, `TextColor3 = C.bg`) [V]. The old proposal had
    graphite and navy at 3.0 : 1 against `bg`, ruby 4.45, plum 4.18 (every free colour is 7.1–10.3), so a buyer's
    buttons would become hard to read; and gold was only ΔE 10 from the free amber (a paid colour that looks like a free
    one). New 8: silver, gold, pink, sky, coral, lilac, mint, aqua, each ≥ 7.2 : 1 and ΔE ≥ 20 from every other colour
    [V `agents/shop_crit/tools/kitcolors.py`].
20. **An owned voucher is always usable** (0.1, R6, 4.1, 5.2). The 30 s / 20 s minimums and the "RP short" rule now
    apply to the Robux (buy) state only. Before, a bought Eureka could be stranded: late in the game the RP stock (cap
    100,000 [V EmpireService.tick]) covers every Lab level, so no Lab-level Eureka button would ever appear, while the
    buy guard still counted those levels as uses left and YOUR ITEMS said "Use it in Lab → Research". The simulator's
    bot never had a minimum (it uses a Eureka on every project and Lab level, `make_sim.py` [V]), so section 10 stays
    valid.
21. **Studio offer: nothing else may block 7B** (5.2.4, 5.3, T16). Added "no training running" (the Review then reads
    "TRAINING SLOT BUSY" [V DesignSteps:1112]) and removed the `NO_DATA` exception (the cash check did not count the data
    pack that NO_DATA needs; with 128 GB VRAM it is rare anyway [V ModelMath.plan: under 1e8 tokens]). `withResearch`
    copies three table levels so the snapshot is never mutated.
22. **T4 was not passable** (9): a waited run draws `session.rng` once per loss point before 35 % (`updateLoss`) [V], so
    a seeded skip and a seeded wait do not draw the same number at the event check. T4 now tests the chances (event rate
    and mix over many seeds), which is what the texts promise.
23. **Last Epoch handler exception stated** (3.2): rolling the event and then returning `DECIDE_FIRST` changes state
    while the voucher is kept. That is intended (the roll would come at 35 % anyway) and is the one allowed exception to
    "an error changes nothing".
24. **Robo Buddy parts never collide** (3.10): a player-owned physics model could otherwise be used to push others.
25. **Smaller corrections:** 4.2 no longer claims "no research wait is 15 minutes" (at night RP stop); 8.5 no longer
    lists Headhunter as unchanged (3.12 changes it); 12.8 no longer says Build a Phone Empire has no texts (9 of its 13
    passes have short descriptions; our 23 rows share no 3-word sequence with any of its 42 names or texts
    [V `agents/shop_crit/tools/textcheck.py`]); R5 and 10.3 now say what boosts do to the rankings and what the "max"
    run shows; the Identity Kit icon shows Kit colours, not free ones.

### 0.4 Sources
Opened by me today (2026-10-11):
- https://create.roblox.com/docs/production/monetization: "Users must never be misled, confused, or pressured into
  purchases in ways they did not intend"; "A discount is not genuine if an item is always "on sale" for the same amount
  of Robux."; "Don't use a countdown timer that isn't accurate or automatically restarts for the same item."; "Don't
  claim that a subscription or item is almost out of stock or only available for a short time if it isn't true.";
  "appointment mechanics and timers which can be removed or brought forward may work well on other platforms" (the
  design quotes the rest of that sentence: "…unpopular with Roblox users who take issue with their fun coming to a
  premature end" [R design 1]); "avoid using pushy or urgent messages when interacting with minors" (re-opened in the
  review round, part 2 [V]).
- https://create.roblox.com/docs/production/monetization/developer-products: "A developer product is an item or ability
  that a user can purchase more than once"; "Set the product price in Robux."; "Unlisted developer products never
  appear in the Shop or outside your game."; NotProcessedYet "tries again next time the user joins the game".
- https://create.roblox.com/docs/production/monetization/shop: "Passes are always listed and can't be unlisted."; an
  unlisted product "can still be purchased through your own in-game purchase flows"; "Listing controls whether a
  developer product appears in the in-game Shop or other eligible Roblox surfaces."
- https://create.roblox.com/docs/production/monetization/passes: "Passes let you charge users a one-time Robux fee to
  access special privileges inside your game"; promoted passes on sale "must be greater than 49 Robux and less than 801
  Robux"; "You must manually assign pass privileges to users that purchase your passes." The page does not say where a
  pass price is set (still unverified, as in ONBOARDING C6; re-opened in the review round: the create steps are icon,
  name, description, category, no price step).
- https://create.roblox.com/docs/production/monetization/paid-random-items: probability modifiers include "Luck boosts",
  "Pity systems", "Enhanced resource drops", "Rate-up scrolls"; enhancement examples include "Potion for ability with
  random duration" and "Upgrade spell with some chance of working"; odds must be shown ("you must indicate all possible
  outcomes and the actual numerical odds") [V, re-opened in the review round].
- Build a Phone Empire, Roblox public APIs (saved in `scratchpad/agents/shop_spec/raw/`):
  `https://games.roblox.com/v1/games?universeIds=10767582899` (name "[UPD] 📱 Build a Phone Empire", creator DEVTEC
  STUDIOS), `https://apis.roblox.com/game-passes/v1/universes/10767582899/game-passes?passView=Full&pageSize=100`
  (13 passes), `https://apis.roblox.com/developer-products/v2/universes/10767582899/developerproducts?limit=100`
  (29 products, every `Description` empty, 18 named "[GIFT] …"; none finishes research, the closest are a research
  points pack and an "Instant Development"). What its products actually do is unverified (no descriptions).
- `scratchpad/tools/API-Dump.json`: `MarketplaceService.PromptProductPurchase`, `PromptGamePassPurchase`,
  `GetProductInfoAsync` (Yields; `GetProductInfo` is Deprecated), `UserOwnsGamePassAsync`, `ProcessReceipt` (Callback),
  `PromptProductPurchaseFinished`, `PromptGamePassPurchaseFinished`; `GuiService.ReducedMotionEnabled` (Hidden,
  ReadOnly, NotReplicated); `ParticleEmitter:Emit`; `BasePart:SetNetworkOwner`; `AlignPosition.Mode`,
  `AlignOrientation.Mode`; `RunService:IsStudio`; `Workspace:GetServerTimeNow`.
- Code in `work/src` (files named per section) and the simulator outputs in `scratchpad/agents/shop2_design/out/`
  (tables re-read today; `check_new60.txt` = `check_old60.txt` and `r1_base.txt` = `shop2_research/out/pay_base.txt`
  byte for byte [V cmp]).

From the research notes (the research agent opened them; section given): the genre category table (stores.md 3), the
DevForum pricing and pay-to-win threads (5.1), the refund webhook announcement devforum t/4890339 and the help-centre
refund/EEA articles (4.8), Community Standards "removing functionality for buyers without proper notice" (4.4), the
University of Sydney study (4.9). Nothing about another game in this file goes beyond those notes and the API lists above.

---------------------------------------------------------------------------------------------------------------------
## 1. Rules every item follows

| # | Rule |
|---|---|
| R1 | **Nothing is needed.** Every office, client and research project can be reached without Robux. With no purchase the new code changes nothing (byte-identical simulation, 10.1). |
| R2 | **Deterministic.** No item has a random result or changes a random chance (Last Epoch rolls the training event first, 3.2; Headhunter made deterministic, 3.12). So no paid random items, no odds, no PolicyService. Randomness the game has anyway (the final stats roll of a training) is not bought: a skip only moves it earlier, with the same chances. |
| R3 | **Honest text, identical in the game and on the Creator Hub**: what it does, by how much, what it does not do. |
| R4 | **No pressure.** No timers on offers, no "limited", "deal", "best value", "worth", "sale" or crossed-out prices. A bought boost's running time is real play time and never restarts, so it is not a sales countdown. |
| R5 | **Never against other players or shared state**: no item touches market shares, users, hype, NPCs, B2B trust, trips, the shuttle, day/night, the market cycle or a leaderboard directly. Revenue boosts act after shares (`MarketService` `factor = b.revenue * cycle.revenue * shopFactor(session)`) [V]. Indirect effect, stated honestly: the rankings (`LeaderboardService`) list the best model score ever trained; a payer trains faster and gets there sooner, but every bot, payer or not, reached the 99.0 cap by minute 120 (payers up to 30 min earlier) [V sim outputs, "best" column], and no item changes a score cap or the chances of a single roll. |
| R6 | **Robux buttons appear only where the item acts and only when it would work now** and save a real amount of time (Eureka ≥ 30 s, Last Epoch ≥ 20 s), always secondary next to the free action, behind the gate `ShopMath.offerAllowed` (5.2.1). A voucher the player already owns shows its USE button wherever the server would accept it, whatever the saving (the note shows the real saving), so nothing bought is ever left without a place to use it. |
| R7 | **Anything that can fail later is a voucher.** The receipt only adds a voucher; redeeming runs the normal rules; any refusal keeps the voucher [V ShopService.redeem]. Consumables act at once, so a refunded product has nothing left to take back. |
| R8 | **Never sell more than can be used**: Eureka buy hidden when vouchers ≥ uses left; boosts and Last Epoch buy hidden at the daily limit (4.1). |
| R9 | **Passes are live flags** (`Shop.owns`, re-checked on join) [V ShopService.refreshPasses]. A refunded pass loses its effect; the one exception is a colour/logo the player already chose with Identity Kit, which stays until they change it. |
| R10 | **Context items are Unlisted** on the Creator Hub (Eureka, Last Epoch, Keynote Boost, Overclock, and the three cash packs: fix round 1). Passes cannot be unlisted, so a pass is created only when its feature works (`ready`). |

---------------------------------------------------------------------------------------------------------------------
## 2. Catalogue (23 items: 11 today + 12 new)

Kind: **V** = developer product granted as a voucher, **P** = developer product applied at once, **G** = game pass.
Tab = Shop sub-tab (5.1). Phase: **1** server + UI with existing hooks, **2** needs a client effect in another package,
**3** needs new 3D content. "Listed" is the owner's choice on the Creator Hub (R10). Icon ideas are briefs for the
owner's 512×512 icons and the in-game Kit icons; all are our own.

| key | Kind | Name | Tag | Tab | In-game text = Creator Hub description | R$ sugg. | Listed | Phase | Icon idea |
|---|---|---|---|---|---|---:|---|---|---|
| **eureka** | V | Eureka | Speed-up | Speed-ups | "Finishes one research project or one Lab level right now. Covers its research points and its wait. You still pay its $ price. Every Eureka button in the game shows the time it saves." | 15 | Unlisted | 1 | gold light bulb with a small neuron inside, blue spark |
| **lastEpoch** | V | Last Epoch | Speed-up | Speed-ups | "Finishes your running AI training now, with the same chances as waiting: a training event, if one comes, is decided first. Saves the time left; the button shows how much." | 9 | Unlisted | 1 | screen with a full progress bar and a green tick |
| **keynote** | V | Keynote Boost | Boost | Boosts | "+20 % on your app and API income for 15 minutes of play. Business clients are not boosted. Other players are never affected. Up to 4 a day." | 35 | Unlisted | 1 | stage microphone with a rising arrow |
| **overclock** | V | Overclock | Boost | Boosts | "Your AI training runs 1.5× as fast for 15 minutes of play (never under 12 seconds per run). Up to 4 a day." | 19 | Unlisted | 1 | GPU chip with a lightning bolt |
| **fireworks** | V | Rooftop Fireworks | Cosmetic | Style | "45 seconds of fireworks in your company colour above your HQ. Everyone nearby sees them. Just for fun." | 19 | Listed | 2 | two bursts above a small office block |
| **identityKit** | G | Identity Kit | Cosmetic | Style | "8 extra company colours and 6 extra logo marks for your company and AI models. GPU racks change at once; HQ trim, cars and jet at their next build." | 59 | – | 1 | shield with four dots in Kit colours (gold, pink, sky, mint), never the free ones |
| **serverGlow** | G | Server Glow | Cosmetic | Style | "Your GPU racks run a slow light wave in your company colour instead of a steady glow. Visitors see it too." | 45 | – | 2 | server rack with a light wave |
| **stageLights** | G | Stage Lights | Cosmetic | Style | "Light sweeps and confetti in your company colour when your new AI is revealed. Only you see it." | 39 | – | 2 | two spotlights over a model card |
| **aiGallery** | G | AI Gallery | Cosmetic | Style | "A lobby wall with framed cards of your 3 best AI models and a neon sign with your company name. Updates by itself." | 65 | – | 3 | three gold frames over a neon bar |
| **teamHoodies** | G | Team Hoodies | Cosmetic | Style | "Your hired team wears hoodies in your company colour with your logo. Operations staff keep their uniforms." | 75 | – | 3 | hoodie in the accent colour |
| **roboBuddy** | G | Robo Buddy | Cosmetic | Style | "A small hovering robot in your company colour follows you around the world. Just for fun." | 95 | – | 3 | round hovering robot with an antenna |
| **styleCollection** | G | Style Collection | Bundle | Style | "Identity Kit, Server Glow and Stage Lights in one pass. Looks only. Already own one of them? Then buy the others one by one." | 109 | – | 2 | two stacked cards, gold and violet |
| seed | P | Seed round | Company cash | Extras | "+{amount} company cash now: {share words} the {next office} price. One per office." | 25 (S1) | Unlisted | 1 | small coin stack |
| seriesA | P | Series A | Company cash | Extras | same pattern | 45 (S1) | Unlisted | 1 | coin stack |
| seriesB | P | Series B | Company cash | Extras | same pattern; garage adds "Leaving the garage still needs your first client." | 75 (S1) | Unlisted | 1 | big coin stack |
| headhunter | V | Headhunter | Helper | Extras | "One applicant with skill 4 of 5 applies, for your smallest team. Redeem when a desk is free; the voucher is kept until then." (changed from C3, 3.12) | 39 | Listed | – | person with a star |
| party | V | Team party | Cosmetic | Style | "Balloons, a banner and sparkles in front of your HQ for 3 minutes. Just for fun." (C3) | 25 | Listed | – | two balloons |
| tip | P | Supporter tip | Tip | Extras | "Say thanks to the developer. You get a thank-you note, nothing else." | 25 | Listed | – | heart |
| bigTip | P | Big supporter tip | Tip | Extras | "A bigger thank-you to the developer. Nothing else changes." | 100 | Listed | – | heart |
| vip | G | VIP Founder | Cosmetic | Style | "A gold VIP tag above your character and a VIP badge in your Menu." (C3) | 149 | – | – | crown |
| limo | G | Executive Limo | Car + perk | Extras | "A limousine for your fleet (top speed 78 when you drive; the free car does 64). VIP helicopter transfers are free (normally $2,500)." (C3) | 199 | – | – | limousine side view |
| founderSuite | G | Founder Suite | Cosmetic | Style | "A brass and leather lounge with a fire bowl on your founder terrace. Appears from Founder Headquarters on." (C3) | 199 | – | – | lounge chairs and a fire bowl |
| investor | G | Investor Relations | Gameplay bonus | Extras | "+10 % on your app and API income. Business clients are not boosted. Other players are never affected. Adds to a Keynote Boost (+30 % together)." | 349 | – | – | rising bar chart |

Notes:
- Prices are our own: a skip saves minutes, so it is priced like a snack (9–15); boosts 19–35; cosmetic passes 39–95,
  all under the DevForum's "more than 500 Robux per one gamepass" warning [R stores.md 5.1]. Promoted passes must cost
  50–800 R$ [V passes page], so Server Glow (45) and Stage Lights (39) could not be promoted at these prices; owner's
  choice.
- Review check against stores.md 1–2: no suggested price equals the price of the closest Build a Phone Empire item
  (Keynote moved from 39 to 35). Overclock's 19 R$ for 15 min sits at the low end of the genre range for short boosts
  (Car Dealership Tycoon 19–29 for 15 min, Restaurant Tycoon 3 50 for 10 min), a pattern, not one game's price.
- Share words for cash packs: 0.10 "10 % of", 0.20 "20 % of", 0.25 "a quarter of", 0.30 "30 % of", 0.5 "half of",
  0.75 "three quarters of", 1.0 "the full", 2.0 "twice". Last stage: "(based on the Global AI Headquarters price)".
- Counts per tab: Speed-ups 2, Boosts 2, Style 11, Extras 8.

---------------------------------------------------------------------------------------------------------------------
## 3. Exact effects and server validation

Common: every voucher redeem goes through `ShopService.redeem(session, key, target)` (6.3). Handlers must **not yield**
between their checks and their effect, and return `(true)` or `(false, ERRCODE)`. Any error keeps the voucher.

### 3.1 Eureka (`eureka`, handler `Empire.eureka`, EmpireService)
Run in the simulator as written in `shop2_design/shop2_patches.luau` patch 1 [V sim]. `target` = a research id,
`"lab"`, or nil.

| Case | Rule | Errors (voucher kept) |
|---|---|---|
| no company | – | `NO_COMPANY` |
| `target == "lab"` | tree complete, `labLevel < 10`; `Economy.spend(labCost$, "lab")`; `labLevel += 1`; `Ops.post(e, "Lab level N (Eureka): +1 core stat on future models")`. Research points are **not** taken. | `PREREQUISITE`, `MAX_LEVEL`, `NO_MONEY` |
| a job runs (`e.researchJob`) | `target` must be nil or the running id. RP the job took come back (`e.points = min(100000, e.points + def.points)`), then `completeResearch(session, job.id)`. No cash (it was paid at start). | `RESEARCH_ACTIVE` (target names another project) |
| no job, `target` = research id | known, not done, prerequisite done; `Economy.spend(def.cost, "research")`; `completeResearch(session, id)`. RP are **not** taken. | `BAD_INPUT`, `ALREADY_DONE`, `PREREQUISITE`, `NO_MONEY` |

- **One completion path:** the tick's completion block becomes `local function completeResearch(session, id)`
  (`research[id] = true`, `researchJob = nil`, `xp += 150`, Notify `EMPIRE_NOTICE` "Research complete: {name}"), used by
  the timer and by Eureka. So quests ("Lab breakthrough"), HUD goals, the 7B unlock and the Studio lock update the
  same way. The player sees the same server notice "Research complete: {name}" as after the timer; the client adds no
  second toast for projects (only the Studio adds "7B is unlocked.", 5.2.4).
- Registered in `Empire.init` with `Shop.setRedeemHandler("eureka", Empire.eureka)` (EmpireService may require
  ShopService; ShopService does not require EmpireService [R design 12.1]).
- It never skips a prerequisite and never skips cash (a cash waiver would be a hidden cash pack worth up to $65,000).

### 3.2 Last Epoch (`lastEpoch`, handler `AIModelService.lastEpoch`)
Patch 2 [V sim]:
```lua
function AIModelService.lastEpoch(session: Session): (boolean, string?)
	local training = session.data.training
	if not training then return false, "NO_TRAINING" end
	local event = training.event
	if event and event.pending then return false, "DECIDE_FIRST" end
	if not training.eventRolled then                   -- the run's one event check happens now, same odds
		rollEvent(session, training, workspace:GetServerTimeNow())
		local rolled = training.event
		if rolled and rolled.pending then return false, "DECIDE_FIRST" end
	end
	return AIModelService.finishNow(session), nil      -- existing: final stats roll like a normal finish
end
```
- Why the roll first: a run rolls one event at 35 % progress with a 60 % chance (`ModelConfig.TRAINING eventAt = 0.35,
  eventChance = 0.6`) [V]. Skipping past it without the roll would make bad events rarer: a paid change of odds (R2).
- The final stats roll (`AIModelService` `finish`: `session.rng:NextNumber(-n, n)` per stat) happens as after waiting, so
  the texts say "same chances as waiting", never "same result" [V].
- If the roll brings a decision, the voucher is kept, the normal decision card shows (25 s auto-pick), and the player
  taps Last Epoch again afterwards. This is the one handler that changes state (the event is rolled) and still returns
  an error; intended, because the roll would come at 35 % anyway and its chances are the same.
- Same chances, not the same numbers: a waited run draws `session.rng` once per loss point before 35 % (`updateLoss`),
  so the draw at the event check differs between a skip and a wait with the same seed [V]. Tests check the chances
  (T4), not equal event ids.
- Refinements use the same slot and the same rule. The extra time of the safe event choices is skipped too (that is
  what is bought); their quality and cost effects stay. The confirm sheet says so.
- Registered in `AIModelService.init` with a lazy require of ShopService (load-order safe, like MarketService's
  `shopFactor`) [A: check order].

### 3.3 Keynote Boost and Overclock (`keynote`, `overclock`, handler `ShopService.startBoost`)
| | Keynote Boost | Overclock |
|---|---|---|
| Effect | `Shop.revenueMultiplier` returns `(investor and 1.10 or 1) + 0.20` while active: own **market** (app + API) revenue only, after shares, never B2B, never NPCs [V MarketService.tick] | the local `trainingTick` in AIModelService (not exported today): `rate = min(rate * 1.5, workTotal / ModelConfig.TRAINING.minSeconds)` while active (12 s floor; `EmpireMath.trainingRate` already applies the same floor [V]) |
| Clock | `data.empire.seconds` (company play time: +dt per tick while online, frozen offline) [V EmpireService.tick, PhoneMath note] | same |
| Start | `boosts[key] = empire.seconds + boostLeft + 900` | same |
| Stacking | one rate (+20 %); another start adds 15 min | one rate (×1.5); adds 15 min |
| Caps | 4 starts per UTC day (`DAILY_LIMIT`); a start is refused while > 2,700 s are left (`BOOST_FULL`), so at most 60 min left | same |
| START in the UI (client, 5.1) | disabled with "No live AI right now" while no own model is live (+20 % of nothing) | enabled; when the running training already trains at the 12 s minimum the row shows "This run is already at the 12 s minimum: Overclock would not speed it up." (`ShopMath.trainingFactor` compares the capped rates) |

`startBoost(session, key)`: `NO_COMPANY` → (keynote only) `NO_LIVE_MODEL` when no own model has `status == "live"` →
`BOOST_FULL` → (daily check is generic, 6.3) → set end time → `markDirty(session, true)`. The server check backs the
disabled START; the voucher is kept. Registered in `Shop.init` for both keys (built in, like `party`).

### 3.4 Rooftop Fireworks (`fireworks`, built-in handler in ShopService)
`ShopDecor.fireworks(office, plot.cframe, color)`: 4 anchored launcher parts on the roof edge and `ParticleEmitter`
bursts via `:Emit(n)` [V API dump] in the company colour, 45 s (`ShopConfig.FIREWORKS_SECONDS`), then destroyed like the
party kit. Errors: `NO_PLOT`, `FIREWORKS_ACTIVE`. With `GuiService.ReducedMotionEnabled` nothing changes server-side
(the effect is world content; the property is client-only) [V dump: NotReplicated]. Phone performance: T23 [A].

### 3.5 Identity Kit (`identityKit`, pass) and the free rebrand
- `CompanyConfig.KIT_COLORS` (8, ids letters only because `ModelMath.parseLook` needs `^([%a]+):(%d+)$` [V]):
  `silver {196,202,206}`, `gold {236,186,64}`, `pink {240,128,150}`, `sky {116,182,246}`, `coral {248,140,104}`,
  `lilac {206,158,238}`, `mint {172,248,172}`, `aqua {100,220,240}` (review round, part 2: replaces graphite, ruby,
  ice, navy, plum and sand, and a brighter gold and coral; 0.3 item 19). No id equals a free `COLORS` id or a colour
  name of Build a Phone Empire's "Premium Finishes" (0.3 item 11). Each entry has `pass = "identityKit"`. Code names
  only: the word "Premium" never appears in player text (it is Roblox's paid membership).
- **Readability rule (binding; RGB values may change if they keep it):** the company colour is the accent of the whole
  UI (`Main.client.luau` → `Theme.setAccent`), and primary buttons draw Theme `bg` (15,21,23) text on it (`Kit.button`
  primary) [V]. So every Kit colour needs **contrast ≥ 7.0 : 1 against `bg`** (the free colours are 7.1–10.3) and
  **ΔE76 ≥ 20 from every free colour and every other Kit colour** (a paid colour must never look like a free one). The
  values above give 7.22–14.7 : 1 and ΔE ≥ 20.4 [V `scratchpad/agents/shop_crit/tools/kitcolors.py`]. T11 checks it.
- `CompanyConfig.KIT_LOGOS` (6 glyphs, appended after `LOGOS` for look emblem indexes 9–14). Proposed: "✦", "⬢",
  "◆", "✚", "◐", "⌬" [A: T24 glyph check in BuilderSans; replace any that render as boxes].
- `getColor(id)` searches `COLORS` then `KIT_COLORS`; `isLogo(glyph)` accepts both lists; new
  `CompanyConfig.isKitColor(id)`, `CompanyConfig.isKitLogo(glyph)`, `CompanyConfig.allLogos()`.
  `ModelMath.parseLook` accepts emblem n ≤ #LOGOS + #KIT_LOGOS.
- **Free rebrand for everyone (S4):** `EmpireAction {action = "rebrand", color, logo}` → `CompanyService.rebrand`:
  validates like create; Kit id without `Shop.owns(session, "identityKit")` → `PASS_NEEDED`; runtime cooldown 60 s
  (`REBRAND_COOLDOWN`, `TOO_FAST`); writes `data.company.color/logo`; `PlotService.refresh(session)` (GPU blades
  repaint at once) [V PlotService accent]; HQ trim, cars and jet pick it up at their next build [V accent passed into
  `Design.build`, VehicleService:64, JetService:86, DriverService:215].
- Create (`CompanyService` create), rebrand and `startTraining` look all refuse Kit ids without the pass
  (`PASS_NEEDED`). After a refund the saved choice stays (R9); no new Kit pick.

### 3.6 Server Glow (`serverGlow`, pass, phase 2)
ShopService sets the office attribute `ServerGlow = true` in `refreshOffice` (like `FounderSuite`). PropFxController
(life package) animates blades with `Lit == true` as a wave (company colour → white → colour, 6 s period) instead of
`breathe` when the attribute is set; with `GuiService.ReducedMotionEnabled` it keeps `breathe`. Client only.

### 3.7 Stage Lights (`stageLights`, pass, phase 2)
Lab package, Stages "reveal": when `live.shop.passes.stageLights`, two light sweeps and a confetti burst in the company
colour during the count-up and a gold frame on the reveal card. UI only; only the buyer sees it (text says so).

### 3.8 AI Gallery (`aiGallery`, pass, phase 3)
`ShopDecor.gallery(office, cf, tier)` at a new per-tier `GalleryAnchor` (buildings package, BuildingPlan): 3 framed
cards (name, size, score, look colour + emblem) of the best released models and a neon company sign; refreshed on
`TRAINING_COMPLETE` and on office rebuilds. Company and model names are shown as saved: CompanyService and
AIModelService store them only after `TextFilter.forBroadcast` [V], so no new filtering is needed.

### 3.9 Team Hoodies (`teamHoodies`, pass, phase 3)
EmployeeRigDesign (staff rigs) takes a `hoodie` colour from the session; the pass flag joins the office `StaffKey`, so
`Design.staff` rebuilds the rigs once when it changes [R design 8]. Operations staff keep their uniforms. Perf: T23.

### 3.10 Robo Buddy (`roboBuddy`, pass, phase 3)
Server model (≤ 30 parts) with `AlignPosition` + `AlignOrientation` to the character, network owner = the player
(`BasePart:SetNetworkOwner`) [V dump]; name tag "{Company} Bot" (the saved, already filtered company name, 3.8);
removed on death/leave; hidden while seated (shuttle, jet) [A]. One per player. Every part `CanCollide = false`,
`CanTouch = false`, `CanQuery = false`, `Massless = true` [V dump: BasePart members]: the owner's client simulates it,
so a colliding buddy could be used to push other players.

### 3.11 Style Collection (`styleCollection`, pass, phase 2)
`ShopConfig.PASSES` entry with `includes = {"identityKit", "serverGlow", "stageLights"}`. `Shop.owns(session, key)` is
true if the key's own flag is set **or** an owned pass `includes` it. The shop hides the bundle when the player owns
any part, and hides the parts when the bundle is owned. The contents never shrink after sale; phase-3 items are not
added to it. `ready = false` until Server Glow and Stage Lights ship.

### 3.12 Existing items
| Item | Change |
|---|---|
| Seed / Series A / Series B | **Once per office, enforced on the server** (fix round 1): `grant` pays the cash and records `data.shop.packs[key] = office` only when `packs[key] ~= office`. A second receipt of the same size in the same office (bought outside our UI, from a direct `PromptProductPurchase`, or a double tap before the snapshot hid the chip) is still **never refused** (PurchaseGranted), but pays **no cash now**: it adds `data.shop.packCredit[key] += 1`. On the next office move (`EmpireService.upgrade` → `ShopService.payPackCredits`) one credit per size is paid at **the new office's** `cashFor` and counts as that office's pack (`packs[key] = new office`), so no office ever gets two packs of one size. At the last office a credit cannot be paid (YOUR ITEMS says so). The row shows "Bought for this office ✓" (no buy chip) while `packs[key] == office`, plus "· n more saved for your next office" with credits; YOUR ITEMS shows "{Name} ×n · Paid when you move to {next office}" [OFFICE ›]. The three packs are **Unlisted** (2, 11). Shares 0.10 / 0.20 / 0.30 (S1). Texts from `share` (section 2 notes). ShopConfig comment "Packs save minutes, not hours" → "Packs are a share of the next office price, one of each per office (SHOP_SPEC S1)." |
| Executive Limo | C3 text and tag "Car + perk" (ONBOARDING C4 fix stays) |
| Investor Relations | C3 text + "Adds to a Keynote Boost (+30 % together)." |
| Headhunter | **Deterministic** (R2): `Recruiting.headhunt` keeps the desk/slot checks, then adds one applicant with hidden skill **exactly 4** (loop over serials until `traits(...).k == 4`), role = the department with the fewest people (team + open applications; ties in `EmpireConfig.ROLES` order), `spec` = the first specialty of that role, salary ask fixed at 1.25 (`roundAsk` of the k = 4 base 0.8 + 3 × 0.15). Name, previous employer and confidence/candour stay as generated (flavour; the ask no longer depends on them). The YOUR ITEMS strip shows the result before redeeming: "Finds a skill-4 {role name} (your smallest team)". Text in section 2. Request to the staff package (8.4). Until it ships the owner creates no Headhunter product (11). |
| VIP, Founder Suite, Team party, tips | unchanged |

### 3.13 Not sold (and why)
| Idea | Why not |
|---|---|
| Auto-research pass / research queue | The user wants the game "almost everything automatic" (LOGIC_BRIEF 2) [R design 7]; selling that automation would sell what the user wants free. Recommendation S2: a free toggle. |
| Extra product line slot | `PRODUCT_SLOTS` is a stage gate; one line vs several is −31 % revenue at 180 min (CORE_SPEC 9.6) → a large permanent multiplier |
| Faster hiring, extra training slot, parallel research, +x % RP | staffing/economy changes; RP never bind (design 1); training slot not built |
| 2× income or any permanent multiplier | the DevForum's clearest pay-to-win example [R stores.md 5.1] |
| Hype / users / marketing reach boosts | change market shares → other players (R5) |
| Luck items (better applicants, scores, clients) | paid random items (R2) [V paid-random-items page] |
| Starter pack / "one-time offer" | scarcity pressure (R4) |
| Consumable bundles ("5 Eurekas") | push buying more than can be used (R8) |
| Gift copies | no gift API; the receiver can still buy the real pass and waste Robux; needs a player picker [R stores.md 4.2, 5.1] |
| Founder outfits | the game never dresses the player's avatar (HumanoidDescription only for NPC crowds) [R design 8] |
| Office, trip, shuttle, day/night, rack-repair, apprentice skips | cash is the gate, or shared state, or selling the fix to a problem the game creates [R design 5] |

---------------------------------------------------------------------------------------------------------------------
## 4. Caps and limits

### 4.1 Table
| Item | Cap | Enforced where | Shop buy guard (client, `ShopMath`) |
|---|---|---|---|
| Eureka | 18 uses per save (8 projects + 10 Lab levels) | natural (nothing left to finish) | hidden when `vouchers.eureka ≥ eurekaUsesLeft(data)`; context **buy** buttons only for a saving ≥ 30 s (`EUREKA_MIN_SAVING`); owned-state buttons on every target the server accepts, so each counted use stays usable |
| Last Epoch | 10 per UTC day | `ShopService.redeem` (`DAILY`) | hidden when `dailyUsed ≥ 10 and vouchers ≥ 1`, or `vouchers ≥ 10`; context **buy** button only with ≥ 20 s left (`LAST_EPOCH_MIN_LEFT`); owned state at any time left |
| Keynote / Overclock | 4 starts per UTC day; ≤ 60 min left | redeem (`DAILY`) + `startBoost` (`BOOST_FULL`) | hidden when `vouchers ≥ 4`, or `dailyUsed ≥ 4 and vouchers ≥ 1` |
| Fireworks / Team party | one running at a time | handler | none (always usable later) |
| Cash packs | each size once per office | `grant`: a second receipt in the same office becomes `packCredit[key] += 1` (no cash), paid one per size at the next office move (`payPackCredits`) | hidden when `packs[key] == office` |
| Any voucher | `VOUCHER_MAX = 999` | Template.cleanShop [V] | – |

- `eurekaUsesLeft(data) = #(research ids not done, a running job counts as not done) + (10 − labLevel)`.
- UTC day = `math.floor(os.time() / 86400)` on the server (`deps.now = os.time` in ShopService [V]); the client uses
  `snapshot.serverTime` for the same formula.
- A receipt is never refused: a late Eureka beyond the uses left still grants; YOUR ITEMS then says "Nothing left to
  research. Your Eureka can't be used." (also stated on the Creator Hub text via "one research project or one Lab level").

### 4.2 Why one Eureka price and no tiers
A developer product has one price [V docs]. Tiers ("Eureka S/M/L") confuse children, and the waits are short: a 35–120 s
timer plus the time to earn the RP (usually under 2 min at office-hours speed; longer in the garage, and RP stop at
night). A fixed "skip 15 minutes" tier would be dishonest because the real saving depends on the job and the player's
speed; every button shows its own saving instead.

---------------------------------------------------------------------------------------------------------------------
## 5. UI placement

Sizes follow ONBOARDING_SPEC B3 (canvas 1254 wide; phone s = 0.598, desktop s = 1.021; text ≥ 20 design px = 12 pt
on the phone; targets ≥ 74 px = 44 pt). Colours: `UI/Theme.module.luau` (bg 15,21,23 · panel 23,31,33 · raised
42,52,53 · text 238,239,231 · muted 158,173,168 · dim 117,136,132 · good 129,204,162 · warn 224,189,122 · accent
120,200,174) [V].

### 5.1 Shop page (ShopApp, native Menu page)
**Sub-tabs** in the Menu header: **Home · Speed-ups · Boosts · Style · Extras** (5 = the B2 maximum). Width check:
124 + 136 + 124 + 124 + 124 + 4 × 8 = 664 px; header total ≈ 1,100 ≤ 1,134 [V mockup].

**Home** (one vertical scroll):
1. Line: "Optional extras for Robux. You can reach every office and every client without them."
2. Studio only: the dashed OWNER PREVIEW banner (C2).
3. **YOUR ITEMS** (only when not empty): a 98 px strip of compact segments, each icon 70 + name 24 + one line 20 +
   a 74 px secondary button: Eureka ×n "Use it in Lab → Research" [OPEN LAB ›]; Last Epoch ×n "Use it in the training
   view" [OPEN LAB ›]; a running boost "+20 % · 12:40 left (play time)" [BOOSTS ›]; other vouchers [REDEEM]; owned
   passes are not repeated here (they show "✓ Owned" in their tab).
4. **Featured tile** (150 px): the first of {Style Collection, Identity Kit, VIP Founder, Founder Suite, Robo Buddy, AI
   Gallery} that is listed, available, `ready`, priced, for sale and not owned (and, for the bundle, no part owned). No
   "featured" or "deal" label. The bundle tile shows its 3 contents as chips.
5. **CATEGORIES**: 4 tiles (each ≈ 266 × 170 px, whole tile is the button): Speed-ups "Finish research or training
   now"; Boosts "15 min of extra income or speed"; Style "Colours, lights and fun. Looks only."; Extras "Perks, company
   cash and tips"; count chip "n items" (listed and available only); tap opens the tab.

**Speed-ups**: line "Each one finishes one job right now. You keep it until you use it." · rows Eureka, Last Epoch ·
info box "Where to use them: Eureka in Lab → Research, on the Lab level card or at a "Needs research" size in the Model
Studio. Last Epoch in the training view. {n} research steps are left in your save, so you can still use up to {n}
Eurekas." (n = `eurekaUsesLeft`). No USE button here (a Eureka needs a target).

**Boosts**: line "Boosts count play time only and never affect other players. Up to 4 starts of each a day." · while a
boost runs, a status card (86 px, no button): "{Name} is on" + "+20 % app and API income · 12:40 left (play time) · 1 of 4
today" + bar (fix round 1: measured against the 15-min blocks this run has, so a fresh boost is a full bar, not 25 % of
the 60-min maximum) · rows Keynote Boost, Overclock: with a held voucher the row shows ×n and a primary button (**START**, or
**ADD 15 MIN** while that boost runs) next to the price chip; START opens the UseSheet (5.3). START rules of 3.3: Keynote
disabled "No live AI right now" without a live model; Overclock row note when the current run is at the 12 s minimum.

**Style**: line "Looks only. Nothing here changes your income or other players." · bundle tile (same text as section 2,
also on the Home featured tile; R3) · sections COMPANY LOOK
(Identity Kit, Server Glow, AI Gallery, Team Hoodies) · SHOWS (Stage Lights, Rooftop Fireworks, Team party) · FOUNDER
(VIP Founder, Founder Suite, Robo Buddy). Identity Kit owned → its row gets "CHANGE LOOK ›" (opens Team → Settings).

**Extras**: PERKS (Executive Limo, Investor Relations) · HELPER (Headhunter) · COMPANY CASH "one of each per office ·
grows with your office" · SUPPORT THE DEVELOPER (tips).

**Row** (ONBOARDING C2 row, changed): 1102 px wide, **height grows with the text (min 126 px), effect text up to 3
lines at 22 px, never cut with an ellipsis**; icon 94; name 28 bold + tag chip 20; right side: optional primary 170×74
(START / ADD 15 MIN / REDEEM / CHANGE LOOK ›) + price chip 170×74. Price chip states as C2 (loaded / "…" / hidden on
failure or `IsForSale == false` / "✓ Owned" / Studio "Not set up"). Tag chip colours: Speed-up 159,211,232; Boost
232,180,138; Cosmetic 176,162,208; Bundle warn; Helper 134,171,198; Company cash good; Car + perk / Gameplay bonus warn.

**Page states** (C2 kept): live with every id 0 → "Shop coming soon" card and no HUD Shop button; some ids → only
listed, available, ready items, empty tabs hidden (and their category tile); Studio → all 23 items as preview.

### 5.2 Robux buttons outside the Shop page

#### 5.2.1 The gate (pure, `ShopMath.offerAllowed(data, key, ui)`)
All must hold, else the button is not created:
1. `TutorialMath.step(data, live, ui) == nil` (guide done or skipped) and `data.stats.modelsReleased ≥ 1` (Shop
   unlocked; ONBOARDING B5);
2. the player holds a voucher of `key` (**owned state**), **or** the product is listed (`id > 0`), in
   `live.shop.available`, its price is loaded and `IsForSale`, and the buy guard (4.1) allows it (**buy state**). In
   Studio with id 0 the button shows "Not set up" and never prompts (owner preview);
3. the action would succeed right now (`ShopMath.eurekaCheck` / training state / daily count); in the **buy state** it
   must also save at least `EUREKA_MIN_SAVING` (Eureka) or `LAST_EPOCH_MIN_LEFT` (Last Epoch), and a Lab-level Eureka
   needs RP < the level's RP. The owned state has no minimum: the note shows the real saving;
4. `ui.lastError` is not NO_MONEY / NO_POINTS / any error from the last 10 s on this page (never right after a failure).

Button style: the Kit price-chip look (raised fill, accent stroke 45 %), label "{ACTION} · EUREKA", then a divider and
either "R$ {price}" (buy state) or "×n" (owned state). Free actions keep their primary/secondary styles, so
the Robux button is never the most prominent button. Fix round 1: the price reads "R$ 15", not a Robux glyph: no
official glyph is documented (the research note `agents/onboarding_research/shop.md` found `\u{E002}` only in DevForum
posts, "aren't official"), and a home-made icon would imitate Roblox's logo; Roblox's own purchase window shows the
real Robux icon and price before anything is bought. Also (fix round 1): with 0 RP and several workable cards, the
**buy** state shows on **one** card only (5.2.2); in the training view the Last Epoch button uses the plain secondary
look (5.2.5); in the Studio strip the Robux button is never wider than the free button next to it (5.2.4).

#### 5.2.2 Lab → Research (EmpireApp `research`, P2 native page)
- Top status row: RESEARCH POINTS · **SPEED IN OFFICE HOURS** (peak office-hours RP/s, the rate the "Saves" line uses;
  the label says so because at night the real speed is 0) · message ("No project running. Research points come in
  office hours." / "Researching {name} · {m:ss} left").
- Project cards in 2 columns: name 28 · meta "$cost · RP · m:ss" · description · button row · note line.

| Card state | Free button | Eureka button | Note line |
|---|---|---|---|
| running, ≥ 30 s left | progress bar, "{m:ss} left" | **FINISH NOW · EUREKA** (buy or ×n) | "Eureka saves about {t}: its {P} RP come back." |
| running, < 30 s left | progress bar, "{m:ss} left" | buy state: none · owned: **FINISH NOW · EUREKA ×n** | owned: "Eureka saves {s} s: its {P} RP come back." |
| idle, prerequisite done, cash ≥ cost, RP ≥ points | **START · $cost** (primary) | **EUREKA** | "Eureka saves about {t}: you keep your {RP} RP, you still pay $cost." |
| idle, cash ≥ cost, RP < points | NEEDS {P} RP (disabled) | **EUREKA** | "Eureka saves about {t}: covers the {P} RP, you still pay $cost." |
| another project running | "Another project is running" (disabled) | none | – |
| cash < cost | NEEDS $cost (disabled) | none | – |
| prerequisite missing | NEEDS {prereq} FIRST (disabled) | none | – |
| done | ✓ DONE chip | none | – |

`?section=research&focus={id}` (route of B9) scrolls to and briefly outlines the card (used by OPEN RESEARCH ›).

Fix round 1 (review): the **buy** (Robux) state of the Eureka button shows on **one** idle card at a time: the card a
deep link asked for (`focus`), else the cheapest card it works on. So a page with 0 RP (garage, at night, right after a
launch) is never a wall of Robux buttons, and the free action stays the obvious choice. An **owned** Eureka shows on
every card it works on (R6: a bought voucher is never stranded). The running project's FINISH NOW · EUREKA is not
affected (one job at a time).

#### 5.2.3 Lab → Models, Lab level card (LabApp card 5, lab package)
Under the existing text, the button row: **UPGRADE LAB · {RP} RP + ${cash}** (unchanged, disabled with its reason) and
**LEVEL UP · EUREKA** (secondary) when the tree is done, level < 10 and cash ≥ the level's $. Buy state only while **RP
< the level's RP** with a saving ≥ 30 s (a Lab level has no timer: with enough RP the free button works and a Eureka
saves no time). Note "Eureka saves {about t}: covers the {RP} RP. You still pay ${cash}." (fix round 1: the saving of
`ShopMath.savingText`, before any Robux prompt, as the Eureka text promises) (Example L6→7: 1,210 RP + $100,663 =
`Ops.labCost(6)` [V formula].) Owned state with enough RP: note "No time saved: your {RP} RP stay yours for the next
level. You still pay ${cash}." (so an owned Eureka is never stranded once the RP stock covers every level).

#### 5.2.4 Model Studio "Needs research" (DesignSteps, lab package)
Today a 7B tile locked by `FRONTIER` shows "Needs / research" and the Review primary reads "RESEARCH FRONTIER
ARCHITECTURE · COMPANY" [V DesignSteps:829, 1121].
- **Step 2, 7B picked and locked by FRONTIER:** the hint line becomes (warn) "7B needs Frontier Architecture · $65,000 ·
  500 RP · 2 min"; with a Eureka offer the last part is the saving instead: "· Eureka saves about 3 min"
  (`ShopMath.savingText`, fix round 1); the presets row (CHEAPEST / BEST I CAN AFFORD / SAME AS LAST) is replaced by a
  74 px **lock strip**: **OPEN RESEARCH ›** (secondary, free deep link to Lab → Research focus `frontier`), OPEN GPUs ›
  when VRAM / a GPU is the other need, and, when the offer rule below holds, **SKIP RESEARCH · EUREKA** (price chip
  style). Fix round 1: the strip's buttons share the width equally, so the Robux button is never wider than the free
  one. The tiles row and CONTINUE stay.
- **Step 6 Review, same lock:** the primary becomes **OPEN RESEARCH › FRONTIER ARCHITECTURE** (same deep link) and the
  hint line is the same warn line as step 2 (fix round 1; "Check it, then start." would ask for the impossible). The
  strip at the top of the Final-review box has **no** OPEN RESEARCH › of its own (fix round 1: the primary is that
  link); it shows only OPEN GPUs › and/or SKIP RESEARCH · EUREKA (half the strip at most) and is hidden without them.
  The Robux button is never the primary.
- **Offer rule** `ShopMath.studioEurekaOffer(data, sel, money, LabPreview.estimate)`:
  1. `estimate(data, sel).lock == "FRONTIER"`;
  2. `eurekaCheck(data, "frontier", money)` ok: not done, `architecture` done, no other job running (a running Frontier
     job turns the label into FINISH NOW · EUREKA), cash ≥ $65,000 when not running;
  3. `data.training == nil` (with a running training the Review reads "TRAINING SLOT BUSY" [V DesignSteps:1112], so a
     Eureka would not let the player train 7B now), and
     `after = estimate(withResearch(data, "frontier"), sel, money − frontierCost)` has `after.lock == nil` (no
     MODEL_LIMIT, NO_GPU, VRAM, NO_DATA, and no MONEY: `estimate` sets MONEY when the cash after Frontier is below the
     7B training cost [V LabPreview.estimate]);
  4. `offerAllowed(data, "eureka", ui)`.
  When 3 fails the hint names the other need, e.g. "7B needs Frontier Architecture and 128 GB VRAM (you have 96).", and
  the strip shows OPEN RESEARCH › plus the free link for that need (OPEN GPUS › for VRAM/NO_GPU; none for the others).
  `withResearch(data, id)` is pure: it clones `data`, `data.empire` and `data.empire.research` (three `table.clone`)
  and sets `research[id] = true`; the snapshot is never mutated.
- After a successful Eureka from the Studio: the server notice "Research complete: Frontier Architecture" plus a client
  toast "7B is unlocked.", and the Studio refreshes in place (the hint returns to normal).

#### 5.2.5 Training view (lab package: Stages "Training", LabApp Models training card)
**FINISH NOW · LAST EPOCH** under the ETA while a run trains, no decision is pending, `dailyUsed < 10`, and the gate
holds (buy state: ≥ 20 s left; owned state: any time left). Fix round 1: plain secondary look (no accent stroke) and
350 px wide, narrower than CLOSE · it keeps training, so it is never the most prominent button of the view. Never during the first training (the Shop unlocks at the first launch). Note "Saves {ETA}". The ETA includes the
Overclock factor (`StateController.trainingWork/trainingEta` × `ShopMath.trainingFactor`).

#### 5.2.6 Look picker and settings
- Studio look picker / company picker: the 8 Kit colours and 6 Kit logos show with a small lock for non-owners and one
  line "More colours with Identity Kit (Shop)". **No buy button in the picker.**
- Team → Settings: card "Change colour & logo" (free, S4), 60 s cooldown text "You can change it again in {s} s".

#### 5.2.7 Home and HUD
- **No HUD chip** for boosts (the phone HUD column is at its height limit, ONBOARDING A2.1).
- Home → Today live strip: while a boost runs, the TRAINING cell reads "×1.5 · 9 min" (Overclock) and the NET cell's
  caption reads "NET · KEYNOTE 12 MIN"; not tappable, never an offer.

### 5.3 UseSheet (new `UI/Shop/UseSheet.module.luau`, built from `Kit.blocker` + `Kit.panel` + `Kit.button`)
760 px wide, centred, dim 62 %; header icon 76 + title 32 + subline 22; 4 rows (caption 21 caps, value 23 with a 22 muted
tail); buttons CANCEL (secondary) and the action (primary, 1.4× wider), 74 px. No timer, no price on the use sheet.
**Modal for every input (fix round 1):** while open it binds (ContextActionService, priority High + 1, above the Studio's
High and the Menu's Medium) gamepad B = CANCEL, L1 / R1 = sunk, Return / KeypadEnter = the action; with a gamepad the
action button is selected and the card is a SelectionGroup that stops at its edges; the Studio's Return handler skips
while a sheet is open; `Computer.close()` and `Studio.close()` close it; the "received" sheet only opens over an open
Menu / Studio (in the world the grant toast says where the voucher is).

| Use | Title | Rows | Action |
|---|---|---|---|
| Eureka, Lab level | "Use 1 Eureka on Lab level {L+1}?" sub "Eureka · you have {n}" | FINISHES "Lab level L → L+1 now · +1 core stat on new models" · COVERS "{RP} RP · you have {have}, they stay yours" (no tail with 0 RP, fix round 1) · YOU PAY "${cash} · cash after ${after}" · SAVES "about {t} at your office-hours speed (+{rate} RP/s)" | USE EUREKA |
| Eureka, project idle | "Use 1 Eureka on {name}?" | FINISHES "{name} now · {desc}" · COVERS "{P} RP" + have/keep tail · YOU PAY "$cost · cash after $x" · SAVES | USE EUREKA |
| Eureka, project running | "Finish {name} now?" | FINISHES · COMES BACK "{P} RP" · YOU PAY "nothing more" · SAVES "{m:ss}" | USE EUREKA |
| Eureka, Studio 7B | "Use 1 Eureka on Frontier Architecture?" | as idle + a 5th row THEN "7B training costs ${after.cost}" | USE EUREKA |
| Last Epoch | "Finish this training now?" | FINISHES "{model} now, same chances as waiting" · EVENT "decided first if one comes" · SKIPS "the extra time of an event choice" · SAVES "{ETA}" | USE LAST EPOCH |
| Boost | "Start Keynote Boost?" / "Start Overclock?" | EFFECT "+20 % on app and API income" / "training 1.5× as fast" · NOW "about +${0.2 × unboosted market $/min}/min right now (it moves with the market)" / "this run about {ETA} → {ETA/1.5}" · LENGTH "15 min of play · {k} of 4 today". Fix round 1: the market income in the snapshot already includes `shopFactor` (Investor 1.10 + a running Keynote), so the base is `market / ((owns investor and 1.10 or 1) + ShopMath.revenueBonus)` | START |
| Boost running | "Add 15 min of {Boost}?" | EFFECT as above · NOW "keeps +20 % / ×1.5 for 15 more min of play" with the tail "left mm:ss → mm:ss" (fix round 1: the effect already applies, one rate, never stacked: no "+$" promise and no "A → B" run time) · LENGTH "+15 min of play · {k} of 4 today" | ADD 15 MIN |
| After buying (any context voucher) | "{Name} received. Use it now?" sub "On {target} · you can also keep it for later" | same rows as its use sheet | USE NOW / LATER |

"Saves" (`ShopMath.eurekaSaving`): timer left (or the project's seconds) + `max(0, need − have) / peakRate`, where
`peakRate = EmpireMath.bonuses(e).points × (spec == "research" and 1.2 or 1) × DUTY_PEAK + subscriptionRP`, and
`DUTY_PEAK = max over the game day of Ops.timesheet(Ops.hour(s + 0.5)) / Ops.TS_MEAN` (≈ 1.70, precomputed once like
`TS_MEAN`) [V formulas EmpireService.tick, CompanyOps.duty]. Rounded **down**: whole minutes from 60 s ("about 3 min"),
tens of seconds below ("about 40 s"); under 30 s whole seconds ("12 s"). It is a lower bound (at night the real wait
is longer). Below `ShopConfig.EUREKA_MIN_SAVING = 30` s no **buy-state** Eureka button is created (`ShopMath.eurekaCheck`
returns `TOO_SMALL` when called with `forBuy = true`); an owned Eureka still shows, with the real saving.

### 5.4 Texts (ShopApp `MESSAGES`, toasts)
- Errors, each ending with "Your {item} is kept.": `RESEARCH_ACTIVE` "Another project is running. Finish that one
  first." · `PREREQUISITE` "Finish the research it builds on first." · `NO_MONEY` "You need {cost} for this." ·
  `ALREADY_DONE` "Already researched." · `MAX_LEVEL` "All 10 Lab levels are done." · `NO_COMPANY` "Found your company
  first." · `NO_TRAINING` "Nothing is training right now." · `DECIDE_FIRST` "Decide the training event first." ·
  `NO_LIVE_MODEL` "Release an AI first: Keynote Boost adds to app and API income." · `DAILY_LIMIT` "That's today's limit ({n} a day). It resets at {local time of 00:00 UTC}." · `BOOST_FULL` "This boost
  already has an hour left." · `FIREWORKS_ACTIVE` "Fireworks are already going." · `PASS_NEEDED` (rebrand/look) "This
  colour comes with Identity Kit." · `TOO_FAST` "You can change it again in a minute."
- `grantedText`: vouchers "{Name} added. {where}" (Eureka "Use it in Lab → Research.", Last Epoch "Use it in the training
  view.", boosts "Start it in Shop → Boosts."); passes "{Name} is yours."; cash unchanged.
- Success toasts (client): projects none (the server notice "Research complete: {name}" shows, 3.1) · "Lab level {L}
  (Eureka): new models get +1 on every core stat." ·
  "Training finished (Last Epoch)." · "{Boost} started: 15 min of play." · end "{Boost} ended."

### 5.5 Never (extends ONBOARDING C1)
No Robux button or shop link in: the guide, a goal card, a tip, a Home card, a toast, the assistant's lines, the phone, an
error message, the 7B tile itself (only the strip), any place where the action would fail. **No Robux button in the HUD**
(the HUD's own Shop button of ONBOARDING B11/C1 only opens the Shop page, after the first launch and the guide; it is not a
buy button). No automatic shop
opening, no automatic redeem, no "you need Robux" wording anywhere.

---------------------------------------------------------------------------------------------------------------------
## 6. Purchase, receipt and redeem flow (existing ShopService, extended)

### 6.1 Buying
1. Client: a price chip or context button calls ShopApp `prompt(kind, id)` → `PromptProductPurchase` /
   `PromptGamePassPurchase` [V]. Context buttons first store `pendingUse = {key, target, at = os.clock()}` (client
   memory only). The chip shows "…" for 2 s.
2. Roblox's own purchase window is the confirmation (no extra sheet before it).
3. Server: `ProcessReceipt` → `Shop.processReceipt` (unchanged: find def by id, wait for session, check/grant/record
   without yielding, save, then `PurchaseGranted`; else `NotProcessedYet`) [V]. `grant` for vouchers adds 1; for cash
   it pays and records `packs[key] = office`, or, when this office already had that size, adds `packCredit[key] += 1`
   and pays nothing now (3.12).
4. Server → client: Notify `SHOP_GRANTED {key, kind, voucher, count}` [V].
5. Client: if `pendingUse.key == payload.voucher` and `os.clock() − at < 120`, open the "received — use it now?" sheet
   with the stored target (recomputed rows; if the action no longer works, a toast "{Name} added. {where}" instead).
   Otherwise the toast. **Never redeemed automatically** (the $ is paid at redeem time and state may have changed).
6. Nothing is granted from `PromptProductPurchaseFinished` [V ShopApp header].

### 6.2 Using
Client sends `ShopAction {action = "redeem", key, target?}` (rate limit unchanged: burst 4, 1/s [V]). The sheet's
action button disables until the reply; on error the sheet closes and the error toast shows.

### 6.3 `ShopService.redeem(session, key, target)` (changed)
1. `ShopConfig.voucher(key)` else `BAD_INPUT`; `target` must be nil or pass `Guard.id` (else `BAD_INPUT`);
2. voucher count ≥ 1 else `NO_VOUCHER`; handler exists else `NOT_AVAILABLE`; `redeeming[session]` → `BUSY` [V];
3. **daily check** (new, generic): roll `daily.day` to today (reset `used`), then if `ShopConfig.DAILY[key]` and
   `used[key] ≥ DAILY[key]` → `DAILY_LIMIT`;
4. `pcall(handler, session, target)` (old handlers ignore `target`);
5. on true: voucher −1 and `used[key] += 1` (if in DAILY), `markDirty(session, true)`, return `{ok, key, left}`.
`ShopAction "status"` also returns `daily` and `boosts` (the client reads them from the snapshot anyway).

---------------------------------------------------------------------------------------------------------------------
## 7. Save fields (pure additions, DATA_VERSION stays 6)

```
data.shop.boosts = { keynote = <empire.seconds end>?, overclock = <end>? }     -- numbers > 0
data.shop.daily  = { day = <utc day>?, used = { keynote = n?, overclock = n?, lastEpoch = n? } }
data.shop.packs  = { seed = <office 1..5>?, seriesA = <office>?, seriesB = <office>? }
data.shop.packCredit = { seriesB = <n>?, ... }  -- fix round 1: packs bought again in an office that had one (3.12)
data.company.color / data.company.logo                                          -- existing; may now hold Kit ids
```
- `Template.newShop` returns these empty tables; `Template.cleanShop` keeps only known keys, finite values: boosts > 0;
  `daily.day` integer; `used[key]` clamped 0..DAILY[key]; `packs[key]` integer 1..#OFFICES; `packCredit` like vouchers
  (valid keys, integer counts 1..VOUCHER_MAX, never dropped for being unknown); everything else dropped. After the
  cleaners, `Template.clampBoosts` cuts any boost end to at most `empire.seconds + BOOST_MAX_LEFT` (fix round 1).
- ShopService `shopOf` shape check adds `typeof(shop.boosts/daily/packs) == "table"` (else cleanShop) — without it an
  old save would lose the fields on load (trap 2, code.md 5) [V cleanShop keeps only receipts/order/vouchers/passes/tips today].
- Size: about 120 bytes; changes only on a start, a redeem or a pack purchase. No per-second field (time left is computed
  from `empire.seconds`, already in the snapshot). `SessionService` strips only receipts/order [R design 12.3];
  `tests/econ/test_net.luau` must still pass.
- Rebrand cooldown and `pendingUse` are runtime only.

---------------------------------------------------------------------------------------------------------------------
## 8. Code: what changes where

### 8.1 Shared
| File | Change |
|---|---|
| `ReplicatedStorage/Shared/Config/ShopConfig.module.luau` | PRODUCTS: eureka, lastEpoch, keynote, overclock, fireworks (`kind = "voucher"`, `voucher = key`, `id = 0`, texts of section 2, `tab`, suggested price in a comment). VOUCHERS for the same keys. PASSES: identityKit, serverGlow, stageLights, aiGallery, teamHoodies, roboBuddy, styleCollection (`id = 0`, `tab = "style"`, `ready = false` for phase 2/3, `includes` on the bundle). Existing entries get `tab` and the section-2 texts. New: `BOOSTS = {keynote = {seconds = 900, revenue = 0.20}, overclock = {seconds = 900, training = 1.5}}`, `BOOST_MAX_LEFT = 3600`, `DAILY = {keynote = 4, overclock = 4, lastEpoch = 10}`, `FIREWORKS_SECONDS = 45`, `REBRAND_COOLDOWN = 60`, `EUREKA_MIN_SAVING = 30`, `LAST_EPOCH_MIN_LEFT = 20`, `FEATURED = {"styleCollection","identityKit","vip","founderSuite","roboBuddy","aiGallery"}`, `CASH.oncePerOffice = true`, comment fix (3.12). Shares unchanged until S1. |
| **new** `ReplicatedStorage/Shared/ShopMath.module.luau` (pure) | `utcDay(now)`, `dailyUsed(shop, key, now)`, `boostLeft(data, key)`, `trainingFactor(data)`, `revenueBonus(data)`, `eurekaUsesLeft(data)`, `eurekaCheck(data, target, money, forBuy)` (mirrors 3.1, returns kind/cost/points/seconds or err; `forBuy` adds the 30 s minimum and the Lab-level "RP short" rule), `withResearch(data, id)`, `peakRate(data)` + `DUTY_PEAK`, `eurekaSaving(data, target)`, `buyAllowed(data, live, key)` (4.1), `offerAllowed(data, key, ui)` (5.2.1), `studioEurekaOffer(data, sel, money, estimate)`, `packOpen(data, key)`, `shareWords(share)`. Used by ShopService, ShopApp, EmpireApp, LabApp, DesignSteps, StateController. |
| `ReplicatedStorage/Shared/Config/CompanyConfig.module.luau` | `KIT_COLORS`, `KIT_LOGOS`, `getColor` both lists, `isLogo` both, `isKitColor`, `isKitLogo`, `allLogos()` (3.5) |
| `ReplicatedStorage/Shared/ModelMath.module.luau` | `parseLook`: emblem n ≤ #allLogos() |

### 8.2 Server
| File | Change |
|---|---|
| `ServerScriptService/Server/Services/ShopService.module.luau` | shape check (7); `redeem(session, key, target)` + daily check (6.3); `ShopAction` passes `payload.target`; `startBoost`, `boostLeft`, `trainingMultiplier`; `revenueMultiplier` adds the Keynote bonus; built-in handlers keynote/overclock/fireworks in `init`; `owns` honours `includes`; `available()` treats `ready == false` passes as not sellable; `grant` records `packs` for cash; `refreshOffice` sets `ServerGlow`; ONBOARDING C4 Founder Suite tier fix stays. |
| `ServerScriptService/Server/Services/ShopDecor.module.luau` | `fireworks(office, cf, color)`; phase 3 `gallery`, robot model |
| `ServerScriptService/Server/Services/EmpireService.module.luau` | `local function completeResearch` before `Empire.tick`, used by the tick and `Empire.eureka` (3.1); `init` registers the handler; EmpireAction `rebrand` → CompanyService |
| `ServerScriptService/Server/Services/AIModelService.module.luau` | Overclock in the local `trainingTick` (lazy ShopService require); `lastEpoch` + registration; `startTraining` look: Kit ids need `identityKit` |
| `ServerScriptService/Server/Services/CompanyService.module.luau` | `rebrand(session, color, logo)` (3.5); create accepts Kit ids only with the pass |
| `ServerScriptService/Server/Lib/Template.module.luau` | `newShop` / `cleanShop` (7) |
| `ServerScriptService/Server/Services/MarketService.module.luau` | none (`shopFactor` already calls `revenueMultiplier` every tick, after shares) [V] |

### 8.3 Client (shop package)
| File | Change |
|---|---|
| `UI/Apps/ShopApp.module.luau` | 5.1 page with sub-tabs (Home, Speed-ups, Boosts, Style, Extras), YOUR ITEMS strip, featured rule, category tiles, rows with growing height, buy guards, `MESSAGES`, `grantedText`, `pendingUse` + received sheet (6.1); `productGroup` replaced by `tab` (trap 4: kinds other than cash/voucher fell into "Support" [R code.md 5]) |
| **new** `UI/Shop/UseSheet.module.luau` | 5.3 |
| `UI/Apps/EmpireApp.module.luau` (`research`) | 5.2.2 page and Eureka buttons; Settings card "Change colour & logo" |
| `Controllers/StateController.module.luau` | `trainingWork` / `trainingEta` × `ShopMath.trainingFactor(data)` |
| `UI/Apps/HomeApp` (ONBOARDING P2) | live-strip captions (5.2.7) |

### 8.4 Requests to other packages (S5)
| Package | Request | Phase |
|---|---|---|
| lab | LabApp Lab level card LEVEL UP · EUREKA (5.2.3); training card + Stages "Training" FINISH NOW · LAST EPOCH (5.2.5); DesignSteps step-2 lock strip and step-6 strip + deep link (5.2.4); look picker Kit tiles (5.2.6); Stages reveal Stage Lights (3.7) | 1 (Stage Lights 2) |
| life | PropFxController Server Glow wave (3.6) | 2 |
| buildings | per-tier `GalleryAnchor` in BuildingPlan (3.8) | 3 |
| staff rigs | EmployeeRigDesign hoodie colour + `StaffKey` (3.9) | 3 |
| staff (recruiting) | `RecruitingService.headhunt` deterministic (3.12) + a pure `Recruiting.headhuntPreview(e)` (role name) for the YOUR ITEMS line | 1 |

### 8.5 Unchanged
Receipt processing, pass checks, Team party, MarketService, every CORE_SPEC economy number (until S1), DATA_VERSION 6,
the Remote list, every id (0). (Headhunter changes: 3.12.)

---------------------------------------------------------------------------------------------------------------------
## 9. Tests the builder must write (report each as passed / failed / not run)
Server tests in `tests/shop` (run.sh, negative.sh), pure ones headless.

1. **T1 Eureka running job:** done, RP back, xp +150, notice fired, voucher −1, quest "research" claimable; **equivalence**:
   state after Eureka == state after the timer finishes, except time and the returned RP.
2. **T2 Eureka idle project:** done, $ cost on ledger "research", RP unchanged; each error keeps the voucher:
   `BAD_INPUT`, `ALREADY_DONE`, `PREREQUISITE`, `NO_MONEY`, `RESEARCH_ACTIVE`, `NO_COMPANY`.
3. **T3 Eureka lab:** level +1, $ on ledger "lab", RP unchanged; `PREREQUISITE` (tree open), `MAX_LEVEL`, `NO_MONEY`.
4. **T4 Last Epoch:** `NO_TRAINING`; pending → `DECIDE_FIRST` (kept, `eventRolled` stays true); before 35 % the event is
   rolled now; **chances:** over 2,000 seeded runs skipped at 10 % the event rate is 60 % ± 3 % and each event's share
   is within 3 points of 2,000 waited runs (not equal ids: `updateLoss` draws from the same RNG, 3.2); after 35 % no
   second roll; refinement path; the final stats come from `finish` like a waited run.
5. **T5 Boosts:** keynote with no live model → `NO_LIVE_MODEL` (kept); start → `boostLeft = 900`; second → 1,800; at 2,701 s left → `BOOST_FULL`; 5th start of the UTC day →
   `DAILY_LIMIT` (kept); new UTC day resets; offline (empire.seconds frozen) keeps the time left; `revenueMultiplier`
   1.20 / 1.30 with Investor; `trainingMultiplier` 1.5 and the 12 s floor holds.
6. **T6 Daily Last Epoch:** 11th redeem of the day → `DAILY_LIMIT` (kept).
7. **T7 Redeem target:** `target` non-id → `BAD_INPUT`; headhunter/party ignore target; `BUSY` while a redeem runs.
8. **T8 Save:** `cleanShop` keeps valid boosts/daily/packs and drops junk (NaN, strings, unknown keys, out-of-range);
   an old save without the fields is repaired once by `shopOf`; round trip via `tests/lead/roundtrip.py`.
9. **T9 Cash packs once per office (server):** a second receipt of the same size in one office returns PurchaseGranted,
   pays **no** cash and adds one `packCredit`; a third adds another; a replayed id adds nothing; the buy chip stays hidden;
   the next `UpgradeOffice` pays exactly one credit per size at the new office's amount and sets `packs` to the new
   office; credits drain one per move; an old save without `packCredit` is repaired by `shopOf`. Simulator: a bot that
   buys every pack three times per office stays ≥ 0.48× the non-payer per stage (10.2, row "heavy, packs ×3").
10. **T10 Bundle:** `owns(identityKit)` true with only styleCollection; bundle flag false removes all three; bundle row
    hidden when a part is owned.
11. **T11 Identity Kit:** Kit colour/logo without the pass → `PASS_NEEDED` on create, rebrand, startTraining look;
    with it ok; after the flag goes false the saved colour stays and renders (getColor finds it); rebrand cooldown
    `TOO_FAST`; old looks (emblem 1–8) unchanged; **readability (pure):** every `KIT_COLORS` entry has WCAG contrast
    ≥ 7.0 against Theme `bg` and CIE76 ΔE ≥ 20 to every `COLORS` entry and every other Kit entry (same formulas as
    `agents/shop_crit/tools/kitcolors.py`).
12. **T12 Fireworks:** `NO_PLOT`, `FIREWORKS_ACTIVE`, kit removed after 45 s.
13. **T13 ShopMath pure:** `eurekaUsesLeft` (fresh 18; running job counts; tree + L10 → 0); `eurekaSaving` rounding
    (75 s → "about 1 min", 40 s → "about 40 s", 156.7 s → "about 2 min", 12.4 s → "12 s"); 25 s with `forBuy` →
    `TOO_SMALL` (no buy button), owned → button with the note "Eureka saves 25 s"; Lab level with RP ≥ the level's RP → no buy
    button, owned button with the "No time saved" note; Last Epoch with 19 s left → no buy button, owned button shown;
    **stranding check:** fixture save with every project done, Lab level 3, 100,000 RP and 1 Eureka owned →
    `eurekaUsesLeft = 7`, no buy button anywhere, and the Lab card shows LEVEL UP · EUREKA ×1; `DUTY_PEAK` within
    1.69–1.71; `shareWords`.
14. **T14 Buy guards:** Eureka hidden when vouchers ≥ uses left; boosts/Last Epoch hidden at the daily limit.
15. **T15 Gate:** no Robux button while `TutorialMath.step ~= nil` or `modelsReleased == 0`; none within 10 s after
    NO_MONEY/NO_POINTS; Studio id 0 → "Not set up" and no Prompt* call (T12 style spy).
16. **T16 Studio offer:** FRONTIER only → offer; FRONTIER + VRAM → no offer, OPEN GPUS › shown; cash < 65,000 →
    none; cash ≥ 65,000 but < 65,000 + training → none; another research job running → none; Frontier running →
    FINISH NOW; a training running → none; FRONTIER + NO_DATA → none; `withResearch` leaves the input table unchanged
    (deep compare before/after); the 7B tile itself never contains a Prompt* call.
17. **T17 Flow:** `pendingUse` opens the received sheet only for the matching voucher within 120 s; never auto-redeems.
18. **T18 UI sizes:** ShopApp tabs, UseSheet and the lab buttons: text ≥ 12 pt, targets ≥ 44 pt on the 844×390 preset
    (guiprev), rows never truncate the effect text; with the step-2 lock strip shown, the locked 7B tile's last line
    ("research") ends at least 4 px above the tile border (in the mockup it touched the border until the tile spacing
    was tightened in the review round).
19. **T19 Economy:** `tests/shop/run.sh --negative`, `tests/lead/run_all.sh`; re-run `agents/shop2_design/run2.sh` with the
    shipped code: stage times within ±10 % of section 10; base run byte-identical to the unpatched game.
20. **T20 Net budget:** `tests/econ/test_net.luau` passes with the new fields.
21. **T21 Texts:** every in-game text in ShopConfig equals section 2 (string compare), no forbidden words (limited, deal,
    best value, worth, sale, only today, premium) in any shop string.
22. **T22 (published game, owner) [A]:** an **Unlisted** developer product can be bought from our UI (docs say yes).
23. **T23 (Studio, phone) [A]:** fireworks, Robo Buddy, hoodie rig rebuild: frame time on a phone.
24. **T24 (Studio) [A]:** the 6 Kit logo glyphs render in BuilderSans; Server Glow with reduced motion
    (`GuiService.ReducedMotionEnabled` is tagged Hidden in the dump and not used in the code yet: confirm a LocalScript
    can read it).
25. **T25 Headhunter deterministic:** 50 redeems on fresh seeds: every applicant has `traits.k == 4`, ask 1.25, role =
    the smallest team (ties in ROLES order) and equals `headhuntPreview` before the redeem; desk/slot errors keep the
    voucher as today.

---------------------------------------------------------------------------------------------------------------------
## 10. Balance results (economy simulator, real `work/src` + proposed server code)

Method [R design 11.2, files re-read today]: `agents/shop2_design/sim_shop2.luau` (built by `make_sim.py` from the lab
simulator + payer flags) loads the current `work/src` and patches in `shop2_patches.luau` (Eureka, completeResearch,
Last Epoch, Overclock, Keynote, startBoost, save fields). 19 runs of 180–200 min + 2 identity checks. Re-run in the review round: `r1_light` (command in `run1.sh`) gave a
byte-identical output (`cmp` with `out/r1_light.txt`) in 1 min 19 s [V]. The 200-min run is `run2.sh`'s `r2_duo_payer`
line with `--minutes 200` (output `out/r2_duo_payer200.txt`; the command, reconstructed from that output's header, is now a
comment in `run2.sh`; re-run in the review round: byte-identical [V cmp]). Casual bot (acts
every second, auto-HR, Save mode, research in a fixed order); `slow` acts every 30 s. Profiles: **light** = Series A
once + 3 Eurekas + 1 Keynote (≈ 125 R$ at the suggested prices); **heavy** = Investor, every pack once per office,
every Eureka, Last Epoch on **every** run (above the 10/day cap: an upper bound), 4 + 4 boosts; **max** = heavy with
both boosts always on.

### 10.1 Identity
With the proposed code and nothing bought, a 60-min and a 180-min run are **byte-identical** to the unpatched game
[V cmp today].

### 10.2 Who reaches what (minutes to Founder HQ / Startup Campus / Innovation Campus / Global HQ)
| Run | Stages | Lowest cash | Bought |
|---|---|---|---|
| seed 4242 non-payer | 7.5 / 34.7 / 83.0 / 168.8 | $1,776 | – |
| seed 4242 light | 10.9 / 25.2 / 75.2 / 162.3 | $1,537 | Series A (at the S1 share 0.20), 3 Eureka, 1 Keynote |
| seed 4242 heavy, no packs | 8.9 / 23.8 / 55.2 / 133.0 | $1,570 | 18 Eureka, 64 Last Epoch, 4 + 4 boosts, Investor |
| seed 4242 heavy, **today's** shares | 5.6 / 5.7 / 5.7 / **5.7** | $823 | + 5 of each pack |
| seed 4242 heavy, O1 caps | 8.5 / 8.5 / 8.5 / **8.6** | $1,614 | + 5 of each pack |
| seed 4242 heavy, **S1 rule** | 6.3 / 16.8 / 53.3 / 104.7 | $1,612 | + 5 of each pack |
| seed 4242 max, S1 rule | 5.8 / 16.1 / 40.6 / 88.4 | $1,521 | boosts always on |
| seed 7 non-payer / light / heavy | 10.9/32.0/96.1/166.6 · 10.5/31.0/77.6/161.1 · 5.7/20.1/50.6/101.2 | ≥ $1,533 | |
| seed 23 non-payer / light / heavy | 10.4/31.4/77.7/165.3 · 10.8/25.9/73.6/161.4 · 6.3/15.6/40.1/89.3 | ≥ $1,244 | |
| slow non-payer / light | 12.5/38.5/92.0/174.5 · 13.0/29.0/83.0/172.5 | $2,104 | |
| one server: control (nobody pays), company 2 | 8.4 / 32.4 / 85.0 / 173.5 | $1,545 | – |
| one server: company 1 heavy, **company 2 non-payer** | 8.8 / 24.6 / 83.9 / 182.1 (200-min run) | $1,534 | – |

### 10.3 Reading
- **The cash packs decide everything.** With today's shares or the O1 caps, three packs on entering an office pay the
  next office at once: Global HQ at 5.7 / 8.6 min, i.e. a buyer skips the whole game. Hence S1.
- **Without packs,** everything else together gives Global HQ at 133 min, about as fast as the free "opt" profile
  (126–136, CORE_SPEC 9.4).
- **Eurekas alone barely move stage times** (research is not the gate). In the garage a Eureka still costs the
  project's cash: the light bot left the garage 3.4 min later than the non-payer (10.9 vs 7.5) — hence "cash after" in
  the sheet.
- **Light payer:** every casual CORE_SPEC window holds (garage 8–12, Campus 25–40, Innovation 70–100, Global HQ
  150–210) except the slow player's garage at 13.0 min, where its own non-payer run takes 12.5.
- **Heavy payer (S1 rule):** Global HQ at 89–112 min (non-payers 165–176), every stage ≥ 0.48× the same seed's
  non-payer (the single 0.48 is seed 4242's Campus), lowest cash ≥ $1,244. The "max" run (both boosts always on: 12 +
  12 starts in 3 h, three times the daily cap) reaches 0.46× at Campus (16.1 vs 34.7 min); the caps make that
  impossible within one UTC day, so it bounds a player who buys across midnight, not the normal case.
- **Rankings:** every run, payer or not, has a best model at the 99.0 cap by minute 120; heavy payers got there at
  minute 90 in 2 of 3 seeds [V "best" column of the outputs].
- **Other players:** the non-payer next to a heavy payer reaches Global HQ at 182.1 vs 173.5 min (+5 %); revenue at
  minute 60 −5 % (41,800 vs 44,183 $/min), at 120 equal (70,400 vs 70,351). That is inside the CORE_SPEC window and
  below the 7–9 % a strong free player costs a newcomer (CORE_SPEC 9.7).
- Robux at the suggested prices (Keynote 35): light 125 R$ (Series A 45 + 3 × Eureka 15 + Keynote 35); heavy (seed
  4242, S1 run: Investor, 5 of each pack, 16 Eureka, 61 Last Epoch, 4 + 4 boosts) about 2,079 R$ in 3 h, about
  1,620 R$ with the Last Epoch cap of 10 a day [V sums from `out/r1_heavy_P1.txt`].
- The light profile buys Series A at the proposed S1 share (0.20). With today's share (0.75) that one pack alone is
  worth three quarters of the next office, so "light payer inside every casual window" holds only under S1.

### 10.4 Limits of the evidence
Bots, not people; one run per seed (4 seeds/start hours), so a few minutes are path noise (CORE_SPEC 9.4 spreads
Innovation over 76–96 min across 12 casual seeds). The heavy payer buys at the best moment and ignores the Last Epoch
cap: an upper bound. Boost times were fixed minutes (the "max" row bounds a player who times them). Cosmetics are not
simulated (no economic effect by design). The new `BOOST_FULL` cap was not simulated; it can only reduce boost use.

---------------------------------------------------------------------------------------------------------------------
## 11. Owner guide (German, for the user)

> **Neue Shop-Sachen freischalten** (zusätzlich zur Anleitung in ONBOARDING_SPEC C6: Spiel veröffentlichen,
> create.roblox.com → Creations → dein Spiel)
>
> 0. **Geld-Pakete (Seed round, Series A, Series B):** S1 ist entschieden (10 / 20 / 30 % des nächsten Büros, jede
>    Größe einmal pro Büro). Der Server achtet selbst darauf: Wer ein Paket im selben Büro ein zweites Mal kauft, bekommt
>    das Geld erst beim Umzug ins nächste Büro. Lege die drei Pakete als **„Unlisted"** an (Schritt 2). **Headhunter**
>    arbeitet seit dem Shop-Paket immer gleich (Fähigkeit 4, kleinstes Team, fester Gehaltswunsch, Abschnitt 3.12,
>    Test T25), ist also kein bezahltes Zufalls-Ergebnis mehr und darf angelegt werden.
> 1. **Developer Products** (Monetization → Developer Products → neues Produkt): für **Eureka, Last Epoch, Keynote
>    Boost, Overclock, die drei Geld-Pakete, Headhunter** und **Rooftop Fireworks**. Bild hochladen (höchstens 512×512, .png/.jpg/.bmp), **Name und
>    Beschreibung genau aus der Tabelle in Abschnitt 2 kopieren**, Preis in Robux selbst festlegen (die Zahlen in der
>    Tabelle sind nur Vorschläge), speichern. ID: mit der Maus aufs Bild → **⋯ → Copy Asset ID**.
> 2. **Eureka, Last Epoch, Keynote Boost, Overclock und die drei Geld-Pakete auf „Unlisted" stellen.** Sie
>    funktionieren nur im Spiel, also sollen sie nicht im Roblox-Shop auftauchen. Laut Roblox-Doku kann man sie trotzdem über unseren eigenen
>    Kauf-Knopf im Spiel kaufen. Bitte im veröffentlichten Spiel einmal ausprobieren (Test T22). Rooftop Fireworks
>    darf „Listed" bleiben.
> 3. **Pässe** (Monetization → Passes → Create pass) **erst anlegen, wenn die Funktion im Spiel fertig ist**, denn Pässe
>    erscheinen immer im Roblox-Shop. Reihenfolge: **Identity Kit** sofort (Phase 1). **Server Glow, Stage Lights,
>    Style Collection** nach Phase 2. **AI Gallery, Team Hoodies, Robo Buddy** nach Phase 3. Der Builder sagt dir, wann
>    eine Phase fertig ist (dann steht im Code `ready = true`).
> 4. Jede kopierte ID in **`ReplicatedStorage/Shared/Config/ShopConfig.module.luau`** hinter `id = ` eintragen (statt
>    `0`), in der Zeile mit dem passenden `key` (Tabelle unten). Speichern, **neu veröffentlichen**.
> 5. **Wichtig:** Nie eine ID erfinden, nie eine alte ID für etwas anderes benutzen, im Creator Hub dieselben ehrlichen
>    Texte wie im Spiel. Testen nur im veröffentlichten Spiel; in Studio zeigt der Shop „Not set up" und kauft nichts.

**Wo jede ID hinkommt** (Datei `ReplicatedStorage/Shared/Config/ShopConfig.module.luau`; in der Datei nach dem Text in
der letzten Spalte suchen und die `0` dahinter ersetzen):

| Was | Creator-Hub-Art | Liste in ShopConfig | Listed? | Wann anlegen | Suchtext |
|---|---|---|---|---|---|
| Eureka | Developer Product | `PRODUCTS` | Unlisted | jetzt (Phase 1) | `key = "eureka", id = 0` |
| Last Epoch | Developer Product | `PRODUCTS` | Unlisted | jetzt | `key = "lastEpoch", id = 0` |
| Keynote Boost | Developer Product | `PRODUCTS` | Unlisted | jetzt | `key = "keynote", id = 0` |
| Overclock | Developer Product | `PRODUCTS` | Unlisted | jetzt | `key = "overclock", id = 0` |
| Rooftop Fireworks | Developer Product | `PRODUCTS` | Listed | nach Phase 2 | `key = "fireworks", id = 0` |
| Identity Kit | Pass | `PASSES` | (immer) | jetzt | `key = "identityKit", id = 0` |
| Server Glow | Pass | `PASSES` | (immer) | nach Phase 2 | `key = "serverGlow", id = 0` |
| Stage Lights | Pass | `PASSES` | (immer) | nach Phase 2 | `key = "stageLights", id = 0` |
| Style Collection | Pass | `PASSES` | (immer) | nach Phase 2 | `key = "styleCollection", id = 0` |
| AI Gallery | Pass | `PASSES` | (immer) | nach Phase 3 | `key = "aiGallery", id = 0` |
| Team Hoodies | Pass | `PASSES` | (immer) | nach Phase 3 | `key = "teamHoodies", id = 0` |
| Robo Buddy | Pass | `PASSES` | (immer) | nach Phase 3 | `key = "roboBuddy", id = 0` |
| Seed round / Series A / Series B | Developer Product | `PRODUCTS` | Unlisted | jetzt (S1 entschieden) | `key = "seed", id = 0` / `"seriesA"` / `"seriesB"` |
| Headhunter | Developer Product | `PRODUCTS` | Listed | jetzt (3.12 ist gebaut) | `key = "headhunter", id = 0` |
| Team party, Supporter tip, Big supporter tip | Developer Product | `PRODUCTS` | Listed | jederzeit (C6) | `key = "party", id = 0` usw. |
| VIP Founder, Executive Limo, Founder Suite, Investor Relations | Pass | `PASSES` | (immer) | jederzeit (C6) | `key = "vip", id = 0` usw. |

Where a pass price is set on the Creator Hub is still not on an official page I opened (ONBOARDING C6 cites a
third-party guide) [unverified]; the owner checks it there.

---------------------------------------------------------------------------------------------------------------------
## 12. Open items and risks
1. S1–S6 (0.2).
2. Studio/published-game checks T22–T24 [A].
3. The Shop sub-tabs depend on the ONBOARDING P2 Menu shell; until P2 ships, ShopApp keeps its own header with the same
   5 tabs as a segmented control (Kit.segmented) [A layout].
4. Risk: the lab package renames DesignSteps locks or LabApp card order; T16 and T15 fail loudly.
5. Risk: Roblox changes the Unlisted rule; T22 catches it, and Listed products would still work.
6. Not verified: what Build a Phone Empire's products actually do (no descriptions) and how its in-game shop looks;
   none of it is needed, because nothing here copies them.
7. Headhunter (3.12) waits for the staff package; until it ships, no Headhunter product is created (11). If the lead
   prefers to keep today's random version, it needs odds shown before buying and a PolicyService check (paid random
   items page), which this spec does not design.
8. Ideas shared with Build a Phone Empire (allowed, genre conventions; names, texts, numbers and art are ours): a
   colours-and-logos pass (its "Premium Finishes" / "Logo & Wallpapers"), a launch-show cosmetic (its "Launch Reveal
   Pack", empty description), a cosmetic bundle (its "Company Branding Bundle", contents unknown), a finish-now skip
   (its "Instant Development"). Listed so the owner knows. Its 29 products have empty descriptions; 9 of its 13 passes
   have one short line each (`shop_spec/raw/bape_passes.json`). Our 23 rows share no 3-word sequence with any of its
   42 names or texts [V `agents/shop_crit/tools/textcheck.py`, run in the review round].

---------------------------------------------------------------------------------------------------------------------
## 13. Mockup and PNGs
`scratchpad/out/shop_design/mockup.html`: click-through (13 screens, iPhone/PC switch). Source and scripts:
`scratchpad/agents/shop_spec/build/` (`mockup.src.html`, `base.css` = the shared Menu/Studio CSS of the onboarding
mockup, `build.js` with the font `scratchpad/out/lab_design/fonts_dl/figtree.woff2`, `shots.js`, `sizes.js`). Rendered
with Playwright for Node and `/opt/pw-browsers/chromium-1194`, 844×390 and 1280×720 at deviceScaleFactor 2. Every
screen has the "DESIGN DRAFT · example values" tag in the Roblox top-bar strip and a note line saying what state it shows.
Review round, part 2: Studio tile spacing (the locked 7B tile's text touched its border), Identity Kit icon dots in Kit
colours, the real Frontier description, Studio note "no training running"; all 8 PNGs re-rendered and looked at;
`sizes.js` over all 13 screens × phone/PC: 26 of 26 with text ≥ 12 pt, targets ≥ 44 pt, nothing under the top bar,
nothing clipped or outside its box [V `agents/shop_crit/sizes_resume.txt`].

Example values: Robux prices = the suggestions of section 2; Frontier Architecture $65,000 · 500 RP · 120 s
(EmpireConfig.RESEARCH) [V]; Lab level 6→7 = 1,210 RP + $100,663 (`Ops.labCost(6)`) [V]; RP 320, speed +4.9 RP/s, cash
$214,300 / $513,560, 7B $61,755 and the stat bars are invented for the picture; "saves" values follow 5.3 with those
numbers (156.7 s → "about 2 min", 75 s → "about 1 min", 181.6 s → "about 3 min"). Font Figtree stands in for BuilderSans;
the Robux glyph is a stand-in. The 4.9 RP/s is labelled as the office-hours speed (5.2.2).

Measured in the mockup (`sizes.js`, all 13 screens × 2 devices): smallest text **12.0 pt** on the phone (20.4 pt on PC),
**every target ≥ 44 pt**, nothing under the top bar, no clipped text [V]. The review round added a containment check
(text and boxes must stay inside their card, tile, panel or button). It found the Studio size tiles 1.8 pt below their
panel and "7B · Deep" 1.2 pt below the model card on the phone (3.1 / 2.0 pt on PC); the Studio panel was tightened and
all 26 runs now pass every check [V re-run, `agents/shop_crit/sizes_after.txt`]. All 8 PNGs were re-rendered and looked at.

| PNG | Shows |
|---|---|
| `phone_1_shop_home.png` | Shop → Home: line, featured Style Collection (full section-2 text) with its 3 contents, 4 category tiles with counts |
| `phone_2_eureka_confirm_lab_level.png` | UseSheet "Use 1 Eureka on Lab level 7?" over the Lab level card (owned Eureka ×2; covers 1,210 RP, you pay $100,663, cash after, saves about 3 min) |
| `phone_3_studio_needs_research.png` | Model Studio step 2, 7B picked and locked by research only: warn hint, lock strip OPEN RESEARCH › + SKIP RESEARCH · EUREKA ⬡15, tiles, CONTINUE |
| `phone_4_boosts.png` | Shop → Boosts: running Keynote status card, Keynote row ×1 with ADD 15 MIN (⬡35), Overclock row ×1 with START |
| `phone_5_cosmetics.png` | Shop → Style: bundle tile, COMPANY LOOK rows (Identity Kit, Server Glow …) |
| `phone_6_lab_research.png` | Lab → Research: status row (SPEED IN OFFICE HOURS), Frontier (NEEDS 500 RP + EUREKA), Smart Quantization (START + EUREKA), saving lines |
| `desktop_1_shop_home.png` | Shop → Home at 1280×720 with YOUR ITEMS (Eureka ×2, running Keynote Boost) |
| `desktop_2_cosmetics.png` | Shop → Style at 1280×720 |

Further screens only in the click-through: Speed-ups, Extras, Studio owner preview, Lab level card without the sheet,
"Eureka received. Use it now?", Studio 7B with a VRAM lock (no Eureka offer, OPEN RESEARCH › + OPEN GPUS ›).
