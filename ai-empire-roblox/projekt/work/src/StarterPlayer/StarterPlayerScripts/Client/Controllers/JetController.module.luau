--!strict
-- JetController (package "guests_jet", client only; Main.client calls init()): the company jets of the server
-- (ReplicatedStorage.CompanyJets/Jet_<userId>, published by JetService once per change, never per frame).
--   * Every jet is a local AircraftModel "bizjet" (JetPlan.KIND / SCALE, the operator's livery and its name on the
--     fin) posed every frame from workspace:GetServerTimeNow() with JetPlan (pushback / taxi / take-off / climb /
--     cruise / approach / landing / taxi-in / tow-in, airstair, tug) - one BulkMoveTo per frame (AircraftMover),
--     nothing written to the server. Distance LOD: full model within LOD_FULL of the camera, medium up to LOD_FAR,
--     nothing beyond (the founder riding always sees the full model).
--   * Shared Hangar 1 (City Airport): a client shows ONLY its own company's jet parked there (JetPlan.HOME_PARK,
--     in place of the airport's decorative PrivateJet, which is hidden locally while the company owns a jet), so
--     twelve owners never collide; other companies' jets appear when they leave the hangar (taxi, flight) and on
--     the Port Meridian stands (everyone sees those; JetPlan.PM_SLOTS - the parked airliner on stand 2 is hidden
--     locally while a jet uses that slot). A warm client light hangs over the own parked jet while the camera is
--     near (the airport zone's server light budget is full).
--   * The two company pilots (ReplicatedStorage.CompanyJets/Jet_<id>/Crew: EmployeeRigDesign "pilot" rigs) wait in
--     the hangar crew corner (captain on the sofa, first officer at the coffee counter; own company only), walk
--     to the airstair and into the cockpit at the start of a departure from home, fly (visible through the
--     glazed cockpit, everyone near), stay aboard in Port Meridian and walk back to the corner after the tow-in.
--     The trip companions (Companions folder, built per flight by the server) climb the airstair at the end of
--     the boarding, sit in the club seats and walk off at the destination. Poses: EmployeeController.pose (no
--     animation assets). Only near the camera (CREW_NEAR) or while riding.
--   * The founder's ride (Player attribute JetFlight = the flight id, set by JetService while the character is
--     held below the field): scriptable camera on the local jet - window seat (cabin window overlay, the wing
--     outside), cockpit (between the pilots) or outside chase view; flight info panel with a View button
--     (touch / mouse / gamepad: a TextButton), captain's announcements. Arrival: JetService places the
--     character; the attribute clears and the camera returns.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local CityPlan=require(ReplicatedStorage.Shared.Config.CityPlan)
local JP=require(ReplicatedStorage.Shared.JetPlan)
local Aircraft=require(ReplicatedStorage.Shared.AircraftModel)
local Mover=require(script.Parent.AircraftMover)
local Employee=require(script.Parent.EmployeeController)
local Toast=require(script.Parent.Parent.UI.Toast)
local Theme=require(script.Parent.Parent.UI.Theme)

local Jet={}
local player=Players.LocalPlayer
Jet.LOD_FULL=900
Jet.LOD_FAR=5000
Jet.CREW_NEAR=420 -- pilots / companions are only cloned and posed near the camera (or while riding)
Jet.TUG_NEAR=700
Jet.LIGHT_NEAR=260
Jet.COMPANION_GAP=1.5 -- seconds between two companions on the airstair
Jet.RIDE_ORDER=14 -- JetRide ScreenGui: above the HUD (10), below Phone.ORDER_CLOSED (15) / ORDER_OPEN (28) and the toasts (30)
Jet.FULL_BUILDS=1 -- full-LOD bizjet builds per frame (~270 parts each); a second jet crossing LOD_FULL waits a frame

type Rig={model: Model,root: BasePart,joints: {[string]: Motor6D},parts: {BasePart},inner: {BasePart},outer: {BasePart},seed: number,visible: boolean?,
	armsHidden: boolean,outerHidden: boolean}
export type State={flying: boolean,tl: JP.Timeline?,tau: number,parkedAt: string,slot: number,pose: JP.Pose,flightId: string?}
type View={folder: Folder,userId: number,own: boolean,model: Model?,mover: Mover.Mover?,lod: string,last: CFrame?,solid: {BasePart},colliding: boolean,
	nearCam: {BasePart},camHidden: boolean,company: string,livery: Color3,crew: {Rig},comps: {Rig},compKey: string,tug: Model?,tugMover: Mover.Mover?,
	paths: {[string]: {Vector3}},fan: number,shown: boolean,state: State?}
local views: {[Folder]: View}={}
local root: Folder?=nil
local clientFolder: Folder?=nil
local riding: string?=nil -- JetFlight while the founder is on board
local rideMode="window"
local lastPhase: string?=nil
local light: Part?=nil
local hiddenDecor: {[BasePart]: boolean}={} -- PrivateJet / PM2 parts hidden locally -> their CanCollide
local privateJet: Model?=nil
local privateConn: RBXScriptConnection?=nil
local pm2: Model?=nil
local pm2Conn: RBXScriptConnection?=nil
local nextDecorSearch=0
local stats={jets=0,models=0,crew=0,companions=0}
local fullBuilds=0 -- full models built this frame

local function num(v: any,default: number): number return if typeof(v)=="number" and v==v then v else default end
local function ensureClientFolder(): Folder
	local f=clientFolder
	if f and f.Parent then return f end
	local nf=Instance.new("Folder");nf.Name="CompanyJetClient";nf.Parent=workspace
	clientFolder=nf
	return nf
