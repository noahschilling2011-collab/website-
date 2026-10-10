--!strict
-- MetroPlan (package "metro"): Port Meridian's layout and the networks of the client-side city life.
--   * Layout (server, MetroBuilder builds the city from it): streets with sidewalks and the Meridian Boulevard
--     median, named districts, building lots (deterministic hash generator, signature towers), the landmark
--     "Meridian Spire", VIP markers (limo stand, two helipads), the business lounge, and street furniture
--     spots (benches, shop fronts, bus stops) that the walkers use as idle places.
--   * Networks (client, CityLifeController): a walk graph (sidewalk centrelines split at the corners, a zebra
--     crossing at every junction, plaza / median / promenade / park paths, idle spots on spurs, building doors
--     and the tunnel gates' pedestrian passages as portals) with every solid prop near it projected onto the
--     edges (Net.obs: the walkers step round them) and car lanes (right-hand traffic, 1-2 lanes per direction,
--     junction refs) for Port Meridian and - read-only from CityPlan.ROADS and CityPlan.DESTINATIONS - for
--     Business City. Traffic signals: one fixed cycle per junction on workspace:GetServerTimeNow(), so every
--     client shows the same phase.
--   * Street furniture / greenery positions (lamps, trees, verges, beds, bollards, carts, signs) shared by the
--     builder and the walk networks.
--   * Far skyline: low-detail shells beyond the boundary walls, clear of the road continuations, and the tunnel
--     gates at the six street ends (client-only; the server never builds them).
-- Pure data and maths (string hash, no Random); nothing here creates instances.
local City=require(script.Parent.CityPlan)
local Plan={}
local G=City.GROUND
local A=City.ABROAD

export type Rect=City.Rect
export type Road={id: string,name: string,axis: string,c: number,a1: number,a2: number,width: number,walk: number,median: number,lanes: number,gaps: {{number}}?,beyond: number?}
export type Lot={id: string,block: string,x: number,z: number,w: number,d: number,h: number,style: string,crown: string,tone: number,face: string,district: string,glow: boolean}
export type Spot={x: number,z: number,y: number,face: Vector3,kind: string}
export type Junction={id: number,x: number,z: number,rx: Road,rz: Road,phase: number}
export type JunctionRef={a: number,j: Junction,other: Road}
export type WalkNode={id: number,p: Vector3,links: {number},idle: string?,face: Vector3?,seat: Vector3?,portal: boolean?}
-- side (crossings only): which zebra of the crossed road (-1 / +1 along its axis from the junction centre, 0 = across the box)
export type WalkEdge={id: number,a: number,b: number,half: number,len: number,junction: Junction?,axis: string?,side: number?}
export type Lane={road: Road,dir: number,off: number,index: number,count: number}
-- Obstacle box in edge space (s along a->b, l = lateral offset to the right of a->b); walkers step round it.
export type EdgeObstacle={s1: number,s2: number,l1: number,l2: number}
export type Net={id: string,bounds: Rect,signals: boolean,roads: {Road},junctions: {Junction},byRoad: {[string]: {JunctionRef}},
	nodes: {WalkNode},edges: {WalkEdge},lanes: {Lane},roadY: number,obs: {[number]: {EdgeObstacle}}}
export type Far={x: number,z: number,w: number,d: number,h: number,tone: number,glass: boolean,crown: boolean}
-- Solid street furniture on the ground (flat box x1..x2, z1..z2): walk-graph obstacles.
export type Obstacle={x1: number,x2: number,z1: number,z2: number,kind: string}

Plan.NAME="Port Meridian"
Plan.RECT=A.rect
Plan.PAVE_TOP=G+.1 -- general paving over the whole city ground
Plan.PLAZA_TOP=G+.3 -- arrival plaza, tower forecourts, waterfront plazas, promenade
Plan.MEDIAN_TOP=G+.6 -- boulevard median (kerbed)
Plan.PARK_TOP=G+.2
Plan.PLINTH_TOP=G+1.6 -- Meridian Spire plinth (its lobby door)
Plan.WALK_TOP=City.WALK_TOP
Plan.ROAD_TOP=City.ROAD_TOP
Plan.SEED=20261004

function Plan.hash(s: string): number
	local h=7
	for i=1,#s do h=(h*31+string.byte(s,i))%2147483647 end
	return h
end
local hash=Plan.hash
-- Spread a hash over all its digits (neighbouring ids like "xw:0:0" / "xw:0:1" differ only in the last byte):
-- three Park-Miller rounds (products stay below 2^53: exact in doubles).
local function mix(h: number): number
	for _=1,3 do h=(h*48271)%2147483647 end
	return h
end
Plan.mix=mix

------------------------------------------------------------------------------------------------ roads
local function road(id: string,name: string,axis: string,c: number,a1: number,a2: number,width: number,walk: number,median: number,lanes: number,gaps: {{number}}?): Road
	return {id=id,name=name,axis=axis,c=c,a1=a1,a2=a2,width=width,walk=walk,median=median,lanes=lanes,gaps=gaps}
end
-- axis "x": runs along X at z = c from a1 to a2 (axis "z": along Z at x = c). width = kerb to kerb (median
-- included), walk = sidewalk width on both sides. gaps = {side, a1, a2}: sidewalk left out (lay-bys).
-- Exchange Street is CityPlan.ABROAD.crossStreet (z 8056..8104). beyond = client-only continuation past the
-- boundary walls (far road strips + traffic that enters / leaves the city), set below for the through streets.
Plan.ROADS={
	road("pm_arrivals","Arrivals Drive","x",7784,-700,700,32,8,0,1,{{-1,-200,-104},{-1,104,200}}),
	road("pm_exchange","Exchange Street","x",(A.crossStreet.z1+A.crossStreet.z2)/2,-700,700,A.crossStreet.z2-A.crossStreet.z1,10,0,2),
	road("pm_harbour","Harbour Street","x",8336,-700,700,32,8,0,1),
	road("pm_boulevard","Meridian Boulevard","z",0,7784,8336,104,12,48,2),
	road("pm_west","Westgate Avenue","z",-420,7784,8336,32,8,0,1),
	road("pm_east","Parkside Avenue","z",420,7784,8336,32,8,0,1),
} :: {Road}
for _,r in Plan.ROADS do if r.axis=="x" then r.beyond=380 end end
function Plan.road(id: string): Road?
	for _,r in Plan.ROADS do if r.id==id then return r end end
	return nil
end
-- Asphalt (or with sidewalks) rectangle of a road.
function Plan.roadRect(r: Road,withWalk: boolean?): Rect
	local h=r.width/2+(if withWalk then r.walk else 0)
	if r.axis=="x" then return {x1=r.a1,x2=r.a2,z1=r.c-h,z2=r.c+h} end
	return {x1=r.c-h,x2=r.c+h,z1=r.a1,z2=r.a2}
end
-- Distance from a road's centre line to its sidewalk centre line (kerb + 1.5 without sidewalks).
local function walkOff(r: Road): number return r.width/2+(if r.walk>0 then r.walk/2 else 1.5) end
Plan.walkOff=walkOff
-- Does road r continue past coordinate `at` (along its axis) towards side (+1 larger, -1 smaller)?
local function extends(r: Road,at: number,side: number): boolean
	if side>0 then return r.a2>at+1 end
	return r.a1<at-1
end
Plan.extends=extends
-- Median strip of the boulevard: from just south of Arrivals Drive to Harbour Street, interrupted at Exchange.
Plan.MEDIAN={
	{x1=-24,x2=24,z1=7801,z2=8052},
	{x1=-24,x2=24,z1=8108,z2=8319},
} :: {Rect}

------------------------------------------------------------------------------------------------ districts
Plan.DISTRICTS={
	{id="arrivals",name="Airport District",x1=-700,x2=700,z1=7500,z2=7760},
	{id="financial",name="Meridian Financial District",x1=-396,x2=396,z1=7760,z2=8360},
	{id="exchange",name="Exchange Quarter",x1=-700,x2=-396,z1=7760,z2=8360},
	{id="parkside",name="Parkside",x1=396,x2=700,z1=7760,z2=8360},
	{id="harbour",name="Harbour Quarter",x1=-700,x2=700,z1=8360,z2=8700},
}
function Plan.districtAt(x: number,z: number): string?
	for _,d in Plan.DISTRICTS do if x>=d.x1 and x<=d.x2 and z>=d.z1 and z<=d.z2 then return d.name end end
	return nil
end

------------------------------------------------------------------------------------------------ landmarks + VIP
-- The landmark supertower on the boulevard axis behind the Meridian Grand Hotel (footprint x -28..28,
-- z 8520..8576), Persistent on the server so it shows from everywhere in the city.
Plan.LANDMARK={name="Meridian Spire",x=0,z=8548,size=56,height=468,mast=74}
-- Helipads (marker parts "Helipad", attribute Purpose). cf = centre of the landing surface (top face).
-- The hotel roof (CityBuilder.building: roof top = GROUND + 126.2) gets a 1-stud deck; the airport pad stands
-- east of the arrival terminal.
local HOTEL=City.building("intl_hotel")
local HOTEL_ROOF=G+17+((if HOTEL then HOTEL.floors else 10)-1)*12+1.2
Plan.HOTEL_ROOF=HOTEL_ROOF
Plan.HELIPADS={
	hotel={id="pm_hotel",purpose="VIP",cf=CFrame.new(0,HOTEL_ROOF+1,8408),size=40,name="Meridian Grand Hotel roof"},
	airport={id="pm_airport",purpose="VIPAirport",cf=CFrame.new(310,G+1,7648),size=44,name="Port Meridian Airport VIP helipad"},
}
-- VIP limousine stand: lay-by on the north kerb of Arrivals Drive, right of the terminal exits. stand = bay 1
-- (kept free for the chauffeur service), bay2 holds a waiting (decorative) limousine. Cars face west.
Plan.VIP_LIMO={
	stand=CFrame.lookAt(Vector3.new(176,City.ROAD_TOP,7762),Vector3.new(160,City.ROAD_TOP,7762)),
	bay2=CFrame.lookAt(Vector3.new(128,City.ROAD_TOP,7762),Vector3.new(112,City.ROAD_TOP,7762)),
	layby={x1=104,x2=200,z1=7756,z2=7768},
}
Plan.TAXI_RANK={x1=-200,x2=-104,z1=7756,z2=7768}
-- Business lounge in the west end of the arrival terminal (partition at x = -104 with a door gap).
Plan.LOUNGE={x1=-158.5,x2=-104,z1=A.terminal.z1+.8,z2=A.terminal.z2-.8,doorZ1=7644,doorZ2=7656}
-- Observation wheel at the east end of the waterfront.
Plan.WHEEL={x=540,z=8556,radius=52,hub=G+62}

------------------------------------------------------------------------------------------------ furniture spots
-- Spots are shared by the builder (bench / shelter / shop front) and the walk graph (idle node on a spur).
-- y = surface height under the spot; face = the direction a person there looks.
local benches: {Spot}={}
local shops: {Spot}={}
local stops: {Spot}={}
local views: {Spot}={}
local function spot(list: {Spot},x: number,z: number,y: number,face: Vector3,kind: string) table.insert(list,{x=x,z=z,y=y,face=face,kind=kind}) end
local N,S,E,W=Vector3.new(0,0,-1),Vector3.new(0,0,1),Vector3.new(1,0,0),Vector3.new(-1,0,0)
-- promenade: benches north of the walk facing the water, and on the quay with their backs to the water
for x=-650,650,100 do spot(benches,x,8630,Plan.PLAZA_TOP,S,"bench") end
for x=-600,600,150 do spot(benches,x+40,8696,Plan.PLAZA_TOP,N,"bench") end
-- boulevard median (between the two median paths, facing the walks; clear of the fountains at z 7880 / 8000 /
-- 8210 (radius 10), the globe plinth (z 7936..7944) and the reflecting pool (z 8250..8302))
Plan.FOUNTAINS={7880,8000,8210}
for _,z in {7850,7972,8150,8236} do spot(benches,-6,z,Plan.MEDIAN_TOP,W,"bench");spot(benches,6,z,Plan.MEDIAN_TOP,E,"bench") end
-- arrival plaza
for _,x in {-150,-60,60,150} do spot(benches,x,7716,Plan.PLAZA_TOP,S,"bench") end
-- park around the pond
for _,p in {{575,7870,S},{575,7990,N},{515,7930,E},{635,7930,W}} :: {{any}} do spot(benches,p[1],p[2],Plan.PARK_TOP,p[3],"bench") end
-- spire plaza (south of the plaza walk z 8590)
for _,x in {-60,60} do spot(benches,x,8600,Plan.PLAZA_TOP,N,"bench") end
-- harbour walk: planting beds between the corridors (z 8566..8582) with bench pairs on their south edge facing the
-- sea; the harbour walk path runs along z 8590 (MetroBuilder builds beds, trees and benches from these lists)
Plan.CORRIDORS={-560,-300,-110,110,300,580} -- walkways from Harbour Street down to the promenade (x at the promenade)
Plan.BEDS={} :: {Rect}
for _,s in {{-690,-568},{-552,-308},{-292,-118},{118,292},{308,500},{596,690}} do
	table.insert(Plan.BEDS,{x1=s[1],x2=s[2],z1=8566,z2=8582})
	local mid=(s[1]+s[2])/2
	for _,dx in {-7,7} do spot(benches,mid+dx,8585,Plan.PLAZA_TOP,S,"bench") end
end
-- pavilion shop fronts along the boulevard sidewalks (pavilion fronts at x = +-66 face the boulevard)
Plan.PAVILIONS={} :: {{x1: number,x2: number,z1: number,z2: number,side: number,name: string}}
local PAVILION_NAMES={"CAFÉ MERIDIAN","FLOWERS & GIFTS","BOOKS · COFFEE","GELATO BAR","NEWS · TRAVEL","PASTRY HOUSE","CITY PHARMACY","TEA ROOM"}
do
	local k=0
	for _,zr in {{7814,7906},{7954,8040},{8120,8206},{8254,8306}} do
		for _,side in {-1,1} do
			k+=1
			local x1,x2=if side<0 then -96 else 66,if side<0 then -66 else 96
			table.insert(Plan.PAVILIONS,{x1=x1,x2=x2,z1=zr[1],z2=zr[2],side=side,name=PAVILION_NAMES[(k-1)%#PAVILION_NAMES+1]})
			for _,f in {.3,.7} do spot(shops,side*63,zr[1]+(zr[2]-zr[1])*f,City.WALK_TOP,Vector3.new(side,0,0),"shop") end
		end
	end
end
-- bus stops (shelter on the back edge of the sidewalk, people stand on the sidewalk line facing the road)
Plan.BUS_STOPS={
	{x=-300,z=7806.5,stand=7804,face=N,line="1 · Harbour Quarter"},
	{x=300,z=8047.5,stand=8051,face=S,line="2 · Airport"},
	{x=-300,z=8112.5,stand=8109,face=N,line="3 · Exchange Quarter"},
	{x=340,z=8358.5,stand=8356,face=N,line="1 · Airport"}, -- east of the x = 300 walkway
} :: {{x: number,z: number,stand: number,face: Vector3,line: string}}
for _,b in Plan.BUS_STOPS do spot(stops,b.x,b.stand,City.WALK_TOP,b.face,"bus") end
-- view points: fountains on the median, the spire, the wheel, the quay
for _,z in Plan.FOUNTAINS do spot(views,-15,z,Plan.MEDIAN_TOP,E,"view");spot(views,15,z,Plan.MEDIAN_TOP,W,"view") end
spot(views,574,8604,Plan.PLAZA_TOP,Vector3.new(-34,0,-48).Unit,"view") -- the Harbour Wheel
spot(views,286,7686,Plan.PLAZA_TOP,Vector3.new(24,0,-38).Unit,"view") -- helipad gate
Plan.BENCHES=benches
Plan.SHOPS=shops
Plan.STOPS=stops
Plan.VIEWS=views

------------------------------------------------------------------------------------------------ building lots
-- Blocks between the streets (6+ studs from every sidewalk). profile -> lot size, gap and height range.
-- Heights: the financial core rises to 180-340 (the four signature towers 350-380), Exchange Quarter / Parkside
-- 110-240, the bay front 120-280 with pointed crowns; the Meridian Spire (468 + crown + mast) stays the summit.
type Profile={target: number,gap: number,h1: number,h2: number,styles: {string},crowns: {string}?}
local PROFILES: {[string]: Profile}={
	core={target=72,gap=16,h1=220,h2=340,styles={"glass","glass","slab","stepped","stone","glass","slab","stone"}},
	mid={target=68,gap=16,h1=110,h2=240,styles={"stone","glass","res","stepped","stone","res"}},
	harbour={target=62,gap=14,h1=120,h2=280,styles={"res","res","glass","drum","stone","res"},crowns={"spire","pyramid","slant","band","spire","plant","pyramid"}},
	airport={target=90,gap=20,h1=26,h2=66,styles={"low","low","glass","low"}},
}
local function towerRect(id: string,pad: number): Rect
	local b=City.building(id);assert(b,id)
	local r: Rect={x1=math.huge,x2=-math.huge,z1=math.huge,z2=-math.huge}
	for _,c in {Vector3.new(-b.width/2,0,-City.OFFICE.parkingDepth),Vector3.new(b.width/2,0,-City.OFFICE.parkingDepth),Vector3.new(-b.width/2,0,b.depth),Vector3.new(b.width/2,0,b.depth)} do
		local w=b.frame:PointToWorldSpace(c)
		r.x1,r.x2,r.z1,r.z2=math.min(r.x1,w.X),math.max(r.x2,w.X),math.min(r.z1,w.Z),math.max(r.z2,w.Z)
	end
	return {x1=r.x1-pad,x2=r.x2+pad,z1=r.z1-pad,z2=r.z2+pad}
end
Plan.towerRect=towerRect
-- id, district, rect, profile
local BLOCKS: {{any}}={
	{"nw","financial",{x1=-390,x2=-104,z1=7814,z2=8040},"core"},
	{"ne","financial",{x1=104,x2=390,z1=7814,z2=8040},"core"},
	{"sw","financial",{x1=-390,x2=-104,z1=8120,z2=8306},"core"},
	{"se","financial",{x1=104,x2=390,z1=8120,z2=8306},"core"},
	{"xw","exchange",{x1=-694,x2=-450,z1=7814,z2=8040},"mid"},
	{"xs","exchange",{x1=-694,x2=-450,z1=8120,z2=8306},"mid"},
	{"ps","parkside",{x1=450,x2=694,z1=8120,z2=8306},"mid"},
	{"aw","arrivals",{x1=-694,x2=-214,z1=7612,z2=7716},"airport"},
	{"ae","arrivals",{x1=384,x2=694,z1=7612,z2=7716},"airport"},
	{"h1","harbour",{x1=-694,x2=-574,z1=8366,z2=8500},"harbour"},
	{"h2","harbour",{x1=-546,x2=-314,z1=8366,z2=8500},"harbour"},
	{"h3","harbour",{x1=-286,x2=-124,z1=8366,z2=8500},"harbour"},
	{"h4","harbour",{x1=124,x2=286,z1=8366,z2=8500},"harbour"},
	{"h5","harbour",{x1=314,x2=546,z1=8366,z2=8500},"harbour"},
	{"h6","harbour",{x1=574,x2=694,z1=8366,z2=8470},"harbour"},
}
local RESERVED: {Rect}={
	towerRect("helixresearch",6),towerRect("orbitsystems",6),towerRect("novainfrastructure",6),towerRect("frontierscience",6),
	{x1=-102,x2=102,z1=7760,z2=8360}, -- boulevard, pavilions, tower approaches
}
local function overlaps(a: Rect,b: Rect): boolean return a.x1<b.x2 and a.x2>b.x1 and a.z1<b.z2 and a.z2>b.z1 end
Plan.overlaps=overlaps
-- Cut lot `r` so it no longer overlaps `o`: keep the largest remaining side (nil if all sides are too small).
local function cut(r: Rect,o: Rect,minSize: number): Rect?
	if not overlaps(r,o) then return r end
	local best: Rect?=nil;local bestA=0
	for _,c in {{x1=r.x1,x2=math.min(r.x2,o.x1),z1=r.z1,z2=r.z2},{x1=math.max(r.x1,o.x2),x2=r.x2,z1=r.z1,z2=r.z2},
		{x1=r.x1,x2=r.x2,z1=r.z1,z2=math.min(r.z2,o.z1)},{x1=r.x1,x2=r.x2,z1=math.max(r.z1,o.z2),z2=r.z2}} :: {Rect} do
		local w,d=c.x2-c.x1,c.z2-c.z1
		if w>=minSize and d>=minSize and w*d>bestA then best,bestA=c,w*d end
	end
	return best
end
local CROWNS={"flat","plant","spire","slant","band","plant","pyramid","band"}
local function makeLots(): {Lot}
	local out: {Lot}={}
	for _,b in BLOCKS do
		local id: string,district: string,r: Rect,pf: Profile=b[1],b[2],b[3],PROFILES[b[4]]
		local W,D=r.x2-r.x1,r.z2-r.z1
		local nx=math.max(1,math.floor((W+pf.gap)/(pf.target+pf.gap)+.5))
		local nz=math.max(1,math.floor((D+pf.gap)/(pf.target+pf.gap)+.5))
		local lw,ld=(W-(nx-1)*pf.gap)/nx,(D-(nz-1)*pf.gap)/nz
		local n=0
		for i=0,nx-1 do
			for j=0,nz-1 do
				local h=mix(hash(id..":"..i..":"..j))
				-- shrink on the sides that do not touch the block edge (street fronts stay aligned)
				local sx1=if i>0 then (h%7) else 0;local sx2=if i<nx-1 then (math.floor(h/7)%7) else 0
				local sz1=if j>0 then (math.floor(h/49)%7) else 0;local sz2=if j<nz-1 then (math.floor(h/343)%7) else 0
				local lot: Rect?={x1=r.x1+i*(lw+pf.gap)+sx1,x2=r.x1+i*(lw+pf.gap)+lw-sx2,z1=r.z1+j*(ld+pf.gap)+sz1,z2=r.z1+j*(ld+pf.gap)+ld-sz2}
				for _,o in RESERVED do
					local l=lot;if l then lot=cut(l,o,34) end
				end
				local l=lot
				if l then
					n+=1
					local w,d=l.x2-l.x1,l.z2-l.z1
					local hgt=pf.h1+(math.floor(h/2401)%1000)/999*(pf.h2-pf.h1)
					-- the towers nearest the boulevard and Exchange Street are the tallest
					if b[4]=="core" then
						local cx,cz=(l.x1+l.x2)/2,(l.z1+l.z2)/2
						hgt*=1-.2*math.clamp((math.abs(cx)-110)/280,0,1)*(.6+.4*math.clamp(math.abs(cz-8080)/240,0,1))
					end
					hgt=math.floor(math.max(pf.h1*.8,hgt)/2)*2
					local faces: {{any}}={{"n",l.z1-r.z1},{"s",r.z2-l.z2},{"w",l.x1-r.x1},{"e",r.x2-l.x2}}
					table.sort(faces,function(p,q) return p[2]<q[2] end)
					local crowns=pf.crowns or CROWNS
					table.insert(out,{id=id.."_"..n,block=id,x=(l.x1+l.x2)/2,z=(l.z1+l.z2)/2,w=w,d=d,h=hgt,
						style=pf.styles[(math.floor(h/13)%#pf.styles)+1],crown=crowns[(math.floor(h/17)%#crowns)+1],
						tone=math.floor(h/19)%6+1,face=faces[1][1],district=district,glow=(math.floor(h/23)%3)~=0})
				end
			end
		end
	end
	-- signature towers: the tallest lot of each financial block gets a distinctive silhouette
	local sig: {[string]: {string}}={nw={"drum","spire"},ne={"twist","band"},sw={"stepped","spire"},se={"slab","spire"}}
	for blk,def in sig do
		local best: Lot?=nil
		for _,l in out do if l.block==blk and (best==nil or l.w*l.d>best.w*best.d) then best=l end end
		if best then best.style=def[1];best.crown=def[2];best.h=math.max(best.h,if blk=="ne" then 380 else 350);best.glow=true end
	end
	return out
end
Plan.LOTS=makeLots()
-- Green verges: lawn strips in the gaps between neighbouring lots of a block (nominal grid gaps, which the lots
-- never enter), split where column and row gaps cross so no two lawns overlap.
Plan.VERGES={} :: {Rect}
do
	for _,b in BLOCKS do
		local r: Rect,pf: Profile=b[3],PROFILES[b[4]]
		if b[4]~="airport" then
			local W,D=r.x2-r.x1,r.z2-r.z1
			local nx=math.max(1,math.floor((W+pf.gap)/(pf.target+pf.gap)+.5))
			local nz=math.max(1,math.floor((D+pf.gap)/(pf.target+pf.gap)+.5))
			local lw,ld=(W-(nx-1)*pf.gap)/nx,(D-(nz-1)*pf.gap)/nz
			local function add(q: Rect)
				for _,o in RESERVED do if overlaps(q,o) then return end end
				if q.x2-q.x1>=6 and q.z2-q.z1>=6 then table.insert(Plan.VERGES,q) end
			end
			-- column gaps (full block depth) and row gaps (inside each column)
			for i=1,nx-1 do local x=r.x1+i*(lw+pf.gap);add({x1=x-pf.gap+2,x2=x-2,z1=r.z1+2,z2=r.z2-2}) end
			for j=1,nz-1 do
				local z=r.z1+j*(ld+pf.gap)
				for i=0,nx-1 do add({x1=r.x1+i*(lw+pf.gap)+2,x2=r.x1+i*(lw+pf.gap)+lw-2,z1=z-pf.gap+2,z2=z-2}) end
			end
		end
	end
end

------------------------------------------------------------------------------------------------ street ends
-- Every through street (beyond > 0) leaves the city through a tunnel portal: a gate building at the boundary
-- wall (x = r.a1 / r.a2) spanning the street, piers over the sidewalks, the mouth over the asphalt, and a dark
-- tube out to the end of the client lane - traffic enters and leaves the city there, the sidewalks end at the
-- piers (no invisible wall mid-street).
export type Tunnel={road: Road,side: number,x: number,z1: number,z2: number,depth: number,height: number,mouth: number,length: number}
Plan.TUNNELS={} :: {Tunnel}
for _,r in Plan.ROADS do
	local ext=r.beyond
	if ext and r.axis=="x" then
		for _,side in {-1,1} do
			local hw=r.width/2+r.walk+22
			table.insert(Plan.TUNNELS,{road=r,side=side,x=if side<0 then r.a1 else r.a2,z1=r.c-hw,z2=r.c+hw,depth=40,height=38,mouth=18,length=ext})
		end
	end
end
-- Ground footprints the far skyline keeps clear of: the client road strips (+ sidewalks + 6) and the gate buildings.
Plan.FAR_CLEAR={} :: {Rect}
for _,t in Plan.TUNNELS do
	local r=t.road
	local hw=r.width/2+r.walk+6
	local xa,xb=t.x,t.x+t.side*(t.length+60)
	table.insert(Plan.FAR_CLEAR,{x1=math.min(xa,xb),x2=math.max(xa,xb),z1=r.c-hw,z2=r.c+hw})
	local ga,gb=t.x,t.x+t.side*(t.depth+12)
	table.insert(Plan.FAR_CLEAR,{x1=math.min(ga,gb),x2=math.max(ga,gb),z1=t.z1-6,z2=t.z2+6})
end

------------------------------------------------------------------------------------------------ far skyline
-- Low shells beyond the boundary walls (west, east, north beyond the runway, and the far shore across the bay):
-- built by the client only while the camera is near Port Meridian. Heights fall off with the distance from the
-- walls; nothing stands on the road continuations or the gate buildings (FAR_CLEAR). Deterministic.
local function makeFar(): {Far}
	local out: {Far}={}
	local function band(tag: string,x1: number,x2: number,z1: number,z2: number,pitch: number,hNear: number,hFar: number,near: (number,number)->number)
		local nx,nz=math.floor((x2-x1)/pitch),math.floor((z2-z1)/pitch)
		for i=0,nx-1 do
			for j=0,nz-1 do
				local h=mix(hash(tag..i..":"..j))
				if h%7~=0 then
					local cx=x1+(i+.5)*pitch+((h%21)-10);local cz=z1+(j+.5)*pitch+((math.floor(h/21)%21)-10)
					local t=math.clamp(near(cx,cz),0,1)
					local w=pitch*(.42+(math.floor(h/441)%30)/100);local d=pitch*(.42+(math.floor(h/13230)%30)/100)
					local hh=(hFar+(hNear-hFar)*t)*(.45+(math.floor(h/397)%55)/100)
					local foot: Rect={x1=cx-w/2,x2=cx+w/2,z1=cz-d/2,z2=cz+d/2}
					local clear=true
					for _,c in Plan.FAR_CLEAR do if overlaps(foot,c) then clear=false;break end end
					if clear then table.insert(out,{x=cx,z=cz,w=w,d=d,h=math.floor(hh),tone=h%6+1,glass=h%3==0,crown=hh>140 and h%2==0}) end
				end
			end
		end
	end
	local R=A.rect
	band("w",-1780,R.x1-40,R.z1-120,8660,120,260,70,function(x: number,_z: number) return 1-(R.x1-40-x)/900 end)
	band("e",R.x2+40,1780,R.z1-120,8660,120,260,70,function(x: number,_z: number) return 1-(x-R.x2-40)/900 end)
	band("n",-1780,1780,6900,R.z1-20,130,150,40,function(x: number,z: number) return (1-math.abs(x)/1900)*(1-(R.z1-z)/700) end)
	band("s",-1800,1800,9260,9700,125,280,90,function(x: number,_z: number) return 1-math.abs(x)/1900 end)
	return out
end
Plan.FAR=makeFar()
-- Ground under the far skyline (client) and where the sea reaches (server: the Sea parts of MetroBuilder).
Plan.FAR_GROUND={
	{x1=-1800,x2=A.rect.x1-4,z1=6880,z2=8700},
	{x1=A.rect.x2+4,x2=1800,z1=6880,z2=8700},
	{x1=A.rect.x1-4,x2=A.rect.x2+4,z1=6880,z2=A.rect.z1},
	{x1=-1820,x2=1820,z1=9200,z2=9760},
} :: {Rect}
Plan.SEA={x1=-1820,x2=1820,z1=A.promenade.z2+4,z2=9200}

------------------------------------------------------------------------------------------------ signals
Plan.CYCLE=28
Plan.GREEN=11.5 -- axis x green [0, 11.5), all red 2.5 s, axis z green [14, 25.5), all red 2.5 s
Plan.CLEAR=2.5
-- Seconds of green left for traffic on roads along `axis` at junction j (0 = red / all red).
function Plan.greenLeft(j: Junction,axis: string,t: number): number
	local u=(t+j.phase)%Plan.CYCLE
	local s=if axis=="x" then 0 else Plan.GREEN+Plan.CLEAR
	if u>=s and u<s+Plan.GREEN then return s+Plan.GREEN-u end
	return 0
end
function Plan.green(j: Junction,axis: string,t: number): boolean return Plan.greenLeft(j,axis,t)>0 end
-- Pedestrians crossing a road along `crossedAxis` walk while the other axis has green.
function Plan.walkLeft(j: Junction,crossedAxis: string,t: number): number
	return Plan.greenLeft(j,if crossedAxis=="x" then "z" else "x",t)
end

------------------------------------------------------------------------------------------------ networks
type Builder={nodes: {WalkNode},edges: {WalkEdge},keys: {[string]: number}}
local function keyOf(x: number,z: number): string return math.floor(x*4+.5)..":"..math.floor(z*4+.5) end
local function addNode(B: Builder,x: number,z: number,y: number): number
	local k=keyOf(x,z)
	local old=B.keys[k]
	if old then return old end
	local id=#B.nodes+1
	B.nodes[id]={id=id,p=Vector3.new(x,y,z),links={}}
	B.keys[k]=id
	return id
end
local function addEdge(B: Builder,a: number,b: number,half: number,j: Junction?,axis: string?): WalkEdge?
	if a==b then return nil end
	for _,eid in B.nodes[a].links do
		local e=B.edges[eid]
		if (e.a==a and e.b==b) or (e.a==b and e.b==a) then return e end
	end
	local pa,pb=B.nodes[a].p,B.nodes[b].p
	local side: number?=nil
	if j and axis then
		local m=if axis=="x" then (pa.X+pb.X)/2-j.x else (pa.Z+pb.Z)/2-j.z
		side=if m>1 then 1 elseif m< -1 then -1 else 0
	end
	local e: WalkEdge={id=#B.edges+1,a=a,b=b,half=half,len=math.max(.1,(Vector3.new(pb.X,0,pb.Z)-Vector3.new(pa.X,0,pa.Z)).Magnitude),junction=j,axis=axis,side=side}
	B.edges[e.id]=e
	table.insert(B.nodes[a].links,e.id);table.insert(B.nodes[b].links,e.id)
	return e
end
-- Split edge e at the node n (n already exists, lies on e).
local function splitAt(B: Builder,e: WalkEdge,n: number)
	local b=e.b
	local pa,pn,pb=B.nodes[e.a].p,B.nodes[n].p,B.nodes[b].p
	e.b=n;e.len=math.max(.1,(Vector3.new(pn.X,0,pn.Z)-Vector3.new(pa.X,0,pa.Z)).Magnitude)
	local links=B.nodes[b].links
	local idx=table.find(links,e.id);if idx then table.remove(links,idx) end
	table.insert(B.nodes[n].links,e.id)
	local e2: WalkEdge={id=#B.edges+1,a=n,b=b,half=e.half,len=math.max(.1,(Vector3.new(pb.X,0,pb.Z)-Vector3.new(pn.X,0,pn.Z)).Magnitude),junction=e.junction,axis=e.axis,side=e.side}
	B.edges[e2.id]=e2
	table.insert(B.nodes[n].links,e2.id);table.insert(links,e2.id)
end
local function flatDist(a: Vector3,b: Vector3): number return math.sqrt((a.X-b.X)^2+(a.Z-b.Z)^2) end
-- Nearest plain (non-crossing) edge to (x, z) within maxD that does not touch node `skip`: edge, t, distance.
local function nearestEdge(B: Builder,x: number,z: number,maxD: number,skip: number?): (WalkEdge?,number,number)
	local best: WalkEdge?=nil;local bestD=maxD;local bestT=0
	for _,e in B.edges do
		if not e.junction and e.a~=skip and e.b~=skip then
			local pa,pb=B.nodes[e.a].p,B.nodes[e.b].p
			local dx,dz=pb.X-pa.X,pb.Z-pa.Z;local l2=dx*dx+dz*dz
			local t=if l2>0 then math.clamp(((x-pa.X)*dx+(z-pa.Z)*dz)/l2,0,1) else 0
			local d=math.sqrt((x-(pa.X+dx*t))^2+(z-(pa.Z+dz*t))^2)
			if d<bestD then best,bestD,bestT=e,d,t end
		end
	end
	return best,bestT,bestD
end
-- Node on edge e at parameter t: an endpoint within 1.5 studs, else a new node splitting e.
local function nodeOn(B: Builder,e: WalkEdge,t: number): number
	local pa,pb=B.nodes[e.a].p,B.nodes[e.b].p
	local q=pa:Lerp(pb,t)
	if flatDist(q,pa)<1.5 then return e.a end
	if flatDist(q,pb)<1.5 then return e.b end
	local k=keyOf(q.X,q.Z)
	local old=B.keys[k]
	if old then return old end
	local n=addNode(B,q.X,q.Z,q.Y)
	splitAt(B,e,n)
	return n
end
-- Path endpoint: an existing node at p, else the nearest plain edge within maxD is split there.
local function attach(B: Builder,x: number,z: number,maxD: number): number?
	local k=B.keys[keyOf(x,z)];if k then return k end
	local e,t=nearestEdge(B,x,z,maxD,nil)
	if not e then return nil end
	return nodeOn(B,e,t)
end
-- Joins an unlinked node n (idle spot, portal) to the graph: spliced into an edge it lies on, else a spur.
local function hang(B: Builder,n: number,maxD: number,half: number)
	if #B.nodes[n].links>0 then return end
	local p=B.nodes[n].p
	local e,t,d=nearestEdge(B,p.X,p.Z,maxD,n)
	if not e then return end
	if d<.75 then
		local pa,pb=B.nodes[e.a].p,B.nodes[e.b].p
		if flatDist(p,pa)>=.5 and flatDist(p,pb)>=.5 then splitAt(B,e,n);return end
	end
	local hub=nodeOn(B,e,t)
	if hub~=n then addEdge(B,n,hub,half) end
end
-- World point of road coordinate `a` at signed offset `off` from the centre line.
local function at(r: Road,a: number,off: number): (number,number)
	if r.axis=="x" then return a,r.c+off end
	return r.c+off,a
end
local function findJunctions(roads: {Road}): ({Junction},{[string]: {JunctionRef}})
	local js: {Junction}={};local by: {[string]: {JunctionRef}}={}
	for _,r in roads do by[r.id]={} end
	for _,rx in roads do
		if rx.axis=="x" then
			for _,rz in roads do
				if rz.axis=="z" and rz.c>=rx.a1-1 and rz.c<=rx.a2+1 and rx.c>=rz.a1-1 and rx.c<=rz.a2+1 then
					local j: Junction={id=#js+1,x=rz.c,z=rx.c,rx=rx,rz=rz,phase=hash("sig"..math.floor(rz.c)..":"..math.floor(rx.c))%Plan.CYCLE}
					table.insert(js,j)
					table.insert(by[rx.id],{a=rz.c,j=j,other=rz});table.insert(by[rz.id],{a=rx.c,j=j,other=rx})
				end
			end
		end
	end
	for _,list in by do table.sort(list,function(p,q) return p.a<q.a end) end
	return js,by
end
-- Is sidewalk coordinate a on road r side s inside one of the road's lay-by gaps?
local function inGap(r: Road,s: number,a1: number,a2: number): boolean
	local gs=r.gaps;if not gs then return false end
	for _,g in gs do if g[1]==s and a1<g[3]-.5 and a2>g[2]+.5 then return true end end
	return false
end
-- One sidewalk line: plain segments between corners, zebra crossings across the other roads, lay-by gaps.
local function sidewalk(B: Builder,r: Road,s: number,refs: {JunctionRef},y: number)
	local off=s*walkOff(r);local half=math.max(1,r.walk/2-1.6)
	-- through streets: the sidewalk ends 2.5 studs before the tunnel gate's pier (a door portal there)
	local endPad=if r.beyond then 2.5 else 0
	local cur=r.a1+endPad
	local function plain(a1: number,a2: number)
		if a2<=a1+.5 then return end
		-- split around lay-by gaps
		local cuts: {number}={a1,a2}
		local gaps: {{number}}=r.gaps or {}
		for _,g in gaps do if g[1]==s then table.insert(cuts,g[2]);table.insert(cuts,g[3]) end end
		table.sort(cuts)
		for i=1,#cuts-1 do
			local p,q=math.max(a1,cuts[i]),math.min(a2,cuts[i+1])
			if q>p+.5 and not inGap(r,s,p,q) then
				local x1,z1=at(r,p,off);local x2,z2=at(r,q,off)
				addEdge(B,addNode(B,x1,z1,y),addNode(B,x2,z2,y),half)
			end
		end
	end
	for _,ref in refs do
		local o=ref.other
		local pre,post=ref.a-walkOff(o),ref.a+walkOff(o)
		plain(cur,math.min(pre,r.a2))
		if extends(o,r.c,s) then
			-- zebra across o (split at o's median)
			local pts: {number}={pre}
			if o.median>0 then table.insert(pts,ref.a-o.median/2);table.insert(pts,ref.a+o.median/2) end
			table.insert(pts,post)
			for i=1,#pts-1 do
				local x1,z1=at(r,pts[i],off);local x2,z2=at(r,pts[i+1],off)
				local isMedian=o.median>0 and i==2
				local ya=if o.median>0 and i>=2 then Plan.MEDIAN_TOP else y
				local yb=if o.median>0 and i<=2 then Plan.MEDIAN_TOP else y
				if isMedian then addEdge(B,addNode(B,x1,z1,ya),addNode(B,x2,z2,yb),3)
				else addEdge(B,addNode(B,x1,z1,ya),addNode(B,x2,z2,yb),2.5,ref.j,o.axis) end
			end
		elseif extends(r,ref.a,-1) and extends(r,ref.a,1) then
			plain(pre,post)
		end
		cur=math.max(cur,post)
	end
	plain(cur,r.a2-endPad)
end
export type Path={pts: {Vector3},half: number,cross: {[number]: string}?}
local function newBuilder(): Builder return {nodes={},edges={},keys={}} end
-- Builds a network: roads (sidewalks with walk > 0 + lanes), extra paths (polylines; endpoints and interior
-- points snap to the graph within 14 studs; cross[i] = road id makes segment i a signalled crossing of that
-- road at its nearest junction), spots (idle nodes on spurs), portals (doors, despawn/spawn points), obstacles
-- (street furniture: projected onto every edge they come near, see EdgeObstacle).
local function build(id: string,bounds: Rect,signals: boolean,roads: {Road},paths: {Path},spots: {Spot},portals: {{any}},obstacles: {Obstacle}): Net
	local B=newBuilder()
	local js,by=findJunctions(roads)
	for _,r in roads do
		if r.walk>0 then for _,s in {-1,1} do sidewalk(B,r,s,by[r.id],City.WALK_TOP) end end
	end
	for _,path in paths do
		local ids: {number}={}
		for i,p in path.pts do
			local n=if i==1 or i==#path.pts then attach(B,p.X,p.Z,14) else nil
			table.insert(ids,n or addNode(B,p.X,p.Z,p.Y))
		end
		for i=1,#ids-1 do
			local rid=path.cross and path.cross[i]
			local j: Junction?=nil;local axis: string?=nil
			if rid then
				local mid=(path.pts[i]+path.pts[i+1])/2;local bestD=math.huge
				local refs: {JunctionRef}=by[rid] or {}
				for _,ref in refs do
					local d=flatDist(Vector3.new(ref.j.x,0,ref.j.z),mid)
					if d<bestD then bestD,j=d,ref.j end
				end
				for _,r in roads do if r.id==rid then axis=r.axis end end
			end
			addEdge(B,ids[i],ids[i+1],if rid then 2.5 else path.half,j,axis)
		end
	end
	for _,sp in spots do
		local n=addNode(B,sp.x,sp.z,sp.y)
		local node=B.nodes[n];node.idle=sp.kind;node.face=sp.face
		if sp.kind=="bench" then node.seat=Vector3.new(sp.x,sp.y,sp.z)-sp.face*1.6 end
		hang(B,n,16,.6)
	end
	for _,pt in portals do
		local p: Vector3=pt[1]
		local n=addNode(B,p.X,p.Z,p.Y)
		local node=B.nodes[n];node.portal=true;node.face=pt[2]
		hang(B,n,60,1)
	end
	-- prune zebra crossings that only lead to a dead end (e.g. across a ring road with no sidewalk beyond)
	local removed: {[number]: boolean}={}
	local changed=true
	while changed do
		changed=false
		for _,node in B.nodes do
			if #node.links==1 and not node.portal and not node.idle then
				local e=B.edges[node.links[1]]
				if e.junction and not removed[e.id] then
					removed[e.id]=true;changed=true
					for _,nid in {e.a,e.b} do
						local ls=B.nodes[nid].links;local i=table.find(ls,e.id);if i then table.remove(ls,i) end
					end
				end
			end
		end
	end
	-- compact: drop the pruned edges and the nodes left without links, renumber
	local nodes: {WalkNode}={};local edges: {WalkEdge}={};local remap: {[number]: number}={}
	for _,node in B.nodes do
		if #node.links>0 then
			local nn: WalkNode={id=#nodes+1,p=node.p,links={},idle=node.idle,face=node.face,seat=node.seat,portal=node.portal}
			nodes[nn.id]=nn;remap[node.id]=nn.id
		end
	end
	for _,e in B.edges do
		if not removed[e.id] and remap[e.a] and remap[e.b] then
			local ne: WalkEdge={id=#edges+1,a=remap[e.a],b=remap[e.b],half=e.half,len=e.len,junction=e.junction,axis=e.axis,side=e.side}
			edges[ne.id]=ne
			table.insert(nodes[ne.a].links,ne.id);table.insert(nodes[ne.b].links,ne.id)
		end
	end
	-- obstacles in edge space (grid-bucketed: 32-stud cells)
	local obs: {[number]: {EdgeObstacle}}={}
	local CELL=32
	local grid: {[string]: {Obstacle}}={}
	for _,o in obstacles do
		for gx=math.floor(o.x1/CELL),math.floor(o.x2/CELL) do
			for gz=math.floor(o.z1/CELL),math.floor(o.z2/CELL) do
				local k=gx..":"..gz
				local list=grid[k];if not list then list={};grid[k]=list end
				table.insert(list,o)
			end
		end
	end
	for _,e in edges do
		local pa,pb=nodes[e.a].p,nodes[e.b].p
		local dx,dz=pb.X-pa.X,pb.Z-pa.Z
		local L=math.sqrt(dx*dx+dz*dz)
		if L>.05 then
			local ux,uz=dx/L,dz/L
			local reach=e.half+3
			local seen: {[Obstacle]: boolean}={}
			local list: {EdgeObstacle}={}
			for gx=math.floor((math.min(pa.X,pb.X)-reach)/CELL),math.floor((math.max(pa.X,pb.X)+reach)/CELL) do
				for gz=math.floor((math.min(pa.Z,pb.Z)-reach)/CELL),math.floor((math.max(pa.Z,pb.Z)+reach)/CELL) do
					local cell: {Obstacle}=grid[gx..":"..gz] or {}
					for _,o in cell do
						if not seen[o] then
							seen[o]=true
							local s1,s2,l1,l2=math.huge,-math.huge,math.huge,-math.huge
							for _,c in {{o.x1,o.z1},{o.x2,o.z1},{o.x1,o.z2},{o.x2,o.z2}} do
								local rx,rz=c[1]-pa.X,c[2]-pa.Z
								local s=rx*ux+rz*uz;local l=-rx*uz+rz*ux
								s1,s2,l1,l2=math.min(s1,s),math.max(s2,s),math.min(l1,l),math.max(l2,l)
							end
							if s2>-2 and s1<L+2 and l2>-reach and l1<reach then table.insert(list,{s1=s1,s2=s2,l1=l1,l2=l2}) end
						end
					end
				end
			end
			if #list>0 then
				table.sort(list,function(p,q) return p.s1<q.s1 end)
				obs[e.id]=list
			end
		end
	end
	-- car lanes
	local lanes: {Lane}={}
	for _,r in roads do
		if r.width>=16 then
			for _,dir in {1,-1} do
				local sign=if r.axis=="x" then dir else -dir
				for i=1,r.lanes do
					local off=sign*(r.median/2+(i-.5)*(r.width-r.median)/2/r.lanes)
					table.insert(lanes,{road=r,dir=dir,off=off,index=i,count=r.lanes})
				end
			end
		end
	end
	return {id=id,bounds=bounds,signals=signals,roads=roads,junctions=js,byRoad=by,nodes=nodes,edges=edges,lanes=lanes,roadY=City.ROAD_TOP,obs=obs}
end
Plan.buildNet=build
function Plan.lanePoint(l: Lane,a: number,y: number): Vector3
	local x,z=at(l.road,a,l.off)
	return Vector3.new(x,y,z)
end
function Plan.laneHeading(l: Lane): Vector3
	return if l.road.axis=="x" then Vector3.new(l.dir,0,0) else Vector3.new(0,0,l.dir)
end
function Plan.lane(net: Net,r: Road,dir: number,index: number): Lane?
	for _,l in net.lanes do if l.road==r and l.dir==dir and l.index==index then return l end end
	return nil
end

------------------------------------------------------------------------------------------------ street furniture
-- Positions shared by MetroBuilder (which builds them) and the walk networks (obstacles the walkers step round).
export type Prop={x: number,z: number,k: number,lit: boolean}
Plan.STREET_LAMPS={} :: {Prop} -- kerb side of every sidewalk
Plan.STREET_TREES={} :: {Prop} -- property side
Plan.SIGNAL_POSTS={} :: {Vector3} -- two per junction (x, 0, z)
-- where paths leave a sidewalk (tower approaches, walkways, park gates, plaza crossings): no lamp / tree there
local ACCESS: {{number}}={{-58,7930},{58,7930},{-58,8230},{58,8230},{0,8356},{440,7930},{560,7804},{560,8051},{-450,7764},{450,7764},
	{-80,7764},{0,7764},{80,7764},{-104,7764},{104,7764},{-206,7764},{206,7764}}
Plan.HARBOUR_WALKWAYS={-560,-300,-110,110,300,560} -- walkways from Harbour Street's south sidewalk (z 8356) to the harbour walk
for _,x in Plan.HARBOUR_WALKWAYS do table.insert(ACCESS,{x,8356}) end
do
	local js=findJunctions(Plan.ROADS)
	for _,j in js do
		for _,q in {{-1,-1},{1,1}} do table.insert(Plan.SIGNAL_POSTS,Vector3.new(j.x+q[1]*(j.rz.width/2+1.4),0,j.z+q[2]*(j.rx.width/2+1.4))) end
	end
	local function free(x: number,z: number,pad: number): boolean
		for _,j in js do
			if math.abs(x-j.x)<j.rz.width/2+j.rz.walk+pad and math.abs(z-j.z)<j.rx.width/2+j.rx.walk+pad then return false end
		end
		for _,b in Plan.BUS_STOPS do if math.abs(x-b.x)<9 and math.abs(z-b.z)<6 then return false end end
		for _,rr in {Plan.VIP_LIMO.layby,Plan.TAXI_RANK} do if x>rr.x1-4 and x<rr.x2+4 and z>rr.z1-6 and z<rr.z2+2 then return false end end
		for _,p in ACCESS do if math.abs(x-p[1])<7 and math.abs(z-p[2])<7 then return false end end
		if math.abs(x)<6 and (z<7810 or z>8310) then return false end
		return true
	end
	local lampN,treeK=0,500
	for _,r in Plan.ROADS do
		if r.walk>0 then
			for _,sd in {-1,1} do
				local step=if r.id=="pm_boulevard" then 46 else 64
				local a=r.a1+(if sd>0 then step/2 else step)
				while a<r.a2-10 do
					local lx,lz=a,r.c+sd*(r.width/2+1.1)
					if r.axis=="z" then lx,lz=lz,lx end
					if not inGap(r,sd,a-2,a+2) and free(lx,lz,4) then
						lampN+=1;table.insert(Plan.STREET_LAMPS,{x=lx,z=lz,k=lampN,lit=lampN%4==1})
					end
					local tx,tz=a+step/4,r.c+sd*(r.width/2+r.walk-1.2)
					if r.axis=="z" then tx,tz=tz,tx end
					local plazaSide=r.id=="pm_arrivals" and sd<0
					if not plazaSide and free(tx,tz,6) then treeK+=1;table.insert(Plan.STREET_TREES,{x=tx,z=tz,k=treeK,lit=false}) end
					a+=step
				end
			end
		end
	end
end
-- boulevard median: flags, double lamps (post at z + 12), trees on the outer lawns (clear of the flags)
Plan.MEDIAN_FLAGS={7840,7920,7970,8030,8130,8180,8240,8300}
Plan.MEDIAN_LAMPS={7860,7960,8030,8160,8270}
Plan.MEDIAN_TREES={} :: {Prop}
do
	local k=760
	for _,md in Plan.MEDIAN do
		for z=md.z1+22,md.z2-18,38 do
			local nearFlag=false
			for _,fz in Plan.MEDIAN_FLAGS do if math.abs(z-fz)<9 then nearFlag=true end end
			if not nearFlag then for _,sx in {-19.5,19.5} do k+=1;table.insert(Plan.MEDIAN_TREES,{x=sx,z=z,k=k,lit=false}) end end
		end
	end
end
Plan.PLAZA_FLAGS={-185,-160,-130,-110,-50,-30,30,50,110,130,160,185} -- arrival plaza, z 7698
-- harbour quarter
Plan.CAFES={-440,-200,200,380} -- café halls at z 8522..8538, umbrella terraces to z 8553
Plan.HARBOUR_LAMPS={} :: {number} -- x, promenade lamp row at z 8662
for x=-655,655,90 do table.insert(Plan.HARBOUR_LAMPS,x) end
Plan.HARBOUR_KIOSK=Vector3.new(24,0,8604) -- GPS kiosk south of the spire plaza walk
Plan.SCULPTURE=Vector3.new(-36,0,8616) -- "Meridian Sail", promenade head
Plan.SPLASH={Vector3.new(-64,0,8560),Vector3.new(64,0,8560)} -- ground-jet splash fountains on the spire plaza (radius 9)
Plan.CARTS={Vector3.new(-520,0,8657),Vector3.new(-250,0,8657),Vector3.new(120,0,8657),Vector3.new(380,0,8657)} -- food carts
Plan.PROM_TREES={} :: {Prop} -- row in planter beds at z 8614 (between the harbour walk and the promenade walk)
do
	local k=950
	for x=-680,680,34 do
		local ok=math.abs(x)>9 and math.abs(x-Plan.SCULPTURE.X)>10 and math.abs(x-Plan.HARBOUR_KIOSK.X)>8
		for _,c in Plan.CORRIDORS do if math.abs(x-c)<9 then ok=false end end
		if ok then k+=1;table.insert(Plan.PROM_TREES,{x=x,z=8614,k=k,lit=false}) end
	end
end
-- second promenade row: trees in planters between the lamps (z 8662), clear of the cross paths and the carts
Plan.LAMP_TREES={} :: {Prop}
do
	local k=1700
	for i=1,#Plan.HARBOUR_LAMPS-1 do
		local x=(Plan.HARBOUR_LAMPS[i]+Plan.HARBOUR_LAMPS[i+1])/2
		local ok=true
		for px=-600,600,200 do if math.abs(x-px)<8 then ok=false end end
		for _,c in Plan.CARTS do if math.abs(x-c.X)<14 then ok=false end end
		if ok then k+=1;table.insert(Plan.LAMP_TREES,{x=x,z=8662,k=k,lit=false}) end
	end
end
Plan.BED_TREES={} :: {Prop} -- trees in the harbour walk beds
do
	local k=1100
	for _,b in Plan.BEDS do
		local n=math.max(1,math.floor((b.x2-b.x1)/32))
		for i=0,n-1 do k+=1;table.insert(Plan.BED_TREES,{x=b.x1+(i+.5)*(b.x2-b.x1)/n,z=(b.z1+b.z2)/2,k=k,lit=false}) end
	end
end
-- mooring bollards on the promenade side of the quay rail (z 8699.3), clear of the quay benches
Plan.BOLLARDS={} :: {number}
for x=-690,690,20 do
	local ok=true
	for _,s in benches do if s.z>8690 and math.abs(s.x-x)<5 then ok=false end end
	if ok then table.insert(Plan.BOLLARDS,x) end
end
-- airport district: tree row between the district walk (z 7728) and Arrivals Drive (from x = +-246: clear of the
-- Airport District sign at x = -226)
Plan.DISTRICT_TREES={} :: {Prop}
do
	local k=1300
	for _,sx in {-1,1} do
		for ax=246,690,34 do
			local x=sx*ax
			if math.abs(ax-450)>9 then k+=1;table.insert(Plan.DISTRICT_TREES,{x=x,z=7744,k=k,lit=false}) end
		end
	end
end
-- one tree per ~30 studs of every verge (long axis)
Plan.VERGE_TREES={} :: {Prop}
do
	local k=1500
	for _,q in Plan.VERGES do
		local w,d=q.x2-q.x1,q.z2-q.z1
		local long=math.max(w,d)
		local n=math.floor(long/30)
		for i=0,n-1 do
			local t=(i+.5)/n
			k+=1
			table.insert(Plan.VERGE_TREES,if w>=d then {x=q.x1+w*t,z=(q.z1+q.z2)/2,k=k,lit=false} else {x=(q.x1+q.x2)/2,z=q.z1+d*t,k=k,lit=false})
		end
	end
end
-- district gateway signs (slab 14 wide facing the street along x, both faces lettered): name, kicker, centre
Plan.DISTRICT_SIGNS={
	{name="FINANCIAL DISTRICT",kicker="MERIDIAN",x=-114,z=7811},
	{name="FINANCIAL DISTRICT",kicker="MERIDIAN",x=114,z=8117},
	{name="EXCHANGE QUARTER",kicker="PORT MERIDIAN",x=-460,z=7811},
	{name="PARKSIDE",kicker="PORT MERIDIAN",x=460,z=8117},
	{name="HARBOUR QUARTER",kicker="PORT MERIDIAN",x=-134,z=8363},
	{name="HARBOUR QUARTER",kicker="PORT MERIDIAN",x=134,z=8363},
	{name="AIRPORT DISTRICT",kicker="PORT MERIDIAN",x=-226,z=7744},
} :: {{name: string,kicker: string,x: number,z: number}}
Plan.SIGN_W=14
Plan.PARK_LAMPS={Vector3.new(462,0,7880),Vector3.new(688,0,7880),Vector3.new(462,0,7990),Vector3.new(688,0,7990)} -- beside the loop path
Plan.PARK_TREE_POS={{490,7850},{530,7860},{660,7852},{620,7845},{500,7990},{650,8000},{540,8005},{610,8008},{690,7900},{690,7960},
	{455,7860},{455,8000},{520,7900},{630,7960}} :: {{number}}

-- Every solid prop near the walk graph (flat boxes): Port Meridian.
local function sq(list: {Obstacle},x: number,z: number,r: number,kind: string) table.insert(list,{x1=x-r,x2=x+r,z1=z-r,z2=z+r,kind=kind}) end
local function boxO(list: {Obstacle},x1: number,x2: number,z1: number,z2: number,kind: string) table.insert(list,{x1=math.min(x1,x2),x2=math.max(x1,x2),z1=math.min(z1,z2),z2=math.max(z1,z2),kind=kind}) end
function Plan.obstacles(): {Obstacle}
	local o: {Obstacle}={}
	for _,p in Plan.STREET_LAMPS do sq(o,p.x,p.z,.3,"lamp") end
	for _,list in {Plan.STREET_TREES,Plan.MEDIAN_TREES,Plan.PROM_TREES,Plan.DISTRICT_TREES,Plan.VERGE_TREES,Plan.LAMP_TREES} do for _,p in list do sq(o,p.x,p.z,.65,"tree") end end
	for _,p in Plan.PROM_TREES do sq(o,p.x,p.z,2.6,"planter") end
	for _,p in Plan.LAMP_TREES do sq(o,p.x,p.z,2.2,"planter") end
	for _,p in Plan.DISTRICT_TREES do sq(o,p.x,p.z,2.6,"planter") end
	for _,p in Plan.SIGNAL_POSTS do sq(o,p.X,p.Z,.35,"signal") end
	-- bus shelters: back glass, posts, bench
	for _,b in Plan.BUS_STOPS do
		local fz=b.face.Z;local back=b.z-fz*1.2
		boxO(o,b.x-5.8,b.x+5.8,back-fz*.25,back+fz*1.0,"shelter")
	end
	-- median: monument, fountains, globe, pool, lamps, flags
	boxO(o,-11,11,7815,7819,"monument")
	for _,z in Plan.FOUNTAINS do sq(o,0,z,10,"fountain") end
	boxO(o,-3.5,3.5,7936,7944,"globe")
	boxO(o,-9,9,8250,8302,"pool")
	for _,z in Plan.MEDIAN_LAMPS do sq(o,0,z+12,.35,"lamp") end
	for _,z in Plan.MEDIAN_FLAGS do for _,sx in {-21,21} do sq(o,sx,z,.25,"flag") end end
	-- arrival plaza: flags, planters, lamps, kiosk, metro entrance, taxi sign, VIP canopy columns, stanchions
	for _,x in Plan.PLAZA_FLAGS do sq(o,x,7698,.25,"flag") end
	for _,x in {-130,-40,40,130} do boxO(o,x-4.5,x+4.5,7738,7747,"planter") end
	for _,p in {{-196,7694},{196,7694},{-60,7745},{60,7745}} do sq(o,p[1],p[2],.3,"lamp") end
	boxO(o,-25.5,-22.5,7741,7743,"kiosk")
	boxO(o,-197,-196.5,7699,7713,"rail");boxO(o,-181.5,-181,7699,7713,"rail");boxO(o,-197,-181,7712.5,7713,"rail")
	sq(o,-178,7698,.3,"pylon");sq(o,-198,7754,.25,"post")
	for _,x in {116,188} do sq(o,x,7748,.45,"column") end
	for _,z in {7700,7716,7732} do for _,x in {75,85} do sq(o,x,z,.25,"stanchion") end end
	-- tower forecourts
	for _,b in City.BUILDINGS do
		if b.zone=="abroad" and b.kind=="tower" then
			local s=if b.frame.X<0 then -1 else 1
			local tz=b.frame.Z
			for _,dz in {-15,15} do boxO(o,s*88,s*108,tz+dz-3,tz+dz+3,"planter") end
			boxO(o,s*118,s*119.4,tz+9,tz+17,"monolith")
			for _,dz in {-21,21} do sq(o,s*126,tz+dz,.25,"flag") end
		end
	end
	-- harbour quarter: spire planters, splash fountains, kiosk, cafés, wheel, lamps, carts, sculpture, bollards, beds
	for _,x in {-70,70} do sq(o,x,8530,5,"planter") end
	for _,p in Plan.SPLASH do sq(o,p.X,p.Z,9,"fountain") end
	boxO(o,Plan.HARBOUR_KIOSK.X-1.5,Plan.HARBOUR_KIOSK.X+1.5,Plan.HARBOUR_KIOSK.Z-1,Plan.HARBOUR_KIOSK.Z+1,"kiosk")
	for _,cx in Plan.CAFES do boxO(o,cx-14,cx+14,8522,8538,"cafe");boxO(o,cx-10.5,cx+10.5,8547.5,8550.5,"terrace") end
	local Wh=Plan.WHEEL
	local hub=Vector3.new(Wh.x,Wh.hub,Wh.z)
	for _,sz in {-1,1} do
		for _,sx in {-1,1} do
			local foot=Vector3.new(Wh.x+sx*24,G+.1,Wh.z+sz*12);local top=hub+Vector3.new(0,0,sz*4)
			local up=foot+(top-foot)*(5.5/(top.Y-foot.Y))
			boxO(o,math.min(foot.X,up.X)-.9,math.max(foot.X,up.X)+.9,math.min(foot.Z,up.Z)-.9,math.max(foot.Z,up.Z)+.9,"wheel")
		end
	end
	boxO(o,Wh.x-14,Wh.x+14,Wh.z-6,Wh.z+6,"wheel")
	for _,x in Plan.HARBOUR_LAMPS do sq(o,x,8662,.3,"lamp") end
	for _,p in Plan.CARTS do boxO(o,p.X-3.6,p.X+3.6,p.Z-1.8,p.Z+1.8,"cart") end
	sq(o,Plan.SCULPTURE.X,Plan.SCULPTURE.Z,4,"sculpture")
	for _,x in Plan.BOLLARDS do sq(o,x,8699.3,.35,"bollard") end
	for _,b in Plan.BEDS do boxO(o,b.x1,b.x2,b.z1,b.z2,"bed") end
	-- park: lamps, trees, bandstand, sign post
	for _,p in Plan.PARK_LAMPS do sq(o,p.X,p.Z,.3,"lamp") end
	for _,p in Plan.PARK_TREE_POS do sq(o,p[1],p[2],.65,"tree") end
	sq(o,660,7974,8,"bandstand");sq(o,452,7940,.3,"post")
	-- district gateway signs
	for _,d in Plan.DISTRICT_SIGNS do boxO(o,d.x-Plan.SIGN_W/2-.4,d.x+Plan.SIGN_W/2+.4,d.z-.9,d.z+.9,"sign") end
	return o
end

-- Port Meridian: extra walk paths (plaza, median, tower approaches, waterfront, park), idle spots, portals.
local function v(x: number,z: number,y: number?): Vector3 return Vector3.new(x,y or Plan.PLAZA_TOP,z) end
local function pmPaths(): {Path}
	local M=Plan.MEDIAN_TOP;local K=Plan.PARK_TOP;local Wk=City.WALK_TOP
	local p: {Path}={}
	local function add(half: number,pts: {Vector3},cross: {[number]: string}?) table.insert(p,{pts=pts,half=half,cross=cross}) end
	-- arrival plaza: exits -> cross walk -> sidewalk; lay-by ends; the crossing to the boulevard median
	add(5,{v(-196,7728),v(-100,7728),v(-80,7728),v(0,7728),v(80,7728),v(100,7728),v(196,7728)})
	for _,x in {-80,0,80} do add(3,{v(x,7728),v(x,7764,Wk)}) end
	add(2.5,{v(-206,7764,Wk),v(-202,7752,Plan.PAVE_TOP),v(-196,7728)});add(2.5,{v(-104,7764,Wk),v(-100,7728)})
	add(2.5,{v(104,7764,Wk),v(100,7728)});add(2.5,{v(206,7764,Wk),v(202,7752,Plan.PAVE_TOP),v(196,7728)})
	for _,x in {-80,0,80} do add(3,{v(x,7695),v(x,7728)}) end
	add(2.5,{v(0,7764,Wk),v(0,7804,M)},{[1]="pm_arrivals"})
	-- airport district promenade along the north strip (lots stop at z 7716)
	add(4,{v(-196,7728),v(-450,7728),v(-690,7728)})
	add(4,{v(196,7728),v(450,7728),v(690,7728)})
	for _,x in {-450,450} do add(2.5,{v(x,7728),v(x,7764,Wk)}) end
	-- helipad gate (people waiting for the VIP transfer)
	add(2,{v(196,7728),v(262,7700),v(286,7686)})
	-- boulevard median: two paths around the fountains, joined at the noses on the crossings
	for _,sx in {-15,15} do
		add(3,{v(0,7804,M),v(sx,7814,M),v(sx,7880,M),v(sx,8000,M),v(sx,8042,M),v(0,8051,M)})
		add(3,{v(0,8109,M),v(sx,8118,M),v(sx,8210,M),v(sx,8306,M),v(0,8316,M)})
	end
	add(2.5,{v(0,8316,M),v(0,8356,Wk)},{[1]="pm_harbour"})
	-- tower approaches from the boulevard sidewalk to the doors (portals)
	for _,t in {{-1,7930},{1,7930},{-1,8230},{1,8230}} do add(3,{v(t[1]*58,t[2],Wk),v(t[1]*100,t[2]),v(t[1]*140,t[2])}) end
	-- hotel forecourt
	add(3,{v(0,8356,Wk),v(0,8370)})
	-- waterfront: the promenade and the quay walk first (the corridors join them), then the corridors from
	-- Harbour Street and the spire plaza ring
	local prom: {Vector3}={};local quay: {Vector3}={}
	for x=-690,690,46 do table.insert(prom,v(x,8640));table.insert(quay,v(x,8684)) end
	add(6,prom);add(4,quay)
	for x=-600,600,200 do add(3,{v(x,8640),v(x,8684)}) end
	for _,x in Plan.HARBOUR_WALKWAYS do
		-- the east walkway bends round the Harbour Wheel's west legs (x 516 / 564) to x = 580
		if x==560 then add(3,{v(x,8356,Wk),v(x,8510),v(580,8526),v(580,8590),v(580,8640)})
		else add(3,{v(x,8356,Wk),v(x,8510),v(x,8590),v(x,8640)}) end
	end
	-- north edge of the spire plaza, clear of the spire's plinth (z 8514+)
	add(3,{v(-110,8510),v(-90,8507),v(-40,8507),v(40,8507),v(90,8507),v(110,8510)})
	add(4,{v(-110,8590),v(-40,8590),v(0,8590),v(40,8590),v(110,8590)})
	-- the harbour walk along the planting beds (z 8590), joined to the promenade at both ends
	add(3,{v(-690,8640),v(-690,8590),v(-560,8590),v(-300,8590),v(-110,8590)})
	add(3,{v(110,8590),v(300,8590),v(580,8590),v(690,8590),v(690,8640)})
	add(3,{v(0,8590),v(0,8640)})
	add(3,{v(-300,8510),v(-560,8510)});add(3,{v(300,8510),v(560,8510)})
	-- Parkside park: loop round the pond, joined to the avenue and both streets
	add(3,{v(470,7834,K),v(575,7834,K),v(680,7834,K),v(680,7930,K),v(680,8022,K),v(575,8022,K),v(470,8022,K),v(470,7930,K),v(470,7834,K)})
	add(3,{v(440,7930,Wk),v(470,7930,K)});add(3,{v(560,7804,Wk),v(575,7834,K)});add(3,{v(560,8051,Wk),v(575,8022,K)})
	-- the four pond benches face the pond: their spurs come round to the bench fronts (pond side)
	add(2.5,{v(470,7915,K),v(521,7915,K),v(521,7930,K)});add(2.5,{v(680,7945,K),v(629,7945,K),v(629,7930,K)})
	add(2.5,{v(560,7834,K),v(560,7876,K),v(575,7876,K)});add(2.5,{v(590,8022,K),v(590,7984,K),v(575,7984,K)})
	return p
end
local function pmPortals(): {{any}}
	local out: {{any}}={}
	for _,x in {-80,0,80} do table.insert(out,{v(x,7695),Vector3.new(0,0,-1)}) end -- terminal exits
	for _,t in {{-1,7930},{1,7930},{-1,8230},{1,8230}} do table.insert(out,{v(t[1]*146,t[2]),Vector3.new(-t[1],0,0)}) end -- client towers
	table.insert(out,{v(0,8376),Vector3.new(0,0,1)}) -- hotel
	table.insert(out,{v(0,8580,Plan.PLINTH_TOP),Vector3.new(0,0,-1)}) -- spire lobby (on the plinth, steps in front)
	for _,pv in Plan.PAVILIONS do table.insert(out,{v(pv.side*64.5,(pv.z1+pv.z2)/2,City.WALK_TOP),Vector3.new(pv.side,0,0)}) end
	-- pedestrian passages in the tunnel gates at the sidewalk ends
	for _,t in Plan.TUNNELS do
		for _,sd in {-1,1} do table.insert(out,{v(t.x-t.side*2.5,t.road.c+sd*walkOff(t.road),City.WALK_TOP),Vector3.new(t.side,0,0)}) end
	end
	return out
end
local function allSpots(): {Spot}
	local out: {Spot}={}
	for _,list in {Plan.BENCHES,Plan.SHOPS,Plan.STOPS,Plan.VIEWS} do for _,s in list do table.insert(out,s) end end
	return out
end
local pmNet: Net?=nil
function Plan.portMeridian(): Net
	local cached=pmNet
	if cached then return cached end
	local r=A.rect
	local n=build("metro",{x1=r.x1-60,x2=r.x2+60,z1=r.z1-40,z2=A.promenade.z2+20},true,Plan.ROADS,pmPaths(),allSpots(),pmPortals(),Plan.obstacles())
	pmNet=n
	return n
end

-- Business City props near its sidewalks (read-only copies of CityBuilder's placement rules): street lamps every
-- 160 studs on alternating sides (property edge - 1.5, not within 10 studs of a crossing), City Plaza planters,
-- lamps, the map board and the fountain rim.
function Plan.downtownObstacles(): {Obstacle}
	local o: {Obstacle}={}
	for _,r in City.ROADS do
		if r.walk>0 then
			local gaps: {{number}}={}
			for _,q in City.ROADS do
				if q~=r and q.axis~=r.axis and q.c>=r.a1-1 and q.c<=r.a2+1 and r.c>=q.a1-1 and r.c<=q.a2+1 then table.insert(gaps,{q.c,q.width/2+q.walk}) end
			end
			local n=0
			for a=r.a1+80,r.a2-40,160 do
				local ok=true
				for _,g in gaps do if math.abs(a-g[1])<g[2]+10 then ok=false end end
				if ok then
					n+=1
					local off=(if n%2==0 then 1 else -1)*(r.width/2+r.walk-1.5)
					if r.axis=="x" then sq(o,a,r.c+off,.3,"lamp") else sq(o,r.c+off,a,.3,"lamp") end
				end
			end
		end
	end
	local P=City.PLAZA;local cx,cz=(P.x1+P.x2)/2,(P.z1+P.z2)/2
	for _,x in {P.x1+30,P.x2-30} do for _,z in {P.z1+60,cz-80,cz+80,P.z2-40} do boxO(o,x-4,x+4,z-4,z+4,"planter") end end
	for _,p in {{P.x1+8,P.z1+8},{P.x2-8,P.z1+8},{P.x1+8,P.z2-8},{P.x2-8,P.z2-8}} do sq(o,p[1],p[2],.3,"lamp") end
	boxO(o,cx-10,cx+10,P.z1+14,P.z1+15,"mapboard")
	sq(o,cx,cz,15,"fountain")
	for _,z in {cz-40,cz+40} do boxO(o,cx-34,cx-30,z-5,z+5,"bench");boxO(o,cx+30,cx+34,z-5,z+5,"bench") end
	-- AirportBuilder's car-park sign post on Airport Road's south sidewalk (owner: airport package)
	boxO(o,-338,-337,2402,2403,"post")
	return o
end

-- Business City (read-only from CityPlan): its roads (ring roads have no sidewalks: cars only), City Plaza
-- paths round the fountain, benches, and every downtown door (offices, City Hotel, convention centre) as portal.
local dtNet: Net?=nil
function Plan.downtown(): Net
	local cached=dtNet
	if cached then return cached end
	local roads: {Road}={}
	for _,r in City.ROADS do
		table.insert(roads,road(r.id,r.name,r.axis,r.c,r.a1,r.a2,r.width,r.walk,0,if r.width>=44 then 2 else 1))
	end
	local P=City.PLAZA;local cx,cz=(P.x1+P.x2)/2,(P.z1+P.z2)/2;local top=G+.3
	local function pv(x: number,z: number): Vector3 return Vector3.new(x,top,z) end
	-- loop round the fountain (rim +-15) inside the bench lines (cx +- 30..34)
	local paths: {Path}={
		{pts={pv(cx-25,cz-25),pv(cx+25,cz-25),pv(cx+25,cz+25),pv(cx-25,cz+25),pv(cx-25,cz-25)},half=2.5},
		-- from the Parkway: round the west end of the map board (x cx-10..cx+10, z P.z1+14..15)
		{pts={Vector3.new(cx,City.WALK_TOP,1024),pv(cx,P.z1),pv(cx-17,P.z1+8),pv(cx-17,P.z1+22),pv(cx,P.z1+30),pv(cx,cz-25)},half=3},
		{pts={Vector3.new(cx,City.WALK_TOP,1476),pv(cx,P.z2),pv(cx,cz+25)},half=3},
		{pts={Vector3.new(24,City.WALK_TOP,cz),pv(P.x1,cz),pv(cx-25,cz)},half=3},
		{pts={Vector3.new(316,City.WALK_TOP,cz),pv(P.x2,cz),pv(cx+25,cz)},half=3},
	}
	local spots: {Spot}={}
	for _,z in {cz-40,cz+40} do
		-- the block benches span cx-34..cx-30 / cx+30..cx+34: stand just in front, sit on the front edge
		table.insert(spots,{x=cx-28.8,z=z,y=top,face=Vector3.new(1,0,0),kind="bench"})
		table.insert(spots,{x=cx+28.8,z=z,y=top,face=Vector3.new(-1,0,0),kind="bench"})
	end
	table.insert(spots,{x=cx,z=cz-18,y=top,face=Vector3.new(0,0,1),kind="view"})
	table.insert(spots,{x=cx,z=cz+18,y=top,face=Vector3.new(0,0,-1),kind="view"})
	local portals: {{any}}={}
	for _,d in City.DESTINATION_LIST do
		if d.zone=="downtown" and (d.kind=="client" or d.kind=="hotel" or d.kind=="venue") then
			local p=d.door.Position
			table.insert(portals,{Vector3.new(p.X,G+.3,p.Z),d.door.LookVector})
		end
	end
	local n=build("downtown",{x1=-1150,x2=1150,z1=540,z2=2420},false,roads,paths,spots,portals,Plan.downtownObstacles())
	dtNet=n
	return n
end
-- Activation regions of the client city life (camera position). Business City ends at Airport Road's south
-- sidewalk (z 2408): City Airport (terminal z 2430+, check-in z 2461, car park bays z 2421) stays quiet.
Plan.REGIONS={
	{id="metro",x1=-2600,x2=2600,z1=6500,z2=10200},
	{id="downtown",x1=-1260,x2=1260,z1=700,z2=2416},
} :: {{id: string,x1: number,x2: number,z1: number,z2: number}}
function Plan.regionAt(p: Vector3): string?
	for _,r in Plan.REGIONS do if p.X>=r.x1 and p.X<=r.x2 and p.Z>=r.z1 and p.Z<=r.z2 then return r.id end end
	return nil
end
return Plan
