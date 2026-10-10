export const meta = {
  name: 'ai-empire-lab-redesign-design',
  description: 'Research how Roblox phone-maker and other product-creation games build their creation screen, then design a much better AI-model creation screen for AI Empire (3 competing designs, judged, final spec + phone-size mockups)',
  phases: [
    { title: 'Research', detail: 'Roblox phone-maker games, other creation-flow games, current code + constraints' },
    { title: 'Design', detail: 'three competing designs from different angles' },
    { title: 'Judge', detail: 'score and pick, graft best ideas' },
    { title: 'Spec', detail: 'final LAB_SPEC.md + HTML mockups rendered to PNG' },
    { title: 'Critique', detail: 'critic checks mockups/spec and fixes them' },
  ],
}
const ROOT = '/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad'
const CTX = `PROJECT: the Roblox game "AI Empire" (AI-company tycoon: you start in a garage, hire staff, buy GPUs, TRAIN and RELEASE your own AI models into product lines, earn money, grow to a huge HQ). Sources: ${ROOT}/work/src (Luau). Binding economy design: ${ROOT}/design/CORE_SPEC.md (section 7 = models). User wishes: ${ROOT}/LOGIC_BRIEF.md. The player is a German teenager who plays Roblox on an iPhone (Roblox on phones runs in LANDSCAPE, e.g. 844x390 points on an iPhone; also PC 1280x720+ and gamepad). In-game UI text is English.
THE USER'S NEW WISH (German, translated): "Make the screen where you create the AI much better. Look at Roblox games where you create phones (phone-maker / phone tycoon games), see how they are built, and do it in that kind of way."
The current creation screen is the "creator" view of ${ROOT}/work/src/StarterPlayer/StarterPlayerScripts/Client/UI/Apps/LabApp.module.luau (preview image: ${ROOT}/out/models/lab_rich_strip_creator.png and the other PNGs in ${ROOT}/out/models/ — LOOK at them with the Read tool): a form with model name, size segment (100M..7B), focus segment (Balanced/Coding/Reasoning/Creative), training budget segment, an "Expected result" panel with stat bars, training time/cost/VRAM/compute/data fill, START TRAINING, product lines list, Lab level card, ready-to-launch row with Refine/Release; then training / result / release views.
HONESTY RULES: never invent game names, features, numbers, Roblox APIs or asset ids. Every claim about an existing game needs a source URL you actually opened (or say "unverified"). Mark assumptions as assumptions. For web research use the WebSearch and WebFetch tools (if they are deferred, load them first with ToolSearch, query "select:WebSearch,WebFetch").`

const RESEARCH = { type: 'object', properties: {
  summary: { type: 'string' },
  findings: { type: 'array', items: { type: 'object', properties: {
    claim: { type: 'string' }, source: { type: 'string' }, confidence: { type: 'string', enum: ['verified', 'likely', 'unverified'] } },
    required: ['claim', 'source', 'confidence'] } },
  patterns_to_copy: { type: 'array', items: { type: 'string' } },
  pitfalls: { type: 'array', items: { type: 'string' } } },
  required: ['summary', 'findings', 'patterns_to_copy', 'pitfalls'] }

