--!strict
-- ShuttleController (package "flight", client only; required and initialised by TravelController).
--   * The Port Meridian shuttle: a local AircraftModel (kind/scale from ReplicatedStorage.Shuttle) posed every
--     frame from workspace:GetServerTimeNow() with FlightPlan (the server only publishes timetable attributes,
--     never positions). One BulkMoveTo per frame (AircraftMover), fans spin with the engines on, gear retracts.
--     Distance LOD: full model within 900 studs of the camera, medium up to 5,000, nothing beyond (riders
--     always see the full model). The full model collides locally only while it stands still (a player on the
--     apron is never trapped inside the moving fuselage). The airport package's parked aircraft on the
--     shuttle stand is hidden locally (the shuttle parks exactly there, at the same scale, so the jet bridge
--     still meets its door).
--   * The two pilots: clones of the server-built rigs (ReplicatedStorage.Shuttle.Crew) walk from the CrewRoom
--     marker through the gate and the jet bridge into the cockpit and sit there (visible through the
--     windshield) until they leave after the arrival home; at Port Meridian they stay aboard and the first
--     officer does the walkaround (down the airstairs to the nose gear and back). Poses from
--     EmployeeController.pose (no animation assets).
--   * Ground handling and flight information (ShuttleGround): pushback tugs, the jet bridge retracting and
--     docking, live rows on the airport's flight information boards, the Port Meridian gate board. Field staff
--     flying on the leg (ShuttlePassengers) walk on and off when players are near.
--   * Tickets and boarding: check-in -> TravelAction {action="ticket"}; a boarding pass panel counts down
--     (all times computed locally from FlightPlan); a beacon marks the gate; the boards show the live status
--     of the next departure ("missed it" = the next one). Board prompt -> {action="board"}.
--   * The ride (Player attribute ShuttleLeg set by the server): scriptable camera on the local aircraft -
--     window seat (cabin window frame overlay, wing and engine outside; the thin window / outline / livery
--     plates right at the camera are hidden locally), cockpit (jump seat behind the pilots; their inner arms
--     are hidden locally) or outside chase view; flight info panel; cabin announcements by the captain. The
--     character itself is held by the server (see ShuttleService), so nothing here needs physics or network
--     ownership.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local CityPlan=require(ReplicatedStorage.Shared.Config.CityPlan)
local FP=require(ReplicatedStorage.Shared.FlightPlan)
local Aircraft=require(ReplicatedStorage.Shared.AircraftModel)
local Format=require(ReplicatedStorage.Shared.Format)
local Mover=require(script.Parent.AircraftMover)
local Ground=require(script.Parent.ShuttleGround)
local Pax=require(script.Parent.ShuttlePassengers)
local Action=require(script.Parent.ActionController)
local Employee=require(script.Parent.EmployeeController)
local Toast=require(script.Parent.Parent.UI.Toast)
local Theme=require(script.Parent.Parent.UI.Theme)
local Shuttle={}
local player=Players.LocalPlayer
Shuttle.LOD_FULL=900
Shuttle.LOD_FAR=5000
Shuttle.CREW_NEAR=420 -- pilots are only built/updated near the camera (or on board)

local MESSAGES: {[string]: string}={
	NO_TICKET="Check in at a counter first to get your boarding pass.",
	NOT_AT_GATE="Walk to the gate to board.",
	NOT_AT_CHECKIN="Walk up to a check-in counter first.",
	NO_MONEY="You need "..Format.money(CityPlan.TRAVEL.ticket).." for the return ticket to Port Meridian.",
	LEAVE_VEHICLE="Leave your car before boarding.",
	BUSY="You are already on board.",
	ALREADY_ABROAD="You are already abroad. Check in at Port Meridian Airport to fly home.",
	NOT_ABROAD="You are already at home.",
	SHUTTLE_OFF="The shuttle is not flying right now.",
	LOADING="Still loading - try again in a moment.",
	RATE_LIMIT="Slow down a little.",
}
local function message(err: any): string
	if typeof(err)=="string" and MESSAGES[err] then return MESSAGES[err] end
	return Action.message(if typeof(err)=="string" then err else nil)
