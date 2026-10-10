--!strict
-- One employee identity owns a real workstation, a bounded navigator and a role-specific task state machine.
-- Economy (CORE_SPEC 5.1, 11.5): this service NEVER writes money or department output. Output is
-- WorkforceMath.count = CompanyOps.output, computed from saved data and the clock only, so a company
-- produces exactly the same whether its owner, a visitor or nobody stands near it. The state machine
-- below only animates the schedule and publishes live.workforce (visible counts, states) for screens.
-- LOD: an employee holding a lift ticket (or riding) never goes to "sleep"; sleeping mid-walk cancels
-- only the walk and keeps identity, station reservation and task, and the walk resumes on wake.
-- Visible work (StaffJobs): operations staff run their job steps (EmployeeConfig.JOBS), employees take a
-- real lunch (servery queue, plate, seat, tray return); held items and poses are rig attributes the client
-- renders (Holding / Pose), props are driven by one FxUntil write per use (PropFx contract).
-- Talking to employees is TalkService's job (the "EmployeeTalk" prompts); Staff.recordOf gives it the
-- live record (state, task, station) of a rig.
-- staffops: ONE clock (CORE_SPEC 6): the shown hour, Lighting.ClockTime, CompanyHour and every schedule come
-- from CompanyOps.hour(workspace:GetServerTimeNow()), the clock the economy uses (trip departures, duty, IT
-- on duty, news stamps); `time` stays a monotonic timer for e.next / cooldowns / Nav.pump (it starts at the
-- server time and is never behind it, so EmployeeConfig.hour(Staff.now()) shows the same hour).
-- Who is on duty (StaffRota, CORE_SPEC 5.3 / 11.1): absent people (vacation, sick, unpaid leave, trips) stay
-- OFF_DUTY with their desk released (employees[role] never changes), night crews work 22-06, operations
-- posts follow a covering day shift (at stage 5 two night rota people take over security and IT at night),
-- apprentices follow their own schedule. Operations rigs that appear in a running office (a rebuilt post,
-- the Training Lead with a new apprentice batch, the night rota) are not new hires: no first day.
-- Visible flows (StaffEvents): first-day arrivals through reception, IT/engineer rack repairs in
-- sync with CompanyOps faults, the apprentices' tour, training session, shadowing and the Training Lead.
-- Staff changes (hire / fire / graduation) are applied incrementally: StaffAssignment keeps every unchanged
-- rig, StaffService registers the new ones (StaffRev) instead of recreating the whole office.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Physics=game:GetService("PhysicsService")
local Lighting=game:GetService("Lighting")
local Config=require(ReplicatedStorage.Shared.Config.EmployeeConfig)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local ModelMath=require(ReplicatedStorage.Shared.ModelMath)
local Workforce=require(ReplicatedStorage.Shared.WorkforceMath)
local Plot=require(script.Parent.PlotService)
local Session=require(script.Parent.SessionService)
local Workstations=require(script.Parent.WorkstationService)
local Nav=require(script.Parent.EmployeeNavigation)
local Jobs=require(script.Parent.StaffJobs)
local Ops=require(ReplicatedStorage.Shared.CompanyOps)
local Rota=require(script.Parent.StaffRota)
local Events=require(script.Parent.StaffEvents)
local Assignment=require(script.Parent.StaffAssignment)
local Staff={}
local caches: {[Instance]:any}={}
local records: {[Model]:any}={}
local evaluationFloors: {[number]:{[number]:boolean}}={}
-- monotonic campus timer (starts at the server clock, never falls behind it; see header)
local time=workspace:GetServerTimeNow();local accumulator=0;local ticks=0;local lastSky=-1
-- the ONE visible clock (CORE_SPEC 6): same hour and day index as the economy
local function shownHour(): number return Ops.hour(workspace:GetServerTimeNow()) end
local function shownDay(): number return math.floor(workspace:GetServerTimeNow()/Ops.DAY) end
local BREAKS={COFFEE_BREAK=true,LUNCH=true}
local QUOTA={researcher=2,engineer=2,marketer=1,curator=1}
local function state(e: any,name: string)
 e.state=name;e.model:SetAttribute("Activity",name)
end
local function jitter(e: any,max: number): number
 e.sequence+=1;return ((e.personality.seed+e.sequence*3571)%1000)/1000*max
end
local function nearest(position: Vector3,positions: {Vector3}): number
 local best=math.huge;for _,p in positions do best=math.min(best,(p-position).Magnitude) end;return best
end
local function destroy(e: any)
 Events.abort(e,e.cache);Jobs.abort(e,e.cache);Nav.cancel(e);Workstations.release(e);records[e.model]=nil
 if e.cache and e.cache.recordsSet then e.cache.recordsSet[e]=nil end
 if e.died then e.died:Disconnect();e.died=nil end
