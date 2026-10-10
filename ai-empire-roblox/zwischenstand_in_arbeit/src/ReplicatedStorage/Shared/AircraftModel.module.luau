--!strict
-- AircraftModel: generic airliners built from anchored parts (no meshes required, no asset ids, no real brands).
-- Two types with real-world proportions (assets/vehicles/skyliner320|380/manifest.json, 1 stud = 0.28 m):
--   kind "320" (default): narrow-body twin, 134.2 x 127.9 x 42.1 studs at real size;
--   kind "380": double-deck quad, 259.7 x 284.8 x 86.0 studs at real size.
-- Shape: circular (320) / two-circle oval (380) barrel from Cylinder parts; nose, tail cone and wing-body
-- fairing from a few long, overlapping ellipsoids (SpecialMesh Sphere; few slices = few crease lines);
-- wings, winglets, stabilisers and fin are exact planforms built from right-triangle WedgeParts (any
-- triangle = 2 wedges), swept, tapered, with dihedral;
-- underwing engines (intake lip, fan disc with blades and spinner, nacelle, core, exhaust plug, pylon),
-- individual windows (320) or window bands (380), door outlines ("Outline"), cheatline, landing gear,
-- nav/beacon lights. The 320 (full LOD) has a glazed cockpit: a canopy lattice over the lower nose with an
-- airliner's window band - two front panes (V, centre post) and two side windows per side, all exact
-- see-through quads, opaque roof above a dark window surround - plus seats, pedestal, glareshield and an
-- instrument panel with primary flight / navigation displays, so seated pilots show from outside
-- (tests/flight/test_aircraft checks the lines of sight to both heads from the gate A1 lounge).
-- Frame (unchanged contract): nose towards -Z (the CFrame's LookVector), +Y up, origin on the ground (tyre
-- contact) on the centre line - 320: fuselage midpoint; 380: main-gear centroid (same as the Blender FBX).
-- Options (all optional, compatible with the old 25-part model):
--   scale    1 = the old 66-stud reference length for the 320 (callers keep their sizes);
--            AircraftModel.REAL_SCALE = real size (134.2 studs for the 320).
--   livery   tail fin, cheatline, nacelles, winglets;  body: fuselage colour;  collide: fuselage, wings,
--            engines and gear collide (default false = pure decoration);  name: Model name.
--   kind     "320" | "380";  lod "full" (<= ~350 parts) | "medium" (~76) | "low" (<= 30) - the distance LODs
--            keep a smooth silhouette (LOD_LOFTS: a few long ellipsoids per cone; the 320's upper nose one
--            ellipsoid with the windshield band painted on);
--   airline  title text on the fuselage + tail letters (e.g. "AI Empire Air", "Meridian Air"); nil = none;
--   mesh     false = never use an imported mesh;
--   airstair (bizjet) true = built with the airstair deployed (AircraftModel.setAirstair toggles it).
-- kind "bizjet" (package "guests_jet"): the company business jet, numbers in studs at BIZJET_SCALE (1.6 =
--   46 x 41.6 x 15.5 studs), same attachments / LODs / Spin / Gear conventions; never meshed. kinds() still
--   lists the airliners only.
-- Imported meshes: if ReplicatedStorage.Assets.Aircraft.<Skyliner320|Skyliner380> (or the manifest's
-- ReplicatedStorage.VehicleAssets.<Name>) exists - the owner imported the Blender FBX in Studio - and lod is
-- "full", a scaled, anchored clone is used instead of the parts (see assets/vehicles/IMPORT_IN_ROBLOX.md).
-- Every model gets an invisible PrimaryPart "AircraftRoot" at the origin with Attachments for boarding:
-- DoorL1 (door centre, facing out; attributes BoardingDoor = true and DoorHalf = half door height - the
-- airport package's jet bridges dock there), DoorR1, DoorL2, CaptainSeat, FirstOfficerSeat (rig root of a
-- seated pilot), CockpitCamera (jump seat behind the pilots), CabinCamera (window seat ahead of the wing
-- root, looking out at the wing and the horizon), CabinSeat1..6
-- (AircraftModel.points(kind, scale) returns the same local CFrames plus noseGearZ/doorHalf/cabin data
-- without building anything).
-- Client helpers: parts with attribute Spin (fan discs/blades, axis = local X of the "Fan" disc) and Gear
-- (landing gear) let animators spin the fans and hide the gear in flight (AircraftMover). Decorative parts
-- never collide, touch or query and cast no shadow.
-- AircraftModel.buildHelicopter: the VIP helicopter (~47 parts, rotors with attribute Rotor = main | tail).
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local AircraftModel={}
export type Options={scale: number?,livery: Color3?,body: Color3?,collide: boolean?,name: string?,kind: string?,lod: string?,airline: string?,mesh: boolean?,airstair: boolean?}
export type Points={doorL1: CFrame,doorR1: CFrame,doorL2: CFrame,captain: CFrame,firstOfficer: CFrame,cockpitCamera: CFrame,cabinCamera: CFrame,
	cabinSeats: {CFrame},cabin: {floorY: number,ceilingY: number,wallX: number,z1: number,z2: number,windowY: number},
	length: number,span: number,height: number,noseZ: number,tailZ: number,mainGearZ: number,noseGearZ: number,doorHalf: number}
AircraftModel.REAL_SCALE=134.18/66
local LEGACY=66/134.18 -- scale 1 = the old 66-stud aircraft
local MESH_NAMES: {[string]: string}={["320"]="Skyliner320",["380"]="Skyliner380"}
local rgb=Color3.fromRGB
local WINDOW=rgb(30,38,48)
local GLASS=rgb(34,48,62)
local INK=rgb(36,38,42)
local METAL=rgb(150,154,160)
local LIP=rgb(206,210,214)
local WING=rgb(208,212,218)
local BELLY=rgb(196,202,208)
local GOLD=rgb(212,170,72)

------------------------------------------------------------------------------------------------ types
type Sample={z: number,top: number,bot: number,hw: number,c: number?}
type Station={x: number,le: number,te: number,t: number}
type Engine={x: number,y: number,zf: number,len: number,dia: number,fan: number}
type Spec={
	key: string,length: number,span: number,height: number,noseZ: number,tailZ: number,
	circles: {{y: number,r: number}},barrel: {number},belly: {Vector3},
	nose: {Sample},tail: {Sample},wing: {Station},wingY: number,dihedral: number,
	winglet: {h: number,cant: number,topLe: number,topTe: number,fence: boolean},
	engines: {Engine},hstab: {Station},hstabY: {number},fin: {{y: number,le: number,te: number,t: number}},
	gear: {noseZ: number,noseTop: number,noseD: number,mainX: {number},mainZ: {number},mainTop: number,mainD: number,bogie: {number}},
	decks: {{y: number,z1: number,z2: number,pitch: number,w: number,h: number,band: boolean}},
	doors: {{z: number,y: number,w: number,h: number}},stripeY: number,titleY: number,titleZ: number,
	cockpit: boolean,points: Points,noseFine: {Sample}?,tailFine: {Sample}?,
}
local function sample(z: number,top: number,bot: number,hw: number,c: number?): Sample return {z=z,top=top,bot=bot,hw=hw,c=c} end
local function station(x: number,le: number,te: number,t: number): Station return {x=x,le=le,te=te,t=t} end

