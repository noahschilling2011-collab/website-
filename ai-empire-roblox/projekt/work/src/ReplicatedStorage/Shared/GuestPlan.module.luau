--!strict
-- GuestPlan (package "guests_jet"): pure, deterministic data and maths for the client-side people of
-- GuestController - nothing here creates instances, every client computes the same people at the same time.
--   * HOTEL GUESTS (guest house of a plot, building-local coordinates, floors at y 0.15 / 16.15): a waypoint graph
--     from the BuildingPlan guest-house rooms (Plan.HOTEL strips: west rooms x -141..-124, corridor -124..-116,
--     east rooms -116..-98; doors from Plan.rooms) and the RoomKitsHotel fit-out (reception counter, lobby seats
--     H0_LOBBY_Wait1..4, breakfast chairs / window-bar stools H0_BREAKFAST_Dining*, buffet coffee): WestPath ->
--     automatic entrance door -> lobby -> check-in desk / lounge seats -> glass door -> guest corridor -> breakfast
--     aisles, the switchback stair (front landing, flight A, mid landing, flight B) and the 12 room doors (the
--     guest walks to the door and goes in = disappears). Every edge keeps clear of walls and furniture
--     (tests/guests_jet/test_guests + hotel_paths.py against the built guest house).
--     Guests: N = min(HotelGuests, HotelRooms) slots per plot (one room each). Slots 1..BASE_GUESTS (CompanyOps:
--     rooms x occupancy = 7) are ordinary guests: a slot's stays last 1-3 nights (seeded per plot + slot); on a
--     turnover day the old guest has breakfast, fetches the suitcase and checks out at the desk (10:00-11:24), the
--     new one arrives with a suitcase in the afternoon (13:30-17:00), checks in and goes to the room. Staying guests
--     come down for breakfast (08:00-09:24 company clock, CompanyOps.hour), ~55 % go out for the day and return
--     16:00-18:00, half of the others read in the lobby around midday, ~3/4 sit in the lobby (its four seats first) /
--     at the window bar in the evening (from 18:05, back in the room by 23:30). Slots above BASE_GUESTS are hosted
--     client teams (CORE_SPEC 11.3: HotelGuests = 7 + 2 per team in the house): breakfast together, the workshop in
--     the first-floor Workshop Room (H1_WORKSHOP) 09:00-16:30, the lobby in the evening. A slot's day never depends
--     on N (seats: lobby seats first in slot order among the guests who come down; midday seats by a daily
--     permutation), so a team checking in or out never moves anybody else. Live changes of N (GuestController):
--     added slots arrive from the street with their suitcase (GP.joinActors), removed ones finish what they are
--     doing and leave with the suitcase (GP.leaveActors). Seats are unique per day. Times are seconds into the
--     CompanyOps day (Ops.DAY; 0 = 08:00), the day index is floor(serverTime / Ops.DAY).
--   * TERMINAL PASSENGERS tied to the real shuttle timetable (FlightPlan): City Airport departures of every "out"
--     leg (door -> check-in serpentine + desk -> security lane -> concourse -> a gate A1 seat with their bag ->
--     boarding call -> boarding lane -> the jet bridge door), City Airport arrivals of every "back" leg (arrival
--     point -> baggage carousel -> trolley -> arrivals door), Port Meridian arrivals of every "out" leg (airstair
--     -> apron walkway -> apron door -> baggage claim -> trolley -> south exits) and departures of every "back" leg
--     (south entrance -> check-in -> benches -> apron door -> airstair). City Airport uses the airport package's
--     walk graph (CityPlan.AIRPORT.walk, read-only) plus seat aisles; Port Meridian a small graph of its own.
local CityPlan=require(script.Parent.Config.CityPlan)
local FP=require(script.Parent.FlightPlan)
local Ops=require(script.Parent.CompanyOps)
local Aircraft=require(script.Parent.AircraftModel)
local okMetro,MetroPlan=pcall(require,script.Parent.Config.MetroPlan)
local GP={}

GP.GUEST_SPEED=4.0
GP.PAX_SPEED=4.6
GP.QUEUE_SPEED=2.2
GP.HOTEL_CAP=12 -- guests per plot (one per room: Plan.HOTEL_ROOMS)
GP.BASE_GUESTS=math.floor(Ops.GUEST.rooms*Ops.GUEST.occupancy+0.5) -- CompanyOps.hotelGuests without hosted teams (7)
GP.TEAM=Ops.HOSTED.guests -- guests per hosted client team (2)
GP.EVENING_SHARE=0.74 -- share of the guests who come down to the lobby / window bar in the evening
GP.HOME_DEPARTURES=14 -- passengers per out leg at City Airport
GP.HOME_ARRIVALS=12
GP.PM_ARRIVALS=12
GP.PM_DEPARTURES=8

export type Seg={kind: string,t0: number,t1: number,path: {Vector3}?,cum: {number}?,at: CFrame?,pose: string?,carry: string?}
export type Actor={id: string,seed: number,segs: {Seg},role: string}
export type Place={hub: string,tail: {Vector3},face: Vector3?,sit: boolean?}
export type Graph={p: {[string]: Vector3},links: {[string]: {string}},cache: {[string]: {string}}}

------------------------------------------------------------------------------------------------ helpers
local function mix(h: number): number
	for _=1,3 do h=(h*48271)%2147483647 end
	return h
end
function GP.hash(s: string): number
	local h=7
	for i=1,#s do h=(h*31+string.byte(s,i))%2147483647 end
	return mix(h+1)
end
local hash=GP.hash
local function u(key: string): number return (hash(key)%100003)/100003 end
GP.u=u
local function v(x: number,y: number,z: number): Vector3 return Vector3.new(x,y,z) end
local function flat(d: Vector3): Vector3
	local f=Vector3.new(d.X,0,d.Z)
	return if f.Magnitude>1e-5 then f.Unit else Vector3.new(0,0,-1)
end
-- seeded permutation of 1..n
local function perm(n: number,key: string): {number}
	local out: {number}={}
	for i=1,n do out[i]=i end
	for i=n,2,-1 do
		local j=1+hash(key..":"..i)%i
		out[i],out[j]=out[j],out[i]
	end
	return out
end
GP.perm=perm

------------------------------------------------------------------------------------------------ graphs
local function newGraph(): Graph return {p={},links={},cache={}} end
local function node(g: Graph,name: string,p: Vector3)
	g.p[name]=p;g.links[name]=g.links[name] or {}
end
local function link(g: Graph,a: string,b: string)
	assert(g.p[a] and g.p[b],"GuestPlan link "..a.." - "..b)
	table.insert(g.links[a],b);table.insert(g.links[b],a)
end
local function chain(g: Graph,list: {string}) for i=2,#list do link(g,list[i-1],list[i]) end end
-- shortest path (Dijkstra, node names a..b inclusive)
local function shortest(g: Graph,a: string,b: string): {string}
	local key=a.."|"..b
	local c=g.cache[key]
	if c then return c end
	local dist: {[string]: number}={[a]=0}
	local prev: {[string]: string}={}
	local done: {[string]: boolean}={}
	while true do
		local best,bd=nil,math.huge
		for n,d in dist do if not done[n] and d<bd then best,bd=n,d end end
		if not best or best==b then break end
		done[best]=true
		for _,m in g.links[best] do
			local nd=bd+(g.p[m]-g.p[best]).Magnitude
			if nd<(dist[m] or math.huge) then dist[m]=nd;prev[m]=best end
		end
	end
	local out: {string}={}
	if dist[b]==nil then return {a} end
	local n: string?=b
	while n do table.insert(out,1,n);n=prev[n] end
	g.cache[key]=out
	return out
