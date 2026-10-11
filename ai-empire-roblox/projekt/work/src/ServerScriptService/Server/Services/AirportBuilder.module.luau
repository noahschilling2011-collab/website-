--!strict
-- City Airport (CityPlan.AIRPORT), built once per server by CityBuilder.build (package "airport"; the airport
-- part of CityBuilder, split off like MetroBuilder). Same budgets as the rest of the city: real lights through
-- kit.light (per-zone budget), decoration never collides, touches, takes queries or casts shadows, every
-- walkable top sits on the zone ground (no holes).
--   * Terminal: glass hall (mullions, transoms, entrance portals) under a curved overhanging roof with
--     skylights, ribs and tree columns. Landside: check-in islands A-D (the four CheckinCounter prompts that
--     fly abroad: CityAction/FlightTo/CheckinTo unchanged), self check-in kiosks, queue barriers, departure
--     boards, information desk, coffee bar, arrivals with a baggage carousel and the arrivals exit. Security:
--     serpentine queue, three lanes (e-gates, divest tables with trays and instruction screens, X-ray machines,
--     walk-through arches, recompose tables, fast track), lightboxes on the wall. Airside:
--     business lounge (Model "BusinessLounge", tag "BusinessLounge"), crew room (marker part "CrewRoom"),
--     newsagent, bakery cafe, electronics, walk-through duty free, restrooms, food court, restaurant, quiet
--     zone, gate lounges A1-A3 with desks, signs and windows to the apron. Floor zoning (terrazzo grid, island
--     and security zones, door axes, kiosk rugs), luggage and trolleys in the queues and by the seats. Seat rows
--     come from CityPlan.AIRPORT.seatRows (= CityPlan.AIRPORT.seats); CityPlan.AIRPORT.walk is the matching
--     pedestrian graph. The fit-out is ONE Atomic model (TerminalInterior) so it streams in complete.
--   * Outside: forecourt (drop-off lane, taxi rank, buses, crossings, signs), car park, apron (stand
--     markings, lead-in lines, equipment roads, GSE parking on the west apron, a coned holding box, ground
--     vehicles (none in the shuttle's sweep on CityPlan.AIRPORT.shuttleStand),
--     jet bridges whose cab ends at the parked aircraft's boarding
--     door - read from the AircraftModel geometry, so a rebuilt model keeps them aligned), taxiway edge
--     lights, runway markings/lights, control tower with radar, hangar with the company-jet stand (marker
--     "CompanyJetStand", Purpose = "CompanyJet"), perimeter fence and trees, and a Persistent horizon (sea
--     to Port Meridian, coast hills, islands) so no void shows from the terminal or the air.
--   * Placeholder posts "AirportPost" (attribute CityPost = checkin | security | gate | lounge | shop | crew)
--     for a later staff package. Client animation only through the PropFx contract (belts, news ticker; the
--     tower radar and beacon carry FxFar / FxVertical and only animate once PropFxController honours them);
--     the server writes nothing after the build. Flight information shows only the one shuttle (FlightPlan
--     flight numbers, gate A<shuttleStand>, no clock times); boards are tagged "FlightInfoBoard" for live rows.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local City=require(ReplicatedStorage.Shared.Config.CityPlan)
local P=require(ReplicatedStorage.Shared.Config.ArchPalette)
local Aircraft=require(ReplicatedStorage.Shared.AircraftModel)
local FlightPlan=require(ReplicatedStorage.Shared.FlightPlan)
local Airport={}
export type Kit={
	light: (BasePart,number,number,Color3?)->boolean,
	prompt: (BasePart,string,string,number,number)->ProximityPrompt,
	kiosk: (Instance,number,number,number,number,string,string)->(),
	tree: (Instance,number,number,number,number?)->(),
	lamp: (Instance,number,number,boolean,number?)->(),
}
local A=City.AIRPORT
local G=City.GROUND
local F=G+.5 -- terminal floor top
local C=P.color
local M=Enum.Material
local SM=M.SmoothPlastic
local rgb=Color3.fromRGB
local PAINT=rgb(236,236,230)
local YELLOW=rgb(222,184,82)
local RED=rgb(190,56,46)
local INK=rgb(242,240,232)
local SIGN_INK=rgb(250,206,80)
local SCREEN_INK=rgb(250,200,110)
local NAVY=rgb(30,44,66)
local SLATE=rgb(52,60,72)
local BRAND=rgb(28,112,132) -- City Airport teal (generic, no real brand)
local FLOOR=rgb(170,167,160) -- polished terrazzo
local SEAT=rgb(58,92,128)
local GLOW=rgb(238,220,184)
local GOODS={rgb(196,62,58),rgb(62,104,170),rgb(238,196,72),rgb(80,150,96),rgb(232,230,224),rgb(150,84,150),rgb(240,140,60),rgb(44,48,54),rgb(120,180,200)}
local BOTTLES={rgb(150,96,40),rgb(60,110,70),rgb(200,170,90),rgb(120,40,50),rgb(200,206,210),rgb(90,60,40)}
local BREAD={rgb(196,146,82),rgb(170,112,60),rgb(222,184,120),rgb(140,90,50)}
local TECH={rgb(36,40,46),rgb(60,64,70),rgb(210,212,214),rgb(30,90,150),rgb(180,60,60),rgb(240,240,236)}
local BOOKS={rgb(170,60,50),rgb(50,90,140),rgb(230,200,90),rgb(60,120,80),rgb(220,220,214),rgb(110,70,130),rgb(230,130,60)}
local kit: Kit

------------------------------------------------------------------------------------------------ helpers
local function mk(parent: Instance,name: string,size: Vector3,cf: CFrame,color: Color3,material: Enum.Material?,decor: boolean?): Part
	local p=Instance.new("Part");p.Name=name;p.Anchored=true;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or SM
	p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
	if decor then p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false end
	p.Parent=parent;return p
end
local function box(parent: Instance,name: string,x1: number,x2: number,y1: number,y2: number,z1: number,z2: number,color: Color3,material: Enum.Material?,decor: boolean?): Part
	return mk(parent,name,Vector3.new(x2-x1,y2-y1,z2-z1),CFrame.new((x1+x2)/2,(y1+y2)/2,(z1+z2)/2),color,material,decor)
end
local function lbox(f: CFrame,parent: Instance,name: string,x1: number,x2: number,y1: number,y2: number,z1: number,z2: number,color: Color3,material: Enum.Material?,decor: boolean?): Part
	return mk(parent,name,Vector3.new(x2-x1,y2-y1,z2-z1),f*CFrame.new((x1+x2)/2,(y1+y2)/2,(z1+z2)/2),color,material,decor)
end
local function glass(p: Part,t: number?): Part p.Material=M.Glass;p.Transparency=t or .45;return p end
local function invisible(p: Part): Part p.Transparency=1;p.CastShadow=false;return p end
local function folder(parent: Instance,name: string,mode: Enum.ModelStreamingMode?): Model
	local m=Instance.new("Model");m.Name=name
	if mode then m.ModelStreamingMode=mode end
	m.Parent=parent;return m
end
-- vertical cylinder (Roblox cylinders run along their local X)
local function post(parent: Instance,name: string,x: number,z: number,y1: number,y2: number,d: number,color: Color3,material: Enum.Material?,decor: boolean?): Part
	local p=mk(parent,name,Vector3.new(y2-y1,d,d),CFrame.new(x,(y1+y2)/2,z)*CFrame.Angles(0,0,math.pi/2),color,material,decor)
	p.Shape=Enum.PartType.Cylinder;return p
end
-- cylinder along the X axis of cf
local function cylinder(parent: Instance,name: string,cf: CFrame,length: number,d: number,color: Color3,material: Enum.Material?,decor: boolean?): Part
	local p=mk(parent,name,Vector3.new(length,d,d),cf,color,material,decor);p.Shape=Enum.PartType.Cylinder;return p
end
local function ball(parent: Instance,name: string,pos: Vector3,d: number,color: Color3,material: Enum.Material?,decor: boolean?): Part
	local p=mk(parent,name,Vector3.new(d,d,d),CFrame.new(pos),color,material,decor);p.Shape=Enum.PartType.Ball;return p
end
-- WedgePart: full height at local +Z, slope facing local -Z
local function wedge(parent: Instance,name: string,size: Vector3,cf: CFrame,color: Color3,material: Enum.Material?,decor: boolean?): WedgePart
	local w=Instance.new("WedgePart");w.Name=name;w.Anchored=true;w.Size=size;w.CFrame=cf;w.Color=color;w.Material=material or SM
	if decor then w.CanCollide=false;w.CanTouch=false;w.CanQuery=false;w.CastShadow=false end
	w.Parent=parent;return w
end
-- square-section member between two points (local Z along the segment; never vertical)
local function member(parent: Instance,name: string,a: Vector3,b: Vector3,w: number,h: number,color: Color3,material: Enum.Material?,decor: boolean?): Part
	return mk(parent,name,Vector3.new(w,h,(b-a).Magnitude),CFrame.lookAt((a+b)/2,b),color,material,decor)
end
local function hash(s: string): number
	local h=7
	for i=1,#s do h=(h*31+string.byte(s,i))%2147483647 end
	return h
end
local function pick<T>(list: {T},k: number): T return list[k%#list+1] end
local function fx(inst: Instance,kinds: string,attrs: {[string]: any})
	inst:AddTag("PropFx");inst:SetAttribute("Fx",kinds)
	for k,v in attrs do inst:SetAttribute(k,v) end
end

type LabelOpts={ink: Color3?,font: Enum.Font?,align: Enum.TextXAlignment?,screen: boolean?,far: boolean?}
local function faceDims(p: BasePart,face: Enum.NormalId): Vector2
	local s=p.Size
	if face==Enum.NormalId.Front or face==Enum.NormalId.Back then return Vector2.new(s.X,s.Y) end
	if face==Enum.NormalId.Left or face==Enum.NormalId.Right then return Vector2.new(s.Z,s.Y) end
	return Vector2.new(s.X,s.Z)
end
-- SurfaceGui text on one face. screen = self-lit display; far = no MaxDistance (big exterior signs).
local function label(p: BasePart,text: string,face: Enum.NormalId?,o: LabelOpts?): TextLabel
	local opts: LabelOpts=o or {}
	local fc=face or Enum.NormalId.Front
	local d=faceDims(p,fc)
	local g=Instance.new("SurfaceGui");g.Face=fc
	-- uniform pixels per stud (no squashed text on long signs); low enough that TextScaled (capped at 100 px)
	-- can fill a big sign; canvas <= 2000 x 1200
	local lines=#string.split(text,"\n")
	local pps=math.max(4,math.min(40,2000/d.X,1200/d.Y,100/math.max(.1,d.Y*.84/lines)))
	g.CanvasSize=Vector2.new(d.X*pps,d.Y*pps)
	if opts.screen then g.LightInfluence=0;g.Brightness=1.6 else g.LightInfluence=.3 end
	if not opts.far then g.MaxDistance=280 end
	g.Parent=p
	local t=Instance.new("TextLabel");t.BackgroundTransparency=1;t.Size=UDim2.fromScale(.94,.84);t.Position=UDim2.fromScale(.03,.08)
	t.Text=text;t.TextScaled=true;t.TextWrapped=true;t.Font=opts.font or Enum.Font.BuilderSansBold
	t.TextColor3=opts.ink or INK;t.TextXAlignment=opts.align or Enum.TextXAlignment.Center;t.Parent=g
	return t
end
-- A sign panel facing `normal` (horizontal), text on its Front face (and optionally on its back).
local function panel(parent: Instance,name: string,center: Vector3,normal: Vector3,w: number,h: number,color: Color3,text: string?,opts: LabelOpts?,back: string?): Part
	local p=mk(parent,name,Vector3.new(w,h,.3),CFrame.lookAt(center,center+normal),color,SM,true)
	if text then label(p,text,Enum.NormalId.Front,opts) end
	if back then label(p,back,Enum.NormalId.Back,opts) end
	return p
end
-- Hanging wayfinding sign (double-sided, yellow on dark), two rods up to the ceiling height `top`.
local function hangingSign(parent: Instance,x: number,z: number,y: number,w: number,front: string,back: string?,top: number,alongZ: boolean?)
	local normal=if alongZ then Vector3.new(1,0,0) else Vector3.new(0,0,-1)
	local p=panel(parent,"WayfindingSign",Vector3.new(x,y,z),normal,w,2.6,rgb(36,40,46),front,{ink=SIGN_INK},back or front)
	for _,s in {-1,1} do
		local o=if alongZ then Vector3.new(0,0,s*(w/2-1)) else Vector3.new(s*(w/2-1),0,0)
		local q=p.Position+o
		box(parent,"SignRod",q.X-.08,q.X+.08,y+1.3,top,q.Z-.08,q.Z+.08,C.metal,M.Metal,true)
	end
end
-- Planter with a shrub ball (or a small indoor tree when tall)
local function planter(parent: Instance,x: number,z: number,w: number,d: number,tall: boolean?,k: number?)
	box(parent,"Planter",x-w/2,x+w/2,F,F+2.2,z-d/2,z+d/2,rgb(70,74,78),M.Slate)
	box(parent,"PlanterSoil",x-w/2+.3,x+w/2-.3,F+2.2,F+2.35,z-d/2+.3,z+d/2-.3,C.soil,M.Ground,true)
	local leaf=if (k or 0)%2==0 then C.foliage else C.foliageLight
	if tall then
		box(parent,"PlanterTrunk",x-.3,x+.3,F+2.3,F+9,z-.3,z+.3,C.oakDark,M.Wood,true)
		ball(parent,"PlanterTree",Vector3.new(x,F+10,z),math.min(w,d)+3,leaf,M.LeafyGrass,true)
	else
		local n=math.clamp(math.floor(w/math.max(d,1)+.5),1,6)
		for i=1,n do
			local cx=x-w/2+(i-.5)*w/n
			ball(parent,"PlanterShrub",Vector3.new(cx,F+3.1,z),math.min(d+.8,w/n+.6),if i%2==0 then C.foliageLight else leaf,M.LeafyGrass,true)
		end
	end
end
-- Wall shelf in frame f (origin = front edge centre on the floor, LookVector = the side customers stand on).
local function shelf(f: CFrame,parent: Instance,w: number,h: number,depth: number,levels: number,seed: number,palette: {Color3})
	lbox(f,parent,"Shelf",-w/2,w/2,0,h,depth-.3,depth,rgb(236,234,228),SM)
	lbox(f,parent,"ShelfPlinth",-w/2,w/2,0,.35,0,depth-.3,rgb(70,74,78),SM,true)
	local step=(h-.6)/levels
	for k=0,levels-1 do
		local y=.35+k*step
		lbox(f,parent,"ShelfBoard",-w/2,w/2,y,y+.12,0,depth-.3,rgb(214,212,206),SM,true)
		local gh=math.min(1.4,step-.4)
		local n=if w>=6 then 3 else 2
		for i=0,n-1 do
			local a=-w/2+.2+i*(w-.4)/n
			local b=a+(w-.4)/n-.25
			local gh2=gh*(.7+.3*((seed+i*7+k*3)%4)/3)
			lbox(f,parent,"Goods",a,b,y+.12,y+.12+gh2,.2,depth-.45,pick(palette,seed+i*5+k*3),SM,true)
		end
	end
end
-- Seat pads of one row side split per seat (small gaps, so single seats read) and thin light-metal armrests
-- between them that stop at the seat edge. z1..z2 = pad depth, n seats over x1..x2.
local function seatPads(parent: Instance,x1: number,x2: number,z1: number,z2: number,n: number,col: Color3)
	local w=(x2-x1)/n
	for i=0,n-1 do
		local a=x1+i*w
		box(parent,"SeatPad",a+.12,a+w-.12,F+1.45,F+1.95,z1,z2,col,M.Fabric)
		if i>0 then box(parent,"Armrest",a-.05,a+.05,F+1.95,F+2.5,z1+.3,z2-.4,rgb(178,184,190),M.Metal,true) end
	end
end
-- Double row of gate seats (back to back) along X, centre z.
local function seatRows(parent: Instance,x1: number,x2: number,z: number)
	box(parent,"SeatBeam",x1,x2,F+1.1,F+1.45,z-.5,z+.5,C.metal,M.Metal)
	for _,x in {x1+1,x2-1} do box(parent,"SeatLeg",x-.2,x+.2,F,F+1.1,z-1.4,z+1.4,C.metal,M.Metal,true) end
	local n=math.max(1,math.floor((x2-x1)/2.6))
	seatPads(parent,x1,x2,z-2.4,z-.4,n,SEAT)
	seatPads(parent,x1,x2,z+.4,z+2.4,n,SEAT)
	box(parent,"SeatBack",x1+.1,x2-.1,F+1.95,F+4.1,z-.35,z+.35,SEAT:Lerp(rgb(30,40,52),.35),M.Fabric)
	box(parent,"SeatBackCap",x1+.1,x2-.1,F+4.1,F+4.25,z-.4,z+.4,C.metalSoft,M.Metal,true)
end
-- Single row of seats facing `facing` (+1 = faces +Z).
local function seatRow(parent: Instance,x1: number,x2: number,z: number,facing: number,color: Color3?)
	local col=color or SEAT
	box(parent,"SeatBeam",x1,x2,F+1.1,F+1.45,z-.5,z+.5,C.metal,M.Metal)
	for _,x in {x1+1,x2-1} do box(parent,"SeatLeg",x-.2,x+.2,F,F+1.1,z-.8,z+.8,C.metal,M.Metal,true) end
	local n=math.max(1,math.floor((x2-x1)/2.6))
	seatPads(parent,x1,x2,z-1.1,z+1.1,n,col)
	local bz=z-facing*1.1
	box(parent,"SeatBack",x1+.1,x2-.1,F+1.95,F+4,bz-.25,bz+.25,col:Lerp(rgb(30,40,52),.35),M.Fabric)
end
-- Seat rows from CityPlan.AIRPORT.seatRows (the same list gives CityPlan.AIRPORT.seats): rows of one gate, or
-- (gate = nil) every landside row.
local function planSeats(parent: Instance,gate: string?,color: Color3?)
	for _,r in A.seatRows do
		if r.gate==gate then
			if r.facing==0 then seatRows(parent,r.x1,r.x2,r.z) else seatRow(parent,r.x1,r.x2,r.z,r.facing,color) end
		end
	end
end
-- Table with chairs (2 or 4): pedestal table; each chair = seat slab on one pedestal post and a thin back.
local function tableSet(parent: Instance,x: number,z: number,chairs: number,top: Color3,chair: Color3,size: number?)
	local s=size or 3
	post(parent,"TablePedestal",x,z,F,F+2.6,.5,C.metal,M.Metal)
	box(parent,"TableTop",x-s/2,x+s/2,F+2.6,F+2.85,z-s/2,z+s/2,top,M.Wood,true)
	local offs={{0,-1},{0,1},{-1,0},{1,0}}
	for i=1,chairs do
		local o=offs[i]
		local cx,cz=x+o[1]*(s/2+1.1),z+o[2]*(s/2+1.1)
		box(parent,"Chair",cx-.85,cx+.85,F+1.4,F+1.7,cz-.85,cz+.85,chair,M.Fabric)
		post(parent,"ChairPost",cx,cz,F,F+1.4,.3,C.metalSoft,M.Metal,true)
		local bx,bz=cx+o[1]*.78,cz+o[2]*.78
		if o[1]==0 then box(parent,"ChairBack",cx-.8,cx+.8,F+1.7,F+3.3,bz-.07,bz+.07,chair,M.Fabric,true)
		else box(parent,"ChairBack",bx-.07,bx+.07,F+1.7,F+3.3,cz-.8,cz+.8,chair,M.Fabric,true) end
	end
end
-- Lounge armchair facing `dir` (unit vector in XZ): recessed dark plinth, leather body, lighter seat cushion,
-- thin low arms and a slightly reclined back.
local function armchair(parent: Instance,x: number,z: number,dir: Vector3,color: Color3,cushion: Color3)
	local f=CFrame.lookAt(Vector3.new(x,F,z),Vector3.new(x,F,z)+dir)
	lbox(f,parent,"ArmchairPlinth",-1.05,1.05,0,.45,-.95,.95,rgb(34,32,32),SM,true)
	lbox(f,parent,"Armchair",-1.4,1.4,.45,1.25,-1.3,1.2,color,M.Leather)
	lbox(f,parent,"ArmchairCushion",-1.05,1.05,1.25,1.6,-1.25,.7,cushion,M.Fabric,true)
	mk(parent,"ArmchairBack",Vector3.new(2.8,2.3,.45),f*CFrame.new(0,2.3,1.02)*CFrame.Angles(math.rad(10),0,0),color,M.Leather,true)
	for _,s in {-1,1} do lbox(f,parent,"ArmchairArm",if s>0 then 1.05 else -1.4,if s>0 then 1.4 else -1.05,1.25,2.05,-1.15,1.0,color:Lerp(rgb(0,0,0),.18),M.Leather,true) end
end
local function stool(parent: Instance,x: number,z: number,h: number,color: Color3)
	post(parent,"StoolPost",x,z,F,F+h-.3,.3,C.metal,M.Metal,true)
	post(parent,"StoolSeat",x,z,F+h-.3,F+h,1.3,color,M.Leather)
end
-- Small screen with text (self-lit).
local function screen(parent: Instance,name: string,center: Vector3,normal: Vector3,w: number,h: number,text: string,ink: Color3?,back: string?): Part
	local p=panel(parent,name,center,normal,w,h,C.screen,text,{ink=ink or SCREEN_INK,screen=true,font=Enum.Font.BuilderSansBold},back)
	return p
end
local function airportPost(parent: Instance,kind: string,pos: Vector3,face: Vector3,extra: string?)
	local p=invisible(mk(parent,"AirportPost",Vector3.new(2,5,1),CFrame.lookAt(pos,pos+face),C.white,SM,true))
	p:SetAttribute("CityPost",kind);p:SetAttribute("BuildingId","airport")
	if extra then p:SetAttribute("Desk",extra) end
end
-- Departure board text (monospace rows)
local function boardText(title: string,rows: {string}): string
	return title.."\n"..table.concat(rows,"\n")
end
-- Flight information: the ONE shuttle aircraft (FlightPlan: PM 101 out from gate A<shuttleStand>, PM 102 back)
-- and no fixed clock times - the live times come from the client (ShuttleController writes the GateBoardHome
-- board; every part tagged "FlightInfoBoard" carries Board / Gate / Flight attributes for the same live rows).
local OUT_NO=FlightPlan.CONFIG.flights.out
local BACK_NO=FlightPlan.CONFIG.flights.back
local SHUTTLE_GATE="A"..A.shuttleStand
local DEPARTURES={
	"FLIGHT   DESTINATION      GATE  REMARK",
	OUT_NO.."   PORT MERIDIAN    "..SHUTTLE_GATE.."    CHECK-IN OPEN",
	"",
	"CHECK-IN A – D  ·  SECURITY LANES 1 – 3",
	"BOARDING TIMES AT GATE "..SHUTTLE_GATE,
}
local ARRIVALS={
	"FLIGHT   FROM             BELT  REMARK",
	BACK_NO.."   PORT MERIDIAN    1     SHUTTLE",
	"",
	"TAXI  ·  BUS  ·  CAR PARK WEST",
}
local MONITOR="DEPARTURES\n"..OUT_NO.."  "..SHUTTLE_GATE.."  PORT MERIDIAN"
local function flightInfo(p: BasePart,kind: string,gate: string?,flight: string?)
	p:AddTag("FlightInfoBoard");p:SetAttribute("Board",kind);p:SetAttribute("Gate",gate or SHUTTLE_GATE)
	p:SetAttribute("Flight",flight or (if kind=="arrivals" then BACK_NO else OUT_NO))
	for _,d in p:GetDescendants() do if d:IsA("TextLabel") then d.Name="FlightText" end end
end
local function board(parent: Instance,name: string,center: Vector3,normal: Vector3,w: number,h: number,title: string,rows: {string}): Part
	local p=mk(parent,name,Vector3.new(w,h,.4),CFrame.lookAt(center,center+normal),rgb(16,20,24),SM,true)
	local t=label(p,boardText(title,rows),Enum.NormalId.Front,{ink=SCREEN_INK,screen=true,font=Enum.Font.RobotoMono,align=Enum.TextXAlignment.Left})
	t.TextYAlignment=Enum.TextYAlignment.Top
	mk(parent,name.."Frame",Vector3.new(w+.5,h+.5,.1),p.CFrame*CFrame.new(0,0,.25),C.metal,M.Metal,true)
	flightInfo(p,if title=="ARRIVALS" then "arrivals" else "departures")
	return p
end

------------------------------------------------------------------------------------------------ roof profile
-- Underside (soffit) of the terminal roof as a function of z: canopy edge over the drop-off lane, crown over
-- the hall, overhang on the apron side. Constant along x.
local RZ={2398,2430,2462,2500,2530,2548}
local RY={G+27.5,G+35,G+40,G+40,G+35,G+31.5}
local function roofY(z: number): number
	if z<=RZ[1] then return RY[1] end
	for i=1,#RZ-1 do
		if z<=RZ[i+1] then return RY[i]+(RY[i+1]-RY[i])*(z-RZ[i])/(RZ[i+1]-RZ[i]) end
	end
	return RY[#RY]
end
-- slab whose bottom face lies `off` above the line (z1,y1)-(z2,y2) (negative off = below), spanning x1..x2
local function slab(parent: Instance,name: string,x1: number,x2: number,z1: number,y1: number,z2: number,y2: number,thick: number,off: number,color: Color3,material: Enum.Material?,decor: boolean?): Part
	local dz,dy=z2-z1,y2-y1
	local len=math.sqrt(dz*dz+dy*dy)
	local a=math.atan2(dy,dz)
	local up=Vector3.new(0,math.cos(a),-math.sin(a))
	local c=Vector3.new((x1+x2)/2,(y1+y2)/2,(z1+z2)/2)+up*(off+thick/2)
	return mk(parent,name,Vector3.new(x2-x1,thick,len),CFrame.new(c)*CFrame.Angles(-a,0,0),color,material,decor)
end

------------------------------------------------------------------------------------------------ terminal shell
local T=A.terminal
local FRONT,BACK=T.z1,T.z2
local SEC=A.security
local DOORS={-150,0,150,A.arrivalsDoor}
local function shell(term: Instance,doorsBack: {number})
	local m=term
	box(m,"HallFloor",T.x1,T.x2,G,F,T.z1,T.z2,FLOOR,M.Limestone)
	-- floor bands (decor): concourse strips landside and airside
	box(m,"FloorBand",T.x1+2,T.x2-2,F,F+.03,2433,2437,rgb(96,102,112),M.Marble,true)
	box(m,"FloorBand",T.x1+2,T.x2-2,F,F+.03,2500,2506,rgb(96,102,112),M.Marble,true)
	for _,z in {2432.4,2437.6,2499.4,2506.6} do box(m,"FloorInlay",T.x1+2,T.x2-2,F,F+.03,z-.15,z+.15,C.brass,M.Metal,true) end
	local fh=roofY(FRONT)
	-- north facade: glass between the door openings, lintels, mullions every 12, two transoms
	local cuts=table.clone(DOORS);table.sort(cuts)
	local x0=T.x1
	for _,x in cuts do
		glass(box(m,"Facade",x0,x-6,F,fh,FRONT,FRONT+.8,C.glass),.55)
		box(m,"EntranceLintel",x-6,x+6,G+12,fh,FRONT,FRONT+.8,C.stoneDeep,M.Limestone)
		x0=x+6
	end
	glass(box(m,"Facade",x0,T.x2,F,fh,FRONT,FRONT+.8,C.glass),.55)
	for x=T.x1+12,T.x2-12,12 do
		local free=true;for _,dx in cuts do if math.abs(x-dx)<7 then free=false end end
		if free then box(m,"Mullion",x-.25,x+.25,F,fh,FRONT-.35,FRONT+1.1,C.metal,M.Metal,true) end
	end
	x0=T.x1
	for _,x in cuts do
		for _,y in {G+12,G+24} do box(m,"Transom",x0,x-6,y-.2,y+.2,FRONT-.3,FRONT+1,C.metal,M.Metal,true) end
		x0=x+6
	end
	for _,y in {G+12,G+24} do box(m,"Transom",x0,T.x2,y-.2,y+.2,FRONT-.3,FRONT+1,C.metal,M.Metal,true) end
	-- entrance portals: framed vestibules with a small canopy and the door function above
	for _,x in cuts do
		box(m,"PortalFrame",x-7,x-6,F,G+12.6,FRONT-3,FRONT+.8,C.metal,M.Metal,true)
		box(m,"PortalFrame",x+6,x+7,F,G+12.6,FRONT-3,FRONT+.8,C.metal,M.Metal,true)
		box(m,"PortalCanopy",x-7.5,x+7.5,G+12.6,G+13.4,FRONT-3.5,FRONT+.8,C.metal,M.Metal,true)
		local s=box(m,"PortalSign",x-6,x+6,G+13.4,G+15.6,FRONT-.4,FRONT-.1,NAVY,SM,true)
		label(s,if x==A.arrivalsDoor then "ARRIVALS" else "DEPARTURES",Enum.NormalId.Front,{ink=INK})
	end
	-- south facade (apron side): glass with the jet-bridge doors, mullions, transoms
	local bh=roofY(BACK)
	local bz=BACK-.8
	local bcuts=table.clone(doorsBack);table.sort(bcuts)
	x0=T.x1
	for _,x in bcuts do
		glass(box(m,"BackGlass",x0,x-3,F,bh,bz,BACK,C.glass),.6)
		box(m,"GateLintel",x-3,x+3,F+9,bh,bz,BACK,C.stoneDeep,M.Limestone)
		box(m,"GateDoorFrame",x-3.4,x-3,F,F+9,bz-.3,BACK+.3,C.metal,M.Metal,true)
		box(m,"GateDoorFrame",x+3,x+3.4,F,F+9,bz-.3,BACK+.3,C.metal,M.Metal,true)
		x0=x+3
	end
	glass(box(m,"BackGlass",x0,T.x2,F,bh,bz,BACK,C.glass),.6)
	for x=T.x1+12,T.x2-12,12 do
		local free=true;for _,dx in bcuts do if math.abs(x-dx)<4 then free=false end end
		if free then box(m,"Mullion",x-.25,x+.25,F,bh,bz-.3,BACK+.35,C.metal,M.Metal,true) end
	end
	for _,y in {G+18} do box(m,"Transom",T.x1,T.x2,y-.2,y+.2,bz-.3,BACK+.3,C.metal,M.Metal,true) end
	-- end walls: stone base, glass gables up to the roof (box + wedge where the roof slopes)
	for _,side in {-1,1} do
		local wx1,wx2=if side<0 then T.x1 else T.x2-1.5,if side<0 then T.x1+1.5 else T.x2
		box(m,"SideWall",wx1,wx2,F,G+16,FRONT+.8,BACK-.8,C.stone,M.Limestone)
		for i=2,4 do
			local z1,z2=RZ[i],RZ[i+1]
			local lo=math.min(RY[i],RY[i+1])
			local zz1,zz2=math.max(z1,FRONT+.8),math.min(z2,BACK-.8)
			glass(box(m,"SideGlass",wx1,wx2,G+16,lo,zz1,zz2,C.glass,nil,true),.55).CanCollide=true
			if RY[i]~=RY[i+1] then
				local h=math.abs(RY[i+1]-RY[i])
				local cf=CFrame.new((wx1+wx2)/2,lo+h/2,(zz1+zz2)/2)*(if RY[i+1]<RY[i] then CFrame.Angles(0,math.pi,0) else CFrame.new())
				local w=wedge(m,"SideGable",Vector3.new(wx2-wx1,h,zz2-zz1),cf,C.glass,M.Glass,true);w.Transparency=.55
			end
		end
		box(m,"SideWallCap",wx1-.3,wx2+.3,G+15.6,G+16.4,FRONT+.8,BACK-.8,C.stoneDeep,M.Limestone,true)
	end
	-- roof: soffit (light wood) + metal skin per profile segment, two skylight bands in the crown
	local rx1,rx2=T.x1-12,T.x2+12
	for i=1,#RZ-1 do
		local z1,y1,z2,y2=RZ[i],RY[i],RZ[i+1],RY[i+1]
		if i==3 then
			-- crown: solid / skylight / solid / skylight / solid
			local cuts2: {{number}}={{2462,2468,0},{2468,2478,1},{2478,2484,0},{2484,2494,1},{2494,2500,0}}
			for _,c in cuts2 do
				local za,zb=c[1],c[2]
				if c[3]==0 then
					slab(m,"RoofSoffit",rx1,rx2,za,y1,zb,y2,.8,0,C.oakLight,M.WoodPlanks)
					slab(m,"RoofSkin",rx1,rx2,za,y1,zb,y2,1,.8,C.metalSoft,M.Metal)
				else
					glass(slab(m,"Skylight",rx1+20,rx2-20,za,y1,zb,y2,1.8,0,C.glass,nil,true),.35)
					slab(m,"SkylightFrame",rx1,rx1+20,za,y1,zb,y2,1.8,0,C.metalSoft,M.Metal)
					slab(m,"SkylightFrame",rx2-20,rx2,za,y1,zb,y2,1.8,0,C.metalSoft,M.Metal)
				end
			end
		else
			slab(m,"RoofSoffit",rx1,rx2,z1,y1,z2,y2,.8,0,C.oakLight,M.WoodPlanks)
			slab(m,"RoofSkin",rx1,rx2,z1,y1,z2,y2,1,.8,C.metalSoft,M.Metal)
		end
		-- white edge fascia along both ends of the roof, following the profile
		for _,x in {rx1-.6,rx2+.6} do slab(m,"RoofFascia",x-.6,x+.6,z1,y1,z2,y2,2.6,-.5,C.white,M.Metal,true) end
	end
	-- front and back edge fascia, standing-seam ribs on the skin (every 40 studs)
	box(m,"RoofEdge",rx1-1.2,rx2+1.2,RY[1]-.8,RY[1]+2.4,RZ[1]-1.2,RZ[1],C.white,M.Metal,true)
	box(m,"RoofEdge",rx1-1.2,rx2+1.2,RY[#RY]-.8,RY[#RY]+2.4,RZ[#RZ],RZ[#RZ]+1.2,C.white,M.Metal,true)
	for x=rx1+20,rx2-20,40 do
		for i=1,#RZ-1 do slab(m,"RoofRib",x-.4,x+.4,RZ[i],RY[i],RZ[i+1],RY[i+1],.9,1.8,C.metal,M.Metal,true) end
	end
	-- the airport name: fascia band over the canopy edge and a rooftop sign (both face the city, north)
	local band=box(m,"AirportFascia",-80,80,RY[1]-.6,RY[1]+2.2,RZ[1]-1.6,RZ[1]-1.25,NAVY,SM,true)
	label(band,"CITY AIRPORT  ·  DEPARTURES  ·  ARRIVALS",Enum.NormalId.Front,{ink=INK,far=true})
	local rs=box(m,"AirportRoofSign",-60,60,roofY(2440)+2,roofY(2440)+9,2439.6,2440.2,NAVY,SM,true)
	label(rs,"CITY AIRPORT",Enum.NormalId.Front,{ink=INK,far=true})
	for _,x in {-50,0,50} do box(m,"RoofSignLeg",x-.3,x+.3,roofY(2440)+1,roofY(2440)+2,2440.2,2441,C.metal,M.Metal,true) end
	-- canopy columns on the curb: tapered posts with two struts to the soffit
	for _,x in {-225,-75,75,225} do
		box(m,"CanopyColumn",x-.7,x+.7,City.WALK_TOP,G+18,2419.3,2420.7,C.white,M.Metal)
		for _,s in {-1,1} do member(m,"CanopyStrut",Vector3.new(x,G+18,2420),Vector3.new(x+s*9,roofY(2410)-.2,2410),.6,.6,C.white,M.Metal,true) end
	end
end

-- Interior structure (part of the shell, visible through the glass): tree columns, roof beams, light strips.
local function structure(term: Instance)
	local m=folder(term,"Structure")
	for x=T.x1+12.5,T.x2-12.5,25 do
		for i=2,4 do slab(m,"RoofBeam",x-.5,x+.5,RZ[i],RY[i],RZ[i+1],RY[i+1],1.6,-1.6,C.white,M.Metal,true) end
	end
	for _,z in {RZ[3],RZ[4]} do box(m,"RoofGirder",T.x1+1.5,T.x2-1.5,RY[3]-2.2,RY[3],z-.6,z+.6,C.white,M.Metal,true) end
	-- continuous light strips under the soffit (neon; real lights hang from fixtures in each zone)
	for _,s in {{2440,2452},{2479,2483},{2508,2520}} do
		local za,zb=s[1],s[2]
		slab(m,"LightStrip",T.x1+3,T.x2-3,za,roofY(za),zb,roofY(zb),.25,-1.85,C.lightNeutral,M.Neon,true)
	end
	-- tree columns on the line z = 2477: white shaft, four branches up to the roof
	for _,x in {-262.5,-187.5,-112.5,-37.5,37.5,112.5,187.5,262.5} do
		box(m,"Column",x-1.2,x+1.2,F,G+24,2475.8,2478.2,C.white,M.Metal)
		box(m,"ColumnBase",x-1.6,x+1.6,F,F+.8,2475.4,2478.6,C.stoneDeep,M.Limestone,true)
		for _,o in {{-1,-1},{1,-1},{-1,1},{1,1}} do
			local tz=2477+o[2]*15
			member(m,"ColumnBranch",Vector3.new(x,G+23,2477),Vector3.new(x+o[1]*9,roofY(tz)-1.8,tz),.8,.8,C.white,M.Metal,true)
		end
	end
	-- security wall: solid up to G+16, glass above (one hall under one roof); lane openings 16 wide
	local lanes=A.lanes
	local x0=T.x1+1.5
	for _,lx in lanes do
		box(m,"SecurityWall",x0,lx-8,F,G+16,SEC-.5,SEC+.5,C.interior,M.Plaster)
		box(m,"SecurityLintel",lx-8,lx+8,G+12,G+16,SEC-.5,SEC+.5,C.interior,M.Plaster)
		x0=lx+8
	end
	box(m,"SecurityWall",x0,T.x2-1.5,F,G+16,SEC-.5,SEC+.5,C.interior,M.Plaster)
	x0=T.x1+1.5
	local segs: {{number}}={}
	for _,lx in lanes do table.insert(segs,{x0,lx-8});x0=lx+8 end
	table.insert(segs,{x0,T.x2-1.5})
	for _,sg in segs do
		box(m,"WallCladding",sg[1],sg[2],F+1.2,G+16,SEC-.62,SEC-.5,C.oakLight,M.WoodPlanks,true)
		box(m,"WallSkirting",sg[1],sg[2],F,F+1.2,SEC-.64,SEC-.5,rgb(70,74,80),M.Slate,true)
	end
	for _,lx in lanes do box(m,"LanePortal",lx-8,lx+8,G+12,G+16,SEC-.64,SEC-.5,NAVY,M.Metal,true) end
	type Ad={x: number,text: string,color: Color3}
	local ads: {Ad}={{x=-262,text="PORT MERIDIAN\nwhere business takes off",color=rgb(28,96,128)},
		{x=-188,text="AI EMPIRE EXPO\nConvention Centre  ·  Business City",color=rgb(150,58,48)},
		{x=-112,text="CITY HOTEL\nstay downtown, meet anywhere",color=rgb(120,92,52)},
		{x=112,text="MERIDIAN GRAND HOTEL\nyour stay abroad",color=rgb(52,72,120)},
		{x=188,text="FLY BUSINESS\nlounge access  ·  fast track lane 3",color=rgb(36,40,46)},
		{x=262,text="BUSINESS CITY\n14 client offices  ·  one avenue",color=rgb(64,110,84)}}
	for _,ad in ads do
		box(m,"AdvertFrame",ad.x-8.4,ad.x+8.4,F+2.6,F+11.4,SEC-.9,SEC-.62,C.metal,M.Metal,true)
		local lb=screen(m,"AdvertLightbox",Vector3.new(ad.x,F+7,SEC-1.05),Vector3.new(0,0,-1),16,8,ad.text,INK)
		lb.Color=ad.color
	end
	glass(box(m,"SecurityGlass",T.x1+1.5,T.x2-1.5,G+16,RY[3],SEC-.2,SEC+.2,C.glass,nil,true),.7)
	box(m,"SecurityWallCap",T.x1+1.5,T.x2-1.5,G+15.8,G+16.3,SEC-.7,SEC+.7,C.metalSoft,M.Metal,true)
end

------------------------------------------------------------------------------------------------ landside
-- Check-in island at x (the prompt counter = the centre desk at CityPlan.AIRPORT.checkin): a row of desks
-- (offsets from x; islands B/C stop short of security lanes 1/3), bag scales between them, the staff corridor
-- (4 studs), the bag belt and the spine with the backlit header and desk screens; serpentine queue in front.
local function checkinIsland(parent: Instance,x: number,letter: string,ticketText: string,offs: {number})
	local m=folder(parent,"CheckIn"..letter)
	local z=A.checkin[1].Z -- 2461: counter line (passengers stand north of it)
	local lo,hi=x+offs[1],x+offs[#offs]
	box(m,"IslandSpine",lo-3,hi+3,F,G+10,2469,2470.6,SLATE,SM) -- ends 3 short: lane 1 passes island B's end
	local header=box(m,"IslandHeader",lo-3.5,hi+3.5,G+10,G+13.6,2468.6,2471,NAVY,M.Metal,true)
	label(header,"CHECK-IN   "..letter,Enum.NormalId.Front,{ink=INK})
	box(m,"HeaderGlow",lo-3,hi+3,G+9.6,G+10,2468.4,2468.8,BRAND,M.Neon,true)
	local duty={"BAG DROP","PORT MERIDIAN","ALL FLIGHTS","PORT MERIDIAN","BUSINESS","FAMILIES","SPECIAL BAGGAGE"}
	for k,dx in offs do
		local cx=x+dx
		local desk=box(m,if dx==0 then "CheckinCounter" else "CheckinDesk",cx-2.5,cx+2.5,F,F+3.6,z-2,z+1.5,C.white,M.Marble)
		if dx==0 then
			local q=kit.prompt(desk,"Check in & fly",ticketText,10,1)
			q:SetAttribute("CityAction","checkin");q:SetAttribute("FlightTo","abroad")
			desk:SetAttribute("CheckinTo","abroad")
		end
		box(m,"DeskFront",cx-2.5,cx+2.5,F+.4,F+3.2,z-2.2,z-2,if dx==offs[#offs] then C.brass else BRAND,SM,true)
		box(m,"DeskTop",cx-2.8,cx+2.8,F+3.6,F+3.9,z-2.4,z+1.7,C.stone,M.Marble,true)
		box(m,"DeskMonitor",cx-1,cx+1,F+3.9,F+5.2,z+.3,z+.5,C.screen,SM,true)
		screen(m,"DeskScreen",Vector3.new(cx,G+7.4,2468.85),Vector3.new(0,0,-1),4.4,2.4,letter..k.."\n"..duty[(k-1)%#duty+1])
		if k<#offs then box(m,"BagScale",cx+2.5,cx+4.5,F,F+.9,z-2,z+1.5,C.metalSoft,M.Metal) end
	end
	box(m,"BagBeltBase",lo-3,hi+3,F,F+.7,z+5.5,z+7.5,C.metalSoft,M.Metal)
	box(m,"BagBelt",lo-3,hi+3,F+.7,F+.85,z+5.6,z+7.4,rgb(30,32,34),M.Rubber,true)
	for i=0,#offs-2 do
		local bx=lo+2+i*7+(hash(letter..i)%4)
		box(m,"Suitcase",bx-1.2,bx+1.2,F+.85,F+2.5+(i%2)*.4,z+5.8,z+7.1,pick(GOODS,hash(letter)+i*2),SM,true)
	end
	-- queue barriers: four rows, openings alternate (serpentine), entry sign at the open end
	for r=0,3 do
		local qz=z-5-r*3.6
		local a,b=if r%2==0 then lo else lo+5,if r%2==0 then hi-5 else hi
		box(m,"QueueBelt",a,b,F+2.6,F+2.85,qz-.05,qz+.05,NAVY,M.Fabric,true)
		local n=math.max(2,math.floor((b-a)/8))
		for j=0,n do post(m,"QueuePost",a+(b-a)*j/n,qz,F,F+3,.32,C.metalSoft,M.Metal,true) end
	end
	-- entry sign beside the queue entrance (west end, CityPlan walk node Q<i>a), clear of the walk lines
	post(m,"QueueSignPost",lo-.8,2446,F,F+5,.3,C.metal,M.Metal,true)
	panel(m,"QueueSign",Vector3.new(lo-.8,F+5.8,2446),Vector3.new(0,0,-1),3.4,1.6,NAVY,"CHECK-IN "..letter.."\nqueue here",{ink=INK},"CHECK-IN "..letter)
	airportPost(m,"checkin",Vector3.new(x,F+3,z+3.5),Vector3.new(0,0,-1),letter)
end

local function kioskGroup(parent: Instance,cx: number,z: number)
	for i=-1,1 do
		local x=cx+i*3.4
		box(parent,"SelfCheckinKiosk",x-.9,x+.9,F,F+4.2,z-.6,z+.6,C.white,SM)
		local head=mk(parent,"SelfCheckinScreen",Vector3.new(1.9,1.5,.25),CFrame.new(x,F+4.6,z-.25)*CFrame.Angles(math.rad(-20),0,0),C.screen,SM,true)
		label(head,"CHECK-IN",Enum.NormalId.Front,{ink=rgb(140,220,230),screen=true})
		box(parent,"KioskBand",x-.95,x+.95,F+3.2,F+3.6,z-.65,z+.65,BRAND,SM,true)
	end
end

-- Nested luggage trolleys along X (handle at the west end): chassis, frame ribs (one per trolley), top rails,
-- a thin red handle bar on two posts.
local function trolleys(parent: Instance,x: number,z: number,n: number)
	local l=n*1.4+2
	local x1,x2=x-l/2,x+l/2
	box(parent,"TrolleyChassis",x1,x2,F+.25,F+.5,z-.8,z+.8,C.metalSoft,M.Metal,true)
	for _,dz in {-.9,.9} do box(parent,"TrolleyRail",x1+.3,x2,F+2.55,F+2.7,z+dz-.06,z+dz+.06,rgb(196,200,204),M.Metal,true) end
	for i=0,n-1 do
		local rx=x1+.6+i*1.4
		box(parent,"TrolleyFrame",rx-.05,rx+.05,F+.5,F+2.7,z-.9,z+.9,rgb(176,182,188),M.Metal,true).Transparency=.3
	end
	for _,dz in {-.85,.85} do box(parent,"TrolleyPost",x1-.05,x1+.07,F+.5,F+3.5,z+dz-.06,z+dz+.06,rgb(196,200,204),M.Metal,true) end
	box(parent,"TrolleyHandle",x1-.12,x1+.1,F+3.45,F+3.65,z-1,z+1,rgb(196,60,50),SM,true)
end
-- One luggage trolley (frame f: origin on the floor, handle at local +Z) loaded with one or two bags.
local function loadedTrolley(parent: Instance,f: CFrame,k: number)
	lbox(f,parent,"TrolleyChassis",-.8,.8,.25,.5,-1.6,1.4,C.metalSoft,M.Metal,true)
	for _,s in {-1,1} do lbox(f,parent,"TrolleyRail",s*.85-.05,s*.85+.05,.5,2.2,1.3,1.4,rgb(196,200,204),M.Metal,true) end
	lbox(f,parent,"TrolleyHandle",-.95,.95,3.2,3.4,1.42,1.6,rgb(196,60,50),SM,true)
	for _,s in {-1,1} do lbox(f,parent,"TrolleyPost",s*.85-.05,s*.85+.05,2.2,3.2,1.45,1.55,rgb(196,200,204),M.Metal,true) end
	lbox(f,parent,"Suitcase",-.75,.75,.5,1.5,-1.5,1.2,pick(GOODS,k),SM,true)
	if k%2==0 then lbox(f,parent,"Suitcase",-.6,.6,1.5,2.3,-1.2,.9,pick(GOODS,k+3),SM,true) end
end
-- Upright suitcase with its pulled-out handle (decor), facing along X.
local function suitcase(parent: Instance,x: number,z: number,k: number)
	local tall=1.6+(k%3)*.5
	box(parent,"Suitcase",x-.7,x+.7,F,F+tall,z-.45,z+.45,pick(GOODS,k),SM,true)
	box(parent,"SuitcaseHandle",x-.35,x+.35,F+tall,F+tall+.8,z-.08,z+.08,rgb(40,42,46),M.Metal,true)
end

-- Floor zoning on the one Limestone hall floor (decor, a few long thin parts; tops staggered F+.02 / .03 / .035
-- / .06 so no two faces are coplanar; shop floors and carpets (F+.04..) cover the grid where they lie):
-- 20-stud terrazzo grid, a darker zone with a brass edge under every check-in island and its queue, a blue-grey
-- zone under the security queue, dark axes from the departure doors, teal rugs at the self check-in kiosks.
local function floorPlan(inside: Instance)
	local m=folder(inside,"FloorPlan")
	local grid=rgb(146,143,137)
	for x=T.x1+20,T.x2-20,20 do box(m,"FloorGrid",x-.15,x+.15,F,F+.02,FRONT+1,BACK-1,grid,M.Marble,true) end
	for _,z in {2450,2470,2490,2515} do box(m,"FloorGrid",T.x1+2,T.x2-2,F,F+.02,z-.15,z+.15,grid,M.Marble,true) end
	local offs: {{number}}={{-21,21},{-28,7},{-7,28},{-21,21}}
	for i,p in A.checkin do
		local o=offs[i] or offs[1]
		local lo,hi=p.X+o[1]-6,p.X+o[2]+6
		box(m,"IslandZone",lo,hi,F,F+.035,2441.5,2472,rgb(124,122,118),M.Marble,true)
		box(m,"IslandZoneEdge",lo,hi,F,F+.045,2441.2,2441.5,C.brass,M.Metal,true)
	end
	-- security approach (lanes 1-2 and lane 3), butting onto the island zones B / C (no overlap, no z-fight)
	for _,r in {{-62,22},{50,62}} do
		box(m,"SecurityZone",r[1],r[2],F,F+.035,2452,2466,rgb(108,116,128),M.Marble,true)
		box(m,"SecurityZoneEdge",r[1],r[2],F,F+.045,2451.7,2452,C.brass,M.Metal,true)
	end
	for _,x in {-150,150} do box(m,"DoorAxis",x-3,x+3,F,F+.03,2437,2472,rgb(96,102,112),M.Marble,true) end
	box(m,"DoorAxis",-3,3,F,F+.03,2437,2451.7,rgb(96,102,112),M.Marble,true)
	for _,cx in {-185,-115,115,185} do box(m,"KioskRug",cx-6.2,cx+6.2,F,F+.06,2456.4,2463.4,rgb(36,86,98),M.Carpet,true) end
	-- entrance mats (metal frame, dark grille mat) inside every door, and a terrazzo medallion (brass ring, dark
	-- field, teal centre) on each departures door axis between the doors and the queues
	for _,x in DOORS do
		box(m,"EntranceMatFrame",x-6.3,x+6.3,F,F+.05,FRONT+.9,FRONT+6.6,C.metalSoft,M.Metal,true)
		box(m,"EntranceMat",x-6,x+6,F,F+.07,FRONT+1.2,FRONT+6.3,rgb(46,48,52),M.Carpet,true)
	end
	for _,x in {-150,0,150} do
		post(m,"FloorMedallion",x,2445,F,F+.04,13,C.brass,M.Metal,true)
		post(m,"FloorMedallion",x,2445,F,F+.05,12.2,rgb(84,88,96),M.Marble,true)
		post(m,"FloorMedallion",x,2445,F,F+.065,5,BRAND,M.Marble,true)
	end
end

local function landside(inside: Instance,ticketText: string)
	floorPlan(inside)
	local m=folder(inside,"CheckinHall")
	local letters={"A","B","C","D"}
	-- desk offsets per island: B and C stop short of security lanes 1 and 3 (their walk-through arches)
	local offs: {{number}}={{-21,-14,-7,0,7,14,21},{-28,-21,-14,-7,0,7},{-7,0,7,14,21,28},{-21,-14,-7,0,7,14,21}}
	for i,p in A.checkin do checkinIsland(m,p.X,letters[i] or tostring(i),ticketText,offs[i] or offs[1]) end
	for _,cx in {-185,-115,115,185} do kioskGroup(m,cx,2460) end
	for _,cx in {-185,-115,115,185} do hangingSign(m,cx,2460,G+12,12,"SELF CHECK-IN",nil,roofY(2460)-.2) end
	-- departure boards on the security wall, security sign, lane numbers
	board(m,"DepartureBoard",Vector3.new(-44,G+21.5,SEC-.75),Vector3.new(0,0,-1),32,9,"DEPARTURES",DEPARTURES)
	board(m,"DepartureBoard",Vector3.new(44,G+21.5,SEC-.75),Vector3.new(0,0,-1),32,9,"DEPARTURES",DEPARTURES)
	panel(m,"SecuritySign",Vector3.new(0,G+18.6,SEC-.75),Vector3.new(0,0,-1),40,3.4,NAVY,"SECURITY  ·  GATES A1 – A3",{ink=SIGN_INK})
	for i,lx in A.lanes do
		panel(m,"LaneSign",Vector3.new(lx,G+14,SEC-.7),Vector3.new(0,0,-1),12,2.6,rgb(36,40,46),if i==3 then "LANE 3  ·  FAST TRACK" else "LANE "..i,{ink=SIGN_INK})
	end
	-- hanging overhead screen in the hall centre and departure monitors near the doors
	local ov=board(m,"DepartureBoard",Vector3.new(0,G+21,2446),Vector3.new(0,0,-1),26,7,"DEPARTURES",DEPARTURES)
	for _,s in {-1,1} do box(m,"SignRod",s*11-.08,s*11+.08,G+24.5,roofY(2446)-.2,2445.9,2446.1,C.metal,M.Metal,true) end
	local _=ov
	for _,x in {-150,0,150} do
		local px=x+9
		post(m,"MonitorPost",px,2441,F,F+7.5,.4,C.metal,M.Metal)
		flightInfo(screen(m,"DepartureMonitor",Vector3.new(px,F+8.6,2440.75),Vector3.new(0,0,-1),3.6,2.2,MONITOR),"monitor")
		flightInfo(screen(m,"DepartureMonitor",Vector3.new(px,F+8.6,2441.25),Vector3.new(0,0,1),3.6,2.2,MONITOR),"monitor")
	end
	-- wayfinding inside the doors
	local top=roofY(2444)-.2
	hangingSign(m,-150,2444,G+14,22,"←  CHECK-IN A        CHECK-IN B  →","EXIT  ·  TAXI  ·  CAR PARK",top)
	hangingSign(m,0,2452,G+15,26,"←  A – B     ↑ SECURITY · GATES     C – D  →","EXIT  ·  TAXI  ·  BUS",roofY(2452)-.2)
	hangingSign(m,150,2444,G+14,22,"←  CHECK-IN C        CHECK-IN D  →","EXIT  ·  TAXI  ·  BUS",top)
	hangingSign(m,0,2474,G+14,22,"↑  SECURITY  ·  ALL GATES","←  CHECK-IN  →",roofY(2474)-.2)
	-- trolleys at the doors, planters along the column line, seating near the glass
	for _,x in {-150,0,150} do trolleys(m,x-12,2434.5,4);trolleys(m,x+14,2434.5,3) end
	for i,x in {-187.5,-112.5,112.5,187.5} do
		planter(m,x-5,2477,6,3,false,i);planter(m,x+5,2477,6,3,false,i+1)
	end
	planSeats(m,nil,C.fabricCharcoal) -- by the doors, information desk, seating islands, baggage reclaim
	-- west end: information desk, coffee bar, ATM, restrooms door, seating
	box(m,"InfoDesk",-292,-280,F,F+3.6,2447,2451,C.white,M.Marble)
	box(m,"InfoDeskTop",-292.4,-279.6,F+3.6,F+3.9,2446.6,2451.4,BRAND,SM,true)
	hangingSign(m,-286,2449,G+13,10,"i  INFORMATION",nil,roofY(2449)-.2)
	airportPost(m,"info",Vector3.new(-286,F+3,2453),Vector3.new(0,0,-1))
	box(m,"CoffeeBar",-296,-270,F,F+3.6,2474,2477,C.oakDark,M.Wood)
	box(m,"CoffeeBarTop",-296.3,-269.7,F+3.6,F+3.9,2473.7,2477.3,C.stone,M.Marble,true)
	box(m,"CoffeeBack",-297,-270,F,F+3.4,2480.5,2484.4,C.oak,M.Wood)
	box(m,"CoffeeMachine",-290,-286,F+3.4,F+5.6,2482,2484,C.metalSoft,M.Metal,true)
	box(m,"CoffeeMachine",-283,-279,F+3.4,F+5.6,2482,2484,rgb(170,40,40),SM,true)
	panel(m,"CoffeeMenu",Vector3.new(-283,G+9,SEC-.85),Vector3.new(0,0,-1),24,3,C.screen,"COFFEE  ·  TEA  ·  SNACKS  TO GO",{ink=INK,screen=true})
	for i,x in {-292,-284,-276} do
		post(m,"HighTable",x,2466,F,F+3.6,.4,C.metal,M.Metal)
		post(m,"HighTableTop",x,2466,F+3.6,F+3.8,2.6,C.oak,M.Wood,true)
		stool(m,x-1.8,2466,3.2,C.fabricCharcoal);stool(m,x+1.8,2466,3.2,C.fabricCharcoal)
		local _=i
	end
	box(m,"ATM",-297.6,-296.4,F,F+5,2456,2459,rgb(60,66,74),SM)
	screen(m,"ATMScreen",Vector3.new(-296.3,F+3.6,2457.5),Vector3.new(1,0,0),2,1.2,"CASH")
	box(m,"RestroomDoor",-298.4,-298.3,F,F+8,2436,2442,rgb(40,44,50),SM,true)
	panel(m,"RestroomSign",Vector3.new(-298.2,F+9.5,2439),Vector3.new(1,0,0),7,1.6,rgb(36,40,46),"RESTROOMS",{ink=SIGN_INK})
	planter(m,-262,2440,4,4,true,3)
	-- luggage standing in the queues and next to the seats (decor; deterministic)
	for i=1,24 do
		local h=hash("bag"..i)
		local p=A.checkin[(i-1)%#A.checkin+1]
		local x=if i<=16 then p.X-16+(h%30) else ({-112,-38,38,112})[(i-17)%4+1]+(h%12)-6
		local z=if i<=16 then p.Z-6.8-(math.floor(h/30)%3)*3.6 else 2440.2
		local tall=1.6+(h%3)*.5
		box(m,"Suitcase",x-.7,x+.7,F,F+tall,z-.45,z+.45,pick(GOODS,h),SM,true)
		box(m,"SuitcaseHandle",x-.35,x+.35,F+tall,F+tall+.8,z-.08,z+.08,rgb(40,42,46),M.Metal,true)
	end
	-- loaded trolleys and more bags between the queue belts (people's luggage; decor)
	for i,p in A.checkin do
		for k=0,2 do
			local h=hash("qt"..i..k)
			local o=offs[i] or offs[1]
			local lo,hi=p.X+o[1]+3,p.X+o[#o]-3
			local x=lo+(h%math.max(1,math.floor(hi-lo)))
			local z=if k%2==0 then 2454.2 else 2450.6
			if k==2 then z=2447 end
			loadedTrolley(m,CFrame.new(x,F,z)*CFrame.Angles(0,math.rad(if h%2==0 then 90 else -90),0),h)
			suitcase(m,x+(if h%2==0 then -2.6 else 2.6),z+.2,h+1)
		end
	end
	-- two indoor trees framing the security queue on the centre door axis (clear of the walk line z 2443)
	planter(m,-10,2448.6,4,4,true,1);planter(m,10,2448.6,4,4,true,2)
	-- information pillar with flight monitors between check-in B and the security queue, a traveller's luggage
	post(m,"InfoPillar",-44,2449,F,F+8.4,1.6,rgb(60,64,70),M.Metal)
	for _,sd in {-1,1} do flightInfo(screen(m,"DepartureMonitor",Vector3.new(-44,F+7,2449+sd*.95),Vector3.new(0,0,sd),3.2,2,MONITOR),"monitor") end
	loadedTrolley(m,CFrame.new(-40.5,F,2451)*CFrame.Angles(0,math.rad(160),0),7)
	suitcase(m,-47.5,2452.5,5)
	-- double-sided advertising totems between the doors and the queues
	type Totem={x: number,text: string,color: Color3}
	local totems: {Totem}={{x=-225,text="MERIDIAN GRAND HOTEL\nyour stay abroad",color=rgb(52,72,120)},
		{x=-75,text="BUSINESS LOUNGE\nairside  ·  near gate A1",color=rgb(36,32,28)},
		{x=75,text="AI EMPIRE EXPO\nConvention Centre",color=rgb(150,58,48)},{x=225,text="CITY HOTEL\nstay downtown",color=rgb(120,92,52)}}
	for _,t in totems do
		box(m,"AdTotem",t.x-1.8,t.x+1.8,F,F+1,2439.4,2440.6,rgb(60,64,70),M.Metal)
		local face=screen(m,"AdTotemScreen",Vector3.new(t.x,F+5,2440),Vector3.new(0,0,-1),3.4,8,t.text,INK,t.text)
		face.Color=t.color
	end
	-- seating islands with planters on the door axes in front of the security wall; luggage wrap and a
	-- trolley return in the same band
	for _,x in {-150,150} do
		planter(m,x-12,2479.5,3,4,false,1);planter(m,x+12,2479.5,3,4,false,2)
		suitcase(m,x-4,2483,hash("ss"..x));suitcase(m,x+5.5,2476,hash("st"..x))
		loadedTrolley(m,CFrame.new(x+11.5,F,2475.4)*CFrame.Angles(0,math.rad(90),0),hash("sr"..x))
	end
	box(m,"LuggageWrap",-228,-224,F,F+2.6,2479,2483,rgb(70,110,150),SM)
	post(m,"LuggageWrapDrum",-226,2481,F+2.6,F+4.8,3,rgb(200,204,206),M.Metal,true)
	post(m,"LuggageWrapSignPost",-222.6,2482.8,F,F+5,.3,C.metal,M.Metal,true)
	panel(m,"LuggageWrapSign",Vector3.new(-222.6,F+5.8,2482.8),Vector3.new(0,0,-1),3.6,1.6,rgb(70,110,150),"LUGGAGE\nWRAP",{ink=INK})
	trolleys(m,226,2481.5,6)
	panel(m,"TrolleySign",Vector3.new(226,G+8.6,SEC-.95),Vector3.new(0,0,-1),6,1.4,rgb(36,40,46),"TROLLEYS",{ink=SIGN_INK})
	box(m,"ExchangeBooth",-277,-267,F,F+3.6,2436,2440,C.white,M.Marble)
	glass(box(m,"ExchangeGlass",-277,-267,F+3.6,F+7,2437.8,2438.2,C.glass,nil,true),.5)
	box(m,"ExchangeRoof",-277.4,-266.6,F+7,F+7.6,2435.6,2440.4,rgb(64,140,90),SM,true)
	panel(m,"ExchangeSign",Vector3.new(-272,F+8.6,2435.8),Vector3.new(0,0,-1),10,1.4,rgb(64,140,90),"CURRENCY EXCHANGE",{ink=INK},"CURRENCY EXCHANGE")
	-- end-wall light box over the information desk
	box(m,"MuralFrame",T.x1+1.5,T.x1+1.9,G+9.6,G+15.4,2452,2478,C.metal,M.Metal,true)
	local mural=screen(m,"MuralLightbox",Vector3.new(T.x1+2.05,G+12.5,2465),Vector3.new(1,0,0),25,5.2,"CITY AIRPORT\nshuttle flights to Port Meridian  ·  gate "..SHUTTLE_GATE,INK)
	mural.Color=BRAND
	-- real lights: six fixtures over the check-in hall
	for _,x in {-250,-150,-50,50,150,250} do
		local fixture=post(m,"PendantLight",x,2455,G+21,G+21.6,4,C.lightNeutral,M.Neon,true)
		box(m,"PendantRod",x-.06,x+.06,G+21.6,roofY(2455)-.2,2454.94,2455.06,C.metal,M.Metal,true)
		kit.light(fixture,60,1.1,C.lightNeutral)
	end
end

local function arrivals(inside: Instance)
	local m=folder(inside,"Arrivals")
	-- baggage carousel (racetrack), belt slats move client-side (PropFx belt), suitcases ride on it
	local cx,cz,len,w=276,2466,22,10
	box(m,"CarouselBase",cx-len/2,cx+len/2,F,F+1.6,cz-w/2,cz+w/2,C.metalSoft,M.Metal)
	for _,s in {-1,1} do post(m,"CarouselEnd",cx+s*len/2,cz,F,F+1.6,w,C.metalSoft,M.Metal) end
	box(m,"CarouselBelt",cx-len/2,cx+len/2,F+1.6,F+1.7,cz-w/2+.2,cz+w/2-.2,rgb(34,36,38),M.Rubber,true)
	for _,s in {-1,1} do post(m,"CarouselBeltEnd",cx+s*len/2,cz,F+1.6,F+1.7,w-.4,rgb(34,36,38),M.Rubber,true) end
	box(m,"CarouselSpine",cx-len/2+1,cx+len/2-1,F+1.6,F+3,cz-1.4,cz+1.4,rgb(70,76,82),M.Metal)
	for _,side in {-1,1} do
		local belt=folder(m,"CarouselSlats")
		local z=cz+side*3.4
		for i=0,9 do
			local x=cx-len/2+1+i*2.2
			box(belt,"Slat",x-.08,x+.08,F+1.7,F+1.76,z-1.5,z+1.5,rgb(90,94,98),M.Metal,true)
		end
		belt.WorldPivot=CFrame.new(cx,F+1.7,z)*(if side>0 then CFrame.new() else CFrame.Angles(0,math.pi,0))
		fx(belt,"belt",{FxAxis="x",FxRate=2,FxTravel=2.2,FxIdle="on"})
	end
	for i=0,5 do
		local side=if i%2==0 then 1 else -1
		local x=cx-9+i*3.4
		local hgt=1+(i%3)*.35
		box(m,"Suitcase",x-1,x+1,F+1.76,F+1.76+hgt,cz+side*3.4-.8,cz+side*3.4+.8,pick(GOODS,i*3+1),SM,true)
	end
	post(m,"BeltDisplayPost",cx,cz,F+3,G+8,.5,C.metal,M.Metal,true)
	local _=w
	local beltText="BELT 1\n"..BACK_NO.."  PORT MERIDIAN"
	flightInfo(screen(m,"BeltDisplay",Vector3.new(cx,G+9.5,cz),Vector3.new(0,0,-1),8,3,beltText,nil,beltText),"belt","BELT 1",BACK_NO)
	hangingSign(m,276,2452,G+14,22,"BAGGAGE RECLAIM  ·  BELT 1","ARRIVALS  ·  BELT 1",roofY(2452)-.2)
	panel(m,"ArrivalsSign",Vector3.new(270,G+15.5,FRONT+1.4),Vector3.new(0,0,1),22,2.8,rgb(36,40,46),"EXIT  ·  TAXI  ·  BUS  ·  CAR PARK WEST",{ink=SIGN_INK})
	board(m,"ArrivalBoard",Vector3.new(297.5,G+11,2470),Vector3.new(-1,0,0),20,6,"ARRIVALS",ARRIVALS)
	-- welcome lightbox for arriving passengers, high on the east end wall over baggage reclaim
	box(m,"MuralFrame",T.x2-1.9,T.x2-1.5,G+14.4,G+20.6,2443,2471,C.metal,M.Metal,true)
	local welcome=screen(m,"MuralLightbox",Vector3.new(T.x2-2.05,G+17.5,2457),Vector3.new(-1,0,0),27,5.8,"WELCOME TO\nBUSINESS CITY",INK)
	welcome.Color=rgb(150,58,48)
	-- car rental desks on the east wall, meeting point
	for i,z in {2440,2452} do
		box(m,"RentalDesk",292,297,F,F+3.6,z-3,z+3,C.white,M.Marble)
		panel(m,"RentalSign",Vector3.new(297.6,G+8,z),Vector3.new(-1,0,0),6,1.6,BRAND,"CAR RENTAL "..i,{ink=INK})
	end
	-- meeting point 4 studs off the walk-graph edge L270 -> arrival (it stood on that line at (262, 2446); metro request 7)
	post(m,"MeetingPointPost",264,2449.5,F,F+9,.4,C.metal,M.Metal,true)
	panel(m,"MeetingPointSign",Vector3.new(264,F+9.8,2449.5),Vector3.new(0,0,-1),6,2,rgb(64,140,90),"MEETING POINT",{ink=INK},"MEETING POINT")
	trolleys(m,262,2481,5)
	planter(m,250,2480,4,4,true,1)
	local over=post(m,"PendantLight",276,2466,G+20,G+20.6,4,C.lightNeutral,M.Neon,true)
	box(m,"PendantRod",275.94,276.06,G+20.6,roofY(2466)-.2,2465.94,2466.06,C.metal,M.Metal,true)
	kit.light(over,50,1,C.lightNeutral)
	-- GPS kiosk faces the arrival point (south)
	kit.kiosk(m,256,2444,F,1,"home","Route to my HQ")
end

------------------------------------------------------------------------------------------------ security
local function security(inside: Instance)
	local m=folder(inside,"Security")
	for i,lx in A.lanes do
		-- boarding-pass e-gates at the lane entry (pedestals collide, 4-stud passage), glass flaps decor
		for _,px in {lx-6.2,lx-.6} do
			box(m,"EGate",px-.4,px+.4,F,F+3.4,2465.6,2469,rgb(196,200,204),M.Metal)
			box(m,"EGateTop",px-.45,px+.45,F+3.4,F+3.6,2465.6,2469,NAVY,SM,true)
			local inward=if px<lx-3.4 then 1 else -1
			glass(box(m,"EGateFlap",math.min(px,px+inward*1.3),math.max(px,px+inward*1.3),F+1.2,F+3.2,2467.2,2467.4,rgb(150,200,220),nil,true),.5)
		end
		box(m,"EGateReader",lx-6.55,lx-5.85,F+3.6,F+4.2,2465.8,2466.4,rgb(120,220,140),M.Neon,true)
		-- divest (roller) table, X-ray machine through the wall opening, recompose table airside
		-- lane 3's table starts 2 studs further south: check-in island C's spine ends at z 2470.6 right behind it
		local t0=if lx+6>A.checkin[3].X-12 and lx<A.checkin[3].X then 2472 else 2470
		box(m,"DivestTable",lx+1,lx+6,F,F+3,t0,2482,C.metalSoft,M.Metal)
		local slats=folder(m,"XrayRollers")
		for k=0,5 do local z=2471+k*2;if z>t0+.5 then box(slats,"Roller",lx+1.2,lx+5.8,F+3,F+3.08,z-.1,z+.1,rgb(150,154,158),M.Metal,true) end end
		slats.WorldPivot=CFrame.new(lx+3.5,F+3,2476)*CFrame.Angles(0,-math.pi/2,0) -- local x = world +Z (towards the X-ray)
		fx(slats,"belt",{FxAxis="x",FxRate=1.2,FxTravel=2,FxIdle="on"})
		box(m,"XrayMachine",lx+.5,lx+6.5,F,F+6,2482,2488.4,rgb(214,216,214),SM)
		box(m,"XrayCurtain",lx+1,lx+6,F+3,F+5.2,2481.8,2482,rgb(30,32,36),M.Fabric,true)
		box(m,"XrayCurtain",lx+1,lx+6,F+3,F+5.2,2488.4,2488.6,rgb(30,32,36),M.Fabric,true)
		box(m,"XrayStripe",lx+.5,lx+6.5,F+5.2,F+5.6,2482,2488.4,BRAND,SM,true)
		box(m,"RecomposeTable",lx+1,lx+6,F,F+3,2488.4,2498,C.metalSoft,M.Metal)
		box(m,"RecomposeTop",lx+1,lx+6,F+3,F+3.1,2488.4,2498,rgb(150,154,158),M.Metal,true)
		-- walk-through metal detector (decor: players pass through), operator monitor
		box(m,"ScannerArch",lx-6,lx-5.2,F,F+7.6,SEC-1,SEC+1,rgb(200,202,204),SM,true)
		box(m,"ScannerArch",lx-1.8,lx-1,F,F+7.6,SEC-1,SEC+1,rgb(200,202,204),SM,true)
		box(m,"ScannerArchTop",lx-6,lx-1,F+7.6,F+8.6,SEC-1,SEC+1,rgb(200,202,204),SM,true)
		box(m,"ScannerLamp",lx-5.9,lx-1.1,F+8.6,F+8.8,SEC-.3,SEC+.3,rgb(120,220,140),M.Neon,true)
		box(m,"XrayDesk",lx+6.6,lx+7.8,F,F+3.4,2489,2493,rgb(70,74,78),SM)
		box(m,"XrayMonitor",lx+6.8,lx+7.6,F+3.4,F+4.8,2490,2492,C.screen,SM,true)
		-- tray stacks and trays
		local tz=if t0>2470 then 2475 else 2470 -- lane 3: south of its instruction post, clear of island C
		box(m,"TrayStack",lx+6.4,lx+8,F,F+2.6,tz,tz+2.2,rgb(110,116,122),SM)
		box(m,"Tray",lx+1.4,lx+3.4,F+3.08,F+3.4,2473,2475.6,rgb(110,116,122),SM,true)
		box(m,"Tray",lx+3.6,lx+5.6,F+3.1,F+3.42,2492,2494.6,rgb(110,116,122),SM,true)
		airportPost(m,"security",Vector3.new(lx-3.4,F+3,2489.5),Vector3.new(0,0,-1),"lane"..i)
	end
	-- serpentine queue in front of lane 2 (front row open at its e-gates), short funnels for lanes 1 and 3
	local function belt(x1: number,z1: number,x2: number,z2: number,n: number)
		box(m,"QueueBelt",math.min(x1,x2)-.05,math.max(x1,x2)+.05,F+2.6,F+2.85,math.min(z1,z2)-.05,math.max(z1,z2)+.05,NAVY,M.Fabric,true)
		for j=0,n do post(m,"QueuePost",x1+(x2-x1)*j/n,z1+(z2-z1)*j/n,F,F+3,.32,C.metalSoft,M.Metal,true) end
	end
	local e1,e2=A.lanes[2]-6.2,A.lanes[2]-.6 -- lane 2 e-gate pedestals
	belt(-26,2464.6,e1,2464.6,4);belt(e2,2464.6,20,2464.6,4)
	belt(-21,2461,20,2461,6);belt(-26,2457.4,15,2457.4,6);belt(-21,2453.8,20,2453.8,6)
	belt(-26,2457.4,-26,2464.6,1);belt(20,2453.8,20,2464.6,2)
	for k,lx in {A.lanes[1],A.lanes[3]} do
		local fast=k==2
		-- lane 1: the last desk of check-in B is the west side of its funnel
		if fast then belt(lx-6.6,2458,lx-6.6,2465,1) end
		belt(lx-.2,2458,lx-.2,2465,1)
		if fast then box(m,"FastTrackMat",lx-6.4,lx-.4,F,F+.04,2457,2465.4,rgb(150,40,46),M.Carpet,true) end
		post(m,"LaneStandPost",lx+1.6,2457.2,F,F+4.6,.3,C.metal,M.Metal,true)
		panel(m,"LaneStand",Vector3.new(lx+1.6,F+5.4,2457.2),Vector3.new(0,0,-1),3.2,1.8,if fast then rgb(150,40,46) else NAVY,
			if fast then "FAST TRACK\nbusiness · crew" else "LANE 1\nopen",{ink=INK},"PLEASE HAVE YOUR\nBOARDING PASS READY")
	end
	-- lane 2 queue entry sign, instruction screens over the divest tables, trays waiting on the rollers
	post(m,"QueueSignPost",-28.2,2452.2,F,F+5,.3,C.metal,M.Metal,true)
	panel(m,"QueueSign",Vector3.new(-28.2,F+5.8,2452.2),Vector3.new(0,0,-1),3.6,1.8,NAVY,"SECURITY\nqueue here",{ink=INK},"SECURITY")
	for i,lx in A.lanes do
		post(m,"InstructionPost",lx+6.9,2474,F,F+6.4,.3,C.metal,M.Metal,true)
		screen(m,"InstructionScreen",Vector3.new(lx+6.9,F+7.5,2474),Vector3.new(0,0,-1),4,2.4,"LAPTOPS · LIQUIDS\nIN A SEPARATE TRAY",rgb(150,220,240))
		for k,z in {2477.4,2479.6} do
			box(m,"Tray",lx+1.4,lx+5.6,F+3.08,F+3.4,z-1,z+1,rgb(110,116,122),SM,true)
			box(m,"TrayItem",lx+2+k*.6,lx+4.2+k*.4,F+3.4,F+3.9+k*.2,z-.7,z+.6,pick(GOODS,hash("tray"..i..k)),M.Fabric,true)
		end
		box(m,"LaneOpenLight",lx-5.2,lx-2,G+11.4,G+11.9,SEC-.66,SEC-.56,rgb(110,230,140),M.Neon,true)
	end
	-- lightboxes on the wall between the lanes: what to prepare
	for _,x in {-18,30} do
		box(m,"InfoFrame",x-6.4,x+6.4,F+3.6,F+10.4,SEC-.9,SEC-.62,C.metal,M.Metal,true)
		local ib=screen(m,"SecurityInfo",Vector3.new(x,F+7,SEC-1.05),Vector3.new(0,0,-1),12.4,6.4,"BEFORE SECURITY\nliquids max 100 ml · 1 l bag\nlaptops and tablets out\nno sharp objects",INK)
		ib.Color=rgb(28,64,96)
	end
	for _,x in {-50,50} do
		post(m,"InfoStandPost",x,2470,F,F+4.5,.3,C.metal,M.Metal,true)
		panel(m,"InfoStand",Vector3.new(x,F+5.5,2470),Vector3.new(0,0,-1),3,2,C.white,"LIQUIDS\nmax 100 ml",{ink=NAVY},"PLEASE HAVE YOUR\nBOARDING PASS READY")
	end
	local lamp=post(m,"PendantLight",0,2492,G+16,G+16.6,4,C.lightNeutral,M.Neon,true)
	box(m,"PendantRod",-.06,.06,G+16.6,roofY(2492)-.2,2491.94,2492.06,C.metal,M.Metal,true)
	kit.light(lamp,56,1,C.lightNeutral)
end

------------------------------------------------------------------------------------------------ airside
local SHOP_Z1,SHOP_Z2=SEC+.5,2499 -- shop band along the security wall
local function shopUnit(parent: Instance,name: string,x1: number,x2: number,title: string,tint: Color3,lit: boolean?,windows: boolean?): Model
	local m=folder(parent,name)
	box(m,"ShopWall",x2-1,x2,F,G+14,SHOP_Z1,SHOP_Z2,C.interior,M.Plaster)
	box(m,"ShopCeiling",x1,x2,G+14,G+14.6,SHOP_Z1,SHOP_Z2,C.plasterShade,M.Plaster,true)
	local fas=box(m,"ShopFascia",x1,x2,G+11.2,G+14,SHOP_Z2-.6,SHOP_Z2,tint,SM,true)
	label(fas,title,Enum.NormalId.Back,{ink=INK})
	-- coloured portal pilaster at the shop's east edge and a blade sign readable along the concourse
	box(m,"ShopPilaster",x2-1.2,x2,F,G+14,SHOP_Z2-.2,SHOP_Z2+.5,tint:Lerp(rgb(20,20,22),.2),SM,true)
	local blade=mk(m,"ShopBladeSign",Vector3.new(4.6,2,.35),CFrame.lookAt(Vector3.new(x1+3,G+12.6,SHOP_Z2+2.6),Vector3.new(x1+4,G+12.6,SHOP_Z2+2.6)),tint,SM,true)
	label(blade,title,Enum.NormalId.Front,{ink=INK});label(blade,title,Enum.NormalId.Back,{ink=INK})
	box(m,"BladeArm",x1+2.9,x1+3.1,G+13.6,G+13.8,SHOP_Z2,SHOP_Z2+5,C.metal,M.Metal,true)
	box(m,"ShopGlow",x1,x2,G+11,G+11.2,SHOP_Z2-.8,SHOP_Z2-.2,C.lightWarm,M.Neon,true)
	box(m,"ShopFloor",x1,x2-1,F,F+.04,SHOP_Z1,SHOP_Z2,tint:Lerp(rgb(235,232,226),.75),M.Marble,true)
	box(m,"ShopBackWall",x1,x2-1,F,G+14,SHOP_Z1,SHOP_Z1+.12,tint:Lerp(rgb(40,40,44),.25),SM,true)
	for _,z in {SHOP_Z1+3.5,SHOP_Z1+9} do box(m,"ShopLightStrip",x1+1.5,x2-2.5,G+13.7,G+14,z-.3,z+.3,C.lightWarm,M.Neon,true) end
	for _,g in (if windows==false then {} else {{x1+.4,x1+5.5},{x2-6.5,x2-1}}) :: {{number}} do
		glass(box(m,"ShopWindow",g[1],g[2],F,G+11,SHOP_Z2-.5,SHOP_Z2-.3,C.glass),.6)
		box(m,"ShopWindowSill",g[1],g[2],F,F+1,SHOP_Z2-.7,SHOP_Z2-.1,tint:Lerp(rgb(40,40,44),.4),SM,true)
	end
	if lit then
		local l=box(m,"ShopLight",(x1+x2)/2-3,(x1+x2)/2+3,G+13.6,G+14,2490,2494,C.lightWarm,M.Neon,true)
		kit.light(l,40,.9,C.lightWarm)
	end
	return m
end
-- frame on the north wall of the shop band, front facing +Z, centred at x
local function northWall(x: number,depth: number): CFrame
	local o=Vector3.new(x,F,SHOP_Z1+depth)
	return CFrame.lookAt(o,o+Vector3.new(0,0,1))
end
local function sideWall(x: number,z: number,facing: number,depth: number): CFrame
	local o=Vector3.new(x+facing*depth,F,z)
	return CFrame.lookAt(o,o+Vector3.new(facing,0,0))
end

local function lounge(inside: Instance)
	local L=A.lounge
	local m=folder(inside,"BusinessLounge")
	m:AddTag("BusinessLounge");m:SetAttribute("Purpose","BusinessLounge");m:SetAttribute("BuildingId","airport")
	local ex=L.x2 -- east wall (outer face)
	local dz1,dz2=2499,2506
	box(m,"LoungeWall",ex-1.2,ex,F,G+14,L.z1,dz1,C.oakDark,M.Wood)
	box(m,"LoungeLintel",ex-1.2,ex,F+9,G+14,dz1,dz2,C.oakDark,M.Wood)
	box(m,"LoungeWall",ex-1.2,ex,F,G+14,dz2,2512,C.oakDark,M.Wood)
	glass(box(m,"LoungeGlass",ex-.8,ex-.4,F,G+13.4,2512,L.z2,C.glass),.5)
	box(m,"LoungeGlassHead",ex-1.2,ex,G+13.4,G+14,2512,L.z2,C.oakDark,M.Wood)
	box(m,"LoungeCeiling",L.x1+1.5,ex,G+14,G+14.6,L.z1,L.z2,C.oakLight,M.WoodPlanks)
	box(m,"LoungeCarpet",L.x1+1.5,ex-1.2,F,F+.05,L.z1,L.z2-.8,rgb(96,82,72),M.Carpet,true)
	local entry=invisible(box(m,"LoungeEntrance",ex-1.2,ex,F,F+9,dz1,dz2,C.white,SM,true))
	entry:SetAttribute("Purpose","BusinessLounge")
	local sgn=mk(m,"LoungeSign",Vector3.new(11,2.6,.3),CFrame.lookAt(Vector3.new(ex+.2,G+10.5,2492),Vector3.new(ex+1.2,G+10.5,2492)),rgb(36,32,28),SM,true)
	label(sgn,"BUSINESS LOUNGE",Enum.NormalId.Front,{ink=C.brass})
	box(m,"LoungeSignGlow",ex,ex+.15,G+9,G+9.2,2486.5,2497.5,C.brass,M.Neon,true)
	-- reception
	box(m,"LoungeReception",-250,-243,F,F+3.6,2489,2495,C.oakDark,M.Wood)
	box(m,"LoungeReceptionTop",-250.3,-242.7,F+3.6,F+3.9,2488.7,2495.3,C.stone,M.Marble,true)
	panel(m,"LoungeLogo",Vector3.new(-252,G+7.5,L.z1+.3),Vector3.new(0,0,1),14,3,rgb(36,32,28),"BUSINESS LOUNGE",{ink=C.brass})
	airportPost(m,"lounge",Vector3.new(-252.5,F+3,2492),Vector3.new(1,0,0))
	-- bar with back shelves and stools
	shelf(northWall(-280,1.6),m,22,8,1.6,3,5,BOTTLES)
	box(m,"LoungeBar",-292,-268,F,F+3.8,2491,2494,rgb(60,44,34),M.Wood)
	box(m,"LoungeBarTop",-292.3,-267.7,F+3.8,F+4.1,2490.6,2494.3,C.stone,M.Marble,true)
	for x=-289,-271,4.5 do stool(m,x,2496,3.4,rgb(120,86,62)) end
	-- buffet island with food trays under a glass guard
	box(m,"Buffet",-266,-257,F,F+3.4,2492,2496,C.white,M.Marble)
	for i=0,3 do local x=-265.4+i*2.1;box(m,"BuffetTray",x,x+1.8,F+3.4,F+3.8,2492.6,2495.4,pick(BREAD,i),SM,true) end
	glass(box(m,"SneezeGuard",-266,-257,F+5,F+5.2,2492,2496,C.glass,nil,true),.4)
	-- three conversation groups (four teal leather armchairs round a low table, each on its own cream rug, aisles
	-- of 3+ studs between them) and two sofas with round coffee tables; a window bar along the apron glass
	local leather,cushion=rgb(38,98,106),rgb(196,206,200)
	for g,c in {{-284,2517,0},{-270,2517,18},{-256,2517,-12}} do
		local cx,cz=c[1],c[2]
		box(m,"LoungeRug",cx-5.6,cx+5.6,F+.05,F+.09,cz-5.6,cz+5.6,rgb(204,192,168),M.Fabric,true)
		post(m,"LoungeTable",cx,cz,F,F+1.3,.6,C.metal,M.Metal)
		post(m,"LoungeTableTop",cx,cz,F+1.3,F+1.5,3,C.oakDark,M.Wood,true)
		box(m,"TableBook",cx-.5,cx+.4,F+1.5,F+1.65,cz-.3,cz+.4,pick(BOOKS,g),SM,true)
		for k=0,3 do
			local a=math.rad(45+90*k+c[3])
			local o=Vector3.new(math.sin(a),0,math.cos(a))
			armchair(m,cx+o.X*3.8,cz+o.Z*3.8,-o,leather,cushion)
		end
	end
	for _,x in {-284,-262} do
		box(m,"LoungeSofa",x-6,x+6,F,F+1.6,2502,2505,rgb(70,74,80),M.Fabric)
		box(m,"LoungeSofaBack",x-6,x+6,F+1.6,F+3.6,2501.4,2502,rgb(70,74,80),M.Fabric,true)
		for _,dx in {-3,3} do box(m,"SofaCushion",x+dx-2.6,x+dx+2.6,F+1.6,F+1.9,2502.2,2504.8,rgb(96,100,108),M.Fabric,true) end
		post(m,"CoffeeTable",x,2507.4,F,F+1.4,3.4,C.oakDark,M.Wood)
	end
	box(m,"WindowBar",-296,-270,F,F+3.6,2526.5,2528.4,C.oakDark,M.Wood)
	for x=-294,-272,3.6 do stool(m,x,2525.2,3.2,C.fabricCharcoal) end
	planter(m,-296.2,2523.4,3,3,true,1);planter(m,-243,2526,3,3,true,2);planter(m,-243,2508,3,3,false,3)
	-- west feature wall: dark wood panelling, flight information board, two art panels; rug, floor lamps,
	-- magazine rack by the reception
	local wx=L.x1+.3 -- inner face of the end wall
	box(m,"LoungePanelling",L.x1,wx,F,G+14,L.z1+.5,L.z2-1,rgb(74,54,40),M.WoodPlanks,true)
	board(m,"LoungeFlightBoard",Vector3.new(wx+.35,G+8.2,2503),Vector3.new(1,0,0),14,6.5,"DEPARTURES",DEPARTURES)
	for n,z in {2490,2516.5} do
		box(m,"ArtFrame",wx,wx+.25,F+4.6,F+11.4,z-4.4,z+4.4,C.brass,M.Metal,true)
		box(m,"ArtCanvas",wx+.25,wx+.35,F+5,F+11,z-4,z+4,rgb(232,226,212),SM,true)
		for j=0,2 do
			local zz=z-3+j*2.1+(n-1)*.4
			box(m,"ArtBlock",wx+.35,wx+.42,F+5.6+((j+n)%2)*1.6,F+8.4+((j+n)%3)*.8,zz-.8,zz+.8,pick({rgb(176,70,48),rgb(40,90,130),rgb(214,170,70),rgb(70,110,84)},j+n),SM,true)
		end
	end
	for _,p in {{-292,2523.2},{-247,2513}} do
		post(m,"FloorLampStem",p[1],p[2],F,F+6.4,.2,C.brass,M.Metal,true)
		post(m,"FloorLampShade",p[1],p[2],F+6.4,F+7.6,1.6,C.lightWarm,M.Neon,true)
	end
	-- 2 studs long: its north end stays 1.6 studs off the walk-graph edge loungeIn -> buffet (metro request 7)
	box(m,"MagazineRack",-249.5,-248.5,F,F+4.2,2496.5,2498.5,C.oakDark,M.Wood,true)
	for j=0,2 do box(m,"Magazine",-248.5,-248.4,F+1+j*1.1,F+1.9+j*1.1,2496.8,2498.2,pick(BOOKS,j+2),SM,true) end
	for _,p in {{-282,2500},{-284,2517},{-270,2517},{-256,2517}} do
		post(m,"LoungePendant",p[1],p[2],G+12.4,G+13,3,C.lightWarm,M.Neon,true)
		box(m,"PendantRod",p[1]-.05,p[1]+.05,G+13,G+14,p[2]-.05,p[2]+.05,C.metal,M.Metal,true)
	end
	kit.light(box(m,"LoungeLight",-276,-270,G+13.6,G+14,2496,2500,C.lightWarm,M.Neon,true),40,.9,C.lightWarm)
	kit.light(box(m,"LoungeLight",-266,-260,G+13.6,G+14,2514,2518,C.lightWarm,M.Neon,true),40,.8,C.lightWarm)
end

local function crewRoom(inside: Instance)
	local m=folder(inside,"CrewRoom")
	local x1,x2=A.lounge.x2,-214
	box(m,"CrewWall",x2-1.2,x2,F,G+12,SHOP_Z1,SHOP_Z2,C.interior,M.Plaster)
	box(m,"CrewWall",x1,-232,F,G+12,SHOP_Z2-1.2,SHOP_Z2,C.interior,M.Plaster)
	box(m,"CrewWall",-227,x2-1.2,F,G+12,SHOP_Z2-1.2,SHOP_Z2,C.interior,M.Plaster)
	box(m,"CrewLintel",-232,-227,F+8.5,G+12,SHOP_Z2-1.2,SHOP_Z2,C.interior,M.Plaster)
	box(m,"CrewCeiling",x1,x2,G+12,G+12.6,SHOP_Z1,SHOP_Z2,C.plasterShade,M.Plaster,true)
	panel(m,"CrewSign",Vector3.new(-229.5,F+10,SHOP_Z2+.2),Vector3.new(0,0,1),6,1.4,rgb(36,40,46),"CREW ONLY",{ink=SIGN_INK})
	box(m,"Lockers",-236.5,-224,F,F+7,SHOP_Z1,SHOP_Z1+1.6,rgb(110,126,140),M.Metal)
	for x=-235,-225.5,1.6 do box(m,"LockerSeam",x-.04,x+.04,F+.3,F+6.8,SHOP_Z1+1.6,SHOP_Z1+1.7,rgb(60,70,80),SM,true) end
	box(m,"CrewTable",-222,-217,F,F+2.6,2489,2494,C.white,SM)
	for _,z in {2488,2495} do box(m,"CrewChair",-220.4,-218.6,F,F+1.7,z-.9,z+.9,C.fabricBlue,M.Fabric) end
	box(m,"CrewCounter",-236.6,-234.6,F,F+3.4,2489,2496,C.oak,M.Wood)
	box(m,"CrewCoffee",-236.4,-235,F+3.4,F+5,2490,2491.6,C.metalSoft,M.Metal,true)
	screen(m,"CrewBriefing",Vector3.new(-215.4,G+7.5,2492),Vector3.new(-1,0,0),8,3.4,"CREW BRIEFING\n"..OUT_NO.." → PORT MERIDIAN  ·  GATE "..SHUTTLE_GATE.."\nWX: CLEAR  ·  WIND 270/08",rgb(150,220,200))
	local light=box(m,"CrewLight",-229,-223,G+11.6,G+12,2490,2494,C.lightNeutral,M.Neon,true)
	kit.light(light,28,.8,C.lightNeutral)
	local marker=invisible(mk(m,"CrewRoom",Vector3.new(2,5,2),A.crewRoom,C.white,SM,true))
	marker:SetAttribute("Purpose","CrewRoom");marker:SetAttribute("Door",Vector3.new(-229.5,F+3,SHOP_Z2+2))
	airportPost(m,"crew",Vector3.new(-222,F+3,2496),Vector3.new(0,0,-1))
end

local function shops(inside: Instance)
	local m=folder(inside,"Shops")
	-- newsagent
	local news=shopUnit(m,"Newsagent",-214,-162,"NEWS  &  BOOKS",rgb(176,56,48),true)
	for i,x in {-206,-193,-180} do shelf(northWall(x,1.4),news,12,8,1.4,4,hash("news"..i),if i==2 then BOOKS else GOODS) end
	shelf(sideWall(-213,2492,1,1.4),news,10,7,1.4,4,11,BOOKS)
	for i,x in {-196,-184} do
		box(news,"BookTable",x-3,x+3,F,F+2.6,2491,2495,C.oak,M.Wood)
		for j=0,2 do box(news,"BookStack",x-2.6+j*1.9,x-1.2+j*1.9,F+2.6,F+3.2+((i+j)%2)*.4,2491.6,2494.4,pick(BOOKS,i*3+j),SM,true) end
	end
	box(news,"ShopCounter",-177,-170,F,F+3.6,2492,2495,C.white,SM)
	box(news,"Till",-174.5,-172.5,F+3.6,F+4.6,2493,2494.4,C.screen,SM,true)
	local tick=box(news,"NewsTicker",-212,-172,G+9.6,G+10.8,SHOP_Z1+.05,SHOP_Z1+.25,C.screen,SM,true)
	local tl=label(tick,"AI EMPIRE EXPO OPENS IN BUSINESS CITY  ·  PORT MERIDIAN SHUTTLE "..OUT_NO.." BOARDS AT GATE "..SHUTTLE_GATE.."  ·  NEW CONVENTION CENTRE SOLD OUT",Enum.NormalId.Back,{ink=rgb(255,120,100),screen=true,align=Enum.TextXAlignment.Left})
	tl.TextScaled=false;tl.TextSize=32;tl.TextWrapped=false;tl.Size=UDim2.fromScale(1,1);tl.Position=UDim2.new()
	fx(tick,"ticker",{FxRate=80,FxIdle="on"})
	airportPost(news,"shop",Vector3.new(-173.5,F+3,2489.5),Vector3.new(0,0,1),"news")
	-- bakery cafe
	local cafe=shopUnit(m,"BakeryCafe",-162,-114,"BAKERY  ·  CAFÉ",rgb(150,104,62),true)
	box(cafe,"CafeCounter",-158,-130,F,F+3.6,2492,2495,C.oakDark,M.Wood)
	box(cafe,"CafeCounterTop",-158.3,-129.7,F+3.6,F+3.9,2491.7,2495.3,C.stone,M.Marble,true)
	glass(box(cafe,"PastryCase",-156,-140,F+3.9,F+5.6,2492.2,2494.8,C.glass,nil,true),.78)
	box(cafe,"PastryShelf",-155.8,-140.2,F+4.75,F+4.85,2492.4,2494.6,C.metalSoft,M.Metal,true)
	for i=0,2 do box(cafe,"Pastries",-155.6+i*5.2,-151+i*5.2,F+3.95,F+4.5,2492.6,2494.4,pick(BREAD,i),SM,true) end
	for i=0,3 do box(cafe,"Cakes",-155.4+i*3.9,-152.6+i*3.9,F+4.85,F+5.35,2492.8,2494.2,pick({rgb(236,214,180),rgb(120,72,46),rgb(214,110,120),rgb(240,236,226)},i),SM,true) end
	-- till and cups on the counter, pendant lamps, a coffee-bean shelf on the back wall
	box(cafe,"Till",-137.5,-135.5,F+3.9,F+4.9,2493,2494.4,C.screen,SM,true)
	for i=0,3 do post(cafe,"Cup",-133.6+i*.9,2493.2,F+3.9,F+4.5,.5,if i%2==0 then C.white else rgb(196,150,96),SM,true) end
	for _,x in {-152,-144,-136} do
		post(cafe,"CafePendant",x,2493.5,G+9.2,G+10,1.4,C.lightWarm,M.Neon,true)
		box(cafe,"PendantRod",x-.05,x+.05,G+10,G+14,2493.45,2493.55,C.metal,M.Metal,true)
	end
	for k=0,1 do
		local y=F+4.4+k*1.3
		box(cafe,"BeanShelf",-142,-131,y,y+.15,SHOP_Z1+.12,SHOP_Z1+1.2,C.oakDark,M.Wood,true)
		for j=0,4 do box(cafe,"CoffeeBag",-141.4+j*2.1,-140+j*2.1,y+.15,y+1,SHOP_Z1+.3,SHOP_Z1+1,pick({rgb(120,72,46),rgb(196,62,58),rgb(44,48,54),rgb(214,170,70)},j+k),SM,true) end
	end
	box(cafe,"CafeBackCounter",-160,-130,F,F+3.6,SHOP_Z1,SHOP_Z1+2.5,C.oak,M.Wood)
	for _,x in {-154,-148} do box(cafe,"EspressoMachine",x-2,x+2,F+3.6,F+6,SHOP_Z1+.3,SHOP_Z1+2,rgb(176,178,180),M.Metal,true) end
	for i,t in {"COFFEE","PASTRIES","TEA & JUICE"} do
		screen(cafe,"MenuBoard",Vector3.new(-156+(i-1)*9,G+9,SHOP_Z1+.25),Vector3.new(0,0,1),8,3,t,rgb(250,236,200))
	end
	shelf(sideWall(-161,2490,1,1.2),cafe,6,6,1.2,3,4,BREAD)
	for i,x in {-125,-118} do
		for j,z in {2489.5,2495} do tableSet(cafe,x,z,2,C.oak,rgb(70,74,78),2.6);local _=i+j end
	end
	airportPost(cafe,"shop",Vector3.new(-144,F+3,2489.5),Vector3.new(0,0,1),"cafe")
	-- electronics
	local tech=shopUnit(m,"Electronics",-114,-70,"TECH  &  TRAVEL",rgb(40,90,150),true)
	for i,x in {-106,-94,-82} do shelf(northWall(x,1.4),tech,11,8,1.4,4,hash("tech"..i),TECH) end
	for i,x in {-100,-88} do
		box(tech,"DisplayTable",x-3.5,x+3.5,F,F+3,2491,2495,C.white,SM)
		for j=0,2 do box(tech,"Device",x-2.8+j*2.2,x-1.4+j*2.2,F+3,F+3.15,2492,2494,pick(TECH,i+j),SM,true) end
	end
	box(tech,"ShopCounter",-83,-77.5,F,F+3.6,2492,2495.5,C.white,SM)
	screen(tech,"PromoScreen",Vector3.new(-71.4,G+8,2492),Vector3.new(-1,0,0),8,4.5,"NOISE-CANCELLING\nHEADPHONES",rgb(140,210,255))
	airportPost(tech,"shop",Vector3.new(-80.25,F+3,2489.5),Vector3.new(0,0,1),"tech")
	local techAd=screen(tech,"WallAdvert",Vector3.new(-69.8,F+7.5,2492),Vector3.new(1,0,0),10,7,"TECH & TRAVEL\nchargers · headphones\nadapters · power banks",INK)
	techAd.Color=rgb(40,90,150)
	-- walk-through duty free between and after the lanes
	local dfree=folder(m,"DutyFree")
	for _,g in {{-50,-10},{10,50}} do
		for i=0,2 do
			local x=g[1]+5+i*12.5
			box(dfree,"PerfumeGondola",x-3,x+3,F,F+3.2,2489,2494,C.white,M.Marble)
			glass(box(dfree,"PerfumeCase",x-2.8,x+2.8,F+3.2,F+4.6,2489.2,2493.8,C.glass,nil,true),.5)
			for j=0,2 do box(dfree,"Perfume",x-2.4+j*1.7,x-1.4+j*1.7,F+3.2,F+3.9+(j%2)*.4,2490.5,2492.5,pick(BOTTLES,i+j+2),M.Glass,true) end
		end
		local mid=(g[1]+g[2])/2
		post(dfree,"DutyFreeTotem",mid,2496.5,F,F+6,1.4,C.brass,M.Metal,true)
	end
	hangingSign(dfree,-30,2493,G+12.5,14,"DUTY FREE",nil,RY[3]-.2)
	hangingSign(dfree,30,2493,G+12.5,14,"DUTY FREE",nil,RY[3]-.2)
	local store=shopUnit(m,"DutyFreeStore",70,150,"DUTY FREE",rgb(30,30,34),true)
	box(store,"ShopWall",70,71,F,G+14,SHOP_Z1,SHOP_Z2-6,C.interior,M.Plaster)
	local dfAd=screen(store,"WallAdvert",Vector3.new(69.8,F+7.5,2490),Vector3.new(-1,0,0),8,7,"DUTY FREE\nfragrance · watches\nsweets · travel retail",C.brass)
	dfAd.Color=rgb(30,30,34)
	for i,x in {78,93,108,123,138} do shelf(northWall(x,1.6),store,14,8.5,1.6,4,hash("df"..i),if i%2==0 then BOTTLES else GOODS) end
	for i,x in {84,104,124} do
		box(store,"Gondola",x-5,x+5,F,F+4.2,2491,2494,C.white,SM)
		for j=0,3 do box(store,"Goods",x-4.6+j*2.4,x-2.6+j*2.4,F+4.2,F+5+((i+j)%3)*.3,2491.3,2493.7,pick(GOODS,i*4+j),SM,true) end
	end
	box(store,"CashDesk",131,139,F,F+3.6,2493,2496,C.white,SM)
	airportPost(store,"shop",Vector3.new(135,F+3,2490),Vector3.new(0,0,1),"dutyfree")
	-- restrooms block (signage only - the doorways are dark recesses)
	local wc=folder(m,"Restrooms")
	box(wc,"RestroomWall",150,168,F,G+14,SHOP_Z2-1,SHOP_Z2,rgb(214,210,200),M.Plaster)
	box(wc,"RestroomWall",167,168,F,G+14,SHOP_Z1,SHOP_Z2-1,rgb(214,210,200),M.Plaster)
	box(wc,"RestroomCap",150,168,G+14,G+14.6,SHOP_Z1,SHOP_Z2,C.plasterShade,M.Plaster,true)
	for i,x in {154.5,163.5} do
		box(wc,"RestroomDoorway",x-2.2,x+2.2,F,F+8,SHOP_Z2,SHOP_Z2+.1,rgb(40,44,50),SM,true)
		panel(wc,"RestroomSign",Vector3.new(x,F+9.3,SHOP_Z2+.2),Vector3.new(0,0,1),4.2,1.4,rgb(36,40,46),if i==1 then "WOMEN" else "MEN",{ink=SIGN_INK})
	end
	panel(wc,"RestroomSign",Vector3.new(159,G+12.6,SHOP_Z2+.2),Vector3.new(0,0,1),14,1.8,rgb(36,40,46),"RESTROOMS  ·  BABY CHANGE",{ink=SIGN_INK})
	box(wc,"WaterFountain",158,160,F,F+3.4,SHOP_Z2,SHOP_Z2+1.2,rgb(180,184,188),M.Metal)
end

local function foodCourt(inside: Instance)
	local m=folder(inside,"FoodCourt")
	type Stall={x1: number,x2: number,title: string,tint: Color3,menu: {string}}
	local stalls: {Stall}={
		{x1=168,x2=211,title="GRILL HOUSE",tint=rgb(176,70,48),menu={"BURGER  9","GRILLED WRAP  8","FRIES  4"}},
		{x1=211,x2=253,title="NOODLE BAR",tint=rgb(170,40,40),menu={"RAMEN  11","FRIED RICE  9","DUMPLINGS  7"}},
		{x1=253,x2=298.5,title="GREEN DELI",tint=rgb(70,140,80),menu={"SALAD BOWL  10","SANDWICH  7","SMOOTHIE  5"}},
	}
	for i,s in stalls do
		local x1,x2=s.x1,s.x2
		local st=shopUnit(m,"FoodStall",x1,x2,s.title,s.tint,i==2,false)
		box(st,"StallCounter",x1+2,x2-5,F,F+3.6,2494,2497,s.tint:Lerp(C.white,.55),SM)
		box(st,"StallCounterTop",x1+1.7,x2-4.7,F+3.6,F+3.9,2493.7,2497.3,C.stone,M.Marble,true)
		for j=0,2 do box(st,"FoodTray",x1+4+j*4,x1+7+j*4,F+3.9,F+4.3,2494.6,2496.6,pick(BREAD,i+j),SM,true) end
		box(st,"KitchenCounter",x1+2,x2-7,F,F+3.6,SHOP_Z1,SHOP_Z1+2.6,C.metalSoft,M.Metal)
		box(st,"ExtractorHood",x1+4,x2-6,G+9,G+11,SHOP_Z1,SHOP_Z1+3,rgb(176,178,180),M.Metal,true)
		box(st,"Fridge",x2-6,x2-3,F,F+7,SHOP_Z1+3,SHOP_Z1+5.5,rgb(200,204,206),M.Metal)
		local menu=s.menu
		for j,t in menu do screen(st,"MenuScreen",Vector3.new(x1+7+(j-1)*10,G+12.2,SHOP_Z1+3.2),Vector3.new(0,0,1),9,2.4,t,rgb(250,236,200)) end
		airportPost(st,"shop",Vector3.new((x1+x2)/2,F+3,2492),Vector3.new(0,0,1),"food"..i)
	end
	-- seating at the east end (gate band) with a window counter
	local seats=folder(m,"FoodCourtSeating")
	for _,x in {246,258,270,282} do
		for _,z in {2505.5,2513,2520.5} do -- first row 2+ studs off the stall walls (CityPlan walk line z 2500.5)
			local k=hash(tostring(x)..":"..tostring(z))
			tableSet(seats,x,z,4,C.white,pick({rgb(196,90,60),rgb(70,120,160),rgb(90,140,90)},k),3)
		end
	end
	box(seats,"WindowCounter",242,296,F,F+3.6,2526.6,2528.4,C.oak,M.Wood)
	for x=244,294,4.2 do stool(seats,x,2525.2,3.2,rgb(70,74,78)) end
	for i,z in {2510,2518,2526} do planter(seats,239.5,z,2.2,5,false,i) end
	hangingSign(seats,268,2502,G+13,18,"FOOD COURT",nil,roofY(2502)-.2)
	box(seats,"MuralFrame",T.x2-1.9,T.x2-1.5,G+8.6,G+15.4,2503,2527,C.metal,M.Metal,true)
	local mural=screen(seats,"MuralLightbox",Vector3.new(T.x2-2.05,G+12,2515),Vector3.new(-1,0,0),23,6.4,"BON VOYAGE\nsee you back in Business City",INK)
	mural.Color=rgb(150,58,48)
	local l=box(seats,"FoodCourtLight",265,271,G+21,G+21.6,2512,2518,C.lightWarm,M.Neon,true)
	box(seats,"PendantRod",267.94,268.06,G+21.6,roofY(2515)-.2,2514.94,2515.06,C.metal,M.Metal,true)
	kit.light(l,56,1,C.lightWarm)
end

local function restaurant(inside: Instance)
	local m=folder(inside,"Restaurant")
	local x1,x2=-158,-42
	box(m,"RestaurantFloor",x1,x2,F,F+.05,2508,2528.4,C.oakLight,M.WoodPlanks,true)
	for _,s in {{x1,-106},{-94,x2}} do planter(m,(s[1]+s[2])/2,2508.6,s[2]-s[1],1.6,false,1) end
	box(m,"HostStand",-101.5,-98.5,F,F+3.8,2508,2510,C.oakDark,M.Wood)
	hangingSign(m,-100,2507,G+13,20,"SKYLINE RESTAURANT",nil,roofY(2507)-.2)
	for _,z in {2514.5,2523} do
		for _,x in {-142,-128,-114,-84,-70,-56} do tableSet(m,x,z,4,C.white,rgb(120,60,50),3.2) end
	end
	box(m,"RestaurantBar",-157,-152,F,F+3.8,2512,2527,C.oakDark,M.Wood)
	shelf(sideWall(-158,2519.5,1,1.2),m,12,8,1.2,3,7,BOTTLES)
	for _,z in {2514,2518,2522,2526} do stool(m,-150.5,z,3.4,rgb(120,60,50)) end
	for _,x in {-128,-70} do
		post(m,"RestaurantPendant",x,2518.8,G+12,G+12.6,3,C.lightWarm,M.Neon,true)
		box(m,"PendantRod",x-.05,x+.05,G+12.6,roofY(2518.8)-.2,2518.75,2518.85,C.metal,M.Metal,true)
	end
	local l=post(m,"RestaurantLight",-100,2518,G+16,G+16.6,4,C.lightWarm,M.Neon,true)
	box(m,"PendantRod",-100.06,-99.94,G+16.6,roofY(2518)-.2,2517.94,2518.06,C.metal,M.Metal,true)
	kit.light(l,56,1,C.lightWarm)
	airportPost(m,"shop",Vector3.new(-100,F+3,2511.5),Vector3.new(0,0,-1),"restaurant")
end

local function quietZone(inside: Instance)
	local m=folder(inside,"QuietZone")
	for i,x in {48,58,68,78,124,134,144,154} do
		local f=CFrame.lookAt(Vector3.new(x,F,2522),Vector3.new(x,F,2530))
		lbox(f,m,"LoungerBase",-1.3,1.3,0,1.2,-2.6,2.6,C.metal,M.Metal)
		local back=wedge(m,"LoungerBack",Vector3.new(2.6,2.6,2.2),f*CFrame.new(0,2.5,1.5),pick({C.fabricSand,C.sage},i),M.Fabric,true)
		local _=back
		lbox(f,m,"LoungerPad",-1.3,1.3,1.2,1.6,-2.6,1,pick({C.fabricSand,C.sage},i),M.Fabric,true)
	end
	for _,x in {90,112} do
		post(m,"ChargingTotem",x,2512,F,F+4.4,1.2,C.white,SM)
		screen(m,"ChargingScreen",Vector3.new(x,F+5.2,2511.3),Vector3.new(0,0,-1),1.6,1,"USB · POWER",rgb(140,220,230))
	end
	box(m,"KidsMat",92,110,F,F+.15,2516,2528,rgb(90,150,190),M.Rubber,true)
	for i=0,3 do
		local x=94+i*4
		box(m,"PlayBlock",x,x+2.4,F+.15,F+2.2+(i%2),2519,2521.4,pick({rgb(230,90,70),rgb(250,200,60),rgb(90,180,110),rgb(240,140,60)},i),SM)
	end
	wedge(m,"KidsSlide",Vector3.new(2.4,3,6),CFrame.new(106,F+1.65,2524),rgb(240,140,60),SM)
	panel(m,"KidsSign",Vector3.new(101,F+7,2515.8),Vector3.new(0,0,-1),8,1.6,rgb(90,150,190),"KIDS CORNER",{ink=INK})
	box(m,"WorkCounter",118,156,F,F+3.6,2508.5,2510.5,C.oak,M.Wood)
	for x=120,154,4.2 do stool(m,x,2511.8,3.2,C.fabricCharcoal) end
	for i,x in {44,86,116} do planter(m,x,2526,3,3,true,i) end
	hangingSign(m,100,2507,G+13,20,"QUIET ZONE  ·  RELAX & RECHARGE",nil,roofY(2507)-.2)
	local l=post(m,"QuietLight",100,2518,G+18,G+18.6,4,C.lightWarm,M.Neon,true)
	box(m,"PendantRod",99.94,100.06,G+18.6,roofY(2518)-.2,2517.94,2518.06,C.metal,M.Metal,true)
	kit.light(l,56,.9,C.lightWarm)
end

-- Gate lounge i (gate centre gx, jet-bridge door at bx in the back facade).
local function gateLounge(inside: Instance,i: number,gx: number,bx: number)
	local m=folder(inside,"GateA"..i)
	local code="A"..i
	box(m,"GateCarpet",gx-35,gx+35,F,F+.04,2508.5,BACK-1,rgb(66,80,100),M.Carpet,true)
	box(m,"GateCarpetEdge",gx-35,gx+35,F,F+.05,2508.2,2508.5,C.brass,M.Metal,true)
	-- only the shuttle gate has a flight (FlightPlan: one aircraft); the other gates are closed
	local shuttle=i==A.shuttleStand
	local signText=if shuttle then code.."   "..OUT_NO.."  PORT MERIDIAN\nSHUTTLE GATE" else code.."\nGATE CLOSED"
	-- desk to the east of the bridge door, boarding lane between belts
	box(m,"GateDesk",bx+5,bx+14,F,F+3.6,2519.5,2523,C.white,M.Marble)
	box(m,"GateDeskFront",bx+5,bx+14,F+.4,F+3.2,2519.3,2519.5,BRAND,SM,true)
	for _,dx in {7,11.5} do box(m,"GateMonitor",bx+dx-.9,bx+dx+.9,F+3.6,F+4.9,2521.6,2521.8,C.screen,SM,true) end
	for _,s in {-1,1} do
		local x=bx+s*4
		box(m,"BoardingBelt",x-.05,x+.05,F+2.6,F+2.85,2514,2528,NAVY,M.Fabric,true)
		for _,z in {2514,2521,2528} do post(m,"QueuePost",x,z,F,F+3,.32,C.metalSoft,M.Metal,true) end
	end
	local door=panel(m,"GateDoorSign",Vector3.new(bx,F+10.6,BACK-1.1),Vector3.new(0,0,-1),7,1.5,NAVY,if shuttle then code.."  ·  "..OUT_NO else code.."  ·  CLOSED",{ink=INK})
	if shuttle then flightInfo(door,"gatedoor",code) end
	-- hanging gate sign (double-sided) and a number totem on the concourse
	local sign=panel(m,"GateSign",Vector3.new(bx+9.5,G+14.5,2516),Vector3.new(0,0,-1),16,4,NAVY,signText,{ink=INK},signText)
	if shuttle then flightInfo(sign,"gate",code) end
	for _,s in {-1,1} do box(m,"SignRod",sign.Position.X+s*7-.08,sign.Position.X+s*7+.08,G+16.5,roofY(2516)-.2,2515.92,2516.08,C.metal,M.Metal,true) end
	box(m,"GateTotem",gx+33,gx+35,F,F+10,2506.6,2508,NAVY,SM)
	panel(m,"GateTotemNumber",Vector3.new(gx+34,F+8.2,2506.4),Vector3.new(0,0,-1),2,3,BRAND,code,{ink=INK})
	-- seats: back-to-back rows east and west of the desk, facing the windows and the desk
	planSeats(m,code) -- CityPlan rows: west of bx-6, east of bx+17 (tests/airport checks the desk lane stays free)
	if shuttle then
		-- passengers' cabin bags in the aisles of the shuttle gate
		for k=0,3 do
			local h=hash(code.."bag"..k)
			local x=if k<2 then gx-31+(h%(bx-gx+21)) else bx+19+(h%12)
			suitcase(m,x,if k==1 then 2521.6 else 2515.2,h)
		end
		loadedTrolley(m,CFrame.new(gx-20,F,2518)*CFrame.Angles(0,math.rad(-90),0),hash(code))
	end
	post(m,"ChargingTotem",bx+16,2511.5,F,F+4.4,1.2,C.white,SM)
	airportPost(m,"gate",Vector3.new(bx+9.5,F+3,2525),Vector3.new(0,0,-1),code)
	local l=post(m,"GateLight",gx,2517,G+18,G+18.6,4,C.lightNeutral,M.Neon,true)
	box(m,"PendantRod",gx-.06,gx+.06,G+18.6,roofY(2517)-.2,2516.94,2517.06,C.metal,M.Metal,true)
	kit.light(l,58,1,C.lightNeutral)
end

local function airsideSigns(inside: Instance)
	local m=folder(inside,"Wayfinding")
	hangingSign(m,-120,2503,G+13.5,24,"←  GATE A1  ·  BUSINESS LOUNGE","GATES A2 – A3  ·  FOOD COURT  →",roofY(2503)-.2)
	hangingSign(m,0,2503,G+13.5,30,"←  A1  ·  LOUNGE      A2  ↓      A3  ·  FOOD  →",nil,roofY(2503)-.2)
	hangingSign(m,110,2503,G+13.5,24,"←  GATES A1 – A2  ·  LOUNGE","GATE A3  ·  FOOD COURT  →",roofY(2503)-.2)
	hangingSign(m,200,2503,G+13.5,20,"↑  RESTROOMS  ·  FOOD COURT  →","←  GATES A1 – A2",roofY(2503)-.2)
	for _,x in {-30,30} do
		post(m,"MonitorPost",x,2501,F,F+7.5,.4,C.metal,M.Metal)
		flightInfo(screen(m,"DepartureMonitor",Vector3.new(x,F+8.6,2500.75),Vector3.new(0,0,-1),3.6,2.2,MONITOR),"monitor")
		flightInfo(screen(m,"DepartureMonitor",Vector3.new(x,F+8.6,2501.25),Vector3.new(0,0,1),3.6,2.2,MONITOR),"monitor")
	end
	local c=post(m,"AirsideLight",0,2504,G+18,G+18.6,4,C.lightNeutral,M.Neon,true)
	box(m,"PendantRod",-.06,.06,G+18.6,roofY(2504)-.2,2503.94,2504.06,C.metal,M.Metal,true)
	kit.light(c,58,1,C.lightNeutral)
end

------------------------------------------------------------------------------------------------ vehicles
-- Built in frame f: origin on the ground under the vehicle centre, -Z (LookVector) = forward. Decor only.
-- One cylinder per axle (both wheels; the body hides the middle) - half the parts of two wheels.
local function wheels(f: CFrame,parent: Instance,hx: number,zs: {number},r: number,w: number)
	for _,z in zs do
		local p=mk(parent,"Wheels",Vector3.new(2*hx+w,2*r,2*r),f*CFrame.new(0,r,z),rgb(28,30,32),M.Rubber,true)
		p.Shape=Enum.PartType.Cylinder
	end
end
-- stowed: a parked catering truck has its box lowered onto the chassis (scissors folded away); a parked car has
-- its lights off
local function vehicle(parent: Instance,f: CFrame,kind: string,color: Color3?,stowed: boolean?)
	local m=folder(parent,kind)
	local dark=rgb(40,46,52)
	if kind=="Car" or kind=="Taxi" then
		local col=color or (if kind=="Taxi" then rgb(232,190,60) else rgb(176,178,174))
		lbox(f,m,"Body",-3,3,.8,2.6,-6.3,6.3,col,SM,true)
		glass(lbox(f,m,"Cabin",-2.75,2.75,2.6,4.1,-2.9,3.3,rgb(70,86,100),nil,true),.25)
		lbox(f,m,"Roof",-2.6,2.6,4.1,4.45,-2.1,2.8,col,SM,true)
		if not stowed then -- a parked (stowed) car has its lights off: no glowing lamp parts
			lbox(f,m,"Lights",-2.6,2.6,1.7,2.2,-6.35,-6.25,rgb(255,246,220),M.Neon,true)
			lbox(f,m,"Lights",-2.6,2.6,1.7,2.1,6.25,6.35,rgb(200,40,36),M.Neon,true)
		end
		if kind=="Taxi" then lbox(f,m,"TaxiSign",-1,1,4.45,5.1,-.4,.6,rgb(250,240,200),M.Neon,true) end
		wheels(f,m,2.8,{-4,4},1,1)
	elseif kind=="Bus" then
		local col=color or rgb(236,236,230)
		lbox(f,m,"Body",-4,4,.9,9,-17,17,col,SM,true)
		glass(lbox(f,m,"Windows",-4.05,4.05,4.6,8,-15,16,dark,nil,true),.15)
		glass(lbox(f,m,"Windscreen",-3.6,3.6,3,8.4,-17.05,-16.9,dark,nil,true),.15)
		lbox(f,m,"Stripe",-4.06,4.06,2.6,3.4,-17,17,BRAND,SM,true)
		local ds=lbox(f,m,"Destination",-3,3,8.4,9,-17.1,-17,rgb(20,20,20),SM,true)
		label(ds,if color==PAINT then "APRON  ·  REMOTE STAND R1" else "AIRPORT  ·  CITY CENTRE",Enum.NormalId.Front,{ink=SCREEN_INK,screen=true})
		wheels(f,m,3.6,{-11,10},1.4,1.2)
	elseif kind=="Pushback" then
		lbox(f,m,"Body",-3.6,3.6,.6,2.6,-5,5,YELLOW,SM,true)
		lbox(f,m,"Cab",-3.4,-.4,2.6,4.4,1,4,dark,M.Glass,true)
		lbox(f,m,"TowBar",-.3,.3,.9,1.3,-12,-5,rgb(60,60,60),M.Metal,true)
		wheels(f,m,3.2,{-3.2,3.2},1,1)
	elseif kind=="Tug" then
		lbox(f,m,"Body",-2,2,.5,2.2,-3,3,YELLOW,SM,true)
		lbox(f,m,"Roof",-2,2,4,4.3,-1,3,dark,SM,true)
		for _,x in {-1.8,1.8} do lbox(f,m,"RoofPost",x-.1,x+.1,2.2,4,2.6,2.8,dark,SM,true) end
		wheels(f,m,1.8,{-2,2},.7,.7)
	elseif kind=="Cart" then
		lbox(f,m,"CartBase",-2.2,2.2,.6,1.2,-3,3,rgb(110,116,122),M.Metal,true)
		lbox(f,m,"Bags",-1.9,1.9,1.2,2.6,-2.6,2.6,pick(GOODS,hash(tostring(f.Position.X))),SM,true)
		wheels(f,m,2,{-2,2},.5,.5)
	elseif kind=="FuelTruck" then
		lbox(f,m,"Chassis",-3,3,.8,1.6,-11,9,dark,SM,true)
		lbox(f,m,"Cab",-3,3,1.6,6,-11,-6.5,rgb(230,230,226),SM,true)
		glass(lbox(f,m,"Windscreen",-2.7,2.7,3.8,5.6,-11.05,-10.9,dark,nil,true),.2)
		cylinder(m,"Tank",f*CFrame.new(0,4.4,1.5)*CFrame.Angles(0,math.pi/2,0),14,5.6,rgb(236,236,232),M.Metal,true)
		lbox(f,m,"TankStripe",-2.85,2.85,3.4,3.9,-5.6,8.6,RED,SM,true)
		wheels(f,m,2.8,{-8,3,6.5},1.2,1)
	elseif kind=="BeltLoader" then
		lbox(f,m,"Chassis",-2.4,2.4,.6,1.8,-6,6,YELLOW,SM,true)
		lbox(f,m,"Cab",-2.4,-.2,1.8,4.2,2,5,dark,M.Glass,true)
		local belt=mk(m,"Conveyor",Vector3.new(2.2,.5,15),f*CFrame.new(.8,5.2,-3)*CFrame.Angles(math.rad(28),0,0),rgb(40,42,44),M.Rubber,true)
		local _=belt
		wheels(f,m,2.2,{-4,4},.8,.8)
	elseif kind=="Catering" then
		lbox(f,m,"Chassis",-3,3,.8,1.8,-9,8,dark,SM,true)
		lbox(f,m,"Cab",-3,3,1.8,6,-9,-5,rgb(230,230,226),SM,true)
		local lift=if stowed then 0 else 6.2
		lbox(f,m,"CateringBox",-3.4,3.4,1.8+lift,8.8+lift,-4.4,8,rgb(236,236,232),SM,true)
		if not stowed then
			for _,s in {-1,1} do mk(m,"Scissor",Vector3.new(.4,.4,13),f*CFrame.new(s*2.6,4.9,1.8)*CFrame.Angles(s*math.rad(24),0,0),rgb(200,200,196),M.Metal,true) end
		end
		lbox(f,m,"BoxStripe",-3.45,3.45,7+lift,7.8+lift,-4.4,8,BRAND,SM,true)
		wheels(f,m,2.8,{-6.5,5.5},1.1,1)
	elseif kind=="Stairs" then
		lbox(f,m,"Chassis",-3,3,.8,1.8,-8,8,rgb(230,230,226),SM,true)
		lbox(f,m,"Cab",-3,3,1.8,5,-8,-4.5,rgb(230,230,226),SM,true)
		local st=wedge(m,"Stairway",Vector3.new(3.6,11,14),f*CFrame.new(0,7.3,2),rgb(150,154,158),M.DiamondPlate,true)
		local _=st
		lbox(f,m,"Platform",-1.8,1.8,12.8,13.2,9,12,rgb(150,154,158),M.DiamondPlate,true)
		for _,s in {-1,1} do mk(m,"Handrail",Vector3.new(.2,.2,17.6),f*CFrame.new(s*1.9,10.6,2.4)*CFrame.Angles(math.rad(-38),0,0),rgb(230,230,226),M.Metal,true) end
		wheels(f,m,2.8,{-5.5,5.5},1.1,1)
	elseif kind=="ULD" or kind=="Dolly" then
		-- LD3-style container (contoured overhang on one side), on the ground or on a dolly
		local y0=0
		if kind=="Dolly" then
			lbox(f,m,"DollyBed",-1.9,1.9,.6,1,-2.3,2.3,rgb(70,74,80),M.Metal,true)
			wheels(f,m,1.5,{-1.6,1.6},.4,.4)
			y0=1
		end
		local uld=color or rgb(186,190,194)
		lbox(f,m,"ULD",-1.5,1.5,y0,y0+2.6,-1.4,1.1,uld,M.Metal,true)
		wedge(m,"ULDContour",Vector3.new(3,1.4,1),f*CFrame.new(0,y0+1.9,-1.9)*CFrame.Angles(0,0,math.pi),uld,M.Metal,true)
	elseif kind=="GPU" then
		lbox(f,m,"Unit",-2,2,.6,4,-3,3,rgb(230,230,226),SM,true)
		lbox(f,m,"UnitStripe",-2.05,2.05,3,3.4,-3,3,YELLOW,SM,true)
		wheels(f,m,1.8,{-2,2},.6,.6)
	end
end
local function cone(parent: Instance,x: number,z: number)
	post(parent,"Cone",x,z,A.apronTop,A.apronTop+1.4,.7,rgb(240,110,40),SM,true)
	post(parent,"ConeBand",x,z,A.apronTop+.7,A.apronTop+1,.74,PAINT,SM,true)
end

------------------------------------------------------------------------------------------------ jet bridges
-- Front left boarding door of a built aircraft. AircraftModel contract: the PrimaryPart "AircraftRoot" carries an
-- Attachment "DoorL1" at the door centre (LookVector out of the fuselage) with the attribute DoorHalf = half
-- the door height (an attachment without DoorHalf is taken as the sill itself) - so the bridge follows
-- whatever AircraftModel builds (part model or imported mesh). Fallback: AircraftModel.points.
-- Returns the sill point (world) and the outward normal.
local function boardingDoor(plane: Model,pivot: CFrame,scale: number): (Vector3,Vector3)
	local root=plane.PrimaryPart
	local a=if root then root:FindFirstChild("DoorL1") else nil
	local door: CFrame
	local half=0
	if root and a and a:IsA("Attachment") then
		door=root.CFrame*a.CFrame
		local h=a:GetAttribute("DoorHalf")
		if typeof(h)=="number" then half=h end
	else
		local pts=Aircraft.points("320",scale)
		door=pivot*pts.doorL1
		half=(pts :: any).doorHalf or 0
	end
	local n=Vector3.new(door.LookVector.X,0,door.LookVector.Z)
	if n.Magnitude<.5 then n=-pivot.RightVector end
	return door.Position-Vector3.new(0,half,0),n.Unit
end
-- Nose-gear z of a built aircraft (frontmost part flagged Gear), for the stop bar; fallback for old models.
local function noseGearZ(plane: Model,pivot: CFrame,scale: number): number
	local best=math.huge
	for _,d in plane:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Gear")==true then
			local l=pivot:PointToObjectSpace(d.Position)
			if math.abs(l.X)<2*scale and l.Z<best then best=l.Z end
		end
	end
	if best==math.huge then best=-22*scale end
	return (pivot*CFrame.new(0,0,best)).Position.Z
end
type Bridge={door: Vector3,cab: CFrame,bx: number,sill: number}
-- Cab position for one stand: cab floor at the door sill, its open side 0.6 studs off the fuselage.
local function bridgePlan(door: Vector3,normal: Vector3): Bridge
	local sill=door.Y
	local c=door+normal*(0.6+4.5)
	return {door=door,cab=CFrame.lookAt(Vector3.new(c.X,sill,c.Z),Vector3.new(door.X,sill,door.Z)),bx=c.X,sill=sill}
end
local function jetBridge(parent: Instance,i: number,b: Bridge)
	local m=folder(parent,"JetBridge_A"..i)
	m:SetAttribute("Gate","A"..i);m:SetAttribute("Stand",i)
	local x=b.bx
	local z0=BACK+.05
	local cabZ1=b.cab.Position.Z-4.5
	local top=b.sill
	local tunnel=Vector3.new(x,F,z0)
	local endp=Vector3.new(x,top,cabZ1)
	local dir=(endp-tunnel)
	local len=dir.Magnitude
	local f=CFrame.lookAt(tunnel,endp) -- local -Z along the bridge, floor at y=0 of this frame
	local metal=rgb(196,200,202)
	local function section(z1: number,z2: number,w: number,h: number,name: string)
		lbox(f,m,name.."Floor",-w/2,w/2,-.6,0,-z2,-z1,rgb(120,124,128),M.DiamondPlate)
		for _,s in {-1,1} do
			lbox(f,m,name.."Wall",s*w/2-(if s>0 then .4 else 0),s*w/2+(if s<0 then .4 else 0),0,2.6,-z2,-z1,metal,M.Metal)
			glass(lbox(f,m,name.."Window",s*w/2-(if s>0 then .3 else 0),s*w/2+(if s<0 then .3 else 0),2.6,5.8,-z2,-z1,rgb(60,70,80)),.35)
			lbox(f,m,name.."Wall",s*w/2-(if s>0 then .4 else 0),s*w/2+(if s<0 then .4 else 0),5.8,h,-z2,-z1,metal,M.Metal)
		end
		lbox(f,m,name.."Roof",-w/2-.2,w/2+.2,h,h+.5,-z2,-z1,metal,M.Metal)
	end
	local split=len*.5
	section(0,split+1,7.6,8.6,"BridgeOuter")
	section(split,len,7,8,"BridgeInner")
	-- drive unit under the inner section (legs + bogie), service stairs, cab and canopy bellows
	local dp=f*CFrame.new(0,0,-(len-6))
	local groundY=A.apronTop
	for _,s in {-1,1} do
		local legTop=dp*CFrame.new(s*2.4,-.6,0)
		box(m,"DriveLeg",legTop.X-.4,legTop.X+.4,groundY+1.2,legTop.Y,legTop.Z-.4,legTop.Z+.4,rgb(90,94,98),M.Metal)
	end
	box(m,"DriveBogie",dp.X-3.2,dp.X+3.2,groundY+.6,groundY+1.4,dp.Z-1,dp.Z+1,rgb(60,64,68),M.Metal,true)
	for _,s in {-1,1} do
		local w=mk(m,"Wheel",Vector3.new(.9,1.6,1.6),CFrame.new(dp.X+s*3.4,groundY+.8,dp.Z),rgb(28,30,32),M.Rubber,true);w.Shape=Enum.PartType.Cylinder
	end
	local cab=b.cab -- LookVector towards the aircraft door
	lbox(cab,m,"CabFloor",-4.5,4.5,-.6,0,-4.5,4.5,rgb(120,124,128),M.DiamondPlate)
	lbox(cab,m,"CabRoof",-4.7,4.7,8,8.6,-4.7,4.7,metal,M.Metal)
	lbox(cab,m,"CabWall",-4.5,4.5,0,8,4.1,4.5,metal,M.Metal) -- side away from the aircraft
	-- local +X = the tail side (south for a nose-north aircraft); the tunnel enters through the open north side
	glass(lbox(cab,m,"CabWindow",4.1,4.5,2.6,5.8,-4.5,4.1,rgb(60,70,80)),.35)
	lbox(cab,m,"CabWall",4.1,4.5,0,2.6,-4.5,4.1,metal,M.Metal)
	lbox(cab,m,"CabWall",4.1,4.5,5.8,8,-4.5,4.1,metal,M.Metal)
	-- bellows frame around the aircraft side opening
	lbox(cab,m,"Bellows",-4.7,4.7,7.2,8.4,-5.1,-4.5,rgb(40,42,44),M.Fabric,true)
	for _,s in {-1,1} do lbox(cab,m,"Bellows",s*4.4-.3,s*4.4+.3,0,8.4,-5.1,-4.5,rgb(40,42,44),M.Fabric,true) end
	box(m,"CabColumn",cab.X-.5,cab.X+.5,groundY,b.sill-.6,cab.Z-.5,cab.Z+.5,rgb(90,94,98),M.Metal)
	local bp=invisible(mk(m,"BoardingPoint",Vector3.new(1,1,1),cab*CFrame.new(0,3,-3),C.white,SM,true))
	bp:SetAttribute("Gate","A"..i);bp:SetAttribute("Stand",i);bp:SetAttribute("AircraftDoor",b.door)
	m:SetAttribute("TerminalDoor",Vector3.new(x,F+3,BACK))
	m:SetAttribute("AircraftDoor",b.door)
	-- docking guidance display on the facade above the stand centre line
end

------------------------------------------------------------------------------------------------ apron
local function standMarkings(parent: Instance,i: number,gx: number,noseGearZ: number)
	local y=A.apronTop
	local function paint(name: string,x1: number,x2: number,z1: number,z2: number,color: Color3)
		box(parent,name,x1,x2,y,y+.05,z1,z2,color,SM,true)
	end
	paint("LeadInLine",gx-.25,gx+.25,noseGearZ-1,A.taxilane,YELLOW)
	paint("StopBar",gx-4,gx+4,noseGearZ-.6,noseGearZ,YELLOW)
	-- equipment restraint area (red) around the nose and the jet bridge
	for _,s in {{gx-38,gx+38,2537,2538},{gx-38,gx+38,2700,2701},{gx-38,gx-37,2537,2701},{gx+37,gx+38,2537,2701}} do paint("RestraintLine",s[1],s[2],s[3],s[4],RED) end
	-- equipment staging box (white outline) beside the stand
	for _,s in {{gx+44,gx+64,2560,2561},{gx+44,gx+64,2600,2601},{gx+44,gx+45,2560,2601},{gx+63,gx+64,2560,2601}} do paint("StagingLine",s[1],s[2],s[3],s[4],PAINT) end
	local num=box(parent,"StandNumber",gx-6,gx+6,y,y+.05,A.taxilane-30,A.taxilane-20,rgb(60,62,64),SM,true)
	label(num,"A"..i,Enum.NormalId.Top,{ink=YELLOW,far=true})
	-- docking guidance display on the terminal facade above the lead-in line
	local vd=panel(parent,"DockingDisplay",Vector3.new(gx,G+20,BACK+.6),Vector3.new(0,0,1),5,3,C.screen,"A"..i.."\nSTOP",{ink=SCREEN_INK,screen=true,far=true})
	local _=vd
end

local function apron(m: Instance)
	local ap=A.apron
	local apronF=folder(m,"Apron")
	box(apronF,"Apron",ap.x1,ap.x2,G+.02,A.apronTop,ap.z1,ap.z2,C.concrete,M.Concrete)
	-- expansion joints (subtle grid) and the taxilane with lead-out lines
	for x=ap.x1+100,ap.x2-100,100 do box(apronF,"ApronJoint",x-.1,x+.1,A.apronTop,A.apronTop+.04,ap.z1+2,ap.z2-2,rgb(150,150,146),SM,true) end
	box(apronF,"TaxilaneLine",ap.x1+40,ap.x2-40,A.apronTop,A.apronTop+.05,A.taxilane-.25,A.taxilane+.25,YELLOW,SM,true)
	local tz=(A.taxiway.z1+A.taxiway.z2)/2
	for _,x in A.exits do box(apronF,"LeadOutLine",x-.25,x+.25,A.apronTop,A.apronTop+.05,A.taxilane,tz,YELLOW,SM,true) end
	-- stands: aircraft, jet bridge to its boarding door, markings, ground vehicles
	local liveries={Color3.fromRGB(94,136,162),Color3.fromRGB(170,110,84),Color3.fromRGB(104,126,111)}
	local bridges: {Bridge}={}
	local planes: {Model}={}
	for i,cf in A.standCFrames do
		local plane=Aircraft.build(apronF,cf,{scale=A.standScale,livery=liveries[i],collide=true,name="ParkedAircraft"})
		plane:SetAttribute("Stand",i);plane:SetAttribute("Gate","A"..i)
		planes[i]=plane
		local door,normal=boardingDoor(plane,cf,A.standScale)
		bridges[i]=bridgePlan(door,normal)
		plane:SetAttribute("NoseGearZ",noseGearZ(plane,cf,A.standScale))
	end
	local jb=folder(apronF,"JetBridges")
	for i,b in bridges do jetBridge(jb,i,b) end
	local gse=folder(apronF,"GroundVehicles")
	for i,cf in A.standCFrames do
		local gx=cf.Position.X
		local s=A.standScale
		local ngz=planes[i]:GetAttribute("NoseGearZ") :: number
		standMarkings(apronF,i,gx,ngz)
		local y=A.apronTop
		local function at(x: number,z: number,yaw: number): CFrame return CFrame.new(x,y,z)*CFrame.Angles(0,math.rad(yaw),0) end
		vehicle(gse,at(gx,ngz-9,180),"Pushback")
		vehicle(gse,at(gx+54,2575,0),"Tug")
		for j=1,3 do vehicle(gse,at(gx+54,2575+j*7.2,0),"Cart") end
		vehicle(gse,at(gx+16,ngz+2,0),"GPU")
		if i==A.shuttleStand then
			-- the client-animated shuttle pushes back from / taxis in on this stand: nothing under its wings or
			-- engines (|x - gx| <= 62 behind the nose); the turnaround vehicles wait in the staging box
			vehicle(gse,at(gx+48,2565,0),"BeltLoader")
			vehicle(gse,at(gx+60,2563,0),"Catering",nil,true) -- waiting: box lowered
			for _,o in {{-4,-24},{4,-24}} do cone(gse,gx+o[1],ngz+o[2]) end
		else
			vehicle(gse,at(gx+14.5,cf.Position.Z-12*s,90),"BeltLoader")
			vehicle(gse,at(gx+16,cf.Position.Z+16*s,-90),"Catering")
			if i~=2 then vehicle(gse,at(gx-30*s,cf.Position.Z+6*s,180),"FuelTruck") end
			vehicle(gse,at(gx-19,cf.Position.Z+18*s,90),"Stairs")
			for _,o in {{-17,-2},{17,-2},{-17*s,7*s},{17*s,7*s}} do cone(gse,gx+o[1],cf.Position.Z+o[2]) end
		end
	end
	-- remote stand R1 on the east apron: a second aircraft served by mobile stairs and an apron bus
	local rcf=CFrame.new(470,A.apronTop,2640)
	local remote=Aircraft.build(apronF,rcf,{scale=A.standScale,livery=rgb(150,62,72),collide=true,name="RemoteAircraft"})
	remote:SetAttribute("Stand","R1")
	local rngz=noseGearZ(remote,rcf,A.standScale)
	local rdoor=boardingDoor(remote,rcf,A.standScale)
	local y=A.apronTop
	local function rat(x: number,z: number,yaw: number): CFrame return CFrame.new(x,y,z)*CFrame.Angles(0,math.rad(yaw),0) end
	box(apronF,"LeadInLine",469.75,470.25,y,y+.05,rngz-1,A.taxilane,YELLOW,SM,true)
	box(apronF,"StopBar",466,474,y,y+.05,rngz-.6,rngz,YELLOW,SM,true)
	local rnum=box(apronF,"StandNumber",464,476,y,y+.05,A.taxilane-30,A.taxilane-20,rgb(60,62,64),SM,true)
	label(rnum,"R1",Enum.NormalId.Top,{ink=YELLOW,far=true})
	local rg=folder(gse,"RemoteStand")
	vehicle(rg,rat(rdoor.X-13,rdoor.Z,90),"Stairs")
	vehicle(rg,rat(rdoor.X-13,rcf.Position.Z+27.3*A.standScale/1.8,90),"Stairs")
	vehicle(rg,rat(rdoor.X-22,rdoor.Z-26,0),"Bus",PAINT)
	vehicle(rg,rat(484.5,rcf.Position.Z-21.6,90),"BeltLoader")
	vehicle(rg,rat(524,rcf.Position.Z+10.8,180),"FuelTruck")
	for _,o in {{-17,-2},{17,-2}} do cone(rg,470+o[1],rcf.Position.Z+o[2]) end
	-- equipment roads: head-of-stand road along the facade (interrupted by the stands' restraint areas) and the
	-- service road behind the stands; white lines
	local y0=A.apronTop
	local rs: {{number}}={}
	local x0=ap.x1+10
	for _,cf in A.standCFrames do table.insert(rs,{x0,cf.Position.X-39});x0=cf.Position.X+39 end
	table.insert(rs,{x0,ap.x2-10})
	for _,r in rs do
		for _,z in {2541,2553} do box(apronF,"RoadLine",r[1],r[2],y0,y0+.05,z-.25,z+.25,PAINT,SM,true) end
	end
	for _,z in {2712,2724} do box(apronF,"RoadLine",ap.x1+10,ap.x2-10,y0,y0+.05,z-.25,z+.25,PAINT,SM,true) end
	-- GSE parking on the west apron (between the two roads, clear of stand A1's wing sweep and of the hangar
	-- apron corridor x < -560): baggage carts, ULD dollies, containers, spare tugs, belt loaders, stairs, a
	-- stowed catering truck, a fuel truck and an apron bus; a coned holding box by the facade
	local park=folder(gse,"GSEParking")
	for _,s in {{-560,-356,2569.75,2570.25},{-560,-356,2675.75,2676.25},{-560.5,-559.5,2570,2676},{-356.5,-355.5,2570,2676}} do
		box(apronF,"ParkingLine",s[1],s[2],y0,y0+.05,s[3],s[4],PAINT,SM,true)
	end
	local plate=box(apronF,"ParkingLabel",-430,-390,y0,y0+.05,2574,2582,rgb(60,62,64),SM,true)
	label(plate,"GSE PARKING",Enum.NormalId.Top,{ink=PAINT,far=true})
	local function pat(x: number,z: number,yaw: number): CFrame return CFrame.new(x,y0,z)*CFrame.Angles(0,math.rad(yaw),0) end
	for i=0,5 do vehicle(park,pat(-544+i*5.6,2592,0),"Cart") end
	for i=0,2 do vehicle(park,pat(-504+i*7,2591,0),"Tug") end
	for i=0,5 do vehicle(park,pat(-544+i*6,2616,0),"Dolly") end
	for i=0,7 do vehicle(park,pat(-546+i*4,2640,0),"ULD",if i%3==2 then rgb(150,156,162) else nil) end
	for i=0,3 do vehicle(park,pat(-506+i*6,2643,0),"Dolly") end
	-- a baggage train waiting along the back of the box (tug + four carts, heading east)
	vehicle(park,pat(-505,2662,-90),"Tug")
	for i=1,4 do vehicle(park,pat(-505-i*7.4,2662,-90),"Cart") end
	for i=0,1 do vehicle(park,pat(-496+i*9,2624,0),"BeltLoader") end
	vehicle(park,pat(-468,2626,0),"Stairs")
	vehicle(park,pat(-430,2618,0),"Catering",nil,true)
	vehicle(park,pat(-410,2620,0),"FuelTruck")
	vehicle(park,pat(-370,2625,0),"Bus",PAINT)
	local hold=folder(gse,"HoldingBox")
	for _,s in {{-662,-628,2559.75,2560.25},{-662,-628,2585.75,2586.25},{-662.25,-661.75,2560,2586},{-628.25,-627.75,2560,2586}} do
		box(apronF,"HoldingLine",s[1],s[2],y0,y0+.05,s[3],s[4],YELLOW,SM,true)
	end
	for _,c in {{-662,2560},{-628,2560},{-662,2586},{-628,2586}} do cone(hold,c[1],c[2]) end
	-- apron flood masts (four real lights) between the stands, 74 studs north of the taxilane (z 2790): out of the
	-- 62-stud wingtip corridor of the taxilane and the taxiway (flight request 6; they stood at z 2836 before)
	local MZ=2716
	for _,x in {-330,-100,100,330} do
		box(apronF,"FloodMast",x-.6,x+.6,A.apronTop,G+32,MZ,MZ+1.2,C.metal,M.Metal)
		box(apronF,"FloodFrame",x-5,x+5,G+32,G+33,MZ-.4,MZ+1.6,C.metal,M.Metal,true)
		local head=box(apronF,"FloodHead",x-4.6,x+4.6,G+33,G+35,MZ-1.8,MZ,GLOW,M.Neon,true)
		head.CFrame=head.CFrame*CFrame.Angles(math.rad(25),0,0)
		kit.light(head,60,.8)
	end
	return planes,bridges
end

------------------------------------------------------------------------------------------------ runway
-- Painted 7-segment-like digit (bars) for the runway designators. f: origin = digit centre on the surface,
-- local -Z = the top of the digit (towards the far end of the runway).
local DIGITS: {[string]: {string}}={["0"]={"a","b","c","d","e","f"},["9"]={"a","b","c","d","f","g"},["2"]={"a","b","g","e","d"},["7"]={"a","b","c"}}
local function digit(parent: Instance,f: CFrame,ch: string,h: number,w: number)
	local t=1.6
	local segs: {[string]: {number}}={a={-w/2,w/2,-h/2,-h/2+t},g={-w/2,w/2,-t/2,t/2},d={-w/2,w/2,h/2-t,h/2},
		f={-w/2,-w/2+t,-h/2,0},b={w/2-t,w/2,-h/2,0},e={-w/2,-w/2+t,0,h/2},c={w/2-t,w/2,0,h/2}}
	local list=DIGITS[ch]
	if not list then return end
	for _,s in list do
		local r=segs[s]
		lbox(f,parent,"RunwayNumber",r[1],r[2],0,.05,r[3],r[4],PAINT,SM,true)
	end
end
local function runway(m: Instance)
	local tw=A.taxiway;local rw=A.runway
	local apronF=m:FindFirstChild("Apron") or m
	local top=City.ROAD_TOP
	box(apronF,"Taxiway",tw.x1,tw.x2,G+.02,top,tw.z1,tw.z2,C.asphalt,M.Asphalt)
	local tz=(tw.z1+tw.z2)/2
	box(apronF,"TaxiLine",tw.x1,tw.x2,top,top+.05,tz-.25,tz+.25,YELLOW,SM,true)
	for _,z in {tw.z1+1.2,tw.z2-1.2} do box(apronF,"TaxiEdgeLine",tw.x1,tw.x2,top,top+.05,z-.2,z+.2,YELLOW,SM,true) end
	for _,x in A.connectors do
		box(apronF,"TaxiConnector",x-20,x+20,G+.02,top,tw.z2,rw.z1,C.asphalt,M.Asphalt)
		box(apronF,"TaxiLine",x-.25,x+.25,top,top+.05,tz,rw.z1+20,YELLOW,SM,true)
		-- hold-short marking: two solid + two dashed lines, and the red runway sign
		for k,dz in {-1.5,-.5} do box(apronF,"HoldShortLine",x-19,x+19,top,top+.05,A.holdShortZ+dz*1.6-.2,A.holdShortZ+dz*1.6+.2,YELLOW,SM,true);local _=k end
		for dx=-18,14,4 do for _,dz in {.6,1.6} do box(apronF,"HoldShortDash",x+dx,x+dx+2.4,top,top+.05,A.holdShortZ+dz*1.6-.2,A.holdShortZ+dz*1.6+.2,YELLOW,SM,true) end end
		-- the red runway sign 32 studs east of the connector centre line: clear of the nacelle while the aircraft
		-- turns through the connector (flight request 6; it stood at x + 23.75 before)
		box(apronF,"HoldSignPost",x+31.75,x+32.25,G,G+4,A.holdShortZ-.25,A.holdShortZ+.25,C.metal,M.Metal,true)
		panel(apronF,"HoldSign",Vector3.new(x+32,G+4.6,A.holdShortZ-.4),Vector3.new(0,0,-1),6,1.6,rgb(190,40,36),"09 – 27",{ink=INK,far=true})
		for z=tw.z2+10,rw.z1-10,20 do for _,s in {-1,1} do post(apronF,"TaxiEdgeLight",x+s*20.5,z,G,G+.9,.5,rgb(70,120,255),M.Neon,true) end end
	end
	-- blue taxiway edge lights (neon) along both edges
	for x=tw.x1+10,tw.x2-10,50 do
		for _,z in {tw.z1-.8,tw.z2+.8} do
			local skip=z<tz and math.abs(x)<=A.apron.x2+5
			for _,cx in A.connectors do if z>tz and math.abs(x-cx)<22 then skip=true end end
			if not skip then post(apronF,"TaxiEdgeLight",x,z,G,G+.9,.5,rgb(70,120,255),M.Neon,true) end
		end
	end
	local runwayF=folder(m,"Runway")
	local rtop=top
	for _,s in {{rw.x1,0},{0,rw.x2}} do
		box(runwayF,"Runway",s[1],s[2],G+.02,rtop,rw.z1,rw.z2,Color3.fromRGB(50,53,56),M.Asphalt)
		for _,z in {rw.z1+3,rw.z2-3} do box(runwayF,"RunwayEdge",s[1]+8,s[2]-8,rtop,rtop+.05,z-.6,z+.6,PAINT,SM,true) end
	end
	local cz=(rw.z1+rw.z2)/2
	for x=rw.x1+200,rw.x2-240,80 do box(runwayF,"RunwayDash",x,x+40,rtop,rtop+.05,cz-.6,cz+.6,PAINT,SM,true) end
	for _,e in {{rw.x1,1},{rw.x2,-1}} do
		local ex,dir=e[1] :: number,e[2] :: number
		-- threshold piano keys (4 each side of the centre line)
		for _,o in {-52,-42,-32,-22,16,26,36,46} do
			local x1=ex+dir*12;local x2=ex+dir*62
			box(runwayF,"Threshold",math.min(x1,x2),math.max(x1,x2),rtop,rtop+.05,cz+o,cz+o+6,PAINT,SM,true)
		end
		-- designator: 09 at the west end (read when landing towards +X), 27 at the east end
		local text=if dir>0 then "09" else "27"
		local nx=ex+dir*110
		local f=CFrame.lookAt(Vector3.new(nx,rtop,cz),Vector3.new(nx+dir,rtop,cz)) -- local -Z = towards the far end
		local r1,r2=string.sub(text,1,1),string.sub(text,2,2)
		digit(runwayF,f*CFrame.new(-9,0,0),r1,30,14)
		digit(runwayF,f*CFrame.new(9,0,0),r2,30,14)
		-- aiming point + touchdown zone bars
		for _,d in {{400,10,50},{250,6,30},{550,6,30}} do
			local ax=ex+dir*d[1]
			for _,s in {-1,1} do box(runwayF,"AimingPoint",ax-d[3]/2,ax+d[3]/2,rtop,rtop+.05,cz+s*22-d[2]/2,cz+s*22+d[2]/2,PAINT,SM,true) end
		end
		-- threshold (green) and runway end (red) light bars
		local lx=ex+dir*3
		box(runwayF,"ThresholdLights",lx-.6,lx+.6,G,G+.8,rw.z1+4,rw.z2-4,rgb(80,230,120),M.Neon,true)
		local rx=ex+dir*1
		box(runwayF,"RunwayEndLights",rx-.4,rx+.4,G,G+.7,rw.z1+4,rw.z2-4,rgb(240,70,60),M.Neon,true)
		-- approach lights: cross bars on posts out to the boundary and beyond (horizon land)
		for k=1,8 do
			local ax=ex-dir*(k*28)
			post(runwayF,"ApproachPost",ax,cz,G-6,G+2.2+k*.2,.5,C.metal,M.Metal,true)
			box(runwayF,"ApproachBar",ax-.4,ax+.4,G+2.2+k*.2,G+2.8+k*.2,cz-10+(k%2)*2,cz+10-(k%2)*2,PAINT,M.Neon,true)
		end
	end
	for x=rw.x1+10,rw.x2-10,100 do
		for _,z in {rw.z1-1.5,rw.z2+1.5} do post(runwayF,"EdgeLight",x,z,G,G+.9,.6,Color3.fromRGB(255,236,180),M.Neon,true) end
	end
	-- wind sock between the taxiway and the runway, 68 studs off the taxiway centre line (out of the wingtip
	-- corridor; flight request 6 - it stood at rw.z1 - 40 before) and 72 off the runway centre line
	post(runwayF,"WindsockPole",620,rw.z1-12,G,G+12,.4,C.metal,M.Metal,true)
	local sock=mk(runwayF,"Windsock",Vector3.new(6,1.6,1.6),CFrame.new(623,G+11.4,rw.z1-12)*CFrame.Angles(0,0,math.rad(-8)),rgb(240,110,40),M.Fabric,true)
	sock.Shape=Enum.PartType.Cylinder
end

------------------------------------------------------------------------------------------------ forecourt
local function forecourt(m: Instance)
	local f=folder(m,"Forecourt")
	local x1,x2=T.x1-30,T.x2+30
	box(f,"DropOffLane",x1,x2,G+.02,City.ROAD_TOP,2400,2418,C.asphalt,M.Asphalt)
	box(f,"Forecourt",x1,x2,G-.175,City.WALK_TOP,2418,FRONT,rgb(196,194,184),M.Concrete)
	box(f,"Curb",x1,x2,City.WALK_TOP-.05,City.WALK_TOP+.02,2418,2418.6,C.stoneDeep,M.Limestone,true)
	local top=City.ROAD_TOP
	-- lane markings: dashed edge line, "DROP-OFF ONLY", crossings at the three departure doors and the
	-- arrivals exit, two zebra crossings over Airport Road to the city side
	for x=x1+4,x2-8,10 do box(f,"LaneDash",x,x+5,top,top+.05,2409.2,2409.6,PAINT,SM,true) end
	for _,x in {-225,-75,75,225} do
		local t=box(f,"LaneText",x-10,x+10,top,top+.05,2410.5,2416.5,C.asphalt,SM,true)
		label(t,"DROP-OFF ONLY",Enum.NormalId.Top,{ink=PAINT,far=true})
	end
	for _,x in DOORS do
		for k=-2,2 do box(f,"Zebra",x+k*2.4-.8,x+k*2.4+.8,top,top+.05,2408.4,2417.6,PAINT,SM,true) end
	end
	for _,x in {-150,150} do
		for k=-2,2 do box(f,"Zebra",x+k*2.4-.8,x+k*2.4+.8,top,top+.05,2361,2399,PAINT,SM,true) end
	end
	-- vehicles: taxi rank (west), private cars, two airport buses at the bus stop (east)
	local function at(x: number,yaw: number): CFrame return CFrame.new(x,top,2413.5)*CFrame.Angles(0,math.rad(yaw),0) end
	for i=0,3 do vehicle(f,at(-280+i*15,-90),"Taxi") end
	vehicle(f,at(-110,-90),"Car",rgb(120,44,40))
	vehicle(f,at(-34,-90),"Car",rgb(42,64,96))
	vehicle(f,at(30,-90),"Car",rgb(210,210,206))
	vehicle(f,at(110,-90),"Taxi")
	vehicle(f,at(196,-90),"Bus")
	vehicle(f,at(240,-90),"Bus",rgb(220,226,230))
	-- taxi and bus signs, bus shelter, bollards, planters, info totems
	post(f,"TaxiSignPost",-292,2420,City.WALK_TOP,City.WALK_TOP+9,.4,C.metal,M.Metal,true)
	panel(f,"TaxiSign",Vector3.new(-292,City.WALK_TOP+9.8,2420),Vector3.new(0,0,-1),5,1.8,rgb(232,190,60),"TAXI",{ink=rgb(30,30,30),far=true},"TAXI")
	box(f,"BusShelterRoof",236,262,City.WALK_TOP+8,City.WALK_TOP+8.6,2419,2425,C.metal,M.Metal,true)
	glass(box(f,"BusShelterGlass",236,262,City.WALK_TOP,City.WALK_TOP+8,2424.6,2425,C.glass,nil,true),.5)
	for _,x in {236.3,261.7} do box(f,"BusShelterPost",x-.3,x+.3,City.WALK_TOP,City.WALK_TOP+8,2424,2424.6,C.metal,M.Metal,true) end
	box(f,"BusShelterBench",239,259,City.WALK_TOP,City.WALK_TOP+1.6,2422.6,2424.2,C.oak,M.Wood)
	panel(f,"BusSign",Vector3.new(249,City.WALK_TOP+9.6,2419.2),Vector3.new(0,0,-1),12,1.4,rgb(58,88,140),"BUS  ·  CITY CENTRE  ·  BUSINESS CITY",{ink=INK,far=true})
	for x=x1+6,x2-6,15 do
		local free=true
		for _,dx in DOORS do if math.abs(x-dx)<9 then free=false end end
		for _,c in {-225,-75,75,225} do if math.abs(x-c)<3 then free=false end end
		if x>233 and x<265 then free=false end
		if free then post(f,"Bollard",x,2419.4,City.WALK_TOP,City.WALK_TOP+2.4,.7,C.metalSoft,M.Metal) end
	end
	for i,x in {-112,-38,38,112} do
		box(f,"CurbPlanter",x-6,x+6,City.WALK_TOP,City.WALK_TOP+2,2424,2428,rgb(70,74,78),M.Slate)
		ball(f,"CurbShrub",Vector3.new(x-3,City.WALK_TOP+2.8,2426),3.6,C.foliage,M.LeafyGrass,true)
		ball(f,"CurbShrub",Vector3.new(x+3,City.WALK_TOP+2.8,2426),3.6,C.foliageLight,M.LeafyGrass,true)
		local _=i
	end
	for _,x in {T.x1-22,T.x2+22} do
		box(f,"InfoTotem",x-1.5,x+1.5,City.WALK_TOP,City.WALK_TOP+12,2421,2422.4,NAVY,SM)
		panel(f,"InfoTotemFace",Vector3.new(x,City.WALK_TOP+8,2420.85),Vector3.new(0,0,-1),2.8,7,NAVY,"CITY\nAIRPORT\n\n← P\n✈ DEP\nARR →",{ink=INK,far=true})
	end
	-- canopy lights under the soffit (four real lights)
	for _,x in {-225,-75,75,225} do
		local l=box(f,"CanopyLight",x-6,x+6,roofY(2412)-.6,roofY(2412)-.2,2410,2414,C.lightWarm,M.Neon,true)
		kit.light(l,48,.9,C.lightWarm)
	end
	-- covered walkway from the car park to the terminal (west)
	box(f,"WalkwayCanopy",-342,T.x1,G+11,G+11.8,2419,2429,C.white,M.Metal,true)
	for _,x in {-338,-318} do for _,z in {2419.6,2428.4} do post(f,"WalkwayPost",x,z,City.WALK_TOP,G+11,.6,C.metal,M.Metal,true) end end
	box(f,"Walkway",-342,x1,G-.175,City.WALK_TOP,2418,FRONT,rgb(196,194,184),M.Concrete)
end

------------------------------------------------------------------------------------------------ car park
local function carPark(m: Instance)
	local lot=A.carParkLot
	local park=folder(m,"CarPark")
	box(park,"CarParkSurface",lot.x1,lot.x2,G+.02,G+.3,lot.z1,lot.z2,C.asphalt,M.Asphalt)
	for i=0,20 do
		local x=-350-i*10
		box(park,"BayLine",x-.15,x+.15,G+.3,G+.35,2412,2430,PAINT,SM,true)
		box(park,"BayLine",x-.15,x+.15,G+.3,G+.35,2500,2518,PAINT,SM,true)
	end
	-- parked cars (decor) in row B and the far part of row A; the bays nearest the terminal stay free
	local tones={rgb(64,72,80),rgb(176,178,174),rgb(120,44,40),rgb(42,64,96),rgb(210,210,206),rgb(30,32,34),rgb(150,140,120)}
	for i=0,20 do
		local x=-355-i*10
		local h=hash("bay"..i)
		if h%4~=0 then vehicle(park,CFrame.new(x,G+.3,2509)*CFrame.Angles(0,if h%2==0 then 0 else math.pi,0),"Car",pick(tones,h),true) end
		if i>=12 and h%3~=0 then vehicle(park,CFrame.new(x,G+.3,2421)*CFrame.Angles(0,math.pi,0),"Car",pick(tones,h+3),true) end
	end
	box(park,"ParkingSignPost",-338,-337,G,G+12,2402,2403,C.metal,M.Metal)
	panel(park,"ParkingSign",Vector3.new(-337.5,G+10,2401.6),Vector3.new(0,0,-1),13,4,rgb(58,88,140),"P  AIRPORT PARKING",{ink=INK,far=true})
	box(park,"PayStation",-344,-342,G+.3,G+5.5,2440,2442,rgb(60,66,74),SM)
	for i,x in {-420,-560,-700,-800} do kit.lamp(park,x,2470,i<=2,G+.3) end
end

------------------------------------------------------------------------------------------------ tower, hangar
local function towerAndHangar(m: Instance)
	local tp=A.tower
	local tower=folder(m,"ControlTower",Enum.ModelStreamingMode.Persistent)
	box(tower,"TowerBase",tp.X-15,tp.X+15,G,G+10,tp.Z-15,tp.Z+15,C.stone,M.Limestone)
	box(tower,"TowerShaft",tp.X-6,tp.X+6,G+10,G+80,tp.Z-6,tp.Z+6,C.stone,M.Limestone)
	glass(box(tower,"TowerCab",tp.X-12,tp.X+12,G+80,G+90,tp.Z-12,tp.Z+12,C.glassDeep),.25)
	box(tower,"TowerRoof",tp.X-14,tp.X+14,G+90,G+91.5,tp.Z-14,tp.Z+14,C.metal,M.Metal)
	box(tower,"TowerAntenna",tp.X-.3,tp.X+.3,G+91.5,G+104,tp.Z-.3,tp.Z+.3,C.metal,M.Metal,true)
	local beacon=box(tower,"TowerBeacon",tp.X-.8,tp.X+.8,G+104,G+105.6,tp.Z-.8,tp.Z+.8,Color3.fromRGB(230,80,60),M.Neon,true)
	kit.light(beacon,24,.6,Color3.fromRGB(230,80,60))
	-- FxFar / FxVertical: per-prop activation range (requested from PropFxController's owner, airport.md #7;
	-- the default 120 / 24 studs never reaches a tower top 100 studs up and 500+ studs from the terminal)
	fx(beacon,"blink",{FxRate=1,FxColor=rgb(70,20,16),FxIdle="on",FxFar=900,FxVertical=200})
	local radar=folder(tower,"Radar")
	box(radar,"RadarMount",tp.X+7,tp.X+9,G+91.5,G+94,tp.Z+7,tp.Z+9,C.metal,M.Metal,true)
	local dish=box(radar,"RadarAntenna",tp.X+3,tp.X+13,G+94,G+96.4,tp.Z+7.6,tp.Z+8.4,rgb(220,222,224),M.Metal,true)
	local _=dish
	radar.WorldPivot=CFrame.new(tp.X+8,G+95,tp.Z+8)
	fx(radar,"spin",{FxAxis="y",FxRate=1.6,FxIdle="on",FxFar=900,FxVertical=200})
	local hg=A.hangar;local ap=A.apron
	local hangar=folder(m,"Hangar")
	box(hangar,"HangarApron",hg.x2,ap.x1,G+.02,A.apronTop,hg.z1+20,hg.z2-20,C.concrete,M.Concrete)
	box(hangar,"HangarFloor",hg.x1,hg.x2,G+.02,A.apronTop,hg.z1,hg.z2,C.concrete,M.Concrete)
	box(hangar,"HangarWall",hg.x1,hg.x1+4,G,G+46,hg.z1,hg.z2,C.metalSoft,M.CorrodedMetal)
	box(hangar,"HangarWall",hg.x1+4,hg.x2,G,G+46,hg.z1,hg.z1+4,C.metalSoft,M.CorrodedMetal)
	box(hangar,"HangarWall",hg.x1+4,hg.x2,G,G+46,hg.z2-4,hg.z2,C.metalSoft,M.CorrodedMetal)
	box(hangar,"HangarHeader",hg.x2-4,hg.x2,G+36,G+46,hg.z1+4,hg.z2-4,C.metalSoft,M.CorrodedMetal)
	box(hangar,"HangarRoof",hg.x1-4,hg.x2+4,G+46,G+48,hg.z1-4,hg.z2+4,C.metal,M.Metal)
	-- folded door panels at both ends of the opening
	for _,z in {hg.z1+4,hg.z2-12} do box(hangar,"HangarDoor",hg.x2-3,hg.x2-1,A.apronTop,G+36,z,z+8,rgb(200,204,206),M.Metal) end
	local cz=(hg.z1+hg.z2)/2
	local hs=mk(hangar,"HangarSign",Vector3.new(60,6,.4),CFrame.lookAt(Vector3.new(hg.x2+.3,G+41,cz),Vector3.new(hg.x2+5,G+41,cz)),C.metal,M.Metal,true)
	label(hs,"HANGAR 1  ·  BUSINESS AVIATION",Enum.NormalId.Front,{ink=INK,far=true})
	Aircraft.build(hangar,CFrame.lookAt(Vector3.new(hg.x1+70,A.apronTop,cz),Vector3.new(hg.x2+100,A.apronTop,cz)),{scale=.9,livery=C.brass,collide=true,name="PrivateJet"})
	kit.light(box(hangar,"HangarLight",hg.x1+20,hg.x2-20,G+45,G+45.5,cz-4,cz+4,C.lightNeutral,M.Neon,true),60,.8)
	-- company-jet stand on the hangar apron: painted box, lead-in line, marker part for the flight package
	local js=A.companyJetStand
	local jf=folder(hangar,"CompanyJetStandArea")
	local y=A.apronTop
	for _,s in {{-26,26,-34,-33},{-26,26,33,34},{-26,-25,-34,34},{25,26,-34,34}} do lbox(js,jf,"StandBox",s[1],s[2],0,.05,s[3],s[4],YELLOW,SM,true) end
	lbox(js,jf,"LeadInLine",-.25,.25,0,.05,-60,20,YELLOW,SM,true)
	local plate=lbox(js,jf,"StandLabel",-10,10,0,.05,10,22,rgb(60,62,64),SM,true)
	label(plate,"COMPANY JET",Enum.NormalId.Top,{ink=YELLOW,far=true})
	local marker=invisible(mk(jf,"CompanyJetStand",Vector3.new(46,.2,60),js,C.white,SM,true))
	marker:SetAttribute("Purpose","CompanyJet");marker:SetAttribute("Scale",.9)
	local _=y
	-- fuel farm east of the tower
	for _,z in {2600,2660} do
		local tank=mk(m,"FuelTank",Vector3.new(16,24,24),CFrame.new(980,G+8,z)*CFrame.Angles(0,0,math.pi/2),C.white,M.Metal)
		tank.Shape=Enum.PartType.Cylinder
	end
end

------------------------------------------------------------------------------------------------ perimeter, horizon
local function perimeter(m: Instance)
	local p=folder(m,"Perimeter")
	local z=3120
	for _,s in {{-1150,0},{0,1150}} do
		local fence=box(p,"PerimeterFence",s[1],s[2],G,G+9,z-.1,z+.1,rgb(150,156,160),M.DiamondPlate)
		fence.Transparency=.55
		box(p,"FenceRail",s[1],s[2],G+9,G+9.4,z-.2,z+.2,C.metal,M.Metal,true)
		box(p,"FenceWire",s[1],s[2],G+10.4,G+10.6,z-.15,z+.15,C.metal,M.Metal,true)
	end
	for x=-1150,1150,100 do box(p,"FencePost",x-.25,x+.25,G,G+10.8,z-.25,z+.25,C.metal,M.Metal,true) end
	-- service road inside the fence, trees and shrubs between the fence and the quay
	for _,s in {{-1140,0},{0,1140}} do box(p,"ServiceRoad",s[1],s[2],G+.02,G+.2,3090,3100,rgb(80,82,84),M.Asphalt) end
	local k=500
	for x=-1100,1100,90 do
		k+=1
		local h=hash("perim"..x)
		kit.tree(p,x+(h%30)-15,3150+(h%20),k,G+.1)
		if h%3==0 then ball(p,"Shrub",Vector3.new(x+30,G+2,3180),7,C.foliageLight,M.LeafyGrass,true) end
	end
end
-- Persistent backdrop: sea from the quay to Port Meridian, coastline land with low hills east and west,
-- islands in the bay. Few big parts (shown from the terminal and from the air beyond the streaming radius).
local function horizon(m: Instance)
	local hz=folder(m,"Horizon",Enum.ModelStreamingMode.Persistent)
	-- same water level as CityBuilder's harbour Sea (top G-3) so the two meet without a step; every strip that
	-- borders the city starts exactly at |x| = 1150 / z = 3800 (the edge of CityGround, DistrictFoundation and
	-- the harbour Sea), so no slit opens between the city and the backdrop
	local seaY1,seaY2=G-3.2,G-3
	local EDGE=City.HARBOUR.x2 -- 1150
	local water=C.water
	local function sea(x1: number,x2: number,z1: number,z2: number)
		glass(box(hz,"OpenSea",x1,x2,seaY1,seaY2,z1,z2,water,nil,true),.15)
	end
	sea(-2600,-EDGE,3206,5200);sea(EDGE,2600,3206,5200)
	sea(-EDGE,0,3800,5800);sea(0,EDGE,3800,5800);sea(-2600,-EDGE,5200,7240);sea(EDGE,2600,5200,7240)
	sea(-EDGE,0,5800,7500);sea(0,EDGE,5800,7500)
	-- coast land west and east of the city (top G-0.2: just under the city ground top G, no z-fight)
	local landC=rgb(112,138,96)
	local sand=rgb(214,200,160)
	for _,s in {{-2600,-EDGE},{EDGE,2600}} do
		box(hz,"CoastLand",s[1],s[2],G-4,G-.2,800,2800,landC,M.Grass,true)
		box(hz,"CoastLand",s[1],s[2],G-4,G-.2,2800,3206,landC,M.Grass,true)
		box(hz,"CoastLand",s[1],s[2],G-4,G-.2,-800,800,landC,M.Grass,true)
		-- beach strip in front of the coast land
		box(hz,"CoastBeach",s[1],s[2],G-4,G-1.6,3206,3220,sand,M.Sand,true)
	end
	-- a ragged shore: angled headlands with a sandy rim break the straight line the quay continues at z = 3206
	for _,side in {-1,1} do
		for _,h in {{1420,3232,300,64,-8},{1910,3268,440,150,13},{2380,3226,300,70,-5}} do
			local cf=CFrame.new(side*h[1],0,h[2])*CFrame.Angles(0,math.rad(side*h[5]),0)
			-- tops a little below the strips they overlap (beach G-1.6, land G-0.2): no coplanar faces
			mk(hz,"CoastSand",Vector3.new(h[3]+26,2.1,h[4]+26),cf+Vector3.new(0,G-2.95,0),sand,M.Sand,true)
			mk(hz,"CoastLand",Vector3.new(h[3],3.55,h[4]),cf+Vector3.new(0,G-2.225,0),landC,M.Grass,true)
		end
	end
	-- low hill lines (sunk spheres) on both coasts and two headlands
	local hills={{-1700,2350,520,40},{-2100,2900,700,58},{-1500,3050,380,34},{-2300,1700,800,70},{-1800,1200,600,48},
		{1700,2450,560,44},{2150,2950,760,62},{1520,3000,360,30},{2300,1800,820,72},{1850,1250,580,46},
		{-2300,3900,900,64},{2350,4050,960,70}}
	for i,h in hills do
		local d,v=h[3],h[4]
		ball(hz,"Hill",Vector3.new(h[1],G-d/2+v,h[2]),d,if i%3==0 then rgb(98,124,84) else rgb(108,134,92),M.Grass,true)
	end
	-- islands in the bay (sunk spheres with a sandy rim)
	for _,s in {{-650,4300,360,26},{520,4750,300,22},{1320,4150,240,18}} do
		local d,v=s[3],s[4]
		local r=math.sqrt(math.max(0,(d/2)^2-(d/2-v-3.2)^2)) -- radius of the hill at sea level
		post(hz,"IslandBeach",s[1],s[2],G-4,G-2.6,2*r+24,sand,M.Sand,true)
		ball(hz,"Island",Vector3.new(s[1],G-d/2+v,s[2]),d,rgb(96,124,82),M.Grass,true)
	end
end

------------------------------------------------------------------------------------------------ entry
-- Builds the airport under root/Airport. ticketText: ObjectText of the four home check-in prompts.
function Airport.build(root: Instance,k: Kit,ticketText: string): Model
	kit=k
	local m=folder(root,"Airport")
	-- apron first: the jet-bridge doors in the facade follow the parked aircraft
	local planes,bridges=apron(m)
	local _=planes
	local doorsBack: {number}={}
	for _,b in bridges do table.insert(doorsBack,b.bx) end
	local terminal=folder(m,"Terminal")
	shell(terminal,doorsBack)
	structure(terminal)
	local inside=folder(terminal,"TerminalInterior",Enum.ModelStreamingMode.Atomic)
	landside(inside,ticketText)
	arrivals(inside)
	security(inside)
	lounge(inside)
	crewRoom(inside)
	shops(inside)
	foodCourt(inside)
	restaurant(inside)
	quietZone(inside)
	for i,gx in A.stands do gateLounge(inside,i,gx,(bridges[i] and bridges[i].bx) or gx-11.4) end
	airsideSigns(inside)
	forecourt(m)
	carPark(m)
	runway(m)
	towerAndHangar(m)
	perimeter(m)
	horizon(m)
	return m
end
return Airport
