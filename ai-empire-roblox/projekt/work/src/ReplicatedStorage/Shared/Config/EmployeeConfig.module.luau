--!strict
-- Employee tuning shared by the server staff services and the client pose controller.
-- Task ids are a contract: BuildingStateService maps them to screen kinds.
local Config={}
Config.NEAR=120;Config.FAR=250;Config.MAX_PATH_JOBS=2;Config.MAX_MOVING_PER_OFFICE=20
-- Movers cap split: employees start new walks only below MAX - OPS_MOVER_RESERVE; the last slots are
-- kept for the operations staff's job walks and hops (a chef or the servery team never starves).
Config.OPS_MOVER_RESERVE=3
function Config.moverCap(role: string?): number
 return if role=="support" then Config.MAX_MOVING_PER_OFFICE else Config.MAX_MOVING_PER_OFFICE-Config.OPS_MOVER_RESERVE
end
Config.BREAK_SHARE=.3 -- at most this share of an office's staff on COFFEE_BREAK/LUNCH at once
Config.LIFT_WAIT=45 -- seconds an employee waits for the cabin before taking the stairs
Config.DOOR_WAIT=4 -- seconds an employee waits for a requested door before recomputing
Config.ROLES={researcher="AI Researcher",engineer="ML Engineer",curator="Data Curator",marketer="Growth Manager",support="Campus Operations"}
-- Operations staff 301.. in OpsIndex order (OperationsStation1..). 1-12 unchanged; 13/14 are the hotel
-- annex posts (built only by the buildings package, optional: no post = nobody placed); 15/16 have
-- posts in RoomKitsSpecial (cleaning cart park in Deliveries, mailroom sorting table).
-- 17 "Training Lead" (staffops, CORE_SPEC 11.1): the apprentices' trainer; no OperationsStation post: the
-- rig exists only while the company has apprentices and works from a free desk in the HR room
-- (StaffAssignment), else at the reception. Its wage ($900/day) is CompanyOps.TRAINING_LEAD.
Config.OPERATIONS_JOBS={"Reception","Reception","Security","Security","Facilities","IT Support","Barista","Chef","Kitchen Team","Cafe Host","Facilities","Fleet","Hotel Reception","Housekeeping","Cleaner","Mailroom","Training Lead"}
Config.OPTIONAL_POSTS={[13]=true,[14]=true,[17]=true}
Config.TRAINING_LEAD_POST=17
-- Pay of one operations post per game day (CORE_SPEC 5.5 / 11.5): CompanyOps.OPS_WAGE reads it, TalkService
-- may quote it.
Config.OPS_WAGE_PER_DAY=720
-- Operations posts follow the day shift (CORE_SPEC 5.3 / 11.1): every post is staffed before the office opens
-- (08:00) until after it closes (18:00); seeded per person inside these windows, breaks are covered in place.
-- From stage 5 the security guard (post 3) and IT (post 6) keep a night rota (no new station); security also
-- stays while a department runs a night crew (the night shift needs a security post on duty).
Config.OPS_SHIFT={start={7.25,7.5},finish={18.0,18.5}}
Config.NIGHT_ROTA_POSTS={[3]=true,[6]=true}
-- Night crew of a department with empire.nightShift[dept] (stage >= 3): 22:00-06:00 company time.
Config.NIGHT_CREW={start=22,finish=6}
-- Apprentices (CORE_SPEC 11.1, user request 18): first day = a guided tour with the Training Lead, then one
-- training session a day in a meeting room (TRAINING_HOURS), the rest of the day shadowing a senior colleague.
Config.APPRENTICE={tourHours={8.3,16.0},tourStops={4,6},stopSeconds={9,13},trainingHours={10.0,11.5},shadowEvery=3,scale=.94}
-- Operations job steps (StaffJobs). Fields: at = post job point (JobPoint_<at>, world space on the post;
-- nil = the post itself), via = points walked through first, sit = sit on the post seat, pose / item
-- (rig attributes Pose / Holding; item=false clears), seconds = {min,max}, prop = use the point's
-- JobProp_<at> for the step, optional = skip when the post has no such point, when = "lunch" | "open"
-- (only during / outside the café lunch service), and special kinds: visit = WorkstationType to work at
-- (Clean), route = WorkstationType visited in MopIndex order by short hops (Mop), fault = IT fix of a
-- broken desk screen, trays = carry returned trays to the dish station, serve = hand out lunch plates;
-- every = n runs the step only every n-th time it comes up.
-- Cross-room points use the bounded navigation, points in the same room short direct hops.
local function step(t: any): any return t end
Config.JOBS={
 Reception={
  step{sit=true,pose="type",seconds={14,24}},
  step{at="greet",pose="greet",seconds={3,4}},
  step{sit=true,pose="type",seconds={10,18}},
  step{at="printer",pose="typeStand",item="badge",prop=true,seconds={3,4},optional=true},
  step{at="greet",pose="greet",item=false,seconds={2,3}},
 },
 Security={
  step{sit=true,pose="type",seconds={16,26}},
  step{at="patrol1",pose="scan",seconds={4,6},optional=true},step{at="patrol2",pose="scan",seconds={4,6},optional=true},
  step{at="patrol3",pose="scan",seconds={4,6},optional=true},step{at="patrol4",pose="scan",seconds={4,6},optional=true},
  step{at="patrol5",pose="scan",seconds={4,6},optional=true},step{at="patrol6",pose="scan",seconds={5,7},optional=true},
  step{at="patrol7",pose="scan",seconds={3,5},optional=true},
 },
 Facilities={
  step{at="bench",pose="inspect",seconds={8,12},optional=true},
  step{at="lift",pose="inspect",prop=true,seconds={10,14},optional=true},
  step{at="bms",pose="typeStand",seconds={8,12},optional=true},
  step{at="switchgear",pose="inspect",seconds={5,7},optional=true},
  step{at="batteries",pose="scan",seconds={4,6},optional=true},
  step{pose="phone",seconds={5,8}},
 },
 ["IT Support"]={
  step{sit=true,pose="type",seconds={18,30}},
  step{fault=true,pose="typeStand",item="laptop",seconds={10,15},every=2},
  step{sit=true,pose="type",seconds={12,20}},
  step{at="bench",pose="inspect",item="laptop",prop=true,seconds={8,12},optional=true},
 },
 Barista={
  step{at="machine",pose="pour",item="cup",prop=true,seconds={5,7}},
  step{at="hand",pose="reach",item="cup",seconds={2,3}},
  step{at="grinder",pose="stir",item=false,seconds={3,5}},
  step{at="machine",pose="pour",item="cup",prop=true,seconds={5,7}},
  step{at="hand",pose="reach",item="cup",seconds={2,3}},
  step{at="wipe",pose="wipe",item="sponge",seconds={4,6}},
 },
 Chef={
  step{at="range",pose="stir",item="spatula",prop=true,seconds={7,10}},
  step{at="oven",pose="inspect",item=false,seconds={3,5}},
  step{at="range",pose="stir",item="spatula",prop=true,seconds={6,9}},
  step{at="pass",via={"aisle"},pose="plate",item="plate",prop=true,seconds={3,4}},
  step{at="range",via={"aisle"},pose="stir",item="spatula",prop=true,seconds={6,9}},
 },
 ["Kitchen Team"]={
  step{at="servery",serve=true,pose="plate",seconds={20,30},when="lunch"},
  step{at="chop",pose="chop",item="knife",seconds={6,9},when="open"},
  step{at="sink",pose="wash",item="sponge",prop=true,seconds={5,7},when="open"},
  step{trays=true,pose="reach",item="tray",seconds={2,3},when="open"},
  step{at="dish",via={"dishVia"},pose="wash",item="sponge",prop=true,seconds={5,7},when="open"},
  step{at="chop",via={"dishVia"},pose="chop",item="knife",seconds={6,9},when="open"},
 },
 ["Cafe Host"]={
  step{at="greet",pose="greet",seconds={3,4}},
  step{at="table1",pose="wipe",item="sponge",seconds={4,6},optional=true},
  step{at="table2",pose="wipe",item="sponge",seconds={4,6},optional=true},
  step{at="greet",pose="typeStand",item=false,seconds={6,10}},
 },
 Fleet={
  step{sit=true,pose="type",seconds={16,26}},
  step{at="keys",pose="reach",item="keys",seconds={2,3},optional=true},
  step{at="ev2",pose="plug",item=false,prop=true,seconds={6,8},optional=true},
  step{sit=true,pose="type",seconds={14,22}},
  step{at="ev4",pose="plug",prop=true,seconds={6,8},optional=true},
 },
 ["Hotel Reception"]={
  step{sit=true,pose="type",seconds={14,24}},
  step{at="greet",pose="greet",seconds={3,4},optional=true},
  step{at="printer",pose="typeStand",item="badge",prop=true,seconds={3,4},optional=true},
 },
 Housekeeping={
  step{at="cart",pose="reach",item="mopcart",seconds={2,3},optional=true},
  step{at="room1",pose="wipe",seconds={6,9},optional=true},step{at="room2",pose="wipe",seconds={6,9},optional=true},
  step{at="room3",pose="wipe",seconds={6,9},optional=true},step{at="room4",pose="wipe",seconds={6,9},optional=true},
  step{at="cart",pose="reach",item=false,seconds={2,3},optional=true},
 },
 Cleaner={
  step{at="cart",pose="reach",item="mopcart",seconds={2,3}},
  step{route="Mop",pose="wipe",item="mopcart",seconds={3,4}},
  step{visit="Clean",pose="wipe",item="mopcart",seconds={6,9}},
  step{visit="Clean",pose="wipe",item="mopcart",seconds={6,9}},
  step{at="cart",pose="reach",item=false,seconds={3,5}},
 },
 -- the apprentices' trainer between tour and training session: plans at the HR desk, takes calls, coaches
 -- an apprentice at their desk (special step "coach", StaffEvents)
 ["Training Lead"]={
  step{sit=true,pose="type",seconds={18,30}},
  step{special="coach",pose="inspect",seconds={10,14}},
  step{sit=true,pose="type",seconds={14,22}},
  step{pose="phone",seconds={5,8}},
 },
 Mailroom={
  step{at="sort",pose="sort",item="parcel",seconds={6,9}},
  step{at="lockers",via={"west"},pose="reach",item="parcel",prop=true,seconds={3,4}},
  step{at="pigeon",pose="sort",item=false,seconds={4,6}},
  step{at="sort",via={"west"},pose="sort",item="parcel",seconds={5,7}},
 },
}
-- The kitchen serves lunch between these company hours (and while anybody still queues).
Config.LUNCH_SERVICE={11.5,15.7}
-- Operations staff take a short break in place every OPS_BREAK seconds (seeded), one per job at a time.
Config.OPS_BREAK={300,480};Config.OPS_BREAK_SECONDS={18,28}
-- Share of coffee breaks that become a wellness break (gym, sauna, showers): (seed + n) % 10 == 0.
Config.WELLNESS_EVERY=10
-- Optional task fields: departments (set of matching departments), access (required RoomAccess), nearest (pure distance).
Config.TASKS={
 researcher={{id="RunExperiment",type="Computer",department="research",seconds={45,180},state="RESEARCH",priority=30},
 {id="UseWhiteboard",type="Whiteboard",department="research",seconds={30,80},state="RESEARCH",priority=18},
 {id="AnalyzeModel",type="Computer",department="evaluation",seconds={40,100},state="MODEL_REVIEW",priority=20},
 {id="ArchitectureStudy",type="Computer",department="design",seconds={45,120},state="RESEARCH",priority=22},
 {id="RunExperiment",type="LabBench",department="research",departments={research=true,evaluation=true},seconds={35,110},state="RESEARCH",priority=24}},
 engineer={{id="WriteCode",type="Computer",department="engineering",seconds={30,120},state="WORKING",priority=30},
 {id="MonitorTraining",type="Computer",department="training",seconds={45,120},state="MONITOR_TRAINING",priority=26},
 {id="InspectServer",type="ServerRack",department="compute",seconds={20,60},state="SERVER_CHECK",priority=15,via="Pickup"}, -- via: fetch a blade at the server cart (Pickup) in the rack's room first
 {id="ReviewModel",type="Computer",department="evaluation",seconds={40,100},state="MODEL_REVIEW",priority=18},
 {id="InspectHardware",type="LabBench",department="engineering",access="compute",seconds={25,75},state="SERVER_CHECK",priority=16}},
 curator={{id="CleanDataset",type="Computer",department="data",seconds={45,140},state="DATA_REVIEW",priority=35},
 {id="CheckQuality",type="Computer",department="data",seconds={45,100},state="DATA_REVIEW",priority=30},
 {id="MonitorPipeline",type="Pipeline",department="data",seconds={25,70},state="DATA_REVIEW",priority=18}},
 marketer={{id="AnalyzeMarket",type="Computer",department="growth",seconds={45,140},state="MARKETING",priority=35},
 {id="PlanLaunch",type="Computer",department="deployment",seconds={45,100},state="MARKETING",priority=30},
 {id="CheckCustomers",type="Computer",department="growth",seconds={35,110},state="MARKETING",priority=25}},
 support={{id="CampusOperations",type="Service",seconds={80,180},state="WORKING",priority=20}},
}
function Config.seed(index: number,owner: number): number return (index*7919+owner*31)%104729 end
-- 32-bit integer hash (lowbias32); the 16-bit split multiply stays exact in doubles, so every
-- server derives identical identities. Used for looks, presentation and names.
local function mul32(a: number,b: number): number
 local ah,al=a//65536,a%65536;local bh,bl=b//65536,b%65536
 return ((ah*bl+al*bh)%65536*65536+al*bl)%4294967296
