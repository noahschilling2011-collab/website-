--!strict
-- CityService: the shared world beyond the campus district and travel through it.
--   * init: CityBuilder builds Business City, the airport and Port Meridian ONCE per server (a failed build
--     is logged and never stops the server); binds TravelAction; meeting prompts (placeholder until the
--     customers package registers a handler); travel state reset on respawn; PlotService away check.
--   * Flights - TravelAction {action="flight", to="abroad"|"home"} at a check-in counter:
--     the ticket is paid at the home check-in (return flight included, price CityPlan.TRAVEL.ticket); the
--     server holds the character (root anchored), asks Roblox to stream the arrival hall to the player
--     (Player:RequestStreamAroundAsync), pivots the character there and answers {seconds}. The client
--     plays its fade + plane cutscene meanwhile; tick() releases the character after `seconds`.
--     States: home -> flying -> abroad -> flying -> home. A respawn or leaving resets to home.
--   * Shuttle (ShuttleService, package "flight"): the scheduled Port Meridian shuttle replaces the cutscene in
--     normal play - TravelAction {action="ticket", to} at a check-in counter (spend once), {action="board"} at
--     the gate during boarding (or automatically at the end of boarding), the ride shown by the client on the
--     client-animated aircraft, server PivotTo at arrival; {action="heli", to="hotel"|"airport"} = VIP
--     helicopter in Port Meridian. Riders are trips with state "flying" (kind "shuttle"/"heli"), so isAway,
--     respawn reset and leaving work the same; ShuttleService.drop refunds an unfinished ride. The instant
--     flight above stays (fallback when the shuttle is off, ShuttleService.setEnabled(false)).
--   * GPS - TravelAction {action="route", to=destinationId|"home"} returns the CityPlan road route from the
--     character to the destination (points + length); City.guide(player, id) asks the client to fetch and
--     draw one (Notify TRAVEL_GUIDE) - for appointments later.
-- Server writes: the Player attribute "TravelState" on each change (nil = home), nothing per frame.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Prompts=game:GetService("ProximityPromptService")
local CityPlan=require(ReplicatedStorage.Shared.Config.CityPlan)
local Format=require(ReplicatedStorage.Shared.Format)
local Remote=require(script.Parent.Parent.Lib.Remote)
local Session=require(script.Parent.SessionService)
local Economy=require(script.Parent.EconomyService)
local Plot=require(script.Parent.PlotService)
local Builder=require(script.Parent.CityBuilder)
local Shuttle=require(script.Parent.ShuttleService)
local City={}
-- kind: nil = instant flight / abroad, "shuttle" / "heli" = ShuttleService rides (releaseAt = math.huge: their
-- end is handled by ShuttleService.tick)
type Trip={player: Player,state: string,to: string,character: Model?,root: BasePart?,wasAnchored: boolean,releaseAt: number,kind: string?}
local trips: {[number]: Trip}={}
local clock=0
local meetingHandler: ((Player,string,ProximityPrompt)->())?=nil
local promptAt: {[Player]: number}={}
City.trips=trips

local function setState(player: Player,state: string)
	player:SetAttribute("TravelState",if state=="home" then nil else state)
end
-- "home", "flying" or "abroad"
function City.state(player: Player): string
	local t=trips[player.UserId]
	return if t then t.state else "home"
end
function City.isAway(player: Player): boolean return City.state(player)~="home" end
function City.ticketText(): string
	return "Port Meridian · "..Format.money(CityPlan.TRAVEL.ticket).." return"
end
local function rootOf(player: Player): (Model?,BasePart?,Humanoid?)
	local character=player.Character
	local root=if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid=if character then character:FindFirstChildOfClass("Humanoid") else nil
	if character and root and root:IsA("BasePart") then return character,root,humanoid end
	return nil,nil,nil
end
local function near(p: Vector3,points: {Vector3},radius: number): boolean
	for _,q in points do if CityPlan.flat(p,q)<=radius and math.abs(p.Y-q.Y)<12 then return true end end
	return false
