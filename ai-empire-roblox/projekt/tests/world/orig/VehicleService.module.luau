--!strict
-- Physical company cars. Server validates drivers and input; Roblox simulates the assembly.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Prompts=game:GetService("ProximityPromptService")
local Config=require(ReplicatedStorage.Shared.Config.CampusConfig)
local Math=require(ReplicatedStorage.Shared.CampusMath)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Net=require(ReplicatedStorage.Shared.Net)
local CompanyConfig=require(ReplicatedStorage.Shared.Config.CompanyConfig)
local Remote=require(script.Parent.Parent.Lib.Remote)
local Session=require(script.Parent.SessionService)
local Economy=require(script.Parent.EconomyService)
local Plot=require(script.Parent.PlotService)
local Vehicles={cars={} :: {[number]:any}}
-- Anything 12 studs below the B1 garage floor (world Y) fell through the map and is reset.
local FLOOR_LIMIT=Config.STREET_Y+Plan.B1_Y-12
local serial=0
local function add(model: Model,root: BasePart?,cf: CFrame,name: string,size: Vector3,offset: CFrame,color: Color3,collide: boolean?): Part
	local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=cf*offset;p.Color=color;p.Material=Enum.Material.SmoothPlastic;p.Anchored=false;p.CanCollide=collide==true;p.Massless=root~=nil;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=model
	if root then local w=Instance.new("WeldConstraint");w.Part0=root;w.Part1=p;w.Parent=p end
	return p
end
local function clear(userId: number)
	local record=Vehicles.cars[userId];if not record then return end
	if record.seat.Occupant then record.seat.Occupant.Sit=false end
	if record.connection then record.connection:Disconnect() end
	record.model:Destroy();Vehicles.cars[userId]=nil
