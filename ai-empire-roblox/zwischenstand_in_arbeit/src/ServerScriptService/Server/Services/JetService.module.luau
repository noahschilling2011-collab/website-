--!strict
-- JetService (package "guests_jet"): the company jet in Hangar 1 of City Airport, its two company pilots, the
-- founder's private flights to Port Meridian and back, and the field staff's abroad trips (CompanyOps tripList).
-- Required + init() by Main.server after PhoneService.init; tick(dt) runs in the campus loop (0.05-0.25 s).
--
-- STABLE API (for the itinerary package; also documented in agents/guests_jet/API.md):
--   JetService.available(player) -> (ok: boolean, reason: string?, info: {at, slot, eta?, purpose?, staff?})
--       reason: "NO_SESSION" | "NO_JET" | "JET_BUSY" (flying a trip - the founder's, field staff, or on its way to
--       pick staff up; info.eta = seconds until it is free, info.purpose = "founder" | "staff" | "position",
--       info.staff = names aboard) | "JET_ABROAD" / "JET_AT_HOME" (the jet waits at the other airport) |
--       "JET_RETURNING" (flying home empty) | "BUSY" (the founder is on a flight) | "LOADING" | "PM_STANDS_FULL"
--       (both Port Meridian jet stands taken by other companies); info.at = "home" | "abroad" = where the jet is.
--   JetService.fly(player, {to = "abroad" | "home", companions = {{name: string, role: string?, seed: number?}}?,
--       onArrive = function(flightId: string, destination: string)?, pay = boolean?}) -> {ok, flightId, departAt,
--       arriveAt, doneAt, delay, slot, to, destination, fuel, err, eta}. Departure: the next slot clear of the
--       shuttle, the ambient airliners and the other company jets (JetPlan.schedule, <= JetPlan.CONFIG.maxDelay s of
--       extra boarding; none -> err "RUNWAY_BUSY", eta = seconds until the next clear slot). departAt = taxi /
--       pushback start, arriveAt = when the founder is placed at the destination (JetPlan.arrivalSpots: Port
--       Meridian by the VIP limousine stand / City Airport arrivals; the first spot nobody stands on). pay = true
--       charges the fuel of one leg (JetService.FUEL_LEG = CompanyOps.JET.fuel / 2, P&L line "jet"; the owner
--       prompt passes it; err "NO_MONEY"). Field staff waiting for the jet board the founder's flight (up to 3
--       travellers in all). Errors as available() plus "BAD_INPUT", "ALREADY_ABROAD", "NOT_ABROAD",
--       "LEAVE_VEHICLE", "RUNWAY_BUSY", "NO_MONEY". The founder is held (anchored, hidden, below the departure field;
--       the Player attribute JetFlight = flightId tells the client to show the ride) and is a CityService trip with
--       state "flying" (PlotService away check, respawn / leave reset like the shuttle).
--   JetService.onArrive(fn: (player, flightId, destination) -> ()) -> disconnect(): after the founder was placed.
--   JetService.summon(player) -> {ok, flightId, arriveAt, slot, err}: the jet flies empty from Hangar 1 to Port
--       Meridian for the founder who is there ("the jet picks you up"); then fly(player, {to = "home"}).
--       err "RUNWAY_BUSY" (+ eta) when no clear slot exists within JetPlan.CONFIG.maxDelayEmpty.
--   JetService.status(player) -> {owned, at, slot, flying, flightId, kind, purpose, phase, departAt, arriveAt, doneAt}
-- Money: the jet's running cost (2 pilots + upkeep) and the B2B jet trips' fuel are CompanyOps' (Ops.JET); the only
-- money moved here is the fuel of a founder leg flown with pay = true. Nothing is saved.
--
-- Field staff (LOGIC_BRIEF 23c): while empire.jet is true ShuttleService leaves the company's abroad B2B trips to
-- the jet (ShuttleService.abroadTrips returns none), so JetService flies exactly those travellers (the same rule:
-- the k-th field rep for the k-th rep trip, the engineers CompanyOps.presence marks as travelling): a trip that
-- starts -> the jet flies them to Port Meridian (no rider, they are the companions) and comes back by itself; a trip
-- that ends -> the jet flies out to fetch them (if it is at home) and brings them back. The founder has priority:
-- with the founder abroad and the jet waiting for him, staff work waits STAFF_WAIT s (notice) before the jet goes.
--
-- What is published (ReplicatedStorage.CompanyJets/Jet_<userId>, written on change only, never per frame):
--   attributes Owner, Company, Livery, At ("home" | "abroad"), Slot, FlightId, FlightKind ("out" | "back" |
--   "ferry"), FlightPurpose ("founder" | "staff" | "position" | "ferry"), FlightSlot, FlightDelay, FlightStart
--   (server time), Companions; children Crew (Captain / FirstOfficer pilot rig templates, EmployeeRigDesign role
--   "pilot", fixed names per company) and Companions (rig templates of the current trip). The folder exists iff
--   empire.jet == true (CompanyOps pays the two pilots exactly then); after the founder leaves the game mid-flight it
--   stays until that flight has ended. Clients (JetController) show the jet parked (home: only the local company's
--   own jet in the shared hangar; Port Meridian: everyone sees it on its stand) or flying (everyone near it).
--   Owner-only ProximityPrompts (OwnerUserId, WorldController shows them to the owner) at the parked jet's
--   airstair: "Fly to Port Meridian" in the hangar, "Fly home" at the Port Meridian stand.
-- Empty / staff flights (ferry, positioning, field staff) also depart only into a clear slot (JetPlan.schedule within
-- CONFIG.maxDelayEmpty); otherwise they wait and are tried again after RETRY s.
-- Auto ferry: a jet parked in Port Meridian whose founder really left (home, on a flight home, left the game - a VIP
-- helicopter transfer inside Port Meridian does not count) flies home after JetPlan.CONFIG.autoFerry seconds.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Prompts=game:GetService("ProximityPromptService")
local CityPlan=require(ReplicatedStorage.Shared.Config.CityPlan)
local CompanyConfig=require(ReplicatedStorage.Shared.Config.CompanyConfig)
local Ops=require(ReplicatedStorage.Shared.CompanyOps)
local JP=require(ReplicatedStorage.Shared.JetPlan)
local CampusMath=require(ReplicatedStorage.Shared.CampusMath)
local Remote=require(script.Parent.Parent.Lib.Remote)
local Session=require(script.Parent.SessionService)
local Economy=require(script.Parent.EconomyService)
local City=require(script.Parent.CityService)
local Rig=require(script.Parent.EmployeeRigDesign)