end
local function reset(player: Player)
	Shuttle.drop(player,"respawn") -- an unfinished shuttle / helicopter ride is refunded
	trips[player.UserId]=nil;setState(player,"home")
end

------------------------------------------------------------------------------------------------ flights
function City.flight(s: any,destination: any): {[string]: any}
	local player: Player=s.player
	if destination~="abroad" and destination~="home" then return {ok=false,err="BAD_INPUT"} end
	local to: string=destination
	local state=City.state(player)
	if state=="flying" then return {ok=false,err="BUSY"} end
	local from: {[string]: string}={abroad="home",home="abroad"} -- where a flight to `to` must start
	if state~=from[to] then return {ok=false,err=if to=="abroad" then "ALREADY_ABROAD" else "NOT_ABROAD"} end
	local character,root,humanoid=rootOf(player)
	if not character or not root or not humanoid or humanoid.Health<=0 then return {ok=false,err="LOADING"} end
	if humanoid.SeatPart then return {ok=false,err="LEAVE_VEHICLE"} end
	local counters=if to=="abroad" then CityPlan.AIRPORT.checkin else CityPlan.ABROAD.checkin
	if not near(root.Position,counters,CityPlan.TRAVEL.checkinRadius) then return {ok=false,err="NOT_AT_CHECKIN"} end
	local price=if to=="abroad" then CityPlan.TRAVEL.ticket else 0
	local held=Shuttle.takeTicket(player,to) -- a shuttle ticket already bought for this trip is used instead
	if held then price=0 end
	if not Economy.spend(s,price,"travel") then return {ok=false,err="NO_MONEY"} end -- P&L line "travel"
	local arrival=if to=="abroad" then CityPlan.ABROAD.arrival else CityPlan.AIRPORT.arrival
	local trip: Trip={player=player,state="flying",to=to,character=character,root=root,wasAnchored=root.Anchored,releaseAt=math.huge}
	trips[player.UserId]=trip;setState(player,"flying")
	root.Anchored=true -- held until tick() releases it: nothing falls before the arrival hall has streamed in
	-- With StreamingEnabled the client only has parts near the character: stream the arrival area first.
	local ok,err=pcall(function() player:RequestStreamAroundAsync(arrival.Position,CityPlan.TRAVEL.streamTimeout) end)
	if not ok then warn("[City] RequestStreamAroundAsync failed for "..player.Name..": "..tostring(err)) end
	if trips[player.UserId]~=trip or player.Character~=character or not root.Parent then
		-- left, respawned or reset while the stream request yielded: no flight, the ticket is refunded
		if trips[player.UserId]==trip then reset(player) end
		if root.Parent then root.Anchored=trip.wasAnchored end
		if price>0 then Economy.grant(s,price,"travel");s.data.stats.totalCost=math.max(0,s.data.stats.totalCost-price) end
		if held then Shuttle.restoreTicket(player,held) end
		return {ok=false,err="CANCELLED"}
	end
	character:PivotTo(arrival)
	trip.releaseAt=clock+CityPlan.TRAVEL.flightSeconds
	Session.markDirty(s,true)
	return {ok=true,to=to,seconds=CityPlan.TRAVEL.flightSeconds,price=price,destination=if to=="abroad" then "Port Meridian" else "City Airport"}
end

------------------------------------------------------------------------------------------------ routes
function City.route(s: any,to: any): {[string]: any}
	if typeof(to)~="string" or #to>40 then return {ok=false,err="BAD_INPUT"} end
	local _,root=rootOf(s.player)
	if not root then return {ok=false,err="LOADING"} end
	local target: Vector3;local name: string
	if to=="home" then
		local p=Plot.get(s.player)
		if not p or typeof(p.index)~="number" then return {ok=false,err="LOADING"} end
		local info=CityPlan.plots()[p.index];if not info then return {ok=false,err="LOADING"} end
		target=info.gate;name=if s.data.company then s.data.company.name.." HQ" else "Your HQ"
	else
		local d=CityPlan.destination(to);if not d then return {ok=false,err="BAD_INPUT"} end
		target=d.drive or d.door.Position;name=d.name
	end
	local r,err=CityPlan.route(root.Position,target)
	if not r then return {ok=false,err=err or "NO_ROUTE"} end
	return {ok=true,to=to,name=name,points=r.points,length=math.floor(r.length+.5)}