end
GP.shortest=shortest
local function finalPos(g: Graph,pl: Place): Vector3
	return if #pl.tail>0 then pl.tail[#pl.tail] else g.p[pl.hub]
end
local function push(pts: {Vector3},p: Vector3)
	local last=pts[#pts]
	if not last or (last-p).Magnitude>0.05 then table.insert(pts,p) end
end
-- polyline from place a's spot to place b's spot (a's tail backwards, the graph, b's tail)
local function route(g: Graph,a: Place,b: Place): {Vector3}
	local pts: {Vector3}={}
	for i=#a.tail,1,-1 do push(pts,a.tail[i]) end
	for _,n in shortest(g,a.hub,b.hub) do push(pts,g.p[n]) end
	for _,p in b.tail do push(pts,p) end
	if #pts==1 then table.insert(pts,pts[1]) end
	return pts
end
GP.route=route
local function cumulative(path: {Vector3}): ({number},number)
	local cum: {number}={0}
	local total=0
	for i=2,#path do total+=(path[i]-path[i-1]).Magnitude;cum[i]=total end
	return cum,total
end
function GP.pathLength(path: {Vector3}): number local _,t=cumulative(path);return t end

------------------------------------------------------------------------------------------------ actors
type Builder={g: Graph,segs: {Seg},t: number,at: Place}
local function builder(g: Graph,t: number,at: Place): Builder return {g=g,segs={},t=t,at=at} end
-- walk from the current place to `to` at `speed`, starting now; returns the arrival time
local function walk(b: Builder,to: Place,speed: number,carry: string?): number
	local path=route(b.g,b.at,to)
	local cum,len=cumulative(path)
	local t1=b.t+math.max(0.5,len/speed)
	table.insert(b.segs,{kind="walk",t0=b.t,t1=t1,path=path,cum=cum,carry=carry})
	b.t=t1;b.at=to
	return t1
end
-- walk a fixed polyline (from the current spot) and end at `to`
local function walkPath(b: Builder,path: {Vector3},to: Place,speed: number,carry: string?): number
	local cum,len=cumulative(path)
	local t1=b.t+math.max(0.5,len/speed)
	table.insert(b.segs,{kind="walk",t0=b.t,t1=t1,path=path,cum=cum,carry=carry})
	b.t=t1;b.at=to
	return t1
end
local function stay(b: Builder,untilT: number,pose: string?,carry: string?)
	if untilT<=b.t then return end
	local p=finalPos(b.g,b.at)
	local f=b.at.face or Vector3.new(0,0,-1)
	table.insert(b.segs,{kind=if b.at.sit then "sit" else "stand",t0=b.t,t1=untilT,at=CFrame.lookAt(p,p+f),pose=pose,carry=carry})
	b.t=untilT
end
-- walk to a seat and sit until `untilT` - unless the seat cannot be reached at least `minSit` seconds before
-- that (then the walk is skipped: nobody walks into a seat and straight out again)
local function sitUntil(b: Builder,seat: Place,untilT: number,speed: number,pose: string?,carry: string?,minSit: number?): boolean
	local len=GP.pathLength(route(b.g,b.at,seat))
	if b.t+len/speed+(minSit or 5)>untilT then return false end
	walk(b,seat,speed,carry)
	stay(b,untilT,pose,carry)
	return true
end
local function hide(b: Builder,untilT: number,at: Place)
	b.t=math.max(b.t,untilT);b.at=at
end
-- What actor a does at time t: mode "hidden" | "walk" | "sit" | "stand", the frame of the feet (facing), the pose
-- hint, what it carries ("suitcase" | "trolley" | "bag" | nil) and the walking phase distance.
function GP.sample(a: Actor,t: number): (string,CFrame?,string?,string?,number)
	for _,s in a.segs do
		if t<s.t0 then return "hidden",nil,nil,nil,0 end
		if t<s.t1 then
			if s.kind=="walk" then
				local path=s.path :: {Vector3}
				local cum=s.cum :: {number}
				local len=cum[#cum]
				local d=len*(t-s.t0)/(s.t1-s.t0)
				for i=2,#path do
					if d<=cum[i] or i==#path then
						local seg=cum[i]-cum[i-1]
						local f=if seg>1e-6 then math.clamp((d-cum[i-1])/seg,0,1) else 1
						local p=path[i-1]:Lerp(path[i],f)
						return "walk",CFrame.lookAt(p,p+flat(path[i]-path[i-1])),nil,s.carry,d
					end
				end
			end
			return s.kind,s.at,s.pose,s.carry,0
		end
	end
	return "hidden",nil,nil,nil,0
end
-- first and last visible time of an actor
function GP.span(a: Actor): (number,number)
	if #a.segs==0 then return math.huge,-math.huge end
	return a.segs[1].t0,a.segs[#a.segs].t1
end

------------------------------------------------------------------------------------------------ hotel graph
local Y0,Y1=0.15,16.15
local W,E,N,S=Vector3.new(-1,0,0),Vector3.new(1,0,0),Vector3.new(0,0,-1),Vector3.new(0,0,1)
local H=newGraph()
GP.HOTEL_GRAPH=H
do
	local function n(name: string,x: number,y: number,z: number) node(H,name,v(x,y,z)) end
	-- outside: the colonnade / WestPath (x -96..-88) and the automatic door (x -98, z 86..94)
	n("street",-92,Y0,60);n("path",-92,Y0,90);n("doorOut",-95.8,Y0,90);n("doorIn",-100.6,Y0,90)
	-- lobby: centre, check-in desk hub, the seating ring round the coffee table, the glass door to the corridor
	n("lobby",-104.6,Y0,89);n("deskHub",-105.6,Y0,95.4)
	n("lobbyE",-104.75,Y0,85.2);n("sofaE",-104.75,Y0,80.65);n("sofaM",-107.8,Y0,80.65);n("sofaW",-111.0,Y0,80.65);n("lobbyW",-111.0,Y0,85.2)
	n("lobbyDoor",-114.4,Y0,86)
	chain(H,{"street","path","doorOut","doorIn","lobby","lobbyE","sofaE","sofaM","sofaW","lobbyW","lobbyE"})
	link(H,"lobby","deskHub");link(H,"lobbyW","lobbyDoor")
	-- ground-floor corridor (x -120) and the breakfast room (door opening x -116, z 118..126): west aisle x -113.8,
	-- east aisle x -104.6 (between the chairs and the window-bar stools), cross aisles between the tables
	for _,z in {79.6,86,122,126.5,140.5,154.5,168.5} do n("c0_"..z,-120,Y0,z) end
	chain(H,{"c0_79.6","c0_86","c0_122","c0_126.5","c0_140.5","c0_154.5","c0_168.5"})
	link(H,"lobbyDoor","c0_86")
	n("bfIn",-113.8,Y0,122)
	for _,z in {110,113.75,123.25,134.2} do n("bfW"..z,-113.8,Y0,z) end
	for _,z in {105.4,113.75,123.25,134.2} do n("bfE"..z,-104.6,Y0,z) end
	link(H,"c0_122","bfIn")
	chain(H,{"bfW110","bfW113.75","bfIn","bfW123.25","bfW134.2"})
	chain(H,{"bfE105.4","bfE113.75","bfE123.25","bfE134.2"})
	link(H,"bfW113.75","bfE113.75");link(H,"bfW123.25","bfE123.25");link(H,"bfW134.2","bfE134.2")
	-- switchback stair (Plan.HOTEL_STAIR_LAYOUT): door x -124 z 79.6, front landing, flight A (x -136.85, +Z, up 8),
	-- mid landing (z 99.75), flight B (x -128.5, -Z, up 8) to the front landing of level 1
	n("st0",-127.6,Y0,79.6);n("stA0",-136.85,Y0,82.6);n("stA1",-136.85,Y0+8,98.4);n("stM0",-136.85,Y0+8,99.75);n("stM1",-128.5,Y0+8,99.75)
	n("stB1",-128.5,Y0+8,98.4);n("stB0",-128.5,Y1,82.6);n("st1",-127.6,Y1,79.6)
	chain(H,{"c0_79.6","st0","stA0","stA1","stM0","stM1","stB1","stB0","st1"})
	-- first-floor corridor
	for _,z in {79.6,90,107.5,112.5,126.5,129.5,140.5,151.5,154.5,168.5} do n("c1_"..z,-120,Y1,z) end
	chain(H,{"c1_79.6","c1_90","c1_107.5","c1_112.5","c1_126.5","c1_129.5","c1_140.5","c1_151.5","c1_154.5","c1_168.5"})
	link(H,"st1","c1_79.6")
end
-- rooms 1..12 = H0_R01..H1_R12 (Plan.rooms): door point in front of the door (the guest goes in there)
GP.HOTEL_ROOMS={
	{id="H0_R01",number=101,hub="c0_126.5",door=v(-123.3,Y0,126.5)},{id="H0_R02",number=102,hub="c0_140.5",door=v(-123.3,Y0,140.5)},
	{id="H0_R03",number=103,hub="c0_154.5",door=v(-123.3,Y0,154.5)},{id="H0_R04",number=104,hub="c0_168.5",door=v(-123.3,Y0,168.5)},
	{id="H1_R05",number=201,hub="c1_112.5",door=v(-123.3,Y1,112.5)},{id="H1_R06",number=202,hub="c1_126.5",door=v(-123.3,Y1,126.5)},
	{id="H1_R07",number=203,hub="c1_140.5",door=v(-123.3,Y1,140.5)},{id="H1_R08",number=204,hub="c1_154.5",door=v(-123.3,Y1,154.5)},
	{id="H1_R09",number=205,hub="c1_168.5",door=v(-123.3,Y1,168.5)},{id="H1_R10",number=206,hub="c1_107.5",door=v(-116.7,Y1,107.5)},
	{id="H1_R11",number=207,hub="c1_129.5",door=v(-116.7,Y1,129.5)},{id="H1_R12",number=208,hub="c1_151.5",door=v(-116.7,Y1,151.5)},
}
local function roomPlace(i: number): Place
	local r=GP.HOTEL_ROOMS[i] or GP.HOTEL_ROOMS[1]
	return {hub=r.hub,tail={r.door},face=if r.door.X<-120 then W else E}
end
local STREET: Place={hub="street",tail={}}
-- the Workshop Room's glass double door (H1_WORKSHOP, east side of the first-floor corridor, z 87..93): the hosted
-- team goes in there (disappears) for the workshop
local WORKSHOP: Place={hub="c1_90",tail={v(-116.7,Y1,90)},face=E}
GP.WORKSHOP=WORKSHOP
local DESKS: {Place}={{hub="deskHub",tail={v(-107.3,Y0,97.6)},face=W},{hub="deskHub",tail={v(-107.3,Y0,100.6)},face=W}}
-- breakfast seats: west chairs (x -110.8; Dining 3, 5, 7, 9, 11 - Dining1 sits behind a planter), east chairs
-- (x -108.2; Dining 2..12), window-bar stools (x -101.3; Dining 13..20). seat = feet of the seated rig.
local function aisleHub(x: number,z: number): string
	local list: {number}=if x<-109 then {110,113.75,123.25,134.2} else {105.4,113.75,123.25,134.2}
	local best,bd=list[1],math.huge
	for _,lz in list do if math.abs(lz-z)<bd then best,bd=lz,math.abs(lz-z) end end
	if x<-109 and math.abs(best-122)>math.abs(z-122) and math.abs(z-122)<bd then return "bfIn" end
	return (if x<-109 then "bfW" else "bfE")..best
end
local function seatPlace(seat: Vector3,face: Vector3,aisleX: number): Place
	return {hub=aisleHub(aisleX,seat.Z),tail={v(aisleX,seat.Y,seat.Z),seat},face=face,sit=true}
end
GP.BREAKFAST_SEATS={} :: {Place}
for i,z in {111.4,116.1,120.9,125.6,130.4} do
	table.insert(GP.BREAKFAST_SEATS,seatPlace(v(-110.8,Y0,z),if i%2==1 then N else S,-113.8))
end
for i,z in {106.6,111.4,116.1,120.9,125.6,130.4} do
	table.insert(GP.BREAKFAST_SEATS,seatPlace(v(-108.2,Y0,z),if i%2==1 then S else N,-104.6))
end
for _,z in {107.5,111.2,114.9,118.6,122.4,126.1,129.8,133.5} do
	table.insert(GP.BREAKFAST_SEATS,seatPlace(v(-101.3,Y0,z),E,-104.6))
end
-- evening seats: the lobby sofa (Wait1 / Wait2), the two armchairs (Wait3 / Wait4) and the window-bar stools
GP.LOUNGE_SEATS={
	{hub="sofaM",tail={v(-106.2,Y0,80.65),v(-106.2,Y0,78.4)},face=S,sit=true},
	{hub="sofaM",tail={v(-109.3,Y0,80.65),v(-109.3,Y0,78.4)},face=S,sit=true},
	{hub="sofaW",tail={v(-111.0,Y0,81.2),v(-113.3,Y0,81.2)},face=E,sit=true},
	{hub="sofaE",tail={v(-104.75,Y0,81.2),v(-102.3,Y0,81.2)},face=W,sit=true},
} :: {Place}
for k=13,20 do table.insert(GP.LOUNGE_SEATS,GP.BREAKFAST_SEATS[k-1]) end -- stools (index 12 + (k - 12))
GP.COFFEE={{hub="bfE134.2",tail={v(-105.6,Y0,134.2),v(-105.6,Y0,135.2)},face=S},{hub="bfE134.2",tail={v(-107.4,Y0,134.2),v(-107.4,Y0,135.2)},face=S}} :: {Place}

------------------------------------------------------------------------------------------------ hotel schedules
-- hour of the company clock -> seconds into the CompanyOps day (0 = 08:00)
function GP.sOfHour(h: number): number
	if h>=8 and h<18 then return (h-8)*90 end
	local hh=if h>=18 then h-18 else h+6
	return 900+hh/14*300
end
local sOf=GP.sOfHour
function GP.dayOf(t: number): (number,number)
	local d=math.floor(t/Ops.DAY)
	return d,t-d*Ops.DAY
end
-- slot g's stay on day d: stay index k, arrival day a, nights L
function GP.stay(plotSeed: number,g: number,d: number): (number,number,number)
	local hs=hash("stay:"..plotSeed..":"..g)
	local L=1+hs%3
	local off=math.floor(hs/7)%L
	local k=math.floor((d+off)/L)
	return k,k*L-off,L
end
-- guests shown for a plot: one per room
function GP.guestCount(hotelGuests: any,hotelRooms: any): number
	local g=if typeof(hotelGuests)=="number" then math.floor(hotelGuests) else 0
	local r=if typeof(hotelRooms)=="number" then math.floor(hotelRooms) else GP.HOTEL_CAP
	return math.clamp(g,0,math.min(r,GP.HOTEL_CAP,#GP.HOTEL_ROOMS))
end
local function roomOf(plotSeed: number,g: number): number
	return perm(#GP.HOTEL_ROOMS,"rooms:"..plotSeed)[g] or g
end
GP.roomOf=roomOf
-- hosted client team slot (above CompanyOps' ordinary occupancy)?
function GP.isHosted(g: number): boolean return g>GP.BASE_GUESTS end
-- Does slot g come down to the lobby / window bar in the evening of day d? (independent of the number of guests)
local function eveningWant(plotSeed: number,g: number,d: number): boolean
	return u("eve:"..plotSeed..":"..g..":"..d)<GP.EVENING_SHARE
end
-- the day's order of the evening seats: the lobby's four seats (shuffled) before the window-bar stools (shuffled)
local function seatOrder(plotSeed: number,d: number): {number}
	local lobby=perm(4,"lobby:"..plotSeed..":"..d)
	local bar=perm(#GP.LOUNGE_SEATS-4,"bar:"..plotSeed..":"..d)
	local out: {number}={}
	for _,i in lobby do table.insert(out,i) end
	for _,i in bar do table.insert(out,4+i) end
	return out
end
-- The day's actors of slot g (building-local, times = seconds into the CompanyOps day d), independent of the number
-- of guests (n is accepted for compatibility and ignored):
--   hosted slot: one team member ("hosted");
--   turnover day (d = arrival day of the stay): "leave" (the previous guest) + "arrive" (the new one);
--   otherwise one staying guest.
local plans: {[string]: {Actor}}={}
local planCount=0
-- drop the cached day plans (tests: compare plans computed from scratch)
function GP.clearPlans() table.clear(plans);planCount=0 end
function GP.slotDay(plotSeed: number,g: number,d: number,_n: number?): {Actor}
	local key=plotSeed..":"..g..":"..d
	local c=plans[key]
	if c then return c end
	local k,a,_L=GP.stay(plotSeed,g,d)
	local room=roomPlace(roomOf(plotSeed,g))
	local bfSeat=GP.BREAKFAST_SEATS[perm(#GP.BREAKFAST_SEATS,"bf:"..plotSeed..":"..d)[g] or 1]
	-- evening seat: the lobby's four seats first, in slot order among the slots that come down tonight; midday
	-- seat: a daily permutation of the 12 lounge seats - both unique per day and independent of N
	local rank=1
	for h=1,g-1 do if eveningWant(plotSeed,h,d) then rank+=1 end end
	local lounge=GP.LOUNGE_SEATS[seatOrder(plotSeed,d)[math.clamp(rank,1,#GP.LOUNGE_SEATS)]]
	local noonSeat=GP.LOUNGE_SEATS[perm(#GP.LOUNGE_SEATS,"noon:"..plotSeed..":"..d)[math.clamp(g,1,#GP.LOUNGE_SEATS)]]
	local eveningOk=eveningWant(plotSeed,g,d)
	local desk=DESKS[(g%2)+1]
	local out: {Actor}={}
	local function key2(who: number,what: string): string return plotSeed..":"..g..":"..who..":"..d..":"..what end
	-- breakfast for whoever slept here (stay k-1 on a turnover day, else stay k)
	local function breakfast(b: Builder,who: number,early: boolean?)
		b.t=sOf(8.0+u(key2(who,"b0"))*(if early then 0.5 else 1.4))
		walk(b,bfSeat,GP.GUEST_SPEED)
		stay(b,b.t+40+u(key2(who,"eat"))*30,"eat")
	end
	-- the lobby / window bar after dinner (leaving the room 17:30-18:30), back in the room by 23:30 at the latest
	-- (night hours are short: 21.4 s each)
	local function evening(b: Builder,who: number)
		if not eveningOk then return end
		local e0=sOf(17.5+u(key2(who,"e0"))*1.0)
		if e0<b.t+5 then return end
		local there=GP.pathLength(route(H,room,lounge))/GP.GUEST_SPEED
		local back=GP.pathLength(route(H,lounge,room))/GP.GUEST_SPEED
		local untilT=math.min(e0+there+40+u(key2(who,"e1"))*30,sOf(23.5)-back)
		if untilT<e0+there+12 then return end
		hide(b,e0,room)
		walk(b,lounge,GP.GUEST_SPEED)
		stay(b,untilT,"relax")
		walk(b,room,GP.GUEST_SPEED)
	end
	if GP.isHosted(g) then
		-- a hosted client team member: breakfast with the team, the workshop upstairs, the lobby in the evening
		local m=(g-GP.BASE_GUESTS-1)%GP.TEAM
		local b=builder(H,0,room)
		b.t=sOf(8.05+m*0.12+u(key2(0,"hb"))*0.06)
		walk(b,bfSeat,GP.GUEST_SPEED)
		stay(b,b.t+45+u(key2(0,"heat"))*20,"eat")
		walk(b,room,GP.GUEST_SPEED)
		hide(b,math.max(b.t+15,sOf(8.95+m*0.04)),room)
		walk(b,WORKSHOP,GP.GUEST_SPEED,"bag")
		hide(b,math.max(b.t+30,sOf(16.4+m*0.06+u(key2(0,"hw"))*0.2)),WORKSHOP)
		walk(b,room,GP.GUEST_SPEED,"bag")
		evening(b,0)
		table.insert(out,{id="g"..g..":hosted",seed=hash("guest:"..plotSeed..":"..g..":hosted"),segs=b.segs,role="hosted"})
	elseif d==a then
		-- the guest of the previous stay checks out
		local who=k-1
		local b=builder(H,0,room)
		breakfast(b,who,true)
		walk(b,room,GP.GUEST_SPEED)
		hide(b,math.max(b.t+20,sOf(10.0+u(key2(who,"c0"))*1.2)),room)
		walk(b,desk,GP.GUEST_SPEED,"suitcase")
		stay(b,b.t+10+u(key2(who,"cd"))*6,"checkout","suitcase")
		walk(b,STREET,GP.GUEST_SPEED,"suitcase")
		table.insert(out,{id="g"..g..":"..who,seed=hash("guest:"..plotSeed..":"..g..":"..who),segs=b.segs,role="leave"})
		-- the new guest arrives
		local b2=builder(H,sOf(13.5+u(key2(k,"a0"))*3.5),STREET)
		walk(b2,desk,GP.GUEST_SPEED,"suitcase")
		stay(b2,b2.t+12+u(key2(k,"ad"))*6,"checkin","suitcase")
		walk(b2,room,GP.GUEST_SPEED,"suitcase")
		evening(b2,k)
		table.insert(out,{id="g"..g..":"..k,seed=hash("guest:"..plotSeed..":"..g..":"..k),segs=b2.segs,role="arrive"})
	else
		local b=builder(H,0,room)
		breakfast(b,k)
		if u(key2(k,"out?"))<0.55 then
			walk(b,STREET,GP.GUEST_SPEED)
			hide(b,math.max(b.t+30,sOf(16.0+u(key2(k,"r0"))*2.0)),STREET)
			walk(b,room,GP.GUEST_SPEED)
		else
			if u(key2(k,"cof?"))<0.35 then
				walk(b,GP.COFFEE[(g%2)+1],GP.GUEST_SPEED)
				stay(b,b.t+6,"pour")
			end
			walk(b,room,GP.GUEST_SPEED)
			-- half of those staying in read in the lobby / at the window bar around midday
			if u(key2(k,"noon?"))<0.5 then
				hide(b,math.max(b.t+20,sOf(11.5+u(key2(k,"n0"))*3.0)),room)
				walk(b,noonSeat,GP.GUEST_SPEED)
				stay(b,b.t+60+u(key2(k,"n1"))*70,"relax")
				walk(b,room,GP.GUEST_SPEED)
			end
		end
		evening(b,k)
		table.insert(out,{id="g"..g..":"..k,seed=hash("guest:"..plotSeed..":"..g..":"..k),segs=b.segs,role="stay"})
	end
	planCount+=1
	if planCount>400 then table.clear(plans);planCount=0 end
	plans[key]=out
	return out
end
-- Guests checked in at day-second s of day d (in the house: rooms, breakfast, lounge, desk) for N slots.
function GP.inHouse(plotSeed: number,n: number,d: number,s: number): number
	local count=0
	for g=1,n do
		local _,a=GP.stay(plotSeed,g,d)
		if GP.isHosted(g) or d~=a then count+=1
		else
			for _,act in GP.slotDay(plotSeed,g,d,n) do
				local first,last=GP.span(act)
				if act.role=="leave" and s<last then count+=1 end
				if act.role=="arrive" and s>=first then count+=1 end
			end
		end
	end
	return count
end

-- Live changes of the guest count (GuestController; client-only, at the moment the client sees HotelGuests change).
local function endPoint(sg: Seg): Vector3
	if sg.kind=="walk" and sg.path then local p=sg.path :: {Vector3};return p[#p] end
	return if sg.at then (sg.at :: CFrame).Position else Vector3.zero
end
-- the whole visible episodes (runs of segments without a gap) of `a` that start at or after t; skipFirst drops the
-- actor's first episode
local function episodesFrom(a: Actor,t: number,skipFirst: boolean): {Seg}
	local out: {Seg}={}
	local started,episode=false,0
	for j,sg in a.segs do
		local prev=a.segs[j-1]
		if prev==nil or sg.t0>prev.t1+1e-6 then episode+=1 end
		if not started and sg.t0>=t and (prev==nil or sg.t0>prev.t1+1e-6) and not (skipFirst and episode==1) then started=true end
		if started then table.insert(out,sg) end
	end
	return out
end
-- A slot that appears now (s = second of day d): the guest comes in from the street with the suitcase (order:
-- the k-th new slot follows 2.5 s behind the previous one - a team arrives together), checks in, goes to the room,
-- then follows the slot's day from its next outing.
function GP.joinActors(plotSeed: number,g: number,d: number,s: number,order: number?): {Actor}
	local base=GP.slotDay(plotSeed,g,d)
	local last=base[#base]
	local room=roomPlace(roomOf(plotSeed,g))
	local b=builder(H,s+((order or 1)-1)*2.5,STREET)
	walk(b,DESKS[(g%2)+1],GP.GUEST_SPEED,"suitcase")
	stay(b,b.t+10+u("join:"..plotSeed..":"..g..":"..d)*5,"checkin","suitcase")
	walk(b,room,GP.GUEST_SPEED,"suitcase")
	local out: {Actor}={{id="g"..g..":join"..d..":"..math.floor(s),seed=if last then last.seed else hash("guest:"..plotSeed..":"..g),segs=b.segs,role="arrive"}}
	for _,a in base do
		if a.role=="leave" then continue end -- the room had no guest before: nobody checks out of it today
		local segs=episodesFrom(a,b.t+0.5,a.role=="arrive") -- a turnover day's arrival already happened above
		if #segs>0 then table.insert(out,{id=a.id,seed=a.seed,segs=segs,role=a.role}) end
	end
	return out
end
-- A slot that disappears now: a guest who is visible finishes the current walk / visit; whoever is (or ends up) in
-- the room comes out with the suitcase, checks out at the desk and leaves into the street. A guest who is out in
-- town stays away.
function GP.leaveActors(plotSeed: number,g: number,d: number,s: number,current: {Actor}?): {Actor}
	local base=current or GP.slotDay(plotSeed,g,d) -- current: the slot's actors shown today (an earlier join)
	local room=roomPlace(roomOf(plotSeed,g))
	local door=room.tail[1]
	local wsDoor=WORKSHOP.tail[1]
	local out: {Actor}={}
	local leaveAt: number?=nil
	local fromWorkshop=false
	local seed: number=hash("guest:"..plotSeed..":"..g)
	for _,a in base do
		local mode=GP.sample(a,s)
		if mode=="hidden" then continue end
		-- keep the episode in progress (the run of segments without a gap around s)
		local idx: number?=nil
		for j,sg in a.segs do if sg.t0<=s and s<sg.t1 then idx=j;break end end
		if not idx then continue end
		local i0,i1=idx :: number,idx :: number
		while i0>1 and a.segs[i0].t0<=a.segs[i0-1].t1+1e-6 do i0-=1 end
		while i1<#a.segs and a.segs[i1+1].t0<=a.segs[i1].t1+1e-6 do i1+=1 end
		local segs: {Seg}={}
		for j=i0,i1 do table.insert(segs,a.segs[j]) end
		table.insert(out,{id=a.id,seed=a.seed,segs=segs,role=a.role})
		local e=endPoint(segs[#segs])
		if (e-door).Magnitude<0.5 then leaveAt=segs[#segs].t1+12;seed=a.seed
		elseif (e-wsDoor).Magnitude<0.5 then leaveAt=segs[#segs].t1+6;seed=a.seed;fromWorkshop=true end
	end
	if #out==0 then
		-- hidden now: in the room (overnight or between outings) or out of the house - by the latest finished walk
		local latest: Seg?=nil
		local latestSeed=seed
		local overnight: number?=nil
		for _,a in base do
			for _,sg in a.segs do
				if sg.t1<=s and (not latest or sg.t1>(latest :: Seg).t1) then latest=sg;latestSeed=a.seed end
			end
			if a.role~="arrive" and #a.segs>0 and a.segs[1].t0>s then overnight=a.seed end
		end
		if latest then
			local e=endPoint(latest)
			if (e-door).Magnitude<0.5 then leaveAt=s+8;seed=latestSeed
			elseif (e-wsDoor).Magnitude<0.5 then leaveAt=s+4;seed=latestSeed;fromWorkshop=true end
		elseif overnight then
			leaveAt=s+8;seed=overnight
		end
	end
	if leaveAt then
		local b=builder(H,leaveAt :: number,if fromWorkshop then WORKSHOP else room)
		if fromWorkshop then
			-- out of the workshop, to the room for the suitcase
			walk(b,room,GP.GUEST_SPEED,"bag")
			hide(b,b.t+10,room)
		end
		walk(b,DESKS[(g%2)+1],GP.GUEST_SPEED,"suitcase")
		stay(b,b.t+8+u("leave:"..plotSeed..":"..g..":"..d)*5,"checkout","suitcase")
		walk(b,STREET,GP.GUEST_SPEED,"suitcase")
		table.insert(out,{id="g"..g..":leave"..d..":"..math.floor(s),seed=seed,segs=b.segs,role="leave"})
	end
	return out
end

------------------------------------------------------------------------------------------------ City Airport
local A=CityPlan.AIRPORT
local AW=A.walk
local F=CityPlan.GROUND+.5
local HG=newGraph()
GP.HOME_GRAPH=HG
do
	for _,nd in AW.nodes do node(HG,nd.name,Vector3.new(nd.p.X,F,nd.p.Z)) end
	for _,e in AW.edges do link(HG,AW.nodes[e.a].name,AW.nodes[e.b].name) end
	-- gate A1 seat aisles east of the gate desk (desk x -206.3..-197.3, seat pads from x -194.1): between the two
	-- seat rows (pads z ..2513.9 / 2517.1..) and behind the second row (pads ..2521.9)
	local g1=(A.gates[A.shuttleStand] or A.gates[1]).Position
	node(HG,"A1aisle0",v(g1.X+4,F,2515.5));node(HG,"A1rear0",v(g1.X+4,F,2525.5))
	link(HG,"A"..A.shuttleStand,"A1aisle0");link(HG,"A1aisle0","A1rear0")
end
local DESK_NAMES: {[number]: {string}}={}
for name in HG.p do
	local i=string.match(name,"^Q(%d)desk%d+$")
	if i then
		local k=tonumber(i) :: number
		DESK_NAMES[k]=DESK_NAMES[k] or {}
		table.insert(DESK_NAMES[k],name)
	end
end
for _,l in DESK_NAMES do table.sort(l) end
-- gate A1 seats for passengers: east of the boarding lane, the sides facing the windows / the aisle (the first
-- row facing the concourse belongs to CityLifeController's seat spurs)
GP.HOME_SEATS={} :: {Place}
do
	local g1=(A.gates[A.shuttleStand] or A.gates[1]).Position
	for _,s in A.seats do
		if s.gate=="A"..A.shuttleStand and s.p.X>g1.X and not (s.face.Z<0 and s.p.Z<2511) then
			local feet=v(s.p.X,F,s.p.Z)
			local ap=feet+s.face*1.9
			local hub=if ap.Z<2520 then "A1aisle0" else "A1rear0"
			local aisleZ=if ap.Z<2520 then 2515.5 else 2525.5
			table.insert(GP.HOME_SEATS,{hub=hub,tail={v(ap.X,F,aisleZ),v(ap.X,F,ap.Z),feet},face=s.face,sit=true})
		end
	end
	table.sort(GP.HOME_SEATS,function(a: Place,b: Place)
		local pa,pb=a.tail[3],b.tail[3]
		if math.abs(pa.Z-pb.Z)>0.1 then return pa.Z<pb.Z end
		return pa.X<pb.X
	end)
end
local function hp(name: string,face: Vector3?): Place return {hub=name,tail={},face=face} end
-- Passengers of the out leg of cycle k (absolute server times).
function GP.homeDepartures(k: number): {Actor}
	local leg=FP.leg("out")
	local B0=FP.legStart("out",k)+leg.phases.boarding.t0
	local B1=FP.legStart("out",k)+leg.phases.boarding.t1
	local seats=perm(#GP.HOME_SEATS,"homeSeats:"..k)
	local out: {Actor}={}
	for i=1,GP.HOME_DEPARTURES do
		local key="hd:"..k..":"..i
		-- gate A1 is at the west end: most use the west islands, the nearest door and security lane
		local r=hash(key..":q")%10
		local q=if r<4 then 1 elseif r<8 then 2 else 3
		local lane=if q==1 then 1 elseif q==2 then 1+hash(key..":s")%2 else 2+hash(key..":s")%2
		local deskList=DESK_NAMES[q] or {"Q"..q.."g"}
		local desk=deskList[1+hash(key..":d")%#deskList]
		local door=if q==3 then "door2" elseif q==2 and hash(key..":door")%2==0 then "door2" else "door1"
		local b=builder(HG,B0-330+(i-1)*14+u(key..":t")*6,hp(door))
		walk(b,hp("Q"..q.."c"),GP.PAX_SPEED,"suitcase")
		-- the last two lanes of the serpentine at queue speed, the desk
		local serp: {Vector3}={}
		for _,c in {"c","d","e","f","g"} do table.insert(serp,HG.p["Q"..q..c]) end
		walkPath(b,serp,hp("Q"..q.."g",S),GP.QUEUE_SPEED,"suitcase")
		walk(b,hp(desk,S),GP.PAX_SPEED,"suitcase")
		stay(b,b.t+9+u(key..":desk")*5,"checkin","suitcase")
		-- security: divest, arch, recompose (the suitcase is checked in: a cabin bag from here on)
		walk(b,hp("S"..lane.."divest",E),GP.PAX_SPEED,"bag")
		stay(b,b.t+5,"divest","bag")
		walk(b,hp("S"..lane.."recompose",E),GP.PAX_SPEED,"bag")
		stay(b,b.t+4,"recompose","bag")
		-- to a seat at gate A1, sit until the boarding call, board through the jet bridge
		local seat=GP.HOME_SEATS[seats[i] or 1]
		local call=B0+4+(i-1)*3.6
		sitUntil(b,seat,call,GP.PAX_SPEED,"wait","bag")
		walk(b,hp("A"..A.shuttleStand.."lane"),GP.PAX_SPEED,"bag")
		walk(b,hp("A"..A.shuttleStand.."board",S),GP.PAX_SPEED,"bag")
		-- never after the doors close: a late passenger is simply gone (boarded) at B1
		local segs=b.segs
		for j=#segs,1,-1 do if segs[j].t0>=B1 then table.remove(segs,j) elseif segs[j].t1>B1 then segs[j].t1=B1 end end
		table.insert(out,{id=key,seed=hash(key),segs=segs,role="depart"})
	end
	return out
end
-- Passengers of the back leg of cycle k arriving at City Airport: arrival point -> carousel -> trolley -> exit.
function GP.homeArrivals(k: number): {Actor}
	local leg=FP.leg("back")
	local D0=FP.legStart("back",k)+leg.phases.deboarding.t0
	local out: {Actor}={}
	for i=1,GP.HOME_ARRIVALS do
		local key="ha:"..k..":"..i
		local b=builder(HG,D0+6+(i-1)*3.2+u(key..":t")*2,hp("arrival"))
		local carousel=if hash(key..":c")%2==0 then hp("reclaimW",E) else hp("reclaimN",S)
		walk(b,carousel,GP.PAX_SPEED,"bag")
		stay(b,b.t+8+u(key..":w")*14,"wait","bag")
		walk(b,hp("doorArr"),GP.PAX_SPEED*0.85,"trolley")
		table.insert(out,{id=key,seed=hash(key),segs=b.segs,role="arrive"})
	end
	return out
end

------------------------------------------------------------------------------------------------ Port Meridian
local B=CityPlan.ABROAD
local PF=CityPlan.GROUND+.5 -- hall floor
local AY=if okMetro and typeof(MetroPlan)=="table" and typeof(MetroPlan.APRON)=="table" and typeof(MetroPlan.APRON.top)=="number" then MetroPlan.APRON.top else CityPlan.GROUND+.25
local PG=newGraph()
GP.PM_GRAPH=PG
-- the shuttle's airstair at the Port Meridian stand (the same geometry ShuttleController builds): foot / top
function GP.pmStairs(): (Vector3,Vector3)
	local pts=Aircraft.points(FP.CONFIG.kind,FP.CONFIG.scale)
	local door=FP.PM_STAND*pts.doorL1
	local sill=door.Position.Y-pts.doorHalf
	local outV=door.LookVector
	local h=sill-CityPlan.ROAD_TOP
	local top=Vector3.new(door.Position.X,sill,door.Position.Z)+outV*0.9
	local bottom=top+outV*(h*1.25)-Vector3.new(0,h,0)
	return bottom,top
end
do
	local function n(name: string,x: number,y: number,z: number) node(PG,name,v(x,y,z)) end
	local foot,top=GP.pmStairs()
	local dz=FP.PM_DOOR and FP.PM_DOOR.Z or 7661
	local dx=FP.PM_DOOR and FP.PM_DOOR.X or B.terminal.x2
	-- two lanes on the apron walkway: arrivals (south, +2.6) and departures (north, -2.6)
	for li,l in {"a","d"} do
		local o=if li==1 then 2.6 else -2.6
		n(l.."top",top.X,top.Y,top.Z);n(l.."foot",foot.X+o*0.4,AY,foot.Z+1.5)
		n(l.."walk",dx+34,AY,dz+o+14);n(l.."apron",dx+6,AY,dz+o);n(l.."door",dx-1,PF,dz+o);n(l.."hall",dx-12,PF,dz+o)
		chain(PG,{l.."top",l.."foot",l.."walk",l.."apron",l.."door",l.."hall"})
	end
	-- the hall's corridor between the baggage carousel (x 110..154, z 7642..7654) and the news kiosk / columns (z 7661)
	for _,x in {140,100,80,40,0,-40,-80} do n("hx"..x,x,PF,7661) end
	chain(PG,{"hx140","hx100","hx80","hx40","hx0","hx-40","hx-80"})
	link(PG,"ahall","hx140");link(PG,"dhall","hx140")
	-- baggage claim: the carousel's south side
	n("claimE",142,PF,7657.5);n("claimW",122,PF,7657.5)
	link(PG,"ahall","claimE");link(PG,"claimE","claimW");link(PG,"claimW","hx100")
	-- exits / entrances (south facade z 7690, openings x -80 / 0 / 80) and the plaza beyond
	for _,x in {-80,0,80} do
		n("in"..x,x,PF,7684);n("out"..x,x,PF,7697);n("plaza"..x,x,PF,7708)
		chain(PG,{"hx"..x,"in"..x,"out"..x,"plaza"..x})
	end
	-- check-in (counters x 58..82 / -82..-58, z 7634..7638; customers on the hall side) and the benches (rows
	-- z 7617..7619.6 / 7624..7626.6, blocks x 6..40 / -40..-6, a gap in the middle)
	n("ck-70",-70,PF,7640.6);n("ck70",70,PF,7640.6)
	link(PG,"ck-70","hx-80");link(PG,"ck-70","hx-40");link(PG,"ck70","hx80");link(PG,"ck70","hx40")
	n("benchW",-23,PF,7632);n("benchGap",0,PF,7632);n("benchE",23,PF,7632);n("row1",0,PF,7621.6)
	chain(PG,{"benchW","benchGap","benchE"});link(PG,"benchGap","row1");link(PG,"benchGap","hx0");link(PG,"benchE","hx40");link(PG,"benchW","hx-40")
	-- the gate call line inside the apron door (departure lane)
	n("dqueue",dx-24,PF,dz-2.6);link(PG,"dqueue","dhall");link(PG,"dqueue","hx100")
end
GP.PM_SEATS={} :: {Place}
for row=1,2 do
	local seatZ=if row==1 then 7618.6 else 7625.6
	local apZ=if row==1 then 7621.6 else 7628.6
	for _,side in {{-40,-6},{6,40}} do
		local nSeats=math.floor((side[2]-side[1])/2.6)
		local w=(side[2]-side[1])/nSeats
		for i=0,nSeats-1 do
			local x=side[1]+(i+.5)*w
			if row==1 then
				table.insert(GP.PM_SEATS,{hub="row1",tail={v(x,PF,apZ),v(x,PF,seatZ)},face=S,sit=true})
			else
				table.insert(GP.PM_SEATS,{hub=if x<0 then "benchW" else "benchE",tail={v(x,PF,7632),v(x,PF,apZ),v(x,PF,seatZ)},face=S,sit=true})
			end
		end
	end
end
local function pp(name: string,face: Vector3?): Place return {hub=name,tail={},face=face} end
-- Port Meridian arrivals of the out leg of cycle k: airstair -> apron door -> baggage claim -> trolley -> exit.
function GP.pmArrivals(k: number): {Actor}
	local leg=FP.leg("out")
	local D0=FP.legStart("out",k)+leg.phases.deboarding.t0
	local out: {Actor}={}
	for i=1,GP.PM_ARRIVALS do
		local key="pa:"..k..":"..i
		local b=builder(PG,D0+4+(i-1)*2.6,pp("atop"))
		local claim=if hash(key..":c")%2==0 then pp("claimE",S) else pp("claimW",S)
		walk(b,claim,GP.PAX_SPEED,"bag")
		local spot=finalPos(PG,b.at)+Vector3.new((u(key..":x")-0.5)*14,0,0)
		local here: Place={hub=claim.hub,tail={spot},face=N}
		walkPath(b,{finalPos(PG,claim),spot},here,GP.PAX_SPEED)
		stay(b,b.t+6+u(key..":w")*12,"wait","bag")
		local exitX=({-80,0,80})[1+hash(key..":e")%3]
		walk(b,pp("plaza"..exitX),GP.PAX_SPEED*0.85,"trolley")
		table.insert(out,{id=key,seed=hash(key),segs=b.segs,role="arrive"})
	end
	return out
end
-- Port Meridian departures of the back leg of cycle k: entrance -> check-in -> benches -> gate call line ->
-- apron door -> airstair (gone at the top before the doors close).
function GP.pmDepartures(k: number): {Actor}
	local leg=FP.leg("back")
	local B0=FP.legStart("back",k)+leg.phases.boarding.t0
	local B1=FP.legStart("back",k)+leg.phases.boarding.t1
	local seats=perm(#GP.PM_SEATS,"pmSeats:"..k)
	local out: {Actor}={}
	for i=1,GP.PM_DEPARTURES do
		local key="pd:"..k..":"..i
		local entX=({-80,0,80})[1+hash(key..":e")%3]
		local b=builder(PG,B0-170+(i-1)*9+u(key..":t")*5,pp("plaza"..entX))
		local ck=if hash(key..":ck")%2==0 then "ck-70" else "ck70"
		walk(b,pp(ck,N),GP.PAX_SPEED,"suitcase")
		stay(b,b.t+8+u(key..":ckd")*5,"checkin","suitcase")
		local seat=GP.PM_SEATS[seats[i] or 1]
		sitUntil(b,seat,B0-32+(i-1)*1.2,GP.PAX_SPEED,"wait","bag")
		local qspot=PG.p.dqueue+Vector3.new(10-(i-1)*2.4,0,0)
		walk(b,pp("dqueue"),GP.PAX_SPEED,"bag")
		walkPath(b,{PG.p.dqueue,qspot},{hub="dqueue",tail={qspot},face=E},GP.PAX_SPEED,"bag")
		stay(b,B0+1+(i-1)*1.5,"wait","bag")
		local path: {Vector3}={qspot}
		for _,nm in {"dhall","ddoor","dapron","dwalk","dfoot","dtop"} do table.insert(path,PG.p[nm]) end
		walkPath(b,path,pp("dtop"),GP.PAX_SPEED*1.2,"bag")
		local segs=b.segs
		for j=#segs,1,-1 do if segs[j].t0>=B1 then table.remove(segs,j) elseif segs[j].t1>B1 then segs[j].t1=B1 end end
		table.insert(out,{id=key,seed=hash(key),segs=segs,role="depart"})
	end
	return out
end
-- Terminal regions (camera inside -> the controller runs the passengers): x / z boxes and the roof line.
type Region={x1: number,x2: number,z1: number,z2: number,y2: number}
GP.TERMINALS={
	home={x1=A.terminal.x1-10,x2=A.terminal.x2+10,z1=A.terminal.z1-26,z2=A.terminal.z2+30,y2=CityPlan.GROUND+A.height+8},
	pm={x1=B.terminal.x1-10,x2=B.terminal.x2+110,z1=B.terminal.z1-10,z2=B.terminal.z2+30,y2=CityPlan.GROUND+B.height+30},
} :: {[string]: Region}
function GP.terminalAt(p: Vector3): string?
	for id,r in GP.TERMINALS do
		if p.X>=r.x1 and p.X<=r.x2 and p.Z>=r.z1 and p.Z<=r.z2 and p.Y<=r.y2 then return id end
	end
	return nil
end
-- memoised per cycle (the lists are pure functions of the cycle; a few cycles are kept)
local cycleCache: {[string]: {Actor}}={}
local cycleKeys: {string}={}
local function cycleList(kind: string,k: number,make: (number) -> {Actor}): {Actor}
	local key=kind..k
	local c=cycleCache[key]
	if c then return c end
	local l=make(k)
	cycleCache[key]=l
	table.insert(cycleKeys,key)
	if #cycleKeys>24 then cycleCache[table.remove(cycleKeys,1) :: string]=nil end
	return l
end
-- Actors of a terminal around server time t (the cycles whose people can be visible then).
function GP.terminalActors(id: string,t: number): {Actor}
	local I=FP.interval()
	local k=math.floor((t-FP.CONFIG.epoch)/I)
	local out: {Actor}={}
	for kk=k-1,k+1 do
		local lists: {{Actor}}=if id=="home" then {cycleList("hd",kk,GP.homeDepartures),cycleList("ha",kk,GP.homeArrivals)}
			else {cycleList("pa",kk,GP.pmArrivals),cycleList("pd",kk,GP.pmDepartures)}
		for _,l in lists do
			for _,a in l do
				local t0,t1=GP.span(a)
				if t>=t0-1 and t<=t1+1 then table.insert(out,a) end
			end
		end
	end
	return out
end

------------------------------------------------------------------------------------------------ tests
-- Every walk the people can take (terminal: world coordinates; hotel: building-local, prefix "hotel:") for the
-- clearance tests (tests/guests_jet).
export type TestWalk={name: string,radius: number,path: {Vector3},trimStart: number?,trimEnd: number?}
function GP.walksForTests(): {TestWalk}
	local out: {TestWalk}={}
	local function add(prefix: string,actors: {Actor})
		for _,a in actors do
			for j,s in a.segs do
				if s.kind=="walk" and s.path then
					-- the last metres into / out of a seat cross the seat itself
					local prev,nxt=a.segs[j-1],a.segs[j+1]
					table.insert(out,{name=prefix..a.id..":"..j,radius=0.7,path=s.path,trimStart=if prev and prev.kind=="sit" then 3.4 else 0,
						trimEnd=if nxt and nxt.kind=="sit" then 3.4 else 0})
				end
			end
		end
	end
	for k=10,11 do add("home:",GP.homeDepartures(k));add("home:",GP.homeArrivals(k));add("pm:",GP.pmArrivals(k));add("pm:",GP.pmDepartures(k)) end
	return out
end
function GP.hotelWalksForTests(): {TestWalk}
	local out: {TestWalk}={}
	local seen: {[string]: boolean}={}
	for d=100,104 do
		for g=1,GP.HOTEL_CAP do
			for _,a in GP.slotDay(7,g,d) do
				for j,s in a.segs do
					if s.kind=="walk" and s.path then
						local path=s.path :: {Vector3}
						local key=tostring(path[1])..tostring(path[#path])
						local prev,nxt=a.segs[j-1],a.segs[j+1]
						if not seen[key] then seen[key]=true;table.insert(out,{name="hotel:"..a.id..":"..d..":"..j,radius=0.7,path=path,
							trimStart=if prev and prev.kind=="sit" then 3.4 else 0,trimEnd=if nxt and nxt.kind=="sit" then 3.4 else 0}) end
					end
				end
			end
		end
	end
	-- every seat, room and desk reachable from the street
	for i in GP.HOTEL_ROOMS do table.insert(out,{name="hotel:room"..i,radius=0.7,path=route(H,STREET,roomPlace(i))}) end
	for i,s in GP.BREAKFAST_SEATS do table.insert(out,{name="hotel:bf"..i,radius=0.7,path=route(H,roomPlace(1),s),trimEnd=3.4}) end
	for i,s in GP.LOUNGE_SEATS do table.insert(out,{name="hotel:lounge"..i,radius=0.7,path=route(H,roomPlace(12),s),trimEnd=3.4}) end
	for i,s in GP.COFFEE do table.insert(out,{name="hotel:coffee"..i,radius=0.7,path=route(H,roomPlace(5),s)}) end
	for i,s in DESKS do table.insert(out,{name="hotel:desk"..i,radius=0.7,path=route(H,STREET,s)}) end
	table.insert(out,{name="hotel:workshop",radius=0.7,path=route(H,STREET,WORKSHOP)})
	for i in GP.HOTEL_ROOMS do table.insert(out,{name="hotel:workshop"..i,radius=0.7,path=route(H,roomPlace(i),WORKSHOP)}) end
	return out
end
GP.STREET=STREET
GP.DESKS=DESKS
GP.roomPlace=roomPlace
return GP
