--!strict
-- The shared world beyond the campus district: pure data and maths, used by the server (CityService,
-- CityBuilder, VehicleService) and the client (TravelController). Nothing here creates instances.
--   * Business City ("downtown", z 800..2300) directly south of the district. Two ring-road extensions
--     and Central Avenue lead there; 14 client offices, the City Hotel, a convention centre, City Plaza.
--   * City Airport (z 2300..3200): terminal (check-in, security, three gates), car park, apron with parked
--     aircraft, taxiway, runway. The harbour strip (z 3200..3800) is water behind a quay wall.
--   * Port Meridian, the international city (z 7500..8700), ~4,400 studs past the runway. It is reached
--     only by flight (client fade + cutscene, server PivotTo), never by road; invisible walls fence it in.
-- North (-Z) is the rival quarter, +X is east (CampusService directory). Every street top is at y = GROUND.
-- Time zone: the same everywhere. Lighting is global per server (StaffService drives ClockTime), so the
-- honest choice is a neighbouring country in the same time zone (world_map.md, "Day and night").
local Config=require(script.Parent.CampusConfig)
local BuildingPlan=require(script.Parent.BuildingPlan)
local City={}

export type Rect={x1: number,x2: number,z1: number,z2: number}
export type Zone={id: string,name: string,x1: number,x2: number,z1: number,z2: number,drivable: boolean}
export type Road={id: string,name: string,axis: string,c: number,a1: number,a2: number,width: number,walk: number}
export type Layout={door: Vector3,lobby: Vector3,desk: Vector3,reception: Vector3,meeting: Vector3?,meetingRoom: Rect?,meetingTable: Vector3?,bays: {number}}
export type Building={id: string,kind: string,name: string,zone: string,frame: CFrame,width: number,depth: number,floors: number,style: string,accent: Color3,parking: boolean,interior: string,skyline: boolean,clientId: string?}
export type Destination={id: string,kind: string,name: string,zone: string,door: CFrame,lobby: CFrame,parking: {CFrame},drive: Vector3?,meeting: CFrame?,reception: CFrame?,clientId: string?,contract: string?,business: string?,building: Building?}
export type Route={points: {Vector3},length: number,nodes: {string}}
export type PlotInfo={index: number,cframe: CFrame,rect: Rect,driveway: Vector3,gate: Vector3}

City.GROUND=Config.STREET_Y
City.ROAD_TOP=City.GROUND+.22 -- asphalt (part centre GROUND+.12, .2 thick), same as the district avenue
City.WALK_TOP=City.GROUND+.475 -- sidewalks (part centre GROUND+.15, .65 thick)
City.TIME_ZONE_OFFSET=0 -- seconds added to the campus clock abroad: 0 = same time zone (see header)
City.TRAVEL={
	ticket=700, -- CORE_SPEC 11.4: = CompanyOps.TRIPS.abroad.flight; return ticket to Port Meridian, paid at the home check-in (the flight home is included)
	flightSeconds=10, -- length of the client cutscene; the server holds the character this long, then releases it
	streamTimeout=8, -- seconds Player:RequestStreamAroundAsync may wait for the arrival area
	checkinRadius=16, -- server distance check: character root to a check-in counter
	arriveRadius=28, -- GPS guide: the route counts as reached this close to its last point
}

------------------------------------------------------------------------------------------------ zones
City.DISTRICT={x1=-1150,x2=1150,z1=-800,z2=800}
City.ZONES={
	{id="district",name="Campus District",x1=-1160,x2=1160,z1=-800,z2=800,drivable=true}, -- old car bounds kept
	{id="downtown",name="Business City",x1=-1150,x2=1150,z1=800,z2=2300,drivable=true},
	{id="airport",name="City Airport",x1=-1150,x2=1150,z1=2300,z2=3200,drivable=true},
	{id="harbour",name="Harbour",x1=-1150,x2=1150,z1=3200,z2=3800,drivable=false},
	{id="abroad",name="Port Meridian",x1=-700,x2=700,z1=7500,z2=8700,drivable=false},
} :: {Zone}
-- Corridors CampusService keeps free in its parkland (it builds their supports; CityBuilder lays the roads).
City.DISTRICT_LINKS={
	{x1=-1042,x2=-990,z1=540,z2=800}, -- West Ring Road extension
	{x1=990,x2=1042,z1=540,z2=800}, -- East Ring Road extension
	{x1=-28,x2=28,z1=550,z2=800}, -- Central Avenue (road 40 + sidewalks 8)
} :: {Rect}

------------------------------------------------------------------------------------------------ roads
local function road(id: string,name: string,axis: string,c: number,a1: number,a2: number,width: number,walk: number): Road
	return {id=id,name=name,axis=axis,c=c,a1=a1,a2=a2,width=width,walk=walk}
end
-- New roads (CityBuilder). axis "x": runs along X at z = c from x = a1 to a2; axis "z": along Z at x = c.
-- walk = sidewalk width on both sides (0 = none). Every part stays <= 2048 studs long.
City.ROADS={
	road("ring_w","West Ring Road","z",-1016,540,2404,48,0),
	road("ring_e","East Ring Road","z",1016,540,2404,48,0),
	road("central","Central Avenue","z",0,540,2400,40,8),
	road("parkway","Parkway","x",1000,-1016,1016,40,8),
	road("business","Business Avenue","x",1500,-1016,1016,40,8),
	road("harbour","Harbour Road","x",2000,-1016,1016,40,8),
	road("west","West Street","z",-340,1000,2000,40,8),
	road("east","East Street","z",340,1000,2000,40,8),
	road("airport","Airport Road","x",2380,-1016,1016,40,8),
} :: {Road}
-- Existing district streets (CampusService) - only for the route graph and on-road checks.
City.DISTRICT_ROADS={
	road("avenue","Innovation Avenue","x",0,-1024,1024,50,8),
	road("boulevard_n","North Boulevard","x",-515,-1024,1024,50,8),
	road("boulevard_s","South Boulevard","x",515,-1024,1024,50,8),
	road("ring_w_d","West Ring Road","z",-1016,-540,540,48,0),
	road("ring_e_d","East Ring Road","z",1016,-540,540,48,0),
	road("rival_link","Rival Link","z",0,-660,-510,24,0),
} :: {Road}

