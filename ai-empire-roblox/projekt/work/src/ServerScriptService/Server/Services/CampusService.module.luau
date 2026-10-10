--!strict
-- A large drivable tech district on ONE continuous ground plane at street level: the streets, the twelve
-- campus plots and everything between them meet at world y = STREET_Y. Green belts with a footpath, trees
-- and lamps fill the gaps between neighbouring plots and the row ends; calm parkland covers the district
-- beyond the boulevards and ring roads. Plot sites (and the garages under them) are never covered.
-- To the south three corridors stay free for the roads to Business City and the airport (CityPlan.
-- DISTRICT_LINKS): this service builds their supports at street level, CityBuilder lays the roads on top.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Config=require(ReplicatedStorage.Shared.Config.CampusConfig)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local CityPlan=require(ReplicatedStorage.Shared.Config.CityPlan)
local SessionService=require(script.Parent.SessionService)
local Campus={board={}}
local boardLabel: TextLabel?=nil
local elapsed=10
type Rect={x1: number,x2: number,z1: number,z2: number}
local GROUND=Config.STREET_Y -- top of every walkable district surface
local BASE=-2 -- top of the deep district foundation
local DISTRICT: Rect={x1=-1150,x2=1150,z1=-800,z2=800}
local function part(root: Instance,name: string,size: Vector3,x: number,y: number,z: number,color: Color3,material: Enum.Material?): Part
	local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=CFrame.new(x,y,z);p.Anchored=true;p.Color=color;p.Material=material or Enum.Material.Concrete;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=root;return p
end
local function block(root: Instance,name: string,r: Rect,y1: number,y2: number,color: Color3,material: Enum.Material?): Part
	return part(root,name,Vector3.new(r.x2-r.x1,y2-y1,r.z2-r.z1),(r.x1+r.x2)/2,(y1+y2)/2,(r.z1+r.z2)/2,color,material)
end
local function detail(p: BasePart): BasePart
	p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;return p
end
-- Rectangle minus holes as few rectangles (grid cells merged greedily).
local function subtract(r: Rect,holes: {Rect}): {Rect}
	local xs,zs={r.x1,r.x2},{r.z1,r.z2};local hs: {Rect}={}
	for _,h in holes do
		local x1,x2,z1,z2=math.max(h.x1,r.x1),math.min(h.x2,r.x2),math.max(h.z1,r.z1),math.min(h.z2,r.z2)
		if x2-x1>1e-3 and z2-z1>1e-3 then table.insert(hs,{x1=x1,x2=x2,z1=z1,z2=z2});table.insert(xs,x1);table.insert(xs,x2);table.insert(zs,z1);table.insert(zs,z2) end
	end
	if #hs==0 then return {r} end
	local function uniq(t: {number}): {number} table.sort(t);local o: {number}={};for _,v in t do if #o==0 or v-o[#o]>1e-4 then table.insert(o,v) end end;return o end
	xs,zs=uniq(xs),uniq(zs)
	local free: {{boolean}}={}
	for i=1,#xs-1 do free[i]={};for j=1,#zs-1 do
		local cx,cz=(xs[i]+xs[i+1])/2,(zs[j]+zs[j+1])/2;local f=true
		for _,h in hs do if cx>h.x1 and cx<h.x2 and cz>h.z1 and cz<h.z2 then f=false;break end end
		free[i][j]=f
	end end
	local out: {Rect}={}
	for j=1,#zs-1 do for i=1,#xs-1 do
		if free[i][j] then
			local i2=i;while i2+1<=#xs-1 and free[i2+1][j] do i2+=1 end
			local j2=j;local grow=true
			while grow and j2+1<=#zs-1 do for k=i,i2 do if not free[k][j2+1] then grow=false;break end end;if grow then j2+=1 end end
			for k=i,i2 do for l=j,j2 do free[k][l]=false end end
			table.insert(out,{x1=xs[i],x2=xs[i2+1],z1=zs[j],z2=zs[j2+1]})
		end
	end end
	return out
