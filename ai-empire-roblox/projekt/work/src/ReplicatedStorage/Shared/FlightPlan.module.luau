--!strict
-- FlightPlan: the shared, deterministic timetable and flight paths of the Port Meridian shuttle, the VIP
-- helicopter and the ambient air traffic (package "flight"). Pure data and maths - nothing here creates
-- instances. The server (ShuttleService) and every client (ShuttleController, AirTrafficController) compute
-- exactly the same aircraft position from workspace:GetServerTimeNow(), so the server never sends positions.
--   * Timetable: ONE aircraft flies both legs. A cycle of FP.interval() seconds = leg "out" (City Airport ->
--     Port Meridian: home boarding + the flight) followed by leg "back" (Port Meridian boarding + the flight
--     home); each direction departs once per cycle. cycle k starts at epoch + k*interval, the back leg
--     FP.leg("out").duration later. Port Meridian boarding is CONFIG.pmBoarding; home boarding gets the rest
--     of the interval (at least CONFIG.minBoarding; if the moving phases do not fit, the interval grows).
--   * Phases of a leg (same names both ways): boarding, doors, pushback, taxi, takeoff, climb, cruise,
--     approach, landing, taxiin, deboarding. Port Meridian (with MetroPlan.APRON): nose-in on apron stand 1
--     facing the hall, pushback east along the stand line with the nose swung north (towards the runway),
--     taxi north along the painted taxi line, left onto the runway. Without the apron the aircraft parks lined
--     up on the runway and its "pushback" / "taxi" are short holds (engine start, line-up).
--   * Paths along the real CityPlan geometry: home stand A<shuttleStand> -> pushback onto the taxilane ->
--     taxilane, west exit, taxiway, west connector -> runway, take-off roll east, climb-out, right turn over
--     the sea, cruise south-west, left turn onto a 4-degree final east into Port Meridian's runway, flare,
--     roll-out, teardrop U-turn, stand facing west (left doors towards the terminal). Port Meridian's whole
--     ground track (final, roll-out, stand, take-off roll) runs on FP.PM_LINE, 11 studs off the runway
--     centreline away from the terminal and the towers that line the runway, so the wingtips keep clear of
--     them; the climb-out stays on that line until it is past the towers. The way back: rolling take-off west,
--     right turn north, cruise, left turn onto a westbound final into City Airport, roll-out, west connector,
--     taxiway, taxilane, nose-in to the stand. tests/flight/clearance.py sweeps the real hull along every
--     low pose against the built world.
--   * Ground tracks are polylines with filleted corners, air tracks centripetal Catmull-Rom splines sampled
--     every ~12 studs; speeds follow accelerate/cruise/decelerate profiles in time. Pose = position on the
--     track, heading from the smoothed tangent (reversed for the pushback), pitch from the climb angle plus an
--     angle-of-attack schedule (rotation, climb, flare, de-rotation), bank from the turn rate.
local CityPlan=require(script.Parent.Config.CityPlan)
-- Port Meridian's apron (MetroPlan.APRON, metro package): stand 1 = the shuttle's stand, taxi line at taxiX.
-- Read-only data; without it the shuttle parks on the runway as before.
local okMetro,MetroPlan=pcall(require,script.Parent.Config.MetroPlan)
local FP={}

FP.CONFIG={
	interval=360, -- seconds between two departures in the same direction (tuned by CORE_SPEC: one aircraft, ~6 real
	-- minutes for the round trip; long waits are bridged by the instant charter flight at the counter)
	epoch=0, -- timetable origin (server time, seconds)
	minBoarding=75, -- home boarding at least this long (gate A<shuttleStand>; the rest of the interval goes here too)
	pmBoarding=30, -- Port Meridian boarding (the crew stays aboard for the quick turnaround)
	doors=5,deboarding=10, -- seconds
	startup=6,lineup=4, -- Port Meridian: engine start and line-up holds
	kind="320",scale=1.8, -- the shuttle: AircraftModel kind and scale (the same as the parked stand aircraft)
	pushSpeed=24,pushAcc=5,taxiSpeed=62,taxiAcc=9, -- studs/s, studs/s^2
	liftoff=140,liftoffPM=130,climbSpeed=250,cruiseSpeed=380,approachSpeed=140,touchdown=125,rollout=55,
	gEff=60,maxBank=math.rad(28), -- bank = atan(v^2 * curvature / gEff), clamped
	flights={out="PM 101",back="PM 102"}, -- the numbers on the airport package's gate A1 sign and Port Meridian's board
	airline="Meridian Air",
	charterAfter=180, -- seconds: the check-in counter also offers the instant charter flight when boarding is further away
	heliSpeed=70,heliCruise=60, -- VIP helicopter: studs/s, cruise height above the higher pad
}
FP.PHASES={"boarding","doors","pushback","taxi","takeoff","climb","cruise","approach","landing","taxiin","deboarding"}
FP.PHASE_TEXT={boarding="Boarding",doors="Doors closed",pushback="Pushback",taxi="Taxiing",takeoff="Take-off",climb="Climbing",
	cruise="Cruising",approach="Approach",landing="Landing",taxiin="Taxiing to the gate",deboarding="Arrived"}

export type Track={pts: {Vector3},cum: {number},length: number,marks: {number}}
export type Profile={T: number,L: number,v0: number,vc: number,v1: number,a: number,t1: number,t2: number}
export type Segment={phase: string,mode: string,t0: number,t1: number,track: Track,s0: number,s1: number,prof: Profile,reverse: boolean,hold: CFrame?,aoa0: number,aoa1: number}
export type Leg={dir: string,from: string,to: string,flight: string,segments: {Segment},duration: number,boarding: number,
	phases: {[string]: {t0: number,t1: number}},stand: CFrame,arrivalStand: CFrame}
export type Pose={cf: CFrame,phase: string,speed: number,onGround: boolean,gearDown: boolean,engines: boolean,altitude: number}

local A=CityPlan.AIRPORT
local B=CityPlan.ABROAD
local G=CityPlan.GROUND
local HY=A.apronTop -- home apron / runway top (wheels)
local PY=CityPlan.ROAD_TOP -- Port Meridian runway top
local rad=math.rad
local function v(x: number,y: number,z: number): Vector3 return Vector3.new(x,y,z) end

------------------------------------------------------------------------------------------------ profiles
-- Accelerate v0 -> vc, cruise, decelerate vc -> v1 with |acceleration| a over the distance L. vc is lowered
-- when L is too short; if even the end speed cannot be reached the acceleration is adjusted to fit exactly.
local function profile(L: number,v0: number,vc: number,v1: number,a: number): Profile
	L=math.max(L,1e-3);a=math.max(a,1e-3)
	vc=math.max(vc,v0,v1)
	local d1=(vc*vc-v0*v0)/(2*a);local d3=(vc*vc-v1*v1)/(2*a)
	if d1+d3>L then
		local lowest=math.max(v0,v1)
		local vcFit=math.sqrt(math.max(0,(2*a*L+v0*v0+v1*v1)/2))
		if vcFit>=lowest then vc=vcFit
		else vc=lowest;a=math.max(1e-3,math.abs(v0*v0-v1*v1)/(2*L)) end
		d1=(vc*vc-v0*v0)/(2*a);d3=(vc*vc-v1*v1)/(2*a)
	end
	local t1=(vc-v0)/a;local t3=(vc-v1)/a
	local tc=math.max(0,L-d1-d3)/math.max(vc,1e-3)
	return {T=t1+tc+t3,L=L,v0=v0,vc=vc,v1=v1,a=a,t1=t1,t2=t1+tc}
