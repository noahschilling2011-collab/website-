--!strict
-- The founder's personal assistant: one Executive Assistant NPC per headquarters (folder Office.Assistant).
-- Identity: feminine first name and appearance seed derived from the owner id (stable across visits),
-- built with EmployeeRigDesign; role "assistant" (BuildingPlan clearance public + staff + founder).
-- Home post: the desk station of the founder reception F_ASSIST (fallback: the planned room centre); in
-- the garage stage (plan tier 0) her small desk by the side door (BuildingPlan.postRoom).
-- She walks with EmployeeNavigation on the shared queue and campus clock (StaffService.now), uses
-- doors via DoorService.requestNPC and the lift via LiftService tickets exactly like employees.
--
-- Talk (owner-only prompt) → Notify ASSISTANT_OPEN with a briefing built ONLY from the owner's session
-- data (finances, training, models, data & hardware, research, team, 1-3 rule-based recommendations).
-- She is an authored helper, not a language model: every sentence is a template over real numbers.
-- Coffee (AssistantAction "coffee", 120 s cooldown): the company pays the menu price of the café's
-- "coffee" at once; she walks to the nearest Coffee activity / coffee machine (founder-floor tea kitchen
-- first), brews for BREW_SECONDS, carries a cup and walks to the founder while they are inside the
-- building (re-targeting every RETARGET s, giving up after GIVE_UP s); within HANDOVER studs she hands it
-- over with FacilityService.deliverSnack and a one-line insight. Founder outside: she waits at her desk
-- with the cup and hands it over when the founder talks to her.
-- Proactive, never chatty: one greeting per session when the founder first comes within GREET_RANGE on
-- the founder floor; a pending training decision is mentioned at most every REMIND_EVERY s when near.
-- Self-healing like LiftService: tick attaches her to every claimed office that has none and drops
-- records of destroyed offices.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Prompts=game:GetService("ProximityPromptService")
local EmpireConfig=require(ReplicatedStorage.Shared.Config.EmpireConfig)
local EmployeeConfig=require(ReplicatedStorage.Shared.Config.EmployeeConfig)
local CampusConfig=require(ReplicatedStorage.Shared.Config.CampusConfig)
local ModelConfig=require(ReplicatedStorage.Shared.Config.ModelConfig)
local MarketConfig=require(ReplicatedStorage.Shared.Config.MarketConfig)
local HardwareConfig=require(ReplicatedStorage.Shared.Config.HardwareConfig)
local Ops=require(ReplicatedStorage.Shared.CompanyOps)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local CampusMath=require(ReplicatedStorage.Shared.CampusMath)
local EmpireMath=require(ReplicatedStorage.Shared.EmpireMath)
local ModelMath=require(ReplicatedStorage.Shared.ModelMath)
local JourneyMath=require(ReplicatedStorage.Shared.JourneyMath)
local Format=require(ReplicatedStorage.Shared.Format)
local Remote=require(script.Parent.Parent.Lib.Remote)
local Session=require(script.Parent.SessionService)
local Economy=require(script.Parent.EconomyService)
local Plot=require(script.Parent.PlotService)
local Rig=require(script.Parent.EmployeeRigDesign)
local Nav=require(script.Parent.EmployeeNavigation)
local Workstations=require(script.Parent.WorkstationService)
local Staff=require(script.Parent.StaffService)
local Facility=require(script.Parent.FacilityService)
local Sound=require(script.Parent.CampusSoundService)
local Recruiting=require(script.Parent.RecruitingService)
local NPC=Recruiting.npc
local Assistant={}
Assistant.TITLE="Executive Assistant"
Assistant.COFFEE_COOLDOWN=120
Assistant.BREW_SECONDS=4
Assistant.HANDOVER=6
Assistant.RETARGET=3
Assistant.GIVE_UP=120
Assistant.GREET_RANGE=25
Assistant.REMIND_EVERY=180
local INDEX=400 -- StaffIndex of her rig (employees 1..240, operations 301..312, visitors 501..)
local records: {[Instance]:any}={}
local orders: {[any]:number}=setmetatable({},{__mode="k"}) :: any
local greeted: {[any]:boolean}=setmetatable({},{__mode="k"}) :: any
local reminded: {[any]:number}=setmetatable({},{__mode="k"}) :: any
local scanClock=1
local failed: {[Instance]:number}=setmetatable({},{__mode="k"}) :: any -- office → retry time after an error
-- Movement and clock seams (headless tests replace them with a fake walker).
local mover: any={
 go=function(e: any,target: Vector3,time: number,cb: (boolean)->()) Nav.go(e,target,time,cb) end,
 cancel=function(e: any) Nav.cancel(e) end,
 tick=function(e: any,time: number) Nav.tick(e,time) end,
}
local clock: ()->number=function() return Staff.now() end
function Assistant._seams(fakeMover: any?,fakeClock: (()->number)?)
 if fakeMover then mover=fakeMover end
 if fakeClock then clock=fakeClock end
end

function Assistant.identity(owner: number): (string,number)
 local seed=EmployeeConfig.hash((math.floor(math.abs(owner))*13+4242)%4294967296)%2147483647
 return CampusMath.nameForSeed(seed,true),seed
end
local function notify(s: any,text: string)
 Remote.fire(s.player,"Notify","ASSISTANT_NOTICE",{text=text})
end
local function founderRoot(rec: any): BasePart?
 local character=rec.session.player.Character
 local root=if character then character:FindFirstChild("HumanoidRootPart") else nil
 return if root and root:IsA("BasePart") then root else nil
end
local function inside(rec: any,p: Vector3): boolean return Plan.inside(rec.tier,rec.cf:PointToObjectSpace(p)) end
local function lowerFirst(text: string): string
 if string.match(text,"^%u%l") then return string.lower(string.sub(text,1,1))..string.sub(text,2) end
 return text
end

