--!strict
-- Port Meridian (the far business capital, CityPlan.ABROAD; layout data in MetroPlan): built once per server by
-- CityBuilder.build, which passes its shared helpers in `kit` (real lights per zone via kit.light - 40 for the
-- whole city -, decor parts never collide/touch/query and cast no shadow).
--   * Airport district: runway with the parked aircraft, arrival terminal (check-in "Fly home", GPS kiosk,
--     departures board, baggage claim, café, seating), the BUSINESS LOUNGE (Atomic model "BusinessLounge":
--     bar, sofa groups with Seats, work pods, buffet, concierge marker), the VIP helipad (marker part
--     "Helipad", Purpose = "VIPAirport"), low airport buildings.
--   * Arrival plaza: flag row, benches, planters, metro entrance (decor), taxi rank and the VIP limousine lay-by
--     with canopy, red carpet and the marker part "VipLimoStand" (bay 1 free for the chauffeur service).
--   * Streets (MetroPlan.ROADS): asphalt, sidewalks with corner pads, lane lines, stop lines, zebra crossings,
--     traffic signals (lamp plates tagged "MetroSignal" with attributes Junction/Axis - CityLifeController
--     switches their colour; the server never touches them again), lamps, street trees, bus shelters.
--   * Meridian Boulevard: kerbed median with lawns and trees, the Meridian Arc over the monument, three fountains,
--     the meridian globe, flags, benches, double lamps, reflecting pool; retail pavilions with four media screens
--     at Exchange Street and tower forecourts; the four client towers and the Meridian
--     Grand Hotel (CityBuilder.building, enterable, meeting rooms unchanged) with the rooftop VIP helipad
--     (marker "Helipad", Purpose = "VIP") and a roof exit marker "HelipadExit".
--   * Skyline: 85 background towers from MetroPlan.LOTS, each an Atomic model "Tower_<lot id>" (6-19 parts:
--     podium with shop glass + awning, a style - glass / stone / slab / stepped / residential / drum / twist -
--     with floor bands, and a crown); window and shop glass tagged "MetroNightGlow" (attribute GlowColor) light
--     up at night on the client. The landmark "Meridian Spire" (468 studs + mast; stepped glass lantern between
--     four gold blades, light lines on the corner piers at night) is the only Persistent model here: it is the
--     city's identity and must show from everywhere in Port Meridian beyond the 512-stud streaming radius (the
--     terminal is 900 studs away; ~80 parts). The far skyline beyond the walls and impostors of streamed-out
--     towers are client-only (CityLifeController).
--   * Budget: ~5,100 parts for the whole city (+4,300 over the pre-phase-2 Port Meridian; package budget +4,500),
--     40 real lights.
--   * Harbour Quarter: spire plaza (granite bands, two ground-jet splash fountains, steps up to the spire door),
--     harbour walk with cafés and planting beds (lawn, flower edges, trees, bench pairs), promenade with a tree row
--     in granite planters on a lawn strip, granite paving bands, food carts, the "Meridian Sail" sculpture, benches,
--     lamps, mooring bollards along the quay, marina with yachts and a harbour cruiser, lighthouse, the Harbour
--     Wheel (model "HarbourWheel", rotated by the client); Parkside park with pond and bandstand.
--   * Greenery between the towers: lawn verges with tree rows in the gaps of every block, the airport district's
--     tree row in planters. District gateway signs (14 x 5 name panel under a kicker strip, both faces lettered,
--     glowing) and billboards (generic, invented ads).
--   * Street furniture positions come from MetroPlan (lamps, trees, benches, shelters, carts, ...): the client
--     walkers step round exactly these. The street ends at the boundary walls are client-side tunnel gates
--     (CityLifeController, beyond the walls like the far skyline).
-- Every walkable top is supported (city ground + paving); every entrance stays reachable (tests/world).
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CollectionService=game:GetService("CollectionService")
local City=require(ReplicatedStorage.Shared.Config.CityPlan)
local Plan=require(ReplicatedStorage.Shared.Config.MetroPlan)
local P=require(ReplicatedStorage.Shared.Config.ArchPalette)
local Aircraft=require(ReplicatedStorage.Shared.AircraftModel)
local Metro={}
local G=City.GROUND
local C=P.color
local A=City.ABROAD
local R=A.rect
local WALK=City.WALK_TOP
local ROAD=City.ROAD_TOP
local PLAZA=Plan.PLAZA_TOP
local MED=Plan.MEDIAN_TOP
local PARK=Plan.PARK_TOP
local BASE_STONE=Color3.fromRGB(186,188,169)
local PM={
	navy=Color3.fromRGB(30,44,74),gold=Color3.fromRGB(212,172,86),teal=Color3.fromRGB(40,118,128),tealGlass=Color3.fromRGB(64,124,138),
	bronze=Color3.fromRGB(128,92,56),ivory=Color3.fromRGB(236,230,214),granite=Color3.fromRGB(112,110,106),graniteLight=Color3.fromRGB(164,160,152),
	paver=Color3.fromRGB(206,196,178),paverDark=Color3.fromRGB(150,140,124),kerb=Color3.fromRGB(178,176,168),asphalt=Color3.fromRGB(46,49,52),
	line=Color3.fromRGB(232,228,214),yellow=Color3.fromRGB(226,186,80),lawn=Color3.fromRGB(98,132,84),water=Color3.fromRGB(70,140,160),
	red=Color3.fromRGB(150,32,42),glow=Color3.fromRGB(255,214,150),walkway=Color3.fromRGB(196,188,172),deck=Color3.fromRGB(146,112,80),
}
local GLASS_TINTS={Color3.fromRGB(110,150,176),Color3.fromRGB(80,132,138),Color3.fromRGB(150,128,98),Color3.fromRGB(104,114,126),Color3.fromRGB(128,160,150),Color3.fromRGB(168,180,192)}
local STONE_TONES={Color3.fromRGB(216,212,201),Color3.fromRGB(200,188,168),Color3.fromRGB(184,172,156),Color3.fromRGB(226,220,208),Color3.fromRGB(168,158,148),Color3.fromRGB(232,224,210)}
local PLASTER_TONES={Color3.fromRGB(238,234,224),Color3.fromRGB(226,214,196),Color3.fromRGB(214,222,226),Color3.fromRGB(232,220,206),Color3.fromRGB(206,198,190),Color3.fromRGB(244,240,232)}
local AWNINGS={Color3.fromRGB(32,72,96),Color3.fromRGB(140,40,44),Color3.fromRGB(46,96,70),Color3.fromRGB(196,150,70),Color3.fromRGB(70,60,96),Color3.fromRGB(30,44,74)}
local SHOP_NAMES={"BAKERY","BOUTIQUE","PHARMACY","BISTRO","BANK","FLORIST","OPTICIAN","GALLERY","DELI","TAILOR","ESPRESSO BAR","BOOKSHOP","WINE CELLAR","SUSHI","GELATO","TRAVEL AGENCY"}
local WINDOW_GLOW=Color3.fromRGB(136,104,66) -- night window light: dim warm neon (bright colours turn facades into light boxes)
local SHOP_GLOW=Color3.fromRGB(240,196,140)
local BAND=Color3.fromRGB(150,144,136) -- granite paving bands (mid grey on the pale pavers)
local FLOWERS={Color3.fromRGB(196,64,86),Color3.fromRGB(236,196,72),Color3.fromRGB(150,96,186),Color3.fromRGB(236,236,240),Color3.fromRGB(226,120,70)}
local CART_NAMES={"GELATO","CREPES","LEMONADE","PRETZELS"}

local K: any=nil -- CityBuilder's kit (set by build)
------------------------------------------------------------------------------------------------ helpers
local function flags(p: BasePart): BasePart p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;return p end
local function mk(parent: Instance,name: string,size: Vector3,cf: CFrame,color: Color3,material: Enum.Material?,decor: boolean?,class: string?): BasePart
	local p=Instance.new((class or "Part") :: any) :: BasePart
	p.Name=name;p.Anchored=true;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
	p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
	if decor then flags(p) end
	p.Parent=parent;return p
end
local function bx(parent: Instance,name: string,x1: number,x2: number,y1: number,y2: number,z1: number,z2: number,color: Color3,material: Enum.Material?,decor: boolean?): BasePart
	return mk(parent,name,Vector3.new(x2-x1,y2-y1,z2-z1),CFrame.new((x1+x2)/2,(y1+y2)/2,(z1+z2)/2),color,material,decor)
end
-- vertical cylinder standing on y1
local function cyl(parent: Instance,name: string,x: number,z: number,y1: number,y2: number,dia: number,color: Color3,material: Enum.Material?,decor: boolean?): BasePart
	local p=mk(parent,name,Vector3.new(y2-y1,dia,dia),CFrame.new(x,(y1+y2)/2,z)*CFrame.Angles(0,0,math.pi/2),color,material,decor)
	;(p :: Part).Shape=Enum.PartType.Cylinder
	return p
end
local function ball(parent: Instance,name: string,x: number,y: number,z: number,dia: number,color: Color3,material: Enum.Material?,decor: boolean?): BasePart
	local p=mk(parent,name,Vector3.new(dia,dia,dia),CFrame.new(x,y,z),color,material,decor)
	;(p :: Part).Shape=Enum.PartType.Ball
	return p
end
local function glassy(p: BasePart,t: number?): BasePart p.Material=Enum.Material.Glass;p.Transparency=t or .4;return p end
local function folder(parent: Instance,name: string,mode: Enum.ModelStreamingMode?): Model
	local m=Instance.new("Model");m.Name=name
	if mode then m.ModelStreamingMode=mode end
	m.Parent=parent;return m
end
local function light(p: BasePart,range: number,brightness: number,color: Color3?): boolean return K.light(p,range,brightness,color) end
-- Text on one face; glow = text unaffected by scene light (reads at night).
local function label(p: BasePart,text: string,face: Enum.NormalId?,ink: Color3?,glow: boolean?,font: Enum.Font?): TextLabel
	local g=Instance.new("SurfaceGui");g.Face=face or Enum.NormalId.Front;g.LightInfluence=if glow then 0 else .3
	local sx,sy=p.Size.X,p.Size.Y
	if g.Face==Enum.NormalId.Left or g.Face==Enum.NormalId.Right then sx=p.Size.Z end
	if g.Face==Enum.NormalId.Top or g.Face==Enum.NormalId.Bottom then sy=p.Size.Z end
	g.CanvasSize=Vector2.new(math.clamp(sx*40,120,1600),math.clamp(sy*40,40,900));g.Parent=p
	local t=Instance.new("TextLabel");t.BackgroundTransparency=1;t.Size=UDim2.fromScale(1,1);t.Text=text;t.TextScaled=true;t.TextWrapped=true
	t.Font=font or Enum.Font.BuilderSansBold;t.TextColor3=ink or Color3.fromRGB(240,238,228);t.Parent=g
	return t
end
local function both(p: BasePart,text: string,axis: string,ink: Color3?,glow: boolean?)
	if axis=="z" then label(p,text,Enum.NormalId.Front,ink,glow);label(p,text,Enum.NormalId.Back,ink,glow)
	else label(p,text,Enum.NormalId.Left,ink,glow);label(p,text,Enum.NormalId.Right,ink,glow) end
end
local function glowTag(p: BasePart,color: Color3)
	p:SetAttribute("GlowColor",color);CollectionService:AddTag(p,"MetroNightGlow")
end
local function tree(parent: Instance,x: number,z: number,k: number,top: number) K.tree(parent,x,z,k,top) end
local function lamp(parent: Instance,x: number,z: number,lit: boolean,top: number) K.lamp(parent,x,z,lit,top) end
-- A parked (decorative) car: body, glass cabin, two axles (wheels both sides), optional roof sign.
local function car(parent: Instance,cf: CFrame,len: number,width: number,color: Color3,kind: string?)
	local m=folder(parent,if kind=="taxi" then "Taxi" elseif kind=="limo" then "Limousine" else "ParkedCar")
	mk(m,"Body",Vector3.new(width,2.2,len),cf*CFrame.new(0,1.9,0),color,Enum.Material.SmoothPlastic,true)
	glassy(mk(m,"Cabin",Vector3.new(width-.6,1.9,len*(if kind=="limo" then .62 else .5)),cf*CFrame.new(0,3.9,len*.04),Color3.fromRGB(30,36,42),nil,true),.15)
	for _,zz in {-len*.32,len*.32} do
		local w=mk(m,"Axle",Vector3.new(width+.5,2.3,2.3),cf*CFrame.new(0,1.15,zz),Color3.fromRGB(26,27,29),Enum.Material.Rubber,true)
		;(w :: Part).Shape=Enum.PartType.Cylinder
	end
	if kind=="taxi" then
		local s=mk(m,"TaxiSign",Vector3.new(2.6,.7,1),cf*CFrame.new(0,5.2,len*.04),Color3.fromRGB(250,240,200),Enum.Material.Neon,true)
		local _=s
	end
	mk(m,"Headlights",Vector3.new(width-1,.5,.2),cf*CFrame.new(0,2.2,-len/2-.05),Color3.fromRGB(255,246,220),Enum.Material.Neon,true)
end
local function flagpole(parent: Instance,x: number,z: number,base: number,height: number,color: Color3,stripe: Color3?)
	cyl(parent,"Flagpole",x,z,base,base+height,.45,C.metalSoft,Enum.Material.Metal)
	bx(parent,"Flag",x+.25,x+7,base+height-5.5,base+height-1,z-.08,z+.08,color,Enum.Material.Fabric,true)
	if stripe then bx(parent,"FlagStripe",x+.25,x+7,base+height-3.6,base+height-2.9,z-.1,z+.1,stripe,Enum.Material.Fabric,true) end
end
local function bench(parent: Instance,s: Plan.Spot)
	-- the walker stands at the spot (facing s.face) and sits 1.6 studs behind it
	local seat=Vector3.new(s.x,s.y,s.z)-s.face*1.6
	local cf=CFrame.lookAt(seat,seat+s.face)
	mk(parent,"Bench",Vector3.new(6,.5,2),cf*CFrame.new(0,1.55,0),C.oak,Enum.Material.Wood)
	mk(parent,"BenchBack",Vector3.new(6,1.6,.35),cf*CFrame.new(0,2.6,.95),C.oak,Enum.Material.Wood,true)
	mk(parent,"BenchFrame",Vector3.new(5,1.3,1.6),cf*CFrame.new(0,.65,0),C.metal,Enum.Material.Metal,true)
end

------------------------------------------------------------------------------------------------ ground + airport district
local function ground(m: Model)
	bx(m,"MeridianGround",R.x1,R.x2,-2,G,R.z1,R.z2,BASE_STONE,Enum.Material.Concrete)
	bx(m,"MeridianPaving",R.x1,R.x2,G,G+.1,R.z1,R.z2,PM.paver,Enum.Material.Pavement)
