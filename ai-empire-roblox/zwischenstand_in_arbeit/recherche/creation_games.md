# Creation-screen research: product-making tycoons and AI-training games

Research notes for the "AI Empire" Model Lab creator redesign. Date: 2026-10-10.
These are research notes, not a spec. Where a pattern is mapped onto AI Empire, it is a **proposal or assumption**, not a fact about any game.

## 0. Method and how far to trust it

- Fandom HTML pages returned 402/403 to WebFetch and curl. So I read the Fandom wikis through their public MediaWiki API (`api.php?action=parse&prop=wikitext`). The text is the same; only the access route differs. Raw copies: `agents/lab_research/raw/*.txt`.
- wiki.gg (the Mad Games Tycoon 2 wiki) is blocked from this container ("Blocked - wiki.gg"). MGT2 facts therefore come from its Steam store page and Steam forum threads only. Most of those are player posts.
- Game Dev Tycoon (GDT) formulas come from a fan wiki that was reverse-engineered from the game code. The wiki pages are tagged with game versions 1.3.9 to 1.4.5. The current game may differ.
- The AI-themed games are mostly **unreleased**. For them I could only read store marketing text.
- Confidence labels: **verified** = I opened the source and it says this. **community** = a player or fan source I opened. It may be wrong. **unverified** = only a search summary, or my own inference.

---

## 1. Per-game findings (with sources)

### 1.1 Game Dev Tycoon (Greenheart Games, 2012; PC, iOS, Android, Switch)
Sources:
- https://en.wikipedia.org/wiki/Game_Dev_Tycoon (verified: developer, platforms, mobile versions, start in a garage in the early 1980s)
- https://store.steampowered.com/app/239820/Game_Dev_Tycoon/ (verified: "the decisions you make during development really matter", "Decide which areas you want to focus on", custom engines, research, secret labs)
- Fan wiki, read through the API:
  - https://gamedevtycoon.fandom.com/wiki/Game_Development_Based_on_Experience/1.4.3
  - https://gamedevtycoon.fandom.com/wiki/Review_Algorithm
  - https://gamedevtycoon.fandom.com/wiki/Tech_and_Design_Points_Generation_Algorithm
  - https://gamedevtycoon.fandom.com/wiki/Custom_Game_Engine
  - https://gamedevtycoon.fandom.com/wiki/Experience
  - https://gamedevtycoon.fandom.com/wiki/Research_and_Unlock
  - https://gamedevtycoon.fandom.com/wiki/Critics
  - https://gamedevtycoon.fandom.com/wiki/Bugs
- Steam thread on game reports: https://steamcommunity.com/app/239820/discussions/0/864977564438785768

Creation flow (verified on the fan wiki):
1. **Pre-production.** The player picks a title, size (small / medium / large / AAA), topic, genre, platform and engine. A target audience (Young / Everyone / Mature) unlocks later through research.
   - Topic+genre, genre+platform and topic+audience each have a fit value. Fit is labelled from "Great" to "Terrible".
   - AAA games unlock only after "making a Large game with a score of 9.25/10 or higher".
2. **Development: three stages.** Each stage has three sliders that split the stage's time:
   - Stage 1: Engine / Gameplay / Story-Quests.
   - Stage 2: Dialogues / Level Design / AI.
   - Stage 3: World Design / Graphics / Sound.
   - Raising one slider lowers the others' share. The split is previewed on a composite bar under the sliders.
   - Each slider part produces a mix of Design and Tech "bubbles" from staff. The game counts them live: Tech in a blue circle, Design in an orange circle. Bugs are counted too. This is the **visible preview that grows** while you watch.
   - Custom-engine features come in groups and only one feature per group is allowed, e.g. "Linear Story or Branching Story, but not both".
3. **Finishing.** Bugs are removed before release.
4. **Reveal.** "A notification appears 3 ticks ... after to tell you that first reviews are out."
   - Four publications each show a score from 1 to 10 with a message: Star Games, Informed Gamer, Game Hero, All Games.
   - The messages come from queues built during scoring, e.g. "good balance", "focus on X served game well", "Great combination", "Too many bugs", "shouldn't forget about X".
   - So the reveal **explains itself in words**.
