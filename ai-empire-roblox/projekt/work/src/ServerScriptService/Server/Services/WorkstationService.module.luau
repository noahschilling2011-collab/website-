--!strict
-- Workstation and activity registry per office (Models with WorkstationId, see SPEC §5/§10).
-- Built by ONE descendants scan and cached until reset (staff reassignment) or a new office.
-- Doors are not scanned here: navigation asks DoorService. One NPC per station; a seated player
-- (Seat.Occupant) blocks a chair for everyone, a player's workout (PlayerUntil) blocks a machine.
-- Props (design/PROPFX_CONTRACT.md): PropId -> root; NPCs drive them with one FxUntil write per use
-- (useProp). Station attributes JobPose / JobItem / UseProp / StandCFrame are applied by perform and
-- undone by release (rig attributes Pose / Holding are written only when they change).
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Config=require(ReplicatedStorage.Shared.Config.EmployeeConfig)
local Sound=require(script.Parent.CampusSoundService)
local Doors=require(script.Parent.DoorService)
local Workstations={}
local registries: {[Instance]:any}=setmetatable({},{__mode="k"}) :: any
local MACHINES={KitchenCoffeeMachine=true,PantryCoffee=true}
local MACHINE_RANGE=10
local function key(id: any): string return tostring(id) end
-- A reset (staff rebuild after hire/fire) keeps the old registry until the next scan, which moves
-- reservations of records that survive the rebuild (visitors, the assistant) onto the new entries.
-- Employees release their stations before the rebuild (StaffService.destroy), so theirs are gone.
local previous: { [Model]: any } = setmetatable({} :: any, { __mode = "k" })
function Workstations.scan(office: Model): any
 local existing=registries[office];if existing then return existing end
 local registry={all={},byId={},byKind={},meetings={},nodes={},machines={},kitchenMachine=nil::BasePart?,fridge=nil::Model?,props={}::{[string]:Instance},queue={},mops={}}
 for _,m in office:GetDescendants() do
  local propId=m:GetAttribute("PropId")
  if typeof(propId)=="string" and not registry.props[propId] then registry.props[propId]=m end
  if m:IsA("Model") then
   local id=m:GetAttribute("WorkstationId")
   if id~=nil then
    local position=m:GetAttribute("InteractionPosition")
    if typeof(position)~="Vector3" then position=m:GetPivot().Position end
    local seat=m:FindFirstChildWhichIsA("Seat",true)
    local w={model=m,id=id,kind=m:GetAttribute("WorkstationType") or "Unknown",department=m:GetAttribute("Department"),role=m:GetAttribute("Role"),
     floor=m:GetAttribute("Floor") or 0,access=m:GetAttribute("RoomAccess"),room=m:GetAttribute("HomeRoom"),meetingRoom=m:GetAttribute("MeetingRoom"),
     group=m:GetAttribute("ConversationGroup"),position=position,seat=seat,allow={},machine=nil,
     index=m:GetAttribute("QueueIndex") or m:GetAttribute("MopIndex")}
    registry.byId[id]=w;table.insert(registry.all,w)
   elseif m.Name=="Door_G_FRIDGE" then registry.fridge=m end
  elseif m:IsA("BasePart") then
   if MACHINES[m.Name] then table.insert(registry.machines,m);if m.Name=="KitchenCoffeeMachine" then registry.kitchenMachine=m end
   elseif m:GetAttribute("NavigationNode") then table.insert(registry.nodes,m) end
  end
 end
 table.sort(registry.all,function(a,b)return key(a.id)<key(b.id) end)
 for _,w in registry.all do
  local list=registry.byKind[w.kind];if not list then list={};registry.byKind[w.kind]=list end;table.insert(list,w)
  if w.kind=="Meeting" then
   local room=w.meetingRoom or w.room or "Meeting"
   local group=registry.meetings[room];if not group then group={id=room,level=w.floor,seats={}};registry.meetings[room]=group end
   table.insert(group.seats,w)
  elseif w.kind=="Queue" then table.insert(registry.queue,w)
  elseif w.kind=="Mop" then table.insert(registry.mops,w) end
 end
 local function byIndex(a: any,b: any): boolean return (tonumber(a.index) or 0)<(tonumber(b.index) or 0) end
 table.sort(registry.queue,byIndex);table.sort(registry.mops,byIndex)
 local old=previous[office];previous[office]=nil
 if old then
  for id,ow in old.byId do
   local r=ow.reserved;local nw=registry.byId[id]
   if r and nw and nw.model==ow.model and (not r.model or r.model.Parent) then
    nw.reserved=r;if r.station==ow then r.station=nw end
   end
  end
 end
 registries[office]=registry;return registry