end
function Config.hash(x: number): number
 x=math.floor(x)%4294967296
 x=bit32.bxor(x,bit32.rshift(x,16));x=mul32(x,0x7feb352d)
 x=bit32.bxor(x,bit32.rshift(x,15));x=mul32(x,0x846ca68b)
 return bit32.bxor(x,bit32.rshift(x,16))
end
-- Presentation from an appearance seed: about half of all seeds are feminine.
function Config.feminine(seed: number): boolean
 return Config.hash(seed*2+1)%2==0
end
-- Presentation of the generated employee (index, owner). Operations staff 301..312 alternate per
-- company so paired posts (reception, security, kitchen) are never all one gender.
function Config.isFeminine(index: number,owner: number): boolean
 if index>300 and index<=300+#Config.OPERATIONS_JOBS then return (index+Config.hash(owner))%2==0 end
 return Config.feminine(Config.seed(index,owner))
end
function Config.personality(index: number,owner: number): any
 return Config.personalityFromSeed(Config.seed(index,owner))
end
-- Personality from an appearance seed (generated or from a persistent staff profile).
function Config.personalityFromSeed(seed: number): any
 seed=math.floor(math.abs(seed))
 return {seed=seed,walkSpeed=11+(seed%31)/10,social=(seed%100)/100,breakEvery=180+seed%240,
  coffee=seed%3~=0,start=7.75+(seed%76)/60,finish=16.5+(seed%91)/60,lunch=11.75+(seed%106)/60,
  scheduleOffset=seed%91,workStyle=seed%4,meetingFrequency=160+seed%280,
  stairs=((seed//7)%100)/100} -- 0 = always takes the lift, 1 = loves the stairs
end
-- True when a station's department satisfies a task definition.
function Config.departmentMatch(task: any,department: string?): boolean
 if department==nil then return false end
 if task.departments then return task.departments[department]==true end
 return task.department==department
end
-- Workdays are visible in a practical session length; night passes faster than working hours.
function Config.hour(seconds: number): number
 local t=seconds%1200
 return (if t<900 then 8+t/90 else 18+(t-900)*14/300)%24
end
function Config.priority(role: string,task: any,event: any): number
 local p=task.priority
 if event.training then
  if task.id=="MonitorTraining" then p+=50 elseif task.id=="InspectServer" then p+=40 elseif task.id=="InspectHardware" then p+=20 elseif task.id=="AnalyzeModel" then p-=20 end
 end
 if event.research and task.id=="RunExperiment" then p+=60 end
 if event.review and (task.id=="AnalyzeModel" or task.id=="ReviewModel") then p+=65 end
 if event.live and role=="marketer" then p+=45 end
 if event.hardware and (task.id=="InspectServer" or task.id=="InspectHardware") then p+=if task.id=="InspectServer" then 65 else 55 end
 if event.data and role=="curator" then p+=35 end
 return p
end
function Config.productive(state: string): number
 if state=="WORKING" or state=="RESEARCH" or state=="DATA_REVIEW" or state=="MARKETING" or state=="SERVER_CHECK" or state=="MONITOR_TRAINING" or state=="MODEL_REVIEW" then return 1 end
 if state=="MEETING" or state=="TALKING" then return .8 end
 if state=="COFFEE_BREAK" or state=="LUNCH" then return .4 end
 if state=="LEAVING" or state=="OFF_DUTY" then return 0 end
 return .75
end
return Config