end
-- World rectangles of the twelve plot sites, computed exactly like PlotService.init.
local function plotSites(): {{Rect}}
	local rows: {{Rect}}={{},{}}
	local s=Plan.SITE
	for i=1,Config.PLOT_COUNT do
		local row=if i<=6 then -1 else 1;local x=((i-1)%6-2.5)*Config.PITCH
		local cf=CFrame.lookAt(Vector3.new(x,Config.STREET_Y,row*Config.ROW_OFFSET),Vector3.new(x,Config.STREET_Y,0))
		local r: Rect={x1=math.huge,x2=-math.huge,z1=math.huge,z2=-math.huge}
		for _,c in {Vector3.new(s.x1,0,s.z1),Vector3.new(s.x2,0,s.z1),Vector3.new(s.x1,0,s.z2),Vector3.new(s.x2,0,s.z2)} do
			local w=cf:PointToWorldSpace(c)
			r.x1,r.x2,r.z1,r.z2=math.min(r.x1,w.X),math.max(r.x2,w.X),math.min(r.z1,w.Z),math.max(r.z2,w.Z)
		end
		table.insert(rows[if row<0 then 1 else 2],r)
	end
	for _,list in rows do table.sort(list,function(a,b) return a.x1<b.x1 end) end
	return rows
end
local function tree(root: Instance,x: number,z: number,k: number,trunk: Color3,leaf: Color3)
	local h=9+(k%3)*1.5
	part(root,"ParkTree",Vector3.new(1.2,h,1.2),x,GROUND+h/2,z,trunk,Enum.Material.Wood)
	local d=9+(k%4)
	local canopy=part(root,"ParkCanopy",Vector3.new(d,d*0.8,d),x,GROUND+h+d*0.25,z,leaf,Enum.Material.LeafyGrass);canopy.Shape=Enum.PartType.Ball;detail(canopy)
end
local function lamp(root: Instance,x: number,z: number,lit: boolean,ink: Color3,glow: Color3)
	part(root,"PathLamp",Vector3.new(.45,9,.45),x,GROUND+4.5,z,ink,Enum.Material.Metal)
	local head=detail(part(root,"PathLampHead",Vector3.new(1.6,.35,1.6),x,GROUND+9.1,z,glow,Enum.Material.Neon))
	if lit then local point=Instance.new("PointLight");point.Range=20;point.Brightness=.6;point.Color=glow;point.Parent=head end
