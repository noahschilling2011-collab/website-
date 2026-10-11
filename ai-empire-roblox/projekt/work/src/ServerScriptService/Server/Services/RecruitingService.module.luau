--!strict
-- Recruiting: job applications arrive over time, the founder invites candidates to the visitor lounge,
-- interviews them in person and hires them with a persistent identity.
--
-- The interview is an AUTHORED dialogue system, not a language model: every answer is composed from
-- templates chosen by the candidate's hidden skill tier (low k<=2 / mid k=3 / high k>=4) and
-- temperament (nervous/confident, candid/overselling) and filled with their experience, previous
-- employer, specialty and the founder's company name. Everything is deterministic per applicant
-- (hash of owner + serial), so a reopened interview shows the same transcript.
--
-- Data (data.empire, replicated with the snapshot): applicants = {Applicant} (<= EmpireMath.MAX_APPLICANTS)
--   {id, serial, role, n = name, s = appearance seed, xp = years, prev = previous employer, spec = specialty,
--    ask = salary multiplier 0.8..1.5, at = created (empire.seconds, play time), st = new|invited|interviewing,
--    q = asked question ids, r = chosen reply to the candidate's question, low = a low offer was declined}
-- Hidden traits (true skill k, confidence, candour) are derived on the server from (owner, serial) and are
-- never stored or replicated; the founder sees an estimated range that narrows with every answer. After
-- hiring the skill becomes the staff profile {n, s, k, w = salary multiplier} (stars on the team list).
--
-- tick (simulate loop, 1 s): repairs staff profiles, expires applications nobody invited after EXPIRE s of
-- play time, and while staff < office cap and fewer than MAX_APPLICANTS are open, one arrives every
-- ARRIVAL s (Random seeded per session). RecruitAction invite → a visitor rig (folder Office.Visitors)
-- walks from the plaza through the automatic entrance to a seat in the visitor lounge G_VISITOR (the
-- route comes from BuildingPlan.visitorRoute(tier): in the garage stage, plan tier 0, applicants wait
-- on the porch benches in front of the garage and a hire leaves at its side door).
-- Navigation is EmployeeNavigation with role "visitor" (public rooms only); BuildingPlan classes the
-- plaza outside the envelope as "staff", so the plaza <-> entrance recess stretch is a direct Humanoid
-- walk. The visitor's ProximityPrompt "Interview" (owner only) opens the conversation (Notify
-- INTERVIEW_OPEN); hire sends the visitor to the speed gates, where the new employee's staff rig takes over
-- (StaffService.expectArrival / handoverArrival: first day through reception); reject sends the visitor back
-- to the plaza, where the rig is removed.
-- Shop: the "headhunter" voucher (ShopService.setRedeemHandler) adds one top candidate (hidden skill >= 4) to
-- the applications; it is refused (voucher kept) while the company has no desk or application slot free.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Prompts=game:GetService("ProximityPromptService")
local EmpireConfig=require(ReplicatedStorage.Shared.Config.EmpireConfig)
local EmployeeConfig=require(ReplicatedStorage.Shared.Config.EmployeeConfig)
local GameConfig=require(ReplicatedStorage.Shared.Config.GameConfig)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local EmpireMath=require(ReplicatedStorage.Shared.EmpireMath)
local Format=require(ReplicatedStorage.Shared.Format)
local Remote=require(script.Parent.Parent.Lib.Remote)
local Guard=require(script.Parent.Parent.Lib.Guard)
local Session=require(script.Parent.SessionService)
local Economy=require(script.Parent.EconomyService)
local Plot=require(script.Parent.PlotService)
local Rig=require(script.Parent.EmployeeRigDesign)
local Nav=require(script.Parent.EmployeeNavigation)
local Doors=require(script.Parent.DoorService)
local Workstations=require(script.Parent.WorkstationService)
local Staff=require(script.Parent.StaffService)
local Shop=require(script.Parent.ShopService)
local Recruiting={}
Recruiting.ARRIVAL={90,180} -- seconds between applications
Recruiting.EXPIRE=EmpireMath.APPLICATION_SECONDS -- an application nobody invited stays open for 30 minutes of play time
Recruiting.MAX_QUESTIONS=7
Recruiting.LOW_OFFER=0.85 -- "offer less" multiplier on the salary ask

export type Person={k: number,confidence: number,candour: number,role: string,xp: number,prev: string,spec: string,n: string,ask: number,serial: number}

-- Deterministic hashing ---------------------------------------------------------------------------
local function stream(seed: number): (number)->number
 local state=EmployeeConfig.hash(seed)
 return function(n: number): number
  state=(state+0x9e3779b9)%4294967296
  return EmployeeConfig.hash(state)%n+1
 end
