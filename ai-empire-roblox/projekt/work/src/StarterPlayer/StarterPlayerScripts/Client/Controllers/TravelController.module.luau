--!strict
-- World travel on the client (everything here is local; the server never receives per-frame data):
--   * Check-in counters (prompt CityAction="checkin", FlightTo): while the scheduled Port Meridian shuttle
--     runs (ReplicatedStorage.Shuttle, Enabled) the counter sells a boarding pass and ShuttleController takes
--     over (gate, boarding prompt CityAction="board", the visible ride with two pilots, arrival); air traffic
--     and the VIP helicopter are AirTrafficController's. Fallback when the shuttle is off: fade to black,
--     TravelAction {action="flight"}; while the server streams the arrival hall and moves the character, a
--     short client-only cutscene plays (a plane over a client-side sea and clouds, camera following it), then
--     the screen fades back in at the arrival hall.
--   * GPS guide: TravelController.guide(destinationId) fetches a CityPlan route from the server
--     (TravelAction {action="route"}) and draws it - glowing dashes along the road and a beacon with the
--     distance at the destination - until the player arrives or clear() is called. Notify "TRAVEL_GUIDE"
--     {to=id} (CityService.guide) lets server systems such as appointments start one.
--   * Info kiosks (prompt CityAction="navigate", To) and a compact GPS panel while driving the own car.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local ProximityPromptService=game:GetService("ProximityPromptService")
local CityPlan=require(ReplicatedStorage.Shared.Config.CityPlan)
local Format=require(ReplicatedStorage.Shared.Format)
local Aircraft=require(ReplicatedStorage.Shared.AircraftModel)
local State=require(script.Parent.StateController)
local Shuttle=require(script.Parent.ShuttleController)
local AirTraffic=require(script.Parent.AirTrafficController)
local Action=require(script.Parent.ActionController)
local Toast=require(script.Parent.Parent.UI.Toast)
local Theme=require(script.Parent.Parent.UI.Theme)
local Kit=require(script.Parent.Parent.UI.Kit)
local Travel={}
local player=Players.LocalPlayer
local MESSAGES: {[string]: string}={
	NO_MONEY="You need "..Format.money(CityPlan.TRAVEL.ticket).." for the return ticket to Port Meridian.",
	NOT_AT_CHECKIN="Walk up to a check-in counter first.",
	LEAVE_VEHICLE="Leave your car before checking in.",
	BUSY="Your flight is already boarding.",
	ALREADY_ABROAD="You are already abroad. Check in at Port Meridian Airport to fly home.",
	NOT_ABROAD="You are already at home.",
	CANCELLED="The flight was cancelled - your ticket was refunded.",
	FLIGHT_REQUIRED="That place is abroad: fly from City Airport (south of Business City) to get there.",
	OFF_MAP="No road leads there from here.",
	NO_ROUTE="No road leads there from here.",
	LOADING="Still loading - try again in a moment.",
	RATE_LIMIT="Slow down a little.",
}
local function message(err: any): string
	if typeof(err)=="string" and MESSAGES[err] then return MESSAGES[err] end
	return Action.message(if typeof(err)=="string" then err else nil)
end
local function rootPart(): BasePart?
	local character=player.Character
	local root=if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

------------------------------------------------------------------------------------------------ overlay
local overlay: ScreenGui?=nil
local shade: Frame?=nil
local caption: TextLabel?=nil
local function ensureOverlay(): (Frame,TextLabel)
	local s,c=shade,caption
	if overlay and overlay.Parent and s and c then return s,c end
	local gui=Instance.new("ScreenGui");gui.Name="TravelOverlay";gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=90
	local f=Instance.new("Frame");f.Size=UDim2.fromScale(1,1);f.BackgroundColor3=Color3.new(0,0,0);f.BackgroundTransparency=1;f.BorderSizePixel=0;f.Parent=gui
	local t=Instance.new("TextLabel");t.AnchorPoint=Vector2.new(.5,1);t.Position=UDim2.new(.5,0,1,-48);t.Size=UDim2.fromOffset(640,44)
	t.BackgroundTransparency=1;t.TextColor3=Theme.colors.text;t.Font=Theme.font.bold;t.TextSize=26;t.Text="";t.TextTransparency=1;t.Parent=gui
	gui.Parent=player:WaitForChild("PlayerGui")
	overlay,shade,caption=gui,f,t
	return f,t
