--!strict
-- Dialogue: what the people in a company say when you talk to them (TalkService / TalkPanel).
-- AUTHORED, not a language model: every line is a template picked deterministically from the person's
-- appearance seed + the campus day + the topic (several templates per topic), and filled ONLY with real
-- game state:
--   subject = the person, read from the rig: name, RoleId + Role (job title), PersonalitySeed,
--             Activity / Task / Pose, the room they stand in (+ level label, kind, desks in use), their
--             home desk (room, department, desks in use), lunch phase, Skill k and wage $/s (profile).
--   context = who is asking ("owner" or "visitor"), the company facts (Dialogue.facts over the owner's
--             session data/live), places for directions (Dialogue.places over BuildingPlan) and the
--             counts TalkService measures (visitors now/today, conversations today, open faults, desks
--             and desks in use, café seats, guest cards, cars, lunches served when the life package
--             reports them).
-- The building explains itself: "What's this room for?" (room kind / department of the plan room the
-- person stands in), "What does your team do?" (home desk room + department + the role's real effect
-- from EmpireConfig.ROLES.desc) and a floor-by-floor tour (BuildingPlan.levelName for every level).
-- Pure: no Roblox services, so every role x job x state is tested headlessly (tests/talk).
-- Tone: personalityFromSeed(seed).social → confident (>= .66) / calm / shy (< .33).
-- Who may talk: the owner with everyone in the company; visitors only with front-of-house jobs
-- (Dialogue.isPublicJob: reception, hotel reception, security, barista, café host, chef).
-- Flow: lines.options = up to 3 topics + "bye"; Dialogue.step answers one option and returns the next
-- options (follow-ups such as the places of "Where is …?" first, then the topics not asked yet).
-- staffops: absences ("Mia Weber is on vacation today (back on day 14)", "Jonas Klein is sick today") come
-- from CompanyOps.presence over the saved team (facts.away), apprentices from CompanyOps.apprentice
-- (facts.apprentices: training day, skill, 40 % wage), rack faults from CompanyOps.faults; the Training Lead
-- (kind "trainer"), first-day hires, rack repairs, the apprentice tour ("Tour:<room id>"), training session,
-- shadowing and practice have their own lines. Night crew shifts come from the rig's ShiftStart / ShiftEnd.
-- "Who's away today?" uses the company day the staff animation uses (StaffRota.workday: from 06:00 to 08:00
-- already the coming day), read from live.workforce.hour (StaffService); without it the saved day.
local Config=require(script.Parent.Config.EmployeeConfig)
local EmpireConfig=require(script.Parent.Config.EmpireConfig)
local Plan=require(script.Parent.Config.BuildingPlan)
local Departments=require(script.Parent.Config.DepartmentConfig)
local Format=require(script.Parent.Format)
local ModelMath=require(script.Parent.ModelMath)
local EmpireMath=require(script.Parent.EmpireMath)
local Ops=require(script.Parent.CompanyOps)
local Dialogue={}
Dialogue.MAX_OPTIONS=4 -- chips shown at once (incl. the goodbye chip)
Dialogue.DAY_SECONDS=1200 -- one campus day (EmployeeConfig.hour)
export type Option={id: string,text: string}
export type Answer={text: string,follow: {Option}?,close: boolean?}
export type Lines={kind: string,tone: string,viewer: string,greeting: string,topics: {Option},options: {Option},answers: {[string]:Answer},farewell: string}
export type Place={id: string,name: string,level: number,label: string,access: string,text: string}
-- Template chooser of one conversation: (topic key, variants) → one variant, stable per person + day.
type Vary=(string,{string})->string

-- Small helpers ------------------------------------------------------------------------------------
local function num(x: any,default: number?): number
 if typeof(x)=="number" and x==x and x>-math.huge and x<math.huge then return x end
 return default or 0
end
local function first(name: string): string return string.match(name,"^%s*(%S+)") or name end
local function plural(n: number,word: string,many: string?): string
 local whole=math.floor(n+.5)
 return Format.int(whole).." "..(if whole==1 then word else (many or word.."s"))
end
-- "Data & model foundations" → "data & model foundations" (acronyms such as "AI …" stay)
local function lowerFirst(text: string): string
 if string.match(text,"^%u%u") then return text end
 return string.lower(string.sub(text,1,1))..string.sub(text,2)