local JetService={}
JetService.PILOTS={9201,9241} -- CampusMath.staffName indices with the owner's userId: the same pair on every server
JetService.MAX_COMPANIONS=3
JetService.PROMPT_COOLDOWN=1.5
JetService.SCAN=1 -- seconds between ownership / field-trip scans (jet bought, company renamed, trips started / ended)
JetService.ARRIVE_AFTER=4 -- seconds into the deboarding when the founder is placed at the destination (airstair down)
JetService.FUEL_LEG=math.floor(Ops.JET.fuel/2+0.5) -- one leg of the founder's own round trip (CompanyOps: fuel per abroad trip)
JetService.STAFF_FRESH=60 -- a field trip seen within this many company seconds of its start still flies out visibly
JetService.STAFF_WAIT=120 -- seconds staff work waits while the founder is abroad with the jet
JetService.SPOT_FREE=2.5 -- an arrival spot is taken when another character stands within this many studs
JetService.RETRY=10 -- seconds before an empty / staff flight that found no clear slot (JetPlan.schedule) is tried again
JetService.FIELD_WAIT_MAX=240 -- at most this long a staff flight out waits for the company car bringing the travellers

type Person={name: string,role: string,seed: number?}
type StaffTrip={key: string,people: {Person},state: string,flight: string?,ended: boolean,readyAt: number}
type Flight={id: string,kind: string,purpose: string,slot: number,delay: number,start: number,tl: JP.Timeline,rider: Player?,trip: any?,
	moved: boolean,arrived: boolean,onArrive: ((string,string)->())?,companions: number,staff: {string},names: {string}}
type Jet={userId: number,player: Player,session: any,folder: Folder,at: string,slot: number,flight: Flight?,seq: number,
	awaySince: number?,company: string,livery: Color3,prompt: Part?,promptKey: string,staff: {[string]: StaffTrip},
	staffWaitSince: number?,staffNotified: boolean,leaving: boolean,retryAt: number?}
local jets: {[number]: Jet}={}
JetService.jets=jets
local root: Folder?=nil
local promptFolder: Folder?=nil
local arriveFns: {(Player,string,string)->()}={}
local promptAt: {[number]: number}={}
local scanAcc=0
local loadedWithout: {[number]: boolean}={} -- sessions loaded without a jet: announce a purchase once

local function now(): number return workspace:GetServerTimeNow() end
local function setAttr(inst: Instance,name: string,value: any)
	if inst:GetAttribute(name)~=value then inst:SetAttribute(name,value) end
end
local function notice(player: Player?,text: string)
	if not player or not player.Parent then return end
	pcall(function() Remote.fire(player,"Notify","CAMPUS_NOTICE",{text=text}) end)
end
local function rootOf(player: Player): (Model?,BasePart?,Humanoid?)
	local character=player.Character
	local r=if character then character:FindFirstChild("HumanoidRootPart") else nil
	local h=if character then character:FindFirstChildOfClass("Humanoid") else nil
	if character and r and r:IsA("BasePart") then return character,r,h end
	return nil,nil,nil
end
local function companyOf(s: any): (string,Color3)
	local c=if s and typeof(s.data)=="table" then s.data.company else nil
	local name=if typeof(c)=="table" and typeof(c.name)=="string" and c.name~="" then c.name else "Company"
	local def=if typeof(c)=="table" and typeof(c.color)=="string" then CompanyConfig.getColor(c.color) else nil
	local livery=if def then Color3.fromRGB(def.rgb[1],def.rgb[2],def.rgb[3]) else Color3.fromRGB(24,120,128)
	return name,livery
end
local function owns(s: any): boolean
	return s~=nil and typeof(s.data)=="table" and typeof(s.data.empire)=="table" and s.data.empire.jet==true
