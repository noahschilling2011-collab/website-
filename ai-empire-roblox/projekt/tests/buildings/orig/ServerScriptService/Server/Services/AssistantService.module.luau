--!strict
-- The founder's personal assistant: one Executive Assistant NPC per headquarters (folder Office.Assistant).
-- Identity: feminine first name and appearance seed derived from the owner id (stable across visits),
-- built with EmployeeRigDesign; role "assistant" (BuildingPlan clearance public + staff + founder).
-- Home post: the desk station of the founder reception F_ASSIST (fallback: the planned room centre).
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
function Assistant.briefing(s: any,name: string?): any
 local data=s.data;local live=s.live;local e=data.empire
 local sections={};local recs={}
 local function recommend(text: string,app: string?,section: string?)
  if #recs<3 then table.insert(recs,{text=text,app=app,section=section}) end
 end
 -- Finances
 local recent,delta=trend(e.history)
 local trendText="Not enough data yet (one sample every 10 s)."
 if recent and delta then
  local steady=math.abs(delta)<math.max(5,math.abs(recent)*.05)
  trendText=if steady then "Steady at "..Format.money(recent).."/min"
   elseif delta>0 then "Rising: "..Format.money(recent).."/min ("..(if delta>=0 then "+" else "")..Format.money(delta)..")"
   else "Falling: "..Format.money(recent).."/min ("..Format.money(delta)..")"
 end
 table.insert(sections,{title="Finances",rows={row("Cash",Format.money(data.money)),row("Revenue",Format.money(live.revenue*60).."/min"),
  row("Costs",Format.money(live.cost*60).."/min"),row("Profit trend",trendText)}})
 -- Training
 local training=data.training;local pending=nil
 if training then
  local model=data.models[training.modelId]
  local rate=EmpireMath.trainingRate(data.gpus,training.workTotal,e)
  local progress=if training.workTotal>0 then training.workDone/training.workTotal else 0
  local rows={row("Model",if model then model.name else "Unnamed run"),row("Progress",Format.percent(progress,0)),
   row("Time left",if rate>0 then Format.duration((training.workTotal-training.workDone)/rate) else "Waiting for compute")}
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
 -- Models
 local best: any,liveCount,unreleased: any=nil,0,nil
 for _,id in data.modelOrder do
  local m=data.models[id]
  if m and m.status~="training" then
   if not best or m.overall>best.overall then best=m end
   if m.status=="live" then liveCount+=1 elseif m.status=="trained" and not unreleased then unreleased=m end
  end
 end
 table.insert(sections,{title="Models",rows={row("Best model",if best then best.name.." · "..string.format("%.1f",best.overall).." overall" else "No trained model yet"),
  row("Live models",tostring(liveCount)),row("Users",Format.compact(live.users))}})
 -- Data & hardware
 local stock=ModelMath.dataSummary(data.data);local fleet=ModelMath.fleet(data.gpus)
 local size=nextSize(data);local journey=JourneyMath.progress(data,{sizeId=size.id})
 table.insert(sections,{title="Data & hardware",rows={row("Training data",Format.tokens(stock.total).." tokens · "..Format.percent(stock.quality,0).." quality"),
  row("VRAM",tostring(fleet.vram).." GB · next size "..size.label.." needs "..tostring(size.vram).." GB"),row("Next step",journey.hint)}})
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
 else table.insert(researchRows,row("Next project","Every project is complete")) end
 table.insert(sections,{title="Research",rows=researchRows})
 -- Team
 local staff=EmpireMath.staff(e);local cap=EmpireConfig.OFFICES[e.office].staff
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
 table.insert(sections,{title="Team",rows=teamRows})
 -- Recommendations: simple rules over the same numbers, most urgent first.
 if pending then recommend("Decide the training event in the Lab: "..pending.title..".","lab") end
 if unreleased then recommend("Release "..unreleased.name.." in Deployment. It isn't earning anything yet.","lab","release") end
 if recent and delta and recent<0 and delta<=0 then recommend("Profit is negative and not improving. Reduce staff or raise prices.","market") end
 if not training and journey.missingVram>0 then recommend("Buy GPUs in Hardware or pick a smaller size: "..journey.hint..".","compute") end
 if not training and stock.total<ModelConfig.TRAINING.minTokens then recommend("Collect at least "..Format.tokens(ModelConfig.TRAINING.minTokens).." tokens in Data before training.","data") end
 if not training and data.stats.modelsTrained==0 and stock.total>=ModelConfig.TRAINING.minTokens and journey.missingVram==0 then recommend("Design and train your first model in the Lab.","lab") end
 if counts.waiting>0 then recommend(string.format("%d candidate%s waiting in the visitor lounge.",counts.waiting,if counts.waiting==1 then " is" else "s are"),"empire","team") end
 if not job and ready then recommend("Start research: "..ready.name..".","empire","research") end
 if counts.open>0 then recommend(string.format("%d new application%s. Invite promising people for an interview.",counts.open,if counts.open==1 then "" else "s"),"empire","team") end
 if staff<cap*.25 and data.money>=10000 then recommend(string.format("Hire more specialists: %d desks are empty.",cap-staff),"empire","team") end
 if #recs==0 then
  table.insert(recs,{text=if recent then "Everything is on track: profit is "..Format.money(recent).."/min. Keep training bigger models." else "Everything is on track. Keep training bigger models."})
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
 for _,w in Workstations.scan(rec.office).all do
  if w.room=="F_ASSIST" and w.kind=="Computer" and w.model.Parent then return w.position,w end
 end
 local r=Plan.room(rec.tier,"F_ASSIST")
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
 local r=Plan.room(rec.tier,"F_PANTRY")
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
 if rec.paid then Economy.grant(rec.session,rec.paid);rec.paid=nil end
 notify(rec.session,rec.name..": "..text)
end
local function fetchCoffee(rec: any,usePlan: boolean)
 local target,w,machine=coffeeSpot(rec)
 if usePlan then
  local r=Plan.room(rec.tier,"F_PANTRY")
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
 local tierAttr=office:GetAttribute("OfficeTier");local tier: number=if typeof(tierAttr)=="number" then tierAttr else s.data.empire.office
 local folder: Instance?=office:FindFirstChild("Assistant")
 if folder then folder:ClearAllChildren() else local created=Instance.new("Folder");created.Name="Assistant";created.Parent=office;folder=created end
 local name,seed=Assistant.identity(s.userId)
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
 if rec.paid then Economy.grant(rec.session,rec.paid);rec.paid=nil end
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
 if not Economy.spend(s,def.price) then notify(s,rec.name..": The company account can't cover a coffee right now.");return false,"NO_MONEY" end
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
