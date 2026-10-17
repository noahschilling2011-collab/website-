--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Math=require(ReplicatedStorage.Shared.ArenaMath)
local Remote=require(script.Parent.Parent.Lib.Remote)
local Guard=require(script.Parent.Parent.Lib.Guard)
local Session=require(script.Parent.SessionService)
local NPC=require(script.Parent.NPCService)
local Arena={runs={} :: {[number]:any}}
local lanes={} :: {any}
local function part(parent: Instance,name: string,size: Vector3,x: number,y: number,z: number,color: Color3): Part
	local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=CFrame.new(x-840,y+24,z);p.Anchored=true;p.Color=color;p.Material=Enum.Material.SmoothPlastic;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=parent;return p
end
local function pose(lane: any,cell: any,robot: Model?)
	local x=lane.x+(cell.x-5)*4;local z=lane.z+(cell.z-4)*4
	for _, p in (robot or lane.robot):GetChildren() do
		if p:IsA("BasePart") then local offset=p:GetAttribute("Offset");p.CFrame=CFrame.new(x-840,24,z)*CFrame.Angles(0,cell.yaw or 0,0)*CFrame.new(offset.X,offset.Y,offset.Z) end
	end
end
local function makeRobot(parent: Instance,color: Color3): Model
	local robot=Instance.new("Model");robot.Name="CourierRobot";robot.Parent=parent
	for _,def in {{"Body",2.2,2.4,1.5,0,2.2,0},{"Head",2,1.3,1.4,0,4.1,0},{"EyeL",.3,.25,.08,-.5,4.2,-.73},{"EyeR",.3,.25,.08,.5,4.2,-.73},{"LegL",.7,1.1,.8,-.65,.65,0},{"LegR",.7,1.1,.8,.65,.65,0},{"Package",1.6,1.2,1,0,2,-1.2}} do
		local c=if string.sub(def[1],1,3)=="Eye" then Color3.fromRGB(241,232,208) elseif def[1]=="Package" then Color3.fromRGB(173,128,84) else color
		local p=part(robot,def[1],Vector3.new(def[2],def[3],def[4]),def[5],def[6],def[7],c);p.CanCollide=false;p:SetAttribute("Offset",Vector3.new(def[5],def[6]+.8,def[7]))
	end
	return robot