end
local function namesText(list: {string}): string
	if #list==0 then return "" end
	if #list==1 then return list[1] end
	return table.concat(list,", ",1,#list-1).." and "..list[#list]
end
local function captainOf(j: Jet): string return "Captain "..CampusMath.staffName(JetService.PILOTS[1],j.userId) end

------------------------------------------------------------------------------------------------ rigs
-- NPC rig template (no tag, no talk prompt, not in workspace = no physics): pilots and companions.
local function template(parent: Instance,temp: Instance,owner: number,index: number,role: string,profile: any,name: string,badge: string): Model?
	local ok,res=pcall(function(): Model
		local m=Rig.build(temp,owner,index,role,CFrame.new(),profile)
		m:RemoveTag("CompanyEmployee")
		-- the clients pose the clones through the Motor6Ds (JetController.cloneRig): no Humanoid / Animator replicated
		local hum=m:FindFirstChildOfClass("Humanoid")
		if hum then hum:Destroy() end
		for _,d in m:GetDescendants() do
			if d:IsA("ProximityPrompt") then d:Destroy()
			elseif d:IsA("BasePart") then d.Anchored=d.Name=="HumanoidRootPart";d.CanCollide=false;d.CanTouch=false;d.CanQuery=false
			elseif d:IsA("TextLabel") and d.Parent and d.Parent.Name=="EmployeeBadge" then d.Text=badge end
		end
		m.Name=name
		m.Parent=parent
		return m
	end)
	if not ok then warn("[Jet] building a rig failed: "..tostring(res));return nil end
	return res
end
local function buildCrew(j: Jet)
	local old=j.folder:FindFirstChild("Crew")
	if old then old:Destroy() end
	local crew=Instance.new("Folder");crew.Name="Crew"
	local temp=Instance.new("Folder")
	for i,key in {"Captain","FirstOfficer"} do
		local index=JetService.PILOTS[i]
		local name=CampusMath.staffName(index,j.userId)
		local title=if i==1 then "Captain" else "First Officer"
		local m=template(crew,temp,j.userId,index,"pilot",{n=name},key,title.." "..name.."\n"..j.company.." flight crew")
		if m then m:SetAttribute("CrewRole",title);m:SetAttribute("PilotName",name);m:SetAttribute("Role","Pilot") end
	end
	temp:Destroy()
	crew.Parent=j.folder
end
local function validPerson(c: any): Person?
	if typeof(c)~="table" or typeof(c.name)~="string" or c.name=="" or #c.name>40 then return nil end
	local role=if typeof(c.role)=="string" and (c.role=="researcher" or c.role=="engineer" or c.role=="curator" or c.role=="marketer") then c.role else "marketer"
	local seed: number?=nil
	if typeof(c.seed)=="number" and c.seed==c.seed and math.abs(c.seed)<1e12 then seed=math.floor(math.abs(c.seed))%2147483647 end
	return {name=c.name,role=role,seed=seed}
end
-- the companion rig templates of a flight (people already validated, <= MAX_COMPANIONS)
local function buildCompanions(j: Jet,people: {Person}): number
	local old=j.folder:FindFirstChild("Companions")
	if old then old:Destroy() end
	local f=Instance.new("Folder");f.Name="Companions"
	local n=0
	if #people>0 then
		local temp=Instance.new("Folder")
		for _,c in people do
			if n>=JetService.MAX_COMPANIONS then break end
			local profile: {[string]: any}={n=c.name}
			if c.seed then profile.s=c.seed end
			n+=1
			local m=template(f,temp,j.userId,760+n,c.role,profile,"Companion"..n,c.name.."\n"..j.company)
			if m then m:SetAttribute("CompanionName",c.name) else n-=1 end
		end
		temp:Destroy()
	end
	f.Parent=j.folder
	return n
end

------------------------------------------------------------------------------------------------ prompts
local function promptCFrame(j: Jet): CFrame
	local park=if j.at=="abroad" then JP.slot(j.slot).cf else JP.HOME_PARK
	local z=JP.POINTS.doorL1.Position.Z
	return park*CFrame.new(-7.2,3,z)
end
-- One owner-only prompt at the parked jet's airstair; re-created whenever the jet parks somewhere else (a fresh
-- instance, so WorldController evaluates OwnerUserId on DescendantAdded; Enabled is never toggled server-side).
local function refreshPrompt(j: Jet)
	local fl=j.flight
	local key=if j.leaving or (fl and workspace:GetServerTimeNow()<fl.start+fl.tl.duration) then "" else j.at..":"..j.slot
	if key==j.promptKey and (key=="" or (j.prompt and j.prompt.Parent)) then return end
	j.promptKey=key
	if j.prompt then j.prompt:Destroy();j.prompt=nil end
	if key=="" or not promptFolder then return end
	local p=Instance.new("Part");p.Name="JetPrompt_"..j.userId;p.Size=Vector3.new(1,1,1);p.Transparency=1;p.Anchored=true
	p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.CFrame=promptCFrame(j)
	local q=Instance.new("ProximityPrompt");q.Name="JetPrompt"
	q.ActionText=if j.at=="abroad" then "Fly home" else "Fly to Port Meridian"
	q.ObjectText=j.company.." · company jet";q.HoldDuration=0.5;q.MaxActivationDistance=12;q.RequiresLineOfSight=false
	q:SetAttribute("OwnerUserId",j.userId);q:SetAttribute("JetAction","fly");q.Parent=p
	p.Parent=promptFolder
	j.prompt=p
end

------------------------------------------------------------------------------------------------ publish
local function publish(j: Jet)
	local f=j.folder
	setAttr(f,"Owner",j.userId);setAttr(f,"Company",j.company);setAttr(f,"Livery",j.livery)
	local fl=j.flight
	if fl then
		-- flight data first, FlightId last (clients key on it)
		setAttr(f,"FlightKind",fl.kind);setAttr(f,"FlightPurpose",fl.purpose);setAttr(f,"FlightSlot",fl.slot);setAttr(f,"FlightDelay",fl.delay)
		setAttr(f,"FlightStart",fl.start);setAttr(f,"Companions",fl.companions);setAttr(f,"FlightId",fl.id)
	end
	setAttr(f,"At",j.at);setAttr(f,"Slot",j.slot)
