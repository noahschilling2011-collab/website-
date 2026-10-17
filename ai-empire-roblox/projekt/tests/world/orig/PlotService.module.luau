--!strict
-- Twelve campus plots with enough space for roads, shop streets and basement ramps.
-- Owns the office lifecycle: build → DoorService.register → LiftService.attach, and the reverse
-- (detach → unregister → destroy) on rebuilds and when the founder leaves.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local Lighting=game:GetService("Lighting")
local Config=require(ReplicatedStorage.Shared.Config.CampusConfig)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local CompanyConfig=require(ReplicatedStorage.Shared.Config.CompanyConfig)
local EmpireConfig=require(ReplicatedStorage.Shared.Config.EmpireConfig)
local HardwareConfig=require(ReplicatedStorage.Shared.Config.HardwareConfig)
local SessionService=require(script.Parent.SessionService)
local Design=require(script.Parent.HeadquartersDesign)
local Doors=require(script.Parent.DoorService)
local Lift=require(script.Parent.LiftService) -- LiftService must never require PlotService (cycle)
local Plot={}
local plots: {any}={}
local changed: {(any,any)->()}={}
local function accent(session: any): Color3
	local company=session.data.company
	local def=if company then CompanyConfig.getColor(company.color) else nil
	return if def then Color3.fromRGB(def.rgb[1],def.rgb[2],def.rgb[3]) else Color3.fromRGB(120,154,129)
end
function Plot.get(player: Player): any
	for _,p in plots do if p.owner==player then return p end end
	return nil
end
function Plot.all(): {any} return plots end
function Plot.onChanged(fn: (any,any)->()) table.insert(changed,fn) end
-- Front plaza in front of the entrance canopy, facing the building (world CFrame).
function Plot.arrival(p: any): CFrame
	local at=Plan.ARRIVAL
	return p.cframe*CFrame.lookAt(at,Vector3.new(at.X,at.Y,Plan.ENTRANCE.z))
end
local function announce(p: any,session: any)
	for _,fn in changed do fn(p,session) end
end
local function sendHome(player: Player,p: any)
	local character=player.Character;if not character then return end
	local root=character:WaitForChild("HumanoidRootPart",5);if not root then return end
	if p.owner~=player or not character.Parent then return end
	character:PivotTo(Plot.arrival(p))
end
local function rootOf(player: Player): BasePart?
	local character=player.Character
	local root=if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end
-- Players standing in the building volume of `tier` (plot-local). Drivers stay in their cars: the
-- garage footprint (Plan.GARAGE) is identical for every tier.
local function occupants(p: any,tier: number,except: Player?): {Player}
	local out={}
	for _,player in Players:GetPlayers() do
		local root=rootOf(player);local character=player.Character
		local h=if character then character:FindFirstChildOfClass("Humanoid") else nil
		local seat=if h then h.SeatPart else nil
		if player~=except and root and not (seat and seat:IsA("VehicleSeat")) and Plan.inside(tier,p.cframe:PointToObjectSpace(root.Position)) then
			table.insert(out,player)
		end
	end
	return out
end
local function evacuate(p: any,list: {Player})
	for _,player in list do
		local character=player.Character;local h=if character then character:FindFirstChildOfClass("Humanoid") else nil
		if character and character.Parent then
			if h then local seat=h.SeatPart;local weld=if seat then seat:FindFirstChild("SeatWeld") else nil;if weld then weld:Destroy() end;h.Sit=false end
			character:PivotTo(Plot.arrival(p))
		end
	end
end
local function connect(office: Model)
	Doors.register(office);Lift.attach(office)
end
local function disconnect(office: Model)
	Lift.detach(office);Doors.unregister(office)
end
local function setText(gui: Instance?,text: string)
	local label=if gui then gui:FindFirstChildWhichIsA("TextLabel",true) else nil
	if label then (label :: TextLabel).Text=text end
