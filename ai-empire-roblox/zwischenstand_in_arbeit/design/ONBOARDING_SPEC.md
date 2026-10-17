# AI Empire: ONBOARDING_SPEC (binding): "First steps" guide, the new Menu and the Robux shop

Date: 2026-10-11, **revision 2** (critic pass, see 0.6). Status: **binding for the builder**, except the items in
section 0.3, which wait for the owner or the lead. Paths are relative to `scratchpad/work/src` unless they start with
`scratchpad/`. Line numbers are hints only, because other packages edit these files. Search for the quoted names instead.

Builds on `scratchpad/agents/onboarding_design/design.md`, which has the full reasoning and is called "design" below.
It also builds on the research notes `scratchpad/agents/onboarding_research/{onboarding,menu,shop}.md`, CORE_SPEC and
LAB_SPEC. Where this file and the design disagree, **this file wins**. Section 0.4 lists every difference.

Mockup: `scratchpad/out/onboarding_design/mockup.html`, a click-through with 19 screens and an iPhone/PC switch. PNGs
are listed in section 8. Mockup source and render scripts: `scratchpad/agents/onboarding_design/build/`.

Tags:
- **[V]**: I checked it today in code, in `tools/API-Dump.json`, in a render I looked at, or on a source page I opened.
- **[R]**: from the research notes. The research agent opened the source, and the note gives the section.
- **[A]**: an assumption or design choice that Roblox Studio or a playtest must confirm.

---------------------------------------------------------------------------------------------------------------------
## 0. Summary, decisions, sources

### 0.1 The user's wish
| Wish (translated from German) | Answer |
|---|---|
| "A tutorial for the start: what you have to do first, how you release your first AI" | **A.** A 5-step "First steps" guide in the HUD goal card, from spawn to the first released AI and its first income. A gold ring marks the one button to press, and the guide never blocks a tap. Progress comes from game state. It can be skipped and it resumes after a rejoin. From spawn it takes 3 taps to start training and 5 to a live AI, about 2 min 10 s of real time (≤ 2 min 40 s with a training decision; budget in A3.1). |
| "Make the menu easier to understand" | **B.** One Menu with 6 labelled entries (Home, Lab, Market, Clients, Team, Shop) replaces 9 apps, 7 journey chips and 9 Company tabs. There are at most 2 levels. Home shows the 3 next actions. Entries unlock in steps and show NEW badges. Phone sizes are real: text ≥ 12 pt and targets ≥ 44 pt, where today they are about 5–7 pt. |
| "Add a Robux shop" | **C.** The shop already exists, but every id is 0, so it only says "Shop coming soon" [V]. It gets a clear place (a Menu entry, plus a HUD button after the first launch), a better page, honest texts, a Studio owner preview, and a German guide for the owner. **No ids are invented.** |

### 0.2 Binding decisions
1. **The guide lives in the existing HUD "Next goal" card** (top right) in a guide mode, plus one ring layer. There is
   no new card at the top left. That spot belongs to the Roblox chat (comment in HUD.module.luau) [V comment], and the
   top centre holds the toasts (Toast holder 440 px centred, y 16) [V].
2. **Progress comes from game state** through the pure function `TutorialMath.step(data, live, ui)`. The save only
   stores flags and the highest step reached.
3. **The guide sends the player straight into the Model Studio quick start** (LAB_SPEC 2.2: the first model opens at
   "6 Review"). The HUD goal routing bug (a fresh save opens Datasets) gets fixed whatever else happens.
4. **No new reward.** The guide points at the existing quest rewards: founder $1,200, data $1,800, train $2,500 and
   release $3,000 (EmpireConfig.QUESTS) [V]. CORE_SPEC 1.2 already counts them.
5. **Build order P1 → P2 → P3** (section 6). The guide (P1) works with today's Computer.
6. **The lab package's files are untouched:** Studio, LabApp, DesignSteps, Stages, LaunchDay, LabPreview, LabState and
   StudioParts. The guide only reads `Studio.mode` / `Studio.isOpen()` and finds 5 named buttons.
7. **No new remote.** EmpireAction and ClaimQuest are extended.

### 0.3 Waiting for the owner or the lead (the builder does NOT do these without a "yes")
| # | Question | Default until answered |
|---|---|---|
| O1 | **Cap the cash packs** at Series A 0.5× and Series B 1.0× of the next office price (today 0.75× / 2.0×, CORE_SPEC 11.7). The math is in C5. | Shares stay as they are. Only the false code comment "Packs save minutes, not hours" is corrected. The shop texts are computed from `share`, so they are right either way. |
| O2 | Robux prices on the Creator Hub. | The owner chooses. The ShopConfig comments (49/129/299/39/25/25/100/149/199/199/349) are only suggestions [V]. |
| O3 | Whether the company name ideas (A7) are acceptable. | Builder uses the list in A7. |
| L1 | Phone HUD panel in compact form (A2.2): users move to Menu → Home, reputation and rank to Market, on phones. | Do it. It keeps the HUD column above the jump button (top at 279 pt, A2.1). |