function City.roadRect(r: Road,withWalk: boolean?): Rect
	local h=r.width/2+(if withWalk then r.walk else 0)
	if r.axis=="x" then return {x1=r.a1,x2=r.a2,z1=r.c-h,z2=r.c+h} end
	return {x1=r.c-h,x2=r.c+h,z1=r.a1,z2=r.a2}
end
local function inRect(r: Rect,x: number,z: number,m: number?): boolean
	local e=m or 0
	return x>=r.x1-e and x<=r.x2+e and z>=r.z1-e and z<=r.z2+e
end
City.inRect=inRect
-- On the asphalt of any road (margin in studs, default 0.5).
function City.onRoad(p: Vector3,margin: number?): boolean
	local m=margin or .5
	for _,list in {City.ROADS,City.DISTRICT_ROADS} do
		for _,r in list do if inRect(City.roadRect(r),p.X,p.Z,m) then return true end end
	end
	return false
end

function City.zoneAt(p: Vector3): string?
	for _,z in City.ZONES do if p.X>=z.x1 and p.X<=z.x2 and p.Z>=z.z1 and p.Z<=z.z2 then return z.id end end
	return nil
end
function City.zone(id: string): Zone?
	for _,z in City.ZONES do if z.id==id then return z end end
	return nil
end
-- VehicleService bounds: a player car outside every drivable zone (or below the map) is reset.
function City.drivable(p: Vector3): boolean
	if p.X~=p.X or p.Z~=p.Z then return false end
	for _,z in City.ZONES do
		if z.drivable and p.X>=z.x1 and p.X<=z.x2 and p.Z>=z.z1 and p.Z<=z.z2 then return true end
	end
	return false
end

------------------------------------------------------------------------------------------------ plots
-- The twelve campus plots exactly like PlotService.init / CampusService.plotSites.
local plotCache: {PlotInfo}?=nil
function City.plots(): {PlotInfo}
	local cached=plotCache;if cached then return cached end
	local out: {PlotInfo}={}
	local s=BuildingPlan.SITE
	for i=1,Config.PLOT_COUNT do
		local row=if i<=6 then -1 else 1;local x=((i-1)%6-2.5)*Config.PITCH
		local cf=CFrame.lookAt(Vector3.new(x,Config.STREET_Y,row*Config.ROW_OFFSET),Vector3.new(x,Config.STREET_Y,0))
		local r: Rect={x1=math.huge,x2=-math.huge,z1=math.huge,z2=-math.huge}
		for _,c in {Vector3.new(s.x1,0,s.z1),Vector3.new(s.x2,0,s.z1),Vector3.new(s.x1,0,s.z2),Vector3.new(s.x2,0,s.z2)} do
			local w=cf:PointToWorldSpace(c)
			r.x1,r.x2,r.z1,r.z2=math.min(r.x1,w.X),math.max(r.x2,w.X),math.min(r.z1,w.Z),math.max(r.z2,w.Z)
		end
		-- driveway mouth on the avenue sidewalk and the approach in front of the garage barrier (ExteriorDesign)
		table.insert(out,{index=i,cframe=cf,rect=r,driveway=cf:PointToWorldSpace(Vector3.new(102,0,s.z1)),gate=cf:PointToWorldSpace(Vector3.new(102,0,-150))})
	end
	plotCache=out
	return out
end
function City.plotAt(p: Vector3): PlotInfo?
	for _,info in City.plots() do if inRect(info.rect,p.X,p.Z) then return info end end
	return nil
end

------------------------------------------------------------------------------------------------ road graph
local function v(x: number,z: number): Vector3 return Vector3.new(x,City.GROUND,z) end
City.NODES={
	av_w=v(-1016,0),av_e=v(1016,0),
	nb_w=v(-1016,-515),nb_c=v(0,-515),nb_e=v(1016,-515),
	sb_w=v(-1016,515),sb_c=v(0,515),sb_e=v(1016,515),
	rival=v(0,-640),lab=v(-1016,-130),
	rw_1000=v(-1016,1000),rw_1500=v(-1016,1500),rw_2000=v(-1016,2000),rw_2380=v(-1016,2380),
	re_1000=v(1016,1000),re_1500=v(1016,1500),re_2000=v(1016,2000),re_2380=v(1016,2380),
	c_1000=v(0,1000),c_1500=v(0,1500),c_2000=v(0,2000),c_2380=v(0,2380),
	w_1000=v(-340,1000),w_1500=v(-340,1500),w_2000=v(-340,2000),
	e_1000=v(340,1000),e_1500=v(340,1500),e_2000=v(340,2000),
} :: {[string]: Vector3}
City.EDGES={
	-- district (existing streets)
	{"av_w","av_e"},{"nb_w","nb_c"},{"nb_c","nb_e"},{"sb_w","sb_c"},{"sb_c","sb_e"},{"nb_c","rival"},
	{"nb_w","lab"},{"lab","av_w"},{"av_w","sb_w"},{"nb_e","av_e"},{"av_e","sb_e"},
	-- ring-road extensions and Central Avenue
	{"sb_w","rw_1000"},{"rw_1000","rw_1500"},{"rw_1500","rw_2000"},{"rw_2000","rw_2380"},
	{"sb_e","re_1000"},{"re_1000","re_1500"},{"re_1500","re_2000"},{"re_2000","re_2380"},
	{"sb_c","c_1000"},{"c_1000","c_1500"},{"c_1500","c_2000"},{"c_2000","c_2380"},
	-- cross streets
	{"rw_1000","w_1000"},{"w_1000","c_1000"},{"c_1000","e_1000"},{"e_1000","re_1000"},
	{"rw_1500","w_1500"},{"w_1500","c_1500"},{"c_1500","e_1500"},{"e_1500","re_1500"},
	{"rw_2000","w_2000"},{"w_2000","c_2000"},{"c_2000","e_2000"},{"e_2000","re_2000"},
	{"w_1000","w_1500"},{"w_1500","w_2000"},{"e_1000","e_1500"},{"e_1500","e_2000"},
	{"rw_2380","c_2380"},{"c_2380","re_2380"},
} :: {{string}}
local NODE_IDS: {string}={}
for id in City.NODES do table.insert(NODE_IDS,id) end
table.sort(NODE_IDS)
City.NODE_IDS=NODE_IDS