end
-- Ask the player's client to fetch and draw a GPS route (appointments, assistant hints ...).
function City.guide(player: Player,destinationId: string)
	Remote.fire(player,"Notify","TRAVEL_GUIDE",{to=destinationId})
end
-- The customers package registers the real meeting here: fn(player, clientId, prompt).
function City.setMeetingHandler(fn: (Player,string,ProximityPrompt)->())
	meetingHandler=fn
end

------------------------------------------------------------------------------------------------ lifecycle
local function onPrompt(q: ProximityPrompt,player: Player)
	if q:GetAttribute("CityAction")~="meeting" then return end
	local part=q.Parent;local _,root=rootOf(player)
	if not part or not part:IsA("BasePart") or not root or (root.Position-part.Position).Magnitude>16 then return end
	local now=workspace:GetServerTimeNow()
	if (promptAt[player] or 0)>now then return end;promptAt[player]=now+1
	local clientId=q:GetAttribute("ClientId")
	if typeof(clientId)~="string" then return end
	local handler=meetingHandler
	if handler then handler(player,clientId,q);return end
	local d=CityPlan.clientOffice(clientId)
	Remote.fire(player,"Notify","CAMPUS_NOTICE",{text="No meeting with "..(if d then d.name else clientId).." is scheduled yet."})
end
function City.tick(dt: number)
	clock+=dt
	Shuttle.tick(dt)
	for userId,t in trips do
		if t.state=="flying" and clock>=t.releaseAt then
			local root=t.root
			if root and root.Parent then root.Anchored=t.wasAnchored end
			if t.to=="abroad" then t.state="abroad";setState(t.player,"abroad")
			else trips[userId]=nil;setState(t.player,"home") end
		end
	end
end
function City.init()
	local ok,err=pcall(function() Builder.build(City.ticketText()) end)
	if not ok then warn("[City] building the shared world failed: "..tostring(err)) end
	local okShuttle,errShuttle=pcall(function() Shuttle.init({trips=trips,setState=setState,rootOf=rootOf}) end)
	if not okShuttle then warn("[City] starting the shuttle failed: "..tostring(errShuttle)) end
	Remote.bind("TravelAction",{burst=4,perSecond=.6},function(s,p)
		local action=p.action
		if action=="flight" then return City.flight(s,p.to) end
		if action=="route" then return City.route(s,p.to) end
		if action=="ticket" then return Shuttle.ticket(s,p.to) end
		if action=="board" then return Shuttle.board(s) end
		if action=="heli" then return Shuttle.heli(s,p.to) end
		if action=="status" then
			local res: {[string]: any}={ok=true,state=City.state(s.player),ticket=CityPlan.TRAVEL.ticket,seconds=CityPlan.TRAVEL.flightSeconds}
			local okStatus,info=pcall(Shuttle.status,s.player)
			if okStatus then for k,v in info do res[k]=v end end
			return res
		end
		return {ok=false,err="BAD_INPUT"}
	end)
	Prompts.PromptTriggered:Connect(onPrompt)
	Session.onLoaded(function(s)
		reset(s.player)
		-- a new character always starts at home (PlotService sends it to the plaza 0.25 s later)
		s.player.CharacterAdded:Connect(function() reset(s.player) end)
	end)
	Session.onClosing(function(s) Shuttle.drop(s.player,"leave");trips[s.userId]=nil;promptAt[s.player]=nil end)
	Plot.setAwayCheck(City.isAway)
end
return City