end
function Plot.refresh(session: any)
	local p=Plot.get(session.player);local office=if p then p.office else nil;if not office then return end
	local tier=session.data.empire.office
	if office:GetAttribute("OfficeTier")~=tier then
		local oldTier=office:GetAttribute("OfficeTier")
		disconnect(office)
		-- Documented safety exception: visitors inside the old building would be left standing in
		-- the air after the rebuild, so they are moved to the plaza. The founder keeps sendHome.
		local inside=if typeof(oldTier)=="number" then occupants(p,oldTier,session.player) else {}
		office:Destroy();office=Design.build(p.cframe,session,accent(session));office.Parent=p.model;p.office=office
		connect(office)
		evacuate(p,inside)
		announce(p,session);task.spawn(sendHome,session.player,p)
	end
	local staffKey=""
	for _,role in EmpireConfig.ROLES do staffKey..=role.id..tostring(session.data.empire.employees[role.id] or 0) end
	if office:GetAttribute("StaffKey")~=staffKey then Design.staff(office,p.cframe,session) end
	office:SetAttribute("CoolingLevel",session.data.empire.infrastructure.cooling)
	local anchor=office:FindFirstChild("SignAnchor",true);local sign=if anchor then anchor:FindFirstChild("Sign") else nil
	local title=if sign then sign:FindFirstChild("Label") else nil
	local name=if session.data.company then session.data.company.name.."\n"..EmpireConfig.OFFICES[tier].name else session.player.DisplayName.."'s Headquarters"
	if title and title:IsA("TextLabel") then title.Text=name else setText(sign,name) end
	if session.data.company then
		local company: string=session.data.company.name
		local boards: {[string]:string}={ReceptionSign="WELCOME TO\n"..company,KitchenBrand=company.."\nSNACK CLUB",CompanyStele=company}
		for boardName,text in boards do
			local board=office:FindFirstChild(boardName,true);local gui=if board then board:FindFirstChildWhichIsA("SurfaceGui",true) else nil
			setText(gui,text)
		end
	end
	local colors: {Color3}={}
	for i=#HardwareConfig.GPUS,1,-1 do
		local gpu=HardwareConfig.GPUS[i]
		if not gpu.starter then for _=1,session.data.gpus[gpu.id] or 0 do table.insert(colors,accent(session)) end end
	end
	local blades=office:FindFirstChild("Blades")
	if blades then for i,blade in blades:GetChildren() do
		if blade:IsA("BasePart") then local lit=i<=#colors;blade:SetAttribute("Lit",lit);blade.Color=if lit then colors[i] else Color3.fromRGB(39,46,43) end
	end end
	office:SetAttribute("Training",session.data.training~=nil)
end
local function vacantPad(p: any)
	local s=Plan.SITE
	local pad=Instance.new("Part");pad.Name="VacantPad";pad.Size=Vector3.new(s.x2-s.x1,24,s.z2-s.z1)
	pad.CFrame=p.cframe*CFrame.new((s.x1+s.x2)/2,-12,(s.z1+s.z2)/2);pad.Color=Color3.fromRGB(140,154,127);pad.Material=Enum.Material.Grass;pad.Anchored=true;pad.Parent=p.model
end
function Plot.claim(session: any)
	if Plot.get(session.player) then return end
	local p=nil;for _,candidate in plots do if not candidate.owner then p=candidate;break end end
	if not p then warn("[Campus] No free plot. Set Max Players to 12.");return end
	local vacant=p.model:FindFirstChild("VacantPad");if vacant then vacant:Destroy() end
	p.owner=session.player;p.office=Design.build(p.cframe,session,accent(session));p.office.Parent=p.model
	connect(p.office)
	Plot.refresh(session);announce(p,session)
	p.characterConn=session.player.CharacterAdded:Connect(function()task.delay(.25,sendHome,session.player,p)end)
	task.delay(.25,sendHome,session.player,p)
end
function Plot.release(player: Player)
	local p=Plot.get(player);if not p then return end
	if p.characterConn then p.characterConn:Disconnect() end
	-- Same safety exception as a rebuild: visitors still inside (e.g. in B1, which the vacant pad
	-- fills) are moved to the plaza once the building is gone.
	local tier=if p.office then p.office:GetAttribute("OfficeTier") else nil
	local inside=if typeof(tier)=="number" then occupants(p,tier,player) else {}
	if p.office then disconnect(p.office);p.office:Destroy() end
	p.owner=nil;p.office=nil;p.characterConn=nil
	vacantPad(p)
	evacuate(p,inside)
end
function Plot.init()
	-- Warm stone under Future lighting; EnvironmentDiffuse/SpecularScale live in the place file and
	-- StaffService drives ClockTime from the campus day (15.8 is only the value before its first tick).
	Lighting.ClockTime=15.8;Lighting.Brightness=2.2;Lighting.Ambient=Color3.fromRGB(88,92,96);Lighting.OutdoorAmbient=Color3.fromRGB(128,134,138)
	local old=workspace:FindFirstChild("Plots");if old then old:Destroy() end
	local folder=Instance.new("Folder");folder.Name="Plots";folder.Parent=workspace
	for i=1,Config.PLOT_COUNT do
		local row=if i<=6 then -1 else 1;local x=((i-1)%6-2.5)*Config.PITCH
		local center=Vector3.new(x,Config.STREET_Y,row*Config.ROW_OFFSET)
		local cf=CFrame.lookAt(center,Vector3.new(x,Config.STREET_Y,0))
		local model=Instance.new("Model");model.Name=string.format("Plot_%02d",i);model.Parent=folder
		model:SetAttribute("CampusCFrame",cf);model:SetAttribute("PlotIndex",i)
		local p={index=i,cframe=cf,model=model}
		vacantPad(p)
		table.insert(plots,p)
	end
	SessionService.onLoaded(Plot.claim);SessionService.onClosing(function(s)Plot.release(s.player)end)
end
return Plot
