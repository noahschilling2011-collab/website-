--!strict
-- StaffRota (staffops): who of a company is on duty right now. Pure functions of the saved company data
-- (data.empire) and the visible server clock hour (CompanyOps.hour), so the building shows exactly the
-- people the economy counts (CORE_SPEC 5.3 / 11.1). StaffService only ANIMATES this; money and output stay
-- in CompanyOps (presence, output, wage) - nothing here is re-derived, it calls CompanyOps.
--   * absences: CompanyOps.presence(e, role)[i] ~= "present" (vacation / sick / unpaid leave / trip)
--   * night crew: the overflow heads beyond the day seats of a role with a night shift work 22:00-06:00
--     (the same heads CompanyOps.wage pays x1.3: the newest paid profiles of that role)
--   * apprentices: CompanyOps.apprentice (skill 1 -> 3, graduation after 9 company days)
--   * operations posts: one day shift that covers the opening hours, security + IT night rota at stage 5
-- Keys are "<role>:<i>" with i = the profile index inside the role (= rig StaffIndex - earlier roles).
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Config=require(ReplicatedStorage.Shared.Config.EmployeeConfig)
local EmpireConfig=require(ReplicatedStorage.Shared.Config.EmpireConfig)
local Ops=require(ReplicatedStorage.Shared.CompanyOps)
local Rota={}
export type Snapshot={day: number,stage: number,away: {[string]:string},night: {[string]:boolean},apprentices: {[string]:{age: number,skill: number,seed: number}},
 apprenticeCount: number,nightCrew: number,securityNight: boolean,itNight: boolean,before: {[string]:number}}

local function count(e: any,role: string): number
 return math.max(0,math.floor(tonumber(e.employees and e.employees[role]) or 0))
end
local function seedOf(p: any,i: number): number
 local s=if typeof(p)=="table" then p.s else nil
 return if typeof(s)=="number" and s==s then math.floor(math.abs(s))%2147483647 else i
end
-- The company day a shift belongs to: the saved calendar day; from 06:00 until the office opens at 08:00
-- (when the server day index - and with it empire.calendar.day - moves on) already the coming day, so the
-- people arriving at 07:45 are the ones who work today.
function Rota.workday(e: any,hour: number): number
 local day=Ops.day(e)
 if hour>=6 and hour<8 then day+=1 end
 return day
end
-- Profile index i of a hired rig from its StaffIndex (StaffAssignment numbers the roles in ROLES order).
function Rota.before(e: any): {[string]:number}
 local out: {[string]:number}={}
 local n=0
 for _,role in EmpireConfig.ROLES do out[role.id]=n;n+=count(e,role.id) end
 return out
end
function Rota.key(role: string,i: number): string return role..":"..tostring(i) end
-- Presence per role on company day `day` (CompanyOps.presence on a view of the data with that day).
function Rota.presence(e: any,day: number,role: string): {string}
 local view=setmetatable({calendar={day=day}},{__index=e})
 return Ops.presence(view,role)
end
-- Night crew heads of a role: CompanyOps.wage pays the newest min(max(0, paid - seats), seats) paid
-- profiles x1.3 while the night shift is on; exactly those work 22:00-06:00.
function Rota.nightRange(e: any,role: string): (number,number)
 if not Ops.nightOn(e,role) then return 0,0 end
 local n=count(e,role)
 local paid=n-((Ops.leaveCounts(e) :: any)[role] or 0)
 local S=Ops.seats(e,role)
 local heads=math.min(math.max(0,paid-S),S)
 return paid-heads+1,paid
end
-- Seeded day shift of an operations post: on duty before 08:00, off after 18:00.
function Rota.opsShift(seed: number): (number,number)
 local s=math.floor(math.abs(seed))
 local a=Config.OPS_SHIFT.start;local b=Config.OPS_SHIFT.finish
 return a[1]+(s%16)/15*(a[2]-a[1]),b[1]+(s%31)/30*(b[2]-b[1])
end
function Rota.nightCrewOnDuty(hour: number): boolean
 return hour>=Config.NIGHT_CREW.start or hour<Config.NIGHT_CREW.finish
end
-- Everything StaffService needs for one office, recomputed every few seconds.
function Rota.compute(e: any,hour: number): Snapshot
 local day=Rota.workday(e,hour)
 local stage=Ops.stageIndex(e)
 local snap: Snapshot={day=day,stage=stage,away={},night={},apprentices={},apprenticeCount=0,nightCrew=0,securityNight=false,itNight=false,before=Rota.before(e)}
 local profiles=if typeof(e.staffProfiles)=="table" then e.staffProfiles else {}
 local apprentices=typeof(e.apprentices)=="table" and next(e.apprentices)~=nil
 for _,role in EmpireConfig.ROLES do
  local id=role.id
  if count(e,id)==0 then continue end
  local list=profiles[id]
  for i,state in Rota.presence(e,day,id) do
   if state~="present" then snap.away[Rota.key(id,i)]=state end
   if apprentices then
    local p=if typeof(list)=="table" then list[i] else nil
    local seed=seedOf(p,i)
    -- apprentices follow the saved calendar day (graduation is CompanyOps.graduate at the day change)
    local today=Ops.day(e)
    local skill=Ops.apprentice(e,seed,today)
    if skill then
     local entry=e.apprentices[tostring(seed)]
     local age=today-(tonumber(entry and entry.day) or today)
     snap.apprentices[Rota.key(id,i)]={age=math.max(0,age),skill=skill,seed=seed}
     snap.apprenticeCount+=1
    end
   end
  end
  local a,b=Rota.nightRange(e,id)
  for i=a,b do
   if i>=1 then snap.night[Rota.key(id,i)]=true;snap.nightCrew+=1 end
  end
 end
 -- the night crew needs a security post on duty; from stage 5 security and IT keep a night rota
 snap.securityNight=stage>=5 or snap.nightCrew>0
 snap.itNight=stage>=5
 return snap
end
-- Hired staff on duty at `hour`: absent people never; the night crew 22-06; everyone else their seeded
-- shift (EmployeeConfig.personalityFromSeed start..finish).
function Rota.hiredOnDuty(hour: number,start: number,finish: number,away: string?,night: boolean?): boolean
 if away then return false end
 if night then return Rota.nightCrewOnDuty(hour) end
 return hour>=start and hour<finish
end
-- Operations posts: the day shift, or around the clock for a night-rota post (security / IT).
function Rota.opsOnDuty(hour: number,start: number,finish: number,nightRota: boolean?): boolean
 if nightRota then return true end
 return hour>=start and hour<finish
end
-- Night rota of operations post `post` (OpsIndex) for this snapshot.
function Rota.nightRota(snap: Snapshot,post: number): boolean
 if not Config.NIGHT_ROTA_POSTS[post] then return false end
 if post==3 then return snap.securityNight end
 return snap.itNight
end
return Rota
