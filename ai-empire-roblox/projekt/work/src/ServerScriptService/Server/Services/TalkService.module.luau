--!strict
-- TalkService: talk to anyone in the company — employees and operations staff; visitors (other players)
-- may talk to the front-of-house jobs (reception, hotel desk, security, barista, café host, chef).
-- The words come from the pure, AUTHORED ReplicatedStorage.Shared.Dialogue (no language model); this
-- service gathers the real state, enforces the rules and keeps one conversation per NPC.
--
-- Entry: ProximityPrompt "EmployeeTalk" (attribute EmployeeTalk = staff index; only this service handles
-- it) → Notify TALK_OPEN, or TalkAction {action="open", npc=Model} → {ok, talk}. Rules checked on the
-- server: the owner talks with everyone in his company; anyone else only with a front-of-house job whose
-- prompt is Public (EmployeeRigDesign); player within OPEN_DISTANCE studs (KEEP_DISTANCE while talking);
-- the NPC is not off duty / inactive; one conversation per NPC and per player; prompt cooldown, say
-- interval and the TalkAction rate limit.
-- talk payload: {id, npc, name, job, kind, initials, seed, viewer, room, level, greeting, options}.
-- TalkAction {action="say", id, option} answers one OFFERED option → {ok, text, options, close?};
-- {action="close", id} ends it. Idle conversations (IDLE s), vanished NPCs and players who leave end on
-- the server with Notify TALK_CLOSE {id, text?}.
-- The NPC: rig attributes TalkingTo (userId) and TalkFace (Vector3 of the player, written on open and
-- per answer) while talking — the client hides the prompt for everyone else and poses may use them.
-- When StaffService provides hold(model, facePosition) / release(model) the employee's state machine
-- pauses (task + station reservation kept, a walk resumes afterwards); without it a standing, anchored
-- NPC is only turned to face the player and turned back afterwards (seated NPCs keep their pose).
-- Numbers: Dialogue.facts over the owner's session, plus counts measured here: visitors in the building
-- now, distinct visitors today (5 s sampler over the plots, per campus day), conversations per NPC today,
-- open PropFx faults (FxState "broken"), computer desks, desks per plan room and café seats (one scan per
-- office) with the desks in use right now (OccupiedBy), the plan room the NPC stands in (kind,
-- department, access, camera) and its home desk room (HomeWorkstation → HomeRoom), the lunch phase of
-- the live staff record (StaffService.recordOf), guest cards (live.campus.passes), cars, and lunches /
-- hotel guests when the life/hotel packages publish the office attributes LunchesServed / HotelGuests /
-- HotelRooms. Nothing is saved; no session.live fields; no per-frame work (a 1 s sweep ends conversations
-- whose player walked away or that ran too long).
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Prompts=game:GetService("ProximityPromptService")
local Collection=game:GetService("CollectionService")
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local CampusConfig=require(ReplicatedStorage.Shared.Config.CampusConfig)
local EmpireConfig=require(ReplicatedStorage.Shared.Config.EmpireConfig)
local EmployeeConfig=require(ReplicatedStorage.Shared.Config.EmployeeConfig)
local Dialogue=require(ReplicatedStorage.Shared.Dialogue)
local Remote=require(script.Parent.Parent.Lib.Remote)
local Session=require(script.Parent.SessionService)
local Plot=require(script.Parent.PlotService)
local Staff=require(script.Parent.StaffService)
local Talk={}
Talk.OPEN_DISTANCE=12 -- studs between the player's root and the NPC to start talking
Talk.KEEP_DISTANCE=16 -- walking further away during the conversation ends it
Talk.IDLE=60 -- seconds without an answer before the NPC goes back to work
Talk.MAX_SECONDS=600 -- hard cap per conversation
Talk.PROMPT_COOLDOWN=.8 -- seconds between prompt triggers per player
Talk.SAY_INTERVAL=.3 -- seconds between answers per conversation
Talk.SAMPLE_EVERY=5 -- seconds between "visitors today" samples
Talk.SWEEP_EVERY=1 -- seconds between walk-away / time-limit checks of open conversations
Talk.clock=function(): number return os.clock() end -- seam: tests drive time
type Info={model: Model,root: BasePart,office: Instance,owner: number,prompt: ProximityPrompt,index: number,roleId: string,job: string,kind: string,name: string}
type Conv={id: string,npc: Model,player: Player,userId: number,owner: number,viewer: string,kind: string,name: string,farewell: string,
 asked: {[string]:boolean},offered: {[string]:boolean},token: number,started: number,last: number,faced: CFrame?,held: boolean,watch: RBXScriptConnection?,closed: boolean}
