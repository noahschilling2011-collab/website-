--!strict
-- One server economy: shared consumer/API demand (MarketMath, CORE_SPEC 3.1) and paid player API access.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local CompanyConfig = require(Shared.Config.CompanyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local MarketConfig = require(Shared.Config.MarketConfig)
local ModelMath = require(Shared.ModelMath)
local MarketMath = require(Shared.MarketMath)
local EmpireMath = require(Shared.EmpireMath)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local HardwareConfig = require(Shared.Config.HardwareConfig)
local Remote = require(script.Parent.Parent.Lib.Remote)
local Guard = require(script.Parent.Parent.Lib.Guard)
local SessionService = require(script.Parent.SessionService)
local Economy = require(script.Parent.EconomyService)
local NPC=require(script.Parent.NPCService)
local Ops=require(Shared.CompanyOps)
local Market = {offers = {} :: {any}, customers = {} :: {any}}
local clock = 0
-- CORE_SPEC 3.2: the server-wide lease auction is removed. Business clients are per company
-- (CompanyOps B2B pipeline: field reps, trips, trust, daily retainers), so players never race for them.
local function all(): {any}
	local list = {}
	for _, s in SessionService.all() do
		if not s.closed and s.data.company then table.insert(list,s) end
	end
	for _, n in NPC.sessions do table.insert(list,n) end
	table.sort(list,function(a,b) return a.userId < b.userId end)
	return list
end
local function seller(id: number): any
	for _, s in all() do if s.userId == id then return s end end
	return nil
end
local function entry(s: any, model: any): any
	return {id=model.id,stats=model.stats,sizeId=model.sizeId,subPrice=model.release.subPrice,
		apiPrice=model.release.apiPrice,market=model.market,target=model.release.target,player=not s.isNPC,company=s.userId}
end
-- Investor Relations pass (ShopService, CORE_SPEC 11.7): own market revenue x INVESTOR_MULTIPLIER after the
-- shares are computed, so it never changes another player's share; never applied to B2B. Required lazily.
local shop: any = nil
local function shopFactor(session: any): number
	if session.isNPC then return 1 end
	if shop == nil then
		local module = script.Parent:FindFirstChild("ShopService")
		shop = if module then (require :: any)(module) else false
	end
	if shop and typeof(shop.revenueMultiplier) == "function" then
		local ok, factor = pcall(shop.revenueMultiplier, session)
		if ok and typeof(factor) == "number" and factor == factor then return factor end
	end
	return 1
end
local function invoice(s: any, text: string, amount: number)
	table.insert(s.data.empire.invoices,1,{time=os.time(),text=text,amount=amount})
	while #s.data.empire.invoices>20 do table.remove(s.data.empire.invoices) end
end
function Market.accessPrice(model: any): number
	return math.max(100,math.floor(model.release.subPrice*100 + model.release.apiPrice*50))
end
local function transfer(buyer: any, provider: any, model: any, fee: number, auto: boolean): boolean
	-- No yielding between the two ledger writes. Prices are server derived, never client supplied.
	if not Economy.spend(buyer,fee,"api") then return false end
	Economy.applyFlow(provider,fee,0,"api")
	buyer.data.empire.subscriptions = {providerId=provider.userId,modelId=model.id,
		provider=provider.data.company.name,name=model.name,score=model.overall,stats=table.clone(model.stats),
		price=fee,expires=os.time()+GameConfig.GAME_MONTH_SECONDS,autoRenew=auto}
	invoice(buyer,"API access: "..model.name,-fee)
	invoice(provider,"API customer: "..buyer.data.company.name,fee)
	SessionService.markDirty(buyer); SessionService.markDirty(provider)
	return true
end
local function buy(buyer: any, payload: any): any
	local providerId = Guard.integer(payload.providerId,-100000003,1e12)
	local modelId = Guard.id(payload.modelId)
	if not providerId or not modelId then return {ok=false,err="BAD_INPUT"} end
	if providerId==0 or providerId==buyer.userId then return {ok=false,err="SELF_PURCHASE"} end
	local sub = buyer.data.empire.subscriptions
	if sub.expires and sub.expires>os.time() then return {ok=false,err="ACCESS_ACTIVE"} end
	local provider = seller(providerId)
	if not provider then return {ok=false,err="SELLER_OFFLINE"} end
	local model = provider.data.models[modelId]
	if not model or model.status~="live" or not model.release then return {ok=false,err="BAD_MODEL"} end
	local fee = Market.accessPrice(model)
	if payload.quotedPrice~=fee then return {ok=false,err="QUOTE_CHANGED"} end
	if not transfer(buyer,provider,model,fee,payload.autoRenew==true) then return {ok=false,err="NO_MONEY"} end
	return {ok=true}
end
local function cancel(buyer: any, _payload: any): any
	buyer.data.empire.subscriptions.autoRenew=false
	SessionService.markDirty(buyer)
	return {ok=true}
end
-- Version age shown on a marketplace offer (client release forecast, CORE_SPEC 7.7): whole OFFER_AGE_STEP
-- seconds, compared lazily (SessionService.LAZY): -8 fit at most over 3600 s, so a 30 s step moves the age
-- penalty by < 0.07 fit points while the offers stay cheap to replicate (CORE_SPEC 11.8).
Market.OFFER_AGE_STEP = 30
function Market.offerAge(market: any): number
	local vage = tonumber(market and market.vage) or 0
	return math.floor(math.max(0, vage) / Market.OFFER_AGE_STEP) * Market.OFFER_AGE_STEP
end
function Market.tickGlobal(dt: number)
	clock += dt
	local offers = {}
	local sessions = all()
	for _, s in sessions do
		for _, id in s.data.modelOrder do
			local m = s.data.models[id]
			if m and m.status=="live" and m.release and m.market then
				table.insert(offers,{providerId=s.userId,company=s.data.company.name,id=id,name=m.name,
					overall=m.overall,stats=m.stats,sub=m.release.subPrice,api=m.release.apiPrice,
					price=Market.accessPrice(m),users=MarketMath.totalUsers(m.market),iterations=m.iterations or 0,
					target=m.release.target,npc=s.isNPC==true,vage=Market.offerAge(m.market)})
			end
		end
		local sub=s.data.empire.subscriptions
		if sub.expires and sub.expires<=os.time() then
			local provider = seller(sub.providerId)
			local model = if provider then provider.data.models[sub.modelId] else nil
			if sub.autoRenew and model and model.status=="live" and Market.accessPrice(model)==sub.price then
				if not transfer(s,provider,model,sub.price,true) then sub.autoRenew=false end
			else sub.autoRenew=false end
		end
	end
	table.sort(offers,function(a,b)
		if a.overall~=b.overall then return a.overall>b.overall end
		if a.providerId~=b.providerId then return a.providerId<b.providerId end
		return a.id<b.id
	end)
	Market.offers=offers
	Market.customers={} -- compatibility: the lease auction is gone (CompanyOps clients are per company)
	for _, s in NPC.sessions do Market.tick(s,dt) end
end
function Market.tick(session: any, dt: number)
	local data = session.data
	local company = data.company
	if not company then return end
	local entries, rivals = {}, {}
	for _, s in all() do
		for _, id in s.data.modelOrder do
			local m = s.data.models[id]
			if m and m.status=="live" and m.release and m.market then
				table.insert(if s==session then entries else rivals,entry(s,m))
			end
		end
	end
	-- stage reach cap, serving capacity (users) and the Growth & Sales reach cap of this company
	local stage=math.clamp(math.floor(tonumber(data.empire.office) or 1),1,#(MarketConfig.STAGE_REACH or {1}))
	local opts={stage=stage,capacity=Ops.capacity(data),reachCap=Ops.reachCap(data,(MarketConfig.STAGE_REACH or {})[stage] or MarketConfig.REACH.max)}
	local live=MarketMath.tick(entries,company.reputation,company.spec,dt,rivals,if #NPC.sessions>0 then {} else nil,opts)
	local b=EmpireMath.bonuses(data.empire)
	local cycle=EmpireConfig.cycle(workspace:GetServerTimeNow())
	local factor=b.revenue*cycle.revenue*shopFactor(session)
	live.revenue*=factor; live.cost*=b.serving*cycle.cost
	for _, r in live.perModel do r.revenue*=factor; r.cost*=b.serving*cycle.cost end
	-- Electricity while serving is distinct from the upfront training electricity budget.
	local fleet=ModelMath.fleet(data.gpus)
	if #entries>0 then live.cost+=fleet.throughput*HardwareConfig.SERVE_POWER end -- electricity of serving (apps request 1)
	live.marketplace={offers=Market.offers,customers=Market.customers}
	-- Merge, never replace: session.live also carries fields other services own (workforce from
	-- StaffService, admin from AdminService, campus, empire, studio, arena, rankings ...).
	local current=session.live :: any
	for key,value in live :: any do current[key]=value end
	Economy.applyFlow(session,live.revenue*dt,live.cost*dt,"market")
	local oldRank=CompanyConfig.rankFor(data.stats.peakUsers)
	data.stats.peakUsers=math.max(data.stats.peakUsers,live.users)
	company.reputation=MarketMath.reputationStep(company.reputation,live.users,data.stats.bestOverall,dt)
	if #entries>0 then SessionService.markDirty(session) end
	local newRank=CompanyConfig.rankFor(data.stats.peakUsers)
	if newRank~=oldRank then Remote.fire(session.player,"Notify","RANK_UP",{rank=newRank}) end
end
function Market.init()
	Remote.bind("BuyModelAccess",{burst=2,perSecond=0.5,company=true},buy)
	Remote.bind("CancelModelAccess",{burst=2,perSecond=0.5,company=true},cancel)
end
return Market