local function flat(a: Vector3,b: Vector3): number
	local dx,dz=a.X-b.X,a.Z-b.Z;return math.sqrt(dx*dx+dz*dz)
end
City.flat=flat
-- Closest point of segment a-b to p (XZ plane, y = GROUND) and its distance.
local function project(p: Vector3,a: Vector3,b: Vector3): (Vector3,number)
	local dx,dz=b.X-a.X,b.Z-a.Z;local len2=dx*dx+dz*dz
	local t=if len2>0 then math.clamp(((p.X-a.X)*dx+(p.Z-a.Z)*dz)/len2,0,1) else 0
	local q=v(a.X+dx*t,a.Z+dz*t)
	return q,flat(p,q)
end
-- Nearest graph edge: edge index, point on it, distance.
function City.snap(p: Vector3): (number,Vector3,number)
	local best,bestQ,bestD=0,p,math.huge
	for i,e in City.EDGES do
		local q,d=project(p,City.NODES[e[1]],City.NODES[e[2]])
		if d<bestD-1e-9 then best,bestQ,bestD=i,q,d end
	end
	return best,bestQ,bestD
end
-- Dijkstra over the graph plus two temporary nodes (the snapped start S and end E).
local function shortest(sEdge: number,sQ: Vector3,eEdge: number,eQ: Vector3): {string}?
	local pos: {[string]: Vector3}={S=sQ,E=eQ}
	for id,p in City.NODES do pos[id]=p end
	local adj: {[string]: {string}}={S={},E={}}
	for _,id in NODE_IDS do adj[id]={} end
	local function link(a: string,b: string) table.insert(adj[a],b);table.insert(adj[b],a) end
	for i,e in City.EDGES do
		if i~=sEdge and i~=eEdge then link(e[1],e[2]) end
	end
	local se,ee=City.EDGES[sEdge],City.EDGES[eEdge]
	-- the snapped edges are split at S/E (their endpoints stay connected through the split point)
	link("S",se[1]);link("S",se[2]);link("E",ee[1]);link("E",ee[2])
	if sEdge==eEdge then link("S","E") end
	local dist: {[string]: number}={S=0};local prev: {[string]: string}={};local done: {[string]: boolean}={}
	local order: {string}={"S","E"};for _,id in NODE_IDS do table.insert(order,id) end
	while true do
		local u: string?=nil;local du=math.huge
		for _,id in order do local d=dist[id];if d and not done[id] and d<du then u,du=id,d end end
		if not u then return nil end
		if u=="E" then break end
		done[u]=true
		for _,w in adj[u] do
			if not done[w] then
				local nd=du+flat(pos[u],pos[w])
				if nd<(dist[w] or math.huge)-1e-9 then dist[w]=nd;prev[w]=u end
			end
		end
	end
	local path: {string}={}
	local cur: string?="E"
	while cur do table.insert(path,1,cur);cur=prev[cur] end
	return path
end
-- Driving route between two world points. Points inside a campus plot leave/enter through its garage
-- barrier and driveway. Port Meridian has no roads: a route there is a straight walk, and a route
-- between home and abroad does not exist (err "FLIGHT_REQUIRED").
function City.route(from: Vector3,to: Vector3): (Route?,string?)
	local zf,zt=City.zoneAt(from),City.zoneAt(to)
	if zf==nil or zt==nil then return nil,"OFF_MAP" end
	if zf=="abroad" or zt=="abroad" then
		if zf==zt then return {points={from,to},length=flat(from,to),nodes={}},nil end
		return nil,"FLIGHT_REQUIRED"
	end
	if not City.drivable(from) or not City.drivable(to) then return nil,"OFF_MAP" end
	local head: {Vector3}={from};local tail: {Vector3}={to}
	local s,e=from,to
	local pf=City.plotAt(from);if pf then table.insert(head,pf.gate);table.insert(head,pf.driveway);s=pf.driveway end
	local pt=City.plotAt(to);if pt then table.insert(tail,1,pt.gate);table.insert(tail,1,pt.driveway);e=pt.driveway end
	local sEdge,sQ=City.snap(s);local eEdge,eQ=City.snap(e)
	local path=shortest(sEdge,sQ,eEdge,eQ);if not path then return nil,"NO_ROUTE" end
	local points: {Vector3}={};local nodes: {string}={}
	local function add(p: Vector3) if #points==0 or flat(points[#points],p)>.5 then table.insert(points,p) end end
	for _,p in head do add(p) end
	for _,id in path do
		if id=="S" then add(sQ) elseif id=="E" then add(eQ) else add(City.NODES[id]);table.insert(nodes,id) end
	end
	for _,p in tail do add(p) end
	local length=0
	for i=2,#points do length+=flat(points[i-1],points[i]) end
	return {points=points,length=length,nodes=nodes},nil
end

