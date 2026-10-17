--!strict
-- Staff assignment for a built office: one rig per hired employee with a home desk, plus the twelve
-- operations staff at their OperationsStation posts (SPEC §10). Called by HeadquartersDesign.staff
-- at the end of every build and whenever the hired team changes (PlotService compares StaffKey).
-- Desks: pass 1 gives every employee a desk whose PreferredRole is their role (lowest floor first);
-- pass 2 seats the rest at any desk their clearance allows ("any" desks first, lowest floor first).
-- Identities: generated from (index, owner), or from session.data.empire.staffProfiles (see profile()).
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local EmpireConfig=require(ReplicatedStorage.Shared.Config.EmpireConfig)
local EmployeeConfig=require(ReplicatedStorage.Shared.Config.EmployeeConfig)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Rig=require(script.Parent.EmployeeRigDesign)
local Assignment={}
local warned: {[string]:boolean}={}
local FALLBACK=Vector3.new(0,3,-14) -- staff atrium, used only when no desk is left
local function key(id: any): string return tostring(id) end
local function fresh(office: Model,name: string): Folder
 local previous=office:FindFirstChild(name);if previous then previous:Destroy() end
 local folder=Instance.new("Folder");folder.Name=name;folder.Parent=office;return folder
end
-- Persistent identity hook: session.data.empire.staffProfiles[roleId][i] = {n=name, s=seed, k=skill}
-- gives the i-th employee of that role its name, appearance seed and Skill attribute. Invalid fields
-- fall back to the generated identity; StaffKey still only reflects the hired counts.
local function profile(raw: any): Rig.Profile?
 if typeof(raw)~="table" then return nil end
 local n=raw.n;local s=raw.s;local k=raw.k
 local out: Rig.Profile={
  n=if typeof(n)=="string" and string.match(n,"%S") then string.sub(n,1,40) else nil,
  s=if typeof(s)=="number" and s==s and math.abs(s)<1e15 then s else nil,
  k=if typeof(k)=="number" and k==k then math.clamp(math.floor(k+.5),1,5) else nil,
 }
 return if out.n or out.s or out.k then out else nil
end
local function standing(m: Model): CFrame?
 local seat=m:GetAttribute("SeatPosition")
 if typeof(seat)=="CFrame" then return seat*CFrame.new(0,1.6,0) end
 local p=m:GetAttribute("InteractionPosition");if typeof(p)~="Vector3" then return nil end
 local face=m:GetAttribute("FacingPosition")
 if typeof(face)=="Vector3" then
  local level=Vector3.new(face.X,p.Y,face.Z)
  if (level-p).Magnitude>.1 then return CFrame.lookAt(p,level) end
 end
 return CFrame.new(p)
