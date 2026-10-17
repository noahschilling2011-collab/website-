# Research notes: Roblox "make a product" creation screens (for the AI Empire Lab creator)

Date: 2026-10-10. Research only, no game files changed.
Confidence tags: VERIFIED = I saw it myself (official Roblox API text or a real screenshot or video frame I opened).
LIKELY = a fan site describes it, it fits what I saw, but I could not read it myself.
UNVERIFIED = a claim with no visual or official confirmation. ASSUMPTION = my own interpretation.

Local evidence (all opened with Read):
- thumbs/on_design-studio-step-{1,2,4,6,10,11,13}*.png: Design Studio steps (1280x720 frames from Ricoko's video, cropped by the fan hub)
- thumbs/on_launch-day-panel-*.png, on_your-phones-*.png, on_sales-run-complete-*.png, on_research-tab-2018-*.png, on_hud-research-complete-*.png
- vid/Jh-nnWCn9f4_maxresdefault_big.png (Design Studio step 3 in the MOBILE layout), vid/Jh-nnWCn9f4_hq3_big.png (step 12, mobile)
- vid/oCb2DRp69Mw_hq1_big.png (launch reveal with confetti + "8.7/10 EXCELLENT"), vid/contact_0.png / contact_5.png / contact_b.png (many reveal-stage frames)
- vid/wrkCVXm2bGc_hq2_big.png (office with "IN DEVELOPMENT" wall TV + a "... is ready" card)
- thumbs/bape_1..3.png (official game thumbnails: marketing art only, no UI)
- raw/games.json (official descriptions from games.roblox.com), raw/online_*.html.txt (fan hub text)

## 0. What I searched and what I found
Roblox omni-search (apis.roblox.com/search-api) for: phone tycoon, make a phone, phone maker, phone company, design phone,
smartphone, phone empire, phone factory, phone simulator, build a phone, tech company tycoon, game dev tycoon, ai tycoon,
ai company, laptop tycoon, car factory tycoon, sneaker tycoon, robot factory tycoon, console tycoon, computer tycoon.
Only ONE Roblox game I found has a real "design your own product" screen: **Build a Phone Empire**. The other phone games
are classic button or conveyor tycoons (their descriptions mention no design step). YouTube downloads were blocked
(bot check), so video evidence = YouTube's public thumbnail and auto-frame images (i.ytimg.com hq1/hq2/hq3) + frames published on a fan site.

## 1. Build a Phone Empire (main reference; closest match to the wish)
- Link: https://www.roblox.com/games/101914705206759/Build-a-Phone-Empire (universe 10767582899). VERIFIED (API)
- Creator: DEVTEC STUDIOS (group). Created 2026-09-22, updated 2026-10-10, 1,706,894 visits, about 7,780 playing on 2026-10-10. VERIFIED (games.roblox.com)
- Official description (VERIFIED, quoted): "Start in a garage in 2007 and build the biggest phone company in the world." /
  "DESIGN every device yourself: screen size, cameras, corners, buttons, colour, finish and logo. Pick the parts, set the price and hand it to your team." /
  "RESEARCH new tech year by year and unlock tablets, smartwatches, earbuds, foldables and laptops." /
  "LAUNCH with a marketing campaign, read the critics' reviews and watch sales come in live." / "Plays on phone, tablet and PC".
  NOTE: it ALSO starts in a garage, like AI Empire. ASSUMPTION: this is likely the kind of game the user means.

### 1.1 Design Studio layout (VERIFIED from frames)
- Full-screen takeover, dark navy. Header "Design Studio" + "2007 · <company> · time is paused".
- Top right: Undo, Redo, Concept shelf, orange "← Back to office".
- Top-left badge "COST TO MAKE $65" + "Untitled phone" + "3.7" screen · #1E1E22 · 2.70 × 4.30 × 0.43 in" (updates live: $65 → $80 → $82 → $83 → $96 across the steps).
- CENTRE: large 3D phone preview that changes with every pick (shape, screen, camera bump, colour, home-screen icons incl. the company logo app).
- LEFT rail "VIEW": Auto / Spin / Front / Back / Side / Bottom, zoom − / +, green "Spin: On".
- RIGHT panel: "STEP N OF 13", title, a one-line hint, then the options; Back + big blue Continue at the bottom (seen on step 3 and step 12).
- BOTTOM: a strip of numbered step pills 1..13; the current one widens to show its name ("3 · Screen size").
- Mobile (VERIFIED, frame from UrbanBloom's video with the Roblox mobile top bar): same 3-column layout at phone landscape; header "… $87 per phone".
  PITFALL seen: the Roblox top-bar buttons cover the "Design Studio" title on both PC and mobile (shows as "esign Studio").

### 1.2 The 13 steps (LIKELY list from the fan hub, which reads Ricoko's video; steps 1, 2, 3, 4, 6, 10, 11, 12, 13 VERIFIED in frames)
1 Device: cards Phone ("The classic. Biggest market.") and greyed Tablet / Smartwatch / Earbuds / Foldable, each showing "Not invented until 2010/2014/2016/2019". VERIFIED
2 Chassis: hero card "Chrome Slab · Brand new" + description + "Freshness" bar 100%; hint "Critics love a new body design. Every year a chassis gets older it loses about 16% freshness."; locked cards "?" "Arrives 2008/2009"; footer "Unit cost for this chassis: $4. Newer designs are also thinner." VERIFIED
3 Screen size: big "7.1"" readout, presets Compact / Balanced / Big, sliders Width 3.10 in / Height 6.40 in, hint "Drag the corner handle, or use the sliders." and green note "Go wild with the shape. Size does not change reviews." VERIFIED (mobile frame)
4 Screen type: groups Resolution / Refresh rate / Technology. Each row = name + small 1-3 segment tier bar + price on the right; picked row has a blue outline + check; other rows show the DIFFERENCE ("-$11" in green); locked rows say "Arrives 2009" (orange) or "Needs research". Hint "Newer panels impress critics but cost more at first." VERIFIED
5 Selfie camera: None / 0.3 MP. LIKELY
6 Back cameras: "ON THE BACK · 1 OF 4", "ADD A LENS: More lenses arrive with research in the Camera group.", Position chips (Top left / Top middle / Top right / Centre) OR drag a "Move" handle on the 3D phone, Camera bump None / Circle / Square / Pill / Bar, lens rows with prices. VERIFIED
7 Corners and bezels (sliders; "border size does not change reviews"). LIKELY
8 Side buttons (side + height; "Its position does not affect reviews"). LIKELY
9 Charging port ("Slide the port along the bottom edge"). LIKELY
10 Specs: hint "The expensive part. Every upgrade adds to the unit cost."; preset buttons "Cheapest everything" / "Best I have"; groups CPU/GPU, RAM, Storage (ROM), (Battery); this panel scrolls on PC. VERIFIED
11 Features: "Turn on what you've researched." toggle rows, e.g. GPS "$4 per unit". VERIFIED
12 Colour & branding: "Pick the finish and place your brand on the device."; colour square + hue bar + hex + swatches; finish cards (Classic, Soft Matte, Carbon Fibre, Brushed Metal; some starred = premium, ASSUMPTION). VERIFIED (2 frames)
13 Final review: "Set a price and hand it to your team."; tiles TO MAKE ONE $96 / FACTORY SETUP $30,000 / YOUR CASH $56,700; text "Building it costs about $240 a day in prototypes and testing (brand-new parts cost extra). After that you order your first batch of phones."; PRICE field with − / +; live "$134 profit per unit · 58% margin"; chip "Suggested $261"; big blue "Begin development"; "The critics' score stays a surprise until launch day."; "+ Show parts list". VERIFIED
- I saw no naming step; the phone stays "Untitled phone" until step 13 (where the name is set is UNVERIFIED).

### 1.3 Development to launch (VERIFIED unless marked)
- After "Begin development" the team builds it in the office. The office wall TV between two leaderboards shows "IN DEVELOPMENT <name>" and later "NOW ON SALE <name>".
- HUD slot "IN DEVELOPMENT  Neveline 1 · ready".
- A "<name> is ready" card in the office with a coloured progress bar, two circular gauges (58 blue, 26 red), buttons (one green). Labels unreadable at 480p; ASSUMPTION: quality and bugs. Launch panel shows "Bugs left: 0". LIKELY
- LAUNCH DAY panel: device render on the left + "Price $220 · Cost to make $96 · Bugs left: 0 · Development cost $6,000"; then
  "1. Advertising campaign" = 4 cards (No marketing Free "BASELINE DEMAND" / Online ads $60,000 "+40% EARLY DEMAND" / TV campaign $400,000 "+90%" / Global launch event $1,500,000 "+180%", each with a bar);
  "2. What this campaign does" = "ESTIMATED FIRST-WEEK DEMAND 36 potential buyers · No ad boost · Available in 30% of the world. Actual sales also depend on reviews, rivals, and stock.";
  "3. Automatic production" = "Opening batch: 100 phones · $9,646 production cost · covers about two forecast weeks. Stock replenishes automatically.";
  footer "Factory setup $30,000 • advertising $0 • first batch $9,646", big "Launch total: $39,646", "You have $52,800 · $13,154 left after launch".
  PITFALL seen: two news toasts sit on top of the campaign cards.
- REVEAL: a dark 3D stage with spotlight beams and neon pillars, the device spins on a lit podium, title "INTRODUCING / <name>", confetti, left card "LAUNCH DAY" (units, revenue …), right card score "8.7 /10 ★★★★☆ EXCELLENT". Fan hub: 7.4 is labelled "GREAT" (LIKELY). It shows up in almost every YouTube frame → it is the highlight moment.

### 1.4 After launch (VERIFIED)
- "Your phones — Your devices on sale, and how they stack up against the competition": left list "Your devices" (name, "50 in stock · 50 sold", score 7.4) + "Competitors on the market" (rival name, company, price, launch date, score, e.g. pPhone 2 · Pear · $249 · 7.6).
  Right: big render + tiles CRITIC SCORE 7.4/10, PRICE, COST PER UNIT, UNITS SOLD, REVENUE, PROFIT (ALL COSTS) -$34,646 (red), IN STOCK, SOLD LAST WEEK, MISSED SALES; "NEW PRICE [220] Update price / Discontinue"; one line "Buyers think a 7.4/10 device is worth about $239 today."; "Automatic production is on"; chart "Units sold per week".
- Goal toast "GOAL COMPLETE Launch a phone rated 6.5 or more +$20,000" (goals use the score).
- HUD "On sale" cards per product: name, week, price, CRITICS 9.3, SOLD, REVENUE, PROFIT, BUZZ bar %, mini sales bars, "230 in stock · ~1 wk".
- "SALES RUN COMPLETE" summary: verdict pill "BIG SUCCESS", "TOTAL PROFIT (AFTER EVERY COST) $219,577", "+143% return", tiles units / revenue / best week / missed sales, "WHERE THE MONEY WENT" stacked bar (Development / Launch + marketing / Building phones / Warehouse), "UNITS SOLD PER WEEK" bars, tip "47 unsold phones went to discount stores for $1,133. Order a little less next time.", buttons **"Design its successor"** and "Continue".

### 1.5 Research (VERIFIED)
- Timeline tree: columns = years, a gold "today" line, lanes = Selfie camera / Main camera / Extra cameras / CHIPS CPU/GPU / MEMORY RAM, Storage / BATTERY / NETWORK / SOFTWARE OS / PORTS, colour per category, nodes "Researched" (check) or locked "Invented 2019".
- Left panel: RESEARCH POINTS 3414 "+14.1 per day", "78 of 144 technologies" bar, nudge card "The lab is idle — Pick something below or a glowing card on the tree.", selected card "CAMERA · READY Depth sensor lens" + plain description + tiles COST 474 RP / TIME 22 days / INVENTED 2017 + "Needs Telephoto 2x lens" / "Leads to Macro lens" + orange "Start research · 474 RP".
- Toast "Research complete: Octa-core + AI chip!" + HUD card "New parts unlocked for your next design!" → research feeds straight into the Design Studio's locked rows.

### 1.6 Monetization (VERIFIED, apis.roblox.com game-passes for universe 10767582899, prices in Robux)
Complete Bundle 449, Triple Research 99, Hyper Speed 49, 2x Money 149, Lab Grant 79, Extra Design Slot 99, Premium Finishes 35,
Logo & Wallpapers 25, Star Recruiter 49, Auto-Hire 25; Auto-Research, Launch Reveal Pack, Company Branding Bundle listed without a price.
Power passes (2x Money, Triple Research, Extra Design Slot, Lab Grant) = pay-to-win pressure. Cosmetic ones (finishes, logo/wallpaper, launch reveal) are the friendly model.

## 2. Other Roblox games checked (no comparable design screen)
- PROVE DAD WRONG BY MAKING PHONES: https://www.roblox.com/games/15838011628 (best tycoons studio, created 2024-01-01, 46.1M visits). The description only has the story premise. VERIFIED (API).
  "Assembly line, sell phones on the street" comes only from a search snippet of Sportskeeda (that page returned 403 to me). UNVERIFIED
- Phone Store Tycoon: https://www.roblox.com/games/107713910741616 (Mega Tycoons Studios, 25.2M visits); calls itself "part 2" of Prove Dad Wrong; store tycoon. VERIFIED (API)
- 2 Player Phone Tycoon: https://www.roblox.com/games/7260410655 (Stylized Games, 38.4M visits): "Choose your character and build your tycoon!". VERIFIED (API)
- make phones to escape poverty tycoon: https://www.roblox.com/games/13485892431 (2.5M visits). VERIFIED (API)
- Make Games: https://www.roblox.com/games/93974749507336 (Triggurod Studios, created 2026-07-23, 2.68M visits): "Create games, choose genres and themes, improve your Graphics, Mechanics and Sound, get reviews". VERIFIED (API). I found no UI evidence; the thumbnails show only the 3D studio, plus one image with the game being made floating as a 3D diorama above the developer's PC (ASSUMPTION about what it means).
- Build an AI [💻 HACK]: https://www.roblox.com/games/84637477108843 (Lucky Loop, 11.3M visits): "train your AI from Tiny Model all the way to AGI", "REBIRTH to release your AI v2, v3, v4". VERIFIED (API); no creation screen (thumbnails are marketing art).
- A YouTube "phone factory tycoon" by Quacks (4I03WRgm21U) shows conveyor upgrade cards ("Phone Space (0/5) 250 Cash Purchase"). Which Roblox game it is: UNVERIFIED.

## 3. Patterns worth copying (mapped to AI Empire)
1. Step wizard instead of one long form: "STEP N OF M", one decision per screen, hint line, Back / Continue, step pills you can tap to jump.
   AI Empire has fewer real parameters → about 6 steps: Product line → Size → Focus → Training plan (budget/validation) → Name & look → Final review.
2. Persistent cost badge at the top-left that updates on every tap (AI Empire: training cost + time + VRAM), plus a short spec line under it.
3. Option rows: name + small tier bar + price; the selected row shows its price, other rows show the delta (green "-$x" / "+$x"); locked rows stay visible with the exact reason
   ("Needs 32 GB VRAM", "Lab level 3", "Unlocks at Startup Campus") instead of being hidden.
4. A live preview object in the centre that reacts to each choice (for an AI: a model "core"/card that grows with size, gets the focus colour, shows the name).
   It must come from parts/Neon/ViewportFrame; never use invented asset ids.
5. Honest hint per step that says what affects quality and what is cosmetic ("Size does not change reviews"). AI Empire: "Focus adds +X to Coding, −Y elsewhere", "Name and colour are only looks".
6. Presets to save taps: "Cheapest everything" / "Best I have"; "Compact / Balanced / Big"; "Suggested $261" chip; − / + steppers.
7. Final review = 3 money tiles (cost / setup / your cash) + money left after starting + one big primary button.
8. Visible "in development" state in the world: office wall TV, HUD slot, then a "ready" card. AI Empire: data-hall screens + the training banner.
9. Launch panel in 3 numbered sections (campaign tiers with "+% early demand" bars → estimated first-week demand with a plain caveat → production/serving) and a "Launch total … left after launch" line.
10. Reveal ceremony: spotlight stage, spinning product, "INTRODUCING <name>", confetti, score card "8.7/10 ★★★★ EXCELLENT" + a label word. AI Empire's "3-2-1 MODEL LIVE" text could become this.
11. Score kept as a surprise ("The critics' score stays a surprise until launch day"). AI Empire shows the exact "Expected 58.8" before training; to keep suspense honestly, show a range and reveal the exact number at the end (design choice for the lead).
12. Product page compared with rivals (list with scores and prices) + "worth about $X today" one-liner + weekly sales chart; this fits CORE_SPEC 7.7 (live rivals).
13. A run summary with a verdict and "Design its successor" → maps to CORE_SPEC 7.2 (a new release into a line = the next version) and 7.3 ageing.
14. Research shown as unlocks for the NEXT design ("New parts unlocked for your next design!"), and locked rows in the creator say which research unlocks them.
15. Goals tied to the score ("Launch a phone rated 6.5 or more").

## 4. Pitfalls
- 13 steps every time is many taps for the 10th phone. Fix ideas: "Train again with the same plan", "Train its successor" pre-filled, step pills to jump (the Concept shelf may do this; its purpose is UNVERIFIED).
- "time is paused" works in their game; AI Empire runs on a shared server clock (EmployeeConfig day), so the creator cannot pause time. Don't copy that line.
- Roblox top bar / safe area overlap (seen in their frames). Use the existing CoreUISafeInsets handling; keep the title under the inset.
- Toasts covering the decision panel (seen on their launch panel).
- Long option lists need scrolling inside the panel (their Specs step scrolls). On 844x390 keep ≤ 4–5 options per step and text ≥ 14 px.
- Hidden scores can feel random if hints don't explain what matters. Pair the surprise with clear per-step hints and a post-launch "why" breakdown.
- Pay-to-win passes (2x Money, Triple Research, Extra Design Slot, Lab Grant). For AI Empire keep power passes off (ids default 0) and prefer cosmetic items (launch-stage effects, model-card skins).
- Their price is free-typed. AI Empire already uses a menu price + Recommended + Auto price (CORE_SPEC 7.7). Keep it; it is easier on a phone.
- Current AI Empire creator (lab_rich_strip_creator.png) is one long scroll form, 858x841 canvas at 1280x720; on 844x390 everything needs scrolling (lab_release_phone.png: the main launch button is cut off at the bottom).