local conversations: {[Model]:Conv}={}
local byPlayer: {[Player]:Conv}={}
local serial=0
local promptAt: {[Player]:number}=setmetatable({},{__mode="k"}) :: any
local talks: {[Model]:{day: number,n: number}}=setmetatable({},{__mode="k"}) :: any
local seen: {[Instance]:{day: number,ids: {[number]:boolean},n: number}}=setmetatable({},{__mode="k"}) :: any
type Statics={desks: number,dining: number,computers: {Instance},byId: {[string]:Instance},byRoom: {[string]:{Instance}}}
local statics: {[Instance]:Statics}=setmetatable({},{__mode="k"}) :: any
local buildings: {[number]:any}={}
local NOTICE: {[string]:string}={
 NPC_BUSY="{name} is talking to someone else right now.",
 OFF_DUTY="{name} is off duty. Try again during working hours.",
 TOO_FAR="Step a little closer to {name}.",
 UNAVAILABLE="{name} can't talk right now.",
}
local MENU_KINDS={barista=true,chef=true,kitchen=true,host=true}
-- IT faults exist when a job step breaks/fixes desk screens (EmployeeConfig.JOBS, StaffJobs "fault").
local FAULT_SYSTEM=(function(): boolean
 local jobs=(EmployeeConfig :: any).JOBS
 if typeof(jobs)~="table" then return false end
 for _,steps in jobs do
  if typeof(steps)=="table" then for _,step in steps do if typeof(step)=="table" and step.fault then return true end end end
 end
 return false
end)()

-- Helpers -------------------------------------------------------------------------------------------
local function firstName(name: string): string return string.match(name,"^%s*(%S+)") or name end
local function campusDay(): number return math.floor(Staff.now()/Dialogue.DAY_SECONDS) end
local function rootOf(player: Player): BasePart?
 local character=player.Character;if not character then return nil end
 local root=character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
 return if root and root:IsA("BasePart") then root else nil
end
local function ownerSession(userId: number): any
 for _,s in Session.all() do if s.userId==userId and not s.closed then return s end end
 return nil
end
-- A staff rig with a talk prompt inside an office (visitors/assistant rigs have their prompt renamed).
local function info(model: Instance): Info?
 if not model:IsA("Model") then return nil end
 local root=model.PrimaryPart;local head=model:FindFirstChild("Head")
 local prompt=if head then head:FindFirstChild("EmployeeTalk") else nil
 if not root or not prompt or not prompt:IsA("ProximityPrompt") then return nil end
 local index=prompt:GetAttribute("EmployeeTalk");local owner=model:GetAttribute("OwnerUserId")
 if typeof(index)~="number" or typeof(owner)~="number" then return nil end
 local office=model:FindFirstAncestor("Office");if not office then return nil end
 local officeOwner=office:GetAttribute("OwnerUserId");if officeOwner~=nil and officeOwner~=owner then return nil end
 local roleId=model:GetAttribute("RoleId");local job=model:GetAttribute("Role");local name=model:GetAttribute("EmployeeName")
 local r=if typeof(roleId)=="string" then roleId else "support"
 local j=if typeof(job)=="string" then job else "Campus Operations"
 return {model=model,root=root,office=office,owner=owner,prompt=prompt,index=index,roleId=r,job=j,kind=Dialogue.kind(r,j),name=if typeof(name)=="string" then name else "Employee"}
end
local function tierOf(office: Instance,s: any): number
 local t=office:GetAttribute("OfficeTier")
 if typeof(t)=="number" then return t end
 return if s then tonumber(s.data.empire.office) or 1 else 1
end
local function campusFrame(model: Model,office: Instance): CFrame?
 local cf=model:GetAttribute("CampusCFrame")
 if typeof(cf)=="CFrame" then return cf end
 for _,p in Plot.all() do if p.office==office then return p.cframe end end
 return nil
end
local function inside(tier: number,cf: CFrame,player: Player): boolean
 local root=rootOf(player)
 return root~=nil and Plan.inside(tier,cf:PointToObjectSpace(root.Position))
end

