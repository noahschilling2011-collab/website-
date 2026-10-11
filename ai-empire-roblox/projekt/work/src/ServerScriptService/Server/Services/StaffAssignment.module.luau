--!strict
-- Staff assignment for a built office: one rig per hired employee with a home desk, plus the operations
-- staff at their OperationsStation posts (SPEC §10). Called by HeadquartersDesign.staff at the end of every
-- build and whenever the hired team changes (PlotService compares StaffKey).
-- Desks: pass 1 gives every employee a desk whose PreferredRole is their role (lowest floor first);
-- pass 2 seats the rest at any desk their clearance allows ("any" desks first, lowest floor first).
-- Identities: generated from (index, owner), or from session.data.empire.staffProfiles (see profile()).
-- Plan tier = the built office's OfficeTier attribute (tier 0 = garage stage: 5 team desks, the founder's
-- and the assistant's desks are not for staff, no operations posts). Operations posts are optional where
-- the plan has none (garage stage), where EmployeeConfig.OPTIONAL_POSTS lists them, or where they belong to
-- an annex that this tier does not build (guest house jobs without Plan.hasHotel): those are skipped
-- silently; any other missing post (incl. a guest-house post in a tier with the guest house) warns once.
-- staffops:
--  * INCREMENTAL: a rig whose identity (role, appearance seed, name) is still on the team keeps its Model
--    and its desk; only new people get a rig (built hidden: OffDuty, StaffService walks them in through
--    reception) and people who left lose theirs. Indices are renumbered in place. A hire therefore costs
--    one rig instead of rebuilding (and re-replicating) every rig of the office. StaffRev counts calls.
--  * Apprentices (empire.apprentices, CORE_SPEC 11.1) look young: no facial hair, no grey hair, a green
--    "Apprentice" lanyard and badge, a slightly smaller build (Model:ScaleTo, within the existing body-size
--    spread). dressApprentice also undoes the lanyard / badge / size at graduation (StaffService).
--  * The Training Lead (OPERATIONS_JOBS[17]) is placed only while the company has apprentices (the same rule
--    as StaffRota: an empire.apprentices entry whose seed belongs to a current profile), at a free desk in the
--    People & Company (HR) room, else another free operations desk, else at the reception.
--  * The stage-5 night rota (OPERATIONS_JOBS[18] / [19], EmployeeConfig.NIGHT_ROTA): a second guard and a
--    second IT person at the station of post 3 / post 6, only in the stage-5 building (plan tier 4).
-- integrate (staffops request 10, lead decision): a post is staffed only from the office stage at which the
-- economy pays it (CORE_SPEC 5.5, EmployeeConfig.POST_FROM_STAGE): stage 2 has 8 post holders, stage 3 12 + 2,
-- stage 4 14 + 2, stage 5 16 + 2 (night rota) - the same numbers as CompanyOps.STAGES[].ops.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local EmpireConfig=require(ReplicatedStorage.Shared.Config.EmpireConfig)
local EmployeeConfig=require(ReplicatedStorage.Shared.Config.EmployeeConfig)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local CampusMath=require(ReplicatedStorage.Shared.CampusMath)
local Ops=require(ReplicatedStorage.Shared.CompanyOps)
local Rig=require(script.Parent.EmployeeRigDesign)
local Assignment={}
local warned: {[string]:boolean}={}
-- Operations jobs whose posts belong to an annex building (built only in some plan tiers).
local ANNEX_JOBS: {[string]:string}={["Hotel Reception"]="hotel",Housekeeping="hotel"}
local rgb=Color3.fromRGB
Assignment.APPRENTICE_GREEN=rgb(118,196,64)
Assignment.APPRENTICE_BADGE=rgb(214,240,190)
local BADGE=rgb(227,230,215)
local function hex(c: Color3): number
 return math.floor(c.R*255+.5)*65536+math.floor(c.G*255+.5)*256+math.floor(c.B*255+.5)
