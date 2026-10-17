--!strict
-- AirTrafficController (package "flight", client only; required and initialised by TravelController).
--   * Ambient air traffic at City Airport, deterministic from server time (FlightPlan.ambient): a visiting
--     airliner lands east, taxis to remote stand R2 on the east apron, stands there, pushes back and takes off
--     west (one model per visit, so nothing pops in or out near the airport: a visit fades in and out only far
--     out in the air); airliners cross the sky high above the city. Placed in each timetable cycle where the
--     shuttle does not use the runway. Cheap: only events near the camera are built (full LOD within
--     FULL_RANGE of the camera, medium beyond, low in the sky), at most a few at a time, one BulkMoveTo per
--     moving aircraft per frame (none while it is parked).
--   * VIP helicopter in Port Meridian: parked on the airport helipad ("Helipad", Purpose VIPAirport), flies
--     transfers to the Meridian Grand roof pad when the server publishes one (ReplicatedStorage.Shuttle
--     HeliStart / HeliMode / HeliRider; pads HeliFromPad / HeliToPad), rotor spinning. Local prompts on the
--     airport pad and in the hotel lobby call TravelAction {action="heli"}; the rider gets a chase camera.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local ProximityPromptService=game:GetService("ProximityPromptService")
local CityPlan=require(ReplicatedStorage.Shared.Config.CityPlan)
local FP=require(ReplicatedStorage.Shared.FlightPlan)
local Aircraft=require(ReplicatedStorage.Shared.AircraftModel)
local Format=require(ReplicatedStorage.Shared.Format)
local Mover=require(script.Parent.AircraftMover)
local Action=require(script.Parent.ActionController)
local Toast=require(script.Parent.Parent.UI.Toast)
local Theme=require(script.Parent.Parent.UI.Theme)
local Traffic={}
local player=Players.LocalPlayer
Traffic.RANGE=6500 -- ambient aircraft are built when the camera is this close (sky crossings: 9,000)
Traffic.FULL_RANGE=600 -- runway traffic switches to the full model this close to the camera (back beyond 700)
Traffic.HELI_RANGE=2500
local rgb=Color3.fromRGB
-- generic liveries (no real airlines): body, tail/engine colour, title
type Livery={body: Color3,livery: Color3,airline: string?,kind: string}
local LIVERIES: {Livery}={
	{body=rgb(240,241,238),livery=rgb(28,78,160),airline="AI Empire Air",kind="320"},
	{body=rgb(240,241,238),livery=rgb(24,120,128),airline="Meridian Air",kind="320"},
	{body=rgb(236,236,232),livery=rgb(170,58,52),airline=nil,kind="320"},
	{body=rgb(232,234,236),livery=rgb(56,112,74),airline=nil,kind="320"},
	{body=rgb(240,241,238),livery=rgb(24,120,128),airline="Meridian Air",kind="380"},
}
local MESSAGES: {[string]: string}={
	HELI_UNAVAILABLE="The VIP helicopter is not available right now.",
	HELI_ABROAD_ONLY="The VIP helicopter flies in Port Meridian.",
	NOT_AT_HELIPAD="Walk onto the VIP helipad at Port Meridian Airport (or into the Meridian Grand lobby) first.",
	BUSY="You are already travelling.",
	LEAVE_VEHICLE="Leave your car first.",
	LOADING="Still loading - try again in a moment.",
}

------------------------------------------------------------------------------------------------ state
local folder: Folder?=nil
local client: Folder?=nil
type Live={model: Model,mover: Mover.Mover,fade: number,fan: number,lod: string,livery: number,sky: boolean,last: CFrame?}
local live: {[string]: Live}={}
local cycleEvents: {[number]: {FP.AmbientEvent}}={}
local function ensureFolder(): Folder
	local c=client
	if c and c.Parent then return c end
	local f=Instance.new("Folder");f.Name="AirTraffic";f.Parent=workspace
	client=f
	return f
end
local function events(cycle: number): {FP.AmbientEvent}
	local e=cycleEvents[cycle]
	if not e then
		e=FP.ambient(cycle)
		cycleEvents[cycle]=e
		for k in cycleEvents do if k<cycle-2 or k>cycle+2 then cycleEvents[k]=nil end end
	end
	return e
