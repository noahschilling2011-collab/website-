--!strict
-- Bounded asynchronous path jobs. Ordinary travel is Humanoid movement, never PivotTo.
-- Contract: every Nav.go ends in exactly ONE callback(ok) unless Nav.cancel aborts it first (cancel
-- never calls back: whoever cancels owns the employee state). A destination outside the employee's
-- clearance calls back(false) at once; every other ending goes through finish(), which clears e.nav
-- and bumps the token BEFORE calling back. Async path results and engine events carry the token and
-- are dropped once it changed.
-- Levels: Plan.levelAt. Different levels → stairs or lift by personality and level distance (lift for
-- 3+ levels, usually for 2 and for B1). Lift: walk to the lobby wait point, LiftService.npcCall, then
-- follow the ticket (walk to target while waiting/board/exit, stand still while riding, continue on
-- done; failed or a wait > LIFT_WAIT → stairs). Stairs: one path through the smooth stair ramps; if
-- that fails, a path to Plan.stairEntry(level) first.
-- Doors: DoorService.doorsNear(root, DOOR_SCAN); a closed door whose doorway the next part of the route
-- crosses (Layout door line test; Sensor test for doors outside the plan) is requested
-- (DoorService.requestNPC, within its 8-stud range) and the employee holds outside its Sensor, ~2.5
-- studs before it, until isPassable (DOOR_WAIT timeout → recompute). A door class the role may not
-- enter fails the route. Speed gates are ordinary doors here (one lane = one door).
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Pathfinding=game:GetService("PathfindingService")
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Layout=require(ReplicatedStorage.Shared.BuildingLayout)
local Config=require(ReplicatedStorage.Shared.Config.EmployeeConfig)
local Doors=require(script.Parent.DoorService)
local Lift=require(script.Parent.LiftService)
local Nav={}
local queue={};local activeJobs=0
local REACH=2.2 -- horizontal distance at which a waypoint counts as reached
local DOOR_GAP=2.5 -- wait this far before a closed door's Sensor
local DOOR_SCAN=12 -- doorsNear radius: swing-door Sensors reach ~7 studs from the doorway, so a 7-stud scan would find them too late
local REQUEST_RANGE=7.6 -- DoorService.requestNPC accepts employees within 8 studs of the doorway centre
local LIFT_TIMEOUT=180 -- absolute safety net for a whole ride
local AGENT={AgentRadius=1.2,AgentHeight=5.6,AgentCanJump=false,AgentCanClimb=false,WaypointSpacing=5} -- radius fits 3-stud speed-gate lanes
local costCache: {[string]:{[string]:number}}={}
local doorDefs: {[number]:{[string]:any}}={}
-- PathfindingModifier labels are access classes; forbidden classes cost math.huge (impassable).
local function costs(role: string): {[string]:number}
 local cached=costCache[role];if cached then return cached end
 local c: {[string]:number}={}
 for _,class in Plan.CLASSES do c[class]=if Plan.roleAllows(role,class) then 1 else math.huge end
 costCache[role]=c;return c
end
local function doorDef(tier: number,id: any): any
 local map=doorDefs[tier]
 if not map then
  local built: {[string]:any}={};for _,d in Layout.doors(tier) do built[d.id]=d end
  doorDefs[tier]=built;map=built
 end
 return if typeof(id)=="string" then map[id] else nil
end
local function allowed(e: any,p: Vector3): boolean
 return Plan.employeeAllowed(e.role,e.tier,e.cf:PointToObjectSpace(p))
end
local function levelAt(e: any,p: Vector3): number
 local y=e.cf:PointToObjectSpace(p).Y;return Plan.levelAt(e.tier,y) or (if y<0 then -1 else 0)
end
local function flat(a: Vector3,b: Vector3): number return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
local function disconnect(e: any)
 if e.blocked then e.blocked:Disconnect();e.blocked=nil end
 if e.moveFinished then e.moveFinished:Disconnect();e.moveFinished=nil end
end
local function stand(e: any)
 if e.humanoid and e.humanoid.Parent and e.root.Parent and not e.root.Anchored then e.humanoid:MoveTo(e.root.Position) end
