--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Shared=ReplicatedStorage.Shared
local Config=require(Shared.Config.StudioConfig)
local Math=require(Shared.StudioMath)
local ModelMath=require(Shared.ModelMath)
local GameConfig=require(Shared.Config.GameConfig)
local Remote=require(script.Parent.Parent.Lib.Remote)
local Guard=require(script.Parent.Parent.Lib.Guard)
local TextFilter=require(script.Parent.Parent.Lib.TextFilter)
local Session=require(script.Parent.SessionService)
local Economy=require(script.Parent.EconomyService)
local NPC=require(script.Parent.NPCService)
local Service={gallery={} :: {any}}
-- CORE_SPEC 3.4: briefs pay once per brief per game day of play (empire.seconds / 1200), reward x STUDIO_SCALE
Service.STUDIO_SCALE=0.5
Service.DAY=1200
local function reward(brief: any): number return math.floor(brief.reward*Service.STUDIO_SCALE) end
local function source(data: any,modelId: any): (any,string?)
	if modelId=="licensed" then
		local sub=data.empire.subscriptions
		if not sub.expires or sub.expires<=os.time() then return nil,nil end
		return sub.stats or {coding=sub.score,creativity=sub.score,reliability=60,reasoning=sub.score},sub.name
	end
	local id=Guard.id(modelId);local m=if id then data.models[id] else nil
	-- stall fix: a model retired by a new version hands its projects to the live successor (<= 8 hops)
	local hops=0
	while m and m.status=="retired" and m.replacedBy and hops<8 do m=data.models[m.replacedBy];hops+=1 end
	if not m or (m.status~="trained" and m.status~="live") then return nil,nil end
	return m.stats,m.name
end
local function build(s: any,p: any): any
	local e=s.data.empire
	if e.projectJob then return {ok=false,err="PROJECT_ACTIVE"} end
	if #e.projectOrder>=30 then return {ok=false,err="PROJECT_LIMIT"} end
	local kind=Config.find(Config.KINDS,p.kind);local style=Config.find(Config.STYLES,p.style)
	local title=Guard.text(p.name,3,28)
	local brief=if p.briefId then Config.find(Config.BRIEFS,p.briefId) else nil
	if not kind or not style or not title or (p.briefId and not brief) or (brief and brief.kind~=kind.id) then return {ok=false,err="BAD_INPUT"} end
	local stats,modelName=source(s.data,p.modelId)
	if not stats then return {ok=false,err="NO_PROJECT_MODEL"} end
	local filtered=TextFilter.forBroadcast(title,s.userId)
	if filtered==nil then return {ok=false,err="FILTER_DOWN"} end
	if filtered~=title then return {ok=false,err="NAME_FILTERED"} end
	-- Text filtering yields, so re-check every mutable precondition before charging.
	if s.closed then return {ok=false,err="LOADING"} end
	if e.projectJob then return {ok=false,err="PROJECT_ACTIVE"} end
	if #e.projectOrder>=30 then return {ok=false,err="PROJECT_LIMIT"} end
	stats,modelName=source(s.data,p.modelId)
	if not stats then return {ok=false,err="NO_PROJECT_MODEL"} end
	if not Economy.spend(s,kind.cost,"studio") then return {ok=false,err="NO_MONEY"} end
	local id="project-"..game:GetService("HttpService"):GenerateGUID(false)
	local item={id=id,name=title,kind=kind.id,style=style.id,briefId=if brief then brief.id else nil,
		status="building",quality=Math.quality(stats,kind),content=Math.content(title,kind.id,p.briefId),
		modelName=modelName,sourceId=p.modelId,createdAt=os.time(),visitors=0,revenueTotal=0,delivered=false}
	e.projects[id]=item;table.insert(e.projectOrder,id)
	e.projectJob={id=id,total=kind.work,done=0}
	Session.markDirty(s);return {ok=true,projectId=id}
end
local function project(s: any,p: any): any
	local id=Guard.id(p.projectId)
	return if id then s.data.empire.projects[id] else nil