------------------------------------------------------------------------------------------------ buildings
-- Client offices (60 x 60) and hotels share one generator (CityBuilder.building). Local frame of a building:
-- origin = middle of its street front at ground level, -Z (LookVector) points to the street, the building
-- covers x -w/2..w/2, z 0..depth, the visitor parking (18 deep) lies in front at z -18..0.
City.OFFICE={width=60,depth=60,groundHeight=16,floorHeight=14,parkingDepth=18,doorWidth=10,setback=46}
-- Interior positions in the local frame (shared by the generator and the destination CFrames).
function City.layout(b: Building): Layout
	local w=b.width
	local bays: {number}={}
	if b.parking then
		for _,x in {-(w/2-8),-(w/2-18),w/2-18,w/2-8} do table.insert(bays,x) end
		table.sort(bays)
	end
	if b.interior=="hotel" then
		return {door=Vector3.new(0,3.5,-5),lobby=Vector3.new(-w/4,3.5,20),desk=Vector3.new(0,0,40),reception=Vector3.new(0,3.5,45),bays=bays}
	end
	return {door=Vector3.new(0,3.5,-5),lobby=Vector3.new(-12,3.5,12),desk=Vector3.new(0,0,22.75),reception=Vector3.new(0,3.5,27.5),
		meeting=Vector3.new(17.5,3.5,42),meetingRoom={x1=6,x2=29,z1=38,z2=59},meetingTable=Vector3.new(17.5,0,49.5),bays=bays}
end
-- Street frame: building on side +1 (greater coordinate) or -1 of a street, front `setback` from its centre.
local function streetFrame(axis: string,c: number,along: number,side: number,setback: number): CFrame
	if axis=="x" then
		local o=Vector3.new(along,City.GROUND,c+side*setback)
		return CFrame.lookAt(o,o-Vector3.new(0,0,side))
	end
	local o=Vector3.new(c+side*setback,City.GROUND,along)
	return CFrame.lookAt(o,o-Vector3.new(side,0,0))
end
local function rgb(t: {number}): Color3 return Color3.fromRGB(t[1],t[2],t[3]) end
-- id, name, refKind, refId, zone, axis, street c, along, side, setback, floors, style, accent
-- refKind/refId match EmpireConfig.CONTRACTS ids ("contract") or MarketService businesses ids ("business").
local CLIENTS: {{any}}={
	{"clouddesk","CloudDesk","contract","helpdesk","downtown","x",1000,-860,1,46,5,"glass",{92,160,214}},
	{"byteworks","ByteWorks","contract","code","downtown","x",1000,-680,1,46,4,"brick",{222,128,60}},
	{"studyspark","StudySpark","contract","study","downtown","x",1000,-500,1,46,3,"ribbon",{232,190,72}},
	{"pixelforge","PixelForge","contract","creative","downtown","x",1000,500,1,46,6,"fins",{196,84,150}},
	{"novalogistics","Nova Logistics","contract","enterprise","downtown","x",1000,680,1,46,7,"stone",{64,150,140}},
	{"pixelgames","Pixel Games","business","pixel","downtown","x",1500,-860,-1,46,3,"ribbon",{130,96,200}},
	{"northlogistics","North Logistics","business","north","downtown","x",1500,-680,-1,46,4,"stone",{58,88,140}},
	{"paperstudio","Paper Studio","business","paper","downtown","x",1500,-500,-1,46,3,"brick",{200,80,70}},
	{"ledgerfinance","Ledger Finance","business","ledger","downtown","x",1500,-680,1,46,8,"glass",{200,160,70}},
	{"orbitgames","Orbit Games","business","orbit","downtown","x",1500,-170,1,46,4,"fins",{120,190,80}},
	{"atlassearch","Atlas Search","business","atlas","downtown","x",1500,170,1,46,6,"glass",{70,120,220}},
	{"civicsupport","Civic Support","business","civic","downtown","x",1500,500,1,46,3,"stone",{80,150,90}},
	{"deltarobotics","Delta Robotics","business","delta","downtown","x",1500,680,1,46,6,"setback",{210,70,60}},
	{"mosaicworlds","Mosaic Worlds","business","mosaic","downtown","x",1500,860,1,46,5,"ribbon",{230,120,100}},
	-- Port Meridian: four towers on Meridian Boulevard (x = 0), no visitor parking (nobody drives abroad)
	{"helixresearch","Helix Research","business","helix","abroad","z",0,7930,-1,150,12,"glass",{60,190,200}},
	{"orbitsystems","Orbit Systems","contract","frontier","abroad","z",0,7930,1,150,11,"fins",{150,110,220}},
	{"novainfrastructure","Nova Infrastructure","business","nova","abroad","z",0,8230,-1,150,10,"stone",{60,140,120}},
	{"frontierscience","Frontier Science","business","frontier","abroad","z",0,8230,1,150,13,"setback",{220,90,70}},
}
City.BUILDINGS={} :: {Building}
City.CLIENTS={} :: {{id: string,name: string,contract: string?,business: string?,zone: string}}
for _,c in CLIENTS do
	local zone: string=c[5]
	local b: Building={id=c[1],kind=if zone=="abroad" then "tower" else "office",name=c[2],zone=zone,frame=streetFrame(c[6],c[7],c[8],c[9],c[10]),
		width=60,depth=60,floors=c[11],style=c[12],accent=rgb(c[13]),parking=zone~="abroad",interior="office",
		skyline=zone=="downtown" and c[11]>=6,clientId=c[1]}
	table.insert(City.BUILDINGS,b)
	table.insert(City.CLIENTS,{id=c[1],name=c[2],contract=if c[3]=="contract" then c[4] else nil,business=if c[3]=="business" then c[4] else nil,zone=zone})
end
table.insert(City.BUILDINGS,{id="city_hotel",kind="hotel",name="City Hotel",zone="downtown",frame=streetFrame("x",1000,860,1,46),width=100,depth=120,
	floors=9,style="hotel",accent=Color3.fromRGB(178,150,98),parking=true,interior="hotel",skyline=true})