-- Measured counts -------------------------------------------------------------------------------------
local function building(tier: number): any
 local b=buildings[tier];if b then return b end
 local rooms,cameras,restrooms=0,0,0;local public={}
 for _,r in Plan.rooms(tier) do
  if not r.hidden then
   rooms+=1
   if r.camera then cameras+=1 end
   if r.kind=="wc" or r.kind=="restrooms" or r.kind=="showers" then restrooms+=1 end
   if r.access=="public" then table.insert(public,r.name) end
  end
 end
 b={floors=Plan.floors(tier),rooms=rooms,cameras=cameras,restrooms=restrooms,stops=#Plan.liftStops(tier),publicRooms=public}
 buildings[tier]=b;return b
end
-- Workstations of a built office, indexed once: computer desks (also per plan room via HomeRoom),
-- café seats and every station by WorkstationId (home desks). Static until the office is rebuilt.
local function officeCounts(office: Instance): Statics
 local cached=statics[office];if cached then return cached end
 local c: Statics={desks=0,dining=0,computers={},byId={},byRoom={}}
 for _,m in office:GetDescendants() do
  if m:IsA("Model") then
   local kind=m:GetAttribute("WorkstationType");local id=m:GetAttribute("WorkstationId")
   if typeof(id)=="string" then c.byId[id]=m end
   if kind=="Computer" then
    c.desks+=1;table.insert(c.computers,m)
    local room=m:GetAttribute("HomeRoom")
    if typeof(room)=="string" then local list=c.byRoom[room] or {};c.byRoom[room]=list;table.insert(list,m) end
   elseif kind=="Dining" then c.dining+=1 end
  end
 end
 statics[office]=c;return c
end
-- Desks of a list that someone works at right now (WorkstationService sets OccupiedBy).
local function busyOf(list: {Instance}?): number?
 if not list then return nil end
 local n=0
 for _,m in list do if m:GetAttribute("OccupiedBy")~=nil then n+=1 end end
 return n
end
-- Open faults of the PropFx contract (screens with FxState "broken"); nil when there is no fault system
-- to report on (no job step breaks screens and no PropFx prop exists in this office).
local function faults(office: Instance,tier: number,cf: CFrame?): any
 local present=FAULT_SYSTEM;local n=0;local rooms: {string}={};local named: {[string]:boolean}={}
 for _,inst in Collection:GetTagged("PropFx") do
  if inst:IsDescendantOf(office) then
   present=true
   if inst:GetAttribute("FxState")=="broken" then
    n+=1
    local pos=if inst:IsA("BasePart") then inst.Position elseif inst:IsA("Model") then inst:GetPivot().Position else nil
    local r=if pos and cf then Plan.roomAt(tier,cf:PointToObjectSpace(pos)) else nil
    if r and not named[r.name] then named[r.name]=true;table.insert(rooms,r.name) end
   end
  end
 end
 return if present then {count=n,rooms=rooms} else nil
end
local function visitorsNow(owner: number,tier: number,cf: CFrame?): number
 if not cf then return 0 end
 local n=0
 for _,s in Session.all() do if not s.closed and s.userId~=owner and inside(tier,cf,s.player) then n+=1 end end
 return n
end
local function markSeen(office: Instance,userId: number)
 local day=campusDay();local old=seen[office]
 local rec=if old and old.day==day then old else {day=day,ids={},n=0}
 seen[office]=rec
 if not rec.ids[userId] then rec.ids[userId]=true;rec.n+=1 end
end
local function visitorsToday(office: Instance): number
 local rec=seen[office]
 return if rec and rec.day==campusDay() then rec.n else 0
end
-- Distinct other players inside each headquarters during the current campus day.
local function sample()
 for _,p in Plot.all() do
  local office=p.office;local owner=p.owner
  if office and owner and p.cframe then
   local tier=tierOf(office,nil)
   for _,s in Session.all() do
    if not s.closed and s.userId~=owner.UserId and inside(tier,p.cframe,s.player) then markSeen(office,s.userId) end
   end
  end
 end
end
local function cars(s: any): any
 local c=s.data.empire.campus
 if typeof(c)~="table" or typeof(c.cars)~="table" then return nil end
 local owned={}
 for _,def in CampusConfig.CARS do if c.cars[def.id] then table.insert(owned,def.name) end end
 local selected=CampusConfig.find(CampusConfig.CARS,c.selectedCar)
 return {owned=owned,ready=if selected and c.cars[selected.id] then selected.name else nil}
end
local function menu(): {any}
 local out={}
 for _,item in CampusConfig.SNACKS do table.insert(out,{name=item.name,price=item.price,seconds=item.seconds}) end
 return out
end

-- Subject + context --------------------------------------------------------------------------------
-- The i-th person of a role is rig index (Σ earlier roles) + i (StaffAssignment); the name confirms it.
local function profileOf(e: any,i: Info,roleId: string): any
 local profiles=e.staffProfiles;local list=if typeof(profiles)=="table" then profiles[roleId] else nil
 if typeof(list)~="table" then return nil end
 local before=0
 for _,role in EmpireConfig.ROLES do if role.id==roleId then break end;before+=tonumber(e.employees[role.id]) or 0 end
 local p=list[i.index-before]
 if typeof(p)=="table" and (p.n==nil or p.n==i.name) then return p end
 for _,q in list do if typeof(q)=="table" and q.n==i.name then return q end end
 return nil
end
-- Home desk of a hired employee: room, department and how many of that room's desks are in use.
local function deskOf(i: Info,st: Statics,tier: number): any
 if i.roleId=="support" then return nil end
 local id=i.model:GetAttribute("HomeWorkstation")
 local w=if typeof(id)=="string" and id~="" then st.byId[id] else nil
 local roomId=if w then w:GetAttribute("HomeRoom") else nil
 local r=if typeof(roomId)=="string" then Plan.room(tier,roomId) else nil
 if not w or not r or r.hidden then return nil end
 local list=st.byRoom[r.id];local dept=w:GetAttribute("Department")
 return {room=r.name,level=Plan.levelLabel(tier,r.level),dept=if typeof(dept)=="string" then dept else r.dept,desks=if list then #list else nil,busy=busyOf(list)}
end
local function subject(i: Info,s: any,tier: number,cf: CFrame?,st: Statics): any
 local m=i.model
 local seed=m:GetAttribute("PersonalitySeed")
 local sub: any={name=i.name,roleId=i.roleId,job=i.job,seed=if typeof(seed)=="number" then seed else EmployeeConfig.seed(i.index,i.owner),index=i.index}
 local activity=m:GetAttribute("Activity");if typeof(activity)=="string" then sub.activity=activity end
 local task=m:GetAttribute("Task");if typeof(task)=="string" then sub.task=task end
 local skill=m:GetAttribute("Skill");if typeof(skill)=="number" then sub.skill=skill end
 local pose=m:GetAttribute("Pose");if typeof(pose)=="string" then sub.pose=pose end
 if cf then
  local lp=cf:PointToObjectSpace(i.root.Position);local r=Plan.roomAt(tier,lp)
  if r then
   sub.room=r.name;sub.level=Plan.levelLabel(tier,r.level);sub.levelNumber=r.level
   if not r.hidden then
    -- "What's this room for?": plan kind, department, door class, camera, desks in use in this room
    sub.roomKind=r.kind;sub.roomDept=r.dept;sub.roomAccess=r.access;sub.roomCamera=r.camera==true
    local list=st.byRoom[r.id]
    if list then sub.roomDesks=#list;sub.roomBusy=busyOf(list) end
   end
  else local level=Plan.levelAt(tier,lp.Y);if level then sub.levelNumber=level;sub.level=Plan.levelLabel(tier,level) end end
 end
 local role=EmpireConfig.find(EmpireConfig.ROLES,i.roleId)
 if role and s then
  local p=profileOf(s.data.empire,i,role.id)
  local w=if p and typeof(p.w)=="number" then p.w else 1
  sub.wage=role.wage*w
  if p and typeof(p.k)=="number" then sub.skill=p.k end
 end
 local a,b=m:GetAttribute("ShiftStart"),m:GetAttribute("ShiftEnd")
 if typeof(a)=="number" and typeof(b)=="number" then sub.shiftStart=a;sub.shiftEnd=b end
 sub.desk=deskOf(i,st,tier)
 -- lunch phase (queue / seat / tray return) of the live record, read only
 local api: any=Staff
 if typeof(api.recordOf)=="function" then
  local ok,rec=pcall(api.recordOf,m)
  if ok and typeof(rec)=="table" and typeof(rec.lunch)=="table" and typeof(rec.lunch.phase)=="string" then sub.lunch=rec.lunch.phase end
 end
 return sub
end
local BUSY_KINDS={reception=true,facilities=true,mailroom=true,ops=true} -- tour / building answers cite desks in use
local function context(viewer: string,player: Player,i: Info,s: any,tier: number,cf: CFrame?,sub: any,st: Statics): any
 local data=s.data
 local c: any={viewer=viewer,viewerName=player.DisplayName,day=campusDay(),hour=EmployeeConfig.hour(Staff.now()),tier=tier,
  facts=Dialogue.facts(data,s.live),company=if data.company then data.company.name else s.player.DisplayName.."'s company",ownerName=s.player.DisplayName}
 local ids=Dialogue.placeIds(viewer,i.kind)
 if #ids>0 then c.places=Dialogue.places(tier,ids,sub.levelNumber) end
 c.building=building(tier)
 c.visitorsNow=visitorsNow(i.owner,tier,cf);c.visitorsToday=visitorsToday(i.office)
 local t=talks[i.model];c.talksToday=if t and t.day==c.day then t.n else 0
 c.desks=st.desks
 if viewer=="owner" and BUSY_KINDS[i.kind] then c.desksBusy=busyOf(st.computers) end
 if MENU_KINDS[i.kind] or sub.roomKind=="cafe" then c.dining=st.dining end
 if MENU_KINDS[i.kind] then c.menu=menu() end
 if i.kind=="it" then c.faults=faults(i.office,tier,cf) end
 if i.kind=="fleet" then c.cars=cars(s) end
 local campus=s.live and s.live.campus
 if typeof(campus)=="table" and typeof(campus.passes)=="table" then c.passes=#campus.passes end
 local lunches=i.office:GetAttribute("LunchesServed");if typeof(lunches)=="number" then c.lunches=lunches end
 local guests=i.office:GetAttribute("HotelGuests")
 if typeof(guests)=="number" then local rooms=i.office:GetAttribute("HotelRooms");c.hotel={guests=guests,rooms=if typeof(rooms)=="number" then rooms else nil} end
 return c
end
local function build(viewer: string,player: Player,i: Info,s: any): (Dialogue.Lines,any)
 local tier=tierOf(i.office,s);local cf=campusFrame(i.model,i.office);local st=officeCounts(i.office)
 local sub=subject(i,s,tier,cf,st)
 return Dialogue.lines(sub,context(viewer,player,i,s,tier,cf,sub,st)),sub
end

-- NPC hold / release ----------------------------------------------------------------------------------
local function face(root: BasePart,target: Vector3)
 local p=root.Position;local d=Vector3.new(target.X-p.X,0,target.Z-p.Z)
 if d.Magnitude>.2 then root.CFrame=CFrame.lookAt(p,p+d) end
end
local function hold(conv: Conv,i: Info,at: Vector3)
 local m=i.model
 m:SetAttribute("TalkingTo",conv.userId);m:SetAttribute("TalkFace",at)
 local api: any=Staff
 if typeof(api.hold)=="function" then
  local ok,res=pcall(api.hold,m,at)
  conv.held=ok and res==true
 end
 local h=m:FindFirstChildOfClass("Humanoid")
 if i.root.Anchored and not (h and h.SeatPart) then conv.faced=i.root.CFrame;face(i.root,at) end
end
local function release(conv: Conv)
 local m=conv.npc
 if m.Parent then m:SetAttribute("TalkingTo",nil);m:SetAttribute("TalkFace",nil) end
 local root=m.PrimaryPart;local faced=conv.faced;conv.faced=nil
 -- turn back only if nobody moved the NPC meanwhile (a new task places it itself)
 if faced and root and root.Parent and root.Anchored and (root.Position-faced.Position).Magnitude<.3 then root.CFrame=faced end
 if conv.held then
  conv.held=false
  local api: any=Staff
  if typeof(api.release)=="function" then pcall(api.release,m) end
 end
end
local function finish(conv: Conv,text: string?,notify: boolean)
 if conv.closed then return end
 conv.closed=true
 if conversations[conv.npc]==conv then conversations[conv.npc]=nil end
 if byPlayer[conv.player]==conv then byPlayer[conv.player]=nil end
 if conv.watch then conv.watch:Disconnect();conv.watch=nil end
 release(conv)
 if notify then Remote.fire(conv.player,"Notify","TALK_CLOSE",{id=conv.id,text=text}) end
end
local function arm(conv: Conv)
 conv.token+=1
 local token=conv.token
 task.delay(Talk.IDLE,function()
  if not conv.closed and conv.token==token then finish(conv,conv.farewell,true) end
 end)
end
local function offer(conv: Conv,options: {Dialogue.Option})
 local set: {[string]:boolean}={}
 for _,o in options do set[o.id]=true end
 conv.offered=set
end

-- Public API ----------------------------------------------------------------------------------------
local function refuse(player: Player,i: Info?,code: string,viaPrompt: boolean?): any
 if viaPrompt and i and NOTICE[code] then
  Remote.fire(player,"Notify","TALK_NOTICE",{text=(string.gsub(NOTICE[code],"{name}",firstName(i.name)))})
 end
 return {ok=false,err=code}
end
function Talk.open(player: Player,model: Instance,viaPrompt: boolean?): any
 local i=info(model);if not i then return {ok=false,err="NPC_GONE"} end
 local own=player.UserId==i.owner
 if not own and not (Dialogue.isPublicKind(i.kind) and i.prompt:GetAttribute("Public")==true) then return refuse(player,i,"NOT_PUBLIC",viaPrompt) end
 local mine=Session.get(player);if not mine or mine.closed then return {ok=false,err="LOADING"} end
 local s=ownerSession(i.owner);if not s or not s.data then return refuse(player,i,"UNAVAILABLE",viaPrompt) end
 local root=rootOf(player)
 if not root or (root.Position-i.root.Position).Magnitude>Talk.OPEN_DISTANCE then return refuse(player,i,"TOO_FAR",viaPrompt) end
 local m=i.model;local activity=m:GetAttribute("Activity")
 if m:GetAttribute("OffDuty")==true or activity=="OFF_DUTY" then return refuse(player,i,"OFF_DUTY",viaPrompt) end
 local h=m:FindFirstChildOfClass("Humanoid")
 if activity=="INACTIVE" or (h and h.Health<=0) then return refuse(player,i,"UNAVAILABLE",viaPrompt) end
 local busy=conversations[m]
 if busy and not busy.closed and busy.player~=player then return refuse(player,i,"NPC_BUSY",viaPrompt) end
 local previous=byPlayer[player];if previous then finish(previous,nil,false) end
 if busy and not busy.closed then finish(busy,nil,false) end
 local viewer=if own then "owner" else "visitor"
 local lines,sub=build(viewer,player,i,s)
 serial+=1
 local t=Talk.clock()
 local conv: Conv={id="talk"..serial,npc=m,player=player,userId=player.UserId,owner=i.owner,viewer=viewer,kind=i.kind,name=i.name,farewell=lines.farewell,
  asked={},offered={},token=0,started=t,last=t,faced=nil,held=false,watch=nil,closed=false}
 conversations[m]=conv;byPlayer[player]=conv
 offer(conv,lines.options)
 local day=campusDay();local old=talks[m]
 local count=if old and old.day==day then old else {day=day,n=0}
 talks[m]=count;count.n+=1
 if not own then markSeen(i.office,player.UserId) end
 hold(conv,i,root.Position)
 conv.watch=m.AncestryChanged:Connect(function()
  if not m:IsDescendantOf(workspace) then finish(conv,nil,true) end
 end)
 arm(conv)
 return {ok=true,talk={id=conv.id,npc=m,name=i.name,job=i.job,kind=i.kind,initials=Dialogue.initials(i.name),seed=sub.seed,viewer=viewer,
  room=sub.room,level=sub.level,greeting=lines.greeting,options=lines.options}}
end
function Talk.say(player: Player,id: any,option: any): any
 local conv=byPlayer[player]
 if not conv or conv.closed or (id~=nil and id~=conv.id) then return {ok=false,err="NO_TALK"} end
 if typeof(option)~="string" or #option>64 or not string.match(option,"^[%w_:%-]+$") or not conv.offered[option] then return {ok=false,err="BAD_INPUT"} end
 local t=Talk.clock()
 if t-conv.last<Talk.SAY_INTERVAL then return {ok=false,err="RATE_LIMIT"} end
 local i=info(conv.npc)
 if not i then finish(conv,nil,false);return {ok=false,err="NPC_GONE"} end
 local root=rootOf(player)
 if not root or (root.Position-i.root.Position).Magnitude>Talk.KEEP_DISTANCE then finish(conv,nil,false);return {ok=false,err="TOO_FAR"} end
 local s=ownerSession(i.owner)
 if not s or t-conv.started>Talk.MAX_SECONDS then finish(conv,nil,false);return {ok=false,err="UNAVAILABLE"} end
 conv.last=t
 local lines=build(conv.viewer,player,i,s) -- fresh numbers for every answer
 local answer,options=Dialogue.step(lines,conv.asked,option)
 if not answer then return {ok=false,err="BAD_INPUT"} end
 if answer.close or #options==0 then
  finish(conv,nil,false)
  return {ok=true,text=answer.text,options={},close=true}
 end
 i.model:SetAttribute("TalkFace",root.Position)
 -- a job step may have turned the NPC back to its desk meanwhile: face the player again (same spot only)
 local faced=conv.faced
 if faced and i.root.Anchored and (i.root.Position-faced.Position).Magnitude<.3 then face(i.root,root.Position) end
 offer(conv,options);arm(conv)
 return {ok=true,text=answer.text,options=options}
end
function Talk.close(player: Player,id: any): any
 local conv=byPlayer[player]
 if conv and (id==nil or id==conv.id) then finish(conv,nil,false) end
 return {ok=true}
end
-- Ends conversations whose player walked away (> KEEP_DISTANCE from the NPC), whose player or NPC is
-- gone, or that ran longer than MAX_SECONDS; the NPC says goodbye (TALK_CLOSE with the farewell).
local function sweep()
 local ended: {Conv}={}
 local t=Talk.clock()
 for npc,conv in conversations do
  local root=rootOf(conv.player);local npcRoot=npc.PrimaryPart
  if not root or not npcRoot or (root.Position-npcRoot.Position).Magnitude>Talk.KEEP_DISTANCE or t-conv.started>Talk.MAX_SECONDS then table.insert(ended,conv) end
 end
 for _,conv in ended do finish(conv,conv.farewell,true) end
end
-- Diagnostics/tests: the conversation an NPC is in (nil when free).
function Talk.conversation(model: Model): any
 local conv=conversations[model]
 return if conv and not conv.closed then {id=conv.id,userId=conv.userId,viewer=conv.viewer,kind=conv.kind} else nil
end
local function act(s: any,p: any): any
 local player: Player=s.player
 local action=p.action
 if action=="open" then
  if typeof(p.npc)~="Instance" then return {ok=false,err="BAD_INPUT"} end
  return Talk.open(player,p.npc,false)
 elseif action=="say" then
  if p.id~=nil and typeof(p.id)~="string" then return {ok=false,err="BAD_INPUT"} end
  return Talk.say(player,p.id,p.option)
 elseif action=="close" then
  return Talk.close(player,if typeof(p.id)=="string" then p.id else nil)
 end
 return {ok=false,err="BAD_INPUT"}
end
local function onPrompt(prompt: ProximityPrompt,player: Player)
 if prompt.Name~="EmployeeTalk" or typeof(prompt:GetAttribute("EmployeeTalk"))~="number" then return end
 local t=Talk.clock()
 if (promptAt[player] or 0)>t then return end
 promptAt[player]=t+Talk.PROMPT_COOLDOWN
 local head=prompt.Parent;local model=if head then head.Parent else nil
 if not model then return end
 local res=Talk.open(player,model,true)
 if res.ok then Remote.fire(player,"Notify","TALK_OPEN",res.talk) end
end
Talk._act=act;Talk._prompt=onPrompt;Talk._sample=sample;Talk._sweep=sweep -- tests
function Talk.init()
 Prompts.PromptTriggered:Connect(onPrompt)
 Remote.bind("TalkAction",{burst=6,perSecond=3},act)
 Players.PlayerRemoving:Connect(function(player: Player)
  local conv=byPlayer[player];if conv then finish(conv,nil,false) end
  promptAt[player]=nil
 end)
 Session.onClosing(function(s: any)
  local list={}
  for _,conv in conversations do if conv.player==s.player or conv.owner==s.userId then table.insert(list,conv) end end
  for _,conv in list do finish(conv,nil,conv.player~=s.player) end
 end)
 task.spawn(function()
  while true do
   task.wait(Talk.SAMPLE_EVERY)
   local ok,err=pcall(sample :: () -> any)
   if not ok then warn("[Talk] visitor sample: "..tostring(err)) end
  end
 end)
 task.spawn(function()
  while true do
   task.wait(Talk.SWEEP_EVERY)
   if next(conversations)~=nil then
    local ok,err=pcall(sweep :: () -> any)
    if not ok then warn("[Talk] sweep: "..tostring(err)) end
   end
  end
 end)
end
return Talk