end
local function clock(seconds: number): string
	seconds=math.max(0,math.floor(seconds))
	return string.format("%d:%02d",seconds//60,seconds%60)
end

------------------------------------------------------------------------------------------------ state
local hg=CityPlan.AIRPORT.hangar
-- pivot inside Hangar 1 (door plane + 2): other companies' jets are not shown there
function Jet.inHangar(p: Vector3): boolean
	return p.X<hg.x2+2 and p.X>hg.x1 and p.Z>hg.z1 and p.Z<hg.z2
end
local PARKED_POSE=function(cf: CFrame): JP.Pose
	return {cf=cf,phase="parked",speed=0,onGround=true,gearDown=true,engines=false,altitude=0}
end
-- Where the jet of folder f is at server time t: flying (timeline + tau) or parked ("home" = Hangar 1, "abroad" =
-- Port Meridian slot). A finished flight parks the jet at its destination even before the server's At catches up.
function Jet.stateOf(f: Instance,t: number): State
	local id=f:GetAttribute("FlightId")
	local at=if f:GetAttribute("At")=="abroad" then "abroad" else "home"
	local slot=num(f:GetAttribute("Slot"),1)
	local tl: JP.Timeline?=nil
	local tau=0
	local fid: string?=nil
	if typeof(id)=="string" and id~="" then
		fid=id
		local kind=f:GetAttribute("FlightKind")
		tl=JP.timeline(if typeof(kind)=="string" then kind else "out",num(f:GetAttribute("FlightSlot"),1),num(f:GetAttribute("FlightDelay"),0))
		tau=t-num(f:GetAttribute("FlightStart"),t)
	end
	if tl and tau<tl.duration then
		tau=math.max(tau,0)
		return {flying=true,tl=tl,tau=tau,parkedAt="",slot=tl.slot,pose=JP.pose(tl,tau),flightId=fid}
	end
	if tl then at=tl.to;if at=="abroad" then slot=tl.slot end end
	return {flying=false,tl=tl,tau=tau,parkedAt=at,slot=slot,pose=PARKED_POSE(if at=="abroad" then JP.slot(slot).cf else JP.HOME_PARK),flightId=fid}
end
-- Shown on this client? Own jet always; others only outside the shared hangar.
function Jet.visible(own: boolean,st: State): boolean
	if own then return true end
	if not st.flying then return st.parkedAt=="abroad" end
	return not Jet.inHangar(st.pose.cf.Position)
end
-- Pilots' state: "corner" | "walk" | "cockpit" | "leave" (+ progress u).
function Jet.crewState(st: State): (string,number?)
	if st.flying then return JP.crew(st.tl,st.tau,nil) end
	if st.tl and st.tau>=st.tl.duration then return JP.crew(st.tl,st.tau,st.parkedAt) end
	return JP.crew(nil,0,st.parkedAt)
end
-- Does a jet use Port Meridian slot 2 (the parked airliner there is hidden locally)?
local function usesSlot2(st: State): boolean
	if st.flying then return st.tl~=nil and st.slot==2 and JP.usesSlot(st.tl :: JP.Timeline,st.tau) end
	return st.parkedAt=="abroad" and st.slot==2
end

------------------------------------------------------------------------------------------------ models
local NEAR_CAM_HIDE: {[string]: boolean}={Window=true,Outline=true,Cheatline=true,Pinstripe=true,Titles=true}
local function destroyModel(v: View)
	if v.model then v.model:Destroy() end
	v.model=nil;v.mover=nil;v.last=nil;table.clear(v.solid);table.clear(v.nearCam);v.camHidden=false
end
local function buildModel(v: View,lod: string,cf: CFrame)
	destroyModel(v)
	-- the full model collides locally while it stands still (players cannot walk through the parked jet)
	local m=Aircraft.build(nil,cf,{kind=JP.KIND,scale=JP.SCALE,lod=lod,livery=v.livery,airline=v.company,name="CompanyJet",collide=lod=="full",airstair=false})
	m:SetAttribute("JetOwner",v.userId)
	local cam=JP.POINTS.cabinCamera.Position
	for _,d in m:GetDescendants() do
		if d:IsA("BasePart") then
			if d.CanCollide then table.insert(v.solid,d) end
			if NEAR_CAM_HIDE[d.Name] and (cf:PointToObjectSpace(d.Position)-cam).Magnitude<3 then table.insert(v.nearCam,d) end
		end
	end
	m.Parent=ensureClientFolder()
	v.model=m;v.mover=Mover.new(m,cf);v.lod=lod;v.colliding=true
end
-- pushback / tow tug (client only, ~8 parts)
local function buildTug(): Model
	local m=Instance.new("Model");m.Name="JetTug"
	local function box(name: string,size: Vector3,c: Vector3,color: Color3,material: Enum.Material?)
		local p=Instance.new("Part");p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=true
		p.Size=size;p.CFrame=CFrame.new(c);p.Color=color;p.Material=material or Enum.Material.SmoothPlastic;p.Parent=m
	end
	-- frame: origin on the ground under the tug's centre, front = -Z (towards the jet's nose gear)
	box("TugBody",Vector3.new(4.2,1.6,6.4),Vector3.new(0,1.3,0),Color3.fromRGB(236,184,40))
	box("TugCab",Vector3.new(2.4,1.6,2.2),Vector3.new(-0.6,2.9,1.6),Color3.fromRGB(40,46,52),Enum.Material.Glass)
	box("TugStripe",Vector3.new(4.3,0.35,6.5),Vector3.new(0,1.75,0),Color3.fromRGB(30,30,34))
	box("TowBar",Vector3.new(0.35,0.35,2.6),Vector3.new(0,0.8,-4.4),Color3.fromRGB(70,72,76),Enum.Material.Metal)
	for _,x in {-1.9,1.9} do for _,z in {-2.1,2.1} do
		local w=Instance.new("Part");w.Name="TugWheel";w.Shape=Enum.PartType.Cylinder;w.Anchored=true;w.CanCollide=false;w.CanTouch=false;w.CanQuery=false
		w.Size=Vector3.new(0.6,1.2,1.2);w.CFrame=CFrame.new(x,0.6,z);w.Color=Color3.fromRGB(26,26,28);w.Material=Enum.Material.Rubber;w.Parent=m
	end end
	m.WorldPivot=CFrame.new()
	return m