end
FP.profile=profile
-- Distance and speed after tau seconds.
local function along(p: Profile,tau: number): (number,number)
	if tau<=0 then return 0,p.v0 end
	if tau>=p.T then return p.L,p.v1 end
	if tau<p.t1 then return p.v0*tau+0.5*p.a*tau*tau,p.v0+p.a*tau end
	local d1=p.v0*p.t1+0.5*p.a*p.t1*p.t1
	if tau<p.t2 then return d1+p.vc*(tau-p.t1),p.vc end
	local u=tau-p.t2
	return math.min(p.L,d1+p.vc*(p.t2-p.t1)+p.vc*u-0.5*p.a*u*u),math.max(0,p.vc-p.a*u)
end
FP.along=along

------------------------------------------------------------------------------------------------ tracks
local function makeTrack(pts: {Vector3},marks: {number}?): Track
	local clean: {Vector3}={pts[1]}
	for i=2,#pts do if (pts[i]-clean[#clean]).Magnitude>1e-3 then table.insert(clean,pts[i]) end end
	if #clean==1 then table.insert(clean,clean[1]+Vector3.new(0,0,-1e-3)) end
	local cum: {number}={0}
	for i=2,#clean do cum[i]=cum[i-1]+(clean[i]-clean[i-1]).Magnitude end
	return {pts=clean,cum=cum,length=cum[#cum],marks=marks or {}}
end
FP.makeTrack=makeTrack
function FP.trackPos(tr: Track,s: number): Vector3
	local cum=tr.cum
	if s<=0 then return tr.pts[1] end
	if s>=tr.length then return tr.pts[#tr.pts] end
	local lo,hi=1,#cum
	while hi-lo>1 do
		local mid=(lo+hi)//2
		if cum[mid]<=s then lo=mid else hi=mid end
	end
	local seg=cum[hi]-cum[lo]
	local u=if seg>0 then (s-cum[lo])/seg else 0
	return tr.pts[lo]:Lerp(tr.pts[hi],u)
end
local trackPos=FP.trackPos
-- Smoothed unit tangent at s (central difference over +-d studs).
function FP.tangent(tr: Track,s: number,d: number?): Vector3
	local h=d or 10
	local a=trackPos(tr,math.max(0,s-h));local b=trackPos(tr,math.min(tr.length,s+h))
	local t=b-a
	if t.Magnitude<1e-5 then
		local n=#tr.pts
		t=tr.pts[n]-tr.pts[math.max(1,n-1)]
		if t.Magnitude<1e-5 then return Vector3.new(0,0,-1) end
	end
	return t.Unit
end
-- Ground polyline with filleted corners (radius r, reduced where segments are short). y of every point kept.
function FP.groundTrack(way: {Vector3},r: number): Track
	local pts: {Vector3}={way[1]}
	local n=#way
	for i=2,n-1 do
		local a,b,c=way[i-1],way[i],way[i+1]
		local d1=Vector3.new(a.X-b.X,0,a.Z-b.Z);local d2=Vector3.new(c.X-b.X,0,c.Z-b.Z)
		local l1,l2=d1.Magnitude,d2.Magnitude
		if l1<1e-3 or l2<1e-3 then table.insert(pts,b);continue end
		d1/=l1;d2/=l2
		local alpha=math.acos(math.clamp(d1:Dot(d2),-1,1)) -- interior angle
		if alpha>math.pi-0.02 then table.insert(pts,b);continue end
		local tmax=math.min(if i==2 then l1 else l1/2,if i==n-1 then l2 else l2/2)
		local t=r/math.tan(alpha/2);local radius=r
		if t>tmax then t=tmax;radius=t*math.tan(alpha/2) end
		local p1=b+d1*t;local p2=b+d2*t
		local centre=b+(d1+d2).Unit*(radius/math.sin(alpha/2))
		local a1=math.atan2(p1.Z-centre.Z,p1.X-centre.X);local a2=math.atan2(p2.Z-centre.Z,p2.X-centre.X)
		local da=a2-a1
		while da>math.pi do da-=2*math.pi end
		while da<-math.pi do da+=2*math.pi end
		local steps=math.max(2,math.ceil(math.abs(da)/rad(6)))
		for k=0,steps do
			local ang=a1+da*k/steps
			table.insert(pts,Vector3.new(centre.X+math.cos(ang)*radius,b.Y,centre.Z+math.sin(ang)*radius))
		end
	end
	table.insert(pts,way[n])
	return makeTrack(pts)
end
-- Centripetal Catmull-Rom through `ctrl` (first/last tangents along dirStart/dirEnd), sampled every ~12
-- studs. marks[i] = arc length at control point i (phase boundaries are taken from these).
local function cr(p0: Vector3,p1: Vector3,p2: Vector3,p3: Vector3,u: number): Vector3
	local function knot(t: number,a: Vector3,b: Vector3): number return t+math.max((b-a).Magnitude,1e-3)^0.5 end
	local t0=0;local t1=knot(t0,p0,p1);local t2=knot(t1,p1,p2);local t3=knot(t2,p2,p3)
	local t=t1+(t2-t1)*u
	local a1=p0*((t1-t)/(t1-t0))+p1*((t-t0)/(t1-t0))
	local a2=p1*((t2-t)/(t2-t1))+p2*((t-t1)/(t2-t1))
	local a3=p2*((t3-t)/(t3-t2))+p3*((t-t2)/(t3-t2))
	local b1=a1*((t2-t)/(t2-t0))+a2*((t-t0)/(t2-t0))
	local b2=a2*((t3-t)/(t3-t1))+a3*((t-t1)/(t3-t1))
	return b1*((t2-t)/(t2-t1))+b2*((t-t1)/(t2-t1))
end
-- adjust (optional) maps every sample before the arc lengths are measured (e.g. a corridor clamp).
function FP.airTrack(ctrl: {Vector3},dirStart: Vector3,dirEnd: Vector3,adjust: ((Vector3)->Vector3)?): Track
	local n=#ctrl
	local ext: {Vector3}={ctrl[1]-dirStart.Unit*120}
	for _,p in ctrl do table.insert(ext,p) end
	table.insert(ext,ctrl[n]+dirEnd.Unit*120)
	local pts: {Vector3}={ctrl[1]}
	local markIdx: {number}={1}
	for i=1,n-1 do
		local p0,p1,p2,p3=ext[i],ext[i+1],ext[i+2],ext[i+3]
		local steps=math.max(2,math.ceil((p2-p1).Magnitude/12))
		for k=1,steps do table.insert(pts,cr(p0,p1,p2,p3,k/steps)) end
		markIdx[i+1]=#pts
	end
	if adjust then for i,p in pts do pts[i]=adjust(p) end end
	local tr=makeTrack(pts)
	-- no duplicate removal happened for spline samples (each step > 0), so indices are valid
	for i,idx in markIdx do tr.marks[i]=tr.cum[math.min(idx,#tr.cum)] end
	return tr
end

------------------------------------------------------------------------------------------------ geometry
local stand=A.standCFrames[A.shuttleStand] or A.standCFrames[1] -- nose north (towards the terminal)
local SX,SZ=stand.X,stand.Z
local TL=A.taxilane
local TZ=(A.taxiway.z1+A.taxiway.z2)/2
local RZ=(A.runway.z1+A.runway.z2)/2
local WEST=A.connectors[1]
local EXIT=A.exits[1]
local PRZ=(B.runway.z1+B.runway.z2)/2
-- Port Meridian's runway is 70 studs wide and lined on the terminal side by the arrival hall and towers whose
-- faces stand ~57 studs from the centreline, less than the shuttle's half span (56.6 + winglet). The whole PM
-- ground track therefore runs 11 studs north of the centreline (main gear still well inside the runway).
FP.PM_LINE=PRZ-11
local PZ=FP.PM_LINE
FP.HOME_STAND=CFrame.new(SX,HY,SZ) -- the parked shuttle (= the airport package's stand aircraft frame)
local apron: any=if okMetro and typeof(MetroPlan)=="table" and typeof(MetroPlan.APRON)=="table" and typeof(MetroPlan.APRON.stand)=="CFrame"
	and typeof(MetroPlan.APRON.taxiX)=="number" then MetroPlan.APRON else nil
FP.PM_APRON=apron~=nil
-- Port Meridian stand: apron stand 1 (nose-in towards the hall's east wall, facing west, left doors towards the
-- city-side walkway), else on the runway facing west (left doors towards the terminal)
FP.PM_STAND=if apron then apron.stand :: CFrame else CFrame.lookAt(v(140,PY,PZ),v(100,PY,PZ))
FP.HOME_GATES={(A.gates[A.shuttleStand] or A.gates[1]).Position}
-- Port Meridian boarding: inside the hall at its apron door (MetroPlan.APRON.door), the hall centre, the counters
local pmDoor: Vector3?=if apron and typeof(apron.door)=="table" then v(apron.door.x-12,G+4,(apron.door.z1+apron.door.z2)/2) else nil
FP.PM_DOOR=if apron and typeof(apron.door)=="table" then v(apron.door.x,G+3.5,(apron.door.z1+apron.door.z2)/2) else nil
FP.PM_GATES=if pmDoor then {pmDoor,v(0,G+4,7636),B.checkin[1]+Vector3.new(0,4,0),B.checkin[2]+Vector3.new(0,4,0)}
	else {v(0,G+4,7636),B.checkin[1]+Vector3.new(0,4,0),B.checkin[2]+Vector3.new(0,4,0)}
FP.GATE_RADIUS=36
FP.GATE_NAME={out="A"..A.shuttleStand,back="Port Meridian"}
-- Where a boarded passenger's character is held (anchored, hidden below the apron) while the client shows
-- the ride: under the departure stand, then under the arrival stand from the middle of the cruise.
FP.HOLD={home=CFrame.new(SX,G-40,SZ),abroad=CFrame.new(FP.PM_STAND.X,G-40,FP.PM_STAND.Z)}

-- tracks per leg (built once, deterministic)
type LegTracks={push: Track?,taxi: Track?,roll: Track,air: Track,flareFrom: number,climbTo: number,descentFrom: number,rollout: Track,taxiin: Track}
local function outTracks(): LegTracks
	local push=FP.groundTrack({v(SX,HY,SZ),v(SX,HY,TL),v(SX+45,HY,TL)},32)
	local taxi=FP.groundTrack({v(SX+45,HY,TL),v(EXIT,HY,TL),v(EXIT,HY,TZ),v(WEST,HY,TZ),v(WEST,HY,RZ),v(WEST+60,HY,RZ)},40)
	local liftX=WEST+60+900
	local roll=makeTrack({v(WEST+60,HY,RZ),v(liftX,HY,RZ)})
	-- climb-out east, right turn over the sea, cruise south-west, left turn onto the final (PM_LINE, eastbound)
	local ctrl={v(liftX,HY,RZ),v(liftX+400,G+45,RZ),v(liftX+800,G+115,RZ),v(1350,G+200,3150),v(1600,G+300,3600), -- 5 = top of climb
		v(1500,G+420,4200),v(700,G+560,5000),v(-700,G+600,5900),v(-1900,G+520,6600), -- 9 = top of descent
		v(-2600,G+380,7050),v(-2850,G+250,7400),v(-2450,G+170,PZ),v(-1900,G+112,PZ),v(-1300,G+55,PZ),
		v(-850,G+14,PZ) --[[ 15 = flare start ]],v(-700,G+4,PZ),v(-600,PY,PZ)}
	local air=FP.airTrack(ctrl,Vector3.new(1,0,0),Vector3.new(1,0,0))
	local rollout: Track,taxiin: Track
	if apron then
		-- roll out to the taxi line, right onto it (north side of the runway), along it to the stand line, left
		-- nose-in to stand 1
		local st=FP.PM_STAND;local tx=apron.taxiX;local AY=st.Y
		rollout=makeTrack({v(-600,PY,PZ),v(tx-70,PY,PZ)})
		taxiin=FP.groundTrack({v(tx-70,PY,PZ),v(tx,PY,PZ),v(tx,AY,st.Z),v(st.X,AY,st.Z)},30)
	else
		rollout=makeTrack({v(-600,PY,PZ),v(90,PY,PZ)})
		-- teardrop U-turn east of the stand (x <= 250; the decorative aircraft stands at x 420)
		taxiin=FP.groundTrack({v(90,PY,PZ),v(160,PY,PZ),v(210,PY,PZ-22),v(250,PY,PZ-2),v(225,PY,PZ+20),v(180,PY,PZ+7),v(140,PY,PZ)},14)
	end
	return {push=push,taxi=taxi,roll=roll,air=air,climbTo=air.marks[5],descentFrom=air.marks[9],flareFrom=air.marks[15],rollout=rollout,taxiin=taxiin}
end
-- Port Meridian pushback: straight back (east) along the stand line to the taxi line, the tail swung south
-- (towards the city) so the nose ends pointing north at the runway; FP.PM_PUSH_END = studs past the stand line.
FP.PM_PUSH_R=7
FP.PM_PUSH_END=11
local function backTracks(): LegTracks
	local liftX=140-720
	local push: Track?,taxi: Track?,roll: Track=nil,nil,makeTrack({v(140,PY,PZ),v(liftX,PY,PZ)})
	if apron then
		local st=FP.PM_STAND;local tx=apron.taxiX;local AY=st.Y
		push=FP.groundTrack({v(st.X,AY,st.Z),v(tx,AY,st.Z),v(tx,AY,st.Z+FP.PM_PUSH_END)},FP.PM_PUSH_R)
		taxi=FP.groundTrack({v(tx,AY,st.Z+FP.PM_PUSH_END),v(tx,PY,PZ),v(tx-70,PY,PZ)},30)
		roll=makeTrack({v(tx-70,PY,PZ),v(liftX,PY,PZ)})
	end
	-- straight climb-out along PM_LINE until past the towers (x < -1040), then the right turn north
	local ctrl={v(liftX,PY,PZ),v(-800,G+20,PZ),v(-1040,G+60,PZ),v(-1300,G+105,PZ-6),v(-1700,G+190,7380),v(-1950,G+330,6950), -- 6 = top of climb
		v(-1700,G+520,6200),v(-500,G+680,5200),v(1000,G+700,4300),v(2300,G+560,3700), -- 10 = top of descent
		v(3000,G+330,3250),v(2700,G+180,RZ),v(2300,G+134,RZ),v(1700,G+86,RZ),
		v(1150,G+22,RZ) --[[ 15 = flare start ]],v(950,G+6,RZ),v(820,HY,RZ)}
	-- never drift towards the terminal side while low over Port Meridian's runway
	local air=FP.airTrack(ctrl,Vector3.new(-1,0,0),Vector3.new(-1,0,0),function(p: Vector3): Vector3
		return if p.X>-1100 and p.Z>PZ then Vector3.new(p.X,p.Y,PZ) else p
	end)
	local rollout=makeTrack({v(820,HY,RZ),v(-700,HY,RZ)})
	local taxiin=FP.groundTrack({v(-700,HY,RZ),v(WEST,HY,RZ),v(WEST,HY,TZ),v(EXIT,HY,TZ),v(EXIT,HY,TL),v(SX,HY,TL),v(SX,HY,SZ)},40)
	return {push=push,taxi=taxi,roll=roll,air=air,climbTo=air.marks[6],descentFrom=air.marks[10],flareFrom=air.marks[15],rollout=rollout,taxiin=taxiin}
end

------------------------------------------------------------------------------------------------ legs
local C=FP.CONFIG
-- Ground handling at the departure stand (client visuals, shared maths so the tests can sweep them): the
-- pushback tug pushes the aircraft, disconnects during `detach` seconds at the end of the pushback (moves 24
-- studs aside, towards its parking spot) and drives back to its place in `home` seconds; the jet bridge retracts (telescopes `retract` studs
-- and swings `angle` away from the fuselage about its terminal end) while the doors close and docks again in
-- `time` seconds after arrival.
FP.TUG={detach=3,home=18,aside=24}
FP.BRIDGE={angle=math.rad(5),retract=4,time=4}
local segmentPose: (Segment,number)->Pose
local function pointTrack(cf: CFrame): Track return makeTrack({cf.Position}) end
local function holdSeg(phase: string,cf: CFrame,T: number): Segment
	return {phase=phase,mode="hold",t0=0,t1=T,track=pointTrack(cf),s0=0,s1=0,prof=profile(1e-3,0,0,0,1),reverse=false,hold=cf,aoa0=0,aoa1=0}
end
local function moveSeg(phase: string,mode: string,tr: Track,s0: number,s1: number,prof: Profile,reverse: boolean?,aoa0: number?,aoa1: number?): Segment
	return {phase=phase,mode=mode,t0=0,t1=prof.T,track=tr,s0=s0,s1=s1,prof=prof,reverse=reverse==true,hold=nil,aoa0=aoa0 or 0,aoa1=aoa1 or aoa0 or 0}
end
-- The moving part of a leg (everything after boarding), without times.
local function movingSegments(dir: string): {Segment}
	local segs: {Segment}={}
	if dir=="out" then
		local t=outTracks()
		table.insert(segs,holdSeg("doors",FP.HOME_STAND,C.doors))
		local push=t.push :: Track
		local pushSeg=moveSeg("pushback","ground",push,0,push.length,profile(push.length,0,C.pushSpeed,0,C.pushAcc),true)
		table.insert(segs,pushSeg)
		-- the tug disconnects and drives aside before the aircraft taxis under its own power
		table.insert(segs,holdSeg("pushback",segmentPose(pushSeg,pushSeg.t1).cf,FP.TUG.detach))
		local taxi=t.taxi :: Track
		table.insert(segs,moveSeg("taxi","ground",taxi,0,taxi.length,profile(taxi.length,0,C.taxiSpeed,0,C.taxiAcc)))
		local L=t.roll.length
		table.insert(segs,moveSeg("takeoff","roll",t.roll,0,L,profile(L,0,C.liftoff,C.liftoff,C.liftoff^2/(2*L))))
		local air=t.air
		table.insert(segs,moveSeg("climb","air",air,0,t.climbTo,profile(t.climbTo,C.liftoff,C.climbSpeed,C.climbSpeed,(C.climbSpeed^2-C.liftoff^2)/(2*t.climbTo))))
		local cruiseL=t.descentFrom-t.climbTo
		table.insert(segs,moveSeg("cruise","air",air,t.climbTo,t.descentFrom,profile(cruiseL,C.climbSpeed,C.cruiseSpeed,C.cruiseSpeed,12)))
		local apL=t.flareFrom-t.descentFrom
		table.insert(segs,moveSeg("approach","air",air,t.descentFrom,t.flareFrom,profile(apL,C.cruiseSpeed,C.cruiseSpeed,C.approachSpeed,(C.cruiseSpeed^2-C.approachSpeed^2)/(2*apL)),false,rad(3)))
		local flL=air.length-t.flareFrom
		table.insert(segs,moveSeg("landing","air",air,t.flareFrom,air.length,profile(flL,C.approachSpeed,C.approachSpeed,C.touchdown,(C.approachSpeed^2-C.touchdown^2)/(2*flL)),false,rad(3),rad(6.5)))
		local rL=t.rollout.length
		table.insert(segs,moveSeg("landing","rollout",t.rollout,0,rL,profile(rL,C.touchdown,C.touchdown,12,(C.touchdown^2-144)/(2*rL))))
		local ti=t.taxiin
		table.insert(segs,moveSeg("taxiin","ground",ti,0,ti.length,profile(ti.length,12,26,0,4.5)))
		table.insert(segs,holdSeg("deboarding",FP.PM_STAND,C.deboarding))
	else
		local t=backTracks()
		table.insert(segs,holdSeg("doors",FP.PM_STAND,C.doors))
		if t.push and t.taxi then
			local push=t.push :: Track
			local pushSeg=moveSeg("pushback","ground",push,0,push.length,profile(push.length,0,C.pushSpeed*0.75,0,C.pushAcc),true)
			table.insert(segs,pushSeg)
			table.insert(segs,holdSeg("pushback",segmentPose(pushSeg,pushSeg.t1).cf,FP.TUG.detach))
			local taxi=t.taxi :: Track
			table.insert(segs,moveSeg("taxi","ground",taxi,0,taxi.length,profile(taxi.length,0,C.taxiSpeed*0.7,0,C.taxiAcc)))
		else
			table.insert(segs,holdSeg("pushback",FP.PM_STAND,C.startup))
			table.insert(segs,holdSeg("taxi",FP.PM_STAND,C.lineup))
		end
		local L=t.roll.length
		table.insert(segs,moveSeg("takeoff","roll",t.roll,0,L,profile(L,0,C.liftoffPM,C.liftoffPM,C.liftoffPM^2/(2*L))))
		local air=t.air
		table.insert(segs,moveSeg("climb","air",air,0,t.climbTo,profile(t.climbTo,C.liftoffPM,C.climbSpeed,C.climbSpeed,(C.climbSpeed^2-C.liftoffPM^2)/(2*t.climbTo))))
		local cruiseL=t.descentFrom-t.climbTo
		table.insert(segs,moveSeg("cruise","air",air,t.climbTo,t.descentFrom,profile(cruiseL,C.climbSpeed,C.cruiseSpeed,C.cruiseSpeed,12)))
		local apL=t.flareFrom-t.descentFrom
		table.insert(segs,moveSeg("approach","air",air,t.descentFrom,t.flareFrom,profile(apL,C.cruiseSpeed,C.cruiseSpeed,C.approachSpeed,(C.cruiseSpeed^2-C.approachSpeed^2)/(2*apL)),false,rad(3)))
		local flL=air.length-t.flareFrom
		table.insert(segs,moveSeg("landing","air",air,t.flareFrom,air.length,profile(flL,C.approachSpeed,C.approachSpeed,C.touchdown,(C.approachSpeed^2-C.touchdown^2)/(2*flL)),false,rad(3),rad(6.5)))
		local rL=t.rollout.length
		table.insert(segs,moveSeg("landing","rollout",t.rollout,0,rL,profile(rL,C.touchdown,C.touchdown,C.rollout,(C.touchdown^2-C.rollout^2)/(2*rL))))
		local ti=t.taxiin
		table.insert(segs,moveSeg("taxiin","ground",ti,0,ti.length,profile(ti.length,C.rollout,C.taxiSpeed,0,C.taxiAcc)))
		table.insert(segs,holdSeg("deboarding",FP.HOME_STAND,C.deboarding))
	end
	return segs
end
local function fixedTime(segs: {Segment}): number
	local T=0
	for _,s in segs do T+=s.t1-s.t0 end
	return T
end
local cache: {legs: {[string]: Leg},interval: number}?=nil
local function build(): {legs: {[string]: Leg},interval: number}
	if cache then return cache end
	local moving={out=movingSegments("out"),back=movingSegments("back")}
	local pmBoarding=math.max(C.pmBoarding,FP.CREW_TURN)
	local need=fixedTime(moving.out)+fixedTime(moving.back)+pmBoarding+C.minBoarding
	local interval=math.max(C.interval,math.ceil(need))
	local legs: {[string]: Leg}={}
	for _,dir in {"out","back"} do
		local segs=moving[dir]
		local boarding=if dir=="out" then interval-fixedTime(moving.out)-fixedTime(moving.back)-pmBoarding else pmBoarding
		local start=if dir=="out" then FP.HOME_STAND else FP.PM_STAND
		table.insert(segs,1,holdSeg("boarding",start,boarding))
		local t=0
		local phases: {[string]: {t0: number,t1: number}}={}
		for _,s in segs do
			local T=s.t1-s.t0
			s.t0=t;s.t1=t+T;t+=T
			local ph=phases[s.phase]
			if ph then ph.t1=s.t1 else phases[s.phase]={t0=s.t0,t1=s.t1} end
		end
		legs[dir]={dir=dir,from=if dir=="out" then "home" else "abroad",to=if dir=="out" then "abroad" else "home",flight=C.flights[dir],
			segments=segs,duration=t,boarding=boarding,phases=phases,stand=start,arrivalStand=if dir=="out" then FP.PM_STAND else FP.HOME_STAND}
	end
	local c={legs=legs,interval=interval}
	cache=c
	return c
end
-- Rebuild after changing CONFIG (tests).
function FP.reset() cache=nil;FP.resetAmbient() end
function FP.interval(): number return build().interval end
function FP.leg(dir: string): Leg return build().legs[dir] or build().legs.out end

------------------------------------------------------------------------------------------------ timetable
export type State={cycle: number,dir: string,leg: Leg,tau: number,phase: string,legStart: number,phaseStart: number,phaseEnd: number}
-- Where the shuttle is in its timetable at server time `now`.
function FP.at(now: number): State
	local b=build()
	local I=b.interval
	local t=now-C.epoch
	local cycle=math.floor(t/I)
	local u=t-cycle*I
	local outDur=b.legs.out.duration
	local dir=if u<outDur then "out" else "back"
	local leg=b.legs[dir]
	local legStart=C.epoch+cycle*I+(if dir=="out" then 0 else outDur)
	local tau=now-legStart
	local phase="deboarding";local p0,p1=legStart,legStart+leg.duration
	for _,name in FP.PHASES do
		local ph=leg.phases[name]
		if ph and tau>=ph.t0 and tau<ph.t1 then phase=name;p0=legStart+ph.t0;p1=legStart+ph.t1;break end
	end
	return {cycle=cycle,dir=dir,leg=leg,tau=tau,phase=phase,legStart=legStart,phaseStart=p0,phaseEnd=p1}
end
-- Start time (server time) of leg `dir` of cycle k (the back leg starts when the out leg ends).
function FP.legStart(dir: string,cycle: number): number
	local b=build()
	return C.epoch+cycle*b.interval+(if dir=="out" then 0 else b.legs.out.duration)
end
-- The next leg in direction `dir` whose boarding has not ended at `now`: (cycle, legStart, departure time =
-- end of boarding + doors = pushback start, boarding end).
function FP.nextLeg(dir: string,now: number): (number,number,number,number)
	local I=build().interval
	local leg=FP.leg(dir)
	local k=math.floor((now-C.epoch)/I)-1
	for _=1,4 do
		local s=FP.legStart(dir,k)
		local boardEnd=s+leg.phases.boarding.t1
		if boardEnd>now then return k,s,s+leg.phases.pushback.t0,boardEnd end
		k+=1
	end
	local s=FP.legStart(dir,k)
	return k,s,s+leg.phases.pushback.t0,s+leg.phases.boarding.t1
end
-- Seconds of flight (pushback start -> deboarding start) of a leg.
function FP.flightTime(dir: string): number
	local leg=FP.leg(dir)
	return leg.phases.deboarding.t0-leg.phases.pushback.t0
end
-- Seconds until boarding of the next leg in direction dir starts (0 while it is boarding).
function FP.boardingIn(dir: string,now: number): number
	local _,start=FP.nextLeg(dir,now)
	return math.max(0,start-now)
end

------------------------------------------------------------------------------------------------ poses
local function smooth(x: number): number x=math.clamp(x,0,1);return x*x*(3-2*x) end
local function flat(d: Vector3): Vector3
	local f=Vector3.new(d.X,0,d.Z)
	return if f.Magnitude>1e-5 then f.Unit else Vector3.new(0,0,-1)
end
-- Signed bank angle (positive = right wing down) from the heading change around s.
local function bankAt(tr: Track,s: number,speed: number): number
	local D=70
	local a=flat(FP.tangent(tr,math.max(0,s-D),20));local b=flat(FP.tangent(tr,math.min(tr.length,s+D),20))
	local dist=math.min(tr.length,s+D)-math.max(0,s-D)
	if dist<1 then return 0 end
	local ang=math.atan2(a:Cross(b).Y,a:Dot(b)) -- < 0 = right turn (y up, viewed from above)
	local kappa=-ang/dist
	return math.clamp(math.atan(speed*speed*kappa/C.gEff),-C.maxBank,C.maxBank)
end
function segmentPose(seg: Segment,tau: number): Pose
	local local_t=tau-seg.t0
	if seg.mode=="hold" then
		local cf=seg.hold or CFrame.new()
		return {cf=cf,phase=seg.phase,speed=0,onGround=true,gearDown=true,engines=seg.phase~="boarding" and seg.phase~="deboarding" and seg.phase~="parked",altitude=0}
	end
	local d,speed=along(seg.prof,local_t)
	local s=seg.s0+d
	local tr=seg.track
	local pos=trackPos(tr,s)
	local tan=FP.tangent(tr,s,if seg.mode=="air" then 16 else 6)
	if seg.mode=="ground" or seg.mode=="roll" or seg.mode=="rollout" then
		local heading=flat(tan)
		if seg.reverse then heading=-heading end
		local pitch=0
		if seg.mode=="roll" then pitch=rad(8)*smooth((local_t-(seg.prof.T-2.6))/2.6) end
		if seg.mode=="rollout" then pitch=rad(5)*(1-smooth(local_t/2.6)) end
		local cf=CFrame.lookAt(pos,pos+heading)*CFrame.Angles(pitch,0,0)
		return {cf=cf,phase=seg.phase,speed=speed,onGround=true,gearDown=true,engines=true,altitude=0}
	end
	-- air
	local u=if seg.prof.T>0 then local_t/seg.prof.T else 1
	local aoa=seg.aoa0+(seg.aoa1-seg.aoa0)*smooth(u)
	if seg.phase=="climb" then aoa=rad(3)+rad(5)*(1-smooth(local_t/6)) end
	local bank=bankAt(tr,s,speed)
	local cf=CFrame.lookAt(pos,pos+tan)*CFrame.Angles(0,0,-bank)*CFrame.Angles(aoa,0,0)
	local ground=if pos.Z>5000 then PY else HY
	local alt=pos.Y-ground
	local gear=alt<160 and not (seg.phase=="climb" and local_t>4)
	if seg.phase=="cruise" then gear=false end
	return {cf=cf,phase=seg.phase,speed=speed,onGround=false,gearDown=gear,engines=true,altitude=alt}
end
-- Pose of leg `leg` at time tau (seconds since the leg start).
function FP.legPose(leg: Leg,tau: number): Pose
	local segs=leg.segments
	if tau<=0 then return segmentPose(segs[1],0) end
	for _,seg in segs do
		if tau<seg.t1 then return segmentPose(seg,tau) end
	end
	local last=segs[#segs]
	return segmentPose(last,last.t1)
end
-- Pose of the shuttle at server time `now`.
function FP.pose(now: number): (Pose,State)
	local st=FP.at(now)
	return FP.legPose(st.leg,st.tau),st
end
-- Pushback tug of the departure stand (home: the airport package's tug; Port Meridian: ShuttleGround's local
-- tug): its frame now, given its parked frame (attached to the nose gear).
function FP.tugFrame(st: State,parked: CFrame): CFrame
	if st.dir=="back" and not FP.PM_APRON then return parked end -- runway stand: no pushback
	local leg=st.leg
	local push=leg.phases.pushback
	local hold=FP.TUG.detach
	if st.tau<push.t0 then return parked end
	local rel=leg.stand:ToObjectSpace(parked)
	if st.tau<push.t1-hold then return FP.legPose(leg,st.tau).cf*rel end
	local endCf=FP.legPose(leg,push.t1-hold).cf
	local attached=endCf*rel
	-- it pulls aside towards the side of its parking spot, clear of the nose gear's taxi path
	local sideSign=if (parked.Position-attached.Position):Dot(endCf.RightVector)>=0 then 1 else -1
	local aside=CFrame.new(endCf.RightVector*FP.TUG.aside*sideSign)*attached
	if st.tau<push.t1 then return attached:Lerp(aside,smooth((st.tau-(push.t1-hold))/hold)) end
	local tx=st.tau-leg.phases.taxi.t0
	if tx>=FP.TUG.home then return parked end
	local u=smooth(tx/FP.TUG.home)
	local a,b=aside.Position,parked.Position
	local p=a:Lerp(b,u)
	local dir=flat(b-a)
	local driving=CFrame.lookAt(p,p+dir)
	local turn=smooth((u-0.8)/0.2)
	local r0=driving.Rotation
	local start=smooth(u/0.15)
	r0=aside.Rotation:Lerp(r0,start)
	return CFrame.new(p)*r0:Lerp(parked.Rotation,turn)
end
-- Jet bridge of the home stand: 0 = docked at the door, 1 = retracted (doors closing -> arrival).
function FP.bridgeU(st: State): number
	local ph=st.leg.phases
	if st.dir=="out" then
		if st.phase=="boarding" then return 0 end
		if st.phase=="doors" then return smooth((st.tau-ph.doors.t0)/math.min(FP.BRIDGE.time,ph.doors.t1-ph.doors.t0)) end
		return 1
	end
	if st.phase=="deboarding" then return 1-smooth((st.tau-ph.deboarding.t0)/FP.BRIDGE.time) end
	return 1
end
-- Axes of a jet bridge from its terminal-end point (model attribute TerminalDoor) and its cab floor frame
-- (LookVector towards the aircraft door): pivot, axis (terminal -> cab) and away (from the fuselage).
function FP.bridgeAxes(terminalDoor: Vector3,cab: CFrame): (Vector3,Vector3,Vector3)
	return terminalDoor,flat(cab.Position-terminalDoor),flat(-cab.LookVector)
end
-- Parts of the outer tunnel (fixed at the terminal) vs everything that telescopes.
function FP.bridgeInner(name: string): boolean return string.sub(name,1,11)~="BridgeOuter" end
-- Frame of one jet-bridge part at retraction u: `inner` parts (inner tunnel, drive unit, cab, bellows)
-- telescope towards the terminal along `axis` (unit, terminal -> cab, horizontal); everything swings about
-- the terminal end `pivot` so that the cab moves along `away` (unit, horizontal, away from the fuselage).
function FP.bridgeFrame(cf: CFrame,inner: boolean,u: number,pivot: Vector3,axis: Vector3,away: Vector3): CFrame
	if u<=0 then return cf end
	local r=Vector3.new(axis.X,0,axis.Z)
	local swing=Vector3.new(r.Z,0,-r.X) -- d(cab)/d(angle) for a rotation about +Y
	local sign=if swing:Dot(away)>=0 then 1 else -1
	local p=Vector3.new(pivot.X,0,pivot.Z)
	local out=cf
	if inner then out=CFrame.new(-axis*FP.BRIDGE.retract*u)*out end
	local rot=CFrame.new(p)*CFrame.Angles(0,sign*FP.BRIDGE.angle*u,0)*CFrame.new(-p)
	return rot*out
end
-- Crew (the two pilots), the same pair on every leg. At City Airport they leave the aircraft after arrival
-- (CREW_LEAVE seconds of walking, from the start of deboarding into the next leg's boarding), wait in the
-- crew room, and walk back to the aircraft in the last part of boarding (CREW_WALK seconds, seated
-- CREW_SEATED seconds before boarding ends). At Port Meridian the turnaround is short: both stay aboard
-- ("cockpit"), and the first officer does the exterior walkaround (down the airstairs, round the nose, back
-- up) WALKAROUND seconds from WALKAROUND_START into the boarding. States: "leaving", "crewroom", "walking",
-- "cockpit".
FP.CREW_WALK=22
FP.CREW_LEAVE=20
FP.CREW_SEATED=3
FP.WALKAROUND_START=3
FP.WALKAROUND=22
FP.CREW_TURN=FP.WALKAROUND_START+FP.WALKAROUND+3 -- the shortest Port Meridian boarding
-- (state, seconds since the leave / walk started; nil otherwise)
function FP.crewTimes(st: State): (string,number?)
	local ph=st.leg.phases
	if st.phase=="deboarding" then
		if st.dir=="back" then return "leaving",st.tau-ph.deboarding.t0 end
		return "cockpit",nil -- arrived at Port Meridian: the crew stays aboard
	end
	if st.phase=="boarding" and st.dir=="out" then
		local sinceLeave=st.tau+C.deboarding -- the previous leg's deboarding started this long ago
		local walkStart=math.max(0,ph.boarding.t1-FP.CREW_SEATED-FP.CREW_WALK)
		if st.tau<walkStart and sinceLeave<FP.CREW_LEAVE then return "leaving",sinceLeave end
		if st.tau<walkStart then return "crewroom",nil end
		if st.tau<ph.boarding.t1-FP.CREW_SEATED then return "walking",st.tau-walkStart end
	end
	return "cockpit",nil
end
function FP.crewState(st: State): string
	local state=FP.crewTimes(st)
	return state
end
-- Seconds into the first officer's Port Meridian walkaround (nil outside it).
function FP.walkaround(st: State): number?
	if st.dir~="back" or st.phase~="boarding" then return nil end
	local since=st.tau-FP.WALKAROUND_START
	if since<0 or since>FP.WALKAROUND then return nil end
	return since
end

------------------------------------------------------------------------------------------------ helicopter
-- VIP helicopter between two pads (Port Meridian: airport pad -> Meridian Grand roof). Spool up, vertical
-- lift to hover height, transit at cruise height along the boulevard corridor (x = HELI_CORRIDOR_X, the open
-- axis between the towers), hover over the target, vertical descent, spool down.
export type HeliPlan={from: Vector3,to: Vector3,duration: number,lift: number,transit: number,descend: number,track: Track,prof: Profile}
FP.HELI_SPOOL=3
FP.HELI_HOVER=30
FP.HELI_CORRIDOR_X=0
function FP.heliPlan(from: Vector3,to: Vector3): HeliPlan
	local cruiseY=math.max(from.Y,to.Y)+C.heliCruise
	local fromUp=from+Vector3.new(0,FP.HELI_HOVER,0)
	local toUp=to+Vector3.new(0,FP.HELI_HOVER,0)
	local x=FP.HELI_CORRIDOR_X
	local sz=if to.Z>from.Z then 1 else -1
	local ctrl={fromUp}
	if math.abs(from.X-x)>40 then table.insert(ctrl,Vector3.new((from.X+x)/2,(fromUp.Y+cruiseY)/2,from.Z+sz*60)) end
	table.insert(ctrl,Vector3.new(x,cruiseY,from.Z+sz*110))
	table.insert(ctrl,Vector3.new(x,cruiseY,to.Z-sz*120))
	if math.abs(to.X-x)>40 then table.insert(ctrl,Vector3.new((to.X+x)/2,(toUp.Y+cruiseY)/2,to.Z-sz*60)) end
	table.insert(ctrl,toUp)
	local d0=Vector3.new(ctrl[2].X-fromUp.X,0,ctrl[2].Z-fromUp.Z)
	local d1=Vector3.new(toUp.X-ctrl[#ctrl-1].X,0,toUp.Z-ctrl[#ctrl-1].Z)
	local track=FP.airTrack(ctrl,if d0.Magnitude>0.1 then d0.Unit else Vector3.new(0,0,sz),if d1.Magnitude>0.1 then d1.Unit else Vector3.new(0,0,sz))
	local prof=profile(track.length,0,C.heliSpeed,0,12)
	local lift=7;local descend=9
	return {from=from,to=to,duration=FP.HELI_SPOOL*2+lift+prof.T+descend,lift=lift,transit=prof.T,descend=descend,track=track,prof=prof}
end
-- Helicopter frame (skids on the pad at both ends) and rotor speed 0..1 at tau seconds into the plan.
function FP.heliPose(h: HeliPlan,tau: number): (CFrame,number)
	local rotor=math.clamp(tau/FP.HELI_SPOOL,0,1)*math.clamp((h.duration-tau)/FP.HELI_SPOOL,0,1)
	local first=flat(FP.tangent(h.track,0,30));local last=flat(FP.tangent(h.track,h.track.length,30))
	local t=tau-FP.HELI_SPOOL
	local fromUp=h.from+Vector3.new(0,FP.HELI_HOVER,0)
	local toUp=h.to+Vector3.new(0,FP.HELI_HOVER,0)
	if t<=0 then return CFrame.lookAt(h.from,h.from+first),rotor end
	if t<h.lift then
		local p=h.from:Lerp(fromUp,smooth(t/h.lift))
		return CFrame.lookAt(p,p+first),rotor
	end
	t-=h.lift
	if t<h.transit then
		local d,speed=along(h.prof,t)
		local p=trackPos(h.track,d)
		local heading=flat(FP.tangent(h.track,d,14))
		local accel=if t<h.prof.t1 then 1 elseif t>h.prof.t2 then -1 else 0
		local pitch=-rad(9)*accel*math.clamp(speed/12,0,1)
		local bank=bankAt(h.track,d,speed)
		return CFrame.lookAt(p,p+heading)*CFrame.Angles(0,0,-bank)*CFrame.Angles(pitch,0,0),rotor
	end
	t-=h.transit
	if t<h.descend then
		local p=toUp:Lerp(h.to,smooth(t/h.descend))
		return CFrame.lookAt(p,p+last),rotor
	end
	return CFrame.lookAt(h.to,h.to+last),rotor
end

-- A transfer requested at t (destination "hotel" | "airport"; a = airport pad, b = hotel pad, the helicopter
-- waits at a): to the hotel = ride a->b, then an empty ferry back; to the airport = ferry a->b to pick the
-- passenger up, then the ride b->a. Returns (ride start, ride end, helicopter free again).
function FP.heliTimes(destination: string,t: number,a: Vector3,b: Vector3): (number,number,number)
	local dAB=FP.heliPlan(a,b).duration;local dBA=FP.heliPlan(b,a).duration
	if destination=="hotel" then return t,t+dAB,t+dAB+dBA+2 end
	return t+dAB,t+dAB+dBA,t+dAB+dBA+2
end
-- Helicopter frame at server time now for a transfer started at `start`: (cf, rotor 0..1, carrying passenger).
function FP.heliAt(destination: string,start: number,now: number,a: Vector3,b: Vector3): (CFrame,number,boolean)
	local ab=FP.heliPlan(a,b);local ba=FP.heliPlan(b,a)
	local tau=now-start
	if tau<ab.duration then
		local cf,rotor=FP.heliPose(ab,tau)
		return cf,rotor,destination=="hotel"
	end
	local cf,rotor=FP.heliPose(ba,math.min(tau-ab.duration,ba.duration))
	return cf,rotor,destination=="airport" and tau<ab.duration+ba.duration
end

------------------------------------------------------------------------------------------------ ambient traffic
-- Other airliners at City Airport (client-only visuals). Each visit is one aircraft: it lands east (from the
-- west), rolls out, turns off at the east connector, taxis along the taxiway and nose-in onto remote stand R2
-- (FP.AMBIENT_STAND, east apron), stands there, then pushes back onto the taxiway, taxis to the east
-- connector and takes off west. Nothing appears or vanishes near the airport: a visit starts and ends in the
-- air several thousand studs out. Sky crossings fly straight across the map at 2,400-3,400 studs. The
-- runway movements are placed in each cycle where the shuttle does not use the runway or its approach
-- (FP.ambientSlots); with two slots a visit lands and departs in the same cycle, with one it lands in even
-- and departs in odd cycles.
export type Ambient={kind: string,t0: number,duration: number,track: Track,segs: {Segment},livery: number,big: boolean}
local function hash(n: number): number
	n=math.floor(n)%2147483647
	n=(n*1103515245+12345)%2147483648
	n=(n*1103515245+12345)%2147483648
	return n
end
FP.hash=hash
FP.AMBIENT_STAND=CFrame.lookAt(v(575,HY,2700),v(575,HY,2600)) -- remote stand R2: nose north, clear of R1 (x 470, z 2640)
local EAST=A.connectors[2]
local function arrivalSegs(): {Segment}
	local st=FP.AMBIENT_STAND
	local ctrl={v(-6500,G+420,RZ),v(-4200,G+260,RZ),v(-2400,G+130,RZ),v(-1400,G+40,RZ),v(-1000,G+8,RZ),v(-880,HY,RZ)}
	local air=FP.airTrack(ctrl,Vector3.new(1,0,0),Vector3.new(1,0,0))
	local roll=makeTrack({v(-880,HY,RZ),v(EAST-150,HY,RZ)})
	local taxi=FP.groundTrack({v(EAST-150,HY,RZ),v(EAST,HY,RZ),v(EAST,HY,TZ),v(st.X,HY,TZ),v(st.X,HY,st.Z)},40)
	return {
		moveSeg("approach","air",air,0,air.length,profile(air.length,230,230,C.touchdown,(230^2-C.touchdown^2)/(2*air.length)),false,rad(3),rad(5.5)),
		moveSeg("landing","rollout",roll,0,roll.length,profile(roll.length,C.touchdown,C.touchdown,24,(C.touchdown^2-24^2)/(2*roll.length))),
		moveSeg("taxiin","ground",taxi,0,taxi.length,profile(taxi.length,24,32,0,3)),
	}
end
local function departureSegs(): {Segment}
	local st=FP.AMBIENT_STAND
	local push=FP.groundTrack({v(st.X,HY,st.Z),v(st.X,HY,TZ),v(st.X-30,HY,TZ)},30)
	local pushSeg=moveSeg("pushback","ground",push,0,push.length,profile(push.length,0,C.pushSpeed,0,C.pushAcc),true)
	local taxi=FP.groundTrack({v(st.X-30,HY,TZ),v(EAST,HY,TZ),v(EAST,HY,RZ),v(EAST-60,HY,RZ)},40)
	local roll=makeTrack({v(EAST-60,HY,RZ),v(-150,HY,RZ)})
	local ctrl={v(-150,HY,RZ),v(-600,G+60,RZ),v(-1300,G+220,RZ),v(-2600,G+480,2900),v(-4500,G+900,2500),v(-7000,G+1400,2000)}
	local air=FP.airTrack(ctrl,Vector3.new(-1,0,0),Vector3.new(-1,0,-0.2))
	return {
		holdSeg("doors",st,4),
		pushSeg,
		holdSeg("pushback",segmentPose(pushSeg,pushSeg.t1).cf,FP.TUG.detach),
		moveSeg("taxi","ground",taxi,0,taxi.length,profile(taxi.length,0,34,0,3.5)),
		moveSeg("takeoff","roll",roll,0,roll.length,profile(roll.length,0,C.liftoff,C.liftoff,C.liftoff^2/(2*roll.length))),
		moveSeg("climb","air",air,0,air.length,profile(air.length,C.liftoff,280,280,(280^2-C.liftoff^2)/(2*air.length))),
	}
end
local function timed(segs: {Segment}): ({Segment},number)
	local t=0
	for _,s in segs do local T=s.t1-s.t0;s.t0=t;s.t1=t+T;t+=T end
	return segs,t
end
local ambientCache: {arrival: {Segment},departure: {Segment},arrivalT: number,departureT: number,parked: {Segment}}?=nil
local function ambientBase()
	if ambientCache then return ambientCache end
	local a,at=timed(arrivalSegs())
	local d,dt=timed(departureSegs())
	local c={arrival=a,departure=d,arrivalT=at,departureT=dt,parked={holdSeg("parked",FP.AMBIENT_STAND,1e9)}}
	ambientCache=c
	return c
end
local slotCache: {number}?=nil
function FP.resetAmbient() slotCache=nil;ambientCache=nil end
-- Offsets (seconds into a cycle) where an ambient runway movement fits (the longer of arrival / departure).
function FP.ambientSlots(): {number}
	if slotCache then return slotCache end
	local b=build()
	local I=b.interval
	local base=ambientBase()
	local len=math.max(base.arrivalT,base.departureT)
	local busy: {{number}}={}
	local out,back=b.legs.out,b.legs.back
	local backStart=out.duration
	table.insert(busy,{out.phases.taxi.t1-20,out.phases.climb.t0+30})
	table.insert(busy,{backStart+back.phases.approach.t0+(back.phases.approach.t1-back.phases.approach.t0)*0.5,backStart+back.phases.taxiin.t0+20})
	local slots: {number}={}
	local t=5
	while t<I-len and #slots<2 do
		local ok=true
		for _,w in busy do if t+len>w[1] and t-8<w[2] then ok=false end end
		if ok then table.insert(slots,t);t+=len+30 else t+=1 end
	end
	slotCache=slots
	return slots
end
-- Ambient events of cycle k: the runway visit (arrival, parked at R2, departure - one aircraft, key `visit`)
-- and two sky crossings (deterministic per cycle). fadeIn / fadeOut: whether the client fades the model at the
-- start / end of the event (only far out in the air).
export type AmbientEvent={id: string,kind: string,t0: number,duration: number,segs: {Segment}?,from: Vector3?,to: Vector3?,livery: number,lod: string,
	visit: string?,fadeIn: boolean,fadeOut: boolean}
function FP.ambient(cycle: number): {AmbientEvent}
	local base=ambientBase()
	local I=build().interval
	local start=C.epoch+cycle*I
	local out: {AmbientEvent}={}
	local slots=FP.ambientSlots()
	local function visitOf(k: number): (string,number)
		local h=hash(k*7+3)
		return "visit"..k,(h//4096)%5+1
	end
	local function arrival(k: number,t0: number,departAt: number)
		local id,livery=visitOf(k)
		table.insert(out,{id=id.."_arr",kind="arrival",t0=t0,duration=base.arrivalT,segs=base.arrival,livery=livery,lod="medium",visit=id,fadeIn=true,fadeOut=false})
		local parkedAt=t0+base.arrivalT
		table.insert(out,{id=id.."_park",kind="parked",t0=parkedAt,duration=math.max(0,departAt-parkedAt),segs=base.parked,livery=livery,lod="medium",visit=id,fadeIn=false,fadeOut=false})
	end
	local function departure(k: number,t0: number)
		local id,livery=visitOf(k)
		table.insert(out,{id=id.."_dep",kind="departure",t0=t0,duration=base.departureT,segs=base.departure,livery=livery,lod="medium",visit=id,fadeIn=false,fadeOut=true})
	end
	if #slots>=2 then
		arrival(cycle,start+slots[1],start+slots[2])
		departure(cycle,start+slots[2])
	elseif #slots==1 then
		if cycle%2==0 then arrival(cycle,start+slots[1],start+I+slots[1])
		else departure(cycle-1,start+slots[1]) end
	end
	for i=1,2 do
		local h=hash(cycle*13+i*101)
		local ang=(h%3600)/3600*math.pi*2
		local alt=G+2400+(h%1000)
		local centre=v(((h//7)%1600)-800,alt,1400+((h//11)%1600))
		local d=Vector3.new(math.cos(ang),0,math.sin(ang))
		table.insert(out,{id="sky"..cycle.."_"..i,kind="sky",t0=start+(i-1)*I/2+((h//13)%60),duration=16000/260,
			from=centre-d*8000,to=centre+d*8000,livery=(h//17)%5+1,lod="low",visit=nil,fadeIn=true,fadeOut=true})
	end
	return out
end
-- Frame of an ambient event at server time now (nil when it is not active).
function FP.ambientPose(e: AmbientEvent,now: number): Pose?
	local tau=now-e.t0
	if tau<0 or tau>e.duration then return nil end
	if e.kind=="sky" then
		local a,b=e.from :: Vector3,e.to :: Vector3
		local p=a:Lerp(b,tau/e.duration)
		return {cf=CFrame.lookAt(p,p+(b-a).Unit),phase="cruise",speed=260,onGround=false,gearDown=false,engines=true,altitude=p.Y-G}
	end
	local segs=e.segs :: {Segment}
	for _,seg in segs do
		if tau<seg.t1 then return segmentPose(seg,tau) end
	end
	return segmentPose(segs[#segs],segs[#segs].t1)
end

return FP