end
local function airport(m: Model)
	local rw=A.runway
	local cz=(rw.z1+rw.z2)/2
	local field=folder(m,"Airfield")
	bx(field,"ArrivalRunway",rw.x1,rw.x2,G+.02,ROAD,rw.z1,rw.z2,Color3.fromRGB(50,53,56),Enum.Material.Asphalt)
	for x=rw.x1+60,rw.x2-100,120 do bx(field,"RunwayDash",x,x+40,ROAD,ROAD+.03,cz-.5,cz+.5,PM.line,nil,true) end
	for _,z in {rw.z1+3,rw.z2-3} do bx(field,"RunwayEdge",rw.x1+8,rw.x2-8,ROAD,ROAD+.03,z-.4,z+.4,PM.line,nil,true) end
	for _,x in {rw.x1+14,rw.x2-54} do
		for i=-3,2 do bx(field,"Threshold",x,x+40,ROAD,ROAD+.03,cz+i*10+2,cz+i*10+7,PM.line,nil,true) end
	end
	bx(field,"Apron",-420,650,G+.02,G+.25,rw.z2,A.terminal.z1,C.concrete,Enum.Material.Concrete)
	for x=rw.x1+10,rw.x2-10,130 do
		for _,z in {rw.z1-1.5,rw.z2+1.5} do bx(field,"EdgeLight",x-.6,x+.6,G+.1,G+.9,z-.6,z+.6,Color3.fromRGB(255,236,180),Enum.Material.Neon,true) end
	end
	Aircraft.build(field,CFrame.lookAt(Vector3.new(420,ROAD,cz),Vector3.new(0,ROAD,cz)),{scale=1.8,livery=PM.teal,collide=true,name="ParkedAircraft"})
	-- terminal: the hall faces the city (south); roof wave fins and an entrance canopy give it a silhouette
	local t=A.terminal
	local term=folder(m,"ArrivalTerminal")
	K.hall(term,t,A.height,1,A.entrances,12)
	local h=G+A.height
	for i=0,6 do
		local x=t.x1+20+i*(t.x2-t.x1-40)/6
		local y=h+3+math.sin(i/6*math.pi)*5
		mk(term,"RoofWave",Vector3.new(6,1,t.z2-t.z1+16),CFrame.new(x,y,(t.z1+t.z2)/2)*CFrame.Angles(math.rad(4),0,0),PM.ivory,Enum.Material.Metal,true)
	end
	bx(term,"RoofSpine",t.x1+10,t.x2-10,h+2,h+3,(t.z1+t.z2)/2-1,(t.z1+t.z2)/2+1,C.metalSoft,Enum.Material.Metal,true)
	bx(term,"EntranceCanopy",-110,110,G+15,G+16,t.z2,t.z2+14,PM.ivory,Enum.Material.Metal,true)
	bx(term,"CanopyFascia",-110,110,G+14.4,G+15,t.z2+13.6,t.z2+14,PM.gold,Enum.Material.Metal,true)
	for _,x in {-104,-40,40,104} do cyl(term,"CanopyColumn",x,t.z2+12.5,G+.3,G+15,1,C.metal,Enum.Material.Metal) end
	local arrSign=bx(term,"ArrivalsSign",-40,40,h-6,h-2,t.z2+.9,t.z2+1.3,PM.navy,Enum.Material.Metal,true)
	arrSign.CFrame=arrSign.CFrame*CFrame.Angles(0,math.pi,0);label(arrSign,"PORT MERIDIAN AIRPORT · ARRIVALS",Enum.NormalId.Front,PM.gold,true)
	-- interior (one Atomic model): check-in home, GPS kiosk, boards, baggage claim, café, seating, columns
	local inside=folder(term,"TerminalInterior",Enum.ModelStreamingMode.Atomic)
	for _,p in A.checkin do K.checkin(inside,p,1,"home","Fly home","City Airport · return ticket included") end
	K.kiosk(inside,30,7676,G+.5,-1,"intl_hotel","Meridian Grand Hotel")
	local welcome=bx(inside,"WelcomeSign",-60,60,G+14,G+20,t.z1+1.2,t.z1+1.6,PM.navy,Enum.Material.Metal,true)
	welcome.CFrame=welcome.CFrame*CFrame.Angles(0,math.pi,0);label(welcome,"WELCOME TO PORT MERIDIAN",Enum.NormalId.Front,PM.gold,true)
	for _,x in {-80,0,80} do light(bx(inside,"CeilingLight",x-24,x+24,h-.5,h,7645,7655,C.lightNeutral,Enum.Material.Neon,true),36,.85) end
	local board=bx(inside,"DepartureBoard",-26,26,G+15,G+22,7639.6,7640.2,C.screen,nil,true)
	board.CFrame=board.CFrame*CFrame.Angles(0,math.pi,0)
	label(board,"DEPARTURES\nPM 102   CITY AIRPORT   CHECK-IN OPEN\nPM 104   CITY AIRPORT   ON TIME\nVIP      HELICOPTER     ON REQUEST",Enum.NormalId.Front,Color3.fromRGB(240,200,110),true,Enum.Font.RobotoMono)
	bx(inside,"FloorInlay",-1,1,G+.5,G+.53,7660,t.z2-1,PM.gold,Enum.Material.Metal,true)
	bx(inside,"FloorBand",t.x1+2,t.x2-2,G+.5,G+.52,7664,7668,PM.granite,Enum.Material.Granite,true)
	for _,x in {-100,-30,30,100} do cyl(inside,"Column",x,7666,G+.5,h,3,PM.ivory,Enum.Material.Marble) end
	for _,z in {7617,7624} do
		for _,s in {{-40,-6},{6,40}} do
			bx(inside,"Seating",s[1],s[2],G+.5,G+2.3,z,z+2.6,C.fabricBlue,Enum.Material.Fabric)
			bx(inside,"SeatingBack",s[1],s[2],G+2.3,G+4.4,z,z+.6,C.fabricBlue,Enum.Material.Fabric,true)
		end
	end
	-- baggage claim (east)
	bx(inside,"BaggageCarousel",116,148,G+.5,G+2.4,7642,7654,C.metalSoft,Enum.Material.Metal)
	for _,x in {116,148} do cyl(inside,"CarouselEnd",x,7648,G+.5,G+2.4,12,C.metalSoft,Enum.Material.Metal) end
	bx(inside,"CarouselBelt",114,150,G+2.4,G+2.6,7643,7653,Color3.fromRGB(40,42,44),Enum.Material.Rubber,true)
	for i,x in {121,129,137,144} do bx(inside,"Suitcase",x-1.4,x+1.4,G+2.6,G+4.4,7644+(i%2)*5,7646+(i%2)*5,AWNINGS[i],nil,true) end
	local claim=bx(inside,"BaggageSign",120,144,G+12,G+15,7647.8,7648.2,PM.navy,Enum.Material.Metal,true)
	both(claim,"BAGGAGE CLAIM · BELT 1","z",PM.gold,true)
	-- café (north glass, east) and a news kiosk
	bx(inside,"CafeCounter",96,128,G+.5,G+4.3,7614,7618,C.oak,Enum.Material.Wood)
	bx(inside,"CafeTop",95.6,128.4,G+4.3,G+4.6,7613.6,7618.4,C.stone,Enum.Material.Marble,true)
	local cafe=bx(inside,"CafeSign",100,124,G+10,G+13,7611.2,7611.6,PM.navy,Enum.Material.Metal,true)
	cafe.CFrame=cafe.CFrame*CFrame.Angles(0,math.pi,0);label(cafe,"CAFÉ AURORA",Enum.NormalId.Front,PM.gold,true)
	bx(inside,"CafeShelf",98,126,G+5,G+5.4,7611.4,7612.6,PM.glow,Enum.Material.Neon,true)
	for _,x in {100,108,116,124} do cyl(inside,"BarStool",x,7620.5,G+.5,G+3.2,1.6,C.metal,Enum.Material.Metal,true) end
	bx(inside,"NewsKiosk",136,152,G+.5,G+4.3,7670,7682,PM.teal,Enum.Material.SmoothPlastic)
	local news=bx(inside,"NewsSign",136,152,G+9,G+11,7669.4,7669.8,PM.navy,Enum.Material.Metal,true)
	label(news,"NEWS · SNACKS · TRAVEL",Enum.NormalId.Front,PM.gold,true)
	bx(inside,"NewsCanopy",135,153,G+8,G+8.6,7669,7683,PM.ivory,Enum.Material.Metal,true)
	-- wayfinding (hanging)
	local w1=bx(inside,"Wayfinding",-12,12,G+16,G+18.5,7682.6,7683,PM.navy,Enum.Material.Metal,true)
	both(w1,"EXIT · CITY CENTRE · TAXI","z",PM.gold,true)
	local w2=bx(inside,"Wayfinding",-98,-80,G+14,G+16.5,7650,7650.4,PM.navy,Enum.Material.Metal,true)
	both(w2,"◄ BUSINESS LOUNGE","z",PM.gold,true)
	local w3=bx(inside,"Wayfinding",84,112,G+14,G+16.5,7676,7676.4,PM.navy,Enum.Material.Metal,true)
	both(w3,"VIP LIMOUSINE · HELIPAD ►","z",PM.gold,true)
	for _,x in {-14,14} do
		cyl(inside,"Planter",x,7684,G+.5,G+3,4,C.terracotta,Enum.Material.Slate)
		ball(inside,"PlanterLeaves",x,G+5,7684,5.5,C.foliage,Enum.Material.LeafyGrass,true)
	end
	return term
end
-- Business lounge: west end of the arrival hall behind a frosted partition with a door gap.
local function lounge(term: Model)
	local L=Plan.LOUNGE
	local lm=folder(term,"BusinessLounge",Enum.ModelStreamingMode.Atomic)
	-- same hooks as City Airport's lounge (AirportBuilder): tag + Purpose, plus Zone to tell them apart
	lm:SetAttribute("VipLounge",true);lm:SetAttribute("Purpose","BusinessLounge");lm:SetAttribute("Zone","abroad")
	CollectionService:AddTag(lm,"BusinessLounge")
	local f=G+.5;local h=G+A.height
	local px=L.x2
	glassy(bx(lm,"LoungePartition",px,px+.6,f,h,L.z1,L.doorZ1,PM.ivory),.45)
	glassy(bx(lm,"LoungePartition",px,px+.6,f,h,L.doorZ2,L.z2,PM.ivory),.45)
	bx(lm,"LoungeLintel",px,px+.6,G+11,h,L.doorZ1,L.doorZ2,PM.navy,Enum.Material.SmoothPlastic)
	for _,z in {L.doorZ1,L.doorZ2} do bx(lm,"DoorFrame",px-.2,px+.8,f,G+11,z-.5,z+.5,PM.bronze,Enum.Material.Metal) end
	local entrance=bx(lm,"LoungeEntrance",px-1,px+1.6,f,f+8,L.doorZ1+.5,L.doorZ2-.5,C.white,nil,true)
	entrance.Transparency=1;entrance:SetAttribute("Purpose","BusinessLounge");entrance:SetAttribute("Zone","abroad")
	local sgn=bx(lm,"LoungeSign",px+.6,px+1,G+11.5,G+14.5,L.doorZ1-1,L.doorZ2+1,PM.navy,Enum.Material.Metal,true)
	label(sgn,"BUSINESS LOUNGE",Enum.NormalId.Right,PM.gold,true)
	bx(lm,"LoungeCarpet",L.x1,px,f,f+.06,L.z1,L.z2,Color3.fromRGB(40,58,74),Enum.Material.Carpet,true)
	-- concierge desk (staff marker for later packages; not a ReceptionistPost)
	bx(lm,"ConciergeDesk",-117,-111,f,f+3.8,7629,7639,C.oakDark,Enum.Material.Wood)
	bx(lm,"ConciergeTop",-117.4,-110.6,f+3.8,f+4.1,7628.6,7639.4,C.stone,Enum.Material.Marble,true)
	local post=mk(lm,"LoungeConciergePost",Vector3.new(2,5,1),CFrame.lookAt(Vector3.new(-120,G+3,7634),Vector3.new(-110,G+3,7634)),C.white,nil,true)
	post.Transparency=1;post:SetAttribute("LoungePost","concierge")
	-- bar along the runway glass
	bx(lm,"BarCounter",-150,-122,f,f+3.8,7615,7618,C.oakDark,Enum.Material.Wood)
	bx(lm,"BarTop",-150.4,-121.6,f+3.8,f+4.1,7614.6,7618.4,C.stone,Enum.Material.Marble,true)
	bx(lm,"BackBar",-150,-122,f,f+9,L.z1,L.z1+1.4,Color3.fromRGB(56,40,30),Enum.Material.Wood)
	bx(lm,"BackBarGlow",-149,-123,f+6,f+6.3,L.z1+1.4,L.z1+1.7,PM.gold,Enum.Material.Neon,true)
	for i,x in {-146,-140,-134,-128} do bx(lm,"Bottles",x-1.5,x+1.5,f+6.3,f+8,L.z1+1.4,L.z1+2,AWNINGS[i]:Lerp(Color3.new(1,1,1),.3),Enum.Material.Glass,true) end
	local barSign=bx(lm,"BarSign",-146,-126,f+9.5,f+11.5,L.z1+.2,L.z1+.6,PM.navy,Enum.Material.Metal,true)
	label(barSign,"THE MERIDIAN BAR",Enum.NormalId.Back,PM.gold,true)
	for _,x in {-147,-141,-135,-129,-124} do cyl(lm,"BarStool",x,7620,f,f+2.8,1.5,PM.bronze,Enum.Material.Metal,true) end
	-- three sofa groups (real Seats: players can sit down)
	for i,cz in {7632,7656,7678} do
		local cx=-132
		bx(lm,"Rug",cx-11,cx+11,f+.06,f+.1,cz-8,cz+8,if i==2 then PM.teal else Color3.fromRGB(150,124,96),Enum.Material.Fabric,true)
		-- the seat faces the coffee table (a Seat seats players along its LookVector; the backrest is behind it)
		mk(lm,"Sofa",Vector3.new(10,1.9,3.6),CFrame.lookAt(Vector3.new(cx,f+.95,cz-5.5),Vector3.new(cx,f+.95,cz)),C.fabricCharcoal,Enum.Material.Fabric,false,"Seat")
		bx(lm,"SofaBack",cx-5,cx+5,f+1.9,f+4.4,cz-7.6,cz-6.8,C.fabricCharcoal,Enum.Material.Fabric,true)
		for _,dx in {-3.5,3.5} do
			mk(lm,"Armchair",Vector3.new(3.6,1.9,3.6),CFrame.lookAt(Vector3.new(cx+dx,f+.95,cz+5.5),Vector3.new(cx+dx,f+.95,cz)),C.leather,Enum.Material.Leather,false,"Seat")
			bx(lm,"ArmchairBack",cx+dx-1.8,cx+dx+1.8,f+1.9,f+4,cz+7.1,cz+7.7,C.leather,Enum.Material.Leather,true)
		end
		bx(lm,"CoffeeTable",cx-3,cx+3,f,f+1.5,cz-1.6,cz+1.6,C.oak,Enum.Material.Wood,true)
		cyl(lm,"FloorLamp",cx+8.5,cz-6,f,f+6,.4,PM.bronze,Enum.Material.Metal,true)
		cyl(lm,"FloorLampShade",cx+8.5,cz-6,f+6,f+7.4,1.8,PM.glow,Enum.Material.Neon,true)
	end
	-- work pods on the west wall
	for _,z in {7630,7650,7670} do
		bx(lm,"WorkDesk",L.x1+.5,L.x1+5,f+2.6,f+3,z-4,z+4,C.oak,Enum.Material.Wood)
		bx(lm,"WorkDeskScreen",L.x1+.6,L.x1+1,f+3,f+5.6,z-2,z+2,C.screen,nil,true)
		mk(lm,"WorkChair",Vector3.new(2.4,1.8,2.4),CFrame.lookAt(Vector3.new(L.x1+7,f+.9,z),Vector3.new(L.x1,f+.9,z)),C.fabricBlue,Enum.Material.Fabric,false,"Seat")
	end
	-- buffet near the partition
	bx(lm,"Buffet",-112,-107,f,f+3.6,7664,7684,C.white,Enum.Material.Marble)
	for i=0,2 do bx(lm,"BuffetTray",-111,-108,f+3.6,f+4.1,7666+i*6,7670+i*6,PM.glow,Enum.Material.Neon,true) end
	local buf=bx(lm,"BuffetSign",-111,-108,f+6,f+7.5,7683.6,7684,PM.navy,Enum.Material.Metal,true)
	label(buf,"BUFFET",Enum.NormalId.Back,PM.gold,true)
	for _,p in {{L.x1+3,L.z1+3},{-108,L.z1+3},{L.x1+3,L.z2-3}} do
		cyl(lm,"Planter",p[1],p[2],f,f+3,3.4,PM.bronze,Enum.Material.Metal)
		ball(lm,"PlanterLeaves",p[1],f+5.4,p[2],5,C.foliage,Enum.Material.LeafyGrass,true)
	end
	-- ceiling cloud, pendant lights, screens
	bx(lm,"CeilingCloud",L.x1+2,px-2,G+13,G+13.6,L.z1+3,L.z2-3,PM.ivory,Enum.Material.SmoothPlastic,true)
	for i=1,5 do local x=L.x1+2+(px-L.x1-4)*i/6;bx(lm,"CeilingSlat",x-.6,x+.6,G+12.4,G+13,L.z1+3,L.z2-3,C.oak,Enum.Material.Wood,true) end
	local feature=bx(lm,"FeatureWall",L.x1,L.x1+.5,f+1,f+11.5,7676,7688,Color3.fromRGB(44,60,78),Enum.Material.Slate,true)
	label(feature,"PORT MERIDIAN\nBUSINESS LOUNGE",Enum.NormalId.Right,PM.gold,true,Enum.Font.Fondamento)
	for i,p in {{-138,7628},{-126,7628},{-138,7660},{-126,7660},{-138,7682},{-126,7682}} do
		local pend=cyl(lm,"Pendant",p[1],p[2],G+10.6,G+11.2,2.4,PM.glow,Enum.Material.Neon,true)
		if i==1 or i==4 then light(pend,30,.8,C.lightWarm) end
	end
	local scr=bx(lm,"FlightScreen",px-.4,px,f+5,f+10,7664,7680,C.screen,nil,true)
	label(scr,"FLIGHTS\nPM 102 · CITY AIRPORT · ON TIME\nVIP HELICOPTER · MERIDIAN GRAND · ON REQUEST",Enum.NormalId.Left,Color3.fromRGB(240,200,110),true,Enum.Font.RobotoMono)
	local info=bx(lm,"HeliInfo",L.x1,L.x1+.4,f+5,f+11,7640,7660,PM.navy,Enum.Material.SmoothPlastic,true)
	label(info,"VIP HELICOPTER TRANSFER\nMeridian Grand Hotel rooftop",Enum.NormalId.Right,PM.gold,true)