------------------------------------------------------------------------------------------------ specs (real studs)
local SPECS: {[string]: Spec}={}
SPECS["320"]={
	key="320",length=134.18,span=127.85,height=42.14,noseZ=-67.09,tailZ=67.09,
	circles={{y=13.7,r=7.2}},barrel={-49.4,33},belly={Vector3.new(0,8.4,-5.5),Vector3.new(6.9,3.2,27)},
	nose={sample(-66.4,12.5,10.9,1.7,1.1),sample(-65.0,13.3,9.7,3.2,2.6),sample(-62.9,13.85,8.5,4.6,3.6),sample(-60.3,14.05,7.6,5.6,4.2),
		sample(-57.3,14.2,7.0,6.3,4.4),sample(-54.3,14.35,6.65,6.85,4.4),sample(-51.4,14.5,6.5,7.15,3.6)},
	tail={sample(33,20.9,6.5,7.2,6),sample(38,20.95,7.4,7.0,6),sample(43,20.9,8.7,6.55,6),sample(48,20.7,10.4,5.85,6),
		sample(53,20.35,12.3,4.9,6),sample(58,19.75,14.2,3.7,5.5),sample(62.2,19.1,15.7,2.5,4),sample(65.6,18.5,16.9,1.3,1.5)},
	wing={station(5.5,-22.6,4.6,2.1),station(22,-14.3,4.9,1.6),station(42,-4.0,8.0,1.1),station(61.5,6.0,11.3,0.7)},wingY=9.7,dihedral=math.rad(5.2),
	winglet={h=8.4,cant=1.3,topLe=11.6,topTe=13.6,fence=false},
	engines={{x=20.54,y=6.2,zf=-27.3,len=29.8,dia=9.18,fan=6.96}},
	hstab={station(0.8,46.6,60.8,0.9),station(22.2,58.7,63.7,0.4)},hstabY={17.9,20.1},
	fin={{y=20.3,le=37.6,te=61.6,t=1.5},{y=42.14,le=56.4,te=64.4,t=0.6}},
	gear={noseZ=-50.2,noseTop=7.2,noseD=2.72,mainX={13.55},mainZ={-3.9},mainTop=10.0,mainD=4.17,bogie={1}},
	decks={{y=16.35,z1=-44.6,z2=29.6,pitch=2.53,w=0.8,h=1.12,band=false}},
	doors={{z=-46.6,y=15.4,w=2.9,h=6.3},{z=30.8,y=15.6,w=2.8,h=6.1},{z=-9.4,y=15.9,w=1.8,h=3.3},{z=-6.4,y=15.9,w=1.8,h=3.3}},
	stripeY=11.9,titleY=18.0,titleZ=-30,cockpit=true,points=nil :: any,
}
SPECS["380"]={
	key="380",length=259.73,span=284.82,height=86.04,noseZ=-126.79,tailZ=132.95,
	circles={{y=19.1,r=12.8},{y=23.5,r=12.8}},barrel={-95,52},belly={Vector3.new(0,10.6,-6),Vector3.new(12.4,5.6,52)},
	nose={sample(-125.6,22.0,18.6,3.0,1.6),sample(-123.0,25.5,15.0,6.2,4.0),sample(-119.0,29.0,11.4,9.1,5.6),sample(-113.5,32.4,8.6,11.2,7),
		sample(-107,34.6,7.0,12.4,7.5),sample(-100.5,35.8,6.4,12.8,7),sample(-95.5,36.3,6.3,12.9,5)},
	tail={sample(52,36.3,6.3,12.9,11),sample(62,36.4,8.0,12.5,11),sample(72,36.3,10.6,11.6,11),sample(82,36.0,14.0,10.3,11),
		sample(92,35.4,17.6,8.6,11),sample(102,34.6,21.2,6.6,10),sample(112,33.6,24.4,4.6,9),sample(121,32.4,27.2,2.8,7),sample(128.5,31.2,29.0,1.4,4.5)},
	wing={station(11,-50.5,15.5,4.2),station(50,-23.4,20.5,3.0),station(95,8.4,36.2,1.9),station(142.4,40.0,52.6,1.0)},wingY=11.8,dihedral=math.rad(5.6),
	winglet={h=8.0,cant=0,topLe=50.0,topTe=54.6,fence=true},
	engines={{x=52.6,y=12.4,zf=-56,len=29,dia=12.6,fan=10.5},{x=91.6,y=17.2,zf=-31,len=28,dia=12.4,fan=10.3}},
	hstab={station(1.5,95,127,1.4),station(54,124.6,134.8,0.6)},hstabY={30.0,34.6},
	fin={{y=35.8,le=82,te=128,t=2.6},{y=86.04,le=121.5,te=137.2,t=1.0}},
	gear={noseZ=-100,noseTop=7.0,noseD=4.4,mainX={19.5,7.2},mainZ={-2.5,4.2},mainTop=12.4,mainD=4.8,bogie={2,3}},
	decks={{y=15.6,z1=-92,z2=50,pitch=2.6,w=0.8,h=1.6,band=true},{y=29.4,z1=-84,z2=46,pitch=2.6,w=0.8,h=1.6,band=true}},
	doors={{z=-90.5,y=13.6,w=3.8,h=6.8},{z=-55,y=13.6,w=3.8,h=6.8},{z=-14,y=13.6,w=3.8,h=6.8},{z=22,y=13.6,w=3.8,h=6.8},{z=46,y=13.6,w=3.8,h=6.8},
		{z=-80,y=27.4,w=3.8,h=6.8},{z=-28,y=27.6,w=3.8,h=6.8},{z=34,y=27.6,w=3.8,h=6.8}},
	stripeY=9.6,titleY=33.0,titleZ=-55,cockpit=false,points=nil :: any,
}
-- "bizjet" (package "guests_jet", additive): the company's small twin-engine business jet - low swept wing with
-- winglets, two engines on the rear fuselage, T-tail, glazed cockpit (the 320's canopy lattice scaled to the
-- smaller nose), six cabin windows a side, front left airstair door. Unlike the airliners its numbers are studs
-- at AircraftModel.BIZJET_SCALE (scale 1.6 = 46 x 41.6 x 15.5 studs, ~0.8 of a real light-midsize jet like the
-- shuttle's 0.885): any other scale multiplies them by scale / BIZJET_SCALE. Built by buildBizjet (cockpit,
-- rear engines, airstair, livery with the operator's name on the fin); hull, wings, tail, gear and windows use
-- the shared builders with this spec.
SPECS["bizjet"]={
	key="bizjet",length=46,span=41.6,height=15.5,noseZ=-22.6,tailZ=23.0,
	circles={{y=6.2,r=3.4}},barrel={-12,6},belly={Vector3.new(0,3.25,0.4),Vector3.new(3.15,1.25,8.2)},
	-- lower nose (radome): the canopy (full LOD) or one ellipsoid (lower LODs) closes the top
	nose={sample(-22.2,5.7,5.0,0.55,0.5),sample(-21.4,6.05,4.55,1.15,1.3),sample(-20.2,6.3,4.0,1.75,1.9),sample(-18.7,6.45,3.45,2.3,2.3),
		sample(-16.9,6.5,3.05,2.8,2.5),sample(-15.0,6.55,2.88,3.15,2.5),sample(-13.2,6.58,2.8,3.37,2.1)},
	tail={sample(6,9.6,2.8,3.4,3.5),sample(9.5,9.62,3.3,3.3,3.5),sample(13,9.55,4.3,2.95,3.5),sample(16.5,9.4,5.5,2.4,3.2),
		sample(19.5,9.15,6.6,1.7,2.6),sample(21.8,8.9,7.4,1.0,1.6),sample(22.8,8.75,7.8,0.45,0.6)},
	wing={station(2.6,-4.6,5.6,0.95),station(8.0,-1.6,5.4,0.75),station(14.5,1.4,6.0,0.5),station(20.3,4.3,7.0,0.32)},wingY=3.4,dihedral=math.rad(3.5),
	winglet={h=3.0,cant=0.5,topLe=6.4,topTe=7.6,fence=false},
	engines={{x=5.3,y=7.6,zf=9.6,len=7.2,dia=2.8,fan=2.3}}, -- rear fuselage pods (buildBizjet), not under the wing
	hstab={station(0.5,19.6,23.3,0.4),station(7.8,21.8,23.5,0.25)},hstabY={14.9,15.2},
	fin={{y=9.0,le=13.6,te=22.8,t=0.55},{y=15.0,le=19.8,te=23.4,t=0.35}},
	gear={noseZ=-16.3,noseTop=2.9,noseD=1.25,mainX={3.7},mainZ={2.6},mainTop=3.3,mainD=1.75,bogie={1}},
	decks={{y=6.9,z1=-8.8,z2=4.0,pitch=2.55,w=1.15,h=1.45,band=false}},
	doors={{z=-10.6,y=6.0,w=2.5,h=4.8}},
	stripeY=5.0,titleY=8.1,titleZ=-3.5,cockpit=false,points=nil :: any,
}

-- Smooth lofts: the nose / tail cone profiles resampled into `count` evenly spaced overlapping ellipsoids
-- (spacing/c small enough that the envelope shows no scallops); none reaches past the tip.
local function densify(list: {Sample},count: number,tipZ: number,front: boolean,overlap: number?): {Sample}
	local out: {Sample}={}
	local z1,z2=list[1].z,list[#list].z
	local step=(z2-z1)/(count-1)
	for k=0,count-1 do
		local z=z1+step*k
		local i=1
		while i<#list-1 and list[i+1].z<z do i+=1 end
		local a,b=list[i],list[i+1]
		local u=math.clamp((z-a.z)/math.max(b.z-a.z,1e-3),0,1)
		local reach=if front then z-tipZ else tipZ-z
		local c=math.max(0.4,math.min(step*(overlap or 4.2),reach+0.15))
		table.insert(out,sample(z,a.top+(b.top-a.top)*u,a.bot+(b.bot-a.bot)*u,a.hw+(b.hw-a.hw)*u,c))
	end
	return out
end
for _,spec in SPECS do
	spec.noseFine=densify(spec.nose,7,spec.noseZ,true)
	spec.tailFine=densify(spec.tail,11,spec.tailZ,false)
end
-- Distance LODs ("medium" / "low"): a few long, overlapping ellipsoids per cone (smooth silhouette, no lumps);
-- the 320's upper nose, which the full model builds as the glazed canopy, is one ellipsoid continuing the barrel
-- (LOD_NOSE_L: its length ahead of the barrel - its tip meets the lower nose, its crown passes y 19 at z -60).
local LOD_NOSE_L=16.2
local LOD_LOFTS: {[string]: {[number]: {nose: {Sample},tail: {Sample}}}}={}
for key,spec in SPECS do
	LOD_LOFTS[key]={
		[1]={nose=densify(spec.nose,4,spec.noseZ,true,1.6),tail=densify(spec.tail,5,spec.tailZ,false,1.6)},
		[0]={nose=densify(spec.nose,3,spec.noseZ,true,1.6),tail=densify(spec.tail,4,spec.tailZ,false,1.6)},
	}
end

------------------------------------------------------------------------------------------------ points
local function seatRows(xs: {number},zs: {number},y: number): {CFrame}
	local out: {CFrame}={}
	for _,z in zs do for _,x in xs do table.insert(out,CFrame.new(x,y,z)) end end
	return out
end
SPECS["320"].points={
	doorL1=CFrame.lookAt(Vector3.new(-7.05,15.4,-46.6),Vector3.new(-20,15.4,-46.6)),doorR1=CFrame.lookAt(Vector3.new(7.05,15.4,-46.6),Vector3.new(20,15.4,-46.6)),
	doorL2=CFrame.lookAt(Vector3.new(-7.05,15.6,30.8),Vector3.new(-20,15.6,30.8)),
	captain=CFrame.new(-2.05,15.9,-57.6),firstOfficer=CFrame.new(2.05,15.9,-57.6), -- heads inside the front panes (seen from ahead)
	-- jump seat 3.2 behind the pilots, at their eye height (the horizon shows through the windshield, whose top
	-- is only a little higher), 8 degrees down: heads at the left / right edges, windshield, glareshield and
	-- displays in the middle (ShuttleController: FieldOfView 56; the pilots' inner arms are hidden locally - at
	-- this distance they would fill the lower middle of the view)
	cockpitCamera=CFrame.lookAt(Vector3.new(0,17.7,-54.4),Vector3.new(0,17.7-math.tan(math.rad(8))*20,-74.4)),
	-- window seat just ahead of the wing root: 6 degrees down, 10 degrees aft (wing and engine low, horizon high)
	cabinCamera=CFrame.lookAt(Vector3.new(-4.9,15.9,-20.3),Vector3.new(-40,15.9-math.tan(math.rad(6))*35.6,-20.3+math.tan(math.rad(10))*35.1)),
	cabinSeats=seatRows({-4.9,-3.3,3.3,4.9},{-13.5,-10.9,-8.3},13.4),
	cabin={floorY=12.0,ceilingY=19.9,wallX=6.35,z1=-44,z2=29,windowY=16.35},
	length=134.18,span=127.85,height=42.14,noseZ=-67.09,tailZ=67.09,mainGearZ=-3.9,noseGearZ=-50.2,doorHalf=3.15,
}
SPECS["380"].points={
	doorL1=CFrame.lookAt(Vector3.new(-12.6,13.6,-90.5),Vector3.new(-30,13.6,-90.5)),doorR1=CFrame.lookAt(Vector3.new(12.6,13.6,-90.5),Vector3.new(30,13.6,-90.5)),
	doorL2=CFrame.lookAt(Vector3.new(-12.4,27.4,-80),Vector3.new(-30,27.4,-80)),
	captain=CFrame.new(-2.4,22.2,-114.5),firstOfficer=CFrame.new(2.4,22.2,-114.5),
	cockpitCamera=CFrame.lookAt(Vector3.new(0,24.2,-110),Vector3.new(0,22,-140)),
	cabinCamera=CFrame.lookAt(Vector3.new(-10.6,15.2,-20),Vector3.new(-60,8,-8)),
	cabinSeats=seatRows({-10.6,-8.9,8.9,10.6},{-20,-17.4,-14.8},12.6),
	cabin={floorY=10.8,ceilingY=21.0,wallX=11.9,z1=-90,z2=48,windowY=15.6},
	length=259.73,span=284.82,height=86.04,noseZ=-126.79,tailZ=132.95,mainGearZ=0,noseGearZ=-100,doorHalf=3.4,
}
-- bizjet (studs at BIZJET_SCALE): airstair door front left (sill = cabin floor 3.6), pilots' rig roots on the
-- cockpit seats (heads inside the windshield band), jump seat camera between the pilots, the founder's window
-- seat camera (seat 3, left, facing forward: looks out at the wing), six club seats (rotation = the way the
-- sitter faces: 1 / 2 face aft towards 3 / 4 across the table, 5 / 6 face forward)
do
	local AFT=CFrame.Angles(0,math.pi,0)
	SPECS["bizjet"].points={
		doorL1=CFrame.lookAt(Vector3.new(-3.42,6.0,-10.6),Vector3.new(-10,6.0,-10.6)),doorR1=CFrame.lookAt(Vector3.new(3.42,6.0,-10.6),Vector3.new(10,6.0,-10.6)),
		doorL2=CFrame.lookAt(Vector3.new(-3.42,6.4,2.6),Vector3.new(-10,6.4,2.6)),
		captain=CFrame.new(-1.15,6.2,-16.4),firstOfficer=CFrame.new(1.15,6.2,-16.4),
		cockpitCamera=CFrame.lookAt(Vector3.new(0,8.15,-13.7),Vector3.new(0,8.15-math.tan(math.rad(7))*12,-25.7)),
		cabinCamera=CFrame.lookAt(Vector3.new(-1.75,7.85,-4.9),Vector3.new(-30,7.85-math.tan(math.rad(7))*28.3,-4.9-math.tan(math.rad(14))*28.3)),
		cabinSeats={CFrame.new(-1.55,6.25,-8.6)*AFT,CFrame.new(1.55,6.25,-8.6)*AFT,CFrame.new(-1.55,6.25,-4.6),CFrame.new(1.55,6.25,-4.6),
			CFrame.new(-1.55,6.25,-0.6),CFrame.new(1.55,6.25,-0.6)},
		cabin={floorY=3.6,ceilingY=9.2,wallX=3.0,z1=-12,z2=4.5,windowY=6.9},
		length=46,span=41.6,height=15.5,noseZ=-22.6,tailZ=23.0,mainGearZ=2.6,noseGearZ=-16.3,doorHalf=2.4,
	}
end
AircraftModel.BIZJET_SCALE=1.6
-- model-space factor of a spec at `scale` (the airliners: real studs x scale x LEGACY; the bizjet: its studs
-- x scale / BIZJET_SCALE)
local function specFactor(spec: Spec,scale: number?): number
	if spec.key=="bizjet" then return (scale or AircraftModel.BIZJET_SCALE)/AircraftModel.BIZJET_SCALE end
	return (scale or 1)*LEGACY
end
local function scaled(cf: CFrame,k: number): CFrame return CFrame.new(cf.Position*k)*cf.Rotation end
-- Local CFrames (model space, studs at the requested scale) for boarding, seats and cameras.
function AircraftModel.points(kind: string?,scale: number?): Points
	local spec=SPECS[kind or "320"] or SPECS["320"]
	local k=specFactor(spec,scale)
	local p=spec.points
	local seats: {CFrame}={}
	for _,c in p.cabinSeats do table.insert(seats,scaled(c,k)) end
	local c=p.cabin
	return {doorL1=scaled(p.doorL1,k),doorR1=scaled(p.doorR1,k),doorL2=scaled(p.doorL2,k),captain=scaled(p.captain,k),firstOfficer=scaled(p.firstOfficer,k),
		cockpitCamera=scaled(p.cockpitCamera,k),cabinCamera=scaled(p.cabinCamera,k),cabinSeats=seats,
		cabin={floorY=c.floorY*k,ceilingY=c.ceilingY*k,wallX=c.wallX*k,z1=c.z1*k,z2=c.z2*k,windowY=c.windowY*k},
		length=p.length*k,span=p.span*k,height=p.height*k,noseZ=p.noseZ*k,tailZ=p.tailZ*k,mainGearZ=p.mainGearZ*k,noseGearZ=p.noseGearZ*k,doorHalf=p.doorHalf*k}
end
function AircraftModel.kinds(): {string} return {"320","380"} end

------------------------------------------------------------------------------------------------ builder state
type Ctx={m: Model,cf: CFrame,k: number,collide: boolean,count: number,spec: Spec}
local function finishPart(ctx: Ctx,p: BasePart,lcf: CFrame,color: Color3,material: Enum.Material?,solid: boolean?,shadow: boolean?)
	p.Anchored=true;p.CFrame=ctx.cf*lcf;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
	p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
	if not (solid and ctx.collide) then p.CanCollide=false;p.CanTouch=false;p.CanQuery=false end
	p.CastShadow=shadow==true
	p.Parent=ctx.m;ctx.count+=1
end
-- Box (or cylinder) in model space: size and position in real studs, scaled by ctx.k.
type PartOpts={solid: boolean?,shadow: boolean?,shape: Enum.PartType?,material: Enum.Material?,transparency: number?}
local function part(ctx: Ctx,name: string,size: Vector3,lcf: CFrame,color: Color3,opts: PartOpts?): Part
	local o: PartOpts=opts or {}
	local p=Instance.new("Part");p.Name=name
	if o.shape then p.Shape=o.shape end
	p.Size=size*ctx.k
	if o.transparency then p.Transparency=o.transparency end
	finishPart(ctx,p,CFrame.new(lcf.Position*ctx.k)*lcf.Rotation,color,o.material,o.solid,o.shadow)
	return p
end
local ALONG=CFrame.Angles(0,math.pi/2,0) -- cylinder axis (local X) along the aircraft (Z)
local function cylZ(ctx: Ctx,name: string,len: number,dia: number,pos: Vector3,color: Color3,solid: boolean?,material: Enum.Material?): Part
	return part(ctx,name,Vector3.new(len,dia,dia),CFrame.new(pos)*ALONG,color,{solid=solid,shadow=solid,shape=Enum.PartType.Cylinder,material=material})
end
local function ellipsoid(ctx: Ctx,name: string,center: Vector3,semi: Vector3,color: Color3,shadow: boolean?): Part
	local p=part(ctx,name,semi*2,CFrame.new(center),color,{shadow=shadow})
	local mesh=Instance.new("SpecialMesh");mesh.MeshType=Enum.MeshType.Sphere;mesh.Parent=p
	return p
end
-- Right triangle as one WedgePart: r = right-angle corner, a = end of the leg along local -Z, b = end of the
-- leg along local +Y; thickness along the normal (WedgePart: vertical face at +Z, slope towards -Z).
local function rightTri(ctx: Ctx,name: string,r: Vector3,a: Vector3,b: Vector3,t: number,color: Color3,solid: boolean?,material: Enum.Material?)
	local la,lb=(a-r).Magnitude,(b-r).Magnitude
	if la<0.03 or lb<0.03 then return end
	local y=(b-r)/lb;local z=-(a-r)/la
	local x=y:Cross(z)
	local w=Instance.new("WedgePart");w.Name=name
	w.Size=Vector3.new(t,lb,la)*ctx.k
	local center=(r+y*(lb/2)-z*(la/2))*ctx.k
	finishPart(ctx,w,CFrame.fromMatrix(center,x,y,z),color,material,solid,solid)
end
-- Any triangle = two right triangles split at the foot of the altitude onto the longest side.
local function tri(ctx: Ctx,name: string,a: Vector3,b: Vector3,c: Vector3,t: number,color: Color3,solid: boolean?,material: Enum.Material?)
	local p,q,v=a,b,c
	local ab,bc,ca=(b-a).Magnitude,(c-b).Magnitude,(a-c).Magnitude
	if bc>=ab and bc>=ca then p,q,v=b,c,a elseif ca>=ab and ca>=bc then p,q,v=c,a,b end
	local d=q-p;local len=d.Magnitude
	if len<0.05 then return end
	local u=d/len
	local h=p+u*math.clamp((v-p):Dot(u),0,len)
	rightTri(ctx,name,h,p,v,t,color,solid,material)
	rightTri(ctx,name,h,q,v,t,color,solid,material)
end
local function quad(ctx: Ctx,name: string,a: Vector3,b: Vector3,c: Vector3,d: Vector3,t: number,color: Color3,solid: boolean?,material: Enum.Material?)
	tri(ctx,name,a,b,c,t,color,solid,material);tri(ctx,name,a,c,d,t,color,solid,material)
end

------------------------------------------------------------------------------------------------ hull surface
-- Half-width of the hull at height y and station z (max over the barrel circles and every ellipsoid sample).
local function ellX(s: Sample,y: number,z: number,c: number): number?
	local cy=(s.top+s.bot)/2;local b=(s.top-s.bot)/2
	local q=1-((y-cy)/b)^2-((z-s.z)/c)^2
	if q<=0 then return nil end
	return s.hw*math.sqrt(q)
end
local function sampleC(list: {Sample},i: number): number
	local s=list[i]
	if s.c then return s.c end
	local n=list[i+1] or list[i-1]
	return math.abs(n.z-s.z)*1.6
end
local function surfX(spec: Spec,y: number,z: number): number?
	local best: number?=nil
	if z>=spec.barrel[1] and z<=spec.barrel[2] then
		for _,c in spec.circles do
			local dy=y-c.y
			if math.abs(dy)<c.r then local x=math.sqrt(c.r*c.r-dy*dy);if not best or x>best then best=x end end
		end
	end
	for _,list in {spec.noseFine or spec.nose,spec.tailFine or spec.tail} do
		for i,s in list do
			local x=ellX(s,y,z,sampleC(list,i))
			if x and (not best or x>best) then best=x end
		end
	end
	return best
end
-- Outward point + normal on side `side` (-1 left, +1 right) at (y, z); normal from finite differences.
local function surface(spec: Spec,side: number,y: number,z: number): (Vector3?,Vector3?)
	local x=surfX(spec,y,z);if not x then return nil,nil end
	local e=0.15
	local xu,xd=surfX(spec,y+e,z) or x,surfX(spec,y-e,z) or x
	local xf,xb=surfX(spec,y,z+e) or x,surfX(spec,y,z-e) or x
	local dxdy=(xu-xd)/(2*e);local dxdz=(xf-xb)/(2*e)
	local n=Vector3.new(side,-dxdy,-dxdz).Unit
	return Vector3.new(side*x,y,z),n
end
-- Thin plate on the hull: centre (y, z), size along the surface (up, along z), lifted `lift` off the skin.
local function skin(ctx: Ctx,name: string,side: number,y: number,z: number,up: number,len: number,color: Color3,thick: number?,lift: number?,material: Enum.Material?,transparency: number?): Part?
	local p,n=surface(ctx.spec,side,y,z)
	if not p or not n then return nil end
	local zAxis=Vector3.new(0,0,1);zAxis=(zAxis-n*n:Dot(zAxis)).Unit
	local yAxis=zAxis:Cross(n)
	local t=thick or 0.1
	local pos=(p+n*((lift or 0.02)+t/2))
	local cf=CFrame.fromMatrix(pos*ctx.k,n,yAxis,zAxis)
	local q=Instance.new("Part");q.Name=name;q.Size=Vector3.new(t,up,len)*ctx.k
	if transparency then q.Transparency=transparency end
	finishPart(ctx,q,cf,color,material,false,false)
	return q
end
-- A strip following the hull between stations z1 and z2 at height y (split into `n` flat pieces).
local function strip(ctx: Ctx,name: string,y1: number,y2: number,z1: number,z2: number,height: number,color: Color3,n: number,material: Enum.Material?)
	for side=-1,1,2 do
		for i=0,n-1 do
			local a,b=i/n,(i+1)/n
			local za,zb=z1+(z2-z1)*a,z1+(z2-z1)*b
			local ya,yb=y1+(y2-y1)*a,y1+(y2-y1)*b
			local pa=surface(ctx.spec,side,ya,za);local pb=surface(ctx.spec,side,yb,zb)
			local pm,nm=surface(ctx.spec,side,(ya+yb)/2,(za+zb)/2)
			if pa and pb and pm and nm then
				local dir=(pb-pa);local len=dir.Magnitude
				if len>0.05 then
					local zAxis=dir/len;local xAxis=(nm-zAxis*nm:Dot(zAxis)).Unit;local yAxis=zAxis:Cross(xAxis)
					local pos=(pa+pb)/2+xAxis*0.08
					local q=Instance.new("Part");q.Name=name;q.Size=Vector3.new(0.08,height,len+0.05)*ctx.k
					finishPart(ctx,q,CFrame.fromMatrix(pos*ctx.k,xAxis,yAxis,zAxis),color,material,false,false)
				end
			end
		end
	end
end
-- Text carrier: an invisible plate on the hull with a SurfaceGui on its outward (Front) face, reading
-- nose -> tail on the left side and tail -> nose on the right side like real titles.
local function title(ctx: Ctx,name: string,side: number,center: Vector3,normal: Vector3,width: number,height: number,text: string,color: Color3)
	local d=Vector3.new(0,0,if side<0 then 1 else -1)
	local up=normal:Cross(d).Unit*(if side<0 then 1 else -1)
	if up.Y<0 then up=-up end
	local xAxis=-d;local zAxis=xAxis:Cross(up)
	if zAxis:Dot(normal)>0 then zAxis=-zAxis;xAxis=-xAxis end
	local q=Instance.new("Part");q.Name=name;q.Size=Vector3.new(width,height,0.05)*ctx.k;q.Transparency=1
	finishPart(ctx,q,CFrame.fromMatrix((center+normal*0.12)*ctx.k,xAxis,up,zAxis),color,nil,false,false)
	local g=Instance.new("SurfaceGui");g.Face=Enum.NormalId.Front;g.LightInfluence=1;g.CanvasSize=Vector2.new(width*40,height*40);g.Parent=q
	local t=Instance.new("TextLabel");t.BackgroundTransparency=1;t.Size=UDim2.fromScale(1,1);t.Text=text;t.TextScaled=true
	t.Font=Enum.Font.BuilderSansBold;t.TextColor3=color;t.Parent=g
end

------------------------------------------------------------------------------------------------ components
local function buildHull(ctx: Ctx,body: Color3,detail: number)
	local spec=ctx.spec
	local b1,b2=spec.barrel[1],spec.barrel[2]
	for i,c in spec.circles do
		cylZ(ctx,if i==1 then "Fuselage" else "UpperDeck",b2-b1,c.r*2,Vector3.new(0,c.y,(b1+b2)/2),body,true)
	end
	local function loft(list: {Sample},name: string,step: number)
		for i=1,#list,step do
			local s=list[i];local c=sampleC(list,i)*(if step>1 then 1.35 else 1)
			ellipsoid(ctx,name,Vector3.new(0,(s.top+s.bot)/2,s.z),Vector3.new(s.hw,(s.top-s.bot)/2,c),body,i<=2)
		end
	end
	if detail>=2 then
		loft(spec.noseFine or spec.nose,"Nose",1)
		loft(spec.tailFine or spec.tail,"TailCone",1)
	else
		local lofts=LOD_LOFTS[spec.key][if detail>=1 then 1 else 0]
		if spec.cockpit then
			local c=spec.circles[1]
			ellipsoid(ctx,"Nose",Vector3.new(0,c.y,b1),Vector3.new(c.r*0.995,c.r*0.995,LOD_NOSE_L),body,true)
		end
		loft(lofts.nose,"Nose",1)
		loft(lofts.tail,"TailCone",1)
	end
	ellipsoid(ctx,"BellyFairing",spec.belly[1],spec.belly[2],BELLY,true)
end
-- Glazed cockpit (320 full detail): the upper nose is a canopy lattice (5 stations x 3 bands per side) over
-- the lower nose ellipsoids, closed at the front by a fan of triangles from the windshield base (apex).
-- The window band (10..62 degrees, 0 = side, 90 = crown) is glass on the first two segments (the sliding and
-- the rear side window) and in the front fan (the two front panes, which reach up to 80 degrees and meet at
-- a narrow dark centre post); the roof above and the cheeks below are opaque skin; a dark surround runs along
-- the top of the glazing. Glass panes are exact quads / triangles (wedges), so no gaps open at their edges;
-- skin plates are boxes as wide as the wider edge of their quad. A dark glareshield, an instrument panel with
-- two primary flight displays (sky / ground) and two navigation displays, seat backs and the rear bulkhead
-- give the view depth.
local CANOPY_Z={-61.6,-58.9,-56.2,-53.0,-49.4}
local CANOPY_HW={4.9,5.9,6.55,7.0,7.2} -- half-width at the canopy centre line
local CANOPY_YC={12.7,13.0,13.3,13.55,13.7} -- canopy ellipse centre height
local CANOPY_TOP={18.4,19.5,20.2,20.6,20.9} -- crown height
local CANOPY_TH={-30,10,62,76,90} -- band angles (degrees); the window band is band 2, the roof two bands
-- (the -30 ring is replaced by a line just above the widest line of the nose ellipsoids, under their surface,
-- so the cheek plates leave the lower nose almost tangentially: no shelf where the radome meets the cockpit)
local CANOPY_APEX=Vector3.new(0,14.4,-63.6) -- windshield base on the centre line
local FRONT_TOP=86 -- the front panes reach up to this angle on the first ring; above it the (narrow) centre post
local COCKPIT_GLASS_T=0.7 -- see-through enough that the seated pilots read from the apron, still reads as tinted glass
local function buildCockpit(ctx: Ctx,body: Color3)
	local frame=rgb(40,44,52)
	local function plate(name: string,a: Vector3,b: Vector3,c: Vector3,d: Vector3,color: Color3,thick: number)
		-- quad a-b-c-d (a-b bottom edge, d-c top edge) as one thin box through its centre, as wide as its wider
		-- edge and slightly oversized so neighbours close up
		local center=(a+b+c+d)/4
		local right=((b-a)+(c-d))/2;local upv=((d-a)+(c-b))/2
		local n=right:Cross(upv)
		if n.Magnitude<1e-4 then return end
		n=n.Unit
		local xAxis=right.Unit;local yAxis=n:Cross(xAxis)
		local w=math.max((b-a).Magnitude,(c-d).Magnitude)
		local p=Instance.new("Part");p.Name=name
		p.Size=Vector3.new(w+0.14,math.abs(upv:Dot(yAxis))+0.14,thick)*ctx.k
		finishPart(ctx,p,CFrame.fromMatrix(center*ctx.k,xAxis,yAxis,-n),color,nil,false,false)
	end
	local function glassTri(name: string,a: Vector3,b: Vector3,c: Vector3)
		-- exact triangle, 0.03 studs inside the skin and 2 % larger so its edges tuck under the frame
		local m=(a+b+c)/3
		local n=(b-a):Cross(c-a)
		local inward=if n.Magnitude>1e-5 then n.Unit else Vector3.zero
		if inward:Dot(m-Vector3.new(0,13.5,m.Z+6))>0 then inward=-inward end -- point into the cockpit
		local function g(v: Vector3): Vector3 return m+(v-m)*1.02+inward*0.03 end
		tri(ctx,name,g(a),g(b),g(c),0.1,GLASS,false,Enum.Material.Glass)
	end
	-- widest line of the lower nose (ellipsoids only) at each canopy station: (half-width, height)
	local cheek: {{number}}={}
	local nose=ctx.spec.noseFine or ctx.spec.nose
	for k,z in CANOPY_Z do
		local bx,by=0,CANOPY_YC[k]
		for y=6,15,0.05 do
			for i,smp in nose do
				local x=ellX(smp,y,z,sampleC(nose,i))
				if x and x>bx then bx=x;by=y end
			end
		end
		-- just above the widest line, buried 0.3 under the nose surface: the nearly vertical cheek plate leaves
		-- the nose almost tangentially (no step, no shelf)
		local y1=by+0.5
		local x1=0
		for i,smp in nose do
			local x=ellX(smp,y1,z,sampleC(nose,i))
			if x and x>x1 then x1=x end
		end
		cheek[k]={math.max(x1-0.3,0.5),y1}
	end
	local function P(k: number,deg: number,side: number): Vector3
		if deg<0 then return Vector3.new(side*cheek[k][1],cheek[k][2],CANOPY_Z[k]) end
		local th=math.rad(deg)
		local yc=CANOPY_YC[k];local b=CANOPY_TOP[k]-yc
		return Vector3.new(side*CANOPY_HW[k]*math.cos(th),yc+b*math.sin(th),CANOPY_Z[k])
	end
	local function stripAlong(name: string,a: Vector3,b: Vector3,w: number,color: Color3)
		local mid=(a+b)/2;local d=b-a
		local out=Vector3.new(mid.X,mid.Y-13.5,-2)
		out=if out.Magnitude>1e-3 then out.Unit else Vector3.new(0,1,0)
		local q=Instance.new("Part");q.Name=name
		q.Size=Vector3.new(w,0.06,d.Magnitude+0.1)*ctx.k
		local z=d.Unit;local y=out-z*out:Dot(z);y=y.Unit;local x=y:Cross(z)
		finishPart(ctx,q,CFrame.fromMatrix((mid+y*0.05)*ctx.k,x,y,z),color,nil,false,false)
	end
	for side=-1,1,2 do
		for k=1,#CANOPY_Z-1 do
			for j=1,#CANOPY_TH-1 do
				local a0,a1=CANOPY_TH[j],CANOPY_TH[j+1]
				local pa,pb,pc,pd=P(k,a0,side),P(k+1,a0,side),P(k+1,a1,side),P(k,a1,side)
				if j==2 and k<=2 then
					glassTri("CockpitSideWindow",pa,pb,pc);glassTri("CockpitSideWindow",pa,pc,pd)
				else
					plate("CockpitSkin",pa,pb,pc,pd,body,0.3)
				end
			end
		end
		-- front fan from the windshield base: cheek, front pane (two triangles), centre post
		tri(ctx,"CockpitSkin",CANOPY_APEX,P(1,CANOPY_TH[1],side),P(1,CANOPY_TH[2],side),0.3,body,false)
		glassTri("Windshield",CANOPY_APEX,P(1,CANOPY_TH[2],side),P(1,CANOPY_TH[3],side))
		glassTri("Windshield",CANOPY_APEX,P(1,CANOPY_TH[3],side),P(1,FRONT_TOP,side))
		tri(ctx,"WindshieldPost",CANOPY_APEX,P(1,FRONT_TOP,side),P(1,90,side),0.3,frame,false)
		-- window pillars: A (front pane | sliding window), B, C (behind the rear side window)
		for k=1,3 do
			local a,b=P(k,CANOPY_TH[2],side),P(k,CANOPY_TH[3],side)
			local mid=(a+b)/2;local up=(b-a)
			part(ctx,"CockpitPillar",Vector3.new(0.34,up.Magnitude+0.1,0.34),CFrame.lookAt(mid,mid+up)*CFrame.Angles(-math.pi/2,0,0),frame)
		end
		-- dark surround along the top of the glazing
		stripAlong("WindowSurround",P(1,CANOPY_TH[3],side),P(2,CANOPY_TH[3],side),0.5,frame)
		stripAlong("WindowSurround",P(2,CANOPY_TH[3],side),P(3,CANOPY_TH[3],side),0.5,frame)
		stripAlong("WindowSurround",P(1,CANOPY_TH[3],side),P(1,FRONT_TOP,side),0.45,frame)
	end
	for _,d in ctx.m:GetChildren() do
		if d:IsA("BasePart") and (d.Name=="Windshield" or d.Name=="CockpitSideWindow") then d.Transparency=COCKPIT_GLASS_T end
	end
	-- interior (dark, so every view through the glass reads as a cockpit, never as a hole)
	local wall=rgb(120,124,130) -- light enough that the pilots' dark uniforms stand out against it
	part(ctx,"CockpitBulkhead",Vector3.new(10.4,6.6,0.3),CFrame.new(0,15.0,-50.2),wall)
	part(ctx,"CockpitBulkheadTop",Vector3.new(5.6,2.0,0.3),CFrame.new(0,19.0,-50.2),wall)
	part(ctx,"Glareshield",Vector3.new(7.0,0.5,1.4),CFrame.new(0,15.0,-60.3),rgb(26,28,32))
	-- instrument panel: a dark panel with a primary flight display (sky over ground) and a navigation display
	-- (dark, magenta route) in front of each pilot
	local panelCf=CFrame.new(0,15.25,-58.95)*CFrame.Angles(math.rad(-20),0,0) -- below the glareshield edge, seen from the seats
	part(ctx,"InstrumentPanel",Vector3.new(6.4,0.9,0.08),panelCf,rgb(38,40,46))
	for _,side in {-1,1} do
		local pfd=panelCf*CFrame.new(side*2.35,0,0.05)
		local nd=panelCf*CFrame.new(side*1.05,0,0.05)
		part(ctx,"PanelScreen",Vector3.new(1.05,0.62,0.04),pfd,rgb(14,16,20))
		part(ctx,"PanelScreen",Vector3.new(1.05,0.62,0.04),nd,rgb(14,16,20))
		part(ctx,"DisplaySky",Vector3.new(0.62,0.26,0.02),pfd*CFrame.new(0,0.12,0.03),rgb(52,128,214),{material=Enum.Material.Neon})
		part(ctx,"DisplayGround",Vector3.new(0.62,0.24,0.02),pfd*CFrame.new(0,-0.13,0.03),rgb(132,86,46),{material=Enum.Material.Neon})
		part(ctx,"DisplayRoute",Vector3.new(0.06,0.44,0.02),nd*CFrame.new(0.05,0.02,0.03)*CFrame.Angles(0,0,math.rad(-14)),rgb(228,70,210),{material=Enum.Material.Neon})
	end
	part(ctx,"Pedestal",Vector3.new(1.3,1.0,2.6),CFrame.new(0,14.5,-57.4),rgb(58,60,66))
	part(ctx,"ThrustLevers",Vector3.new(0.9,0.5,0.25),CFrame.new(0,15.2,-57.6)*CFrame.Angles(math.rad(-25),0,0),rgb(28,30,34))
	for _,x in {-2.05,2.05} do
		-- sheepskin seat covers: light behind the pilots' dark caps and jackets (they read through the glass, and
		-- the jump-seat view is not a dark box)
		part(ctx,"PilotSeat",Vector3.new(1.8,0.7,1.8),CFrame.new(x,14.0,-57.5),rgb(196,184,160),{material=Enum.Material.Fabric})
		part(ctx,"PilotSeatBack",Vector3.new(1.8,3.4,0.45),CFrame.new(x,16.0,-56.35)*CFrame.Angles(math.rad(-8),0,0),rgb(196,184,160),{material=Enum.Material.Fabric})
		part(ctx,"Headrest",Vector3.new(1.3,0.8,0.5),CFrame.new(x,18.05,-56.05),rgb(206,196,174),{material=Enum.Material.Fabric})
	end
end
local function buildWindows(ctx: Ctx,body: Color3,detail: number)
	local spec=ctx.spec
	for _,deck in spec.decks do
		if detail>=2 and not deck.band then
			local z=deck.z1
			while z<=deck.z2 do
				local blocked=false
				for _,d in spec.doors do if math.abs(z-d.z)<d.w/2+0.6 and d.h>4 then blocked=true end end
				if not blocked then for side=-1,1,2 do skin(ctx,"Window",side,deck.y,z,deck.h,deck.w,WINDOW,0.1,0.01) end end
				z+=deck.pitch
			end
		else
			-- window bands, broken at the doors of this deck
			local cuts: {number}={}
			for _,d in spec.doors do if math.abs(d.y-deck.y)<6 and d.z>deck.z1 and d.z<deck.z2 then table.insert(cuts,d.z) end end
			table.sort(cuts)
			local z0=deck.z1
			local pieces: {{number}}={}
			for _,cz in cuts do table.insert(pieces,{z0,cz-2.6});z0=cz+2.6 end
			table.insert(pieces,{z0,deck.z2})
			for _,pc in pieces do
				if pc[2]-pc[1]>2 then
					local segs=if detail>=2 then math.max(1,math.ceil((pc[2]-pc[1])/24)) else 1
					strip(ctx,"WindowBand",deck.y,deck.y,pc[1],pc[2],deck.h*0.85,WINDOW,segs)
				end
			end
		end
	end
	if detail<2 then return end
	-- door outlines: two vertical edges (each two pieces following the hull) + top and bottom edges
	local line=body:Lerp(INK,0.35)
	for _,d in spec.doors do
		for side=-1,1,2 do
			for _,dz in {-d.w/2,d.w/2} do
				for _,f in {-0.25,0.25} do skin(ctx,"Outline",side,d.y+f*d.h,d.z+dz,d.h/2+0.05,0.16,line,0.05,0.03) end
			end
			for _,dy in {-d.h/2,d.h/2} do skin(ctx,"Outline",side,d.y+dy,d.z,0.16,d.w,line,0.05,0.03) end
		end
	end
end
local function buildLivery(ctx: Ctx,livery: Color3,airline: string?,detail: number)
	local spec=ctx.spec
	local y=spec.stripeY
	local b1,b2=spec.barrel[1],spec.barrel[2]
	local n=if detail>=2 then 1 else 1
	strip(ctx,"Cheatline",y,y,b1+0.5,b2,if spec.key=="380" then 1.3 else 0.62,livery,n)
	if detail>=2 then
		strip(ctx,"Pinstripe",y-0.62,y-0.62,b1+0.5,b2,0.2,GOLD,1)
		-- the cheatline sweeps up along the tail cone; it ends where the nose begins (the cockpit cheeks cover
		-- the nose's upper half, a forward sweep would vanish under them)
		local t2=spec.tail[#spec.tail-2].z
		strip(ctx,"Cheatline",y,y+(spec.tail[#spec.tail-2].bot-spec.tail[2].bot)*0.75,b2,t2,if spec.key=="380" then 1.1 else 0.5,livery,3)
	end
	if airline and detail>=2 then
		for side=-1,1,2 do
			local p,nrm=surface(spec,side,spec.titleY,spec.titleZ)
			if p and nrm then title(ctx,"Titles",side,p,nrm,if spec.key=="380" then 52 else 26,if spec.key=="380" then 4.4 else 2.1,string.upper(airline),livery) end
		end
	end
end
local function wingY(spec: Spec,x: number): number return spec.wingY+(x-spec.wing[1].x)*math.tan(spec.dihedral) end
local function buildWings(ctx: Ctx,livery: Color3,detail: number)
	local spec=ctx.spec
	local st=spec.wing
	for side=-1,1,2 do
		local function P(s: Station,edge: number): Vector3 return Vector3.new(side*s.x,wingY(spec,s.x),edge) end
		if detail>=1 then
			local step=if detail>=2 then 1 else (#st-1)
			local i=1
			while i<#st do
				local a,b=st[i],st[math.min(i+step,#st)]
				quad(ctx,"Wing",P(a,a.le),P(a,a.te),P(b,b.te),P(b,b.le),(a.t+b.t)/2,WING,true)
				i+=step
			end
		else
			-- low detail: one rotated slab per wing
			local a,b=st[1],st[#st]
			local p1=Vector3.new(side*a.x,wingY(spec,a.x),(a.le+a.te)/2);local p2=Vector3.new(side*b.x,wingY(spec,b.x),(b.le+b.te)/2)
			local mid=(p1+p2)/2;local chord=((a.te-a.le)+(b.te-b.le))/2
			part(ctx,"Wing",Vector3.new((p2-p1).Magnitude,(a.t+b.t)/2,chord),CFrame.lookAt(mid,mid+(p2-p1).Unit:Cross(Vector3.new(0,1,0)))*CFrame.Angles(0,0,0),WING,{solid=true,shadow=true})
		end
		-- blended winglets (320) or wingtip fences (380)
		local tip=st[#st]
		local wl=spec.winglet
		local base=Vector3.new(side*tip.x,wingY(spec,tip.x),0)
		if detail>=1 then
			local top=base.Y+wl.h
			quad(ctx,"Winglet",Vector3.new(base.X,base.Y,tip.le),Vector3.new(base.X,base.Y,tip.te),Vector3.new(base.X+side*wl.cant,top,wl.topTe),Vector3.new(base.X+side*wl.cant,top,wl.topLe),0.5,livery)
			if wl.fence then
				quad(ctx,"Winglet",Vector3.new(base.X,base.Y,tip.le),Vector3.new(base.X,base.Y,tip.te),Vector3.new(base.X,base.Y-wl.h*0.55,tip.te-2),Vector3.new(base.X,base.Y-wl.h*0.55,tip.le+3.5),0.5,livery)
			end
		end
		if detail>=2 then
			-- flap track fairings under the trailing edge
			for f=1,3 do
				local x=st[1].x+(tip.x-st[1].x)*(0.2+f*0.18)
				local i=1;while i<#st-1 and st[i+1].x<x do i+=1 end
				local a,b=st[i],st[i+1];local u=(x-a.x)/(b.x-a.x)
				local te=a.te+(b.te-a.te)*u;local le=a.le+(b.le-a.le)*u;local chord=te-le
				ellipsoid(ctx,"FlapFairing",Vector3.new(side*x,wingY(spec,x)-chord*0.06,te-chord*0.2),Vector3.new(chord*0.035+0.25,chord*0.06+0.3,chord*0.32),WING:Lerp(INK,0.08))
			end
			-- navigation lights: red left, green right; strobe white at the tail
			part(ctx,"NavLight",Vector3.new(0.5,0.5,0.5),CFrame.new(base.X+side*0.2,base.Y+0.2,tip.le+0.6),if side<0 then rgb(255,60,50) else rgb(60,255,120),{material=Enum.Material.Neon,shape=Enum.PartType.Ball})
		end
	end
end
local function buildEngines(ctx: Ctx,livery: Color3,detail: number)
	local spec=ctx.spec
	for _,e in spec.engines do
		for side=-1,1,2 do
			local x=side*e.x
			local zf=e.zf
			local bodyLen=e.len*0.6
			if detail>=1 then
				cylZ(ctx,"EngineLip",e.len*0.04,e.dia*0.985,Vector3.new(x,e.y,zf+e.len*0.02),LIP,true,Enum.Material.Metal)
				cylZ(ctx,"Nacelle",bodyLen,e.dia,Vector3.new(x,e.y,zf+e.len*0.04+bodyLen/2),livery,true)
				cylZ(ctx,"NacelleAft",e.len*0.2,e.dia*0.86,Vector3.new(x,e.y,zf+e.len*0.74),livery,true)
				local fan=cylZ(ctx,"Fan",0.12,e.fan,Vector3.new(x,e.y,zf-0.02),rgb(44,46,50),false,Enum.Material.Metal);fan:SetAttribute("Spin",true)
				cylZ(ctx,"EngineCore",e.len*0.13,e.dia*0.56,Vector3.new(x,e.y-e.dia*0.03,zf+e.len*0.905),METAL,true,Enum.Material.Metal)
				ellipsoid(ctx,"ExhaustPlug",Vector3.new(x,e.y-e.dia*0.03,zf+e.len*0.98),Vector3.new(e.dia*0.17,e.dia*0.17,e.len*0.09),rgb(70,72,76))
				-- pylon from the nacelle top to the wing
				local wy=wingY(spec,e.x)
				local top=e.y+e.dia/2
				local h=math.max(0.6,wy-top+0.4)
				part(ctx,"Pylon",Vector3.new(e.dia*0.13,h+0.8,e.len*0.62),CFrame.new(x,top+h/2-0.3,zf+e.len*0.55),rgb(226,228,232),{shadow=true})
			else
				cylZ(ctx,"Nacelle",e.len,e.dia,Vector3.new(x,e.y,zf+e.len/2),livery,true)
			end
			if detail>=2 then
				local spinner=ellipsoid(ctx,"Spinner",Vector3.new(x,e.y,zf-0.1),Vector3.new(e.fan*0.12,e.fan*0.12,e.fan*0.16),rgb(30,30,34));spinner:SetAttribute("Spin",true)
				for i=0,9 do
					local a=i*math.pi*2/10
					local r=e.fan*0.29
					local blade=part(ctx,"FanBlade",Vector3.new(e.fan*0.36,0.32,0.1),CFrame.new(x+math.cos(a)*r,e.y+math.sin(a)*r,zf-0.1)*CFrame.Angles(0,0,a)*CFrame.Angles(0.5,0,0),rgb(150,154,160),{material=Enum.Material.Metal})
					blade:SetAttribute("Spin",true)
				end
			end
		end
	end
end
local function buildTail(ctx: Ctx,livery: Color3,body: Color3,airline: string?,detail: number)
	local spec=ctx.spec
	local hs=spec.hstab
	for side=-1,1,2 do
		local a,b=hs[1],hs[#hs]
		local ya,yb=spec.hstabY[1],spec.hstabY[2]
		if detail>=1 then
			quad(ctx,"Stabilizer",Vector3.new(side*a.x,ya,a.le),Vector3.new(side*a.x,ya,a.te),Vector3.new(side*b.x,yb,b.te),Vector3.new(side*b.x,yb,b.le),(a.t+b.t)/2,body)
		else
			local p1=Vector3.new(side*a.x,ya,(a.le+a.te)/2);local p2=Vector3.new(side*b.x,yb,(b.le+b.te)/2)
			local mid=(p1+p2)/2
			part(ctx,"Stabilizer",Vector3.new((p2-p1).Magnitude,0.6,((a.te-a.le)+(b.te-b.le))/2),CFrame.lookAt(mid,mid+(p2-p1).Unit:Cross(Vector3.new(0,1,0))),body)
		end
	end
	local f1,f2=spec.fin[1],spec.fin[2]
	if detail>=1 then
		quad(ctx,"Fin",Vector3.new(0,f1.y,f1.le),Vector3.new(0,f1.y,f1.te),Vector3.new(0,f2.y,f2.te),Vector3.new(0,f2.y,f2.le),(f1.t+f2.t)/2,livery,true)
	else
		tri(ctx,"Fin",Vector3.new(0,f1.y,f1.le),Vector3.new(0,f1.y,f1.te),Vector3.new(0,f2.y,(f2.le+f2.te)/2),(f1.t+f2.t)/2,livery,true)
	end
	if detail>=2 then
		-- dorsal fillet in front of the fin, anti-collision beacon, tail logo letters
		local fy=f1.y+(f2.y-f1.y)*0.14
		local fz=f1.le+(f2.le-f1.le)*0.14
		tri(ctx,"DorsalFin",Vector3.new(0,f1.y,f1.le-(f1.te-f1.le)*0.3),Vector3.new(0,f1.y,f1.le+1),Vector3.new(0,fy,fz),f1.t*0.7,livery)
		part(ctx,"Beacon",Vector3.new(0.6,0.35,0.9),CFrame.new(0,spec.circles[#spec.circles].y+spec.circles[#spec.circles].r+0.1,(spec.barrel[1]+spec.barrel[2])/2),rgb(255,60,50),{material=Enum.Material.Neon})
		part(ctx,"TailLight",Vector3.new(0.4,0.4,0.4),CFrame.new(0,spec.tail[#spec.tail].top-0.8,spec.tailZ-0.2),rgb(255,255,250),{material=Enum.Material.Neon,shape=Enum.PartType.Ball})
		if airline then
			local letters=string.upper(string.sub(airline,1,1))
			local first=string.match(airline,"^(%S+)")
			if first and #first<=3 then letters=string.upper(first) end
			local h=(f2.y-f1.y)
			local cy=f1.y+h*0.55;local cz=f1.le+(f2.le-f1.le)*0.55+((f1.te-f1.le)+(f2.te-f2.le))*0.25
			for side=-1,1,2 do
				title(ctx,"TailLogo",side,Vector3.new(side*((f1.t+f2.t)/4+0.02),cy,cz),Vector3.new(side,0,0),h*0.42,h*0.3,letters,Color3.new(1,1,1))
			end
		end
	end
end
local function buildGear(ctx: Ctx,detail: number)
	local spec=ctx.spec
	local g=spec.gear
	local tyre=rgb(26,26,28)
	local strut=rgb(212,214,218)
	local function mark(p: BasePart) p:SetAttribute("Gear",true) end
	-- nose gear
	local nr=g.noseD/2
	if detail>=1 then mark(part(ctx,"NoseGear",Vector3.new(g.noseD*0.18,g.noseTop-nr,g.noseD*0.18),CFrame.new(0,(g.noseTop+nr)/2,g.noseZ),strut,{shape=Enum.PartType.Block,shadow=true})) end
	local noseXs: {number}=if detail>=1 then {-g.noseD*0.26,g.noseD*0.26} else {0}
	for _,x in noseXs do
		mark(part(ctx,"NoseWheel",Vector3.new(g.noseD*0.34,g.noseD,g.noseD),CFrame.new(x,nr,g.noseZ),tyre,{shape=Enum.PartType.Cylinder,solid=true,shadow=true}))
	end
	-- main gear legs (320: 2 x twin wheels; 380: 2 wing bogies x 4 + 2 body bogies x 6)
	local mr=g.mainD/2
	for i,mx in g.mainX do
		local axles=g.bogie[i]
		for side=-1,1,2 do
			local x=side*mx
			local z=g.mainZ[i]
			if detail>=1 then
				mark(part(ctx,"MainGear",Vector3.new(g.mainD*0.16,g.mainTop-mr,g.mainD*0.16),CFrame.new(x,(g.mainTop+mr)/2,z),strut,{shadow=true}))
				if axles>1 then mark(part(ctx,"Bogie",Vector3.new(g.mainD*0.14,g.mainD*0.14,axles*g.mainD*1.05),CFrame.new(x,mr,z),strut)) end
			end
			for a=1,axles do
				local az=z+(a-(axles+1)/2)*g.mainD*1.05
				local pair: {number}=if detail>=1 then {-g.mainD*0.3,g.mainD*0.3} else {0}
				for _,dx in pair do
					mark(part(ctx,"MainWheel",Vector3.new(g.mainD*(if detail>=1 then 0.3 else 0.5),g.mainD,g.mainD),CFrame.new(x+dx,mr,az),tyre,{shape=Enum.PartType.Cylinder,solid=true,shadow=true}))
				end
			end
		end
	end
end
local function cockpitWindowsPainted(ctx: Ctx,detail: number)
	-- closed (painted) cockpit windows on the nose for the 380 and the lower LODs
	local spec=ctx.spec
	local n=spec.nose
	local s=n[math.max(1,#n-3)]
	local y=s.top-(s.top-s.bot)*(if spec.key=="380" then 0.33 else 0.2)
	if spec.key=="380" and detail>=1 then
		-- a continuous band of four panes per side (narrow pillars between them) wrapping round the nose
		-- between the decks, plus the sloping front panes: reads as a cockpit, not as two small "eyes"
		local zs={-120.4,-116.9,-113.2,-109.4}
		local lens={2.6,3.4,3.5,3.5}
		for side=-1,1,2 do
			for i,z in zs do skin(ctx,"CockpitWindow",side,24.9+(i-1)*0.12,z,2.9,lens[i],WINDOW,0.1,0.02) end
			-- front pane: on the forward-facing surface at the band's height, beside the centre post
			local wy=24.6
			local z=spec.noseZ
			while z<-115 and (surfX(spec,wy,z) or 0)<1.9 do z+=0.05 end
			local p,nrm=surface(spec,side,wy,z)
			if p and nrm then part(ctx,"CockpitWindow",Vector3.new(3.0,2.5,0.1),CFrame.lookAt(p+nrm*0.06,p+nrm*1.06),WINDOW) end
		end
		return
	end
	if spec.cockpit then
		-- 320 distance LODs: the windshield band painted on the upper-nose ellipsoid (buildHull, LOD_NOSE_L):
		-- two side panes per side and the two front panes beside the centre post
		local c=spec.circles[1]
		local a,b1,wy=c.r*0.995,spec.barrel[1],16.6
		local function surf(side: number,z: number): (Vector3?,Vector3?)
			local q=1-((wy-c.y)/a)^2-((z-b1)/LOD_NOSE_L)^2
			if q<=0 then return nil,nil end
			local x=a*math.sqrt(q)
			return Vector3.new(side*x,wy,z),Vector3.new(side*x/(a*a),(wy-c.y)/(a*a),(z-b1)/(LOD_NOSE_L*LOD_NOSE_L)).Unit
		end
		for side=-1,1,2 do
			local panes: {{number}}=if detail>=1 then {{-55.4,2.4},{-58.3,2.6}} else {{-57.0,4.6}} -- low: one long pane
			if detail>=1 then
				-- front pane: where the band's half-width is 1.25 (beside the centre post)
				local z=b1-LOD_NOSE_L
				while z<b1 do local p0=surf(side,z);if p0 and math.abs(p0.X)>=1.25 then break end;z+=0.05 end
				table.insert(panes,{z,0})
			end
			for _,pz in panes do
				local p0,nrm=surf(side,pz[1])
				if p0 and nrm then
					local w=if pz[2]>0 then pz[2] else 2.2
					part(ctx,"CockpitWindow",Vector3.new(w,1.5,0.1),CFrame.lookAt(p0+nrm*0.06,p0+nrm*1.06),WINDOW)
				end
			end
		end
		return
	end
	if detail>=1 then
		for side=-1,1,2 do
			skin(ctx,"CockpitWindow",side,y,n[#n-3].z-0.6,(s.top-s.bot)*0.13,(n[#n-2].z-n[#n-4].z)*0.55,WINDOW,0.1,0.02)
			skin(ctx,"CockpitWindow",side,y,n[#n-2].z,(s.top-s.bot)*0.13,(n[#n-1].z-n[#n-3].z)*0.45,WINDOW,0.1,0.02)
		end
	end
	local f=n[3]
	local fy=f.top-(f.top-f.bot)*0.12
	local fz=f.z+0.25*(n[4].z-f.z)
	part(ctx,"CockpitWindow",Vector3.new(f.hw*1.3,(f.top-f.bot)*0.12,0.3),CFrame.new(0,fy,fz)*CFrame.Angles(math.rad(42),0,0),WINDOW)
end

------------------------------------------------------------------------------------------------ attachments
local function addPoints(m: Model,cf: CFrame,kind: string,scale: number,size: number): BasePart
	local root=Instance.new("Part");root.Name="AircraftRoot";root.Size=Vector3.new(1,1,1)*math.max(0.2,size);root.Transparency=1
	root.Anchored=true;root.CanCollide=false;root.CanTouch=false;root.CanQuery=false;root.CastShadow=false;root.CFrame=cf;root.Parent=m
	local pts=AircraftModel.points(kind,scale)
	local function att(name: string,c: CFrame) local a=Instance.new("Attachment");a.Name=name;a.CFrame=c;a.Parent=root end
	att("DoorL1",pts.doorL1);att("DoorR1",pts.doorR1);att("DoorL2",pts.doorL2)
	local l1=root:FindFirstChild("DoorL1");if l1 then l1:SetAttribute("BoardingDoor",true);l1:SetAttribute("DoorHalf",pts.doorHalf) end
	att("CaptainSeat",pts.captain);att("FirstOfficerSeat",pts.firstOfficer)
	att("CockpitCamera",pts.cockpitCamera);att("CabinCamera",pts.cabinCamera)
	for i,c in pts.cabinSeats do if i<=6 then att("CabinSeat"..i,c) end end
	m.PrimaryPart=root
	return root
end

------------------------------------------------------------------------------------------------ meshes
-- The owner's imported FBX (Studio 3D Importer), if present: ReplicatedStorage.Assets.Aircraft.<Name> or
-- ReplicatedStorage.VehicleAssets.<Name>.
function AircraftModel.meshTemplate(kind: string?): Model?
	local name=MESH_NAMES[kind or "320"]
	if not name then return nil end
	local assets=ReplicatedStorage:FindFirstChild("Assets")
	local folder=if assets then assets:FindFirstChild("Aircraft") else nil
	local t=if folder then folder:FindFirstChild(name) else nil
	if not t then
		local va=ReplicatedStorage:FindFirstChild("VehicleAssets")
		t=if va then va:FindFirstChild(name) else nil
	end
	return if t and t:IsA("Model") then t else nil
end
local function fromMesh(template: Model,cf: CFrame,k: number,o: Options): Model
	local m=template:Clone()
	m.Name=o.name or template.Name
	for _,d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored=true
			local solid=o.collide==true and d.Name=="Fuselage"
			d.CanCollide=solid;d.CanTouch=false;d.CanQuery=solid
			if string.find(d.Name,"Fan") then d:SetAttribute("Spin",true) end
			if string.find(d.Name,"Gear") or string.find(d.Name,"Wheel") then d:SetAttribute("Gear",true) end
		end
	end
	m:PivotTo(CFrame.new())
	if math.abs(k-1)>1e-3 then m:ScaleTo(k) end
	m:PivotTo(cf)
	m.WorldPivot=cf
	return m
end

------------------------------------------------------------------------------------------------ bizjet
-- Glazed cockpit of the bizjet: the 320's canopy lattice (buildCockpit) with its stations scaled to the small
-- nose (narrower window band 14..52 degrees, a sleeker windshield) - glass on the first two segments
-- and in the front fan from the windshield base, roof and cheeks opaque, a dark surround - plus a compact
-- interior (panel with displays, glareshield, pedestal, two seats, bulkhead) so the pilots read through the glass.
local BIZ_CANOPY={z={-19.6,-17.9,-16.2,-14.2,-12.0},hw={1.95,2.6,3.0,3.28,3.4},yc={5.85,5.95,6.05,6.14,6.2},
	top={8.1,8.8,9.2,9.45,9.6},th={-30,14,52,70,90},apex=Vector3.new(0,6.3,-21.0),frontTop=86,centreY=6.4}
local function bizCockpit(ctx: Ctx,body: Color3)
	local C=BIZ_CANOPY
	local frame=rgb(40,44,52)
	local function plate(name: string,a: Vector3,b: Vector3,c: Vector3,d: Vector3,color: Color3,thick: number)
		local center=(a+b+c+d)/4
		local right=((b-a)+(c-d))/2;local upv=((d-a)+(c-b))/2
		local n=right:Cross(upv)
		if n.Magnitude<1e-4 then return end
		n=n.Unit
		local xAxis=right.Unit;local yAxis=n:Cross(xAxis)
		local w=math.max((b-a).Magnitude,(c-d).Magnitude)
		local p=Instance.new("Part");p.Name=name
		p.Size=Vector3.new(w+0.07,math.abs(upv:Dot(yAxis))+0.07,thick)*ctx.k
		finishPart(ctx,p,CFrame.fromMatrix(center*ctx.k,xAxis,yAxis,-n),color,nil,false,false)
	end
	local function glassTri(name: string,a: Vector3,b: Vector3,c: Vector3)
		local m=(a+b+c)/3
		local n=(b-a):Cross(c-a)
		local inward=if n.Magnitude>1e-5 then n.Unit else Vector3.zero
		if inward:Dot(m-Vector3.new(0,C.centreY,m.Z+3))>0 then inward=-inward end
		local function g(v: Vector3): Vector3 return m+(v-m)*1.02+inward*0.02 end
		tri(ctx,name,g(a),g(b),g(c),0.06,GLASS,false,Enum.Material.Glass)
	end
	local cheek: {{number}}={}
	local nose=ctx.spec.noseFine or ctx.spec.nose
	for k,z in C.z do
		local bx,by=0,C.yc[k]
		for y=2.5,7.5,0.05 do
			for i,smp in nose do
				local x=ellX(smp,y,z,sampleC(nose,i))
				if x and x>bx then bx=x;by=y end
			end
		end
		local y1=by+0.25
		local x1=0
		for i,smp in nose do
			local x=ellX(smp,y1,z,sampleC(nose,i))
			if x and x>x1 then x1=x end
		end
		cheek[k]={math.max(x1-0.15,0.25),y1}
	end
	local function P(k: number,deg: number,side: number): Vector3
		if deg<0 then return Vector3.new(side*cheek[k][1],cheek[k][2],C.z[k]) end
		local th=math.rad(deg)
		local yc=C.yc[k];local b=C.top[k]-yc
		return Vector3.new(side*C.hw[k]*math.cos(th),yc+b*math.sin(th),C.z[k])
	end
	local function stripAlong(name: string,a: Vector3,b: Vector3,w: number,color: Color3)
		local mid=(a+b)/2;local d=b-a
		local out=Vector3.new(mid.X,mid.Y-C.centreY,-1)
		out=if out.Magnitude>1e-3 then out.Unit else Vector3.new(0,1,0)
		local q=Instance.new("Part");q.Name=name
		q.Size=Vector3.new(w,0.04,d.Magnitude+0.05)*ctx.k
		local zz=d.Unit;local y=out-zz*out:Dot(zz);y=y.Unit;local x=y:Cross(zz)
		finishPart(ctx,q,CFrame.fromMatrix((mid+y*0.03)*ctx.k,x,y,zz),color,nil,false,false)
	end
	local TH=C.th
	for side=-1,1,2 do
		for k=1,#C.z-1 do
			for j=1,#TH-1 do
				local a0,a1=TH[j],TH[j+1]
				local pa,pb,pc,pd=P(k,a0,side),P(k+1,a0,side),P(k+1,a1,side),P(k,a1,side)
				if j==2 and k<=2 then
					glassTri("CockpitSideWindow",pa,pb,pc);glassTri("CockpitSideWindow",pa,pc,pd)
				else
					plate("CockpitSkin",pa,pb,pc,pd,body,0.15)
				end
			end
		end
		tri(ctx,"CockpitSkin",C.apex,P(1,TH[1],side),P(1,TH[2],side),0.15,body,false)
		glassTri("Windshield",C.apex,P(1,TH[2],side),P(1,TH[3],side))
		glassTri("Windshield",C.apex,P(1,TH[3],side),P(1,C.frontTop,side))
		tri(ctx,"WindshieldPost",C.apex,P(1,C.frontTop,side),P(1,90,side),0.15,frame,false)
		for k=1,3 do
			local a,b=P(k,TH[2],side),P(k,TH[3],side)
			local mid=(a+b)/2;local up=(b-a)
			part(ctx,"CockpitPillar",Vector3.new(0.18,up.Magnitude+0.05,0.18),CFrame.lookAt(mid,mid+up)*CFrame.Angles(-math.pi/2,0,0),frame)
		end
		stripAlong("WindowSurround",P(1,TH[3],side),P(2,TH[3],side),0.26,frame)
		stripAlong("WindowSurround",P(2,TH[3],side),P(3,TH[3],side),0.26,frame)
		stripAlong("WindowSurround",P(1,TH[3],side),P(1,C.frontTop,side),0.24,frame)
	end
	for _,d in ctx.m:GetChildren() do
		if d:IsA("BasePart") and (d.Name=="Windshield" or d.Name=="CockpitSideWindow") then d.Transparency=COCKPIT_GLASS_T end
	end
	-- interior
	local wall=rgb(120,124,130)
	part(ctx,"CockpitFloor",Vector3.new(4.2,0.15,6.4),CFrame.new(0,3.35,-15.6),rgb(46,48,54))
	part(ctx,"CockpitBulkhead",Vector3.new(4.0,5.0,0.2),CFrame.new(0,6.0,-12.35),wall) -- inside the hull (r 3.4 about y 6.2)
	part(ctx,"Glareshield",Vector3.new(3.3,0.28,0.85),CFrame.new(0,6.62,-18.95),rgb(26,28,32))
	local panelCf=CFrame.new(0,6.28,-18.55)*CFrame.Angles(math.rad(-20),0,0)
	part(ctx,"InstrumentPanel",Vector3.new(3.1,0.6,0.05),panelCf,rgb(38,40,46))
	for _,side in {-1,1} do
		local pfd=panelCf*CFrame.new(side*1.1,0,0.03)
		local nd=panelCf*CFrame.new(side*0.45,0,0.03)
		part(ctx,"PanelScreen",Vector3.new(0.5,0.4,0.03),pfd,rgb(14,16,20))
		part(ctx,"PanelScreen",Vector3.new(0.5,0.4,0.03),nd,rgb(14,16,20))
		part(ctx,"DisplaySky",Vector3.new(0.34,0.16,0.02),pfd*CFrame.new(0,0.08,0.02),rgb(52,128,214),{material=Enum.Material.Neon})
		part(ctx,"DisplayGround",Vector3.new(0.34,0.14,0.02),pfd*CFrame.new(0,-0.08,0.02),rgb(132,86,46),{material=Enum.Material.Neon})
		part(ctx,"DisplayRoute",Vector3.new(0.04,0.28,0.02),nd*CFrame.new(0.03,0.01,0.02)*CFrame.Angles(0,0,math.rad(-14)),rgb(228,70,210),{material=Enum.Material.Neon})
	end
	part(ctx,"Pedestal",Vector3.new(0.7,0.65,1.4),CFrame.new(0,4.05,-17.4),rgb(58,60,66))
	part(ctx,"ThrustLevers",Vector3.new(0.5,0.3,0.15),CFrame.new(0,4.5,-17.6)*CFrame.Angles(math.rad(-25),0,0),rgb(28,30,34))
	for _,x in {-1.15,1.15} do
		part(ctx,"PilotSeat",Vector3.new(1.2,0.35,1.2),CFrame.new(x,4.7,-16.35),rgb(196,184,160),{material=Enum.Material.Fabric})
		part(ctx,"PilotSeatBack",Vector3.new(1.2,2.2,0.3),CFrame.new(x,5.95,-15.65)*CFrame.Angles(math.rad(-8),0,0),rgb(196,184,160),{material=Enum.Material.Fabric})
		part(ctx,"Headrest",Vector3.new(0.9,0.55,0.32),CFrame.new(x,7.3,-15.45),rgb(206,196,174),{material=Enum.Material.Fabric})
	end
end
-- Rear engine pods on short horizontal pylons from the tail cone.
local function bizEngines(ctx: Ctx,body: Color3,livery: Color3,detail: number)
	for _,e in ctx.spec.engines do
		for side=-1,1,2 do
			local x=side*e.x
			local zf=e.zf
			if detail>=1 then
				cylZ(ctx,"EngineLip",0.3,e.dia*0.98,Vector3.new(x,e.y,zf+0.15),LIP,true,Enum.Material.Metal)
				cylZ(ctx,"Nacelle",4.6,e.dia,Vector3.new(x,e.y,zf+0.3+2.3),body,true)
				cylZ(ctx,"NacelleAft",1.6,e.dia*0.86,Vector3.new(x,e.y,zf+5.7),body,true)
				cylZ(ctx,"NacelleBand",0.5,e.dia*1.01,Vector3.new(x,e.y,zf+1.4),livery,false)
				local fan=cylZ(ctx,"Fan",0.1,e.fan,Vector3.new(x,e.y,zf-0.02),rgb(44,46,50),false,Enum.Material.Metal);fan:SetAttribute("Spin",true)
				cylZ(ctx,"EngineCore",0.9,e.dia*0.54,Vector3.new(x,e.y,zf+6.9),METAL,true,Enum.Material.Metal)
				ellipsoid(ctx,"ExhaustPlug",Vector3.new(x,e.y,zf+7.35),Vector3.new(e.dia*0.17,e.dia*0.17,0.6),rgb(70,72,76))
				part(ctx,"Pylon",Vector3.new(1.6,0.45,4.0),CFrame.new(side*3.4,e.y,zf+3.2),rgb(226,228,232),{shadow=true})
			else
				cylZ(ctx,"Nacelle",e.len,e.dia,Vector3.new(x,e.y,zf+e.len/2),body,true)
			end
			if detail>=2 then
				local spinner=ellipsoid(ctx,"Spinner",Vector3.new(x,e.y,zf-0.08),Vector3.new(e.fan*0.13,e.fan*0.13,e.fan*0.17),rgb(30,30,34));spinner:SetAttribute("Spin",true)
				for i=0,7 do
					local a=i*math.pi*2/8
					local r=e.fan*0.29
					local blade=part(ctx,"FanBlade",Vector3.new(e.fan*0.36,0.16,0.06),CFrame.new(x+math.cos(a)*r,e.y+math.sin(a)*r,zf-0.06)*CFrame.Angles(0,0,a)*CFrame.Angles(0.5,0,0),rgb(150,154,160),{material=Enum.Material.Metal})
					blade:SetAttribute("Spin",true)
				end
			end
		end
	end
end
-- Integrated airstair at door L1 (the door hinges at the sill and folds down): flight, steps and handrails
-- carry the attribute Airstair = true, the closed door skin DoorPanel = true; AircraftModel.setAirstair shows
-- one or the other.
local function bizAirstair(ctx: Ctx,body: Color3,deployed: boolean)
	local d=ctx.spec.doors[1]
	local z=d.z
	local sill=Vector3.new(-2.25,3.6,z)
	local foot=Vector3.new(-5.0,0.12,z)
	local mid=(sill+foot)/2
	local len=(sill-foot).Magnitude
	local frame=CFrame.lookAt(mid,foot)
	local parts: {BasePart}={}
	local function add(p: BasePart) p:SetAttribute("Airstair",true);table.insert(parts,p) end
	add(part(ctx,"AirstairFlight",Vector3.new(2.1,0.2,len),frame,body:Lerp(INK,0.08)))
	for i=1,3 do
		local p=sill:Lerp(foot,i/4)
		add(part(ctx,"AirstairStep",Vector3.new(2.0,0.12,0.55),CFrame.new(p+Vector3.new(0,0.1,0)),rgb(150,154,158),{material=Enum.Material.DiamondPlate}))
	end
	for _,s in {-1,1} do
		add(part(ctx,"AirstairRail",Vector3.new(0.1,0.1,len),CFrame.new(0,2.3,0)*frame*CFrame.new(s*1.0,0,0),rgb(168,172,178),{material=Enum.Material.Metal}))
		for k=0,1 do
			local p=sill:Lerp(foot,0.15+k*0.7)+Vector3.new(0,0,s*1.0)
			add(part(ctx,"AirstairPost",Vector3.new(0.08,2.3,0.08),CFrame.new(p+Vector3.new(0,1.15,0)),rgb(168,172,178),{material=Enum.Material.Metal}))
		end
	end
	local panel=skin(ctx,"DoorPanel",-1,d.y,z,d.h-0.2,d.w-0.15,body:Lerp(INK,0.12),0.06,0.04)
	if panel then panel:SetAttribute("DoorPanel",true) end
	for _,p in parts do p.Transparency=if deployed then 0 else 1 end
	if panel then panel.Transparency=if deployed then 1 else 0 end
end
-- Show (true) or stow (false) the bizjet's airstair: the airstair parts and the closed door panel swap. Pure
-- instance writes on a client-built model (Transparency, not LocalTransparencyModifier, so AircraftMover's
-- setVisible can still hide the whole model).
function AircraftModel.setAirstair(m: Model,deployed: boolean)
	if m:GetAttribute("AirstairDeployed")==deployed then return end
	m:SetAttribute("AirstairDeployed",deployed)
	for _,d in m:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("Airstair")==true then d.Transparency=if deployed then 0 else 1
			elseif d:GetAttribute("DoorPanel")==true then d.Transparency=if deployed then 1 else 0 end
		end
	end
end
-- Cabin (full LOD): carpet, six cream club seats from the points (backs behind the sitter), a table between the
-- facing pairs, a walnut rear bulkhead.
local function bizCabin(ctx: Ctx)
	local pts=ctx.spec.points
	part(ctx,"CabinFloor",Vector3.new(4.4,0.12,16.4),CFrame.new(0,3.54,-3.8),rgb(70,62,58),{material=Enum.Material.Fabric})
	local leather=rgb(222,210,186)
	for _,c in pts.cabinSeats do
		part(ctx,"CabinSeat",Vector3.new(1.35,0.4,1.3),c*CFrame.new(0,-1.5,0),leather,{material=Enum.Material.Leather})
		part(ctx,"CabinSeatBack",Vector3.new(1.35,2.3,0.35),c*CFrame.new(0,-0.25,0.72)*CFrame.Angles(math.rad(-6),0,0),leather,{material=Enum.Material.Leather})
	end
	part(ctx,"CabinTable",Vector3.new(1.3,0.1,1.5),CFrame.new(-1.55,5.35,-6.6),rgb(96,62,40),{material=Enum.Material.Wood})
	part(ctx,"CabinTable",Vector3.new(1.3,0.1,1.5),CFrame.new(1.55,5.35,-6.6),rgb(96,62,40),{material=Enum.Material.Wood})
	part(ctx,"CabinBulkhead",Vector3.new(4.2,4.6,0.2),CFrame.new(0,6.3,4.7),rgb(96,62,40),{material=Enum.Material.Wood})
end
-- Livery: cheatline + gold pinstripe sweeping up the tail cone, a small title over the windows, the operator's
-- name in white on both sides of the (livery-coloured) fin.
local function bizLivery(ctx: Ctx,livery: Color3,airline: string?,detail: number)
	local spec=ctx.spec
	local y=spec.stripeY
	local b1,b2=spec.barrel[1],spec.barrel[2]
	strip(ctx,"Cheatline",y,y,b1+0.3,b2,0.42,livery,1)
	if detail>=2 then
		strip(ctx,"Pinstripe",y-0.38,y-0.38,b1+0.3,b2,0.12,GOLD,1)
		strip(ctx,"Cheatline",y,y+2.6,b2,spec.tail[#spec.tail-2].z,0.36,livery,3)
	end
	if airline and detail>=2 then
		for side=-1,1,2 do
			local p,nrm=surface(spec,side,spec.titleY,spec.titleZ)
			if p and nrm then title(ctx,"Titles",side,p,nrm,9.5,0.95,string.upper(airline),livery) end
		end
		local f1,f2=spec.fin[1],spec.fin[2]
		local cy=f1.y+(f2.y-f1.y)*0.48
		local u=0.48
		local le=f1.le+(f2.le-f1.le)*u;local te=f1.te+(f2.te-f1.te)*u
		local th=(f1.t+(f2.t-f1.t)*u)/2+0.03
		for side=-1,1,2 do
			title(ctx,"TailName",side,Vector3.new(side*th,cy,(le+te)/2+0.2),Vector3.new(side,0,0),(te-le)*0.86,2.1,string.upper(airline),Color3.new(1,1,1))
		end
	end
end
-- LOD nose (medium / low): one ellipsoid continuing the barrel closes the top of the radome, with painted
-- cockpit panes.
local BIZ_NOSE_L=9.7
local function bizLodNose(ctx: Ctx,body: Color3,detail: number)
	local spec=ctx.spec
	local c=spec.circles[1]
	local b1=spec.barrel[1]
	ellipsoid(ctx,"Nose",Vector3.new(0,c.y,b1),Vector3.new(c.r*0.995,c.r*0.995,BIZ_NOSE_L),body,true)
	if detail<1 then return end
	local a,wy=c.r*0.995,7.55
	local function surf(side: number,z: number): (Vector3?,Vector3?)
		local q=1-((wy-c.y)/a)^2-((z-b1)/BIZ_NOSE_L)^2
		if q<=0 then return nil,nil end
		local x=a*math.sqrt(q)
		return Vector3.new(side*x,wy,z),Vector3.new(side*x/(a*a),(wy-c.y)/(a*a),(z-b1)/(BIZ_NOSE_L*BIZ_NOSE_L)).Unit
	end
	for side=-1,1,2 do
		local panes: {{number}}={{-15.4,1.3},{-17.2,1.4}}
		local z=b1-BIZ_NOSE_L
		while z<b1 do local p0=surf(side,z);if p0 and math.abs(p0.X)>=0.7 then break end;z+=0.05 end
		table.insert(panes,{z,1.2})
		for _,pz in panes do
			local p0,nrm=surf(side,pz[1])
			if p0 and nrm then part(ctx,"CockpitWindow",Vector3.new(pz[2],0.8,0.06),CFrame.lookAt(p0+nrm*0.04,p0+nrm*1.04),WINDOW) end
		end
	end
end
local function buildBizjet(ctx: Ctx,body: Color3,livery: Color3,airline: string?,detail: number,airstair: boolean)
	buildHull(ctx,body,detail)
	if detail>=2 then bizCockpit(ctx,body);bizCabin(ctx) else bizLodNose(ctx,body,detail) end
	buildWindows(ctx,body,detail)
	bizLivery(ctx,livery,airline,detail)
	buildWings(ctx,livery,detail)
	bizEngines(ctx,body,livery,detail)
	buildTail(ctx,livery,body,nil,detail)
	buildGear(ctx,detail)
	if detail>=2 then bizAirstair(ctx,body,airstair) end
end

------------------------------------------------------------------------------------------------ entry
function AircraftModel.build(parent: Instance?,cf: CFrame,opts: Options?): Model
	local o: Options=opts or {}
	local kind=if o.kind and SPECS[o.kind] then o.kind else "320"
	local spec=SPECS[kind]
	local scale=o.scale or (if kind=="bizjet" then AircraftModel.BIZJET_SCALE else 1)
	local k=specFactor(spec,scale)
	local lod=o.lod or "full"
	local detail=if lod=="low" then 0 elseif lod=="medium" then 1 else 2
	local body=o.body or rgb(240,241,238)
	local livery=o.livery or rgb(94,136,162)
	if detail==2 and o.mesh~=false then
		local template=AircraftModel.meshTemplate(kind)
		if template then
			local m=fromMesh(template,cf,k,o)
			addPoints(m,cf,kind,scale,k)
			m:SetAttribute("AircraftKind",kind);m:SetAttribute("AircraftMesh",true)
			m.Parent=parent
			return m
		end
	end
	local m=Instance.new("Model");m.Name=o.name or "Aircraft"
	local ctx: Ctx={m=m,cf=cf,k=k,collide=o.collide==true,count=0,spec=spec}
	if kind=="bizjet" then
		buildBizjet(ctx,body,livery,o.airline,detail,o.airstair==true)
		addPoints(m,cf,kind,scale,k)
		m:SetAttribute("AircraftKind",kind);m:SetAttribute("AircraftLod",lod)
		if detail>=2 then m:SetAttribute("AirstairDeployed",o.airstair==true) end
		m.WorldPivot=cf
		m.Parent=parent
		return m
	end
	buildHull(ctx,body,detail)
	if spec.cockpit and detail>=2 then buildCockpit(ctx,body) else cockpitWindowsPainted(ctx,detail) end
	buildWindows(ctx,body,detail)
	buildLivery(ctx,livery,o.airline,detail)
	buildWings(ctx,livery,detail)
	buildEngines(ctx,livery,detail)
	buildTail(ctx,livery,body,o.airline,detail)
	buildGear(ctx,detail)
	addPoints(m,cf,kind,scale,k)
	m:SetAttribute("AircraftKind",kind);m:SetAttribute("AircraftLod",lod)
	m.WorldPivot=cf
	m.Parent=parent
	return m
end

------------------------------------------------------------------------------------------------ helicopter
-- VIP helicopter (twin-engine light helicopter look, ~38 studs long, rotor 32 studs) from ~40 parts, pure
-- decoration (never collides). Frame: nose -Z, skids on y = 0. Main rotor blades carry the attribute
-- Rotor = "main" (spin about +Y through the attribute RotorHub of the model, a Vector3 in model space),
-- tail rotor blades Rotor = "tail" (about the model X axis through TailHub). Options: livery (body colour),
-- trim, name, airline (small title on the tail boom).
export type HeliOptions={livery: Color3?,trim: Color3?,name: string?,airline: string?}
function AircraftModel.buildHelicopter(parent: Instance?,cf: CFrame,opts: HeliOptions?): Model
	local o: HeliOptions=opts or {}
	local body=o.livery or rgb(24,30,44)
	local trim=o.trim or GOLD
	local m=Instance.new("Model");m.Name=o.name or "Helicopter"
	local ctx: Ctx={m=m,cf=cf,k=1,collide=false,count=0,spec=SPECS["320"]}
	local glass=rgb(36,52,66)
	local metal=rgb(70,74,80)
	-- cabin and nose
	ellipsoid(ctx,"HeliCabin",Vector3.new(0,5.4,-1.5),Vector3.new(3.9,3.7,7.2),body,true)
	ellipsoid(ctx,"HeliBelly",Vector3.new(0,3.6,-0.5),Vector3.new(3.5,1.9,6.4),body:Lerp(INK,0.25))
	local nose=ellipsoid(ctx,"HeliNoseGlass",Vector3.new(0,5.9,-6.6),Vector3.new(3.15,2.75,3.6),glass)
	nose.Material=Enum.Material.Glass;nose.Transparency=0.25
	part(ctx,"HeliFrameBar",Vector3.new(0.25,0.25,5.4),CFrame.new(0,8.25,-6.1)*CFrame.Angles(math.rad(-22),0,0),body)
	-- side windows and doors (both sides)
	for _,side in {-1,1} do
		part(ctx,"HeliWindow",Vector3.new(0.12,2.1,3.0),CFrame.new(side*3.72,6.3,-2.6)*CFrame.Angles(0,0,side*math.rad(-6)),glass,{material=Enum.Material.Glass,transparency=0.2})
		part(ctx,"HeliWindow",Vector3.new(0.12,2.0,2.6),CFrame.new(side*3.62,6.25,0.8)*CFrame.Angles(0,0,side*math.rad(-6)),glass,{material=Enum.Material.Glass,transparency=0.2})
		part(ctx,"HeliTrim",Vector3.new(0.1,0.32,11.4),CFrame.new(side*3.86,4.55,-1.2),trim,{material=Enum.Material.Metal})
		-- skids: tube, two struts, upturned front
		part(ctx,"HeliSkid",Vector3.new(16,0.55,0.55),CFrame.new(side*3.3,0.3,-0.6)*ALONG,metal,{shape=Enum.PartType.Cylinder,material=Enum.Material.Metal})
		part(ctx,"HeliSkidTip",Vector3.new(2.4,0.5,0.5),CFrame.new(side*3.3,0.95,-9.2)*CFrame.Angles(math.rad(35),0,0)*ALONG,metal,{shape=Enum.PartType.Cylinder,material=Enum.Material.Metal})
		for _,z in {-4.4,3.0} do
			part(ctx,"HeliStrut",Vector3.new(0.4,3.4,0.6),CFrame.new(side*2.9,1.9,z)*CFrame.Angles(0,0,side*math.rad(14)),metal,{material=Enum.Material.Metal})
		end
		part(ctx,"HeliNavLight",Vector3.new(0.4,0.4,0.4),CFrame.new(side*1.3,7.2,15.6),if side<0 then rgb(255,60,50) else rgb(60,255,120),{material=Enum.Material.Neon,shape=Enum.PartType.Ball})
	end
	-- engine deck, intakes, exhausts
	part(ctx,"HeliEngine",Vector3.new(4.4,2.0,7.4),CFrame.new(0,9.1,0.6),body:Lerp(Color3.new(1,1,1),0.08))
	ellipsoid(ctx,"HeliCowl",Vector3.new(0,9.6,-2.4),Vector3.new(2.2,1.1,2.6),body)
	for _,side in {-1,1} do
		cylZ(ctx,"HeliExhaust",1.4,1.0,Vector3.new(side*1.5,9.4,4.6),rgb(40,40,44),false,Enum.Material.Metal)
		part(ctx,"HeliIntake",Vector3.new(0.12,0.9,1.6),CFrame.new(side*2.22,9.4,-1.0),INK)
	end
	-- tail boom, fin, stabiliser
	cylZ(ctx,"HeliBoom",9.5,2.3,Vector3.new(0,6.6,9.6),body)
	cylZ(ctx,"HeliBoomAft",7.0,1.5,Vector3.new(0,7.1,16.6),body)
	tri(ctx,"HeliFin",Vector3.new(0,6.8,17.4),Vector3.new(0,6.8,20.6),Vector3.new(0,12.4,21.2),0.35,body)
	tri(ctx,"HeliFin",Vector3.new(0,6.8,18.6),Vector3.new(0,6.8,20.6),Vector3.new(0,3.9,20.8),0.35,body)
	part(ctx,"HeliStabilizer",Vector3.new(6.4,0.28,1.8),CFrame.new(0,7.0,15.4),body)
	cylZ(ctx,"HeliTailStripe",1.2,2.42,Vector3.new(0,6.6,12.6),trim)
	local beacon=part(ctx,"HeliBeacon",Vector3.new(0.6,0.35,0.6),CFrame.new(0,10.3,4.2),rgb(255,60,50),{material=Enum.Material.Neon})
	local _=beacon
	-- main rotor: mast, hub, 4 blades
	part(ctx,"HeliMast",Vector3.new(0.7,1.8,0.7),CFrame.new(0,10.9,0.4),metal,{material=Enum.Material.Metal})
	local hub=Vector3.new(0,11.9,0.4)
	part(ctx,"HeliHub",Vector3.new(1.6,0.6,1.6),CFrame.new(hub),rgb(40,42,46),{material=Enum.Material.Metal}):SetAttribute("Rotor","main")
	for i=0,3 do
		local a=i*math.pi/2+math.rad(20)
		local dir=Vector3.new(math.cos(a),0,math.sin(a))
		local blade=part(ctx,"HeliBlade",Vector3.new(15.4,0.14,1.05),CFrame.lookAt(hub+dir*8.2,hub+dir*8.2+dir:Cross(Vector3.new(0,1,0)))*CFrame.Angles(math.rad(4),0,0),rgb(34,36,40))
		blade:SetAttribute("Rotor","main")
	end
	-- tail rotor (left side of the fin), 2 blades
	local tailHub=Vector3.new(-0.6,10.2,20.5)
	part(ctx,"HeliTailHub",Vector3.new(0.5,0.5,0.5),CFrame.new(tailHub),metal,{shape=Enum.PartType.Ball}):SetAttribute("Rotor","tail")
	for _,a in {0,math.pi/2} do
		local blade=part(ctx,"HeliTailBlade",Vector3.new(0.1,4.6,0.5),CFrame.new(tailHub-Vector3.new(0.1,0,0))*CFrame.Angles(a,0,0),rgb(34,36,40))
		blade:SetAttribute("Rotor","tail")
	end
	if o.airline then
		for _,side in {-1,1} do
			title(ctx,"HeliTitle",side,Vector3.new(side*1.16,6.6,10.6),Vector3.new(side,0,0),6.4,0.9,string.upper(o.airline),Color3.new(1,1,1))
		end
	end
	local root=Instance.new("Part");root.Name="HeliRoot";root.Size=Vector3.new(1,1,1);root.Transparency=1;root.Anchored=true
	root.CanCollide=false;root.CanTouch=false;root.CanQuery=false;root.CastShadow=false;root.CFrame=cf;root.Parent=m
	local seat=Instance.new("Attachment");seat.Name="PassengerSeat";seat.CFrame=CFrame.new(1.6,5.6,0.6);seat.Parent=root
	local cam=Instance.new("Attachment");cam.Name="CabinCamera";cam.CFrame=CFrame.lookAt(Vector3.new(1.4,6.6,0.2),Vector3.new(12,2,-6));cam.Parent=root
	m.PrimaryPart=root
	m:SetAttribute("RotorHub",hub);m:SetAttribute("TailHub",tailHub);m:SetAttribute("AircraftKind","heli")
	m.WorldPivot=cf
	m.Parent=parent
	return m
end
return AircraftModel