end
local function fade(target: number,seconds: number)
	local f=ensureOverlay()
	local tween=TweenService:Create(f,TweenInfo.new(seconds,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{BackgroundTransparency=target})
	tween:Play();task.wait(seconds)
end
local function say(text: string)
	local _,t=ensureOverlay();t.Text=text;t.TextTransparency=if text=="" then 1 else 0
end

------------------------------------------------------------------------------------------------ cutscene
-- A client-only scene high above the empty sea between home and Port Meridian (nothing streams there):
-- a sea plane, a few clouds and the aircraft, which flies forward while the camera circles it.
Travel.SCENE_ORIGIN=CFrame.new(0,2600,5600)
function Travel.buildScene(): (Model,Model)
	local scene=Instance.new("Model");scene.Name="FlightCutscene"
	local o=Travel.SCENE_ORIGIN
	local function deco(name: string,size: Vector3,cf: CFrame,color: Color3,shape: Enum.PartType?,transparency: number?): Part
		local p=Instance.new("Part");p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
		p.Size=size;p.CFrame=cf;p.Color=color;p.Material=Enum.Material.SmoothPlastic;p.Transparency=transparency or 0
		if shape then p.Shape=shape end
		p.Parent=scene;return p
	end
	deco("Sea",Vector3.new(2048,1,2048),o*CFrame.new(0,-420,-900),Color3.fromRGB(70,118,150))
	local rng=Random.new(20261003) -- the same clouds on every flight
	for _=1,22 do
		local d=rng:NextNumber(30,70)
		deco("Cloud",Vector3.new(d,d,d),o*CFrame.new(rng:NextNumber(-260,260),rng:NextNumber(-140,-30),-rng:NextNumber(0,2000)),Color3.fromRGB(245,246,248),Enum.PartType.Ball,.15)
	end
	local plane=Aircraft.build(scene,o,{scale=1.6,livery=Theme.accent,name="CutscenePlane"}) -- company colour livery
	return scene,plane
end
local function cutscene(seconds: number)
	local camera=workspace.CurrentCamera
	if not camera then task.wait(seconds);return end
	local scene,plane=Travel.buildScene()
	scene.Parent=workspace
	camera.CameraType=Enum.CameraType.Scriptable
	local o=Travel.SCENE_ORIGIN
	local t0=os.clock()
	local connection=RunService.RenderStepped:Connect(function()
		local t=math.clamp((os.clock()-t0)/seconds,0,1)
		local pcf=o*CFrame.new(0,math.sin(t*math.pi*2)*6,-t*1500)*CFrame.Angles(0,0,math.sin(t*5)*.06)
		plane:PivotTo(pcf)
		local a=1.9+t*1.6 -- the camera swings from the left wing round behind the tail
		local eye=pcf.Position+Vector3.new(math.cos(a)*150,40-t*18,math.sin(a)*150+40)
		camera.CFrame=CFrame.lookAt(eye,pcf.Position)
	end)
	task.wait(seconds)
	connection:Disconnect()
	scene:Destroy()
	camera.CameraType=Enum.CameraType.Custom -- the normal player camera, following the character again
	local character=player.Character
	local humanoid=if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then camera.CameraSubject=humanoid end
end
local flying=false
function Travel.fly(to: string)
	if flying or (to~="abroad" and to~="home") then return end
	flying=true
	Travel.clear()
	fade(0,.6)
	say("Checking in…")
	local ok,res=Action.call("TravelAction",{action="flight",to=to},true)
	if not ok then
		say("");fade(1,.5);flying=false
		Toast.show("error",message(res.err))
		return
	end
	local seconds=if typeof(res.seconds)=="number" then math.clamp(res.seconds,3,20) else CityPlan.TRAVEL.flightSeconds
	say("Flight to "..tostring(res.destination or "Port Meridian"))
	task.spawn(fade,1,.8)
	cutscene(seconds-.6)
	fade(0,.4)
	say("")
	task.wait(.2)
	fade(1,.8)
	flying=false
	if to=="abroad" then
		Toast.show("success","Welcome to Port Meridian. Your return flight is included - check in at the counters to fly home.",6)
	else
		Toast.show("success","Welcome back! Your car waits in the airport car park west of the terminal.",6)
	end
end

------------------------------------------------------------------------------------------------ GPS guide
local guideFolder: Folder?=nil
local guideTarget: Vector3?=nil
local guideName=""
local guideLabel: TextLabel?=nil
local guideSerial=0
function Travel.clear()
	guideSerial+=1
	if guideFolder then guideFolder:Destroy() end
	guideFolder=nil;guideTarget=nil;guideLabel=nil
end
function Travel.active(): boolean return guideFolder~=nil end
-- Draws a route (points from CityPlan.route). Segments inside a campus plot (garage, ramp) are skipped.
function Travel.draw(points: {Vector3},name: string)
	Travel.clear()
	if #points<2 then return end
	local folder=Instance.new("Folder");folder.Name="TravelGuide"
	local color=Theme.accent
	local function dash(cf: CFrame)
		local p=Instance.new("Part");p.Name="GuideDash";p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
		p.Size=Vector3.new(1.4,.12,6);p.CFrame=cf;p.Color=color;p.Material=Enum.Material.Neon;p.Transparency=.15;p.Parent=folder
	end
	local y=CityPlan.GROUND+.8
	local count=0
	for i=1,#points-1 do
		local a,b=points[i],points[i+1]
		if CityPlan.plotAt(a) or CityPlan.plotAt(b) then continue end
		local from,to=Vector3.new(a.X,y,a.Z),Vector3.new(b.X,y,b.Z)
		local len=(to-from).Magnitude
		if len<1 then continue end
		local dir=(to-from)/len
		local s=6
		while s<len and count<600 do
			local p=from+dir*s
			dash(CFrame.lookAt(p,p+dir))
			s+=16;count+=1
		end
	end
	local target=points[#points]
	local beacon=Instance.new("Part");beacon.Name="GuideBeacon";beacon.Anchored=true;beacon.CanCollide=false;beacon.CanTouch=false;beacon.CanQuery=false;beacon.CastShadow=false
	beacon.Shape=Enum.PartType.Cylinder;beacon.Size=Vector3.new(80,3,3);beacon.CFrame=CFrame.new(target.X,CityPlan.GROUND+40,target.Z)*CFrame.Angles(0,0,math.pi/2)
	beacon.Color=color;beacon.Material=Enum.Material.Neon;beacon.Transparency=.35;beacon.Parent=folder
	local gui=Instance.new("BillboardGui");gui.Name="GuideLabel";gui.Size=UDim2.fromOffset(260,52);gui.AlwaysOnTop=true;gui.StudsOffsetWorldSpace=Vector3.new(0,46,0);gui.Adornee=beacon;gui.Parent=beacon
	local label=Instance.new("TextLabel");label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.TextColor3=Color3.new(1,1,1);label.TextStrokeTransparency=.4
	label.Font=Theme.font.bold;label.TextScaled=true;label.Text=name;label.Parent=gui
	folder.Parent=workspace
	guideFolder,guideTarget,guideName,guideLabel=folder,target,name,label
end
-- Fetch a route for a destination id (CityPlan.DESTINATIONS or "home") and draw it.
function Travel.guide(id: string)
	task.spawn(function()
		local token=guideSerial
		local ok,res=Action.call("TravelAction",{action="route",to=id},true)
		if token~=guideSerial then return end -- cleared, replaced or a flight started meanwhile
		if not ok then Toast.show("error",message(res.err));return end
		if typeof(res.points)~="table" then return end
		local points: {Vector3}={}
		for _,p in res.points do if typeof(p)=="Vector3" then table.insert(points,p) end end
		local name=if typeof(res.name)=="string" then res.name else "Destination"
		Travel.draw(points,name)
		Toast.show("info","Route to "..name.." · "..Format.int(tonumber(res.length) or 0).." studs. Follow the glowing line.",5)
	end)
end
local function watchArrival()
	while true do
		task.wait(.5)
		local target=guideTarget;local root=rootPart()
		if target and root then
			local d=CityPlan.flat(root.Position,target)
			local label=guideLabel
			if label then label.Text=guideName.."\n"..Format.int(d).." studs" end
			if d<=CityPlan.TRAVEL.arriveRadius then
				local name=guideName
				Travel.clear()
				Toast.show("success","You have arrived at "..name..".",4)
			end
		end
	end
end

------------------------------------------------------------------------------------------------ GPS panel
local panel: ScreenGui?=nil
local function closePanel() if panel then panel:Destroy();panel=nil end end
local function driving(): boolean
	local character=player.Character
	local humanoid=if character then character:FindFirstChildOfClass("Humanoid") else nil
	local seat=if humanoid then humanoid.SeatPart else nil
	return seat~=nil and seat:IsA("VehicleSeat") and seat.Parent~=nil and seat.Parent:GetAttribute("OwnerUserId")==player.UserId
end
local function openPanel()
	closePanel()
	local gui=Instance.new("ScreenGui");gui.Name="TravelGPS";gui.ResetOnSpawn=false;gui.DisplayOrder=30;gui.Parent=player:WaitForChild("PlayerGui");panel=gui
	local box=Kit.frame(gui,UDim2.fromOffset(250,44),UDim2.new(0,16,.5,-120));box.BackgroundColor3=Theme.colors.panel;box.BackgroundTransparency=.08;Kit.corner(box,10);Kit.stroke(box,.85)
	local toggle=Kit.button(box,"GPS · choose a destination","secondary",UDim2.new(1,-12,0,32));toggle.Position=UDim2.fromOffset(6,6)
	local list: ScrollingFrame?=nil
	Kit.onClick(toggle,function()
		if list then list:Destroy();list=nil;box.Size=UDim2.fromOffset(250,44);return end
		box.Size=UDim2.fromOffset(250,330)
		local scroll=Kit.scroll(box,UDim2.new(1,-12,1,-50),UDim2.fromOffset(6,44));list=scroll
		Kit.list(scroll,4)
		local entries: {{string}}={{"home","My HQ"}}
		if Travel.active() then table.insert(entries,1,{"","Clear route"}) end
		for _,d in CityPlan.DESTINATION_LIST do
			if d.zone~="abroad" and (d.kind~="landmark" or d.zone=="downtown") then table.insert(entries,{d.id,d.name}) end
		end
		for i,e in entries do
			local b=Kit.button(scroll,e[2],if e[1]=="" then "ghost" else "secondary",UDim2.new(1,-8,0,30));b.LayoutOrder=i;b.TextSize=14
			Kit.onClick(b,function()
				if e[1]=="" then Travel.clear() else Travel.guide(e[1]) end
				if list then list:Destroy();list=nil;box.Size=UDim2.fromOffset(250,44) end
			end)
		end
	end)
end
local function watchDriving()
	while true do
		task.wait(.5)
		local d=driving()
		if d and not panel then openPanel() elseif not d and panel then closePanel() end
	end
end

------------------------------------------------------------------------------------------------ init
function Travel.init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt,who: Player)
		if who~=player then return end
		local action=prompt:GetAttribute("CityAction")
		if action=="checkin" then
			local to=prompt:GetAttribute("FlightTo")
			if typeof(to)=="string" then
				if Shuttle.active() then ensureOverlay();task.spawn(Shuttle.checkIn,to) else task.spawn(Travel.fly,to) end
			end
		elseif action=="board" then
			task.spawn(Shuttle.board)
		elseif action=="navigate" then
			local to=prompt:GetAttribute("To")
			if typeof(to)=="string" then Travel.guide(to) end
		end
	end)
	State.onNotify(function(kind,payload)
		if kind=="TRAVEL_GUIDE" and typeof(payload.to)=="string" then Travel.guide(payload.to) end
	end)
	-- a flight or a respawn ends any guide
	player:GetAttributeChangedSignal("TravelState"):Connect(function() if player:GetAttribute("TravelState")~=nil then Travel.clear() end end)
	player.CharacterAdded:Connect(function() Travel.clear() end)
	task.spawn(watchArrival)
	task.spawn(watchDriving)
	Shuttle.init()
	AirTraffic.init()
end
return Travel
