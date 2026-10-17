--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Shared=ReplicatedStorage.Shared
local ModelMath=require(Shared.ModelMath)
local MarketMath=require(Shared.MarketMath)
local ModelConfig=require(Shared.Config.ModelConfig)
local Hardware=require(Shared.Config.HardwareConfig)
local StudioMath=require(Shared.StudioMath)
local Template=require(script.Parent.Parent.Lib.Template)
local Economy=require(script.Parent.EconomyService)
local NPC={sessions={} :: {any},activities={} :: {any}}
-- Server-independent NPC band (CORE_SPEC 3.1): every server meets the same three rival labs.
NPC.NPC_BOOST=1.2
NPC.NPC_CAP=64
NPC.API_FLOOR=1.0
local elapsed=0
local signs: {[number]:TextLabel}={}
local identities={{id=-100000001,name="Morrow Labs",focus="coding",color={126,155,177}},
	{id=-100000002,name="Fern Intelligence",focus="balanced",color={139,166,131}},
	{id=-100000003,name="Kiln Research",focus="reasoning",color={189,141,108}}}
local function note(s: any,text: string)
	s.activity=text
	table.insert(NPC.activities,1,{company=s.data.company.name,text=text,time=workspace:GetServerTimeNow()})
	while #NPC.activities>12 do table.remove(NPC.activities) end
end
local function part(parent: Instance,name: string,size: Vector3,position: Vector3,color: Color3): Part
	local p=Instance.new("Part");p.Name=name;p.Size=size;position=Vector3.new(position.X-115,position.Y+24,position.Z-500);p.Position=position;p.CFrame=CFrame.new(position.X,position.Y,position.Z);p.Anchored=true
	p.Color=color;p.Material=Enum.Material.SmoothPlastic;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=parent;return p
end
local function office(s: any,index: number)
	local root=workspace:FindFirstChild("RivalQuarter")
	if not root then root=Instance.new("Folder");root.Name="RivalQuarter";root.Parent=workspace end
	local m=Instance.new("Model");m.Name=s.data.company.name;m.Parent=root
	local x=60+(index-1)*55
	local stone=Color3.fromRGB(186,184,169);local dark=Color3.fromRGB(39,51,49);local accent=Color3.fromRGB(unpack(s.rgb))
	part(m,"Foundation",Vector3.new(42,1,34),Vector3.new(x,.6,-148),stone)
	part(m,"Facade",Vector3.new(38,14,1),Vector3.new(x,8,-163),dark)
	part(m,"Roof",Vector3.new(42,1,34),Vector3.new(x,15,-148),stone)
	for _, dx in {-19,19} do part(m,"Column",Vector3.new(1.2,14,32),Vector3.new(x+dx,8,-148),stone) end
	part(m,"SignBand",Vector3.new(36,2,.3),Vector3.new(x,12,-130.5),accent)
	local board=part(m,"CompanyBoard",Vector3.new(30,5,.3),Vector3.new(x,8,-130.3),dark)
	local gui=Instance.new("SurfaceGui");gui.Name="CompanyPrint";gui.Face=Enum.NormalId.Front;gui.PixelsPerStud=28;gui.Parent=board
	local text=Instance.new("TextLabel");text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1;text.TextColor3=Color3.fromRGB(239,235,220);text.Font=Enum.Font.BuilderSansBold;text.TextSize=23;text.TextWrapped=true;text.Text=s.data.company.name;text.Parent=gui;signs[s.userId]=text
	board.CFrame=board.CFrame*CFrame.Angles(0,math.pi,0)
	for unit=1,2 do
		part(m,"RoofVent",Vector3.new(5,.7,4),Vector3.new(x-8+(unit-1)*15,15.9,-152),dark)
		for slat=1,4 do part(m,"VentSlat",Vector3.new(.35,.15,3.5),Vector3.new(x-10+(unit-1)*15+slat*.8,16.3,-152),stone) end
	end
	part(m,"EntryPath",Vector3.new(38,.25,9),Vector3.new(x,.85,-126),Color3.fromRGB(163,172,152))
	for planter=1,2 do
		local px=x-15+(planter-1)*30
		part(m,"Planter",Vector3.new(3,1.4,3),Vector3.new(px,1.5,-126),Color3.fromRGB(147,112,83))
		part(m,"Foliage",Vector3.new(3.8,2.5,3.8),Vector3.new(px,3.2,-126),Color3.fromRGB(99,135,91))
	end
	for slat=1,6 do part(m,"TimberScreen",Vector3.new(.55,5,.5),Vector3.new(x-17+slat,4,-131),Color3.fromRGB(166,128,88)) end
	local light=part(m,"EntryLight",Vector3.new(4,.25,.3),Vector3.new(x,11,-130),Color3.fromRGB(221,199,151));light.Material=Enum.Material.Neon
	local prompt=Instance.new("ProximityPrompt");prompt.ActionText="Inspect rival";prompt.ObjectText=s.data.company.name;prompt.MaxActivationDistance=10;prompt:SetAttribute("Public",true);prompt:SetAttribute("App","arena");prompt.Parent=board
	for desk=1,3 do
		part(m,"Worktable",Vector3.new(8,.5,4),Vector3.new(x-13+(desk-1)*13,3,-151),Color3.fromRGB(162,125,91))
		part(m,"Screen",Vector3.new(3.6,2.3,.25),Vector3.new(x-13+(desk-1)*13,4.5,-152),dark)
		part(m,"Rack",Vector3.new(3,8,3),Vector3.new(x-13+(desk-1)*13,4.8,-159),dark)
		for blade=1,5 do part(m,"ServerFace",Vector3.new(2.5,.5,.25),Vector3.new(x-13+(desk-1)*13,1.5+blade,-157.3),accent) end
	end
