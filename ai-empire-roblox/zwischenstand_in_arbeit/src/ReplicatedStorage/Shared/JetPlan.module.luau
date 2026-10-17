--!strict
-- JetPlan (package "guests_jet"): the company jet's private flights - pure, deterministic maths shared by the
-- server (JetService) and every client (JetController). Nothing here creates instances. The server publishes a
-- flight ONCE (kind, PM slot, departure delay, start time); every client computes the same pose from
-- workspace:GetServerTimeNow() with these functions, like the shuttle with FlightPlan.
--   * Aircraft: AircraftModel "bizjet" at JetPlan.SCALE (46 x 41.6 x 15.5 studs). Home: Hangar 1 of City Airport
--     (CityPlan.AIRPORT.hangar), parked nose west (towed in nose first; the operator's name on the fin faces the
--     door). Port Meridian: PM_SLOTS - slot 1 "VIP apron" on the runway shoulder beside the VIP helipad
--     (MetroPlan.HELIPADS.airport), slot 2 = apron stand 2 (the parked airliner there is hidden locally while a
--     jet uses it). The founder is placed at ARRIVAL.abroad (by the VIP limousine stand, MetroPlan.VIP_LIMO) or
--     ARRIVAL.home (City Airport arrivals, like the shuttle).
--   * Flights: "out" (trip home -> Port Meridian), "back" (trip Port Meridian -> home), "ferry" (back, empty: the
--     jet flies home by itself after the founder left Port Meridian another way). Phases: boarding (pilots walk
--     from the hangar crew corner to the cockpit in the first CONFIG.crewWalk seconds of a departure from home;
--     companions climb the airstair at the end; a departure delay waiting for a clear runway is added here),
--     doors, pushback (home: the tug pushes the jet tail first out of the hangar, the tail swings north so the
--     nose ends pointing south), startup, taxi, takeoff, climb, cruise, approach, landing, taxiin, deboarding and
--     (home) towin (the tug tows it nose first back into the hangar). The air tracks are the shuttle's
--     (FlightPlan outTracks / backTracks control points, the same Port Meridian line FP.PM_LINE clear of the
--     towers); ground tracks run hangar -> hangar apron -> west apron edge -> taxiway -> west connector ->
--     runway at home and on the runway / shoulder / apron at Port Meridian.
--   * Separation: JetPlan.schedule delays a departure (inside "boarding": at most CONFIG.maxDelay s with the founder
--     aboard, CONFIG.maxDelayEmpty s for an empty / staff flight) until none of its field windows (JP.windows: the
--     time the jet spends in a field's zone - City Airport runway + taxiway + corridors, the runway alone for the
--     ambient airliners, Port Meridian's runway + corridors, the apron in front of Hangar 1) overlaps the shuttle
--     (FlightPlan timetable), the ambient airliners at City Airport (FlightPlan.ambient) or another company jet.
--   * Pose (cf, phase, speed, gear, engines), airstair, tug, crew and companion states for the client.
local CityPlan=require(script.Parent.Config.CityPlan)
local FP=require(script.Parent.FlightPlan)
local Aircraft=require(script.Parent.AircraftModel)
local okMetro,MetroPlan=pcall(require,script.Parent.Config.MetroPlan)
local JP={}

JP.KIND="bizjet"
JP.SCALE=Aircraft.BIZJET_SCALE
JP.CONFIG={
	crewWalk=14, -- pilots: crew corner -> cockpit at the start of a departure from home (and back after towin)
	boarding=16, -- shortest boarding of a trip (the companions climb the airstair in its last 10 s)
	ferryBoarding=6,
	doors=4,startup=5,deboarding=10,ferryDeboarding=4,
	pushSpeed=12,pushAcc=3,towSpeed=10,towAcc=2.5,taxiSpeed=32,taxiAcc=7,
	liftoff=110,climbSpeed=240,cruiseSpeed=380,approachSpeed=130,touchdown=110,brake=7,
	gEff=60,maxBank=math.rad(26),
	maxDelay=240, -- seconds a departure with the founder aboard may wait for a clear runway (else RUNWAY_BUSY; alone
	-- on the server the jet always finds one within ~150 s, median ~40 s - tests/guests_jet sep_check)
	maxDelayEmpty=600, -- the same for empty / staff flights (ferry, positioning, field staff) - nobody waits aboard
	guard=2, -- seconds added around every field window of a jet
	pad=2, -- seconds added around the shuttle's / ambient airliners' field windows
	autoFerry=20, -- seconds after the founder left Port Meridian another way before the parked jet flies home empty
}
JP.PHASES={"boarding","doors","pushback","startup","taxi","takeoff","climb","cruise","approach","landing","taxiin","deboarding","towin"}
JP.PHASE_TEXT={boarding="Boarding",doors="Doors closed",pushback="Pushback",startup="Engine start",taxi="Taxiing",takeoff="Take-off",
	climb="Climbing",cruise="Cruising",approach="Approach",landing="Landing",taxiin="Taxiing to the stand",deboarding="Arrived",towin="Towing into the hangar",parked="Arrived - stepping off"}

export type Segment=FP.Segment
export type Pose=FP.Pose
export type Slot={id: number,name: string,where: string,cf: CFrame,arrive: {Vector3},arriveR: number,depart: {Vector3},departR: number,rollFrom: number,hides: string?,exit: {Vector3}}
export type Timeline={kind: string,slot: number,delay: number,dir: string,from: string,to: string,segments: {Segment},
	phases: {[string]: {t0: number,t1: number}},duration: number,park: CFrame}
export type Window={field: string,a: number,b: number}

local A=CityPlan.AIRPORT
local G=CityPlan.GROUND
local HY=A.apronTop
local PY=CityPlan.ROAD_TOP
local AY=if okMetro and typeof(MetroPlan)=="table" and typeof(MetroPlan.APRON)=="table" and typeof(MetroPlan.APRON.top)=="number" then MetroPlan.APRON.top else G+.25
local RZ=(A.runway.z1+A.runway.z2)/2
local TZ=(A.taxiway.z1+A.taxiway.z2)/2
local WEST=A.connectors[1]
local PZ=FP.PM_LINE
local hg=A.hangar
local HZ=(hg.z1+hg.z2)/2
local JX=A.companyJetStand.Position.X
local rad=math.rad
local function v(x: number,y: number,z: number): Vector3 return Vector3.new(x,y,z) end

------------------------------------------------------------------------------------------------ places
JP.POINTS=Aircraft.points(JP.KIND,JP.SCALE)
local pts=JP.POINTS
-- parked in Hangar 1, nose west (towed in nose first); the stand in front of the hangar door (arrival: nose west)
JP.HOME_PARK=CFrame.lookAt(v(-930,HY,HZ),v(-1000,HY,HZ))
JP.HOME_STAND=CFrame.lookAt(v(JX,HY,HZ),v(JX-60,HY,HZ))
JP.HANGAR_X=hg.x2 -- door plane (the hangar opens east)
-- Port Meridian stands (pivot = tyre contact on the centre line, nose west). The airstair is on the left (south)
-- side; exit = where the companions walk after deboarding (rig root height; slot 1: forward round the nose and
-- south between the apron and helipad fences, slot 2: south-west along the apron fence towards the hall).
JP.PM_SLOTS={
	{id=1,name="VIP apron",where="on the VIP apron",cf=CFrame.lookAt(v(600,AY,7612),v(560,AY,7612)),
		arrive={v(470,PY,PZ),v(632,PY,PZ),v(632,AY,7612),v(600,AY,7612)},arriveR=28,
		depart={v(600,AY,7612),v(552,AY,7612),v(552,PY,PZ),v(500,PY,PZ)},departR=26,rollFrom=500,hides=nil,
		exit={v(575,AY+3,7622),v(558,AY+3,7628),v(558,AY+3,7660)}},
	{id=2,name="Stand 2",where="at Stand 2",cf=CFrame.lookAt(v(480,AY,7664),v(440,AY,7664)),
		arrive={v(470,PY,PZ),v(520,PY,PZ),v(520,AY,7664),v(480,AY,7664)},arriveR=24,
		depart={v(480,AY,7664),v(450,AY,7664),v(450,PY,PZ),v(400,PY,PZ)},departR=24,rollFrom=400,hides="PM2",
		exit={v(452,AY+3,7680),v(452,AY+3,7700),v(300,AY+3,7705)}},
} :: {Slot}
function JP.slot(i: number?): Slot return JP.PM_SLOTS[i or 1] or JP.PM_SLOTS[1] end
-- the founder after the flight: by the VIP limousine stand in Port Meridian (under the canopy, facing the bay) /
-- City Airport arrivals (the shuttle's arrival point)
local limo=if okMetro and typeof(MetroPlan)=="table" and typeof(MetroPlan.VIP_LIMO)=="table" and typeof(MetroPlan.VIP_LIMO.stand)=="CFrame" then MetroPlan.VIP_LIMO.stand :: CFrame else CFrame.new(176,PY,7762)
JP.ARRIVAL={abroad=CFrame.lookAt(v(limo.X-8,G+3.3,limo.Z-12),v(limo.X-8,G+3.3,limo.Z)),home=A.arrival}
-- Placement spots after a flight (JetService takes the first one no other character stands on): the arrival
-- point, then lateral steps of ARRIVAL_STEP studs along it (Port Meridian: along the kerb under the canopy; City
-- Airport: along the east end of the arrivals hall). Checked against the built world (tests/guests_jet/clearance.py).
JP.ARRIVAL_STEP=3
JP.ARRIVAL_OFFSETS={0,-1,1,-2,2,-3}
function JP.arrivalSpots(dest: string): {CFrame}
	local base=if dest=="abroad" then JP.ARRIVAL.abroad else JP.ARRIVAL.home
	local out: {CFrame}={}
	for _,k in JP.ARRIVAL_OFFSETS do
		local off=if dest=="abroad" then Vector3.new(k*JP.ARRIVAL_STEP,0,0) else Vector3.new(k*JP.ARRIVAL_STEP,0,0)
		table.insert(out,base+off)
	end
	return out
end
-- the boarded founder's character is held here (anchored, below the ground) while the client shows the ride
JP.HOLD_HOME=CFrame.new(-930,G-40,HZ)
function JP.hold(dest: string,slot: number?): CFrame
	if dest=="abroad" then local c=JP.slot(slot).cf;return CFrame.new(c.X,G-40,c.Z) end
	return JP.HOLD_HOME
end
-- Crew corner in the south-west of Hangar 1 (AirportBuilder dresses it: sofa, coffee table, coffee counter,
-- lockers, planning screen, carpet, a "FLIGHT CREW" board): where the two company pilots wait. spots = rig root
-- frames (captain on the sofa, first officer standing at the coffee counter), via = the first steps out of the
-- corner per pilot (in front of the sofa, clear of its arm and the table), door = the corner's opening towards the jet.
JP.CREW={spots={CFrame.lookAt(v(-992.6,HY+2.95,2701.5),v(-980,HY+2.95,2701.5)),CFrame.lookAt(v(-984.5,HY+3,2711.2),v(-984.5,HY+3,2716))},
	sit={true,false},via={{v(-989.5,HY+3,2701.5),v(-989.5,HY+3,2697)},{v(-975,HY+3,2704)}},door=v(-960,HY+3,2694)}
-- Companions come in through the hangar's open door (south end) and round the left wingtip to the airstair.
JP.COMPANION_FROM=v(-852,HY+3,2700)
JP.COMPANION_VIA={v(-905,HY+3,2675),v(-948,HY+3,2656)}
-- World path (rig root height) from `from` (+ optional waypoints) to the left airstair foot, up into the cabin and
-- to `seat` (model frame of the jet at cf).
function JP.boardPath(cf: CFrame,seat: CFrame,from: Vector3,via: {Vector3}?): {Vector3}
	local z=pts.doorL1.Position.Z
	local fl=pts.cabin.floorY+3
	local out: {Vector3}={from}
	local extra: {Vector3}=via or {}
	for _,p in extra do table.insert(out,p) end
	table.insert(out,cf*Vector3.new(-8.6,3,z));table.insert(out,cf*Vector3.new(-5.6,3,z))
	table.insert(out,cf*Vector3.new(-2.1,fl,z));table.insert(out,cf*Vector3.new(0,fl,z))
	table.insert(out,cf*Vector3.new(0,fl,seat.Position.Z+(if seat.LookVector.Z<0 then 1.4 else -1.4)))
	table.insert(out,cf*seat.Position)
	return out
end
-- pilots: crew corner spot i -> airstair -> cockpit seat i (1 captain, 2 first officer)
function JP.crewPath(cf: CFrame,i: number): {Vector3}
	local spot=JP.CREW.spots[i] or JP.CREW.spots[1]
	local seat=if i==1 then pts.captain else pts.firstOfficer
	local way: {Vector3}=table.clone(JP.CREW.via[i] or JP.CREW.via[1])
	table.insert(way,JP.CREW.door)
	local path=JP.boardPath(cf,seat,spot.Position,way)
	return path
end
-- companion k (1..3) boarding at home: hangar door -> round the wingtip -> cabin seat (seats 1, 2, 4: the founder
-- has seat 3, the window seat camera)
JP.COMPANION_SEATS={1,2,4}
function JP.companionPath(cf: CFrame,k: number,atHome: boolean,slot: number?): {Vector3}
	local seat=pts.cabinSeats[JP.COMPANION_SEATS[k] or 1]
	if atHome then return JP.boardPath(cf,seat,JP.COMPANION_FROM,JP.COMPANION_VIA) end
	-- Port Meridian: from the slot's exit path (reversed) to the seat
	local ex=JP.slot(slot).exit
	local list: {Vector3}={}
	for i=#ex,1,-1 do table.insert(list,ex[i]) end
	local from=table.remove(list,1) :: Vector3
	return JP.boardPath(cf,seat,from,list)
end

------------------------------------------------------------------------------------------------ tracks
local makeTrack=FP.makeTrack
local profile=FP.profile
local along=FP.along
local trackPos=FP.trackPos
type Tracks={push: FP.Track?,taxi: FP.Track,roll: FP.Track,air: FP.Track,climbTo: number,descentFrom: number,flareFrom: number,rollout: FP.Track,taxiin: FP.Track,tow: FP.Track?}
local OUT_LIFT=-905+620
local function outTracks(slot: Slot): Tracks
	local push=FP.groundTrack({v(-930,HY,HZ),v(-700,HY,HZ),v(-700,HY,2585)},28)
	local taxi=FP.groundTrack({v(-700,HY,2585),v(-700,HY,TZ),v(WEST,HY,TZ),v(WEST,HY,RZ),v(-905,HY,RZ)},30)
	local roll=makeTrack({v(-905,HY,RZ),v(OUT_LIFT,HY,RZ)})
	local L=OUT_LIFT
	local ctrl={v(L,HY,RZ),v(L+400,G+45,RZ),v(L+800,G+115,RZ),v(1350,G+200,3150),v(1600,G+300,3600), -- 5 = top of climb
		v(1500,G+420,4200),v(700,G+560,5000),v(-700,G+600,5900),v(-1900,G+520,6600), -- 9 = top of descent
		v(-2600,G+380,7050),v(-2850,G+250,7400),v(-2450,G+170,PZ),v(-1900,G+112,PZ),v(-1300,G+55,PZ),
		v(-850,G+14,PZ) --[[ 15 = flare ]],v(-700,G+4,PZ),v(-600,PY,PZ)}
	local air=FP.airTrack(ctrl,Vector3.new(1,0,0),Vector3.new(1,0,0))
	local rollout=makeTrack({v(-600,PY,PZ),slot.arrive[1]})
	local taxiin=FP.groundTrack(slot.arrive,slot.arriveR)
	return {push=push,taxi=taxi,roll=roll,air=air,climbTo=air.marks[5],descentFrom=air.marks[9],flareFrom=air.marks[15],rollout=rollout,taxiin=taxiin,tow=nil}
end
local function backTracks(slot: Slot): Tracks
	local taxi=FP.groundTrack(slot.depart,slot.departR)
	local roll=makeTrack({v(slot.rollFrom,PY,PZ),v(-580,PY,PZ)})
	local ctrl={v(-580,PY,PZ),v(-800,G+20,PZ),v(-1040,G+60,PZ),v(-1300,G+105,PZ-6),v(-1700,G+190,7380),v(-1950,G+330,6950), -- 6 = top of climb
		v(-1700,G+520,6200),v(-500,G+680,5200),v(1000,G+700,4300),v(2300,G+560,3700), -- 10 = top of descent
		v(3000,G+330,3250),v(2700,G+180,RZ),v(2300,G+134,RZ),v(1700,G+86,RZ),
		v(1150,G+22,RZ) --[[ 15 = flare ]],v(950,G+6,RZ),v(820,HY,RZ)}
	local air=FP.airTrack(ctrl,Vector3.new(-1,0,0),Vector3.new(-1,0,0),function(p: Vector3): Vector3
		return if p.X>-1100 and p.Z>PZ then Vector3.new(p.X,p.Y,PZ) else p
	end)
	local rollout=makeTrack({v(820,HY,RZ),v(-880,HY,RZ)})
	local taxiin=FP.groundTrack({v(-880,HY,RZ),v(WEST,HY,RZ),v(WEST,HY,TZ),v(-700,HY,TZ),v(-700,HY,HZ),v(JX,HY,HZ)},30)
	local tow=makeTrack({v(JX,HY,HZ),v(-930,HY,HZ)})
	return {push=nil,taxi=taxi,roll=roll,air=air,climbTo=air.marks[6],descentFrom=air.marks[10],flareFrom=air.marks[15],rollout=rollout,taxiin=taxiin,tow=tow}
end
local trackCache: {[string]: Tracks}={}
local function tracks(dir: string,slot: Slot): Tracks
	local key=dir..slot.id
	local c=trackCache[key]
	if c then return c end
	local t=if dir=="out" then outTracks(slot) else backTracks(slot)
	trackCache[key]=t
	return t
end

------------------------------------------------------------------------------------------------ segments
local function pointTrack(cf: CFrame): FP.Track return makeTrack({cf.Position}) end
local function holdSeg(phase: string,cf: CFrame,T: number): Segment
	return {phase=phase,mode="hold",t0=0,t1=T,track=pointTrack(cf),s0=0,s1=0,prof=profile(1e-3,0,0,0,1),reverse=false,hold=cf,aoa0=0,aoa1=0}
end
local function moveSeg(phase: string,mode: string,tr: FP.Track,s0: number,s1: number,prof: FP.Profile,reverse: boolean?,aoa0: number?,aoa1: number?): Segment
	return {phase=phase,mode=mode,t0=0,t1=prof.T,track=tr,s0=s0,s1=s1,prof=prof,reverse=reverse==true,hold=nil,aoa0=aoa0 or 0,aoa1=aoa1 or aoa0 or 0}
end
local segPose: (Segment,number)->Pose
local function frameAt(tr: FP.Track,s: number,reverse: boolean): CFrame
	local p=trackPos(tr,s)
	local t=FP.tangent(tr,s,6)
	local f=Vector3.new(t.X,0,t.Z)
	f=if f.Magnitude>1e-5 then f.Unit else Vector3.new(0,0,-1)
	if reverse then f=-f end
	return CFrame.lookAt(p,p+f)
end
-- The segments of a flight (times filled in by timeline()).
local function build(kind: string,slot: Slot,delay: number): ({Segment},string)
	local C=JP.CONFIG
	local segs: {Segment}={}
	local function add(s: Segment) table.insert(segs,s) end
	local function air(t: Tracks,lift: number)
		local a=t.air
		add(moveSeg("climb","air",a,0,t.climbTo,profile(t.climbTo,lift,C.climbSpeed,C.climbSpeed,(C.climbSpeed^2-lift^2)/(2*t.climbTo))))
		add(moveSeg("cruise","air",a,t.climbTo,t.descentFrom,profile(t.descentFrom-t.climbTo,C.climbSpeed,C.cruiseSpeed,C.cruiseSpeed,12)))
		local apL=t.flareFrom-t.descentFrom
		add(moveSeg("approach","air",a,t.descentFrom,t.flareFrom,profile(apL,C.cruiseSpeed,C.cruiseSpeed,C.approachSpeed,(C.cruiseSpeed^2-C.approachSpeed^2)/(2*apL)),false,rad(3)))
		local flL=a.length-t.flareFrom
		add(moveSeg("landing","air",a,t.flareFrom,a.length,profile(flL,C.approachSpeed,C.approachSpeed,C.touchdown,(C.approachSpeed^2-C.touchdown^2)/(2*flL)),false,rad(3),rad(6)))
		local rL=t.rollout.length
		-- roll-out: hold the touchdown speed, then brake (at least CONFIG.brake) - frees the runway sooner
		add(moveSeg("landing","rollout",t.rollout,0,rL,profile(rL,C.touchdown,C.touchdown,18,math.max(C.brake,(C.touchdown^2-18^2)/(2*rL)))))
	end
	if kind=="out" then
		local t=tracks("out",slot)
		local push=t.push :: FP.Track
		add(holdSeg("boarding",JP.HOME_PARK,C.boarding+delay))
		add(holdSeg("doors",JP.HOME_PARK,C.doors))
		local pushSeg=moveSeg("pushback","ground",push,0,push.length,profile(push.length,0,C.pushSpeed,0,C.pushAcc),true)
		add(pushSeg)
		add(holdSeg("startup",frameAt(push,push.length,true),C.startup))
		add(moveSeg("taxi","ground",t.taxi,0,t.taxi.length,profile(t.taxi.length,0,C.taxiSpeed,0,C.taxiAcc)))
		local L=t.roll.length
		add(moveSeg("takeoff","roll",t.roll,0,L,profile(L,0,C.liftoff,C.liftoff,C.liftoff^2/(2*L))))
		air(t,C.liftoff)
		local ti=t.taxiin
		add(moveSeg("taxiin","ground",ti,0,ti.length,profile(ti.length,18,24,0,4)))
		add(holdSeg("deboarding",slot.cf,C.deboarding))
		return segs,"out"
	end
	-- "back" (trip home) or "ferry" (empty, home)
	local t=tracks("back",slot)
	local ferry=kind=="ferry"
	add(holdSeg("boarding",slot.cf,(if ferry then C.ferryBoarding else C.boarding)+delay))
	add(holdSeg("doors",slot.cf,C.doors))
	add(holdSeg("startup",slot.cf,C.startup))
	add(moveSeg("taxi","ground",t.taxi,0,t.taxi.length,profile(t.taxi.length,0,C.taxiSpeed*0.8,0,C.taxiAcc)))
	local L=t.roll.length
	add(moveSeg("takeoff","roll",t.roll,0,L,profile(L,0,C.liftoff,C.liftoff,C.liftoff^2/(2*L))))
	air(t,C.liftoff)
	local ti=t.taxiin
	add(moveSeg("taxiin","ground",ti,0,ti.length,profile(ti.length,18,C.taxiSpeed,0,C.taxiAcc)))
	add(holdSeg("deboarding",JP.HOME_STAND,if ferry then C.ferryDeboarding else C.deboarding))
	local tow=t.tow :: FP.Track
	add(moveSeg("towin","ground",tow,0,tow.length,profile(tow.length,0,C.towSpeed,0,C.towAcc)))
	return segs,"back"
end
local tlCache: {[string]: Timeline}={}
local tlCount=0
-- The flight `kind` ("out" | "back" | "ferry") to / from Port Meridian slot `slot`, with `delay` seconds of extra
-- boarding. Times are seconds since the flight start.
function JP.timeline(kind: string,slot: number?,delay: number?): Timeline
	local k=if kind=="out" or kind=="back" or kind=="ferry" then kind else "out"
	local sl=JP.slot(slot)
	local d=math.clamp(math.floor((delay or 0)*10+0.5)/10,0,JP.CONFIG.maxDelayEmpty)
	local key=k..":"..sl.id..":"..d
	local c=tlCache[key]
	if c then return c end
	local segs,dir=build(k,sl,d)
	local t=0
	local phases: {[string]: {t0: number,t1: number}}={}
	for _,s in segs do
		local T=s.t1-s.t0
		s.t0=t;s.t1=t+T;t+=T
		local ph=phases[s.phase]
		if ph then ph.t1=s.t1 else phases[s.phase]={t0=s.t0,t1=s.t1} end
	end
	local tl: Timeline={kind=k,slot=sl.id,delay=d,dir=dir,from=if dir=="out" then "home" else "abroad",to=if dir=="out" then "abroad" else "home",
		segments=segs,phases=phases,duration=t,park=if dir=="out" then sl.cf else JP.HOME_PARK}
	tlCount+=1
	if tlCount>64 then table.clear(tlCache);tlCount=0 end
	tlCache[key]=tl
	return tl
end
-- Phase name at tau (seconds since the flight start); "parked" after the end, "waiting" before the start.
function JP.phaseAt(tl: Timeline,tau: number): string
	if tau<0 then return "waiting" end
	if tau>=tl.duration then return "parked" end
	for _,s in tl.segments do if tau<s.t1 then return s.phase end end
	return "parked"
end
-- departs = pushback (home) / taxi start (Port Meridian), arrives = deboarding start, done = end of the flight
function JP.times(tl: Timeline,start: number): (number,number,number)
	local dep=if tl.dir=="out" then tl.phases.pushback.t0 else tl.phases.taxi.t0
	return start+dep,start+tl.phases.deboarding.t0,start+tl.duration
end

------------------------------------------------------------------------------------------------ poses
local function smooth(x: number): number x=math.clamp(x,0,1);return x*x*(3-2*x) end
local function flat(d: Vector3): Vector3
	local f=Vector3.new(d.X,0,d.Z)
	return if f.Magnitude>1e-5 then f.Unit else Vector3.new(0,0,-1)
end
local function bankAt(tr: FP.Track,s: number,speed: number): number
	local D=60
	local a=flat(FP.tangent(tr,math.max(0,s-D),20));local b=flat(FP.tangent(tr,math.min(tr.length,s+D),20))
	local dist=math.min(tr.length,s+D)-math.max(0,s-D)
	if dist<1 then return 0 end
	local ang=math.atan2(a:Cross(b).Y,a:Dot(b))
	local kappa=-ang/dist
	local C=JP.CONFIG
	return math.clamp(math.atan(speed*speed*kappa/C.gEff),-C.maxBank,C.maxBank)
end
local OFF: {[string]: boolean}={boarding=true,doors=true,pushback=true,deboarding=true,towin=true,parked=true,waiting=true}
function segPose(seg: Segment,tau: number): Pose
	local lt=tau-seg.t0
	if seg.mode=="hold" then
		return {cf=seg.hold or CFrame.new(),phase=seg.phase,speed=0,onGround=true,gearDown=true,engines=not OFF[seg.phase],altitude=0}
	end
	local d,speed=along(seg.prof,lt)
	local s=seg.s0+d
	local tr=seg.track
	local pos=trackPos(tr,s)
	local tan=FP.tangent(tr,s,if seg.mode=="air" then 16 else 6)
	if seg.mode~="air" then
		local heading=flat(tan)
		if seg.reverse then heading=-heading end
		local pitch=0
		if seg.mode=="roll" then pitch=rad(8)*smooth((lt-(seg.prof.T-2.2))/2.2) end
		if seg.mode=="rollout" then pitch=rad(5)*(1-smooth(lt/2.2)) end
		return {cf=CFrame.lookAt(pos,pos+heading)*CFrame.Angles(pitch,0,0),phase=seg.phase,speed=speed,onGround=true,gearDown=true,engines=not OFF[seg.phase],altitude=0}
	end
	local u=if seg.prof.T>0 then lt/seg.prof.T else 1
	local aoa=seg.aoa0+(seg.aoa1-seg.aoa0)*smooth(u)
	if seg.phase=="climb" then aoa=rad(3)+rad(5)*(1-smooth(lt/5)) end
	local bank=bankAt(tr,s,speed)
	local cf=CFrame.lookAt(pos,pos+tan)*CFrame.Angles(0,0,-bank)*CFrame.Angles(aoa,0,0)
	local ground=if pos.Z>5000 then PY else HY
	local alt=pos.Y-ground
	local gear=alt<140 and not (seg.phase=="climb" and lt>4)
	if seg.phase=="cruise" then gear=false end
	return {cf=cf,phase=seg.phase,speed=speed,onGround=false,gearDown=gear,engines=true,altitude=alt}
end
-- Pose at tau seconds since the flight start (before: the departure park, after: the arrival park).
function JP.pose(tl: Timeline,tau: number): Pose
	local segs=tl.segments
	if tau<=0 then return segPose(segs[1],0) end
	if tau>=tl.duration then
		return {cf=tl.park,phase="parked",speed=0,onGround=true,gearDown=true,engines=false,altitude=0}
	end
	for _,seg in segs do if tau<seg.t1 then return segPose(seg,tau) end end
	return segPose(segs[#segs],segs[#segs].t1)
end
-- Airstair down? Boarding, deboarding and parked at Port Meridian (waiting for the founder); stowed when parked
-- in the hangar and whenever the jet moves.
function JP.stairsDown(tl: Timeline?,tau: number,parkedAt: string?): boolean
	if not tl or tau>=tl.duration or tau<0 then return parkedAt=="abroad" end
	local ph=JP.phaseAt(tl,tau)
	return ph=="boarding" or ph=="deboarding"
end
-- Tug (pushback at home: in front of the nose gear facing the jet; tow-in: ahead, pulling; startup: drives away
-- to the side for 4 s): world frame, or nil.
JP.TUG_GAP=3.2
function JP.tug(tl: Timeline,tau: number): CFrame?
	local ph=JP.phaseAt(tl,tau)
	local ng=pts.noseGearZ
	if ph=="pushback" or ph=="doors" and tl.dir=="out" then
		return JP.pose(tl,tau).cf*CFrame.new(0,0,ng-JP.TUG_GAP)*CFrame.Angles(0,math.pi,0)
	end
	if ph=="startup" and tl.dir=="out" then
		local st=tl.phases.startup
		local u=smooth((tau-st.t0)/math.min(4,st.t1-st.t0))
		local cf=JP.pose(tl,tau).cf
		return cf*CFrame.new(-u*16,0,ng-JP.TUG_GAP-u*6)*CFrame.Angles(0,math.pi-u*math.pi/2,0)
	end
	if ph=="towin" or (ph=="deboarding" and tl.dir=="back") then
		return JP.pose(tl,tau).cf*CFrame.new(0,0,ng-JP.TUG_GAP-2.4)
	end
	return nil
end
-- Pilots: "corner" (hangar crew corner), "walk" (corner -> cockpit, u), "cockpit", "leave" (cockpit -> corner, u).
function JP.crew(tl: Timeline?,tau: number,parkedAt: string?): (string,number?)
	local C=JP.CONFIG
	if not tl or tau<0 then return (if parkedAt=="abroad" then "cockpit" else "corner"),nil end
	if tau>=tl.duration then
		if tl.dir=="out" then return "cockpit",nil end
		local since=tau-tl.duration
		if since<C.crewWalk then return "leave",since/C.crewWalk end
		return "corner",nil
	end
	if tl.dir=="out" and tau<C.crewWalk then return "walk",tau/C.crewWalk end
	return "cockpit",nil
end
-- Companions (trip flights): "board" (u: up the airstair to the seat, the last 10 s of boarding), "seated",
-- "deboard" (u: down the stairs and away), nil = not shown.
JP.COMPANION_BOARD=10
function JP.companions(tl: Timeline,tau: number): (string?,number?)
	if tl.kind=="ferry" or tau<0 then return nil,nil end
	local ph=tl.phases
	if tau<ph.boarding.t1 then
		local s=ph.boarding.t1-JP.COMPANION_BOARD
		if tau<s then return nil,nil end
		return "board",(tau-s)/JP.COMPANION_BOARD
	end
	if tau<ph.deboarding.t0 then return "seated",nil end
	if tau<ph.deboarding.t1 then return "deboard",(tau-ph.deboarding.t0)/(ph.deboarding.t1-ph.deboarding.t0) end
	return nil,nil
end
-- Is the hangar parking spot in use by this flight at tau (so a client hides its own parked jet / the
-- airport's decorative jet there)?
function JP.usesHangar(tl: Timeline,tau: number): boolean
	if tau<0 or tau>=tl.duration then return false end
	local ph=tl.phases
	if tl.dir=="out" then return tau<ph.pushback.t1 end
	return tau>=ph.towin.t0
end
-- Does the flight occupy Port Meridian slot `slot` at tau (parked there counts: the caller knows "parked")?
function JP.usesSlot(tl: Timeline,tau: number): boolean
	if tau<0 then return false end
	local ph=tl.phases
	if tl.dir=="out" then return tau>=ph.taxiin.t0 end
	return tau<ph.taxi.t1
end

------------------------------------------------------------------------------------------------ separation
-- Fields = zones a movement occupies; two movements of the same field never share time (the zone box reaches
-- ZONE.reach studs along the runway axis and ZONE.alt studs up: the runway, short final and the initial climb):
--   "home"  City Airport runway + taxiway (z > taxiway - 30): the shuttle and the jets (they share the west half of
--           the taxiway and the west connector)
--   "rwy"   the same box without the taxiway (z > runway - 40): the ambient airliners (FlightPlan.ambient taxi on
--           the east half of the taxiway, the jets on the west half - they only share the runway and its ends)
--   "pm"    Port Meridian's runway (z PM_LINE - 300 .. PM_LINE + 46, x -ZONE.pmReach .. 950): shuttle + jets
--   "apron" the apron edge and the stand in front of Hangar 1 (x < -660, z 2540 .. taxiway): pushback, taxi to /
--           from the taxiway, deboarding at HOME_STAND and the tow-in (jets only)
-- tests/guests_jet/test_jet samples every scheduled flight against the shuttle, the ambient airliners and a second
-- jet (hull distance at every altitude) to prove these windows are enough.
local RW=A.runway
local TWZ1=A.taxiway.z1
JP.FIELDS={"home","rwy","pm","apron"}
JP.ZONE={reach=1600,pmReach=1700,alt=120}
function JP.inZone(field: string,p: Vector3): boolean
	local Z=JP.ZONE
	if field=="home" or field=="rwy" then
		local z1=if field=="home" then TWZ1-30 else RW.z1-40
		return p.Z>z1 and p.Z<RW.z2+300 and math.abs(p.X)<Z.reach and p.Y-HY<Z.alt
	elseif field=="pm" then
		return p.Z>PZ-300 and p.Z<PZ+46 and p.X>-Z.pmReach and p.X<950 and p.Y-PY<Z.alt
	elseif field=="apron" then
		return p.X<-660 and p.X>hg.x1-10 and p.Z>2540 and p.Z<TWZ1
	end
	return false
end
JP.SPAN_STEP=0.25
-- Time spans {a, b} (seconds from 0 to T) in which posAt(t) lies in the field's zone, sampled every SPAN_STEP s
-- (each span starts one sample early: conservative).
local function spans(field: string,posAt: (number)->Vector3?,T: number): {{number}}
	local out: {{number}}={}
	local open: number?=nil
	local t=0
	while t<=T+1e-6 do
		local p=posAt(t)
		local inside=p~=nil and JP.inZone(field,p)
		if inside and not open then open=math.max(0,t-JP.SPAN_STEP) end
		if not inside and open then table.insert(out,{open,t});open=nil end
		t+=JP.SPAN_STEP
	end
	if open then table.insert(out,{open,T}) end
	return out
end
JP.spans=spans
local function spanAt(list: {{number}},t: number): {number}
	for _,sp in list do if t>=sp[1]-1e-6 and t<=sp[2]+1e-6 then return sp end end
	return {t,t}
end
-- Field windows of a flight (seconds since its start, padded by CONFIG.guard):
--   out:  apron (doors closed .. the taxi leaves the apron), home (on the taxiway .. the climb leaves the zone), rwy
--         (lined up .. the climb leaves the zone), pm (final approach .. turned off the runway towards the stand)
--   back: pm (taxi start .. the climb leaves the zone), home / rwy (final approach .. off the runway / taxiway),
--         apron (back on the apron .. towed into the hangar)
function JP.windows(tl: Timeline): {Window}
	local cached=(tl :: any).windows
	if cached then return cached end
	local g=JP.CONFIG.guard
	local ph=tl.phases
	local sp: {[string]: {{number}}}={}
	for _,f in JP.FIELDS do sp[f]=spans(f,function(t: number): Vector3? return JP.pose(tl,t).cf.Position end,tl.duration) end
	local out: {Window}={}
	local function add(field: string,a: number,b: number) table.insert(out,{field=field,a=a-g,b=b+g}) end
	local roll=ph.takeoff.t0+0.1
	local land=ph.landing.t1-0.1 -- the end of the roll-out, still on the runway
	if tl.dir=="out" then
		add("apron",ph.doors.t0,spanAt(sp.apron,ph.doors.t0)[2])
		local h=spanAt(sp.home,roll);add("home",h[1],h[2])
		local r=spanAt(sp.rwy,roll);add("rwy",r[1],r[2])
		local p=spanAt(sp.pm,land);add("pm",p[1],p[2])
	else
		add("pm",ph.taxi.t0,spanAt(sp.pm,roll)[2])
		local h=spanAt(sp.home,land);add("home",h[1],h[2])
		local r=spanAt(sp.rwy,land);add("rwy",r[1],r[2])
		add("apron",spanAt(sp.apron,tl.duration)[1],tl.duration)
	end
	(tl :: any).windows=out
	return out
end
-- The shuttle's zone spans per cycle (seconds into the cycle; FlightPlan legs: out from 0, back after it).
local shuttleCache: {[string]: {{number}}}?=nil
local function shuttleSpans(): {[string]: {{number}}}
	local c=shuttleCache
	if c then return c end
	local out: {[string]: {{number}}}={home={},pm={}}
	local outDur=FP.leg("out").duration
	for _,dir in {"out","back"} do
		local leg=FP.leg(dir)
		local off=if dir=="out" then 0 else outDur
		for _,f in {"home","pm"} do
			for _,s in spans(f,function(t: number): Vector3? return FP.legPose(leg,t).cf.Position end,leg.duration) do
				table.insert(out[f],{off+s[1],off+s[2]})
			end
		end
	end
	shuttleCache=out
	return out
end
-- The ambient airliners' runway spans relative to each event's start (arrival / departure).
local ambientRel: {[string]: {{number}}}?=nil
local function ambientSpans(): {[string]: {{number}}}
	local c=ambientRel
	if c then return c end
	local rel: {[string]: {{number}}}={}
	for k=0,3 do
		for _,e in FP.ambient(k) do
			if (e.kind=="arrival" or e.kind=="departure") and not rel[e.kind] then
				rel[e.kind]=spans("rwy",function(t: number): Vector3?
					local p=FP.ambientPose(e,e.t0+t)
					return if p then p.cf.Position else nil
				end,e.duration)
			end
		end
	end
	ambientRel=rel
	return rel
end
local ambCycle: {[number]: {{number}}}={}
local ambCount=0
-- absolute runway windows (padded) of the ambient airliners of cycle k
local function ambientWindows(k: number): {{number}}
	local c=ambCycle[k]
	if c then return c end
	local rel=ambientSpans()
	local pad=JP.CONFIG.pad
	local out: {{number}}={}
	for _,e in FP.ambient(k) do
		local list=rel[e.kind]
		if list then for _,s in list do table.insert(out,{e.t0+s[1]-pad,e.t0+s[2]+pad}) end end
	end
	ambCount+=1
	if ambCount>48 then table.clear(ambCycle);ambCount=0 end
	ambCycle[k]=out
	return out
end
-- Absolute windows {a, b} of the shuttle (field "home" / "pm") or the ambient airliners ("rwy") within [a, b].
function JP.trafficWindows(field: string,a: number,b: number): {{number}}
	local I=FP.interval()
	local e0=FP.CONFIG.epoch
	local k0=math.floor((a-e0)/I)-1
	local k1=math.floor((b-e0)/I)+1
	local out: {{number}}={}
	if field=="home" or field=="pm" then
		local pad=JP.CONFIG.pad
		local list=shuttleSpans()[field]
		for k=k0,k1 do
			local base=e0+k*I
			for _,s in list do
				local x1,x2=base+s[1]-pad,base+s[2]+pad
				if x2>a and x1<b then table.insert(out,{x1,x2}) end
			end
		end
	elseif field=="rwy" then
		for k=k0,k1 do for _,w in ambientWindows(k) do if w[2]>a and w[1]<b then table.insert(out,w) end end end
	end
	return out
end
-- Seconds of [a, b] (server time) during which the shuttle / the ambient airliners use the field.
function JP.trafficOverlap(field: string,a: number,b: number): number
	local total=0
	for _,w in JP.trafficWindows(field,a,b) do total+=math.max(0,math.min(b,w[2])-math.max(a,w[1])) end
	return total
end
function JP.shuttleOverlap(field: string,a: number,b: number): number
	return if field=="home" or field=="pm" then JP.trafficOverlap(field,a,b) else 0
end
function JP.ambientOverlap(a: number,b: number): number return JP.trafficOverlap("rwy",a,b) end
function JP.shuttleBusy(field: string,a: number,b: number): boolean return JP.shuttleOverlap(field,a,b)>0 end
-- Absolute windows of a published flight.
function JP.absWindows(tl: Timeline,start: number): {Window}
	local out: {Window}={}
	for _,w in JP.windows(tl) do table.insert(out,{field=w.field,a=start+w.a,b=start+w.b}) end
	return out
end
-- Overlap (seconds) of the flight `kind` / `slot` starting at `now` with `d` s of extra boarding with the traffic
-- and `others` (absolute windows of other jets).
function JP.overlapAt(kind: string,slot: number?,now: number,d: number,others: {Window}?): number
	local overlap=0
	local list: {Window}=others or {}
	for _,w in JP.windows(JP.timeline(kind,slot,0)) do
		local a,b=now+w.a+d,now+w.b+d
		overlap+=JP.trafficOverlap(w.field,a,b)
		for _,o in list do if o.field==w.field then overlap+=math.max(0,math.min(b,o.b)-math.max(a,o.a)) end end
	end
	return overlap
end
-- The smallest departure delay (whole seconds, <= maxDelay, default CONFIG.maxDelay, at most CONFIG.maxDelayEmpty)
-- for a flight starting at `now` whose field windows overlap neither the traffic nor `others`. Returns (delay,
-- clear): when no such delay exists, the delay with the least overlap (clear = false; JetService then refuses a
-- founder flight with RUNWAY_BUSY instead of departing into a conflict).
function JP.schedule(kind: string,slot: number?,now: number,others: {Window}?,maxDelay: number?): (number,boolean)
	local limit=math.floor(math.min(maxDelay or JP.CONFIG.maxDelay,JP.CONFIG.maxDelayEmpty))
	local bestD,best=0,math.huge
	for d=0,limit do
		local overlap=JP.overlapAt(kind,slot,now,d,others)
		if overlap<=0 then return d,true end
		if overlap<best-1e-6 then best=overlap;bestD=d end
	end
	return bestD,false
end
return JP
