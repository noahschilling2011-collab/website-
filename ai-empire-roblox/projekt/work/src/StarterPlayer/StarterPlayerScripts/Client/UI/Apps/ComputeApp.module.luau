--!strict
-- Compute (user request 23 "the servers really work", CORE_SPEC 3.1 / 3.2 / 5.5): what the GPUs are doing right now
-- (business clients' reserved compute, serving users, free headroom, units off line by rack faults), capacity vs load
-- with the waitlist, the training speed left over, active rack faults with the IT repair countdown, running power and
-- serving costs, the rack with the GPU slots of the office stage, cooling, the studio split and the GPU shop.
-- Every number comes from the replicated state (live.compute / capacity / load / waitlist / ops / perModel) or the
-- shared formulas (CompanyOps.capacity, EmpireMath.trainingRate, HardwareConfig.thermal / slots).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local HardwareConfig = require(Shared.Config.HardwareConfig)
local ModelConfig = require(Shared.Config.ModelConfig)
local MarketConfig = require(Shared.Config.MarketConfig)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local ModelMath = require(Shared.ModelMath)
local EmpireMath = require(Shared.EmpireMath)
local CompanyOps = require(Shared.CompanyOps)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local UI = script.Parent.Parent
local Client = UI.Parent
local StateController = require(Client.Controllers.StateController)
local ActionController = require(Client.Controllers.ActionController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)

local C = Theme.colors
local F = Theme.font

type Snapshot = Types.Snapshot

local TIER_SHADE: { [string]: (Color3) -> Color3 } = {
	consumer = Theme.darker(0.35),
	workstation = function(color: Color3): Color3
		return color
	end,
	accelerator = Theme.lighter(0.55),
}
-- electricity while anything is live: throughput x this $/s (MarketService.tick; HardwareConfig.SERVE_POWER once the
-- econ owner exports it, see design/requests/apps.md)
local SERVE_POWER: number = (HardwareConfig :: any).SERVE_POWER or 0.025
local MAX_SLOTS = 72 -- 48 GPU slots x 1.5 with Distributed Cluster (Global AI HQ)

local ComputeApp = {}

local root: Frame? = nil
local refresh: (Snapshot) -> () = function(_snapshot: Snapshot) end

-- What the fleet does right now, in effective compute units (throughput x thermal, CompanyOps.capacity):
-- clients = reserved for business clients, serving = used by users, free = headroom, offline = rack faults.
export type Split = { total: number, clients: number, serving: number, free: number, offline: number, load: number, capacity: number, waitlist: number }
function ComputeApp.split(data: any, live: any): Split
	local e = data.empire
	local compute = if typeof(live.compute) == "table" then live.compute else {}
	local fleet = ModelMath.fleet(data.gpus)
	local units = tonumber(compute.units) or fleet.throughput
	local lost = math.clamp(tonumber(compute.lost) or 0, 0, units)
	local thermal = HardwareConfig.thermal(e, units)
	local reserved = tonumber(compute.reserved) or (if typeof(e.deals) == "table" then tonumber(e.deals.reserved) else nil) or 0
	local online = (units - lost) * thermal
	local clients = math.min(reserved, online)
	local consumer = math.max(0, online - reserved)
	local capacity = tonumber(live.capacity) or 0
	local load = tonumber(live.load) or 0
	local used = if capacity > 0 then consumer * math.min(1, load / capacity) else 0
	return {
		total = units * thermal, clients = clients, serving = used, free = math.max(0, consumer - used), offline = lost * thermal,
		load = load, capacity = capacity, waitlist = tonumber(live.waitlist) or 0,
	}
end

-- training speed share left by the business clients' reservation (EmpireMath.trainingRate with and without it)
function ComputeApp.trainingShare(data: any): number
	local e = data.empire
	local fleet = ModelMath.fleet(data.gpus)
	if fleet.throughput <= 0 then
		return 1
	end
	local free = table.clone(e)
	local deals: { [string]: any } = if typeof(e.deals) == "table" then table.clone(e.deals) else {}
	deals.reserved = 0
	free.deals = deals
	local full = EmpireMath.trainingRate(data.gpus, 1e18, free)
	return if full > 0 then EmpireMath.trainingRate(data.gpus, 1e18, e) / full else 1
end

-- CompanyOps.capacity counts in 500M-model user equivalents; real users per unit for today's model mix =
-- demand (users) / load (units) from MarketMath (1 when nothing is live yet)
function ComputeApp.usersPerUnit(live: any?): number
	local load = if live then tonumber(live.load) or 0 else 0
	local demand = if live then tonumber(live.demand) or 0 else 0
	return if load > 0 and demand > 0 then demand / load else 1
end
-- extra serving capacity of one more GPU of this kind (CompanyOps.capacity with the GPU added), in real users when
-- `live` is given (else in 500M-model user equivalents)
function ComputeApp.extraUsers(data: any, gpuId: string, live: any?): number
	local gpus = table.clone(data.gpus)
	gpus[gpuId] = (gpus[gpuId] or 0) + 1
	local withGpu = table.clone(data)
	withGpu.gpus = gpus
	return math.max(0, CompanyOps.capacity(withGpu) - CompanyOps.capacity(data)) * ComputeApp.usersPerUnit(live)
end

-- What to do about users waiting for servers (CORE_SPEC 8.2), checked against free rack slots and the cooling cap:
--   buy      a free slot and a GPU adds users: gpu = the GPU that adds the most (among those the company can pay,
--            else the cheapest), extra = capacity it adds (CompanyOps.capacity units; x perUnit = real users)
--   rack     the rack is full: next office (nextSlots), Distributed Cluster (cluster = not researched yet), or swap the
--            weakest GPU for gpu (extra = users gained by the swap; 0 = no swap helps)
--   cooling  the fleet runs hotter than the cooling keeps up with and cooling < 8: upgrade cooling first (cost)
--   maxed    heat-limited at cooling 8/8: more GPUs add nothing here; next office cools nextCools units (nil = none)
export type Advice = {
	kind: string,
	gpu: string?,
	weakest: string?,
	extra: number,
	used: number,
	slots: number,
	cooling: number,
	cost: number,
	cools: number,
	nextOffice: string?,
	nextSlots: number?,
	nextCools: number?,
	cluster: boolean,
	perUnit: number, -- real users per capacity unit for today's model mix (ComputeApp.usersPerUnit)
}
ComputeApp.COOLING_MAX = 8
function ComputeApp.coolingCost(level: number): number
	return math.floor(8000 * 1.7 ^ (level - 1)) -- ComputeService.cooling
end
local function capacityWith(data: any, gpus: { [string]: number }): number
	local copy = table.clone(data)
	copy.gpus = gpus
	return CompanyOps.capacity(copy)
end
function ComputeApp.advice(data: any, cash: number, live: any?): Advice
	local e = data.empire
	local fleet = ModelMath.fleet(data.gpus)
	local slots = HardwareConfig.slots(e)
	local cooling = math.floor(tonumber(e.infrastructure and e.infrastructure.cooling) or 1)
	local stage = CompanyOps.stageIndex(e)
	local nextDef = EmpireConfig.OFFICES[stage + 1]
	local research = if typeof(e.research) == "table" then e.research else {}
	local cools = HardwareConfig.thermal(e, 1e9) * 1e9
	local nextE = if nextDef then table.clone(e) else nil
	if nextE then
		nextE.office = stage + 1
	end
	local a: Advice = {
		kind = "buy", gpu = nil, weakest = nil, extra = 0, used = fleet.slotsUsed, slots = slots, cooling = cooling,
		cost = ComputeApp.coolingCost(cooling), cools = cools, nextOffice = if nextDef then nextDef.name else nil,
		nextSlots = if nextE then HardwareConfig.slots(nextE) else nil,
		nextCools = if nextE then HardwareConfig.thermal(nextE, 1e9) * 1e9 else nil,
		cluster = research.cluster ~= true and EmpireConfig.find(EmpireConfig.RESEARCH, "cluster") ~= nil,
		perUnit = ComputeApp.usersPerUnit(live),
	}
	local base = CompanyOps.capacity(data)
	if HardwareConfig.thermal(e, fleet.throughput) < 1 then
		-- every extra unit only runs hotter: GPUs (new or swapped) add nothing until the cooling budget grows
		a.kind = if cooling < ComputeApp.COOLING_MAX then "cooling" else "maxed"
		return a
	end
	if fleet.slotsUsed < slots then
		local cheapest = math.huge
		for _, gpu in HardwareConfig.GPUS do
			if not gpu.starter then cheapest = math.min(cheapest, gpu.price) end
		end
		for _, gpu in HardwareConfig.GPUS do
			if not gpu.starter and gpu.price <= math.max(cash, cheapest) then
				local gpus = table.clone(data.gpus)
				gpus[gpu.id] = (gpus[gpu.id] or 0) + 1
				local extra = math.max(0, capacityWith(data, gpus) - base)
				if extra > a.extra then
					a.extra = extra
					a.gpu = gpu.id
				end
			end
		end
		return a
	end
	-- rack full: what a swap of the weakest GPU for a stronger one gains (sold at SELL_REFUND, the new one bought)
	a.kind = "rack"
	local weakest = nil
	for _, gpu in HardwareConfig.GPUS do
		if not gpu.starter and (data.gpus[gpu.id] or 0) > 0 and (weakest == nil or gpu.throughput < weakest.throughput) then
			weakest = gpu
		end
	end
	if weakest then
		a.weakest = weakest.id
		local budget = cash + weakest.price * HardwareConfig.SELL_REFUND
		local cheapest = math.huge
		for _, gpu in HardwareConfig.GPUS do
			if not gpu.starter and gpu.throughput > weakest.throughput then cheapest = math.min(cheapest, gpu.price) end
		end
		for _, gpu in HardwareConfig.GPUS do
			if not gpu.starter and gpu.throughput > weakest.throughput and gpu.price <= math.max(budget, cheapest) then
				local gpus: { [string]: number } = table.clone(data.gpus)
				gpus[weakest.id] -= 1
				gpus[gpu.id] = (gpus[gpu.id] or 0) + 1
				local extra = math.max(0, capacityWith(data, gpus) - base)
				if extra > a.extra then
					a.extra = extra
					a.gpu = gpu.id
				end
			end
		end
	end
	return a
end

-- "an AI Accelerator" / "a Workstation GPU" / "an HBM Datacenter GPU" (HBM is read "aitch-bee-em")
local function article(label: string): string
	local vowel = string.find("AEIOU", string.sub(label, 1, 1), 1, true) ~= nil or string.sub(label, 1, 3) == "HBM"
	return (if vowel then "an " else "a ") .. label
end
ComputeApp.article = article

-- The sentence after "<n> users waiting —" for an Advice (HUD-free: also the Hardware app's waitlist line)
function ComputeApp.adviceText(a: Advice): string
	local function label(id: string?): string
		local def = if id then HardwareConfig.getGPU(id) else nil
		return if def then def.label else tostring(id)
	end
	if a.kind == "cooling" then
		return string.format("cooling is the limit: upgrade cooling first (level %d / %d, %s). More GPUs would only run hotter.", a.cooling, ComputeApp.COOLING_MAX, Format.money(a.cost))
	elseif a.kind == "maxed" then
		if a.nextOffice and a.nextCools then
			return string.format("cooling is maxed (%d / %d): more GPUs add no capacity here. Move to the %s (cools %s units instead of %s) or raise prices.",
				a.cooling, ComputeApp.COOLING_MAX, a.nextOffice, Format.int(a.nextCools), Format.int(a.cools))
		end
		return string.format("cooling is maxed (%d / %d) in your largest office: more GPUs add no capacity. Raise prices so demand fits your servers.", a.cooling, ComputeApp.COOLING_MAX)
	elseif a.kind == "rack" then
		local options = {}
		if a.nextOffice and a.nextSlots then table.insert(options, string.format("move to the %s (%d slots)", a.nextOffice, a.nextSlots)) end
		if a.cluster then table.insert(options, "research Distributed Cluster (×1.5 slots)") end
		if a.gpu and a.weakest and a.extra >= 1 then table.insert(options, string.format("swap %s for %s (+%s users)", article(label(a.weakest)), article(label(a.gpu)), Format.int(a.extra * a.perUnit))) end
		if #options == 0 then
			return string.format("rack full (%d / %d) in your largest office: raise prices so demand fits your servers.", a.used, a.slots)
		end
		local list = if #options == 1 then options[1] else table.concat(options, ", ", 1, #options - 1) .. " or " .. options[#options]
		return string.format("rack full (%d / %d): %s.", a.used, a.slots, list)
	end
	if a.gpu and a.extra >= 1 then
		return string.format("buy GPUs: one more %s serves %s more users.", label(a.gpu), Format.int(a.extra * a.perUnit))
	end
	return "business clients reserve your compute right now: buy GPUs to serve more users."
end

local function gpuLabel(id: string): string
	local def = HardwareConfig.getGPU(id)
	return if def then def.label else id
end

local function stageList(): string
	local parts = {}
	for i, slots in HardwareConfig.STAGE_SLOTS do
		table.insert(parts, string.format("%s %d", string.gsub(EmpireConfig.OFFICES[i].name, "Headquarters", "HQ"), slots))
	end
	return table.concat(parts, " · ")
end

function ComputeApp.mount(parent: Frame, navigation: Kit.Nav)
	root = parent

	local scroll = Kit.scroll(parent)
	scroll.Name = "ComputeScroll"
	Kit.padding(scroll, 2, 14, 20, 2)
	Kit.list(scroll, 14)

	Kit.heading(scroll, "COMPUTE", "Your GPUs serve your users, carry the compute your business clients reserve and train your models. More throughput = more users and faster training, more VRAM = bigger models.", 1)

	-- Servers: what the fleet does right now
	local servers = Kit.card(scroll, 2, 10)
	servers.Name = "Servers"
	local serverHead = Kit.frame(servers, UDim2.new(1, 0, 0, 26))
	serverHead.LayoutOrder = 1
	local serverTitle = Kit.text(serverHead, "Servers", 20, F.bold, C.text)
	serverTitle.Name = "Load"
	local serverTag = Kit.tag(serverHead, "OK", C.good)
	serverTag.AnchorPoint = Vector2.new(1, 0.5)
	serverTag.Position = UDim2.fromScale(1, 0.5)
	local serverText = Kit.para(servers, "", 14, C.muted, 2)
	local waitText = Kit.para(servers, "", 15, C.warn, 3)
	waitText.Name = "Waitlist"
	waitText.Font = F.bold
	local splitBar = Kit.splitBar(servers, 16, 4)
	splitBar.frame.Name = "Split"
	local legend = Kit.frame(servers, UDim2.new(1, 0, 0, 18))
	legend.LayoutOrder = 5
	Kit.list(legend, 16, true)
	local colors = {
		clients = C.warn,
		serving = Theme.accent,
		free = C.raised:Lerp(C.white, 0.18),
		offline = C.bad,
	}
	local _, lClients = Kit.legend(legend, colors.clients, "", 1)
	local _, lServing = Kit.legend(legend, colors.serving, "", 2)
	local _, lFree = Kit.legend(legend, colors.free, "", 3)
	local offlineChip, lOffline = Kit.legend(legend, colors.offline, "", 4)
	-- who uses the compute (LOGIC_BRIEF 23a): business clients' reservation and each live model's share of serving
	local usageCaption = Kit.caption(servers, "Who uses it", 6)
	local usage = Kit.stack(servers, 2, 7)
	usage.Name = "Usage"
	type UsageRow = { frame: Frame, name: TextLabel, users: TextLabel, share: TextLabel }
	local usageRows: { UsageRow } = {}
	local function usageRow(i: number): UsageRow
		local existing = usageRows[i]
		if existing then
			return existing
		end
		local row = Kit.frame(usage, UDim2.new(1, 0, 0, 20))
		row.Name = "Use" .. i
		row.LayoutOrder = i
		local name = Kit.cell(row, "", UDim.new(0.46, 0), 14, F.medium, C.text)
		local users = Kit.cell(row, "", UDim.new(0.26, 0), 13, F.regular, C.muted)
		users.Position = UDim2.fromScale(0.46, 0)
		local share = Kit.cell(row, "", UDim.new(0.28, 0), 13, F.bold, C.muted)
		share.Position = UDim2.fromScale(0.72, 0)
		share.TextXAlignment = Enum.TextXAlignment.Right
		local made: UsageRow = { frame = row, name = name, users = users, share = share }
		usageRows[i] = made
		return made
	end
	local trainText = Kit.para(servers, "", 14, C.muted, 8)
	trainText.Name = "Training"
	Kit.divider(servers, 9)
	Kit.caption(servers, "Rack faults", 10)
	local faultRows = Kit.stack(servers, 4, 11)
	faultRows.Name = "Faults"
	local faultNote = Kit.para(servers, "", 13, C.dim, 12)
	Kit.divider(servers, 13)
	Kit.caption(servers, "Running costs per game day", 14)
	local costText = Kit.para(servers, "", 14, C.muted, 15)
	costText.Name = "Costs"

	-- Rack: fleet and GPU slots of the office stage
	local fleetCard = Kit.card(scroll, 3, 12)
	local metrics = Kit.grid(fleetCard, 4, 48, 10, 1)
	local mThroughput = Kit.metric(metrics, "Throughput", 1, 20)
	local mTflops = Kit.metric(metrics, "Peak", 2, 20)
	local mVram = Kit.metric(metrics, "VRAM", 3, 20)
	local mPower = Kit.metric(metrics, "Power cost", 4, 20)
	local rackHead = Kit.frame(fleetCard, UDim2.new(1, 0, 0, 18))
	rackHead.LayoutOrder = 2
	Kit.caption(rackHead, "Server rack")
	local rackText = Kit.text(rackHead, "", 13, F.bold, C.muted)
	rackText.AnchorPoint = Vector2.new(1, 0)
	rackText.Position = UDim2.fromScale(1, 0)
	local rack = Kit.frame(fleetCard, UDim2.fromScale(1, 0))
	rack.Name = "Rack"
	rack.AutomaticSize = Enum.AutomaticSize.Y
	rack.LayoutOrder = 3
	local rackGrid = Instance.new("UIGridLayout")
	rackGrid.CellPadding = UDim2.fromOffset(6, 6)
	rackGrid.SortOrder = Enum.SortOrder.LayoutOrder
	rackGrid.Parent = rack
	local slots: { { frame: Frame, label: TextLabel } } = {}
	for i = 1, MAX_SLOTS do
		local slot = Kit.frame(rack)
		slot.Name = "Slot" .. i
		slot.LayoutOrder = i
		slot.BackgroundTransparency = 0
		slot.BackgroundColor3 = C.raised
		Kit.corner(slot, 5)
		local label = Kit.text(slot, "", 11, F.bold, C.bg)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		slots[i] = { frame = slot, label = label }
	end
	local stageText = Kit.para(fleetCard, "GPU slots per office: " .. stageList() .. " (×1.5 with Distributed Cluster).", 13, C.dim, 4)
	stageText.Name = "StageSlots"
	local speedText = Kit.para(fleetCard, "", 14, C.muted, 5)

	local operations = Kit.card(scroll, 4, 10)
	Kit.caption(operations, "Compute operations", 1)
	local thermal = Kit.para(operations, "", 13, C.muted, 2)
	local cooling = Kit.button(operations, "UPGRADE COOLING", "secondary", UDim2.new(1, 0, 0, Kit.tap(34, 96)))
	cooling.LayoutOrder = 3
	Kit.onClick(cooling, function()
		ActionController.call("UpgradeCooling", {})
	end)
	Kit.caption(operations, "GPU split while a studio project builds", 4)
	local shares = Kit.segmented(operations, { { id = "0.35", label = "35% training" }, { id = "0.5", label = "50%" }, { id = "0.7", label = "70%" }, { id = "0.9", label = "90%" } }, "0.7", function(id)
		ActionController.call("SetComputeShare", { share = tonumber(id) })
	end, Kit.tap(38, 96))
	shares.frame.LayoutOrder = 5
	Kit.para(operations, "More training compute leaves less capacity for studio projects. Business clients reserve their own compute. Better cooling prevents large clusters from slowing down.", 13, C.dim, 6)

	-- Shop
	Kit.caption(scroll, "Hardware", 5)
	local list = Kit.stack(scroll, 10, 6)
	list.Name = "Shop"
	local rowRefs: { [string]: { owned: TextLabel, buy: TextButton?, sell: TextButton? } } = {}
	for index, gpu in HardwareConfig.GPUS do
		local row = Kit.frame(list, UDim2.new(1, 0, 0, Kit.tap(96, 124)))
		row.Name = "GPU_" .. gpu.id
		row.LayoutOrder = index
		row.BackgroundTransparency = 0.05
		row.BackgroundColor3 = C.panel2
		Kit.corner(row, 12)
		Kit.stroke(row, 0.92)
		Kit.padding(row, 12, 14, 12, 16)

		local nameRow = Kit.frame(row, UDim2.new(1, -Kit.tap(260, 300), 0, 24))
		Kit.list(nameRow, 8, true)
		local name = Kit.text(nameRow, gpu.label, 18, F.bold, C.text)
		name.LayoutOrder = 1
		Kit.tag(nameRow, gpu.tier, if gpu.starter then C.dim else C.muted, 2)
		local stats = Kit.text(
			row,
			`{gpu.throughput} units/s · {gpu.vram} GB VRAM · ${gpu.powerCost} power per unit`,
			14,
			F.medium,
			C.muted
		)
		stats.Position = UDim2.fromOffset(0, 30)
		local owned = Kit.text(row, "", 14, F.bold, C.text)
		owned.Name = "Owned"
		owned.Position = UDim2.fromOffset(0, 52)

		local refs: { owned: TextLabel, buy: TextButton?, sell: TextButton? } = { owned = owned, buy = nil, sell = nil }
		if gpu.starter then
			local included = Kit.text(row, "Included", 15, F.medium, C.dim)
			included.AnchorPoint = Vector2.new(1, 0.5)
			included.Position = UDim2.fromScale(1, 0.5)
		else
			local buy = Kit.button(row, `BUY {Format.money(gpu.price)}`, "primary", UDim2.fromOffset(Kit.tap(150, 170), Kit.tap(38, 96)))
			buy.Name = "Buy"
			buy.AnchorPoint = Vector2.new(1, 0.5)
			buy.Position = UDim2.new(1, -Kit.tap(96, 116), 0.5, 0)
			buy.TextSize = 14
			local sell = Kit.button(row, "SELL", "ghost", UDim2.fromOffset(Kit.tap(86, 104), Kit.tap(38, 96)))
			sell.Name = "Sell"
			sell.AnchorPoint = Vector2.new(1, 0.5)
			sell.Position = UDim2.fromScale(1, 0.5)
			sell.TextSize = 14
			Kit.onClick(buy, function()
				local ok = ActionController.call("BuyGPU", { gpuId = gpu.id })
				if ok then
					Toast.show("success", `{gpu.label} installed in your rack.`)
				end
			end)
			Kit.onClick(sell, function()
				local refund = math.floor(gpu.price * HardwareConfig.SELL_REFUND)
				local ok = ActionController.call("SellGPU", { gpuId = gpu.id })
				if ok then
					Toast.show("info", `Sold {gpu.label} for {Format.money(refund)}.`)
				end
			end)
			refs.buy = buy
			refs.sell = sell
		end
		rowRefs[gpu.id] = refs
	end
	Kit.para(scroll, `Selling refunds {Format.percent(HardwareConfig.SELL_REFUND)} and is locked while a model trains.`, 13, C.dim, 7)

	refresh = function(snapshot: Snapshot)
		local data: any = snapshot.data
		local live: any = snapshot.live
		local e = data.empire
		local fleet = ModelMath.fleet(data.gpus)
		local compute = if typeof(live.compute) == "table" then live.compute else {}
		local ops = if typeof(live.ops) == "table" then live.ops else {}
		local anyLive = false
		for _, id in data.modelOrder do
			local m = data.models[id]
			if m and m.status == "live" then
				anyLive = true
				break
			end
		end

		-- servers: load, waitlist, split
		local sp = ComputeApp.split(data, live)
		local full = if sp.capacity > 0 then sp.load / sp.capacity else 0
		local limit = HardwareConfig.thermal(e, fleet.throughput)
		if not anyLive then
			serverTitle.Text = "Servers idle"
			serverText.Text = "No model is live yet. Release one in Models and users start using your GPUs."
			serverTag.Text = "IDLE"
			serverTag.TextColor3 = C.dim
		else
			serverTitle.Text = if full > 1 then string.format("Servers full · demand %d %%", math.floor(full * 100 + 0.5)) else string.format("Servers %d %% full", math.floor(full * 100 + 0.5))
			-- capacity in real users for today's model mix: capacity units x demand users / load units (MarketMath)
			local demand = tonumber(live.demand) or 0
			local room = if sp.load > 0 and demand > 0 then sp.capacity * demand / sp.load else 0
			local roomText = if room > 0
				then string.format("%s users online · demand %s · room for %s users with your current models (bigger models need more compute per user).",
					Format.compact(live.users or 0), Format.compact(demand), Format.compact(room))
				else string.format("%s users online.", Format.compact(live.users or 0))
			serverText.Text = roomText .. (if limit < 1 then string.format(" Cooling holds the fleet at %.0f of its %.0f units.", fleet.throughput * limit, fleet.throughput) else "")
			local over = full > 1
			serverTag.Text = if over then "OVER CAPACITY" elseif full > 0.85 then "NEARLY FULL" else "OK"
			serverTag.TextColor3 = if over then C.bad elseif full > 0.85 then C.warn else C.good
		end
		-- the waitlist and what really helps: a GPU only while a slot is free and the cooling keeps up
		waitText.Visible = sp.waitlist > 0
		if sp.waitlist > 0 then
			local advice = ComputeApp.advice(data, StateController.money(), live)
			waitText.Text = string.format("%s users waiting — %s", Format.int(sp.waitlist), ComputeApp.adviceText(advice))
			waitText:SetAttribute("Advice", advice.kind)
		end
		splitBar.set({
			{ value = sp.clients, color = colors.clients },
			{ value = sp.serving, color = colors.serving },
			{ value = sp.free, color = colors.free },
			{ value = sp.offline, color = colors.offline },
		}, sp.total)
		local function u(n: number): string
			return string.format("%.1f u", n)
		end
		lClients.Text = "Business clients " .. u(sp.clients)
		lServing.Text = "Users " .. u(sp.serving)
		lFree.Text = "Free " .. u(sp.free)
		lOffline.Text = "Rack faults " .. u(sp.offline)
		offlineChip.Visible = sp.offline > 0
		-- who uses it: the reservation, then each live model's share of the serving load (users x SERVE_UNITS)
		local accounts = 0
		if typeof(e.deals) == "table" and typeof(e.deals.accounts) == "table" then
			for _ in e.deals.accounts do accounts += 1 end
		end
		type Use = { name: string, users: string, share: string, color: Color3 }
		local uses: { Use } = {}
		if sp.clients > 0 or accounts > 0 then
			table.insert(uses, { name = string.format("Business clients · %d account%s", accounts, if accounts == 1 then "" else "s"), users = "reserved", share = u(sp.clients), color = C.warn })
		end
		local perModel = if typeof(live.perModel) == "table" then live.perModel else {}
		local loads: { { m: any, users: number, load: number } } = {}
		local totalLoad = 0
		for _, id in data.modelOrder do
			local m = data.models[id]
			local r = perModel[id]
			if m and m.status == "live" and typeof(r) == "table" then
				local users = tonumber(r.users) or 0
				local load = users * (((MarketConfig :: any).SERVE_UNITS or {})[m.sizeId] or 1)
				totalLoad += load
				table.insert(loads, { m = m, users = users, load = load })
			end
		end
		table.sort(loads, function(a, b)
			return a.load > b.load
		end)
		for _, l in loads do
			local share = if totalLoad > 0 then l.load / totalLoad else 0
			local size = ModelConfig.getSize(tostring(l.m.sizeId))
			table.insert(uses, {
				name = string.format("%s v%d%s", tostring(l.m.name), tonumber(l.m.version) or 1, if size then " · " .. size.label else ""),
				users = Format.compact(l.users) .. " users",
				share = string.format("%d %% · %s", math.floor(share * 100 + 0.5), u(sp.serving * share)),
				color = C.text,
			})
		end
		usageCaption.Visible = #uses > 0
		for i, use in uses do
			local r = usageRow(i)
			r.frame.Visible = true
			r.name.Text = use.name
			r.name.TextColor3 = use.color
			r.users.Text = use.users
			r.share.Text = use.share
		end
		for i = #uses + 1, #usageRows do
			usageRows[i].frame.Visible = false
		end
		-- training: EmpireMath.trainingRate (the speed share); the reserved units are the same effective units as the
		-- split bar above (its yellow part), never the GPUs' raw throughput
		local share = ComputeApp.trainingShare(data)
		local reserved = tonumber(compute.reserved) or 0
		trainText.Text = if reserved > 0
			then string.format("Training runs at %d %% speed while business clients reserve %s (the yellow part above). Training never drops below 30 %%.",
				math.floor(share * 100 + 0.5), u(sp.clients))
			else "Training runs at full speed: no compute is reserved for business clients."

		-- faults (live.compute.faults: slot = blade order, best GPU first; repair FAULT.it s with IT on duty)
		local faults = if typeof(compute.faults) == "table" then compute.faults else {}
		local it = compute.it == true
		local F_ = CompanyOps.FAULT
		local texts: { string } = {}
		for _, f in faults do
			-- the server keeps the exact repair progress; the client counts down from the fault's start (approximate)
			local elapsed = math.max(0, (tonumber(e.seconds) or 0) - (tonumber(f.since) or 0))
			local left = if typeof(f.eta) == "number" then math.max(0, f.eta) else math.max(0, (if it then F_.it else F_.alone) - elapsed)
			local eta = if left <= 0 then "almost fixed" elseif left < 90 then string.format("~%d s", math.ceil(left)) else string.format("~%d min", math.ceil(left / 60))
			table.insert(texts, string.format("Rack R%d fault · %s · %s · %s", tonumber(f.slot) or 0, gpuLabel(tostring(f.gpu)), if it then "IT on the way" else "no IT on duty", eta))
		end
		if #texts == 0 then
			table.insert(texts, "No faults. Every rack runs normally.")
		end
		local labels = {}
		for _, child in faultRows:GetChildren() do
			if child:IsA("TextLabel") then table.insert(labels, child) end
		end
		for i, text in texts do
			local line = labels[i] or Kit.para(faultRows, "", 14, C.bad, i)
			line.Name = "Fault" .. i
			line.LayoutOrder = i
			line.Font = F.medium
			line.Text = text
			line.TextColor3 = if #faults == 0 then C.good else C.bad
		end
		for i = #texts + 1, #labels do
			labels[i]:Destroy()
		end
		faultNote.Text = string.format("A fault takes %d compute unit off line until it is fixed: about %d s while IT is on duty, %d min without (%s). A staffed hardware lab halves the fault rate.",
			F_.units, F_.it, math.floor(F_.alone / 60), if CompanyOps.stageIndex(e) < 2 then "the garage has no IT desk" elseif CompanyOps.stageIndex(e) >= 5 then "IT is also on call at night" else "IT works 08:00–18:00")

		-- running costs: power while serving, serving per model, client serving (live.ops $/min)
		local power = if anyLive then fleet.throughput * SERVE_POWER * CompanyOps.DAY else 0
		local serving = 0
		if typeof(live.perModel) == "table" then
			for _, r in live.perModel do
				serving += (tonumber(r.cost) or 0) * CompanyOps.DAY
			end
		end
		local b2bServe = (tonumber(ops.b2bserveCost) or 0) * CompanyOps.DAY / 60
		costText.Text = string.format("Power while serving %s · serving users %s · serving business clients %s · cooling has no running cost (one-off upgrades below).",
			CompanyOps.money(power), CompanyOps.money(serving), CompanyOps.money(b2bServe))

		-- rack
		local infrastructure = e.infrastructure
		local budget = HardwareConfig.thermal(e, 1e9) * 1e9 -- compute units the cooling keeps at full speed
		thermal.Text = "Cooling level " .. tostring(infrastructure.cooling) .. " / 8 · " .. Format.percent(HardwareConfig.thermal(e, fleet.throughput)) .. " sustained GPU performance · cools up to " .. string.format("%.0f", budget) .. " compute units"
		local coolingCost = ComputeApp.coolingCost(infrastructure.cooling)
		local maxed = infrastructure.cooling >= ComputeApp.COOLING_MAX
		cooling.Text = if maxed then "COOLING AT MAXIMUM (8 / 8)" else "UPGRADE COOLING · " .. Format.money(coolingCost)
		Kit.setDisabled(cooling, maxed or data.money < coolingCost)
		shares.set(tostring(infrastructure.trainingShare))
		mThroughput.value.Text = `{fleet.throughput} u/s`
		mTflops.value.Text = `{Format.compact(fleet.throughput * HardwareConfig.TFLOPS_PER_UNIT, 0)} TFLOPS`
		mVram.value.Text = `{fleet.vram} GB`
		mPower.value.Text = `${string.format("%.1f", fleet.costPerWork)}/unit`

		local slotCount = math.min(MAX_SLOTS, HardwareConfig.slots(e))
		local cols = math.min(12, slotCount)
		local cellH = if slotCount > 24 then 24 else 32
		rackGrid.CellSize = UDim2.new(1 / cols, -6 * (cols - 1) / cols, 0, cellH)
		local broken: { [number]: boolean } = {}
		for _, f in faults do
			broken[tonumber(f.slot) or 0] = true
		end
		-- fill the rack from strong to weak GPUs (like the blades in the data hall: CompanyOps.rack order)
		local filled = 0
		for _, r in CompanyOps.rack(data.gpus) do
			filled += 1
			local slot = slots[filled]
			if slot then
				local def = HardwareConfig.getGPU(r.gpu)
				local shade = TIER_SHADE[r.gpu]
				slot.frame.BackgroundColor3 = if broken[r.slot] then C.bad elseif shade then shade(Theme.accent) else Theme.accent
				slot.label.Text = if broken[r.slot] then "!" elseif def then "T" .. string.sub(def.tier, -1) else ""
			end
		end
		for i = 1, MAX_SLOTS do
			slots[i].frame.Visible = i <= slotCount
			if i > filled then
				slots[i].frame.BackgroundColor3 = C.raised
				slots[i].label.Text = ""
			end
		end
		rackText.Text = `{fleet.slotsUsed}/{HardwareConfig.slots(e)} slots used · {#faults} fault{if #faults == 1 then "" else "s"}`

		local parts: { string } = {}
		for _, size in ModelConfig.SIZES do
			if size.id == "s7b" and not e.research.frontier then
				table.insert(parts, "7B: research required")
			elseif fleet.vram < size.vram then
				table.insert(parts, `{size.label}: needs {size.vram} GB`)
			else
				local plan = ModelMath.plan(size, fleet, { total = math.huge, quality = 0, shares = {} })
				local rate = EmpireMath.trainingRate(data.gpus, plan.work, e)
				table.insert(parts, `{size.label}: {Kit.countdown(if rate > 0 then plan.work / rate else 0)}`)
			end
		end
		speedText.Text = "Training time: " .. table.concat(parts, " · ")

		local money = StateController.money()
		local rackFull = fleet.slotsUsed >= HardwareConfig.slots(e)
		local training = data.training ~= nil
		for _, gpu in HardwareConfig.GPUS do
			local refs = rowRefs[gpu.id]
			if refs then
				local count = data.gpus[gpu.id] or 0
				local extra = if gpu.starter or rackFull then 0 else ComputeApp.extraUsers(data, gpu.id, live)
				refs.owned.Text = if gpu.starter then `Owned: {count}`
					elseif rackFull then `Owned: {count} · no free rack slot`
					elseif extra < 1 and HardwareConfig.thermal(e, fleet.throughput) < 1 then `Owned: {count} · one more adds no capacity (cooling)`
					else `Owned: {count} · one more serves +{Format.compact(extra)} users`
				local buy, sell = refs.buy, refs.sell
				if buy then
					Kit.setDisabled(buy, rackFull or money < gpu.price)
					buy.Text = if rackFull then "RACK FULL" else `BUY {Format.money(gpu.price)}`
				end
				if sell then
					Kit.setDisabled(sell, count <= 0 or training)
				end
			end
		end
	end

	StateController.onChange(function(snapshot: Snapshot)
		if parent.Visible and navigation.isOpen() then
			refresh(snapshot)
		end
	end)
	Theme.onAccent(function()
		local snapshot = StateController.snapshot
		if snapshot and parent.Visible then
			refresh(snapshot)
		end
	end)
end

function ComputeApp.onShow()
	local snapshot = StateController.snapshot
	if snapshot and root then
		refresh(snapshot)
	end
end

return ComputeApp
