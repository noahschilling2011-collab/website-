--!strict
-- DriverService (package "drivers"): company chauffeurs, the founder's rides, visible fleet rides of the field staff
-- and the VIP limousine service in Port Meridian (user requests 2, 3, 21, 22, 23b, part of 24).
-- Pre-wired by the integration lead: Main.server calls init() once (after JetService.init, before SessionService.init)
-- and tick(dt) in its campus loop (every 0.05-0.25 s, inside a pcall).
--
-- STABLE API (for the itinerary package; also documented in agents/drivers/API.md):
--   DriverService.request(player, {to = placeId, passengers = {{name: string, role: string?, seed: number?}}?,
--       purpose = "phone" | "itinerary", wait = seconds?, onArrive = function(rideId: string, placeId: string)?})
--       -> {ok, rideId, eta, arriveEta, queued, pickup, pickupName, pickupAt, to, toName, err}
--       (pickupAt = the pick-up's name inside a sentence: "the HQ entrance", "City Airport (departures)")
--       The nearest pick-up place to the founder (his HQ entrance on his own plot, the City Airport kerbs, a Business
--       City building; abroad the limousine stand - also from anywhere in the arrivals hall / plaza -, the Meridian
--       Grand, a client tower, the airport kerb) is where the car comes to; eta = seconds until it waits there,
--       arriveEta = estimated seconds until the drop-off if he gets in at once. queued = true: every car is out, the
--       ride starts by itself when one is back (eta counts that in).
--       At home the car is a company car with a company driver (exactly CompanyOps' paid drivers: Ops.DRIVER, 1 from
--       stage 2, 2 from stage 4); abroad the VIP limousine service (no company driver, no cost): one limousine waits
--       at bay 1 of the stand, LIMO_FLEET more come from the service's garage in the east tunnel; bay 1 is never
--       booked twice (a second booking there waits for the next car, honest ETA).
--       passengers (<= 2) sit in the back with the founder (rig templates). wait (<= 600 s): the car waits at the
--       destination before it drives back. Destinations: every place of DriverService.places except pm_limo (a
--       pick-up point only). Errors: "LOADING", "NO_COMPANY", "NO_DRIVER" (garage stage), "FLYING", "BAD_PLACE",
--       "FLIGHT_REQUIRED" (destination in the other city), "TOO_FAR" (no pick-up place near the founder),
--       "ALREADY_THERE", "ALREADY_RIDING" (a ride or queued request of his in this city is still open), "COOLDOWN",
--       "LEAVE_VEHICLE" (sitting in a car), "BAD_INPUT".
--   DriverService.cancel(rideId) -> (boolean, string?) - queued: dropped; driver still walking to the car: gone;
--       on the way / waiting: the car turns back (the limousine at the stand simply stays there); riding: the founder
--       gets out right there (kerb side, a spot free of props) and the car drives on empty (before it pulled away:
--       it stays / turns back). Returning cars cannot be cancelled ("RETURNING").
--   DriverService.free(player) -> (count, reason?) - free company drivers now (abroad: free limousines);
--       reason "NO_DRIVER" | "ALL_BUSY" | "FLYING" | "LOADING" | "NO_COMPANY" when count is 0.
--   DriverService.places(zone?, player?) -> {{id, name, short, zone, kind, clientId?}} (DrivePlan.places; with a
--       player the home list starts with his HQ entrance)
--   DriverService.onArrive(fn: (player, rideId, placeId) -> ()) -> disconnect(); DriverService.arrived
--       (BindableEvent, same arguments). Fires once per ride, right after the founder was placed at the drop-off.
--       A per-request onArrive(rideId, placeId) fires first.
--   DriverService.status(player) -> {state = "none" | "queued" | "coming" | "waiting" | "riding", rideId?, eta?,
--       pickup?, pickupName?, pickupAt?, to?, toName?, drivers, free} (rides of the city he is in; none in flight)
--   DriverService.onTripAction(action, handler(session, payload) -> result) - the remote TripAction is bound here;
--       action "ride" belongs to this service, every other action (go, cancel, leave, status, ...) is passed to the
--       handler the itinerary package registers (each action has its own rate limit).
-- Remote TripAction {action = "ride", op = "request" (to) | "board" | "cancel" | "status" | "places"}.
-- Phone: PhoneService.onAction("driver") answers the Driver contact with the honest state and sends the founder's
-- client the destination sheet (Notify DRIVE_SHEET; the phone's dial screen shows only text).
--
-- What is published (ReplicatedStorage.CompanyDrivers, written on change only, never per frame):
--   Drivers_<userId> (per company): attributes Owner, Company, Livery, Plot, Tier, Drivers (= paid drivers),
--     DriverName<i>; children Driver<i> (rig templates: "Driver" uniform with cap) and the company's rides. When the
--     founder leaves, open rides finish their current leg empty in "Drivers_<userId>_left<n>" (attribute Detached).
--   Limo: the limousine service's rides, attributes Stand ("idle" = the limousine waits at bay 1 | "held" = a ride
--     has bay 1 | "empty") and StandRide (id); Chauffeur: its chauffeur template.
--   Ride_<n> folders: attributes Id, Kind ("founder" | "field" | "guest" | "limo"), Look, Zone, Plot, Driver (index,
--     0 = none), Plan (DrivePlan.encode: legs + start times + seat occupants), State ("coming" | "waiting" |
--     "riding" | "returning" | "driving"), Rider (userId while he is booked / on board, else 0), Pickup, To, ToName,
--     WaitUntil, Companions / Guests (counts), Purpose; children C1..C2 / G1..G2 (rig templates).
--   Clients (DriveController) pose the cars from the plan with workspace:GetServerTimeNow() - nothing moves over the
--   network per frame. NPC passengers get in / out at the places between two legs (the client shows them standing
--   at the place's door while the car waits). The server holds the riding founder's character (root anchored,
--   below the road under the car, moved once per second so streaming follows the ride) and places it at the drop-off.
-- Visible fleet rides: when a B2B trip of empire.deals.tripList starts or ends (CompanyOps), a FREE company driver
-- takes the field rep (+ engineer) from the HQ entrance to the client's Business City building / the City Airport
-- departures kerb and fetches him from there / arrivals when the trip ends (user request 22); a hosted visit's client
-- team is fetched / brought back the same way. Without a free driver (or with a founder booking waiting) the trip
-- stays data. Purely visual: nothing here touches money, trips or saved data (CompanyOps pays the drivers, the
-- leases and the trips); a busy driver only delays the founder's next ride (honest ETA).
-- Working hours (request 2): the drivers are an on-call service (CompanyOps pays a fixed daily wage); 06-22 they
-- wait under the entrance canopy, at night in the drivers' room (DrivePlan.walkAt: a longer walk to the car).
-- The garage barrier opens for the cars through DoorService.requestNPC (an invisible "DriverProxy" support NPC).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Prompts = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local Drive = require(Shared.DrivePlan)
local Ops = require(Shared.CompanyOps)
local CityPlan = require(Shared.Config.CityPlan)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local CompanyConfig = require(Shared.Config.CompanyConfig)
local CampusMath = require(Shared.CampusMath)
local Remote = require(script.Parent.Parent.Lib.Remote)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local Session = require(script.Parent.SessionService)
local Rig = require(script.Parent.EmployeeRigDesign)
local Plot = require(script.Parent.PlotService)
local City = require(script.Parent.CityService)
local Phone = require(script.Parent.PhoneService)
local Vehicles = require(script.Parent.VehicleService)
local Doors = require(script.Parent.DoorService)

local DriverService = {}
DriverService.DRIVERS = { 9301, 9343 } -- CampusMath.staffName indices with the owner's userId: the same names on every server
DriverService.CHAUFFEUR = 9407 -- the limousine service's chauffeur (owner 0)
DriverService.SCAN = 1 -- seconds between looks at every company (drivers paid, trips)
DriverService.FOCUS_EVERY = 1 -- seconds between two moves of a riding founder's held character
DriverService.STREAM_AHEAD = 8 -- seconds before the drop-off: ask Roblox to stream the destination
DriverService.ALIGHT = 1.2 -- seconds after the car stopped: the founder stands at the door
DriverService.DROP_PAUSE = 4 -- seconds the car stands at the drop-off before it leaves (+ wait)
DriverService.FIELD_PAUSE = 6 -- seconds a driver waits for the field rep / client guests to get in or out
DriverService.REQUEST_GAP = 3 -- seconds between two ride requests of one founder
DriverService.MAX_PASSENGERS = 2
DriverService.MAX_WAIT = 600
DriverService.HOLD_DEPTH = 60 -- the held character stays this far below the road
DriverService.BARRIER_LEAD = 3 -- seconds before a car reaches the garage barrier: ask DoorService to open it
DriverService.BARRIER_AFTER = 2
DriverService.PROMPT_COOLDOWN = 1
DriverService.BACK_RETRY = 60 -- seconds a field trip's back ride waits for a free driver (then it stays data)
DriverService.LIMO_FLEET = 3 -- limousine rides on the road at once (+ the one waiting at the stand)
DriverService.LIMO_CLEAR = 4 -- seconds after the stand car pulled away: bay 1 is free for the next limousine
DriverService.LIMO_FROM_DEPOT = 2 -- seconds until a limousine leaves the service's garage
DriverService.SPOT_BOX = Vector3.new(3, 4.6, 3) -- "let me out here": the spot must be free of props (root at +3)
-- per-player rate limits of TripAction (the remote itself has a generous outer limit): ride bookings / boarding /
-- cancelling, ride status / destination list, and every itinerary action on its own
DriverService.LIMITS = { write = { 6, 2 }, read = { 12, 4 }, other = { 8, 3 } } :: { [string]: { number } }

type Hold = { character: Model, root: BasePart, wasAnchored: boolean, display: any }
type Ride = {
	id: string,
	n: number,
	kind: string,
	userId: number,
	zone: string,
	plot: number?,
	look: string,
	driver: number,
	segs: { Drive.Seg },
	folder: Folder,
	state: string,
	rider: Player?,
	pickup: string?,
	to: string?,
	purpose: string,
	wait: number,
	waitUntil: number,
	hold: Hold?,
	onArrive: ((string, string) -> ())?,
	prompt: Part?,
	focusAt: number,
	streamed: boolean,
	dropped: boolean,
	borrowed: string?,
	untilT: number?,
	passengers: number,
	barriers: { number },
	barrierAsk: number,
	holdsStand: boolean, -- limousine: this ride has bay 1 of the VIP stand
	reposition: boolean, -- limousine without a booking driving from the garage to the stand
}
type Request = { player: Player, to: string, pickup: string, passengers: any, purpose: string, wait: number, onArrive: ((string, string) -> ())?, at: number }
type TripInfo = { trip: any, people: any, ride: string? }
type Pending = { key: string, info: TripInfo, after: number, deadline: number }
type Company = {
	userId: number,
	player: Player,
	session: any,
	folder: Folder,
	plot: number?,
	tier: number,
	drivers: number,
	company: string,
	livery: Color3,
	rides: { [string]: Ride },
	queue: Request?,
	trips: { [string]: TripInfo }?,
	seq: number,
	proxy: Model?,
	requestAt: number,
	detached: boolean,
	pending: { Pending }, -- back rides that wait until the travellers have arrived at the HQ
}

local root: Folder? = nil
local limoFolder: Folder? = nil
local companies: { [number]: Company } = {}
local detached: { Company } = {}
local detachSeq = 0
local limoRides: { [string]: Ride } = {}
local limoQueue: { Request } = {}
local limoRequestAt: { [number]: number } = {}
local limoSeq = 0
local standState = "idle" -- "idle" | "held" | "empty"
local standRide: string? = nil
local arriveFns: { (Player, string, string) -> () } = {}
local tripHandlers: { [string]: (any, any) -> any } = {}
local limiters: { [string]: RateLimiter.Limiter } = {}
local promptAt: { [number]: number } = {}
local scanAcc = 0
local arrivedEvent = Instance.new("BindableEvent")
arrivedEvent.Name = "DriverArrived"
DriverService.arrived = arrivedEvent
DriverService.companies = companies
DriverService.limoRides = limoRides
DriverService.limoQueue = limoQueue
DriverService.detached = detached

local function now(): number
	return workspace:GetServerTimeNow()
end
local function setAttr(inst: Instance, name: string, value: any)
	if inst:GetAttribute(name) ~= value then inst:SetAttribute(name, value) end
end
local function notice(player: Player?, text: string)
	if not player then return end
	pcall(function() Remote.fire(player, "Notify", "CAMPUS_NOTICE", { text = text }) end)
end
local function rootOf(player: Player): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	local r = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local h = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if character and r and r:IsA("BasePart") then return character, r, h end
	return nil, nil, nil
end
local function companyOf(s: any): (string, Color3)
	local c = if s and typeof(s.data) == "table" then s.data.company else nil
	local name = if typeof(c) == "table" and typeof(c.name) == "string" and c.name ~= "" then c.name else "Company"
	local def = if typeof(c) == "table" and typeof(c.color) == "string" then CompanyConfig.getColor(c.color) else nil
	local livery = if def then Color3.fromRGB(def.rgb[1], def.rgb[2], def.rgb[3]) else Color3.fromRGB(24, 120, 128)
	return name, livery
end
local function empireOf(s: any): any
	if not s or typeof(s.data) ~= "table" or not s.data.company then return nil end
	local e = s.data.empire
	return if typeof(e) == "table" then e else nil
end
local function driverName(c: Company, i: number): string
	return CampusMath.staffName(DriverService.DRIVERS[i] or DriverService.DRIVERS[1], c.userId)
end
local function firstName(name: string): string
	return string.match(name, "^(%S+)") or name
end
local function stageName(i: number): string
	local o = EmpireConfig.OFFICES[i]
	return if o then o.name else "the next office"
end
-- the city the founder is in for rides: "home" | "abroad" | nil (in flight)
local function zoneOf(player: Player): string?
	local st = City.state(player)
	if st == "flying" then return nil end
	return if st == "abroad" then "abroad" else "home"
end
local function wbOf(r: Ride): number
	return Drive.WHEELBASE[r.look] or Drive.WHEELBASE.fleet
end

------------------------------------------------------------------------------------------------ rigs
-- NPC rig template (no tag, no talk prompt, not in workspace = no physics), cloned and posed by the clients.
local function template(parent: Instance, owner: number, index: number, role: string, profile: any, name: string, badge: string): Model?
	local temp = Instance.new("Folder")
	local ok, res = pcall(function(): Model
		local m = Rig.build(temp, owner, index, role, CFrame.new(), profile)
		m:RemoveTag("CompanyEmployee")
		for _, d in m:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = d.Name == "HumanoidRootPart"; d.CanCollide = false; d.CanTouch = false; d.CanQuery = false
			elseif d:IsA("TextLabel") and d.Parent and d.Parent.Name == "EmployeeBadge" then
				d.Text = badge
			end
		end
		m.Name = name
		m.Parent = parent
		return m
	end)
	temp:Destroy()
	if not ok then warn("[Drivers] building a rig failed: " .. tostring(res)); return nil end
	return res
end
local function buildDrivers(c: Company)
	for _, ch in c.folder:GetChildren() do
		if ch:IsA("Model") and string.match(ch.Name, "^Driver%d$") then ch:Destroy() end
	end
	for i = 1, c.drivers do
		local name = driverName(c, i)
		local m = template(c.folder, c.userId, DriverService.DRIVERS[i], "driver", { n = name }, "Driver" .. i, name .. "\nDriver · " .. c.company)
		if m then m:SetAttribute("DriverName", name); m:SetAttribute("Role", "Driver") end
		setAttr(c.folder, "DriverName" .. i, name)
	end
	for i = c.drivers + 1, #DriverService.DRIVERS do setAttr(c.folder, "DriverName" .. i, nil) end
end
local function companionTemplates(folder: Folder, owner: number, list: any, prefix: string, company: string, max: number): number
	local n = 0
	if typeof(list) ~= "table" then return 0 end
	for _, p in list do
		if n >= max then break end
		if typeof(p) ~= "table" or typeof(p.name) ~= "string" or p.name == "" or #p.name > 40 then continue end
		local role = if p.role == "researcher" or p.role == "engineer" or p.role == "curator" or p.role == "marketer" then p.role else "marketer"
		local profile: { [string]: any } = { n = p.name }
		if typeof(p.seed) == "number" and p.seed == p.seed then profile.s = math.floor(math.abs(p.seed)) % 2147483647 end
		n += 1
		local badge = if typeof(p.badge) == "string" then p.badge else p.name .. "\n" .. company
		local m = template(folder, owner, (if prefix == "G" then 9500 else 780) + n, role, profile, prefix .. n, badge)
		if m then m:SetAttribute("CompanionName", p.name) else n -= 1 end
	end
	return n
end

------------------------------------------------------------------------------------------------ rides: publish
local function publishRide(r: Ride)
	local f = r.folder
	setAttr(f, "Id", r.id); setAttr(f, "Kind", r.kind); setAttr(f, "Look", r.look); setAttr(f, "Zone", r.zone)
	setAttr(f, "Plot", r.plot or 0); setAttr(f, "Driver", r.driver); setAttr(f, "Rider", if r.rider then r.rider.UserId else 0)
	setAttr(f, "Pickup", r.pickup or ""); setAttr(f, "To", r.to or "")
	local toPlace = if r.to then Drive.place(r.to, r.plot) else nil
	setAttr(f, "ToName", if toPlace then toPlace.name else "")
	setAttr(f, "WaitUntil", r.waitUntil); setAttr(f, "Until", r.untilT)
	setAttr(f, "Purpose", if r.reposition then "reposition" else r.purpose)
	setAttr(f, "State", r.state)
	setAttr(f, "Plan", Drive.encode(r.segs)) -- last: clients rebuild the car pose from it
end
local function legEnd(r: Ride): number
	return Drive.planEnd(r.segs, r.plot) or now()
end
-- garage barrier pass times of every segment that runs through the ramp head (plot-local z -140)
local function barrierTimes(r: Ride): { number }
	local out: { number } = {}
	if r.zone ~= "home" or not r.plot then return out end
	local cf = Drive.plotCF(r.plot)
	if not cf then return out end
	for _, sg in r.segs do
		if sg.from ~= "hq_garage" and sg.to ~= "hq_garage" then continue end
		local leg = Drive.segLeg(sg, r.plot)
		if not leg then continue end
		for i = 2, #leg.pts do
			local a = cf:PointToObjectSpace(leg.pts[i - 1])
			local b = cf:PointToObjectSpace(leg.pts[i])
			if (a.Z - -140) * (b.Z - -140) <= 0 and math.abs(a.X - 102) < 14 then
				table.insert(out, sg.t0 + leg.t[i])
				break
			end
		end
	end
	return out
end
local function setPlan(r: Ride, segs: { Drive.Seg })
	r.segs = segs
	r.barriers = barrierTimes(r)
	publishRide(r)
end
local function newRide(c: Company?, kind: string, zone: string, plot: number?, look: string, driver: number, userId: number): Ride
	local n: number
	local parent: Folder
	if c then
		c.seq += 1
		n = c.seq
		parent = c.folder
	else
		limoSeq += 1
		n = limoSeq
		parent = limoFolder :: Folder
	end
	local f = Instance.new("Folder")
	f.Name = "Ride_" .. n
	local r: Ride = { id = "drive:" .. (if c then tostring(userId) else "limo") .. ":" .. n, n = n, kind = kind, userId = userId, zone = zone, plot = plot,
		look = look, driver = driver, segs = {}, folder = f, state = "coming", rider = nil, pickup = nil, to = nil, purpose = "phone", wait = 0,
		waitUntil = 0, hold = nil, onArrive = nil, prompt = nil, focusAt = 0, streamed = false, dropped = false, borrowed = nil, untilT = nil,
		passengers = 0, barriers = {}, barrierAsk = 0, holdsStand = false, reposition = false }
	f.Parent = parent
	if c then c.rides[r.id] = r else limoRides[r.id] = r end
	return r
end
-- bay 1 of the VIP stand: "idle" (the limousine waits there, drawn by every client), "held" by ride `id`, "empty"
local function setStand(state: string, id: string?)
	standState = state
	standRide = id
	local lf = limoFolder
	if lf then
		setAttr(lf, "StandRide", id or "")
		setAttr(lf, "Stand", state)
	end
end

------------------------------------------------------------------------------------------------ the founder's character
local function riderValid(r: Ride): boolean
	local player = r.rider
	local h = r.hold
	if not player or not h then return false end
	return player.Parent ~= nil and player.Character == h.character and h.root.Parent ~= nil
end
local function release(r: Ride, at: CFrame?)
	local h = r.hold
	r.hold = nil
	local player = r.rider
	if player then pcall(function() player:SetAttribute("DriveRide", nil) end) end
	if not h then return end
	if h.root.Parent and player and player.Character == h.character then
		if at then h.character:PivotTo(at) end
		h.root.Anchored = h.wasAnchored
		local humanoid = h.character:FindFirstChildOfClass("Humanoid")
		if humanoid and h.display then humanoid.DisplayDistanceType = h.display end
	end
end
local function holdAt(r: Ride, pos: Vector3)
	local h = r.hold
	if not h or not h.root.Parent then return end
	h.character:PivotTo(CFrame.new(pos.X, CityPlan.GROUND - DriverService.HOLD_DEPTH, pos.Z))
end
local function streamAsync(player: Player, pos: Vector3)
	local ok, err = pcall(function() player:RequestStreamAroundAsync(pos, CityPlan.TRAVEL.streamTimeout) end)
	if not ok then warn("[Drivers] RequestStreamAroundAsync failed for " .. player.Name .. ": " .. tostring(err)) end
end
-- empty the seats of `codes` (e.g. {R = true}) from segment `from` on (the founder got out / left / respawned)
local function strip(r: Ride, from: number, codes: { [string]: boolean })
	local segs = table.clone(r.segs)
	for i = math.max(1, from), #segs do
		local sg = table.clone(segs[i])
		local list: { string } = {}
		for code in string.gmatch(sg.who .. ",", "([^,]*),") do table.insert(list, if codes[code] then "" else code) end
		while #list > 1 and list[#list] == "" do table.remove(list) end
		sg.who = table.concat(list, ",")
		segs[i] = sg
	end
	setPlan(r, segs)
end
-- index of the segment that carries the founder to his destination
local function rideIndex(r: Ride): number?
	for i, sg in r.segs do
		if sg.to == r.to and string.find(sg.who, "R", 1, true) then return i end
	end
	return nil
end
-- "let me out here": the first kerb-side spot (DrivePlan.kerbCandidates) that no prop blocks
local function freeSpot(cf: CFrame, zone: string, plot: number?): CFrame
	local list = Drive.kerbCandidates(cf, zone, plot)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.MaxParts = 1
	local skip: { Instance } = {}
	for _, p in Players:GetPlayers() do if p.Character then table.insert(skip, p.Character) end end
	params.FilterDescendantsInstances = skip
	for _, spot in list do
		local ok, hits = pcall(function() return workspace:GetPartBoundsInBox(spot, DriverService.SPOT_BOX, params) end)
		if ok and typeof(hits) == "table" and #hits == 0 then return spot end
	end
	return list[1]
end
DriverService.freeSpot = freeSpot

------------------------------------------------------------------------------------------------ prompts
local function clearPrompt(r: Ride)
	if r.prompt then r.prompt:Destroy(); r.prompt = nil end
end
local promptFolder: Folder? = nil
-- Owner-only "Get in" prompt at the rear right door of the waiting car (WorldController shows it to the owner).
local function makePrompt(r: Ride, carCF: CFrame)
	clearPrompt(r)
	local player = r.rider
	if not player or not promptFolder then return end
	local p = Instance.new("Part")
	p.Name = "DrivePrompt_" .. player.UserId
	p.Size = Vector3.new(1, 1, 1); p.Transparency = 1; p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
	p.CFrame = carCF * CFrame.new(Drive.CAR_WIDTH[if r.look == "limo" then "limo" else "fleet"] / 2 + 0.6, 3, if r.look == "limo" then 4.6 else 2.6)
	local q = Instance.new("ProximityPrompt")
	q.Name = "DrivePrompt"
	q.ActionText = "Get in"
	local to = if r.to then Drive.place(r.to, r.plot) else nil
	q.ObjectText = if to then "Ride to " .. to.name else "Your car"
	q.HoldDuration = 0; q.MaxActivationDistance = 12; q.RequiresLineOfSight = false
	q:SetAttribute("OwnerUserId", player.UserId)
	q:SetAttribute("DriveAction", "board")
	q:SetAttribute("RideId", r.id)
	q.Parent = p
	p.Parent = promptFolder
	r.prompt = p
end

------------------------------------------------------------------------------------------------ helpers
local function sessionOf(player: Player): any
	local s = Session.get(player)
	if not s or s.closed then return nil end
	return s
end
local function plotIndex(player: Player): number?
	local p = Plot.get(player)
	return if p and typeof(p.index) == "number" then p.index else nil
end
local function busyDrivers(c: Company): { [number]: Ride }
	local out: { [number]: Ride } = {}
	for _, r in c.rides do if r.driver > 0 then out[r.driver] = r end end
	return out
end
local function freeDriver(c: Company): number?
	local busy = busyDrivers(c)
	for i = 1, c.drivers do if not busy[i] then return i end end
	return nil
end
local function depotOf(zone: string): string
	return if zone == "abroad" then "pm_depot" else "hq_garage"
end
-- worst-case end of a ride (the founder may still have to get in)
local function rideEndEstimate(r: Ride): number
	local t = now()
	if r.state == "coming" or r.state == "waiting" then
		local arrive = if #r.segs > 0 then Drive.segEnd(r.segs[#r.segs], r.plot) else t
		local waitEnd = if r.state == "waiting" then r.waitUntil else arrive + Drive.WAIT
		local ride = if r.pickup and r.to then Drive.leg(r.pickup, r.to, r.plot) else nil
		local back = if r.to then Drive.leg(r.to, depotOf(r.zone), r.plot, if r.to == "hq_entrance" then "drop" else nil) else nil
		return waitEnd + Drive.BOARD_DELAY + (if ride then ride.dur else 0) + DriverService.DROP_PAUSE + r.wait + (if back then back.dur else 0)
	end
	return math.max(t, legEnd(r))
end
-- the founder's open ride in `zone` (nil = either city); repositioning limousines are nobody's
local function founderRide(userId: number, zone: string?): Ride?
	local c = companies[userId]
	if c and zone ~= "abroad" then
		for _, r in c.rides do if r.kind == "founder" and r.state ~= "returning" then return r end end
	end
	if zone ~= "home" then
		for _, r in limoRides do if not r.reposition and r.userId == userId and r.state ~= "returning" then return r end end
	end
	return nil
end
local function limoQueued(userId: number): (Request?, number?)
	for i, q in limoQueue do if q.player.UserId == userId then return q, i end end
	return nil, nil
end
local function findRide(id: string): (Ride?, Company?)
	for _, c in companies do
		local r = c.rides[id]
		if r then return r, c end
	end
	for _, c in detached do
		local r = c.rides[id]
		if r then return r, c end
	end
	return limoRides[id], nil
end
local function finishRide(r: Ride, c: Company?)
	clearPrompt(r)
	if r.hold then release(r, nil) end
	r.folder:Destroy()
	if c then
		c.rides[r.id] = nil
		if r.borrowed and c.session and not c.session.closed then
			pcall(function() Vehicles.giveBack(c.session, r.borrowed :: string) end)
		end
	else
		limoRides[r.id] = nil
		if r.holdsStand and standRide == r.id then
			-- the car stands at bay 1 (it never left, or a repositioning limousine arrived): the idle limousine again
			r.holdsStand = false
			setStand("idle", nil)
		end
	end
end
local function clearRider(r: Ride)
	local player = r.rider
	if player then pcall(function() player:SetAttribute("DriveRide", nil) end) end
	r.rider = nil
end

------------------------------------------------------------------------------------------------ limousine stand
local function limoCount(): number
	local n = 0
	for _ in limoRides do n += 1 end
	return n
end
local function limoLeg(fromId: string, toId: string, side: string?): number
	local leg = Drive.leg(fromId, toId, nil, side)
	return if leg then leg.dur else 0
end
-- a limousine without a booking drives from the service's garage to bay 1 (the stand stays "held" meanwhile)
local function startReposition(): Ride?
	if limoCount() >= DriverService.LIMO_FLEET or not limoFolder then return nil end
	local r = newRide(nil, "limo", "abroad", nil, "limo", 0, 0)
	r.reposition = true
	r.holdsStand = true
	r.pickup = "pm_limo"
	r.to = "pm_limo"
	r.state = "driving"
	setPlan(r, { { from = "pm_depot", to = "pm_limo", t0 = now() + DriverService.LIMO_FROM_DEPOT, who = "D" } })
	setStand("held", r.id)
	return r
end
-- seconds until a limousine waits at `pickup`, if a booking now would get one (nil: no car free = queue)
local function limoReady(pickup: string): (number?, string)
	local t = now()
	if pickup == "pm_limo" then
		if standState == "idle" then return 0, "stand" end
		local holder = if standRide then limoRides[standRide] else nil
		if holder and holder.reposition and #holder.segs > 0 then return math.max(0, Drive.segEnd(holder.segs[1], nil) - t), "reposition" end
		return nil, "busy"
	end
	if limoCount() >= DriverService.LIMO_FLEET then return nil, "busy" end
	return DriverService.LIMO_FROM_DEPOT + limoLeg("pm_depot", pickup), "depot"
end
-- honest estimate for a booking that has to wait (bay 1 busy / every limousine out)
local function limoWaitEstimate(pickup: string): number
	local t = now()
	local soonest = math.huge
	if pickup == "pm_limo" and standRide then
		local holder = limoRides[standRide]
		if holder and not holder.reposition then
			-- worst case: he gets in at the last second, the car pulls away, the next one comes from the garage
			local leave = t
			if holder.state == "waiting" then
				leave = holder.waitUntil + Drive.BOARD_DELAY
			elseif holder.state == "coming" then
				leave = (if #holder.segs > 0 then Drive.segEnd(holder.segs[#holder.segs], nil) else t) + Drive.WAIT + Drive.BOARD_DELAY
			else
				for _, sg in holder.segs do if sg.from == "pm_limo" then leave = sg.t0; break end end
			end
			return math.max(0, math.max(t, leave) + DriverService.LIMO_CLEAR + DriverService.LIMO_FROM_DEPOT + limoLeg("pm_depot", "pm_limo") - t)
		end
	end
	for _, r in limoRides do soonest = math.min(soonest, rideEndEstimate(r)) end
	if soonest == math.huge then soonest = t end
	return math.max(0, soonest - t) + DriverService.LIMO_FROM_DEPOT + limoLeg("pm_depot", pickup)
end

------------------------------------------------------------------------------------------------ founder rides
-- seconds until a home ride started at server time `at` (default now) has its car waiting at `pickup` (the driver's
-- walk to the car - longer at night - + the leg)
local function comingSeconds(pickup: string, plot: number?, at: number?): number
	local leg = Drive.leg("hq_garage", pickup, plot)
	return Drive.walkAt(at or now()) + (if leg then leg.dur else 0)
end

local function startHome(c: Company, q: Request, driver: number): Ride
	local player = q.player
	local look = "fleet"
	local borrowed: string? = nil
	-- the founder's own parked car (not the 19-stud pass limousine: B1's depot lane is planned for <= 15 studs)
	local okPark, parked = pcall(Vehicles.parkedOnSite, player)
	if okPark and typeof(parked) == "string" and (Drive.CAR_LENGTH[parked] or 99) <= Drive.CAR_LENGTH.fleet then
		local okLend, id = pcall(Vehicles.lend, player)
		if okLend and typeof(id) == "string" then look = Drive.look(id); borrowed = id end
	end
	local r = newRide(c, "founder", "home", c.plot, look, driver, player.UserId)
	r.rider = player; r.pickup = q.pickup; r.to = q.to; r.purpose = q.purpose; r.wait = q.wait; r.onArrive = q.onArrive; r.borrowed = borrowed
	r.passengers = companionTemplates(r.folder, player.UserId, q.passengers, "C", c.company, DriverService.MAX_PASSENGERS)
	setAttr(r.folder, "Companions", r.passengers)
	r.state = "coming"
	local t = now()
	setPlan(r, { { from = "hq_garage", to = q.pickup, t0 = t + Drive.walkAt(t), who = "D" } })
	player:SetAttribute("DriveRide", r.id)
	return r
end

-- a limousine booking that has a car now (limoReady ~= nil); returns the ride
local function startLimo(q: Request): Ride?
	local player = q.player
	local _, how = limoReady(q.pickup)
	local r: Ride
	if how == "stand" then
		r = newRide(nil, "limo", "abroad", nil, "limo", 0, player.UserId)
		r.holdsStand = true
		setStand("held", r.id)
	elseif how == "reposition" then
		r = limoRides[standRide :: string]
		r.reposition = false
		r.userId = player.UserId
	elseif how == "depot" then
		r = newRide(nil, "limo", "abroad", nil, "limo", 0, player.UserId)
	else
		return nil
	end
	r.rider = player; r.pickup = q.pickup; r.to = q.to; r.purpose = q.purpose; r.wait = q.wait; r.onArrive = q.onArrive
	-- a converted repositioning car keeps no old companions (it had none)
	r.passengers = companionTemplates(r.folder, player.UserId, q.passengers, "C", "Port Meridian VIP", DriverService.MAX_PASSENGERS)
	setAttr(r.folder, "Companions", r.passengers)
	local t = now()
	if how == "stand" then
		-- the limousine already stands at bay 1: it waits right away (an empty plan = the car stands at the stand)
		r.state = "waiting"
		r.waitUntil = t + Drive.WAIT
		setPlan(r, {})
		local stand = Drive.place("pm_limo")
		if stand then makePrompt(r, stand.stop) end
	elseif how == "depot" then
		r.state = "coming"
		setPlan(r, { { from = "pm_depot", to = q.pickup, t0 = t + DriverService.LIMO_FROM_DEPOT, who = "D" } })
	else
		r.state = "coming"
		publishRide(r)
	end
	player:SetAttribute("DriveRide", r.id)
	return r
end

local function resultOf(r: Ride?, q: Request, plot: number?, eta: number, queued: boolean, driver: string?): { [string]: any }
	local pickup = Drive.place(q.pickup, plot)
	local to = Drive.place(q.to, plot)
	local legRide = Drive.leg(q.pickup, q.to, plot)
	local rideSecs = Drive.BOARD_DELAY + (if legRide then legRide.dur else 0)
	return { ok = true, rideId = if r then r.id else "queued:" .. q.player.UserId, eta = math.ceil(eta), arriveEta = math.ceil(eta + rideSecs), queued = queued,
		pickup = q.pickup, pickupName = if pickup then pickup.name else nil, pickupAt = if pickup then Drive.atName(pickup) else nil, to = q.to,
		toName = if to then to.name else nil, driver = driver }
end

function DriverService.request(player: Player, opts: any): { [string]: any }
	local o = if typeof(opts) == "table" then opts else {}
	local s = sessionOf(player)
	if not s then return { ok = false, err = "LOADING" } end
	local e = empireOf(s)
	if not e then return { ok = false, err = "NO_COMPANY" } end
	if typeof(o.to) ~= "string" or #o.to > 40 then return { ok = false, err = "BAD_INPUT" } end
	local purpose = if o.purpose == "itinerary" then "itinerary" else "phone"
	local wait = if typeof(o.wait) == "number" and o.wait == o.wait then math.clamp(o.wait, 0, DriverService.MAX_WAIT) else 0
	local zone = zoneOf(player)
	if not zone then return { ok = false, err = "FLYING" } end
	local c = companies[player.UserId]
	if zone == "home" then
		if not c or c.drivers <= 0 then return { ok = false, err = "NO_DRIVER", stage = stageName(Drive.FIRST_DRIVER_STAGE) } end
		if not c.plot then return { ok = false, err = "LOADING" } end
		-- the rides start in the B1 garage of the HQ buildings (plan tier >= 1); a forced garage-stage building has none
		if c.tier < 1 then return { ok = false, err = "NO_DRIVER", stage = stageName(Drive.FIRST_DRIVER_STAGE) } end
	end
	local plot = if zone == "home" and c then c.plot else nil
	local to = Drive.place(o.to, plot)
	if not to then return { ok = false, err = "BAD_PLACE" } end
	if to.zone ~= zone then return { ok = false, err = "FLIGHT_REQUIRED" } end
	if to.kind == "garage" or to.id == "pm_limo" then return { ok = false, err = "BAD_PLACE" } end
	if founderRide(player.UserId, zone) or (zone == "home" and c and c.queue) or (zone == "abroad" and limoQueued(player.UserId)) then
		return { ok = false, err = "ALREADY_RIDING" }
	end
	local t = now()
	local last = if c then c.requestAt else (limoRequestAt[player.UserId] or -math.huge)
	if t - last < DriverService.REQUEST_GAP then return { ok = false, err = "COOLDOWN" } end
	local character, r0, humanoid = rootOf(player)
	if not character or not r0 or not humanoid or humanoid.Health <= 0 then return { ok = false, err = "LOADING" } end
	if humanoid.SeatPart then return { ok = false, err = "LEAVE_VEHICLE" } end
	local pickup, perr = Drive.nearestPickup(r0.Position, zone, plot)
	if not pickup then return { ok = false, err = perr or "TOO_FAR", zone = zone } end
	if pickup.id == to.id then return { ok = false, err = "ALREADY_THERE" } end
	if not Drive.leg(pickup.id, to.id, plot) then return { ok = false, err = "BAD_PLACE" } end
	local q: Request = { player = player, to = to.id, pickup = pickup.id, passengers = o.passengers, purpose = purpose, wait = wait,
		onArrive = if typeof(o.onArrive) == "function" then o.onArrive else nil, at = t }
	if c then c.requestAt = t end
	limoRequestAt[player.UserId] = t
	if zone == "abroad" then
		local eta = limoReady(pickup.id)
		if eta then
			local r = startLimo(q)
			notice(player, if eta > 0.5 then "The VIP limousine is on its way to " .. Drive.atName(pickup) .. " (" .. Drive.clock(eta) .. ")."
				else "Your VIP limousine is waiting at the stand. Get in when you're ready.")
			return resultOf(r, q, nil, eta, false, nil)
		end
		-- bay 1 is busy / every limousine is out: the next car is booked for him (first come, first served)
		local wait2 = limoWaitEstimate(pickup.id)
		table.insert(limoQueue, q)
		pcall(function() player:SetAttribute("DriveQueue", t + wait2); player:SetAttribute("DriveQueueTo", to.name) end)
		notice(player, "Every VIP limousine is out with a guest. Yours comes to " .. Drive.atName(pickup) .. " in about " .. Drive.clock(wait2) .. ".")
		return resultOf(nil, q, nil, wait2, true, nil)
	end
	local cc = c :: Company
	local d = freeDriver(cc)
	if d then
		local r = startHome(cc, q, d)
		local eta = comingSeconds(pickup.id, plot)
		notice(player, firstName(driverName(cc, d)) .. " is bringing the car to " .. Drive.atName(pickup) .. " (" .. Drive.clock(eta) .. ").")
		return resultOf(r, q, plot, eta, false, driverName(cc, d))
	end
	-- every driver is out: queue with an honest estimate (the first driver back + the way to the pick-up)
	local soonest = math.huge
	for _, r in busyDrivers(cc) do soonest = math.min(soonest, rideEndEstimate(r)) end
	if soonest == math.huge then soonest = t end
	cc.queue = q
	local eta = math.max(0, soonest - t) + comingSeconds(pickup.id, plot, math.max(t, soonest))
	-- the founder's HUD shows the booking (one write; cleared when the ride starts or the booking is dropped)
	pcall(function() player:SetAttribute("DriveQueue", t + eta); player:SetAttribute("DriveQueueTo", to.name) end)
	notice(player, (if cc.drivers == 1 then "Your driver is" else "Both drivers are") .. " out right now. Next car at " .. Drive.atName(pickup) .. " in about " .. Drive.clock(eta) .. ".")
	return resultOf(nil, q, plot, eta, true, nil)
end

local function board(r: Ride, player: Player): (boolean, string?)
	if r.state ~= "waiting" or r.rider ~= player then return false, "NOT_WAITING" end
	local character, r0, humanoid = rootOf(player)
	if not character or not r0 or not humanoid or humanoid.Health <= 0 then return false, "LOADING" end
	if humanoid.SeatPart then return false, "LEAVE_VEHICLE" end
	local pickup = Drive.place(r.pickup, r.plot)
	local to = Drive.place(r.to, r.plot)
	if not pickup or not to then return false, "BAD_PLACE" end
	local carCF = pickup.stop
	if #r.segs > 0 then
		local leg = Drive.segLeg(r.segs[#r.segs], r.plot)
		if leg then carCF = Drive.endCF(leg) end
	end
	local p = r0.Position
	if Drive.flat(p, carCF.Position) > Drive.BOARD_RADIUS or math.abs(p.Y - carCF.Position.Y) > Drive.BOARD_DY then return false, "TOO_FAR" end
	local t = now()
	-- hold the founder below the car: anchored, name tag off; the client shows him on the back seat
	r.hold = { character = character, root = r0, wasAnchored = r0.Anchored, display = humanoid.DisplayDistanceType }
	r0.Anchored = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	holdAt(r, carCF.Position)
	clearPrompt(r)
	local who = "D,R" .. (if r.passengers >= 1 then ",C1" else "") .. (if r.passengers >= 2 then ",C2" else "")
	local segs = table.clone(r.segs)
	local rideSeg: Drive.Seg = { from = pickup.id, to = to.id, t0 = t + Drive.BOARD_DELAY, who = who }
	table.insert(segs, rideSeg)
	local rideEnd = Drive.segEnd(rideSeg, r.plot)
	local depot = depotOf(r.zone)
	table.insert(segs, { from = to.id, to = depot, side = if to.id == "hq_entrance" then "drop" else nil, t0 = rideEnd + DriverService.DROP_PAUSE + r.wait, who = "D" })
	r.state = "riding"
	r.focusAt = t
	setPlan(r, segs)
	player:SetAttribute("DriveRide", r.id)
	local s = Session.get(player)
	if s then Session.markDirty(s, true) end
	return true, nil
end

local function arrive(r: Ride)
	r.dropped = true
	local player = r.rider
	local to = if r.to then Drive.place(r.to, r.plot) else nil
	if not player or not to or not riderValid(r) then
		release(r, nil)
		clearRider(r)
		r.state = "returning"
		strip(r, rideIndex(r) or 1, { R = true })
		return
	end
	local door = to.door
	if to.id == "hq_entrance" and r.plot then
		local cf = Drive.plotCF(r.plot)
		if cf then door = cf * Drive.HQ.alight end
	end
	release(r, door)
	r.state = "returning"
	-- the founder stands at the door (his real character); his companions get out with him: they stay on the ride
	-- leg and the next leg (back) carries only the driver, so every client shows them standing at the door while the
	-- car waits (DROP_PAUSE) - then they have gone in
	local ri = rideIndex(r) or 1
	clearRider(r)
	strip(r, ri, { R = true })
	local s = Session.get(player)
	if s then Session.markDirty(s, true) end
	local placeId = to.id
	if r.onArrive then
		local cb = r.onArrive :: (string, string) -> ()
		local ok, err = pcall(function() cb(r.id, placeId) end)
		if not ok then warn("[Drivers] onArrive callback failed: " .. tostring(err)) end
	end
	for _, fn in table.clone(arriveFns) do
		local ok, err = pcall(function() fn(player, r.id, placeId) end)
		if not ok then warn("[Drivers] onArrive listener failed: " .. tostring(err)) end
	end
	arrivedEvent:Fire(player, r.id, placeId)
end

-- the car turns back to its depot from where it is (or from the end of the leg it is on)
local function turnBack(r: Ride)
	local t = now()
	local segs = table.clone(r.segs)
	local depot = depotOf(r.zone)
	local at = r.pickup or depot
	local start = t
	local side: string? = nil
	if #segs > 0 then
		local last = segs[#segs]
		start = math.max(t, Drive.segEnd(last, r.plot))
		at = last.to
		if at == "hq_entrance" and last.from ~= "hq_garage" then side = "drop" end
	end
	if at ~= depot then
		table.insert(segs, { from = at, to = depot, side = side, t0 = start + 0.5, who = "D" })
	end
	clearPrompt(r)
	r.state = "returning"
	setPlan(r, segs)
end

-- the queued-booking HUD attributes (set by request when every car is out)
local function clearQueued(player: Player?)
	if not player then return end
	pcall(function() player:SetAttribute("DriveQueue", nil); player:SetAttribute("DriveQueueTo", nil) end)
end

-- a booked car is not needed any more (cancel, wait over, founder gone / in the other city): the limousine waiting
-- at bay 1 simply stays there (idle again), a repositioning car that was converted goes on to the stand, every
-- other car turns back (or vanishes if the driver has not left yet)
local function dropBooking(r: Ride, c: Company?)
	clearPrompt(r)
	clearRider(r)
	local t = now()
	if r.holdsStand then
		local atBay = #r.segs == 0 or (r.segs[#r.segs].to == "pm_limo" and t >= Drive.segEnd(r.segs[#r.segs], nil))
		if atBay then
			finishRide(r, nil)
			return
		end
		-- still on the way to the stand: a repositioning car again
		r.reposition = true
		r.userId = 0
		r.state = "driving"
		r.onArrive = nil
		for _, ch in r.folder:GetChildren() do if ch:IsA("Model") then ch:Destroy() end end
		r.passengers = 0
		setAttr(r.folder, "Companions", 0)
		publishRide(r)
		return
	end
	if #r.segs > 0 and t < r.segs[1].t0 then
		-- the driver has not left yet: no car at all
		finishRide(r, c)
		return
	end
	turnBack(r)
end

-- the founder leaves the car during a ride (cancel = "let me out here" at a free kerb-side spot; respawn / leaving the
-- game = no placement). Before the car pulled away it stays / turns back from the pick-up; on the way the car
-- drives on empty (companions get out at the destination).
local function leaveRide(r: Ride, c: Company?, place: boolean)
	local t = now()
	local k = rideIndex(r)
	local at: CFrame? = nil
	if place and riderValid(r) then
		local pose = Drive.pose(r.segs, r.plot, t, wbOf(r))
		if pose then at = freeSpot(pose.cf, r.zone, r.plot) end
	end
	release(r, at)
	r.dropped = true
	clearRider(r)
	clearPrompt(r)
	if k and t < r.segs[k].t0 then
		local segs: { Drive.Seg } = {}
		for i = 1, k - 1 do table.insert(segs, r.segs[i]) end
		r.segs = segs
		if r.holdsStand then
			finishRide(r, nil)
			return
		end
		turnBack(r)
		return
	end
	r.state = "returning"
	strip(r, k or 1, { R = true })
end

function DriverService.cancel(rideId: any): (boolean, string?)
	if typeof(rideId) ~= "string" then return false, "BAD_INPUT" end
	local queuedUser = tonumber(string.match(rideId, "^queued:(%d+)$"))
	if queuedUser then
		local c = companies[queuedUser]
		if c and c.queue then clearQueued(c.queue.player); c.queue = nil; return true, nil end
		local q, i = limoQueued(queuedUser)
		if q and i then clearQueued(q.player); table.remove(limoQueue, i); return true, nil end
		return false, "NO_RIDE"
	end
	local r, c = findRide(rideId)
	if not r or r.reposition or (r.kind ~= "founder" and r.kind ~= "limo") then return false, "NO_RIDE" end
	if r.state == "returning" then return false, "RETURNING" end
	if r.state == "coming" or r.state == "waiting" then
		dropBooking(r, c)
		return true, nil
	elseif r.state == "riding" then
		leaveRide(r, c, true)
		return true, nil
	end
	return false, "NO_RIDE"
end

function DriverService.free(player: Player): (number, string?)
	local s = sessionOf(player)
	if not s then return 0, "LOADING" end
	if not empireOf(s) then return 0, "NO_COMPANY" end
	local zone = zoneOf(player)
	if not zone then return 0, "FLYING" end
	if zone == "abroad" then
		local n = math.max(0, DriverService.LIMO_FLEET - limoCount()) + (if standState == "idle" then 1 else 0)
		return n, if n == 0 then "ALL_BUSY" else nil
	end
	local c = companies[player.UserId]
	if not c or c.drivers <= 0 then return 0, "NO_DRIVER" end
	local busy = busyDrivers(c)
	local n = 0
	for i = 1, c.drivers do if not busy[i] then n += 1 end end
	if n == 0 then return 0, "ALL_BUSY" end
	return n, nil
end

function DriverService.places(zone: string?, player: Player?): { { [string]: any } }
	local plot = if player then plotIndex(player) else nil
	local out: { { [string]: any } } = {}
	for _, p in Drive.places(zone, plot) do
		if p.kind == "garage" then continue end
		table.insert(out, { id = p.id, name = p.name, short = p.short, zone = p.zone, kind = p.kind, clientId = p.clientId })
	end
	return out
end

function DriverService.onArrive(fn: (Player, string, string) -> ()): () -> ()
	table.insert(arriveFns, fn)
	return function()
		local i = table.find(arriveFns, fn)
		if i then table.remove(arriveFns, i) end
	end
end

function DriverService.onTripAction(action: string, handler: (any, any) -> any)
	if action == "ride" then return end
	tripHandlers[action] = handler
end

function DriverService.status(player: Player): { [string]: any }
	local c = companies[player.UserId]
	local count, reason = DriverService.free(player)
	local zone = zoneOf(player)
	local res: { [string]: any } = { state = "none", drivers = if c then c.drivers else 0, free = count, reason = reason, zone = zone }
	if not zone then return res end
	local t = now()
	local q: Request? = nil
	local qEta = 0
	if zone == "home" and c and c.queue then
		q = c.queue
		local soonest = math.huge
		for _, r in busyDrivers(c) do soonest = math.min(soonest, rideEndEstimate(r)) end
		if soonest == math.huge then soonest = t end
		qEta = math.max(0, soonest - t) + comingSeconds((c.queue :: Request).pickup, c.plot, math.max(t, soonest))
	elseif zone == "abroad" then
		q = limoQueued(player.UserId)
		if q then qEta = limoWaitEstimate(q.pickup) end
	end
	if q then
		local pickup = Drive.place(q.pickup, if c then c.plot else nil)
		local to = Drive.place(q.to, if c then c.plot else nil)
		res.state = "queued"; res.rideId = "queued:" .. player.UserId; res.to = q.to; res.pickup = q.pickup
		res.eta = math.ceil(qEta)
		res.pickupName = if pickup then pickup.name else nil
		res.pickupAt = if pickup then Drive.atName(pickup) else nil
		res.toName = if to then to.name else nil
		return res
	end
	local r = founderRide(player.UserId, zone)
	if r then
		res.state = r.state; res.rideId = r.id; res.to = r.to; res.pickup = r.pickup
		local pickup = if r.pickup then Drive.place(r.pickup, r.plot) else nil
		local to = if r.to then Drive.place(r.to, r.plot) else nil
		res.pickupName = if pickup then pickup.name else nil
		res.pickupAt = if pickup then Drive.atName(pickup) else nil
		res.toName = if to then to.name else nil
		if r.state == "coming" then
			res.eta = math.ceil(math.max(0, (if #r.segs > 0 then Drive.segEnd(r.segs[#r.segs], r.plot) else t) - t))
		elseif r.state == "waiting" then
			res.eta = 0; res.waitLeft = math.ceil(math.max(0, r.waitUntil - t))
		elseif r.state == "riding" then
			local ri = rideIndex(r)
			if ri then res.eta = math.ceil(math.max(0, Drive.segEnd(r.segs[ri], r.plot) - t)) end
		end
		local cc = companies[r.userId]
		if cc and r.driver > 0 then res.driverName = driverName(cc, r.driver) end
	end
	return res
end

------------------------------------------------------------------------------------------------ field rides
local function profileOf(e: any, role: string, i: number): any
	local list = if typeof(e.staffProfiles) == "table" then e.staffProfiles[role] else nil
	local p = if typeof(list) == "table" then list[i] else nil
	return if typeof(p) == "table" and typeof(p.n) == "string" then p else nil
end
-- the travellers of every non-founder trip: the k-th field rep for the k-th trip of the reps, the engineers
-- CompanyOps.presence marks as travelling for region / abroad pilots (ShuttleService / PhoneService rule)
local function tripTravellers(e: any): { [string]: { { name: string, role: string, seed: number? } } }
	local out: { [string]: { { name: string, role: string, seed: number? } } } = {}
	local deals = e.deals
	if typeof(deals) ~= "table" or typeof(deals.tripList) ~= "table" then return out end
	local away: { any } = {}
	local okP, presence = pcall(Ops.presence, e, "engineer")
	if okP and typeof(presence) == "table" then
		for i, st in presence do if st == "trip" then local p = profileOf(e, "engineer", i); if p then table.insert(away, p) end end end
	end
	local k, m = 0, 0
	local reps = Ops.fieldReps(e)
	for _, trip in deals.tripList do
		if typeof(trip) ~= "table" or trip.founder == true then continue end
		k += 1
		local c = Ops.client(trip.client)
		if not c then continue end
		local list: { { name: string, role: string, seed: number? } } = {}
		local rep = if k <= reps then profileOf(e, "marketer", k) else nil
		if rep then table.insert(list, { name = rep.n, role = "marketer", seed = rep.s }) end
		if c.trip ~= "city" and not trip.hosted and trip.kind == "sign" then
			m += 1
			if away[m] and (tonumber(trip.crew) or 0) >= 2 then table.insert(list, { name = away[m].n, role = "engineer", seed = away[m].s }) end
		end
		out[tostring(trip.client) .. ":" .. tostring(trip.left)] = list
	end
	return out
end
local function guestsOf(c: Company, client: any, key: string): { { name: string, role: string, seed: number?, badge: string } }
	local h = 0
	for i = 1, #key do h = (h * 31 + string.byte(key, i)) % 100000 end
	local out = {}
	for g = 1, 2 do
		local name = CampusMath.staffName(9600 + (h + g * 7) % 300, c.userId)
		table.insert(out, { name = name, role = if g == 1 then "marketer" else "researcher", seed = h * 10 + g, badge = name .. "\nGuest · " .. tostring(client.name) })
	end
	return out
end
-- where the field staff of a trip go: the client's Business City building (city / region), City Airport (abroad)
local function fieldDest(client: any, back: boolean): string?
	if client.trip == "abroad" then return if back then "airport_arrivals" else "airport_departures" end
	local p = Drive.clientPlace(client.name)
	return if p and p.zone == "home" then p.id else nil
end
-- A visible fleet ride for a trip that just left (back = false) or just ended (back = true): a free company driver
-- takes the travellers (field rep (+ engineer) / the client team of a hosted visit) between the HQ entrance and the
-- trip's place. No free driver (or a founder booking waiting): the trip stays data. Returns the ride id.
local function fieldRide(c: Company, key: string, trip: any, people: any, back: boolean): string?
	if not c.plot or c.tier < 1 or c.queue then return nil end
	local client = Ops.client(trip.client)
	if not client or trip.founder == true then return nil end
	local hosted = trip.hosted == true
	-- a hosted visit: the client team comes to the HQ (fetched from their building / the arrivals kerb) and goes back
	local place = if hosted then fieldDest(client, not back) else fieldDest(client, back)
	if not place then return nil end
	local list: any = people
	if hosted then list = guestsOf(c, client, key) end
	if typeof(list) ~= "table" or #list == 0 then return nil end
	local d = freeDriver(c)
	if not d then return nil end
	local t = now()
	local plot = c.plot
	local r = newRide(c, if hosted then "guest" else "field", "home", plot, "fleet", d, c.userId)
	local prefix = if hosted then "G" else "C"
	local n = companionTemplates(r.folder, c.userId, list, prefix, c.company, 2)
	setAttr(r.folder, if hosted then "Guests" else "Companions", n)
	if n == 0 then finishRide(r, c); return nil end
	local who = "D," .. prefix .. "1" .. (if n >= 2 then "," .. prefix .. "2" else "")
	-- to the HQ (field rep back, guests arriving) or away from it (field rep out, guests leaving)
	local toHQ = (back and not hosted) or (hosted and not back)
	local from, dest = if toHQ then place else "hq_entrance", if toHQ then "hq_entrance" else place
	local a: Drive.Seg = { from = "hq_garage", to = from, t0 = t + Drive.walkAt(t), who = "D" }
	local b: Drive.Seg = { from = from, to = dest, t0 = Drive.segEnd(a, plot) + DriverService.FIELD_PAUSE, who = who }
	local cc: Drive.Seg = { from = dest, to = "hq_garage", side = if dest == "hq_entrance" then "drop" else nil, t0 = Drive.segEnd(b, plot) + DriverService.FIELD_PAUSE, who = "D" }
	r.state = "driving"; r.pickup = from; r.to = dest
	setPlan(r, { a, b, cc })
	return r.id
end
-- the travellers' segment of a field ride (the one carrying C*/G* codes) and its index
local function passengerSeg(r: Ride): (number?, Drive.Seg?)
	for i, sg in r.segs do
		if string.find(sg.who, "C", 1, true) or string.find(sg.who, "G", 1, true) then return i, sg end
	end
	return nil, nil
end
-- a trip ended (or was cancelled) while its outbound ride may still be on the road: the same car turns the
-- travellers round instead of a second car fetching them (no traveller in two cars at once). Returns "done" when
-- the outbound ride took care of it, "defer" (+ time) when the travellers are still on their way to the HQ (the
-- back ride starts after they got out there), "none" for a normal back ride.
local function endOutbound(c: Company, info: TripInfo): (string, number?)
	local r = if info.ride then c.rides[info.ride] else nil
	if not r then return "none", nil end
	local k, sg = passengerSeg(r)
	if not k or not sg then return "none", nil end
	local t = now()
	if t < sg.t0 then
		-- not on board yet: the trip is off before it started, the car goes back without them
		local segs: { Drive.Seg } = {}
		for i = 1, k - 1 do table.insert(segs, r.segs[i]) end
		r.segs = segs
		if #segs == 0 then finishRide(r, c) else turnBack(r) end
		return "done", nil
	end
	local arriveAt = Drive.segEnd(sg, r.plot)
	if sg.to == "hq_entrance" then
		-- that ride brings them to the HQ (a hosted visit's client team): the back ride after they got out there
		if t < arriveAt + DriverService.FIELD_PAUSE then return "defer", arriveAt + DriverService.FIELD_PAUSE + 1 end
		return "none", nil
	end
	if t < arriveAt then
		-- on the way there: drop nobody, drive them straight back to the HQ entrance
		local segs: { Drive.Seg } = {}
		for i = 1, k do table.insert(segs, r.segs[i]) end
		local back: Drive.Seg = { from = sg.to, to = "hq_entrance", t0 = arriveAt + 1, who = sg.who }
		table.insert(segs, back)
		table.insert(segs, { from = "hq_entrance", to = "hq_garage", side = "drop", t0 = Drive.segEnd(back, r.plot) + DriverService.FIELD_PAUSE, who = "D" })
		r.to = "hq_entrance"
		setPlan(r, segs)
		return "done", nil
	end
	if t < arriveAt + DriverService.FIELD_PAUSE then
		-- just dropped (standing at the door): they get back in
		local segs: { Drive.Seg } = {}
		for i = 1, k do table.insert(segs, r.segs[i]) end
		local back: Drive.Seg = { from = sg.to, to = "hq_entrance", t0 = arriveAt + DriverService.FIELD_PAUSE, who = sg.who }
		table.insert(segs, back)
		table.insert(segs, { from = "hq_entrance", to = "hq_garage", side = "drop", t0 = Drive.segEnd(back, r.plot) + DriverService.FIELD_PAUSE, who = "D" })
		r.to = "hq_entrance"
		setPlan(r, segs)
		return "done", nil
	end
	return "none", nil
end

-- ItineraryService (package "itinerary", optional, required lazily: it requires this module) - the founder may take a
-- trip's field rep + engineer in his own car (design/requests/itinerary.md #1)
local itinMod: any = nil
local itinTried = false
local function itinerary(): any
	if not itinTried then
		itinTried = true
		local mod = script.Parent:FindFirstChild("ItineraryService")
		if mod and mod:IsA("ModuleScript") then
			local ok, res = pcall(require, mod)
			if ok and typeof(res) == "table" then itinMod = res end
		end
	end
	return itinMod
end
local function itinAsk(fn: string, userId: number, key: string): boolean
	local I = itinerary()
	local f = if I then I[fn] else nil
	if typeof(f) ~= "function" then return false end
	local ok, res = pcall(f, userId, key)
	return ok and res == true
end
local function scanTrips(c: Company)
	local e = empireOf(c.session)
	if not e then return end
	local deals = e.deals
	local list = if typeof(deals) == "table" and typeof(deals.tripList) == "table" then deals.tripList else {}
	local current: { [string]: any } = {}
	for _, trip in list do
		if typeof(trip) == "table" and trip.founder ~= true then current[tostring(trip.client) .. ":" .. tostring(trip.left)] = trip end
	end
	local seen = c.trips
	if not seen then
		-- first look after loading: trips already under way stay data (no burst of cars at join)
		local first: { [string]: TripInfo } = {}
		for key, trip in current do first[key] = { trip = trip, people = nil, ride = nil } end
		c.trips = first
		return
	end
	local people: { [string]: any }? = nil
	for key, trip in current do
		if not seen[key] then
			-- the founder is being asked whether he travels along (the assistant's call): looked at again next scan
			if itinAsk("pending", c.userId, key) then continue end
			people = people or tripTravellers(e)
			local who = (people :: any)[key]
			local info: TripInfo = { trip = trip, people = who, ride = nil }
			seen[key] = info
			-- he said Go: they ride in his car (ItineraryService books it with them as passengers)
			if itinAsk("carries", c.userId, key) then continue end
			local ok, res = pcall(fieldRide, c, key, trip, who, false)
			if ok then info.ride = res else warn("[Drivers] field ride failed: " .. tostring(res)) end
		end
	end
	for key, info in seen do
		if not current[key] then
			seen[key] = nil
			-- the founder's car brings them home (his itinerary): no field car fetches them
			if itinAsk("carries", c.userId, key) then continue end
			local ok, how, after = pcall(endOutbound, c, info)
			if not ok then
				warn("[Drivers] field ride failed: " .. tostring(how))
			elseif how == "defer" then
				local at = after or now()
				table.insert(c.pending, { key = key, info = info, after = at, deadline = at + 2 * DriverService.BACK_RETRY })
			elseif how == "none" and (info.people ~= nil or info.trip.hosted == true) then
				table.insert(c.pending, { key = key, info = info, after = now(), deadline = now() + DriverService.BACK_RETRY })
			end
		end
	end
	-- back rides: as soon as a driver is free (and the travellers have arrived at the HQ); too long: they stay data
	local t = now()
	local i = 1
	while i <= #c.pending do
		local pnd = c.pending[i]
		if t >= pnd.after and freeDriver(c) and not c.queue then
			table.remove(c.pending, i)
			local ok2, err = pcall(fieldRide, c, pnd.key, pnd.info.trip, pnd.info.people, true)
			if not ok2 then warn("[Drivers] field ride failed: " .. tostring(err)) end
		elseif t > pnd.deadline then
			table.remove(c.pending, i)
		else
			i += 1
		end
	end
end

------------------------------------------------------------------------------------------------ companies
local function ensureCompany(s: any): Company?
	local player: Player? = s.player
	if not player or not root then return nil end
	local existing = companies[player.UserId]
	if existing then return existing end
	local name, livery = companyOf(s)
	local f = Instance.new("Folder")
	f.Name = "Drivers_" .. player.UserId
	local c: Company = { userId = player.UserId, player = player, session = s, folder = f, plot = nil, tier = 0, drivers = 0, company = name,
		livery = livery, rides = {}, queue = nil, trips = nil, seq = 0, proxy = nil, requestAt = -math.huge, detached = false, pending = {} }
	companies[player.UserId] = c
	setAttr(f, "Owner", c.userId); setAttr(f, "Company", name); setAttr(f, "Livery", livery); setAttr(f, "Drivers", 0)
	f.Parent = root
	return c
end
-- The founder left (his HQ is torn down with him): rides on the road finish their current leg empty in a detached
-- folder (other players do not see a car vanish mid-street); a leg into the vanished HQ / a car still in the
-- garage ends at once. The folder goes when its last ride is over.
local function dropCompany(userId: number)
	local c = companies[userId]
	if not c then return end
	companies[userId] = nil
	c.queue = nil
	if c.proxy then c.proxy:Destroy(); c.proxy = nil end
	local t = now()
	for _, r in c.rides do
		clearPrompt(r)
		if r.hold then release(r, nil) end
		r.rider = nil
		r.borrowed = nil
		r.untilT = nil
		-- keep the leg the car is on (or waits after); nothing into the HQ
		local keep: { Drive.Seg } = {}
		for i, sg in r.segs do
			local started = t >= sg.t0
			local ended = t >= Drive.segEnd(sg, r.plot)
			if started and not ended and sg.from ~= "hq_garage" and sg.to ~= "hq_garage" and sg.to ~= "hq_entrance" then
				local s2 = table.clone(sg)
				s2.who = if string.sub(sg.who, 1, 1) == "D" then "D" else ""
				table.insert(keep, s2)
				break
			end
			local _ = i
		end
		if #keep == 0 then
			r.folder:Destroy()
			c.rides[r.id] = nil
		else
			r.state = "returning"
			setPlan(r, keep)
		end
	end
	local any = next(c.rides) ~= nil
	if not any then
		c.folder:Destroy()
		return
	end
	detachSeq += 1
	c.detached = true
	c.folder.Name = "Drivers_" .. userId .. "_left" .. detachSeq
	setAttr(c.folder, "Detached", true)
	setAttr(c.folder, "Drivers", 0)
	table.insert(detached, c)
end
local function refreshCompany(c: Company, announce: boolean)
	local e = empireOf(c.session)
	local n = if e then Drive.drivers(e) else 0
	local name, livery = companyOf(c.session)
	local p = Plot.get(c.player)
	local plot = if p and typeof(p.index) == "number" then p.index else nil
	local tier = 0
	if p and p.office then
		local t = p.office:GetAttribute("OfficeTier")
		tier = if typeof(t) == "number" then t else 0
	end
	local changed = name ~= c.company or livery ~= c.livery
	c.company = name; c.livery = livery; c.plot = plot; c.tier = tier
	setAttr(c.folder, "Company", name); setAttr(c.folder, "Livery", livery); setAttr(c.folder, "Plot", plot or 0); setAttr(c.folder, "Tier", tier)
	if n ~= c.drivers or changed then
		local old = c.drivers
		c.drivers = n
		buildDrivers(c)
		setAttr(c.folder, "Drivers", n)
		if announce and n > old and c.player then
			if old == 0 then
				notice(c.player, "Your first company driver, " .. driverName(c, 1) .. ", starts today. Call him from the phone's Driver contact - he waits at the HQ entrance.")
			else
				notice(c.player, driverName(c, n) .. " joins as your second company driver.")
			end
		end
	end
end
-- the queued request starts as soon as a driver is back (from the pick-up nearest to the founder now)
local function serveQueue(c: Company)
	local q = c.queue
	if not q then return end
	local d = freeDriver(c)
	if not d then return end
	c.queue = nil
	clearQueued(q.player)
	if not q.player.Parent or companies[q.player.UserId] ~= c then return end
	local zone = zoneOf(q.player)
	if zone ~= "home" then
		notice(q.player, "Your booked company car was cancelled - you left the city.")
		return
	end
	if founderRide(q.player.UserId, "home") then return end
	local _, r0 = rootOf(q.player)
	if r0 then
		local here = Drive.nearestPickup(r0.Position, "home", c.plot)
		if here then
			if here.id == q.to then
				notice(q.player, "Your booked company car was cancelled - you're already at " .. Drive.atName(here) .. ".")
				return
			end
			q.pickup = here.id
		end
	end
	local ok, res = pcall(startHome, c, q, d)
	if ok then
		local eta = comingSeconds(q.pickup, c.plot)
		local pickup = Drive.place(q.pickup, c.plot)
		notice(q.player, firstName(driverName(c, d)) .. " is free now and brings the car to " .. (if pickup then Drive.atName(pickup) else "you") .. " (" .. Drive.clock(eta) .. ").")
	else
		warn("[Drivers] queued ride failed: " .. tostring(res))
	end
end
-- limousine bookings that waited for a car: first come, first served
local function serveLimoQueue()
	local i = 1
	while i <= #limoQueue do
		local q = limoQueue[i]
		local player = q.player
		local gone = not player.Parent or not sessionOf(player)
		if gone or zoneOf(player) ~= "abroad" then
			table.remove(limoQueue, i)
			clearQueued(player)
			if not gone then notice(player, "Your VIP limousine booking was cancelled - you left Port Meridian.") end
			continue
		end
		local _, r0 = rootOf(player)
		if r0 then
			local here = Drive.nearestPickup(r0.Position, "abroad", nil)
			if here and here.id ~= q.pickup then
				if here.id == q.to then
					table.remove(limoQueue, i)
					clearQueued(player)
					notice(player, "Your VIP limousine booking was cancelled - you're already at " .. Drive.atName(here) .. ".")
					continue
				end
				q.pickup = here.id
			end
		end
		if limoReady(q.pickup) == nil then
			i += 1
			continue
		end
		table.remove(limoQueue, i)
		clearQueued(player)
		local ok, res = pcall(startLimo, q)
		if ok and res then
			local pickup = Drive.place(q.pickup)
			notice(player, "Your VIP limousine is coming to " .. (if pickup then Drive.atName(pickup) else "you") .. " now.")
		elseif not ok then
			warn("[Drivers] queued limousine failed: " .. tostring(res))
		end
	end
end

------------------------------------------------------------------------------------------------ garage barrier
local function proxyFor(c: Company): Model?
	if c.detached then return nil end
	local p = Plot.get(c.player)
	local office = if p then p.office else nil
	if not office or not c.plot then return nil end
	if c.proxy and c.proxy.Parent == office then return c.proxy end
	if c.proxy then c.proxy:Destroy() end
	local m = Instance.new("Model")
	m.Name = "DriverProxy"
	m:SetAttribute("OwnerUserId", c.userId)
	m:SetAttribute("RoleId", "support")
	m:SetAttribute("EmployeeName", if c.drivers > 0 then driverName(c, 1) else "Fleet driver")
	local part = Instance.new("Part")
	part.Name = "HumanoidRootPart"
	part.Size = Vector3.new(1, 1, 1); part.Transparency = 1; part.Anchored = true; part.CanCollide = false; part.CanTouch = false; part.CanQuery = false
	part.CastShadow = false
	local cf = Drive.plotCF(c.plot)
	part.CFrame = if cf then cf * CFrame.new(102, 3, -137) else CFrame.new()
	part.Parent = m
	m.PrimaryPart = part
	m.Parent = office
	c.proxy = m
	return m
end
local function openBarrier(c: Company)
	local proxy = proxyFor(c)
	if not proxy then return end
	pcall(function()
		local office = proxy.Parent :: Model
		local door = Doors.find(office, "SITE_BARRIER")
		if door then Doors.requestNPC(proxy, door) end
	end)
end

------------------------------------------------------------------------------------------------ tick
local function stepRide(r: Ride, c: Company?, t: number): boolean -- false = finished
	-- garage barrier (home rides through the ramp head)
	if c then
		for _, pass in r.barriers do
			if t >= pass - DriverService.BARRIER_LEAD and t <= pass + DriverService.BARRIER_AFTER and t - r.barrierAsk >= 1 then
				r.barrierAsk = t
				openBarrier(c)
				break
			end
		end
	end
	if (r.kind == "founder" or r.kind == "limo") and not r.reposition then
		if r.rider and not r.rider.Parent then
			-- the founder left the game: the ride goes on empty and the car drives back
			r.hold = nil
			if r.state == "coming" or r.state == "waiting" then
				dropBooking(r, c)
			elseif r.state == "riding" then
				leaveRide(r, c, false)
			end
			if r.folder.Parent == nil then return false end
		end
		-- the founder is in the other city / in flight: his booking here is void
		local rider = r.rider
		if rider and (r.state == "coming" or r.state == "waiting") and zoneOf(rider) ~= r.zone then
			notice(rider, if r.zone == "abroad" then "Your VIP limousine booking was cancelled - you left Port Meridian."
				else "Your company car booking was cancelled - you left the city.")
			dropBooking(r, c)
			if r.folder.Parent == nil then return false end
		end
		if r.state == "coming" then
			local arrival = if #r.segs > 0 then Drive.segEnd(r.segs[#r.segs], r.plot) else t
			if t >= arrival then
				r.state = "waiting"
				r.waitUntil = t + Drive.WAIT
				local leg = if #r.segs > 0 then Drive.segLeg(r.segs[#r.segs], r.plot) else nil
				local stand = Drive.place(r.pickup, r.plot)
				local carCF = if leg then Drive.endCF(leg) elseif stand then stand.stop else nil
				if carCF then makePrompt(r, carCF) end
				publishRide(r)
				local pickup = Drive.place(r.pickup, r.plot)
				local who = if c and r.driver > 0 then firstName(driverName(c, r.driver)) else "The VIP limousine"
				notice(r.rider, who .. " is waiting for you at " .. (if pickup then Drive.atName(pickup) else "the pick-up") .. ".")
			end
		elseif r.state == "waiting" then
			if t >= r.waitUntil then
				notice(r.rider, (if r.zone == "abroad" then "Your limousine waited " .. Drive.WAIT .. " s at " .. (if r.pickup == "pm_limo" then "the stand" else "the kerb")
					else "Your driver waited " .. Drive.WAIT .. " s and drove back") .. ". Call again from the phone when you're ready.")
				dropBooking(r, c)
				if r.folder.Parent == nil then return false end
			end
		elseif r.state == "riding" then
			if not riderValid(r) then
				-- respawned or reset: the car goes on without him
				leaveRide(r, c, false)
				if r.folder.Parent == nil then return false end
			else
				local ri = rideIndex(r)
				local rideEnd = if ri then Drive.segEnd(r.segs[ri], r.plot) else t
				if t - r.focusAt >= DriverService.FOCUS_EVERY then
					r.focusAt = t
					local pose = Drive.pose(r.segs, r.plot, t)
					if pose then holdAt(r, pose.cf.Position) end
				end
				if not r.streamed and t >= rideEnd - DriverService.STREAM_AHEAD then
					r.streamed = true
					local to = Drive.place(r.to, r.plot)
					local player = r.rider
					if to and player then task.spawn(streamAsync, player, to.door.Position) end
				end
				if t >= rideEnd + DriverService.ALIGHT then arrive(r) end
			end
		end
	end
	-- bay 1: the stand car pulled away -> the next limousine moves up from the garage
	if r.holdsStand and not r.reposition and r.state ~= "coming" and r.state ~= "waiting" then
		local first = r.segs[1]
		local from = if first then first.from else nil
		if first and (from == "pm_limo" or (from == "pm_depot" and r.segs[2] ~= nil and r.segs[2].from == "pm_limo")) then
			local leaveSeg = if from == "pm_limo" then first else r.segs[2]
			if t >= leaveSeg.t0 + DriverService.LIMO_CLEAR then
				r.holdsStand = false
				if standRide == r.id then
					if not startReposition() then setStand("empty", nil) end
				end
			end
		end
	end
	-- done when the last leg is over (a repositioning limousine: it is the idle one at the stand now)
	local done = false
	if r.state == "returning" or r.state == "driving" then
		local e = legEnd(r)
		local untilT = r.untilT
		done = t >= e and (untilT == nil or t >= untilT)
		if #r.segs == 0 then done = true end
	end
	if done then
		finishRide(r, c)
		return false
	end
	return true
end

local function scan()
	local seen: { [number]: boolean } = {}
	for _, s in Session.all() do
		local player: Player? = s.player
		if not player or s.closed or not empireOf(s) then continue end
		seen[player.UserId] = true
		local fresh = companies[player.UserId] == nil
		local c = companies[player.UserId] or ensureCompany(s)
		if c then
			c.session = s
			refreshCompany(c, not fresh)
			scanTrips(c)
		end
	end
	for uid in companies do
		if not seen[uid] then dropCompany(uid) end
	end
end

local function stepCompany(c: Company, t: number)
	for _, r in c.rides do
		local ok, res = pcall(stepRide, r, c, t)
		if not ok then
			warn("[Drivers] ride " .. r.id .. ": " .. tostring(res))
			finishRide(r, c)
		end
	end
end

function DriverService.tick(dt: number)
	if not root then return end
	scanAcc += dt
	if scanAcc >= DriverService.SCAN then
		scanAcc = 0
		scan()
	end
	local t = now()
	for _, c in companies do
		stepCompany(c, t)
		if c.queue then serveQueue(c) end
	end
	local i = 1
	while i <= #detached do
		local c = detached[i]
		stepCompany(c, t)
		if next(c.rides) == nil then
			c.folder:Destroy()
			table.remove(detached, i)
		else
			i += 1
		end
	end
	for _, r in limoRides do
		local ok, res = pcall(stepRide, r, nil, t)
		if not ok then
			warn("[Drivers] ride " .. r.id .. ": " .. tostring(res))
			finishRide(r, nil)
		end
	end
	if standState == "empty" then startReposition() end
	if #limoQueue > 0 then serveLimoQueue() end
end

------------------------------------------------------------------------------------------------ phone + remote
local MESSAGES: { [string]: string } = {
	FLYING = "You're on a flight. Call your driver when you've landed.",
	TOO_FAR = "Walk to a pick-up point first: your HQ entrance, the airport kerb or a client building in Business City.",
	TOO_FAR_abroad = "Walk to a pick-up point first: the VIP limousine stand by the arrivals hall, the Meridian Grand or a client tower.",
	ALREADY_THERE = "You're already there.",
	ALREADY_RIDING = "Your ride is already booked.",
	FLIGHT_REQUIRED = "That's in the other city - take the shuttle or the company jet first.",
	COOLDOWN = "One moment - your last booking is still being handled.",
	LEAVE_VEHICLE = "Leave your car first.",
	LOADING = "Still loading - try again in a moment.",
	BAD_PLACE = "That destination isn't on the driver's list.",
}
DriverService.MESSAGES = MESSAGES
local function messageOf(err: any, zone: string?): string?
	if typeof(err) ~= "string" then return nil end
	if zone == "abroad" and MESSAGES[err .. "_abroad"] then return MESSAGES[err .. "_abroad"] end
	return MESSAGES[err]
end
DriverService.messageOf = messageOf
-- the destination sheet for the founder (home: airport, his clients first, every Business City building, back to HQ;
-- abroad: Meridian Grand, the client towers, the airport). Without a pick-up point near him the rows carry no ETA.
local function sheetFor(s: any): { [string]: any }
	local player: Player = s.player
	local e = empireOf(s)
	local zone = zoneOf(player) or "home"
	local c = companies[player.UserId]
	local plot = if c then c.plot else plotIndex(player)
	local _, r0 = rootOf(player)
	local pickup = if r0 then Drive.nearestPickup(r0.Position, zone, plot) else nil
	local nearest, nearestD = nil, math.huge
	if r0 and not pickup then nearest, nearestD = Drive.nearestAny(r0.Position, zone, plot) end
	local items: { { [string]: any } } = {}
	local clients: { [string]: string } = {}
	-- the wait until a car can come (every company driver out / bay 1 busy): the ETAs include it (honest)
	local ready = 0
	if pickup then
		if zone == "home" then
			if c and c.drivers > 0 and not freeDriver(c) then
				local soonest = math.huge
				for _, r in busyDrivers(c) do soonest = math.min(soonest, rideEndEstimate(r)) end
				if soonest == math.huge then soonest = now() end
				ready = math.max(0, soonest - now()) + comingSeconds(pickup.id, plot, math.max(now(), soonest))
			else
				ready = comingSeconds(pickup.id, plot)
			end
		else
			ready = limoReady(pickup.id) or limoWaitEstimate(pickup.id)
		end
	end
	if e and typeof(e.deals) == "table" then
		if typeof(e.deals.accounts) == "table" then
			for id in e.deals.accounts do
				local cl = Ops.client(id)
				if cl then clients[cl.name] = "Your client" end
			end
		end
		if typeof(e.deals.tripList) == "table" then
			for _, trip in e.deals.tripList do
				local cl = if typeof(trip) == "table" then Ops.client(trip.client) else nil
				if cl then clients[cl.name] = "Visit under way" end
			end
		end
		local pinned = if typeof(e.deals.pinned) == "string" then Ops.client(e.deals.pinned) else nil
		if pinned and not clients[pinned.name] then clients[pinned.name] = "Pinned client" end
	end
	local function add(p: any, title: string, sub: string?)
		if pickup and p.id == pickup.id then return end
		local eta: number? = nil
		if pickup then
			local leg = Drive.leg(pickup.id, p.id, plot)
			if not leg then return end
			eta = math.ceil(ready + Drive.BOARD_DELAY + leg.dur)
		end
		table.insert(items, { id = p.id, title = title, sub = sub, eta = eta })
	end
	if zone == "home" then
		local airport = Drive.place("airport_departures", plot)
		if airport then add(airport, "To the airport", "City Airport departures") end
		local others: { any } = {}
		for _, p in Drive.places("home", plot) do
			if p.kind == "client" or p.kind == "hotel" then
				local d = if p.clientId then CityPlan.clientOffice(p.clientId) else nil
				local label = clients[p.name] or (if d then clients[d.name] else nil)
				if label then add(p, "To " .. p.name, label) else table.insert(others, p) end
			end
		end
		table.sort(others, function(a, b) return a.name < b.name end)
		for _, p in others do add(p, "To " .. p.name, if p.kind == "hotel" then "Hotel" else "Business City") end
		local hq = if plot then Drive.place("hq_entrance", plot) else nil
		if hq then add(hq, "Back to HQ", if c then c.company .. " HQ" else "Your HQ") end
	else
		local hotel = Drive.place("pm_hotel")
		if hotel then add(hotel, "Limo to " .. hotel.name, "Hotel") end
		for _, p in Drive.places("abroad") do
			if p.kind == "client" then
				local label = clients[p.name]
				add(p, "Limo to " .. p.name, label or "Client tower")
			end
		end
		local airport = Drive.place("pm_airport")
		if airport then add(airport, "Limo to the airport", "Port Meridian Airport") end
	end
	return { zone = zone, pickup = if pickup then pickup.id else nil, pickupName = if pickup then pickup.name else nil, places = items,
		nearest = if nearest then nearest.id else nil, nearestName = if nearest then Drive.atName(nearest) else nil,
		nearestDist = if nearest then math.floor(nearestD + 0.5) else nil }
end
DriverService.sheetFor = sheetFor

local function phoneHook(s: any, _payload: any): { [string]: any }
	local player: Player = s.player
	local e = empireOf(s)
	if not e then return { ok = true, title = "Driver", text = "Found your company first." } end
	local st = DriverService.status(player)
	local zone = zoneOf(player)
	local c = companies[player.UserId]
	local text: string
	local canBook = false
	local sheet: { [string]: any }? = nil
	if not zone then
		text = MESSAGES.FLYING
	elseif zone == "home" and (not c or c.drivers <= 0) then
		text = "Your first driver joins at the " .. stageName(Drive.FIRST_DRIVER_STAGE) .. ". In the garage you drive yourself."
	elseif st.state == "queued" then
		text = "Booked: the next free car comes to " .. tostring(st.pickupAt or "you") .. " in about " .. Drive.clock(st.eta or 0) .. "."
	elseif st.state == "coming" then
		text = (if st.driverName then firstName(st.driverName) else "The limousine") .. " is on the way to " .. tostring(st.pickupAt or "you") .. " · " .. Drive.clock(st.eta or 0) .. "."
	elseif st.state == "waiting" then
		text = (if st.driverName then firstName(st.driverName) else "The limousine") .. " is waiting for you at " .. tostring(st.pickupAt or "the pick-up") .. "."
	elseif st.state == "riding" then
		text = "You're on the way to " .. tostring(st.toName or "your destination") .. " · " .. Drive.clock(st.eta or 0) .. "."
	else
		sheet = sheetFor(s)
		local sh = sheet :: { [string]: any }
		if not sh.pickup then
			-- honest: no car can come to where he stands; the list only shows where the car goes
			local where = if sh.nearestName then sh.nearestName .. " (" .. tostring(sh.nearestDist) .. " studs)" else "a pick-up point"
			text = (if zone == "abroad" then "VIP limousine service, good day! " else "") .. "Walk to " .. where .. " first - the car picks you up there."
		elseif zone == "abroad" then
			local ready = limoReady(sh.pickup :: string)
			if ready == nil then
				text = "VIP limousine service, good day! Every car is out with a guest right now - book and the next one comes to you."
			elseif sh.pickup == "pm_limo" and ready < 1 then
				text = "VIP limousine service, good day! Your car waits at the stand by the arrivals hall. Where to?"
			else
				text = "VIP limousine service, good day! A car comes to " .. tostring(sh.pickupName) .. ". Where to?"
			end
			canBook = true
		else
			local cc = c :: Company
			local free = freeDriver(cc)
			if free then
				text = firstName(driverName(cc, free)) .. " here - the car is ready. Where to?"
			else
				local soonest = math.huge
				local what = {}
				for i, r in busyDrivers(cc) do
					soonest = math.min(soonest, rideEndEstimate(r))
					local who = firstName(driverName(cc, i))
					if r.kind == "field" then table.insert(what, who .. " is driving field staff")
					elseif r.kind == "guest" then table.insert(what, who .. " is driving client guests")
					else table.insert(what, who .. " is on a ride") end
				end
				text = table.concat(what, ", ") .. ". Next free car in about " .. Drive.clock(math.max(0, (if soonest == math.huge then now() else soonest) - now())) .. " - book it now and it comes to you."
			end
			canBook = true
		end
	end
	-- the destination sheet when there is something to book (or a list to look at) or a ride to manage; no driver
	-- yet / on a flight: the phone's answer says why
	local open = sheet ~= nil or st.state ~= "none"
	if open then
		local sh = sheet or sheetFor(s)
		sh.title = if sh.zone == "abroad" then "VIP limousine" else "Driver"
		sh.text = text
		sh.state = st.state
		sh.rideId = st.rideId
		sh.canBook = canBook and st.state == "none"
		if st.state ~= "none" then sh.places = {} end -- a ride is open: the sheet only manages it
		pcall(function() Remote.fire(player, "Notify", "DRIVE_SHEET", sh) end)
	end
	return { ok = true, title = "Driver", text = text, sheet = open }
end
DriverService.phoneHook = phoneHook

local function rideRemote(s: any, p: any): { [string]: any }
	local player: Player = s.player
	local op = p.op
	if op == "request" then
		if typeof(p.to) ~= "string" then return { ok = false, err = "BAD_INPUT" } end
		local res = DriverService.request(player, { to = p.to, purpose = "phone" })
		if not res.ok then res.text = messageOf(res.err, res.zone or zoneOf(player)) end
		return res
	elseif op == "board" then
		local zone = zoneOf(player)
		if not zone then return { ok = false, err = "FLYING" } end
		local r = founderRide(player.UserId, zone)
		if not r then return { ok = false, err = "NO_RIDE" } end
		local ok, err = board(r, player)
		return { ok = ok, err = err, rideId = r.id }
	elseif op == "cancel" then
		local id = p.rideId
		local st = DriverService.status(player)
		if typeof(id) ~= "string" then id = st.rideId end
		if typeof(id) ~= "string" then return { ok = false, err = "NO_RIDE" } end
		-- only the founder's own ride
		if id ~= st.rideId then return { ok = false, err = "NO_RIDE" } end
		local ok, err = DriverService.cancel(id)
		return { ok = ok, err = err }
	elseif op == "status" then
		local st = DriverService.status(player)
		st.ok = true
		return st
	elseif op == "places" then
		local sheet = sheetFor(s)
		sheet.ok = true
		return sheet
	end
	return { ok = false, err = "BAD_INPUT" }
end
DriverService._ride = rideRemote

local function limiterFor(name: string, kind: string): RateLimiter.Limiter
	local l = limiters[name]
	if not l then
		local lim = DriverService.LIMITS[kind] or DriverService.LIMITS.other
		l = RateLimiter.new(lim[1], lim[2])
		limiters[name] = l
	end
	return l
end
local function act(s: any, p: any): any
	local action = p.action
	local player: Player = s.player
	if action == "ride" then
		local op = p.op
		local kind = if op == "status" or op == "places" then "read" else "write"
		if not limiterFor("ride:" .. kind, kind).allow(player) then return { ok = false, err = "RATE_LIMIT" } end
		return rideRemote(s, p)
	end
	if typeof(action) == "string" then
		local h = tripHandlers[action]
		if h then
			if not limiterFor("trip:" .. action, "other").allow(player) then return { ok = false, err = "RATE_LIMIT" } end
			return h(s, p)
		end
	end
	return { ok = false, err = "BAD_INPUT" }
end
DriverService._act = act
function DriverService._resetLimits() -- test seam: fresh per-action buckets
	table.clear(limiters)
end

local function onPrompt(q: ProximityPrompt, player: Player)
	if q:GetAttribute("DriveAction") ~= "board" or q:GetAttribute("OwnerUserId") ~= player.UserId then return end
	local t = now()
	if (promptAt[player.UserId] or 0) > t then return end
	promptAt[player.UserId] = t + DriverService.PROMPT_COOLDOWN
	local zone = zoneOf(player)
	local r = if zone then founderRide(player.UserId, zone) else nil
	if not r or r.id ~= q:GetAttribute("RideId") then return end
	local ok, err = board(r, player)
	if not ok then
		notice(player, if err == "TOO_FAR" then "Step closer to the car." elseif err == "LEAVE_VEHICLE" then MESSAGES.LEAVE_VEHICLE else "You can't get in right now.")
	end
end

------------------------------------------------------------------------------------------------ init
function DriverService.init()
	local old = ReplicatedStorage:FindFirstChild("CompanyDrivers")
	if old then old:Destroy() end
	local f = Instance.new("Folder")
	f.Name = "CompanyDrivers"
	f:SetAttribute("Version", 2)
	local lf = Instance.new("Folder")
	lf.Name = "Limo"
	lf.Parent = f
	f.Parent = ReplicatedStorage
	root = f
	limoFolder = lf
	template(f, 0, DriverService.CHAUFFEUR, "chauffeur", { n = CampusMath.staffName(DriverService.CHAUFFEUR, 0) }, "Chauffeur",
		CampusMath.staffName(DriverService.CHAUFFEUR, 0) .. "\nVIP Chauffeur · Port Meridian")
	local oldPrompts = workspace:FindFirstChild("DrivePrompts")
	if oldPrompts then oldPrompts:Destroy() end
	local pf = Instance.new("Folder")
	pf.Name = "DrivePrompts"
	pf.Parent = workspace
	promptFolder = pf
	table.clear(companies); table.clear(limoRides); table.clear(promptAt); table.clear(limoQueue); table.clear(detached); table.clear(limoRequestAt)
	table.clear(limiters)
	setStand("idle", nil)
	scanAcc = DriverService.SCAN
	-- outer limit of the remote (spam guard); the per-action limits are in act()
	Remote.bind("TripAction", { burst = 30, perSecond = 10, company = true }, act)
	Phone.onAction("driver", phoneHook)
	Prompts.PromptTriggered:Connect(onPrompt)
	Session.onClosing(function(s: any)
		local player: Player? = s.player
		if not player then return end
		for _, r in limoRides do
			if r.userId == player.UserId and not r.reposition then
				r.hold = nil
				if r.state == "coming" or r.state == "waiting" then dropBooking(r, nil)
				elseif r.state == "riding" then leaveRide(r, nil, false) end
			end
		end
		local _, qi = limoQueued(player.UserId)
		if qi then table.remove(limoQueue, qi) end
		dropCompany(player.UserId)
		promptAt[player.UserId] = nil
		limoRequestAt[player.UserId] = nil
		for _, l in limiters do l.forget(player) end
	end)
end

return DriverService
