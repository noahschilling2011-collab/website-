--!strict
-- One server economy: shared demand, monthly business contracts and paid player API access.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local CompanyConfig = require(Shared.Config.CompanyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local MarketConfig = require(Shared.Config.MarketConfig)
local ModelConfig = require(Shared.Config.ModelConfig)
local ModelMath = require(Shared.ModelMath)
local MarketMath = require(Shared.MarketMath)
local EmpireMath = require(Shared.EmpireMath)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local Remote = require(script.Parent.Parent.Lib.Remote)
local Guard = require(script.Parent.Parent.Lib.Guard)
local SessionService = require(script.Parent.SessionService)
local Economy = require(script.Parent.EconomyService)
local NPC=require(script.Parent.NPCService)
local Market = {offers = {} :: {any}, customers = {} :: {any}}
local clock = 0
local businesses = {
	{id="pixel",name="Pixel Games",stat="coding",minimum=22,budget=900,tokens=50},
	{id="north",name="North Logistics",stat="reasoning",minimum=25,budget=1800,tokens=100},
	{id="paper",name="Paper Studio",stat="creativity",minimum=28,budget=1400,tokens=80},
	{id="ledger",name="Ledger Finance",stat="math",minimum=40,budget=4500,tokens=180},
	{id="orbit",name="Orbit Games",stat="coding",minimum=45,budget=5000,tokens=240},
	{id="atlas",name="Atlas Search",stat="knowledge",minimum=48,budget=6000,tokens=300},
	{id="civic",name="Civic Support",stat="reliability",minimum=48,budget=3500,tokens=160},
	{id="delta",name="Delta Robotics",stat="reasoning",minimum=60,budget=12000,tokens=450},
	{id="mosaic",name="Mosaic Worlds",stat="creativity",minimum=65,budget=15000,tokens=700},
	{id="helix",name="Helix Research",stat="math",minimum=80,budget=22000,tokens=900},
	{id="nova",name="Nova Infrastructure",stat="coding",minimum=100,budget=45000,tokens=1800},
	{id="frontier",name="Frontier Science",stat="reasoning",minimum=140,budget=90000,tokens=3000},
}
local leases: {[string]:any} = {}
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
		apiPrice=model.release.apiPrice,market=model.market}
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
	if not Economy.spend(buyer,fee) then return false end
	Economy.applyFlow(provider,fee,0)
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
function Market.tickGlobal(dt: number)
	clock += dt
	local offers = {}
	local sessions = all()
	local capacity: {[number]:number} = {}
	for _, s in sessions do
		s.data.empire.customers = {}
		s.data.empire.businessRevenue = 0
		capacity[s.userId] = ModelMath.fleet(s.data.gpus).throughput*100*require(Shared.Config.HardwareConfig).thermal(s.data.empire,ModelMath.fleet(s.data.gpus).throughput)
		if s.data.training then capacity[s.userId] *= 1-s.data.empire.infrastructure.trainingShare end
		for _, id in s.data.modelOrder do
			local m = s.data.models[id]
			if m and m.status=="live" and m.release and m.market then
				table.insert(offers,{providerId=s.userId,company=s.data.company.name,id=id,name=m.name,
					overall=m.overall,stats=m.stats,sub=m.release.subPrice,api=m.release.apiPrice,
					price=Market.accessPrice(m),users=MarketMath.totalUsers(m.market),iterations=m.iterations or 0})
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
	local customers = {}
	-- Existing leases consume capacity first. New competitors can win when the game month renews.
	for _, business in businesses do
		local lease=leases[business.id]
		local provider=if lease then seller(lease.providerId) else nil
		local model=if provider then provider.data.models[lease.modelId] else nil
		if lease and (clock>=lease.renewAt or not model or model.status~="live"
			or (capacity[lease.providerId] or 0)<business.tokens) then leases[business.id]=nil
		elseif lease then capacity[lease.providerId]-=business.tokens end
	end
	for _, business in businesses do
		local lease = leases[business.id]
		if not lease then
			local winner:any=nil
			local best=-math.huge
			for _, offer in offers do
				local quote=math.floor(offer.sub*10 + offer.api*business.tokens)
				local ability=offer.stats[business.stat] or 0
				local value=ability/(1+quote/business.budget)
				if ability>=business.minimum and quote>0 and quote<=business.budget
					and (capacity[offer.providerId] or 0)>=business.tokens and value>best then
					winner=offer;best=value
				end
			end
			if winner then
				lease={providerId=winner.providerId,modelId=winner.id,
					price=math.floor(winner.sub*10+winner.api*business.tokens),renewAt=clock+GameConfig.GAME_MONTH_SECONDS}
				leases[business.id]=lease
				capacity[winner.providerId]-=business.tokens
			end
		end
		local provider = if lease then seller(lease.providerId) else nil
		local row={id=business.id,name=business.name,stat=business.stat,minimum=business.minimum,
			budget=business.budget,tokens=business.tokens,providerId=if provider then provider.userId else 0,
			provider=if provider then provider.data.company.name else "Seeking provider",
			price=if lease then lease.price else 0,remaining=if lease then math.ceil(lease.renewAt-clock) else 0}
		table.insert(customers,row)
		if provider then
			row.modelId=lease.modelId
			table.insert(provider.data.empire.customers,row)
			provider.data.empire.businessRevenue+=lease.price/GameConfig.GAME_MONTH_SECONDS
		end
	end
	Market.customers=customers
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
	local live=MarketMath.tick(entries,company.reputation,company.spec,dt,rivals,if #NPC.sessions>0 then {} else nil)
	local b=EmpireMath.bonuses(data.empire)
	local cycle=EmpireConfig.cycle(workspace:GetServerTimeNow())
	live.revenue*=b.revenue*cycle.revenue; live.cost*=b.serving*cycle.cost
	for _, r in live.perModel do r.revenue*=b.revenue*cycle.revenue; r.cost*=b.serving*cycle.cost end
	for _, customer in data.empire.customers do
		local m=data.models[customer.modelId]
		if m and m.status=="live" then
			local size=ModelConfig.getSize(m.sizeId)
			local revenue=customer.price/GameConfig.GAME_MONTH_SECONDS
			local cost=customer.tokens*(if size then size.serveCost else 0)*b.serving/GameConfig.GAME_MONTH_SECONDS
			live.revenue+=revenue;live.cost+=cost
			local r=live.perModel[m.id]
			if r then r.revenue+=revenue;r.cost+=cost end
		end
	end
	-- Electricity while serving is distinct from the upfront training electricity budget.
	local fleet=ModelMath.fleet(data.gpus)
	if #entries>0 then live.cost+=fleet.throughput*0.025 end
	live.marketplace={offers=Market.offers,customers=Market.customers}
	session.live=live
	Economy.applyFlow(session,live.revenue*dt,live.cost*dt)
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