const R = [
  { key: 'roblox_phone', prompt: `${CTX}
YOUR JOB (research only, no file edits except notes in ${ROOT}/agents/lab_research/roblox_phone.md): find REAL Roblox games where players design/create phones (or similar products: laptops, cars, sneakers, games) and sell them — e.g. search for "Roblox phone tycoon", "Roblox smartphone tycoon", "Roblox make a phone", "Roblox phone company simulator", "Roblox create your own phone game", and also YouTube/wiki/DevForum pages about them. For each game you can verify: name, link, and HOW THE CREATION SCREEN WORKS: steps/order, component categories (screen, chip, battery, camera, design/colour…), how choices show cost and stats, live preview (3D model / card), naming, price setting, research/unlock tree for better parts, the release moment (reviews/score/sales reveal, celebration), how sales/history are shown, how it feels on mobile. Then distill the patterns that make these screens fun and clear, and the pitfalls (too many taps, unreadable on phones, pay-to-win).` },
  { key: 'creation_games', prompt: `${CTX}
YOUR JOB (research only, notes in ${ROOT}/agents/lab_research/creation_games.md): study creation flows of well-known product-making tycoon games outside Roblox and any AI-themed tycoon games (Roblox or not) — e.g. Game Dev Tycoon (topic/genre/platform choice, design-focus sliders, review score reveal), Mad Games Tycoon 2, Software Inc., Startup Company, mobile "Smartphone Tycoon" style games, and games about training AI models if any exist. Verify each with sources. Extract: how they turn a creation into a satisfying loop (meaningful trade-offs, visible preview that grows, the 'reveal' of the score/reviews, comparison with your last product and rivals, history shelf, unlocks), how they keep it simple for beginners and deep for veterans, and which patterns fit an AI-model creator (components like data, architecture size, training method, safety, personality, context length, modalities).` },
  { key: 'code', prompt: `${CTX}
YOUR JOB (read-only analysis, notes in ${ROOT}/agents/lab_research/code.md): read LabApp, ModelsUI, MarketApp, DataApp (datasets the player owns), Kit + Theme (UI components/conventions), Shared ModelConfig, ModelMath, PricingMath, Types, server AIModelService (+ the remotes it handles), CORE_SPEC section 7 and Appendix A, and the tool ${ROOT}/tools/guiprev/README.md. Report: (1) the exact current creation → training → result → release flow and its data (choices the server accepts, validation, what is saved per model); (2) which NEW player choices could be added WITHOUT touching balance (pure presentation, identity: icon/colour/mascot/personality used by the phone chat's system prompt, a visible 'model card', step-by-step staging of existing choices) vs which need ModelMath/AIModelService/ModelConfig changes and a re-run of the economy simulation (name the sim/tests that guard balance: tests/models, tests/econ, sim scripts); (3) concrete weaknesses of the current screen (look at the PNGs in ${ROOT}/out/models/: density, hierarchy, mobile landscape fit, missing feedback/excitement); (4) constraints for a rebuild (Kit components available, ScreenGui size rules, touch targets, guiprev preview workflow, tests that build the LabApp UI and must keep passing).` },
]
phase('Research')
const research = await parallel(R.map(r => () => agent(r.prompt, { label: `research:${r.key}`, phase: 'Research', schema: RESEARCH })))
const resText = R.map((r, i) => `=== RESEARCH ${r.key} ===\n${JSON.stringify(research[i], null, 1)}`).join('\n\n').slice(0, 60000)

const DESIGN = { type: 'object', properties: {
  title: { type: 'string' },
  pitch: { type: 'string' },
  flow: { type: 'array', items: { type: 'string' } },
  screens: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, layout_phone_landscape: { type: 'string' }, layout_desktop: { type: 'string' }, interactions: { type: 'string' } }, required: ['name', 'layout_phone_landscape', 'layout_desktop', 'interactions'] } },
  components: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, options: { type: 'string' }, effect_in_code: { type: 'string' }, balance_impact: { type: 'string' } }, required: ['name', 'options', 'effect_in_code', 'balance_impact'] } },
  server_changes: { type: 'array', items: { type: 'string' } },
  excitement_moments: { type: 'array', items: { type: 'string' } },
  risks: { type: 'array', items: { type: 'string' } },
  effort: { type: 'string' } },
  required: ['title', 'pitch', 'flow', 'screens', 'components', 'server_changes', 'excitement_moments', 'risks', 'effort'] }

const ANGLES = [
  { key: 'phone_maker', angle: 'PHONE-MAKER STYLE: stay as close as possible to how the Roblox phone-maker games build their creation screen (component categories as big tiles with icons, a live product preview that changes with every pick, cost/stat deltas on each option, name + look, then launch with a reveal). Translate every phone part into an AI-model part that maps to real game data.' },
  { key: 'safe_wizard', angle: 'LOW-RISK RESTAGING: keep the economy math exactly as it is (size, focus, budget, lines, refine, lab level, pricing) and only restage it: a short step wizard (e.g. Core → Skills → Identity → Train) with a growing live "model card" preview, big readable choices for phone landscape, clear before/after deltas vs your best model and rivals, and strong moments (training montage, score reveal, launch). Identity choices (icon, colour, personality for the phone AI chat) are presentation only.' },
  { key: 'depth', angle: 'DEPTH WITH REAL TRADE-OFFS: add 2–4 new meaningful components (e.g. dataset mix drawn from the datasets the player really owns, context length, safety/alignment level that affects reliability and churn, a personality that shapes the phone chat) with EXACT proposed formulas that plug into ModelMath/AIModelService, keep CORE_SPEC income targets intact (state how the sim must be re-run and what must stay equal), and keep beginners safe with a recommended preset.' },
]
phase('Design')
const designs = await parallel(ANGLES.map(a => () => agent(`${CTX}
RESEARCH RESULTS (from three researchers):
${resText}
YOUR JOB: design the new AI-model creation experience from this angle: ${a.angle}
It must be MUCH better than today for a teenager on an iPhone in landscape, while staying honest (every number comes from real game state) and buildable in Roblox Luau with the project's Kit/Theme UI (no invented APIs). Cover: the full flow from opening the Lab to a released model (creation, training, result/reveal, release/pricing), each screen's layout for phone landscape (844x390) and desktop, the component list with exact mapping to code, server changes, the excitement moments, risks, effort. Read the code yourself where needed (${ROOT}/work/src). No file edits except notes in ${ROOT}/agents/lab_design/${a.key}.md.`, { label: `design:${a.key}`, phase: 'Design', schema: DESIGN })))

