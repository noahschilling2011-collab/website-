--!strict
-- GuestController (package "guests_jet", client only; Main.client calls init()): people who are not employees.
--   * Hotel guests in the guest house of every plot near the camera (BuildingPlan.hasHotel tiers): the office
--     attributes HotelGuests / HotelRooms (EmpireService, from CompanyOps) give the number of guests (one per room,
--     GuestPlan.guestCount); GuestPlan computes what each of them does today from the company clock (check-out with
--     the suitcase in the morning, breakfast, out for the day, back in the afternoon, check-in of new arrivals,
--     the lobby / window bar in the evening, bed) on a waypoint graph of the guest house (walls and furniture
--     tested). Building-local positions go through the office's CampusCFrame. A slot's day never depends on the
--     guest count; when HotelGuests changes while the guest house is watched (a hosted client team checks in / out)
--     the added guests come in from the street with their suitcases (GuestPlan.joinActors) and the removed ones
--     finish what they are doing and check out (GuestPlan.leaveActors) - nobody else moves, nobody pops in or out.
--   * Terminal passengers in City Airport and Port Meridian while the camera is in a terminal (GuestPlan.TERMINALS):
--     departures with suitcases through check-in, security, the gate A1 seats and the jet bridge (City Airport) /
--     the benches, the apron door and the airstair (Port Meridian), and arrivals with baggage trolleys, all timed to
--     the real shuttle timetable (FlightPlan). City Airport also has CityLifeController's 30 ambient walkers.
--   * Figures: cheap 7-8 part people in CityLifeController's style (skin / hair / clothes palettes, business
--     attire, a shirt front), eyes when near, luggage parts (rolling suitcase, backpack, trolley with bags) only
--     while carried. Procedural walk / sit / stand poses (no animation assets). One workspace:BulkMoveTo per step
--     (<= 30 Hz; figures beyond FAR_LOD at 10 Hz without limb swing). Caps: HOTEL_CAP guests per plot on at most
--     MAX_PLOTS plots, TERMINAL_CAP passengers; everything is unparented when no plot / terminal is near. Nothing
--     is written to the server, no network traffic; deterministic (GuestPlan seeds, server clock).
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local GP=require(ReplicatedStorage.Shared.GuestPlan)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Ops=require(ReplicatedStorage.Shared.CompanyOps)

local Guests={}
Guests.HOTEL_NEAR=240 -- guest-house centre within this distance of the camera
Guests.MAX_PLOTS=2
Guests.HOTEL_CAP=GP.HOTEL_CAP
Guests.TERMINAL_CAP=40
Guests.FAR_LOD=150
Guests.EYES_NEAR=60
Guests.STEP=1/30
Guests.SCAN=0.5
Guests.STALE=5 -- a plot not scanned for this many seconds: a changed guest count is taken as is (no arrival / departure walks)
local FAR_STEP=0.1
local STRIDE=3.2
local HOTEL_CENTRE=Vector3.new(-120,8,124)

type Figure={id: number,model: Model,parts: {BasePart},eyes: {BasePart},shirt: BasePart,case: {BasePart},bag: BasePart,trolley: {BasePart},
	business: boolean,carry: string?,near: boolean?,eyesOn: boolean,actor: string?,lastAt: number,pos: Vector3}
type Active={key: string,actor: GP.Actor,frame: CFrame,toWorld: CFrame?,timeOf: (number) -> number,fig: Figure?}
local pool: {Figure}={}
local free: {Figure}={}
local active: {[string]: Active}={}
local folder: Model?=nil
type PlotRec={office: Instance,cf: CFrame,seed: number,n: number,day: number,list: {{key: string,actor: GP.Actor}},
	override: {[number]: {day: number,actors: {GP.Actor}}},seen: number,dirty: boolean}