end
local function clock(seconds: number): string
	seconds=math.max(0,math.floor(seconds))
	return string.format("%d:%02d",seconds//60,seconds%60)
end
Shuttle.clock=clock

------------------------------------------------------------------------------------------------ state
local folder: Folder?=nil
local clientFolder: Folder?=nil
type Plane={model: Model,mover: Mover.Mover,lod: string,last: CFrame?,solid: {BasePart},colliding: boolean,nearCam: {BasePart},camHidden: boolean}
local plane: Plane?=nil
local fanAngle=0
local lastState: FP.State?=nil
type Ticket={flight: string,to: string,gate: string,departs: number,boardingStarts: number,boardingEnds: number,destination: string}
local ticket: Ticket?=nil
local riding: string?=nil -- ShuttleLeg key while on board
local rideMode="window"
local hiddenStand: Model?=nil
local hiddenConn: RBXScriptConnection?=nil
local airstairs: Model?=nil
function Shuttle.active(): boolean
	local f=folder or ReplicatedStorage:FindFirstChild("Shuttle")
	return f~=nil and f:IsA("Folder") and f:GetAttribute("Enabled")==true
end
function Shuttle.ticket(): Ticket? return ticket end
function Shuttle.riding(): string? return riding end
function Shuttle.plane(): Model? return if plane then plane.model else nil end
local function kindScale(): (string,number)
	local f=folder
	local kind=if f and typeof(f:GetAttribute("Kind"))=="string" then f:GetAttribute("Kind") :: string else FP.CONFIG.kind
	local scale=if f and typeof(f:GetAttribute("Scale"))=="number" then f:GetAttribute("Scale") :: number else FP.CONFIG.scale
	return kind,scale
end
local ptsKey="";local ptsCache: Aircraft.Points?=nil
local function points(): Aircraft.Points
	local kind,scale=kindScale()
	local key=kind..":"..scale
	local c=ptsCache
	if c and key==ptsKey then return c end
	local p=Aircraft.points(kind,scale)
	ptsCache=p;ptsKey=key
	return p
end
local function ensureClientFolder(): Folder
	local cf=clientFolder
	if cf and cf.Parent then return cf end
	local f=Instance.new("Folder");f.Name="ShuttleClient";f.Parent=workspace
	clientFolder=f
	return f
end

------------------------------------------------------------------------------------------------ aircraft
local NEAR_CAM_HIDE: {[string]: boolean}={Window=true,Outline=true,Cheatline=true,Pinstripe=true,Titles=true}
local function destroyPlane()
	if plane then plane.model:Destroy();plane=nil end
end
local function buildPlane(lod: string,cf: CFrame)
	destroyPlane()
	local kind,scale=kindScale()
	-- the full model collides locally while it stands still (players cannot walk through the parked shuttle);
	-- far LODs never do
	local m=Aircraft.build(nil,cf,{kind=kind,scale=scale,lod=lod,livery=Color3.fromRGB(24,120,128),airline=FP.CONFIG.airline,name="ShuttleAircraft",collide=lod=="full"})
	m:SetAttribute("ShuttleClient",true)
	local solid: {BasePart}={}
	local nearCam: {BasePart}={}
	local cam=Aircraft.points(kind,scale).cabinCamera.Position
	local root=m.PrimaryPart
	for _,d in m:GetDescendants() do
		if d:IsA("BasePart") then
			if d.CanCollide then table.insert(solid,d) end
			-- thin skin plates within 4 studs of the window-seat camera (the fuselage cylinder is culled from
			-- inside, these are not): hidden locally while riding in the window seat
			if root and NEAR_CAM_HIDE[d.Name] and (root.CFrame:PointToObjectSpace(d.Position)-cam).Magnitude<4 then table.insert(nearCam,d) end
		end
	end
	m.Parent=ensureClientFolder()
	plane={model=m,mover=Mover.new(m,cf),lod=lod,last=nil,solid=solid,colliding=true,nearCam=nearCam,camHidden=false}
end
-- The airport package parks an aircraft on the shuttle stand; the shuttle replaces it locally.
local nextStandSearch=0
local function hideStandAircraft(t: number)
	if hiddenStand and hiddenStand.Parent then return end
	hiddenStand=nil
	if t<nextStandSearch then return end
	nextStandSearch=t+3 -- searched only every 3 s while it is not streamed in
	local world=workspace:FindFirstChild("WorldCity")
	if not world then return end
	-- AirportBuilder: WorldCity/Airport/Apron/ParkedAircraft (a few dozen children); until the apron has
	-- streamed in, just retry in 3 s
	local airport=world:FindFirstChild("Airport")
	local apron=if airport then airport:FindFirstChild("Apron") else nil
	if not apron then return end
	for _,d in apron:GetChildren() do
		if d:IsA("Model") and d.Name=="ParkedAircraft" and d:GetAttribute("Stand")==CityPlan.AIRPORT.shuttleStand then
			local function hidePart(p: Instance)
				if p:IsA("BasePart") then p.LocalTransparencyModifier=1;p.CanCollide=false;p.CanQuery=false end
			end
			for _,p in d:GetDescendants() do hidePart(p) end
			-- the model is not Atomic: parts that stream in later are hidden as they arrive
			if hiddenConn then hiddenConn:Disconnect() end
			hiddenConn=d.DescendantAdded:Connect(hidePart)
			hiddenStand=d
			return
		end
	end
end

------------------------------------------------------------------------------------------------ airstairs (Port Meridian)
local function buildAirstairs(): Model
	local m=Instance.new("Model");m.Name="ShuttleAirstairs"
	local pts=points()
	local stand=FP.PM_STAND
	local door=stand*pts.doorL1 -- outward = LookVector
	local sill=door.Position.Y-pts.doorHalf
	local out=door.LookVector
	local side=out:Cross(Vector3.new(0,1,0))
	local ground=CityPlan.ROAD_TOP
	local h=sill-ground
	local run=h*1.25
	local function part(name: string,size: Vector3,cf: CFrame,color: Color3,material: Enum.Material?)
		local p=Instance.new("Part");p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
		p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic;p.Parent=m
	end
	local top=Vector3.new(door.Position.X,sill,door.Position.Z)+out*0.9
	local bottom=top+out*run-Vector3.new(0,h,0)
	local mid=(top+bottom)/2
	local len=(top-bottom).Magnitude
	local frame=CFrame.lookAt(mid,mid+(bottom-top).Unit)
	part("StairFlight",Vector3.new(4.2,0.4,len),frame,Color3.fromRGB(190,194,198),Enum.Material.DiamondPlate)
	local steps=math.max(4,math.floor(h/0.9))
	for i=1,steps-1 do
		local p=top:Lerp(bottom,i/steps)
		part("StairStep",Vector3.new(4.2,0.2,0.5),CFrame.lookAt(p+Vector3.new(0,0.2,0),p+Vector3.new(0,0.2,0)+out),Color3.fromRGB(150,154,158),Enum.Material.Metal)
	end
	for _,s in {-1,1} do
		part("Handrail",Vector3.new(0.25,0.25,len),frame*CFrame.new(s*2.1,3.2,0),Color3.fromRGB(230,232,234),Enum.Material.Metal)
		for k=0,2 do
			local p=top:Lerp(bottom,k/2)+side*s*2.1
			part("RailPost",Vector3.new(0.2,3.2,0.2),CFrame.new(p+Vector3.new(0,1.6,0)),Color3.fromRGB(230,232,234),Enum.Material.Metal)
		end
	end
	part("Platform",Vector3.new(4.6,0.4,2.2),CFrame.lookAt(top+out*0.6,top+out*2),Color3.fromRGB(190,194,198),Enum.Material.DiamondPlate)
	-- the tow truck under the stairs
	local base=(top+bottom)/2;base=Vector3.new(base.X,ground+1.4,base.Z)
	part("StairTruck",Vector3.new(5.6,2.4,run*0.8),CFrame.lookAt(base,base+out),Color3.fromRGB(236,236,232))
	part("StairTruckStripe",Vector3.new(5.7,0.5,run*0.8),CFrame.lookAt(base+Vector3.new(0,0.4,0),base+Vector3.new(0,0.4,0)+out),Color3.fromRGB(24,120,128))
	for _,s in {-1,1} do for _,f in {-0.3,0.3} do
		local w=base+side*s*2.6+out*(run*f)-Vector3.new(0,0.6,0)
		local p=Instance.new("Part");p.Name="StairWheel";p.Shape=Enum.PartType.Cylinder;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
		p.Size=Vector3.new(0.7,1.6,1.6);p.CFrame=CFrame.lookAt(w,w+out)*CFrame.Angles(0,math.pi/2,0);p.Color=Color3.fromRGB(26,26,28);p.Material=Enum.Material.Rubber;p.Parent=m
	end end
	m:SetAttribute("Bottom",bottom+Vector3.new(0,3,0));m:SetAttribute("Top",top+Vector3.new(0,3,0))
	return m
end
local function setAirstairs(show: boolean)
	if show and not airstairs then
		local m=buildAirstairs();m.Parent=ensureClientFolder();airstairs=m
	elseif not show and airstairs then
		airstairs:Destroy();airstairs=nil
	end
end

------------------------------------------------------------------------------------------------ crew
type CrewMember={model: Model,root: BasePart,joints: {[string]: Motor6D},seed: number,seat: CFrame,delay: number,visible: boolean?,parts: {BasePart},
	inner: {BasePart},armsHidden: boolean}
local crew: {CrewMember}={}
local function dropCrew()
	for _,c in crew do c.model:Destroy() end
	table.clear(crew)
end
local function buildCrew(): boolean
	if #crew>0 then return true end
	local f=folder
	local templates=if f then f:FindFirstChild("Crew") else nil
	if not templates then return false end
	local pts=points()
	for i,name in {"Captain","FirstOfficer"} do
		local t=templates:FindFirstChild(name)
		if t and t:IsA("Model") then
			local m=t:Clone()
			local hum=m:FindFirstChildOfClass("Humanoid");if hum then hum:Destroy() end
			local root=m:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
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
				-- the arm on the aisle side (captain: right, first officer: left) and its hand: hidden in the
				-- cockpit view, where it would fill the lower middle of the frame
				local arm=m:FindFirstChild(if i==1 then "Right Arm" else "Left Arm")
				local inner: {BasePart}={}
				if arm and arm:IsA("BasePart") then
					table.insert(inner,arm)
					for _,d in m:GetDescendants() do
						local w=if d:IsA("BasePart") then d:FindFirstChildOfClass("WeldConstraint") else nil
						if w and w.Part0==arm and d:IsA("BasePart") then table.insert(inner,d) end
					end
				end
				m.Parent=ensureClientFolder()
				local seed=m:GetAttribute("PersonalitySeed")
				table.insert(crew,{model=m,root=root,joints=joints,seed=if typeof(seed)=="number" then seed else i*97,seat=if i==1 then pts.captain else pts.firstOfficer,
					delay=(i-1)*1.4,visible=nil,parts=parts,inner=inner,armsHidden=false})
			else m:Destroy() end
		end
	end
	return #crew>0
end
local function cachedBridge(): (Vector3?,Vector3?)
	local world=workspace:FindFirstChild("WorldCity")
	local bridge=if world then world:FindFirstChild("JetBridge_A"..CityPlan.AIRPORT.shuttleStand,true) else nil
	if not bridge then return nil,nil end
	local td=bridge:GetAttribute("TerminalDoor");local ad=bridge:GetAttribute("AircraftDoor")
	return if typeof(td)=="Vector3" then td else nil,if typeof(ad)=="Vector3" then ad else nil
end
local function crewRoomPoints(): {Vector3}
	local a=CityPlan.AIRPORT
	local p0=a.crewRoom.Position
	local door=p0+Vector3.new(0,0,9)
	local world=workspace:FindFirstChild("WorldCity")
	local marker=if world then world:FindFirstChild("CrewRoom",true) else nil
	if marker then
		local inner=marker:FindFirstChild("CrewRoom")
		local m=if marker:IsA("BasePart") then marker elseif inner and inner:IsA("BasePart") then inner else nil
		local d=if m then m:GetAttribute("Door") else nil
		if typeof(d)=="Vector3" then door=Vector3.new(d.X,p0.Y,d.Z) end
	end
	return {p0,door}
end
-- Walk path (world points, root height) from the departure terminal to the cockpit seat for the plane at cf.
local function crewPath(atHome: boolean,cf: CFrame,seat: CFrame): {Vector3}
	local pts=points()
	local door=cf*pts.doorL1
	local floorY=cf.Position.Y+pts.cabin.floorY+3
	local inCabin={cf*Vector3.new(pts.doorL1.X*0.55,pts.cabin.floorY+3,pts.doorL1.Z),cf*Vector3.new(0,pts.cabin.floorY+3,pts.doorL1.Z-1.5),
		cf*Vector3.new(0,pts.cabin.floorY+3,seat.Z+3.2),cf*Vector3.new(seat.X,seat.Y,seat.Z+1.2)}
	local path: {Vector3}={}
	local sillPoint=Vector3.new(door.Position.X,floorY,door.Position.Z)+door.LookVector*0.8
	if atHome then
		local room=crewRoomPoints()
		local td,_=cachedBridge()
		local g=CityPlan.AIRPORT.gates[CityPlan.AIRPORT.shuttleStand] or CityPlan.AIRPORT.gates[1]
		local terminalDoor=td or Vector3.new(g.Position.X-11.4,CityPlan.GROUND+3.5,CityPlan.AIRPORT.terminal.z2)
		-- out of the crew room onto the concourse, then straight down the boarding lane (between the queue
		-- belts, west of the gate desk) to the jet bridge door
		table.insert(path,room[1]);table.insert(path,room[2])
		table.insert(path,Vector3.new(room[2].X,room[1].Y,room[2].Z+5))
		table.insert(path,Vector3.new(terminalDoor.X,room[1].Y,room[2].Z+6))
		table.insert(path,Vector3.new(terminalDoor.X,room[1].Y,terminalDoor.Z))
		table.insert(path,sillPoint+door.LookVector*4)
	else
		-- Port Meridian walkaround: from the foot of the airstairs (ahead of the nose gear and back - see
		-- walkaroundPath) up into the aircraft
		local stairs=airstairs
		local bottom=if stairs and typeof(stairs:GetAttribute("Bottom"))=="Vector3" then stairs:GetAttribute("Bottom") :: Vector3 else sillPoint+door.LookVector*14
		local top=if stairs and typeof(stairs:GetAttribute("Top"))=="Vector3" then stairs:GetAttribute("Top") :: Vector3 else sillPoint+door.LookVector*1.2
		table.insert(path,bottom)
		table.insert(path,top)
	end
	table.insert(path,sillPoint)
	for _,p in inCabin do table.insert(path,p) end
	return path
end
-- The first officer's walkaround at Port Meridian: seat -> door -> down the airstairs -> beside the nose gear
-- -> back up -> seat.
local function walkaroundPath(cf: CFrame,seat: CFrame): {Vector3}
	local into=crewPath(false,cf,seat) -- foot of the stairs ... seat
	local pts=points()
	local nose=cf*Vector3.new(pts.doorL1.X*0.5,3,pts.noseGearZ-5)
	local path: {Vector3}={}
	for i=#into,1,-1 do table.insert(path,into[i]) end
	table.insert(path,nose)
	for _,p in into do table.insert(path,p) end
	return path
end
local function along(path: {Vector3},u: number): (Vector3,Vector3)
	local total=0
	for i=2,#path do total+=(path[i]-path[i-1]).Magnitude end
	local s=math.clamp(u,0,1)*total
	for i=2,#path do
		local seg=(path[i]-path[i-1]).Magnitude
		if s<=seg or i==#path then
			local dir=path[i]-path[i-1]
			local f=if seg>0 then math.clamp(s/seg,0,1) else 1
			return path[i-1]:Lerp(path[i],f),if dir.Magnitude>1e-3 then dir.Unit else Vector3.new(0,0,-1)
		end
		s-=seg
	end
	return path[#path],Vector3.new(0,0,-1)
end
local function poseCrew(c: CrewMember,cf: CFrame,sitting: boolean,walking: boolean,t: number,near: boolean)
	c.root.CFrame=cf
	if not near then return end
	-- seated: "COCKPIT" (not a desk activity: arms down, hands in the lap - the autopilot flies)
	local transforms=Employee.pose(if sitting then "COCKPIT" else "WALKING",sitting,walking,t,c.seed)
	for name,tr in transforms do
		local j=c.joints[name]
		if j and j.Parent then j.Transform=tr end
	end
end
local pathKey=""
local pathCache: {[number]: {Vector3}}={}
local function updateCrew(st: FP.State,pose: FP.Pose,t: number,camPos: Vector3)
	local near=riding~=nil or (camPos-pose.cf.Position).Magnitude<Shuttle.CREW_NEAR
	if not near then if #crew>0 then dropCrew() end return end
	if not buildCrew() then return end
	local state,since=FP.crewTimes(st)
	local atHome=(st.dir=="out" and st.phase=="boarding") or (st.dir=="back" and st.phase=="deboarding")
	local closeUp=riding~=nil or (camPos-pose.cf.Position).Magnitude<160
	local wa=FP.walkaround(st)
	for idx,c in crew do
		local visible=true
		if wa and idx==2 then
			local key="wa"..st.cycle
			if key~=pathKey then pathKey=key;table.clear(pathCache) end
			local path=pathCache[idx]
			if not path then path=walkaroundPath(pose.cf,c.seat);pathCache[idx]=path end
			local u=math.clamp(wa/FP.WALKAROUND,0,1)
			-- a short look at the nose gear half way round
			local half=0.5
			if math.abs(u-half)<0.06 then u=half end
			local p,dir=along(path,u)
			local flatDir=Vector3.new(dir.X,0,dir.Z)
			if flatDir.Magnitude<1e-3 then flatDir=pose.cf.LookVector*Vector3.new(1,0,1) end
			if u<=0.001 or u>=0.999 then poseCrew(c,pose.cf*c.seat,true,false,t,closeUp)
			else poseCrew(c,CFrame.lookAt(p,p+flatDir.Unit),false,u~=half,t,closeUp) end
		elseif (state=="walking" or state=="leaving") and since then
			local walkT=since-c.delay
			local dur=(if state=="walking" then FP.CREW_WALK else FP.CREW_LEAVE)-2
			local u=math.clamp(walkT/dur,0,1)
			if state=="leaving" then u=1-u end
			local key=(if atHome then "home" else "pm")..st.dir..st.cycle..state
			if key~=pathKey then pathKey=key;table.clear(pathCache) end
			local path=pathCache[idx]
			if not path then path=crewPath(atHome,pose.cf,c.seat);pathCache[idx]=path end
			local p,dir=along(path,u)
			local flatDir=Vector3.new(dir.X,0,dir.Z)
			if state=="leaving" then flatDir=-flatDir end
			if flatDir.Magnitude<1e-3 then flatDir=pose.cf.LookVector*Vector3.new(1,0,1) end
			local seated=u>=0.999
			if seated then poseCrew(c,pose.cf*c.seat,true,false,t,closeUp)
			else poseCrew(c,CFrame.lookAt(p,p+flatDir.Unit),false,walkT>0 and walkT<dur,t,closeUp) end
			-- before the walk starts / after it ends the pilot is inside the terminal
			visible=not ((state=="walking" and walkT<0) or (state=="leaving" and walkT>dur))
		elseif state=="cockpit" then
			poseCrew(c,pose.cf*c.seat,true,false,t,closeUp)
		else
			visible=false
		end
		if c.visible~=visible then
			c.visible=visible
			for _,d in c.parts do d.LocalTransparencyModifier=if visible then 0 else 1 end
			if c.armsHidden then for _,d in c.inner do d.LocalTransparencyModifier=1 end end
		end
	end
end

------------------------------------------------------------------------------------------------ boarding pass + gate
local passGui: ScreenGui?=nil
local passText: TextLabel?=nil
local beacon: Part?=nil
local function playerGui(): Instance? return player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui",2) end
local function closePass()
	if passGui then passGui:Destroy();passGui=nil;passText=nil end
	if beacon then beacon:Destroy();beacon=nil end
end
local function openPass()
	closePass()
	local pg=playerGui()
	if not pg then return end
	local gui=Instance.new("ScreenGui");gui.Name="ShuttlePass";gui.ResetOnSpawn=false;gui.DisplayOrder=25
	local box=Instance.new("Frame");box.Name="Pass";box.AnchorPoint=Vector2.new(1,0.5);box.Position=UDim2.new(1,-16,0.5,40);box.Size=UDim2.fromOffset(270,96)
	box.BackgroundColor3=Theme.colors.panel;box.BackgroundTransparency=0.06;box.BorderSizePixel=0;box.Parent=gui
	local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,10);corner.Parent=box
	local stripe=Instance.new("Frame");stripe.Size=UDim2.new(0,6,1,0);stripe.BackgroundColor3=Color3.fromRGB(24,120,128);stripe.BorderSizePixel=0;stripe.Parent=box
	local t=Instance.new("TextLabel");t.Name="Text";t.BackgroundTransparency=1;t.Position=UDim2.fromOffset(16,6);t.Size=UDim2.new(1,-24,1,-12)
	t.TextXAlignment=Enum.TextXAlignment.Left;t.TextYAlignment=Enum.TextYAlignment.Top;t.TextWrapped=true;t.RichText=false
	t.Font=Theme.font.medium;t.TextSize=15;t.TextColor3=Theme.colors.text;t.Text="";t.Parent=box
	gui.Parent=pg
	passGui=gui;passText=t
	-- a beacon over the boarding gate
	local tk=ticket
	if tk then
		local pos=if tk.to=="abroad" then FP.HOME_GATES[1] else FP.PM_GATES[1]
		local b=Instance.new("Part");b.Name="ShuttleGateBeacon";b.Anchored=true;b.CanCollide=false;b.CanTouch=false;b.CanQuery=false;b.CastShadow=false
		b.Shape=Enum.PartType.Cylinder;b.Size=Vector3.new(26,1.2,1.2);b.CFrame=CFrame.new(pos+Vector3.new(0,16,0))*CFrame.Angles(0,0,math.pi/2)
		b.Color=Color3.fromRGB(24,170,180);b.Material=Enum.Material.Neon;b.Transparency=0.35;b.Parent=ensureClientFolder()
		local bb=Instance.new("BillboardGui");bb.Size=UDim2.fromOffset(200,44);bb.StudsOffsetWorldSpace=Vector3.new(0,16,0);bb.AlwaysOnTop=true;bb.MaxDistance=400;bb.Parent=b
		local l=Instance.new("TextLabel");l.BackgroundTransparency=1;l.Size=UDim2.fromScale(1,1);l.TextScaled=true;l.Font=Theme.font.bold;l.TextColor3=Color3.new(1,1,1)
		l.TextStrokeTransparency=0.4;l.Text=(if tk.to=="abroad" then "Gate "..tk.gate else "Boarding")..(" · "..tk.flight);l.Parent=bb
		beacon=b
	end
end
-- Status line of the next departure in direction dir at time t (boards, pass): ShuttleGround.statusText.
Shuttle.statusText=Ground.statusText
local function updatePass(t: number)
	local tk=ticket
	local label=passText
	if not tk or not label then return end
	local dir=if tk.to=="abroad" then "out" else "back"
	local st=FP.at(t)
	local leg=FP.leg(dir)
	local route=if tk.to=="abroad" then "City Airport  →  Port Meridian" else "Port Meridian  →  City Airport"
	local line: string
	if st.dir==dir and st.phase=="boarding" then
		line="BOARDING NOW at "..(if tk.to=="abroad" then "gate "..tk.gate else "the gate").." · departs in "..clock(st.legStart+leg.phases.pushback.t0-t)
	else
		local _,start,dep=FP.nextLeg(dir,t)
		if t>tk.boardingEnds+1 and dep>tk.departs+1 then
			line="You missed "..tk.flight..". Your pass is valid for the next one: boarding in "..clock(start-t).." (departs "..clock(dep-t)..")."
		else
			line="Boarding in "..clock(start-t).." at "..(if tk.to=="abroad" then "gate "..tk.gate else "the gate").." · departs in "..clock(dep-t)
		end
	end
	label.Text="BOARDING PASS · "..tk.flight.."\n"..route.."\n"..line
end
------------------------------------------------------------------------------------------------ ride
local rideGui: ScreenGui?=nil
local rideInfo: TextLabel?=nil
local windowFrame: Frame?=nil
local chaseEye: Vector3?=nil
local function rideButtonText(): string
	return "View: "..(if rideMode=="window" then "Window seat" elseif rideMode=="cockpit" then "Cockpit" else "Outside")
end
local function openRide()
	if rideGui then return end
	local pg=playerGui()
	if not pg then return end
	local gui=Instance.new("ScreenGui");gui.Name="ShuttleRide";gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=80
	-- cabin window: a rounded transparent frame whose huge stroke paints the cabin wall around it
	local win=Instance.new("Frame");win.Name="CabinWindow";win.AnchorPoint=Vector2.new(0.5,0.5);win.Position=UDim2.fromScale(0.5,0.5)
	win.Size=UDim2.fromScale(0.42,0.62);win.BackgroundTransparency=1;win.Parent=gui
	local wc=Instance.new("UICorner");wc.CornerRadius=UDim.new(0.45,0);wc.Parent=win
	local wall=Instance.new("UIStroke");wall.Thickness=1800;wall.Color=Color3.fromRGB(214,212,204);wall.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;wall.Parent=win
	local rim=Instance.new("Frame");rim.Name="Rim";rim.AnchorPoint=Vector2.new(0.5,0.5);rim.Position=UDim2.fromScale(0.5,0.5);rim.Size=UDim2.new(1,0,1,0);rim.BackgroundTransparency=1;rim.Parent=win
	local rc=Instance.new("UICorner");rc.CornerRadius=UDim.new(0.45,0);rc.Parent=rim
	local rs=Instance.new("UIStroke");rs.Thickness=14;rs.Color=Color3.fromRGB(168,166,160);rs.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;rs.Parent=rim
	windowFrame=win
	local box=Instance.new("Frame");box.Name="FlightInfo";box.AnchorPoint=Vector2.new(0.5,0);box.Position=UDim2.new(0.5,0,0,58);box.Size=UDim2.fromOffset(420,74)
	box.BackgroundColor3=Theme.colors.panel;box.BackgroundTransparency=0.08;box.BorderSizePixel=0;box.Parent=gui
	local bc=Instance.new("UICorner");bc.CornerRadius=UDim.new(0,10);bc.Parent=box
	local info=Instance.new("TextLabel");info.BackgroundTransparency=1;info.Position=UDim2.fromOffset(14,6);info.Size=UDim2.new(1,-150,1,-12)
	info.TextXAlignment=Enum.TextXAlignment.Left;info.TextYAlignment=Enum.TextYAlignment.Center;info.Font=Theme.font.medium;info.TextSize=15
	info.TextColor3=Theme.colors.text;info.TextWrapped=true;info.Text="";info.Parent=box
	rideInfo=info
	local button=Instance.new("TextButton");button.Name="ViewButton";button.AnchorPoint=Vector2.new(1,0.5);button.Position=UDim2.new(1,-10,0.5,0);button.Size=UDim2.fromOffset(128,40)
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
local function setCamHidden(hide: boolean)
	local pl=plane
	if pl and pl.camHidden~=hide then
		pl.camHidden=hide
		for _,p in pl.nearCam do
			p.LocalTransparencyModifier=if hide then 1 else 0
			for _,g in p:GetChildren() do if g:IsA("SurfaceGui") then g.Enabled=not hide end end
		end
	end
end
local function setArmsHidden(hide: boolean)
	for _,c in crew do
		local h=hide and c.visible==true
		if c.armsHidden~=h then
			c.armsHidden=h
			for _,p in c.inner do p.LocalTransparencyModifier=if h or c.visible==false then 1 else 0 end
		end
	end
end
local function closeRide()
	setCamHidden(false);setArmsHidden(false)
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
local function updateRideCamera(pose: FP.Pose,dt: number)
	local camera=workspace.CurrentCamera
	if not camera then return end
	camera.CameraType=Enum.CameraType.Scriptable
	local pts=points()
	local win=windowFrame
	if win then win.Visible=rideMode=="window" end
	setCamHidden(rideMode=="window")
	setArmsHidden(rideMode=="cockpit")
	if rideMode=="window" then
		camera.FieldOfView=62
		camera.CFrame=pose.cf*pts.cabinCamera
	elseif rideMode=="cockpit" then
		camera.FieldOfView=56 -- jump seat: windshield, glareshield and displays between the pilots' heads
		camera.CFrame=pose.cf*pts.cockpitCamera
	else
		camera.FieldOfView=60
		local want=(pose.cf*CFrame.new(-pts.span*0.55,pts.height*0.55,pts.length*1.15)).Position
		local prevEye=chaseEye
		local eye: Vector3=if prevEye then prevEye:Lerp(want,math.clamp(dt*2.5,0,1)) else want
		chaseEye=eye
		camera.CFrame=CFrame.lookAt(eye,pose.cf.Position+Vector3.new(0,pts.height*0.3,0))
	end
end
local ANNOUNCE: {[string]: string}={
	climb="The seat belt sign is now off. Enjoy the view of the coast on the left side.",
	approach="Cabin crew, please prepare for landing.",
	taxiin="Welcome! Please stay seated until we reach the gate.",
}
local function announce(st: FP.State)
	local f=folder
	local captain=if f and typeof(f:GetAttribute("CaptainName"))=="string" then f:GetAttribute("CaptainName") :: string else ""
	if st.phase=="pushback" then
		local dest=if st.dir=="out" then "Port Meridian" else "City Airport"
		Toast.show("info","This is your captain"..(if captain~="" then ", "..captain else "")..". Welcome aboard "..FP.CONFIG.airline.." flight "..st.leg.flight
			.." to "..dest..". Flight time today is about "..math.max(1,math.floor(FP.flightTime(st.dir)/60+0.5)).." minutes. Sit back and enjoy the flight.",8)
	elseif ANNOUNCE[st.phase] then
		Toast.show("info",ANNOUNCE[st.phase],5)
	end
end
local function updateRideInfo(st: FP.State,t: number)
	local info=rideInfo
	if not info then return end
	local leg=st.leg
	local route=if st.dir=="out" then "City Airport  →  Port Meridian" else "Port Meridian  →  City Airport"
	local arrive=st.legStart+leg.phases.deboarding.t0-t
	local phase=FP.PHASE_TEXT[st.phase] or st.phase
	local extra=if st.phase=="boarding" then " · departs in "..clock(st.legStart+leg.phases.pushback.t0-t) else " · arrival in "..clock(arrive)
	info.Text=leg.flight.." · "..route.."\n"..phase..extra
end

------------------------------------------------------------------------------------------------ actions
local busy=false
function Shuttle.checkIn(to: string)
	if busy then return end
	busy=true
	local ok,res=Action.call("TravelAction",{action="ticket",to=to},true)
	busy=false
	if not ok then Toast.show("error",message(res.err));return end
	ticket={flight=tostring(res.flight or ""),to=tostring(res.to or to),gate=tostring(res.gate or ""),departs=tonumber(res.departs) or 0,
		boardingStarts=tonumber(res.boardingStarts) or 0,boardingEnds=tonumber(res.boardingEnds) or 0,destination=tostring(res.destination or "")}
	openPass()
	local t=workspace:GetServerTimeNow()
	local tk=ticket :: Ticket
	local where=if tk.to=="abroad" then "gate "..tk.gate.." (airside, past security)" else "the gate"
	local paid=if typeof(res.price)=="number" and res.price>0 then " · "..Format.money(res.price).." paid, return flight included" else ""
	if t>=tk.boardingStarts then
		Toast.show("success","Checked in: "..tk.flight.." to "..tk.destination..paid..". Boarding now at "..where..".",7)
	else
		Toast.show("success","Checked in: "..tk.flight.." to "..tk.destination..paid..". Boarding starts in "..clock(tk.boardingStarts-t).." at "..where..".",7)
	end
	updatePass(t)
end
function Shuttle.board()
	if busy then return end
	busy=true
	local ok,res=Action.call("TravelAction",{action="board"},true)
	busy=false
	if ok then return end
	if res.err=="NOT_BOARDING" then
		local t=workspace:GetServerTimeNow()
		local starts=tonumber(res.boardingStarts) or t
		Toast.show("info",tostring(res.flight or "The shuttle").." is not boarding yet. Boarding starts in "..clock(starts-t)..".",5)
	else
		Toast.show("error",message(res.err))
	end
end

------------------------------------------------------------------------------------------------ frame
local accum=0
local function step(dt: number)
	local f=folder
	if not f or f:GetAttribute("Enabled")~=true then
		if plane or #crew>0 then Ground.reset();Pax.reset() end
		destroyPlane();dropCrew();return
	end
	local t=workspace:GetServerTimeNow()
	local pose,st=FP.pose(t)
	local camera=workspace.CurrentCamera
	local camPos=if camera then camera.CFrame.Position else pose.cf.Position
	local dist=(camPos-pose.cf.Position).Magnitude
	local want=if riding then "full" elseif dist<Shuttle.LOD_FULL then "full" elseif dist<Shuttle.LOD_FAR then "medium" else "none"
	if want=="none" then destroyPlane()
	elseif not plane or plane.lod~=want then buildPlane(want,pose.cf) end
	local pl=plane
	if pl then
		-- parked with the engines off: nothing moves, no BulkMoveTo at all
		if pose.engines or pl.last~=pose.cf then
			if pose.engines then fanAngle=(fanAngle+dt*(if pose.onGround and pose.speed<1 then 9 else 26))%(math.pi*2) end
			Mover.move(pl.mover,pose.cf,fanAngle)
			pl.last=pose.cf
		end
		Mover.setGear(pl.mover,pose.gearDown)
		-- collide only while standing still: never trap a player inside the moving fuselage
		local still=pose.onGround and pose.speed<0.01
		if still~=pl.colliding then
			pl.colliding=still
			for _,p in pl.solid do p.CanCollide=still end
		end
	end
	-- announcements + ride
	local prev=lastState
	if riding and prev and (prev.phase~=st.phase) then announce(st) end
	lastState=st
	if riding then openRide();updateRideCamera(pose,dt) end
	-- Port Meridian airstairs while the shuttle stands there (before the crew: their path uses the stairs)
	local atPM=(st.dir=="back" and (st.phase=="boarding" or st.phase=="doors")) or (st.dir=="out" and st.phase=="deboarding")
	setAirstairs(atPM and (camPos-FP.PM_STAND.Position).Magnitude<1500)
	updateCrew(st,pose,t,camPos)
	Ground.step(st,t,camPos,ensureClientFolder())
	Pax.step(st,pose,t,camPos,folder,ensureClientFolder(),airstairs)
	accum+=dt
	if accum>=0.25 then
		accum=0
		hideStandAircraft(t)
		updatePass(t)
		if riding then updateRideInfo(st,t) end
	end
end
Shuttle.step=step

------------------------------------------------------------------------------------------------ init
local function onLeg()
	local key=player:GetAttribute("ShuttleLeg")
	if typeof(key)=="string" and key~="" then
		riding=key
		ticket=nil
		closePass()
		rideMode="window"
		openRide()
		Toast.show("success","Welcome aboard! Find your window seat - use the View button to change the camera.",5)
	elseif riding then
		riding=nil
		closeRide()
		local state=player:GetAttribute("TravelState")
		if state=="abroad" then
			Toast.show("success","Welcome to Port Meridian! Your return flight is included - check in at the counters to fly home.",7)
		elseif state==nil then
			Toast.show("success","Welcome back to City Airport! Your car waits in the car park west of the terminal.",6)
		end
	end
end
function Shuttle.init()
	task.spawn(function()
		local f=ReplicatedStorage:WaitForChild("Shuttle",30)
		if not f or not f:IsA("Folder") then return end
		folder=f
		RunService.RenderStepped:Connect(step)
	end)
	player:GetAttributeChangedSignal("ShuttleLeg"):Connect(onLeg)
	player:GetAttributeChangedSignal("TravelState"):Connect(function()
		-- a ticket is moot once the state changes (flight, respawn, arrival)
		local state=player:GetAttribute("TravelState")
		if ticket and state~=nil and state~="flying" then ticket=nil;closePass() end
	end)
	player.CharacterAdded:Connect(function()
		if ticket and ticket.to=="home" then ticket=nil;closePass() end
		if riding then riding=nil;closeRide() end
	end)
	if player:GetAttribute("ShuttleLeg")~=nil then onLeg() end
end
return Shuttle