end
local function build(s: any,def: any,cf: CFrame): any
	serial+=1
	local folder=workspace:FindFirstChild("CompanyVehicles")
	if not folder then folder=Instance.new("Folder");folder.Name="CompanyVehicles";folder.Parent=workspace end
	local m=Instance.new("Model");m.Name="CompanyCar_"..tostring(s.userId);m:SetAttribute("OwnerUserId",s.userId);m:SetAttribute("CarId",tostring(serial));m:SetAttribute("VehicleType",def.id)
	local colorDef=CompanyConfig.getColor(s.data.company.color);local color=if colorDef then Color3.fromRGB(unpack(colorDef.rgb)) else Color3.fromRGB(91,125,100)
	local ink=Color3.fromRGB(35,42,40);local cream=Color3.fromRGB(222,219,199)
	local root=add(m,nil,cf,"Chassis",Vector3.new(def.width,.8,def.length),CFrame.new(),ink,true);root.CustomPhysicalProperties=PhysicalProperties.new(2,.25,.05);m.PrimaryPart=root
	add(m,root,cf,"Body",Vector3.new(def.width,1.5,def.length-.4),CFrame.new(0,.8,0),color)
	add(m,root,cf,"Hood",Vector3.new(def.width-.2,.6,3.5),CFrame.new(0,1.8,-def.length/2+2),color)
	if def.id=="van" then
		add(m,root,cf,"CargoBody",Vector3.new(def.width-.5,3.8,6.8),CFrame.new(0,2.4,3.4),color)
		for _,side in {-1,1} do add(m,root,cf,"CargoDoor",Vector3.new(def.width/2-.4,3,.15),CFrame.new(side*def.width/4,2.4,6.85),cream) end
	elseif def.id=="sport" then
		add(m,root,cf,"RearSpoiler",Vector3.new(def.width+1,.3,1.3),CFrame.new(0,3.05,def.length/2-1),ink)
		for _,side in {-1,1} do add(m,root,cf,"HoodStripe",Vector3.new(.35,.04,3.1),CFrame.new(side*.5,2.12,-def.length/2+2),cream) end
		add(m,root,cf,"Splitter",Vector3.new(def.width+.5,.22,1),CFrame.new(0,.1,-def.length/2-.4),ink)
	elseif def.id=="executive" then
		add(m,root,cf,"FrontTrim",Vector3.new(def.width-.6,.15,.15),CFrame.new(0,1.45,-def.length/2-.13),cream)
	end
	add(m,root,cf,"Roof",Vector3.new(def.width-.8,.45,if def.id=="van" then 9 else 5.8),CFrame.new(0,3.65,if def.id=="van" then 1.8 else .35),color)
	local windshield=add(m,root,cf,"Windshield",Vector3.new(def.width-1.1,2,.15),CFrame.new(0,2.7,-2.7)*CFrame.Angles(math.rad(-18),0,0),Color3.fromRGB(117,153,148));windshield.Transparency=.42;windshield.Material=Enum.Material.Glass
	local back=add(m,root,cf,"BackWindow",Vector3.new(def.width-1.1,1.7,.15),CFrame.new(0,2.7,3.1)*CFrame.Angles(math.rad(12),0,0),windshield.Color);back.Transparency=.4
	for _,side in {-1,1} do
		add(m,root,cf,"RoofPillar",Vector3.new(.28,2.3,.4),CFrame.new(side*(def.width/2-.35),2.7,-2.6),color)
		add(m,root,cf,"RearPillar",Vector3.new(.35,2.3,.5),CFrame.new(side*(def.width/2-.35),2.7,3),color)
		add(m,root,cf,"Mirror",Vector3.new(.8,.5,1),CFrame.new(side*(def.width/2+.35),2,-2.1),color)
		for _,z in {-def.length*.31,def.length*.31} do
			local wheel=add(m,root,cf,"Wheel",Vector3.new(.8,2.8,2.8),CFrame.new(side*(def.width/2+.12),-.8,z),ink,true);wheel.Shape=Enum.PartType.Cylinder;wheel.CustomPhysicalProperties=PhysicalProperties.new(.7,.08,.05)
			local rim=add(m,root,cf,"WheelRim",Vector3.new(.86,1.65,1.65),CFrame.new(side*(def.width/2+.18),-.8,z),cream);rim.Shape=Enum.PartType.Cylinder
		end
		add(m,root,cf,"Headlight",Vector3.new(1.5,.6,.2),CFrame.new(side*(def.width/2-1.2),1,-def.length/2-.02),cream)
		add(m,root,cf,"TailLight",Vector3.new(1.3,.5,.2),CFrame.new(side*(def.width/2-1),1,def.length/2+.02),Color3.fromRGB(164,66,49))
	end
	add(m,root,cf,"Bumper",Vector3.new(def.width-.3,.45,.4),CFrame.new(0,.3,-def.length/2-.25),ink)
	add(m,root,cf,"SeatBack",Vector3.new(2,2,.4),CFrame.new(-1.35,2,.6),ink)
	add(m,root,cf,"PassengerSeat",Vector3.new(2,.5,2),CFrame.new(1.35,1.5,.2),ink)
	local plate=add(m,root,cf,"CompanyPlate",Vector3.new(2.5,.6,.1),CFrame.new(0,.95,-def.length/2-.16),cream)
	local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Front;gui.CanvasSize=Vector2.new(400,100);gui.Parent=plate
	local text=Instance.new("TextLabel");text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1;text.Text=s.data.company.name;text.TextColor3=ink;text.TextScaled=true;text.Font=Enum.Font.BuilderSansBold;text.Parent=gui
	local seat=Instance.new("VehicleSeat");seat.Name="DriverSeat";seat.Size=Vector3.new(2,.5,2);seat.CFrame=cf*CFrame.new(-1.35,1.5,.2);seat.Color=ink;seat.CanCollide=false;seat.Massless=true;seat.Disabled=true;seat.HeadsUpDisplay=true;seat.MaxSpeed=def.speed;seat.Parent=m
	local weld=Instance.new("WeldConstraint");weld.Part0=root;weld.Part1=seat;weld.Parent=seat
	local attachment=Instance.new("Attachment");attachment.Name="DriveAttachment";attachment.Parent=root
	local velocity=Instance.new("LinearVelocity");velocity.Name="DriveVelocity";velocity.Attachment0=attachment;velocity.RelativeTo=Enum.ActuatorRelativeTo.World;velocity.VelocityConstraintMode=Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis=Vector3.new(1,0,0);velocity.SecondaryTangentAxis=Vector3.new(0,0,1);velocity.ForceLimitsEnabled=true;velocity.ForceLimitMode=Enum.ForceLimitMode.PerAxis;velocity.MaxPlanarAxesForce=Vector2.new(24000,24000);velocity.PlaneVelocity=Vector2.new(0,0);velocity.Parent=root
	local alignment=Instance.new("AlignOrientation");alignment.Attachment0=attachment;alignment.Mode=Enum.OrientationAlignmentMode.OneAttachment;alignment.MaxTorque=32000;alignment.Responsiveness=12;alignment.CFrame=cf.Rotation;alignment.Parent=root
	local prompt=Instance.new("ProximityPrompt");prompt.ActionText="Drive";prompt.ObjectText=def.name;prompt.MaxActivationDistance=10;prompt.RequiresLineOfSight=false;prompt:SetAttribute("OwnerUserId",s.userId);prompt:SetAttribute("VehicleAction",true);prompt.Parent=seat
	m.Parent=folder
	local record={model=m,root=root,seat=seat,velocity=velocity,alignment=alignment,definition=def,home=cf,speed=0,throttle=0,steer=0,inputAt=0,checkClock=0,lastPosition=root.Position,lastInput=-1}
	Vehicles.cars[s.userId]=record
	record.connection=seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant=seat.Occupant
		if occupant then
			local driver=Players:GetPlayerFromCharacter(occupant.Parent)
			if driver~=s.player then occupant.Sit=false;return end
			m:SetAttribute("DriverUserId",s.userId);root:SetNetworkOwner(s.player)
		else
			record.throttle=0;record.steer=0;seat.Disabled=true;m:SetAttribute("DriverUserId",nil);root:SetNetworkOwner(nil)
		end
	end)
	root:SetNetworkOwner(nil)
	return record