end
function NPC.init()
	if #NPC.sessions>0 then return end
	for i,def in identities do
		local d=Template.new();d.company={name=def.name,logo="N",color="mint",spec="general",reputation=15,foundedAt=os.time()}
		d.money=25000+i*5000;d.gpus={workstation=1};d.data={general={tokens=3e9,quality=.7},code={tokens=1e9,quality=.8}}
		d.empire.office=3 -- stage 3 (Startup Campus): 12 GPU slots, thermal 40 (CORE_SPEC 2.4)
		local stats,overall=ModelMath.computeStats("s500m",def.focus,ModelMath.dataSummary(d.data),"general",1,nil)
		-- NPC band (CORE_SPEC 3.1): start at the s500m stats x NPC_BOOST, never above NPC_CAP per stat; never reads players
		for _,st in ModelConfig.STATS do if st.weight>0 and st.id~="reliability" then stats[st.id]=math.min(NPC.NPC_CAP,math.round(stats[st.id]*NPC.NPC_BOOST*10)/10) end end;overall=ModelMath.overall(stats)
		local id="npc"..tostring(i)
		d.models[id]={id=id,name=({"Morrow Code","Fern One","Kiln Logic"})[i],version=1,sizeId="s500m",focusId=def.focus,status="live",createdAt=os.time(),trainedAt=os.time(),stats=stats,overall=overall,trainCost=0,dataUsed=ModelMath.dataSummary(d.data),release={subPrice=10,apiPrice=1.5,marketing=0,target="general",releasedAt=os.time()},market=MarketMath.newMarketState("general",0)}
		d.modelOrder={id};d.stats.bestOverall=overall
		local s={userId=def.id,data=d,player={Name=def.name},closed=false,live={revenue=0,cost=0,users=0,perModel={},npcUsers={}},rgb=def.color,focus=def.focus,index=i,iteration=0,pending=nil,activity="Opened the lab",isNPC=true}
		Economy.spend(s,900)
		s.portfolio={id="npc-site-"..tostring(i),name=def.name,kind="website",style=({"paper","slate","brick"})[i],status="published",quality=StudioMath.quality(stats,{stat="coding"}),content=StudioMath.content(def.name,"website",nil),modelName=d.models[id].name,providerId=s.userId}
		table.insert(NPC.sessions,s);office(s,i);note(s,"Opened a self-funded lab")
	end
end
function NPC.tick(dt: number)
	elapsed+=dt
	for _, s in NPC.sessions do
		local d=s.data;local m=d.models[d.modelOrder[1]]
		local pending=s.pending
		if pending then
			pending.remaining-=dt*ModelMath.fleet(d.gpus).throughput
			if pending.remaining<=0 then
				for _,stat in ModelConfig.STATS do
					if stat.weight>0 and stat.id~="reliability" then m.stats[stat.id]=math.min(NPC.NPC_CAP,m.stats[stat.id]+(2+6*pending.quality)/math.sqrt(1+s.iteration)) end
				end
				m.overall=ModelMath.overall(m.stats);m.version+=1;m.iterations=(m.iterations or 0)+1;s.iteration+=1;s.pending=nil;d.training=nil
				d.stats.bestOverall=m.overall;note(s,"Released "..m.name.." v"..tostring(m.version).." · "..tostring(m.overall).." pts")
			end
		end
		local label=signs[s.userId]
		if label then label.Text=d.company.name.."\n"..string.format("%.1f intelligence pts  /  %s",m.overall,s.activity) end
	end
	if elapsed<45 then return end
	elapsed=0
	for _,s in NPC.sessions do
		local d=s.data;local m=d.models[d.modelOrder[1]]
		if s.pending then continue end
		local fleet=ModelMath.fleet(d.gpus)
		local desired=if fleet.throughput<12 then Hardware.getGPU("accelerator") else Hardware.getGPU("datacenter")
		if Hardware.thermal(d.empire,fleet.throughput)<.8 and d.empire.infrastructure.cooling<8 and d.money>12000 then
			if Economy.spend(s,8000) then d.empire.infrastructure.cooling+=1;note(s,"Invested in cooling for sustained compute") end
		elseif desired and d.money>desired.price*1.5 and fleet.slotsUsed<Hardware.slots(d.empire) then
			if Economy.spend(s,desired.price) then d.gpus[desired.id]=(d.gpus[desired.id] or 0)+1;note(s,"Bought "..desired.label.." from its operating budget") end
		elseif d.money>6000+(s.iteration*700) then
			local cost=math.floor(2500+s.iteration*900)
			if Economy.spend(s,cost) then
				ModelMath.addTokens(d.data,"code",8e8,.72+.02*math.min(s.iteration,8))
				d.training={npc=true}
				s.pending={remaining=140+s.iteration*60,quality=ModelMath.dataSummary(d.data).quality}
				note(s,"Training a new checkpoint with fresh data")
			end
		elseif not s.portfolio and d.money>1600 then
			Economy.spend(s,900)
			s.portfolio={id="npc-site-"..tostring(s.index),name=d.company.name,kind="website",style=({"paper","slate","brick"})[s.index],status="published",quality=StudioMath.quality(m.stats,{stat="coding"}),content=StudioMath.content(d.company.name,"website",nil),modelName=m.name,providerId=s.userId}
			note(s,"Built its own company website")
		else
			m.release.apiPrice=math.max(NPC.API_FLOOR,m.release.apiPrice-.1)
			note(s,"Adjusted API price to attract customers")
		end
	end
end
return NPC