end
local function dropTicket(e: any,n: any)
 if n.ticket then Lift.npcCancel(n.ticket);n.ticket=nil end
 if n.liftActivity then n.liftActivity=false;e.model:SetAttribute("Activity",e.state) end
end
-- Abort without callback.
function Nav.cancel(e: any)
 local n=e.nav
 e.navToken=(e.navToken or 0)+1;e.nav=nil;e.queued=false;disconnect(e)
 if n then dropTicket(e,n) end
 stand(e)
end
-- The single place that ends a started route.
local function finish(e: any,ok: boolean)
 local n=e.nav;if not n then return end
 local cb=n.callback
 e.navToken=(e.navToken or 0)+1;e.nav=nil;e.queued=false;disconnect(e);dropTicket(e,n)
 if ok then e.model:SetAttribute("NavigationIssue",nil) else stand(e) end
 cb(ok)
end
local function enqueue(e: any,at: number)
 local n=e.nav;if not n then return end
 n.retryAt=at;n.points=nil;n.door=nil;n.phase="queued"
 if e.queued then return end
 e.queued=true;table.insert(queue,{employee=e,token=e.navToken})
end
local function fail(e: any,time: number,reason: string)
 local n=e.nav;if not n then return end
 disconnect(e);n.points=nil;n.door=nil;n.retries+=1;stand(e);e.model:SetAttribute("NavigationIssue",reason)
 if n.retries>=3 then e.model:SetAttribute("NavigationIssue","Waiting for a clear route");finish(e,false)
 else enqueue(e,time+.5*n.retries) end
end
local function chooseMode(e: any,from: number,to: number): string
 if from==to then return "walk" end
 local span=math.abs(to-from);local fondness=e.personality.stairs or .5;local basement=from<0 or to<0
 if span>=3 then return "lift" end
 if span==2 then return if fondness>.8 and not basement then "stairs" else "lift" end
 if basement then return if fondness>.85 then "stairs" else "lift" end
 return if fondness<.25 then "lift" else "stairs"
end
local function toStairs(e: any,time: number,reason: string)
 local n=e.nav;if not n then return end
 dropTicket(e,n);n.mode="stairs";n.stage="walk";n.viaStair=false;n.goal=nil
 e.model:SetAttribute("NavigationIssue",reason);stand(e);enqueue(e,time)
end
local function goal(e: any,n: any): Vector3
 if n.stage=="toLift" then return e.cf*Plan.liftWaitPoint(n.source,n.slot)
 elseif n.stage=="toStair" then return e.cf*Plan.stairEntry(n.source) end
 return n.target
end
local function callLift(e: any,time: number)
 local n=e.nav;if not n then return end
 local ticket=Lift.npcCall(e.office,e.model,n.source,n.destination)
 if not ticket then toStairs(e,time,"Lift unavailable");return end
 n.ticket=ticket;n.stage="lift";n.phase="lift";n.liftStart=time;n.liftState="waiting";n.liftActivity=true;n.goal=nil
 e.model:SetAttribute("Activity","ELEVATOR")
end
local function arrived(e: any,time: number)
 local n=e.nav;if not n then return end
 disconnect(e);n.points=nil
 if n.stage=="toLift" then callLift(e,time)
 elseif n.stage=="toStair" then n.stage="walk";enqueue(e,time)
 else finish(e,true) end
end
local function nextWaypoint(e: any,time: number)
 local n=e.nav;if not n or not n.points then return end
 while n.index<=#n.points and flat(n.points[n.index].Position,e.root.Position)<REACH and math.abs(n.points[n.index].Position.Y-e.root.Position.Y)<6 do n.index+=1 end
 if n.index>#n.points then arrived(e,time);return end
 local point=n.points[n.index]
 n.phase="moving";n.deadline=time+math.max(3,flat(point.Position,e.root.Position)/e.personality.walkSpeed+3)
 e.humanoid:MoveTo(point.Position)
