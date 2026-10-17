--!strict
-- Live architecture: every value comes from the same session that owns the building.
-- Screens (attribute LiveScreen=<kind>, SurfaceGui Desktop -> Header/Body/Footer/ProgressTrack.Fill)
-- are registered once per office and rewritten only near players (1 s close by, 6 s further away).
-- Texts describe real state only: idle rooms say they are idle, guidance repeats the real rule.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ModelMath=require(ReplicatedStorage.Shared.ModelMath)
local EmpireMath=require(ReplicatedStorage.Shared.EmpireMath)
local Workforce=require(ReplicatedStorage.Shared.WorkforceMath)
local Journey=require(ReplicatedStorage.Shared.JourneyMath)
local Format=require(ReplicatedStorage.Shared.Format)
local MarketMath=require(ReplicatedStorage.Shared.MarketMath)
local ModelConfig=require(ReplicatedStorage.Shared.Config.ModelConfig)
local MarketConfig=require(ReplicatedStorage.Shared.Config.MarketConfig)
local HardwareConfig=require(ReplicatedStorage.Shared.Config.HardwareConfig)
local CampusConfig=require(ReplicatedStorage.Shared.Config.CampusConfig)
local EmpireConfig=require(ReplicatedStorage.Shared.Config.EmpireConfig)
local StudioConfig=require(ReplicatedStorage.Shared.Config.StudioConfig)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Ops=require(ReplicatedStorage.Shared.CompanyOps)
local Plot=require(script.Parent.PlotService)
local Session=require(script.Parent.SessionService)
local Service={}
local EPOCHS=10 -- AIModelService logs ten epochs per run
local FOOTER="DATA → COMPUTE → DESIGN → TRAIN → EVALUATE → LAUNCH"
-- Screens whose header turns amber (client side) while a training decision waits.
local ALERT_KINDS={training=true,compute=true,engineering=true,journey=true,founder=true,lobby=true,boardroom=true}
local clock=0;local caches: {[Instance]:any}=setmetatable({},{__mode="k"}) :: any

-- Optional services (DoorService, LiftService) are required lazily: a missing or failing module
-- only removes those lines from the security screen, it never breaks the other screens.
local optional: {[string]:any}={}
local function service(name: string): any
	local known=optional[name]
	if known~=nil then return if known==false then nil else known end
	local ok,mod=pcall(function(): any
		local m=script.Parent:FindFirstChild(name)
		return if m and m:IsA("ModuleScript") then (require :: any)(m) else nil
	end)
	if not ok then warn(`[Screens] {name} unavailable: {mod}`) end
	optional[name]=if ok and mod then mod else false
	return if ok then mod else nil
end
local function inspect(name: string,office: Model): any
	local svc=service(name)
	if not svc or typeof(svc.inspect)~="function" then return nil end
	local ok,result=pcall(svc.inspect,office)
	return if ok then result else nil
end

local function proximity(position: Vector3,positions: {Vector3}): number
	local min=math.huge;for _,p in positions do min=math.min(min,(p-position).Magnitude) end;return min
end
local function attr(i: Instance?,name: string): any return if i then i:GetAttribute(name) else nil end
local function title(model: any): string return if model then model.name.." v"..model.version else "No model yet" end
local function words(id: string): string
	-- "ModelReviewMeeting" / "MODEL REVIEW" -> "Model review meeting" / "Model review"
	local text=string.lower((string.gsub(id,"(%l)(%u)","%1 %2")))
	return string.upper(string.sub(text,1,1))..string.sub(text,2)
