--!strict
-- ShuttlePassengers (package "flight", client only; stepped by ShuttleController): the field staff of the
-- server's companies who fly on the current shuttle leg (user request 20: "field staff on international trips
-- take the shuttle, visible when players are near"). ShuttleService builds their rigs once per leg as templates
-- (ReplicatedStorage.Shuttle.Passengers, attribute Leg = "<dir>:<cycle>"); here they are cloned and walked
-- with EmployeeController poses (no animation assets, no physics, no network):
--   * boarding: one after another from the gate (City Airport: the boarding lane at gate A<n> and the jet
--     bridge; Port Meridian: the hall's apron door and the airstairs) through the forward left door into the
--     cabin, where they disappear (the cabin windows are opaque);
--   * deboarding at the arrival airport: the same way back out into the terminal.
-- Only near the camera (NEAR studs from the aircraft); at most Shuttle.MAX_PAX walkers; clones live until
-- their walk ends even if the server replaces the templates for the next leg.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CityPlan=require(ReplicatedStorage.Shared.Config.CityPlan)
local FP=require(ReplicatedStorage.Shared.FlightPlan)
local Aircraft=require(ReplicatedStorage.Shared.AircraftModel)
local Employee=require(script.Parent.EmployeeController)
local Pax={}
Pax.NEAR=420
Pax.START=5 -- seconds into the boarding / deboarding before the first walker starts
Pax.GAP=4.5 -- seconds between two walkers
Pax.SPEED=4.2 -- studs per second

type Walker={model: Model,root: BasePart,joints: {[string]: Motor6D},parts: {BasePart},seed: number,path: {Vector3},length: number,
	start: number,reverse: boolean,shown: boolean?}
type Group={key: string,walkers: {Walker},ends: number}
local groups: {[string]: Group}={}

local function pathLength(path: {Vector3}): number
	local total=0
	for i=2,#path do total+=(path[i]-path[i-1]).Magnitude end
	return total
end
local function along(path: {Vector3},s: number): (Vector3,Vector3)
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
Pax.along=along

-- Walk path (root height) from the departure / arrival terminal into the cabin of the aircraft at `cf`.
-- stairs: the Port Meridian airstairs model (attributes Bottom / Top) if present.
function Pax.path(atHome: boolean,cf: CFrame,stairs: Instance?): {Vector3}?
	local pts=Aircraft.points(FP.CONFIG.kind,FP.CONFIG.scale)
	local door=cf*pts.doorL1
	local floorY=door.Position.Y-pts.doorHalf+3
	local sill=Vector3.new(door.Position.X,floorY,door.Position.Z)+door.LookVector*0.8
	local cabin=cf*Vector3.new(pts.doorL1.X*0.3,pts.cabin.floorY+3,pts.doorL1.Z+4)
	local path: {Vector3}={}
	if atHome then
		local g=CityPlan.AIRPORT.gates[CityPlan.AIRPORT.shuttleStand] or CityPlan.AIRPORT.gates[1]
		local world=workspace:FindFirstChild("WorldCity")
		local bridge=if world then world:FindFirstChild("JetBridge_A"..CityPlan.AIRPORT.shuttleStand,true) else nil
		local td=if bridge then bridge:GetAttribute("TerminalDoor") else nil
		local y=CityPlan.GROUND+3.5
		local terminalDoor: Vector3=if typeof(td)=="Vector3" then td else Vector3.new(g.Position.X-11.4,y,CityPlan.AIRPORT.terminal.z2)
		-- from the seats of the gate lounge down the boarding lane to the bridge, through the bridge
		table.insert(path,Vector3.new(g.Position.X+8,terminalDoor.Y,terminalDoor.Z-16))
		table.insert(path,Vector3.new(terminalDoor.X,terminalDoor.Y,terminalDoor.Z-10))
		table.insert(path,terminalDoor)
		table.insert(path,sill+door.LookVector*4)
	else
		local doorPos=FP.PM_DOOR
		if not doorPos then return nil end -- no apron: nobody walks across the runway
		local bottom: Vector3?=nil;local top: Vector3?=nil
		if stairs then
			local b=stairs:GetAttribute("Bottom");local t=stairs:GetAttribute("Top")
			if typeof(b)=="Vector3" then bottom=b end
			if typeof(t)=="Vector3" then top=t end
		end
		local foot=bottom or (sill+door.LookVector*14-Vector3.new(0,floorY-(CityPlan.GROUND+3.5),0))
		table.insert(path,doorPos-Vector3.new(10,0,0))
		table.insert(path,doorPos)
		table.insert(path,doorPos+Vector3.new(6,0,0))
		table.insert(path,foot+door.LookVector*5)
		table.insert(path,foot)
		if top then table.insert(path,top) end
	end
	table.insert(path,sill)
	table.insert(path,cabin)
	return path
end

local function clone(t: Model,parent: Instance): Walker?
	local m=t:Clone()
	local hum=m:FindFirstChildOfClass("Humanoid");if hum then hum:Destroy() end
	local root=m:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then m:Destroy();return nil end
	local joints: {[string]: Motor6D}={}
	local parts: {BasePart}={}
	for _,d in m:GetDescendants() do
		if d:IsA("Motor6D") then joints[d.Name]=d end
		if d:IsA("BasePart") then
			d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.CastShadow=false
			if d.Name~="HumanoidRootPart" then table.insert(parts,d) end
		end
	end
	root.Anchored=true
	m.Parent=parent
	local seed=m:GetAttribute("PersonalitySeed")
	return {model=m,root=root,joints=joints,parts=parts,seed=if typeof(seed)=="number" then seed else 1,path={},length=0,start=0,reverse=false,shown=nil}
end
local function setShown(w: Walker,shown: boolean)
	if w.shown==shown then return end
	w.shown=shown
	for _,p in w.parts do p.LocalTransparencyModifier=if shown then 0 else 1 end
end
local function dropGroup(key: string)
	local g=groups[key]
	if not g then return end
	for _,w in g.walkers do w.model:Destroy() end
	groups[key]=nil
end

-- The phase window of leg st in which walkers move: boarding (on) or deboarding (off) - (key, t0, reverse,
-- at home).
local function window(st: FP.State): (string?,number,boolean,boolean)
	local ph=st.leg.phases
	if st.phase=="boarding" then return st.dir..":"..st.cycle,st.legStart+ph.boarding.t0,false,st.dir=="out" end
	if st.phase=="deboarding" then return st.dir..":"..st.cycle,st.legStart+ph.deboarding.t0,true,st.dir=="back" end
	return nil,0,false,false
end

function Pax.step(st: FP.State,pose: FP.Pose,t: number,camPos: Vector3,folder: Instance?,parent: Instance,stairs: Instance?)
	local near=(camPos-pose.cf.Position).Magnitude<Pax.NEAR
	local key,t0,reverse,atHome=window(st)
	local gkey=if key then key..(if reverse then ":off" else ":on") else nil
	-- start a group when its window opens (templates must belong to this leg)
	if near and gkey and key and not groups[gkey] then
		local templates=if folder then folder:FindFirstChild("Passengers") else nil
		if templates and templates:GetAttribute("Leg")==key then
			local path=Pax.path(atHome,pose.cf,stairs)
			if path then
				local g: Group={key=gkey,walkers={},ends=0}
				local len=pathLength(path)
				local i=0
				for _,tpl in templates:GetChildren() do
					if not tpl:IsA("Model") then continue end
					local w=clone(tpl,parent)
					if w then
						w.path=path;w.length=len;w.start=t0+Pax.START+i*Pax.GAP;w.reverse=reverse
						table.insert(g.walkers,w)
						g.ends=math.max(g.ends,w.start+len/Pax.SPEED+0.5)
						i+=1
					end
				end
				groups[gkey]=g
			end
		end
	end
	for k,g in groups do
		if t>g.ends or not near then dropGroup(k);continue end
		for _,w in g.walkers do
			local walked=(t-w.start)*Pax.SPEED
			if walked<0 then
				-- boarding: still in the terminal (hidden); deboarding: still in the cabin (hidden)
				setShown(w,false)
			elseif walked>=w.length then
				setShown(w,false) -- boarded (inside the cabin) / gone into the terminal
			else
				local s=if w.reverse then w.length-walked else walked
				local p,dir=along(w.path,s)
				local flat=Vector3.new(dir.X,0,dir.Z)
				if w.reverse then flat=-flat end
				if flat.Magnitude<1e-3 then flat=Vector3.new(0,0,-1) end
				w.root.CFrame=CFrame.lookAt(p,p+flat.Unit)
				for name,tr in Employee.pose("WALKING",false,true,t,w.seed) do
					local j=w.joints[name]
					if j and j.Parent then j.Transform=tr end
				end
				setShown(w,true)
			end
		end
	end
end
function Pax.count(): number
	local n=0
	for _,g in groups do n+=#g.walkers end
	return n
end
function Pax.walkers(): {Model}
	local out: {Model}={}
	for _,g in groups do for _,w in g.walkers do table.insert(out,w.model) end end
	return out
end
function Pax.reset()
	for k in groups do dropGroup(k) end
end
return Pax
