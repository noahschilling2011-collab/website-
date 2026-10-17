--!strict
-- ShuttleGround (package "flight", client only; stepped by ShuttleController): ground handling around the
-- shuttle and the live flight information. Everything is local - nothing replicates, the server writes nothing.
--   * Home stand A<shuttleStand>: the airport package's pushback tug (WorldCity/Airport/Apron/GroundVehicles/
--     Pushback nearest the stand) pushes the shuttle back, pulls aside and drives home (FlightPlan.tugFrame);
--     the jet bridge (JetBridge_A<n>) retracts while the doors close and docks again after the arrival, so it
--     never touches the moving aircraft and stands retracted while the shuttle is away (FlightPlan.bridgeU /
--     bridgeFrame). These are server parts moved locally with workspace:BulkMoveTo; every part's original
--     frame is cached once, and parts that stream in later are cached at rest (the server never moves them).
--   * Port Meridian apron stand (FlightPlan.PM_APRON): a local pushback tug (5 parts) at the nose, driven by the
--     same FlightPlan.tugFrame.
--   * Flight information: every part tagged "FlightInfoBoard" (airport package: attribute Board = departures |
--     arrivals | monitor | gate | gatedoor | belt; labels named "FlightText") within BOARD_RANGE of the camera
--     gets live rows once per second; Port Meridian's boarding gate gets a small studs-sized board.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CollectionService=game:GetService("CollectionService")
local CityPlan=require(ReplicatedStorage.Shared.Config.CityPlan)
local FP=require(ReplicatedStorage.Shared.FlightPlan)
local Aircraft=require(ReplicatedStorage.Shared.AircraftModel)
local Ground={}
Ground.BOARD_RANGE=150
Ground.NEAR=700 -- the home tug / jet bridge are only animated within this distance of the camera
local player=Players.LocalPlayer