end
-- Helipad: landing surface = the marker part "Helipad" (attributes Purpose, PadId); ring, H, edge lights, windsock.
local function helipad(parent: Instance,def: any,deckBase: number)
	local c: CFrame=def.cf;local s: number=def.size;local x,z=c.X,c.Z;local top=c.Y
	local pad=bx(parent,"Helipad",x-s/2,x+s/2,deckBase,top,z-s/2,z+s/2,C.concrete,Enum.Material.Concrete)
	pad:SetAttribute("Purpose",def.purpose);pad:SetAttribute("PadId",def.id);pad:SetAttribute("PadName",def.name)
	local ring=mk(parent,"HelipadRing",Vector3.new(.06,s*.82,s*.82),CFrame.new(x,top+.03,z)*CFrame.Angles(0,0,math.pi/2),PM.yellow,nil,true);(ring :: Part).Shape=Enum.PartType.Cylinder
	local inner=mk(parent,"HelipadDisc",Vector3.new(.08,s*.74,s*.74),CFrame.new(x,top+.05,z)*CFrame.Angles(0,0,math.pi/2),Color3.fromRGB(70,74,78),Enum.Material.Concrete,true);(inner :: Part).Shape=Enum.PartType.Cylinder
	bx(parent,"HelipadH",x-6,x-3.6,top+.09,top+.12,z-7,z+7,PM.line,nil,true)
	bx(parent,"HelipadH",x+3.6,x+6,top+.09,top+.12,z-7,z+7,PM.line,nil,true)
	bx(parent,"HelipadH",x-3.6,x+3.6,top+.09,top+.12,z-1.2,z+1.2,PM.line,nil,true)
	local n=0
	for _,p in {{-1,-1},{0,-1},{1,-1},{1,0},{1,1},{0,1},{-1,1},{-1,0}} do
		n+=1
		local e=bx(parent,"HelipadEdgeLight",x+p[1]*(s/2-1)-.5,x+p[1]*(s/2-1)+.5,top,top+.6,z+p[2]*(s/2-1)-.5,z+p[2]*(s/2-1)+.5,Color3.fromRGB(120,200,120),Enum.Material.Neon,true)
		if n==1 then light(e,40,.7,Color3.fromRGB(200,255,210)) end
	end
	local wx,wz=x+s/2+3,z-s/2+3
	cyl(parent,"WindsockPole",wx,wz,deckBase,deckBase+10,.35,C.metalSoft,Enum.Material.Metal)
	local sock=mk(parent,"Windsock",Vector3.new(4,1.2,1.2),CFrame.new(wx+2,deckBase+9.4,wz)*CFrame.Angles(0,0,math.rad(-12)),Color3.fromRGB(236,120,40),Enum.Material.Fabric,true);(sock :: Part).Shape=Enum.PartType.Cylinder
	return pad
end
local function vipAirport(m: Model)
	local v=folder(m,"VipHelipad")
	local def=Plan.HELIPADS.airport
	local x,z=def.cf.X,def.cf.Z
	helipad(v,def,G)
	local fx1,fx2,fz1,fz2=x-36,x+36,z-36,z+36
	for _,s in {{fx1,fx2,fz1,fz1+.4},{fx2-.4,fx2,fz1,fz2},{fx1+16,fx2,fz2-.4,fz2},{fx1,fx1+.4,fz1,fz2}} do
		bx(v,"HelipadFence",s[1],s[2],G+.1,G+3.6,s[3],s[4],C.metalSoft,Enum.Material.Metal)
	end
	for _,gx in {fx1+.4,fx1+16} do cyl(v,"GatePost",gx,fz2-.2,G+.1,G+5,.8,PM.gold,Enum.Material.Metal) end
	local kiosk=glassy(bx(v,"VipTerminal",250,268,G+.1,G+9,7676,7690,PM.tealGlass),.3)
	local _=kiosk
	bx(v,"VipTerminalRoof",248,270,G+9,G+10,7674,7692,PM.ivory,Enum.Material.Metal)
	local s=bx(v,"VipTerminalSign",250,268,G+10,G+12.5,7691.6,7692,PM.navy,Enum.Material.Metal,true)
	label(s,"VIP HELICOPTER TERMINAL",Enum.NormalId.Back,PM.gold,true)
end

------------------------------------------------------------------------------------------------ arrival plaza
local function plaza(m: Model)
	local pz=folder(m,"ArrivalPlaza")
	local pl=A.plaza
	local lay=Plan.VIP_LIMO.layby;local taxi=Plan.TAXI_RANK
	bx(pz,"PlazaPaving",pl.x1,pl.x2,G+.1,PLAZA,pl.z1,lay.z1,PM.paver,Enum.Material.Pavement)
	bx(pz,"PlazaPaving",taxi.x2,lay.x1,G+.1,PLAZA,lay.z1,pl.z2,PM.paver,Enum.Material.Pavement)
	bx(pz,"MeridianLine",-1.2,1.2,PLAZA,PLAZA+.02,pl.z1,lay.z1,PM.gold,Enum.Material.Metal,true)
	bx(pz,"PlazaWalk",pl.x1,pl.x2,PLAZA,PLAZA+.015,7723,7733,PM.paverDark,Enum.Material.Granite,true)
	for _,r in {lay,taxi} do bx(pz,"LayBy",r.x1,r.x2,G+.02,ROAD,r.z1,r.z2,PM.asphalt,Enum.Material.Asphalt) end
	-- flag row in front of the terminal (Port Meridian: navy with a gold band; teal)
	for i,x in Plan.PLAZA_FLAGS do flagpole(pz,x,7698,PLAZA,30,if i%2==0 then PM.navy else PM.teal,if i%2==0 then PM.gold else nil) end
	for _,s in Plan.BENCHES do if s.z>7700 and s.z<7730 then bench(pz,s) end end
	local k=300
	for _,x in {-130,-40,40,130} do
		bx(pz,"Planter",x-4.5,x+4.5,PLAZA,PLAZA+1.8,7738,7747,PM.granite,Enum.Material.Granite)
		k+=1;tree(pz,x,7742.5,k,PLAZA+1.8)
	end
	for i,p in {{-196,7694},{196,7694},{-60,7745},{60,7745}} do lamp(pz,p[1],p[2],i>=3,PLAZA) end
	K.kiosk(pz,-24,7742,PLAZA,-1,"promenade","Meridian Waterfront")
	-- metro entrance (decor: the stair is a dark inlay, the floor stays walkable)
	local me=folder(pz,"MetroEntrance")
	bx(me,"MetroStairs",-196,-182,PLAZA,PLAZA+.03,7700,7712,Color3.fromRGB(26,28,32),Enum.Material.Slate,true)
	for i=0,3 do bx(me,"MetroStep",-195,-183,PLAZA+.03,PLAZA+.06,7701+i*2.6,7701.6+i*2.6,C.metalSoft,Enum.Material.Metal,true) end
	for _,s in {{-197,-196.5,7699,7713},{-181.5,-181,7699,7713},{-197,-181,7712.5,7713}} do bx(me,"MetroRail",s[1],s[2],PLAZA,PLAZA+3.4,s[3],s[4],C.metal,Enum.Material.Metal) end
	glassy(bx(me,"MetroCanopy",-198,-180,PLAZA+9,PLAZA+9.4,7698,7714,PM.tealGlass,nil,true),.35)
	for _,x in {-197.5,-180.5} do bx(me,"MetroCanopyPost",x-.3,x+.3,PLAZA,PLAZA+9,7713.4,7714,C.metal,Enum.Material.Metal,true) end
	cyl(me,"MetroPylon",-178,7698,PLAZA,PLAZA+12,.6,C.metal,Enum.Material.Metal)
	local msign=bx(me,"MetroSign",-180,-176,PLAZA+12,PLAZA+16,7697.6,7698.4,Color3.fromRGB(200,40,50),Enum.Material.Neon,true)
	both(msign,"M\nMETRO","z",Color3.new(1,1,1),true)
	-- taxi rank and VIP limousine stand (canopy, red carpet, marker, a waiting limousine in bay 2)
	for i,x in {-188,-164,-140} do car(pz,CFrame.lookAt(Vector3.new(x,ROAD,7762),Vector3.new(x-10,ROAD,7762)),11.5,6.2,Color3.fromRGB(232,190,64),"taxi");local _=i end
	cyl(pz,"TaxiSignPost",-198,7754,PLAZA,PLAZA+10,.5,C.metal,Enum.Material.Metal)
	local ts=bx(pz,"TaxiSign",-200,-196,PLAZA+10,PLAZA+12.4,7753.7,7754.3,Color3.fromRGB(232,190,64),Enum.Material.Neon,true)
	both(ts,"TAXI","z",Color3.fromRGB(30,30,30),true)
	local vip=folder(pz,"VipLimoArea")
	bx(vip,"VipCanopy",lay.x1+4,lay.x2-4,G+12,G+12.6,lay.z1-10,lay.z2,PM.navy,Enum.Material.Metal,true)
	bx(vip,"VipCanopyFascia",lay.x1+4,lay.x2-4,G+11.4,G+12,lay.z2-.4,lay.z2,PM.gold,Enum.Material.Metal,true)
	for _,x in {lay.x1+12,lay.x2-12} do cyl(vip,"VipCanopyColumn",x,lay.z1-8,PLAZA,G+12,.9,PM.gold,Enum.Material.Metal) end
	local vs=bx(vip,"VipSign",lay.x1+20,lay.x2-20,G+12.6,G+15,lay.z1-6,lay.z1-5.6,PM.navy,Enum.Material.Metal,true)
	both(vs,"VIP CHAUFFEUR SERVICE","z",PM.gold,true)
	local cl=bx(vip,"VipCanopyLight",lay.x1+30,lay.x2-30,G+11.6,G+12,lay.z1-4,lay.z1-2,PM.glow,Enum.Material.Neon,true)
	light(cl,26,.8,C.lightWarm)
	bx(vip,"RedCarpet",76,84,PLAZA,PLAZA+.05,A.terminal.z2,lay.z1-3,PM.red,Enum.Material.Fabric,true)
	bx(vip,"RedCarpet",84,lay.x2-12,PLAZA,PLAZA+.05,lay.z1-7,lay.z1-3,PM.red,Enum.Material.Fabric,true)
	for _,z in {7700,7716,7732} do for _,x in {75,85} do cyl(vip,"Stanchion",x,z,PLAZA,PLAZA+3.2,.5,PM.gold,Enum.Material.Metal,true) end end
	local stand=mk(vip,"VipLimoStand",Vector3.new(8,.2,22),Plan.VIP_LIMO.stand*CFrame.new(0,.1,0),PM.gold,nil,true)
	stand.Transparency=1
	stand:SetAttribute("Purpose","VIP");stand:SetAttribute("Zone","abroad");stand:SetAttribute("Bays",2);stand:SetAttribute("Bay2",Plan.VIP_LIMO.bay2)
	car(vip,Plan.VIP_LIMO.bay2,19,6.6,Color3.fromRGB(18,20,24),"limo")
	bx(vip,"BayMarking",lay.x1+2,lay.x2-2,ROAD,ROAD+.02,lay.z2-.5,lay.z2-.2,PM.yellow,nil,true)
	local bm=bx(vip,"BayText",156,196,ROAD,ROAD+.02,7758,7766,PM.asphalt,Enum.Material.Asphalt,true)
	label(bm,"VIP",Enum.NormalId.Top,PM.yellow)