end

------------------------------------------------------------------------------------------------ rigs
-- an arm and the parts welded to it (hand, cuff)
local function armParts(m: Model,name: string?): {BasePart}
	local out: {BasePart}={}
	local arm=if name then m:FindFirstChild(name) else nil
	if arm and arm:IsA("BasePart") then
		table.insert(out,arm)
		for _,d in m:GetDescendants() do
			local w=if d:IsA("BasePart") then d:FindFirstChildOfClass("WeldConstraint") else nil
			if w and w.Part0==arm and d:IsA("BasePart") then table.insert(out,d) end
		end
	end
	return out
end
local function cloneRig(t: Instance,parent: Instance,innerArm: string?,outerArm: string?): Rig?
	if not t:IsA("Model") then return nil end
	local m=t:Clone()
	local hum=m:FindFirstChildOfClass("Humanoid");if hum then hum:Destroy() end
	local r=m:FindFirstChild("HumanoidRootPart")
	if not r or not r:IsA("BasePart") then m:Destroy();return nil end
	local joints: {[string]: Motor6D}={}
	local parts: {BasePart}={}
	for _,d in m:GetDescendants() do
		if d:IsA("Motor6D") then joints[d.Name]=d end
		if d:IsA("BasePart") then
			d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.CastShadow=false
			if d.Name~="HumanoidRootPart" then table.insert(parts,d) end
		end
	end
	r.Anchored=true
	-- the pilot's arm on the aisle side: hidden in the cockpit view (it would fill the lower middle); the arm on the
	-- window side: hidden while seated in the cockpit (the bizjet's cockpit is narrower than two rigs side by side:
	-- it would poke through the skin below the side windows)
	local inner=armParts(m,innerArm)
	local outer=armParts(m,outerArm)
	m.Parent=parent
	local seed=m:GetAttribute("PersonalitySeed")
	return {model=m,root=r,joints=joints,parts=parts,inner=inner,outer=outer,seed=if typeof(seed)=="number" then seed else 1,visible=nil,
		armsHidden=false,outerHidden=false}
end
local function setRigVisible(r: Rig,visible: boolean)
	if r.visible==visible then return end
	r.visible=visible
	for _,p in r.parts do p.LocalTransparencyModifier=if visible then 0 else 1 end
	if r.armsHidden then for _,p in r.inner do p.LocalTransparencyModifier=1 end end
	if r.outerHidden then for _,p in r.outer do p.LocalTransparencyModifier=1 end end
end
-- the arm on the window side of a seat (model space): the one that would poke through the skin - the bizjet's
-- cockpit (skin at x +-2.46 by the pilots) and cabin (fuselage radius 3.4, club seats at x +-1.55) are narrower than a
-- seated rig with its arms (half-width 1.95)
function Jet.windowArm(seat: CFrame): string
	return if seat.Position.X*seat.RightVector.X>0 then "Right Arm" else "Left Arm"
end
local function setOuterHidden(r: Rig,hide: boolean)
	if r.outerHidden==hide then return end
	r.outerHidden=hide
	for _,p in r.outer do p.LocalTransparencyModifier=if hide or r.visible==false then 1 else 0 end
end
local function poseRig(r: Rig,cf: CFrame,activity: string,sitting: boolean,walking: boolean,t: number,pose: string?,detail: boolean)
	r.root.CFrame=cf
	if not detail then return end
	for name,tr in Employee.pose(activity,sitting,walking,t,r.seed,nil,pose) do
		local j=r.joints[name]
		if j and j.Parent then j.Transform=tr end
	end
end
local function dropRigs(list: {Rig})
	for _,r in list do r.model:Destroy() end
	table.clear(list)
end
local function pathLength(path: {Vector3}): number
	local total=0
	for i=2,#path do total+=(path[i]-path[i-1]).Magnitude end
	return total