end
function Workstations.reset(office: Model) previous[office]=registries[office] or previous[office];registries[office]=nil end
-- Current level of an employee record (building-local height → Plan level).
function Workstations.levelOf(e: any): number
 local y=e.cf:PointToObjectSpace(e.root.Position).Y
 return Plan.levelAt(e.tier,y) or (if y<0 then -1 else 0)
end
function Workstations.allowed(w: any,e: any): boolean
 if not w.model.Parent then return false end
 local cached=w.allow[e.role]
 if cached==nil then
  -- Static per office: role clearance for the room class and the plan zone at the standing point.
  cached=Plan.roleAllows(e.role,w.access) and (w.role==nil or w.role=="any" or w.role==e.role) and Plan.employeeAllowed(e.role,e.tier,e.cf:PointToObjectSpace(w.position))
  w.allow[e.role]=cached
 end
 return cached
end
function Workstations.available(w: any,e: any): boolean
 if not (Workstations.allowed(w,e) and (not w.reserved or w.reserved==e) and (not w.seat or not w.seat.Occupant or w.seat.Occupant==e.humanoid)) then return false end
 local player=w.model:GetAttribute("PlayerUntil") -- a player's workout session on this machine
 return not (typeof(player)=="number" and player>workspace:GetServerTimeNow())
end
-- Rig attributes for the client (EmployeeController): written only when they change.
function Workstations.setPose(e: any,pose: string?)
 if e.pose==pose then return end
 e.pose=pose;if e.model.Parent then e.model:SetAttribute("Pose",pose) end
end
function Workstations.setItem(e: any,item: string?)
 if e.item==item then return end
 e.item=item;if e.model.Parent then e.model:SetAttribute("Holding",item) end
end
-- One state write on a prop root: works for `seconds` (<= 0 stops it). Returns the root or nil.
function Workstations.useProp(office: Model,id: any,seconds: number): Instance?
 if typeof(id)~="string" then return nil end
 local root=Workstations.scan(office).props[id]
 if not root or not root.Parent then return nil end
 root:SetAttribute("FxUntil",if seconds>0 then workspace:GetServerTimeNow()+seconds else 0)
 return root
end
function Workstations.reserve(w: any,e: any): boolean
 if not Workstations.available(w,e) then return false end
 if e.station and e.station~=w then Workstations.release(e) end
 w.reserved=e;w.model:SetAttribute("ReservedBy",e.index);e.station=w;return true
end
-- Frees the station, the seat weld, the anchor and a finished cup, and undoes what perform applied
-- from the station (pose, item, prop in use, a snap onto a machine). Safe to call repeatedly.
function Workstations.release(e: any)
 local w=e.station
 if w and w.reserved==e then
  w.reserved=nil;w.model:SetAttribute("ReservedBy",nil);w.model:SetAttribute("OccupiedBy",nil);w.model:SetAttribute("EmployeeName",nil);w.model:SetAttribute("Software",nil);w.model:SetAttribute("LoginUntil",nil)
 end
 if e.usingProp then
  -- stop the prop only if nobody (a player) restarted it meanwhile
  local root=Workstations.scan(e.office).props[e.usingProp]
  if root and root:GetAttribute("FxUntil")==e.usingPropUntil then root:SetAttribute("FxUntil",0) end
  e.usingProp=nil;e.usingPropUntil=nil
 end
 if e.stationPose then e.stationPose=nil;Workstations.setPose(e,nil) end
 if e.stationItem then e.stationItem=nil;Workstations.setItem(e,nil) end
 if e.humanoid and e.humanoid.Parent then e.humanoid.Sit=false end
 if e.snapped and e.root and e.root.Parent then
  -- step back off the machine onto the floor point the employee walked to
  local back=e.snapped;e.snapped=nil
  e.root.CFrame=CFrame.new(back)*(e.root.CFrame-e.root.CFrame.Position)
 end
 if e.root and e.root.Parent then e.root.Anchored=false end
 local cup=e.model:FindFirstChild("EmployeeCup");if cup and (not e.carryCupUntil or workspace:GetServerTimeNow()>=e.carryCupUntil) then cup:Destroy();e.model:SetAttribute("HoldingCup",false) end
 e.station=nil
end
-- Best free station for a task. Coffee-style tasks (nearest=true) take the closest point, counting
-- each level of difference as 80 studs so the pantry on the employee's own floor wins.
function Workstations.choose(e: any,taskDef: any): any
 local list=Workstations.scan(e.office).byKind[taskDef.type];if not list then return nil end
 local here=e.root.Position;local level=Workstations.levelOf(e)
 local best=nil;local score=-math.huge
 for _,w in list do
  if taskDef.room and w.meetingRoom~=taskDef.room then continue end
  if taskDef.access and w.access~=taskDef.access then continue end
  if taskDef.type=="Service" and e.home~=nil and key(e.home)~="" and key(w.id)~=key(e.home) then continue end
  if not Workstations.available(w,e) then continue end
  local flat=Vector3.new(w.position.X-here.X,0,w.position.Z-here.Z).Magnitude
  local levels=math.abs(w.floor-level)
  local value=if taskDef.nearest then -(flat+levels*80)
   else (if Config.departmentMatch(taskDef,w.department) then 120 else 0)+(if e.home~=nil and key(w.id)==key(e.home) then 45 else 0)-flat*.15-levels*12
  if value>score then best=w;score=value end
 end
 return best