5. **The reviews compare you with your own best.** "In this game, you compete exclusively against your own previous high score".
   - Target = top score + delta × year modifier. A game only scores high if it beats your last best by roughly 10 to 20 %.
   - The wiki notes that some players call the fourth critic, All Games, "unfair". (Critics page, community.)
6. **Variety rules.**
   - Repeating the exact topic/genre combination of your previous game gives −0.4 quality.
   - A sequel within 40 weeks gives −0.4.
   - A sequel on a better engine gives +0.2.
   - XP bonus +0.2 each for: a new topic, a new combo, a great combo, a trend match. (Experience page, verified.)
7. **Knowledge layer: the game report.** It is available "the week after you release any game". It gives "between 2 and 5 hints", which then show under the sliders as +++ / ++ / + / - / --. A greyed "?" means the hint is borrowed from the same genre. (Steam thread, community; quotes from a player named Ralek.)
8. **Beginner on-ramp.** Few topics at the start. Since v1.4.0 the starting topics are random. More topics cost 10 RP each. You start in a garage with one person, yourself. (verified, wiki)

### 1.2 Game Dev Story (Kairosoft; iOS/Android since 2010, also Switch, PS4, Steam, Xbox). This is the phone-native one.
Sources:
- https://en.wikipedia.org/wiki/Game_Dev_Story (verified: platforms and dates; one reviewer gives 1-10 with a comment; weekly sales charts; Hall of Fame; sequels)
- https://kairosoft.fandom.com/wiki/Creating_games_(Game_Dev_Story) (API, verified)
- https://kairosoft.fandom.com/wiki/Magazine_Reviews_(Game_Dev_Story) (API, verified)
- https://kairosoft.fandom.com/wiki/Genres_and_types_(Game_Dev_Story) (API, verified)

Creation flow (verified, wiki):
- **Setup.**
  - Platform: console, CPU, media.
  - Genre + Type: combos are rated from "Not good" to "Amazing!". Genres unlock through staff job levels.
  - Direction:
    - Normal = base cost.
    - Speed = +20 % cost, quicker, lower quality.
    - Quality = +30 %.
    - Research = +50 %, more research data.
    - Budget+ = double cost.
  - Then you spend a small pool of points on eight "what will it be like" dials: Cuteness, Realism, Approachability, Niche Appeal, Simplicity, Innovation, Game World, Polish. The pool grows by 2 when a genre reaches level 2 and level 5.
- **Development.** Writing comes first, then Art at 40 %, Music at 80 %, then Bugs.
  - Points accumulate in four stats: Fun, Creativity, Graphics, Sound.
  - Live milestone messages: passing 50 in a stat gives "has a lot of fun/sound"; 100 gives "people lining up".
  - At 25 % a staff member offers to improve the game. This is a gamble: success gives +25-32 to one stat; failure gives 20-30 bugs and less hype.
  - Random events: blackout (−20..50 points), a similar game released by a rival (fewer sales).
- **Release reveal.** You name the game, then four critics give 0-10 each, 40 in total, each with a one-liner, e.g. "A masterpiece!!" (10), "So close and yet so far..." (7), "Rethink the combination." (4).
  - **32/40 or more = Hall of Fame**, which unlocks a sequel. The sequel "will start with some of the points from the original game".
  - The game announces whether you will make the sales chart and how close to #1 you will get.
- **History shelf.** The records keep "the latest 32 games". A sequel must start while the original is still in the records.