local function clock(seconds: number): string
	seconds=math.max(0,math.floor(seconds))
	return string.format("%d:%02d",seconds//60,seconds%60)
end
Ground.clock=clock

------------------------------------------------------------------------------------------------ status text
-- Status of the next departure in direction dir at time t: (status, time left as m:ss).
function Ground.statusText(dir: string,t: number): (string,string)
	local st=FP.at(t)
	local leg=FP.leg(dir)
	if st.dir==dir and st.phase=="boarding" then
		return "BOARDING",clock(st.legStart+leg.phases.pushback.t0-t)
	end
	if st.dir==dir and st.phase=="doors" then return "GATE CLOSED",clock(st.legStart+leg.phases.pushback.t0-t) end
	if st.dir==dir and st.tau<leg.phases.deboarding.t0 then
		local _,_,dep=FP.nextLeg(dir,t+1)
		return "DEPARTED",clock(dep-t)
	end
	local _,start,dep=FP.nextLeg(dir,t)
	return if start-t<60 then "BOARDING SOON" else "ON TIME",clock(dep-t)
end
-- Arrival remark of the return flight at City Airport (or the out flight at Port Meridian).
function Ground.arrivalText(dir: string,t: number): string
	local st=FP.at(t)
	local leg=FP.leg(dir)
	if st.dir==dir then
		if st.phase=="deboarding" then return "ARRIVED" end
		if st.phase=="landing" or st.phase=="taxiin" then return "LANDED" end
		if st.tau>=leg.phases.pushback.t0 then return "EXPECTED "..clock(st.legStart+leg.phases.deboarding.t0-t) end
	end
	local _,start=FP.nextLeg(dir,t)
	return "SCHEDULED "..clock(start+leg.phases.deboarding.t0-t)
end

------------------------------------------------------------------------------------------------ server parts moved locally
type Moved={model: Instance?,parts: {BasePart},orig: {CFrame},count: number,applied: number,ref: CFrame?,extra: {[string]: any}}
local function newMoved(): Moved return {model=nil,parts={},orig={},count=0,applied=-1,ref=nil,extra={}} end
local origOf: {[BasePart]: CFrame}=setmetatable({},{__mode="k"}) :: any
local function collect(m: Moved,model: Instance)
	m.model=model
	table.clear(m.parts);table.clear(m.orig)
	for _,d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local o=origOf[d]
			if not o then o=d.CFrame;origOf[d]=o end
			table.insert(m.parts,d);table.insert(m.orig,o)
		end
	end
	m.count=#m.parts
	-- all parts where the server put them: the rest state is applied already; else re-apply the current state
	local atRest=true
	for i,p in m.parts do if p.CFrame~=m.orig[i] then atRest=false;break end end
	m.applied=if atRest then 0 else -1
end
local function stale(m: Moved): boolean
	local model=m.model
	if not model or not model.Parent then return true end
	for _,p in m.parts do if not p.Parent then return true end end
	return false
end
local function partsCount(model: Instance): number
	local n=0
	for _,d in model:GetDescendants() do if d:IsA("BasePart") then n+=1 end end
	return n
end
local function apron(): Instance?
	local world=workspace:FindFirstChild("WorldCity")
	local airport=if world then world:FindFirstChild("Airport") else nil
	return if airport then airport:FindFirstChild("Apron") else nil
end
local homeTug=newMoved()
local bridge=newMoved()
local nextSearch=0
local function search(t: number)
	if t<nextSearch then return end
	nextSearch=t+3
	local ap=apron()
	if not ap then return end
	-- the stand's pushback tug: the Pushback group whose body stands on the stand's centre line
	if stale(homeTug) or (homeTug.model and partsCount(homeTug.model)~=homeTug.count) then
		homeTug.model=nil
		local gse=ap:FindFirstChild("GroundVehicles")
		if gse then
			for _,v in gse:GetChildren() do
				local body=if v.Name=="Pushback" then v:FindFirstChild("Body") else nil
				if body and body:IsA("BasePart") and math.abs(body.Position.X-FP.HOME_STAND.X)<6 then
					collect(homeTug,v)
					homeTug.ref=origOf[body]
					break
				end
			end
		end
	end
	if stale(bridge) or (bridge.model and partsCount(bridge.model)~=bridge.count) then
		bridge.model=nil
		local jb=ap:FindFirstChild("JetBridges")
		local m=if jb then jb:FindFirstChild("JetBridge_A"..CityPlan.AIRPORT.shuttleStand) else nil
		local cab=if m then m:FindFirstChild("CabFloor") else nil
		local td=if m then m:GetAttribute("TerminalDoor") else nil
		if m and cab and cab:IsA("BasePart") and typeof(td)=="Vector3" then
			collect(bridge,m)
			local pivot,axis,away=FP.bridgeAxes(td,origOf[cab])
			bridge.extra.pivot=pivot;bridge.extra.axis=axis;bridge.extra.away=away
			local inner: {boolean}={}
			for i,p in bridge.parts do inner[i]=FP.bridgeInner(p.Name) end
			bridge.extra.inner=inner
		end
	end
end
local function moveTo(m: Moved,cfs: {CFrame})
	if #m.parts>0 then workspace:BulkMoveTo(m.parts,cfs,Enum.BulkMoveMode.FireCFrameChanged) end
end
local function stepHomeTug(st: FP.State)
	local ref=homeTug.ref
	if not homeTug.model or not ref then return end
	local cf=if st.dir=="out" then FP.tugFrame(st,ref) else ref -- the home stand's tug only pushes on the out leg
	local key=if cf==ref then 0 else 1
	if key==0 and homeTug.applied==0 then return end -- parked: nothing to do
	homeTug.applied=key
	local rel=ref:Inverse()
	local cfs: {CFrame}=table.create(#homeTug.parts)
	for i,o in homeTug.orig do cfs[i]=cf*(rel*o) end
	moveTo(homeTug,cfs)
end
local function stepBridge(st: FP.State)
	if not bridge.model then return end
	local u=FP.bridgeU(st)
	if bridge.applied>=0 and math.abs(u-bridge.applied)<0.002 then return end
	bridge.applied=u
	local ex=bridge.extra
	local inner: {boolean}=ex.inner
	local cfs: {CFrame}=table.create(#bridge.parts)
	for i,o in bridge.orig do cfs[i]=FP.bridgeFrame(o,inner[i],u,ex.pivot,ex.axis,ex.away) end
	moveTo(bridge,cfs)
end

------------------------------------------------------------------------------------------------ Port Meridian tug (local)
type LocalTug={model: Model,parts: {BasePart},rel: {CFrame},parked: CFrame,last: CFrame?}
local pmTug: LocalTug?=nil
local function pmTugParked(): CFrame
	local kind=FP.CONFIG.kind;local scale=FP.CONFIG.scale
	local ngz=Aircraft.points(kind,scale).noseGearZ
	return FP.PM_STAND*CFrame.new(0,0,ngz-9)*CFrame.Angles(0,math.pi,0) -- 9 studs ahead of the nose gear, facing it
end
local function buildPmTug(parent: Instance): LocalTug
	local m=Instance.new("Model");m.Name="ShuttleTug"
	local parked=pmTugParked()
	local parts: {BasePart}={};local rel: {CFrame}={}
	local function box(name: string,size: Vector3,c: Vector3,color: Color3,material: Enum.Material?,cyl: boolean?)
		local p=Instance.new("Part");p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
		if cyl then p.Shape=Enum.PartType.Cylinder end
		p.Size=size;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
		local r=CFrame.new(c)
		p.CFrame=parked*r;p.Parent=m
		table.insert(parts,p);table.insert(rel,r)
	end
	-- the airport package's Pushback shape: body, cab, tow bar, two axles (frame: -Z forward, origin on the ground)
	box("Body",Vector3.new(7.2,2,10),Vector3.new(0,1.6,0),Color3.fromRGB(236,184,40))
	box("Cab",Vector3.new(3,1.8,3),Vector3.new(-1.9,3.5,2.5),Color3.fromRGB(40,46,52),Enum.Material.Glass)
	box("TowBar",Vector3.new(0.6,0.4,7),Vector3.new(0,1.1,-8.5),Color3.fromRGB(60,60,60),Enum.Material.Metal)
	for _,z in {-3.2,3.2} do box("Wheels",Vector3.new(7.4,2,2),Vector3.new(0,1,z),Color3.fromRGB(28,30,32),Enum.Material.Rubber,true) end
	m.Parent=parent
	return {model=m,parts=parts,rel=rel,parked=parked,last=nil}
end
local function stepPmTug(st: FP.State,camPos: Vector3,parent: Instance)
	local near=FP.PM_APRON and (camPos-FP.PM_STAND.Position).Magnitude<1500
	if not near then
		if pmTug then pmTug.model:Destroy();pmTug=nil end
		return
	end
	local tug=pmTug or buildPmTug(parent)
	pmTug=tug
	local cf=if st.dir=="back" then FP.tugFrame(st,tug.parked) else tug.parked
	if tug.last==cf then return end
	tug.last=cf
	local cfs: {CFrame}=table.create(#tug.parts)
	for i,r in tug.rel do
		-- the cylinder axles are built along local X (Part cylinder axis): rel already carries no rotation
		cfs[i]=cf*r
	end
	workspace:BulkMoveTo(tug.parts,cfs,Enum.BulkMoveMode.FireCFrameChanged)
end
function Ground.pmTug(): Model? return if pmTug then pmTug.model else nil end

------------------------------------------------------------------------------------------------ flight information
local OUT=FP.CONFIG.flights.out
local BACK=FP.CONFIG.flights.back
local GATE="A"..CityPlan.AIRPORT.shuttleStand
local function pad(s: string,n: number): string return s..string.rep(" ",math.max(1,n-#s)) end
function Ground.boardText(kind: string,t: number): string?
	local status,left=Ground.statusText("out",t)
	local remark=status.." "..left
	if kind=="departures" then
		return "DEPARTURES\n"..pad("FLIGHT",9)..pad("DESTINATION",17)..pad("GATE",6).."REMARK\n"
			..pad(OUT,9)..pad("PORT MERIDIAN",17)..pad(GATE,6)..remark.."\n\nCHECK-IN A – D  ·  SECURITY LANES 1 – 3\nBOARDING AT GATE "..GATE
	elseif kind=="arrivals" then
		return "ARRIVALS\n"..pad("FLIGHT",9)..pad("FROM",17)..pad("BELT",6).."REMARK\n"
			..pad(BACK,9)..pad("PORT MERIDIAN",17)..pad("1",6)..Ground.arrivalText("back",t).."\n\nTAXI  ·  BUS  ·  CAR PARK WEST"
	elseif kind=="monitor" then
		return "DEPARTURES\n"..OUT.."  "..GATE.."  PORT MERIDIAN\n"..remark
	elseif kind=="gate" then
		return GATE.."   "..OUT.."  PORT MERIDIAN\n"..status.."  ·  DEPARTS IN "..left
	elseif kind=="gatedoor" then
		return GATE.."  ·  "..OUT.."  ·  "..(if status=="BOARDING" then "BOARDING" elseif status=="GATE CLOSED" then "CLOSED" else left)
	elseif kind=="belt" then
		local st=FP.at(t)
		local arrived=st.dir=="back" and st.phase=="deboarding" or (st.dir=="out" and st.tau<60)
		return "BELT 1  ·  "..BACK.."  PORT MERIDIAN\n"..(if arrived then "BAGGAGE ON BELT" else Ground.arrivalText("back",t))
	end
	return nil
end
local function writeBoards(t: number,camPos: Vector3)
	for _,p in CollectionService:GetTagged("FlightInfoBoard") do
		if not p:IsA("BasePart") or (p.Position-camPos).Magnitude>Ground.BOARD_RANGE then continue end
		local kind=p:GetAttribute("Board")
		local text=if typeof(kind)=="string" then Ground.boardText(kind,t) else nil
		if not text then continue end
		for _,d in p:GetDescendants() do
			if d:IsA("TextLabel") and d.Name=="FlightText" and d.Text~=text then d.Text=text end
		end
	end
end
-- Port Meridian's boarding gate: a board sized in studs (BillboardGui scale) above the board prompt.
local pmBoard: BillboardGui?=nil
local function writePmBoard(t: number)
	local gates=workspace:FindFirstChild("ShuttleGates")
	local part=if gates then gates:FindFirstChild("GateBoardAbroad") else nil
	local pg=player and player:FindFirstChild("PlayerGui")
	if not part or not part:IsA("BasePart") or not pg then if pmBoard then pmBoard.Enabled=false end return end
	local gui=pmBoard
	if not gui or not gui.Parent then
		local g=Instance.new("BillboardGui");g.Name="ShuttleGateBoard";g.Size=UDim2.fromScale(7,2.1);g.StudsOffsetWorldSpace=Vector3.new(0,5.5,0)
		g.MaxDistance=120;g.LightInfluence=0;g.ResetOnSpawn=false
		local bg=Instance.new("Frame");bg.Size=UDim2.fromScale(1,1);bg.BackgroundColor3=Color3.fromRGB(18,24,36);bg.BackgroundTransparency=0.1;bg.BorderSizePixel=0;bg.Parent=g
		local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0.08,0);c.Parent=bg
		local l=Instance.new("TextLabel");l.Name="Text";l.BackgroundTransparency=1;l.Size=UDim2.fromScale(0.94,0.86);l.Position=UDim2.fromScale(0.03,0.07)
		l.Font=Enum.Font.RobotoMono;l.TextScaled=true;l.TextColor3=Color3.fromRGB(250,206,80);l.TextXAlignment=Enum.TextXAlignment.Left;l.Parent=bg
		g.Parent=pg
		gui=g;pmBoard=g
	end
	local g=gui :: BillboardGui
	g.Adornee=part;g.Enabled=true
	local status,left=Ground.statusText("back",t)
	local l=g:FindFirstChild("Text",true)
	if l and l:IsA("TextLabel") then l.Text=BACK.."  CITY AIRPORT\n"..status.."\nDEPARTS IN "..left end
end
function Ground.pmBoard(): BillboardGui? return pmBoard end

------------------------------------------------------------------------------------------------ step
local boardAt=0
function Ground.step(st: FP.State,t: number,camPos: Vector3,parent: Instance)
	search(t)
	if (camPos-FP.HOME_STAND.Position).Magnitude<Ground.NEAR then
		stepHomeTug(st)
		stepBridge(st)
	end
	stepPmTug(st,camPos,parent)
	if t>=boardAt then
		boardAt=t+1
		writeBoards(t,camPos)
		writePmBoard(t)
	end
end
-- Shuttle off: everything back where the server put it.
function Ground.reset()
	for _,m in {homeTug,bridge} do
		if m.model and m.applied~=0 and #m.parts>0 then moveTo(m,m.orig) end
		m.applied=-1
	end
	if pmTug then pmTug.model:Destroy();pmTug=nil end
	if pmBoard then pmBoard.Enabled=false end
end
function Ground.homeTugParts(): {BasePart} return homeTug.parts end
function Ground.bridgeParts(): {BasePart} return bridge.parts end
return Ground