end
-- Street arrivals use the plaza in front of the entrance, car commuters the garage (B1; at plan tier 0 the
-- visitor bays in front of the garage): Plan.staffArrival.
local function commute(e: any): CFrame
 local base=Plan.staffArrival(e.tier,e.garage)
 return e.cf*CFrame.new(base+Vector3.new((e.index%5-2)*1.6,0,(e.index//5%3-1)*1.6))
end
-- On duty right now (StaffRota): absent people never, operations posts their covering day shift (or the
-- night rota), the night crew 22-06, everybody else the seeded shift.
local applyRota: (c: any,e: any,r: Rota.Snapshot)->()
local function onDutyAt(e: any,hour: number): boolean
 if e.role=="support" then
  if e.nightPerson then return Rota.nightRotaOnDuty(hour,e.shiftStart or 18,e.shiftEnd or 7.5) end
  return Rota.opsOnDuty(hour,e.shiftStart or 0,e.shiftEnd or 24,e.nightRota)
 end
 return Rota.hiredOnDuty(hour,e.personality.start,e.personality.finish,e.away,e.night)
end
-- Shift attributes for the talk lines ("My shift today runs from 7:15 to 18:20"); nil = around the clock
-- (night rota) or the seeded personality shift of hired staff.
local function shiftAttrs(e: any)
 local a,b=nil,nil
 if e.role=="support" then
  if not e.nightRota then a,b=e.shiftStart,e.shiftEnd end
 elseif e.night then a,b=Config.NIGHT_CREW.start,Config.NIGHT_CREW.finish end
 if e.model:GetAttribute("ShiftStart")~=a then e.model:SetAttribute("ShiftStart",a) end
 if e.model:GetAttribute("ShiftEnd")~=b then e.model:SetAttribute("ShiftEnd",b) end
end
-- Rota facts of one record (StaffRota snapshot): away today, night crew, night rota post, apprentice.
-- The apprentice look (lanyard, badge, size) follows graduation without a rebuild.
applyRota=function(c: any,e: any,r: Rota.Snapshot)
 if e.role=="support" then
  if e.nightPerson then return end
  local nightRota=Rota.nightRota(r,e.post or 0)
  if nightRota~=(e.nightRota==true) then e.nightRota=nightRota or nil;shiftAttrs(e) end
  return
 end
 local i=e.index-(r.before[e.role] or 0)
 local key=Rota.key(e.role,i)
 e.away=r.away[key]
 local night=r.night[key]==true
 if night~=(e.night==true) then e.night=night or nil;shiftAttrs(e) end
 local a: {age: number,skill: number,seed: number}?=r.apprentices[key]
 if a and a.seed~=e.personality.seed then a=nil end -- the profile at this index changed: next resync fixes it
 e.apprentice=a
 local dressed=e.model:GetAttribute("Apprentice")==true
 -- the rig's Skill follows the apprentice ramp (CompanyOps.apprentice: 1 -> 3) and, at graduation, the
 -- profile skill CompanyOps.graduate wrote; ordinary staff keep the Skill StaffAssignment gave them
 local skill: number?=if a then a.skill else nil
 if not a and dressed then
  local profiles=c.session.data.empire.staffProfiles
  local list=if typeof(profiles)=="table" then profiles[e.role] else nil
  local p=if typeof(list)=="table" then list[i] else nil
  if typeof(p)=="table" and typeof(p.k)=="number" and typeof(p.s)=="number" and math.floor(math.abs(p.s))%2147483647==e.personality.seed then skill=p.k end
 end
 if skill and skill~=e.skillK then e.skillK=skill;e.skill=Workforce.factor(skill);e.model:SetAttribute("Skill",skill) end
 if (a~=nil)~=dressed then Assignment.dressApprentice(e.model,a~=nil,c.session.data.empire) end
end
-- Off duty at the commute point (hidden by the client, never talked to, desk released).
local function park(e: any)
 Events.abort(e,e.cache);Jobs.abort(e,e.cache);Nav.cancel(e);Workstations.release(e)
 e.model:PivotTo(commute(e));e.root.Anchored=true;e.model:SetAttribute("OffDuty",true);state(e,"OFF_DUTY");e.next=time+e.index%7
end
-- One record per rig. mode "initial": spawn placement of a fresh office (off duty at the commute point,
-- a small staggered group arriving, everybody else at the desk); mode "added": a rig that appeared in a
-- running office (a hire, the Training Lead): a new hire arrives through reception (first day), later
-- shifts start normally.
local function register(c: any,m: Model,mode: string): any?
 if not m:IsA("Model") or not m.PrimaryPart then return nil end
 local h=m:FindFirstChildOfClass("Humanoid");local index=m:GetAttribute("StaffIndex")
 if not h or typeof(index)~="number" then return nil end
 local s=c.session
 local role=m:GetAttribute("RoleId") or "support"
 local skillAttr=m:GetAttribute("Skill")
 local e={model=m,root=m.PrimaryPart,humanoid=h,index=index,name=m:GetAttribute("EmployeeName"),role=role,skill=Workforce.factor(skillAttr),skillK=if typeof(skillAttr)=="number" then skillAttr :: number else 3,home=m:GetAttribute("HomeWorkstation"),cf=c.cf,tier=c.tier,office=c.office,session=s,personality=if typeof(m:GetAttribute("PersonalitySeed"))=="number" then Config.personalityFromSeed(m:GetAttribute("PersonalitySeed") :: number) else Config.personality(index,s.userId),sequence=0,state="SELECT_TASK",next=time+index%5*.7,lastBreak=time-index%80,lastMeeting=-200,now=time,taskStarted=time,cache=c}
 local work=m:GetAttribute("WorkCFrame");e.homePosition=if typeof(work)=="CFrame" then work.Position else m.PrimaryPart.Position
 e.garage=e.personality.seed%3==0
 if role=="support" then
  e.post=index-300
  -- the job loop needs a task even when the post is held by someone else right now (the night rota shares
  -- the stations of posts 3 / 6 with the day people; a step may run before the own post is reserved)
  e.task=Config.TASKS.support[1]
  -- a stage-5 night rota person (EmployeeConfig.NIGHT_ROTA) works the night at another post's station
  local dayPost=Config.NIGHT_ROTA[e.post]
  e.nightPerson=dayPost~=nil or nil
  if dayPost then
   -- hand-over at the day person's own shift ends (that rig's seeded Rota.opsShift): on when they leave,
   -- off when they are back the next morning
   local dayRig=if c.ops then c.ops:FindFirstChild("Employee_"..tostring(300+dayPost)) else nil
   local daySeed=if dayRig then dayRig:GetAttribute("PersonalitySeed") else nil
   if typeof(daySeed)=="number" then local a,b=Rota.opsShift(daySeed);e.shiftStart,e.shiftEnd=b,a
   else e.shiftStart,e.shiftEnd=Rota.nightRotaShift(e.personality.seed) end
  else e.shiftStart,e.shiftEnd=Rota.opsShift(e.personality.seed) end
 end
 for _,part in m:GetDescendants() do if part:IsA("BasePart") then part.CollisionGroup="CompanyEmployees" end end
 e.died=h.Died:Connect(function()
  -- A dead rig keeps its identity (counted as offscreen) but never holds a station or a route.
  e.dead=true;Events.abort(e,c);Nav.cancel(e);Workstations.release(e);state(e,"INACTIVE")
 end)
 records[m]=e;table.insert(c.all,e);c.recordsSet[e]=true
 if c.rota then applyRota(c,e,c.rota) end
 local hour=shownHour()
 local duty=onDutyAt(e,hour)
 e.onDuty=duty
 shiftAttrs(e)
 if mode=="added" then
  local seed=e.personality.seed
  if role=="support" then
   -- operations staff are no new hires (no badge at reception): on duty they walk in from the commute
   -- point to their post on the next tick (StaffService.tick shift start), else they wait off duty
   park(e)
   if duty then e.next=time+1 end
   return e
  end
  if not duty then
   park(e)
   Events.expect(c.office,seed,nil)
  elseif Events.held(c.office,seed) then
   park(e);e.next=time+1 -- the hired candidate is still walking out to the speed gates
  else
   local pending=Events.claim(c.office,seed)
   Events.arrive(e,c,if pending and pending.from then pending.from else commute(e))
  end
  return e
 end
 local home=Workstations.scan(c.office).byId[e.home]
 if home and Workstations.reserve(home,e) then
  e.task=(Config.TASKS[role] or Config.TASKS.support)[1]
  -- operations staff start their job loop soon; employees work a while at their desk first
  if Workstations.perform(e,time) then state(e,e.task.state);e.next=time+(if role=="support" then 2+jitter(e,8) else 35+jitter(e,100)) end
 end
 -- Spawn placement (not movement): people whose shift has not started (or is over, or who are away
 -- today) wait off duty at their commute point; a small staggered group arrives from the street or
 -- garage; everyone else starts at their real desk.
 if not duty then park(e)
 elseif role~="support" and index%24<3 then
  Nav.cancel(e);Workstations.release(e)
  m:PivotTo(commute(e));e.root.Anchored=false;state(e,"ARRIVING");e.next=time+index%12*.8
 end
 return e
end
-- Rigs added / removed / renumbered by StaffAssignment in a running office (StaffRev changed).
local function resync(c: any)
 c.rev=c.office:GetAttribute("StaffRev")
 -- the team changed: a fresh rota first (new apprentices, absences of the new people)
 c.rota=Rota.compute(c.session.data.empire,shownHour());c.rotaAt=time+2
 local seen: {[Model]:boolean}={}
 for _,group in {c.folder,c.ops} do if group then for _,m in group:GetChildren() do
  if not m:IsA("Model") then continue end
  local e=records[m]
  if e and e.cache==c then
   seen[m]=true
   local index=m:GetAttribute("StaffIndex");if typeof(index)=="number" then e.index=index end
   local home=m:GetAttribute("HomeWorkstation")
   if home~=e.home then
    e.home=home
    local work=m:GetAttribute("WorkCFrame");e.homePosition=if typeof(work)=="CFrame" then work.Position else e.homePosition
   end
   local k=m:GetAttribute("Skill");if typeof(k)=="number" then e.skillK=k;e.skill=Workforce.factor(k) end
  else
   local added=register(c,m,"added");if added then seen[m]=true end
  end
 end end end
 for i=#c.all,1,-1 do
  local e=c.all[i]
  if not seen[e.model] then destroy(e);table.remove(c.all,i) end
 end
end
local function sync(p: any,s: any): any
 local office=p.office;local folder=office:FindFirstChild("Employees");local ops=office:FindFirstChild("OperationsEmployees")
 local cached=caches[p.model]
 if cached and cached.office==office and cached.folder==folder and cached.ops==ops then
  if office:GetAttribute("StaffRev")~=cached.rev then resync(cached) end
  return cached
 end
 if cached then for _,e in cached.all do destroy(e) end end
 Workstations.reset(office)
 Workstations.scan(office)
 -- per-office passes are staggered by plot index (12 offices do not compute their rota in the same frame)
 local phase=((tonumber(p.index) or 0)%10)*.2
 local c={office=office,folder=folder,ops=ops,all={},recordsSet={},session=s,event={},cf=p.cframe,rev=office:GetAttribute("StaffRev"),phase=phase,eventsAt=time+phase,tier=(function(): number local t=office:GetAttribute("OfficeTier");return if typeof(t)=="number" then t else Plan.tierForOffice(s.data.empire.office) end)(),lastTraining=s.data.training~=nil,lastResearch=if s.data.empire.researchJob then s.data.empire.researchJob.id else nil,lastReleased=s.data.stats.modelsReleased,lastTrained=s.data.stats.modelsTrained,lastHardware=ModelMath.fleet(s.data.gpus).slotsUsed,lastData=ModelMath.dataSummary(s.data.data).total,nextMeeting=time+55,nextSocial=time+40,moving=0,onBreak=0,load={}}
 caches[p.model]=c
 c.rota=Rota.compute(s.data.empire,shownHour());c.rotaAt=time+2+phase
 for _,group in {folder,ops} do if group then for _,m in group:GetChildren() do register(c,m,"initial") end end end
 return c
end
-- Held drink/snack after a break: the client renders it from the rig's Holding attribute (no server
-- part). A coffee is carried back to the desk for 90 s; a snack bar is eaten at the counter.
local function cup(e: any,item: string)
 Workstations.setItem(e,item)
 e.carryUntil=if item=="cup" then time+90 else time+6
end
local function dropItems(e: any)
 if e.lunch then return end
 e.carryUntil=nil;Workstations.setItem(e,nil);Workstations.setPose(e,nil)
end
-- A task with `via` (e.g. InspectServer via the server cart): the Pickup activity in the station's room.
local function viaStation(e: any,def: any,w: any): any
 if not def.via or e.viaDone==w then return nil end
 for _,p in Workstations.scan(e.office).byKind[def.via] or {} do
  if p.room==w.room and Workstations.allowed(p,e) then return p end
 end
 return nil
end
local walk: (e: any,def: any,w: any)->()
-- Walk to a reserved station and start the task there; also used to resume a walk after LOD sleep.
walk=function(e: any,def: any,w: any)
 e.walkTask=def
 local pickup=viaStation(e,def,w)
 local target=if pickup then pickup.position else w.position
 Nav.go(e,target,time,function(ok)
  e.walkTask=nil
  if e.dead or not e.model.Parent then return end
  if ok and pickup and e.station==w then
   -- picked up the item at the via point (one Pose + one Holding write), then on to the station
   e.viaDone=w;state(e,def.state)
   local f=pickup.model:GetAttribute("FacingPosition")
   if typeof(f)=="Vector3" then local d=Vector3.new(f.X-e.root.Position.X,0,f.Z-e.root.Position.Z);if d.Magnitude>.2 then e.root.CFrame=CFrame.lookAt(e.root.Position,e.root.Position+d) end end
   Workstations.setPose(e,"reach");local item=pickup.model:GetAttribute("JobItem");Workstations.setItem(e,if typeof(item)=="string" then item else nil)
   e.pendingWalk={def=def,station=w,at=time+2.5};e.next=math.huge
   return
  end
  if ok and e.station==w and Workstations.perform(e,time) then
   state(e,def.state);local duration=def.seconds or {45,100};e.next=time+duration[1]+jitter(e,duration[2]-duration[1]);e.taskStarted=time
   if e.role=="support" then e.next=time+2+jitter(e,4) end -- back at the post: the job loop starts
   if def.state=="COFFEE_BREAK" then e.lastBreak=time;if def.id=="Coffee" or def.id=="FridgeDrink" then e.cupAt=time+4 end
   elseif def.state=="LUNCH" then e.lastLunch=shownDay()
   elseif def.state=="MEETING" or def.state=="TALKING" then e.lastMeeting=time;e.next=def.untilTime or e.next end
   if e.viaDone==w and e.item then Workstations.setPose(e,"reach") end -- carrying the blade to the rack
  else
   Workstations.release(e);state(e,"SELECT_TASK");e.next=time+5+jitter(e,8);dropItems(e)
   if def.state=="COFFEE_BREAK" then e.lastBreak=time-e.personality.breakEvery+45 elseif def.state=="LUNCH" then e.lunchRetry=time+20 end
  end
 end)
end
local function begin(e: any,def: any,w: any)
 if e.cache.moving>=Config.moverCap(e.role) then e.next=time+3;return end
 if not w then e.next=time+4+jitter(e,6);state(e,"WAIT_AT_DESK");return end
 Nav.cancel(e);Workstations.release(e)
 e.viaDone=nil;e.pendingWalk=nil
 if not e.carryUntil then dropItems(e) end -- a coffee stays in the hand on the way back to work
 if not Workstations.reserve(w,e) then e.next=time+3;state(e,"SELECT_TASK");return end
 e.cache.moving+=1;if BREAKS[def.state] then e.cache.onBreak+=1 end
 e.task=def;e.taskStarted=time;e.next=math.huge;e.model:SetAttribute("Task",def.id);state(e,"WALKING")
 walk(e,def,w)
end
local function breakRoom(c: any): boolean
 return c.onBreak<math.max(1,math.floor(#c.all*Config.BREAK_SHARE))
end
local function selectTask(e: any,c: any,hour: number)
 if c.moving>=Config.moverCap(e.role) then e.next=time+2+jitter(e,3);return end
 -- operations staff: their visible job loop (never a coffee walk; short breaks in place)
 if e.role=="support" then Jobs.next(e,c);return end
 if e.forced then local forced=e.forced;e.forced=nil;if (forced.task.untilTime or math.huge)>time+10 then begin(e,forced.task,forced.station);return end end
 local day=shownDay()
 local lunchEnd=e.personality.lunch+1.1+(if e.lunchDeferred==day then .9 else 0)
 if hour>=e.personality.lunch and hour<lunchEnd and e.lastLunch~=day and time>=(e.lunchRetry or 0) then
  if breakRoom(c) then
   local def={id="Lunch",type="Dining",department="kitchen",seconds={120,230},state="LUNCH"};local w=Workstations.choose(e,def)
   if w and Jobs.lunch(e,c,w,def) then c.onBreak+=1;return end
   e.lunchRetry=time+15
  else e.lunchDeferred=day;e.lunchRetry=time+12+jitter(e,10) end
 end
 if time-e.lastBreak>e.personality.breakEvery then
  if breakRoom(c) then
   e.breaks=(e.breaks or 0)+1
   -- about every tenth break is a wellness break (treadmill, bike, rower, weights, sauna, shower)
   if (e.personality.seed+e.breaks*3)%Config.WELLNESS_EVERY==0 then
    local def={id="Wellness",type="Wellness",department="wellness",seconds={40,70},state="COFFEE_BREAK"}
    local w=Workstations.choose(e,def);if w then begin(e,def,w);return end
   end
   local roof=e.personality.seed%7==0;local lounge=not roof and e.personality.seed%5==0;local drink=not roof and not lounge and e.personality.seed%4==0
   local coffee=not roof and not lounge and not drink and e.personality.coffee
   local def={id=if roof then "RoofBreak" elseif lounge then "LoungeBreak" elseif drink then "FridgeDrink" elseif coffee then "Coffee" else "Snack",type=if roof or lounge then "Lounge" elseif drink then "Fridge" elseif coffee then "Coffee" else "Snack",department=if roof then "roof" elseif lounge then "lounge" else "kitchen",nearest=coffee,seconds={20,55},state="COFFEE_BREAK"}
   local w=Workstations.choose(e,def);if w then begin(e,def,w);return end
   e.lastBreak=time-e.personality.breakEvery+40 -- nothing free: ask again later
  else e.lastBreak=time-e.personality.breakEvery+20+jitter(e,25) end
 end
 -- apprentices (staffops): practice at the own desk or sit next to a senior colleague; the tour and the
 -- training session are office events (StaffEvents.academyTick)
 if e.apprentice and Events.apprenticeTask(e,c) then return end
 local best,station=nil,nil;local score=-math.huge
 for _,def in Config.TASKS[e.role] or Config.TASKS.support do
  local w=Workstations.choose(e,def)
  if w then
   local load=(c.load[def.id] or 0)-(if e.task and e.task.id==def.id then 1 else 0)
   local p=Config.priority(e.role,def,c.event)+jitter(e,28)-load*1.6+(if Config.departmentMatch(def,w.department) then 8 else -10)
   if p>score then best=def;station=w;score=p end
  end
 end
 if best then begin(e,best,station) else e.next=time+6;state(e,"WAIT_AT_DESK") end
end
local function evaluation(tier: number): {[number]:boolean}
 local cached=evaluationFloors[tier];if cached then return cached end
 local set: {[number]:boolean}={}
 for _,r in Plan.rooms(tier) do if r.dept=="evaluation" then set[r.level]=true end end
 evaluationFloors[tier]=set;return set
end
local function free(room: any): {any}
 local out={}
 for _,w in room.seats do if w.model.Parent and not w.reserved and not (w.seat and w.seat.Occupant) then table.insert(out,w) end end
 return out
end
local function available(e: any): boolean
 -- apprentices keep their own schedule (tour, training, shadowing): not drafted into team meetings / chats
 return e.role~="support" and not e.dead and not e.talkHold and e.lod~="sleep" and not e.nav and not e.forced and not e.apprentice and not e.event and time-e.lastMeeting>=160
  and e.state~="LUNCH" and e.state~="COFFEE_BREAK" and e.state~="OFF_DUTY" and e.state~="LEAVING" and e.state~="ARRIVING" and e.state~="MEETING" and e.state~="TALKING" and e.state~="INACTIVE"
end
-- Any meeting room with >= 3 free Meeting seats. Reviews prefer the G project room and meeting rooms
-- on evaluation floors; team meetings take a room on the floor where most free colleagues are.
-- Participants come mostly from the room's floor; role quotas and cooldowns as before.
local function meeting(c: any,review: boolean)
 local eligible={};local perLevel={}
 for _,e in c.all do if available(e) then e.meetLevel=Workstations.levelOf(e);table.insert(eligible,e);perLevel[e.meetLevel]=(perLevel[e.meetLevel] or 0)+1 end end
 if #eligible<2 then return end
 local floors=evaluation(c.tier);local stamp=math.floor(time)
 local room,seats,best=nil,nil,-math.huge
 for id,r in Workstations.scan(c.office).meetings do
  local open=free(r);if #open<3 then continue end
  local here=perLevel[r.level] or 0
  local score=if review then (if id=="ProjectRoom" then 60 else 0)+(if floors[r.level] then 40 else 0)+here*2 else here*10+(if id=="Boardroom" then 4 else 0)
  score+=((#tostring(id)*37+stamp)%11)/10
  if score>best then room=r;seats=open;best=score end
 end
 if not room or not seats then return end
 local level=room.level
 table.sort(eligible,function(a,b)
  local da=math.abs(a.meetLevel-level);local db=math.abs(b.meetLevel-level)
  if da~=db then return da<db end
  local ka=(a.index*7+stamp)%13;local kb=(b.index*7+stamp)%13
  if ka~=kb then return ka<kb end
  return a.index<b.index
 end)
 local selected={};local roles={researcher=0,engineer=0,marketer=0,curator=0};local taken={};local limit=math.min(5,#seats)
 for _,e in eligible do
  if (roles[e.role] or 0)>=(QUOTA[e.role] or 0) then continue end
  local seat=nil;for _,w in seats do if not taken[w] and Workstations.available(w,e) then seat=w;break end end
  if not seat then continue end
  taken[seat]=true;table.insert(selected,{employee=e,seat=seat});roles[e.role]+=1
  if #selected>=limit then break end
 end
 if #selected<2 then return end
 local untilTime=time+150
 for i,s in selected do
  s.employee.forced={task={id=if review then "ModelReviewMeeting" else "TeamMeeting",state="MEETING",seconds={80,160},untilTime=untilTime},station=s.seat}
  s.employee.next=math.min(s.employee.next,time+i*1.3)
 end
 c.office:SetAttribute("MeetingTopic",if review then "MODEL REVIEW" else "TEAM REVIEW");c.office:SetAttribute("MeetingUntil",untilTime);c.office:SetAttribute("MeetingRoom",tostring(room.id))
end
local function conversation(c: any)
 local groups={}
 for _,w in Workstations.scan(c.office).byKind.Conversation or {} do
  if not w.reserved and w.model.Parent then local id=w.group or w.id;groups[id]=groups[id] or {};table.insert(groups[id],w) end
 end
 for _,seats in groups do if #seats>=2 then
  local selected={}
  for _,e in c.all do
   if e.personality.social>.55 and available(e) and time-e.lastMeeting>100 and (e.root.Position-seats[1].position).Magnitude<80 and math.abs(e.root.Position.Y-seats[1].position.Y)<8
    and Workstations.available(seats[#selected+1],e) then table.insert(selected,e);if #selected==2 then break end end
  end
  if #selected==2 then for i,e in selected do e.forced={task={id="DiscussWork",state="TALKING",seconds={25,45},untilTime=time+55},station=seats[i]};e.next=math.min(e.next,time+i) end;return end
 end end
end
local function events(c: any,s: any)
 local d=s.data;local trained=d.stats.modelsTrained;local hardware=ModelMath.fleet(d.gpus).slotsUsed;local data=ModelMath.dataSummary(d.data).total
 local review=trained>c.lastTrained
 if review then c.reviewUntil=time+150;c.nextMeeting=time+2 end
 if hardware>c.lastHardware then c.hardwareUntil=time+80 end
 if data>c.lastData+1e8 then c.dataUntil=time+80 end
 local live=false;for _,model in d.models do if model.status=="live" then live=true;break end end
 c.event={training=d.training~=nil,research=d.empire.researchJob~=nil,review=(c.reviewUntil or 0)>time,live=live,hardware=(c.hardwareUntil or 0)>time,data=(c.dataUntil or 0)>time}
 local research=if d.empire.researchJob then d.empire.researchJob.id else nil
 local changed=(research~=c.lastResearch) or d.stats.modelsReleased>c.lastReleased or (c.lastTraining~=(d.training~=nil)) or review or hardware>c.lastHardware
 if changed then for _,e in c.all do if (e.role=="engineer" or e.role=="researcher" or e.role=="marketer") and not e.nav and time-e.taskStarted>10 and e.state~="LUNCH" then e.next=math.min(e.next,time+e.index%9) end end end
 c.lastResearch=research;c.lastReleased=d.stats.modelsReleased
 c.lastTraining=d.training~=nil;c.lastTrained=trained;c.lastHardware=hardware;c.lastData=data
 if time>=c.nextMeeting then meeting(c,c.event.review);c.nextMeeting=time+180 end
 if time>=c.nextSocial then conversation(c);c.nextSocial=time+75 end
end
local function leave(e: any)
 if e.nav then return end
 -- the end-of-shift wave respects the office movers cap too (departures stagger instead of 40+ walkers)
 if e.cache.moving>=Config.moverCap(e.role) then e.next=time+2+jitter(e,4);return end
 e.cache.moving+=1
 Events.abort(e,e.cache);Jobs.abort(e,e.cache);dropItems(e)
 Workstations.release(e);e.task={id="Leaving",state="LEAVING"};state(e,"LEAVING");e.next=math.huge
 Nav.go(e,commute(e).Position,time,function(ok)
  if e.dead or not e.model.Parent then return end
  if ok then state(e,"OFF_DUTY");e.model:SetAttribute("OffDuty",true);e.root.Anchored=true;e.next=time+8;e.leaveFails=nil
  else
   -- no route home three times in a row (e.g. a post in the guest house): off duty where the route ends
   e.leaveFails=(e.leaveFails or 0)+1
   if e.leaveFails>=3 then e.leaveFails=nil;park(e) else state(e,"SELECT_TASK");e.next=time+12 end
  end
 end)
end
-- Rare fallback only (an employee found in a zone its role may not enter); never ordinary movement.
local function security(e: any)
 local pos=e.cf:PointToObjectSpace(e.root.Position)
 if Plan.employeeAllowed(e.role,e.tier,pos) then return end
 warn(string.format("[Staff] Security recovery: %s (%s) in a restricted zone at local %.1f, %.1f, %.1f; returned to the home desk",tostring(e.name),tostring(e.role),pos.X,pos.Y,pos.Z))
 Nav.cancel(e);Workstations.release(e)
 local home=e.model:GetAttribute("WorkCFrame")
 local target=if typeof(home)=="CFrame" and Plan.employeeAllowed(e.role,e.tier,e.cf:PointToObjectSpace(home.Position)) then home else commute(e)
 e.model:PivotTo(target);e.next=time+5;state(e,"SELECT_TASK")
end
-- Conversation hold (TalkService): the employee stays put; identity, task, station and state are kept
-- (the economy counts it exactly as before). A route in progress is re-issued on release with its own
-- callback, a job hop walks on, everything else continues where it was.
local HOLD_MAX=120
local function unhold(e: any)
 if not e.talkHold then return end
 e.talkHold=nil;e.talkHoldUntil=nil
 local held=e.heldNav;e.heldNav=nil
 local anchored=e.heldAnchored;e.heldAnchored=nil
 if e.dead or not e.model.Parent or not e.root.Parent then return end
 if anchored~=nil and not e.humanoid.SeatPart then e.root.Anchored=anchored end
 if held then Nav.go(e,held.target,time,held.callback) else Jobs.resume(e,time) end
end
local function setLod(e: any,lod: string)
 local was=e.lod;e.lod=lod;e.model:SetAttribute("SimulationLOD",lod)
 if lod=="sleep" then
  unhold(e)
  -- Keep identity, reservation and task; only the walk stops (resumed on wake). Lunch and job flows
  -- end cleanly (they restart from selectTask when somebody comes close again).
  local flow=e.lunch~=nil or e.jobStep~=nil or e.hop~=nil or e.event~=nil
  if flow then Events.abort(e,e.cache);Jobs.abort(e,e.cache);if e.lunch==nil and e.state=="LUNCH" then state(e,"SELECT_TASK") end;e.next=math.min(e.next,time+1) end
  e.pendingWalk=nil
  e.resumeWalk=e.nav~=nil and e.state=="WALKING" and e.station~=nil and e.walkTask~=nil and not flow
  local pending=e.walkTask
  Nav.cancel(e);e.walkTask=pending
  if flow and e.state=="WALKING" then Workstations.release(e);state(e,"SELECT_TASK") end
  e.humanoid.EvaluateStateMachine=false;e.root.Anchored=true
 elseif was=="sleep" or was==nil then
  if e.state=="OFF_DUTY" or e.state=="INACTIVE" then return end
  e.humanoid.EvaluateStateMachine=true
  -- nobody saw the shift end / the absence start while asleep: already at home, not walking out now
  if was=="sleep" and not onDutyAt(e,shownHour()) then park(e);return end
  if e.resumeWalk and e.station and e.walkTask then
   e.resumeWalk=false;e.root.Anchored=false;walk(e,e.walkTask,e.station);return
  end
  e.resumeWalk=false;e.walkTask=nil
  if e.state=="WALKING" or e.state=="LEAVING" then Workstations.release(e);state(e,"SELECT_TASK") end
  e.root.Anchored=e.station~=nil and e.station.seat~=nil
  e.next=math.min(e.next,time+e.index%11)
 end
end
function Staff.init()
 Jobs.bind({now=function(): number return time end,hour=shownHour,state=state,jitter=jitter})
 Events.bind({now=function(): number return time end,hour=shownHour,state=state,jitter=jitter,begin=begin})
 pcall(function()Physics:RegisterCollisionGroup("CompanyEmployees")end)
 pcall(function()Physics:RegisterCollisionGroup("CompanyPlayers")end)
 Physics:CollisionGroupSetCollidable("CompanyEmployees","CompanyEmployees",false)
 Physics:CollisionGroupSetCollidable("CompanyEmployees","CompanyPlayers",false)
 local function bindCharacter(char: Model)
  local function set(p: Instance)if p:IsA("BasePart") then p.CollisionGroup="CompanyPlayers" end end
  for _,p in char:GetDescendants() do set(p) end;char.DescendantAdded:Connect(set)
 end
 Session.onLoaded(function(s)if s.player.Character then bindCharacter(s.player.Character) end;s.player.CharacterAdded:Connect(bindCharacter)end)
 Session.onClosing(function(s)
  for model,c in caches do if c.session==s then for _,e in c.all do destroy(e) end;caches[model]=nil end end
 end)
end
-- Office rota (every 2 s): absences, night crew, night rota, apprentices; the Training Lead leaves with
-- the last apprentice (CORE_SPEC 11.1: the post exists only while there are apprentices). Rota.compute is
-- memoised: while nothing changed it returns the snapshot already applied and this pass ends here.
local function refreshRota(c: any,s: any,hour: number)
 if time<(c.rotaAt or 0) then return end
 c.rotaAt=time+2
 local r=Rota.compute(s.data.empire,hour)
 c.rota=r
 if c.rotaApplied==r then return end
 c.rotaApplied=r
 for i=#c.all,1,-1 do
  local e=c.all[i]
  if r.apprenticeCount==0 and e.role=="support" and e.model:GetAttribute("Role")=="Training Lead" then
   destroy(e);table.remove(c.all,i)
   if e.model.Parent then e.model:Destroy() end
  else applyRota(c,e,r) end
 end
end
function Staff.tick(dt: number)
 time=math.max(time+dt,workspace:GetServerTimeNow());accumulator+=dt;if accumulator<.2 then return end;accumulator=0;ticks+=1
 local positions={};for _,s in Session.all() do if not s.closed and s.player.Character and s.player.Character.PrimaryPart then table.insert(positions,s.player.Character.PrimaryPart.Position) end end
 local hour=shownHour()
 -- the sky follows the shown hour (written when it moved by at least 0.01 h, about 1 s of day time)
 local sky=math.abs(hour-lastSky);if math.min(sky,24-sky)>=.01 then lastSky=hour;Lighting.ClockTime=hour end
 local clock=workspace:GetServerTimeNow()
 for _,p in Plot.all() do if p.office and p.owner then
  local s=Session.get(p.owner);if not s or s.closed then continue end
  local c=sync(p,s);events(c,s)
  refreshRota(c,s,hour)
  c.moving=0;c.onBreak=0;c.load={}
  for _,e in c.all do
   if e.nav or e.hop then c.moving+=1 end
   if e.task then c.load[e.task.id]=(c.load[e.task.id] or 0)+1 end
   if BREAKS[e.state] or (e.state=="WALKING" and e.task and BREAKS[e.task.state]) then c.onBreak+=1 end
  end
  local counts={researcher=0,engineer=0,curator=0,marketer=0};local states={};local visible=0
  for _,e in c.all do
   e.now=time
   if e.dead or not e.root.Parent or not e.humanoid.Parent then
    if counts[e.role] then counts[e.role]+=e.skill end
    states.INACTIVE=(states.INACTIVE or 0)+1;continue
   end
   if e.carryUntil and time>=e.carryUntil and not e.lunch then e.carryUntil=nil;if e.item=="cup" or e.item=="snack" then Workstations.setItem(e,nil) end end
   local distance=nearest(e.root.Position,positions);local lod=if distance>Config.FAR then "sleep" elseif distance>Config.NEAR then "reduced" else "full"
   -- Never freeze an employee inside the moving cabin: sleep waits until the lift ticket is done.
   if lod=="sleep" and e.lod~="sleep" and Nav.liftBusy(e) then lod=e.lod or "reduced" end
   if lod~=e.lod then setLod(e,lod) end
   local productive=1
   if e.talkHold and time>=(e.talkHoldUntil or 0) then unhold(e) end -- safety: a lost release
   if e.lod~="sleep" then
    visible+=1
    if not e.talkHold and (ticks+e.index)%5==0 and not Nav.liftBusy(e) then security(e) end
    Nav.tick(e,time)
    local onDuty=onDutyAt(e,hour);e.onDuty=onDuty
    -- shift over: during the day the current task is finished first; once the office has closed (night
    -- hours pass at ~21 s per hour) the step ends within a few seconds, so nobody works until morning
    if onDuty then e.offAt=nil elseif not e.offAt and (hour>=18 or hour<8) then e.offAt=time+3+jitter(e,8) end
    if e.talkHold then
     -- in a conversation: no task changes, no walking (state and economy weight unchanged)
    elseif e.pendingWalk and time>=e.pendingWalk.at and not e.nav then
     local p=e.pendingWalk
     if c.moving>=Config.moverCap(e.role) then p.at=time+1 -- second leg (cart -> rack) waits for a free slot
     else
      e.pendingWalk=nil
      if e.station==p.station then c.moving+=1;state(e,"WALKING");walk(e,p.def,p.station) else e.next=time+1 end
     end
    elseif Jobs.busy(e) then Jobs.tick(e,c,time)
    elseif Events.busy(e) then
     if onDuty then Events.tick(e,c,time) else Events.abort(e,c);Jobs.abort(e,c);Nav.cancel(e);Workstations.release(e);state(e,"SELECT_TASK");e.next=time end
    elseif not onDuty and e.state~="OFF_DUTY" and e.state~="LEAVING" and not e.nav and (time>=e.next or time>=(e.offAt or math.huge)) then leave(e)
    elseif onDuty and (e.state=="OFF_DUTY" or e.state=="ARRIVING") and not e.nav and time>=e.next then
     if Events.held(c.office,e.personality.seed) then e.next=time+1
     else
      e.model:SetAttribute("OffDuty",false)
      local pending=Events.claim(c.office,e.personality.seed)
      -- first day of a hire (made while this person was off duty, or an interview hire): in through reception
      if pending then Events.arrive(e,c,pending.from or commute(e))
      else local def=(Config.TASKS[e.role] or Config.TASKS.support)[1];local home=Workstations.scan(e.office).byId[e.home] or Workstations.choose(e,def);begin(e,def,home) end
     end
    elseif onDuty and not e.nav and time>=e.next then selectTask(e,c,hour) end
    if e.cupAt and time>=e.cupAt then cup(e,if e.task and e.task.id=="Snack" then "snack" else "cup");e.cupAt=nil end
    productive=Config.productive(e.state)
   end
   if counts[e.role] then counts[e.role]+=productive*e.skill end
   states[e.state]=(states[e.state] or 0)+1
  end
  Jobs.officeTick(c)
  -- once a second: rack faults (blade states + repairs, in sync with CompanyOps) and the apprentices
  if time>=(c.eventsAt or 0) then
   c.eventsAt=math.max(c.eventsAt+1,time+.5)
   Events.rackTick(c,s,clock)
   Events.academyTick(c,hour,if c.rota then c.rota.day else Ops.day(s.data.empire))
  end
  s.live.workforce={researcher=counts.researcher,engineer=counts.engineer,curator=counts.curator,marketer=counts.marketer,visible=visible,total=#c.all,hour=hour,states=states}
  -- CompanyHour: written when the shown hour changes (PropFx "Hour" gate and screens read it)
  local shown=math.floor(hour*10)/10
  if c.lastHour~=shown then c.lastHour=shown;c.office:SetAttribute("CompanyHour",hour) end
 end end
 for model,c in caches do if not c.office.Parent then for _,e in c.all do destroy(e) end;caches[model]=nil end end
 Nav.pump(time)
end
-- TalkService: pause one employee for a conversation (false = not now: unknown, dead, asleep, off duty,
-- leaving or in the lift). The caller turns a standing NPC towards the player and calls release once.
function Staff.hold(model: Model,_face: Vector3): boolean
 local e=records[model]
 if not e or e.dead or not e.root.Parent or not e.humanoid.Parent or e.lod=="sleep" then return false end
 if e.state=="OFF_DUTY" or e.state=="LEAVING" or e.state=="INACTIVE" or Nav.liftBusy(e) then return false end
 e.talkHoldUntil=time+HOLD_MAX
 if e.talkHold then return true end
 e.talkHold=true
 local n=e.nav
 if n then e.heldNav={target=n.target,callback=n.callback};Nav.cancel(e) end
 Jobs.pause(e)
 if not e.humanoid.SeatPart then
  e.heldAnchored=e.root.Anchored
  e.humanoid:MoveTo(e.root.Position);e.root.Anchored=true
 end
 return true
end
function Staff.release(model: Model)
 local e=records[model]
 if e then unhold(e) end
end
-- Live record of an employee rig (TalkService reads state / task / station for dialogue). Read-only use.
function Staff.recordOf(model: Model): any
 return records[model]
end
-- Campus clock of the shared EmployeeNavigation queue (Nav.pump runs on it): other NPC drivers
-- (RecruitingService visitors, AssistantService) pass this time to Nav.go/Nav.tick.
function Staff.now(): number return time end
-- The visible company hour (CompanyOps.hour of the server clock): sky, schedules, economy.
function Staff.hour(): number return shownHour() end
-- RecruitingService (interview hire): the new employee walks in through reception (StaffEvents first-day
-- flow) once StaffAssignment has built the rig - from `from`, or, with `hold`, hidden until
-- Staff.handoverArrival hands over the visitor's last spot (the speed gates).
function Staff.expectArrival(office: Instance,seed: number,from: CFrame?,hold: boolean?)
 Events.expect(office,math.floor(math.abs(seed))%2147483647,from,hold)
end
function Staff.handoverArrival(office: Instance,seed: number,from: CFrame?)
 Events.handover(office,math.floor(math.abs(seed))%2147483647,from)
end
-- Admin diagnostics: one plain row per employee.
function Staff.inspect(office: Model): {any}
 for _,c in caches do if c.office==office then
  local out={}
  for _,e in c.all do
   table.insert(out,{name=e.name,index=e.index,role=e.role,state=e.state,task=if e.task then e.task.id else nil,station=if e.station then e.station.id else nil,
    home=e.home,lod=e.lod,navIssue=e.model:GetAttribute("NavigationIssue"),navStage=Nav.stage(e),liftTicketState=Nav.ticketState(e),
    away=e.away,night=e.night==true,apprentice=e.apprentice~=nil,event=if e.event then e.event.kind else nil,onDuty=e.onDuty})
  end
  return out
 end end
 return {}
end
return Staff