end
-- "Nimbus Labs'" / "Noah's"
local function possessive(name: string): string return if string.sub(name,-1)=="s" then name.."'" else name.."'s" end
-- "the A, the B and the C"
local function roomList(names: {string}): string
 local out={}
 for _,n in names do table.insert(out,"the "..n) end
 if #out<=1 then return out[1] or "" end
 return table.concat(out,", ",1,#out-1).." and "..out[#out]
end
local function keyHash(key: string): number
 local h=7;for i=1,#key do h=(h*31+string.byte(key,i))%1000003 end;return h
end
-- Deterministic choice per person, campus day and topic (identical on every server).
local function pick<T>(list: {T},seed: number,day: number,key: string): T
 return list[Config.hash(math.floor(math.abs(seed))*7+math.floor(math.abs(day))*131+keyHash(key))%#list+1]
end
local function fill(text: string,vars: {[string]:string}): string
 return (string.gsub(text,"{(%w+)}",function(k: string): string return vars[k] or ("{"..k.."}") end))
end
-- "8:15", "13:05" (EmployeeConfig hours are fractional, 12.5 = 12:30)
function Dialogue.clock(hour: number): string
 local h=math.floor(num(hour))%24;local m=math.floor((num(hour)%1)*60+.5)
 if m>=60 then h=(h+1)%24;m=0 end
 return string.format("%d:%02d",h,m)
end
-- Spoken durations: "45 seconds", "3 min", "2 min 10 s", "1 h 20 min".
function Dialogue.spoken(seconds: number): string
 local s=math.max(0,math.floor(num(seconds)+.5))
 if s<60 then return plural(s,"second") end
 if s<600 then local m,r=s//60,s%60;return if r==0 then tostring(m).." min" else string.format("%d min %d s",m,r) end
 if s<3600 then return tostring(math.floor(s/60+.5)).." min" end
 local h,m=s//3600,math.floor((s%3600)/60+.5)
 if m==60 then h+=1;m=0 end
 return if m==0 then tostring(h).." h" else string.format("%d h %d min",h,m)
end
function Dialogue.initials(name: string): string
 local out=""
 for word in string.gmatch(name,"%S+") do out..=string.sub(word,1,1);if #out>=2 then break end end
 return string.upper(out)
end
function Dialogue.tone(seed: number): string
 local social=Config.personalityFromSeed(num(seed)).social
 return if social>=.66 then "confident" elseif social<.33 then "shy" else "calm"
end

-- Jobs -------------------------------------------------------------------------------------------
local HIRED={researcher=true,engineer=true,curator=true,marketer=true}
local PUBLIC={reception=true,hotel=true,security=true,barista=true,host=true,chef=true}
-- Topic family of a person: the four hired roles by RoleId, operations staff by their job title
-- (EmployeeConfig.OPERATIONS_JOBS incl. jobs added later such as "Hotel Reception", "Housekeeping").
function Dialogue.kind(roleId: string?,job: string?): string
 if roleId and HIRED[roleId] then return roleId end
 local j=string.lower(job or "")
 if string.find(j,"hotel",1,true) then return "hotel" end
 if string.find(j,"reception",1,true) then return "reception" end
 if string.find(j,"security",1,true) or string.find(j,"guard",1,true) then return "security" end
 if string.find(j,"housekeep",1,true) then return "housekeeping" end
 if string.find(j,"clean",1,true) or string.find(j,"janitor",1,true) then return "cleaner" end
 if j=="it" or string.find(j,"^it ") or string.find(j,"it support",1,true) then return "it" end
 if string.find(j,"barista",1,true) then return "barista" end
 if string.find(j,"chef",1,true) or string.find(j,"cook",1,true) then return "chef" end
 if string.find(j,"kitchen",1,true) then return "kitchen" end
 if string.find(j,"host",1,true) then return "host" end
 if string.find(j,"fleet",1,true) or string.find(j,"mechanic",1,true) or string.find(j,"driver",1,true) then return "fleet" end
 if string.find(j,"facilit",1,true) or string.find(j,"maintenance",1,true) then return "facilities" end
 if string.find(j,"mail",1,true) then return "mailroom" end
 if string.find(j,"training lead",1,true) or string.find(j,"trainer",1,true) then return "trainer" end
 return "ops"
end
function Dialogue.isPublicKind(kind: string): boolean return PUBLIC[kind]==true end
-- Front-of-house jobs visitors (other players) may talk to; EmployeeRigDesign makes their prompt Public.
function Dialogue.isPublicJob(job: string?): boolean
 if job==nil then return false end
 return PUBLIC[Dialogue.kind(nil,job)]==true
end

-- Company facts from the owner's session (plain data; same numbers the assistant briefing shows) ----
local function trend(history: any): (number?,number?)
 if typeof(history)~="table" or #history<2 then return nil,nil end
 local function avg(from: number,to: number): number
  local sum,n=0,0
  for i=math.max(1,from),to do local h=history[i];sum+=if typeof(h)=="table" then num(h.profit) else 0;n+=1 end
  return if n>0 then sum/n else 0
 end
 local last=#history;local window=math.min(6,math.floor(last/2))
 local recent=avg(last-window+1,last);local before=avg(last-2*window+1,last-window)
 return recent,recent-before
end
function Dialogue.facts(data: any,live: any): any
 local e: any=if typeof(data.empire)=="table" then data.empire else {}
 local lv: any=if typeof(live)=="table" then live else {}
 local f: any={company=if typeof(data.company)=="table" then tostring(data.company.name) else "the company",
  cash=num(data.money),revenue=num(lv.revenue),cost=num(lv.cost),users=num(lv.users)}
 f.profitPerMin=(f.revenue-f.cost)*60
 f.trendRecent,f.trendDelta=trend(e.history)
 local liveCount,best=0,nil
 local models: any=if typeof(data.models)=="table" then data.models else {}
 for _,id in (if typeof(data.modelOrder)=="table" then data.modelOrder else {}) :: {any} do
  local m=models[id]
  if typeof(m)=="table" and m.status~="training" then
   if not best or num(m.overall)>num(best.overall) then best=m end
   if m.status=="live" then liveCount+=1 end
  end
 end
 f.live=liveCount
 f.best=if best then {name=tostring(best.name),overall=num(best.overall)} else nil
 local stats: any=if typeof(data.stats)=="table" then data.stats else {}
 f.trained=num(stats.modelsTrained);f.released=num(stats.modelsReleased)
 local t=data.training
 if typeof(t)=="table" then
  local m=models[t.modelId];local total=num(t.workTotal);local done=num(t.workDone)
  local ok,rate=pcall(EmpireMath.trainingRate,data.gpus,total,e)
  local r=if ok then num(rate) else 0
  f.training={model=if typeof(m)=="table" then tostring(m.name) else "the new model",progress=if total>0 then math.clamp(done/total,0,1) else 0,
   eta=if r>0 then math.max(0,(total-done)/r) else nil,decision=typeof(t.event)=="table" and t.event.pending==true}
 end
 local staff=0;f.roles={}
 local employees: any=if typeof(e.employees)=="table" then e.employees else {}
 for _,role in EmpireConfig.ROLES do local n=num(employees[role.id]);f.roles[role.id]=n;staff+=n end
 f.staff=staff
 local office=EmpireConfig.OFFICES[num(e.office,1)]
 f.cap=if office then office.staff else nil
 local open,waiting=0,0
 for _,a in (if typeof(e.applicants)=="table" then e.applicants else {}) :: {any} do
  if typeof(a)=="table" then if a.st=="new" then open+=1 else waiting+=1 end end
 end
 f.applicantsOpen=open;f.applicantsWaiting=waiting
 local research: any=if typeof(e.research)=="table" then e.research else {}
 local job=e.researchJob
 if typeof(job)=="table" then
  local def=EmpireConfig.find(EmpireConfig.RESEARCH,job.id)
  local seconds=math.max(1,num(job.seconds,1))
  f.research={name=if def then def.name else tostring(job.id),progress=math.clamp(num(job.elapsed)/seconds,0,1),left=math.max(0,seconds-num(job.elapsed))}
 end
 f.points=num(e.points)
 local doneCount=0
 for _,def in EmpireConfig.RESEARCH do
  if research[def.id] then doneCount+=1
  elseif not f.nextResearch and (not def.prereq or research[def.prereq]) then f.nextResearch={name=def.name,points=def.points,cost=def.cost} end
 end
 f.researchDone=doneCount;f.researchTotal=#EmpireConfig.RESEARCH
 local okData,stock=pcall(ModelMath.dataSummary,if typeof(data.data)=="table" then data.data else {})
 f.tokens=if okData then num(stock.total) else 0;f.quality=if okData then num(stock.quality) else 0
 local okFleet,fleet=pcall(ModelMath.fleet,if typeof(data.gpus)=="table" then data.gpus else {})
 f.vram=if okFleet then num(fleet.vram) else 0;f.slots=if okFleet then num(fleet.slotsUsed) else 0
 -- staffops: who is away today, apprentices, rack faults (same functions the economy uses)
 f.day=Ops.day(e)
 -- the shift day (StaffRota.workday): between 06:00 and 08:00 the people arriving are the coming day's
 local wf: any=lv.workforce
 local hour=if typeof(wf)=="table" and typeof(wf.hour)=="number" then wf.hour else nil
 f.workday=f.day+(if hour then Config.workdayOffset(hour) else 0)
 local view: any=if f.workday~=f.day then setmetatable({calendar={day=f.workday}},{__index=e}) else e
 f.away={};f.awayCount={vacation=0,sick=0,trip=0,leave=0};f.apprentices={};f.apprenticeCount=0
 local profiles: any=if typeof(e.staffProfiles)=="table" then e.staffProfiles else {}
 for _,role in EmpireConfig.ROLES do
  if num(employees[role.id])<=0 then continue end
  local list: any=profiles[role.id]
  local okP,presence=pcall(Ops.presence,view,role.id)
  for i,state in (if okP and typeof(presence)=="table" then presence else {}) :: {string} do
   local p=if typeof(list)=="table" then list[i] else nil
   local name=if typeof(p)=="table" and typeof(p.n)=="string" then p.n else nil
   local seed=if typeof(p)=="table" and typeof(p.s)=="number" and p.s==p.s then math.floor(math.abs(p.s))%2147483647 else nil
   if state~="present" and name then
    table.insert(f.away,{name=name,role=role.id,state=state,back=f.workday+1})
    f.awayCount[state]=(f.awayCount[state] or 0)+1
   end
   if seed and typeof(e.apprentices)=="table" then
    local entry=e.apprentices[tostring(seed)]
    local skill=Ops.apprentice(e,seed,f.day)
    if skill and typeof(entry)=="table" then
     local age=math.max(0,f.day-num(entry.day,f.day))
     f.apprentices[seed]={name=name or "an apprentice",role=role.id,day=age+1,skill=skill,graduates=num(entry.day,f.day)+Ops.APPRENTICE.graduateDays}
     f.apprenticeCount+=1
    end
   end
  end
 end
 local okF,faults=pcall(Ops.faults,e)
 f.rackFaults=if okF and typeof(faults)=="table" then #faults else 0
 f.stage=Ops.stageIndex(e)
 return f
end

-- Places for "Where is …?" -------------------------------------------------------------------------
-- Building-local geometry → spoken directions. Entering from the street you walk +Z, so +X (east
-- wing, e.g. the café) is on your LEFT and -X (west wing, visitor lounge) on your RIGHT.
local function levelPhrase(tier: number,level: number): string
 if level<0 then return "down on B1"
 elseif level==0 then return "on the ground floor (G)"
 elseif level==Plan.roofLevel(tier) then return "up on the roof (R)" end
 return "on level "..Plan.levelLabel(tier,level)
end
function Dialogue.describe(room: any,tier: number,fromLevel: number?): string
 local cx=(room.x1+room.x2)/2;local cz=(room.z1+room.z2)/2
 local where={}
 if room.pavilion then table.insert(where,"in the pavilion behind the main building")
 elseif room.level<0 and cx>-22 and cx<22 and cz>36 then table.insert(where,"right by the lift")
 else
  if cx<-22 then table.insert(where,"on the right as you come in from the street")
  elseif cx>22 then table.insert(where,"on the left as you come in from the street")
  else table.insert(where,"in the middle of the building") end
  if cz<-16 then table.insert(where,"at the front") elseif cz>54 then table.insert(where,"at the back") end
 end
 local text="The "..room.name.." is "..levelPhrase(tier,room.level)..", "..table.concat(where,", ").."."
 if fromLevel~=nil then
  if fromLevel==room.level then text..=" It's on this floor."
  else text..=" Take the lift or the stairs behind the atrium to "..Plan.levelLabel(tier,room.level).."." end
 end
 return text
end
-- Rooms by id in the order given (unknown or hidden rooms are skipped).
function Dialogue.places(tier: number,ids: {string},fromLevel: number?): {Place}
 local out: {Place}={}
 for _,id in ids do
  local r: any=Plan.room(tier,id)
  if r and not r.hidden then
   table.insert(out,{id=r.id,name=r.name,level=r.level,label=Plan.levelLabel(tier,r.level),access=r.access,text=Dialogue.describe(r,tier,fromLevel)})
  end
 end
 return out
end
-- Which places a person points to (front desk staff know the visitor routes; the owner gets the
-- rooms a founder looks for). Only public rooms for visitors.
local PLACE_IDS: {[string]:{[string]:{string}}}={
 owner={reception={"G_CAFE","F_BOARDROOM","F_OFFICE","B1_DATAHALL","P0_GYM","R_TERRACE"},
  security={"P1_SECURITY","B1_GARAGE","G_COMPUTE","B1_DATAHALL"},hotel={"G_CAFE","B1_GARAGE","G_VISITOR"},
  host={"G_CAFE","G_VISITOR","R_TERRACE"}},
 visitor={reception={"G_CAFE","G_SHOWROOM","G_VISITOR"},security={"G_VISITOR","G_SHOWROOM","G_CAFE"},hotel={"G_CAFE","G_VISITOR","G_SHOWROOM"},
  host={"G_CAFE","G_SHOWROOM","G_VISITOR"},barista={"G_CAFE","G_SHOWROOM","G_VISITOR"},chef={"G_CAFE","G_SHOWROOM","G_VISITOR"}},
}
function Dialogue.placeIds(viewer: string,kind: string): {string}
 local byViewer=PLACE_IDS[viewer] or PLACE_IDS.visitor
 return byViewer[kind] or {}
end

-- What the building has -------------------------------------------------------------------------------
-- Floor by floor from the plan: "B1 garage, data hall & building services · G reception, … · R roof terrace".
function Dialogue.floorGuide(tier: number): string
 local parts={}
 for _,level in Plan.levels(tier) do table.insert(parts,Plan.levelLabel(tier,level).." "..lowerFirst(Plan.levelName(tier,level))) end
 return table.concat(parts," · ")
end
-- What a department does (names from DepartmentConfig; the wording matches its descriptions).
local DEPT_TEXT: {[string]:string}={
 data="Our training data gets collected, filtered, cleaned and tokenized here. Better data makes the next model better.",
 design="Here we decide how big a new model gets and what it should be good at.",
 research="The experiments behind our research projects happen here.",
 evaluation="Every model gets benchmarked here before it ships: coding, reasoning, math, creativity, knowledge and reliability.",
 engineering="The training code gets written here, and models get ready to train on our GPUs.",
 training="From here we watch the GPUs while a model trains: progress, loss and the decisions along the way.",
 growth="Our models meet users and API customers here: pricing, target markets and support.",
 deployment="Launches get prepared here: pick a trained model, set prices and a target market, then market it.",
 operations="Hiring, onboarding and company admin happen here, so every team stays staffed.",
}
-- What a room of a given plan kind is for (rooms without a department).
local ROOM_TEXT: {[string]:string}={
 lobby="This is the {room}. Visitors check in at the desk, and the speed gates behind it keep the offices for people with a company card.",
 visitor_lounge="This is the {room}. Guests and job applicants wait here until someone picks them up.",
 cafe="This is the {room}. The kitchen serves lunch to the whole team here, and anyone can buy coffee and snacks. Snacks give you a speed boost for a while.",
 kitchen_boh="This is the {room}. The chef and the kitchen team cook lunch for the whole company here.",
 showroom="This is the {room}. We show our models to visitors here.",
 atrium="This is the {room}. The lift and the main stairs connect every floor from here.",
 first_ai="This is the {room}, a small team room on the ground floor. Overflow desks for the team are in here.",
 project_meeting="This is the {room}. Teams meet here to plan projects and review models.",
 meeting="This is the {room}, a meeting room. Teams meet here to plan and review their work.",
 boardroom="This is the {room}. Big decisions and model reviews happen around this table.",
 pantry="This is the {room}. Coffee and snacks for the team between tasks.",
 lounge="This is the {room}. People come here for a short break.",
 recovery="This is the {room}. A quiet place to recharge after a workout or the sauna.",
 terrace="This is the {room}. Fresh air between meetings.",
 roof_terrace="This is the {room}. Fresh air and a view over the city, right on top of the building.",
 focus="This is the {room}, a focus room: one desk for quiet, concentrated work.",
 phone="These are the {room}, for private calls.",
 print="This is the {room}: printers, paper and office supplies.",
 hr="This is the {room}. Hiring, onboarding and company admin happen here.",
 datahall="This is the {room}. Our GPU racks live here, and every GPU you install lights up a blade.",
 compute="This is {room}. The servers and the cooling are watched from here.",
 itdesk="This is the {room}. Broken screens and laptops end up here.",
 garage="This is the {room}. The company cars park and charge down here.",
 fleet="This is the {room}. The company cars are looked after from here.",
 workshop="This is the {room}. Cars and hardware get fixed down here.",
 storage="This is {room}. New hardware and supplies are stored here.",
 delivery="This is {room}. Supplies arrive here, and the cleaning carts are parked here.",
 mailroom="This is the {room}. Post and parcels for the whole building are sorted here.",
 gym="This is the {room}. A workout here gives you a speed boost for a while.",
 sauna="This is the {room}. A sauna session gives you a speed boost for a while.",
 showers="These are the {room}, for after a workout.",
 restrooms="These are the {room}.",wc="These are the {room}.",
 security="This is {room}. The camera feeds of the building come in here.",
 founder_office="This is the {room}. It's yours.",founder_bath="This is the {room}, part of the founder suite.",founder_assist="This is the {room}. Your assistant works here.",
 founder_library="This is the {room}, a quiet place for the founder.",archive="This is the {room}. Company records are kept here.",
 vault="This is the {room}. Our trained models are kept safe here.",prototype="This is the {room}. Hardware prototypes are built in here.",
 plant="This is the {room}: power and cooling for the whole building.",ups="This is the {room}. The batteries keep the servers running if the power fails.",
 machine="This is the {room}. The lift motor lives up here.",roof_tech="This is the {room}: cooling and ventilation.",roof_solar="This is the {room}. It makes some of our power.",
 garden_lobby="This is the {room}. It connects the main building with the wellness pavilion.",
 pavilion_roof="This is the {room}, a green roof on top of the pavilion.",
 -- garage stage and guest house (buildings request 6, added by integrate; corridors and stairs get no purpose)
 garage_lab="This is the {room}. The whole team works in here until the company moves into its first real office.",
 garage_founder="This is the {room}. It's yours.",garage_assist="This is the {room}. Your assistant works here.",
 garage_wc="This is the {room}.",garage_porch="This is the {room}, the way into the garage.",
 hotel_lobby="This is the {room}. Guests of the guest house check in at the desk here.",
 hotel_breakfast="This is the {room}. Guests of the guest house have breakfast here in the morning.",
 hotel_pantry="This is the {room}. Breakfast for the guest house is prepared here.",
 hotel_service="This is the {room}. Housekeeping keeps the linen and the cleaning carts here.",
 hotel_office="This is the {room}. Luggage is stored here and the guest house is run from here.",
 hotel_workshop="This is the {room}. Visiting client teams hold their workshops here.",
 guestroom="This is {room}, one of the guest rooms. Visiting clients stay here overnight.",
}
-- Desks in a room: "8 desks in here, 5 in use right now."
local function deskLine(desks: any,busy: any,where: string): string
 if typeof(desks)~="number" or desks<=0 then return "" end
 local text=" "..plural(desks,"desk").." "..where
 if typeof(busy)=="number" then text..=", "..Format.int(math.min(busy,desks)).." in use right now" end
 return text.."."
end
-- "What's this room for?" about the plan room the person stands in.
local function roomText(subject: any,c: any): string
 local name=tostring(subject.room or "room")
 local dept=subject.roomDept
 local d=if typeof(dept)=="string" then (Departments.DEPARTMENTS :: any)[dept] else nil
 local text
 if d and subject.roomKind=="focus" then text="This is "..name..", a focus room of "..d.name..": one desk for quiet, concentrated work."
 elseif d and DEPT_TEXT[dept] then
  -- "the Data Operations A" needs no "part of Data Operations"
  text="This is the "..name..(if string.find(name,d.name,1,true) then "" else ", part of "..d.name)..". "..DEPT_TEXT[dept]
 elseif typeof(subject.roomKind)=="string" and ROOM_TEXT[subject.roomKind] then text=fill(ROOM_TEXT[subject.roomKind],{room=name})
 else text="This is the "..name.."." end
 text..=deskLine(subject.roomDesks,subject.roomBusy,"in here")
 if subject.roomKind=="cafe" and typeof(c.dining)=="number" then text..=" "..plural(c.dining,"seat").." at the tables." end
 if subject.roomCamera==true then text..=" It's covered by the security cameras." end
 local label=if typeof(subject.roomAccess)=="string" and subject.roomAccess~="staff" then (Plan.CLASS_LABEL :: any)[subject.roomAccess] else nil
 if typeof(label)=="string" then text..=" The door sign says: "..label.."." end
 return text
end
-- Only rooms with an authored purpose are offered ("What's this room for?" never answers "the Stairs").
function Dialogue.explainsRoom(subject: any): boolean
 if typeof(subject.roomKind)~="string" then return false end
 if ROOM_TEXT[subject.roomKind] then return true end
 return typeof(subject.roomDept)=="string" and DEPT_TEXT[subject.roomDept]~=nil
end
-- Building tour: floors, what each floor is for, the visitor areas, desks.
local function tourText(c: any,owner: boolean,V: Vary): string
 local tier=num(c.tier,1)
 local company=tostring(c.company or (c.facts and c.facts.company) or "The company")
 local top=Plan.levelLabel(tier,Plan.founderLevel(tier))
 local text=fill(V("tour",{"{company} headquarters has {floors} from G up to {top}, plus B1 below and the roof on top.",
  "We have {floors} here, G up to {top}, plus B1 and the roof."}),{company=possessive(company),floors=plural(Plan.floors(tier),"floor"),top=top})
 text..=" Floor by floor: "..Dialogue.floorGuide(tier).."."
 local b=c.building
 local public=if typeof(b)=="table" and typeof(b.publicRooms)=="table" and #b.publicRooms>0 then roomList(b.publicRooms) else nil
 if owner then
  if typeof(c.desks)=="number" and c.desks>0 then
   text..=" "..plural(c.desks,"computer desk").." in total"
   if typeof(c.desksBusy)=="number" then text..=", "..Format.int(math.min(c.desksBusy,c.desks)).." in use right now" end
   text..="."
  end
  if public then text..=" Visitors may use "..public.."." end
 elseif public then
  text..=" As a visitor you're welcome in "..public..". Everything else needs a company card."
 end
 return text
end

-- Phrases ----------------------------------------------------------------------------------------
local ROLE_NAME: {[string]:string}={researcher="AI researcher",engineer="ML engineer",curator="data curator",marketer="growth manager"}
local JOB_PHRASE: {[string]:string}={reception="I run the front desk",hotel="I look after the hotel desk",security="I'm on security",facilities="I keep the building running",
 it="I'm IT support",barista="I'm the barista",chef="I'm the chef",kitchen="I'm on the kitchen team",host="I host the café",fleet="I look after the company cars",
 housekeeping="I'm on housekeeping",cleaner="I keep the place clean",mailroom="I run the mailroom",trainer="I train our apprentices",ops="I'm on the campus team"}
local function hello(hour: number): string
 return if hour>=5 and hour<12 then "Good morning" elseif hour>=12 and hour<17 then "Good afternoon" else "Good evening"
end
local function roomPhrase(subject: any): string
 if typeof(subject.room)~="string" or subject.room=="" then return "" end
 local label=if typeof(subject.level)=="string" then " ("..subject.level..")" else ""
 return " in the "..subject.room..label
end
local function count(f: any,key: string): number return num(f[key]) end
local function profitTrend(f: any): string
 local recent,delta=f.trendRecent,f.trendDelta
 if typeof(recent)~="number" or typeof(delta)~="number" then
  return "We make "..Format.money(num(f.profitPerMin)).." a minute right now."
 end
 local steady=math.abs(delta)<math.max(5,math.abs(recent)*.05)
 if steady then return "Profit is steady at "..Format.money(recent).." a minute." end
 if delta>0 then return "Profit is rising: "..Format.money(recent).." a minute, up "..Format.money(delta).."." end
 return "Profit is falling: "..Format.money(recent).." a minute, down "..Format.money(-delta).."."
end
local function modelsLine(f: any): string
 local live=count(f,"live")
 if live<=0 then
  if f.best then return "Nothing is live yet; our best trained model is "..f.best.name.." at "..string.format("%.1f",f.best.overall).." overall." end
  return "We haven't released a model yet."
 end
 local text=plural(live,"model").." live with "..Format.compact(count(f,"users")).." users."
 if f.best then text..=" Our best is "..f.best.name.." at "..string.format("%.1f",f.best.overall).." overall." end
 return text
end
local function trainingLine(f: any): string
 local t=f.training
 if typeof(t)~="table" then return "Nothing is training right now." end
 local text=t.model.." is training: "..Format.percent(t.progress,0).." done"
 if typeof(t.eta)=="number" then text..=", about "..Dialogue.spoken(t.eta).." to go." else text..=", but it's waiting for compute." end
 if t.decision then text..=" There's a decision waiting for you in the Lab." end
 return text
end
local function researchLine(f: any): string
 local r=f.research
 if typeof(r)=="table" then
  return "We're researching "..r.name..": "..Format.percent(r.progress,0).." done, "..Dialogue.spoken(r.left).." left."
 end
 local n=f.nextResearch
 if typeof(n)=="table" then
  local text="No research project is running. Next up is "..n.name..": "..Format.int(n.points).." RP and "..Format.money(n.cost).."."
  return text.." We have "..Format.int(math.floor(count(f,"points"))).." RP banked."
 end
 return "Every research project is finished. We have "..Format.int(math.floor(count(f,"points"))).." RP banked."
end
-- Research topic: the running project plus what comes after it (the work answer cites only the first part).
local function researchMore(f: any): string
 local text=researchLine(f)
 if typeof(f.research)=="table" then
  text..=" "..Format.int(count(f,"researchDone")).." of "..Format.int(count(f,"researchTotal")).." projects are done"
  if typeof(f.nextResearch)=="table" and f.nextResearch.name~=f.research.name then text..=", and "..f.nextResearch.name.." could come next" end
  text..="."
 end
 return text
end
local function dataLine(f: any): string
 return "We hold "..Format.tokens(count(f,"tokens")).." tokens of training data at "..Format.percent(count(f,"quality"),0).." quality."
end
local function hardwareLine(f: any): string
 local slots=count(f,"slots")
 if slots<=0 then return "We haven't installed a GPU yet." end
 return "We run "..plural(slots,"GPU slot").." with "..Format.int(count(f,"vram")).." GB of VRAM in total."
end
local function marketLine(f: any): string
 if count(f,"live")<=0 then return "Nothing is live, so there's no market data yet. Release a model in Deployment and I'll get to work." end
 return Format.compact(count(f,"users")).." users on "..plural(count(f,"live"),"live model")..". Revenue is "..Format.money(count(f,"revenue")*60).." a minute, costs "..Format.money(count(f,"cost")*60).."."
end
local function staffLine(f: any): string
 local text="We're "..plural(count(f,"staff"),"specialist").." on the team"
 if typeof(f.cap)=="number" then text..=", with desks for "..Format.int(f.cap) end
 return text.."."
end
local function menuLine(menu: any,seed: number,day: number,V: Vary): string
 if typeof(menu)~="table" or #menu==0 then return "The menu board is empty today." end
 local items={}
 for _,item in menu do table.insert(items,tostring(item.name).." "..Format.money(num(item.price))) end
 local special=menu[(math.floor(num(day))%#menu)+1]
 local text=fill(V("menu",{"Today we have {items}. My pick today: the {special}.","On the board today: {items}. I'd go for the {special}."}),
  {items=table.concat(items,", "),special=tostring(special.name)})
 if typeof(special.seconds)=="number" and special.seconds>0 then text..=" It keeps you quick on your feet for "..Dialogue.spoken(special.seconds).."." end
 return text
end

-- staffops: absences and apprentices -------------------------------------------------------------
local AWAY_TEXT: {[string]:string}={vacation="is on vacation today (back on day {back})",sick="is sick today",trip="is away on a client trip",leave="is on unpaid leave until our cash recovers"}
local function awayPhrase(a: any): string
 return a.name.." "..fill(AWAY_TEXT[a.state] or "is away today",{back=tostring(math.floor(num(a.back)))})
end
-- "Mia Weber is on vacation today (back on day 14), Jonas Klein is sick today and 3 more."
local function awayList(list: {any},max: number): string
 local parts={}
 for i=1,math.min(#list,max) do table.insert(parts,awayPhrase(list[i])) end
 local text
 if #parts<=1 then text=parts[1] or ""
 elseif #list<=max then text=table.concat(parts,", ",1,#parts-1).." and "..parts[#parts]
 else text=table.concat(parts,", ") end
 if #list>max then text..=" and "..plural(#list-max,"more","more") end
 return text.."."
end
local function awayText(f: any): string
 local list=if typeof(f.away)=="table" then f.away else {}
 local n=#list
 if n==0 then return "Everybody is in today: nobody on vacation, nobody sick." end
 local text=plural(n,"person","people")..(if n==1 then " is" else " are").." away today: "..awayList(list,3)
 local c=f.awayCount or {}
 local bits={}
 if num(c.vacation)>0 then table.insert(bits,Format.int(num(c.vacation)).." on vacation") end
 if num(c.sick)>0 then table.insert(bits,Format.int(num(c.sick)).." sick") end
 if num(c.trip)>0 then table.insert(bits,Format.int(num(c.trip)).." on client trips") end
 if num(c.leave)>0 then table.insert(bits,Format.int(num(c.leave)).." on unpaid leave") end
 if n>3 and #bits>0 then text..=" In total "..table.concat(bits,", ").."." end
 return text.." HR spreads vacations so only a few people per team are off on the same day."
end
-- Teammates of the same role who are away today ("From my team, Mia Weber is sick today.").
local function teamAway(f: any,roleId: any,selfName: any): string
 local list={}
 for _,a in (if typeof(f.away)=="table" then f.away else {}) :: {any} do if a.role==roleId and a.name~=selfName then table.insert(list,a) end end
 if #list==0 then return "" end
 return " From my team, "..awayList(list,2)
end
local function apprenticeOf(subject: any,f: any): any
 local a=if typeof(f.apprentices)=="table" then f.apprentices[math.floor(num(subject.seed))] else nil
 return if typeof(a)=="table" then a else nil
end
local function apprenticesText(f: any): string
 local list={}
 for _,a in (if typeof(f.apprentices)=="table" then f.apprentices else {}) :: {[any]:any} do table.insert(list,a) end
 if #list==0 then return "We have no apprentices right now. Hire one in the Empire app and I'll show them around." end
 table.sort(list,function(a: any,b: any): boolean if a.graduates~=b.graduates then return a.graduates<b.graduates end;return tostring(a.name)<tostring(b.name) end)
 local parts={}
 for i=1,math.min(#list,3) do local a=list[i];table.insert(parts,first(tostring(a.name)).." (day "..Format.int(a.day).." of "..Format.int(Ops.APPRENTICE.graduateDays)..", skill "..Format.int(a.skill)..")") end
 local text="We have "..plural(#list,"apprentice")..": "..table.concat(parts,", ")..(if #list>3 then " and more" else "").."."
 text..=" New apprentices get a tour on their first day, then training every morning at "..Dialogue.clock(Config.APPRENTICE.trainingHours[1])..". "
 text..=first(tostring(list[1].name)).." graduates on day "..Format.int(list[1].graduates).."."
 return text
end
local function tourRoomText(c: any,roomId: string): string
 local r: any=Plan.room(num(c.tier,1),roomId)
 if not r then return "I'm showing our apprentices around the building." end
 local d=if typeof(r.dept)=="string" then (Departments.DEPARTMENTS :: any)[r.dept] else nil
 local purpose=if d and DEPT_TEXT[r.dept] then DEPT_TEXT[r.dept] elseif ROOM_TEXT[r.kind] then fill(ROOM_TEXT[r.kind],{room=r.name}) else ""
 -- "This is the Café. The kitchen serves lunch ..." -> keep what comes after the room's own name
 if string.sub(purpose,1,5)=="This " or string.sub(purpose,1,6)=="These " then purpose=string.match(purpose,"^[^%.:]*[%.:]%s*(.*)$") or "" end
 return "I'm showing our new apprentices around: this is the "..r.name.."."..(if purpose~="" then " "..purpose else "")
end

-- What the person is doing right now (Activity + Task attributes, room, live numbers) ---------------
local TASK_TEXT: {[string]:(any,any,Vary)->string}={
 RunExperiment=function(s,f,V)
  if typeof(f.research)=="table" then return fill(V("task",{"I'm running experiments for {r}{at}. It's {p} done.","Experiments for {r}{at}: we're at {p}."}),{r=f.research.name,at=roomPhrase(s),p=Format.percent(f.research.progress,0)}) end
  return "I'm running small experiments"..roomPhrase(s).." so we have ideas ready for the next research project." end,
 UseWhiteboard=function(s,_f,V) return V("task",{"I'm sketching architecture ideas on the whiteboard","Whiteboard session: I'm drawing up model ideas"})..roomPhrase(s).."." end,
 ArchitectureStudy=function(s,_f,V) return V("task",{"I'm studying architectures for our next model size","I'm comparing model sizes for our next run"})..roomPhrase(s).."." end,
 AnalyzeModel=function(s,f,_V) if f.best then return "I'm going through the evaluation of "..f.best.name..roomPhrase(s)..": "..string.format("%.1f",f.best.overall).." overall." end;return "I'm setting up benchmarks"..roomPhrase(s)..". There's no trained model to evaluate yet." end,
 ReviewModel=function(s,f,_V) if f.best then return "I'm reviewing "..f.best.name..roomPhrase(s)..": "..string.format("%.1f",f.best.overall).." overall." end;return "I'm preparing the review checklist"..roomPhrase(s)..". Nothing is trained yet." end,
 WriteCode=function(s,f,V)
  if typeof(f.training)=="table" then return fill(V("task",{"I'm writing training code{at}. The run on {m} is at {p}.","Coding{at}. Meanwhile the {m} run is at {p}."}),{at=roomPhrase(s),m=f.training.model,p=Format.percent(f.training.progress,0)}) end
  return V("task",{"I'm writing tooling for the next training run","I'm getting the code ready for our next training run"})..roomPhrase(s).."." end,
 MonitorTraining=function(s,f,_V) if typeof(f.training)=="table" then return "I'm watching the training run"..roomPhrase(s)..". "..trainingLine(f) end;return "I'm checking the training dashboards"..roomPhrase(s)..". Nothing is training right now." end,
 InspectServer=function(s,f,_V) return "I'm checking the servers"..roomPhrase(s)..". "..hardwareLine(f) end,
 InspectHardware=function(s,f,_V) return "I'm testing hardware"..roomPhrase(s)..". "..hardwareLine(f) end,
 CleanDataset=function(s,f,V) return V("task",{"I'm cleaning datasets","I'm filtering out junk from our datasets"})..roomPhrase(s)..". "..dataLine(f) end,
 CheckQuality=function(s,f,_V) return "I'm checking data quality"..roomPhrase(s)..". "..dataLine(f) end,
 MonitorPipeline=function(s,f,_V) return "I'm watching the data pipeline"..roomPhrase(s)..". "..dataLine(f) end,
 AnalyzeMarket=function(s,f,V) return V("task",{"I'm analysing the market","I'm going through the market numbers"})..roomPhrase(s)..". "..marketLine(f) end,
 PlanLaunch=function(s,f,_V) if count(f,"live")>0 then return "I'm planning the next launch"..roomPhrase(s)..". "..modelsLine(f) end;return "I'm preparing our launch plan"..roomPhrase(s)..". "..modelsLine(f) end,
 CheckCustomers=function(s,f,_V) return "I'm checking on our customers"..roomPhrase(s)..". "..marketLine(f) end,
 -- lunch phases from the live staff record (StaffService.recordOf → lunch.phase) when TalkService has it
 Lunch=function(s,_f,V)
  local phase=s.lunch
  if phase=="toQueue" or phase=="queue" then return "I'm in the lunch queue at the servery." end
  if phase=="toSeat" then return "I've got my lunch, just looking for a seat." end
  if phase=="toReturn" or phase=="return" then return "Just bringing my tray back." end
  return V("task",{"I'm having lunch at the café.","Lunch break! I'm eating at the café."}) end,
 Coffee=function(_s,_f,V) return V("task",{"I'm on a short coffee break.","Just a quick coffee, then back to it."}) end,
 Snack=function(_s,_f,_V) return "Just grabbing a snack." end,
 FridgeDrink=function(_s,_f,_V) return "Just getting a cold drink from the fridge." end,
 RoofBreak=function(_s,_f,_V) return "I'm getting some fresh air on the roof." end,
 LoungeBreak=function(_s,_f,_V) return "I'm taking five in the lounge." end,
 TeamMeeting=function(s,_f,_V) return "I'm in the team meeting"..roomPhrase(s).."." end,
 ModelReviewMeeting=function(s,f,_V) return "We're in the model review"..roomPhrase(s)..". "..(if f.best then "We're looking at "..f.best.name.."." else "There's no trained model yet, so it's mostly planning.") end,
 DiscussWork=function(_s,_f,_V) return "I was just talking shop with a colleague." end,
 Leaving=function(_s,_f,_V) return "I'm heading home for the day." end,
 -- staffops
 FirstDay=function(_s,_f,V) return V("task",{"It's my first day! I'm picking up my badge at reception, then I'm off to my new desk.","First day here! Badge from reception first, then my new desk."}) end,
 RackRepair=function(s,f,_V)
  local n=count(f,"rackFaults")
  -- IT outside the compute rooms (no compute clearance): the remote fix from the corridor (StaffEvents)
  local remote=s.job=="IT Support" and s.roomAccess~="compute"
  local text=if remote then "I'm fixing a rack fault remotely from out here: IT has no access to the compute rooms."
   else "I'm fixing a server rack"..roomPhrase(s).."."
  if n>0 then
   text..=" "..plural(n,"rack fault").." open right now: each one takes a compute unit offline until it's fixed"
   text..=if num(f.stage,1)<2 then " (about five minutes: there's no IT post in the garage yet)." else " (about a minute while IT is on duty, five minutes otherwise)."
  else text..=" It's fixed: I'm just logging the repair." end
  return text end,
 ApprenticeTour=function(_s,_f,V) return V("task",{"We're on the apprentice tour of the building.","Apprentice tour! We're seeing every department today."}) end,
 TrainingSession=function(s,_f,_V) return "I'm in today's apprentice training session"..roomPhrase(s).."." end,
 TrainingLead=function(s,f,_V) return "I'm teaching today's training session"..roomPhrase(s).." for our "..plural(count(f,"apprenticeCount"),"apprentice").."." end,
 Shadowing=function(s,_f,V)
  -- the senior's real name from the rig attribute ShadowOf (TalkService passes it as sub.shadowOf; staffops request 3)
  if typeof(s.shadowOf)=="string" and s.shadowOf~="" then return "I'm sitting with "..s.shadowOf.." today to learn how they work"..roomPhrase(s).."." end
  return V("task",{"I'm sitting with a senior colleague to learn how they work","I'm shadowing one of our seniors today"})..roomPhrase(s).."." end,
 Practice=function(s,_f,V) return V("task",{"I'm practising on a small task at my desk","Practice task"})..roomPhrase(s)..". My trainer checks it later." end,
 Coaching=function(_s,_f,_V) return "I'm checking in on one of our apprentices at their desk." end,
}
-- Ops jobs: what the post is about (used when Task is CampusOperations or a job step).
local POST_TEXT: {[string]:(any,any,any,Vary)->string}={
 reception=function(s,_f,c,V) return fill(V("post",{"I'm looking after the front desk{at}. {n} at the desk today so far.","Front desk duty{at}. {n} here today so far."}),{at=roomPhrase(s),n=plural(num(c.talksToday),"conversation")}) end,
 hotel=function(s,_f,c,_V) if typeof(c.hotel)=="table" and typeof(c.hotel.guests)=="number" then return "I'm at the hotel desk"..roomPhrase(s)..". "..plural(c.hotel.guests,"guest").." checked in tonight." end;return "I'm setting up the hotel desk"..roomPhrase(s)..". The hotel isn't taking guests yet." end,
 security=function(s,_f,c,V) return fill(V("post",{"I'm watching the entrances{at}. {n} in the building right now.","Keeping an eye on the gates{at}. {n} in the building right now."}),{at=roomPhrase(s),n=plural(num(c.visitorsNow),"visitor")}) end,
 facilities=function(s,_f,c,_V) local b=c.building;if typeof(b)=="table" then return "I'm on my facilities round"..roomPhrase(s)..": "..plural(num(b.rooms),"room").." and a lift with "..plural(num(b.stops),"stop").." to keep running." end;return "I'm on my facilities round"..roomPhrase(s).."." end,
 it=function(s,_f,c,V) if typeof(c.faults)=="table" and num(c.faults.count)>0 then return "I'm working through IT tickets"..roomPhrase(s)..": "..plural(c.faults.count,"open fault").."." end;return V("post",{"I'm keeping the computers running","I'm on a desk check"})..roomPhrase(s).."." end,
 barista=function(s,_f,_c,V) return V("post",{"I'm making coffee","Coffee duty"})..roomPhrase(s)..V("post2",{".",". The machine barely gets a rest."}) end,
 chef=function(s,_f,c,V) local text=V("post",{"I'm cooking","I'm at the range"})..roomPhrase(s).."."
  if typeof(c.lunches)=="number" then text..=" "..plural(c.lunches,"lunch","lunches").." served today." end;return text end,
 kitchen=function(s,_f,_c,V) return V("post",{"I'm prepping food and keeping the kitchen clean","Chopping, washing up, handing out lunch: kitchen work"})..roomPhrase(s).."." end,
 host=function(s,_f,c,V) local text=V("post",{"I'm keeping the café tables ready","I'm wiping tables and seating people"})..roomPhrase(s)
  if typeof(c.dining)=="number" then return text..": "..plural(c.dining,"seat").." to look after." end;return text.."." end,
 fleet=function(s,_f,c,V) local text=V("post",{"I'm looking after the cars","Keys, chargers and tyres: I'm looking after the cars"})..roomPhrase(s).."."
  local cars=c.cars;if typeof(cars)=="table" and typeof(cars.owned)=="table" then text..=" We have "..plural(#cars.owned,"company car").."." end;return text end,
 housekeeping=function(s,_f,_c,V) return V("post",{"I'm getting rooms ready","Fresh towels and clean rooms: that's me"})..roomPhrase(s).."." end,
 cleaner=function(s,_f,c,V) local text=V("post",{"I'm cleaning","I'm on my cleaning round"})..roomPhrase(s).."."
  local b=c.building;if typeof(b)=="table" and num(b.restrooms)>0 then text..=" "..plural(b.restrooms,"washroom").." on my list." end;return text end,
 mailroom=function(s,_f,_c,V) return V("post",{"I'm sorting parcels","I'm sorting today's post and parcels"})..roomPhrase(s).."." end,
 trainer=function(s,f,_c,_V) return "I'm planning the next training"..roomPhrase(s)..". "..plural(count(f,"apprenticeCount"),"apprentice").." in the programme right now." end,
 ops=function(s,_f,_c,_V) return "I'm at my post"..roomPhrase(s).."." end,
}
local productive: {[string]:boolean}={WORKING=true,RESEARCH=true,DATA_REVIEW=true,MARKETING=true,SERVER_CHECK=true,MONITOR_TRAINING=true,MODEL_REVIEW=true}
local STATE_TEXT: {[string]:string}={
 WORKING="I'm working",RESEARCH="I'm on research work",DATA_REVIEW="I'm reviewing data",MARKETING="I'm on marketing work",SERVER_CHECK="I'm checking hardware",
 MONITOR_TRAINING="I'm monitoring training",MODEL_REVIEW="I'm reviewing a model",MEETING="I'm in a meeting",TALKING="I'm chatting with a colleague",
 COFFEE_BREAK="I'm on a short break",LUNCH="I'm having lunch",WAIT_AT_DESK="I'm waiting for a free workstation",SELECT_TASK="I'm deciding what to do next",
 ARRIVING="I'm just arriving",LEAVING="I'm heading home",ELEVATOR="I'm waiting for the lift",
}
-- What an operations job step looks like right now (rig attribute Pose, StaffJobs / PropFx contract).
local POSE_TEXT: {[string]:string}={pour="Pulling a coffee right now.",stir="Stirring a pan right now.",plate="Plating up right now.",chop="Chopping vegetables right now.",
 wash="Doing the dishes right now.",wipe="Wiping down right now.",greet="Greeting people at the door right now.",scan="Out on my patrol right now.",
 inspect="Checking the equipment right now.",typeStand="Updating the system right now.",type="At the computer right now.",sort="Sorting parcels right now.",
 plug="Plugging in a car to charge right now.",phone="On the phone right now.",push="Pushing the cart around right now."}
local function taskBody(subject: any,f: any,c: any,kind: string,V: Vary): string
 local task=subject.task
 local tourRoom=if typeof(task)=="string" then string.match(task,"^Tour:(.+)$") else nil
 if tourRoom then return tourRoomText(c,tourRoom) end
 local fn=if typeof(task)=="string" then TASK_TEXT[task] else nil
 if fn then return fn(subject,f,V) end
 if not HIRED[kind] and (task==nil or task=="CampusOperations" or subject.activity=="WORKING" or subject.activity==nil) then
  local pose=if typeof(subject.pose)=="string" then POSE_TEXT[subject.pose] else nil
  return (if pose then pose.." " else "")..(POST_TEXT[kind] or POST_TEXT.ops)(subject,f,c,V)
 end
 local state=STATE_TEXT[subject.activity or ""] or "I'm busy with my work"
 local text=state..roomPhrase(subject).."."
 if HIRED[kind] and productive[subject.activity or ""] then
  local extra=if kind=="researcher" then researchLine(f) elseif kind=="engineer" then trainingLine(f) elseif kind=="curator" then dataLine(f) else marketLine(f)
  text..=" "..extra
 end
 return text
end
local function taskText(subject: any,f: any,c: any,kind: string,V: Vary): string
 -- the night crew says so first (the shift is otherwise only in "How's your day going?")
 if HIRED[kind] and subject.shiftStart==Config.NIGHT_CREW.start and typeof(subject.shiftEnd)=="number" then
  return "I'm on the night crew ("..Dialogue.clock(subject.shiftStart).." to "..Dialogue.clock(subject.shiftEnd).."). "..taskBody(subject,f,c,kind,V)
 end
 return taskBody(subject,f,c,kind,V)
end
-- Destination phrase while walking ("On my way to the café").
local WALK_TO: {[string]:string}={Lunch="lunch at the café",Coffee="grab a coffee",Snack="grab a snack",FridgeDrink="get a drink",RoofBreak="the roof for some air",
 LoungeBreak="the lounge",TeamMeeting="a team meeting",ModelReviewMeeting="the model review",DiscussWork="catch up with a colleague",Leaving="head home",
 FirstDay="my new desk",RackRepair="a server rack that needs fixing",ApprenticeTour="the next stop of the apprentice tour",TrainingSession="today's apprentice training",
 TrainingLead="the training room",Shadowing="sit with a senior colleague",Practice="my desk",Coaching="check on an apprentice"}
local function walking(subject: any): string?
 local a=subject.activity
 if a=="WALKING" then
  local to=if typeof(subject.task)=="string" then WALK_TO[subject.task] else nil
  return if to then "I'm on my way to "..to.."." else "I'm on my way to my next task."
 elseif a=="ELEVATOR" then return "I'm waiting for the lift."
 elseif a=="LEAVING" then return "I'm just heading home."
 elseif a=="ARRIVING" then
  if subject.task=="FirstDay" then return "It's my first day! I'm on my way to reception for my badge." end
  return "I'm just arriving."
 end
 return nil
end

-- Greeting ---------------------------------------------------------------------------------------
local GREET: {[string]:{[string]:{string}}}={
 owner={confident={"Hey {viewer}!","{hello}, {viewer}!","Oh, the boss! Hi {viewer}."},calm={"Hi {viewer}.","{hello}, {viewer}.","Hello {viewer}."},
  shy={"Oh — hi, {viewer}.","Um, hi {viewer}.","{hello}… hi {viewer}."}},
 visitor={confident={"Hi there, welcome to {company}!","{hello}! Welcome to {company}."},calm={"{hello}, welcome to {company}.","Hello, welcome to {company}."},
  shy={"Oh, hello — welcome to {company}.","Hi… welcome to {company}."}},
}
local STATUS_BREAK={COFFEE_BREAK="I'm just on a quick break.",LUNCH="I'm just having lunch.",MEETING="We're in a meeting, but go ahead.",TALKING="I was just chatting with a colleague."}
local ASK: {[string]:{string}}={
 owner={"What's up?","What can I do for you?","Need anything?"},
 reception={"How can I help you?","What can I do for you?"},hotel={"How can I help you?","Are you checking in?"},security={"Can I help you?","Everything all right?"},
 barista={"What can I get you?","Coffee?"},host={"Table for one?","Looking for a seat?"},chef={"Hungry?","Here for lunch?"},
}
local function greeting(subject: any,c: any,kind: string,tone: string,seed: number,day: number): string
 local viewer=c.viewer=="owner" and "owner" or "visitor"
 local vars={viewer=first(tostring(c.viewerName or "there")),hello=hello(num(c.hour,9)),company=tostring(c.company or (c.facts and c.facts.company) or "the company")}
 local text=fill(pick(GREET[viewer][tone],seed,day,"greet"),vars)
 if viewer=="visitor" then
  text..=" I'm "..first(subject.name)..". "..(JOB_PHRASE[kind] or JOB_PHRASE.ops).."."
 end
 local moving=walking(subject)
 if moving then text..=" "..moving
 elseif STATUS_BREAK[subject.activity or ""] then text..=" "..STATUS_BREAK[subject.activity]
 elseif viewer=="owner" and not HIRED[kind] then text..=" "..(JOB_PHRASE[kind] or JOB_PHRASE.ops)..roomPhrase(subject).."." end
 local asks=if viewer=="owner" then ASK.owner else (ASK[kind] or ASK.reception)
 return text.." "..pick(asks,seed,day,"ask")
end

-- Topics -----------------------------------------------------------------------------------------
local OPTION_TEXT: {[string]:string}={
 work="What are you working on?",day="How's your day going?",company="How is the company doing?",you="Tell me about yourself.",
 research="How's the research going?",training="How's training going?",data="How's our data looking?",market="How's the market?",
 where="Where is …?",visitors="Busy today?",about="What does this company do?",access="Where am I allowed to go?",cameras="Where's the camera room?",
 building="How's the building?",faults="Any IT problems?",hardware="How's our hardware?",menu="What's on the menu?",lunch="How's lunch service?",
 seat="Where can I sit?",cars="How are the company cars?",rooms="Do you have a room?",clean="How's the cleaning going?",
 team="What does your team do?",room="What's this room for?",tour="What's in this building?",
 away="Who's away today?",apprentices="How are the apprentices doing?",
}
local OWNER_TEXT: {[string]:string}={access="How's building security?",rooms="How's the hotel?"}
-- "room" is only offered while the person stands in a plan room with a purpose (Dialogue.explainsRoom).
local TOPICS: {[string]:{[string]:{string}}}={
 owner={researcher={"work","research","team","company","day","you","room"},engineer={"work","training","team","company","day","you","room"},
  curator={"work","data","team","company","day","you","room"},marketer={"work","market","team","company","day","you","room"},
  reception={"visitors","away","where","tour","work","day","room"},hotel={"rooms","where","work","day","room"},
  security={"access","cameras","visitors","day","room"},facilities={"building","work","tour","day","room"},it={"faults","hardware","work","day","room"},
  barista={"menu","lunch","work","day","room"},chef={"lunch","menu","work","day","room"},kitchen={"lunch","menu","work","day","room"},
  host={"lunch","menu","seat","day","room"},fleet={"cars","work","day","room"},housekeeping={"clean","rooms","day","room"},
  cleaner={"clean","work","day","room"},mailroom={"work","day","building","room"},trainer={"apprentices","work","away","day","room"},ops={"work","day","building","room"}},
 visitor={reception={"about","where","visitors","tour","room"},hotel={"rooms","where","about","tour"},security={"access","where","about","tour"},
  barista={"menu","seat","about","room"},host={"menu","seat","about","room"},chef={"menu","lunch","about","room"}},
}
local BYE: {[string]:{[string]:{string}}}={
 owner={confident={"Anytime, {viewer}! Back to it.","Always good to see you, {viewer}!"},calm={"Sure thing, {viewer}. Back to work.","Okay {viewer}, see you around."},
  shy={"Okay… thanks for stopping by, {viewer}.","Oh — okay. Bye, {viewer}."}},
 visitor={confident={"Enjoy your visit!","Have fun looking around!"},calm={"Have a good visit.","Enjoy your stay."},shy={"Okay, have a nice day.","Um, enjoy your visit."}},
}
-- Openers in front of an answer; each ends a sentence, so the answer may start with a name or a number.
local SOFT: {[string]:{string}}={confident={"Honestly? ","Good question! ",""},calm={"","Let me think. ",""},shy={"Um… ","Oh, okay. ",""}}
-- Opening of "How's your day going?" by tone (no claims, just mood).
local MOOD: {[string]:{string}}={confident={"Great, thanks! ","Busy, the way I like it. ","Pretty good! "},calm={"Fine, thanks. ","Good so far. ",""},shy={"Oh, fine… ","Okay, I think. ",""}}

local function scheduleText(subject: any,c: any,kind: string,tone: string,V: Vary): string
 local hour=num(c.hour,9)
 local now=V("mood",MOOD[tone] or MOOD.calm).."It's "..Dialogue.clock(hour).." now."
 if HIRED[kind] and typeof(subject.shiftStart)=="number" and typeof(subject.shiftEnd)=="number" then
  return now.." I'm on the night crew: "..Dialogue.clock(subject.shiftStart).." to "..Dialogue.clock(subject.shiftEnd)..", while the day team is at home."
 end
 if HIRED[kind] then
  local p=Config.personalityFromSeed(num(subject.seed))
  local text=fill(V("day",{"I start at {a} and leave at {b}. ","My hours are {a} to {b}. "}),{a=Dialogue.clock(p.start),b=Dialogue.clock(p.finish)})
  if hour<p.lunch then text..="Lunch is usually around "..Dialogue.clock(p.lunch).."."
  elseif hour<p.lunch+1.1 then text..="It's my lunch window right now ("..Dialogue.clock(p.lunch).." onwards)."
  else text..="I had lunch around "..Dialogue.clock(p.lunch).."." end
  if apprenticeOf(subject,c.facts or {}) then text..=" Apprentice training is every morning at "..Dialogue.clock(Config.APPRENTICE.trainingHours[1]).."." end
  return now.." "..text
 end
 if typeof(subject.shiftStart)=="number" and typeof(subject.shiftEnd)=="number" then
  if subject.shiftStart>subject.shiftEnd then
   -- the stage-5 night rota (EmployeeConfig.NIGHT_ROTA): an evening start, a morning end
   return now.." I'm on the night rota: "..Dialogue.clock(subject.shiftStart).." to "..Dialogue.clock(subject.shiftEnd)..". I take over the post when the day shift goes home."
  end
  return now.." My shift today runs from "..Dialogue.clock(subject.shiftStart).." to "..Dialogue.clock(subject.shiftEnd).."."
 end
 -- no ShiftStart/ShiftEnd on the rig: the guard who stays on while a department runs a night crew (StaffRota)
 local post=string.lower(tostring(subject.job or "campus"))
 return now.." "..fill(V("day",{"We have a night crew, so I stay on at the {post} post tonight.","Our night crew needs a guard on duty, so I'm staying at the {post} post through the night."}),{post=post})
end
local function aboutText(subject: any,c: any,V: Vary): string
 local roleName=ROLE_NAME[subject.roleId] or "specialist"
 local appr=apprenticeOf(subject,c.facts or {})
 if appr then
  -- the real apprentice wage (CompanyOps.APPRENTICE.wage of the profile wage) and the ramping skill
  local wage=if typeof(subject.wage)=="number" and subject.wage>0 then subject.wage*Ops.APPRENTICE.wage else nil
  local text="I'm "..subject.name..", an apprentice "..roleName..": day "..Format.int(appr.day).." of my "..Format.int(Ops.APPRENTICE.graduateDays).." training days."
  text..=" My skill is "..Format.int(appr.skill).." out of 5 and goes up every "..Format.int(Ops.APPRENTICE.rampDays).." days."
  if wage then text..=" You pay me "..string.format("$%.2f",wage).." a second while I'm in training." end
  return text.." I graduate on day "..Format.int(appr.graduates).."."
 end
 local skill=if typeof(subject.skill)=="number" then tostring(math.floor(subject.skill+.5)) else nil
 local wage=if typeof(subject.wage)=="number" and subject.wage>0 then subject.wage else nil
 if V("you",{"a","b"})=="b" then
  local text=first(subject.name).." here, your "..roleName.."."
  if skill then text..=" My skill rating is "..skill.." out of 5." end
  if wage then text..=" My wage is "..string.format("$%.2f",wage).." a second ("..Format.money(wage*Dialogue.DAY_SECONDS).." per company day)." end
  return text
 end
 local text="I'm "..subject.name..", one of your "..roleName.."s."
 if skill then text..=" On the team list I'm rated "..skill.." out of 5." end
 if wage then text..=" You pay me "..string.format("$%.2f",wage).." a second — about "..Format.money(wage*Dialogue.DAY_SECONDS).." per company day." end
 return text
end
-- "What does your team do?": home desk room + department, what the role is for, the role's real effect.
local TEAM_TEXT: {[string]:string}={
 researcher="Researchers earn the research points that unlock our research projects.",
 engineer="Engineers turn data and GPUs into trained models.",
 curator="Curators collect and clean the data every model is trained on.",
 marketer="Growth managers bring our live models to users and customers.",
}
local function teamText(subject: any,c: any,kind: string,V: Vary): string
 local f=c.facts or {}
 local desk=subject.desk
 local text=""
 if typeof(desk)=="table" and typeof(desk.room)=="string" then
  local d=if typeof(desk.dept)=="string" then (Departments.DEPARTMENTS :: any)[desk.dept] else nil
  local part=if d and not string.find(desk.room,d.name,1,true) then ", part of "..d.name else ""
  text="My desk is in the "..desk.room..(if typeof(desk.level)=="string" then " ("..desk.level..")" else "")..part.."."
  text..=deskLine(desk.desks,desk.busy,"in there")
  text..=" "
 end
 text..=TEAM_TEXT[kind] or "We keep the company running."
 local role=EmpireConfig.find(EmpireConfig.ROLES,subject.roleId)
 local n=num(f.roles and f.roles[subject.roleId])
 local word=ROLE_NAME[kind] or "specialist"
 if n==1 then text..=" I'm our only "..word.." so far."
 elseif n>1 then text..=" "..fill(V("team",{"We're {n} on the team.","The team has {n} right now."}),{n=plural(n,word)}) end
 if role and typeof(role.desc)=="string" then
  -- EmpireConfig.ROLES desc, e.g. "+0.6 research points/s per employee." → "Each of us adds +0.6 research points/s."
  local gain,rest=string.match(role.desc,"^(.-) per employee%.%s*(.*)$")
  if gain and gain~="" then
   text..=" Each of us adds "..gain
   if rest and rest~="" then text..=" ("..lowerFirst((string.gsub(rest,"%.$","")))..")" end
   text..="."
  else text..=" "..role.desc end
 end
 if kind=="researcher" and typeof(f.nextResearch)=="table" and typeof(f.research)~="table" then text..=" Next up: "..f.nextResearch.name.."." end
 if HIRED[kind] then text..=teamAway(f,subject.roleId,subject.name) end
 return text
end
local function companyText(f: any,V: Vary): string
 local cash=Format.money(count(f,"cash"))
 return fill(V("company",{"We have {cash} in the bank. {trend} {models}","{trend} {models} Cash in the bank: {cash}.","{models} {trend} We have {cash} in the bank."}),
  {cash=cash,trend=profitTrend(f),models=modelsLine(f)})
end
local function visitorsText(c: any,owner: boolean): string
 local now=num(c.visitorsNow);local today=num(c.visitorsToday)
 if owner then
  local f=c.facts or {}
  return plural(now,"visitor").." in the building right now, "..plural(today,"visitor").." so far today. "
   ..plural(count(f,"applicantsWaiting"),"candidate").." waiting in the visitor lounge and "..plural(count(f,"applicantsOpen"),"new application").." open."
 end
 return "You're one of "..plural(math.max(1,today),"visitor").." today — "..plural(math.max(1,now),"guest").." in the building right now. Make yourself at home in the public areas."
end
local function accessText(c: any,owner: boolean): string
 local b=c.building
 local public=if typeof(b)=="table" and typeof(b.publicRooms)=="table" and #b.publicRooms>0 then roomList(b.publicRooms) else "the reception hall"
 if owner then
  local text="Visitors may use "..public..". Everything past the speed gates needs a card."
  if typeof(c.passes)=="number" then text..=" "..plural(c.passes,"guest card").." active right now." end
  return text
 end
 return "Visitors are welcome in "..public..". Past the speed gates you need a guest card from "..tostring(c.ownerName or "the founder").."."
end
local function camerasText(c: any): string
 local b=c.building;local places=c.places
 local where="Campus Security, on level 1 of the pavilion"
 if typeof(places)=="table" then for _,p in places do if p.id=="P1_SECURITY" then where=p.name..", "..levelPhrase(num(c.tier,1),p.level)..(if p.level==1 then " of the pavilion" else "") end end end
 local text="The camera room is "..where..". Founder access only."
 if typeof(b)=="table" and typeof(b.cameras)=="number" then text..=" "..plural(b.cameras,"room").." are on camera." end
 return text
end
local function faultsText(c: any): string
 local racks=num(c.facts and c.facts.rackFaults)
 local rackLine=if racks>0 then " And "..plural(racks,"server rack").." down: each one costs a compute unit until it's fixed, about a minute while IT is on duty." else ""
 local fl=c.faults
 if rackLine~="" and (typeof(fl)~="table" or num(fl.count)<=0) then return "No desk faults, but "..plural(racks,"server rack").." down: each one costs a compute unit until it's fixed, about a minute while IT is on duty." end
 if typeof(fl)~="table" then return "No ticket system is wired up here yet, so I check the desks on my rounds. Nothing has been reported to me." end
 if num(fl.count)<=0 then return "No open faults right now. Every screen I look after is working." end
 local text=plural(fl.count,"open fault").." right now"
 if typeof(fl.rooms)=="table" and #fl.rooms>0 then text..=": "..table.concat(fl.rooms,", ",1,math.min(#fl.rooms,3)) end
 return text..". I'm on it."..rackLine
end
local function buildingText(c: any): string
 local b=c.building
 if typeof(b)~="table" then return "Everything is running." end
 local tier=num(c.tier,1)
 local text="This building has "..plural(num(b.floors),"floor").." from G up to "..Plan.levelLabel(tier,Plan.founderLevel(tier))..", plus B1 and the roof: "
  ..plural(num(b.rooms),"room").." and a lift with "..plural(num(b.stops),"stop").."."
 if typeof(c.desks)=="number" and c.desks>0 then
  text..=" "..plural(c.desks,"computer desk")
  if typeof(c.desksBusy)=="number" then text..=", "..Format.int(math.min(c.desksBusy,c.desks)).." in use right now" end
  text..="."
 end
 return text.." Everything is running."
end
-- Earliest / latest lunch start of any personality (EmployeeConfig.personalityFromSeed), computed once.
local lunchRange: {number}?=nil
function Dialogue.lunchWindow(): (number,number)
 if not lunchRange then
  local lo,hi=math.huge,-math.huge
  for seed=0,1999 do local l=Config.personalityFromSeed(seed).lunch;lo=math.min(lo,l);hi=math.max(hi,l) end
  lunchRange={lo,hi}
 end
 local r=lunchRange :: {number}
 return r[1],r[2]
end
local function lunchText(c: any): string
 local text=if typeof(c.lunches)=="number" then plural(c.lunches,"lunch","lunches").." served today. " else ""
 local service=(Config :: any).LUNCH_SERVICE
 if typeof(service)=="table" and typeof(service[1])=="number" and typeof(service[2])=="number" then
  text..="The kitchen serves lunch from "..Dialogue.clock(service[1]).." to "..Dialogue.clock(service[2])..". "
 end
 local lo,hi=Dialogue.lunchWindow()
 text..="The team goes to lunch between "..Dialogue.clock(lo).." and "..Dialogue.clock(hi).."."
 if typeof(c.dining)=="number" then text..=" We have "..plural(c.dining,"seat").." in the café." end
 return text
end
local function carsText(c: any): string
 local cars=c.cars
 if typeof(cars)~="table" or typeof(cars.owned)~="table" or #cars.owned==0 then return "There's no company car in the garage yet." end
 local text="We have "..plural(#cars.owned,"company car")..": "..table.concat(cars.owned,", ").."."
 if typeof(cars.ready)=="string" then text..=" The "..cars.ready.." is the one set up for you, down on B1." end
 return text
end
local function hotelText(c: any,owner: boolean): string
 local h=c.hotel
 if typeof(h)=="table" and typeof(h.guests)=="number" then
  local text=plural(h.guests,"guest").." checked in tonight"
  if typeof(h.rooms)=="number" then text..=", "..plural(math.max(0,h.rooms-h.guests),"room").." free" end
  return text.."."
 end
 if owner then return "The hotel isn't taking guests yet. Once it opens I'll check in our travelling staff and visitors here." end
 return "Sorry, we aren't taking guests yet."
end
local function cleanText(c: any,kind: string): string
 local b=c.building
 if kind=="housekeeping" then
  local h=c.hotel
  if typeof(h)=="table" and typeof(h.guests)=="number" then return plural(h.guests,"guest room").." to turn around tomorrow morning, plus fresh towels for everyone." end
  if typeof(b)=="table" and num(b.restrooms)>0 then return "No hotel guests yet, so I help keep the main building tidy: "..plural(b.restrooms,"washroom").." on today's list." end
  return "No hotel guests yet, so I help keep the main building tidy."
 end
 if typeof(b)=="table" and num(b.restrooms)>0 then return "Good! "..plural(b.restrooms,"washroom").." and the corridors are on my list today." end
 return "Good! The corridors are on my list today."
end
local function aboutCompany(c: any): string
 local f=c.facts or {}
 local text=tostring(c.company or f.company).." builds AI models"
 if typeof(c.ownerName)=="string" then text..=", founded by "..c.ownerName end
 text..=". "..staffLine(f)
 if count(f,"live")>0 then text..=" "..plural(count(f,"live"),"model").." live right now." end
 return text
end
local function seatText(c: any): string
 local text="Take any free table in the café"
 if typeof(c.dining)=="number" then text..=" — we have "..plural(c.dining,"seat") end
 return text..". The visitor lounge next to reception has sofas too."
end
local function answerFor(id: string,subject: any,c: any,kind: string,tone: string,seed: number,day: number,V: Vary): Answer
 local f=c.facts or {}
 local owner=c.viewer=="owner"
 local soft=pick(SOFT[tone],seed,day,"soft"..id)
 if id=="work" then return {text=taskText(subject,f,c,kind,V)}
 elseif id=="day" then return {text=scheduleText(subject,c,kind,tone,V)}
 elseif id=="company" then return {text=soft..companyText(f,V)}
 elseif id=="you" then return {text=aboutText(subject,c,V)}
 elseif id=="research" then return {text=soft..researchMore(f)}
 elseif id=="training" then return {text=soft..trainingLine(f).." "..hardwareLine(f)}
 elseif id=="data" then return {text=soft..dataLine(f).." "..plural(num(f.roles and f.roles.curator),"curator").." on the team."}
 elseif id=="market" then return {text=soft..marketLine(f)}
 elseif id=="team" then return {text=teamText(subject,c,kind,V)}
 elseif id=="room" then return {text=roomText(subject,c)}
 elseif id=="tour" then return {text=tourText(c,owner,V)}
 elseif id=="visitors" then return {text=visitorsText(c,owner)}
 elseif id=="about" then return {text=aboutCompany(c)}
 elseif id=="access" then return {text=accessText(c,owner)}
 elseif id=="cameras" then return {text=camerasText(c)}
 elseif id=="building" then return {text=buildingText(c)}
 elseif id=="faults" then return {text=faultsText(c)}
 elseif id=="hardware" then return {text=(if typeof(c.desks)=="number" then plural(c.desks,"computer desk").." in the building. " else "")..hardwareLine(f)}
 elseif id=="menu" then return {text=menuLine(c.menu,seed,day,V)}
 elseif id=="lunch" then return {text=lunchText(c)}
 elseif id=="seat" then return {text=seatText(c)}
 elseif id=="cars" then return {text=carsText(c)}
 elseif id=="rooms" then return {text=hotelText(c,owner)}
 elseif id=="clean" then return {text=cleanText(c,kind)}
 elseif id=="away" then return {text=soft..awayText(f)}
 elseif id=="apprentices" then return {text=apprenticesText(f)}
 end
 return {text="Hm, I'm not sure."}
end

-- Lines --------------------------------------------------------------------------------------------
local PAGE=3
function Dialogue.lines(subject: any,c: any): Lines
 local kind=Dialogue.kind(subject.roleId,subject.job)
 local viewer=if c.viewer=="owner" then "owner" else "visitor"
 local seed=num(subject.seed);local day=num(c.day)
 local tone=Dialogue.tone(seed)
 local V: Vary=function(key: string,list: {string}): string return pick(list,seed,day,key) end
 local ids=(TOPICS[viewer][kind] or (if viewer=="owner" then TOPICS.owner.ops else TOPICS.visitor.reception))
 local topics: {Option}={};local answers: {[string]:Answer}={}
 for _,id in ids do
  if id=="room" and not Dialogue.explainsRoom(subject) then continue end
  local option: Option={id=id :: string,text=(if viewer=="owner" then OWNER_TEXT[id] else nil) or OPTION_TEXT[id]}
  table.insert(topics,option)
  if id=="where" then
   -- Pages of chips: up to PAGE places fit on the last page; earlier pages show PAGE-1 places and a
   -- "Somewhere else…" chip that opens the next page (chips stay <= MAX_OPTIONS incl. goodbye).
   local places: {Place}=if typeof(c.places)=="table" then c.places else {}
   for _,p in places do answers["where:"..p.id]={text=p.text} end
   if #places==0 then answers.where={text="I'm new to this floor plan myself, sorry."}
   else
    local pages: {{Option}}={}
    local at=1
    while at<=#places do
     local left=#places-at+1
     local take=if left<=PAGE then left else PAGE-1
     local page: {Option}={}
     for k=at,at+take-1 do table.insert(page,{id="where:"..places[k].id,text=places[k].name}) end
     at+=take
     table.insert(pages,page)
    end
    for k=1,#pages-1 do
     local id=if k==1 then "where:more" else "where:more"..tostring(k)
     table.insert(pages[k],{id=id,text="Somewhere else…"})
     answers[id]={text=if k==1 then "Other places people ask me about:" else "And these:",follow=pages[k+1]}
    end
    answers.where={text=pick({"Sure — where do you want to go?","Happy to help. Which place?","Of course. Where to?"},seed,day,"where"),follow=pages[1]}
   end
  else
   answers[id]=answerFor(id,subject,c,kind,tone,seed,day,V)
  end
 end
 local farewell=fill(V("bye",BYE[viewer][tone]),{viewer=first(tostring(c.viewerName or "there"))})
 answers.bye={text=farewell,close=true}
 local lines: Lines={kind=kind,tone=tone,viewer=viewer,greeting=greeting(subject,c,kind,tone,seed,day),topics=topics,options={},answers=answers,farewell=farewell}
 lines.options=Dialogue.options(lines,{},nil)
 return lines
end
-- Next chips: follow-ups first, then topics not asked yet, always ending with the goodbye chip.
function Dialogue.options(lines: Lines,asked: {[string]:boolean},follow: {Option}?): {Option}
 local out: {Option}={}
 local limit=Dialogue.MAX_OPTIONS-1
 if follow and #follow>0 then
  for _,o in follow do if #out<limit then table.insert(out,o) end end
 else
  for _,o in lines.topics do if #out<limit and not asked[o.id] then table.insert(out,o) end end
 end
 table.insert(out,{id="bye",text=if lines.viewer=="owner" then "Thanks, carry on." else "Thanks, bye!"})
 return out
end
-- Answers option `id` (must be one of the offered ids; TalkService checks). Marks the topic as asked
-- (a place marks "where") and returns the answer plus the next options (empty after "bye").
function Dialogue.step(lines: Lines,asked: {[string]:boolean},id: string): (Answer?,{Option})
 local answer=lines.answers[id]
 if not answer then return nil,{} end
 if answer.close then return answer,{} end
 local topic=string.match(id,"^([^:]+)") or id
 asked[topic]=true
 return answer,Dialogue.options(lines,asked,answer.follow)
end
return Dialogue