end
function Vehicles.spawn(s: any,p: any): any
	local id=p.carId or s.data.empire.campus.selectedCar;local def=Config.find(Config.CARS,id)
	if not def then return {ok=false,err="BAD_INPUT"} end
	if not s.data.empire.campus.cars[id] then return {ok=false,err="NOT_OWNED"} end
	local plot=Plot.get(s.player);if not plot or not plot.office then return {ok=false,err="LOADING"} end
	-- GarageSpawn may sit anywhere inside the office (site/garage models); the plan is the fallback.
	local marker=plot.office:FindFirstChild("GarageSpawn",true);local markerCF=if marker then marker:GetAttribute("SpawnCFrame") else nil
	local spawnCF: CFrame=if typeof(markerCF)=="CFrame" then markerCF else plot.cframe*Plan.GARAGE_SPAWN
	local previous=Vehicles.cars[s.userId];if previous and previous.seat.Occupant then return {ok=false,err="CAR_OCCUPIED"} end
	if previous and os.clock()-(previous.spawnedAt or 0)<3 then return {ok=false,err="COOLDOWN"} end
	clear(s.userId);local record=build(s,def,spawnCF);record.spawnedAt=os.clock()
	s.data.empire.campus.selectedCar=id;Session.markDirty(s);return {ok=true}
end
function Vehicles.input(player: Player,id: any,throttle: any,steer: any)
	local record=Vehicles.cars[player.UserId]
	if not record or tostring(id)~=record.model:GetAttribute("CarId") or not Math.finiteUnit(throttle) or not Math.finiteUnit(steer) then return end
	local occupant=record.seat.Occupant
	if not occupant or Players:GetPlayerFromCharacter(occupant.Parent)~=player then return end
	local now=os.clock();if now-record.lastInput<1/30 then return end
	record.lastInput=now;record.inputAt=now;record.throttle=throttle;record.steer=steer