end

------------------------------------------------------------------------------------------------ streets
type Net=Plan.Net
local function along(r: Plan.Road,a1: number,a2: number,off1: number,off2: number,y1: number,y2: number): (number,number,number,number,number,number)
	if r.axis=="x" then return math.min(a1,a2),math.max(a1,a2),y1,y2,r.c+math.min(off1,off2),r.c+math.max(off1,off2) end
	return r.c+math.min(off1,off2),r.c+math.max(off1,off2),y1,y2,math.min(a1,a2),math.max(a1,a2)
end
-- [a1,a2] minus cut intervals
local function spans(a1: number,a2: number,cuts: {{number}}): {{number}}
	table.sort(cuts,function(p,q) return p[1]<q[1] end)
	local out: {{number}}={};local cur=a1
	for _,c in cuts do
		if c[2]>cur and c[1]<a2 then
			if c[1]>cur+.5 then table.insert(out,{cur,c[1]}) end
			cur=math.max(cur,c[2])
		end
	end
	if a2>cur+.5 then table.insert(out,{cur,a2}) end
	return out
end
local function streets(m: Model,net: Net)
	local f=folder(m,"Streets")
	local walkOff=Plan.walkOff
	for _,r in Plan.ROADS do
		local refs=net.byRoad[r.id]
		-- asphalt: x-roads run through; z-roads stop at the crossing asphalt (no coplanar overlap)
		local acuts: {{number}}={}
		if r.axis=="z" then for _,ref in refs do table.insert(acuts,{ref.a-ref.other.width/2,ref.a+ref.other.width/2}) end end
		local aspans=spans(r.a1,r.a2,acuts)
		local carriage: {{number}}=if r.median>0 then {{-r.width/2,-r.median/2},{r.median/2,r.width/2}} else {{-r.width/2,r.width/2}}
		-- markings are interrupted over every junction box (+2)
		local mcuts: {{number}}={}
		for _,ref in refs do table.insert(mcuts,{ref.a-ref.other.width/2-2,ref.a+ref.other.width/2+2}) end
		local mspans=spans(r.a1,r.a2,mcuts)
		for _,s in aspans do
			for _,cw in carriage do
				local x1,x2,y1,y2,z1,z2=along(r,s[1],s[2],cw[1],cw[2],G+.02,ROAD)
				bx(f,"Road",x1,x2,y1,y2,z1,z2,PM.asphalt,Enum.Material.Asphalt)
			end
		end
		for _,s in mspans do
			if r.median==0 then
				for _,o in {-.35,.35} do
					local x1,x2,y1,y2,z1,z2=along(r,s[1],s[2],o-.15,o+.15,ROAD,ROAD+.03)
					bx(f,"CentreLine",x1,x2,y1,y2,z1,z2,PM.yellow,nil,true)
				end
			end
			if r.lanes>1 then
				local lw=(r.width-r.median)/2/r.lanes
				for i=1,r.lanes-1 do
					for _,sd in {-1,1} do
						local o=sd*(r.median/2+i*lw)
						local x1,x2,y1,y2,z1,z2=along(r,s[1],s[2],o-.15,o+.15,ROAD,ROAD+.03)
						bx(f,"LaneLine",x1,x2,y1,y2,z1,z2,PM.line,nil,true)
					end
				end
			end
		end
		-- sidewalks (cut where a crossing road continues to that side, and at the lay-bys)
		if r.walk>0 then
			for _,sd in {-1,1} do
				local wcuts: {{number}}={}
				for _,ref in refs do
					if Plan.extends(ref.other,r.c,sd) then table.insert(wcuts,{ref.a-ref.other.width/2-ref.other.walk,ref.a+ref.other.width/2+ref.other.walk}) end
				end
				local gaps: {{number}}=r.gaps or {}
					for _,g in gaps do if g[1]==sd then table.insert(wcuts,{g[2],g[3]}) end end
				for _,s in spans(r.a1,r.a2,wcuts) do
					local o1,o2=sd*r.width/2,sd*(r.width/2+r.walk)
					local x1,x2,y1,y2,z1,z2=along(r,s[1],s[2],o1,o2,G-.175,WALK)
					bx(f,"Sidewalk",x1,x2,y1,y2,z1,z2,PM.walkway,Enum.Material.Pavement)
					local k1,k2,ky1,ky2,kz1,kz2=along(r,s[1],s[2],o1,o1+sd*.6,WALK,WALK+.02)
					bx(f,"Kerb",k1,k2,ky1,ky2,kz1,kz2,PM.kerb,Enum.Material.Granite,true)
				end
			end
		end
	end
	-- junctions: corner pads, stop lines, zebras, signals, street names
	for _,j in net.junctions do
		local rx,rz=j.rx,j.rz
		for _,qx in {-1,1} do
			for _,qz in {-1,1} do
				if rx.walk>0 and rz.walk>0 and Plan.extends(rx,j.x,qx) and Plan.extends(rz,j.z,qz) then
					local xa,xb=j.x+qx*rz.width/2,j.x+qx*(rz.width/2+rz.walk)
					local za,zb=j.z+qz*rx.width/2,j.z+qz*(rx.width/2+rx.walk)
					bx(f,"CornerPad",math.min(xa,xb),math.max(xa,xb),G-.175,WALK,math.min(za,zb),math.max(za,zb),PM.walkway,Enum.Material.Pavement)
				end
			end
		end
		for _,pair in {{rx,rz},{rz,rx}} do
			local r,o=pair[1],pair[2]
			local a=if r.axis=="x" then j.x else j.z
			-- stop lines on each approach of r
			for _,d in {1,-1} do
				if Plan.extends(r,a,-d) then
					local sa=a-d*(walkOff(o)+4.5)
					local sign=if r.axis=="x" then d else -d
					local x1,x2,y1,y2,z1,z2=along(r,sa-.4,sa+.4,sign*r.median/2,sign*r.width/2,ROAD,ROAD+.03)
					bx(f,"StopLine",x1,x2,y1,y2,z1,z2,PM.line,nil,true)
				end
			end
			-- zebras across o, along r's sidewalk lines on the sides o continues to
			if r.walk>0 then
				for _,sd in {-1,1} do
					if Plan.extends(o,r.c,sd) then
						local line=r.c+sd*walkOff(r)
						local oc=o.c
						local segs: {{number}}=if o.median>0 then {{-o.width/2,-o.median/2},{o.median/2,o.width/2}} else {{-o.width/2,o.width/2}}
						for _,sg in segs do
							local n=math.max(2,math.floor((sg[2]-sg[1])/4.6))
							local step=(sg[2]-sg[1])/n
							for i=0,n-1 do
								local c1=oc+sg[1]+i*step+step*.25;local c2=oc+sg[1]+i*step+step*.75
								if o.axis=="z" then bx(f,"Zebra",c1,c2,ROAD,ROAD+.03,line-3,line+3,PM.line,nil,true)
								else bx(f,"Zebra",line-3,line+3,ROAD,ROAD+.03,c1,c2,PM.line,nil,true) end
							end
						end
					end
				end
			end
		end
		-- two signal poles on opposite corners: post, housing, four lamp plates (client sets their colour)
		for i,q in {{-1,-1},{1,1}} do
			local px,pzz=j.x+q[1]*(rz.width/2+1.4),j.z+q[2]*(rx.width/2+1.4)
			cyl(f,"SignalPost",px,pzz,WALK,WALK+13,.6,C.metal,Enum.Material.Metal)
			bx(f,"SignalHousing",px-.9,px+.9,WALK+10,WALK+13,pzz-.9,pzz+.9,Color3.fromRGB(28,30,32),Enum.Material.Metal,true)
			for _,fc in {{1,0,"x"},{-1,0,"x"},{0,1,"z"},{0,-1,"z"}} :: {{any}} do
				local lx,lz=px+fc[1]*.95,pzz+fc[2]*.95
				local lampPart=bx(f,"SignalLamp",lx-(if fc[1]~=0 then .06 else .55),lx+(if fc[1]~=0 then .06 else .55),WALK+11.6,WALK+12.7,lz-(if fc[2]~=0 then .06 else .55),lz+(if fc[2]~=0 then .06 else .55),Color3.fromRGB(200,40,40),Enum.Material.Neon,true)
				lampPart:SetAttribute("Junction",j.id);lampPart:SetAttribute("Axis",fc[3])
				CollectionService:AddTag(lampPart,"MetroSignal")
			end
			if i==1 then
				local blade=bx(f,"StreetName",px-6,px+6,WALK+8.4,WALK+9.6,pzz-.1,pzz+.1,Color3.fromRGB(28,70,60),Enum.Material.Metal,true)
				both(blade,rx.name.."  ·  "..rz.name,"z")
			end
		end
	end
	-- street furniture along every sidewalk (MetroPlan positions - the walkers step round the same list): lamps at
	-- the kerb, trees on the property side
	for _,p in Plan.STREET_LAMPS do lamp(f,p.x,p.z,p.lit,WALK) end
	for _,p in Plan.STREET_TREES do tree(f,p.x,p.z,p.k,WALK) end
	-- bus shelters
	for _,b in Plan.BUS_STOPS do
		local fz=b.face.Z;local back=b.z-fz*1.2
		bx(f,"ShelterRoof",b.x-6,b.x+6,WALK+8,WALK+8.5,math.min(back,b.z+fz*2.5),math.max(back,b.z+fz*2.5),PM.navy,Enum.Material.Metal,true)
		glassy(bx(f,"ShelterGlass",b.x-5.5,b.x+5.5,WALK+.3,WALK+7.6,back-.15,back+.15,C.glass,nil,true),.5)
		for _,x in {b.x-5.6,b.x+5.6} do bx(f,"ShelterPost",x-.2,x+.2,WALK,WALK+8,back-.2,back+.2,C.metal,Enum.Material.Metal,true) end
		bx(f,"ShelterBench",b.x-4,b.x+4,WALK+1.5,WALK+2,back+fz*.4-.6,back+fz*.4+.6,C.oak,Enum.Material.Wood,true)
		local sg=bx(f,"BusStopSign",b.x+6.2,b.x+7.4,WALK+5,WALK+9,b.z-.2,b.z+.2,PM.navy,Enum.Material.Metal,true)
		both(sg,"BUS\n"..b.line,"z",PM.gold,true)
	end
end