end
local function setFade(l: Live,f: number)
	if math.abs(l.fade-f)<0.04 then return end
	l.fade=f
	for _,p in l.mover.parts do p.LocalTransparencyModifier=f end
end
local function drop(id: string)
	local l=live[id]
	if l then l.model:Destroy();live[id]=nil end
end
function Traffic.liveCount(): number
	local n=0
	for _ in live do n+=1 end
	return n
end

------------------------------------------------------------------------------------------------ ambient
local function stepAmbient(t: number,dt: number,camPos: Vector3)
	local I=FP.interval()
	local cycle=math.floor((t-FP.CONFIG.epoch)/I)
	local seen: {[string]: boolean}={}
	for k=cycle-2,cycle do
		for _,e in events(k) do
			local pose=FP.ambientPose(e,t)
			if not pose then continue end
			local sky=e.kind=="sky"
			local dist=(pose.cf.Position-camPos).Magnitude
			local range=if sky then 9000 else Traffic.RANGE
			if dist>range then continue end
			local key=e.visit or e.id
			if seen[key] then continue end -- the hand-over instant between two phases of one visit
			seen[key]=true
			local l: Live?=live[key]
			-- distance LOD of runway traffic (with hysteresis); sky crossings stay low
			local want=if sky then e.lod elseif dist<Traffic.FULL_RANGE then "full" elseif dist>Traffic.FULL_RANGE+100 then "medium" elseif l then l.lod else "medium"
			if l and l.lod~=want then l.model:Destroy();live[key]=nil;l=nil end
			if not l then
				local lv=LIVERIES[e.livery] or LIVERIES[1]
				local m=Aircraft.build(nil,pose.cf,{kind=if sky then lv.kind else "320",scale=if lv.kind=="380" and sky then 1.4 else FP.CONFIG.scale,
					lod=want,livery=lv.livery,body=lv.body,airline=lv.airline,name="TrafficAircraft",collide=false,mesh=false})
				m.Parent=ensureFolder()
				l={model=m,mover=Mover.new(m,pose.cf),fade=0,fan=0,lod=want,livery=e.livery,sky=sky,last=nil}
				live[key]=l
			end
			local cur=l :: Live
			local tau=t-e.t0
			local fadeIn=if e.fadeIn then math.clamp(tau/3,0,1) else 1
			local fadeOut=if e.fadeOut then math.clamp((e.duration-tau)/3,0,1) else 1
			setFade(cur,1-math.min(fadeIn,fadeOut))
			if pose.engines or cur.last~=pose.cf then
				if pose.engines then cur.fan=(cur.fan+dt*22)%(math.pi*2) end
				Mover.move(cur.mover,pose.cf,cur.fan)
				cur.last=pose.cf
			end
			Mover.setGear(cur.mover,pose.gearDown)
		end
	end
	for id in live do if not seen[id] then drop(id) end end
end

------------------------------------------------------------------------------------------------ helicopter
type Heli={model: Model,mover: Mover.Mover,main: number,tail: number}
local heli: Heli?=nil
local heliPrompt: ProximityPrompt?=nil
local lobbyPart: Part?=nil
local rideCam=false
local heliInfo: ScreenGui?=nil
local function pads(): (Vector3?,Vector3?)
	local f=folder
	if not f then return nil,nil end
	local a=f:GetAttribute("HeliFromPad");local b=f:GetAttribute("HeliToPad")
	return if typeof(a)=="Vector3" then a else nil,if typeof(b)=="Vector3" then b else nil
end
-- Frame of the helicopter now: on the airport pad, or flying the published transfer.
function Traffic.heliFrame(t: number): (CFrame?,number,boolean)
	local a,b=pads()
	if not a or not b then return nil,0,false end
	local f=folder :: Folder
	local start=f:GetAttribute("HeliStart");local mode=f:GetAttribute("HeliMode")
	if typeof(start)=="number" and typeof(mode)=="string" then
		local _,_,free=FP.heliTimes(mode,start,a,b)
		if t>=start and t<free then return FP.heliAt(mode,start,t,a,b) end
	end
	local dir=Vector3.new(b.X-a.X,0,b.Z-a.Z)
	return CFrame.lookAt(a,a+(if dir.Magnitude>1 then dir.Unit else Vector3.new(0,0,1))),0,false