local plots: {PlotRec}={}
local plotCache: {[number]: PlotRec}={} -- by seed: today's actors (rebuilt when the day or the guest count changes)
local terminal: string?=nil
local termActors: {GP.Actor}={}
local acc,scanAcc=0,0
local stepConn: RBXScriptConnection?=nil
local stats={plots=0,guests=0,passengers=0,figures=0,parts=0,terminal="none",lastStepMs=0}

------------------------------------------------------------------------------------------------ figures
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
local CASES={Color3.fromRGB(40,42,46),Color3.fromRGB(150,30,38),Color3.fromRGB(30,70,130),Color3.fromRGB(196,168,112),Color3.fromRGB(70,110,96),Color3.fromRGB(220,220,214)}
local EYE=Color3.fromRGB(28,26,30)
local function pick<T>(list: {T},h: number): T return list[(h%#list)+1] end
local function part(parent: Instance?,name: string,size: Vector3,color: Color3,material: Enum.Material?,shape: Enum.PartType?): Part
	local p=Instance.new("Part");p.Name=name;p.Size=size;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
	p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
	p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
	if shape then p.Shape=shape end
	p.CFrame=CFrame.new(0,-500,0)
	p.Parent=parent
	return p
end
local function newFigure(): Figure
	local m=Instance.new("Model");m.Name="Guest"
	local white=Color3.new(1,1,1)
	local parts: {BasePart}={
		part(m,"Torso",Vector3.new(2,2,1),white,Enum.Material.Fabric),
		part(m,"Head",Vector3.new(1.25,1.25,1.25),white,Enum.Material.SmoothPlastic,Enum.PartType.Ball),
		part(m,"Hair",Vector3.new(1.34,1.34,1.34),white,Enum.Material.SmoothPlastic,Enum.PartType.Ball),
		part(m,"LeftArm",Vector3.new(.9,1.9,.9),white,Enum.Material.Fabric),
		part(m,"RightArm",Vector3.new(.9,1.9,.9),white,Enum.Material.Fabric),
		part(m,"LeftLeg",Vector3.new(.95,2,.95),white,Enum.Material.Fabric),
		part(m,"RightLeg",Vector3.new(.95,2,.95),white,Enum.Material.Fabric),
	}
	local shirt=part(nil,"Shirt",Vector3.new(.7,1.5,.06),white,Enum.Material.Fabric)
	local eyes: {BasePart}={part(nil,"Eye",Vector3.new(.15,.18,.1),EYE),part(nil,"Eye",Vector3.new(.15,.18,.1),EYE)}
	local case: {BasePart}={part(nil,"Suitcase",Vector3.new(1.3,1.9,.75),white,Enum.Material.SmoothPlastic),part(nil,"SuitcaseHandle",Vector3.new(.12,1.7,.12),Color3.fromRGB(60,62,66),Enum.Material.Metal)}
	local bag=part(nil,"Backpack",Vector3.new(1.3,1.5,.6),white,Enum.Material.Fabric)
	local metal=Color3.fromRGB(176,180,186)
	local trolley: {BasePart}={
		part(nil,"TrolleyBase",Vector3.new(2.2,.2,3.0),metal,Enum.Material.Metal),
		part(nil,"TrolleyBar",Vector3.new(2.4,.16,.16),Color3.fromRGB(40,42,46),Enum.Material.Metal),
		part(nil,"TrolleyPost",Vector3.new(.14,1.9,.14),metal,Enum.Material.Metal),
		part(nil,"TrolleyPost",Vector3.new(.14,1.9,.14),metal,Enum.Material.Metal),
		part(nil,"TrolleyBag",Vector3.new(1.9,.95,1.3),white,Enum.Material.SmoothPlastic),
		part(nil,"TrolleyBag",Vector3.new(1.4,.8,1.1),white,Enum.Material.Fabric),
	}
	local f: Figure={id=#pool+1,model=m,parts=parts,eyes=eyes,shirt=shirt,case=case,bag=bag,trolley=trolley,business=false,carry=nil,near=nil,eyesOn=false,
		actor=nil,lastAt=0,pos=Vector3.zero}
	table.insert(pool,f)
	return f
end
-- the look of an actor (seeded): business attire for ~40 %
local function style(f: Figure,seed: number)
	local h=seed
	local business=(h%5)<2
	local top=if business then pick(SUIT,h) else pick(TOPS,h)
	local legs=if business then (if h%3==0 then top else pick(SUIT,math.floor(h/7))) else pick(LEGS,math.floor(h/7))
	local skin=pick(SKIN,math.floor(h/53))
	local sleeves=if business or h%2==0 then top else skin
	local ps=f.parts
	ps[1].Color=top;ps[2].Color=skin;ps[3].Color=pick(HAIR,math.floor(h/331))
	ps[4].Color=sleeves;ps[5].Color=sleeves;ps[6].Color=legs;ps[7].Color=legs
	f.shirt.Color=pick(SHIRT,math.floor(h/11))
	f.shirt.Parent=if business then f.model else nil
	f.business=business
	local caseC=pick(CASES,math.floor(h/17))
	f.case[1].Color=caseC;f.bag.Color=pick(CASES,math.floor(h/29)+2)
	f.trolley[5].Color=caseC;f.trolley[6].Color=pick(CASES,math.floor(h/37)+1)
end
local function setCarry(f: Figure,carry: string?)
	if f.carry==carry then return end
	f.carry=carry
	for _,p in f.case do p.Parent=if carry=="suitcase" then f.model else nil end
	f.bag.Parent=if carry=="bag" then f.model else nil
	for _,p in f.trolley do p.Parent=if carry=="trolley" then f.model else nil end
end
local SHADOW: {[string]: boolean}={Torso=true,LeftLeg=true,RightLeg=true}
local function setNear(f: Figure,near: boolean,eyes: boolean)
	if f.near~=near then
		f.near=near
		for _,p in f.parts do if SHADOW[p.Name] then p.CastShadow=near end end
	end
	if f.eyesOn~=eyes then
		f.eyesOn=eyes
		for _,e in f.eyes do e.Parent=if eyes then f.model else nil end
	end
end
local function acquire(key: string,seed: number): Figure
	local f=table.remove(free) or newFigure()
	f.actor=key;f.carry="?";setCarry(f,nil);f.near=nil;f.eyesOn=true;setNear(f,false,false)
	style(f,seed)
	f.model.Parent=folder
	return f
end
local function release(f: Figure)
	f.actor=nil
	f.model.Parent=nil
	table.insert(free,f)
end

------------------------------------------------------------------------------------------------ poses
local batchParts: {BasePart}={}
local batchFrames: {CFrame}={}
local function push(p: BasePart,cf: CFrame) table.insert(batchParts,p);table.insert(batchFrames,cf) end
local EYE_L,EYE_R=CFrame.new(-.22,.03,-.57),CFrame.new(.22,.03,-.57)
local A=CFrame.Angles
-- One figure: root = the feet frame (facing), mode walk / sit / stand, distance walked (limb phase), hint pose.
local function pose(f: Figure,root: CFrame,mode: string,hint: string?,walked: number,now: number,far: boolean)
	local ps=f.parts
	local carry=f.carry
	if mode=="sit" then
		local torso=root*CFrame.new(0,2.8,.15)
		local armX=if hint=="eat" then (if math.sin(now*1.3+f.id)>0.4 then 1.55 else .9) else .45
		push(ps[1],torso);local head=root*CFrame.new(0,4.45,.15);push(ps[2],head);push(ps[3],head*CFrame.new(0,.17,.1))
		push(ps[4],root*CFrame.new(-1.45,3.6,.1)*A(.45,0,0)*CFrame.new(0,-.85,0))
		push(ps[5],root*CFrame.new(1.45,3.6,.1)*A(armX,0,0)*CFrame.new(0,-.85,0))
		push(ps[6],root*CFrame.new(-.5,2.3,-.3)*A(math.pi/2,0,0)*CFrame.new(0,-1,0))
		push(ps[7],root*CFrame.new(.5,2.3,-.3)*A(math.pi/2,0,0)*CFrame.new(0,-1,0))
		if f.business then push(f.shirt,torso*CFrame.new(0,.15,-.53)) end
		if f.eyesOn then push(f.eyes[1],head*EYE_L);push(f.eyes[2],head*EYE_R) end
		if carry=="bag" then push(f.bag,root*CFrame.new(1.75,.75,-.2)) end
		if carry=="suitcase" then push(f.case[1],root*CFrame.new(1.8,.95,0));push(f.case[2],root*CFrame.new(1.8,2.6,0)) end
		return
	end
	local swing,bob=0,0
	if mode=="walk" and not far then
		local ph=walked/STRIDE*math.pi*2
		swing=.55*math.sin(ph);bob=math.abs(math.cos(ph))*.09
	end
	local r=root
	if mode=="stand" and (hint=="wait" or hint=="relax") then r=r*A(0,math.sin(now*.6+f.id)*.15,0) end
	local torso=r*CFrame.new(0,3+bob,0)
	push(ps[1],torso)
	local head=r*CFrame.new(0,4.65+bob,0)
	push(ps[2],head);push(ps[3],head*CFrame.new(0,.17,.1))
	local lx,rx=-swing*.8,swing*.8
	if mode=="stand" then
		if hint=="checkin" or hint=="checkout" then rx=.9+.15*math.sin(now*2+f.id) end
		if hint=="divest" or hint=="recompose" or hint=="pour" then lx,rx=1.1,1.2+.1*math.sin(now*3) end
	end
	if carry=="suitcase" then rx=if mode=="walk" then -.35 else -.1 end
	if carry=="trolley" then lx,rx=1.25,1.25 end
	local la=r*CFrame.new(-1.45,3.85+bob,0)*A(lx,0,0)*CFrame.new(0,-.9,0)
	local ra=r*CFrame.new(1.45,3.85+bob,0)*A(rx,0,0)*CFrame.new(0,-.9,0)
	push(ps[4],la);push(ps[5],ra)
	push(ps[6],r*CFrame.new(-.5,2,0)*A(swing,0,0)*CFrame.new(0,-1,0))
	push(ps[7],r*CFrame.new(.5,2,0)*A(-swing,0,0)*CFrame.new(0,-1,0))
	if f.business then push(f.shirt,torso*CFrame.new(0,.15,-.53)) end
	if f.eyesOn then push(f.eyes[1],head*EYE_L);push(f.eyes[2],head*EYE_R) end
	if carry=="suitcase" then
		-- a rolling case behind the right hand (tilted while pulled, upright while standing)
		local caseCf=if mode=="walk" then r*CFrame.new(1.55,1.2,1.25)*A(-.42,0,0) else r*CFrame.new(1.7,.95,.35)
		push(f.case[1],caseCf);push(f.case[2],caseCf*CFrame.new(0,1.75,-.25))
	elseif carry=="bag" then
		push(f.bag,torso*CFrame.new(0,.1,.8))
	elseif carry=="trolley" then
		local base=r*CFrame.new(0,.75,-3.3)
		local tp=f.trolley
		push(tp[1],base);push(tp[2],r*CFrame.new(0,2.95,-1.55));push(tp[3],r*CFrame.new(-1.1,1.9,-1.8));push(tp[4],r*CFrame.new(1.1,1.9,-1.8))
		push(tp[5],base*CFrame.new(0,.58,.1));push(tp[6],base*CFrame.new(0,1.45,.2))
	end
end

------------------------------------------------------------------------------------------------ sources
local function ensureFolder(): Model
	local f=folder
	if f and f.Parent then return f end
	local m=Instance.new("Model");m.Name="GuestLife";m.Parent=workspace
	folder=m
	for _,fig in pool do if fig.actor then fig.model.Parent=m end end
	return m
end
local function num(v: any): number? return if typeof(v)=="number" and v==v then v else nil end
-- guest houses near the camera (nearest first, at most MAX_PLOTS)
local function findPlots(camPos: Vector3,now: number)
	table.clear(plots)
	local root=workspace:FindFirstChild("Plots")
	if not root then return end
	local cands={}
	for i,plot in root:GetChildren() do
		local office=plot:FindFirstChild("Office")
		if not office then continue end
		local cf=office:GetAttribute("CampusCFrame")
		local tier=num(office:GetAttribute("OfficeTier"))
		if typeof(cf)~="CFrame" or not tier or not Plan.hasHotel(tier) then continue end
		local n=GP.guestCount(office:GetAttribute("HotelGuests"),office:GetAttribute("HotelRooms"))
		if n<=0 then continue end
		local d=((cf :: CFrame)*HOTEL_CENTRE-camPos).Magnitude
		if d<=Guests.HOTEL_NEAR then
			local owner=num(office:GetAttribute("OwnerUserId"))
			table.insert(cands,{office=office,cf=cf :: CFrame,seed=if owner then owner else i,n=n,d=d})
		end
	end
	table.sort(cands,function(a,b) return a.d<b.d end)
	for i=1,math.min(#cands,Guests.MAX_PLOTS) do
		local c=cands[i]
		local n=math.min(c.n,Guests.HOTEL_CAP)
		local rec: PlotRec?=plotCache[c.seed]
		if not rec then
			local fresh: PlotRec={office=c.office,cf=c.cf,seed=c.seed,n=n,day=-1,list={},override={},seen=now,dirty=true}
			plotCache[c.seed]=fresh
			rec=fresh
		end
		local r=rec :: PlotRec
		if r.n~=n then
			-- live change of the guest count: added slots arrive from the street, removed ones check out
			local d,s=GP.dayOf(now)
			if now-r.seen<=Guests.STALE then
				if n>r.n then
					for g=r.n+1,n do r.override[g]={day=d,actors=GP.joinActors(r.seed,g,d,s,g-r.n)} end
				else
					for g=n+1,r.n do
						local o=r.override[g]
						r.override[g]={day=d,actors=GP.leaveActors(r.seed,g,d,s,if o and o.day==d then o.actors else nil)}
					end
				end
			else
				table.clear(r.override)
			end
			r.n=n;r.dirty=true
		end
		r.seen=now
		r.office=c.office;r.cf=c.cf
		table.insert(plots,r)
	end
end
local function dayTime(t: number): number local _,s=GP.dayOf(t);return s end
local function absTime(t: number): number return t end
local function scan(camPos: Vector3,now: number)
	findPlots(camPos,now)
	terminal=GP.terminalAt(camPos)
	termActors=if terminal then GP.terminalActors(terminal,now) else {}
	-- passengers nearest the camera first (cap)
	if #termActors>Guests.TERMINAL_CAP then
		local scored={}
		for _,a in termActors do
			local mode,cf=GP.sample(a,now)
			local d=if cf then (cf.Position-camPos).Magnitude else 1e6
			if mode=="hidden" then d+=1e5 end
			table.insert(scored,{a=a,d=d})
		end
		table.sort(scored,function(x,y) return x.d<y.d end)
		local keep: {GP.Actor}={}
		for i=1,Guests.TERMINAL_CAP do table.insert(keep,scored[i].a) end
		termActors=keep
	end
	stats.plots=#plots;stats.terminal=terminal or "none"
end
Guests.scan=scan

------------------------------------------------------------------------------------------------ step
local wanted: {[string]: boolean}={}
local function want(key: string,actor: GP.Actor,toWorld: CFrame?,timeOf: (number) -> number)
	wanted[key]=true
	local a=active[key]
	if not a then
		active[key]={key=key,actor=actor,frame=CFrame.new(),toWorld=toWorld,timeOf=timeOf,fig=nil}
	else
		a.actor=actor;a.toWorld=toWorld;a.timeOf=timeOf
	end
end
local function step(dt: number,now: number,camPos: Vector3): ({BasePart},{CFrame})
	table.clear(batchParts);table.clear(batchFrames);table.clear(wanted)
	local t0=os.clock()
	local d=GP.dayOf(now)
	for _,pl in plots do
		if pl.day~=d or pl.dirty then
			pl.day=d;pl.dirty=false;table.clear(pl.list)
			-- today's overrides (arrivals / departures after a live change) replace the slot's plan; older ones expire
			local top=pl.n
			for g,o in pl.override do if o.day~=d then pl.override[g]=nil elseif g>top then top=g end end
			for g=1,top do
				local o=pl.override[g]
				local list: {GP.Actor}=if o then o.actors elseif g<=pl.n then GP.slotDay(pl.seed,g,d,pl.n) else {}
				for _,actor in list do table.insert(pl.list,{key=pl.seed..":"..actor.id,actor=actor}) end
			end
		end
		for _,e in pl.list do want(e.key,e.actor,pl.cf,dayTime) end
	end
	for _,actor in termActors do want("t:"..actor.id,actor,nil,absTime) end
	local guests,pax=0,0
	for key,a in active do
		if not wanted[key] then
			if a.fig then release(a.fig) end
			active[key]=nil
			continue
		end
		local mode,cf,hint,carry,walked=GP.sample(a.actor,a.timeOf(now))
		if mode=="hidden" or not cf then
			local old=a.fig
			if old then release(old);a.fig=nil end
			continue
		end
		local world=if a.toWorld then (a.toWorld :: CFrame)*cf else cf
		local fig: Figure=a.fig or acquire(key,a.actor.seed)
		if a.fig~=fig then a.fig=fig;fig.lastAt=0 end
		local dist=(world.Position-camPos).Magnitude
		local far=dist>Guests.FAR_LOD
		if far and now-fig.lastAt<FAR_STEP then
			if a.toWorld then guests+=1 else pax+=1 end
			continue
		end
		fig.lastAt=now
		setCarry(fig,carry)
		setNear(fig,not far,dist<Guests.EYES_NEAR)
		pose(fig,world,mode,hint,walked,now,far)
		fig.pos=world.Position
		if a.toWorld then guests+=1 else pax+=1 end
	end
	stats.guests=guests;stats.passengers=pax;stats.figures=#pool;stats.parts=#batchParts
	stats.lastStepMs=(os.clock()-t0)*1000
	return batchParts,batchFrames
end
Guests.step=step
-- one update (scan every SCAN s, step at <= 30 Hz); returns whether anything is active
function Guests.update(camPos: Vector3,dt: number,now: number): boolean
	scanAcc+=dt
	if scanAcc>=Guests.SCAN then scanAcc=0;scan(camPos,now) end
	if #plots==0 and not terminal then
		if next(active) then
			for key,a in active do if a.fig then release(a.fig) end;active[key]=nil end
		end
		if folder and folder.Parent then folder.Parent=nil end
		stats.guests=0;stats.passengers=0
		return false
	end
	local f=ensureFolder()
	if not f.Parent then f.Parent=workspace end
	acc+=dt
	if acc<Guests.STEP then return true end
	acc=0
	local parts,frames=step(dt,now,camPos)
	if #parts>0 then workspace:BulkMoveTo(parts,frames,Enum.BulkMoveMode.FireCFrameChanged) end
	return true
end
function Guests.stats(): typeof(stats) return stats end
function Guests.active(): {[string]: Active} return active end
function Guests.pool(): {Figure} return pool end
function Guests.plots(): {PlotRec} return plots end
function Guests.folder(): Model? return folder end
function Guests.dayTime(t: number): number return dayTime(t) end
Guests.hourOf=function(t: number): number return Ops.hour(t) end

function Guests.init()
	if stepConn then return end
	stepConn=RunService.RenderStepped:Connect(function(dt: number)
		local camera=workspace.CurrentCamera
		if not camera then return end
		Guests.update(camera.CFrame.Position,dt,workspace:GetServerTimeNow())
	end)
end
return Guests