end
-- Nearest coffee machine part within MACHINE_RANGE of a station (cached per station).
function Workstations.machineFor(office: Model,w: any): BasePart?
 if w.machine==nil then
  local best: BasePart?=nil;local distance=MACHINE_RANGE
  for _,m in Workstations.scan(office).machines do
   local d=(m.Position-w.position).Magnitude;if m.Parent and d<=distance then best=m;distance=d end
  end
  w.machine=best or false
 end
 return if w.machine then w.machine else nil
end
-- opts.stand: work standing in front of a seated station (IT fixing a desk) instead of sitting down.
function Workstations.perform(e: any,time: number,opts: {stand: boolean?}?): boolean
 local w=e.station;if not w or w.reserved~=e or not Workstations.available(w,e) then return false end
 if w.kind=="Coffee" then
  local machine=Workstations.machineFor(e.office,w)
  if machine then
   Sound.play(machine,"coffee");e.brewMachine=machine;e.brewUntil=time+4
   machine:SetAttribute("FxUntil",workspace:GetServerTimeNow()+4) -- PropFx: steam + brew light for 4 s (client)
  end
 elseif w.kind=="Fridge" then
  local door=Workstations.scan(e.office).fridge;if door then Doors.requestNPC(e.model,door) end
 end
 w.model:SetAttribute("OccupiedBy",e.index);w.model:SetAttribute("EmployeeName",e.name);w.model:SetAttribute("Software",e.task.id);w.model:SetAttribute("LoginUntil",workspace:GetServerTimeNow()+1.8)
 e.model:SetAttribute("Workstation",w.id);e.model:SetAttribute("WorkstationType",w.kind);e.model:SetAttribute("Task",e.task.id)
 local pose=w.model:GetAttribute("JobPose");if typeof(pose)=="string" then e.stationPose=true;Workstations.setPose(e,pose) end
 local item=w.model:GetAttribute("JobItem");if typeof(item)=="string" then e.stationItem=true;Workstations.setItem(e,item) end
 local use=w.model:GetAttribute("UseProp")
 if typeof(use)=="string" then
  local root=Workstations.useProp(e.office,use,600)
  if root then e.usingProp=use;e.usingPropUntil=root:GetAttribute("FxUntil") end
 end
 local stand=w.model:GetAttribute("StandCFrame")
 if typeof(stand)=="CFrame" then
  -- machines you stand on (treadmill): snap onto the belt, back to the floor point on release
  e.snapped=w.position;e.humanoid:MoveTo(e.root.Position);e.humanoid.AutoRotate=false
  e.root.CFrame=stand;e.root.Anchored=true
  return true
 end
 if w.seat and not (opts and opts.stand) then
  -- Sit is the engine's real seat weld, rather than a character placed in front of a desk.
  e.humanoid.AutoRotate=false;e.root.Anchored=false;w.seat:Sit(e.humanoid)
  e.root.Anchored=true
 else
  e.humanoid:MoveTo(e.root.Position);e.humanoid.AutoRotate=false
  local target=w.model:GetAttribute("FacingPosition")
  if typeof(target)~="Vector3" then target=if w.model.PrimaryPart then w.model.PrimaryPart.Position else nil end
  if typeof(target)=="Vector3" then
   local delta=Vector3.new(target.X-e.root.Position.X,0,target.Z-e.root.Position.Z)
   if delta.Magnitude>.2 then e.root.CFrame=CFrame.lookAt(e.root.Position,e.root.Position+delta) end
  end
  e.root.Anchored=true
 end
 return true
end
-- Admin diagnostics: totals plus per-type {total, reserved, occupied}.
function Workstations.inspect(office: Model): any
 local out={total=0,reserved=0,occupied=0,playerSeated=0,byType={}}
 for _,w in Workstations.scan(office).all do
  local t=out.byType[w.kind];if not t then t={total=0,reserved=0,occupied=0};out.byType[w.kind]=t end
  local occupant=if w.seat then w.seat.Occupant else nil
  local occupied=w.model:GetAttribute("OccupiedBy")~=nil or occupant~=nil
  out.total+=1;t.total+=1
  if w.reserved then out.reserved+=1;t.reserved+=1 end
  if occupied then out.occupied+=1;t.occupied+=1 end
  if occupant and (not w.reserved or occupant~=w.reserved.humanoid) then out.playerSeated+=1 end
 end
 return out
end
return Workstations
