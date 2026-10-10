export const meta = {
  name: 'ai-empire-design-core',
  description: 'Judge panel: 3 independent core-loop/economy designs (each verified in the economy simulator), 2 judges, 1 synthesis into CORE_SPEC.md',
  phases: [
    { title: 'Design', detail: '3 independent core designs with simulator evidence' },
    { title: 'Judge', detail: '2 independent judges score all designs' },
    { title: 'Synthesize', detail: 'final CORE_SPEC.md, re-verified in the simulator' },
  ],
}
const ROOT = '/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad'
const BASE = `You are a senior game designer + Luau engineer on the Roblox game "AI Empire" (AI-company tycoon). READ FIRST, completely: ${ROOT}/LOGIC_BRIEF.md (user requests, decisions, constraints, root causes, targets) and ALL analysis reports in ${ROOT}/agents/logic_understand/reports/ (economy, time_staff, vehicles, contracts_customers, data_ui, models, staff_life, hotel_site, monetization, world_map, building_meaning; props_animation/npc_actions may appear later — not needed for the core). Game sources: ${ROOT}/work/src (read the real code for any formula you change: EmpireConfig, EmpireMath, WorkforceMath, MarketConfig, MarketMath, MarketService, NPCService, ModelConfig, ModelMath, AIModelService, EmpireService, HardwareConfig, DataConfig, CampusConfig, StaffService, EmployeeConfig, BuildingPlan). Never modify ${ROOT}/work or ${ROOT}/src.
ECONOMY SIMULATOR (mandatory evidence): ${ROOT}/agents/logic_understand/economy/ contains sim.luau (loads the REAL game services in the headless mock and plays a greedy bot; usage in its header: tools/luau sim.luau -a [--profile default|opt] [--minutes N] [--patch name]... [--hire none|balanced|smart] [--late minutes] [--refine n]), patches.luau (name → in-memory find/replace patches on the real sources), runset.sh, and earlier outputs out_*.txt. Copy the whole folder to your own scratch dir (given below) and work ONLY there; adjust the relative paths (the sim requires ../../../tools/luau and the harness/gen dirs — check sim.luau's paths and fix them for your copy's location, or keep the copy at the same depth: ${ROOT}/agents/<yourdir>/economy/). Express your numeric changes as patches (or as small new Luau logic injected via patches) so the bot plays YOUR economy, and report the money curve (money, revenue/min, cost/min, staff, office, best model, NPC best) at minutes 0,5,10,20,30,45,60,90,120,180 for (a) the casual profile, (b) the opt profile, (c) joining a server that is already 60 min old (--late 60). If a mechanic cannot be simulated (e.g. trips/hotel), model its cash flow as an injected income/cost term and say so. Never invent results; if a run fails, report it.
Your design document must contain, with exact numbers and the code hooks (file:function) for each:
1. Core loop in one paragraph a 13-year-old understands, plus the first-10-minutes walkthrough (what the player sees/does minute by minute, when the first $ comes in).
2. Office stages: the NEW very small first stage (garage / tiny office: who fits, what's there, what the plot around it looks like) + the existing 4 HQ tiers; price, staff cap, what each stage UNLOCKS in gameplay (departments, revenue streams, GPU slots, hotel, fleet...), migration of old saves (office index +1).
3. Income sources and their formulas (fixed consumer market incl. the NPC-rival fix and anti-clone rule; B2B customer deals with sales pipeline → on-site trips → monthly retainers; contracts/pilots; studio; guest-house revenue if any; retail), each with its share of income at minutes 10/60/180 in your sim.
4. Costs and their formulas (wages with working-hours logic, hiring fees (reduce?), paid vacation, fleet leases for field staff + boss, trip costs: fuel/flight/hotel nights, cafeteria food, guest-house running cost, utilities/power, rent per stage?), with share of costs.
5. Staff/department production model: per-department output O_d = f(productive staff in that department's seats × skill × morale × room quality); identical formula whether watched or not (expected value from the shift calendar offscreen); night = off-duty except optional night shift; vacation days per employee (automatic HR planning, max share absent); sick days?; morale from lunch served by the chef + wellness; how ops staff (reception, chef, barista, security, cleaners…) become paid jobs with a real function; what each department produces (map every room kind).
6. Calendar: one saved game calendar (day = 1200 s; vacation, trips, hotel nights, payroll, retainers in game days; relation to GAME_MONTH_SECONDS and real-day contracts).
7. AI models: several live models made meaningful (product lines/segments, company nest or other anti-clone rule, parallel training slots from engineering capacity, versions replacing predecessors with user migration, ageing, refinement fixed and capped, ONE training per slot).
8. Automation: what runs automatically (HR, sales, trips, vacation, purchasing?) and what the player decides; how the assistant explains it.
9. Targets check: show from your sim runs that the brief's targets are met (or how close), incl. office stage times, $/min by minute 5/10, wage share in mid game, no collapse/no runaway, late joiner OK.
10. Risks and what you'd cut first if time runs out.
Write the document to the path given below (markdown, as long as needed but no fluff), and return a short summary (≤ 250 words) with the path and the key numbers.`
const DESIGNERS = [
  { key: 'realism', dir: 'design_realism', lens: 'LENS: "REAL STARTUP SIMULATION". Prioritise believability: departments that work like a real AI startup, real HR (shifts, vacation, sick days), real sales pipeline and field trips, real costs (rent, leases, hotel). Keep it automatic (the user chose that) and keep the numbers fun.' },
  { key: 'clarity', dir: 'design_clarity', lens: 'LENS: "PLAYER CLARITY & FUN". Prioritise a clear, satisfying progression for a Roblox player (13+): obvious next goal, visible growth, satisfying numbers, every system visible on screens/in the app, nothing confusing; simplify realistic mechanics where they would confuse. Keep everything the user asked for present at least in a simple form.' },
  { key: 'robust', dir: 'design_robust', lens: 'LENS: "ECONOMY ROBUSTNESS". Prioritise a bounded, exploit-free, multiplayer-fair economy: no collapse, no runaway, no clone stacking, no watched-vs-unwatched difference, late joiners fine, every new cost/income sized after the market fix, few parameters that are easy to tune. Still deliver every user-requested mechanic.' },
]
phase('Design')
const designs = await parallel(DESIGNERS.map(d => () => agent(`${BASE}
${d.lens}
Your scratch dir: ${ROOT}/agents/${d.dir}/ (create it; copy the economy simulator into ${ROOT}/agents/${d.dir}/economy/). Write your design to ${ROOT}/design/core_${d.key}.md (create ${ROOT}/design/).`, { label: `design:${d.key}`, phase: 'Design' }).then(r => ({ key: d.key, summary: r }))))
const ok = designs.filter(Boolean)
log(`designs finished: ${ok.map(d => d.key).join(', ')}`)
const JUDGE_SCHEMA = {
  type: 'object',
  properties: {
    scores: { type: 'array', items: { type: 'object', properties: {
      design: { type: 'string' }, fidelity: { type: 'number' }, coherence: { type: 'number' }, economy_evidence: { type: 'number' },
      implementability: { type: 'number' }, automation: { type: 'number' }, total: { type: 'number' }, strengths: { type: 'string' }, weaknesses: { type: 'string' } },
      required: ['design', 'fidelity', 'coherence', 'economy_evidence', 'implementability', 'automation', 'total', 'strengths', 'weaknesses'] } },
    winner: { type: 'string' },
    grafts: { type: 'array', items: { type: 'string' } },
    must_fix: { type: 'array', items: { type: 'string' } },
  },
  required: ['scores', 'winner', 'grafts', 'must_fix'],
}
phase('Judge')
const JUDGE_LENS = [
  'You judge as the USER: a German teenager who wants the game to feel like a real AI startup, earn more money early, start very small, everything automatic, lots of life in the building. Would he be happy? Would it make sense to him?',
  'You judge as a SKEPTICAL LEAD ENGINEER: are the numbers really backed by the simulator outputs (open the out files in the designers\' dirs and check), is it implementable in this codebase within the constraints (one place file, save compatibility, performance, no invented APIs/ids), are there exploits, contradictions or hidden runaway/collapse?',
]
const judgements = await parallel(JUDGE_LENS.map((lens, i) => () => agent(`${BASE}
You are JUDGE ${i + 1}. ${lens}
Read the three designs: ${ROOT}/design/core_realism.md, ${ROOT}/design/core_clarity.md, ${ROOT}/design/core_robust.md (some may be missing if a designer failed — score only existing ones) and inspect their simulator evidence in ${ROOT}/agents/design_*/economy/. Score each 0-10 on fidelity (to the user's requests and decisions), coherence (everything makes sense together), economy_evidence (targets met per actual sim outputs), implementability (codebase + constraints), automation (matches "almost everything automatic"); total = weighted (fidelity 0.25, coherence 0.2, economy_evidence 0.25, implementability 0.2, automation 0.1). Pick a winner, list concrete grafts from the runners-up worth adopting, and list must_fix problems (in any design, incl. the winner).`, { label: `judge:${i + 1}`, phase: 'Judge', schema: JUDGE_SCHEMA })))
const js = judgements.filter(Boolean)
phase('Synthesize')
const synth = await agent(`${BASE}
You are the SYNTHESIZER. Inputs: the three designs (${ROOT}/design/core_*.md), their simulator folders (${ROOT}/agents/design_*/economy/), and the judges' verdicts:
${JSON.stringify(js, null, 1)}
Produce ${ROOT}/design/CORE_SPEC.md: the final core design, starting from the judges' winner (by combined total; break ties toward the engineer judge), adopting the listed grafts where they do not conflict, and fixing every must_fix item. It must be complete and implementable: exact formulas, constants, data fields (with defaults + migration), hooks (file:function), the office-stage table incl. the new first stage, income/cost tables, department production table (every room kind), calendar, model-portfolio rules, automation rules, and the first-10-minutes walkthrough. Then VERIFY: build the final patch set in your own copy ${ROOT}/agents/design_final/economy/ and run casual, opt and --late 60 for 180 min; paste the money-curve tables and check every brief target (state clearly which are met / missed and by how much). Also add a section "Interfaces for subsystem designers" listing the exact numbers/functions the subsystem specs (calendar/HR, customers+trips+fleet+hotel costs, guest house, world map city/airport/abroad, staff life/chef/talk/animation, models, shop, tech/network/save) must use, so they stay consistent. Return a ≤300-word summary with the key numbers and target results.`, { label: 'synthesize', phase: 'Synthesize' })
return { designs: ok, judgements: js, synthesis: synth }