end
local function hourText(hour: number?): string
	if typeof(hour)~="number" then return "--:--" end
	local minutes=math.floor((hour%24)*60+.5)
	return string.format("%02d:%02d",(minutes//60)%24,minutes%60)
end
local function count(t: any): number
	if typeof(t)=="number" then return t end
	if typeof(t)~="table" then return 0 end
	local n=0;for _,v in t do if v then n+=1 end end;return n
end

-- Company state helpers (CORE_SPEC 3.2 / 5.5 / 11.5): B2B accounts, trips, compute ------------------------
local function money(n: number): string return Ops.money(n) end
local function accountsOf(e: any): ({any},number)
	local list,retainer={},0
	local d=e.deals
	if typeof(d)=="table" and typeof(d.accounts)=="table" then
		for _,c in Ops.CLIENTS do
			local acc=d.accounts[c.id]
			if acc then table.insert(list,{client=c,acc=acc});retainer+=c.retainer end
		end
	end
	return list,retainer
end
local function tripsOf(s: any): {any}
	local ops=s.live and s.live.ops
	if typeof(ops)=="table" and typeof(ops.trips)=="table" then return ops.trips end
	local d=s.data.empire.deals
	return if typeof(d)=="table" and typeof(d.tripList)=="table" then d.tripList else {}
end
local function tripShort(t: any): string
	local c=Ops.client(t.client);local name=if c then c.name else tostring(t.client)
	if t.hosted then return name.." team at the guest house" end
	local who=if t.founder then "Founder" elseif (tonumber(t.crew) or 1)>=2 then "Rep + engineer" else "Rep"
	return string.format("%s → %s (%s)",who,name,if t.kind=="renew" then "check-in" else "pilot")
end
-- who is in today per role (CompanyOps.presence), computed at most once per second per company: a tier-4 HQ has
-- ~16 HR screens and 2 receptions refreshing every second near the player
type Presence={present: number,vacation: number,sick: number,total: number}
local presenceMemo: {[any]:{at: number,roles: {[string]:Presence}}}=setmetatable({},{__mode="k"}) :: any
local function presenceOf(e: any): {[string]:Presence}
	local now=math.floor(workspace:GetServerTimeNow())
	local memo=presenceMemo[e]
	if memo and memo.at==now then return memo.roles end
	local roles: {[string]:Presence}={}
	for _,role in EmpireConfig.ROLES do
		local p: Presence={present=0,vacation=0,sick=0,total=0}
		for _,st in Ops.presence(e,role.id) do
			p.total+=1
			if st=="present" then p.present+=1 elseif st=="vacation" then p.vacation+=1 elseif st=="sick" then p.sick+=1 end
		end
		roles[role.id]=p
	end
	presenceMemo[e]={at=now,roles=roles}
	return roles
end
-- the company day an account ends on (the calendar moves with the server day)
local function endDay(e: any,expires: number): number
	local into=(workspace:GetServerTimeNow()%Ops.DAY)/Ops.DAY
	return Ops.day(e)+math.floor(into+math.max(0,expires-(tonumber(e.seconds) or 0))/Ops.DAY)
end

-- Screen registry ---------------------------------------------------------------------------
local function stationOf(p: BasePart,office: Model): Model?
	local node: Instance?=p.Parent
	for _=1,4 do
		if not node or node==office then return nil end
		if node:IsA("Model") and node:GetAttribute("WorkstationId")~=nil and node:GetAttribute("WorkstationType")~=nil then return node end
		node=node.Parent
	end
	return nil
end
local function roomOf(p: BasePart,office: Model,tier: number,cf: CFrame?): (string?,string?,number?)
	local node: Instance?=p.Parent
	while node and node~=office do
		local id=node:GetAttribute("RoomId")
		if typeof(id)=="string" then
			local r=Plan.room(tier,id)
			return id,(node:GetAttribute("RoomName") or (if r then r.name else id)) :: string,(node:GetAttribute("Level") or (if r then r.level else nil)) :: number?
		end
		node=node.Parent
	end
	if cf then
		local v=cf:PointToObjectSpace(p.Position);local r=Plan.roomAt(tier,v)
		if r then return r.id,r.name,r.level end
		return nil,nil,Plan.levelAt(tier,v.Y)
	end
	return nil,nil,nil
end
local function scan(office: Model): any
	local cache=caches[office];if cache then return cache end
	local tier=Plan.clampTier(tonumber(office:GetAttribute("OfficeTier")) or 1) -- plan tier 0 = garage stage
	local cf=office:GetAttribute("CampusCFrame");local frame: CFrame?=if typeof(cf)=="CFrame" then cf else nil
	cache={screens={},byPart={},meetings={},cameras=0,tier=tier,cf=frame,visitors=0,security=nil,securityAt=-math.huge}
	for _,p in office:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("LiveScreen") then
			local roomId,roomName,level=roomOf(p,office,tier,frame)
			local entry={part=p,kind=tostring(p:GetAttribute("LiveScreen")),w=stationOf(p,office),roomId=roomId,roomName=roomName,level=level,next=0}
			table.insert(cache.screens,entry);cache.byPart[p]=entry
		elseif p:IsA("Model") and p:GetAttribute("WorkstationType")=="Meeting" then
			local room=tostring(p:GetAttribute("MeetingRoom") or p:GetAttribute("HomeRoom") or "")
			cache.meetings[room]=cache.meetings[room] or {};table.insert(cache.meetings[room],p)
		elseif p:IsA("BasePart") and p:GetAttribute("CameraId")~=nil then
			cache.cameras+=1
		end
	end
	caches[office]=cache;return cache
end

-- Shared value helpers ----------------------------------------------------------------------
function Service.assetValue(data: any): number
	local total=data.money
	for _,gpu in HardwareConfig.GPUS do total+=(data.gpus[gpu.id] or 0)*(gpu.price or 0) end
	for i=2,data.empire.office do total+=EmpireConfig.OFFICES[i].price end
	for _,car in CampusConfig.CARS do if data.empire.campus.cars[car.id] then total+=car.price end end
	return total
end
local function sizeOf(id: string?): any return if id then ModelConfig.getSize(id) else nil end
local function focusLabel(id: string?): string local f=if id then ModelConfig.getFocus(id) else nil;return if f then f.label else "Balanced" end
-- Largest size the fleet's VRAM fits and the next size up (7B also needs Frontier research).
local function vramFit(d: any): (any,any)
	local vram=ModelMath.fleet(d.gpus).vram;local fit,nextSize=nil,nil
	for _,size in ModelConfig.SIZES do
		if size.vram<=vram then fit=size elseif not nextSize then nextSize=size end
	end
	return fit,nextSize
end
-- Guidance that repeats JourneyMath's real checks: VRAM first, then data, then research.
local function guidance(d: any): string
	local flow=Journey.progress(d)
	local fit,nextSize=vramFit(d);local vram=ModelMath.fleet(d.gpus).vram
	if flow.missingVram>0 then
		-- JourneyMath checks the smallest size on the server, so a smaller size is no option here.
		local smallest=ModelConfig.getSize("s100m") or ModelConfig.SIZES[1]
		return string.format("%s needs %d GB more VRAM · Open Lab → GPUs",smallest.label,flow.missingVram)
	end
	if not fit then return "Open Lab → GPUs: no model size fits your VRAM yet." end
	local stock=ModelMath.dataSummary(d.data)
	if stock.total<ModelConfig.TRAINING.minTokens then return flow.hint end
	if nextSize then
		local missing=nextSize.vram-vram
		return string.format("%s needs %d GB more VRAM · Open Lab → GPUs or pick a smaller size",nextSize.label,missing)
	end
	if not d.empire.research.frontier then return "7B fits your VRAM; it requires Frontier Architecture research." end
	return flow.hint
end
local function gpuCount(d: any): number
	local n=0;for _,gpu in HardwareConfig.GPUS do n+=d.gpus[gpu.id] or 0 end;return n
end
local function researchBonuses(b: any): string
	local parts={}
	if b.core>0 then table.insert(parts,string.format("+%d core stats",b.core)) end
	if b.reliability>0 then table.insert(parts,string.format("+%d reliability",b.reliability)) end
	if b.serving<1 then table.insert(parts,string.format("serving cost -%.0f%%",(1-b.serving)*100)) end
	return if #parts>0 then table.concat(parts," · ") else "no research bonuses yet"
end
local function liveModels(d: any): {any}
	local out={};for _,id in d.modelOrder do local m=d.models[id];if m and m.status=="live" then table.insert(out,m) end end;return out
end
local function usersOf(s: any,m: any): number
	local r=s.live.perModel and s.live.perModel[m.id]
	if r and typeof(r.users)=="number" then return r.users end
	return if m.market then MarketMath.totalUsers(m.market) else 0
end
local function benchmarks(m: any): string
	local st=m.stats or {}
	return string.format("R%.0f C%.0f M%.0f Cr%.0f K%.0f Rl%.0f",st.reasoning or 0,st.coding or 0,st.math or 0,st.creativity or 0,st.knowledge or 0,st.reliability or 0)
end
local function trainingLine(d: any): string?
	local t=d.training;if not t then return nil end
	return string.format("%s %.0f%% · epoch %d / %d",if t.refinement then "refining" else "training",math.clamp(t.workDone/math.max(1,t.workTotal),0,1)*100,t.epoch or 0,EPOCHS)
end
local function rankOf(s: any): string
	if s.live.rankings and s.live.rankings.boards then
		for i,row in s.live.rankings.boards.overall or {} do if row.userId==s.userId then return "#"..i end end
	end
	return "Not listed"
end
-- Live building state (doors, lift, cameras), cached per office for one second ---------------
-- LiftService.inspect: {attached, state, level, target, door, queue={hall={levels},car={levels}}, riders,
-- tickets (count), reason}. Cabin attributes CurrentLevel/LiftState are the fallback.
local function liftState(office: Model): any
	local info=inspect("LiftService",office)
	local cabin=office:FindFirstChild("LiftCabin",true)
	local out={state=attr(cabin,"LiftState"),level=attr(cabin,"CurrentLevel"),target=nil,calls=0,riders=0,queue=0,attached=cabin~=nil}
	if typeof(info)=="table" then
		if info.attached==false then out.attached=false end
		out.state=info.state or info.status or out.state
		out.level=info.level or info.currentLevel or out.level
		out.target=info.target
		local q=info.queue
		if typeof(q)=="table" and (q.hall~=nil or q.car~=nil) then out.calls=count(q.hall)+count(q.car)
		else out.calls=count(info.hall)+count(info.car);out.queue=count(q) end
		out.riders=count(info.riders)
		out.queue+=count(info.tickets)
	end
	return out
end
local function securityState(office: Model,cache: any): any
	local now=os.clock()
	if cache.security and now-cache.securityAt<1 then return cache.security end
	local doors=inspect("DoorService",office)
	local st={known=typeof(doors)=="table",doors=0,open=0,locked=0,computeOpen=0,lift=liftState(office),cameras=cache.cameras}
	if st.known then
		for _,door in doors do
			if typeof(door)~="table" or door.kind=="cubicle" or door.kind=="fridge" then continue end
			st.doors+=1
			if door.state=="locked" then st.locked+=1
			elseif door.state=="open" or door.state=="opening" or door.state=="closing" then
				st.open+=1;if door.access=="compute" then st.computeOpen+=1 end
			end
		end
	end
	cache.security=st;cache.securityAt=now
	return st
end
local function liftText(tier: number,lift: any): string
	if not lift.attached then return "Lift not running yet · use the stairs" end
	local level=if typeof(lift.level)=="number" then Plan.levelLabel(tier,lift.level) else "?"
	local state=if typeof(lift.state)=="string" then string.lower((string.gsub(lift.state,"_"," "))) else nil
	if state=="out of service" then return "Lift out of service at "..level.." · use the stairs" end
	if typeof(lift.target)=="number" and lift.target~=lift.level then
		return string.format("Lift %s → %s · %d riding",level,Plan.levelLabel(tier,lift.target),lift.riders)
	end
	return string.format("Lift %s at %s · %d calls · %d staff waiting",state or "ready",level,lift.calls,lift.queue)
end
local function meetingInfo(ctx: any,fallback: string?): (string,number,number,{string},string?)
	local entry=ctx.entry;local cache=ctx.cache
	local room=attr(ctx.screen,"MeetingRoom") or fallback
	if typeof(room)~="string" and entry and entry.roomId then
		local r=Plan.room(ctx.tier,entry.roomId);room=if r and r.meeting then r.meeting else entry.roomId
	end
	local seats=if cache and typeof(room)=="string" then cache.meetings[room] or {} else {}
	local used,people,topic=0,{},nil
	for _,m in seats do
		local seat=m:FindFirstChildWhichIsA("Seat",true)
		if m:GetAttribute("OccupiedBy")~=nil or (seat and seat.Occupant) then
			used+=1
			local name=m:GetAttribute("EmployeeName");if typeof(name)=="string" and #people<4 then table.insert(people,name) end
			local task=m:GetAttribute("Software");if typeof(task)=="string" and not topic then topic=words(task) end
		end
	end
	return tostring(room or "Meeting room"),#seats,used,people,topic
end

-- Presentations -----------------------------------------------------------------------------
type Ctx={s: any,d: any,e: any,w: Model?,screen: BasePart?,office: Model?,cache: any,entry: any,tier: number,company: string,footer: string}
local P: {[string]:(Ctx)->(string,string,string,number)}={}

P.data=function(c)
	local d=c.d;local stock=ModelMath.dataSummary(d.data)
	local general=d.data.general;local code=d.data.code;local mathData=d.data.math
	return "DATA OPERATIONS",string.format("General  %s tokens\nCode       %s tokens\nMath       %s tokens\nQuality    %.1f%%\nCurator production  %s tokens/s",Format.tokens(if general then general.tokens else 0),Format.tokens(if code then code.tokens else 0),Format.tokens(if mathData then mathData.tokens else 0),stock.quality*100,Format.tokens(Workforce.count(c.e,"curator")*300000)),c.footer,stock.quality
end
P.training=function(c)
	local d,e=c.d,c.e;local t=d.training;local fleet=ModelMath.fleet(d.gpus)
	local n=gpuCount(d)
	local cluster=string.format("%d GPU%s · %d GB VRAM · cooling %d / 8",n,if n==1 then "" else "s",fleet.vram,e.infrastructure.cooling)
	if not t then
		local fit=vramFit(d);local last=Journey.latest(d)
		return "GPU CLUSTER · IDLE",table.concat({
			"No training run. The cluster is idle.",cluster,
			if fit then "Fits models up to "..fit.label else "No model size fits yet",
			guidance(d),
			if last then string.format("Last model  %s · overall %.1f",title(last),last.overall or 0) else "No model trained yet",
		},"\n"),c.footer,0
	end
	local m=d.models[t.modelId];local size=sizeOf(m and m.sizeId)
	local progress=math.clamp(t.workDone/math.max(1,t.workTotal),0,1)
	local loss=t.loss[#t.loss]
	local name=string.format("%s · %s · %s",title(m),if size then size.label else "?",focusLabel(m and m.focusId))
	local event=t.event
	if event and event.pending then
		local def=ModelConfig.getEvent(event.id)
		local choices={};if def and def.choices then for _,ch in def.choices do table.insert(choices,ch.label) end end
		local default=if def and def.default and def.choices then ModelConfig.getChoice(def,def.default) else nil
		local left=math.max(0,math.ceil((event.expiresAt or 0)-workspace:GetServerTimeNow()))
		return "TRAINING DECISION REQUIRED",table.concat({
			if def then def.title..": "..def.text else "A training decision is waiting.",
			"Choose  "..table.concat(choices," / "),
			string.format("Automatic choice in %d s: %s",left,if default then default.label else "default"),
			string.format("%s paused at %.1f%% · epoch %d / %d",title(m),progress*100,t.epoch or 0,EPOCHS),
			"Decide in Lab → Training Control",
		},"\n"),c.footer,progress
	end
	local rate=EmpireMath.trainingRate(d.gpus,t.workTotal,e)
	local eta=if rate>0 then (t.workTotal-t.workDone)/rate else math.huge
	return if t.refinement then "MODEL REFINEMENT" else "MODEL TRAINING",table.concat({
		name,
		string.format("Progress  %.1f%%  ·  epoch %d / %d",progress*100,t.epoch or 0,EPOCHS),
		string.format("Loss  %s  ·  expected overall %.1f",if loss then string.format("%.3f",loss) else "—",t.expected or 0),
		if eta<math.huge then "Time left  about "..Format.duration(eta) else "Time left  waiting for compute",
		cluster,
	},"\n"),c.footer,progress
end
-- Data hall / compute operations / IT desk (user request 23): load, rack faults, compute reserved for clients
P.compute=function(c)
	local s,d,e=c.s,c.d,c.e;local live=s.live;local fleet=ModelMath.fleet(d.gpus)
	local compute=if typeof(live.compute)=="table" then live.compute else {}
	local capacity=tonumber(live.capacity) or 0;local load=tonumber(live.load) or 0;local waiting=tonumber(live.waitlist) or 0
	local serving=#liveModels(d)>0
	local full=if capacity>0 then load/capacity else 0
	local faults=if typeof(compute.faults)=="table" then compute.faults else {}
	local accounts=accountsOf(e)
	local lines={}
	table.insert(lines,if not serving then "No model is serving · the racks idle" elseif capacity<=0 then string.format("Serving %s users",Format.compact(live.users or 0)) else string.format("Servers %d%% full · %s users",math.floor(full*100+.5),Format.compact(live.users or 0)))
	if waiting>0 then table.insert(lines,string.format("%s users waiting for capacity",Format.int(waiting))) end
	table.insert(lines,string.format("GPUs %d / %d slots · %.1f units · cooling %d%%",fleet.slotsUsed,HardwareConfig.slots(e),fleet.throughput,math.floor(HardwareConfig.thermal(e,fleet.throughput)*100+.5)))
	table.insert(lines,string.format("Reserved for clients %.1f units · %d account%s",tonumber(compute.reserved) or 0,#accounts,if #accounts==1 then "" else "s"))
	-- which model uses the serving compute (LOGIC_BRIEF 23a): share of the load = users x SERVE_UNITS of its size
	if serving then
		local units=(MarketConfig :: any).SERVE_UNITS or {}
		local loads,total={},0
		for _,m in liveModels(d) do local l=usersOf(s,m)*(units[m.sizeId] or 1);total+=l;table.insert(loads,{m=m,l=l}) end
		table.sort(loads,function(a,b) return a.l>b.l end)
		if total>0 then
			local parts={}
			for i=1,math.min(3,#loads) do table.insert(parts,string.format("%s v%d %d%%",tostring(loads[i].m.name),tonumber(loads[i].m.version) or 1,math.floor(loads[i].l/total*100+.5))) end
			table.insert(lines,"Serving  "..table.concat(parts," · "))
		end
	end
	if #faults==0 then table.insert(lines,"Rack faults  none · every blade online")
	else
		-- who repairs it: StaffEvents writes FaultWorker (job title, nil = nobody yet) and FaultFix ("walk" / "rack" /
		-- "remote") on the blade of each fault slot (staffops request #8; same words as the rack label)
		local blades=if c.office then c.office:FindFirstChild("Blades") else nil
		local bladeList=if blades then blades:GetChildren() else {}
		for i=1,math.min(2,#faults) do
			local f=faults[i];local gpu=HardwareConfig.getGPU(tostring(f.gpu))
			local blade=bladeList[tonumber(f.slot) or 0]
			local who=if blade then blade:GetAttribute("FaultWorker") else nil
			local fix=if blade then blade:GetAttribute("FaultFix") else nil
			local state=if typeof(who)~="string" then (if compute.it then "waiting for IT" else "no IT on duty")
				elseif fix=="walk" then who.." on the way" elseif fix=="remote" then who.." · remote fix" else who.." repairing"
			table.insert(lines,string.format("Rack R%d fault · %s · %s",tonumber(f.slot) or 0,if gpu then gpu.label else tostring(f.gpu),state))
		end
		if #faults>2 then table.insert(lines,string.format("+ %d more rack faults",#faults-2)) end
	end
	table.insert(lines,if d.training then "Training  "..(trainingLine(d) or "running") else "Training  idle")
	local header=if #faults>0 then "DATA HALL · RACK FAULT" elseif waiting>0 then "DATA HALL · OVER CAPACITY" elseif serving and capacity>0 then string.format("DATA HALL · %d%% LOAD",math.floor(full*100+.5)) elseif serving then "DATA HALL · SERVING" else "DATA HALL · IDLE"
	local footer=if Ops.stageIndex(e)<2 then "Garage rack · no IT desk yet" elseif compute.it then "IT on duty · a fault takes about "..Ops.FAULT.it.." s to fix" else "No IT on duty · faults take about "..math.floor(Ops.FAULT.alone/60).." min"
	return header,table.concat(lines,"\n"),footer,math.clamp(full,0,1)
end
P.engineering=function(c)
	local d=c.d;local fleet=ModelMath.fleet(d.gpus);local stock=ModelMath.dataSummary(d.data)
	local current=if d.training then d.models[d.training.modelId] else Journey.latest(d)
	local progress=if d.training then math.clamp(d.training.workDone/math.max(1,d.training.workTotal),0,1) else 0
	local mode=if c.w then tostring(c.w:GetAttribute("WorkstationId") or "") else ""
	if #mode%2==0 then return "AI EMPIRE / DEV",string.format("model = %q\ndata.tokens = %s\ncompute.vram = %d GB\ntraining.status = %q\nteam.engineers = %.1f",title(current),Format.tokens(stock.total),fleet.vram,if d.training then "RUNNING" else "IDLE",Workforce.count(c.e,"engineer")),c.footer,progress end
	return P.training(c)
end
P.research=function(c)
	local e=c.e;local job=e.researchJob;local p=if job then math.clamp(job.elapsed/math.max(1,job.seconds),0,1) else 0
	local def=if job then EmpireConfig.find(EmpireConfig.RESEARCH,job.id) else nil
	return if job then "RESEARCH ACTIVE" else "RESEARCH · IDLE",string.format("Study  %s\nProgress  %.1f%%\nResearch points  %s\nProduction  %.1f points/s\n%s",if def then def.name else if job then job.id else "No active study",p*100,Format.compact(e.points),EmpireMath.bonuses(e).points,if job then "Better architecture helps your next model." else "Start a study in Lab → Research."),c.footer,p
end
P.design=function(c)
	local d=c.d;local vram=ModelMath.fleet(d.gpus).vram;local lines={}
	for _,size in ModelConfig.SIZES do
		local research=size.id=="s7b" and not d.empire.research.frontier
		local state=if size.vram>vram then string.format("needs %d GB more%s",size.vram-vram,if research then " + Frontier" else "") elseif research then "needs Frontier research" else "fits"
		table.insert(lines,string.format("%s  ·  %d GB VRAM  ·  %s",size.label,size.vram,state))
	end
	table.insert(lines,"Choose SIZE + FOCUS + RECIPE · good data decides quality")
	return "MODEL ARCHITECTURE",table.concat(lines,"\n"),guidance(d),0
end
P.evaluation=function(c)
	local m=Journey.latest(c.d);if not m then return "MODEL EVALUATION","No trained model yet.\nTrain a model, then compare its six benchmark scores here.",c.footer,0 end
	return "EVALUATION / "..title(m),string.format("Reasoning %.1f   Coding %.1f\nMath %.1f          Creativity %.1f\nKnowledge %.1f  Reliability %.1f\nOverall %.1f\n%s",m.stats.reasoning or 0,m.stats.coding or 0,m.stats.math or 0,m.stats.creativity or 0,m.stats.knowledge or 0,m.stats.reliability or 0,m.overall,if m.status=="trained" then "READY FOR RELEASE" else string.upper(m.status)),c.footer,math.min(1,m.overall/100)
end
P.growth=function(c)
	local s,d,e=c.s,c.d,c.e
	local accounts,retainer=accountsOf(e)
	return "DEPLOYMENT / CUSTOMERS",string.format("Users  %s\nRevenue  %s\nBusiness clients  %d · %s/day\nLive releases  %d\nModel → pricing → target → marketing → launch",Format.compact(s.live.users),Format.perDay(s.live.revenue),#accounts,money(retainer),d.stats.modelsReleased),c.footer,0
end
P.deployment=P.growth
P.milestones=function(c)
	local d=c.d
	return "COMPANY MILESTONES",string.format("Models trained  %d\nModels launched  %d\nBest benchmark  %.1f\nTotal revenue  %s\nYour next generation starts here.",d.stats.modelsTrained,d.stats.modelsReleased,d.stats.bestOverall,Format.money(d.stats.totalRevenue)),c.company,0
end
P.history=function(c)
	local d=c.d;local lines={}
	for i=math.max(1,#d.modelOrder-4),#d.modelOrder do local m=d.models[d.modelOrder[i]];if m then table.insert(lines,title(m).." / "..m.status.." / "..string.format("%.1f",m.overall or 0)) end end
	return "MODEL HISTORY",if #lines>0 then table.concat(lines,"\n") else "Your first trained model starts the story.",c.company,0
end
P.journey=function(c)
	local flow=Journey.progress(c.d)
	return "BUILD YOUR FIRST AI",string.format("%d / 7  /  %s\n%s\nDATA → GPU → MODEL → TRAIN\nEVALUATE → RELEASE → GROW",flow.index,string.upper(flow.step.title),flow.step.body),guidance(c.d),(flow.index-1)/7
end
local function overview(c: Ctx,header: string): (string,string,string,number)
	local s,d=c.s,c.d;local best=Journey.latest(d)
	local body=string.format("Users %s   /   Revenue %s\nTeam %d    /    GPUs %d\nBest AI %.1f   /   Rank %s\nAsset value %s  /  Total revenue %s\n%s",Format.compact(s.live.users),Format.perDay(s.live.revenue),EmpireMath.staff(d.empire),gpuCount(d),d.stats.bestOverall,rankOf(s),Format.money(Service.assetValue(d)),Format.money(d.stats.totalRevenue),if d.training then "Training "..title(d.models[d.training.modelId]) else title(best))
	return header,body,"Live company data / "..(if s.live.rankings then s.live.rankings.status else "Rankings loading"),0
end
P.lobby=function(c) return overview(c,string.upper(c.company)) end
P.founder=function(c) return overview(c,"FOUNDER / COMPANY CONTROL") end
P.boardroom=function(c)
	-- The topic only shows while the boardroom seats are actually in use.
	local _,_,used,_,topic=meetingInfo(c,"Boardroom")
	if used>0 and not topic then local t=attr(c.office,"MeetingTopic");topic=if typeof(t)=="string" then words(t) else nil end
	return overview(c,if used>0 then string.upper(topic or "Board meeting") else "COMPANY REVIEW")
end

-- Reception (G_LOBBY): today's visitors, applicants and trips; the guest-house reception (H0_LOBBY) shows its guests
P.reception=function(c)
	local s,e=c.s,c.e;local campus=s.live.campus
	local trips=tripsOf(s)
	if c.entry and typeof(c.entry.roomId)=="string" and string.sub(c.entry.roomId,1,3)=="H0_" then
		local guests=attr(c.office,"HotelGuests");local rooms=attr(c.office,"HotelRooms")
		local hosted={}
		for _,t in trips do if t.hosted then local cl=Ops.client(t.client);table.insert(hosted,if cl then cl.name else tostring(t.client)) end end
		local g=Ops.GUEST
		local lines={
			string.format("Rooms %d · guests tonight %d",tonumber(rooms) or g.rooms,tonumber(guests) or Ops.hotelGuests(e)),
			if #hosted>0 then "Client teams in house  "..table.concat(hosted,", ") else "No client team in house right now",
			string.format("Outside guests %d rooms · %s per night",math.floor(g.rooms*g.occupancy+.5),money(g.rate)),
			string.format("Company day %d · %s",Ops.day(e),hourText(Ops.hour(workspace:GetServerTimeNow()))),
		}
		return "GUEST HOUSE · RECEPTION",table.concat(lines,"\n"),"Client teams of hosted pilots stay two nights",0
	end
	local present,total=0,0
	for _,p in presenceOf(e) do total+=p.total;present+=p.present end
	local applicants,waiting=0,0
	for _,a in e.applicants or {} do if a.st=="new" then applicants+=1 else waiting+=1 end end
	local lines={
		string.format("Visitors in the building  %d  ·  guest cards %d",if c.cache then c.cache.visitors else 0,if campus and campus.passes then #campus.passes else 0),
		string.format("Day %d · %s · team %d / %d in today",Ops.day(e),hourText(Ops.hour(workspace:GetServerTimeNow())),present,total),
		string.format("Candidates in the lounge %d · applications %d",waiting,applicants),
	}
	if #trips==0 then table.insert(lines,"Trips today  nobody is travelling")
	else
		for i=1,math.min(3,#trips) do table.insert(lines,"Trip  "..tripShort(trips[i])) end
		if #trips>3 then table.insert(lines,string.format("+ %d more trips",#trips-3)) end
	end
	local accounts=accountsOf(e)
	table.insert(lines,string.format("Business clients %d · hosted visits %d",#accounts,typeof(e.deals)=="table" and e.deals.hosted or 0))
	return "WELCOME TO "..string.upper(c.company),table.concat(lines,"\n"),"Café & showroom open to all · cards pass the speed gates",0
end
P.directory=function(c)
	local lift=if c.office then liftState(c.office) else nil;local lines={}
	for level=Plan.roofLevel(c.tier),-1,-1 do
		table.insert(lines,Plan.floorTitle(c.tier,level)..(if lift and lift.level==level then "   ← lift" else ""))
	end
	local here=if c.entry and typeof(c.entry.level)=="number" then "You are on "..Plan.floorTitle(c.tier,c.entry.level) else "Lift and stairs behind the atrium"
	return "BUILDING DIRECTORY",table.concat(lines,"\n"),here,0
end
P.showroom=function(c)
	local s,d=c.s,c.d;local released={}
	for _,id in d.modelOrder do local m=d.models[id];if m and m.release and (m.status=="live" or m.status=="retired") then table.insert(released,m) end end
	if #released==0 then return "MODEL SHOWROOM","No model released yet.\nTrain, evaluate and release your first model in the Lab;\nit will be presented here with its live users.",c.company,0 end
	local live=0;for _,m in released do if m.status=="live" then live+=1 end end
	local lines={string.format("Portfolio  %d released  ·  %d live",#released,live)}
	for i=#released,math.max(1,#released-2),-1 do
		local m=released[i]
		table.insert(lines,if m.status=="live" then string.format("%s · live · %.1f · %s users",title(m),m.overall or 0,Format.compact(usersOf(s,m))) else string.format("%s · %s · %.1f",title(m),m.status,m.overall or 0))
	end
	local ranked=table.clone(released);table.sort(ranked,function(a,b)return (a.overall or 0)>(b.overall or 0) end)
	local a,b=ranked[1],ranked[2]
	if b then
		table.insert(lines,string.format("Best two  %s %.1f  vs  %s %.1f",title(a),a.overall or 0,title(b),b.overall or 0))
		table.insert(lines,benchmarks(a).."  /  "..benchmarks(b))
	else table.insert(lines,"Release a second model to compare benchmarks.") end
	return "MODEL SHOWROOM",table.concat(lines,"\n"),"R reason · C code · M math · Cr creative · K know · Rl reliable",if a then math.min(1,(a.overall or 0)/100) else 0
end
-- B2B clients (CORE_SPEC 3.2): accounts with their retainer, trips under way, the best lead
P.customers=function(c)
	local s,e=c.s,c.e;local lines={}
	local accounts,retainer=accountsOf(e)
	local limit=Ops.accountLimit(e)
	local ops=if typeof(s.live.ops)=="table" then s.live.ops else {}
	if #accounts==0 then
		table.insert(lines,"No business client yet.")
		table.insert(lines,"Your sales team visits clients by itself (08:00–15:00);")
		table.insert(lines,"a signed client pays a pilot fee, then every day.")
	else
		table.insert(lines,string.format("Accounts %d / %d · %s/day",#accounts,limit,money(retainer)))
		for i=1,math.min(4,#accounts) do
			local a=accounts[i]
			table.insert(lines,string.format("%s · %s/day · %s",a.client.name,money(a.client.retainer),if a.acc.renewing then "check-in under way" else "until day "..endDay(e,tonumber(a.acc.expires) or 0)))
		end
		if #accounts>4 then table.insert(lines,string.format("+ %d more accounts",#accounts-4)) end
	end
	local trips=tripsOf(s)
	if #trips>0 then table.insert(lines,"On the road  "..tripShort(trips[1])..(if #trips>1 then string.format(" + %d",#trips-1) else "")) end
	local d2=e.deals;local bestLead,bestTrust=nil,-1
	if typeof(d2)=="table" and typeof(d2.trust)=="table" then
		for id,t in d2.trust do local cl=Ops.client(id);if cl and (tonumber(t) or 0)>bestTrust and not (typeof(d2.accounts)=="table" and d2.accounts[id]) then bestTrust=tonumber(t) or 0;bestLead=cl end end
	end
	if bestLead then table.insert(lines,string.format("Best lead  %s · trust %d%%",bestLead.name,math.floor(math.min(1,bestTrust)*100))) end
	table.insert(lines,string.format("Signed %d · lost %d · retainers %s",typeof(d2)=="table" and d2.signed or 0,typeof(d2)=="table" and d2.lost or 0,Format.perDay((tonumber(ops.b2b) or 0)/60)))
	return "BUSINESS CLIENTS",table.concat(lines,"\n"),c.company,math.clamp(#accounts/math.max(1,limit),0,1)
end
P.product=function(c)
	local e=c.e;local job=e.projectJob;local lines={};local published,delivered=0,0
	for _,id in e.projectOrder do local item=e.projects[id];if item then
		if item.status=="published" then published+=1 end;if item.delivered then delivered+=1 end
	end end
	if #e.projectOrder==0 then return "PRODUCT STUDIO","No studio projects yet.\nBuild a website, online shop, game companion or\noffice automation with your model in Studio.",c.company,0 end
	table.insert(lines,string.format("Projects  %d  ·  %d published  ·  %d delivered",#e.projectOrder,published,delivered))
	local progress=0
	if job then
		local item=e.projects[job.id];progress=math.clamp(job.done/math.max(1,job.total),0,1)
		table.insert(lines,string.format("Building  %s · %.0f%% · quality %.1f",if item then item.name else "project",progress*100,if item then item.quality or 0 else 0))
	else table.insert(lines,"No project building · compute is free for training") end
	for i=#e.projectOrder,math.max(1,#e.projectOrder-3),-1 do
		local item=e.projects[e.projectOrder[i]]
		if item and (not job or item.id~=job.id) then
			local kind=StudioConfig.find(StudioConfig.KINDS,item.kind)
			table.insert(lines,string.format("%s · %s · %s · q %.1f",tostring(item.name),if kind then kind.name else tostring(item.kind),tostring(item.status),item.quality or 0))
		end
	end
	return "PRODUCT STUDIO",table.concat(lines,"\n"),c.company,progress
end
P.hr=function(c)
	local e=c.e;local b=EmpireMath.bonuses(e);local staff=EmpireMath.staff(e);local stage=Ops.stageIndex(e);local cap=EmpireConfig.OFFICES[stage].staff
	local lines={string.format("Team  %d / %d desks  ·  %d operations staff",staff,cap,Ops.opsPosts(e))}
	local vacation,sick=0,0
	local today=presenceOf(e)
	for _,role in EmpireConfig.ROLES do
		local p=today[role.id];local here=p.present
		vacation+=p.vacation;sick+=p.sick
		table.insert(lines,string.format("%s  %d / %d desks  ·  %d in today",if string.sub(role.name,-5)=="Sales" then role.name else role.name.."s",e.employees[role.id] or 0,Ops.seats(e,role.id),here))
	end
	table.insert(lines,string.format("Today  %d on vacation · %d sick · morale %d%%",vacation,sick,math.floor(Ops.morale(e)*100+.5)))
	table.insert(lines,"Wages  "..Format.money(b.wage*Ops.DAY).."/day"..(if Ops.apprenticeCount(e)>0 then string.format("  ·  %d apprentices",Ops.apprenticeCount(e)) else ""))
	local nextOffice=EmpireConfig.OFFICES[stage+1]
	local hint=if staff<cap then string.format("%d desks free · %s",cap-staff,if Ops.hrSettings(e) then "HR hires automatically" else "hire in Team → Staff")
		elseif nextOffice then string.format("All desks filled · %s adds %d desks (%s)",nextOffice.name,nextOffice.staff-cap,Format.money(nextOffice.price))
		else "All desks filled in the largest headquarters"
	return "PEOPLE & COMPANY",table.concat(lines,"\n"),hint,math.clamp(staff/math.max(1,cap),0,1)
end
P.security=function(c)
	if not c.office or not c.cache then return "CAMPUS SECURITY","Live building data appears once the headquarters is online.",c.company,0 end
	local st=securityState(c.office,c.cache);local lift=st.lift
	local outOfService=typeof(lift.state)=="string" and string.upper(lift.state)=="OUT_OF_SERVICE"
	local attention=st.locked>0 or outOfService
	local lines={}
	if st.known and st.doors>0 then
		table.insert(lines,string.format("Doors  %d  ·  %d moving or open  ·  %d locked",st.doors,st.open,st.locked))
		-- Compute Operations (G) and the Data Hall (B1) share the compute access class.
		table.insert(lines,if st.computeOpen>0 then string.format("Compute areas  %d door open for staff passing",st.computeOpen) else "Compute Operations & Data Hall doors closed")
	else table.insert(lines,"Door status not available yet") end
	table.insert(lines,liftText(c.tier,lift))
	table.insert(lines,string.format("Cameras  %d channels live",st.cameras))
	table.insert(lines,string.format("Visitors in the building  %d",c.cache.visitors))
	return if attention then "SECURITY · ATTENTION" else "SECURITY · ALL CLEAR",table.concat(lines,"\n"),if st.locked>0 then "Lockdown active · exits keep working" else "Founder security desk · live",0
end
P.vault=function(c)
	local d=c.d;local lines={}
	for i=#d.modelOrder,math.max(1,#d.modelOrder-4),-1 do
		local m=d.models[d.modelOrder[i]]
		if not m then continue end
		local running=d.training and d.training.modelId==m.id
		table.insert(lines,if running then title(m).." · "..(trainingLine(d) or "training") else string.format("%s · %s · %.1f · %s",title(m),m.status,m.overall or 0,benchmarks(m)))
	end
	if #lines==0 then return "MODEL VAULT · CONFIDENTIAL","The vault is empty.\nEvery trained model version is archived here.",c.company,0 end
	return "MODEL VAULT · CONFIDENTIAL",table.concat(lines,"\n"),"R reason · C code · M math · Cr creative · K know · Rl reliable",0
end
P.secretlab=function(c)
	local d,e=c.d,c.e;local job=e.researchJob;local b=EmpireMath.bonuses(e)
	local unlocked={};for _,r in EmpireConfig.RESEARCH do if e.research[r.id] then table.insert(unlocked,r.name) end end
	local nextDef=nil
	for _,r in EmpireConfig.RESEARCH do if not e.research[r.id] and (not r.prereq or e.research[r.prereq]) and not (job and job.id==r.id) then nextDef=r;break end end
	local p=if job then math.clamp(job.elapsed/math.max(1,job.seconds),0,1) else 0
	local def=if job then EmpireConfig.find(EmpireConfig.RESEARCH,job.id) else nil
	local lines={
		if job then string.format("Active  %s · %.0f%% · %s left",if def then def.name else job.id,p*100,Format.duration(job.seconds-job.elapsed)) else "No study running in the lab",
		string.format("Unlocked %d / %d  %s",#unlocked,#EmpireConfig.RESEARCH,if #unlocked>0 then table.concat(unlocked,", ") else "none yet"),
		if b.core>0 or b.reliability>0 then "Next models gain "..researchBonuses({core=b.core,reliability=b.reliability,serving=1}).."." else "Next models train without architecture bonuses yet.",
		string.format("Research runs at %.1f points/s with %s banked.",b.points,Format.compact(e.points)),
		if nextDef then string.format("Next breakthrough: %s (%d points).",nextDef.name,nextDef.points) else "Every known research project is complete.",
	}
	if d.stats.bestOverall>0 then table.insert(lines,string.format("Best model so far: %.1f overall.",d.stats.bestOverall)) end
	return "PRIVATE RESEARCH",table.concat(lines,"\n"),"Founder only · not shown anywhere else",p
end
P.meeting=function(c)
	local room,seats,used,people,topic=meetingInfo(c)
	local name=if c.entry and c.entry.roomName then c.entry.roomName else words(room)
	if used==0 then return string.upper(name),if seats>0 then string.format("Free\n%d seats · no meeting running",seats) else "Free\nNo meeting running",c.company,0 end
	if not topic then local t=attr(c.office,"MeetingTopic");topic=if typeof(t)=="string" then words(t) else "Team meeting" end
	local untilTime=attr(c.office,"MeetingUntil");local now=workspace:GetServerTimeNow()
	-- MeetingUntil is only trusted when it is a server timestamp (StaffService clock may differ).
	local ends=if typeof(untilTime)=="number" and untilTime>1e6 and untilTime>now then string.format(" · ends in %d min",math.ceil((untilTime-now)/60)) else ""
	return string.upper(name),string.format("In use · %s\n%d of %d seats taken%s\n%s",topic or "Team meeting",used,seats,ends,table.concat(people,", ")),c.company,math.clamp(used/math.max(1,seats),0,1)
end
P.cafe=function(c)
	local campus=c.e.campus;local lines={}
	for _,def in CampusConfig.SNACKS do table.insert(lines,string.format("%s  %s  ·  walk boost %d s",def.name,Format.money(def.price),def.seconds)) end
	table.insert(lines,string.format("Retail level %d / 4  ·  %s sales  ·  %s net",campus.retailLevel,Format.int(campus.retailSales),Format.money(campus.retailRevenue)))
	return "HOUSE KITCHEN · MENU",table.concat(lines,"\n"),"Open to visitors · pay at the counter",math.clamp(campus.retailLevel/4,0,1)
end
P.fleet=function(c)
	local campus=c.e.campus;local lines={};local owned=0
	for _,car in CampusConfig.CARS do
		local has=campus.cars[car.id]==true;if has then owned+=1 end
		table.insert(lines,string.format("%s  ·  %s  ·  %d studs/s",car.name,if campus.selectedCar==car.id then "selected" elseif has then "owned" else Format.money(car.price),car.speed))
	end
	return "COMPANY FLEET",table.concat(lines,"\n"),"Collect a car at the fleet desk or in Campus → Fleet",owned/math.max(1,#CampusConfig.CARS)
end
-- Fleet office (B1_FLEET): leased field cars, trips on the road, drivers, the company jet
P.operations=function(c)
	local s,e=c.s,c.e;local stage=Ops.stageIndex(e)
	local reps=Ops.fieldReps(e);local trips=tripsOf(s)
	local drivers=if stage>=Ops.DRIVER.more then 2 elseif stage>=Ops.DRIVER.from then 1 else 0
	local lines={
		string.format("Field cars leased %d · %s/day each",reps,money(Ops.FLEET_LEASE)),
		string.format("Drivers %d · %s/day each",drivers,money(Ops.DRIVER.wage)),
	}
	if #trips==0 then table.insert(lines,"On the road  nobody")
	else for i=1,math.min(3,#trips) do table.insert(lines,"On the road  "..tripShort(trips[i])) end end
	table.insert(lines,if e.jet==true then "Company jet  in the airport hangar · 2 pilots" elseif stage>=Ops.JET.stage then "Company jet  not bought ("..money(Ops.JET.price)..")" else "Company jet  from the "..EmpireConfig.OFFICES[Ops.JET.stage].name)
	return "FLEET OPERATIONS",table.concat(lines,"\n"),"Cars for field reps · the boss's cars in Campus → Fleet",math.clamp(#trips/math.max(1,reps),0,1)
end
P.platform=function(c)
	local s,d,e=c.s,c.d,c.e;local live=liveModels(d)
	if #live==0 then return "PLATFORM OPERATIONS","No model is serving yet.\nRelease a trained model in the Lab to go live.",c.company,0 end
	local lines={
		string.format("Live models  %d  ·  %s users",#live,Format.compact(s.live.users)),
		string.format("Revenue %s  ·  costs %s",Format.perDay(s.live.revenue),Format.money(s.live.cost*Ops.DAY).."/day"),
	}
	for i=1,math.min(3,#live) do
		local m=live[i];local r=s.live.perModel and s.live.perModel[m.id]
		table.insert(lines,string.format("%s · %s users · %s",title(m),Format.compact(usersOf(s,m)),Format.perDay(if r then r.revenue or 0 else 0)))
	end
	local accounts=accountsOf(e)
	local reserved=if typeof(s.live.compute)=="table" then tonumber(s.live.compute.reserved) or 0 else 0
	table.insert(lines,string.format("Business clients  %d · %.1f compute units reserved",#accounts,reserved))
	if d.training and e.projectJob then table.insert(lines,string.format("Training uses %.0f%% of compute while a project builds",e.infrastructure.trainingShare*100)) end
	return "PLATFORM OPERATIONS",table.concat(lines,"\n"),"All live models serving normally",0
end
P.prototype=function(c)
	local d,e=c.d,c.e;local b=EmpireMath.bonuses(e);local vram=ModelMath.fleet(d.gpus).vram
	local m=Journey.latest(d,true);local lines={}
	if m then
		local size=sizeOf(m.sizeId)
		table.insert(lines,string.format("%s · %s · %s · overall %.1f",title(m),if size then size.label else "?",focusLabel(m.focusId),m.overall or 0))
		table.insert(lines,"Trained, not released · evaluate and release in the Lab")
		if size then table.insert(lines,string.format("%s needs %d GB VRAM · you have %d GB",size.label,size.vram,vram)) end
	else
		table.insert(lines,"No unreleased prototype right now.")
		table.insert(lines,"Trained models wait here until you release them.")
	end
	local _,nextSize=vramFit(d)
	table.insert(lines,if nextSize then string.format("Next size %s needs %d GB (%d GB more)",nextSize.label,nextSize.vram,nextSize.vram-vram) else "Your VRAM fits every model size")
	table.insert(lines,"Research  "..researchBonuses(b))
	table.insert(lines,string.format("Training speed x%.2f with team and research",b.speed))
	return "PROTOTYPE LAB",table.concat(lines,"\n"),guidance(d),0
end
P.secondary=function(c)
	local stock=ModelMath.dataSummary(c.d.data);local wf=c.s.live.workforce
	return "COMPANY OS / TEAM",string.format("Team  %d specialists\nData  %s tokens\nCompany time  %s",EmpireMath.staff(c.e),Format.tokens(stock.total),hourText(if wf then wf.hour else nil)),c.company,0
end

local TASK_KIND: {[string]:string}={
	CleanDataset="data",CheckQuality="data",MonitorPipeline="data",WriteCode="engineering",MonitorTraining="training",
	RunExperiment="research",ArchitectureStudy="research",AnalyzeModel="evaluation",ReviewModel="evaluation",
	AnalyzeMarket="growth",CheckCustomers="growth",PlanLaunch="growth",InspectServer="compute",InspectHardware="compute",
}
-- kind: LiveScreen kind; w: workstation Model of the screen (or nil); screen: the screen Part.
function Service.presentation(s: any,kind: string,w: Model?,screen: BasePart?): (string,string,string,number)
	local d=s.data;local company=if d.company then d.company.name else "Your Company"
	local office=if screen then screen:FindFirstAncestor("Office") else nil
	local cache=if office and office:IsA("Model") then scan(office) else nil
	local entry=if cache and screen then cache.byPart[screen] else nil
	local footer=FOOTER
	if w and w:GetAttribute("OccupiedBy") then
		if (tonumber(w:GetAttribute("LoginUntil")) or 0)>workspace:GetServerTimeNow() then return "EMPLOYEE LOGIN",tostring(w:GetAttribute("EmployeeName") or ""),company,0 end
		local taskId=w:GetAttribute("Software")
		if kind=="secondary" then
			local stock=ModelMath.dataSummary(d.data);local wf=s.live.workforce
			return "COMPANY OS / TEAM",string.format("%s\nTask  %s\nWorkstation  %s\nData  %s tokens\nCompany time  %s",tostring(w:GetAttribute("EmployeeName") or "Employee"),if typeof(taskId)=="string" then words(taskId) else "Working",tostring(w:GetAttribute("WorkstationId") or ""),Format.tokens(stock.total),hourText(if wf then wf.hour else nil)),company,0
		end
		if typeof(taskId)=="string" and TASK_KIND[taskId] then kind=TASK_KIND[taskId] end
		footer=tostring(w:GetAttribute("EmployeeName") or "Employee").." / "..(if typeof(taskId)=="string" then words(taskId) else "Working")
	elseif w and w:GetAttribute("WorkstationType")=="Computer" then
		return company,"WORKSTATION LOCKED\nAvailable for your team's next task.\nUse this terminal to open Company OS.","SECURE / EMPLOYEE CARD",0
	end
	local tier=if cache then cache.tier else Plan.tierForOffice(d.empire.office)
	local ctx: Ctx={s=s,d=d,e=d.empire,w=w,screen=screen,office=if office and office:IsA("Model") then office else nil,cache=cache,entry=entry,tier=tier,company=company,footer=footer}
	local present=P[kind]
	if present then return present(ctx) end
	-- Unknown kinds show the company overview rather than an empty screen.
	return overview(ctx,company)
end
local function write(s: any,entry: any,time: number)
	local p: BasePart=entry.part
	local gui=p:FindFirstChild("Desktop");if not gui then return end
	local w: Model?=entry.w
	local kind=entry.kind;local header: string,body: string,footer: string,fill: number
	if w and w:GetAttribute("OccupiedBy") and (tonumber(w:GetAttribute("LoginUntil")) or 0)>time then
		header="EMPLOYEE LOGIN";body=tostring(w:GetAttribute("EmployeeName") or "");footer="Company OS / secure session";fill=.15
	else header,body,footer,fill=Service.presentation(s,kind,w,p) end
	local texts: {[string]:string}={Header=header,Body=body,Footer=footer}
	for name,text in texts do
		local label=gui:FindFirstChild(name)
		if label and label:IsA("TextLabel") and label.Text~=text then label.Text=text end
	end
	local track=gui:FindFirstChild("ProgressTrack");local bar=if track then track:FindFirstChild("Fill") else nil
	if bar and bar:IsA("GuiObject") then
		local size=UDim2.fromScale(math.clamp(fill,0,1),1);if bar.Size~=size then bar.Size=size end
	end
	local t=s.data.training
	local alert=t~=nil and t.event~=nil and t.event.pending==true and (ALERT_KINDS[kind]==true or (w~=nil and w:GetAttribute("Software")=="MonitorTraining"))
	if p:GetAttribute("TrainingAlert")~=alert then p:SetAttribute("TrainingAlert",alert) end
end
function Service.tick(dt: number)
	clock+=dt;if clock<1 then return end;clock=0
	local positions={};local players={}
	for _,s in Session.all() do if not s.closed and s.player.Character and s.player.Character.PrimaryPart then
		local position=s.player.Character.PrimaryPart.Position;table.insert(positions,position);table.insert(players,{userId=s.userId,position=position})
	end end
	local time=workspace:GetServerTimeNow()
	for _,p in Plot.all() do if p.office and p.owner then
		local s=Session.get(p.owner);if not s or s.closed then continue end
		local cache=scan(p.office)
		-- Visitors: other players standing inside this headquarters right now.
		local visitors=0
		if cache.cf then for _,other in players do
			if other.userId~=s.userId and Plan.inside(cache.tier,cache.cf:PointToObjectSpace(other.position)) then visitors+=1 end
		end end
		cache.visitors=visitors
		for _,entry in cache.screens do
			local screen=entry.part
			local distance=proximity(screen.Position,positions)
			if screen.Parent and distance<250 then local interval=if distance<120 then 1 else 6
				if entry.next<=time then write(s,entry,time);entry.next=time+interval end
			end
		end
		local t=s.data.training
		p.office:SetAttribute("Training",t~=nil);p.office:SetAttribute("TrainingAlert",t~=nil and t.event~=nil and t.event.pending==true)
	end end
end
return Service