end
-- A direct path failed: stairs routes retry via the stair entry, a lift lobby route takes the stairs.
local function unreachable(e: any,time: number)
 local n=e.nav;if not n then return end
 if n.stage=="walk" and n.mode=="stairs" and not n.viaStair then n.viaStair=true;n.stage="toStair";enqueue(e,time);return end
 if n.stage=="toLift" then toStairs(e,time,"Lift lobby unreachable");return end
 fail(e,time,"Path unavailable")
end
function Nav.go(e: any,target: Vector3,time: number,callback: (boolean)->())
 Nav.cancel(e)
 if not allowed(e,target) then e.model:SetAttribute("NavigationIssue","Restricted destination");callback(false);return end
 e.humanoid.EvaluateStateMachine=true;e.root.Anchored=false;e.humanoid.Sit=false;e.humanoid.AutoRotate=true;e.humanoid.WalkSpeed=e.personality.walkSpeed
 pcall(function()e.root:SetNetworkOwner(nil)end)
 local source=levelAt(e,e.root.Position);local destination=levelAt(e,target);local mode=chooseMode(e,source,destination)
 e.nav={target=target,callback=callback,retries=0,index=1,retryAt=time,source=source,destination=destination,mode=mode,
  stage=if mode=="lift" then "toLift" else "walk",slot=e.index%6+1,phase="queued",doorRequests={}}
 enqueue(e,time)
end
function Nav.pump(time: number)
 local launched=0
 for i=#queue,1,-1 do
  local entry=queue[i];local e=entry.employee
  if entry.token~=e.navToken then table.remove(queue,i)
  elseif not e.nav or not e.model.Parent then table.remove(queue,i);e.queued=false
  elseif time>=e.nav.retryAt and activeJobs<Config.MAX_PATH_JOBS and launched<Config.MAX_PATH_JOBS then
   table.remove(queue,i);e.queued=false;activeJobs+=1;launched+=1
   local n=e.nav;n.phase="computing";n.source=levelAt(e,e.root.Position)
   local token=e.navToken;local start=e.root.Position;local target=goal(e,n)
   task.spawn(function()
    local path: Path?=nil
    local ok=pcall(function()
     local params=table.clone(AGENT) :: any;params.Costs=costs(e.role)
     local p=Pathfinding:CreatePath(params);path=p;p:ComputeAsync(start,target)
    end)
    activeJobs-=1 -- always reached: the job slot can never leak
    local now=e.now or time
    if token~=e.navToken or not e.nav or not e.model.Parent then return end
    if not ok or not path or path.Status~=Enum.PathStatus.Success then unreachable(e,now);return end
    local points=path:GetWaypoints()
    if #points<1 then fail(e,now,"Empty route");return end
    for _,p in points do if not allowed(e,p.Position) then fail(e,now,"Restricted waypoint");return end end
    local m=e.nav;m.points=points;m.index=1;m.doorRequests={}
    disconnect(e)
    e.blocked=path.Blocked:Connect(function(index)
     local cur=e.nav;if token==e.navToken and cur and cur.points and cur.phase=="moving" and index>=cur.index then fail(e,e.now or now,"Path blocked") end
    end)
    e.moveFinished=e.humanoid.MoveToFinished:Connect(function(reached)
     local cur=e.nav;if token~=e.navToken or not cur or cur.phase~="moving" or not cur.points then return end
     local point=cur.points[cur.index];if not point then return end
     if flat(point.Position,e.root.Position)<=REACH+.8 then cur.index+=1;nextWaypoint(e,e.now or now)
     elseif not reached then fail(e,e.now or now,"Move timed out") end
    end)
    nextWaypoint(e,now)
   end)
  end
 end
end
-- Door geometry ----------------------------------------------------------------------------
local function sensorOf(door: Model): BasePart?
 local s=door:FindFirstChild("Sensor");return if s and s:IsA("BasePart") then s else nil
end
-- Doorway centre as DoorService measures NPC request range (the Sensor sits on the closed leaves).
local function doorCentre(door: Model): Vector3
 local s=sensorOf(door);return if s then s.Position else door:GetPivot().Position
end
local function insideBox(box: BasePart,p: Vector3,margin: number): boolean
 local l=box.CFrame:PointToObjectSpace(p);local h=box.Size/2
 return math.abs(l.X)<=h.X+margin and math.abs(l.Z)<=h.Z+margin and math.abs(l.Y)<=h.Y+4