end
-- the grey hair tones of EmployeeRigDesign (GREY) for "older" looks
local GREY_HAIR: {[number]:boolean}={[hex(rgb(124,122,120))]=true,[hex(rgb(160,158,154))]=true,[hex(rgb(206,204,198))]=true}
local YOUNG_HAIR={rgb(24,21,20),rgb(44,34,28),rgb(70,52,38),rgb(101,70,45),rgb(156,96,56),rgb(196,160,104)}
local HAIR_PARTS={Hair=true,HairBack=true,LongHair=true,Bob=true,Braid=true,CurlsBack=true,Curl=true,SidePart=true,HairBun=true,Ponytail=true}
local FACIAL={Beard=true,ShortBeard=true,Moustache=true}
-- Training Lead uniform tones (same build-up as EmployeeRigDesign.UNIFORMS: shirt / trousers)
local TRAINER={shirt=rgb(46,126,112),trousers=rgb(44,50,66),lanyard=rgb(118,196,64)}
type Person={index:number,role:string,profile:Rig.Profile?,seed:number,name:string,rig:Model?}
local function key(id: any): string return tostring(id) end
local function folder(office: Model,name: string): (Folder,boolean)
 local existing=office:FindFirstChild(name)
 if existing and existing:IsA("Folder") then return existing,true end
 if existing then existing:Destroy() end
 local f=Instance.new("Folder");f.Name=name;f.Parent=office;return f,false
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
-- The identity Rig.build gives (index, owner, profile): appearance seed + name decide the whole look.
local function identity(index: number,owner: number,p: Rig.Profile?): (number,string)
 local seed=if p and p.s then math.floor(math.abs(p.s))%2147483647 else EmployeeConfig.seed(index,owner)
 local name=if p and p.n then p.n else CampusMath.staffName(index,owner)
 return seed,name
end
local function identKey(role: any,seed: any,name: any): string
 return tostring(role).."|"..tostring(seed).."|"..tostring(name)
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
local function set(m: Instance,name: string,value: any)
 if m:GetAttribute(name)~=value then m:SetAttribute(name,value) end
end
local function badgeLabel(model: Model): TextLabel?
 local head=model:FindFirstChild("Head")
 local badge=if head then head:FindFirstChild("EmployeeBadge") else nil
 local label=if badge then badge:FindFirstChildWhichIsA("TextLabel") else nil
 return label