end
local nextPadSearch=0
local function ensurePrompts(a: Vector3?,t: number)
	-- airport pad: a local prompt on the marker part (re-added when the part streams back in; searched at most
	-- every 3 s while it is missing)
	if (not heliPrompt or not heliPrompt.Parent) and a and t>=nextPadSearch then
		nextPadSearch=t+3
		heliPrompt=nil
		-- MetroBuilder: WorldCity/PortMeridian/.../VipHelipad/Helipad (a few dozen parts, not the whole world)
		local world=workspace:FindFirstChild("WorldCity")
		local pm=if world then world:FindFirstChild("PortMeridian") else nil
		local group=if pm then pm:FindFirstChild("VipHelipad",true) else nil
		local pad: BasePart?=nil
		if group then
			for _,d in group:GetDescendants() do
				if d:IsA("BasePart") and d.Name=="Helipad" and d:GetAttribute("Purpose")=="VIPAirport" then pad=d;break end
			end
		end
		if pad then
			local q=Instance.new("ProximityPrompt");q.Name="HeliPrompt";q.ActionText="VIP helicopter";q.ObjectText="To the Meridian Grand Hotel"
			q.MaxActivationDistance=28;q.HoldDuration=0.5;q.RequiresLineOfSight=false
			q:SetAttribute("CityAction","heli");q:SetAttribute("HeliTo","hotel");q:SetAttribute("Public",true);q.Parent=pad
			heliPrompt=q
		end
	end
	-- hotel lobby: a local invisible part with the return prompt
	if not lobbyPart or not lobbyPart.Parent then
		local hotel=CityPlan.INTL_HOTEL
		if hotel then
			local p=Instance.new("Part");p.Name="HeliLobbyDesk";p.Size=Vector3.new(1,1,1);p.Transparency=1;p.Anchored=true
			p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false;p.CFrame=hotel.lobby;p.Parent=ensureFolder()
			local q=Instance.new("ProximityPrompt");q.Name="HeliPrompt";q.ActionText="VIP helicopter";q.ObjectText="Rooftop transfer to the airport"
			q.MaxActivationDistance=12;q.HoldDuration=0.5;q.RequiresLineOfSight=false
			q:SetAttribute("CityAction","heli");q:SetAttribute("HeliTo","airport");q:SetAttribute("Public",true);q.Parent=p
			lobbyPart=p
		end
	end
end
local function closeHeliInfo()
	if heliInfo then heliInfo:Destroy();heliInfo=nil end