table.insert(City.BUILDINGS,{id="intl_hotel",kind="hotel",name="Meridian Grand Hotel",zone="abroad",frame=CFrame.new(0,City.GROUND,8380),width=140,depth=120,
	floors=10,style="hotel",accent=Color3.fromRGB(196,170,120),parking=false,interior="hotel",skyline=false})
function City.building(id: string): Building?
	for _,b in City.BUILDINGS do if b.id==id then return b end end
	return nil
end

------------------------------------------------------------------------------------------------ venues
-- Convention centre (custom generator): front on the Parkway, 220 x 180.
City.CONVENTION={frame=streetFrame("x",1000,-170,1,80),width=220,depth=180,height=30}
City.PLAZA={x1=60,x2=300,z1=1060,z2=1440}
-- Home airport (world coordinates; terminal front faces north onto the forecourt and Airport Road).
City.AIRPORT={
	terminal={x1=-300,x2=300,z1=2430,z2=2530},height=30,
	entrances={-150,0,150}, -- door openings in the north facade (x centres, 12 wide)
	checkin={Vector3.new(-225,City.GROUND,2461),Vector3.new(-75,City.GROUND,2461),Vector3.new(75,City.GROUND,2461),Vector3.new(225,City.GROUND,2461)},
	security=2485,lanes={-60,0,60},
	gates={CFrame.lookAt(Vector3.new(-200,28,2512),Vector3.new(-200,28,2600)),CFrame.lookAt(Vector3.new(0,28,2512),Vector3.new(0,28,2600)),CFrame.lookAt(Vector3.new(200,28,2512),Vector3.new(200,28,2600))},
	arrival=CFrame.new(250,28,2450), -- home arrivals: east end of the landside hall, facing the exit (north)
	carParkLot={x1=-820,x2=-340,z1=2400,z2=2528},
	carParkBays={} :: {CFrame},
	carPark=CFrame.new(), -- set below: bay 1 of row A
	apron={x1=-700,x2=700,z1=2530,z2=2840},
	stands={-200,0,200}, -- parked aircraft x, nose towards the terminal
	taxiway={x1=-1000,x2=1000,z1=2840,z2=2880},
	runway={x1=-1100,x2=1100,z1=2940,z2=3060},
	tower=Vector3.new(820,City.GROUND,2620),
	hangar={x1=-1000,x2=-840,z1=2560,z2=2720},
	-- airport package (additive): stands, markers and zones for the shuttle, company jet and VIP logic
	apronTop=City.GROUND+.25, -- top of the apron / hangar floor (aircraft wheels stand here)
	standZ=2612,standScale=1.8, -- parked aircraft: AircraftModel pivot z and scale on every stand
	standCFrames={} :: {CFrame}, -- set below: pivot per stand (nose north towards the terminal), index = gate A<i>
	shuttleStand=1, -- the public Port Meridian shuttle docks at gate A1 (departure boards say so)
	arrivalsDoor=270, -- extra door opening (12 wide) in the north facade: arrivals exit, east end of the hall
	taxilane=2790, -- apron taxilane centreline (z) behind the stands; lead-in lines join it
	exits={-450,450}, -- x where lead-out lines leave the taxilane for the taxiway
	connectors={-950,950}, -- taxiway -> runway connectors (x)
	holdShortZ=2924, -- hold-short line on both connectors
	companyJetStand=CFrame.lookAt(Vector3.new(-772,City.GROUND+.25,2640),Vector3.new(-700,City.GROUND+.25,2640)), -- nose east
	crewRoom=CFrame.lookAt(Vector3.new(-226,City.GROUND+3.5,2491),Vector3.new(-226,City.GROUND+3.5,2499)), -- pilots start here
	lounge={x1=-298.5,x2=-238,z1=2485.5,z2=2529.2} :: Rect, -- business lounge (airside, west end)
	loungeDoor=Vector3.new(-238.6,City.GROUND+3.5,2502.5), -- its doorway in the east wall
}
for i=0,7 do -- row A of the car park, nearest the terminal first; cars park nose south
	table.insert(City.AIRPORT.carParkBays,CFrame.lookAt(Vector3.new(-355-i*10,City.GROUND+2,2421),Vector3.new(-355-i*10,City.GROUND+2,2440)))
end
City.AIRPORT.carPark=City.AIRPORT.carParkBays[1]
for _,x in City.AIRPORT.stands do table.insert(City.AIRPORT.standCFrames,CFrame.new(x,City.AIRPORT.apronTop,City.AIRPORT.standZ)) end
-- Ground route from a stand to the runway along the painted lines (pushback onto the taxilane, lead-out to
-- the taxiway, connector, hold-short line, runway centreline). runwayEnd "west" (default): line up at the
-- west connector for a take-off towards +X; "east": the east connector, take-off towards -X. Points at y =
-- apronTop. Reverse the list for the arrival taxi. (Data only - the flight package animates it.)
function City.taxiRoute(stand: number,runwayEnd: string?): {Vector3}
	local a=City.AIRPORT;local y=a.apronTop
	local cf=a.standCFrames[stand] or a.standCFrames[1]
	local east=runwayEnd=="east"
	local exitX=if east then a.exits[2] else a.exits[1]
	local conn=if east then a.connectors[2] else a.connectors[1]
	local tz=(a.taxiway.z1+a.taxiway.z2)/2;local rz=(a.runway.z1+a.runway.z2)/2
	local x=cf.Position.X
	return {cf.Position,Vector3.new(x,y,a.taxilane),Vector3.new(exitX,y,a.taxilane),Vector3.new(exitX,y,tz),
		Vector3.new(conn,y,tz),Vector3.new(conn,y,a.holdShortZ),Vector3.new(conn,y,rz)}