end
local function publish(s: any,p: any): any
	local item=project(s,p)
	if not item or item.status~="ready" then return {ok=false,err="PROJECT_NOT_READY"} end
	item.status="published";Session.markDirty(s);return {ok=true}
end
local function deliver(s: any,p: any): any
	local item=project(s,p)
	if not item or (item.status~="ready" and item.status~="published") then return {ok=false,err="PROJECT_NOT_READY"} end
	local brief=Config.find(Config.BRIEFS,item.briefId)
	if not brief or item.quality<brief.minimum then return {ok=false,err="PROJECT_QUALITY"} end
	local day=math.floor((tonumber(s.data.empire.seconds) or 0)/Service.DAY)
	if item.delivered or s.data.empire.deliveries[brief.id]==day then return {ok=false,err="ALREADY_DONE"} end
	item.delivered=true;s.data.empire.deliveries[brief.id]=day
	Economy.applyFlow(s,reward(brief),0,"studio");s.data.empire.xp+=100
	Session.markDirty(s);return {ok=true,reward=reward(brief)}
end
local function cancel(s: any,_p: any): any
	local e=s.data.empire
	if not e.projectJob then return {ok=false,err="PROJECT_NOT_READY"} end
	local item=e.projects[e.projectJob.id]
	if item then item.status="cancelled" end
	e.projectJob=nil;Session.markDirty(s);return {ok=true}
end
local function archive(s: any,p: any): any
	local item=project(s,p)
	if not item or item.status=="building" then return {ok=false,err="PROJECT_NOT_READY"} end
	local e=s.data.empire;local index=table.find(e.projectOrder,item.id)
	if index then table.remove(e.projectOrder,index) end
	e.projects[item.id]=nil;Session.markDirty(s);return {ok=true}
end
function Service.tick(s: any,dt: number)
	if not s.data.company then return end
	local e=s.data.empire;local job=e.projectJob
	if job then
		local item=e.projects[job.id]
		if not item then e.projectJob=nil
		else
			local stats=source(s.data,item.sourceId)
			if stats then
				local rate=Math.rate(s.data.gpus,e)*(if s.data.training then 1-e.infrastructure.trainingShare else 1)
				job.done=math.min(job.total,job.done+rate*dt)
				if job.done>=job.total then item.status="ready";e.projectJob=nil;Remote.fire(s.player,"Notify","EMPIRE_NOTICE",{text="Project ready: "..item.name}) end
			end
		end
	end
	local revenue=0
	for _,id in e.projectOrder do
		local item=e.projects[id]
		if item and item.status=="published" then
			local rate=math.max(0,item.quality-20)*2/GameConfig.GAME_MONTH_SECONDS
			item.visitors+=item.quality*dt/30;item.revenueTotal+=rate*dt;revenue+=rate
		end
	end
	if revenue>0 then Economy.applyFlow(s,revenue*dt,0,"studio");s.live.revenue+=revenue end
	Session.markDirty(s)
end
function Service.refresh()
	local list={}
	for _, s in Session.all() do
		if not s.closed and s.data.company then
			for _, id in s.data.empire.projectOrder do
				local item=s.data.empire.projects[id]
				if item and item.status=="published" then local copy=table.clone(item);copy.company=s.data.company.name;copy.providerId=s.userId;table.insert(list,copy) end
			end
		end
	end
	for _, s in NPC.sessions do
		if s.portfolio then local copy=table.clone(s.portfolio);copy.company=s.data.company.name;table.insert(list,copy) end
	end
	while #list>36 do table.remove(list) end
	Service.gallery=list
	for _, s in Session.all() do s.live.studio={gallery=list} end
end
function Service.init()
	local limit={burst=2,perSecond=.5,company=true}
	Remote.bind("BuildProject",limit,build);Remote.bind("CancelProject",limit,cancel);Remote.bind("ArchiveProject",limit,archive);Remote.bind("PublishProject",limit,publish);Remote.bind("DeliverProject",limit,deliver)
end
return Service
