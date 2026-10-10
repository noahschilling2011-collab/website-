--!strict
-- Runtime only: never adds derived fields to the player's save.
-- Skill: every hired person has a persistent skill k (1..5, data.empire.staffProfiles[role][i].k,
-- missing = 3). Their productive weight is factor(k) = (7 + k) / 10, so k = 3 is exactly 1.0.
-- Department output (CORE_SPEC 5.1) is ONE formula, watched or not: Math.count(e, role) = O_r computed from
-- saved data only (CompanyOps.output): the people at work today (vacation / sick hashes, unpaid leave,
-- travelling engineers excluded), the seat rule min(H, S) + 0.5 * overflow, morale. StaffService no longer
-- reports anything: a company produces exactly the same whether its owner, a visitor or nobody watches.
--  * Math.capacity = sum of factor over the hired profiles (profiles beyond the hired count are ignored,
--    a missing profile counts as k = 3); kept for screens and older callers.
--  * Math.set is kept as a no-op so old callers (client StateController) stay valid.
local Math={}
Math.MIN_SKILL=1;Math.MAX_SKILL=5;Math.DEFAULT_SKILL=3
function Math.skill(k: any): number
 if typeof(k)~="number" or k~=k then return Math.DEFAULT_SKILL end
 return math.clamp(math.floor(k+.5),Math.MIN_SKILL,Math.MAX_SKILL)
end
-- Productive weight of one employee with skill k (division keeps k = 3 at exactly 1.0).
function Math.factor(k: any): number return (7+Math.skill(k))/10 end
function Math.capacity(empire: any,role: string): number
 local n=empire.employees[role] or 0
 local profiles=empire.staffProfiles
 local list=if typeof(profiles)=="table" then profiles[role] else nil
 if typeof(list)~="table" then return n end
 local total=0
 for i=1,n do
  local p=list[i]
  total+=if typeof(p)=="table" then Math.factor(p.k) else 1
 end
 return total
end
-- Deprecated: the economy no longer reads watched staff states (CORE_SPEC 5.1). No effect.
function Math.set(_empire: any,_counts: any?) end
-- CompanyOps requires this module at load time, so it is required lazily here (no require cycle).
local ops: any=nil
function Math.count(empire: any,role: string): number
 if ops==nil then
  local module=script.Parent:FindFirstChild("CompanyOps")
  if not module then return Math.capacity(empire,role) end
  ops=(require :: any)(module)
 end
 return ops.output(empire,role)
end
return Math
