--!strict
-- Card authority, door access rules, facility prompts (doors, lift, fixtures, founder terminals),
-- shop economy and real consumable snack tools.
--
-- Security model: doors are the primary barrier (DoorService asks authorizeDoor below for every
-- entry from the non-secure side; leaving is always possible). The access guard in Facility.tick is
-- only the fallback for what a door cannot stop — tailgating through a speed gate or behind the
-- founder, glitching through geometry, a guest card expiring while its holder is inside. It
-- relocates players, it never traps. Public rooms (reception hall, visitor lounge, showroom, café)
-- are open to visitors without a card (BuildingPlan.playerAllows).
--
-- Props and fixtures never move on the server: every prompt writes one state attribute (FxUntil /
-- FxState, design/PROPFX_CONTRACT.md) and the client animates (water, flush, steam, belts, flywheels,
-- printers, lockers, chargers, robot arms ...). Generic player prop action: CampusAction "prop".
local Collection=game:GetService("CollectionService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Prompts=game:GetService("ProximityPromptService")
local Config=require(ReplicatedStorage.Shared.Config.CampusConfig)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Layout=require(ReplicatedStorage.Shared.BuildingLayout)
local Remote=require(script.Parent.Parent.Lib.Remote)
local Session=require(script.Parent.SessionService)
local Economy=require(script.Parent.EconomyService)
local Plot=require(script.Parent.PlotService)
local Lift=require(script.Parent.LiftService)
local Doors=require(script.Parent.DoorService)
local Sound=require(script.Parent.CampusSoundService)
local Facility={}
local cards: {[Instance]:any}={}
local snackTools: {[Instance]:any}={}
local guests: {[number]:{[number]:number}}={}
local connections: {[Player]:RBXScriptConnection}={}
local guardClock=0
local routines: {[Player]:any}={}
local propCooldown: {[Instance]:number}=setmetatable({},{__mode="k"}) :: any
local FX_TAG="PropFx"
local promptTimes: {[Player]:number}={}
local routineCooldown: {[Player]:number}={}
local speedApplied: {[Player]:{humanoid:Humanoid,value:number}}={}
local toiletSeats: {[Seat]:number}={} -- seats enabled for a player; re-disabled once empty
local CARD_TEXT="Access denied. You need a valid card for this company."
local BADGE_TEXT="Badge required — ask for a guest card at reception."
local VISITOR_TEXT="This area needs a company or guest card. Visitors are welcome in the reception hall, showroom and café."
local DENY: {[string]:string}={
	founder="Founder-only room. Your employee or guest pass does not open it.",
	research="Research clearance required. Guest cards stop at the lab door.",
	compute="Compute clearance required. The compute room is closed to guests.",
	technical="Technical staff only. This service area is closed to guests.",
	guest="Hotel rooms are for guests.",
}
-- Hidden doors answer non-founders neutrally so they do not give themselves away.
local HIDDEN_DENY: {[string]:string}={
	bookcase="Just a bookcase full of old binders.",
	flush="Just a timber wall panel.",
	vault="Model vault · founder biometrics required.",
}
-- LiftService answers with codes; the landing button shows them as short notices.
local LIFT_TEXT: {[string]:string}={
	CARD_REQUIRED="The lift needs a company or guest card.",
	LIFT_OUT_OF_SERVICE="The lift is out of service right now.",
	LIFT_FLOOR_LOCKED="That floor is not on your card.",
}
local FOUNDER_ACTIONS: {[string]:string}={
	security="Camera control belongs to the campus founder.",
	ownerComputer="This terminal belongs to the founder.",
	report="Company reports are printed for the founder only.",
	modelSafe="The model safe opens for the founder only.",
	fleet="The fleet desk is managed by the founder.",
}
local function notify(player: Player,text: string,kind: string?)
	Remote.fire(player,"Notify",kind or "CAMPUS_NOTICE",{text=text})
end
local function backpack(player: Player): Instance?
	return player:FindFirstChildOfClass("Backpack")
end
local function carried(player: Player,tool: Instance): boolean
	return tool.Parent~=nil and (tool.Parent==backpack(player) or tool.Parent==player.Character)
end
function Facility.hasCard(player: Player,owner: number,executive: boolean?): boolean
	for tool,record in cards do
		if record.holder==player and record.owner==owner and carried(player,tool) and (record.expires==0 or record.expires>os.time()) then
			if not executive or player.UserId==owner then return true end
		end
	end
	return false
end
function Facility.issueCard(player: Player,owner: number,expires: number?): boolean
	local bag=backpack(player);if not bag then return false end
	for tool,record in cards do if record.holder==player and record.owner==owner then tool:Destroy();cards[tool]=nil end end
	local tool=Instance.new("Tool");tool.Name=if owner==player.UserId then "Employee Card" else "Guest Card";tool.CanBeDropped=false;tool.ToolTip="Scan at the door reader. Carry in your backpack or hand."
	local handle=Instance.new("Part");handle.Name="Handle";handle.Size=Vector3.new(1.6,.12,1);handle.Color=Color3.fromRGB(225,222,205);handle.CanCollide=false;handle.Massless=true;handle.Parent=tool
	local stripe=Instance.new("Part");stripe.Name="CardStripe";stripe.Size=Vector3.new(1.6,.02,.24);stripe.CFrame=handle.CFrame*CFrame.new(0,.08,.25);stripe.Color=Color3.fromRGB(82,110,85);stripe.CanCollide=false;stripe.Massless=true;stripe.Parent=tool
	local weld=Instance.new("WeldConstraint");weld.Part0=handle;weld.Part1=stripe;weld.Parent=handle
	tool:SetAttribute("CardOwner",owner);tool:SetAttribute("CardHolder",player.UserId)
	cards[tool]={holder=player,owner=owner,expires=expires or 0};tool.Parent=bag
	return true
end
local function rootOf(player: Player): BasePart?
	local character=player.Character
	local root=if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end
local function humanoidOf(player: Player): Humanoid?
	local character=player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end
local function nearby(player: Player,p: BasePart,maxDistance: number): boolean
	local root=rootOf(player);return root~=nil and (root.Position-p.Position).Magnitude<=maxDistance
end
local function ownerSession(owner: number): any
	for _,s in Session.all() do if s.userId==owner and not s.closed then return s end end
	return nil
end
-- Stand a humanoid up, including the engine's SeatWeld so a following PivotTo is not pulled back.
local function unseat(h: Humanoid?)
	if not h then return end
	local seat=h.SeatPart
	if seat then local weld=seat:FindFirstChild("SeatWeld");if weld then weld:Destroy() end end
	h.Sit=false
end

-- Door authorizer -------------------------------------------------------------------------------
-- Entry from the non-secure side: founder always; company/guest card holders by access class.
local function authorizeDoor(player: Player,office: Model,door: Model): (boolean,string?)
	local owner=office:GetAttribute("OwnerUserId")
	if typeof(owner)~="number" then return false,"Door offline." end
	if player.UserId==owner then return true,nil end
	local classAttr=door:GetAttribute("AccessClass");local class=if typeof(classAttr)=="string" then classAttr else "staff"
	local card=Facility.hasCard(player,owner)
	if Plan.playerAllows(false,card,class) then return true,nil end
	local kind=door:GetAttribute("DoorKind")
	if typeof(kind)=="string" and HIDDEN_DENY[kind] then return false,HIDDEN_DENY[kind] end
	if door:GetAttribute("Hidden")==true then return false,"Nothing happens." end
	if not card then return false,if kind=="speedgate" then BADGE_TEXT else CARD_TEXT end
	return false,DENY[class] or "Access denied."
end

-- PropFx state writes (the client animates) --------------------------------------------------------
local function serverNow(): number return workspace:GetServerTimeNow() end
-- Tagged prop root of `inst`: itself or the nearest tagged ancestor below the office.
local function propRoot(inst: Instance?): Instance?
	local node=inst
	while node and node.Name~="Office" do
		if Collection:HasTag(node,FX_TAG) then return node end
		node=node.Parent
	end
	return nil
end
-- PropFx root by PropId inside one office (prompts beside their prop, e.g. a robot arm's controller).
local propIndex: {[Instance]:{[string]:Instance}}=setmetatable({},{__mode="k"}) :: any
local function propById(office: Instance,id: any): Instance?
	if typeof(id)~="string" then return nil end
	local map=propIndex[office]
	local cached=if map then map[id] else nil
	if map and (cached==nil or cached.Parent) then return cached end
	local fresh: {[string]:Instance}={}
	for _,root in Collection:GetTagged(FX_TAG) do
		local pid=root:GetAttribute("PropId")
		if typeof(pid)=="string" and root:IsDescendantOf(office) then fresh[pid]=root end
	end
	propIndex[office]=fresh
	return fresh[id]
end
-- Works for `seconds` from now (<= 0 stops it). One attribute write.
local function run(root: Instance?,seconds: number)
	if root then root:SetAttribute("FxUntil",if seconds>0 then serverNow()+seconds else 0) end
end
local function running(root: Instance?): boolean
	local untilTime=if root then root:GetAttribute("FxUntil") else nil
	return typeof(untilTime)=="number" and untilTime>serverNow()
end

-- Fixture index (SPEC §6 FixtureKey contract), built once per office instance -----------------
type FixtureIndex={byKey:{[string]:{[string]:BasePart}},named:{[string]:{BasePart}},machines:{[string]:{Instance}}}
local FIXTURE_NAMES: {[string]:boolean}={ToiletSeat=true,FlushButton=true,ToiletWater=true,Tap=true,TapWater=true,ShowerHead=true,ShowerWater=true,SaunaHeater=true}
local fixtureCache: {[Instance]:FixtureIndex}=setmetatable({},{__mode="k"}) :: any
local function fixtures(office: Instance): FixtureIndex
	local cached=fixtureCache[office];if cached then return cached end
	local index: FixtureIndex={byKey={},named={},machines={}}
	for _,d in office:GetDescendants() do
		if not d:IsA("BasePart") then continue end
		if FIXTURE_NAMES[d.Name] then
			local list=index.named[d.Name];if not list then list={};index.named[d.Name]=list end;table.insert(list,d)
			local key=d:GetAttribute("FixtureKey")
			if key~=nil then local map=index.byKey[d.Name];if not map then map={};index.byKey[d.Name]=map end;map[tostring(key)]=d end
		end
	end
	-- workout machines: PropFx roots carrying Machine = <prompt Value> (belts, flywheels, rower fans)
	for _,root in Collection:GetTagged(FX_TAG) do
		local machine=root:GetAttribute("Machine")
		if machine~=nil and root:IsDescendantOf(office) then
			local list=index.machines[tostring(machine)];if not list then list={};index.machines[tostring(machine)]=list end;table.insert(list,root)
		end
	end
	fixtureCache[office]=index;return index
end
local function fixtureFor(office: Instance,name: string,key: any): BasePart?
	if key==nil then return nil end
	local map=fixtures(office).byKey[name];local part=if map then map[tostring(key)] else nil
	return if part and part.Parent then part else nil
end
local function nearestNamed(office: Instance,name: string,position: Vector3,maxDistance: number): BasePart?
	local best: BasePart?=nil;local distance=maxDistance
	local list=fixtures(office).named[name];if not list then return nil end
	for _,part in list do
		if part.Parent and (part.Position-position).Magnitude<distance then best=part;distance=(part.Position-position).Magnitude end
	end
	return best
end

-- Snacks, guests, retail (unchanged economy) ---------------------------------------------------
local function consume(player: Player,tool: Instance)
	local record=snackTools[tool];local s=Session.get(player)
	if not record or record.holder~=player or not s or s.closed or not carried(player,tool) then return end
	local c=s.data.empire.campus;local n=c.snacks[record.id] or 0;if n<1 then return end
	snackTools[tool]=nil;c.snacks[record.id]=n-1
	local def=Config.find(Config.SNACKS,record.id);c.boostUntil=os.time()+def.seconds;c.boostSpeed=def.speed
	tool:Destroy();Session.markDirty(s);notify(player,def.name.." enjoyed. Walk speed "..def.speed.." for "..def.seconds.."s.")
end
local function issueSnack(s: any,id: string)
	local bag=backpack(s.player);if not bag or s.closed then return end
	local def=Config.find(Config.SNACKS,id);if not def then return end
	local tool=Instance.new("Tool");tool.Name=def.name;tool.CanBeDropped=false;tool.ToolTip="Equip, then click or tap to eat."
	local handle=Instance.new("Part");handle.Name="Handle";handle.Size=if def.shape=="cup" then Vector3.new(.9,1.3,.9) else Vector3.new(1.7,.5,1)
	handle.Color=Color3.fromRGB(unpack(def.color));handle.Massless=true;handle.CanCollide=false;handle.Parent=tool
	snackTools[tool]={holder=s.player,id=id};tool.Activated:Connect(function()consume(s.player,tool)end);tool.Parent=bag
end
local function restore(s: any)
	if s.closed or not s.player.Parent then return end
	Facility.issueCard(s.player,s.userId)
	for owner,list in guests do if list[s.userId] and list[s.userId]>os.time() then Facility.issueCard(s.player,owner,list[s.userId]) end end
	for tool,record in snackTools do if record.holder==s.player then tool:Destroy();snackTools[tool]=nil end end
	for id,count in s.data.empire.campus.snacks do for _=1,count do issueSnack(s,id) end end
end
local function buySnack(s: any,p: any): any
	local def=Config.find(Config.SNACKS,p.snackId);if not def then return {ok=false,err="BAD_INPUT"} end
	local c=s.data.empire.campus;local total=0;for _,count in c.snacks do total+=count end
	if total>=16 then return {ok=false,err="SNACK_FULL"} end
	local delivery=if p.atCounter==true then 0 else 15
	-- atCounter is only accepted from the server prompt route, never from remote payloads.
	if not Economy.spend(s,def.price+delivery,"campus") then return {ok=false,err="NO_MONEY"} end
	c.snacks[def.id]=(c.snacks[def.id] or 0)+1;issueSnack(s,def.id)
	local seller=if delivery==0 and typeof(p.shopOwnerId)=="number" then ownerSession(p.shopOwnerId) else nil
	if seller and seller~=s then
		local net=def.price*.55;Economy.grant(seller,net,"retail");seller.data.empire.campus.retailRevenue+=net;seller.data.empire.campus.retailSales+=1;Session.markDirty(seller)
	end
	Session.markDirty(s);return {ok=true}
end
-- A snack brought by staff (the founder's assistant's coffee run): joins the 16-slot snack bag as
-- the same real tool a counter purchase gives. The company pays the menu price here unless the order
-- already paid it (prepaid). false = unknown snack, bag full, closed session or not enough money.
function Facility.deliverSnack(s: any,snackId: string,prepaid: boolean?): boolean
	local def=Config.find(Config.SNACKS,snackId);if not def or s.closed then return false end
	local c=s.data.empire.campus;local total=0;for _,count in c.snacks do total+=count end
	if total>=16 then return false end
	if not prepaid and not Economy.spend(s,def.price,"campus") then return false end
	c.snacks[def.id]=(c.snacks[def.id] or 0)+1;issueSnack(s,def.id)
	Session.markDirty(s);return true
end
local function grantGuest(s: any,p: any): any
	if typeof(p.userId)~="number" or p.userId~=math.floor(p.userId) or p.userId==s.userId then return {ok=false,err="BAD_INPUT"} end
	local peer=ownerSession(p.userId);if not peer then return {ok=false,err="PLAYER_OFFLINE"} end
	guests[s.userId]=guests[s.userId] or {};guests[s.userId][p.userId]=os.time()+3600
	Facility.issueCard(peer.player,s.userId,guests[s.userId][p.userId]);notify(peer.player,s.player.DisplayName.." gave you a one-hour guest card. Founder rooms and technical labs stay private.")
	Session.markDirty(s);return {ok=true}
end
local function revokeGuest(s: any,p: any): any
	if typeof(p.userId)~="number" then return {ok=false,err="BAD_INPUT"} end
	if guests[s.userId] then guests[s.userId][p.userId]=nil end
	for tool,record in cards do if record.owner==s.userId and record.holder.UserId==p.userId then tool:Destroy();cards[tool]=nil end end
	Session.markDirty(s);return {ok=true}
end
local function upgradeRetail(s: any,_p: any): any
	local c=s.data.empire.campus;local cost=Config.RETAIL[c.retailLevel];if not cost then return {ok=false,err="MAX_RETAIL"} end
	if not Economy.spend(s,cost,"campus") then return {ok=false,err="NO_MONEY"} end
	c.retailLevel+=1;Session.markDirty(s);return {ok=true}
end

-- Security cameras: channels come from Office.Cameras (SPEC §6); founder only.
local function openSecurity(s: any,payload: any): any
	if payload.ownerId~=nil and payload.ownerId~=s.userId then return {ok=false,err="OWNER_ONLY"} end
	local p=Plot.get(s.player)
	if not p or not p.office then return {ok=false,err="LOADING"} end
	if not Facility.hasCard(s.player,s.userId,true) then return {ok=false,err="CARD_REQUIRED"} end
	local channels={}
	local folder=p.office:FindFirstChild("Cameras")
	if folder then for _,c in folder:GetDescendants() do
		local id=c:GetAttribute("CameraId");local view=c:GetAttribute("ViewCFrame")
		if c:IsA("BasePart") and id~=nil and typeof(view)=="CFrame" then
			local name=c:GetAttribute("CameraName");local level=c:GetAttribute("Level")
			table.insert(channels,{id=tostring(id),name=if typeof(name)=="string" then name else tostring(id),cframe=view,level=if typeof(level)=="number" then level else 0,room=c:GetAttribute("RoomId"),private=c:GetAttribute("Private")==true})
		end
	end end
	table.sort(channels,function(a,b)if a.level~=b.level then return a.level<b.level end;return a.name<b.name end)
	return {ok=true,ownerId=s.userId,channels=channels}
end

-- Internal employee route: identity comes from the current server-built office, never a payload.
function Facility.openEmployeeDoor(npc: Model,door: Instance): boolean
	if not door:IsA("Model") then return false end
	return Doors.requestNPC(npc,door)
end

-- Prompt actions --------------------------------------------------------------------------------
type Ctx={s:any,player:Player,q:ProximityPrompt,part:BasePart,office:Model,owner:number,plot:any,humanoid:Humanoid?}

local function doorOf(q: ProximityPrompt,office: Model): Model?
	local node: Instance?=q.Parent
	while node and node~=office do
		if node:IsA("Model") and node:GetAttribute("DoorId")~=nil then return node end
		node=node.Parent
	end
	local value=q:GetAttribute("Value")
	return if value~=nil then Doors.find(office,tostring(value)) else nil
end
local function useDoor(ctx: Ctx)
	local door=doorOf(ctx.q,ctx.office);if not door then return end
	local sideAttr=ctx.q:GetAttribute("Side")
	local ok,reason=Doors.request(ctx.player,door,if typeof(sideAttr)=="string" then sideAttr else nil)
	if not ok and reason then notify(ctx.player,if reason=="Occupied" then "Occupied. Please use another cubicle." else reason) end
end
local function toilet(ctx: Ctx)
	local p,h=ctx.part,ctx.humanoid
	local seat: Seat?=if p:IsA("Seat") then p else nil
	if not seat then local found=fixtureFor(ctx.office,"ToiletSeat",p:GetAttribute("FixtureKey"));if found and found:IsA("Seat") then seat=found end end
	if not h or not seat then return end
	if seat.Occupant and seat.Occupant~=h then notify(ctx.player,"This cubicle is occupied.");return end
	if h.SeatPart==seat then h.Sit=false;seat.Disabled=true;toiletSeats[seat]=nil
	else seat.Disabled=false;seat:Sit(h);toiletSeats[seat]=os.clock()+1.5 end
end
local function flush(ctx: Ctx)
	local p=ctx.part;Sound.play(p,"flush")
	local water=fixtureFor(ctx.office,"ToiletWater",p:GetAttribute("FixtureKey"));if not water then return end
	run(propRoot(water) or water,2) -- the client dips the water level for 2 s (PropFx flow)
	notify(ctx.player,"Toilet flushed.")
end
local function water(ctx: Ctx,action: string)
	local w=fixtureFor(ctx.office,if action=="tap" then "TapWater" else "ShowerWater",ctx.part:GetAttribute("FixtureKey"));if not w then return end
	local root=propRoot(w) or w
	-- a second press stops the water; otherwise it runs 6 s (tap) / 15 s (shower) on the client
	if running(root) then run(root,0) else run(root,if action=="tap" then 6 else 15) end
end
-- Wellness station (WorkstationService) linked to a machine root by FxStation, if any.
local function machineStation(office: Model,root: Instance): Instance?
	local id=root:GetAttribute("FxStation")
	if typeof(id)~="string" then return nil end
	local found=office:FindFirstChild(id,true)
	return if found and found:GetAttribute("WorkstationId")==id then found else nil
end
local function routine(ctx: Ctx,action: string)
	local player=ctx.player
	if routines[player] or (routineCooldown[player] or 0)>os.clock() then notify(player,"Finish your session or take a short break before the next one.");return end
	local machine=ctx.q:GetAttribute("Value")
	local roots: {Instance}=if action=="workout" and machine~=nil then (fixtures(ctx.office).machines[tostring(machine)] or {}) else {}
	if action=="workout" then
		for _,job in routines do if job.part==ctx.part or (machine~=nil and job.machine==machine and job.office==ctx.office) then notify(player,"This machine is in use.");return end end
		-- an employee on a wellness break holds the machine too
		for _,root in roots do
			local station=machineStation(ctx.office,root)
			if station and station:GetAttribute("OccupiedBy")~=nil then notify(player,"This machine is in use.");return end
		end
	end
	local seconds=if action=="workout" then 18 else 12
	routines[player]={part=ctx.part,kind=action,left=seconds,seconds=seconds,owner=ctx.owner,machine=machine,office=ctx.office,cf=ctx.plot.cframe,roots=roots}
	for _,root in roots do
		run(root,seconds) -- belts / flywheels / rower fan move on the client for the session
		local station=machineStation(ctx.office,root)
		if station then station:SetAttribute("PlayerUntil",serverNow()+seconds) end -- employees keep off it
	end
	if action=="sauna" then
		local heater=if ctx.part.Name=="SaunaHeater" then ctx.part else nearestNamed(ctx.office,"SaunaHeater",ctx.part.Position,40)
		run(propRoot(heater) or heater,20)
	end
	notify(player,if action=="workout" then "Exercise started · stay at this machine for 18 seconds." else "Sauna started · relax inside the sauna for 12 seconds.")
end
-- Generic prop use (coffee machines, fridges, copiers, printers, lockers, chargers, car lift, robot arm,
-- vending, water points ...): distance, throttle and room access were checked by handle; here a
-- per-prop cooldown, then one FxUntil write. Cosmetic: no money, no saved data.
local function useProp(ctx: Ctx)
	local root=propRoot(ctx.part) or propById(ctx.office,ctx.q:GetAttribute("Value"))
	if not root then return end
	if (propCooldown[root] or 0)>os.clock() then notify(ctx.player,"Just a moment, it is still busy.");return end
	local seconds=root:GetAttribute("FxSeconds");local secs=if typeof(seconds)=="number" then math.clamp(seconds,1,30) else 4
	propCooldown[root]=os.clock()+secs+1
	run(root,secs)
end
local function report(ctx: Ctx)
	local s,player=ctx.s,ctx.player
	run(propRoot(ctx.part),3) -- the printer feeds pages on the client
	local bag=backpack(player);if not bag then return end
	local old=bag:FindFirstChild("Company Report");if old then old:Destroy() end
	local equipped=if player.Character then player.Character:FindFirstChild("Company Report") else nil;if equipped then equipped:Destroy() end
	local tool=Instance.new("Tool");tool.Name="Company Report";tool.CanBeDropped=false;tool.RequiresHandle=false;tool.ToolTip=string.format("$%.0f · AI %.1f · office %d",s.data.money,s.data.stats.bestOverall or 0,s.data.empire.office)
	local text=tool.ToolTip;tool.Activated:Connect(function()if tool.Parent and carried(player,tool) then notify(player,text) end end);tool.Parent=bag;notify(player,"Company report printed to your backpack.")
end
-- Founder's model safe: confidential summary of the newest four model versions + training state.
local function modelSafe(ctx: Ctx)
	local data=ctx.s.data;local lines={"MODEL SAFE · CONFIDENTIAL"}
	local order=data.modelOrder or {}
	for i=#order,math.max(1,#order-3),-1 do
		local m=data.models[order[i]]
		if m then table.insert(lines,string.format("%s v%s · %s · score %.1f",tostring(m.name),tostring(m.version),tostring(m.status),m.overall or 0)) end
	end
	if #lines==1 then table.insert(lines,"No model versions stored yet.") end
	local training=data.training
	if training then
		local m=data.models[training.modelId]
		local share=if training.workTotal and training.workTotal>0 then math.clamp(training.workDone/training.workTotal,0,1) else 0
		table.insert(lines,string.format("Training: %s · %d%%",if m then m.name.." v"..tostring(m.version) else "model",math.floor(share*100)))
	else table.insert(lines,"Training: idle") end
	notify(ctx.player,table.concat(lines,"\n"))
	Remote.fire(ctx.player,"Notify","OWNER_COMPUTER",{app="lab"})
end
-- Players may take a free workstation chair that no employee has reserved.
local function sit(ctx: Ctx)
	local h=ctx.humanoid;if not h then return end
	local node: Instance?=ctx.part;local station: Instance?=nil
	while node and node~=ctx.office do if node:GetAttribute("WorkstationId")~=nil then station=node;break end;node=node.Parent end
	local seat: Seat?=if ctx.part:IsA("Seat") then ctx.part else nil
	if not seat and station then local found=station:FindFirstChildWhichIsA("Seat",true);if found then seat=found end end
	if not seat then return end
	if h.SeatPart==seat then h.Sit=false;return end
	if seat.Occupant or (station and station:GetAttribute("ReservedBy")~=nil) then notify(ctx.player,"This desk is in use.");return end
	seat:Sit(h)
end
local ACTIONS: {[string]:(Ctx)->()}={
	toilet=toilet,
	flush=flush,
	tap=function(ctx) water(ctx,"tap") end,
	shower=function(ctx) water(ctx,"shower") end,
	sauna=function(ctx) routine(ctx,"sauna") end,
	workout=function(ctx) routine(ctx,"workout") end,
	report=report,
	modelSafe=modelSafe,
	sit=sit,
	prop=useProp,
	security=function(ctx)
		local result=openSecurity(ctx.s,{ownerId=ctx.owner});if result.ok then Remote.fire(ctx.player,"Notify","SECURITY_OPEN",result) end
	end,
	ownerComputer=function(ctx)
		local app=ctx.q:GetAttribute("Value");Remote.fire(ctx.player,"Notify","OWNER_COMPUTER",{app=if typeof(app)=="string" then app else "empire"})
	end,
	fleet=function(ctx) Remote.fire(ctx.player,"Notify","OWNER_COMPUTER",{app="campus",section="fleet"}) end,
}
function Facility.handle(player: Player,q: ProximityPrompt)
	local action=q:GetAttribute("CampusAction");if typeof(action)~="string" or action=="spawnCar" then return end
	local s=Session.get(player);local part=q.Parent
	if not s or s.closed or not part or not part:IsA("BasePart") or not nearby(player,part,16) then return end
	local officeInst=q:FindFirstAncestor("Office");if not officeInst or not officeInst:IsA("Model") then return end
	local office: Model=officeInst
	local owner=office:GetAttribute("OwnerUserId");if typeof(owner)~="number" then return end
	local own=ownerSession(owner);local p=if own then Plot.get(own.player) else nil
	if not own or not p or p.office~=office then return end
	if (promptTimes[player] or 0)>os.clock() then return end;promptTimes[player]=os.clock()+.3
	local ctx: Ctx={s=s,player=player,q=q,part=part,office=office,owner=owner,plot=p,humanoid=humanoidOf(player)}
	if action=="door" then useDoor(ctx);return end -- DoorService decides (egress never needs a card)
	if action=="liftCall" then
		local level=q:GetAttribute("Value");if typeof(level)~="number" then return end
		local ok,reason=Lift.hallCall(player,office,level)
		if not ok and reason and reason~="BAD_INPUT" then notify(player,LIFT_TEXT[reason] or reason) end
		return
	end
	if action=="liftPanel" then Remote.fire(player,"Notify","LIFT_PANEL",Lift.panel(player,office));return end
	if action=="snack" then -- the café is public: visitors pay like everybody else
		local result=buySnack(s,{snackId=q:GetAttribute("Value"),shopOwnerId=owner,atCounter=true})
		notify(player,if result.ok then "Snack added to your backpack. Equip it to eat." elseif result.err=="NO_MONEY" then "Not enough money for this snack." elseif result.err=="SNACK_FULL" then "Your snack bag is full." else "This snack is not on the menu.")
		return
	end
	if action=="card" then
		if owner==player.UserId then Facility.issueCard(player,owner);notify(player,"Replacement employee card issued.") end
		return
	end
	local fn=ACTIONS[action];if not fn then return end
	local founderText=FOUNDER_ACTIONS[action] or (if q:GetAttribute("OwnerOnly")==true then "Founder only." else nil)
	if founderText then
		if player.UserId~=owner then notify(player,founderText);return end
		if not Facility.hasCard(player,owner,true) then notify(player,CARD_TEXT);return end
	else
		-- Fixtures follow the access class of the room they stand in (public rooms need no card).
		local tier=office:GetAttribute("OfficeTier")
		local class=if typeof(tier)=="number" then Plan.accessAt(tier,p.cframe:PointToObjectSpace(part.Position)) else "staff"
		local card=Facility.hasCard(player,owner)
		if not Plan.playerAllows(player.UserId==owner,card,class) then notify(player,if card then DENY[class] or CARD_TEXT else CARD_TEXT);return end
	end
	fn(ctx)
end

-- Access guard (security fallback) ---------------------------------------------------------------
local function inRect(r: any,v: Vector3): boolean
	return v.X>r.x1 and v.X<r.x2 and v.Z>r.z1 and v.Z<r.z2
end
-- Just outside the nearest door of `room` whose far side this player may use (plot-local door
-- centre ± inward*4, whichever point lies outside the room; facing away from the room). Doors owned
-- by neighbouring rooms count too, and flipped doors (inward pointing out of the room) work.
local function outsideDoor(p: any,tier: number,room: any,localPos: Vector3,isOwner: boolean,hasCard: boolean): CFrame?
	local best: CFrame?=nil;local bestDistance=math.huge
	for _,d in Layout.doors(tier) do
		if d.level~=room.level then continue end
		local centre=Vector3.new(d.x,Plan.levelY(d.level)+3,d.z)
		local a,b=centre+d.inward*4,centre-d.inward*4
		local target: Vector3?=nil
		if inRect(room,a) and not inRect(room,b) then target=b elseif inRect(room,b) and not inRect(room,a) then target=a end
		if target then
			local distance=(target-localPos).Magnitude
			if distance<bestDistance and Plan.playerAllows(isOwner,hasCard,(Plan.accessAt(tier,target))) then
				best=p.cframe*CFrame.lookAt(target,target+(target-centre));bestDistance=distance
			end
		end
	end
	return best
end
local function guard(s: any,character: Model,root: BasePart,h: Humanoid?)
	local seat=if h then h.SeatPart else nil
	if seat and seat:IsA("VehicleSeat") then return end -- never yank a driver out of a car
	if Lift.riding(character) then return end -- re-checked after the ride
	for _,p in Plot.all() do
		if not p.owner or not p.office then continue end
		local tier=p.office:GetAttribute("OfficeTier");if typeof(tier)~="number" then continue end
		local localPos=p.cframe:PointToObjectSpace(root.Position)
		if not Plan.inside(tier,localPos) then continue end
		local ownerId=p.owner.UserId;local isOwner=s.userId==ownerId
		local hasCard=isOwner or Facility.hasCard(s.player,ownerId)
		local class,room=Plan.accessAt(tier,localPos)
		if not Plan.playerAllows(isOwner,hasCard,class) then
			local target=(if room then outsideDoor(p,tier,room,localPos,isOwner,hasCard) else nil) or Plot.arrival(p)
			local text=if hasCard then (DENY[class] or "This room is not on your card.").." You were shown back out." else VISITOR_TEXT
			unseat(h);character:PivotTo(target);notify(s.player,text)
		end
		return
	end
end
local function walkSpeed(s: any,h: Humanoid)
	local c=s.data.empire.campus
	local want=if c.boostUntil>os.time() then c.boostSpeed else 16
	local last=speedApplied[s.player]
	if last and last.humanoid==h and last.value==want then return end -- leave other scripts' changes alone
	if h.WalkSpeed~=want then h.WalkSpeed=want end
	speedApplied[s.player]={humanoid=h,value=want}
end
local function atRoutine(player: Player,job: any): boolean
	if job.kind~="sauna" then return nearby(player,job.part,7) end
	local root=rootOf(player);local tier=job.office:GetAttribute("OfficeTier")
	if not root or typeof(tier)~="number" then return false end
	local room=Plan.room(tier,"P0_SAUNA");if not room then return nearby(player,job.part,10) end
	local pos=job.cf:PointToObjectSpace(root.Position);local base=Plan.levelY(room.level)
	return pos.X>room.x1 and pos.X<room.x2 and pos.Z>room.z1 and pos.Z<room.z2 and pos.Y>base-2 and pos.Y<base+14
end
function Facility.tick(dt: number)
	for seat,grace in toiletSeats do
		if not seat.Parent then toiletSeats[seat]=nil
		elseif os.clock()>grace and seat.Occupant==nil then seat.Disabled=true;toiletSeats[seat]=nil end
	end
	for player,job in routines do
		local s=Session.get(player)
		if not s or s.closed or not job.part.Parent or not atRoutine(player,job) or not Facility.hasCard(player,job.owner) then
			routines[player]=nil;notify(player,"Session stopped because you left the station.")
			for _,root in job.roots or {} do
				run(root,0)
				local station=machineStation(job.office,root);if station then station:SetAttribute("PlayerUntil",nil) end
			end
		else
			job.left-=dt
			if job.left<=1e-6 then
				local c=s.data.empire.campus;local boosted=c.boostUntil>os.time();c.boostUntil=math.max(c.boostUntil,os.time()+90);local speed=if job.kind=="workout" then 20 else 18;c.boostSpeed=if boosted then math.max(c.boostSpeed,speed) else speed
				routines[player]=nil;routineCooldown[player]=os.clock()+60;Session.markDirty(s);notify(player,"Session complete · refreshed for 90 seconds.")
			end
		end
	end
	for tool,record in cards do if not tool.Parent or (record.expires>0 and record.expires<=os.time()) then tool:Destroy();cards[tool]=nil end end
	for tool,_ in snackTools do if not tool.Parent then snackTools[tool]=nil end end
	guardClock+=dt;local guardNow=guardClock>=.25;if guardNow then guardClock=0 end
	for _,s in Session.all() do
		if s.closed then continue end
		local character=s.player.Character;local root=rootOf(s.player);local h=humanoidOf(s.player)
		if h then walkSpeed(s,h) end
		if guardNow and character and root then guard(s,character,root,h) end
	end
end
function Facility.economyTick(s: any,dt: number)
	local c=s.data.empire.campus
	if s.data.company then
		c.retailClock+=dt
		if c.retailClock>=30 then
			c.retailClock-=30
			local staff=0;for _,count in s.data.empire.employees do staff+=count end
			local tickets=c.retailLevel+math.floor(staff/24)
			local net=tickets*12
			-- P&L line "retail" (CORE_SPEC 3.6; corefix request 8 / econ request 3)
			c.retailSales+=tickets;c.retailRevenue+=net;Economy.grant(s,net,"retail");Session.markDirty(s)
		end
	end
	local online={};local passes={}
	for _,peer in Session.all() do if not peer.closed and peer.userId~=s.userId then table.insert(online,{id=peer.userId,name=peer.player.DisplayName}) end end
	local granted=guests[s.userId];if granted then for id,expires in granted do if expires>os.time() then table.insert(passes,{id=id,expires=expires}) end end end
	local job=routines[s.player]
	local own=Plot.get(s.player);local opsFolder=if own and own.office then own.office:FindFirstChild("OperationsEmployees") else nil
	s.live.campus={hasCard=Facility.hasCard(s.player,s.userId),online=online,passes=passes,supportStaff=if opsFolder then #opsFolder:GetChildren() else 0,retailNetPerTicket=12,routine=if job then {kind=job.kind,remaining=job.left,seconds=job.seconds} else nil}
end
function Facility.init()
	Doors.setAuthorizer(authorizeDoor)
	Doors.setNotifier(function(player: Player,text: string) notify(player,text) end)
	Lift.init(function(player: Player,ownerId: number): boolean return Facility.hasCard(player,ownerId) end)
	local limits={burst=3,perSecond=1,company=true}
	Remote.bind("UseCampusLift",{burst=4,perSecond=2},Lift.remote)
	Remote.bind("OpenSecurity",{burst=2,perSecond=.5},openSecurity)
	Remote.bind("BuySnack",limits,function(s,p)return buySnack(s,{snackId=p.snackId})end)
	Remote.bind("GrantGuestCard",limits,grantGuest);Remote.bind("RevokeGuestCard",limits,revokeGuest);Remote.bind("UpgradeRetail",limits,upgradeRetail)
	Remote.bind("ReplaceCard",{burst=2,perSecond=.25},function(s,_p)return {ok=Facility.issueCard(s.player,s.userId)}end)
	-- PromptTriggered passes (prompt, player); handle keeps its (player, prompt) signature.
	Prompts.PromptTriggered:Connect(function(q: ProximityPrompt,player: Player) Facility.handle(player,q) end)
	Session.onLoaded(function(s)
		connections[s.player]=s.player.CharacterAdded:Connect(function()task.delay(.5,restore,s)end)
		task.delay(.5,restore,s)
	end)
	Session.onClosing(function(s)
		routines[s.player]=nil;routineCooldown[s.player]=nil;promptTimes[s.player]=nil;speedApplied[s.player]=nil
		if connections[s.player] then connections[s.player]:Disconnect();connections[s.player]=nil end
		guests[s.userId]=nil
		for _,list in guests do list[s.userId]=nil end
		for tool,record in cards do if record.holder==s.player or record.owner==s.userId then tool:Destroy();cards[tool]=nil end end
		for tool,record in snackTools do if record.holder==s.player then tool:Destroy();snackTools[tool]=nil end end
	end)
end
return Facility
