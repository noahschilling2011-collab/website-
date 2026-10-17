--!strict
-- Campus dimensions, shop catalogues and staff names. Building geometry, rooms and access rules
-- live in BuildingPlan; the values below that describe the building are derived from it.
local Plan = require(script.Parent.BuildingPlan)
local Config = {}
Config.PLOT_COUNT = 12
Config.PITCH = 320
Config.ROW_OFFSET = 252
Config.STREET_Y = 24
Config.FLOOR_HEIGHT = Plan.FLOOR_HEIGHT
Config.WIDTH = Plan.MAIN.x2 - Plan.MAIN.x1
Config.DEPTH = Plan.MAIN.z2 - Plan.MAIN.z1
Config.FLOORS = Plan.TIER_FLOORS -- above-ground storeys per office tier (roof level = FLOORS[tier])
Config.DESKS_PER_FLOOR = 48
Config.CARS = {
	{id="compact",name="Founder's Hatch",price=0,speed=64,reverse=24,acceleration=26,turn=1.8,length=12,width=6.4},
	{id="van",name="Studio Cargo",price=16000,speed=58,reverse=20,acceleration=20,turn=1.5,length=15,width=7.4},
	{id="executive",name="Executive Electric",price=28000,speed=82,reverse=26,acceleration=32,turn=1.65,length=15,width=7},
	{id="sport",name="Circuit GT",price=110000,speed=104,reverse=28,acceleration=40,turn=1.9,length=13.5,width=7.2},
}
Config.SNACKS = {
	{id="coffee",name="House Coffee",price=25,color={113,76,50},speed=20,seconds=90,shape="cup"},
	{id="bar",name="Founder Oat Bar",price=18,color={176,128,73},speed=18,seconds=150,shape="box"},
	{id="juice",name="Orchard Juice",price=30,color={214,155,64},speed=21,seconds=70,shape="cup"},
	{id="lunch",name="Campus Lunch",price=65,color={111,146,85},speed=19,seconds=240,shape="box"},
}
Config.STORES = {
	{id="cafe",name="House Kitchen",subtitle="Coffee, lunch & your own snack label",app="campus"},
	{id="hardware",name="Compute Supply",subtitle="GPUs & cooling equipment",app="compute"},
	{id="studio",name="Company Store",subtitle="Websites, apps & game AI",app="studio"},
	{id="mobility",name="Fleet Desk",subtitle="Collect your company car",app="campus"},
}
Config.RETAIL = {12000,32000,85000}
-- Staff first names by presentation (EmployeeRigDesign/CampusMath.staffName keep name and look
-- consistent). No ambiguous names in either list.
Config.FIRST_NAMES_F = {"Maya","Lea","Sofia","Lina","Ella","Nora","Zoe","Jana","Emma","Yara","Ada","Romy","Nina","Clara","Alma","Amara","Priya","Aiko","Fatima","Ingrid","Lucia","Mei","Nadia","Olivia","Rosa","Sana","Talia","Valentina","Wanjiru","Hana","Leila","Chiara"}
Config.FIRST_NAMES_M = {"Noah","Emil","Amir","Theo","Jonas","Milan","Ben","Luis","Leon","Finn","Luca","Nico","Eli","Tom","Kofi","Arjun","Kenji","Mateo","Omar","Rafael","Sven","Tariq","Hugo","Diego","Hamza","Ivan","Jamal","Kwame","Malik","Oscar","Ravi","Yusuf"}
Config.FIRST_NAMES = table.move(Config.FIRST_NAMES_M, 1, #Config.FIRST_NAMES_M, #Config.FIRST_NAMES_F + 1, table.clone(Config.FIRST_NAMES_F)) -- combined (legacy)
Config.LAST_NAMES = {"Weber","Khan","Meyer","Park","Silva","Chen","Rossi","Schmidt","Diaz","Miller","Kim","Novak","Okafor","Nakamura","Haddad","Johansson","Garcia","Nguyen","Kowalski","Mensah","Patel","Moreau","Costa","Yilmaz"}
function Config.find(list: {any}, id: any): any
	for _,def in list do if def.id == id then return def end end
	return nil
end
-- "2  ·  AI engineering & training" (B1, G, numbered floors, founder floor, R = roof)
function Config.floorName(tier: number, floor: number): string
	return Plan.floorTitle(tier, floor)
end
return Config