### 1.3 Mad Games Tycoon 2 (Eggcode, 2023; PC)
Sources:
- https://store.steampowered.com/app/1342330/Mad_Games_Tycoon_2/ (verified: garage to mega company; own engines or licensed ones; IPs; consoles with Pro/Slim versions; up to 100 rivals; "tons of charts"; difficulty from very easy to legendary)
- Steam threads (community):
  - https://steamcommunity.com/app/1342330/discussions/0/3833172420306649053 : four stats "gameplay, sound, graphics, technical"; "Games need a minimal amount of points in each of their four stats to get to 90%+"; at least one Game Designer; experience "stars" on genres/topics/features; target-group fit; don't release without debugging; polishing after release.
  - https://steamcommunity.com/app/1342330/discussions/0/3079873089702441389 : a "Game Analysis" feature puts green numbers on the sliders. A player wanted them removable. Reply from a user named Panda (the thread summary calls Panda a developer; not independently confirmed): it "works pretty good", and on Legendary it "would be a little too hard if you had no help at all from reports". Another player: "beginners play and the game is over without knowing how to improve the game".
  - https://steamcommunity.com/app/1342330/discussions/0/3039354735023925463 : players say the slider percentages matter less than total points.
- Search summary only (unverified): a review-aggregator site says players find the slider mechanic "unintuitive", "reducing gameplay to guessing values" (https://vaporlens.app/app/1342330/mad_games_tycoon_2.md, not opened).

### 1.4 Software Inc. (Coredumping; PC)
Sources: https://softwareinc.coredumping.com/wiki/ (official-domain wiki, read through the API). Pages: Software_Types, Game, Quickstart_Guide, Beginner's_Tips. The wiki tags the quickstart as {{Outdated}}.
- **Features with dependencies** (verified, wiki):
  1. Time-locked: features unlock by year.
  2. Dependency-locked: e.g. the Game feature "3D graphics" needs "Game Engine: 3D rendering" and "3D Editor: Vertex editing". Your other products gate this one.
  3. Dependency tree: evolutions replace each other, e.g. PC speaker becomes 8-bit audio, and you can pick only one.
- **Trade-off feature:** "QA ... will improve stability and usability at the cost of development time and innovation." (verified, wiki)
- **Project stages:** Design, then Alpha, then Delay, then Beta (bug fixing), then Release. "If you leave the project in the design stage for too long, you'll lose progress". (verified, wiki, outdated tag)
- **Beginner tip:** start with a smaller product a one-person team can make. (community)

### 1.5 Startup Company (Hovgaard Games; PC)
Sources: https://startupcompany.fandom.com/wiki/Getting_Started, /Frameworks, /Production_plan (API, verified).
- You choose a website type at the start ("Social Media is the most straightforward route ... recommended for beginners").
- **Limited feature slots:** "three at the moment, and it will take a good amount of time until you can unlock more". Frameworks raise the limits: max features 3 → 6 → 9 → 12, and max feature level 10 → 7000, bought with license cost plus RP.
- Features are Base / Revenue / Enhancement. A feature levels up by consuming components (UI, Backend from developers; Blueprint, Graphics from designers).
- An adviser, "Pam from Johnson Invest", gives milestone tasks as the tutorial.
- "Jitter" is an in-game social feed "to gauge public reaction to new features".

### 1.6 Phone-maker tycoons outside Roblox (the genre the user named)
Most of these list only marketing text. None of their score formulas are published.
- **Mad Smartphone Tycoon** (Miradil / Gamersky Games, 12 Sep 2024): https://store.steampowered.com/app/2891120/ (verified)
  - "comprehensive phone design page", "customize every aspect of their device".
  - Appearance: size, colour, material, camera. Hardware: processor, storage, battery.
  - The warning that a "blind leap on configuration may create high parameters but low sales": cost-effectiveness matters.
  - Marketing: slogan, product launch, adverts, "even attack competitors". Steam rating: Mostly Positive, 71 % of 577 reviews.
- **Devices Tycoon** (Oleksii Cherneha; iOS): https://apps.apple.com/us/app/-/id1631674811 (verified)
  - "device size, color, screen, processor, graphics card, speakers, packaging and much more".
  - "When your first devices start appearing on store shelves, you will have the first customer reviews. The higher the score, the better the sales!"
  - "view ratings of other companies around the world".
  - "16 offices" to buy and upgrade. 4.0/5 from 272 ratings.
- **Smartphone Tycoon - Lite** (Roastery Games, PC, 14 Apr 2020): https://rawg.io/games/smartphone-tycoon-lite (verified)
  - "design a device from scratch", "think of a name and a logo for it".
  - Pick screen, camera, processor, RAM, battery, then "set the selling price".
- **Smartphone Tycoon** (Roastery Games, PC 2019), review: https://www.tabletowo.pl/smartphone-tycoon-steam-opinia (verified, Polish)
  - Screen size and technology, body corner rounding, button placement, triple camera, processor platform, an OS tab.
  - The reviewer liked the large tech tree and the stylish animations.
  - He hit a bug: the OS screen's X button did not close it.
- **Smartphone Tycoon 2** (Oleksii Cherneha; iOS): https://apps.apple.com/app/id1470806544 (verified)
  - Short description only. 2.5/5 from 757 ratings.
  - User reviews quoted on the page: marketing/OS/news "seemed to do nothing"; a cheap phone sold expensive still made a profit; little real competition.
  - **Lesson: choices that do not visibly matter feel fake.**
- Roblox phone games turned up in search but are outside this note's scope: "Phone Store Tycoon" and "PROVE DAD WRONG BY MAKING PHONES", found via rowatcher.com. I did not open them, so they are unverified here.

### 1.7 AI-themed games (training or releasing AI models)
- **LLM Tycoon** (Futt Studio): https://store.steampowered.com/app/4861430/ (verified; the page says not yet released, planned 2026, demo available, no reviews). App 5071100 shows the same title.
  - Personality sliders: "Honesty, safety, tone, depth. Set the sliders however you like."
  - "Play it safe and reviewers call your model boring." Extreme slider positions make "strange things start to happen" (scandals).
  - "Your rivals wrestle with the same sliders".
  - Rivals react on an in-game social feed. Six eras from chatbots to superintelligence.
- **AI Lab Tycoon** (BT Games): https://store.steampowered.com/app/5015590 (verified; not yet released, planned 2026)
  - "Start in mom's garage." "Train, evaluate, and release new AI models"; "watch the market react".
  - Connected tech tree. Four office tiers.
- **AI Startup Simulator** (Small Hours): https://store.steampowered.com/app/5178270/ (verified; planned Q4 2026)
  - "Choose datasets, configure training, and allocate GPU resources." "Follow the training logs, save your finished models, and assign them to client jobs or launch AI services."
- **AI Magnate** (browser, desktop + mobile UI, released 22 May 2026): https://magnate-games.itch.io/ai-magnate and https://www.incrementaldb.com/game/ai-magnate (verified)
  - "Design models from scratch — choose what they can do, where their training data comes from" plus safety investment.
  - "Models age over time". "Miss a generation and your users start leaving."
  - Free / Pro / Max tiers that you price. Rivals "Titan Systems and NovaCore".
  - Final score = AGI readiness, model quality, research breakthroughs, finances, safety record.
- **Little Learning Machines** (Transitional Forms, released 6 Mar 2024): https://store.steampowered.com/app/1993710/ (verified)
  - A no-code reinforcement-learning trainer for robot companions. Choices shape "abilities and personalities". Training runs as a live simulation.
- **Roblox "AI Tycoon"** (Tycoon Republic): https://earlygame.com/guides/codes/ai-tycoon-codes, which links to https://www.roblox.com/games/16121315773/AI-Tycoon (verified on earlygame only)
  - Robot theme: "Train your big AI friend, unlock new rooms". **Not** a model-creator, so it offers no creation-screen pattern.
  - I found no verified Roblox game where you design and train an AI model.

---

## 2. Cross-game patterns: what makes the creation loop satisfying

| # | Pattern | Seen in (verified) | Why it works |
|---|---|---|---|
| P1 | Few big choices first ("what is it, for whom"): topic/genre/platform/audience; genre/type/console; website type; device parts | GDT, GDS, Startup Co, phone makers | The player commits to an identity before tuning numbers |
| P2 | Each pair of choices shows a fit rating ("Great combination" ... "Strange combination"; "Not good" ... "Amazing!") | GDT, GDS | A word label is easier to read than numbers; it teaches synergy |
| P3 | Fixed-budget split (sliders that sum to 100 % per stage; a points pool for dials) | GDT, GDS, MGT2 | Every gain costs something, which forces a real trade-off |
| P4 | Speed/quality/cost "direction" preset | GDS (Normal/Speed/Quality/Research/Budget+) | One tap that beginners understand |
| P5 | Mutually exclusive groups and dependency trees | GDT feature groups, Software Inc | Depth without a huge list; gives research a reason |
| P6 | A preview that grows live during production (point counters, bubbles, bug count, milestone messages) | GDT, GDS | Waiting turns into watching |
| P7 | A mid-production decision event (gamble or safe choice) | GDS 25 % event; GDT boosts | One moment of agency per run |
| P8 | A staged reveal: several critics, a score each, a short sentence each, with reasons taken from the real calculation | GDT (4 publications, message queues), GDS (4 critics, 40 points, one-liners) | Suspense, then explanation |
| P9 | Compare with your own best | GDT (the target is your top score), GDS Hall of Fame line at 32/40 | A personal record to chase |
| P10 | Compare with rivals and the market (charts, other companies' ratings, a rival releasing the same genre) | GDS sales chart + "similar game released"; Devices Tycoon; MGT2 charts; AI Magnate rivals | Places the result in a world |
| P11 | History shelf and sequels that inherit part of the old product | GDS (32 records; sequel keeps some points); GDT sequel rules | Progress you can see; a reason to iterate |
| P12 | Variety reward, repeat penalty | GDT (−0.4 for the same combo; XP bonus for new topic or combo) | Stops one-config spam |
| P13 | Knowledge that builds over releases (report hints shown on the sliders) | GDT game report, MGT2 Game Analysis | Beginners get help; veterans earn mastery |
| P14 | Unlock gates on achievements (AAA after a Large ≥ 9.25; Hall of Fame enables sequels; more feature slots via frameworks) | GDT, GDS, Startup Co | Clear goals |
| P15 | Name and identity (name + logo; appearance: colour, material) | Smartphone Tycoon Lite, Mad Smartphone Tycoon, Devices Tycoon | Ownership: it's *my* phone |
| P16 | Value warning: high specs are not the same as high sales | Mad Smartphone Tycoon store text | Teaches cost/benefit |
| P17 | Personality as a design axis, with reviewer and press consequences | LLM Tycoon | An AI-specific, emotional choice |

Simple for beginners, deep for veterans (verified mechanisms):
- Few options at the start, unlocked later: GDT random starting topics; GDS genres via staff levels; Startup Co 3 feature slots.
- A recommended path: Startup Co's adviser milestones; Startup Co's "Social Media ... recommended for beginners".
- Hints on the controls: GDT report symbols; MGT2 green numbers. Even the developers defend these for hard difficulty.
- Depth sits in hidden layers: GDT tech/design ratio, per-genre slider importance, trends. The wiki notes players need reference charts to master it. That is depth for veterans, and also a pitfall (see section 5).

---

## 3. What the current AI Empire creator has, and where the gaps are

Read from `out/models/lab_rich_strip_creator.png`, `lab_release_phone.png`, `lab_release_rich_strip_release.png` and `work/src/ReplicatedStorage/Shared/Config/ModelConfig.module.luau`.

Already present (good):
- Name field.
- Size segment 100M..7B (potential, dataNeed, VRAM).
- Focus segment with stat multipliers.
- Recipe segment: Quick pass / Balanced / Deep. This is like GDS "Direction" (P4).
- An expected-result panel with 6 stat bars and "Overall (estimate) / your best: 61.6 (−2.8)". This is partly P9.
- Data fill bar, cost, time, VRAM, compute.
- Training events at 35 % with choices, e.g. data issue "Clean it / Ignore", instability "Roll back / Push through (50 % chance)". This is P7.
- Product lines, versions, ageing, Refine 1/3, Lab level.
- Release view with audience fit per segment and a forecast. This is P2 and P10, but only at release.
- The phone layout already shows a top stepper: DATA ✓ / COMPUTE ✓ / DESIGN / TRAIN / EVALUATE / LAUNCH / GROW.

Gaps compared with the genre (observations; whether to fill them is for the lead/designer to decide):
- G1: **Target line is chosen only at release.** In GDT/GDS the "for whom" (platform/audience) is chosen up front and shown as a fit word. In the creator the player can't see "Coding focus × Developer API = Great fit" until the release screen (P1/P2).
- G2: **No identity or visual of the model.** It is a text form; phone games revolve around a device picture plus name/logo/colour (P15). Nothing on screen grows as you choose (P6 at design time).
- G3: **The reveal is not a moment.** The result view shows stats. There are no critic or benchmark cards, no one-line reasons, no "NEW RECORD" (P8/P9).
- G4: **No rival placement in the creator** ("would rank #3 in Coding"). CORE_SPEC 7.7 already requires live rivals for the forecast (P10).
- G5: **No history shelf or hall of fame** for past models (P11). Retired models are kept: `RETIRED_KEEP = 80`.
- G6: **No variety reward.** Nothing nudges the player to try a new focus×line combo (P12). Anti-clone is handled by line versions (CORE_SPEC 7.2).
- G7: **Long scroll form on a phone.** At 844×390 minus insets (58 top / 21 bottom in the preview) the creator is a ~841 px tall canvas.

---

## 4. Patterns that fit an AI-model creator (proposals, ranked by economy risk)

CORE_SPEC is binding for the economy. Each proposal says whether it touches the economy.

### 4.1 Zero economy impact (UI and presentation only, derived from existing numbers)
1. **Model card preview (P6, P15).** A visual "core" that grows with the size choice, is tinted by focus, gets a ring that fills with Data fill, and wears a badge for the target line. Name + icon/colour picker. Cosmetic only.
   - Assumption: icons drawn from UI primitives or text glyphs, because **no asset ids may be invented**.
2. **Fit words (P2).** In the creator, show the *existing* line fit (the release view's "Audience fit") as a label per line, e.g. "Great fit: Developer API". Thresholds come from existing fit values. The label wording is a proposal.
3. **Step layout for landscape phone (G7).** Four steps:
   1. What & for whom: name, target line, focus.
   2. Size & data: size, data fill, VRAM check.
   3. Training plan: recipe, cost, time.
   4. Review & start.
   - A fixed left column holds the model card + Overall + delta vs best. A fixed bottom bar holds the main action button.
   - The stepper pattern already exists in the phone release layout. The exact layout is a design decision; this is a suggestion.
4. **Staged reveal (P8).** After training, show 4 "reviewer" cards one after another. Proposal: one card per product-line audience (Consumers, Students, Developers, Businesses), using the existing segment fit numbers. Each card gets a short line chosen from **real** causes (focus matched the line; data fill under 100 %; Deep training on thin data; reliability high or low).
   - Fictional publication names only. No real outlets or brands.
   - Messages must never claim something the maths didn't do.
5. **"vs your best" and "NEW RECORD!" (P9).** Already partly there ("your best: 61.6 (−2.8)"). Make the reveal celebrate a new best.
   - Use **absolute** scores. Do *not* copy GDT's moving target (see pitfalls).
6. **Rival placement (P10).** "Would rank #N of M in <line>". Computed from live marketplace offers. CORE_SPEC 7.7 already moves the forecast to live rivals.
7. **History shelf / Hall of Fame (P11).** A horizontal strip of past models (name, version, Overall, line, best rank). Hall of Fame badge above a threshold.
   - Existing data: retired models with `replacedBy`. Cosmetic.
8. **Live training preview (P6).** During training, stat bars climb toward their estimates, with milestone toasts, e.g. "Coding passed 60: better than Coder v1". Like GDS's 50/100 messages. Uses only the estimate and progress already computed.
9. **Personality step (P17) for the model chat only.** Tone (Friendly / Formal / Funny / Nerdy), emoji use, catchphrase.
   - LOGIC_BRIEF request 16: model chat reads `name/stats/overall/sizeId/focusId` only and has **no** economic effect.
   - A personality field would feed the chat system prompt or the authored fallback replies. It must stay economy-free.
   - This is AI-specific and very likely fun for a teen. Assumption, not tested.

### 4.2 Small economy touch (needs a CORE_SPEC check or sim before shipping)
10. **Variety bonus (P12).** E.g. "new focus×line combo: +X research points", or a small XP/fame bonus. Needs tuning in the sim.
11. **Hints that build up (P13).** After each release, reveal which stats each line's audience values most. These are the existing segment weights. Show them as +++/-- on focus choices once "discovered". Display-only if the weights are already fixed; it changes how quickly players optimise.

### 4.3 Real economy changes (v2 ideas; need design + sim)
12. **Capability slots (Startup Co P5/P14, Software Inc dependencies).** E.g. Long context, Tool use, Vision, Voice.
    - Unlocked by Lab level or research. Each needs a data type, e.g. Vision needs an image dataset. This is a dependency-lock like Software Inc's "3D graphics needs Engine 3D rendering".
    - Cap of 1 → 2 → 3 slots by stage, like Startup Co's 3 → 6 → 9 → 12.
13. **Safety/alignment trade-off (Software Inc QA, LLM Tycoon, AI Magnate).** E.g. a "Safety tuning" choice that moves points from Creativity to Reliability and costs time. Software Inc's QA "improve[s] stability ... at the cost of development time and innovation".
14. **Training-method group (P5).** One per group: Pretrain only / Instruction-tuned / Feedback-tuned (RLHF-style) / Distilled from your best model. Distilled would echo the GDS sequel that "start[s] with some of the points from the original game".
15. **Data mix split (P3).** A 3-way split of general/code/math for this run.
    - Today the mix is the company stock: `ModelMath.dataSummary` shares, bought in DataApp.
    - A per-run split would be a fixed-budget trade-off like GDT's sliders. It changes stat outcomes, so it is an economy change.

Domain components for an AI model (realism check; game mapping is my proposal): parameters/size, training data (amount, quality, mix), training method, compute budget, safety tuning, personality/tone, context length, modalities (text/vision/voice), tool use, speed vs quality (serving cost). Size, data amount, quality, mix and the compute/recipe already exist in ModelConfig. The rest are proposals.

---

## 5. Pitfalls (from sources)

- **Opaque "guess the slider" maths frustrates.** MGT2 needed a "Game Analysis" hint layer, and its developer-side reply defends hints for hard modes (community). A search summary says players dislike the sliders as guessing (unverified). GDT players rely on wiki charts (community). → Show the consequence of every choice in the live preview.
- **A moving target can feel unfair.** GDT compares each game with your own top score plus about 10-20 % (fan wiki). A good model can then "score low". A teen will read that as a bug. → Keep absolute scores; show "vs your best" as a separate delta.
- **Choices that do nothing feel fake.** Smartphone Tycoon 2 user reviews on the App Store page say marketing/OS/news seemed to do nothing. → Every option must move a number on the preview, or be clearly cosmetic.
- **Specs vs value.** Mad Smartphone Tycoon warns that high parameters can mean low sales. → Show serving cost / value next to Overall, so 7B isn't always "best".
- **Too many options on a small screen.** Startup Co caps early features at 3 slots. GDS uses one points pool. → Start with 3 choices (line, focus, size) plus a recipe preset; unlock the rest.
- **Bugs in UI flows.** The Smartphone Tycoon review: the OS screen's X button did not close it. → Every step needs a working Back/Close on touch and gamepad.
- **Don't invent anything.** No real publication or company names in reviewer cards; no asset ids; no Roblox APIs beyond those already checked (LOGIC_BRIEF section 3). The unreleased AI games are marketing copy only, so don't cite their mechanics as proven.

## 6. Not verified / open
- MGT2's exact slider list (wiki.gg blocked). The forum lists the stats as gameplay/graphics/sound/technical (community).
- Whether Panda in the MGT2 thread is really an Eggcode developer.
- Any Roblox phone-tycoon creation screen (outside this note).
- Whether the GDT fan-wiki formulas still hold in current versions.