end
-- the jet record of a session (a rejoin while the previous session's jet is still flying takes it over)
local function ensureJet(s: any): Jet?
	local player: Player?=s.player
	if not player or not root then return nil end
	local existing=jets[player.UserId]
	if existing then
		if existing.session~=s then existing.session=s;existing.player=player;existing.leaving=false;existing.promptKey="-" end
		return existing
	end
	local company,livery=companyOf(s)
	local f=Instance.new("Folder");f.Name="Jet_"..player.UserId
	local j: Jet={userId=player.UserId,player=player,session=s,folder=f,at="home",slot=1,flight=nil,seq=0,awaySince=nil,
		company=company,livery=livery,prompt=nil,promptKey="-",staff={},staffWaitSince=nil,staffNotified=false,leaving=false,retryAt=nil}
	jets[player.UserId]=j
	buildCrew(j)
	publish(j)
	f.Parent=root
	refreshPrompt(j)
	return j
end
local function dropJet(userId: number)
	local j=jets[userId]
	if not j then return end
	jets[userId]=nil
	if j.prompt then j.prompt:Destroy() end
	j.folder:Destroy()
end

------------------------------------------------------------------------------------------------ helpers
local function flying(j: Jet,t: number): boolean
	local fl=j.flight
	return fl~=nil and t<fl.start+fl.tl.duration
end
-- PM slot in use by another company's jet (parked there, flying out to it, or not yet off it on the way home)
local function slotTaken(slot: number,except: number,t: number): boolean
	for uid,j in jets do
		if uid==except then continue end
		local fl=j.flight
		if fl and t<fl.start+fl.tl.duration then
			if fl.slot==slot and (fl.tl.dir=="out" or JP.usesSlot(fl.tl,t-fl.start)) then return true end
		elseif j.at=="abroad" and j.slot==slot then
			return true
		end
	end
	return false
end
local function freeSlot(except: number,t: number): number?
	for _,s in JP.PM_SLOTS do if not slotTaken(s.id,except,t) then return s.id end end
	return nil
end
local function otherWindows(except: number,t: number): {JP.Window}
	local out: {JP.Window}={}
	for uid,j in jets do
		local fl=j.flight
		if uid~=except and fl and t<fl.start+fl.tl.duration then
			for _,w in JP.absWindows(fl.tl,fl.start) do table.insert(out,w) end
		end
	end
	return out
end
local function streamAsync(player: Player,pos: Vector3)
	local ok,err=pcall(function() player:RequestStreamAroundAsync(pos,CityPlan.TRAVEL.streamTimeout) end)
	if not ok then warn("[Jet] RequestStreamAroundAsync failed for "..player.Name..": "..tostring(err)) end
end
local function riderValid(fl: Flight): boolean
	local player=fl.rider
	local trip=fl.trip
	if not player or not trip then return false end
	return City.trips[player.UserId]==trip and player.Character==trip.character and trip.root~=nil and trip.root.Parent~=nil
end
local function releaseRider(fl: Flight)
	local player=fl.rider
	fl.rider=nil
	if player then pcall(function() player:SetAttribute("JetFlight",nil) end) end
end
-- Where the founder is for the jet: "abroad" (in Port Meridian - also during a VIP helicopter transfer there),
-- "flying" (on a flight to Port Meridian), "home" (at home, on a flight home, or gone).
local function founderWhere(j: Jet): string
	if j.leaving or not j.player.Parent then return "home" end
	local state=City.state(j.player)
	if state=="abroad" then return "abroad" end
	if state=="flying" then
		local trip: any=City.trips[j.player.UserId]
		if trip and trip.to=="abroad" then return if trip.kind=="heli" then "abroad" else "flying" end
	end
	return "home"
end
JetService.founderWhere=function(player: Player): string
	local j=jets[player.UserId]
	return if j then founderWhere(j) else "home"
end

------------------------------------------------------------------------------------------------ field staff
-- Seconds until the company car (DriverService, package "drivers") drops the travellers of trip `key` at the City
-- Airport departures kerb: DriverService.fieldEta(userId, key) -> seconds? if that function exists (key =
-- client..":"..left, the same as here), else 0 - the travellers then board at once, as before.
local driverMod: any=nil
local driverTried=false
local function fieldEta(userId: number,key: string): number
	if not driverTried then
		driverTried=true
		local mod=script.Parent:FindFirstChild("DriverService")
		if mod and mod:IsA("ModuleScript") then
			local ok,res=pcall(require,mod)
			if ok and typeof(res)=="table" then driverMod=res end
		end
	end
	local fn=if driverMod then driverMod.fieldEta else nil
	if typeof(fn)~="function" then return 0 end
	local ok,eta=pcall(fn,userId,key)
	if not ok or typeof(eta)~="number" or eta~=eta then return 0 end
	return math.clamp(eta,0,JetService.FIELD_WAIT_MAX)
end
local function profileOf(e: any,role: string,i: number): any
	local list=if typeof(e.staffProfiles)=="table" then e.staffProfiles[role] else nil
	local p=if typeof(list)=="table" then list[i] else nil
	return if typeof(p)=="table" and typeof(p.n)=="string" then p else nil
end
-- The travellers of the company's abroad B2B trips by key (client..":"..left) - ShuttleService.abroadTrips' rule,
-- which hands exactly these trips to the jet while empire.jet is true.
function JetService.abroadTravellers(e: any): {[string]: {people: {Person},left: number}}
	local out: {[string]: {people: {Person},left: number}}={}
	local deals=if typeof(e)=="table" then e.deals else nil
	if typeof(deals)~="table" or typeof(deals.tripList)~="table" then return out end
	local away: {any}={}
	local okPresence,presence=pcall(Ops.presence,e,"engineer")
	if okPresence and typeof(presence)=="table" then
		for i,state in presence do if state=="trip" then local p=profileOf(e,"engineer",i);if p then table.insert(away,p) end end end
	end
	local k,m=0,0
	local okReps,reps=pcall(Ops.fieldReps,e)
	local nReps=if okReps and typeof(reps)=="number" then reps else 0
	for _,trip in deals.tripList do
		if typeof(trip)~="table" or trip.founder==true then continue end
		k+=1
		local c=Ops.client(trip.client)
		if not c or c.trip=="city" or trip.hosted then continue end
		if trip.kind=="sign" then m+=1 end
		if c.trip~="abroad" or (tonumber(trip.crew) or 0)<=0 then continue end
		local list: {Person}={}
		local rep=if k<=nReps then profileOf(e,"marketer",k) else nil
		if rep then
			local p=validPerson({name=rep.n,role="marketer",seed=rep.s})
			if p then table.insert(list,p) end
		end
		if trip.kind=="sign" and away[m] and (tonumber(trip.crew) or 0)>=2 then
			local p=validPerson({name=away[m].n,role="engineer",seed=away[m].s})
			if p then table.insert(list,p) end
		end
		if #list>0 then out[tostring(trip.client)..":"..tostring(trip.left)]={people=list,left=tonumber(trip.left) or 0} end
	end
	return out
end
-- Trips started / ended since the last scan (once per SCAN s).
local function scanStaff(j: Jet,s: any)
	local e=if typeof(s.data)=="table" then s.data.empire else nil
	if typeof(e)~="table" then return end
	local current=JetService.abroadTravellers(e)
	local seconds=tonumber(e.seconds) or 0
	for key,info in current do
		if not j.staff[key] then
			local fresh=seconds-info.left<=JetService.STAFF_FRESH
			j.staff[key]={key=key,people=info.people,state=if fresh then "wait_out" else "abroad",flight=nil,ended=false,
				readyAt=if fresh then now()+fieldEta(j.userId,key) else 0}
		end
	end
	for key,st in j.staff do
		if current[key] or st.ended then continue end
		st.ended=true
		if st.state=="wait_out" then j.staff[key]=nil
		elseif st.state=="abroad" then st.state="wait_back" end
	end
end
-- ItineraryService.holds(owner, tripKey) (package "itinerary", optional, required lazily - it requires this module):
-- the founder takes this trip's travellers on his own flight (design/requests/itinerary.md #2)
local itinMod: any=nil
local itinTried=false
local function itinHolds(userId: number,key: string): boolean
	if not itinTried then
		itinTried=true
		local mod=script.Parent:FindFirstChild("ItineraryService")
		if mod and mod:IsA("ModuleScript") then
			local ok,res=pcall(require,mod)
			if ok and typeof(res)=="table" then itinMod=res end
		end
	end
	local fn=if itinMod then itinMod.holds else nil
	if typeof(fn)~="function" then return false end
	local ok,res=pcall(fn,userId,key)
	return ok and res==true
end
-- staff entries in `state`, oldest first, their people capped at `room` (travellers still in the company car on
-- their way to the airport are not ready yet; travellers the founder takes on his own flight wait for it - only his
-- flight (founder = true) picks them up)
-- (aboard: names already on this flight - the founder's own companions - take no extra seat)
local function pending(j: Jet,state: string,room: number,founder: boolean?,aboard: {[string]: boolean}?): ({StaffTrip},{Person})
	local keys: {string}={}
	local t=now()
	for key,st in j.staff do
		if st.state==state and st.readyAt<=t and (founder or not itinHolds(j.userId,key)) then table.insert(keys,key) end
	end
	table.sort(keys)
	local trips: {StaffTrip}={}
	local people: {Person}={}
	for _,key in keys do
		local st=j.staff[key]
		local extra: {Person}={}
		for _,p in st.people do if not (aboard and aboard[p.name]) then table.insert(extra,p) end end
		if #people+#extra>room then break end
		table.insert(trips,st)
		for _,p in extra do table.insert(people,p) end
	end
	return trips,people
end
local function hasState(j: Jet,state: string): boolean
	for _,st in j.staff do if st.state==state then return true end end
	return false
end

------------------------------------------------------------------------------------------------ API
function JetService.available(player: Player): (boolean,string?,{[string]: any})
	local s=Session.get(player)
	if not s or s.closed then return false,"NO_SESSION",{} end
	if not owns(s) then return false,"NO_JET",{} end
	local j=ensureJet(s)
	if not j then return false,"LOADING",{} end
	local t=now()
	local info: {[string]: any}={at=j.at,slot=j.slot}
	local fl=j.flight
	if fl and flying(j,t) then
		info.eta=math.ceil(fl.start+fl.tl.duration-t);info.purpose=fl.purpose;info.staff=table.clone(fl.names)
		return false,if fl.kind=="ferry" then "JET_RETURNING" else "JET_BUSY",info
	end
	local state=City.state(player)
	if state=="flying" then return false,"BUSY",info end
	if state=="home" and j.at=="abroad" then return false,"JET_ABROAD",info end
	if state=="abroad" and j.at=="home" then return false,"JET_AT_HOME",info end
	if state=="home" and not freeSlot(player.UserId,t) then return false,"PM_STANDS_FULL",info end
	return true,nil,info
end
-- Start a flight now with `delay` s of extra boarding. people = companions (validated), staff = staff trips aboard.
local function start(j: Jet,kind: string,slot: number,delay: number,rider: Player?,purpose: string,people: {Person},staff: {StaffTrip},onArrive: ((string,string)->())?): Flight
	local t=now()
	local tl=JP.timeline(kind,slot,delay)
	j.seq+=1
	local id="jet:"..j.userId..":"..j.seq
	local names: {string}={}
	local keys: {string}={}
	for _,st in staff do
		table.insert(keys,st.key)
		st.flight=id
		st.state=if tl.dir=="out" then "out" else "back"
		for _,p in st.people do table.insert(names,p.name) end
	end
	local fl: Flight={id=id,kind=kind,purpose=purpose,slot=slot,delay=tl.delay,start=t,tl=tl,rider=rider,trip=nil,moved=false,arrived=false,
		onArrive=onArrive,companions=0,staff=keys,names=names}
	fl.companions=buildCompanions(j,if kind=="ferry" then {} else people)
	j.flight=fl
	j.awaySince=nil;j.staffWaitSince=nil;j.staffNotified=false
	if kind=="out" then j.slot=slot end
	publish(j)
	refreshPrompt(j)
	return fl
end
-- a rider-less flight (staff, positioning, ferry): the next clear slot within CONFIG.maxDelayEmpty; none (busy
-- runways with other company jets) -> nothing starts, the dispatch tries again after RETRY s
local function startEmpty(j: Jet,kind: string,slot: number,purpose: string,people: {Person},staff: {StaffTrip}): Flight?
	local t=now()
	local delay,clear=JP.schedule(kind,slot,t,otherWindows(j.userId,t),JP.CONFIG.maxDelayEmpty)
	if not clear then j.retryAt=t+JetService.RETRY;return nil end
	j.retryAt=nil
	return start(j,kind,slot,delay,nil,purpose,people,staff,nil)
end
function JetService.fly(player: Player,opts: any): {[string]: any}
	local o=if typeof(opts)=="table" then opts else {}
	local to: string=if o.to=="abroad" or o.to=="home" then o.to else ""
	if to=="" then return {ok=false,err="BAD_INPUT"} end
	local s=Session.get(player)
	if not s or s.closed then return {ok=false,err="NO_SESSION"} end
	if not owns(s) then return {ok=false,err="NO_JET"} end
	local j=ensureJet(s)
	if not j then return {ok=false,err="LOADING"} end
	local t=now()
	local cur=j.flight
	if cur and flying(j,t) then
		return {ok=false,err=if cur.kind=="ferry" then "JET_RETURNING" else "JET_BUSY",eta=math.ceil(cur.start+cur.tl.duration-t)}
	end
	local state: string=City.state(player)
	if state=="flying" then return {ok=false,err="BUSY"} end
	local from: string=if to=="abroad" then "home" else "abroad" -- where the founder and the jet must be
	if state~=from then return {ok=false,err=if to=="abroad" then "ALREADY_ABROAD" else "NOT_ABROAD"} end
	if j.at~=from then return {ok=false,err=if to=="abroad" then "JET_ABROAD" else "JET_AT_HOME"} end
	local character,r,humanoid=rootOf(player)
	if not character or not r or not humanoid or humanoid.Health<=0 then return {ok=false,err="LOADING"} end
	if humanoid.SeatPart then return {ok=false,err="LEAVE_VEHICLE"} end
	local slot=j.slot
	if to=="abroad" then
		local free=freeSlot(player.UserId,t)
		if not free then return {ok=false,err="PM_STANDS_FULL"} end
		slot=free
	end
	local kind=if to=="abroad" then "out" else "back"
	local others=otherWindows(j.userId,t)
	local delay,clear=JP.schedule(kind,slot,t,others,JP.CONFIG.maxDelay)
	if not clear then
		local later,ok2=JP.schedule(kind,slot,t,others,JP.CONFIG.maxDelayEmpty)
		return {ok=false,err="RUNWAY_BUSY",eta=if ok2 then later else nil}
	end
	-- companions: the caller's first, then field staff waiting for the jet in this direction
	local people: {Person}={}
	local seen: {[string]: boolean}={}
	if typeof(o.companions)=="table" then
		for _,c in o.companions do
			if #people>=JetService.MAX_COMPANIONS then break end
			local p=validPerson(c)
			if p and not seen[p.name] then seen[p.name]=true;table.insert(people,p) end
		end
	end
	local staffTrips,staffPeople=pending(j,if to=="abroad" then "wait_out" else "wait_back",JetService.MAX_COMPANIONS-#people,true,seen)
	for _,p in staffPeople do if not seen[p.name] then seen[p.name]=true;table.insert(people,p) end end
	local fuel=0
	if o.pay==true then
		fuel=JetService.FUEL_LEG
		if not Economy.spend(s,fuel,"jet") then return {ok=false,err="NO_MONEY",price=fuel} end
	end
	local fl=start(j,kind,slot,delay,player,"founder",people,staffTrips,if typeof(o.onArrive)=="function" then o.onArrive else nil)
	-- the founder: a CityService trip ("flying"), held below the departure field while the client shows the ride
	local trip={player=player,state="flying",to=to,character=character,root=r,wasAnchored=r.Anchored,releaseAt=math.huge,kind="jet",
		display=humanoid.DisplayDistanceType,flight=fl.id}
	City.trips[player.UserId]=trip :: any
	player:SetAttribute("TravelState","flying")
	fl.trip=trip
	r.Anchored=true
	humanoid.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
	character:PivotTo(JP.hold(if to=="abroad" then "home" else "abroad",slot))
	player:SetAttribute("JetFlight",fl.id)
	Session.markDirty(s,true)
	task.spawn(streamAsync,player,if to=="abroad" then JP.HOME_PARK.Position else JP.slot(slot).cf.Position)
	local dep,arr,done=JP.times(fl.tl,fl.start)
	local arriveAt=arr+JetService.ARRIVE_AFTER
	return {ok=true,flightId=fl.id,departAt=dep,arriveAt=arriveAt,doneAt=done,delay=fl.delay,slot=slot,to=to,fuel=fuel,staff=table.clone(fl.names),
		destination=if to=="abroad" then "Port Meridian" else "City Airport"}
end
-- Send the jet (parked in Hangar 1) empty to Port Meridian for the founder who is there (came by shuttle) - "the jet
-- picks you up"; field staff waiting for a trip fly along. -> {ok, flightId, arriveAt (the jet parked on its
-- stand, ready for "Fly home"), slot, err ("NOT_ABROAD", "ALREADY_THERE", "JET_BUSY", "JET_RETURNING",
-- "PM_STANDS_FULL", "NO_JET", ...)}. Costs nothing (no rider).
function JetService.summon(player: Player): {[string]: any}
	local s=Session.get(player)
	if not s or s.closed then return {ok=false,err="NO_SESSION"} end
	if not owns(s) then return {ok=false,err="NO_JET"} end
	local j=ensureJet(s)
	if not j then return {ok=false,err="LOADING"} end
	local t=now()
	local cur=j.flight
	if cur and flying(j,t) then return {ok=false,err=if cur.kind=="ferry" then "JET_RETURNING" else "JET_BUSY",eta=math.ceil(cur.start+cur.tl.duration-t)} end
	if founderWhere(j)~="abroad" then return {ok=false,err="NOT_ABROAD"} end
	if j.at=="abroad" then return {ok=false,err="ALREADY_THERE"} end
	local slot=freeSlot(j.userId,t)
	if not slot then return {ok=false,err="PM_STANDS_FULL"} end
	local outsT,outsP=pending(j,"wait_out",JetService.MAX_COMPANIONS)
	local fl=startEmpty(j,"out",slot,if #outsT>0 then "staff" else "position",outsP,outsT)
	if not fl then return {ok=false,err="RUNWAY_BUSY",eta=JetService.RETRY} end
	local _,_,done=JP.times(fl.tl,fl.start)
	return {ok=true,flightId=fl.id,arriveAt=done,slot=slot}
end
function JetService.onArrive(fn: (Player,string,string)->()): ()->()
	table.insert(arriveFns,fn)
	return function()
		local i=table.find(arriveFns,fn)
		if i then table.remove(arriveFns,i) end
	end
end
function JetService.status(player: Player): {[string]: any}
	local s=Session.get(player)
	local j=jets[player.UserId]
	if not j then return {owned=owns(s),at="home",flying=false} end
	local t=now()
	local fl=j.flight
	local res: {[string]: any}={owned=true,at=j.at,slot=j.slot,flying=fl~=nil and flying(j,t)}
	if fl and res.flying then
		local dep,arr,done=JP.times(fl.tl,fl.start)
		res.flightId=fl.id;res.kind=fl.kind;res.purpose=fl.purpose;res.phase=JP.phaseAt(fl.tl,t-fl.start);res.departAt=dep
		res.arriveAt=arr+JetService.ARRIVE_AFTER;res.doneAt=done
	end
	return res
end
function JetService.flightOf(player: Player): Flight?
	local j=jets[player.UserId]
	return if j then j.flight else nil
end
-- the field-staff trips the jet knows of (tests / debug): key -> {state, people names}
function JetService.staffOf(player: Player): {[string]: {state: string,people: {string}}}
	local j=jets[player.UserId]
	local out: {[string]: {state: string,people: {string}}}={}
	if not j then return out end
	for key,st in j.staff do
		local names: {string}={}
		for _,p in st.people do table.insert(names,p.name) end
		out[key]={state=st.state,people=names}
	end
	return out
end

------------------------------------------------------------------------------------------------ ride
-- the first arrival spot no other character stands on
local function arrivalSpot(dest: string,except: Player): CFrame
	local spots=JP.arrivalSpots(dest)
	local others: {Vector3}={}
	for _,s in Session.all() do
		local pl: Player?=s.player
		if pl and pl~=except then
			local _,r=rootOf(pl)
			if r then table.insert(others,r.Position) end
		end
	end
	for _,cf in spots do
		local taken=false
		for _,p in others do
			local d=Vector3.new(p.X-cf.X,0,p.Z-cf.Z).Magnitude
			if d<JetService.SPOT_FREE and math.abs(p.Y-cf.Y)<6 then taken=true;break end
		end
		if not taken then return cf end
	end
	return spots[1]
end
local function moveHold(fl: Flight)
	fl.moved=true
	local player=fl.rider
	if not player then return end
	local dest=fl.tl.to
	task.spawn(function()
		-- stream the arrival area (the placement spot) early, then hold the character under the destination field
		streamAsync(player,(if dest=="abroad" then JP.ARRIVAL.abroad else JP.ARRIVAL.home).Position)
		if not riderValid(fl) or fl.arrived then return end
		local trip: any=fl.trip
		local character: Model=trip.character
		character:PivotTo(JP.hold(dest,fl.slot))
	end)
end
local function fireArrive(player: Player,fl: Flight,dest: string)
	if fl.onArrive then
		local cb=fl.onArrive :: (string,string)->()
		local ok,err=pcall(function() cb(fl.id,dest) end)
		if not ok then warn("[Jet] onArrive callback failed: "..tostring(err)) end
	end
	for _,fn in table.clone(arriveFns) do
		local ok,err=pcall(function() fn(player,fl.id,dest) end)
		if not ok then warn("[Jet] onArrive listener failed: "..tostring(err)) end
	end
end
local function arrive(j: Jet,fl: Flight)
	fl.arrived=true
	local player=fl.rider
	if not player or not riderValid(fl) then releaseRider(fl);return end
	local dest=fl.tl.to
	task.spawn(function()
		streamAsync(player,(if dest=="abroad" then JP.ARRIVAL.abroad else JP.ARRIVAL.home).Position)
		if not riderValid(fl) then releaseRider(fl);return end
		local trip: any=fl.trip
		local character: Model=trip.character
		local r: BasePart=trip.root
		character:PivotTo(arrivalSpot(dest,player))
		r.Anchored=trip.wasAnchored
		local humanoid=character:FindFirstChildOfClass("Humanoid")
		if humanoid and trip.display then humanoid.DisplayDistanceType=trip.display end
		if dest=="abroad" then
			trip.state="abroad";trip.kind=nil;player:SetAttribute("TravelState","abroad")
		else
			City.trips[player.UserId]=nil;player:SetAttribute("TravelState",nil)
		end
		releaseRider(fl)
		local s=Session.get(player)
		if s then Session.markDirty(s,true) end
		fireArrive(player,fl,dest)
	end)
end
local function finish(j: Jet,fl: Flight)
	j.at=fl.tl.to
	if j.at=="abroad" then j.slot=fl.slot end
	-- the staff aboard: arrived abroad (back again if their trip already ended) / home (done)
	for _,key in fl.staff do
		local st=j.staff[key]
		if st and st.flight==fl.id then
			st.flight=nil
			if st.state=="out" then st.state=if st.ended then "wait_back" else "abroad"
			elseif st.state=="back" then j.staff[key]=nil end
		end
	end
	publish(j)
	refreshPrompt(j)
end

------------------------------------------------------------------------------------------------ staff dispatch
-- The jet is idle (not flying): serve the field staff and bring an abandoned jet home.
local function dispatch(j: Jet,t: number)
	if j.retryAt and t<j.retryAt then return end -- no clear slot a moment ago
	local where=founderWhere(j)
	local room=JetService.MAX_COMPANIONS
	if j.at=="abroad" and where=="abroad" then
		-- the jet waits for the founder: staff work waits STAFF_WAIT s, then the jet goes (back with returning staff,
		-- or home to fetch departing staff)
		j.awaySince=nil
		local backs=hasState(j,"wait_back")
		local outs=hasState(j,"wait_out")
		if not backs and not outs then j.staffWaitSince=nil;j.staffNotified=false;return end
		j.staffWaitSince=j.staffWaitSince or t
		if not j.staffNotified then
			local trips,people=pending(j,if backs then "wait_back" else "wait_out",room)
			local names: {string}={}
			for _,p in people do table.insert(names,p.name) end
			if #trips>0 then -- (travellers still in the company car: told once they are at the airport)
				j.staffNotified=true
				notice(j.player,if backs then "Your jet takes "..namesText(names).." home from Port Meridian in "..math.floor(JetService.STAFF_WAIT/60+0.5)
					.." min - fly home with them from the airstair, or it leaves without you."
					else namesText(names).." needs the company jet for a trip. Your jet flies home for them in "..math.floor(JetService.STAFF_WAIT/60+0.5).." min unless you fly home now.")
			end
		end
		if t-(j.staffWaitSince :: number)<JetService.STAFF_WAIT then return end
		if backs then
			local trips,people=pending(j,"wait_back",room)
			if #trips>0 then startEmpty(j,"back",j.slot,"staff",people,trips) end
		else
			startEmpty(j,"ferry",j.slot,"ferry",{},{})
		end
		return
	end
	j.staffWaitSince=nil;j.staffNotified=false
	if j.at=="home" then
		j.awaySince=nil
		local outsT,outsP=pending(j,"wait_out",room)
		if #outsT>0 then
			local slot=freeSlot(j.userId,t)
			if slot and startEmpty(j,"out",slot,"staff",outsP,outsT) then
				local names: {string}={}
				for _,p in outsP do table.insert(names,p.name) end
				notice(j.player,captainOf(j).." flies "..namesText(names).." to Port Meridian in your company jet.")
			end
			return
		end
		if hasState(j,"wait_back") then
			local slot=freeSlot(j.userId,t)
			if slot and startEmpty(j,"out",slot,"position",{},{}) then
				local _,people=pending(j,"wait_back",room)
				local names: {string}={}
				for _,p in people do table.insert(names,p.name) end
				notice(j.player,"Your company jet flies to Port Meridian to bring "..namesText(names).." home.")
			end
		end
		return
	end
	-- parked in Port Meridian, the founder is not there (or on his way there)
	if where=="flying" then j.awaySince=nil;return end
	local backsT,backsP=pending(j,"wait_back",room)
	if #backsT>0 then startEmpty(j,"back",j.slot,"staff",backsP,backsT);return end
	-- nobody to bring home: fly home empty after autoFerry s (at once when staff wait at home)
	j.awaySince=j.awaySince or t
	if hasState(j,"wait_out") or t-(j.awaySince :: number)>=JP.CONFIG.autoFerry then startEmpty(j,"ferry",j.slot,"ferry",{},{}) end
end

------------------------------------------------------------------------------------------------ tick
local function scan()
	local seen: {[number]: boolean}={}
	for _,s in Session.all() do
		local player: Player?=s.player
		if not player or s.closed then continue end
		if owns(s) then
			seen[player.UserId]=true
			local j: Jet?=jets[player.UserId]
			if not j then
				j=ensureJet(s)
				if j and loadedWithout[player.UserId] then
					loadedWithout[player.UserId]=nil
					notice(player,"Your company jet is in Hangar 1 at City Airport. "..captainOf(j)
						.." and First Officer "..CampusMath.staffName(JetService.PILOTS[2],player.UserId).." are on standby.")
				end
			else
				ensureJet(s) -- a rejoin takes over the jet still flying from the previous session
				local company,livery=companyOf(s)
				if company~=j.company or livery~=j.livery then
					j.company=company;j.livery=livery
					publish(j)
					if not j.flight or not flying(j,now()) then buildCrew(j) end
					j.promptKey="-"
				end
				refreshPrompt(j)
			end
			local jj=jets[player.UserId]
			if jj then scanStaff(jj,s) end
		elseif jets[player.UserId]==nil and loadedWithout[player.UserId]==nil then
			loadedWithout[player.UserId]=true
		end
	end
	for uid,j in jets do
		if not seen[uid] and not (j.flight and flying(j,now())) then dropJet(uid) end
	end
end
function JetService.tick(dt: number)
	if not root then return end
	scanAcc+=dt
	if scanAcc>=JetService.SCAN then scanAcc=0;scan() end
	local t=now()
	for uid,j in jets do
		local fl=j.flight
		if fl then
			local tau=t-fl.start
			if fl.rider and not fl.arrived and not riderValid(fl) then releaseRider(fl) end -- respawned / left: the jet flies on
			local ph=fl.tl.phases
			if fl.rider and not fl.moved and tau>=(ph.cruise.t0+ph.cruise.t1)/2 then moveHold(fl) end
			if not fl.arrived and tau>=ph.deboarding.t0+JetService.ARRIVE_AFTER then arrive(j,fl) end
			if tau>=fl.tl.duration and j.at~=fl.tl.to then finish(j,fl) end
		end
		if j.leaving then
			-- the founder left the game mid-flight: the folder stays until that flight has ended
			if not flying(j,t) then dropJet(uid) end
			continue
		end
		if not flying(j,t) then dispatch(j,t) end
	end
end

------------------------------------------------------------------------------------------------ init
local MESSAGES: {[string]: string}={
	BUSY="You are already on a flight.",LOADING="Still loading - try again in a moment.",LEAVE_VEHICLE="Leave your car first.",
	PM_STANDS_FULL="Both jet stands in Port Meridian are taken by other companies' jets right now. Take the shuttle or try again later.",
	ALREADY_ABROAD="You are already abroad.",NOT_ABROAD="You are already at home.",JET_BUSY="Your jet is flying right now.",
	JET_RETURNING="Your jet is flying home - it will be back in Hangar 1 soon.",
}
local function onPrompt(q: ProximityPrompt,player: Player)
	if q:GetAttribute("JetAction")~="fly" or q:GetAttribute("OwnerUserId")~=player.UserId then return end
	local t=now()
	if (promptAt[player.UserId] or 0)>t then return end
	promptAt[player.UserId]=t+JetService.PROMPT_COOLDOWN
	local part=q.Parent
	local _,r=rootOf(player)
	if not part or not part:IsA("BasePart") or not r or (r.Position-part.Position).Magnitude>20 then return end
	local j=jets[player.UserId]
	if not j then return end
	local res=JetService.fly(player,{to=if j.at=="home" then "abroad" else "home",pay=true})
	if res.ok then
		local wait=math.max(0,math.floor(res.departAt-t+0.5))
		local with=if #res.staff>0 then " "..namesText(res.staff).." flies with you." else ""
		notice(player,"Welcome aboard! Departure in "..wait.." s"..(if res.delay>0 then " (waiting for a clear runway)" else "")..", arrival in "
			..math.max(1,math.floor((res.arriveAt-t)/60+0.5)).." min. Fuel $"..res.fuel.."."..with)
	elseif res.err=="RUNWAY_BUSY" then
		notice(player,"The runway is busy right now"..(if typeof(res.eta)=="number" then " - the next free departure slot is in about "..math.max(1,math.floor(res.eta/60+0.5)).." min" else "")
			..". Try again then, or take the shuttle.")
	elseif res.err=="NO_MONEY" then
		notice(player,"You need $"..tostring(res.price or JetService.FUEL_LEG).." for the jet fuel.")
	else
		notice(player,MESSAGES[tostring(res.err)] or "The jet cannot fly right now.")
	end
end
function JetService.init()
	local old=ReplicatedStorage:FindFirstChild("CompanyJets")
	if old then old:Destroy() end
	local f=Instance.new("Folder");f.Name="CompanyJets"
	f:SetAttribute("Kind",JP.KIND);f:SetAttribute("Scale",JP.SCALE)
	f.Parent=ReplicatedStorage
	root=f
	local oldPrompts=workspace:FindFirstChild("CompanyJetPrompts")
	if oldPrompts then oldPrompts:Destroy() end
	local pf=Instance.new("Folder");pf.Name="CompanyJetPrompts";pf.Parent=workspace
	promptFolder=pf
	table.clear(jets);table.clear(promptAt);table.clear(loadedWithout);scanAcc=JetService.SCAN
	Prompts.PromptTriggered:Connect(onPrompt)
	Session.onClosing(function(s)
		local player: Player?=s.player
		if not player then return end
		local j=jets[player.UserId]
		if j and j.session==s then
			if j.flight then releaseRider(j.flight) end
			if j.flight and flying(j,now()) then
				-- everyone near keeps seeing the jet fly on; the folder goes when the flight has ended
				j.leaving=true;table.clear(j.staff)
				refreshPrompt(j)
			else
				dropJet(player.UserId)
			end
		end
		promptAt[player.UserId]=nil;loadedWithout[player.UserId]=nil
	end)
end
return JetService