end
function Vehicles.tick(dt: number)
	for userId,record in Vehicles.cars do
		if not record.model.Parent then clear(userId);continue end
		local occupant=record.seat.Occupant
		if not occupant or os.clock()-record.inputAt>.8 then record.throttle=0;record.steer=0 end
		local speed,turn=Math.drive(record.speed,record.throttle,record.steer,math.min(dt,.1),record.definition);record.speed=speed
		local root=record.root;local forward=root.CFrame.LookVector
		local yaw=math.atan2(-forward.X,-forward.Z)+turn*dt
		local heading=Vector3.new(-math.sin(yaw),0,-math.cos(yaw))
		record.velocity.PlaneVelocity=Vector2.new(heading.X*speed,heading.Z*speed)
		local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={record.model,if occupant then occupant.Parent else record.model}
		local ground=workspace:Raycast(root.Position,Vector3.new(0,-9,0),params)
		local up=if ground and ground.Normal.Y>.55 then ground.Normal else Vector3.new(0,1,0)
		record.alignment.CFrame=CFrame.lookAt(root.Position,root.Position+heading,up).Rotation
		record.model:SetAttribute("Speed",math.round(math.abs(speed)));record.model:SetAttribute("Steer",record.steer)
		record.checkClock+=dt
		if record.checkClock>=.5 then
			local position=root.Position;local distance=(position-record.lastPosition).Magnitude
			if position.Y<FLOOR_LIMIT or math.abs(position.X)>1160 or math.abs(position.Z)>800 or distance>record.definition.speed*record.checkClock*1.8+35 or root.AssemblyLinearVelocity.Magnitude>record.definition.speed*2+30 then
				if occupant then occupant.Sit=false end
				record.model:PivotTo(record.home);root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero;record.speed=0
				position=root.Position
			end
			record.lastPosition=position;record.checkClock=0
		end
	end
end
function Vehicles.init()
	Remote.bind("BuyCar",{burst=2,perSecond=.5,company=true},function(s,p)
		local def=Config.find(Config.CARS,p.carId);if not def then return {ok=false,err="BAD_INPUT"} end
		local c=s.data.empire.campus;if c.cars[def.id] then return {ok=false,err="ALREADY_DONE"} end
		if not Economy.spend(s,def.price) then return {ok=false,err="NO_MONEY"} end
		c.cars[def.id]=true;c.selectedCar=def.id;Session.markDirty(s);return {ok=true}
	end)
	Remote.bind("SpawnCar",{burst=2,perSecond=.25,company=true},Vehicles.spawn)
	Net.getEvent("VehicleInput").OnServerEvent:Connect(Vehicles.input)
	Prompts.PromptTriggered:Connect(function(q,player)
		local s=Session.get(player);if not s or s.closed or not s.data.company or not q.Parent then return end
		local character=player.Character;local root=if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not root or not q.Parent:IsA("BasePart") or (root.Position-q.Parent.Position).Magnitude>14 then return end
		if q:GetAttribute("CampusAction")=="spawnCar" and q:GetAttribute("OwnerUserId")==player.UserId then
			local result=Vehicles.spawn(s,{});Remote.fire(player,"Notify","CAMPUS_NOTICE",{text=if result.ok then "Your car is waiting in bay B1 — 14." else "Car collection unavailable: "..tostring(result.err)})
		elseif q:GetAttribute("VehicleAction")==true and q:GetAttribute("OwnerUserId")==player.UserId then
			local record=Vehicles.cars[player.UserId];local humanoid=if character then character:FindFirstChildOfClass("Humanoid") else nil
			if record and q.Parent==record.seat and humanoid and not record.seat.Occupant then record.seat.Disabled=false;record.seat:Sit(humanoid) end
		end
	end)
	Plot.onChanged(function(_plot,s)clear(s.userId)end)
	Session.onClosing(function(s)clear(s.userId)end)
end
return Vehicles