end
local function unit(pick: (number)->number): number return (pick(10001)-1)/10000 end
local function choose<T>(pick: (number)->number,list: {T}): T return list[pick(#list)] end
local function textHash(text: string): number
 local h=0;for i=1,#text do h=(h*31+string.byte(text,i))%4294967296 end;return h
end
local function ownerBase(owner: number,salt: number): number
 return EmployeeConfig.hash(math.floor(math.abs(owner))%4294967296+salt)
end
-- Hidden traits of an applicant (server only).
function Recruiting.traits(owner: number,serial: number): {k: number,confidence: number,candour: number}
 local pick=stream((ownerBase(owner,0x2545f491)+serial*0x632be5ab)%4294967296)
 local roll=pick(100)
 local k=if roll<=8 then 1 elseif roll<=30 then 2 elseif roll<=70 then 3 elseif roll<=92 then 4 else 5
 return {k=k,confidence=unit(pick),candour=unit(pick)}
end
function Recruiting.person(owner: number,a: any): Person
 local t=Recruiting.traits(owner,a.serial)
 return {k=t.k,confidence=t.confidence,candour=t.candour,role=a.role,xp=a.xp,prev=a.prev,spec=a.spec,n=a.n,ask=a.ask,serial=a.serial}
end

-- Applicant generation ----------------------------------------------------------------------------
local EMPLOYERS={"Bluepeak Software","Harborlight Analytics","Cedar & Finch Consulting","Helixa Robotics","Lumen Fieldworks","Ironbridge Systems",
 "Saffron Pixel Games","Polar Grove Insights","Brightmoor Media","Meridale Health Tech","Kestrel Freight Logistics","Riverstone Credit Union",
 "Quillfeather Publishing","Copperleaf Energy","Tidewater Retail Group","Orchard Lane Labs"}
local FIRST_JOBS={"a university research group","a two-person startup","a student research project"}
local SPECIALTIES: {[string]:{string}}={
 researcher={"reinforcement learning","evaluation and benchmarks","efficient architectures","interpretability","multilingual models","reasoning and maths"},
 engineer={"distributed training","GPU performance","inference serving","ML tooling","large-scale data pipelines","model compression"},
 curator={"deduplication and filtering","code datasets","multilingual text","labelling programmes","data provenance","synthetic data"},
 marketer={"developer marketing","pricing and packaging","enterprise sales","community launches","growth analytics","partnerships"},
}
local function roleDef(id: string): any return EmpireConfig.find(EmpireConfig.ROLES,id) end
local function roundAsk(x: number): number return math.floor(math.clamp(x,0.8,1.5)*100+.5)/100 end
-- New applicant: identity from EmpireMath.nextIdentity (advances hireSerial), role weighted toward the
-- roles with the fewest people (team + open applications), skill-correlated experience and salary ask.
function Recruiting.generate(e: any,owner: number,now: number): any
 local name,seed,serial=EmpireMath.nextIdentity(e,owner)
 local t=Recruiting.traits(owner,serial)
 local pick=stream((ownerBase(owner,0x68e31da4)+serial*0x1b873593)%4294967296)
 local counts: {[string]:number}={};local most=0
 for _,role in EmpireConfig.ROLES do counts[role.id]=e.employees[role.id] or 0 end
 for _,a in e.applicants do if counts[a.role] then counts[a.role]+=1 end end
 for _,n in counts do most=math.max(most,n) end
 local total=0;for _,role in EmpireConfig.ROLES do total+=most-counts[role.id]+1 end
 local roll=pick(total);local role=EmpireConfig.ROLES[1].id
 for _,def in EmpireConfig.ROLES do roll-=most-counts[def.id]+1;if roll<=0 then role=def.id;break end end
 local xp=math.max(0,math.floor((t.k-1)*2.4+unit(pick)*4.5-.5))
 local prev=if xp<=1 then choose(pick,FIRST_JOBS) else choose(pick,EMPLOYERS)
 local spec=choose(pick,SPECIALTIES[role])
 local ask=0.8+(t.k-1)*0.15+(unit(pick)-.4)*0.16+(if t.candour<.35 then .08 else 0)+(if t.confidence>.65 then .04 else 0)
 return {id="A"..tostring(serial),serial=serial,role=role,n=name,s=seed,xp=xp,prev=prev,spec=spec,ask=roundAsk(ask),at=now,st="new",q={}}
end
-- Same escalating base as an agency hire (EmpireMath.hireCost), so recruiting is never a cheaper
-- loophole at scale; the candidate's salary ask scales it.
function Recruiting.hireCost(roleId: string,mult: number,e: any?): number
 local def=roleDef(roleId)
 local base=if e then EmpireMath.hireCost(e,def) else def.price
 return math.floor(base*mult+.5)
end
function Recruiting.wage(roleId: string,mult: number): number
 return roleDef(roleId).wage*mult
end

-- Question bank -----------------------------------------------------------------------------------
type Question={id: string,text: string,kind: string,topic: string?,high: string?,mid: string?}
local GENERIC: {Question}={
 {id="background",text="Walk me through your background.",kind="general"},
 {id="why",text="Why do you want to join {company}?",kind="general"},
 {id="failure",text="Tell me about a project that failed.",kind="general"},
 {id="pressure",text="How do you work under pressure?",kind="general"},
 {id="team",text="How do you handle a disagreement with a colleague?",kind="general"},
 {id="strength",text="What's your biggest strength?",kind="general"},
 {id="weakness",text="What's a weakness you're working on?",kind="general"},
 {id="learning",text="How do you keep up with a field that moves this fast?",kind="general"},
 {id="proud",text="What work are you most proud of?",kind="general"},
 {id="salary",text="What are your salary expectations?",kind="general"},
 {id="start",text="When could you start?",kind="general"},
 {id="questions",text="Do you have any questions for us?",kind="general"},
}
local TECHNICAL: {[string]:{Question}}={
 researcher={
  {id="r_idea",kind="technical",topic="research prioritisation",text="How do you decide whether a research idea is worth a week of compute?",
   high="I write down the hypothesis and the result that would kill it, then run the smallest experiment that can falsify it: a small model, a fixed seed budget and a strong, properly tuned baseline. Only if it beats that baseline by more than the seed noise does it get the full week.",
   mid="I'd check the literature first, then try it on a small model and compare it against our current baseline before asking for a full run."},
  {id="r_eval",kind="technical",topic="evaluation design",text="How would you design an evaluation for a new reasoning model?",
   high="Held-out problems written after the training cut-off so nothing can leak, several difficulty levels, exact-match scoring plus checks on the intermediate steps, multiple samples per problem to measure variance, and a human-graded slice to make sure the metric tracks what users actually need.",
   mid="I'd build a test set of reasoning problems with known answers, keep it separate from the training data and report accuracy next to a few baselines."},
  {id="r_jump",kind="technical",topic="benchmark anomalies",text="A benchmark score jumps 15 points overnight. What do you check first?",
   high="Contamination first: search the training data for the test items and near-duplicates. Then confirm the evaluation code didn't change, re-run with different seeds, and look at which items flipped. A real gain is spread across the benchmark; a leak is concentrated.",
   mid="I'd make sure the test data didn't leak into the training set and re-run the benchmark to confirm the result."},
  {id="r_ablate",kind="technical",topic="ablation studies",text="How do you structure ablations for a new training trick?",
   high="One change at a time against a fixed baseline, at least three seeds each, the same compute budget, and I decide in advance which metric settles it. Then I also remove components from the full recipe, because tricks often only work in combination.",
   mid="Change one thing at a time, keep everything else fixed and compare it against the baseline."},
  {id="r_paper",kind="technical",topic="paper triage",text="How do you decide whether a new paper is useful for us?",
   high="I check whether the baselines were tuned properly, whether the gain survives at our scale and with our data, and how much compute the comparison used. Then I reproduce the core claim on a small budget before anyone plans around it.",
   mid="I look at the results tables, check whether the setup is similar to ours and try the idea if it looks promising."},
 },
 engineer={
  {id="e_diverge",kind="technical",topic="training instabilities",text="Training loss suddenly diverges at step 40,000. Walk me through debugging it.",
   high="Roll back to the last good checkpoint and replay with the same data order. Look at the learning-rate schedule, gradient norms and loss scaling just before the spike, and check the data shard around that step. Typical fixes: a lower peak learning rate, gradient clipping, skipping the bad batch, and an alert so we catch it earlier next time.",
   mid="I'd go back to an earlier checkpoint, lower the learning rate and check whether some bad data caused the spike."},
  {id="e_gpu",kind="technical",topic="GPU utilisation",text="Our GPUs sit at 45% utilisation during training. Where do you look?",
   high="I profile a single step. At 45% it's usually the input pipeline or communication: prefetch and pack the data, add loader workers, overlap the gradient all-reduce with compute, raise the micro-batch until memory is full, and use mixed precision with fused kernels.",
   mid="I'd check whether data loading is too slow and try a bigger batch size so the GPUs have more work."},
  {id="e_scale",kind="technical",topic="distributed training",text="How would you scale training from one machine to a cluster?",
   high="Start with data parallelism and sharded optimiser states, and add tensor or pipeline parallelism only when the model no longer fits. Keep the global batch and learning rate consistent, measure the network bandwidth first, and make every job restartable from checkpoints.",
   mid="Use data-parallel training across the machines, make sure the network is fast enough and adjust the batch size."},
  {id="e_serve",kind="technical",topic="inference cost",text="How do you cut inference cost without hurting quality?",
   high="Measure where the cost goes first. Then quantise the weights to 8 or 4 bits behind an evaluation gate, batch requests continuously, cache repeated prompts, and route easy traffic to a smaller distilled model, each step checked against our quality suite.",
   mid="Quantisation and batching requests together usually help. I'd check the quality afterwards."},
  {id="e_checkpoint",kind="technical",topic="checkpointing",text="What's your checkpointing and recovery strategy for long runs?",
   high="Asynchronous checkpoints every 30 to 60 minutes including optimiser and data-loader state, two copies on different storage, automatic restarts on node failure, and a regular restore drill. A checkpoint you have never restored is just a hope.",
   mid="Save checkpoints regularly with the optimiser state, keep a few older ones and test that a restart works."},
 },
 curator={
  {id="c_quality",kind="technical",topic="data quality",text="How do you measure data quality?",
   high="In layers: cheap heuristics for length, language and symbol ratios; a small quality classifier trained on hand-rated samples; perplexity filtering against a reference model; and finally the real test: train small models on each variant and compare their downstream scores.",
   mid="I'd use filters for language and length, read random samples by hand and remove the obvious spam."},
  {id="c_dedup",kind="technical",topic="deduplication",text="How would you deduplicate a two-trillion-token web crawl?",
   high="Exact duplicates first, with hashes of normalised text; then near-duplicates with MinHash and locality-sensitive hashing at document level, sharded so it scales. Afterwards I'd check our test sets against the result to avoid contamination.",
   mid="Remove exact duplicates with hashes, and use a similarity method for the near-duplicates."},
  {id="c_mix",kind="technical",topic="data mixes",text="How do you choose the data mix for a coding-focused model?",
   high="Start from a baseline mix and train small proxy models with different code shares, say 20, 35 and 50 percent, while keeping natural language and maths so reasoning doesn't collapse. Weight high-quality repositories up, deduplicate forks, and pick the mix by downstream coding and general scores.",
   mid="More code data, but still some general text, with a focus on good repositories."},
  {id="c_license",kind="technical",topic="licensing and personal data",text="How do you handle licensing and personal data in scraped text?",
   high="Respect opt-outs and crawler rules, keep provenance for every document, filter by licence, and scrub personal data with detectors plus manual audits on samples. Everything documented, so we can answer customers and regulators.",
   mid="I'd filter out personal data, avoid sites that don't allow scraping and keep track of the sources."},
  {id="c_labels",kind="technical",topic="labelling projects",text="How do you run a labelling project people can trust?",
   high="Clear written guidelines with examples, a pilot round to remove ambiguities, gold questions mixed in to measure every labeller, overlapping items to compute agreement, and fair pay, because rushed labellers produce noisy labels.",
   mid="Write good instructions, check samples of the work and remove labellers who make many mistakes."},
 },
 marketer={
  {id="m_price",kind="technical",topic="API pricing",text="How would you price our API against much bigger competitors?",
   high="Not on list price alone. Find a segment where our model is clearly good enough, price slightly under the big players there, and add a free tier with an obvious upgrade trigger. Then track conversion and gross margin per customer and adjust every month.",
   mid="Price it a bit below the competition and offer a free trial so people can test it."},
  {id="m_launch",kind="technical",topic="launch plans",text="Outline a launch plan for our next model.",
   high="Two weeks before: a private beta with ten design partners and their quotes. Launch day: a demo of the one thing we do better, honest benchmarks, docs and pricing live. Afterwards: weekly case studies and a fast feedback loop into the product team.",
   mid="Announce it on social media, write a blog post, maybe hold a launch event and give early users a discount."},
  {id="m_churn",kind="technical",topic="churn",text="Subscribers cancel after the first month. What do you do?",
   high="Interview the people who left and compare them with what successful users did in their first week. Usually the fix is onboarding: get people to their first real result faster. Then annual plans and usage nudges for the ones who drift.",
   mid="Send reminder emails, offer a discount to stay and ask people why they left."},
  {id="m_position",kind="technical",topic="positioning",text="How do we stand out when everyone claims to have the best model?",
   high="Pick one job we do better than anyone for one specific audience, prove it with their own examples instead of generic benchmarks, and repeat that message everywhere for a year.",
   mid="Focus on what makes us different, like price or a special feature, and talk about it a lot."},
  {id="m_metrics",kind="technical",topic="growth metrics",text="Which numbers would you look at every morning?",
   high="New sign-ups, activation in the first day, paid conversion, revenue per user, churn and serving cost per user. Together they show growth and whether every user actually makes us money.",
   mid="Users, revenue and how many people cancel."},
 },
}
-- Generic answers by the tier the candidate PRESENTS (overselling candidates present one tier higher).
local GENERIC_ANSWERS: {[string]:{[string]:{string}}}={
 background={
  low={"I've been working for {years}, most recently at {prev}. I did a bit of everything there, mostly support work around {spec}.","I spent {years} at {prev}. It was my first real role in the field, and I picked up the basics of {spec} along the way."},
  mid={"I've spent {years} in the field, the last stretch at {prev}, where I focused on {spec}. I owned a few projects end to end and worked closely with the product team.","{Years} in total. At {prev} I was the go-to person for {spec}, and I helped set up the team's review process."},
  high={"I have {years} of experience. At {prev} I led the {spec} work: I set the technical direction, hired two people and shipped the system that is still in production.","{Years}, most of it hands-on. At {prev} I built the {spec} stack from scratch and mentored the junior team. The results are in our public release notes."},
 },
 why={
  low={"I've heard AI is where everything is going, and {company} seems like an exciting place. I want to learn.","The job post looked interesting, and I need a new challenge after {prev}."},
  mid={"I've followed what {company} is doing with its models, and I like that a small team still ships real products. I think my {spec} experience fits.","{company} is at the stage where one person can still change a lot. That's what I'm looking for after {prev}."},
  high={"Because {company} trains its own models instead of wrapping someone else's API. With my {spec} background I can make your next generation measurably better, and I already have ideas for the first three months.","I want ownership. At {prev} the big decisions were made far away; here I can build the {spec} side properly and see the impact in the numbers."},
 },
 failure={
  low={"Hmm... I can't really think of a failure. Most things went fine.","Once a deadline slipped because the requirements changed. It wasn't really my fault, though."},
  mid={"We once launched a feature at {prev} without enough testing and had to roll it back. Since then I insist on a staged rollout and a checklist.","A project I ran took twice as long as planned because I underestimated the data cleaning. Now I estimate that part first."},
  high={"At {prev} I pushed a {spec} redesign that looked great offline but lost users in production. I ran the post-mortem myself: our evaluation didn't match real usage. We rebuilt it from live traffic, and the second version clearly beat the old system.","I once spent six weeks on an approach that a two-day experiment could have ruled out. Since then every idea gets a cheap kill test first, and I write down in advance which result would make me stop."},
 },
 pressure={
  low={"I just work harder and stay late if I have to.","I try not to panic. Usually it works out."},
  mid={"I split the work into what must ship and what can wait, tell people early what slips, and stay on the critical path.","I make a short list, cut scope early and keep everyone updated so there are no surprises."},
  high={"I get calmer, honestly. First I find out what actually matters for the deadline, then I cut everything else and say so openly. That's how we shipped a release at {prev} during a hardware outage.","Pressure is mostly a prioritisation problem. I write down the three things that must be true at the deadline, protect the team's focus and give stakeholders an honest status twice a day."},
 },
 team={
  low={"I usually just go along with what the others want.","I try to avoid arguments if I can."},
  mid={"I try to understand their reasoning first, then propose a small experiment so the data decides.","I talk to them directly instead of over chat, and if we can't agree we ask the lead to decide and move on."},
  high={"I separate the person from the idea, write down both options with their risks and agree on what evidence would settle it. Then whoever was wrong commits fully, and sometimes that's me.","Disagreement is useful if it's fast. I ask what would change their mind, share what would change mine, and we run the cheapest test that answers it."},
 },
 strength={
  low={"I'm a hard worker and a fast learner.","I'm very motivated and I get along with everyone."},
  mid={"I'm reliable. If I say something will be ready on Friday, it's ready on Friday, and I'm good at {spec}.","I'm good at turning vague requests into concrete tasks, especially around {spec}."},
  high={"Depth in {spec}, combined with judgement about what not to build. I've saved teams months by stopping the wrong projects early.","I make other people faster. At {prev} I built the tools and reviews that let the whole team ship {spec} work twice as often."},
 },
 weakness={
  low={"I'm a perfectionist.","Maybe that I work too hard sometimes."},
  mid={"I sometimes take on too much myself instead of delegating. I've started blocking time for reviews so others can take over.","Public speaking. I've been presenting our results every month to get better at it."},
  high={"I can be impatient with slow processes. I've learned to ask why a process exists before I try to remove it.","I tend to go deep before going wide. Now I timebox exploration and share early drafts, even rough ones."},
 },
 learning={
  low={"I watch videos and follow some accounts online.","I read the news when I have time."},
  mid={"I read a few papers a week, try the interesting ones on small problems and share notes with my team.","I keep a reading list, reproduce one result a month and follow the main conferences."},
  high={"I reproduce the papers that matter for {spec} on a small budget before believing them, and I keep a short digest for my team. Most hype dies on reproduction.","I read primary sources rather than threads and run small ablations myself. I also talk to practitioners, because what works in production often isn't in papers yet."},
 },
 proud={
  low={"I helped finish a big project at {prev}.","Getting this far in my career, I think."},
  mid={"A {spec} pipeline at {prev} that cut our processing time in half. It's still in use.","An internal dashboard I built at {prev} that the whole team checks every morning."},
  high={"The {spec} system I designed at {prev}: it now handles millions of requests a day, and two people I trained on it lead teams themselves.","Turning a failing {spec} project at {prev} around in three months. We found the real bottleneck, fixed it, and it became the company's headline feature."},
 },
}
local NERVOUS_OPEN={"Um, okay. ","Sorry, let me think for a second. ","Right, so... ","Oh, good question. "}
local CONFIDENT_OPEN={"Sure. ","Happy to. ","Great question. ","Absolutely. "}
local NEUTRAL_OPEN={"","","Okay. ","Good question. "}
local OVERSELL_CLOSE={" Honestly, I'd say I'm one of the best at this."," I've basically mastered this already."," Most teams I've worked with couldn't have done it without me."}
local NERVOUS_CLOSE={" I hope that makes sense."," Sorry, I'm a little nervous today."," Does that answer your question?"}
local HUMBLE_CLOSE={" To be honest, I still have a lot to learn there."," I won't pretend I'm an expert yet."}
local CANDID_CLOSE={" I don't have every answer, but I know how to find them quickly."," And if I'm wrong, I'd rather find out early."}
local BUZZ={"Easy. I'd take a holistic, data-driven approach to {topic}: leverage the latest frameworks, optimise the whole pipeline end to end and iterate fast. I've done this many times.",
 "That's exactly my area. You bring in cutting-edge tooling, align everyone on the vision for {topic}, and the numbers follow.",
 "I'm known for {topic}, actually. It's all about synergy: the right AI-first mindset, best-in-class tools and a lot of disruption."}
local HONEST={"Honestly, I haven't worked on {topic} myself yet. I'd look at how the team handled it before and ask a senior colleague to review my plan.",
 "I've only read about {topic} so far, to be honest. I'd want to learn it properly from someone experienced before touching anything important.",
 "I don't have hands-on experience with {topic} yet. I'd start small, write down what I try and ask for feedback early."}
local VAGUE={"I'd look into it, check the settings and try a few things until it gets better.","Probably try different options and see what works. Maybe search online for similar problems.",
 "It depends on the situation. I'd have a look and then decide, I think."}
local START={"I could start next week.","I have a four-week notice period at {prev}, so early next month.","Right away. My contract at {prev} ended last month.","In two weeks. I want to hand over my projects at {prev} properly."}
-- The candidate's own question at the end ("Do you have any questions for us?") and the founder's
-- replies. Effects add up per matching trait (high = k>=4, low = k<=2) and are clamped to -1..1.
local function options(...: any): {any} return {...} end
local ASKS: {any}={
 {text="What does a normal day look like at {company}?",options=options(
  {text="Fast and a bit chaotic, but you'll own real problems from day one.",high=1,nervous=-1,candid=1},
  {text="Calm and flexible: sensible hours and good coffee.",nervous=1,low=1},
  {text="Long hours. We expect results, not excuses.",all=-1,oversell=1})},
 {text="How do you decide what the team works on?",options=options(
  {text="We look at the numbers together every week and pick what moves them.",high=1,candid=1},
  {text="I decide, and the team executes.",high=-1,confident=-1},
  {text="Honestly, we're still figuring that out.",candid=1,nervous=-1})},
 {text="What would success look like for me after six months?",options=options(
  {text="You've shipped something our users notice.",high=1,confident=1},
  {text="You've learned our stack and found your feet.",low=1,nervous=1},
  {text="You've hit every target we set, no matter what.",all=-1,oversell=1})},
}
local REACTIONS={[1]={"That's exactly what I was hoping to hear.","Great. That sounds like a place where I'd do my best work."},
 [0]={"Okay, thanks. Good to know.","Fair enough, thank you."},
 [-1]={"Hm. I see.","Okay... not quite what I'm looking for, but thanks for being direct."}}
local DECLINE={"I appreciate the offer, but I can't go below what I asked for.","Thank you, but at that number I'll stay where I am."}
local ACCEPT={"Thank you! I'm really excited. See you on my first day.","Deal. I can't wait to get started at {company}."}
local WORDS={"one","two","three","four","five","six","seven","eight","nine","ten","eleven","twelve"}
local function yearsText(n: number): string
 if n<=0 then return "less than a year" end
 return (WORDS[n] or tostring(n))..(if n==1 then " year" else " years")
end
local function fill(text: string,ctx: {[string]:string}): string
 return (string.gsub(text,"{(%a+)}",function(key: string): any return ctx[key] end))
end
function Recruiting.question(roleId: string,id: string): Question?
 for _,q in GENERIC do if q.id==id then return q end end
 local technical: {Question}=TECHNICAL[roleId] or {}
 for _,q in technical do if q.id==id then return q end end
 return nil
end
function Recruiting.questions(roleId: string): {Question}
 local out=table.clone(GENERIC)
 local technical: {Question}=TECHNICAL[roleId] or {}
 for _,q in technical do table.insert(out,q) end
 return out
end
-- Context for the templates: {company}, {years}, {Years}, {prev}, {spec}, {roleName}, {cost}, {wage}, {month}, {topic}.
function Recruiting.context(person: Person,company: string,e: any?): {[string]:string}
 local years=yearsText(person.xp)
 local def=roleDef(person.role)
 return {company=company,years=years,Years=(string.gsub(years,"^%l",string.upper)),prev=person.prev,spec=person.spec,roleName=def.name,
  cost=Format.money(Recruiting.hireCost(person.role,person.ask,e)),wage=string.format("$%.2f/s",Recruiting.wage(person.role,person.ask)),
  month=Format.money(Recruiting.wage(person.role,person.ask)*GameConfig.GAME_MONTH_SECONDS)}
end
local function tierOf(k: number): string return if k<=2 then "low" elseif k>=4 then "high" else "mid" end
-- Position of a question in its bank (generic or the role's technical list): consecutive questions
-- pick consecutive template variants, so recurring phrases never repeat back to back.
local ORDER: {[string]:number}={}
for i,q in GENERIC do ORDER[q.id]=i end
for _,list in TECHNICAL do for i,q in list do ORDER[q.id]=20+i end end
local function variant<T>(person: Person,qid: string,list: {T}): T
 return list[(person.serial+(ORDER[qid] or 0))%#list+1]
end
local function picker(person: Person,qid: string,salt: number): (number)->number
 return stream((person.serial*0x27d4eb2f+textHash(qid)+salt)%4294967296)
end
-- What one answer tells an interviewer about the skill: (evidence on the 1..5 scale, weight).
-- Overselling inflates general answers by a full tier, nerves deflate them; technical answers show the
-- real skill (weight 2.5); salary asks are a weak, honest signal (the ask correlates with skill).
local function evidence(person: Person,q: Question): (number,number)
 local noise=(unit(picker(person,q.id,0x51ed27))-.5)*.8
 if q.kind=="technical" then return person.k+noise,2.5 end
 if q.id=="salary" then return 1+(person.ask-.8)/.175,.4 end
 if q.id=="start" then return person.k+noise*2,.15 end
 local bias=(if person.candour<.35 then 1 else 0)-(if person.confidence<.35 then .5 else 0)
 if q.id=="questions" then return person.k+bias*.5+noise,.6 end
 return person.k+bias+noise,1
end
function Recruiting.candidateAsk(person: Person): any return ASKS[person.serial%#ASKS+1] end
-- Answer text for question `qid` (nil when the question does not exist for the role).
function Recruiting.answer(person: Person,qid: string,ctx: {[string]:string}): string?
 local q=Recruiting.question(person.role,qid);if not q then return nil end
 local pick=picker(person,qid,0)
 local tier=tierOf(person.k)
 local nervous,confident=person.confidence<.35,person.confidence>.65
 local oversell,candid=person.candour<.35,person.candour>.65
 local opener: string=choose(pick,if nervous then NERVOUS_OPEN elseif confident then CONFIDENT_OPEN else NEUTRAL_OPEN)
 local body: string;local closer=""
 if q.kind=="technical" then
  local local_ctx=table.clone(ctx);local_ctx.topic=q.topic or "this"
  if tier=="high" then body=q.high or "" elseif tier=="mid" then body=q.mid or ""
  elseif oversell then body=variant(person,qid,BUZZ) elseif candid then body=variant(person,qid,HONEST) else body=variant(person,qid,VAGUE) end
  if oversell and tier~="low" and pick(10)<=6 then closer=variant(person,qid,OVERSELL_CLOSE)
  elseif nervous and pick(10)<=5 then closer=variant(person,qid,NERVOUS_CLOSE)
  elseif candid and tier=="high" and pick(10)<=4 then closer=variant(person,qid,CANDID_CLOSE) end
  return fill(opener..body..closer,local_ctx)
 elseif qid=="salary" then
  body="I'm looking for a signing package of about {cost}, then {wage}, roughly {month} per game month."
  closer=if oversell then " With my track record, that's a bargain." elseif nervous then " But I'm, um, open to discussing it."
   elseif tier=="high" and confident then " That's in line with the other offers I have." elseif tier=="low" and candid then " I know I'm still learning, so I kept it reasonable." else ""
 elseif qid=="start" then
  body=if tier=="high" then START[4] else choose(pick,START)
  if nervous then closer=" If that works for you, of course." end
 elseif qid=="questions" then
  opener="" -- the candidate's own question needs no filler
  body=(if nervous then "Um, yes, actually. " else "Yes, actually. ")..Recruiting.candidateAsk(person).text
 else
  local shown=if oversell and tier=="low" then "mid" elseif oversell then "high" else tier
  body=choose(pick,GENERIC_ANSWERS[qid][shown])
  if oversell and pick(10)<=7 then closer=variant(person,qid,OVERSELL_CLOSE)
  elseif nervous and pick(10)<=5 then closer=variant(person,qid,NERVOUS_CLOSE)
  elseif candid and tier=="low" and pick(10)<=5 then closer=variant(person,qid,HUMBLE_CLOSE) end
 end
 return fill(opener..body..closer,ctx)
end
-- Mood change (-1..1) caused by the founder's reply option to the candidate's question.
function Recruiting.mood(person: Person,option: number?): number
 if not option then return 0 end
 local opt=Recruiting.candidateAsk(person).options[option];if not opt then return 0 end
 local m=(opt.all or 0)+(if person.k>=4 then opt.high or 0 else 0)+(if person.k<=2 then opt.low or 0 else 0)
  +(if person.confidence<.35 then opt.nervous or 0 else 0)+(if person.confidence>.65 then opt.confident or 0 else 0)
  +(if person.candour>.65 then opt.candid or 0 else 0)+(if person.candour<.35 then opt.oversell or 0 else 0)
 return math.clamp(m,-1,1)
end
function Recruiting.reaction(person: Person,option: number): string
 local list=REACTIONS[Recruiting.mood(person,option)]
 return list[picker(person,"reply",option)(#list)]
end
-- Would the candidate accept the reduced offer? Weak candidates always, average ones unless the
-- conversation went badly, strong ones only after a reply they liked.
function Recruiting.acceptsLow(person: Person,option: number?): boolean
 local mood=Recruiting.mood(person,option)
 return person.k<=2 or (person.k==3 and mood>=0) or (person.k>=4 and mood>=1)
end
-- Estimated skill range after the asked questions; never collapses to an exact value before hiring.
function Recruiting.impression(person: Person,asked: {string}): {estimateLow: number,estimateHigh: number,note: string}
 local weight,sum,technical=0,0,0
 for _,id in asked do
  local q=Recruiting.question(person.role,id)
  if q then local e,w=evidence(person,q);weight+=w;sum+=e*w;if q.kind=="technical" then technical+=1 end end
 end
 if weight<=0 then return {estimateLow=1,estimateHigh=5,note="First impressions only. Ask questions to judge their skill."} end
 local estimate=sum/weight
 local spread=math.clamp(2.4/math.sqrt(1+weight),.5,2)
 local low=math.clamp(math.floor((estimate-spread)*2+.5)/2,1,5);local high=math.clamp(math.floor((estimate+spread)*2+.5)/2,1,5)
 if high-low<1 then
  local mid=math.clamp(math.floor(estimate*2+.5)/2,1.5,4.5);low=mid-.5;high=mid+.5
 end
 local manner=if person.confidence<.35 then "Nervous" elseif person.confidence>.65 then "Self-assured" else "Composed"
 local note
 if technical==0 then note=manner..". Ask a technical question to test real depth."
 elseif person.candour<.35 and person.k<=3 then note="Big claims; the technical answers don't fully back them up."
 elseif person.k>=4 then note=if person.confidence<.35 then "Nervous, but the technical steps are concrete and correct." else "Concrete, correct technical steps."
 elseif person.k==3 then note="Solid fundamentals, fewer specifics."
 elseif person.candour>.65 then note="Honest about gaps; technical depth is limited."
 else note="Technical answers stay vague." end
 return {estimateLow=low,estimateHigh=high,note=note}
end

-- Visitor NPC helpers (shared with AssistantService) ----------------------------------------------
local NPC={}
Recruiting.npc=NPC
function NPC.flat(a: Vector3,b: Vector3): number return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
-- Turns a rig from EmployeeRigDesign into a non-staff person: role for doors/navigation, badge text and
-- an owner-only prompt handled by `action` (the EmployeeTalk attribute is removed, so StaffService
-- ignores it). Parts join the CompanyEmployees collision group like staff.
function NPC.dress(model: Model,roleId: string,title: string,actionText: string,action: string,attrs: {[string]:any},lanyard: Color3?)
 model:SetAttribute("RoleId",roleId);model:SetAttribute("Role",title);model:SetAttribute("AccessClass",roleId)
 local head=model:FindFirstChild("Head")
 local badge=if head then head:FindFirstChild("EmployeeBadge") else nil
 local label=if badge then badge:FindFirstChildWhichIsA("TextLabel") else nil
 if label then label.Text=tostring(model:GetAttribute("EmployeeName")).."\n"..title end
 local prompt=if head then head:FindFirstChild("EmployeeTalk") else nil
 if prompt and prompt:IsA("ProximityPrompt") then
  prompt.Name="PeopleTalk";prompt:SetAttribute("EmployeeTalk",nil);prompt:SetAttribute("PeopleAction",action)
  prompt.ActionText=actionText;prompt.RequiresLineOfSight=false;prompt.HoldDuration=0
  for k,v in attrs do prompt:SetAttribute(k,v) end
 end
 for _,p in model:GetDescendants() do
  if p:IsA("BasePart") then
   p.CollisionGroup="CompanyEmployees"
   if lanyard and p.Name=="Lanyard" then p.Color=lanyard end
  end
 end
end
-- Navigation record compatible with EmployeeNavigation and WorkstationService.
function NPC.record(model: Model,roleId: string,index: number,tier: number,cf: CFrame,office: Model,seed: number): any
 local h=model:FindFirstChildOfClass("Humanoid")
 return {model=model,root=model.PrimaryPart,humanoid=h,index=index,name=model:GetAttribute("EmployeeName"),role=roleId,tier=tier,cf=cf,office=office,
  personality=EmployeeConfig.personalityFromSeed(seed),state="WAITING",now=Staff.now(),sequence=0}
end
-- Direct Humanoid walk (no path) for open ground the plan does not class as public (plaza).
function NPC.straight(e: any,target: Vector3)
 e.root.Anchored=false;e.humanoid.Sit=false;e.humanoid.AutoRotate=true;e.humanoid.EvaluateStateMachine=true;e.humanoid.WalkSpeed=e.personality.walkSpeed
 pcall(function() e.root:SetNetworkOwner(nil) end)
 e.humanoid:MoveTo(target)
end
-- DoorService only counts NPCs in Employees/OperationsEmployees as "in the doorway"; while one of
-- these NPCs stands in an open door it re-requests the door so the hold timer cannot close it on them.
function NPC.holdDoors(e: any,time: number)
 if (e.doorHoldAt or 0)>time then return end
 e.doorHoldAt=time+.5
 for _,door in Doors.doorsNear(e.office,e.root.Position,7) do
  local state=Doors.state(door)
  if state=="open" or state=="opening" then
   local sensor=door:FindFirstChild("Sensor")
   local centre=if sensor and sensor:IsA("BasePart") then sensor.Position else door:GetPivot().Position
   local class=door:GetAttribute("AccessClass")
   if NPC.flat(centre,e.root.Position)<=4.5 and Plan.roleAllows(e.role,if typeof(class)=="string" then class else nil) then Doors.requestNPC(e.model,door) end
  end
 end
end
function NPC.face(e: any,position: Vector3)
 if not e.root.Parent or (e.humanoid and e.humanoid.SeatPart) then return end
 local p=e.root.Position;local d=Vector3.new(position.X-p.X,0,position.Z-p.Z)
 if d.Magnitude>.2 then e.root.CFrame=CFrame.lookAt(p,p+d) end
end

-- Visitors ------------------------------------------------------------------------------------------
local visits: {[string]:any}={}
local claimed: {[Instance]:{[any]:string}}=setmetatable({},{__mode="k"}) :: any
local runtime: {[any]:any}=setmetatable({},{__mode="k"}) :: any
local function visitKey(s: any,id: string): string return tostring(s.userId)..":"..id end
local function find(e: any,id: string): (any,number?)
 for i,a in e.applicants do if a.id==id then return a,i end end
 return nil,nil
end
local function notify(s: any,text: string)
 Remote.fire(s.player,"Notify","PEOPLE_NOTICE",{text=text})
end
local function companyName(s: any): string
 return if s.data.company then s.data.company.name else s.player.DisplayName.."'s company"
end
-- Waiting places in the visitor lounge: its activities (Lounge seats …), else the raw Seats of its room
-- model, then standing spots along the lounge's open east edge (kept free of furniture; used when the
-- room is not furnished or every seat is taken), so an invited candidate always has somewhere to wait.
-- A raw seat is approached from the side away from its neighbours (sofas face a coffee table, so the
-- floor in front of a seat is often blocked), then the other side, then just in front; Seat:Sit does
-- the last step like workstation chairs.
local function floorPoint(v: any,p: Vector3): Vector3
 local lp=v.cf:PointToObjectSpace(p);return v.cf*Vector3.new(lp.X,Plan.levelY(0)+3,lp.Z)
end
local function spots(v: any): {any}
 local list={}
 local route=Plan.visitorRoute(v.tier)
 for _,w in Workstations.scan(v.office).all do
  if w.room==route.room and w.kind~="Computer" and w.model.Parent then table.insert(list,{key=w,w=w,candidates={w.position}}) end
 end
 if #list==0 then
  local rooms=v.office:FindFirstChild("Rooms");local room=if rooms then rooms:FindFirstChild(route.room) else nil
  local seats: {Seat}={}
  if room then for _,d in room:GetDescendants() do if d:IsA("Seat") and not d.Disabled then table.insert(seats,d) end end end
  for _,seat in seats do
   local function crowd(p: Vector3): number
    local m=math.huge;for _,o in seats do if o~=seat then m=math.min(m,(o.Position-p).Magnitude) end end;return m
   end
   local offset=seat.CFrame.RightVector*(seat.Size.X/2+2.2)
   local a,b=seat.Position+offset,seat.Position-offset
   if crowd(b)>crowd(a) then a,b=b,a end
   table.insert(list,{key=seat,seat=seat,candidates={floorPoint(v,a),floorPoint(v,b),floorPoint(v,seat.Position+seat.CFrame.LookVector*1.6)}})
  end
 end
 for i,p in route.standing do table.insert(list,{key="edge"..i,candidates={v.cf*p}}) end
 return list
end
local function releaseSpot(v: any)
 local spot=v.spot;if not spot then return end
 local claims=claimed[v.office];if claims and claims[spot.key]==v.key then claims[spot.key]=nil end
 if spot.w then Workstations.release(v.e)
 else v.e.humanoid.Sit=false;v.e.root.Anchored=false end
 v.spot=nil;v.seated=false
end
local function claimSpot(v: any): any
 local claims=claimed[v.office];if not claims then claims={};claimed[v.office]=claims end
 for _,spot in spots(v) do
  if claims[spot.key]==nil and not (spot.seat and spot.seat.Occupant) then
   if spot.w and not Workstations.reserve(spot.w,v.e) then continue end
   claims[spot.key]=v.key;v.spot=spot;v.tries=0;return spot
  end
 end
 return nil
end
local function sit(v: any)
 local spot=v.spot;local e=v.e;if not spot then return end
 if spot.w then
  e.task={id="Interview",state="WAITING"}
  if Workstations.perform(e,Staff.now()) then v.seated=true;return end
 elseif spot.seat then
  e.humanoid.AutoRotate=false;e.root.Anchored=false;spot.seat:Sit(e.humanoid);e.root.Anchored=true;v.seated=true;return
 end
 -- standing spot: face the route's waiting direction (HQ: the reception hall, building east) and wait
 local p=e.root.Position;NPC.face(e,p+v.cf:VectorToWorldSpace(Plan.visitorRoute(v.tier).standFace));e.root.Anchored=true;v.seated=true
end
local function despawn(v: any)
 if v.hireSeed then
  -- a hired candidate leaves at the speed gates: the staff rig takes over at that spot (first day)
  local root=v.e.root
  Staff.handoverArrival(v.office,v.hireSeed,if root and root.Parent then root.CFrame else nil)
  v.hireSeed=nil
 end
 Nav.cancel(v.e);releaseSpot(v)
 if v.model.Parent then v.model:Destroy() end
 visits[v.key]=nil
end
local enter: (v: any)->()
local function go(v: any,target: Vector3,done: (boolean)->())
 v.e.now=Staff.now()
 Nav.go(v.e,target,Staff.now(),function(ok: boolean) if visits[v.key]==v then done(ok) end end)
end
-- Walk to the claimed place; a failed route tries the next approach point, then gives up and waits
-- where the candidate stands (the Interview prompt works anywhere).
enter=function(v: any)
 v.phase="enter"
 local spot=v.spot or claimSpot(v)
 if not spot then v.phase="waiting";return end
 local target=spot.candidates[math.min(v.tries+1,#spot.candidates)]
 go(v,target,function(ok)
  if v.phase~="enter" then return end
  if ok then v.phase="waiting";sit(v)
  else
   v.tries+=1
   if v.tries<math.max(3,#spot.candidates) then v.phase="retry";v.retryAt=Staff.now()+2 else releaseSpot(v);v.phase="waiting" end
  end
 end)
end
local function walkStraight(v: any,target: Vector3,phase: string)
 v.phase=phase;v.walk={target=target,since=Staff.now(),issued=Staff.now()};NPC.straight(v.e,target)
end
-- Inside the entrance recess (public per the plan from z = -48), just before the automatic doors
-- (garage stage: in front of the porch).
local function portalPoint(v: any): Vector3
 local route=Plan.visitorRoute(v.tier)
 return v.cf*(route.portal+route.spread*((v.slot-1)%3-1))
end
-- kind "out": back to the plaza (rejected); "hired": through the public hall to the speed gates.
local function leave(v: any,kind: string)
 if v.phase=="leaving" or v.phase=="exit" then return end
 Nav.cancel(v.e);releaseSpot(v);v.phase="leaving";v.tries=0
 local route=Plan.visitorRoute(v.tier)
 if kind=="hired" then
  local exit=route.exits[(v.slot-1)%#route.exits+1]
  go(v,v.cf*exit,function(_ok) despawn(v) end)
 else
  go(v,portalPoint(v),function(_ok)
   if visits[v.key]~=v then return end
   walkStraight(v,v.cf*(route.arrival+Vector3.new(((v.slot-1)%3-1)*2,0,0)),"exit")
  end)
 end
end
local function spawnVisitor(s: any,p: any,a: any): any
 local office: Model=p.office;local cf: CFrame=p.cframe
 local tierAttr=office:GetAttribute("OfficeTier");local tier: number=if typeof(tierAttr)=="number" then tierAttr else Plan.tierForOffice(s.data.empire.office)
 local folder: Instance?=office:FindFirstChild("Visitors")
 if not folder then local created=Instance.new("Folder");created.Name="Visitors";created.Parent=office;folder=created end
 local used: {[number]:boolean}={}
 for _,v in visits do if v.office==office then used[v.slot]=true end end
 local slot=1;while used[slot] do slot+=1 end
 local route=Plan.visitorRoute(tier)
 local start=route.arrival+Vector3.new(((slot-1)%3-1)*2,0,-((slot-1)//3)*2)
 local pose=cf*CFrame.lookAt(start,start+route.face)
 -- Interview clothes: the marketer wardrobe is mostly blazers; the role is "visitor" for doors and paths.
 local model=Rig.build(folder::Instance,s.userId,500+slot,"marketer",pose,{n=a.n,s=a.s})
 local def=roleDef(a.role)
 NPC.dress(model,"visitor","Applicant · "..def.name,"Interview","interview",{ApplicantId=a.id},Color3.fromRGB(150,154,160))
 local e=NPC.record(model,"visitor",500+slot,tier,cf,office,a.s)
 local v={key=visitKey(s,a.id),id=a.id,session=s,office=office,cf=cf,tier=tier,model=model,e=e,slot=slot,phase="approach",tries=0,seated=false}
 visits[v.key]=v
 walkStraight(v,portalPoint(v),"approach")
 return v
end
function Recruiting.visit(s: any,id: string): any return visits[visitKey(s,id)] end
-- After an interview that interrupted the walk in: continue to the lounge (from the plaza: walk to the
-- entrance recess first, the plan does not class the plaza as public).
local function resume(v: any)
 if v.seated or v.phase~="waiting" or not v.e.root.Parent then return end
 v.e.root.Anchored=false
 if Plan.employeeAllowed(v.e.role,v.tier,v.cf:PointToObjectSpace(v.e.root.Position)) then enter(v)
 else walkStraight(v,portalPoint(v),"approach") end
end

-- Interview payload -------------------------------------------------------------------------------
local function initials(name: string): string
 local out=""
 for word in string.gmatch(name,"%S+") do out..=string.sub(word,1,1);if #out>=2 then break end end
 return string.upper(out)
end
function Recruiting.payload(s: any,a: any): any
 local person=Recruiting.person(s.userId,a);local company=companyName(s);local ctx=Recruiting.context(person,company,s.data.empire)
 local def=roleDef(a.role)
 local transcript={}
 for _,id in a.q do
  local q=Recruiting.question(a.role,id)
  if q then
   table.insert(transcript,{from="founder",text=fill(q.text,ctx)})
   table.insert(transcript,{from="candidate",text=Recruiting.answer(person,id,ctx) or ""})
   if id=="questions" and a.r then
    local opt=Recruiting.candidateAsk(person).options[a.r]
    table.insert(transcript,{from="founder",text=if opt then opt.text else ""})
    table.insert(transcript,{from="candidate",text=Recruiting.reaction(person,a.r)})
   end
  end
 end
 local lowMult=roundAsk(a.ask*Recruiting.LOW_OFFER)
 if a.low then
  table.insert(transcript,{from="founder",text="We can offer "..Format.money(Recruiting.hireCost(a.role,lowMult,s.data.empire)).." and "..string.format("$%.2f/s",Recruiting.wage(a.role,lowMult)).."."})
  table.insert(transcript,{from="candidate",text=DECLINE[a.serial%#DECLINE+1]})
 end
 local remaining={}
 local asked: {[string]:boolean}={};for _,id in a.q do asked[id]=true end
 if #a.q<Recruiting.MAX_QUESTIONS then
  for _,q in Recruiting.questions(a.role) do if not asked[q.id] then table.insert(remaining,{id=q.id,text=fill(q.text,ctx),kind=q.kind}) end end
 end
 local pending=nil
 if asked.questions and not a.r then
  local ask=Recruiting.candidateAsk(person);local options={}
  for i,opt in ask.options do options[i]=opt.text end
  pending={text=fill(ask.text,ctx),options=options}
 end
 local e=s.data.empire
 return {id=a.id,name=a.n,initials=initials(a.n),seed=a.s,role=a.role,roleName=def.name,xp=a.xp,years=ctx.years,prev=a.prev,spec=a.spec,ask=a.ask,
  cost=Recruiting.hireCost(a.role,a.ask,e),wage=Recruiting.wage(a.role,a.ask),lowCost=Recruiting.hireCost(a.role,lowMult,e),lowWage=Recruiting.wage(a.role,lowMult),
  lowDeclined=a.low==true,monthSeconds=GameConfig.GAME_MONTH_SECONDS,transcript=transcript,questions=remaining,asked=#a.q,max=Recruiting.MAX_QUESTIONS,
  impression=Recruiting.impression(person,a.q),pendingAsk=pending,company=company,status=a.st,
  staffFull=EmpireMath.staff(e)>=EmpireConfig.OFFICES[e.office].staff}
end
function Recruiting.counts(s: any): {open: number,waiting: number}
 local open,waiting=0,0
 for _,a in s.data.empire.applicants do if a.st=="new" then open+=1 else waiting+=1 end end
 return {open=open,waiting=waiting}
end

-- Remote --------------------------------------------------------------------------------------------
local function interviewing(a: any): boolean return a.st=="interviewing" end
local function hire(s: any,a: any,index: number,low: boolean): any
 local e=s.data.empire
 if EmpireMath.staff(e)>=EmpireConfig.OFFICES[e.office].staff then return {ok=false,err="STAFF_FULL"} end
 local person=Recruiting.person(s.userId,a)
 if low and a.low then return {ok=false,err="OFFER_DECLINED"} end
 if low and not Recruiting.acceptsLow(person,a.r) then
  a.low=true;Session.markDirty(s)
  return {ok=true,accepted=false,text=DECLINE[a.serial%#DECLINE+1],interview=Recruiting.payload(s,a)}
 end
 local mult=if low then roundAsk(a.ask*Recruiting.LOW_OFFER) else a.ask
 local cost=Recruiting.hireCost(a.role,mult,e)
 if not Economy.spend(s,cost,"hire") then return {ok=false,err="NO_MONEY"} end
 EmpireMath.syncProfiles(e,s.userId)
 table.insert(e.staffProfiles[a.role],{n=a.n,s=a.s,k=person.k,w=mult})
 e.employees[a.role]=(e.employees[a.role] or 0)+1
 table.remove(e.applicants,index)
 Session.markDirty(s)
 local v=visits[visitKey(s,a.id)]
 if v then
  -- the candidate walks out to the speed gates; there the new colleague's rig takes over (first day:
  -- badge at reception, then the desk)
  Staff.expectArrival(v.office,a.s,nil,true);v.hireSeed=a.s
  leave(v,"hired")
 end
 Plot.refresh(s)
 local def=roleDef(a.role)
 notify(s,a.n.." joined "..companyName(s).." as "..def.name..".")
 return {ok=true,accepted=true,cost=cost,text=fill(ACCEPT[a.serial%#ACCEPT+1],{company=companyName(s)})}
end
local function act(s: any,p: any): any
 local action=p.action;local id=Guard.id(p.id)
 if typeof(action)~="string" or not id then return {ok=false,err="BAD_INPUT"} end
 local e=s.data.empire
 local a,index=find(e,id)
 if not a or not index then return {ok=false,err="APPLICANT_GONE"} end
 if action=="invite" then
  if a.st~="new" then return {ok=false,err="ALREADY_INVITED"} end
  local plot=Plot.get(s.player)
  if not plot or not plot.office then return {ok=false,err="NO_OFFICE"} end
  spawnVisitor(s,plot,a);a.st="invited";Session.markDirty(s)
  return {ok=true}
 elseif action=="reject" then
  table.remove(e.applicants,index);Session.markDirty(s)
  local v=visits[visitKey(s,id)];if v then leave(v,"out") end
  return {ok=true}
 elseif action=="open" then
  if not interviewing(a) then return {ok=false,err="NOT_HERE"} end
  return {ok=true,interview=Recruiting.payload(s,a)}
 elseif action=="close" then
  if interviewing(a) then a.st="invited";Session.markDirty(s) end
  local v=visits[visitKey(s,id)];if v then resume(v) end
  return {ok=true}
 elseif action=="question" then
  if not interviewing(a) then return {ok=false,err="NOT_HERE"} end
  local qid=Guard.id(p.questionId);local q=if qid then Recruiting.question(a.role,qid) else nil
  if not qid or not q then return {ok=false,err="BAD_INPUT"} end
  if table.find(a.q,qid) then return {ok=false,err="ASKED"} end
  if #a.q>=Recruiting.MAX_QUESTIONS then return {ok=false,err="QUESTION_LIMIT"} end
  table.insert(a.q,qid);Session.markDirty(s)
  local person=Recruiting.person(s.userId,a);local ctx=Recruiting.context(person,companyName(s),s.data.empire)
  return {ok=true,question=fill(q.text,ctx),answer=Recruiting.answer(person,qid,ctx),interview=Recruiting.payload(s,a)}
 elseif action=="reply" then
  if not interviewing(a) then return {ok=false,err="NOT_HERE"} end
  local option=Guard.integer(p.option,1,3)
  if not option then return {ok=false,err="BAD_INPUT"} end
  if not table.find(a.q,"questions") or a.r~=nil then return {ok=false,err="NO_ASK"} end
  a.r=option;Session.markDirty(s)
  local person=Recruiting.person(s.userId,a)
  return {ok=true,text=Recruiting.reaction(person,option),interview=Recruiting.payload(s,a)}
 elseif action=="hire" then
  if not interviewing(a) then return {ok=false,err="NOT_HERE"} end
  return hire(s,a,index,p.offer=="low")
 end
 return {ok=false,err="BAD_INPUT"}
end
Recruiting._act=act -- tests

-- Prompt: the founder talks to a waiting candidate -----------------------------------------------
local function onPrompt(q: ProximityPrompt,player: Player)
 if q:GetAttribute("PeopleAction")~="interview" then return end
 local id=q:GetAttribute("ApplicantId")
 if typeof(id)~="string" or q:GetAttribute("OwnerUserId")~=player.UserId then return end
 local s=Session.get(player);if not s or s.closed then return end
 local v=visits[visitKey(s,id)];local a=find(s.data.empire,id)
 local character=player.Character;local root=if character then character.PrimaryPart else nil
 if not v or not a or not root or (root.Position-v.e.root.Position).Magnitude>14 then return end
 if v.phase=="leaving" or v.phase=="exit" then return end
 a.st="interviewing";Session.markDirty(s,true) -- prompt-driven: urgent send (net request 2)
 if v.e.nav then Nav.cancel(v.e) end
 -- also in "retry" (no route active): otherwise campusTick re-enters and walks off mid-interview
 if v.phase=="enter" or v.phase=="retry" then v.phase="waiting";releaseSpot(v) end
 if v.phase=="approach" then v.phase="waiting";v.walk=nil end
 if not v.seated then NPC.face(v.e,root.Position);v.e.root.Anchored=true end
 Remote.fire(player,"Notify","INTERVIEW_OPEN",Recruiting.payload(s,a))
end
Recruiting._prompt=onPrompt -- tests

-- Ticks ---------------------------------------------------------------------------------------------
local function rt(s: any): any
 local state=runtime[s]
 if not state then
  state={rng=Random.new((s.userId%2147483647+7919*(tonumber(s.data.empire.hireSerial) or 0))%2147483647),loaded=false,next=nil}
  runtime[s]=state
 end
 return state
end
-- Simulation step (1 s): profile repair, expiry, arrivals.
function Recruiting.tick(s: any,_dt: number)
 if s.closed or not s.data.company then return end
 local e=s.data.empire;local state=rt(s)
 if not state.loaded then
  state.loaded=true
  -- after a rejoin nobody is waiting in the lounge any more; the interview so far is kept and the
  -- expiry window restarts (a.at is the application time, which may already be past EXPIRE)
  for _,a in e.applicants do if a.st~="new" and not visits[visitKey(s,a.id)] then a.st="new";a.at=e.seconds end end
 end
 if not EmpireMath.profilesConsistent(e) then EmpireMath.syncProfiles(e,s.userId);Session.markDirty(s) end
 local now=e.seconds
 for i=#e.applicants,1,-1 do
  local a=e.applicants[i]
  if a.st=="new" and now-a.at>=Recruiting.EXPIRE then table.remove(e.applicants,i);Session.markDirty(s) end
 end
 local open=EmpireMath.staff(e)<EmpireConfig.OFFICES[e.office].staff and #e.applicants<EmpireMath.MAX_APPLICANTS
 if not open then state.next=nil;return end
 if state.next==nil then state.next=now+state.rng:NextInteger(Recruiting.ARRIVAL[1],Recruiting.ARRIVAL[2]) end
 if now>=state.next then
  state.next=nil
  local a=Recruiting.generate(e,s.userId,now)
  table.insert(e.applicants,a);Session.markDirty(s)
  notify(s,"New application: "..a.n.." · "..roleDef(a.role).name)
 end
end
-- Campus step (Heartbeat): visitor navigation on the shared EmployeeNavigation queue/clock.
function Recruiting.campusTick(_dt: number)
 local time=Staff.now()
 for _,v in visits do
  local e=v.e
  if not v.model.Parent or not v.office.Parent or v.session.closed or not e.root.Parent then
   local a=if not v.session.closed then find(v.session.data.empire,v.id) else nil
   if a and a.st~="new" then a.st="new";a.at=v.session.data.empire.seconds;Session.markDirty(v.session) end
   despawn(v);continue
  end
  e.now=time
  Nav.tick(e,time)
  NPC.holdDoors(e,time)
  local walk=v.walk
  if (v.phase=="approach" or v.phase=="exit") and walk then
   -- the walk in hands over to navigation only on ground the visitor role may use
   local arrived=NPC.flat(e.root.Position,walk.target)<(if v.phase=="approach" then 1.2 else 2.2)
    and (v.phase=="exit" or Plan.employeeAllowed(e.role,v.tier,v.cf:PointToObjectSpace(e.root.Position)))
   if arrived or time-walk.since>25 then
    v.walk=nil
    if v.phase=="exit" then despawn(v) else enter(v) end
   elseif time-walk.issued>3 then walk.issued=time;e.humanoid:MoveTo(walk.target) end
  elseif v.phase=="retry" and time>=(v.retryAt or 0) then enter(v) end
 end
end

-- Headhunter voucher (shop, CORE_SPEC 11.7): one applicant whose hidden skill is 4 or 5. Deterministic: the
-- serial stream is walked until such a candidate comes up (each generate() takes the next serial).
function Recruiting.headhunt(s: any): (boolean,string?)
 if not s.data.company then return false,"NO_COMPANY" end
 local e=s.data.empire
 if #e.applicants>=EmpireMath.MAX_APPLICANTS then return false,"APPLICANTS_FULL" end
 if EmpireMath.staff(e)>=EmpireConfig.OFFICES[e.office].staff then return false,"STAFF_FULL" end
 for _=1,60 do
  local a=Recruiting.generate(e,s.userId,e.seconds)
  if Recruiting.traits(s.userId,a.serial).k>=4 then
   table.insert(e.applicants,a)
   Session.markDirty(s,true)
   notify(s,"Headhunter: "..a.n.." · "..roleDef(a.role).name.." applied (top candidate)")
   return true
  end
 end
 return false,"NO_CANDIDATE"
end
function Recruiting.init()
 Remote.bind("RecruitAction",{burst=4,perSecond=2,company=true},act)
 Shop.setRedeemHandler("headhunter",Recruiting.headhunt)
 Prompts.PromptTriggered:Connect(onPrompt)
 Session.onLoaded(function(s)
  -- identities StaffAssignment shows today become persistent profiles (no visible change)
  EmpireMath.syncProfiles(s.data.empire,s.userId)
 end)
 Session.onClosing(function(s)
  for _,v in visits do if v.session==s then despawn(v) end end
  runtime[s]=nil
 end)
end
return Recruiting
