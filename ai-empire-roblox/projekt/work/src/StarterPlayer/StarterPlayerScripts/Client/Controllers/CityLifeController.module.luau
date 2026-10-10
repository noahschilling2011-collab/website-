--!strict
-- CityLifeController (package "metro"): client-only city life in Port Meridian and Business City (downtown).
--   * Walkers: cheap R6-like figures built from 7-9 parts (varied skin, hair and clothing; business attire with
--     a shirt front and briefcase for ~40 %; eyes on near walkers) on MetroPlan's walk graph - sidewalks, zebra
--     crossings (signal phases in Port Meridian, gaps in the traffic downtown), plaza / median / promenade / park
--     paths. They step round the street furniture beside their line (MetroPlan obstacles per edge), sit on
--     benches, look into shop windows, wait at bus stops and view points, and enter / leave buildings and the
--     tunnel gates through door portals. Procedural walk cycle (legs and arms swing with the distance walked).
--   * Cars: sedans, hatchbacks, SUVs, vans, taxis, buses and the odd limousine (body, sloped windscreen / rear
--     window, bumpers) on MetroPlan's lanes (right-hand traffic): car following (also behind a car turning out of
--     the lane), red lights (Port Meridian), forced turns at T-ends and random turns at junctions. Every car
--     reserves the junction box before its stop line: granted only when no walker is on a zebra its swept path
--     crosses, no reserved car of another approach has a path sharing a cell with it, and the exit has room;
--     walkers never step in front of a reserved path, and with signals turning cars yield to walkers on their walk
--     phase. Requests that waited longest win (no starvation either way). Port Meridian's through streets continue
--     past the boundary walls on client road strips into tunnel gates, so traffic enters and leaves out of sight.
--   * Port Meridian extras: traffic-signal colours (lamp plates tagged "MetroSignal"), night glow of windows
--     and shop glass ("MetroNightGlow", attribute GlowColor), the turning Harbour Wheel ("MetroWheel"), the far
--     skyline beyond the walls (MetroPlan.FAR), the tunnel gates (MetroPlan.TUNNELS) and impostors for towers
--     streamed out on this client (their material, tint, silhouette, crown / needle and night glow).
--   * City Airport terminal (airport request #5): 30 walkers (the top of the requested 20-30: the hall is 600 studs
--     long), no cars, on the airport package's walk graph
--     (MetroPlan.airportNet: check-in queues and desks, security, concourse, shops, food court, lounge, gates,
--     baggage reclaim) with seat spurs at gate A1 and the landside seating islands; they board / arrive through
--     the A1 jet bridge and the doors. Only while the camera is between the forecourt and the jet bridges, below
--     the roof line (MetroPlan.REGIONS).
--   * Budget: <= 60 walkers / 25 cars (downtown 44 / 18) around the camera: spawn 110-340 studs out (the first
--     fill anywhere within the radius; walkers prefer the nearer spots), recycle beyond 380. One step at <= 30 Hz
--     writes every moved CFrame with a single workspace:BulkMoveTo; walkers beyond 170 studs update at 10 Hz
--     without limb swing, eyes or shadows. Shadows: car bodies and the torso / legs of near walkers only. Outside
--     the regions (campus, plots, the airport forecourt / apron, the flight) all of it is unparented and the step
--     connection is cut: the only cost left is one region check every 0.5 s. No server instance is written, no
--     network traffic.
--   * Deterministic: Random seeded per region activation from MetroPlan.SEED; signal phases follow
--     workspace:GetServerTimeNow(), so every client shows the same lights.
local RunService=game:GetService("RunService")
local CollectionService=game:GetService("CollectionService")
local Lighting=game:GetService("Lighting")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Plan=require(ReplicatedStorage.Shared.Config.MetroPlan)
local City=require(ReplicatedStorage.Shared.Config.CityPlan)

local CityLife={}
CityLife.CAPS={metro={walkers=60,cars=25},downtown={walkers=44,cars=18},airport={walkers=30,cars=0}} :: {[string]: {walkers: number,cars: number}}
CityLife.SPAWN_MIN=110
CityLife.RADIUS=340
CityLife.DESPAWN=380
CityLife.STEP=1/30 -- at most 30 updates per second
CityLife.SCAN=.5 -- region check, spawning, LOD
CityLife.FAR_LOD=170
local FAR_STEP=.1
local G=City.GROUND
local ROAD_Y=City.ROAD_TOP
local WALK_SPEED={3.8,5.6}
local STRIDE=3.2 -- studs per full walk cycle
local CROSS_HURRY=1.5 -- walkers hurry across a street
local WALK_WINDOW=5 -- seconds at the start of a walk phase in which walkers may step onto a zebra
local NEAR_BIAS=.55 -- walker spawn acceptance falls from 1 (near) to 0.45 (rim)
local CAR_ACCEL,CAR_PLAN_BRAKE,CAR_MAX_BRAKE,CAR_MIN_GAP,TURN_SPEED=10,14,40,3.5,15

type Net=Plan.Net
type Road=Plan.Road
type JRef=Plan.JunctionRef
type WalkEdge=Plan.WalkEdge
type Walker={
	id: number,model: Model,parts: {BasePart},eyes: {BasePart},business: boolean,bag: boolean,shirt: boolean,
	alive: boolean,edge: WalkEdge?,from: number,to: number,s: number,lat: number,speed: number,phase: number,
	mode: string,untilT: number,age: number,idleCool: number,waitT: number,pos: Vector3,look: Vector3,
	seat: Vector3?,benchNode: number?,crossKey: string?,crossE: number?,claimJ: number?,nextAt: number,far: boolean,near: boolean,sway: number,snap: boolean,
}
-- incoming: cars turning into the lane (followers brake for their entry point); outgoing: cars that turned out of
-- it and still reach into its band (followers keep treating them as leaders)
type LaneRec={id: number,lane: Plan.Lane,road: Road,dir: number,a0: number,a1: number,len: number,refs: {JRef},tEnd: JRef?,cars: {Car},incoming: {Car},outgoing: {Car}}
type Turn={s: Vector3,c: Vector3,e: Vector3,u: number,len: number,to: LaneRec,aE: number}
type CarPlan={ref: JRef,to: LaneRec}
-- A movement through a junction box (approach lane -> exit lane) for one car size class: the cells (2-stud grid) the
-- car body sweeps from the stop line until its tail has cleared the far zebra, the zebra crossings it passes
-- (cross), and the exit-lane progress at which the tail is clear (release).
type Move={id: string,j: Plan.Junction,from: LaneRec,to: LaneRec,cls: string,cells: {[number]: boolean},cross: {[number]: boolean},release: number}
type Car={
	id: number,model: Model,parts: {BasePart},offs: {CFrame},kind: string,len: number,width: number,alive: boolean,
	lane: LaneRec?,a: number,v: number,vmax: number,turn: Turn?,plan: CarPlan?,decided: {[number]: boolean},
	pos: Vector3,look: Vector3,leaderGap: number,res: Move?,cls: string,outFrom: LaneRec?,
	waitT: number,pendJ: number?,pendMove: Move?,
}
-- occ: walkers on the crossings per junction + crossed axis ("<j>:<axis>"), occE: per crossing edge; box: the cars
-- holding a reservation of each junction box; moves / conf: cached movements and their pairwise conflicts.
type Region={id: string,net: Net,lanes: {LaneRec},roadLanes: {[string]: {LaneRec}},laneTotal: number,occ: {[string]: number},
	occE: {[number]: number},seats: {[number]: number},rng: Random,candidates: {WalkEdge},candTotal: number,portals: {number},
	box: {[number]: {Car}},pend: {[number]: {Car}},wclaim: {[number]: {Walker}},moves: {[string]: Move},conf: {[string]: boolean},jEdges: {[number]: {WalkEdge}}}
type Look={color: Color3,material: Enum.Material,transparency: number,glow: Color3,lit: boolean}
type WheelPart={part: BasePart,angle: number,r: number,kind: string,hang: number}
type Wheel={model: Instance,hub: Vector3,parts: {WheelPart}}
type Impostor={part: BasePart,parts: {BasePart},shown: boolean,present: () -> boolean}

-- module state
local folder: Model?=nil -- workspace.CityLife (walkers + cars)
local farModel: Model?=nil -- far skyline, far ground, road continuations, impostors (Port Meridian only)
local walkers: {Walker}={}
local cars: {Car}={}
local region: Region?=nil
local regionCache: {[string]: Region}={}
local impostors: {Impostor}={}
local glowParts: {[BasePart]: Look}=setmetatable({},{__mode="k"}) :: any
local signalParts: {[BasePart]: boolean}={}
local wheels: {[Instance]: Wheel}={}
local night=false
local acc,scanAcc,signalAcc,wheelAcc,glowAcc=0,0,0,0,0
local stepConn: RBXScriptConnection?=nil
local batchParts: {BasePart}={}
local batchFrames: {CFrame}={}
local stats={region="none",walkers=0,cars=0,parts=0,lastStepMs=0,maxStepMs=0,steps=0,spawnedWalkers=0,spawnedCars=0,despawned=0,forcedBox=0}

------------------------------------------------------------------------------------------------ helpers
local function flat(v: Vector3): Vector3 return Vector3.new(v.X,0,v.Z) end
local function flatDist(a: Vector3,b: Vector3): number return math.sqrt((a.X-b.X)^2+(a.Z-b.Z)^2) end
local function part(parent: Instance,name: string,size: Vector3,color: Color3,material: Enum.Material?,shape: Enum.PartType?): Part
	local p=Instance.new("Part");p.Name=name;p.Size=size;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
	p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
	p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
	if shape then p.Shape=shape end
	p.CFrame=CFrame.new(0,-500,0)
	p.Parent=parent
	return p
end
-- WedgePart (vertical face at local +Z, the slope falls towards the front, -Z), same flags as part().
local function wedge(parent: Instance,name: string,size: Vector3,color: Color3,material: Enum.Material?): WedgePart
	local p=Instance.new("WedgePart");p.Name=name;p.Size=size;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
	p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
	p.CFrame=CFrame.new(0,-500,0)
	p.Parent=parent
	return p
