--!strict
-- ShuttleService (package "flight"): the scheduled Port Meridian shuttle, its two pilots, boarding, the ride
-- and the VIP helicopter - server side. Required, initialised and ticked by CityService (City.init/tick).
--   * Timetable + path: FlightPlan (shared). The server never moves the aircraft: it publishes the timetable
--     state as attributes on ReplicatedStorage.Shuttle (always replicated, no streaming): Enabled, Interval,
--     Epoch, Kind, Scale, Airline, Phase, PhaseStart, PhaseEnd, Leg ("out" | "back"), Cycle, LegStart,
--     Flight, From, To, NextOut, NextBack (departure times), CrewState, CaptainName, FirstOfficerName, Heli*.
--     They change once per phase (~11 writes per leg). Every client animates the aircraft from
--     workspace:GetServerTimeNow() with the same FlightPlan maths (ShuttleController).
--   * Pilots: two EmployeeRigDesign rigs (role "pilot": uniform + cap, fixed names) built ONCE into
--     ReplicatedStorage.Shuttle.Crew as templates (no tag, no talk prompt, not in workspace = no physics);
--     clients clone them, walk them from the CrewRoom marker / the terminal to the aircraft and seat them in
--     the cockpit (CrewState says which).
--   * Tickets: TravelAction {action="ticket"} at a check-in counter (City Airport: CityPlan.TRAVEL.ticket via
--     Economy.spend, the return flight included; Port Meridian: free). One ticket per player, valid for the
--     next departures until used.
--   * Boarding: at the gate (prompt CityAction="board" -> TravelAction {action="board"}) during "boarding",
--     or automatically when boarding ends for ticket holders standing at the gate. A boarded passenger's
--     character is held server-side: root anchored, name hidden, parked under the departure stand (below the
--     apron, nobody sees it, and the replication focus stays at the airport the aircraft is at); the Player
--     attribute ShuttleLeg tells the client to show the ride (cabin window or chase camera on the
--     client-animated aircraft over the real streamed map). Why this is safe: the server only ever moves the
--     character three times (board, mid-cruise, arrival), each move after Player:RequestStreamAroundAsync of
--     the target area (MinimumRadiusPause never stalls the ride), nothing is welded to a client-only model
--     (no physics ownership or replication conflicts), and a respawn, leave or rebuild cannot strand the
--     player: CityService state "flying" (PlotService away check), refund unless arrived.
--   * Arrival: when the aircraft reaches "deboarding" the server streams the arrival hall and pivots the
--     character there (CityPlan.ABROAD.arrival / AIRPORT.arrival), unanchored, state abroad / home.
--   * Field staff on international trips (user request 20): at the start of every boarding the service picks
--     up to MAX_PAX travellers of the server's companies - the field rep (and the travelling engineer) of each
--     abroad pilot trip (CompanyOps tripList, not hosted, no company jet) flies out on the next out leg and home
--     on the first return leg after the trip has ended (at the latest RETURN_CYCLES cycles later; the economy
--     keeps its own trip clock, this is the visible part). Their rigs (EmployeeRigDesign, the same look as in
--     the HQ: role + profile name/seed) are built once per leg as templates into ReplicatedStorage.Shuttle.
--     Passengers (attributes Leg, PassengerName, Company); ShuttlePassengers (client) walks them from the gate
--     to the aircraft during boarding and off it after the arrival when players are near.
--   * VIP helicopter: TravelAction {action="heli", to="hotel"|"airport"} between the "Helipad" markers
--     (Purpose VIPAirport = Port Meridian Airport, VIP = Meridian Grand Hotel roof; built by MetroBuilder; the
--     service answers HELI_UNAVAILABLE if they are missing). Free with the "limo" game pass
--     (ShopService.owns via pcall), else HELI_FEE. Same hold/stream/arrive pattern; the ride is published as
--     HeliStart/HeliFrom/HeliTo/HeliRider so every client sees the helicopter fly.
--   * Company bookings (package "itinerary", additive): Shuttle.book(session, {to, companions, trip}) gives the founder a
--     prepaid ticket for his business trip (no counter, price 0: CompanyOps already books the trip's flights) that boards
--     like any ticket (gate prompt / auto-board) and is valid for the next departures until used; the companions (the
--     trip's field rep + engineer) board with him and join that leg's Passengers (walked off at the destination like
--     the field staff). While a booking holds a trip - or ItineraryService.holds(owner, tripKey) says the founder will
--     take them (his offer is open, he said Go and is on his way to the airport, or they fly home with him) - the
--     field-staff rule above does not fly those travellers on another leg; once boarded they count as flown in that
--     direction. A ticket he paid for at the counter that becomes the company booking is refunded (the company books
--     the seat; the existing refund path). Shuttle.unbook drops it, Shuttle.booking reads it, Shuttle.flownAhead /
--     Shuttle.travellersLeg tell whether / on which leg a trip's travellers flew.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CityPlan=require(ReplicatedStorage.Shared.Config.CityPlan)
local FP=require(ReplicatedStorage.Shared.FlightPlan)
local Format=require(ReplicatedStorage.Shared.Format)
local CampusMath=require(ReplicatedStorage.Shared.CampusMath)
local Economy=require(script.Parent.EconomyService)
local Session=require(script.Parent.SessionService)
local Rig=require(script.Parent.EmployeeRigDesign)
local Ops=require(ReplicatedStorage.Shared.CompanyOps)
local Shuttle={}
Shuttle.ENABLED=true
Shuttle.HELI_FEE=2500 -- tuned by CORE_SPEC: VIP helicopter transfer without the limousine pass
Shuttle.HELI_RADIUS=40 -- server distance check: character to the departure helipad / hotel lobby
Shuttle.CREW={captain=9160,firstOfficer=9140} -- CampusMath.staffName indices (owner 0): the same two pilots on every server
Shuttle.MAX_PAX=4 -- field staff shown per leg
Shuttle.RETURN_CYCLES=2 -- a traveller flies home at the latest this many cycles after flying out
-- (Tom Nakamura, Sana Okafor; indices far apart so the surnames differ)

export type Api={trips: {[number]: any},setState: (Player,string)->(),rootOf: (Player)->(Model?,BasePart?,Humanoid?)}
type Ticket={to: string,price: number,session: any,at: number,prepaid: boolean?,companions: {any}?,trip: string?}
local api: Api?=nil
local folder: Folder?=nil
local tickets: {[number]: Ticket}={}
Shuttle.tickets=tickets
local lastKey=""
local lastPhase=""
local lastCrew=""
local nextPadSearch=0
local autoDone: {[string]: boolean}={}
local heli: {busyUntil: number,from: Vector3?,to: Vector3?,fromPad: BasePart?,toPad: BasePart?}={busyUntil=0,from=nil,to=nil,fromPad=nil,toPad=nil}
-- field staff: trip key -> what was shown (dir of the last leg flown, cycle, who)
type Flown={dir: string,cycle: number,owner: number,profile: any,role: string,company: string}
local flown: {[string]: Flown}={}
Shuttle.flown=flown
local paxKey=""

local function now(): number return workspace:GetServerTimeNow() end
local function flat(a: Vector3,b: Vector3): number return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
local function nearAny(p: Vector3,points: {Vector3},radius: number): boolean
	for _,q in points do if flat(p,q)<=radius and math.abs(p.Y-q.Y)<14 then return true end end
	return false
end
local function refund(s: any,price: number)
	if price<=0 or not s or not s.data then return end
	Economy.grant(s,price,"travel") -- refund: P&L line "travel" (design/requests/econ.md #4)
	s.data.stats.totalCost=math.max(0,s.data.stats.totalCost-price)
	Session.markDirty(s,true)
end
local function setAttr(name: string,value: any)
	local f=folder
	if f and f:GetAttribute(name)~=value then f:SetAttribute(name,value) end
end
function Shuttle.enabled(): boolean
	local f=folder
	return Shuttle.ENABLED and f~=nil and f:GetAttribute("Enabled")==true
end
-- Shuttle.ENABLED=false (or the attribute Enabled=false) turns the scheduled shuttle off: check-in falls back
-- to the instant flight (CityService.flight) on the client.
function Shuttle.setEnabled(on: boolean)
	Shuttle.ENABLED=on
	setAttr("Enabled",on)
end

------------------------------------------------------------------------------------------------ crew
local function buildCrew(f: Folder)
	local crew=Instance.new("Folder");crew.Name="Crew"
	local temp=Instance.new("Folder");temp.Name="CrewBuild"
	local names: {[string]: string}={}
	type Def={key: string,index: number,title: string}
	local defs: {Def}={{key="Captain",index=Shuttle.CREW.captain,title="Captain"},{key="FirstOfficer",index=Shuttle.CREW.firstOfficer,title="First Officer"}}
	for _,def in defs do
		local ok,err=pcall(function()
			local name=CampusMath.staffName(def.index,0)
			local m=Rig.build(temp,0,def.index,"pilot",CFrame.new(),{n=name})
			-- a template, not an employee: no tag (EmployeeController/TalkController), no talk prompt
			m:RemoveTag("CompanyEmployee")
			for _,d in m:GetDescendants() do
				if d:IsA("ProximityPrompt") then d:Destroy()
				elseif d:IsA("BasePart") then d.Anchored=d.Name=="HumanoidRootPart";d.CanCollide=false;d.CanTouch=false;d.CanQuery=false
				elseif d:IsA("TextLabel") and d.Parent and d.Parent.Name=="EmployeeBadge" then d.Text=def.title.." "..name.."\n"..FP.CONFIG.airline end
			end
			m.Name=def.key;m:SetAttribute("CrewRole",def.title);m:SetAttribute("Role","Pilot")
			m.Parent=crew
			names[def.key]=name
		end)
		if not ok then warn("[Shuttle] building the pilot rig failed: "..tostring(err)) end
	end
	temp:Destroy()
	crew.Parent=f
	f:SetAttribute("CaptainName",names.Captain or "")
	f:SetAttribute("FirstOfficerName",names.FirstOfficer or "")
end

------------------------------------------------------------------------------------------------ world hooks
-- Board prompts (invisible anchored parts, client handles CityAction="board" -> TravelAction {action="board"}).
local function gatePrompt(parent: Instance,name: string,pos: Vector3,from: string,objectText: string)
	local p=Instance.new("Part");p.Name=name;p.Size=Vector3.new(1,1,1);p.Transparency=1;p.Anchored=true
	p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.CFrame=CFrame.new(pos);p.Parent=parent
	p:SetAttribute("BoardFrom",from)
	local q=Instance.new("ProximityPrompt");q.Name="BoardPrompt";q.ActionText="Board";q.ObjectText=objectText
	q.MaxActivationDistance=12;q.HoldDuration=0.3;q.RequiresLineOfSight=false
	-- Public: WorldController disables every prompt that is neither the player's own nor Public
	q:SetAttribute("CityAction","board");q:SetAttribute("BoardFrom",from);q:SetAttribute("Public",true);q.Parent=p
end
local function findHomeDesk(): Vector3
	local world=workspace:FindFirstChild("WorldCity")
	local gate=if world then world:FindFirstChild("GateA"..CityPlan.AIRPORT.shuttleStand,true) else nil
	local desk=if gate then gate:FindFirstChild("GateDesk") else nil
	if desk and desk:IsA("BasePart") then return desk.Position+Vector3.new(0,1.4,-desk.Size.Z/2-1.6) end
	return FP.HOME_GATES[1]+Vector3.new(0,0,6)
end
local function findPads()
	local world=workspace:FindFirstChild("WorldCity")
	if not world then return end
	for _,d in world:GetDescendants() do
		if d:IsA("BasePart") and d.Name=="Helipad" then
			local purpose=d:GetAttribute("Purpose")
			if purpose=="VIPAirport" then heli.fromPad=d elseif purpose=="VIP" then heli.toPad=d end
		end
	end
end
local function padTop(p: BasePart): Vector3 return p.Position+Vector3.new(0,p.Size.Y/2,0) end

------------------------------------------------------------------------------------------------ field staff
local function profileOf(e: any,role: string,i: number): any
	local list=if typeof(e.staffProfiles)=="table" then e.staffProfiles[role] else nil
	local p=if typeof(list)=="table" then list[i] else nil
	return if typeof(p)=="table" and typeof(p.n)=="string" then p else nil
end
-- Travellers of a company's abroad pilot trips: {key, trip, rep profile?, engineer profile?} (the k-th field rep
-- for the k-th trip of the reps, the engineers CompanyOps.presence marks as travelling - PhoneService's rule).
local function abroadTrips(e: any): {{key: string,profiles: {{p: any,role: string}}}}
	local out={}
	local deals=e.deals
	if typeof(deals)~="table" or typeof(deals.tripList)~="table" or e.jet==true then return out end
	local away: {any}={}
	local okPresence,presence=pcall(Ops.presence,e,"engineer")
	if okPresence and typeof(presence)=="table" then
		for i,state in presence do if state=="trip" then local p=profileOf(e,"engineer",i);if p then table.insert(away,p) end end end
	end
	local k,m=0,0
	local reps=Ops.fieldReps(e)
	for _,trip in deals.tripList do
		if typeof(trip)~="table" or trip.founder==true then continue end
		k+=1
		local c=Ops.client(trip.client)
		if not c or c.trip=="city" or trip.hosted then continue end
		if trip.kind=="sign" then m+=1 end
		if c.trip~="abroad" or (tonumber(trip.crew) or 0)<=0 then continue end
		local list: {{p: any,role: string}}={}
		local rep=if k<=reps then profileOf(e,"marketer",k) else nil
		if rep then table.insert(list,{p=rep,role="marketer"}) end
		if trip.kind=="sign" and away[m] and (tonumber(trip.crew) or 0)>=2 then table.insert(list,{p=away[m],role="engineer"}) end
		if #list>0 then table.insert(out,{key=tostring(trip.client)..":"..tostring(trip.left),profiles=list}) end
	end
	return out
end
-- ItineraryService.holds(owner, tripKey) (package "itinerary", optional, required lazily - it requires this module):
-- the founder's itinerary will take this trip's travellers on his own flight
local itinMod: any=nil
local itinTried=false
local function itinHolds(userId: number,tripKey: string): boolean
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
	local ok,res=pcall(fn,userId,tripKey)
	return ok and res==true
end
-- trip keys ("<owner>:<client>:<left>") of open company bookings in direction `to` (their travellers fly with the founder)
local function heldTrips(to: string?): {[string]: boolean}
	local out: {[string]: boolean}={}
	for userId,t in tickets do
		if t.trip and (to==nil or t.to==to) then out[userId..":"..t.trip]=true end
	end
	return out
end
-- Who flies on leg st (called once when its boarding starts): out = travellers of new abroad trips, back =
-- travellers whose trip ended (or flew out RETURN_CYCLES cycles ago). Returns {owner, profile, role, company}.
function Shuttle.passengersFor(st: FP.State): {Flown}
	local list: {Flown}={}
	local current: {[string]: boolean}={}
	local held=heldTrips(if st.dir=="out" then "abroad" else "home")
	for _,s in Session.all() do
		local player: Player?=s.player
		local data=s.data
		local e=if typeof(data)=="table" then data.empire else nil
		if not player or typeof(e)~="table" then continue end
		local company=if typeof(data.company)=="table" and typeof(data.company.name)=="string" then data.company.name else ""
		for _,t in abroadTrips(e) do
			local key=player.UserId..":"..t.key
			current[key]=true
			if st.dir=="out" and not flown[key] and not held[key] and not itinHolds(player.UserId,t.key) then
				for _,who in t.profiles do
					if #list>=Shuttle.MAX_PAX then break end
					local f: Flown={dir="out",cycle=st.cycle,owner=player.UserId,profile=who.p,role=who.role,company=company}
					flown[key..":"..who.role]=f
					table.insert(list,f)
				end
				flown[key]={dir="out",cycle=st.cycle,owner=player.UserId,profile=nil,role="",company=company}
			end
		end
	end
	if st.dir=="back" then
		for key,f in flown do
			if f.dir~="out" or f.profile==nil or #list>=Shuttle.MAX_PAX then continue end
			local tripKey=string.match(key,"^(.*):[^:]+$") or key
			if held[tripKey] then continue end -- they fly home with the founder's company booking
			local owner,tk=string.match(tripKey,"^(%d+):(.+)$")
			if owner and tk and itinHolds(tonumber(owner) or 0,tk) then continue end -- ... or will (his itinerary)
			if not current[tripKey] or st.cycle-f.cycle>=Shuttle.RETURN_CYCLES then
				f.dir="back";f.cycle=st.cycle
				table.insert(list,f)
			end
		end
	end
	-- forget trips that ended and whose travellers are home (or never flew)
	for key,f in flown do
		local tripKey=if f.profile then (string.match(key,"^(.*):[^:]+$") or key) else key
		if not current[tripKey] and (f.dir=="back" or f.profile==nil) and st.cycle-f.cycle>=1 then flown[key]=nil end
	end
	return list
end
local function publishPassengers(st: FP.State)
	local f=folder
	if not f then return end
	local old=f:FindFirstChild("Passengers")
	if old then old:Destroy() end
	local pax=Instance.new("Folder");pax.Name="Passengers"
	local legKey=st.dir..":"..st.cycle
	pax:SetAttribute("Leg",legKey)
	local temp=Instance.new("Folder")
	for i,p in Shuttle.passengersFor(st) do
		local ok,err=pcall(function()
			local m=Rig.build(temp,p.owner,700+i,p.role,CFrame.new(),p.profile)
			m:RemoveTag("CompanyEmployee")
			for _,d in m:GetDescendants() do
				if d:IsA("ProximityPrompt") then d:Destroy()
				elseif d:IsA("BasePart") then d.Anchored=d.Name=="HumanoidRootPart";d.CanCollide=false;d.CanTouch=false;d.CanQuery=false end
			end
			m.Name="Passenger"..i
			m:SetAttribute("PassengerName",tostring(p.profile.n or ""));m:SetAttribute("Company",p.company);m:SetAttribute("Leg",legKey)
			m.Parent=pax
		end)
		if not ok then warn("[Shuttle] building a passenger rig failed: "..tostring(err)) end
	end
	temp:Destroy()
	pax.Parent=f
end

------------------------------------------------------------------------------------------------ publish
local function publish(st: FP.State,t: number)
	local f=folder
	if not f then return end
	local leg=st.leg
	setAttr("Leg",st.dir);setAttr("Cycle",st.cycle);setAttr("LegStart",st.legStart)
	setAttr("Phase",st.phase);setAttr("PhaseStart",st.phaseStart);setAttr("PhaseEnd",st.phaseEnd)
	setAttr("Flight",leg.flight);setAttr("From",leg.from);setAttr("To",leg.to)
	local _,_,depOut=FP.nextLeg("out",t);local _,_,depBack=FP.nextLeg("back",t)
	setAttr("NextOut",depOut);setAttr("NextBack",depBack)
	setAttr("CrewState",FP.crewState(st))
end

------------------------------------------------------------------------------------------------ tickets
-- "abroad" ticket at a City Airport counter (paid, return included), "home" ticket at Port Meridian (free).
function Shuttle.ticket(s: any,destination: any): {[string]: any}
	local a=api
	if not a or not Shuttle.enabled() then return {ok=false,err="SHUTTLE_OFF"} end
	local player: Player=s.player
	if destination~="abroad" and destination~="home" then return {ok=false,err="BAD_INPUT"} end
	local trip=a.trips[player.UserId]
	local state=if trip then trip.state else "home"
	if state=="flying" then return {ok=false,err="BUSY"} end
	local from=if destination=="abroad" then "home" else "abroad"
	if state~=from then return {ok=false,err=if destination=="abroad" then "ALREADY_ABROAD" else "NOT_ABROAD"} end
	local _,root,humanoid=a.rootOf(player)
	if not root or not humanoid or humanoid.Health<=0 then return {ok=false,err="LOADING"} end
	local counters=if destination=="abroad" then CityPlan.AIRPORT.checkin else CityPlan.ABROAD.checkin
	if not nearAny(root.Position,counters,CityPlan.TRAVEL.checkinRadius) then return {ok=false,err="NOT_AT_CHECKIN"} end
	local dir=if destination=="abroad" then "out" else "back"
	local t=now()
	local _,legStart,departs,boardEnd=FP.nextLeg(dir,t)
	local leg=FP.leg(dir)
	local info={ok=true,flight=leg.flight,to=destination,gate=FP.GATE_NAME[dir],departs=departs,boardingStarts=legStart,boardingEnds=boardEnd,
		destination=if destination=="abroad" then "Port Meridian" else "City Airport"}
	local held=tickets[player.UserId]
	if held and held.to==destination then info.price=0;info.held=true;return info end
	local price=if destination=="abroad" then CityPlan.TRAVEL.ticket else 0
	if not Economy.spend(s,price,"travel") then return {ok=false,err="NO_MONEY"} end
	tickets[player.UserId]={to=destination,price=price,session=s,at=t}
	Session.markDirty(s,true)
	info.price=price
	return info
end

-- The instant flight (CityService.flight) uses a held ticket for the same destination instead of charging
-- again; restoreTicket puts it back when that flight is cancelled.
function Shuttle.takeTicket(player: Player,destination: string): Ticket?
	local t=tickets[player.UserId]
	if t and t.to==destination then tickets[player.UserId]=nil;return t end
	return nil
end
function Shuttle.restoreTicket(player: Player,ticket: Ticket)
	if tickets[player.UserId]==nil then tickets[player.UserId]=ticket end
end

------------------------------------------------------------------------------------------------ company bookings
local ROLES: {[string]: boolean}={marketer=true,engineer=true,researcher=true,curator=true}
local function cleanCompanions(list: any): {any}
	local out: {any}={}
	if typeof(list)~="table" then return out end
	for _,c in list do
		if #out>=2 then break end
		if typeof(c)~="table" or typeof(c.name)~="string" or c.name=="" or #c.name>40 then continue end
		local seed=if typeof(c.seed)=="number" and c.seed==c.seed and math.abs(c.seed)<1e12 then math.floor(math.abs(c.seed))%2147483647 else nil
		table.insert(out,{name=c.name,role=if typeof(c.role)=="string" and ROLES[c.role] then c.role else "marketer",seed=seed})
	end
	return out
end
-- Prepaid company booking for the founder's business trip (package "itinerary"): no check-in counter, price 0 (the
-- economy books the trip's flights in CompanyOps.tripPlan). opts = {to = "abroad" | "home", companions =
-- {{name, role?, seed?}}? (<= 2, they board with him), trip = CompanyOps trip key "client:left"?}. A ticket he already
-- holds for that direction becomes the company booking: a price he paid at the counter is refunded (refund(), P&L
-- "travel" - the company books the seat, he never pays twice for it) and it gets the companions. The shuttle is
-- public: a booking never runs out of seats. -> {ok, prepaid, flight, to, gate, departs, boardingStarts,
-- boardingEnds, destination, refunded} | {ok = false, err = SHUTTLE_OFF | BAD_INPUT | BUSY | ALREADY_ABROAD | NOT_ABROAD}
function Shuttle.book(s: any,opts: any): {[string]: any}
	local a=api
	if not a or not Shuttle.enabled() then return {ok=false,err="SHUTTLE_OFF"} end
	local o=if typeof(opts)=="table" then opts else {}
	local destination=o.to
	if destination~="abroad" and destination~="home" then return {ok=false,err="BAD_INPUT"} end
	local player: Player=s.player
	local trip=a.trips[player.UserId]
	local state=if trip then trip.state else "home"
	if state=="flying" then return {ok=false,err="BUSY"} end
	local from=if destination=="abroad" then "home" else "abroad"
	if state~=from then return {ok=false,err=if destination=="abroad" then "ALREADY_ABROAD" else "NOT_ABROAD"} end
	local tripKey: string?=if typeof(o.trip)=="string" and #o.trip>0 and #o.trip<=48 then o.trip else nil
	local companions=cleanCompanions(o.companions)
	local dir=if destination=="abroad" then "out" else "back"
	local t=now()
	local _,legStart,departs,boardEnd=FP.nextLeg(dir,t)
	local held=tickets[player.UserId]
	local refunded=0
	if held and held.to==destination then
		if held.price>0 then
			refunded=held.price
			refund(held.session or s,held.price)
			held.price=0
		end
		held.prepaid=true;held.companions=companions;held.trip=tripKey
	else
		tickets[player.UserId]={to=destination,price=0,session=s,at=t,prepaid=true,companions=companions,trip=tripKey}
	end
	return {ok=true,prepaid=true,flight=FP.leg(dir).flight,to=destination,gate=FP.GATE_NAME[dir],departs=departs,boardingStarts=legStart,boardingEnds=boardEnd,
		destination=if destination=="abroad" then "Port Meridian" else "City Airport",refunded=refunded}
end
-- Drop the founder's company booking if it was not used (a prepaid ticket goes, nothing to refund; a ticket he paid
-- for himself stays and only loses the companions).
function Shuttle.unbook(player: Player)
	local t=tickets[player.UserId]
	if not t or not t.trip and not t.prepaid then return end
	if t.prepaid and t.price<=0 then tickets[player.UserId]=nil
	else t.companions=nil;t.trip=nil end
end
-- The open booking / ticket of a player: {to, prepaid, companions, trip} (a copy) or nil
function Shuttle.booking(player: Player): {[string]: any}?
	local t=tickets[player.UserId]
	if not t then return nil end
	return {to=t.to,prepaid=t.prepaid==true,price=t.price,trip=t.trip,companions=if t.companions then table.clone(t.companions) else nil}
end
-- Did the travellers of trip `tripKey` (client..":"..left) of this founder already fly out on a shuttle leg?
function Shuttle.flownAhead(player: Player,tripKey: string): boolean
	local f=flown[player.UserId..":"..tripKey]
	return f~=nil and f.dir=="out"
end
-- On which leg did the travellers of trip `tripKey` of this founder fly last? -> (dir "out" | "back", cycle) or nil
function Shuttle.travellersLeg(player: Player,tripKey: string): (string?,number?)
	local key=player.UserId..":"..tripKey
	local best: Flown?=nil
	for k,f in flown do
		if f.profile~=nil and string.sub(k,1,#key+1)==key..":" and (best==nil or f.cycle>best.cycle or (f.cycle==best.cycle and f.dir=="back")) then best=f end
	end
	local f=best or flown[key]
	if not f then return nil,nil end
	return f.dir,f.cycle
end
-- The travellers of trip `tripKey` came home another way (with the founder in the company jet): no shuttle leg flies
-- them home again
function Shuttle.travellersHome(player: Player,tripKey: string)
	local key=player.UserId..":"..tripKey
	local cycle=FP.at(now()).cycle
	for k,f in flown do
		if f.owner==player.UserId and f.profile~=nil and f.dir=="out" and string.sub(k,1,#key+1)==key..":" then f.dir="back";f.cycle=cycle end
	end
end
-- the companions of a company booking count as flown in that direction (no second copy on another leg)
local function markCompanions(ticket: Ticket,player: Player,st: FP.State)
	if not ticket.trip then return end
	local key=player.UserId..":"..ticket.trip
	local companions: {any}=ticket.companions or {}
	local s=ticket.session
	local company=if s and typeof(s.data)=="table" and typeof(s.data.company)=="table" and typeof(s.data.company.name)=="string" then s.data.company.name else ""
	if st.dir=="out" then
		flown[key]={dir="out",cycle=st.cycle,owner=player.UserId,profile=nil,role="",company=company}
		for _,c in companions do
			flown[key..":"..c.role]={dir="out",cycle=st.cycle,owner=player.UserId,profile={n=c.name,s=c.seed},role=c.role,company=company}
		end
	else
		for k,f in flown do
			if f.owner==player.UserId and f.profile~=nil and string.sub(k,1,#key+1)==key..":" then
				for _,c in companions do
					if c.role==f.role then f.dir="back";f.cycle=st.cycle end
				end
			end
		end
	end
end

-- ... and they join the leg's Passengers (the rigs ShuttlePassengers walks off at the destination, like the field staff)
local function boardCompanions(ticket: Ticket,player: Player,st: FP.State)
	local f=folder
	local list=ticket.companions
	if not f or not list or #list==0 then return end
	local pax=f:FindFirstChild("Passengers")
	local legKey=st.dir..":"..st.cycle
	if not pax or pax:GetAttribute("Leg")~=legKey then return end
	local s=ticket.session
	local company=if s and typeof(s.data)=="table" and typeof(s.data.company)=="table" and typeof(s.data.company.name)=="string" then s.data.company.name else ""
	local n=#pax:GetChildren()
	local temp=Instance.new("Folder")
	for i,c in list do
		local ok,err=pcall(function()
			local m=Rig.build(temp,player.UserId,760+n+i,c.role,CFrame.new(),{n=c.name,s=c.seed})
			m:RemoveTag("CompanyEmployee")
			for _,d in m:GetDescendants() do
				if d:IsA("ProximityPrompt") then d:Destroy()
				elseif d:IsA("BasePart") then d.Anchored=d.Name=="HumanoidRootPart";d.CanCollide=false;d.CanTouch=false;d.CanQuery=false end
			end
			m.Name="Passenger"..(n+i)
			m:SetAttribute("PassengerName",c.name);m:SetAttribute("Company",company);m:SetAttribute("Leg",legKey);m:SetAttribute("CompanionOf",player.UserId)
			m.Parent=pax
		end)
		if not ok then warn("[Shuttle] building a companion rig failed: "..tostring(err)) end
	end
	temp:Destroy()
end

------------------------------------------------------------------------------------------------ boarding
local function hide(trip: any,humanoid: Humanoid?)
	if humanoid then trip.display=humanoid.DisplayDistanceType;humanoid.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None end
end
local function restore(trip: any)
	local character: Model?=trip.character
	local humanoid=if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid and trip.display then humanoid.DisplayDistanceType=trip.display end
end
local function streamAsync(player: Player,pos: Vector3)
	local ok,err=pcall(function() player:RequestStreamAroundAsync(pos,CityPlan.TRAVEL.streamTimeout) end)
	if not ok then warn("[Shuttle] RequestStreamAroundAsync failed for "..player.Name..": "..tostring(err)) end
end
local function valid(trip: any): boolean
	local a=api
	if not a then return false end
	local player: Player=trip.player
	local root: BasePart?=trip.root
	return a.trips[player.UserId]==trip and player.Character==trip.character and root~=nil and root.Parent~=nil
end
-- Board the shuttle leg `key` (dir..":"..cycle). Internal: all checks done by the caller.
local function doBoard(s: any,ticket: Ticket,st: FP.State,character: Model,root: BasePart,humanoid: Humanoid)
	local a=api :: Api
	local player: Player=s.player
	local key=st.dir..":"..st.cycle
	local trip={player=player,state="flying",to=ticket.to,character=character,root=root,wasAnchored=root.Anchored,releaseAt=math.huge,
		kind="shuttle",price=ticket.price,session=s,leg=key,dir=st.dir,cycle=st.cycle,moved=false,arriving=false,arrived=false,display=nil,
		companions=ticket.companions,booking=ticket.trip}
	tickets[player.UserId]=nil
	markCompanions(ticket,player,st)
	boardCompanions(ticket,player,st)
	a.trips[player.UserId]=trip
	a.setState(player,"flying")
	player:SetAttribute("ShuttleLeg",key)
	root.Anchored=true
	hide(trip,humanoid)
	local hold=if st.dir=="out" then FP.HOLD.home else FP.HOLD.abroad
	character:PivotTo(hold)
	Session.markDirty(s,true)
	-- pre-stream the take-off roll (the camera follows the aircraft down the runway)
	task.spawn(streamAsync,player,if st.dir=="out" then Vector3.new(0,CityPlan.GROUND,(CityPlan.AIRPORT.runway.z1+CityPlan.AIRPORT.runway.z2)/2) else Vector3.new(-250,CityPlan.GROUND,7555))
	return trip
end
function Shuttle.board(s: any): {[string]: any}
	local a=api
	if not a or not Shuttle.enabled() then return {ok=false,err="SHUTTLE_OFF"} end
	local player: Player=s.player
	local trip=a.trips[player.UserId]
	if trip and trip.state=="flying" then return {ok=false,err="BUSY"} end
	local ticket=tickets[player.UserId]
	if not ticket then return {ok=false,err="NO_TICKET"} end
	local character,root,humanoid=a.rootOf(player)
	if not character or not root or not humanoid or humanoid.Health<=0 then return {ok=false,err="LOADING"} end
	if humanoid.SeatPart then return {ok=false,err="LEAVE_VEHICLE"} end
	local dir=if ticket.to=="abroad" then "out" else "back"
	local gates=if dir=="out" then FP.HOME_GATES else FP.PM_GATES
	if not nearAny(root.Position,gates,FP.GATE_RADIUS) then return {ok=false,err="NOT_AT_GATE"} end
	local t=now()
	local st=FP.at(t)
	if st.dir~=dir or st.phase~="boarding" then
		local _,legStart,departs=FP.nextLeg(dir,t)
		return {ok=false,err="NOT_BOARDING",boardingStarts=legStart,departs=departs,flight=FP.leg(dir).flight}
	end
	doBoard(s,ticket,st,character,root,humanoid)
	return {ok=true,flight=st.leg.flight,departs=st.legStart+st.leg.phases.pushback.t0,leg=st.dir..":"..st.cycle,to=ticket.to}
end
-- End of boarding: every ticket holder of this leg standing at the gate is boarded automatically.
local function autoBoard(st: FP.State)
	local a=api
	if not a then return end
	for userId,ticket in tickets do
		local dir=if ticket.to=="abroad" then "out" else "back"
		if dir~=st.dir then continue end
		local s=ticket.session
		local player: Player?=if s then s.player else nil
		if not player or s.closed then tickets[userId]=nil;continue end
		local trip=a.trips[userId]
		if trip and trip.state=="flying" then continue end
		local character,root,humanoid=a.rootOf(player)
		if character and root and humanoid and humanoid.Health>0 and not humanoid.SeatPart
			and nearAny(root.Position,if dir=="out" then FP.HOME_GATES else FP.PM_GATES,FP.GATE_RADIUS) then
			doBoard(s,ticket,{cycle=st.cycle,dir=st.dir,leg=st.leg,tau=st.tau,phase="boarding",legStart=st.legStart,phaseStart=st.phaseStart,phaseEnd=st.phaseEnd},character,root,humanoid)
		end
	end
end

------------------------------------------------------------------------------------------------ ride
local function arrive(trip: any)
	local a=api
	if not a or trip.arriving then return end
	trip.arriving=true
	local player: Player=trip.player
	local dest=if trip.to=="abroad" then CityPlan.ABROAD.arrival else CityPlan.AIRPORT.arrival
	if trip.kind=="heli" then dest=trip.dest end
	task.spawn(function()
		streamAsync(player,dest.Position)
		if not valid(trip) then return end -- respawned / left meanwhile: drop() handled it
		local character: Model=trip.character
		local root: BasePart=trip.root
		character:PivotTo(dest)
		root.Anchored=trip.wasAnchored
		restore(trip)
		trip.arrived=true
		local wasShuttle=trip.kind=="shuttle"
		-- state first, then ShuttleLeg: the client reads TravelState when the ride ends (welcome message)
		if trip.to=="abroad" then trip.state="abroad";trip.kind=nil;a.setState(player,"abroad")
		else a.trips[player.UserId]=nil;a.setState(player,"home") end
		if wasShuttle then player:SetAttribute("ShuttleLeg",nil) end
		if trip.session then Session.markDirty(trip.session,true) end
	end)
end
local function moveHold(trip: any)
	trip.moved=true
	local player: Player=trip.player
	local target=if trip.to=="abroad" then FP.HOLD.abroad else FP.HOLD.home
	task.spawn(function()
		streamAsync(player,(if trip.to=="abroad" then FP.PM_STAND else FP.HOME_STAND).Position)
		if not valid(trip) or trip.arriving then return end
		local character: Model=trip.character
		character:PivotTo(target)
	end)
end

------------------------------------------------------------------------------------------------ helicopter
Shuttle.heliTimes=FP.heliTimes
function Shuttle.heliInfo(): (boolean,Vector3?,Vector3?)
	if not heli.fromPad or not heli.toPad or not heli.fromPad.Parent or not heli.toPad.Parent then findPads() end
	local fp,tp=heli.fromPad,heli.toPad
	if not fp or not tp then return false,nil,nil end
	return true,padTop(fp),padTop(tp)
end
local function shopOwns(player: Player,pass: string): boolean
	local ok,mod=pcall(function(): any return require(script.Parent.ShopService) end)
	local shop: any=if ok then mod else nil
	if typeof(shop)~="table" or typeof(shop.owns)~="function" then return false end
	local okOwns,owned=pcall(shop.owns,player,pass)
	return okOwns and owned==true
end
Shuttle.shopOwns=shopOwns
-- Arrival frames: next to the airport helipad gate / in the Meridian Grand lobby (the roof pad has no way down).
function Shuttle.heliArrival(to: string): CFrame
	if to=="hotel" then
		local hotel=CityPlan.INTL_HOTEL
		return if hotel then hotel.lobby else CityPlan.ABROAD.arrival
	end
	local ok,from=Shuttle.heliInfo()
	local p=if ok and from then from else Vector3.new(310,CityPlan.GROUND+1,7648)
	return CFrame.lookAt(Vector3.new(p.X-28,CityPlan.GROUND+3.5,p.Z+44),Vector3.new(p.X-28,CityPlan.GROUND+3.5,p.Z+80))
end
function Shuttle.heli(s: any,destination: any): {[string]: any}
	local a=api
	if not a then return {ok=false,err="HELI_UNAVAILABLE"} end
	if destination~="hotel" and destination~="airport" then return {ok=false,err="BAD_INPUT"} end
	local player: Player=s.player
	local trip=a.trips[player.UserId]
	local state=if trip then trip.state else "home"
	if state=="flying" then return {ok=false,err="BUSY"} end
	if state~="abroad" then return {ok=false,err="HELI_ABROAD_ONLY"} end
	local okPads,fromPad,toPad=Shuttle.heliInfo()
	if not okPads or not fromPad or not toPad then return {ok=false,err="HELI_UNAVAILABLE"} end
	local character,root,humanoid=a.rootOf(player)
	if not character or not root or not humanoid or humanoid.Health<=0 then return {ok=false,err="LOADING"} end
	if humanoid.SeatPart then return {ok=false,err="LEAVE_VEHICLE"} end
	local hotel=CityPlan.INTL_HOTEL
	local startAt: Vector3=if destination=="hotel" then fromPad elseif hotel then hotel.lobby.Position else toPad
	if flat(root.Position,startAt)>Shuttle.HELI_RADIUS or math.abs(root.Position.Y-startAt.Y)>16 then return {ok=false,err="NOT_AT_HELIPAD"} end
	local t=now()
	if heli.busyUntil>t then return {ok=false,err="HELI_BUSY",seconds=math.ceil(heli.busyUntil-t)} end
	local pass=shopOwns(player,"limo")
	local price=if pass then 0 else Shuttle.HELI_FEE
	if not Economy.spend(s,price,"travel") then return {ok=false,err="NO_MONEY",price=price} end
	-- The helicopter waits on the airport pad: to the hotel = ride A->B then an empty ferry back; to the airport
	-- = ferry A->B to pick the passenger up, then the ride B->A. (Shuttle.heliTimes, the same on the client.)
	local ride0,ride1,busy=Shuttle.heliTimes(destination,t,fromPad,toPad)
	local dest=Shuttle.heliArrival(destination)
	local hold=if destination=="hotel" then fromPad else toPad
	local ride={player=player,state="flying",to="abroad",character=character,root=root,wasAnchored=root.Anchored,releaseAt=math.huge,
		kind="heli",price=price,session=s,dest=dest,finishAt=ride1,arriving=false,arrived=false,display=nil}
	a.trips[player.UserId]=ride
	a.setState(player,"flying")
	root.Anchored=true
	hide(ride,humanoid)
	character:PivotTo(CFrame.new(hold.X,CityPlan.GROUND-40,hold.Z))
	heli.busyUntil=busy
	setAttr("HeliStart",t);setAttr("HeliMode",destination);setAttr("HeliRider",player.UserId)
	Session.markDirty(s,true)
	task.spawn(streamAsync,player,dest.Position)
	return {ok=true,seconds=ride1-t,rideStart=ride0,price=price,pass=pass,destination=if destination=="hotel" then "Meridian Grand Hotel" else "Port Meridian Airport",start=t}
end

------------------------------------------------------------------------------------------------ drop / status
-- A respawn (reason "respawn") or leaving ("leave"): cancels the ride (refund unless arrived), clears tickets.
-- Called by CityService BEFORE it resets the trip.
function Shuttle.drop(player: Player,reason: string)
	local a=api
	local ticket=tickets[player.UserId]
	if ticket then
		-- an unused paid ticket survives a respawn at home; leaving refunds it; a "home" ticket is moot after a respawn
		if reason=="leave" then refund(ticket.session,ticket.price);tickets[player.UserId]=nil
		elseif ticket.to=="home" then tickets[player.UserId]=nil end
	end
	if not a then return end
	local trip=a.trips[player.UserId]
	if trip and (trip.kind=="shuttle" or trip.kind=="heli") and not trip.arrived then
		refund(trip.session,trip.price or 0)
		local root: BasePart?=trip.root
		if root and root.Parent then root.Anchored=trip.wasAnchored end
		restore(trip)
		trip.arrived=true -- never processed again
		if trip.kind=="shuttle" then pcall(function() player:SetAttribute("ShuttleLeg",nil) end) end
	end
end
function Shuttle.status(player: Player): {[string]: any}
	local t=now()
	local st=FP.at(t)
	local ticket=tickets[player.UserId]
	local _,_,depOut=FP.nextLeg("out",t);local _,_,depBack=FP.nextLeg("back",t)
	local okPads=Shuttle.heliInfo()
	return {shuttle=Shuttle.enabled(),phase=st.phase,leg=st.dir,flight=st.leg.flight,nextOut=depOut,nextBack=depBack,
		ticketTo=if ticket then ticket.to else nil,heli=okPads,heliFee=Shuttle.HELI_FEE,heliPass=shopOwns(player,"limo")}
end
function Shuttle.state(): FP.State return FP.at(now()) end

------------------------------------------------------------------------------------------------ tick
function Shuttle.tick(_dt: number)
	local a=api
	if not a or not folder then return end
	local t=now()
	local st=FP.at(t)
	local key=st.dir..":"..st.cycle
	local crewState=FP.crewState(st)
	if key~=lastKey or st.phase~=lastPhase or crewState~=lastCrew then
		lastKey=key;lastPhase=st.phase;lastCrew=crewState
		publish(st,t)
	end
	-- field staff of this leg: once, when its boarding starts (or at start-up during a boarding)
	if st.phase=="boarding" and key~=paxKey then
		paxKey=key
		publishPassengers(st)
	end
	-- the helipads may be built after the shuttle started (or stream in later on a test server): retry
	local f=folder :: Folder
	if f:GetAttribute("HeliAvailable")~=true and t>=nextPadSearch then
		nextPadSearch=t+5
		local okPads,fromPad,toPad=Shuttle.heliInfo()
		if okPads and fromPad and toPad then
			f:SetAttribute("HeliFromPad",fromPad);f:SetAttribute("HeliToPad",toPad);f:SetAttribute("HeliAvailable",true)
		end
	end
	-- auto-boarding once per leg, when boarding has ended (doors closing)
	if Shuttle.enabled() and st.phase~="boarding" and not autoDone[key] and st.tau<st.leg.phases.pushback.t0 then
		autoDone[key]=true
		autoBoard(st)
	end
	-- riders
	for _,trip in a.trips do
		if trip.arrived or trip.arriving then continue end
		if trip.kind=="shuttle" then
			if not valid(trip) then continue end -- CharacterAdded / closing calls drop()
			local leg=FP.leg(trip.dir)
			local start=FP.legStart(trip.dir,trip.cycle)
			local cruise=leg.phases.cruise
			if not trip.moved and t>=start+(cruise.t0+cruise.t1)/2 then moveHold(trip) end
			if t>=start+leg.phases.deboarding.t0 then arrive(trip) end
		elseif trip.kind=="heli" then
			if not valid(trip) then continue end
			if t>=trip.finishAt then arrive(trip) end
		end
	end
	-- forget old auto-board keys
	local n=0
	for _ in autoDone do n+=1 end
	if n>8 then table.clear(autoDone);autoDone[key]=true end
end

------------------------------------------------------------------------------------------------ init
function Shuttle.init(cityApi: Api)
	api=cityApi
	local old=ReplicatedStorage:FindFirstChild("Shuttle")
	if old then old:Destroy() end
	local f=Instance.new("Folder");f.Name="Shuttle"
	local C=FP.CONFIG
	f:SetAttribute("Enabled",Shuttle.ENABLED);f:SetAttribute("Interval",FP.interval());f:SetAttribute("Epoch",C.epoch)
	f:SetAttribute("Kind",C.kind);f:SetAttribute("Scale",C.scale);f:SetAttribute("Airline",C.airline)
	f:SetAttribute("Ticket",CityPlan.TRAVEL.ticket);f:SetAttribute("HeliFee",Shuttle.HELI_FEE)
	folder=f
	buildCrew(f)
	local okPads,fromPad,toPad=Shuttle.heliInfo()
	f:SetAttribute("HeliAvailable",okPads)
	if fromPad and toPad then f:SetAttribute("HeliFromPad",fromPad);f:SetAttribute("HeliToPad",toPad) end
	f.Parent=ReplicatedStorage
	-- gate prompts
	local gates=workspace:FindFirstChild("ShuttleGates")
	if gates then gates:Destroy() end
	local g=Instance.new("Folder");g.Name="ShuttleGates"
	gatePrompt(g,"GateBoardHome",findHomeDesk(),"home","Gate "..FP.GATE_NAME.out.." · "..C.flights.out.." to Port Meridian")
	gatePrompt(g,"GateBoardAbroad",FP.PM_GATES[1],"abroad",C.flights.back.." to City Airport")
	g.Parent=workspace
	lastKey="";lastPhase="";lastCrew="";nextPadSearch=0;paxKey=""
	table.clear(flown)
	table.clear(autoDone)
	local st=FP.at(now())
	autoDone[st.dir..":"..st.cycle]=st.phase~="boarding" -- a leg already past boarding at start-up boards nobody
	Shuttle.tick(0)
end
-- Formatting helper for messages (server-side notices).
function Shuttle.clock(serverTime: number): string
	local sec=math.max(0,math.floor(serverTime-now()))
	return Format.duration(sec)
end
return Shuttle
