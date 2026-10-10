--!strict
-- Phase 2: all prices and rewards are authoritative on the server.
local Config = {}
-- Office stages (CORE_SPEC 2.1). Stage = office index; the building (plan tier) is stage - 1
-- (BuildingPlan.tierForOffice). 1 = the Garage Lab (new), 2..5 = the HQ buildings of plan tiers 1..4.
-- Leaving the garage also needs the first signed business client (EmpireService.upgrade, "FIRST_CLIENT").
Config.OFFICES = {
	{ name = "Garage Lab", price = 0, staff = 5, points = 0.1, color = {120,154,129} },
	{ name = "Founder Headquarters", price = 27000, staff = 24, points = 0.15, color = {120,154,129} },
	{ name = "Startup Campus", price = 100000, staff = 64, points = 0.3, color = {158,136,106} },
	{ name = "Innovation Campus", price = 380000, staff = 128, points = 0.6, color = {112,143,130} },
	{ name = "Global AI Headquarters", price = 1900000, staff = 240, points = 1, color = {169,149,111} },
}
-- Hired roles. price = flat agency fee (about a third of a day's wage); wage = $ per second (x the
-- profile multiplier w), i.e. per game day (1200 s): researcher 3,600, engineer 4,320, curator 2,700,
-- Growth & Sales 4,320. Wages accrue every second, day and night, incl. paid vacation and sick days.
Config.ROLES = {
	{ id = "researcher", name = "AI Researcher", price = 1000, wage = 3, desc = "+0.6 research points/s per employee. Also stronger future models and Lab levels." },
	{ id = "engineer", name = "ML Engineer", price = 1200, wage = 3.6, desc = "+15% training speed per employee. Also more serving capacity and cheaper serving." },
	{ id = "curator", name = "Data Curator", price = 800, wage = 2.25, desc = "+300k curated tokens/s per employee. Improves with research." },
	{ id = "marketer", name = "Growth & Sales", price = 1200, wage = 3.6, desc = "+1.2% market reach per employee. In the office they lift revenue; field reps with a company car win business clients." },
}
Config.RESEARCH = {
	{ id = "pipeline", name = "Parallel Training", cost = 4000, points = 50, seconds = 35, prereq = nil, desc = "+20% training speed." },
	{ id = "cleaning", name = "Data Cleaning", cost = 6000, points = 75, seconds = 45, prereq = nil, desc = "Curator data quality rises from 65% to 85%." },
	{ id = "architecture", name = "Transformer V2", cost = 12000, points = 140, seconds = 65, prereq = "pipeline", desc = "+4 to every core stat of future models." },
	{ id = "quantization", name = "Smart Quantization", cost = 15000, points = 180, seconds = 75, prereq = "pipeline", desc = "Serving costs -15%." },
	{ id = "alignment", name = "Reliability Lab", cost = 18000, points = 200, seconds = 90, prereq = "cleaning", desc = "+8 reliability on future models." },
	{ id = "distribution", name = "Global Distribution", cost = 28000, points = 260, seconds = 90, prereq = "architecture", desc = "+15% market revenue." },
	{ id = "frontier", name = "Frontier Architecture", cost = 65000, points = 500, seconds = 120, prereq = "architecture", desc = "+6 additional core stats; unlocks 7B training." },
	{ id = "cluster", name = "Distributed Cluster", cost = 45000, points = 360, seconds = 110, prereq = "quantization", desc = "+35% additional training speed; 50% more GPU rack slots." },
} :: { any }
-- The old once-per-day contract clicks are gone: their clients are in the B2B catalogue
-- (CompanyOps.CLIENTS) and pay a pilot fee on signing (CORE_SPEC 3.3).
Config.CONTRACTS = {} :: { any }
Config.QUESTS = {
	{ id = "founder", name = "Open the doors", desc = "Found your company.", kind = "company", target = 1, reward = 1200, xp = 50 },
	{ id = "data", name = "Feed the model", desc = "Collect 1B training tokens.", kind = "tokens", target = 1e9, reward = 1800, xp = 70 },
	{ id = "gpu", name = "Upgrade the rig", desc = "Own a non-starter GPU.", kind = "gpus", target = 1, reward = 1500, xp = 70 },
	{ id = "train", name = "First run", desc = "Complete your first training.", kind = "modelsTrained", target = 1, reward = 2500, xp = 100 },
	{ id = "release", name = "Launch day", desc = "Release your first AI model.", kind = "modelsReleased", target = 1, reward = 3000, xp = 120 },
	{ id = "team", name = "Two pairs of hands", desc = "Hire two employees.", kind = "staff", target = 2, reward = 2500, xp = 100 },
	{ id = "research", name = "Lab breakthrough", desc = "Finish one research project.", kind = "research", target = 1, reward = 3000, xp = 130 },
	{ id = "client", name = "Reliable supplier", desc = "Sign three business clients.", kind = "contractsCompleted", target = 3, reward = 6500, xp = 180 },
	{ id = "office", name = "Out of the garage", desc = "Move from the garage into your first HQ.", kind = "office", target = 2, reward = 5000, xp = 150 },
	{ id = "users", name = "Word gets around", desc = "Reach 5,000 peak users.", kind = "peakUsers", target = 5000, reward = 10000, xp = 250 },
	{ id = "quality", name = "A better model", desc = "Train a model with 65 overall.", kind = "bestOverall", target = 65, reward = 15000, xp = 300 },
	{ id = "million", name = "Seven figures", desc = "Earn 1M in market revenue.", kind = "totalRevenue", target = 1e6, reward = 25000, xp = 500 },
}
Config.CYCLES = {
	{ name = "Stable Market", desc = "Customers are buying at normal rates.", revenue = 1, cost = 1 },
	{ name = "AI Investment Wave", desc = "Demand for AI services is rising. Revenue +20%.", revenue = 1.2, cost = 1 },
	{ name = "Energy Squeeze", desc = "Serving energy costs +15%. Efficient labs have an edge.", revenue = 1, cost = 1.15 },
	{ name = "Enterprise Rush", desc = "Companies are adopting AI. Revenue +12%.", revenue = 1.12, cost = 1 },
}
function Config.find(list: any, id: any): any
	if typeof(id) ~= "string" then return nil end
	for _, def in list do if def.id == id then return def end end
	return nil
end
function Config.cycle(time: number): (any, number)
	local index = math.floor(time / 300) % #Config.CYCLES + 1
	return Config.CYCLES[index], 300 - time % 300
end
return Config