const JUDGE = { type: 'object', properties: {
  scores: { type: 'array', items: { type: 'object', properties: { key: { type: 'string' }, wish_fit: { type: 'number' }, fun_clarity_mobile: { type: 'number' }, economy_safety: { type: 'number' }, buildability: { type: 'number' }, effort_risk: { type: 'number' }, notes: { type: 'string' } }, required: ['key', 'wish_fit', 'fun_clarity_mobile', 'economy_safety', 'buildability', 'effort_risk', 'notes'] } },
  winner: { type: 'string' },
  grafts: { type: 'array', items: { type: 'string' } },
  must_fix: { type: 'array', items: { type: 'string' } } },
  required: ['scores', 'winner', 'grafts', 'must_fix'] }
phase('Judge')
const dText = ANGLES.map((a, i) => `=== DESIGN ${a.key} ===\n${JSON.stringify(designs[i], null, 1)}`).join('\n\n').slice(0, 80000)
const judge = await agent(`${CTX}
Three competing designs for the new AI-model creation screen:
${dText}
Research summary: ${resText.slice(0, 15000)}
YOUR JOB: be a strict, independent judge. Verify claims against the code (${ROOT}/work/src) where a design says something maps to existing data. Score each design 1–10 on: wish_fit (feels like the Roblox phone-maker games the user means, clearly "much better"), fun_clarity_mobile (teenager on iPhone landscape: few taps, readable, exciting), economy_safety (CORE_SPEC income targets and balance stay intact or the plan to re-verify is concrete), buildability (Roblox/Luau/Kit, no invented APIs, testable with the mock + guiprev), effort_risk (higher = less effort/risk). Pick the winner, list ideas to graft from the others, and list must-fix problems of the winner.`, { label: 'judge', phase: 'Judge', schema: JUDGE })

phase('Spec')
const spec = await agent(`${CTX}
Designs: ${dText.slice(0, 50000)}
Judge verdict: ${JSON.stringify(judge, null, 1)}
YOUR JOB: write the FINAL binding spec ${ROOT}/design/LAB_SPEC.md for the builder (winner + grafts + must-fixes): flow, every screen with element list and sizes for phone landscape (844x390) and desktop (1280x720), components with exact effects (pointing at the code: ModelConfig/ModelMath/AIModelService/PricingMath fields), server/remote changes with validation, save compatibility (old models must load; no DATA_VERSION bump unless unavoidable — then the migration), balance guard (which tests/sims must stay equal), tests the builder must write, and what stays unchanged (product lines, refine, lab level, pricing, release into a live line, MarketApp). Then build a CLICK-THROUGH HTML MOCKUP of the main screens (dark theme like the game's Theme colours in Theme.module.luau; English UI; realistic values taken from the game's config, labelled as example values) at ${ROOT}/out/lab_design/mockup.html and RENDER PNGs with Playwright for Node (it is installed globally: run node with NODE_PATH="$(npm root -g)" and require('playwright'); launch chromium with executablePath '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' if the default lookup fails — check the actual binary path with ls): one PNG per main screen at 844x390 (iPhone landscape, deviceScaleFactor 2) named ${ROOT}/out/lab_design/phone_<n>_<screen>.png and two at 1280x720 named desktop_<n>_<screen>.png. LOOK at every PNG and iterate until it is clean, readable at phone size, and attractive. The mockup is a design draft, not the game — put a small "Design draft" tag in a corner. Final message: spec summary (10–15 lines) + list of PNG paths.`, { label: 'spec+mockup', phase: 'Spec' })

phase('Critique')
const critique = await agent(`${CTX}
A designer wrote ${ROOT}/design/LAB_SPEC.md and mockups in ${ROOT}/out/lab_design/ (mockup.html + PNGs). Their summary: ${String(spec).slice(0, 4000)}
YOUR JOB: be a tough critic, then FIX what you find directly in LAB_SPEC.md and mockup.html (re-render the PNGs the same way, LOOK again). Check: (1) does it really feel like the phone-maker games (component tiles, live preview, reveal) and clearly better than ${ROOT}/out/models/lab_rich_strip_creator.png? (2) iPhone landscape 844x390: text size (nothing below ~12 pt equivalent), touch targets ≥ 44 pt, number of taps from "open Lab" to "Start training" (aim ≤ 4 for the recommended path), nothing hidden behind the Roblox top bar (keep ~40 pt free at the top) or the joystick/jump areas when the app is open? (3) every number traceable to real game data per the spec; (4) economy: spec keeps CORE_SPEC income targets or defines a concrete re-verification; (5) buildability with Kit/Theme and no invented Roblox APIs; (6) save compatibility. Final message: list of problems found and what you changed, plus the final PNG paths.`, { label: 'critique', phase: 'Critique' })
return { research, designs, judge, spec, critique }