end
-- Terminal seating and pedestrian network (airport package, additive; data only). AirportBuilder builds the
-- seat rows from seatRows, so seats[] always matches the real pads; a later walker set (CityLifeController /
-- an airport crowd) can use walk + seats. facing 0 = back-to-back double row, +-1 = single row facing +-Z.
-- Seats: n = floor((x2 - x1) / 2.6) per row side, p = the pad top, face = the way a seated person looks.
export type AirportSeatRow={x1: number,x2: number,z: number,facing: number,gate: string?}
export type AirportSeat={p: Vector3,face: Vector3,gate: string?}
-- Walk graph in the MetroPlan WalkNode / WalkEdge shape: name = readable key, idle = what a walker does on that
-- node ("checkin" | "queue" | "security" | "gate" | "board" | "shop" | "food" | "lounge" | "reclaim" | "wait"),
-- face = where it looks while idle, portal = a door to the outside (spawn / despawn).
export type AirportWalkNode={id: number,name: string,p: Vector3,links: {number},idle: string?,face: Vector3?,seat: Vector3?,portal: boolean?}
export type AirportWalkEdge={id: number,a: number,b: number,half: number,len: number}
do
	local a=City.AIRPORT
	local F=City.GROUND+.5 -- terminal floor top
	local rows: {AirportSeatRow}={}
	for i,gx in a.stands do
		local g="A"..i
		-- west of the desk / boarding lane (gx-17.4 .. gx+5.8 stays free), east of it
		table.insert(rows,{x1=gx-34,x2=gx-17.4,z=2511.5,facing=0,gate=g})
		table.insert(rows,{x1=gx-34,x2=gx-17.4,z=2524.5,facing=0,gate=g})
		table.insert(rows,{x1=gx+5.8,x2=gx+34,z=2511.5,facing=0,gate=g})
		table.insert(rows,{x1=gx+5.8,x2=gx+34,z=2519.5,facing=0,gate=g})
	end
	for _,x in {-112,-38,38,112} do table.insert(rows,{x1=x-8,x2=x+8,z=2437.5,facing=-1}) end -- by the doors
	table.insert(rows,{x1=-294,x2=-280,z=2460,facing=1}) -- information desk
	table.insert(rows,{x1=284,x2=296,z=2480,facing=-1}) -- baggage reclaim
	for _,x in {-150,150} do table.insert(rows,{x1=x-9.1,x2=x+9.1,z=2479.5,facing=0}) end -- seating islands
	a.seatRows=rows
	local seats: {AirportSeat}={}
	for _,r in rows do
		local n=math.max(1,math.floor((r.x2-r.x1)/2.6))
		local w=(r.x2-r.x1)/n
		local sides: {{number}}=if r.facing==0 then {{-1.4,-1},{1.4,1}} else {{0,r.facing}}
		for i=0,n-1 do
			for _,sd in sides do
				table.insert(seats,{p=Vector3.new(r.x1+(i+.5)*w,F+1.95,r.z+sd[1]),face=Vector3.new(0,0,sd[2]),gate=r.gate})
			end
		end
	end
	a.seats=seats
	-- walk graph
	local nodes: {AirportWalkNode}={}
	local byName: {[string]: number}={}
	local edges: {AirportWalkEdge}={}
	local function node(name: string,x: number,z: number,idle: string?,face: Vector3?,portal: boolean?): number
		local id=#nodes+1
		nodes[id]={id=id,name=name,p=Vector3.new(x,F,z),links={},idle=idle,face=face,portal=portal}
		byName[name]=id
		return id
	end
	local function link(n1: string,n2: string)
		local i,j=byName[n1],byName[n2]
		assert(i and j,"airport walk link "..n1.." - "..n2)
		local pa,pb=nodes[i].p,nodes[j].p
		table.insert(nodes[i].links,j);table.insert(nodes[j].links,i)
		table.insert(edges,{id=#edges+1,a=i,b=j,half=1,len=(Vector3.new(pb.X,0,pb.Z)-Vector3.new(pa.X,0,pa.Z)).Magnitude})
	end
	local function chain(list: {string}) for k=2,#list do link(list[k-1],list[k]) end end
	local N,S,E,W=Vector3.new(0,0,-1),Vector3.new(0,0,1),Vector3.new(1,0,0),Vector3.new(-1,0,0)
	-- doors and the landside line between the doors and the queues (z 2443)
	for k,x in a.entrances do node("door"..k,x,2433,nil,nil,true) end
	node("doorArr",a.arrivalsDoor,2433,nil,nil,true)
	local lineX: {number}={-249,-243.5,-150,-106,-100.5,-63,-23.5,0,56.6,65,70.5,150,201,206.5,262,a.arrivalsDoor}
	table.sort(lineX)
	local line: {string}={}
	for _,x in lineX do table.insert(line,"L"..x);node("L"..x,x,if x==262 then 2440.5 else 2443) end -- 262: past the GPS kiosk
	chain(line)
	for k,x in a.entrances do link("door"..k,"L"..x) end
	link("doorArr","L"..a.arrivalsDoor)
	-- check-in islands: serpentine queue (enter at the west end, three lanes), desk fronts, exit to the west
	local offs: {{number}}={{-21,21},{-28,7},{-7,28},{-21,21}}
	local deskOffs: {{number}}={{-21,-14,-7,0,7,14,21},{-28,-21,-14,-7,0,7},{-7,0,7,14,21,28},{-21,-14,-7,0,7,14,21}}
	for i,c in a.checkin do
		local o=offs[i] or offs[1]
		local lo,hi=c.X+o[1],c.X+o[2]
		local k="Q"..i
		node(k.."a",lo+2.5,2447,"queue",E);node(k.."b",hi-2.5,2447,"queue",E)
		node(k.."c",hi-2.5,2450.6,"queue",W);node(k.."d",lo+2.5,2450.6,"queue",W)
		node(k.."e",lo+2.5,2454.2,"queue",E);node(k.."f",hi-2.5,2454.2,"queue",E)
		node(k.."g",hi-2.5,2457.4,"checkin",S)
		chain({"L"..(lo+2.5),k.."a",k.."b",k.."c",k.."d",k.."e",k.."f",k.."g"})
		local desks: {string}={}
		for j=#(deskOffs[i] or deskOffs[1]),1,-1 do
			local dx=(deskOffs[i] or deskOffs[1])[j]
			if c.X+dx<hi-2.4 then node(k.."desk"..j,c.X+dx,2457.4,"checkin",S);table.insert(desks,k.."desk"..j) end
		end
		node(k.."x",lo-3,2457.4)
		local list={k.."g"};for _,d in desks do table.insert(list,d) end;table.insert(list,k.."x");table.insert(list,"L"..(lo-3))
		chain(list)
	end
	-- security: lane 1 and 3 funnels, lane 2 serpentine; e-gate, divest table, walk-through arch, recompose
	local lanes=a.lanes
	local lx1,lx2,lx3=lanes[1]-3.4,lanes[2]-3.4,lanes[3]-3.4
	node("S1a",lx1,2457);node("S3a",lx3,2456)
	chain({"L-63","S1a"});link("L56.6","S3a")
	node("S2a",-23.5,2452,"queue",S);node("S2b",-23.5,2455.6,"queue",E);node("S2c",17.5,2455.6,"queue",S)
	node("S2d",17.5,2459.2,"queue",W);node("S2e",-23.5,2459.2,"queue",S);node("S2f",-23.5,2462.8,"queue",E)
	node("S2g",lx2,2462.8)
	chain({"L-23.5","S2a","S2b","S2c","S2d","S2e","S2f","S2g"})
	for i,x in {lx1,lx2,lx3} do
		local k="S"..i
		node(k.."gate",x,2463,"queue",S);node(k.."egate",x,2467.3)
		node(k.."divest",x,2476,"security",E);node(k.."arch",x,2485);node(k.."recompose",x,2493,"security",E)
		node(k.."out",x,2503)
		chain({k.."gate",k.."egate",k.."divest",k.."arch",k.."recompose",k.."out"})
	end
	link("S1a","S1gate");link("S2g","S2gate");link("S3a","S3gate")
	-- airside concourse (z 2503): lounge, shops, duty free, gates, food court
	local cx: {number}={-230,-200,-190,-144,-90,lx1,-36,lx2,0,36,lx3,100,159,200,236}
	table.sort(cx)
	local con: {string}={}
	for _,x in cx do
		local key=if x==lx1 then "S1out" elseif x==lx2 then "S2out" elseif x==lx3 then "S3out" else "C"..x
		if not byName[key] then node(key,x,2503) end
		table.insert(con,key)
	end
	chain(con)
	-- shops (one browsing spot each) and the walk-through duty free
	node("news",-190,2497.5,"shop",N);node("cafe",-144,2497,"shop",N);node("tech",-90,2497.5,"shop",N)
	node("dutyW",-36,2497.5,"shop",N);node("dutyE",36,2497.5,"shop",N);node("restrooms",159,2502.5,"wait",N)
	link("C-190","news");link("C-144","cafe");link("C-90","tech");link("C-36","dutyW");link("C36","dutyE");link("C159","restrooms")
	-- lounge: doorway, reception, buffet, bar
	node("loungeDoor",a.loungeDoor.X,2502.5);node("loungeIn",-244,2501);node("reception",-246.5,2497,"lounge",N)
	node("buffet",-261.5,2498,"lounge",N);node("bar",-280,2498.6,"lounge",N)
	chain({"C-230","loungeDoor","loungeIn","reception"});chain({"loungeIn","buffet","bar"})
	-- gates: gate point (the CityPlan gate CFrame), desk front, boarding lane to the bridge door
	for i,g in a.gates do
		local gx=g.Position.X
		local k="A"..i
		node(k,gx,g.Position.Z,"gate",S)
		node(k.."desk",gx-1.9,2517.5,"gate",S)
		node(k.."lane",gx-11.4,2513);node(k.."board",gx-11.4,2528,"board",S)
		link("C"..gx,k);chain({k,k.."desk"});chain({k,k.."lane",k.."board"})
	end
	-- food court: a line along z 2500.5 (between the stall walls and the seating) with a spur to each counter
	node("F1",190,2500.5);node("F2",232,2500.5);node("F3",275,2500.5)
	node("grill",190,2498.4,"food",N);node("noodle",232,2498.4,"food",N);node("deli",275,2498.4,"food",N)
	chain({"C200","F1","F2","F3"});link("C236","F2");link("F1","grill");link("F2","noodle");link("F3","deli")
	-- arrivals: arrival point, baggage carousel, exit
	node("arrival",a.arrival.X,a.arrival.Z);node("reclaimW",257.5,2466,"reclaim",E);node("reclaimN",276,2458.5,"reclaim",S)
	chain({"L"..a.arrivalsDoor,"arrival","reclaimW"});link("arrival","reclaimN")
	a.walk={nodes=nodes,edges=edges,byName=byName,walkers=24} -- walkers: suggested crowd size in the terminal
end
City.HARBOUR={quay=3200,x1=-1150,x2=1150,z2=3800}
-- Port Meridian (world coordinates)
City.ABROAD={
	rect={x1=-700,x2=700,z1=7500,z2=8700},
	runway={x1=-650,x2=650,z1=7520,z2=7590},
	terminal={x1=-160,x2=160,z1=7610,z2=7690},height=26,
	entrances={-80,0,80}, -- door openings in the south facade (towards the city)
	checkin={Vector3.new(-70,City.GROUND,7636),Vector3.new(70,City.GROUND,7636)},
	arrival=CFrame.lookAt(Vector3.new(0,28,7655),Vector3.new(0,28,7700)), -- facing the city (south)
	plaza={x1=-200,x2=200,z1=7690,z2=7760},
	boulevard={x1=-24,x2=24,z1=7760,z2=8380},
	crossStreet={x1=-700,x2=700,z1=8056,z2=8104},
	promenade={x1=-700,x2=700,z1=8600,z2=8700},
	sea={z1=8700,z2=9100},
}

------------------------------------------------------------------------------------------------ destinations
local function faceIn(frame: CFrame,p: Vector3): CFrame return frame*CFrame.new(p)*CFrame.Angles(0,math.pi,0) end
City.DESTINATIONS={} :: {[string]: Destination}
City.DESTINATION_LIST={} :: {Destination}
local function addDestination(d: Destination)
	assert(City.DESTINATIONS[d.id]==nil,"duplicate destination "..d.id)
	City.DESTINATIONS[d.id]=d;table.insert(City.DESTINATION_LIST,d)
end
for _,b in City.BUILDINGS do
	local l=City.layout(b);local f=b.frame
	local parking: {CFrame}={}
	for _,x in l.bays do table.insert(parking,f*CFrame.new(x,2,-City.OFFICE.parkingDepth/2)*CFrame.Angles(0,math.pi,0)) end
	local client=nil
	for _,c in City.CLIENTS do if c.id==b.clientId then client=c end end
	addDestination({id=b.id,kind=if b.clientId then "client" else "hotel",name=b.name,zone=b.zone,door=faceIn(f,l.door),lobby=faceIn(f,l.lobby),
		reception=f*CFrame.new(l.reception),meeting=if l.meeting then faceIn(f,l.meeting) else nil,parking=parking,
		drive=if #parking>0 then parking[1].Position else nil,clientId=b.clientId,contract=if client then client.contract else nil,
		business=if client then client.business else nil,building=b})
end
do
	local f=City.CONVENTION.frame
	addDestination({id="convention",kind="venue",name="Convention Centre",zone="downtown",door=faceIn(f,Vector3.new(0,3.5,-6)),lobby=faceIn(f,Vector3.new(0,3.5,18)),
		parking={},drive=f:PointToWorldSpace(Vector3.new(60,0,-30))})
	addDestination({id="city_plaza",kind="landmark",name="City Plaza",zone="downtown",door=CFrame.lookAt(Vector3.new(180,27.5,1070),Vector3.new(180,27.5,1250)),
		lobby=CFrame.lookAt(Vector3.new(180,27.5,1215),Vector3.new(180,27.5,1250)),parking={},drive=v(180,1030)}) -- facing the fountain
	local a=City.AIRPORT
	addDestination({id="airport",kind="airport",name="City Airport",zone="airport",door=CFrame.lookAt(Vector3.new(0,27.5,2423),Vector3.new(0,27.5,2500)),
		lobby=CFrame.lookAt(Vector3.new(0,28,2448),Vector3.new(0,28,2500)),parking=table.clone(a.carParkBays),drive=a.carPark.Position})
	local m=City.ABROAD
	addDestination({id="intl_arrivals",kind="airport",name="Port Meridian Airport",zone="abroad",door=CFrame.lookAt(Vector3.new(0,27.5,7700),Vector3.new(0,27.5,7600)),
		lobby=m.arrival,parking={}})
	addDestination({id="promenade",kind="landmark",name="Meridian Waterfront",zone="abroad",door=CFrame.lookAt(Vector3.new(0,27.5,8620),Vector3.new(0,27.5,8700)),
		lobby=CFrame.lookAt(Vector3.new(0,27.5,8650),Vector3.new(0,27.5,8700)),parking={}})
	addDestination({id="founder_square",kind="landmark",name="Founder Square",zone="district",door=CFrame.lookAt(Vector3.new(1050,27.5,0),Vector3.new(1100,27.5,0)),
		lobby=CFrame.new(1062,27.5,10),parking={},drive=v(1060,0)})
	addDestination({id="test_grounds",kind="landmark",name="Courier Test Grounds",zone="district",door=CFrame.lookAt(Vector3.new(-1050,27.5,-130),Vector3.new(-1100,27.5,-130)),
		lobby=CFrame.new(-1070,27.5,-130),parking={},drive=v(-1060,-130)})
	addDestination({id="rival_quarter",kind="landmark",name="Rival Quarter",zone="district",door=CFrame.lookAt(Vector3.new(0,27.5,-600),Vector3.new(0,27.5,-650)),
		lobby=CFrame.new(0,27.5,-640),parking={},drive=v(0,-640)})
end
City.CITY_HOTEL=City.DESTINATIONS.city_hotel
City.INTL_HOTEL=City.DESTINATIONS.intl_hotel

function City.destination(id: any): Destination?
	if typeof(id)~="string" then return nil end
	return City.DESTINATIONS[id]
end
-- Destinations filtered by kind and/or zone (nil = any), in their fixed order.
function City.destinations(kind: string?,zone: string?): {Destination}
	local out: {Destination}={}
	for _,d in City.DESTINATION_LIST do
		if (kind==nil or d.kind==kind) and (zone==nil or d.zone==zone) then table.insert(out,d) end
	end
	return out
end
-- Client office by client id, display name (any case), contract id or business id. `refKind` ("contract" or
-- "business") disambiguates ids both lists use (e.g. "frontier": contract = Orbit Systems, business =
-- Frontier Science); without it a contract id wins.
function City.clientOffice(key: any,refKind: string?): Destination?
	if typeof(key)~="string" then return nil end
	local low=string.lower(key)
	if refKind==nil then
		local d=City.DESTINATIONS[low];if d and d.kind=="client" then return d end
		for _,c in City.DESTINATION_LIST do if c.kind=="client" and string.lower(c.name)==low then return c end end
	end
	for _,kind in {"contract","business"} do
		if refKind==nil or refKind==kind then
			for _,c in City.DESTINATION_LIST do
				if c.kind=="client" and ((kind=="contract" and c.contract==key) or (kind=="business" and c.business==key)) then return c end
			end
		end
	end
	return nil
end
function City.routeTo(from: Vector3,id: string): (Route?,string?)
	local d=City.destination(id);if not d then return nil,"BAD_INPUT" end
	return City.route(from,d.drive or d.door.Position)
end
return City