end
function Assignment.assign(office: Model,cf: CFrame,session: any)
 local tier=session.data.empire.office;local owner=session.userId
 local employees=fresh(office,"Employees")
 local operations=fresh(office,"OperationsEmployees")
 -- One descendants pass: Computer desks and operations posts.
 local desks: {Model}={};local posts: {[number]:Model}={}
 for _,m in office:GetDescendants() do
  if m:IsA("Model") and m:GetAttribute("WorkstationId")~=nil then
   local kind=m:GetAttribute("WorkstationType")
   if kind=="Computer" then table.insert(desks,m)
   elseif kind=="Service" then
    local i=m:GetAttribute("OpsIndex")
    if typeof(i)=="number" and not posts[i] then posts[i]=m end
   end
  end
 end
 table.sort(desks,function(a,b)return key(a:GetAttribute("WorkstationId"))<key(b:GetAttribute("WorkstationId")) end)
 -- Clearance per (desk, role) is static for this office: compute once.
 local clearance: {[Model]:{[string]:boolean}}={}
 local function allowed(w: Model,role: string): boolean
  local byRole=clearance[w];if not byRole then byRole={};clearance[w]=byRole end
  local ok=byRole[role]
  if ok==nil then
   local p=w:GetAttribute("InteractionPosition");local r=w:GetAttribute("Role");local access=w:GetAttribute("RoomAccess")
   ok=typeof(p)=="Vector3" and (r==nil or r=="any" or r==role) and Plan.roleAllows(role,if typeof(access)=="string" then access else nil) and Plan.employeeAllowed(role,tier,cf:PointToObjectSpace(p))
   byRole[role]=ok
  end
  return ok==true
 end
 local function floor(w: Model): number local f=w:GetAttribute("Floor");return if typeof(f)=="number" then f else 0 end
 local profiles=session.data.empire.staffProfiles
 local people: {{index:number,role:string,profile:Rig.Profile?}}={};local staffKey=""
 for _,role in EmpireConfig.ROLES do
  local count=session.data.empire.employees[role.id] or 0
  staffKey..=role.id..tostring(count)
  local list=if typeof(profiles)=="table" then profiles[role.id] else nil
  for i=1,count do table.insert(people,{index=#people+1,role=role.id,profile=profile(if typeof(list)=="table" then list[i] else nil)}) end
 end
 local taken: {[Model]:boolean}={};local home: {[number]:Model}={}
 local function pick(person: {index:number,role:string,profile:Rig.Profile?},preferredOnly: boolean)
  local best: Model?=nil;local score=-math.huge
  for _,w in desks do
   if taken[w] then continue end
   local preferred=w:GetAttribute("PreferredRole")
   if preferredOnly and preferred~=person.role then continue end
   if not allowed(w,person.role) then continue end
   local value=(if preferredOnly or preferred==nil or preferred=="any" then 500 else 0)-floor(w)*5
   if value>score then best=w;score=value end
  end
  if best then taken[best]=true;home[person.index]=best end
 end
 for _,person in people do pick(person,true) end
 for _,person in people do if not home[person.index] then pick(person,false) end end
 for _,person in people do
  local best=home[person.index]
  local work: CFrame=(if best then standing(best) else nil) or cf*CFrame.new(FALLBACK+Vector3.new((person.index%3-1)*3,0,0))
  local employee=Rig.build(employees,owner,person.index,person.role,work,person.profile)
  employee:SetAttribute("HomeWorkstation",if best then best:GetAttribute("WorkstationId") else "")
  employee:SetAttribute("WorkCFrame",work);employee:SetAttribute("CampusCFrame",cf)
  employee:SetAttribute("StaffFloor",if best then Plan.levelY(floor(best)) else 0)
  local localPos=cf:PointToObjectSpace(work.Position);employee:SetAttribute("StaffX",localPos.X);employee:SetAttribute("StaffZ",localPos.Z)
 end
 -- Operations staff 301..312 at their posts; a missing post skips that person.
 local missing={}
 for i,_ in EmployeeConfig.OPERATIONS_JOBS do
  local post=posts[i];local work=if post then standing(post) else nil
  if not post or not work then table.insert(missing,i);continue end
  local e=Rig.build(operations,owner,300+i,"support",work)
  e:SetAttribute("HomeWorkstation",post:GetAttribute("WorkstationId"));e:SetAttribute("WorkCFrame",work);e:SetAttribute("CampusCFrame",cf)
  e:SetAttribute("StaffFloor",Plan.levelY(floor(post)))
  local localPos=cf:PointToObjectSpace(work.Position);e:SetAttribute("StaffX",localPos.X);e:SetAttribute("StaffZ",localPos.Z)
 end
 if #missing>0 then
  local id=tostring(tier)..":"..table.concat(missing,",")
  if not warned[id] then warned[id]=true;warn(`[Staff] Missing OperationsStation posts (OpsIndex {table.concat(missing,", ")}) in tier {tier}; those operations staff are not placed.`) end
 end
 office:SetAttribute("StaffKey",staffKey);office:SetAttribute("StaffCount",#people)
end
return Assignment
