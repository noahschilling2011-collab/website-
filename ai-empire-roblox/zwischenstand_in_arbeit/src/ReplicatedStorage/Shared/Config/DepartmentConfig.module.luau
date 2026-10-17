--!strict
-- Department identities (role, app, colour, screen). Rooms, access classes and employee movement
-- rules come from the single architectural plan (BuildingPlan); the functions below adapt it to
-- the older call signatures used by staff, workstations and navigation.
local Plan=require(script.Parent.BuildingPlan)
local Config={}
Config.DEPARTMENTS={
 data={name="Data Operations",role="curator",app="data",color={105,140,153},screen="data",description="Collect → filter → clean → tokenize. Better data improves your next model."},
 engineering={name="AI Engineering",role="engineer",app="lab",color={108,133,123},screen="engineering",description="Design a model, install enough VRAM, then train with your own data."},
 design={name="Model Architecture",role="researcher",app="lab",color={147,137,107},screen="design",description="Size sets potential and hardware needs. Focus chooses the model's strengths."},
 training={name="Training Control",role="engineer",app="lab",color={108,133,123},screen="training",description="GPUs process training data. Monitor progress, loss and training decisions."},
 research={name="AI Research",role="researcher",app="empire",section="research",color={126,121,149},screen="research",description="Research improves future models. Data quality still matters."},
 evaluation={name="Model Evaluation",role="researcher",app="lab",section="evaluation",color={129,149,115},screen="evaluation",description="Compare coding, reasoning, math, creativity, knowledge and reliability."},
 growth={name="Product & Growth",role="marketer",app="market",color={168,133,109},screen="growth",description="Launch with pricing and a target market. Users and API customers generate revenue."},
 deployment={name="Deployment Studio",role="marketer",app="lab",section="release",color={168,133,109},screen="deployment",description="Choose a trained model → price subscription and API → target → marketing → launch."},
 -- People & company office rooms in the plan (F_HR, F_ASSISTANTS, wing "hr" rooms) use this department.
 operations={name="People & Operations",role="support",app="empire",section="team",color={120,126,120},screen="hr",description="Hiring, onboarding and company administration keep every team staffed."},
}
export type DepartmentRoom = {
 id: string, name: string, kind: string, department: string, floor: number,
 x1: number, x2: number, z1: number, z2: number, access: string, style: number,
}
-- Plan rooms on one level that belong to a department (work rooms, focus rooms, team offices).
function Config.rooms(tier: number,floor: number): {DepartmentRoom}
 local out: {DepartmentRoom}={}
 for _,r in Plan.roomsOnLevel(tier,floor) do
  local dept=r.dept
  if dept then
   table.insert(out,{id=r.id,name=r.name,kind=r.kind,department=dept,floor=r.level,x1=r.x1,x2=r.x2,z1=r.z1,z2=r.z2,access=r.access,style=r.style})
  end
 end
 return out
end
-- Building-local point check for an employee role (access class of the room at that point).
function Config.employeeAllowed(role: string,x: number,y: number,z: number,tier: number): boolean
 return Plan.employeeAllowed(role,tier,Vector3.new(x,y,z))
end
-- Can this role pass a door / use a workstation of the given access class?
function Config.doorAllowed(role: string,access: string?): boolean
 return Plan.roleAllows(role,access)
end
return Config
