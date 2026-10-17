--!strict
-- Builds the shared world described by CityPlan ONCE per server (CityService.init): the ring-road
-- extensions and Central Avenue, Business City (streets, 14 client offices, City Hotel, convention centre,
-- City Plaza, park, background blocks), City Airport (AirportBuilder: terminal inside and out, forecourt, car
-- park, apron with three parked aircraft and jet bridges, taxiway, runway, tower, hangar, perimeter and
-- horizon), the harbour, and Port Meridian far to the south (MetroBuilder).
-- Budgets per zone (tests/world): downtown <= 3,000 parts, airport <= 7,000 (terminal interior <= 3,500),
-- Port Meridian <= 20,000; real PointLights <= 40 per zone (buildings first, then the airport, then street
-- lamps; further lamps keep a neon head only). Decorative parts never collide, touch or take spatial queries;
-- every walkable top is supported by the zone ground (no holes).
-- Streaming (Workspace streaming properties are NotScriptable; pack.py sets StreamingEnabled, MinRadius 128,
-- TargetRadius 512, ModelStreamingBehavior Improved, StreamOutBehavior Opportunistic, StreamingIntegrityMode
-- MinimumRadiusPause):
--   * every building interior is an Atomic model - it streams in and out as one piece, never half a room;
--   * the shells of the tall downtown towers, the City Hotel and the control tower are Persistent so the
--     skyline shows from the campus beyond the 512-stud radius (~7 models, ~300 parts on every client -
--     negligible next to one plot's 13-25k parts); everything else streams normally.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local City=require(ReplicatedStorage.Shared.Config.CityPlan)
local P=require(ReplicatedStorage.Shared.Config.ArchPalette)
local Metro=require(script.Parent.MetroBuilder)
local Airport=require(script.Parent.AirportBuilder)
local Builder={}
local G=City.GROUND
local LIGHT_BUDGET=40 -- real lights per zone
local lights: {[string]: number}={}
Builder.lights=lights
local C=P.color
local LAWN=Color3.fromRGB(104,134,94)
local BASE_STONE=Color3.fromRGB(186,188,169)
local WHITE=Color3.fromRGB(229,223,199)
local YELLOW=Color3.fromRGB(222,184,82)
local GLOW=Color3.fromRGB(238,220,184)

------------------------------------------------------------------------------------------------ helpers
local function mk(parent: Instance,name: string,size: Vector3,cf: CFrame,color: Color3,material: Enum.Material?,decor: boolean?): Part
	local p=Instance.new("Part");p.Name=name;p.Anchored=true;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
	p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
	if decor then p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false end
	p.Parent=parent;return p
end
-- world axis-aligned box from its extents
local function box(parent: Instance,name: string,x1: number,x2: number,y1: number,y2: number,z1: number,z2: number,color: Color3,material: Enum.Material?,decor: boolean?): Part
	return mk(parent,name,Vector3.new(x2-x1,y2-y1,z2-z1),CFrame.new((x1+x2)/2,(y1+y2)/2,(z1+z2)/2),color,material,decor)
end
-- box in a building frame (local extents)
local function lbox(f: CFrame,parent: Instance,name: string,x1: number,x2: number,y1: number,y2: number,z1: number,z2: number,color: Color3,material: Enum.Material?,decor: boolean?): Part
	return mk(parent,name,Vector3.new(x2-x1,y2-y1,z2-z1),f*CFrame.new((x1+x2)/2,(y1+y2)/2,(z1+z2)/2),color,material,decor)
end
local function glass(p: Part,t: number?): Part p.Material=Enum.Material.Glass;p.Transparency=t or .45;return p end
local function invisible(p: Part): Part p.Transparency=1;p.CastShadow=false;return p end
local function folder(parent: Instance,name: string,mode: Enum.ModelStreamingMode?): Model
	local m=Instance.new("Model");m.Name=name
	if mode then m.ModelStreamingMode=mode end
	m.Parent=parent;return m
end
-- A real PointLight while the zone has budget left; the part stays a neon head either way.
local function light(p: BasePart,range: number,brightness: number,color: Color3?): boolean
	local zone=City.zoneAt(p.Position) or "none"
	if zone=="district" or (lights[zone] or 0)>=LIGHT_BUDGET then return false end
	lights[zone]=(lights[zone] or 0)+1
	local l=Instance.new("PointLight");l.Range=range;l.Brightness=brightness;l.Color=color or GLOW;l.Shadows=false;l.Parent=p
	return true
end
local function sign(p: BasePart,text: string,face: Enum.NormalId?,ink: Color3?,size: Vector2?): TextLabel
	local g=Instance.new("SurfaceGui");g.Face=face or Enum.NormalId.Front;g.LightInfluence=.3
	-- uniform pixels per stud of the face (long signs were squashed); TextScaled caps at 100 px, so big signs
	-- get fewer pixels per stud and the text can fill them
	local f=face or Enum.NormalId.Front
	local w,h=p.Size.X,p.Size.Y
	if f==Enum.NormalId.Left or f==Enum.NormalId.Right then w=p.Size.Z elseif f==Enum.NormalId.Top or f==Enum.NormalId.Bottom then h=p.Size.Z end
	local lines=#string.split(text,"\n")
	local pps=math.max(4,math.min(40,1600/w,900/h,100/math.max(.1,h/lines)))
	g.CanvasSize=size or Vector2.new(w*pps,h*pps);g.Parent=p
	local t=Instance.new("TextLabel");t.BackgroundTransparency=1;t.Size=UDim2.fromScale(1,1);t.Text=text;t.TextScaled=true;t.TextWrapped=true
	t.Font=Enum.Font.BuilderSansBold;t.TextColor3=ink or Color3.fromRGB(240,238,228);t.Parent=g
	return t
end
local function prompt(p: BasePart,action: string,object: string,distance: number,hold: number): ProximityPrompt
	local q=Instance.new("ProximityPrompt");q.ActionText=action;q.ObjectText=object;q.MaxActivationDistance=distance;q.HoldDuration=hold
	q.RequiresLineOfSight=false;q:SetAttribute("Public",true);q.Parent=p
	return q
end
-- Info kiosk with a GPS prompt (TravelController draws the route to `to`).
-- face: -1 = screen towards -Z, +1 = towards +Z
local function kiosk(parent: Instance,x: number,z: number,top: number,face: number,to: string,label: string)
	local k=box(parent,"InfoKiosk",x-1.5,x+1.5,top,top+5,z-1,z+1,C.metal,Enum.Material.Metal)
	local sz=z+face*1.1
	local screen=box(parent,"InfoKioskScreen",x-1.3,x+1.3,top+2.6,top+4.8,sz-.05,sz+.05,C.screen,nil,true)
	sign(screen,"i  GPS\n"..label,if face<0 then Enum.NormalId.Front else Enum.NormalId.Back,Color3.fromRGB(150,210,190))
	local q=prompt(k,"Show route",label,10,0);q:SetAttribute("CityAction","navigate");q:SetAttribute("To",to)
end
local function tree(parent: Instance,x: number,z: number,k: number,top: number?)
	local h=9+(k%3)*1.5;local base=top or G
	mk(parent,"Tree",Vector3.new(1.2,h,1.2),CFrame.new(x,base+h/2,z),C.oak,Enum.Material.Wood)
	local d=9+(k%4)
	local canopy=mk(parent,"TreeCanopy",Vector3.new(d,d*.8,d),CFrame.new(x,base+h+d*.25,z),if k%2==0 then C.foliage else C.foliageLight,Enum.Material.LeafyGrass,true)
	canopy.Shape=Enum.PartType.Ball
end
local function lamp(parent: Instance,x: number,z: number,lit: boolean,top: number?)
	local base=top or City.WALK_TOP
	mk(parent,"StreetLamp",Vector3.new(.5,12,.5),CFrame.new(x,base+6,z),C.metal,Enum.Material.Metal)
	local head=mk(parent,"StreetLampHead",Vector3.new(2.2,.4,2.2),CFrame.new(x,base+12.2,z),GLOW,Enum.Material.Neon,true)
	if lit then light(head,28,.75) end
end
local function hash(s: string): number
	local h=7
	for i=1,#s do h=(h*31+string.byte(s,i))%2147483647 end
	return h
end

------------------------------------------------------------------------------------------------ roads
-- Positions along road r where other roads cross it (centre, half width incl. sidewalks).
local function crossings(r: City.Road): {{number}}
	local out: {{number}}={}
	for _,o in City.ROADS do
		if o~=r and o.axis~=r.axis and o.c>=r.a1-1 and o.c<=r.a2+1 and r.c>=o.a1-1 and r.c<=o.a2+1 then
			table.insert(out,{o.c,o.width/2+o.walk})
		end
	end
	table.sort(out,function(a,b) return a[1]<b[1] end)
	return out
end
-- [a1,a2] minus the crossing gaps (each gap widened by `pad`)
local function spans(a1: number,a2: number,gaps: {{number}},pad: number): {{number}}
	local out: {{number}}={};local cur=a1
	for _,g in gaps do
		local g1,g2=g[1]-g[2]-pad,g[1]+g[2]+pad
		if g2>cur and g1<a2 then
			if g1>cur+1 then table.insert(out,{cur,g1}) end
			cur=math.max(cur,g2)
		end
	end
	if a2>cur+1 then table.insert(out,{cur,a2}) end
	return out
end
local function strip(parent: Instance,name: string,r: City.Road,a1: number,a2: number,off: number,w: number,y1: number,y2: number,color: Color3,material: Enum.Material?,decor: boolean?): Part
	if r.axis=="x" then return box(parent,name,a1,a2,y1,y2,r.c+off-w/2,r.c+off+w/2,color,material,decor) end
	return box(parent,name,r.c+off-w/2,r.c+off+w/2,y1,y2,a1,a2,color,material,decor)
end
local function roads(root: Instance)
	local m=folder(root,"Roads")
	for _,r in City.ROADS do
		local ring=r.walk==0
		strip(m,"CityRoad",r,r.a1,r.a2,0,r.width,G+.02,City.ROAD_TOP,C.asphalt,Enum.Material.Asphalt)
		local gaps=crossings(r)
		-- centre line, interrupted at the crossings
		for _,s in spans(r.a1,r.a2,gaps,2) do
			strip(m,"CentreLine",r,s[1],s[2],0,.35,City.ROAD_TOP,City.ROAD_TOP+.03,if ring then YELLOW else WHITE,nil,true)
		end
		if r.walk>0 then
			-- sidewalks on both sides, open where another street crosses
			for _,side in {-1,1} do
				for _,s in spans(r.a1,r.a2,gaps,0) do
					strip(m,"Sidewalk",r,s[1],s[2],side*(r.width/2+r.walk/2),r.walk,G-.175,City.WALK_TOP,BASE_STONE,Enum.Material.Concrete)
				end
			end
			-- street lamps on alternating sides every 160 studs (not on a crossing)
			local n=0
			for a=r.a1+80,r.a2-40,160 do
				local free=true
				for _,g in gaps do if math.abs(a-g[1])<g[2]+10 then free=false end end
				if free then
					n+=1
					local side=if n%2==0 then 1 else -1
					local off=side*(r.width/2+r.walk-1.5)
					if r.axis=="x" then lamp(m,a,r.c+off,n%2==1) else lamp(m,r.c+off,a,n%2==1) end
				end
			end
		else
			-- ring roads: lamps outside the outer edge, neon heads only
			for a=r.a1+300,r.a2-60,240 do
				local x=r.c+(if r.c<0 then -1 else 1)*(r.width/2+3)
				if a>800 then lamp(m,x,a,false,G) end
			end
		end
	end
	-- raised crossings where the new roads meet the South Boulevard's outer sidewalk (z 542..550)
	for _,x in {-1008,0,1008} do
		local hw=if x==0 then 20 else 16
		box(m,"RoadCrossing",x-hw,x+hw,G+.3,City.WALK_TOP+.03,541,551,C.asphalt,Enum.Material.Asphalt)
		for i=-3,3 do box(m,"Zebra",x+i*4-1,x+i*4+1,City.WALK_TOP+.03,City.WALK_TOP+.06,542,550,WHITE,nil,true) end
	end
	-- signposts at the entrances from the district
	local post=box(m,"CitySignPost",30,31,G,G+14,560,561,C.metal,Enum.Material.Metal)
	local board=box(m,"CitySign",24,38,G+8,G+14,559.4,560,Color3.fromRGB(43,51,47),Enum.Material.Metal,true)
	sign(board,"↓ BUSINESS CITY · AIRPORT",Enum.NormalId.Front)
	local _=post
	for _,x in {-1046,1046} do
		box(m,"CitySignPost",x-.5,x+.5,G,G+14,600,601,C.metal,Enum.Material.Metal)
		local b2=box(m,"CitySign",x-7,x+7,G+8,G+14,599.4,600,Color3.fromRGB(43,51,47),Enum.Material.Metal,true)
		sign(b2,"↓ BUSINESS CITY · AIRPORT",Enum.NormalId.Front)
	end
end

------------------------------------------------------------------------------------------------ ground
local function ground(root: Instance)
	local m=folder(root,"Ground")
	-- downtown + airport: stone base with a lawn skin, four pieces (parts stay <= 2048)
	for _,x in {{-1150,0},{0,1150}} do
		for _,z in {{800,2000},{2000,3200}} do
			box(m,"CityGround",x[1],x[2],-2,G,z[1],z[2],BASE_STONE,Enum.Material.Concrete)
			box(m,"CityLawn",x[1],x[2],G,G+.1,z[1],z[2],LAWN,Enum.Material.Grass)
		end
	end
	-- harbour: quay wall, railing, water, and invisible walls along the edges of the south strip
	for _,x in {{-1150,0},{0,1150}} do
		box(m,"Quay",x[1],x[2],-2,G+.6,3200,3206,C.stoneDeep,Enum.Material.Limestone)
		box(m,"QuayRailing",x[1],x[2],G+.6,G+3.8,3203.6,3204.2,C.metal,Enum.Material.Metal,true)
		glass(box(m,"Sea",x[1],x[2],G-3.2,G-3,3206,3800,C.water,nil,true),.15)
		invisible(box(m,"BoundaryWall",x[1],x[2],G,G+80,3206,3210,C.white))
	end
	for _,x in {-1154,1150} do
		for _,z in {{800,2000},{2000,3210}} do invisible(box(m,"BoundaryWall",x,x+4,G,G+80,z[1],z[2],C.white)) end
	end
end

------------------------------------------------------------------------------------------------ buildings
type Style={core: Color3,coreMat: Enum.Material,coreT: number,band: Color3?,bandMat: Enum.Material?,bandT: number?,trim: Color3}
local STYLES: {[string]: Style}={
	glass={core=C.glassDeep,coreMat=Enum.Material.Glass,coreT=0,trim=C.stoneDeep},
	stone={core=C.stone,coreMat=Enum.Material.Limestone,coreT=0,band=Color3.fromRGB(70,82,92),bandMat=Enum.Material.Glass,bandT=.15,trim=C.stoneDeep},
	brick={core=C.terracotta,coreMat=Enum.Material.Brick,coreT=0,band=Color3.fromRGB(64,74,82),bandMat=Enum.Material.Glass,bandT=.2,trim=C.stone},
	ribbon={core=C.white,coreMat=Enum.Material.Plaster,coreT=0,band=Color3.fromRGB(52,60,70),bandMat=Enum.Material.Glass,bandT=.1,trim=C.metalSoft},
	fins={core=C.blueSoft,coreMat=Enum.Material.Glass,coreT=0,trim=C.stone},
	setback={core=C.stone,coreMat=Enum.Material.Limestone,coreT=0,band=Color3.fromRGB(60,72,84),bandMat=Enum.Material.Glass,bandT=.15,trim=C.stoneDeep},
	hotel={core=C.fabricSand,coreMat=Enum.Material.Plaster,coreT=0,band=Color3.fromRGB(58,64,72),bandMat=Enum.Material.Glass,bandT=.1,trim=C.brass},
}
-- Upper floors: facade only (the ground-floor ceiling closes the volume; nothing above it is enterable).
local function shellUpper(f: CFrame,m: Instance,b: City.Building,base: number,top: number,fh: number)
	local hw,d=b.width/2,b.depth;local st=STYLES[b.style] or STYLES.stone
	local floors=math.max(1,math.floor((top-base)/fh+.5))
	local coreTop=top
	if b.style=="setback" and floors>=4 then
		coreTop=base+(floors-2)*fh
		local inset=8
		glass(lbox(f,m,"UpperVolume",-hw+inset,hw-inset,coreTop+1,top,inset,d-inset,C.glassDeep:Lerp(b.accent,.12),nil),0).Material=Enum.Material.Glass
		lbox(f,m,"Terrace",-hw,hw,coreTop,coreTop+1,0,d,st.trim,Enum.Material.Limestone)
		glass(lbox(f,m,"TerraceRail",-hw,hw,coreTop+1,coreTop+3.6,-.1,.3,C.glass,nil,true),.5)
	end
	local core=lbox(f,m,"Volume",-hw+.5,hw-.5,base,coreTop,.5,d-.5,if b.style=="glass" then st.core:Lerp(b.accent,.15) else st.core,st.coreMat)
	core.Transparency=st.coreT
	local n=math.max(1,math.floor((coreTop-base)/fh+.5))
	if b.style=="glass" then
		for k=1,n-1 do lbox(f,m,"FloorBand",-hw-.3,hw+.3,base+k*fh-.4,base+k*fh+.4,-.3,d+.3,st.trim,Enum.Material.Limestone,true) end
		for i=-2,3 do lbox(f,m,"Fin",i*10-5.6,i*10-4.4,base,coreTop,-1.2,0,C.metal,Enum.Material.Metal,true) end
	elseif b.style=="fins" then
		for i=-3,3 do lbox(f,m,"Fin",i*8.4-.6,i*8.4+.6,base,coreTop,-1.4,0,st.trim,Enum.Material.Limestone,true) end
		for _,x in {-hw,hw-1.4} do for j=1,3 do lbox(f,m,"Fin",x,x+1.4,base,coreTop,j*d/4-.6,j*d/4+.6,st.trim,Enum.Material.Limestone,true) end end
	elseif b.style=="brick" then
		for i=-2,2 do
			local x=i*10.5
			glass(lbox(f,m,"WindowColumn",x-2.6,x+2.6,base+2,coreTop-2,-.2,d+.2,st.band or C.metal,nil,true),st.bandT or .2)
		end
		for k=1,n-1 do lbox(f,m,"FloorBand",-hw-.2,hw+.2,base+k*fh-.35,base+k*fh+.35,-.25,d+.25,st.trim,Enum.Material.Limestone,true) end
	else
		-- stone / ribbon / setback / hotel: one glass ribbon per floor wrapping all four sides
		for k=1,n do
			local y=base+(k-1)*fh
			local ribbon=lbox(f,m,"WindowRibbon",-hw-.1,hw+.1,y+2.5,y+fh-2.5,-.1,d+.1,st.band or C.metal,st.bandMat or Enum.Material.Glass,true)
			ribbon.Transparency=st.bandT or .15
		end
		if b.style=="stone" or b.style=="setback" then
			for _,c in {{-hw-.4,-hw+1.6,-.4,1.6},{hw-1.6,hw+.4,-.4,1.6},{-hw-.4,-hw+1.6,d-1.6,d+.4},{hw-1.6,hw+.4,d-1.6,d+.4}} do
				lbox(f,m,"Pilaster",c[1],c[2],base,coreTop,c[3],c[4],st.trim,Enum.Material.Limestone,true)
			end
		elseif b.style=="ribbon" then
			lbox(f,m,"AccentStripe",hw-6,hw-2,base,coreTop,-.5,.2,b.accent,nil,true)
		end
	end
	-- roof: cap, accent crown, plant room
	lbox(f,m,"Roof",-hw-.3,hw+.3,top,top+1.2,-.3,d+.3,st.trim,Enum.Material.Limestone)
	lbox(f,m,"Crown",-hw-.2,hw+.2,top-1.6,top,-.2,d+.2,b.accent,nil,true)
	lbox(f,m,"PlantRoom",-hw*.4,hw*.3,top+1.2,top+4.6,d*.45,d*.8,C.metalSoft,Enum.Material.Metal,true)
end
local function officeInterior(f: CFrame,m: Instance,b: City.Building,l: City.Layout,gf: number)
	local name=b.name
	-- reception desk, logo wall, receptionist post (placeholder: the later staff package puts an NPC here)
	lbox(f,m,"ReceptionDesk",-8,8,.5,4,21.5,23.5,C.oak,Enum.Material.Wood)
	lbox(f,m,"ReceptionTop",-8.5,8.5,4,4.4,21.2,24,C.stone,Enum.Material.Limestone)
	local wall=lbox(f,m,"LogoWall",-10,10,.5,13,33,34,b.accent:Lerp(C.metal,.35),Enum.Material.SmoothPlastic)
	sign(wall,name,Enum.NormalId.Front)
	local post=invisible(mk(m,"ReceptionistPost",Vector3.new(2,5,1),f*CFrame.new(l.reception),C.white,nil,true))
	post:SetAttribute("CityPost","reception");post:SetAttribute("BuildingId",b.id)
	if b.clientId then post:SetAttribute("ClientId",b.clientId) end
	-- waiting area
	lbox(f,m,"Sofa",-27,-17,.5,2.6,8,12,C.fabric,Enum.Material.Fabric)
	lbox(f,m,"SofaBack",-27,-17,2.6,5,11,12,C.fabric,Enum.Material.Fabric,true)
	lbox(f,m,"CoffeeTable",-25,-19,.5,1.9,3.5,6.5,C.oakDark,Enum.Material.Wood)
	lbox(f,m,"Planter",-27,-24,.5,3,27,30,C.terracotta,Enum.Material.Slate)
	local leaf=lbox(f,m,"PlantLeaves",-28,-23,3,8,26,31,C.foliage,Enum.Material.LeafyGrass,true);leaf.Shape=Enum.PartType.Ball
	light(lbox(f,m,"CeilingLight",-6,6,gf-.4,gf,8,20,C.lightWarm,Enum.Material.Neon,true),30,.9,C.lightWarm)
	-- meeting room (glass partitions; door gap x 12..18)
	local r=l.meetingRoom
	if r then
		glass(lbox(f,m,"MeetingGlass",r.x1,12,.5,gf,r.z1,r.z1+.6,C.glass))
		glass(lbox(f,m,"MeetingGlass",18,r.x2,.5,gf,r.z1,r.z1+.6,C.glass))
		lbox(f,m,"MeetingLintel",12,18,11,gf,r.z1,r.z1+.6,C.stone,Enum.Material.Limestone)
		glass(lbox(f,m,"MeetingGlass",r.x1,r.x1+.6,.5,gf,r.z1+.6,r.z2,C.glass))
		local tableTop=lbox(f,m,"MeetingTable",12,23,.5,3.2,46,53,C.oak,Enum.Material.Wood)
		local q=prompt(tableTop,"Start meeting",name,10,.5)
		q:SetAttribute("CityAction","meeting");q:SetAttribute("BuildingId",b.id)
		if b.clientId then q:SetAttribute("ClientId",b.clientId);tableTop:SetAttribute("ClientId",b.clientId) end
		for _,x in {14,17.5,21} do
			for _,z in {44.6,54.4} do lbox(f,m,"MeetingChair",x-1,x+1,.5,2.4,z-1,z+1,C.fabricCharcoal,Enum.Material.Fabric,true) end
		end
		local screen=lbox(f,m,"MeetingScreen",11,24,5,11,58.4,59,C.screen,Enum.Material.SmoothPlastic,true)
		sign(screen,name.."\nMeeting room",Enum.NormalId.Front,Color3.fromRGB(200,214,220))
		lbox(f,m,"MeetingLightPanel",12,23,gf-.4,gf,45,54,C.lightNeutral,Enum.Material.Neon,true)
	end
end
local function hotelInterior(f: CFrame,m: Instance,b: City.Building,l: City.Layout,gf: number)
	local hw,d=b.width/2,b.depth
	local dz=l.desk.Z
	lbox(f,m,"ReceptionDesk",-12,12,.5,4,dz-1.5,dz+1.5,C.oakDark,Enum.Material.Wood)
	lbox(f,m,"ReceptionTop",-12.5,12.5,4,4.4,dz-1.8,dz+1.8,C.stone,Enum.Material.Marble)
	local wall=lbox(f,m,"LogoWall",-16,16,.5,13,dz+10,dz+11,C.brass:Lerp(C.oakDark,.4),Enum.Material.Wood)
	sign(wall,string.upper(b.name).."\nReception",Enum.NormalId.Front)
	local post=invisible(mk(m,"ReceptionistPost",Vector3.new(2,5,1),f*CFrame.new(l.reception),C.white,nil,true))
	post:SetAttribute("CityPost","hotel_reception");post:SetAttribute("BuildingId",b.id)
	-- lounge
	for i,x in {-hw+6,-hw+20} do
		lbox(f,m,"LoungeSofa",x,x+10,.5,2.6,14,18,C.fabricBlue,Enum.Material.Fabric)
		lbox(f,m,"LoungeSofaBack",x,x+10,2.6,5,17,18,C.fabricBlue,Enum.Material.Fabric,true)
		local _=i
	end
	lbox(f,m,"LoungeTable",-hw+10,-hw+26,.5,1.9,8,12,C.oak,Enum.Material.Wood)
	for _,x in {hw-14,hw-24} do lbox(f,m,"Armchair",x,x+5,.5,2.8,16,21,C.leather,Enum.Material.Leather) end
	for _,x in {-hw+4,hw-7} do
		lbox(f,m,"Planter",x,x+3,.5,3,d-12,d-9,C.terracotta,Enum.Material.Slate)
		local leaf=lbox(f,m,"PlantLeaves",x-1,x+4,3,8,d-13,d-8,C.foliage,Enum.Material.LeafyGrass,true);leaf.Shape=Enum.PartType.Ball
	end
	-- lift doors to the (abstract) room floors, and a direction sign
	for _,x in {-14,-2,10} do lbox(f,m,"LiftFront",x,x+4.6,.5,11,d-1.25,d-1,C.metalSoft,Enum.Material.Metal,true) end
	local info=lbox(f,m,"FloorSign",-14,14.6,11.6,13.6,d-1.3,d-1.1,C.metal,Enum.Material.Metal,true)
	sign(info,"Lifts · Rooms 101–"..tostring(100*(b.floors-1)+12),Enum.NormalId.Front)
	light(lbox(f,m,"CeilingLight",-10,10,gf-.4,gf,10,30,C.lightWarm,Enum.Material.Neon,true),36,.9,C.lightWarm)
	light(lbox(f,m,"CeilingLight",-10,10,gf-.4,gf,d-34,d-14,C.lightWarm,Enum.Material.Neon,true),36,.8,C.lightWarm)
end
-- Office / hotel / tower: enterable ground floor (lobby + reception + meeting room or lounge), facade above.
function Builder.building(parent: Instance,b: City.Building): Model
	local f=b.frame;local hw,d=b.width/2,b.depth
	local l=City.layout(b)
	local gf=City.OFFICE.groundHeight
	local fh=if b.interior=="hotel" then 12 else City.OFFICE.floorHeight
	local base=gf+1;local top=base+(b.floors-1)*fh
	local m=Instance.new("Model");m.Name=(if b.kind=="hotel" then "Hotel_" elseif b.kind=="tower" then "ClientTower_" else "ClientOffice_")..b.id
	m:SetAttribute("BuildingId",b.id);m:SetAttribute("Zone",b.zone)
	if b.clientId then m:SetAttribute("ClientId",b.clientId) end
	local shell=folder(m,"Shell",if b.skyline then Enum.ModelStreamingMode.Persistent else nil)
	local inside=folder(m,"Interior",Enum.ModelStreamingMode.Atomic)
	local dw=if b.interior=="hotel" then 14 else City.OFFICE.doorWidth
	-- ground floor shell
	lbox(f,shell,"Floor",-hw,hw,0,.5,0,d,C.stone,Enum.Material.Limestone)
	glass(lbox(f,shell,"Storefront",-hw,-dw/2,.5,gf,0,.8,C.glass))
	glass(lbox(f,shell,"Storefront",dw/2,hw,.5,gf,0,.8,C.glass))
	lbox(f,shell,"EntranceLintel",-dw/2,dw/2,11,gf,0,.8,C.stoneDeep,Enum.Material.Limestone)
	for x=-hw+10,hw-10,10 do
		if math.abs(x)>dw/2+.5 then lbox(f,shell,"Mullion",x-.2,x+.2,.5,gf,-.2,.9,C.metal,Enum.Material.Metal,true) end
	end
	lbox(f,shell,"SideWall",-hw,-hw+1,.5,gf,.8,d,C.stone,Enum.Material.Limestone)
	lbox(f,shell,"SideWall",hw-1,hw,.5,gf,.8,d,C.stone,Enum.Material.Limestone)
	lbox(f,shell,"BackWall",-hw+1,hw-1,.5,gf,d-1,d,C.stone,Enum.Material.Limestone)
	lbox(f,shell,"Ceiling",-hw,hw,gf,base,0,d,C.stoneDeep,Enum.Material.Limestone)
	shellUpper(f,shell,b,base,top,fh)
	-- entrance canopy and the company sign
	lbox(f,shell,"Canopy",-dw/2-3,dw/2+3,11.2,11.8,-6,0,b.accent,Enum.Material.Metal,true)
	local plate=lbox(f,shell,"CompanySign",-14,14,12.4,15.4,-.7,-.1,C.metal,Enum.Material.Metal,true)
	sign(plate,b.name,Enum.NormalId.Front)
	if b.skyline or b.kind=="tower" then
		local roofSign=lbox(f,shell,"RoofSign",-hw+6,hw-6,top+1.2,top+7,.4,1,C.metal,Enum.Material.Metal,true)
		sign(roofSign,string.upper(b.name),Enum.NormalId.Front,b.accent:Lerp(Color3.new(1,1,1),.55))
	end
	-- forecourt: visitor parking (downtown) or paving (abroad)
	local pd=City.OFFICE.parkingDepth
	if b.parking then
		local lot=lbox(f,shell,"VisitorParking",-hw,hw,-.05,.3,-pd,0,C.asphalt,Enum.Material.Asphalt);lot:SetAttribute("VisitorBays",#l.bays)
		lbox(f,shell,"Walkway",-dw/2-1,dw/2+1,.3,.34,-pd,0,C.stonePave,Enum.Material.Pavement,true)
		local edges: {number}={}
		for _,x in l.bays do
			for _,e in {x-5,x+5} do if not table.find(edges,e) then table.insert(edges,e) end end
		end
		table.sort(edges)
		for _,x in edges do lbox(f,shell,"BayLine",x-.15,x+.15,.3,.33,-pd+1,-1,WHITE,nil,true) end
		local visitor=lbox(f,shell,"VisitorSign",-hw+1,-hw+5,.3,3.3,-1.4,-1.2,Color3.fromRGB(58,88,140),nil,true)
		sign(visitor,"P\nVISITORS",Enum.NormalId.Front)
	else
		lbox(f,shell,"Forecourt",-hw,hw,-.05,.3,-pd,0,C.stonePave,Enum.Material.Pavement)
	end
	if b.interior=="hotel" then hotelInterior(f,inside,b,l,gf) else officeInterior(f,inside,b,l,gf) end
	m.Parent=parent
	return m
end

------------------------------------------------------------------------------------------------ downtown
local function convention(root: Instance)
	local c=City.CONVENTION;local f=c.frame;local hw,d,h=c.width/2,c.depth,c.height
	local m=Instance.new("Model");m.Name="ConventionCentre";m:SetAttribute("BuildingId","convention")
	local shell=folder(m,"Shell");local inside=folder(m,"Interior",Enum.ModelStreamingMode.Atomic)
	local setback=-f:PointToObjectSpace(Vector3.new(f.Position.X,G,1000)).Z -- street centre in front
	lbox(f,shell,"Forecourt",-hw,hw,-.05,.3,-(setback-28),0,C.stonePave,Enum.Material.Pavement)
	lbox(f,shell,"Floor",-hw,hw,0,.5,0,d,C.stone,Enum.Material.Limestone)
	local doors={-40,0,40}
	local x0=-hw
	for _,x in doors do
		glass(lbox(f,shell,"Facade",x0,x-6,.5,h,0,.8,C.glass))
		lbox(f,shell,"EntranceLintel",x-6,x+6,12,h,0,.8,C.stoneDeep,Enum.Material.Limestone)
		x0=x+6
	end
	glass(lbox(f,shell,"Facade",x0,hw,.5,h,0,.8,C.glass))
	for x=-hw+20,hw-20,20 do
		local free=true;for _,dx in doors do if math.abs(x-dx)<7 then free=false end end
		if free then lbox(f,shell,"Mullion",x-.3,x+.3,.5,h,-.3,.9,C.metal,Enum.Material.Metal,true) end
	end
	lbox(f,shell,"SideWall",-hw,-hw+1.5,.5,h,.8,d,C.stone,Enum.Material.Limestone)
	lbox(f,shell,"SideWall",hw-1.5,hw,.5,h,.8,d,C.stone,Enum.Material.Limestone)
	lbox(f,shell,"BackWall",-hw+1.5,hw-1.5,.5,h,d-1.5,d,C.stone,Enum.Material.Limestone)
	lbox(f,shell,"Roof",-hw-4,hw+4,h,h+2,-8,d+2,C.stoneDeep,Enum.Material.Limestone)
	lbox(f,shell,"RoofCrown",-hw-4.2,hw+4.2,h-1.4,h,-8.2,-7.8,C.sage,nil,true)
	local title=lbox(f,shell,"VenueSign",-36,36,h-7,h-2,-8.6,-8.2,C.metal,Enum.Material.Metal,true)
	sign(title,"CONVENTION CENTRE",Enum.NormalId.Front)
	-- foyer / hall partition with two openings
	local pz=50
	for _,s in {{-hw+1.5,-50},{-38,38},{50,hw-1.5}} do lbox(f,inside,"HallWall",s[1],s[2],.5,h,pz,pz+1,C.interior,Enum.Material.Plaster) end
	for _,x in {-44,44} do lbox(f,inside,"HallLintel",x-6,x+6,12,h,pz,pz+1,C.interior,Enum.Material.Plaster) end
	local expo=lbox(f,inside,"ExpoBanner",-30,30,16,24,pz-.2,pz,C.sage,nil,true)
	sign(expo,"AI EMPIRE EXPO\nBusiness City",Enum.NormalId.Front)
	lbox(f,inside,"InfoDesk",-10,10,.5,4,24,27,C.oak,Enum.Material.Wood)
	-- hall: stage with two steps, screen, seating blocks either side of the centre aisle
	lbox(f,inside,"Stage",-60,60,.5,3.5,150,d-2,C.oakDark,Enum.Material.WoodPlanks)
	lbox(f,inside,"StageStep",-8,8,.5,2,146,150,C.oakDark,Enum.Material.WoodPlanks)
	local screen=lbox(f,inside,"StageScreen",-40,40,8,26,d-3.5,d-2,C.screen,nil,true)
	sign(screen,"AI EMPIRE EXPO",Enum.NormalId.Front,Color3.fromRGB(150,210,190))
	for row=0,5 do
		local z=80+row*10
		for _,s in {{-70,-8},{8,70}} do lbox(f,inside,"SeatRow",s[1],s[2],.5,2.3,z,z+3,C.fabricCharcoal,Enum.Material.Fabric) end
	end
	light(lbox(f,inside,"CeilingLight",-14,14,h-.4,h,18,34,C.lightWarm,Enum.Material.Neon,true),36,.9,C.lightWarm)
	light(lbox(f,inside,"CeilingLight",-30,30,h-.4,h,90,100,C.lightNeutral,Enum.Material.Neon,true),48,.8)
	light(lbox(f,inside,"CeilingLight",-30,30,h-.4,h,130,140,C.lightNeutral,Enum.Material.Neon,true),48,.8)
	m.Parent=root
end
local function plaza(root: Instance)
	local r=City.PLAZA;local m=folder(root,"CityPlaza")
	box(m,"PlazaPaving",r.x1,r.x2,G,G+.3,r.z1,r.z2,C.stonePave,Enum.Material.Pavement)
	local cx,cz=(r.x1+r.x2)/2,(r.z1+r.z2)/2
	local top=G+.3
	-- fountain
	for _,s in {{cx-15,cx+15,cz-15,cz-13},{cx-15,cx+15,cz+13,cz+15},{cx-15,cx-13,cz-13,cz+13},{cx+13,cx+15,cz-13,cz+13}} do
		box(m,"FountainRim",s[1],s[2],top,top+1.4,s[3],s[4],C.stone,Enum.Material.Limestone)
	end
	glass(box(m,"FountainWater",cx-13,cx+13,top,top+.9,cz-13,cz+13,C.water,nil,true),.25)
	box(m,"FountainColumn",cx-2,cx+2,top,top+4,cz-2,cz+2,C.stoneDeep,Enum.Material.Limestone)
	local jet=box(m,"FountainJet",cx-.6,cx+.6,top+4,top+12,cz-.6,cz+.6,Color3.fromRGB(190,226,236),Enum.Material.Neon,true);jet.Transparency=.35
	-- planters with trees, benches, lamps
	local k=0
	for _,x in {r.x1+30,r.x2-30} do
		for _,z in {r.z1+60,cz-80,cz+80,r.z2-40} do
			k+=1
			box(m,"Planter",x-4,x+4,top,top+1.6,z-4,z+4,C.stone,Enum.Material.Limestone)
			tree(m,x,z,k,top+1.6)
		end
	end
	for _,z in {cz-40,cz+40} do
		for _,x in {cx-34,cx+30} do box(m,"Bench",x,x+4,top,top+1.6,z-5,z+5,C.oak,Enum.Material.Wood) end
	end
	for i,p in {{r.x1+8,r.z1+8},{r.x2-8,r.z1+8},{r.x1+8,r.z2-8},{r.x2-8,r.z2-8}} do lamp(m,p[1],p[2],i<=2,top) end
	local plinth=box(m,"MapBoard",cx-10,cx+10,top,top+9,r.z1+14,r.z1+15,Color3.fromRGB(43,51,47),Enum.Material.Metal)
	sign(plinth,"BUSINESS CITY\nParkway · Business Avenue · Harbour Road\nCity Hotel east · Airport south",Enum.NormalId.Front)
	local q=prompt(plinth,"Show route","City Airport",10,0);q:SetAttribute("CityAction","navigate");q:SetAttribute("To","airport")
end
-- Background blocks: solid, not enterable (core + glass skin + roof; tall ones get a setback crown).
local function filler(m: Instance,x: number,z: number,w: number,dd: number,h: number,k: number)
	local tones={C.stone,C.concrete,C.sageLight,C.fabricSand,C.blueSoft,C.white}
	local tone=tones[k%#tones+1]
	local glassy=k%3==0
	box(m,"CityBlock",x-w/2,x+w/2,G,G+h,z-dd/2,z+dd/2,if glassy then C.glassDeep else tone,if glassy then Enum.Material.Glass elseif k%2==0 then Enum.Material.Limestone else Enum.Material.Concrete)
	if not glassy then glass(box(m,"CityBlockWindows",x-w/2-.2,x+w/2+.2,G+6,G+h-3,z-dd/2-.2,z+dd/2+.2,Color3.fromRGB(70,86,98),nil,true),.55) end
	box(m,"CityBlockRoof",x-w/2-.4,x+w/2+.4,G+h,G+h+1,z-dd/2-.4,z+dd/2+.4,C.stoneDeep,Enum.Material.Limestone,true)
	if h>=70 then box(m,"CityBlockCrown",x-w/3,x+w/3,G+h+1,G+h+9,z-dd/3,z+dd/3,if glassy then C.stone else C.glassDeep,if glassy then Enum.Material.Limestone else Enum.Material.Glass,true) end
end
local function overlaps(a: City.Rect,b: City.Rect): boolean return a.x1<b.x2 and a.x2>b.x1 and a.z1<b.z2 and a.z2>b.z1 end
-- World rectangle of a building incl. its forecourt, padded.
local function footprint(b: City.Building,pad: number): City.Rect
	local hw=b.width/2;local r: City.Rect={x1=math.huge,x2=-math.huge,z1=math.huge,z2=-math.huge}
	for _,c in {Vector3.new(-hw,0,-City.OFFICE.parkingDepth),Vector3.new(hw,0,-City.OFFICE.parkingDepth),Vector3.new(-hw,0,b.depth),Vector3.new(hw,0,b.depth)} do
		local w=b.frame:PointToWorldSpace(c)
		r.x1,r.x2,r.z1,r.z2=math.min(r.x1,w.X),math.max(r.x2,w.X),math.min(r.z1,w.Z),math.max(r.z2,w.Z)
	end
	return {x1=r.x1-pad,x2=r.x2+pad,z1=r.z1-pad,z2=r.z2+pad}
end
-- Fill a city block with background buildings on a 92-stud lot grid (26+ stud walkways between them),
-- skipping lots that touch `occupied`; about every sixth lot is a pocket park. Deterministic (hash).
local function fillLots(m: Instance,block: City.Rect,occupied: {City.Rect},seed: string,minH: number,stepH: number)
	local step=92
	local nx,nz=math.floor((block.x2-block.x1)/step),math.floor((block.z2-block.z1)/step)
	local ox=block.x1+((block.x2-block.x1)-nx*step)/2;local oz=block.z1+((block.z2-block.z1)-nz*step)/2
	for i=0,nx-1 do
		for j=0,nz-1 do
			local h=hash(seed..":"..i..":"..j)
			local w,dd=52+(h%3)*8,52+(math.floor(h/3)%3)*8
			local cx,cz=ox+i*step+step/2,oz+j*step+step/2
			local lot: City.Rect={x1=cx-w/2,x2=cx+w/2,z1=cz-dd/2,z2=cz+dd/2}
			local free=true
			for _,o in occupied do if overlaps(lot,o) then free=false;break end end
			if free then
				if h%6==0 then
					box(m,"PocketPark",lot.x1,lot.x2,G+.1,G+.2,lot.z1,lot.z2,LAWN,Enum.Material.Grass)
					for t=0,2 do tree(m,cx+(t-1)*w/3,cz+(if t==1 then dd/4 else -dd/5),h+t,G+.2) end
				else
					filler(m,cx,cz,w,dd,minH+(math.floor(h/9)%7)*stepH,h)
				end
			end
		end
	end
end
local function downtown(root: Instance)
	local m=folder(root,"Downtown")
	local offices=folder(m,"ClientOffices")
	for _,b in City.BUILDINGS do if b.zone=="downtown" then Builder.building(offices,b) end end
	convention(m)
	plaza(m)
	local green=folder(m,"Greenery")
	-- City Park between the campus parkland and the Parkway, with a footpath
	for _,s in {{-990,-28},{28,990}} do box(green,"ParkPath",s[1],s[2],G,G+.15,882,888,C.stonePave,Enum.Material.Pavement) end
	local k=0
	for _,z in {836,930} do
		for x=-950,950,95 do
			k+=1
			local tx=x+((k*37)%30)-15
			if math.abs(tx)>48 and math.abs(tx)<975 then tree(green,tx,z+((k*23)%24)-12,k) end
		end
	end
	-- trees along Airport Road
	for x=-960,960,120 do k+=1;if math.abs(x)>60 then tree(green,x,2330,k) end end
	-- background blocks fill the city blocks around the client offices, the plaza and the convention centre
	local blocks=folder(m,"CityBlocks")
	local occupied: {City.Rect}={}
	for _,b in City.BUILDINGS do if b.zone=="downtown" then table.insert(occupied,footprint(b,10)) end end
	local cv=City.CONVENTION
	table.insert(occupied,{x1=cv.frame.X-cv.width/2-12,x2=cv.frame.X+cv.width/2+12,z1=1028,z2=cv.frame.Z+cv.depth+12})
	local pz=City.PLAZA;table.insert(occupied,{x1=pz.x1-12,x2=pz.x2+12,z1=pz.z1-12,z2=pz.z2+12})
	table.insert(occupied,{x1=-1200,x2=1200,z1=2290,z2=2420}) -- tree row and Airport Road
	local xs={{-992,-368},{-312,-28},{28,312},{368,992}}
	for row,zs in {{1028,1472},{1528,1972}} do
		for col,x in xs do fillLots(blocks,{x1=x[1]+6,x2=x[2]-6,z1=zs[1]+6,z2=zs[2]-6},occupied,"dt"..row..col,30,12) end
	end
	for col,x in {{-992,-28},{28,992}} do fillLots(blocks,{x1=x[1]+6,x2=x[2]-6,z1=2034,z2=2346},occupied,"south"..col,24,10) end
end

------------------------------------------------------------------------------------------------ halls (Port Meridian kit)
-- A glass hall with door openings in the front facade (frontSide -1 = facade at z1, +1 = facade at z2).
local function hall(parent: Instance,r: City.Rect,h: number,frontSide: number,doors: {number},w: number): Model
	local m=folder(parent,"Hall")
	local fz=if frontSide<0 then r.z1 else r.z2-.8
	local bz=if frontSide<0 then r.z2-.8 else r.z1
	box(m,"HallFloor",r.x1,r.x2,G,G+.5,r.z1,r.z2,C.stone,Enum.Material.Limestone)
	local x0=r.x1
	for _,x in doors do
		glass(box(m,"Facade",x0,x-w/2,G+.5,G+h,fz,fz+.8,C.glass))
		box(m,"EntranceLintel",x-w/2,x+w/2,G+12,G+h,fz,fz+.8,C.stoneDeep,Enum.Material.Limestone)
		x0=x+w/2
	end
	glass(box(m,"Facade",x0,r.x2,G+.5,G+h,fz,fz+.8,C.glass))
	glass(box(m,"BackGlass",r.x1,r.x2,G+.5,G+h,bz,bz+.8,C.glass))
	box(m,"SideWall",r.x1,r.x1+1.5,G+.5,G+h,r.z1+.8,r.z2-.8,C.stone,Enum.Material.Limestone)
	box(m,"SideWall",r.x2-1.5,r.x2,G+.5,G+h,r.z1+.8,r.z2-.8,C.stone,Enum.Material.Limestone)
	box(m,"Roof",r.x1-6,r.x2+6,G+h,G+h+2,r.z1-6,r.z2+6,C.stoneDeep,Enum.Material.Limestone)
	box(m,"RoofBand",r.x1-6.2,r.x2+6.2,G+h+.4,G+h+1.6,(if frontSide<0 then r.z1-6.2 else r.z2+5.8),(if frontSide<0 then r.z1-5.8 else r.z2+6.2),C.sage,nil,true)
	for x=r.x1+24,r.x2-24,24 do
		local free=true;for _,dx in doors do if math.abs(x-dx)<w/2+1 then free=false end end
		if free then box(m,"Mullion",x-.3,x+.3,G+.5,G+h,fz-.3,fz+1.1,C.metal,Enum.Material.Metal,true) end
	end
	return m
end
local function checkin(m: Instance,p: Vector3,facing: number,to: string,action: string,object: string)
	-- facing +1: passengers stand at larger z (counter faces +Z); -1: passengers at smaller z
	local z=p.Z
	local counter=box(m,"CheckinCounter",p.X-12,p.X+12,G+.5,G+4.3,z-2,z+2,C.white,Enum.Material.Marble)
	box(m,"BagBelt",p.X+12,p.X+16,G+.5,G+2,z-2,z+2,C.metalSoft,Enum.Material.Metal,true)
	local backZ=z-facing*5
	local panel=box(m,"CheckinPanel",p.X-12,p.X+12,G+.5,G+10,backZ-.5,backZ+.5,Color3.fromRGB(58,88,140),Enum.Material.SmoothPlastic)
	sign(panel,if to=="abroad" then "CHECK-IN\nPort Meridian" else "CHECK-IN\nCity Airport (home)",if facing<0 then Enum.NormalId.Front else Enum.NormalId.Back)
	local q=prompt(counter,action,object,10,1)
	q:SetAttribute("CityAction","checkin");q:SetAttribute("FlightTo",to)
	counter:SetAttribute("CheckinTo",to)
end

------------------------------------------------------------------------------------------------ entry
-- Builds the whole shared world under workspace.WorldCity (replacing an old one) and returns it.
-- ticketText: ObjectText of the home check-in prompts (price from CityPlan.TRAVEL, formatted by CityService).
function Builder.build(ticketText: string?): Model
	local old=workspace:FindFirstChild("WorldCity");if old then old:Destroy() end
	table.clear(lights)
	local root=Instance.new("Model");root.Name="WorldCity"
	ground(root)
	downtown(root) -- buildings take their lights first ...
	Airport.build(root,{light=light,prompt=prompt,kiosk=kiosk,tree=tree,lamp=lamp},ticketText or "Port Meridian") -- City Airport (AirportBuilder)
	Metro.build(root,{folder=folder,box=box,hall=hall,checkin=checkin,kiosk=kiosk,light=light,sign=sign,tree=tree,lamp=lamp,
		footprint=footprint,fillLots=fillLots,glass=glass,invisible=invisible,building=Builder.building}) -- Port Meridian (MetroBuilder)
	roads(root) -- ... street lamps use what is left of each zone's budget
	root.Parent=workspace
	return root
end
return Builder