end
-- Young look + "Apprentice" lanyard/badge (on), or back to the regular badge at graduation (off).
function Assignment.dressApprentice(model: Model,on: boolean,_empire: any?)
 local role=model:GetAttribute("RoleId")
 local title=EmployeeConfig.ROLES[tostring(role)] or "Employee"
 local name=tostring(model:GetAttribute("EmployeeName") or "")
 local label=badgeLabel(model)
 if on then
  if model:GetAttribute("Apprentice")==true then return end
  model:SetAttribute("Apprentice",true)
  local seed=tonumber(model:GetAttribute("PersonalitySeed")) or 0
  local young=YOUNG_HAIR[seed%#YOUNG_HAIR+1]
  for _,p in model:GetDescendants() do
   if p:IsA("BasePart") then
    if FACIAL[p.Name] then p:Destroy()
    elseif p.Name=="Lanyard" then
     if model:GetAttribute("LanyardColor")==nil then model:SetAttribute("LanyardColor",p.Color) end
     p.Color=Assignment.APPRENTICE_GREEN
    elseif p.Name=="IDBadge" then p.Color=Assignment.APPRENTICE_BADGE
    elseif HAIR_PARTS[p.Name] and GREY_HAIR[hex(p.Color)] then p.Color=young end
   elseif p:IsA("Frame") and p.Name=="Brow" and GREY_HAIR[hex(p.BackgroundColor3)] then p.BackgroundColor3=young end
  end
  if label then
   label.Text=name.."\nApprentice · "..title
   -- "Apprentice · Growth Manager" is wider than the regular 150 px badge: a wider badge, and the text
   -- shrinks below 12 px only if a long name still does not fit
   local badge=label.Parent
   if badge and badge:IsA("BillboardGui") then
    if model:GetAttribute("BadgeWidth")==nil then model:SetAttribute("BadgeWidth",badge.Size.X.Offset) end
    badge.Size=UDim2.fromOffset(EmployeeConfig.APPRENTICE.badgeWidth,badge.Size.Y.Offset)
   end
   label.TextScaled=true
   if not label:FindFirstChild("ApprenticeFit") then
    local fit=Instance.new("UITextSizeConstraint");fit.Name="ApprenticeFit";fit.MaxTextSize=12;fit.MinTextSize=8;fit.Parent=label
   end
  end
  local scale=EmployeeConfig.APPRENTICE.scale
  if math.abs(model:GetScale()-1)<1e-3 and scale<1 then model:ScaleTo(scale) end
 else
  if model:GetAttribute("Apprentice")~=true then return end
  model:SetAttribute("Apprentice",nil)
  local lanyard=model:GetAttribute("LanyardColor")
  for _,p in model:GetDescendants() do
   if p:IsA("BasePart") then
    if p.Name=="Lanyard" and typeof(lanyard)=="Color3" then p.Color=lanyard
    elseif p.Name=="IDBadge" then p.Color=BADGE end
   end
  end
  model:SetAttribute("LanyardColor",nil)
  if label then
   label.Text=name.."\n"..title
   label.TextScaled=false
   local fit=label:FindFirstChild("ApprenticeFit");if fit then fit:Destroy() end
   local badge=label.Parent;local width=model:GetAttribute("BadgeWidth")
   if badge and badge:IsA("BillboardGui") and typeof(width)=="number" then badge.Size=UDim2.fromOffset(width,badge.Size.Y.Offset) end
  end
  model:SetAttribute("BadgeWidth",nil)
  if math.abs(model:GetScale()-1)>1e-3 then model:ScaleTo(1) end
 end
end
-- Training Lead: uniform tones on the shirt (torso, sleeves) and trousers, the programme's green lanyard.
local function dressTrainer(model: Model)
 for _,p in model:GetDescendants() do
  if p:IsA("BasePart") then
   if p.Name=="Torso" or p.Name=="Left Arm" or p.Name=="Right Arm" then p.Color=TRAINER.shirt
   elseif (p.Name=="Left Leg" or p.Name=="Right Leg") and model:FindFirstChild("Skirt")==nil then p.Color=TRAINER.trousers
   elseif p.Name=="Lanyard" then p.Color=TRAINER.lanyard end
  end
 end
end
-- Active apprentices of a save: the seeds of the CURRENT profiles (employees[role] of them, the rule of
-- StaffRota / Dialogue.facts) that CompanyOps.apprentice calls an apprentice on today's company day. An
-- empire.apprentices entry without a profile (a stale save) places no Training Lead.
local function apprenticeSeeds(e: any): {[number]:boolean}
 local out: {[number]:boolean}={}
 if typeof(e.apprentices)~="table" or next(e.apprentices)==nil then return out end
 local day=Ops.day(e)
 local profiles=if typeof(e.staffProfiles)=="table" then e.staffProfiles else {}
 for _,role in EmpireConfig.ROLES do
  local n=math.max(0,math.floor(tonumber(e.employees and e.employees[role.id]) or 0))
  local list=profiles[role.id]
  for i=1,n do
   local p=if typeof(list)=="table" then list[i] else nil
   local s=if typeof(p)=="table" then p.s else nil
   local seed=if typeof(s)=="number" and s==s then math.floor(math.abs(s))%2147483647 else i
   if Ops.apprentice(e,seed,day) then out[seed]=true end
  end
 end
 return out
end
Assignment.apprenticeSeeds=apprenticeSeeds
-- Name of an operations person without a post of their own (Training Lead, night rota): the index-based
-- CampusMath name can repeat a hired person's name, so the next free name of the same presentation list is
-- taken (the look stays EmployeeConfig.seed(index, owner); the name list keeps the presentation).
local function uniqueOpsName(index: number,owner: number,used: {[string]:boolean}): string
 local name=CampusMath.staffName(index,owner)
 local j=0
 while used[name] and j<64 do
  j+=1
  name=CampusMath.nameForSeed(EmployeeConfig.seed(index,owner)+j*7919,EmployeeConfig.isFeminine(index,owner))
 end
 used[name]=true
 return name
end
Assignment.uniqueOpsName=uniqueOpsName
function Assignment.assign(office: Model,cf: CFrame,session: any)
 local tierAttr=office:GetAttribute("OfficeTier")
 local tier: number=if typeof(tierAttr)=="number" then tierAttr else Plan.tierForOffice(session.data.empire.office)
 local owner=session.userId
 local fallback=Plan.staffFallback(tier) -- used only when no desk is left (HQ: staff atrium)
 local employees,hadEmployees=folder(office,"Employees")
 local operations,_=folder(office,"OperationsEmployees")
 -- rigs added to an office that already has staff appear hidden: StaffService walks them in (first day)
 local live=hadEmployees
 -- One descendants pass: Computer desks and operations posts.
 local desks: {Model}={};local posts: {[number]:Model}={};local byId: {[string]:Model}={}
 for _,m in office:GetDescendants() do
  if m:IsA("Model") and m:GetAttribute("WorkstationId")~=nil then
   local kind=m:GetAttribute("WorkstationType")
   if kind=="Computer" then table.insert(desks,m);byId[key(m:GetAttribute("WorkstationId"))]=m
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
 local people: {Person}={};local staffKey=""
 for _,role in EmpireConfig.ROLES do
  local count=session.data.empire.employees[role.id] or 0
  staffKey..=role.id..tostring(count)
  local list=if typeof(profiles)=="table" then profiles[role.id] else nil
  for i=1,count do
   local index=#people+1
   local p=profile(if typeof(list)=="table" then list[i] else nil)
   local seed,name=identity(index,owner,p)
   table.insert(people,{index=index,role=role.id,profile=p,seed=seed,name=name})
  end
 end
 -- keep every rig whose person is still on the team (same role, seed and name = the same look)
 local existing: {[string]:{Model}}={}
 for _,m in employees:GetChildren() do
  if m:IsA("Model") then
   local k=identKey(m:GetAttribute("RoleId"),m:GetAttribute("PersonalitySeed"),m:GetAttribute("EmployeeName"))
   local list=existing[k];if not list then list={};existing[k]=list end
   table.insert(list,m)
  end
 end
 for _,person in people do
  local list=existing[identKey(person.role,person.seed,person.name)]
  if list and #list>0 then person.rig=table.remove(list,1) end
 end
 for _,list in existing do for _,m in list do m:Destroy() end end
 local taken: {[Model]:boolean}={};local home: {[number]:Model}={}
 -- kept people keep their desk while it is still theirs to use
 for _,person in people do
  local m=person.rig
  if m then
   local w=byId[key(m:GetAttribute("HomeWorkstation"))]
   if w and not taken[w] and allowed(w,person.role) then taken[w]=true;home[person.index]=w end
  end
 end
 local function pick(person: Person,preferredOnly: boolean)
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
 for _,person in people do if not home[person.index] then pick(person,true) end end
 for _,person in people do if not home[person.index] then pick(person,false) end end
 local apprentices=apprenticeSeeds(session.data.empire)
 for _,person in people do
  local best=home[person.index]
  local work: CFrame=(if best then standing(best) else nil) or cf*CFrame.new(fallback+Vector3.new((person.index%3-1)*3,0,0))
  local kept=person.rig
  local employee: Model
  if kept then
   employee=kept
   -- renumber in place (the rig index follows the team list: TalkService profileOf, Employee_<i>)
   if employee:GetAttribute("StaffIndex")~=person.index then
    employee:SetAttribute("StaffIndex",person.index);employee.Name="Employee_"..person.index
    local head=employee:FindFirstChild("Head");local prompt=if head then head:FindFirstChild("EmployeeTalk") else nil
    if prompt then prompt:SetAttribute("EmployeeTalk",person.index) end
   end
   if person.profile and person.profile.k then set(employee,"Skill",person.profile.k) end
  else
   employee=Rig.build(employees,owner,person.index,person.role,work,person.profile)
   if live then employee:SetAttribute("OffDuty",true) end
  end
  local e=employee
  set(e,"HomeWorkstation",if best then best:GetAttribute("WorkstationId") else "")
  set(e,"WorkCFrame",work);set(e,"CampusCFrame",cf)
  set(e,"StaffFloor",if best then Plan.levelY(floor(best)) else 0)
  local localPos=cf:PointToObjectSpace(work.Position);set(e,"StaffX",localPos.X);set(e,"StaffZ",localPos.Z)
  local young=apprentices[person.seed]==true and person.role~="support"
  if young~=(e:GetAttribute("Apprentice")==true) then Assignment.dressApprentice(e,young,session.data.empire) end
 end
 -- Operations staff 301.. at their posts; a missing post skips that person. A post is expected (else one
 -- warning) in the HQ tiers unless EmployeeConfig.OPTIONAL_POSTS lists it; the posts of an annex job are
 -- expected exactly when the annex is built (guest house: Plan.hasHotel); the garage stage has none.
 local missing={}
 local optional: {[number]:boolean}=(EmployeeConfig :: any).OPTIONAL_POSTS or {}
 local keepOps: {[number]:Model}={}
 for _,m in operations:GetChildren() do
  local i=m:GetAttribute("StaffIndex")
  if m:IsA("Model") and typeof(i)=="number" and not keepOps[i] then keepOps[i]=m else m:Destroy() end
 end
 local leadPost=(EmployeeConfig :: any).TRAINING_LEAD_POST or 17
 local postFrom: {[number]:number}=(EmployeeConfig :: any).POST_FROM_STAGE or {}
 local nightRota: {[number]:number}=(EmployeeConfig :: any).NIGHT_ROTA or {}
 -- names in use: the hired team and every post holder (their generated names)
 local usedNames: {[string]:boolean}={}
 for _,person in people do usedNames[person.name]=true end
 for i in EmployeeConfig.OPERATIONS_JOBS do if i~=leadPost and not nightRota[i] then usedNames[CampusMath.staffName(300+i,owner)]=true end end
 for i,job in EmployeeConfig.OPERATIONS_JOBS do
  local existingRig=keepOps[300+i];keepOps[300+i]=nil
  local nightOf=nightRota[i]
  if nightOf then
   -- stage-5 night rota (CORE_SPEC 5.5): a second person who uses post `nightOf`'s station at night
   local post=posts[nightOf];local work=if post then standing(post) else nil
   if tier<4 or not post or not work then
    if existingRig then existingRig:Destroy() end
    continue
   end
   local r: Model
   if existingRig and existingRig:GetAttribute("HomeWorkstation")==post:GetAttribute("WorkstationId") then r=existingRig
   else
    if existingRig then existingRig:Destroy() end
    r=Rig.build(operations,owner,300+i,"support",work,{n=uniqueOpsName(300+i,owner,usedNames)})
    if live then r:SetAttribute("OffDuty",true) end
   end
   usedNames[tostring(r:GetAttribute("EmployeeName"))]=true
   set(r,"HomeWorkstation",post:GetAttribute("WorkstationId"));set(r,"WorkCFrame",work);set(r,"CampusCFrame",cf)
   set(r,"StaffFloor",Plan.levelY(floor(post)));set(r,"NightRotaOf",nightOf)
   local lp=cf:PointToObjectSpace(work.Position);set(r,"StaffX",lp.X);set(r,"StaffZ",lp.Z)
   continue
  end
  if i==leadPost then
   -- the Training Lead: only while there are apprentices, at a free HR desk (else reception)
   if next(apprentices)==nil or tier<1 then
    if existingRig then existingRig:Destroy() end
    continue
   end
   local desk: Model?=nil
   local existingDesk=if existingRig then byId[key(existingRig:GetAttribute("HomeWorkstation"))] else nil
   if existingDesk and not taken[existingDesk] then desk=existingDesk end
   if not desk then
    local bestScore=-math.huge
    for _,w in desks do
     if taken[w] or not allowed(w,"support") then continue end
     local room=Plan.room(tier,tostring(w:GetAttribute("HomeRoom")))
     local score=(if room and room.kind=="hr" then 1000 elseif w:GetAttribute("Department")=="operations" then 500 else 0)-floor(w)*5
     if score>bestScore then desk=w;bestScore=score end
    end
   end
   if desk then taken[desk]=true end
   local work=(if desk then standing(desk) else nil) or cf*CFrame.new(Plan.visitorRoute(tier).portal+Vector3.new(6,0,8))
   local lead=existingRig or Rig.build(operations,owner,300+i,"support",work,{n=uniqueOpsName(300+i,owner,usedNames)})
   usedNames[tostring(lead:GetAttribute("EmployeeName"))]=true
   if not existingRig then
    dressTrainer(lead)
    if live then lead:SetAttribute("OffDuty",true) end
   end
   set(lead,"HomeWorkstation",if desk then desk:GetAttribute("WorkstationId") else "")
   set(lead,"WorkCFrame",work);set(lead,"CampusCFrame",cf)
   set(lead,"StaffFloor",if desk then Plan.levelY(floor(desk)) else 0)
   local lp=cf:PointToObjectSpace(work.Position);set(lead,"StaffX",lp.X);set(lead,"StaffZ",lp.Z)
   continue
  end
  -- a post the economy does not pay at this stage stays empty (CORE_SPEC 5.5, EmployeeConfig.POST_FROM_STAGE)
  if Plan.officeForTier(tier)<(postFrom[i] or 2) then
   if existingRig then existingRig:Destroy() end
   continue
  end
  local post=posts[i];local work=if post then standing(post) else nil
  if not post or not work then
   if existingRig then existingRig:Destroy() end
   local annex=ANNEX_JOBS[job]
   local expected=tier>=1 and (if annex=="hotel" then Plan.hasHotel(tier) else not optional[i])
   if expected then table.insert(missing,i) end
   continue
  end
  local r: Model
  if existingRig and existingRig:GetAttribute("HomeWorkstation")==post:GetAttribute("WorkstationId") then r=existingRig
  else
   if existingRig then existingRig:Destroy() end
   r=Rig.build(operations,owner,300+i,"support",work)
   if live then r:SetAttribute("OffDuty",true) end
  end
  set(r,"HomeWorkstation",post:GetAttribute("WorkstationId"));set(r,"WorkCFrame",work);set(r,"CampusCFrame",cf)
  set(r,"StaffFloor",Plan.levelY(floor(post)))
  local localPos=cf:PointToObjectSpace(work.Position);set(r,"StaffX",localPos.X);set(r,"StaffZ",localPos.Z)
 end
 for _,m in keepOps do m:Destroy() end
 if #missing>0 then
  local id=tostring(tier)..":"..table.concat(missing,",")
  if not warned[id] then warned[id]=true;warn(`[Staff] Missing OperationsStation posts (OpsIndex {table.concat(missing,", ")}) in tier {tier}; those operations staff are not placed.`) end
 end
 office:SetAttribute("StaffKey",staffKey);office:SetAttribute("StaffCount",#people)
 office:SetAttribute("StaffRev",(tonumber(office:GetAttribute("StaffRev")) or 0)+1)
end
return Assignment