end
-- Continuous district ground: green belts between plots and at the row ends, parkland everywhere else.
local function districtGround(root: Instance,stone: Color3,green: Color3,wood: Color3,ink: Color3)
	local folder=Instance.new("Model");folder.Name="DistrictGround";folder.Parent=root
	local lawn=Color3.fromRGB(104,134,94);local pave=Color3.fromRGB(184,180,170);local leafA=Color3.fromRGB(80,112,76);local leafB=Color3.fromRGB(112,142,96)
	local glow=Color3.fromRGB(238,220,184)
	local function ground(r: Rect,name: string)
		-- parts are limited to 2048 studs per axis: split long rectangles
		local nx,nz=math.ceil((r.x2-r.x1)/1200),math.ceil((r.z2-r.z1)/1200)
		for i=0,nx-1 do for j=0,nz-1 do
			local piece: Rect={x1=r.x1+(r.x2-r.x1)*i/nx,x2=r.x1+(r.x2-r.x1)*(i+1)/nx,z1=r.z1+(r.z2-r.z1)*j/nz,z2=r.z1+(r.z2-r.z1)*(j+1)/nz}
			block(folder,name,piece,BASE,GROUND,stone)
			block(folder,"Lawn",piece,GROUND,GROUND+.1,lawn,Enum.Material.Grass)
		end end
	end
	-- 1. green belts: every gap between neighbouring plot sites and from the row ends to the ring roads
	local ringInner=1016-26
	local k=0
	for _,sites in plotSites() do
		local z1,z2=sites[1].z1,sites[1].z2
		local edges={-ringInner}
		for _,r in sites do table.insert(edges,r.x1);table.insert(edges,r.x2) end
		table.insert(edges,ringInner)
		for g=1,#edges,2 do
			local x1,x2=edges[g],edges[g+1]
			if x2-x1>0.5 then
				local cx=(x1+x2)/2
				ground({x1=x1,x2=x2,z1=z1,z2=z2},"GreenBelt")
				part(folder,"BeltPath",Vector3.new(6,.12,z2-z1),cx,GROUND+.06,(z1+z2)/2,pave,Enum.Material.Pavement)
				local n=0
				for z=z1+24,z2-20,48 do
					n+=1;k+=1
					local side=if n%2==0 then 1 else -1
					tree(folder,cx+side*math.min(9,(x2-x1)/2-5),z,k,wood,if k%2==0 then leafA else leafB)
				end
				local m=0
				for z=z1+48,z2-40,96 do
					m+=1;lamp(folder,cx+3.8,z,m%2==1,ink,glow)
				end
			end
		end
	end
	-- 2. parkland beyond the back boulevards and the ring roads (around the squares and platforms)
	local holes: {Rect}={
		{x1=-200,x2=200,z1=-714,z2=-586}, -- rival promenade
		{x1=-12,x2=12,z1=-660,z2=-510}, -- rival link
		{x1=1018,x2=1122,z1=-60,z2=60}, -- founder square
		{x1=-1125,x2=-1015,z1=-225,z2=-35}, -- west lab platform (courier test grounds)
		{x1=-1024,x2=1024,z1=-35,z2=35}, -- innovation avenue on its support (2048 long)
		{x1=-1024,x2=1024,z1=480,z2=550},{x1=-1024,x2=1024,z1=-550,z2=-480}, -- back boulevards
		{x1=-1042,x2=-990,z1=-540,z2=540},{x1=990,x2=1042,z1=-540,z2=540}, -- ring roads
		{x1=-990,x2=990,z1=-480,z2=480}, -- plots, green belts and the avenue between the ring roads
	}
	-- road corridors to the south (ring-road extensions, Central Avenue): a support at street level each
	for _,r in CityPlan.DISTRICT_LINKS do
		table.insert(holes,r)
		block(folder,"LinkSupport",r,BASE,GROUND,stone)
	end
	local function inLink(x: number,z: number,margin: number): boolean
		for _,r in CityPlan.DISTRICT_LINKS do if x>r.x1-margin and x<r.x2+margin and z>r.z1-margin and z<r.z2+margin then return true end end
		return false
	end
	for _,r in subtract(DISTRICT,holes) do ground(r,"Parkland") end
	-- promenades, plazas and tree groves in the parkland
	-- promenades parallel to the back boulevards (the southern one meets the rival promenade)
	for _,z in {-610,610} do
		-- the southern promenade stops at the three road corridors (pedestrians cross on the road)
		local spans: {{number}}=if z<0 then {{-1120,-200},{200,1120}} else {{-1120,-1042},{-990,-28},{28,990},{1042,1120}}
		for _,span in spans do
			part(folder,"ParkPromenade",Vector3.new(span[2]-span[1],.12,8),(span[1]+span[2])/2,GROUND+.06,z,pave,Enum.Material.Pavement)
		end
	end
	for _,x in {-480,160,800} do
		block(folder,"ParkPlaza",{x1=x-22,x2=x+22,z1=640,z2=684},GROUND,GROUND+.14,pave,Enum.Material.Pavement)
		part(folder,"ParkPlanter",Vector3.new(10,1.6,10),x,GROUND+.8,662,stone,Enum.Material.Limestone)
		tree(folder,x,662,x,wood,leafA)
	end
	for _,z in {700,760,-660,-700} do
		for x=-1080,1080,120 do
			local inPromenade=z<0 and x>-230 and x<230
			if not inPromenade then
				k+=1
				local tx,tz=x+((k*37)%40)-20,z+((k*23)%30)-15
				if not inLink(tx,tz,8) then tree(folder,tx,tz,k,wood,if k%2==0 then leafA else leafB) end
			end
		end
	end
	for _,x in {-1096,1096} do
		for z=-520,520,80 do
			local blocked=(x>0 and z>-80 and z<80) or (x<0 and z>-245 and z<-15)
			if not blocked then k+=1;tree(folder,x,z,k,wood,if k%2==0 then leafA else leafB) end
		end
	end