end
-- point and walking direction at fraction u of a polyline
function Jet.along(path: {Vector3},u: number): (Vector3,Vector3)
	local s=math.clamp(u,0,1)*pathLength(path)
	for i=2,#path do
		local seg=(path[i]-path[i-1]).Magnitude
		if s<=seg or i==#path then
			local d=path[i]-path[i-1]
			local f=if seg>0 then math.clamp(s/seg,0,1) else 1
			return path[i-1]:Lerp(path[i],f),if d.Magnitude>1e-3 then d.Unit else Vector3.new(0,0,-1)
		end
		s-=seg
	end
	return path[#path],Vector3.new(0,0,-1)
end
local function walkFrame(path: {Vector3},u: number,reverse: boolean): CFrame
	local p,dir=Jet.along(path,u)
	local f=Vector3.new(dir.X,0,dir.Z)
	if reverse then f=-f end
	if f.Magnitude<1e-3 then f=Vector3.new(0,0,-1) end
	return CFrame.lookAt(p,p+f.Unit)
end
local function cachedPath(v: View,key: string,make: () -> {Vector3}): {Vector3}
	local p=v.paths[key]
	if p then return p end
	local np=make()
	v.paths[key]=np
	return np
end
local function reversed(path: {Vector3}): {Vector3}
	local out: {Vector3}={}
	for i=#path,1,-1 do table.insert(out,path[i]) end
	return out
end
-- Companion k's walk this flight: boarding (departure airport) or deboarding (arrival) path, departure order.
function Jet.companionPath(tl: JP.Timeline,k: number,deboard: boolean): {Vector3}
	if not deboard then
		if tl.dir=="out" then return JP.companionPath(JP.HOME_PARK,k,true) end
		return JP.companionPath(JP.slot(tl.slot).cf,k,false,tl.slot)
	end
	if tl.dir=="out" then return reversed(JP.companionPath(tl.park,k,false,tl.slot)) end
	-- home: down the airstair at the stand in front of the hangar, then towards the hangar door (no detour round
	-- the hangar's parking box)
	local seat=JP.POINTS.cabinSeats[JP.COMPANION_SEATS[k] or 1]
	return reversed(JP.boardPath(JP.HOME_STAND,seat,JP.COMPANION_FROM,nil))
end

local function updateCrew(v: View,st: State,t: number,camPos: Vector3,detail: boolean)
	local near=(riding~=nil and v.own) or (v.shown and (camPos-st.pose.cf.Position).Magnitude<Jet.CREW_NEAR)
	if not near then
		if #v.crew>0 then dropRigs(v.crew) end
		return
	end
	if #v.crew==0 then
		local templates=v.folder:FindFirstChild("Crew")
		if not templates then return end
		for i,name in {"Captain","FirstOfficer"} do
			local tpl=templates:FindFirstChild(name)
			local seat=if i==1 then JP.POINTS.captain else JP.POINTS.firstOfficer
			local r=if tpl then cloneRig(tpl,ensureClientFolder(),if i==1 then "Right Arm" else "Left Arm",Jet.windowArm(seat)) else nil
			if r then table.insert(v.crew,r) end
		end
		if #v.crew<2 then dropRigs(v.crew);return end
	end
	local state,u=Jet.crewState(st)
	local pts=JP.POINTS
	for i,r in v.crew do
		local seat=if i==1 then pts.captain else pts.firstOfficer
		local visible=true
		local seated=state=="cockpit"
		if state=="cockpit" then
			poseRig(r,st.pose.cf*seat,"COCKPIT",true,false,t,nil,detail)
		elseif not v.own then
			visible=false -- the shared hangar's crew corner shows only the local company's pilots
		elseif state=="corner" then
			local spot=JP.CREW.spots[i] or JP.CREW.spots[1]
			if JP.CREW.sit[i] then poseRig(r,spot,"IDLE",true,false,t,"phone",detail)
			else poseRig(r,spot,"COFFEE_BREAK",false,false,t,nil,detail) end
		else
			-- walk (corner -> cockpit) / leave (cockpit -> corner); the first officer follows 1.4 s later
			local total=JP.CONFIG.crewWalk
			local delay=(i-1)*1.4
			local w=math.clamp(((u or 0)*total-delay)/(total-2),0,1)
			local path=cachedPath(v,"crew"..i,function() return JP.crewPath(JP.HOME_PARK,i) end)
			if state=="leave" then
				if w>=1 then poseRig(r,JP.CREW.spots[i] or JP.CREW.spots[1],"IDLE",JP.CREW.sit[i]==true,false,t,nil,detail)
				else poseRig(r,walkFrame(path,1-w,true),"WALKING",false,w>0,t,nil,detail) end
			else
				if w>=1 then poseRig(r,st.pose.cf*seat,"COCKPIT",true,false,t,nil,detail);seated=true
				else poseRig(r,walkFrame(path,w,false),"WALKING",false,w>0,t,nil,detail) end
			end
		end
		setRigVisible(r,visible)
		setOuterHidden(r,seated)
	end
end
local function updateCompanions(v: View,st: State,t: number,camPos: Vector3,detail: boolean)
	local tl=st.tl
	local mode,u=nil,nil
	if tl and st.flying then mode,u=JP.companions(tl,st.tau) end
	local near=(riding~=nil and v.own) or (v.shown and (camPos-st.pose.cf.Position).Magnitude<Jet.CREW_NEAR)
	local key=st.flightId or ""
	if not mode or not near or key~=v.compKey then
		if #v.comps>0 then dropRigs(v.comps) end
		v.compKey=key
		if not mode or not near then return end
	end
	local f=v.folder:FindFirstChild("Companions")
	if #v.comps==0 then
		if not f then return end
		for k=1,3 do
			local tpl=f:FindFirstChild("Companion"..k)
			local r=if tpl then cloneRig(tpl,ensureClientFolder(),nil,Jet.windowArm(JP.POINTS.cabinSeats[JP.COMPANION_SEATS[k] or 1])) else nil
			if r then table.insert(v.comps,r) end
		end
		if #v.comps==0 then return end
	end
	local ttl=tl :: JP.Timeline
	local pts=JP.POINTS
	local n=#v.comps
	for k,r in v.comps do
		local visible=true
		local seated=mode=="seated"
		if mode=="seated" then
			local seat=pts.cabinSeats[JP.COMPANION_SEATS[k] or 1]
			poseRig(r,st.pose.cf*seat,"IDLE",true,false,t,"relax",detail)
		else
			local deboard=mode=="deboard"
			local T=if deboard then ttl.phases.deboarding.t1-ttl.phases.deboarding.t0 else JP.COMPANION_BOARD
			local gap=Jet.COMPANION_GAP
			local w=math.clamp(((u or 0)*T-(k-1)*gap)/math.max(1,T-(n-1)*gap-0.5),0,1)
			local path=cachedPath(v,key..(if deboard then ":off" else ":on")..k,function() return Jet.companionPath(ttl,k,deboard) end)
			if deboard then
				-- seated until the walk starts, gone (into the terminal / the limousine) after it
				if w<=0 then poseRig(r,st.pose.cf*pts.cabinSeats[JP.COMPANION_SEATS[k] or 1],"IDLE",true,false,t,"relax",detail);seated=true
				elseif w>=1 then visible=false
				else poseRig(r,walkFrame(path,w,false),"WALKING",false,true,t,nil,detail) end
			else
				if w<=0 then visible=false
				elseif w>=1 then poseRig(r,st.pose.cf*pts.cabinSeats[JP.COMPANION_SEATS[k] or 1],"IDLE",true,false,t,"relax",detail);seated=true
				else poseRig(r,walkFrame(path,w,false),"WALKING",false,true,t,nil,detail) end
			end
		end
		setRigVisible(r,visible)
		setOuterHidden(r,seated)
	end
end

------------------------------------------------------------------------------------------------ decor hiding
local function hidePart(p: Instance)
	if p:IsA("BasePart") and hiddenDecor[p]==nil then
		hiddenDecor[p]=p.CanCollide
		p.LocalTransparencyModifier=1;p.CanCollide=false;p.CanQuery=false
	end
end
local function restore(m: Model?)
	if not m then return end
	for _,p in m:GetDescendants() do
		if p:IsA("BasePart") and hiddenDecor[p]~=nil then
			p.LocalTransparencyModifier=0;p.CanCollide=hiddenDecor[p] :: boolean;p.CanQuery=true
			hiddenDecor[p]=nil
		end
	end
end
-- WorldCity/Airport/Hangar/PrivateJet (AirportBuilder) and the Port Meridian stand-2 airliner (MetroBuilder,
-- ParkedAircraft with Stand = "PM2"): searched every 3 s at most while needed and not streamed in.
local function findDecor(t: number,wantPrivate: boolean,wantPM2: boolean)
	if t<nextDecorSearch then return end
	if not ((wantPrivate and not (privateJet and privateJet.Parent)) or (wantPM2 and not (pm2 and pm2.Parent))) then return end
	nextDecorSearch=t+3
	local world=workspace:FindFirstChild("WorldCity")
	if not world then return end
	if wantPrivate and not (privateJet and privateJet.Parent) then
		local airport=world:FindFirstChild("Airport")
		local hangar=if airport then airport:FindFirstChild("Hangar") else nil
		local m=if hangar then hangar:FindFirstChild("PrivateJet") else nil
		if m and m:IsA("Model") then privateJet=m end
	end
	if wantPM2 and not (pm2 and pm2.Parent) then
		local pm=world:FindFirstChild("PortMeridian")
		local field=if pm then pm:FindFirstChild("Airfield") or pm else nil
		if field then
			for _,d in field:GetDescendants() do
				if d:IsA("Model") and d.Name=="ParkedAircraft" and d:GetAttribute("Stand")=="PM2" then pm2=d;break end
			end
		end
	end
end
local function setHidden(m: Model?,hide: boolean,conn: RBXScriptConnection?): RBXScriptConnection?
	if not m then return conn end
	if hide then
		for _,p in m:GetDescendants() do hidePart(p) end
		if not conn then return m.DescendantAdded:Connect(hidePart) end
		return conn
	end
	if conn then conn:Disconnect() end
	restore(m)
	return nil
end
local privateHidden,pm2Hidden=false,false
local function updateDecor(t: number,ownJet: boolean,slot2: boolean)
	findDecor(t,ownJet,slot2)
	if ownJet~=privateHidden or (ownJet and privateJet and not privateConn) then
		privateConn=setHidden(privateJet,ownJet,privateConn)
		privateHidden=ownJet and (if privateJet then true else false)
	end
	if slot2~=pm2Hidden or (slot2 and pm2 and not pm2Conn) then
		pm2Conn=setHidden(pm2,slot2,pm2Conn)
		pm2Hidden=slot2 and (if pm2 then true else false)
	end
end

------------------------------------------------------------------------------------------------ ride
local rideGui: ScreenGui?=nil
local rideInfo: TextLabel?=nil
local windowFrame: Frame?=nil
local chaseEye: Vector3?=nil
local function playerGui(): Instance? return player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui",2) end
local function rideButtonText(): string
	return "View: "..(if rideMode=="window" then "Window seat" elseif rideMode=="cockpit" then "Cockpit" else "Outside")
end
local function openRide()
	if rideGui then return end
	local pg=playerGui()
	if not pg then return end
	-- above the HUD (10), below the phone (launcher 15, open 28) and the toasts (UIRoot top layer 30): the phone
	-- (itinerary, calendar, calls) stays reachable in flight and the captain's announcements readable
	local gui=Instance.new("ScreenGui");gui.Name="JetRide";gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=Jet.RIDE_ORDER
	-- cabin window: an oval transparent frame whose huge stroke paints the cabin wall around it (its rim ends above the
	-- flight info box on an 844x390 phone: bottom at 0.595 of the height + the 12 px rim, top below a one-line toast)
	local win=Instance.new("Frame");win.Name="CabinWindow";win.AnchorPoint=Vector2.new(0.5,0.5);win.Position=UDim2.fromScale(0.5,0.365)
	win.Size=UDim2.fromScale(0.32,0.46);win.BackgroundTransparency=1;win.Parent=gui
	local wc=Instance.new("UICorner");wc.CornerRadius=UDim.new(0.5,0);wc.Parent=win
	local wall=Instance.new("UIStroke");wall.Thickness=1800;wall.Color=Color3.fromRGB(226,216,198);wall.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;wall.Parent=win
	local rim=Instance.new("Frame");rim.Name="Rim";rim.AnchorPoint=Vector2.new(0.5,0.5);rim.Position=UDim2.fromScale(0.5,0.5);rim.Size=UDim2.fromScale(1,1);rim.BackgroundTransparency=1;rim.Parent=win
	local rc=Instance.new("UICorner");rc.CornerRadius=UDim.new(0.5,0);rc.Parent=rim
	local rs=Instance.new("UIStroke");rs.Thickness=12;rs.Color=Color3.fromRGB(150,118,84);rs.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;rs.Parent=rim
	windowFrame=win
	-- flight info at the bottom (clear of the window on short phone screens and of the top bar)
	local box=Instance.new("Frame");box.Name="FlightInfo";box.AnchorPoint=Vector2.new(0.5,1);box.Position=UDim2.new(0.5,0,1,-28);box.Size=UDim2.fromOffset(440,76)
	box.BackgroundColor3=Theme.colors.panel;box.BackgroundTransparency=0.08;box.BorderSizePixel=0;box.Parent=gui
	local size=Instance.new("UISizeConstraint");size.MaxSize=Vector2.new(440,76);size.Parent=box
	local bc=Instance.new("UICorner");bc.CornerRadius=UDim.new(0,10);bc.Parent=box
	local stripe=Instance.new("Frame");stripe.Name="Stripe";stripe.Size=UDim2.new(0,6,1,0);stripe.BackgroundColor3=Color3.fromRGB(196,160,92);stripe.BorderSizePixel=0;stripe.Parent=box
	local info=Instance.new("TextLabel");info.Name="Info";info.BackgroundTransparency=1;info.Position=UDim2.fromOffset(16,6);info.Size=UDim2.new(1,-170,1,-12)
	info.TextXAlignment=Enum.TextXAlignment.Left;info.TextYAlignment=Enum.TextYAlignment.Center;info.Font=Theme.font.medium;info.TextSize=15
	info.TextColor3=Theme.colors.text;info.TextWrapped=true;info.Text="";info.Parent=box
	rideInfo=info
	local button=Instance.new("TextButton");button.Name="ViewButton";button.AnchorPoint=Vector2.new(1,0.5);button.Position=UDim2.new(1,-10,0.5,0);button.Size=UDim2.fromOffset(146,46)
	button.BackgroundColor3=Theme.colors.raised;button.TextColor3=Theme.colors.text;button.Font=Theme.font.bold;button.TextSize=14;button.Text=rideButtonText();button.AutoButtonColor=true;button.Parent=box
	local btc=Instance.new("UICorner");btc.CornerRadius=UDim.new(0,8);btc.Parent=button
	button.Activated:Connect(function()
		rideMode=if rideMode=="window" then "cockpit" elseif rideMode=="cockpit" then "outside" else "window"
		button.Text=rideButtonText()
		chaseEye=nil
	end)
	gui.Parent=pg
	rideGui=gui
end
Jet.openRide=openRide
local function setCamHidden(v: View?,hide: boolean)
	if v and v.camHidden~=hide then
		v.camHidden=hide
		for _,p in v.nearCam do
			p.LocalTransparencyModifier=if hide then 1 else 0
			for _,g in p:GetChildren() do if g:IsA("SurfaceGui") then g.Enabled=not hide end end
		end
	end
end
local function setArmsHidden(v: View?,hide: boolean)
	if not v then return end
	for _,r in v.crew do
		local h=hide and r.visible==true
		if r.armsHidden~=h then
			r.armsHidden=h
			for _,p in r.inner do p.LocalTransparencyModifier=if h or r.visible==false then 1 else 0 end
		end
	end
end
local function ownView(): View?
	for _,v in views do if v.own then return v end end
	return nil
end
local function closeRide()
	local v=ownView()
	setCamHidden(v,false);setArmsHidden(v,false)
	if rideGui then rideGui:Destroy();rideGui=nil;rideInfo=nil;windowFrame=nil end
	local camera=workspace.CurrentCamera
	if camera then
		camera.CameraType=Enum.CameraType.Custom
		camera.FieldOfView=70
		local character=player.Character
		local humanoid=if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then camera.CameraSubject=humanoid end
	end
	chaseEye=nil
end
local function updateRideCamera(v: View,pose: JP.Pose,dt: number)
	local camera=workspace.CurrentCamera
	if not camera then return end
	camera.CameraType=Enum.CameraType.Scriptable
	local pts=JP.POINTS
	local win=windowFrame
	if win then win.Visible=rideMode=="window" end
	setCamHidden(v,rideMode=="window")
	setArmsHidden(v,rideMode=="cockpit")
	if rideMode=="window" then
		camera.FieldOfView=64
		camera.CFrame=pose.cf*pts.cabinCamera
	elseif rideMode=="cockpit" then
		camera.FieldOfView=60
		camera.CFrame=pose.cf*pts.cockpitCamera
	else
		camera.FieldOfView=60
		local want=(pose.cf*CFrame.new(-pts.span*0.6,pts.height*0.7,pts.length*1.25)).Position
		local prev=chaseEye
		local eye: Vector3=if prev then prev:Lerp(want,math.clamp(dt*2.5,0,1)) else want
		chaseEye=eye
		camera.CFrame=CFrame.lookAt(eye,pose.cf.Position+Vector3.new(0,pts.height*0.35,0))
	end
end
local ANNOUNCE: {[string]: string}={
	taxi="Cabin crew, doors closed. We are taxiing to the runway.",
	climb="We are climbing out over the coast. Make yourself comfortable.",
	approach="We are starting our approach. Please fasten your seat belt.",
	taxiin="Welcome! Please stay seated until we reach the stand.",
}
local function announce(v: View,st: State)
	local tl=st.tl
	if not tl then return end
	if st.pose.phase=="pushback" or (st.pose.phase=="startup" and tl.dir~="out") then
		local crew=v.folder:FindFirstChild("Crew")
		local cap=if crew then crew:FindFirstChild("Captain") else nil
		local name=if cap and typeof(cap:GetAttribute("PilotName"))=="string" then cap:GetAttribute("PilotName") :: string else ""
		local dest=if tl.to=="abroad" then "Port Meridian" else "City Airport"
		local ph=tl.phases
		Toast.show("info","This is your captain"..(if name~="" then ", "..name else "")..". Welcome aboard the "..v.company.." jet to "..dest
			..". Flight time today is about "..math.max(1,math.floor((ph.deboarding.t0-ph.takeoff.t0)/60+0.5)).." minutes.",8)
	elseif ANNOUNCE[st.pose.phase] then
		Toast.show("info",ANNOUNCE[st.pose.phase],5)
	end
end
local function updateRideInfo(v: View,st: State,t: number)
	local info=rideInfo
	local tl=st.tl
	if not info or not tl then return end
	local route=if tl.to=="abroad" then "to Port Meridian" else "to City Airport"
	local phase=JP.PHASE_TEXT[st.pose.phase] or st.pose.phase
	local start=t-st.tau
	local dep,arr=JP.times(tl,start)
	-- no countdown once the jet is at its stand (deboarding / parked while the arrival area streams in)
	local extra=if t<dep then " · departure in "..clock(dep-t) elseif t<arr then " · arrival in "..clock(arr-t) else ""
	-- a departure delay (JetPlan.schedule): the boarding says why
	if st.pose.phase=="boarding" and tl.delay>0 then phase="Waiting for a clear runway" end
	info.Text=v.company.." jet "..route.."\n"..phase..extra
end
function Jet.rideMode(): string return rideMode end
function Jet.setRideMode(mode: string)
	if mode~="window" and mode~="cockpit" and mode~="outside" then return end
	rideMode=mode
	local b=if rideGui then rideGui:FindFirstChild("ViewButton",true) else nil
	if b and b:IsA("TextButton") then b.Text=rideButtonText() end
end

------------------------------------------------------------------------------------------------ views
-- the local company (headless renders without a LocalPlayer may set Jet.localUserId)
Jet.localUserId=nil :: number?
local function localId(): number
	if Jet.localUserId then return Jet.localUserId :: number end
	return if player then player.UserId else 0
end
local function newView(f: Folder): View?
	local owner=f:GetAttribute("Owner")
	if typeof(owner)~="number" then return nil end
	local company=f:GetAttribute("Company")
	local livery=f:GetAttribute("Livery")
	return {folder=f,userId=owner,own=owner==localId(),model=nil,mover=nil,lod="none",last=nil,solid={},colliding=true,nearCam={},camHidden=false,
		company=if typeof(company)=="string" then company else "Company",livery=if typeof(livery)=="Color3" then livery else Color3.fromRGB(24,120,128),
		crew={},comps={},compKey="",tug=nil,tugMover=nil,paths={},fan=0,shown=false,state=nil}
end
local function dropView(v: View)
	destroyModel(v);dropRigs(v.crew);dropRigs(v.comps)
	if v.tug then v.tug:Destroy();v.tug=nil;v.tugMover=nil end
end
local function sync()
	local r=root
	if not r then return end
	for f,v in views do
		if f.Parent~=r then dropView(v);views[f]=nil end
	end
	for _,f in r:GetChildren() do
		if f:IsA("Folder") and not views[f] then
			local v=newView(f)
			if v then views[f]=v end
		elseif f:IsA("Folder") then
			local v=views[f]
			local company=f:GetAttribute("Company");local livery=f:GetAttribute("Livery")
			if v and ((typeof(company)=="string" and company~=v.company) or (typeof(livery)=="Color3" and livery~=v.livery)) then
				v.company=if typeof(company)=="string" then company else v.company
				v.livery=if typeof(livery)=="Color3" then livery else v.livery
				destroyModel(v) -- rebuilt with the new name / colours on the next frame
				dropRigs(v.crew) -- the server rebuilds the crew badges
			end
		end
	end
end
local function updateLight(v: View?,st: State?,camPos: Vector3)
	local want=v~=nil and st~=nil and v.model~=nil and (not st.flying and st.parkedAt=="home" or (st.flying and Jet.inHangar(st.pose.cf.Position)))
		and (camPos-JP.HOME_PARK.Position).Magnitude<Jet.LIGHT_NEAR
	if want and not light then
		local p=Instance.new("Part");p.Name="JetHangarLight";p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
		p.Transparency=1;p.Size=Vector3.new(1,1,1);p.CFrame=JP.HOME_PARK*CFrame.new(0,26,0) -- above the fin, below the roof
		local l=Instance.new("PointLight");l.Range=60;l.Brightness=1.5;l.Color=Color3.fromRGB(255,236,206);l.Shadows=false;l.Parent=p
		-- the crew corner (JetPlan.CREW, outside the jet light's reach): a warm lamp over the sofa so the pilots read
		local c=Instance.new("Part");c.Name="CrewCornerLight";c.Anchored=true;c.CanCollide=false;c.CanTouch=false;c.CanQuery=false;c.CastShadow=false
		c.Transparency=1;c.Size=Vector3.new(1,1,1);c.CFrame=CFrame.new((JP.CREW.spots[1].Position+JP.CREW.spots[2].Position)/2+Vector3.new(0,7,0))
		local cl=Instance.new("PointLight");cl.Range=32;cl.Brightness=2.2;cl.Color=Color3.fromRGB(255,224,180);cl.Shadows=false;cl.Parent=c
		c.Parent=p
		p.Parent=ensureClientFolder()
		light=p
	elseif not want and light then
		light:Destroy();light=nil
	end
end

local function stepView(v: View,t: number,dt: number,camPos: Vector3)
	local st=Jet.stateOf(v.folder,t)
	v.state=st
	v.shown=Jet.visible(v.own,st)
	-- the ride view stays on the jet until JetService has placed the founder (JetFlight cleared), also when the arrival
	-- area streams in after the flight has ended
	local isRide=v.own and riding~=nil and riding==st.flightId
	local dist=(camPos-st.pose.cf.Position).Magnitude
	local want=if not v.shown then "none" elseif isRide or dist<Jet.LOD_FULL then "full" elseif dist<Jet.LOD_FAR then "medium" else "none"
	if want=="none" then
		if v.model then destroyModel(v) end
	elseif not v.model or v.lod~=want then
		-- a frame builds at most FULL_BUILDS full models (the ride always gets its own at once); the others keep their
		-- medium model (or build one) and upgrade on a later frame
		if want=="full" and not isRide and fullBuilds>=Jet.FULL_BUILDS then
			if not v.model then buildModel(v,"medium",st.pose.cf) end
		else
			if want=="full" then fullBuilds+=1 end
			buildModel(v,want,st.pose.cf)
		end
	end
	local mv=v.mover
	local pose=st.pose
	if v.model and mv then
		if pose.engines or v.last~=pose.cf then
			if pose.engines then v.fan=(v.fan+dt*(if pose.onGround and pose.speed<1 then 9 else 26))%(math.pi*2) end
			Mover.move(mv,pose.cf,v.fan)
			v.last=pose.cf
		end
		Mover.setGear(mv,pose.gearDown)
		local still=pose.onGround and pose.speed<0.01
		if still~=v.colliding then
			v.colliding=still
			for _,p in v.solid do p.CanCollide=still end
		end
		if v.lod=="full" then
			local down=if st.flying then JP.stairsDown(st.tl,st.tau,nil) else JP.stairsDown(nil,0,st.parkedAt)
			Aircraft.setAirstair(v.model :: Model,down)
		end
	end
	-- tug (pushback out of / tow into the hangar)
	local tugCf=if st.flying and st.tl and v.shown and dist<Jet.TUG_NEAR then JP.tug(st.tl :: JP.Timeline,st.tau) else nil
	if tugCf then
		if not v.tug then
			local m=buildTug();m.Parent=ensureClientFolder()
			v.tug=m;v.tugMover=Mover.new(m,CFrame.new())
		end
		Mover.move(v.tugMover :: Mover.Mover,tugCf)
	elseif v.tug then
		v.tug:Destroy();v.tug=nil;v.tugMover=nil
	end
	local detail=dist<160 or isRide
	updateCrew(v,st,t,camPos,detail)
	updateCompanions(v,st,t,camPos,detail)
	if isRide then
		openRide()
		updateRideCamera(v,pose,dt)
		if lastPhase and lastPhase~=pose.phase then announce(v,st) end
		lastPhase=pose.phase
	end
end

local infoAcc=0
local function step(dt: number)
	fullBuilds=0
	local t=workspace:GetServerTimeNow()
	local camera=workspace.CurrentCamera
	local camPos=if camera then camera.CFrame.Position else Vector3.zero
	local own: View?=nil
	local slot2=false
	local n,models,crew,comps=0,0,0,0
	for _,v in views do
		stepView(v,t,dt,camPos)
		if v.own then own=v end
		if v.state and usesSlot2(v.state :: State) then slot2=true end
		n+=1;if v.model then models+=1 end;crew+=#v.crew;comps+=#v.comps
	end
	stats.jets=n;stats.models=models;stats.crew=crew;stats.companions=comps
	updateDecor(t,own~=nil,slot2)
	updateLight(own,if own then own.state else nil,camPos)
	infoAcc+=dt
	if infoAcc>=0.25 then
		infoAcc=0
		if riding and own and own.state then updateRideInfo(own,own.state :: State,t) end
	end
end
Jet.step=step
Jet.sync=sync
function Jet.views(): {[Folder]: View} return views end
function Jet.stats(): typeof(stats) return stats end
function Jet.riding(): string? return riding end
function Jet.decor(): (Model?,boolean,Model?,boolean) return privateJet,privateHidden,pm2,pm2Hidden end

------------------------------------------------------------------------------------------------ init
local function onFlight()
	local id=player:GetAttribute("JetFlight")
	if typeof(id)=="string" and id~="" then
		riding=id
		rideMode="window"
		lastPhase=nil
		openRide()
		Toast.show("success","Welcome aboard your company jet! Use the View button to change the camera.",5)
	elseif riding then
		riding=nil
		closeRide()
		local state=player:GetAttribute("TravelState")
		if state=="abroad" then
			-- the stand the jet actually uses (JetPlan.PM_SLOTS: slot 1 VIP apron, slot 2 Stand 2)
			local v=ownView()
			local slot=if v then num(v.folder:GetAttribute("FlightSlot"),num(v.folder:GetAttribute("Slot"),1)) else 1
			Toast.show("success","Welcome to Port Meridian! The VIP limousine stand is right here. Your jet waits "..JP.slot(slot).where.." - its airstair takes you home.",8)
		elseif state==nil then
			Toast.show("success","Welcome back to City Airport! Your jet is towed into Hangar 1.",6)
		end
	end
end
Jet.onFlight=onFlight
function Jet.attach(folder: Folder)
	root=folder
	folder.ChildAdded:Connect(function() task.defer(sync) end)
	folder.ChildRemoved:Connect(function() task.defer(sync) end)
	sync()
end
function Jet.init()
	task.spawn(function()
		local f=ReplicatedStorage:WaitForChild("CompanyJets",30)
		if not f or not f:IsA("Folder") then return end
		Jet.attach(f)
		-- attribute changes of a jet folder (company renamed, livery) are picked up here at most twice a second
		local acc=0
		RunService.RenderStepped:Connect(function(dt: number)
			acc+=dt
			if acc>=0.5 then acc=0;sync() end
			step(dt)
		end)
	end)
	player:GetAttributeChangedSignal("JetFlight"):Connect(onFlight)
	player.CharacterAdded:Connect(function()
		if riding then riding=nil;closeRide() end
	end)
	if player:GetAttribute("JetFlight")~=nil then onFlight() end
end
return Jet
