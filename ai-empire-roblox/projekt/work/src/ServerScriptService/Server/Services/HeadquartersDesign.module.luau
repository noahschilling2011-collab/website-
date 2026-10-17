--!strict
-- Builds one company headquarters from the shared BuildingPlan. Generators only create geometry,
-- furniture and registration data; doors, the lift, access and work are driven by services.
-- Plan tier 0 (garage stage) runs the same pipeline without the core and the HQ room kits: the
-- exterior builds the converted garage and the construction site, RoomKitsGarage furnishes it.
-- Tiers with Plan.hasHotel also get the guest house (RoomKitsHotel furnishes its rooms).
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
local KitsHotel=load("RoomKitsHotel")
local KitsGarage=load("RoomKitsGarage")
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

-- Plan tier this session's office builds: an explicit session.planTier (admin "tier0" test command,
-- harness; not saved) wins, else the office index through Plan.tierForOffice.
function Design.tierFor(session: any): number
	local forced=session.planTier
	if typeof(forced)=="number" and forced==forced then return Plan.clampTier(forced) end
	local office=if session.data and session.data.empire then session.data.empire.office else nil
	return Plan.tierForOffice(if typeof(office)=="number" then office else 1)
end

function Design.build(cf: CFrame,session: any,accent: Color3): Model
	local tier=Design.tierFor(session)
	local floors=Plan.floors(tier);local owner=session.userId
	local office=Instance.new("Model");office.Name="Office"
	office:SetAttribute("OwnerUserId",owner);office:SetAttribute("OfficeTier",tier);office:SetAttribute("FloorCount",floors)
	office:SetAttribute("CampusCFrame",cf);office:SetAttribute("FacilitiesVersion",3)
	if tier<1 then office:SetAttribute("GarageStage",true) end
	if Plan.hasHotel(tier) then office:SetAttribute("HotelRooms",Plan.HOTEL_ROOMS) end
	local folders={}
	for _,name in FOLDERS do local f=Instance.new("Folder");f.Name=name;f.Parent=office;folders[name]=f end
	local company=if session.data.company then session.data.company.name else (session.player.DisplayName.."'s Company")
	local ctx={office=office,cf=cf,tier=tier,floors=floors,owner=owner,session=session,accent=accent,company=company,
		ownerName=session.player.DisplayName,plan=Plan,layout=Layout,kit=Kit,palette=Palette,folders=folders,rooms={}}
	local generators: { { label: string, module: any } }
	if tier<1 then
		generators={{label="exterior",module=Exterior},{label="interior",module=Interior},{label="garage lab",module=KitsGarage}}
	else
		generators={{label="exterior",module=Exterior},{label="core",module=Core},{label="interior",module=Interior},
			{label="work rooms",module=KitsWork},{label="ground & garage rooms",module=KitsSpecial},{label="pavilion & roof rooms",module=KitsPavilion}}
		if Plan.hasHotel(tier) then table.insert(generators,{label="guest house",module=KitsHotel}) end
	end
	for _,def in generators do
		local generator=def.module
		if generator then step(def.label,function() generator.build(ctx) end) end
	end
	step("staff",function() Design.staff(office,cf,session) end)
	return office
end
return Design