end
-- Horizontal distance from a point to the door Sensor box (0 = inside).
local function gapAt(e: any,door: Model,def: any,p: Vector3): number
 local sensor=sensorOf(door)
 if sensor then
  local l=sensor.CFrame:PointToObjectSpace(p);local h=sensor.Size/2
  local dx=math.max(math.abs(l.X)-h.X,0);local dz=math.max(math.abs(l.Z)-h.Z,0)
  return math.sqrt(dx*dx+dz*dz)
 end
 if def then
  local q=e.cf:PointToObjectSpace(p)
  return math.max(math.abs(if def.axis=="x" then q.Z-def.z else q.X-def.x)-def.w/2,0)
 end
 return math.max(flat(door:GetPivot().Position,p)-3,0)
end
-- Does the next stretch of the route (root → next three waypoints) pass through this doorway?
local function onRoute(e: any,n: any,door: Model,def: any): boolean
 local kind=door:GetAttribute("DoorKind")
 if kind=="cubicle" or kind=="fridge" then return false end
 local pts={e.root.Position}
 for k=n.index,math.min(n.index+2,#n.points) do table.insert(pts,n.points[k].Position) end
 if def then
  local base=Plan.levelY(def.level);local half=def.w/2+.6;local centre=if def.axis=="x" then def.x else def.z
  for i=1,#pts-1 do
   local a=e.cf:PointToObjectSpace(pts[i]);local b=e.cf:PointToObjectSpace(pts[i+1])
   local da=if def.axis=="x" then a.Z-def.z else a.X-def.x
   local db=if def.axis=="x" then b.Z-def.z else b.X-def.x
   if da~=db and ((da<=0 and db>=0) or (da>=0 and db<=0)) then
    local t=da/(da-db)
    local u=if def.axis=="x" then a.X+(b.X-a.X)*t else a.Z+(b.Z-a.Z)*t
    local y=a.Y+(b.Y-a.Y)*t
    if math.abs(u-centre)<=half and y>base-3 and y<base+12 then return true end
   end
  end
  return false
 end
 local sensor=sensorOf(door);if not sensor then return false end
 for i=1,#pts-1 do for s=0,8 do if insideBox(sensor,pts[i]:Lerp(pts[i+1],s/8),.25) then return true end end end
 return false
end
-- Where to wait for a closed door: outside its Sensor, ~DOOR_GAP before it, but never beyond
-- DoorService's NPC request range (wide swing doors have Sensors ~7 studs deep on each side).
local function holdPoint(e: any,n: any,door: Model,def: any,gap: number): Vector3
 local here=e.root.Position;local centre=doorCentre(door)
 local toward=Vector3.new(centre.X-here.X,0,centre.Z-here.Z)
 if gap<=0 then
  -- Inside the Sensor: step back out, stopping at DOOR_GAP or before leaving the request range.
  local away=-toward
  if away.Magnitude<.1 then
   local back=n.points and n.points[math.max(1,n.index-1)]
   away=if back then Vector3.new(back.Position.X-here.X,0,back.Position.Z-here.Z) else Vector3.xAxis
   if away.Magnitude<.1 then away=Vector3.xAxis end
  end
  local dir=away.Unit;local s=0
  while s<10 do
   local p=here+dir*s;local g=gapAt(e,door,def,p)
   if g>=.5 and (g>=DOOR_GAP or (p-centre).Magnitude>REQUEST_RANGE-.4) then return p end
   s+=.25
  end
  return here+dir*s
 end
 if toward.Magnitude<.1 then return here end
 local dir=toward.Unit;local first: number?=nil;local inRange: number?=nil;local edge: number?=nil;local s=0
 while s<=gap+1 do
  local p=here+dir*s;local g=gapAt(e,door,def,p)
  if not first and g<=DOOR_GAP then first=s end
  if not inRange and (p-centre).Magnitude<=REQUEST_RANGE then inRange=s end
  if g<=.5 then edge=s;break end
  s+=.25
 end
 local stop=math.max(first or 0,inRange or 0)
 if edge then stop=math.min(stop,edge) end
 return here+dir*stop
end
local function request(e: any,n: any,door: Model,time: number)
 if time>=(n.doorRequests[door] or 0) and (e.root.Position-doorCentre(door)).Magnitude<=REQUEST_RANGE+.3 then
  Doors.requestNPC(e.model,door);n.doorRequests[door]=time+.75
 end
end
-- true while the employee is held by a door (or the route just failed).
local function doorTick(e: any,n: any,time: number): boolean
 if n.door then
  local door=n.door
  if not door.Parent or Doors.isPassable(door) then n.door=nil;nextWaypoint(e,time);return false end
  if time>=n.doorUntil then n.door=nil;fail(e,time,"Door did not open");return true end
  request(e,n,door,time)
  return true
 end
 for _,door in Doors.doorsNear(e.office,e.root.Position,DOOR_SCAN) do
  if Doors.isPassable(door) then continue end
  local def=doorDef(e.tier,door:GetAttribute("DoorId"))
  if not onRoute(e,n,door,def) then continue end
  local class=door:GetAttribute("AccessClass")
  if not Plan.roleAllows(e.role,if typeof(class)=="string" then class else nil) then fail(e,time,"Door access denied");return true end
  request(e,n,door,time)
  local gap=gapAt(e,door,def,e.root.Position)
  if gap<=DOOR_GAP+e.personality.walkSpeed*.3 then
   n.door=door;n.doorUntil=time+Config.DOOR_WAIT;n.phase="door"
   local p=holdPoint(e,n,door,def,gap)
   e.humanoid:MoveTo(Vector3.new(p.X,e.root.Position.Y,p.Z))
   return true
  end
 end
 return false
end
-- Lift ticket ------------------------------------------------------------------------------
local function liftTick(e: any,n: any,time: number)
 local info=Lift.npcTicket(n.ticket)
 local state=if info then info.state else "failed"
 n.liftState=state
 if state=="done" then
  n.ticket=nil;n.liftActivity=false;e.model:SetAttribute("Activity",e.state)
  n.mode="walk";n.stage="walk";n.retries=0;n.goal=nil;enqueue(e,time);return
 end
 if state=="failed" then toStairs(e,time,"Lift failed");return end
 if (state=="waiting" or state=="board") and time-n.liftStart>Config.LIFT_WAIT then toStairs(e,time,"Lift wait timeout");return end
 if time-n.liftStart>LIFT_TIMEOUT then toStairs(e,time,"Lift ride timeout");return end
 if state=="riding" then
  if n.goal then n.goal=nil;stand(e) end
  return
 end
 local target=if info then info.target else nil
 if typeof(target)=="Vector3" and (not n.goal or (n.goal-target).Magnitude>.5 or time>=n.goalAt) then
  n.goal=target;n.goalAt=time+3
  if flat(target,e.root.Position)>.8 then e.humanoid:MoveTo(target) end
 end
end
function Nav.tick(e: any,time: number)
 local n=e.nav;if not n then return end
 if n.phase=="lift" then liftTick(e,n,time);return end
 if (n.phase~="moving" and n.phase~="door") or not n.points then return end
 if doorTick(e,n,time) then return end
 if e.nav~=n or n.phase~="moving" or not n.points then return end
 if n.deadline and time>n.deadline then fail(e,time,"Stuck; recomputing");return end
 local point=n.points[n.index]
 if point and flat(point.Position,e.root.Position)<REACH and math.abs(point.Position.Y-e.root.Position.Y)<6 then n.index+=1;nextWaypoint(e,time) end
end
-- Diagnostics / LOD helpers.
function Nav.liftBusy(e: any): boolean
 local n=e.nav
 return (n~=nil and n.ticket~=nil) or Lift.riding(e.model)
end
function Nav.ticketState(e: any): string?
 local n=e.nav;return if n and n.ticket then n.liftState else nil
end
function Nav.stage(e: any): string?
 local n=e.nav;return if n then string.format("%s/%s/%s",n.mode,n.stage,n.phase) else nil
end
return Nav