-- Briefing (pure: session data + live values only) ----------------------------------------------
local function row(label: string,value: string): {string} return {label,value} end
local function nextSize(data: any): any
 local best=0
 for _,m in data.models do
  for i,size in ModelConfig.SIZES do if size.id==m.sizeId then best=math.max(best,i) end end
 end
 return ModelConfig.SIZES[math.min(best+1,#ModelConfig.SIZES)]
end
local function trend(history: {any}): (number?,number?)
 if #history<2 then return nil,nil end
 local function avg(from: number,to: number): number
  local sum,n=0,0
  for i=math.max(1,from),to do sum+=history[i].profit;n+=1 end
  return if n>0 then sum/n else 0
 end
 local last=#history;local window=math.min(6,math.floor(last/2))
 local recent=avg(last-window+1,last);local before=avg(last-2*window+1,last-window)
 return recent,recent-before
end
-- Briefing (CORE_SPEC 8.2): sections Today, Customers, Money and Models first (company day and who is away, the B2B
-- pipeline, today's P&L from the ledger, live lines and servers), then Training, Research and Team. The first
-- recommendation is the "Next goal" of EmpireMath.nextGoal (only a pending training decision comes before it).
local MOVE_NOTE_SECONDS=900 -- "New HQ: profit dips for ~15 minutes while new people start" (CORE_SPEC 9.5)
local movedAt: {[any]:number}=setmetatable({},{__mode="k"}) :: any
local seenOffice: {[any]:number}=setmetatable({},{__mode="k"}) :: any
local LEDGER_NAMES: {[string]:string}={market="AI products",b2b="retainers",pilot="pilot fees",studio="studio",guest="guest house",retail="stores",
 quest="milestones",daily="daily grant",wages="wages",ops="operations staff",upkeep="rent & utilities",food="lunch",fleet="fleet",trips="trips",
 b2bserve="client serving",jet="jet",jetbuy="jet purchase",hire="hiring fees",research="research",lab="Lab levels",office="office move",gpu="GPUs",
 data="data",training="training",refine="refinement",marketing="marketing",campus="campus",shop="shop",other="other"}
local function dollars(n: number): string return Ops.money(n) end
-- a countdown in play time that never looks like a clock time ("45 s", "4 min 30 s", "~32 min"; Client/UI/Kit.countdown)
local function countdown(seconds: number): string
 local t=math.max(0,math.floor((if seconds==seconds then seconds else 0)+0.5))
 if t<60 then return t.." s" end
 if t<600 then local m,r=t//60,t%60;return if r==0 then m.." min" else string.format("%d min %d s",m,r) end
 if t<5400 then return (if t%60==0 then "" else "~")..math.floor(t/60+0.5).." min" end
 return string.format("~%.1f h",t/3600)
end
-- top n categories of one ledger side: "wages $31,600 · research $12,000"
local function topLines(map: any,n: number): (string,number)
 local list,total={},0
 if typeof(map)=="table" then for cat,v in map do local x=tonumber(v) or 0;if x>0 then table.insert(list,{cat=tostring(cat),v=x});total+=x end end end
 table.sort(list,function(a,b) if a.v~=b.v then return a.v>b.v end;return a.cat<b.cat end)
 local parts={}
 for i=1,math.min(n,#list) do table.insert(parts,(LEDGER_NAMES[list[i].cat] or list[i].cat).." "..dollars(list[i].v)) end
 return table.concat(parts," · "),total
end
-- when a trip that is back at play second `back` returns, on the visible clock: "14:20", "tonight 02:10", "day 12 09:00".
-- A game day runs 08:00 -> 08:00, so a return shortly after 08:00 is a new company day although it is only minutes
-- away: anything within SOON game hours is just the time ("08:39" at 07:58), never "tomorrow".
local SOON_HOURS=2
local function backText(e: any,back: number,clock: number): string
 local at=clock+math.max(0,back-(tonumber(e.seconds) or 0))
 local h=Ops.hour(at);local days=math.floor(at/Ops.DAY)-math.floor(clock/Ops.DAY)
 local hm=string.format("%02d:%02d",math.floor(h),math.floor((h%1)*60))
 local ahead=(h-Ops.hour(clock))%24 -- game hours until the return on the visible clock
 if at-clock<Ops.DAY and ahead<SOON_HOURS then return hm end
 if days<=0 then return if h<8 then "tonight "..hm else hm end
 return "day "..(Ops.day(e)+days).." "..hm
end
Assistant._backText=backText -- tests
local function tripLine(e: any,t: any,clock: number): string
 local c=Ops.client(t.client);local name=if c then c.name else tostring(t.client)
 local tier=t.tier or (if c then c.trip else "city")
 local who=if t.hosted then name.." team at the guest house" elseif t.founder then "you at "..name elseif (tonumber(t.crew) or 1)>=2 then "rep + engineer at "..name else "rep at "..name
 local stay=""
 if not t.hosted then
  local T=Ops.TRIPS[tier]
  if tier=="abroad" then stay=if e.jet==true then ", company jet" else ", Meridian Grand $"..(T and T.hotel or 0)
  elseif tier=="region" then stay=", City Hotel $"..(T and T.hotel or 0) end
 end
 return string.format("%s (%s, back %s%s)",who,if t.kind=="renew" then "check-in" else "pilot",backText(e,tonumber(t.back) or 0,clock),stay)
end
-- What helps a waitlist (CORE_SPEC 8.2), checked against free rack slots and the cooling cap. Same decisions as the
-- Hardware app (Client/UI/Apps/ComputeApp.advice; tests/apps checks both agree): "cooling" (heat-limited, cooling < 8),
-- "maxed" (heat-limited at 8/8), "rack" (no free slot: next office / Distributed Cluster / swap the weakest GPU),
-- "buy" (a free slot: the GPU that adds the most users among those the company can pay, else the cheapest).
local COOLING_MAX=8
local function capacityWith(data: any,gpus: any): number
 local copy=table.clone(data);copy.gpus=gpus
 return Ops.capacity(copy)
end
local function computeAdvice(data: any,cash: number,live: any?): any
 local e=data.empire;local fleet=ModelMath.fleet(data.gpus)
 local slots=HardwareConfig.slots(e);local cooling=math.floor(tonumber(e.infrastructure and e.infrastructure.cooling) or 1)
 local stage=Ops.stageIndex(e);local nextDef=EmpireConfig.OFFICES[stage+1]
 local nextE=if nextDef then table.clone(e) else nil
 if nextE then nextE.office=stage+1 end
 local research=if typeof(e.research)=="table" then e.research else {}
 local a={kind="buy",gpu=nil :: string?,weakest=nil :: string?,extra=0,used=fleet.slotsUsed,slots=slots,cooling=cooling,cost=math.floor(8000*1.7^(cooling-1)),
  cools=HardwareConfig.thermal(e,1e9)*1e9,nextOffice=if nextDef then nextDef.name else nil,nextSlots=if nextE then HardwareConfig.slots(nextE) else nil,
  nextCools=if nextE then HardwareConfig.thermal(nextE,1e9)*1e9 else nil,cluster=research.cluster~=true and EmpireConfig.find(EmpireConfig.RESEARCH,"cluster")~=nil,
  -- capacity counts 500M-model user equivalents: real users per unit for today's mix = demand / load (MarketMath)
  perUnit=if live and (tonumber(live.load) or 0)>0 and (tonumber(live.demand) or 0)>0 then live.demand/live.load else 1}
 local base=Ops.capacity(data)
 if HardwareConfig.thermal(e,fleet.throughput)<1 then a.kind=if cooling<COOLING_MAX then "cooling" else "maxed";return a end
 if fleet.slotsUsed<slots then
  local cheapest=math.huge
  for _,gpu in HardwareConfig.GPUS do if not gpu.starter then cheapest=math.min(cheapest,gpu.price) end end
  for _,gpu in HardwareConfig.GPUS do
   if not gpu.starter and gpu.price<=math.max(cash,cheapest) then
    local g=table.clone(data.gpus);g[gpu.id]=(g[gpu.id] or 0)+1
    local extra=math.max(0,capacityWith(data,g)-base)
    if extra>a.extra then a.extra=extra;a.gpu=gpu.id end
   end
  end
  return a
 end
 a.kind="rack"
 local weakest=nil
 for _,gpu in HardwareConfig.GPUS do if not gpu.starter and (data.gpus[gpu.id] or 0)>0 and (weakest==nil or gpu.throughput<weakest.throughput) then weakest=gpu end end
 if weakest then
  a.weakest=weakest.id
  local budget=cash+weakest.price*HardwareConfig.SELL_REFUND;local cheapest=math.huge
  for _,gpu in HardwareConfig.GPUS do if not gpu.starter and gpu.throughput>weakest.throughput then cheapest=math.min(cheapest,gpu.price) end end
  for _,gpu in HardwareConfig.GPUS do
   if not gpu.starter and gpu.throughput>weakest.throughput and gpu.price<=math.max(budget,cheapest) then
    local g: {[string]:number}=table.clone(data.gpus);g[weakest.id]-=1;g[gpu.id]=(g[gpu.id] or 0)+1
    local extra=math.max(0,capacityWith(data,g)-base)
    if extra>a.extra then a.extra=extra;a.gpu=gpu.id end
   end
  end
 end
 return a
end
Assistant._computeAdvice=computeAdvice -- tests
local function gpuName(id: string?): string
 local def=if id then HardwareConfig.getGPU(id) else nil
 return if def then def.label else tostring(id)
end
local function withArticle(label: string): string
 local vowel=string.find("AEIOU",string.sub(label,1,1),1,true)~=nil or string.sub(label,1,3)=="HBM"
 return (if vowel then "an " else "a ")..label
end
-- short form for the briefing ("rack full (12 / 12): move to the Innovation Campus (24 slots) ...")
local function adviceText(a: any): string
 if a.kind=="cooling" then return string.format("cooling is the limit: upgrade cooling first (level %d / %d, %s) in Lab → GPUs",a.cooling,COOLING_MAX,Format.money(a.cost))
 elseif a.kind=="maxed" then
  if a.nextOffice then return string.format("cooling is maxed (%d / %d), more GPUs add no capacity here: move to the %s (cools %s units) or raise prices",a.cooling,COOLING_MAX,a.nextOffice,Format.int(a.nextCools or 0)) end
  return string.format("cooling is maxed (%d / %d) in your largest office: raise prices so demand fits your servers",a.cooling,COOLING_MAX)
 elseif a.kind=="rack" then
  local options={}
  if a.nextOffice and a.nextSlots then table.insert(options,string.format("move to the %s (%d slots)",a.nextOffice,a.nextSlots)) end
  if a.cluster then table.insert(options,"research Distributed Cluster (×1.5 slots)") end
  if a.gpu and a.weakest and a.extra>=1 then table.insert(options,string.format("swap %s for %s (+%s users)",withArticle(gpuName(a.weakest)),withArticle(gpuName(a.gpu)),Format.int(a.extra*a.perUnit))) end
  if #options==0 then return string.format("rack full (%d / %d) in your largest office: raise prices so demand fits your servers",a.used,a.slots) end
  local list=if #options==1 then options[1] else table.concat(options,", ",1,#options-1).." or "..options[#options]
  return string.format("rack full (%d / %d): %s",a.used,a.slots,list)
 end
 if a.gpu and a.extra>=1 then return string.format("buy GPUs in Lab → GPUs: one more %s serves %s more users",gpuName(a.gpu),Format.int(a.extra*a.perUnit)) end
 return "business clients reserve your compute right now: buy GPUs in Lab → GPUs"
end
-- the goal of the HUD bar as a recommendation with its concrete next step
local function goalRecommendation(s: any,goal: any,stock: any,journey: any,unreleased: any): (string,string?,string?)
 local data=s.data;local e=data.empire
 local id=goal.id
 if id=="train" then
  if data.training then return goal.text..": the first training run is under way in the Lab.","lab",nil end
  if stock.total<ModelConfig.TRAINING.minTokens then return goal.text..": collect at least "..Format.tokens(ModelConfig.TRAINING.minTokens).." tokens in Data first.","data",nil end
  if journey.missingVram>0 then return goal.text..": buy GPUs in Lab → GPUs or pick a smaller size ("..journey.hint..").","compute",nil end
  return goal.text..": design and train it in the Lab.","lab",nil
 elseif id=="release" then
  return if unreleased then "Release "..unreleased.name.." in Deployment: it isn't earning anything yet." else goal.text..": release your trained model in Deployment.","lab","release"
 elseif id=="client" then
  local c=Ops.CLIENTS[1];local best=Ops.liveBest(data,c.stat)
  local trip=nil
  for _,t in (if typeof(e.deals)=="table" and typeof(e.deals.tripList)=="table" then e.deals.tripList else {}) do if t.client==c.id then trip=t end end
  if trip then return goal.text..": you are on the way for the pilot visit.","empire","clients" end
  if best<=0 then return string.format("%s: %s needs %s %d. No model is live: release one first.",goal.text,c.name,c.stat,c.minimum),"lab","release" end
  if best<c.minimum then return string.format("%s: %s needs %s %d (your best live model: %d).",goal.text,c.name,c.stat,c.minimum,math.floor(best)),"lab",nil end
  local h=Ops.hour(workspace:GetServerTimeNow())
  if h<Ops.DEPART.from or h>=Ops.DEPART.to then return goal.text..": visits start 08:00–15:00, you drive over at 08:00.","empire","clients" end
  return goal.text..": the pilot visit starts by itself as soon as cash covers the trip.","empire","clients"
 elseif goal.etaMinutes~=nil or string.match(id,"^office") or id=="jet" then
  local eta=goal.etaMinutes
  local when=if (tonumber(goal.have) or 0)>=(tonumber(goal.need) or 1) then "ready to buy" elseif eta==nil then "no profit yet" elseif eta<1 then "under a minute away" elseif eta<120 then string.format("about %d min away",math.ceil(eta)) else string.format("about %d h away",math.ceil(eta/60))
  return string.format("%s: %s of %s saved, %s.",goal.text,dollars(tonumber(goal.have) or 0),dollars(tonumber(goal.need) or 0),when),"empire",if id=="jet" then "settings" else "office"
 elseif id=="lines2" then return goal.text..": release a model into another product line.","lab",if unreleased then "release" else nil
 elseif id=="region" then return goal.text..": Growth & Sales field reps visit region clients (City Hotel night).","empire","clients"
 elseif id=="frontier" then return goal.text..": research Frontier Architecture.","empire","research"
 elseif id=="lines90" then
  return string.format("%s: %d of %d lines are there. Train stronger versions (bigger size, better data) in the Lab.",goal.text,math.floor(tonumber(goal.have) or 0),math.floor(tonumber(goal.need) or 4)),"lab",nil
 elseif id=="lab" then
  local level=math.floor(tonumber(goal.have) or 0);local pts,cost=Ops.labCost(level)
  return string.format("%s: level %d now, the next one costs %s research points + %s in Lab → Models.",goal.text,level,Format.int(pts),dollars(cost)),"lab",nil
 end
 return string.format("%s (%d / %d).",goal.text,math.floor(tonumber(goal.have) or 0),math.floor(tonumber(goal.need) or 0)),"lab",nil
end
function Assistant.briefing(s: any,name: string?): any
 local data=s.data;local live=s.live;local e=data.empire
 local sections={};local recs={}
 local function recommend(text: string,app: string?,section: string?)
  if #recs<3 then table.insert(recs,{text=text,app=app,section=section}) end
 end
 local clock=workspace:GetServerTimeNow()
 local ops=if typeof(live.ops)=="table" then live.ops else {}
 local deals=if typeof(e.deals)=="table" then e.deals else Ops.newDeals()
 local trips=if typeof(ops.trips)=="table" then ops.trips elseif typeof(deals.tripList)=="table" then deals.tripList else {}
 -- Today: company day, who is at work / away, trips
 local present,vacation,sick,away,leave,total=0,0,0,0,0,0
 for _,role in EmpireConfig.ROLES do
  for _,state in Ops.presence(e,role.id) do
   total+=1
   if state=="present" then present+=1 elseif state=="vacation" then vacation+=1 elseif state=="sick" then sick+=1 elseif state=="trip" then away+=1 else leave+=1 end
  end
 end
 local repsAway=0 -- field reps on trips (the travelling engineers are already "trip" in Ops.presence)
 for _,t in trips do if not t.hosted and not t.founder then repsAway+=1 end end
 away+=repsAway
 local todayRows={row("Company day",Format.dayClock(Ops.day(e),Ops.hour(clock)))}
 -- safety rules (CORE_SPEC 8.3): broke for a whole day pauses trips and night crews; deep debt sends the newest
 -- hires on unpaid leave until cash covers a day of payroll
 local leaveN=math.max(0,math.floor(tonumber(e.unpaidLeave) or 0))
 local paused=ops.paused==true
 local warnings={}
 if paused then table.insert(warnings,"Cash has been below $0 for a whole day: trips and night shifts are paused")
 elseif data.money<0 then table.insert(warnings,"Cash is below $0: trips and night shifts pause after a whole day like this") end
 if leaveN>0 then table.insert(warnings,string.format("%d newest hire%s on unpaid leave until cash is above %s",leaveN,if leaveN==1 then " is" else "s are",dollars(Ops.dailyPayroll(e)))) end
 if #warnings>0 then table.insert(todayRows,row("Warning",table.concat(warnings,". ").."." )) end
 if total==0 then table.insert(todayRows,row("Team","Nobody hired yet: you run the company alone."))
 else
  local parts={}
  if vacation>0 then table.insert(parts,vacation.." on vacation") end
  if sick>0 then table.insert(parts,sick.." sick") end
  if away>0 then table.insert(parts,away.." travelling") end
  if leave>0 then table.insert(parts,leave.." on unpaid leave") end
  local base=if Ops.inOffice(clock) then string.format("%d of %d at work",math.max(0,present-repsAway),total) else string.format("night: off duty until 08:00 (%d of %d)",total-vacation-sick-leave,total)
  table.insert(todayRows,row("Team",base..(if #parts>0 then " · "..table.concat(parts,", ") else "")))
 end
 local stage=Ops.stageIndex(e)
 if Ops.opsPosts(e)>0 then
  local drivers=if stage>=Ops.DRIVER.more then 2 elseif stage>=Ops.DRIVER.from then 1 else 0
  table.insert(todayRows,row("Operations",string.format("%d operations staff%s · lunch for the team from the chef",Ops.opsPosts(e),if drivers>0 then string.format(" · %d driver%s",drivers,if drivers==1 then "" else "s") else "")))
 end
 if #trips>0 then
  local lines={}
  for i=1,math.min(3,#trips) do table.insert(lines,tripLine(e,trips[i],clock)) end
  table.insert(todayRows,row("Trips",table.concat(lines,"; ")..(if #trips>3 then string.format(" and %d more",#trips-3) else "")))
 else table.insert(todayRows,row("Trips","Nobody is travelling right now.")) end
 -- the founder's own business trip (package "itinerary": the booking she made for him)
 local okTrip,tripText=pcall(function(): string?
  local mod=script.Parent:FindFirstChild("ItineraryService")
  local Itin=if mod then (require :: any)(mod) else nil
  return if Itin and typeof(Itin.summary)=="function" then Itin.summary(s) else nil
 end)
 if okTrip and typeof(tripText)=="string" then table.insert(todayRows,row("Your trip",tripText)) end
 local moved=movedAt[s]
 if moved and (tonumber(e.seconds) or 0)-moved<MOVE_NOTE_SECONDS then
  table.insert(todayRows,row("New HQ","Profit dips for about 15 minutes while new people start."))
 end
 table.insert(sections,{title="Today",rows=todayRows})
 -- Customers: the B2B pipeline
 local custRows={}
 local accounts,retainer=0,0
 local renew: {string}={}
 for id,acc in (if typeof(deals.accounts)=="table" then deals.accounts else {}) do
  local c=Ops.client(id)
  accounts+=1
  if c then
   retainer+=c.retainer
   local left=((tonumber(acc.expires) or 0)-(tonumber(e.seconds) or 0))/Ops.DAY
   if acc.renewing then table.insert(renew,c.name.." (check-in under way)")
   elseif left<Ops.TRIPS[c.trip].days+Ops.RENEW_LEAD_DAYS+0.5 then table.insert(renew,string.format("%s in %.1f days",c.name,math.max(0,left))) end
  end
 end
 local limit=Ops.accountLimit(e)
 table.insert(custRows,row("Accounts",if accounts==0 then "No business client yet." else string.format("%d of %d slots · %s/day in retainers",accounts,limit,dollars(retainer))))
 local leads,bestLead,bestTrust,needs=0,nil,-1,nil
 for _,c in Ops.CLIENTS do
  local acc=typeof(deals.accounts)=="table" and deals.accounts[c.id]
  if not acc and stage>=c.stage then
   local best=Ops.liveBest(data,c.stat)
   if best>=c.minimum then
    leads+=1
    local t=tonumber(typeof(deals.trust)=="table" and deals.trust[c.id]) or 0
    if t>bestTrust then bestTrust=t;bestLead=c end
   elseif not needs then
    needs=if best<=0 then string.format("%s needs %s %d: release a model first.",c.name,c.stat,c.minimum) else string.format("%s needs %s %d (your best: %d).",c.name,c.stat,c.minimum,math.floor(best))
   end
  end
 end
 table.insert(custRows,row("Pipeline",if leads==0 then "No open lead right now." else string.format("%d lead%s%s · %d on the road",leads,if leads==1 then "" else "s",if bestLead then string.format(" · %s trust %d %%",bestLead.name,math.floor(math.min(1,bestTrust)*100)) else "",#trips)))
 if #renew>0 then table.insert(custRows,row("Renewals",table.concat(renew,", "))) end
 if needs then table.insert(custRows,row("Needs",needs)) end
 table.insert(sections,{title="Customers",rows=custRows})
 -- Money: today's P&L by category from the ledger, the running rate and the trend
 local entry=if typeof(e.ledger)=="table" then e.ledger[tostring(Ops.day(e))] else nil
 local incomeText,income=topLines(entry and entry.i,3)
 local costText,costs=topLines(entry and entry.o,3)
 local recent,delta=trend(e.history)
 local trendText="Not enough data yet (one sample every 10 s)."
 if recent and delta then
  local steady=math.abs(delta)<math.max(5,math.abs(recent)*.05)
  trendText=if steady then "Steady at "..Format.money(recent*20).."/day"
   elseif delta>0 then "Rising: "..Format.money(recent*20).."/day"
   else "Falling: "..Format.money(recent*20).."/day"
 end
 table.insert(sections,{title="Money",rows={row("Cash",Format.money(data.money)),
  row("Today",if income+costs==0 then "Nothing booked yet today." else string.format("income %s · costs %s · net %s",dollars(income),dollars(costs),dollars(income-costs))),
  row("Income",if incomeText~="" then incomeText else "none yet"),row("Costs",if costText~="" then costText else "none yet"),
  row("Running now",if (tonumber(live.revenue) or 0)==0 and (tonumber(live.cost) or 0)==0 then "no income or costs yet" else Format.perDay(live.revenue-live.cost).." net"),row("Profit trend",trendText)}})
 -- Models: live lines, servers, ageing, growth
 local best: any,liveCount,unreleased: any=nil,0,nil
 for _,id in data.modelOrder do
  local m=data.models[id]
  if m and m.status~="training" then
   if not best or m.overall>best.overall then best=m end
   if m.status=="live" then liveCount+=1 elseif m.status=="trained" and not unreleased then unreleased=m end
  end
 end
 local lines,nLines=ModelMath.liveLines(data)
 local lineParts,oldest,oldestAge={},nil,0
 for _,def in ModelConfig.LINES do
  local list=lines[def.segment]
  if list then
   local top=list[1];for _,m in list do if (m.overall or 0)>(top.overall or 0) then top=m end end
   table.insert(lineParts,string.format("%s %s v%d (%.1f)",def.label,top.name,top.version or 1,top.overall or 0))
   local age=ModelMath.versionAge(top)
   if age>oldestAge then oldestAge=age;oldest={def=def,model=top} end
  end
 end
 local modelRows={row("Live lines",if nLines==0 then "No model is live yet." else string.format("%d of %d: %s",nLines,ModelMath.productSlots(stage),table.concat(lineParts," · "))),
  row("Users",Format.compact(live.users))}
 local capacity=tonumber(live.capacity) or 0;local load=tonumber(live.load) or 0;local waiting=tonumber(live.waitlist) or 0
 if liveCount>0 and capacity>0 then
  local text=if load>capacity then string.format("full (demand %d %%)",math.floor(load/capacity*100+0.5)) else string.format("%d %% full",math.floor(load/capacity*100+0.5))
  if waiting>0 then text..=string.format(", %s waiting — %s.",Format.int(waiting),adviceText(computeAdvice(data,data.money,live))) end
  table.insert(modelRows,row("Servers",text))
 end
 if oldest then
  local fit=ModelMath.ageFit(oldestAge)
  if fit>=1 then table.insert(modelRows,row("Oldest line",string.format("Your %s line is %d min old (-%d fit). A new version resets it.",oldest.def.label,math.floor(oldestAge/60),math.floor(fit+0.5)))) end
 end
 local marketers=tonumber(e.employees and e.employees.marketer) or 0
 if marketers>0 then
  local stageMax=(MarketConfig.STAGE_REACH or {})[stage] or 0.9
  local office=marketers-Ops.fieldReps(e)
  local cap=Ops.reachCap(data,stageMax)
  table.insert(modelRows,row("Growth",if cap>=stageMax-1e-6 then string.format("Growth team at full effect (%d in the office).",office) else string.format("%d in the office reach %d %% of the %d %% this office allows.",office,math.floor(cap*100+0.5),math.floor(stageMax*100+0.5))))
 end
 table.insert(modelRows,row("Best model",if best then best.name.." · "..string.format("%.1f",best.overall).." overall" else "No trained model yet"))
 table.insert(sections,{title="Models",rows=modelRows})
 -- Training
 local training=data.training;local pending=nil
 if training then
  local model=data.models[training.modelId]
  local rate=EmpireMath.trainingRate(data.gpus,training.workTotal,e)
  local progress=if training.workTotal>0 then training.workDone/training.workTotal else 0
  local rows={row("Model",if model then model.name else "Unnamed run"),row("Progress",Format.percent(progress,0)),
   row("Time left",if rate>0 then countdown((training.workTotal-training.workDone)/rate) else "Waiting for compute")}
  local event=training.event
  if event and event.pending then
   local def=ModelConfig.getEvent(event.id)
   if def then
    local choices={}
    local list: {any}=def.choices or {}
    for _,c in list do table.insert(choices,c.label.." ("..c.desc..")") end
    pending=def
    table.insert(rows,row("Decision needed",def.title.." · "..table.concat(choices," or ")))
   end
  end
  table.insert(sections,{title="Training",rows=rows})
 else
  local last=JourneyMath.latest(data)
  table.insert(sections,{title="Training",rows={row("Status","No training running"),row("Last model",if last then last.name.." · "..string.format("%.1f",last.overall).." overall" else "None yet")}})
 end
 -- Data & hardware (until the first release: the journey's next step)
 local stock=ModelMath.dataSummary(data.data);local fleet=ModelMath.fleet(data.gpus)
 local size=nextSize(data);local journey=JourneyMath.progress(data,{sizeId=size.id})
 if (data.stats.modelsReleased or 0)==0 then
  table.insert(sections,{title="Data & hardware",rows={row("Training data",Format.tokens(stock.total).." tokens · "..Format.percent(stock.quality,0).." quality"),
   row("VRAM",tostring(fleet.vram).." GB · next size "..size.label.." needs "..tostring(size.vram).." GB"),row("Next step",journey.hint)}})
 end
 -- Research
 local job=e.researchJob;local ready,nextDef=nil,nil
 for _,def in EmpireConfig.RESEARCH do
  if not e.research[def.id] and (not def.prereq or e.research[def.prereq]) then
   if not nextDef then nextDef=def end
   if not ready and e.points>=def.points and data.money>=def.cost then ready=def end
  end
 end
 local researchRows={}
 if job then
  local def=EmpireConfig.find(EmpireConfig.RESEARCH,job.id)
  table.insert(researchRows,row("Active",(if def then def.name else job.id).." · "..Format.percent(job.elapsed/math.max(1,job.seconds),0).." · "..tostring(math.ceil(job.seconds-job.elapsed)).." s left"))
 else table.insert(researchRows,row("Active","Nothing is being researched")) end
 if ready then table.insert(researchRows,row("Affordable now",ready.name.." · "..Format.money(ready.cost).." · "..tostring(ready.points).." RP"))
 elseif nextDef then
  local missing={}
  if e.points<nextDef.points then table.insert(missing,tostring(math.ceil(nextDef.points-e.points)).." RP") end
  if data.money<nextDef.cost then table.insert(missing,Format.money(nextDef.cost-data.money)) end
  table.insert(researchRows,row("Next project",nextDef.name.." · needs "..table.concat(missing," and ").." more"))
 else
  local level=math.floor(tonumber(e.labLevel) or 0)
  table.insert(researchRows,row("Next project",if level<Ops.LAB_MAX then string.format("Every project is complete · Lab level %d / %d in Lab → Models",level,Ops.LAB_MAX) else "Every project and Lab level is complete"))
 end
 table.insert(sections,{title="Research",rows=researchRows})
 -- Team
 local staff=EmpireMath.staff(e);local cap=EmpireConfig.OFFICES[stage].staff
 local counts=Recruiting.counts(s)
 local teamRows={row("Team",string.format("%d / %d desks filled",staff,cap))}
 local wf=live.workforce
 if typeof(wf)=="table" and typeof(wf.states)=="table" then
  local working,breaks,meetings,off=0,0,0,0
  for state,n in wf.states do
   if EmployeeConfig.productive(state)>=1 then working+=n
   elseif state=="COFFEE_BREAK" or state=="LUNCH" then breaks+=n
   elseif state=="MEETING" or state=="TALKING" then meetings+=n
   elseif state=="OFF_DUTY" or state=="LEAVING" or state=="ARRIVING" then off+=n end
  end
  table.insert(teamRows,row("In the building now",string.format("%d working · %d on a break · %d in meetings · %d off duty",working,breaks,meetings,off)))
 else table.insert(teamRows,row("In the building now","Activity appears once your headquarters is open")) end
 table.insert(teamRows,row("Applications",string.format("%d open · %d candidate%s in the visitor lounge",counts.open,counts.waiting,if counts.waiting==1 then "" else "s")))
 local hrAuto=Ops.hrSettings(e)
 table.insert(teamRows,row("HR",if hrAuto then "Automatic hiring is on (Team → Settings)" else "Automatic hiring is off: hire in Team → Staff"))
 table.insert(sections,{title="Team",rows=teamRows})
 -- Recommendations: a pending training decision, then the Next goal, then simple rules over the same numbers.
 if pending then recommend("Decide the training event in the Lab: "..pending.title..".","lab") end
 local goal=EmpireMath.nextGoal(data,live)
 if goal then
  local text,app,section=goalRecommendation(s,goal,stock,journey,unreleased)
  recommend(text,app,section)
 end
 -- the safety rules come right after the goal (CORE_SPEC 8.2 keeps the goal first)
 if paused or leaveN>0 or data.money<0 then
  local net=((tonumber(live.revenue) or 0)-(tonumber(live.cost) or 0))*Ops.DAY
  recommend(string.format("Cash is %s%s: raise prices in Market → My AIs, lower the HR budget or pause HR in Team → Settings.",Format.money(data.money),
   if net<0 then string.format(" and falling by %s/day",Format.money(-net)) else ""),"empire","settings")
 end
 if unreleased and not (goal and goal.id=="release") then recommend("Release "..unreleased.name.." in Deployment. It isn't earning anything yet.","lab","release") end
 if recent and delta and recent<0 and delta<=0 then recommend("Profit is negative and not improving. Reduce staff or raise prices.","market") end
 if waiting>0 then
  local advice=computeAdvice(data,data.money,live)
  recommend(string.format("%s users are waiting for server capacity: %s.",Format.int(waiting),adviceText(advice)),if advice.kind=="rack" and advice.extra<1 and advice.nextOffice then "empire" else "compute",if advice.kind=="rack" and advice.extra<1 and advice.nextOffice then "office" else nil)
 end
 if not training and journey.missingVram>0 and (data.stats.modelsReleased or 0)==0 then recommend("Buy GPUs in Lab → GPUs or pick a smaller size: "..journey.hint..".","compute") end
 if counts.waiting>0 then recommend(string.format("%d candidate%s waiting in the visitor lounge.",counts.waiting,if counts.waiting==1 then " is" else "s are"),"empire","team") end
 if not job and ready and live.ops and live.ops.saveMode~=true then recommend("Start research: "..ready.name..".","empire","research") end
 if counts.open>0 then recommend(string.format("%d new application%s. Invite promising people for an interview.",counts.open,if counts.open==1 then "" else "s"),"empire","team") end
 if not hrAuto and staff<cap*.25 and data.money>=10000 then recommend(string.format("Hire more specialists: %d desks are empty.",cap-staff),"empire","team") end
 if #recs==0 then
  table.insert(recs,{text=if recent then "Everything is on track: profit is "..Format.money(recent*20).."/day. Keep training bigger models." else "Everything is on track. Keep training bigger models."})
 end
 local assistantName=name or Assistant.identity(s.userId)
 return {name=assistantName,role=Assistant.TITLE,sections=sections,recommendations=recs,company=if data.company then data.company.name else nil}
end
-- One-line insight for notices (the most urgent recommendation).
function Assistant.insight(s: any): string
 return Assistant.briefing(s).recommendations[1].text
end

-- NPC ----------------------------------------------------------------------------------------------
local function homeOf(rec: any): (Vector3,any)
 local post=Plan.postRoom(rec.tier,"assistant") or "F_ASSIST"
 for _,w in Workstations.scan(rec.office).all do
  if w.room==post and w.kind=="Computer" and w.model.Parent then return w.position,w end
 end
 local r=Plan.room(rec.tier,post)
 local level=Plan.founderLevel(rec.tier)
 if r then return rec.cf*Vector3.new((r.x1+r.x2)/2,Plan.levelY(r.level)+3,(r.z1+r.z2)/2),nil end
 return rec.cf*Vector3.new(32,Plan.levelY(level)+3,-5),nil
end
local function settle(rec: any)
 local e=rec.e
 local _,desk=homeOf(rec)
 if desk and Workstations.reserve(desk,e) then
  e.task={id="Assistant",state="WORKING"}
  if Workstations.perform(e,clock()) then e.model:SetAttribute("Activity","WORKING");return end
 end
 -- standing post: face the reception door (building west)
 NPC.face(e,e.root.Position-rec.cf:VectorToWorldSpace(Vector3.xAxis));e.root.Anchored=true
 e.model:SetAttribute("Activity","WORKING")
end
local function dropCup(rec: any)
 local cup=rec.model:FindFirstChild("EmployeeCup");if cup then cup:Destroy() end
 rec.model:SetAttribute("HoldingCup",false);rec.cup=false;rec.e.carryCupUntil=nil
end
local function makeCup(rec: any)
 local arm=rec.model:FindFirstChild("Right Arm")
 if not rec.model:FindFirstChild("EmployeeCup") and arm and arm:IsA("BasePart") then
  local p=Instance.new("Part");p.Name="EmployeeCup";p.Size=Vector3.new(.5,.7,.5);p.Color=Color3.fromRGB(230,225,210);p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Massless=true
  p.CFrame=arm.CFrame*CFrame.new(0,-.8,-.55);p.Parent=rec.model
  local weld=Instance.new("WeldConstraint");weld.Part0=arm;weld.Part1=p;weld.Parent=p
 end
 rec.model:SetAttribute("HoldingCup",true);rec.cup=true
 rec.e.carryCupUntil=math.huge -- WorkstationService.release must not take the cup away
end
local goHome: (rec: any)->()
local function leavePost(rec: any)
 Workstations.release(rec.e);rec.e.model:SetAttribute("Activity","WALKING")
end
goHome=function(rec: any)
 local home=homeOf(rec)
 leavePost(rec);rec.state="toPost"
 mover.go(rec.e,home,clock(),function(ok: boolean)
  if records[rec.office]~=rec or rec.state~="toPost" then return end
  if ok then settle(rec);rec.state=if rec.cup then "waitCup" else "post"
  else rec.state="retryHome";rec.retryAt=clock()+5 end
 end)
end
-- Coffee point: nearest free Coffee activity (her floor first: other floors count 80 studs per level),
-- else the nearest machine part, else the planned tea kitchen of the founder floor.
local function coffeeSpot(rec: any): (Vector3,any,BasePart?)
 local reg=Workstations.scan(rec.office);local level=Plan.founderLevel(rec.tier);local here=rec.e.root.Position
 local best,score=nil,math.huge
 for _,w in reg.byKind.Coffee or {} do
  if w.model.Parent and Workstations.available(w,rec.e) then
   local d=NPC.flat(w.position,here)+math.abs((w.floor or 0)-level)*80
   if d<score then best=w;score=d end
  end
 end
 if best then return best.position,best,Workstations.machineFor(rec.office,best) end
 local machine: BasePart?=nil;score=math.huge
 for _,m in reg.machines do
  if m.Parent then
   local l=rec.cf:PointToObjectSpace(m.Position)
   local d=NPC.flat(m.Position,here)+math.abs((Plan.levelAt(rec.tier,l.Y) or 0)-level)*80
   if d<score then machine=m;score=d end
  end
 end
 if machine then
  local l=rec.cf:PointToObjectSpace(machine.Position);local toward=rec.cf:PointToObjectSpace(here)-l
  local offset=Vector3.new(toward.X,0,toward.Z);offset=if offset.Magnitude>.1 then offset.Unit*2.5 else Vector3.new(0,0,2.5)
  local floorY=Plan.levelY(Plan.levelAt(rec.tier,l.Y) or level)
  return rec.cf*Vector3.new(l.X+offset.X,floorY+3,l.Z+offset.Z),nil,machine
 end
 local r=Plan.room(rec.tier,Plan.postRoom(rec.tier,"pantry") or "F_PANTRY")
 if r then return rec.cf*Vector3.new((r.x1+r.x2)/2,Plan.levelY(r.level)+3,(r.z1+r.z2)/2),nil,nil end
 return here,nil,nil
end
local function steam(machine: BasePart?)
 if not machine then return end
 for _,d in machine:GetDescendants() do if d:IsA("ParticleEmitter") then d:Emit(5) end end
end
local function brew(rec: any)
 local e=rec.e;rec.state="brewing";rec.brewUntil=clock()+Assistant.BREW_SECONDS
 local w=rec.coffeeStation
 if w and Workstations.reserve(w,e) then e.task={id="Coffee",state="COFFEE_BREAK"};Workstations.perform(e,clock())
 elseif rec.machine then Sound.play(rec.machine,"coffee") end
 e.model:SetAttribute("Activity","COFFEE_BREAK")
 steam(rec.machine)
end
local function refund(rec: any,text: string)
 if rec.paid then Economy.grant(rec.session,rec.paid,"campus");rec.paid=nil end
 notify(rec.session,rec.name..": "..text)
end
local function fetchCoffee(rec: any,usePlan: boolean)
 local target,w,machine=coffeeSpot(rec)
 if usePlan then
  local r=Plan.room(rec.tier,Plan.postRoom(rec.tier,"pantry") or "F_PANTRY")
  if r then target=rec.cf*Vector3.new((r.x1+r.x2)/2,Plan.levelY(r.level)+3,(r.z1+r.z2)/2);w=nil end
 end
 rec.coffeeStation=w;rec.machine=machine;rec.state="toCoffee"
 mover.go(rec.e,target,clock(),function(ok: boolean)
  if records[rec.office]~=rec or rec.state~="toCoffee" then return end
  if ok then brew(rec)
  elseif not usePlan then fetchCoffee(rec,true)
  else refund(rec,"Sorry, I can't get to a coffee machine right now. I've cancelled the order.");goHome(rec) end
 end)
end
local function handover(rec: any)
 local s=rec.session
 local ok=Facility.deliverSnack(s,"coffee",true)
 dropCup(rec)
 if ok then rec.paid=nil;notify(s,rec.name..": Here's your coffee — "..lowerFirst(Assistant.insight(s)))
 else refund(rec,"Your snack bag is full, so I took the coffee back. No charge.") end
 goHome(rec)
end
local function finishBrew(rec: any)
 Workstations.release(rec.e);makeCup(rec)
 local root=founderRoot(rec)
 if root and inside(rec,root.Position) then
  rec.state="toFounder";rec.chaseStart=clock();rec.retargetAt=0;rec.lastTarget=nil;rec.e.model:SetAttribute("Activity","WALKING")
 else goHome(rec) end
end
local function chase(rec: any,now: number)
 local root=founderRoot(rec);local e=rec.e
 if not root or not inside(rec,root.Position) or now-rec.chaseStart>Assistant.GIVE_UP then goHome(rec);return end
 if NPC.flat(root.Position,e.root.Position)<=Assistant.HANDOVER and math.abs(root.Position.Y-e.root.Position.Y)<6 then handover(rec);return end
 local target=root.Position
 if now>=rec.retargetAt and (rec.lastTarget==nil or (rec.lastTarget-target).Magnitude>3) then
  rec.retargetAt=now+Assistant.RETARGET
  if Plan.employeeAllowed(e.role,rec.tier,rec.cf:PointToObjectSpace(target)) then
   rec.lastTarget=target
   mover.go(e,target,now,function(_ok: boolean) if rec.state=="toFounder" then rec.lastTarget=nil end end)
  else
   -- the founder is somewhere she may not enter: wait here and try again shortly
   mover.cancel(e);rec.lastTarget=nil
  end
 end
end
local function proactive(rec: any,now: number)
 local s=rec.session;local root=founderRoot(rec);if not root then return end
 local near=(root.Position-rec.e.root.Position).Magnitude<=Assistant.GREET_RANGE
 if not near then return end
 local level=Plan.levelAt(rec.tier,rec.cf:PointToObjectSpace(root.Position).Y)
 if not greeted[s] and level==Plan.founderLevel(rec.tier) then
  greeted[s]=true
  local hour=EmployeeConfig.hour(now)
  local hello=if hour>=5 and hour<12 then "Good morning" elseif hour>=12 and hour<18 then "Good afternoon" else "Good evening"
  notify(s,rec.name..": "..hello..", "..s.player.DisplayName.."! "..Assistant.insight(s).." Talk to me any time for a briefing or a coffee.")
  reminded[s]=now
  return
 end
 local training=s.data.training
 if training and training.event and training.event.pending and now-(reminded[s] or -math.huge)>=Assistant.REMIND_EVERY then
  reminded[s]=now
  local def=ModelConfig.getEvent(training.event.id)
  notify(s,rec.name..": The training run needs your decision"..(if def then " ("..def.title..")" else "")..". Open the Lab to choose.")
 end
end
local function attach(p: any,s: any): any
 local office: Model=p.office;local cf: CFrame=p.cframe
 local tierAttr=office:GetAttribute("OfficeTier");local tier: number=if typeof(tierAttr)=="number" then tierAttr else Plan.tierForOffice(s.data.empire.office)
 local folder: Instance?=office:FindFirstChild("Assistant")
 if folder then folder:ClearAllChildren() else local created=Instance.new("Folder");created.Name="Assistant";created.Parent=office;folder=created end
 local name,seed=Assistant.identity(s.userId)
 -- a bigger office than last time this session: the briefing warns about the short profit dip (CORE_SPEC 9.5)
 local officeIndex=math.floor(tonumber(s.data.empire.office) or 1)
 local before=seenOffice[s]
 if before and officeIndex>before then
  movedAt[s]=tonumber(s.data.empire.seconds) or 0
  notify(s,name..": Welcome to the new HQ! Profit dips for about 15 minutes while the new people start.")
 end
 seenOffice[s]=officeIndex
 local rec: any={office=office,cf=cf,tier=tier,session=s,plot=p,name=name,seed=seed,state="post",cup=false}
 local home=homeOf(rec)
 local model=Rig.build(folder::Instance,s.userId,INDEX,"marketer",CFrame.new(home),{n=name,s=seed})
 NPC.dress(model,"assistant",Assistant.TITLE,"Talk","assistant",{},Color3.fromRGB(176,140,96))
 rec.model=model;rec.e=NPC.record(model,"assistant",INDEX,tier,cf,office,seed)
 records[office]=rec
 settle(rec)
 return rec
end
local function drop(rec: any)
 mover.cancel(rec.e)
 if rec.paid then Economy.grant(rec.session,rec.paid,"campus");rec.paid=nil end
 if rec.model.Parent then rec.model:Destroy() end
 if records[rec.office]==rec then records[rec.office]=nil end
end
function Assistant.recordFor(s: any): any
 for _,rec in records do if rec.session==s then return rec end end
 return nil
end

-- Actions -------------------------------------------------------------------------------------------
function Assistant.payload(s: any): any
 local rec=Assistant.recordFor(s)
 local brief=Assistant.briefing(s,if rec then rec.name else nil)
 local def=CampusConfig.find(CampusConfig.SNACKS,"coffee")
 local cooldown=math.max(0,(orders[s] or -math.huge)+Assistant.COFFEE_COOLDOWN-clock())
 brief.coffee={price=def.price,cooldown=math.ceil(cooldown),state=if rec then rec.state else "absent",carrying=rec~=nil and rec.cup==true}
 brief.seed=if rec then rec.seed else select(2,Assistant.identity(s.userId))
 return brief
end
-- (ok, error code)
function Assistant.order(s: any): (boolean,string?)
 local rec=Assistant.recordFor(s)
 if not rec then return false,"NO_ASSISTANT" end
 if rec.cup or not (rec.state=="post" or rec.state=="toPost" or rec.state=="retryHome") then return false,"ASSISTANT_BUSY" end
 if (orders[s] or -math.huge)+Assistant.COFFEE_COOLDOWN>clock() then return false,"COFFEE_COOLDOWN" end
 local def=CampusConfig.find(CampusConfig.SNACKS,"coffee")
 local total=0;for _,n in s.data.empire.campus.snacks do total+=n end
 if total>=16 then return false,"SNACK_FULL" end
 if not Economy.spend(s,def.price,"campus") then notify(s,rec.name..": The company account can't cover a coffee right now.");return false,"NO_MONEY" end
 orders[s]=clock();rec.paid=def.price
 leavePost(rec)
 fetchCoffee(rec,false)
 return true,nil
end
local function act(s: any,p: any): any
 if p.action=="coffee" then
  local ok,err=Assistant.order(s)
  return {ok=ok,err=err,assistant=Assistant.payload(s)}
 elseif p.action=="brief" then
  return {ok=true,assistant=Assistant.payload(s)}
 end
 return {ok=false,err="BAD_INPUT"}
end
Assistant._act=act -- tests
local function onPrompt(q: ProximityPrompt,player: Player)
 if q:GetAttribute("PeopleAction")~="assistant" or q:GetAttribute("OwnerUserId")~=player.UserId then return end
 local s=Session.get(player);if not s or s.closed then return end
 local rec=Assistant.recordFor(s);local root=founderRoot(rec or {session=s})
 if not rec or not root or (root.Position-rec.e.root.Position).Magnitude>12 then return end
 if rec.cup and (rec.state=="waitCup" or rec.state=="post" or rec.state=="toPost" or rec.state=="toFounder") then handover(rec) end
 Remote.fire(player,"Notify","ASSISTANT_OPEN",Assistant.payload(s))
end
Assistant._prompt=onPrompt -- tests

-- Ticks ---------------------------------------------------------------------------------------------
local function step(rec: any,now: number)
 local e=rec.e
 e.now=now
 mover.tick(e,now)
 NPC.holdDoors(e,now)
 if rec.state=="brewing" then
  if now>=rec.brewUntil then finishBrew(rec) end
 elseif rec.state=="toFounder" then chase(rec,now)
 elseif rec.state=="retryHome" and now>=(rec.retryAt or 0) then goHome(rec) end
 proactive(rec,now)
end
function Assistant.tick(dt: number)
 local now=clock()
 scanClock+=dt
 if scanClock>=1 then
  scanClock=0
  for office,rec in records do
   if not office.Parent or rec.session.closed or not rec.model.Parent or not rec.e.root.Parent then drop(rec) end
  end
  for _,p in Plot.all() do
   if p.office and p.owner then
    local s=Session.get(p.owner)
    if s and not s.closed and not records[p.office] and now>=(failed[p.office] or -math.huge) then
     local ok,err=pcall(attach,p,s)
     if not ok then failed[p.office]=now+30;warn("[Assistant] could not place the assistant: "..tostring(err)) end
    end
   end
  end
 end
 for _,rec in records do step(rec,now) end
end
function Assistant.init()
 Remote.bind("AssistantAction",{burst=3,perSecond=1,company=true},act)
 Prompts.PromptTriggered:Connect(onPrompt)
 Session.onClosing(function(s)
  for _,rec in records do if rec.session==s then drop(rec) end end
 end)
end
return Assistant