end
local function pick<T>(list: {T},h: number): T return list[(h%#list)+1] end
local function push(p: BasePart,cf: CFrame) table.insert(batchParts,p);table.insert(batchFrames,cf) end
-- A pending car only claims while its light is green (or there are no signals): at red it keeps its place and its
-- waiting time but blocks nobody.
local function pendActive(R: Region,mv: Move,now: number): boolean
	return not R.net.signals or Plan.greenLeft(mv.j,mv.from.road.axis,now)>0
end

------------------------------------------------------------------------------------------------ appearance
local SKIN={Color3.fromRGB(255,220,188),Color3.fromRGB(240,196,160),Color3.fromRGB(214,160,120),Color3.fromRGB(176,118,82),
	Color3.fromRGB(128,84,58),Color3.fromRGB(92,60,42),Color3.fromRGB(246,206,170)}
local HAIR={Color3.fromRGB(28,22,18),Color3.fromRGB(64,42,28),Color3.fromRGB(112,76,46),Color3.fromRGB(196,156,96),Color3.fromRGB(150,146,140),
	Color3.fromRGB(44,32,30),Color3.fromRGB(150,64,36),Color3.fromRGB(20,20,22)}
local SUIT={Color3.fromRGB(32,38,58),Color3.fromRGB(50,52,58),Color3.fromRGB(22,22,26),Color3.fromRGB(70,76,92),Color3.fromRGB(96,82,66),Color3.fromRGB(40,48,44)}
local SHIRT={Color3.fromRGB(238,240,242),Color3.fromRGB(196,214,232),Color3.fromRGB(240,232,220)}
local TOPS={Color3.fromRGB(196,60,58),Color3.fromRGB(58,110,176),Color3.fromRGB(236,200,80),Color3.fromRGB(70,150,110),Color3.fromRGB(232,232,228),
	Color3.fromRGB(230,140,60),Color3.fromRGB(140,90,160),Color3.fromRGB(40,44,52),Color3.fromRGB(110,170,190),Color3.fromRGB(220,120,150),
	Color3.fromRGB(150,40,52),Color3.fromRGB(120,130,80)}
local LEGS={Color3.fromRGB(46,70,110),Color3.fromRGB(60,86,128),Color3.fromRGB(190,170,130),Color3.fromRGB(30,30,34),Color3.fromRGB(110,112,116),
	Color3.fromRGB(86,96,60),Color3.fromRGB(226,222,212)}
local BAGS={Color3.fromRGB(70,44,28),Color3.fromRGB(28,28,30),Color3.fromRGB(196,60,58),Color3.fromRGB(236,200,80),Color3.fromRGB(70,150,110)}
local EYE=Color3.fromRGB(28,26,30)

-- Pool walker i (fixed look for the pool slot): Torso, Head, Hair, LeftArm, RightArm, LeftLeg, RightLeg [, Shirt] [, Bag].
local function buildWalker(parent: Instance,i: number): Walker
	local h=Plan.hash("walker"..i)
	local business=(i%5)<2
	local m=Instance.new("Model");m.Name="Walker";local _=parent
	local top=if business then pick(SUIT,h) else pick(TOPS,h)
	local legs=if business then (if h%3==0 then top else pick(SUIT,math.floor(h/7))) else pick(LEGS,math.floor(h/7))
	local skin=pick(SKIN,math.floor(h/53))
	local sleeves=if business or h%2==0 then top else skin
	local parts: {BasePart}={
		part(m,"Torso",Vector3.new(2,2,1),top,Enum.Material.Fabric),
		part(m,"Head",Vector3.new(1.25,1.25,1.25),skin,Enum.Material.SmoothPlastic,Enum.PartType.Ball),
		part(m,"Hair",Vector3.new(1.34,1.34,1.34),pick(HAIR,math.floor(h/331)),Enum.Material.SmoothPlastic,Enum.PartType.Ball),
		part(m,"LeftArm",Vector3.new(.9,1.9,.9),sleeves,Enum.Material.Fabric),
		part(m,"RightArm",Vector3.new(.9,1.9,.9),sleeves,Enum.Material.Fabric),
		part(m,"LeftLeg",Vector3.new(.95,2,.95),legs,Enum.Material.Fabric),
		part(m,"RightLeg",Vector3.new(.95,2,.95),legs,Enum.Material.Fabric),
	}
	if business then table.insert(parts,part(m,"Shirt",Vector3.new(.7,1.5,.06),pick(SHIRT,math.floor(h/11)),Enum.Material.Fabric)) end
	local bag=business and h%5~=0 or (not business and h%5==1)
	if bag then
		local bagC=if business then pick(BAGS,math.floor(h/13)%2) else pick(BAGS,2+math.floor(h/13)%3)
		table.insert(parts,part(m,"Bag",if business then Vector3.new(.4,1.1,1.5) else Vector3.new(.7,1.3,1.2),bagC,if business then Enum.Material.Leather else Enum.Material.Fabric))
	end
	-- two eyes (near walkers only: parented and posed inside FAR_LOD, see setNear)
	local eyes: {BasePart}={part(m,"Eye",Vector3.new(.15,.18,.1),EYE),part(m,"Eye",Vector3.new(.15,.18,.1),EYE)}
	for _,e in eyes do e.Parent=nil end -- setNear parents them
	return {id=i,model=m,parts=parts,eyes=eyes,business=business,bag=bag,shirt=business,alive=false,edge=nil,from=0,to=0,s=0,lat=.5,
		speed=WALK_SPEED[1]+(h%100)/99*(WALK_SPEED[2]-WALK_SPEED[1]),phase=(h%628)/100,mode="walk",untilT=0,age=0,idleCool=0,waitT=0,
		pos=Vector3.new(0,-500,0),look=Vector3.new(0,0,-1),seat=nil,benchNode=nil,crossKey=nil,crossE=nil,claimJ=nil,nextAt=0,far=false,near=false,sway=(h%97)/97*6.28,snap=true}
end
-- Near walkers (inside FAR_LOD) show eyes and cast shadows from torso and legs (~45 parts at the caps); far ones
-- drop both (the eyes are unparented, so the step does not pose them).
local SHADOW_PARTS={Torso=true,LeftLeg=true,RightLeg=true}
local function setNear(w: Walker,near: boolean)
	if w.near==near then return end
	w.near=near
	for _,p in w.parts do if SHADOW_PARTS[p.Name] then p.CastShadow=near end end
	for _,e in w.eyes do e.Parent=if near then w.model else nil end
end
CityLife.setNear=setNear

-- Car bodies. Offsets are relative to the road point under the car centre, front = -Z.
local PAINT={Color3.fromRGB(236,236,232),Color3.fromRGB(22,22,26),Color3.fromRGB(150,154,160),Color3.fromRGB(176,34,40),Color3.fromRGB(34,70,140),
	Color3.fromRGB(90,96,104),Color3.fromRGB(28,60,46),Color3.fromRGB(200,180,140),Color3.fromRGB(110,30,40),Color3.fromRGB(60,120,170),
	Color3.fromRGB(220,220,214),Color3.fromRGB(40,44,60)}
local KINDS={"sedan","hatch","suv","taxi","sedan","van","suv","hatch","sedan","limo","sedan","bus","hatch","suv","taxi","sedan","van","sedan","suv","hatch",
	"sedan","bus","taxi","suv","sedan"}
-- ws / rs: depth of the sloped windscreen / rear window (wedges; rs = 0: upright hatch / SUV tailgate)
type Spec={len: number,w: number,body: number,cab: number,cabLen: number,cabZ: number,ws: number,rs: number,vmax: number}
local SPECS: {[string]: Spec}={
	sedan={len=11.5,w=6.2,body=2.1,cab=1.8,cabLen=.5,cabZ=.06,ws=1.7,rs=1.4,vmax=32},
	hatch={len=9.6,w=5.8,body=2.1,cab=1.9,cabLen=.55,cabZ=.12,ws=1.5,rs=0,vmax=30},
	suv={len=12.4,w=6.6,body=2.8,cab=2.1,cabLen=.6,cabZ=.08,ws=1.4,rs=0,vmax=31},
	taxi={len=11.5,w=6.2,body=2.1,cab=1.8,cabLen=.5,cabZ=.06,ws=1.7,rs=1.4,vmax=33},
	limo={len=19,w=6.6,body=2.2,cab=1.8,cabLen=.66,cabZ=.06,ws=1.6,rs=1.2,vmax=27},
	van={len=13,w=6.6,body=5.2,cab=0,cabLen=0,cabZ=0,ws=0,rs=0,vmax=28},
	bus={len=28,w=7.4,body=7.4,cab=0,cabLen=0,cabZ=0,ws=0,rs=0,vmax=22},
}
local function buildCar(parent: Instance,i: number): Car
	local kind=KINDS[((i-1)%#KINDS)+1]
	local sp=SPECS[kind]
	local h=Plan.hash("car"..i)
	local paint=if kind=="taxi" then Color3.fromRGB(236,190,60) elseif kind=="limo" then Color3.fromRGB(16,16,20)
		elseif kind=="bus" then (if h%2==0 then Color3.fromRGB(32,60,110) else Color3.fromRGB(196,44,44)) else pick(PAINT,h)
	local m=Instance.new("Model");m.Name=if kind=="bus" then "Bus" elseif kind=="taxi" then "Taxi" else "Car";local _=parent
	local parts: {BasePart}={};local offs: {CFrame}={}
	local function add(p: BasePart,cf: CFrame) table.insert(parts,p);table.insert(offs,cf) end
	local glass=Color3.fromRGB(30,38,46)
	local trim=Color3.fromRGB(40,42,46)
	local base=.9
	local body=part(m,"Body",Vector3.new(sp.w,sp.body,sp.len),paint,Enum.Material.SmoothPlastic)
	body.CastShadow=true -- cars cast a shadow (body only: 25 parts at the cap)
	add(body,CFrame.new(0,base+sp.body/2,0))
	-- split bumpers (dark trim) front and rear
	for _,sz in {-1,1} do add(part(m,"Bumper",Vector3.new(sp.w+.2,.75,.5),trim,Enum.Material.SmoothPlastic),CFrame.new(0,base+.3,sz*(sp.len/2+.15))) end
	if sp.cab>0 then
		local cl=sp.len*sp.cabLen;local cz=sp.len*sp.cabZ
		add(part(m,"Cabin",Vector3.new(sp.w-.7,sp.cab,cl),glass,Enum.Material.Glass),CFrame.new(0,base+sp.body+sp.cab/2,cz))
		add(part(m,"Roof",Vector3.new(sp.w-.8,.25,cl),paint,Enum.Material.SmoothPlastic),CFrame.new(0,base+sp.body+sp.cab+.12,cz))
		-- sloped windscreen (high edge at the cabin, falling to the hood) and rear window (falling to the trunk)
		add(wedge(m,"Windscreen",Vector3.new(sp.w-.7,sp.cab,sp.ws),glass,Enum.Material.Glass),CFrame.new(0,base+sp.body+sp.cab/2,cz-cl/2-sp.ws/2))
		if sp.rs>0 then
			add(wedge(m,"RearWindow",Vector3.new(sp.w-.7,sp.cab,sp.rs),glass,Enum.Material.Glass),CFrame.new(0,base+sp.body+sp.cab/2,cz+cl/2+sp.rs/2)*CFrame.Angles(0,math.pi,0))
		end
	elseif kind=="van" then
		add(part(m,"Windscreen",Vector3.new(sp.w+.06,1.8,2.2),glass,Enum.Material.Glass),CFrame.new(0,base+sp.body-1.5,-sp.len/2+1))
	else -- bus: window band, destination display
		add(part(m,"Windows",Vector3.new(sp.w+.06,2.6,sp.len-3),glass,Enum.Material.Glass),CFrame.new(0,base+sp.body-2.3,.6))
		add(part(m,"Destination",Vector3.new(sp.w-1.6,.8,.1),Color3.fromRGB(255,190,70),Enum.Material.Neon),CFrame.new(0,base+sp.body-.7,-sp.len/2-.03))
	end
	local wheel=if kind=="bus" then 3.2 else 2.3
	for _,z in {-sp.len*.32,sp.len*.32} do
		add(part(m,"Wheels",Vector3.new(sp.w+.3,wheel,wheel),Color3.fromRGB(24,24,26),Enum.Material.Rubber,Enum.PartType.Cylinder),CFrame.new(0,wheel/2,z))
	end
	add(part(m,"Headlights",Vector3.new(sp.w-1.2,.45,.12),Color3.fromRGB(255,246,222),Enum.Material.Neon),CFrame.new(0,base+sp.body*.45,-sp.len/2-.05))
	add(part(m,"Taillights",Vector3.new(sp.w-1,.4,.12),Color3.fromRGB(190,30,30),Enum.Material.Neon),CFrame.new(0,base+sp.body*.5,sp.len/2+.05))
	if kind=="taxi" then add(part(m,"TaxiSign",Vector3.new(2.4,.7,1),Color3.fromRGB(255,244,206),Enum.Material.Neon),CFrame.new(0,base+sp.body+sp.cab+.6,sp.len*sp.cabZ)) end
	return {id=i,model=m,parts=parts,offs=offs,kind=kind,len=sp.len,width=sp.w,alive=false,lane=nil,a=0,v=0,vmax=sp.vmax*(.9+(h%20)/100),turn=nil,plan=nil,
		decided={},pos=Vector3.new(0,-500,0),look=Vector3.new(0,0,-1),leaderGap=math.huge,res=nil,cls=if sp.len<=13.5 then "s" elseif sp.len<=19.5 then "l" else "b",outFrom=nil,
		waitT=0,pendJ=nil,pendMove=nil}
end
CityLife.buildWalker=buildWalker
CityLife.buildCar=buildCar

------------------------------------------------------------------------------------------------ regions
local function laneRecords(net: Net): ({LaneRec},{[string]: {LaneRec}},number)
	local out: {LaneRec}={};local by: {[string]: {LaneRec}}={};local total=0
	for _,l in net.lanes do
		local r=l.road;local d=l.dir;local ext=r.beyond or 0
		local a0=if d>0 then r.a1-ext else r.a2+ext
		local a1=if d>0 then r.a2+ext else r.a1-ext
		local refs: {JRef}=table.clone(net.byRoad[r.id] or {})
		table.sort(refs,function(p,q) return p.a*d<q.a*d end)
		local tEnd: JRef?=nil
		local last=refs[#refs]
		if ext==0 and last and math.abs(last.a-a1)<=last.other.width/2+12 then tEnd=last end
		local rec: LaneRec={id=#out+1,lane=l,road=r,dir=d,a0=a0,a1=a1,len=math.abs(a1-a0),refs=refs,tEnd=tEnd,cars={},incoming={},outgoing={}}
		table.insert(out,rec);total+=rec.len
		by[r.id]=by[r.id] or {};table.insert(by[r.id],rec)
	end
	return out,by,total
end
local function getRegion(id: string): Region
	local cached=regionCache[id]
	if cached then return cached end
	local net=if id=="metro" then Plan.portMeridian() elseif id=="airport" then Plan.airportNet() else Plan.downtown()
	local lanes,by,total=laneRecords(net)
	local portals: {number}={}
	for _,n in net.nodes do if n.portal then table.insert(portals,n.id) end end
	local jEdges: {[number]: {WalkEdge}}={}
	for _,e in net.edges do
		local j=e.junction
		if j then jEdges[j.id]=jEdges[j.id] or {};table.insert(jEdges[j.id],e) end
	end
	local r: Region={id=id,net=net,lanes=lanes,roadLanes=by,laneTotal=total,occ={},occE={},seats={},rng=Random.new(Plan.SEED),candidates={},candTotal=0,
		portals=portals,box={},pend={},wclaim={},moves={},conf={},jEdges=jEdges}
	regionCache[id]=r
	return r
end
CityLife.getRegion=getRegion

------------------------------------------------------------------------------------------------ walkers
-- Street furniture beside the walk lines (MetroPlan.obstacles projected onto every edge: s along a->b, l to the
-- right of a->b): a walker whose lane would brush an obstacle steps to the nearest free lateral offset - inside
-- the edge's band if possible - ramping in over 2 studs before and after it.
local BODY_R=1.95 -- half the width over the swinging arms + margin
local AV_FULL,AV_RAMP=1.2,3.2
local avLo: {number},avHi: {number}={},{}
local function avBlocked(n: number,x: number): boolean
	for i=1,n do if x>avLo[i]+1e-6 and x<avHi[i]-1e-6 then return true end end
	return false
end
local function avoid(net: Net,e: WalkEdge,se: number,le: number): number
	local list=net.obs[e.id]
	if not list then return le end
	local n=0
	for _,o in list do
		if o.s1>se+AV_RAMP then break end
		local d=math.max(o.s1-se,se-o.s2,0)
		if d<AV_RAMP then
			local r=if d<=AV_FULL then BODY_R else BODY_R*(AV_RAMP-d)/(AV_RAMP-AV_FULL)
			n+=1;avLo[n]=o.l1-r;avHi[n]=o.l2+r
		end
	end
	if n==0 or not avBlocked(n,le) then return le end
	local hb=e.half+.6
	local best,bestD,bestIn=le,math.huge,false
	for i=1,n do
		for k=1,2 do
			local c=if k==1 then avLo[i] else avHi[i]
			if not avBlocked(n,c) then
				local inBand=math.abs(c)<=hb
				local dd=math.abs(c-le)
				if (inBand and not bestIn) or (inBand==bestIn and dd<bestD) then best,bestD,bestIn=c,dd,inBand end
			end
		end
	end
	return best
end
CityLife.avoid=avoid
local function walkerTarget(R: Region,w: Walker): (Vector3,Vector3)
	local e=w.edge
	local a,b=R.net.nodes[w.from].p,R.net.nodes[w.to].p
	if not e then return a,w.look end
	local dx,dz=b.X-a.X,b.Z-a.Z
	local L=math.sqrt(dx*dx+dz*dz)
	local ux,uz=if L>0 then dx/L else 0,if L>0 then dz/L else 1
	local t=math.clamp(w.s/math.max(e.len,.1),0,1)
	local lat=(.2+.8*w.lat)*e.half
	if R.net.obs[e.id] then
		if w.from==e.a then lat=avoid(R.net,e,w.s,lat) else lat=-avoid(R.net,e,e.len-w.s,-lat) end
	end
	local y=a.Y+(b.Y-a.Y)*t
	if e.junction and math.min(w.s,e.len-w.s)>3 then y=ROAD_Y end
	-- right-hand walking: offset to the right of the direction of travel
	return Vector3.new(a.X+dx*t-uz*lat,y,a.Z+dz*t+ux*lat),Vector3.new(ux,0,uz)
end
local function releaseCrossing(R: Region,w: Walker)
	local k=w.crossKey
	if k then R.occ[k]=math.max(0,(R.occ[k] or 1)-1);w.crossKey=nil end
	local ce=w.crossE
	if ce then R.occE[ce]=math.max(0,(R.occE[ce] or 1)-1);w.crossE=nil end
end
local function releaseSeat(R: Region,w: Walker)
	local b=w.benchNode
	if b then R.seats[b]=math.max(0,(R.seats[b] or 1)-1);w.benchNode=nil end
end
-- A walker held up by cars for WALK_PRIO s claims its zebra: cars that have waited less long do not get a box
-- path over it (the same age order as pending cars, so neither side starves and they never wait for each other).
local WALK_PRIO=6
local function unclaim(R: Region,w: Walker)
	local j=w.claimJ
	if not j then return end
	local list=R.wclaim[j]
	if list then local i=table.find(list,w);if i then table.remove(list,i) end end
	w.claimJ=nil
end
local function despawnWalker(R: Region,w: Walker)
	releaseCrossing(R,w);releaseSeat(R,w);unclaim(R,w)
	w.alive=false;w.edge=nil;w.mode="walk";w.model.Parent=nil
	w.pos=Vector3.new(w.pos.X,-400,w.pos.Z)
	stats.despawned+=1
end
-- Leaves node `n` on a random link (prefers going on straight; the edge it came by only at a dead end).
local function chooseNext(R: Region,w: Walker,n: number,came: WalkEdge?,heading: Vector3)
	unclaim(R,w)
	local node=R.net.nodes[n]
	local total=0
	local weights: {number}={}
	for i,eid in node.links do
		local e=R.net.edges[eid]
		local wgt=0
		if e~=came or #node.links==1 then
			local other=if e.a==n then e.b else e.a
			local op=R.net.nodes[other]
			local d=flat(op.p-node.p)
			local u=if d.Magnitude>0 then d.Unit else heading
			wgt=1+2.5*math.max(0,u:Dot(heading))
			if op.idle then wgt*=.7 end
			if op.portal then wgt*=.6 end
		end
		weights[i]=wgt;total+=wgt
	end
	local x=R.rng:NextNumber()*total
	local chosen=node.links[#node.links]
	for i,eid in node.links do
		x-=weights[i]
		if x<=0 and weights[i]>0 then chosen=eid;break end
	end
	local e=R.net.edges[chosen]
	w.edge=e;w.from=n;w.to=if e.a==n then e.b else e.a;w.s=0
	w.mode=if e.junction then "wait" else "walk";w.waitT=0
end
-- Signal (Port Meridian: enough walk time left) or gap (downtown: no moving car closing in on the crossing).
local function crossingOpen(R: Region,w: Walker,e: WalkEdge,now: number): boolean
	local j=e.junction :: Plan.Junction
	local axis=e.axis or j.rx.axis
	if R.net.signals then
		-- walkers step off during the first WALK_WINDOW s of the walk phase only (then the "don't walk" clearance):
		-- turning cars that yield to them get the rest of the green
		local wl=Plan.walkLeft(j,axis,now)
		return wl>=e.len/(w.speed*CROSS_HURRY)+.5 and wl>=Plan.GREEN-WALK_WINDOW
	end
	local road=if j.rx.axis==axis then j.rx else j.rz
	local p=R.net.nodes[w.from].p
	local cross=if road.axis=="x" then p.X else p.Z
	local lanes: {LaneRec}=R.roadLanes[road.id] or {}
	for _,lr in lanes do
		for _,c in lr.cars do
			local ahead=(cross-c.a)*lr.dir
			if c.v>2 and ahead>-8 and ahead<48 then return false end
		end
	end
	return true
end
CityLife.crossingOpen=crossingOpen
local function mayCross(R: Region,w: Walker,now: number): boolean
	local e=w.edge
	if not e then return true end
	local j=e.junction
	if not j then return true end
	local signals=R.net.signals
	local open=crossingOpen(R,w,e,now)
	if signals and not open then unclaim(R,w);return false end
	-- never in front of a car that holds the junction box on a path over this zebra, nor (downtown) of an older
	-- pending car; with signals walkers on the walk phase have right of way over turning cars (see tryReserve)
	local blocked=not open
	local box=R.box[j.id]
	if box and not blocked then for _,c in box do local mv=c.res;if mv and mv.cross[e.id] then blocked=true;break end end end
	local pend=R.pend[j.id]
	if pend and not blocked and not signals then
		for _,c in pend do
			local mv=c.pendMove
			if mv and mv.cross[e.id] and c.waitT>w.waitT and pendActive(R,mv,now) then blocked=true;break end
		end
	end
	if blocked then
		if w.waitT>WALK_PRIO and w.claimJ==nil then
			w.claimJ=j.id
			local list=R.wclaim[j.id];if not list then list={};R.wclaim[j.id]=list end
			table.insert(list,w)
		end
		return false
	end
	unclaim(R,w)
	return true
end
local function arrive(R: Region,w: Walker,now: number)
	releaseCrossing(R,w)
	local came=w.edge
	local n=w.to
	local node=R.net.nodes[n]
	local d=flat(node.p-R.net.nodes[w.from].p)
	local heading=if d.Magnitude>.01 then d.Unit else w.look
	if node.portal and w.age>14 and R.rng:NextNumber()<.55 then despawnWalker(R,w);return end
	local kind=node.idle
	if kind and w.idleCool<=0 then
		local chance=if kind=="bench" then .65 elseif kind=="shop" then .55 elseif kind=="bus" then .6 else .45
		if R.rng:NextNumber()<chance then
			local face=node.face or heading
			w.edge=nil;w.from=n;w.to=n;w.s=0
			if kind=="bench" and node.seat and (R.seats[n] or 0)<2 then
				local side=if (R.seats[n] or 0)==0 then -1 else 1
				R.seats[n]=(R.seats[n] or 0)+1;w.benchNode=n
				local right=Vector3.new(-face.Z,0,face.X)
				w.seat=(node.seat :: Vector3)+right*(side*1.4);w.mode="sit";w.look=face
				w.untilT=now+8+R.rng:NextNumber()*16
			elseif kind~="bench" then
				w.mode="idle";w.look=face;w.untilT=now+(if kind=="bus" then 10 else 4)+R.rng:NextNumber()*10
			else
				w.mode="walk"
			end
			if w.mode~="walk" then w.idleCool=25;return end
		end
	end
	chooseNext(R,w,n,came,heading)
end
local function stepWalker(R: Region,w: Walker,dt: number,now: number)
	w.age+=dt;w.idleCool-=dt
	if w.mode=="sit" or w.mode=="idle" then
		if now>=w.untilT then
			releaseSeat(R,w);w.seat=nil
			chooseNext(R,w,w.from,nil,-w.look)
		end
		return
	end
	if w.mode=="wait" then
		w.waitT+=dt
		if not mayCross(R,w,now) then return end
		local e=w.edge
		if e and e.junction then
			local k=e.junction.id..":"..(e.axis or "")
			R.occ[k]=(R.occ[k] or 0)+1;w.crossKey=k
			R.occE[e.id]=(R.occE[e.id] or 0)+1;w.crossE=e.id
		end
		w.mode="walk"
	end
	local e=w.edge
	if not e then return end
	local step=w.speed*dt*(if w.crossKey then CROSS_HURRY else 1)
	w.s+=step;w.phase+=step/STRIDE*math.pi*2
	if w.s>=e.len then arrive(R,w,now) end
end
local EYE_L,EYE_R=CFrame.new(-.22,.03,-.57),CFrame.new(.22,.03,-.57) -- on the face below the hair line
-- CFrames of one walker into the batch (walking / waiting / idling / sitting pose).
local function poseWalker(w: Walker,target: Vector3,look: Vector3,dt: number,now: number)
	local k=1-math.exp(-dt*10)
	w.pos=if w.snap then target else w.pos:Lerp(target,k)
	w.snap=false
	local f=flat(look);if f.Magnitude<.01 then f=Vector3.new(0,0,-1) end
	local P=w.pos
	if w.mode~="sit" and w.mode~="idle" then w.look=f.Unit end
	local root=CFrame.lookAt(P,P+f.Unit)
	local ps=w.parts
	if w.mode=="sit" then
		local torso=root*CFrame.new(0,2.8,.15)
		push(ps[1],torso);push(ps[2],root*CFrame.new(0,4.45,.15));push(ps[3],root*CFrame.new(0,4.62,.25))
		push(ps[4],root*CFrame.new(-1.45,3.6,.1)*CFrame.Angles(.45,0,0)*CFrame.new(0,-.85,0))
		push(ps[5],root*CFrame.new(1.45,3.6,.1)*CFrame.Angles(.45,0,0)*CFrame.new(0,-.85,0))
		push(ps[6],root*CFrame.new(-.5,2.3,-.3)*CFrame.Angles(math.pi/2,0,0)*CFrame.new(0,-1,0))
		push(ps[7],root*CFrame.new(.5,2.3,-.3)*CFrame.Angles(math.pi/2,0,0)*CFrame.new(0,-1,0))
		local i=8
		if w.shirt then push(ps[i],torso*CFrame.new(0,.15,-.53));i+=1 end
		if w.bag then push(ps[i],root*CFrame.new(1.7,2.25,.2)) end
		if w.near then local hd=root*CFrame.new(0,4.45,.15);push(w.eyes[1],hd*EYE_L);push(w.eyes[2],hd*EYE_R) end
		return
	end
	local swing,bob=0,0
	if w.mode=="walk" and not w.far then swing=.55*math.sin(w.phase);bob=math.abs(math.cos(w.phase))*.09 end
	if w.mode=="idle" then root=root*CFrame.Angles(0,math.sin(now*.6+w.sway)*.15,0) end
	local torso=root*CFrame.new(0,3+bob,0)
	push(ps[1],torso)
	local head=root*CFrame.new(0,4.65+bob,0)
	push(ps[2],head);push(ps[3],head*CFrame.new(0,.17,.1))
	local la=root*CFrame.new(-1.45,3.85+bob,0)*CFrame.Angles(-swing*.8,0,0)*CFrame.new(0,-.9,0)
	local ra=root*CFrame.new(1.45,3.85+bob,0)*CFrame.Angles(swing*.8,0,0)*CFrame.new(0,-.9,0)
	push(ps[4],la);push(ps[5],ra)
	push(ps[6],root*CFrame.new(-.5,2,0)*CFrame.Angles(swing,0,0)*CFrame.new(0,-1,0))
	push(ps[7],root*CFrame.new(.5,2,0)*CFrame.Angles(-swing,0,0)*CFrame.new(0,-1,0))
	local i=8
	if w.shirt then push(ps[i],torso*CFrame.new(0,.15,-.53));i+=1 end
	if w.bag then push(ps[i],ra*CFrame.new(0,-1.35,0)) end
	if w.near then push(w.eyes[1],head*EYE_L);push(w.eyes[2],head*EYE_R) end
end
-- Spawn walker w: on a random candidate edge (weighted by length) or out of a door portal.
local function spawnWalker(R: Region,w: Walker,focus: Vector3,initial: boolean,now: number): boolean
	local rng=R.rng
	if not initial and #R.portals>0 and rng:NextNumber()<.3 then
		local n=R.portals[rng:NextInteger(1,#R.portals)]
		local p=R.net.nodes[n].p
		local d=flatDist(p,focus)
		if d<CityLife.RADIUS and d>25 then
			w.alive=true;w.age=0;w.idleCool=10;w.pos=p;w.snap=true;w.nextAt=0;w.far=d>CityLife.FAR_LOD;setNear(w,not w.far);w.model.Parent=folder
			chooseNext(R,w,n,nil,R.net.nodes[n].face or Vector3.new(0,0,-1))
			w.lat=rng:NextNumber();stats.spawnedWalkers+=1
			return true
		end
	end
	if R.candTotal<=0 then return false end
	-- spots nearer the camera are preferred (density near the player ~2.2x the rim's: the crowd is where it is seen)
	local d0=if initial then 12 else CityLife.SPAWN_MIN
	for _=1,24 do
		local x=rng:NextNumber()*R.candTotal
		local e=R.candidates[#R.candidates]
		for _,c in R.candidates do x-=c.len;if x<=0 then e=c;break end end
		if not e.junction then
			local s=rng:NextNumber()*e.len
			local a,b=R.net.nodes[e.a].p,R.net.nodes[e.b].p
			local p=a:Lerp(b,s/e.len)
			local d=flatDist(p,focus)
			local near=1-NEAR_BIAS*math.clamp((d-d0)/(CityLife.RADIUS-d0),0,1)
			if d<=CityLife.RADIUS and d>=d0 and rng:NextNumber()<near then
				w.alive=true;w.age=0;w.idleCool=if initial then 0 else 6;w.mode="walk";w.waitT=0
				if rng:NextNumber()<.5 then w.from,w.to=e.a,e.b else w.from,w.to=e.b,e.a end
				w.edge=e;w.s=if w.from==e.a then s else e.len-s;w.lat=rng:NextNumber()
				w.pos=p;w.snap=true;w.nextAt=0;w.far=d>CityLife.FAR_LOD;setNear(w,not w.far);w.model.Parent=folder;stats.spawnedWalkers+=1
				return true
			end
		end
	end
	return false
end

------------------------------------------------------------------------------------------------ cars
local function laneAt(R: Region,road: Road,dir: number,index: number): LaneRec?
	local lanes: {LaneRec}=R.roadLanes[road.id] or {}
	for _,l in lanes do if l.dir==dir and l.lane.index==index then return l end end
	return nil
end
-- Target lane when turning from lane L onto road `o` towards `side` (right turn -> kerb lane, left -> inner).
local function turnLane(R: Region,L: LaneRec,o: Road,side: number): (LaneRec?,boolean)
	local h1=Plan.laneHeading(L.lane)
	local h2=if o.axis=="x" then Vector3.new(side,0,0) else Vector3.new(0,0,side)
	local right=(Vector3.new(-h1.Z,0,h1.X)-h2).Magnitude<.01
	return laneAt(R,o,side,if right then o.lanes else 1),right
end
local function turnFrom(R: Region,c: Car,L: LaneRec,ref: JRef,forced: boolean): CarPlan?
	local o=ref.other
	local opts: {number}={}
	for _,side in {-1,1} do if Plan.extends(o,L.road.c,side) then table.insert(opts,side) end end
	if #opts==0 then return nil end
	local side=opts[R.rng:NextInteger(1,#opts)]
	if forced and L.lane.count>1 and #opts==2 then
		-- T-end with two lanes: the kerb lane turns right, the inner lane left (their paths never cross)
		for _,sd in opts do
			local _,isRight=turnLane(R,L,o,sd)
			if isRight==(L.lane.index==L.lane.count) then side=sd end
		end
	end
	local to,right=turnLane(R,L,o,side)
	if not to then return nil end
	if not forced then
		-- only from the matching lane: right turns from the kerb lane, left turns from the inner lane - and no
		-- voluntary left turns from a single-lane approach (a car waiting for oncoming traffic would hold up the
		-- whole lane)
		if right and L.lane.index~=L.lane.count then return nil end
		if not right and (L.lane.index~=1 or L.lane.count==1) then return nil end
	end
	return {ref=ref,to=to}
end
local function enterLane(R: Region,c: Car,L: LaneRec,a: number)
	c.lane=L;c.a=a;c.turn=nil;c.plan=nil;c.decided={}
	table.insert(L.cars,c)
	for _,ref in L.refs do if math.abs(ref.a-a)<=ref.other.width/2+1 then c.decided[ref.j.id]=true end end
	local t=L.tEnd
	if t then c.plan=turnFrom(R,c,L,t,true);c.decided[t.j.id]=true end
end
local function leaveLane(c: Car)
	local L=c.lane
	if L then local i=table.find(L.cars,c);if i then table.remove(L.cars,i) end end
	c.lane=nil
end
-- A car that has waited WAIT_PRIO s at the line for the box becomes pending: younger requests whose paths conflict
-- with it and walkers on its zebras wait for it (no starvation at busy crossings; the oldest pending car is only
-- held up by reservations that are already running out).
local WAIT_PRIO=4
local function unpend(R: Region,c: Car)
	local j=c.pendJ
	if not j then return end
	local list=R.pend[j]
	if list then local i=table.find(list,c);if i then table.remove(list,i) end end
	c.pendJ=nil;c.pendMove=nil
end
local function releaseBox(R: Region,c: Car)
	local mv=c.res
	if not mv then return end
	local list=R.box[mv.j.id]
	if list then local i=table.find(list,c);if i then table.remove(list,i) end end
	c.res=nil
end
local function despawnCar(R: Region,c: Car)
	local t=c.turn
	if t then local i=table.find(t.to.incoming,c);if i then table.remove(t.to.incoming,i) end end
	releaseBox(R,c);unpend(R,c);c.waitT=0
	local of=c.outFrom
	if of then local i=table.find(of.outgoing,c);if i then table.remove(of.outgoing,i) end;c.outFrom=nil end
	leaveLane(c);c.alive=false;c.turn=nil;c.plan=nil;c.v=0;c.model.Parent=nil
	c.pos=Vector3.new(c.pos.X,-400,c.pos.Z)
	stats.despawned+=1
end
-- Can a car of length len enter lane L at coordinate a? Blocked by lane cars within [back, ahead] studs (centres),
-- a car behind that could no longer stop before the entering car's tail, a car ahead whose tail is within the
-- entering car's front + gap, or another car turning in nearby.
local function entryBlocked(L: LaneRec,a: number,back: number?,ahead: number?,len: number?): boolean
	local p=a*L.dir
	local b,f=back or 16,ahead or 20
	local half=(len or 0)/2
	for _,o in L.cars do
		local q=o.a*L.dir
		if q>p-b and q<p+f then return true end
		if q<=p then
			if (p-half)-(q+o.len/2)<o.v*o.v/(2*CAR_MAX_BRAKE*.8)+CAR_MIN_GAP then return true end
		elseif (q-o.len/2)-(p+half)<CAR_MIN_GAP then
			return true
		end
	end
	for _,o in L.incoming do
		local t=o.turn
		if t and math.abs(t.aE*L.dir-p)<b+f+half+o.len/2 then return true end
	end
	return false
end
-- Turn from lane L onto lane `to` at junction ref: quadratic Bezier from the near edge of the crossing road's
-- carriageway (sA on L) to the far edge of L's carriageway on the new road (eA on `to`).
local function turnGeom(L: LaneRec,ref: JRef,to: LaneRec): (Vector3,Vector3,Vector3,number)
	local o=ref.other
	local sA=ref.a-L.dir*(o.width/2)
	local eA=L.road.c+to.dir*(L.road.width/2)
	local s=Plan.lanePoint(L.lane,sA,ROAD_Y)
	local e=Plan.lanePoint(to.lane,eA,ROAD_Y)
	local cpt=if L.road.axis=="x" then Vector3.new(e.X,ROAD_Y,s.Z) else Vector3.new(s.X,ROAD_Y,e.Z)
	return s,cpt,e,eA
end
local function startTurn(c: Car,L: LaneRec,plan: CarPlan)
	local to=plan.to
	local s,cpt,e,eA=turnGeom(L,plan.ref,to)
	local len=((s-e).Magnitude+(s-cpt).Magnitude+(cpt-e).Magnitude)/2
	leaveLane(c)
	c.turn={s=s,c=cpt,e=e,u=0,len=math.max(len,4),to=to,aE=eA}
	table.insert(to.incoming,c)
	local of=c.outFrom
	if of and of~=L then local i=table.find(of.outgoing,c);if i then table.remove(of.outgoing,i) end end
	if of~=L then table.insert(L.outgoing,c) end
	c.outFrom=L
end
-- How far a car that turned out of lane L still reaches into L's band: the smallest progress (along L) of its body
-- corners, or nil once the body is clear of the band (follower half width + margin).
local function intrusion(L: LaneRec,o: Car): number?
	local f=o.look;local r=Vector3.new(-f.Z,0,f.X)
	local hl,hw=o.len/2,o.width/2
	local centre=Plan.lanePoint(L.lane,0,ROAD_Y)
	local minP,minL,maxL=math.huge,math.huge,-math.huge
	for k=1,4 do
		local q=o.pos+f*(if k<=2 then hl else -hl)+r*(if k%2==1 then hw else -hw)
		local along,lat
		if L.road.axis=="x" then along,lat=q.X*L.dir,q.Z-centre.Z else along,lat=q.Z*L.dir,q.X-centre.X end
		minP=math.min(minP,along);minL=math.min(minL,lat);maxL=math.max(maxL,lat)
	end
	if minL>4 or maxL< -4 then return nil end
	return minP
end

------------------------------------------------------------------------------------------------ junction boxes
-- Every car reserves the junction box before it passes the stop line (at its planning brake distance): the
-- reservation is granted when no walker is on a zebra its path crosses and no reserved car of another approach
-- lane has a conflicting path (pairs tested once on the real geometry and cached), and - so the box is never
-- blocked - when the exit lane has room. It is released once the car's tail has cleared the far zebra. Walkers
-- in turn never step onto a zebra a reserved path crosses. Cars that can no longer stop take the box anyway
-- (stats.forcedBox; they only occur after spawning inside an approach).
-- Size classes (length x width incl. a small margin) the swept cells are computed for.
local CLASS_DIM: {[string]: Vector2}={s=Vector2.new(13.5,6.9),l=Vector2.new(19.5,6.9),b=Vector2.new(28.5,7.7)}
local CELL=2
local function getMove(R: Region,L: LaneRec,ref: JRef,to: LaneRec?,cls: string): Move
	local j=ref.j
	local exit=to or L
	local key=j.id..":"..L.id..">"..exit.id..cls
	local cached=R.moves[key]
	if cached then return cached end
	local o=ref.other
	local dim=CLASS_DIM[cls]
	local hl,hw=dim.X/2,dim.Y/2
	local cells: {[number]: boolean}={}
	-- straight run of the body along lane lr, centre from progress p1 to p2: an axis-aligned band of cells
	local function laneRun(lr: LaneRec,p1: number,p2: number)
		local a1,a2=math.min(p1,p2)*lr.dir,math.max(p1,p2)*lr.dir
		local lo,hi=math.min(a1,a2)-hl,math.max(a1,a2)+hl
		local c=Plan.lanePoint(lr.lane,0,0)
		local x1,x2,z1,z2
		if lr.road.axis=="x" then x1,x2,z1,z2=lo,hi,c.Z-hw,c.Z+hw else x1,x2,z1,z2=c.X-hw,c.X+hw,lo,hi end
		for cx=math.floor(x1/CELL),math.floor(x2/CELL) do
			for cz=math.floor(z1/CELL),math.floor(z2/CELL) do cells[cx*100003+cz]=true end
		end
	end
	local rp=ref.a*L.dir
	local stopP=rp-(Plan.walkOff(o)+4.5)
	local release
	if to and to~=L then
		local s,cpt,e,eA=turnGeom(L,ref,to)
		laneRun(L,stopP-hl,(ref.a-L.dir*(o.width/2))*L.dir)
		-- the turn: the oriented body stamped along the Bezier (plain numbers: this runs once per movement)
		local sx,sz,qx,qz,ex,ez=s.X,s.Z,cpt.X,cpt.Z,e.X,e.Z
		local n=math.max(14,math.ceil(((s-cpt).Magnitude+(cpt-e).Magnitude)))
		for i=0,n do
			local u=i/n
			local px=sx*(1-u)^2+qx*(2*(1-u)*u)+ex*u*u
			local pz=sz*(1-u)^2+qz*(2*(1-u)*u)+ez*u*u
			local dx=(qx-sx)*(2*(1-u))+(ex-qx)*(2*u)
			local dz=(qz-sz)*(2*(1-u))+(ez-qz)*(2*u)
			local dl=math.sqrt(dx*dx+dz*dz)
			if dl<1e-3 then dx,dz,dl=1,0,1 end
			local fx,fz=dx/dl,dz/dl
			local u2=-hl
			while u2<=hl+1e-3 do
				local v=-hw
				while v<=hw+1e-3 do
					local uu,vv=math.min(u2,hl),math.min(v,hw)
					cells[math.floor((px+fx*uu-fz*vv)/CELL)*100003+math.floor((pz+fz*uu+fx*vv)/CELL)]=true
					v+=1.5
				end
				u2+=1.5
			end
		end
		local farA=L.road.c+to.dir*(Plan.walkOff(L.road)+3.5)
		laneRun(to,eA*to.dir,farA*to.dir+hl)
		release=farA*to.dir
	else
		release=rp+Plan.walkOff(o)+3.5
		laneRun(L,stopP-hl,release+hl)
	end
	-- zebra crossings whose walker band touches the swept cells (one cell of reach)
	local cross: {[number]: boolean}={}
	local jes: {WalkEdge}=R.jEdges[j.id] or {}
	for _,e in jes do
		local pa,pb=R.net.nodes[e.a].p,R.net.nodes[e.b].p
		local ax,az=pa.X,pa.Z
		local dx,dz=pb.X-ax,pb.Z-az
		local len=math.sqrt(dx*dx+dz*dz)
		if len>.01 then
			local fx,fz=dx/len,dz/len
			local hit=false
			local u=0
			while u<=len and not hit do
				local v=-e.half
				while v<=e.half+1e-3 and not hit do
					local vv=math.min(v,e.half)
					local cx,cz=math.floor((ax+fx*u-fz*vv)/CELL),math.floor((az+fz*u+fx*vv)/CELL)
					for ddx=-1,1 do
						for ddz=-1,1 do if cells[(cx+ddx)*100003+(cz+ddz)] then hit=true end end
					end
					v+=1
				end
				u+=1
			end
			if hit then cross[e.id]=true end
		end
	end
	local mv: Move={id=key,j=j,from=L,to=exit,cls=cls,cells=cells,cross=cross,release=release}
	R.moves[key]=mv
	return mv
end
CityLife.getMove=getMove
-- Do two movements of different approach lanes share a swept cell? (same approach lane: car following keeps the
-- cars apart, also behind a car turning out of the lane - see LaneRec.outgoing)
local function conflicts(R: Region,a: Move,b: Move): boolean
	if a.from==b.from then return false end
	local key=if a.id<b.id then a.id.."|"..b.id else b.id.."|"..a.id
	local known=R.conf[key]
	if known~=nil then return known end
	local hit=false
	for k in a.cells do if b.cells[k] then hit=true;break end end
	R.conf[key]=hit
	return hit
end
CityLife.conflicts=conflicts
local function tryReserve(R: Region,c: Car,L: LaneRec,ref: JRef,force: boolean,now: number): boolean
	local plan=c.plan
	local to=if plan and plan.ref==ref then plan.to else nil
	local mv=getMove(R,L,ref,to,c.cls)
	if not force then
		for eid in mv.cross do if (R.occE[eid] or 0)>0 then return false end end
		local list=R.box[ref.j.id]
		if list then
			for _,o in list do
				local om=o.res
				-- for a car going straight on, a holder that has already turned into this lane is just a car ahead
				-- (car following keeps them apart)
				if o~=c and om and not (to==nil and o.lane~=nil and o.lane==om.to and om.to==L) and conflicts(R,mv,om) then return false end
				-- one turning car per approach lane at a time (a second one would wait inside the box for the first)
				if o~=c and om and to and om.from==L and om.to~=L and o.lane~=om.to then return false end
			end
		end
		local pend=R.pend[ref.j.id]
		if pend then
			for _,o in pend do
				local om=o.pendMove
				if o~=c and om and o.waitT>c.waitT and pendActive(R,om,now) and conflicts(R,mv,om) then return false end
			end
		end
		if R.net.signals then
			-- walkers waiting on their walk phase go first (turning cars yield; they get the rest of the green)
			for _,w in walkers do
				local we=w.edge
				if w.alive and w.mode=="wait" and we and mv.cross[we.id] and crossingOpen(R,w,we,now) then return false end
			end
		end
		local claims=R.wclaim[ref.j.id]
		if claims then
			for _,w in claims do
				local we=w.edge
				if we and w.mode=="wait" and mv.cross[we.id] and w.waitT>c.waitT and (not R.net.signals or crossingOpen(R,w,we,now)) then return false end
			end
		end
		if to then
			if entryBlocked(to,L.road.c+to.dir*(L.road.width/2),nil,nil,c.len) then return false end
		else
			-- do not enter while the car ahead stands within one car length of the box exit
			local p=c.a*L.dir
			for _,o in L.cars do
				local q=o.a*L.dir
				if q>p and o.v<2 and q-o.len/2<mv.release+c.len+CAR_MIN_GAP then return false end
			end
		end
	else
		stats.forcedBox+=1
	end
	local list=R.box[ref.j.id]
	if not list then list={};R.box[ref.j.id]=list end
	table.insert(list,c);c.res=mv
	unpend(R,c);c.waitT=0
	return true
end
local function stepCar(R: Region,c: Car,dt: number,now: number)
	local t=c.turn
	if t then
		c.v=math.min(c.v+CAR_ACCEL*dt,TURN_SPEED)
		t.u+=c.v*dt/t.len
		if t.u>=1 then
			local i=table.find(t.to.incoming,c);if i then table.remove(t.to.incoming,i) end
			enterLane(R,c,t.to,t.aE)
			c.pos=Plan.lanePoint(t.to.lane,t.aE,ROAD_Y);c.look=Plan.laneHeading(t.to.lane)
		else
			local u=t.u
			c.pos=t.s*(1-u)^2+t.c*(2*(1-u)*u)+t.e*(u*u)
			local d=(t.c-t.s)*(2*(1-u))+(t.e-t.c)*(2*u)
			if d.Magnitude>.01 then c.look=d.Unit end
		end
		return
	end
	local L=c.lane
	if not L then return end
	local prog=c.a*L.dir
	local front=prog+c.len/2
	local gap=c.leaderGap
	local turnAt: number?=nil
	for _,ref in L.refs do
		local o=ref.other
		local rp=ref.a*L.dir
		if prog>=rp+o.width/2-.5 then continue end
		local stopP=rp-(Plan.walkOff(o)+4.5)
		local mv=c.res
		local held=mv~=nil and mv.j==ref.j
		-- decide on a turn 60 studs before the stop line (before the box is reserved for the movement)
		if not c.decided[ref.j.id] and stopP-front<60 then
			c.decided[ref.j.id]=true
			if not held and R.rng:NextNumber()<.22 then
				local p=turnFrom(R,c,L,ref,false)
				if p then c.plan=p end
			end
		end
		local plan=c.plan
		local turning=plan~=nil and plan.ref==ref
		if turning then turnAt=rp-o.width/2 end
		if front<=stopP+1 then
			local dist=stopP-front
			local canStop=c.v*c.v/(2*CAR_MAX_BRAKE*.8)<dist+.5
			local stop=false
			if R.net.signals then
				-- stop unless the car reaches the line while it is still green, or can no longer stop before it
				local g=Plan.greenLeft(ref.j,L.road.axis,now)
				if g<=dist/math.max(c.v,1)+.3 and canStop then stop=true end
			end
			if stop then
				if held then releaseBox(R,c);held=false end
			elseif not held and dist<c.v*c.v/(2*CAR_PLAN_BRAKE)+12 then
				-- inside the planning distance: reserve the junction box or plan to stop at the line
				held=tryReserve(R,c,L,ref,false,now)
				if not held and not canStop then held=tryReserve(R,c,L,ref,true,now) end
				if not held then
					stop=true
					if c.v<1 then c.waitT+=dt end
					if c.waitT>WAIT_PRIO and c.pendJ~=ref.j.id then
						unpend(R,c)
						local pl=c.plan
						c.pendJ=ref.j.id;c.pendMove=getMove(R,L,ref,if pl and pl.ref==ref then pl.to else nil,c.cls)
						local pl2=R.pend[ref.j.id];if not pl2 then pl2={};R.pend[ref.j.id]=pl2 end
						table.insert(pl2,c)
					end
				end
			end
			if stop then gap=math.min(gap,dist) end
		elseif not held then
			held=tryReserve(R,c,L,ref,true,now) -- already past the line (spawned in the approach): take the box
		end
		break
	end
	local plan=c.plan
	if turnAt and plan and turnAt-prog<40 then
		-- the target lane can fill up after the stop line was passed: wait at the turn point until it is clear
		if not entryBlocked(plan.to,L.road.c+plan.to.dir*(L.road.width/2),nil,nil,c.len) then
			if prog>=turnAt then startTurn(c,L,plan);return end
		else
			gap=math.min(gap,math.max(0,turnAt-.5-prog)+CAR_MIN_GAP)
		end
	end
	if prog>=L.a1*L.dir then despawnCar(R,c);return end
	local target=math.min(c.vmax,math.sqrt(2*CAR_PLAN_BRAKE*math.max(0,gap-CAR_MIN_GAP)))
	if turnAt then target=math.min(target,TURN_SPEED+math.max(0,turnAt-prog)*.6) end
	if c.v<target then c.v=math.min(target,c.v+CAR_ACCEL*dt) else c.v=math.max(target,c.v-CAR_MAX_BRAKE*dt) end
	c.a+=L.dir*c.v*dt
	c.pos=Plan.lanePoint(L.lane,c.a,ROAD_Y);c.look=Plan.laneHeading(L.lane)
	-- the tail has cleared the box (and the far zebra): free the reservation
	local rs=c.res
	if rs and rs.to==L and c.a*L.dir-c.len/2>rs.release then releaseBox(R,c) end
end
local function poseCar(c: Car)
	local base=CFrame.lookAt(c.pos,c.pos+c.look)
	for i,p in c.parts do push(p,base*c.offs[i]) end
end
-- Spawn spots keep clear of junctions and of the 60 studs before each stop line (a car spawning there at speed
-- could not stop for a red light).
local function nearJunction(L: LaneRec,a: number): boolean
	local p=a*L.dir
	for _,ref in L.refs do
		local rp=ref.a*L.dir
		if p>rp-(Plan.walkOff(ref.other)+4.5)-60 and p<rp+ref.other.width/2+8 then return true end
	end
	return false
end
local function spawnCar(R: Region,c: Car,focus: Vector3,initial: boolean): boolean
	local rng=R.rng
	for _=1,14 do
		local x=rng:NextNumber()*R.laneTotal
		local L=R.lanes[#R.lanes]
		for _,l in R.lanes do x-=l.len;if x<=0 then L=l;break end end
		if c.kind=="bus" and L.lane.index~=L.lane.count then continue end
		local a=L.a0+(L.a1-L.a0)*rng:NextNumber()
		local p=Plan.lanePoint(L.lane,a,ROAD_Y)
		local d=flatDist(p,focus)
		if d<=CityLife.RADIUS+30 and d>=(if initial then 30 else 150) and not nearJunction(L,a) and not entryBlocked(L,a,45,25,c.len) then
			c.alive=true;c.v=c.vmax*.6;enterLane(R,c,L,a);c.model.Parent=folder
			c.pos=p;c.look=Plan.laneHeading(L.lane);stats.spawnedCars+=1
			return true
		end
	end
	return false
end

------------------------------------------------------------------------------------------------ Port Meridian extras
local function signalColor(R: Region,p: BasePart,now: number)
	local jid=p:GetAttribute("Junction");local axis=p:GetAttribute("Axis")
	if typeof(jid)~="number" or typeof(axis)~="string" then return end
	local j=R.net.junctions[jid]
	if not j then return end
	local g=Plan.greenLeft(j,axis,now)
	local col=if g>3 then Color3.fromRGB(70,214,110) elseif g>0 then Color3.fromRGB(246,176,46) else Color3.fromRGB(220,46,46)
	if p.Color~=col then p.Color=col end
end
-- Office window panels light up on about half the towers at night (whole lit facades read as light boxes);
-- the rest only darken. Shop fronts, the spire, cafés and the crown always light up.
local WINDOW_PARTS={Windows=true,WindowGlow=true,GlassBand=true,FarTower=true,Impostor=true}
local function nightLook(p: BasePart,look: Look)
	if look.lit then p.Material=Enum.Material.Neon;p.Color=look.glow;p.Transparency=math.min(look.transparency,.15)
	else p.Color=look.color:Lerp(Color3.fromRGB(20,24,30),.55) end
end
local function registerGlow(p: BasePart,glow: Color3)
	if glowParts[p] then return end
	local h=Plan.hash(string.format("%d:%d",math.floor(p.Position.X),math.floor(p.Position.Z+p.Position.Y)))
	local lit=not WINDOW_PARTS[p.Name] or h%20<9
	local look: Look={color=p.Color,material=p.Material,transparency=p.Transparency,glow=glow:Lerp(Color3.fromRGB(40,42,50),.1+(h%6)*.08),lit=lit}
	glowParts[p]=look
	if night then nightLook(p,look) end
end
local function setNight(on: boolean)
	if night==on then return end
	night=on
	for p,look in glowParts do
		if p.Parent then
			if on then nightLook(p,look)
			else p.Material=look.material;p.Color=look.color;p.Transparency=look.transparency end
		end
	end
end
CityLife.setNight=setNight
-- Day / night look of a glow part that was (re)parented while the mode was already set.
local function applyLook(p: BasePart)
	local look=glowParts[p]
	if not look then return end
	if night then nightLook(p,look) else p.Material=look.material;p.Color=look.color;p.Transparency=look.transparency end
end
local function isNight(): boolean
	local t=Lighting.ClockTime
	return t<6.3 or t>18.2
end
local function registerWheel(m: Instance)
	local hub=m:GetAttribute("Hub")
	if typeof(hub)~="Vector3" then return end
	local w: Wheel={model=m,hub=hub,parts={}}
	for _,d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local a=d:GetAttribute("WheelAngle");local r=d:GetAttribute("WheelR")
			if typeof(a)=="number" and typeof(r)=="number" then
				local hang=d:GetAttribute("Hang")
				table.insert(w.parts,{part=d,angle=a,r=r,kind=d.Name,hang=if typeof(hang)=="number" then hang else 0})
			end
		end
	end
	wheels[m]=w
end
local WHEEL_SPEED=math.pi*2/240 -- one turn in four minutes
local function poseWheels(focus: Vector3,now: number)
	for m,w in wheels do
		if not m.Parent then wheels[m]=nil;continue end
		if flatDist(w.hub,focus)>900 then continue end
		local off=now*WHEEL_SPEED
		for _,wp in w.parts do
			if not wp.part.Parent then continue end
			local a=wp.angle+off
			local p=w.hub+Vector3.new(math.cos(a)*wp.r,math.sin(a)*wp.r-wp.hang,0)
			if wp.kind=="WheelRim" then push(wp.part,CFrame.new(p)*CFrame.Angles(0,0,a+math.pi/2))
			elseif wp.kind=="WheelSpoke" then push(wp.part,CFrame.new(p)*CFrame.Angles(0,0,a))
			else push(wp.part,CFrame.new(p)) end
		end
	end
end
CityLife.poseWheels=poseWheels
CityLife.registerWheel=registerWheel

-- Client-only scenery beyond Port Meridian's walls: ground, road continuations, low skyline shells; impostors
-- for every server tower (shown while that tower is streamed out on this client).
local FAR_TINTS={Color3.fromRGB(104,128,148),Color3.fromRGB(132,142,152),Color3.fromRGB(156,150,140),Color3.fromRGB(96,110,122),Color3.fromRGB(150,146,138),Color3.fromRGB(118,130,124)}
-- the server towers' palettes (MetroBuilder GLASS_TINTS / STONE_TONES / PLASTER_TONES, by lot tone)
local GLASS_TINTS={Color3.fromRGB(110,150,176),Color3.fromRGB(80,132,138),Color3.fromRGB(150,128,98),Color3.fromRGB(104,114,126),Color3.fromRGB(128,160,150),Color3.fromRGB(168,180,192)}
local STONE_TONES={Color3.fromRGB(216,212,201),Color3.fromRGB(200,188,168),Color3.fromRGB(184,172,156),Color3.fromRGB(226,220,208),Color3.fromRGB(168,158,148),Color3.fromRGB(232,224,210)}
local PLASTER_TONES={Color3.fromRGB(238,234,224),Color3.fromRGB(226,214,196),Color3.fromRGB(214,222,226),Color3.fromRGB(232,220,206),Color3.fromRGB(206,198,190),Color3.fromRGB(244,240,232)}
local WINDOW_GLOW=Color3.fromRGB(136,104,66)
local GATE_STONE=Color3.fromRGB(214,208,194)
local BRONZE=Color3.fromRGB(128,92,56)
local GOLD=Color3.fromRGB(212,172,86)
local NAVY=Color3.fromRGB(30,44,74)
local SHADE=Color3.fromRGB(10,11,13)
local function cityPath(names: {string}): () -> boolean
	return function(): boolean
		local cur: Instance?=workspace:FindFirstChild("WorldCity")
		for _,n in names do
			if not cur then return false end
			cur=cur:FindFirstChild(n)
		end
		return cur~=nil and #cur:GetChildren()>=3
	end
end
local function boxPart(m: Instance,name: string,x1: number,x2: number,y1: number,y2: number,z1: number,z2: number,color: Color3,material: Enum.Material?): Part
	local p=part(m,name,Vector3.new(math.abs(x2-x1),y2-y1,math.abs(z2-z1)),color,material)
	p.CFrame=CFrame.new((x1+x2)/2,(y1+y2)/2,(z1+z2)/2)
	return p
end
local function signText(p: BasePart,face: Enum.NormalId,text: string,ink: Color3)
	local g=Instance.new("SurfaceGui");g.Face=face;g.LightInfluence=0
	g.CanvasSize=Vector2.new(math.clamp(p.Size.Z*40,120,1600),math.clamp(p.Size.Y*40,40,900));g.Parent=p
	local t=Instance.new("TextLabel");t.BackgroundTransparency=1;t.Size=UDim2.fromScale(1,1);t.Text=text;t.TextScaled=true;t.TextWrapped=true
	t.Font=Enum.Font.BuilderSansBold;t.TextColor3=ink;t.Parent=g
end
-- Tunnel gate at a through street's end (MetroPlan.TUNNELS): a stone gate building beyond the boundary wall whose
-- city face stands on the wall line - the carriageway disappears into a dark mouth, the sidewalks into lit
-- pedestrian passages (walker portals), so the street visibly ends and traffic enters / leaves out of sight.
local TUNNEL_NAMES={pm_arrivals="AIRPORT TUNNEL",pm_exchange="EXCHANGE TUNNEL",pm_harbour="HARBOUR TUNNEL"}
local function buildGate(m: Model,t: Plan.Tunnel)
	local r=t.road;local sd=t.side
	local x0,x1=t.x,t.x+sd*t.depth -- city face, back
	local top=G+t.height
	local kerb=r.width/2;local outer=r.width/2+r.walk
	local walkTop=City.WALK_TOP
	for _,zs in {-1,1} do
		-- side block (beyond the sidewalk), pier over the sidewalk passage, the passage's dark recess
		boxPart(m,"TunnelGate",x0,x1,G,top,r.c+zs*outer,r.c+zs*(t.z2-r.c),GATE_STONE,Enum.Material.Limestone)
		boxPart(m,"TunnelGate",x0,x1,walkTop+10,top,r.c+zs*kerb,r.c+zs*outer,GATE_STONE,Enum.Material.Limestone)
		boxPart(m,"TunnelShade",x0+sd*1.5,x1,walkTop,walkTop+10,r.c+zs*kerb,r.c+zs*outer,SHADE)
		boxPart(m,"TunnelLight",x0+sd*.05,x0+sd*.25,walkTop+9.4,walkTop+9.8,r.c+zs*(kerb+.6),r.c+zs*(outer-.6),GOLD,Enum.Material.Neon)
	end
	-- lintel over the mouth, the mouth's dark tube (cars inside it are hidden), the lit mouth frame
	boxPart(m,"TunnelGate",x0,x1,ROAD_Y+t.mouth,top,r.c-kerb,r.c+kerb,GATE_STONE,Enum.Material.Limestone)
	boxPart(m,"TunnelShade",x0+sd*2.5,x1,ROAD_Y-.2,ROAD_Y+t.mouth,r.c-kerb,r.c+kerb,SHADE)
	boxPart(m,"TunnelLight",x0+sd*.05,x0+sd*.3,ROAD_Y+t.mouth-.7,ROAD_Y+t.mouth-.2,r.c-kerb+.5,r.c+kerb-.5,Color3.fromRGB(255,226,170),Enum.Material.Neon)
	-- facade articulation: granite plinth, pilasters framing mouth and passages, an attic storey over the mouth
	local GRANITE=Color3.fromRGB(120,116,110)
	boxPart(m,"TunnelPlinth",x0-sd*.5,x0+sd*.5,G,G+3.2,t.z1-.3,r.c-outer-1.2,GRANITE,Enum.Material.Granite)
	boxPart(m,"TunnelPlinth",x0-sd*.5,x0+sd*.5,G,G+3.2,r.c+outer+1.2,t.z2+.3,GRANITE,Enum.Material.Granite)
	for _,zz in {r.c-outer-1.2,r.c-kerb-.2,r.c+kerb+.2,r.c+outer+1.2} do
		boxPart(m,"TunnelPilaster",x0-sd*.8,x0+sd*.5,G,top-1.6,zz-1.25,zz+1.25,GRANITE:Lerp(GATE_STONE,.45),Enum.Material.Granite)
	end
	boxPart(m,"TunnelAttic",x0+sd*3,x1,top,top+7,r.c-kerb-2,r.c+kerb+2,GATE_STONE:Lerp(Color3.new(1,1,1),.1),Enum.Material.Limestone)
	boxPart(m,"TunnelAtticBand",x0+sd*2.6,x0+sd*3.2,top+5.4,top+6.2,r.c-kerb-2,r.c+kerb+2,GOLD,Enum.Material.Neon)
	-- bronze cornice, gold band, name panel over the mouth (facing the city)
	boxPart(m,"TunnelCornice",x0-sd*.6,x1,top-1.6,top,t.z1-.6,t.z2+.6,BRONZE,Enum.Material.Metal)
	boxPart(m,"TunnelBand",x0-sd*.3,x0+sd*.2,ROAD_Y+t.mouth+1,ROAD_Y+t.mouth+1.5,t.z1,t.z2,GOLD,Enum.Material.Neon)
	local panel=boxPart(m,"TunnelSign",x0-sd*.5,x0,ROAD_Y+t.mouth+3,ROAD_Y+t.mouth+9,r.c-math.min(kerb,15),r.c+math.min(kerb,15),NAVY,Enum.Material.Metal)
	signText(panel,if sd<0 then Enum.NormalId.Right else Enum.NormalId.Left,(TUNNEL_NAMES[r.id] or "CITY TUNNEL").."\n"..(if sd<0 then "WEST GATE" else "EAST GATE"),Color3.fromRGB(240,226,190))
end
local function buildFar(): Model
	local m=Instance.new("Model");m.Name="MetroFarSkyline"
	local ground=Color3.fromRGB(150,150,140)
	for _,r in Plan.FAR_GROUND do
		local p=part(m,"FarGround",Vector3.new(r.x2-r.x1,2,r.z2-r.z1),ground,Enum.Material.Concrete)
		p.CFrame=CFrame.new((r.x1+r.x2)/2,G-1,(r.z1+r.z2)/2)
	end
	for _,r in Plan.ROADS do
		local ext=r.beyond
		if ext and r.axis=="x" then
			for _,side in {-1,1} do
				local x1=if side<0 then r.a1-ext else r.a2
				local x2=if side<0 then r.a1 else r.a2+ext
				local road=part(m,"FarRoad",Vector3.new(x2-x1,.2,r.width),Color3.fromRGB(46,49,52),Enum.Material.Asphalt)
				road.CFrame=CFrame.new((x1+x2)/2,ROAD_Y-.1,r.c)
				for _,sd in {-1,1} do
					local walk=part(m,"FarSidewalk",Vector3.new(x2-x1,.5,r.walk),Color3.fromRGB(196,188,172),Enum.Material.Pavement)
					walk.CFrame=CFrame.new((x1+x2)/2,City.WALK_TOP-.25,r.c+sd*(r.width/2+r.walk/2))
				end
				local line=part(m,"FarLine",Vector3.new(x2-x1,.04,.3),Color3.fromRGB(226,186,80),Enum.Material.SmoothPlastic)
				line.CFrame=CFrame.new((x1+x2)/2,ROAD_Y+.02,r.c)
			end
		end
	end
	for _,t in Plan.TUNNELS do buildGate(m,t) end
	for _,f in Plan.FAR do
		local col=FAR_TINTS[f.tone]
		local p=part(m,"FarTower",Vector3.new(f.w,f.h,f.d),if f.glass then col else col:Lerp(Color3.fromRGB(200,194,182),.15),if f.glass then Enum.Material.Glass else Enum.Material.Concrete)
		p.CFrame=CFrame.new(f.x,G+f.h/2,f.z)
		if f.glass then registerGlow(p,Color3.fromRGB(104,86,62)) end -- far shells: a dim glow only (whole boxes light up)
		if f.crown then
			local c=part(m,"FarCrown",Vector3.new(f.w*.5,8,f.d*.5),Color3.fromRGB(110,112,116),Enum.Material.Metal)
			c.CFrame=CFrame.new(f.x,G+f.h+4,f.z)
		end
	end
	-- impostors (inset 1 stud) for the background lots, the client towers and the hotel: the tower's material and
	-- tint, its silhouette (drum as a cylinder, stepped with its setback, needles / crowns of the spire, drum and
	-- twist towers) and the same night glow as its windows; shown (parented) only while the tower is streamed out
	local function impostor(cf: CFrame,size: Vector3,color: Color3,material: Enum.Material,present: () -> boolean,glow: boolean,shape: Enum.PartType?): Impostor
		local p=part(m,"Impostor",if shape then Vector3.new(size.Y-1,size.X-2,size.Z-2) else size-Vector3.new(2,1,2),color,material,shape)
		p.CFrame=if shape then cf*CFrame.new(0,-.5,0)*CFrame.Angles(0,0,math.pi/2) else cf*CFrame.new(0,-.5,0)
		if glow then registerGlow(p,WINDOW_GLOW) end
		local imp: Impostor={part=p,parts={p},shown=true,present=present}
		table.insert(impostors,imp)
		return imp
	end
	local function extra(imp: Impostor,name: string,size: Vector3,cf: CFrame,color: Color3,material: Enum.Material)
		local p=part(m,name,size,color,material)
		p.CFrame=cf
		table.insert(imp.parts,p)
	end
	for _,l in Plan.LOTS do
		local glassy=l.style=="glass" or l.style=="slab" or l.style=="drum" or l.style=="twist"
		local col=if glassy then GLASS_TINTS[l.tone] elseif l.style=="res" then PLASTER_TONES[l.tone] elseif l.style=="low" then Color3.fromRGB(226,222,210) else STONE_TONES[l.tone]
		local mat=if glassy then Enum.Material.Glass elseif l.style=="res" then Enum.Material.Plaster elseif l.style=="low" then Enum.Material.Concrete else Enum.Material.Limestone
		local present=cityPath({"PortMeridian","CityBlocks","Tower_"..l.id})
		local top=G+l.h
		local imp: Impostor
		if l.style=="drum" then
			local dia=math.min(l.w,l.d)-4
			imp=impostor(CFrame.new(l.x,G+l.h/2,l.z),Vector3.new(dia+2,l.h,dia+2),col,mat,present,l.glow,Enum.PartType.Cylinder)
		elseif l.style=="stepped" then
			local y1=G+12+(top-G-12)*.55
			imp=impostor(CFrame.new(l.x,(G+y1)/2,l.z),Vector3.new(l.w,y1-G,l.d),col,mat,present,l.glow)
			extra(imp,"ImpostorSetback",Vector3.new(math.max(4,l.w-16),top-y1,math.max(4,l.d-16)),CFrame.new(l.x,(y1+top)/2,l.z),GLASS_TINTS[l.tone],Enum.Material.Glass)
		else
			imp=impostor(CFrame.new(l.x,G+l.h/2,l.z),Vector3.new(l.w,l.h,l.d),col,mat,present,l.glow)
		end
		-- 1-part crown proxies: needles (spire crown, drum), the twist's gold crown
		if l.style=="drum" then
			extra(imp,"ImpostorNeedle",Vector3.new(1.6,50,1.6),CFrame.new(l.x,top+26,l.z),Color3.fromRGB(150,154,160),Enum.Material.Metal)
		elseif l.style=="twist" then
			local sz=(math.min(l.w,l.d)-6)*.6
			extra(imp,"ImpostorCrown",Vector3.new(sz,8,sz),CFrame.new(l.x,top+4,l.z),GOLD,Enum.Material.Neon)
		elseif l.crown=="spire" then
			local nh=14+math.min(60,l.h*.22)
			extra(imp,"ImpostorNeedle",Vector3.new(1.4,nh,1.4),CFrame.new(l.x,top+nh/2,l.z),Color3.fromRGB(150,154,160),Enum.Material.Metal)
		end
	end
	for _,b in City.BUILDINGS do
		if b.zone=="abroad" then
			local fh=if b.interior=="hotel" then 12 else City.OFFICE.floorHeight
			local h=City.OFFICE.groundHeight+1+(b.floors-1)*fh+1.2
			local cf=b.frame*CFrame.new(0,0,b.depth/2)
			local path=if b.kind=="hotel" then {"PortMeridian","Hotel_"..b.id,"Shell"} else {"PortMeridian","ClientTowers","ClientTower_"..b.id,"Shell"}
			impostor(CFrame.new(cf.X,G+h/2,cf.Z)*cf.Rotation,Vector3.new(b.width,h,b.depth),Color3.fromRGB(150,170,186),Enum.Material.Glass,cityPath(path),true)
		end
	end
	return m
end
local function updateImpostors()
	local fm=farModel
	for _,imp in impostors do
		local show=not imp.present()
		if show~=imp.shown then
			imp.shown=show
			for _,p in imp.parts do
				p.Parent=if show then fm else nil
				if show then applyLook(p) end
			end
		end
	end
end
CityLife.buildFar=buildFar
CityLife.updateImpostors=updateImpostors

------------------------------------------------------------------------------------------------ activation
local function ensureFolder(): Model
	local f=folder
	if f then return f end
	local m=Instance.new("Model");m.Name="CityLife"
	folder=m
	return m
end
local function refreshCandidates(R: Region,focus: Vector3)
	table.clear(R.candidates);R.candTotal=0
	local r=CityLife.RADIUS
	for _,e in R.net.edges do
		local a,b=R.net.nodes[e.a].p,R.net.nodes[e.b].p
		if not e.junction and flatDist((a+b)/2,focus)<r+e.len/2 then table.insert(R.candidates,e);R.candTotal+=e.len end
	end
end
-- Releases the region (every walker / car back to the pool, folders unparented); the step connection stays.
local function releaseRegion()
	local R=region
	if R then
		for _,w in walkers do if w.alive then despawnWalker(R,w) end end
		for _,c in cars do if c.alive then despawnCar(R,c) end end
		table.clear(R.occ);table.clear(R.occE);table.clear(R.seats);table.clear(R.box);table.clear(R.pend);table.clear(R.wclaim)
	end
	region=nil
	local f=folder;if f then f.Parent=nil end
	local fm=farModel;if fm then fm.Parent=nil end
	stats.region="none";stats.walkers=0;stats.cars=0
end
-- Leaving both regions: release + cut the per-frame step (the 0.5 s monitor reconnects it on entry).
local function deactivate()
	releaseRegion()
	local conn=stepConn;if conn then conn:Disconnect();stepConn=nil end
end
CityLife.deactivate=deactivate
-- Fills both pools up to the region's caps (instances are created once and reused).
local function activate(id: string,focus: Vector3)
	if region and region.id==id then return end
	-- switching regions (or the first fill) keeps the step connection that is calling us
	releaseRegion()
	local R=getRegion(id)
	R.rng=Random.new(Plan.SEED+(if id=="metro" then 1 elseif id=="downtown" then 2 else 3))
	region=R
	acc,scanAcc,signalAcc,wheelAcc=0,0,0,0
	local f=ensureFolder()
	local caps=CityLife.CAPS[id]
	while #walkers<caps.walkers do table.insert(walkers,buildWalker(f,#walkers+1)) end
	while #cars<caps.cars do table.insert(cars,buildCar(f,#cars+1)) end
	f.Parent=workspace
	if id=="metro" then
		local fm: Model=farModel or buildFar()
		farModel=fm
		fm.Parent=workspace
		updateImpostors()
	end
	refreshCandidates(R,focus)
	for i=1,caps.walkers do spawnWalker(R,walkers[i],focus,true,0) end
	for i=1,caps.cars do spawnCar(R,cars[i],focus,true) end
	stats.region=id
end
CityLife.activate=activate
-- Region check + spawning / recycling (every SCAN seconds).
local function scan(focus: Vector3,now: number)
	local id=Plan.regionAt(focus)
	if not id then if region then deactivate() end;return end
	if not region or region.id~=id then activate(id,focus) end
	local R=region :: Region
	refreshCandidates(R,focus)
	local caps=CityLife.CAPS[R.id]
	local spawned=0
	local nw,nc=0,0
	for i=1,caps.walkers do
		local w=walkers[i]
		if w.alive and flatDist(w.pos,focus)>CityLife.DESPAWN then despawnWalker(R,w) end
		if not w.alive and spawned<6 then if spawnWalker(R,w,focus,false,now) then spawned+=1 end end
		if w.alive then nw+=1;w.far=flatDist(w.pos,focus)>CityLife.FAR_LOD;setNear(w,not w.far) end
	end
	for i=1,caps.cars do
		local c=cars[i]
		if c.alive and flatDist(c.pos,focus)>CityLife.DESPAWN+40 then despawnCar(R,c) end
		if not c.alive and spawned<9 then if spawnCar(R,c,focus,false) then spawned+=1 end end
		if c.alive then nc+=1 end
	end
	stats.walkers=nw;stats.cars=nc
	if R.id=="metro" then updateImpostors() end
end
CityLife.scan=scan

-- One simulation step (dt seconds) + the CFrame batch. Returns the batch (parts, cframes) after BulkMoveTo.
local function step(dt: number,now: number,focus: Vector3): ({BasePart},{CFrame})
	table.clear(batchParts);table.clear(batchFrames)
	local R=region
	if not R then return batchParts,batchFrames end
	local t0=os.clock()
	local caps=CityLife.CAPS[R.id]
	-- car following: per lane, sorted by progress
	for _,L in R.lanes do
		local list=L.cars
		if #list>1 then table.sort(list,function(p,q) return p.a*L.dir<q.a*L.dir end) end
		-- cars that turned out of this lane block it until their body has left its band
		local intr: {number}={}
		for k=#L.outgoing,1,-1 do
			local o=L.outgoing[k]
			local ip=if o.alive then intrusion(L,o) else nil
			if ip then table.insert(intr,ip)
			elseif not (o.turn and o.outFrom==L and o.turn.u<.5) then
				table.remove(L.outgoing,k);if o.outFrom==L then o.outFrom=nil end
			end
		end
		for i,c in list do
			local nxt=list[i+1]
			local back=c.a*L.dir+c.len/2
			local gap=if nxt then (nxt.a*L.dir-nxt.len/2)-back else math.huge
			-- a car turning into this lane appears at its entry point: brake for it
			for _,o in L.incoming do
				local t=o.turn
				if t then
					local q=t.aE*L.dir-o.len/2
					if q>c.a*L.dir then gap=math.min(gap,q-back) end
				end
			end
			for _,ip in intr do if ip>c.a*L.dir then gap=math.min(gap,ip-back) end end
			c.leaderGap=gap
		end
	end
	for i=1,caps.cars do
		local c=cars[i]
		if c.alive then
			stepCar(R,c,dt,now)
			if c.alive then poseCar(c) end
		end
	end
	for i=1,caps.walkers do
		local w=walkers[i]
		if w.alive then
			if w.far and now<w.nextAt then
				-- far walkers: 10 Hz, rigid (no limb swing); keep simulating with the accumulated time
				stepWalker(R,w,dt,now)
			else
				w.nextAt=now+FAR_STEP
				stepWalker(R,w,dt,now)
				if w.alive then
					local target: Vector3,look: Vector3
					if w.mode=="sit" then
						target,look=w.seat or w.pos,w.look
					else
						target,look=walkerTarget(R,w)
						if w.mode=="idle" then look=w.look end
					end
					poseWalker(w,target,look,if w.far then FAR_STEP else dt,now)
				end
			end
		end
	end
	signalAcc+=dt
	if R.id=="metro" and signalAcc>=.25 then
		signalAcc=0
		for p in signalParts do if p.Parent then signalColor(R,p,now) else signalParts[p]=nil end end
	end
	wheelAcc+=dt
	if R.id=="metro" and wheelAcc>=1/15 then wheelAcc=0;poseWheels(focus,now) end
	if #batchParts>0 then workspace:BulkMoveTo(batchParts,batchFrames,Enum.BulkMoveMode.FireCFrameChanged) end
	local ms=(os.clock()-t0)*1000
	stats.lastStepMs=ms;stats.maxStepMs=math.max(stats.maxStepMs,ms);stats.steps+=1;stats.parts=#batchParts
	return batchParts,batchFrames
end
CityLife.step=step

-- Frame driver (also used by the tests with a virtual clock): accumulates time, scans, steps at <= 30 Hz.
function CityLife.update(focus: Vector3,dt: number,now: number): boolean
	scanAcc+=dt;glowAcc+=dt
	if scanAcc>=CityLife.SCAN or (region==nil and Plan.regionAt(focus)~=nil) then scanAcc=0;scan(focus,now) end
	if glowAcc>=2 then glowAcc=0;setNight(isNight()) end
	if not region then return false end
	acc+=dt
	if acc<CityLife.STEP then return false end
	local d=math.min(acc,.1);acc=0
	step(d,now,focus)
	return true
end
function CityLife.stats(): typeof(stats) return stats end
function CityLife.walkers(): {Walker} return walkers end
function CityLife.cars(): {Car} return cars end
function CityLife.region(): Region? return region end
function CityLife.folder(): Model? return folder end
function CityLife.far(): Model? return farModel end
function CityLife.impostors(): {Impostor} return impostors end

local function cameraPos(): Vector3?
	local cam=workspace.CurrentCamera
	return if cam then cam.CFrame.Position else nil
end
local function connectStep()
	if stepConn then return end
	stepConn=RunService.Heartbeat:Connect(function(dt: number)
		local p=cameraPos()
		if p then CityLife.update(p,dt,workspace:GetServerTimeNow()) end
	end)
end
CityLife.connectStep=connectStep
function CityLife.stepConnected(): boolean return stepConn~=nil end
function CityLife.init()
	local function addSignal(p: Instance) if p:IsA("BasePart") then signalParts[p]=true end end
	for _,p in CollectionService:GetTagged("MetroSignal") do addSignal(p) end
	CollectionService:GetInstanceAddedSignal("MetroSignal"):Connect(addSignal)
	CollectionService:GetInstanceRemovedSignal("MetroSignal"):Connect(function(p: Instance) if p:IsA("BasePart") then signalParts[p]=nil end end)
	local function addGlow(p: Instance)
		if not p:IsA("BasePart") then return end
		local c=p:GetAttribute("GlowColor")
		registerGlow(p,if typeof(c)=="Color3" then c else Color3.fromRGB(196,156,104))
	end
	for _,p in CollectionService:GetTagged("MetroNightGlow") do addGlow(p) end
	CollectionService:GetInstanceAddedSignal("MetroNightGlow"):Connect(addGlow)
	CollectionService:GetInstanceRemovedSignal("MetroNightGlow"):Connect(function(p: Instance) if p:IsA("BasePart") then glowParts[p]=nil end end)
	for _,m in CollectionService:GetTagged("MetroWheel") do registerWheel(m) end
	CollectionService:GetInstanceAddedSignal("MetroWheel"):Connect(function(m: Instance) task.defer(registerWheel,m) end)
	CollectionService:GetInstanceRemovedSignal("MetroWheel"):Connect(function(m: Instance) wheels[m]=nil end)
	setNight(isNight())
	-- region monitor: the per-frame step only runs inside a region
	task.spawn(function()
		while true do
			local p=cameraPos()
			local id=if p then Plan.regionAt(p) else nil
			if id then connectStep()
			elseif region or stepConn then deactivate() end
			task.wait(CityLife.SCAN)
		end
	end)
end
return CityLife