end
local function stepHeli(t: number,dt: number,camPos: Vector3)
	local f=folder
	if not f or f:GetAttribute("HeliAvailable")~=true then
		if heli then heli.model:Destroy();heli=nil end
		return
	end
	local a=pads()
	local cf,rotor,carrying=Traffic.heliFrame(t)
	local isRider=f:GetAttribute("HeliRider")==player.UserId and player:GetAttribute("TravelState")=="flying"
	if not cf or ((camPos-cf.Position).Magnitude>Traffic.HELI_RANGE and not isRider) then
		if heli then heli.model:Destroy();heli=nil end
	else
		local existing=heli
		local h: Heli
		if existing then h=existing
		else
			local m=Aircraft.buildHelicopter(nil,cf,{livery=rgb(22,28,42),trim=rgb(212,170,72),airline=FP.CONFIG.airline,name="VipHelicopter"})
			m.Parent=ensureFolder()
			h={model=m,mover=Mover.new(m,cf),main=0,tail=0}
			heli=h
		end
		h.main=(h.main+dt*rotor*28)%(math.pi*2)
		h.tail=(h.tail+dt*rotor*60)%(math.pi*2)
		Mover.move(h.mover,cf,nil,h.main,h.tail)
		if isRider then
			local camera=workspace.CurrentCamera
			if camera then
				rideCam=true
				camera.CameraType=Enum.CameraType.Scriptable
				local eye=(cf*CFrame.new(-26,14,46)).Position
				camera.CFrame=CFrame.lookAt(eye,cf.Position+Vector3.new(0,5,0))
			end
			if not heliInfo then
				local pg=player:FindFirstChild("PlayerGui")
				if pg then
					local gui=Instance.new("ScreenGui");gui.Name="HeliRide";gui.ResetOnSpawn=false;gui.DisplayOrder=80
					local box=Instance.new("Frame");box.AnchorPoint=Vector2.new(0.5,0);box.Position=UDim2.new(0.5,0,0,58);box.Size=UDim2.fromOffset(360,54)
					box.BackgroundColor3=Theme.colors.panel;box.BackgroundTransparency=0.08;box.BorderSizePixel=0;box.Parent=gui
					local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,10);c.Parent=box
					local l=Instance.new("TextLabel");l.Name="Text";l.BackgroundTransparency=1;l.Size=UDim2.new(1,-20,1,0);l.Position=UDim2.fromOffset(10,0)
					l.Font=Theme.font.medium;l.TextSize=15;l.TextColor3=Theme.colors.text;l.TextWrapped=true;l.Parent=box
					gui.Parent=pg
					heliInfo=gui
				end
			end
			local gui=heliInfo
			local label=if gui then gui:FindFirstChild("Text",true) else nil
			if label and label:IsA("TextLabel") then
				label.Text=if carrying then "VIP transfer · "..FP.CONFIG.airline.." helicopter" else "Your helicopter is on its way to pick you up"
			end
		end
	end
	if not isRider and rideCam then
		rideCam=false
		closeHeliInfo()
		local camera=workspace.CurrentCamera
		if camera then
			camera.CameraType=Enum.CameraType.Custom
			local character=player.Character
			local hum=if character then character:FindFirstChildOfClass("Humanoid") else nil
			if hum then camera.CameraSubject=hum end
		end
	end
	if (camPos-(a or camPos)).Magnitude<1500 then ensurePrompts(a,t) end
end
local busy=false
function Traffic.heli(to: string)
	if busy then return end
	busy=true
	local ok,res=Action.call("TravelAction",{action="heli",to=to},true)
	busy=false
	if not ok then
		if res.err=="HELI_BUSY" then Toast.show("info","The helicopter is on a transfer - it is free again in "..tostring(res.seconds or "a few").." s.",5)
		elseif res.err=="NO_MONEY" then
			local fee=tonumber(res.price) or (if folder then tonumber(folder:GetAttribute("HeliFee")) else nil) or 0
			Toast.show("error","You need "..Format.money(fee).." for the VIP transfer - or the VIP Limousine pass, which includes it.")
		else Toast.show("error",MESSAGES[tostring(res.err)] or Action.message(tostring(res.err))) end
		return
	end
	local paid=if typeof(res.price)=="number" and res.price>0 then " ("..Format.money(res.price)..")" else " (included with your VIP Limousine pass)"
	Toast.show("success","VIP transfer to "..tostring(res.destination)..paid..". Enjoy the view over Port Meridian!",6)
end

------------------------------------------------------------------------------------------------ init
local function step(dt: number)
	local camera=workspace.CurrentCamera
	if not camera then return end
	local t=workspace:GetServerTimeNow()
	local camPos=camera.CFrame.Position
	stepAmbient(t,dt,camPos)
	stepHeli(t,dt,camPos)
end
Traffic.step=step
function Traffic.init()
	task.spawn(function()
		local f=ReplicatedStorage:WaitForChild("Shuttle",30)
		if f and f:IsA("Folder") then folder=f end
		RunService.RenderStepped:Connect(step)
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt,who: Player)
		if who~=player or prompt:GetAttribute("CityAction")~="heli" then return end
		local to=prompt:GetAttribute("HeliTo")
		if typeof(to)=="string" then task.spawn(Traffic.heli,to) end
	end)
end
return Traffic
