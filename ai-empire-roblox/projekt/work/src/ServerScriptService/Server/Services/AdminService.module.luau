--!strict
-- The Roblox server supplies Player.Name; a display name or a remote payload grants no rights.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local EmpireConfig=require(ReplicatedStorage.Shared.Config.EmpireConfig)
local HardwareConfig=require(ReplicatedStorage.Shared.Config.HardwareConfig)
local CampusConfig=require(ReplicatedStorage.Shared.Config.CampusConfig)
local DataConfig=require(ReplicatedStorage.Shared.Config.DataConfig)
local ModelMath=require(ReplicatedStorage.Shared.ModelMath)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Remote=require(script.Parent.Parent.Lib.Remote)
local Session=require(script.Parent.SessionService)
local Economy=require(script.Parent.EconomyService)
local Plot=require(script.Parent.PlotService)
local Facility=require(script.Parent.FacilityService)
local AI=require(script.Parent.AIModelService)
local Admin={}
local ACCOUNT="nonortrttrt"
function Admin.allowed(player: Player): boolean
	return string.lower(player.Name)==ACCOUNT
end
local function campus(s: any)
	s.data.empire.office=#EmpireConfig.OFFICES
	s.data.empire.campus.retailLevel=#CampusConfig.RETAIL+1
	Facility.issueCard(s.player,s.userId)
end
local function staff(s: any)
	campus(s)
	local e=s.data.empire;local total=0
	for _,r in EmpireConfig.ROLES do total+=e.employees[r.id] or 0 end
	while total<EmpireConfig.OFFICES[e.office].staff do
		local lowest=EmpireConfig.ROLES[1]
		for _,r in EmpireConfig.ROLES do if (e.employees[r.id] or 0)<(e.employees[lowest.id] or 0) then lowest=r end end
		e.employees[lowest.id]=(e.employees[lowest.id] or 0)+1;total+=1
	end
end
local function research(s: any)
	for _,r in EmpireConfig.RESEARCH do s.data.empire.research[r.id]=true end
	s.data.empire.researchJob=nil
	s.data.empire.points=math.max(s.data.empire.points,10000)
	s.data.empire.infrastructure.cooling=8
end
local function hardware(s: any)
	campus(s);s.data.empire.infrastructure.cooling=8
	local used=0;for _,g in HardwareConfig.GPUS do if not g.starter then used+=s.data.gpus[g.id] or 0 end end
	local count=s.data.gpus.superpod or 0
	s.data.gpus.superpod=count+math.min(math.max(0,2-count),math.max(0,HardwareConfig.slots(s.data.empire)-used))
end
local function fleet(s: any)
	for _,car in CampusConfig.CARS do s.data.empire.campus.cars[car.id]=true end
end
local function data(s: any)
	for _,d in DataConfig.TYPES do ModelMath.addTokens(s.data.data,d.id,1e10,.9) end
end
-- Read-only diagnostics -------------------------------------------------------------------
-- Optional services are required lazily so a missing or failing module only removes its section.
local function inspect(name: string,office: Model): (any,string?)
	local ok,result=pcall(function(): any
		local m=script.Parent:FindFirstChild(name)
		if not m or not m:IsA("ModuleScript") then return nil end
		local svc=(require :: any)(m)
		return if typeof(svc)=="table" and typeof(svc.inspect)=="function" then svc.inspect(office) else nil
	end)
	if not ok then return nil,tostring(result) end
	return result,nil
end
local function count(t: any): number
	if typeof(t)=="number" then return t end
	if typeof(t)~="table" then return 0 end
	local n=0;for _ in t do n+=1 end;return n
end
local function list(t: any): string
	if typeof(t)~="table" or next(t)==nil then return "—" end
	local out={};for _,v in t do table.insert(out,tostring(v)) end;return table.concat(out,",")