end
local function run(s: any,p: any): any
	if Arena.runs[s.userId] then return {ok=false,err="ARENA_ACTIVE"} end
	local id=Guard.id(p.modelId);local model=if id then s.data.models[id] else nil
	if not model or (model.status~="trained" and model.status~="live") then return {ok=false,err="BAD_MODEL"} end
	local lane:any=nil
	for _, candidate in lanes do if not candidate.owner then lane=candidate;break end end
	if not lane then return {ok=false,err="ARENA_BUSY"} end
	local plan=Math.route(model.stats,#s.data.empire.arenaHistory+1)
	local peer=NPC.sessions[(#s.data.empire.arenaHistory%math.max(1,#NPC.sessions))+1]
	local rival=if peer then peer.data.models[peer.data.modelOrder[1]] else nil
	local opponent=if rival then {name=peer.data.company.name,score=Math.route(rival.stats,1).score} else {name="House courier",score=130}
	local rivalPlan=Math.route(if rival then rival.stats else {reasoning=35,coding=35,reliability=50,speed=50},1)
	local active={lane=lane,plan=plan,rivalPlan=rivalPlan,duration=math.max(plan.seconds,rivalPlan.seconds),elapsed=0,modelId=model.id,modelName=model.name,opponent=opponent,player=s.player}
	lane.owner=s.userId;Arena.runs[s.userId]=active
	pose(lane,plan.path[1]);pose(lane,rivalPlan.path[1],lane.rivalRobot);Session.markDirty(s)
	return {ok=true,lane=lane.index}
end
function Arena.tick(dt: number)
	for userId,runInfo in Arena.runs do
		local s:any=nil
		for _,candidate in Session.all() do if candidate.userId==userId and not candidate.closed then s=candidate;break end end
		if not s then runInfo.lane.owner=nil;Arena.runs[userId]=nil;continue end
		runInfo.elapsed=math.min(runInfo.duration,runInfo.elapsed+dt)
		local step=math.min(runInfo.elapsed/runInfo.plan.stepSeconds,#runInfo.plan.path-1)
		local index=math.min(#runInfo.plan.path,math.floor(step)+1)
		local a=runInfo.plan.path[index];local b=runInfo.plan.path[math.min(#runInfo.plan.path,index+1)]
		local blend=step%1
		pose(runInfo.lane,{x=a.x+(b.x-a.x)*blend,z=a.z+(b.z-a.z)*blend,yaw=if a~=b then math.atan2(-(b.x-a.x),-(b.z-a.z)) else 0})
		local rivalStep=math.min(runInfo.elapsed/runInfo.rivalPlan.stepSeconds,#runInfo.rivalPlan.path-1)
		local ri=math.min(#runInfo.rivalPlan.path,math.floor(rivalStep)+1)
		local ra=runInfo.rivalPlan.path[ri];local rb=runInfo.rivalPlan.path[math.min(#runInfo.rivalPlan.path,ri+1)]
		pose(runInfo.lane,{x=ra.x+(rb.x-ra.x)*(rivalStep%1),z=ra.z+(rb.z-ra.z)*(rivalStep%1),yaw=if ra~=rb then math.atan2(-(rb.x-ra.x),-(rb.z-ra.z)) else 0},runInfo.lane.rivalRobot)
		if runInfo.elapsed>=runInfo.duration then
			local result={name=runInfo.modelName,score=runInfo.plan.score,moves=runInfo.plan.moves,seconds=math.round(runInfo.plan.seconds*10)/10,
				winner=runInfo.plan.score>=runInfo.opponent.score,opponent=runInfo.opponent.name,opponentScore=runInfo.opponent.score,time=os.time()}
			table.insert(s.data.empire.arenaHistory,1,result)
			while #s.data.empire.arenaHistory>12 do table.remove(s.data.empire.arenaHistory) end
			s.data.empire.arenaBest=math.max(s.data.empire.arenaBest,result.score)
			runInfo.lane.owner=nil;Arena.runs[userId]=nil
			Remote.fire(s.player,"Notify","EMPIRE_NOTICE",{text="Courier test complete: "..tostring(result.score).." points"})
		end
		Session.markDirty(s)
	end
	for _,s in Session.all() do
		local info=Arena.runs[s.userId]
		s.live.arena={active=if info then {model=info.modelName,lane=info.lane.index,progress=info.elapsed/info.duration,moves=info.plan.moves,opponent=info.opponent.name} else nil,
			rivals=NPC.activities}
	end
end
function Arena.init()
	local old=workspace:FindFirstChild("TestGrounds");if old then old:Destroy() end
	local root=Instance.new("Model");root.Name="TestGrounds";root.Parent=workspace
	local cream=Color3.fromRGB(194,192,171);local dark=Color3.fromRGB(44,61,52);local green=Color3.fromRGB(118,155,130)
	part(root,"Walkway",Vector3.new(85,.4,20),-222,.3,-61,cream)
	local terminal=part(root,"ArenaTerminal",Vector3.new(4,4,2),-202,2.5,-59,dark)
	local prompt=Instance.new("ProximityPrompt");prompt.ActionText="Open test arena";prompt.ObjectText="Courier Lab";prompt.MaxActivationDistance=12;prompt:SetAttribute("Public",true);prompt:SetAttribute("App","arena");prompt.Parent=terminal
	for laneIndex=1,3 do
		local lane={index=laneIndex,x=-230,z=-91-(laneIndex-1)*34,owner=nil}
		part(root,"CourseDeck",Vector3.new(42,.5,30),lane.x,.4,lane.z,cream)
		for x=1,Math.WIDTH do for z=1,Math.HEIGHT do
			local px=lane.x+(x-5)*4;local pz=lane.z+(z-4)*4
			if Math.blocked(x,z) then part(root,"MazeBarrier",Vector3.new(3.7,2.6,3.7),px,1.95,pz,dark)
			else part(root,"RouteTile",Vector3.new(3.7,.15,3.7),px,.75,pz,if (x==1 or x==9) and z==4 then green else Color3.fromRGB(166,174,155)) end
		end end
		lane.robot=makeRobot(root,({green,Color3.fromRGB(129,153,172),Color3.fromRGB(182,133,94)})[laneIndex])
		lane.rivalRobot=makeRobot(root,Color3.fromRGB(168,133,102))
		for _, p in lane.rivalRobot:GetChildren() do if p:IsA("BasePart") then local v=p:GetAttribute("Offset");p:SetAttribute("Offset",Vector3.new(v.X+.6,v.Y,v.Z+.6)) end end
		pose(lane,{x=1,z=4});pose(lane,{x=1,z=4},lane.rivalRobot);table.insert(lanes,lane)
	end
	Remote.bind("RunArena",{burst=2,perSecond=.25,company=true},run)
end
return Arena
