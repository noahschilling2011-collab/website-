--!strict
-- Builds one company headquarters from the shared BuildingPlan. Generators only create geometry,
-- furniture and registration data; doors, the lift, access and work are driven by services.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Layout=require(ReplicatedStorage.Shared.BuildingLayout)
local Palette=require(ReplicatedStorage.Shared.Config.ArchPalette)
-- Generators are loaded defensively so one missing/broken module is reported instead of
-- preventing every company from getting a building.
local function load(name: string): any
	local module=script.Parent:FindFirstChild(name)
	if not module then warn(`[HQ] generator {name} missing`);return nil end
	local ok,result=pcall(require,module)
	if not ok then warn(`[HQ] generator {name} failed to load: {result}`);return nil end
	return result
end
local Kit=load("ArchKit")
local Exterior=load("ExteriorDesign")
local Core=load("CoreDesign")
local Interior=load("InteriorDesign")
local KitsWork=load("RoomKitsWork")
local KitsSpecial=load("RoomKitsSpecial")
local KitsPavilion=load("RoomKitsPavilion")
local StaffAssignment=load("StaffAssignment")
local Design={}
local FOLDERS={"Structure","Facade","Site","Core","Lift","Walls","Doors","Rooms","Circulation","Cameras","Navigation","SharedWorkstations","Blades"}

function Design.staff(office: Model,cf: CFrame,session: any)
	if StaffAssignment then StaffAssignment.assign(office,cf,session) end
end

local function step(label: string,fn: ()->())
	-- One generator failing must not leave a half-registered office without telling us why.
	local ok,err=pcall(fn :: ()->any)
	if not ok then warn(`[HQ] {label} failed: {err}`) end
end

function Design.build(cf: CFrame,session: any,accent: Color3): Model
	local tier=math.clamp(math.floor(session.data.empire.office or 1),1,#Plan.TIER_FLOORS)
	local floors=Plan.floors(tier);local owner=session.userId
	local office=Instance.new("Model");office.Name="Office"
	office:SetAttribute("OwnerUserId",owner);office:SetAttribute("OfficeTier",tier);office:SetAttribute("FloorCount",floors)
	office:SetAttribute("CampusCFrame",cf);office:SetAttribute("FacilitiesVersion",3)
	local folders={}
	for _,name in FOLDERS do local f=Instance.new("Folder");f.Name=name;f.Parent=office;folders[name]=f end
	local company=if session.data.company then session.data.company.name else (session.player.DisplayName.."'s Company")
	local ctx={office=office,cf=cf,tier=tier,floors=floors,owner=owner,session=session,accent=accent,company=company,
		ownerName=session.player.DisplayName,plan=Plan,layout=Layout,kit=Kit,palette=Palette,folders=folders,rooms={}}
	local generators: { { label: string, module: any } }={{label="exterior",module=Exterior},{label="core",module=Core},{label="interior",module=Interior},
		{label="work rooms",module=KitsWork},{label="ground & garage rooms",module=KitsSpecial},{label="pavilion & roof rooms",module=KitsPavilion}}
	for _,def in generators do
		local generator=def.module
		if generator then step(def.label,function() generator.build(ctx) end) end
	end
	step("staff",function() Design.staff(office,cf,session) end)
	return office
end
return Design