end
local function roomReport(office: Model,tier: number,lines: {string})
	local perLevel,planned={},{}
	for _,r in Plan.rooms(tier) do perLevel[r.level]=(perLevel[r.level] or 0)+1;planned[r.id]=true end
	local parts={}
	for _,level in Plan.levels(tier) do table.insert(parts,Plan.levelLabel(tier,level).." "..(perLevel[level] or 0)) end
	table.insert(lines,"Rooms (Plan): "..table.concat(parts," · "))
	local folder=office:FindFirstChild("Rooms");local built,missing=0,{}
	if folder then for _,m in folder:GetChildren() do if planned[m.Name] then built+=1 end end end
	for _,r in Plan.rooms(tier) do if not folder or not folder:FindFirstChild(r.id) then table.insert(missing,r.id) end end
	table.insert(lines,string.format("Rooms built: %d / %d%s",built,count(planned),if #missing>0 then " · missing "..table.concat(missing,",",1,math.min(#missing,10))..(if #missing>10 then ",…" else "") else ""))
end
local function workstationReport(office: Model,lines: {string})
	local w,err=inspect("WorkstationService",office)
	if typeof(w)~="table" then table.insert(lines,"Workstations: unavailable"..(if err then " ("..err..")" else ""));return end
	table.insert(lines,string.format("Workstations: %s total · %s reserved · %s occupied · %s seated players",tostring(w.total or "?"),tostring(w.reserved or "?"),tostring(w.occupied or "?"),tostring(w.playerSeated or 0)))
	if typeof(w.byType)=="table" then
		local parts={}
		for kind,t in w.byType do if typeof(t)=="table" then table.insert(parts,string.format("%s %d/%d/%d",tostring(kind),t.total or 0,t.reserved or 0,t.occupied or 0)) end end
		table.sort(parts);if #parts>0 then table.insert(lines,"  by type (total/reserved/occupied): "..table.concat(parts," · ")) end
	end
end
-- StaffService.inspect rows: {name, index, role, state, task, station, home, lod, navIssue, navStage,
-- liftTicketState}.
local function staffReport(office: Model,lines: {string})
	local report,err=inspect("StaffService",office)
	if typeof(report)~="table" then table.insert(lines,"Employees: unavailable"..(if err then " ("..err..")" else ""));return end
	local total,issues,tickets,sleeping=0,0,0,0
	local detail={}
	for _,r in report do
		if typeof(r)~="table" then continue end
		total+=1
		if r.lod=="sleep" then sleeping+=1 end
		local issue=r.navIssue;local ticket=r.liftTicketState
		if issue~=nil and issue~="" and issue~=false then issues+=1 else issue=nil end
		if ticket~=nil then tickets+=1 end
		if (issue or ticket) and #detail<12 then
			table.insert(detail,string.format("  #%s %s (%s) %s%s%s%s",tostring(r.index or "?"),tostring(r.name or "?"),tostring(r.role or "?"),tostring(r.state or ""),
				if r.navStage then " · "..tostring(r.navStage) else "",if issue then " · nav: "..tostring(issue) else "",if ticket then " · lift "..tostring(ticket) else ""))
		end
	end
	table.insert(lines,string.format("Employees: %d simulated (%d asleep, far from players) · %d nav issues · %d lift tickets",total,sleeping,issues,tickets))
	for _,line in detail do table.insert(lines,line) end
end
local function liftReport(office: Model,tier: number,lines: {string})
	local r,err=inspect("LiftService",office)
	if typeof(r)~="table" then table.insert(lines,"Lift: unavailable"..(if err then " ("..err..")" else ""));return end
	if r.attached==false then table.insert(lines,if r.none then "Lift: none in this building (garage stage)" else "Lift: not attached"..(if r.failed then " (attach failed)" else ""));return end
	local q=if typeof(r.queue)=="table" then r.queue else {}
	local states={};if typeof(r.ticketStates)=="table" then for k,v in r.ticketStates do table.insert(states,tostring(k).." "..tostring(v)) end;table.sort(states) end
	table.insert(lines,string.format("Lift: %s at %s%s · door %s · riders %s/%s%s · hall %s · car %s · tickets %s%s%s",
		tostring(r.state or "?"),if typeof(r.level)=="number" then Plan.levelLabel(tier,r.level) else "?",if typeof(r.target)=="number" then " → "..Plan.levelLabel(tier,r.target) else "",
		tostring(r.door or "?"),tostring(r.riders or 0),tostring(r.capacity or "?"),if r.full then " FULL" else "",list(q.hall),list(q.car),tostring(r.tickets or 0),
		if #states>0 then " ("..table.concat(states,", ")..")" else "",if r.reason then " · reason "..tostring(r.reason) else ""))
end
local function doorReport(office: Model,tier: number,lines: {string})
	local r,err=inspect("DoorService",office)
	if typeof(r)~="table" then table.insert(lines,"Doors: unavailable"..(if err then " ("..err..")" else ""));return end
	-- Compute Operations (G_COMPUTE) and the Data Hall (B1_DATAHALL) are both compute-class rooms.
	local computeRooms={};for _,room in Plan.rooms(tier) do if room.kind=="compute" or room.kind=="datahall" then table.insert(computeRooms,room.name) end end
	local total,locked,odd,compute={},0,{},{}
	for _,d in r do
		if typeof(d)~="table" then continue end
		table.insert(total,d)
		if d.state=="locked" then locked+=1 end
		if d.state~="closed" and d.state~="locked" and #odd<16 then table.insert(odd,string.format("%s %s",tostring(d.id),tostring(d.state))) end
		if d.access=="compute" then table.insert(compute,string.format("%s %s",tostring(d.id),tostring(d.state))) end
	end
	table.insert(lines,string.format("Doors: %d registered · %d locked · not closed: %s",#total,locked,if #odd>0 then table.concat(odd,", ") else "none"))
	table.insert(lines,string.format("  compute doors (%s): %s",table.concat(computeRooms," + "),if #compute>0 then table.concat(compute,", ") else "none registered"))
end
local function cameraReport(office: Model,lines: {string})
	local total,private,levels=0,0,{}
	for _,p in office:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("CameraId")~=nil then
			total+=1;if p:GetAttribute("Private")==true then private+=1 end
			local level=p:GetAttribute("Level");if typeof(level)=="number" then levels[level]=(levels[level] or 0)+1 end
		end
	end
	table.insert(lines,string.format("Cameras: %d channels · %d private · on %d levels",total,private,count(levels)))
end
-- Compact text report about one headquarters; never changes anything.
function Admin.diagnostics(office: Model,tier: number): string
	local def=EmpireConfig.OFFICES[Plan.officeForTier(tier)]
	local name=if def then def.name elseif tier<1 then "Garage stage" else "?"
	local shape=if tier<1 then "1 storey, no B1, no lift" else string.format("%d storeys + B1 + roof",Plan.floors(tier))
	local lines={string.format("HQ diagnostics · plan tier %d (%s) · %s%s",tier,name,shape,if Plan.hasHotel(tier) then " · guest house" else "")}
	for _,section in {
		function() roomReport(office,tier,lines) end,
		function() workstationReport(office,lines) end,
		function() staffReport(office,lines) end,
		function() liftReport(office,tier,lines) end,
		function() doorReport(office,tier,lines) end,
		function() cameraReport(office,lines) end,
	} do
		local ok,err=pcall(section :: () -> any);if not ok then table.insert(lines,"(section failed: "..tostring(err)..")") end
	end
	return table.concat(lines,"\n")
end
-- Testing only: changes the admin's OWN saved office tier (and trims staff to the new desk count,
-- exactly like loading a save would). Plot.refresh then rebuilds the headquarters.
local function trimStaff(s: any,cap: number)
	local e=s.data.empire;local remaining=cap
	for _,role in EmpireConfig.ROLES do
		local n=math.min(e.employees[role.id] or 0,remaining);e.employees[role.id]=n;remaining-=n
	end
end
local function setTier(s: any,tier: number)
	s.data.empire.office=tier
	trimStaff(s,EmpireConfig.OFFICES[tier].staff)
end
-- "tierN" builds plan tier N (0 = garage stage, 1..4 = the HQ buildings): an alias of "stage(N+1)" through
-- Plan.officeForTier (OFFICE_TIER_OFFSET = 1 since DATA_VERSION 6). A plan tier that an office
-- index maps to (Plan.officeForTier) is set through the save as before; one that no office maps to yet
-- (the garage stage before the save migration) is a session-only override (session.planTier, never
-- saved) that HeadquartersDesign.tierFor reads. Returns false when the rebuild did not happen.
local function setPlanTier(s: any,tier: number): boolean
	local office=Plan.officeForTier(tier)
	if EmpireConfig.OFFICES[office] then
		s.planTier=nil
		setTier(s,office)
		return true
	end
	s.planTier=tier
	trimStaff(s,if tier<1 then Plan.GARAGE_STAGE.staff else EmpireConfig.OFFICES[s.data.empire.office].staff)
	return true
end
local function run(s: any,p: any): any
	if s.userId~=s.player.UserId or not Admin.allowed(s.player) then return {ok=false,err="ADMIN_ONLY"} end
	local cmd=p.cmd
	if cmd=="diag" then
		local plot=Plot.get(s.player)
		if not plot or not plot.office then return {ok=false,err="LOADING"} end
		print(`[Admin] {s.player.Name} ({s.userId}): diag`)
		local built=plot.office:GetAttribute("OfficeTier")
		return {ok=true,cmd=cmd,report=Admin.diagnostics(plot.office,if typeof(built)=="number" then built else Plan.tierForOffice(s.data.empire.office))}
	end
	-- "stageN" sets the office index (1 = Garage Lab .. 5 = Global AI HQ, CORE_SPEC 2.4); the building follows
	local stage=if typeof(cmd)=="string" then tonumber(string.match(cmd,"^stage(%d)$")) else nil
	if stage and EmpireConfig.OFFICES[stage] then
		s.planTier=nil
		setTier(s,stage)
		Plot.refresh(s);Session.markDirty(s)
		print(`[Admin] {s.player.Name} ({s.userId}): {cmd}`)
		return {ok=true,cmd=cmd}
	end
	local tier=if typeof(cmd)=="string" then tonumber(string.match(cmd,"^tier(%d)$")) else nil
	if tier and tier>=Plan.MIN_TIER and tier<=Plan.MAX_TIER then
		local e=s.data.empire
		local before={office=e.office,employees=table.clone(e.employees),planTier=s.planTier}
		setPlanTier(s,tier)
		Plot.refresh(s);Session.markDirty(s)
		local plot=Plot.get(s.player)
		local built=if plot and plot.office then plot.office:GetAttribute("OfficeTier") else nil
		if built~=tier then
			-- the plot did not rebuild (a PlotService that compares the saved office index never rebuilds
			-- for a session-only plan tier): undo everything, the save keeps its staff
			s.planTier=before.planTier;e.office=before.office;e.employees=before.employees
			Plot.refresh(s);Session.markDirty(s)
			return {ok=false,err="TIER_NOT_BUILT"}
		end
		print(`[Admin] {s.player.Name} ({s.userId}): {cmd}`)
		return {ok=true,cmd=cmd}
	elseif cmd=="campus" then campus(s)
	elseif cmd=="staff" then staff(s)
	elseif cmd=="hardware" then hardware(s)
	elseif cmd=="research" then research(s)
	elseif cmd=="fleet" then fleet(s)
	elseif cmd=="money" then Economy.grant(s,1000000,"admin")
	elseif cmd=="data" then data(s)
	elseif cmd=="finish" then if not AI.finishNow(s) then return {ok=false,err="NO_TRAINING"} end
	elseif cmd=="setup" then campus(s);staff(s);research(s);hardware(s);fleet(s);data(s);Economy.grant(s,1000000,"admin")
	else return {ok=false,err="BAD_INPUT"} end
	Plot.refresh(s);Session.markDirty(s)
	print(`[Admin] {s.player.Name} ({s.userId}): {cmd}`)
	return {ok=true,cmd=cmd}
end
function Admin.init()
	Remote.bind("AdminAction",{burst=3,perSecond=.5},run)
	Session.onLoaded(function(s)
		s.live.admin=Admin.allowed(s.player);Session.markDirty(s)
	end)
end
return Admin