### 0.4 What changed against design.md (and why)
1. **Assistant name:** the design's example "Mia" is not in `CampusConfig.FIRST_NAMES_F` [V]. The card uses the first
   name of `AssistantService.identity(userId)`. My JS port of that formula gives "Ada Costa" for user id 1 and −1
   (Studio test players), so the mockup shows "Ada" [V port; A until the test in section 7 #T5 passes].
2. **Phone HUD panel becomes compact** (A2.2). In the mockup, the full panel plus the guide card plus the row pushed
   the column to ≈ 344 pt, past the jump button. Revision 2: the jump button top is **279 pt**, not the remembered
   300 pt (A2.1), so the paddings were tightened as well. The column now ends at **265 pt** (guide) and **267 pt**
   (hand-off), 13.5 / 11.6 pt above the jump button, measured in the mockup [V mockup; A for the device insets].
3. **Caption:** "FIRST STEPS · n/5" plus a 5-segment bar (step 3's segment fills with training progress), instead of
   five dots. The design version did not fit in 272 px.
4. **The step 1 line changes:** the greeting shows for 8 s or until the first input, then an instruction per input type.
5. **Step 2 holds when the Studio is closed:** a saved `step ≥ 2` keeps step 2 instead of falling back to step 1.
6. **The dim hole for HUD targets** is the guide card plus the button row, so the greeting stays readable.
7. **The chip carries an action phrase** ("Tap to open the lab"), **world steps only**, left of the HUD column.
   Revision 2: no chip on Studio or Menu targets. In the Studio every spot next to the ringed button is another button
   (the Review's `ReviewLines` tile with BREAKDOWN › is a TextButton [V DesignSteps]), so the chip broke the "never over
   a button" rule. The ringed button's own label ("BUY DATA PLAN · $7,400", "LAUNCH CHAT · …") is the instruction.
8. **No money number in the step 5 line.** The compact panel shows the income.
9. **Guide row:** the left button shows only when quests can be claimed. Otherwise the action button is full width.
10. **During steps 1–2** the C key and the HUD "Open company"/"Menu" button also open the Studio design view, the same
    redirect as the founder computer.
11. **Shop:** one-column list rows (1102×126 px) instead of 2-column cards. The honest texts need 2 lines of about 70
    characters, and a 559-px card leaves only about 250 px for text.
12. **Menu tokens:** the Studio's tokens on every device (LAB_SPEC 3.3/3.4). Desktop uses the extra canvas height
    (648 px) for a Goals row. There is no separate desktop token set.
13. **Sub-tabs** are separate 74-px buttons (44 pt). The NEW pill sits beside the rail icon, not over it.
14. **Company names** go in `CompanyConfig.COMPANY_NAME_IDEAS`, because `LabState.NAME_IDEAS` already exists for model
    names [V].
15. **Highlight colour** is `C.warn` (gold), the same as the ring: gold means "press this".
16. **Intro line:** "You start in a garage with $10,000. Build the biggest AI company." There is no "old laptop" claim.

### 0.5 Sources
I opened each of these today:
- Roblox onboarding techniques, https://create.roblox.com/docs/production/game-design/onboarding-techniques:
  - "Highlighting something that players should look at is more effective than describing it in text."
  - Persistent hints "stay on-screen until the player has completed a step".
  - Timed hints: "most players find and press the button within 10 seconds", so "a highlight to the button at 11
    seconds".
  - Hints "only appear the first time the task is presented" and "only be shown to those who need it".
  - "Delaying non-essential information to future sessions reduces what they must learn".
  - "Players generally don't like to read instructions". [V]
- Funnel events, https://create.roblox.com/docs/production/analytics/funnel-events:
  - "Events can only be sent from the server and in published games."
  - "If for some reason you skip a step in a funnel, the earlier steps automatically complete."
  - "the funnel only considers the first instance of the step". [V]
- Monetization, https://create.roblox.com/docs/production/monetization:
  - "Users must never be misled, confused, or pressured into purchases in ways they did not intend".
  - No always-on discounts and no very short ones.
  - No countdown timer "that isn't accurate or automatically restarts".
  - For minors: "View Item", "See Price", "Open Shop".
  - Paid random items need PolicyService. [V]
- In-game Shop, https://create.roblox.com/docs/production/monetization/shop:
  - "By default, Shop appears in the in-game menu".
  - "Passes are always listed and can't be unlisted".
  - Listing controls whether a developer product appears.
  - Hide it with `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.ExperienceShop, false)`.
  - Global Shop button: "The button is disabled by default." [V]
- Developer products, https://create.roblox.com/docs/production/monetization/developer-products:
  - publish first;
  - Monetization ⟩ Developer Products;
  - icon ≤ 512×512 .jpg/.png/.bmp;
  - name, description, category;
  - price 1 to 1 billion Robux;
  - ⋯ ⟩ Copy Asset ID;
  - ProcessReceipt "can only be done once by one server-side script". [V]
- Passes, https://create.roblox.com/docs/production/monetization/passes:
  - Monetization ⟩ Passes ⟩ Create pass (icon, name, description, category);
  - ⋯ ⟩ Copy Asset ID;
  - **the page does not say where the price is set**. [V]
- OneEsports guide (third party, 2025-06-03), https://www.oneesports.gg/gaming/how-to-make-a-game-pass-on-roblox-guide/:
  - "Open the Sales tab and enable 'Item for Sale'", then "Hit Save Changes";
  - it names no price field. **[third party]**
- Apple HIG accessibility JSON,
  https://developer.apple.com/tutorials/data/design/human-interface-guidelines/accessibility.json: iOS text 17 pt
  default / 11 pt minimum; controls 44×44 pt default / 28×28 pt minimum. [V]
- Build a Phone Empire description, `https://games.roblox.com/v1/games?universeIds=10767582899`, fetched today (8,079
  playing, 2,061,640 visits): "✅ 28 goals with cash rewards", "✅ Plays on phone, tablet and PC". The goal card at the
  top left and the permanent "Store" tab come from video frames [R onboarding.md 3.1, menu.md].
- Added in revision 2 (opened today):
  - Roblox PlayerModule `TouchJump.lua` and `ControlModule.lua`, read from the third-party mirror of the client scripts
    (client version 0.742.0.7421053):
    https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/scripts/PlayerScripts/StarterPlayerScripts/PlayerModule.module/ControlModule/TouchJump.lua
    and `…/PlayerModule.module/ControlModule.lua`. Small screen (`min(axis) <= 500`): jump button 70 px at
    `UDim2.new(1, -(70*1.5-10), 1, -70-20)` inside `TouchGui.TouchControlFrame` (full size of the ScreenGui). With the
    newer ability controls (`FFlagUserAllowAbilityControls` and `AvatarAbilitiesInterface.isEnabled()`): 72 px at
    136 px from the right and bottom edges. `TouchGui` sets no `ScreenInsets`. **[third party mirror]**
  - ScreenGui reference, https://create.roblox.com/docs/reference/engine/classes/ScreenGui.md: "The default of
    CoreUISafeInsets keeps all descendant GuiObjects inside the core UI safe area". [V]
  - Assets, https://create.roblox.com/docs/projects/assets: the rbxthumb types are Asset, Avatar, AvatarBust,
    AvatarHeadShot, BadgeIcon, BundleThumbnail, FontFamily, GameIcon, GamePass (150×150), GameThumbnail, GroupIcon,
    Outfit. **DeveloperProduct is not one of them.** [V]
  - MarketplaceService reference, https://create.roblox.com/docs/reference/engine/classes/MarketplaceService.md:
    `GetProductInfoAsync` returns `PriceInRobux`, `IsForSale` ("Describes whether the asset is purchasable") and
    `IconImageAssetId` ("The asset ID of the product's icon, or 0 if there isn't one"); "not all information is
    provided or necessarily relevant for the kind of product you're querying". [V]
  - In-game Shop page re-opened: "By default, Shop appears in the in-game menu", "Passes are always listed and can't be
    unlisted", "The button is disabled by default." [V]
- From the notes [R]: DevForum tutorial threads ("not being able to skip it", side of the screen, not the middle), NN/g
  (no slideshows, 2 disclosure levels), the Roblox cross-platform doc (bottom corners belong to the thumbstick and jump
  button), and the Sydney study on spend prompts after a loss (shop.md 1.8).
- Roblox members checked in `tools/API-Dump.json` today [V]:
  - `AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName="", customFields=nil)` and
    `LogCustomEvent(player, eventName, value=1, customFields=nil)`;
  - `GuiObject.Active/Interactable/InputSink` (enum None/Activate/All), `GuiObject.Selectable`;
  - `GuiService.SelectedObject`, `TouchControlsEnabled`, `ReducedMotionEnabled` (ReadOnly, Hidden);
  - `UserInputService.PreferredInput` (KeyboardAndMouse/Gamepad/Touch/MicroGamepad), `LastInputTypeChanged`,
    `KeyboardEnabled`;
  - `Highlight.Adornee/DepthMode/FillTransparency/OutlineTransparency/OutlineColor`;
  - `Beam.Attachment0/Width0/Segments/CurveSize0/FaceCamera`;
  - `ContextActionService:BindActionAtPriority`;
  - `MarketplaceService.GetProductInfoAsync` (Yields), `PromptProductPurchase`, `PromptGamePassPurchase`,
    `UserOwnsGamePassAsync` (Yields), `PromptGamePassPurchaseFinished`, `ProcessReceipt` (Callback);
  - `RunService:IsStudio()`, `StarterGui:SetCoreGuiEnabled`, `Enum.CoreGuiType.ExperienceShop`;
  - `ScreenGui.ScreenInsets` (`CoreUISafeInsets`), `DisplayOrder`, `ResetOnSpawn`;
  - `Enum.KeyCode.ButtonL1/ButtonB`, `ProximityPrompt.ActionText`;
  - revision 2: `Beam.Attachment1/Width1/Transparency`, `ScreenGui.ClipToDeviceSafeArea`, `GuiService.SelectedObject`,
    and `Enum.ContextActionPriority` = Low / Medium / High (**there is no "Default" item**, so B6 uses Medium).

### 0.6 Revision 2: what the critic pass found and changed
Every item was checked against the code in `work/src`, the API dump or a source page opened today.
| # | Problem in revision 1 | Fix (section) |
|---|---|---|
| 1 | Step 2 ringed `BuyDataPlan`. That is the step-4 strip button and is **hidden on the Review**, where the first model opens. The plan is bought with `Primary` ("BUY DATA PLAN · $7,400", action "buy") [V DesignSteps `refresh`]. The ring would never show at the most important tap. | Both step 2 rings target `Primary` (A3, A9, T6). |
| 2 | The 290-pt limit came from memory. PlayerModule `TouchJump` + the default `CoreUISafeInsets` put the jump button at x 702–772, **y 279–349** on the 844×390 preset, so the column (282 / 286 pt) overlapped it. | Limit ≤ 271 pt (8 pt gap); paddings tightened; column now 265 / 267 pt (A2.1, T7). |
| 3 | The cleaner snippet called `math.floor(finite(t.step) or 0)`, but Template's `finite` returns a **boolean**: `math.floor(true)` throws inside `Template.migrate`. | Snippet fixed (A6). |
| 4 | "Restart first steps" lived in Team → Settings, which is **locked until the first launch**, while Restart is only shown before the first launch: never reachable in P2. | "Guide & tips" card lives in Home → Goals (P2) / Company → Settings (P1) (A12). |
| 5 | The mockup's cash path was impossible: $11K at first spawn needs the $1,000 daily grant, a manual claim in Company → Overview that steps 1–2 redirect away from; step 5 offered $5,500 although the $1,800 data reward was never collected; step 4 hid the claimable $2,500. | One consistent path with the real formulas (A3 "Cash on this path"; mockup). |
| 6 | Studio chips covered buttons (ReviewLines/BREAKDOWN). | No chip on Studio or Menu targets (0.4 #7, A9). |
| 7 | Gamepad: auto-selecting a HUD button in the world takes the thumbstick for UI navigation [A], so the player cannot walk; the `{Input}` "Press (A)" would make the character jump. | No auto-select in the world; L1 selects the guide action (A10). |
| 8 | Menu mapping gaps: `campus/access` and `campus/shops` unmapped; Team → Campus hidden until office ≥ 2 although its content works in the garage (card, guest cards, store upgrades that earn money, snacks); Lab → Research hidden until 50 RP / first hire although it now holds the API subscription, a research-point source; Company → Overview content (profit chart, market cycle, daily grant) and MarketApp's own metrics, serving capacity and "Intelligence leaderboard" had no new place; `empire/jet` does not exist (the jet goal opens `empire/settings`). | B5, B9 rewritten. |
| 9 | "Users and reputation are on Menu → Home and Company → Overview": false, neither shows reputation; the HUD rank line was not mentioned. | Users → Home strip; reputation and rank → Market (A2.2). |
| 10 | Shop icons used `rbxthumb://type=DeveloperProduct`, which is not a supported rbxthumb type. | `IconImageAssetId` from the same `GetProductInfoAsync` call; passes may use `type=GamePass&w=150&h=150` (C2). |
| 11 | Limo text "looks only, not faster" is false: top speed 78 vs 64 for the free Founder's Hatch (CampusConfig.CARS) when the player drives. Driver trips use fixed road speeds (DrivePlan.SPEED), so it changes nothing else. ShopConfig still calls it "Cosmetic". | New text and tag "Car + perk"; ShopConfig text fix (C3, C4). |
| 12 | Home card line "Your founder pitches there." is invented, not a `HUD.describe` text. | The card uses the HUD's progress text ("Trust 0 %") (B4). |
| 13 | Cash edge advised "Sell a GPU in Hardware", but the starter laptop cannot be sold (HardwareConfig `starter`); the case "plan costs more than the cash" (Primary reads "NEED TRAINING DATA · OPEN DATA") was missing. | Ordered cash-edge lines (A3). |
| 14 | SEE YOUR AI › called `LabApp.openReveal/openRelease` directly; `Studio.open` ignores calls while the Computer is closed. | Route `Computer.open("lab", "release")`, then `LabApp.openRelease(id)` like today's HUD (A3). |
| 15 | No real-time budget for the "≤ 3 min" goal. | A3.1 budget. |
| 16 | "START is always affordable" ignored garage upkeep ($300 per game day = $15/min [V CompanyOps.STAGES]). | Wording (A3). |
| 17 | B7 missed text anchors: PhoneMath "Open Company → Office", AssistantService "(Company → Settings)" and "hire in Company → Team", StudioApp's second "Noah Studio" (brand label). | B7. |
| 18 | Shop PNGs showed Robux prices that cannot exist while every id is 0; the hand-off PNG showed the HUD Shop button that is hidden while every id is 0. | On-image notes (section 8). |
| 19 | P1 ring on the sidebar "Models" had no name to find (the nav buttons are unnamed). | Name them `Nav_<appId>` (A3, files list). |
| 20 | Replication budget not re-checked for the new field. | T2 runs `tests/econ/test_net.luau` (CORE_SPEC 11.8). |
| 21 | Tap counts hid cases: launch is 4 taps when the reveal has not played; a later model is 4 when its suggestion has a data plan; the office move is 4 when Home's 3 card slots are taken. | B10 notes. |

---------------------------------------------------------------------------------------------------------------------
## A. TUTORIAL "First steps"

### A1. Rules
- **Learn by doing:** one real button, ringed. No slideshow and no "Next ›" pages.
- **Placement:** one place (the HUD goal card), at the side of the screen. Never in the middle and never in the bottom
  corners.
- **Text:** one short line per step, at most 2 lines on the phone.
- **Skip and resume:** skippable at any moment and resumed from state. It never blocks input, time or a button.
- **Hints:** a hint stays until its step is done. A delayed ring appears only for players who need it and never comes
  back.
- **Moment of joy:** the reveal, NOW LIVE (both from the Studio) and the "First income!" burst.
- **Scope:** only the core loop (data → train → launch → income). Everything else comes later as one-time tips (A12).

### A2. Where it lives
#### A2.1 World (Computer closed): the HUD goal card in guide mode
The HUD column keeps its geometry: 300 design px wide, 16 px from the right, scale 0.432 × 1.5 = **0.648 pt per px on
the phone** and 0.919 on 1280×720 [V HUD.module.luau `WIDTH`, `COMPACT_BOOST`, `TOUCH_BUTTON`]. Sizes below are design
px, with phone pt in brackets.

| Part | Normal mode (today) | Guide mode |
|---|---|---|
| Caption row (26) | "Next goal" | "FIRST STEPS · n/5" (19 px bold accent, letter spacing 0.07 em [12.3 pt]) and, on the right, a "Skip" text button (20 px muted, underlined [13 pt]) whose invisible hit box is ≥ 68×68 px (44 pt). The hit box may spill outside the card but must not cover the action row. |
| Segment bar (8) | – | 5 segments, gap 6: done = accent, current = accent at 28 % with a fill (35 % static; step 3: training progress; step 5: 100 %), future = white at 10 %. |
| Title (32) | goal text | step title (27 px bold [17.5 pt], 1 line) |
| Line (2 × 24) | hint (hidden on phones) | assistant line, **shown on phones too**: "**{A}:** …" (19 px [12.3 pt]; `{A}` in accent bold; at most 2 lines) |
| Row (70 [45 pt]) | [Collect reward] [Open company] | left: **[Collect $X]** only while quests are claimable (secondary); right: the step's action (primary, or the gold style for DECIDE). With no claim, the action button is full width. With no action (step 3 wait), [Collect $X] and [WATCH ›] are both secondary. |

Card height (revision 2) 10 + 26 + 4 + 8 + 6 + 32 + 4 + 48 + 10 + 2 (border) = **150 px (97 pt)**. Column on the
phone: 80 (compact panel, A2.2) + 6 + 150 + 6 + 70 = 312 px = 202 pt, starting 5 pt under the safe top (58 pt), so it
**ends at 265 pt** (guide) and **267 pt** (hand-off card), measured in the mockup [V]. The gaps between panel, card
and row are 6 px.

- **Binding check:** the column bottom must stay **≤ 271 pt** on 844×390, 8 pt above the jump button.
  - Jump button, derived [V source 0.5, A device insets]: `TouchGui` keeps the default `ScreenInsets =
    CoreUISafeInsets`, so its `TouchControlFrame` is the safe area (47, 58)–(797, 369), 750 × 311 pt. That is a small
    screen (311 ≤ 500), so the button is 70 pt at (1, −95, 1, −90): **x 702–772, y 279–349**. The HUD column spans
    x ≈ 596–790, so it overlaps horizontally and only the vertical gap protects it.
  - The newer ability-control variant (72 pt at 136 pt from the edges) would sit at x 661–733, **y 233–305**. No column
    of this layout clears that. T13 must check which variant runs on a phone. If it is the ability variant, the row
    moves into the panel line (P1 follow-up) [A].
- **Desktop:** the full panel stays, the column ends at 428 px of 720 [V mockup], and lines may take 3 lines.

#### A2.2 Phone HUD panel, compact form (guide mode and normal mode, phones only; decision L1)
- **Size:** 300 × 80 px (padding 10 / 16, border included).
- **Content:** logo 52×52, then a column with the company name (22 px bold, truncated) and a second line. The second
  line is the cash (28 px bold, the HUD's money format, e.g. "$11.2K") plus "+$X/day" (19 px; good colour when > 0,
  muted "+$0/day" when 0). Fix round 1: while the guide runs and there is no income yet, the garage upkeep reads
  "-$300/day upkeep" in the muted colour (Home's live strip: caption "NET · UPKEEP", muted), so the first screen does
  not read as "losing".
- **Moved:** users, reputation and the rank line leave the phone HUD.
  - Users: Menu → Home live strip (P2); in P1 the Market app ("Users" metric) [V MarketApp].
  - Reputation and rank: Market → My AIs header metrics ("Reputation", "Rank") [V MarketApp]; in P1 the Market app.
  - Company → Overview does **not** show reputation [V EmpireApp `overview`], so it is not named as a place.
- **Desktop:** keeps today's panel.
- **Tests:** tests/apps read `NetPerDay`; the compact form keeps that name (B12 contract).

#### A2.3 Computer open
- The HUD column is hidden, as today (`Computer.isOpen()` → HUD hides) [V design A2], so the card never covers the
  Studio.
- In the Studio the guidance is the ring (plus the chip during the first-contact dim) and the Studio's own hint
  ("FIRST MODEL · buy the data plan, then press START." / "… a good starter is ready. Just press START.",
  DesignSteps.module.luau, search "FIRST MODEL") [V].

#### A2.4 Ring layer
- New ScreenGui **`AIEmpire_Guide`**, DisplayOrder **22**:
  - above HUD (10), Dim (19) and Overlay (20);
  - below Intro (25), Phone (28) and Top (30) (UIRoot) [V].
- Settings: `ScreenInsets = CoreUISafeInsets`, `ResetOnSpawn = false`, no UIScale on the root (it works in the screen
  units of `AbsolutePosition`).
- It is created by `Guide.mount` from `Main.client.luau` after `UIRoot.init`.

### A3. Steps, exact texts and what is ringed
`{A}` = the first name of `AssistantService.identity(userId)` (same formula in `TutorialMath.assistantName`).
`{Name}` = `Player.DisplayName`, left out when it is longer than 12 characters ("{A}: Hi! Let's build your first AI.").
`{Model}` = the model's display name as the Studio shows it (e.g. "Nova v1"). `{Input}` = "Tap" (Touch), "Click"
(KeyboardAndMouse) or "Press L1, then (A)," (Gamepad; A10: in the world (A) alone would jump), from
`UserInputService.PreferredInput`, re-read on `LastInputTypeChanged`. Fix round 1: in step 1 the gamepad wording is
"Press L1" without "then (A)": in steps 1–2 L1 alone opens the lab (the guide's open filter, A8), and a following (A)
would press the Studio's selected BUY DATA PLAN straight away (cash the player did not knowingly choose to spend).

| Step · sub | When (first match, A5) | Card title | Card line | Row (left · right) | Ringed element (abstract id → GuiObject) | Dim | Ring delay | Chip |
|---|---|---|---|---|---|---|---|---|
| 1 openLab | default | **Open your AI lab** | first 8 s or until the first input: "{A}: Hi {Name}! Let's build your first AI." Then Touch: "{A}: Tap OPEN LAB or walk to the glowing computer." · PC: "{A}: Click OPEN LAB or press C." · Gamepad: "{A}: Press L1 or walk to the glowing computer." (fix round 1) | [Collect $X] · **OPEN LAB ›** | `guide_action` = the HUD row's action button. Computer open: `menu_lab` (P1: sidebar button `Nav_lab` (new name, A9), then the Lab home tile `DesignNewModel` [V LabApp]; P2: the Home guide card button) | yes (hole = card + row) | 0 s | "{Input} to open the lab" (gamepad: "Press L1 to open the lab", fix round 1), left of the HUD column |
| 2 buyData | Studio design open with data < `ModelConfig.TRAINING.minTokens` (1e8) [V], **or** saved step ≥ 2 and no training and nothing trained | **Get training data** | "{A}: I picked a good first model. It needs data." | [Collect $X] · **OPEN LAB ›** | Studio: **`Primary`**, which reads "BUY DATA PLAN · $7,400" on the Review (action "buy") [V DesignSteps `refresh`]. Not `BuyDataPlan`: that is the step-4 strip button, hidden on the Review. World: `guide_action` | yes, at first contact with `Primary` | 0 s | none (Studio target) |
| 2 start | same, data ≥ 1e8 | **Start training** | "{A}: Data is in. Now press START." | [Collect $X] · **OPEN LAB ›** | Studio: `Primary` ("START TRAINING · $1,280") [V]; world: `guide_action` | yes, at first contact with `Primary` after its label changed | 0 s | none (Studio target) |
| 2 cash edge | as above, but `Primary` reads `NEED $X` (disabled, training unaffordable) or "NEED TRAINING DATA · OPEN DATA" (the plan costs more than the cash; it opens Datasets) [V DesignSteps] | (same title) | first match: claimable quests → "{A}: Not enough cash. Collect your rewards first." · daily grant claimable → "{A}: Not enough cash. Claim today's grant in Company." (P2: "on Home") · plan too expensive → "{A}: The plan costs too much. Datasets has free data." (SCRAPE: 80M tokens every 30 s, so two scrapes pass the 100M minimum [V DataConfig]) · owns a non-starter GPU → "{A}: Not enough cash. Sell a GPU in Hardware for half back." (`SELL_REFUND = 0.5`; the starter laptop cannot be sold [V HardwareConfig]) · else → "{A}: Not enough cash. Your next daily grant comes at 00:00 UTC." | [Collect $X] · OPEN LAB › | as above (`Primary`) | – | – | – |
| 3 wait | `data.training ~= nil`, no pending event | **Your AI is training** | "{A}: About {eta} left. You can close the lab." `{eta}` = `StateController.trainingEta()` as "1 min 12 s" / "40 s"; paused: "{A}: Training is paused." | [Collect $X] · [WATCH ›] (opens the Studio training stage) | none | – | – | – |
| 3 decide | `training.event.pending` | **Quick choice needed** | "{A}: Pick one in the lab. If you wait, it picks for you." | **DECIDE ›** (gold style; Collect is hidden here, one urgent button) | world: `guide_action`; Studio: `Decision` [V Stages] | no | 6 s (the server auto-picks after 25 s, LAB_SPEC 2.5) | world: "{Input} to decide"; Studio: none |
| 4 open | a model with `status == "trained"`, Studio not in reveal/launch | **Launch your AI** | "{A}: {Model} is ready! Let's see how it did." | [Collect $X] · **SEE YOUR AI ›** → `Computer.open("lab", "release")`, then `LabApp.openRelease(id)` (today's HUD order). `LabApp.onShow` plays the reveal of a model trained in this session; after a rejoin the model counts as revealed and Launch Day opens [V LabApp, LabState]. Calling `LabApp.openReveal` alone does nothing while the Computer is closed (`Studio.open` checks `hostReady`) [V Studio] | `guide_action` | no | 0 s | "{Input} to see it" |
| 4 reveal | `Studio.mode == "reveal"` | (card hidden) | – | – | `Launch` (LAUNCH ›) [V Stages] | no | reveal sequence end + 3 s (the sequence is 0.18 + 0.2 + 1.15 + 8 × 0.12 ≈ 2.5 s; during it a full-size `SkipCeremony` button catches taps [V Stages]) | none |
| 4 launch | `Studio.mode == "launch"` | (card hidden) | – | – | `LaunchButton` [V LaunchDay] | yes, first contact | 0 s | none (Studio target) |
| 5 waitIncome | `stats.modelsReleased >= 1`, no revenue yet | **Your AI is live** | "{A}: Users are trying {Model} now." | [Collect $X] · **GOT IT** | none | – | – | – |
| 5 income | `live.revenue > 0` or `stats.totalRevenue > 0` | **First income!** | "{A}: People pay to use {Model}. Well done!" | [Collect $X] · **GOT IT** | none | – | – | – |
| done | after op `done` | caption "GUIDE COMPLETE ✓" (good colour) for 5 s over the normal goal | normal: "Sign your first client (CloudDesk)", progress "Trust 0 %" [V tests/apps strings] | normal | – | – | – | – |

- **Studio target names** are looked up by name under the frame `ModelStudio` (Studio.module.luau `root.Name =
  "ModelStudio"`) [V]: `Primary`, `Decision`, `Launch`, `LaunchButton` [V]. The Lab home also has a button named
  `Launch` (a ready-model row, LabApp) [V], so the search must stay under `ModelStudio`.
  - Step 2 rings `Primary` on every design step. On steps 1–5 it reads "CONTINUE ›" and leads to the Review; the ring
    counts as used only when the sub-step changes (buyData → start → training), not on a CONTINUE tap.
- **The Studio modes** are "design", "training", "reveal", "live" and "launch" (LabApp `Studio.register`) [V]. The
  decision card is inside "training".
- **Taps from spawn to a live AI:** OPEN LAB · BUY DATA PLAN · START · LAUNCH › · LAUNCH = **5** while the Computer
  stays open. The reveal starts by itself: TRAINING_COMPLETE while the Studio shows "training" calls
  `navigation.show("lab")`, and `LabApp.onShow` opens the reveal [V LabApp]. BUY DATA PLAN and START are both taps on
  `Primary` [V]. When the player closes the Computer during training, SEE YOUR AI › adds a 6th tap. A decision and the
  collects are optional extras.
- **Cash on this path** [V formulas]:
  - The $1,000 daily grant is a manual claim in Company → Overview (EmpireApp "Claim daily grant", remote
    `ClaimDaily`) [V]. A fresh player in steps 1–2 is redirected away from Company, so the path does not count it.
    (LAB_SPEC 4.9 and CORE_SPEC 1.2 start at $11,000 / $12,200 because their bot claims it.)
  - A save that collects nothing: $10,000 (GameConfig.START_MONEY) − $7,400 − $1,280 = $1,320, so START is affordable
    unless the player spent cash elsewhere first, or idled about 1.5 h (garage upkeep $300 per game day = $15/min
    [V CompanyOps.STAGES, DAY = 1200 s]). Auto-HR hires nothing before a model is live [V EmpireService `autoHire`].
  - The mockup's path: the player taps every Collect the card offers. $10,000 → Collect $1,200 (founder) → $11,200 →
    plan → $3,800 → START → $2,520 → in step 3 Collect $1,800 (data: 1B tokens, the plan gives 4B) → $4,320 → in
    step 4 Collect $2,500 (first run) → $6,820.
  - Launch Day pre-selects `PricingMath.recommendedMarketing(6820, 0)` = min(5000, floor((6820 − 1500)/500)·500) =
    **$5,000** (reserve max(1500, wage·120); cap `ModelConfig.PRICING.marketingMax = 5000`) [V]. The button reads
    "LAUNCH CHAT · $5K MARKETING" (LaunchDay label rule, `Format.money`) [V], and $1,820 is left.
  - Step 5 then offers Collect $3,000 (launch) → $4,820. A player who collects nothing launches with $1,320 and the
    Recommended campaign is $0 (no marketing).
- **GOT IT** sends op `done`. It also fires by itself 120 s after the first income.

#### A3.1 Real-time budget of the quick path (phone, Computer kept open)
| Part | Seconds | Basis |
|---|---|---|
| Intro: read, START | ~10 | estimate [A] |
| Spawn: greeting, OPEN LAB | ~8 | estimate [A]; the greeting yields to the first input |
| Review: read, BUY DATA PLAN, wait for the data | ~10 + ≤ 3 | estimate [A]; `BuyData` calls, then "BUYING DATA…" until the snapshot, at most 3 s [V DesignSteps] |
| START | ~3 | estimate [A] |
| Training of the first model | 80 | "TIME 1:20" on the Review [V lab render]; CORE_SPEC 1.2 bot: 0:00–1:18 |
| Training decision (about 3 in 10 runs) | 0–25 | the run pauses; the server picks after 25 s (LAB_SPEC 2.5) [V Review text "3 in 10 runs pause for a decision"] |
| Reveal sequence, LAUNCH › | ~2.5 + ~5 | sequence [V Stages]; reading [A] |
| Launch Day: read, LAUNCH | ~10 | estimate [A] |
| **Total** | **≈ 130 s (2 min 10 s); ≤ 160 s (2 min 40 s) with a decision** | under the 3-minute target; human times must be measured in a playtest |

### A4. Celebration and the assistant's voice
- **Celebration** (step 5 income, once): ≤ 24 small Frames (5×9 px, theme colours) burst from the cash label towards
  the left and up. Fix round 1: it plays (and the 120 s auto-`done` timer starts) only once the Menu is closed, i.e.
  when the HUD card is on screen; on the 5-tap path the first revenue usually arrives while NOW LIVE still shows. They stay outside the HUD column, so no text is covered, and are destroyed after 1.5 s. With
  `GuiService.ReducedMotionEnabled` the cash label only flashes in the good colour [V member]. The reveal confetti and
  NOW LIVE belong to the Studio (LAB_SPEC 4.11/4.13).
- **AssistantService:** while `TutorialMath.active(data)`, `proactive()` skips the greeting toast ("Good morning, …")
  [V function]. The training-decision reminder stays. The NPC is never forced to walk to the player.

### A5. `TutorialMath` (new, pure, shared: `ReplicatedStorage/Shared/TutorialMath.module.luau`)
```
TutorialMath.STEPS = 5
TutorialMath.active(data) -> boolean        -- company exists and not tutorial.done and not tutorial.skipped
TutorialMath.reachable(data) -> number      -- highest step state proves: 5 released, 4 trained, 3 training, else 1
TutorialMath.step(data, live, ui) -> View?  -- ui = {computerOpen, studioOpen, studioMode, revealed = fn(id)->bool,
                                            --       inputKind = "touch"|"pc"|"pad", greetingOver = bool}
-- View = {step = 1..5, sub = string, title, line, action = {label, route}?, collect = number?, target = abstract id?,
--         dim = bool, delay = seconds, chip = string?, frac = number?}
TutorialMath.SEEN_KEYS, TutorialMath.TIP_KEYS, TutorialMath.unlockedKeys(data) (B5), TutorialMath.assistantName(userId)
```
Rules, first match wins:
1. `not active` → nil, and the HUD shows the normal goal.
2. `stats.modelsReleased >= 1` → step 5.
3. any model has `status == "trained"` → step 4.
4. `data.training ~= nil` → step 3.
5. `ui.studioMode == "design"` **or** `tutorial.step >= 2` → step 2.
6. otherwise → step 1.

`collect` is the sum of the rewards of every quest with `progress ≥ target` and not yet claimed (the HUD's existing
claim test); nil when 0. `Format.int` gives "$1,200". The texts live in `TutorialMath.TEXTS` (English) so tests can
check them.

### A6. Save field and migration (pure addition, **no DATA_VERSION bump**; DATA_VERSION stays 6)
```
empire.tutorial = { v = 1, step = 0, done = false, skipped = false, tipsOff = false, seen = {}, tips = {} }
```
- **Default:**
  - add the table to `EmpireMath.new()` (EmpireMath.module.luau `function Math.new()`) [V];
  - new saves get it through `Template.new()`;
  - old saves get it through the nested-defaults loop in `Template.migrate` (`for key, value in EmpireMath.new()`) [V];
  - this is the same pattern as `prefs` [V comment].
- **Cleaner:** new `Template.cleanTutorial(raw)`, called in `Template.migrate` right after `Template.cleanCompany(raw)`
  [V call site]. It must be idempotent:
  ```
  local e = raw.empire
  local t = if typeof(e.tutorial) == "table" then e.tutorial else {}
  -- Template's local `finite(v)` returns a BOOLEAN (Template.module.luau, "local function finite"), not the number
  local step = if finite(t.step) then math.clamp(math.floor(t.step), 0, TutorialMath.STEPS) else 0
  local out = { v = 1, step = step,
    done = t.done == true, skipped = t.skipped == true, tipsOff = t.tipsOff == true, seen = {}, tips = {} }
  for k, v in (if typeof(t.seen) == "table" then t.seen else {}) do
    if v == true and table.find(TutorialMath.SEEN_KEYS, k) then out.seen[k] = true end end
  for k, v in (if typeof(t.tips) == "table" then t.tips else {}) do
    if v == true and table.find(TutorialMath.TIP_KEYS, k) then out.tips[k] = true end end
  -- old saves that already launched a model never see the guide and get no NEW-badge flood
  if out.step == 0 and not out.done and not out.skipped and (tonumber(raw.stats and raw.stats.modelsReleased) or 0) > 0 then
    out.done = true
    for _, key in TutorialMath.unlockedKeys(raw) do out.seen[key] = true end
  end
  e.tutorial = out
  ```
- **Other old saves:** a save with trained but unreleased models resumes at step 4. A save with nothing resumes at
  step 1, or at step 3 while training runs, because `data.training` is saved.
- **Replication:** no network change. StatePatch diffs the whole data tree [V design A3]. The full table is at most
  14 seen keys + 6 tip keys + 5 scalars (well under 0.5 KB [arithmetic]); CORE_SPEC 11.8 keeps "the rest < 0.5 KB",
  so T2 re-runs the replication budget test `tests/econ/test_net.luau`.
- **Types:** `Types.PlayerData.empire` is typed `any` [V Types.module.luau], so no type change is needed.
- **Writes:** server only, through **EmpireAction `{action = "tutorial", op = …}`**. Add a branch in `empireAction`
  (EmpireService.module.luau) [V]. It is already rate limited to burst 4 / 2 per s [V].

| op | payload | allowed when | effect |
|---|---|---|---|
| `skip` | – | not done | `skipped = true`; `Funnel.custom(player, "TutorialSkipped", step)` |
| `done` | – | `stats.modelsReleased >= 1`, else `NOT_READY` | `done = true`; funnel step 8 |
| `restart` | – | `stats.modelsReleased == 0`, else `NOT_AVAILABLE` | `skipped = false; done = false; step = 0` |
| `step` | `n` integer 1..6 | not done/skipped; `n <= TutorialMath.reachable(data) + 1`, else `BAD_INPUT` | `step = max(step, min(n, 5))`; funnel step for a new maximum (A11) |
| `seen` | `keys` (≤ 8 strings) | every key in SEEN_KEYS, else `BAD_INPUT` | `seen[key] = true` |
| `tip` | `key` | key in TIP_KEYS | `tips[key] = true` |
| `tips` | `on` boolean | – | `tipsOff = not on` |
| `replayTips` | – | – | `tips = {}` |

Every op calls `SessionService.markDirty`. No op changes money, items or unlocks. A forged `step` can only distort
analytics.

### A7. Intro (Screens/Intro.module.luau): name + START
- **One screen:**
  - title "AI Empire" (72 px);
  - the line "You start in a garage with $10,000. Build the biggest AI company." (26 px muted);
  - caption "COMPANY NAME";
  - a name box 84 px tall, **prefilled** with a random entry of the new `CompanyConfig.COMPANY_NAME_IDEAS`. The entries
    are fictional: "Nimbus Labs", "Bright Circuit", "Polar Minds", "Quiet Spark AI", "Little Robot Co", "Moonbeam AI",
    "Pixel Brain", "Kite Labs" [A: owner may edit, O3]. The player may type over the name, and it still passes the
    server's CreateCompany filter;
  - a dice button 84×84 that rolls another name;
  - **START** 320×84;
  - the link "Customize (optional) ›";
  - the note "Logo, colour and specialization are picked for you. Customize changes them now." (20 px dim).
- **Customize** opens today's logo, colour and specialization controls on the same screen. The defaults are `LOGOS[1]`,
  `COLORS[1]` and spec `general` ("Balanced. +2 on every core stat.") [V]. The spec card adds "Stays for the whole
  game.", which is true because no remote changes them later [V Net: only CreateCompany].
- **Scale:** the Intro root gets its own UIScale with the Studio formula `s = clamp(min(A.X/1254, A.Y/520), 0.5, 1.25)`
  (LAB_SPEC 3.2). On the iPhone that is 0.598 pt per px, so text ≥ 20 px (12 pt).
- **Taps:** 1 (START). "Welcome back · CONTINUE" stays as it is.

### A8. World pointer (step 1 only)
- **Target:** the player's own `FounderTerminal`. It is found as the ProximityPrompt with attribute
  `CampusAction == "ownerComputer"` inside the player's `Office`. Its ObjectText is "Founder computer · whole company"
  and its ActionText is "Open" (RoomKitsGarage / RoomKitsWork + ArchKit `Kit.action`) [V].
- **Client-only objects, made by GuideController.** They are destroyed when step 1 ends, on Skip, or when the Computer
  opens:
  - one `Highlight` on the terminal: `DepthMode = AlwaysOnTop`, `FillTransparency = 1`, `OutlineTransparency = 0`,
    `OutlineColor = C.warn`. Destroy it, never just disable it, because a disabled Highlight still takes one of 255
    slots [R onboarding.md 2.7];
  - one `Beam` from an Attachment in the local HumanoidRootPart to an Attachment on the terminal: `FaceCamera`,
    `Width0 = Width1 = 0.4`, `Segments = 12`, `CurveSize0 = 3`, gold, transparency 0.3 → 0.8. It shows only while the
    player is > 10 studs away. **No Texture id** is set. If an untextured Beam is too faint in Studio, drop it [A];
  - one BillboardGui "● Founder computer · opens the Lab" (dark pill, gold dot).
- **Redirects during steps 1–2** (client side): the `OWNER_COMPUTER` prompt (WorldController, kind "OWNER_COMPUTER") [V],
  the C key (HUD) and the HUD "Open company"/"Menu" button all open `Computer.open("lab", "design")`. After step 2 they
  behave as usual.
  - Not a trap: the Studio's "‹ LAB" (`Studio.close`) returns to the Lab home inside the Computer, whose sidebar
    (P1) / rail (P2) reaches every app; "×" closes the Computer [V Studio]. The redirect ends at once on Skip.
- **JourneyController:** shows nothing while `TutorialMath.active` (today it marks the data desk, the wrong place) [V].
  It is removed in P2.

### A9. Ring, dim and chip (`UI/Screens/Guide.module.luau`)
- **Ring:**
  - a Frame + UICorner 14 + UIStroke 3 px `C.warn`, with a soft glow;
  - rect = target AbsolutePosition/Size relative to the guide root, padded 6 px on every side [A: alignment across the
    two ScreenGuis, check at 844×390 and 1280×720];
  - re-placed on RenderStepped while visible;
  - pulse: TweenInfo(0.8 s, Sine, InOut, −1, true) on stroke transparency 0 ↔ 0.55 and pad 6 ↔ 12; static with
    ReducedMotion. Fix round 1: computed per frame from os.clock only while the ring shows (no tween runs for the
    whole session);
  - fix round 1: the ring rect stays inside the guide root (the safe area); on a side where another button is closer
    than pad + stroke, the pad shrinks to the gap, and the glow is hidden where it would spill onto a neighbour or past
    the safe area (the ring never covers a neighbouring button);
  - hidden while the target is invisible, has no size, or is clipped by its ScrollingFrame.
  - Target resolution: HUD → `NextGoal` row buttons; Studio → by name under `ModelStudio` (A3); P1 Computer → the
    sidebar button, which gets the new name `Nav_<appId>` in `Computer.buildNavButton` (today the nav TextButtons have
    no name [V Computer.module.luau]), and the Lab home tile `DesignNewModel` [V].
- **Dim:**
  - 4 black Frames at 0.52 transparency around a hole;
  - hole = the ring rect, or for HUD targets the union of the guide card and the row;
  - only at the first contact with a target (steps 1, 2 buyData, 2 start, 4 launch);
  - timing: in 0.2 s, hold 2.5 s, out 0.4 s; any `InputBegan` ends it early.
- **Chip** (world steps only):
  - a TextLabel, 13 pt bold, dark fill, 2 px gold stroke, with an arrow glyph pointing at the ring;
  - HUD targets: left of the HUD column, vertically centred on the ring;
  - Studio and Menu targets: **no chip** (revision 2; every spot near those buttons is another button);
  - never over the target or any other GuiButton (T8 checks it; the mockup's `sizes.js` reports `chipOverButton`).
- **Never blocks input:**
  - every guide object has `Active = false` and `InputSink = Enum.InputSink.None` [V members; A: check in Studio that
    taps reach the button];
  - nothing in the layer is a GuiButton.
- **A used ring never comes back:** after its target is pressed or its step is left. The delays (6 s decision,
  reveal + 3 s, dim 2.5 s, greeting 8 s) are starting values to tune in playtests [A].

### A10. Phone, PC, gamepad
- **Phone:**
  - card ≥ 12.3 pt and buttons 45 pt;
  - the bottom corners stay free; the HUD column ends ≤ 271 pt (A2.1);
  - in the Studio the thumbstick and jump button are already off (`GuiService.TouchControlsEnabled = false` while
    open [V Studio `bindInput`]).
- **PC:** chip "Click …"; Return = the Studio primary (LAB_SPEC 3.5); the step 1 line mentions C.
- **Gamepad:**
  - **World steps: no automatic selection.** A selected HUD button takes the thumbstick for UI navigation, so the
    player could not walk to the founder computer [A: from memory, check in Studio, T13], and (A) alone would jump.
  - **L1 = "go to the guide"**: while the guide card shows an action and the Computer is closed, ButtonL1
    (`ContextActionService:BindActionAtPriority`, `Enum.ContextActionPriority.Medium.Value`, no touch button) sets
    `GuiService.SelectedObject` to the guide action; (A) presses it; ButtonB clears the selection. In P2 the same key
    opens the Menu, whose Home shows the same guide card first (B6), so "L1, then (A)" stays true in both phases.
    The Studio's High-priority L1/R1/B binding wins while it is open [V Studio]. [A: check that no core binding uses L1]
  - Chip: "Press L1, then (A), to open the lab". Step 1 also offers the world route (the founder computer prompt).
  - Studio targets: the Studio already selects `Primary` / `Launch` / `LaunchButton` (`view.focus()`) [V Studio,
    DesignSteps, Stages]; the guide sets nothing there.
  - The guide row buttons and Skip are `Selectable = true`.

### A11. Funnel analytics (`ServerScriptService/Server/Lib/Funnel.module.luau`, new)
- `Funnel.step(player, n, name)`:
  - per-session memo;
  - `pcall(AnalyticsService.LogOnboardingFunnelStepEvent, AnalyticsService, player, n, name)`;
  - no-op when `RunService:IsStudio()`.
- `Funnel.custom(player, name, value)` → `LogCustomEvent`.

| n | name | where |
|---|---|---|
| 1 | Joined | SessionService: session loaded with `data.company == nil` |
| 2 | Company created | CompanyService CreateCompany ok |
| 3 | Lab opened | EmpireAction tutorial `step` n = 2 |
| 4 | Training started | `step` n = 3 |
| 5 | Model trained | `step` n = 4 |
| 6 | Model launched | `step` n = 5 |
| 7 | First income | `step` n = 6 (sent once by the client when step 5 `income` first shows) |
| 8 | Guide finished | op `done` |

**Skip is not a funnel step.** Skipped steps make the earlier ones count as complete [V doc], so a skip goes to
`LogCustomEvent(player, "TutorialSkipped", step)`.

### A12. Skip, resume, restart, hand-off, tips
- **Skip:**
  - the card's "Skip" in every world step (1, 2 outside the Studio, 3, 4 open, 5), plus "Skip guide" in the
    "Guide & tips" card;
  - in the Studio steps (2, 4 reveal, 4 launch) the guide is only a ring and a 2.5 s dim that any input ends; nothing
    there needs skipping, and "‹ LAB", "LATER" or "×" always leave [V Studio, Stages];
  - op `skip`, and the card turns into the normal goal at once;
  - nothing else changes, and tips stay on.
- **"Guide & tips" card** (Skip guide, Restart first steps, Tips on/off, Replay tips):
  - P1: Company → Settings (always visible today);
  - P2: **Home → Goals**, not Team → Settings. Team is locked until the first launch (B5), and Restart only shows
    while `modelsReleased == 0`, so in Team it could never be reached.
- **Restart:** "Guide & tips" → "Restart first steps", shown only while `modelsReleased == 0`.
- **Hand-off:**
  - after `done`, `HUD.describe` takes over with the caption "GUIDE COMPLETE ✓" for 5 s;
  - in P2, one toast: "New in your Menu: Market, Clients, Team";
  - in P2, the HUD Shop button appears (B11).
- **Tips:** one-time, state-triggered, shown as a "TIP" line in the same card for 10 s or until tapped. An optional
  "SHOW ME" button deep-links and rings the target.
  - limits: at most 1 per 90 s; none in the first 60 s after the guide; none while a decision is pending or the
    Computer is open; none when `tipsOff`;
  - each key is saved with op `tip`.

| key | trigger | line | SHOW ME |
|---|---|---|---|
| `team` | Σ `empire.employees` ≥ 1 | "HR hires people by itself. Team shows them." | Team → Staff (P1: Company → Team) |
| `phone` | first unread phone item (PhoneController badge > 0) | "New message on your company phone." | ring on the phone button |
| `clients` | a CloudDesk trip runs (`live.ops.trips`) | "You drive to CloudDesk. A signed client pays every day." | Clients |
| `gpus` | serving ≥ 85 % full or a waitlist (LaunchDay rule) | "Servers almost full: more GPUs serve more users." | Lab → GPUs |
| `successor` | a live model, and VRAM and data allow a bigger size | "Train v2: a bigger brain takes over v1's users." | Lab → Models |
| `design_steps` | second Studio design open | "Chips 1–5 let you design every part yourself." | – |
| ~~shop~~ | **never** | | |

### A13. Why there is no reward, and why the guide cannot block the economy
- **Reward:** an extra $X would move the casual garage exit by X / 2,662 min (net $/min at minute 5, CORE_SPEC 9.1)
  [V design A13]. That is small, but it pays players for not skipping, which is pressure, and it breaks CORE_SPEC 1.2's
  money column. **No new money or items.**
- **The server never reads the guide flags for gameplay.** Training, auto-HR, trips, auto price, decisions (25 s
  auto-pick) and quests are unchanged.
- **Every step has another route** (Datasets app, world prompt, Menu). Steps come from state, so a Robux cash pack or an
  odd order cannot get anyone stuck.

---------------------------------------------------------------------------------------------------------------------
## B. MENU

### B1. Today's problems (from the research, rechecked in renders)
- About 29 navigation targets on one screen (9 apps + 7 journey chips + 9 Company tabs + shortcuts) [R menu.md 2].
- On iPhone, Company, Market, Datasets and Hardware text is 4.8–10 pt (UIRoot 0.432) [R menu.md 3; V render
  `prev/phone_fresh_empire.png`].
- One place has many names, and key actions are buried (Hire ≈ 6 swipes with 32 staff) [R menu.md 4].
- "Open company" reopens the last app [V HUD], and no gamepad button opens the Computer [R].

### B2. Structure: 6 entries, at most 5 sub-tabs, 2 levels
| Entry (icon) | Page line (22 px muted) | Sub-tabs (default first) |
|---|---|---|
| **Home** (2×2 tiles) | "What to do next" | Today · Money · Goals |
| **Lab** (neuron) | "Build and train your AIs" | Models · Data · GPUs · Research · Test arena |
| **Market** (price tag) | "Your AIs, prices and users" | My AIs · Lines · Projects · Leaderboard |
| **Clients** (briefcase, wider than tall) | "Business deals that pay every day" | Clients · Receipts |
| **Team** (two people) | "Staff, office and cars" | Staff · Office · Fleet · Campus · Settings |
| **Shop** (bag, gold `C.warn`) | "Optional extras for Robux. You can reach every office and every client without them." | – |

Labels always show under the icons. The 7-chip journey bar is removed in P2. Its job moves to the Home cards, the HUD
goal and the guide.

### B3. Shell and sizes (Screens/Computer.module.luau rebuilt; root frame name "Computer" kept)
- **Scale:**
  - the shell gets its own UIScale with the Studio formula (LAB_SPEC 3.2);
  - phone: s = 0.598, canvas **1254 × 520**;
  - 1280×720: s = 1.021, canvas **1254 × 648** (fills the screen under the top bar);
  - same tokens everywhere (LAB_SPEC 3.4): text floor 20 px (12 pt on the phone), body 22, titles 28–34, every target
    ≥ 74 × 74 px (44 pt).

| Region | design px (phone) | Content |
|---|---|---|
| Rail | 120 × full height | 6 entries of 108 × 78 (margin 6), vertically centred. Icon 36 px + label 20 px. Selected: accent fill 18 % plus a 5 px accent bar on the left. Locked: 40 % opacity. NEW: a 20-px pill "NEW" (accent fill) **beside** the icon. |
| Header | 1134 × 84 | "‹" 76×76 · title 32 px · sub-tabs as separate buttons, each ≥ 124 × 74 (22 px) with gap 8 · cash (caption 20 + value 28) · "×" 76×76 |
| Content | 1134 × (canvas − 84), padding 10/16 | page |

- **Sub-tab width check:** 5 tabs × 124 + 4 × 8 = 652 px. 76 + 12 + ~140 (title) + 652 + 12 + ~150 (cash) + 76 = 1118
  ≤ 1134 [arithmetic]. For "Test arena" (≈ 121 px of text at 22 px) the button grows to 157 px. If the 5 tabs then do
  not fit, the title shrinks to the entry icon (the rail shows the name anyway).
- **Toasts:** the toast lane (x ≈ 468–786 canvas px on the phone) overlaps the sub-tabs. Toast frames must not sink
  input [A: check `Toast.module.luau` item frames have `Active = false`].
- **Page scale per page** until P3:
  - native pages (Home, Shop) at 0.598;
  - LabApp's Models page keeps its own compact tokens (page UIScale 0.722 → 0.432 effective, as tuned in LAB_SPEC 4.1);
  - legacy pages (EmpireApp tabs, Market, Data, GPUs, Projects, Test arena, Campus) at 0.80 effective (page UIScale
    1.338; 14 px → 11.2 pt).
  - The legacy zoom is **reported separately** in the size test until P3 gives each page native tokens.
  - **Fix round 1 (review): legacy floor.** The shell raises every legacy-page text below 14 px to 14 px (11.2 pt on
    the phone, above Apple's 11 pt minimum) on mount, on show and for rows added later (`Computer.LEGACY_TEXT_MIN`);
    the small touch targets found on the phone (Market Auto price / Manual, Sub price chips, API − / +, RETIRE; Team →
    Staff filter chips; Team → Campus card and store buttons) are 56 px on touch (44.8 pt). Market → My AIs shows the
    live models with their price row first (B9), Team → Staff the Hire cards first. `tests/menu/sizes.py` now FAILS a
    legacy page below 11 pt text or 44 pt targets (measured over the whole scroll, not only the visible window).
- **The Model Studio is untouched.** Its host stays the frame "Computer" (LAB_SPEC 3.1). Hiding the Models page closes
  it as today.

### B4. Home → Today
- **Layout:**
  - line "What to do next" with an "All goals ›" link on the right (44 px row since fix round 1, so the 74 px link
    starts at the page clip instead of 6 pt above it);
  - **3 action cards** in one row (each ≈ 356 × 262 px on the phone, 290 on desktop):
    - kind caption with icon (20 px caps);
    - title (28 px, ≤ 2 lines);
    - one line (22 px, prefer 1 line);
    - button 74 px full width (the first card's button is primary);
  - **live strip** 98 px: CASH · NET (good colour) · USERS · LIVE · TRAINING, plus "DAILY +$X" (secondary button 74 px)
    while `ClaimDaily` is possible (reward 1000 + (streak − 1)·500) [V EmpireService `daily`];
  - **desktop only:** a Goals row ("GOALS · n of 12 done", bar, "Next: {quest name} · +$reward").
  - Phone total: 10 + 44 + 8 + 262 + 14 + 98 = 436 ≤ 436 px, so nothing scrolls [V mockup; 34 px row + 10, fix round 1].
- **`Home.cards(snapshot, ui) → {Card}`** (new, pure, unit-tested). Take the first 3 distinct cards in this priority:
  1. **Urgent:** a training decision is pending → "Decide: {event title}"; cash < 0 → "Cash below $0 · lower costs" →
     Team → Settings; serving ≥ 95 % with a waitlist → "Servers full · buy a GPU" → Lab → GPUs.
  2. **Guide active:** the guide card, with kind "FIRST STEPS · n/5" and the same title, line and action as the HUD
     (ringed like the HUD action, no chip). Step 1 uses the line "{A}: I picked a good first model for you.", because
     the world hints ("walk to the glowing computer", "press C") make no sense inside the Menu.
  3. **Ready:**
     - "Launch {Model}" when a model is trained but not launched;
     - "Collect ${sum}" for claimable quests, line "Goal done: {quest name}" (claims in place with
       `ClaimQuest {all = true}`);
     - "Move to {office}" when the office is affordable and allowed;
     - "Meet {n} applicants".
  4. **Next goal:** `EmpireMath.nextGoal` worded by `HUD.describe`, with the same title as the HUD card and the HUD's
     `shortProgress` as its line (e.g. "Sign your first client (CloudDesk)", line "Trust 0 %", button
     "OPEN CLIENTS ›") [V HUD.describe]. The describe *body* ("CloudDesk wants a pilot. You drive over by yourself in a
     moment.") is too long for the card's one line; revision 1's "Your founder pitches there." was not a game text.
     Skipped while the guide card shows, because the next goal is then the guide's own goal ("Train your first AI").
  5. **Fillers:**
     - "Train a new AI" with "A successor takes over 90 % of {Model}'s users." (ModelConfig migrate share 0.9, LAB_SPEC
       4.12–4.13) and button SUCCESSOR › (or DESIGN ›);
     - "Hire" (free desks and auto-HR off);
     - "Buy GPUs" (VRAM is missing).
  - **Never a Shop card.**
  - Fewer than 3 distinct cards (e.g. step 1: guide + Collect): the row shows what exists, left-aligned. No made-up
    filler.
- **Home → Money** = today's Company → Money builder, with Company → Overview's profit chart, "Market cycle" card and
  metrics (cash, profit per game day, active users) on top [V EmpireApp `overview`].
- **Home → Goals** = Company → Goals plus a "Collect all" button, the Overview's "A business with a plan" card, and the
  **"Guide & tips"** card (A12). Fix round 1: "Collect all" shows only when something can be collected; each goal shows
  its progress ("0 / 1B", "Collected ✓") as a text line and a COLLECT button only when ready; "Guide & tips" is the
  first card while the guide runs.
- The Overview's "Daily founder grant" card becomes the live strip's DAILY button; its three shortcut buttons
  (Clients / Money / Settings) are dropped, because the rail does their job.

### B5. Unlock waves and NEW badges (from existing data: `TutorialMath.unlockedKeys(data)`)
| Wave | State | Visible from then on |
|---|---|---|
| 0 | company exists | Home (Today, Goals); Lab (Models, Data, GPUs) |
| 1 | `stats.modelsTrained >= 1` | Lab → Test arena; Market → Projects |
| 2 | `stats.modelsReleased >= 1` | Market (My AIs, Lines, Leaderboard); Clients → Clients; Team (Staff, Office, Fleet, **Campus**, Settings); Home → Money; **Lab → Research**; **Shop** |
| 2 early | Σ employees ≥ 1 or `empire.points >= 50` (before a launch) | Lab → Research |
| 3 | `empire.contractsCompleted >= 1` | Clients → Receipts |

- Revision 2 moved **Team → Campus** from "office ≥ 2" to wave 2: its content works in the garage today (employee card
  and replacement, one-hour guest cards, store upgrades that earn money, snacks) [V CampusApp `access`, `shops`], so
  hiding it would remove features from the Menu.
- Revision 2 moved **Lab → Research** to wave 2 as well: it now also holds Market's "Your API subscription" and
  "Provider exchange", and the API subscription is a way to earn research points ("API access adds research points
  while active" [V MarketApp]). Gating it on 50 points would hide one way to get them. The cheapest research needs
  50 points (Parallel Training) [V EmpireConfig.RESEARCH], so the early rule shows it exactly when it can be used.
- Before the first launch only Home and Lab are open. Nothing behind the locked entries is needed to release the first
  AI, and deep links still open them (below).

- **Locked top entries:**
  - they stay visible at 40 % opacity with no padlock;
  - a tap shows a centred card, e.g. **"Market opens after your first launch."**, then "Train your first AI and launch
    it. Then Market, Clients, Team and Shop open.", then [GO TO LAB ›];
  - locked sub-tabs are hidden.
- **Deep links are never blocked:** a world prompt, phone link or assistant button that targets a locked page opens it
  and marks it unlocked.
- **NEW badges:**
  - a pill on the rail entry and on the sub-tab until it is opened once (op `seen`, keys batched);
  - suppressed while the guide is active, then shown at the end with the hand-off toast;
  - **the Shop never gets a NEW badge.**
- `SEEN_KEYS` = `home.money`, `home.goals`, `lab.data`, `lab.gpus`, `lab.research`, `lab.arena`, `market`,
  `market.projects`, `clients`, `clients.receipts`, `team`, `team.fleet`, `team.campus`, `team.settings`.

### B6. One exit rule, input
- **"‹"** goes back one level: a sub-tab other than the default → the default; an entry other than Home → Home; Home →
  close.
- **"×"** always closes.
- **Desktop only:** a click on the backdrop closes. Not on phones, to avoid accidental closes [A].
- **Gamepad:**
  - **ButtonL1** toggles the Menu in the world: `ContextActionService:BindActionAtPriority` at
    `Enum.ContextActionPriority.Medium.Value` (the enum has Low / Medium / High, no "Default" [V API dump]). The
    Studio's High-priority L1/R1/B binding wins while it is open (LAB_SPEC 3.5) [A: check that no core binding uses L1];
  - **ButtonB** = back, then close, bound only while the Menu is open and the Studio is closed;
  - on open, `GuiService.SelectedObject` = the first Home card button;
  - fix round 1: a page switched by a deep link (HUD Shop button, Home card, tip) gives its first selectable button the
    selection when the old one is outside the Menu or on a hidden page (a selection on the rail / header stays); B / ‹
    first closes the locked-entry card, and `Computer.close()` hides it; an open shop use sheet takes B itself (SHOP_SPEC
    5.3).
- **Sub-tab row:** hidden when only one tab would show (e.g. the Shop's "coming soon" state), fix round 1.
- **PC:** C toggles the Menu (today's key) [V HUD]. Keys 1–6 select entries (nice-to-have).

### B7. One name per place, and text fixes
- **Glossary:** Menu · Home · Lab · Model Studio (only the editor's title) · Data · GPUs · Research · Test arena ·
  Market · My AIs · Lines · Projects · Leaderboard · Clients · Receipts · Team · Staff · Office · Fleet · Campus ·
  Settings · Shop.
- **Text fixes:**
  - AssistantService advice "raise prices in Models … pause HR in Company → Settings" → "raise prices in Market → My AIs
    … pause HR in Team → Settings";
  - the Studio's "OPEN COMPUTE" → "OPEN GPUs" (request to the lab package, not done by this builder);
  - the HUD toast "Open your computer to see it" → "Tap the goal card to see it";
  - phone deep links "Open Company → Money/Team" → "Open Home → Money" / "Open Team" (PhoneScreens) [V];
  - phone message "Open Company → Office when you want to move" → "Open Team → Office …" (PhoneMath, search
    `Open Company → Office`) [V];
  - AssistantService briefing rows "Automatic hiring is on (Company → Settings)" and "hire in Company → Team" →
    "(Team → Settings)" / "hire in Team → Staff" [V];
  - remove the placeholder "Noah Studio" in StudioApp: the prefilled box (`name.Text="Noah Studio"`) gets an empty box
    with the placeholder "Your brand or project name", and the browser preview's brand label (second `"Noah Studio"`)
    shows the typed name or "Your brand" [V StudioApp].
  - P1 already applies the texts that do not name new places (HUD toast, "Noah Studio"); the place names change in P2.

### B8. Icons (Kit.icon, blocks and rings, no rotation)
- home: 2×2 rounded tiles.
- lab: today's neuron.
- market: price tag (a block with a hole).
- clients: briefcase (wide block + handle + strap). It must not read as a padlock.
- team: two heads and two bodies.
- shop: today's bag in `C.warn`.
- The old "empire" icon is not used for navigation any more.

### B9. Old → new mapping (route table inside `Computer.open(appId, section)`; no server change)
| Old (app / section) | New place |
|---|---|
| empire / nil, overview; ownerComputer | Home → Today (guide steps 1–2: Studio design, A8). The garage founder computer sends `OWNER_COMPUTER {app = "empire"}` [V FacilityService, RoomKitsGarage]; the pavilion's "Private lab computer" sends `app = "lab"` [V RoomKitsPavilion] |
| empire / clients, contracts | Clients → Clients |
| empire / money | Home → Money |
| empire / team | Team → Staff (hire cards first) |
| empire / research | Lab → Research |
| empire / milestones | Home → Goals |
| empire / office | Team → Office |
| empire / settings | Team → Settings (also the HUD's jet goal, which opens `empire/settings` and its "Company jet" card [V HUD.describe]; there is no `jet` section [V EmpireApp builders]) |
| empire / board | Market → Leaderboard |
| lab / nil, design, train, evaluation, release | Lab → Models + `LabApp.openSection(section)` |
| data | Lab → Data |
| compute | Lab → GPUs |
| market | Market → My AIs (price chips ≥ 44 pt first), with Market's metrics (Users, Net income, Reputation, Revenue, Serving cost, Rank) and "Serving capacity" on top [V MarketApp] |
| Market "Intelligence leaderboard · live models" | Market → Leaderboard, above Company → Board's "Company rankings" |
| Market "Product lines" | Market → Lines |
| Market "Your API subscription", "Provider exchange" | Lab → Research |
| Market "Business clients · receipts" | Clients → Receipts |
| studio | Market → Projects |
| arena | Lab → Test arena |
| campus / nil (CampusConfig stores "House Kitchen" and "Fleet Desk" send `app = "campus"` [V]) | Team → Campus |
| campus / access ("Cards & guests") | Team → Campus, section "Cards & guests" |
| campus / shops ("Stores & snacks") | Team → Campus, section "Stores & snacks" |
| campus / fleet | Team → Fleet |
| campus / building ("Your headquarters", directory, getting around, founder camera control, use the rooms) | Team → Office, below Company → Office's upgrade card |
| shop | Shop |
| unknown id | Home |

Company → Settings "Lab level" card: removed as a duplicate. Lab level stays on Lab → Models.
Team → Campus is one page with two stacked sections ("Cards & guests", "Stores & snacks"), so the 2-level rule holds.
T11 greps every `(app, section)` pair in `work/src` (prompt attributes, `OWNER_COMPUTER` payloads, PhoneService
`open/section`, AssistantService recommends, HUD.describe, JourneyMath, DepartmentConfig, CampusConfig) and checks
that each lands on a page that exists.

### B10. Taps for the 10 common actions (phone, start in the world)
| # | Action | Today (taps / swipes) | New (taps / swipes) |
|---|---|---|---|
| 1 | Train the first model | 5 / 0 via the menu; the HUD goal takes a detour through Datasets (5–6 / 1) | **3 / 0**: HUD goal or OPEN LAB · BUY DATA PLAN · START |
| 1b | Train a later model | 4 / 0 | 3 / 0: Menu · Home "Train a new AI" · START (4 when the suggestion includes a data plan: BUY DATA PLAN first [V DesignSteps]) |
| 2 | Launch it | 3 / 0 | 3 / 0: Menu · Home "Launch {Model}" · LAUNCH (4 when the reveal has not played yet: + LAUNCH ›) |
| 3 | Set a price | 3 / 1–2 | 3 / 0: Menu · Market · price chip |
| 4 | Hire | 3 / 0–6 | 3 / 0: Menu · Team · Hire |
| 5 | Buy GPUs | 3 / ~2 | 4 / 0: Menu · Lab · GPUs · BUY (3 via Home "Servers full") |
| 6 | Upgrade the office | 2 | 2 via the Home card "Move to {office}" (shown whenever the move is allowed and affordable); 4 via Team → Office when three higher cards fill Home |
| 7 | See money | 2 | 2; the Home live strip needs 1 |
| 8 | See clients | 2 | 2 |
| 9 | Open the shop | 2 (and it says "Coming soon") | **1** (HUD Shop button) / 2 via the Menu |
| 10 | Company phone | 1 | 1 |
Source of "today": menu.md 5 [R]. "New" are designed values, to be confirmed on renders in P2 [A].

### B11. HUD changes
- "Open company" → **"Menu"** (keycap C) in P2, and it always opens Home. P1 keeps the label.
- "Collect reward" → **"Collect $X"**: it claims everything in place (`ClaimQuest {all = true}`) with one toast
  "+$X from N goals".
- **Shop button:**
  - shown after the first launch, once the guide is done or skipped, and only if the shop is visible
    (`ShopConfig.anyListed()` on live servers, or Studio);
  - row: [Menu] [bag icon + "Shop" in `C.warn`], 70 px tall;
  - never during the guide.

### B12. Contracts that must keep working
- `Computer.open/close/toggle/isOpen/show` and their signatures [V exports].
- The root frame name "Computer".
- The LabApp container given to `LabApp.mount`.
- The HUD names `NextGoal`, `Title`, `Have`, `Eta`, `NetPerDay`, `RewardReady` (tests/apps).
- The ShopApp names `ComingSoon`, `NothingNow`, `Thanks`, `Product_<key>`, `Pass_<key>`, `Voucher_<key>` [V].
- The strings tests/models reads after `Computer.open("lab")`.

---------------------------------------------------------------------------------------------------------------------
## C. ROBUX SHOP

### C1. Status and placement
- **Server:** correct per Roblox's docs:
  - one ProcessReceipt, grant before `PurchaseGranted`, the grant saved per PurchaseId;
  - passes through UserOwnsGamePassAsync + PromptGamePassPurchaseFinished;
  - prices read with GetProductInfoAsync on the client [R shop.md 2; V member names].
- **Every id is 0** (ShopConfig `id = 0` on all 11 entries) [V], so the user sees "Shop coming soon".
- **Placement:**
  - a normal Menu entry "Shop" (gold bag; locked until the first launch, like Market);
  - the HUD Shop button (B11);
  - Roblox's own Shop stays in the Roblox menu (default), and its global top-bar button stays off (default) [V doc].
- **Never:**
  - in the guide, a goal card, a tip or a Home card;
  - opened automatically or prompted after a failure (e.g. NO_MONEY);
  - with timers or the words "limited", "deal", "best value" or "worth".
  - Wording follows Roblox's minor-safe examples ("Open Shop", "See Price") [V].

### C2. Page (ShopApp rebuilt as a native Menu page, content 1134 px wide)
Order, one vertical scroll:
1. Line: "Optional extras for Robux. You can reach every office and every client without them." (true: the casual sims
   reach stage 5 with no purchases, CORE_SPEC 9.1 [R design C2]).
2. Studio only (`RunService:IsStudio()`), a dashed gold banner: "OWNER PREVIEW · Studio only. Items without an id show
   'Not set up'. Nothing can be bought here."
3. **YOUR ITEMS** (only when not empty):
   - vouchers to redeem: [REDEEM] primary 170×74, disabled with the reason when no desk is free;
   - owned passes: "✓ Owned" chip in the good colour, with the line "Your gold VIP tag is on." or similar.
4. **Featured tile** (1102 × 160, gold-tinted gradient, icon 120): the first entry of the fixed order {VIP Founder,
   Founder Suite, Executive Limo, Investor Relations, Team party} that is listed, available, priced, for sale and not
   owned. It has no "featured" or "deal" label, only its tag.
5. **PASSES** · "buy once, keep".
6. **EXTRAS** · "one-time": Team party, Headhunter.
7. **COMPANY CASH** · "one-time · grows with your office": Seed, Series A, Series B.
8. **SUPPORT THE DEVELOPER**: Supporter tip, Big supporter tip.

**Row** (1102 × 126 px):
- icon tile 94 px, when id > 0: `rbxassetid://{IconImageAssetId}` from the same `GetProductInfoAsync` result that
  gives the price (products and passes; 0 means "no icon") [V MarketplaceService doc]. A pass may instead use
  `rbxthumb://type=GamePass&id={id}&w=150&h=150` [V assets doc]. **There is no rbxthumb type for developer products**
  (revision 1 used `type=DeveloperProduct`) [V assets doc]. Otherwise, and in Studio with id 0, a Kit icon;
- name 28 px bold + tag chip 20 px;
- effect text 22 px, at most 2 lines;
- **price chip** 170×74 px, secondary style with an accent stroke: "R$ {PriceInRobux}" (fix round 1, SHOP_SPEC 5.2.1: no
  official Robux glyph is documented, so the text stays "R$").

| Price chip state | Shows |
|---|---|
| price loaded | "R$ " + price (client, `GetProductInfoAsync`, also check `IsForSale == true`) |
| loading | "…" (disabled) + one line "Loading prices from Roblox…" |
| failed or `IsForSale == false` | row hidden on live servers + one line "Some items couldn't load." |
| owned | "✓ Owned"; the row moves to YOUR ITEMS |
| Studio and id = 0 | "Not set up" (grey, never prompts) |

- **Page states:**
  - live with every id 0 → today's "Shop coming soon" card (`ComingSoon`) with the line "Nothing to buy yet. Every
    office and every client can be reached without the shop.", and no HUD Shop button;
  - some ids set → only listed items;
  - Studio → all 11 items (preview).
- **Purchase flow (server unchanged):**
  - chip → `PromptProductPurchase` / `PromptGamePassPurchase` (ShopApp `prompt()`) → the Roblox window → ShopService
    grants → `SHOP_GRANTED` toast;
  - the chip shows "…" for 2 s after a tap;
  - nothing is granted on the client.

### C3. Catalogue and honest texts (in-game text; the owner pastes the same text on the Creator Hub)
| key | Creator Hub type | Name | Tag | In-game text (≤ 2 lines) | Suggested Robux (ShopConfig comment; owner decides) |
|---|---|---|---|---|---|
| vip | Pass | VIP Founder | Cosmetic | "A gold VIP tag above your character and a VIP badge in your Menu." | 149 |
| limo | Pass | Executive Limo | Car + perk | "A limousine for your fleet (top speed 78 when you drive; the free car does 64). VIP helicopter transfers are free (normally $2,500)." Revision 1 said "looks only, not faster", which is false: CampusConfig.CARS speeds are Founder's Hatch (free) 64, Studio Cargo 58, Executive Limousine 78, Executive Electric 82 ($28,000 cash), Circuit GT 104 [V]. Driver trips use fixed road speeds (DrivePlan.SPEED road 64), so only manual driving is faster [V]. HELI_FEE 2500, free with the pass [V ShuttleService] | 199 |
| founderSuite | Pass | Founder Suite | Cosmetic | "A brass and leather lounge with a fire bowl on your founder terrace. Appears from Founder Headquarters on." | 199 |
| investor | Pass | Investor Relations | Gameplay bonus | "+10 % on your app and API income. Business clients are not boosted. Other players are never affected." (`INVESTOR_MULTIPLIER = 1.10`, market only, never B2B [V]) | 349 |
| party | Developer Product (a voucher, redeemed later [V ShopConfig kind "voucher"]) | Team party | Cosmetic | "Balloons, a banner and sparkles in front of your HQ for 3 minutes. Just for fun." (`PARTY_SECONDS = 180` [V]) | 25 |
| headhunter | Developer Product (a voucher [V]) | Headhunter | Helper | "One top applicant (skill 4–5 of 5) applies. Redeem when a desk is free; the voucher is kept until then." (RecruitingService: hidden skill 4 or 5 [V]) | 39 |
| seed | Developer Product | Seed round | Company cash | "+{amount} company cash now: a quarter of the {next office} price." | 49 |
| seriesA | Developer Product | Series A | Company cash | "+{amount} company cash now: {three quarters / half} of the {next office} price." | 129 |
| seriesB | Developer Product | Series B | Company cash | "+{amount} now: {twice / the full} {next office} price." Garage add-on: "Leaving the garage still needs your first client." (`FIRST_CLIENT` gate [V]) | 299 |
| tip | Developer Product | Supporter tip | Tip | "Say thanks to the developer. You get a thank-you note, nothing else." [V current text] | 25 |
| bigTip | Developer Product | Big supporter tip | Tip | "A bigger thank-you to the developer. Nothing else changes." [V current text] | 100 |

- **Wording of the cash share:** 0.25 = "a quarter of", 0.5 = "half of", 0.75 = "three quarters of", 1.0 = "the full",
  2.0 = "twice the".
- **At the last stage** the text reads "+{amount} company cash (based on the Global AI Headquarters price)."
- **Amounts** come from `ShopConfig.cashFor` (rounded to $100, minimum $2,000).
- **No paid random items:** the catalogue has none [V ShopConfig header]. Keep it that way, so no odds and no
  PolicyService are needed.

### C4. Small fixes
| Fix | Where |
|---|---|
| The limo card says "Get the pass" and opens "Shop coming soon" while the pass id is 0. Show "Not available yet" (disabled) when `ShopConfig.pass("limo").id <= 0` or the pass is unavailable | CampusApp (search `"Get the pass"`) [V] |
| The Founder Suite fallback passes the office index where a plan tier is expected. Use `Plan.tierForOffice(session.data.empire.office)` (BuildingPlan) | ShopService (search `ShopDecor.founderSuite(`) [V] |
| Voucher errors say the voucher is kept: STAFF_FULL "All desks are filled. Your voucher is kept.", NO_CANDIDATE "No applicant found right now. Your voucher is kept.", NO_COMPANY | ShopApp MESSAGES [V codes exist in RecruitingService] |
| Check `IsForSale == true` as well as `PriceInRobux` | ShopApp fetchPrice |
| Investor text (B2B excluded) and the header jargon "Prices come from Roblox, and nothing here is random." → the C2 line | ShopApp |
| Comment "Packs save minutes, not hours": correct it (O1 default) or keep it true with the cap | ShopConfig |
| The limo pass desc says "Adds the Executive Limo to your company fleet. Cosmetic." The limo is faster than the free car (78 vs 64). Use the C3 text; also on the Creator Hub | ShopConfig `PASSES` limo, CampusApp fleet card |
| Icons: read `IconImageAssetId` from the `GetProductInfoAsync` call that `fetchPrice` already makes (C2) | ShopApp fetchPrice |

### C5. Fairness (for O1)
- **Other players are never affected:** all other players together weigh 0.15 of one company per segment, and B2B
  clients are per player (CORE_SPEC 3.2/11.7) [R shop.md 3.3].
- **The buyer's own progress:** pack value in minutes of casual net income. Net $/min per stage, from CORE_SPEC 9.1 at
  a sample minute: 2,662 / 11,799 / 29,532 / 46,315 / 71,952 [R design C5]. Amounts are from `cashFor` with the office
  prices 27,000 / 100,000 / 380,000 / 1,900,000 [V]; I recomputed them today.

| Stage | Seed 0.25 | Series A 0.75 → 0.5 | Series B 2.0 → 1.0 |
|---|---|---|---|
| 1 Garage | $6,800 = 2.6 min | $20,300 = 7.6 → $13,500 = 5.1 | $54,000 = 20.3 → $27,000 = 10.1 |
| 2 Founder HQ | $25,000 = 2.1 | $75,000 = 6.4 → $50,000 = 4.2 | $200,000 = 17.0 → $100,000 = 8.5 |
| 3 Startup Campus | $95,000 = 3.2 | $285,000 = 9.7 → $190,000 = 6.4 | $760,000 = 25.7 → $380,000 = 12.9 |
| 4 Innovation Campus | $475,000 = 10.3 | $1.425M = 30.8 → $950,000 = 20.5 | **$3.8M = 82.0** → $1.9M = 41.0 |
| 5 Global HQ | $475,000 = 6.6 | $1.425M = 19.8 → $950,000 = 13.2 | $3.8M = 52.8 → $1.9M = 26.4 |

- Today one Series B pays for a whole office move from stage 2 on, because after the garage the price is the only gate
  (EmpireService `upgrade`) [V].
- With 1.0× a pack is never more than one office price.
- **Owner decides** (O1). The mockup shows the capped amounts and says so.

### C6. Owner guide (German, for the user)
> **So schaltest du den Robux-Shop frei** (einmalig, ca. 20–30 Minuten)
> 1. **Spiel veröffentlichen.** Produkte und Pässe gibt es nur für ein veröffentlichtes Spiel.
> 2. Öffne **create.roblox.com** → **Creations** → dein Spiel.
> 3. **Developer Products** (Geld-Pakete, Gutscheine, Trinkgeld): **Monetization → Developer Products →** neues Produkt
>    anlegen. Bild hochladen (höchstens 512×512, .png/.jpg/.bmp), Name, Beschreibung (Texte aus der Tabelle),
>    Kategorie, **Preis in Robux** → speichern. Danach mit der Maus aufs Bild → **⋯** → **Copy Asset ID**.
> 4. **Pässe** (VIP, Limousine, Founder Suite, Investor): **Monetization → Passes → Create pass**. Bild, Name,
>    Beschreibung, Kategorie → **Create pass**. Zum Verkaufen: auf der Seite des Passes unter **Sales** „Item for Sale"
>    einschalten, Preis eintragen, **Save Changes**. Das steht so in einer Anleitung von OneEsports, die offizielle
>    Roblox-Seite beschreibt diesen Schritt nicht. Bitte im Creator Hub nachsehen. ID: **⋯ → Copy Asset ID**.
> 5. Die Zahl in `ReplicatedStorage/Shared/Config/ShopConfig.module.luau` in der passenden Zeile hinter `id = `
>    einfügen (statt `0`). Speichern und **neu veröffentlichen**.
> 6. **Wichtig:**
>    - Pässe erscheinen laut Roblox-Doku automatisch auch im Roblox-Shop im Roblox-Menü. Lege nur Pässe an, deren
>      Funktion schon im Spiel ist. Alle vier funktionieren heute.
>    - Schreib im Creator Hub dieselben ehrlichen Texte wie im Spiel.
>    - Eine Produkt-ID nie für etwas anderes wiederverwenden.
>    - Testen nur im veröffentlichten Spiel. In Studio zeigt der Shop eine „Owner Preview" ohne Kaufen.
>    - Nie ausgedachte IDs eintragen, nur IDs, die du selbst kopiert hast.

The table for step 3/4 is C3, columns "Creator Hub type", "Name", "In-game text" and "Suggested Robux".

---------------------------------------------------------------------------------------------------------------------
## 4. Files touched (all phases)
| Phase | File | Change |
|---|---|---|
| P1 | **new** ReplicatedStorage/Shared/TutorialMath.module.luau | A5: step logic, texts, keys, unlockedKeys, assistantName |
| P1 | **new** Client/Controllers/GuideController.module.luau | runs `TutorialMath.step` on StateController and Studio mode changes; drives the HUD guide mode, ring layer, world pointer and tips; sends EmpireAction `tutorial` ops |
| P1 | **new** Client/UI/Screens/Guide.module.luau | ring / dim / chip layer, ScreenGui `AIEmpire_Guide` (22) |
| P1 | **new** ServerScriptService/Server/Lib/Funnel.module.luau | A11 |
| P1 | Shared/EmpireMath.module.luau | `tutorial` default in `Math.new()` |
| P1 | Server/Lib/Template.module.luau | `Template.cleanTutorial` and its call in `migrate` |
| P1 | Server/Services/EmpireService.module.luau | EmpireAction `tutorial` ops; `ClaimQuest {all = true}` (claims every eligible quest in one call with no yield between check and grant, returns `{ok, claimed = {ids}, total}`; the single-id path stays) |
| P1 | Server/Services/AssistantService.module.luau | skip the greeting while active; the B7 text fix |
| P1 | Server/Services/SessionService, CompanyService | `Funnel.step` 1 and 2 |
| P1 | Client/UI/Screens/HUD.module.luau | guide mode (A2.1); compact phone panel (A2.2); `describe` "train" → `app = "lab", section = "design"`, progress "Open the Lab", no "Step 1 of 7"; LAB_SPEC 4.14 `revealId`; "Collect $X" in place; C key / Open company redirect in steps 1–2 |
| P1 | Client/UI/Screens/Intro.module.luau | A7 |
| P1 | Shared/Config/CompanyConfig.module.luau | `COMPANY_NAME_IDEAS` |
| P1 | Client/Controllers/WorldController.module.luau | `OWNER_COMPUTER` → lab/design in steps 1–2 |
| P1 | Client/Controllers/JourneyController.module.luau | off while the guide is active |
| P1 | Client/UI/UIRoot.module.luau + Client/Main.client.luau | mount Guide, init GuideController |
| P1 | Client/UI/Screens/Computer.module.luau | only `button.Name = "Nav_" .. id` in `buildNavButton` (ring target `menu_lab`, A9); the "Guide & tips" card goes into EmpireApp `settings` |
| P1 | Apps/EmpireApp | "Guide & tips" card in Settings (A12) |
| P1 | Apps/ShopApp, Apps/CampusApp, Services/ShopService, Config/ShopConfig | C3 texts, C4 fixes, Studio owner preview |
| P1 | Apps/StudioApp | remove "Noah Studio" |
| P1 | tests/apps/test_ui.luau | replace the 3 garage checks that encode the bug ("Step 1 of 7", hint "Datasets", "tap opens the Datasets app") with "tap opens the Model Studio design view" [V lines ≈ 116–121] |
| P2 | Screens/Computer.module.luau | new shell (rail, header, back/close, scale, route table, unlocks, badges, page host) |
| P2 | **new** UI/Apps/HomeApp.module.luau + `Home.cards` | B4 |
| P2 | Apps/EmpireApp | `App.mountPage(container, tabId)` that renders one existing tab builder |
| P2 | Apps/MarketApp | page builders `myais / lines / leaderboard / access / receipts` |
| P2 | Apps/ShopApp | C2 page layout |
| P2 | Screens/HUD | "Menu" label, Shop button, L1 opens the Menu (P1: L1 selects the guide action, A10) |
| P2 | Kit.module.luau | new icons |
| P2 | Phone/PhoneScreens, Shared/PhoneMath, Services/AssistantService | deep-link labels and place names (B7) |
| P2 | JourneyController | removed |
| P3 | Apps/DataApp, ComputeApp, CampusApp, EmpireApp pages | native tokens, primary action first (Hire, BUY, price chips) |

## 5. Tests the builder must write (report each as passed / failed / not run)
- **T1 `tests/guide/test_tutorialmath.luau`:** `TutorialMath.step` for each case:
  - fresh save, Computer closed → 1;
  - Studio design without data → 2 buyData with target `Primary`; after the data plan → 2 start with target `Primary`;
  - plan costs more than the cash → 2 cash edge with the "Datasets has free data" line; starter GPU only and nothing
    claimable, daily taken → the "00:00 UTC" line (never the "Sell a GPU" line);
  - Studio closed after opening it with saved step 2 → 2 (not 1);
  - training → 3 wait with eta text; pending event → 3 decide;
  - trained, not revealed, world → 4 open with action "SEE YOUR AI ›"; reveal mode → target `Launch`; launch mode →
    target `LaunchButton`;
  - released, no revenue → 5 waitIncome; first revenue → 5 income;
  - skipped → nil; done → nil;
  - old save with a release after the cleaner → nil with `seen` filled; old save trained but unreleased → 4;
  - data bought in Datasets first → 2 start;
  - extra Robux cash → the same steps;
  - `collect` = the exact sum of claimable rewards;
  - `{Name}` dropped when > 12 characters.
- **T2 cleaner:**
  - idempotent (two runs give equal output);
  - junk types repaired;
  - unknown seen/tip keys dropped;
  - `step` clamped to 0..5; `step = "3"`, `NaN`, `math.huge` and `true` give 0 (the revision-1 snippet threw here);
  - DATA_VERSION unchanged;
  - `tests/econ/test_net.luau` (replication budget, CORE_SPEC 11.8) still passes with the field.
- **T3 EmpireAction `tutorial`:**
  - each op's rule;
  - negatives: `done` before release → NOT_READY; `restart` after release → NOT_AVAILABLE; `step` 6 on a fresh save →
    BAD_INPUT; `seen` with an unknown key → BAD_INPUT;
  - no op changes money.
- **T4 `ClaimQuest {all = true}`:**
  - grants each quest once;
  - a second call claims nothing;
  - `total` = the sum of rewards;
  - the single-id path is unchanged.
- **T5** `TutorialMath.assistantName(id)` equals the first name of `AssistantService.identity(id)` for 20 ids,
  including −1 and 1 (expected "Ada").
- **T6 resolver:** each abstract target id resolves to a **visible** GuiObject in the Studio and HUD test scenes. It
  fails loudly if `Primary`, `Decision`, `Launch`, `LaunchButton`, `DesignNewModel` or `Nav_lab` is renamed. In the
  first-model Review scene the resolved step-2 target must be `Primary` with the text "BUY DATA PLAN · $7,400" (then
  "START TRAINING · $1,280"), and `BuyDataPlan` must be invisible there (the revision-1 bug).
- **T7 guiprev, at 844×390 and 1280×720 with `--report`, plus size thresholds:**
  - **text ≥ 12 pt** (the 20 px floor at 0.598; 19 px in the HUD at 0.648), **targets ≥ 44 pt**, nothing above the
    58-pt top inset;
  - **HUD column bottom ≤ 271 pt** on the phone (insets 58/47/21/47) in every guide step, the hand-off and normal
    mode: 8 pt above the jump button top (279 pt, A2.1);
  - scenes: the HUD in every guide step; the Studio with the ring on all 5 targets; the Intro (default + Customize).
- **T8 negatives:**
  - the ring rect never overlaps the inside of its target;
  - the chip never overlaps the target or another button; no chip exists while the Computer is open;
  - gamepad: in world steps the guide never sets `GuiService.SelectedObject` by itself (only on L1);
  - the guide card is hidden whenever `Computer.isOpen()`;
  - no guide object is a GuiButton or has `Active = true`.
- **T9 `Home.cards`:**
  - cases: fresh, guide active, training, decision, trained not launched, claimable, cash < 0, office affordable,
    servers full, late game;
  - never a Shop card.
- **T10 `unlockedKeys`:** fresh / first trained / first launch / first hire / first client / office 2 / old save.
- **T11 route table:**
  - every old (app, section) pair found by grep lands on an existing page, including `campus/access`,
    `campus/shops`, `empire/board`, `empire/office` (PhoneService ring) and `campus/fleet` (FacilityService);
  - no Menu-reachable feature of today disappears in any wave: Campus, Research with the API subscription, and the
    Overview's chart, market cycle and daily grant each have a page;
  - unknown → Home;
  - back rule: from every page, ‹ or B leads to Home, then closes, and never leaves a hidden selected object.
- **T12 shop:**
  - tests/shop stays green (146/0 server, 46/0 client [R]);
  - Studio preview shows 11 rows and never calls Prompt*;
  - live with every id 0 → `ComingSoon`, no rows, no HUD Shop button;
  - `IsForSale == false` → hidden;
  - owned pass → YOUR ITEMS with "✓ Owned";
  - featured = the first by the fixed order;
  - no Shop in `Home.cards`, `TutorialMath.step` or tips;
  - no prompt after a NO_MONEY error;
  - `cashFor` matches the C5 table for the shares in force.
- **T13 Studio-only checks [A], reported "not run" until done in Roblox Studio:**
  - taps pass through the dim and ring;
  - ring alignment;
  - untextured Beam visibility;
  - L1 free outside the Studio;
  - jump button position vs the HUD column: which TouchJump variant runs (classic 70 pt at y 279–349, or the
    ability-controls one at y 233–305), measured on an iPhone and in the Studio device emulator;
  - a gamepad-selected HUD button really blocks walking (the reason for A10's L1 rule);
  - toast frames do not sink input;
  - gamepad selection.

## 6. What stays unchanged
- **The lab package:** Studio, LabApp, DesignSteps, Stages, LaunchDay, LabPreview, LabState, StudioParts. Requests to it
  are text only ("OPEN GPUs").
- **The economy:** every economy service and number; EmpireConfig.QUESTS rewards; GameConfig.START_MONEY; CORE_SPEC
  targets; ShopConfig shares (until O1).
- **Save and network:** DATA_VERSION 6; the Remote list (no new remote).
- **Shop server:** ShopService receipt, pass and voucher logic; ShopDecor, VehicleService, MarketService investor hook,
  RecruitingService headhunter.
- **Other UI:** the company phone UI; the Talk/Interview/Assistant panels.
- **Ids:** every ShopConfig id stays 0 until the owner pastes real ones.

## 7. Open items and risks
1. Owner/lead: O1–O3, L1 (section 0.3).
2. Studio-only checks: T13.
3. The human timings and hint delays are estimates (A3.1). The only measured timing is the casual bot: first $ at 1:18
   (CORE_SPEC 1.2).
4. Risk: the lab package renames a button or changes the Review's primary states. T6 fails loudly.
5. Risk: on phones the toast lane overlaps the Menu sub-tabs (B3). It is acceptable if toasts do not sink input.
6. Risk: Roblox ships the ability-control jump button (y 233–305 on the preset). The HUD column cannot clear it in this
   layout; the fallback (row beside the panel) needs a new mockup (A2.1, T13).
7. Risk: the jump-button numbers come from a third-party mirror of the PlayerModule (version 0.742) and guiprev's
   iPhone insets. Both can differ on a real device (T13).
8. Not verified: Roblox refund rules (help centre blocked [R]); where a pass price is set (third-party guide only);
   that a gamepad-selected HUD button stops walking (A10).

## 8. Mockup and PNGs
`scratchpad/out/onboarding_design/mockup.html` is a click-through: 13 guide screens, 2 Menu, 4 Shop, iPhone/PC switch. A
"Design draft · example values" tag sits in the top-right corner, inside the Roblox top-bar strip. No game UI is under
the top bar (checked by script). Source and scripts: `scratchpad/agents/onboarding_design/build/` (`mockup.src.html`,
`build.js` with the font `scratchpad/out/lab_design/fonts_dl/figtree.woff2`, `shots.js`, `sizes.js`). Revision 1 is
kept in `scratchpad/onbcrit/backup/`.

Example values:
- the guided cash path of A3 ("Cash on this path"): $10,000 → $11,200 → $3,800 → $2,520 → $4,320 → $6,820 →
  Launch Day $5,000 campaign → $1,820 → Collect $3,000 → $4,820;
- the Studio's other numbers (cost $1,280, time 1:20, VRAM 4 of 6 GB, ~40.2, final 37.7–42.7, plan 2× Web Crawl
  Chunk + 2× Public Repos = 4B tokens, $7,400) come from the Lab renders (`out/lab/phone_08…`, `phone_09…`);
- rewards and shop texts come from the configs;
- Robux prices are the ShopConfig suggestions; the shop PNGs carry a note that this state needs the owner's ids
  (today the live shop says "Shop coming soon");
- Home's cash $5,128, users 26.8K and net +$55.5K/day are the casual bot at minute 5 (CORE_SPEC 1.2 run): rev
  3,368/min − cost 591/min, × 20 min per game day;
- grey bars are live values;
- the jump circle is the TouchJump layout of A2.1 (x 702–772, y 279–349);
- the font is Figtree, as a stand-in for BuilderSans.

Measured in the mockup (`sizes.js`, revision 2): smallest text 12.0 pt on every phone screen (12.3 pt in the HUD card),
every target ≥ 44 pt, nothing under the top bar, no chip over a button, HUD column bottom **265 pt** (guide) /
**267 pt** (hand-off), i.e. 13.5 / 11.6 pt above the jump button.

| PNG (844×390 @2x unless desktop, 1280×720 @2x) | Shows |
|---|---|
| phone_1_guide_greeting.png | step 1, first contact: greeting line, dim with the card hole, ring + chip on OPEN LAB, [Collect $1,200], cash $10K |
| phone_2_computer_highlight.png | step 1 after the dim, founder reward collected ($11.2K): gold Highlight on the founder computer, beam, billboard, instruction line |
| phone_3_studio_quickstart.png | step 2: Model Studio first-model Review, ring on `Primary` = BUY DATA PLAN · $7,400 during the dim, **no chip**; cash $11,200, cash after all $2,520 |
| phone_4_reveal_launch.png | step 4: reveal "Nova v1 · 40.5 · CHALLENGER", ring on LAUNCH › (no chip), cash $6,820 |
| phone_5_first_income.png | step 5: "First income!", burst from the cash ($1,820), [Collect $3,000] [GOT IT] |
| phone_6_guide_complete.png | hand-off: "GUIDE COMPLETE ✓", next goal "Sign your first client (CloudDesk)", toast, Menu + Shop buttons (note: the Shop button needs the owner's ids) |
| phone_7_menu_home.png | Menu → Home → Today with NEW pills, 3 cards (next goal line "Trust 0 %"), live strip |
| phone_8_shop.png | Shop: line, featured VIP Founder, passes (state after the owner adds ids) |
| phone_9_shop_owned.png | Shop with YOUR ITEMS (Headhunter voucher, VIP owned), featured Founder Suite |
| desktop_1_menu_home.png | Menu Home at 1280×720 with the Goals row |
| desktop_2_shop.png | Shop at 1280×720 |