end
local function sign(p: BasePart,text: string): TextLabel
	local g=Instance.new("SurfaceGui");g.Face=Enum.NormalId.Front;g.CanvasSize=Vector2.new(1200,650);g.LightInfluence=.3;g.Parent=p
	local t=Instance.new("TextLabel");t.BackgroundTransparency=1;t.Size=UDim2.fromScale(1,1);t.Text=text;t.TextScaled=true;t.TextWrapped=true;t.Font=Enum.Font.BuilderSansBold;t.TextColor3=Color3.fromRGB(235,231,216);t.Parent=g;return t
end
function Campus.init()
	local old=workspace:FindFirstChild("TechDistrict");if old then old:Destroy() end
	local root=Instance.new("Model");root.Name="TechDistrict";root.Parent=workspace
	local ink=Color3.fromRGB(43,51,47);local stone=Color3.fromRGB(186,188,169);local green=Color3.fromRGB(88,117,85);local wood=Color3.fromRGB(158,119,78)
	-- parts are limited to 2048 studs per axis (Roblox clamps larger sizes): the deep base is two halves,
	-- the boulevards are 2048 long (x -1024..1024, overlapping the ring roads at x 990..1042)
	for _,x in {-575,575} do part(root,"DistrictFoundation",Vector3.new(1150,2,1600),x,-3,0,stone) end
	for _,z in {0,-515,515} do
		-- the support also carries both sidewalks, so no trench opens beside the street
		part(root,"BoulevardSupport",Vector3.new(2048,26,70),0,11,z,stone)
		part(root,"InnovationAvenue",Vector3.new(2048,.2,50),0,24.12,z,ink,Enum.Material.Asphalt)
		for x=-990,990,44 do
			part(root,"LaneMark",Vector3.new(13,.035,.3),x,24.25,z,Color3.fromRGB(229,223,199))
		end
		for _,side in {-1,1} do
			part(root,"Sidewalk",Vector3.new(2048,.65,8),0,24.15,z+side*31,stone)
			for x=-960,960,160 do
				if z==515 and side==1 and math.abs(x)<30 then continue end -- Central Avenue meets the boulevard here
				part(root,"LightPost",Vector3.new(.65,16,.65),x,32.5,z+side*31,ink,Enum.Material.Metal)
				local light=part(root,"StreetLight",Vector3.new(6,.35,1.2),x,40.5,z+side*29,Color3.fromRGB(238,220,184),Enum.Material.Neon)
				local point=Instance.new("PointLight");point.Range=28;point.Brightness=.7;point.Color=Color3.fromRGB(238,220,184);point.Parent=light
			end
		end
	end
	for _,x in {-1016,1016} do
		part(root,"LoopSupport",Vector3.new(52,24,1080),x,12,0,stone)
		part(root,"RingRoad",Vector3.new(48,.2,1080),x,24.12,0,ink,Enum.Material.Asphalt)
		for z=-480,480,48 do part(root,"RingMark",Vector3.new(.3,.035,14),x,24.25,z,Color3.fromRGB(229,223,199)) end
	end
	-- Street trees and shaded benches along the outer sidewalks of the back boulevards (the old rows at
	-- z = +-76 stood inside the plot forecourts and are gone; the campus sites plant their own frontage).
	for _,z in {-574,574} do
		for x=-880,880,160 do
			part(root,"TreeTrunk",Vector3.new(1.4,12,1.4),x,GROUND+6,z,wood,Enum.Material.Wood)
			detail(part(root,"TreeCanopy",Vector3.new(12,9,12),x,GROUND+14,z,green,Enum.Material.Grass))
			part(root,"Bench",Vector3.new(10,2.2,3),x+22,GROUND+1.1,z,wood,Enum.Material.Wood)
		end
	end
	districtGround(root,stone,green,wood,ink)
	for _,x in {-480,160,800} do for i=-3,3 do part(root,"Crosswalk",Vector3.new(2,.04,50),x+i*3,24.28,0,stone) end end
	part(root,"FounderSquare",Vector3.new(104,24,120),1070,12,0,stone)
	local board=part(root,"FounderBoard",Vector3.new(60,28,1.2),1062,41,33,ink,Enum.Material.Metal)
	boardLabel=sign(board,"AI EMPIRE / FOUNDER DISTRICT\nTrain. Build. Grow.")
	local directory=part(root,"DistrictDirectory",Vector3.new(28,14,.7),1062,32,-38,green)
	sign(directory,"CAMPUS DISTRICT\n01—06  NORTH HEADQUARTERS\n07—12  SOUTH HEADQUARTERS\nWEST  COURIER TEST GROUNDS\nNORTH  RIVAL COMPANIES\nSOUTH: DOWNTOWN · AIRPORT\nRING ROAD  ↔  COMPANY GARAGES")
	for i,def in {{"COMPANY OS","empire"},{"CAMPUS & FLEET","campus"},{"MODEL LAB","lab"}} do
		local terminal=part(root,"PublicTerminal",Vector3.new(7,6,2),1040+(i-1)*16,27.5,-10,ink)
		sign(terminal,def[1]);local q=Instance.new("ProximityPrompt");q.ActionText="Open";q.ObjectText=def[1];q.MaxActivationDistance=12;q.RequiresLineOfSight=false;q:SetAttribute("Public",true);q:SetAttribute("App",def[2]);q.Parent=terminal
	end
	part(root,"WestLabPlatform",Vector3.new(110,24,190),-1070,12,-130,stone)
	part(root,"RivalPromenade",Vector3.new(400,24,128),0,12,-650,stone)
	part(root,"RivalLink",Vector3.new(24,24,150),0,12,-585,stone)
	for _,x in {-48,48} do part(root,"SquarePlanter",Vector3.new(8,2,8),1062+x,25,52,green,Enum.Material.Grass) end
	-- A distant skyline stays clear of the twelve playable campuses.
	for i=1,12 do
		local x=-900+(i-1)*160;local h=44+(i%4)*14
		part(root,"SkylineTower",Vector3.new(48,h,42),x,GROUND+h/2,-750,Color3.fromRGB(112,123,109)) -- based on the district ground
		for y=10,h-5,12 do part(root,"SkylineWindow",Vector3.new(40,3,.2),x,GROUND+y,-728.8,Color3.fromRGB(166,181,169),Enum.Material.Glass).CanCollide=false end
	end
end
function Campus.tick(dt: number)
	elapsed+=dt
	if elapsed>=5 then
		elapsed=0
		local board={}
		for _,session in SessionService.all() do
			local data=session.data;local company=data.company
			if not session.closed and company then
				table.insert(board,{name=company.name,revenue=data.stats.totalRevenue,users=data.stats.peakUsers,best=data.stats.bestOverall,office=data.empire.office,userId=session.userId})
			end
		end
		table.sort(board,function(a,b)
			if a.best==b.best then return a.userId<b.userId end
			return a.best>b.best
		end)
		Campus.board=board
		local label=boardLabel
		if label then
			local lines={"AI EMPIRE  /  STRONGEST TRAINED AI",""}
			for i=1,math.min(8,#board) do
				local entry=board[i]
				table.insert(lines,string.format("%d. %s  |  %s",i,entry.name,string.format("%.1f pts",entry.best)))
			end
			if #board==0 then table.insert(lines,"Your company could be first.") end
			label.Text=table.concat(lines,"\n")
		end
	end
	for _,session in SessionService.all() do
		session.live.empire={board=Campus.board}
	end
end
return Campus