------------------------------------------------------------------------------------------------ boulevard
local function boulevard(m: Model)
	local b=folder(m,"MeridianBoulevard")
	for _,md in Plan.MEDIAN do
		bx(b,"Median",md.x1,md.x2,G+.02,MED,md.z1,md.z2,PM.graniteLight,Enum.Material.Granite)
		bx(b,"MedianLawn",-10,10,MED,MED+.04,md.z1+12,md.z2-12,PM.lawn,Enum.Material.Grass,true)
		for _,sx in {-1,1} do bx(b,"MedianLawn",sx*19.5-2.5,sx*19.5+2.5,MED,MED+.04,md.z1+6,md.z2-6,PM.lawn,Enum.Material.Grass,true) end
		for _,sx in {-15,15} do bx(b,"MedianWalk",sx-3,sx+3,MED,MED+.02,md.z1+2,md.z2-2,PM.paver,Enum.Material.Pavement,true) end
	end
	-- monument wall at the north tip, facing the terminal
	bx(b,"MonumentBase",-11,11,MED,MED+.8,7815,7819,PM.granite,Enum.Material.Granite)
	local wall=bx(b,"MonumentWall",-10,10,MED+.8,MED+3.4,7816,7818,PM.navy,Enum.Material.Granite)
	label(wall,"PORT MERIDIAN",Enum.NormalId.Front,PM.gold,true,Enum.Font.Fondamento)
	label(wall,"MERIDIAN BOULEVARD",Enum.NormalId.Back,PM.gold,true)
	-- "Meridian Arc": a bronze half ring over the monument that frames the view down the boulevard
	local arcR,arcY,segs=9.4,MED+3.4,10
	for i=0,segs-1 do
		local a1,a2=i/segs*math.pi,(i+1)/segs*math.pi
		local p1=Vector3.new(math.cos(a1)*arcR,arcY+math.sin(a1)*arcR,7817)
		local p2=Vector3.new(math.cos(a2)*arcR,arcY+math.sin(a2)*arcR,7817)
		mk(b,"MeridianArc",Vector3.new(1.3,1.3,(p2-p1).Magnitude+.5),CFrame.lookAt((p1+p2)/2,p2),if i%2==0 then PM.bronze else PM.gold,Enum.Material.Metal,true)
	end
	-- fountains
	for i,z in {7880,8000,8210} do
		cyl(b,"FountainRim",0,z,MED,MED+1.3,20,PM.ivory,Enum.Material.Marble)
		glassy(cyl(b,"FountainWater",0,z,MED+1.3,MED+1.4,18.6,PM.water,nil,true),.2)
		cyl(b,"FountainColumn",0,z,MED+1.3,MED+5,3,PM.ivory,Enum.Material.Marble)
		local jet=cyl(b,"FountainJet",0,z,MED+5,MED+15,1.1,Color3.fromRGB(196,232,240),Enum.Material.Neon,true);jet.Transparency=.35
		for _,d in {{1,0},{-1,0},{0,1},{0,-1}} do
			local sj=cyl(b,"FountainSpray",d[1]*6,z+d[2]*6,MED+1.4,MED+5.5,.5,Color3.fromRGB(196,232,240),Enum.Material.Neon,true);sj.Transparency=.45
		end
		light(cyl(b,"FountainGlow",0,z,MED+1.4,MED+1.6,6,PM.glow,Enum.Material.Neon,true),22,.7,Color3.fromRGB(180,230,255))
		local _=i
	end
	-- the meridian globe between the first two fountains
	bx(b,"GlobePlinth",-3.5,3.5,MED,MED+5,7936,7944,PM.granite,Enum.Material.Granite)
	ball(b,"Globe",0,MED+10,7940,9,PM.gold,Enum.Material.Metal)
	-- armillary rings (two meridians + the equator), each from 14 bronze segments
	local gc=Vector3.new(0,MED+10,7940)
	for k,frame in {CFrame.new(gc),CFrame.new(gc)*CFrame.Angles(0,math.pi/2,0),CFrame.new(gc)*CFrame.Angles(math.pi/2,0,0)} do
		local r,n=6.9,14
		for i=0,n-1 do
			local a1,a2=i/n*math.pi*2,(i+1)/n*math.pi*2
			local p1=frame:PointToWorldSpace(Vector3.new(math.cos(a1)*r,math.sin(a1)*r,0))
			local p2=frame:PointToWorldSpace(Vector3.new(math.cos(a2)*r,math.sin(a2)*r,0))
			mk(b,if k==3 then "GlobeEquator" else "GlobeMeridian",Vector3.new(.45,.45,(p2-p1).Magnitude+.2),CFrame.lookAt((p1+p2)/2,p2),PM.bronze,Enum.Material.Metal,true)
		end
	end
	-- reflecting pool towards the hotel
	bx(b,"PoolRim",-9,9,MED,MED+.8,8250,8302,PM.ivory,Enum.Material.Marble)
	glassy(bx(b,"PoolWater",-8,8,MED+.8,MED+.85,8251,8301,PM.water,nil,true),.15)
	-- trees on the outer lawn strips (clear of the flags)
	for _,p in Plan.MEDIAN_TREES do tree(b,p.x,p.z,p.k,MED+.04) end
	-- flags along the median lawns, benches, double lamps
	for _,z in Plan.MEDIAN_FLAGS do for _,sx in {-21,21} do flagpole(b,sx,z,MED,26,if z%20==0 then PM.navy else PM.teal,if z%20==0 then PM.gold else nil) end end
	for _,s in Plan.BENCHES do if math.abs(s.x)<10 and s.z>7800 and s.z<8320 then bench(b,s) end end
	local n=0
	for _,z in Plan.MEDIAN_LAMPS do
		n+=1
		cyl(b,"BoulevardLamp",0,z+12,MED,MED+16,.7,C.metal,Enum.Material.Metal)
		bx(b,"BoulevardLampArm",-5,5,MED+15.6,MED+16.2,z+11.7,z+12.3,C.metal,Enum.Material.Metal,true)
		for _,sx in {-5,5} do
			local hd=bx(b,"BoulevardLampHead",sx-1.4,sx+1.4,MED+15,MED+15.6,z+10.6,z+13.4,PM.glow,Enum.Material.Neon,true)
			if sx<0 and n%2==1 then light(hd,30,.75) end
		end
	end
	-- retail pavilions along the sidewalks
	for i,pv in Plan.PAVILIONS do
		local s=pv.side
		local front,back=s*66,s*96
		bx(b,"PavilionCore",math.min(s*70,back),math.max(s*70,back),G+.1,PLAZA+11,pv.z1,pv.z2,STONE_TONES[(i%6)+1],Enum.Material.Limestone)
		local show=glassy(bx(b,"PavilionGlass",math.min(front,s*70),math.max(front,s*70),G+.1,PLAZA+10,pv.z1+1.5,pv.z2-1.5,Color3.fromRGB(200,176,140)),.3)
		glowTag(show,SHOP_GLOW)
		bx(b,"PavilionLight",math.min(s*69,s*69.6),math.max(s*69,s*69.6),PLAZA+8.6,PLAZA+9.2,pv.z1+3,pv.z2-3,PM.glow,Enum.Material.Neon,true)
		bx(b,"PavilionRoof",math.min(s*64,s*98),math.max(s*64,s*98),PLAZA+11,PLAZA+12.2,pv.z1-1,pv.z2+1,PM.ivory,Enum.Material.Metal)
		local aw=bx(b,"PavilionAwning",math.min(s*61,s*66),math.max(s*61,s*66),PLAZA+8.2,PLAZA+8.8,pv.z1+3,pv.z2-3,AWNINGS[(i%#AWNINGS)+1],Enum.Material.Fabric,true)
		local _=aw
		local sg=bx(b,"PavilionSign",math.min(s*63.6,s*64),math.max(s*63.6,s*64),PLAZA+11,PLAZA+12.2,pv.z1+8,pv.z2-8,PM.navy,Enum.Material.Metal,true)
		label(sg,pv.name,if s<0 then Enum.NormalId.Right else Enum.NormalId.Left,PM.gold,true)
	end
	-- media screens on the pavilion roofs at Exchange Street, facing the junction (glowing text, generic ads)
	local SCREENS={"GLOBAL AI SUMMIT\nConvention week in Port Meridian","MERIDIAN EXCHANGE\nMarkets open around the clock",
		"FLY BUSINESS\nCity Airport - Port Meridian daily","HARBOUR WHEEL\nThe best view of the bay"}
	local si=0
	for _,sz in {{8036,1},{8124,-1}} do
		for _,sx in {-1,1} do
			si+=1
			local z,f=sz[1],sz[2]
			local frame=bx(b,"MediaScreenFrame",sx*81-13,sx*81+13,PLAZA+12.2,PLAZA+27,z-.6,z+.6,Color3.fromRGB(28,30,34),Enum.Material.Metal,true)
			local _=frame
			local scr=bx(b,"MediaScreen",sx*81-12,sx*81+12,PLAZA+13,PLAZA+26.2,math.min(z+f*.6,z+f*.75),math.max(z+f*.6,z+f*.75),Color3.fromRGB(24,52,96),Enum.Material.Neon,true)
			label(scr,SCREENS[si],if f>0 then Enum.NormalId.Back else Enum.NormalId.Front,Color3.fromRGB(255,236,190),true)
		end
	end
	-- tower forecourts: paving, planters with trees, name monolith, company flags
	local k=700
	for _,b2 in City.BUILDINGS do
		if b2.zone=="abroad" and b2.kind=="tower" then
			local s=if b2.frame.X<0 then -1 else 1
			local tz=b2.frame.Z
			bx(b,"Forecourt",math.min(s*64,s*132),math.max(s*64,s*132),G+.1,PLAZA,tz-24,tz+24,PM.paverDark:Lerp(PM.paver,.5),Enum.Material.Granite)
			for _,dz in {-15,15} do
				bx(b,"ForecourtPlanter",math.min(s*88,s*108),math.max(s*88,s*108),PLAZA,PLAZA+1.6,tz+dz-3,tz+dz+3,PM.granite,Enum.Material.Granite)
				k+=1;tree(b,s*98,tz+dz,k,PLAZA+1.6)
			end
			local mono=bx(b,"NameMonolith",math.min(s*118,s*119.4),math.max(s*118,s*119.4),PLAZA,PLAZA+7,tz+9,tz+17,PM.granite,Enum.Material.Granite)
			label(mono,string.upper(b2.name),if s<0 then Enum.NormalId.Right else Enum.NormalId.Left,b2.accent:Lerp(Color3.new(1,1,1),.4),true)
			for _,dz in {-21,21} do flagpole(b,s*126,tz+dz,PLAZA,22,b2.accent,nil) end
		end
	end
end

------------------------------------------------------------------------------------------------ hotel + client towers
local function towers(m: Model)
	local tf=folder(m,"ClientTowers")
	for _,b in City.BUILDINGS do
		if b.zone=="abroad" then K.building(if b.kind=="hotel" then m else tf,b) end
	end
	-- the Meridian Grand Hotel: rooftop helipad, roof exit, illuminated name
	local hotel=m:FindFirstChild("Hotel_intl_hotel")
	local roof=folder(if hotel then hotel else m,"RooftopHelipad")
	local def=Plan.HELIPADS.hotel
	helipad(roof,def,Plan.HOTEL_ROOF)
	local top=Plan.HOTEL_ROOF
	bx(roof,"RoofLiftHouse",26,36,top,top+10,8388,8400,PM.ivory,Enum.Material.Concrete)
	bx(roof,"RoofLiftDoor",25.8,26,top,top+7.5,8391,8397,PM.bronze,Enum.Material.Metal,true)
	local exit=mk(roof,"HelipadExit",Vector3.new(2,5,2),CFrame.lookAt(Vector3.new(23,top+2.5,8394),Vector3.new(30,top+2.5,8394)),C.white,nil,true)
	exit.Transparency=1;exit:SetAttribute("To","intl_hotel");exit:SetAttribute("PadId",def.id)
	local hs=bx(roof,"HotelRoofSign",-44,44,top-14,top-6,8378.6,8379.2,PM.navy,Enum.Material.Metal,true)
	label(hs,"MERIDIAN GRAND HOTEL",Enum.NormalId.Front,PM.gold,true,Enum.Font.Fondamento)
	bx(roof,"HotelRoofSignGlow",-44,44,top-14.6,top-14,8378.4,8379.2,PM.gold,Enum.Material.Neon,true)
end

------------------------------------------------------------------------------------------------ background towers
local function crown(md: Model,l: Plan.Lot,x1: number,x2: number,z1: number,z2: number,top: number,accent: Color3)
	local w,d=x2-x1,z2-z1
	local cap=bx(md,"Roof",x1-.4,x2+.4,top,top+1.2,z1-.4,z2+.4,C.stoneDeep,Enum.Material.Concrete)
	local _=cap
	local cx,cz=(x1+x2)/2,(z1+z2)/2
	if l.crown=="plant" then
		bx(md,"PlantRoom",cx-w*.25,cx+w*.2,top+1.2,top+6.5,cz-d*.2,cz+d*.25,C.metalSoft,Enum.Material.Metal,true)
	elseif l.crown=="spire" then
		bx(md,"CrownBox",cx-w*.3,cx+w*.3,top+1.2,top+14,cz-d*.3,cz+d*.3,accent,Enum.Material.Glass,true)
		cyl(md,"Spire",cx,cz,top+14,top+14+math.min(60,l.h*.22),1.4,C.metal,Enum.Material.Metal,true)
		bx(md,"Beacon",cx-.7,cx+.7,top+14+math.min(60,l.h*.22),top+15.4+math.min(60,l.h*.22),cz-.7,cz+.7,Color3.fromRGB(230,70,60),Enum.Material.Neon,true)
	elseif l.crown=="slant" then
		local wd=mk(md,"SlantTop",Vector3.new(w,math.min(18,w*.4),d),CFrame.new(cx,top+1.2+math.min(18,w*.4)/2,cz)*CFrame.Angles(0,if l.face=="n" then 0 elseif l.face=="s" then math.pi elseif l.face=="w" then math.pi/2 else -math.pi/2,0),accent,Enum.Material.Glass,true,"WedgePart")
		local _w=wd
	elseif l.crown=="band" then
		bx(md,"CrownBand",x1-.3,x2+.3,top-3.4,top-1.8,z1-.3,z2+.3,accent,Enum.Material.Neon,true)
	elseif l.crown=="pyramid" then
		bx(md,"CrownStep",cx-w*.36,cx+w*.36,top+1.2,top+6,cz-d*.36,cz+d*.36,C.stoneDeep,Enum.Material.Limestone,true)
		bx(md,"CrownStep",cx-w*.2,cx+w*.2,top+6,top+11,cz-d*.2,cz+d*.2,accent,Enum.Material.Glass,true)
	end
end
local function backgroundTower(parent: Instance,l: Plan.Lot)
	local md=folder(parent,"Tower_"..l.id,Enum.ModelStreamingMode.Atomic)
	md:SetAttribute("Lot",l.id);md:SetAttribute("Height",l.h)
	local x1,x2,z1,z2=l.x-l.w/2,l.x+l.w/2,l.z-l.d/2,l.z+l.d/2
	local top=G+l.h
	local tint=GLASS_TINTS[l.tone];local stone=STONE_TONES[l.tone];local plaster=PLASTER_TONES[l.tone]
	local accent=if l.tone%2==0 then PM.gold else tint:Lerp(Color3.new(1,1,1),.25)
	local ph=G+(if l.style=="low" then 0 else 12+(l.tone%3)*2)
	if l.style~="low" then
		bx(md,"Podium",x1,x2,G+.1,ph,z1,z2,PM.granite:Lerp(stone,.35),Enum.Material.Granite)
		local shop=glassy(bx(md,"ShopGlass",x1-.3,x2+.3,G+1.6,ph-3,z1-.3,z2+.3,Color3.fromRGB(196,170,130),nil,true),.25)
		glowTag(shop,SHOP_GLOW)
		local fx1,fx2,fz1,fz2=x1+4,x2-4,z1-3.2,z1-.3
		if l.face=="s" then fz1,fz2=z2+.3,z2+3.2 elseif l.face=="w" then fx1,fx2,fz1,fz2=x1-3.2,x1-.3,z1+4,z2-4 elseif l.face=="e" then fx1,fx2,fz1,fz2=x2+.3,x2+3.2,z1+4,z2-4 end
		local aw=bx(md,"Awning",fx1,fx2,ph-3.4,ph-2.8,fz1,fz2,AWNINGS[l.tone],Enum.Material.Fabric,true)
		local face=if l.face=="n" then Enum.NormalId.Front elseif l.face=="s" then Enum.NormalId.Back elseif l.face=="w" then Enum.NormalId.Left else Enum.NormalId.Right
		label(aw,SHOP_NAMES[(Plan.hash(l.id)%#SHOP_NAMES)+1],face,PM.ivory,true)
	end
	local s=l.style
	if s=="glass" then
		local core=bx(md,"Core",x1+2,x2-2,ph,top,z1+2,z2-2,tint,Enum.Material.Glass)
		if l.glow then
			core.Transparency=.35
			glowTag(bx(md,"WindowGlow",x1+3.5,x2-3.5,ph+1,top-1,z1+3.5,z2-3.5,Color3.fromRGB(58,64,70),Enum.Material.SmoothPlastic,true),WINDOW_GLOW)
		end
		bx(md,"Fin",l.x-.6,l.x+.6,ph,top,z1+1.4,z2-1.4,C.metal,Enum.Material.Metal,true)
		bx(md,"Fin",x1+1.4,x2-1.4,ph,top,l.z-.6,l.z+.6,C.metal,Enum.Material.Metal,true)
		local nb=math.clamp(math.floor((top-ph)/42),2,6)
		for k=1,nb do local y=ph+(top-ph)*k/(nb+1);bx(md,"Spandrel",x1+1.6,x2-1.6,y-.9,y+.9,z1+1.6,z2-1.6,stone,Enum.Material.Limestone,true) end
		crown(md,l,x1+2,x2-2,z1+2,z2-2,top,accent)
	elseif s=="stone" or s=="res" then
		local core=bx(md,"Core",x1+1.5,x2-1.5,ph,top,z1+1.5,z2-1.5,if s=="res" then plaster else stone,if s=="res" then Enum.Material.Plaster else Enum.Material.Limestone)
		local _=core
		local iw,id=(x2-x1)*.2,(z2-z1)*.2
		local wa=glassy(bx(md,"Windows",x1+1.5+iw,x2-1.5-iw,ph+3,top-4,z1+1.1,z2-1.1,Color3.fromRGB(70,86,98),nil,true),.1)
		local wb=glassy(bx(md,"Windows",x1+1.1,x2-1.1,ph+3,top-4,z1+1.5+id,z2-1.5-id,Color3.fromRGB(70,86,98),nil,true),.1)
		if l.glow then glowTag(wa,WINDOW_GLOW);glowTag(wb,WINDOW_GLOW) end
		if s=="res" then
			-- balcony slabs on every floor (14 studs), at most 9
			local nf=math.clamp(math.floor((top-ph-6)/14),2,9)
			for f=1,nf do local y=ph+(top-ph-4)*f/(nf+1);bx(md,"Balcony",x1+.6,x2-.6,y-.4,y+.4,z1+.6,z2-.6,PM.ivory,Enum.Material.Concrete,true) end
		else
			-- stone floor bands across the window panels (16 studs), at most 8, and a cornice
			local nf=math.clamp(math.floor((top-ph-7)/16),2,8)
			for f=1,nf do local y=ph+3+(top-ph-7)*f/(nf+1);bx(md,"FloorBand",x1+.9,x2-.9,y-.6,y+.6,z1+.9,z2-.9,stone:Lerp(PM.ivory,.3),Enum.Material.Limestone,true) end
			bx(md,"Cornice",x1+.8,x2-.8,top-2,top,z1+.8,z2-.8,C.stoneDeep,Enum.Material.Limestone,true)
		end
		crown(md,l,x1+1.5,x2-1.5,z1+1.5,z2-1.5,top,accent)
	elseif s=="slab" then
		local alongX=(x2-x1)>=(z2-z1)
		local sx1,sx2,sz1,sz2=x1+2,x2-2,z1+2,z2-2
		if alongX then local c=(z1+z2)/2;sz1,sz2=c-(z2-z1)*.28,c+(z2-z1)*.28 else local c=(x1+x2)/2;sx1,sx2=c-(x2-x1)*.28,c+(x2-x1)*.28 end
		local core=bx(md,"Core",sx1,sx2,ph,top,sz1,sz2,tint,Enum.Material.Glass)
		if l.glow then core.Transparency=.35;glowTag(bx(md,"WindowGlow",sx1+1.5,sx2-1.5,ph+1,top-1,sz1+1.5,sz2-1.5,Color3.fromRGB(58,64,70),Enum.Material.SmoothPlastic,true),WINDOW_GLOW) end
		local nb=math.clamp(math.floor((top-ph)/48),1,5)
		for k=1,nb do local y=ph+(top-ph)*k/(nb+1);bx(md,"Spandrel",sx1-.3,sx2+.3,y-.7,y+.7,sz1-.3,sz2+.3,C.metalSoft,Enum.Material.Metal,true) end
		if alongX then
			bx(md,"SlabWall",sx1-2,sx1+2,ph,top+6,sz1-1,sz2+1,stone,Enum.Material.Limestone)
			bx(md,"SlabWall",sx2-2,sx2+2,ph,top+6,sz1-1,sz2+1,stone,Enum.Material.Limestone)
		else
			bx(md,"SlabWall",sx1-1,sx2+1,ph,top+6,sz1-2,sz1+2,stone,Enum.Material.Limestone)
			bx(md,"SlabWall",sx1-1,sx2+1,ph,top+6,sz2-2,sz2+2,stone,Enum.Material.Limestone)
		end
		crown(md,l,sx1,sx2,sz1,sz2,top,accent)
	elseif s=="stepped" then
		local y1,y2=ph+(top-ph)*.55,ph+(top-ph)*.8
		bx(md,"Core",x1+1.5,x2-1.5,ph,y1,z1+1.5,z2-1.5,stone,Enum.Material.Limestone)
		local iw,id=(x2-x1)*.22,(z2-z1)*.22
		local wa=glassy(bx(md,"Windows",x1+1.5+iw,x2-1.5-iw,ph+3,y1-3,z1+1.1,z2-1.1,Color3.fromRGB(70,86,98),nil,true),.1)
		local wb=glassy(bx(md,"Windows",x1+1.1,x2-1.1,ph+3,y1-3,z1+1.5+id,z2-1.5-id,Color3.fromRGB(70,86,98),nil,true),.1)
		if l.glow then glowTag(wa,WINDOW_GLOW);glowTag(wb,WINDOW_GLOW) end
		local nf=math.clamp(math.floor((y1-ph-6)/16),2,6)
		for f=1,nf do local y=ph+3+(y1-ph-6)*f/(nf+1);bx(md,"FloorBand",x1+.9,x2-.9,y-.6,y+.6,z1+.9,z2-.9,stone:Lerp(PM.ivory,.3),Enum.Material.Limestone,true) end
		bx(md,"Setback",x1+7,x2-7,y1,y2,z1+7,z2-7,tint,Enum.Material.Glass)
		bx(md,"Setback",x1+13,x2-13,y2,top,z1+13,z2-13,stone,Enum.Material.Limestone)
		bx(md,"SetbackBand",x1+6.6,x2-6.6,y2-1.2,y2,z1+6.6,z2-6.6,accent,Enum.Material.Metal,true)
		crown(md,l,x1+13,x2-13,z1+13,z2-13,top,accent)
	elseif s=="drum" then
		local dia=math.min(x2-x1,z2-z1)-4
		local core=cyl(md,"Core",l.x,l.z,ph,top,dia,tint,Enum.Material.Glass)
		local _=core
		for _,f in {.25,.5,.75} do local y=ph+(top-ph)*f;cyl(md,"DrumRing",l.x,l.z,y-.8,y+.8,dia+1.6,stone,Enum.Material.Limestone,true) end
		cyl(md,"DrumCap",l.x,l.z,top,top+1.6,dia+1,C.stoneDeep,Enum.Material.Concrete)
		cyl(md,"Spire",l.x,l.z,top+1.6,top+50,1.6,C.metal,Enum.Material.Metal,true)
		bx(md,"Beacon",l.x-.8,l.x+.8,top+50,top+51.6,l.z-.8,l.z+.8,Color3.fromRGB(230,70,60),Enum.Material.Neon,true)
	elseif s=="twist" then
		local n=7;local size=math.min(x2-x1,z2-z1)-6
		for i=0,n-1 do
			local y1=ph+(top-ph)*i/n;local y2=ph+(top-ph)*(i+1)/n
			local p=mk(md,"TwistFloor",Vector3.new(size,y2-y1-.6,size),CFrame.new(l.x,(y1+y2)/2,l.z)*CFrame.Angles(0,math.rad(i*9),0),tint:Lerp(Color3.new(1,1,1),(i%2)*.08),Enum.Material.Glass)
			if i==n-1 then local _=p end
			mk(md,"TwistSlab",Vector3.new(size+1.2,.6,size+1.2),CFrame.new(l.x,y2-.3,l.z)*CFrame.Angles(0,math.rad(i*9),0),PM.ivory,Enum.Material.Concrete,true)
		end
		bx(md,"CrownBand",l.x-size*.3,l.x+size*.3,top,top+8,l.z-size*.3,l.z+size*.3,PM.gold,Enum.Material.Neon,true)
	else -- low airport buildings: hangar-like hall with a glass band
		bx(md,"Core",x1,x2,G+.1,top,z1,z2,if l.tone%2==0 then PM.ivory else C.metalSoft:Lerp(PM.ivory,.5),Enum.Material.Concrete)
		local band=glassy(bx(md,"GlassBand",x1-.3,x2+.3,G+4,top-4,z1-.3,z2+.3,PM.tealGlass,nil,true),.15)
		glowTag(band,WINDOW_GLOW)
		bx(md,"RoofUnit",x1+(x2-x1)*.3,x2-(x2-x1)*.3,top,top+4,z1+(z2-z1)*.3,z2-(z2-z1)*.3,C.metalSoft,Enum.Material.Metal,true)
	end
end
local function blocks(m: Model)
	local f=folder(m,"CityBlocks")
	for _,l in Plan.LOTS do backgroundTower(f,l) end
end

------------------------------------------------------------------------------------------------ landmark
-- Meridian Spire: four setback tiers of teal glass between bronze corner piers and fins, gold setback rings,
-- a glowing crown lantern and a needle mast. Persistent (see header).
local function spire(m: Model)
	local L=Plan.LANDMARK
	local sm=folder(m,"MeridianSpire",Enum.ModelStreamingMode.Persistent)
	sm:SetAttribute("Landmark","spire")
	local x,z=L.x,L.z;local hs=L.size/2
	bx(sm,"SpirePlinth",x-hs-6,x+hs+6,G+.1,G+1.6,z-hs-6,z+hs+6,PM.granite,Enum.Material.Granite)
	glassy(bx(sm,"SpireLobby",x-hs,x+hs,G+1.6,G+22,z-hs,z+hs,PM.tealGlass),.3)
	glowTag(bx(sm,"SpireLobbyGlow",x-hs+2,x+hs-2,G+20,G+21.4,z-hs+2,z+hs-2,PM.glow,Enum.Material.SmoothPlastic,true),PM.glow)
	bx(sm,"SpireCanopy",x-16,x+16,G+15,G+16,z+hs,z+hs+10,PM.ivory,Enum.Material.Metal,true)
	local cs=bx(sm,"SpireCanopySign",x-16,x+16,G+16,G+18.4,z+hs+9.6,z+hs+10,PM.navy,Enum.Material.Metal,true)
	label(cs,"MERIDIAN SPIRE",Enum.NormalId.Back,PM.gold,true)
	cyl(sm,"RevolvingDoor",x,z+hs,G+1.6,G+10,7,PM.bronze,Enum.Material.Glass,true).Transparency=.4
	local light1=bx(sm,"LobbyLight",x-6,x+6,G+21,G+21.6,z+hs-12,z+hs-4,PM.glow,Enum.Material.Neon,true)
	light(light1,34,.8,C.lightWarm)
	local tiers={{G+22,G+190,hs,3},{G+192,G+312,hs-4,3},{G+314,G+402,hs-9,2},{G+404,G+450,hs-14,0}}
	for i,t in tiers do
		local y1,y2,h,fins=t[1],t[2],t[3],t[4]
		local core=glassy(bx(sm,"SpireTier",x-h,x+h,y1,y2,z-h,z+h,PM.tealGlass),if i<4 then .3 else .15)
		local _=core
		if i<4 then glowTag(bx(sm,"SpireGlow",x-h+2,x+h-2,y1+2,y2-2,z-h+2,z+h-2,Color3.fromRGB(40,52,58),Enum.Material.SmoothPlastic,true),Color3.fromRGB(96,148,160)) end
		for _,c in {{-1,-1},{1,-1},{1,1},{-1,1}} do
			bx(sm,"SpirePier",x+c[1]*h-2.2,x+c[1]*h+2.2,y1,y2+(if i==4 then 6 else 0),z+c[2]*h-2.2,z+c[2]*h+2.2,PM.bronze,Enum.Material.Metal)
		end
		if fins>0 then
			for k=1,fins do
				local o=-h+2*h*k/(fins+1)
				bx(sm,"SpireFin",x+o-.5,x+o+.5,y1,y2,z-h-1,z+h+1,PM.bronze,Enum.Material.Metal,true)
				bx(sm,"SpireFin",x-h-1,x+h+1,y1,y2,z+o-.5,z+o+.5,PM.bronze,Enum.Material.Metal,true)
			end
		end
		if i<4 then
			bx(sm,"SetbackTerrace",x-h-1,x+h+1,y2,y2+2,z-h-1,z+h+1,PM.ivory,Enum.Material.Concrete)
			bx(sm,"SetbackRing",x-h-1.3,x+h+1.3,y2-1.2,y2,z-h-1.3,z+h+1.3,PM.gold,Enum.Material.Neon,true)
		end
	end
	-- crown: a stepped glass lantern (glows at night) between four gold blades that lean in towards the mast,
	-- light lines on the corner piers of the upper tiers (night), mast with rings and beacon
	local c1=G+450
	local top=c1
	for i,sz in {12,9,6,3.5} do
		local h=if i==1 then 12 elseif i==2 then 10 elseif i==3 then 8 else 6
		local step=glassy(bx(sm,"CrownLantern",x-sz,x+sz,top,top+h,z-sz,z+sz,Color3.fromRGB(196,226,236)),.25)
		glowTag(step,Color3.fromRGB(190,240,255))
		bx(sm,"CrownRing",x-sz-.4,x+sz+.4,top+h-.6,top+h,z-sz-.4,z+sz+.4,PM.gold,Enum.Material.Neon,true)
		top+=h
	end
	local crownLight=bx(sm,"CrownLight",x-2,x+2,c1+8,c1+9,z-2,z+2,PM.glow,Enum.Material.Neon,true)
	light(crownLight,60,1,Color3.fromRGB(200,240,255))
	for _,c in {{-1,-1},{1,-1},{1,1},{-1,1}} do
		local a=Vector3.new(x+c[1]*14.5,c1-30,z+c[2]*14.5)
		local b=Vector3.new(x+c[1]*2.5,top+12,z+c[2]*2.5)
		local blade=mk(sm,"CrownBlade",Vector3.new(1.8,.9,(b-a).Magnitude),CFrame.lookAt((a+b)/2,b),PM.gold,Enum.Material.Metal,true)
		glowTag(blade,PM.gold)
	end
	for i=2,4 do
		local t=tiers[i]
		local h=t[3]
		for _,c in {{-1,-1},{1,-1},{1,1},{-1,1}} do
			local px,pz=x+c[1]*(h+2.25),z+c[2]*(h+2.25)
			local strip=bx(sm,"PierLight",px-.25,px+.25,t[1],t[2],pz-.25,pz+.25,PM.bronze,Enum.Material.Metal,true)
			glowTag(strip,Color3.fromRGB(255,214,150))
		end
	end
	local mast=top
	cyl(sm,"Mast",x,z,mast,mast+L.mast,2.2,C.metal,Enum.Material.Metal,true)
	for _,f in {.3,.62} do cyl(sm,"MastRing",x,z,mast+L.mast*f,mast+L.mast*f+1,4.2,PM.gold,Enum.Material.Metal,true) end
	bx(sm,"MastBeacon",x-1,x+1,mast+L.mast,mast+L.mast+2,z-1,z+1,Color3.fromRGB(240,60,50),Enum.Material.Neon,true)
end

------------------------------------------------------------------------------------------------ harbour quarter
local function harbour(m: Model)
	local h=folder(m,"HarbourQuarter")
	local pr=A.promenade
	-- spire plaza and harbour walk
	bx(h,"SpirePlaza",-100,100,G+.1,PLAZA,8504,pr.z1,PM.paver,Enum.Material.Granite)
	for _,s in {{R.x1,-100},{100,R.x2}} do bx(h,"HarbourWalk",s[1],s[2],G+.1,PLAZA,8506,pr.z1,PM.paver:Lerp(PM.walkway,.5),Enum.Material.Pavement) end
	for _,x in Plan.HARBOUR_WALKWAYS do bx(h,"Walkway",x-3,x+3,G+.1,G+.13,8360,8506,PM.walkway,Enum.Material.Pavement,true) end
	-- granite bands across the spire plaza (framing the door axis) and along the harbour walk
	for _,x in {-36,36} do bx(h,"PlazaBand",x-1,x+1,PLAZA,PLAZA+.02,8504,pr.z1,BAND,Enum.Material.Granite,true) end
	bx(h,"PlazaBand",-100,100,PLAZA,PLAZA+.02,8586,8588,BAND,Enum.Material.Granite,true)
	for _,s in Plan.BENCHES do if s.z>8500 then bench(h,s) end end -- harbour walk, spire plaza, promenade, quay
	for _,x in {-70,70} do
		cyl(h,"SpirePlanter",x,8530,PLAZA,PLAZA+1.8,10,PM.granite,Enum.Material.Granite)
		tree(h,x,8530,900+x,PLAZA+1.8)
	end
	K.kiosk(h,Plan.HARBOUR_KIOSK.X,Plan.HARBOUR_KIOSK.Z,PLAZA,-1,"intl_hotel","Meridian Grand Hotel")
	-- steps up to the spire plinth's door (the walkers' door spur climbs them)
	for i,dz in {{8582,8584.5},{8584.5,8587}} do bx(h,"SpireStep",-10,10,PLAZA,PLAZA+(Plan.PLINTH_TOP-PLAZA)*(3-i)/3,dz[1],dz[2],PM.graniteLight,Enum.Material.Granite) end
	-- ground-jet splash fountains on the spire plaza (basin flush with the paving, a ring of jets)
	for _,sp in Plan.SPLASH do
		cyl(h,"SplashBasin",sp.X,sp.Z,PLAZA,PLAZA+.35,18,PM.graniteLight,Enum.Material.Granite)
		glassy(cyl(h,"SplashWater",sp.X,sp.Z,PLAZA+.35,PLAZA+.4,15.6,PM.water,nil,true),.2)
		local jet=cyl(h,"SplashJet",sp.X,sp.Z,PLAZA+.4,PLAZA+7,.9,Color3.fromRGB(196,232,240),Enum.Material.Neon,true);jet.Transparency=.35
		for i=0,5 do
			local a=i/6*math.pi*2
			local sj=cyl(h,"SplashJet",sp.X+math.cos(a)*5,sp.Z+math.sin(a)*5,PLAZA+.4,PLAZA+3.6+(i%2)*1.2,.45,Color3.fromRGB(196,232,240),Enum.Material.Neon,true);sj.Transparency=.45
		end
	end
	-- planting beds between the corridors (lawn, flower edges, trees; bench pairs on their sea side)
	for i,bd in Plan.BEDS do
		bx(h,"BedKerb",bd.x1,bd.x2,PLAZA,PLAZA+.6,bd.z1,bd.z2,PM.granite,Enum.Material.Granite)
		bx(h,"BedLawn",bd.x1+.6,bd.x2-.6,PLAZA+.6,PLAZA+.66,bd.z1+.6,bd.z2-.6,PM.lawn,Enum.Material.Grass,true)
		for _,fz in {bd.z1+.6,bd.z2-2.2} do
			bx(h,"BedFlowers",bd.x1+1.2,bd.x2-1.2,PLAZA+.6,PLAZA+1.1,fz,fz+1.6,FLOWERS[(i+math.floor(fz))%#FLOWERS+1],Enum.Material.Grass,true)
		end
	end
	for _,p in Plan.BED_TREES do tree(h,p.x,p.z,p.k,PLAZA+.6) end
	-- cafés with umbrella terraces
	for i,cx in {-440,-200,200,380} do
		local cz=8530
		glassy(bx(h,"CafeHall",cx-14,cx+14,PLAZA,PLAZA+10,cz-8,cz+8,Color3.fromRGB(206,184,150)),.25)
		bx(h,"CafeRoof",cx-16,cx+16,PLAZA+10,PLAZA+11,cz-10,cz+10,PM.ivory,Enum.Material.Metal)
		local aw=bx(h,"CafeAwning",cx-14,cx+14,PLAZA+7.4,PLAZA+8,cz+8,cz+12,AWNINGS[i+1],Enum.Material.Fabric,true)
		label(aw,({"HARBOUR GRILL","CAFÉ MARINA","OYSTER BAR","SUNSET LOUNGE"})[i],Enum.NormalId.Back,PM.ivory,true)
		glowTag(bx(h,"CafeGlow",cx-12,cx+12,PLAZA+9,PLAZA+9.6,cz-6,cz+6,Color3.fromRGB(90,80,70),Enum.Material.SmoothPlastic,true),SHOP_GLOW)
		for _,dx in {-9,0,9} do
			local tx,tz=cx+dx,cz+19
			cyl(h,"TerraceTable",tx,tz,PLAZA,PLAZA+2.6,3,PM.ivory,Enum.Material.Metal,true)
			cyl(h,"Umbrella",tx,tz,PLAZA+2.6,PLAZA+8,.3,C.metal,Enum.Material.Metal,true)
			cyl(h,"UmbrellaTop",tx,tz,PLAZA+7.6,PLAZA+8.2,7.5,AWNINGS[((i+dx)%#AWNINGS)+1]:Lerp(PM.ivory,.35),Enum.Material.Fabric,true)
		end
	end
	-- promenade, boardwalk, quay, railing
	bx(h,"Promenade",pr.x1,pr.x2,G+.1,PLAZA,pr.z1,pr.z2,PM.paver,Enum.Material.Pavement)
	bx(h,"Boardwalk",pr.x1,pr.x2,PLAZA,PLAZA+.03,pr.z2-28,pr.z2,PM.deck,Enum.Material.WoodPlanks,true)
	bx(h,"Quay",pr.x1,pr.x2,-2,G+.6,pr.z2,pr.z2+4,C.stoneDeep,Enum.Material.Limestone)
	bx(h,"QuayRail",pr.x1,pr.x2,G+3.4,G+3.8,pr.z2+1.6,pr.z2+2.2,C.metal,Enum.Material.Metal)
	glassy(bx(h,"QuayGlass",pr.x1,pr.x2,G+.6,G+3.4,pr.z2+1.8,pr.z2+2,C.glass,nil,true),.6)
	-- granite bands across the promenade every ~23 studs (the boardwalk stays timber) and one along it
	for x=R.x1+12,R.x2-12,23 do bx(h,"PromenadeBand",x-.7,x+.7,PLAZA,PLAZA+.02,pr.z1,pr.z2-28,BAND,Enum.Material.Granite,true) end
	bx(h,"PromenadeBand",pr.x1,pr.x2,PLAZA+.005,PLAZA+.025,8648,8650,BAND,Enum.Material.Granite,true)
	-- tree row in granite planters on a lawn strip (interrupted where the paths cross it)
	local cuts: {{number}}={}
	for _,x in {R.x1+10,-560,-300,-110,0,110,300,580,R.x2-10} do table.insert(cuts,{x-4,x+4}) end
	for _,sp in spans(R.x1+2,R.x2-2,cuts) do bx(h,"PromenadeLawn",sp[1],sp[2],PLAZA,PLAZA+.04,8609,8619,PM.lawn,Enum.Material.Grass,true) end
	for _,p in Plan.PROM_TREES do
		bx(h,"TreePlanter",p.x-2.6,p.x+2.6,PLAZA,PLAZA+.8,p.z-2.6,p.z+2.6,PM.granite,Enum.Material.Granite)
		tree(h,p.x,p.z,p.k,PLAZA+.8)
	end
	for i,x in Plan.HARBOUR_LAMPS do
		cyl(h,"HarbourLamp",x,8662,PLAZA,PLAZA+11,.5,PM.navy,Enum.Material.Metal)
		local hd=ball(h,"HarbourLampGlobe",x,PLAZA+11.6,8662,1.8,PM.glow,Enum.Material.Neon,true)
		if i%3==2 then light(hd,26,.7) end
	end
	for _,p in Plan.LAMP_TREES do
		cyl(h,"TreePot",p.x,p.z,PLAZA,PLAZA+1.2,4.4,PM.graniteLight,Enum.Material.Granite)
		tree(h,p.x,p.z,p.k,PLAZA+1.2)
	end
	-- mooring bollards along the quay edge
	for _,x in Plan.BOLLARDS do cyl(h,"Bollard",x,8699.3,PLAZA,PLAZA+1.5,.7,Color3.fromRGB(40,42,46),Enum.Material.Metal) end
	-- food carts (generic names) and the "Meridian Sail" sculpture at the promenade head
	for i,p in Plan.CARTS do
		local cx,cz=p.X,p.Z
		bx(h,"CartBody",cx-3.4,cx+3.4,PLAZA+.9,PLAZA+3.6,cz-1.5,cz+1.5,AWNINGS[(i%#AWNINGS)+1]:Lerp(PM.ivory,.25),Enum.Material.SmoothPlastic)
		bx(h,"CartCounter",cx-3.6,cx+3.6,PLAZA+3.6,PLAZA+3.9,cz-1.7,cz+1.8,PM.ivory,Enum.Material.Metal,true)
		for _,dx in {-2.2,2.2} do
			local wheel=mk(h,"CartWheel",Vector3.new(.4,1.8,1.8),CFrame.new(cx+dx,PLAZA+.9,cz+1.6)*CFrame.Angles(0,math.pi/2,0),Color3.fromRGB(30,30,32),Enum.Material.Rubber,true)
			;(wheel :: Part).Shape=Enum.PartType.Cylinder
		end
		cyl(h,"CartPole",cx,cz,PLAZA+3.9,PLAZA+7.6,.25,C.metal,Enum.Material.Metal,true)
		local can=bx(h,"CartCanopy",cx-3.6,cx+3.6,PLAZA+7.6,PLAZA+8,cz-1.8,cz+1.8,AWNINGS[((i+2)%#AWNINGS)+1],Enum.Material.Fabric,true)
		local _=can
		local sg=bx(h,"CartSign",cx-3,cx+3,PLAZA+4.4,PLAZA+5.6,cz-1.75,cz-1.6,PM.navy,Enum.Material.Metal,true)
		label(sg,CART_NAMES[(i-1)%#CART_NAMES+1],Enum.NormalId.Front,PM.gold,true)
	end
	local sc=Plan.SCULPTURE
	cyl(h,"SculpturePlinth",sc.X,sc.Z,PLAZA,PLAZA+1.2,8,PM.granite,Enum.Material.Granite)
	cyl(h,"SculptureMast",sc.X,sc.Z,PLAZA+1.2,PLAZA+19,.8,PM.bronze,Enum.Material.Metal)
	for i,d in {{0,11,PM.ivory},{math.pi,8,PM.bronze}} :: {{any}} do
		-- two leaning sails (wedges) either side of the mast
		local yaw: number=d[1];local hgt: number=d[2]
		local w=mk(h,"SculptureSail",Vector3.new(.5,hgt+5,6),CFrame.new(sc.X,PLAZA+1.2+(hgt+5)/2,sc.Z)*CFrame.Angles(0,yaw+math.rad(25),0)*CFrame.new(0,0,3.3)*CFrame.Angles(0,math.pi,0),d[3],Enum.Material.Metal,true,"WedgePart")
		local _=i;local _w=w
	end
	ball(h,"SculptureOrb",sc.X,PLAZA+19.6,sc.Z,1.6,PM.gold,Enum.Material.Neon,true)
	-- sea (beyond the walk: decoration), marina, yachts, harbour cruiser, lighthouse
	local sea=Plan.SEA
	for _,s in {{sea.x1,0},{0,sea.x2}} do glassy(bx(h,"Sea",s[1],s[2],G-3.2,G-3,sea.z1,sea.z2,C.water,nil,true),.15) end
	local mar=folder(h,"Marina")
	bx(mar,"Pontoon",-620,280,G-1.6,G-.8,8742,8748,PM.deck,Enum.Material.WoodPlanks,true)
	local yk=0
	for x=-600,260,40 do
		bx(mar,"Finger",x-1.5,x+1.5,G-1.6,G-.8,8710,8742,PM.deck,Enum.Material.WoodPlanks,true)
		yk+=1
		if Plan.hash("yacht"..yk)%4~=0 then
			local yx=x+20;local len=18+(Plan.hash("y"..yk)%3)*5
			local hullC=if yk%3==0 then PM.navy else PM.ivory
			local cf=CFrame.lookAt(Vector3.new(yx,G-2.4,8724),Vector3.new(yx,G-2.4,8700))
			mk(mar,"Hull",Vector3.new(6,2.6,len*.7),cf*CFrame.new(0,0,len*.15),hullC,Enum.Material.SmoothPlastic,true)
			mk(mar,"Bow",Vector3.new(6,2.6,len*.3),cf*CFrame.new(0,0,-len*.35)*CFrame.Angles(0,math.pi,0),hullC,Enum.Material.SmoothPlastic,true,"WedgePart")
			mk(mar,"Deck",Vector3.new(4.4,2,len*.4),cf*CFrame.new(0,2.3,len*.1),PM.ivory,Enum.Material.SmoothPlastic,true)
			glassy(mk(mar,"DeckGlass",Vector3.new(4.6,.9,len*.3),cf*CFrame.new(0,2.6,len*.04),Color3.fromRGB(40,50,60),nil,true),.1)
			if yk%2==0 then cyl(mar,"Mast",yx,8724,G-1,G+22,.4,PM.ivory,Enum.Material.Metal,true) end
		end
	end
	local sh=CFrame.lookAt(Vector3.new(470,G-2,8760),Vector3.new(560,G-2,8760))
	mk(mar,"CruiserHull",Vector3.new(14,6,70),sh,PM.ivory,Enum.Material.SmoothPlastic,true)
	mk(mar,"CruiserBow",Vector3.new(14,6,14),sh*CFrame.new(0,0,-42)*CFrame.Angles(0,math.pi,0),PM.ivory,Enum.Material.SmoothPlastic,true,"WedgePart")
	mk(mar,"CruiserDeck",Vector3.new(11,5,44),sh*CFrame.new(0,5.5,4),PM.navy,Enum.Material.SmoothPlastic,true)
	glassy(mk(mar,"CruiserWindows",Vector3.new(11.4,1.8,40),sh*CFrame.new(0,6,4),Color3.fromRGB(40,50,60),nil,true),.1)
	cyl(mar,"CruiserFunnel",470+16,8760,G+6,G+14,4,PM.gold,Enum.Material.Metal,true)
	bx(mar,"FerryPier",420,520,G-1.6,G-.6,8704,8750,PM.deck,Enum.Material.WoodPlanks,true)
	local lh=folder(h,"Lighthouse")
	bx(lh,"Breakwater",-700,-560,G-4,G-1,8840,8862,C.stoneDeep,Enum.Material.Rock,true)
	cyl(lh,"LighthouseTower",-640,8851,G-1,G+34,9,PM.ivory,Enum.Material.Plaster,true)
	for _,y in {G+6,G+20} do cyl(lh,"LighthouseBand",-640,8851,y,y+5,9.3,PM.red,Enum.Material.Plaster,true) end
	cyl(lh,"LighthouseLantern",-640,8851,G+34,G+39,6,Color3.fromRGB(255,236,180),Enum.Material.Neon,true)
	cyl(lh,"LighthouseCap",-640,8851,G+39,G+41,7.5,PM.red,Enum.Material.Metal,true)
	-- Harbour Wheel (the client turns rim, spokes and cabins; the server keeps it static)
	local W=Plan.WHEEL
	local wm=folder(h,"HarbourWheel",Enum.ModelStreamingMode.Atomic) -- streams as one piece (the client turns it)
	CollectionService:AddTag(wm,"MetroWheel")
	wm:SetAttribute("Hub",Vector3.new(W.x,W.hub,W.z));wm:SetAttribute("Radius",W.radius)
	local hub=Vector3.new(W.x,W.hub,W.z)
	for _,sz in {-1,1} do
		for _,sx in {-1,1} do
			local foot=Vector3.new(W.x+sx*24,G+.1,W.z+sz*12)
			local top=hub+Vector3.new(0,0,sz*4)
			local mid=(foot+top)/2
			mk(wm,"WheelLeg",Vector3.new(1.6,(top-foot).Magnitude,1.6),CFrame.lookAt(mid,top)*CFrame.Angles(-math.pi/2,0,0),PM.ivory,Enum.Material.Metal)
		end
	end
	local axle=mk(wm,"WheelAxle",Vector3.new(10,3,3),CFrame.new(hub)*CFrame.Angles(0,math.pi/2,0),C.metalSoft,Enum.Material.Metal,true);(axle :: Part).Shape=Enum.PartType.Cylinder
	local hubP=mk(wm,"WheelHub",Vector3.new(4,8,8),CFrame.new(hub)*CFrame.Angles(0,math.pi/2,0),PM.gold,Enum.Material.Metal,true);(hubP :: Part).Shape=Enum.PartType.Cylinder
	local segs=24
	for i=0,segs-1 do
		local a=(i+.5)/segs*math.pi*2
		local p=hub+Vector3.new(math.cos(a)*W.radius,math.sin(a)*W.radius,0)
		local rim=mk(wm,"WheelRim",Vector3.new(2*math.pi*W.radius/segs+.4,1,1.4),CFrame.new(p)*CFrame.Angles(0,0,a+math.pi/2),if i%2==0 then PM.ivory else Color3.fromRGB(150,210,255),if i%2==0 then Enum.Material.Metal else Enum.Material.Neon,true)
		rim:SetAttribute("WheelAngle",a);rim:SetAttribute("WheelR",W.radius)
	end
	for i=0,11 do
		local a=i/12*math.pi*2
		local p=hub+Vector3.new(math.cos(a)*W.radius/2,math.sin(a)*W.radius/2,0)
		local sp=mk(wm,"WheelSpoke",Vector3.new(W.radius,.4,.4),CFrame.new(p)*CFrame.Angles(0,0,a),PM.ivory,Enum.Material.Metal,true)
		sp:SetAttribute("WheelAngle",a);sp:SetAttribute("WheelR",W.radius/2)
	end
	for i=0,15 do
		local a=i/16*math.pi*2
		local p=hub+Vector3.new(math.cos(a)*(W.radius+1),math.sin(a)*(W.radius+1)-3,0)
		local cab=mk(wm,"WheelCabin",Vector3.new(4.6,4.6,4.6),CFrame.new(p),AWNINGS[(i%#AWNINGS)+1]:Lerp(PM.ivory,.3),Enum.Material.Glass,true)
		cab:SetAttribute("WheelAngle",a);cab:SetAttribute("WheelR",W.radius+1);cab:SetAttribute("Hang",3)
	end
	bx(wm,"WheelStation",W.x-14,W.x+14,PLAZA,PLAZA+5,W.z-6,W.z+6,PM.navy,Enum.Material.SmoothPlastic)
	local ws=bx(wm,"WheelSign",W.x-12,W.x+12,PLAZA+5,PLAZA+7.6,W.z+5.8,W.z+6.2,PM.navy,Enum.Material.Metal,true)
	label(ws,"HARBOUR WHEEL",Enum.NormalId.Back,PM.gold,true)
end
------------------------------------------------------------------------------------------------ park
local function park(m: Model)
	local pk=folder(m,"MeridianPark")
	local x1,x2,z1,z2=446,694,7810,8044
	bx(pk,"ParkLawn",x1,x2,G+.1,PARK,z1,z2,PM.lawn,Enum.Material.Grass)
	for _,s in {{470,680,7832,7836},{470,680,8020,8024},{468,472,7832,8024},{678,682,7832,8024},{440,470,7928,7932}} do
		bx(pk,"ParkPath",s[1],s[2],PARK,PARK+.03,s[3],s[4],Color3.fromRGB(196,180,150),Enum.Material.Pebble,true)
	end
	for _,s in {{573,577,7804,7836},{573,577,8020,8051}} do bx(pk,"ParkPath",s[1],s[2],PARK,PARK+.03,s[3],s[4],Color3.fromRGB(196,180,150),Enum.Material.Pebble,true) end
	-- bench spurs round to the bench fronts (MetroPlan park paths)
	for _,s in {{472,521,7913.5,7916.5},{519.5,522.5,7915,7930},{629,678,7943.5,7946.5},{627.5,630.5,7930,7945},
		{558.5,561.5,7836,7876},{560,575,7874.5,7877.5},{588.5,591.5,7984,8020},{575,590,7982.5,7985.5}} do
		bx(pk,"ParkPath",s[1],s[2],PARK,PARK+.03,s[3],s[4],Color3.fromRGB(196,180,150),Enum.Material.Pebble,true)
	end
	cyl(pk,"PondRim",575,7930,PARK,PARK+.6,78,PM.ivory,Enum.Material.Limestone,true)
	glassy(cyl(pk,"Pond",575,7930,PARK+.6,PARK+.65,75,PM.water,nil,true),.15)
	local jet=cyl(pk,"PondJet",575,7930,PARK+.6,PARK+12,1,Color3.fromRGB(196,232,240),Enum.Material.Neon,true);jet.Transparency=.4
	local k=1200
	for _,p in Plan.PARK_TREE_POS do k+=1;tree(pk,p[1],p[2],k,PARK) end
	for _,s in Plan.BENCHES do if s.x>440 and s.z<8050 then bench(pk,s) end end
	-- bandstand
	cyl(pk,"Bandstand",660,8020-46,PARK,PARK+1.4,16,PM.ivory,Enum.Material.Marble)
	for _,d in {{1,0},{-1,0},{0,1},{0,-1}} do cyl(pk,"BandstandPost",660+d[1]*6.5,7974+d[2]*6.5,PARK+1.4,PARK+10,.6,PM.ivory,Enum.Material.Metal) end
	cyl(pk,"BandstandRoof",660,7974,PARK+10,PARK+11.2,17,PM.teal,Enum.Material.Metal,true)
	for i,p in Plan.PARK_LAMPS do lamp(pk,p.X,p.Z,i==1,PARK) end
	cyl(pk,"ParkSignPost",452,7940,PARK,PARK+6,.5,C.metal,Enum.Material.Metal)
	local s=bx(pk,"ParkSign",446,458,PARK+3,PARK+6,7938.8,7939.2,PM.teal,Enum.Material.Metal,true)
	both(s,"MERIDIAN PARK","z",PM.ivory,true)
end
------------------------------------------------------------------------------------------------ greenery
-- Lawn verges with tree rows in the gaps between neighbouring towers of a block, and the airport district's tree
-- row in planters (MetroPlan.VERGES / VERGE_TREES / DISTRICT_TREES).
local function greenery(m: Model)
	local g=folder(m,"Greenery")
	for _,q in Plan.VERGES do bx(g,"Verge",q.x1,q.x2,G+.1,G+.16,q.z1,q.z2,PM.lawn,Enum.Material.Grass,true) end
	for _,p in Plan.VERGE_TREES do tree(g,p.x,p.z,p.k,G+.16) end
	for _,p in Plan.DISTRICT_TREES do
		bx(g,"TreePlanter",p.x-2.6,p.x+2.6,G+.1,G+.9,p.z-2.6,p.z+2.6,PM.granite,Enum.Material.Granite)
		tree(g,p.x,p.z,p.k,G+.9)
	end
end
------------------------------------------------------------------------------------------------ districts, billboards, walls
local ADS={"SKYLINE SUITES\nStay above the city","HARBOUR WHEEL\nOpen daily till midnight","MERIDIAN JAZZ NIGHTS\nThis weekend at the bay",
	"BAYSIDE FISH MARKET\nFresh every morning","MERIDIAN SPIRE\nThe tallest tower on the bay","CITY MARATHON\nSunday · Meridian Boulevard",
	"FRESH ROAST COFFEE\nOn every corner","PORT MERIDIAN AQUARIUM\nNew shark tunnel"}
local function signage(m: Model)
	local s=folder(m,"Signage")
	-- district gateway signs: a 14 x 5 name panel (two lines of ~2-stud letters, both faces, glowing) under a kicker
	-- strip, on two bronze posts (MetroPlan.DISTRICT_SIGNS; the walkers step round them)
	local W=Plan.SIGN_W;local b=G+.1
	for _,d in Plan.DISTRICT_SIGNS do
		local x,z=d.x,d.z
		for _,sx in {-1,1} do cyl(s,"SignPost",x+sx*(W/2-.7),z,b,b+13.6,.8,PM.bronze,Enum.Material.Metal) end
		local panel=bx(s,"DistrictSign",x-W/2,x+W/2,b+6.4,b+11.4,z-.3,z+.3,PM.navy,Enum.Material.Metal,true)
		both(panel,d.name,"z",PM.ivory,true)
		bx(s,"DistrictSignBand",x-W/2-.05,x+W/2+.05,b+11.4,b+11.7,z-.35,z+.35,PM.gold,Enum.Material.Neon,true)
		local kick=bx(s,"DistrictKicker",x-W/2,x+W/2,b+11.7,b+13.2,z-.3,z+.3,Color3.fromRGB(22,32,56),Enum.Material.Metal,true)
		both(kick,d.kicker,"z",PM.gold,true)
		bx(s,"DistrictSignCap",x-W/2-.3,x+W/2+.3,b+13.2,b+13.6,z-.45,z+.45,PM.gold,Enum.Material.Metal,true)
	end
	-- billboards on the roofs of lower buildings near the main streets, facing the street
	local n=0
	for _,l in Plan.LOTS do
		if n<#ADS and l.h<=150 and l.style~="drum" and l.style~="twist" and (l.block=="xw" or l.block=="xs" or l.block=="ps" or l.block=="aw" or l.block=="ae" or l.block=="h2" or l.block=="h5") and Plan.hash(l.id.."ad")%2==0 then
			n+=1
			local top=G+l.h+1.2
			local w=math.min(30,l.w-8)
			local face=l.face
			local cx,cz=l.x,l.z
			local yaw=if face=="n" then 0 elseif face=="s" then math.pi elseif face=="w" then math.pi/2 else -math.pi/2
			local cf=CFrame.new(cx,top,cz)*CFrame.Angles(0,yaw,0)
			mk(s,"BillboardLeg",Vector3.new(.6,6,.6),cf*CFrame.new(-w*.35,3,0),C.metal,Enum.Material.Metal,true)
			mk(s,"BillboardLeg",Vector3.new(.6,6,.6),cf*CFrame.new(w*.35,3,0),C.metal,Enum.Material.Metal,true)
			local board=mk(s,"Billboard",Vector3.new(w,w*.42,.6),cf*CFrame.new(0,6+w*.21,0),PM.navy:Lerp(AWNINGS[(n%#AWNINGS)+1],.5),Enum.Material.SmoothPlastic,true)
			label(board,ADS[n],Enum.NormalId.Front,PM.ivory,true)
			mk(s,"BillboardLight",Vector3.new(w,.4,.6),cf*CFrame.new(0,6+w*.42+.3,-.6),PM.glow,Enum.Material.Neon,true)
		end
	end
end
local function walls(m: Model)
	local pr=A.promenade
	local inv=function(p: BasePart) p.Transparency=1;p.CastShadow=false end
	inv(bx(m,"BoundaryWall",R.x1-4,R.x1,G,G+80,R.z1,pr.z2+4,C.white))
	inv(bx(m,"BoundaryWall",R.x2,R.x2+4,G,G+80,R.z1,pr.z2+4,C.white))
	inv(bx(m,"BoundaryWall",R.x1-4,R.x2+4,G,G+80,R.z1-4,R.z1,C.white))
	inv(bx(m,"BoundaryWall",R.x1-4,R.x2+4,G,G+80,pr.z2+4,pr.z2+8,C.white))
end

------------------------------------------------------------------------------------------------ entry
function Metro.build(root: Instance,kit: any)
	K=kit
	local m=folder(root,"PortMeridian")
	m:SetAttribute("City","Port Meridian")
	ground(m)
	-- light budget order (40 per zone): terminal, lounge, helipads, buildings, spire, plaza, fountains, lamps
	local term=airport(m)
	lounge(term)
	vipAirport(m)
	towers(m)
	spire(m)
	plaza(m)
	boulevard(m)
	harbour(m)
	park(m)
	streets(m,Plan.portMeridian())
	blocks(m)
	greenery(m)
	signage(m)
	walls(m)
	return m
end
return Metro
