--!strict
-- Campus helpers shared by server and client. Building volumes and access zones delegate to the
-- single architectural plan (BuildingPlan) so walls, doors and access checks never disagree.
local Config = require(script.Parent.Config.CampusConfig)
local Plan = require(script.Parent.Config.BuildingPlan)
local Employee = require(script.Parent.Config.EmployeeConfig)
local Math = {}
function Math.new(): any
	return {snacks={},retailLevel=1,retailClock=0,retailSales=0,retailRevenue=0,cars={compact=true},selectedCar="compact",boostUntil=0,boostSpeed=16}
end
-- Generated employee name whose first name matches the employee's presentation
-- (EmployeeConfig.isFeminine(index, owner)). Unique within a company for up to 32 x 24 people per
-- presentation; owner nil = 0 (legacy single-argument calls keep working).
function Math.staffName(index: number, owner: number?): string
	local o = owner or 0
	local list = if Employee.isFeminine(index, o) then Config.FIRST_NAMES_F else Config.FIRST_NAMES_M
	local k = index - 1 + Employee.hash(o + 7) % (#list * #Config.LAST_NAMES)
	if index >= 300 and index < 400 then
		-- operations staff (301..316): consecutive indices would give the whole block one surname.
		-- Step k by #list+1 instead (a new surname each) and start past the 240 hired indices, so
		-- within one presentation list no name repeats a hired employee's index-based name.
		k = Employee.hash(o + 7) % (#list * #Config.LAST_NAMES) + 240 + (index - 301) * (#list + 1)
	end
	return list[k % #list + 1] .. " " .. Config.LAST_NAMES[(k // #list) % #Config.LAST_NAMES + 1]
end
-- Name for a persistent staff profile seed, consistent with EmployeeConfig.feminine(seed) unless a
-- presentation is given (for recruiting: generate the seed, then the name from it).
function Math.nameForSeed(seed: number, feminine: boolean?): string
	local f = if feminine == nil then Employee.feminine(seed) else feminine
	local list = if f then Config.FIRST_NAMES_F else Config.FIRST_NAMES_M
	local h = Employee.hash(seed * 3 + 11)
	return list[h % #list + 1] .. " " .. Config.LAST_NAMES[(h // #list) % #Config.LAST_NAMES + 1]
end
-- true/false when the first name is in one of the staff lists, nil for unknown names.
local feminineNames: { [string]: boolean } = {}
for _, n in Config.FIRST_NAMES_F do feminineNames[n] = true end
for _, n in Config.FIRST_NAMES_M do feminineNames[n] = false end
function Math.nameFeminine(name: string): boolean?
	local first = string.match(name, "^%s*(%S+)")
	return if first then feminineNames[first] else nil
end
-- Building-local point inside the occupied building (main block, pavilion, garage, roof deck).
function Math.inside(x: number, y: number, z: number, tier: number): boolean
	return Plan.inside(tier, Vector3.new(x, y, z))
end
function Math.garage(x: number, y: number, z: number): boolean
	return Plan.inGarage(Vector3.new(x, y, z))
end
-- Founder-only or hidden room at this point (founder suite, founder services, secret lab, vault).
function Math.privateZone(x: number, y: number, z: number, tier: number): boolean
	local class, room = Plan.accessAt(tier, Vector3.new(x, y, z))
	return class == "founder" or (room ~= nil and room.hidden == true)
end
-- May an ordinary staff member (public + staff clearance) stand here?
function Math.staffAllowed(x: number, y: number, z: number, tier: number): boolean
	return Plan.employeeAllowed("marketer", tier, Vector3.new(x, y, z))
end
function Math.drive(speed: number, throttle: number, steer: number, dt: number, def: any): (number, number)
	local target=if throttle>=0 then throttle*def.speed else throttle*def.reverse
	local delta=math.clamp(target-speed,-def.acceleration*dt,def.acceleration*dt)
	local nextSpeed=speed+delta
	if math.abs(nextSpeed)<.15 then nextSpeed=0 end
	local turn= -steer*def.turn*math.clamp(math.abs(nextSpeed)/18,0,1)*(if nextSpeed<0 then -1 else 1)
	return nextSpeed,turn
end
function Math.finiteUnit(value: any): boolean
	return typeof(value)=="number" and value==value and value>-math.huge and value<math.huge and math.abs(value)<=1
end
return Math
